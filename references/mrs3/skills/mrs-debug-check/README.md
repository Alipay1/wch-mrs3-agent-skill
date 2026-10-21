# debug-check Skill

调试前检查 Skill（WCH RISC-V 工程）：**第一步**调用 `ide-check-before-debug` 做调试前检测（返回"调试前检测失败" → 直接终止检查），检测通过后再执行容量检查（规则1/规则2）、FLASH 起始地址检查（规则3，需询问用户）、断点上限检查。

> **适用场景**：当用户需要执行**任何调试相关操作**时（开始/继续/暂停/单步调试、调试检查、设置/管理断点、查看调试配置、下载程序后调试、IAP/APP 调试、调试异常排查、RAM/Flash 容量检查、断点上限、页擦、FLASH 起始地址非0 等），**或用户问题中包含调试相关关键词**（调试、debug、单步、断点、调试配置、烧录、下载程序后调试、无法运行 等）时，都必须先调用本技能完成调试前检查。

| 检查项 | 实现方式 | 规则 |
|---|---|---|
| 规则1 FLASH/RAM 容量 | 脚本（硬性） | 总 FLASH、总 RAM 分别**小于等于**（`≤`）mcu_isa.json 中芯片最大 flash/sram（link.ld MEMORY 块多区域 LENGTH 合计，支持表达式） |
| 规则2 内存分配检查 | 工具确认支持性 + 脚本（硬性） | 先调用 `ide-debug-support-memory-allocation` 查支持性；支持 → `ide-debug-read-memory-allocation` 读 RAM 值，`--ram-avail` 传入，总 RAM ≤ 该值；不支持 → 跳过 |
| 规则3 FLASH 起始地址非 0 | 脚本检测 + **Agent 询问用户** | 询问"0 地址是否有程序"：无 → WCH 芯片无法运行，提醒修改；有 → IAP+APP，调试需开启页擦 |
| 断点上限 | 脚本读取 + Agent 遵守 | mcu_isa.json 的 `maxbreakpoint`（空 = 不限制；非空 = 最大断点数），`--breakpoints <n>` 可硬校验 |
| 调试前检测 | **【必须】第一步执行** | 先于所有其他校验调用 `ide-check-before-debug`：返回"调试前检测失败" → **终止检查**；检测通过 → 才继续后续校验（不提示"检测成功"） |
| 下载工具 | Skill 规则 | 调试前不需要调用 IDE 内部下载工具（调试时自动下载） |

## 目录结构

```
debug-check/
├── SKILL.md           # Skill 定义（规则/使用流程/询问事项/输出格式）
├── check_debug.bat    # Windows 启动器（仅转发调用 check_debug.ps1，转发退出码）
├── check_debug.ps1    # 检查脚本（PowerShell 版核心逻辑；原生 UTF-8、支持正斜杠路径）
├── check_debug.sh     # 检查脚本（bash 版，Linux/macOS 使用，--selftest 内置自测）
├── mcu_isa.json       # 数据副本（38 系列 / 98 型号；芯片级可选字段 maxbreakpoint，缺失/为空 = 不限制）
└── tests/             # 测试样例（正常 / 等于上限 PASS / 超上限 FAIL / 多区域 / 起始地址非 0）
```

> `maxbreakpoint` 为芯片级可选字段：为空或缺省表示当前调试不限制断点数；非空（如 `10`）表示最大支持的断点数。当前数据副本中未含该字段（不限制），源数据更新后请同步覆盖。

## 校验规则

1. **规则1（容量，硬性）**：解析 link.ld `MEMORY` 块，`FLASH*`/`RAM*` 区域 LENGTH 全部相加；总 FLASH ≤ 芯片最大 flash 且总 RAM ≤ 芯片最大 sram（**小于等于，大于上限判 FAIL**，等于上限可通过）。LENGTH 支持表达式（`448K - 256`/`0x3FC00`/`64K*2`），内置计算器转十进制（仅用于比较，不改写文件）。**修改原则：仅当合计超过上限（FAIL）时，才调整 link.ld 超限区域的 LENGTH 使合计 ≤ 上限；在合理范围内（≤ 上限，含等于上限）不得修改 FLASH/RAM 的任何值。**
2. **规则2（内存分配检查，硬性）**：**先调用 `ide-debug-support-memory-allocation` 查看芯片/调试器是否支持内存分配检查**；支持 → 再调用 `ide-debug-read-memory-allocation` 读取内存分配中的 RAM 值 → `--ram-avail` 传入 → 总 RAM ≤ 该值；**不支持 → 跳过规则2，不检查**。
3. **规则3（起始地址，脚本检测 + Agent 询问）**：FLASH `ORIGIN != 0` 时脚本输出 ⚠ 提示；**Agent 必须询问用户"0 地址是否有程序"**——无 → WCH 芯片程序无法运行，提醒修改；有 → IAP+APP，调试当前程序需开启页擦。此提示不影响 PASS/FAIL。
4. **断点上限**：读取 `maxbreakpoint`（空 = 不限制；非空 = 上限），Agent 设置断点总数不得超过；`--breakpoints <n>` 可硬校验。
5. **下载**：调试前不调用 IDE 内部下载工具（调试时自动下载）。
6. **调试前检测（【必须】第一步执行）**：位于整个校验流程**第一步**（先于定位 link.ld 及规则1/2/3、断点上限等），必须调用 `ide-check-before-debug`（异步 → 轮询）不得跳过；**工具返回"调试前检测失败" → 直接终止检查**，提示用户检测失败的原因（如与 Debug level 相关，可指引到"属性页 → Build Settings → Debugging → Debug level"修改后再编译，**推荐使用 default(-g)**）；**检测通过 → 才继续后续校验，不输出"调试前检测成功/通过"提示**。

## 用法

```bash
# Windows（.bat 为启动器，内部调用 check_debug.ps1）
cmd /c "check_debug.bat" V5F\link.ld --chip CH32H417WEU
cmd /c "check_debug.bat" V3F\link.ld V5F\link.ld --chip CH32H417WEU        # 双核合计
cmd /c "check_debug.bat" V5F\link.ld --chip CH32H417WEU --ram-avail 896K   # 规则2
cmd /c "check_debug.bat" V5F\link.ld --chip CH32H417WEU --breakpoints 5    # 断点上限
# 调试前检测（ide-check-before-debug，第一步）由 skill 调用完成，无需脚本参数
# 也可直接调用 PowerShell 脚本：
powershell -NoProfile -ExecutionPolicy Bypass -File check_debug.ps1 V5F/link.ld --chip CH32H417WEU

# Linux / macOS
bash check_debug.sh V5F/link.ld --chip CH32H417WEU --ram-avail 896K
```

退出码：0 = PASS；1 = 存在 FAIL（规则1/规则2/断点上限）；2 = FATAL（文件/配置缺失、无法推断型号）。`--quiet` 只输出结论与 ⚠/❌ 行。

## 自测

```bash
cmd /c "check_debug.bat" --selftest   # Windows；Linux/macOS 用 bash check_debug.sh --selftest（均支持）
```

自测覆盖表达式计算器（`480K`、`0x3FC00`、`64K*2`、`448K - 256`、`1M/2`、`0x1000+0x2000`、`ALIGN(4)` 不可计算）。

测试样例（tests/）：
- `link_v5f_ok_nonzero_origin.ld`：CH32H417WEU，480K≤960K、448K≤896K PASS；ORIGIN=0x40000000 触发规则3 ⚠；
- `link_single_origin_zero.ld`：CH32V203CCT，FLASH=256K=上限 → 规则1 PASS（等于上限）；ORIGIN=0 不触发规则3；
- `link_multi_equal_limit.ld`：多区域 64K+192K=256K=上限、RAM=32K=上限 → 规则1 PASS（等于上限）；
- `link_single_over_limit.ld`：CH32V203CCT，FLASH=300K>256K 上限 → 规则1 FAIL（超上限）。

## 安装

1. 将 `debug-check` 目录复制到 Agent 的 skills 目录。
2. `mcu_isa.json` 内置副本，脚本固定从本技能目录加载（不接受路径参数）；源数据更新后请同步覆盖本目录副本（含可选的 `maxbreakpoint` 字段）。
3. Agent 调用时需保证 `mrs-ide-tools_ide-get-projectToOperate` / `ide-get-project-linker-scripts` / `ide-get-project-chipType` 可用，并正确处理异步任务轮询。
