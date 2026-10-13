#!/usr/bin/env bash
# ============================================================================
# test_resolve2_mutations.sh — paired §1.1 mutation proof for runner patch resolve2
# ============================================================================
# Purpose      A test that cannot fail is decoration. Apply each single-edit MUTANT of
#              runner_patches/resolve2.py (table: test_resolve2_mutate.py) to a COPY of
#              the tooling and require that the NAMED test(s) in test_resolve2.sh turn RED
#              (exit 1 + each named RESULT line FAIL). The unmutated tooling (golden-false)
#              must stay GREEN (exit 0).
#                M1 materializing getNodesByKind  => Q1   M4 wrong language filter => Q2+Q3
#                M2 objc filter widened (java)    => Q2+Q3 M5 stop after 1st objc   => Q2+Q3
#                M3 iteration order reversed      => Q2+Q3
# Usage        bash test_resolve2_mutations.sh                 (golden-false + all mutants)
#              ONLY=M1,M5 bash test_resolve2_mutations.sh      (ONLY=GOLD for golden-false)
# Inputs       STOCK (default: globally installed codegraph-linux-x64), TMPDIR
# Outputs      one RESULT line per mutant (KILLED = named tests went RED) + SUMMARY;
#              exit 1 if any mutant SURVIVES or the golden-false run is not GREEN
# Side effects copies the tooling under $TMPDIR; never edits the real tree
# Dependencies bash, python3, test_resolve2.sh (+ helpers), test_resolve2_mutate.py
# Cross-refs   ../runner_patches/resolve2.py, test_resolve2.sh
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
W="$(t_workdir resolve2_mut)"
echo "workdir $W"

make_copy() {
    # make_copy <dir> — copy exactly what test_resolve2.sh needs from the tooling dir
    rm -rf "$1"; mkdir -p "$1"
    cp -r "$CG_DIR/runner_patches" "$CG_DIR/tests" "$1/"
    cp "$CG_DIR"/*.py "$1/" 2>/dev/null
}

run_tests() {
    # run_tests <copy> <label> <ONLY-csv> -> echoes the test exit code; log in $W/<label>.log
    ( cd "$1/tests" && TMPDIR="$W/tmp_$2" ONLY="$3" bash ./test_resolve2.sh > "$W/$2.log" 2>&1; echo "exit=$?" >> "$W/$2.log" )
    sed -n 's/^exit=//p' "$W/$2.log" | tail -1
}

if t_want GOLD; then
    make_copy "$W/copy_GOLD"
    rc="$(run_tests "$W/copy_GOLD" GOLD Q1,Q2,Q3)"
    [ "$rc" = "0" ]
    t_check GOLD "unmutated tooling stays GREEN (golden-false)" $? "exit=$rc $(grep -E '^SUMMARY' "$W/GOLD.log")"
fi

while IFS=$'\t' read -r mid red; do
    t_want "$mid" || continue
    copy="$W/copy_$mid"; make_copy "$copy"
    if ! python3 "$HERE/test_resolve2_mutate.py" --apply "$mid" "$copy/runner_patches/resolve2.py" 2> "$W/$mid.merr"; then
        t_bad "$mid" "mutant applies to exactly one place" "$(head -c 200 "$W/$mid.merr")"; continue
    fi
    rc="$(run_tests "$copy" "$mid" "$red")"
    missing=""
    for c in $(echo "$red" | tr ',' ' '); do
        grep -q "^RESULT $c FAIL" "$W/$mid.log" || missing="$missing $c"
    done
    [ "$rc" = "1" ] && [ -z "$missing" ]
    t_check "$mid" "mutant KILLED (named test(s) $red turn RED)" $? "exit=$rc not-red:[${missing# }]"
done < <(python3 "$HERE/test_resolve2_mutate.py" --list)
t_finish
