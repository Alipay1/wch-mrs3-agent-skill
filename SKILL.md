---
name: wch-mrs3-automation
description: WCH MounRiver Studio 3 automation and embedded-agent knowledge on Windows. Covers (a) MRS3 build and flash through its bundled RISC-V GCC, GNU make and WCH OpenOCD, (b) the IDE's own tool surface — build, rebuild, download, build properties, linker scripts, clang-tidy, debug gates — invoked from an external agent over the local MCP endpoint the running IDE serves, and (c) the built-in WCH Agent (OpenCode-based) whose prompts, skills and tool inventory are extracted and mirrored here, including CH32/STM32 migration rules, link.ld and march validation, and debug pre-checks. Use for CH32 RISC-V build, clean, flash, build-and-flash, MRS3 PATH diagnosis, calling MRS3 IDE tools over MCP, agent-driven iteration, MRS3 agent prompt or skill extraction, chip migration, or firmware validation.
---

# WCH MounRiver Studio 3 Agent Skill

MRS3 exposes three capability layers. This skill automates the first two and
mirrors the third:

| Layer | What it is | How you drive it |
|---|---|---|
| **Toolchain CLI** | Bundled RISC-V GCC, GNU make, WCH OpenOCD | `scripts/wch-mrs3.ps1 -Action doctor / configure / build / flash / build-flash` |
| **IDE tool surface** | 72+ `ide-*` tools implemented in the IDE extension | same script: `mcp-tools`, `mcp`, `ide-task`, `ide-build`, `ide-download` |
| **Agent knowledge** | WCH Agent prompt, 8 skills, runtime config | `references/mrs3/` mirror + `references/mrs3-skill-catalog.md` |

Rule of thumb: **build and flash through the bundled toolchain when the IDE is
closed or the generated makefile is complete; go through the IDE tools when the
action needs the IDE's own project model (project conversion, build properties,
linker scripts, clang-tidy, debug gates, download configuration). Mine
`references/mrs3/` for domain knowledge before touching any WCH flash, clock or
delay code.**

---

## Operating constraints

- Windows PowerShell 5.1 or newer. MRS3 is Windows-only here.
- Keep executable PowerShell scripts ASCII-only unless saved as UTF-8 with BOM.
  Windows PowerShell 5.1 may parse UTF-8-without-BOM scripts through the active
  ANSI code page, turning non-ASCII literals into syntax errors before the script
  runs. (Mirrored Markdown keeps its Chinese content; the only substitution is the local profile path, rewritten to `<user>`.)
- Modify only the current process environment by default. Persist only the current
  user's `MRS3_HOME` and `PATH`. Never touch machine-wide PATH and never request
  administrator rights merely to configure MRS3.
- Prefer ELF or HEX for download. Both carry addresses; raw BIN needs an explicit or
  reliably extracted flash address.
- Never download when project selection, firmware selection, or a raw BIN address
  is ambiguous.
- Do not reconstruct compiler/linker flags by guessing from source files. A normal
  MRS3 build requires a generated makefile or a project-provided build script.
- IDE actions act on the project the IDE has **active**. Do not pass a different
  path and assume the IDE will switch; open or focus the project in MRS3 first.
- The IDE tool endpoint is authenticated only by being bound to loopback: it accepts
  unauthenticated MCP calls and answers with `Access-Control-Allow-Origin: *`. Keep
  it on `127.0.0.1`, never publish the port, and do not leave long unattended
  sessions running against a machine other people can use.

---

## Part 1 — MRS3 automation

Use `scripts/wch-mrs3.ps1` as the single source of truth. Do not invent MRS3 paths,
compiler prefixes, OpenOCD paths, build directories, firmware names, or flash
addresses.

Resolve the directory containing this `SKILL.md`, then:

```powershell
$Mrs3 = Join-Path $SkillDirectory 'scripts\wch-mrs3.ps1'
```

When the host does not expose `$SkillDirectory`, locate `wch-mrs3.ps1` relative to
this file. `wch-mrs3.cmd` is the same thing for shells that prefer a `.cmd` entry.

### 1.1 Diagnose and discover

Run before modifying files or invoking the compiler:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $Mrs3 `
  -Action doctor `
  -ProjectPath .
```

Search order for the install: explicit `-Mrs3Root` → `MRS3_HOME` and related
environment variables → existing PATH entries and their parent directories → Windows
uninstall registry entries → common WCH/MounRiver install directories on local
drives.

It validates the MRS3 executable, `product.json` versions, the RISC-V toolchain,
GNU make, the OpenOCD executable and `wch-riscv.cfg`, then reports the project, its
chip type, the agent payload, the live agent ports and the IDE tool count.
`-NoProbe` skips the network probes.

### 1.2 Configure the environment

Current process only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $Mrs3 `
  -Action configure `
  -ProjectPath .
```

Persist the current user's PATH for future sessions:

```powershell
... -Action configure -ProjectPath . -PersistUserPath
```

Both put every installed RISC-V toolchain `bin`, the make directory and the OpenOCD
directory on PATH, selected toolchain first. The persist path additionally sets
`MRS3_HOME` and the PATH entries for the current user.

### 1.3 Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $Mrs3 `
  -Action build `
  -ProjectPath .
```

Add `-Clean` for a clean build, `-Jobs N` to bound parallelism. The script:

- locates the `.wvproj` project and reads its `component_toolchain`;
- prepends the matching MRS3 GCC `bin` to process PATH;
- locates a generated makefile, preferring the project's `flashConfig.target_path`
  directory, then `obj`, `Debug`, `Release`, `build`;
- invokes MRS3's bundled `make.exe` and propagates its exit code;
- reports generated ELF / HEX / BIN artifacts.

With no makefile, look for a documented `build.ps1`, `build.cmd`, CMake preset or
other project-provided entrypoint. If none exists, report that MRS3 build files have
not been generated yet. Do not fabricate a build command.

### 1.4 Download

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $Mrs3 `
  -Action flash `
  -ProjectPath .
```

Exact artifact, or raw BIN with an address:

```powershell
... -Action flash -ProjectPath . -Artifact '.\obj\firmware.elf'
... -Action flash -ProjectPath . -Artifact '.\obj\firmware.bin' -FlashAddress 0x00000000
```

The script runs the MRS3-bundled OpenOCD with the bundled `wch-riscv.cfg` and does
`program`, `verify`, `reset`, `exit`. When `flashConfig.target_path` exists it is the
preferred artifact; otherwise the newest ELF, then HEX, then BIN is used, and an
ambiguous tie is refused rather than guessed.

When OpenOCD prints `Ready for Remote Connections` then exits or crashes before
programming, separate tool invocation from probe/target connection:

```powershell
Get-PnpDevice -PresentOnly |
  Where-Object { $_.FriendlyName -match 'WCH|WCH-Link|CMSIS-DAP' -or $_.InstanceId -match 'VID_1A86' } |
  Select-Object Status,Class,FriendlyName,InstanceId

& $OpenOcdExe -f $OpenOcdConfig -c 'init; targets; exit'
& $OpenOcdExe -d3 -f $OpenOcdConfig -c 'init; targets; exit'
```

A healthy connection shows WCH-LinkE mode/version, `wlink_init ok`, the examined
RISC-V core, programming finished, verify OK, and target reset. If the probe
enumerates but `init` does not examine the target, ask the user to check WCH-Link
mode, target power, wiring, reset/boot state, and whether another process owns the
probe before retrying the same command.

### 1.5 Build and download

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $Mrs3 `
  -Action build-flash `
  -ProjectPath . `
  -Clean
```

Stop immediately if compilation fails. Never flash an artifact left over from an
earlier failed build.

### 1.6 Explicit disambiguation

```powershell
-Mrs3Root 'D:\MounRiver\MounRiver_Studio3'
-ProjectPath 'D:\Work\CH32V203_App\App.wvproj'
-BuildDir 'D:\Work\CH32V203_App\obj'
-Artifact 'D:\Work\CH32V203_App\obj\App.elf'
-FlashAddress 0x00000000
-OpenOcdConfig 'D:\custom\target.cfg'
-Jobs 12
```

### 1.7 Iteration policy

1. Run `doctor` once per session.
2. Build after each coherent patch.
3. Parse the first compiler or linker error, fix the root cause, rebuild.
4. Flash only after a successful build from the current source state.
5. Preserve full compiler and OpenOCD output in the task log.
6. Treat nonzero exit codes as failure; never infer success from partial output.
7. For anything involving more than a couple of steps, keep a todo list and update
   it as work actually lands — MRS3 enforces this on its own agent, and the same
   discipline keeps an external agent honest.

### 1.8 The IDE tool surface over MCP

The IDE runs its agent as a headless server and serves its own tool surface as an
MCP server on loopback. `%USERPROFILE%\.config\opencode\mrs-serve-state.json` carries
`port` (engine) and `mcpPort` (tool server); the script reads it, so nothing has to
be discovered by scanning ports.

```powershell
& $Mrs3 -Action mcp-tools                     # list all ide-* tools
& $Mrs3 -Action mcp-tools -ShowSchema          # ... with input schemas
& $Mrs3 -Action mcp     -Tool ide-get-projectStructure
& $Mrs3 -Action mcp     -Tool ide-get-project-chipType `
                        -ToolArguments '{"projectPath":"D:\\Work\\App"}'
& $Mrs3 -Action ide-task -Tool ide-get-project-chipType -ToolArgumentsFile .\args.json
& $Mrs3 -Action ide-build                      # ide-build-project on the active project
& $Mrs3 -Action ide-build -Clean               # ide-rebuild-project instead
& $Mrs3 -Action ide-download                   # ide-download-project (flashes hardware)
```

| Action | Calls | Notes |
|---|---|---|
| `mcp-tools` | `initialize` + `tools/list` | read-only inventory; `-ShowSchema` for argument schemas |
| `mcp` | `tools/call` | any tool, any arguments; synchronous tools |
| `ide-task` | `tools/call` + polling | asynchronous tools that return a `task_*` id |
| `ide-build` | `ide-build-project` / `ide-rebuild-project` | the active project; `-Clean` picks rebuild |
| `ide-download` | `ide-download-project` | flashes the active project's download configuration |

Asynchronous contract, which the script implements rather than leaving to the caller:

1. Submit the tool. The IDE answers with a prose acknowledgement containing
   `task_<tool>_<timestamp>_<hex>`.
2. Poll `ide-get-task-status` with `{"taskId":"..."}` until the report's status word
   is terminal (`success`, `failed`, `error`, `cancelled`, `aborted`, `timeout`).
3. On `success`, print the IDE's own result block and exit 0. On any failure status,
   print the IDE's log lines and exit 1. On timeout, exit 1 with the last status.

Tool conventions worth knowing before writing a call:

- `ide-get-projectToOperate` returns the **active project path as a plain string** on
  success, and `{"success": false, "error": ...}` when no project is open. The script
  turns the latter into a clear "open the project in MRS3 first" failure.
- Several tools require `projectPath` (`ide-get-project-chipType`,
  `ide-get-project-basic-property`, …), while the build/download family takes no
  arguments and uses the active project.
- Results are either plain text or JSON. Application-level failures arrive as
  `{"success": false, ...}`, which the script treats as a failure even though MCP
  itself reported no protocol error.
- Use `-ToolArgumentsFile` for nested or quote-heavy arguments instead of fighting
  shell escaping.

Transport, for when something breaks: `GET /sse` opens the event stream and its first
`endpoint` event yields the POST URL; JSON-RPC requests go to
`POST /message?sessionId=<id>` and their responses come back on the stream. Protocol
`2024-11-05`. The engine port (`port`) is a different service and requires the
per-session `OPENCODE_SERVER_PASSWORD`, so it answers 401 without it — that is why
this skill talks to `mcpPort`, not to the engine API.

### 1.9 Traps in this layout

- **Generated makefiles hard-code a compiler name and absolute paths.** A file
  generated in another workspace can say `riscv32-wch-elf-gcc -I"d:/WorkSpace/old_project/..."`.
  The compiler name does not follow the project's toolchain selection, and the
  include paths point at where the project used to live. The script therefore puts
  **every installed RISC-V toolchain `bin` on PATH**, selected one first, so those
  names resolve; the stale paths still have to be regenerated in the IDE or
  mechanically migrated (never hand-edit flag by flag).
- **`CC ?=` does not select a compiler.** GNU make predefines `CC=cc`, so `?=` keeps
  it, and whichever `cc.exe` is first on PATH wins — on a machine with SEGGER
  Embedded Studio installed that is a licensed compiler that fails with
  `error: no active license found`. A hand-written makefile must use `CC :=`.
- **`.wvproj` is JSON, not XML.** `flashConfig.address` (e.g. `0x08000000`) and
  `flashConfig.target_path` (e.g. `obj/app.hex`) are the authoritative flash
  settings; the script uses `target_path` as the preferred artifact and as the
  build-directory hint. `0x08000000` is normalized to `0x00000000` for the probe.
- **make runs under a POSIX shell.** Clean rules in hand-written makefiles must use
  `rm -f`, not `del`.

---

## Part 2 — MRS3 embedded agent

MRS3 is a VS Code-derived IDE with a built-in agent ("WCH Agent", variant `default`,
payload v1.10) running OpenCode on a DeepSeek gateway. Its entire prompt and skill
set ships as **plain readable files**:

```text
<MRS3>\resources\app\resources\win32\components\WCH\Others\WCHAgent\default\opencode\
    AGENTS.md        global coding rules (the main prompt)
    opencode.json    provider / model / compaction / skills.paths
    mcp.json         MCP servers (injected via OPENCODE_CONFIG)
    skills\<name>\   eight skills, each with references and scripts
```

The extension spawns the agent as a headless server —
`opencode.exe serve --hostname 127.0.0.1 --port <n>` — and records the pid, engine
port and MCP port in `mrs-serve-state.json`. Part 1.8 uses that record; this part is
about what the agent knows, not how to call it.

A mirror lives in `references/mrs3/` — byte-exact apart from the local profile path, which is rewritten to `<user>` — hashed in
`references/mrs3/mrs3-manifest.json`. Read it directly when you need the exact
wording; use `references/mrs3-skill-catalog.md` for the distilled index.
`scripts/wch-mrs3.ps1 -Action agent` reports the payload, engine version and live
ports without sending a model request.

### 2.1 Global rules worth adopting from `AGENTS.md`

WCH's own agent is held to ten rules. The ones that transfer to any agent working
on a WCH project:

- **Plan first.** Create a todo list before code generation or modification, and
  never mark work complete ahead of the real tool result.
- **Stay inside the target project.** Do not search, scan or read anything outside
  it — no sibling projects, no historic projects, no local SDK samples. Use the
  template library instead. If the user wants files opened, they must name the
  directory.
- **Create a project before exploring it.** For new projects the create step comes
  first; `projectPath` is the parent directory and must not contain `projectName`.
  Never nest a project inside a project.
- **Templates are the reference of record.** `chip_code_tree` → `chip_code_read` →
  land with `chip_code_download`. Never read a whole template file and hand-copy it
  with `write`.
- **Do not fake a knowledge search mid-edit.** Pause the code edit, search, resume.
- **Minimal diffs.** New files via `write`; existing files through the IDE edit
  path. Never overwrite an existing file with `write`, never bypass the edit tool
  with scripts.
- **Missing `.a` / `.lib` is not a stop sign.** Finish what is determinable, compile,
  and let the real link result decide.
- **Report in four parts:** completion status, code changes, build/flash result,
  open items needing user verification.

### 2.2 Skill catalog

Eight skills ship with MRS3. Trigger text is quoted from each `description:` field —
those keywords are what make MRS3 auto-select them, so they are also the best guide
for when an external agent should follow the same procedure.

| Skill | Use when | Core value |
|---|---|---|
| `mrs-stm32f1-to-ch32v20x-spl` | STM32F103 / MDK SPL → CH32V203 / V20x | Project convert → symbol replacement → compile; bare-address access, bit-band → BSHR/BCR, USB layered migration, 76 behaviour-changed functions |
| `mrs-ch32v003-to-ch32v002-005` | CH32V003 → CH32V002 / CH32V005 | `ide-create-project-byConvert` + two build properties (GCC15, ZMMUL), then code porting with verified macro/function deltas |
| `mrs-validate-march` | march / ISA / ABI / toolchain / startfile validation | Compares build properties against `mcu_isa.json` |
| `mrs-validate-linkld` | link.ld / Flash-RAM capacity / overflow / V5F | Offline linker-script validation with `.ld` fixtures |
| `mrs-debug-check` | **Any** debug operation, first | Blocking pre-debug gate: capacity, memory allocation, Flash origin, breakpoint ceiling |
| `mrs-code-check-fix` | Code, syntax or clang-tidy problems | `ide-get-projectToOperate` first, clang-tidy before reading source, Warnings analysed not auto-fixed, `ide-edit` only, re-check after edits |
| `mrs-prepare-verify` | Any codegen that will be hardware-verified | Verification plan + single confirmation dialog + pin-level hardware connection table before code generation |
| `mrs-external-tools` | Any tool question, and any verification run | Queries/installs MRS tools, drives them through the shipped pipe scripts; forbids inventing tool names, IDs or paths |

The migration skills carry the highest-value, hardest-won content — silent-failure
traps the compiler never reports: Flash erase granularity (`FLASH_ErasePage` must
become align-1KB + 4× Fast erase), HCLK vs SYSCLK and the USB 48/96/144 MHz
constraint, ST SPL having no delay functions at all (and CH32's `Delay_*` unit being
10 ms), and `printf` float formatting being off by default in MRS projects.
Read the catalog before touching any WCH flash, clock or delay code.

### 2.3 IDE-hosted capabilities

These tools are implemented inside MRS3's IDE host, so they act on the IDE's current
window and current project and exist only while MRS3 runs. Part 1.8 calls them over
MCP; the list below is the inventory worth routing to the IDE instead of emulating by
editing files:

`ide-get-root-type`, `ide-get-projectToOperate`, `ide-get-project-chipType`, `ide-edit`,
`ide-create-project-byConvert`, `ide-get-installed-toolchain`,
`ide-get-project-build-property` / `ide-set-project-build-property`,
`ide-get-project-linker-scripts`, `ide-get-project-problems-by-clang-tidy`,
`ide-build-project` / `ide-rebuild-project` / `ide-build-all`, `ide-download-project`,
`ide-check-before-debug`, `ide-debug-support-memory-allocation` /
`ide-debug-read-memory-allocation`, `ide-get-task-status`, `ide-decorate-diffs`,
`ide-get-external-toolList-description`, `ide-install-external-tool`,
`chip_code_tree`, `chip_code_read`, `chip_code_download`, `chip_knowledge_search`.

### 2.4 Runtime facts

- Model gateway `https://llm.mounriver.com/v1`, model `deepseek-flash`,
  524288 context / 131072 output, auto-compaction with 3 tail turns preserved.
  Requests are signed locally through `modelAuthUrl`
  (`http://127.0.0.1:4420/internal/opencode/model-request-auth`) while the IDE runs.
- MCP: `mrs-ai-meter` (remote, `http://127.0.0.1:3182/mcp`) plus the local
  `mrs-ide-tools` server the extension hosts on `mcpPort`. 72–76 tools observed on
  1.80.2, protocol `2024-11-05`, SSE transport.
- Host-set environment: `XDG_CONFIG_HOME` (redirected), `OPENCODE_CONFIG`
  (→ `mcp.json`), `OPENCODE_SERVER_PASSWORD` (random per session),
  `OPENCODE_DISABLE_AUTOUPDATE` / `_MODELS_FETCH` / `_SHARE`, `MRS_AGENT_API_KEY`.
- User state: `%USERPROFILE%\.config\opencode\` — `opencode.json` override,
  `mrs-serve-state.json` (pid, engine `port`, `mcpPort`, `gatewayBaseUrl`,
  `modelAuthUrl`, `apiKeyFp`), `chat-activity\`, `mcp-bind\`.

---

## Part 3 — Refreshing the MRS3 mirror

WCH replaces the whole payload on upgrade with no migration notice, and its release
cadence is unknown. `scripts/sync-mrs3-agent.ps1` makes that a diff instead of a
re-investigation:

```powershell
$Sync = Join-Path $SkillDirectory 'scripts\sync-mrs3-agent.ps1'

& $Sync -Action Check      # exit 0 = in sync, 2 = drift, 1 = error
& $Sync -Action Export -Force
& $Sync -Action List       # print the current skill catalog
```

`-Action Check` compares MRS3 appVersion, WCH Agent version, the `opencode.exe`
hash, and every mirrored file's SHA256. After exporting, review the diff, then
update `references/mrs3-skill-catalog.md` — and this file if a rule or capability
changed. Never hand-edit `references/mrs3/` itself; the hashes would stop meaning
anything.

Full procedure, layout-change fallbacks, and pre-commit checks: `mrs3-sync.md`.

---

## References

- [scripts/wch-mrs3.ps1](scripts/wch-mrs3.ps1) — toolchain automation and IDE tool calls over MCP.
- [MRS3 skill catalog](references/mrs3-skill-catalog.md) — distilled prompts, the 8 skills, IDE tool surface, runtime config.
- [MRS3 sync methodology](references/mrs3-sync.md) — payload anatomy, drift procedure, recovery when the layout changes.
- `references/mrs3/` — payload mirror (profile path sanitized to `<user>`): `AGENTS.md`, `opencode.json`, `mcp.json`, `skills/**`, `_variant/**`.
- `references/mrs3/mrs3-manifest.json` — version stamps and per-file SHA256.
