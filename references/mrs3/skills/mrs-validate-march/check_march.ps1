#!/usr/bin/env pwsh
# check_march.ps1 - Validate project build config (march/toolchain/abi/startfile)
# against mcu_isa.json (PowerShell implementation).
#
# Logic is identical to check_march.py:
#   1. march: must start with "rv32"; split by "_"; first segment is split
#      character-by-character, later segments kept verbatim; every part must
#      be present in the core's isa_ext (membership check, order irrelevant).
#   2. toolchain: component_toolchain must be in the series "toolchain" array.
#   3. abi: riscvTargetProcessor.integer_ABI must be in the core's "mabi" array.
#   4. startfile: .S files under --startfile-dir are compared with the chip's
#      "startfile" array (WARN only, never modified).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_march.ps1 --chip CH32H417WEU --core v5f \
#       --march rv32imafc_zba_zbb_zbc_zbs_xw --toolchain GCC15 --abi ilp32f
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_march.ps1 --march rv32imac_xw --isa-ext i,m,a,c,xw
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_march.ps1 --chip CH32V203CCT --startfile-dir <dir>
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_march.ps1 --selftest
#
# mcu_isa.json is always loaded from the same directory as this script (skill dir);
# no path argument is accepted.
# Exit code: 0 = all PASS; 1 = FAIL or argument error.

# Force UTF-8 output so Chinese/emoji render correctly in GBK consoles and UTF-8 terminals alike.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$DIVIDER = '=' * 72

# ---------------------------------------------------------------------------
# march splitting / checking
# ---------------------------------------------------------------------------
function Split-March {
    param([string]$march)
    # returns @(parts, err) — parts is $null when err is set
    $m = (($march -replace '^\s+|\s+$', '')).ToLower()
    if (-not $m) { return @($null, 'march 为空') }
    if (-not $m.StartsWith('rv32')) { return @($null, "march 必须以 rv32 开头（实际: $march）") }
    $rest = $m.Substring(4)
    if (-not $rest) { return @($null, 'march 在 rv32 之后为空') }
    $segs = $rest -split '_'
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($ch in $segs[0].ToCharArray()) { $parts.Add([string]$ch) }
    for ($k = 1; $k -lt $segs.Count; $k++) { if ($segs[$k]) { $parts.Add($segs[$k]) } }
    # @(a, b) 逗号连接的元素不会被 @() 展开/解包，$r[0] 即 List 本身
    return @($parts, $null)
}

function Test-March {
    param([string]$march, [string[]]$isaExt)
    # returns @(ok, err, parts, missing)
    $r = Split-March $march
    $parts = $r[0]; $err = $r[1]
    if ($err) { return @($false, $err, $null, $null) }
    $missing = @($parts | Where-Object { $_ -notin $isaExt })
    return @(($missing.Count -eq 0), $null, $parts, $missing)
}

function Join-List {
    param($items)
    return ((@($items) -join ', '))
}

# ---------------------------------------------------------------------------
# mcu_isa.json (always loaded from this script's directory)
# ---------------------------------------------------------------------------
function Get-IsaData {
    $path = Join-Path $PSScriptRoot 'mcu_isa.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "mcu_isa.json 不存在: $path" }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Find-Chip {
    param($data, [string]$name)
    foreach ($entry in $data) {
        foreach ($chip in $entry.chips) {
            if ($chip.name.ToUpper() -eq $name.ToUpper()) { return @($entry, $chip) }
        }
    }
    return @($null, $null)
}

function Pick-Core {
    param($cores, [string]$sel)
    if (-not $sel) { return $null }
    foreach ($c in $cores) {
        if ($c.core.ToLower().Contains($sel.ToLower())) { return $c }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Report rows
# ---------------------------------------------------------------------------
function New-Rows {
    # 逗号包裹：空 List 经函数返回会被枚举成无输出（$null），必须保持 List 本身
    return ,([System.Collections.Generic.List[object]]::new())
}
function Add-Row {
    param($rows, [string]$name, [string]$verdict, [string]$text)
    $rows.Add(@{ name = $name; verdict = $verdict; text = $text })
}

# ---------------------------------------------------------------------------
# Checker (context: chipName / coreSel / entry / chip / rows / core)
# ---------------------------------------------------------------------------
function Invoke-CheckMarch {
    param($ctx, [string]$march)
    $cores = @($ctx.entry.cores)
    $core = $ctx.core
    if ($null -ne $core) {
        $r = Test-March $march @($core.isa_ext | Where-Object { $_ })
        $ok = $r[0]; $err = $r[1]; $parts = $r[2]; $missing = $r[3]
        if ($err) { Add-Row $ctx.rows 'march' 'fail' $err; return $false }
        $text = "march=$march → 拆分: $(Join-List $parts) | isa_ext[$($ctx.entry.series) $($core.core)]: $(Join-List $core.isa_ext)"
        if ($missing.Count -gt 0) { $text += " | 缺失: $(Join-List $missing)" } else { $text += ' | 全部命中' }
        Add-Row $ctx.rows 'march' $(if ($ok) { 'ok' } else { 'fail' }) $text
        return $ok
    }
    Add-Row $ctx.rows 'march' 'info' "未指定内核，对芯片全部 $($cores.Count) 个内核逐一比对:"
    $anyPass = $false
    foreach ($c in $cores) {
        $r = Test-March $march @($c.isa_ext | Where-Object { $_ })
        $ok = $r[0]; $missing = $r[3]
        $anyPass = $anyPass -or $ok
        $t = "vs $($ctx.entry.series) $($c.core) isa_ext=[$(Join-List $c.isa_ext)]"
        if (-not $ok) { $t += " → 缺失: $(Join-List $missing)" }
        Add-Row $ctx.rows 'march' $(if ($ok) { 'ok' } else { 'fail' }) $t
    }
    Add-Row $ctx.rows 'march' $(if ($anyPass) { 'ok' } else { 'fail' }) $(if ($anyPass) { '结果: PASS（至少一个内核匹配）' } else { '结果: FAIL（所有内核均不匹配）' })
    return $anyPass
}

function Invoke-CheckToolchain {
    param($ctx, [string]$value)
    $allowed = @($ctx.entry.toolchain | Where-Object { $_ })
    $ok = $allowed -contains $value
    $text = "component_toolchain=$value | 允许值[$($ctx.entry.series)]: $(Join-List $allowed)"
    if (-not $ok) { $text += " | ❌ $value 不在允许列表中" }
    Add-Row $ctx.rows 'toolchain' $(if ($ok) { 'ok' } else { 'fail' }) $text
    if ($ctx.installedToolchains.Count -gt 0) {
        $usable = @($allowed | Where-Object { $ctx.installedToolchains -contains $_ })
        Add-Row $ctx.rows 'toolchain' 'info' "已安装工具链(ide-get-installed-toolchain): $(Join-List $ctx.installedToolchains)"
        if ($usable.Count -gt 0) { Add-Row $ctx.rows 'toolchain' 'info' "已安装且允许: $(Join-List $usable)" }
        else { Add-Row $ctx.rows 'toolchain' 'info' '已安装且允许: 无' }
        if (-not $ok) {
            if ($usable.Count -gt 0) {
                Add-Row $ctx.rows 'toolchain' 'info' "建议改为已安装且允许的工具链: $($usable[0])（通过 ide-set-project-build-property 修改 component_toolchain）"
            } else {
                Add-Row $ctx.rows 'toolchain' 'warn' '无已安装且允许的工具链（需要先安装对应工具链，或核对已安装列表）'
            }
        } elseif ($ctx.installedToolchains -notcontains $value) {
            Add-Row $ctx.rows 'toolchain' 'warn' "当前工具链 $value 不在已安装列表中（ide-get-installed-toolchain），请确认"
        }
    }
    return $ok
}

function Invoke-CheckAbi {
    param($ctx, [string]$value)
    $cores = @($ctx.entry.cores)
    $core = $ctx.core
    if ($null -ne $core) {
        $allowed = @($core.mabi | Where-Object { $_ })
        $ok = $allowed -contains $value
        $text = "riscvTargetProcessor.integer_ABI=$value | 允许值[$($ctx.entry.series) $($core.core)]: $(Join-List $allowed)"
        if (-not $ok) { $text += " | ❌ $value 不在允许列表中" }
        Add-Row $ctx.rows 'abi' $(if ($ok) { 'ok' } else { 'fail' }) $text
        return $ok
    }
    Add-Row $ctx.rows 'abi' 'info' "未指定内核，对芯片全部 $($cores.Count) 个内核逐一比对:"
    $anyPass = $false
    foreach ($c in $cores) {
        $allowed = @($c.mabi | Where-Object { $_ })
        $ok = $allowed -contains $value
        $anyPass = $anyPass -or $ok
        Add-Row $ctx.rows 'abi' $(if ($ok) { 'ok' } else { 'fail' }) "vs $($ctx.entry.series) $($c.core) mabi=[$(Join-List $allowed)]"
    }
    Add-Row $ctx.rows 'abi' $(if ($anyPass) { 'ok' } else { 'fail' }) $(if ($anyPass) { '结果: PASS（至少一个内核匹配）' } else { '结果: FAIL（所有内核均不匹配）' })
    return $anyPass
}

function Invoke-CheckStartfile {
    param($ctx, [string]$startupDir)
    $expected = @($ctx.chip.startfile | Where-Object { $_ })
    if ($expected.Count -eq 0) {
        Add-Row $ctx.rows 'startfile' 'info' "芯片 $($ctx.chipName) 在 mcu_isa.json 中 startfile 为空（[]），跳过校验"
        return $true
    }
    if (-not (Test-Path -LiteralPath $startupDir -PathType Container)) {
        Add-Row $ctx.rows 'startfile' 'fail' "Startup 目录不存在: $startupDir"
        return $false
    }
    $found = @(Get-ChildItem -LiteralPath $startupDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.ToUpper().EndsWith('.S') } |
        Select-Object -ExpandProperty Name | Sort-Object)
    $missing = @($expected | Where-Object { $_ -notin $found })
    $extra = @($found | Where-Object { $_ -notin $expected })
    if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
        Add-Row $ctx.rows 'startfile' 'ok' "Startup 目录 $startupDir 中的 .S 文件与 mcu_isa.json startfile 完全一致: $(Join-List $expected)"
        return $true
    }
    $msg = "Startup 目录 $startupDir 与 mcu_isa.json startfile 不一致（只提示，不修改） | 期望(startfile)=$(Join-List $expected) | 实际=$(Join-List $found)"
    if ($missing.Count -gt 0) { $msg += " | 缺少: $(Join-List $missing)" }
    if ($extra.Count -gt 0) { $msg += " | 多余: $(Join-List $extra)" }
    Add-Row $ctx.rows 'startfile' 'warn' $msg
    return $true  # startfile mismatch is WARN only, never FAILs
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Show-Usage {
    Write-Output '用法: check_march.ps1 --chip CH32H417WEU [--core v3f|v5f] [--march <arch>] [--toolchain <tc>] [--abi <abi>] [--startfile-dir <dir>] [--installed-toolchains GCC12,GCC15]'
    Write-Output '      check_march.ps1 --march <arch> --isa-ext i,m,a,c,xw   (手动指定扩展，不查 json)'
    Write-Output '      check_march.ps1 --selftest'
}

$argv = @($args)
$opts = @{}
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = $argv[$i]
    if ($a -like '--*') {
        $key = $a.Substring(2)
        $next = if ($i + 1 -lt $argv.Count) { $argv[$i + 1] } else { $null }
        if ($null -ne $next -and $next -notlike '--*') { $opts[$key] = $next; $i++ }
        else { $opts[$key] = $true }
    } elseif ($a -eq '-h') { $opts['help'] = $true }
}

if ($opts.ContainsKey('help')) { Show-Usage; exit 0 }

# -- selftest
if ($opts.ContainsKey('selftest')) {
    $cases = @(
        @('march PASS', $true,  'rv32imafc_zba_zbb_zbc_zbs_xw', @('i','m','a','c','f','zba','zbb','zbc','zbs','xw')),
        @('march FAIL d', $false, 'rv32imafdc_zba_zbb_zbc_zbs_xw', @('i','m','a','c','f','zba','zbb','zbc','zbs','xw')),
        @('march FAIL rv64', $false, 'rv64imac_xw', @('i','m','a','c','xw')),
        @('march FAIL z 扩展', $false, 'rv32imac_zba_zbb_zbc_zbs_xw', @('i','m','a','c','xw')),
        @('march FAIL 空', $false, 'rv32', @('i')),
        @('march 顺序无关', $true, 'rv32imafc_zba_zbb_zbc_zbs_xw', @('i','m','a','c','f','zba','zbb','zbc','zbs','xw'))
    )
    $failed = 0
    foreach ($c in $cases) {
        $got = (Test-March $c[2] $c[3])[0]
        $pass = ($got -eq $c[1])
        if (-not $pass) { $failed++ }
        $tag = if ($pass) { '✅' } else { '❌' }
        Write-Output ("{0} {1,-18} expect={2} got={3}" -f $tag, $c[0], $(if ($c[1]) { 'PASS' } else { 'FAIL' }), $(if ($got) { 'PASS' } else { 'FAIL' }))
    }
    Write-Output ''
    if ($failed -eq 0) { Write-Output '自测通过'; exit 0 }
    Write-Output "自测失败 $failed 项"
    exit 1
}

# -- march + manual isa-ext (no json lookup)
if ($opts.ContainsKey('march') -and $opts.ContainsKey('isa-ext') -and -not $opts.ContainsKey('chip')) {
    $isaExt = @($opts['isa-ext'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $r = Test-March $opts['march'] $isaExt
    $ok = $r[0]; $err = $r[1]; $parts = $r[2]; $missing = $r[3]
    Write-Output $DIVIDER
    Write-Output 'march 校验报告（手动指定 isa_ext）'
    Write-Output $DIVIDER
    Write-Output "march   : $($opts['march'])"
    if ($null -ne $parts) { Write-Output "拆分结果: $(Join-List $parts)" }
    Write-Output "isa_ext : $(Join-List $isaExt)"
    if ($err) { Write-Output "❌ [ERROR] $err"; exit 1 }
    if ($ok) { Write-Output "✅ PASS — 拆分出的 $($parts.Count) 项全部在 isa_ext 中"; exit 0 }
    Write-Output "❌ FAIL — 以下 $($missing.Count) 项不在 isa_ext 中: $(Join-List $missing)"
    exit 1
}

# -- chip-based checks
$hasCheck = $opts.ContainsKey('march') -or $opts.ContainsKey('toolchain') -or $opts.ContainsKey('abi') -or $opts.ContainsKey('startfile-dir')
if (-not $hasCheck) { Write-Output '[FATAL] 至少提供 --march / --toolchain / --abi / --startfile-dir 之一'; exit 1 }
if (-not $opts.ContainsKey('chip')) { Write-Output '[FATAL] 需要 --chip（或 march 校验时用 --isa-ext 代替）'; exit 1 }

try { $isa = Get-IsaData } catch { Write-Output "[FATAL] $_"; exit 1 }
$chipName = $opts['chip']
$coreSel = if ($opts.ContainsKey('core')) { [string]$opts['core'] } else { $null }
$found = Find-Chip $isa $chipName
$entry = $found[0]; $chip = $found[1]
if ($null -eq $chip) { Write-Output "[FATAL] 在 mcu_isa.json 中找不到型号 $chipName"; exit 1 }
$cores = @($entry.cores)
$core = $null
if ($coreSel) {
    $core = Pick-Core $cores $coreSel
    if ($null -eq $core) { Write-Output "[FATAL] 内核 $coreSel 不在芯片 $chipName 的 cores 中"; exit 1 }
}
$coreLabel = if ($coreSel) { $core.core } else { '全部内核' }
$installedToolchains = @()
if ($opts.ContainsKey('installed-toolchains')) {
    $installedToolchains = @($opts['installed-toolchains'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$ctx = @{ chipName = $chipName; coreSel = $coreSel; entry = $entry; chip = $chip; rows = (New-Rows); core = $core; installedToolchains = $installedToolchains }

Write-Output $DIVIDER
Write-Output "编译配置校验报告（$($chip.name) / 系列 $($entry.series) / 内核 $coreLabel）"
Write-Output $DIVIDER
if ($opts.ContainsKey('march')) { [void](Invoke-CheckMarch $ctx $opts['march']) }
if ($opts.ContainsKey('toolchain')) { [void](Invoke-CheckToolchain $ctx $opts['toolchain']) }
if ($opts.ContainsKey('abi')) { [void](Invoke-CheckAbi $ctx $opts['abi']) }
if ($opts.ContainsKey('startfile-dir')) { [void](Invoke-CheckStartfile $ctx $opts['startfile-dir']) }
$marks = @{ ok = '✅'; fail = '❌'; warn = '⚠'; info = 'ℹ' }
$totalOk = $true
foreach ($row in $ctx.rows) {
    if ($row.verdict -eq 'fail') { $totalOk = $false }
    Write-Output "  $($marks[$row.verdict]) [$($row.name)] $($row.text)"
}
Write-Output ''
if ($totalOk) { Write-Output '结论: ✅ PASS — 全部校验通过'; exit 0 }
Write-Output '结论: ❌ FAIL — 存在不匹配项'
exit 1
