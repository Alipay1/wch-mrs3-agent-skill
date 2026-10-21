<#
.SYNOPSIS
    MounRiver Studio 3 (MRS3) discovery, environment setup, build and flash.

.DESCRIPTION
    MounRiver Studio 3 automation in two layers.

    1. Toolchain automation. Resolves MRS3's own layout and drives its bundled
       compiler, make and OpenOCD:

        <MRS3>\MounRiver Studio 3.exe
        <MRS3>\bin\mounriver-studio 3.cmd              IDE CLI (VS Code derived)
        <MRS3>\resources\app\product.json              version / mrsVersion / commit
        <MRS3>\resources\app\resources\win32\
            components\WCH\Toolchain\                  RISC-V Embedded GCC[12|15]
            components\WCH\OpenOCD\OpenOCD\bin\        openocd.exe + wch-riscv.cfg
            components\WCH\Others\WCHAgent\            embedded agent payload
                sub_manifest.json                      variant + payload version
                default\opencode.exe                   engine (OpenCode build)
                default\opencode\                      AGENTS.md, mcp.json, skills
            others\Build_Tools\Make\bin\make.exe       GNU make

    2. IDE tools over MCP. The extension runs the agent as a headless server
       ("opencode.exe serve --hostname 127.0.0.1 --port <n>"), records pid and
       ports in %USERPROFILE%\.config\opencode\mrs-serve-state.json, and serves
       its ide-* tool surface as an MCP server (SSE, protocol 2024-11-05) on the
       recorded mcpPort. This script speaks that protocol directly: it lists the
       tools, calls any of them, and submits / polls asynchronous tasks.

    Actions:
        doctor       Verify install, project, toolchain, make, OpenOCD, agent.
        configure    Put the MRS3 toolchain, make and OpenOCD on the process PATH.
        build        Run the project's generated makefile with the matching GCC.
        flash        Program, verify and reset through MRS3's bundled OpenOCD.
        build-flash  Build, then flash only if the build succeeded.
        agent        Report the embedded agent: payload, engine, live ports, tools.
        mcp-tools    List the IDE tools served over MCP (add -ShowSchema).
        mcp          Call one IDE tool: -Tool plus -ToolArguments / -ToolArgumentsFile.
        ide-task     Call one asynchronous IDE tool and poll it to completion.
        ide-build    Build the IDE active project (ide-build-project / -rebuild).
        ide-download Flash the IDE active project (ide-download-project).

    Exit codes: 0 success, 1 failure. Never infers success from partial output;
    an IDE task counts as success only when its status word is success.

.PARAMETER Action
    doctor (default), configure, build, flash, build-flash, agent, mcp-tools, mcp,
    ide-task, ide-build or ide-download.

.PARAMETER ProjectPath
    Project directory, a .wvproj file, or any directory containing one.

.PARAMETER Mrs3Root
    MRS3 install root. Defaults to auto-discovery.

.PARAMETER BuildDir
    Generated build directory containing the makefile.

.PARAMETER Artifact
    Exact ELF / HEX / BIN to program. Defaults to the project flashConfig
    target_path when it exists, otherwise the best artifact in the build directory.

.PARAMETER FlashAddress
    Load address for a raw BIN. Required unless the project supplies one.

.PARAMETER OpenOcdConfig
    Alternative OpenOCD config. Defaults to the bundled wch-riscv.cfg.

.PARAMETER Jobs
    Parallel build jobs. Defaults to the processor count.

.PARAMETER Clean
    Run "make clean" before building.

.PARAMETER PersistUserPath
    Persist MRS3_HOME and the toolchain entries to the current user's environment.

.PARAMETER NoProbe
    Skip the live agent / MCP network probes in doctor and agent.

.EXAMPLE
    .\wch-mrs3.ps1 -Action doctor -ProjectPath .

.EXAMPLE
    .\wch-mrs3.ps1 -Action build -ProjectPath . -Clean

.EXAMPLE
    .\wch-mrs3.ps1 -Action flash -ProjectPath . -Artifact .\obj\app.elf
#>

[CmdletBinding()]
param(
    [ValidateSet('doctor', 'configure', 'build', 'flash', 'build-flash', 'agent',
                 'mcp-tools', 'mcp', 'ide-task', 'ide-build', 'ide-download')]
    [string]$Action = 'doctor',

    [string]$ProjectPath = '.',
    [string]$Mrs3Root,
    [string]$BuildDir,
    [string]$Artifact,
    [string]$FlashAddress,
    [string]$OpenOcdConfig,

    [ValidateRange(1, 256)]
    [int]$Jobs = [Math]::Max(1, [Environment]::ProcessorCount),

    [string]$Tool,
    [string]$ToolArguments,
    [string]$ToolArgumentsFile,

    [ValidateRange(5, 900)]
    [int]$McpTimeoutSec = 300,

    [switch]$Clean,
    [switch]$PersistUserPath,
    [switch]$NoProbe,
    [switch]$ShowSchema
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[MRS3] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "[MRS3] $Message"
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$BasePath = (Get-Location).Path
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim('"'))
    if ([IO.Path]::IsPathRooted($expanded)) {
        return [IO.Path]::GetFullPath($expanded)
    }
    return [IO.Path]::GetFullPath((Join-Path $BasePath $expanded))
}

function Add-UniqueString {
    param(
        [Parameter(Mandatory = $true)]$List,
        [Parameter(Mandatory = $true)]$Seen,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    try { $full = [IO.Path]::GetFullPath($Value.Trim('"').TrimEnd('\')) } catch { return }
    if ($Seen.Add($full)) { [void]$List.Add($full) }
}

function Test-Mrs3Root {
    param([string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    try { $rootFull = Resolve-FullPath $Root } catch { return $false }
    $exe = Join-Path $rootFull 'MounRiver Studio 3.exe'
    $win32 = Join-Path $rootFull 'resources\app\resources\win32'
    return (Test-Path -LiteralPath $exe -PathType Leaf) -and (Test-Path -LiteralPath $win32 -PathType Container)
}

function Find-Mrs3Root {
    param([string]$ExplicitRoot)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    Add-UniqueString $candidates $seen $ExplicitRoot
    Add-UniqueString $candidates $seen $env:MRS3_HOME
    Add-UniqueString $candidates $seen $env:MOUNRIVER_STUDIO3_HOME

    foreach ($entry in (($env:Path -split ';') | Where-Object { $_ })) {
        $cursor = $entry.Trim('"')
        for ($i = 0; $i -lt 9 -and -not [string]::IsNullOrWhiteSpace($cursor); $i++) {
            Add-UniqueString $candidates $seen $cursor
            $parent = Split-Path -Parent $cursor
            if ($parent -eq $cursor) { break }
            $cursor = $parent
        }
    }

    $registryRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($regRoot in $registryRoots) {
        try {
            Get-ItemProperty $regRoot -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'MounRiver\s*Studio\s*3|MRS3' } |
                ForEach-Object {
                    Add-UniqueString $candidates $seen $_.InstallLocation
                    if ($_.DisplayIcon) { Add-UniqueString $candidates $seen (Split-Path -Parent ($_.DisplayIcon -replace ',\d+$', '')) }
                }
        } catch { }
    }

    $common = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA,
        $env:USERPROFILE
    ) | Where-Object { $_ }

    foreach ($base in $common) {
        foreach ($name in @('MounRiver Studio 3', 'MounRiver_Studio3', 'MounRiverStudio3', 'MRS3', 'MounRiver')) {
            Add-UniqueString $candidates $seen (Join-Path $base $name)
        }
    }

    try {
        foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root })) {
            foreach ($relative in @(
                'MounRiver Studio 3',
                'MounRiver_Studio3',
                'MounRiver\MounRiver_Studio3',
                'WCH\MounRiver_Studio3',
                'Program Files\MounRiver Studio 3',
                'Program Files\MounRiver_Studio3',
                'Program Files (x86)\MounRiver Studio 3',
                'Program Files (x86)\MounRiver_Studio3'
            )) {
                Add-UniqueString $candidates $seen (Join-Path $drive.Root $relative)
            }
        }
    } catch { }

    foreach ($candidate in $candidates) {
        if (Test-Mrs3Root $candidate) { return (Resolve-FullPath $candidate) }
    }

    throw 'Valid MounRiver Studio 3 install directory was not found. Use -Mrs3Root to specify the directory containing "MounRiver Studio 3.exe".'
}

function Get-Mrs3Layout {
    param([Parameter(Mandatory = $true)][string]$Root)

    $win32 = Join-Path $Root 'resources\app\resources\win32'
    $toolchainRoot = Join-Path $win32 'components\WCH\Toolchain'
    $makeExe = Join-Path $win32 'others\Build_Tools\Make\bin\make.exe'
    $openOcdRoot = Join-Path $win32 'components\WCH\OpenOCD\OpenOCD'
    $agentRoot = Join-Path $win32 'components\WCH\Others\WCHAgent'

    [pscustomobject]@{
        Root          = $Root
        StudioExe     = Join-Path $Root 'MounRiver Studio 3.exe'
        IdeCli        = Join-Path $Root 'bin\mounriver-studio 3.cmd'
        ProductJson   = Join-Path $Root 'resources\app\product.json'
        Win32Root     = $win32
        ToolchainRoot = $toolchainRoot
        MakeExe       = $makeExe
        OpenOcdRoot   = $openOcdRoot
        OpenOcdExe    = Join-Path $openOcdRoot 'bin\openocd.exe'
        OpenOcdConfig = Join-Path $openOcdRoot 'bin\wch-riscv.cfg'
        AgentRoot     = $agentRoot
        SubManifest   = Join-Path $agentRoot 'sub_manifest.json'
        AgentExe      = Join-Path $agentRoot 'default\opencode.exe'
        AgentPayload  = Join-Path $agentRoot 'default\opencode'
    }
}

function Get-ProductInfo {
    param([Parameter(Mandatory = $true)][string]$ProductJson)

    if (-not (Test-Path -LiteralPath $ProductJson -PathType Leaf)) { return $null }
    try {
        $product = Get-Content -LiteralPath $ProductJson -Raw | ConvertFrom-Json
        return [pscustomobject]@{
            Version    = Get-Prop $product 'version'
            MrsVersion = Get-Prop $product 'mrsVersion'
            Commit     = Get-Prop $product 'commit'
            Date       = Get-Prop $product 'date'
        }
    } catch {
        return $null
    }
}

function Resolve-Project {
    param([string]$InputPath)

    $full = Resolve-FullPath $InputPath
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        if ([IO.Path]::GetExtension($full) -ine '.wvproj') {
            throw "ProjectPath must point to a .wvproj file when it points to a file: $full"
        }
        return [pscustomobject]@{ Root = Split-Path -Parent $full; Wvproj = $full }
    }

    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "Project path does not exist: $full"
    }

    $direct = @(Get-ChildItem -LiteralPath $full -Filter '*.wvproj' -File -ErrorAction SilentlyContinue)
    if ($direct.Count -eq 1) {
        return [pscustomobject]@{ Root = $full; Wvproj = $direct[0].FullName }
    }
    if ($direct.Count -gt 1) {
        throw "Multiple .wvproj files found in directory. Use -ProjectPath to specify one file:`n$($direct.FullName -join "`n")"
    }

    $recursive = @(Get-ChildItem -LiteralPath $full -Filter '*.wvproj' -File -Recurse -ErrorAction SilentlyContinue)
    if ($recursive.Count -eq 1) {
        return [pscustomobject]@{ Root = $recursive[0].Directory.FullName; Wvproj = $recursive[0].FullName }
    }
    if ($recursive.Count -gt 1) {
        throw "Multiple .wvproj files found recursively. Use -ProjectPath to specify one file:`n$($recursive.FullName -join "`n")"
    }

    return [pscustomobject]@{ Root = $full; Wvproj = $null }
}

function Get-ProjectJson {
    param([string]$Wvproj)

    if ([string]::IsNullOrWhiteSpace($Wvproj)) { return $null }
    if (-not (Test-Path -LiteralPath $Wvproj -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $Wvproj -Raw | ConvertFrom-Json } catch { return $null }
}

function Get-RequestedToolchainName {
    param([string]$Wvproj)

    if ([string]::IsNullOrWhiteSpace($Wvproj) -or -not (Test-Path -LiteralPath $Wvproj)) { return $null }
    $text = Get-Content -LiteralPath $Wvproj -Raw
    $match = [regex]::Match($text, '\$\{WCH:Toolchain:(?<name>[^}]+)\}', 'IgnoreCase')
    if ($match.Success) { return $match.Groups['name'].Value.Trim() }
    return $null
}

function Get-ProjectFlashConfig {
    param($ProjectJson)

    $flash = Get-Prop $ProjectJson 'flashConfig'
    if (-not $flash) { return $null }
    [pscustomobject]@{
        Address    = Get-Prop $flash 'address'
        TargetPath = Get-Prop $flash 'target_path'
        McuType    = Get-Prop $flash 'mcutype'
    }
}

function Resolve-Toolchain {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [string]$RequestedName
    )

    if (-not (Test-Path -LiteralPath $Layout.ToolchainRoot -PathType Container)) {
        throw "MRS3 toolchain directory does not exist: $($Layout.ToolchainRoot)"
    }

    $mapping = @{
        'GCC'       = 'RISC-V Embedded GCC'
        'GCC8'      = 'RISC-V Embedded GCC'
        'RISC-V'    = 'RISC-V Embedded GCC'
        'GCC12'     = 'RISC-V Embedded GCC12'
        'GCC15'     = 'RISC-V Embedded GCC15'
    }

    $dirs = @(Get-ChildItem -LiteralPath $Layout.ToolchainRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'RISC-V' })
    if ($dirs.Count -eq 0) { throw "No MRS3 RISC-V toolchain found in: $($Layout.ToolchainRoot)" }

    $selected = $null
    if ($RequestedName) {
        $key = $RequestedName.ToUpperInvariant()
        if ($mapping.ContainsKey($key)) {
            $wanted = $mapping[$key]
            $selected = $dirs | Where-Object { $_.Name -ieq $wanted } | Select-Object -First 1
        }
        if (-not $selected) {
            $selected = $dirs | Where-Object { $_.Name -like "*$RequestedName*" } | Select-Object -First 1
        }
        if (-not $selected) {
            throw "Project requested toolchain '$RequestedName', but no matching MRS3 directory is installed. Installed: $($dirs.Name -join ', ')"
        }
    }

    if (-not $selected) {
        foreach ($preferred in @('RISC-V Embedded GCC15', 'RISC-V Embedded GCC12', 'RISC-V Embedded GCC')) {
            $selected = $dirs | Where-Object { $_.Name -ieq $preferred } | Select-Object -First 1
            if ($selected) { break }
        }
    }
    if (-not $selected) { $selected = $dirs | Sort-Object Name -Descending | Select-Object -First 1 }

    $bin = Join-Path $selected.FullName 'bin'
    $gcc = @(Get-ChildItem -LiteralPath $bin -Filter '*gcc.exe' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'gcc-(ar|nm|ranlib)' } |
        Sort-Object Name |
        Select-Object -First 1)
    if ($gcc.Count -eq 0) { throw "GCC was not found in toolchain directory: $bin" }

    [pscustomobject]@{
        Name = $selected.Name
        Bin  = $bin
        Gcc  = $gcc[0].FullName
    }
}

function Set-ProcessPath {
    param([string[]]$Prepend)
    $items = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Prepend) { Add-UniqueString $items $seen $item }
    foreach ($item in ($env:Path -split ';')) { Add-UniqueString $items $seen $item }
    $env:Path = $items -join ';'
}

function Set-UserEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Prepend
    )

    [Environment]::SetEnvironmentVariable('MRS3_HOME', $Root, 'User')
    $existing = [Environment]::GetEnvironmentVariable('Path', 'User')
    $items = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Prepend) { Add-UniqueString $items $seen $item }
    foreach ($item in ($existing -split ';')) { Add-UniqueString $items $seen $item }
    [Environment]::SetEnvironmentVariable('Path', ($items -join ';'), 'User')
}

function Resolve-BuildDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$ExplicitBuildDir,
        [string]$PreferredDirectory
    )

    if ($ExplicitBuildDir) {
        $full = Resolve-FullPath $ExplicitBuildDir $ProjectRoot
        if (-not (Test-Path -LiteralPath (Join-Path $full 'Makefile') -PathType Leaf)) {
            throw "Specified build directory does not contain Makefile: $full"
        }
        return $full
    }

    $makefiles = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter 'Makefile' -File -Recurse -ErrorAction SilentlyContinue)
    if ($makefiles.Count -eq 0) {
        throw "No generated Makefile found in project: $ProjectRoot. Generate build files with MRS3 first, or provide a project build script."
    }

    $ranked = foreach ($file in $makefiles) {
        $dir = $file.Directory.FullName
        $leaf = $file.Directory.Name
        $score = 0
        if ($dir -ieq $ProjectRoot) { $score += 20 }
        if ($leaf -match '^(obj|debug|release|build|output|out)$') { $score += 100 }
        if ($PreferredDirectory -and $dir -ieq $PreferredDirectory) { $score += 150 }
        if (@(Get-ChildItem -LiteralPath $dir -Filter '*.elf' -File -ErrorAction SilentlyContinue).Count -gt 0) { $score += 30 }
        if (@(Get-ChildItem -LiteralPath $dir -Filter '*.map' -File -ErrorAction SilentlyContinue).Count -gt 0) { $score += 10 }
        [pscustomobject]@{ Directory = $dir; Score = $score; Modified = $file.LastWriteTimeUtc }
    }

    $ordered = @($ranked | Sort-Object @{Expression='Score'; Descending=$true}, @{Expression='Modified'; Descending=$true})
    if ($ordered.Count -gt 1 -and $ordered[0].Score -eq $ordered[1].Score) {
        Write-Warn "Multiple candidate Makefiles found; selected most recent: $($ordered[0].Directory). Use -BuildDir to specify explicitly."
    }
    return $ordered[0].Directory
}

function Invoke-MakeBuild {
    param(
        [Parameter(Mandatory = $true)][string]$MakeExe,
        [Parameter(Mandatory = $true)][string]$Directory,
        [int]$ParallelJobs,
        [switch]$DoClean
    )

    Push-Location $Directory
    try {
        if ($DoClean) {
            Write-Step "Clean: $Directory"
            & $MakeExe clean
            if ($LASTEXITCODE -ne 0) { throw "make clean failed, exit code: $LASTEXITCODE" }
        }

        Write-Step "Build: $Directory"
        & $MakeExe "-j$ParallelJobs"
        if ($LASTEXITCODE -ne 0) { throw "Build failed, make exit code: $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}

function Get-FirmwareCandidates {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.elf', '.hex', '.bin') })

    foreach ($file in $files) {
        $priority = 0
        if ($file.Extension -ieq '.elf') { $priority = 300 }
        elseif ($file.Extension -ieq '.hex') { $priority = 200 }
        elseif ($file.Extension -ieq '.bin') { $priority = 100 }
        [pscustomobject]@{ File = $file; Priority = $priority }
    }
}

function Resolve-FirmwareArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$BuildDirectory,
        [string]$ExplicitArtifact,
        [string]$PreferredArtifact
    )

    if ($ExplicitArtifact) {
        $full = Resolve-FullPath $ExplicitArtifact $ProjectRoot
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Firmware does not exist: $full" }
        if ([IO.Path]::GetExtension($full) -notin @('.elf', '.hex', '.bin')) {
            throw "Unsupported firmware format: $full"
        }
        return [pscustomobject]@{ Path = $full; Source = 'explicit' }
    }

    if ($PreferredArtifact) {
        $preferredFull = Resolve-FullPath $PreferredArtifact $ProjectRoot
        if ((Test-Path -LiteralPath $preferredFull -PathType Leaf) -and
            ([IO.Path]::GetExtension($preferredFull) -in @('.elf', '.hex', '.bin'))) {
            return [pscustomobject]@{ Path = $preferredFull; Source = 'project flashConfig target_path' }
        }
    }

    if (-not $BuildDirectory) {
        throw 'No build directory was resolved and no -Artifact was supplied. Pass -Artifact <file> or -BuildDir <dir>.'
    }

    $ranked = @(Get-FirmwareCandidates $BuildDirectory |
        Sort-Object @{Expression='Priority'; Descending=$true}, @{Expression={$_.File.LastWriteTimeUtc}; Descending=$true})
    if ($ranked.Count -eq 0) { throw "No ELF, HEX, or BIN found in build directory: $BuildDirectory" }

    $bestPriority = $ranked[0].Priority
    $sameType = @($ranked | Where-Object { $_.Priority -eq $bestPriority })
    if ($sameType.Count -gt 1) {
        $newest = $sameType[0].File.LastWriteTimeUtc
        $nearNewest = @($sameType | Where-Object { [Math]::Abs(($_.File.LastWriteTimeUtc - $newest).TotalSeconds) -lt 2 })
        if ($nearNewest.Count -gt 1) {
            throw "Multiple same-priority firmware artifacts found; cannot safely choose automatically. Use -Artifact:`n$($nearNewest.File.FullName -join "`n")"
        }
    }
    return [pscustomobject]@{ Path = $ranked[0].File.FullName; Source = 'build directory' }
}

function Normalize-FlashAddress {
    param([string]$Address)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $null }
    $trimmed = $Address.Trim()
    if ($trimmed -notmatch '^0x[0-9a-fA-F]+$') { throw "Invalid FlashAddress: $Address" }
    if ($trimmed -match '^0x08000000$') { return '0x00000000' }
    return $trimmed
}

function Invoke-OpenOcdFlash {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [Parameter(Mandatory = $true)][string]$Firmware,
        [string]$Address,
        [string]$ExplicitConfig
    )

    $config = if ($ExplicitConfig) { Resolve-FullPath $ExplicitConfig } else { $Layout.OpenOcdConfig }
    if (-not (Test-Path -LiteralPath $Layout.OpenOcdExe -PathType Leaf)) { throw "OpenOCD does not exist: $($Layout.OpenOcdExe)" }
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "OpenOCD config does not exist: $config" }

    $extension = [IO.Path]::GetExtension($Firmware)
    $normalizedAddress = Normalize-FlashAddress $Address
    if ($extension -ieq '.bin' -and -not $normalizedAddress) {
        throw 'Flashing BIN requires a reliable -FlashAddress; the script will not guess. Prefer ELF or HEX.'
    }

    $openOcdPath = $Firmware.Replace('\', '/')
    $parts = New-Object 'System.Collections.Generic.List[string]'
    [void]$parts.Add("program `"$openOcdPath`"")
    if ($normalizedAddress) { [void]$parts.Add($normalizedAddress) }
    [void]$parts.Add('verify')
    [void]$parts.Add('reset')
    [void]$parts.Add('exit')
    $command = $parts -join ' '

    Write-Step "Flash: $Firmware"
    Push-Location (Split-Path -Parent $Layout.OpenOcdExe)
    try {
        & $Layout.OpenOcdExe -f $config -c $command
        if ($LASTEXITCODE -ne 0) { throw "OpenOCD flash failed, exit code: $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}

function Get-AgentInfo {
    param([Parameter(Mandatory = $true)]$Layout)

    $variantName = $null
    $variantVersion = $null
    if (Test-Path -LiteralPath $Layout.SubManifest -PathType Leaf) {
        try {
            $manifest = Get-Content -LiteralPath $Layout.SubManifest -Raw | ConvertFrom-Json
            $details = @(Get-Prop $manifest 'details')
            $detail = $details | Where-Object { (Get-Prop $_ 'name') -eq 'default' } | Select-Object -First 1
            if (-not $detail) { $detail = $details | Select-Object -First 1 }
            if ($detail) {
                $variantName = Get-Prop $detail 'name'
                $variantVersion = Get-Prop $detail 'version'
            }
        } catch { }
    }

    $engineVersion = $null
    $engineSize = 0
    if (Test-Path -LiteralPath $Layout.AgentExe -PathType Leaf) {
        try {
            $engineVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Layout.AgentExe).FileVersion
            $engineSize = (Get-Item -LiteralPath $Layout.AgentExe).Length
        } catch { }
    }

    [pscustomobject]@{
        Payload        = $Layout.AgentPayload
        PayloadPresent = (Test-Path -LiteralPath $Layout.AgentPayload -PathType Container)
        Exe            = $Layout.AgentExe
        ExePresent     = (Test-Path -LiteralPath $Layout.AgentExe -PathType Leaf)
        Variant        = $variantName
        VariantVersion = $variantVersion
        EngineVersion  = $engineVersion
        EngineSizeMb   = [Math]::Round($engineSize / 1MB, 1)
    }
}

function Get-RuntimeState {
    $home_ = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($home_)) {
        try { $home_ = [Environment]::GetFolderPath('UserProfile') } catch { $home_ = $null }
    }
    if ([string]::IsNullOrWhiteSpace($home_)) { return $null }
    $statePath = Join-Path $home_ '.config\opencode\mrs-serve-state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        return [pscustomobject]@{
            Path        = $statePath
            Pid         = Get-Prop $state 'pid'
            Port        = Get-Prop $state 'port'
            McpPort     = Get-Prop $state 'mcpPort'
            ModelAuth   = Get-Prop $state 'modelAuth'
            ModelAuthUrl= Get-Prop $state 'modelAuthUrl'
            ApiKeyFp    = Get-Prop $state 'apiKeyFp'
            ServerPass  = Get-Prop $state 'serverPassword'
        }
    } catch {
        return $null
    }
}

function Test-PortOpen {
    param([int]$Port, [string]$Target = '127.0.0.1')
    if ($Port -le 0) { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Target, $Port)
        if (-not $task.Wait(500)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Get-McpHealth {
    param([int]$Port)
    if ($Port -le 0) { return $null }
    $uri = "http://127.0.0.1:$Port/health"
    try {
        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 4
        $payload = $response.Content | ConvertFrom-Json
        return [pscustomobject]@{
            Ok        = $true
            Protocol  = Get-Prop $payload 'protocol'
            Transport = Get-Prop $payload 'transport'
            Tools     = @(Get-Prop $payload 'tools')
        }
    } catch {
        return [pscustomobject]@{ Ok = $false; Error = $_.Exception.Message; Tools = @() }
    }
}

function Show-AgentReport {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [switch]$SkipProbe
    )

    $agent = Get-AgentInfo $Layout
    if ($agent.PayloadPresent -or $agent.ExePresent) {
        $variantText = if ($agent.VariantVersion) { "$($agent.Variant) $($agent.VariantVersion)" } else { 'unknown variant' }
        Write-Step "Agent: $variantText, engine $($agent.EngineVersion) ($($agent.EngineSizeMb) MB)"
        Write-Step "Agent payload: $($agent.Payload)"
    } else {
        Write-Warn "WCH Agent payload not found under: $($Layout.AgentRoot)"
    }

    $state = Get-RuntimeState
    if (-not $state) {
        Write-Step 'Agent runtime: no mrs-serve-state.json (MRS3 is not running, or has not started the agent).'
        return
    }

    Write-Step "Agent runtime: pid $($state.Pid), engine port $($state.Port), MCP port $($state.McpPort)"
    if ($state.ModelAuthUrl) { Write-Step "Model auth endpoint: $($state.ModelAuthUrl)" }
    if ($state.ServerPass) { Write-Step 'Engine server password: enabled (random per session, memory only)' }

    if ($SkipProbe) { return }

    if (Test-PortOpen $state.Port) {
        Write-Step "Engine port $($state.Port): open (HTTP API requires the per-session password; expect 401 without it)"
    } else {
        Write-Step "Engine port $($state.Port): closed (stale state file, or the agent stopped)"
    }

    $health = Get-McpHealth $state.McpPort
    if ($health -and $health.Ok) {
        Write-Step "IDE tools: $($health.Tools.Count) tools via MCP/$($health.Transport) at http://127.0.0.1:$($state.McpPort)/sse ($($health.Protocol))"
        $sample = @($health.Tools | Select-Object -First 8) -join ', '
        Write-Step "IDE tool sample: $sample"
    } else {
        $reason = if ($health) { $health.Error } else { 'mcpPort not recorded' }
        Write-Step "IDE tools: MCP endpoint not reachable ($reason)"
    }
}

function Read-SseEvent {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][datetime]$Deadline
    )

    $eventName = 'message'
    $data = New-Object 'System.Collections.Generic.List[string]'

    while ($true) {
        $remaining = [int][Math]::Max(1, ($Deadline - (Get-Date)).TotalMilliseconds)
        $task = $Session.Reader.ReadLineAsync()
        if (-not $task.Wait($remaining)) {
            throw "Timed out waiting for an MCP event on port $($Session.Port)."
        }
        $line = $task.Result
        if ($null -eq $line) { throw 'MCP event stream was closed by the IDE.' }

        if ($line -eq '') {
            if ($data.Count -gt 0) {
                return [pscustomobject]@{ Event = $eventName; Data = ($data -join "`n") }
            }
            $eventName = 'message'
            continue
        }
        if ($line.StartsWith('event:')) { $eventName = $line.Substring(6).Trim(); continue }
        if ($line.StartsWith('data:')) { [void]$data.Add($line.Substring(5).Trim()); continue }
        # ':' prefixed lines are keepalive comments; anything else is ignored.
    }
}

function New-McpSession {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSec = 20
    )

    try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }

    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [Threading.Timeout]::InfiniteTimeSpan
    $uri = "http://127.0.0.1:$Port/sse"
    $response = $client.GetAsync($uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) {
        $code = [int]$response.StatusCode
        $client.Dispose()
        throw "MCP endpoint $uri returned HTTP $code."
    }

    $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $reader = New-Object System.IO.StreamReader($stream)

    $session = [pscustomobject]@{
        Client   = $client
        Response = $response
        Reader   = $reader
        Endpoint = $null
        Port     = $Port
        NextId   = 0
        Server   = $null
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $session.Endpoint) {
        $event = Read-SseEvent $session $deadline
        if ($event.Event -eq 'endpoint' -and $event.Data) { $session.Endpoint = $event.Data }
    }
    return $session
}

function Send-McpMessage {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Json
    )

    $postClient = New-Object System.Net.Http.HttpClient
    $postClient.Timeout = [TimeSpan]::FromSeconds(15)
    try {
        $content = New-Object System.Net.Http.StringContent($Json, [Text.Encoding]::UTF8, 'application/json')
        $postResponse = $postClient.PostAsync($Session.Endpoint, $content).GetAwaiter().GetResult()
        $status = [int]$postResponse.StatusCode
        if ($status -lt 200 -or $status -ge 300) { throw "MCP POST returned HTTP $status." }
        return $status
    } finally {
        $postClient.Dispose()
    }
}

function Send-McpNotification {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Method,
        $Params
    )

    $message = [ordered]@{ jsonrpc = '2.0'; method = $Method }
    if ($null -ne $Params) { $message['params'] = $Params }
    [void](Send-McpMessage $Session ($message | ConvertTo-Json -Depth 20 -Compress))
}

function Invoke-McpRpc {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Method,
        $Params,
        [int]$TimeoutSec = 300
    )

    $Session.NextId++
    $id = $Session.NextId
    $message = [ordered]@{ jsonrpc = '2.0'; id = $id; method = $Method }
    if ($null -ne $Params) { $message['params'] = $Params }
    [void](Send-McpMessage $Session ($message | ConvertTo-Json -Depth 20 -Compress))

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($true) {
        $event = Read-SseEvent $Session $deadline
        if ($event.Event -ne 'message') { continue }
        $payload = $null
        try { $payload = $event.Data | ConvertFrom-Json } catch { continue }
        if ((Get-Prop $payload 'id') -ne $id) { continue }
        $errorInfo = Get-Prop $payload 'error'
        if ($errorInfo) { throw "MCP error for ${Method}: $(Get-Prop $errorInfo 'message')" }
        return (Get-Prop $payload 'result')
    }
}

function Connect-McpSession {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSec = 20
    )

    $session = New-McpSession $Port $TimeoutSec
    $initParams = [ordered]@{
        protocolVersion = '2024-11-05'
        capabilities    = @{}
        clientInfo      = [ordered]@{ name = 'wch-mrs3-cli'; version = '1.0.0' }
    }
    $server = Invoke-McpRpc $session 'initialize' $initParams $TimeoutSec
    Send-McpNotification $session 'notifications/initialized' $null
    $session.Server = $server
    return $session
}

function Close-McpSession {
    param($Session)
    if (-not $Session) { return }
    try { $Session.Reader.Dispose() } catch { }
    try { $Session.Response.Dispose() } catch { }
    try { $Session.Client.Dispose() } catch { }
}

function Get-McpTools {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [int]$TimeoutSec = 60
    )
    $result = Invoke-McpRpc $Session 'tools/list' $null $TimeoutSec
    return @(Get-Prop $result 'tools')
}

function Invoke-McpTool {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Name,
        $Arguments,
        [int]$TimeoutSec = 300
    )

    $params = [ordered]@{ name = $Name; arguments = $Arguments }
    $result = Invoke-McpRpc $Session 'tools/call' $params $TimeoutSec

    $isError = Get-Prop $result 'isError'
    $texts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @(Get-Prop $result 'content')) {
        $type = Get-Prop $item 'type'
        if ($type -eq 'text') { [void]$texts.Add([string](Get-Prop $item 'text')) }
        else { [void]$texts.Add(($item | ConvertTo-Json -Depth 20 -Compress)) }
    }
    return [pscustomobject]@{ IsError = [bool]$isError; Text = ($texts -join "`n") }
}

function Show-McpToolResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Result
    )

    if ($Result.IsError) {
        Write-Step "Tool $Name reported an error."
        if ($Result.Text) { Write-Host $Result.Text }
        throw "IDE tool '$Name' returned isError=true."
    }
    if (-not $Result.Text) {
        Write-Step "Tool $Name completed with no text content."
        return
    }
    $parsed = $null
    try { $parsed = $Result.Text | ConvertFrom-Json } catch { }
    if ($null -ne $parsed) {
        Write-Host ($parsed | ConvertTo-Json -Depth 20)
        # IDE tools report application-level failures as {"success": false, ...}.
        if ($false -eq (Get-Prop $parsed 'success')) {
            throw "IDE tool '$Name' reported success=false."
        }
        return
    }
    Write-Host $Result.Text
}

function Get-McpToolArguments {
    param([string]$Json, [string]$File)

    if (-not [string]::IsNullOrWhiteSpace($File)) {
        $full = Resolve-FullPath $File
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "ToolArgumentsFile does not exist: $full" }
        $Json = Get-Content -LiteralPath $full -Raw
    }
    if ([string]::IsNullOrWhiteSpace($Json)) { return @{} }
    try { return ($Json | ConvertFrom-Json) } catch { throw "Tool arguments are not valid JSON: $($_.Exception.Message)" }
}

function Get-TaskIdFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, 'task_[A-Za-z0-9_\-]+')
    if ($match.Success) { return $match.Value }
    return $null
}

function Get-IdeTaskStatus {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    # The IDE prefixes its task report with a status line: four CJK characters
    # meaning "task status", a colon, then the ASCII status word. The marker is
    # assembled from code points so this script stays ASCII-only.
    $marker = [string]([char]0x4EFB) + [char]0x52A1 + [char]0x72B6 + [char]0x6001 + ':'
    $index = $Text.IndexOf($marker)
    if ($index -lt 0) { return $null }
    $rest = $Text.Substring($index + $marker.Length).Trim()
    $match = [regex]::Match($rest, '^[A-Za-z_]+')
    if ($match.Success) { return $match.Value.ToLowerInvariant() }
    return $null
}

function Wait-IdeTask {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [int]$TimeoutSec = 300,
        [int]$PollMs = 800
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $unreadable = 0
    $status = $null
    $lastText = $null
    $polls = 0

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds $PollMs
        $polls++
        $result = Invoke-McpTool $Session 'ide-get-task-status' @{ taskId = $TaskId } 60
        $lastText = $result.Text
        $status = Get-IdeTaskStatus $lastText

        if (-not $status) {
            $unreadable++
            if ($unreadable -ge 5) {
                throw "Could not read the status of IDE task $TaskId. Last response:`n$lastText"
            }
            continue
        }
        $unreadable = 0

        if ($status -eq 'success') {
            return [pscustomobject]@{ Status = $status; Text = $lastText; Polls = $polls }
        }
        if ($status -match '^(failed|error|cancelled|canceled|aborted|timeout)$') {
            throw "IDE task $TaskId finished with status '$status':`n$lastText"
        }
    }

    throw "Timed out after $TimeoutSec s waiting for IDE task $TaskId (last status: $status).`n$lastText"
}

function Resolve-IdeProject {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [int]$TimeoutSec = 60
    )

    $result = Invoke-McpTool $Session 'ide-get-projectToOperate' @{} $TimeoutSec
    $text = [string]$result.Text
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'IDE returned no active project. Open the project in MRS3 first.'
    }

    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { }
    if ($null -ne $parsed) {
        if ($false -eq (Get-Prop $parsed 'success')) {
            throw "No active project in MRS3: $(Get-Prop $parsed 'error'). Open the project in the IDE first."
        }
        $payload = Get-Prop $parsed 'data'
        if (-not $payload) { $payload = $parsed }
        $projectPath = Get-Prop $payload 'projectPath'
        if (-not $projectPath) { $projectPath = Get-Prop $payload 'path' }
        $projectName = Get-Prop $payload 'projectName'
        if (-not $projectName) { $projectName = Get-Prop $payload 'name' }
        return [pscustomobject]@{ ProjectPath = $projectPath; ProjectName = $projectName; Text = $text }
    }

    # Success returns the bare fsPath of the active project.
    $projectPath = $text.Trim()
    if (-not (Test-Path -LiteralPath $projectPath)) {
        throw "No active project in MRS3. The IDE said: $text"
    }
    return [pscustomobject]@{ ProjectPath = $projectPath; ProjectName = (Split-Path -Leaf $projectPath); Text = $text }
}

function Invoke-IdeTask {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$ToolName,
        $Arguments,
        [int]$TimeoutSec = 300
    )

    if ($null -eq $Arguments) { $Arguments = @{} }

    Write-Step "Submitting IDE task: $ToolName"
    $submission = Invoke-McpTool $Session $ToolName $Arguments $TimeoutSec
    if ($submission.IsError) { throw "IDE tool '$ToolName' failed: $($submission.Text)" }

    $taskId = Get-TaskIdFromText $submission.Text
    if (-not $taskId) {
        Write-Host $submission.Text
        throw "IDE tool '$ToolName' did not return a task id, so its completion cannot be verified."
    }
    Write-Step "Task id: $taskId"

    $outcome = Wait-IdeTask $Session $taskId $TimeoutSec
    Write-Host $outcome.Text
    Write-Step "Task finished: $($outcome.Status) (polled $($outcome.Polls)x)"
    return $outcome
}

function Get-McpSessionInfo {
    param([Parameter(Mandatory = $true)]$Session)

    $server = $Session.Server
    $info = Get-Prop $server 'serverInfo'
    return [pscustomobject]@{
        Name        = Get-Prop $info 'name'
        Version     = Get-Prop $info 'version'
        Protocol    = Get-Prop $server 'protocolVersion'
        Capabilities= (Get-Prop $server 'capabilities')
    }
}

try {
    Write-Step "Action: $Action"
    $root = Find-Mrs3Root $Mrs3Root
    $layout = Get-Mrs3Layout $root
    $product = Get-ProductInfo $layout.ProductJson

    if ($product -and $product.Version) {
        Write-Step "MRS3: $($layout.Root) ($($product.Version) / MRS $($product.MrsVersion))"
    } else {
        Write-Step "MRS3: $($layout.Root)"
    }
    if (Test-Path -LiteralPath $layout.IdeCli -PathType Leaf) { Write-Step "IDE CLI: $($layout.IdeCli)" }

    if ($Action -eq 'agent') {
        Show-AgentReport $layout -SkipProbe:$NoProbe
        exit 0
    }

    if ($Action -eq 'mcp-tools' -or $Action -eq 'mcp' -or $Action -eq 'ide-task' -or
        $Action -eq 'ide-build' -or $Action -eq 'ide-download') {
        $state = Get-RuntimeState
        if (-not $state) {
            throw 'The MRS3 agent is not running: %USERPROFILE%\.config\opencode\mrs-serve-state.json is missing. Start MRS3 and open a project.'
        }
        if (-not $state.McpPort) {
            throw 'mrs-serve-state.json has no mcpPort; the IDE tool server did not start.'
        }
        if (-not (Test-PortOpen $state.McpPort)) {
            throw "MCP port $($state.McpPort) is not accepting connections; the agent service is not running."
        }

        $session = Connect-McpSession $state.McpPort
        try {
            $info = Get-McpSessionInfo $session
            Write-Step "MCP: $($info.Name) $($info.Version), protocol $($info.Protocol), port $($state.McpPort)"
            $tools = Get-McpTools $session
            Write-Step "$($tools.Count) IDE tools available."

            switch ($Action) {
                'mcp-tools' {
                    foreach ($toolInfo in $tools) {
                        $toolName = Get-Prop $toolInfo 'name'
                        $description = [string](Get-Prop $toolInfo 'description')
                        $firstLine = @($description -split "`n")[0].Trim()
                        if ($firstLine.Length -gt 110) { $firstLine = $firstLine.Substring(0, 110) + '...' }
                        Write-Host ("  {0,-44} {1}" -f $toolName, $firstLine)
                        if ($ShowSchema) {
                            $schema = Get-Prop $toolInfo 'inputSchema'
                            if ($schema) { Write-Host ($schema | ConvertTo-Json -Depth 12) }
                        }
                    }
                    exit 0
                }
                'mcp' {
                    if ([string]::IsNullOrWhiteSpace($Tool)) {
                        throw 'The mcp action requires -Tool <name>. Use -Action mcp-tools to list the tools.'
                    }
                    $arguments = Get-McpToolArguments $ToolArguments $ToolArgumentsFile
                    Write-Step "Calling tool: $Tool"
                    $result = Invoke-McpTool $session $Tool $arguments $McpTimeoutSec
                    Show-McpToolResult $Tool $result
                    Write-Step 'Action succeeded.'
                    exit 0
                }
                'ide-task' {
                    if ([string]::IsNullOrWhiteSpace($Tool)) {
                        throw 'The ide-task action requires -Tool <name>. Use -Action mcp-tools to list the asynchronous tools.'
                    }
                    $arguments = Get-McpToolArguments $ToolArguments $ToolArgumentsFile
                    [void](Invoke-IdeTask $session $Tool $arguments $McpTimeoutSec)
                    Write-Step 'Action succeeded.'
                    exit 0
                }
                'ide-build' {
                    $ideProject = Resolve-IdeProject $session
                    Write-Step "Active IDE project: $($ideProject.ProjectPath)"
                    Write-Step 'IDE actions act on the IDE active project; -ProjectPath and -BuildDir do not apply here.'
                    $ideTool = if ($Clean) { 'ide-rebuild-project' } else { 'ide-build-project' }
                    [void](Invoke-IdeTask $session $ideTool @{} $McpTimeoutSec)
                    Write-Step 'Action succeeded.'
                    exit 0
                }
                'ide-download' {
                    $ideProject = Resolve-IdeProject $session
                    Write-Step "Active IDE project: $($ideProject.ProjectPath)"
                    Write-Step 'Flashing through the IDE download configuration of the active project.'
                    [void](Invoke-IdeTask $session 'ide-download-project' @{} $McpTimeoutSec)
                    Write-Step 'Action succeeded.'
                    exit 0
                }
            }
        } finally {
            Close-McpSession $session
        }
    }

    $project = Resolve-Project $ProjectPath
    $projectJson = Get-ProjectJson $project.Wvproj
    $requestedToolchain = Get-RequestedToolchainName $project.Wvproj
    $flashConfig = Get-ProjectFlashConfig $projectJson
    $toolchain = Resolve-Toolchain $layout $requestedToolchain

    foreach ($required in @($layout.StudioExe, $layout.MakeExe, $layout.OpenOcdExe, $layout.OpenOcdConfig, $toolchain.Gcc)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing required file: $required" }
    }

    # Generated makefiles hard-code a compiler name (riscv-none-embed-gcc,
    # riscv-wch-elf-gcc, riscv32-wch-elf-gcc) that does not change when the
    # project's toolchain selection changes. Put every installed RISC-V
    # toolchain on PATH, selected one first, so those names always resolve.
    $toolchainBins = New-Object 'System.Collections.Generic.List[string]'
    [void]$toolchainBins.Add($toolchain.Bin)
    foreach ($dir in @(Get-ChildItem -LiteralPath $layout.ToolchainRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'RISC-V' })) {
        [void]$toolchainBins.Add((Join-Path $dir.FullName 'bin'))
    }

    $pathEntries = @(
        (Split-Path -Parent $layout.MakeExe),
        (Split-Path -Parent $layout.OpenOcdExe),
        $layout.Root
    ) + $toolchainBins.ToArray()
    Set-ProcessPath $pathEntries
    $env:MRS3_HOME = $layout.Root

    Write-Step "Project: $($project.Root)"
    if ($project.Wvproj) { Write-Step "WVPROJ: $($project.Wvproj)" } else { Write-Warn 'No .wvproj found; existing Makefile only.' }
    Write-Step "Toolchain: $($toolchain.Name)"
    Write-Step "GCC: $($toolchain.Gcc)"
    Write-Step "Make: $($layout.MakeExe)"
    Write-Step "OpenOCD: $($layout.OpenOcdExe)"
    if ($flashConfig -and $flashConfig.McuType) { Write-Step "Chip (project): $($flashConfig.McuType)" }

    if ($PersistUserPath) {
        Set-UserEnvironment $layout.Root $pathEntries
        Write-Step 'Updated current user MRS3_HOME and PATH.'
    }

    if ($Action -eq 'doctor' -or $Action -eq 'configure') {
        Show-AgentReport $layout -SkipProbe:$NoProbe
        Write-Step 'Environment check passed.'
        exit 0
    }

    $resolvedBuildDir = $null
    $explicitArtifact = -not [string]::IsNullOrWhiteSpace($Artifact)
    if ($Action -eq 'flash' -and $explicitArtifact -and [string]::IsNullOrWhiteSpace($BuildDir)) {
        Write-Step 'Build directory not required: -Artifact was supplied explicitly.'
    } else {
        $preferredBuildDir = $null
        if ($flashConfig -and $flashConfig.TargetPath) {
            try {
                $targetFull = Resolve-FullPath $flashConfig.TargetPath $project.Root
                $preferredBuildDir = Split-Path -Parent $targetFull
            } catch { }
        }

        $resolvedBuildDir = Resolve-BuildDirectory $project.Root $BuildDir $preferredBuildDir
        Write-Step "Build directory: $resolvedBuildDir"
    }

    if ($Action -eq 'build' -or $Action -eq 'build-flash') {
        $buildStartedAt = [DateTime]::UtcNow
        Invoke-MakeBuild $layout.MakeExe $resolvedBuildDir $Jobs -DoClean:$Clean
        $newArtifacts = @(Get-FirmwareCandidates $resolvedBuildDir |
            Where-Object { $_.File.LastWriteTimeUtc -ge $buildStartedAt.AddSeconds(-2) } |
            Sort-Object @{Expression='Priority'; Descending=$true}, @{Expression={$_.File.LastWriteTimeUtc}; Descending=$true})
        if ($newArtifacts.Count -eq 0) {
            Write-Warn 'Build succeeded, but no newly generated ELF/HEX/BIN was found for this build.'
        } else {
            Write-Step "Build artifact: $($newArtifacts[0].File.FullName)"
        }
        if ($Action -eq 'build') { exit 0 }
    }

    $preferredArtifact = $null
    if ($flashConfig) { $preferredArtifact = $flashConfig.TargetPath }
    $firmware = Resolve-FirmwareArtifact $project.Root $resolvedBuildDir $Artifact $preferredArtifact
    if ($firmware.Source -eq 'project flashConfig target_path') {
        Write-Step "Firmware from project flashConfig: $($firmware.Path)"
    }

    $address = $FlashAddress
    if (-not $address -and [IO.Path]::GetExtension($firmware.Path) -ieq '.bin' -and $flashConfig) {
        $address = $flashConfig.Address
        if ($address) { Write-Step "Read BIN address from project flashConfig: $address" }
    }
    Invoke-OpenOcdFlash $layout $firmware.Path $address $OpenOcdConfig
    Write-Step 'Action succeeded.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
