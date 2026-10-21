#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate_linkld.py — 校验 WCH RISC-V 工程 link.ld 链接脚本。

核心规则（对照脚本同目录下 mcu_isa.json）：
  1. 解析 link.ld 中 MEMORY 块的 FLASH / RAM 区域（支持同名区域或 FLASH/FLASH2、
     RAM/RAM2 等多区域写法）的 ORIGIN 与 LENGTH；
  2. LENGTH / ORIGIN 支持表达式（如 448K - 256、0x3FC00、64K*2、0x1000+0x2000），
     由脚本内置的小型表达式计算器（calc_length）统一转成十进制后再计算；
  3. FLASH / RAM 的多个区域（多行）LENGTH 全部相加后，再与 mcu_isa.json 中
     的芯片上限（flash / sram）比较：合计 > 上限 → ERROR；
  4. 双核芯片（CH32H415/H416/H417）分别校验 V3F、V5F 两份脚本，并核对合计不超上限；
  5. __global_pointer$ 符号检查：ld 文件（注释剥离后）中未出现时报告（INFO）；
  6. 语法检测：注释剥离后的 {} () [] 括号配对、MEMORY 行格式、>区域/ORIGIN()/LENGTH()
     区域引用有效、赋值语句分号完整；以及 MEMORY/SECTIONS 块存在；
  7. 运算符空格检测：变量与 = + - * / % << >> & | ^ 等运算符之间必须有空格（ERROR，需修复；
     注释与通配符（*(.text)、.text*）不检查；运算符两侧均为数字字面量（如 64K*2、
     0x1000+0x2000）时不检查、不计算最终值、原样保留；/DISCARD/ 段名、一元负号跳过）。

用法：
    python validate_linkld.py <link.ld> [第二个 link.ld(双核合计用)] \
        [--chip CH32H417WEU] [--core v3f|v5f|single|auto] [--quiet]

注意：
    - mcu_isa.json 固定从本脚本所在目录（技能目录）加载，不接受路径参数；
    - 脚本对 LENGTH 表达式的计算仅用于“校验比较”，绝不改写 ld 文件内容。
退出码：0 = 无错误；1 = 存在 ERROR。
"""
import argparse
import json
import os
import re
import sys

# Windows 控制台默认 GBK 编码，输出中文/emoji（✅❌⚠ 等）会触发 UnicodeEncodeError。
# 将 stdout/stderr 重配置为 UTF-8（errors='replace'），避免 GBK 编码问题，且不影响管道/重定向。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

SIZE_UNITS = {'K': 1024, 'M': 1024 * 1024, 'G': 1024 ** 3}
CHIP_RE = re.compile(r'CH32[A-Z0-9]+', re.I)
DUAL_CORE_SERIES = {'CH32H415', 'CH32H416', 'CH32H417'}


# ---------------------------------------------------------------------------
# 小型表达式计算器：把 ld 的 LENGTH/ORIGIN 表达式统一转成十进制字节数
# ---------------------------------------------------------------------------
class _ExprError(Exception):
    """表达式无法计算（含符号/函数/非法语法等）。"""


class _LengthCalc:
    """递归下降解析器：支持十进制/十六进制(0x..)数值、K/M/G 单位后缀、
    + - * / % << >> & | ^ ~ 运算符、括号与一元负号（优先级参照 C 语言）。
    不支持符号名/函数调用（如 ORIGIN(RAM)、ALIGN(4)），遇到即解析失败。
    """

    _NUM_RE = re.compile(r'(?:0[xX][0-9a-fA-F]+|\d+)(?:[KMG])?', re.I)

    def __init__(self, s):
        self.toks = self._tokenize(s)
        self.i = 0

    # ---- 词法 ----
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
        """'448K'/'0x3FC00'/'1M' -> 十进制字节数；非法时抛 _ExprError。"""
        m = re.fullmatch(r'(0[xX][0-9a-fA-F]+|\d+)([KMG])?', tok, re.I)
        if not m:
            raise _ExprError(f'非法数字: {tok}')
        base = 16 if m.group(1).lower().startswith('0x') else 10
        v = int(m.group(1), base)
        return v * SIZE_UNITS.get((m.group(2) or '').upper(), 1)

    # ---- 语法（优先级从低到高：| -> ^ -> & -> << >> -> + - -> * / % -> 一元 -> 括号） ----
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
    """把 ld 中的长度/地址表达式统一转成十进制字节数：
        '448K - 256'  -> 458496
        '0x3FC00'     -> 261120
        '64K*2'       -> 131072
        '0x1000+0x2000' -> 12288
    含符号名/函数（如 ORIGIN(RAM)、ALIGN(4)）等无法计算的内容时返回 None。"""
    s = (s or '').strip().rstrip(';').strip()
    if not s:
        return None
    try:
        return _LengthCalc(s).parse()
    except _ExprError:
        return None


def fmt_size(n):
    """字节数 -> 人类可读（'480K'/'448.8K'/'1M'）。"""
    if n is None:
        return '?'
    if n >= 1024 * 1024:
        v = n / (1024 * 1024)
        return f'{v:g}M' if v == int(v) else f'{v:.1f}M'
    if n >= 1024:
        v = n / 1024
        return f'{v:g}K' if v == int(v) else f'{v:.1f}K'
    return str(n)


def load_isa():
    """mcu_isa.json：固定从本脚本所在目录加载，不接受路径参数。"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mcu_isa.json')
    if not os.path.exists(path):
        sys.exit(f'[FATAL] mcu_isa.json 不存在: {path}')
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def find_chip(data, name):
    for entry in data:
        for chip in entry.get('chips', []):
            if chip.get('name', '').upper() == name.upper():
                return entry, chip
    return None, None


def auto_detect_core(path):
    m = re.search(r'[Vv]3[Ff]', path)
    if m:
        return 'v3f'
    m = re.search(r'[Vv]5[Ff]', path)
    if m:
        return 'v5f'
    return None


def auto_detect_chip(path, text):
    for src in (path, text):
        for m in CHIP_RE.finditer(src):
            cand = m.group(0).upper()
            if len(cand) >= 6:
                return cand
    return None


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


def strip_comments(text):
    """去掉 /* */ 与 // 注释（块注释内的换行原样保留，保证行号不变）。"""
    t = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    t = re.sub(r'//[^\n]*', '', t)
    return t


def region_kind(name):
    """按区域名归类：FLASH/FLASH2/FLASHX... -> 'flash'；RAM/RAM2/RAMX... -> 'ram'。"""
    n = name.upper()
    if n.startswith('FLASH'):
        return 'flash'
    if n.startswith('RAM'):
        return 'ram'
    return None


def check_syntax(text, region_names, mem_open, mem_end, rep):
    """ld 语法检测：
       1) 注释剥离后的 {} () [] 括号配对；
       2) MEMORY 块内每行必须符合区域定义格式（LENGTH/ORIGIN 允许表达式）；
       3) SECTIONS 中 >区域 / AT>区域 / ORIGIN(区域) / LENGTH(区域) 必须引用已定义区域。
    """
    clean = strip_comments(text)
    # 1) 括号配对
    for op, cl, nm in (('{', '}', '花括号'), ('(', ')', '圆括号'), ('[', ']', '方括号')):
        o, c = clean.count(op), clean.count(cl)
        if o != c:
            rep.err(f'{nm}不配对: {op} {o} 个 vs {cl} {c} 个')

    # 整段注释剥离后的行（strip_comments 保留换行，行号不变）
    lines = clean.split('\n')
    line_offsets = []
    off = 0
    for line in lines:
        line_offsets.append(off)
        off += len(line) + 1

    # 2) MEMORY 行格式（跳过空行与块首尾的 { } 行）
    for ln, line in enumerate(lines, 1):
        if not (mem_open <= line_offsets[ln - 1] < mem_end):
            continue
        s = line.strip()
        if not s or re.match(r'^[{}]\s*$', s):
            continue
        if re.match(r'^\w+\s*\([^)]*\)\s*:\s*ORIGIN\s*=\s*.+,\s*LENGTH\s*=\s*.+$', s):
            continue
        rep.err(f'MEMORY 块中存在无法解析的行（第{ln}行）: {s}')

    # 3) 区域引用
    for m in re.finditer(r'(?:AT\s*)?>\s*(\w+)', clean):
        name = m.group(1)
        if name not in region_names:
            ln = clean[:m.start()].count('\n') + 1
            rep.warn(f'引用了未定义的 MEMORY 区域: {name}（第{ln}行，可能来自 INCLUDE 文件）')
    for m in re.finditer(r'\b(ORIGIN|LENGTH)\s*\(\s*(\w+)\s*\)', clean):
        name = m.group(2)
        if name not in region_names:
            ln = clean[:m.start()].count('\n') + 1
            rep.warn(f'{m.group(1)}({name}) 引用了未定义的 MEMORY 区域（第{ln}行，可能来自 INCLUDE 文件）')


def check_semicolons(text, mem_open, mem_end, rep):
    """赋值语句缺少分号检测（WARN）：
       注释剥离后，MEMORY 块之外、不含 { } 的行，若含 '=' 且不以 ';' 或
       续行符（, + - * / % & | ^ < > = ( ）结尾，则报缺少分号。"""
    clean = strip_comments(text)   # 整段剥离注释（含跨行注释），避免注释内容误报
    lines = clean.split('\n')
    line_offsets = []
    off = 0
    for line in lines:
        line_offsets.append(off)
        off += len(line) + 1
    cont_end = '+-*/%&|^<>=,('   # 以这些字符结尾视为续行/语句未结束，跳过
    for ln, line in enumerate(lines, 1):
        if mem_open <= line_offsets[ln - 1] < mem_end:
            continue
        s = line.strip()
        if not s or '{' in s or '}' in s:
            continue
        if '=' not in s:
            continue
        if s.endswith(';') or s.endswith(tuple(cont_end)):
            continue
        rep.warn(f'赋值语句缺少分号（第{ln}行）: {s}')


def _is_num_token(tok):
    """是否为数字字面量：123 / 123K / 1M / 0x1F / 0x1000K 等。"""
    return bool(re.fullmatch(r'(?:0[xX][0-9a-fA-F]+|\d+)(?:[KMG])?', tok or ''))


def _both_sides_numeric(s, i, op_len):
    """运算符两侧是否都是数字字面量（如 64K*2、0x1000+0x2000）。
       若是：禁止计算最终值，直接保留原样，不做空格检查。"""
    j = i - 1
    while j >= 0 and (s[j].isalnum() or s[j] in '_.'):
        j -= 1
    lt = s[j + 1:i]
    j = i + op_len
    while j < len(s) and (s[j].isalnum() or s[j] in '_.'):
        j += 1
    rt = s[i + op_len:j]
    return bool(lt and rt) and _is_num_token(lt) and _is_num_token(rt)


def check_operator_spacing(text, rep):
    """变量与运算符之间必须有空格（ERROR，需修复）。
       检查对象：= + - / % << >> & | ^ 等运算符，两侧必须为空白；
       不检查：注释（先整体剥离 /* */ 与 //，含跨行块注释）与通配符（* 一律不视为运算符）；
       运算符两侧均为数字字面量（如 64K*2、0x1000+0x2000）时不检查、不计算最终值、原样保留；
       /DISCARD/ 等特殊段名行整体跳过；- 用作一元负号（前邻 ( = , [ : 或空白/行首）时跳过。
    """
    clean = strip_comments(text)
    lines = clean.split('\n')
    for ln, line in enumerate(lines, 1):
        s = line.strip()
        if not s or re.match(r'^\s*/\w+/\s*:', s):   # /DISCARD/ 等特殊段名行整体跳过
            continue
        bad = []
        i = 0
        n = len(s)
        while i < n:
            two = s[i:i + 2]
            if two in ('<<', '>>', '&&', '||'):
                if _both_sides_numeric(s, i, 2):   # 两侧数字：原样保留，不检查
                    i += 2
                    continue
                prev_ws = i == 0 or s[i - 1].isspace()
                next_ws = i + 2 >= n or s[i + 2].isspace()
                if not (prev_ws and next_ws):
                    bad.append(two)
                i += 2
                continue
            ch = s[i]
            if ch in '&|^':
                if _both_sides_numeric(s, i, 1):   # 两侧数字：原样保留，不检查
                    i += 1
                    continue
                prev_ws = i == 0 or s[i - 1].isspace()
                next_ws = i + 1 >= n or s[i + 1].isspace()
                if not (prev_ws and next_ws):
                    bad.append(ch)
                i += 1
                continue
            if ch == '=':
                if i + 1 < n and s[i + 1] == '=':
                    i += 2
                    continue
                if i > 0 and s[i - 1] in '=!<>':
                    i += 1
                    continue
                if _both_sides_numeric(s, i, 1):   # 两侧数字：原样保留，不检查
                    i += 1
                    continue
                prev_ws = i == 0 or s[i - 1].isspace()
                next_ws = i + 1 >= n or s[i + 1].isspace()
                if not (prev_ws and next_ws):
                    bad.append('=')
                i += 1
                continue
            if ch in '+/':
                # /DISCARD/ 等段名形式（/ 后紧跟非空白且行内还有闭合 /）跳过
                if ch == '/' and i + 1 < n and not s[i + 1].isspace() and '/' in s[i + 1:]:
                    i += 1
                    continue
                if _both_sides_numeric(s, i, 1):   # 两侧数字：原样保留，不检查
                    i += 1
                    continue
                prev_ws = i == 0 or s[i - 1].isspace()
                next_ws = i + 1 >= n or s[i + 1].isspace()
                if not (prev_ws and next_ws):
                    bad.append(ch)
                i += 1
                continue
            if ch == '-':
                unary = (i == 0 or s[i - 1].isspace() or s[i - 1] in '(=,[:')
                if not unary:
                    if _both_sides_numeric(s, i, 1):   # 两侧数字：原样保留，不检查
                        i += 1
                        continue
                    prev_ws = s[i - 1].isspace()
                    next_ws = i + 1 >= n or s[i + 1].isspace()
                    if not (prev_ws and next_ws):
                        bad.append('-')
                i += 1
                continue
            if ch == '%':
                if _both_sides_numeric(s, i, 1):   # 两侧数字：原样保留，不检查
                    i += 1
                    continue
                prev_ws = i == 0 or s[i - 1].isspace()
                next_ws = i + 1 >= n or s[i + 1].isspace()
                if not (prev_ws and next_ws):
                    bad.append('%')
                i += 1
                continue
            i += 1
        if bad:
            uniq = []
            for b in bad:
                if b not in uniq:
                    uniq.append(b)
            rep.err(f'运算符两侧必须加空格（第{ln}行）: {s}  [运算符: {" ".join(uniq)}]')


def check_global_pointer(text, rep):
    """检查 ld 文件中是否有 __global_pointer$ 符号（注释剥离后）；
       没有则报告（INFO，不影响 PASS）。"""
    clean = strip_comments(text)
    if '__global_pointer$' in clean:
        rep.ok('检测到 __global_pointer$ 符号')
    else:
        rep.info('未检测到 __global_pointer$ 符号（RISC-V GP 优化通常需要定义 __global_pointer$ = . + 0x800;）')


# MEMORY 区域定义行：名称(属性) : ORIGIN = <表达式>, LENGTH = <表达式>
# LENGTH 取值可能含空格（如 448K - 256），因此用 [^,\n]+ 捕获整个表达式。
MEM_REGEX = re.compile(
    r'(\w+)\s*\(([^)]*)\)\s*:\s*ORIGIN\s*=\s*([^,]+),\s*LENGTH\s*=\s*([^,\n]+)'
)


def check_script(path, rep, isa, chip, core):
    with open(path, encoding='utf-8', errors='replace') as f:
        text = f.read()
    clean = strip_comments(text)   # 统一用注释剥离后的文本做解析/检测（保留换行，行号不变）

    # ---- 语法基础 ----
    if 'MEMORY' not in clean:
        rep.err('缺少 MEMORY 块')
        return None
    if 'SECTIONS' not in clean:
        rep.err('缺少 SECTIONS 块')

    # ---- 解析 MEMORY（支持同名/FLASH2/RAM2 等全部区域，多行全部记录） ----
    mem = re.search(r'MEMORY\s*\{', clean)
    if not mem:
        rep.err('无法定位 MEMORY 块')
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

    regions = []            # 全部区域记录（多区域/多行全部保留）
    region_names = set()
    for m in MEM_REGEX.finditer(mem_text):
        name, attrs, origin_s, length_s = m.groups()
        origin_s = origin_s.strip()
        length_s = length_s.strip()
        line_no = clean[:mem_open + m.start()].count('\n') + 1
        origin = calc_length(origin_s)
        length = calc_length(length_s)
        rec = {
            'name': name, 'attrs': attrs,
            'origin': origin, 'length': length,
            'origin_s': origin_s.strip(), 'length_s': length_s.strip(),
            'line': line_no, 'kind': region_kind(name),
        }
        regions.append(rec)
        region_names.add(name)
        o_txt = origin_s.strip() if origin is None else f'{origin_s.strip()} (= {origin})'
        l_txt = length_s.strip() if length is None else f'{length_s.strip()} (= {length})'
        rep.info(f'MEMORY {name}({attrs}): ORIGIN = {o_txt}, LENGTH = {l_txt} (第{line_no}行)')

    # ---- ld 语法检测（括号配对/MEMORY 行格式/区域引用/赋值分号/运算符空格） ----
    check_syntax(text, region_names, mem_open, i, rep)
    check_semicolons(text, mem_open, i, rep)
    check_operator_spacing(text, rep)
    # ---- __global_pointer$ 符号检查（缺失时报告） ----
    check_global_pointer(text, rep)

    flash_recs = [r for r in regions if r['kind'] == 'flash']
    ram_recs = [r for r in regions if r['kind'] == 'ram']
    for need, recs in (('FLASH', flash_recs), ('RAM', ram_recs)):
        if not recs:
            rep.err(f'MEMORY 中缺少 {need} 区域')
            return None

    # LENGTH 可解析性
    for r in regions:
        if r['kind'] in ('flash', 'ram') and r['length'] is None:
            rep.err(f'{r["name"]} 的 LENGTH 无法计算（含符号/函数等）: {r["length_s"]}（第{r["line"]}行）')

    # ---- 多区域合计（全部相加后再与芯片上限比较） ----
    def kind_total(recs):
        total = 0
        for r in recs:
            if r['length'] is None:
                return None
            total += r['length']
        return total

    flash_total = kind_total(flash_recs)
    ram_total = kind_total(ram_recs)

    series, chip_entry = find_chip(isa, chip)
    if chip_entry is None:
        rep.err(f'在 mcu_isa.json 中找不到型号 {chip}，无法做容量校验（请用 --chip 指定正确型号）')
    else:
        max_flash = calc_length(chip_entry['flash'])
        max_sram = calc_length(chip_entry['sram'])
        rep.info(f'芯片 {chip}（系列 {series["series"]}）: 最大 flash={chip_entry["flash"]}, sram={chip_entry["sram"]}')
        for need, recs, total, mx in (('FLASH', flash_recs, flash_total, max_flash),
                                      ('RAM', ram_recs, ram_total, max_sram)):
            if total is None:
                continue   # 已有“LENGTH 无法计算”的 ERROR，跳过容量比较
            parts = ' + '.join(r['length_s'] for r in recs)
            if len(recs) > 1:
                rep.info(f'{need} 区域共 {len(recs)} 个，LENGTH 合计: {parts} = {fmt_size(total)}')
            if total > mx:
                rep.err(f'{need} LENGTH 合计 {fmt_size(total)} 超过芯片最大 {fmt_size(mx)}'
                        f'（区域: {parts}；建议改为合计 <= {fmt_size(mx)}）')
            else:
                ratio = total / mx
                msg = f'{need} 合计 {fmt_size(total)} <= {fmt_size(mx)}（使用 {ratio:.1%}）'
                rep.ok(msg) if ratio < 0.9 else rep.warn(msg + '，接近上限')

    # ---- 内核与芯片系列核对（不检查 ORIGIN 布局） ----
    if core in ('v3f', 'v5f') and series and series['series'] not in DUAL_CORE_SERIES:
        rep.warn(f'检测到内核 {core.upper()}，但芯片 {chip} 不是双核系列，请确认 --core 是否正确')

    # ---- INCLUDE ----
    base = os.path.dirname(os.path.abspath(path))
    for m in re.finditer(r'INCLUDE\s+(\S+)', text):
        inc = m.group(1).strip('"')
        if not os.path.exists(os.path.join(base, inc)):
            rep.warn(f'INCLUDE 文件不存在（可能由工具链提供）: {inc}')

    return {'names': region_names, 'flash_total': flash_total, 'ram_total': ram_total}


def main():
    ap = argparse.ArgumentParser(description='校验 WCH RISC-V link.ld（容量/语法）')
    ap.add_argument('files', nargs='+', help='link.ld 路径（可传两份做双核合计校验）')
    ap.add_argument('--chip', help='芯片型号，如 CH32H417WEU（缺省自动从路径/文件内容推断）')
    ap.add_argument('--core', choices=['v3f', 'v5f', 'single', 'auto'], default='auto',
                    help='内核（默认按路径中的 V3F/V5F 自动识别）')
    ap.add_argument('--quiet', action='store_true', help='只输出结论行')
    args = ap.parse_args()

    isa = load_isa()
    reports = []
    regions_list = []
    total_flash = total_ram = 0
    chips_seen = set()

    for path in args.files:
        if not os.path.exists(path):
            sys.exit(f'[FATAL] 文件不存在: {path}')
        with open(path, encoding='utf-8', errors='replace') as f:
            text = f.read()
        chip = args.chip or auto_detect_chip(path, text)
        if not chip:
            sys.exit('[FATAL] 无法推断芯片型号，请用 --chip 指定')
        core = args.core
        if core == 'auto':
            core = auto_detect_core(path) or ('v3f' if any(s in path.upper() for s in ('V3F',)) else None)
            core = core or 'single'
        rep = Report()
        rep.info(f'文件: {path}')
        rep.info(f'芯片: {chip} | 内核: {core.upper() if core else "?"}')
        res = check_script(path, rep, isa, chip, core)
        reports.append((path, rep))
        chips_seen.add(chip)
        if res:
            regions_list.append((path, core, res))
            if res['flash_total'] is not None:
                total_flash += res['flash_total']
            if res['ram_total'] is not None:
                total_ram += res['ram_total']

    # 双核合计校验（各文件已先做多区域合计，这里再做文件间合计）
    if len(regions_list) >= 2 and len(chips_seen) == 1:
        chip = args.chip or next(iter(chips_seen))
        _, chip_entry = find_chip(isa, chip)
        if chip_entry:
            max_flash = calc_length(chip_entry['flash'])
            max_sram = calc_length(chip_entry['sram'])
            rep = Report()
            rep.info(f'双核合计校验: {len(regions_list)} 份脚本, flash 合计 {fmt_size(total_flash)}, ram 合计 {fmt_size(total_ram)}')
            if total_flash > max_flash:
                rep.err(f'V3F+V5F FLASH 合计 {fmt_size(total_flash)} 超过芯片最大 {fmt_size(max_flash)}')
            else:
                rep.ok(f'V3F+V5F FLASH 合计 {fmt_size(total_flash)} <= {fmt_size(max_flash)}')
            if total_ram > max_sram:
                rep.err(f'V3F+V5F RAM 合计 {fmt_size(total_ram)} 超过芯片最大 {fmt_size(max_sram)}')
            else:
                rep.ok(f'V3F+V5F RAM 合计 {fmt_size(total_ram)} <= {fmt_size(max_sram)}')
            reports.append(('双核合计', rep))

    print()
    print('=' * 72)
    print('link.ld 校验报告')
    print('=' * 72)
    total_err = total_warn = 0
    for path, rep in reports:
        total_err += rep.errors
        total_warn += rep.warns
        print(f'\n--- {path} ---')
        if not args.quiet:
            print('\n'.join(rep.lines))
        else:
            print(f'  错误 {rep.errors} 个 / 警告 {rep.warns} 个')
    print()
    if total_err:
        print(f'\u274c 结论: FAIL（{total_err} 个错误, {total_warn} 个警告）')
        return 1
    print(f'\u2705 结论: PASS（{total_warn} 个警告）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
