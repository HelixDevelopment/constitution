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
    cp "$HERE/../lib/third_party_prune.sh" "$HERE/../lib/default_scan_root.sh" "$HERE/../lib/gate_env_override.sh" "$d/scripts/lib/"   # guard lib: without it the suite's DANGEROUS_COMBO_PYTHON text-mode override is ignored (fail closed) and the text mutants m11-m13 survive
    mkdir -p "$d/scripts/deps_manifest"   # round 4: the lib reads manifests through the shared structural reader
    cp "$HERE/../deps_manifest/helix_deps_tsv.sh" "$HERE/../deps_manifest/override_guard.sh" "$HERE/../deps_manifest/helix_deps_tsv.py" "$HERE/../deps_manifest/helix_deps_manifest.py" "$d/scripts/deps_manifest/"
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
kill_check m1_oracle_no_prune gates/cm_oracle_strategy_named_and_independent.sh 'cm_third_party_prune_find_expr "$root"' ':' "oracle default prune disabled"
kill_check m2_dcfc_no_prune gates/cm_dangerous_combination_fail_closed.sh 'cm_third_party_prune_find_expr "$root"' ':' "dcfc default prune disabled"
kill_check m3_lib_accepts_unsafe lib/third_party_prune.sh 'cm_third_party_prune_ok() { # $1=candidate -> 0 iff safe relative path' 'cm_third_party_prune_ok() { return 0; }
cm_third_party_prune_ok_orig() {' "unsafe manifest paths no longer dropped"
kill_check m4_lib_no_helix_deps deps_manifest/helix_deps_tsv.py '"1" if tp.strip() == "true" else "0"' '"0"' "helix-deps third_party ignored"
kill_check m5_matcher_no_terminator gates/cm_oracle_strategy_named_and_independent.sh '([ \t]*[(#;,"\047]|[ \t]*$)' '' "prose with trailing words parsed as annotation"
kill_check m6_matcher_no_prefix gates/cm_oracle_strategy_named_and_independent.sh '(^|#)[ \t]*["\047]*[ \t]*oracle' 'oracle' "mid-sentence prose parsed as annotation"
kill_check m7_ast_idiom_off gates/cm_dangerous_combination_fail_closed.sh 'if kind == "swallow" and is_exception_assertion_idiom(' 'if False and is_exception_assertion_idiom(' "assert-False idiom flagged again (AST)"
kill_check m8_ast_broad_exempt gates/cm_dangerous_combination_fail_closed.sh 'if n in ("Exception", "BaseException", "AssertionError"):' 'if n in ("__none__",):' "broad/AssertionError handlers exempted (AST)"
kill_check m9_ast_non_test_exempt gates/cm_dangerous_combination_fail_closed.sh 'if not (func_name and func_name.startswith("test")):' 'if False:' "non-test helpers exempted (AST)"
kill_check m10_ast_first_stmt gates/cm_dangerous_combination_fail_closed.sh 'not _is_terminal_failure(body[-1])' 'not _is_terminal_failure(body[0])' "non-terminal assert exempted (AST)"
kill_check m11_text_idiom_off gates/cm_dangerous_combination_fail_closed.sh 'if (in_test) continue' 'if (0) continue' "assert-False idiom flagged again (text)"
kill_check m12_text_bare_exempt gates/cm_dangerous_combination_fail_closed.sh 'if (cl ~ /^except[ \t]*:/) narrow = 0' ':' "bare except exempted (text)"
kill_check m13_text_nested_exempt gates/cm_dangerous_combination_fail_closed.sh 'indent_of(lines[prev]) == tb_indent' 'indent_of(lines[prev]) > exc_indent' "nested assert exempted (text)"
kill_check m14_lib_prunes_gitmodules lib/third_party_prune.sh "    printf '%s\\n' third_party site-packages" "    printf '%s\\n' third_party site-packages; sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' \"\$root/.gitmodules\" 2>/dev/null" "own-org .gitmodules paths pruned again (pre-2026-11-01 behaviour)"
kill_check m15_lib_no_dirnames lib/third_party_prune.sh "    printf '%s\\n' third_party site-packages" "    :" "directory names third_party/site-packages no longer emitted by the resolver"
kill_check m16_lib_wrong_default_path lib/third_party_prune.sh 'p="${path:-submodules/$name}"' 'p="${path:-submodules/x_$name}"' "third_party dep default path wrong"
kill_check m17_lib_prunes_all_deps lib/third_party_prune.sh "if [ \"\$tp\" = 1 ]; then printf 'T" "if true; then printf 'T" "non-third_party helix-deps entries pruned"

kill_check m18_lib_no_nested lib/third_party_prune.sh '[ "$depth" -lt 3 ] || return 0' 'return 0' "nested own-org manifests never read"
kill_check m19_lib_nested_no_prefix lib/third_party_prune.sh '[ -n "$pre" ] && p="$pre/$p"' ':' "nested entries emitted without submodule prefix"
kill_check m20_lib_nested_reads_pruned lib/third_party_prune.sh 'tps="$tps|$p|"' 'tps="$tps"' "third_party-marked submodule's own manifest still read"
kill_check m21_lib_nested_ignores_listed_own lib/third_party_prune.sh 'else own="$own $p"; fi' 'else :; fi' "own-org deps named only by a non-third_party manifest path never descended"
kill_check m22_lib_nested_no_raw_validation lib/third_party_prune.sh 'cm_third_party_prune_ok "$p" || continue   # validate the RAW path before prefixing' ':' "nested absolute path accepted after prefixing"
# round 4: the hand parser (and its m23-m25/m30/m31 mutants) is gone; these mutate the structural reader path instead
kill_check m23_lib_tp_any_value lib/third_party_prune.sh 'if [ "$tp" = 1 ]; then printf' 'if [ -n "$tp" ]; then printf' "every dep treated as third_party (flag 0 read as true)"
kill_check m24_lib_field_order lib/third_party_prune.sh 'read -r name path url ref tp' 'read -r path name url ref tp' "reader record fields misassigned (name/path swapped)"
kill_check m25_reader_tp_any deps_manifest/helix_deps_tsv.py '"1" if tp.strip() == "true" else "0"' '"1" if tp.strip() else "0"' "reader marks third_party: false as true"
kill_check m26_lib_depth_unbounded lib/third_party_prune.sh '[ "$depth" -lt 3 ] || return 0' '[ "$depth" -lt 99 ] || return 0' "nested depth cap removed"
kill_check m27_lib_depth_too_small lib/third_party_prune.sh '[ "$depth" -lt 3 ] || return 0' '[ "$depth" -lt 1 ] || return 0' "nested depth cap lowered"
kill_check m28_lib_manifest_symlink lib/third_party_prune.sh '[ -f "$mf" ] && [ -r "$mf" ] && [ ! -L "$mf" ] || return 0' '[ -f "$mf" ] && [ -r "$mf" ] || return 0' "symlinked manifest followed"
# round 3/4 mutants
kill_check m30_lib_trailing_slash lib/third_party_prune.sh '        p="${p%/}"' '        :' "trailing-slash manifest path not normalised"
kill_check m31_reader_drops_path deps_manifest/helix_deps_tsv.py '("name", "path", "ssh_url", "ref")' '("name", "name", "ssh_url", "ref")' "reader loses the explicit path: field"
kill_check m32_oracle_name_based_paths gates/cm_oracle_strategy_named_and_independent.sh 'cm_third_party_prune_find_expr "$root"' 'for _x in $(cm_third_party_prune_paths "$root"); do prune_expr+=(-name "${_x##*/}" -o); done' "manifest-derived prune matches by basename at any depth (M3)"
kill_check m33_dcfc_name_based_paths gates/cm_dangerous_combination_fail_closed.sh 'cm_third_party_prune_find_expr "$root"' 'for _x in $(cm_third_party_prune_paths "$root"); do prune_expr+=(-name "${_x##*/}" -o); done' "manifest-derived prune matches by basename at any depth (M3)"
n=$((n+1)); mkcopy m29_lib_symlink_dirs
if mutate m29_lib_symlink_dirs lib/third_party_prune.sh '[ -d "$d" ] && [ ! -L "$d" ] || continue' '[ -d "$d" ] || continue' && mutate m29_lib_symlink_dirs lib/third_party_prune.sh '[ -d "$root/$c" ] && [ ! -L "$root/$c" ] || continue' '[ -d "$root/$c" ] || continue'; then
    if run_suite m29_lib_symlink_dirs; then echo "FAIL m29 SURVIVED: symlinked submodule dirs followed"; rc=1; else echo "ok   m29 killed: symlinked submodule dirs followed"; fi
else echo "FAIL m29: mutation did not apply"; rc=1; fi
echo "mutants: $n"
[ "$rc" -eq 0 ] && echo "META PASS — every mutant killed" || echo "META FAIL"
exit "$rc"
