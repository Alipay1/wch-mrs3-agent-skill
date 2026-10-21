# MRS3 Built-in Agent — Prompt & Skill Catalog

Distilled index of what ships inside WCH MounRiver Studio 3's embedded agent.
Full verbatim sources sit next to this file under `references/mrs3/`.

| Fact | Value |
|---|---|
| MRS3 appVersion | 1.80.2 |
| MRS3 mrsVersion | 3.0.0 |
| WCH Agent variant | `default`, v1.10 |
| Agent engine | OpenCode (Bun-compiled `opencode.exe`, file version 1.3.14) |
| Payload files | 76 (+5 companion files) |
| Bundled skills | 8 |
| Snapshot | `references/mrs3/`, hashes in `mrs3-manifest.json` |

Source path inside the installation:

```text
<MRS3>\resources\app\resources\win32\components\WCH\Others\WCHAgent\default\
    opencode.exe                    OpenCode host binary (145 MB, never vendored)
    mrs-agent-todowrite-instructions.md
    opencode\AGENTS.md              global coding rules (the main prompt)
    opencode\opencode.json          provider / model / compaction / skills.paths
    opencode\mcp.json               MCP servers, injected via OPENCODE_CONFIG
    opencode\skills\<name>\         the 8 skills
    TempData\mrs-standard-config.json
```

---

## 1. Global rules (`AGENTS.md`)

The single most transferable asset. Ten rules, in WCH's own priority order:

1. **Plan before acting.** Any code generation/modification starts with a todo list.
   Todo status reflects real tool results — never claim completion early.
2. **Stay inside the target project.** Never search, scan or read anything outside
   the current project (no sibling projects, no historic projects, no local SDK
   samples). Use the template library instead. If the user asks to open files,
   they must name the directory; do not crawl the filesystem.
3. **Create the project before exploring it.** For a new project, create it first,
   then explore templates, then write code. `projectPath` is the *parent* directory
   and must not contain `projectName`. Never nest a project inside a project, never
   produce `Demo/Demo`.
4. **Template code library is the reference of record** — `chip_code_tree` →
   `chip_code_read` → land files with `chip_code_download`. Never read a whole
   template file and then hand-copy it with `write` to fake a download.
5. **Knowledge search is gated.** `chip_knowledge_search` is forbidden while
   actively writing code; pause the edit, search, then resume.
6. **File modification discipline** — new file: `write`. Existing file: `ide-edit`
   (the plain `edit` tool is disabled). Never overwrite an existing file with
   `write`, never bypass `ide-edit` with bash or scripts. Minimal diffs only.
7. **Missing files** — check the template library first; if absent, never search
   outside the project; tell the user which file is missing.
8. **Missing `.a`/`.lib`** — do not stop. Finish the code you can determine, compile,
   and let the real link result decide whether the missing library actually matters.
9. **Standard flow** — todo → target project → read code → template refs → optional
   knowledge search → implement → compile → flash (when supported) → report →
   hardware verification is the user's step.
10. **Report format** — 完成情况 / 代码改动 / 编译与烧录 / 待验证与遗留问题.

A managed `todowrite` contract is embedded at the end of `AGENTS.md` (markers
`MRS-TODOWRITE-INSTRUCTIONS:BEGIN/END`). Its hard requirements: send the **complete**
list every time, flip to `in_progress` *before* the first tool call of that item,
close each item immediately on completion, re-send for the last item too, advance at
most **one** item to `completed` per call, keep `content` byte-stable, use only
`pending` / `in_progress` / `completed` / `cancelled`.

---

## 2. Bundled skills

All eight follow the same shape: YAML front matter (`name`, `description`) plus a
`SKILL.md` body, and optionally `references/`, `scripts/`, `tests/`.
The `description` field doubles as the auto-trigger text — it is deliberately
keyword-dense in Chinese and English.

### Migration skills

| Skill | Trigger | What it guarantees |
|---|---|---|
| `mrs-stm32f1-to-ch32v20x-spl` | "STM32F103 → CH32V203/V20x", MDK/Keil SPL project conversion | Three-stage pipeline: project-level convert → peripheral-library symbol replacement → compile in MRS. Covers bare-address register access, Cortex-M3 bit-band → BSHR/BCR rewriting, USB layered migration, and 76 same-signature-different-behaviour functions |
| `mrs-ch32v003-to-ch32v002-005` | "CH32V003 → CH32V002/V005", "003转002" | Two-stage: MRS built-in `ide-create-project-byConvert` (plus two project properties: GCC15 toolchain, disable M multiply / enable ZMMUL), then code-level porting. Ships verified macro/function deltas from full EVT source scans: 183 V003-only macros, 23 V003-only functions, 402 target-only macros, 49 target-only functions, 98 same-name-different-value macros, 8 same-signature-changed-behaviour groups |

### Validation skills

| Skill | Trigger | Checks |
|---|---|---|
| `mrs-validate-march` | march / ISA extension / ABI / toolchain / startfile / `riscvTargetProcessor` validation | Compares project build properties against `mcu_isa.json`: `march` vs `cores[].isa_ext`, toolchain vs series `toolchain[]`, `abi` vs `cores[].mabi`, `startfile` vs `chips[].startfile[]` (advisory only) |
| `mrs-validate-linkld` | link.ld / linker script / Flash-RAM capacity / overflow / dual-core V3F-V5F | Offline linker-script validation against `mcu_isa.json`, including expression lengths, multi-region overflow, V5F scripts. Ships multi-language implementations (ps1/py/js/sh/bat) and 10 `.ld` fixtures |
| `mrs-debug-check` | Anything debug-related; must run **before** any debug operation | Blocking pre-debug gate: (a) pre-debug probe must pass, (b) Flash/RAM capacity vs project, (c) memory allocation support + actual values, (d) Flash origin non-zero → asks the user, (e) breakpoint ceiling. Rule and threshold data in `mcu_isa.json` |

### Workflow gates

| Skill | Trigger | Enforces |
|---|---|---|
| `mrs-code-check-fix` | Code/syntax/clang-tidy problems | First tool must be `ide-get-projectToOperate`; todo right after; clang-tidy **before** reading source; Warning analysed but **not** auto-fixed unless the user asks; Error fixes must not carry Warning changes; edits only via `ide-edit`; re-run clang-tidy after any edit; fixed report format as the final output |
| `mrs-prepare-verify` | Any code creation/modification that will later be verified with hardware | Plans "how the code is designed + how the effect is verified", presents it in a **single** dialog for user confirmation, then emits a hardware connection table (global conventions + text + diagram; pin-level, every connection listed) with network checks N1–N5 when Ethernet is involved. Code generation must not start before this passes |
| `mrs-external-tools` | Any tool question — list/available/how to use/path/install — and any verification or debug run | Queries the tool catalog via MRS IDE, installs on demand, then drives tools through the shipped pipe scripts (`mrs_pipe_host.ps1` + `mrs_pipe_send.ps1`). Forbids inventing tool names, IDs, paths or parameters. Shares the C1–C4 scene/hardware checks with `mrs-prepare-verify` |

### Transferable hard rules from the migration skills

These are the silent-failure traps — the compiler does not warn about any of them:

- **Flash erase granularity.** STM32's 1 KB page boundary does not exist on CH32.
  Replace `FLASH_ErasePage` with "align down to 1 KB + 4 × `FLASH_ErasePage_Fast`".
  Erase goes Fast; **programming must not** — `FLASH_ProgramPage_Fast` is a 256 B
  whole-page commit with no half-word interface. `FLASH_Lock_Fast` and `FLASH_Lock`
  are two different locks and must be paired in separate, non-overlapping regions.
- **Core clock.** Match HCLK (`SystemCoreClock`), not SYSCLK. For a 72 MHz source,
  pick CH32's 144 MHz HSE profile + `RCC_HPRE_DIV2` so HCLK stays 72 MHz with zero
  peripheral-clock recalculation. `SystemInit()` does **not** call
  `SystemCoreClockUpdate()` — do it manually. With USB, the clock is constrained to
  48 / 96 / 144 MHz; a 72 MHz profile silently leaves the USB divider unconfigured.
- **Delays.** The ST SPL has no delay functions at all. Split by original form:
  busy-loop style → `__NOP()` busy wait calibrated on hardware (coupled to `-Os`);
  SysTick style → CH32 `Delay_Us`/`Delay_Ms` (unit is **10 ms**, so multiply by 10)
  after `SystemCoreClockUpdate()`.
- **printf float.** MRS disables float formatting by default (linker option
  `Use wchprintfloat(-lprintfloat)`). `%f`/`%e`/`%g` compile and link fine and then
  print nothing at runtime.
- **GPIO remap, OPA struct, DBGMCU chip ID, core_riscv WFE / `.highcode`** differ
  between V003 and V002/V005 despite identical names.

---

## 3. MRS IDE tool surface

The prompt and skills reference these IDE-hosted tools. They are implemented in
the extension host, so they act on the IDE's active window and active project and
exist only while MRS3 runs. They are nevertheless reachable from a plain local
process: the extension serves them as an MCP server over SSE on the port recorded
as `mcpPort`, where `GET /health` answers unauthenticated with the complete tool
list and `GET /sse` + `POST /message?sessionId=` speak protocol 2024-11-05.
Observed tool count on 1.80.2: 72–76. That surface includes `ide-build-project`,
`ide-rebuild-project`, `ide-download-project`, `ide-convert-keil-project` and the
whole debug family — which is how MRS3 can build and download without any
externally resolved toolchain.

| Tool | Purpose |
|---|---|
| `ide-get-projectToOperate` | Get the active project (always the first call in project workflows) |
| `ide-get-project-chipType` | Current project's chip type |
| `ide-edit` | The only sanctioned way to modify an existing file |
| `ide-create-project-byConvert` | Project-level chip conversion from a template |
| `ide-get-installed-toolchain` | Installed toolchains |
| `ide-get-project-build-property` / `ide-set-project-build-property` | Read/write march, ABI, toolchain, startfile, linker options |
| `ide-get-project-linker-scripts` | Linker scripts of the project |
| `ide-get-project-problems-by-clang-tidy` | clang-tidy diagnostics |
| `ide-build-project` / `ide-rebuild-project` / `ide-build-all` | Project build through the IDE's own configuration |
| `ide-download-project` | Flash through the IDE's download settings |
| `ide-check-before-debug` | Pre-debug gate |
| `ide-debug-support-memory-allocation` / `ide-debug-read-memory-allocation` | RAM/Flash allocation probing |
| `ide-get-task-status` | Async task result polling |
| `ide-decorate-diffs` | Decorations (explicitly not called by `mrs-code-check-fix`) |
| `ide-get-external-toolList-description` / `ide-install-external-tool` | Tool catalog and installation |
| `chip_code_tree` / `chip_code_read` / `chip_code_download` | Template code library navigation, reading, landing |
| `chip_knowledge_search` | Chip knowledge base |

Plus the OpenCode built-ins: `read`, `write`, `glob`, `grep`, `bash`, `todowrite`,
`webfetch`, `task`, `patch`, `edit` (disabled by `AGENTS.md`).

> The transport facts above come from the extension bundle and a live probe, not
> from the mirrored payload; the tool names themselves do appear in the payload.

---

## 4. Runtime configuration

`opencode/opencode.json` (the bundled default):

```json
{
  "share": "disabled",
  "provider": {
    "default": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "deepseek",
      "options": {
        "baseURL": "https://llm.mounriver.com/v1",
        "apiKey": "{env:MRS_AGENT_API_KEY}"
      },
      "models": { "deepseek-flash": { "limit": { "context": 524288, "output": 131072 } } }
    }
  },
  "model": "default/deepseek-flash",
  "compaction": { "auto": true, "prune": true, "reserved": 131072, "tail_turns": 3, "preserve_recent_tokens": 10240 },
  "skills": { "paths": ["<user>/.config/opencode/skills"] }
}
```

`opencode/mcp.json`, injected as `OPENCODE_CONFIG`:

```json
{ "mcp": { "mrs-ai-meter": { "type": "remote", "url": "http://127.0.0.1:3182/mcp", "enabled": true, "oauth": false } } }
```

The extension also manages a local `mrs-ide-tools` MCP server and registers it with
the engine through the engine's own MCP API; both names are whitelisted in the
extension bundle. The engine itself is started as
`opencode.exe serve --hostname 127.0.0.1 --port <n>`, and the password below is
generated per session with `randomBytes(32)`.

Environment variables the host sets when spawning the agent (useful when
diagnosing behaviour):

```text
XDG_CONFIG_HOME              redirected into MRS3's own data dir
OPENCODE_CONFIG              <agent>\opencode\mcp.json
OPENCODE_SERVER_PASSWORD     random per-session, memory only
OPENCODE_DISABLE_AUTOUPDATE  =1
OPENCODE_DISABLE_MODELS_FETCH=1
OPENCODE_DISABLE_SHARE       =1
OPENCODE_DISABLE_LSP_DOWNLOAD
OPENCODE_DISABLE_PROJECT_CONFIG
MRS_AGENT_API_KEY            model gateway credential from the MRS account
MRS_MODEL_AUTH_*             request-signing knobs
OPENCODE_KNOWLEDGE_BASE_*    knowledge base endpoint / key
```

Runtime state lives in `%USERPROFILE%\.config\opencode\`:
`opencode.json` (user override), `mrs-serve-state.json` (pid, `port`, `mcpPort`,
`startedAt`, `apiKeyFp`, `gatewayBaseUrl`, `modelAuthUrl`, `serverPassword`),
`chat-activity\<window>.json`, `mcp-bind\<key>.<window>.json`, `skills\`.

Reading `mrs-serve-state.json` is the cheapest way to learn where the live agent is:
`scripts/wch-mrs3.ps1 -Action agent` does exactly that, then probes `/health` on
`mcpPort` and the raw TCP state of `port` without ever sending a model request.

> That user config can contain a plaintext provider API key. **Never vendor it.**
> `sync-mrs3-agent.ps1` deliberately reads only the installation payload.

---

## 5. How this catalog stays honest

`references/mrs3/` is a payload mirror (profile path sanitized to `<user>`) with per-file SHA256 in
`mrs3-manifest.json`. If WCH ships a new agent, `-Action Check` reports exactly
which files moved. See `mrs3-sync.md` for the refresh procedure.
