#!/usr/bin/env bash
# ============================================================================
# codegraph_mcp.sh — the ONLY sanctioned entry point for a CodeGraph MCP server
# ============================================================================
# Purpose      Start a READ-ONLY CodeGraph MCP server for one project so any agent/subagent can
#              query the index without any chance of mutating it. Stock `codegraph serve --mcp`
#              is NOT read-only (startup catch-up sync, heal-on-open DDL, 2-minute stale-lock
#              theft, detached daemon) — see runner_patches/mcpro1.py. This wrapper therefore:
#                1. serves ONLY via the mcpro1 runner (built/verified from a receipt), never the
#                   `codegraph` found on PATH and never any other runner;
#                2. refuses to start while a LIVE WRITER exists on the project's database — decided
#                   by REAL evidence (a process holding codegraph.db open for writing, or the
#                   lock file's PID alive with a codegraph command line read from /proc), never by
#                   lock-file age (§11.4.201: a lock older than 2 min is not proof of a dead writer);
#                3. pins the environment (no daemon/watcher/update-check/telemetry/prompt-hook, query
#                   pool off, the full 8-tool set exposed) and execs the server (stdout = MCP channel).
# Usage        codegraph_mcp.sh [--project DIR] [--dry-run] [serve] [--mcp]
#                --project DIR   project root holding .codegraph/codegraph.db (default: $CODEGRAPH_MCP_PROJECT, then $PWD)
#                --dry-run       do every check, print one JSON verdict line + the ENV/EXEC plan, do NOT exec
#              `serve --mcp` are accepted (so an MCP client may declare  command=codegraph_mcp.sh args=[serve,--mcp]);
#              any other argument (index/sync/init/...) is refused (exit 2).
# Inputs       HELIX_CODEGRAPH_RUNNER_DIR  runner cache (builder default: ~/.cache/helix/codegraph_runner)
#              HELIX_CODEGRAPH_SRC         pristine package to build the runner from (default: the installed one)
#              HELIX_CODEGRAPH_MCP_RUNNER  pin an explicit runner bin (its receipt is STILL verified: must be exactly mcpro1)
# Outputs      stdout: only the MCP JSON-RPC stream (or the --dry-run plan); refusals go to stderr.
#              Exit: 0 ok / 2 usage / 3 no index / 4 live writer / 5 runner missing or not a valid mcpro1 runner
# Side effects builds the mcpro1 runner into the runner cache the first time (never touches the project);
#              NEVER writes inside the project's .codegraph/.
# Dependencies bash, python3, a codegraph 1.6.x package (only to BUILD the runner)
# Cross-refs   fk_index_patch.py --patches mcpro1, runner_patches/mcpro1.py, codegraph_mcp_preflight.sh,
#              tests/test_codegraph_mcp.sh, constitution §11.4.201 / §11.4.196(D) / §11.4.273
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { local rc="$1"; shift; echo "codegraph_mcp: $*" >&2; exit "$rc"; }   # never write to stdout: it is the MCP channel

PROJECT="${CODEGRAPH_MCP_PROJECT:-}"; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --project) [ $# -ge 2 ] || die 2 "--project needs a directory"; PROJECT="$2"; shift 2 ;;
        --project=*) PROJECT="${1#--project=}"; shift ;;
        --dry-run) DRY=1; shift ;;
        serve|--mcp) shift ;;
        -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die 2 "refusing '$1': this entry point only serves MCP read-only (index/sync/init/uninit belong to the writer runner)" ;;
    esac
done
[ -n "$PROJECT" ] || PROJECT="$PWD"
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd -P)" || die 3 "project directory not found"
DB="$PROJECT/.codegraph/codegraph.db"
[ -f "$DB" ] || die 3 "no CodeGraph index at $DB (the read-only server never creates one)"

# ---- runner: mcpro1 only, receipt-verified, never the PATH stock binary --------------------------
ERRF="$(mktemp "${TMPDIR:-/tmp}/cg_mcp_err.XXXXXX")"; trap 'rm -f "$ERRF"' EXIT
if [ -n "${HELIX_CODEGRAPH_MCP_RUNNER:-}" ]; then
    RUNNER="$HELIX_CODEGRAPH_MCP_RUNNER"
else
    BARGS=(--patches mcpro1 --print-bin); [ -n "${HELIX_CODEGRAPH_SRC:-}" ] && BARGS+=(--src "$HELIX_CODEGRAPH_SRC")
    RUNNER="$(python3 "$HERE/fk_index_patch.py" "${BARGS[@]}" 2>"$ERRF")" || die 5 "cannot provide the read-only runner (no fallback to the PATH codegraph): $(head -c 300 "$ERRF" | tr '\n' ' ')"
fi
[ -x "$RUNNER" ] || die 5 "runner not executable: $RUNNER"
RDIR="$(cd "$(dirname "$RUNNER")/.." 2>/dev/null && pwd -P)" || die 5 "runner directory unresolvable: $RUNNER"
RKEY="$(python3 - "$RDIR" 2>"$ERRF" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
rc = json.load(open(os.path.join(d, "RUNNER_RECEIPT.json")))
assert rc.get("patch_set") == ["mcpro1"], "patch_set is %r, not exactly ['mcpro1']" % (rc.get("patch_set"),)
assert str(rc.get("runner_key", "")).endswith("-mcpro1"), "runner_key %r" % (rc.get("runner_key"),)
for rel in ("lib/dist/db/index.js", "lib/dist/utils.js", "lib/dist/mcp/engine.js", "lib/dist/mcp/index.js", "lib/dist/bin/codegraph.js"):
    assert "helix-mcpro1" in open(os.path.join(d, rel), encoding="utf-8").read(), "%s lacks the mcpro1 marker" % rel
sha = hashlib.sha256(open(os.path.join(d, "lib/dist/db/index.js"), "rb").read()).hexdigest()
assert sha == rc.get("patched_dbjs_sha256"), "db/index.js changed since the receipt was written"
print(rc["runner_key"])
PY
)" || die 5 "runner $RDIR is not a valid mcpro1 (read-only) runner: $(head -c 300 "$ERRF" | tr '\n' ' ')"

# ---- live-writer detection: REAL evidence, not lock age ------------------------------------------
WRITERS="$(python3 - "$DB" "$PROJECT/.codegraph/codegraph.lock" 2>"$ERRF" <<'PY'
import json, os, sys
db, lock = sys.argv[1], sys.argv[2]
rdb = os.path.realpath(db)
targets = {rdb}                        # ONLY the main file: SQLite opens -wal/-shm O_RDWR even for a read-only connection (MEASURED: a live RO MCP session showed rw fds on them), so those are NOT writer signals
me = {os.getpid(), os.getppid()}
def cmd(pid):
    try:
        return open("/proc/%d/cmdline" % pid, "rb").read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        return None
out = []
for name in os.listdir("/proc"):
    if not name.isdigit() or int(name) in me:
        continue
    pid = int(name); fddir = "/proc/%d/fd" % pid
    try:
        fds = os.listdir(fddir)
    except OSError:
        continue
    for fd in fds:
        try:
            tgt = os.readlink("%s/%s" % (fddir, fd))
        except OSError:
            continue
        if tgt not in targets:
            continue
        try:
            flags = int(open("/proc/%d/fdinfo/%s" % (pid, fd)).read().split("flags:")[1].split()[0], 8)
        except Exception:
            flags = None                # unreadable => conservative: treat as writable (§11.4.201(4))
        if flags is None or (flags & 3) != 0:
            out.append({"pid": pid, "why": "rw-fd" if flags is not None else "fd-flags-unreadable", "path": tgt, "cmd": (cmd(pid) or "")[:160]})
try:
    lp = int(open(lock).read().split()[0])
except Exception:
    lp = None
if lp and lp not in me and os.path.isdir("/proc/%d" % lp):
    c = cmd(lp)
    if c is None or "codegraph" in c.lower():   # alive AND (codegraph-ish OR unreadable => conservative); a recycled non-codegraph PID is not a writer
        out.append({"pid": lp, "why": "lock-holder-alive", "path": lock, "cmd": (c or "<unreadable>")[:160]})
print(json.dumps(out))
PY
)" || die 4 "cannot determine whether a writer is live (refusing conservatively): $(head -c 300 "$ERRF" | tr '\n' ' ')"
if [ "$WRITERS" != "[]" ]; then
    die 4 "REFUSING to start: live writer on $DB — $(printf '%s' "$WRITERS" | head -c 400)  (retry after it finishes; a lock's age is never treated as proof it is dead)"
fi

# ---- pinned environment + exec -------------------------------------------------------------------
declare -a PINNED=(
    CODEGRAPH_NO_DAEMON=1 CODEGRAPH_NO_WATCH=1 CODEGRAPH_NO_UPDATE_CHECK=1 DO_NOT_TRACK=1 CODEGRAPH_TELEMETRY=0
    CODEGRAPH_NO_PROMPT_HOOK=1 CODEGRAPH_QUERY_POOL_SIZE=0
    CODEGRAPH_MCP_TOOLS=explore,node,search,callers,callees,impact,files,status
)
if [ "$DRY" -eq 1 ]; then
    printf '{"ok": true, "project": "%s", "runner": "%s", "runner_key": "%s", "writers": []}\n' "$PROJECT" "$RUNNER" "$RKEY"
    for kv in "${PINNED[@]}"; do echo "ENV $kv"; done
    echo "EXEC $RUNNER serve --mcp (cwd $PROJECT)"
    exit 0
fi
for kv in "${PINNED[@]}"; do export "$kv"; done
cd "$PROJECT" || die 3 "cannot enter $PROJECT"
exec "$RUNNER" serve --mcp
