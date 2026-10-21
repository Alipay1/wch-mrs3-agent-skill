<#
.SYNOPSIS
扫描用户代码中的裸地址与位带用法（STM32F103 -> CH32V20x 移植用）。

.DESCRIPTION
本脚本与同目录的 scan_regaccess.py 功能等价，是 Windows 上的无依赖实现。
适用场景：机器上没有 Python，但有 Windows PowerShell（Win7 起系统自带）。

为什么需要这个脚本：
    改名写错，编译器报「未声明」；地址写错，编译器一句话都不说。
    裸地址与位带是本次移植中唯一没有编译期保护的两类写法，
    必须先扫出来、逐条核对，再上真机验证对应功能。

使用要点：
    - 扫描对象是待移植的 STM32 源工程（通常是 User/ 与用户自己的驱动目录）。
    - 不要拿它扫 CH32 目标库自身：那里本来就用 NVIC->IENR 这类 CH32 独有写法，
      会被判为可疑项；那不是移植需要处理的内容。
    - 本工具是文本模式匹配，宏展开后的间接用法可能漏检；
      结论要配合 references/07_pointer-and-bitband.md 人工复核。

.PARAMETER Path
要扫描的目录或文件，可给多个。

.PARAMETER Quiet
只输出分类统计，不列明细。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scan_regaccess.ps1 <用户代码目录>
    powershell -ExecutionPolicy Bypass -File scan_regaccess.ps1 <用户代码目录> -Quiet

扫描项与处理依据见 references/07_pointer-and-bitband.md。
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# ---- 输出编码：确保中文在控制台正常显示 ----
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ============================================================================
#  常量（与 scan_regaccess.py 保持一致）
# ============================================================================
$PERIPH_BASE    = 0x40000000
$PERIPH_BB_BASE = 0x42000000
$PERIPH_BB_END  = 0x44000000
$SRAM_BB_BASE   = 0x22000000
$SRAM_BB_END    = 0x24000000

# 外设基址（两侧一致的部分 + STM32 独有的外设，用于把绝对地址翻译成外设名 + 偏移）
$BASES = @(
    @(0x40000000,'TIM2'), @(0x40000400,'TIM3'), @(0x40000800,'TIM4'),
    @(0x40000C00,'TIM5'), @(0x40001000,'TIM6'), @(0x40001400,'TIM7'),
    @(0x40001800,'TIM12'), @(0x40001C00,'TIM13'), @(0x40002000,'TIM14'),
    @(0x40002800,'RTC'), @(0x40002C00,'WWDG'), @(0x40003000,'IWDG'),
    @(0x40003800,'SPI2'), @(0x40003C00,'SPI3'),
    @(0x40004400,'USART2'), @(0x40004800,'USART3'),
    @(0x40004C00,'UART4'), @(0x40005000,'UART5'),
    @(0x40005400,'I2C1'), @(0x40005800,'I2C2'),
    @(0x40006400,'CAN1'), @(0x40006800,'CAN2'),
    @(0x40006C00,'BKP'), @(0x40007000,'PWR'), @(0x40007400,'DAC'),
    @(0x40007800,'CEC'),
    @(0x40010000,'AFIO'), @(0x40010400,'EXTI'), @(0x40010800,'GPIOA'),
    @(0x40010C00,'GPIOB'), @(0x40011000,'GPIOC'), @(0x40011400,'GPIOD'),
    @(0x40011800,'GPIOE'), @(0x40011C00,'GPIOF'), @(0x40012000,'GPIOG'),
    @(0x40012400,'ADC1'), @(0x40012800,'ADC2'), @(0x40012C00,'TIM1'),
    @(0x40013000,'SPI1'), @(0x40013400,'TIM8'), @(0x40013800,'USART1'),
    @(0x40013C00,'ADC3'),
    @(0x40014000,'TIM15'), @(0x40014400,'TIM16'), @(0x40014800,'TIM17'),
    @(0x40014C00,'TIM9'), @(0x40015000,'TIM10'), @(0x40015400,'TIM11'),
    @(0x40018000,'SDIO'), @(0x40020000,'DMA1'), @(0x40020400,'DMA2'),
    @(0x40021000,'RCC'), @(0x40022000,'FLASH'), @(0x40023000,'CRC')
)

# CH32V20x 上没有的外设（命中这些地址 = 该功能整块不存在）
# 注意：ADC2、UART4、TIM5 在 CH32V20x 上是存在的，不在此列。
$CH32_MISSING = @('TIM6','TIM7','TIM8','TIM9','TIM10','TIM11','TIM12',
                  'TIM13','TIM14','TIM15','TIM16','TIM17',
                  'GPIOE','GPIOF','GPIOG','ADC3','DMA2','SDIO','CEC',
                  'DAC','FSMC','CAN2','SPI3','UART5')

$SRC_EXT = @('.c','.h','.cpp','.hpp','.cc')
$SKIP_DIR = @('.git','node_modules','__pycache__','obj','Debug','Release')

# ---- 规则表（顺序与 .py 一致，影响输出分组） ----
$RULES = @(
    @{ Label='位带基址宏'; Rx='\b(PERIPH_BB_BASE|SRAM_BB_BASE)\b';
       Advice='CH32 侧不存在该宏 → 必然编译报错。位带必须整体改写：GPIO 用 BSHR/BCR，其它外设用读-改-写，需原子性时用 __AMOOR_W/__AMOAND_W。' },
    @{ Label='通用位带宏'; Rx='\b(BITBAND|BITBAND_PERI|BIT_ADDR|MEM_ADDR)\b';
       Advice='Cortex-M3 位带宏，CH32 无位带硬件。整组宏与调用点都要改写，见 07 文件 2.4。' },
    @{ Label='位带别名宏定义'; Rx='^\s*#\s*define\s+\w*_BB\b';
       Advice='位带别名宏（_BB 后缀）。查 07 文件的位带反解表；它一定依赖 PERIPH_BB_BASE，编译时会报错，但若被写成字面地址就不会。' },
    @{ Label='位带地址换算特征'; Rx='<<\s*5\).*<<\s*2\)|\*\s*32\).*\*\s*4\)';
       Advice='位带地址换算公式。CH32 无位带，必须改为直接读写寄存器。' },
    @{ Label='NVIC / SCB 直访'; Rx='\b(NVIC|SCB)\s*->';
       Advice='CH32 中断控制器是 PFIC，成员名全不同 → 会编译报错。改用 NVIC_EnableIRQ/NVIC_DisableIRQ/NVIC_SetPriority；优先级语义也不同。' },
    @{ Label='BSRR 使用'; Rx='->\s*BSRR\b';
       Advice='CH32 用 BSHR(置位) / BCR(清零)。⚠ 若原写法是 BSRR = (1 << (n + 16)) 表示清零，不能只改成 BSHR，必须改成 BCR = (1 << n)。' },
    @{ Label='BRR 使用'; Rx='->\s*BRR\b';
       Advice='CH32 侧改名为 BCR，语义相同（写 1 清零）。' },
    @{ Label='DBGMCU 裸地址'; Rx='0xE0042000';
       Advice='STM32 的 DBGMCU 在 0xE0042000（内存映射）；CH32V20x 的调试控制是 RISC-V CSR(0x7C0)，该内存地址在 CH32 上无效。改用 DBGMCU_Config() / __get_DEBUG_CR / __set_DEBUG_CR；读芯片 ID 用 DBGMCU_GetCHIPID()（CH32 的 IDCODE 在 0x1FFFF704）。' }
)

# 只有「作为地址使用」的字面量才算命中：指针转换、宏定义。
# 否则 GPIOD->CRL = 0x44BB44BB; 这类配置值会被误报。
$RX_PTR_CAST = '\*\s*\)\s*0x([0-9A-Fa-f]{8})'
$RX_MACRO_ADDR = '^\s*#\s*define\s+([A-Za-z_]\w*)\s+\(*\s*(?:\(*\s*(?:uint32_t|uint16_t|unsigned\s+int|unsigned\s+long)\s*\)*\s*\)*\s*)?0x([0-9A-Fa-f]{8})'
# 位带别名地址段：0x42/0x43 外设，0x22/0x23 SRAM。范围窄，任何上下文都要报。
$RX_BB_ADDR = '\b0x((?:42|43|22|23)[0-9A-Fa-f]{6})\b'

# ---- 预编译（跳过编译失败的规则，并在最后告知） ----
$compiled = @()
foreach ($r in $RULES) {
    try {
        $compiled += @{ Label = $r.Label; Rx = [regex]::new($r.Rx); Advice = $r.Advice }
    } catch {
        Write-Warning ("规则正则编译失败，已跳过：{0} / {1}" -f $r.Label, $r.Rx)
    }
}
$RxPtrCast   = [regex]::new($RX_PTR_CAST)
$RxMacroAddr = [regex]::new($RX_MACRO_ADDR, 'Multiline')
$RxBBAddr    = [regex]::new($RX_BB_ADDR)

# ============================================================================
#  辅助函数
# ============================================================================
function Get-PeripheralOf([long]$addr) {
    $best = $null
    foreach ($b in $BASES) {
        if ($b[0] -le $addr -and ($null -eq $best -or $b[0] -gt $best[0])) { $best = $b }
    }
    if ($null -eq $best -or ($addr - $best[0]) -gt 0x3FF) { return $null }
    return @{ Name = $best[1]; Off = [int]($addr - $best[0]) }
}

function Classify-Addr([long]$value) {
    if ($value -ge $PERIPH_BB_BASE -and $value -lt $PERIPH_BB_END) {
        $d = $value - $PERIPH_BB_BASE
        $off = [int]($d -shr 5)
        $bit = [int](($d -shr 2) -band 0x1F)
        $addr = $PERIPH_BASE + $off
        $p = Get-PeripheralOf $addr
        $where = if ($p) { '{0} + 0x{1:X}' -f $p.Name, $p.Off } else { '0x{0:X8}' -f $addr }
        return @{ Cat='位带别名地址(外设)';
                  Msg=('🔴 CH32 无位带硬件，该地址段无定义。反解得：寄存器 {0}，位 {1} → 改写为对该寄存器的位操作。' -f $where, $bit) }
    }
    if ($value -ge $SRAM_BB_BASE -and $value -lt $SRAM_BB_END) {
        $d = $value - $SRAM_BB_BASE
        $off = [int]($d -shr 5)
        $bit = [int](($d -shr 2) -band 0x1F)
        return @{ Cat='位带别名地址(SRAM)';
                  Msg=('🔴 CH32 无位带硬件。反解得：变量偏移 0x{0:X}，位 {1} → 改写为读-改-写；跨上下文共享时用 __AMOOR_W/__AMOAND_W 保持原子性。' -f $off, $bit) }
    }
    if ($value -ge $PERIPH_BASE -and $value -lt 0x60000000) {
        $p = Get-PeripheralOf $value
        if ($p) {
            $warn = if ($CH32_MISSING -contains $p.Name) { ' ⚠️ CH32V20x 无此外设。' } else { '' }
            # 反引号（`）在 PowerShell 双引号串里是转义符，写成 `` 只会输出一个。
            # 这里要的是「原文一个反引号」，所以用 [char]0x60 拼，避免转义歧义。
            $bt = [char]0x60
            return @{ Cat='外设寄存器地址';
                      Msg=('两侧基址一致，通常可沿用：{0} + 0x{1:X}。{2}建议改回符号名（如 {3}{0}->...{3}）以便编译器检查。' -f $p.Name, $p.Off, $warn, $bt) }
        }
        return @{ Cat='外设区地址'; Msg='落在外设区但不在已知外设范围内，需人工确认。' }
    }
    return $null
}

# 收集待扫描的源文件（与 .py 的 collect() 等价）
function Collect-Files([string[]]$targets) {
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($t in $targets) {
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if (Test-Path -LiteralPath $t -PathType Container) {
            # 不要对结果排序。Python 版用 os.walk 深度优先 + 每层目录内 sorted(fn)，
            # 最终顺序是「文件系统枚举序」，不是全路径字典序。Get-ChildItem -Recurse
            # 的原始顺序与之逐条吻合（实测 1615 个文件全等），一旦排序反而错位：
            # 全路径字典序会把 Cortex/ 与 CRC/ 按码点比较排成 CRC 在前，
            # 而文件系统序（不分大小写）是 Cortex 在前。
            Get-ChildItem -LiteralPath $t -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $SRC_EXT -contains $_.Extension.ToLower() } |
                Where-Object {
                    $skip = $false
                    foreach ($seg in ($_.FullName -split '[\\/]')) { if ($SKIP_DIR -contains $seg) { $skip = $true; break } }
                    -not $skip
                } |
                ForEach-Object { $files.Add($_.FullName) }
        } elseif (Test-Path -LiteralPath $t -PathType Leaf) {
            $files.Add((Resolve-Path -LiteralPath $t).Path)
        }
    }
    return $files
}

# 扫描单个文件，返回命中列表（与 .py 的 scan_file() 等价）
function Scan-File([string]$path) {
    $text = $null
    try {
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    } catch {
        try { $text = [System.IO.File]::ReadAllText($path) } catch { return @() }
    }
    if ($null -eq $text) { return @() }

    $lines = $text -split "\r\n|\n|\r"
    $hits = New-Object System.Collections.Generic.List[object]
    $inBlockComment = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        $line = $lines[$i]
        $stripped = $line.Trim()

        # ---- 块注释状态跟踪（.py 用「跳过以 * 开头的行」近似，这里做得更准） ----
        $lineForScan = $line
        if ($inBlockComment) {
            $endIdx = $lineForScan.IndexOf('*/')
            if ($endIdx -ge 0) {
                $inBlockComment = $false
                $lineForScan = $lineForScan.Substring($endIdx + 2)
            } else {
                continue
            }
        }
        # 去掉本行内的 /* ... */ 片段，并判断是否进入块注释
        while ($true) {
            $s = $lineForScan.IndexOf('/*')
            if ($s -lt 0) { break }
            $e = $lineForScan.IndexOf('*/', $s + 2)
            if ($e -lt 0) {
                $lineForScan = $lineForScan.Substring(0, $s)
                $inBlockComment = $true
                break
            } else {
                $lineForScan = $lineForScan.Substring(0, $s) + ' ' + $lineForScan.Substring($e + 2)
            }
        }
        # 去掉本行内的 // 之后内容（粗略，不处理字符串字面量里的 //）
        $sl = $lineForScan.IndexOf('//')
        if ($sl -ge 0) { $lineForScan = $lineForScan.Substring(0, $sl) }

        $stripped = $lineForScan.Trim()
        if ($stripped.Length -eq 0) { continue }

        $seen = @{}
        $addHit = {
            param($label, $advice)
            $key = "$lineNo|$label"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $hits.Add([pscustomobject]@{
                    Line   = $lineNo
                    Label  = $label
                    Code   = if ($line.Trim().Length -gt 120) { $line.Trim().Substring(0, 120) } else { $line.Trim() }
                    Advice = $advice
                })
            }
        }

        # ---- 规则匹配 ----
        foreach ($r in $compiled) {
            if ($r.Rx.IsMatch($lineForScan)) { & $addHit $r.Label $r.Advice }
        }

        # ---- 位带别名地址：落在 0x42/0x43/0x22/0x23 段，任何上下文都算 ----
        foreach ($m in $RxBBAddr.Matches($lineForScan)) {
            $v = [Convert]::ToInt64($m.Groups[1].Value, 16)
            if (($v % 4) -ne 0) { continue }
            $c = Classify-Addr $v
            if ($c) { & $addHit $c.Cat $c.Msg }
        }

        # ---- 其余地址：只在指针转换或宏定义里才算，避免把配置值当地址 ----
        $cands = New-Object System.Collections.Generic.List[long]
        foreach ($m in $RxPtrCast.Matches($lineForScan)) {
            $cands.Add([Convert]::ToInt64($m.Groups[1].Value, 16))
        }
        $mm = $RxMacroAddr.Match($lineForScan)
        if ($mm.Success) { $cands.Add([Convert]::ToInt64($mm.Groups[2].Value, 16)) }

        foreach ($v in $cands) {
            if (($v -ge $PERIPH_BB_BASE -and $v -lt $PERIPH_BB_END) -or
                ($v -ge $SRAM_BB_BASE -and $v -lt $SRAM_BB_END)) { continue }
            $c = Classify-Addr $v
            if ($c) { & $addHit $c.Cat $c.Msg }
        }
    }
    # 统一返回 object[]：单元素 List 会被 PowerShell 解包成裸对象，调用方拿到
    # 的就不是集合了（PSCustomObject 连 .Count 都没有）。这里显式转成数组，
    # 配合主流程的 @() 接收，保证任何命中数下行为一致。
    return $hits.ToArray()
}

# ============================================================================
#  主流程
# ============================================================================
# 兼容 --quiet / -q 的裸写法（.py 允许）
$quietFlag = $Quiet.IsPresent
$targets = @()
foreach ($a in $Path) {
    if ($a -eq '--quiet' -or $a -eq '-q') { $quietFlag = $true }
    else { $targets += $a }
}

if ($targets.Count -eq 0) {
    Write-Host "用法: scan_regaccess.ps1 <目录或文件> [...] [-Quiet]"
    Write-Host "  例: scan_regaccess.ps1 User Hardware -Quiet"
    exit 2
}

$files = Collect-Files $targets
if ($files.Count -eq 0) {
    Write-Host '未找到可扫描的源文件。'
    exit 2
}

$out = New-Object System.Collections.Generic.List[object]
$total = 0
foreach ($f in $files) {
    # @() 包裹是必需的：Scan-File 返回单元素 List 时会被 PowerShell 解包成裸
    # PSCustomObject，而 PSCustomObject 没有 Count 属性 → $h.Count 为 $null，
    # 单命中文件会被静默丢弃（实测漏检 3/444 处）。
    $h = @(Scan-File $f)
    if ($h.Count -gt 0) {
        $out.Add([pscustomobject]@{ Path = $f; Hits = $h })
        $total += $h.Count
    }
}

Write-Host ('=' * 72)
Write-Host '裸地址 / 位带扫描结果'
Write-Host ('扫描 {0} 个文件，命中 {1} 处。' -f $files.Count, $total)
Write-Host ('=' * 72)

if ($total -eq 0) {
    Write-Host ''
    Write-Host '未发现裸地址或位带写法。'
    Write-Host '提示：本扫描基于文本模式匹配，宏展开后的间接用法可能漏检。'
    exit 0
}

$order = @('位带别名地址(外设)','位带别名地址(SRAM)','位带基址宏','通用位带宏',
           '位带别名宏定义','位带地址换算特征','NVIC / SCB 直访','BSRR 使用',
           'BRR 使用','DBGMCU 裸地址','外设寄存器地址','外设区地址')
$counts = @{}
foreach ($o in $out) {
    foreach ($hit in $o.Hits) {
        if ($counts.ContainsKey($hit.Label)) { $counts[$hit.Label]++ } else { $counts[$hit.Label] = 1 }
    }
}

Write-Host ''
Write-Host '按类别统计：'
$sorted = $counts.Keys | Sort-Object { $idx = $order.IndexOf($_); if ($idx -lt 0) { 99 } else { $idx } }
foreach ($k in $sorted) {
    $flag = if ($k.StartsWith('位带')) { '🔴' }
            elseif ($k -like '*NVIC*' -or $k -like '*BSRR*') { '⚠️' }
            else { '🟡' }
    Write-Host ('  {0} {1,-22} {2} 处' -f $flag, $k, $counts[$k])
}

if ($quietFlag) { exit 0 }

foreach ($o in $out) {
    Write-Host ''
    Write-Host ('-' * 72)
    Write-Host $o.Path
    Write-Host ('-' * 72)
    foreach ($hit in $o.Hits) {
        Write-Host ('  L{0,-5} [{1}]' -f $hit.Line, $hit.Label)
        Write-Host ('          {0}' -f $hit.Code)
        Write-Host ('          → {0}' -f $hit.Advice)
    }
}

Write-Host ''
Write-Host ('=' * 72)
Write-Host '下一步：按 references/07_pointer-and-bitband.md 逐条改写，'
Write-Host '然后在真实硬件上验证对应功能 —— 这些写法没有编译期保护。'
exit 0
