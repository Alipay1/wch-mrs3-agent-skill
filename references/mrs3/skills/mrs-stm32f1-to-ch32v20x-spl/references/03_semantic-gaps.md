# 语义差异清单（同名不同值 / 仅单侧存在）

> 本文件收录**无法靠单纯改名解决**的差异。
> ⚠ 关键前提：「同名」不等于「同义」，也**不等于「危险」**——
> 目标库若在实现层面对该编码做了配套处理，或提供了兼容别名，
> 那么沿用宏名即可得到正确行为，**不需要改动用户代码**。
> 下表判定列已逐项核对目标库源码，不要跳过判定直接改。

## 一、同名不同值

### 寄存器 · 位定义 / 基址（设备头）

| 模块 | 符号 | STM32 取值 | CH32 取值 | 判定 | 说明 |
|---|---|---|---|---|---|
| rcc | `HSE_STARTUP_TIMEOUT` | `((uint16_t)0x0500)` | `((uint16_t)0x1000)` | ✅ 库内自洽 | 仅起振等待上限不同，较长的一侧更宽松，无行为风险 |

小计：**1** 项。

> **`HSE_VALUE` / `HSI_VALUE` 不在此表 —— 本型号下两侧取值相同**（均为 `8000000`）。
> STM32 把 `STM32F10X_CL` 专用的 25 MHz 分支写在 `#else` 之前、CH32 把 D8 / D8W 的
> 32 MHz 分支写在外层，**只读源码头几行会误判成两侧晶振不同**。
> 两个宏在两侧都可被工程预定义覆盖，**以用户板实际晶振为准** —— 这一点比宏值本身更重要。

### 宏 · 功能宏（模块头）

| 模块 | 符号 | STM32 取值 | CH32 取值 | 判定 | 说明 |
|---|---|---|---|---|---|
| gpio | `GPIO_Remap_PD01` | `((uint32_t)0x00008000)` | `GPIO_Remap_PD0PD1` | ✅ 兼容别名 | CH32 侧 `#define GPIO_Remap_PD01 GPIO_Remap_PD0PD1`，原名可编译 |
| rcc | `RCC_USBCLKSource_PLLCLK_Div1` | `((uint8_t)0x01)` | `((uint8_t)0x00)` | 🔴 语义已变 | STM32=0x01（0x00 留给 1.5 分频）；CH32=0x00（0x01 已是 2 分频）。用宏名等价，**但裸值 0x00/0x01 的含义互换了** |
| misc | `NVIC_PriorityGroup_1` | `((uint32_t)0x600)` | `((uint32_t)0x01)` | 🔴 语义已变 | STM32=1 位抢占/3 位子优先级；CH32=开启嵌套/1 位抢占/2 位子优先级。**编码与语义同时改变**；CH32 默认配置下只定义这一个分组宏 |
| usart | `USART_IT_ORE` | `((uint16_t)0x0360)` | `USART_IT_ORE_ER` | ✅ 兼容别名 | CH32 侧 `#define USART_IT_ORE USART_IT_ORE_ER`，原名可编译 |
| flash | `FLASH_FLAG_OPTERR` | `((uint32_t)0x00000001)` | `((uint32_t)0x80000001)` | ✅ 库内自洽 | CH32 的 `FLASH_GetFlagStatus` 对该编码有专门分支（读 OBR bit0），用宏名结果正确；⚠ 该值与 CH32 的 `FLASH_FLAG_BSY` 数值重合，禁止把宏值当数字传递 |
| pwr | `PWR_PVDLevel_2V2` | `((uint32_t)0x00000000)` | `PWR_PVDLevel_MODE0` | ✅ 兼容别名 | CH32 侧 `#define PWR_PVDLevel_2V2 PWR_PVDLevel_MODE0`，档位值一致 |
| pwr | `PWR_PVDLevel_2V3` | `((uint32_t)0x00000020)` | `PWR_PVDLevel_MODE1` | ✅ 兼容别名 | 同上 |
| pwr | `PWR_PVDLevel_2V4` | `((uint32_t)0x00000040)` | `PWR_PVDLevel_MODE2` | ✅ 兼容别名 | 同上 |
| pwr | `PWR_PVDLevel_2V5` | `((uint32_t)0x00000060)` | `PWR_PVDLevel_MODE3` | ✅ 兼容别名 | 同上 |
| pwr | `PWR_PVDLevel_2V6` | `((uint32_t)0x00000080)` | `PWR_PVDLevel_MODE4` | ✅ 兼容别名 | 同上 |
| pwr | `PWR_PVDLevel_2V7` | `((uint32_t)0x000000A0)` | `PWR_PVDLevel_MODE5` | ✅ 兼容别名 | 同上 |
| pwr | `PWR_PVDLevel_2V8` | `((uint32_t)0x000000C0)` | `PWR_PVDLevel_MODE6` | ✅ 兼容别名 | 同上 |
| pwr | `PWR_PVDLevel_2V9` | `((uint32_t)0x000000E0)` | `PWR_PVDLevel_MODE7` | ✅ 兼容别名 | 同上 |
| dbgmcu | `DBGMCU_CAN1_STOP` | `((uint32_t)0x00004000)` | `((uint32_t)0x00100000)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |
| dbgmcu | `DBGMCU_I2C1_SMBUS_TIMEOUT` | `((uint32_t)0x00008000)` | `((uint32_t)0x00000400)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |
| dbgmcu | `DBGMCU_I2C2_SMBUS_TIMEOUT` | `((uint32_t)0x00010000)` | `((uint32_t)0x00000800)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |
| dbgmcu | `DBGMCU_TIM1_STOP` | `((uint32_t)0x00000400)` | `((uint32_t)0x00001000)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |
| dbgmcu | `DBGMCU_TIM2_STOP` | `((uint32_t)0x00000800)` | `((uint32_t)0x00002000)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |
| dbgmcu | `DBGMCU_TIM3_STOP` | `((uint32_t)0x00001000)` | `((uint32_t)0x00004000)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |
| dbgmcu | `DBGMCU_TIM4_STOP` | `((uint32_t)0x00002000)` | `((uint32_t)0x00008000)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |
| dbgmcu | `DBGMCU_TIM5_STOP` | `((uint32_t)0x00040000)` | `((uint32_t)0x00010000)` | ✅ 库内自洽 | 位位置重排但宏名保留，用宏名调用 `DBGMCU_Config` 结果正确；**禁止沿用 STM32 手册里的位掩码数值** |

小计：**21** 项。

> 合计 **22** 项：✅ 兼容别名 10 ／ ✅ 库内自洽 10 ／ 🔴 语义已变 2 ／ 🟠 需确认 0。

**真正需要人工重做的只有 🔴 与 🟠 这两类，逐项处理方式见 `references/05_migration-rules.md` 第三节。**

## 二、CH32 侧被改写为「符号引用」的宏

下列宏在 CH32 侧不再直接给出数值字面量，而是指向同族内另一个宏 —— 
这是 WCH 为兼容旧代码特意保留的别名，**原名可以直接编译通过**。

| 模块 | 符号 | STM32 取值 | CH32 取值 |
|---|---|---|---|
| gpio | `GPIO_Remap_PD01` | `((uint32_t)0x00008000)` | `GPIO_Remap_PD0PD1` |
| usart | `USART_IT_ORE` | `((uint16_t)0x0360)` | `USART_IT_ORE_ER` |
| pwr | `PWR_PVDLevel_2V2` | `((uint32_t)0x00000000)` | `PWR_PVDLevel_MODE0` |
| pwr | `PWR_PVDLevel_2V3` | `((uint32_t)0x00000020)` | `PWR_PVDLevel_MODE1` |
| pwr | `PWR_PVDLevel_2V4` | `((uint32_t)0x00000040)` | `PWR_PVDLevel_MODE2` |
| pwr | `PWR_PVDLevel_2V5` | `((uint32_t)0x00000060)` | `PWR_PVDLevel_MODE3` |
| pwr | `PWR_PVDLevel_2V6` | `((uint32_t)0x00000080)` | `PWR_PVDLevel_MODE4` |
| pwr | `PWR_PVDLevel_2V7` | `((uint32_t)0x000000A0)` | `PWR_PVDLevel_MODE5` |
| pwr | `PWR_PVDLevel_2V8` | `((uint32_t)0x000000C0)` | `PWR_PVDLevel_MODE6` |
| pwr | `PWR_PVDLevel_2V9` | `((uint32_t)0x000000E0)` | `PWR_PVDLevel_MODE7` |

设备头与模块头中**全部**此类别名的完整清单另见第四节。

## 三、CH32 侧全部兼容别名（目标库为旧代码保留的名字）

这些别名意味着：**用户代码里的 STM32 原名在 CH32 上依然有效**，
不需要为了兼容而改名。清单由扫描 CH32 头文件中的「宏体为单一标识符」定义得出。

### ch32v20x.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `ADC1_2_IRQn` | `ADC_IRQn` |
| `HSEStartUp_TimeOut` | `HSE_STARTUP_TIMEOUT` |
| `HSE_Value` | `HSE_VALUE` |
| `HSI_Value` | `HSI_VALUE` |
| `HardFault_IRQn` | `EXC_IRQn` |
| `PWR_CTLR_PLS_2V2` | `PWR_CTLR_PLS_MODE0` |
| `PWR_CTLR_PLS_2V3` | `PWR_CTLR_PLS_MODE1` |
| `PWR_CTLR_PLS_2V4` | `PWR_CTLR_PLS_MODE2` |
| `PWR_CTLR_PLS_2V5` | `PWR_CTLR_PLS_MODE3` |
| `PWR_CTLR_PLS_2V6` | `PWR_CTLR_PLS_MODE4` |
| `PWR_CTLR_PLS_2V7` | `PWR_CTLR_PLS_MODE5` |
| `PWR_CTLR_PLS_2V8` | `PWR_CTLR_PLS_MODE6` |
| `PWR_CTLR_PLS_2V9` | `PWR_CTLR_PLS_MODE7` |
| `RCC_USBHD` | `RCC_USBFS` |
| `SysTicK_IRQn` | `SysTick_IRQn` |
| `USBHDWakeUp_IRQHandler` | `USBFSWakeUp_IRQHandler` |
| `USBHDWakeUp_IRQn` | `USBFSWakeUp_IRQn` |
| `USBHD_IRQHandler` | `USBFS_IRQHandler` |
| `USBHD_IRQn` | `USBFS_IRQn` |
| `USBOTG_FS` | `USBFSD` |
| `USBOTG_H_FS` | `USBFSH` |

### ch32v20x_can.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `CANINITFAILED` | `CAN_InitStatus_Failed` |
| `CANINITOK` | `CAN_InitStatus_Success` |
| `CANSLEEPFAILED` | `CAN_Sleep_Failed` |
| `CANSLEEPOK` | `CAN_Sleep_Ok` |
| `CANTXFAILE` | `CAN_TxStatus_Failed` |
| `CANTXOK` | `CAN_TxStatus_Ok` |
| `CANTXPENDING` | `CAN_TxStatus_Pending` |
| `CANWAKEUPFAILED` | `CAN_WakeUp_Failed` |
| `CANWAKEUPOK` | `CAN_WakeUp_Ok` |
| `CAN_FilterFIFO0` | `CAN_Filter_FIFO0` |
| `CAN_FilterFIFO1` | `CAN_Filter_FIFO1` |
| `CAN_ID_EXT` | `CAN_Id_Extended` |
| `CAN_ID_STD` | `CAN_Id_Standard` |
| `CAN_IT_RQCP0` | `CAN_IT_TME` |
| `CAN_IT_RQCP1` | `CAN_IT_TME` |
| `CAN_IT_RQCP2` | `CAN_IT_TME` |
| `CAN_NO_MB` | `CAN_TxStatus_NoMailBox` |
| `CAN_RTR_DATA` | `CAN_RTR_Data` |
| `CAN_RTR_REMOTE` | `CAN_RTR_Remote` |

### ch32v20x_flash.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `FLASH_FLAG_BANK1_BSY` | `FLASH_FLAG_BSY` |
| `FLASH_FLAG_BANK1_EOP` | `FLASH_FLAG_EOP` |
| `FLASH_FLAG_BANK1_WRPRTERR` | `FLASH_FLAG_WRPRTERR` |
| `FLASH_IT_BANK1_EOP` | `FLASH_IT_EOP` |
| `FLASH_IT_BANK1_ERROR` | `FLASH_IT_ERROR` |

### ch32v20x_gpio.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `GPIO_Remap_PD01` | `GPIO_Remap_PD0PD1` |

### ch32v20x_misc.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `INTSYSCR_INEST` | `INTSYSCR_INEST_EN` |

### ch32v20x_pwr.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `PWR_PVDLevel_2V2` | `PWR_PVDLevel_MODE0` |
| `PWR_PVDLevel_2V3` | `PWR_PVDLevel_MODE1` |
| `PWR_PVDLevel_2V4` | `PWR_PVDLevel_MODE2` |
| `PWR_PVDLevel_2V5` | `PWR_PVDLevel_MODE3` |
| `PWR_PVDLevel_2V6` | `PWR_PVDLevel_MODE4` |
| `PWR_PVDLevel_2V7` | `PWR_PVDLevel_MODE5` |
| `PWR_PVDLevel_2V8` | `PWR_PVDLevel_MODE6` |
| `PWR_PVDLevel_2V9` | `PWR_PVDLevel_MODE7` |

### ch32v20x_rcc.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `RCC_AHBPeriph_OTG_FS` | `RCC_AHBPeriph_USBFS` |

### ch32v20x_tim.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `TIM_DMABurstLength_10Bytes` | `TIM_DMABurstLength_10Transfers` |
| `TIM_DMABurstLength_11Bytes` | `TIM_DMABurstLength_11Transfers` |
| `TIM_DMABurstLength_12Bytes` | `TIM_DMABurstLength_12Transfers` |
| `TIM_DMABurstLength_13Bytes` | `TIM_DMABurstLength_13Transfers` |
| `TIM_DMABurstLength_14Bytes` | `TIM_DMABurstLength_14Transfers` |
| `TIM_DMABurstLength_15Bytes` | `TIM_DMABurstLength_15Transfers` |
| `TIM_DMABurstLength_16Bytes` | `TIM_DMABurstLength_16Transfers` |
| `TIM_DMABurstLength_17Bytes` | `TIM_DMABurstLength_17Transfers` |
| `TIM_DMABurstLength_18Bytes` | `TIM_DMABurstLength_18Transfers` |
| `TIM_DMABurstLength_1Byte` | `TIM_DMABurstLength_1Transfer` |
| `TIM_DMABurstLength_2Bytes` | `TIM_DMABurstLength_2Transfers` |
| `TIM_DMABurstLength_3Bytes` | `TIM_DMABurstLength_3Transfers` |
| `TIM_DMABurstLength_4Bytes` | `TIM_DMABurstLength_4Transfers` |
| `TIM_DMABurstLength_5Bytes` | `TIM_DMABurstLength_5Transfers` |
| `TIM_DMABurstLength_6Bytes` | `TIM_DMABurstLength_6Transfers` |
| `TIM_DMABurstLength_7Bytes` | `TIM_DMABurstLength_7Transfers` |
| `TIM_DMABurstLength_8Bytes` | `TIM_DMABurstLength_8Transfers` |
| `TIM_DMABurstLength_9Bytes` | `TIM_DMABurstLength_9Transfers` |

### ch32v20x_usart.h

| 旧名（兼容保留） | 指向的名字 |
|---|---|
| `USART_IT_ORE` | `USART_IT_ORE_ER` |


## 四、参数校验宏 `IS_*`：CH32 侧整体不存在

STM32 标准外设库在每个函数入口用 `assert_param(IS_XXX(...))` 做参数合法性检查，
CH32V20x 外设库**移除了全部校验宏与校验语句**，共 **264** 个 `IS_*` 宏在 CH32 侧无定义。

| 模块 | `IS_*` 宏数 |
|---|---:|
| gpio | 11 |
| rcc | 19 |
| misc | 7 |
| tim | 61 |
| usart | 25 |
| spi | 26 |
| i2c | 18 |
| dma | 15 |
| exti | 4 |
| flash | 12 |
| adc | 21 |
| can | 23 |
| pwr | 5 |
| rtc | 5 |
| bkp | 4 |
| iwdg | 4 |
| wwdg | 3 |
| dbgmcu | 1 |

**用户代码极少直接调用 `IS_*`**，但以下情况会触发编译错误：

- 用户自定义的 `assert_param` 包装或调试宏引用了 `IS_*`；
- 用户代码显式做参数校验（如 `if (IS_GPIO_PIN(pin)) ...`）；
- 复制了 STM32 库函数体到自己文件中。

处理方式：删除校验语句，或改为等价的显式判断。**不要自行实现 `IS_*` 宏去迎合旧代码**，
目标库本身不做校验，补上会造成与目标库行为不一致。

## 五、仅 STM32 存在的函数（需放弃或改用其它方案）

| 模块 | 函数 |
|---|---|
| rcc | `RCC_AHBPeriphResetCmd` |
| rcc | `RCC_I2S2CLKConfig` |
| rcc | `RCC_I2S3CLKConfig` |
| rcc | `RCC_OTGFSCLKConfig` |
| rcc | `RCC_PLL2Cmd` |
| rcc | `RCC_PLL2Config` |
| rcc | `RCC_PLL3Cmd` |
| rcc | `RCC_PLL3Config` |
| rcc | `RCC_PREDIV1Config` |
| rcc | `RCC_PREDIV2Config` |
| misc | `NVIC_SetVectorTable` |
| misc | `NVIC_SystemLPConfig` |
| misc | `SysTick_CLKSourceConfig` |
| usart | `USART_OneBitMethodCmd` |
| usart | `USART_OverSampling8Cmd` |
| flash | `FLASH_BootConfig` |
| flash | `FLASH_EraseAllBank2Pages` |
| flash | `FLASH_GetBank2Status` |
| flash | `FLASH_GetPrefetchBufferStatus` |
| flash | `FLASH_HalfCycleAccessCmd` |
| flash | `FLASH_LockBank2` |
| flash | `FLASH_PrefetchBufferCmd` |
| flash | `FLASH_SetLatency` |
| flash | `FLASH_UnlockBank2` |
| flash | `FLASH_WaitForLastBank2Operation` |

> **flash 这一栏要分两类看：**
>
> - **必须放弃的 4 个（真正的能力缺口）**：`FLASH_SetLatency`、
>   `FLASH_HalfCycleAccessCmd`、`FLASH_PrefetchBufferCmd`、
>   `FLASH_GetPrefetchBufferStatus`。它们都写 `FLASH->ACR`，
>   而 CH32 的 `FLASH->ACTLR`（同偏移 `0x00`）**没有任何位定义**：等待周期与预取
>   搬到了 RISC-V 内核 CSR `0xBC0`，由启动文件写入并默认全开
>   （`SRC/Startup/startup_ch32v20x_D6.S` 写 `0x1F`）。
>   用户代码里这四类调用**必须整句删除**；改主频时同步改启动文件里 `0xBC0` 的初值。
>   替代关系：Flash 访问时钟由 `FLASH_Access_Clock_Cfg()` 走 `FLASH->CTLR` bit25
>   （调用前需先 `FLASH_Unlock()`）。
> - **只是不在本型号编译的 6 个**：`FLASH_UnlockBank2`、`FLASH_LockBank2`、
>   `FLASH_EraseAllBank2Pages`、`FLASH_GetBank2Status`、`FLASH_WaitForLastBank2Operation`、
>   `FLASH_BootConfig` —— 整块包在 `#ifdef STM32F10X_XL` 里，`STM32F10X_MD`
>   下**两侧都没有**，不属于缺口。列在这里只为说明「大容量双 Bank」能力未覆盖。

## 六、仅 CH32 存在的函数（可选用的新增能力）

| 模块 | 函数 |
|---|---|
| gpio | `GPIO_IPD_Unused` |
| rcc | `RCC_ADCCLKADJcmd` |
| rcc | `RCC_ETHDIVConfig` |
| rcc | `RCC_USB5PRE_JUDGE` |
| tim | `TIM5_GetCapture1` |
| tim | `TIM5_GetCapture2` |
| tim | `TIM5_GetCapture3` |
| tim | `TIM5_GetCapture4` |
| tim | `TIM5_GetCounter` |
| tim | `TIM5_OC1Init` |
| tim | `TIM5_OC2Init` |
| tim | `TIM5_OC3Init` |
| tim | `TIM5_OC4Init` |
| tim | `TIM5_OCStructInit` |
| tim | `TIM5_SetAutoreload` |
| tim | `TIM5_SetCompare1` |
| tim | `TIM5_SetCompare2` |
| tim | `TIM5_SetCompare3` |
| tim | `TIM5_SetCompare4` |
| tim | `TIM5_SetCounter` |
| tim | `TIM5_TimeBaseInit` |
| tim | `TIM5_TimeBaseStructInit` |
| flash | `FLASH_Access_Clock_Cfg` |
| flash | `FLASH_Enhance_Mode` |
| flash | `FLASH_EraseBlock_32K_Fast` |
| flash | `FLASH_ErasePage_Fast` |
| flash | `FLASH_GetMACAddress` |
| flash | `FLASH_Lock_Fast` |
| flash | `FLASH_ProgramPage_Fast` |
| flash | `FLASH_ROM_ERASE` |
| flash | `FLASH_ROM_WRITE` |
| flash | `FLASH_Unlock_Fast` |
| adc | `ADC_BufferCmd` |
| adc | `Get_CalibrationValue` |
| adc | `TempSensor_Volt_To_Temper` |
| pwr | `PWR_EnterSTANDBYMode_RAM` |
| pwr | `PWR_EnterSTANDBYMode_RAM_LV` |
| pwr | `PWR_EnterSTANDBYMode_RAM_LV_VBAT_EN` |
| pwr | `PWR_EnterSTANDBYMode_RAM_VBAT_EN` |
| pwr | `PWR_EnterSTOPMode_RAM_LV` |
| rtc | `Calibration_LSI` |
| dbgmcu | `DBGMCU_GetCHIPID` |
| dbgmcu | `__get_DEBUG_CR` |
| dbgmcu | `__set_DEBUG_CR` |

## 七、仅单侧存在的功能宏

### 仅 STM32 存在

- **gpio**（20）：`GPIO_PortSourceGPIOE`, `GPIO_PortSourceGPIOF`, `GPIO_PortSourceGPIOG`, `GPIO_Remap_CAN2`, `GPIO_Remap_CEC`, `GPIO_Remap_MISC`, `GPIO_Remap_SPI3`, `GPIO_Remap_SWJ_JTAGDisable`, `GPIO_Remap_SWJ_NoJTRST`, `GPIO_Remap_TIM10`, `GPIO_Remap_TIM11`, `GPIO_Remap_TIM12`, `GPIO_Remap_TIM13`, `GPIO_Remap_TIM14`, `GPIO_Remap_TIM15`, `GPIO_Remap_TIM16`, `GPIO_Remap_TIM17`, `GPIO_Remap_TIM1_DMA`, `GPIO_Remap_TIM67_DAC_DMA`, `GPIO_Remap_TIM9`
- **rcc**（21）：`RCC_AHBPeriph_FLITF`, `RCC_APB1Periph_CAN2`, `RCC_APB1Periph_CEC`, `RCC_APB1Periph_SPI3`, `RCC_APB1Periph_TIM12`, `RCC_APB1Periph_TIM13`, `RCC_APB1Periph_TIM14`, `RCC_APB1Periph_TIM6`, `RCC_APB1Periph_TIM7`, `RCC_APB1Periph_UART5`, `RCC_APB2Periph_ADC3`, `RCC_APB2Periph_GPIOE`, `RCC_APB2Periph_GPIOF`, `RCC_APB2Periph_GPIOG`, `RCC_APB2Periph_TIM10`, `RCC_APB2Periph_TIM11`, `RCC_APB2Periph_TIM15`, `RCC_APB2Periph_TIM16`, `RCC_APB2Periph_TIM17`, `RCC_APB2Periph_TIM8`, `RCC_APB2Periph_TIM9`
- **misc**（11）：`NVIC_LP_SEVONPEND`, `NVIC_LP_SLEEPDEEP`, `NVIC_LP_SLEEPONEXIT`, `NVIC_PriorityGroup_0`, `NVIC_PriorityGroup_2`, `NVIC_PriorityGroup_3`, `NVIC_PriorityGroup_4`, `NVIC_VectTab_FLASH`, `NVIC_VectTab_RAM`, `SysTick_CLKSource_HCLK`, `SysTick_CLKSource_HCLK_Div8`
- **dma**（40）：`DMA2_FLAG_GL1`, `DMA2_FLAG_GL2`, `DMA2_FLAG_GL3`, `DMA2_FLAG_GL4`, `DMA2_FLAG_GL5`, `DMA2_FLAG_HT1`, `DMA2_FLAG_HT2`, `DMA2_FLAG_HT3`, `DMA2_FLAG_HT4`, `DMA2_FLAG_HT5`, `DMA2_FLAG_TC1`, `DMA2_FLAG_TC2`, `DMA2_FLAG_TC3`, `DMA2_FLAG_TC4`, `DMA2_FLAG_TC5`, `DMA2_FLAG_TE1`, `DMA2_FLAG_TE2`, `DMA2_FLAG_TE3`, `DMA2_FLAG_TE4`, `DMA2_FLAG_TE5`, `DMA2_IT_GL1`, `DMA2_IT_GL2`, `DMA2_IT_GL3`, `DMA2_IT_GL4`, `DMA2_IT_GL5`, `DMA2_IT_HT1`, `DMA2_IT_HT2`, `DMA2_IT_HT3`, `DMA2_IT_HT4`, `DMA2_IT_HT5`, `DMA2_IT_TC1`, `DMA2_IT_TC2`, `DMA2_IT_TC3`, `DMA2_IT_TC4`, `DMA2_IT_TC5`, `DMA2_IT_TE1`, `DMA2_IT_TE2`, `DMA2_IT_TE3`, `DMA2_IT_TE4`, `DMA2_IT_TE5`
- **flash**（72）：`FLASH_FLAG_BANK1_PGERR`, `FLASH_FLAG_PGERR`, `FLASH_HalfCycleAccess_Disable`, `FLASH_HalfCycleAccess_Enable`, `FLASH_Latency_0`, `FLASH_Latency_1`, `FLASH_Latency_2`, `FLASH_PrefetchBuffer_Disable`, `FLASH_PrefetchBuffer_Enable`, `FLASH_WRProt_Pages0to1`, `FLASH_WRProt_Pages0to3`, `FLASH_WRProt_Pages104to107`, `FLASH_WRProt_Pages108to111`, `FLASH_WRProt_Pages10to11`, `FLASH_WRProt_Pages112to115`, `FLASH_WRProt_Pages116to119`, `FLASH_WRProt_Pages120to123`, `FLASH_WRProt_Pages12to13`, `FLASH_WRProt_Pages12to15`, `FLASH_WRProt_Pages14to15`, `FLASH_WRProt_Pages16to17`, `FLASH_WRProt_Pages16to19`, `FLASH_WRProt_Pages18to19`, `FLASH_WRProt_Pages20to21`, `FLASH_WRProt_Pages20to23`, `FLASH_WRProt_Pages22to23`, `FLASH_WRProt_Pages24to25`, `FLASH_WRProt_Pages24to27`, `FLASH_WRProt_Pages26to27`, `FLASH_WRProt_Pages28to29`, `FLASH_WRProt_Pages28to31`, `FLASH_WRProt_Pages2to3`, `FLASH_WRProt_Pages30to31`, `FLASH_WRProt_Pages32to33`, `FLASH_WRProt_Pages32to35`, `FLASH_WRProt_Pages34to35`, `FLASH_WRProt_Pages36to37`, `FLASH_WRProt_Pages36to39`, `FLASH_WRProt_Pages38to39`, `FLASH_WRProt_Pages40to41`, `FLASH_WRProt_Pages40to43`, `FLASH_WRProt_Pages42to43`, `FLASH_WRProt_Pages44to45`, `FLASH_WRProt_Pages44to47`, `FLASH_WRProt_Pages46to47`, `FLASH_WRProt_Pages48to49`, `FLASH_WRProt_Pages48to51`, `FLASH_WRProt_Pages4to5`, `FLASH_WRProt_Pages4to7`, `FLASH_WRProt_Pages52to53`, `FLASH_WRProt_Pages52to55`, `FLASH_WRProt_Pages54to55`, `FLASH_WRProt_Pages56to57`, `FLASH_WRProt_Pages56to59`, `FLASH_WRProt_Pages58to59`, `FLASH_WRProt_Pages60to61`, `FLASH_WRProt_Pages60to63`, `FLASH_WRProt_Pages62to127`, `FLASH_WRProt_Pages62to255`, `FLASH_WRProt_Pages62to511`, `FLASH_WRProt_Pages64to67`, `FLASH_WRProt_Pages68to71`, `FLASH_WRProt_Pages6to7`, `FLASH_WRProt_Pages72to75`, `FLASH_WRProt_Pages76to79`, `FLASH_WRProt_Pages80to83`, `FLASH_WRProt_Pages84to87`, `FLASH_WRProt_Pages88to91`, `FLASH_WRProt_Pages8to11`, `FLASH_WRProt_Pages8to9`, `FLASH_WRProt_Pages92to95`, `FLASH_WRProt_Pages96to99`
- **adc**（6）：`ADC_ExternalTrigConv_T2_CC3`, `ADC_ExternalTrigConv_T3_CC1`, `ADC_ExternalTrigConv_T5_CC1`, `ADC_ExternalTrigConv_T5_CC3`, `ADC_ExternalTrigConv_T8_CC1`, `ADC_ExternalTrigConv_T8_TRGO`
- **dbgmcu**（13）：`DBGMCU_CAN2_STOP`, `DBGMCU_TIM10_STOP`, `DBGMCU_TIM11_STOP`, `DBGMCU_TIM12_STOP`, `DBGMCU_TIM13_STOP`, `DBGMCU_TIM14_STOP`, `DBGMCU_TIM15_STOP`, `DBGMCU_TIM16_STOP`, `DBGMCU_TIM17_STOP`, `DBGMCU_TIM6_STOP`, `DBGMCU_TIM7_STOP`, `DBGMCU_TIM8_STOP`, `DBGMCU_TIM9_STOP`

### 仅 CH32 存在

- **gpio**（5）：`GPIO_FullRemap_USART4`, `GPIO_PartialRemap_USART4`, `GPIO_Remap_MII_RMII_SEL`, `GPIO_Remap_PD0PD1`, `GPIO_Remap_USART1_HighBit`
- **rcc**（16）：`RCC_AHBPeriph_OTG_FS`, `RCC_AHBPeriph_RNG`, `RCC_AHBPeriph_USBFS`, `RCC_AHBPeriph_USBHS`, `RCC_PLLMul_18`, `RCC_USBCLKSource_PLLCLK_Div2`, `RCC_USBCLKSource_PLLCLK_Div3`, `RCC_USBPLL_Div2`, `RCC_USBPLL_Div3`, `RCC_USBPLL_Div4`, `RCC_USBPLL_Div5`, `RCC_USBPLL_Div6`, `RCC_USBPLL_Div7`, `RCC_USBPLL_Div8`, `SysTick_CLKSource_HCLK`, `SysTick_CLKSource_HCLK_Div8`
- **misc**（3）：`INTSYSCR_INEST`, `INTSYSCR_INEST_EN`, `INTSYSCR_INEST_NoEN`
- **usart**（2）：`USART_IT_ORE_ER`, `USART_IT_ORE_RX`
- **dma**（8）：`DMA1_FLAG_GL8`, `DMA1_FLAG_HT8`, `DMA1_FLAG_TC8`, `DMA1_FLAG_TE8`, `DMA1_IT_GL8`, `DMA1_IT_HT8`, `DMA1_IT_TC8`, `DMA1_IT_TE8`
- **exti**（1）：`EXTI_Line20`
- **flash**（31）：`FLASH_Access_SYSTEM_HALF`, `FLASH_WRProt_Sectors0`, `FLASH_WRProt_Sectors1`, `FLASH_WRProt_Sectors10`, `FLASH_WRProt_Sectors11`, `FLASH_WRProt_Sectors12`, `FLASH_WRProt_Sectors13`, `FLASH_WRProt_Sectors14`, `FLASH_WRProt_Sectors15`, `FLASH_WRProt_Sectors16`, `FLASH_WRProt_Sectors17`, `FLASH_WRProt_Sectors18`, `FLASH_WRProt_Sectors19`, `FLASH_WRProt_Sectors2`, `FLASH_WRProt_Sectors20`, `FLASH_WRProt_Sectors21`, `FLASH_WRProt_Sectors22`, `FLASH_WRProt_Sectors23`, `FLASH_WRProt_Sectors24`, `FLASH_WRProt_Sectors26`, `FLASH_WRProt_Sectors27`, `FLASH_WRProt_Sectors28`, `FLASH_WRProt_Sectors29`, `FLASH_WRProt_Sectors3`, `FLASH_WRProt_Sectors30`, `FLASH_WRProt_Sectors4`, `FLASH_WRProt_Sectors5`, `FLASH_WRProt_Sectors6`, `FLASH_WRProt_Sectors7`, `FLASH_WRProt_Sectors8`, `FLASH_WRProt_Sectors9`
- **adc**（6）：`ADC_OutputBuffer_Disable`, `ADC_OutputBuffer_Enable`, `ADC_Pga_1`, `ADC_Pga_16`, `ADC_Pga_4`, `ADC_Pga_64`
- **pwr**（8）：`PWR_PVDLevel_MODE0`, `PWR_PVDLevel_MODE1`, `PWR_PVDLevel_MODE2`, `PWR_PVDLevel_MODE3`, `PWR_PVDLevel_MODE4`, `PWR_PVDLevel_MODE5`, `PWR_PVDLevel_MODE6`, `PWR_PVDLevel_MODE7`

> **两个容易误读的条目：**
>
> - **`RCC_AHBPeriph_OTG_FS` 出现在「仅 CH32」是型号口径的结果。** STM32 侧它是
>   `STM32F10X_CL` 专用（`0x1000`，OTG 全速），`STM32F10X_MD` 下不存在；
>   CH32 侧写成 `#define RCC_AHBPeriph_OTG_FS RCC_AHBPeriph_USBFS`，
>   **是保留给旧代码的兼容别名，不是新能力**。
> - 同理，STM32 侧的 `RCC_AHBPeriph_ETH_MAC*`、`RCC_APB1Periph_CAN2` /
>   `CEC` / `SPI3` / `UART5`、`RCC_APB2Periph_GPIOE~G`、`RCC_PREDIV*` /
>   `RCC_PLL2*` / `RCC_PLL3*` 等 60 余项属 CL / XL 专用，
>   **在本口径下不列入「仅 STM32」** —— 它们对应的外设 CH32V203 本来就没有。

### flash 补充（按设备头逐项复核后的追加与更正）

上面各模块的清单由符号比对管线生成；flash 部分经**设备头逐项复核**后补充如下，
`FLASH_WRProt_*` 一组另需按下方的粒度说明处理。

| 符号 | 取值 | 类别 | 说明 |
|---|---|---|---|
| `FLASH_CTLR_FAST_LOCK` | `((uint32_t)0x00008000)` | 设备头位定义 | 快速模式下锁定，STM32 无 |
| `FLASH_CTLR_PAGE_PG` | `((uint32_t)0x00010000)` | 设备头位定义 | 256 字节页编程，STM32 无 |
| `FLASH_CTLR_PAGE_ER` | `((uint32_t)0x00020000)` | 设备头位定义 | 256 字节页擦除，STM32 无 |
| `FLASH_CTLR_PAGE_BER32` | `((uint32_t)0x00040000)` | 设备头位定义 | 32 KB 块擦除，STM32 无 |
| `FLASH_CTLR_PG_STRT` | `((uint32_t)0x00200000)` | 设备头位定义 | 页编程启动，STM32 无 |
| `FLASH_Access_SYSTEM` | `((uint32_t)0x02000000)` | 模块头宏 | 与 `FLASH_Access_SYSTEM_HALF`(`0x0`) 同组，写 `FLASH->CTLR` bit25 |
| `FLASH_WRProt_Sectors25` | `((uint32_t)0x02000000)` | 模块头宏 | 补齐上面的 Sector 清单 |
| `FLASH_WRProt_Sectors31to127` | `((uint32_t)0x80000000)` | 模块头宏 | 保护第 31 个及之后全部 sector |
| `FLASH_WRProt_AllSectors` | `((uint32_t)0xFFFFFFFF)` | 模块头宏 | STM32 侧对应物是 `FLASH_WRProt_AllPages`，两侧同值 |

> **`FLASH_WRProt_*` 这一组「不能按宏名对应」，按粒度理解。**
>
> - STM32（67 条）**按页**，且把三种容量的分档全列在同一组里，
>   **同一时刻只有一套有效**：大容量档每 4 页一位（`Pages0to3`…`Pages124to127`）、
>   中容量档每 2 页一位（`Pages0to1`…`Pages60to61` + `Pages62to127`）、
>   以及按容量补齐的 `Pages62to255` / `Pages62to511`。
> - CH32（33 条）**只按 4 KB sector**，粒度固定、无密度分档。
> - 因此：`FLASH_WRProt_Pages4n..4n+3`（大容量档，bit n，覆盖 4 KB）
>   ↔ `FLASH_WRProt_Sectors n`，**这是唯一能一一对上的一套**；
>   中容量档的 `Pages0to1`（bit0，覆盖 2 KB）落到 `Sectors0` 会**多保护 2 KB**。
> - 两侧「第 N 位」的位位置相同、覆盖范围不同，**照搬宏名会静默扩大保护范围**，
>   编译期无任何提示。
