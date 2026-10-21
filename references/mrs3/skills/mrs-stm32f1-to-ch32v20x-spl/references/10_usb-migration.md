# USB / HID 迁移注意点

> 本文件**手工维护**，不由 `build_skill_data.py` 产出。
>
> 数据来源：`CH32V20xEVT` 源码逐项核实（`ch32v20x.h`、`EXAM/USB/USBD/*/User/USBLIB/`）。
> **本工作区没有 ST 侧 USB 库**（`stm32f10x-stdperiph-lib-master` 只含标准外设库，
> 不含 `STM32_USB-FS-Device_Driver`），因此本文件里标 🟠 的「ST 侧」结论均由公开版本推断，
> **须以用户源工程里的那个版本为准**（该版本随工程级转换的副本一起可读，见下）。
> ⚠ **做实际转换时这些 🟠 项是可以落到实际代码上的**：工程级转换会把整份原始 Keil 工程文件
> （含 ST 侧 USB 库，若有）放进**新工程根目录下的 `.mrs/originalKeilFiles/`** ——
> 按 §八 第 1 步到该目录读 ST 侧源码逐行对照，即可把 🟠 升级为 ✅ 或改判。
> 该目录**只读**，且**交付前随目录一起删除**（`SKILL.md` 阶段 4.4），因此**这一步必须在删除之前做完**。
> 外部参考文档《从 STM32F103C8T6 移植到 CH32V203C8T6》§4.6 可作线索（其关键代码位于图片中，无法读取）。
>
> ⚠ **本文件与主技能的关系**：主技能的 01–08 参考文件覆盖 19 个**标准外设**，**不包含 USB**。
> USB 是另一套独立代码（对应 ST 的 `STM32_USB-FS-Device_Driver`）。处理方式是**分层替换**：
> **驱动层与配置层照搬 CH32 官方版，业务层保留 ST 原样，靠编译错误收敛**（方案 B，见 §1.3）。
> 既不是「整套换库」，也不是「移出编译列表」。
> ⚠ **编译通过后必须再过一遍 §1.5 的自查清单** —— USB 这块有 5 处编译器抓不到的静默失败。
> **本文件覆盖面有限，参考文件里查不到的部分按 §八 补齐。**

## 一、总体策略（方案 B）：驱动层照搬 CH32 官方版，业务层保留 ST

### 1.1 先厘清：两侧寄存器映射**是兼容的**

| 项 | CH32 值 | 与 STM32F103 |
|---|---|---|
| 寄存器基址 `RegBase` | `0x40005C00` | 相同 |
| 分组缓冲 `PMAAddr` | `0x40006000` | 相同 |
| 端点 0 寄存器 `EP0REG` | `RegBase + 0x00` | 相同 |
| `CNTLR` / `ISTR` / `FNR` / `DADDR` / `BTABLE` | `+0x40` / `+0x44` / `+0x48` / `+0x4C` / `+0x50` | 偏移相同；**寄存器指针宏 ST 作 `CNTR`，CH32 作 `CNTLR`** |

- `CNTR_CTRM` 系列**位宏**、`SetCNTR` / `GetCNTR` 等**函数名**两侧完全一致；
  **改名只发生在「寄存器指针宏」这一处** —— 与 CH32 其它外设 `CR`→`CTLR` 的命名习惯一致。
- `usb_mem.c` 的两个 PMA 拷贝函数写法也与 ST 公开版本一致（`UserToPMABufferCopy` 里
  `pdwVal++` 连加两次、`PMAToUserBufferCopy` 里用 `uint32_t*` 读 PMA，
  这两个写法很有特征，可作为「同一份代码」的判据）✅ CH32 侧核实 / 🟠 ST 侧待对照。
- ⚠ **不要改用 `USBFS_BASE`**：CH32 头文件里另有一套**布局完全不同**的 USB 视图
  ——`USBFSD_TypeDef`（`USBFS_BASE = 0x50000000`，成员是 `UEP0_DMA` / `UEP0_TX_LEN` /
  `UEP0_TX_CTRL` / `BASE_CTRL` / `OTG_CR` …），那是 CH32 自己的另一套 USB 寄存器，
  **USB 库不使用它**。库代码一律走 `RegBase` 绝对地址，不要「为了用库定义」把寄存器访问改过去。

**结论：寄存器层与驱动层就是同一套东西** —— 这就是「不必整套换库、改在文件里即可」的基础。

### 1.2 但 CH32 版带了 ST 原版没有的补丁 —— 这才是必须处理的部分

**(a) 3 个端点状态宏加了「写后读回校验」的 `while`** ✅ CH32 侧核实（CH32 `usb_regs.h`）

| 行 | 宏 | 校验字段 |
|---:|---|---|
| 250 | `_SetEPTxStatus` | `EPTX_STAT` |
| 274 | `_SetEPRxStatus` | `EPRX_STAT` |
| 307 / 311 | `_SetEPRxTxStatus` | `EPTX_STAT` / `EPRX_STAT` |

```c
    _SetENDPOINT(bEpNum, (_wRegVal | EP_CTR_RX | EP_CTR_TX));
    while( ( _GetENDPOINT(bEpNum) & EPTX_STAT ) != wState )
    {
        _SetENDPOINT(bEpNum, (_wRegVal | EP_CTR_RX | EP_CTR_TX));
    };
```

针对的是 `USB_EPnR` 里 `rc_w0`（读清零）位与「读-改-写」的竞态：ST 版写一次即结束，
CH32 版写后读回、不等就重写。`usb_regs.c` / `usb_core.c` 里没有 `while` —— 补丁只在这 3 个宏上。
**缺这三处时，端点状态可能只写进去一次而未被硬件接受，编译器一句都不会报。**

> 与外部文档 §4.6.3(2) 吻合：该文档称「用新的 `usb_regs.h` 替代原来的，主要对 **3 个函数**进行修改」
> ——数量、位置、改动性质三方面都对得上（🟠 函数名仍属推定，但**不影响行动**：
> 见 1.3 第 2 条，对齐判据是 CH32 版，不需要知道 ST 版长什么样）。

**(b) `_SetEPRxCount` 多了 EP0 分支，并引入 `Ep0RxBlks`** ✅ CH32 侧核实 / 🟠 ST 侧待对照

```c
#define _SetEPRxCount(bEpNum,wCount) {\
    uint32_t *pdwReg = _pEPRxCount(bEpNum); \
    _SetEPCountRxReg(pdwReg, wCount);\
    if (bEpNum == ENDP0) \
      _GetNumBlock(Device_Property.MaxPacketSize,Ep0RxBlks);\
  }
```

`Ep0RxBlks`（`usb_istr.c:17` 定义、`usb_regs.h:37` 声明）在 `USB_Istr()` 入口被**写回 EP0 的 RXCOUNT**：

```c
if ((*_pEPRxCount(0) & 0xFC00 ) != Ep0RxBlks)
{
  *_pEPRxCount(0) |= (Ep0RxBlks & 0xFC00);
}
```

作用：把 EP0 RXCOUNT 高 6 位的**块编码**在被打乱后重新对齐
（`_GetNumBlock` 会按 `Device_Property.MaxPacketSize` 重算块数）。
相关宏还有 `_GetNumBlock` / `_SetEPRxDblBuf0Count`，都是 ST 侧没有的 ✅ CH32 侧。

**(c) 两处「复位重同步」序列** ✅ CH32 侧核实 / 🟠 ST 侧待对照

`usb_istr.c` 的 `USB_Istr()`（ESOF 分支）与 `usb_pwr.c` 的 `Suspend()` 里各有一段：
**先读回 8 个端点寄存器 → 置 `CNTR_FRES` → 清 `CNTR_FRES` → 等 `ISTR_RESET` → 清 RESET →
把 8 个端点寄存器写回**。

```c
for (i=0;i<8;i++) EP[i] = _GetENDPOINT(i);
wCNTR |= CNTR_FRES;  _SetCNTR(wCNTR);
wCNTR &= ~CNTR_FRES; _SetCNTR(wCNTR);
while((_GetISTR() & ISTR_RESET) == 0);
_SetISTR((uint16_t)CLR_RESET);
for (i=0;i<8;i++) _SetENDPOINT(i, EP[i]);
```

`Suspend()` 里还多了 `wCNTR |= CNTR_RESETM;` 与进入低功耗前的这一整段 ——
**ST 版 `Suspend()` 是直接 `FSUSP` → `LPMODE`，没有这些**。

**(d) 应用层 `USBD_init()` 多了 5 句**（对应外部文档 §4.6.3(1)「端点状态寄存器初始化需全清」）
✅ CH32 侧核实（`CONFIG/usb_prop.c:201-215`） / 🟠 ST 侧待对照

```c
void USBD_init(void)
{
  uint8_t i;
  pInformation->Current_Configuration = 0;
  PowerOn();
  for (i=0;i<8;i++) _SetENDPOINT(i,_GetENDPOINT(i) & 0x7F7F & EPREG_MASK);//all clear
  _SetISTR((uint16_t)0x00FF);//all clear
  USB_SIL_Init();
  bDeviceState = UNCONNECTED;
  USB_Port_Set(DISABLE, DISABLE);
  Delay_Ms(20);
  USB_Port_Set(ENABLE, ENABLE);
}
```

ST 版例程的 `XXX_Init()` 只有 `Current_Configuration = 0` / `PowerOn()` / `USB_SIL_Init()` /
`bDeviceState = UNCONNECTED` 四句。**迁移动作：把这 5 句补进用户工程对应函数的 `USB_SIL_Init()`
之后** —— 否则端点寄存器带上电残留（`0x7F7F` 掩码清的是 CTR/DTOG/STAT 各位），
USB 口也不做「先断开 20 ms 再接入」的重连动作。

**(e) include 链不同** ✅ CH32 侧核实

| 文件 | CH32 侧 | 说明 |
|---|---|---|
| `usb_lib.h` | 首行 `#include "hw_config.h"` | ST 版没有这一行 |
| `usb_type.h` | `#include "debug.h"` + `"usb_conf.h"` | `debug.h` 是 MRS 模板里的调试头 |
| `usb_regs.h` | `#include "ch32v20x.h"` | 提供 `__IO` 与设备定义 |

### 1.3 做法（方案 B）：分层替换 + 靠编译错误收敛

**一句话**：驱动层与配置层**照搬 CH32 官方版**，业务层**保留 ST 原样**，编译报错就按代码逻辑改业务层的调用。

| 层 | 文件 | 处理 |
|---|---|---|
| **驱动层**<br>照搬 CH32 | `USB-Driver/{inc,src}` 全部 15 个文件：`usb_regs` / `usb_int` / `usb_core` / `usb_mem` / `usb_init` / `usb_sil` 的 `.c/.h`，加 `usb_lib.h` / `usb_def.h` / `usb_type.h` | **整份用 CH32 官方版**，不做逐行改动。§1.2(a)(b)(c) 的补丁、`CNTR`→`CNTLR` 改名、include 链随之一次性到位 |
| **配置层**<br>照搬 CH32 | `usb_conf.h`、`hw_config.c/h`、`usb_istr.c/h`、`usb_pwr.c/h` | **也跟 CH32 官方版** —— 它们在 `CONFIG/` 目录下，但**没有一行是用户的业务逻辑**，且是补丁宿主（§1.2(c)(d)、`Ep0RxBlks`、`Set_USBConfig`、`USB_Port_Set`）。例外见下方「`usb_conf.h` 要改回的值」 |
| **业务层**<br>保留 ST | `usb_desc.c/h`、`usb_prop.c/h`、`usb_endp.c`、例程主文件 | **一行都不动** —— 描述符、报告逻辑、端点回调、上位机可见接口全在这层；编译报错就按逻辑改**这里的调用** |

**为什么配置层不能留给 ST**：`usb_istr.c` / `usb_pwr.c` / `hw_config.c` 里没有一行是用户业务，
却承载了 CH32 的 3 组**行为**补丁 —— 而这些差异**编译错误抓不到**（§1.5 第 2、3、4 条）。

#### `usb_conf.h` 要按用户工程改回的两类值

`usb_conf.h` 跟 CH32 版，但下面两类必须保持用户工程原值 —— 它们属**用户配置**，不是库配置：

| 项 | 为什么 |
|---|---|
| `EP_NUM` | 是「设备用几个端点」。已核实 `EP_NUM` 全工程只出现在 `usb_conf.h:17`（定义）与 `usb_prop.c:34`（`Device_Info = {EP_NUM, 1}`）—— 消费者在**业务层**，必须沿用 ST 工程的值（CH32 例程是 3） |
| `BTABLE_ADDRESS` / `ENDP0_RXADDR` / `ENDP0_TXADDR` / `ENDP1_RXADDR` … | PMA 缓冲地址分配，取决于端点数与最大包长，必须与用户实际端点配置匹配 |

反过来，`IMR_MSK` 与「端点回调宏映射」（`EPx_IN/OUT_Callback → NOP_Process`）**必须与 CH32 版一致** ——
前者是 `usb_istr.c` 的条件编译门（§1.5 第 2 条），后者决定哪些端点走空实现。

#### 四条硬性要求

1. **同名文件只留一份。** 两侧库文件名完全相同（`usb_regs` / `usb_core` / `usb_int` / `usb_mem` /
   `usb_init`）。做法二选一：① 原地替换文件内容（工程文件列表不动，最省事）；② 从工程里移除 ST 的
   `STM32_USB-FS-Device_Driver` 分组、加入 CH32 的 `USB-Driver` 分组。**不要两份共存**（重复定义）。
2. **驱动层不做逐行改动。** 照搬能让 §1.2 的 5 组差异一次到位；逐行改反而容易漏 ——
   这正是方案 B 取代「逐文件对齐」的原因。
3. **业务层不要为「和 CH32 一样」而改名或改结构。** 例程前缀差异（`USBD_` vs `HID_`）见 §6.4。
4. **判据不是「编译通过」。** 编译通过只说明接口对上了；USB 有 5 处静默失败点，
   必须按 §1.5 逐条自查；业务层改完后再按 §1.6 确认上位机侧零改动。

### 1.4 参考基准：用哪个例程

`EXAM/USB/USBD/` 下 7 个例程的 `USB-Driver` 逐个 diff 的结果 ✅ 已核实：

| 例程 | 驱动层 |
|---|---|
| `CompatibilityHID` / `CompositeKM` / `SimulateCDC` / `SimulateCDC-HID` / `CH372` | **完全一致** |
| `MSC_CD-ROM` / `MSC_U-Disk` | `usb_core.c` / `usb_sil.c` 各多一处**例程专用**改动（CTR 回调里插 `UDISK_Up_CSW()` 之类），**不要照搬** |

→ **HID 类工程以 `CompatibilityHID` 为基准最干净**；MSC 类工程对齐时要用 MSC 例程，
但要能分辨哪些是库改动、哪些是例程钩子。

### 1.5 编译通过后必查的 5 条（编译器抓不到）

方案 B 靠编译错误收敛，但下面 5 处**编译不报错**（或只报 warning），却是 USB 挂掉的直接原因。
业务层定稿后逐条过一遍：

| # | 风险 | 检查点 | 不查的后果 |
|---|---|---|---|
| 🔴1 | **`DEVICE_PROP` 成员错位** —— CH32 的 `usb_core.h:117` 在 `GetStringDescriptor` 与 `MaxPacketSize` 之间**多了一个 `void* RxEP_buffer`**（驱动层任何 `.c` 都不使用它，纯占位） | 业务层 `DEVICE_PROP Device_Property = {...}` 的**值个数与顺序**。CH32 例程写 **12 个**（第 11 个填 `0` 占位，`usb_prop.c:38-52`）；ST 版只有 **11 个** | ST 的 11 个值落到 CH32 的 12 成员结构上 → 第 11 个值（`0x40`）被赋给 `RxEP_buffer`，**`MaxPacketSize` = 0**，GCC/Keil 只给一句 `int-conversion` warning。`MaxPacketSize` 用于 `usb_core.c:286/762-772/908`、`usb_prop.c:237`、`usb_regs.h:509` → **EP0 包长全废，枚举挂在 SET_ADDRESS 之后**（PC 端表现为「未知 USB 设备」）。修法：在业务层初始化列表 `GetStringDescriptor` 之后补一个 `0` 占位 |
| 🔴2 | **`IMR_MSK` 是条件编译门** | `usb_istr.c:146` 的 `#if (IMR_MSK & ISTR_ESOF)` 包住整段复位重同步；`IMR_MSK` 定义在 `usb_conf.h`，CH32 版含 `CNTR_ESOFM`（0x0100 = `ISTR_ESOF`，`usb_regs.h:99`） | 若 `IMR_MSK` 位组合与 CH32 不同 → **整段补丁被静默裁掉**，编译无提示 |
| 🟠3 | **`Ep0RxBlks` 只兜住一半** | `usb_regs.h:37` 有 `extern`，`:509` 的宏里 `_GetNumBlock(MaxPacketSize, Ep0RxBlks)` 使用它，定义却在 `usb_istr.c:17`。若业务层还留着 ST 的 `usb_istr.c` → 链接报 `undefined reference` | ⚠ 只补一句变量定义**就能过编译**，但真正起作用的是 `USB_Istr():57-59` 的写回 —— **这条没人提醒你**。正解：`usb_istr.c` 用 CH32 版（见 §1.3 配置层） |
| 🔴4 | **`XXX_Init()` 缺 5 句** | `DEVICE_PROP.Init` 指向的那个函数（ST 名如 `HID_Init`）里是否补了「8 端点全清 + `_SetISTR(0x00FF)` + `USB_Port_Set(DISABLE)` → `Delay_Ms(20)` → `USB_Port_Set(ENABLE)`」（§1.2(d)、§6.1） | 端点寄存器带上电残留；USB 口不做「先断开 20 ms 再接入」的重连 |
| 🔴5 | **中断服务函数属性** | `USB_LP_CAN1_RX0_IRQHandler` 是否带 `__attribute__((interrupt("WCH-Interrupt-fast")))` | 编译过、运行时中断行为错（§五） |

> 这 5 条的共同特征：**都落在业务层与库的接缝上** —— 而方案 B 的「保留业务层」正好把这个接缝
> 留在手上。这也是「编译通过不算做完」的具体含义。

### 1.6 上位机（PC 端）要不要改 —— **不用改**

上位机认的是**描述符**，不是 MCU。而描述符全在业务层文件里，方案 B 原样保留：

| 上位机依赖项 | 存放位置 | 方案 B 下 |
|---|---|---|
| VID / PID | `usb_desc.c` 设备描述符偏移 8–11 | 不变 |
| `bcdDevice`（硬件 ID 里的 `REV_xxxx`）、`bcdUSB`、`bMaxPacketSize0` | 同上 | 不变 |
| 设备类 / 子类 / 协议 | 同上 | 不变 |
| 配置 / 接口 / 端点描述符（端点地址、包长） | `usb_desc.c` 配置描述符 | 不变 |
| HID 报告描述符（Report ID、报告长度） | `usb_desc.c` | 不变 |
| 厂商 / 产品 / 序列号字符串 | `usb_desc.c` | 不变 |

→ 对 Windows 而言移植前后是**同一台设备**（设备实例 ID 相同，此前装的驱动与绑定直接复用）。
按 VID/PID 打开的上位机（hidapi / SetupAPI / WinUSB / libusb）全部照旧，`.inf`、注册表都不用动。

**唯一会让上位机必须改的操作：顺手把 `usb_desc.c/h` 也换成 CH32 例程的。** 已核实 CH32
`CompatibilityHID` 例程的值：VID/PID = `0x1A86` / `0xFE07`、厂商串 `wch.cn`、产品串 `CH32V20x`、
序列号 `0123456789`、`bcdUSB 1.10`、`DEF_USBD_UEP0_SIZE 64`、HID 报告 34 B
（Usage Page `0xFF00`，64 B IN/OUT）。
⚠ `0x1A86` 是**沁恒的厂商 VID，量产不可使用** —— 保留 ST 原有 VID/PID 反而避开了这个合规问题。

另外两种需要同步上位机的情况：① 用户自行调整了端点 / 接口布局或报告格式；
② 原来是 CDC 虚拟串口 —— COM 口号由 Windows 分配，可能变号（按 VID/PID 打开的则不受影响）。

**验收标准**：插上电脑能正常枚举，且描述符逐字段与原值一致（不是「编译通过」）。

**验证方法**（最省事）：移植前先记下设备管理器 → 该设备 → 属性 → 详细信息 →「硬件 ID」里的
`USB\VID_xxxx&PID_xxxx&REV_xxxx`（有 USBView / USBTreeView 的话，连接口 / 端点 / 报告长度一并存），
移植后逐字段比对。

## 二、硬件差异：USBD 引脚内置上拉电阻

| | STM32F103C8T6 | CH32V203C8T6 |
|---|---|---|
| USBD 上拉电阻 | **需外接**（1.5 kΩ 到 3.3 V） | **芯片内置，程序配置开启** |

CH32 的 USBD 引脚内置上拉，通过**扩展控制寄存器**开启：

```c
if(Pin_In_IPU) (EXTEN->EXTEN_CTR) |= EXTEN_USBD_PU_EN;
else           (EXTEN->EXTEN_CTR) &= ~EXTEN_USBD_PU_EN;
```

（`EXTEN_CTR` 是 `EXTEN_TypeDef` 的唯一成员；`EXTEN_BASE = AHBPERIPH_BASE + 0x3800`。）

EVT 的 `USBLIB/CONFIG/hw_config.c` 的 `USB_Port_Set()`（第 150–169 行）已做处理，
**通常无需用户自己写** —— 但若用户代码里保留了「控制外接上拉」的逻辑
（如 GPIO 拉高某引脚），迁移后应删除。

> ⚠ 外部文档把寄存器名写作 `EXTEND_CTR`，**正确名是 `EXTEN_CTR`**。位号「位 1」与源码一致。

## 三、时钟要求：使用 USBD 时主频只能取三档

| | STM32F103C8T6 | CH32V203C8T6 |
|---|---|---|
| 可用主频 | 48 MHz（1 分频）<br>72 MHz（1.5 分频） | **48 MHz（1 分频）**<br>**96 MHz（2 分频）**<br>**144 MHz（3 分频）** |

USB 需要 48 MHz 时钟。STM32 在 72 MHz 主频下走 1.5 分频；CH32V203 **没有 1.5 分频档**，
只能用 48 / 96 / 144 MHz。CH32 例程的做法是**按当前 SYSCLK 反推分频**：

```c
RCC_GetClocksFreq(&RCC_ClocksStatus);
if     (SYSCLK == 144000000) RCC_USBCLKConfig(RCC_USBCLKSource_PLLCLK_Div3);
else if(SYSCLK ==  96000000) RCC_USBCLKConfig(RCC_USBCLKSource_PLLCLK_Div2);
else if(SYSCLK ==  48000000) RCC_USBCLKConfig(RCC_USBCLKSource_PLLCLK_Div1);
else if(SYSCLK == 240000000 && RCC_USB5PRE_JUDGE() == SET)
                             RCC_USBCLKConfig(RCC_USBCLKSource_PLLCLK_Div5);
RCC_APB1PeriphClockCmd(RCC_APB1Periph_USB, ENABLE);
```

迁移动作：

- 确认目标主频属于 {48, 96, 144} MHz，否则调整 `SystemInit()` 的 PLL 配置。
- 用户代码/`system_ch32v20x.c` 若把主频配成上述三档之外，USB 无法工作。
- ⚠ `RCC_USBCLKSource_PLLCLK_Div1` 这个宏的**裸值在两侧含义互换**（见主技能
  `references/03_semantic-gaps.md` 的 USB 时钟源条目）—— 保留宏名即正确，**不要按数值搬**。

### 3.1 时钟配置**函数名不同、作用相同**（`Set_USBClock` ↔ `Set_USBConfig`）

| | STM32F103（USB-FS-Device 库） | CH32V203（USBLIB） |
|---|---|---|
| 函数名 | `Set_USBClock()` | `Set_USBConfig()` |
| 位置 | `hw_config.c` / `hw_config.h` | `hw_config.c` / `hw_config.h` |
| 作用 | **USB 时钟配置**：选 USB 时钟源分频 + 使能 USB 外设时钟 | **完全相同** |

两者做的都是同一件事，两句话：`RCC_USBCLKConfig()` 选 USB 时钟源分频，
`RCC_APB1PeriphClockCmd(RCC_APB1Periph_USB, ENABLE)` 打开 USB 外设时钟。

→ **用户工程里的 `Set_USBClock()` 调用不是「CH32 不存在的函数」，不能一删了之。**
处理二选一：① 保留调用点，把函数体换成 CH32 版写法；② 改调用为 `Set_USBConfig()`，
并在 `hw_config.h` 里补上原型（CH32 版原型在 `hw_config.h`，与 ST 同位置）。

差别只在**分频怎么定**：

| | ST | CH32 |
|---|---|---|
| 分频选择 | **写死**（例程按 72 MHz 主频写 1.5 分频） | **运行时按 `SYSCLK` 反推**：144 MHz→/3、96 MHz→/2、48 MHz→/1 |

对齐动作：

1. **不要只改函数名、不要照抄 ST 的固定分频** —— CH32 版开头多了 `RCC_GetClocksFreq()`
   反推逻辑，`RCC_USBCLKConfig()` 的参数随主频变化；固定分频一旦与当前主频不匹配，
   USB 直接枚举失败，编译期一句都不报。
2. **别漏 `RCC_APB1PeriphClockCmd(RCC_APB1Periph_USB, ENABLE)`** —— 两侧都有这一句，
   USB 时钟没开时表现是「完全不枚举」，同样无编译提示。
3. 若用户工程把「选分频」与「开时钟」拆在两处（如 `SystemInit()` 里开时钟、
   `Set_USBClock()` 只选分频），**合并进这一个函数**，别留两处 —— 重复使能无害，
   但分叉后容易漏改其中一处。

## 四、`EXTEN_CTR` 速查（USB 相关位）

| 宏 | 位 | 值 | 用途 |
|---|---:|---|---|
| `EXTEN_USBD_PU_EN` | 1 | `0x00000002` | **USBD 内置上拉使能** |
| `EXTEN_USBD_LS` | 0 | `0x00000001` | USBD 低速模式 |
| `EXTEN_PLL_HSI_PRE` | 4 | `0x00000010` | **PLL 以 HSI 为源**（STM32 只能 HSI/2 作源） |
| `EXTEN_ETH_10M_EN` | 2 | `0x00000004` | 10M 以太网（V203 无此功能） |

## 五、USB 工程文件结构与例程索引

**CH32 例程的文件结构，与 ST 的 USB-FS-Device 例程是同构的**（这一点很关键）：

```
<例程>/
├── User/
│   ├── Main.c
│   ├── system_ch32v20x.c/h
│   ├── ch32v20x_it.c/h
│   ├── usbd_<设备名>.c/h          ← 例程本人的应用层（如 UART/TIM 与报文互转），非库
│   └── USBLIB/
│       ├── USB-Driver/inc/        ← usb_regs.h, usb_core.h, usb_int.h, usb_mem.h, usb_sil.h ...
│       ├── USB-Driver/src/        ← 对应的 .c
│       └── CONFIG/                ← usb_conf.h, hw_config.c/h, usb_pwr.c/h,
│                                     usb_istr.c/h, usb_endp.c, usb_desc.c/h, usb_prop.c/h
```

> `usbd_compatibility_hid.c` 之类**不是**把 `usb_prop` / `usb_desc` / `usb_endp` / `usb_istr`
> 合并成一个文件 —— 它只是例程的应用逻辑（UART2/TIM2 ↔ HID 报文桥接）。
> `CONFIG/` 下那 7 组文件与 ST 例程**一一对应、职责相同**。

HID 例程索引（**直接对照可省大量时间**）：

| 例程 | 路径 | 说明 |
|---|---|---|
| `CompatibilityHID` | `EXAM/USB/USBD/CompatibilityHID` | **兼容 HID（含自定义/键盘/鼠标）**，通用性最好，**推荐基准** |
| `CompositeKM` | `EXAM/USB/USBD/CompositeKM` | 复合设备（键盘 + 鼠标） |
| `SimulateCDC-HID` | `EXAM/USB/USBD/SimulateCDC-HID` | CDC + HID 复合 |
| `SimulateCDC` | `EXAM/USB/USBD/SimulateCDC` | 纯 CDC |
| `CH372` | `EXAM/USB/USBD/CH372` | 厂商自定义设备 |
| `MSC_CD-ROM` / `MSC_U-Disk` | 同目录 | 驱动层带例程钩子，见 §1.4 |

**中断**（两边**中断名相同、中断号不同**，一律写符号名）：

| 项 | STM32F103 | CH32V20x |
|---|---|---|
| USB 低优先级 / CAN1 RX0 | `USB_LP_CAN1_RX0_IRQn` = 20 | `USB_LP_CAN1_RX0_IRQn` = **36** |
| USB 唤醒 | `USBWakeUp_IRQn` = 42 | `USBWakeUp_IRQn` = **58** |
| 服务函数 | `USB_LP_CAN1_RX0_IRQHandler` / `USBWakeUp_IRQHandler` | 同名 |

→ 服务函数名不用改，但 **CH32 侧必须补 `__attribute__((interrupt("WCH-Interrupt-fast")))`**
（与其它外设中断一致，见主技能 `references/06_interrupt-map.md`）。

## 六、程序差异点

### 6.1 端点状态寄存器「全清」+ 口复位（✅ 已定位）

外部文档 §4.6.3(1) 说「CH32 端点状态寄存器初始化时需进行全清操作」但在图片里没有代码。
CH32 源码里的落点就是 §1.2(d) —— `CONFIG/usb_prop.c` 的 `USBD_init()`：
`for (i=0;i<8;i++) _SetENDPOINT(i,_GetENDPOINT(i) & 0x7F7F & EPREG_MASK);//all clear`，
外加 `_SetISTR(0x00FF)`、`USB_Port_Set(DISABLE)` → `Delay_Ms(20)` → `USB_Port_Set(ENABLE)`。

**处理方式**：不要把这 5 句照抄进任意位置 —— 它们必须落在**用户工程自己的 `XXX_Init()`**
（即 `DEVICE_PROP` 结构体里 `Init` 字段指向的那个函数）的 `USB_SIL_Init()` 之后。

### 6.2 `usb_regs.h`：补丁与改名（不再是待定项）

外部文档 §4.6.3(2) 的「替代 `usb_regs.h`、3 个函数被修改」= §1.2(a) 的 3 处 `while`。

**按方案 B，这件事不需要单独处理**：驱动层整份用 CH32 官方版（§1.3 硬性要求 2），
那 3 处 `while`、`CNTR`→`CNTLR` 指针宏改名、`Ep0RxBlks` / `_GetNumBlock` 的引入全都随之到位，
**不需要先弄清 ST 版写了什么**。下面这份函数清单仅用于事后排查 —— 确认照搬是否完整：

```
SetCNTR/GetCNTR  SetISTR/GetISTR  GetFNR  SetDADDR/GetDADDR  SetBTABLE/GetBTABLE
SetENDPOINT/GetENDPOINT  SetEPType/GetEPType
SetEPTxStatus/SetEPRxStatus/GetEPTxStatus/GetEPRxStatus
SetEPTxValid/SetEPRxValid  SetEP_KIND/ClearEP_KIND
Set_Status_Out/Clear_Status_Out  SetEPDoubleBuff/ClearEPDoubleBuff
GetTxStallStatus/GetRxStallStatus  ClearEP_CTR_RX/ClearEP_CTR_TX
ToggleDTOG_RX/ToggleDTOG_TX  ClearDTOG_RX/ClearDTOG_TX
SetEPAddress/GetEPAddress  SetEPTxAddr/SetEPRxAddr  GetEPTxAddr/GetEPRxAddr
SetEPTxCount/SetEPRxCount  GetEPTxCount/GetEPRxCount
SetEPDblBuffAddr/SetEPDblBuf0Addr/SetEPDblBuf1Addr  ...
SetDouBleBuffEPStall  UserToPMABufferCopy/PMAToUserBufferCopy
ToWord / ByteSwap / FreeUserBuffer
```

### 6.3 配置层照搬后仍要核的三处

配置层按 §1.3 整份用 CH32 版，这三处**天然正确**；但仍要确认它们与**用户工程**接上了 ——
`hw_config.c` 写的是 CH32 例程的引脚与接法，未必等于用户的硬件：

| 点 | CH32 侧位置 | 核对什么 |
|---|---|---|
| USB 时钟分频 | `hw_config.c` 的 `Set_USBConfig()`（ST 侧同职责函数叫 `Set_USBClock()`，见 §3.1） | ① 是否有按 SYSCLK 选 `RCC_USBCLKConfig` 的那段；② 末尾是否有 `RCC_APB1PeriphClockCmd(RCC_APB1Periph_USB, ENABLE)`（§三） |
| 上拉与口复位 | `hw_config.c` 的 `USB_Port_Set()` | `EXTEN_USBD_PU_EN` 与 PA11/PA12 的 `CFGHR`/`OUTDR` 设置（§二）；用户若另有「控制外接上拉」的逻辑要删掉 |
| 中断注册 | `hw_config.c` 的 `USB_Interrupts_Config()` | 走 `USB_LP_CAN1_RX0_IRQn`（CH32=36）；**服务函数在用户的 `ch32v20x_it.c` 里**，必须补 `WCH-Interrupt-fast` 属性（§五、§1.5 第 5 条） |

### 6.4 命名前缀差异：**不必为对齐而改名**

CH32 例程用 `USBD_` 前缀（`USBD_init` / `USBD_Reset` / `USBD_SetConfiguration` /
`USBD_GetDeviceDescriptor` …），ST 例程用设备名前缀（`HID_Init` / `Virtual_Com_Port_Init` …）。
**这是例程风格差异，不影响功能** —— 只要用户工程里 `DEVICE_PROP` / `USER_STANDARD_REQUESTS`
结构体注册的函数名与其定义一致即可，**不要为了「和 CH32 一样」去批量改名**。

## 七、本文件的已确认 / 未确认清单

| 项 | 状态 | 依据 |
|---|---|---|
| 两侧 USB 寄存器映射相同（`RegBase` / `PMAAddr` / 各寄存器偏移） | ✅ CH32 侧核实 | `usb_regs.h:39-52` 宏定义 |
| 指针宏改名 `CNTR`→`CNTLR`；位宏与函数名不变 | ✅ CH32 侧核实 | `usb_regs.h:47/117-131/194-207` |
| `usb_mem.c` 两个 PMA 拷贝函数写法与 ST 公开版本一致 | ✅ CH32 侧核实 / 🟠 ST 侧待对照 | 代码特征（`pdwVal++` 双递增等） |
| `USBFSD_TypeDef`（`0x50000000`）是另一套视图，USB 库不用 | ✅ CH32 侧核实 | `ch32v20x.h:654-705/922` |
| CH32 在 3 个端点状态宏上加了 `while` 读回校验 | ✅ CH32 侧核实 | `usb_regs.h:250/274/307/311` |
| `_SetEPRxCount` 的 EP0 分支 + `Ep0RxBlks` + `USB_Istr()` 回写 | ✅ CH32 侧核实 / 🟠 ST 侧待对照 | `usb_regs.h:509`、`usb_istr.c:17/57` |
| `USB_Istr()` ESOF / `Suspend()` 的复位重同步序列 | ✅ CH32 侧核实 / 🟠 ST 侧待对照 | `usb_istr.c:146-176`、`usb_pwr.c:81-108` |
| `USBD_init()` 的「全清 + 口复位 + 延时」5 句 | ✅ CH32 侧核实 / 🟠 ST 侧待对照 | `usb_prop.c:201-215` |
| include 链差异（`usb_lib.h` / `usb_type.h` / `usb_regs.h`） | ✅ CH32 侧核实 | 三个文件头部 |
| 7 个例程驱动层 diff 结果（5 个一致、2 个 MSC 带钩子） | ✅ 已核实 | `diff -rq` |
| USBD 内置上拉，`EXTEN_USBD_PU_EN` 位 1 | ✅ 已核实 | `ch32v20x.h` 位定义；`hw_config.c:168` |
| `EXTEN_PLL_HSI_PRE` 位 4（PLL 用 HSI 作源） | ✅ 已核实 | `ch32v20x.h` 位定义 |
| 使用 USBD 时主频限 48/96/144 MHz | ✅ 已核实 | `hw_config.c:57-79` 的分频选择 |
| 时钟配置**函数名不同、作用相同**：ST `Set_USBClock()` ↔ CH32 `Set_USBConfig()`；CH32 侧**无** `Set_USBClock` 定义 | ✅ CH32 侧核实 / 🟠 ST 侧待对照 | 函数体 `hw_config.c:57-81`（选分频 + `RCC_APB1PeriphClockCmd(RCC_APB1Periph_USB, ENABLE)`）、原型 `hw_config.h:24` |
| `DEVICE_PROP` 在 `GetStringDescriptor` 与 `MaxPacketSize` 之间多一个 `void* RxEP_buffer`（驱动层不使用，纯占位）；CH32 例程的初始化写 **12 个值** | ✅ CH32 侧核实 / 🟠 ST 侧待对照 | `usb_core.h:117`；`usb_prop.c:38-52`（第 11 个为 `0`） |
| `usb_istr.c` 的 ESOF 复位重同步段受 `#if (IMR_MSK & ISTR_ESOF)` 门控 | ✅ CH32 侧核实 | `usb_istr.c:146`；`IMR_MSK` 定义在 `usb_conf.h`，CH32 版含 `CNTR_ESOFM` |
| `EP_NUM` 只在 `usb_conf.h:17` 定义、被 `usb_prop.c:34` 使用 —— 属**业务层配置**，须沿用用户工程的值 | ✅ CH32 侧核实 | 全工程 grep |
| CH32 例程描述符值：VID/PID `0x1A86`/`0xFE07`、厂商串 `wch.cn`、产品串 `CH32V20x`、序列号 `0123456789`（**误换 `usb_desc.c` 才会要求上位机改**） | ✅ CH32 侧核实 | `usb_desc.c` |
| 上位机（PC 端）无需改动 —— 描述符全在业务层，方案 B 原样保留 | ✅ 结论 | §1.6 |
| 两套库文件名完全相同（不能共存两份） | ✅ 已核实 | 目录清单 |
| 上述所有 🟠（ST 侧那一半） | 🟠 待对照 | 本工作区无 ST 侧 USB 库 → 做实际转换时按 §八 第 1 步，到新工程根目录下的 `.mrs/originalKeilFiles/` 读**用户源工程那份版本**的 ST 侧源码逐行对照（**须在删除该目录之前**） |

> 上表 🟠 项**不得当成两侧逐行比对结论使用**；但它们**不影响迁移动作** ——
> 对齐方向是明确的（向 CH32 官方实现靠），需要确认的只是「用户工程版本里差多少」。

## 八、USB 资料不全时怎么补

USB 是本技能覆盖最薄的一块，原因很实在：**做符号比对时工作区里没有 ST 侧 USB 库**
（`stm32f10x-stdperiph-lib-master` 只含标准外设库，不含 USB-FS-Device 驱动），
所以 USB 无法像 19 个标准外设那样做全量四维 diff。本文件里所有 🟠 项都由此而来。
⚠ 但**实际转换时是有 ST 侧源码可读的** —— 工程级转换已把整份原始 Keil 工程文件放进
**新工程根目录下的 `.mrs/originalKeilFiles/`**，按本步读它即可逐项落地；
**该目录交付前随目录一起删除（`SKILL.md` 阶段 4.4），所以本步必须在删除之前完成。**

补齐方式固定三步（与 SKILL.md「参考文件覆盖不到时怎么办」一致）：

**1. 检索知识库 + 两侧源码对照（并列为首选依据）**

- **知识库**：在 MRS 智能体自带的知识库里检索「CH32V20x / CH32V203 USB 库、USB 例程、
  `usb_regs.h`」等，拿到 CH32 侧的权威口径（版本、已知问题、型号差异）。
- **两侧源码**：
  - 源工程侧：`STM32_USB-FS-Device_Driver/{inc,src}` —— 去**新工程根目录下的
    `.mrs/originalKeilFiles/`** 里读，**不需要向用户索要**。（若该目录不存在 → 向用户索要
    ST 侧 USB 库源码或请其重跑工程级转换；**不得凭记忆推断**。）
  - 目标侧：`CH32V20xEVT/EVT/EXAM/USB/USBD/<最接近的例程>/User/USBLIB/{USB-Driver,CONFIG}`。
- 做法：同名文件逐行对照。**优先看 `.h` 里的宏** —— CH32 的补丁大多藏在头文件的宏里，
  `.c` 常常是原样搬运（见 §1.2 的 `while` 与 `_GetNumBlock`）。
- ⚠ 按方案 B（§1.3），这一步的用途是**事后核对「照搬是否完整」**、以及资料不全时补齐认知，
  **不是**用来逐行改写工程文件 —— 驱动层与配置层直接照搬即可。

**2. 官方例程对照**

- 以 §1.4 选定的基准例程（HID 用 `CompatibilityHID`）为准。
- **以例程的实际写法为准**，不按 ST 侧的习惯推导；注意分辨例程钩子与库改动。

**3. 仍不确定 → 停下问用户**，标为未确认。

> 反面教材：手上那份《从 STM32F103C8T6 移植到 CH32V203C8T6》的 USB 章节（§4.6）
> 关键内容全在截图里，且它**只说了「替代 `usb_regs.h`」这一步**，
> 没说端点寄存器全清要落在 `Init()` 里、也没说主频与分频的对应写法。
> 另外该文档把 `CPAR`/`CMAR` 与 `PADDR`/`MADDR` 的对应关系写反了
> （两侧源码按结构体偏移核对是明确的）。**这类文档只能当线索，不能当依据。**
