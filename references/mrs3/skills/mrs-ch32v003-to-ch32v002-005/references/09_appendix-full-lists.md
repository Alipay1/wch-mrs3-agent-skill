# 09 附录：全量差异清单

由脚本扫描两侧 `Peripheral/inc/*.h` + `Core/*.h` 机器生成。
统计：宏 —— V003 侧 2073 / 目标侧 2292 / 共有 1890；函数 —— V003 侧 346 / 目标侧 372 / 共有 323。

> 本文件是明细备查。日常迁移按 `02` / `03` 的分类表处理，不必逐条读这里。

## A. 仅 V003 有的宏（183 条）—— 目标侧报未声明

```
ADC_CAL                         ADC_CALVOLSELECT                ADC_CALVOLSELECT_0              ADC_CALVOLSELECT_1
ADC_CALVOL_50PERCENT            ADC_CALVOL_75PERCENT            ADC_Channel_Vcalint             ADC_DLYR_DLYSRC
ADC_DLYR_DLYVLU                 ADC_ExternalTrigConv_Ext_PD3_PC2  ADC_ExternalTrigInjecConv_Ext_PD1_PA2  ADC_ExternalTrigInjec_DLY
ADC_ExternalTrigRegul_DLY       ADC_RSTCAL                      ADC_SMP10                       ADC_SMP10_0
ADC_SMP10_1                     ADC_SMP10_2                     ADC_SMP11                       ADC_SMP11_0
ADC_SMP11_1                     ADC_SMP11_2                     ADC_SMP12                       ADC_SMP12_0
ADC_SMP12_1                     ADC_SMP12_2                     ADC_SMP13                       ADC_SMP13_0
ADC_SMP13_1                     ADC_SMP13_2                     ADC_SMP14                       ADC_SMP14_0
ADC_SMP14_1                     ADC_SMP14_2                     ADC_SMP15                       ADC_SMP15_0
ADC_SMP15_1                     ADC_SMP15_2                     ADC_SampleTime_15Cycles         ADC_SampleTime_241Cycles
ADC_SampleTime_30Cycles         ADC_SampleTime_3Cycles          ADC_SampleTime_43Cycles         ADC_SampleTime_57Cycles
ADC_SampleTime_73Cycles         ADC_SampleTime_9Cycles          AFIO_PCFR1_ADC1_ETRGINJ_REMAP   AFIO_PCFR1_ADC1_ETRGREG_REMAP
AFIO_PCFR1_I2C1_HIGH_BIT_REMAP  AFIO_PCFR1_PA12_REMAP           AFIO_PCFR1_SWJ_CFG_DISABLE      AFIO_PCFR1_SWJ_CFG_JTAGDISABLE
AFIO_PCFR1_SWJ_CFG_NOJNTRST     AFIO_PCFR1_SWJ_CFG_RESET        AFIO_PCFR1_TIM1_1_RM            AFIO_PCFR1_TIM1_REMAP_FULLREMAP
AFIO_PCFR1_TIM1_REMAP_NOREMAP   AFIO_PCFR1_TIM1_REMAP_PARTIALREMAP  AFIO_PCFR1_TIM1_REMAP_PARTIALREMAP_1  AFIO_PCFR1_TIM2_REMAP_FULLREMAP
AFIO_PCFR1_TIM2_REMAP_NOREMAP   AFIO_PCFR1_TIM2_REMAP_PARTIALREMAP1  AFIO_PCFR1_TIM2_REMAP_PARTIALREMAP2  AFIO_PCFR1_USART1_HIGH_BIT_REMAP
AHBPERIPH_BASE                  APB1PERIPH_BASE                 APB2PERIPH_BASE                 CFG0_PLL_TRIM
EXTEN_LDO_TRIM                  EXTEN_OPA_EN                    EXTEN_OPA_NSEL                  EXTEN_OPA_PSEL
FLASH_BOOT_MODEKEYR_KEY1        FLASH_BOOT_MODEKEYR_KEY2        FLASH_CTLR_OPTPG                FLASH_CTLR_PG
FLASH_FLAG_BANK1_EOP            FLASH_IT_BANK1_EOP              FLASH_IT_BANK1_ERROR            FLASH_MODEKEYR_KEY1
FLASH_MODEKEYR_KEY2             FLASH_OBR_FIX_11                FLASH_OBR_STANDY_RST            FLASH_OBR_nRST_STOP
FLASH_STATR_LOCK                FLASH_STATR_MODE                FLASH_WRProt_Pages0to15         FLASH_WRProt_Pages112to127
FLASH_WRProt_Pages128to143      FLASH_WRProt_Pages144to159      FLASH_WRProt_Pages160to175      FLASH_WRProt_Pages16to31
FLASH_WRProt_Pages176to191      FLASH_WRProt_Pages192to207      FLASH_WRProt_Pages208to223      FLASH_WRProt_Pages224to239
FLASH_WRProt_Pages240to255      FLASH_WRProt_Pages32to47        FLASH_WRProt_Pages48to63        FLASH_WRProt_Pages64to79
FLASH_WRProt_Pages80to95        FLASH_WRProt_Pages96to111       GPIO_FullRemap_I2C1             GPIO_PartialRemap_I2C1
GPIO_Remap_PA1PA2               GPIO_Remap_SPI1                 GPIO_Speed_50MHz                HardFault_IRQn
I2S_FLAG_CHSIDE                 I2S_FLAG_UDR                    I2S_IT_UDR                      OB_STOP_NoRST
OB_STOP_RST                     PWR_AWUCSR_AWUEN                PWR_AWUPSC_1024                 PWR_AWUPSC_10240
PWR_AWUPSC_128                  PWR_AWUPSC_16                   PWR_AWUPSC_2048                 PWR_AWUPSC_256
PWR_AWUPSC_32                   PWR_AWUPSC_4                    PWR_AWUPSC_4096                 PWR_AWUPSC_512
PWR_AWUPSC_61440                PWR_AWUPSC_64                   PWR_AWUPSC_8                    PWR_CTLR_PLS_2
PWR_PVDLevel_2V9                PWR_PVDLevel_3V1                PWR_PVDLevel_3V3                PWR_PVDLevel_3V5
PWR_PVDLevel_3V7                PWR_PVDLevel_3V9                PWR_PVDLevel_4                  PWR_PVDLevel_4V1
PWR_PVDLevel_4V4                PWR_PVDLevel_5                  PWR_PVDLevel_6                  PWR_PVDLevel_7
PWR_PVDLevel_MODE0              PWR_PVDLevel_MODE1              PWR_PVDLevel_MODE2              PWR_PVDLevel_MODE3
PWR_PVDLevel_MODE4              PWR_PVDLevel_MODE5              PWR_PVDLevel_MODE6              PWR_PVDLevel_MODE7
RCC_AHBPeriph_DMA1              RCC_AHBPeriph_SRAM              RCC_APB1Periph_I2C1             RCC_APB1Periph_PWR
RCC_APB1Periph_TIM2             RCC_APB1Periph_WWDG             RCC_APB2Periph_ADC1             RCC_APB2Periph_AFIO
RCC_APB2Periph_GPIOA            RCC_APB2Periph_GPIOC            RCC_APB2Periph_GPIOD            RCC_APB2Periph_SPI1
RCC_APB2Periph_TIM1             RCC_APB2Periph_USART1           RCC_FLAG_LPWRRST                RCC_LPWRRSTF
SPI_STATR_CHSIDE                SPI_STATR_UDR                   USART_CPHA_1Edge                USART_CPHA_2Edge
USART_CPOL_High                 USART_CPOL_Low                  USART_CTLR2_CLKEN               USART_CTLR2_CPHA
USART_CTLR2_CPOL                USART_CTLR2_LBCL                USART_CTLR3_NACK                USART_CTLR3_SCEN
USART_Clock_Disable             USART_Clock_Enable              USART_GPR_GT                    USART_LastBit_Disable
USART_LastBit_Enable            VENDOR_CFG0_BASE                _WFE_
```

## B. 同名异值宏（98 条）—— 编译器零提示

| 宏 | V003 值 | 目标侧值 |
|---|---|---|
| `ADC1_BASE` | `(APB2PERIPH_BASE + 0x2400)` | `(PB2PERIPH_BASE + 0x2400)` |
| `ADC_HT` | `((uint16_t)0x03FF)` | `((uint16_t)0x0FFF)` |
| `ADC_JOFFSET1` | `((uint16_t)0x03FF)` | `((uint16_t)0x0FFF)` |
| `ADC_JOFFSET2` | `((uint16_t)0x03FF)` | `((uint16_t)0x0FFF)` |
| `ADC_JOFFSET3` | `((uint16_t)0x03FF)` | `((uint16_t)0x0FFF)` |
| `ADC_JOFFSET4` | `((uint16_t)0x03FF)` | `((uint16_t)0x0FFF)` |
| `ADC_LT` | `((uint16_t)0x03FF)` | `((uint16_t)0x0FFF)` |
| `ADC_RDATAR_DATA` | `((uint32_t)0xFFFFFFFF)` | `((uint32_t)0x0000FFFF)` |
| `AFIO_BASE` | `(APB2PERIPH_BASE + 0x0000)` | `(PB2PERIPH_BASE + 0x0000)` |
| `AFIO_PCFR1_I2C1_REMAP` | `((uint32_t)0x00000002)` | `((uint32_t)0x00000038)` |
| `AFIO_PCFR1_SPI1_REMAP` | `((uint32_t)0x00000001)` | `((uint32_t)0x00000007)` |
| `AFIO_PCFR1_TIM1_REMAP` | `((uint32_t)0x000000C0)` | `((uint32_t)0x00003C00)` |
| `AFIO_PCFR1_TIM1_REMAP_0` | `((uint32_t)0x00000040)` | `((uint32_t)0x00000400)` |
| `AFIO_PCFR1_TIM1_REMAP_1` | `((uint32_t)0x00000080)` | `((uint32_t)0x00000800)` |
| `AFIO_PCFR1_TIM2_REMAP` | `((uint32_t)0x00000300)` | `((uint32_t)0x0001C000)` |
| `AFIO_PCFR1_TIM2_REMAP_0` | `((uint32_t)0x00000100)` | `((uint32_t)0x00004000)` |
| `AFIO_PCFR1_TIM2_REMAP_1` | `((uint32_t)0x00000200)` | `((uint32_t)0x00008000)` |
| `AFIO_PCFR1_USART1_REMAP` | `((uint32_t)0x00000004)` | `((uint32_t)0x000003C0)` |
| `DBGMCU_IWDG_STOP` | `((uint32_t)0x00000001)` | `((uint32_t)0x00000100)` |
| `DBGMCU_TIM1_STOP` | `((uint32_t)0x00000010)` | `((uint32_t)0x00001000)` |
| `DBGMCU_TIM2_STOP` | `((uint32_t)0x00000020)` | `((uint32_t)0x00002000)` |
| `DBGMCU_WWDG_STOP` | `((uint32_t)0x00000002)` | `((uint32_t)0x00000200)` |
| `DMA1_BASE` | `(AHBPERIPH_BASE + 0x0000)` | `(HBPERIPH_BASE + 0x0000)` |
| `DMA1_Channel1_BASE` | `(AHBPERIPH_BASE + 0x0008)` | `(HBPERIPH_BASE + 0x0008)` |
| `DMA1_Channel2_BASE` | `(AHBPERIPH_BASE + 0x001C)` | `(HBPERIPH_BASE + 0x001C)` |
| `DMA1_Channel3_BASE` | `(AHBPERIPH_BASE + 0x0030)` | `(HBPERIPH_BASE + 0x0030)` |
| `DMA1_Channel4_BASE` | `(AHBPERIPH_BASE + 0x0044)` | `(HBPERIPH_BASE + 0x0044)` |
| `DMA1_Channel5_BASE` | `(AHBPERIPH_BASE + 0x0058)` | `(HBPERIPH_BASE + 0x0058)` |
| `DMA1_Channel6_BASE` | `(AHBPERIPH_BASE + 0x006C)` | `(HBPERIPH_BASE + 0x006C)` |
| `DMA1_Channel7_BASE` | `(AHBPERIPH_BASE + 0x0080)` | `(HBPERIPH_BASE + 0x0080)` |
| `EXTEN_BASE` | `((uint32_t)0x40023800)` | `(HBPERIPH_BASE + 0x3800)` |
| `EXTI_BASE` | `(APB2PERIPH_BASE + 0x0400)` | `(PB2PERIPH_BASE + 0x0400)` |
| `FLASH_FLAG_OPTERR` | `((uint32_t)0x00000001)` | `((uint32_t)0x80000001)` |
| `FLASH_OBR_USER` | `((uint16_t)0x03FC)` | `((uint16_t)0x00F4)` |
| `FLASH_R_BASE` | `(AHBPERIPH_BASE + 0x2000)` | `(HBPERIPH_BASE + 0x2000)` |
| `FLASH_WRProt_AllPages` | `((uint32_t)0x0000FFFF)` | `((uint32_t)0xFFFFFFFF)` |
| `GPIOA_BASE` | `(APB2PERIPH_BASE + 0x0800)` | `(PB2PERIPH_BASE + 0x0800)` |
| `GPIOC_BASE` | `(APB2PERIPH_BASE + 0x1000)` | `(PB2PERIPH_BASE + 0x1000)` |
| `GPIOD_BASE` | `(APB2PERIPH_BASE + 0x1400)` | `(PB2PERIPH_BASE + 0x1400)` |
| `GPIO_CFGLR_MODE` | `((uint32_t)0x33333333)` | `((uint32_t)0x11111111)` |
| `GPIO_CFGLR_MODE0` | `((uint32_t)0x00000003)` | `((uint32_t)0x00000001)` |
| `GPIO_CFGLR_MODE0_0` | `((uint32_t)0x00000001)` | `((uint32_t)0x00000000)` |
| `GPIO_CFGLR_MODE0_1` | `((uint32_t)0x00000002)` | `((uint32_t)0x00000001)` |
| `GPIO_CFGLR_MODE1` | `((uint32_t)0x00000030)` | `((uint32_t)0x00000010)` |
| `GPIO_CFGLR_MODE1_0` | `((uint32_t)0x00000010)` | `((uint32_t)0x00000000)` |
| `GPIO_CFGLR_MODE1_1` | `((uint32_t)0x00000020)` | `((uint32_t)0x00000010)` |
| `GPIO_CFGLR_MODE2` | `((uint32_t)0x00000300)` | `((uint32_t)0x00000100)` |
| `GPIO_CFGLR_MODE2_0` | `((uint32_t)0x00000100)` | `((uint32_t)0x00000000)` |
| `GPIO_CFGLR_MODE2_1` | `((uint32_t)0x00000200)` | `((uint32_t)0x00000100)` |
| `GPIO_CFGLR_MODE3` | `((uint32_t)0x00003000)` | `((uint32_t)0x00001000)` |
| `GPIO_CFGLR_MODE3_0` | `((uint32_t)0x00001000)` | `((uint32_t)0x00000000)` |
| `GPIO_CFGLR_MODE3_1` | `((uint32_t)0x00002000)` | `((uint32_t)0x00001000)` |
| `GPIO_CFGLR_MODE4` | `((uint32_t)0x00030000)` | `((uint32_t)0x00010000)` |
| `GPIO_CFGLR_MODE4_0` | `((uint32_t)0x00010000)` | `((uint32_t)0x00000000)` |
| `GPIO_CFGLR_MODE4_1` | `((uint32_t)0x00020000)` | `((uint32_t)0x00010000)` |
| `GPIO_CFGLR_MODE5` | `((uint32_t)0x00300000)` | `((uint32_t)0x00100000)` |
| `GPIO_CFGLR_MODE5_0` | `((uint32_t)0x00100000)` | `((uint32_t)0x00000000)` |
| `GPIO_CFGLR_MODE5_1` | `((uint32_t)0x00200000)` | `((uint32_t)0x00100000)` |
| `GPIO_CFGLR_MODE6` | `((uint32_t)0x03000000)` | `((uint32_t)0x01000000)` |
| `GPIO_CFGLR_MODE6_1` | `((uint32_t)0x02000000)` | `((uint32_t)0x01000000)` |
| `GPIO_CFGLR_MODE7` | `((uint32_t)0x30000000)` | `((uint32_t)0x10000000)` |
| `GPIO_CFGLR_MODE7_0` | `((uint32_t)0x10000000)` | `((uint32_t)0x00000000)` |
| `GPIO_CFGLR_MODE7_1` | `((uint32_t)0x20000000)` | `((uint32_t)0x10000000)` |
| `GPIO_FullRemap_TIM1` | `((uint32_t)0x001600C0)` | `((uint32_t)0x001A2400)` |
| `GPIO_FullRemap_TIM2` | `((uint32_t)0x00180300)` | `((uint32_t)0x084E0007)` |
| `GPIO_FullRemap_USART1` | `((uint32_t)0x80200004)` | `((uint32_t)0x00160240)` |
| `GPIO_PartialRemap1_TIM1` | `((uint32_t)0x00160040)` | `((uint32_t)0x001A0400)` |
| `GPIO_PartialRemap1_TIM2` | `((uint32_t)0x00180100)` | `((uint32_t)0x084E0001)` |
| `GPIO_PartialRemap1_USART1` | `((uint32_t)0x80000004)` | `((uint32_t)0x00160040)` |
| `GPIO_PartialRemap2_TIM1` | `((uint32_t)0x00160080)` | `((uint32_t)0x001A0800)` |
| `GPIO_PartialRemap2_TIM2` | `((uint32_t)0x00180200)` | `((uint32_t)0x084E0002)` |
| `GPIO_PartialRemap2_USART1` | `((uint32_t)0x80200000)` | `((uint32_t)0x00160080)` |
| `GPIO_Pin_All` | `((uint16_t)0xFFFF)` | `((uint16_t)0x00FF)` |
| `GPIO_Remap_ADC1_ETRGINJ` | `((uint32_t)0x00200002)` | `((uint32_t)0x00200004)` |
| `GPIO_Remap_ADC1_ETRGREG` | `((uint32_t)0x00200004)` | `((uint32_t)0x00200008)` |
| `GPIO_Remap_LSI_CAL` | `((uint32_t)0x00200080)` | `((uint32_t)0x001A3000)` |
| `GPIO_Remap_PA1_2` | `GPIO_Remap_PA1PA2` | `((uint32_t)0x00200002)` |
| `GPIO_Remap_SDI_Disable` | `((uint32_t)0x00300400)` | `((uint32_t)0x08300400)` |
| `I2C1_BASE` | `(APB1PERIPH_BASE + 0x5400)` | `(PB1PERIPH_BASE + 0x5400)` |
| `IWDG_BASE` | `(APB1PERIPH_BASE + 0x3000)` | `(PB1PERIPH_BASE + 0x3000)` |
| `PWR_AWUPSC_0` | `((uint16_t)0x0000)` | `((uint16_t)0x0001)` |
| `PWR_AWUPSC_2` | `((uint16_t)0x0002)` | `((uint16_t)0x0004)` |
| `PWR_BASE` | `(APB1PERIPH_BASE + 0x7000)` | `(PB1PERIPH_BASE + 0x7000)` |
| `PWR_CTLR_PLS` | `((uint16_t)0x00E0)` | `((uint16_t)0x0060)` |
| `PWR_PVDLevel_0` | `((uint16_t)0x0000)` | `((uint32_t)0x00000000)` |
| `PWR_PVDLevel_1` | `((uint16_t)0x0020)` | `((uint32_t)0x00000020)` |
| `PWR_PVDLevel_2` | `((uint16_t)0x0040)` | `((uint32_t)0x00000040)` |
| `PWR_PVDLevel_3` | `((uint16_t)0x0060)` | `((uint32_t)0x00000060)` |
| `RCC_BASE` | `(AHBPERIPH_BASE + 0x1000)` | `(HBPERIPH_BASE + 0x1000)` |
| `SPI1_BASE` | `(APB2PERIPH_BASE + 0x3000)` | `(PB2PERIPH_BASE + 0x3000)` |
| `TIM1_BASE` | `(APB2PERIPH_BASE + 0x2C00)` | `(PB2PERIPH_BASE + 0x2C00)` |
| `TIM2_BASE` | `(APB1PERIPH_BASE + 0x0000)` | `(PB1PERIPH_BASE + 0x0000)` |
| `TIM_CCR1` | `((uint16_t)0xFFFF)` | `((uint32_t)0x0000FFFF)` |
| `TIM_CCR2` | `((uint16_t)0xFFFF)` | `((uint32_t)0x0000FFFF)` |
| `TIM_CCR3` | `((uint16_t)0xFFFF)` | `((uint32_t)0x0000FFFF)` |
| `TIM_CCR4` | `((uint16_t)0xFFFF)` | `((uint32_t)0x0000FFFF)` |
| `USART1_BASE` | `(APB2PERIPH_BASE + 0x3800)` | `(PB2PERIPH_BASE + 0x3800)` |
| `WWDG_BASE` | `(APB1PERIPH_BASE + 0x2C00)` | `(PB1PERIPH_BASE + 0x2C00)` |

## C. 仅目标侧有的宏（402 条）—— 新增能力，不影响迁移

```
ADC_AWD0_RES                    ADC_AWD0_RST_EN                 ADC_AWD1_RES                    ADC_AWD1_RST_EN
ADC_AWD2_RES                    ADC_AWD2_RST_EN                 ADC_AWD_SCAN                    ADC_AnalogWatchdog_0_FLAG
ADC_AnalogWatchdog_0_RST_EN     ADC_AnalogWatchdog_1_FLAG       ADC_AnalogWatchdog_1_RST_EN     ADC_AnalogWatchdog_2_FLAG
ADC_AnalogWatchdog_2_RST_EN     ADC_BUFEN                       ADC_Channel_OPA                 ADC_DRVEN
ADC_DRV_OUTEN                   ADC_DUTYEN                      ADC_ExternalTrigConv_Ext_PD3_PC2_OPA  ADC_ExternalTrigInjecConv_Ext_PD1_PA2_OPA
ADC_ExternalTrigInjecConv_T3_CC1  ADC_ExternalTrigInjecConv_T3_CC2  ADC_InjectedExTrigConv_OPA      ADC_InjectedExTrigConv_PD1_PA2
ADC_LP                          ADC_RegularExTrigConv_OPA       ADC_RegularExTrigConv_PD3_PC2   ADC_SampleTime_CyclesMode0
ADC_SampleTime_CyclesMode1      ADC_SampleTime_CyclesMode2      ADC_SampleTime_CyclesMode3      ADC_SampleTime_CyclesMode4
ADC_SampleTime_CyclesMode5      ADC_SampleTime_CyclesMode6      ADC_SampleTime_CyclesMode7      ADC_Sample_NoOver_1M_Mode
ADC_Sample_Over_1M_Mode         ADC_TGINJE                      ADC_TGREGU                      ADC_TKENABLE
ADC_TKITUNE                     ADC_TKey_Current_mode0          ADC_TKey_Current_mode1          ADC_WDTR1_HTR1
ADC_WDTR1_LTR1                  ADC_WDTR2_HTR2                  ADC_WDTR2_LTR2                  AFIO_EXTICR1_EXTI0_PB
AFIO_EXTICR1_EXTI1_PB           AFIO_EXTICR1_EXTI2_PB           AFIO_EXTICR1_EXTI3_PB           AFIO_EXTICR1_EXTI4_PB
AFIO_EXTICR1_EXTI5_PB           AFIO_EXTICR1_EXTI6_PB           AFIO_EXTICR1_EXTI7_PB           AFIO_PCFR1_ADC_ETRGINJ_REMAP
AFIO_PCFR1_ADC_ETRGREG_REMAP    AFIO_PCFR1_I2C1_REMAP_0         AFIO_PCFR1_I2C1_REMAP_1         AFIO_PCFR1_I2C1_REMAP_2
AFIO_PCFR1_PA1PA2_REMAP         AFIO_PCFR1_SPI1_REMAP_0         AFIO_PCFR1_SPI1_REMAP_1         AFIO_PCFR1_SPI1_REMAP_2
AFIO_PCFR1_TIM1_1_REMAP         AFIO_PCFR1_TIM1_REMAP_2         AFIO_PCFR1_TIM1_REMAP_3         AFIO_PCFR1_TIM2_REMAP_2
AFIO_PCFR1_USART1_REMAP_0       AFIO_PCFR1_USART1_REMAP_1       AFIO_PCFR1_USART1_REMAP_2       AFIO_PCFR1_USART1_REMAP_3
AFIO_PCFR1_USART2_REMAP         AFIO_PCFR1_USART2_REMAP_0       AFIO_PCFR1_USART2_REMAP_1       AFIO_PCFR1_USART2_REMAP_2
BOOT_MODEKEYP_MODEKEYR          BOOT_MODEKEYP_MODEKEYR1         BOOT_MODEKEYP_MODEKEYR2         CH32V006
CMP_FILT_Len_0                  CMP_FILT_Len_1                  CMP_FLAG_OUT_POLL_CH_1          CMP_FLAG_OUT_POLL_CH_2
CMP_FLAG_OUT_POLL_CH_3          CMP_FLAG_POLL_END               CMP_KEY                         DBGMCU_SLEEP
DBGMCU_STANDBY                  DBGMCU_TIM3_STOP                EXTEN_TIM2_DMA_REMAP            FLASH_CTLR_BER32
FLASH_FLAG_FWAKE                FLASH_IT_FWAKE                  FLASH_MODEKEYR_MODEKEYR         FLASH_MODEKEYR_MODEKEYR1
FLASH_MODEKEYR_MODEKEYR2        FLASH_OBR_DATA0                 FLASH_OBR_DATA1                 FLASH_STATR_BOOT_AVA
FLASH_STATR_BOOT_LOCK           FLASH_STATR_BOOT_MODE           FLASH_STATR_BOOT_STATUS         FLASH_STATR_FWAKE_FLAG
FLASH_STATR_TURBO               FLASH_WRProt_Pages0to7          FLASH_WRProt_Pages104to111      FLASH_WRProt_Pages112to119
FLASH_WRProt_Pages120to127      FLASH_WRProt_Pages128to135      FLASH_WRProt_Pages136to143      FLASH_WRProt_Pages144to151
FLASH_WRProt_Pages152to159      FLASH_WRProt_Pages160to167      FLASH_WRProt_Pages168to175      FLASH_WRProt_Pages16to23
FLASH_WRProt_Pages176to183      FLASH_WRProt_Pages184to191      FLASH_WRProt_Pages192to199      FLASH_WRProt_Pages200to207
FLASH_WRProt_Pages208to215      FLASH_WRProt_Pages216to223      FLASH_WRProt_Pages224to231      FLASH_WRProt_Pages232to239
FLASH_WRProt_Pages240to247      FLASH_WRProt_Pages24to31        FLASH_WRProt_Pages32to39        FLASH_WRProt_Pages40to47
FLASH_WRProt_Pages48to55        FLASH_WRProt_Pages56to63        FLASH_WRProt_Pages64to71        FLASH_WRProt_Pages72to79
FLASH_WRProt_Pages80to87        FLASH_WRProt_Pages88to95        FLASH_WRProt_Pages8to15         FLASH_WRProt_Pages96to103
GPIOB                           GPIOB_BASE                      GPIO_FullRemap4_I2C1            GPIO_FullRemap_SPI1
GPIO_FullRemap_USART2           GPIO_PartialRemap1_I2C1         GPIO_PartialRemap1_SPI1         GPIO_PartialRemap1_USART2
GPIO_PartialRemap2_I2C1         GPIO_PartialRemap2_SPI1         GPIO_PartialRemap2_USART2       GPIO_PartialRemap3_I2C1
GPIO_PartialRemap3_SPI1         GPIO_PartialRemap3_TIM1         GPIO_PartialRemap3_TIM2         GPIO_PartialRemap3_USART1
GPIO_PartialRemap3_USART2       GPIO_PartialRemap4_SPI1         GPIO_PartialRemap4_TIM1         GPIO_PartialRemap4_TIM2
GPIO_PartialRemap4_USART1       GPIO_PartialRemap4_USART2       GPIO_PartialRemap5_SPI1         GPIO_PartialRemap5_TIM1
GPIO_PartialRemap5_TIM2         GPIO_PartialRemap5_USART1       GPIO_PartialRemap5_USART2       GPIO_PartialRemap6_TIM1
GPIO_PartialRemap6_TIM2         GPIO_PartialRemap6_USART1       GPIO_PartialRemap7_TIM1         GPIO_PartialRemap7_USART1
GPIO_PartialRemap8_TIM1         GPIO_PartialRemap8_USART1       GPIO_PortSourceGPIOB            HBPERIPH_BASE
OPA                             OPA_BASE                        OPA_CFGR1_AUTO_ADC_CFG          OPA_CFGR1_IE_OUT1
OPA_CFGR1_IF_OUT_POLL_CH1       OPA_CFGR1_IF_OUT_POLL_CH2       OPA_CFGR1_IF_OUT_POLL_CH3       OPA_CFGR1_NMI_EN
OPA_CFGR1_POLL1_NUM             OPA_CFGR1_POLL1_NUM_0           OPA_CFGR1_POLL1_NUM_1           OPA_CFGR1_POLL_CH1
OPA_CFGR1_POLL_CH1_0            OPA_CFGR1_POLL_CH1_1            OPA_CFGR1_POLL_CH2              OPA_CFGR1_POLL_CH2_0
OPA_CFGR1_POLL_CH2_1            OPA_CFGR1_POLL_CH3              OPA_CFGR1_POLL_CH3_0            OPA_CFGR1_POLL_CH3_1
OPA_CFGR1_POLL_EN               OPA_CFGR1_POLL_LOCK             OPA_CFGR1_POLL_SEL              OPA_CFGR1_POLL_SEL_0
OPA_CFGR1_POLL_SEL_1            OPA_CFGR1_POLL_SEL_2            OPA_CFGR1_POLL_SWSTRT           OPA_CFGR1_RST_EN1
OPA_CFGR1_SETUP_CFG             OPA_CFGR1_SETUP_CFG_0           OPA_CFGR1_SETUP_CFG_1           OPA_CFGR2_IE_CNT
OPA_CFGR2_IE_OUT1               OPA_CFGR2_IF_CNT                OPA_CFGR2_IF_OUT_POLL_CH1       OPA_CFGR2_IF_OUT_POLL_CH2
OPA_CFGR2_IF_OUT_POLL_CH3       OPA_CFGR2_POLL_CH1              OPA_CFGR2_POLL_CH1_0            OPA_CFGR2_POLL_CH1_1
OPA_CFGR2_POLL_CH2              OPA_CFGR2_POLL_CH2_0            OPA_CFGR2_POLL_CH2_1            OPA_CFGR2_POLL_CH3
OPA_CFGR2_POLL_CH3_0            OPA_CFGR2_POLL_CH3_1            OPA_CFGR2_POLL_EN1              OPA_CFGR2_POLL_NUM
OPA_CFGR2_POLL_NUM_0            OPA_CFGR2_POLL_NUM_1            OPA_CFGR2_POLL_VLU              OPA_CFGR2_RST_EN1
OPA_CFGR2_RST_EN2               OPA_CTLR1_FB_EN1                OPA_CTLR1_MODE1                 OPA_CTLR1_MODE1_0
OPA_CTLR1_MODE1_1               OPA_CTLR1_NSEL1                 OPA_CTLR1_NSEL1_0               OPA_CTLR1_NSEL1_1
OPA_CTLR1_NSEL1_2               OPA_CTLR1_OPA_EN1               OPA_CTLR1_OPA_HS1               OPA_CTLR1_OPA_LOCK
OPA_CTLR1_PGADIF                OPA_CTLR1_PSEL1                 OPA_CTLR1_PSEL1_0               OPA_CTLR1_PSEL1_1
OPA_CTLR1_VBCMPSEL              OPA_CTLR1_VBCMPSEL_0            OPA_CTLR1_VBCMPSEL_1            OPA_CTLR1_VBEN
OPA_CTLR1_VBSEL                 OPA_CTLR2_BKIN_CFG              OPA_CTLR2_BKIN_CFG_0            OPA_CTLR2_BKIN_CFG_1
OPA_CTLR2_CMP_EN1               OPA_CTLR2_CMP_EN2               OPA_CTLR2_CMP_LOCK              OPA_CTLR2_FILT_EN
OPA_CTLR2_FILT_SEL              OPA_CTLR2_HYEN1                 OPA_CTLR2_MODE1                 OPA_CTLR2_MODE1_0
OPA_CTLR2_MODE1_1               OPA_CTLR2_NSEL1                 OPA_CTLR2_NSEL1_0               OPA_CTLR2_NSEL1_1
OPA_CTLR2_PSEL1                 OPA_CTLR2_PSEL1_0               OPA_CTLR2_PSEL1_1               OPA_CTLR2_RMID1
OPA_FLAG_OUT_POLL_CH_1          OPA_FLAG_OUT_POLL_CH_2          OPA_FLAG_OUT_POLL_CH_3          OPA_KEY
PB1PERIPH_BASE                  PB2PERIPH_BASE                  POLL_KEY                        PWR_AWUEN
PWR_AWUPSC_1                    PWR_AWUPSC_3                    PWR_AWUWR_0                     PWR_AWUWR_1
PWR_AWUWR_2                     PWR_AWUWR_3                     PWR_AWUWR_4                     PWR_AWUWR_5
PWR_CTLR_FLASH_LP               PWR_CTLR_FLASH_LP_0             PWR_CTLR_FLASH_LP_1             PWR_CTLR_FLASH_LP_REG
PWR_CTLR_LDO_MODE               PWR_CTLR_LDO_MODE_0             PWR_CTLR_LDO_MODE_1             PWR_CTLR_LDO_MODE_ENERGYSAVE
PWR_CTLR_LDO_MODE_LOWPOWER      PWR_CTLR_LDO_MODE_NORMAL        PWR_CTLR_PLS_MODE0              PWR_CTLR_PLS_MODE1
PWR_CTLR_PLS_MODE2              PWR_CTLR_PLS_MODE3              RCC_ADCPRE_DIV12                RCC_ADCPRE_DIV128
RCC_ADCPRE_DIV16                RCC_ADCPRE_DIV24                RCC_ADCPRE_DIV32                RCC_ADCPRE_DIV48
RCC_ADCPRE_DIV64                RCC_ADCPRE_DIV96                RCC_ADCRSTF                     RCC_ADC_CLK_ADJ
RCC_ADC_CLK_MODE                RCC_ADC_H_Level_Mode0           RCC_ADC_H_Level_Mode1           RCC_FLAG_ADCRST
RCC_FLAG_OPCMRST                RCC_FLAG_SYSCFAL                RCC_HBPeriph_DMA1               RCC_HBPeriph_SRAM
RCC_HSE_C_Level0                RCC_HSE_C_Level1                RCC_HSE_C_Level2                RCC_HSE_C_Level3
RCC_HSE_LP                      RCC_HSE_SI                      RCC_HSE_SI_0                    RCC_HSE_SI_1
RCC_HSILP                       RCC_IOPBEN                      RCC_IOPBRST                     RCC_IT_SYSCLK_FAIL
RCC_OPCMRSTF                    RCC_PB1Periph_I2C1              RCC_PB1Periph_PWR               RCC_PB1Periph_TIM2
RCC_PB1Periph_TIM3              RCC_PB1Periph_WWDG              RCC_PB2Periph_ADC1              RCC_PB2Periph_AFIO
RCC_PB2Periph_GPIOA             RCC_PB2Periph_GPIOB             RCC_PB2Periph_GPIOC             RCC_PB2Periph_GPIOD
RCC_PB2Periph_SPI1              RCC_PB2Periph_TIM1              RCC_PB2Periph_USART1            RCC_PB2Periph_USART2
RCC_PCLK2_Div1                  RCC_SYSCLK_FAILIE               RCC_SYSCLK_FAILIF               RCC_SYSCM_EN
RCC_TIM3EN                      RCC_TIM3RST                     RCC_USART2EN                    RCC_USART2RST
SLTM_ARPE                       SLTM_ATRLR                      SLTM_CC3DE                      SLTM_CC4DE
SLTM_CEN                        SLTM_CH1CVR                     SLTM_CH2CVR                     SLTM_CH3CVR
SLTM_CH4CVR                     SLTM_CMS                        SLTM_CMS_0                      SLTM_CMS_1
SLTM_CNT                        SLTM_DIR                        SLTM_OC1PE                      SLTM_OC2PE
SLTM_OC3PE                      SLTM_OC4PE                      SLTM_SMS                        SLTM_SMS_0
SLTM_SMS_1                      SLTM_SMS_2                      SLTM_UDIS                       TIM1_Brake_Source_CMP1
TIM1_Brake_Source_CMP2          TIM1_Brake_Source_IO            TIM1_Brake_Source_OPA           TIM3
TIM3_BASE                       TIM_CAPLVL                      TIM_CAPOV                       TIM_DT1
TIM_DT1N_P                      TIM_DT1_0                       TIM_DT1_1                       TIM_DT1_2
TIM_DT1_3                       TIM_DT1_P                       TIM_DT2                         TIM_DT2N_P
TIM_DT2_0                       TIM_DT2_1                       TIM_DT2_2                       TIM_DT2_3
TIM_DT2_P                       TIM_LEVEL1                      TIM_LEVEL2                      TIM_LEVEL3
TIM_LEVEL4                      TIM_OC1N_EN                     TIM_OC2N_EN                     TKey1
USART2                          USART2_BASE
```

## D. 仅 V003 有的函数（23 条）

| 函数 | 签名 |
|---|---|
| `ADC_Calibration_Vol` | `void ADC_Calibration_Vol(ADC_TypeDef *ADCx, uint32_t ADC_CALVOL)` |
| `ADC_ExternalTrig_DLY` | `void ADC_ExternalTrig_DLY(ADC_TypeDef *ADCx, uint32_t channel, uint16_t DelayTim)` |
| `ADC_GetCalibrationStatus` | `FlagStatus ADC_GetCalibrationStatus(ADC_TypeDef *ADCx)` |
| `ADC_GetResetCalibrationStatus` | `FlagStatus ADC_GetResetCalibrationStatus(ADC_TypeDef *ADCx)` |
| `ADC_ResetCalibration` | `void ADC_ResetCalibration(ADC_TypeDef *ADCx)` |
| `ADC_StartCalibration` | `void ADC_StartCalibration(ADC_TypeDef *ADCx)` |
| `FLASH_ProgramHalfWord` | `FLASH_Status FLASH_ProgramHalfWord(uint32_t Address, uint16_t Data)` |
| `FLASH_ProgramOptionByteData` | `FLASH_Status FLASH_ProgramOptionByteData(uint32_t Address, uint8_t Data)` |
| `FLASH_ProgramWord` | `FLASH_Status FLASH_ProgramWord(uint32_t Address, uint32_t Data)` |
| `FLASH_ReadOutProtection` | `FLASH_Status FLASH_ReadOutProtection(FunctionalState NewState)` |
| `OPA_DeInit` | `void OPA_DeInit(void)` |
| `RCC_AHBPeriphClockCmd` | `void RCC_AHBPeriphClockCmd(uint32_t RCC_AHBPeriph, FunctionalState NewState)` |
| `RCC_APB1PeriphClockCmd` | `void RCC_APB1PeriphClockCmd(uint32_t RCC_APB1Periph, FunctionalState NewState)` |
| `RCC_APB1PeriphResetCmd` | `void RCC_APB1PeriphResetCmd(uint32_t RCC_APB1Periph, FunctionalState NewState)` |
| `RCC_APB2PeriphClockCmd` | `void RCC_APB2PeriphClockCmd(uint32_t RCC_APB2Periph, FunctionalState NewState)` |
| `RCC_APB2PeriphResetCmd` | `void RCC_APB2PeriphResetCmd(uint32_t RCC_APB2Periph, FunctionalState NewState)` |
| `USART_ClockInit` | `void USART_ClockInit(USART_TypeDef *USARTx, USART_ClockInitTypeDef *USART_ClockInitStruct)` |
| `USART_ClockStructInit` | `void USART_ClockStructInit(USART_ClockInitTypeDef *USART_ClockInitStruct)` |
| `USART_OneBitMethodCmd` | `void USART_OneBitMethodCmd(USART_TypeDef *USARTx, FunctionalState NewState)` |
| `USART_OverSampling8Cmd` | `void USART_OverSampling8Cmd(USART_TypeDef *USARTx, FunctionalState NewState)` |
| `USART_SetGuardTime` | `void USART_SetGuardTime(USART_TypeDef *USARTx, uint8_t USART_GuardTime)` |
| `USART_SmartCardCmd` | `void USART_SmartCardCmd(USART_TypeDef *USARTx, FunctionalState NewState)` |
| `USART_SmartCardNACKCmd` | `void USART_SmartCardNACKCmd(USART_TypeDef *USARTx, FunctionalState NewState)` |

## E. 仅目标侧有的函数（49 条）

| 函数 | 签名 |
|---|---|
| `ADC_AnalogWatchdog1ThresholdsConfig` | `void ADC_AnalogWatchdog1ThresholdsConfig(ADC_TypeDef *ADCx, uint16_t HighThreshold, uint16_t LowThreshold)` |
| `ADC_AnalogWatchdog2ThresholdsConfig` | `void ADC_AnalogWatchdog2ThresholdsConfig(ADC_TypeDef *ADCx, uint16_t HighThreshold, uint16_t LowThreshold)` |
| `ADC_AnalogWatchdogResetCmd` | `void ADC_AnalogWatchdogResetCmd(ADC_TypeDef *ADCx, uint32_t ADC_AnalogWatchdog_x, FunctionalState NewState)` |
| `ADC_AnalogWatchdogScanCmd` | `void ADC_AnalogWatchdogScanCmd(ADC_TypeDef *ADCx, FunctionalState NewState)` |
| `ADC_BufferCmd` | `void ADC_BufferCmd(ADC_TypeDef *ADCx, FunctionalState NewState)` |
| `ADC_ClearAnalogWatchdogFlag` | `void ADC_ClearAnalogWatchdogFlag(ADC_TypeDef *ADCx, uint32_t AnalogWatchdog_FLAG)` |
| `ADC_DutyDelayCmd` | `void ADC_DutyDelayCmd(ADC_TypeDef *ADCx, FunctionalState NewState)` |
| `ADC_GetAnalogWatchdogFlagStatus` | `FlagStatus ADC_GetAnalogWatchdogFlagStatus(ADC_TypeDef *ADCx, uint32_t AnalogWatchdog_FLAG)` |
| `ADC_InjectedExTrigConvConfig` | `void ADC_InjectedExTrigConvConfig(ADC_TypeDef *ADCx, uint32_t InjectedExTrigConv)` |
| `ADC_RegularExTrigConvConfig` | `void ADC_RegularExTrigConvConfig(ADC_TypeDef *ADCx, uint32_t RegularExTrigConv)` |
| `ADC_Sample_ModeConfig` | `void ADC_Sample_ModeConfig(ADC_TypeDef *ADCx, uint32_t ADC_Sample_Mode)` |
| `ADC_TKeyCmd` | `void ADC_TKeyCmd(ADC_TypeDef *ADCx, FunctionalState NewState)` |
| `ADC_TKey_ChannelxMulShieldCmd` | `void ADC_TKey_ChannelxMulShieldCmd(ADC_TypeDef *ADCx, uint8_t ADC_Channel, FunctionalState NewState)` |
| `ADC_TKey_MulShieldCmd` | `void ADC_TKey_MulShieldCmd(ADC_TypeDef *ADCx, FunctionalState NewState)` |
| `ADC_Tkey_CurrentConfig` | `void ADC_Tkey_CurrentConfig(ADC_TypeDef *ADCx, uint32_t TKey_CurrentMode)` |
| `FLASH_EnableReadOutProtection` | `FLASH_Status FLASH_EnableReadOutProtection(void)` |
| `FLASH_EraseBlock_32K_Fast` | `void FLASH_EraseBlock_32K_Fast(uint32_t Block_Address)` |
| `GPIO_IPD_Unused` | `void GPIO_IPD_Unused(void)` |
| `OPA_CMP1_Init` | `void OPA_CMP1_Init(CMP1_InitTypeDef *CMP_InitStruct)` |
| `OPA_CMP1_StructInit` | `void OPA_CMP1_StructInit(CMP1_InitTypeDef *CMP_InitStruct)` |
| `OPA_CMP_ClearFlag` | `void OPA_CMP_ClearFlag(uint32_t CMP_FLAG)` |
| `OPA_CMP_Cmd` | `void OPA_CMP_Cmd(CMP_Num_TypeDef CMP_NUM, FunctionalState NewState)` |
| `OPA_CMP_FILT_Cmd` | `void OPA_CMP_FILT_Cmd(FunctionalState NewState)` |
| `OPA_CMP_FILT_LEN_Config` | `void OPA_CMP_FILT_LEN_Config(uint32_t FILT_Len)` |
| `OPA_CMP_GetFlagStatus` | `FlagStatus OPA_CMP_GetFlagStatus(uint32_t CMP_FLAG)` |
| `OPA_CMP_Lock` | `void OPA_CMP_Lock(void)` |
| `OPA_CMP_POLL_Lock` | `void OPA_CMP_POLL_Lock(void)` |
| `OPA_CMP_SystemReset_Cmd` | `void OPA_CMP_SystemReset_Cmd(CMP_Num_TypeDef CMP_NUM, FunctionalState NewState)` |
| `OPA_CMP_TIM1_BKINConfig` | `void OPA_CMP_TIM1_BKINConfig(uint32_t Brake_Source)` |
| `OPA_CMP_Unlock` | `void OPA_CMP_Unlock(void)` |
| `OPA_ClearFlag` | `void OPA_ClearFlag(uint32_t OPA_FLAG)` |
| `OPA_GetFlagStatus` | `FlagStatus OPA_GetFlagStatus(uint32_t OPA_FLAG)` |
| `OPA_Lock` | `void OPA_Lock(void)` |
| `OPA_SoftwareStartPollCmd` | `void OPA_SoftwareStartPollCmd(FunctionalState NewState)` |
| `OPA_SystemReset_Cmd` | `void OPA_SystemReset_Cmd(FunctionalState NewState)` |
| `OPA_Unlock` | `void OPA_Unlock(void)` |
| `PWR_FLASH_LP_Cmd` | `void PWR_FLASH_LP_Cmd(FunctionalState NewState)` |
| `RCC_ADCCLKDutyCycleConfig` | `void RCC_ADCCLKDutyCycleConfig(uint32_t RCC_DutyCycle)` |
| `RCC_ClockMonitorCmd` | `void RCC_ClockMonitorCmd(FunctionalState NewState)` |
| `RCC_HBPeriphClockCmd` | `void RCC_HBPeriphClockCmd(uint32_t RCC_HBPeriph, FunctionalState NewState)` |
| `RCC_HSECurrentConfig` | `void RCC_HSECurrentConfig(uint32_t RCC_HSECurrent)` |
| `RCC_HSE_LP_Cmd` | `void RCC_HSE_LP_Cmd(FunctionalState NewState)` |
| `RCC_HSI_LP_Cmd` | `void RCC_HSI_LP_Cmd(FunctionalState NewState)` |
| `RCC_PB1PeriphClockCmd` | `void RCC_PB1PeriphClockCmd(uint32_t RCC_PB1Periph, FunctionalState NewState)` |
| `RCC_PB1PeriphResetCmd` | `void RCC_PB1PeriphResetCmd(uint32_t RCC_PB1Periph, FunctionalState NewState)` |
| `RCC_PB2PeriphClockCmd` | `void RCC_PB2PeriphClockCmd(uint32_t RCC_PB2Periph, FunctionalState NewState)` |
| `RCC_PB2PeriphResetCmd` | `void RCC_PB2PeriphResetCmd(uint32_t RCC_PB2Periph, FunctionalState NewState)` |
| `SPI_HS_RX_Cmd` | `void SPI_HS_RX_Cmd(SPI_TypeDef *SPIx, FunctionalState NewState)` |
| `TIM_DeadTimeConfig` | `void TIM_DeadTimeConfig(TIM_TypeDef *TIMx, uint16_t TIM_Channel, uint8_t DeadTime)` |

## F. 同名不同签名的函数（0 条）

**无。** 两侧不存在「同名但签名变了」的函数。

这意味着：编译器报未声明的函数，按 `03_api-delta.md` 的表查即可；
不存在「签名悄悄变了」的隐蔽情况。签名不变但函数体行为改变的情况见 `07_func-behavior.md`。
