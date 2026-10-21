# 08 core_riscv 专项（内核层）

**结论：`core_riscv.h` 与 `core_riscv.c` 整份直接换成目标侧（002/005/006 共用同一份），不需要手工改。**

---

## 8.1 差异全景

`core_riscv.h`：V003 473 行 / 目标 434 行。差异只有三类：

| 类 | 内容 | 处理 |
|---|---|---|
| ① 逐字节相同（约 95%） | 类型定义、`PFIC_Type` / `SysTick_Type` 结构、`NVIC_KEY*`、`__enable_irq` / `__disable_irq` / `__NOP`、8 个 `NVIC_*IRQ`、`NVIC_SetPriority`、`_SEV`、`__WFI`、`SetVTFIRQ`、`NVIC_SystemReset`、导出的 `__get_*` / `__set_*` 声明 | ✅ 直接换 |
| ② 同名、实现不同（2 个） | `_WFE()` · `__WFE()` | ⚠️ 见 8.2 |
| ③ V003 独有、目标侧整体删除（3 个） | `WFItoWFE()` · `WFE(u32 t)` 声明 · `_WFE_()` 宏 | ❌ 见 8.3 |

### 相同部分明细（不用动）

`__I/__O/__IO` 定义、`vuc32` 等旧类型别名、`ErrorStatus` / `FunctionalState` / `FlagStatus` / `ITStatus`
枚举、`RV_STATIC_INLINE` 宏、`PFIC_Type` 结构体、`SysTick_Type` 结构体、
`PFIC` / `NVIC` / `NVIC_KEY1..3` / `SysTick` 宏、
`__enable_irq` `__disable_irq` `__NOP` `NVIC_EnableIRQ` `NVIC_DisableIRQ` `NVIC_GetStatusIRQ`
`NVIC_GetPendingIRQ` `NVIC_SetPendingIRQ` `NVIC_ClearPendingIRQ` `NVIC_GetActive` `NVIC_SetPriority`
`_SEV` `__WFI` `SetVTFIRQ` `NVIC_SystemReset`
（其中 `__disable_irq` / `NVIC_DisableIRQ` 里的 `"fence.i" ` 与 `"fence.i"` 只差一个尾随空格，无语义差异）

### `core_riscv.c`

目标侧唯一差异：**删掉末尾整个 `WFE(uint32_t t)` 函数**（该函数带 `.highcode` 段）：

```c
/* V003 侧独有，目标侧不存在 */
__attribute__( (section(".highcode")) ) void WFE(uint32_t t)
{
  asm volatile ("wfi");
  asm volatile ("1:addi a0, a0, -1\n\t"
                "bnez a0, 1b\n\t"
          );
}
```

其余函数（`__get_MSTATUS` 等一批 `__get_*` / `__set_*`）逐字节相同。

---

## 8.2 同名、实现不同：`_WFE()` 与 `__WFE()`

根因是 `.highcode` 机制被移除——V003 靠"把 `WFE()` 搬进 RAM 执行"来做等待延时，
目标侧改成就地执行 `wfi`。

| | V003 | 目标侧 |
|---|---|---|
| `_WFE()` 等待方式 | `WFItoWFE(); _WFE_();`（即 `NVIC->SCTLR \|= (1<<3)` + `WFE(19)`） | `NVIC->SCTLR \|= (1<<3); asm volatile ("wfi");` |
| `_WFE()` 非嵌套分支 | `else { NVIC->SCTLR \|= (1<<4); __disable_irq(); }` | **无 else 分支** |
| `_WFE()` 收尾 | 两分支对称恢复后**无条件** `__enable_irq()` | 只在嵌套分支里 `__enable_irq()` |
| `__WFE()` 等待方式 | `_SEV(); WFItoWFE(); _WFE_(); WFItoWFE(); _WFE_();` | `_SEV(); NVIC->SCTLR \|= (1<<3); wfi; NVIC->SCTLR \|= (1<<3); wfi;` |

`__WFI()` 两侧相同（都是 `__WFE();`）。

**处理**：用户代码只要不是直接依赖这两个函数的内部时序，整份换掉即可。
若用户代码调用了 `_WFE()` / `__WFE()` 做低功耗等待，编译会通过但**行为变了** → 🔴 人工核对耗时/唤醒路径。

---

## 8.3 V003 独有、目标侧删除的 3 个符号

| 符号 | 形式 | 说明 |
|---|---|---|
| `WFItoWFE()` | `static inline` 函数 | 置 `NVIC->SCTLR` bit3 |
| `WFE(u32 t)` | 函数声明（定义在 `.c`，带 `.highcode` 段） | 忙等 t 次 `wfi`，实际靠 RAM 执行 |
| `_WFE_()` | 宏（`#define _WFE_() WFE(19)`，另有 24M/16M/8M 注释备选） | 供 `_WFE`/`__WFE` 调用 |

**用户代码引用这三个符号 → 目标侧编译期报未声明**（编译器可兜底），但**需要人工决定替代写法**，
因为目标侧没有 `.highcode` 机制。替代方向：直接用 `__WFI()` / `__WFE()`，或按目标侧写法就地 `wfi`。

---

## 8.4 与 `.highcode` 段的联动

| 载体 | V003 | 目标侧 |
|---|---|---|
| `Link.ld` 的 `.highcodelalign` / `.highcode` 段 | 有 | **无** |
| `startup_*.S` 的段搬运代码（`_highcode_lma` / `_highcode_vma_start` / `_highcode_vma_end`） | 有 | **无** |
| `core_riscv.h` 的 `WFE()` 声明 + `_WFE_()` 宏 | 有 | **无** |
| `core_riscv.c` 的 `WFE()` 定义 | 有 | **无** |

全库扫描：**目标侧没有任何** `WFItoWFE` / `_WFE_` / `WFE(` / `.highcode` 引用。
用户工程里若出现 `__attribute__((section(".highcode")))`，**链接期才报错**（找不到段），
需重定向到普通段或删除该属性（见 `01_model-and-project.md` 第 3 节）。

---

## 8.5 阶段 3 强制核对清单（core_riscv）

- [ ] 用户代码是否引用 `WFE(...)` / `WFItoWFE()` / `_WFE_()` → 改 `__WFI()` / `__WFE()` 或删除
- [ ] 用户代码是否调用 `_WFE()` / `__WFE()` 做低功耗等待 → 核对唤醒路径与耗时
- [ ] 用户代码是否出现 `__attribute__((section(".highcode")))` → 删除该属性（目标侧无此段）
- [ ] `core_riscv.h` / `core_riscv.c` 是否已整份替换为目标侧版本
