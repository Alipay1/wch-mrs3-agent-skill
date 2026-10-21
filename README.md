# WCH MounRiver Studio 3 Agent Skill

An Agent-facing package for WCH MounRiver Studio 3 on Windows, in three parts:
toolchain automation, the IDE's own tool surface called over MCP, and a byte-exact
mirror of the embedded agent's prompts and skills.

**Requirements:** Windows 10/11, PowerShell 5.1 or newer, and WCH MounRiver Studio 3
installed (developed against 1.80.2 / MRS 3.0.0, agent payload v1.10). No
administrator rights are needed: the scripts change only the current process
environment, and only on request the current user's `MRS3_HOME` and `PATH`.

```powershell
.\wch-mrs3.cmd -Action doctor -ProjectPath .   # one-shot environment check
```

| Piece | Needs MRS3 running? | Can touch hardware? |
|---|---|---|
| `doctor` / `configure` / `build` | no | no |
| `agent` / `mcp-tools` / `mcp` / `ide-task` / `ide-build` | yes | only if the tool you call does |
| `flash` / `build-flash` / `ide-download` | `flash`: no, `ide-download`: yes | yes |

## 1. Build and flash (bundled toolchain)

Discover MRS3, repair PATH, locate a `.wvproj` project and its generated makefile,
build with the matching bundled RISC-V GCC, and flash through the bundled WCH
OpenOCD.

- `scripts/wch-mrs3.ps1` — discovery, PATH configuration, build, flash, agent/IDE inspection.
- `wch-mrs3.cmd` — convenience Windows wrapper.

```powershell
.\wch-mrs3.cmd -Action doctor -ProjectPath .
.\wch-mrs3.cmd -Action configure -ProjectPath . -PersistUserPath
.\wch-mrs3.cmd -Action build -ProjectPath . -Clean
.\wch-mrs3.cmd -Action flash -ProjectPath .
.\wch-mrs3.cmd -Action build-flash -ProjectPath . -Clean
.\wch-mrs3.cmd -Action agent           # payload, engine, live ports, MCP tool count
```

The build stage requires an existing generated makefile or another project-provided
build backend. The script intentionally does not guess compiler and linker flags
from source files.

## 2. IDE tools over MCP

The running IDE serves its `ide-*` tool surface as an MCP server on loopback; its
address is read from `%USERPROFILE%\.config\opencode\mrs-serve-state.json`. No token
is required, the IDE must be running, and the tools act on the **active** project.

```powershell
.\wch-mrs3.cmd -Action mcp-tools                        # 72+ tools
.\wch-mrs3.cmd -Action mcp-tools -ShowSchema             # with input schemas
.\wch-mrs3.cmd -Action mcp -Tool ide-get-projectStructure
.\wch-mrs3.cmd -Action mcp -Tool ide-get-project-chipType `
               -ToolArguments '{"projectPath":"D:\\Work\\App"}'
.\wch-mrs3.cmd -Action ide-task -Tool ide-get-project-chipType -ToolArgumentsFile .\args.json
.\wch-mrs3.cmd -Action ide-build          # ide-build-project
.\wch-mrs3.cmd -Action ide-build -Clean   # ide-rebuild-project
.\wch-mrs3.cmd -Action ide-download       # ide-download-project (flashes hardware)
```

| Action | Calls | Notes |
|---|---|---|
| `mcp-tools` | `initialize` + `tools/list` | read-only inventory |
| `mcp` | `tools/call` | synchronous tools, any arguments |
| `ide-task` | `tools/call` + polling | asynchronous tools returning `task_*` |
| `ide-build` | `ide-build-project` / `ide-rebuild-project` | active project |
| `ide-download` | `ide-download-project` | active project's download configuration |

Asynchronous tools are handled end to end: the script extracts the `task_*` id from
the IDE's acknowledgement, polls `ide-get-task-status` until the status word is
terminal, prints the IDE's own result or failure log, and maps that to the exit code
(0 only for `success`). `-McpTimeoutSec` bounds the wait; `-ToolArgumentsFile` avoids
shell quoting problems for nested arguments.

Transport: `GET /sse`, POST to the `endpoint` URL it announces
(`/message?sessionId=…`), JSON-RPC 2.0, protocol `2024-11-05`. The separate engine
port requires a random per-session password and answers 401 without it, which is why
this skill talks to the MCP port.

> The MCP endpoint is unauthenticated and answers with
> `Access-Control-Allow-Origin: *`. It is loopback-only by design; keep it that way
> and do not leave it driving a shared machine unattended.

## 3. Embedded-agent knowledge (reverse-extracted)

MRS3 ships its own agent — an OpenCode build with a WCH prompt and eight skills —
as plain readable files inside the installation. That payload is mirrored here
byte-for-byte, so its domain knowledge is usable from any agent, and so upgrades
show up as a diff rather than as unexplained behaviour changes.

- `scripts/sync-mrs3-agent.ps1` — extract, snapshot, drift-check.
- `references/mrs3/` — byte-exact mirror (`AGENTS.md`, `opencode.json`, `mcp.json`,
  `skills/**`, `_variant/**`) plus `mrs3-manifest.json` with per-file SHA256.
- `references/mrs3-skill-catalog.md` — distilled prompts, skill catalog, IDE tool
  surface, runtime configuration.
- `references/mrs3-sync.md` — how to refresh the mirror when MRS3 updates.

```powershell
.\scripts\sync-mrs3-agent.ps1 -Action Check    # 0 = in sync, 2 = drift
.\scripts\sync-mrs3-agent.ps1 -Action Export -Force
.\scripts\sync-mrs3-agent.ps1 -Action List    # current skill catalog
```

Snapshot as of MRS3 3.0.0 / app 1.80.2, agent payload v1.10, OpenCode 1.3.14:
81 files, 8 skills.

## Contents

```text
SKILL.md                          decision rules and workflow
README.md
wch-mrs3.cmd                      Windows wrapper for the MRS3 script
scripts\wch-mrs3.ps1              toolchain automation + IDE tools over MCP
scripts\sync-mrs3-agent.ps1       MRS3 extraction / sync / drift check
references\mrs3-skill-catalog.md  distilled MRS3 knowledge
references\mrs3-sync.md           refresh methodology
references\mrs3\                  byte-exact MRS3 payload mirror + manifest
```

## Notes from field use

- Keep PowerShell automation scripts ASCII-only or UTF-8 with BOM for Windows
  PowerShell 5.1 compatibility. Mirrored Markdown is copied byte-for-byte and keeps
  its Chinese content; only the scripts need the ASCII discipline. That also means
  matching IDE prose has to go through code points, not literals.
- Generated make files hard-code a compiler name (`riscv-none-embed-gcc`,
  `riscv-wch-elf-gcc`, `riscv32-wch-elf-gcc`) that does not follow the project's
  toolchain selection, and they can retain absolute paths from where they were
  generated. The script puts every installed RISC-V toolchain on PATH; stale paths
  still have to be regenerated or mechanically migrated.
- In a hand-written makefile use `CC := <compiler>`, not `CC ?=`: GNU make
  predefines `CC=cc`, so `?=` keeps it and an unrelated `cc.exe` wins — on a machine
  with SEGGER Embedded Studio that fails as `error: no active license found`.
- MRS3's make runs commands through a POSIX shell; use `rm -f` in clean rules, not
  `del`.
- `.wvproj` is JSON (`flashConfig.address`, `flashConfig.target_path`); do not parse
  it as XML when looking for the flash address.
- `ide-get-projectToOperate` returns the active project path as a plain string on
  success and `{"success": false, ...}` when nothing is open — check that before
  assuming the build/download family has a target.
- For flash failures, confirm WCH-Link/CMSIS-DAP enumeration first, then run a
  minimal OpenOCD `init; targets; exit` test before blaming the firmware artifact.
- Never vendor `opencode.exe` (145 MB) or `%USERPROFILE%\.config\opencode\opencode.json`
  — the latter can contain a plaintext provider API key.

## Safety

- `flash` and `ide-download` reprogram real microcontrollers, and nothing here
  verifies that the artifact matches the connected chip beyond what OpenOCD and the
  IDE check themselves.
- The MCP tool server has no authentication and answers with
  `Access-Control-Allow-Origin: *`. It is bound to loopback by design: do not proxy
  or publish the port, and do not leave an agent driving it unattended.
- The scripts refuse to guess — no fabricated compiler flags, no BIN without an
  address, no silent choice between ambiguous artifacts, no "success" inferred from
  partial output.

## License and attribution

Original code and documentation are MIT licensed — see [LICENSE](LICENSE).
`references/mrs3/**` is a byte-exact mirror of files shipped inside MounRiver
Studio 3 and remains the property of WCH / MounRiver and the OpenCode project; see
[NOTICE.md](NOTICE.md) for details.

Not affiliated with, endorsed by, or supported by WCH or MounRiver.

