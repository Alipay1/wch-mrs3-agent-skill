# 中断向量对照与处理函数

> 数据来源：`stm32f10x.h` / `ch32v20x.h` 的 `IRQn_Type` 枚举，以及两侧启动文件的向量表。
> **两套编号体系不同**：Cortex-M 的异常号为负数起始，RISC-V 的 PFIC 中断号为 16 起始。
> 绝对值不可沿用，必须使用符号名。

## 一、核心事实

| 项 | 结论 |
|---|---|
| 处理函数名 | ✅ **同名沿用**。CH32 启动文件按 `XXX_IRQHandler` 命名（如 `TIM2_IRQHandler`），与 STM32 一致 |
| 函数属性 | 🔴 **必须补** `__attribute__((interrupt("WCH-Interrupt-fast")))`，两侧不可省略 |
| 向量表弱定义 | ✅ 启动文件全部使用 `.weak`，未实现的中断不会导致链接失败 |
| 中断编号 | 🔴 **数值全部不同**，任何裸数字写法必须改为符号 |
| 内核异常 | 🔴 `SVCall` / `BusFault` / `MemoryManagement` / `DebugMonitor` 在 RISC-V 侧不存在 | — | 无对应，无替代 |
| `PendSV_IRQn` | `Software_IRQn` | `SW_Handler` | 🟠 RISC-V 侧没有 PendSV，**RTOS 的上下文切换改走软中断**（编号 14，见 §三）。`PendSV_Handler` 整段改名为 `SW_Handler`，**不要直接删** |

## 二、中断源对照表（STM32 → CH32）

| STM32 中断源 | CH32 中断源 | 处理函数名 | 说明 |
|---|---|---|---|
| `NonMaskableInt_IRQn` | `NonMaskableInt_IRQn` | `NMI_Handler` | 内核异常，编号体系不同 |
| `HardFault_IRQn` | `EXC_IRQn` | `HardFault_Handler` | CH32 提供别名 `HardFault_IRQn` |
| `SysTick_IRQn` | `SysTick_IRQn` | `SysTick_Handler` |  |
| `WWDG_IRQn` | `WWDG_IRQn` | `WWDG_IRQHandler` |  |
| `PVD_IRQn` | `PVD_IRQn` | `PVD_IRQHandler` |  |
| `TAMPER_IRQn` | `TAMPER_IRQn` | `TAMPER_IRQHandler` |  |
| `RTC_IRQn` | `RTC_IRQn` | `RTC_IRQHandler` |  |
| `FLASH_IRQn` | `FLASH_IRQn` | `FLASH_IRQHandler` |  |
| `RCC_IRQn` | `RCC_IRQn` | `RCC_IRQHandler` |  |
| `EXTI0_IRQn` | `EXTI0_IRQn` | `EXTI0_IRQHandler` |  |
| `EXTI1_IRQn` | `EXTI1_IRQn` | `EXTI1_IRQHandler` |  |
| `EXTI2_IRQn` | `EXTI2_IRQn` | `EXTI2_IRQHandler` |  |
| `EXTI3_IRQn` | `EXTI3_IRQn` | `EXTI3_IRQHandler` |  |
| `EXTI4_IRQn` | `EXTI4_IRQn` | `EXTI4_IRQHandler` |  |
| `DMA1_Channel1_IRQn` | `DMA1_Channel1_IRQn` | `DMA1_Channel1_IRQHandler` |  |
| `DMA1_Channel2_IRQn` | `DMA1_Channel2_IRQn` | `DMA1_Channel2_IRQHandler` |  |
| `DMA1_Channel3_IRQn` | `DMA1_Channel3_IRQn` | `DMA1_Channel3_IRQHandler` |  |
| `DMA1_Channel4_IRQn` | `DMA1_Channel4_IRQn` | `DMA1_Channel4_IRQHandler` |  |
| `DMA1_Channel5_IRQn` | `DMA1_Channel5_IRQn` | `DMA1_Channel5_IRQHandler` |  |
| `DMA1_Channel6_IRQn` | `DMA1_Channel6_IRQn` | `DMA1_Channel6_IRQHandler` |  |
| `DMA1_Channel7_IRQn` | `DMA1_Channel7_IRQn` | `DMA1_Channel7_IRQHandler` |  |
| `ADC1_2_IRQn` | `ADC_IRQn` | `ADC1_2_IRQHandler` | CH32 提供别名 `ADC1_2_IRQn` → `ADC_IRQn` |
| `USB_HP_CAN1_TX_IRQn` | `USB_HP_CAN1_TX_IRQn` | `USB_HP_CAN1_TX_IRQHandler` |  |
| `USB_LP_CAN1_RX0_IRQn` | `USB_LP_CAN1_RX0_IRQn` | `USB_LP_CAN1_RX0_IRQHandler` |  |
| `CAN1_RX1_IRQn` | `CAN1_RX1_IRQn` | `CAN1_RX1_IRQHandler` |  |
| `CAN1_SCE_IRQn` | `CAN1_SCE_IRQn` | `CAN1_SCE_IRQHandler` |  |
| `EXTI9_5_IRQn` | `EXTI9_5_IRQn` | `EXTI9_5_IRQHandler` |  |
| `TIM1_BRK_IRQn` | `TIM1_BRK_IRQn` | `TIM1_BRK_IRQHandler` |  |
| `TIM1_UP_IRQn` | `TIM1_UP_IRQn` | `TIM1_UP_IRQHandler` |  |
| `TIM1_TRG_COM_IRQn` | `TIM1_TRG_COM_IRQn` | `TIM1_TRG_COM_IRQHandler` |  |
| `TIM1_CC_IRQn` | `TIM1_CC_IRQn` | `TIM1_CC_IRQHandler` |  |
| `TIM2_IRQn` | `TIM2_IRQn` | `TIM2_IRQHandler` |  |
| `TIM3_IRQn` | `TIM3_IRQn` | `TIM3_IRQHandler` |  |
| `TIM4_IRQn` | `TIM4_IRQn` | `TIM4_IRQHandler` |  |
| `I2C1_EV_IRQn` | `I2C1_EV_IRQn` | `I2C1_EV_IRQHandler` |  |
| `I2C1_ER_IRQn` | `I2C1_ER_IRQn` | `I2C1_ER_IRQHandler` |  |
| `I2C2_EV_IRQn` | `I2C2_EV_IRQn` | `I2C2_EV_IRQHandler` |  |
| `I2C2_ER_IRQn` | `I2C2_ER_IRQn` | `I2C2_ER_IRQHandler` |  |
| `SPI1_IRQn` | `SPI1_IRQn` | `SPI1_IRQHandler` |  |
| `SPI2_IRQn` | `SPI2_IRQn` | `SPI2_IRQHandler` |  |
| `USART1_IRQn` | `USART1_IRQn` | `USART1_IRQHandler` |  |
| `USART2_IRQn` | `USART2_IRQn` | `USART2_IRQHandler` |  |
| `USART3_IRQn` | `USART3_IRQn` | `USART3_IRQHandler` |  |
| `EXTI15_10_IRQn` | `EXTI15_10_IRQn` | `EXTI15_10_IRQHandler` |  |
| `RTCAlarm_IRQn` | `RTCAlarm_IRQn` | `RTCAlarm_IRQHandler` |  |
| `USBWakeUp_IRQn` | `USBWakeUp_IRQn` | `USBWakeUp_IRQHandler` |  |
| `TIM5_IRQn` | `TIM5_IRQn` | `TIM5_IRQHandler` | 仅 CH32V20x_D8 / D8W 存在 |
| `UART4_IRQn` | `UART4_IRQn` | `UART4_IRQHandler` |  |

> 中断源名称相同的项，编号依然不同（见本文第三节）。

## 三、CH32 中断编号表（`NVIC_IRQChannel` 取值）

| 编号 | 中断源 | 处理函数 | 型号归属 |
|---:|---|---|---|
| 2 | `NonMaskableInt_IRQn` | `NMI_Handler` | 全部 |
| 3 | `EXC_IRQn` | `HardFault_Handler` | 全部 |
| 5 | `Ecall_M_Mode_IRQn` | `Ecall_M_Mode_Handler` | 全部 |
| 8 | `Ecall_U_Mode_IRQn` | `Ecall_U_Mode_Handler` | 全部 |
| 9 | `Break_Point_IRQn` | `Break_Point_Handler` | 全部 |
| 12 | `SysTick_IRQn` | `SysTick_Handler` | 全部 |
| 14 | `Software_IRQn` | `SW_Handler` | 全部 |
| 16 | `WWDG_IRQn` | `WWDG_IRQHandler` | 全部 |
| 17 | `PVD_IRQn` | `PVD_IRQHandler` | 全部 |
| 18 | `TAMPER_IRQn` | `TAMPER_IRQHandler` | 全部 |
| 19 | `RTC_IRQn` | `RTC_IRQHandler` | 全部 |
| 20 | `FLASH_IRQn` | `FLASH_IRQHandler` | 全部 |
| 21 | `RCC_IRQn` | `RCC_IRQHandler` | 全部 |
| 22 | `EXTI0_IRQn` | `EXTI0_IRQHandler` | 全部 |
| 23 | `EXTI1_IRQn` | `EXTI1_IRQHandler` | 全部 |
| 24 | `EXTI2_IRQn` | `EXTI2_IRQHandler` | 全部 |
| 25 | `EXTI3_IRQn` | `EXTI3_IRQHandler` | 全部 |
| 26 | `EXTI4_IRQn` | `EXTI4_IRQHandler` | 全部 |
| 27 | `DMA1_Channel1_IRQn` | `DMA1_Channel1_IRQHandler` | 全部 |
| 28 | `DMA1_Channel2_IRQn` | `DMA1_Channel2_IRQHandler` | 全部 |
| 29 | `DMA1_Channel3_IRQn` | `DMA1_Channel3_IRQHandler` | 全部 |
| 30 | `DMA1_Channel4_IRQn` | `DMA1_Channel4_IRQHandler` | 全部 |
| 31 | `DMA1_Channel5_IRQn` | `DMA1_Channel5_IRQHandler` | 全部 |
| 32 | `DMA1_Channel6_IRQn` | `DMA1_Channel6_IRQHandler` | 全部 |
| 33 | `DMA1_Channel7_IRQn` | `DMA1_Channel7_IRQHandler` | 全部 |
| 34 | `ADC_IRQn` | `ADC1_2_IRQHandler` | 全部 |
| 35 | `USB_HP_CAN1_TX_IRQn` | `USB_HP_CAN1_TX_IRQHandler` | 全部 |
| 36 | `USB_LP_CAN1_RX0_IRQn` | `USB_LP_CAN1_RX0_IRQHandler` | 全部 |
| 37 | `CAN1_RX1_IRQn` | `CAN1_RX1_IRQHandler` | 全部 |
| 38 | `CAN1_SCE_IRQn` | `CAN1_SCE_IRQHandler` | 全部 |
| 39 | `EXTI9_5_IRQn` | `EXTI9_5_IRQHandler` | 全部 |
| 40 | `TIM1_BRK_IRQn` | `TIM1_BRK_IRQHandler` | 全部 |
| 41 | `TIM1_UP_IRQn` | `TIM1_UP_IRQHandler` | 全部 |
| 42 | `TIM1_TRG_COM_IRQn` | `TIM1_TRG_COM_IRQHandler` | 全部 |
| 43 | `TIM1_CC_IRQn` | `TIM1_CC_IRQHandler` | 全部 |
| 44 | `TIM2_IRQn` | `TIM2_IRQHandler` | 全部 |
| 45 | `TIM3_IRQn` | `TIM3_IRQHandler` | 全部 |
| 46 | `TIM4_IRQn` | `TIM4_IRQHandler` | 全部 |
| 47 | `I2C1_EV_IRQn` | `I2C1_EV_IRQHandler` | 全部 |
| 48 | `I2C1_ER_IRQn` | `I2C1_ER_IRQHandler` | 全部 |
| 49 | `I2C2_EV_IRQn` | `I2C2_EV_IRQHandler` | 全部 |
| 50 | `I2C2_ER_IRQn` | `I2C2_ER_IRQHandler` | 全部 |
| 51 | `SPI1_IRQn` | `SPI1_IRQHandler` | 全部 |
| 52 | `SPI2_IRQn` | `SPI2_IRQHandler` | 全部 |
| 53 | `USART1_IRQn` | `USART1_IRQHandler` | 全部 |
| 54 | `USART2_IRQn` | `USART2_IRQHandler` | 全部 |
| 55 | `USART3_IRQn` | `USART3_IRQHandler` | 全部 |
| 56 | `EXTI15_10_IRQn` | `EXTI15_10_IRQHandler` | 全部 |
| 57 | `RTCAlarm_IRQn` | `RTCAlarm_IRQHandler` | 全部 |
| 58 | `USBWakeUp_IRQn` | `USBWakeUp_IRQHandler` | 全部 |
| 59 | `USBFS_IRQn` | `USBFS_IRQHandler` | 全部（CH32 独有） |
| 60 | `USBFSWakeUp_IRQn` | `USBFSWakeUp_IRQHandler` | 全部（CH32 独有） |
| 61 | `UART4_IRQn（D6）／ETH_IRQn（D8/D8W）` | `UART4_IRQHandler / ETH_IRQHandler` | ⚠ 编号同、中断源不同 |
| 62 | `DMA1_Channel8_IRQn（D6）／ETHWakeUp_IRQn（D8/D8W）` | `DMA1_Channel8_IRQHandler / ETHWakeUp_IRQHandler` | ⚠ 编号同、中断源不同 |
| 63 | `BB_IRQn` | `—` | 仅 D8W |
| 64 | `LLE_IRQn` | `—` | 仅 D8W |
| 65 | `TIM5_IRQn` | `TIM5_IRQHandler` | 仅 D8 / D8W |
| 66 | `UART4_IRQn` | `UART4_IRQHandler` | 仅 D8 / D8W |
| 67 | `DMA1_Channel8_IRQn` | `DMA1_Channel8_IRQHandler` | 仅 D8 / D8W |
| 68 | `OSC32KCal_IRQn` | `—` | 仅 D8 / D8W |
| 69 | `OSCWakeUp_IRQn` | `—` | 仅 D8 / D8W |

> 🔴 编号 61 / 62 在不同型号下**含义不同**，这是唯一一处编号冲突。
> 用户代码若是带型号条件编译的，把源型号宏（`STM32F10X_MD` 等）换成 `CH32V20x_D6` / `D8` / `D8W` 即可
> —— D6 目标下该宏由 `ch32v20x.h:19-24` 兜底自动定义，用户代码照常 `#ifdef` 即可，**无需在任何地方显式定义**（详见 `05_migration-rules.md` 第二节第 4 项）。

## 四、其余差异

### 仅 STM32 存在（CH32 无对应外设，中断不会触发）

- `CAN2_TX_IRQn`
- `CAN2_RX0_IRQn`
- `CAN2_RX1_IRQn`
- `CAN2_SCE_IRQn`
- `DMA2_Channel1~5_IRQn`
- `ADC3_IRQn`
- `SPI3_IRQn`
- `FSMC_IRQn`
- `SDIO_IRQn`
- `CEC_IRQn`
- `ETH_WKUP_IRQn`
- `OTG_FS_IRQn`
- `OTG_FS_WKUP_IRQn`
- `SVCall_IRQn`
- `BusFault_IRQn`
- `MemoryManagement_IRQn`
- `DebugMonitor_IRQn`
- `PendSV_IRQn`（**有替代**：改用 `Software_IRQn` / `SW_Handler`，见 §一）
- `UART5_IRQn`（CH32V20x 有 `UART4_IRQn`，无 UART5）
- `TIM6_IRQn` / `TIM7_IRQn`
- `TIM8_BRK_IRQn` / `TIM8_UP_IRQn` / `TIM8_TRG_COM_IRQn` / `TIM8_CC_IRQn`
- `TIM9` ~ `TIM17` 相关中断（CH32V20x 只有 TIM1~TIM5）

### 仅 CH32 存在（新增能力）

- `EXC_IRQn`
- `Ecall_M_Mode_IRQn`
- `Ecall_U_Mode_IRQn`
- `Break_Point_IRQn`
- `Software_IRQn`
- `USBFS_IRQn`
- `USBFSWakeUp_IRQn`
- `DMA1_Channel8_IRQn`
- `ETH_IRQn`
- `ETHWakeUp_IRQn`
- `BB_IRQn`
- `LLE_IRQn`
- `OSC32KCal_IRQn`
- `OSCWakeUp_IRQn`

### CH32 提供的中断相关兼容别名

| STM32 写法 | CH32 头文件中的别名 |
|---|---|
| `HardFault_IRQn` | → `EXC_IRQn` |
| `ADC1_2_IRQn` | → `ADC_IRQn` |
| `SysTicK_IRQn` | → `SysTick_IRQn` |
| `USBHD_IRQn` | → `USBFS_IRQn` |
| `USBHDWakeUp_IRQn` | → `USBFSWakeUp_IRQn` |
| `USBHD_IRQHandler` | → `USBFS_IRQHandler` |
| `USBHDWakeUp_IRQHandler` | → `USBFSWakeUp_IRQHandler` |
