#!/usr/bin/env python3
# ============================================================================
# test_codegraph_launch_class.py — unit tests for codegraph_launch_class.py (the launch-target classifier)
# ============================================================================
# Purpose      Prove the classifier names what an MCP entry LAUNCHES: stock codegraph shapes => "stock", the sanctioned wrapper => "wrapper",
#              everything that merely MENTIONS codegraph (or launches something else) => "other", malformed input never raises, and the
#              walk terminates on cycles. Every case is a table row: (id, description, command, args, expected kind).
# Usage        python3 test_codegraph_launch_class.py            (CG_DIR overrides the directory holding the module; TMPDIR is honoured)
# Outputs      `RESULT <id> PASS|FAIL <description>` lines + `SUMMARY cases=N failed=M`; exit 1 on any failure
# Side effects temp tree under $TMPDIR (removed on exit); nothing else
# Cross-refs   ../codegraph_launch_class.py, test_codegraph_mcp_preflight.sh (F13-F18 drive it through the preflight), constitution §11.4.201/.224/.273
# ============================================================================
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CG_DIR = os.environ.get("CG_DIR") or os.path.dirname(HERE)
sys.path.insert(0, CG_DIR)
import codegraph_launch_class as L   # noqa: E402

W = tempfile.mkdtemp(prefix="cg_launch_class.", dir=os.environ.get("TMPDIR") or None)


def mk(rel, text="", mode=0o755):
    p = os.path.join(W, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as fh:
        fh.write(text)
    os.chmod(p, mode)
    return p


# a faithful miniature of the stock package: package.json name + the bin script + another file inside the package
PKG = os.path.join(W, "pkg")
mk("pkg/package.json", '{"name": "@colbymchenry/codegraph", "version": "1.6.2"}\n', 0o644)
STOCK_JS = mk("pkg/lib/dist/bin/codegraph.js", "// stock\n")
STOCK_INNER = mk("pkg/lib/dist/server.js", "// inside the stock package\n")
os.makedirs(os.path.join(W, "ln"), exist_ok=True)
os.symlink(STOCK_JS, os.path.join(W, "ln", "cg_link"))
# the sanctioned wrapper: a file named codegraph_mcp.sh with fk_index_patch.py beside it (genuine) / without (fake)
GOOD_WRAP = mk("tool/codegraph_mcp.sh", "#!/bin/sh\nexec true\n")
mk("tool/fk_index_patch.py", "# marker\n", 0o644)
FAKE_WRAP = mk("fake/codegraph_mcp.sh", "#!/bin/sh\nexec true\n")
# shims
SH_EXEC = mk("shim/exec_cg", "#!/bin/sh\nexec codegraph serve --mcp \"$@\"\n")
SH_ENV = mk("shim/exec_cg_env", "#!/usr/bin/env bash\nset -e\ncodegraph serve --mcp\n")
SH_NESTED = mk("shim/outer", "#!/bin/sh\nexec %s \"$@\"\n" % SH_EXEC)
SH_PLAIN = mk("shim/plain", "#!/bin/sh\necho hello\n")
SH_PROBE = mk("shim/probe", "#!/bin/sh\nif command -v codegraph >/dev/null 2>&1; then echo have; fi\ntype codegraph || true\nwhich codegraph\n")
SH_CYC_A = mk("shim/cyc_a", "#!/bin/sh\nexec %s/shim/cyc_b \"$@\"\n" % W)
SH_CYC_B = mk("shim/cyc_b", "#!/bin/sh\nexec %s/shim/cyc_a \"$@\"\n" % W)
PY_SCRIPT = mk("shim/py_tool", "#!/usr/bin/env python3\nprint('codegraph serve')\n")
BIG = mk("shim/big", "#!/bin/sh\n" + "# pad\n" * 60000 + "exec codegraph serve\n")
SHELL_FILE = mk("shim/as_arg.sh", "codegraph serve --mcp\n", 0o644)           # no shebang: only a shell invocation runs it as shell
# 8 nested env wrappers around codegraph: wrapper peeling is not depth-limited
ENV8 = ["env"] * 8 + ["codegraph", "serve"]

CASES = [
    # ---- stock: direct names, absolute paths, symlinks, absent targets -------------------------------------------------
    ("S01", "bare codegraph", "codegraph", ["serve", "--mcp"], "stock"),
    ("S02", "absolute path to a codegraph binary name", "/usr/local/bin/codegraph", ["serve"], "stock"),
    ("S03", "codegraph.js named directly", "/nonexistent/x/codegraph.js", [], "stock"),
    ("S04", "symlink resolving to codegraph.js", os.path.join(W, "ln", "cg_link"), [], "stock"),
    # ---- stock: transparent wrappers -----------------------------------------------------------------------------------
    ("S10", "env VAR=1", "env", ["A=1", "codegraph", "serve"], "stock"),
    ("S11", "env -u NAME VAR=1", "env", ["-u", "FOO", "A=1", "codegraph"], "stock"),
    ("S12", "env -S 'string'", "env", ["-S", "codegraph serve --mcp"], "stock"),
    ("S13", "env --split-string=...", "env", ["--split-string=codegraph serve"], "stock"),
    ("S14", "exec", "exec", ["codegraph", "serve"], "stock"),
    ("S15", "nohup", "nohup", ["codegraph", "serve"], "stock"),
    ("S16", "timeout DURATION", "timeout", ["5", "codegraph", "serve"], "stock"),
    ("S17", "timeout -s SIG -k T DURATION", "timeout", ["-s", "KILL", "-k", "2", "5", "codegraph", "serve"], "stock"),
    ("S18", "nice -n 5", "nice", ["-n", "5", "codegraph"], "stock"),
    ("S19", "sudo -u USER", "sudo", ["-u", "bob", "codegraph", "serve"], "stock"),
    ("S1A", "eight nested env wrappers (peeling is not depth-limited)", ENV8[0], ENV8[1:], "stock"),
    ("S1B", "stdbuf -oL", "stdbuf", ["-oL", "codegraph"], "stock"),
    # ---- stock: shell -c strings ----------------------------------------------------------------------------------------
    ("S20", "bash -c plain", "bash", ["-c", "codegraph serve"], "stock"),
    ("S21", "sh -lc exec", "sh", ["-lc", "exec codegraph serve --mcp"], "stock"),
    ("S22", "bash -c with VAR=val prefix", "bash", ["-c", "FOO=1 codegraph serve"], "stock"),
    ("S23", "bash -c after cd &&", "bash", ["-c", "cd /x && codegraph serve"], "stock"),
    ("S24", "bash -c in a pipeline", "bash", ["-c", "echo hi | codegraph serve"], "stock"),
    ("S25", "bash -c in a subshell", "bash", ["-c", "(codegraph serve)"], "stock"),
    ("S26", "bash -c inside if/then", "bash", ["-c", "if true; then codegraph serve; fi"], "stock"),
    ("S27", "bash -c after a here-document", "bash", ["-c", "cat <<EOF\nx\nEOF\ncodegraph serve"], "stock"),
    ("S28", "bash -c after a redirection", "bash", ["-c", "echo a >out 2>&1; codegraph serve"], "stock"),
    ("S29", "bash -c with env wrapper inside", "bash", ["-c", "env A=1 nohup codegraph serve"], "stock"),
    ("S2A", "dash script path run through a shell (file without shebang)", "bash", [SHELL_FILE], "stock"),
    # ---- stock: node / bun scripts -------------------------------------------------------------------------------------
    ("S30", "node codegraph.js", "node", [STOCK_JS, "serve"], "stock"),
    ("S31", "node script inside the stock package", "node", [STOCK_INNER], "stock"),
    ("S32", "node -r PRELOAD codegraph.js", "node", ["-r", "./pre.js", STOCK_JS], "stock"),
    ("S33", "node --require PRELOAD codegraph.js", "node", ["--require", "./pre.js", "/nonexistent/codegraph.js"], "stock"),
    ("S34", "node20 codegraph.js", "node20", [STOCK_JS], "stock"),
    ("S35", "nodejs codegraph.js", "nodejs", [STOCK_JS], "stock"),
    ("S36", "bun codegraph.js", "bun", [STOCK_JS], "stock"),
    # ---- stock: package runners ----------------------------------------------------------------------------------------
    ("S40", "npx -y @colbymchenry/codegraph", "npx", ["-y", "@colbymchenry/codegraph", "serve", "--mcp"], "stock"),
    ("S41", "npx with a version suffix", "npx", ["@colbymchenry/codegraph@1.6.2", "serve"], "stock"),
    ("S42", "npx --package=...", "npx", ["--package=@colbymchenry/codegraph", "codegraph", "serve"], "stock"),
    ("S43", "npx -p ...", "npx", ["-p", "@colbymchenry/codegraph", "codegraph"], "stock"),
    ("S44", "npx -c 'codegraph serve'", "npx", ["-c", "codegraph serve"], "stock"),
    ("S45", "npm exec", "npm", ["exec", "@colbymchenry/codegraph"], "stock"),
    ("S46", "pnpm dlx", "pnpm", ["dlx", "@colbymchenry/codegraph"], "stock"),
    ("S47", "yarn dlx", "yarn", ["dlx", "@colbymchenry/codegraph"], "stock"),
    ("S48", "bunx", "bunx", ["@colbymchenry/codegraph"], "stock"),
    ("S49", "bun x", "bun", ["x", "@colbymchenry/codegraph"], "stock"),
    ("S4A", "pnpx", "pnpx", ["@colbymchenry/codegraph"], "stock"),
    ("S4B", "npx codegraph (bare bin name: refused as the conservative default, UNCONFIRMED which npm package it names)", "npx", ["codegraph", "serve"], "stock"),
    # ---- stock: shim scripts -------------------------------------------------------------------------------------------
    ("S50", "sh shim that execs codegraph", SH_EXEC, [], "stock"),
    ("S51", "env-bash shim with set -e", SH_ENV, [], "stock"),
    ("S52", "shim that execs another shim that execs codegraph", SH_NESTED, [], "stock"),
    # ---- wrapper -------------------------------------------------------------------------------------------------------
    ("W01", "genuine codegraph_mcp.sh", GOOD_WRAP, ["serve", "--mcp"], "wrapper"),
    ("W02", "genuine codegraph_mcp.sh behind env", "env", ["A=1", GOOD_WRAP, "serve"], "wrapper"),
    ("W03", "genuine codegraph_mcp.sh behind bash", "bash", [GOOD_WRAP, "serve"], "wrapper"),
    ("W04", "codegraph_mcp.sh without fk_index_patch.py beside it is NOT the wrapper", FAKE_WRAP, ["serve"], "other"),
    # ---- other: mentions, other launches, lookups ------------------------------------------------------------------------
    ("O01", "echo", "echo", ["hi"], "other"),
    ("O02", "unrelated node server", "node", ["/opt/other/server.js"], "other"),
    ("O03", "node codegraph-viewer.js (name contains codegraph)", "node", ["/opt/other/codegraph-viewer.js"], "other"),
    ("O04", "npx @other/codegraph-ui", "npx", ["-y", "@other/codegraph-ui", "serve"], "other"),
    ("O05", "npx @colbymchenry/other", "npx", ["@colbymchenry/other"], "other"),
    ("O06", "bash -c grep codegraph", "bash", ["-c", "grep codegraph /var/log/x; echo codegraph"], "other"),
    ("O07", "bash -c echo of a quoted string", "bash", ["-c", 'echo "codegraph serve"'], "other"),
    ("O08", "env with a VALUE mentioning codegraph", "env", ["CODEGRAPH_NOTE=codegraph", "/opt/other/server"], "other"),
    ("O09", "bash -c here-document body is data", "bash", ["-c", "cat <<EOF\ncodegraph serve\nEOF"], "other"),
    ("O0A", "bash -c here-doc <<- with quoted delimiter and tab-indented end", "bash", ["-c", "cat <<-'EOF'\n\tcodegraph serve\n\tEOF\necho done"], "other"),
    ("O0B", "bash -c here-string is data", "bash", ["-c", "cat <<< codegraph"], "other"),
    ("O0C", "bash -c comment mention", "bash", ["-c", "echo hi # codegraph serve; codegraph"], "other"),
    ("O0D", "bash -c variable assignment only", "bash", ["-c", "x=codegraph"], "other"),
    ("O0E", "command -v codegraph is a lookup", "bash", ["-c", "command -v codegraph"], "other"),
    ("O0F", "shim whose body only looks codegraph up (command -v / type / which)", SH_PROBE, [], "other"),
    ("O10", "shim without codegraph", SH_PLAIN, [], "other"),
    ("O11", "shim cycle terminates", SH_CYC_A, [], "other"),
    ("O12", "non-shell script (python) is not read as shell", PY_SCRIPT, [], "other"),
    ("O13", "shim larger than the read cap is not read (documented boundary)", BIG, [], "other"),
    ("O14", "missing target that is not named codegraph", "/nonexistent/server", [], "other"),
    ("O15", "directory as command", W, [], "other"),
    ("O16", "env with nothing to run", "env", ["A=1"], "other"),
    ("O17", "timeout with nothing to run", "timeout", ["5"], "other"),
    # ---- malformed input never raises ---------------------------------------------------------------------------------
    ("M01", "command is an int", 7, [], "other"),
    ("M02", "command is None", None, [], "other"),
    ("M03", "command is empty", "", [], "other"),
    ("M04", "args is a string", "bash", "-c codegraph", "other"),
    ("M05", "args holds a non-string", "bash", ["-c", 5], "other"),
    ("M06", "args is None", "echo", None, "other"),
    ("M07", "unbalanced quote in -c string", "bash", ["-c", "echo 'codegraph"], "other"),
    ("M08", "bash -c with no string", "bash", ["-c"], "other"),
]

fails = 0
for cid, desc, cmd, args, want in CASES:
    try:
        kind, detail = L.classify(cmd, args, W)
        ok = (kind == want)
        note = "" if ok else " (got %s: %s)" % (kind, detail)
    except Exception as e:  # a raise is a failure of the never-raises contract
        ok, note = False, " (raised %s: %s)" % (type(e).__name__, str(e)[:80])
    fails += 0 if ok else 1
    print("RESULT %s %s %s%s" % (cid, "PASS" if ok else "FAIL", desc, note))

# classify_shell (settings-file hook command strings)
for cid, desc, text, want in [
    ("H01", "hook: absolute-path codegraph", "/opt/cg/bin/codegraph prompt-hook", "stock"),
    ("H02", "hook: echo mentioning codegraph", 'echo "see the codegraph docs"', "other"),
    ("H03", "hook: wrapper", "%s serve --mcp" % GOOD_WRAP, "wrapper"),
    ("H04", "hook: empty", "   ", "other"),
]:
    kind, detail = L.classify_shell(text, W)
    ok = (kind == want)
    fails += 0 if ok else 1
    print("RESULT %s %s %s%s" % (cid, "PASS" if ok else "FAIL", desc, "" if ok else " (got %s: %s)" % (kind, detail)))

# the detail text never carries an argument/env value (a secret passed as an argument must not reach a report)
SECRET = "SECRETNEEDLE_ARG_789"
leaks = []
for cmd, args in [("codegraph", ["serve", "--api-key", SECRET]), ("env", ["TOKEN=" + SECRET, "codegraph"]),
                  ("bash", ["-c", "TOKEN=%s codegraph serve --key %s" % (SECRET, SECRET)]), ("node", [STOCK_JS, "--token", SECRET]),
                  ("npx", ["@colbymchenry/codegraph", "--token=" + SECRET])]:
    kind, detail = L.classify(cmd, args, W)
    if kind != "stock" or SECRET in detail:
        leaks.append((cmd, kind, detail))
ok = not leaks
fails += 0 if ok else 1
print("RESULT D01 %s detail text never carries an argument/env value and each secret-bearing entry is still classified stock%s" % ("PASS" if ok else "FAIL", "" if ok else " %r" % leaks))

# CLI contract
import subprocess  # noqa: E402
r = subprocess.run([sys.executable, "-I", "-B", os.path.join(CG_DIR, "codegraph_launch_class.py"), "--", "env", "A=1", "codegraph", "serve"], capture_output=True, text=True)
ok = r.returncode == 0 and r.stdout.startswith("stock\t")
fails += 0 if ok else 1
print("RESULT C01 %s CLI prints '<kind>\\t<detail>' and exits 0 (rc=%s out=%r)" % ("PASS" if ok else "FAIL", r.returncode, r.stdout[:60]))
r = subprocess.run([sys.executable, "-I", "-B", os.path.join(CG_DIR, "codegraph_launch_class.py")], capture_output=True, text=True)
ok = r.returncode == 2
fails += 0 if ok else 1
print("RESULT C02 %s CLI without a command exits 2 (rc=%s)" % ("PASS" if ok else "FAIL", r.returncode))

shutil.rmtree(W, ignore_errors=True)
print("SUMMARY cases=%d failed=%d" % (len(CASES) + 4 + 1 + 2, fails))
sys.exit(1 if fails else 0)
