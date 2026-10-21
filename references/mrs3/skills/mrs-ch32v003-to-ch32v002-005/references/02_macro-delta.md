# 02 宏对照表

数据来源：全量扫描两侧 `Peripheral/inc/*.h` + `Core/*.h`，解析 `#define`（含续行合并、注释剥离）。
统计口径：V003 侧 2073 个宏 / 目标侧 2292 个 / 共有 1890 个。

| 类别 | 条数 | 编译器能否兜底 |
|---|---|---|
| 仅 V003 有 | 183 | ✅ 报未声明 |
| 仅目标侧有 | 402 | — （新增能力，不影响迁移） |
| 同名异值 | 98 | ❌ **零提示** |

完整清单见 `09_appendix-full-lists.md`。本文件按「处理动作」重组。

---

## 2.1 改名族：时钟 APB2→PB2 / APB1→PB1 / AHB→HB（宏 + 函数一起改）

规则文件只写了宏名，实测**函数名同步改**，宏也一样改前缀：

| V003 侧宏 | 目标侧宏 |
|---|---|
| `RCC_APB2Periph_GPIOA` / `_GPIOC` / `_GPIOD` | `RCC_PB2Periph_GPIOA` / `_GPIOC` / `_GPIOD` |
| `RCC_APB2Periph_AFIO` | `RCC_PB2Periph_AFIO` |
| `RCC_APB2Periph_TIM1` | `RCC_PB2Periph_TIM1` |
| `RCC_APB2Periph_ADC1` | `RCC_PB2Periph_ADC1` |
| `RCC_APB2Periph_SPI1` | `RCC_PB2Periph_SPI1` |
| `RCC_APB2Periph_USART1` | `RCC_PB2Periph_USART1` |
| `RCC_APB1Periph_TIM2` | `RCC_PB1Periph_TIM2` |
| `RCC_APB1Periph_I2C1` | `RCC_PB1Periph_I2C1` |
| `RCC_APB1Periph_WWDG` | `RCC_PB1Periph_WWDG` |
| `RCC_APB1Periph_PWR` | `RCC_PB1Periph_PWR` |
| `RCC_AHBPeriph_DMA1` | `RCC_HBPeriph_DMA1` |
| `RCC_AHBPeriph_SRAM` | `RCC_HBPeriph_SRAM` |

| V003 侧函数 | 目标侧函数 |
|---|---|
| `RCC_APB2PeriphClockCmd` | `RCC_PB2PeriphClockCmd` |
| `RCC_APB2PeriphResetCmd` | `RCC_PB2PeriphResetCmd` |
| `RCC_APB1PeriphClockCmd` | `RCC_PB1PeriphClockCmd` |
| `RCC_APB1PeriphResetCmd` | `RCC_PB1PeriphResetCmd` |
| `RCC_AHBPeriphClockCmd` | `RCC_HBPeriphClockCmd` |

注：`AHB→HB` **只有 ClockCmd，没有 ResetCmd**（V003 侧也没有 AHB ResetCmd），两侧对称。

**结构体成员同规则改**（`ch32v00x.h` 的 RCC 结构体）：

| V003 侧成员 | 目标侧成员 |
|---|---|
| `RCC->APB2PCENR` | `RCC->PB2PCENR` |
| `RCC->APB1PCENR` | `RCC->PB1PCENR` |
| `RCC->AHBPCENR` | `RCC->HBPCENR` |

同类改名沿用：`APB2PERIPH_BASE`→`PB2PERIPH_BASE`、`APB1PERIPH_BASE`→`PB1PERIPH_BASE`、`AHBPERIPH_BASE`→`HBPERIPH_BASE`。
`EXTEN_BASE` / `AFIO_BASE` / `DMA1_BASE` 等 `*_BASE` 宏的值文本因此变化，但**地址值不变**，用户代码用宏名即正确，🟡 无需处理。

**V003 无、目标侧新增的时钟宏**（不影响迁移，仅提示可用）：`RCC_PB2Periph_GPIOB`、`RCC_PB1Periph_TIM3`、
`RCC_PB2Periph_USART2`、`RCC_HSILP`、`RCC_HSE_LP`、`RCC_HSE_C_Level0..3`、`RCC_ADCPRE_DIV*`、
`RCC_APB1Periph_TIM3` 对应物等（GPIOB / TIM3 / USART2 只在目标侧存在）。

**目标侧不存在的 RCC 宏**：
- `RCC_FLAG_LPWRRST`、`RCC_LPWRRSTF` → 002/5 无低功耗复位标志查询（规则文件已提及）。
  用户若查该标志，只能删除该判断并在报告中告知。

---

## 2.2 🔴 同名异值（98 条，编译器零提示）

按影响排序，挑出必须人工重算的：

### (a) ADC 位宽 10bit → 12bit

| 宏 | V003 | 目标侧 | 影响 |
|---|---|---|---|
| `ADC_HT` / `ADC_LT` | `0x03FF` | `0x0FFF` | 阈值掩码 |
| `ADC_JOFFSET1..4` | `0x03FF` | `0x0FFF` | 注入通道偏移 |
| `ADC_RDATAR_DATA` | `0xFFFFFFFF` | `0x0000FFFF` | 数据位宽 |

用户代码若对 ADC 结果做 `& 0x03FF`、按 1024 满量程换算电压、或硬编码阈值，**必须按 4096 重算**。

### (b) GPIO 模式位编码 `GPIO_CFGLR_MODE*`

`GPIO_CFGLR_MODE` V003 `0x33333333` → 目标 `0x11111111`；`MODE0..7` 及其 `_0/_1` 子位全部变。
反映两侧 `CFGLR` 配置寄存器布局不同。用户直接操作该寄存器位时必须重写。
（用 `GPIO_Init()` + `GPIO_Mode_*` 枚举的写法不受影响，见 `06_gpio.md`。）

### (c) GPIO_Pin_All

| 宏 | V003 | 目标侧 |
|---|---|---|
| `GPIO_Pin_All` | `0xFFFF` | `0x00FF` |

`GPIO_Pin_0..7` 两侧位值完全相同（`0x0001`…`0x0080`），只有 `All` 不同。
用户用 `GPIO_SetBits(GPIOx, GPIO_Pin_All)` 时，目标侧只覆盖低 8 位。🟠

### (d) 重映射参数（规则文件所说「参数定义大多不一致」）

同名异值：

| 宏 | V003 | 目标侧 |
|---|---|---|
| `AFIO_PCFR1_SPI1_REMAP` | `0x00000001` | `0x00000007` |
| `AFIO_PCFR1_I2C1_REMAP` | `0x00000002` | `0x00000038` |
| `AFIO_PCFR1_USART1_REMAP` | `0x00000004` | `0x000003C0` |
| `AFIO_PCFR1_TIM1_REMAP` | `0x000000C0` | `0x00003C00` |
| `AFIO_PCFR1_TIM1_REMAP_0/1` | `0x40` / `0x80` | `0x400` / `0x800` |
| `AFIO_PCFR1_TIM2_REMAP` | `0x00000300` | `0x0001C000` |
| `AFIO_PCFR1_TIM2_REMAP_0/1` | `0x100` / `0x200` | `0x4000` / `0x8000` |
| `GPIO_FullRemap_TIM1` | `0x001600C0` | `0x001A2400` |
| `GPIO_FullRemap_TIM2` | `0x00180300` | `0x084E0007` |
| `GPIO_FullRemap_USART1` | `0x80200004` | `0x00160240` |
| `GPIO_PartialRemap1_TIM1` | `0x00160040` | `0x001A0400` |
| `GPIO_PartialRemap1_TIM2` | `0x00180100` | `0x084E0001` |
| `GPIO_PartialRemap1_USART1` | `0x80000004` | `0x00160040` |
| `GPIO_PartialRemap2_TIM1` | `0x00160080` | `0x001A0800` |
| `GPIO_PartialRemap2_TIM2` | `0x00180200` | `0x084E0002` |
| `GPIO_PartialRemap2_USART1` | `0x80200000` | `0x00160080` |
| `GPIO_Remap_ADC1_ETRGINJ` | `0x00200002` | `0x00200004` |
| `GPIO_Remap_ADC1_ETRGREG` | `0x00200004` | `0x00200008` |
| `GPIO_Remap_LSI_CAL` | `0x00200080` | `0x001A3000` |
| `GPIO_Remap_SDI_Disable` | `0x00300400` | `0x08300400` |

**这些宏的值全部变了，用宏名不保险** —— V003 与目标侧的位布局不同，同一宏名指的不是同一件事。
必须按目标侧的引脚映射重选参数，见 `06_gpio.md`。

另有一批**只在一侧存在**的重映射宏（改名，编译期兜底）：

| V003 侧 | 目标侧 |
|---|---|
| `AFIO_PCFR1_ADC1_ETRGINJ_REMAP` | `AFIO_PCFR1_ADC_ETRGINJ_REMAP` |
| `AFIO_PCFR1_ADC1_ETRGREG_REMAP` | `AFIO_PCFR1_ADC_ETRGREG_REMAP` |
| `AFIO_PCFR1_PA12_REMAP` | `AFIO_PCFR1_PA1PA2_REMAP` |
| `AFIO_PCFR1_TIM1_1_RM` | `AFIO_PCFR1_TIM1_1_REMAP` |
| `AFIO_PCFR1_TIM1_REMAP_FULLREMAP` 等 | `AFIO_PCFR1_TIM1_REMAP_2/3` |
| `GPIO_Remap_SPI1` | （目标侧无同名，见 `06_gpio.md`） |
| `GPIO_Remap_PA1PA2` | `GPIO_Remap_PA1_2`（值也不同，见上表） |
| `GPIO_FullRemap_I2C1` / `GPIO_PartialRemap_I2C1` | （目标侧无同名） |
| `AFIO_PCFR1_I2C1_HIGH_BIT_REMAP` / `USART1_HIGH_BIT_REMAP` | （目标侧无同名） |
| `AFIO_PCFR1_SWJ_CFG_*` | （目标侧无同名） |

### (e) DBGMCU 停机位

| 宏 | V003 | 目标侧 |
|---|---|---|
| `DBGMCU_IWDG_STOP` | `0x00000001` | `0x00000100` |
| `DBGMCU_WWDG_STOP` | `0x00000002` | `0x00000200` |
| `DBGMCU_TIM1_STOP` | `0x00000010` | `0x00001000` |
| `DBGMCU_TIM2_STOP` | `0x00000020` | `0x00002000` |

用户用宏名传参给 `DBGMCU_Config()`，位定义由库侧决定，**保留宏名即正确** → 🟡 不必改。

### (f) FLASH

| 宏 | V003 | 目标侧 | 备注 |
|---|---|---|---|
| `FLASH_WRProt_AllPages` | `0x0000FFFF` | `0xFFFFFFFF` | 见 `05_flash.md` |
| `FLASH_FLAG_OPTERR` | `0x00000001` | `0x80000001` | 标志位定义变 |
| `FLASH_OBR_USER` | `0x03FC` | `0x00F4` | 用户选项字节掩码变 |

### (g) PWR

| 宏 | V003 | 目标侧 |
|---|---|---|
| `PWR_CTLR_PLS` | `0x00E0` | `0x0060` |
| `PWR_AWUPSC_0` | `0x0000` | `0x0001` |
| `PWR_AWUPSC_2` | `0x0002` | `0x0004` |
| `PWR_PVDLevel_0..3` | `0x0000/0x20/0x40/0x60`（uint16） | 同数值（uint32） |

`PWR_PVDLevel_*` 数值相同、仅类型文本不同 → 🟡 不必改。
规则文件提到「`PWR_PVDLevelConfig` 函数参数改动」，实测枚举值 0..3 同值；真正差异在
**V003 独有 `PWR_PVDLevel_2V9..4V4`、`PWR_PVDLevel_MODE0..7` 等具名档位，目标侧没有**（见 2.3）。

### (h) 🟡 仅类型文本不同、数值相同（不必改）

`TIM_CCR1..4`：V003 `((uint16_t)0xFFFF)` → 目标 `((uint32_t)0x0000FFFF)`，数值一致。
`PWR_PVDLevel_0..3`：同上。

---

## 2.3 仅 V003 有（183 条，编译期报未声明）

按模块分组。处理方式：**目标芯片无此功能 → 整句删除**；改名类 → 查 2.1 对照表。

| 模块 | 宏（节选/全量见附录） | 性质 |
|---|---|---|
| ADC | `ADC_CAL` `ADC_RSTCAL` `ADC_CALVOLSELECT*` `ADC_CALVOL_50PERCENT` `ADC_CALVOL_75PERCENT` `ADC_Channel_Vcalint` `ADC_DLYR_DLYSRC` `ADC_DLYR_DLYVLU` `ADC_ExternalTrig*_DLY` `ADC_ExternalTrigConv_Ext_PD3_PC2` `ADC_ExternalTrigInjecConv_Ext_PD1_PA2` `ADC_SMP10..15(+_0/_1/_2)` `ADC_SampleTime_3/9/15/30/43/57/73/241Cycles` | 002/5 无校准、无 DLYR、采样时间档位不同 |
| AFIO | `AFIO_PCFR1_ADC1_ETRGINJ_REMAP` `AFIO_PCFR1_ADC1_ETRGREG_REMAP` `AFIO_PCFR1_I2C1_HIGH_BIT_REMAP` `AFIO_PCFR1_PA12_REMAP` `AFIO_PCFR1_SWJ_CFG_*` `AFIO_PCFR1_TIM1_1_RM` `AFIO_PCFR1_TIM1_REMAP_*` `AFIO_PCFR1_TIM2_REMAP_*` `AFIO_PCFR1_USART1_HIGH_BIT_REMAP` | 重映射位定义不同 |
| 时钟 | `APB1PERIPH_BASE` `APB2PERIPH_BASE` `AHBPERIPH_BASE` `RCC_APB2Periph_*` `RCC_APB1Periph_*` `RCC_AHBPeriph_*` `RCC_FLAG_LPWRRST` `RCC_LPWRRSTF` | 改名 / 无此标志 |
| FLASH | `FLASH_WRProt_Pages0to15` … `Pages240to255`（16 个）`FLASH_CTLR_PG` `FLASH_CTLR_OPTPG` `FLASH_STATR_LOCK` `FLASH_STATR_MODE` `FLASH_FLAG_BANK1_EOP` `FLASH_IT_BANK1_*` `FLASH_MODEKEYR_KEY1/2` `FLASH_BOOT_MODEKEYR_KEY1/2` `FLASH_OBR_FIX_11` `FLASH_OBR_STANDY_RST` `FLASH_OBR_nRST_STOP` | 写保护粒度 16→8 页 |
| GPIO | `GPIO_Speed_50MHz` `GPIO_FullRemap_I2C1` `GPIO_PartialRemap_I2C1` `GPIO_Remap_PA1PA2` `GPIO_Remap_SPI1` | 速度档位 / 重映射名 |
| 中断 | `HardFault_IRQn`（V003 是 `#define HardFault_IRQn EXC_IRQn` 的别名，`EXC_IRQn` 才是枚举成员） `SysTicK_IRQn`（别名） | 见 03 |
| OPA/EXTEN | `EXTEN_OPA_EN` `EXTEN_OPA_NSEL` `EXTEN_OPA_PSEL` `EXTEN_LDO_TRIM` `CFG0_PLL_TRIM` | V002 无 OPA |
| PWR | `PWR_AWUCSR_AWUEN` `PWR_AWUPSC_4/8/16/32/64/128/256/512/1024/2048/4096/10240/61440` `PWR_CTLR_PLS_2` `PWR_PVDLevel_2V9/3V1/3V3/3V5/3V7/3V9/4/4V1/4V4/5/6/7` `PWR_PVDLevel_MODE0..7` `OB_STOP_RST` `OB_STOP_NoRST` | AWU 预分频档位与 PVD 档位定义不同 |
| SPI/I2S | `SPI_STATR_CHSIDE` `SPI_STATR_UDR` `I2S_FLAG_CHSIDE` `I2S_FLAG_UDR` `I2S_IT_UDR` | 目标侧 STATR 无这两位 |
| USART | `USART_CTLR2_LBCL` `USART_CTLR2_CPHA` `USART_CTLR2_CPOL` `USART_CTLR2_CLKEN` `USART_CTLR3_NACK` `USART_CTLR3_SCEN` `USART_GPR_GT` `USART_CPHA_1Edge/2Edge` `USART_CPOL_High/Low` `USART_Clock_Enable/Disable` `USART_LastBit_Enable/Disable` | 002/5 无智能卡/同步时钟 |
| Core | `_WFE_` | `.highcode` 宏，见 `08_core-riscv.md` |

---

## 2.4 仅目标侧有（402 条，仅告知）

不影响迁移，是目标芯片的**新增能力**。用户若想用可直接调用：

| 模块 | 代表 | 说明 |
|---|---|---|
| ADC | `ADC_AnalogWatchdog*` `ADC_TKey*` `ADC_BUFEN` `ADC_DRVEN` `ADC_LP` `ADC_Channel_OPA` `ADC_WDTR1_*/WDTR2_*` `ADC_SampleTime_CyclesMode0..7` | 模拟看门狗 / 触摸按键 / 缓冲 / OPA 通道 |
| RCC | `RCC_PB2Periph_GPIOB` `RCC_PB1Periph_TIM3` `RCC_PB2Periph_USART2` `RCC_ADCPRE_DIV*` `RCC_HSE_C_Level*` `RCC_HSILP` `RCC_HSE_LP` `RCC_SYSCM_EN` | GPIOB / TIM3 / USART2 等新外设 |
| AFIO | `AFIO_EXTICR1_EXTI0_PB` … `EXTI7_PB`、`AFIO_PCFR1_USART2_REMAP*` | GPIOB 的 EXTI 映射 |
| OPA | `OPA_CTLR1_*` `OPA_CTLR2_*` `OPA_CFGR1_*` `OPA_CFGR2_*` `OPA_FLAG_OUT_POLL_CH_*` `OPA_KEY` | V005 复杂 OPA + 比较器 |
| PWR | `PWR_CTLR_LDO_MODE*` `PWR_CTLR_FLASH_LP*` `PWR_AWUWR_0..5` `PWR_CTLR_PLS_MODE0..3` | LDO 模式 / Flash 低功耗 |
| SPI | （`SPI_HS_RX_Cmd` 对应宏） | 高速接收 |

> 目标侧宏总数比 V003 多 219 个，其中多数是 002/4/5/6/7 五型号共用的条件编译块。
> **按目标型号取用的宏集合，以工程实际生效的芯片宏为准**；本表只列与 V003 有差集的项。
