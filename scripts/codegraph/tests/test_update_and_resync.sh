#!/usr/bin/env bash
# ============================================================================
# test_update_and_resync.sh — behavioural tests for scripts/codegraph_update_and_resync.sh
# ============================================================================
# Purpose      Prove the pull / index / commit / push one-shot routes every CodeGraph
#              write through the single writer entry codegraph_safe.sh (§11.4.78(7),
#              §11.4.80(5)) and never masks its failure (the `|| true` pattern that
#              CM-CODEGRAPH-SAFE-INDEX-PATH forbids). The real script is run; only the
#              writer entry (CG_UPDATE_SAFE_BIN) and the operator's helper commands
#              (pull_all, commit, push_all, exported shell functions) are replaced by
#              recording stubs, and a poisoned `codegraph` on PATH proves stock is
#              never called.
# Usage        bash test_update_and_resync.sh ; ONLY=U3 bash test_update_and_resync.sh
# Inputs       none; fixture repos under $TMPDIR/cg_safe_tests
# Outputs      RESULT lines; exit 1 on any failure
# Side effects fixture dirs under $TMPDIR/cg_safe_tests
# Dependencies bash, git
# Cross-refs   ../../codegraph_update_and_resync.sh, ../codegraph_safe.sh, test_guard.sh G9
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
S="${CG_UPDATE_SCRIPT:-$(cd "$HERE/../.." && pwd)/codegraph_update_and_resync.sh}"

# fixture <name> <db:yes|no> <safe_rc> — a git repo with a recording writer stub
fixture() {
    W="$(t_workdir "$1")"
    mkdir -p "$W/repo" "$W/bin"
    git -C "$W/repo" init -q
    [ "$2" = yes ] && { mkdir -p "$W/repo/.codegraph"; : > "$W/repo/.codegraph/codegraph.db"; }
    LOG="$W/calls.log"; : > "$LOG"
    cat > "$W/safe.sh" <<EOF
#!/usr/bin/env bash
printf 'safe %s\n' "\$*" >> "$LOG"
exit $3
EOF
    chmod +x "$W/safe.sh"
    cat > "$W/bin/codegraph" <<EOF
#!/usr/bin/env bash
printf 'STOCK %s\n' "\$*" >> "$LOG"
exit 0
EOF
    chmod +x "$W/bin/codegraph"
}

run() {
    # run — the real script, from inside the fixture repo, with stubs exported
    OUT="$(cd "$W/repo" || exit 99
        export LOG
        pull_all() { printf 'pull_all\n' >> "$LOG"; }
        commit() { printf 'commit\n' >> "$LOG"; }
        push_all() { printf 'push_all\n' >> "$LOG"; }
        export -f pull_all commit push_all
        PATH="$W/bin:$PATH" CG_UPDATE_SAFE_BIN="$W/safe.sh" bash "$S" 2>&1)"
    RC=$?
    CALLS="$(tr '\n' '|' < "$LOG")"
}

if t_want U1; then
    fixture u1 yes 0; run
    [ "$RC" -eq 0 ] && [ "$CALLS" = "pull_all|safe --wait sync|commit|push_all|" ]
    t_check U1 "populated DB: pull, safe --wait sync, commit, push in order; rc 0" $? "rc=$RC calls=$CALLS out=$OUT"
fi

if t_want U2; then
    fixture u2 no 0; run
    [ "$RC" -eq 0 ] && [ "$CALLS" = "pull_all|safe --wait init|commit|push_all|" ]
    t_check U2 "no DB: safe --wait init (never stock), rc 0" $? "rc=$RC calls=$CALLS out=$OUT"
fi

if t_want U3; then
    fixture u3 yes 7; run
    [ "$RC" -eq 7 ] && printf '%s' "$OUT" | grep -q 'codegraph_safe.sh sync FAILED (rc=7)'
    t_check U3 "writer failure is NOT masked: script exits with the writer's rc and says so" $? "rc=$RC calls=$CALLS out=$OUT"
fi

if t_want U4; then
    fixture u4 yes 1; run
    case "$CALLS" in *STOCK*) r=1 ;; *) r=0 ;; esac
    t_check U4 "stock codegraph on PATH is never invoked (even on writer failure)" $r "calls=$CALLS"
fi

if t_want U5; then
    fixture u5 yes 0; rm -f "$W/safe.sh"; run
    case "$CALLS" in *STOCK*) r=1 ;; *) [ "$RC" -eq 127 ] && r=0 || r=1 ;; esac
    t_check U5 "missing writer entry: exit 127, no stock fallback" $r "rc=$RC calls=$CALLS out=$OUT"
fi

if t_want U6; then
    OUT="$(bash "$(cd "$HERE/.." && pwd)/codegraph_guard.sh" --root "$(dirname "$S")" 2>&1)"; RC=$?
    printf '%s' "$OUT" | grep -q 'codegraph_update_and_resync.sh' && r=1 || r=0
    t_check U6 "the guard reports no offence in codegraph_update_and_resync.sh" $r "rc=$RC out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

t_finish
