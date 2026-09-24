#!/usr/bin/env python3
# test_codegraph_mcp_preflight_mutate.py <id> <copy-dir> — apply ONE named mutation to codegraph_mcp_preflight.sh in a COPY.
# Prints the F-list that must FAIL. Exit 2 on unknown id / anchor not exactly once.
import sys
F = "codegraph_mcp_preflight.sh"
MUT = {
    "Y1": ([(F, 'if os.path.basename(real) != "codegraph_mcp.sh":', 'if False:')], "F2"),
    "Y2": ([(F, 'if "codegraph" in s.lower() and "codegraph_mcp" not in s.lower():', 'if False:')], "F5"),
    "Y3": ([(F, 'assert d.get("init_ok") and d.get("calls_ok", 0) >= 1, ("session did not answer", d.get("error"))', 'pass'),
            (F, 'assert modes and all(str(m) == "r" for m in modes), ("db fd modes must be all read-only", modes)', 'pass')], "F11"),
    "Y4": ([(F, 'else: prob.append("argument %r is not allowed (only: serve --mcp --project DIR)" % a); i += 1', 'else: i += 1')], "F4"),
    "Y5": ([(F, 'if "codegraph" in names:', 'if False:')], "F9"),
    "Y6": ([(F, '4) say P6 WARN', '4) say P6 FAIL')], "F7"),
}
if len(sys.argv) != 3 or sys.argv[1] not in MUT:
    sys.stderr.write("usage: test_codegraph_mcp_preflight_mutate.py <%s> <copy-dir>\n" % "|".join(MUT)); sys.exit(2)
edits, expect = MUT[sys.argv[1]]
for rel, old, new in edits:
    path = sys.argv[2].rstrip("/") + "/" + rel
    text = open(path, encoding="utf-8").read()
    if text.count(old) != 1:
        sys.stderr.write("anchor occurs %dx in %s: %r\n" % (text.count(old), rel, old[:70])); sys.exit(2)
    open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
print(expect)
