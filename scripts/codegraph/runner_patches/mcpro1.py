"""mcpro1 — READ-ONLY CodeGraph runner for MCP serving. Never used for init/index/sync.

Why (measured, measured on stock v1.6.0): `codegraph serve --mcp` is NOT
read-only. (1) mcp/engine.js runs `catchUpSync()` = `cg.sync()` unconditionally at
startup (a write path; only the file WATCHER has an env kill switch) and starts a file
watcher; (2) every `DatabaseConnection.open()` runs migrations, `healBulkNodeLoad`,
`healBulkSecondaryIndexes` (DDL: recreates deliberately-dropped bulk indexes) and
`healOversizedWal`; (3) `FileLock.acquire()` treats a lock whose MTIME is older than 2
minutes as stale REGARDLESS of the holder PID and unlinks it — so a stock MCP server
started next to a live bulk indexer steals its lock and syncs concurrently; (4) the
default mode spawns a detached daemon per project (daemon.pid/log/sock + up to 16
workers that each run the full heal-writing open). No stock env var or flag prevents
(1)-(3).

This patch makes the runner INCAPABLE of mutating a project (unconditionally — no env
gate, so a missing/typoed variable cannot re-enable a writer), anchor by anchor:
  db/index.js   static open(dbPath)      -> createDatabase(dbPath,{readOnly:true}) (fd O_RDONLY),
                                            PRAGMA query_only=ON, smaller page cache, NO
                                            migrations/heals; schema older than this build =>
                                            throw (never migrate). Stock body kept verbatim
                                            (unreachable) as helixLegacyOpen.
  db/index.js   static initialize(dbPath) -> throw (cannot create a database).
  utils.js      FileLock.acquire()        -> throw   (no write lock, no stale-lock unlink)
  utils.js      FileLock.release()        -> no-op   (never unlinks a lock file)
  mcp/engine.js startWatching()           -> no-op + one stderr notice (contains 'read-only')
  mcp/engine.js catchUpSync()             -> no-op
  mcp/index.js  daemonOptOutSet()         -> always true (direct mode; no daemon, no daemon files)
  bin/codegraph.js  CLI allowlist         -> only `serve --mcp`, `status`, --version/--help/no-args run;
                                            init/index/sync/uninit/unlock/upgrade/... exit 78 before any
                                            open/lock/delete (MEASURED without this guard: the CLI index subcommand
                                            on this runner DELETED the database — removeDatabaseFiles runs
                                            before initialize() throws).
Layering: the CLI allowlist is the first line for command misuse, RO open/no-op sync/no-daemon
are the operational lines for the MCP server itself; the initialize/FileLock throws are
second-line guards for any path that bypasses the CLI (unit-tested at node level, test R12).
Because open() is the single choke point for every project the tools touch (including a
`projectPath` argument that points at another indexed project), every DB the server can
reach is opened read-only.

Exclusive: the runner key is "<ver>-mcpro1" and the patch is refused when combined with
any writer patch (runner_patches.load). Not part of the default patch set (OPT_IN):
build it explicitly with `fk_index_patch.py --patches mcpro1`.

Fail-closed: every anchor must occur exactly once (PatchPlan.replace_once) and the
package must not already carry the marker.
"""
from .common import PatchPlan, Refuse

PATCH_ID = "mcpro1"
SUMMARY = "READ-ONLY MCP runner: RO db open (no migrate/heal), no watcher/catch-up sync/daemon/write-lock; never for init/index/sync"
DBJS = "lib/dist/db/index.js"
UTILS = "lib/dist/utils.js"
ENGINE = "lib/dist/mcp/engine.js"
MCPIDX = "lib/dist/mcp/index.js"
BIN = "lib/dist/bin/codegraph.js"
MARK = "helix-mcpro1"
TAG = "// helix-mcpro1 (constitution/scripts/codegraph/runner_patches/mcpro1.py)"

OPEN_ANCHOR = "    static open(dbPath) {"
OPEN_NEW = """    static open(dbPath) {
        %s: READ-ONLY open — no migration,
        // no heal, no DDL; the descriptor is O_RDONLY and query_only guards a second time.
        if (!fs.existsSync(dbPath)) {
            throw new Error(`Database not found: ${dbPath}`);
        }
        const { db, backend } = (0, sqlite_adapter_1.createDatabase)(dbPath, { readOnly: true });
        db.pragma('busy_timeout = 5000');
        db.pragma('query_only = ON');
        db.pragma('cache_size = -16000');
        db.pragma('temp_store = MEMORY');
        db.pragma('mmap_size = 268435456');
        const currentVersion = (0, migrations_1.getCurrentVersion)(db);
        if (currentVersion < migrations_1.CURRENT_SCHEMA_VERSION) {
            try {
                db.close();
            }
            catch { /* ignore */ }
            throw new Error(`helix-mcpro1: schema v${currentVersion} is older than v${migrations_1.CURRENT_SCHEMA_VERSION}; a read-only runner cannot migrate`);
        }
        return new DatabaseConnection(db, dbPath, backend);
    }
    static helixLegacyOpen(dbPath) {""" % TAG

INIT_ANCHOR = "    static initialize(dbPath) {"
INIT_NEW = """    static initialize(dbPath) {
        %s: a read-only runner never creates a database.
        throw new Error('helix-mcpro1: read-only runner cannot create a database (init/index need the sanctioned writer runner)');
    }
    static helixLegacyInitialize(dbPath) {""" % TAG

ACQ_ANCHOR = "    acquire() {"
ACQ_NEW = """    acquire() {
        %s: no write lock is ever taken, and a lock file
        // (however old) is never treated as stale and unlinked by this runner.
        console.error('helix-mcpro1: read-only runner cannot acquire the write lock (sync/index need the sanctioned writer runner)');
        throw new Error('helix-mcpro1: read-only runner cannot acquire the write lock');
    }
    helixLegacyAcquire() {""" % TAG

REL_ANCHOR = "    release() {"
REL_NEW = """    release() {
        return; %s: never unlinks a lock file
    }
    helixLegacyRelease() {""" % TAG

WATCH_ANCHOR = "    startWatching() {"
WATCH_NEW = """    startWatching() {
        %s: no file watcher in a read-only runner.
        console.error('[CodeGraph] helix-mcpro1: read-only runner - file watcher and catch-up sync are disabled');
        return;
    }
    helixLegacyStartWatching() {""" % TAG

SYNC_ANCHOR = "    catchUpSync() {"
SYNC_NEW = """    catchUpSync() {
        return; %s: no startup catch-up sync (cg.sync() writes)
    }
    helixLegacyCatchUpSync() {""" % TAG

DAEMON_ANCHOR = "function daemonOptOutSet() {"
CLI_ANCHOR = "    const program = new commander_1.Command();"
CLI_NEW = """    %s: CLI allowlist — this runner is the read-only MCP
    // server; every other command (init/index/sync/uninit/unlock/upgrade/...) is refused BEFORE
    // it can open, lock, delete or rewrite anything.
    {
        const helixArgs = process.argv.slice(2);
        const helixCmd = helixArgs[0];
        const helixOk = helixArgs.length === 0
            || ['--version', '-V', '-v', '--help', '-h', 'help', 'status'].includes(helixCmd)
            || (helixCmd === 'serve' && helixArgs.includes('--mcp'));
        if (!helixOk) {
            console.error(`helix-mcpro1: refusing 'codegraph ${helixArgs.join(' ')}' - this runner is READ-ONLY and only serves 'serve --mcp' (plus status/--version/--help); use the sanctioned writer runner for init/index/sync`);
            process.exit(78);
        }
    }
    const program = new commander_1.Command();""" % TAG

DAEMON_NEW = """function daemonOptOutSet() {
    return true; %s: MCP always direct (no detached daemon, no daemon files in .codegraph/)
}
function helixLegacyDaemonOptOutSet() {""" % TAG


def plan(view):
    for rel in (DBJS, UTILS, ENGINE, MCPIDX, BIN):
        if MARK in view.read(rel):
            raise Refuse(f"mcpro1: {rel} is ALREADY patched — --src must be the pristine package")
    p = PatchPlan(PATCH_ID)
    p.replace_once(view, DBJS, OPEN_ANCHOR, OPEN_NEW, "DatabaseConnection.open -> read-only, no migrate/heal")
    p.replace_once(view, DBJS, INIT_ANCHOR, INIT_NEW, "DatabaseConnection.initialize -> throw")
    p.replace_once(view, UTILS, ACQ_ANCHOR, ACQ_NEW, "FileLock.acquire -> throw (no stale-lock unlink)")
    p.replace_once(view, UTILS, REL_ANCHOR, REL_NEW, "FileLock.release -> no-op")
    p.replace_once(view, ENGINE, WATCH_ANCHOR, WATCH_NEW, "MCPEngine.startWatching -> no-op + notice")
    p.replace_once(view, ENGINE, SYNC_ANCHOR, SYNC_NEW, "MCPEngine.catchUpSync -> no-op")
    p.replace_once(view, MCPIDX, DAEMON_ANCHOR, DAEMON_NEW, "daemonOptOutSet -> always direct")
    p.replace_once(view, BIN, CLI_ANCHOR, CLI_NEW, "CLI allowlist (serve --mcp/status/--version/--help only)")
    p.detail = {"mode": "unconditional read-only (no env gate)", "exclusive": True, "opt_in": True,
                "db_open": "createDatabase(readOnly) + query_only, no migrations/heals",
                "stale_lock_unlink": "removed (FileLock.acquire throws, release no-op)",
                "daemon": "never", "watcher": "never", "catch_up_sync": "never"}
    return p
