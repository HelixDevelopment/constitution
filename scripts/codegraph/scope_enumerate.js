#!/usr/bin/env node
// ============================================================================
// scope_enumerate.js — read-only bridge into an installed CodeGraph runner's
//                      OWN file-discovery code (scanDirectory + config loader)
// ============================================================================
// Purpose      Ask the runner itself which files it would index, so the scope
//              guard measures the engine's real behaviour instead of a
//              re-implementation of it (§11.4.201 — assert the real condition).
//              Also runs the runner-contract probe (config-format drift) and the
//              "explain drops" census of tracked source dropped by built-in skips.
// Usage        node scope_enumerate.js <mode> --dist <runner lib/dist> --root <dir> [opts]
//                mode enumerate  --out <file> [--overlay-config F] [--overlay-gitignore F]
//                                [--config-filename codegraph.json] [--roots-file F]
//                                (--roots-file: JSON array of project-relative dirs; the
//                                 answer carries root_census {dir: {checked_out, tracked_source}})
//                mode contract   --work <empty scratch dir> [--config-filename codegraph.json]
//                mode explain    --enumerated <file> --out <file> [--overlay-config F]
//                                [--overlay-gitignore F]
// Inputs       the runner's dist tree (never modified); the project tree (read only).
//              Overlays let a dry run apply a candidate codegraph.json/.gitignore
//              WITHOUT writing to the project: fs reads of <root>/<config-filename>
//              and <root>/.gitignore are answered from the overlay files.
// Outputs      one JSON object on stdout; files named by --out.
// Side effects none on the project (no DB, no lock, no writes). `contract` mode
//              creates a throwaway git repo under --work.
// Dependencies node >= 18, git.
// Exit codes   0 ok; 2 contract drift (contract mode); 3 usage / runner not loadable.
// Cross-refs   codegraph_scope_guard.py, scope_render.py, constitution §11.4.78 /
//              §11.4.79 / §11.4.201 / §11.4.273.
// ============================================================================
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function die(code, msg) {
  process.stdout.write(JSON.stringify({ ok: false, error: msg }) + '\n');
  process.exit(code);
}

function parseArgs(argv) {
  const mode = argv[0];
  const o = { mode };
  for (let i = 1; i < argv.length; i += 2) {
    const k = argv[i];
    if (!k || !k.startsWith('--') || i + 1 >= argv.length) die(3, 'bad argument near ' + k);
    o[k.slice(2)] = argv[i + 1];
  }
  return o;
}

const opts = parseArgs(process.argv.slice(2));
if (!opts.dist) die(3, '--dist <runner lib/dist> is required');
const DIST = path.resolve(opts.dist);
const CFG_NAME = opts['config-filename'] || 'codegraph.json';

// ---- overlay: answer reads of <root>/<CFG_NAME> and <root>/.gitignore -------------
// Installed BEFORE the runner modules are required. The runner imports fs through
// a live-getter wrapper, so patching the shared fs module object is observed.
const overlay = new Map();
function installOverlay(root) {
  const ROOT = path.resolve(root);
  if (opts['overlay-config']) overlay.set(path.join(ROOT, CFG_NAME), fs.readFileSync(opts['overlay-config']));
  if (opts['overlay-gitignore']) overlay.set(path.join(ROOT, '.gitignore'), fs.readFileSync(opts['overlay-gitignore']));
  if (overlay.size === 0) return;
  const realRead = fs.readFileSync, realStat = fs.statSync, realExists = fs.existsSync;
  const hit = (p) => (typeof p === 'string' ? overlay.get(path.resolve(p)) : undefined);
  fs.readFileSync = function (p, enc) {
    const b = hit(p);
    if (b === undefined) return realRead.apply(fs, arguments);
    const e = typeof enc === 'string' ? enc : (enc && enc.encoding);
    return e ? b.toString(e) : Buffer.from(b);
  };
  fs.statSync = function (p) {
    const b = hit(p);
    if (b === undefined) return realStat.apply(fs, arguments);
    const st = realStat(opts['overlay-config'] && path.resolve(p) === path.join(ROOT, CFG_NAME)
      ? opts['overlay-config'] : opts['overlay-gitignore']);
    return st;
  };
  fs.existsSync = function (p) {
    if (hit(p) !== undefined) return true;
    return realExists.apply(fs, arguments);
  };
}

function loadRunner() {
  let pc, ex, grammars, ignoreLib;
  try {
    pc = require(path.join(DIST, 'project-config.js'));
    ex = require(path.join(DIST, 'extraction', 'index.js'));
    grammars = require(path.join(DIST, 'extraction', 'grammars.js'));
  } catch (e) {
    die(3, 'runner not loadable from ' + DIST + ': ' + e.message);
  }
  try { ignoreLib = require(require.resolve('ignore', { paths: [DIST] })); } catch (e) { ignoreLib = null; }
  return { pc, ex, grammars, ignoreLib };
}

function runnerVersion() {
  for (const p of [path.join(DIST, '..', 'package.json'), path.join(DIST, 'package.json')]) {
    try { return JSON.parse(fs.readFileSync(p, 'utf8')).version || null; } catch (e) { /* next */ }
  }
  return null;
}

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] });
}

// Per-root census: is the dir its own checked-out git repo, and how many of ITS OWN
// tracked files are runner-supported source files? (`git ls-files` WITHOUT
// --recurse-submodules: a nested gitlink is one non-source entry.) Lets the guard tell
// "zero enumerated because excluded" from "zero because there was nothing to index".
function censusRoots(ROOT, roots, pc, grammars) {
  const overrides = pc.loadExtensionOverrides(ROOT);
  const out = {};
  for (const r of roots) {
    const dir = path.join(ROOT, r);
    let top = null;
    try { top = fs.realpathSync(git(dir, ['rev-parse', '--show-toplevel']).trim()); } catch (e) { top = null; }
    let real = null;
    try { real = fs.realpathSync(dir); } catch (e) { real = null; }
    if (!top || !real || top !== real) { out[r] = { checked_out: false, tracked_source: 0 }; continue; }
    const list = git(dir, ['ls-files', '-z']).split('\0').filter(Boolean);
    out[r] = { checked_out: true, tracked_source: list.filter((p) => grammars.isSourceFile(p, overrides)).length };
  }
  return out;
}

// ---- mode: enumerate ----------------------------------------------------------------
function modeEnumerate() {
  if (!opts.root || !opts.out) die(3, 'enumerate needs --root and --out');
  installOverlay(opts.root);
  const { pc, ex, grammars } = loadRunner();
  // scan-mode probe: the runner CATCHES a throw from `git ls-files -z -s --recurse-submodules` (measured: ENOBUFS when the
  // listing exceeds its 50 MiB execFileSync buffer) and silently falls back to a filesystem walk — observe it, never guess.
  let scanMode = 'git';  // §1.1-anchor:scan_mode_probe
  const cp = require('child_process');
  const realExec = cp.execFileSync;
  cp.execFileSync = function (cmd, args) {
    try { return realExec.apply(this, arguments); } catch (e) {
      const a = Array.isArray(args) ? args.join(' ') : '';
      if (cmd === 'git' && scanMode === 'git' && (a === 'ls-files -z -s --recurse-submodules' || a.startsWith('rev-parse --show-toplevel'))) {
        scanMode = 'walk_fallback:' + (a.startsWith('rev-parse') ? 'not_a_git_repo' : (e.code || 'error'));
      }
      throw e;
    }
  };
  const t0 = Date.now();
  const files = ex.scanDirectory(path.resolve(opts.root));
  cp.execFileSync = realExec;
  files.sort();
  fs.writeFileSync(opts.out, files.join('\n') + (files.length ? '\n' : ''));
  const ans = {
    ok: true, mode: 'enumerate', count: files.length, ms: Date.now() - t0, scan_mode: scanMode,
    runner_version: runnerVersion(), runner_config_filename: pc.PROJECT_CONFIG_FILENAME,
    overlay: [...overlay.keys()],
  };
  if (opts['roots-file']) {
    const roots = JSON.parse(fs.readFileSync(opts['roots-file'], 'utf8'));
    ans.root_census = censusRoots(path.resolve(opts.root), roots, pc, grammars);
  }
  process.stdout.write(JSON.stringify(ans) + '\n');
}

// ---- mode: contract (config-format drift probe) --------------------------------------
// Builds a throwaway git repo and checks, through the runner's OWN scanDirectory,
// every assumption the scope tooling relies on. Any broken assumption => exit 2.
function modeContract() {
  if (!opts.work) die(3, 'contract needs --work <scratch dir>');
  const { pc, ex } = loadRunner();
  const W = path.resolve(opts.work, 'cg_contract_repo');
  fs.rmSync(W, { recursive: true, force: true });
  fs.mkdirSync(W, { recursive: true });
  const write = (rel, s) => { fs.mkdirSync(path.dirname(path.join(W, rel)), { recursive: true }); fs.writeFileSync(path.join(W, rel), s); };
  write('keep_me.c', 'int keep(void){return 1;}\n');
  write('drop_me/x.c', 'int drop(void){return 1;}\n');
  write('build/owned.c', 'int owned(void){return 1;}\n');
  write('.gitignore', '# probe\n');
  git(W, ['init', '-q']);
  git(W, ['-c', 'user.email=p@p', '-c', 'user.name=p', 'add', '-A']);
  git(W, ['-c', 'user.email=p@p', '-c', 'user.name=p', 'commit', '-qm', 'probe']);
  const checks = [];
  const scan = () => { if (pc.clearProjectConfigCache) pc.clearProjectConfigCache(); return new Set(ex.scanDirectory(W)); };
  const add = (id, ok, detail) => checks.push({ id, ok: !!ok, detail });

  add('C0_config_filename', pc.PROJECT_CONFIG_FILENAME === CFG_NAME,
    'runner PROJECT_CONFIG_FILENAME=' + JSON.stringify(pc.PROJECT_CONFIG_FILENAME) + ' expected=' + JSON.stringify(CFG_NAME));
  let s = scan();
  // control needle: the probe repo must be visible at all (instrument can see)
  add('C1_control_needle_visible', s.has('keep_me.c') && s.has('drop_me/x.c'), 'baseline scan=' + JSON.stringify([...s]));
  add('C2_builtin_skip_build', !s.has('build/owned.c'), 'build/owned.c present without negation=' + s.has('build/owned.c'));
  // config file with exclude + an unknown provenance key (must be tolerated)
  write(CFG_NAME, JSON.stringify({ _generated: { probe: true }, exclude: ['/drop_me/'] }) + '\n');
  s = scan();
  add('C3_exclude_honored_with_unknown_key', s.has('keep_me.c') && !s.has('drop_me/x.c'),
    'with ' + CFG_NAME + ' scan=' + JSON.stringify([...s]));
  // root .gitignore negation re-includes a built-in-skipped dir
  write('.gitignore', '# probe\n!/build/\n');
  s = scan();
  add('C4_gitignore_negation_reincludes', s.has('build/owned.c'), 'with !/build/ scan=' + JSON.stringify([...s]));
  // exclude wins over the negation
  write(CFG_NAME, JSON.stringify({ exclude: ['/drop_me/', '/build/'] }) + '\n');
  s = scan();
  add('C5_exclude_wins_over_negation', !s.has('build/owned.c') && s.has('keep_me.c'), 'scan=' + JSON.stringify([...s]));
  const ok = checks.every((c) => c.ok);
  process.stdout.write(JSON.stringify({ ok, mode: 'contract', runner_version: runnerVersion(),
    runner_config_filename: pc.PROJECT_CONFIG_FILENAME, checks }) + '\n');
  fs.rmSync(W, { recursive: true, force: true });
  process.exit(ok ? 0 : 2);
}

// ---- mode: explain (census of tracked source dropped by built-in skips) ------------
function modeExplain() {
  if (!opts.root || !opts.enumerated || !opts.out) die(3, 'explain needs --root --enumerated --out');
  installOverlay(opts.root);
  const { pc, ex, grammars } = loadRunner();
  const ROOT = path.resolve(opts.root);
  const overrides = pc.loadExtensionOverrides(ROOT);
  const enumerated = new Set(fs.readFileSync(opts.enumerated, 'utf8').split('\n').filter(Boolean));
  const out = git(ROOT, ['ls-files', '-z', '--recurse-submodules']);
  const tracked = out.split('\0').filter((p) => p && grammars.isSourceFile(p, overrides));
  // defaults-only matcher: buildDefaultIgnore on an empty dir has no .gitignore to merge
  const empty = fs.mkdtempSync(path.join(require('os').tmpdir(), 'cgscope-empty-'));
  const defaults = ex.buildDefaultIgnore(empty);
  fs.rmSync(empty, { recursive: true, force: true });
  const exclude = pc.loadExcludePatterns(ROOT);
  const ig = require(require.resolve('ignore', { paths: [DIST] }));
  const exM = exclude.length ? ig().add(exclude) : null;
  const groups = new Map();
  let dropped = 0;
  for (const p of tracked) {
    if (enumerated.has(p)) continue;
    if (exM && exM.ignores(p)) continue; // excluded on purpose, not a silent drop
    dropped++;
    const segs = p.split('/');
    let key = null;
    for (let i = 1; i < segs.length; i++) {
      const dir = segs.slice(0, i).join('/') + '/';
      if (defaults.ignores(dir)) { key = 'default:' + dir; break; }
    }
    if (!key) key = 'non-default:' + segs.slice(0, Math.min(2, segs.length - 1)).join('/') + '/';
    groups.set(key, (groups.get(key) || 0) + 1);
  }
  const rows = [...groups.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1));
  fs.writeFileSync(opts.out, rows.map(([k, v]) => v + '\t' + k).join('\n') + '\n');
  process.stdout.write(JSON.stringify({ ok: true, mode: 'explain', tracked_source: tracked.length, dropped, groups: rows.length }) + '\n');
}

if (opts.mode === 'enumerate') modeEnumerate();
else if (opts.mode === 'contract') modeContract();
else if (opts.mode === 'explain') modeExplain();
else die(3, 'unknown mode ' + opts.mode);
