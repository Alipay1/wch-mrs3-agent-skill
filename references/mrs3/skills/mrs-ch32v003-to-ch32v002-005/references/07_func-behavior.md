# 07 同名同签名、实现已变（编译器零提示项）

生成方式：对两侧 `Peripheral/src/*.c` 逐函数抽取函数体、归一化空白后逐一比对
（脚本 `scripts/` 内同源，见 7.4）。**这是本次迁移最需要人工介入的一类**——
名字对、签名对、编译通过，只有上机才暴露。

比对结果分三类，处理方式完全不同：

| 类 | 含义 | 处理 |
|---|---|---|
| 🔴 真语义变化 | 同一输入产生不同效果 | 必须改逻辑 |
| 🟡 超集扩展 | 目标侧多出对新增外设（TIM3/GPIOB/USART2…）的分支，原分支不变 | 不用改 |
| ❌ 纯格式差异 | 仅空白/注释不同 | 不用改（避免误报为 bug） |

---

## 7.1 🔴 真语义变化（必须处理）

### (1) FLASH 页粒度组 —— 见 `05_flash.md`

| 函数 | 差异 |
|---|---|
| `FLASH_ErasePage` | 目标侧多一句 `FLASH->CTLR &= (CR_OPTER_Reset & CR_PAGE_ER_Reset);`；**核心是页大小 64B→256B** |
| `FLASH_ErasePage_Fast` | 同上，页粒度 64B→256B |
| `FLASH_ProgramPage_Fast` | 同上 |
| `FLASH_BufLoad` / `FLASH_BufReset` | 页缓冲大小 64B→256B |
| `FLASH_ROM_ERASE` / `FLASH_ROM_WRITE` | 地址对齐要求 `%64`→`%256`，内部按页循环次数变 |

> 这四个函数**同名同签名**，是本次迁移里最危险的一组。用户按 64B 步长循环擦写会在目标侧连带擦掉相邻数据。

### (2) FLASH 写保护组

`FLASH_EnableWriteProtection`：

| | V003 | 目标侧 |
|---|---|---|
| 局部变量 | `WRP0_Data` / `WRP1_Data`（2×`uint16_t`） | `WRP0..WRP3_Data`（4×`uint8_t`） |
| 掩码 | `WRP0_Mask` `WRP1_Mask` | `WRP0..WRP3_Mask` |
| 写选项字节方式 | 逐字节写 `OB->WRPR0/1` + `CR_OPTPG` | 组装 `buf[4]` 后调 `FLASH_OptionBytePR(buf)` |
| 读保护检查 | 无 | 开头增加 `if((FLASH->OBR & RDPRT_Mask) != RESET) status = FLASH_RDP;` |

**16 页/组 → 8 页/组**。传进去的 `FLASH_Pages` 位含义变了 → 🔴 必须按目标侧组号重选（见 `05_flash.md` 5.3）。

### (3) OPA 组 —— 见 `04_migration-rules.md` 4.4

`OPA_Init` / `OPA_StructInit` / `OPA_Cmd` **同名存在**，但：

| | V003 | 目标侧 |
|---|---|---|
| `OPA_InitTypeDef` 成员 | 2（`PSEL` `NSEL`） | 15（`POLL_CH1..3` `POLL_SEL` `Mode` `FB` `PGADIF` `PGA_VBEN` `PGA_VBSEL` `VBCMPSEL` `OPA_HS` …） |
| `OPA_StructInit` 默认值 | 只填 2 个字段 | 填 15 个字段 |
| `OPA_Cmd` | 单寄存器位操作 | 按 V005 的 OPA 控制寄存器重写 |

**目标 V005 → 整体按 V005 OPA 库重写**；**目标 V002 → 整句删除并在报告告知**。

### (4) `GPIO_PinRemapConfig` —— 重映射实现完全不同

两侧同名同签名，但函数体整体重写：

| | V003 | 目标侧 |
|---|---|---|
| 分支条件 | `GPIO_Remap & 0x10000000` / `0x80000000` / `(DBGAFR_LOCATION_MASK|DBGAFR_NUMBITS_MASK)` | `GPIO_Remap & 0x08000000` / `(DBGAFR_LOCATION_MASK\|DBGAFR_NUMBITS_MASK)` / `DBGAFR_TIM2RP_MASK` |
| 位移写法 | `(GPIO_Remap >> 0x15) * 0x10` | 先 `GPIO_Remap & 0x00FFFFFF` 再移位；新增 `tmpmask + 0x10` 分支 |
| 掩码宽度 | `0x03` / `0x0F` | `0x07` / `0x0F` 并按 `DBGAFR_NUMBITS_MASK` 分流 |

→ **必须按目标侧宏名重选参数**，不能沿用 V003 的宏名/宏值（见 `06_gpio.md` 6.5）。

### (5) `DBGMCU_GetCHIPID` —— 读的寄存器地址不同

| | V003 | 目标侧 |
|---|---|---|
| 读取地址 | `0x1FFFF7C4` | `0x1FFFF704` |
| 返回的 ID 值 | CH32V003 家族 | CH32V002/5 家族 |

**用户代码若用 `DBGMCU_GetCHIPID()` 做芯片识别或参数分支，返回值必然不同** → 需按目标芯片的 ID 值重写判断。
`DBGMCU_GetDEVID` / `DBGMCU_GetREVID` 同类。

### (6) `RCC_SYSCLKConfig` —— HSI 校准分支被删

V003 侧在切换 SYSCLK 到 PLL 且 PLL 源为 `RCC_PLLSource_HSI_MUL2` 时，会读 `CFG0_PLL_TRIM`
并调 `RCC_AdjustHSICalibrationValue()` 微调 HSI。**目标侧没有这段**。
→ 只影响基于 HSI 的时钟精度，不改变频率。若源工程依赖 HSI 校准后的精度，需在报告中提示。

### (7) `USART_Init` —— 8 倍过采样分支被删

V003 侧有 `if((USARTx->CTLR1 & CTLR1_OVER8_Set) != 0)` 的波特率计算分支（配合
`USART_OverSampling8Cmd`）。目标侧无此分支（该功能不存在）。
→ 常规 16 倍过采样波特率计算不受影响；用了 8 倍过采样的须删除。

### (8) `ADC_RegularChannelConfig` / `ADC_InjectedChannelConfig` —— 通道 > 9 的采样时间分支被删

V003 侧有 `if(ADC_Channel > ADC_Channel_9)` 分支，额外写 `SAMPTR1` 设置通道 10..15 的采样时间。
目标侧删掉了这个分支（通道 10..15 在目标侧不存在，采样时间改由 `ADC_Sample_ModeConfig` 管）。
→ 常规通道（0..9）不受影响。

---

## 7.2 🟡 超集扩展（不用改，但要知道）

目标库是 **CH32V002/004/005/006/007 五型号共用**，因此大量函数在原名基础上加了新分支或换用新寄存器宏。
**对原型号（V003 对应）路径，行为不变**。

| 组 | 函数 | 差异性质 |
|---|---|---|
| TIM（30 个） | `TIM_Cmd` `TIM_TimeBaseInit` `TIM_OC1Init` `TIM_OC1..4PreloadConfig` `TIM_SetCompare1..4` `TIM_GetCapture1..4` `TIM_SetCounter` `TIM_GetCounter` `TIM_SetAutoreload` `TIM_ARRPreloadConfig` `TIM_CounterModeConfig` `TIM_InternalClockConfig` `TIM_SelectSlaveMode` `TIM_DMACmd` `TIM_UpdateDisableConfig` `TIM_DeInit` `TI1_Config`..`TI4_Config` | 增加 `TIM3` 分支（`TIMx->TIM3_CTLR` / `TIM3_ATRLR`）与 TIM2 的 `TIM2_DTCR` 死区处理；TIM1/TIM2 原路径不变 |
| 各模块 `*_DeInit` | `GPIO_DeInit` `GPIO_AFIODeInit` `ADC_DeInit` `USART_DeInit` `SPI_I2S_DeInit` `I2C_DeInit` `PWR_DeInit` `WWDG_DeInit` `TIM_DeInit` | 仅 RCC 时钟宏改名（`APB2→PB2` 等）+ 目标侧多 GPIOB/USART2 分支；逻辑等价 |
| RCC 中断/时钟查询 | `RCC_GetITStatus` `RCC_ClearITPendingBit` `RCC_GetClocksFreq` | 增加 `RCC_IT_SYSCLK_FAIL`（时钟失效监听，目标侧新增能力）；`APBAHBPrescTable`→`PBHBPrescTable` 改名；`RCC_GetClocksFreq` 增加 ADCCLK 计算 |
| `GPIO_StructInit` | — | 默认速度从 `GPIO_Speed_2MHz` 改成 `GPIO_Speed_30MHz`（因目标侧只有一档）；仍用 `GPIO_StructInit` 的用户代码自动跟随 |

> `RCC_ClocksTypeDef` 两侧成员完全相同（`SYSCLK/HCLK/PCLK1/PCLK2/ADCCLK_Frequency`），不用管。

---

## 7.3 ❌ 已核实的假警报（不要再当成差异）

| 项 | 核实结论 |
|---|---|
| `NVIC_PriorityGroup_0/1` 语义 | **两侧行为一致**。`misc.c` 两侧逐字节相同（仅文件大小写与日期差异），宏值相同（`0x00`/`0x01`），`INTSYSCR_INEST` 默认值相同。**差异只在 `misc.h` 的第 60/62 行注释文字**——V003 侧注释写反了（WCH 文档笔误），目标侧注释是对的。`NVIC_PriorityGroupConfig(NVIC_PriorityGroup_1)` **不用改** |
| `ch32v00x_misc.c` vs `ch32v00X_misc.c` | 同名同体 2 / 同名异体 0，即逐字节等价 |
| `IWDG_Enable` | 两侧唯一差异是 `while ((...)` 与 `while((...)` 的空格 → 纯格式 |
| `GPIO_Speed_30MHz` 数值 `3`→`1` | 枚举值变，但赋给 `GPIOSpeed_TypeDef` 字段，**用宏名即正确**，不要去"修"这个数字 |
| `DBGMCU_*_STOP` 位定义变 | 传参用宏名，位定义由库侧决定 → 用宏名即正确 |
| `FLASH_WRProt_AllPages` `0x0000FFFF`→`0xFFFFFFFF` | 语义都是"全部页" → 用宏名即正确 |
| `TIM_CCR1..4` / `PWR_PVDLevel_0..3` | 仅类型文本 `uint16_t`→`uint32_t`，数值相同 |
| 各外设 `*_BASE` | 值文本里 `APB2PERIPH_BASE`→`PB2PERIPH_BASE`，**地址不变** |

> **原则：库文件里"同名同义、仅内部编码不同"的位置一律不动。** 两侧库各自实现同一个宏的正确取值；
> 用户代码里保留宏名，库侧自动映射。去"修正"这些数值反而引入 bug。

---

## 7.4 自己重跑这份清单

对任意模块，比较两侧同名函数的函数体：

```
python .workbuddy/scan/cmp_bodies.py <V003的.c> <目标的.c>
```

输出：同名同体数 / 同名异体数 / 仅单侧存在的函数名。对 `同名异体` 的条目再逐个人工判定属于
7.1（真语义变化）、7.2（超集扩展）还是 7.3（格式差异）。

判定要点（避免误报）：
- 差异出现在 `TIMx == TIM3` / `USARTx == USART2` / `GPIOx == GPIOB` 这类**新增分支** → 超集扩展
- 差异只是 `RCC_APB2PeriphResetCmd`→`RCC_PB2PeriphResetCmd` 这类**改名** → 超集扩展
- 差异出现在**主路径**上、且涉及数值/粒度/地址/位布局 → 真语义变化

---

## 7.5 阶段 3 强制核对清单（零提示项）

- [ ] FLASH 页粒度（`05_flash.md` 5.7）
- [ ] FLASH 写保护粒度
- [ ] OPA 组（V002 删除 / V005 重写）
- [ ] `GPIO_PinRemapConfig` 参数重选
- [ ] `DBGMCU_GetCHIPID` 等芯片 ID 判断
- [ ] `RCC_SYSCLKConfig` 的 HSI 校准依赖
- [ ] `USART_Init` 的 8 倍过采样
- [ ] `_WFE` / `__WFE`（`08_core-riscv.md`）
