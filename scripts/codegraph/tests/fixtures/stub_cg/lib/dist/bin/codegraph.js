'use strict';
// UNIT-TEST STUB ONLY (constitution §11.4.27). Environment-driven fake of the
// codegraph CLI used by tests/test_unit_safe.sh. Never used by production code.
//   STUB_CALL_LOG   append "<role> <args...>" per invocation
//   STUB_VERSION    version string (default 1.6.0); STUB_RUNNER_VERSION overrides it for the runner role
//   STUB_FILES      comma list of paths to insert into files (default src/a.c,src/b.c,lib/c.py)
//   STUB_STATE      index_state value (default complete)
//   STUB_REPORTED   number printed in "Indexed N files" (default = number of files)
//   STUB_ACCOUNTED  index_files_accounted (default = number of files)
//   STUB_SLEEP_MS   how long a bulk op holds the lock (default 1500)
//   STUB_EXIT       exit code of a bulk op (default 0)
//   STUB_PARK=1     stay alive STUB_SLEEP_MS with the given argv, no lock, no DB
//   STUB_SYNC_HOLD=1     `sync` on an EXISTING db holds the lock for STUB_SLEEP_MS (like a long real sync)
//   STUB_RESOLVE_PENDING=1  `sync` on an existing db deletes status='pending' unresolved_refs rows (a completed resolution pass)
//   The stub db carries the real unresolved_refs table + idx_unresolved_status (subset of CodeGraph's schema.sql).
const fs = require('fs');
const path = require('path');
const role = process.env.STUB_ROLE || 'unknown';
const args = process.argv.slice(2);
if (process.env.STUB_CALL_LOG) fs.appendFileSync(process.env.STUB_CALL_LOG, role + ' ' + args.join(' ') + '\n');
if (args[0] === '--version' || args[0] === 'version' || args[0] === '-V') {
  console.log((role === 'runner' && process.env.STUB_RUNNER_VERSION) || process.env.STUB_VERSION || '1.6.0'); process.exit(0);
}
const op = args[0];
if (process.env.STUB_PARK === '1') {
  // park: stay alive with the requested argv (e.g. "sync <root>" / "serve --mcp") holding NO lock —
  // lets tests prove the launcher's /proc root scan, independent of the lock file.
  setTimeout(() => process.exit(0), parseInt(process.env.STUB_SLEEP_MS || '60000', 10));
  return;
}
const pos = args.slice(1).filter((a) => !a.startsWith('-'));
const proj = path.resolve(pos[pos.length - 1] || process.cwd());
const cg = path.join(proj, '.codegraph');
const dbp = path.join(cg, 'codegraph.db');
function openDb() { const { DatabaseSync } = require('node:sqlite'); return new DatabaseSync(dbp); }
function bulk() {
  fs.mkdirSync(cg, { recursive: true });
  const lock = path.join(cg, 'codegraph.lock');
  fs.writeFileSync(lock, String(process.pid), { flag: 'wx' });
  try { fs.unlinkSync(dbp); } catch (e) { /* none */ }
  const db = openDb();
  db.exec('create table files(path text primary key, language text); create table nodes(id text primary key);' +
          'create table project_metadata(key text primary key, value text, updated_at integer);' +
          "create table unresolved_refs(id integer primary key autoincrement, from_node_id text not null, reference_name text not null, " +
          "reference_kind text not null, line integer not null, col integer not null, candidates text, file_path text not null default '', " +
          "language text not null default 'unknown', status text not null default 'pending', name_tail text not null default '');" +
          'create index idx_unresolved_status on unresolved_refs(status)');
  const files = (process.env.STUB_FILES || 'src/a.c,src/b.c,lib/c.py').split(',').filter(Boolean);
  const ins = db.prepare('insert into files(path, language) values (?, ?)');
  for (const f of files) ins.run(f, 'c');
  db.prepare("insert into nodes(id) values ('n1')").run();
  const meta = db.prepare('insert into project_metadata values (?, ?, 0)');
  meta.run('index_state', process.env.STUB_STATE || 'complete');
  meta.run('index_files_accounted', String(process.env.STUB_ACCOUNTED || files.length));
  db.close();
  console.log('Phase: scanning');
  console.log('  Indexed ' + (process.env.STUB_REPORTED || files.length) + ' files');
  const ms = parseInt(process.env.STUB_SLEEP_MS || '1500', 10);
  setTimeout(() => { try { fs.unlinkSync(lock); } catch (e) { /* gone */ } process.exit(parseInt(process.env.STUB_EXIT || '0', 10)); }, ms);
}
if (op === 'init' || op === 'index') { bulk(); }
else if (op === 'sync') {
  // like the real DatabaseConnection.open: recreate a dropped idx_unresolved_status (the TABLE is not recreated
  // by this stub); optionally simulate a completed resolution pass (STUB_RESOLVE_PENDING=1)
  const resolvePending = () => {
    const db = openDb();
    try { db.exec('create index if not exists idx_unresolved_status on unresolved_refs(status)'); } catch (e) { /* no table */ }
    if (process.env.STUB_RESOLVE_PENDING === '1') {
      try { db.exec("delete from unresolved_refs where status = 'pending'"); } catch (e) { /* no table */ }
    }
    db.close();
  };
  if (!fs.existsSync(dbp)) { bulk(); }
  else if (process.env.STUB_SYNC_HOLD === '1') {
    const lock = path.join(cg, 'codegraph.lock');
    fs.writeFileSync(lock, String(process.pid), { flag: 'wx' });
    resolvePending();
    console.log('Added: 0');
    const ms = parseInt(process.env.STUB_SLEEP_MS || '1500', 10);
    setTimeout(() => { try { fs.unlinkSync(lock); } catch (e) { /* gone */ } process.exit(parseInt(process.env.STUB_EXIT || '0', 10)); }, ms);
  } else { resolvePending(); console.log('Added: 0'); process.exit(0); }
} else if (op === 'status') {
  let n = 0;
  try { const db = openDb(); n = db.prepare('select count(*) as c from files').get().c; db.close(); } catch (e) { n = 0; }
  console.log('Index Statistics:');
  console.log('  Files:     ' + (process.env.STUB_STATUS_FILES || n));
  process.exit(0);
} else if (op === 'sleep') {
  // used by tests as a live process carrying the real codegraph identity
  setTimeout(() => process.exit(0), parseInt(process.env.STUB_SLEEP_MS || '60000', 10));
} else { process.exit(0); }
