#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# check_debug.sh — 调试前检查（WCH RISC-V 工程，原生 bash 实现，不依赖 Python）。
#
# 检查项：
#   规则1  FLASH / RAM 容量：解析 link.ld MEMORY 块，FLASH*/RAM* 区域 LENGTH 全部相加后，
#          必须分别【小于等于】mcu_isa.json 中该芯片的最大 flash / sram（total <= max）。
#   规则2  ROM/RAM 可配置芯片：--ram-avail <值> 传入“当前硬件配置”读到的 RAM 值，
#          校验 总RAM <= 该值（未提供时仅提示，由 skill 决定是否需要）。
#   规则3  FLASH 起始地址检测（仅报告，不判 FAIL）：任一 link.ld 的 FLASH ORIGIN != 0 时
#          输出 ⚠ 提示——由 skill 询问用户“0 地址是否有程序”后决定处理方式。
#   断点上限：读取 mcu_isa.json 中该芯片的 maxbreakpoint 字段（可缺省/为空 = 不限制）；
#          --breakpoints <n> 可硬校验。
#
# 用法：
#   ./check_debug.sh <link.ld> [link.ld2] --chip CH32H417WEU \
#       [--ram-avail 896K] [--breakpoints 3] [--quiet]
#   ./check_debug.sh --selftest
#
# 注意：mcu_isa.json 固定从本脚本所在目录（技能目录）加载，不接受路径参数。
# 退出码：0 = PASS；1 = 存在 FAIL；2 = FATAL。
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISA="$SKILL_DIR/mcu_isa.json"

# ---------------------------------------------------------------------------
# 内嵌 awk 程序
# ---------------------------------------------------------------------------
# 1) 剥离 /* */（跨行）与 // 注释，保留换行（行号不变）
read -r -d '' STRIP_COMMENTS_AWK <<'AWK'
BEGIN { inc = 0 }
{
    s = $0
    out = ""
    while (length(s) > 0) {
        if (inc) {
            p = index(s, "*/")
            if (p == 0) { s = ""; break }
            s = substr(s, p + 2)
            inc = 0
        } else {
            p1 = index(s, "/*")
            p2 = index(s, "//")
            if (p1 == 0 && p2 == 0) { out = out s; break }
            if (p1 > 0 && (p2 == 0 || p1 < p2)) {
                out = out substr(s, 1, p1 - 1)
                s = substr(s, p1 + 2)
                inc = 1
            } else {
                out = out substr(s, 1, p2 - 1)
                break
            }
        }
    }
    print out
}
AWK

# 2) 定位 MEMORY 块，输出 "起始行 结束行"
read -r -d '' MEMORY_AWK <<'AWK'
BEGIN { mem = 0; started = 0; depth = 0; start = 0; done = 0 }
{
    if (done) next
    if (!started) {
        if ($0 ~ /^[[:space:]]*MEMORY([[:space:]]*\{|[[:space:]]*$)/) mem = 1
        if (mem && index($0, "{") > 0) { started = 1; start = NR }
    }
    if (started) {
        t = $0
        o = gsub(/{/, "", t)
        c = gsub(/}/, "", t)
        depth += o - c
        if (depth <= 0) { print start, NR; done = 1 }
    }
}
AWK

# 3) 芯片数据：series|name|flash|sram（每芯片一行）
read -r -d '' ISA_AWK <<'AWK'
/"series"/ { s = $0; sub(/^.*"series"[[:space:]]*:[[:space:]]*"/, "", s); sub(/".*$/, "", s); series = s }
/"name"/   { n = $0; sub(/^.*"name"[[:space:]]*:[[:space:]]*"/, "", n); sub(/".*$/, "", n); name = n }
/"flash"/  { f = $0; sub(/^.*"flash"[[:space:]]*:[[:space:]]*"/, "", f); sub(/".*$/, "", f); flash = f }
/"sram"/   { r = $0; sub(/^.*"sram"[[:space:]]*:[[:space:]]*"/, "", r); sub(/".*$/, "", r); if (name != "") print series "|" name "|" flash "|" r }
AWK

# 4) maxbreakpoint：name|值（可缺省；兼容数组形式 [] = 不限制、[4] = 上限 4、标量 4）
read -r -d '' MAXBP_AWK <<'AWK'
function mbval(s,    t) {
    t = s
    sub(/^.*"maxbreakpoint"[[:space:]]*:[[:space:]]*/, "", t)
    sub(/[",}].*$/, "", t)
    sub(/^\[/, "", t)
    sub(/\]$/, "", t)
    sub(/^[[:space:]]+/, "", t)
    sub(/[[:space:]]+$/, "", t)
    return t
}
/"name"/ { n = $0; sub(/^.*"name"[[:space:]]*:[[:space:]]*"/, "", n); sub(/".*$/, "", n); name = n }
/"maxbreakpoint"/ {
    if (name == "") next
    if ($0 ~ /\]/) {          # 单行：[] 或 [4] 或 4
        v = mbval($0)
        print name "|" v
        in_mb = 0
    } else {
        in_mb = 1             # 多行数组开始（[ 换行 数字 换行 ]）
    }
    next
}
in_mb {
    if ($0 ~ /\]/) { in_mb = 0; got_mb = 0; next }
    if (got_mb) next
    v = mbval($0)
    if (v != "") { print name "|" v; got_mb = 1 }
    next
}
AWK

# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------
ROWS=""          # 每行: 标记<TAB>文本（标记: ✅ / ⚠ [WARN] / ❌ [ERROR] / ℹ [INFO]）
ERRORS=0
WARNS=0

add_ok()   { ROWS="$ROWS"$'\n'"✅	$1"; }
add_warn() { ROWS="$ROWS"$'\n'"⚠ [WARN]	$1"; WARNS=$((WARNS + 1)); }
add_err()  { ROWS="$ROWS"$'\n'"❌ [ERROR]	$1"; ERRORS=$((ERRORS + 1)); }
add_info() { ROWS="$ROWS"$'\n'"ℹ [INFO]	$1"; }

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# calc_length "表达式" → 输出十进制字节数；失败输出空并返回 1
calc_length() {
    local s rest out v
    s="$(trim "${1%;}")"
    [ -z "$s" ] && return 1
    rest="$(printf '%s' "$s" | sed -E 's/0[xX][0-9a-fA-F]+[KMGkmg]?/N/g; s/[0-9]+[KMGkmg]?/N/g')"
    case "$rest" in
        *[A-Za-z]*) return 1 ;;
    esac
    out="$(printf '%s' "$s" | sed -E \
        's/(0[xX][0-9a-fA-F]+)[Kk]/(\1 * 1024)/g;
         s/(0[xX][0-9a-fA-F]+)[Mm]/(\1 * 1024 * 1024)/g;
         s/(0[xX][0-9a-fA-F]+)[Gg]/(\1 * 1024 * 1024 * 1024)/g;
         s/([0-9]+)[Kk]/(\1 * 1024)/g;
         s/([0-9]+)[Mm]/(\1 * 1024 * 1024)/g;
         s/([0-9]+)[Gg]/(\1 * 1024 * 1024 * 1024)/g')"
    if ! v=$(( out )) 2>/dev/null; then
        return 1
    fi
    echo "$v"
    return 0
}

fmt_size() {
    local n="$1"
    if [ "$n" -ge 1048576 ]; then
        awk -v n="$n" 'BEGIN { v = n / 1048576; if (v == int(v)) printf "%dM", v; else printf "%.1fM", v }'
    elif [ "$n" -ge 1024 ]; then
        awk -v n="$n" 'BEGIN { v = n / 1024; if (v == int(v)) printf "%dK", v; else printf "%.1fK", v }'
    else
        echo "$n"
    fi
}

# find_chip <型号> → 设置 SERIES / CHIP_FLASH_STR / CHIP_SRAM_STR；找不到返回 1
ISA_FLAT=""
find_chip() {
    local chip="$1" line
    [ -n "$ISA_FLAT" ] || ISA_FLAT="$(awk "$ISA_AWK" "$ISA")"
    line="$(printf '%s\n' "$ISA_FLAT" | awk -F'|' -v c="$chip" 'toupper($2) == toupper(c) { print; exit }')"
    if [ -z "$line" ]; then
        SERIES=""; CHIP_FLASH_STR=""; CHIP_SRAM_STR=""
        return 1
    fi
    SERIES="${line%%|*}"; line="${line#*|}"; line="${line#*|}"
    CHIP_FLASH_STR="${line%%|*}"; CHIP_SRAM_STR="${line#*|}"
    return 0
}

# find_maxbp <型号> → 输出 maxbreakpoint 值（无字段/空 = 不限制）
find_maxbp() {
    awk "$MAXBP_AWK" "$ISA" | awk -F'|' -v c="$1" 'toupper($1) == toupper(c) { print $2; exit }'
}

# ---------------------------------------------------------------------------
# link.ld 解析：设置 CUR_FLASH_TOTAL / CUR_RAM_TOTAL / FIRST_FLASH_ORIGIN / FIRST_FLASH_LINE
# ---------------------------------------------------------------------------
REGION_RE='^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([^)]*\)[[:space:]]*:[[:space:]]*ORIGIN[[:space:]]*=[[:space:]]*[^,]+,[[:space:]]*LENGTH[[:space:]]*=.+$'

CUR_FLASH_TOTAL=""; CUR_RAM_TOTAL=""; FIRST_FLASH_ORIGIN=""; FIRST_FLASH_LINE=""

parse_ld() {
    local path="$1"
    local text clean mem_info mem_start mem_end i line name attrs origin_s length_s origin length kind
    local n_flash=0 n_ram=0 flash_total="" ram_total="" first_f_origin="" first_f_line=""
    local total_lines ln

    [ -f "$path" ] || { echo "[FATAL] 文件不存在: $path" >&2; return 1; }
    text="$(tr -d '\r' < "$path")"   # 统一换行：去除 CRLF/CR 的 \r，避免行粘连、解析/行号出错
    clean="$(printf '%s\n' "$text" | awk "$STRIP_COMMENTS_AWK")"

    mem_info="$(printf '%s\n' "$clean" | awk "$MEMORY_AWK")"
    [ -n "$mem_info" ] || { echo "[FATAL] 无法定位 MEMORY 块: $path" >&2; return 1; }
    mem_start="${mem_info%% *}"
    mem_end="${mem_info##* }"

    CLEAN_LINES=()
    i=0
    while IFS= read -r ln; do
        i=$((i + 1))
        CLEAN_LINES[$i]="$ln"
    done <<< "$clean"
    total_lines=$i

    i="$mem_start"
    while [ "$i" -le "$mem_end" ]; do
        line="$(trim "${CLEAN_LINES[$i]:-}")"
        if [ -n "$line" ] && [ "$line" != '{' ] && [ "$line" != '}' ]; then
            if [[ "$line" =~ $REGION_RE ]]; then
                name="${BASH_REMATCH[1]}"
                attrs="${BASH_REMATCH[2]}"
                origin_s="$(trim "${BASH_REMATCH[3]}")"
                length_s="$(trim "${BASH_REMATCH[4]}")"
                origin="$(calc_length "$origin_s")"
                length="$(calc_length "$length_s")"
                kind=""
                case "$(printf '%s' "$name" | tr 'a-z' 'A-Z')" in
                    FLASH*) kind="flash" ;;
                    RAM*) kind="ram" ;;
                esac
                if [ "$kind" = "flash" ]; then
                    n_flash=$((n_flash + 1))
                    if [ -n "$length" ]; then
                        [ -n "$flash_total" ] || flash_total=0
                        flash_total=$((flash_total + length))
                    fi
                    if [ -z "$first_f_origin" ] && [ -n "$origin" ]; then
                        first_f_origin="$origin"; first_f_line="$i"
                    fi
                elif [ "$kind" = "ram" ]; then
                    n_ram=$((n_ram + 1))
                    if [ -n "$length" ]; then
                        [ -n "$ram_total" ] || ram_total=0
                        ram_total=$((ram_total + length))
                    fi
                fi
            else
                echo "[FATAL] MEMORY 块中存在无法解析的行（第${i}行）: $line" >&2
                return 1
            fi
        fi
        i=$((i + 1))
    done

    [ "$n_flash" -gt 0 ] || { echo "[FATAL] MEMORY 中缺少 FLASH 区域: $path" >&2; return 1; }
    [ "$n_ram" -gt 0 ] || { echo "[FATAL] MEMORY 中缺少 RAM 区域: $path" >&2; return 1; }

    CUR_FLASH_TOTAL="$flash_total"
    CUR_RAM_TOTAL="$ram_total"
    FIRST_FLASH_ORIGIN="$first_f_origin"
    FIRST_FLASH_LINE="$first_f_line"
    return 0
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
usage() {
    echo "用法: $0 <link.ld> [link.ld2] --chip CH32H417WEU [--ram-avail <值>] [--breakpoints <n>] [--quiet]"
    echo "      $0 --selftest"
}

# 自测（表达式计算器）
selftest() {
    local failed=0 g
    run_calc() {
        local got="$1" expect="$2"
        local v; v="$(calc_length "$1")"
        if [ "$v" = "$expect" ]; then
            echo "✅ calc_length($1) = $v  expect=$expect"
        else
            echo "❌ calc_length($1) = $v  expect=$expect"; failed=$((failed + 1))
        fi
    }
    run_calc '480K' '491520'
    run_calc '0x3FC00' '261120'
    run_calc '64K*2' '131072'
    run_calc '448K - 256' '458496'
    run_calc '1M/2' '524288'
    run_calc '0x1000+0x2000' '12288'
    g="$(calc_length 'ALIGN(4)')"
    if [ -z "$g" ]; then
        echo '✅ calc_length(ALIGN(4)) = (空)  expect=(空)'
    else
        echo "❌ calc_length(ALIGN(4)) = $g"; failed=$((failed + 1))
    fi
    echo
    if [ "$failed" = "0" ]; then echo '自测通过'; exit 0; fi
    echo "自测失败 $failed 项"
    exit 1
}

CHIP=""; RAM_AVAIL=""; BREAKPOINTS=""; QUIET=0
FILES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --chip) CHIP="${2:-}"; shift 2 ;;
        --ram-avail) RAM_AVAIL="${2:-}"; shift 2 ;;
        --breakpoints) BREAKPOINTS="${2:-}"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        --selftest) selftest ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "[FATAL] 未知参数: $1" >&2; exit 2 ;;
        *) FILES+=("$1"); shift ;;
    esac
done

[ "${#FILES[@]}" -gt 0 ] || { echo '[FATAL] 至少提供 1 个 link.ld 路径' >&2; exit 2; }
[ -f "$ISA" ] || { echo "[FATAL] mcu_isa.json 不存在: $ISA" >&2; exit 2; }

# 芯片型号
if [ -z "$CHIP" ]; then
    CHIP="$(grep -oiE 'CH32[A-Z0-9]+' "${FILES[0]}" 2>/dev/null | awk 'length($0) >= 6 { print toupper($0); exit }')"
fi
if [ -z "$CHIP" ]; then
    echo '[FATAL] 无法推断芯片型号，请用 --chip 指定' >&2
    exit 2
fi
if ! find_chip "$CHIP"; then
    echo "[FATAL] 在 mcu_isa.json 中找不到型号 $CHIP" >&2
    exit 2
fi
max_flash="$(calc_length "$CHIP_FLASH_STR")"
max_sram="$(calc_length "$CHIP_SRAM_STR")"
MAXBP="$(find_maxbp "$CHIP")"

add_info "芯片: $CHIP（系列 $SERIES）| 最大 flash=$CHIP_FLASH_STR, sram=$CHIP_SRAM_STR"

total_flash=0; total_ram=0
flash_ok=1; ram_ok=1
for f in "${FILES[@]}"; do
    add_info "文件: $f"
    if ! parse_ld "$f"; then exit 2; fi
    if [ -n "$CUR_FLASH_TOTAL" ]; then
        total_flash=$((total_flash + CUR_FLASH_TOTAL))
    else
        add_err 'FLASH LENGTH 存在无法计算的值（含符号/函数）'; flash_ok=0
    fi
    if [ -n "$CUR_RAM_TOTAL" ]; then
        total_ram=$((total_ram + CUR_RAM_TOTAL))
    else
        add_err 'RAM LENGTH 存在无法计算的值（含符号/函数）'; ram_ok=0
    fi
    if [ -n "$FIRST_FLASH_ORIGIN" ] && [ "$FIRST_FLASH_ORIGIN" != "0" ]; then
        add_warn "[规则3] $f 的 FLASH 起始地址 0x$(printf '%08X' "$FIRST_FLASH_ORIGIN") ≠ 0（第${FIRST_FLASH_LINE}行）——需询问用户 0 地址是否有程序：无程序 → WCH 芯片程序无法运行，提醒修改起始地址；有程序 → 多为 IAP+APP，调试当前程序需开启页擦"
    fi
done
add_info "总 FLASH 合计: $(fmt_size "$total_flash") | 总 RAM 合计: $(fmt_size "$total_ram")"

# 规则1：小于等于上限
if [ "$flash_ok" = "1" ] && [ -n "$max_flash" ]; then
    if [ "$total_flash" -gt "$max_flash" ]; then
        add_err "[规则1] FLASH 合计 $(fmt_size "$total_flash") > 芯片最大 $(fmt_size "$max_flash")（必须小于等于上限）"
    else
        add_ok "[规则1] FLASH 合计 $(fmt_size "$total_flash") <= 芯片最大 $(fmt_size "$max_flash")"
    fi
fi
if [ "$ram_ok" = "1" ] && [ -n "$max_sram" ]; then
    if [ "$total_ram" -gt "$max_sram" ]; then
        add_err "[规则1] RAM 合计 $(fmt_size "$total_ram") > 芯片最大 $(fmt_size "$max_sram")（必须小于等于上限）"
    else
        add_ok "[规则1] RAM 合计 $(fmt_size "$total_ram") <= 芯片最大 $(fmt_size "$max_sram")"
    fi
fi

# 规则2：ROM/RAM 可配置芯片，总 RAM <= 当前硬件配置读到的值
if [ -n "$RAM_AVAIL" ]; then
    ram_avail="$(calc_length "$RAM_AVAIL")"
    if [ -z "$ram_avail" ]; then
        add_err "[规则2] --ram-avail 无法解析: $RAM_AVAIL"
    elif [ "$ram_ok" = "1" ]; then
        if [ "$total_ram" -le "$ram_avail" ]; then
            add_ok "[规则2] RAM 合计 $(fmt_size "$total_ram") <= 硬件配置 RAM $(fmt_size "$ram_avail")"
        else
            add_err "[规则2] RAM 合计 $(fmt_size "$total_ram") > 硬件配置 RAM $(fmt_size "$ram_avail")"
        fi
    fi
else
    add_info '[规则2] 未提供 --ram-avail（skill 应先调用 ide-debug-support-memory-allocation 确认支持，再调用 ide-debug-read-memory-allocation 读取 RAM 值传入比对；不支持则跳过）'
fi

# 断点上限：maxbreakpoint（缺失/为空 = 不限制）
if [ -z "$MAXBP" ]; then
    add_info '[断点] maxbreakpoint 未配置（不限制断点数量）'
else
    add_info "[断点] maxbreakpoint = $MAXBP（调试时设置断点不得超过该值）"
    if [ -n "$BREAKPOINTS" ]; then
        if [ "$BREAKPOINTS" -le "$MAXBP" ]; then
            add_ok "[断点] 计划断点数 $BREAKPOINTS <= 上限 $MAXBP"
        else
            add_err "[断点] 计划断点数 $BREAKPOINTS > 上限 $MAXBP（请减少断点）"
        fi
    fi
fi

echo
echo '========================================================================'
echo '调试前检查报告'
echo '========================================================================'
printf '%s\n' "$ROWS" | awk -F'\t' -v q="$QUIET" 'NF { if (q == "1" && $1 == "ℹ [INFO]") next; print "  " $1 " " $2 }'
echo
if [ "$ERRORS" -gt 0 ]; then
    echo "❌ 结论: FAIL（$ERRORS 个错误, $WARNS 个警告）"
    exit 1
fi
echo "✅ 结论: PASS（$WARNS 个警告）"
exit 0
