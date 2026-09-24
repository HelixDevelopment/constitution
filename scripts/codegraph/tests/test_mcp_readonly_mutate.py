#!/usr/bin/env python3
# test_mcp_readonly_mutate.py <id> <copy-dir> — apply ONE named mutation to a COPY of the codegraph tooling
# (never the tracked tree). Prints the R-list that must FAIL. Exit 2 on unknown id / anchor not exactly once.
import sys
P = "runner_patches/mcpro1.py"
LEG_ACQ = ("        throw new Error('helix-mcpro1: read-only runner cannot acquire the write lock');",
           "        return this.helixLegacyAcquire();")
MUT = {
    "M0": ([("runner_patches/__init__.py", 'REGISTRY = ["fkidx1", "lockfix1", "datafrag1", "resolve1", "resolve2", "mcpro1"]',
             'REGISTRY = ["fkidx1", "lockfix1", "datafrag1", "resolve1", "resolve2"]')], "R1,R5,R7"),
    "M1": ([(P, "createDatabase)(dbPath, { readOnly: true });", "createDatabase)(dbPath, { readOnly: false });")], "R3"),
    "M3": ([(P, "        db.pragma('query_only = ON');", "        db.pragma('query_only = ON');\n        return DatabaseConnection.helixLegacyOpen(dbPath);")], "R3,R5"),
    "M4": ([(P,) + LEG_ACQ], "R12"),
    "M5": ([(P, "        return;\n    }\n    helixLegacyStartWatching() {", "        return this.helixLegacyStartWatching();\n    }\n    helixLegacyStartWatching() {")], "R6"),
    "M6": ([(P,) + LEG_ACQ,
            (P, "        return; %s: no startup catch-up sync", "        return this.helixLegacyCatchUpSync(); %s: no startup catch-up sync")], "R7"),
    "M7": ([(P, "    return true; %s: MCP always direct", "    return helixLegacyDaemonOptOutSet(); %s: MCP always direct")], "R11"),
    "M8": ([(P, "        if (!helixOk) {", "        if (false && !helixOk) {")], "R9,R10"),
    "M9": ([("runner_patches/__init__.py", 'OPT_IN = frozenset(["mcpro1"])', "OPT_IN = frozenset([])")], "R13"),
    "M10": ([("runner_patches/__init__.py", 'EXCLUSIVE = frozenset(["mcpro1"])', "EXCLUSIVE = frozenset([])")], "R13"),
}
if len(sys.argv) != 3 or sys.argv[1] not in MUT:
    sys.stderr.write("usage: test_mcp_readonly_mutate.py <%s> <copy-dir>\n" % "|".join(MUT)); sys.exit(2)
edits, expect = MUT[sys.argv[1]]
for rel, old, new in edits:
    path = sys.argv[2].rstrip("/") + "/" + rel
    text = open(path, encoding="utf-8").read()
    if text.count(old) != 1:
        sys.stderr.write("anchor occurs %dx in %s: %r\n" % (text.count(old), rel, old[:60])); sys.exit(2)
    open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
print(expect)
