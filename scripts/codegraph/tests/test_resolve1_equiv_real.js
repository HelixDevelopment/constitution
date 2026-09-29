// test_resolve1_equiv_real.js — per-reference resolution outcomes on a REAL index, read-only.
//
// Purpose   Emit, for a deterministic sample of pending unresolved_refs, exactly what the
//           resolver decides for each one, so a STOCK package and a PATCHED package can be
//           compared byte-for-byte (sha256 of stdout) on the operator's real data.
// Usage     node test_resolve1_equiv_real.js <distDir> <dbPath> <projectRoot> <offsets-csv> <n-per-offset>
//             offsets: rowid lower bounds, e.g. 5000000,10000000 ; n refs are read after each.
// Inputs    a codegraph.db that is NOT being written (a frozen copy). It is opened
//           immutable+read-only: no locks, no WAL, no writes of any kind.
// Outputs   stdout: one TSV line per ref  rowId kind lang name file target resolvedBy confidence
//           stderr: timing summary (refs, ms, refs/s, getAllFilePaths calls)
// Side effects none (read-only). Never point this at a DB a writer is using.
// Cross     test_resolve1.sh (fixture oracle), runner_patches/resolve1.py
'use strict';
const [,, dist, dbPath, root, offsArg, nArg] = process.argv;
if (!nArg) { console.error('usage: node test_resolve1_equiv_real.js <distDir> <dbPath> <projectRoot> <offsets-csv> <n>'); process.exit(2); }
const { QueryBuilder } = require(dist + '/db/queries.js');
const { ReferenceResolver } = require(dist + '/resolution/index.js');
const { DatabaseSync } = require('node:sqlite');
const mod = require(dist + '/db/sqlite-adapter.js');
const raw = new DatabaseSync(new URL('file://' + dbPath + '?immutable=1&mode=ro'), { readOnly: true });
const tmp = mod.createDatabase(':memory:', {});
tmp.db._db.close();
tmp.db._db = raw;
const q = new QueryBuilder(tmp.db);
let gaf = 0;
const orig = q.getAllFilePaths.bind(q);
q.getAllFilePaths = function () { gaf++; return orig(); };
const r = new ReferenceResolver(root, q);
r.initialize();
r.warmCaches();
let refs = [];
for (const off of String(offsArg).split(',')) refs = refs.concat(q.getUnresolvedReferencesBatchAfter(Number(off), Number(nArg)));
const t0 = Date.now();
const lines = [];
for (const ref of refs) {
  const res = r.resolveOne(ref);
  lines.push([ref.rowId, ref.referenceKind, ref.language, ref.referenceName, ref.filePath,
    res ? res.targetNodeId : '-', res ? res.resolvedBy : 'fail', res ? res.confidence : ''].join('\t'));
}
const ms = Date.now() - t0;
process.stdout.write(lines.join('\n') + '\n');
console.error(`[equiv] refs=${refs.length} resolveMs=${ms} refs/s=${(refs.length * 1000 / Math.max(1, ms)).toFixed(1)} getAllFilePathsCalls=${gaf}`);
