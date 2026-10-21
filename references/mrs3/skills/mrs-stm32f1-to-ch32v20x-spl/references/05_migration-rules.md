# 替换与修复规则

> 本文件是执行移植时的判定依据。所有结论已逐项核对两侧库源码，可直接引用。
> 引用格式 `文件:行号` 均指 CH32V20x EVT 包内的 `EVT/EXAM/SRC/Peripheral` 或设备头。

## 一、四条判定原则

移植中遇到的每一个符号，先归类再动手。**归类错了，改得越多错得越多。**

| 类型 | 特征 | 处理 | 占比 |
|---|---|---|---|
| **甲** 目标库无此符号 | 编译报「未声明」，或在改名表里查到新名 | 查映射表改名；查不到就确认是否属于缺失能力 | 绝大多数 |
| **乙** 同名、同义、仅编码不同 | 名字一样，数值可能不同 | **不要动**。目标库内部自洽，用宏名即正确 | 常见 |
| **丙** 同名、语义不同 | 名字一样，含义被换了 | 必须重做逻辑 | 极少 |
| **丁** 用户代码绕过符号名 | 直接写数值、地址、位掩码、位带 | **编译器不会报错**，查 `07_pointer-and-bitband.md` | 隐蔽 |

**乙 类是本次移植最反直觉的一点**：两侧数值不同 ≠ 需要修改。例如 `DBGMCU_TIM1_STOP`
在 STM32 是 `0x400`、在 CH32 是 `0x1000`，但两侧都叫这个名字且都表示「调试时暂停 TIM1」，
用户代码 `DBGMCU_Config(DBGMCU_TIM1_STOP, ENABLE)` 换成 CH32 头文件后**自动就是对的**。
此时去把代码里的宏名改成别的，反而会引入错误。

反过来，**丙 类必须高度警惕**：名字相同、数值也可能相同，但含义被换了，
编译器不会报警。全部 🔴 项已在 `references/03_semantic-gaps.md` 第一节列出，
只有 3 项。

**丁 类的性质与甲、乙、丙都不同**：它不是「改对改错」的问题，而是**根本没有编译期反馈**。
用户代码里写 `*(volatile uint32_t *)0x4001080C` 或位带别名地址 `0x42420000` 时，
改名表帮不上忙，编译器也一句话不说。这一类必须靠主动扫描 + 逐条核对，
详见 `references/07_pointer-and-bitband.md`。

## 二、工程基线替换（改任何用户代码之前先完成）

| # | 动作 | 说明 |
|---:|---|---|
| 1 | 头文件整体换名 | `stm32f10x.h`→`ch32v20x.h`；`stm32f10x_conf.h`→`ch32v20x_conf.h`；`stm32f10x_it.c/h`→`ch32v20x_it.c/h`；`stm32f10x_<外设>.h`→`ch32v20x_<外设>.h`；`misc.h`→`ch32v20x_misc.h`；`system_stm32f10x.c/h`→`system_ch32v20x.c/h` |
| 2 | 内核头文件 | `core_cm3.h` 无对应，改 `core_riscv.h`（由 `ch32v20x.h` 自动引入）。**不要保留 `core_cm3.h` 的 include** |
| 3 | 移出 STM32 库源文件 | 用户工程里若存在 `stm32f10x_*.c` / `system_stm32f10x.c` / `core_cm3.c`，**移出编译列表**，改用 CH32 EVT 的对应源文件。⚠ **只移出编译列表，不要从工程目录里删除源文件** —— 交付前的「已用符号功能一致性复核」要读它对照。**读 ST 库源码的落点是新工程根目录下的 `.mrs/originalKeilFiles/`**（工程级转换导入的原始 Keil 工程文件，含 ST 外设库源码与用户代码）：只读、**不得编辑**、**不得加入编译列表 / include 路径**，并在**交付前随该目录一起删除**（`SKILL.md` 阶段 4.4）—— ⚠ **两个对象别混**：**本项移出的这些文件永不删除**，删的只是 `.mrs/` 下那份**临时副本**；该目录不存在时停下向用户索要源码或请其重跑工程级转换，**不得凭记忆推断**。⚠ **执行本项之前先核对源库版本**（读 `stm32f10x.h:135-142` 的 `__STM32F10X_STDPERIPH_VERSION`，应为 `0x03500000`）—— 本技能映射表按**官方 SPL V3.5.0** 建立，库一旦移出编译列表就再也对不了。⚠ **不要拿 `stm32f10x_*.c` 通配一刀切**：先按**官方 SPL 白名单**甄别 —— 官方 V3.5.0 只有 **23 个模块**（`misc` + `adc bkp can cec crc dac dbgmcu dma exti flash fsmc gpio i2c iwdg pwr rcc rtc sdio spi tim usart wwdg`），白名单**外**的库目录 `.c` / `.h` = **用户在库里新增的文件，不要移出**，按用户代码纳入迁移（通配移出会让其功能静默丢失）。见 `SKILL.md`「适用前提」与「已用符号功能一致性复核专项」 |
| 4 | 型号宏 | STM32 的 `STM32F10X_LD/MD/HD/XL/CL/VL` 全部失效。**D6 目标（V203 全系）不需要任何配置** —— `ch32v20x.h:19-24` 会在三个型号宏均未定义时自动 `#define CH32V20x_D6`，这是 WCH 官方默认路径（EVT 中 176 个 D6 工程无一显式定义），**不要为此去改工程属性文件**。仅 **D8 / D8W（V208 / V203RBT）** 才须显式生效：改 `ch32v20x.h:20-22` 那三行注释（顺序安全）。⚠ **禁止放进 `ch32v20x_conf.h`** —— 它被 `ch32v20x.h:4881`（末尾）才包含，而设备头自身的 D8/D8W 条件编译在 `:30 / :116 / :125 / :749 / :794 / :874 / :930`，晚了 4800 行，根本看不到 |
| 5 | `assert_param` | STM32 的校验宏体系在 CH32 侧整体不存在（264 个 `IS_*` 宏）。见 `references/03_semantic-gaps.md` 第四节 |
| 6 | 中断服务函数属性 | 每个 `XXX_IRQHandler` 定义**必须**加属性：**硬件压栈**用 `__attribute__((interrupt("WCH-Interrupt-fast")))`，**软件压栈**用 `__attribute__((interrupt()))`（无参数）。函数名与 STM32 同名，可沿用；缺属性会导致中断触发时上下文保存/恢复不符合 RISC-V 约定。硬件压栈需用 MRS 或其工具链编译 |
| 7 | 时钟初始化与主频 | `SystemInit()` → `SystemInit()` + `SystemCoreClockUpdate()`（后者在时钟配置变更后必须重新调用，Delay 与波特率都依赖它）；**并确认 `SYSCLK_FREQ_*` 档位与 AHB 分频使 HCLK 与源工程一致**（见 3.5） |
| 8 | 启动文件与链接脚本 | 用 EVT 的 `startup_ch32v20x_D6.S` / `D8.S` / `D8W.S` 与对应 `.ld`，不可沿用 STM32 的 `.s` / `.ld` |
| 9 | 浮点打印 | 检测原工程是否有 printf 浮点格式（`%f` / `%e` / `%g` / `%a`，含 `%0.1f` 这类精度写法）—— 有则**通知 MRS 内智能体开启**链接器选项 `Use wchprintfloat(-lprintfloat)`（**默认关闭**）。关闭状态下浮点项**编译、链接均不报错、运行期不打印**。⚠ **不要自行改 `.cproject` / `.uvprojx`**；原工程无浮点输出则保持关闭（该选项会显著增大体积）。详见 `SKILL.md`「printf 与浮点打印专项」 |
| 10 | 库被本地修改的检出（**交付前**执行） | 见 `SKILL.md`「已用符号功能一致性复核专项」：对用户代码**实际用到的外设库函数**逐一核对两侧行为语义 —— 有官方基线处 🔴 不一致须补实现并登记、🟠 无基线处只列「待人工确认清单」；并按官方 SPL 白名单甄别库文件增删。⚠ **不在本阶段执行** —— 第 1–9 项是「改用户代码之前」的基线替换，本项要等**编译通过之后**（阶段 4.3）才做，因为「用到的符号集合」那时才定形；且**必须在删除 `.mrs/originalKeilFiles/` 之前完成**（本项要读其中的 ST 侧源码，`SKILL.md` 阶段 4.4） |

## 三、🔴 必须重做的语义差异与关键配置（全部 5 项）

### 3.1 NVIC 优先级分组 —— `NVIC_PriorityGroup_0` / `_1`

**这是唯一一类「名字相同、数值不同、含义也完全不同」的宏。**

| | STM32 标准外设库 | CH32V20x |
|---|---|---|
| 可选分组 | `Group_0` ~ `Group_4`（5 组） | 只有 `Group_0` 与 `Group_1`（2 组） |
| 分组选择依据 | 抢占位数 | **由 CSR(0x804) bit1 的中断嵌套开关在启动文件里决定** |
| `Group_0` 含义 | 0 位抢占 + 4 位子优先级 | 嵌套关闭：抢占固定 0，子优先级 0–7 |
| `Group_0` 取值 | `0x700` | `0x00` |
| `Group_1` 含义 | 1 位抢占 + 3 位子优先级 | 嵌套开启：抢占 0–1，子优先级 0–3 |
| `Group_1` 取值 | `0x600` | `0x01` |
| `Group_2`~`Group_4` | 存在 | **不存在** |

CH32 的 `NVIC_PriorityGroupConfig()` 只是把参数存进一个全局变量，真正的分组行为由
`NVIC_Init()` 在写入优先级时按嵌套开关展开（`ch32v20x_misc.c:52-81`）。

> ⚠️ **`NVIC_PriorityGroup_0` 与 `_1` 在 CH32 侧是编译期互斥的**（`ch32v20x_misc.h:59-63`）：
> 头文件用 `#if (INTSYSCR_INEST == INTSYSCR_INEST_NoEN)` 二选一，**默认
> （`INTSYSCR_INEST = INTSYSCR_INEST_EN`，`ch32v20x_misc.h:36-37`）只定义了
> `NVIC_PriorityGroup_1`**。因此用户代码若写 `NVIC_PriorityGroupConfig(NVIC_PriorityGroup_0)`，
> 在默认配置下会直接编译报错——这是 fail-fast，属好事，但排查时要知道原因不是「拼写错误」。
> `NVIC_PriorityGroup_2`~`_4` 则根本不存在，同样编译报错。

**处理步骤：**

1. 判定用户工程原先用的是哪一组：
   - STM32 `Group_2`（2 位抢占 + 2 位子优先级）是绝大多数工程的默认选择。
   - CH32 侧没有 2 位抢占的模式，最接近的是 **`Group_1`**（1 位抢占 + 2 位子优先级）。
2. 把 `NVIC_PriorityGroupConfig(NVIC_PriorityGroup_2)` 改为 `NVIC_PriorityGroupConfig(NVIC_PriorityGroup_1)`。
3. **重新计算每个中断的优先级数值**：原抢占优先级取值 `0-3` 需压缩到 `0-1`，原子优先级 `0-3` 保持。
   压缩规则：抢占优先级 `0` 与 `1` 保持，`2` 与 `3` 折到 `1`。
4. 若原工程依赖 3 层以上抢占嵌套，**这套优先级在 CH32 上无法原样表达**，需要重新设计中断响应关系，
   此时必须向用户说明，不可自行降级。
5. 确认启动文件里的嵌套开关与代码一致（`INTSYSCR_INEST`，默认开启，见 `ch32v20x_misc.h:36-38`）。

> 若用户工程只是用 `NVIC_Init` 配置一两个中断且不依赖嵌套顺序，可退化为：
> `NVIC_PriorityGroupConfig(NVIC_PriorityGroup_1)` + 抢占优先级全部填 0 + 子优先级保持原值。

其他 misc 差异：

| STM32 符号 | 状态 | 处理 |
|---|---|---|
| `NVIC_SetVectorTable` | CH32 无 | 向量表由启动文件决定，删除该调用；若原工程靠它做 Bootloader 跳转，需改为 RISC-V 的中断入口重定位方式，属需人工确认项 |
| `NVIC_SystemLPConfig` | CH32 无 | CH32 的低功耗进入方式不同，删除并改用 `PWR_EnterSTOPMode` / `PWR_EnterSTANDBYMode` |
| `SysTick_CLKSourceConfig` | CH32 无此函数 | 🟠 **分三种情况，不要一律补实现。** ① **源工程的延时用 SysTick（滴答定时器）** —— 按「延时与 SysTick 专项」路线 ②，改用 CH32 侧的 `Delay_Us` / `Delay_Ms`（定义在 `EVT/EXAM/SRC/Debug/debug.c`，须把 `Debug/` 目录连同 `debug.h` 一并加进工程，并在 `SystemCoreClockUpdate()` 之后调 `Delay_Init()`），此时**直接删除该调用、不要再补实现** —— SysTick 由 `debug.c` 接管（它每次调用都会改写 `CTLR`），两处都配会互相踩。② **源工程的延时用空循环（本就不涉及 SysTick）** —— 按路线 ① 改用 `__NOP()` 忙等（**不占 SysTick**），这条调用原本也不该存在；若用户在别处配了 SysTick，按其原意保留、各自处理。③ **用户另有基于 SysTick 的独立功能**（跑表 / OS 节拍 / 自建时基）—— 才需要自配，改法见 `SKILL.md` 的「延时与 SysTick 专项」：CH32 的 `SysTick` 结构体只有 `CTLR` / `SR` / `CNT` / `CMP` 四个成员（`core_riscv.h`，`0xE000F000`）、**没有任何位定义宏**，位号须查 `CH32FV2x_V3xRM`，**不要照抄 ST 的宏值**。⚠ 三种情况都**不要**保留 `SysTick_Config` —— CH32 库内不存在这个函数，见第六节第 3 轮 |
| `INTSYSCR_INEST*` | 仅 CH32 | 可选新能力，仅在需要显式控制嵌套时使用 |

### 3.2 `HSE_VALUE` —— 必须按实际硬件确认

| | STM32 | CH32 |
|---|---|---|
| 默认值 | 25000000（25 MHz） | 32000000（32 MHz） |

这个值决定 `SystemCoreClock`、`Delay_*`、串口/CAN 波特率的换算基准。
**两侧默认值都不是「正确答案」，唯一正确的值是用户板上的实际晶振频率。**

处理：找到 CH32 工程中 `HSE_VALUE` 的定义处（在 `ch32v20x.h` 或工程预定义宏里），
改为用户板实测晶振频率。若用户板是 8 MHz 晶振，就写 8000000。
无法确认板载晶振时，**必须向用户询问，不可沿用默认值**。

同时核对 `system_ch32v20x.c` 顶部的 `SYSCLK_FREQ_*` 选择项：CH32V20x 支持到 144 MHz，
EVT 例程默认选 `SYSCLK_FREQ_96MHz_HSE`（`GPIO/GPIO_Toggle/User/system_ch32v20x.c:25`）。
若用户工程原先依赖 72 MHz，此处要一并确认。
⚠ **由 `HSE_VALUE` 推出的系统主频同样必须与源工程一致**，且**口径是 HCLK（`SystemCoreClock`）而非 SYSCLK**
（`SystemCoreClockUpdate()` 末尾会按 `AHBPrescTable` 折算 AHB 分频）。完整做法见 **3.5**。

### 3.3 `RCC_USBCLKSource_PLLCLK_Div1`

| | STM32 | CH32 |
|---|---|---|
| `_1Div5` | `0x00` | 不存在 |
| `Div1` | `0x01` | `0x00` |
| `Div2` | 不存在（见下表） | `0x01` |
| `Div3` | 不存在 | `0x02` |

用宏名迁移是等价的（都表示 1 分频）。**风险在于裸值**：
用户代码若写 `RCC_USBCLKConfig(0x01)`，在 STM32 上是 1 分频，在 CH32 上是 2 分频——静默出错。

处理：把所有 `RCC_USBCLKConfig` 的实参替换为宏名；若原本就是裸值，按「原意是几分频」重新选宏。

### 3.4 用户代码直接使用数值/地址（丁类）

**这一类编译器不会报错，必须逐条人工核对。** 完整对照表、反解公式与转换方案见
`references/07_pointer-and-bitband.md`，此处只列需要主动扫描的写法：

| 写法 | 实际情况 | 处理 |
|---|---|---|
| `*(volatile uint32_t *)0x40010C00 = ...` | **两侧外设基址完全相同**，可沿用 | 确认偏移后决定；建议改回 `GPIOB->...` |
| `*(volatile uint32_t *)0x4001080C` | 偏移也相同（`OUTDR`），可直接沿用 | 同上 |
| `GPIOA->CRL \|= 0x...` | 成员名与位掩码同时变 | 查 `01_regmap.md` / `02_structmap.md` |
| `NVIC->ISER[0] = ...` | CH32 中断控制器是 PFIC，成员名全不同 | **编译报错**；改用 `NVIC_EnableIRQ()` 等接口 |
| `NVIC->IP[x] = y` | CH32 是 `NVIC->IPRIOR[x] = y`，优先级含义也不同 | 改用 `NVIC_SetPriority()`，语义见 3.1 |
| 位带别名地址 `0x42xxxxxx` / `0x43xxxxxx` | **CH32 无位带硬件**，该地址段无定义 | 反解后改写，见 `07_pointer-and-bitband.md` 2.3 / 2.4 |
| `PERIPH_BB_BASE` / `SRAM_BB_BASE` | CH32 侧完全不存在 | **编译报错** |
| `_BB` 结尾的自定义位带宏 | 依赖 `PERIPH_BB_BASE`，必然报错 | 按 `07_pointer-and-bitband.md` 2.4 整组改写 |
| `BITBAND` / `BIT_ADDR` / `MEM_ADDR` 通用位带宏 | 同上 | 同上 |
| `GPIOA->BSRR = (1 << (n + 16))` | CH32 的 `BSHR` 只有置位语义，无高位清零 | 改为 `GPIOA->BCR = (1 << n)` |
| `0xE0042000`（STM32 DBGMCU 地址） | CH32 的调试控制是 CSR(0x7C0)，该内存地址无效 | 改用 `DBGMCU_Config()`；读 ID 用 `DBGMCU_GetCHIPID()`（在 `0x1FFFF704`） |
| 中断向量号裸数字 | 两侧编号体系不同 | 见 `references/06_interrupt-map.md` |
| `#define XXX 0x01` 之类照抄 STM32 手册的位掩码 | 见乙 / 丙类判定 | 查 `03_semantic-gaps.md` |

**扫描关键字**：`0x4000` / `0x4001` / `0x4002`（外设地址）、`0x42` / `0x43`（外设位带）、
`0x22` / `0x23`（SRAM 位带）、`*(volatile`、`*(__IO`、`BSRR`、`_BB`、`BITBAND`、`NVIC->`。

**改完仍要真机验证**：这一类没有编译期保护，唯一可靠的验收方式是上硬件跑一遍对应功能。

### 3.5 系统主频与时钟档位 —— 必须与源工程一致（按 HCLK 对齐）

**规则：迁移后工程的主频必须与原工程一致。** 口径是 **HCLK（`SystemCoreClock`）**，不是 `SYSCLK` ——
CH32 的 `SystemCoreClockUpdate()`（`system_ch32v20x.c:130-205`）末尾
`SystemCoreClock >>= AHBPrescTable[HPRE]`，`RCC_GetClocksFreq()`（`ch32v20x_rcc.c:552-636`）
同样是 `HCLK = SYSCLK >> presc`。**判定「一致 / 不一致」前先确认比的是 HCLK 还是 SYSCLK，
不要拿 SYSCLK 的 144 与 HCLK 的 72 去误判。**

**推荐做法（源工程选 72 MHz）**：CH32 侧选 `SYSCLK_FREQ_144MHz_HSE` 档，`main()` 起始加：
```c
RCC->CFGR0 |= (uint32_t)RCC_HPRE_DIV2;   /* PLL = 144M，AHB 二分频 */
SystemCoreClockUpdate();                 /* ⚠ SystemInit() 不会替你调 */
```
→ **HCLK 72 / PCLK2 72 / PCLK1 36 MHz**，与原 ST 工程逐项相同、**零参数重算**；
USB 得 `144 / 3 = 48 MHz`。官方先例：D8W 的 120 MHz 档
`EVT/EXAM/**/system_ch32v20x.c:628-631`（PLL 240M + `RCC_HPRE_DIV2` → HCLK 120M）。

- ⚠ **`SystemInit()` 不调 `SystemCoreClockUpdate()`**（`system_ch32v20x.c:111-120` 只调 `SetSysClock()`），
  `SystemCoreClock` 在 `main` 之前仍是**编译期宏值** → **`Delay_Init()` / 波特率计算之前必须显式调一次**。
- ⚠ 寄存器名是 `RCC->CFGR0`（CH32）而非 STM32 的 `RCC->CFGR`。
- ⚠ **EVT 默认档是 `SYSCLK_FREQ_96MHz_HSE`**（`system_ch32v20x.c:25`），不是 72 MHz，**不要沿用默认**。
- **CH32 无对应档位时**（例如源工程 24 MHz）：在 `system_ch32v20x.c` 里照 WCH 结构加档位宏 + 分支（推荐），
  或 `main` 里 `RCC_DeInit(); SetSysClockToXX_HSE(); SystemCoreClockUpdate();`
  （`RCC_DeInit()` 在 `ch32v20x_rcc.c:82`）。
  ⚠ 抄现成档位改系数时**注释主频要一起改** —— 24 MHz = `HSE(8M) × 3`（`RCC_PLLMULL3`），
  从 48M 档抄来若留「`PLLCLK = HSE * 3 = 48 MHz`」的注释即错。

🔴 **带 USB 时的约束**：`RCC_USBCLKConfig` 无 Div1.5，官方 `Set_USBConfig()`
（`USBLIB/CONFIG/hw_config.c:57`）只覆盖 144→Div3 / 96→Div2 / 48→Div1（判据 `SYSCLK_Frequency`）
→ **带 USB 时 SYSCLK 只能 48 / 96 / 144 MHz**。为对齐 72 MHz 而改用 `SYSCLK_FREQ_72MHz_HSE`
会使 USB 分频三分支全不匹配 → **USB 静默失效**；正解仍是「144 MHz 档 + HPRE÷2」。
详见 `SKILL.md`「主频与时钟配置专项」与 `references/10_usb-migration.md`。

## 四、外设能力缺失的处理

STM32F103 有而 CH32V20x 没有的外设，**不用改名，功能本身不存在**。

| 缺失项 | 处理 |
|---|---|
| `DAC` / `CEC` / `FSMC` / `SDIO` | 整个模块不可移植。统计调用点后与用户确认：去掉功能，或改用外部器件 |
| `DMA2` | 改用 `DMA1`（通道需重新分配） |
| `ADC3` | 改用 `ADC1` / `ADC2`（CH32V20x 有 ADC2） |
| `SPI3` | 改用 `SPI1` / `SPI2` |
| `TIM6` / `TIM7` / `TIM8` / `TIM9` ~ `TIM17` | CH32V20x 只有 `TIM1`~`TIM5`，其余全部不存在，需改用 `TIM1`~`TIM5` |
| `CAN2` | 只用 `CAN1` |
| `UART5` | CH32V20x 有 `UART4` 但无 `UART5` |
| `ETH`（STM32F107） | CH32V20x_D8/D8W 另有 `ETH_IRQn` 与 `ETH10M` 外设，属**不同实现**，不可直接套用 |

注意：`DAC` 相关的 `GPIO_Remap_TIM67_DAC_DMA`、`AFIO_MAPR2_*` 等宏在 CH32 侧同样不存在，
它们会随功能一起被删除。

与 `CH32V20x_D8` / `D8W` 绑定、D6 型号没有的能力：
`TIM5`（32 位定时器，专用 `TIM5_TimeBaseInitTypeDef` / `TIM5_OCInitTypeDef`）、
`ETH`、`OSC32K`、`USBFS` 主机模式。**若目标型号是 D6，这些一律不可用。**

## 五、逐外设替换要点

完整改名表见 `references/01_regmap.md` 与 `references/02_structmap.md`；**函数体层面的差异**见 `references/08_func-behavior.md`。本表只列各外设的**特别之处**。

| 外设 | 特别之处 |
|---|---|
| **gpio** | 寄存器成员全改（`CRL`→`CFGLR`、`BSRR`→`BSHR`、`BRR`→`BCR`…）。⚠ **GPIOC 的引脚重编号不是「调用方无感」**，有三个真实陷阱：① 它依赖的文件级全局 `MCU_Version` 全文件**只在 `GPIO_Init()` 内被赋值一次**，另 9 个函数（`GPIO_SetBits`/`GPIO_Write`/各 `Read*Data*`/`GPIO_PinLockConfig`）**只读不写** → 在任何 `GPIO_Init()` **之前**调用不会重编号；② 重编号**只在库函数路径内**发生，裸地址 / 位带直访 GPIOC 不参与，与库函数路径结果不一致；③ `MCU_Version` 未在任何头文件暴露（无 `extern`），用户代码查不到也改不了。触发条件：`CH32V20x_D6` 且 `(*(uint32_t*)0x40022030 & 0x0F000000) == 0`（旧版芯片）。见 `08_func-behavior.md` 第三节第 1 条 |
| **rcc** | 差异规模最大。位定义改名 180 项 + 功能宏 96 项。CH32 新增 `RCC_USBFS`/`RCC_USBHS` 命名，`OTG_FS` 已提供别名。⚠ 时钟常量与 `HSE_VALUE` 一并核对 |
| **tim** | 共存 **91** 个函数，其中 **81** 个非完全一致（✅10 / 🟡69 / ❌12），但**函数签名零冲突**，调用点无需改。12 条 ❌ 中 10 条是 `TIM6/7/8/15/16/17` 实例集合比较、2 条是 `TIM_CCxCmd` / `TIM_CCxNCmd` 的等价 if/else 改写。改名集中在 `CR1`→`CTLR1`、`SR`→`INTFR`、`CCMR1/2`→`CHCTLR1/2`、`DIER`→`DMAINTENR`。若用 `TIM5`，仅 D8/D8W 可用且须换专用结构体 |
| **usart** | `CR1/2/3`→`CTLR1/2/3`、`SR`→`STATR`、`DR`→`DATAR`。CH32 缺 `USART_OneBitMethodCmd`、`USART_OverSampling8Cmd`（1-bit 采样 / 8 倍过采样）。ℹ `stm32f10x_usart.c` 里的文件内私有宏与 CH32 侧名称有差异但**取值相同** —— 属乙类，**不要因为「名字对不上」就去改用户代码**，它与用户代码无关 |
| **spi** | `CR1/2`→`CTLR1/2`、`SR`→`STATR`、`DR`→`DATAR`。🔴 **`SPI_StructInit` 不初始化 `SPI_NSS`** —— STM32 写 9 个成员、CH32 只写 8 个，该成员会**残留未初始化的栈值**。`SPI_StructInit()` 之后须手工补 `s.SPI_NSS = SPI_NSS_Hard;`。⚠ SPI 最高时钟 STM32 为 36 MHz、**CH32 为 72 MHz**；用高速时钟需配置 `SPI_HSCR` 位 0（CH32 侧多出 `HSCR` 寄存器，见 `02_structmap.md`） |
| **i2c** | 位定义 68 项全部改名，函数实现 29 个有差异，**时序相关，需重点核对**。⚠ `I2C_Init` 在 CH32 侧多一句 `if (freqrange >= 60) freqrange = 60;` —— 源工程在 STM32 上 PCLK1 最高 36 MHz、永不触发，但**迁移后 CH32 的 APB1 可达 144 MHz，若用户把 PCLK1 配到 ≥60 MHz 该分支就会生效**（钳位上升时间寄存器计算），须核对实际需求 |
| **dma** | `CCR`→`CFG`、`CNDTR`→`CNTR`、`CPAR`→`PADDR`、`CMAR`→`MADDR`（按结构体偏移对齐：`CPAR`↔`PADDR`、`CMAR`↔`MADDR`）；`DMA_Channel1..7` 带数字后缀的位定义宏整体改名为 `DMA_CFG1_*` 等。⚠ CH32V20x 只有**一个 DMA1、8 个通道**：🔴 `DMA_GetFlagStatus` / `DMA_ClearFlag` / `DMA_GetITStatus` / `DMA_ClearITPendingBit` 在 CH32 侧**固定只读 `DMA1`**，传 `DMA2_*` 参数不报错但读到错的寄存器。🔴 **通道使能后 `PADDR` / `MADDR` 不可写** —— STM32 的 `CPAR` / `CMAR` 在运行中仍可写（官方手册不建议），CH32 上这类「运行中改地址」的写法会失效 |
| **exti** | `IMR`→`INTENR`、`EMR`→`EVENR`、`RTSR`→`RTENR`、`FTSR`→`FTENR`、`SWIER`→`SWIEVR`、`PR`→`INTFR`。位定义 120 项全部改名。🔴 **中断服务函数必须带属性**：硬件压栈用 `__attribute__((interrupt("WCH-Interrupt-fast")))`，**软件压栈用 `__attribute__((interrupt()))`**（无参数）—— 两者不可混用，见第二节第 6 项 |
| **flash** | 宏差异最多的模块。CH32 新增 `FLASH_ProgramPage_Fast` / `FLASH_ROM_WRITE` 等 —— 是另一套接口（256 字节页编程 / 256B·32K·64K 擦除，且 `FLASH_Lock_Fast` 与 `FLASH_Lock` 是**两把不同的锁**）。🔴 **页擦除一律改用 Fast —— 这是迁移的必需修复，不是「更快」的优化**：两侧 `FLASH_ErasePage` 都**不对传入地址做对齐**（STM32 擦「该地址所属的 1 KB 页」，CH32 擦「该地址所属的 4 KB sector」），沿用 STM32 上按 1 KB 页推算的地址必然擦错范围 —— 数据跨 sector 写进未擦区**静默失败**，或擦掉同 sector 前半段的**用户代码**（`0x0800FC00` 这类「1 KB 页首」在 CH32 上只是 4 KB sector 的中段）。统一改法：`base = addr & ~0x3FF` → `FLASH_Unlock_Fast()` → `for(i<4) FLASH_ErasePage_Fast(base + i*256)` → `FLASH_Lock_Fast()`（256 B × 4 = 1 KB，粒度与 STM32 精确等价、**地址一个字都不用动**）。⚠ **对齐方向必须向下** —— WCH 官方的 `CFG_ERASE(addr, len)` 是**区间语义**，直接照搬它的循环会**向右越界到相邻页**。⚠ **编程侧不动**：`FLASH_ProgramHalfWord` / `FLASH_ProgramWord` 仍走 `FLASH_Unlock()` / `FLASH_Lock()`，两套锁**分段不交叉**（官方 `IAP_EEPROM_WRITE` 即此写法）；**不要**用 `FLASH_ProgramPage_Fast` 替换半字 / 字写（它是 256 B 整页一次性提交、无半字接口）。STM32 的 Bank2 / Prefetch / Latency 相关函数在 CH32 不存在。🔴 `FLASH_GetStatus` / `FLASH_GetBank1Status` **删掉了 PGERR 分支**，`FLASH_ERROR_PG` 永不返回 —— 失败判断改为「非 `FLASH_COMPLETE` 即失败」；选项字节相关函数改用 `0x1FFFF800` 基址直访，写保护粒度按 4 KB sector。⚠ `FLASH_TypeDef` 里的 `ACTLR` 在 CH32 侧**无位定义、实际无功能**，`FLASH_Latency_*` / `FLASH_PrefetchBuffer_*` 一组随之不存在，须整句删（**不要只改宏名**）🔴 **主频 >120 MHz 时**，操作非零等待区 Flash / 用户字 / 厂商配置字 / Boot 区须**先把 HCLK 二分频**、操作完再恢复，保证 FLASH 操作频率 ≤100 MHz |
| **adc** | 位定义改名 261 项。`ADC_InitTypeDef` 多出 `ADC_OutputBuffer`、`ADC_Pga` 两个成员（运放/输出缓冲），**初始化结构体多出成员不影响旧代码**（未赋值为 0）。CH32 新增 `ADC_BufferCmd`、`Get_CalibrationValue`、`TempSensor_Volt_To_Temper`。🔴 **CH32 的 ADC 需要软件校准**（读校准值再配置），与 STM32 的出厂校准流程不同 —— 用户代码里的校准段**不能照搬**，须按 EVT 的 `EXAM/ADC` 例程重做。⚠ **内部通道与外部通道共用一个转换单元**，同时使用时须**先关掉内部通道**，要用时再开。🔴 **拿到校准值只是一半**：校准流程之后，**每次转换结果都要加上 `Calibrattion_Val` 并钳位到 `0–4095`** —— 原工程里直接用 `ADC_GetConversionValue()` 返回值的地方必须一并改，否则整段读数偏低。参考 EVT `EXAM/ADC` 的 `Get_ConversionVal()` |
| **can** | 位定义改名 218 项，另有大量返回值别名（`CANTXOK`→`CAN_TxStatus_Ok` 等，见 `03_semantic-gaps.md` 第三节），**旧名可编译**。🔴 **旧版芯片的过滤器表会整体搬移 256 字节**：`CH32V20x_D6` 且 `(*(uint32_t*)0x40022030 & 0x0F000000) == 0` 时，`CAN_FilterInit()` 执行 `0x40006000+512 ← +768` 的 64 次搬移（库已处理，用户无需干预）。**该判断表达式与 gpio 的 `MCU_Version` 是同一个**——同一颗旧版芯片会同时触发 gpio 引脚重编号与 CAN 过滤器搬移 |
| **pwr** | `PWR_PVDLevel_2V2..2V9` 已有兼容别名指向 `PWR_PVDLevel_MODE0..7`，**原名可编译、档位值一致**；但档位对应的实际电压阈值需查 CH32 数据手册确认。🔴 **待机模式语义不同**：CH32 的待机**相当于 STM32 的停止模式**（保持 IO 状态），区别是某些唤醒条件退出后会被**复位**（执行电源复位）；STM32 待机则把 IO 全部置高阻。PA0（wakeup）中断/事件模式均可唤醒（与 STM32 一致），**其他 IO 唤醒须配成事件模式**（CH32 新增能力） |
| **rtc** | CH32 侧功能宏比 STM32 多 14 个（新增能力） |
| **bkp** | `DR*`→`DATAR*`，位定义 53 项改名 |
| **crc / iwdg / wwdg** | 差异规模最小，改名即可 |
| **dbgmcu** | 位定义整体重排（见 `03_semantic-gaps.md`），用宏名即正确；STM32 的 `TIM6`~`TIM17`、`CAN2` 相关停机位在 CH32 不存在。⚠ 实现方式不同：CH32 的调试控制是 **CSR(0x7C0)** 而非内存映射寄存器，且 `DBGMCU_Config(x, ENABLE)` 是整体覆写——单次 `A\|B\|C` 调用两侧等价，**连续分开调用会互相清除，需合并**。🔴 `DBGMCU_GetREVID` 与 `DBGMCU_GetDEVID` 在 CH32 侧**返回值互换**（要版本号反而应调 `GetDEVID`），IDCODE 地址改为 `0x1FFFF704`。CH32 新增 `DBGMCU_GetCHIPID` |
| **misc** | 优先级分组必须重做（见 3.1）；⚠ `NVIC_PriorityGroupConfig` 在 CH32 侧**不写硬件、只存全局变量**，必须**先调它、再调 `NVIC_Init`**，顺序颠倒分组不生效。🔴 **SysTick 结构完全不同**：STM32 是 Cortex-M3 的 24 位**向下递减**计数器（递减到 0 触发中断）；CH32 是 RISC-V 的 **64 位加减计数器 + 64 位比较寄存器**（计数与比较值相同时触发中断），由 **6 个寄存器**控制（见 `CH32FV2x_V3xRM` 手册）。基址与寄存器名都不同，**任何直写 SysTick 寄存器的代码都必须重做**。🔴 **`SysTick_Config` 在 CH32 库中不存在**，须自制（步骤见第六节第 3 轮）；补实现时别忘了在 `ch32v20x_it.c` 里声明 `SysTick_Handler` 并加中断属性（`SysTick_Handler` 本身在 CH 侧**是有的**，带 `WCH-Interrupt-fast` 属性，缺的只是库函数 `SysTick_Config`）。🔴 **延时类函数**：ST SPL 库内**没有任何 Delay 函数**，`Delay` 全部定义在用户代码里 —— 比对表里不会出现、编译器也不会提示。**按 ST 原形态分流**：① **空循环式**（参数是**循环次数**、无时间语义）→ 改用 `__NOP()` 忙等（**不占 SysTick**；`i = SystemCoreClock/1000/8` 等系数依赖优化等级、须上机标定）；② **SysTick / 滴答定时器式**（单位 **10 ms**，`SysTick_Config(HCLK/100)`）→ 改用 CH32 的 `Delay_Us` / `Delay_Ms`（`EVT/EXAM/SRC/Debug/debug.c`，须连同 `debug.h` 一并加入工程，并在 `SystemCoreClockUpdate()` 之后调 `Delay_Init()`），并整段删除原 SysTick 代码。详见 `SKILL.md` 的「延时与 SysTick 专项」 |

## 六、按编译结果迭代修复

替换完成后不要试图一次改对，按下面的顺序循环：

### 第 1 轮：预处理与语法错误

| 报错 | 含义 | 动作 |
|---|---|---|
| `fatal error: stm32f10x_xxx.h: No such file` | 头文件未替换 | 按第二节第 1 条改名 |
| 找不到 `core_cm3.h` | 内核头文件残留 | 删除该 include |
| `XXX` undeclared（宏名） | 甲类 | 查 `references/01_regmap.md`（位定义）与 `03_semantic-gaps.md` 第七节（功能宏） |
| `IS_XXX` undeclared | 参数校验宏 | 查看是否用户代码显式调用，删除该判断 |
| `#error` 来自 `ch32v20x.h` | 型号宏未定义 | 按第二节第 4 条设置 `CH32V20x_D6` 等 |

### 第 2 轮：类型与成员错误

| 报错 | 含义 | 动作 |
|---|---|---|
| `has no member named 'CRL'` 之类 | 寄存器结构体成员改名 | 查 `references/02_structmap.md` |
| `'XXX_TypeDef' has no member` | 同上 | 同上 |
| `has no member named 'BSRR'` / `'BRR'` | CH32 用 `BSHR` 置位、`BCR` 清零 | ⚠️ 只改名字不够：`BSRR = (1 << (n+16))` 必须改成 `BCR = (1 << n)`，见 `07_pointer-and-bitband.md` 2.5 |
| `has no member named 'ISER'` / `'IP'` | CH32 中断控制器是 PFIC | 改用 `NVIC_EnableIRQ()` / `NVIC_SetPriority()` |
| `conflicting types for 'XXX_IRQHandler'` | 中断函数签名不符 | 补 `__attribute__((interrupt("WCH-Interrupt-fast")))` |
| `unknown type name 'NVIC_InitTypeDef'` | 未包含 `ch32v20x_misc.h` | 在配置头里使能对应外设 |

### 第 3 轮：链接错误

| 报错 | 含义 | 动作 |
|---|---|---|
| `undefined reference to 'RCC_PLL2Cmd'` 等 | 目标库无此函数 | 查 `references/03_semantic-gaps.md` 第五节，属缺失能力，与用户确认 |
| `undefined reference to 'XXX_IRQHandler'` | 中断函数名与向量表不符 | 查 `references/06_interrupt-map.md` 第二节 |
| `undefined reference to 'SysTick_Config'` | 🔴 **CH32 库内没有这个函数**：`core_riscv.h` 与 `ch32v20x_misc.c/h` 均无定义，`ch32v20x.h` 里 `__Vendor_SysTickConfig` 为 `0` | **先判来源**：若该调用来自**延时路径**（源工程用 SysTick / 滴答定时器做延时）→ 按「延时与 SysTick 专项」路线 ②**整段删除**（`SysTick_Config` / `TimingDelay` / `SysTick_Handler`）、改用 `debug.c` 的 `Delay_*`，**不要为此自制**；若用户**另有**基于 SysTick 的独立功能（跑表 / OS 节拍 / 自建时基）才自制 —— **没有现成接口可指**，按 SysTick 的 64 位 `CNT` / `CMP` 自制：清 `SR` → 清 `CNT` → 写 `CMP` → 置 `CTLR` → `NVIC_SetPriority(SysTick_IRQn, …)` → `NVIC_EnableIRQ(SysTick_IRQn)`；并在 `ch32v20x_it.c` 补 `SysTick_Handler` 及其中断属性 |
| `undefined reference to 'assert_failed'` | 校验体系残留 | 清掉 `assert_param` 相关引用 |

### 第 4 轮：能编译但要核对行为

编译通过**不代表移植完成**。按下表逐项确认，无法在编译期发现：

| 核对项 | 依据 |
|---|---|
| 系统主频与 `HSE_VALUE` | 第三节 3.2 |
| **系统主频是否与源工程一致（HCLK 口径）** —— `SYSCLK_FREQ_*` 档位与 AHB 分频合起来是否使 HCLK 对齐（如 144M + `RCC_HPRE_DIV2` → HCLK 72M）、`SystemCoreClockUpdate()` 是否已调用；带 USB 时主频是否落在 48/96/144 MHz | 第三节 3.5 |
| Delay 函数实测周期是否准确 | 依赖 `SystemCoreClockUpdate()` 与主频 |
| 串口/CAN 波特率 | 同上 |
| 中断能否进入、优先级是否符合预期 | 第三节 3.1 |
| 调试时外设是否按预期暂停 | `references/03_semantic-gaps.md` 第一节 |
| **裸地址访问的寄存器是否读到了预期值** | `07_pointer-and-bitband.md` 1.3 / 1.4（无编译期保护） |
| **位带改写后的位操作是否真的生效** | `07_pointer-and-bitband.md` 2.4（无编译期保护） |
| **GPIO 清零方向是否正确**（`BSRR` 高位 → `BCR`） | `07_pointer-and-bitband.md` 2.5 |
| I2C/SPI 时序 | 实现差异最多的模块之一 |
| **函数实现层的行为差异**（GPIO 重编号的顺序依赖、`SPI_StructInit` 漏初始化 `SPI_NSS`、DMA 标志函数只读 DMA1、`FLASH_ERROR_PG` 不返回、`DBGMCU` 两个 Get 函数互换…） | `references/08_func-behavior.md` 第三节（**签名零冲突，编译期无任何提示**） |
| **`NVIC_PriorityGroupConfig` 是否在 `NVIC_Init` 之前调用** | 第三节 3.1 + `08_func-behavior.md` 第三节第 4 条 |
| 低功耗模式 | CH32 无 `NVIC_SystemLPConfig`，需重做 |
| **Flash 页擦除是否已改成 Fast 循环** —— `base = addr & ~0x3FF` → `FLASH_Unlock_Fast()` → `for(i<4) FLASH_ErasePage_Fast(base + i*256)` → `FLASH_Lock_Fast()`；编程侧是否仍走普通半字 / 字写 | `SKILL.md` FLASH 专项 —— `FLASH_ErasePage` 两侧**同名同签名，编译期零提示**。漏改则**静默**擦错范围：数据跨 sector 写进未擦区 → 写入失败；或擦掉同 sector 前半段的**用户代码** → 程序跑飞 |
| **延时是否已按 ST 原形态分流改对** —— ① 空循环型是否已改用 `__NOP()` 忙等（参数由「循环次数」改为 ms/us 数、系数按上下文给初值并**上机实测标定**、**确未引入 SysTick**）；② SysTick / 滴答定时器型是否已改用 `Delay_Us` / `Delay_Ms`（工程已加入 `EVT/EXAM/SRC/Debug/debug.c` + `debug.h`、`Delay_Init()` 在 `SystemCoreClockUpdate()` **之后**调用、`Delay(nTime)` 换算已 **×10**、原 SysTick 相关代码 `TimingDelay` / `TimingDelay_Decrement` / `SysTick_Handler` / `SysTick_Config` 已整段删除） | `SKILL.md`「延时与 SysTick 专项」—— ST SPL 库内**没有任何 Delay 函数**，**比对表与编译器都不覆盖**。**两条路线必须按原形态分流、不可混用**：空循环型改 `__NOP`（不占 SysTick，系数依赖优化等级）；SysTick 型改 `Delay_*`（单位 10 ms，漏乘即缩短十倍） |
| **浮点格式化输出是否已处理** —— 原工程用了 `%f` / `%e` / `%g` 等浮点格式时，是否已通知 MRS 侧开启 `Use wchprintfloat(-lprintfloat)`（该选项**默认关闭**，关闭时浮点项**编译与链接均不报错、运行期不打印**）；无浮点输出的工程是否**保持关闭**（开启会显著增大体积） | `SKILL.md`「printf 与浮点打印专项」—— 工具链配置类，**比对表与编译器都不覆盖** |
| **已用符号功能一致性复核是否已完成** —— 用户代码实际用到的**外设库函数**是否已逐个核对两侧行为语义（有官方基线处 🔴 不一致的是否已补实现并登记、🟠 无基线处是否已出「待人工确认清单」）；库文件的增删是否已按官方 SPL 白名单甄别（用户新增的库文件**不得**被 `stm32f10x_*.c` 通配移出）—— 本项要读 `.mrs/originalKeilFiles/` 里的 ST 侧源码，**必须在删除该目录之前做完** | `SKILL.md`「已用符号功能一致性复核专项」—— **源工程 ST 库可能被本地改过，而版本宏判不出**；参照物只能是 `08_func-behavior.md` 记录的 ST 侧基线（**不得**拿 CH32 库代码当参照，否则假阳性会让人重写几百个本来正确的函数）。**等量替换型的函数体改动只有内容对照能发现** |
| **「注释改了、代码没改」的地方是否已逐处复核** | 这类位置通常是迁移者**已经意识到差异、却漏改代码**的地方（本次 Flash 页大小问题即由此发现）。凡见注释里的规格描述被改过（如 `1k`→`4k`）而对应常量 / 地址 / 循环未动，必须回查 |
| **ST 源码副本目录是否已删除** —— `<新工程根>/.mrs/originalKeilFiles/` 是否已按 `SKILL.md` 阶段 4.4 删除（**只在复核专项出结论之后删**；只删这一层目录、写完整路径、不用通配） | `SKILL.md` 阶段 4.4 —— 该目录是工程级转换的**一次性产物**（整份原始 Keil 工程文件，含 ST 外设库源码）。**早删 = 丢掉「用户改过 ST 库」这整类风险的检出能力**；不删 = 给用户留一个与工程无关的冗余目录 |

**最终验收只能上真实硬件。** 编译与静态检查不构成移植完成的证据。
