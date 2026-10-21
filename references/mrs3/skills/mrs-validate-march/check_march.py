#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_march.py — 校验工程编译配置与 mcu_isa.json 是否匹配。

校验项（均可独立使用，提供哪项就校验哪项）：
  1. march（架构）:
     - 必须为 rv32 开头；
     - 按 "_" 分割：首个分段去掉 "rv32" 后按字符逐个拆分，后续分段原样保留；
     - 拆分出的每一项都必须出现在该内核的 isa_ext 中，全部命中才算 PASS。
  2. toolchain（工具链）: component_toolchain 的值必须在该芯片所属系列的 "toolchain" 数组中。
  3. abi（整数 ABI）: riscvTargetProcessor.integer_ABI 的值必须在该芯片内核的 "mabi" 数组中。
  4. startfile（启动文件，只提示不修改）: --startfile-dir 目录下的 .S 文件必须与 mcu_isa.json
     中该型号的 "startfile" 数组一致，不一致时输出 ⚠ 提示。

用法：
    python check_march.py --chip CH32H417WEU --core v5f \
        --march rv32imafc_zba_zbb_zbc_zbs_xw --toolchain GCC15 --abi ilp32f
    python check_march.py --chip CH32H417WEU --startfile-dir <工程>/Common/Startup
    python check_march.py --march rv32imac_xw --isa-ext i,m,a,c,xw     # 手动指定扩展
    python check_march.py --selftest                                    # 内置自测

注意：mcu_isa.json 固定从本脚本所在目录（技能目录）加载，不接受路径参数。
退出码：0 = 全部 PASS；1 = 存在 FAIL 或参数错误。
"""
import argparse
import json
import os
import sys

# Windows 控制台默认 GBK 编码，输出中文/emoji（✅❌⚠ 等）会触发 UnicodeEncodeError。
# 将 stdout/stderr 重配置为 UTF-8（errors='replace'），避免 GBK 编码问题，且不影响管道/重定向。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

DIVIDER = '=' * 72


def split_march(march):
    """按规则拆分 march，返回 (错误信息 or None, 拆分项列表)。"""
    m = (march or '').strip().lower()
    if not m:
        return 'march 为空', None
    if not m.startswith('rv32'):
        return f'march 必须以 rv32 开头（实际: {march}）', None
    rest = m[4:]
    if not rest:
        return 'march 在 rv32 之后为空', None
    segs = rest.split('_')
    parts = list(segs[0])            # 首段：逐字符拆分
    parts += [s for s in segs[1:]]   # 后续段：原样保留
    return None, [p for p in parts if p]


def march_check(march, isa_ext):
    """返回 (ok, 错误信息, 拆分项, 缺失项)。"""
    err, parts = split_march(march)
    if err:
        return False, err, None, None
    missing = [p for p in parts if p not in isa_ext]
    return (not missing), None, parts, missing


def fmt_list(items):
    return ', '.join(items)


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


def pick_core(cores, sel):
    if not sel:
        return None
    return next((c for c in cores if sel.lower() in c.get('core', '').lower()), None)


class Checker:
    """按芯片/内核做多项校验，逐行记录带判定的报告。"""

    def __init__(self, chip_name, core_sel=None, installed_toolchains=None):
        self.chip_name = chip_name
        self.core_sel = core_sel
        self.installed_toolchains = [x for x in (installed_toolchains or []) if x]
        self.entry = None
        self.chip = None
        self.rows = []      # (name, verdict, text)，verdict: 'ok'/'fail'/'info'/'warn'

    def resolve(self, isa):
        self.entry, self.chip = find_chip(isa, self.chip_name)
        if self.chip is None:
            sys.exit(f'[FATAL] 在 mcu_isa.json 中找不到型号 {self.chip_name}')
        cores = self.entry.get('cores', [])
        if self.core_sel and pick_core(cores, self.core_sel) is None:
            sys.exit(f'[FATAL] 内核 {self.core_sel} 不在芯片 {self.chip_name} 的 cores 中')

    def _core_label(self, core):
        return f'{self.entry["series"]} {core["core"]}'

    # ---- march ----
    def check_march(self, march):
        cores = self.entry.get('cores', [])
        core = pick_core(cores, self.core_sel)
        if core is not None:
            ok, err, parts, missing = march_check(march, core.get('isa_ext', []))
            if err:
                self.rows.append(('march', 'fail', err))
                return ok
            self.rows.append(('march', 'ok' if ok else 'fail',
                              f'march={march} → 拆分: {fmt_list(parts)} | isa_ext[{self._core_label(core)}]: {fmt_list(core.get("isa_ext", []))}'
                              + (f' | 缺失: {fmt_list(missing)}' if missing else ' | 全部命中')))
            return ok
        self.rows.append(('march', 'info', f'未指定内核，对芯片全部 {len(cores)} 个内核逐一比对:'))
        any_pass = False
        for c in cores:
            ok, err, parts, missing = march_check(march, c.get('isa_ext', []))
            any_pass = any_pass or ok
            self.rows.append(('march', 'ok' if ok else 'fail',
                              f'vs {self._core_label(c)} isa_ext=[{fmt_list(c.get("isa_ext", []))}]'
                              + ('' if ok else f' → 缺失: {fmt_list(missing)}')))
        self.rows.append(('march', 'ok' if any_pass else 'fail',
                          f'结果: {"PASS（至少一个内核匹配）" if any_pass else "FAIL（所有内核均不匹配）"}'))
        return any_pass

    # ---- toolchain（系列级） ----
    def check_toolchain(self, value):
        allowed = self.entry.get('toolchain', [])
        ok = value in allowed
        self.rows.append(('toolchain', 'ok' if ok else 'fail',
                          f'component_toolchain={value} | 允许值[{self.entry["series"]}]: {fmt_list(allowed)}'
                          + ('' if ok else f' | ❌ {value} 不在允许列表中')))
        if self.installed_toolchains:
            usable = [x for x in allowed if x in self.installed_toolchains]
            self.rows.append(('toolchain', 'info',
                              f'已安装工具链(ide-get-installed-toolchain): {fmt_list(self.installed_toolchains)}'))
            self.rows.append(('toolchain', 'info',
                              f'已安装且允许: {fmt_list(usable) if usable else "无"}'))
            if not ok:
                if usable:
                    self.rows.append(('toolchain', 'info',
                                      f'建议改为已安装且允许的工具链: {usable[0]}（通过 ide-set-project-build-property 修改 component_toolchain）'))
                else:
                    self.rows.append(('toolchain', 'warn',
                                      '无已安装且允许的工具链（需要先安装对应工具链，或核对已安装列表）'))
            elif value not in self.installed_toolchains:
                self.rows.append(('toolchain', 'warn',
                                  f'当前工具链 {value} 不在已安装列表中（ide-get-installed-toolchain），请确认'))
        return ok

    # ---- abi（内核级） ----
    def check_abi(self, value):
        cores = self.entry.get('cores', [])
        core = pick_core(cores, self.core_sel)
        if core is not None:
            allowed = core.get('mabi', [])
            ok = value in allowed
            self.rows.append(('abi', 'ok' if ok else 'fail',
                              f'riscvTargetProcessor.integer_ABI={value} | 允许值[{self._core_label(core)}]: {fmt_list(allowed)}'
                              + ('' if ok else f' | ❌ {value} 不在允许列表中')))
            return ok
        self.rows.append(('abi', 'info', f'未指定内核，对芯片全部 {len(cores)} 个内核逐一比对:'))
        any_pass = False
        for c in cores:
            allowed = c.get('mabi', [])
            ok = value in allowed
            any_pass = any_pass or ok
            self.rows.append(('abi', 'ok' if ok else 'fail',
                              f'vs {self._core_label(c)} mabi=[{fmt_list(allowed)}]'))
        self.rows.append(('abi', 'ok' if any_pass else 'fail',
                          f'结果: {"PASS（至少一个内核匹配）" if any_pass else "FAIL（所有内核均不匹配）"}'))
        return any_pass

    # ---- startfile（只提示，不修改） ----
    def check_startfile(self, startup_dir):
        expected = self.chip.get('startfile', []) or []
        if not expected:
            self.rows.append(('startfile', 'info',
                              f'芯片 {self.chip_name} 在 mcu_isa.json 中 startfile 为空（[]），跳过校验'))
            return True
        if not os.path.isdir(startup_dir):
            self.rows.append(('startfile', 'fail', f'Startup 目录不存在: {startup_dir}'))
            return False
        found = sorted(f for f in os.listdir(startup_dir) if f.upper().endswith('.S'))
        missing = [e for e in expected if e not in found]
        extra = [f for f in found if f not in expected]
        if not missing and not extra:
            self.rows.append(('startfile', 'ok',
                              f'Startup 目录 {startup_dir} 中的 .S 文件与 mcu_isa.json startfile 完全一致: {fmt_list(expected)}'))
            return True
        msg = (f'Startup 目录 {startup_dir} 与 mcu_isa.json startfile 不一致（只提示，不修改）'
               f' | 期望(startfile)={fmt_list(expected)} | 实际={fmt_list(found)}')
        if missing:
            msg += f' | 缺少: {fmt_list(missing)}'
        if extra:
            msg += f' | 多余: {fmt_list(extra)}'
        self.rows.append(('startfile', 'warn', msg))
        return True  # startfile 不一致只提示，不导致 FAIL


def main():
    ap = argparse.ArgumentParser(description='校验编译配置（march/toolchain/abi）与 mcu_isa.json 是否匹配')
    ap.add_argument('--march', help='架构字符串（来自 riscvTargetProcessor.architecture），如 rv32imafc_zba_zbb_zbc_zbs_xw')
    ap.add_argument('--toolchain', help='工具链值（来自 component_toolchain），如 GCC12/GCC15')
    ap.add_argument('--abi', help='整数 ABI 值（来自 riscvTargetProcessor.integer_ABI），如 ilp32f/ilp32/ilp32e')
    ap.add_argument('--chip', help='芯片型号，如 CH32H417WEU')
    ap.add_argument('--core', choices=['v3f', 'v5f'], help='双核芯片指定内核（缺省对全部内核逐一比对）')
    ap.add_argument('--isa-ext', help='直接指定 isa_ext（逗号分隔），与 --chip 二选一用于 march 校验')
    ap.add_argument('--startfile-dir', help='工程 Startup 目录（含 .S 启动文件），与 mcu_isa.json 的 startfile 比对（只提示，不修改）')
    ap.add_argument('--installed-toolchains', help='已安装的工具链列表（逗号分隔，来自 ide-get-installed-toolchain），用于给出修改建议')
    ap.add_argument('--selftest', action='store_true', help='运行内置自测用例')
    args = ap.parse_args()

    if args.selftest:
        cases = [
            ('march PASS', True, march_check('rv32imafc_zba_zbb_zbc_zbs_xw', ['i', 'm', 'a', 'c', 'f', 'zba', 'zbb', 'zbc', 'zbs', 'xw'])[0]),
            ('march FAIL d', False, march_check('rv32imafdc_zba_zbb_zbc_zbs_xw', ['i', 'm', 'a', 'c', 'f', 'zba', 'zbb', 'zbc', 'zbs', 'xw'])[0]),
            ('march FAIL rv64', False, march_check('rv64imac_xw', ['i', 'm', 'a', 'c', 'xw'])[0]),
            ('march FAIL z 扩展', False, march_check('rv32imac_zba_zbb_zbc_zbs_xw', ['i', 'm', 'a', 'c', 'xw'])[0]),
            ('march FAIL 空', False, march_check('rv32', ['i'])[0]),
            ('march 顺序无关', True, march_check('rv32imafc_zba_zbb_zbc_zbs_xw', ['i', 'm', 'a', 'c', 'f', 'zba', 'zbb', 'zbc', 'zbs', 'xw'])[0]),
        ]
        failed = 0
        for name, expect, got in cases:
            tag = '✅' if got == expect else '❌'
            if got != expect:
                failed += 1
            print(f'{tag} {name:18s} expect={"PASS" if expect else "FAIL"} got={"PASS" if got else "FAIL"}')
        print()
        print('自测通过' if failed == 0 else f'自测失败 {failed} 项')
        return 0 if failed == 0 else 1

    # march + 手动 isa_ext（不查 json）
    if args.march and args.isa_ext and not args.chip:
        isa_ext = [x.strip() for x in args.isa_ext.split(',') if x.strip()]
        ok, err, parts, missing = march_check(args.march, isa_ext)
        print(DIVIDER)
        print('march 校验报告（手动指定 isa_ext）')
        print(DIVIDER)
        print(f'march   : {args.march}')
        if parts:
            print(f'拆分结果: {fmt_list(parts)}')
        print(f'isa_ext : {fmt_list(isa_ext)}')
        if err:
            print(f'❌ [ERROR] {err}')
            return 1
        if ok:
            print(f'✅ PASS — 拆分出的 {len(parts)} 项全部在 isa_ext 中')
            return 0
        print(f'❌ FAIL — 以下 {len(missing)} 项不在 isa_ext 中: {fmt_list(missing)}')
        return 1

    need = [args.march, args.toolchain, args.abi, args.startfile_dir]
    if not any(need):
        sys.exit('[FATAL] 至少提供 --march / --toolchain / --abi / --startfile-dir 之一')
    if not args.chip:
        sys.exit('[FATAL] 需要 --chip（或 march 校验时用 --isa-ext 代替）')

    isa = load_isa()
    installed = [x.strip() for x in (args.installed_toolchains or '').split(',') if x.strip()]
    chk = Checker(args.chip, args.core, installed)
    chk.resolve(isa)
    cores = chk.entry.get('cores', [])
    core_label = pick_core(cores, args.core)['core'] if args.core else '全部内核'

    print(DIVIDER)
    print(f'编译配置校验报告（{chk.chip["name"]} / 系列 {chk.entry["series"]} / 内核 {core_label}）')
    print(DIVIDER)
    if args.march:
        chk.check_march(args.march)
    if args.toolchain:
        chk.check_toolchain(args.toolchain)
    if args.abi:
        chk.check_abi(args.abi)
    if args.startfile_dir:
        chk.check_startfile(args.startfile_dir)
    marks = {'ok': '✅', 'fail': '❌', 'warn': '⚠', 'info': 'ℹ'}
    for name, verdict, text in chk.rows:
        print(f'  {marks[verdict]} [{name}] {text}')
    print()
    total_ok = all(v != 'fail' for _, v, _ in chk.rows)
    print(f'结论: {"✅ PASS — 全部校验通过" if total_ok else "❌ FAIL — 存在不匹配项"}')
    return 0 if total_ok else 1


if __name__ == '__main__':
    sys.exit(main())
