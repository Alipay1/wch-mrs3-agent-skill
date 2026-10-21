#!/usr/bin/env node
/**
 * check_march.js — 校验工程编译配置与 mcu_isa.json 是否匹配（JS 版，替代 check_march.py）。
 *
 * 校验项（均可独立使用，提供哪项就校验哪项）：
 *   1. march（架构）:
 *      - 必须为 rv32 开头；
 *      - 按 "_" 分割：首个分段去掉 "rv32" 后按字符逐个拆分，后续分段原样保留；
 *      - 拆分出的每一项都必须出现在该内核的 isa_ext 中，全部命中才算 PASS。
 *   2. toolchain（工具链）: component_toolchain 的值必须在该芯片所属系列的 "toolchain" 数组中。
 *   3. abi（整数 ABI）: riscvTargetProcessor.integer_ABI 的值必须在该芯片内核的 "mabi" 数组中。
 *   4. startfile（启动文件，只提示不修改）: --startfile-dir 目录下的 .S 文件必须与 mcu_isa.json
 *      中该型号的 "startfile" 数组一致，不一致时输出 ⚠ 提示。
 *
 * 用法：
 *   node check_march.js --chip CH32H417WEU --core v5f \
 *       --march rv32imafc_zba_zbb_zbc_zbs_xw --toolchain GCC15 --abi ilp32f
 *   node check_march.js --chip CH32V203CCT --startfile-dir <工程>/Common/Startup
 *   node check_march.js --march rv32imac_xw --isa-ext i,m,a,c,xw     // 手动指定扩展
 *   node check_march.js --selftest                                   // 内置自测
 *
 * 退出码：0 = 全部 PASS；1 = 存在 FAIL 或参数错误。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIVIDER = '='.repeat(72);

// ---------- 参数解析（--key value / --flag，无第三方依赖） ----------
function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      i++;
    }
  }
  return args;
}

// ---------- march 拆分（规则 1/2） ----------
function splitMarch(march) {
  const m = (march || '').trim().toLowerCase();
  if (!m) return { err: 'march 为空', parts: null };
  if (!m.startsWith('rv32')) return { err: `march 必须以 rv32 开头（实际: ${march}）`, parts: null };
  const rest = m.slice(4);
  if (!rest) return { err: 'march 在 rv32 之后为空', parts: null };
  const segs = rest.split('_');
  // 首段：逐字符拆分；后续段：原样保留
  const parts = [...segs[0], ...segs.slice(1)].filter((p) => p !== '');
  return { err: null, parts };
}

function marchCheck(march, isaExt) {
  const { err, parts } = splitMarch(march);
  if (err) return { ok: false, err, parts: null, missing: null };
  const missing = parts.filter((p) => !isaExt.includes(p));
  return { ok: missing.length === 0, err: null, parts, missing };
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

function pickCore(cores, sel) {
  if (!sel) return null;
  return cores.find((c) => String(c.core).toLowerCase().includes(sel.toLowerCase())) || null;
}

// ---------- 校验器 ----------
class Checker {
  constructor(chipName, coreSel) {
    this.chipName = chipName;
    this.coreSel = coreSel || null;
    this.entry = null;
    this.chip = null;
    this.rows = []; // { name, verdict: 'ok'|'fail'|'info', text }
  }

  resolve(isa) {
    const { entry, chip } = findChip(isa, this.chipName);
    if (!chip) {
      console.error(`[FATAL] 在 mcu_isa.json 中找不到型号 ${this.chipName}`);
      process.exit(1);
    }
    this.entry = entry;
    this.chip = chip;
    const cores = entry.cores || [];
    if (this.coreSel && !pickCore(cores, this.coreSel)) {
      console.error(`[FATAL] 内核 ${this.coreSel} 不在芯片 ${this.chipName} 的 cores 中`);
      process.exit(1);
    }
  }

  coreLabel(core) {
    return `${this.entry.series} ${core.core}`;
  }

  // ---- march ----
  checkMarch(march) {
    const cores = this.entry.cores || [];
    const core = pickCore(cores, this.coreSel);
    if (core) {
      const { ok, err, parts, missing } = marchCheck(march, core.isa_ext || []);
      if (err) {
        this.rows.push({ name: 'march', verdict: 'fail', text: err });
        return ok;
      }
      this.rows.push({
        name: 'march',
        verdict: ok ? 'ok' : 'fail',
        text:
          `march=${march} → 拆分: ${parts.join(', ')} | ` +
          `isa_ext[${this.coreLabel(core)}]: ${(core.isa_ext || []).join(', ')}` +
          (missing.length ? ` | 缺失: ${missing.join(', ')}` : ' | 全部命中'),
      });
      return ok;
    }
    this.rows.push({ name: 'march', verdict: 'info', text: `未指定内核，对芯片全部 ${cores.length} 个内核逐一比对:` });
    let anyPass = false;
    for (const c of cores) {
      const { ok, missing } = marchCheck(march, c.isa_ext || []);
      anyPass = anyPass || ok;
      this.rows.push({
        name: 'march',
        verdict: ok ? 'ok' : 'fail',
        text:
          `vs ${this.coreLabel(c)} isa_ext=[${(c.isa_ext || []).join(', ')}]` +
          (ok ? '' : ` → 缺失: ${(missing || []).join(', ')}`),
      });
    }
    this.rows.push({
      name: 'march',
      verdict: anyPass ? 'ok' : 'fail',
      text: `结果: ${anyPass ? 'PASS（至少一个内核匹配）' : 'FAIL（所有内核均不匹配）'}`,
    });
    return anyPass;
  }

  // ---- toolchain（系列级） ----
  checkToolchain(value) {
    const allowed = this.entry.toolchain || [];
    const ok = allowed.includes(value);
    this.rows.push({
      name: 'toolchain',
      verdict: ok ? 'ok' : 'fail',
      text:
        `component_toolchain=${value} | 允许值[${this.entry.series}]: ${allowed.join(', ')}` +
        (ok ? '' : ` | ❌ ${value} 不在允许列表中`),
    });
    return ok;
  }

  // ---- abi（内核级） ----
  checkAbi(value) {
    const cores = this.entry.cores || [];
    const core = pickCore(cores, this.coreSel);
    if (core) {
      const allowed = core.mabi || [];
      const ok = allowed.includes(value);
      this.rows.push({
        name: 'abi',
        verdict: ok ? 'ok' : 'fail',
        text:
          `riscvTargetProcessor.integer_ABI=${value} | 允许值[${this.coreLabel(core)}]: ${allowed.join(', ')}` +
          (ok ? '' : ` | ❌ ${value} 不在允许列表中`),
      });
      return ok;
    }
    this.rows.push({ name: 'abi', verdict: 'info', text: `未指定内核，对芯片全部 ${cores.length} 个内核逐一比对:` });
    let anyPass = false;
    for (const c of cores) {
      const allowed = c.mabi || [];
      const ok = allowed.includes(value);
      anyPass = anyPass || ok;
      this.rows.push({ name: 'abi', verdict: ok ? 'ok' : 'fail', text: `vs ${this.coreLabel(c)} mabi=[${allowed.join(', ')}]` });
    }
    this.rows.push({
      name: 'abi',
      verdict: anyPass ? 'ok' : 'fail',
      text: `结果: ${anyPass ? 'PASS（至少一个内核匹配）' : 'FAIL（所有内核均不匹配）'}`,
    });
    return anyPass;
  }

  // ---- startfile（只提示，不修改） ----
  checkStartfile(startupDir) {
    const expected = this.chip.startfile || [];
    if (!expected.length) {
      this.rows.push({
        name: 'startfile',
        verdict: 'info',
        text: `芯片 ${this.chipName} 在 mcu_isa.json 中 startfile 为空（[]），跳过校验`,
      });
      return true;
    }
    if (!fs.existsSync(startupDir) || !fs.statSync(startupDir).isDirectory()) {
      this.rows.push({ name: 'startfile', verdict: 'fail', text: `Startup 目录不存在: ${startupDir}` });
      return false;
    }
    const found = fs.readdirSync(startupDir).filter((f) => f.toUpperCase().endsWith('.S')).sort();
    const missing = expected.filter((e) => !found.includes(e));
    const extra = found.filter((f) => !expected.includes(f));
    if (!missing.length && !extra.length) {
      this.rows.push({
        name: 'startfile',
        verdict: 'ok',
        text: `Startup 目录 ${startupDir} 中的 .S 文件与 mcu_isa.json startfile 完全一致: ${expected.join(', ')}`,
      });
      return true;
    }
    let msg =
      `Startup 目录 ${startupDir} 与 mcu_isa.json startfile 不一致（只提示，不修改）` +
      ` | 期望(startfile)=${expected.join(', ')} | 实际=${found.join(', ')}`;
    if (missing.length) msg += ` | 缺少: ${missing.join(', ')}`;
    if (extra.length) msg += ` | 多余: ${extra.join(', ')}`;
    this.rows.push({ name: 'startfile', verdict: 'warn', text: msg });
    return true; // startfile 不一致只提示，不导致 FAIL
  }
}

// ---------- 主入口 ----------
function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.selftest) {
    const cases = [
      { name: 'march PASS', expect: true, march: 'rv32imafc_zba_zbb_zbc_zbs_xw', ext: ['i', 'm', 'a', 'c', 'f', 'zba', 'zbb', 'zbc', 'zbs', 'xw'] },
      { name: 'march FAIL d', expect: false, march: 'rv32imafdc_zba_zbb_zbc_zbs_xw', ext: ['i', 'm', 'a', 'c', 'f', 'zba', 'zbb', 'zbc', 'zbs', 'xw'] },
      { name: 'march FAIL rv64', expect: false, march: 'rv64imac_xw', ext: ['i', 'm', 'a', 'c', 'xw'] },
      { name: 'march FAIL z 扩展', expect: false, march: 'rv32imac_zba_zbb_zbc_zbs_xw', ext: ['i', 'm', 'a', 'c', 'xw'] },
      { name: 'march FAIL 空', expect: false, march: 'rv32', ext: ['i'] },
      // 顺序无关：march 中 f 在 c 前，isa_ext 中 c 在 f 前
      { name: 'march 顺序无关', expect: true, march: 'rv32imafc_zba_zbb_zbc_zbs_xw', ext: ['i', 'm', 'a', 'c', 'f', 'zba', 'zbb', 'zbc', 'zbs', 'xw'] },
    ];
    let failed = 0;
    for (const c of cases) {
      const got = marchCheck(c.march, c.ext).ok;
      const pass = got === c.expect;
      if (!pass) failed++;
      console.log(`${pass ? '✅' : '❌'} ${c.name.padEnd(18)} expect=${c.expect ? 'PASS' : 'FAIL'} got=${got ? 'PASS' : 'FAIL'}`);
    }
    console.log();
    console.log(failed === 0 ? '自测通过' : `自测失败 ${failed} 项`);
    return failed === 0 ? 0 : 1;
  }

  // march + 手动 isa_ext（不查 json）
  if (args.march && args['isa-ext'] && !args.chip) {
    const isaExt = String(args['isa-ext']).split(',').map((s) => s.trim()).filter(Boolean);
    const { ok, err, parts, missing } = marchCheck(args.march, isaExt);
    console.log(DIVIDER);
    console.log('march 校验报告（手动指定 isa_ext）');
    console.log(DIVIDER);
    console.log(`march   : ${args.march}`);
    if (parts) console.log(`拆分结果: ${parts.join(', ')}`);
    console.log(`isa_ext : ${isaExt.join(', ')}`);
    if (err) {
      console.log(`❌ [ERROR] ${err}`);
      return 1;
    }
    if (ok) {
      console.log(`✅ PASS — 拆分出的 ${parts.length} 项全部在 isa_ext 中`);
      return 0;
    }
    console.log(`❌ FAIL — 以下 ${missing.length} 项不在 isa_ext 中: ${missing.join(', ')}`);
    return 1;
  }

  if (!args.march && !args.toolchain && !args.abi && !args['startfile-dir']) {
    console.error('[FATAL] 至少提供 --march / --toolchain / --abi / --startfile-dir 之一');
    return 1;
  }
  if (!args.chip) {
    console.error('[FATAL] 需要 --chip（或 march 校验时用 --isa-ext 代替）');
    return 1;
  }

  const isa = loadIsa();
  const chk = new Checker(args.chip, args.core);
  chk.resolve(isa);
  const cores = chk.entry.cores || [];
  const coreLabel = args.core ? pickCore(cores, args.core).core : '全部内核';

  console.log(DIVIDER);
  console.log(`编译配置校验报告（${chk.chip.name} / 系列 ${chk.entry.series} / 内核 ${coreLabel}）`);
  console.log(DIVIDER);
  if (args.march) chk.checkMarch(args.march);
  if (args.toolchain) chk.checkToolchain(args.toolchain);
  if (args.abi) chk.checkAbi(args.abi);
  if (args['startfile-dir']) chk.checkStartfile(args['startfile-dir']);
  const marks = { ok: '✅', fail: '❌', warn: '⚠', info: 'ℹ' };
  for (const r of chk.rows) {
    console.log(`  ${marks[r.verdict]} [${r.name}] ${r.text}`);
  }
  console.log();
  const totalOk = chk.rows.every((r) => r.verdict !== 'fail');
  console.log(`结论: ${totalOk ? '✅ PASS — 全部校验通过' : '❌ FAIL — 存在不匹配项'}`);
  return totalOk ? 0 : 1;
}

process.exitCode = main();
