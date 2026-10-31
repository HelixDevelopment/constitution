#!/usr/bin/env bash
# scanner_gate_false_positive_repairs_mutation_test.sh — paired §1.1
# mutation test for scanner_gate_false_positive_repairs_test.sh.
# Each mutant re-introduces ONE of the repaired defects in a private copy of the
# gates + lib; the repair test suite MUST fail against it. A mutant that the
# suite does not detect means the suite is decoration (§1.1). The unmutated copy
# is also run and MUST pass (golden-TRUE: no false kill).
# Side effects: mktemp -d sandbox only. Exit 0 iff every mutant is killed.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_repair_mut.XXXXXX")" || exit 2
: "${TMP:?}"
trap 'rm -rf -- "${TMP:?}"' EXIT

mkcopy() { # name -> $TMP/name/scripts/{gates,lib}
    local d="$TMP/$1"; mkdir -p "$d/scripts/gates" "$d/scripts/lib"
    cp "$HERE/cm_oracle_strategy_named_and_independent.sh" "$HERE/cm_dangerous_combination_fail_closed.sh" "$d/scripts/gates/"
    cp "$HERE/../lib/third_party_prune.sh" "$HERE/../lib/default_scan_root.sh" "$d/scripts/lib/"
}
mutate() { # name file(rel to scripts/) old new
    python3 - "$TMP/$1/scripts/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
}
run_suite() { CM_REPAIR_SKIP_E2E=1 CM_REPAIR_TEST_GATE_DIR="$TMP/$1/scripts/gates" nice -n 15 "$HERE/scanner_gate_false_positive_repairs_test.sh" >"$TMP/$1.log" 2>&1; }

rc=0
mkcopy clean
if run_suite clean; then echo "ok   golden-TRUE: unmutated copy passes the suite"; else echo "FAIL unmutated copy fails the suite"; tail -5 "$TMP/clean.log"; rc=1; fi

n=0
kill_check() { # name file old new desc
    n=$((n+1)); mkcopy "$1"
    if ! mutate "$1" "$2" "$3" "$4"; then echo "FAIL $1: mutation did not apply (stale anchor)"; rc=1; return; fi
    if run_suite "$1"; then echo "FAIL $1 SURVIVED: $5"; rc=1; else echo "ok   $1 killed: $5"; fi
}
kill_check m1_oracle_no_prune gates/cm_oracle_strategy_named_and_independent.sh 'cm_third_party_prune_paths "$root"' 'true' "oracle default prune disabled"
kill_check m2_dcfc_no_prune gates/cm_dangerous_combination_fail_closed.sh 'cm_third_party_prune_paths "$root"' 'true' "dcfc default prune disabled"
kill_check m3_lib_accepts_unsafe lib/third_party_prune.sh 'cm_third_party_prune_ok() { # $1=candidate -> 0 iff safe relative path' 'cm_third_party_prune_ok() { return 0; }
cm_third_party_prune_ok_orig() {' "unsafe manifest paths no longer dropped"
kill_check m4_lib_no_helix_deps lib/third_party_prune.sh '[ "$p" = true ] && tp=1' ':' "helix-deps third_party ignored"
kill_check m5_matcher_no_terminator gates/cm_oracle_strategy_named_and_independent.sh '([ \t]*[(#;,"\047]|[ \t]*$)' '' "prose with trailing words parsed as annotation"
kill_check m6_matcher_no_prefix gates/cm_oracle_strategy_named_and_independent.sh '(^|#)[ \t]*["\047]*[ \t]*oracle' 'oracle' "mid-sentence prose parsed as annotation"
kill_check m7_ast_idiom_off gates/cm_dangerous_combination_fail_closed.sh 'if kind == "swallow" and is_exception_assertion_idiom(' 'if False and is_exception_assertion_idiom(' "assert-False idiom flagged again (AST)"
kill_check m8_ast_broad_exempt gates/cm_dangerous_combination_fail_closed.sh 'if n in ("Exception", "BaseException", "AssertionError"):' 'if n in ("__none__",):' "broad/AssertionError handlers exempted (AST)"
kill_check m9_ast_non_test_exempt gates/cm_dangerous_combination_fail_closed.sh 'if not (func_name and func_name.startswith("test")):' 'if False:' "non-test helpers exempted (AST)"
kill_check m10_ast_first_stmt gates/cm_dangerous_combination_fail_closed.sh 'not _is_terminal_failure(body[-1])' 'not _is_terminal_failure(body[0])' "non-terminal assert exempted (AST)"
kill_check m11_text_idiom_off gates/cm_dangerous_combination_fail_closed.sh 'if (in_test) continue' 'if (0) continue' "assert-False idiom flagged again (text)"
kill_check m12_text_bare_exempt gates/cm_dangerous_combination_fail_closed.sh 'if (cl ~ /^except[ \t]*:/) narrow = 0' ':' "bare except exempted (text)"
kill_check m13_text_nested_exempt gates/cm_dangerous_combination_fail_closed.sh 'indent_of(lines[prev]) == tb_indent' 'indent_of(lines[prev]) > exc_indent' "nested assert exempted (text)"

echo "mutants: $n"
[ "$rc" -eq 0 ] && echo "META PASS — every mutant killed" || echo "META FAIL"
exit "$rc"
