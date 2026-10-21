# 04 逐模块迁移规则

主干来自硬件工程师的 `003-002、005规则.md`，逐条展开并与两侧源码核对。
**规则文件与源码冲突时以源码为准**，冲突点已在各模块内标注。

---

## 判定原则：先分类再动手

| 判定 | 编译期表现 | 处理 |
|---|---|---|
| 目标库无此符号（改名类） | 报未声明 | 查 `02`/`03` 对照表改名，编译器兜底 |
| 目标芯片无此功能（删除类） | 报未声明 | **整句删除**，并确认删掉后功能不退化 |
| 同名但值/粒度已变 | **零提示** | 必须重算，查 `02_macro-delta.md` 2.2 |
| 同名同签名、实现已变 | **零提示** | 必须逐条核对，查 `07_func-behavior.md` |

后两类是本次迁移的真正价值所在——编译器一句话都不会说。

---

## 4.1 时钟 RCC

**规则原文**：`APB2→PB2`、`APB1→PB1`、`AHB→HB`；库直接替换 V002/5。

**实测展开**（规则文件只提宏名，实际宏名与函数名同改）：

- 宏：`RCC_APB2Periph_*`→`RCC_PB2Periph_*`，`RCC_APB1Periph_*`→`RCC_PB1Periph_*`，`RCC_AHBPeriph_*`→`RCC_HBPeriph_*`
- 函数：5 个 `*PeriphClockCmd` / `*PeriphResetCmd`（完整表见 `03_api-delta.md` 3.1）
- 结构体成员：`RCC->APB2PCENR`→`PB2PCENR`，`APB1PCENR`→`PB1PCENR`，`AHBPCENR`→`HBPCENR`

**功能缺失**：002/5 无低功耗复位标志，`RCC_FLAG_LPWRRST` / `RCC_LPWRRSTF` 不存在。
用户若查询该标志 → 删除该判断，并在报告标注。

---

## 4.2 ADC

**规则原文**：002/5 ADC 没有校准功能；`ADC_Channel9` 定义不同
（V003 `ADC_Channel_Vcalint` / 002 `ADC_Channel_OPA`）；002 没有 `ADC->DLYR` 寄存器。

**实测展开**：

| 项 | 处理 |
|---|---|
| 校准 | 删除 `ADC_StartCalibration` / `ADC_GetCalibrationStatus` / `ADC_GetResetCalibrationStatus` / `ADC_ResetCalibration` / `ADC_Calibration_Vol`，以及相关宏 `ADC_CAL` `ADC_RSTCAL` `ADC_CALVOL*` |
| `ADC->DLYR` | 删除 `ADC_ExternalTrig_DLY` 及 `ADC_DLYR_*` `ADC_ExternalTrig*_DLY` 宏 |
| 通道定义 | `ADC_Channel_Vcalint`（V003）→ 目标侧无对应；`ADC_Channel_OPA`（002）→ 边界情况按目标侧通道表重选 |
| **位宽 10bit→12bit** | 🔴 `ADC_HT`/`ADC_LT`/`ADC_JOFFSET1..4`（`0x03FF`→`0x0FFF`）、`ADC_RDATAR_DATA`（`0xFFFFFFFF`→`0x0000FFFF`）。用户对 ADC 结果做掩码/满量程换算/阈值硬编码的，**必须按 4096 重算** |
| 采样时间档 | V003 独有 `ADC_SampleTime_3/9/15/30/43/57/73/241Cycles`（+`ADC_SMP10..15` 位宏），目标侧改为 `ADC_SampleTime_CyclesMode0..7`。用到的需重选档位 |
| 触发源 | V003 `ADC_ExternalTrigConv_Ext_PD3_PC2` / `ADC_ExternalTrigInjecConv_Ext_PD1_PA2` → 目标侧对应 `ADC_RegularExTrigConv_PD3_PC2` / `ADC_InjectedExTrigConv_PD1_PA2`（改名） |

---

## 4.3 GPIO

**规则原文**：差异较大。`GPIO_Speed` 宏定义差异，V002/5 只有一组 `GPIO_Speed_30MHz`，
所有调用的整体替换；外设引脚重映射参数定义大多不一致；库文件替换 V002/5。
专项详见 `06_gpio.md`。

**结论速览**：
- `GPIO_Speed_10MHz` / `_2MHz` / `_50MHz` → 统一改 `GPIO_Speed_30MHz`
- `GPIO_Mode_*` 枚举**两侧完全相同**，不用动
- `GPIO_Pin_0..7` 两侧位值相同；仅 `GPIO_Pin_All` 从 `0xFFFF` 变 `0x00FF`
- **重映射参数必须重选**，同名宏的值也变了（🔴 零提示）

---

## 4.4 OPA

**规则原文**：V003 OPA 功能简洁；V002 无 OPA；V005 有 OPA 且复杂，有对应寄存器。
`OPA_DeInit` 函数调用直接删除。

**实测展开**（两侧差异极大，规则文件只给了一句）：

| | V003 `ch32v00x_opa.h` | 目标 `ch32v00X_opa.h` |
|---|---|---|
| 行数 | 53 | 373 |
| 函数数 | 4 | 21 |
| `OPA_InitTypeDef` 成员 | 2（`PSEL` `NSEL`） | 15（含 `POLL_CH1..3` `Mode` `FB` `PGADIF` `OPA_HS` 等） |
| `OPA_DeInit` | 有 | **无** |

**处理口径（按目标芯片分流，boss 已确认）**：

| 目标 | 处理 |
|---|---|
| **V002** | V002 无 OPA。所有 OPA 调用**整句删除**（`OPA_DeInit` `OPA_Init` `OPA_Cmd` …），并在最终报告告知「源工程使用了 OPA，目标芯片无此功能」 |
| **V005** | **整体按 V005 的 OPA 库重写**——`PSEL`/`NSEL` 之外的字段、`OPA_StructInit` 的初始化内容、以及 `OPA_DeInit` 的替代（无此函数，直接去掉即可）都要按目标侧语义重写；不得只做改名 |

> V005 的 `OPA_Init` / `OPA_StructInit` / `OPA_Cmd` **同名存在**，编译器不会报错 ——
> 但 `OPA_InitTypeDef` 结构体成员已完全不同，属于"同名不同义"，🔴 必须人工重写。见 `07_func-behavior.md`。

---

## 4.5 PWR

**规则原文**：`PWR_PVDLevelConfig` 函数参数改动；库直接替换 V002/5。

**实测展开**：

- `PWR_PVDLevel_0..3` 两侧**数值相同**（`0x00/0x20/0x40/0x60`），仅类型从 `uint16_t` 变 `uint32_t` → 🟡 不必改
- V003 独有具名档位 `PWR_PVDLevel_2V9/3V1/3V3/3V5/3V7/3V9/4/4V1/4V4/5/6/7`、`PWR_PVDLevel_MODE0..7` → 目标侧无，用到的需按目标侧档位重选
- `PWR_CTLR_PLS` 掩码 `0x00E0`→`0x0060`；V003 `PWR_CTLR_PLS_2` → 目标侧改为 `PWR_CTLR_PLS_MODE0..3`
- AWU 预分频：V003 `PWR_AWUPSC_4/8/16/…/61440`（13 档）→ 目标侧 `PWR_AWUPSC_1/3` + `PWR_AWUWR_0..5`，**档位体系变了**，需重算
- V003 独有 `PWR_AWUCSR_AWUEN`、`OB_STOP_RST` / `OB_STOP_NoRST` → 删除或替换

---

## 4.6 USART

**规则原文**：002/5 的 `CTLR2` 没有 `USART_CTLR2_LBCL` `USART_CTLR2_CPHA` `USART_CTLR2_CPOL` `USART_CTLR2_CLKEN`；
`CTLR3` 没有 `USART_CTLR3_NACK` `USART_CTLR3_SCEN`；002/5 没有智能卡相关功能。

**实测确认**（完全一致）。处理：

| 类别 | 内容 |
|---|---|
| 删除的宏 | `USART_CTLR2_LBCL` `USART_CTLR2_CPHA` `USART_CTLR2_CPOL` `USART_CTLR2_CLKEN` `USART_CTLR3_NACK` `USART_CTLR3_SCEN` `USART_GPR_GT` |
| 删除的函数 | `USART_ClockInit` `USART_ClockStructInit` `USART_SetGuardTime` `USART_SmartCardCmd` `USART_SmartCardNACKCmd` `USART_OneBitMethodCmd` `USART_OverSampling8Cmd` |
| 连带删除的枚举 | `USART_CPHA_1Edge/2Edge` `USART_CPOL_High/Low` `USART_Clock_Enable/Disable` `USART_LastBit_Enable/Disable` |
| **功能缺失告知** | 「USART 智能卡 / 同步时钟 / 单线半双工（OneBit）/ 8 倍过采样」在目标芯片上不可用，须在报告列出 |

> 常规 UART 收发（`USART_Init` / `USART_Cmd` / `USART_SendData` / `USART_ReceiveData` / 中断）不受影响。

---

## 4.7 SPI

**规则原文**：002/5 `SPI->STATR` 没有 `SPI_STATR_CHSIDE` 和 `SPI_STATR_UDR` 功能位；
对应没有标志位宏 `I2S_FLAG_CHSIDE` 和 `I2S_FLAG_UDR`。

**实测确认**。另：`I2S_IT_UDR` 也是 V003 独有。用到的删除或在报告标注。

---

## 4.8 FLASH

见 `05_flash.md`（专项）。要点：页擦写最小单位 64B→256B、半字写不支持、
编程 API 被整体换成 Fast 编程、写保护粒度 16 页→8 页、读保护函数改名去参。

---

## 4.9 「通用替换」7 项 —— 免逐条对照

`debugmcu` / `dma` / `exti` / `i2c` / `iwdg` / `misc` / `tim`

**处理口径**：这些模块的**库文件直接用 V002/V5 侧的**（不做逐条差异对照）。

依据：两侧这些库基本同源，行数持平（dma 416/411、exti 182/182、i2c 975/973、
iwdg 126/126、misc 81/81、wwdg 141/141、tim 相近），差异集中在命名与注释。

库文件本身不需要 skill 处理（工程级转换后已经是目标侧的库）。skill 只需保证：

1. 用户代码对这几个模块的**调用**能编译通过 —— 依赖编译器兜底，按 `02`/`03` 表处理个别符号；
2. 不改动这些库文件本身。

### 用户代码调用这几个模块时仍需注意的个别符号

| 模块 | 用户代码里可能出现的 V003 专有符号 | 处理 |
|---|---|---|
| tim | `TIM_CCR1..4`（仅类型文本变，数值同） | 🟡 不改 |
| tim | `TIM_DeadTimeConfig` 是目标侧新增 | 目标侧可用，不影响迁移 |
| dma | `RCC_AHBPeriph_DMA1` → `RCC_HBPeriph_DMA1` | 改名（属 RCC 族） |
| dma | `DMA1_BASE` 等 `*_BASE` 值文本变 | 🟡 不改 |
| debugmcu | `DBGMCU_*_STOP` 位定义变 | 🟡 用宏名即正确，不改 |
| exti | `AFIO_EXTICR1_EXTI0..7_PB` 是目标侧新增（GPIOB） | 目标侧可用 |
| misc | 两侧 `misc.c` 逐字节相同；`misc.h` 仅注释差异 | 🟡 不改（见 `07_func-behavior.md` 的误报条目） |
