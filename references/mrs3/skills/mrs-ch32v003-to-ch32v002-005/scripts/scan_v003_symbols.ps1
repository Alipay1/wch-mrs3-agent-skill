#Requires -Version 5.1
<#
.SYNOPSIS
    扫描 CH32V003 客户工程，找出迁移到 CH32V002 / CH32V005 时需要处理的符号。

.DESCRIPTION
    本脚本是 scan_v003_symbols.py 的 PowerShell 等价实现，供 Windows 下无 Python 环境时使用。
    两者共用同目录下的 data.json，输出分类、判定规则、提示文案完全一致。
    【维护约定】修改任一脚本（规则、分类、提示文案、data.json 字段）时，.py 与 .ps1 必须同步更新。

.PARAMETER Root
    要扫描的工程根目录。

.PARAMETER Target
    目标型号（CH32V002 / CH32V005），可选。用于 OPA 等按目标分流的判定。

.PARAMETER All
    连纯模板/库目录（Peripheral / Core / Startup / Ld / Library）一起扫，默认跳过。
    注意：Debug/ 不在跳过清单内 —— 其中的 debug.c 含 USART 重映射等工程级配置，需一并核对。

.PARAMETER Json
    以 JSON 输出。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scan_v003_symbols.ps1 C:\proj\003soft -Target CH32V005

.EXAMPLE
    .\scan_v003_symbols.ps1 .\003soft -Target CH32V002 -Json

.NOTES
    输出分类：
      [必须人工核对]  编译器零提示 —— 同名异值宏、重映射、页粒度、core_riscv 等待类
      [需改名]        目标库无此符号，改名后编译通过
      [建议删除]      目标芯片无此功能
      [提示]          行为变化或按目标型号分流的告知项

    退出码：0 正常 / 2 参数或数据文件错误
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Root,

    [string]$Target = '',

    [switch]$All,

    [switch]$Json
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------------------------------------------------------------- 常量
$SrcExts = @('.c', '.h', '.cpp', '.hpp', '.S', '.s')
# 默认跳过的纯模板/库目录（工程级转换后应为目标侧版本）
# 注意：Debug/ 不跳过 —— 其中的 debug.c 含 USART 重映射等工程级配置，需一并核对
$LibDirs = @('peripheral', 'core', 'startup', 'ld', 'library')

$W = 100

$DataPath = Join-Path $PSScriptRoot 'data.json'
if (-not (Test-Path -LiteralPath $DataPath)) {
    [Console]::Error.WriteLine("缺少数据文件: $DataPath")
    exit 2
}
$Data = Get-Content -LiteralPath $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------------------------------------------------------------- 工具函数
function ConvertTo-Hashtable($obj) {
    $h = @{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

# 与 Python sorted() 一致：按序数值排序（而非区域文化排序）
function Sort-Ordinal([string[]]$Names) {
    $a = [string[]]$Names
    if ($a.Count -le 1) { return $a }
    try {
        [Array]::Sort($a, [System.Collections.IComparer][System.StringComparer]::Ordinal)
    }
    catch {
        $a = [string[]]($a | Sort-Object)
    }
    return $a
}

function New-WordPattern([string[]]$Names) {
    $esc = @($Names | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) })
    return '\b(' + ($esc -join '|') + ')\b'
}

function New-PrefixPattern([string[]]$Names) {
    $esc = @($Names | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) })
    return '\b(' + ($esc -join '|') + ')[A-Za-z0-9_]*'
}

# 枚举工程内需要扫描的源文件（含目录跳过规则），返回排序后的绝对路径
function Get-SourceFiles([string]$Dir, [string]$RootFull, [bool]$ScanAll, $Sink) {
    if (-not $ScanAll -and $Dir -ne $RootFull) {
        $name = [System.IO.Path]::GetFileName($Dir)
        if ($LibDirs -contains $name.ToLower()) { return }
    }
    foreach ($f in [System.IO.Directory]::GetFiles($Dir)) {
        $ext = [System.IO.Path]::GetExtension($f)
        if ($SrcExts -ccontains $ext) { [void]$Sink.Add($f) }
    }
    foreach ($d in [System.IO.Directory]::GetDirectories($Dir)) {
        Get-SourceFiles -Dir $d -RootFull $RootFull -ScanAll $ScanAll -Sink $Sink
    }
}

# ---------------------------------------------------------------- 分类规则
$DiffValue = ConvertTo-Hashtable $Data.diff_value_macros      # 同名异值宏 -> [V003, 目标]

$ManualExact = Sort-Ordinal @($Data.diff_value_macros.PSObject.Properties | ForEach-Object { $_.Name })

$ManualPrefix = @(
    'GPIO_FullRemap', 'GPIO_PartialRemap', 'GPIO_Remap_', 'AFIO_PCFR1_',
    'GPIO_CFGLR_MODE', 'GPIO_Pin_All'
)

$ManualSym = @(
    'GPIO_PinRemapConfig',
    'DBGMCU_GetCHIPID', 'DBGMCU_GetDEVID', 'DBGMCU_GetREVID',
    'FLASH_ErasePage', 'FLASH_ErasePage_Fast', 'FLASH_ProgramPage_Fast',
    'FLASH_BufLoad', 'FLASH_BufReset', 'FLASH_ROM_ERASE', 'FLASH_ROM_WRITE',
    'FLASH_EnableWriteProtection',
    'OPA_Init', 'OPA_StructInit', 'OPA_Cmd',
    'USART_Init', 'ADC_RegularChannelConfig', 'ADC_InjectedChannelConfig',
    'RCC_SYSCLKConfig'
)

$WaitSyms = @('WFItoWFE', '_WFE_', '__WFE', '__WFI')

$ManualNote = @{
    'GPIO_PinRemapConfig'           = '重映射参数两侧不通用，必须按目标引脚重选（references/06_gpio.md 6.5）'
    'GPIO_FullRemap'                = '重映射宏同名但值不同（references/06_gpio.md 6.5）'
    'GPIO_PartialRemap'             = '重映射宏同名但值不同（references/06_gpio.md 6.5）'
    'GPIO_Remap_'                   = '重映射宏同名但值不同（references/06_gpio.md 6.5）'
    'AFIO_PCFR1_'                   = 'AFIO 重映射位定义两侧不同（references/06_gpio.md 6.5）'
    'GPIO_CFGLR_MODE'               = 'GPIO 配置寄存器位布局两侧不同（references/06_gpio.md 6.5）'
    'GPIO_Pin_All'                  = 'V003=0xFFFF / 目标=0x00FF，只覆盖低 8 位（references/06_gpio.md 6.3）'
    'DBGMCU_GetCHIPID'              = '读的寄存器地址不同（0x1FFFF7C4 vs 0x1FFFF704），返回值必变（references/07 7.1）'
    'DBGMCU_GetDEVID'               = '芯片 ID 寄存器地址不同（references/07 7.1）'
    'DBGMCU_GetREVID'               = '芯片 ID 寄存器地址不同（references/07 7.1）'
    'FLASH_ErasePage'               = '页粒度 64B->256B，循环擦写会连带擦掉相邻数据（references/05_flash.md）'
    'FLASH_ErasePage_Fast'          = '页粒度 64B->256B（references/05_flash.md）'
    'FLASH_ProgramPage_Fast'        = '页粒度 64B->256B（references/05_flash.md）'
    'FLASH_BufLoad'                 = '页缓冲 64B->256B（references/05_flash.md 5.2）'
    'FLASH_BufReset'                = '页缓冲 64B->256B（references/05_flash.md 5.2）'
    'FLASH_ROM_ERASE'               = '地址对齐 %64->%256（references/05_flash.md 5.1）'
    'FLASH_ROM_WRITE'               = '地址对齐 %64->%256（references/05_flash.md 5.1）'
    'FLASH_EnableWriteProtection'   = '写保护粒度 16 页/组->8 页/组（references/05_flash.md 5.3）'
    'OPA_Init'                      = 'OPA_InitTypeDef 成员 2->15，同名不同义；V002 删除 / V005 重写（references/04 4.4）'
    'OPA_StructInit'                = '同上（references/04 4.4）'
    'OPA_Cmd'                       = '同上（references/04 4.4）'
    'USART_Init'                    = '目标侧删除 8 倍过采样分支（references/07 7.1）'
    'ADC_RegularChannelConfig'      = '目标侧删除通道 >9 的采样时间分支（references/07 7.1）'
    'ADC_InjectedChannelConfig'     = '同上（references/07 7.1）'
    'RCC_SYSCLKConfig'              = '目标侧删除 HSI 校准分支（references/07 7.1）'
}

$MacroRename = ConvertTo-Hashtable $Data.macro_rename_map        # 前缀 -> 新前缀
$FuncRename  = ConvertTo-Hashtable $Data.func_rename_map         # 符号 -> 新符号
$RegRename   = ConvertTo-Hashtable $Data.reg_member_rename_map   # 成员 -> 新成员

# 可改名的符号要从「建议删除」里剔除（它们只是改名，不是功能缺失）
$RenamePrefixes = @($MacroRename.Keys)
$DelMacros = @($Data.only_v003_macros | Where-Object {
        $m = $_
        $hit = $false
        foreach ($p in $RenamePrefixes) { if ($m.StartsWith($p)) { $hit = $true; break } }
        -not $hit
    })

$DelFuncs = @($Data.only_v003_funcs | Where-Object { -not $FuncRename.ContainsKey($_) })

$SpeedObsolete = @($Data.speed_obsolete)
$OpaSyms = @($Data.opa_symbols)

$DelNote = @{
    'OPA_DeInit'                   = 'V002 无 OPA -> 删除；V005 -> 按 V005 OPA 库重写（references/04 4.4）'
    'ADC_StartCalibration'         = '002/5 无 ADC 校准，删除整句'
    'ADC_ResetCalibration'         = '002/5 无 ADC 校准，删除整句'
    'ADC_GetCalibrationStatus'     = '002/5 无 ADC 校准，删除整句'
    'ADC_GetResetCalibrationStatus' = '002/5 无 ADC 校准，删除整句'
    'ADC_Calibration_Vol'          = '002/5 无 ADC 校准，删除整句'
    'ADC_ExternalTrig_DLY'         = '002/5 无 ADC->DLYR，删除整句'
    'FLASH_ProgramHalfWord'        = '002/5 不支持半字写 -> 改用 Fast 编程（references/05_flash.md 5.2）'
    'FLASH_ProgramWord'            = '目标侧无此函数 -> 改用 Fast 编程或 ROM 接口（references/05_flash.md 5.2）'
    'FLASH_ProgramOptionByteData'  = '目标侧无此函数（references/05_flash.md 5.2）'
}

# ---------------------------------------------------------------- 正则
$ReManualExact  = [regex](New-WordPattern $ManualExact)
$ReManualPrefix = [regex](New-PrefixPattern $ManualPrefix)
$ReManualSym    = [regex](New-WordPattern $ManualSym)
$ReWait         = [regex](New-WordPattern $WaitSyms)
$ReReg          = [regex]('->(' + ((@($RegRename.Keys) | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b')
$ReMacroRename  = [regex](New-PrefixPattern @($MacroRename.Keys))
$ReFuncRename   = [regex](New-WordPattern @($FuncRename.Keys))
$ReLowerInc     = [regex]'#\s*include\s*[<"](ch32v00x_[A-Za-z0-9_]+\.h|system_ch32v00x\.h|ch32v00x_it\.h)[>"]'
$ReHighcode     = [regex]'\.highcode'
$RePrio         = [regex]'\bNVIC_PriorityGroupConfig\s*\('
$ReDelMacros    = [regex](New-WordPattern $DelMacros)
$ReDelFuncs     = [regex](New-WordPattern $DelFuncs)
$ReSpeed        = [regex](New-WordPattern $SpeedObsolete)
$ReOpa          = [regex](New-WordPattern (Sort-Ordinal $OpaSyms))

# ---------------------------------------------------------------- 主流程
if ([string]::IsNullOrWhiteSpace($Root)) {
    [Console]::Error.WriteLine('用法: scan_v003_symbols.ps1 <工程目录> [-Target CH32V002|CH32V005] [-All] [-Json]')
    exit 2
}

$RootFull = [System.IO.Path]::GetFullPath($Root)
if ($RootFull.Length -gt 3) { $RootFull = $RootFull.TrimEnd('\', '/') }
if (-not [System.IO.Directory]::Exists($RootFull)) {
    [Console]::Error.WriteLine("目录不存在: $RootFull")
    exit 2
}

$fileList = [System.Collections.Generic.List[string]]::new()
Get-SourceFiles -Dir $RootFull -RootFull $RootFull -ScanAll ([bool]$All) -Sink $fileList
$files = $fileList.ToArray()
if ($files.Count -gt 1) {
    try { [Array]::Sort($files, [System.Collections.IComparer][System.StringComparer]::Ordinal) }
    catch { $files = [string[]]($files | Sort-Object) }
}

$manual   = [System.Collections.Generic.List[object]]::new()
$rename   = [System.Collections.Generic.List[object]]::new()
$deletion = [System.Collections.Generic.List[object]]::new()
$notice   = [System.Collections.Generic.List[object]]::new()
$nFiles   = 0

foreach ($path in $files) {
    $nFiles++
    $text = $null
    try {
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    }
    catch {
        continue
    }
    $rp = $path.Substring($RootFull.Length).TrimStart('\', '/').Replace('\', '/')
    $lines = $text -split "`n"

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $loc = '{0}:{1}' -f $rp, ($i + 1)

        # ---- 必须人工核对
        foreach ($mo in $ReManualExact.Matches($line)) {
            $s = $mo.Groups[1].Value
            $v = $DiffValue[$s]
            $manual.Add([PSCustomObject]@{
                    loc  = $loc
                    sym  = $s
                    note = ('同名异值宏（V003={0} / 目标={1}）' -f $v[0], $v[1])
                })
        }
        foreach ($mo in $ReManualPrefix.Matches($line)) {
            $key = $mo.Groups[1].Value
            $n = $ManualNote[$key]
            if (-not $n) { $n = '重映射/寄存器位定义两侧不同' }
            $manual.Add([PSCustomObject]@{ loc = $loc; sym = $mo.Value; note = $n })
        }
        foreach ($mo in $ReManualSym.Matches($line)) {
            $s = $mo.Groups[1].Value
            $n = $ManualNote[$s]
            if (-not $n) { $n = '实现或行为已变（references/07）' }
            $manual.Add([PSCustomObject]@{ loc = $loc; sym = $s; note = $n })
        }
        foreach ($mo in $ReWait.Matches($line)) {
            $manual.Add([PSCustomObject]@{
                    loc = $loc; sym = $mo.Groups[1].Value
                    note = 'core_riscv 等待类，目标侧实现不同（references/08）'
                })
        }
        if ($ReHighcode.IsMatch($line)) {
            $manual.Add([PSCustomObject]@{
                    loc = $loc; sym = '.highcode'
                    note = '目标侧无 .highcode 段，链接期报错（references/01 第 3 节）'
                })
        }

        # ---- 需改名
        foreach ($mo in $ReReg.Matches($line)) {
            $s = $mo.Groups[1].Value
            $rename.Add([PSCustomObject]@{
                    loc = $loc; sym = 'RCC->' + $s
                    note = 'RCC->' + $RegRename[$s] + '（references/02 2.1）'
                })
        }
        foreach ($mo in $ReMacroRename.Matches($line)) {
            $s = $mo.Value
            $pref = $mo.Groups[1].Value
            $new = $MacroRename[$pref] + $s.Substring($pref.Length)
            $rename.Add([PSCustomObject]@{ loc = $loc; sym = $s; note = $new })
        }
        foreach ($mo in $ReFuncRename.Matches($line)) {
            $s = $mo.Groups[1].Value
            $n = $FuncRename[$s]
            if ($s -eq 'FLASH_ReadOutProtection') {
                $n = 'FLASH_EnableReadOutProtection()  <- 去掉参数'
            }
            $rename.Add([PSCustomObject]@{ loc = $loc; sym = $s; note = $n })
        }
        foreach ($mo in $ReLowerInc.Matches($line)) {
            $s = $mo.Groups[1].Value
            $rename.Add([PSCustomObject]@{
                    loc = $loc; sym = '<' + $s + '>'
                    note = '<' + $s.Replace('ch32v00x', 'ch32v00X') + '>'
                })
        }

        # ---- 建议删除
        foreach ($mo in $ReDelMacros.Matches($line)) {
            $deletion.Add([PSCustomObject]@{
                    loc = $loc; sym = $mo.Groups[1].Value
                    note = '目标侧无此宏（目标芯片无此功能），建议删除并确认功能不退化'
                })
        }
        foreach ($mo in $ReDelFuncs.Matches($line)) {
            $s = $mo.Groups[1].Value
            $n = $DelNote[$s]
            if (-not $n) { $n = '目标侧无此函数，建议删除并确认功能不退化' }
            if ($s.StartsWith('USART_') -and -not $DelNote.ContainsKey($s)) {
                $n = '002/5 无智能卡/同步时钟功能，删除并在报告标注功能缺失'
            }
            $deletion.Add([PSCustomObject]@{ loc = $loc; sym = $s; note = $n })
        }

        # ---- 提示
        foreach ($mo in $ReSpeed.Matches($line)) {
            $notice.Add([PSCustomObject]@{
                    loc = $loc; sym = $mo.Groups[1].Value
                    note = '目标侧只有 GPIO_Speed_30MHz，统一替换（references/06 6.1）'
                })
        }
        if ($RePrio.IsMatch($line)) {
            $notice.Add([PSCustomObject]@{
                    loc = $loc; sym = 'NVIC_PriorityGroupConfig'
                    note = '已核实两侧行为一致，不用改（references/07 7.3）'
                })
        }
        if ($Target -and $Target.ToUpper() -eq 'CH32V002') {
            foreach ($mo in $ReOpa.Matches($line)) {
                $notice.Add([PSCustomObject]@{
                        loc = $loc; sym = $mo.Groups[1].Value
                        note = '目标为 V002（无 OPA），需在最终报告告知用户'
                    })
            }
        }
    }
}

function Select-Dedup($rows) {
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $rows) {
        $k = $r.loc + "`t" + $r.sym
        if ($seen.Add($k)) { $out.Add($r) }
    }
    # 前置逗号：阻止 PowerShell 把单元素列表解包成标量（否则 .Count 为空）
    return , $out
}

$manual = Select-Dedup $manual
$rename = Select-Dedup $rename
$deletion = Select-Dedup $deletion
$notice = Select-Dedup $notice

if ($Json) {
    $payload = [ordered]@{
        root     = $RootFull
        target   = $(if ($Target) { $Target } else { $null })
        files    = $nFiles
        manual   = $manual
        rename   = $rename
        deletion = $deletion
        notice   = $notice
    }
    $jsonText = $payload | ConvertTo-Json -Depth 6
    # Windows PowerShell 5.1 的 ConvertTo-Json 会把非 ASCII 与 < > 转义为 \uXXXX，还原以保证与 .py 输出一致
    # 注意：变量名不可用 $json —— 与开关参数 $Json 同名（PowerShell 变量名大小写不敏感）会报类型转换错误
    $jsonText = [regex]::Replace($jsonText, '\\u([0-9a-fA-F]{4})', {
            param($m)
            [char][Convert]::ToInt32($m.Groups[1].Value, 16)
        })
    Write-Output $jsonText
    return
}

$bar = '=' * $W
$dash = '-' * $W

Write-Output $bar
Write-Output 'CH32V003 -> CH32V002/CH32V005 迁移扫描报告'
Write-Output ('扫描目录: ' + $RootFull)
Write-Output ('目标型号: ' + $(if ($Target) { $Target } else { '(未指定)' }))
$skipMsg = ''
if (-not $All) { $skipMsg = '（已跳过 Peripheral/Core/Startup/Ld）' }
Write-Output ('扫描文件: {0} 个{1}' -f $nFiles, $skipMsg)
Write-Output $bar

function Write-Section($title, $rows) {
    Write-Output ''
    Write-Output $dash
    Write-Output ('{0}  ({1})' -f $title, $rows.Count)
    Write-Output $dash
    if ($rows.Count -eq 0) {
        Write-Output '  (无)'
        return
    }
    foreach ($r in $rows) {
        Write-Output ('  {0,-44} {1}' -f $r.loc, $r.sym)
        Write-Output ('      ' + $r.note)
    }
}

Write-Section '[必须人工核对] 编译器零提示，必须逐条处理' $manual
Write-Section '[需改名] 目标库无此符号，改名后编译通过' $rename
Write-Section '[建议删除] 目标芯片无此功能' $deletion
Write-Section '[提示] 行为变化 / 按目标型号分流' $notice

Write-Output ''
Write-Output $bar
Write-Output ('汇总: 必须人工核对 {0} 处 | 需改名 {1} 处 | 建议删除 {2} 处 | 提示 {3} 处' -f `
        $manual.Count, $rename.Count, $deletion.Count, $notice.Count)
Write-Output '处理依据见 references/ 目录下 02~08 各文件。'
Write-Output $bar
