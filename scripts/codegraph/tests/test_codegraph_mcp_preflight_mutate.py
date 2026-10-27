#!/usr/bin/env python3
# test_codegraph_mcp_preflight_mutate.py <id> <copy-dir> — apply ONE named mutation to the preflight (or the launch-target classifier) in a COPY.
# Prints the F-list that must FAIL. Exit 2 on unknown id / anchor not exactly once.
#   Y1-Y6   original holes (P1 basename check, P3 hook check, P5 read-only proof, P1 argv allow-list, P2 stock detection, P6 WARN->FAIL)
#   Y7-Y11  P7 holes: top-level scan, projects scan, invalid-JSON-as-clean, non-wrapper `codegraph` accepted, secret echoed
#   Y12     classifier too broad (substring over argv) => the mention-only entries are refused (F15 is the over-correction guard)
#   Y13-Y17 classifier too narrow: shell -c, wrapper peeling, node scripts, package runners, shim scripts
#   Y18     classifier termination guards removed (cycle + depth) => a shim cycle crashes the check
#   Y19-Y21 classifier edge cases: here-document skipping, comment skipping, not-on-disk codegraph.js
#   Y22-Y23 P3 settings mcpServers check, genuine-wrapper recognition
import sys
F = "codegraph_mcp_preflight.sh"
C = "codegraph_launch_class.py"
MUT = {
    "Y1": ([(F, 'if os.path.basename(real) != "codegraph_mcp.sh":', 'if False:')], "F2"),
    "Y2": ([(F, 'bad.append("%s: hook runs the stock codegraph (%s)" % (p, detail))', 'pass')], "F5,F18"),
    "Y3": ([(F, 'assert d.get("init_ok") and d.get("calls_ok", 0) >= 1, ("session did not answer", d.get("error"))', 'pass'),
            (F, 'assert modes and all(str(m) == "r" for m in modes), ("db fd modes must be all read-only", modes)', 'pass')], "F11"),
    "Y4": ([(F, 'else: prob.append("argument %r is not allowed (only: serve --mcp --project DIR)" % a); i += 1', 'else: i += 1')], "F4"),
    "Y5": ([(F, 'stock.append(k); why.append("%s: %s" % (str(k)[:60].replace("\\n", " "), detail))', 'pass')], "F9,F14"),
    "Y6": ([(F, '4) say P6 WARN', '4) say P6 FAIL')], "F7"),
    "Y7": ([(F, '            yield "mcpServers", project, k, v', '            pass')], "F13,F17"),
    "Y8": ([(F, '                    yield "projects[%s].mcpServers" % nm(pk), (pk if isinstance(pk, str) and os.path.isabs(pk) else project), k, v',
                '                    pass')], "F13"),
    "Y9": ([(F, '        bad.append("%s is not valid JSON (%s at line %d column %d) — it cannot be shown clean" % (p, e.msg, e.lineno, e.colno)); continue',
                '        continue')], "F13"),
    "Y10": ([(F, '        elif name == "codegraph" and kind != "wrapper":', '        elif False:')], "F17"),
    "Y11": ([(F, 'launches the stock codegraph, which opens the index for writing (%s)" % (p, scope, nm(name), detail))',
                 'launches the stock codegraph, which opens the index for writing (%s %s)" % (p, scope, nm(name), detail, json.dumps(v)))')], "F13"),
    "Y12": ([(C, '    if base in STOCK_NAMES:', '    if "codegraph" in " ".join(argv):')], "F15"),
    "Y13": ([(C, '                if "c" in a[1:] and i + 1 < len(args):', '                if False and i + 1 < len(args):')], "F14,F17"),
    "Y14": ([(C, '    while argv and os.path.basename(argv[0]) in WRAPPERS:', '    while False:')], "F14,F16"),
    "Y15": ([(C, '    if NODE_RE.match(base):', '    if False:')], "F14,F16"),
    "Y16": ([(C, '    if base in NPX_RUNNERS:', '    if False:')], "F14"),
    "Y17": ([(C, '    if as_shell or _shebang_interp(data) in SHELLS:', '    if as_shell:')], "F14,F18"),
    "Y18": ([(C, '    if real in ctx["seen"]:', '    if False:'), (C, '    if ctx["depth"] >= MAX_DEPTH:', '    if False:')], "F15"),
    "Y19": ([(C, '                heredocs.append((delim, strip))', '                pass')], "F18"),
    "Y20": ([(C, '        if c == "#" and cur is None:', '        if False:')], "F18"),
    "Y21": ([(C, '        if os.path.basename(path) in STOCK_NAMES:', '        if False:')], "F18"),
    "Y22": ([(F, '                bad.append("%s: mcpServers.%s launches the stock codegraph (%s)" % (p, str(k)[:60].replace("\\n", " "), detail))',
                 '                pass')], "F16"),
    "Y23": ([(C, '    if rb == WRAPPER_NAME and os.path.isfile(os.path.join(os.path.dirname(real), WRAPPER_SIBLING)):', '    if False:')], "F13"),
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
