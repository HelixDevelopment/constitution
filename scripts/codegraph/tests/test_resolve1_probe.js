// test_resolve1_probe.js — behavioural probe of ctx.getAllFiles() for test_resolve1.sh.
// usage: node test_resolve1_probe.js <distDir> <writable db copy> <projectRoot> [vue]
// Prints one JSON object of FACTS (no verdicts); the shell test asserts on them.
//   same      : two consecutive getAllFiles() calls return the identical array
//   frozen    : the returned array is frozen
//   order_ok  : elementwise equal to SELECT path FROM files ORDER BY path
//   after_insert_len / after_clear_len / has_new_after_clear : clearCaches() invalidation
//   vue_scan_after_add / vue_new_found (vue mode): a .vue row added + clearCaches() is found
//   vue_before / vue_after_init : initialize() invalidation — a .vue row inserted WITHOUT
//     clearCaches must be seen by detectFrameworks() (stock re-queries; fixture has no vue)
'use strict';
const [,, dist, dbPath, root, mode] = process.argv;
const { QueryBuilder } = require(dist + '/db/queries.js');
const { ReferenceResolver } = require(dist + '/resolution/index.js');
const { createDatabase } = require(dist + '/db/sqlite-adapter.js');
const { db } = createDatabase(dbPath, {});
const q = new QueryBuilder(db);
const r = new ReferenceResolver(root, q);
r.initialize();
const ctx = r.getResolutionContext();
if (mode === 'vue') {
  // R5: count String#endsWith('.vue') probes per vue.resolve call (stock scans every file per call).
  const vue = r.frameworks.find((f) => f.name === 'vue');
  // The ref must be in a language the vue resolver serves: CodeGraph >= 1.6.2 returns null
  // for any other language before the scan (VUE_SCRIPT_LANGUAGES), so a C++ ref would never
  // reach the code under test. The shell test also asserts vue_scan_1st > 0 (scan reached).
  const ref = { referenceName: 'Widget', referenceKind: 'calls', filePath: 'tools/web/src/app.js', language: 'javascript', line: 1, column: 1, fromNodeId: 'x' };
  const ew = String.prototype.endsWith; let n = 0;
  String.prototype.endsWith = function (s) { if (s === '.vue') n++; return ew.apply(this, arguments); };
  const r1 = vue ? vue.resolve(ref, ctx) : null; const s1 = n; n = 0;
  const r2 = vue ? vue.resolve(ref, ctx) : null; const s2 = n;
  // R5b (review I2-1): a .vue file added after the first resolve, then clearCaches(), must be found: the
  // subset is keyed per file-list identity, never served stale from an earlier generation. The node lookup
  // for the new file is answered by a thin overlay (the DB row has no nodes); the file LIST is the real one.
  db.prepare("INSERT INTO files (path, content_hash, language, size, modified_at, indexed_at) VALUES (?, 'x', 'vue', 1, 0, 0)")
    .run('web/Gadget.vue');
  r.clearCaches();
  const ctx2 = Object.create(ctx);
  ctx2.getNodesInFile = (f) => (f === 'web/Gadget.vue'
    ? [{ kind: 'component', name: 'Gadget', id: 'helix-probe-gadget' }] : ctx.getNodesInFile(f));
  n = 0;
  const r3 = vue ? vue.resolve(Object.assign({}, ref, { referenceName: 'Gadget' }), ctx2) : null; const s3 = n;
  String.prototype.endsWith = ew;
  const comp = q.getNodesByFile('web/Widget.vue').find((x) => x.kind === 'component');
  process.stdout.write(JSON.stringify({ vue: !!vue, n: ctx.getAllFiles().length, vue_scan_1st: s1, vue_scan_2nd: s2,
    vue_resolve_ok: !!(r1 && r2 && comp && r1.targetNodeId === comp.id && r2.targetNodeId === comp.id),
    vue_scan_after_add: s3, vue_new_found: !!(r3 && r3.targetNodeId === 'helix-probe-gadget') }) + '\n');
  process.exit(0);
}
const a = ctx.getAllFiles();
const b = ctx.getAllFiles();
const direct = q.getAllFilePaths();
const out = {
  n: a.length,
  same: a === b,
  frozen: Object.isFrozen(a),
  order_ok: a.length === direct.length && a.every((p, i) => p === direct[i]),
};
const ins = db.prepare("INSERT INTO files (path, content_hash, language, size, modified_at, indexed_at) VALUES (?, 'x', 'c', 1, 0, 0)");
ins.run('zz_helix_probe_new_1.c');
out.after_insert_len = ctx.getAllFiles().length;
r.clearCaches();
const c = ctx.getAllFiles();
out.after_clear_len = c.length;
out.has_new_after_clear = c.includes('zz_helix_probe_new_1.c');
out.new_array_after_clear = c !== a;
out.vue_before = r.getDetectedFrameworks().includes('vue');
ctx.getAllFiles(); // re-arm the memo from the current (vue-free) file set
ins.run('zz_helix_probe_new_2.vue');
r.initialize();
out.vue_after_init = r.getDetectedFrameworks().includes('vue');
process.stdout.write(JSON.stringify(out) + '\n');
