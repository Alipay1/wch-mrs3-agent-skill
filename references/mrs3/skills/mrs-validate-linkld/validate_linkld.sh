#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# validate_linkld.sh — 校验 WCH RISC-V 工程 link.ld 链接脚本（原生 bash 实现，不依赖 Python）。
#
# 逻辑与 validate_linkld.py 一致：
#   1. 解析 MEMORY 块中 FLASH/RAM 区域（支持 FLASH/FLASH2、RAM/RAM2 等多区域写法）；
#   2. LENGTH/ORIGIN 支持表达式（448K - 256、0x3FC00、64K*2 等），内置计算器统一转十进制；
#   3. FLASH/RAM 多区域 LENGTH 全部相加后与 mcu_isa.json 芯片上限比较，合计 > 上限 → ERROR；
#   4. 双核（V3F/V5F 两份脚本）合计校验；
#   5. __global_pointer$ 缺失时报告（INFO）；
#   6. 语法：括号配对、MEMORY 行格式、区域引用、赋值分号、运算符两侧空格（注释/通配符不检查）。
#
# 用法：./validate_linkld.sh <link.ld> [link.ld2] [--chip CH32H417WEU] [--core v3f|v5f|single|auto] [--quiet]
# 退出码：0 = 无错误；1 = 存在 ERROR。
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISA="$SKILL_DIR/mcu_isa.json"

# ---------------------------------------------------------------------------
# 内嵌 awk 程序（POSIX awk）
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

# 2) 定位 MEMORY 块，输出 "起始行 结束行"（1-based，含 { } 行）
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

# 3) 运算符空格检测：逐行输出 "行号<TAB>运算符列表<TAB>原文"
read -r -d '' SPACING_AWK <<'AWK'
function istok(c) { return c ~ /^[A-Za-z0-9_.]$/ }
function isnum(t) { return (t != "" && t ~ /^(0[xX][0-9a-fA-F]+|[0-9]+)([KMGkmg])?$/) }
function addop(bad, op) { return (index(" " bad " ", " " op " ") == 0) ? bad " " op : bad }
function isws(s, k, n) {
    if (k < 1 || k > n) return 1
    return substr(s, k, 1) ~ /^[[:space:]]$/
}
function bothnum(s, i, len,    j, lt, rt) {
    j = i - 1
    while (j >= 1 && istok(substr(s, j, 1))) j--
    lt = substr(s, j + 1, (i - 1) - j)
    j = i + len
    while (j <= length(s) && istok(substr(s, j, 1))) j++
    rt = substr(s, i + len, j - (i + len))
    return (lt != "" && rt != "" && isnum(lt) && isnum(rt))
}
{
    s = $0
    sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
    if (s == "") next
    if (s ~ /^\/[A-Za-z0-9_]+\/[[:space:]]*:/) next
    n = length(s)
    bad = ""
    i = 1
    while (i <= n) {
        two = substr(s, i, 2)
        if (two == "<<" || two == ">>" || two == "&&" || two == "||") {
            if (bothnum(s, i, 2)) { i += 2; continue }
            if (!(isws(s, i - 1, n) && isws(s, i + 2, n))) bad = addop(bad, two)
            i += 2
            continue
        }
        c = substr(s, i, 1)
        if (c == "&" || c == "|" || c == "^") {
            if (bothnum(s, i, 1)) { i++; continue }
            if (!(isws(s, i - 1, n) && isws(s, i + 1, n))) bad = addop(bad, c)
            i++
            continue
        }
        if (c == "=") {
            if (substr(s, i + 1, 1) == "=") { i += 2; continue }
            if (i > 1 && substr(s, i - 1, 1) ~ /^[=!<>]$/) { i++; continue }
            if (bothnum(s, i, 1)) { i++; continue }
            if (!(isws(s, i - 1, n) && isws(s, i + 1, n))) bad = addop(bad, c)
            i++
            continue
        }
        if (c == "+" || c == "/") {
            if (c == "/" && i + 1 <= n && substr(s, i + 1, 1) !~ /^[[:space:]]$/ && index(substr(s, i + 1), "/") > 0) { i++; continue }
            if (bothnum(s, i, 1)) { i++; continue }
            if (!(isws(s, i - 1, n) && isws(s, i + 1, n))) bad = addop(bad, c)
            i++
            continue
        }
        if (c == "-") {
            unary = (i == 1 || substr(s, i - 1, 1) ~ /^[[:space:](=,\[:]$/)
            if (!unary) {
                if (bothnum(s, i, 1)) { i++; continue }
                if (!(isws(s, i - 1, n) && isws(s, i + 1, n))) bad = addop(bad, c)
            }
            i++
            continue
        }
        if (c == "%") {
            if (bothnum(s, i, 1)) { i++; continue }
            if (!(isws(s, i - 1, n) && isws(s, i + 1, n))) bad = addop(bad, c)
            i++
            continue
        }
        i++
    }
    if (bad != "") printf "%d\t%s\t%s\n", NR, bad, s
}
AWK

# 4) 从 mcu_isa.json 提取 "series|name|flash|sram" 每芯片一行
read -r -d '' ISA_AWK <<'AWK'
/"series"/ { s = $0; sub(/^.*"series"[[:space:]]*:[[:space:]]*"/, "", s); sub(/".*$/, "", s); series = s }
/"name"/   { n = $0; sub(/^.*"name"[[:space:]]*:[[:space:]]*"/, "", n); sub(/".*$/, "", n); name = n }
/"flash"/  { f = $0; sub(/^.*"flash"[[:space:]]*:[[:space:]]*"/, "", f); sub(/".*$/, "", f); flash = f }
/"sram"/   { r = $0; sub(/^.*"sram"[[:space:]]*:[[:space:]]*"/, "", r); sub(/".*$/, "", r); if (name != "") print series "|" name "|" flash "|" r }
AWK

# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------
ERRORS=0
WARNS=0
QUIET=0

ok()   { [ "$QUIET" -eq 1 ] && return; echo "  ✅ $*"; }
warn() { WARNS=$((WARNS + 1)); [ "$QUIET" -eq 1 ] && return; echo "  ⚠ [WARN] $*"; }
err()  { ERRORS=$((ERRORS + 1)); [ "$QUIET" -eq 1 ] && return; echo "  ❌ [ERROR] $*"; }
info() { [ "$QUIET" -eq 1 ] && return; echo "  ℹ [INFO] $*"; }

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# calc_length "表达式" → 输出十进制字节数；失败输出空并返回 1
calc_length() {
    local s rest out v
    s="$(trim "${1%;}")"
    [ -z "$s" ] && return 1

    # 掩掉数字+单位后仍含字母 → 含符号/函数，无法计算
    rest="$(printf '%s' "$s" | sed -E 's/0[xX][0-9a-fA-F]+[KMGkmg]?/N/g; s/[0-9]+[KMGkmg]?/N/g')"
    case "$rest" in
        *[A-Za-z]*) return 1 ;;
    esac

    # 单位后缀 → 乘法
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

# find_chip "型号" → 设置 SERIES / CHIP_FLASH_STR / CHIP_SRAM_STR；找不到返回 1
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

auto_chip() {  # $1 path $2 text
    printf '%s\n%s\n' "$1" "$2" | grep -oiE 'CH32[A-Z0-9]+' | awk 'length($0) >= 6 { print toupper($0); exit }'
}

auto_core() {  # $1 path
    case "$1" in
        *[Vv]3[Ff]*) echo v3f ;;
        *[Vv]5[Ff]*) echo v5f ;;
        *) echo single ;;
    esac
}

# ---------------------------------------------------------------------------
# 单文件校验：设置 CUR_FLASH_TOTAL / CUR_RAM_TOTAL（无法解析时为空）
# ---------------------------------------------------------------------------
REGION_RE='^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([^)]*\)[[:space:]]*:[[:space:]]*ORIGIN[[:space:]]*=[[:space:]]*[^,]+,[[:space:]]*LENGTH[[:space:]]*=[[:space:]]*.+$'

check_file() {
    local path="$1" chip="$2" core="$3"
    local text clean mem_info mem_start mem_end total_lines
    local i line name attrs origin_s length_s origin length kind
    local n_flash=0 n_ram=0 flash_total="" ram_total=""
    local flash_ok=1 ram_ok=1
    local region_names=""
    local flash_parts="" ram_parts=""

    [ -f "$path" ] || { echo "[FATAL] 文件不存在: $path"; exit 2; }
    text="$(tr -d '\r' < "$path")"   # 统一换行：去除 CRLF/CR 的 \r，避免行粘连、解析/行号出错
    clean="$(printf '%s\n' "$text" | awk "$STRIP_COMMENTS_AWK")"

    info "文件: $path"
    info "芯片: $chip | 内核: $(echo "$core" | tr 'a-z' 'A-Z')"

    # ---- 基本块存在性 ----
    printf '%s' "$clean" | grep -q 'MEMORY' || { err '缺少 MEMORY 块'; return 1; }
    printf '%s' "$clean" | grep -q 'SECTIONS' || err '缺少 SECTIONS 块'

    mem_info="$(printf '%s\n' "$clean" | awk "$MEMORY_AWK")"
    [ -n "$mem_info" ] || { err '无法定位 MEMORY 块'; return 1; }
    mem_start="${mem_info%% *}"
    mem_end="${mem_info##* }"

    # ---- 存入行数组（下标 1..N） ----
    CLEAN_LINES=()
    i=0
    while IFS= read -r ln; do
        i=$((i + 1))
        CLEAN_LINES[$i]="$ln"
    done <<< "$clean"
    total_lines=$i

    # ---- 解析 MEMORY 区域（多行/多区域全部记录） ----
    i="$mem_start"
    while [ "$i" -le "$mem_end" ]; do
        line="$(trim "${CLEAN_LINES[$i]}")"
        if [ -n "$line" ] && [ "$line" != '{' ] && [ "$line" != '}' ]; then
            if [[ "$line" =~ $REGION_RE ]]; then
                name="${BASH_REMATCH[1]}"
                attrs="${BASH_REMATCH[2]}"
                origin_s="$(trim "${BASH_REMATCH[3]}")"
                length_s="$(trim "${BASH_REMATCH[4]}")"
                origin="$(calc_length "$origin_s")"
                length="$(calc_length "$length_s")"
                region_names="$region_names $name"

                if [ -n "$origin" ] && [ -n "$length" ]; then
                    info "MEMORY ${name}(${attrs}): ORIGIN = ${origin_s} (= ${origin}), LENGTH = ${length_s} (= ${length}) (第${i}行)"
                else
                    info "MEMORY ${name}(${attrs}): ORIGIN = ${origin_s}, LENGTH = ${length_s} (第${i}行)"
                fi

                kind=""
                case "$(echo "$name" | tr 'a-z' 'A-Z')" in
                    FLASH*) kind="flash" ;;
                    RAM*) kind="ram" ;;
                esac

                if [ "$kind" = "flash" ]; then
                    n_flash=$((n_flash + 1))
                    flash_parts="$flash_parts|$length_s"
                    if [ -z "$length" ]; then
                        flash_ok=0
                    else
                        [ -n "$flash_total" ] || flash_total=0
                        flash_total=$((flash_total + length))
                    fi
                elif [ "$kind" = "ram" ]; then
                    n_ram=$((n_ram + 1))
                    ram_parts="$ram_parts|$length_s"
                    if [ -z "$length" ]; then
                        ram_ok=0
                    else
                        [ -n "$ram_total" ] || ram_total=0
                        ram_total=$((ram_total + length))
                    fi
                fi
            else
                err "MEMORY 块中存在无法解析的行（第${i}行）: $line"
            fi
        fi
        i=$((i + 1))
    done

    [ "$n_flash" -gt 0 ] || { err 'MEMORY 中缺少 FLASH 区域'; return 1; }
    [ "$n_ram" -gt 0 ] || { err 'MEMORY 中缺少 RAM 区域'; return 1; }

    # ---- 语法：括号配对 ----
    local o c
    o=$(printf '%s' "$clean" | tr -cd '{' | wc -c); c=$(printf '%s' "$clean" | tr -cd '}' | wc -c)
    [ "$o" -eq "$c" ] || err "花括号不配对: { $o 个 vs } $c 个"
    o=$(printf '%s' "$clean" | tr -cd '(' | wc -c); c=$(printf '%s' "$clean" | tr -cd ')' | wc -c)
    [ "$o" -eq "$c" ] || err "圆括号不配对: ( $o 个 vs ) $c 个"
    o=$(printf '%s' "$clean" | tr -cd '[' | wc -c); c=$(printf '%s' "$clean" | tr -cd ']' | wc -c)
    [ "$o" -eq "$c" ] || err "方括号不配对: [ $o 个 vs ] $c 个"

    # ---- 语法：区域引用 ----
    local ref
    for ref in $(printf '%s' "$clean" | grep -oE '>[[:space:]]*[A-Za-z_][A-Za-z0-9_]*' | sed -E 's/^>[[:space:]]*//'); do
        case " $region_names " in
            *" $ref "*) : ;;
            *) warn "引用了未定义的 MEMORY 区域: $ref（可能来自 INCLUDE 文件）" ;;
        esac
    done
    for ref in $(printf '%s' "$clean" | grep -oE '(ORIGIN|LENGTH)[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*' | sed -E 's/^(ORIGIN|LENGTH)[[:space:]]*\([[:space:]]*//'); do
        case " $region_names " in
            *" $ref "*) : ;;
            *) warn "ORIGIN/LENGTH($ref) 引用了未定义的 MEMORY 区域（可能来自 INCLUDE 文件）" ;;
        esac
    done

    # ---- 语法：赋值分号 ----
    i=1
    while [ "$i" -le "$total_lines" ]; do
        line="$(trim "${CLEAN_LINES[$i]}")"
        if [ "$i" -ge "$mem_start" ] && [ "$i" -le "$mem_end" ]; then
            : # MEMORY 块内不要求分号
        elif [ -n "$line" ]; then
            case "$line" in
                *'{'*|*'}'*) : ;;
                *)
                    if printf '%s' "$line" | grep -q '='; then
                        case "$line" in
                            *[;,+*/%&|^<>=(-]) : ;;
                            *) warn "赋值语句缺少分号（第${i}行）: $line" ;;
                        esac
                    fi
                    ;;
            esac
        fi
        i=$((i + 1))
    done

    # ---- 语法：运算符空格 ----
    while IFS=$'\t' read -r ln ops s; do
        ops="$(trim "$ops")"
        err "运算符两侧必须加空格（第${ln}行）: $s  [运算符: $ops]"
    done < <(printf '%s\n' "$clean" | awk "$SPACING_AWK")

    # ---- __global_pointer$ ----
    if printf '%s' "$clean" | grep -q '__global_pointer\$'; then
        ok '检测到 __global_pointer$ 符号'
    else
        info '未检测到 __global_pointer$ 符号（RISC-V GP 优化通常需要定义 __global_pointer$ = . + 0x800;）'
    fi

    # ---- LENGTH 可解析性 ----
    [ "$flash_ok" -eq 1 ] || err "FLASH 区域存在 LENGTH 无法计算（含符号/函数等）"
    [ "$ram_ok" -eq 1 ] || err "RAM 区域存在 LENGTH 无法计算（含符号/函数等）"

    # ---- 容量 vs mcu_isa.json ----
    if ! find_chip "$chip"; then
        err "在 mcu_isa.json 中找不到型号 $chip，无法做容量校验（请用 --chip 指定正确型号）"
    else
        local max_flash max_sram pct
        max_flash="$(calc_length "$CHIP_FLASH_STR")"
        max_sram="$(calc_length "$CHIP_SRAM_STR")"
        info "芯片 $chip（系列 $SERIES）: 最大 flash=$CHIP_FLASH_STR, sram=$CHIP_SRAM_STR"
        if [ -n "$flash_total" ] && [ -n "$max_flash" ]; then
            if [ "$n_flash" -gt 1 ]; then
                info "FLASH 区域共 $n_flash 个，LENGTH 合计: $(echo "$flash_parts" | sed 's/^|//; s/|/ + /g') = $(fmt_size "$flash_total")"
            fi
            if [ "$flash_total" -gt "$max_flash" ]; then
                err "FLASH LENGTH 合计 $(fmt_size "$flash_total") 超过芯片最大 $(fmt_size "$max_flash")（建议改为合计 <= $(fmt_size "$max_flash")）"
            else
                pct="$(awk -v a="$flash_total" -v b="$max_flash" 'BEGIN { printf "%.1f", a / b * 100 }')"
                if awk -v a="$flash_total" -v b="$max_flash" 'BEGIN { exit !(a >= b * 0.9) }'; then
                    warn "FLASH 合计 $(fmt_size "$flash_total") <= $(fmt_size "$max_flash")（使用 $pct%，接近上限）"
                else
                    ok "FLASH 合计 $(fmt_size "$flash_total") <= $(fmt_size "$max_flash")（使用 $pct%）"
                fi
            fi
        fi
        if [ -n "$ram_total" ] && [ -n "$max_sram" ]; then
            if [ "$n_ram" -gt 1 ]; then
                info "RAM 区域共 $n_ram 个，LENGTH 合计: $(echo "$ram_parts" | sed 's/^|//; s/|/ + /g') = $(fmt_size "$ram_total")"
            fi
            if [ "$ram_total" -gt "$max_sram" ]; then
                err "RAM LENGTH 合计 $(fmt_size "$ram_total") 超过芯片最大 $(fmt_size "$max_sram")（建议改为合计 <= $(fmt_size "$max_sram")）"
            else
                pct="$(awk -v a="$ram_total" -v b="$max_sram" 'BEGIN { printf "%.1f", a / b * 100 }')"
                if awk -v a="$ram_total" -v b="$max_sram" 'BEGIN { exit !(a >= b * 0.9) }'; then
                    warn "RAM 合计 $(fmt_size "$ram_total") <= $(fmt_size "$max_sram")（使用 $pct%，接近上限）"
                else
                    ok "RAM 合计 $(fmt_size "$ram_total") <= $(fmt_size "$max_sram")（使用 $pct%）"
                fi
            fi
        fi

        # ---- 内核与芯片系列核对（不检查 ORIGIN 布局） ----
        if [ "$core" = "v3f" ] || [ "$core" = "v5f" ]; then
            case "$SERIES" in
                CH32H415|CH32H416|CH32H417) : ;;
                *) warn "检测到内核 $(echo "$core" | tr 'a-z' 'A-Z')，但芯片 $chip 不是双核系列，请确认 --core 是否正确" ;;
            esac
        fi
    fi

    # ---- INCLUDE ----
    local base inc
    base="$(cd "$(dirname "$path")" 2>/dev/null && pwd)"
    for inc in $(printf '%s' "$text" | grep -oE 'INCLUDE[[:space:]]+[^[:space:]]+' | awk '{ print $2 }' | sed 's/^"//; s/"$//'); do
        [ -f "$base/$inc" ] || warn "INCLUDE 文件不存在（可能由工具链提供）: $inc"
    done

    CUR_FLASH_TOTAL="$flash_total"
    CUR_RAM_TOTAL="$ram_total"
    return 0
}

usage() {
    echo "用法: $0 <link.ld> [link.ld2] [--chip CH32H417WEU] [--core v3f|v5f|single|auto] [--quiet]"
}

main() {
    local files=()
    local chip="" core="auto"
    while [ $# -gt 0 ]; do
        case "$1" in
            --chip) chip="$2"; shift 2 ;;
            --core) core="$2"; shift 2 ;;
            --quiet) QUIET=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) files+=("$1"); shift ;;
        esac
    done
    [ "${#files[@]}" -gt 0 ] || { usage; exit 2; }
    [ -f "$ISA" ] || { echo "[FATAL] mcu_isa.json 不存在: $ISA"; exit 2; }

    local path chip2 core2 total_flash="" total_ram="" chips_seen=""
    local err_before warn_before
    echo
    echo '========================================================================'
    echo 'link.ld 校验报告'
    echo '========================================================================'
    for path in "${files[@]}"; do
        [ -f "$path" ] || { echo "[FATAL] 文件不存在: $path"; exit 2; }
        chip2="$chip"
        [ -n "$chip2" ] || chip2="$(auto_chip "$path" "$(tr -d '\r' < "$path")")"
        [ -n "$chip2" ] || { echo '[FATAL] 无法推断芯片型号，请用 --chip 指定'; exit 2; }
        core2="$core"
        [ "$core2" = "auto" ] && core2="$(auto_core "$path")"
        echo
        echo "--- $path ---"
        err_before=$ERRORS; warn_before=$WARNS
        CUR_FLASH_TOTAL=""; CUR_RAM_TOTAL=""
        check_file "$path" "$chip2" "$core2"
        if [ "$QUIET" -eq 1 ]; then
            echo "  错误 $((ERRORS - err_before)) 个 / 警告 $((WARNS - warn_before)) 个"
        fi
        if [ -n "$CUR_FLASH_TOTAL" ]; then
            [ -n "$total_flash" ] || total_flash=0
            total_flash=$((total_flash + CUR_FLASH_TOTAL))
        fi
        if [ -n "$CUR_RAM_TOTAL" ]; then
            [ -n "$total_ram" ] || total_ram=0
            total_ram=$((total_ram + CUR_RAM_TOTAL))
        fi
        chips_seen="$chips_seen $chip2"
    done

    # ---- 双核合计 ----
    local n_uniq c mf ms
    n_uniq="$(printf '%s' "$chips_seen" | tr ' ' '\n' | awk 'NF' | sort -u | wc -l)"
    if [ "${#files[@]}" -ge 2 ] && [ "$n_uniq" -eq 1 ]; then
        c="$(printf '%s' "$chips_seen" | awk '{ print $NF }')"
        if find_chip "$c"; then
            mf="$(calc_length "$CHIP_FLASH_STR")"
            ms="$(calc_length "$CHIP_SRAM_STR")"
            echo
            echo '--- 双核合计 ---'
            info "双核合计校验: ${#files[@]} 份脚本, flash 合计 $(fmt_size "$total_flash"), ram 合计 $(fmt_size "$total_ram")"
            if [ -n "$total_flash" ]; then
                if [ "$total_flash" -gt "$mf" ]; then
                    err "V3F+V5F FLASH 合计 $(fmt_size "$total_flash") 超过芯片最大 $(fmt_size "$mf")"
                else
                    ok "V3F+V5F FLASH 合计 $(fmt_size "$total_flash") <= $(fmt_size "$mf")"
                fi
            fi
            if [ -n "$total_ram" ]; then
                if [ "$total_ram" -gt "$ms" ]; then
                    err "V3F+V5F RAM 合计 $(fmt_size "$total_ram") 超过芯片最大 $(fmt_size "$ms")"
                else
                    ok "V3F+V5F RAM 合计 $(fmt_size "$total_ram") <= $(fmt_size "$ms")"
                fi
            fi
        fi
    fi

    echo
    if [ "$ERRORS" -gt 0 ]; then
        echo "❌ 结论: FAIL（$ERRORS 个错误, $WARNS 个警告）"
        return 1
    fi
    echo "✅ 结论: PASS（$WARNS 个警告）"
    return 0
}

main "$@"
exit $?
