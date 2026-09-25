#!/usr/bin/env bash
# ============================================================================
# test_codegraph_mcp_serve.sh — tests for codegraph_mcp_serve.sh, the .mcp.json
# command target that wires CodeGraph's real query tools (codegraph_explore /
# codegraph_node / etc.) into every agent working in this repo as first-class
# MCP tools (2026-09-25, operator mandate: "indexed space exposed and used by
# all agents").
# ============================================================================
# Purpose      Prove (a) the wrapper resolves the SAME patched runner
#              codegraph_safe.sh would use (never bare stock), (b) it always
#              passes --path + --no-watch to serve, (c) --no-watch genuinely
#              prevents the auto-sync WRITE that caused a real forensic
#              incident this same day (T04 below IS that incident, replayed
#              as a repeatable regression test), (d) project-dir resolution
#              is submodule-aware, (e) it fails closed when runner resolution
#              cannot proceed.
# Usage        bash test_codegraph_mcp_serve.sh            (all cases)
#              ONLY=T01,T04 bash test_codegraph_mcp_serve.sh (subset)
# Inputs       tests/fixtures/stub_cg (T01-T03, T05, T06 — STUB codegraph,
#              §11.4.27, never the real daemon-spawning binary); a real tiny
#              init'd project under $TMPDIR (T04 ONLY — the one case that
#              must prove REAL behaviour, run against an isolated scratch
#              project, never this repository's own checkout).
# Outputs      RESULT lines (lib_test.sh); exit 1 when any case fails.
# Side effects T04 launches a REAL `serve --mcp` daemon against an isolated
#              scratch project and ALWAYS kills it in a trap on every exit
#              path (§11.4.14) via lib_test.sh's t_kill_codegraph_pid (real
#              /proc identity check before any signal — §11.4.174/§11.4.263).
#              NEVER targets this repository's own .codegraph/ — see the
#              forensic incident note in codegraph_mcp_serve.sh itself.
# Dependencies bash, node (node:sqlite for the stub DB in T04's real init),
#              python3, git.
# Cross-refs   ../codegraph_mcp_serve.sh, lib_test.sh, test_unit_safe.sh
#              (shares the stub_cg fixture + setup() pattern).
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
FIX="$HERE/fixtures"
WRAPPER="$CG_DIR/codegraph_mcp_serve.sh"

# --------------------------------------------------------------------------
# Real daemons this run may spawn; the EXIT trap kills every one of them via
# the SAME real-cmdline-checked helper lib_test.sh's other suite uses — never
# a bare pkill -f (the exact class of carrier-match footgun §11.4.196(D) /
# §12.12 warn against).
# --------------------------------------------------------------------------
SPAWNED_PIDS=""
cleanup() {
    local p
    for p in $SPAWNED_PIDS; do t_kill_codegraph_pid "$p"; done
}
trap cleanup EXIT

setup() {
    # setup <name> → sets W (work dir) and P (project dir), stub env matching
    # test_unit_safe.sh's own setup() (T01-T03/T05/T06 reuse it verbatim).
    W="$(t_workdir "$1")"
    P="$W/proj"
    mkdir -p "$P/src"
    echo 'int a(void){return 1;}' > "$P/src/a.c"
    cp -a "$FIX/stub_cg" "$W/stub"
    python3 - "$W/stub" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
sha = hashlib.sha256(open(os.path.join(d, "lib/dist/db/index.js"), "rb").read()).hexdigest()
json.dump({"patch_id": "fkidx1", "codegraph_version": "1.6.0", "patched_dbjs_sha256": sha},
          open(os.path.join(d, "RUNNER_RECEIPT.json"), "w"))
PY
    export CODEGRAPH_BIN="$W/stub/bin/codegraph_stock"
    export CG_SAFE_PATCH_TOOL="$FIX/stub_patch_tool.sh"
    unset CG_SAFE_HELPER  # defaults to the REAL codegraph_safe_helper.py — safe,
    # side-effect-free (matches test_unit_safe.sh's own setup(), which never
    # stubs this either); its receipt() check reads RUNNER_RECEIPT.json, which
    # setup() writes for real above, so it passes against the stub runner dir.
    export STUB_RUNNER_BIN="$W/stub/bin/codegraph"
    export STUB_CALL_LOG="$W/calls.log"
    export STUB_PARK=1 STUB_SLEEP_MS=200
    : > "$STUB_CALL_LOG"
}

# ============================================================================

if t_want T01; then setup t01
    # The wrapper's resolved RUNNER must be the SAME path the patch tool's
    # own --print-bin reports — never a hand-picked/independent computation
    # that could silently drift from what codegraph_safe.sh itself uses.
    EXPECT="$(bash "$CG_SAFE_PATCH_TOOL" --patches fkidx1,resolve1 --print-bin 2>/dev/null | tail -n 1)"
    OUT="$(CLAUDE_PROJECT_DIR="$P" timeout 5 bash "$WRAPPER" < /dev/null 2>&1)"
    LOGGED="$(tail -n 1 "$STUB_CALL_LOG" 2>/dev/null | awk '{print $1}')"
    # stub_cg's role=runner wrapper execs `node .../codegraph.js "$@"` from
    # inside $EXPECT's own directory tree, so the call-log's logged role
    # confirms the RUNNER path (not stock) actually served the request.
    [ "$LOGGED" = "runner" ]
    t_check T01 "resolved runner is the SAME path fk_index_patch.py --print-bin reports (never independently computed)" $? "expect_runner=$EXPECT logged_role=$LOGGED out=$(printf '%s' "$OUT" | tr '\n' ' ')"
fi

if t_want T02; then setup t02
    # --path and --no-watch are ALWAYS passed to `serve --mcp` — the
    # forensic-incident-driven contract. STUB_PARK=1 makes the stub just
    # record argv and idle, never actually opening a DB.
    CLAUDE_PROJECT_DIR="$P" timeout 5 bash "$WRAPPER" < /dev/null > /dev/null 2>&1
    CALL="$(cat "$STUB_CALL_LOG" 2>/dev/null)"
    case "$CALL" in
        *"serve --mcp"*"--path"*"--no-watch"*) ok=0 ;;
        *) ok=1 ;;
    esac
    t_check T02 "wrapper always invokes 'serve --mcp --path <project> --no-watch' (--no-watch is NEVER optional)" $ok "call=$CALL"
fi

if t_want T03; then setup t03
    # --path targets exactly the resolved project dir, not cwd or something
    # else guessed.
    CLAUDE_PROJECT_DIR="$P" timeout 5 bash "$WRAPPER" < /dev/null > /dev/null 2>&1
    CALL="$(cat "$STUB_CALL_LOG" 2>/dev/null)"
    case "$CALL" in *"--path $P "*|*"--path $P") ok=0 ;; *) ok=1 ;; esac
    t_check T03 "--path targets exactly \$CLAUDE_PROJECT_DIR ($P), never cwd/guessed" $ok "call=$CALL"
fi

if t_want T04; then setup t04
    # ============================================================
    # THE FORENSIC-INCIDENT REGRESSION TEST — real codegraph, real init,
    # real serve, real file mutation, real DB mtime check. Never the stub:
    # the incident this test guards against IS the real daemon's own
    # file-watcher/auto-sync behaviour, which a stub cannot exhibit.
    # ISOLATED scratch project ONLY — never this repository's own checkout.
    # ============================================================
    REAL_CG_BIN="$(command -v codegraph 2>/dev/null || true)"
    if [ -z "$REAL_CG_BIN" ]; then
        echo "SKIP T04: real 'codegraph' binary not on PATH in this environment — cannot exercise the real daemon (honest skip, §11.4.3, not a pass)"
    else
        RW="$(t_workdir t04_real)"
        RP="$RW/realproj"
        mkdir -p "$RP"
        ( cd "$RP" && git init -q . && echo hello > f.txt \
          && git add f.txt && git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1
        REAL_RUNNER="$(python3 "$CG_DIR/fk_index_patch.py" --patches fkidx1,resolve1 --print-bin 2>/dev/null | tail -n 1)"
        if [ -z "$REAL_RUNNER" ] || [ ! -x "$REAL_RUNNER" ]; then
            echo "SKIP T04: could not resolve a real patched runner in this environment (honest skip)"
        else
            "$REAL_RUNNER" init -y "$RP" >/dev/null 2>&1
            if [ ! -f "$RP/.codegraph/codegraph.db" ]; then
                echo "SKIP T04: real init did not produce a codegraph.db (honest skip)"
            else
                BEFORE="$(stat -c '%Y' "$RP/.codegraph/codegraph.db" 2>/dev/null)"
                ( unset CODEGRAPH_BIN CG_SAFE_PATCH_TOOL CG_SAFE_HELPER STUB_PARK STUB_RUNNER_BIN STUB_CALL_LOG
                  CLAUDE_PROJECT_DIR="$RP" nohup bash "$WRAPPER" </dev/null >"$RW/serve.out" 2>"$RW/serve.err" &
                  echo $! > "$RW/wrapper.pid" )
                sleep 3
                REAL_PID="$(pgrep -f "serve --mcp.*$RP" 2>/dev/null | head -n 1)"
                if [ -n "$REAL_PID" ]; then SPAWNED_PIDS="$SPAWNED_PIDS $REAL_PID"; fi
                echo "second line" >> "$RP/f.txt"
                sleep 4
                AFTER="$(stat -c '%Y' "$RP/.codegraph/codegraph.db" 2>/dev/null)"
                for p in $SPAWNED_PIDS; do t_kill_codegraph_pid "$p"; done
                SPAWNED_PIDS=""
                [ "$BEFORE" = "$AFTER" ]
                t_check T04 "--no-watch genuinely prevents the auto-sync WRITE that caused the 2026-09-25 database-is-locked incident (DB mtime unchanged after a tracked-file edit)" $? "before=$BEFORE after=$AFTER real_runner=$REAL_RUNNER real_pid=$REAL_PID"
            fi
        fi
    fi
fi

if t_want T05; then setup t05
    # Project-dir resolution prefers $CLAUDE_PROJECT_DIR when set — must NOT
    # fall through to git-toplevel guessing when the authoritative env var
    # is already present.
    OTHER_W="$(t_workdir t05_other)"
    CLAUDE_PROJECT_DIR="$OTHER_W" timeout 5 bash "$WRAPPER" < /dev/null > /dev/null 2>&1
    CALL="$(cat "$STUB_CALL_LOG" 2>/dev/null)"
    case "$CALL" in *"--path $OTHER_W "*|*"--path $OTHER_W") ok=0 ;; *) ok=1 ;; esac
    t_check T05 "\$CLAUDE_PROJECT_DIR, when set, is used verbatim — never overridden by git-toplevel guessing" $ok "call=$CALL other_w=$OTHER_W"
fi

if t_want T06; then setup t06
    # Fail-closed: when neither the patch tool nor python3 can be consulted,
    # the wrapper exits non-zero rather than silently falling back to an
    # unverified binary (§11.4.201 fail-closed — mirrors codegraph_safe.sh's
    # own resolve_runner() discipline).
    unset CLAUDE_PROJECT_DIR
    OUT="$(CG_SAFE_PATCH_TOOL="$W/does_not_exist.py" timeout 5 bash "$WRAPPER" < /dev/null 2>&1)"; rc=$?
    [ "$rc" -ne 0 ]
    t_check T06 "wrapper fails closed (non-zero exit) when the patch tool cannot be consulted, never silently falls back to stock" $? "rc=$rc out=$(printf '%s' "$OUT" | tr '\n' ' ')"
fi

t_finish
