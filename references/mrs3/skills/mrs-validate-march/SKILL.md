---
name: mrs-validate-march
description: 检查和校验工程编译配置，【触发条件】当用户要求"校验或者编译架构、march、ISA 扩展、工具链、toolchain、已安装工具链、ide-get-installed-toolchain、ABI、startfile、启动文件、riscvTargetProcessor、编译配置与芯片不匹配、修复编译配置"时使用本技能。
---

# mrs-validate-march — 编译架构与编译配置校验

## 1. 目的

工程编译配置（架构 march、工具链 toolchain、整数 ABI、启动文件 startfile）必须与芯片能力一致：配置了不支持的 ISA 扩展/ABI 会导致编译报错或生成非法指令，工具链版本不在支持列表内可能链接异常，启动文件与型号不匹配会导致启动异常。本技能通过 IDE 读取工程的编译属性，对照 `mcu_isa.json` 逐项校验；发现问题时通过 IDE 工具修复。

**【执行边界】本技能只负责校验、必要的修复、复检和报告。完成这些步骤后必须立即停止，不得自主触发编译、构建、链接或烧录；只有用户另行明确要求执行上述动作时，才可进入相应流程。用户要求“检查编译配置”或“编译前检查”不等于授权执行编译。**

## 2. 校验项与规则

### 2.1 march（架构）— 参考 `cores[].isa_ext`
1. **检查 march 是否以 `rv32` 开头**，不是则直接报错；
2. **分割 march**：按 `_` 分割；首个分段去掉 `rv32` 前缀后**按字符逐个拆分**（如 `rv32imafc` → `i`,`m`,`a`,`f`,`c`），后续分段**原样保留**（如 `zba_zbb_zbc_zbs_xw` → `zba`,`zbb`,`zbc`,`zbs`,`xw`）；
3. **与 isa_ext 比对**：拆分出的每一项都必须在**该内核**的 `isa_ext` 中，**全部命中才算 PASS**，否则 FAIL 并列出缺失项。
   - 示例：`rv32imafc_zba_zbb_zbc_zbs_xw` → `i,m,a,f,c,zba,zbb,zbc,zbs,xw`，CH32H417 V5F 的 `isa_ext: [i,m,a,c,f,zba,zbb,zbc,zbs,xw]` 全部命中 → PASS（成员关系比对，**不要求顺序一致**）。

### 2.2 toolchain（工具链）— 参考系列级 `toolchain` 数组
- **`component_toolchain` 的值必须在该芯片所属系列的 `toolchain` 数组中**（如 CH32H417 为 `["GCC12","GCC15"]`，则 GCC12/GCC15 通过，GCC8 报错）；
- **【必须】检查完工具链值是否匹配后，调用 `ide-get-installed-toolchain` 获取已安装的工具链列表**，通过脚本 `--installed-toolchains <列表>`（逗号分隔）传入：
  - **值不匹配、需要修改时**：新值必须从**已安装且允许**（已安装列表 ∩ 系列 `toolchain` 数组）中选择——脚本输出"建议改为已安装且允许的工具链: X"；若**无交集**，提示需先安装对应工具链（不能随便改成未安装的版本）；
  - **值匹配但不在已安装列表中**：脚本输出 ⚠ 提示"当前工具链不在已安装列表中，请确认"（不判 FAIL）。

### 2.3 abi（整数 ABI）— 参考 `cores[].mabi` 数组
- **`riscvTargetProcessor.integer_ABI` 的值必须在该芯片内核的 `mabi` 数组中**（如 CH32H417 V5F 为 `["ilp32f","ilp32"]`，则 ilp32f/ilp32 通过，ilp32e 报错）。

### 2.4 startfile（启动文件）— 参考 `chips[].startfile` 数组（只提示，不修改）
- **校验工程 Startup 目录下的 `.S` 文件是否与 mcu_isa.json 中该型号的 `startfile` 数组一致**；
- Startup 目录位置：工程目录下 `Common/Startup` 或 `<V3F|V5F>/Startup`（以实际工程为准，可用工具定位）；
- **不一致时只输出 ⚠ 提示**（列出期望/实际/缺少/多余），**不进行任何修改**；
- 型号 `startfile` 为 `[]`（无数据）时跳过该校验。

## 3. 获取/设置编译属性（IDE 工具）

编译属性必须通过 IDE 工具获取与设置，**不要直接改工程文件**：

1. **【必须】获取当前工程路径**：先调用 **`mrs-ide-tools_ide-get-projectToOperate`** 获取当前工程路径（异步任务 → 轮询 `get-task-status` 至 success → 取结果）；该路径用于确定当前工程上下文和双核工程的 V3F/V5F 子目录，**不得从路径名直接确定芯片型号**。
2. **【必须】获取工程芯片型号**：调用 **`mrs-ide-tools_ide-get-project-chipType`**，传入第 1 步取得的当前工程路径，轮询 **`mrs-ide-tools_ide-get-task-status`** 至 success 后取得工程属性中的芯片型号。该结果是 ISA、march、ABI、toolchain 和 startfile 校验的芯片依据，**优先级高于工程名、父目录名和路径中出现的其他型号**。
3. **获取属性**：调用 **`mrs-ide-tools_ide-get-project-build-property`**，分别查询：
   - **`riscvTargetProcessor`** → 结果中取 **`architecture`**（march）与 **`integer_ABI`**（abi）；
   - **`component_toolchain`** → 结果为工具链值（如 `GCC15`）；
4. 上述 IDE 工具为异步任务：返回"任务已提交 (ID: task_xxx)"后，用 **`mrs-ide-tools_ide-get-task-status`** 轮询直到 `任务状态: success`，再读取结果。
5. **获取已安装工具链（工具链校验后）**：调用 **`mrs-ide-tools_ide-get-installed-toolchain`** 获取已安装的工具链列表（异步任务 → 轮询 `get-task-status` 至 success → 取结果，如 `GCC12, GCC15, GCC8`），作为修改 `component_toolchain` 的依据。
6. **设置属性（修复时用）**：调用 **`mrs-ide-tools_ide-set-project-build-property`** 修改对应属性（如 `riscvTargetProcessor.architecture`、`riscvTargetProcessor.integer_ABI`、`component_toolchain`），同样为异步任务，需轮询至 success。

## 4. 使用流程（Agent 按此执行）

1. **【必须】获取当前工程路径**：先调用 `mrs-ide-tools_ide-get-projectToOperate` 获取当前工程路径，后续 IDE 工具调用均以该工程为上下文。
2. **【必须】确定芯片型号与内核**：
   1. 先调用 **`mrs-ide-tools_ide-get-project-chipType`** 读取当前工程属性中的芯片型号，轮询 `get-task-status` 至 success；后续查找 `mcu_isa.json` 与执行脚本时的 `--chip` **必须使用该值**。
   2. 若 chipType 与工程路径或工程名中的型号不一致，**以 chipType 为准**，路径中的型号不参与 ISA/march 匹配；可在报告中提示该差异。例如工程 `Test` 的 chipType 为 `CH32V307`，即使父路径含 `CH32V003`，也必须按 `CH32V307` 校验。
   3. 仅当 `ide-get-project-chipType` 失败或返回空值时，才可按“用户明确告知的型号 → `.wvproj/.project` 中的型号 → 路径中的型号”顺序降级推断，并在报告中标明芯片型号的来源及工具失败原因。
   4. 内核需在已确定的芯片型号范围内判定：单核芯片使用其唯一内核；双核芯片再根据当前工程上下文中的 `V3F` / `V5F` 子目录确定内核。路径只可用于区分已确定的双核芯片内核，不可用于替代 chipType 判定芯片型号。
3. **获取编译属性**：按第 3 节查询 `riscvTargetProcessor`（architecture、integer_ABI）与 `component_toolchain`。
4. **查参考值**：必须使用本技能目录的 `mcu_isa.json`，定位芯片的系列 `toolchain`、对应内核的 `isa_ext` 与 `mabi`、型号的 `startfile`。注意！必须使用本技能目录下的 mcu_isa.json（与脚本同目录，脚本直接在同目录加载该文件，**不接受路径参数**；不要使用工程里其他位置的 mcu_isa.json）。
5. **执行比对（按以下顺序）**：
   1. **根据操作系统平台选择原生脚本**（与 Python 版逻辑一致，均支持 `--selftest` 内置自测）：
      - **Windows 平台 → 执行 `check_march.bat`**（启动器，内部调用 PowerShell 脚本 `check_march.ps1` 实现核心校验；无需 Python，原生支持 UTF-8 与正斜杠路径）：
        ```
        cmd /c "<skill目录>\check_march.bat" --chip CH32H417WEU --core v5f --march <architecture值> --toolchain <GCC15> --abi <ilp32f>
        # march 也可直接与手动扩展列表比对（跳过 mcu_isa.json）：
        cmd /c "<skill目录>\check_march.bat" --march rv32imac_xw --isa-ext i,m,a,c,xw
        # 已安装工具链列表（来自 ide-get-installed-toolchain）：
        cmd /c "<skill目录>\check_march.bat" --chip CH32H417WEU --core v5f --toolchain <GCC8> --installed-toolchains GCC12,GCC15
        ```
      - **Linux / macOS 平台 → 执行 `check_march.sh`**（bash 脚本，无需 Python）：
        ```
        bash <skill目录>/check_march.sh --chip CH32H417WEU --core v5f --march <architecture值> --toolchain <GCC15> --abi <ilp32f>
        bash <skill目录>/check_march.sh --march rv32imac_xw --isa-ext i,m,a,c,xw
        bash <skill目录>/check_march.sh --chip CH32H417WEU --core v5f --toolchain <GCC8> --installed-toolchains GCC12,GCC15
        ```
      - **平台判断**：命令执行环境为 cmd / PowerShell（可运行 `.bat`）→ Windows；为 bash / sh（可运行 `.sh`）→ Linux/macOS。
   2. **最后按第 2 节规则手工拆分比对**（上述脚本均无法运行时）。
   所有脚本（`.bat`+`.ps1` / `.sh`）逻辑一致，均直接加载**本技能目录**的 `mcu_isa.json`（不接受路径参数），均支持 `--selftest` 内置自测。
6. **【必须】工具链检查后查已安装工具链**：若本次校验包含工具链项（提供了 `--toolchain`），检查匹配结果后**必须**调用 **`mrs-ide-tools_ide-get-installed-toolchain`** 获取已安装列表，并**重新执行脚本追加 `--installed-toolchains <已安装列表>`**，取得"已安装且允许"交集与修改建议（见第 3 节第 5 条）。
7. **发现问题时修复（必须调用 IDE 工具）**：对 FAIL 项，调用 **`mrs-ide-tools_ide-set-project-build-property`** 修改对应属性：
    - march 不匹配 → 根据 mcu_isa.json 中该内核的 `march` 值，参考ide-property-readBuildConfigRawType的属性节点的值枚举，以修改 `riscvTargetProcessor`中相关的属性值 。例如mcu_isa.json 中该内核的 `march` 值为rv32ec_zmmul_xw时, 需同时改变以下属性：修改riscvTargetProcessor.architecture为`rv32e`，riscvTargetProcessor.compressed_extension为true, riscvTargetProcessor.multiplication_subset_of_the_M_extension为true, riscvTargetProcessor.extra_compressed_extension为true； 
   - toolchain 不在列表 → 修改 `component_toolchain` 为**已安装且允许的工具链**（如 `${WCH:Toolchain:GCC15}`）；**无交集时提示用户先安装对应工具链，不得改为未安装的版本**；
   - abi 不在列表 → 修改 `riscvTargetProcessor.integer_ABI` 为该内核 `mabi` 中的值。
   - **【约束】工具链在允许范围内时保持原值**：如果读上来的 `component_toolchain` 已在芯片允许的 `toolchain` 范围内，则在设置编译参数时，**禁止修改工具链参数**。
   异步提交 → 轮询 `get-task-status` 至 success；**修改后重新获取属性并再次校验，直到全部 PASS**。startfile 不一致**不要修改**，只提示。
8. **startfile 校验（只提示，不修改）**：定位工程 Startup 目录（如 `<工程>/Common/Startup` 或 `<工程>/<V3F|V5F>/Startup`），用脚本 `--startfile-dir <目录>` 与 mcu_isa.json 的 `startfile` 比对；不一致时输出 ⚠ 提示（期望 vs 实际），**不要修改**。
9. **输出结论**：报告每项校验的取值、参考值、PASS/FAIL（或 ⚠ 提示）；FAIL 项说明已做的修改与修改后的校验结果；工具链相关说明"已安装列表 / 已安装且允许 / 建议值"。
10. **停止**：输出结论后结束本技能，**不得继续调用任何编译、构建、链接或烧录工具**。校验通过或修复后复检通过，都不构成执行编译的授权。

## 5. 输出报告格式

```
编译配置校验报告（CH32H417WEU / 系列 CH32H417 / 内核 QingKeV5F）
  ✅ [march]     march=rv32imafc_zba_zbb_zbc_zbs_xw → 拆分: i, m, a, f, c, zba, zbb, zbc, zbs, xw
                | isa_ext: i, m, a, c, f, zba, zbb, zbc, zbs, xw | 全部命中
  ✅ [toolchain] component_toolchain=GCC15 | 允许值: GCC12, GCC15
                | 已安装(ide-get-installed-toolchain): GCC12, GCC15, GCC8 | 已安装且允许: GCC12, GCC15
  ✅ [abi]       riscvTargetProcessor.integer_ABI=ilp32f | 允许值: ilp32f, ilp32
  ⚠ [startfile] Startup 目录 <工程>/Common/Startup 与 startfile 不一致（只提示，不修改）
                | 期望(startfile)=startup_ch32v20x_D6.S | 实际=startup_wrong.S
                | 缺少: startup_ch32v20x_D6.S | 多余: startup_wrong.S
结论: ✅ PASS — 全部校验通过（startfile 为提示项，不修改）
```

FAIL 示例（修复前）：

```
  ❌ [toolchain] component_toolchain=GCC8 | 允许值: GCC12, GCC15 | ❌ GCC8 不在允许列表中
  ❌ [abi]       riscvTargetProcessor.integer_ABI=ilp32e | 允许值: ilp32f, ilp32 | ❌ ilp32e 不在允许列表中
结论: ❌ FAIL — 存在不匹配项
```

修复流程示例：调用 `ide-set-project-build-property`（toolchain=GCC12、integer_ABI=ilp32）→ 重新获取属性 → 重新校验 PASS
> 注：示例中 toolchain=GCC12 仅适用于**工具链不在允许范围**（校验 FAIL）需修正的场景；若工具链校验已通过（在允许范围内），则**工具链参数保持读上来的原值**，只修改 march/ABI 等不匹配项。

## 6. 注意事项

- **【必须】工程上下文**：每次执行本技能，第一步都必须是调用 `mrs-ide-tools_ide-get-projectToOperate` 获取当前工程路径，禁止跳过该步骤直接猜测工程路径。
- **【必须】芯片型号来源**：获取工程路径后，必须优先调用 `mrs-ide-tools_ide-get-project-chipType` 获取工程属性中的芯片型号。chipType 成功返回时，禁止使用工程名、父目录名或路径中的芯片字样覆盖它；路径型号仅可在 chipType 失败/为空时作为最后兜底。
- **【必须】修复走 IDE 工具**：发现问题需要修改时，**必须**调用 `mrs-ide-tools_ide-set-project-build-property` 修改，禁止直接改工程配置文件。
- **【必须】校验完成即停止**：本技能的终点是校验/修复/复检结果报告；除非用户另行明确要求，否则禁止自主执行编译、构建、链接或烧录。
- **【必须】工具链在允许范围内时保持原值**：当读上来的 `component_toolchain` 已在芯片允许的 `toolchain` 范围内（该校验项 PASS）时，设置编译参数**必须继续使用读上来的工具链原值**，不得修改、不得替换为其他工具链值；仅当工具链校验 FAIL（不在允许范围）时才允许修改工具链参数，且**修改时必须按 `ide-get-installed-toolchain` 的已安装列表选择"已安装且允许"的工具链**（脚本会给出建议值）；无交集时提示用户先安装，不得改为未安装的版本。
- **startfile 只提示不修改**：startfile 校验结果不一致时仅输出 ⚠ 提示，**不修改任何文件**，也不计入 FAIL。
- **双核芯片**（CH32H415/H416/H417）：`isa_ext` 与 `mabi` 是**内核级**属性，必须按当前工程的内核取值比对；`toolchain` 是**系列级**属性，与内核无关。`--core v3f|v5f` 用于指定内核，缺省对全部内核逐一比对（任一匹配即 PASS）。
- 比对是**成员包含关系**（march 拆分项 ⊆ isa_ext），不要求顺序一致。
- `architecture`/`integer_ABI`/工具链值为空或工具结果异常时，先检查工程上下文与属性名是否正确，不要凭空猜测。 
- 注意：修改文件必须使用`ide-edit`工具
