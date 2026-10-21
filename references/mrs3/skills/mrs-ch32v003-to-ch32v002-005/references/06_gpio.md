# 06 GPIO 专项

规则原文：差异较大。`GPIO_Speed` 宏定义差异，V002/5 只有一组 `GPIO_Speed_30MHz`，所有调用的整体替换；
外设引脚重映射差异大，参数定义大多不一致；库文件替换 V002/5。

---

## 6.1 GPIO_Speed：3 档 → 1 档

两侧定义（`ch32v00x_gpio.h` / `ch32v00X_gpio.h`，枚举本体）：

| V003 | 值 | 目标侧 | 值 |
|---|---|---|---|
| `GPIO_Speed_10MHz` | 1 | — | — |
| `GPIO_Speed_2MHz` | 2 | — | — |
| `GPIO_Speed_30MHz` | 3 | `GPIO_Speed_30MHz` | **1** |
| `GPIO_Speed_50MHz`（宏别名 = 30MHz） | — | — | — |

**处理**：用户代码里所有 `GPIO_Speed_10MHz` / `GPIO_Speed_2MHz` / `GPIO_Speed_50MHz`
统一改成 `GPIO_Speed_30MHz`。目标侧无低速档位，输出速度统一为 30MHz。

`GPIO_Speed_30MHz` **同名但值不同（3 → 1）**，但它是枚举、赋给 `GPIOSpeed_TypeDef` 字段，
用宏名即正确 → 🟡 不必"修正"这个数值。

---

## 6.2 GPIO_Mode：两侧完全相同 ✅

| 枚举 | 值（两侧一致） |
|---|---|
| `GPIO_Mode_AIN` | `0x0` |
| `GPIO_Mode_IN_FLOATING` | `0x04` |
| `GPIO_Mode_IPD` | `0x28` |
| `GPIO_Mode_IPU` | `0x48` |
| `GPIO_Mode_Out_OD` | `0x14` |
| `GPIO_Mode_Out_PP` | `0x10` |
| `GPIO_Mode_AF_OD` | `0x1C` |
| `GPIO_Mode_AF_PP` | `0x18` |

不用改。

---

## 6.3 GPIO_Pin：0..7 相同，All 不同

`GPIO_Pin_0` … `GPIO_Pin_7` 两侧位值完全相同（`0x0001` … `0x0080`）→ 🟡 不用改。

| 宏 | V003 | 目标侧 |
|---|---|---|
| `GPIO_Pin_All` | `0xFFFF` | `0x00FF` |

🟠 用 `GPIO_Pin_All` 的地方（如 `GPIO_SetBits(GPIOx, GPIO_Pin_All)`）在目标侧只覆盖低 8 位。

---

## 6.4 GPIO 函数：同名同签名 ✅

`GPIO_DeInit` `GPIO_AFIODeInit` `GPIO_Init` `GPIO_StructInit` `GPIO_ReadInputDataBit`
`GPIO_ReadInputData` `GPIO_ReadOutputDataBit` `GPIO_ReadOutputData` `GPIO_SetBits`
`GPIO_ResetBits` `GPIO_WriteBit` `GPIO_Write` `GPIO_PinLockConfig` `GPIO_EventOutputConfig`
`GPIO_EventOutputCmd` `GPIO_PinRemapConfig` `GPIO_EXTILineConfig`

两侧完全一致。目标侧另有新增的 `GPIO_IPD_Unused(void)`。

---

## 6.5 引脚重映射 🔴 —— 不存在 1:1 映射表

`GPIO_PinRemapConfig(uint32_t GPIO_Remap, FunctionalState NewState)` 两侧同名同签名，
但**可选参数集合与取值都不同**。规则文件所说「参数定义大多不一致」属实，且程度比描述更深。

### V003 侧可选值（18 个）

| 外设 | V003 可选 |
|---|---|
| I2C1 | `GPIO_PartialRemap_I2C1` · `GPIO_FullRemap_I2C1` |
| SPI1 | `GPIO_Remap_SPI1` |
| TIM1 | `GPIO_PartialRemap1_TIM1` · `GPIO_PartialRemap2_TIM1` · `GPIO_FullRemap_TIM1` |
| TIM2 | `GPIO_PartialRemap1_TIM2` · `GPIO_PartialRemap2_TIM2` · `GPIO_FullRemap_TIM2` |
| USART1 | `GPIO_PartialRemap1_USART1` · `GPIO_PartialRemap2_USART1` · `GPIO_FullRemap_USART1` |
| ADC 触发 | `GPIO_Remap_ADC1_ETRGINJ` · `GPIO_Remap_ADC1_ETRGREG` |
| 其他 | `GPIO_Remap_LSI_CAL` · `GPIO_Remap_PA1PA2`（别名 `GPIO_Remap_PA1_2`） · `GPIO_Remap_SDI_Disable` |

### 目标侧可选值（部分，按引脚组合细分到 4–8 档）

| 外设 | 目标侧可选（节选） |
|---|---|
| I2C1 | `GPIO_PartialRemap1/2/3_I2C1` · `GPIO_FullRemap4_I2C1` |
| SPI1 | `GPIO_PartialRemap1..5_SPI1` · `GPIO_FullRemap_SPI1` |
| TIM1 | `GPIO_PartialRemap1..8_TIM1` · `GPIO_FullRemap_TIM1` |
| TIM2 | `GPIO_PartialRemap1..6_TIM2` · `GPIO_FullRemap_TIM2` |
| USART1 | `GPIO_PartialRemap1..8_USART1` · `GPIO_FullRemap_USART1` |
| USART2 | `GPIO_PartialRemap1..5_USART2` · `GPIO_FullRemap_USART2`（V003 无 USART2） |
| ADC 触发 | `GPIO_Remap_ADC1_ETRGINJ` · `GPIO_Remap_ADC1_ETRGREG` · `GPIO_Remap_LSI_CAL` |
| 其他 | `GPIO_Remap_PA1_2` · `GPIO_Remap_SDI_Disable` |

### 同名宏的值也不同（🔴 零提示）

| 宏 | V003 值 | 目标侧值 |
|---|---|---|
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
| `GPIO_Remap_PA1_2` | `0x00008000`（V003 里是 `GPIO_Remap_PA1PA2` 的别名） | `0x00200002`（目标侧是本体，无 `PA1PA2` 名） |
| `GPIO_Remap_SDI_Disable` | `0x00300400` | `0x08300400` |

> **不要"照着原宏名换一个相近的"**。同名宏在两侧指的不是同一组引脚。
> 例如 `GPIO_FullRemap_USART1` 在 V003 是 `0x80200004`、目标侧是 `0x00160240`，
> 即便宏名相同，落到寄存器上的位完全不同。

### 处理流程

1. 先在源代码注释 / 原理图 / 用户说明中确认**原先重映射是为了把哪个外设的哪几个信号引到哪几个物理引脚**；
2. 到目标芯片的引脚定义（目标 EVT 里对应外设的 `EXAM` 例程或数据手册）中找**能实现同一组物理引脚**的重映射档位；
3. 用目标侧的宏名替换，**不要保留 V003 的宏名**。

若无法确认原意（源码无注释、无原理图），**停下询问**，不要凭"名字相近"猜一个。

### 相关联的 AFIO 宏（同名异值，同样不能沿用原值）

| 宏 | V003 | 目标侧 |
|---|---|---|
| `AFIO_PCFR1_SPI1_REMAP` | `0x00000001` | `0x00000007` |
| `AFIO_PCFR1_I2C1_REMAP` | `0x00000002` | `0x00000038` |
| `AFIO_PCFR1_USART1_REMAP` | `0x00000004` | `0x000003C0` |
| `AFIO_PCFR1_TIM1_REMAP` | `0x000000C0` | `0x00003C00` |
| `AFIO_PCFR1_TIM2_REMAP` | `0x00000300` | `0x0001C000` |

### GPIO CFGLR 寄存器的模式位（同名异值）

`GPIO_CFGLR_MODE` / `MODE0..7` 及其 `_0/_1` 子位，两侧位定义不同
（`GPIO_CFGLR_MODE` V003 `0x33333333` → 目标 `0x11111111`）。
用户若直接用这些位宏操作 `GPIOx->CFGLR`，必须按目标侧布局重写；
用 `GPIO_Init()` + `GPIO_Mode_*` 的写法不受影响。

---

## 6.6 阶段 3 强制核对清单（GPIO）

- [ ] `GPIO_Speed_10MHz` / `_2MHz` / `_50MHz` 是否已全部改为 `GPIO_Speed_30MHz`
- [ ] 是否有 `GPIO_Pin_All` 的用法 → 目标侧只覆盖低 8 位
- [ ] 所有 `GPIO_PinRemapConfig` 调用 → 按目标引脚重选档位，**不得沿用 V003 宏名/值**
- [ ] 是否有直接操作 `GPIOx->CFGLR` 的代码 → 按目标侧位布局重写
- [ ] 用到的引脚在目标封装上是否存在（`01_model-and-project.md` 的封装表）
