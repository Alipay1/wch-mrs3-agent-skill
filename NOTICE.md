# Attribution and third-party content

This repository contains two kinds of material.

## 1. Original work

`SKILL.md`, `README.md`, `LICENSE`, `NOTICE.md`, `wch-mrs3.cmd`,
`scripts/wch-mrs3.ps1` and `scripts/sync-mrs3-agent.ps1` are original work,
licensed under the MIT license in [LICENSE](LICENSE).

## 2. Mirrored material

`references/mrs3/**` is a copy of files that ship inside
WCH MounRiver Studio 3 — the embedded "WCH Agent" payload: `AGENTS.md`,
`opencode.json`, `mcp.json`, the eight `skills/**` folders, and the `_variant/**`
files. Those files remain the property of their respective authors:

- WCH / MounRiver for the agent prompt and the eight skills;
- the OpenCode project for the runtime configuration and files covered by the
  MIT license reproduced at [`references/mrs3/_variant/LICENSE`](references/mrs3/_variant/LICENSE).

They are mirrored for interoperability and study. The MIT license above does not
relicense them, and nothing here grants rights the original authors did not grant.

The mirror is deliberately incomplete: `opencode.exe` (145 MB) and the user
configuration `%USERPROFILE%\.config\opencode\opencode.json` — which can contain a
plaintext model-provider API key — are never copied. Per-file SHA256 hashes for the
mirrored files are recorded in `references/mrs3/mrs3-manifest.json`.

Upstream bakes the author's local profile path into three places: `skills.paths` in
`references/mrs3/opencode.json` and
`references/mrs3/_variant/TempData/mrs-standard-config.json`, and `runtimeHome` in
`references/mrs3/mrs3-manifest.json`. In this repository the account name in those
three places is replaced with `<user>`, so the mirror is machine independent and
carries no local account name. `scripts/sync-mrs3-agent.ps1` performs the
substitution both when writing the mirror and when hashing it, which is why
`-Action Check` still compares like with like. No credentials are involved; these
are file paths.

## 3. No affiliation

This project is not affiliated with, endorsed by, or supported by WCH or
MounRiver. "MounRiver Studio", "WCH", "CH32" and related names are the marks of
their owners. Use at your own risk: the scripts here can erase and reprogram
microcontrollers.
