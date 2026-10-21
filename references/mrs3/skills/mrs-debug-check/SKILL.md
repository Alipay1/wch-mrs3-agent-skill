---
name: mrs-debug-check
description: 调试前检查（WCH RISC-V 工程）。【触发条件】当用户需要执行【任何调试相关操作】时都必须先调用本技能进行检查；或用户问题中包含调试相关关键词（调试、debug、调试检查、单步、断点、调试配置、IAP/APP 调试、无法运行、RAM/Flash 容量、页擦、FLASH 起始地址 等）时也必须调用本技能。
---

# mrs-debug-check — 调试前检查

## 1. 目的

在开始调试前，对工程做三类检查，避免调试失败或运行异常：①**容量**——link.ld 配置的 FLASH/RAM 超过芯片实际容量会导致下载/运行越界；②**FLASH 起始地址**——起始地址非 0 时程序能否运行取决于 0 地址是否有程序（IAP+APP 场景），需要用户确认并做相应处理；③**断点上限**——超出硬件支持的断点数会设置失败。

**【必须】适用场景**：当用户需要执行**任何调试相关操作**（开始/继续/暂停/单步调试、调试检查、设置/管理/删除断点、查看调试配置、下载程序后调试、IAP/APP 调试、调试异常/无法运行排查等）时，**都必须先调用本技能完成调试前检查**，检查通过后再执行对应的调试操作。**用户问题中包含调试相关关键词**（调试、debug、单步、断点、调试配置、RAM/Flash 容量、页擦、FLASH 起始地址 等）时同样必须调用本技能。

硬性数值检查（规则1、规则2、断点上限）由脚本完成；**需要询问用户的检查（规则3）由 Agent 询问用户**。

## 2. 校验规则

### 调试前检测（**【必须】第一个校验动作**，返回"调试前检测失败"时终止）
- **【必须】允许在本检测前仅执行获取当前工程路径、双核上下文等必需的工程上下文操作；`mrs-ide-tools_ide-check-before-debug` 必须是获取工程上下文后的第一个校验动作**，并位于定位 link.ld、规则1/2/3、断点上限等所有校验之前（异步任务 → 轮询 `get-task-status` 至 success → 取结果），不得跳过、不得假定正常；
- **工具返回"调试前检测失败"** → **直接终止检查**：不再执行后续任何校验（规则1/2/3、断点上限等均不执行、不进入调试），并提示用户检测失败的原因（如与 Debug level 相关，可指引到『属性页 → Build Settings → Debugging → Debug level』修改后再编译，**推荐使用 default(-g)**）；
- **工具未返回"调试前检测失败"（检测通过）→ 才继续执行下面的校验步骤**（规则1/2/3、断点上限等），且**不要输出"调试前检测成功/通过"之类的提示**。

### 规则1 — FLASH / RAM 容量（硬性检查，脚本完成）
- 解析工程 link.ld 的 `MEMORY` 块，`FLASH*` 与 `RAM*` 区域（含 FLASH2/RAM2 等多区域）的 LENGTH **全部相加**；
- 总 FLASH、总 RAM 必须分别 **小于等于** `mcu_isa.json` 中该芯片的最大 flash / sram（`total <= max`；**大于上限判 FAIL**）；
- **【必须】修改原则**：规则1仅负责容量校验。仅当总 FLASH / 总 RAM **超过上限（规则1 FAIL）时**，才允许因容量问题修改 link.ld 中对应区域的 `LENGTH`（把超限区域的 `LENGTH` 调小，使合计 ≤ 上限）；规则1 PASS（合计 ≤ 上限，含等于上限）时，不得因容量检查修改任何 `LENGTH`。`ORIGIN` 是否需要修改由规则3独立决定，不受规则1 PASS 限制；
- LENGTH 支持表达式（`448K - 256`、`0x3FC00`、`64K*2` 等），脚本内置计算器统一转十进制后相加（仅用于校验比较，不改写文件）。

### 规则2 — 内存分配检查（先查支持性，再读取 RAM 值；硬性检查由脚本完成）
- **【必须】先调用 `mrs-ide-tools_ide-debug-support-memory-allocation` 查看当前芯片/调试器是否支持内存分配检查**（异步任务 → 轮询 `get-task-status` 至 success → 取结果）：
  - **支持** → 再调用 **`mrs-ide-tools_ide-debug-read-memory-allocation`** 读取当前内存分配中的 RAM 值（同样异步 → 轮询），通过脚本 `--ram-avail <值>` 传入；
  - **不支持** → **跳过规则2，不进行检查**（不要调用读取工具、不要传入 `--ram-avail`）；
- 校验 **总 RAM ≤ 读到的 RAM 值**（`--ram-avail` 未提供时脚本仅提示，由 Agent 按支持性决定是否读取传入）；

### 规则3 — FLASH 起始地址非 0（检测由脚本完成，**询问由 Agent 完成**）
- 脚本检测任一 link.ld 的 FLASH `ORIGIN != 0` 时输出 ⚠ 提示（带行号）；
- **Agent 必须询问用户："0 地址是否有程序？"**
  - **没有程序** → 对 WCH 芯片，起始地址非 0 且 0 地址无程序时**程序无法运行**，提醒用户修改起始地址（改为 0 或确认引导方案）；
  - **有程序** → 多为 **IAP + APP** 场景，调试当前程序时**需要开启页擦（Page Erase）**，提醒用户检查调试器的擦除方式设置。
- 在用户尚未回答时，整体检查状态必须为 **`PENDING_CONFIRMATION`（待确认）**，不得输出最终 `PASS`、不得表示可以开始调试，也不得进入调试。若用户在当前请求中已经明确说明 0 地址是否有程序，可直接按对应分支处理，无需重复询问。

### 断点上限（脚本读取 + Agent 遵守） 
- 脚本读取 `mcu_isa.json` 中该芯片的 `maxbreakpoint` 字段：
  - **为空/缺省** → 不限制断点数量；
  - **非空** → 当前调试支持的最大断点数，Agent 设置断点**不得超过该值**；
- 可传 `--breakpoints <n>` 由脚本硬校验计划断点数是否超限。

### 调试与下载
- **调试前不需要特意调用 IDE 内部的下载工具**；开始调试时会有下载过程（IDE 自动完成），Agent 不要额外触发下载。

## 3. 使用流程（Agent 按此执行）

1. **【必须】获取当前工程路径**：调用 **`mrs-ide-tools_ide-get-projectToOperate`** 获取当前工程路径（异步任务 → 轮询 `get-task-status` 至 success → 取结果）；双核工程据此确认 V3F / V5F 上下文。
2. **【必须】调试前检测（获取工程上下文后的第一个校验动作）**：调用 **`mrs-ide-tools_ide-check-before-debug`**（异步任务 → 轮询 `get-task-status` 至 success → 取结果）。除第 1 步获取工程上下文外，在此之前不得定位 link.ld、执行规则1/2/3、查询内存分配或检查断点上限：
   - **工具返回"调试前检测失败"** → **直接终止检查**：不再执行后续任何步骤（不定位 link.ld、不做规则1/2/3、断点上限等校验、不进入调试），并提示用户检测失败的原因（如与 Debug level 相关，可指引到『属性页 → Build Settings → Debugging → Debug level』修改后再编译，**推荐使用 default(-g)**）；
   - **工具未返回"调试前检测失败"（检测通过）→ 继续执行下面的校验步骤**，且**不要输出"调试前检测成功/通过"等提示**。
3. **定位 link.ld**：调用 **`mrs-ide-tools_ide-get-project-linker-scripts`**（参数为第 1 步得到的工程路径；异步 → 轮询）获取 link.ld 路径；用户提供路径时可直接使用。
4. **确定芯片型号**：优先用户告知 → 其次 **`mrs-ide-tools_ide-get-project-chipType`**（异步 → 轮询）→ 最后从 link.ld 内容/路径推断（正则 `CH32[A-Z0-9]+`）。
5. **执行检查脚本（工作目录为第 1 步工程路径，参数可用相对路径；按平台选择原生脚本）**（均支持 `--selftest`）：
   - **Windows 平台 → 执行 `check_debug.bat`**（启动器，内部调用 PowerShell 脚本 `check_debug.ps1` 实现核心校验；原生支持 UTF-8 与正斜杠路径）：
     ```
     cmd /c "<skill目录>\check_debug.bat" <link.ld路径> --chip CH32H417WEU
     # 规则2：先调用 ide-debug-support-memory-allocation 确认支持，再调用 ide-debug-read-memory-allocation
     # 读取内存分配中的 RAM 值（如 32K）传入比对；不支持则跳过：
     cmd /c "<skill目录>\check_debug.bat" <link.ld路径> --chip CH32V203CCT --ram-avail 32K
     # 计划设置 5 个断点（规则 断点上限）：
     cmd /c "<skill目录>\check_debug.bat" <link.ld路径> --chip CH32H417WEU --breakpoints 5
     # 双核工程把两份 link.ld 都传入做合计：
     cmd /c "<skill目录>\check_debug.bat" V3F\link.ld V5F\link.ld --chip CH32H417WEU
     ```
   - **Linux / macOS 平台 → 执行 `check_debug.sh`**（bash 脚本）：
     ```
     bash <skill目录>/check_debug.sh <link.ld路径> --chip CH32H417WEU
     bash <skill目录>/check_debug.sh <link.ld路径> --chip CH32V203CCT --ram-avail 32K
     bash <skill目录>/check_debug.sh <link.ld路径> --chip CH32H417WEU --breakpoints 5
     bash <skill目录>/check_debug.sh V3F/link.ld V5F/link.ld --chip CH32H417WEU
     ```
   - **平台判断**：命令执行环境为 cmd / PowerShell（可运行 `.bat`）→ Windows；为 bash / sh（可运行 `.sh`）→ Linux/macOS。
   - **脚本均无法运行时**：按第 2 节规则人工核对（容量用 link.ld 各区域 LENGTH 相加对比 mcu_isa.json 上限；起始地址看 ORIGIN 值；断点数看 maxbreakpoint 字段）。
6. **按脚本结果处理**：
   - **规则1 PASS（总 FLASH / 总 RAM ≤ 上限，含等于上限）→ 不得因容量检查修改任何 `LENGTH`**；继续独立执行规则3，由规则3决定是否需要修改 `ORIGIN`；
   - 规则1 FAIL（总 FLASH 或总 RAM **超过上限**）→ 才需要修改：调整 link.ld 中超限区域的 LENGTH，使合计 ≤ 芯片上限（用 `ide-edit` 修改，修改后重新执行检查脚本至 PASS）；规则2 / 断点上限 FAIL → 按对应规则处理（规则2 超限需调整内存分配配置或告知用户，断点数超限则减少断点）；
   - 规则3 出现 ⚠ 提示 → 若用户尚未提供信息，**必须询问用户 0 地址是否有程序**并输出 `PENDING_CONFIRMATION`，停止在待确认状态；用户回答后再按第 2 节规则3的分支处理（提醒修改 / 提示开启页擦）。
7. **输出结论**：报告每项检查结果（见第 4 节格式），说明发现的问题与处理建议。存在未完成的规则3确认时只能输出 `PENDING_CONFIRMATION`；所有硬性检查通过且不存在待确认项时才能输出 `PASS`。调试开始后，**不需要再调用 IDE 下载工具**（调试时自动下载）。

## 4. 输出报告格式

```
调试前检查报告（CH32H417WEU / 系列 CH32H417）
  ℹ [INFO] 芯片: CH32H417WEU（系列 CH32H417）| 最大 flash=960K, sram=896K
  ℹ [INFO] 文件: V5F/link.ld
  ℹ [INFO] MEMORY FLASH(rx): ORIGIN = 0x40000000 (= 1073741824), LENGTH = 480K (= 491520) (第4行)
  ℹ [INFO] MEMORY RAM(xrw): ORIGIN = 0x38000000 (= 939524096), LENGTH = 448K (= 458752) (第5行)
  ℹ [INFO] 总 FLASH 合计: 480K | 总 RAM 合计: 448K
  ✅ [规则1] FLASH 合计 480K <= 芯片最大 960K
  ✅ [规则1] RAM 合计 448K <= 芯片最大 896K
  ⚠ [WARN] [规则3] V5F/link.ld 的 FLASH 起始地址 0x40000000 ≠ 0（第4行）——需询问用户 0 地址是否有程序
  ℹ [INFO] [断点] maxbreakpoint = 10（调试时设置断点不得超过该值）
结论: ⏳ PENDING_CONFIRMATION（待确认）——请确认：0 地址是否有程序？
```

调试前检测失败的处理（首个校验动作失败即终止，示例）：

```
❌ ide-check-before-debug 返回：调试前检测失败
——【终止检查】提示用户检测失败的原因（如与 Debug level 相关，请先手动到『属性页 → Build Settings → Debugging → Debug level』修改后再编译，**推荐使用 default(-g)**）。
```

> 若 ide-check-before-debug 未返回"调试前检测失败"（检测通过），**不要输出"调试前检测成功/通过"等提示**，继续后续校验即可。

FAIL 示例：

```
  ❌ [ERROR] [规则1] FLASH 合计 1024K > 芯片最大 960K（必须小于等于上限）
结论: ❌ FAIL（1 个错误, 0 个警告）
```

## 5. 注意事项

- **【必须】规则3 要询问用户并进入待确认状态**：脚本检测到 FLASH 起始地址非 0 且用户尚未提供信息时，Agent **必须**询问用户"0 地址是否有程序"，不得跳过；答复前状态为 `PENDING_CONFIRMATION`，不得输出最终 PASS 或进入调试。按回答分支处理（无程序 → 提醒修改，WCH 芯片无法运行；有程序 → IAP+APP，提示开启页擦）。
- **【必须】断点不超过 maxbreakpoint**：脚本输出 `maxbreakpoint = N` 时，Agent 调试过程中设置断点的总数不得超过 N；未配置（空）时不限制。
- **【必须】调试前不调用 IDE 下载工具**：不要特意调用内部 IDE 的下载工具，调试时会有下载过程。
- **【必须】规则1 是小于等于**：总 FLASH / 总 RAM 必须 **≤** 芯片上限，**大于上限判 FAIL**（等于上限可通过）。
- **【必须】容量与起始地址分开处理**：规则1校验通过（总 FLASH / 总 RAM ≤ 上限，含等于上限）时，禁止因容量检查修改任何 `LENGTH`；只有合计**超过上限（FAIL）**时才允许调整超限区域的 `LENGTH`，调整目标为合计 ≤ 芯片上限，修改后重新检查。`ORIGIN` 的修改权限和处理方式完全由规则3独立决定。
- **【必须】规则2 先查支持性**：必须先调用 `ide-debug-support-memory-allocation` 确认当前芯片/调试器是否支持内存分配检查；**支持** → 再调用 `ide-debug-read-memory-allocation` 读取内存分配中的 RAM 值，传入 `--ram-avail` 比对（总 RAM ≤ 该值）；**不支持 → 跳过规则2，不检查**（不要强行读取或传入）。
- **【必须】调试前检测是第一个校验动作（不得跳过）**：允许在它之前仅获取当前工程路径、双核上下文等必需的工程上下文；获取上下文后立即调用 `ide-check-before-debug`（异步 → 轮询），且必须先于定位 link.ld、规则1/2/3、内存分配和断点上限等校验。**工具返回"调试前检测失败" → 直接终止检查**，提示用户检测失败的原因（如与 Debug level 相关，可指引到『属性页 → Build Settings → Debugging → Debug level』修改后再编译，**推荐使用 default(-g)**）；**检测通过 → 才继续后续校验，且不输出"调试前检测成功/通过"提示**。
- **多区域合计**：link.ld 中 FLASH/RAM 可能有多行/多个区域（区域名以 FLASH/RAM 开头即归入同类），脚本会把同类全部 LENGTH 相加后再与上限比较。
- **mcu_isa.json**：脚本固定加载本技能目录的 `mcu_isa.json`（不接受路径参数）；不要使用工程里其他位置的 mcu_isa.json。
- **脚本退出码**：0 = PASS；1 = 存在 FAIL（规则1/规则2/断点上限）；2 = FATAL（文件/配置缺失、无法推断型号）。
- 规则3 的 ⚠ 提示**不影响脚本退出码**（脚本退出码仍由硬性检查决定），但 Agent 的整体流程状态必须为 `PENDING_CONFIRMATION`，直至用户确认并完成对应处理。
- 注意：修改文件必须使用`ide-edit`工具
