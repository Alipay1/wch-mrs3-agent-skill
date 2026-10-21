<#
.SYNOPSIS
    Extract, snapshot and drift-check the agent payload that ships inside
    WCH MounRiver Studio 3 (MRS3).

.DESCRIPTION
    MRS3 embeds an OpenCode-based coding agent ("WCH Agent") whose prompt,
    config and skill files live in a plain directory tree inside the MRS3
    installation. That tree is readable and versionable, so this script turns
    it into a reproducible snapshot plus a hash baseline.

    Payload layout (discovered automatically):

        <MRS3>\resources\app\resources\win32\components\WCH\Others\
            WCHAgent\<variant>\opencode\
                AGENTS.md          global coding rules (system instructions)
                opencode.json      provider / model / compaction / skills.paths
                mcp.json           MCP servers injected via OPENCODE_CONFIG
                skills\<name>\     bundled skills (SKILL.md + references + scripts)

    Actions:
        Export  Mirror the payload into <skill>\references\mrs3 and write
                mrs3-manifest.json (per-file SHA256 + version stamps).
        Check   Re-hash the live MRS3 payload and report drift against the
                stored manifest. Exit 0 = in sync, 2 = drift, 1 = error.
        List    Print the bundled skill catalog without copying anything.

.PARAMETER Action
    Export (default), Check or List.

.PARAMETER Mrs3Root
    MRS3 install root. Defaults to auto-discovery.

.PARAMETER Destination
    Snapshot directory. Defaults to <skill root>\references\mrs3.

.PARAMETER Force
    Export: delete destination files that no longer exist in MRS3.
    Without it, stale files are kept and reported.

.EXAMPLE
    .\sync-mrs3-agent.ps1 -Action Export -Force

.EXAMPLE
    .\sync-mrs3-agent.ps1 -Action Check

.NOTES
    ASCII-only on purpose: Windows PowerShell 5.1 may parse UTF-8-without-BOM
    scripts through the active ANSI code page. Payload files are copied
    byte-for-byte, so their Chinese content is preserved regardless.
#>

[CmdletBinding()]
param(
    [ValidateSet('Export', 'Check', 'List')]
    [string]$Action = 'Export',

    [string]$Mrs3Root,

    [string]$Destination,

    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

function Write-Info { param([string]$Message) Write-Host "[mrs3] $Message" }
function Write-Warn2 { param([string]$Message) Write-Host "[mrs3] WARN $Message" -ForegroundColor Yellow }

function Get-NormalizedPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-IsMRS3Root {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $product = Join-Path $Path 'resources\app\product.json'
    if (Test-Path -LiteralPath $product) { return $true }
    # Also accept a directory that itself is the "resources\app" folder.
    if (Test-Path -LiteralPath (Join-Path $Path 'product.json')) { return $true }
    return $false
}

function Resolve-Mrs3Root {
    param([string]$Explicit)

    $candidates = New-Object System.Collections.ArrayList

    if ($Explicit) {
        $p = Get-NormalizedPath $Explicit
        # Allow pointing at the app dir, the resources dir or the install root.
        $candidates.Add($p) | Out-Null
        $candidates.Add((Join-Path $p 'resources\app')) | Out-Null
        $candidates.Add((Join-Path $p '..\..')) | Out-Null
        $parent = Split-Path $p -Parent
        if ($parent) { $candidates.Add((Join-Path $parent '..\..')) | Out-Null }
    }

    foreach ($envName in @('MRS3_HOME', 'MOUNRIVER_STUDIO3_HOME', 'MRS3_ROOT')) {
        $v = [Environment]::GetEnvironmentVariable($envName)
        if ($v) { $candidates.Add($v) | Out-Null }
    }

    # Uninstall registry (both hives, both views).
    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($rk in $regRoots) {
        try {
            if (-not (Test-Path $rk)) { continue }
            foreach ($k in Get-ChildItem $rk -ErrorAction SilentlyContinue) {
                $props = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }
                $name = [string]$props.DisplayName
                if ($name -match 'MounRiver\s*Studio\s*3') {
                    foreach ($field in @('InstallLocation', 'DisplayIcon', 'UninstallString')) {
                        $val = [string]$props.$field
                        if (-not $val) { continue }
                        $val = $val.Trim('"')
                        if ($val -match '\.exe') { $val = Split-Path $val -Parent }
                        if ($val) { $candidates.Add($val) | Out-Null }
                    }
                }
            }
        } catch { }
    }

    # Common install locations. Join-Path throws for drives that do not exist,
    # so build these strings by hand.
    $drives = @('C:', 'D:', 'E:', 'F:')
    foreach ($d in $drives) {
        foreach ($rel in @('MounRiver\MounRiver_Studio3', 'MounRiver Studio 3', 'Program Files\MounRiver\MounRiver_Studio3', 'Program Files (x86)\MounRiver\MounRiver_Studio3')) {
            $candidates.Add(('{0}\{1}' -f $d, $rel)) | Out-Null
        }
    }
    try {
        $pf = [Environment]::GetFolderPath('ProgramFiles')
        if ($pf) { $candidates.Add(('{0}\{1}' -f $pf, 'MounRiver\MounRiver_Studio3')) | Out-Null }
    } catch { }

    foreach ($c in $candidates) {
        if (-not $c) { continue }
        try {
            $full = Get-NormalizedPath $c
        } catch { continue }
        if (-not (Test-Path -LiteralPath $full)) { continue }
        if ($full -match '\\resources\\app$') {
            $root = Split-Path (Split-Path $full -Parent) -Parent
            if (Test-IsMRS3Root $root) { return $root }
            continue
        }
        if (Test-IsMRS3Root $full) { return $full }
    }
    return $null
}

function Get-ProductInfo {
    param([string]$Root)
    $info = [pscustomobject]@{
        Version    = ''
        MrsVersion = ''
        Date       = ''
        Commit     = ''
    }
    $appDir = Join-Path $Root 'resources\app'
    $productPath = Join-Path $appDir 'product.json'
    if (Test-Path -LiteralPath $productPath) {
        try {
            $p = Get-Content -LiteralPath $productPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $info.Version = [string]$p.version
            $info.MrsVersion = [string]$p.mrsVersion
            $info.Date = [string]$p.date
            $info.Commit = [string]$p.commit
        } catch { }
    }
    return $info
}

function Resolve-AgentPayload {
    param([string]$Root)

    # Probe the known layouts first (fast path).
    $bases = @(
        (Join-Path $Root 'resources\app\resources\win32\components\WCH\Others\WCHAgent'),
        (Join-Path $Root 'resources\win32\components\WCH\Others\WCHAgent'),
        (Join-Path $Root 'components\WCH\Others\WCHAgent')
    )
    $agentDir = $null
    foreach ($b in $bases) {
        if (Test-Path -LiteralPath $b) { $agentDir = $b; break }
    }

    # Fallback: bounded search.
    if (-not $agentDir) {
        $searchRoots = @((Join-Path $Root 'resources'), $Root)
        foreach ($sr in $searchRoots) {
            if (-not (Test-Path -LiteralPath $sr)) { continue }
            try {
                $hit = Get-ChildItem -LiteralPath $sr -Recurse -Directory -Depth 8 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'WCHAgent' } |
                    Select-Object -First 1
                if ($hit) { $agentDir = $hit.FullName; break }
            } catch { }
        }
    }
    if (-not $agentDir) { return $null }

    $variants = Get-ChildItem -LiteralPath $agentDir -Directory -ErrorAction SilentlyContinue
    $chosen = $null
    foreach ($v in $variants) {
        $payload = Join-Path $v.FullName 'opencode'
        if ((Test-Path -LiteralPath (Join-Path $payload 'AGENTS.md')) -or
            (Test-Path -LiteralPath (Join-Path $payload 'opencode.json'))) {
            $chosen = $v; break
        }
    }
    if (-not $chosen) { return $null }

    $result = [pscustomobject]@{
        AgentDir       = $agentDir
        VariantName    = $chosen.Name
        VariantDir     = $chosen.FullName
        PayloadDir     = (Join-Path $chosen.FullName 'opencode')
        Version        = ''
        Intro          = ''
        ExePath        = ''
        ExeFileVersion = ''
        ExeSha256      = ''
    }

    $manifestPath = Join-Path $agentDir 'sub_manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($d in $m.details) {
                if ([string]$d.name -eq $chosen.Name) {
                    $result.Version = [string]$d.version
                    $result.Intro = [string]$d.intro
                    break
                }
            }
        } catch { }
    }

    $exe = Join-Path $chosen.FullName 'opencode.exe'
    if (Test-Path -LiteralPath $exe) {
        $result.ExePath = $exe
        try { $result.ExeFileVersion = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion } catch { }
        try { $result.ExeSha256 = Get-Sha256 $exe } catch { }
    }
    return $result
}

function Get-PayloadFiles {
    param([string]$PayloadDir)
    $files = Get-ChildItem -LiteralPath $PayloadDir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\node_modules\\' }
    return $files
}

# Companion prompt/config files that live next to the payload (variant root and
# TempData), not inside opencode\. They carry the todowrite contract and the
# default config template, so they are worth snapshotting too. The 145 MB
# opencode.exe is deliberately never copied.
function Get-ExtraFiles {
    param([string]$VariantDir)
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $VariantDir)) { return $out }
    Get-ChildItem -LiteralPath $VariantDir -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ne '.exe' } |
        ForEach-Object { $out.Add($_) | Out-Null }
    $tempData = Join-Path $VariantDir 'TempData'
    if (Test-Path -LiteralPath $tempData) {
        Get-ChildItem -LiteralPath $tempData -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $out.Add($_) | Out-Null }
    }
    return $out
}

function Get-RelativePath {
    param([string]$Base, [string]$Path)
    $b = (Get-NormalizedPath $Base) + '\'
    $p = Get-NormalizedPath $Path
    if ($p.StartsWith($b, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $p.Substring($b.Length)
    }
    return $p
}

function Get-ManifestPath {
    param([string]$Dest)
    return (Join-Path $Dest 'mrs3-manifest.json')
}

function Read-Manifest {
    param([string]$Dest)
    $mp = Get-ManifestPath $Dest
    if (-not (Test-Path -LiteralPath $mp)) { return $null }
    try {
        return (Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Warn2 "manifest unreadable: $mp"
        return $null
    }
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

$skillRoot = Split-Path $PSScriptRoot -Parent
if (-not $Destination) {
    $Destination = Join-Path $skillRoot 'references\mrs3'
}
$Destination = Get-NormalizedPath $Destination

$root = Resolve-Mrs3Root $Mrs3Root
if (-not $root) {
    Write-Host "[mrs3] ERROR MRS3 installation not found."
    Write-Host "        Pass -Mrs3Root 'C:\MounRiver\MounRiver_Studio3' or set MRS3_HOME."
    exit 1
}
Write-Info "install root: $root"

$product = Get-ProductInfo $root
Write-Info ("MRS3 appVersion={0} mrsVersion={1}" -f $product.Version, $product.MrsVersion)

$agent = Resolve-AgentPayload $root
if (-not $agent) {
    Write-Host "[mrs3] ERROR WCHAgent payload not found under $root"
    Write-Host "        Expected ...\components\WCH\Others\WCHAgent\<variant>\opencode"
    exit 1
}
Write-Info "payload: $($agent.PayloadDir)"
Write-Info ("variant={0} version={1}" -f $agent.VariantName, $agent.Version)

$payloadFiles = Get-PayloadFiles $agent.PayloadDir
Write-Info ("payload files: {0}" -f @($payloadFiles).Count)

$extraFiles = Get-ExtraFiles $agent.VariantDir
Write-Info ("companion files: {0}" -f @($extraFiles).Count)

# Unified source list. Rel is the path inside the snapshot; companion files are
# parked under _variant\ so they never collide with the payload tree.
$sources = New-Object System.Collections.ArrayList
foreach ($f in $payloadFiles) {
    $sources.Add([pscustomobject]@{
        Rel    = (Get-RelativePath $agent.PayloadDir $f.FullName)
        Source = $f.FullName
        Length = $f.Length
    }) | Out-Null
}
foreach ($f in $extraFiles) {
    $sources.Add([pscustomobject]@{
        Rel    = ('_variant\' + (Get-RelativePath $agent.VariantDir $f.FullName))
        Source = $f.FullName
        Length = $f.Length
    }) | Out-Null
}

# ---------------------------------------------------------------- List mode
if ($Action -eq 'List') {
    $skillsDir = Join-Path $agent.PayloadDir 'skills'
    Write-Host ''
    Write-Host 'Bundled skills:'
    if (Test-Path -LiteralPath $skillsDir) {
        Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object {
            $md = Join-Path $_.FullName 'SKILL.md'
            $desc = ''
            if (Test-Path -LiteralPath $md) {
                $lines = Get-Content -LiteralPath $md -Encoding UTF8
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match '^description:\s*(.*)$') { $desc = $Matches[1]; break }
                }
            }
            if ($desc.Length -gt 150) { $desc = $desc.Substring(0, 150) + '...' }
            Write-Host ("  {0}" -f $_.Name)
            Write-Host ("      {0}" -f $desc)
        }
    }
    exit 0
}

# --------------------------------------------------------------- Check mode
if ($Action -eq 'Check') {
    $manifest = Read-Manifest $Destination
    if (-not $manifest) {
        Write-Host "[mrs3] ERROR no manifest at $(Get-ManifestPath $Destination). Run -Action Export first."
        exit 1
    }

    $drift = New-Object System.Collections.ArrayList

    if ([string]$manifest.mrs3.appVersion -ne $product.Version) {
        $drift.Add("MRS3 appVersion $($manifest.mrs3.appVersion) -> $($product.Version)") | Out-Null
    }
    if ([string]$manifest.wchAgent.version -ne $agent.Version) {
        $drift.Add("WCHAgent version $($manifest.wchAgent.version) -> $($agent.Version)") | Out-Null
    }
    if ([string]$manifest.opencodeExe.sha256 -ne $agent.ExeSha256 -and $agent.ExeSha256) {
        $drift.Add("opencode.exe changed (bundled OpenCode engine updated)") | Out-Null
    }

    $old = @{}
    foreach ($f in $manifest.files) { $old[[string]$f.path] = [string]$f.sha256 }

    $new = @{}
    foreach ($f in $sources) {
        $new[[string]$f.Rel] = Get-Sha256 $f.Source
    }

    foreach ($k in ($new.Keys | Sort-Object)) {
        if (-not $old.ContainsKey($k)) {
            $drift.Add("added:    $k") | Out-Null
        } elseif ($old[$k] -ne $new[$k]) {
            $drift.Add("modified: $k") | Out-Null
        }
    }
    foreach ($k in ($old.Keys | Sort-Object)) {
        if (-not $new.ContainsKey($k)) {
            $drift.Add("removed:  $k") | Out-Null
        }
    }

    if ($drift.Count -eq 0) {
        Write-Info 'in sync with installed MRS3 payload'
        exit 0
    }

    Write-Host ''
    Write-Host ("[mrs3] DRIFT detected ({0} item(s)):" -f $drift.Count)
    $drift | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
    Write-Host '  Re-run:  .\sync-mrs3-agent.ps1 -Action Export -Force'
    Write-Host '  Then review the diff and update references\mrs3-skill-catalog.md'
    exit 2
}

# -------------------------------------------------------------- Export mode
if (Test-Path -LiteralPath $Destination) {
    if ($Force) {
        Write-Info "removing previous snapshot: $Destination"
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
} else {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$entries = New-Object System.Collections.ArrayList
$copied = 0
foreach ($s in $sources) {
    $rel = [string]$s.Rel
    $target = Join-Path $Destination $rel
    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $s.Source -Destination $target -Force
    $hash = Get-Sha256 $target
    $entries.Add([ordered]@{ path = $rel; sha256 = $hash; size = $s.Length }) | Out-Null
    $copied++
}
Write-Info "copied $copied file(s)"

# Report extras that stayed behind when -Force was not used.
if (-not $Force) {
    $expected = @{}
    foreach ($e in $entries) { $expected[[string]$e.path] = $true }
    $extras = Get-ChildItem -LiteralPath $Destination -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'mrs3-manifest.json' } |
        ForEach-Object { Get-RelativePath $Destination $_.FullName } |
        Where-Object { -not $expected.ContainsKey($_) }
    if ($extras) {
        Write-Warn2 ("{0} stale file(s) kept; re-run with -Force to prune:" -f @($extras).Count)
        $extras | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" }
    }
}

$runtimeHome = Join-Path $HOME '.config\opencode'
$runtimeNote = 'not found'
if (Test-Path -LiteralPath $runtimeHome) {
    $runtimeNote = $runtimeHome
}

$skillCount = 0
$skillsDir = Join-Path $agent.PayloadDir 'skills'
if (Test-Path -LiteralPath $skillsDir) {
    $skillCount = @(Get-ChildItem -LiteralPath $skillsDir -Directory).Count
}

$manifestOut = [ordered]@{
    schema       = 1
    exportedAt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    mrs3         = [ordered]@{
        installRoot = $root
        appVersion  = $product.Version
        mrsVersion  = $product.MrsVersion
        productDate = $product.Date
        commit      = $product.Commit
    }
    wchAgent     = [ordered]@{
        variant = $agent.VariantName
        version = $agent.Version
        intro   = $agent.Intro
        payload = $agent.PayloadDir
    }
    opencodeExe  = [ordered]@{
        path        = $agent.ExePath
        fileVersion = $agent.ExeFileVersion
        sha256      = $agent.ExeSha256
        copied      = $false
    }
    runtimeHome  = $runtimeNote
    fileCount    = $entries.Count
    skillCount   = $skillCount
    files        = $entries
}

$manifestPath = Get-ManifestPath $Destination
$json = $manifestOut | ConvertTo-Json -Depth 6
Set-Content -LiteralPath $manifestPath -Value $json -Encoding UTF8
Write-Info "manifest: $manifestPath"

Write-Host ''
Write-Info ("snapshot complete: {0} files, {1} skills, {2} KB" -f $entries.Count, $skillCount, [math]::Round((($payloadFiles | Measure-Object Length -Sum).Sum) / 1KB, 1))
exit 0
