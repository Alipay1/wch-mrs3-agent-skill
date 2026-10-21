# validate-march Skill

校验工程编译配置与 `mcu_isa.json` 是否匹配的 Skill。覆盖三项编译配置 + startfile 校验：

| 校验项 | 取值来源（IDE 属性） | 参考值（mcu_isa.json） | 不匹配时 |
|---|---|---|---|
| march 架构 | `riscvTargetProcessor` → `architecture` | 内核 `isa_ext` | 修复：`ide-set-project-build-property` |
| 整数 ABI | `riscvTargetProcessor` → `integer_ABI` | 内核 `mabi` | 修复：`ide-set-project-build-property` |
| 工具链 | `component_toolchain` | 系列 `toolchain` | 修复：`ide-set-project-build-property`（**按 `ide-get-installed-toolchain` 已安装列表选"已安装且允许"的值**） |
| startfile | 工程 Startup 目录的 `.S` 文件 | 型号 `startfile` | **只提示（⚠），不修改** |

修改完成后必须调用 `ide-decorate-diffs` 渲染页面（调用后直接返回，无需等待执行结果）。

## 目录结构

```
validate-march/
├── SKILL.md           # Skill 定义（规则/工具调用流程/修复与渲染流程/输出格式）
├── check_march.py     # 确定性比对脚本（Python 版，优先使用，--selftest 内置自测）
├── check_march.bat    # Windows 启动器（仅转发调用 check_march.ps1，转发退出码）
├── check_march.ps1    # 确定性比对脚本（PowerShell 版核心逻辑，与 Python 版一致；原生 UTF-8、支持正斜杠路径）
├── check_march.sh     # 确定性比对脚本（bash 版，Linux/macOS 且 Python 不可用时使用，--selftest 内置自测）
├── mcu_isa.json       # 数据副本（38 系列 / 98 型号）——脚本同目录加载，不接受路径参数
└── README.md
```

## 校验规则

1. **march**：必须 `rv32` 开头；按 `_` 分割，首段去掉 `rv32` 后逐字符拆分（`rv32imafc` → `i,m,a,f,c`），后续段原样保留（`zba_zbb_zbc_zbs_xw` → `zba,zbb,zbc,zbs,xw`）；拆分项 ⊆ 内核 `isa_ext` 全部命中 → PASS。
2. **toolchain**：`component_toolchain` ∈ 系列 `toolchain` 数组；**检查完匹配后必须调用 `ide-get-installed-toolchain` 获取已安装列表**，通过 `--installed-toolchains` 传入脚本——需要修改时新值必须选**已安装且允许**（交集）的工具链（脚本给出建议值）；无交集时提示先安装；值匹配但未安装时脚本 ⚠ 提示。
3. **abi**：`riscvTargetProcessor.integer_ABI` ∈ 内核 `mabi` 数组。
4. **startfile**：工程 Startup 目录的 `.S` 文件与型号 `startfile` 数组一致；不一致**只提示（⚠），不修改**；`startfile` 为 `[]` 时跳过。

## Agent 调用流程（SKILL.md 中的要点）

0. **【必须】** 先调用 `mrs-ide-tools_ide-get-projectToOperate`（异步 → 轮询 `get-task-status`）获取当前工程路径，作为校验上下文（双核工程据此区分 V3F/V5F）。
1. 调用 `mrs-ide-tools_ide-get-project-build-property` 查询 `riscvTargetProcessor`（取 `architecture` 与 `integer_ABI`）和 `component_toolchain`（均为异步 → 轮询）。
2. 对照本技能目录 `mcu_isa.json` 的 `isa_ext` / `mabi` / `toolchain` / `startfile` 执行比对。
3. **发现问题时修复**：调用 `mrs-ide-tools_ide-set-project-build-property` 修改对应属性（异步 → 轮询），修改后重新获取属性并再次校验至 PASS；startfile 不一致**只提示不修改**。**约束：若工具链（component_toolchain）已在芯片允许范围内（校验 PASS），设置编译参数时工具链保持读上来的原值，不得修改；仅工具链校验 FAIL 时才可修改工具链参数，且必须按 `ide-get-installed-toolchain` 的已安装列表选择"已安装且允许"的工具链（脚本 `--installed-toolchains` 会给出建议值），无交集时提示用户先安装。** 执行比对用脚本：优先 Python（`check_march.py`）；Python 不可用时按平台选择——Windows 执行 `check_march.bat`（启动器 → `check_march.ps1` 核心），Linux/macOS 执行 `check_march.sh`，三版逻辑与参数一致。
4. **修改完成后**：必须调用 `mrs-ide-tools_ide-decorate-diffs` 进行页面渲染；**调用后直接返回，无需等待执行结果**（不轮询、不等待）。

## 用法

```bash
# Python 版（优先）
python check_march.py --chip CH32H417WEU --core v5f \
    --march rv32imafc_zba_zbb_zbc_zbs_xw --toolchain GCC15 --abi ilp32f

# 工具链：检查完匹配后调用 ide-get-installed-toolchain 获取已安装列表，再传入脚本获取交集与修改建议
python check_march.py --chip CH32H417WEU --core v5f --toolchain GCC8 --installed-toolchains GCC12,GCC15,GCC8

# Windows（Python 不可用时；.bat 为启动器，内部调用 check_march.ps1）
cmd /c "check_march.bat" --chip CH32H417WEU --core v5f \
    --march rv32imafc_zba_zbb_zbc_zbs_xw --toolchain GCC15 --abi ilp32f
# 也可直接调用 PowerShell 脚本：
powershell -NoProfile -ExecutionPolicy Bypass -File check_march.ps1 --chip CH32H417WEU --core v5f --march rv32imafc_zba_zbb_zbc_zbs_xw

# Linux / macOS（Python 不可用时）
bash check_march.sh --chip CH32H417WEU --core v5f \
    --march rv32imafc_zba_zbb_zbc_zbs_xw --toolchain GCC15 --abi ilp32f

# 只校验其中几项也可以
python check_march.py --chip CH32V203CCT --toolchain GCC12 --abi ilp32
python check_march.py --march rv32imac_xw --isa-ext i,m,a,c,xw   # 手动指定扩展
python check_march.py --selftest                                 # 内置自测（py/bat+ps1/sh 均支持）

# startfile 校验（只提示，不修改；退出码不受影响）
python check_march.py --chip CH32V203CCT --startfile-dir <工程>/Common/Startup
```

退出码：0 = PASS，1 = FAIL（startfile 不一致仅 ⚠ 提示，不影响退出码）。`--core` 只对双核芯片有意义（`v3f`/`v5f`）；缺省对全部内核逐一比对，任一匹配即 PASS。

## 自测结果（当前实现）

| 用例 | 期望 | 结果 |
|---|---|---|
| rv32imafc_zba_zbb_zbc_zbs_xw vs H417 V5F 扩展 | PASS | ✅ |
| rv32imac_xw vs i,m,a,c,xw | PASS | ✅ |
| rv32ec_xw vs e,c,xw | PASS | ✅ |
| rv32imafdc_...（含 d） | FAIL | ✅ |
| rv64imac_xw（非 rv32） | FAIL | ✅ |
| rv32imac_zba_zbb_zbc_zbs_xw（zba..zbs 不在） | FAIL | ✅ |
| rv32（拆分后为空） | FAIL | ✅ |
| 顺序无关（march f 在 c 前 / isa_ext c 在 f 前） | PASS | ✅ |

## 安装

1. 将 `validate-march` 目录复制到 Agent 的 skills 目录（如 opencode 的 `~/.config/opencode/skills/` 或工程 `.opencode/skills/`）。
2. `mcu_isa.json` 内置副本，脚本固定从本技能目录加载（不接受路径参数）；源数据 `MCU_ISA/mcu_isa.json` 更新后请同步覆盖本目录副本。
3. Agent 调用时需保证 `mrs-ide-tools_ide-get-project-build-property`（riscvTargetProcessor / component_toolchain）可用，并正确处理异步任务轮询。
