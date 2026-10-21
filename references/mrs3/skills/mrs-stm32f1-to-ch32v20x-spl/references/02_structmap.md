# 寄存器结构体成员映射表（STM32F10x → CH32V20x）

> 数据来源：两侧设备头（`stm32f10x.h` / `ch32v20x.h`）中的 `XXX_TypeDef` 定义。
> 用户代码中任何 `外设指针->成员名` 的写法都受本表影响，**这类代码编译期报错，不会静默出错**。

## 配对方式与可靠性

两侧寄存器结构体按**声明顺序**对齐（前提：同一外设的寄存器排布在两侧一致，仅命名不同），
配对前已剔除 `RESERVED*` 保留填充字段——它们不承载寄存器语义，两侧数量常不相同。

⚠ **位置对齐是推定，不是证明。** 依据是两侧寄存器地址偏移一致这一观察结果。
使用本表时遵循两点：

- 「改名」类条目已通过两侧**取值相同的位定义宏**交叉验证（见 `01_regmap.md`），可信度高。
- 若某结构体标有「成员数不同」警告，说明两侧存在寄存器增删或顺序差异，
  该处对齐**自警告点之后不再可靠**，必须对照寄存器手册的地址偏移确认。

## 覆盖范围

| 项 | 数量 |
|---|---:|
| 两侧同名的寄存器结构体 | 23 |
| 仅 STM32 存在 | 10 |
| 仅 CH32 存在 | 6 |

仅 STM32 存在的寄存器结构体：`CEC_TypeDef`, `DAC_TypeDef`, `DBGMCU_TypeDef`, `ETH_TypeDef`, `FSMC_Bank1E_TypeDef`, `FSMC_Bank1_TypeDef`, `FSMC_Bank2_TypeDef`, `FSMC_Bank3_TypeDef`, `FSMC_Bank4_TypeDef`, `SDIO_TypeDef`

仅 CH32 存在的寄存器结构体：`ETH10M_TypeDef`, `EXTEN_TypeDef`, `OPA_TypeDef`, `OSC_TypeDef`, `USBFSD_TypeDef`, `USBFSH_TypeDef`

## 一、成员名完全一致的寄存器结构体（1 个，无需改动）

`CAN_FilterRegister_TypeDef`

## 二、成员名有差异的寄存器结构体（22 个，逐成员对照）

### ADC_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `SR` | `STATR` | 改名 |
| 2 | `CR1` | `CTLR1` | 改名 |
| 3 | `CR2` | `CTLR2` | 改名 |
| 4 | `SMPR1` | `SAMPTR1` | 改名 |
| 5 | `SMPR2` | `SAMPTR2` | 改名 |
| 6 | `JOFR1` | `IOFR1` | 改名 |
| 7 | `JOFR2` | `IOFR2` | 改名 |
| 8 | `JOFR3` | `IOFR3` | 改名 |
| 9 | `JOFR4` | `IOFR4` | 改名 |
| 10 | `HTR` | `WDHTR` | 改名 |
| 11 | `LTR` | `WDLTR` | 改名 |
| 12 | `SQR1` | `RSQR1` | 改名 |
| 13 | `SQR2` | `RSQR2` | 改名 |
| 14 | `SQR3` | `RSQR3` | 改名 |
| 15 | `JSQR` | `ISQR` | 改名 |
| 16 | `JDR1` | `IDATAR1` | 改名 |
| 17 | `JDR2` | `IDATAR2` | 改名 |
| 18 | `JDR3` | `IDATAR3` | 改名 |
| 19 | `JDR4` | `IDATAR4` | 改名 |
| 20 | `DR` | `RDATAR` | 改名 |

### AFIO_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `EVCR` | `ECR` | 改名 |
| 2 | `MAPR` | `PCFR1` | 改名 |
| 3 | `EXTICR` | `EXTICR` |  |
| 4 | `MAPR2` | `PCFR2` | 改名 |

> 保留填充字段（`RESERVED*`）数量：STM32 1 个 / CH32 1 个，不影响寄存器访问。

### BKP_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `DR1` | `DATAR1` | 改名 |
| 2 | `DR2` | `DATAR2` | 改名 |
| 3 | `DR3` | `DATAR3` | 改名 |
| 4 | `DR4` | `DATAR4` | 改名 |
| 5 | `DR5` | `DATAR5` | 改名 |
| 6 | `DR6` | `DATAR6` | 改名 |
| 7 | `DR7` | `DATAR7` | 改名 |
| 8 | `DR8` | `DATAR8` | 改名 |
| 9 | `DR9` | `DATAR9` | 改名 |
| 10 | `DR10` | `DATAR10` | 改名 |
| 11 | `RTCCR` | `OCTLR` | 改名 |
| 12 | `CR` | `TPCTLR` | 改名 |
| 13 | `CSR` | `TPCSR` | 改名 |
| 14 | `DR11` | `DATAR11` | 改名 |
| 15 | `DR12` | `DATAR12` | 改名 |
| 16 | `DR13` | `DATAR13` | 改名 |
| 17 | `DR14` | `DATAR14` | 改名 |
| 18 | `DR15` | `DATAR15` | 改名 |
| 19 | `DR16` | `DATAR16` | 改名 |
| 20 | `DR17` | `DATAR17` | 改名 |
| 21 | `DR18` | `DATAR18` | 改名 |
| 22 | `DR19` | `DATAR19` | 改名 |
| 23 | `DR20` | `DATAR20` | 改名 |
| 24 | `DR21` | `DATAR21` | 改名 |
| 25 | `DR22` | `DATAR22` | 改名 |
| 26 | `DR23` | `DATAR23` | 改名 |
| 27 | `DR24` | `DATAR24` | 改名 |
| 28 | `DR25` | `DATAR25` | 改名 |
| 29 | `DR26` | `DATAR26` | 改名 |
| 30 | `DR27` | `DATAR27` | 改名 |
| 31 | `DR28` | `DATAR28` | 改名 |
| 32 | `DR29` | `DATAR29` | 改名 |
| 33 | `DR30` | `DATAR30` | 改名 |
| 34 | `DR31` | `DATAR31` | 改名 |
| 35 | `DR32` | `DATAR32` | 改名 |
| 36 | `DR33` | `DATAR33` | 改名 |
| 37 | `DR34` | `DATAR34` | 改名 |
| 38 | `DR35` | `DATAR35` | 改名 |
| 39 | `DR36` | `DATAR36` | 改名 |
| 40 | `DR37` | `DATAR37` | 改名 |
| 41 | `DR38` | `DATAR38` | 改名 |
| 42 | `DR39` | `DATAR39` | 改名 |
| 43 | `DR40` | `DATAR40` | 改名 |
| 44 | `DR41` | `DATAR41` | 改名 |
| 45 | `DR42` | `DATAR42` | 改名 |

> 保留填充字段（`RESERVED*`）数量：STM32 46 个 / CH32 46 个，不影响寄存器访问。

### CAN_FIFOMailBox_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `RIR` | `RXMIR` | 改名 |
| 2 | `RDTR` | `RXMDTR` | 改名 |
| 3 | `RDLR` | `RXMDLR` | 改名 |
| 4 | `RDHR` | `RXMDHR` | 改名 |

### CAN_TxMailBox_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `TIR` | `TXMIR` | 改名 |
| 2 | `TDTR` | `TXMDTR` | 改名 |
| 3 | `TDLR` | `TXMDLR` | 改名 |
| 4 | `TDHR` | `TXMDHR` | 改名 |

### CAN_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `MCR` | `CTLR` | 改名 |
| 2 | `MSR` | `STATR` | 改名 |
| 3 | `TSR` | `TSTATR` | 改名 |
| 4 | `RF0R` | `RFIFO0` | 改名 |
| 5 | `RF1R` | `RFIFO1` | 改名 |
| 6 | `IER` | `INTENR` | 改名 |
| 7 | `ESR` | `ERRSR` | 改名 |
| 8 | `BTR` | `BTIMR` | 改名 |
| 9 | `sTxMailBox` | `sTxMailBox` |  |
| 10 | `sFIFOMailBox` | `sFIFOMailBox` |  |
| 11 | `FMR` | `FCTLR` | 改名 |
| 12 | `FM1R` | `FMCFGR` | 改名 |
| 13 | `FS1R` | `FSCFGR` | 改名 |
| 14 | `FFA1R` | `FAFIFOR` | 改名 |
| 15 | `FA1R` | `FWR` | 改名 |
| 16 | `sFilterRegister` | `sFilterRegister` |  |

> 保留填充字段（`RESERVED*`）数量：STM32 6 个 / CH32 6 个，不影响寄存器访问。

### CRC_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `DR` | `DATAR` | 改名 |
| 2 | `IDR` | `IDATAR` | 改名 |
| 3 | `CR` | `CTLR` | 改名 |

> 保留填充字段（`RESERVED*`）数量：STM32 2 个 / CH32 2 个，不影响寄存器访问。

### DMA_Channel_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CCR` | `CFGR` | 改名 |
| 2 | `CNDTR` | `CNTR` | 改名 |
| 3 | `CPAR` | `PADDR` | 改名 |
| 4 | `CMAR` | `MADDR` | 改名 |

### DMA_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `ISR` | `INTFR` | 改名 |
| 2 | `IFCR` | `INTFCR` | 改名 |

### EXTI_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `IMR` | `INTENR` | 改名 |
| 2 | `EMR` | `EVENR` | 改名 |
| 3 | `RTSR` | `RTENR` | 改名 |
| 4 | `FTSR` | `FTENR` | 改名 |
| 5 | `SWIER` | `SWIEVR` | 改名 |
| 6 | `PR` | `INTFR` | 改名 |

### FLASH_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `ACR` | `ACTLR` | 改名（⚠ CH32 侧该寄存器**没有任何位定义**，等待周期与预取改由内核 CSR `0xBC0` 控制） |
| 2 | `KEYR` | `KEYR` |  |
| 3 | `OPTKEYR` | `OBKEYR` | 改名 |
| 4 | `SR` | `STATR` | 改名 |
| 5 | `CR` | `CTLR` | 改名 |
| 6 | `AR` | `ADDR` | 改名 |
| 7 | `OBR` | `OBR` |  |
| 8 | `WRPR` | `WPR` | 改名 |
| 9 | `—` | `MODEKEYR` | 仅 CH32 新增（`+0x24`，快速擦写模式的解锁钥匙寄存器） |

> 前 8 个寄存器（`+0x00`~`+0x20`）两侧偏移一一对应（两侧在 `+0x18` 处都有一个保留字），
> 唯一多出的是 CH32 尾部的 `MODEKEYR`（`+0x24`）—— 所以 **STM32 `0x24` 字节 / CH32 `0x28` 字节**。
> STM32 侧的 `KEYR2`/`SR2`/`CR2`/`AR2`（`+0x44` 起）属 `STM32F10X_XL` 双 bank 专用，
> **`STM32F10X_MD` 下不参与编译，不在本表内**。
> **两侧共有寄存器的裸地址都可以直接沿用。**

### GPIO_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CRL` | `CFGLR` | 改名 |
| 2 | `CRH` | `CFGHR` | 改名 |
| 3 | `IDR` | `INDR` | 改名 |
| 4 | `ODR` | `OUTDR` | 改名 |
| 5 | `BSRR` | `BSHR` | 改名 |
| 6 | `BRR` | `BCR` | 改名 |
| 7 | `LCKR` | `LCKR` |  |

### I2C_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CR1` | `CTLR1` | 改名 |
| 2 | `CR2` | `CTLR2` | 改名 |
| 3 | `OAR1` | `OADDR1` | 改名 |
| 4 | `OAR2` | `OADDR2` | 改名 |
| 5 | `DR` | `DATAR` | 改名 |
| 6 | `SR1` | `STAR1` | 改名 |
| 7 | `SR2` | `STAR2` | 改名 |
| 8 | `CCR` | `CKCFGR` | 改名 |
| 9 | `TRISE` | `RTR` | 改名 |

> 保留填充字段（`RESERVED*`）数量：STM32 9 个 / CH32 9 个，不影响寄存器访问。

### IWDG_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `KR` | `CTLR` | 改名 |
| 2 | `PR` | `PSCR` | 改名 |
| 3 | `RLR` | `RLDR` | 改名 |
| 4 | `SR` | `STATR` | 改名 |

### OB_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `RDP` | `RDPR` | 改名 |
| 2 | `USER` | `USER` |  |
| 3 | `Data0` | `Data0` |  |
| 4 | `Data1` | `Data1` |  |
| 5 | `WRP0` | `WRPR0` | 改名 |
| 6 | `WRP1` | `WRPR1` | 改名 |
| 7 | `WRP2` | `WRPR2` | 改名 |
| 8 | `WRP3` | `WRPR3` | 改名 |

### PWR_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CR` | `CTLR` | 改名 |
| 2 | `CSR` | `CSR` |  |

### RCC_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CR` | `CTLR` | 改名 |
| 2 | `CFGR` | `CFGR0` | 改名 |
| 3 | `CIR` | `INTR` | 改名 |
| 4 | `APB2RSTR` | `APB2PRSTR` | 改名 |
| 5 | `APB1RSTR` | `APB1PRSTR` | 改名 |
| 6 | `AHBENR` | `AHBPCENR` | 改名 |
| 7 | `APB2ENR` | `APB2PCENR` | 改名 |
| 8 | `APB1ENR` | `APB1PCENR` | 改名 |
| 9 | `BDCR` | `BDCTLR` | 改名 |
| 10 | `CSR` | `RSTSCKR` | 改名 |
| 11 | `—` | `AHBRSTR` | 仅 CH32 新增 |
| 12 | `—` | `CFGR2` | 仅 CH32 新增 |

> ⚠ 剔除保留字段后成员数仍不同：STM32 10 个 / CH32 12 个，存在**寄存器增删或顺序差异**，位置对齐在第 10 项之后不可靠，直接操作该类寄存器时必须核对寄存器手册。

### RTC_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CRH` | `CTLRH` | 改名 |
| 2 | `CRL` | `CTLRL` | 改名 |
| 3 | `PRLH` | `PSCRH` | 改名 |
| 4 | `PRLL` | `PSCRL` | 改名 |
| 5 | `DIVH` | `DIVH` |  |
| 6 | `DIVL` | `DIVL` |  |
| 7 | `CNTH` | `CNTH` |  |
| 8 | `CNTL` | `CNTL` |  |
| 9 | `ALRH` | `ALRMH` | 改名 |
| 10 | `ALRL` | `ALRML` | 改名 |

> 保留填充字段（`RESERVED*`）数量：STM32 10 个 / CH32 10 个，不影响寄存器访问。

### SPI_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CR1` | `CTLR1` | 改名 |
| 2 | `CR2` | `CTLR2` | 改名 |
| 3 | `SR` | `STATR` | 改名 |
| 4 | `DR` | `DATAR` | 改名 |
| 5 | `CRCPR` | `CRCR` | 改名 |
| 6 | `RXCRCR` | `RCRCR` | 改名 |
| 7 | `TXCRCR` | `TCRCR` | 改名 |
| 8 | `I2SCFGR` | `I2SCFGR` |  |
| 9 | `I2SPR` | `I2SPR` |  |
| 10 | `—` | `HSCR` | 仅 CH32 新增 |

> ⚠ 剔除保留字段后成员数仍不同：STM32 9 个 / CH32 10 个，存在**寄存器增删或顺序差异**，位置对齐在第 9 项之后不可靠，直接操作该类寄存器时必须核对寄存器手册。

> 保留填充字段（`RESERVED*`）数量：STM32 9 个 / CH32 10 个，不影响寄存器访问。

### TIM_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CR1` | `CTLR1` | 改名 |
| 2 | `CR2` | `CTLR2` | 改名 |
| 3 | `SMCR` | `SMCFGR` | 改名 |
| 4 | `DIER` | `DMAINTENR` | 改名 |
| 5 | `SR` | `INTFR` | 改名 |
| 6 | `EGR` | `SWEVGR` | 改名 |
| 7 | `CCMR1` | `CHCTLR1` | 改名 |
| 8 | `CCMR2` | `CHCTLR2` | 改名 |
| 9 | `CCER` | `CCER` |  |
| 10 | `CNT` | `CNT` | 同名（CH32 在 union 中另暴露 32 位写法 `CNT_R32`） |
| 11 | `PSC` | `PSC` |  |
| 12 | `ARR` | `ATRLR` | 改名（union 成员，另暴露 `ATRLR_R32`） |
| 13 | `RCR` | `RPTCR` | 改名 |
| 14 | `CCR1` | `CH1CVR` | 改名（union 成员，另暴露 `CH1CVR_R32`） |
| 15 | `CCR2` | `CH2CVR` | 改名（同上，另暴露 `CH2CVR_R32`） |
| 16 | `CCR3` | `CH3CVR` | 改名（同上，另暴露 `CH3CVR_R32`） |
| 17 | `CCR4` | `CH4CVR` | 改名（同上，另暴露 `CH4CVR_R32`） |
| 18 | `BDTR` | `BDTR` |  |
| 19 | `DCR` | `DMACFGR` | 改名 |
| 20 | `DMAR` | `DMAADR` | 改名 |

> 两侧均为 20 个顶层成员、总大小 80 B，**偏移一一对应**，裸地址可直接沿用。
> CH32 把 `CNT`/`ATRLR`/`CH1CVR`~`CH4CVR` 放进匿名 union，同时暴露 16 位与 32 位两种访问名
> （`*_R32` 是 CH32 独有，配合 32 位的 TIM5；STM32 代码不会用到，**也不必改用**）。
> 本表已按两侧头文件原文手工核对（自动生成工具无法展开 union，曾在此产生错乱，已修正）。

### USART_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `SR` | `STATR` | 改名 |
| 2 | `DR` | `DATAR` | 改名 |
| 3 | `BRR` | `BRR` |  |
| 4 | `CR1` | `CTLR1` | 改名 |
| 5 | `CR2` | `CTLR2` | 改名 |
| 6 | `CR3` | `CTLR3` | 改名 |
| 7 | `GTPR` | `GPR` | 改名 |

> 保留填充字段（`RESERVED*`）数量：STM32 7 个 / CH32 7 个，不影响寄存器访问。

### WWDG_TypeDef

| # | STM32 成员 | CH32 成员 | 说明 |
|---:|---|---|---|
| 1 | `CR` | `CTLR` | 改名 |
| 2 | `CFR` | `CFGR` | 改名 |
| 3 | `SR` | `STATR` | 改名 |
