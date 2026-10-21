#!/usr/bin/env pwsh
# check_debug.ps1 - Pre-debug checks for WCH RISC-V projects (PowerShell implementation).
#
# Logic:
#   Rule 1  FLASH/RAM capacity: parse link.ld MEMORY block, sum LENGTH of FLASH*/RAM*
#           regions, each total must be LESS THAN OR EQUAL to the chip max in mcu_isa.json
#           (total <= max; greater than max = FAIL).
#   Rule 2  ROM/RAM-configurable chips: pass --ram-avail <value> read from the current
#           hardware configuration; check total RAM <= that value (reported only when
#           the argument is given; the skill decides whether it is needed).
#   Rule 3  FLASH start address detection (report only, never FAILs): when any link.ld
#           has FLASH ORIGIN != 0, a WARN is emitted - the skill must then ASK the user
#           whether a program exists at address 0 (none -> WCH chip cannot run, remind to
#           fix; yes -> usually IAP+APP, enable page erase when debugging).
#   Breakpoints: read the chip's maxbreakpoint field from mcu_isa.json (optional/empty =
#           no limit; non-empty = max supported breakpoints); --breakpoints <n> hard-checks.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_debug.ps1 <link.ld> [link.ld2] \
#       --chip CH32H417WEU [--core v3f|v5f|single|auto] [--ram-avail 896K] [--breakpoints 3] [--quiet]
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_debug.ps1 --selftest
#
# mcu_isa.json is always loaded from the same directory as this script (skill dir).
# Exit code: 0 = PASS; 1 = FAIL (rule 1/rule 2/breakpoint limit); 2 = FATAL.

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$SIZE_UNITS = @{ 'K' = 1024; 'M' = 1024 * 1024; 'G' = 1024 * 1024 * 1024 }
$NUM_RE = '(?:0[xX][0-9a-fA-F]+|\d+)(?:[KMG])?'
$MEM_REGEX = '(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?<attrs>[^)]*)\)\s*:\s*ORIGIN\s*=\s*(?<origin>[^,]+),\s*LENGTH\s*=\s*(?<length>[^,\n]+)'

# ---------------------------------------------------------------------------
# Expression calculator
# ---------------------------------------------------------------------------
function ConvertFrom-LdToken {
    param([string]$tok)
    $m = [regex]::Match($tok, '^(0[xX][0-9a-fA-F]+|\d+)([KMG])?$')
    if (-not $m.Success) { throw "invalid number: $tok" }
    $num = $m.Groups[1].Value
    $isHex = $num.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)
    $digits = if ($isHex) { $num.Substring(2) } else { $num }
    $v = [Convert]::ToInt64($digits, $(if ($isHex) { 16 } else { 10 }))
    $u = $m.Groups[2].Value.ToUpper()
    if ($u -and $SIZE_UNITS.ContainsKey($u)) { $v = $v * $SIZE_UNITS[$u] }
    return $v
}

function Get-LdTokens {
    param([string]$s)
    $toks = [System.Collections.Generic.List[string]]::new()
    $numRx = [regex]::new($NUM_RE)
    $i = 0; $n = $s.Length
    while ($i -lt $n) {
        $c = $s[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        $two = if ($i + 1 -lt $n) { $s.Substring($i, 2) } else { [string]$c }
        if ($two -eq '<<' -or $two -eq '>>') { $toks.Add($two); $i += 2; continue }
        if ($two -eq '&&' -or $two -eq '||') { throw "unsupported operator: $two" }
        if ('+-*/%&|^~()'.Contains($c)) { $toks.Add([string]$c); $i++; continue }
        $m = $numRx.Match($s, $i)
        if ($m.Success) { $toks.Add($m.Value.ToUpper()); $i = $m.Index + $m.Length; continue }
        throw "unrecognized char: $c"
    }
    return $toks
}

function Get-LdPeek { param($st) if ($st.i -lt $st.toks.Count) { return $st.toks[$st.i] }; return $null }
function Move-LdNext { param($st) $t = Get-LdPeek $st; $st.i++; return $t }

function Invoke-LdOrExpr  { param($st) $v = Invoke-LdXorExpr $st; while ((Get-LdPeek $st) -eq '|') { Move-LdNext $st | Out-Null; $v = $v -bor (Invoke-LdXorExpr $st) }; return $v }
function Invoke-LdXorExpr { param($st) $v = Invoke-LdAndExpr $st; while ((Get-LdPeek $st) -eq '^') { Move-LdNext $st | Out-Null; $v = $v -bxor (Invoke-LdAndExpr $st) }; return $v }
function Invoke-LdAndExpr { param($st) $v = Invoke-LdShiftExpr $st; while ((Get-LdPeek $st) -eq '&') { Move-LdNext $st | Out-Null; $v = $v -band (Invoke-LdShiftExpr $st) }; return $v }
function Invoke-LdShiftExpr {
    param($st)
    $v = Invoke-LdAddExpr $st
    $op = Get-LdPeek $st
    while ($op -eq '<<' -or $op -eq '>>') {
        Move-LdNext $st | Out-Null
        $r = Invoke-LdAddExpr $st
        if ($r -lt 0 -or $r -gt 63) { throw 'invalid shift amount' }
        $v = if ($op -eq '<<') { $v -shl $r } else { $v -shr $r }
        $op = Get-LdPeek $st
    }
    return $v
}
function Invoke-LdAddExpr {
    param($st)
    $v = Invoke-LdMulExpr $st
    $op = Get-LdPeek $st
    while ($op -eq '+' -or $op -eq '-') {
        Move-LdNext $st | Out-Null
        $r = Invoke-LdMulExpr $st
        $v = if ($op -eq '+') { $v + $r } else { $v - $r }
        $op = Get-LdPeek $st
    }
    return $v
}
function Invoke-LdMulExpr {
    param($st)
    $v = Invoke-LdUnary $st
    $op = Get-LdPeek $st
    while ($op -eq '*' -or $op -eq '/' -or $op -eq '%') {
        Move-LdNext $st | Out-Null
        $r = Invoke-LdUnary $st
        if ($op -eq '*') { $v = $v * $r }
        elseif ($op -eq '/') {
            if ($r -eq 0) { throw 'divide by 0' }
            $v = [long][math]::Floor($v / $r)
        } else {
            if ($r -eq 0) { throw 'modulo 0' }
            $v = $v % $r
        }
        $op = Get-LdPeek $st
    }
    return $v
}
function Invoke-LdUnary {
    param($st)
    $t = Get-LdPeek $st
    if ($t -eq '-' -or $t -eq '~') {
        Move-LdNext $st | Out-Null
        $v = Invoke-LdUnary $st
        return $(if ($t -eq '-') { -$v } else { -bnot $v })
    }
    return Invoke-LdPrimary $st
}
function Invoke-LdPrimary {
    param($st)
    $t = Move-LdNext $st
    if ($null -eq $t) { throw 'incomplete expression' }
    if ($t -eq '(') {
        $v = Invoke-LdOrExpr $st
        if ((Move-LdNext $st) -ne ')') { throw 'missing closing paren' }
        return $v
    }
    return ConvertFrom-LdToken $t
}

function Get-CalcLength {
    param([string]$Expr)
    $s = (($Expr -replace '^\s+|\s+$', '')).TrimEnd(';').Trim()
    if (-not $s) { return $null }
    try {
        # @() 强制数组：防止单 token 结果被 PowerShell 解包成字符串
        $toks = @(Get-LdTokens $s)
        $st = @{ toks = $toks; i = 0 }
        $v = Invoke-LdOrExpr $st
        if ($st.i -lt $toks.Count) { return $null }
        return $v
    } catch { return $null }
}

function Get-FmtSize {
    param($n)
    if ($null -eq $n) { return '?' }
    if ($n -ge 1048576) {
        $v = $n / 1048576.0
        if ($v -eq [math]::Floor($v)) { return ('{0}M' -f [long]$v) }
        return ('{0:F1}M' -f $v)
    }
    if ($n -ge 1024) {
        $v = $n / 1024.0
        if ($v -eq [math]::Floor($v)) { return ('{0}K' -f [long]$v) }
        return ('{0:F1}K' -f $v)
    }
    return "$n"
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
function New-Report {
    # 逗号包裹：空 List 经函数返回会被枚举成无输出（$null）
    return ,([System.Collections.Generic.List[object]]::new())
}
function Add-Ok   { param($rep, [string]$msg) $rep.Add(@{ mark = 'ok'; text = "  $([char]0x2705) $msg" }) }
function Add-Warn { param($rep, [string]$msg) $rep.Add(@{ mark = 'warn'; text = "  $([char]0x26A0) [WARN] $msg" }) }
function Add-Err  { param($rep, [string]$msg) $rep.Add(@{ mark = 'err'; text = "  $([char]0x274C) [ERROR] $msg" }) }
function Add-Info { param($rep, [string]$msg) $rep.Add(@{ mark = 'info'; text = "  $([char]0x2139) [INFO] $msg" }) }

# ---------------------------------------------------------------------------
# mcu_isa.json / link.ld helpers
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

function Get-AutoChip {
    param([string]$path, [string]$text)
    foreach ($src in @($path, $text)) {
        foreach ($m in [regex]::Matches($src, 'CH32[A-Z0-9]+')) {
            $cand = $m.Value.ToUpper()
            if ($cand.Length -ge 6) { return $cand }
        }
    }
    return $null
}

function Remove-LdComments {
    param([string]$text)
    $eval = { param($m) $nl = ($m.Value.ToCharArray() | Where-Object { $_ -eq "`n" }).Count; return ("`n" * $nl) }
    $t = [regex]::Replace($text, '/\*.*?\*/', $eval, 'Singleline')
    return [regex]::Replace($t, '//[^\n]*', '')
}

function Get-RegionKind {
    param([string]$name)
    $n = $name.ToUpper()
    if ($n.StartsWith('FLASH')) { return 'flash' }
    if ($n.StartsWith('RAM')) { return 'ram' }
    return $null
}

function Get-LineNo {
    param([string]$text, [int]$endIndex)
    $nl = 0
    for ($k = 0; $k -lt $endIndex; $k++) { if ($text[$k] -eq "`n") { $nl++ } }
    return $nl + 1
}

function Get-KindTotal {
    param($recs)
    $total = [long]0
    foreach ($r in $recs) { if ($null -eq $r.length) { return $null }; $total += $r.length }
    return $total
}

function Invoke-ParseLd {
    param([string]$path, $rep)
    # returns @(flashTotal, ramTotal, firstFlashOrigin, firstFlashLine) or $null
    if (-not (Test-Path -LiteralPath $path)) { Add-Err $rep "文件不存在: $path"; return $null }
    try { $text = ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n") } catch { Add-Err $rep "读取失败 ${path}: $_"; return $null }
    # 注：读取后统一换行（\r\n、\r -> \n），避免 CRLF/CR 行尾导致行粘连、解析/行号出错
    $clean = Remove-LdComments $text
    $memMatch = [regex]::Match($clean, 'MEMORY\s*\{')
    if (-not $memMatch.Success) { Add-Err $rep "无法定位 MEMORY 块: $path"; return $null }
    $memOpen = $clean.IndexOf('{', $memMatch.Index)
    $depth = 1; $i = $memOpen + 1
    while ($i -lt $clean.Length -and $depth -gt 0) {
        if ($clean[$i] -eq '{') { $depth++ }
        elseif ($clean[$i] -eq '}') { $depth-- }
        $i++
    }
    $memText = $clean.Substring($memOpen, $i - $memOpen)
    $regions = [System.Collections.Generic.List[object]]::new()
    foreach ($m in [regex]::Matches($memText, $MEM_REGEX)) {
        $name = $m.Groups['name'].Value
        $attrs = $m.Groups['attrs'].Value
        $originS = $m.Groups['origin'].Value.Trim()
        $lengthS = $m.Groups['length'].Value.Trim()
        $lineNo = Get-LineNo $clean ($memOpen + $m.Index)
        $origin = Get-CalcLength $originS
        $length = Get-CalcLength $lengthS
        $regions.Add(@{ name = $name; attrs = $attrs; origin = $origin; length = $length; originS = $originS; lengthS = $lengthS; line = $lineNo; kind = (Get-RegionKind $name) })
        $oTxt = if ($null -eq $origin) { $originS } else { "$originS (= $origin)" }
        $lTxt = if ($null -eq $length) { $lengthS } else { "$lengthS (= $length)" }
        Add-Info $rep "MEMORY $name($attrs): ORIGIN = $oTxt, LENGTH = $lTxt (第${lineNo}行)"
    }
    $flashRecs = @($regions | Where-Object { $_.kind -eq 'flash' })
    $ramRecs = @($regions | Where-Object { $_.kind -eq 'ram' })
    $flashTotal = Get-KindTotal $flashRecs
    $ramTotal = Get-KindTotal $ramRecs
    if ($flashRecs.Count -eq 0) { Add-Err $rep 'MEMORY 中缺少 FLASH 区域'; return $null }
    if ($ramRecs.Count -eq 0) { Add-Err $rep 'MEMORY 中缺少 RAM 区域'; return $null }
    if ($null -ne $flashTotal) {
        Add-Info $rep "FLASH 区域 $($flashRecs.Count) 个，LENGTH 合计: $(($flashRecs | ForEach-Object { $_.lengthS }) -join ' + ') = $(Get-FmtSize $flashTotal)"
    }
    if ($null -ne $ramTotal) {
        Add-Info $rep "RAM 区域 $($ramRecs.Count) 个，LENGTH 合计: $(($ramRecs | ForEach-Object { $_.lengthS }) -join ' + ') = $(Get-FmtSize $ramTotal)"
    }
    $first = $flashRecs[0]
    return @($flashTotal, $ramTotal, $first.origin, $first.line)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Show-Usage {
    Write-Output '用法: check_debug.ps1 <link.ld> [link.ld2] --chip CH32H417WEU [--core v3f|v5f|single|auto] [--ram-avail <值>] [--breakpoints <n>] [--quiet]'
    Write-Output '      check_debug.ps1 --selftest'
}

$argv = @($args)
$files = [System.Collections.Generic.List[string]]::new()
$chip = $null; $core = 'auto'; $ramAvail = $null; $breakpoints = $null; $quiet = $false
for ($i = 0; $i -lt $argv.Count; $i++) {
    switch ($argv[$i]) {
        '--chip' { $chip = $argv[$i + 1]; $i++ }
        '--core' { $core = $argv[$i + 1]; $i++ }
        '--ram-avail' { $ramAvail = $argv[$i + 1]; $i++ }
        '--breakpoints' { $breakpoints = [int]$argv[$i + 1]; $i++ }
        '--quiet' { $quiet = $true }
        '--selftest' { $optsSelftest = $true }
        '-h' { Show-Usage; exit 0 }
        '--help' { Show-Usage; exit 0 }
        default {
            if ($argv[$i] -like '--*') { Write-Output "[FATAL] 未知参数: $($argv[$i])"; exit 2 }
            $files.Add($argv[$i])
        }
    }
}

if ($optsSelftest) {
    $cases = @(
        @('480K', 491520), @('0x3FC00', 261120), @('64K*2', 131072),
        @('448K - 256', 458496), @('1M/2', 524288), @('0x1000+0x2000', 12288), @('ALIGN(4)', $null)
    )
    $failed = 0
    foreach ($c in $cases) {
        $got = Get-CalcLength $c[0]
        $gotTxt = if ($null -eq $got) { 'None' } else { $got }
        $expTxt = if ($null -eq $c[1]) { 'None' } else { $c[1] }
        $ok = ($got -eq $c[1])
        if (-not $ok) { $failed++ }
        Write-Output ("{0} calc_length({1,-14}) = {2}  expect={3}" -f $(if ($ok) { '✅' } else { '❌' }), $c[0], $gotTxt, $expTxt)
    }
    Write-Output ''
    if ($failed -eq 0) { Write-Output '自测通过'; exit 0 }
    Write-Output "自测失败 $failed 项"
    exit 1
}

if ($files.Count -lt 1) { Write-Output '[FATAL] 至少提供 1 个 link.ld 路径'; exit 2 }
try { $isa = Get-IsaData } catch { Write-Output "[FATAL] $_"; exit 2 }

if (-not $chip) {
    $text = ([System.IO.File]::ReadAllText($files[0], [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n")
    $chip = Get-AutoChip $files[0] $text
}
if (-not $chip) { Write-Output '[FATAL] 无法推断芯片型号，请用 --chip 指定'; exit 2 }
$found = Find-Chip $isa $chip
$series = $found[0]; $chipEntry = $found[1]
if ($null -eq $chipEntry) { Write-Output "[FATAL] 在 mcu_isa.json 中找不到型号 $chip"; exit 2 }
$maxFlash = Get-CalcLength $chipEntry.flash
$maxSram = Get-CalcLength $chipEntry.sram

$rep = New-Report
Add-Info $rep "芯片: $chip（系列 $($series.series)）| 最大 flash=$($chipEntry.flash), sram=$($chipEntry.sram)"

$totalFlash = [long]0; $totalRam = [long]0
$flashOk = $true; $ramOk = $true
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) { [Console]::Error.WriteLine("[FATAL] 文件不存在: $f"); exit 2 }
    Add-Info $rep "文件: $f"
    $r = Invoke-ParseLd $f $rep
    if ($null -eq $r) { exit 2 }
    if ($null -eq $r[0]) { Add-Err $rep 'FLASH LENGTH 存在无法计算的值（含符号/函数）'; $flashOk = $false }
    else { $totalFlash += $r[0] }
    if ($null -eq $r[1]) { Add-Err $rep 'RAM LENGTH 存在无法计算的值（含符号/函数）'; $ramOk = $false }
    else { $totalRam += $r[1] }
    if ($null -ne $r[2] -and $r[2] -ne 0) {
        Add-Warn $rep "[规则3] $f 的 FLASH 起始地址 0x$('{0:X8}' -f $r[2]) ≠ 0（第$($r[3])行）——需询问用户 0 地址是否有程序：无程序 → WCH 芯片程序无法运行，提醒修改起始地址；有程序 → 多为 IAP+APP，调试当前程序需开启页擦"
    }
}
Add-Info $rep "总 FLASH 合计: $(Get-FmtSize $totalFlash) | 总 RAM 合计: $(Get-FmtSize $totalRam)"

# 规则1：小于等于上限
if ($flashOk -and $null -ne $maxFlash) {
    if ($totalFlash -gt $maxFlash) { Add-Err $rep "[规则1] FLASH 合计 $(Get-FmtSize $totalFlash) > 芯片最大 $(Get-FmtSize $maxFlash)（必须小于等于上限）" }
    else { Add-Ok $rep "[规则1] FLASH 合计 $(Get-FmtSize $totalFlash) <= 芯片最大 $(Get-FmtSize $maxFlash)" }
}
if ($ramOk -and $null -ne $maxSram) {
    if ($totalRam -gt $maxSram) { Add-Err $rep "[规则1] RAM 合计 $(Get-FmtSize $totalRam) > 芯片最大 $(Get-FmtSize $maxSram)（必须小于等于上限）" }
    else { Add-Ok $rep "[规则1] RAM 合计 $(Get-FmtSize $totalRam) <= 芯片最大 $(Get-FmtSize $maxSram)" }
}

# 规则2：ROM/RAM 可配置芯片，总 RAM <= 硬件配置读到的值
if ($ramAvail) {
    $ramAvailVal = Get-CalcLength $ramAvail
    if ($null -eq $ramAvailVal) { Add-Err $rep "[规则2] --ram-avail 无法解析: $ramAvail" }
    elseif ($ramOk) {
        if ($totalRam -le $ramAvailVal) { Add-Ok $rep "[规则2] RAM 合计 $(Get-FmtSize $totalRam) <= 硬件配置 RAM $(Get-FmtSize $ramAvailVal)" }
        else { Add-Err $rep "[规则2] RAM 合计 $(Get-FmtSize $totalRam) > 硬件配置 RAM $(Get-FmtSize $ramAvailVal)" }
    }
} else {
    Add-Info $rep '[规则2] 未提供 --ram-avail（skill 应先调用 ide-debug-support-memory-allocation 确认支持，再调用 ide-debug-read-memory-allocation 读取 RAM 值传入比对；不支持则跳过）'
}

# 断点上限：maxbreakpoint（缺失/空数组/为空 = 不限制）
$maxbp = $chipEntry.maxbreakpoint
# 兼容 mcu_isa.json 的数组形式：[] = 不限制；[4] = 上限 4；标量（4 / "4"）直接用
if ($maxbp -is [System.Array]) { $maxbp = if ($maxbp.Count -gt 0) { $maxbp[0] } else { $null } }
if ($null -eq $maxbp -or "$maxbp".Trim() -eq '') {
    Add-Info $rep '[断点] maxbreakpoint 未配置（不限制断点数量）'
} else {
    $maxbpInt = [int]$maxbp
    Add-Info $rep "[断点] maxbreakpoint = $maxbpInt（调试时设置断点不得超过该值）"
    if ($null -ne $breakpoints) {
        if ($breakpoints -le $maxbpInt) { Add-Ok $rep "[断点] 计划断点数 $breakpoints <= 上限 $maxbpInt" }
        else { Add-Err $rep "[断点] 计划断点数 $breakpoints > 上限 $maxbpInt（请减少断点）" }
    }
}

Write-Output ''
Write-Output ('=' * 72)
Write-Output '调试前检查报告'
Write-Output ('=' * 72)
$totalErr = 0; $totalWarn = 0
foreach ($row in $rep) {
    if ($row.mark -eq 'err') { $totalErr++ }
    elseif ($row.mark -eq 'warn') { $totalWarn++ }
    if ($quiet -and $row.mark -eq 'info') { continue }
    Write-Output $row.text
}
Write-Output ''
if ($totalErr -gt 0) {
    Write-Output "❌ 结论: FAIL（$totalErr 个错误, $totalWarn 个警告）"
    exit 1
}
Write-Output "✅ 结论: PASS（$totalWarn 个警告）"
exit 0
