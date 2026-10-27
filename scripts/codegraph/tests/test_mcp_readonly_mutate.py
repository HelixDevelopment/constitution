#!/usr/bin/env python3
# test_mcp_readonly_mutate.py <id> <copy-dir> — apply ONE named mutation to a COPY of the codegraph tooling
# (never the tracked tree). Prints the R-list that must FAIL. Exit 2 on unknown id / anchor not exactly once,
# exit 3 when the mutant has no meaning for the stock package shape under test (reported N/A by the harness, never counted).
#
# SHAPES (mcpro1.py patches two upstream code shapes; the test builds against whichever the INSTALLED package has):
#   A = CodeGraph 1.6.0   B = CodeGraph >= 1.6.2 (native readOnly open, writer-slot + writable-engine paths in direct mode)
# A mutant must re-open its hole in the shape that is actually under test, so each mutant carries per-shape edits. On shape B
# the watcher / catch-up-sync / writer-slot holes are closed by TWO layers (the patched method AND the engine's own native
# `readOnly` option); a single-layer mutant is equivalent there and would survive for the wrong reason, so the B mutants for
# those holes revert every layer that closes the hole (the shape-A anchors are unaffected). §11.4.201 / §11.4.273: the
# mutation must be shown to take effect on the effective code path, or its survival says nothing.
import os
import sys

P = "runner_patches/mcpro1.py"
INIT = "runner_patches/__init__.py"
LEG_ACQ = (P, "        throw new Error('helix-mcpro1: read-only runner cannot acquire the write lock');",
           "        return this.helixLegacyAcquire();")
WATCH = (P, "        return;\n    }\n    helixLegacyStartWatching() {",
         "        return this.helixLegacyStartWatching();\n    }\n    helixLegacyStartWatching() {")
SYNC_TAIL = "        return; %s: no startup catch-up sync (cg.sync() writes)\n    }\n    helixLegacyCatchUpSync("
SYNC_A = (P, SYNC_TAIL + ") {", "        return this.helixLegacyCatchUpSync(); %s: no startup catch-up sync (cg.sync() writes)\n    }\n    helixLegacyCatchUpSync() {")
SYNC_B = (P, SYNC_TAIL + "afterReopen = false) {", "        return this.helixLegacyCatchUpSync(afterReopen); %s: no startup catch-up sync (cg.sync() writes)\n    }\n    helixLegacyCatchUpSync(afterReopen = false) {")
OPEN_B_RW = (P, "helixLegacyOpen(dbPath, { ...options, readOnly: true });", "helixLegacyOpen(dbPath, { ...options, readOnly: false });")
ENGINE_B_WRITABLE = (P, '"        this.engine = new engine_1.MCPEngine({ readOnly: true }); " + TAG',
                     '"        this.engine = new engine_1.MCPEngine({ queryPool: true, queryPoolDefaultMax: DIRECT_QUERY_POOL_MAX }); " + TAG')
WRITER_B_SLOT = (P, '"        const writerRoot = null; " + TAG', '"        const writerRoot = resolveDaemonRoot(this.projectPath); " + TAG')

# id -> {shape: (edits, expected-FAIL R-list)}; "*" = shape-independent
MUT = {
    "M0": {"*": ([(INIT, 'REGISTRY = ["fkidx1", "lockfix1", "datafrag1", "resolve1", "resolve2", "mcpro1"]',
                   'REGISTRY = ["fkidx1", "lockfix1", "datafrag1", "resolve1", "resolve2"]')], "R1,R5,R7")},
    "M1": {"A": ([(P, "createDatabase)(dbPath, { readOnly: true });", "createDatabase)(dbPath, { readOnly: false });")], "R3"),
           "B": ([OPEN_B_RW], "R3")},
    "M3": {"A": ([(P, "        db.pragma('query_only = ON');", "        db.pragma('query_only = ON');\n        return DatabaseConnection.helixLegacyOpen(dbPath);")], "R3,R5"),
           "B": ([OPEN_B_RW], "R3,R5")},
    "M4": {"*": ([LEG_ACQ], "R12")},
    # shape B: the watcher is armed by TWO cooperating steps in upstream mcp/engine.js + mcp/project-lifecycle.js —
    # startWatching() only creates the project lease, and the lease's activate() (which calls cg.watch() and logs
    # "File watcher active") runs lazily from lease.ready(), which only catchUpSync() calls. Both patched methods are
    # no-ops, and the engine's own `readOnly` option also short-circuits both, so the hole re-opens only with all three reverted.
    "M5": {"A": ([WATCH], "R6"), "B": ([WATCH, SYNC_B, ENGINE_B_WRITABLE], "R6")},
    "M6": {"A": ([LEG_ACQ, SYNC_A], "R7"), "B": ([LEG_ACQ, SYNC_B, ENGINE_B_WRITABLE], "R7")},
    "M7": {"*": ([(P, "    return true; %s: MCP always direct", "    return helixLegacyDaemonOptOutSet(); %s: MCP always direct")], "R11")},
    # shape B: with the allowlist off, `codegraph sync` is still refused by the second-line FileLock.acquire throw (documented
    # layering in mcpro1.py), so only R10 (index: removeDatabaseFiles runs before initialize throws) can see the allowlist
    "M8": {"A": ([(P, "        if (!helixOk) {", "        if (false && !helixOk) {")], "R9,R10"),
           "B": ([(P, "        if (!helixOk) {", "        if (false && !helixOk) {")], "R10")},
    "M9": {"*": ([(INIT, 'OPT_IN = frozenset(["mcpro1"])', "OPT_IN = frozenset([])")], "R13")},
    "M10": {"*": ([(INIT, 'EXCLUSIVE = frozenset(["mcpro1"])', "EXCLUSIVE = frozenset([])")], "R13")},
    # shape B only: the writer slot (.codegraph/writer.pid) that 1.6.2 direct mode claims
    "M11": {"B": ([WRITER_B_SLOT], "R14")},
}


def stock_shape(copy_dir):
    src = os.environ.get("STOCK_SRC")
    if not src:
        sys.path.insert(0, copy_dir)
        import fk_index_patch
        src = fk_index_patch.default_src()
    text = open(os.path.join(src, "lib", "dist", "db", "index.js"), encoding="utf-8").read()
    return "B" if text.count("    static open(dbPath, options = {}) {") == 1 else "A"


if len(sys.argv) != 3 or sys.argv[1] not in MUT:
    sys.stderr.write("usage: test_mcp_readonly_mutate.py <%s> <copy-dir>\n" % "|".join(MUT)); sys.exit(2)
copy_dir = sys.argv[2].rstrip("/")
variants = MUT[sys.argv[1]]
shape = "*" if "*" in variants else stock_shape(copy_dir)
if shape not in variants:
    sys.stderr.write("mutant %s has no variant for stock shape %s (not applicable)\n" % (sys.argv[1], shape)); sys.exit(3)
edits, expect = variants[shape]
for rel, old, new in edits:
    path = copy_dir + "/" + rel
    text = open(path, encoding="utf-8").read()
    if text.count(old) != 1:
        sys.stderr.write("anchor occurs %dx in %s: %r\n" % (text.count(old), rel, old[:60])); sys.exit(2)
    open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
print(expect)
