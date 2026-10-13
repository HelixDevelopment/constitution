#!/usr/bin/env bash
# ============================================================================
# test_bulk_classify_mutations.sh — paired §1.1 mutation proof for the sync BULK-classification fix
# ============================================================================
# Purpose      A test that cannot fail is decoration. Apply each single-edit MUTANT of
#              codegraph_safe.sh / codegraph_safe_helper.py (table: test_bulk_classify_mutate.py)
#              to a COPY of the tooling and require that the NAMED unit case(s) of
#              test_unit_safe.sh (U31-U43) turn RED (exit 1 + each named RESULT line FAIL). The
#              unmutated copy (golden-false) must run U31-U43 fully GREEN.
# Usage        bash test_bulk_classify_mutations.sh                 (golden-false + all mutants)
#              ONLY=MB1,MB7 bash test_bulk_classify_mutations.sh    (ONLY=GOLD for golden-false)
# Inputs       TMPDIR (work area), the tooling dir above tests/
# Outputs      one RESULT line per mutant (KILLED = named cases went RED) + SUMMARY;
#              exit 1 if any mutant SURVIVES or the golden-false run is not GREEN
# Side effects copies the tooling under $TMPDIR; never edits the real tree
# Dependencies bash, python3, node (stub runner), test_unit_safe.sh, test_bulk_classify_mutate.py
# Cross-refs   ../codegraph_safe.sh, ../codegraph_safe_helper.py, lib_test.sh
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
W="$(t_workdir bulk_classify_mut)"
echo "workdir $W"
ALL_CASES="U31,U32,U33,U34,U35,U36,U37,U38,U39,U40,U41,U42,U43"

make_copy() {
    # make_copy <dir> — the whole tooling dir (small), minus caches
    rm -rf "$1"; mkdir -p "$1"
    cp -r "$CG_DIR"/. "$1/"
    rm -rf "$1/__pycache__" "$1/tests/__pycache__"
}

run_cases() {
    # run_cases <copy> <label> <ONLY-csv> -> echoes the exit code; full log in $W/<label>.log
    ( cd "$1/tests" && TMPDIR="$W/tmp_$2" ONLY="$3" bash ./test_unit_safe.sh > "$W/$2.log" 2>&1; echo "exit=$?" >> "$W/$2.log" )
    sed -n 's/^exit=//p' "$W/$2.log" | tail -1
}

if t_want GOLD; then
    make_copy "$W/copy_GOLD"
    rc="$(run_cases "$W/copy_GOLD" GOLD "$ALL_CASES")"
    [ "$rc" = "0" ]
    t_check GOLD "unmutated tooling: U31-U43 all GREEN (golden-false)" $? "exit=$rc $(grep -E '^SUMMARY' "$W/GOLD.log")"
fi

while IFS=$'\t' read -r mid red what; do
    t_want "$mid" || continue
    copy="$W/copy_$mid"; make_copy "$copy"
    if ! python3 "$HERE/test_bulk_classify_mutate.py" --apply "$mid" "$copy" 2> "$W/$mid.merr"; then
        t_bad "$mid" "mutant applies to exactly one place" "$(head -c 200 "$W/$mid.merr")"; continue
    fi
    rc="$(run_cases "$copy" "$mid" "$red")"
    missing=""
    for c in $(echo "$red" | tr ',' ' '); do
        grep -q "^RESULT $c FAIL" "$W/$mid.log" || missing="$missing $c"
    done
    [ "$rc" = "1" ] && [ -z "$missing" ]
    t_check "$mid" "mutant KILLED ($what): named case(s) $red turn RED" $? "exit=$rc not-red:[${missing# }]"
done < <(python3 "$HERE/test_bulk_classify_mutate.py" --list)
t_finish
