#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
扫描 CH32V003 客户工程，找出迁移到 CH32V002 / CH32V005 时需要处理的符号。

用法:
    python scan_v003_symbols.py <工程目录> [--target CH32V002|CH32V005] [--all] [--json]

参数:
    <工程目录>   要扫描的工程根目录
    --target     目标型号（用于 OPA 等按目标分流的判定），可选
    --all        连纯模板/库目录（Peripheral/Core/Startup/Ld）一起扫，默认跳过
    --json       以 JSON 输出

输出分类:
    [必须人工核对]  编译器零提示 —— 同名异值宏、重映射、页粒度、core_riscv 等待类
    [需改名]        目标库无此符号，改名后编译通过
    [建议删除]      目标芯片无此功能
    [提示]          行为变化或按目标型号分流的告知项

【维护约定】本脚本与同目录 scan_v003_symbols.ps1 功能等价，共用 data.json。
修改任一脚本（判定规则、分类、提示文案、data.json 字段、输出格式）时，两者必须同步更新。

【JSON 输出格式】（--json / -Json 一致）
    {
      "root": "...", "target": "CH32V005", "files": 10,
      "manual":   [ {"loc": "User/main.c:52", "sym": "DBGMCU_GetCHIPID", "note": "..."}, ... ],
      "rename":   [ ... ], "deletion": [ ... ], "notice": [ ... ]
    }
"""
import os, re, sys, json, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(HERE, "data.json"), encoding="utf-8"))

SRC_EXT = (".c", ".h", ".cpp", ".hpp", ".S", ".s")
# 默认跳过的纯模板/库目录（工程级转换后应为目标侧版本）
# 注意：Debug/ 不跳过 —— 其中的 debug.c 含 USART 重映射等工程级配置，需一并核对
LIB_DIRS = ("peripheral", "core", "startup", "ld", "library")

# ---------------------------------------------------------------- 分类规则

MANUAL_EXACT = sorted(DATA["diff_value_macros"].keys())        # 同名异值宏
MANUAL_PREFIX = [
    "GPIO_FullRemap", "GPIO_PartialRemap", "GPIO_Remap_", "AFIO_PCFR1_",
    "GPIO_CFGLR_MODE", "GPIO_Pin_All",
]
MANUAL_SYM = [
    "GPIO_PinRemapConfig",
    "DBGMCU_GetCHIPID", "DBGMCU_GetDEVID", "DBGMCU_GetREVID",
    "FLASH_ErasePage", "FLASH_ErasePage_Fast", "FLASH_ProgramPage_Fast",
    "FLASH_BufLoad", "FLASH_BufReset", "FLASH_ROM_ERASE", "FLASH_ROM_WRITE",
    "FLASH_EnableWriteProtection",
    "OPA_Init", "OPA_StructInit", "OPA_Cmd",
    "USART_Init", "ADC_RegularChannelConfig", "ADC_InjectedChannelConfig",
    "RCC_SYSCLKConfig",
]
WAIT_SYMS = ["WFItoWFE", "_WFE_", "__WFE", "__WFI"]

MANUAL_NOTE = {
    "GPIO_PinRemapConfig": "重映射参数两侧不通用，必须按目标引脚重选（references/06_gpio.md 6.5）",
    "GPIO_FullRemap": "重映射宏同名但值不同（references/06_gpio.md 6.5）",
    "GPIO_PartialRemap": "重映射宏同名但值不同（references/06_gpio.md 6.5）",
    "GPIO_Remap_": "重映射宏同名但值不同（references/06_gpio.md 6.5）",
    "AFIO_PCFR1_": "AFIO 重映射位定义两侧不同（references/06_gpio.md 6.5）",
    "GPIO_CFGLR_MODE": "GPIO 配置寄存器位布局两侧不同（references/06_gpio.md 6.5）",
    "GPIO_Pin_All": "V003=0xFFFF / 目标=0x00FF，只覆盖低 8 位（references/06_gpio.md 6.3）",
    "DBGMCU_GetCHIPID": "读的寄存器地址不同（0x1FFFF7C4 vs 0x1FFFF704），返回值必变（references/07 7.1）",
    "DBGMCU_GetDEVID": "芯片 ID 寄存器地址不同（references/07 7.1）",
    "DBGMCU_GetREVID": "芯片 ID 寄存器地址不同（references/07 7.1）",
    "FLASH_ErasePage": "页粒度 64B->256B，循环擦写会连带擦掉相邻数据（references/05_flash.md）",
    "FLASH_ErasePage_Fast": "页粒度 64B->256B（references/05_flash.md）",
    "FLASH_ProgramPage_Fast": "页粒度 64B->256B（references/05_flash.md）",
    "FLASH_BufLoad": "页缓冲 64B->256B（references/05_flash.md 5.2）",
    "FLASH_BufReset": "页缓冲 64B->256B（references/05_flash.md 5.2）",
    "FLASH_ROM_ERASE": "地址对齐 %64->%256（references/05_flash.md 5.1）",
    "FLASH_ROM_WRITE": "地址对齐 %64->%256（references/05_flash.md 5.1）",
    "FLASH_EnableWriteProtection": "写保护粒度 16 页/组->8 页/组（references/05_flash.md 5.3）",
    "OPA_Init": "OPA_InitTypeDef 成员 2->15，同名不同义；V002 删除 / V005 重写（references/04 4.4）",
    "OPA_StructInit": "同上（references/04 4.4）",
    "OPA_Cmd": "同上（references/04 4.4）",
    "USART_Init": "目标侧删除 8 倍过采样分支（references/07 7.1）",
    "ADC_RegularChannelConfig": "目标侧删除通道 >9 的采样时间分支（references/07 7.1）",
    "ADC_InjectedChannelConfig": "同上（references/07 7.1）",
    "RCC_SYSCLKConfig": "目标侧删除 HSI 校准分支（references/07 7.1）",
}

MACRO_RENAME = DATA["macro_rename_map"]     # 前缀 -> 新前缀
FUNC_RENAME = DATA["func_rename_map"]       # 符号 -> 新符号
REG_RENAME = DATA["reg_member_rename_map"]  # 成员 -> 新成员

# 可改名的符号要从「建议删除」里剔除（它们只是改名，不是功能缺失）
_RENAME_PREFIXES = tuple(MACRO_RENAME.keys())
DEL_MACROS = [m for m in DATA["only_v003_macros"] if not m.startswith(_RENAME_PREFIXES)]
DEL_FUNCS = [f for f in DATA["only_v003_funcs"] if f not in FUNC_RENAME]
SPEED_OBSOLETE = DATA["speed_obsolete"]
OPA_SYMS = set(DATA["opa_symbols"])

DEL_NOTE = {
    "OPA_DeInit": "V002 无 OPA -> 删除；V005 -> 按 V005 OPA 库重写（references/04 4.4）",
    "ADC_StartCalibration": "002/5 无 ADC 校准，删除整句",
    "ADC_ResetCalibration": "002/5 无 ADC 校准，删除整句",
    "ADC_GetCalibrationStatus": "002/5 无 ADC 校准，删除整句",
    "ADC_GetResetCalibrationStatus": "002/5 无 ADC 校准，删除整句",
    "ADC_Calibration_Vol": "002/5 无 ADC 校准，删除整句",
    "ADC_ExternalTrig_DLY": "002/5 无 ADC->DLYR，删除整句",
    "FLASH_ProgramHalfWord": "002/5 不支持半字写 -> 改用 Fast 编程（references/05_flash.md 5.2）",
    "FLASH_ProgramWord": "目标侧无此函数 -> 改用 Fast 编程或 ROM 接口（references/05_flash.md 5.2）",
    "FLASH_ProgramOptionByteData": "目标侧无此函数（references/05_flash.md 5.2）",
}

# ---------------------------------------------------------------- 正则

def word_re(names):
    return re.compile(r"\b(" + "|".join(re.escape(x) for x in names) + r")\b")


RE_MANUAL_EXACT = word_re(MANUAL_EXACT)
RE_MANUAL_PREFIX = re.compile(r"\b(" + "|".join(re.escape(x) for x in MANUAL_PREFIX) + r")[A-Za-z0-9_]*")
RE_MANUAL_SYM = word_re(MANUAL_SYM)
RE_WAIT = word_re(WAIT_SYMS)
RE_REG = re.compile(r"->(" + "|".join(re.escape(x) for x in REG_RENAME) + r")\b")
RE_MACRO_RENAME = re.compile(r"\b(" + "|".join(re.escape(k) for k in MACRO_RENAME) + r")[A-Za-z0-9_]*")
RE_FUNC_RENAME = word_re(list(FUNC_RENAME.keys()))
RE_LOWER_INC = re.compile(r"#\s*include\s*[<\"](ch32v00x_[A-Za-z0-9_]+\.h|system_ch32v00x\.h|ch32v00x_it\.h)[>\"]")
RE_HIGHCODE = re.compile(r"\.highcode")
RE_PRIO = re.compile(r"\bNVIC_PriorityGroupConfig\s*\(")
RE_DEL_MACROS = word_re(DEL_MACROS)
RE_DEL_FUNCS = word_re(DEL_FUNCS)
RE_SPEED = word_re(SPEED_OBSOLETE)
RE_OPA = word_re(sorted(OPA_SYMS))


def iter_files(root, scan_all):
    for dirpath, dirnames, filenames in os.walk(root):
        if not scan_all and dirpath != root:
            if os.path.basename(dirpath).lower() in LIB_DIRS:
                dirnames[:] = []
                continue
        for fn in filenames:
            if fn.endswith(SRC_EXT):
                yield os.path.join(dirpath, fn)


def rel(p, root):
    try:
        return os.path.relpath(p, root).replace("\\", "/")
    except ValueError:
        return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--target", default=None)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print("目录不存在: " + root, file=sys.stderr)
        sys.exit(2)

    manual, rename, deletion, notice = [], [], [], []
    n_files = 0

    # 固定遍历顺序，保证 .py 与 .ps1 输出可逐行对照
    for path in sorted(iter_files(root, args.all)):
        n_files += 1
        try:
            lines = open(path, "r", encoding="utf-8", errors="replace").read().split("\n")
        except OSError:
            continue
        rp = rel(path, root)
        for i, line in enumerate(lines, 1):
            loc = "%s:%d" % (rp, i)

            # 必须人工核对
            for mo in RE_MANUAL_EXACT.finditer(line):
                s = mo.group(1)
                manual.append((loc, s, "同名异值宏（V003=%s / 目标=%s）"
                               % (DATA["diff_value_macros"][s][0], DATA["diff_value_macros"][s][1])))
            for mo in RE_MANUAL_PREFIX.finditer(line):
                s = mo.group(0)
                manual.append((loc, s, MANUAL_NOTE.get(mo.group(1), "重映射/寄存器位定义两侧不同")))
            for mo in RE_MANUAL_SYM.finditer(line):
                s = mo.group(1)
                manual.append((loc, s, MANUAL_NOTE.get(s, "实现或行为已变（references/07）")))
            for mo in RE_WAIT.finditer(line):
                s = mo.group(1)
                manual.append((loc, s, "core_riscv 等待类，目标侧实现不同（references/08）"))
            if RE_HIGHCODE.search(line):
                manual.append((loc, ".highcode", "目标侧无 .highcode 段，链接期报错（references/01 第 3 节）"))

            # 需改名
            for mo in RE_REG.finditer(line):
                s = mo.group(1)
                rename.append((loc, "RCC->" + s, "RCC->" + REG_RENAME[s] + "（references/02 2.1）"))
            for mo in RE_MACRO_RENAME.finditer(line):
                s = mo.group(0)
                pref = mo.group(1)
                rename.append((loc, s, s.replace(pref, MACRO_RENAME[pref], 1)))
            for mo in RE_FUNC_RENAME.finditer(line):
                s = mo.group(1)
                new = FUNC_RENAME[s]
                note = new
                if s == "FLASH_ReadOutProtection":
                    note = "FLASH_EnableReadOutProtection()  <- 去掉参数"
                rename.append((loc, s, note))
            for mo in RE_LOWER_INC.finditer(line):
                s = mo.group(1)
                rename.append((loc, "<" + s + ">", "<" + s.replace("ch32v00x", "ch32v00X") + ">"))

            # 建议删除
            for mo in RE_DEL_MACROS.finditer(line):
                deletion.append((loc, mo.group(1), "目标侧无此宏（目标芯片无此功能），建议删除并确认功能不退化"))
            for mo in RE_DEL_FUNCS.finditer(line):
                s = mo.group(1)
                note = DEL_NOTE.get(s, "目标侧无此函数，建议删除并确认功能不退化")
                if s.startswith("USART_") and s not in DEL_NOTE:
                    note = "002/5 无智能卡/同步时钟功能，删除并在报告标注功能缺失"
                deletion.append((loc, s, note))

            # 提示
            for mo in RE_SPEED.finditer(line):
                notice.append((loc, mo.group(1), "目标侧只有 GPIO_Speed_30MHz，统一替换（references/06 6.1）"))
            if RE_PRIO.search(line):
                notice.append((loc, "NVIC_PriorityGroupConfig", "已核实两侧行为一致，不用改（references/07 7.3）"))
            if args.target and args.target.upper() == "CH32V002":
                for mo in RE_OPA.finditer(line):
                    notice.append((loc, mo.group(1), "目标为 V002（无 OPA），需在最终报告告知用户"))

    def dedup(rows):
        seen, out = set(), []
        for r in rows:
            k = (r[0], r[1])
            if k in seen:
                continue
            seen.add(k)
            out.append(r)
        return out

    manual, rename, deletion, notice = map(dedup, (manual, rename, deletion, notice))

    if args.json:
        def rows_json(rows):
            return [{"loc": a, "sym": b, "note": c} for a, b, c in rows]

        print(json.dumps({"root": root, "target": args.target, "files": n_files,
                          "manual": rows_json(manual), "rename": rows_json(rename),
                          "deletion": rows_json(deletion), "notice": rows_json(notice)},
                         ensure_ascii=False, indent=1))
        return

    W = 100
    print("=" * W)
    print("CH32V003 -> CH32V002/CH32V005 迁移扫描报告")
    print("扫描目录: " + root)
    print("目标型号: " + (args.target or "(未指定)"))
    print("扫描文件: %d 个%s" % (n_files, "" if args.all else "（已跳过 Peripheral/Core/Startup/Ld）"))
    print("=" * W)

    def dump(title, rows):
        print()
        print("-" * W)
        print("%s  (%d)" % (title, len(rows)))
        print("-" * W)
        if not rows:
            print("  (无)")
            return
        for loc, sym, note in rows:
            print("  %-44s %s" % (loc, sym))
            print("      " + note)

    dump("[必须人工核对] 编译器零提示，必须逐条处理", manual)
    dump("[需改名] 目标库无此符号，改名后编译通过", rename)
    dump("[建议删除] 目标芯片无此功能", deletion)
    dump("[提示] 行为变化 / 按目标型号分流", notice)

    print()
    print("=" * W)
    print("汇总: 必须人工核对 %d 处 | 需改名 %d 处 | 建议删除 %d 处 | 提示 %d 处"
          % (len(manual), len(rename), len(deletion), len(notice)))
    print("处理依据见 references/ 目录下 02~08 各文件。")
    print("=" * W)


if __name__ == "__main__":
    main()
