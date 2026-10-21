#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_debug.py — 调试前检查（WCH RISC-V 工程）。

检查项（硬性数值检查，均由脚本完成；需要询问用户的事项由 skill 负责）：
  规则1  FLASH / RAM 容量：解析 link.ld 的 MEMORY 块，FLASH* 与 RAM* 区域 LENGTH
         全部相加后，必须分别【严格小于】mcu_isa.json 中该芯片的最大 flash / sram
         （total < max；等于上限判 FAIL）。
  规则2  ROM/RAM 可配置芯片：--ram-avail <值> 传入“当前硬件配置”读到的 RAM 值，
         校验 总RAM <= 该值（未提供时仅提示，由 skill 决定是否需要）。
  规则3  FLASH 起始地址检测（仅报告，不判 FAIL）：任一 link.ld 的 FLASH ORIGIN != 0
         时输出 ⚠ 提示——需要由 skill 询问用户“0 地址是否有程序”：
         无程序 → WCH 芯片程序无法运行，提醒修改；有程序 → 多为 IAP+APP，
         调试当前程序需开启页擦。
  断点上限：读取 mcu_isa.json 中该芯片的 maxbreakpoint 字段（可缺省/为空）：
         为空 → 不限制；非空 → 调试时断点数不得超过该值；--breakpoints <n> 可硬校验。

用法：
    python check_debug.py <link.ld> [link.ld2] --chip CH32H417WEU \
        [--core v3f|v5f|single|auto] [--ram-avail 896K] [--breakpoints 3] [--debug-level default] [--quiet]
    python check_debug.py --selftest

注意：mcu_isa.json 固定从本脚本所在目录（技能目录）加载，不接受路径参数。
退出码：0 = PASS；1 = 存在 FAIL（规则1/规则2/断点上限任一不满足）；2 = FATAL（文件/配置缺失、无法推断型号）。
"""
import argparse
import json
import os
import re
import sys

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

SIZE_UNITS = {'K': 1024, 'M': 1024 * 1024, 'G': 1024 ** 3}
CHIP_RE = re.compile(r'CH32[A-Z0-9]+', re.I)
MEM_REGEX = re.compile(
    r'(\w+)\s*\(([^)]*)\)\s*:\s*ORIGIN\s*=\s*([^,]+),\s*LENGTH\s*=\s*([^,\n]+)'
)


# ---------------------------------------------------------------------------
# 小型表达式计算器（把 ld 的 LENGTH/ORIGIN 表达式统一转成十进制字节数）
# ---------------------------------------------------------------------------
class _ExprError(Exception):
    pass


class _LengthCalc:
    _NUM_RE = re.compile(r'(?:0[xX][0-9a-fA-F]+|\d+)(?:[KMG])?', re.I)

    def __init__(self, s):
        self.toks = self._tokenize(s)
        self.i = 0

    def _tokenize(self, s):
        toks = []
        i, n = 0, len(s)
        while i < n:
            c = s[i]
            if c.isspace():
                i += 1
                continue
            if s[i:i + 2] in ('<<', '>>'):
                toks.append(s[i:i + 2])
                i += 2
                continue
            if s[i:i + 2] in ('&&', '||'):
                raise _ExprError(f'不支持的运算符: {s[i:i + 2]}')
            if c in '+-*/%&|^~()':
                toks.append(c)
                i += 1
                continue
            m = self._NUM_RE.match(s, i)
            if m:
                toks.append(m.group(0).upper())
                i = m.end()
                continue
            raise _ExprError(f'无法识别的字符: {c!r}')
        return toks

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def next(self):
        t = self.peek()
        self.i += 1
        return t

    @staticmethod
    def _value(tok):
        m = re.fullmatch(r'(0[xX][0-9a-fA-F]+|\d+)([KMG])?', tok, re.I)
        if not m:
            raise _ExprError(f'非法数字: {tok}')
        base = 16 if m.group(1).lower().startswith('0x') else 10
        v = int(m.group(1), base)
        return v * SIZE_UNITS.get((m.group(2) or '').upper(), 1)

    def parse(self):
        v = self._or_expr()
        if self.peek() is not None:
            raise _ExprError(f'多余的 token: {self.peek()}')
        return v

    def _or_expr(self):
        v = self._xor_expr()
        while self.peek() == '|':
            self.next()
            v |= self._xor_expr()
        return v

    def _xor_expr(self):
        v = self._and_expr()
        while self.peek() == '^':
            self.next()
            v ^= self._and_expr()
        return v

    def _and_expr(self):
        v = self._shift_expr()
        while self.peek() == '&':
            self.next()
            v &= self._shift_expr()
        return v

    def _shift_expr(self):
        v = self._add_expr()
        while self.peek() in ('<<', '>>'):
            op = self.next()
            r = self._add_expr()
            if r < 0 or r > 63:
                raise _ExprError('移位量非法')
            v = (v << r) if op == '<<' else (v >> r)
        return v

    def _add_expr(self):
        v = self._mul_expr()
        while self.peek() in ('+', '-'):
            op = self.next()
            r = self._mul_expr()
            v = v + r if op == '+' else v - r
        return v

    def _mul_expr(self):
        v = self._unary()
        while self.peek() in ('*', '/', '%'):
            op = self.next()
            r = self._unary()
            if op == '*':
                v *= r
            elif op == '/':
                if r == 0:
                    raise _ExprError('除以 0')
                v //= r
            else:
                if r == 0:
                    raise _ExprError('模 0')
                v %= r
        return v

    def _unary(self):
        t = self.peek()
        if t in ('-', '~'):
            self.next()
            v = self._unary()
            return -v if t == '-' else ~v
        return self._primary()

    def _primary(self):
        t = self.next()
        if t is None:
            raise _ExprError('表达式不完整')
        if t == '(':
            v = self._or_expr()
            if self.next() != ')':
                raise _ExprError('缺少右括号')
            return v
        return self._value(t)


def calc_length(s):
    """ld 表达式 -> 十进制字节数；无法计算（含符号/函数）返回 None。"""
    s = (s or '').strip().rstrip(';').strip()
    if not s:
        return None
    try:
        return _LengthCalc(s).parse()
    except _ExprError:
        return None


def fmt_size(n):
    if n is None:
        return '?'
    if n >= 1024 * 1024:
        v = n / (1024 * 1024)
        return f'{v:g}M' if v == int(v) else f'{v:.1f}M'
    if n >= 1024:
        v = n / 1024
        return f'{v:g}K' if v == int(v) else f'{v:.1f}K'
    return str(n)


# ---------------------------------------------------------------------------
# mcu_isa.json
# ---------------------------------------------------------------------------
def load_isa():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mcu_isa.json')
    if not os.path.exists(path):
        sys.exit(f'[FATAL] mcu_isa.json 不存在: {path}')
    with open(path, encoding='utf-8-sig') as f:   # utf-8-sig 兼容有无 BOM
        return json.load(f)


def find_chip(data, name):
    for entry in data:
        for chip in entry.get('chips', []):
            if chip.get('name', '').upper() == name.upper():
                return entry, chip
    return None, None


def auto_detect_chip(path, text):
    for src in (path, text):
        for m in CHIP_RE.finditer(src):
            cand = m.group(0).upper()
            if len(cand) >= 6:
                return cand
    return None


def auto_detect_core(path):
    m = re.search(r'[Vv]3[Ff]', path)
    if m:
        return 'v3f'
    m = re.search(r'[Vv]5[Ff]', path)
    if m:
        return 'v5f'
    return None


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.lines = []
        self.errors = 0
        self.warns = 0

    def ok(self, msg):
        self.lines.append(f'  \u2705 {msg}')

    def warn(self, msg):
        self.warns += 1
        self.lines.append(f'  \u26a0 [WARN] {msg}')

    def err(self, msg):
        self.errors += 1
        self.lines.append(f'  \u274c [ERROR] {msg}')

    def info(self, msg):
        self.lines.append(f'  \u2139 [INFO] {msg}')


# ---------------------------------------------------------------------------
# link.ld 解析
# ---------------------------------------------------------------------------
def strip_comments(text):
    t = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    t = re.sub(r'//[^\n]*', '', t)
    return t


def region_kind(name):
    n = name.upper()
    if n.startswith('FLASH'):
        return 'flash'
    if n.startswith('RAM'):
        return 'ram'
    return None


def parse_ld(path, rep):
    """解析单个 link.ld，返回 (flash_total, ram_total, first_flash_origin, first_flash_line)
       或 None（无法解析）。"""
    if not os.path.exists(path):
        rep.err(f'文件不存在: {path}')
        return None
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except Exception as e:
        rep.err(f'读取失败 {path}: {e}')
        return None
    clean = strip_comments(text)
    mem = re.search(r'MEMORY\s*\{', clean)
    if not mem:
        rep.err(f'无法定位 MEMORY 块: {path}')
        return None
    mem_open = clean.find('{', mem.start())
    depth = 1
    i = mem_open + 1
    while i < len(clean) and depth > 0:
        if clean[i] == '{':
            depth += 1
        elif clean[i] == '}':
            depth -= 1
        i += 1
    mem_text = clean[mem_open:i]

    regions = []
    for m in MEM_REGEX.finditer(mem_text):
        name, attrs, origin_s, length_s = m.groups()
        origin_s = origin_s.strip()
        length_s = length_s.strip()
        line_no = clean[:mem_open + m.start()].count('\n') + 1
        rec = {
            'name': name, 'attrs': attrs,
            'origin': calc_length(origin_s), 'length': calc_length(length_s),
            'origin_s': origin_s, 'length_s': length_s,
            'line': line_no, 'kind': region_kind(name),
        }
        regions.append(rec)
        o_txt = origin_s if rec['origin'] is None else f'{origin_s} (= {rec["origin"]})'
        l_txt = length_s if rec['length'] is None else f'{length_s} (= {rec["length"]})'
        rep.info(f'MEMORY {name}({attrs}): ORIGIN = {o_txt}, LENGTH = {l_txt} (第{line_no}行)')

    flash_recs = [r for r in regions if r['kind'] == 'flash']
    ram_recs = [r for r in regions if r['kind'] == 'ram']

    def total(recs):
        t = 0
        for r in recs:
            if r['length'] is None:
                return None
            t += r['length']
        return t

    flash_total = total(flash_recs)
    ram_total = total(ram_recs)
    if flash_total is not None and flash_recs:
        parts = ' + '.join(r['length_s'] for r in flash_recs)
        rep.info(f'FLASH 区域 {len(flash_recs)} 个，LENGTH 合计: {parts} = {fmt_size(flash_total)}')
    if ram_total is not None and ram_recs:
        parts = ' + '.join(r['length_s'] for r in ram_recs)
        rep.info(f'RAM 区域 {len(ram_recs)} 个，LENGTH 合计: {parts} = {fmt_size(ram_total)}')
    if not flash_recs:
        rep.err('MEMORY 中缺少 FLASH 区域')
        return None
    if not ram_recs:
        rep.err('MEMORY 中缺少 RAM 区域')
        return None

    first = flash_recs[0]
    return {
        'flash_total': flash_total,
        'ram_total': ram_total,
        'first_flash_origin': first['origin'],
        'first_flash_origin_s': first['origin_s'],
        'first_flash_line': first['line'],
    }


def main():
    ap = argparse.ArgumentParser(description='调试前检查（FLASH/RAM 容量、FLASH 起始地址、调试等级、断点上限）')
    ap.add_argument('files', nargs='*', help='link.ld 路径（可传两份做合计）')
    ap.add_argument('--chip', help='芯片型号，如 CH32H417WEU')
    ap.add_argument('--core', choices=['v3f', 'v5f', 'single', 'auto'], default='auto')
    ap.add_argument('--ram-avail', help='当前硬件配置读到的 RAM 值（如 896K/917504），规则2 用')
    ap.add_argument('--breakpoints', type=int, help='计划设置的断点数，校验是否超过 maxbreakpoint')
    ap.add_argument('--debug-level', help='debugging.debug_level 值（来自 ide-get-project-build-property），规则4 用；非 default 时报告提醒')
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args()

    if args.selftest:
        cases = [
            ('480K', 491520),
            ('0x3FC00', 261120),
            ('64K*2', 131072),
            ('448K - 256', 458496),
            ('1M/2', 524288),
            ('0x1000+0x2000', 12288),
            ('ALIGN(4)', None),
        ]
        failed = 0
        for expr, expect in cases:
            got = calc_length(expr)
            ok = (got == expect)
            if not ok:
                failed += 1
            print(f'{"✅" if ok else "❌"} calc_length({expr:14s}) = {got}  expect={expect}')
        print()
        print('自测通过' if failed == 0 else f'自测失败 {failed} 项')
        return 0 if failed == 0 else 1

    if not args.files:
        sys.exit('[FATAL] 至少提供 1 个 link.ld 路径')
    isa = load_isa()

    # 芯片型号
    chip = args.chip
    if not chip:
        with open(args.files[0], encoding='utf-8', errors='replace') as f:
            text = f.read()
        chip = auto_detect_chip(args.files[0], text)
    if not chip:
        sys.exit('[FATAL] 无法推断芯片型号，请用 --chip 指定')
    series, chip_entry = find_chip(isa, chip)
    if chip_entry is None:
        sys.exit(f'[FATAL] 在 mcu_isa.json 中找不到型号 {chip}')
    max_flash = calc_length(chip_entry.get('flash'))
    max_sram = calc_length(chip_entry.get('sram'))

    rep = Report()
    rep.info(f'芯片: {chip}（系列 {series["series"]}）| 最大 flash={chip_entry.get("flash")}, sram={chip_entry.get("sram")}')

    results = []
    total_flash = 0
    total_ram = 0
    total_flash_ok = True
    total_ram_ok = True
    for path in args.files:
        rep.info(f'文件: {path}')
        r = parse_ld(path, rep)
        if r is None:
            return 2
        results.append(r)
        if r['flash_total'] is None:
            rep.err('FLASH LENGTH 存在无法计算的值（含符号/函数）')
            total_flash_ok = False
        else:
            total_flash += r['flash_total']
        if r['ram_total'] is None:
            rep.err('RAM LENGTH 存在无法计算的值（含符号/函数）')
            total_ram_ok = False
        else:
            total_ram += r['ram_total']

    rep.info(f'总 FLASH 合计: {fmt_size(total_flash)} | 总 RAM 合计: {fmt_size(total_ram)}')

    # ---- 规则1：总 FLASH / 总 RAM 严格小于芯片上限 ----
    if total_flash_ok and max_flash is not None:
        if total_flash >= max_flash:
            rep.err(f'[规则1] FLASH 合计 {fmt_size(total_flash)} >= 芯片最大 {fmt_size(max_flash)}（必须严格小于上限）')
        else:
            rep.ok(f'[规则1] FLASH 合计 {fmt_size(total_flash)} < 芯片最大 {fmt_size(max_flash)}')
    if total_ram_ok and max_sram is not None:
        if total_ram >= max_sram:
            rep.err(f'[规则1] RAM 合计 {fmt_size(total_ram)} >= 芯片最大 {fmt_size(max_sram)}（必须严格小于上限）')
        else:
            rep.ok(f'[规则1] RAM 合计 {fmt_size(total_ram)} < 芯片最大 {fmt_size(max_sram)}')

    # ---- 规则2：支持 ROM/RAM 配置的芯片，总 RAM <= 当前硬件配置读到的值 ----
    if args.ram_avail:
        ram_avail = calc_length(args.ram_avail)
        if ram_avail is None:
            rep.err(f'[规则2] --ram-avail 无法解析: {args.ram_avail}')
        elif total_ram_ok:
            if total_ram <= ram_avail:
                rep.ok(f'[规则2] RAM 合计 {fmt_size(total_ram)} <= 硬件配置 RAM {fmt_size(ram_avail)}')
            else:
                rep.err(f'[规则2] RAM 合计 {fmt_size(total_ram)} > 硬件配置 RAM {fmt_size(ram_avail)}')
    else:
        rep.info('[规则2] 未提供 --ram-avail（skill 应先调用 ide-debug-support-memory-allocation 确认支持，再调用 ide-debug-read-memory-allocation 读取 RAM 值传入比对；不支持则跳过）')

    # ---- 规则3：FLASH 起始地址 != 0（仅检测，不判 FAIL；需 skill 询问用户） ----
    for path, r in zip(args.files, results):
        if r['first_flash_origin'] is not None and r['first_flash_origin'] != 0:
            rep.warn(f'[规则3] {path} 的 FLASH 起始地址 0x{r["first_flash_origin"]:08X} ≠ 0（第{r["first_flash_line"]}行）'
                     f'——需询问用户 0 地址是否有程序：无程序 → WCH 芯片程序无法运行，提醒修改起始地址；'
                     f'有程序 → 多为 IAP+APP，调试当前程序需开启页擦')

    # ---- 规则4：调试等级 debugging.debug_level（非 default 时报告提醒，不判 FAIL） ----
    if args.debug_level:
        dl = str(args.debug_level).strip().lower()
        if dl == 'default':
            rep.ok('[规则4] 调试等级 debugging.debug_level = default')
        else:
            rep.warn(f'[规则4] 调试等级 debugging.debug_level = {args.debug_level} ≠ default（请在报告中提醒用户确认调试等级是否符合预期）')
    else:
        rep.info('[规则4] 未提供 --debug-level（skill 应通过 ide-get-project-build-property 查询 debugging.debug_level 后传入；非 default 需在报告中提醒）')

    # ---- 断点上限：maxbreakpoint（缺失/为空 = 不限制） ----
    maxbp = chip_entry.get('maxbreakpoint')
    if maxbp is None or str(maxbp).strip() == '':
        rep.info('[断点] maxbreakpoint 未配置（不限制断点数量）')
    else:
        try:
            maxbp_int = int(maxbp)
        except (TypeError, ValueError):
            rep.err(f'[断点] maxbreakpoint 不是有效数字: {maxbp}')
            maxbp_int = None
        if maxbp_int is not None:
            rep.info(f'[断点] maxbreakpoint = {maxbp_int}（调试时设置断点不得超过该值）')
            if args.breakpoints is not None:
                if args.breakpoints <= maxbp_int:
                    rep.ok(f'[断点] 计划断点数 {args.breakpoints} <= 上限 {maxbp_int}')
                else:
                    rep.err(f'[断点] 计划断点数 {args.breakpoints} > 上限 {maxbp_int}（请减少断点）')

    print()
    print('=' * 72)
    print('调试前检查报告')
    print('=' * 72)
    for ln in rep.lines:
        if args.quiet and ln.startswith('  \u2139'):
            continue   # --quiet 隐藏 INFO 行，保留 ✅/⚠/❌
        print(ln)
    print()
    if rep.errors:
        print(f'\u274c 结论: FAIL（{rep.errors} 个错误, {rep.warns} 个警告）')
        return 1
    print(f'\u2705 结论: PASS（{rep.warns} 个警告）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
