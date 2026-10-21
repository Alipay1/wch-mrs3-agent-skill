# 函数实现层差异清单（函数体逻辑，不是签名）

> **这一页补的是最后一条缝**：函数原型在两侧零冲突（见 `04_api-delta.md`），
> 所以改名、换头文件、编译—— **编译器一句话都不会说**。
> 但函数体内部可能已经变了。本表列出归一化后仍不一致的全部条目。

> 数据来源：`_periph_diff/02_modules/<模块>.md` 的「3.1 差异索引」。
> 该表先按 `02_structmap.md` / `01_regmap.md` 的配对把 CH32 的寄存器名与位宏名
> **换算回 STM32 名称**、再按宏环境裁掉不生效的条件分支，最后比符号序列 ——
> 因此这里剩下的差异，是**换名换不掉的那部分**。

> 判定列为人工逐函数回两侧源码核实后写成；形态规则可归类的（位带改写 / 型号分支 / 续行符）
> 由脚本自动标注。

## 一、判定口径

| 判定 | 含义 |
|---|---|
| 🔴 必须改 | 函数名或接口不变，但**行为已变**，不改会出错或静默失效。 |
| 🟠 需确认 | 实现路径被重写或粒度改变，调用点不用改，但**需要按实际硬件验证**。 |
| 🟡 边界差异 | 仅在本型号不涉及的分支、或 CH32 独有工作条件下才出现；常规迁移路径碰不到。 |
| 🟢 无需处理 | 归一化后仍被判 ❌ 只是**表达形态不同**（位带改写 / 续行符 / 掩码写 vs if-else），语义等价。 |

> ⚠ 未出现在本表的函数，要么归一化后**完全一致**（含仅差 `assert_param` / 仅差命名 / 仅差类型转换三种等价情形），要么是**单侧存在** —— 后者见 `03_semantic-gaps.md` 第五、六节。

## 二、总表

| 模块 | 函数总数 | ✅ 完全一致 | 🟡 等价（命名/断言/转换） | ❌ 逻辑差异 | ⚪ 单侧/不编译 |
|---|---:|---:|---:|---:|---:|
| gpio | 19 | 3 | 1 | **14** | 1 |
| rcc | 35 | 0 | 23 | **9** | 3 |
| misc | 5 | 0 | 0 | **2** | 3 |
| tim | 91 | 10 | 69 | **12** | 0 |
| usart | 29 | 3 | 22 | **2** | 2 |
| spi | 23 | 2 | 19 | **2** | 0 |
| i2c | 33 | 4 | 28 | **1** | 0 |
| dma | 11 | 1 | 5 | **5** | 0 |
| exti | 8 | 1 | 7 | **0** | 0 |
| flash | 39 | 5 | 9 | **10** | 15 |
| adc | 39 | 2 | 32 | **2** | 3 |
| can | 25 | 2 | 21 | **2** | 0 |
| pwr | 14 | 2 | 4 | **3** | 5 |
| rtc | 14 | 1 | 11 | **2** | 0 |
| bkp | 12 | 3 | 4 | **5** | 0 |
| crc | 6 | 0 | 6 | **0** | 0 |
| iwdg | 6 | 0 | 5 | **1** | 0 |
| wwdg | 8 | 1 | 6 | **1** | 0 |
| dbgmcu | 6 | 0 | 0 | **3** | 3 |
| **合计** | **423** | **40** | **272** | **76** | **35** |

> `🟡 = 0` 里包含「仅差 `assert_param`」这一档：两侧都可能有纯断言块，剔除断言后函数体为空 —— 这类不计入 ❌。

## 三、必须改的高价值陷阱

下面几条是 76 条差异里最容易静默出错的，逐条给结论与动作。

### 1. `GPIO_SetBits` / `GPIO_Write` 等 9 个函数对 GPIOC 的引脚重编号**依赖调用顺序**

- `ch32v20x_gpio.c` 里 `uint8_t MCU_Version = 0;` 是**文件级全局**，全文件**只在 `GPIO_Init()` 内被赋值一次**；
- 其余读引脚/写引脚/读输出/写输出的 9 个函数**只读不写**。
- 因此在**任何 `GPIO_Init()` 之前**调 `GPIO_SetBits(GPIOC, GPIO_Pin_13)`，不会做重编号 → 在早期批次芯片上操作的是错误的位。
- 触发条件：`CH32V20x_D6` 且 `(*(uint32_t*)0x40022030 & 0x0F000000) == 0`（旧版芯片）。
- `MCU_Version` **未在任何头文件暴露**（无 `extern`），用户代码查不到、也改不了。
- 该重编号**只在库函数路径内**发生 —— 用户代码若用裸地址或位带直访 GPIOC，**不参与重编号**，与库函数路径操作同一引脚的结果不一致；这一条要与 `07_pointer-and-bitband.md` 的裸地址核对叠加处理。

> **动作**：把 `GPIO_Init()` 放在对 GPIOC 的任何操作之前；或对 GPIOC 的引脚一律按目标库重编号后的编号书写（早期芯片上 `GPIO_Pin >> 13`）。

### 2. `SPI_StructInit` 不初始化 `SPI_NSS`，该成员会残留栈值

- STM32 写 9 个成员，CH32 只写 8 个 —— 少的是 `SPI_InitStruct->SPI_NSS = SPI_NSS_Hard;`。
- 最常见写法 `SPI_InitTypeDef s; SPI_StructInit(&s); SPI_Init(SPI1, &s);` 下，`s.SPI_NSS` 是**未初始化的栈值**，`SPI_Init` 会把它写进 `CTLR1`。

> **动作**：在 `SPI_StructInit()` 之后**手工补一句** `s.SPI_NSS = SPI_NSS_Hard;`（或所需模式）。

### 3. `FLASH_GetStatus` / `FLASH_GetBank1Status` 删掉了 PGERR 分支

- STM32 依次判 `BSY` → `PGERR` → `WRPRTERR`；CH32 只判 `BSY` → `WRPRTERR`。
- **`FLASH_ERROR_PG` 在 CH32 上永远不会被返回** —— `if (FLASH_GetStatus() == FLASH_ERROR_PG)` 恒不成立。

> **动作**：把编程失败的判断改为「非 `FLASH_COMPLETE` 即失败」，不要依赖 `FLASH_ERROR_PG`。

### 4. `NVIC_PriorityGroupConfig` 不写硬件，`NVIC_Init` 的优先级语义也已变

- STM32 的 `NVIC_PriorityGroupConfig` 立刻写 `SCB->AIRCR`；CH32 只是把值存进全局 `NVIC_Priority_Group`。
- **分组值延迟到 `NVIC_Init()` 才被读取** → 两者必须按「先分组、后初始化」顺序调用，顺序颠倒则分组不生效。
- `NVIC_Init` 里 CH32 只在 `NVIC_Priority_Group == NVIC_PriorityGroup_1`（开启嵌套）时使用 `NVIC_IRQChannelPreemptionPriority`，并用 `<<4` / `<<5` 自行拼优先级值。
- 分组宏本身的编码与语义两侧也不同（见 `03_semantic-gaps.md` 的 `NVIC_PriorityGroup_0/1`）。

> **动作**：确认调用顺序；并按 `05_migration-rules.md` 第三节重新设计优先级分组。

### 5. `DBGMCU_GetREVID` / `DBGMCU_GetDEVID` 在 CH32 侧**返回值互换**

- CH32：`GetREVID()` 返回 `*(uint32_t*)0x1FFFF704 & IDCODE_DEVID_MASK`（**器件 ID**）；
- STM32：`GetREVID()` 返回 `DBGMCU->IDCODE >> 16`（**版本号**）。
- 两个函数恰好对调 —— 要取版本号反而应调 CH32 的 `GetDEVID()`。
- 同时访问地址从内存映射的 `0xE0042000` 换成 **`0x1FFFF704`**（CH32 的调试停机控制是内核 CSR `0x7C0`，不是内存映射寄存器）。

> **动作**：需要版本号 → 调 CH32 的 `DBGMCU_GetDEVID()`；需要器件 ID → 调 `DBGMCU_GetREVID()`。并在代码里写明，避免下一个人照名字理解。

### 6. DMA 的标志/中断查询函数固定只读 `DMA1`

- STM32 按 `DMAy_FLAG & FLAG_Mask` 选 `DMA2->ISR` 还是 `DMA1->ISR`；
- CH32 的 `DMA_GetFlagStatus` / `DMA_ClearFlag` / `DMA_GetITStatus` / `DMA_ClearITPendingBit` **一律只用 `DMA1`**。
- CH32V20x 只有一个 DMA1、8 个通道，传 `DMA2_*` 参数不会报错，只会读到错的寄存器。

> **动作**：改用 `DMA1_Channel1`~`DMA1_Channel8`；`DMA2` 相关代码无硬件可落，需重新设计。

## 四、按模块明细

### gpio（14 条 ❌ / 共 19 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `GPIO_DeInit` | :108 | :37 | 73.8% | `删除: else if ( GPIOx == GPIOE ) { RCC_APB2PeriphResetCmd ( RCC_AP → (空)` | 🟡 型号分支，本型号不涉及 —— CH32V20x_D6 只有 GPIOA~GPIOD（设备头无 `GPIOE_BASE`），故删掉了 `GPIOE` 那一支。用到 GPIOE 的旧代码在 CH32 上本就无对应硬件。 |
| 03 | `GPIO_Init` | :173 | :85 | 94.8% | `插入: (空) → * ( uint32_t * ) 0x40022030 ) & 0x0F000000 ) == 0 ) { MCU_Ve` | 🔴 重编号标志的**唯一赋值点**，见第三节第 1 条 —— CH32 在此读 `0x40022030` 的版本位并写入文件级全局 `MCU_Version`。**其余 9 个函数只读不写** —— 先调 `GPIO_SetBits(GPIOC, ...)` 再调 `GPIO_Init()`，前者不会重编号。 |
| 05 | `GPIO_ReadInputDataBit` | :281 | :197 | 85.7% | `插入: (空) → if ( ( GPIOx == GPIOC ) && MCU_Version ) { GPIO_Pin = GPIO_P` | 🔴 GPIOC 引脚重编号，见第三节第 1 条 —— 读引脚前插 `if ((GPIOx == GPIOC) && MCU_Version) { GPIO_Pin = GPIO_Pin >> 13; }`。`MCU_Version` 由 `GPIO_Init()` 赋值 —— **在它之前调用本函数不会重编号**。 |
| 06 | `GPIO_ReadInputData` | :305 | :229 | 49.3% | `替换: return → uint16_t val ; if` | 🔴 GPIOC 引脚重编号（改用局部量承接），见第三节第 1 条 —— CH32 把 `return GPIOx->INDR;` 改成先用局部 `uint16_t val` 承接、在局部量上做 GPIOC 重编号后再返回。同样**依赖 `GPIO_Init()` 先执行**。 |
| 07 | `GPIO_ReadOutputDataBit` | :320 | :259 | 85.7% | `插入: (空) → if ( ( GPIOx == GPIOC ) && MCU_Version ) { GPIO_Pin = GPIO_P` | 🔴 GPIOC 引脚重编号，见第三节第 1 条 —— 同 `GPIO_ReadInputDataBit`，只是读的是 `OUTDR`。 |
| 08 | `GPIO_ReadOutputData` | :343 | :291 | 49.3% | `替换: return → uint16_t val ; if` | 🔴 GPIOC 引脚重编号（改用局部量承接），见第三节第 1 条 —— 同 `GPIO_ReadInputData`，读的是 `OUTDR`。 |
| 09 | `GPIO_SetBits` | :358 | :321 | 66.7% | `插入: (空) → if ( ( GPIOx == GPIOC ) && MCU_Version ) { GPIO_Pin = GPIO_P` | 🔴 GPIOC 引脚重编号，见第三节第 1 条 —— 置位前插 GPIOC 重编号块。**顺序敏感**：先 `GPIO_SetBits(GPIOC, ...)` 后 `GPIO_Init()` 不会重编号。 |
| 10 | `GPIO_ResetBits` | :374 | :344 | 66.7% | `插入: (空) → if ( ( GPIOx == GPIOC ) && MCU_Version ) { GPIO_Pin = GPIO_P` | 🔴 GPIOC 引脚重编号，见第三节第 1 条 —— 同 `GPIO_SetBits`，写 `BCR`。 |
| 11 | `GPIO_WriteBit` | :394 | :369 | 80.9% | `插入: (空) → if ( ( GPIOx == GPIOC ) && MCU_Version ) { GPIO_Pin = GPIO_P` | 🔴 GPIOC 引脚重编号，见第三节第 1 条 —— 同 `GPIO_SetBits`。 |
| 12 | `GPIO_Write` | :417 | :398 | 66.7% | `插入: (空) → if ( ( GPIOx == GPIOC ) && MCU_Version ) { PortVal = PortVal` | 🔴 GPIOC 引脚重编号（改写端口值），见第三节第 1 条 —— CH32 多出 `if ((GPIOx == GPIOC) && MCU_Version) { PortVal = PortVal ... }` —— 整端口值的位序被重排，不只是单个引脚号。 |
| 13 | `GPIO_PinLockConfig` | :432 | :421 | 85.0% | `插入: (空) → if ( ( GPIOx == GPIOC ) && MCU_Version ) { GPIO_Pin = GPIO_P` | 🔴 GPIOC 引脚重编号，见第三节第 1 条 —— 锁定配置前同样插入重编号块。 |
| 15 | `GPIO_EventOutputCmd` | :483 | :473 | 44.1% | `替换: * → if` | 🟢 等价改写（掩码写 → if/else） —— STM32 用 `*(__IO uint32_t *)EVCR_PORTPINCONFIG_MASK = NewState;` 单次写；CH32 写成 if/else 分支读-改-写 `AFIO->EVCR`。净效果相同。 |
| 16 | `GPIO_PinRemapConfig` | :549 | :526 | 73.6% | `插入: (空) → if ( ( ( * ( uint32_t * ) 0x40022030 ) & 0x0F000000 ) == 0 )` | 🟡 旧版芯片适配（CH32 新增） —— CH32 在读 `0x40022030` 判定为早期批次时，对 AFIO 重映射做额外处理；新片不触发。 |
| 18 | `GPIO_ETH_MediaInterfaceConfig` | :630 | :633 | 39.3% | `替换: * → if` | 🟡 无对应外设 —— CH32V20x 无以太网 MAC，该配置项无处落地。保持库内自洽，**用户侧不应调用**。 |

### rcc（9 条 ❌ / 共 35 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `RCC_DeInit` | :217 | :82 | 96.6% | `替换: 0xF8FF0000 → 0xF0FF0000` | 🟢 无需处理 —— STM32 的掩码包在 `#ifndef STM32F10X_CL` 里，本型号取 `0xF8FF0000`（只清 bit26）；CH32 固定 `0xF0FF0000`（清 bit26/27），多清的 bit27 在 CH32 的 `CFGR0` 中同为保留位。末行 ST `0xFF80FFFF` ↔ CH `0xFF00FFFF` 同理（差在保留的 bit24）。**净效果一致**。 |
| 05 | `RCC_HSICmd` | :354 | :187 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 07 | `RCC_PLLCmd` | :401 | :251 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 14 | `RCC_USBCLKConfig` | :728 | :417 | 54.2% | `替换: * → RCC -> CFGR &= ~` | 🟡 用宏名等价，裸值不等价 —— STM32 位带写 `CFGR_USBPRE_BB`，CH32 改为读-改-写 `CFGR0`。⚠ 取值含义已变：`RCC_USBCLKSource_PLLCLK_Div1` 在 STM32 是 `0x01`、CH32 是 `0x00`。用**宏名**调用两侧等价，**裸值 `0x00`/`0x01` 互换**（见 `03_semantic-gaps.md`）。 |
| 17 | `RCC_LSICmd` | :862 | :490 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 19 | `RCC_RTCCLKCmd` | :893 | :530 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 20 | `RCC_GetClocksFreq` | :908 | :552 | 94.6% | `插入: (空) → pllmull == 17 ) pllmull = 18 ; if (` | 🟢 无需处理（CH32 能力适配） —— CH32 在 `case 0x08` 分支补 `if (pllmull == 17) pllmull = 18;` —— CH32 把 `CFGR0` 的 PLLMULL 域（bit18-21）取值 `0b1111` 定义为 **×18**（STM32 无 ×17/×18 档），而取值公式统一是「域值 + 2」，会算出 17，故补一行修正。另 CH32 额外支持 `EXTEN->EXTEN_CTR` 的 HSI 预分频。**旧代码不受影响**。 |
| 29 | `RCC_BackupResetCmd` | :1237 | :815 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 30 | `RCC_ClockSecuritySystemCmd` | :1250 | :832 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |

### misc（2 条 ❌ / 共 5 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `NVIC_PriorityGroupConfig` | :96 | :29 | 78.6% | `替换: SCB -> AIRCR → NVIC_Priority_Group` | 🔴 不写硬件，只记全局变量，见第三节第 4 条 —— STM32 写 `SCB->AIRCR = AIRCR_VECTKEY_MASK \| NVIC_PriorityGroup;`；CH32 只是 `NVIC_Priority_Group = NVIC_PriorityGroup;`。**分组值延迟到 `NVIC_Init()` 才生效 → 两者必须按「先分组、后初始化」顺序调用。** |
| 02 | `NVIC_Init` | :112 | :52 | 27.7% | `替换: uint32_t tmppriority = 0x00 → if ( NVIC_Priority_Group == NVIC_Pri` | 🔴 优先级编码语义已变，见第三节第 4 条 —— CH32 只在 `NVIC_Priority_Group == NVIC_PriorityGroup_1`（开启嵌套）时使用抢占优先级，并按 `<<4` / `<<5` 自行拼装优先级值，不走 STM32 的 AIRCR PRIGROUP 机制。**同名参数、不同含义**。 |

### tim（12 条 ❌ / 共 91 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `TIM_DeInit` | :122 | :40 | 46.9% | `删除: else if ( TIMx == TIM6 ) { RCC_APB1PeriphResetCmd ( RCC_APB1 → (空)` | 🟡 型号实例比较 —— CH32V20x 只有 TIM1~TIM5，删掉了 TIM6/7/8/15/16/17 的复位分支。用到这些定时器的旧代码在 CH32 上无对应硬件。 |
| 02 | `TIM_TimeBaseInit` | :226 | :81 | 85.2% | `删除: TIM8 ) \` | 🟡 型号实例比较 —— 删掉把 TIM8/TIM15/TIM16/TIM17 纳入的重复计数器（RCR）处理分支。 |
| 03 | `TIM_OC1Init` | :279 | :119 | 95.3% | `删除: \` | 🟡 型号实例比较 —— 被删的是实例清单 `\|\| (TIMx == TIM8) \|\| (TIMx == TIM15) \|\| (TIMx == TIM16) \|\| (TIMx == TIM17)`，对应 STM32 用 `IS_TIM_LIST8_PERIPH` 覆盖的更大实例集。**比较逻辑本身未变**。 |
| 04 | `TIM_OC2Init` | :362 | :166 | 99.0% | `删除: \` | 🟡 型号实例比较 —— 同 `TIM_OC1Init`：删的是不可用实例的清单。 |
| 05 | `TIM_OC3Init` | :444 | :211 | 99.0% | `删除: \` | 🟡 型号实例比较 —— 同 `TIM_OC1Init`。 |
| 06 | `TIM_OC4Init` | :523 | :255 | 98.6% | `删除: \` | 🟡 型号实例比较 —— 同 `TIM_OC1Init`。 |
| 57 | `TIM_CCxCmd` | :1974 | :1524 | 89.9% | `插入: (空) → if ( TIM_CCx == TIM_CCx_Disable ) {` | 🟢 等价改写（无条件写 → if/else） —— STM32 无条件做「先 `CCER &= ~tmp` 再 `CCER \|= (TIM_CCx << Channel)`」；CH32 按 `TIM_CCx == TIM_CCx_Disable` 分成两路。使能时两路合并与 STM32 相同；禁用时 STM32 的 `\|= 0` 本就是空操作。**净效果一致**。 |
| 58 | `TIM_CCxNCmd` | :2004 | :1555 | 89.9% | `插入: (空) → if ( TIM_CCxN == TIM_CCxN_Disable ) {` | 🟢 等价改写（无条件写 → if/else） —— 同 `TIM_CCxCmd`，作用于互补输出通道 `CCxNE`。 |
| 88 | `TI1_Config` | :2701 | :2193 | 80.2% | `删除: if ( ( TIMx == TIM1 ) \` | 🟡 型号实例比较 —— 被删的是 `if ((TIMx == TIM1) \|\| (TIMx == TIM8) \|\| (TIMx == TIM2) ...)` 实例清单，CH32 侧只保留可用实例。**输入捕获配置逻辑未变**。 |
| 89 | `TI2_Config` | :2748 | :2232 | 81.8% | `删除: if ( ( TIMx == TIM1 ) \` | 🟡 型号实例比较 —— 同 `TI1_Config`。 |
| 90 | `TI3_Config` | :2797 | :2273 | 81.7% | `删除: if ( ( TIMx == TIM1 ) \` | 🟡 型号实例比较 —— 同 `TI1_Config`。 |
| 91 | `TI4_Config` | :2845 | :2313 | 81.6% | `删除: if ( ( TIMx == TIM1 ) \` | 🟡 型号实例比较 —— 同 `TI1_Config`。 |

### usart（2 条 ❌ / 共 29 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `USART_DeInit` | :130 | :62 | 88.9% | `删除: else { if ( USARTx == UART5 ) { RCC_APB1PeriphResetCmd ( RCC → (空)` | 🟡 型号分支，本型号不涉及 —— CH32V20x 无 UART5，删掉该支。 |
| 02 | `USART_Init` | :176 | :99 | 79.1% | `替换: uint32_t → uint64_t` | 🟡 加宽中间变量，防溢出 —— `tmpreg` / `apbclock` 由 `uint32_t` 改为 `uint64_t`。CH32 的 APB 时钟可远高于 STM32F103（最高 144 MHz），`25 * apbclock` 在 32 位下会溢出。**波特率计算结果正确，无需处理**。 |

### spi（2 条 ❌ / 共 23 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `SPI_I2S_DeInit` | :119 | :58 | 81.2% | `删除: else { if ( SPIx == SPI3 ) { RCC_APB1PeriphResetCmd ( RCC_AP → (空)` | 🟡 型号分支，本型号不涉及 —— CH32V20x_D6 无 SPI3（`SPI3` 相关位定义不参与编译），删掉该支。 |
| 04 | `SPI_StructInit` | :370 | :192 | 95.0% | `删除: SPI_NSS = SPI_NSS_Hard ; SPI_InitStruct -> → (空)` | 🔴 少初始化一个成员，见第三节第 2 条 —— CH32 **不写** `SPI_InitStruct->SPI_NSS`（STM32 写 `SPI_NSS_Hard`）。`SPI_InitTypeDef s; SPI_StructInit(&s); SPI_Init(SPI1, &s);` 这条最常见写法下，`s.SPI_NSS` 是**未初始化的栈值**。 |

### i2c（1 条 ❌ / 共 33 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 02 | `I2C_Init` | :191 | :127 | 98.1% | `插入: (空) → if ( freqrange >= 60 ) { freqrange = 60 ; }` | 🟡 高时钟下的钳位 —— 源工程不触发、迁移后可能触发 —— CH32 补 `if (freqrange >= 60) freqrange = 60;`。`freqrange = PCLK1 / 1MHz`，仅在 PCLK1 ≥ 60 MHz 时生效，用于封顶上升时间寄存器的计算。⚠ **这一支在源工程上永不触发、迁移后却会生效**：STM32F103 的 PCLK1 最高 36 MHz，而 CH32V203 的 APB1 可达 144 MHz —— 若用户把 PCLK1 配到 ≥60 MHz，I2C 上升时间计算会被钳位到 60，须按实际 I2C 速率核对。 |

### dma（5 条 ❌ / 共 11 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `DMA_DeInit` | :108 | :42 | 82.6% | `替换: DMA2_Channel1 → DMA1_Channel8` | 🟡 单 DMA / 双 DMA 差异 —— STM32 覆盖 DMA1 通道 1-7 + DMA2 通道 1-5；CH32V20x 只有 **一个 DMA1、8 个通道**。CH32 侧 `DMA1_Channel8`（第 61/62 号中断）是无对应物的新增通道。⚠ 用 `DMA2_Channel*` 的旧代码在 CH32 上无硬件可落。 |
| 08 | `DMA_GetFlagStatus` | :433 | :266 | 81.5% | `删除: if ( ( DMAy_FLAG & FLAG_Mask ) != ( uint32_t ) RESET ) { tmp → (空)` | 🔴 只读 DMA1，见第三节第 6 条 —— STM32 按 `DMAy_FLAG & FLAG_Mask` 选择读 `DMA2->ISR` 还是 `DMA1->ISR`；CH32 固定读 `DMA1->INTFR`，**传 DMA2 标志不会报错，只会读到错的寄存器**。 |
| 09 | `DMA_ClearFlag` | :523 | :325 | 53.8% | `删除: { if ( ( DMAy_FLAG & FLAG_Mask ) != ( uint32_t ) RESET ) { D → (空)` | 🔴 同 `DMA_GetFlagStatus` —— CH32 固定操作 `DMA1->INTFCR`，无 DMA2 分支。 |
| 10 | `DMA_GetITStatus` | :595 | :371 | 81.5% | `删除: if ( ( DMAy_IT & FLAG_Mask ) != ( uint32_t ) RESET ) { tmpre → (空)` | 🔴 同 `DMA_GetFlagStatus` —— CH32 固定读 `DMA1->INTFR`，无 DMA2 分支。 |
| 11 | `DMA_ClearITPendingBit` | :684 | :429 | 53.8% | `删除: { if ( ( DMAy_IT & FLAG_Mask ) != ( uint32_t ) RESET ) { DMA → (空)` | 🔴 同 `DMA_GetFlagStatus` —— CH32 固定操作 `DMA1->INTFCR`，无 DMA2 分支。 |

### flash（10 条 ❌ / 共 39 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 09 | `FLASH_EraseAllPages` | :492 | :169 | 95.7% | `插入: (空) → FLASH_EraseAll_Delay ( 150000 ) ;` | 🟢 无需处理（CH32 新增等待） —— CH32 在全片擦除后补 `FLASH_EraseAll_Delay(150000)`（D8/D8W 用 180000）—— 一个纯 NOP 循环，等硬件擦除真正完成（宏定义见 `ch32v20x_flash.c:76`）。STM32 侧无此等待。**只会更稳，不改变语义**。 |
| 10 | `FLASH_EraseAllBank1Pages` | :555 | :199 | 95.7% | `插入: (空) → FLASH_EraseAll_Delay ( 150000 ) ;` | 🟢 同上（CH32 新增等待） —— 同 `FLASH_EraseAllPages`，尾部补 NOP 等待循环。 |
| 11 | `FLASH_EraseOptionBytes` | :616 | :229 | 82.8% | `插入: (空) → uint32_t Address = 0x1FFFF800 ; __IO uint8_t i ;` | 🟠 选项字节写法重写 —— CH32 直接以 `0x1FFFF800` 为基址、用 `__IO uint8_t i` 逐字节回读校验，不再用 STM32 那套 `FLASH->OBR` / `FLASH_OPTCR` 位操作。调用接口不变，但**若用户代码依赖读回值与 STM32 一致，需要实测**。 |
| 20 | `FLASH_ProgramOptionByteData` | :929 | :363 | 37.8% | `插入: (空) → uint32_t Addr = 0x1FFFF800 ; __IO uint8_t i ; uint16_t pbuf` | 🟠 选项字节写法重写 —— 同 `FLASH_EraseOptionBytes`：改为直接按 `0x1FFFF800` 基址操作。 |
| 23 | `FLASH_EnableWriteProtection` | :975 | :413 | 50.5% | `插入: (空) → uint32_t Addr = 0x1FFFF800 ; __IO uint8_t i ; uint16_t pbuf` | 🟠 写保护粒度已变，见 `03_semantic-gaps.md` —— CH32 改按 `0x1FFFF800` 直接写；且 `FLASH_WRProt_*` 一侧按页、一侧按 4KB sector，**照搬宏名会静默改变保护范围**。 |
| 26 | `FLASH_ReadOutProtection` | :1049 | :471 | 47.3% | `插入: (空) → ; uint32_t Addr = 0x1FFFF800 ; __IO uint8_t i ; uint16_t pbu` | 🟠 选项字节写法重写 —— 同 `FLASH_EraseOptionBytes`：改为直接按 `0x1FFFF800` 基址操作。 |
| 27 | `FLASH_UserOptionByteConfig` | :1118 | :529 | 36.2% | `插入: (空) → uint32_t Addr = 0x1FFFF800 ; __IO uint8_t i ; uint16_t pbuf` | 🟠 选项字节写法重写 —— 同 `FLASH_EraseOptionBytes`：改为直接按 `0x1FFFF800` 基址操作。 |
| 34 | `FLASH_GetFlagStatus` | :1357 | :652 | 96.5% | `替换: FLASH_FLAG_OPTERR → ( 1 << 0 )` | 🟢 无需处理（CH32 库内自洽） —— CH32 对 `FLASH_FLAG_OPTERR` 单独开分支读 `FLASH->OBR` bit0（CH32 的 `STATR` 无该位），其余标志照读 `STATR`。**用宏名调用结果正确**。⚠ 该宏取值与 `FLASH_FLAG_BSY` 数值重合，**禁止把宏值当数字传**。 |
| 36 | `FLASH_GetStatus` | :1477 | :705 | 85.3% | `删除: FLASH_FLAG_PGERR ) != 0 ) { flashstatus = FLASH_ERROR_PG ; } → (空)` | 🔴 PGERR 分支被删，见第三节第 3 条 —— CH32 只判 `BSY` / `WRPRTERR`，**`FLASH_ERROR_PG` 永不返回**。`if (FLASH_GetStatus() == FLASH_ERROR_PG)` 这类判断在 CH32 上恒不成立。 |
| 37 | `FLASH_GetBank1Status` | :1515 | :735 | 85.3% | `删除: FLASH_FLAG_BANK1_PGERR ) != 0 ) { flashstatus = FLASH_ERROR_ → (空)` | 🔴 同 `FLASH_GetStatus` —— CH32 删掉了 PGERR 分支，`FLASH_ERROR_PG` 不会返回。 |

### adc（2 条 ❌ / 共 39 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `ADC_DeInit` | :179 | :120 | 81.2% | `删除: else { if ( ADCx == ADC3 ) { RCC_APB2PeriphResetCmd ( RCC_AP → (空)` | 🟡 型号分支，本型号不涉及 —— 被删分支指向 CH32V20x 不具备的外设实例（GPIOE / ADC3 / CAN2 / UART5 / SPI3 等）。 |
| 02 | `ADC_Init` | :218 | :147 | 95.4% | `插入: (空) → \` | 🟢 等价改写（续行符） —— STM32 用 `\` 续行写长表达式，CH32 写成单行。归一化后一致，**无需处理**。 |

### can（2 条 ❌ / 共 25 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 01 | `CAN_DeInit` | :122 | :62 | 78.5% | `删除: else { RCC_APB1PeriphResetCmd ( RCC_APB1Periph_CAN2 , ENABLE → (空)` | 🟡 型号分支，本型号不涉及 —— CH32V20x 只有 CAN1（库内所有操作都直接写 `CAN1`），删掉 CAN2 分支。 |
| 03 | `CAN_FilterInit` | :292 | :195 | 90.3% | `插入: (空) → ( ( * ( uint32_t * ) 0x40022030 ) & 0x0F000000 ) == 0 ) { ui` | 🟡 旧版芯片适配（CH32 新增） —— CH32 在读 `0x40022030` 判定为早期批次时，把滤波 RAM 的 64 个半字从 `+768` 搬到 `+512`；D8/D8W 另有一条带自检的等价分支。新片不触发。 |

### pwr（3 条 ❌ / 共 14 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 02 | `PWR_BackupAccessCmd` | :124 | :44 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 03 | `PWR_PVDCmd` | :137 | :65 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 05 | `PWR_WakeUpPinCmd` | :178 | :114 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |

### rtc（2 条 ❌ / 共 14 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 04 | `RTC_GetCounter` | :133 | :73 | 31.6% | `替换: tmp → high1a = 0 , high1b = 0 , high2a = 0 , high2b` | 🟢 无需处理（CH32 更稳） —— CH32 改成「连读两次 `CNTH` 至稳定 → 连读两次 `CNTL` 至稳定 → 再读 `CNTH`，若高位变了就重读低位」的防翻转序列。STM32 只读一次。**返回值语义一致，CH32 侧在计数器翻转瞬间更可靠。** |
| 08 | `RTC_GetDivider` | :193 | :163 | 24.3% | `替换: uint32_t tmp → uint16_t high1a` | 🟢 无需处理（CH32 更稳） —— 同上：CH32 用双读稳定序列取 `DIV`，STM32 单次读。返回值语义一致。 |

### bkp（5 条 ❌ / 共 12 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 02 | `BKP_TamperPinLevelConfig` | :134 | :45 | 39.3% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 03 | `BKP_TamperPinCmd` | :147 | :66 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 04 | `BKP_ITConfig` | :160 | :87 | 44.1% | `替换: * → if` | 🟢 等价改写（位带 → 读改写） —— STM32 用位带别名地址 `*(__IO uint32_t *)X_BB = ...` 单次写；CH32 是 RISC-V 无位带，改为读-改-写或 if/else。净效果相同，**无需处理**。 |
| 09 | `BKP_GetFlagStatus` | :259 | :191 | 35.3% | `插入: (空) → if ( BKP -> CSR & ( 1 << 8 ) ) {` | 🟢 等价改写 —— STM32 走 `BKP->CSR` 的位读取宏，CH32 直接 `if (BKP->CSR & (1 << 8))`。等价。 |
| 11 | `BKP_GetITStatus` | :280 | :222 | 35.3% | `插入: (空) → if ( BKP -> CSR & ( 1 << 9 ) ) {` | 🟢 等价改写 —— 同上，CH 写 `if (BKP->CSR & (1 << 9))`。等价。 |

### iwdg（1 条 ❌ / 共 6 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 05 | `IWDG_Enable` | :148 | :92 | 66.7% | `插入: (空) → while ( ( RCC -> RSTSCKR & 0x2 ) == RESET ) ;` | 🟡 CH32 新增等待 —— CH32 在写入使能键后补 `while ((RCC->RSTSCKR & 0x2) == RESET);`，等 LSI 就绪（`RSTSCKR` bit1 = LSIRDY）。**若 LSI 始终不起振，这里会死等** —— 排查「卡在 `IWDG_Enable` 里」时想到这一条。 |

### wwdg（1 条 ❌ / 共 8 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 04 | `WWDG_EnableIT` | :159 | :85 | 54.1% | `替换: * → WWDG -> CFR \` | 🟢 等价改写（位带 → 读改写） —— STM32 位带写 `CFR_EWI_BB`；CH32 改 `WWDG->CFGR \|= (1 << 9)`。等价。 |

### dbgmcu（3 条 ❌ / 共 6 个函数）

| # | 函数 | STM32 位置 | CH32 位置 | 归一化相似度 | 源码差异片段 | 迁移动作 |
|---:|---|---|---|---:|---|---|
| 03 | `DBGMCU_GetREVID` | :84 | :23 | 59.5% | `替换: DBGMCU -> IDCODE >> 16 → ( * ( uint32_t * ) 0x1FFFF704 ) & IDCODE_` | 🔴 返回值与函数名对不上，见第三节第 5 条 —— CH32 的 `DBGMCU_GetREVID()` 返回 `*(uint32_t*)0x1FFFF704 & IDCODE_DEVID_MASK`（这是**器件 ID**），而 STM32 的 `DBGMCU_GetREVID()` 返回 `DBGMCU->IDCODE >> 16`（这是**版本号**）。同时地址也从内存映射的 `0xE0042000` 换成 `0x1FFFF704`。 |
| 04 | `DBGMCU_GetDEVID` | :94 | :35 | 59.5% | `替换: DBGMCU -> IDCODE & IDCODE_DEVID_MASK → ( * ( uint32_t * ) 0x1FFFF7` | 🔴 返回值与函数名对不上，见第三节第 5 条 —— 与 `DBGMCU_GetREVID` **互换**：CH32 的 `DBGMCU_GetDEVID()` 返回 `>> 16`（版本号）。要取器件 ID 反而应调 `DBGMCU_GetREVID()`。 |
| 06 | `DBGMCU_Config` | :134 | :85 | 66.7% | `插入: (空) → uint32_t val ;` | 🔴 整体覆写而非读-改-写，见 `07_pointer-and-bitband.md` 1.2 —— CH32 新增局部 `uint32_t val;`，实现改成整体覆写内核 CSR `0x7C0`。**单次多标志合并调用两侧等价；连续两次分开调用会互相清除。** |

---

逐函数**源码并排对照**（左 STM32 / 右 CH32）见 `_periph_diff/02_modules/<模块>.md` 第 3.2 节，或对应的 PDF 报告。本页只给结论与动作，不重复源码。
