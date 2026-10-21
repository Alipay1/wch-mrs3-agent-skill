#!/usr/bin/env pwsh
# validate_linkld.ps1 - Validate WCH RISC-V project link.ld linker scripts (PowerShell implementation).
#
# Logic is identical to validate_linkld.py:
#   1. Parse FLASH/RAM regions in the MEMORY block (supports multi-region FLASH/FLASH2, RAM/RAM2);
#   2. LENGTH supports expressions (448K - 256, 0x3FC00, 64K*2, ...) - built-in mini calculator
#      converts everything to decimal bytes for comparison only, never rewrites the ld file;
#   3. Sum LENGTH of all same-kind regions, compare against the chip limit in mcu_isa.json
#      (same directory as this script; no path argument accepted) -> over limit = ERROR;
#   4. Dual-core (V3F/V5F, two scripts) combined check;
#   5. __global_pointer$ missing -> INFO (does not fail);
#   6. Syntax: bracket pairing, MEMORY line format, region references, assignment semicolons,
#      operator spacing (comments/wildcards not checked; expressions with numeric literals on
#      BOTH sides of an operator are NOT checked and NEVER computed - kept verbatim).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File validate_linkld.ps1 <link.ld> [link.ld2] \
#       [--chip CH32H417WEU] [--core v3f|v5f|single|auto] [--quiet]
# Exit code: 0 = PASS; 1 = ERROR(s) found; 2 = FATAL (file/config missing, chip undetectable).

# Force UTF-8 output so Chinese/emoji render correctly in GBK consoles and UTF-8 terminals
# (Git Bash / opencode) alike.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$SIZE_UNITS = @{ 'K' = 1024; 'M' = 1024 * 1024; 'G' = 1024 * 1024 * 1024 }
$DUAL_CORE_SERIES = @('CH32H415', 'CH32H416', 'CH32H417')

$NUM_RE = '(?:0[xX][0-9a-fA-F]+|\d+)(?:[KMG])?'
# MEMORY region definition line: name(attrs) : ORIGIN = <expr>, LENGTH = <expr>
$MEM_REGEX = '(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?<attrs>[^)]*)\)\s*:\s*ORIGIN\s*=\s*(?<origin>[^,]+),\s*LENGTH\s*=\s*(?<length>[^,\n]+)'
$REGION_FORMAT_RE = '^[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\)\s*:\s*ORIGIN\s*=\s*.+,\s*LENGTH\s*=\s*.+$'

# ---------------------------------------------------------------------------
# Expression calculator: ld LENGTH/ORIGIN expression -> decimal bytes
# ---------------------------------------------------------------------------
function ConvertFrom-LdToken {
    param([string]$tok)
    # '448K' / '0x3FC00' / '1M' -> [long]; throws on invalid
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

function Invoke-LdOrExpr { param($st) $v = Invoke-LdXorExpr $st; while ((Get-LdPeek $st) -eq '|') { Move-LdNext $st | Out-Null; $v = $v -bor (Invoke-LdXorExpr $st) }; return $v }
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
    # ld length/address expression -> decimal bytes; $null when uncomputable
    # (contains symbols/functions such as ORIGIN(RAM), ALIGN(4)).
    $s = (($Expr -replace '^\s+|\s+$', '')).TrimEnd(';').Trim()
    if (-not $s) { return $null }
    try {
        # @() 强制数组：PowerShell 函数返回集合会被枚举展开，单元素结果会解包成
        # 字符串导致 $toks[0] 取到字符而非完整 token。
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

function Test-NumberToken {
    param([string]$tok)
    return ($tok -match "^$NUM_RE$")
}

# ---------------------------------------------------------------------------
# Report helpers
# ---------------------------------------------------------------------------
function New-Report {
    return @{ Lines = [System.Collections.Generic.List[string]]::new(); Errors = 0; Warns = 0 }
}
function Add-Ok    { param($rep, [string]$msg) $rep.Lines.Add("  $([char]0x2705) $msg") }
function Add-Warn  { param($rep, [string]$msg) $rep.Warns++; $rep.Lines.Add("  $([char]0x26A0) [WARN] $msg") }
function Add-Err   { param($rep, [string]$msg) $rep.Errors++; $rep.Lines.Add("  $([char]0x274C) [ERROR] $msg") }
function Add-Info  { param($rep, [string]$msg) $rep.Lines.Add("  $([char]0x2139) [INFO] $msg") }

# ---------------------------------------------------------------------------
# ld text helpers
# ---------------------------------------------------------------------------
function Remove-LdComments {
    param([string]$text)
    # Strip /* */ (incl. multi-line) and // comments; keep newlines so line numbers stay valid.
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

function Get-LineOffsets {
    param([string[]]$lines)
    $offsets = [System.Collections.Generic.List[int]]::new()
    $off = 0
    foreach ($line in $lines) { $offsets.Add($off); $off += $line.Length + 1 }
    # 逗号包裹：防止返回时被枚举展开/解包（单元素时变 int 会导致 $offsets[$idx] 报错）
    return ,$offsets
}

# ---------------------------------------------------------------------------
# Syntax checks
# ---------------------------------------------------------------------------
function Invoke-SyntaxCheck {
    param([string]$text, $regionNames, [int]$memOpen, [int]$memEnd, $rep)
    $clean = Remove-LdComments $text

    # 1) bracket pairing
    foreach ($pair in @(@('{', '}', '花括号'), @('(', ')', '圆括号'), @('[', ']', '方括号'))) {
        $o = ($clean.ToCharArray() | Where-Object { $_ -eq $pair[0] }).Count
        $c = ($clean.ToCharArray() | Where-Object { $_ -eq $pair[1] }).Count
        if ($o -ne $c) { Add-Err $rep "$($pair[2])不配对: $($pair[0]) $o 个 vs $($pair[1]) $c 个" }
    }

    # 2) MEMORY line format (skip blank lines and the { } wrapper lines)
    $lines = $clean -split "`n"
    $offsets = Get-LineOffsets $lines
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $lineOff = $offsets[$idx]
        if ($lineOff -lt $memOpen -or $lineOff -ge $memEnd) { continue }
        $s = $lines[$idx].Trim()
        if (-not $s -or $s -match '^[{}]\s*$') { continue }
        if ($s -match $REGION_FORMAT_RE) { continue }
        Add-Err $rep "MEMORY 块中存在无法解析的行（第$($idx + 1)行）: $s"
    }

    # 3) region references: >region / AT>region / ORIGIN(region) / LENGTH(region)
    foreach ($m in [regex]::Matches($clean, '(?:AT\s*)?>\s*([A-Za-z_][A-Za-z0-9_]*)')) {
        $name = $m.Groups[1].Value
        if (-not $regionNames.Contains($name)) {
            $ln = Get-LineNo $clean $m.Index
            Add-Warn $rep "引用了未定义的 MEMORY 区域: $name（第${ln}行，可能来自 INCLUDE 文件）"
        }
    }
    foreach ($m in [regex]::Matches($clean, '\b(ORIGIN|LENGTH)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)')) {
        $name = $m.Groups[2].Value
        if (-not $regionNames.Contains($name)) {
            $ln = Get-LineNo $clean $m.Index
            Add-Warn $rep "$($m.Groups[1].Value)($name) 引用了未定义的 MEMORY 区域（第${ln}行，可能来自 INCLUDE 文件）"
        }
    }
}

function Invoke-SemicolonCheck {
    param([string]$text, [int]$memOpen, [int]$memEnd, $rep)
    $clean = Remove-LdComments $text
    $lines = $clean -split "`n"
    $offsets = Get-LineOffsets $lines
    $contEnd = '+-*/%&|^<>=,('
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $lineOff = $offsets[$idx]
        if ($lineOff -ge $memOpen -and $lineOff -lt $memEnd) { continue }
        $s = $lines[$idx].Trim()
        if (-not $s -or $s.Contains('{') -or $s.Contains('}')) { continue }
        if (-not $s.Contains('=')) { continue }
        if ($s.EndsWith(';') -or $s.EndsWith($contEnd.ToCharArray())) { continue }
        Add-Warn $rep "赋值语句缺少分号（第$($idx + 1)行）: $s"
    }
}

function Test-BothNumeric {
    param([string]$s, [int]$i, [int]$opLen)
    # Are both sides of the operator numeric literals (e.g. 64K*2, 0x1000+0x2000)?
    # If so: do NOT check spacing, NEVER compute the final value, keep verbatim.
    $j = $i - 1
    while ($j -ge 0 -and ($s[$j] -match '[A-Za-z0-9_.]')) { $j-- }
    $lt = $s.Substring($j + 1, ($i - 1) - $j)
    $j = $i + $opLen
    while ($j -lt $s.Length -and ($s[$j] -match '[A-Za-z0-9_.]')) { $j++ }
    $rt = $s.Substring($i + $opLen, $j - ($i + $opLen))
    return ($lt -and $rt -and (Test-NumberToken $lt) -and (Test-NumberToken $rt))
}

function Invoke-SpacingCheck {
    param([string]$text, $rep)
    # Operators (= + - / % << >> & | ^) must have whitespace on both sides (ERROR, fixable).
    # Not checked: comments (stripped), wildcards (*), /DISCARD/ style section names,
    # unary minus, and expressions with numeric literals on both sides (kept verbatim).
    $clean = Remove-LdComments $text
    $lines = $clean -split "`n"
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $s = $lines[$idx].Trim()
        if (-not $s) { continue }
        if ($s -match '^/[A-Za-z0-9_]+/\s*:') { continue }
        $bad = [System.Collections.Generic.List[string]]::new()
        $i = 0; $n = $s.Length
        while ($i -lt $n) {
            $two = if ($i + 1 -lt $n) { $s.Substring($i, 2) } else { '' }
            if ($two -eq '<<' -or $two -eq '>>' -or $two -eq '&&' -or $two -eq '||') {
                if (Test-BothNumeric $s $i 2) { $i += 2; continue }
                $prevWs = ($i -eq 0) -or [char]::IsWhiteSpace($s[$i - 1])
                $nextWs = ($i + 2 -ge $n) -or [char]::IsWhiteSpace($s[$i + 2])
                if (-not ($prevWs -and $nextWs)) { $bad.Add($two) }
                $i += 2; continue
            }
            $ch = $s[$i]
            if ($ch -eq '&' -or $ch -eq '|' -or $ch -eq '^') {
                if (Test-BothNumeric $s $i 1) { $i++; continue }
                $prevWs = ($i -eq 0) -or [char]::IsWhiteSpace($s[$i - 1])
                $nextWs = ($i + 1 -ge $n) -or [char]::IsWhiteSpace($s[$i + 1])
                if (-not ($prevWs -and $nextWs)) { $bad.Add([string]$ch) }
                $i++; continue
            }
            if ($ch -eq '=') {
                if ($i + 1 -lt $n -and $s[$i + 1] -eq '=') { $i += 2; continue }
                if ($i -gt 0 -and '=!<>'.Contains($s[$i - 1])) { $i++; continue }
                if (Test-BothNumeric $s $i 1) { $i++; continue }
                $prevWs = ($i -eq 0) -or [char]::IsWhiteSpace($s[$i - 1])
                $nextWs = ($i + 1 -ge $n) -or [char]::IsWhiteSpace($s[$i + 1])
                if (-not ($prevWs -and $nextWs)) { $bad.Add('=') }
                $i++; continue
            }
            if ($ch -eq '+' -or $ch -eq '/') {
                # /DISCARD/ style: '/' followed by non-space and another '/' later in the line
                if ($ch -eq '/' -and $i + 1 -lt $n -and -not [char]::IsWhiteSpace($s[$i + 1]) -and $s.Substring($i + 1).Contains('/')) { $i++; continue }
                if (Test-BothNumeric $s $i 1) { $i++; continue }
                $prevWs = ($i -eq 0) -or [char]::IsWhiteSpace($s[$i - 1])
                $nextWs = ($i + 1 -ge $n) -or [char]::IsWhiteSpace($s[$i + 1])
                if (-not ($prevWs -and $nextWs)) { $bad.Add([string]$ch) }
                $i++; continue
            }
            if ($ch -eq '-') {
                $unary = ($i -eq 0) -or [char]::IsWhiteSpace($s[$i - 1]) -or $s[$i - 1] -eq '(' -or $s[$i - 1] -eq '=' -or $s[$i - 1] -eq ',' -or $s[$i - 1] -eq '[' -or $s[$i - 1] -eq ':'
                if (-not $unary) {
                    if (Test-BothNumeric $s $i 1) { $i++; continue }
                    $prevWs = ($i -eq 0) -or [char]::IsWhiteSpace($s[$i - 1])
                    $nextWs = ($i + 1 -ge $n) -or [char]::IsWhiteSpace($s[$i + 1])
                    if (-not ($prevWs -and $nextWs)) { $bad.Add('-') }
                }
                $i++; continue
            }
            if ($ch -eq '%') {
                if (Test-BothNumeric $s $i 1) { $i++; continue }
                $prevWs = ($i -eq 0) -or [char]::IsWhiteSpace($s[$i - 1])
                $nextWs = ($i + 1 -ge $n) -or [char]::IsWhiteSpace($s[$i + 1])
                if (-not ($prevWs -and $nextWs)) { $bad.Add('%') }
                $i++; continue
            }
            $i++
        }
        if ($bad.Count -gt 0) {
            $uniq = @($bad | Select-Object -Unique)
            Add-Err $rep "运算符两侧必须加空格（第$($idx + 1)行）: $s  [运算符: $($uniq -join ' ')]"
        }
    }
}

function Invoke-GlobalPointerCheck {
    param([string]$text, $rep)
    $clean = Remove-LdComments $text
    if ($clean.Contains('__global_pointer$')) {
        Add-Ok $rep '检测到 __global_pointer$ 符号'
    } else {
        Add-Info $rep '未检测到 __global_pointer$ 符号（RISC-V GP 优化通常需要定义 __global_pointer$ = . + 0x800;）'
    }
}

# ---------------------------------------------------------------------------
# mcu_isa.json helpers
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

function Get-AutoCore {
    param([string]$path)
    if ($path -match '[Vv]3[Ff]') { return 'v3f' }
    if ($path -match '[Vv]5[Ff]') { return 'v5f' }
    return $null
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

# ---------------------------------------------------------------------------
# Per-file validation
# ---------------------------------------------------------------------------
function Invoke-ScriptCheck {
    param([string]$path, $rep, $isa, [string]$chip, [string]$core)
    # 统一换行（\r\n、\r -> \n），避免 CRLF/CR 行尾导致行粘连、解析与行号出错
    $text = ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n")
    $clean = Remove-LdComments $text

    if (-not $clean.Contains('MEMORY')) { Add-Err $rep '缺少 MEMORY 块'; return $null }
    if (-not $clean.Contains('SECTIONS')) { Add-Err $rep '缺少 SECTIONS 块' }

    # locate MEMORY { ... } block (brace depth)
    $memMatch = [regex]::Match($clean, 'MEMORY\s*\{')
    if (-not $memMatch.Success) { Add-Err $rep '无法定位 MEMORY 块'; return $null }
    $memOpen = $clean.IndexOf('{', $memMatch.Index)
    $depth = 1; $i = $memOpen + 1
    while ($i -lt $clean.Length -and $depth -gt 0) {
        if ($clean[$i] -eq '{') { $depth++ }
        elseif ($clean[$i] -eq '}') { $depth-- }
        $i++
    }
    $memText = $clean.Substring($memOpen, $i - $memOpen)

    # parse all regions (multi-line / FLASH2 / RAM2 all recorded)
    $regions = [System.Collections.Generic.List[object]]::new()
    $regionNames = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($memText, $MEM_REGEX)) {
        $name = $m.Groups['name'].Value
        $attrs = $m.Groups['attrs'].Value
        $originS = $m.Groups['origin'].Value.Trim()
        $lengthS = $m.Groups['length'].Value.Trim()
        $lineNo = Get-LineNo $clean ($memOpen + $m.Index)
        $origin = Get-CalcLength $originS
        $length = Get-CalcLength $lengthS
        $regions.Add(@{ name = $name; attrs = $attrs; origin = $origin; length = $length; originS = $originS; lengthS = $lengthS; line = $lineNo; kind = (Get-RegionKind $name) })
        [void]$regionNames.Add($name)
        $oTxt = if ($null -eq $origin) { $originS } else { "$originS (= $origin)" }
        $lTxt = if ($null -eq $length) { $lengthS } else { "$lengthS (= $length)" }
        Add-Info $rep "MEMORY $name($attrs): ORIGIN = $oTxt, LENGTH = $lTxt (第${lineNo}行)"
    }

    # syntax / symbols
    Invoke-SyntaxCheck $text $regionNames $memOpen $i $rep
    Invoke-SemicolonCheck $text $memOpen $i $rep
    Invoke-SpacingCheck $text $rep
    Invoke-GlobalPointerCheck $text $rep

    $flashRecs = @($regions | Where-Object { $_.kind -eq 'flash' })
    $ramRecs = @($regions | Where-Object { $_.kind -eq 'ram' })
    foreach ($need in @(@('FLASH', $flashRecs), @('RAM', $ramRecs))) {
        if ($need[1].Count -eq 0) { Add-Err $rep "MEMORY 中缺少 $($need[0]) 区域"; return $null }
    }

    # LENGTH computability (ORIGIN is intentionally NOT checked)
    foreach ($r in $regions) {
        if (($r.kind -eq 'flash' -or $r.kind -eq 'ram') -and $null -eq $r.length) {
            Add-Err $rep "$($r.name) 的 LENGTH 无法计算（含符号/函数等）: $($r.lengthS)（第$($r.line)行）"
        }
    }

    function Get-KindTotal {
        param($recs)
        $total = [long]0
        foreach ($r in $recs) { if ($null -eq $r.length) { return $null }; $total += $r.length }
        return $total
    }
    $flashTotal = Get-KindTotal $flashRecs
    $ramTotal = Get-KindTotal $ramRecs

    # capacity vs mcu_isa.json
    $found = Find-Chip $isa $chip
    $series = $found[0]; $chipEntry = $found[1]
    if ($null -eq $chipEntry) {
        Add-Err $rep "在 mcu_isa.json 中找不到型号 $chip，无法做容量校验（请用 --chip 指定正确型号）"
    } else {
        $maxFlash = Get-CalcLength $chipEntry.flash
        $maxSram = Get-CalcLength $chipEntry.sram
        Add-Info $rep "芯片 $chip（系列 $($series.series)）: 最大 flash=$($chipEntry.flash), sram=$($chipEntry.sram)"
        foreach ($item in @(@('FLASH', $flashRecs, $flashTotal, $maxFlash), @('RAM', $ramRecs, $ramTotal, $maxSram))) {
            $need = $item[0]; $recs = $item[1]; $total = $item[2]; $mx = $item[3]
            if ($null -eq $total) { continue }
            $parts = ($recs | ForEach-Object { $_.lengthS }) -join ' + '
            if ($recs.Count -gt 1) { Add-Info $rep "$need 区域共 $($recs.Count) 个，LENGTH 合计: $parts = $(Get-FmtSize $total)" }
            if ($total -gt $mx) {
                Add-Err $rep "$need LENGTH 合计 $(Get-FmtSize $total) 超过芯片最大 $(Get-FmtSize $mx)（区域: $parts；建议改为合计 <= $(Get-FmtSize $mx)）"
            } else {
                $pct = [math]::Round($total * 100.0 / $mx, 1)
                if ($total * 10 -lt $mx * 9) {
                    Add-Ok $rep "$need 合计 $(Get-FmtSize $total) <= $(Get-FmtSize $mx)（使用 $('{0:0.0}' -f $pct)%）"
                } else {
                    Add-Warn $rep "$need 合计 $(Get-FmtSize $total) <= $(Get-FmtSize $mx)（使用 $('{0:0.0}' -f $pct)%，接近上限）"
                }
            }
        }

        # core vs series check (ORIGIN layout is intentionally NOT checked)
        if (($core -eq 'v3f' -or $core -eq 'v5f') -and -not $DUAL_CORE_SERIES.Contains($series.series)) {
            Add-Warn $rep "检测到内核 $($core.ToUpper())，但芯片 $chip 不是双核系列，请确认 --core 是否正确"
        }
    }

    # INCLUDE
    $base = Split-Path -Parent $path
    foreach ($m in [regex]::Matches($text, 'INCLUDE\s+(\S+)')) {
        $inc = $m.Groups[1].Value.Trim('"')
        if (-not (Test-Path -LiteralPath (Join-Path $base $inc))) {
            Add-Warn $rep "INCLUDE 文件不存在（可能由工具链提供）: $inc"
        }
    }

    return @{ names = $regionNames; flashTotal = $flashTotal; ramTotal = $ramTotal }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Show-Usage {
    Write-Output '用法: validate_linkld.ps1 <link.ld> [link.ld2] [--chip CH32H417WEU] [--core v3f|v5f|single|auto] [--quiet]'
}

$argv = @($args)
$files = [System.Collections.Generic.List[string]]::new()
$chip = $null
$core = 'auto'
$quiet = $false

for ($i = 0; $i -lt $argv.Count; $i++) {
    switch ($argv[$i]) {
        '--chip'  { $chip = $argv[$i + 1]; $i++ }
        '--core'  { $core = $argv[$i + 1]; $i++ }
        '--quiet' { $quiet = $true }
        '-h'      { Show-Usage; exit 0 }
        '--help'  { Show-Usage; exit 0 }
        default   { $files.Add($argv[$i]) }
    }
}

if ($files.Count -lt 1) { Show-Usage; exit 2 }

try { $isa = Get-IsaData } catch { Write-Output "[FATAL] $_"; exit 2 }

$reports = [System.Collections.Generic.List[object]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$chipsSeen = [System.Collections.Generic.HashSet[string]]::new()
$totalFlash = [long]0
$totalRam = [long]0

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) { Write-Output "[FATAL] 文件不存在: $f"; exit 2 }
    $text = ([System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n")
    $curChip = $chip
    if (-not $curChip) { $curChip = Get-AutoChip $f $text }
    if (-not $curChip) { Write-Output '[FATAL] 无法推断芯片型号，请用 --chip 指定'; exit 2 }
    $curCore = $core
    if ($curCore -eq 'auto') {
        $curCore = Get-AutoCore $f
        if (-not $curCore) { $curCore = 'single' }
    }
    $rep = New-Report
    Add-Info $rep "文件: $f"
    Add-Info $rep "芯片: $curChip | 内核: $($curCore.ToUpper())"
    $res = Invoke-ScriptCheck $f $rep $isa $curChip $curCore
    [void]$chipsSeen.Add($curChip)
    $reports.Add(@{ path = $f; rep = $rep })
    if ($null -ne $res) {
        $results.Add(@{ path = $f; core = $curCore; res = $res })
        if ($null -ne $res.flashTotal) { $totalFlash += $res.flashTotal }
        if ($null -ne $res.ramTotal) { $totalRam += $res.ramTotal }
    }
}

# dual-core combined check (sum across files; per-file multi-region sums already applied)
if ($results.Count -ge 2 -and $chipsSeen.Count -eq 1) {
    $c = ($chipsSeen | Select-Object -First 1)
    $found = Find-Chip $isa $c
    if ($null -ne $found[1]) {
        $maxFlash = Get-CalcLength $found[1].flash
        $maxSram = Get-CalcLength $found[1].sram
        $rep = New-Report
        Add-Info $rep "双核合计校验: $($results.Count) 份脚本, flash 合计 $(Get-FmtSize $totalFlash), ram 合计 $(Get-FmtSize $totalRam)"
        if ($totalFlash -gt $maxFlash) {
            Add-Err $rep "V3F+V5F FLASH 合计 $(Get-FmtSize $totalFlash) 超过芯片最大 $(Get-FmtSize $maxFlash)"
        } else {
            Add-Ok $rep "V3F+V5F FLASH 合计 $(Get-FmtSize $totalFlash) <= $(Get-FmtSize $maxFlash)"
        }
        if ($totalRam -gt $maxSram) {
            Add-Err $rep "V3F+V5F RAM 合计 $(Get-FmtSize $totalRam) 超过芯片最大 $(Get-FmtSize $maxSram)"
        } else {
            Add-Ok $rep "V3F+V5F RAM 合计 $(Get-FmtSize $totalRam) <= $(Get-FmtSize $maxSram)"
        }
        $reports.Add(@{ path = '双核合计'; rep = $rep })
    }
}

Write-Output ''
Write-Output ('=' * 72)
Write-Output 'link.ld 校验报告'
Write-Output ('=' * 72)
$totalErr = 0; $totalWarn = 0
foreach ($r in $reports) {
    $totalErr += $r.rep.Errors
    $totalWarn += $r.rep.Warns
    Write-Output ''
    Write-Output "--- $($r.path) ---"
    if ($quiet) {
        Write-Output "  错误 $($r.rep.Errors) 个 / 警告 $($r.rep.Warns) 个"
    } else {
        foreach ($ln in $r.rep.Lines) { Write-Output $ln }
    }
}
Write-Output ''
if ($totalErr -gt 0) {
    Write-Output "$([char]0x274C) 结论: FAIL（$totalErr 个错误, $totalWarn 个警告）"
    exit 1
}
Write-Output "$([char]0x2705) 结论: PASS（$totalWarn 个警告）"
exit 0
