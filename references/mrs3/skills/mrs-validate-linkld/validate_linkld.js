#!/usr/bin/env node
/**
 * validate_linkld.js — 校验 WCH RISC-V 工程 link.ld 链接脚本（JS 版，替代 validate_linkld.py）。
 *
 * 核心规则（对照技能目录下 mcu_isa.json）：
 *   1. 解析 link.ld 中 MEMORY 块的 FLASH / RAM 的 ORIGIN 与 LENGTH；
 *   2. 按芯片型号查 mcu_isa.json 获取最大 flash / sram；
 *   3. 校验：FLASH LENGTH <= 最大 flash；RAM LENGTH <= 最大 sram；
 *   4. 双核芯片（CH32H415/H416/H417）分别校验 V3F、V5F 两份脚本，并核对合计不超上限；
 *   5. 布局检查（参考 WCH EVT 模板，WARN 级）：单核 FLASH=0x00000000/RAM=0x20000000；
 *      V3F FLASH=0x00000000/RAM=0x20000000；V5F FLASH=0x40000000/RAM=0x38000000；
 *   6. 语法检查：MEMORY/SECTIONS 存在、花括号配对、LENGTH/ORIGIN 可解析。
 *
 * 用法：
 *   node validate_linkld.js <link.ld> [第二个 link.ld(双核合计用)] \
 *       [--chip CH32H417WEU] [--core v3f|v5f|single|auto] [--quiet]
 *
 * 注意：mcu_isa.json 固定从本脚本所在目录（技能目录）加载，不接受路径参数。
 * 退出码：0 = 无错误；1 = 存在 ERROR。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const SIZE_UNITS = { K: 1024, M: 1024 * 1024, G: 1024 ** 3 };
const CHIP_RE = /CH32[A-Z0-9]+/gi;
const DUAL_CORE_SERIES = new Set(['CH32H415', 'CH32H416', 'CH32H417']);

// WCH EVT 模板内存布局（参考值；如有出入以官方 EVT 为准）
const KNOWN_LAYOUT = {
  single: { flash_org: 0x00000000, ram_org: 0x20000000 },
  v3f: { flash_org: 0x00000000, ram_org: 0x20000000 },
  v5f: { flash_org: 0x40000000, ram_org: 0x38000000 },
};

// ---------- 参数解析（--key value / --flag，其余为位置参数） ----------
function parseArgs(argv) {
  const opts = {};
  const positionals = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) {
        opts[key] = next;
        i++;
      } else {
        opts[key] = true;
      }
    } else {
      positionals.push(a);
    }
  }
  return { opts, positionals };
}

// ---------- 数值工具 ----------
function parseSize(s) {
  /* '64K'/'1M'/'0x10000'/2048 -> bytes；失败返回 null。 */
  if (s === undefined || s === null) return null;
  s = String(s).trim().replace(/;$/, '');
  if (!s) return null;
  if (/^0x/i.test(s)) {
    const v = parseInt(s, 16);
    return Number.isNaN(v) ? null : v;
  }
  const m = /^\s*(\d+)\s*([KMG])?\s*$/i.exec(s);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  const unit = (m[2] || '').toUpperCase();
  return n * (SIZE_UNITS[unit] || 1);
}

function fmtSize(n) {
  if (n === null || n === undefined) return '?';
  if (n >= 1024 * 1024) {
    const v = n / (1024 * 1024);
    return Number.isInteger(v) ? `${v}M` : `${v.toFixed(1)}M`;
  }
  if (n >= 1024) {
    const v = n / 1024;
    return Number.isInteger(v) ? `${v}K` : `${v.toFixed(1)}K`;
  }
  return String(n);
}

function hex8(n) {
  return `0x${n.toString(16).toUpperCase().padStart(8, '0')}`;
}

// ---------- mcu_isa.json（固定加载脚本同目录下的配置文件） ----------
function loadIsa() {
  const jsonPath = path.join(__dirname, 'mcu_isa.json');
  if (!fs.existsSync(jsonPath)) {
    console.error(`[FATAL] mcu_isa.json 不存在: ${jsonPath}`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));
}

function findChip(data, name) {
  const upper = String(name).toUpperCase();
  for (const entry of data) {
    for (const chip of entry.chips || []) {
      if (String(chip.name).toUpperCase() === upper) return { entry, chip };
    }
  }
  return { entry: null, chip: null };
}

function autoDetectCore(p) {
  if (/[Vv]3[Ff]/.test(p)) return 'v3f';
  if (/[Vv]5[Ff]/.test(p)) return 'v5f';
  return null;
}

function autoDetectChip(p, text) {
  for (const src of [p, text]) {
    CHIP_RE.lastIndex = 0;
    let m;
    while ((m = CHIP_RE.exec(src)) !== null) {
      const cand = m[0].toUpperCase();
      if (cand.length >= 6) return cand;
    }
  }
  return null;
}

// ---------- 报告 ----------
class Report {
  constructor() {
    this.lines = [];
    this.errors = 0;
    this.warns = 0;
  }
  ok(msg) { this.lines.push(`  ✅ ${msg}`); }
  warn(msg) { this.warns++; this.lines.push(`  ⚠ [WARN] ${msg}`); }
  err(msg) { this.errors++; this.lines.push(`  ❌ [ERROR] ${msg}`); }
  info(msg) { this.lines.push(`  ℹ [INFO] ${msg}`); }
}

// ---------- ld 语法检测 ----------
function stripComments(text) {
  /* 去掉块注释与行注释（保留换行，保证行号不变）。 */
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

function checkLdSyntax(text, regions, memOpen, memEnd, rep) {
  /* 1) 注释剥离后的 {} () [] 括号配对；
     2) MEMORY 块内每行必须符合区域定义格式；
     3) SECTIONS 中 >区域 / AT>区域 / ORIGIN(区域) / LENGTH(区域) 必须引用已定义区域；
     4) 顶层符号赋值语句必须以分号结尾。 */
  const clean = stripComments(text);
  // 1) 括号配对
  for (const [op, cl, nm] of [['{', '}', '花括号'], ['(', ')', '圆括号'], ['[', ']', '方括号']]) {
    const o = (clean.match(new RegExp(`\\${op}`, 'g')) || []).length;
    const c = (clean.match(new RegExp(`\\${cl}`, 'g')) || []).length;
    if (o !== c) rep.err(`${nm}不配对: ${op} ${o} 个 vs ${cl} ${c} 个`);
  }
  const lines = text.split('\n');
  const lineOffsets = [];
  let off = 0;
  for (const line of lines) {
    lineOffsets.push(off);
    off += line.length + 1;
  }
  // 2) MEMORY 行格式（跳过空行与块首尾的 { } 行）
  lines.forEach((line, idx) => {
    const ln = idx + 1;
    if (!(memOpen <= lineOffsets[idx] && lineOffsets[idx] < memEnd)) return;
    const s = stripComments(line).trim();
    if (!s || /^[{}]\s*$/.test(s)) return;
    if (/^\w+\s*\([^)]*\)\s*:\s*ORIGIN\s*=\s*[^,]+,\s*LENGTH\s*=\s*\S+\s*$/.test(s)) return;
    rep.err(`MEMORY 块中存在无法解析的行（第${ln}行）: ${s}`);
  });
  // 3) 区域引用
  let m;
  const refRe = /(?:AT\s*)?>\s*(\w+)/g;
  while ((m = refRe.exec(clean)) !== null) {
    const name = m[1];
    if (!(name in regions)) {
      const ln = clean.slice(0, m.index).split('\n').length;
      rep.warn(`引用了未定义的 MEMORY 区域: ${name}（第${ln}行，可能来自 INCLUDE 文件）`);
    }
  }
  const fnRe = /\b(ORIGIN|LENGTH)\s*\(\s*(\w+)\s*\)/g;
  while ((m = fnRe.exec(clean)) !== null) {
    const name = m[2];
    if (!(name in regions)) {
      const ln = clean.slice(0, m.index).split('\n').length;
      rep.warn(`${m[1]}(${name}) 引用了未定义的 MEMORY 区域（第${ln}行，可能来自 INCLUDE 文件）`);
    }
  }
  // 4) 赋值语句分号
  lines.forEach((line, idx) => {
    const ln = idx + 1;
    if (memOpen <= lineOffsets[idx] && lineOffsets[idx] < memEnd) return;
    const s = stripComments(line).trim();
    if (!s || s.includes('{') || s.includes('}')) return;
    if (/^[A-Za-z_.]\w*\s*=/.test(s) && !s.endsWith(';')) {
      rep.warn(`符号赋值语句缺少分号（第${ln}行）: ${s}`);
    }
  });
}

function isNumToken(tok) {
  /* 是否为数字字面量：123 / 123K / 1M / 0x1F / 0x1000K 等。 */
  return /^(?:0[xX][0-9a-fA-F]+|\d+)(?:[KMG])?$/.test(tok || '');
}

function bothSidesNumeric(s, i, opLen) {
  /* 运算符两侧是否都是数字字面量（如 64K*2、0x1000+0x2000）。
     若是：禁止计算最终值，直接保留原样，不做空格检查。 */
  let j = i - 1;
  while (j >= 0 && /[0-9A-Za-z_.]/.test(s[j])) j--;
  const lt = s.slice(j + 1, i);
  j = i + opLen;
  while (j < s.length && /[0-9A-Za-z_.]/.test(s[j])) j++;
  const rt = s.slice(i + opLen, j);
  return !!(lt && rt) && isNumToken(lt) && isNumToken(rt);
}

function checkOperatorSpacing(text, rep) {
  /* 变量与运算符之间必须有空格（ERROR，需修复）。
     检查对象：= + - / % << >> & | ^ 等运算符，两侧必须为空白；
     不检查：注释（先整体剥离块注释与行注释，含跨行块注释）与通配符（* 一律不视为运算符）；
     运算符两侧均为数字字面量（如 64K*2、0x1000+0x2000）时不检查、不计算最终值、原样保留；
     /DISCARD/ 等特殊段名行整体跳过；- 用作一元负号（前邻 ( = , [ : 或空白/行首）时跳过。 */
  const clean = stripComments(text);
  const lines = clean.split('\n');
  lines.forEach((line, idx) => {
    const ln = idx + 1;
    const s = line.trim();
    if (!s || /^\s*\/\w+\/\s*:/.test(s)) return;   // /DISCARD/ 等特殊段名行整体跳过
    const bad = [];
    let i = 0;
    const n = s.length;
    while (i < n) {
      const two = s.slice(i, i + 2);
      if (two === '<<' || two === '>>' || two === '&&' || two === '||') {
        if (bothSidesNumeric(s, i, 2)) { i += 2; continue; }   // 两侧数字：原样保留
        const prevWs = i === 0 || /\s/.test(s[i - 1]);
        const nextWs = i + 2 >= n || /\s/.test(s[i + 2]);
        if (!(prevWs && nextWs)) bad.push(two);
        i += 2;
        continue;
      }
      const ch = s[i];
      if (ch === '&' || ch === '|' || ch === '^') {
        if (bothSidesNumeric(s, i, 1)) { i += 1; continue; }
        const prevWs = i === 0 || /\s/.test(s[i - 1]);
        const nextWs = i + 1 >= n || /\s/.test(s[i + 1]);
        if (!(prevWs && nextWs)) bad.push(ch);
        i += 1;
        continue;
      }
      if (ch === '=') {
        if (i + 1 < n && s[i + 1] === '=') { i += 2; continue; }
        if (i > 0 && '=!<>'.includes(s[i - 1])) { i += 1; continue; }
        if (bothSidesNumeric(s, i, 1)) { i += 1; continue; }
        const prevWs = i === 0 || /\s/.test(s[i - 1]);
        const nextWs = i + 1 >= n || /\s/.test(s[i + 1]);
        if (!(prevWs && nextWs)) bad.push('=');
        i += 1;
        continue;
      }
      if (ch === '+' || ch === '/') {
        // /DISCARD/ 等段名形式（/ 后紧跟非空白且行内还有闭合 /）跳过
        if (ch === '/' && i + 1 < n && !/\s/.test(s[i + 1]) && s.slice(i + 1).includes('/')) {
          i += 1;
          continue;
        }
        if (bothSidesNumeric(s, i, 1)) { i += 1; continue; }
        const prevWs = i === 0 || /\s/.test(s[i - 1]);
        const nextWs = i + 1 >= n || /\s/.test(s[i + 1]);
        if (!(prevWs && nextWs)) bad.push(ch);
        i += 1;
        continue;
      }
      if (ch === '-') {
        const unary = i === 0 || /\s/.test(s[i - 1]) || '(=,[:'.includes(s[i - 1]);
        if (!unary) {
          if (bothSidesNumeric(s, i, 1)) { i += 1; continue; }
          const prevWs = /\s/.test(s[i - 1]);
          const nextWs = i + 1 >= n || /\s/.test(s[i + 1]);
          if (!(prevWs && nextWs)) bad.push('-');
        }
        i += 1;
        continue;
      }
      if (ch === '%') {
        if (bothSidesNumeric(s, i, 1)) { i += 1; continue; }
        const prevWs = i === 0 || /\s/.test(s[i - 1]);
        const nextWs = i + 1 >= n || /\s/.test(s[i + 1]);
        if (!(prevWs && nextWs)) bad.push('%');
        i += 1;
        continue;
      }
      i += 1;
    }
    if (bad.length) {
      const uniq = [...new Set(bad)];
      rep.err(`运算符两侧必须加空格（第${ln}行）: ${s}  [运算符: ${uniq.join(' ')}]`);
    }
  });
}

// ---------- 单个脚本校验 ----------
function checkScript(filePath, rep, isa, chip, core) {
  let text;
  try {
    text = fs.readFileSync(filePath, 'utf-8'); // 无效字节自动替换，等价 errors='replace'
  } catch (e) {
    rep.err(`无法读取文件: ${e.message}`);
    return null;
  }

  // ---- 语法基础 ----
  if (!text.includes('MEMORY')) {
    rep.err('缺少 MEMORY 块');
    return null;
  }
  if (!text.includes('SECTIONS')) rep.err('缺少 SECTIONS 块');

  // ---- 解析 MEMORY ----
  const mem = /MEMORY\s*\{/.exec(text);
  if (!mem) {
    rep.err('无法定位 MEMORY 块');
    return null;
  }
  const memOpen = text.indexOf('{', mem.index);
  let depth = 1;
  let i = memOpen + 1;
  while (i < text.length && depth > 0) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') depth--;
    i++;
  }
  const memText = text.slice(memOpen, i);
  const regions = {};
  const regionRe = /(\w+)\s*\(([^)]*)\)\s*:\s*ORIGIN\s*=\s*([^,]+),\s*LENGTH\s*=\s*(\S+)/g;
  let m;
  while ((m = regionRe.exec(memText)) !== null) {
    const name = m[1], attrs = m[2], originS = m[3], lengthS = m[4];
    const lineNo = text.slice(0, memOpen + m.index).split('\n').length;
    regions[name] = {
      attrs,
      origin: parseSize(originS),
      length: parseSize(lengthS),
      origin_s: originS.trim(),
      length_s: lengthS.trim(),
      line: lineNo,
    };
    rep.info(`MEMORY ${name}(${attrs}): ORIGIN=${originS.trim()} LENGTH=${lengthS.trim()} (第${lineNo}行)`);
  }

  // ---- ld 语法检测（括号配对/MEMORY 行格式/区域引用/赋值分号） ----
  checkLdSyntax(text, regions, memOpen, i, rep);
  // ---- 运算符空格检测（变量与运算符之间必须有空格） ----
  checkOperatorSpacing(text, rep);

  for (const need of ['FLASH', 'RAM']) {
    if (!(need in regions)) {
      rep.err(`MEMORY 中缺少 ${need} 区域`);
      return null;
    }
    if (regions[need].origin === null) rep.err(`${need} 的 ORIGIN 无法解析: ${regions[need].origin_s}`);
    if (regions[need].length === null) {
      rep.err(`${need} 的 LENGTH 无法解析: ${regions[need].length_s}`);
      return null;
    }
  }

  const flash = regions.FLASH;
  const ram = regions.RAM;

  // ---- 容量 vs mcu_isa.json ----
  const { entry: series, chip: chipEntry } = findChip(isa, chip);
  let maxFlash = null, maxSram = null;
  if (!chipEntry) {
    rep.err(`在 mcu_isa.json 中找不到型号 ${chip}，无法做容量校验（请用 --chip 指定正确型号）`);
  } else {
    maxFlash = parseSize(chipEntry.flash);
    maxSram = parseSize(chipEntry.sram);
    rep.info(`芯片 ${chip}（系列 ${series.series}）: 最大 flash=${chipEntry.flash}, sram=${chipEntry.sram}`);
    if (flash.length > maxFlash) {
      rep.err(`FLASH LENGTH=${flash.length_s} 超过芯片最大 ${fmtSize(maxFlash)}（第${flash.line}行），建议改为 <= ${fmtSize(maxFlash)}`);
    } else {
      const ratio = flash.length / maxFlash;
      const msg = `FLASH ${fmtSize(flash.length)} <= ${fmtSize(maxFlash)}（使用 ${(ratio * 100).toFixed(1)}%）`;
      if (ratio < 0.9) rep.ok(msg);
      else rep.warn(msg + '，接近上限');
    }
    if (ram.length > maxSram) {
      rep.err(`RAM LENGTH=${ram.length_s} 超过芯片最大 ${fmtSize(maxSram)}（第${ram.line}行），建议改为 <= ${fmtSize(maxSram)}`);
    } else {
      const ratio = ram.length / maxSram;
      const msg = `RAM ${fmtSize(ram.length)} <= ${fmtSize(maxSram)}（使用 ${(ratio * 100).toFixed(1)}%）`;
      if (ratio < 0.9) rep.ok(msg);
      else rep.warn(msg + '，接近上限');
    }
  }

  // ---- 布局检查 ----
  const layout = KNOWN_LAYOUT[core] || KNOWN_LAYOUT.single;
  if ((core === 'v3f' || core === 'v5f') && series && !DUAL_CORE_SERIES.has(series.series)) {
    rep.warn(`检测到内核 ${core.toUpperCase()}，但芯片 ${chip} 不是双核系列，请确认 --core 是否正确`);
  }
  for (const [rname, key] of [['FLASH', 'flash_org'], ['RAM', 'ram_org']]) {
    const expect = layout[key];
    const actual = regions[rname].origin;
    if (actual === null) continue;
    const template = core === 'v3f' || core === 'v5f' ? '双核' : '单核';
    if (actual !== expect) {
      rep.warn(`${rname} ORIGIN=${hex8(actual)} 与 ${core === 'single' ? '单核' : core.toUpperCase()}模板 ${hex8(expect)} 不一致（第${regions[rname].line}行；如属自定义布局可忽略）`);
    } else {
      rep.ok(`${rname} ORIGIN=${hex8(actual)} 符合 ${template}模板`);
    }
  }

  // ---- INCLUDE ----
  const base = path.dirname(path.resolve(filePath));
  const incRe = /INCLUDE\s+(\S+)/g;
  let im;
  while ((im = incRe.exec(text)) !== null) {
    const inc = im[1].replace(/^"|"$/g, '');
    if (!fs.existsSync(path.join(base, inc))) {
      rep.warn(`INCLUDE 文件不存在（可能由工具链提供）: ${inc}`);
    }
  }

  return regions;
}

// ---------- 主入口 ----------
function main() {
  const { opts, positionals } = parseArgs(process.argv.slice(2));

  if (positionals.length === 0) {
    console.error('[FATAL] 缺少 link.ld 路径参数（可传两份做双核合计校验）');
    return 1;
  }

  // mcu_isa.json：固定加载本脚本所在目录（技能目录）下的配置文件，不接受路径参数
  const isa = loadIsa();

  const reports = [];
  const regionsList = [];
  let totalFlash = 0, totalRam = 0;
  const chipsSeen = new Set();

  for (const filePath of positionals) {
    if (!fs.existsSync(filePath)) {
      console.error(`[FATAL] 文件不存在: ${filePath}`);
      return 1;
    }
    const text = fs.readFileSync(filePath, 'utf-8');
    const chip = opts.chip || autoDetectChip(filePath, text);
    if (!chip) {
      console.error('[FATAL] 无法推断芯片型号，请用 --chip 指定');
      return 1;
    }
    let core = opts.core || 'auto';
    if (core === 'auto') {
      core = autoDetectCore(filePath) || (filePath.toUpperCase().includes('V3F') ? 'v3f' : null) || 'single';
    }
    const rep = new Report();
    rep.info(`文件: ${filePath}`);
    rep.info(`芯片: ${chip} | 内核: ${core ? core.toUpperCase() : '?'}`);
    const regions = checkScript(filePath, rep, isa, chip, core);
    reports.push([filePath, rep]);
    chipsSeen.add(chip);
    if (regions) {
      regionsList.push([filePath, core, regions]);
      if (regions.FLASH && regions.FLASH.length !== null) totalFlash += regions.FLASH.length;
      if (regions.RAM && regions.RAM.length !== null) totalRam += regions.RAM.length;
    }
  }

  // 双核合计校验
  if (regionsList.length >= 2 && chipsSeen.size === 1) {
    const chip = opts.chip || [...chipsSeen][0];
    const { chip: chipEntry } = findChip(isa, chip);
    if (chipEntry) {
      const maxFlash = parseSize(chipEntry.flash);
      const maxSram = parseSize(chipEntry.sram);
      const rep = new Report();
      rep.info(`双核合计校验: ${regionsList.length} 份脚本, flash 合计 ${fmtSize(totalFlash)}, ram 合计 ${fmtSize(totalRam)}`);
      if (totalFlash > maxFlash) {
        rep.err(`V3F+V5F FLASH 合计 ${fmtSize(totalFlash)} 超过芯片最大 ${fmtSize(maxFlash)}`);
      } else {
        rep.ok(`V3F+V5F FLASH 合计 ${fmtSize(totalFlash)} <= ${fmtSize(maxFlash)}`);
      }
      if (totalRam > maxSram) {
        rep.err(`V3F+V5F RAM 合计 ${fmtSize(totalRam)} 超过芯片最大 ${fmtSize(maxSram)}`);
      } else {
        rep.ok(`V3F+V5F RAM 合计 ${fmtSize(totalRam)} <= ${fmtSize(maxSram)}`);
      }
      reports.push(['双核合计', rep]);
    }
  }

  console.log();
  console.log('='.repeat(72));
  console.log('link.ld 校验报告');
  console.log('='.repeat(72));
  let totalErr = 0, totalWarn = 0;
  for (const [label, rep] of reports) {
    totalErr += rep.errors;
    totalWarn += rep.warns;
    console.log(`\n--- ${label} ---`);
    if (!opts.quiet) {
      console.log(rep.lines.join('\n'));
    } else {
      console.log(`  错误 ${rep.errors} 个 / 警告 ${rep.warns} 个`);
    }
  }
  console.log();
  if (totalErr) {
    console.log(`❌ 结论: FAIL（${totalErr} 个错误, ${totalWarn} 个警告）`);
    return 1;
  }
  console.log(`✅ 结论: PASS（${totalWarn} 个警告）`);
  return 0;
}

process.exitCode = main();
