#!/usr/bin/env bash
# ============================================================================
# test_guard.sh — tests for codegraph_guard.sh (future gate CM-CODEGRAPH-SAFE-INDEX-PATH)
# ============================================================================
# Purpose      Golden-true / golden-false-with-carrier fixtures (§11.4.201) for
#              the mechanical gate that forbids direct stock `codegraph init|index`
#              and `codegraph … || true` masking outside codegraph_safe.sh.
# Usage        bash test_guard.sh ; ONLY=G2 bash test_guard.sh
# Inputs       planted fixture trees under $TMPDIR; the real constitution/scripts dir
# Outputs      RESULT lines; exit 1 on any failure
# Side effects fixture trees under $TMPDIR/cg_safe_tests
# Dependencies bash, grep, awk
# Cross-refs   ../codegraph_guard.sh, test_mutation.sh
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
G="$CG_DIR/codegraph_guard.sh"
REAL_SCRIPTS="$(cd "$CG_DIR/.." && pwd)"

tree() { W="$(t_workdir "$1")"; mkdir -p "$W/scripts" "$W/docs"; }
guard() { OUT="$(bash "$G" --root "$W" 2>&1)"; RC=$?; }

if t_want G1; then
    OUT="$(bash "$G" --self-test 2>&1)"; RC=$?
    t_check G1 "--self-test: finds planted violations, does not flag codegraph_safe.sh" "$RC" "$(printf '%s' "$OUT" | tail -5 | tr '\n' ' ')"
fi

if t_want G2; then tree g2
    printf '#!/bin/sh\necho start\ncodegraph index /repo\n' > "$W/scripts/reindex.sh"  # codegraph-guard: allow planted guard-test fixture
    guard
    [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'scripts/reindex.sh:3'
    t_check G2 "direct stock 'codegraph index' in a script -> exit 1 with file:line" $? "rc=$RC out=$OUT"  # codegraph-guard: allow description text, not a command
fi

if t_want G3; then tree g3
    printf '#!/bin/sh\n(codegraph sync . || true)\n' > "$W/scripts/s.sh"  # codegraph-guard: allow planted guard-test fixture
    guard
    [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'scripts/s.sh:2'
    t_check G3 "'codegraph … || true' masking -> exit 1" $? "rc=$RC out=$OUT"
fi

if t_want G4; then tree g4
    printf '#!/bin/sh\n# never run codegraph index directly here\necho ok\n' > "$W/scripts/c.sh"  # codegraph-guard: allow planted guard-test fixture
    printf 'import os\n# codegraph init is wrapped\nprint(1)\n' > "$W/scripts/c.py"  # codegraph-guard: allow planted guard-test fixture
    guard
    t_check G4 "carrier: mention inside a comment line -> not flagged (exit 0)" "$RC" "rc=$RC out=$OUT"
fi

if t_want G5; then tree g5
    printf 'Prose that says codegraph init is unsafe.\n\n```bash\ncodegraph init -y .\n```\n' > "$W/docs/howto.md"  # codegraph-guard: allow planted guard-test fixture
    guard; r1=$RC; o1="$OUT"
    tree g5b
    printf 'Prose that says codegraph init is unsafe.\n\n```bash\nbash codegraph_safe.sh init\n```\n' > "$W/docs/howto.md"  # codegraph-guard: allow planted guard-test fixture
    guard; r2=$RC
    [ "$r1" -eq 1 ] && printf '%s' "$o1" | grep -q 'docs/howto.md:4' && [ "$r2" -eq 0 ]
    t_check G5 "markdown: fenced command flagged; prose mention not flagged" $? "r1=$r1 r2=$r2 o1=$o1"
fi

if t_want G6; then tree g6
    printf '#!/bin/sh\nnpx -y @colbymchenry/codegraph index .\n' > "$W/scripts/n.sh"  # codegraph-guard: allow planted guard-test fixture
    printf 'import subprocess\nsubprocess.run(["codegraph", "init", "-y", root])\n' > "$W/scripts/p.py"  # codegraph-guard: allow planted guard-test fixture
    guard
    [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'scripts/n.sh:2' && printf '%s' "$OUT" | grep -q 'scripts/p.py:2'
    t_check G6 "npx form and python argv-list form are flagged" $? "rc=$RC out=$OUT"
fi

if t_want G7; then tree g7
    cp "$CG_DIR/codegraph_safe.sh" "$W/scripts/codegraph_safe.sh"
    guard; r1=$RC
    mkdir -p "$W/evil"; printf '#!/bin/sh\ncodegraph index .\n' > "$W/evil/codegraph_safe.sh"  # codegraph-guard: allow planted guard-test fixture
    guard; r2=$RC
    [ "$r1" -eq 0 ] && [ "$r2" -eq 1 ]
    t_check G7 "launcher copy is content-clean (0); a violating file NAMED codegraph_safe.sh elsewhere is flagged (1)" $? "r1=$r1 r2=$r2 out=$OUT"
fi

if t_want G8; then tree g8
    printf '#!/bin/sh\ncodegraph index . # codegraph-guard: allow red-test of stock behaviour\n' > "$W/scripts/red.sh"
    printf '#!/bin/sh\ncodegraph index . # codegraph-guard: allow\n' > "$W/scripts/noreason.sh"  # codegraph-guard: allow planted guard-test fixture
    guard
    [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'noreason.sh:2' && ! printf '%s' "$OUT" | grep -q 'red.sh:2'
    t_check G8 "inline allow marker needs a reason; with a reason the line is exempt" $? "rc=$RC out=$OUT"
fi

if t_want G9; then
    OUT="$(bash "$G" --root "$REAL_SCRIPTS" 2>&1)"; RC=$?
    t_check G9 "real constitution/scripts tree (after the legacy fix) is clean" "$RC" "rc=$RC out=$(printf '%s' "$OUT" | head -8 | tr '\n' ' ')"
fi

t_finish
