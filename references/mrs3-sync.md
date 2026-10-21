# Keeping the MRS3 Mirror Current

MRS3's agent is not a black box. It ships as a plain directory tree of Markdown
prompts, JSON config and skill folders, so the honest way to track it is a
**byte-exact mirror plus a hash baseline** — not re-reading minified JavaScript
every release.

Everything below is implemented by `scripts/sync-mrs3-agent.ps1`.

---

## 1. What is mirrored, and what is deliberately not

| Mirrored | Why |
|---|---|
| `opencode\AGENTS.md` | The global prompt — the highest-value asset |
| `opencode\opencode.json`, `mcp.json` | Provider, model, compaction, MCP wiring |
| `opencode\skills\**` | All 8 skills, with references, scripts and test fixtures |
| `_variant\mrs-agent-todowrite-instructions.md` | The task-list contract |
| `_variant\TempData\mrs-standard-config.json` | WCH's default config template |

| Never mirrored | Why |
|---|---|
| `opencode.exe` | 145 MB; only its file version and SHA256 go in the manifest |
| `%USERPROFILE%\.config\opencode\opencode.json` | User override, may contain a **plaintext API key** |
| `node_modules\` | Irrelevant to prompt content |

Vendored files must stay **byte-exact**. Do not hand-edit anything under
`references/mrs3/` — the manifest hashes would stop meaning anything. All
interpretation belongs in `mrs3-skill-catalog.md`.

---

## 2. Where the payload lives

Current layout (MRS3 3.0.0 / app 1.80.2):

```text
C:\MounRiver\MounRiver_Studio3\
  resources\app\product.json                                  <- appVersion, mrsVersion
  resources\app\resources\win32\components\WCH\Others\
    WCHAgent\
      sub_manifest.json                                       <- variant list + version
      default\
        opencode.exe                                          <- engine version
        opencode\AGENTS.md
        opencode\opencode.json
        opencode\mcp.json
        opencode\skills\<skill>\SKILL.md
        TempData\
```

Three independent version stamps let you tell *what* changed:

| Stamp | File | Current |
|---|---|---|
| MRS3 release | `resources\app\product.json` → `version`, `mrsVersion` | 1.80.2 / 3.0.0 |
| Agent payload | `WCHAgent\sub_manifest.json` → `details[].version` | v1.10 |
| Agent engine | `opencode.exe` → `VersionInfo.FileVersion`, SHA256 | 1.3.14 |

---

## 3. Refresh procedure after an MRS3 update

```powershell
$S = '.\scripts\sync-mrs3-agent.ps1'

# 1. Did anything move? This already lists added / modified / removed files.
& $S -Action Check            # exit 0 = in sync, 2 = drift, 1 = error

# 2. Keep the old snapshot if this folder is not under version control
#    (-Action Export -Force replaces it)
Copy-Item .\references\mrs3 .\references\mrs3.prev -Recurse -Force

# 3. Re-snapshot (prunes files WCH removed)
& $S -Action Export -Force

# 4. Read the delta — with git
git diff --stat -- references/mrs3
git diff -- references/mrs3/AGENTS.md references/mrs3/opencode.json
```

Without git, diff the two snapshots directly:

```powershell
$a = Get-ChildItem .\references\mrs3.prev -Recurse -File | ForEach-Object {
       [pscustomobject]@{ p = $_.FullName.Replace((Resolve-Path .\references\mrs3.prev).Path,''); h = (Get-FileHash $_.FullName).Hash } }
$b = Get-ChildItem .\references\mrs3 -Recurse -File | ForEach-Object {
       [pscustomobject]@{ p = $_.FullName.Replace((Resolve-Path .\references\mrs3).Path,''); h = (Get-FileHash $_.FullName).Hash } }
Compare-Object $a $b -Property p,h
Remove-Item .\references\mrs3.prev -Recurse -Force   # once satisfied
```

Then, in order:

1. **`AGENTS.md` changed** — this is a behaviour change for every MRS3 session.
   Update §1 of `mrs3-skill-catalog.md` and, if the rule is generally useful,
   the operating constraints in `SKILL.md`.
2. **A `skills\` folder was added/removed/renamed** — extend or prune the catalog
   tables. New skill means a new capability worth surfacing.
3. **A `description:` changed** — that is *trigger* drift, not cosmetic. The
   description is what makes MRS3 auto-select the skill, so the catalog's
   "Trigger" column must follow it.
4. **`opencode.json` changed** — check provider, model, context/output limits,
   `compaction`, `skills.paths`. A model swap changes the practical context budget.
5. **`mcp.json` changed** — a new MCP server means new tool families.
6. **`ide-*` / `chip_*` names changed** — re-run the tool inventory (below) and
   update §3 of the catalog.
7. `-Action Check` must return 0 again. Commit the snapshot, the manifest and the
   catalog in one change so the baseline never lags the prose.

Tool inventory one-liner (finds every IDE tool name referenced by any skill):

```powershell
Get-ChildItem 'references\mrs3' -Recurse -Filter *.md |
  Select-String -Pattern '\b(ide-[A-Za-z][\w-]*|chip_\w+)\b' -AllMatches |
  ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
```

---

## 4. If the layout itself changes

`sync-mrs3-agent.ps1` already degrades in stages, so try it first:

1. **Known paths** — probes
   `<root>\resources\app\resources\win32\components\WCH\Others\WCHAgent`,
   `<root>\resources\win32\...`, `<root>\components\WCH\Others\WCHAgent`.
2. **Bounded search** — walks `<root>\resources` (depth 8) looking for a directory
   named `WCHAgent`, then picks the first variant containing `opencode\AGENTS.md`
   or `opencode\opencode.json`.
3. **Explicit override** — `-Mrs3Root 'D:\Other\MounRiver_Studio3'`, or set
   `MRS3_HOME`.

If the *internal* names changed as well, recover the new contract from the
extension bundle. It is minified but its string literals are intact:

```powershell
$js = 'C:\MounRiver\MounRiver_Studio3\resources\app\extensions\mrs-team.mrs-vscode\out\extension.js'
$t  = [IO.File]::ReadAllText($js)

# Env vars the host sets when spawning the agent
[regex]::Matches($t,'\b(OPENCODE|MRS|WCH)_[A-Z0-9_]{3,}\b') |
  ForEach-Object Value | Sort-Object -Unique

# Payload path resolution / config injection
$t.Substring($t.IndexOf('OPENCODE_CONFIG')-500, 900)
```

Note `Get-Content`/`Select-String` on this 4 MB single-line bundle is slow and can
hit regex limits; `[IO.File]::ReadAllText` plus explicit `Substring` is reliable.

Runtime confirmation, when the app is open: the extension logs `[OpenCode]` lines
to `%APPDATA%\MounRiver Studio 3\logs\<session>\window*\exthost\` — including the
resolved `OPENCODE_CONFIG` path and whether the todowrite block reached the model.
`%USERPROFILE%\.config\opencode\mrs-serve-state.json` records the live pid, ports
and gateway URL.

---

## 5. Checks worth running before trusting a refresh

- `-Action Check` → exit 0.
- `references/mrs3/AGENTS.md` still contains both `MRS-TODOWRITE-INSTRUCTIONS`
  markers (the managed block is how the task card stays honest).
- `manifest.skillCount` equals the number of `SKILL.md` files actually present.
- No `opencode.exe` and no API key anywhere under `references/`:

```powershell
Get-ChildItem references -Recurse -File | Where-Object { $_.Extension -eq '.exe' -or $_.Length -gt 1MB }
Get-ChildItem references -Recurse -File | Select-String -Pattern 'sk-[A-Za-z0-9]{20,}'
```

Both must return nothing.

---

## 6. Why not just read the app every time?

Because the payload is versioned by the installer, not by the user. Upgrading MRS3
silently replaces `AGENTS.md` and every skill — there is no migration notice. A
mirror with hashes turns "the agent behaves differently after the upgrade" into a
one-command diff, and keeps the extracted knowledge usable from agents that are
not MRS3 (this skill is loaded by DeepSeek Harness, not by MRS3, and still benefits
from WCH's domain rules).
