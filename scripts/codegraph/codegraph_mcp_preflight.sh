#!/usr/bin/env bash
# ============================================================================
# codegraph_mcp_preflight.sh — assert the read-only CodeGraph MCP path is wired AND working
# ============================================================================
# Purpose      Answer, with evidence and WITHOUT touching the project's index, "can an agent safely use the codegraph MCP here?":
#                P1 .mcp.json declares a `codegraph` server whose command is the sanctioned codegraph_mcp.sh (a genuine copy of this
#                   tooling; only `serve --mcp [--project DIR]` args) — the stock `codegraph` is NOT read-only and is refused
#                P2 no OTHER server entry launches the stock codegraph — judged by what the entry LAUNCHES (node codegraph.js, bash -c,
#                   npx @colbymchenry/codegraph, env/exec wrappers, shim scripts), never by the command basename or a substring
#                P3 optional settings files carry no stock-codegraph hook/server (`codegraph upgrade` can install a prompt hook); hook
#                   commands and mcpServers entries are classified by launch target like P2
#                P7 user-scope configs ($HOME/.claude.json, $CLAUDE_CONFIG_DIR/.claude.json; top-level mcpServers and projects.*.mcpServers)
#                   launch no stock codegraph and any server named `codegraph` there is the sanctioned wrapper; a present file that is not
#                   valid JSON is a FAIL (it cannot be shown clean). Secrets in args/env/headers never reach the output.
#                P4 the wrapper resolves a receipt-valid mcpro1 runner (builds it into the runner cache if missing)
#                P5 a FIXTURE query answers end-to-end through the wrapper and the server holds the DB read-only (fd modes read from /proc)
#                P6 the real project has an index; a live writer on it is reported as WARN (the wrapper will refuse to start until
#                   it finishes — by design), any other refusal is FAIL
#              The real project is only ever STAT-ed and passed to `codegraph_mcp.sh --dry-run` (which reads /proc + the lock file, never
#              opens the database and never runs codegraph). The fixture (P4/P5) is created in a temp dir with the PRISTINE package.
# Usage        codegraph_mcp_preflight.sh [--project DIR] [--mcp-json FILE] [--settings FILE]...
# Inputs       HELIX_CODEGRAPH_SRC / HELIX_CODEGRAPH_RUNNER_DIR (as the wrapper); HELIX_CODEGRAPH_FIXTURE_BIN (tests: the fixture writer);
#              HOME and CLAUDE_CONFIG_DIR (P7: the user-scope .claude.json files, read-only)
# Outputs      `PREFLIGHT <id> PASS|FAIL|WARN <text>` lines + `SUMMARY fail=N warn=M`; exit 0 = no FAIL, 1 = any FAIL, 2 = usage
# Side effects temp fixture dir (removed on exit); may build the mcpro1 runner into the runner cache; nothing in the project
# Dependencies bash, python3 (stdlib only), git, a pristine codegraph 1.6.x package
# Boundaries   P2/P3/P7 are STATIC: they see what codegraph_launch_class.py can resolve (see its header for the list and for what it
#              cannot see); they do not look at managed/enterprise settings, plugin-provided servers or ~/.claude/settings.json hooks
#              other than files passed with --settings. The runtime proof that the project's own server is read-only is P5.
# Cross-refs   codegraph_mcp.sh, codegraph_mcp_probe.py, codegraph_launch_class.py, fk_index_patch.py, tests/test_codegraph_mcp_preflight.sh,
#              docs/scripts/codegraph_mcp_preflight.md, constitution §11.4.201/.273
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$PWD"; MCPJSON=""; SETTINGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --project) [ $# -ge 2 ] || { echo "usage: --project DIR" >&2; exit 2; }; PROJECT="$2"; shift 2 ;;
        --mcp-json) [ $# -ge 2 ] || { echo "usage: --mcp-json FILE" >&2; exit 2; }; MCPJSON="$2"; shift 2 ;;
        --settings) [ $# -ge 2 ] || { echo "usage: --settings FILE" >&2; exit 2; }; SETTINGS+=("$2"); shift 2 ;;
        -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd -P)" || { echo "project directory not found" >&2; exit 2; }
[ -n "$MCPJSON" ] || MCPJSON="$PROJECT/.mcp.json"
WRAP="$HERE/codegraph_mcp.sh"; PROBE="$HERE/codegraph_mcp_probe.py"
FAILS=0; WARNS=0
say() { echo "PREFLIGHT $1 $2 $3"; [ "$2" = FAIL ] && FAILS=$((FAILS+1)); [ "$2" = WARN ] && WARNS=$((WARNS+1)); return 0; }
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cg_mcp_pf.XXXXXX")"; trap 'rm -rf "$TMPD"' EXIT

# ---- P1/P2 (.mcp.json) and P3 (settings) — parsed, never grepped ---------------------------------
while read -r id st msg; do say "$id" "$st" "$msg"; done < <(python3 -I -B - "$HERE" "$MCPJSON" "$PROJECT" <<'PY'
import json, os, sys
here, mcpjson, project = sys.argv[1:4]
sys.path.insert(0, here)
import codegraph_launch_class as L
rp = os.path.realpath
try:
    d = json.load(open(mcpjson))
except FileNotFoundError:
    print("P1 FAIL no .mcp.json at %s" % mcpjson); print("P2 FAIL no .mcp.json to inspect"); sys.exit(0)
except Exception as e:
    print("P1 FAIL .mcp.json is not valid JSON: %s" % str(e)[:120]); print("P2 FAIL .mcp.json unreadable"); sys.exit(0)
servers = d.get("mcpServers") if isinstance(d, dict) else None
if not isinstance(servers, dict):
    print("P1 FAIL .mcp.json has no mcpServers object"); print("P2 FAIL no mcpServers object"); sys.exit(0)
def script_of(sv):
    cmd, args = sv.get("command"), sv.get("args") or []
    if not isinstance(cmd, str) or not isinstance(args, list) or not all(isinstance(a, str) for a in args):
        return None, None, cmd
    script, rest = cmd, args
    if os.path.basename(cmd) in ("bash", "sh", "env") and args:
        script, rest = args[0], args[1:]
    if not os.path.isabs(script):
        script = os.path.join(project, script)
    return script, rest, cmd
sv = servers.get("codegraph")
if not isinstance(sv, dict):
    print("P1 FAIL 'codegraph' server is not declared in .mcp.json (declared: %s)" % (sorted(servers) or "none"))
else:
    script, rest, cmd = script_of(sv)
    prob = []
    if script is None:
        prob.append("command/args malformed")
    else:
        real = rp(script)
        if os.path.basename(real) != "codegraph_mcp.sh":
            prob.append("command resolves to %s, not codegraph_mcp.sh (the stock codegraph is NOT read-only)" % real)
        elif not os.access(real, os.X_OK):
            prob.append("%s is not executable" % real)
        elif not os.path.isfile(os.path.join(os.path.dirname(real), "fk_index_patch.py")):
            prob.append("%s is not a genuine copy of the tooling (no fk_index_patch.py beside it)" % real)
        i = 0
        while i < len(rest):
            a = rest[i]
            if a in ("serve", "--mcp"): i += 1
            elif a == "--project" and i + 1 < len(rest): i += 2
            elif a.startswith("--project="): i += 1
            else: prob.append("argument %r is not allowed (only: serve --mcp --project DIR)" % a); i += 1
    print("P1 FAIL " + "; ".join(prob) if prob else "P1 PASS 'codegraph' server -> %s" % rp(script))
others = [k for k, v in servers.items() if k != "codegraph" and isinstance(v, dict)]
stock, why = [], []
for k in others:
    v = servers[k]
    kind, detail = L.classify(v.get("command"), v.get("args"), project)   # by what the entry LAUNCHES, never by basename/substring
    if kind == "stock":
        stock.append(k); why.append("%s: %s" % (str(k)[:60].replace("\n", " "), detail))
if stock:
    print("P2 FAIL other server entr%s launch%s the stock codegraph: %s (%s)" % ("ies" if len(stock) > 1 else "y", "" if len(stock) > 1 else "es", stock, "; ".join(why)))
else:
    print("P2 PASS no other server entry launches the stock codegraph (%d other entr%s classified by launch target)" % (len(others), "y" if len(others) == 1 else "ies"))
PY
)   # process substitution, NOT a pipe: a piped `while` runs in a subshell and its FAIL/WARN counts would be lost (measured)
if [ "${#SETTINGS[@]}" -gt 0 ]; then
while read -r id st msg; do say "$id" "$st" "$msg"; done < <(python3 -I -B - "$HERE" "$PROJECT" "${SETTINGS[@]}" <<'PY'
import json, os, sys
here, project = sys.argv[1:3]
sys.path.insert(0, here)
import codegraph_launch_class as L
bad = []
def hook_commands(o):          # the `command` values of the hook handlers — what a shell would run
    if isinstance(o, dict):
        c = o.get("command")
        if isinstance(c, str): yield c
        for v in o.values(): yield from hook_commands(v)
    elif isinstance(o, list):
        for v in o: yield from hook_commands(v)
for p in sys.argv[3:]:
    try:
        d = json.load(open(p))
    except FileNotFoundError:
        continue
    except Exception as e:
        bad.append("%s unreadable (%s)" % (p, type(e).__name__)); continue
    for c in hook_commands(d.get("hooks", {}) if isinstance(d, dict) else {}):
        kind, detail = L.classify_shell(c, project)
        if kind == "stock":
            bad.append("%s: hook runs the stock codegraph (%s)" % (p, detail))
    ms = d.get("mcpServers", {}) if isinstance(d, dict) else {}
    for k, v in (ms.items() if isinstance(ms, dict) else []):
        if isinstance(v, dict):
            kind, detail = L.classify(v.get("command"), v.get("args"), project)
            if kind == "stock":
                bad.append("%s: mcpServers.%s launches the stock codegraph (%s)" % (p, str(k)[:60].replace("\n", " "), detail))
print("P3 FAIL " + "; ".join(bad) if bad else "P3 PASS settings carry no stock-codegraph hook/server")
PY
)
fi

# ---- P7 (user-scope configs: $HOME/.claude.json, $CLAUDE_CONFIG_DIR/.claude.json — read-only, parsed, never grepped) ----
# A stock `codegraph serve --mcp` declared at USER scope reaches every project's session and takes the database for writing (the
# measured stall that the sanctioned wrapper exists to avoid), so it is checked here although it is not part of the project's files.
while read -r id st msg; do say "$id" "$st" "$msg"; done < <(python3 -I -B - "$HERE" "$PROJECT" <<'PY'
import json, os, sys
here, project = sys.argv[1:3]
sys.path.insert(0, here)
import codegraph_launch_class as L
files, seen = [], set()
for base in (os.environ.get("HOME") or "", os.environ.get("CLAUDE_CONFIG_DIR") or ""):
    if not base:
        continue
    p = os.path.join(base, ".claude.json")
    real = os.path.realpath(p)
    if real in seen or not os.path.lexists(p):
        continue
    seen.add(real); files.append(p)
def nm(s):
    return str(s)[:60].replace("\n", " ")
def servers_of(d):
    if not isinstance(d, dict):
        return
    ms = d.get("mcpServers")
    if isinstance(ms, dict):
        for k, v in ms.items():
            yield "mcpServers", project, k, v
    pr = d.get("projects")
    if isinstance(pr, dict):
        for pk, pv in pr.items():
            if isinstance(pv, dict) and isinstance(pv.get("mcpServers"), dict):
                for k, v in pv["mcpServers"].items():
                    yield "projects[%s].mcpServers" % nm(pk), (pk if isinstance(pk, str) and os.path.isabs(pk) else project), k, v
bad, inspected = [], 0
for p in files:
    try:
        with open(p, "rb") as fh:
            d = json.loads(fh.read().decode("utf-8"))
    except json.JSONDecodeError as e:
        bad.append("%s is not valid JSON (%s at line %d column %d) — it cannot be shown clean" % (p, e.msg, e.lineno, e.colno)); continue
    except Exception as e:
        bad.append("%s is unreadable (%s) — it cannot be shown clean" % (p, type(e).__name__)); continue
    for scope, base, name, v in servers_of(d):
        inspected += 1
        if isinstance(v, dict):
            kind, detail = L.classify(v.get("command"), v.get("args"), base)
        else:
            kind, detail = "other", "entry is not an object"
        if kind == "stock":
            bad.append("%s: %s server '%s' launches the stock codegraph, which opens the index for writing (%s)" % (p, scope, nm(name), detail))
        elif name == "codegraph" and kind != "wrapper":
            bad.append("%s: %s server 'codegraph' is not the sanctioned codegraph_mcp.sh wrapper (%s)" % (p, scope, detail))
if bad:
    print("P7 FAIL " + "; ".join(bad))
elif not files:
    print("P7 PASS no user-scope .claude.json present (HOME and CLAUDE_CONFIG_DIR checked) — nothing to inspect")
else:
    print("P7 PASS user-scope config%s inspected (%d file%s, %d server entr%s): none launches the stock codegraph" % (
        "s" if len(files) > 1 else "", len(files), "" if len(files) == 1 else "s", inspected, "y" if inspected == 1 else "ies"))
PY
)

# ---- P4/P5 (fixture, never the project) -----------------------------------------------------------
SRC="${HELIX_CODEGRAPH_SRC:-$(cd "$HERE" && python3 -c 'import fk_index_patch as m; print(m.default_src())' 2>/dev/null)}"
FIXBIN="${HELIX_CODEGRAPH_FIXTURE_BIN:-$SRC/bin/codegraph}"
FX="$TMPD/fx"; mkdir -p "$FX/src"
printf 'def compute_total(items):\n    return sum(price_of(i) for i in items)\n\ndef price_of(item):\n    return item.get("price", 0)\n' > "$FX/src/alpha.py"
( cd "$FX" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm fixture ) >/dev/null 2>&1
if [ -x "$FIXBIN" ] && CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 "$FIXBIN" init -y "$FX" >"$TMPD/init.log" 2>&1; then
    FXOK=1
else
    FXOK=0; say P5 FAIL "fixture could not be created with $FIXBIN (init failed: $(head -c 120 "$TMPD/init.log" 2>/dev/null | tr '\n' ' '))"
fi
if [ "$FXOK" -eq 1 ]; then
    DOUT="$("$WRAP" --project "$FX" --dry-run 2>"$TMPD/dry.err")"; DRC=$?
    KEY="$(printf '%s' "$DOUT" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["runner_key"])' 2>/dev/null)"
    if [ "$DRC" -eq 0 ] && case "$KEY" in *-mcpro1) true ;; *) false ;; esac; then
        say P4 PASS "wrapper resolves a receipt-valid mcpro1 runner ($KEY)"
    else
        say P4 FAIL "wrapper cannot provide a valid mcpro1 runner (rc=$DRC): $(head -c 200 "$TMPD/dry.err" | tr '\n' ' ')"
    fi
    PJ="$(python3 "$PROBE" --bin "$WRAP" --project "$FX" --stderr-file "$TMPD/probe.err" --query compute_total 2>/dev/null)"; PRC=$?
    if python3 - "$PJ" 2>"$TMPD/p5.err" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d.get("init_ok") and d.get("calls_ok", 0) >= 1, ("session did not answer", d.get("error"))
modes = d.get("db_fd_modes") or []
assert modes and all(str(m) == "r" for m in modes), ("db fd modes must be all read-only", modes)
PY
    then say P5 PASS "fixture query answered through the wrapper; server holds the database read-only"
    else say P5 FAIL "fixture session failed (probe rc=$PRC): $(tail -1 "$TMPD/p5.err" | head -c 200) json=$(printf '%s' "$PJ" | head -c 160)"; fi
fi

# ---- P6 (real project: stat + wrapper --dry-run only) ----------------------------------------------
if [ -f "$PROJECT/.codegraph/codegraph.db" ]; then
    "$WRAP" --project "$PROJECT" --dry-run >/dev/null 2>"$TMPD/real.err"; RRC=$?
    case "$RRC" in
        0) say P6 PASS "index present, no live writer, runner valid — the server would start" ;;
        4) say P6 WARN "live writer on the project index — the server refuses to start until it finishes (by design): $(head -c 220 "$TMPD/real.err" | tr '\n' ' ')" ;;
        *) say P6 FAIL "wrapper refuses the real project (rc=$RRC): $(head -c 220 "$TMPD/real.err" | tr '\n' ' ')" ;;
    esac
else
    say P6 FAIL "no CodeGraph index at $PROJECT/.codegraph/codegraph.db"
fi
echo "SUMMARY fail=$FAILS warn=$WARNS"
[ "$FAILS" -eq 0 ]
