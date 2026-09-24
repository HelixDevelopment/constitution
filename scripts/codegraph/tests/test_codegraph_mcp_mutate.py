#!/usr/bin/env python3
# test_codegraph_mcp_mutate.py <id> <copy-dir> — apply ONE named mutation to codegraph_mcp.sh in a COPY of the tooling.
# Prints the W-list that must FAIL. Exit 2 on unknown id / anchor not exactly once.
import sys
F = "codegraph_mcp.sh"
NOREC = [(F, 'assert rc.get("patch_set") == ["mcpro1"],', 'assert True or rc.get("patch_set") == ["mcpro1"],'),
         (F, 'assert str(rc.get("runner_key", "")).endswith("-mcpro1"),', 'assert True or str(rc.get("runner_key", "")).endswith("-mcpro1"),'),
         (F, 'assert "helix-mcpro1" in open(os.path.join(d, rel), encoding="utf-8").read(),', 'assert True or "helix-mcpro1" in open(os.path.join(d, rel), encoding="utf-8").read(),'),
         (F, 'assert sha == rc.get("patched_dbjs_sha256"),', 'assert True or sha == rc.get("patched_dbjs_sha256"),')]
MUT = {
    "X1": ([(F, 'if [ "$WRITERS" != "[]" ]; then', 'if false; then')], "W3,W4"),
    "X2": ([(F, 'if lp and lp not in me and os.path.isdir("/proc/%d" % lp):', 'if lp and lp not in me and os.path.isdir("/proc/%d" % lp) and (__import__("time").time() - os.path.getmtime(lock)) < 120:')], "W4"),
    "X3": ([(F, '|| die 5 "cannot provide the read-only runner', '|| RUNNER="$(command -v codegraph)"; true "cannot provide the read-only runner'),
            (F, ')" || die 5 "runner $RDIR is not a valid mcpro1 (read-only) runner: $(head -c 300 "$ERRF" | tr \'\\n\' \' \')"', ')" || true')], "W5"),   # fallback AND no receipt gate (the receipt file's absence alone would mask the fallback)
    "X4": ([(F, '    CODEGRAPH_MCP_TOOLS=explore,node,search,callers,callees,impact,files,status', '    CODEGRAPH_UNUSED_PLACEHOLDER=1')], "W1,W7"),
    "X5": (NOREC, "W8"),
    "X6": ([(F, 'if flags is None or (flags & 3) != 0:', 'if True:')], "W9"),
    "X7": ([(F, '''        *) die 2 "refusing '$1': this entry point only serves MCP read-only (index/sync/init/uninit belong to the writer runner)" ;;''', '        *) shift ;;')], "W6"),
}
if len(sys.argv) != 3 or sys.argv[1] not in MUT:
    sys.stderr.write("usage: test_codegraph_mcp_mutate.py <%s> <copy-dir>\n" % "|".join(MUT)); sys.exit(2)
edits, expect = MUT[sys.argv[1]]
for rel, old, new in edits:
    path = sys.argv[2].rstrip("/") + "/" + rel
    text = open(path, encoding="utf-8").read()
    if text.count(old) != 1:
        sys.stderr.write("anchor occurs %dx in %s: %r\n" % (text.count(old), rel, old[:70])); sys.exit(2)
    open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
print(expect)
