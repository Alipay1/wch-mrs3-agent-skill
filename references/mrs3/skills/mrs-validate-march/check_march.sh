#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# check_march.sh — 校验工程编译配置与 mcu_isa.json 是否匹配（原生 bash 实现，不依赖 Python）。
#
# 逻辑与 check_march.py 一致：
#   1. march: 必须 rv32 开头；按 _ 分割，首段去掉 rv32 后逐字符拆分，后续段原样保留；
#      拆分出的每一项必须在该内核 isa_ext 中（成员关系，不要求顺序一致），全部命中才 PASS；
#   2. toolchain: component_toolchain 必须在系列 toolchain 数组中；
#   3. abi: riscvTargetProcessor.integer_ABI 必须在内核 mabi 数组中；
#   4. startfile: --startfile-dir 目录下 .S 文件与型号 startfile 数组比对（只提示，不修改）。
#
# 用法：
#   ./check_march.sh --chip CH32H417WEU --core v5f --march rv32imafc_zba_zbb_zbc_zbs_xw --toolchain GCC15 --abi ilp32f
#   ./check_march.sh --chip CH32V203CCT --startfile-dir <工程>/Common/Startup
#   ./check_march.sh --march rv32imac_xw --isa-ext i,m,a,c,xw      # 手动指定扩展，不查 json
#   ./check_march.sh --selftest
#
# 注意：mcu_isa.json 固定从本脚本所在目录（技能目录）加载，不接受路径参数。
# 退出码：0 = 全部 PASS；1 = 存在 FAIL 或参数错误。
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISA="$SKILL_DIR/mcu_isa.json"
DIVIDER="$(printf '%*s' 72 '' | tr ' ' '=')"

# ---------------------------------------------------------------------------
# 内嵌 awk：从 mcu_isa.json 提取目标芯片所属系列的扁平记录
#   输出行（TARGET 芯片所在系列）：
#     NOTFOUND|1            芯片不存在
#     SERIES|<series>
#     TOOLCHAIN|<item>      每个 toolchain 项一行
#     CORE|<label>|<isa_ext 逗号连接>|<mabi 逗号连接>   每个内核一行
#     STARTFILE|<item>      目标芯片 startfile 每项一行（[] 时不输出 → 视为空）
# ---------------------------------------------------------------------------
read -r -d '' EXTRACT_AWK <<'AWK'
function val(s,    t) {
    t = s
    sub(/^.*:[[:space:]]*"/, "", t)   # "key": "value", → 剥到 value 开引号
    sub(/^[[:space:]]*"/, "", t)      # 数组裸项 "item", → 剥前导空白与开引号
    sub(/".*$/, "", t)                # 从闭引号起剥到行尾
    return t
}
BEGIN { target = toupper(TARGET); chip_hit = 0; sf_hit = 0; series_hit = 0; hit_series = ""; in_sf = 0; in_tc = 0; in_cores = 0; in_mabi = 0; in_isa = 0 }
{
    line = $0
    if (line ~ /"series"/) { series = val(line); chip_hit = 0; sf_hit = 0; in_tc = 0; in_cores = 0; next }
    if (line ~ /"name"/) {
        # sf_hit：当前芯片是否为目标芯片（startfile 用）；chip_hit：系列内命中锁存（toolchain/cores 用）
        sf_hit = (toupper(val(line)) == target)
        if (sf_hit) { chip_hit = 1; series_hit = 1; hit_series = series }
        in_sf = 0
        next
    }
    if (line ~ /"startfile"/) {
        if (sf_hit && !(line ~ /\]/)) in_sf = 1
        else in_sf = 0
        next
    }
    if (in_sf) {
        if (line ~ /\]/) { in_sf = 0; next }
        v = val(line)
        if (v != "") print "STARTFILE|" v
        next
    }
    if (line ~ /"toolchain"/) { in_tc = !(line ~ /\]/); next }
    if (in_tc) {
        if (line ~ /\]/) { in_tc = 0; next }
        v = val(line)
        if (chip_hit && v != "") print "TOOLCHAIN|" v
        next
    }
    if (line ~ /"cores"/) { in_cores = !(line ~ /\]/); core_label = ""; isa = ""; mabi = ""; in_mabi = 0; in_isa = 0; next }
    if (in_cores) {
        if (line ~ /"core"/) { core_label = val(line); next }
        if (line ~ /"mabi"/) { in_mabi = !(line ~ /\]/); next }
        if (line ~ /"isa_ext"/) { in_isa = !(line ~ /\]/); next }
        if (in_mabi) {
            if (line ~ /\]/) { in_mabi = 0; next }
            v = val(line)
            mabi = mabi (mabi == "" ? "" : ",") v
            next
        }
        if (in_isa) {
            if (line ~ /\]/) { in_isa = 0; next }
            v = val(line)
            isa = isa (isa == "" ? "" : ",") v
            next
        }
        if (line ~ /^[[:space:]]*\}/) {
            if (chip_hit && core_label != "") print "CORE|" core_label "|" isa "|" mabi
            core_label = ""; isa = ""; mabi = ""; in_mabi = 0; in_isa = 0
            next
        }
    }
}
END {
    if (series_hit) print "SERIES|" hit_series
    else print "NOTFOUND|1"
}
AWK

# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------
ROWS=""          # 每行: mark<TAB>name<TAB>text（mark: ✅❌⚠ℹ；TAB 不会出现在文本中）
TOTAL_FAIL=0

add_row() { ROWS="$ROWS
$1	$2	$3"; }

fmt() { local IFS=,; echo "$*"; }

# load_chip <chip>：设置 SERIES / TOOLCHAIN_LIST / CORE_LINES / STARTFILE_LIST / CHIP_FOUND
load_chip() {
    local chip="$1" kind rest
    SERIES=""; TOOLCHAIN_LIST=""; CORE_LINES=""; STARTFILE_LIST=""; CHIP_FOUND=1
    while IFS='|' read -r kind rest; do
        case "$kind" in
            NOTFOUND) CHIP_FOUND=0 ;;
            SERIES) SERIES="$rest" ;;
            TOOLCHAIN) TOOLCHAIN_LIST="$TOOLCHAIN_LIST|$rest" ;;
            CORE) CORE_LINES="$CORE_LINES"$'\n'"$rest" ;;
            STARTFILE) STARTFILE_LIST="$STARTFILE_LIST|$rest" ;;
        esac
    done < <(awk -v TARGET="$chip" "$EXTRACT_AWK" "$ISA")
}

# pick_core <sel>：echo "label|isa|mabi"（子串匹配，大小写不敏感）；未命中返回 1
pick_core() {
    local sel="$1" label isa mabi
    sel="$(printf '%s' "$sel" | tr 'A-Z' 'a-z')"
    while IFS='|' read -r label isa mabi; do
        [ -n "$label" ] || continue
        case "$(printf '%s' "$label" | tr 'A-Z' 'a-z')" in
            *"$sel"*) echo "$label|$isa|$mabi"; return 0 ;;
        esac
    done < <(printf '%s\n' "$CORE_LINES")
    return 1
}

core_count() {
    [ -z "$CORE_LINES" ] && { echo 0; return; }
    printf '%s\n' "$CORE_LINES" | awk 'NF' | wc -l | tr -d ' '
}

# split_march <march>：设置 MARCH_PARTS（数组）与 MARCH_ERR；出错返回 1
MARCH_PARTS=()
MARCH_ERR=""
split_march() {
    local m="$1" rest
    MARCH_ERR=""
    MARCH_PARTS=()
    m="$(printf '%s' "$m" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr 'A-Z' 'a-z')"
    [ -n "$m" ] || { MARCH_ERR='march 为空'; return 1; }
    case "$m" in
        rv32*) : ;;
        *) MARCH_ERR="march 必须以 rv32 开头（实际: $1）"; return 1 ;;
    esac
    rest="${m#rv32}"
    [ -n "$rest" ] || { MARCH_ERR='march 在 rv32 之后为空'; return 1; }
    local segs_str="$rest" k
    local first="${segs_str%%_*}"
    local tail="${segs_str#*_}"
    for ((k = 0; k < ${#first}; k++)); do MARCH_PARTS+=("${first:$k:1}"); done
    [ "$tail" = "$segs_str" ] || {
        local seg
        while IFS= read -r seg; do
            [ -n "$seg" ] && MARCH_PARTS+=("$seg")
        done <<< "$(printf '%s' "$tail" | tr '_' '\n')"
    }
    return 0
}

# march_check <march> <isa_ext 逗号连接>：设置 MARCH_OK / MARCH_ERR / MARCH_PARTS / MARCH_MISSING
MARCH_OK=0
MARCH_MISSING=""
march_check() {
    local march="$1" isa="$2" p
    MARCH_OK=0; MARCH_MISSING=""
    split_march "$march" || return 1
    for p in "${MARCH_PARTS[@]}"; do
        case ",$isa," in
            *",$p,"*) : ;;
            *) MARCH_MISSING="$MARCH_MISSING,$p" ;;
        esac
    done
    MARCH_MISSING="${MARCH_MISSING#,}"
    [ -z "$MARCH_MISSING" ] && MARCH_OK=1
    return 0
}

# ---------------------------------------------------------------------------
# 校验器
# ---------------------------------------------------------------------------
check_march() {  # $1 = march
    local core_line label isa mabi t any_pass
    core_line="$(pick_core "${CORE_SEL:-}")"
    if [ -n "$core_line" ]; then
        label="${core_line%%|*}"; local rest="${core_line#*|}"
        isa="${rest%%|*}"; mabi="${rest#*|}"
        march_check "$1" "$isa" || { add_row '❌' 'march' "$MARCH_ERR"; return 1; }
        t="march=$1 → 拆分: $(fmt "${MARCH_PARTS[@]}") | isa_ext[$SERIES $label]: $isa"
        if [ -n "$MARCH_MISSING" ]; then t="$t | 缺失: $MARCH_MISSING"; else t="$t | 全部命中"; fi
        if [ "$MARCH_OK" = "1" ]; then add_row '✅' 'march' "$t"; return 0
        else add_row '❌' 'march' "$t"; return 1; fi
    fi
    add_row 'ℹ' 'march' "未指定内核，对芯片全部 $(core_count) 个内核逐一比对:"
    any_pass=0
    while IFS='|' read -r label isa mabi; do
        [ -n "$label" ] || continue
        march_check "$1" "$isa"
        if [ "$MARCH_OK" = "1" ]; then
            any_pass=1
            add_row '✅' 'march' "vs $SERIES $label isa_ext=[$isa]"
        else
            add_row '❌' 'march' "vs $SERIES $label isa_ext=[$isa] → 缺失: $MARCH_MISSING"
        fi
    done < <(printf '%s\n' "$CORE_LINES")
    if [ "$any_pass" = "1" ]; then
        add_row '✅' 'march' '结果: PASS（至少一个内核匹配）'; return 0
    fi
    add_row '❌' 'march' '结果: FAIL（所有内核均不匹配）'
    return 1
}

check_toolchain() {  # $1 = value
    local allowed="${TOOLCHAIN_LIST#|}" ok=0
    case "|$TOOLCHAIN_LIST|" in
        *"|$1|"*) ok=1 ;;
    esac
    local allowed_fmt="${allowed//|/, }"
    if [ "$ok" = "1" ]; then
        add_row '✅' 'toolchain' "component_toolchain=$1 | 允许值[$SERIES]: $allowed_fmt"
    else
        add_row '❌' 'toolchain' "component_toolchain=$1 | 允许值[$SERIES]: $allowed_fmt | ❌ $1 不在允许列表中"
    fi
    if [ -n "$INSTALLED_TC" ]; then
        inst_fmt="${INSTALLED_TC#|}"
        add_row 'ℹ' 'toolchain' "已安装工具链(ide-get-installed-toolchain): ${inst_fmt//|/, }"
        usable=""
        local t
        local IFS='|'
        for t in $allowed; do
            case "|$INSTALLED_TC|" in
                *"|$t|"*) usable="$usable|$t" ;;
            esac
        done
        unset IFS
        usable="${usable#|}"
        if [ -n "$usable" ]; then
            add_row 'ℹ' 'toolchain' "已安装且允许: ${usable//|/, }"
        else
            add_row 'ℹ' 'toolchain' '已安装且允许: 无'
        fi
        if [ "$ok" = "1" ]; then
            case "|$INSTALLED_TC|" in
                *"|$1|"*) : ;;
                *) add_row '⚠' 'toolchain' "当前工具链 $1 不在已安装列表中（ide-get-installed-toolchain），请确认" ;;
            esac
        else
            if [ -n "$usable" ]; then
                add_row 'ℹ' 'toolchain' "建议改为已安装且允许的工具链: ${usable%%|*}（通过 ide-set-project-build-property 修改 component_toolchain）"
            else
                add_row '⚠' 'toolchain' '无已安装且允许的工具链（需要先安装对应工具链，或核对已安装列表）'
            fi
        fi
    fi
    [ "$ok" = "1" ] && return 0
    return 1
}

check_abi() {  # $1 = value
    local core_line label isa mabi t any_pass
    core_line="$(pick_core "${CORE_SEL:-}")"
    if [ -n "$core_line" ]; then
        label="${core_line%%|*}"; local rest="${core_line#*|}"
        isa="${rest%%|*}"; mabi="${rest#*|}"
        case ",$mabi," in
            *",$1,"*) add_row '✅' 'abi' "riscvTargetProcessor.integer_ABI=$1 | 允许值[$SERIES $label]: ${mabi//,/, }"; return 0 ;;
            *) add_row '❌' 'abi' "riscvTargetProcessor.integer_ABI=$1 | 允许值[$SERIES $label]: ${mabi//,/, } | ❌ $1 不在允许列表中"; return 1 ;;
        esac
    fi
    add_row 'ℹ' 'abi' "未指定内核，对芯片全部 $(core_count) 个内核逐一比对:"
    any_pass=0
    while IFS='|' read -r label isa mabi; do
        [ -n "$label" ] || continue
        case ",$mabi," in
            *",$1,"*) any_pass=1; add_row '✅' 'abi' "vs $SERIES $label mabi=[${mabi//,/, }]" ;;
            *) add_row '❌' 'abi' "vs $SERIES $label mabi=[${mabi//,/, }]" ;;
        esac
    done < <(printf '%s\n' "$CORE_LINES")
    if [ "$any_pass" = "1" ]; then
        add_row '✅' 'abi' '结果: PASS（至少一个内核匹配）'; return 0
    fi
    add_row '❌' 'abi' '结果: FAIL（所有内核均不匹配）'
    return 1
}

check_startfile() {  # $1 = dir
    local expected="${STARTFILE_LIST#|}" found missing extra
    if [ -z "$expected" ]; then
        add_row 'ℹ' 'startfile' "芯片 $CHIP 在 mcu_isa.json 中 startfile 为空（[]），跳过校验"; return 0
    fi
    if [ ! -d "$1" ]; then
        add_row '❌' 'startfile' "Startup 目录不存在: $1"; return 1
    fi
    found="$(ls -1 "$1" 2>/dev/null | awk '{ if (toupper($0) ~ /\.S$/) print }' | sort | tr '\n' '|' | sed 's/|$//')"
    missing=""
    local e f
    local IFS='|'
    for e in $expected; do
        case "|$found|" in
            *"|$e|"*) : ;;
            *) missing="$missing,$e" ;;
        esac
    done
    extra=""
    for f in $found; do
        case "|$expected|" in
            *"|$f|"*) : ;;
            *) extra="$extra,$f" ;;
        esac
    done
    unset IFS
    missing="${missing#,}"; extra="${extra#,}"
    local exp_fmt="${expected//|/, }" found_fmt="${found//|/, }"
    if [ -z "$missing" ] && [ -z "$extra" ]; then
        add_row '✅' 'startfile' "Startup 目录 $1 中的 .S 文件与 mcu_isa.json startfile 完全一致: $exp_fmt"; return 0
    fi
    local msg="Startup 目录 $1 与 mcu_isa.json startfile 不一致（只提示，不修改） | 期望(startfile)=$exp_fmt | 实际=$found_fmt"
    [ -n "$missing" ] && msg="$msg | 缺少: $missing"
    [ -n "$extra" ] && msg="$msg | 多余: $extra"
    add_row '⚠' 'startfile' "$msg"
    return 0  # startfile 不一致只提示，不导致 FAIL
}

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
CHIP=""; CORE_SEL=""; MARCH=""; TOOLCHAIN=""; ABI=""; ISA_EXT=""; STARTFILE_DIR=""; INSTALLED_TC=""; SELFTEST=0
usage() {
    echo "用法: $0 --chip CH32H417WEU [--core v3f|v5f] [--march <arch>] [--toolchain <tc>] [--abi <abi>] [--startfile-dir <dir>]"
    echo "      $0 --march <arch> --isa-ext i,m,a,c,xw   (手动指定扩展，不查 json)"
    echo "      $0 --selftest"
}
while [ $# -gt 0 ]; do
    case "$1" in
        --chip) CHIP="${2:-}"; shift 2 ;;
        --core) CORE_SEL="${2:-}"; shift 2 ;;
        --march) MARCH="${2:-}"; shift 2 ;;
        --toolchain) TOOLCHAIN="${2:-}"; shift 2 ;;
        --abi) ABI="${2:-}"; shift 2 ;;
        --isa-ext) ISA_EXT="${2:-}"; shift 2 ;;
        --startfile-dir) STARTFILE_DIR="${2:-}"; shift 2 ;;
        --installed-toolchains) INSTALLED_TC="|$(printf '%s' "${2:-}" | tr ',' '|' | sed 's/^|//; s/||*/|/g; s/|$//')"; shift 2 ;;
        --selftest) SELFTEST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) shift ;;
    esac
done

# -- selftest
if [ "$SELFTEST" = "1" ]; then
    failed=0
    run_case() {  # $1=name $2=expect $3=march $4=isa_ext
        local name="$1" expect="$2" march="$3" isa="$4"
        march_check "$march" "$isa"
        local got="$MARCH_OK" tag
        if [ "$got" = "$expect" ]; then tag='✅'; else tag='❌'; failed=$((failed + 1)); fi
        local e_s p_s
        [ "$expect" = "1" ] && e_s='PASS' || e_s='FAIL'
        [ "$got" = "1" ] && p_s='PASS' || p_s='FAIL'
        printf '%s %-18s expect=%s got=%s\n' "$tag" "$name" "$e_s" "$p_s"
    }
    run_case 'march PASS' 1 'rv32imafc_zba_zbb_zbc_zbs_xw' 'i,m,a,c,f,zba,zbb,zbc,zbs,xw'
    run_case 'march FAIL d' 0 'rv32imafdc_zba_zbb_zbc_zbs_xw' 'i,m,a,c,f,zba,zbb,zbc,zbs,xw'
    run_case 'march FAIL rv64' 0 'rv64imac_xw' 'i,m,a,c,xw'
    run_case 'march FAIL z 扩展' 0 'rv32imac_zba_zbb_zbc_zbs_xw' 'i,m,a,c,xw'
    run_case 'march FAIL 空' 0 'rv32' 'i'
    run_case 'march 顺序无关' 1 'rv32imafc_zba_zbb_zbc_zbs_xw' 'i,m,a,c,f,zba,zbb,zbc,zbs,xw'
    echo
    if [ "$failed" = "0" ]; then echo '自测通过'; exit 0; fi
    echo "自测失败 $failed 项"
    exit 1
fi

# -- march + 手动 isa_ext（不查 json）
if [ -n "$MARCH" ] && [ -n "$ISA_EXT" ] && [ -z "$CHIP" ]; then
    march_check "$MARCH" "$ISA_EXT"
    echo "$DIVIDER"
    echo 'march 校验报告（手动指定 isa_ext）'
    echo "$DIVIDER"
    echo "march   : $MARCH"
    [ "${#MARCH_PARTS[@]}" -gt 0 ] && echo "拆分结果: $(fmt "${MARCH_PARTS[@]}")"
    echo "isa_ext : ${ISA_EXT//,/, }"
    if [ -n "$MARCH_ERR" ]; then echo "❌ [ERROR] $MARCH_ERR"; exit 1; fi
    if [ "$MARCH_OK" = "1" ]; then
        echo "✅ PASS — 拆分出的 ${#MARCH_PARTS[@]} 项全部在 isa_ext 中"; exit 0
    fi
    cnt=0
    [ -n "$MARCH_MISSING" ] && cnt=$(($(printf '%s' "$MARCH_MISSING" | tr -cd ',' | wc -c) + 1))
    echo "❌ FAIL — 以下 ${cnt} 项不在 isa_ext 中: $MARCH_MISSING"
    exit 1
fi

# -- 芯片级校验
if [ -z "$MARCH" ] && [ -z "$TOOLCHAIN" ] && [ -z "$ABI" ] && [ -z "$STARTFILE_DIR" ]; then
    echo '[FATAL] 至少提供 --march / --toolchain / --abi / --startfile-dir 之一' >&2
    exit 1
fi
if [ -z "$CHIP" ]; then
    echo '[FATAL] 需要 --chip（或 march 校验时用 --isa-ext 代替）' >&2
    exit 1
fi
[ -f "$ISA" ] || { echo "[FATAL] mcu_isa.json 不存在: $ISA" >&2; exit 1; }

load_chip "$CHIP"
if [ "$CHIP_FOUND" = "0" ]; then
    echo "[FATAL] 在 mcu_isa.json 中找不到型号 $CHIP" >&2
    exit 1
fi
if [ -n "$CORE_SEL" ] && ! pick_core "$CORE_SEL" >/dev/null; then
    echo "[FATAL] 内核 $CORE_SEL 不在芯片 $CHIP 的 cores 中" >&2
    exit 1
fi

if [ -n "$CORE_SEL" ]; then
    CORE_LABEL="$(pick_core "$CORE_SEL" | cut -d'|' -f1)"
else
    CORE_LABEL='全部内核'
fi

echo "$DIVIDER"
echo "编译配置校验报告（$CHIP / 系列 $SERIES / 内核 $CORE_LABEL）"
echo "$DIVIDER"
[ -n "$MARCH" ] && check_march "$MARCH"
[ -n "$TOOLCHAIN" ] && check_toolchain "$TOOLCHAIN"
[ -n "$ABI" ] && check_abi "$ABI"
[ -n "$STARTFILE_DIR" ] && check_startfile "$STARTFILE_DIR"
printf '%s\n' "$ROWS" | awk -F'\t' 'NF { print "  " $1 " [" $2 "] " $3 }'
echo
if printf '%s\n' "$ROWS" | grep -q '^❌'; then
    echo '结论: ❌ FAIL — 存在不匹配项'
    exit 1
fi
echo '结论: ✅ PASS — 全部校验通过'
exit 0
