#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""扫描用户代码中的裸地址与位带用法（STM32F103 → CH32V20x 移植用）。

用法：
    python scan_regaccess.py <目录或文件> [...]

为什么需要这个脚本：
    改名写错，编译器报「未声明」；地址写错，编译器一句话都不说。
    裸地址与位带是本次移植中**唯一没有编译期保护**的两类写法，
    必须先扫出来、逐条核对，再上真机验证对应功能。

使用要点：
    - 扫描对象是**待移植的 STM32 源工程**（通常是 `User/` 与用户自己的驱动目录）。
    - 不要拿它扫 CH32 目标库自身：那里本来就用 `NVIC->IENR` 这类 CH32 独有写法，
      会被判为可疑项；那不是移植需要处理的内容。
    - 本工具是文本模式匹配，宏展开后的间接用法可能漏检，
      结论要配合 references/07_pointer-and-bitband.md 人工复核。

扫描项与处理依据见 references/07_pointer-and-bitband.md。
"""
import os
import re
import sys

PERIPH_BASE = 0x40000000
PERIPH_BB_BASE = 0x42000000
PERIPH_BB_END = 0x44000000
SRAM_BB_BASE = 0x22000000
SRAM_BB_END = 0x24000000

# 外设基址（两侧一致的部分 + STM32 独有的外设，用于把绝对地址翻译成外设名 + 偏移）。
BASES = [
    (0x40000000, 'TIM2'), (0x40000400, 'TIM3'), (0x40000800, 'TIM4'),
    (0x40000C00, 'TIM5'), (0x40001000, 'TIM6'), (0x40001400, 'TIM7'),
    (0x40001800, 'TIM12'), (0x40001C00, 'TIM13'), (0x40002000, 'TIM14'),
    (0x40002800, 'RTC'), (0x40002C00, 'WWDG'), (0x40003000, 'IWDG'),
    (0x40003800, 'SPI2'), (0x40003C00, 'SPI3'),
    (0x40004400, 'USART2'), (0x40004800, 'USART3'),
    (0x40004C00, 'UART4'), (0x40005000, 'UART5'),
    (0x40005400, 'I2C1'), (0x40005800, 'I2C2'),
    (0x40006400, 'CAN1'), (0x40006800, 'CAN2'),
    (0x40006C00, 'BKP'), (0x40007000, 'PWR'), (0x40007400, 'DAC'),
    (0x40007800, 'CEC'),
    (0x40010000, 'AFIO'), (0x40010400, 'EXTI'), (0x40010800, 'GPIOA'),
    (0x40010C00, 'GPIOB'), (0x40011000, 'GPIOC'), (0x40011400, 'GPIOD'),
    (0x40011800, 'GPIOE'), (0x40011C00, 'GPIOF'), (0x40012000, 'GPIOG'),
    (0x40012400, 'ADC1'), (0x40012800, 'ADC2'), (0x40012C00, 'TIM1'),
    (0x40013000, 'SPI1'), (0x40013400, 'TIM8'), (0x40013800, 'USART1'),
    (0x40013C00, 'ADC3'),
    (0x40014000, 'TIM15'), (0x40014400, 'TIM16'), (0x40014800, 'TIM17'),
    (0x40014C00, 'TIM9'), (0x40015000, 'TIM10'), (0x40015400, 'TIM11'),
    (0x40018000, 'SDIO'), (0x40020000, 'DMA1'), (0x40020400, 'DMA2'),
    (0x40021000, 'RCC'), (0x40022000, 'FLASH'), (0x40023000, 'CRC'),
]

# CH32V20x 上没有的外设（命中这些地址 = 该功能整块不存在）。
# 注意：ADC2、UART4、TIM5 在 CH32V20x 上是存在的，不在此列。
CH32_MISSING = ('TIM6', 'TIM7', 'TIM8', 'TIM9', 'TIM10', 'TIM11', 'TIM12',
                'TIM13', 'TIM14', 'TIM15', 'TIM16', 'TIM17',
                'GPIOE', 'GPIOF', 'GPIOG', 'ADC3', 'DMA2', 'SDIO', 'CEC',
                'DAC', 'FSMC', 'CAN2', 'SPI3', 'UART5')

RULES = [
    ('位带基址宏', re.compile(r'\b(PERIPH_BB_BASE|SRAM_BB_BASE)\b'),
     'CH32 侧不存在该宏 → 必然编译报错。位带必须整体改写：'
     'GPIO 用 BSHR/BCR，其它外设用读-改-写，需原子性时用 __AMOOR_W/__AMOAND_W。'),
    ('通用位带宏', re.compile(r'\b(BITBAND|BITBAND_PERI|BIT_ADDR|MEM_ADDR)\b'),
     'Cortex-M3 位带宏，CH32 无位带硬件。整组宏与调用点都要改写，见 07 文件 2.4。'),
    ('位带别名宏定义', re.compile(r'^\s*#\s*define\s+\w*_BB\b'),
     '位带别名宏（`_BB` 后缀）。查 07 文件的位带反解表；'
     '它一定依赖 PERIPH_BB_BASE，编译时会报错，但若被写成字面地址就不会。'),
    ('位带地址换算特征', re.compile(r'<<\s*5\).*<<\s*2\)|\*\s*32\).*\*\s*4\)'),
     '位带地址换算公式。CH32 无位带，必须改为直接读写寄存器。'),
    ('NVIC / SCB 直访', re.compile(r'\b(NVIC|SCB)\s*->'),
     'CH32 中断控制器是 PFIC，成员名全不同 → 会编译报错。'
     '改用 NVIC_EnableIRQ/NVIC_DisableIRQ/NVIC_SetPriority；优先级语义也不同。'),
    ('BSRR 使用', re.compile(r'->\s*BSRR\b'),
     'CH32 用 BSHR(置位) / BCR(清零)。⚠️ 若原写法是 `BSRR = (1 << (n + 16))` 表示清零，'
     '不能只改成 BSHR，必须改成 `BCR = (1 << n)`。'),
    ('BRR 使用', re.compile(r'->\s*BRR\b'),
     'CH32 侧改名为 BCR，语义相同（写 1 清零）。'),
    ('DBGMCU 裸地址', re.compile(r'0xE0042000'),
     'STM32 的 DBGMCU 在 0xE0042000（内存映射）；CH32V20x 的调试控制是 RISC-V CSR(0x7C0)，'
     '该内存地址在 CH32 上无效。改用 DBGMCU_Config() / __get_DEBUG_CR / __set_DEBUG_CR；'
     '读芯片 ID 用 DBGMCU_GetCHIPID()（CH32 的 IDCODE 在 0x1FFFF704）。'),
]

# 只有「作为地址使用」的字面量才算命中：指针转换、宏定义。
# 否则 `GPIOD->CRL = 0x44BB44BB;` 这类配置值会被误报。
PTR_CAST_ADDR = re.compile(r'\*\s*\)\s*0x([0-9A-Fa-f]{8})')
MACRO_ADDR = re.compile(
    r'^\s*#\s*define\s+([A-Za-z_]\w*)\s+\(*\s*'
    r'(?:\(*\s*(?:uint32_t|uint16_t|unsigned\s+int|unsigned\s+long)\s*\)*\s*\)*\s*)?'
    r'0x([0-9A-Fa-f]{8})')
# 位带别名地址段：0x42/0x43 外设，0x22/0x23 SRAM。范围窄，任何上下文都要报。
BB_ADDR = re.compile(r'\b0x((?:42|43|22|23)[0-9A-Fa-f]{6})\b')

SRC_EXT = ('.c', '.h', '.cpp', '.hpp', '.cc')


def peripheral_of(addr):
    """把寄存器绝对地址翻译成 (外设名, 偏移)。"""
    best = None
    for base, name in BASES:
        if base <= addr and (best is None or base > best[0]):
            best = (base, name)
    if best is None or addr - best[0] > 0x3FF:
        return None, None
    return best[1], addr - best[0]


def classify_addr(value):
    """返回 (类别, 说明)。"""
    if PERIPH_BB_BASE <= value < PERIPH_BB_END:
        d = value - PERIPH_BB_BASE
        off, bit = d >> 5, (d >> 2) & 0x1F
        addr = PERIPH_BASE + off
        name, roff = peripheral_of(addr)
        where = ('%s + 0x%X' % (name, roff)) if name else ('0x%08X' % addr)
        return '位带别名地址(外设)', (
            '🔴 CH32 无位带硬件，该地址段无定义。'
            '反解得：寄存器 %s，位 %d → 改写为对该寄存器的位操作。' % (where, bit))
    if SRAM_BB_BASE <= value < SRAM_BB_END:
        d = value - SRAM_BB_BASE
        off, bit = d >> 5, (d >> 2) & 0x1F
        return '位带别名地址(SRAM)', (
            '🔴 CH32 无位带硬件。反解得：变量偏移 0x%X，位 %d → '
            '改写为读-改-写；跨上下文共享时用 __AMOOR_W/__AMOAND_W 保持原子性。' % (off, bit))
    if PERIPH_BASE <= value < 0x60000000:
        name, roff = peripheral_of(value)
        if name:
            warn = ' ⚠️ CH32V20x 无此外设。' if name in CH32_MISSING else ''
            return '外设寄存器地址', (
                '两侧基址一致，通常可沿用：%s + 0x%X。%s'
                '建议改回符号名（如 `%s->...`）以便编译器检查。'
                % (name, roff or 0, warn, name))
        return '外设区地址', '落在外设区但不在已知外设范围内，需人工确认。'
    return None, None


def scan_file(path, out):
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return 0
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        # 跳过注释行（粗略）：`//`、`/*`、块注释续行 `* ...`。
        # 注意 `*(` 开头的是指针解引用语句（正是要扫的对象），不是注释。
        if stripped.startswith('//') or stripped.startswith('/*'):
            continue
        if stripped.startswith('*') and not stripped.startswith('*('):
            continue
        seen = set()

        def add(label, advice):
            key = (i, label)
            if key in seen:
                return
            seen.add(key)
            hits.append((i, label, stripped[:120], advice))

        for label, rx, advice in RULES:
            if rx.search(line):
                add(label, advice)

        # 位带别名地址：落在 0x42/0x43/0x22/0x23 段，任何上下文都算
        for m in BB_ADDR.finditer(line):
            v = int(m.group(1), 16)
            if v % 4:
                continue
            cat, msg = classify_addr(v)
            if cat:
                add(cat, msg)

        # 其余地址：只在指针转换或宏定义里才算，避免把配置值当地址
        cands = [int(m.group(1), 16) for m in PTR_CAST_ADDR.finditer(line)]
        mdef = MACRO_ADDR.match(line)
        if mdef:
            cands.append(int(mdef.group(2), 16))
        for v in cands:
            if PERIPH_BB_BASE <= v < PERIPH_BB_END or SRAM_BB_BASE <= v < SRAM_BB_END:
                continue
            cat, msg = classify_addr(v)
            if cat:
                add(cat, msg)
    if hits:
        out.append((path, hits))
        return len(hits)
    return 0


def collect(targets):
    files = []
    for t in targets:
        if os.path.isfile(t):
            files.append(t)
        else:
            for dp, dn, fn in os.walk(t):
                dn[:] = [d for d in dn if d not in ('.git', 'node_modules', '__pycache__')]
                for f in sorted(fn):
                    if f.lower().endswith(SRC_EXT):
                        files.append(os.path.join(dp, f))
    return files


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    quiet = '--quiet' in sys.argv
    if not args:
        print(__doc__)
        return 2

    files = collect(args)
    if not files:
        print('未找到可扫描的源文件。')
        return 2

    out = []
    total = 0
    for f in files:
        total += scan_file(f, out)

    print('=' * 72)
    print('裸地址 / 位带扫描结果')
    print('扫描 %d 个文件，命中 %d 处。' % (len(files), total))
    print('=' * 72)
    if not total:
        print()
        print('未发现裸地址或位带写法。')
        print('提示：本扫描基于文本模式匹配，宏展开后的间接用法可能漏检。')
        return 0

    order = ['位带别名地址(外设)', '位带别名地址(SRAM)', '位带基址宏', '通用位带宏',
             '位带别名宏定义', '位带地址换算特征', 'NVIC / SCB 直访', 'BSRR 使用',
             'BRR 使用', 'DBGMCU 裸地址', '外设寄存器地址', '外设区地址']
    counts = {}
    for _, hits in out:
        for _, label, _, _ in hits:
            counts[label] = counts.get(label, 0) + 1

    print()
    print('按类别统计：')
    for k in sorted(counts, key=lambda x: (order.index(x) if x in order else 99)):
        flag = '🔴' if k.startswith('位带') else ('⚠️' if 'NVIC' in k or 'BSRR' in k else '🟡')
        print('  %s %-22s %d 处' % (flag, k, counts[k]))

    if quiet:
        return 0

    for path, hits in out:
        print()
        print('-' * 72)
        print(path)
        print('-' * 72)
        for ln, label, code, advice in hits:
            print('  L%-5d [%s]' % (ln, label))
            print('          %s' % code)
            print('          → %s' % advice)
    print()
    print('=' * 72)
    print('下一步：按 references/07_pointer-and-bitband.md 逐条改写，')
    print('然后在真实硬件上验证对应功能 —— 这些写法没有编译期保护。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
