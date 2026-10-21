# 03 函数（API）对照表

数据来源：全量解析两侧 `Peripheral/inc/*.h` 与 `Core/*.h` 的函数原型。
统计口径：V003 侧 346 个函数 / 目标侧 372 个 / 共有 323 个。

| 类别 | 条数 | 编译器能否兜底 |
|---|---|---|
| 仅 V003 有 | 23 | ✅ 报未声明 |
| 仅目标侧有 | 49 | — （新增能力） |
| **同名不同签名** | **0** | — |

**重要结论：两侧不存在"同名但签名变了"的函数。** 函数层面的差异只有两种：
改名（V003 有名 A、目标叫名 B）与删除（目标侧完全没有）。这意味着：
**凡是编译器报「未声明」的函数，按 3.1 / 3.2 / 3.3 三张表查即可，不存在"签名悄悄变了"的隐蔽情况。**
但**签名不变、函数体行为已变**的情况存在，见 `07_func-behavior.md`。

---

## 3.1 改名族（5 个，时钟前缀）

| V003 侧 | 目标侧 |
|---|---|
| `RCC_APB2PeriphClockCmd` | `RCC_PB2PeriphClockCmd` |
| `RCC_APB2PeriphResetCmd` | `RCC_PB2PeriphResetCmd` |
| `RCC_APB1PeriphClockCmd` | `RCC_PB1PeriphClockCmd` |
| `RCC_APB1PeriphResetCmd` | `RCC_PB1PeriphResetCmd` |
| `RCC_AHBPeriphClockCmd` | `RCC_HBPeriphClockCmd` |

签名不变（均为 `(uint32_t, FunctionalState)`）。改函数名的同时，传入的宏参数也要按 `02_macro-delta.md` 2.1 改名。

---

## 3.2 仅 V003 有（23 个）—— 目标芯片无此功能

### 3.2.1 整句删除（目标芯片无对应功能）

| # | 函数 | 所属 | 处理 |
|---|---|---|---|
| 1 | `ADC_StartCalibration` | ADC | 002/5 无 ADC 校准 → **删除整句** |
| 2 | `ADC_GetCalibrationStatus` | ADC | 同上 |
| 3 | `ADC_GetResetCalibrationStatus` | ADC | 同上 |
| 4 | `ADC_ResetCalibration` | ADC | 同上 |
| 5 | `ADC_Calibration_Vol` | ADC | 同上（校准电压档位） |
| 6 | `ADC_ExternalTrig_DLY` | ADC | 002/5 无 `ADC->DLYR` → **删除整句** |
| 7 | `OPA_DeInit` | OPA | V002 无 OPA → **删除整句**；V005 → 见 `04`/`07` 的 OPA 专项 |
| 8 | `USART_ClockInit` | USART | 002/5 无同步时钟 → **删除整句** |
| 9 | `USART_ClockStructInit` | USART | 同上 |
| 10 | `USART_SetGuardTime` | USART | 无智能卡 → 删除 |
| 11 | `USART_SmartCardCmd` | USART | 无智能卡 → 删除 |
| 12 | `USART_SmartCardNACKCmd` | USART | 无智能卡 → 删除 |
| 13 | `USART_OneBitMethodCmd` | USART | 无智能卡 → 删除 |
| 14 | `USART_OverSampling8Cmd` | USART | 目标侧无此位 → 删除 |

> 删除前确认：删掉后原功能不退化。ADC 校准项被删属于"目标芯片本身不需要校准"，不是功能损失。
> USART 智能卡/同步模式被删是**真实功能缺失**，须在最终报告列出。

### 3.2.2 改名（按 3.1 表改）

`RCC_APB2PeriphClockCmd` `RCC_APB2PeriphResetCmd` `RCC_APB1PeriphClockCmd` `RCC_APB1PeriphResetCmd` `RCC_AHBPeriphClockCmd`

### 3.2.3 FLASH 编程 API 被整体替换（🔴 规则文件未覆盖，见 `05_flash.md`）

| V003 侧 | 目标侧对应物 |
|---|---|
| `FLASH_ProgramWord(uint32_t Address, uint32_t Data)` | **无同名同义替代** → 用 `FLASH_BufLoad` + `FLASH_ProgramPage_Fast`，或 `FLASH_ROM_WRITE` |
| `FLASH_ProgramHalfWord(uint32_t Address, uint16_t Data)` | 无（002/5 不支持半字写） |
| `FLASH_ProgramOptionByteData(uint32_t Address, uint8_t Data)` | 无 |
| `FLASH_ReadOutProtection(FunctionalState NewState)` | `FLASH_EnableReadOutProtection(void)`（**名与签名同变**，见 3.3） |

---

## 3.3 仅目标侧有（49 个）

| 模块 | 函数 | 说明 |
|---|---|---|
| ADC（15） | `ADC_AnalogWatchdog1ThresholdsConfig` `ADC_AnalogWatchdog2ThresholdsConfig` `ADC_AnalogWatchdogResetCmd` `ADC_AnalogWatchdogScanCmd` `ADC_BufferCmd` `ADC_ClearAnalogWatchdogFlag` `ADC_DutyDelayCmd` `ADC_GetAnalogWatchdogFlagStatus` `ADC_InjectedExTrigConvConfig` `ADC_RegularExTrigConvConfig` `ADC_Sample_ModeConfig` `ADC_TKeyCmd` `ADC_TKey_ChannelxMulShieldCmd` `ADC_TKey_MulShieldCmd` `ADC_Tkey_CurrentConfig` | 看门狗 / 触摸键 / 采样模式 |
| OPA（20） | `OPA_CMP1_Init` `OPA_CMP1_StructInit` `OPA_CMP_ClearFlag` `OPA_CMP_Cmd` `OPA_CMP_FILT_Cmd` `OPA_CMP_FILT_LEN_Config` `OPA_CMP_GetFlagStatus` `OPA_CMP_Lock` `OPA_CMP_POLL_Lock` `OPA_CMP_SystemReset_Cmd` `OPA_CMP_TIM1_BKINConfig` `OPA_CMP_Unlock` `OPA_ClearFlag` `OPA_GetFlagStatus` `OPA_Lock` `OPA_SoftwareStartPollCmd` `OPA_SystemReset_Cmd` `OPA_Unlock` | V005 复杂 OPA + 比较器 |
| RCC（9） | `RCC_ADCCLKDutyCycleConfig` `RCC_ClockMonitorCmd` `RCC_HBPeriphClockCmd` `RCC_HSECurrentConfig` `RCC_HSE_LP_Cmd` `RCC_HSI_LP_Cmd` `RCC_PB1PeriphClockCmd` `RCC_PB1PeriphResetCmd` `RCC_PB2PeriphClockCmd` `RCC_PB2PeriphResetCmd` | 其中 5 个是 3.1 的改名目标 |
| FLASH（2） | `FLASH_EnableReadOutProtection(void)` `FLASH_EraseBlock_32K_Fast(uint32_t)` | 读保护改名 + 32K 块擦 |
| 其他（3） | `GPIO_IPD_Unused` `PWR_FLASH_LP_Cmd` `SPI_HS_RX_Cmd` `TIM_DeadTimeConfig` | 新增配置能力 |

---

## 3.4 中断向量（`IRQn_Type`）

V003 27 个 / 目标 29 个 / 共有 26 个。

| 类别 | 内容 |
|---|---|
| 仅 V003 | `EXC_IRQn = 3` |
| 仅目标 | `HardFault_IRQn = 3` · `USART2_IRQn = 39` · `OPCM_IRQn = 40` |
| **同名不同编号** | **无（26 个共有向量编号全部一致）** |

- `HardFault_IRQn` 在**两侧都可用**：V003 是 `#define HardFault_IRQn EXC_IRQn` 的别名，
  目标是枚举成员本身，编号同为 3。**用 `HardFault_IRQn` 的代码不用改**。
- 用 `EXC_IRQn` 的代码在目标侧报未声明 → 改成 `HardFault_IRQn`。
- V003 另有两个别名 `SysTicK_IRQn`（注意大小写）→ 目标侧无。用到的改成 `SysTick_IRQn`。

### 中断服务函数名

`User/ch32v00x_it.c` → 目标侧 `ch32v00X_it.c`。ISR 名字由启动文件决定，两侧同名同功能，
逐条核对即可（见 `01_model-and-project.md` 的工程结构）。

---

## 3.5 速查：从编译器错误反查处理动作

| 编译器提示 | 处理 |
|---|---|
| `RCC_APB2PeriphClockCmd` 等 5 个时钟函数未声明 | 按 3.1 改名 |
| `FLASH_ProgramWord` / `ProgramHalfWord` / `ProgramOptionByteData` 未声明 | 按 3.2.3 改用 Fast 编程 API，见 `05_flash.md` |
| `FLASH_ReadOutProtection` 未声明 | 改成 `FLASH_EnableReadOutProtection()`，去掉参数 |
| `ADC_StartCalibration` 等 6 个 ADC 函数未声明 | 删除整句（目标无校准） |
| `OPA_DeInit` 未声明 | V002 删除；V005 见 `07` 的 OPA 专项 |
| `USART_Clock*` / `USART_SmartCard*` / `USART_SetGuardTime` / `USART_OneBitMethodCmd` / `USART_OverSampling8Cmd` 未声明 | 删除整句，并在报告标注「USART 智能卡/同步模式功能缺失」 |
| `GPIO_Speed_10MHz` / `_2MHz` / `_50MHz` 未声明 | 统一改为 `GPIO_Speed_30MHz`，见 `06_gpio.md` |
| `RCC_FLAG_LPWRRST` / `RCC_LPWRRSTF` 未声明 | 删除该判断，报告标注「无低功耗复位标志查询」 |
| `EXC_IRQn` 未声明 | 改成 `HardFault_IRQn` |
| `SysTicK_IRQn` 未声明 | 改成 `SysTick_IRQn` |
| `WFE` / `WFItoWFE` / `_WFE_` 未声明 | 见 `08_core-riscv.md` |
| 链接期报 `.highcode` 无匹配段 | 去掉 `__attribute__((section(".highcode")))`，见 `01` 第 3 节 |
