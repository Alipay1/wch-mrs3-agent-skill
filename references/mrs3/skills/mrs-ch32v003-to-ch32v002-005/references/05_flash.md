# 05 FLASH 专项

FLASH 是本次迁移里"编译期零提示、上机才炸"风险最集中的模块。规则文件只给了一句话，
本文件逐项展开并与两侧源码核对。

---

## 5.1 页粒度：64 字节 → 256 字节 🔴

规则原文：「扇区大小相同都是 1KB。页大小不同：003 页大小是 64 字节，所以执行快速页擦除/编程的最小单位是 64 字节；
002/5 页大小是 256 字节，所以执行快速页擦除/编程的最小单位是 256 字节」。

源码佐证（两侧函数注释）：

| | V003 `ch32v00x_flash.c` | 目标 `ch32v00X_flash.c` |
|---|---|---|
| `FLASH_ProgramPage_Fast` 注释 | `Program a specified FLASH page (1page = 64Byte)` | `Program a specified FLASH page (1page = 256Byte)` |
| `FLASH_ROM_ERASE` 要求 | `StartAddr%64 == 0` | `StartAddr%256 == 0` |

**影响**：`FLASH_ErasePage(addr)` / `FLASH_ErasePage_Fast(addr)` / `FLASH_ProgramPage_Fast(addr)`
在**两侧同名、同签名**，但一次作用的字节数从 64 变成 256。

| 用户写法 | 迁移后后果 |
|---|---|
| 按 64B 步长循环调用 `FLASH_ErasePage` / `ProgramPage_Fast`（典型：模拟 EEPROM、参数存储） | 🔴 目标侧每次调用擦掉整 256B 页 → **反复擦同一页、并连带擦掉相邻 3 个 64B 块的数据** |
| 按 64B 对齐的地址做页内偏移编程 | 🔴 地址对齐要求从 64 变 256，需重算 |
| 只做整块擦写（按 1KB 扇区 / 整片） | 🟡 通常不受影响，但仍要核对地址对齐 |

**处理**：凡用户代码里出现 `FLASH_ErasePage` / `ErasePage_Fast` / `ProgramPage_Fast` 的
**循环步长或地址对齐**，一律按 256 字节重算。这是硬性核对项，不能靠编译器发现。

---

## 5.2 编程 API 被整体替换 🔴（规则文件未覆盖）

V003 提供的字/半字/选项字节编程函数，**目标侧全部没有同名同义替代**：

| V003 侧函数 | 目标侧 |
|---|---|
| `FLASH_ProgramWord(uint32_t Address, uint32_t Data)` | **无** |
| `FLASH_ProgramHalfWord(uint32_t Address, uint16_t Data)` | **无**（002/5 不支持半字写，规则文件已提） |
| `FLASH_ProgramOptionByteData(uint32_t Address, uint8_t Data)` | **无** |

> 注意：不止半字写没了，**字编程 `FLASH_ProgramWord` 也没了**。规则文件只提了半字写。

**目标侧替代路径**（两者都在目标侧存在）：

| 路径 | 用法 |
|---|---|
| A. 快速编程 | `FLASH_Unlock_Fast()` → `FLASH_BufLoad(addr, data)` 填 256B 页缓冲 → `FLASH_ProgramPage_Fast(addr)` → `FLASH_Lock_Fast()` |
| B. ROM 接口 | `FLASH_ROM_ERASE(StartAddr, Length)` / `FLASH_ROM_WRITE(StartAddr, pbuf, Length)`（两端都有，签名相同） |

`FLASH_BufLoad` / `FLASH_BufReset` / `FLASH_Unlock_Fast` / `FLASH_Lock_Fast` 两侧同名同签名，
可沿用；差异只在**每次装载的字节数与页边界**（见 5.1）。

---

## 5.3 写保护粒度：16 页/组 → 8 页/组

| | V003 | 目标侧 |
|---|---|---|
| 每组页数 | 16 | 8 |
| 组数 | 16（`Pages0to15` … `Pages240to255`） | 32（`Pages0to7` … `Pages240to247`） |
| `FLASH_WRProt_AllPages` | `0x0000FFFF` | `0xFFFFFFFF` |

**同名宏只有 `FLASH_WRProt_AllPages`，值从 `0x0000FFFF` 变 `0xFFFFFFFF`** ——
🟡 语义都是"全部页"，用宏名即正确，不必改。

**其余 16 个 `Pages0to15` 式宏在目标侧不存在**（目标侧叫 `Pages0to7` 式）→ 编译期报未声明。
处理：按目标侧 8 页/组重新选择写保护组。**若原意是"保护某一段"，映射后会扩大保护范围**，
需按字节地址重新换算到目标侧的组号。

---

## 5.4 读保护：函数名与签名同时变

| | V003 | 目标侧 |
|---|---|---|
| 函数 | `FLASH_ReadOutProtection(FunctionalState NewState)` | `FLASH_EnableReadOutProtection(void)` |
| 语义 | 传参决定开/关 | 只负责**开启**，无关闭参数 |

规则原文写「`FLASH_EnableReadOutProtection` 函数差异：V003 需要传参」——
**实测 V003 侧的函数名是 `FLASH_ReadOutProtection`**，两侧名与签名都不同。
以源码为准（boss 已确认冲突以源码为准）。

处理：改成 `FLASH_EnableReadOutProtection()`，去掉实参。查询状态用 `FLASH_GetReadOutProtectionStatus()`（两侧同名）。

---

## 5.5 其他 FLASH 宏差异

| 宏 | V003 | 目标侧 | 处理 |
|---|---|---|---|
| `FLASH_FLAG_OPTERR` | `0x00000001` | `0x80000001` | 🟡 同名异值，用宏名传参即正确 |
| `FLASH_OBR_USER` | `0x03FC` | `0x00F4` | 🔴 用户选项字节掩码变，直接做位运算的需重算 |
| `FLASH_CTLR_PG` `FLASH_CTLR_OPTPG` `FLASH_STATR_LOCK` `FLASH_STATR_MODE` `FLASH_MODEKEYR_KEY1/2` `FLASH_OBR_*` `FLASH_FLAG_BANK1_EOP` `FLASH_IT_BANK1_*` | 有 | 无 | 目标侧改名为 `FLASH_CTLR_PAGE_PG` / `FLASH_CTLR_PAGE_ER` / `FLASH_CTLR_OPTER` / `FLASH_CTLR_BER32` 等，按 `ch32v00X_flash.h` 重选 |
| `FLASH_EraseBlock_32K_Fast` | 无 | 有 | 目标侧新增（32K 块擦） |

---

## 5.6 其他 FLASH 函数（两侧同名同签名，需核对行为）

| 函数 | 两侧 | 说明 |
|---|---|---|
| `FLASH_Unlock` / `FLASH_Lock` | 同名同签名 | 标准解锁/加锁 |
| `FLASH_Unlock_Fast` / `FLASH_Lock_Fast` | 同名同签名 | 快速编程解锁 |
| `FLASH_BufReset` / `FLASH_BufLoad(addr, Data0)` | 同名同签名 | 差异在装载字节数（64B vs 256B） |
| `FLASH_ErasePage(Page_Address)` | **同名同签名、行为不同** | 🔴 见 5.1 |
| `FLASH_ErasePage_Fast(Page_Address)` | **同名同签名、行为不同** | 🔴 见 5.1 |
| `FLASH_ProgramPage_Fast(Page_Address)` | **同名同签名、行为不同** | 🔴 见 5.1 |
| `FLASH_EraseAllPages` / `FLASH_EraseOptionBytes` | 同名同签名 | — |
| `FLASH_EnableWriteProtection(uint32_t FLASH_Pages)` | 同名同签名 | 粒度变，见 5.3 |
| `FLASH_UserOptionByteConfig(uint16_t OB_IWDG, uint16_t OB_STDBY, uint16_t OB_RST, uint16_t OB_PowerON_Start_Mode)` | 同名同签名 | 选项字节定义见 5.5 |
| `FLASH_GetUserOptionByte` / `FLASH_GetWriteProtectionOptionByte` / `FLASH_GetReadOutProtectionStatus` | 同名同签名 | — |
| `FLASH_GetStatus` / `FLASH_GetBank1Status` / `FLASH_WaitForLastOperation` | 同名同签名 | — |
| `FLASH_ITConfig` / `FLASH_GetFlagStatus` / `FLASH_ClearFlag` | 同名同签名 | 标志位宏见 5.5 |
| `FLASH_ROM_ERASE` / `FLASH_ROM_WRITE` | 同名同签名 | 对齐要求 64→256 |

---

## 5.7 阶段 3 强制核对清单（FLASH）

- [ ] 用户代码是否出现 `FLASH_ErasePage` / `ErasePage_Fast` / `ProgramPage_Fast` 的循环或地址对齐 → 按 256B 重算
- [ ] 是否有 `FLASH_ProgramWord` / `ProgramHalfWord` / `ProgramOptionByteData` 调用 → 改 Fast 编程或 ROM 接口
- [ ] 是否有 `FLASH_ReadOutProtection` → 改 `FLASH_EnableReadOutProtection()` 去参
- [ ] 是否有 `FLASH_WRProt_PagesNtoM`（16 页式）→ 按 8 页/组重选
- [ ] 是否对 `FLASH_OBR_USER` 做位运算 → 按 `0x00F4` 重算
- [ ] `FLASH_ROM_ERASE` / `FLASH_ROM_WRITE` 的起始地址是否满足 `%256 == 0`
