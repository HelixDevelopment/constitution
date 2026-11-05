#!/usr/bin/env bash
# tests/gates/test_oracle_frozen_exclusions.sh -- CON-043 (operator decision 2026-11-05): checked-in per-file exclusion
# list for frozen RED-evidence files in CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (section 11.4.245).
#   Contract under test (config/oracle_frozen_evidence_exclusions.tsv, TAB columns: path class blob-sha reason):
#     * header line `# ceiling: N` is REQUIRED (the entry count may only decrease; more entries than N => FAIL);
#     * path is a literal repository-relative file (no glob, no absolute, no `..`, no trailing slash);
#     * class is a member of the closed set {frozen-red-evidence}; blob-sha is the 40-hex git blob id of the frozen bytes;
#     * an entry whose file's current blob id differs (or cannot be hashed) is VOIDED: the file is scanned again AND the
#       gate FAILs naming the voided entry; a malformed list is BLIND (rc 2), never a pass; an absent list = no exclusions.
#   Part B proves, on the REAL tree, that no runner executes the 3 frozen files (the premise of the exclusion).
# Test classes: unit/integration (REAL gate CLI in git sandboxes, no doubles), security (glob/path abuse), chaos (malformed,
# duplicate, missing-ceiling lists), determinism x3, RED proof vs the committed gate, paired section 1.1 mutations.
set -uo pipefail
export CONSTITUTION_JEV_HOOK=off
unset ORACLE_GUARD_STRICT ORACLE_GUARD_BASELINE ORACLE_GUARD_BASE ORACLE_GUARD_ROOT CONSUMER_ROOT
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
chk() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }
OR=cm_oracle_strategy_named_and_independent
GIT=(git -c user.email=t@t -c user.name=t -c commit.gpgsign=false)
EXC=config/oracle_frozen_evidence_exclusions.tsv

mkgate() { # $1 dir ; $2 gate source ; optional $3 sed expr (mutant)
    mkdir -p "$1/scripts/gates" "$1/scripts/lib" "$1/scripts/deps_manifest"
    cp "$2" "$1/scripts/gates/$OR.sh"
    cp "$src"/scripts/lib/default_scan_root.sh "$src"/scripts/lib/gate_env_override.sh "$src"/scripts/lib/third_party_prune.sh "$1/scripts/lib/"
    cp "$src"/scripts/deps_manifest/helix_deps_tsv.sh "$src"/scripts/deps_manifest/helix_deps_tsv.py "$src"/scripts/deps_manifest/helix_deps_manifest.py "$src"/scripts/deps_manifest/override_guard.sh "$1/scripts/deps_manifest/"
    [ -z "${3:-}" ] || sed -i -E "$3" "$1/scripts/gates/$OR.sh"
}
mkgate "$sb/g_new" "$src/scripts/gates/$OR.sh"
git -C "$src" show HEAD:scripts/gates/$OR.sh > "$sb/head_gate.sh" 2>/dev/null || { echo "FATAL: git show of the committed gate failed" >&2; exit 2; }
mkgate "$sb/g_head" "$sb/head_gate.sh"

run() { local gd="$1" r="$2"; shift 2; OUT=$(cd "$sb" && nice -n 15 bash "$gd/scripts/gates/$OR.sh" --root "$r" "$@" 2>&1); RC=$?; }
commit() { "${GIT[@]}" -C "$1" add -A >/dev/null 2>&1; "${GIT[@]}" -C "$1" commit -qm "$2" >/dev/null 2>&1; git -C "$1" update-ref refs/remotes/origin/main HEAD; }
FROZEN='def test_a():
    assert 1

def test_b():
    assert 2
'
mkrepo() { # $1 dir ; $2 ceiling ; $3 class (default frozen-red-evidence); entry for frozen/test_frozen.py with its real blob sha
    local d="$1" sha
    mkdir -p "$d/config" "$d/frozen"; git -C "$d" init -q 2>/dev/null
    printf '%s' "$FROZEN" > "$d/frozen/test_frozen.py"
    printf '# baseline\n' > "$d/config/oracle_ratchet_baseline.txt"
    sha=$(git hash-object --no-filters "$d/frozen/test_frozen.py")
    printf '# frozen evidence exclusions\n# ceiling: %s\nfrozen/test_frozen.py\t%s\t%s\tarchived RED evidence, cannot run\n' "$2" "${3:-frozen-red-evidence}" "$sha" > "$d/$EXC"
    printf 'one\n' > "$d/README.md"; commit "$d" c1; printf 'two\n' >> "$d/README.md"; commit "$d" c2
}

# RED proof: the committed gate (no exclusion support) FAILs a file above the empty baseline
mkrepo "$sb/r1" 1
run "$sb/g_head" "$sb/r1" --quiet
[ "$RC" = 1 ]; chk $? "RED: committed gate FAILs the frozen file (rc=$RC) -- no exclusion support existed"
run "$sb/g_new" "$sb/r1" --quiet
[ "$RC" = 0 ] && grep -q $'^ORACLE-VERDICT\tPASS\tmode=ratchet' <<<"$OUT" && grep -q 'excluded=1' <<<"$OUT" && grep -q 'voided=0' <<<"$OUT"; chk $? "GREEN: listed frozen file is excluded (rc=$RC, excluded=1 voided=0 in verdict)"
echo "$OUT" | tail -2

# determinism x3
a=$(bash -c 'cd "$1" && for i in 1 2 3; do bash "$2/scripts/gates/'"$OR"'.sh" --root "$3" --quiet 2>&1 | grep -v "^ORACLE-VERDICT" | sha256sum; done | sort -u | wc -l' _ "$sb" "$sb/g_new" "$sb/r1")
[ "$a" = 1 ]; chk $? "determinism: 3 runs give one identical output hash"

# voiding: edit the frozen file -> entry voided -> FAIL (with and without baseline slack)
mkrepo "$sb/r2" 1; printf '\ndef test_c():\n    assert 3\n' >> "$sb/r2/frozen/test_frozen.py"; commit "$sb/r2" edit
run "$sb/g_new" "$sb/r2" --quiet
[ "$RC" = 1 ] && grep -q 'VOIDED' <<<"$OUT" && grep -q 'frozen/test_frozen.py' <<<"$OUT"; chk $? "edited frozen file -> entry VOIDED, rc=1 (rc=$RC)"
printf '# baseline\nfrozen/test_frozen.py\t9\n' > "$sb/r2/config/oracle_ratchet_baseline.txt"; commit "$sb/r2" slack
run "$sb/g_new" "$sb/r2" --quiet
[ "$RC" = 1 ] && grep -q 'VOIDED' <<<"$OUT"; chk $? "voided entry FAILs even when the baseline has slack to absorb the file"
mkrepo "$sb/r2b" 1; rm -f "$sb/r2b/frozen/test_frozen.py"; mkdir -p "$sb/r2b/frozen"; ln -s /nonexistent "$sb/r2b/frozen/test_frozen.py"; commit "$sb/r2b" sym
run "$sb/g_new" "$sb/r2b" --quiet
[ "$RC" = 1 ]; chk $? "unhashable (dangling symlink) frozen path -> fail closed (rc=$RC)"

# new unlisted unannotated file still fails
mkrepo "$sb/r3" 1; printf 'def test_z():\n    assert 0\n' > "$sb/r3/frozen/test_other.py"; commit "$sb/r3" other
run "$sb/g_new" "$sb/r3" --quiet
[ "$RC" = 1 ] && grep -q 'test_other.py' <<<"$OUT"; chk $? "new unlisted unannotated file still FAILs"

# malformed lists are BLIND (rc 2)
badlist() { # $1 name ; $2 sed expr applied to the entry line ; $3 desc
    mkrepo "$sb/$1" 1; sed -i -E "$2" "$sb/$1/$EXC"; commit "$sb/$1" bad
    run "$sb/g_new" "$sb/$1" --quiet
    [ "$RC" = 2 ] && grep -q $'^ORACLE-VERDICT\tBLIND' <<<"$OUT"; chk $? "$3 -> BLIND rc=2 (rc=$RC)"
}
badlist b_glob 's#^frozen/test_frozen.py#frozen/*.py#' "glob in path"
badlist b_glob2 's#^frozen/test_frozen.py#frozen/test_frozen.p[y]#' "bracket glob in path"
badlist b_abs 's#^frozen/test_frozen.py#/etc/passwd#' "absolute path"
badlist b_dots 's#^frozen/test_frozen.py#frozen/../frozen/test_frozen.py#' "dot-dot path"
badlist b_dir 's#^frozen/test_frozen.py#frozen/#' "directory path"
badlist b_class 's#frozen-red-evidence#whatever#' "class outside the closed set"
badlist b_sha 's#\t[0-9a-f]{40}\t#\tabc\t#' "malformed blob sha"
badlist b_cols 's#\tarchived RED evidence, cannot run##' "missing reason column"
mkrepo "$sb/b_dup" 2; sed -n '3p' "$sb/b_dup/$EXC" >> "$sb/b_dup/$EXC"; commit "$sb/b_dup" dup
run "$sb/g_new" "$sb/b_dup" --quiet
[ "$RC" = 2 ]; chk $? "duplicate path -> BLIND rc=2 (rc=$RC)"
mkrepo "$sb/b_nc" 1; sed -i '/^# ceiling/d' "$sb/b_nc/$EXC"; commit "$sb/b_nc" noceil
run "$sb/g_new" "$sb/b_nc" --quiet
[ "$RC" = 2 ] && grep -q 'ceiling' <<<"$OUT"; chk $? "missing ceiling header -> BLIND rc=2"
mkrepo "$sb/b_over" 0; commit "$sb/b_over" over
run "$sb/g_new" "$sb/b_over" --quiet
[ "$RC" = 1 ] && grep -q 'ceiling' <<<"$OUT"; chk $? "more entries than the ceiling -> FAIL rc=1 (count may only decrease)"

# absent list = no exclusions, existing behaviour unchanged
mkrepo "$sb/r4" 1; rm -f "$sb/r4/$EXC"; commit "$sb/r4" noexc
run "$sb/g_new" "$sb/r4" --quiet
[ "$RC" = 1 ] && ! grep -q 'excluded=[1-9]' <<<"$OUT"; chk $? "absent exclusion list: frozen file counted as before (FAIL against empty baseline)"
# stale entry (file removed) is reported, not fatal
mkrepo "$sb/r5" 1; git -C "$sb/r5" rm -q -f frozen/test_frozen.py; commit "$sb/r5" rm
run "$sb/g_new" "$sb/r5" --quiet
[ "$RC" = 0 ] && grep -q 'stale exclusion' <<<"$OUT"; chk $? "stale exclusion entry reported, not fatal (rc=$RC)"
# strict mode ignores exclusions (absolute mode)
run "$sb/g_new" "$sb/r1" --quiet --strict
[ "$RC" = 1 ]; chk $? "--strict (absolute mode) does not honour exclusions"

# ── paired mutations: each mutant gate must be caught by the cases above ────────────────────────────────────────
mut() { # $1 name ; $2 sed ; $3 repo ; $4 expected rc that the REAL gate gives ; $5 desc
    mkgate "$sb/m_$1" "$src/scripts/gates/$OR.sh" "$2"
    if cmp -s "$sb/m_$1/scripts/gates/$OR.sh" "$sb/g_new/scripts/gates/$OR.sh"; then bad "mutant $1: sed did not change the gate (dead mutation)"; return; fi
    run "$sb/m_$1" "$3" --quiet
    [ "$RC" != "$4" ]; chk $? "mutant $1 killed: $5 (mutant rc=$RC, real gate rc=$4)"
}
mut sha 's#^excl_sha_ok[(][)] [{]#excl_sha_ok() { return 0;#' "$sb/r2" 1 "blob sha comparison disabled -> edited frozen file no longer voided"
mut glob 's#^is_glob[(][)] [{]#is_glob() { return 1;#' "$sb/b_glob" 2 "glob validation removed"
mut ceil 's#^excl_over_ceiling[(][)] [{]#excl_over_ceiling() { return 1;#' "$sb/b_over" 1 "ceiling check removed"
mut cls 's#frozen-red-evidence\) return 0#*) return 0#' "$sb/b_class" 2 "closed class set widened"

# ── Part B: the premise, on the REAL tree: no runner executes the 3 frozen files ───────────────────────────────
L="$src/submodules/llmctl"; P=specs/009-jev-decision-models/evidence/p1-red-original/harness/py
if [ ! -f "$L/$P/n_tests.py" ]; then
    echo "SKIP part B: submodules/llmctl not checked out (topology_unsupported)"
else
    # real list covers exactly the 3 frozen files with their real blob ids
    n=0; allok=0
    while IFS=$'\t' read -r p c s r; do
        case "$p" in ''|'#'*) continue ;; esac
        n=$((n+1)); [ "$(git hash-object --no-filters "$src/$p")" = "$s" ] || allok=1
    done < "$src/$EXC"
    [ "$n" = 3 ] && [ "$allok" = 0 ]; chk $? "real list: 3 entries, every recorded blob id equals the file's current blob id (n=$n)"
    # (1) parent census cannot see them: the parent tracks only the gitlink
    [ -z "$(git -C "$src" ls-files -- submodules/llmctl/specs)" ] && [ -n "$(git -C "$src" ls-files -- scripts/run_full_suite.sh)" ]; chk $? "parent run_full_suite census: no file under submodules/llmctl/specs is tracked by the parent (control needle: scripts/run_full_suite.sh is)"
    # (2) llmctl runner enumerates only tests/test_*.sh ; the py tier discovers only tests/py
    grep -q 'TESTS_DIR}"/test_\*\.sh' "$L/tests/run_tests.sh" && grep -q 'discover -s tests/py ' "$L/tests/test_py_unit.sh"; chk $? "llmctl runners: run_tests.sh globs tests/test_*.sh, test_py_unit.sh discovers -s tests/py only"
    ! grep -rnE 'specs/|p1-red-original|\bn_tests\b|\btest_d16_d32\b|\btest_defects_d01_d15\b' "$L/tests/run_tests.sh" "$L/tests/test_py_unit.sh" "$L/Makefile"; chk $? "no runner/Makefile references specs/, p1-red-original or the 3 modules"
    # (3) no code outside the frozen dir imports or invokes them
    hits=$(grep -rlE '\bn_tests\b|\btest_d16_d32\b|\btest_defects_d01_d15\b' "$L/tests" "$L/lib" "$L/bin" "$L/llmctld" "$L/scripts" 2>/dev/null | grep -v '/evidence/' | wc -l)
    [ "$hits" = 0 ]; chk $? "no file under llmctl tests/ lib/ bin/ llmctld/ scripts/ names the 3 modules (hits=$hits)"
    # (4) the archive itself says it cannot run and is not part of make test; the seams it drives are gone
    R="$L/specs/009-jev-decision-models/evidence/p1-red-original/README.md"
    grep -q 'can no longer run' "$R" && grep -q 'NOT part of `make test`' "$R" && [ ! -e "$L/lib/decide_gateway.py" ]; chk $? "archive README declares non-runnable + not in make test; the Python gateway it drives (lib/decide_gateway.py) is gone"
    # control needle for the greps above: the instrument can see a present name
    grep -q 'discover' "$L/tests/test_py_unit.sh"; chk $? "control needle: instrument sees 'discover' in test_py_unit.sh"
fi
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
