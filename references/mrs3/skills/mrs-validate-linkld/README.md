# validate-linkld Skill

校验 WCH RISC-V 工程 `link.ld` 链接脚本的 Skill：对照**本技能目录下**的 `mcu_isa.json` 检查 FLASH/RAM 容量上限（多区域 LENGTH 合计、支持 `448K - 256`/`0x3FC00` 等表达式）、语法（括号/分号/运算符空格）、`__global_pointer$` 符号。**检查出问题后必须修复**（修改 link.ld 文件），修复完毕后调用 `ide-decorate-diffs` 渲染。

## 目录结构

```
validate-linkld/
├── SKILL.md              # Skill 定义（名称/描述/使用流程/校验清单/输出格式）
├── validate_linkld.py    # 校验脚本（Python 版，优先使用）
├── validate_linkld.bat   # Windows 启动器（仅转发调用 validate_linkld.ps1，转发退出码）
├── validate_linkld.ps1   # 校验脚本（PowerShell 版核心逻辑，与 Python 版一致；原生 UTF-8、支持正斜杠路径，无 findstr 依赖）
├── validate_linkld.sh    # 校验脚本（bash 版，Linux/macOS 且 Python 不可用时使用）
├── mcu_isa.json          # 芯片容量数据副本（38 系列 / 98 型号）——必须使用本目录这份，脚本同目录加载，不接受路径参数
└── tests/                # 测试样例（模板正常 / 超限 / 单核错误 / 多区域 / 表达式 / 语法错误）
```

## Agent 调用流程（SKILL.md 中的要点）

0. **【必须】** 先调用 `mrs-ide-tools_ide-get-projectToOperate`（异步 → 轮询 `get-task-status`）获取当前工程路径，作为校验上下文。
1. **定位 link.ld**：调用 `mrs-ide-tools_ide-get-project-linker-scripts`（异步任务 → 轮询 `get-task-status` → 取结果），双核工程会返回 V3F、V5F 两份；用户提供路径时直接用。
2. **确定芯片型号**：用户告知 → `mrs-ide-tools_ide-get-project-chipType`（异步+轮询）→ 最后从 link.ld 注释/路径/`.wvproj/.project/.cproject` 推断（正则 `CH32[A-Z0-9]+`）。
3. **执行脚本（按平台选择）**：优先 `python validate_linkld.py <link.ld> [link.ld2] [--chip ...] [--core ...]`；Python 不可用时**根据平台选择原生脚本**——Windows 执行 `validate_linkld.bat`（`cmd /c "<skill目录>\validate_linkld.bat" ...`，启动器内部调用 PowerShell 脚本 `validate_linkld.ps1`，核心逻辑与 Python 版一致，原生支持 UTF-8 与正斜杠路径，不依赖 findstr），Linux/macOS 执行 `validate_linkld.sh`（`bash <skill目录>/validate_linkld.sh ...`）；全部不可用时按 SKILL.md 清单人工逐项检查。
4. **mcu_isa.json**：脚本固定加载本技能目录的 `mcu_isa.json`（脚本同目录），不接受 `--json` 等路径参数。
5. **发现问题必须修复**：修改 link.ld 文件（容量超限 → 按多区域**合计**调整 LENGTH 使合计 ≤ 芯片上限；语法错误 → 修正），修复后重新校验至 PASS。
6. **【必须】修复后渲染**：调用 `mrs-ide-tools_ide-decorate-diffs` 完成页面渲染；**调用后直接返回，无需等待执行结果**（不轮询、不等待）。

## 用法

```bash
# Python 版（优先）
python validate_linkld.py V3F/link.ld --chip CH32H417WEU --core v3f
python validate_linkld.py V3F/link.ld V5F/link.ld --chip CH32H417WEU   # 双核合计

# Windows（Python 不可用时；.bat 为启动器，内部调用 validate_linkld.ps1）
cmd /c "validate_linkld.bat" V3F\link.ld --chip CH32H417WEU --core v3f
cmd /c "validate_linkld.bat" V3F\link.ld V5F\link.ld --chip CH32H417WEU
# 也可直接调用 PowerShell 脚本：
powershell -NoProfile -ExecutionPolicy Bypass -File validate_linkld.ps1 V3F/link.ld --chip CH32H417WEU

# Linux / macOS（Python 不可用时）
bash validate_linkld.sh V3F/link.ld --chip CH32H417WEU --core v3f
bash validate_linkld.sh V3F/link.ld V5F/link.ld --chip CH32H417WEU
```

## 自测

```bash
python validate_linkld.py tests/link_v5f_ok.ld                        # 期望 PASS
python validate_linkld.py tests/link_v5f_overflow.ld                  # 期望 FAIL（FLASH 超限）
python validate_linkld.py tests/link_single_bad.ld --chip CH32V203CCT --core single  # 期望 FAIL
python validate_linkld.py tests/link_syntax_bad.ld                    # 期望 FAIL（括号/分号/未定义区域）
python validate_linkld.py tests/link_space_bad.ld                     # 期望 FAIL（运算符缺空格）
python validate_linkld.py tests/link_comment_wildcard_ok.ld           # 期望 PASS（注释/通配符不误报）
python validate_linkld.py tests/link_number_expr_ok.ld                # 期望 PASS（数字表达式原样保留）
python validate_linkld.py tests/link_multi_region_ok.ld --chip CH32V203CCT --core single       # 期望 PASS（多区域合计不超限）
python validate_linkld.py tests/link_multi_region_overflow.ld --chip CH32V203CCT --core single  # 期望 FAIL（多区域合计超限）
python validate_linkld.py tests/link_expr_length_ok.ld --core v5f     # 期望 PASS（LENGTH 表达式计算）
```

## 校验规则一览（已移除符号/段/栈堆检查）

| 级别 | 内容 |
|---|---|
| ERROR | FLASH/RAM 全部区域（多行/`FLASH2`/`RAM2` 等）LENGTH **合计**超过 mcu_isa.json 中芯片上限（LENGTH 支持表达式如 `448K - 256`、`0x3FC00`，内置计算器统一转十进制后相加）；双核合计超上限；括号不配对（`{}`/`()`/`[]`，注释剥离后）；MEMORY 块中存在无法解析的行；**运算符两侧缺少空格**（需修复补空格） |
| WARN | 容量使用率 ≥90%（按合计）；区域引用（`>区域`/`AT>区域`/`ORIGIN()`/`LENGTH()`）未定义；赋值语句缺少分号（MEMORY 块外、不含 `{}` 的行中含 `=` 且未以 `;` 结尾）；INCLUDE 文件不存在 |
| INFO | 解析出的 MEMORY 区域（含十进制换算值）与芯片上限、使用率；**`__global_pointer$` 缺失时报告**（不影响 PASS） |

## ld 语法检测项（新增）

- **括号配对**：注释剥离后检查 `{}`、`()`、`[]` 是否配对（注释中的括号不影响检测）；
- **MEMORY 行格式**：MEMORY 块内每行必须是 `名称(属性) : ORIGIN = 值, LENGTH = 值` 格式，无法解析的行报 ERROR（带行号）；
- **多区域合计（容量比较核心）**：MEMORY 块中 FLASH/RAM 可能有多行/多个区域（区域名以 FLASH/RAM 开头，如 `FLASH2`、`RAM2`），同类全部 LENGTH **相加**后与芯片上限比较；`LENGTH = 448K - 256`、`LENGTH = 0x3FC00` 等表达式由内置小型计算器（`calc_length`，支持 `+ - * / % << >> & | ^ ~`、括号、K/M/G 后缀、十进制/十六进制）统一转十进制后再计算；含符号/函数（如 `ORIGIN(RAM)`、`ALIGN(4)`）时报告“无法计算”。**计算仅用于校验比较，绝不改写 ld 文件**；
- **`__global_pointer$` 检查**：ld 文件（注释剥离后）中未出现 `__global_pointer$` 时输出 INFO 报告（不影响 PASS）；
- **区域引用**：`>FLASH`、`AT> FLASH`、`ORIGIN(RAM)`、`LENGTH(RAM)` 必须引用已定义区域，未定义时报 WARN（可能来自 INCLUDE 文件）；
- **赋值分号**：MEMORY 块外、不含 `{}` 的行中，含 `=` 且未以 `;`（或续行符 `, + - * / % & | ^ < > = (`）结尾的赋值语句报 WARN 缺少分号；
- **运算符空格（ERROR，需修复）**：变量与运算符（`=`、`+`、`-`、`/`、`%`、`<<`、`>>`、`&`、`|`、`^`）之间必须有空格，如 `_estack=...`、`a+b` 报错；**注释（含跨行块注释）与通配符（`*(.text)`、`.text*`）不检查**；**运算符两侧均为数字字面量（如 `64K*2`、`0x1000+0x2000`）时不检查空格，且【绝对禁止】计算其数值最终值——不得求值、不得换算单位、不得合并化简，必须原样保留**；`/DISCARD/` 段名、一元负号不检查。修复方式：运算符两侧补空格。
- **脚本无法运行时的强制人工检查**：Python 与对应平台脚本（Windows 的 `.bat` / Linux、macOS 的 `.sh`）均无法运行时，人工逐行核对运算符两侧空格（注释与通配符不检查）与赋值分号，发现缺失必须修复补空格。
