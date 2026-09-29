#!/usr/bin/env bash
# ============================================================================
# run_scope_tests.sh — runs the CodeGraph scope tooling test suite
# ============================================================================
# Purpose      One entry point for t_scope_cases.py (behaviour) and
#              t_scope_mutations.py (paired §1.1 mutations), optionally repeated
#              N times with a determinism check (§11.4.50): identical exit codes
#              and identical RESULT-line hashes across iterations.
# Usage        bash run_scope_tests.sh [--iterations N] [--evidence DIR]
#              env CODEGRAPH_RUNNER_DIST=<runner lib/dist> (required unless the
#              `codegraph` executable on PATH resolves to a runner with lib/dist)
# Inputs       env as above
# Outputs      RESULT lines; DETERMINISM line; exit 0 only when every case PASSes
#              in every iteration AND all iterations are byte-identical.
# Side effects scratch dirs under $TMPDIR (or --evidence DIR); never touches the
#              live runner (mutations operate on scratch copies).
# Dependencies bash, python3 (+PyYAML), node, git, sha256sum
# Cross-refs   t_scope_cases.py, t_scope_mutations.py, ../codegraph_scope_guard.py
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER=1
EVID=""
while [ $# -gt 0 ]; do
    case "$1" in
        --iterations) ITER="$2"; shift 2 ;;
        --evidence) EVID="$2"; shift 2 ;;
        *) echo "usage: $0 [--iterations N] [--evidence DIR]" >&2; exit 3 ;;
    esac
done
if [ -z "${CODEGRAPH_RUNNER_DIST:-}" ]; then
    CODEGRAPH_RUNNER_DIST="$(python3 "$HERE/../codegraph_scope_guard.py" --resolve-dist 2>/dev/null || true)"
fi
if [ -z "$CODEGRAPH_RUNNER_DIST" ] || [ ! -f "$CODEGRAPH_RUNNER_DIST/extraction/index.js" ]; then
    echo "run_scope_tests: runner lib/dist not found (set CODEGRAPH_RUNNER_DIST)" >&2
    exit 3
fi
export CODEGRAPH_RUNNER_DIST SCOPE_RUNNER_DIST="$CODEGRAPH_RUNNER_DIST"
[ -n "$EVID" ] || EVID="$(mktemp -d "${TMPDIR:-/tmp}/scope_tests.XXXXXX")"
mkdir -p "$EVID"
FIRST_HASH=""
FIRST_RC=""
ALL_OK=0
i=1
while [ "$i" -le "$ITER" ]; do
    W="$EVID/iter$i"
    rm -rf "$W"; mkdir -p "$W"
    SCOPE_WORK="$W/cases" python3 "$HERE/t_scope_cases.py" > "$W/cases.out" 2>&1
    RC1=$?
    SCOPE_WORK="$W/mut" python3 "$HERE/t_scope_mutations.py" > "$W/mut.out" 2>&1
    RC2=$?
    cat "$W/cases.out" "$W/mut.out"
    H="$(grep -h '^RESULT ' "$W/cases.out" "$W/mut.out" | sha256sum | cut -d' ' -f1)"
    echo "ITERATION $i cases_rc=$RC1 mutations_rc=$RC2 result_sha256=$H"
    [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ] || ALL_OK=1
    if [ -z "$FIRST_HASH" ]; then FIRST_HASH="$H"; FIRST_RC="$RC1/$RC2"
    elif [ "$H" != "$FIRST_HASH" ] || [ "$RC1/$RC2" != "$FIRST_RC" ]; then
        echo "DETERMINISM FAIL iteration $i differs from iteration 1"; ALL_OK=1
    fi
    i=$((i + 1))
done
echo "DETERMINISM iterations=$ITER first_sha256=$FIRST_HASH verdict=$([ "$ALL_OK" -eq 0 ] && echo PASS || echo FAIL)"
exit "$ALL_OK"
