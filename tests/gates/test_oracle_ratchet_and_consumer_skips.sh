#!/usr/bin/env bash
# tests/gates/test_oracle_ratchet_and_consumer_skips.sh -- known_failures_v73 rows 9/10 (operator decisions 2026-11-01).
#   (A) CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT adopts a monotone-decreasing RATCHET (checked-in per-file baseline) plus a
#       NEW/MODIFIED-test-function annotation requirement; untouched legacy tests are exempt (golden-FALSE); a missing or
#       malformed baseline is BLIND (rc=2), never a pass.
#   (B) CM-CODEGRAPH-MCP-HEALTH and CM-OPENDESIGN-UI-SYSTEM take --standalone-canon: an honest SKIP (rc=3 + VERDICT line,
#       reason topology_unsupported) when the declared canon has no such surface, while a consumer that HAS the surface and
#       violates it still FAILs.
# Test classes: unit/integration/e2e (REAL gates through their real CLI in git sandboxes, no doubles), security (hostile
# file names, prose carriers), chaos (unreadable/duplicate/malformed baseline, concurrent runs), determinism x3,
# idempotency, performance budget, RED proof against the committed (pre-change) gate, paired §1.1 mutations.
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

# gate sandboxes: current gate (new), committed gate (RED proof), mutants
mkgate() { # $1 dir ; $2 = source file for the gate ; optional $3 sed expr to mutate
    mkdir -p "$1/scripts/gates" "$1/scripts/lib"
    cp "$2" "$1/scripts/gates/$OR.sh"
    cp "$src/scripts/lib/default_scan_root.sh" "$src/scripts/lib/gate_env_override.sh" "$1/scripts/lib/"   # the REAL env-override guard is exercised in every sandbox
    # F3: every gate sandbox uses the WORKING-TREE lib (the figure tracks the lib under test); only the RED-proof sandbox
    # (OLDLIB=1, the committed pre-change gate) pairs the gate with the committed lib.
    if [ "${OLDLIB:-0}" = 1 ]; then
        # N2 (round 3): no silent fallback -- if the committed lib cannot be read the RED proof would test the new lib, so stop loudly
        git -C "$src" show HEAD:scripts/lib/third_party_prune.sh > "$1/scripts/lib/third_party_prune.sh" 2>/dev/null \
            || { echo "FATAL: git show HEAD:scripts/lib/third_party_prune.sh failed; the RED-proof sandbox cannot be built" >&2; exit 2; }
    else
        cp "$src/scripts/lib/third_party_prune.sh" "$1/scripts/lib/"
    fi
    # round 4: the prune lib reads manifests through the shared structural reader (scripts/deps_manifest/helix_deps_tsv.*)
    mkdir -p "$1/scripts/deps_manifest"
    cp "$src"/scripts/deps_manifest/helix_deps_tsv.sh "$src"/scripts/deps_manifest/helix_deps_tsv.py "$src"/scripts/deps_manifest/helix_deps_manifest.py "$src"/scripts/deps_manifest/override_guard.sh "$1/scripts/deps_manifest/"
    [ -z "${3:-}" ] || sed -i -E "$3" "$1/scripts/gates/$OR.sh"
}
mkgate "$sb/g_new" "$src/scripts/gates/$OR.sh"
git -C "$src" show HEAD:scripts/gates/$OR.sh > "$sb/head_gate.sh" 2>/dev/null || { echo "FATAL: git show HEAD:scripts/gates/$OR.sh failed" >&2; exit 2; }
OLDLIB=1 mkgate "$sb/g_head" "$sb/head_gate.sh"

run() { # $1 gate dir, $2 root, rest args -> OUT RC
    local gd="$1" r="$2"; shift 2
    OUT=$(cd "$sb" && nice -n 15 bash "$gd/scripts/gates/$OR.sh" --root "$r" "$@" 2>&1); RC=$?
}

LEGACY='def test_a():
    assert 1

def test_b():
    assert 2

def test_c():
    # oracle: SPECIFIED
    assert 3

def test_d():
    assert 4
'
mkrepo() { # $1 dir ; $2 baseline count for test_legacy.py (empty = no baseline file)
    local d="$1"
    mkdir -p "$d/config"; git -C "$d" init -q 2>/dev/null
    printf '%s' "$LEGACY" > "$d/test_legacy.py"
    if [ -n "${2:-}" ]; then printf '# baseline\ntest_legacy.py\t%s\n' "$2" > "$d/config/oracle_ratchet_baseline.txt"; fi
    printf 'one\n' > "$d/README.md"
    "${GIT[@]}" -C "$d" add -A >/dev/null 2>&1; "${GIT[@]}" -C "$d" commit -q -m c1 >/dev/null 2>&1
    printf 'two\n' >> "$d/README.md"; "${GIT[@]}" -C "$d" commit -qam c2 >/dev/null 2>&1
    git -C "$d" update-ref refs/remotes/origin/main HEAD   # c2 counts as pushed: the non-sliding base (no real remote needed)
}
markpushed() { git -C "$1" update-ref refs/remotes/origin/main HEAD; }   # everything committed so far counts as pushed
commit() { "${GIT[@]}" -C "$1" add -A >/dev/null 2>&1; "${GIT[@]}" -C "$1" commit -qm "$2" >/dev/null 2>&1; }

# ── RED proof: the committed (pre-change) gate has no ratchet -----------------------------------------------
mkrepo "$sb/r_eq" 3
run "$sb/g_head" "$sb/r_eq" --quiet
[ "$RC" = 1 ]; chk $? "RED: committed gate FAILs a repo that sits exactly at its baseline (rc=$RC) -- no ratchet existed"
run "$sb/g_new" "$sb/r_eq" --quiet
[ "$RC" = 0 ] && grep -q $'^ORACLE-VERDICT\tPASS\tmode=ratchet' <<<"$OUT"; chk $? "GREEN: new gate PASSes at baseline (rc=$RC, ORACLE-VERDICT PASS ratchet)"

# ── ratchet core -----------------------------------------------------------------------------------------------
# above baseline
mkrepo "$sb/r_over" 3
printf '\ndef test_e():\n    assert 5\n' >> "$sb/r_over/test_legacy.py"; commit "$sb/r_over" add_e; markpushed "$sb/r_over"   # pushed: isolates the COUNT ratchet from the new-function check (no ambient --base)
run "$sb/g_new" "$sb/r_over" --quiet
[ "$RC" = 1 ] && grep -q 'exceeds baseline 3' <<<"$OUT" && grep -q $'^ORACLE-VERDICT\tFAIL\tmode=ratchet' <<<"$OUT"; chk $? "above baseline -> rc=1 with 'exceeds baseline 3'"
# below baseline: pass + tells how to lower; --write-baseline lowers; a second write is a no-op; raising refused
mkrepo "$sb/r_low" 9
run "$sb/g_new" "$sb/r_low"
[ "$RC" = 0 ] && grep -q 'lower the baseline with --write-baseline' <<<"$OUT"; chk $? "below baseline -> rc=0 and tells how to lower it"
run "$sb/g_new" "$sb/r_low" --write-baseline
v1=$(grep -v '^#' "$sb/r_low/config/oracle_ratchet_baseline.txt")
[ "$RC" = 0 ] && [ "$v1" = $'test_legacy.py\t3' ]; chk $? "--write-baseline lowers 9 -> 3 (rc=$RC)"
h1=$(sha256sum "$sb/r_low/config/oracle_ratchet_baseline.txt"); run "$sb/g_new" "$sb/r_low" --write-baseline; h2=$(sha256sum "$sb/r_low/config/oracle_ratchet_baseline.txt")
[ "$h1" = "$h2" ]; chk $? "idempotency: second --write-baseline leaves the baseline byte-identical"
printf '\ndef test_e():\n    assert 5\n' >> "$sb/r_low/test_legacy.py"
run "$sb/g_new" "$sb/r_low" --write-baseline
[ "$RC" = 1 ] && grep -q 'refuse to RAISE' <<<"$OUT" && [ "$(grep -v '^#' "$sb/r_low/config/oracle_ratchet_baseline.txt")" = $'test_legacy.py\t3' ]; chk $? "--write-baseline refuses to raise (rc=1, baseline unchanged)"
# a brand-new unannotated test FILE (absent from the baseline = 0) fails
mkrepo "$sb/r_newfile" 3
printf 'def test_z():\n    assert 0\n' > "$sb/r_newfile/test_new.py"; commit "$sb/r_newfile" newfile
run "$sb/g_new" "$sb/r_newfile" --quiet
[ "$RC" = 1 ] && grep -q 'test_new.py' <<<"$OUT"; chk $? "file absent from the baseline counts against a baseline of 0"

# ── NEW / MODIFIED function check --------------------------------------------------------------------------------
# slack present (baseline 5 > 3): a NEW unannotated function must still fail
mkrepo "$sb/n1" 5
printf '\ndef test_e():\n    assert 5\n' >> "$sb/n1/test_legacy.py"; commit "$sb/n1" add_e
run "$sb/g_new" "$sb/n1" --quiet
[ "$RC" = 1 ] && grep -q 'NEW or MODIFIED test function without a valid oracle annotation' <<<"$OUT" && ! grep -q 'exceeds baseline' <<<"$OUT"; chk $? "new unannotated function fails even with baseline slack (not an over-baseline failure)"
# golden-FALSE: new but annotated
mkrepo "$sb/n2" 5
printf '\ndef test_e():\n    # oracle: INVARIANT\n    assert 5\n' >> "$sb/n2/test_legacy.py"; commit "$sb/n2" add_e
run "$sb/g_new" "$sb/n2" --quiet
[ "$RC" = 0 ]; chk $? "golden-FALSE: new function WITH annotation passes (rc=$RC)"
# modified legacy function (body edit) must be annotated
mkrepo "$sb/n3" 5
sed -i 's/assert 2/assert 22/' "$sb/n3/test_legacy.py"; commit "$sb/n3" edit_b
run "$sb/g_new" "$sb/n3" --quiet
[ "$RC" = 1 ] && grep -q 'test_legacy.py:4: NEW or MODIFIED' <<<"$OUT"; chk $? "modified legacy unannotated function fails"
# golden-FALSE: editing one legacy function does not fail the UNTOUCHED siblings (only test_b is reported)
[ "$(grep -c 'NEW or MODIFIED' <<<"$OUT")" = 1 ]; chk $? "golden-FALSE: untouched legacy siblings are not failed (exactly 1 modified report)"
# golden-FALSE: change outside any test function (a module-level comment) fails nothing
mkrepo "$sb/n4" 5
printf '# a module comment\n' >> "$sb/n4/test_legacy.py"; commit "$sb/n4" comment
run "$sb/g_new" "$sb/n4" --quiet
[ "$RC" = 0 ]; chk $? "golden-FALSE: edit outside test functions passes"
# F2: deletion-only hunks. (a) deleting an annotation from a function that stays => that function is MODIFIED and fails
mkrepo "$sb/f2a" 5
sed -i '/# oracle: SPECIFIED/d' "$sb/f2a/test_legacy.py"; commit "$sb/f2a" strip_annotation
run "$sb/g_new" "$sb/f2a" --quiet
[ "$RC" = 1 ] && grep -q 'test_legacy.py:7: NEW or MODIFIED' <<<"$OUT"; chk $? "F2 RED->GREEN: deletion-only hunk that strips an annotation is not silently skipped (rc=$RC)"
# (b) golden-FALSE: deleting a whole annotated function (annotation + def removed together) needs no annotation
mkrepo "$sb/f2b" 5
python3 - "$sb/f2b/test_legacy.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,"w").write(s.replace("def test_c():\n    # oracle: SPECIFIED\n    assert 3\n\n",""))
PY
commit "$sb/f2b" drop_c
run "$sb/g_new" "$sb/f2b" --quiet
[ "$RC" = 0 ]; chk $? "F2 golden-FALSE: deleting a whole annotated test function passes (rc=$RC)"
# (c) golden-FALSE: deleting an unrelated body line (no annotation involved) is not a new/changed test
mkrepo "$sb/f2c" 5
sed -i '/assert 4/d' "$sb/f2c/test_legacy.py"; commit "$sb/f2c" del_body
run "$sb/g_new" "$sb/f2c" --quiet
[ "$RC" = 0 ]; chk $? "F2 golden-FALSE: deletion-only hunk with no annotation removed passes (rc=$RC)"
# paired mutation: the deletion-annotation tracking disabled => case (a) goes undetected
mkgate "$sb/g_f2m" "$src/scripts/gates/$OR.sh" 's/if \(pend && delann && !deldef\)/if (0)/'
run "$sb/g_f2m" "$sb/f2a" --quiet
[ "$RC" = 0 ]; chk $? "F2 §1.1 mutation: deletion tracking disabled -> stripped annotation slips through (mutant detectable, rc=$RC)"
# F2b (review 2026-11-03): REPLACING (not deleting) the annotation comment in the 3-line window above a def is a one-line
# replace hunk (`@@ -1 +1 @@`) that must mark the function modified. Baseline 4 (= count after the strip): strip test_c annotation by replacing
# its comment line and annotate test_a -> without the window rule test_c is silently legalised.
mkrepo "$sb/f2r" 4
python3 - "$sb/f2r/test_legacy.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,"w").write(s.replace("def test_c():\n    # oracle: SPECIFIED\n","# oracle: SPECIFIED\ndef test_c():\n"))
PY
commit "$sb/f2r" annotation_above_def; markpushed "$sb/f2r"
python3 - "$sb/f2r/test_legacy.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,"w").write(s.replace("# oracle: SPECIFIED\ndef test_c","# reviewed, no strategy\ndef test_c"))
PY
commit "$sb/f2r" replace_annotation
run "$sb/g_new" "$sb/f2r" --quiet
[ "$RC" = 1 ] && grep -q 'NEW or MODIFIED' <<<"$OUT"; chk $? "F2b RED->GREEN: replace-hunk that swaps an annotation line above a def marks the function modified (rc=$RC)"
mkgate "$sb/g_f2r" "$src/scripts/gates/$OR.sh" 's/re\[q\] >= wstart/re[q] >= i/'
run "$sb/g_f2r" "$sb/f2r" --quiet
[ "$RC" = 0 ]; chk $? "F2b §1.1 mutation: window rule disabled -> replaced annotation slips through (mutant detectable, rc=$RC)"
# golden-FALSE: a changed line in the window of a function whose annotation is intact does not fail it
mkrepo "$sb/f2g" 5
python3 - "$sb/f2g/test_legacy.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,"w").write(s.replace("    # oracle: SPECIFIED\n","    # oracle: SPECIFIED\n",1).replace("def test_d","# note\ndef test_d"))
PY
commit "$sb/f2g" note_above_d
run "$sb/g_new" "$sb/f2g" --quiet
[ "$(grep -c 'NEW or MODIFIED' <<<"$OUT")" = 1 ]; chk $? "F2b golden-FALSE: only the touched function (test_d) is reported, siblings are not"
# finding 5: the real env guard is present in the sandbox and ignores the ambient baseline override without HELIX_TEST_MODE
[ -r "$sb/g_new/scripts/lib/gate_env_override.sh" ]; chk $? "sandbox carries the real gate_env_override.sh"
OUT=$(cd "$sb" && ORACLE_GUARD_BASELINE=/nonexistent nice -n 15 bash "$sb/g_new/scripts/gates/$OR.sh" --root "$sb/f2g" --quiet 2>&1)
grep -q 'ignoring ORACLE_GUARD_BASELINE\|overrides=' <<<"$OUT"; chk $? "ambient ORACLE_GUARD_BASELINE ignored without HELIX_TEST_MODE (real guard)"

# working-tree (uncommitted/staged) and untracked changes are covered
mkrepo "$sb/n5" 5
sed -i 's/assert 4/assert 44/' "$sb/n5/test_legacy.py"
run "$sb/g_new" "$sb/n5" --quiet
[ "$RC" = 1 ]; chk $? "uncommitted edit of an unannotated legacy function fails"
mkrepo "$sb/n6" 5
printf 'def test_u():\n    assert 0\n' > "$sb/n6/test_untracked.py"
run "$sb/g_new" "$sb/n6" --quiet
[ "$RC" = 1 ] && grep -q 'test_untracked.py:1: NEW or MODIFIED' <<<"$OUT"; chk $? "untracked new test file with an unannotated function fails"
# --base: may only be the non-sliding base (c2, "pushed") or OLDER; never newer (round 3, I2)
mkrepo "$sb/n7" 5
printf '\ndef test_e():\n    assert 5\n' >> "$sb/n7/test_legacy.py"; commit "$sb/n7" add_e; printf 'x\n' >> "$sb/n7/README.md"; commit "$sb/n7" readme
run "$sb/g_new" "$sb/n7" --quiet
a=$RC; run "$sb/g_new" "$sb/n7" --quiet --base HEAD~2; b=$RC
[ "$a" = 1 ] && [ "$b" = 1 ] && grep -qE $'^ORACLE-VERDICT\tFAIL\tmode=ratchet.*\tbase=[0-9a-f]{12}$' <<<"$OUT"; chk $? "default base is the non-sliding base (sees add_e though the last commit is README only, rc=$a); --base HEAD~2 (= that base) accepted (rc=$b); verdict carries base=<sha12>"
run "$sb/g_new" "$sb/n7" --quiet --base HEAD; [ "$RC" = 2 ] && grep -q "refused" <<<"$OUT"; chk $? "I2: --base HEAD (newer than the non-sliding base) refused rc=2 (rc=$RC)"
run "$sb/g_new" "$sb/n7" --quiet --base HEAD~1; [ "$RC" = 2 ]; chk $? "I2: --base HEAD~1 (newer than the non-sliding base) refused rc=2 (rc=$RC)"
run "$sb/g_new" "$sb/n7" --quiet --base HEAD~3; [ "$RC" = 1 ] && grep -q 'evaluated against' <<<"$OUT"; chk $? "I2: --base older than the non-sliding base (the root commit) accepted and stricter (rc=$RC)"
run "$sb/g_new" "$sb/n7" --quiet --base nonexistent_ref_zz; [ "$RC" = 2 ]; chk $? "I2: unresolvable --base refused rc=2"
# I2: an ambient ORACLE_GUARD_BASE must not turn a FAIL into a PASS
OUT=$(cd "$sb" && ORACLE_GUARD_BASE=HEAD nice -n 15 bash "$sb/g_new/scripts/gates/$OR.sh" --root "$sb/n7" --quiet 2>&1); RC=$?
[ "$RC" = 1 ] && grep -q 'ORACLE_GUARD_BASE is ignored' <<<"$OUT"; chk $? "I2: ORACLE_GUARD_BASE=HEAD is ignored (FAIL stays FAIL, noted) (rc=$RC)"
# I3: remotes named github_x (no origin, no tracking branch) still give the non-sliding base; none at all is BLIND
mkrepo "$sb/n8" 5; git -C "$sb/n8" update-ref -d refs/remotes/origin/main; git -C "$sb/n8" update-ref refs/remotes/github_x/main HEAD
printf '\ndef test_e():\n    assert 5\n' >> "$sb/n8/test_legacy.py"; commit "$sb/n8" add_e
for i in 1 2 3; do "${GIT[@]}" -C "$sb/n8" commit -q --allow-empty -m "empty$i" >/dev/null 2>&1; done
run "$sb/g_new" "$sb/n8" --quiet
[ "$RC" = 1 ] && grep -q 'NEW or MODIFIED' <<<"$OUT"; chk $? "I3: remote github_x/main only: base found, empty commits cannot slide it (rc=$RC)"
git -C "$sb/n8" update-ref -d refs/remotes/github_x/main
run "$sb/g_new" "$sb/n8" --quiet
[ "$RC" = 2 ] && grep -q $'^ORACLE-VERDICT\tBLIND\tmode=ratchet\treason=no_nonsliding_base' <<<"$OUT"; chk $? "I3: no remote main at all -> BLIND rc=2, never HEAD~1 (rc=$RC)"
# I3: of several remotes the OLDEST merge-base wins (most conservative): github_y lags at c1, github_x at the tip
mkrepo "$sb/n9" 5; git -C "$sb/n9" update-ref -d refs/remotes/origin/main
git -C "$sb/n9" update-ref refs/remotes/github_y/main HEAD~1
printf '\ndef test_e():\n    assert 5\n' >> "$sb/n9/test_legacy.py"; commit "$sb/n9" add_e; git -C "$sb/n9" update-ref refs/remotes/github_x/main HEAD
run "$sb/g_new" "$sb/n9" --quiet
[ "$RC" = 1 ] && grep -q "evaluated against $(git -C "$sb/n9" rev-parse --short=12 HEAD~2)" <<<"$OUT"; chk $? "I3: oldest remote merge-base chosen (github_y lag keeps the range wide) (rc=$RC)"
# M4: a baseline entry for a vanished file is reported as stale even under --quiet
mkrepo "$sb/n10" 3; printf 'test_old_name.py\t4\n' >> "$sb/n10/config/oracle_ratchet_baseline.txt"; commit "$sb/n10" stale; markpushed "$sb/n10"
run "$sb/g_new" "$sb/n10" --quiet
[ "$RC" = 0 ] && grep -q 'stale baseline entry test_old_name.py' <<<"$OUT" && grep -q 'stale_entries=1' <<<"$OUT"; chk $? "M4: stale baseline entry (file renamed away) reported under --quiet (rc=$RC)"
run "$sb/g_new" "$sb/n10" --write-baseline; ! grep -q 'test_old_name' "$sb/n10/config/oracle_ratchet_baseline.txt"; chk $? "M4: --write-baseline prunes the stale entry"
# not a git repo: new-function check reported SKIPPED, count ratchet still enforced
mkdir -p "$sb/ng/config"; printf '%s' "$LEGACY" > "$sb/ng/test_legacy.py"; printf 'test_legacy.py\t3\n' > "$sb/ng/config/oracle_ratchet_baseline.txt"
run "$sb/g_new" "$sb/ng" --quiet
[ "$RC" = 0 ] && grep -q 'SKIPPED (not a git work tree)' <<<"$OUT"; chk $? "non-git root: new-function check explicitly SKIPPED, ratchet still PASS"
printf '\ndef test_e():\n    assert 5\n' >> "$sb/ng/test_legacy.py"
run "$sb/g_new" "$sb/ng" --quiet
[ "$RC" = 1 ]; chk $? "non-git root: count above baseline still FAILs"

# ── BLIND / config errors ------------------------------------------------------------------------------------------
mkrepo "$sb/b1" ""
run "$sb/g_new" "$sb/b1" --quiet
[ "$RC" = 2 ] && grep -q $'^ORACLE-VERDICT\tBLIND\tmode=ratchet\treason=baseline_missing' <<<"$OUT"; chk $? "missing baseline -> rc=2 BLIND, never a pass"
run "$sb/g_new" "$sb/b1" --quiet --strict
[ "$RC" = 1 ]; chk $? "--strict needs no baseline and keeps the legacy absolute behaviour (rc=1)"
mkrepo "$sb/b2" 3; printf 'test_legacy.py\tthree\n' > "$sb/b2/config/oracle_ratchet_baseline.txt"
run "$sb/g_new" "$sb/b2" --quiet; [ "$RC" = 2 ]; chk $? "chaos: non-integer baseline count -> rc=2 BLIND"
mkrepo "$sb/b3" 3; printf 'test_legacy.py\t3\ntest_legacy.py\t9\n' > "$sb/b3/config/oracle_ratchet_baseline.txt"
run "$sb/g_new" "$sb/b3" --quiet; [ "$RC" = 2 ]; chk $? "chaos: duplicate baseline entry (would hide a raise) -> rc=2 BLIND"
mkrepo "$sb/b4" 3; : > "$sb/b4/config/oracle_ratchet_baseline.txt"
run "$sb/g_new" "$sb/b4" --quiet; [ "$RC" = 1 ]; chk $? "chaos: empty baseline = ceiling 0 everywhere -> rc=1, not a pass"
mkrepo "$sb/b5" 3; chmod 000 "$sb/b5/config/oracle_ratchet_baseline.txt"
run "$sb/g_new" "$sb/b5" --quiet; [ "$RC" != 0 ]; chk $? "chaos: unreadable baseline never yields a pass (rc=$RC)"
chmod 600 "$sb/b5/config/oracle_ratchet_baseline.txt"

# ── security: hostile names and prose carriers -----------------------------------------------------------------------
mkrepo "$sb/s1" 3
mkdir -p "$sb/s1/dir;touch pwned"; printf 'def test_h():\n    # oracle: HUMAN\n    assert 1\n' > "$sb/s1/dir;touch pwned/test_h.py"; commit "$sb/s1" hostile
run "$sb/g_new" "$sb/s1" --quiet
[ "$RC" = 0 ] && [ ! -e "$sb/s1/pwned" ] && [ ! -e "$sb/pwned" ]; chk $? "security: hostile directory name executes nothing and is handled (rc=$RC)"
mkrepo "$sb/s2" 5
printf '\ndef test_e():\n    """Independent oracle: raw grep of the file"""\n    assert 5\n' >> "$sb/s2/test_legacy.py"; commit "$sb/s2" prose
run "$sb/g_new" "$sb/s2" --quiet
[ "$RC" = 1 ]; chk $? "security: prose 'Independent oracle: ...' is a carrier, not an annotation (new function still fails)"
mkrepo "$sb/s3" 3; printf '../../etc/passwd\t0\ntest_legacy.py\t3\n' > "$sb/s3/config/oracle_ratchet_baseline.txt"
run "$sb/g_new" "$sb/s3" --quiet; [ "$RC" = 0 ]; chk $? "security: traversal-looking baseline key is inert data (stale entry, no read outside the root)"

# ── adoption path: --adopt-new-files --reason (operator decision 2026-11-01) --------------------------------------------
pushorigin() { # $1 repo : bare origin in the sandbox, current HEAD pushed, upstream tracked
    git init -q --bare "$1.origin.git" 2>/dev/null; git -C "$1" remote add origin "$1.origin.git" 2>/dev/null
    git -C "$1" push -q -u origin HEAD:refs/heads/main >/dev/null 2>&1; git -C "$1" branch -q -u origin/main >/dev/null 2>&1; true
}
adoptrepo() { mkrepo "$1" 3; printf 'def test_n1():\n    assert 1\n\ndef test_n2():\n    assert 2\n' > "$1/test_newf.py"; commit "$1" newf; pushorigin "$1"; }
adoptrepo "$sb/a0"
run "$sb/g_new" "$sb/a0" --quiet
[ "$RC" = 1 ]; chk $? "adopt RED: unadopted new unannotated file FAILs the ratchet (rc=$RC)"
run "$sb/g_new" "$sb/a0" --adopt-new-files
[ "$RC" = 2 ] && ! grep -q 'test_newf' "$sb/a0/config/oracle_ratchet_baseline.txt" && [ ! -e "$sb/a0/config/oracle_ratchet_adoptions.log" ]; chk $? "adopt without --reason refused (rc=$RC), baseline and log untouched"
run "$sb/g_new" "$sb/a0" --adopt-new-files --reason "   "
[ "$RC" = 2 ] && ! grep -q 'test_newf' "$sb/a0/config/oracle_ratchet_baseline.txt"; chk $? "adopt with blank --reason refused (rc=$RC)"
run "$sb/g_new" "$sb/a0" --reason "x"
[ "$RC" = 2 ]; chk $? "--reason without --adopt-new-files refused (rc=$RC)"
run "$sb/g_new" "$sb/a0" --adopt-new-files --write-baseline --reason "x"
[ "$RC" = 2 ]; chk $? "adopt combined with --write-baseline refused (rc=$RC)"
run "$sb/g_new" "$sb/a0" --adopt-new-files --reason "operator decision test"
[ "$RC" = 0 ] && grep -q $'^test_newf.py\t2$' "$sb/a0/config/oracle_ratchet_baseline.txt" && grep -q $'^test_legacy.py\t3$' "$sb/a0/config/oracle_ratchet_baseline.txt"; chk $? "adopt adds new file at today's count, existing entry unchanged (rc=$RC)"
grep -q $'^[0-9-]\{10\}\tfiles=1\tadded=2\treason=operator decision test\tbase=[0-9a-f]\{7,\}\tlimit=submodule_contents_not_diffed$' "$sb/a0/config/oracle_ratchet_adoptions.log"; chk $? "adoption log line: date, file count, total added, reason"
run "$sb/g_new" "$sb/a0" --quiet
[ "$RC" = 0 ]; chk $? "after adoption the default ratchet PASSes (rc=$RC)"
h1=$(sha256sum "$sb/a0/config/oracle_ratchet_baseline.txt"); run "$sb/g_new" "$sb/a0" --adopt-new-files --reason again; h2=$(sha256sum "$sb/a0/config/oracle_ratchet_baseline.txt")
[ "$RC" = 0 ] && [ "$h1" = "$h2" ] && [ "$(wc -l < "$sb/a0/config/oracle_ratchet_adoptions.log")" = 1 ]; chk $? "idempotent: second adoption is a no-op (no baseline change, no new log line)"
printf 'def test_n3():\n    assert 3\n' > "$sb/a0/test_later.py"; commit "$sb/a0" later
run "$sb/g_new" "$sb/a0" --quiet
[ "$RC" = 1 ]; chk $? "ratchet still FAILs afterwards on a new unannotated test file (rc=$RC)"
printf '\ndef test_n4():\n    assert 4\n' >> "$sb/a0/test_newf.py"; commit "$sb/a0" grow; markpushed "$sb/a0"
run "$sb/g_new" "$sb/a0" --quiet
[ "$RC" = 1 ]; chk $? "ratchet FAILs when an adopted file grows (rc=$RC)"
# adoption cannot raise an existing file
adoptrepo "$sb/a1"
printf '\ndef test_e():\n    assert 5\n' >> "$sb/a1/test_legacy.py"; commit "$sb/a1" add_e
run "$sb/g_new" "$sb/a1" --adopt-new-files --reason "try to hide a raise"
[ "$RC" = 1 ] && grep -q 'adoption refused' <<<"$OUT" && ! grep -q 'test_newf' "$sb/a1/config/oracle_ratchet_baseline.txt" && [ ! -e "$sb/a1/config/oracle_ratchet_adoptions.log" ] && grep -q $'^test_legacy.py\t3$' "$sb/a1/config/oracle_ratchet_baseline.txt"; chk $? "adoption cannot raise an existing file: refused rc=$RC, nothing written"
# existing higher baseline is not lowered by adoption
adoptrepo "$sb/a2"; printf 'test_legacy.py\t9\n' > "$sb/a2/config/oracle_ratchet_baseline.txt"
run "$sb/g_new" "$sb/a2" --adopt-new-files --reason keep
[ "$RC" = 0 ] && grep -q $'^test_legacy.py\t9$' "$sb/a2/config/oracle_ratchet_baseline.txt"; chk $? "adoption does not lower an existing entry (9 stays 9)"
# missing baseline: adoption refused
mkrepo "$sb/a3" ""; run "$sb/g_new" "$sb/a3" --adopt-new-files --reason x
[ "$RC" = 2 ] && [ ! -e "$sb/a3/config/oracle_ratchet_baseline.txt" ]; chk $? "adoption without an existing baseline refused (rc=$RC)"
# F2 (review 2026-11-01): adoption must not legalise unannotated NEW/MODIFIED functions, and the rule-(3) base must not slide
mkrepo "$sb/f2a" 3; pushorigin "$sb/f2a"
printf 'def test_sneak():\n    assert 9\n' > "$sb/f2a/test_sneak.py"; commit "$sb/f2a" sneak
run "$sb/g_new" "$sb/f2a" --adopt-new-files --reason "sneak committed-unpushed"
[ "$RC" = 1 ] && ! grep -q 'test_sneak' "$sb/f2a/config/oracle_ratchet_baseline.txt" && [ ! -e "$sb/f2a/config/oracle_ratchet_adoptions.log" ]; chk $? "F2 RED: committed-but-unpushed unannotated new test cannot be adopted (rc=$RC)"
for i in 1 2; do "${GIT[@]}" -C "$sb/f2a" commit -q --allow-empty -m "empty$i" >/dev/null 2>&1; done
run "$sb/g_new" "$sb/f2a" --adopt-new-files --reason "sneak after empty commits"
[ "$RC" = 1 ] && ! grep -q 'test_sneak' "$sb/f2a/config/oracle_ratchet_baseline.txt"; chk $? "F2 empty commits do not slide the adoption base (rc=$RC)"
mkrepo "$sb/f2b" 3; pushorigin "$sb/f2b"
printf 'def test_wt():\n    assert 9\n' > "$sb/f2b/test_wt.py"
run "$sb/g_new" "$sb/f2b" --adopt-new-files --reason "sneak untracked"
[ "$RC" = 1 ] && ! grep -q 'test_wt' "$sb/f2b/config/oracle_ratchet_baseline.txt"; chk $? "F2 untracked new unannotated test cannot be adopted (rc=$RC)"
# modified function of an UNBASELINED file also refused: legacy file with no entry, edited in the worktree
mkrepo "$sb/f2c" ""; printf 'x\t0\n' > "$sb/f2c/config/oracle_ratchet_baseline.txt"; commit "$sb/f2c" bl; pushorigin "$sb/f2c"
printf '    assert 99\n' >> "$sb/f2c/test_legacy.py"
run "$sb/g_new" "$sb/f2c" --adopt-new-files --reason "edit legacy"
[ "$RC" = 1 ] && ! grep -q 'test_legacy' "$sb/f2c/config/oracle_ratchet_baseline.txt"; chk $? "F2 modified legacy functions of an unbaselined file cannot be adopted (rc=$RC)"
# --adopt-new-files forbids --base (I2): adopting a new unannotated file with --base HEAD is refused, nothing written
adoptrepo "$sb/i2a"; printf 'def test_slide():\n    assert 1\n' > "$sb/i2a/test_slide.py"; commit "$sb/i2a" slide
run "$sb/g_new" "$sb/i2a" --adopt-new-files --reason r --base HEAD
[ "$RC" = 2 ] && ! grep -q 'test_slide' "$sb/i2a/config/oracle_ratchet_baseline.txt" && [ ! -e "$sb/i2a/config/oracle_ratchet_adoptions.log" ]; chk $? "I2: --adopt-new-files --base HEAD refused rc=2, baseline and log untouched (rc=$RC)"
OUT=$(cd "$sb" && ORACLE_GUARD_BASE=HEAD nice -n 15 bash "$sb/g_new/scripts/gates/$OR.sh" --root "$sb/i2a" --adopt-new-files --reason r 2>&1); RC=$?
[ "$RC" = 1 ] && ! grep -q 'test_slide' "$sb/i2a/config/oracle_ratchet_baseline.txt"; chk $? "I2: ambient ORACLE_GUARD_BASE=HEAD cannot make adoption accept a new unannotated file (rc=$RC)"
# no upstream and no --base: no non-sliding base -> refused rc=2
mkrepo "$sb/f2d" 3; git -C "$sb/f2d" update-ref -d refs/remotes/origin/main; printf 'def test_o():\n    assert 1\n' > "$sb/f2d/test_o.py"; commit "$sb/f2d" o
run "$sb/g_new" "$sb/f2d" --adopt-new-files --reason "no upstream"
[ "$RC" = 2 ] && grep -q 'non-sliding base' <<<"$OUT" && ! grep -q 'test_o' "$sb/f2d/config/oracle_ratchet_baseline.txt"; chk $? "F2 adoption without an upstream and without --base refused (rc=$RC)"
# rule (3) default base does not slide with empty commits (unpushed new unannotated function in a file with slack)
mkrepo "$sb/f2e" 9; pushorigin "$sb/f2e"
printf '\ndef test_e():\n    assert 5\n' >> "$sb/f2e/test_legacy.py"; commit "$sb/f2e" e
run "$sb/g_new" "$sb/f2e" --quiet; r1=$RC
for i in 1 2 3; do "${GIT[@]}" -C "$sb/f2e" commit -q --allow-empty -m "empty$i" >/dev/null 2>&1; done
run "$sb/g_new" "$sb/f2e" --quiet
[ "$r1" = 1 ] && [ "$RC" = 1 ]; chk $? "F2 rule (3) still FAILs the unpushed new function after empty commits (rc $r1 then $RC)"
# §1.1 mutants of the adoption path
mkgate "$sb/g_am1" "$src/scripts/gates/$OR.sh" 's/\[ -z "\$_r" \] \|\| //'
adoptrepo "$sb/a4"; run "$sb/g_am1" "$sb/a4" --adopt-new-files --reason " "
[ "$RC" != 2 ]; chk $? "§1.1 mutation: blank-reason guard removed -> adoption proceeds (mutant detectable)"
mkgate "$sb/g_am2" "$src/scripts/gates/$OR.sh" 's/if \[ "\$\{cnt\[\$rel\]\}" -gt "\$\{base\[\$rel\]\}" \]; then up=/if false; then up=/'
adoptrepo "$sb/a5"; printf '\ndef test_e():\n    assert 5\n' >> "$sb/a5/test_legacy.py"; commit "$sb/a5" add_e
run "$sb/g_am2" "$sb/a5" --adopt-new-files --reason x
[ "$RC" = 0 ]; chk $? "§1.1 mutation: raise-guard removed -> adoption would pass with an over-baseline file (mutant detectable)"
mkgate "$sb/g_am3" "$src/scripts/gates/$OR.sh" 's/newent\["\$rel"\]="\$\{cnt\[\$rel\]\}"/newent["$rel"]=0/'
adoptrepo "$sb/a6"; run "$sb/g_am3" "$sb/a6" --adopt-new-files --reason x; run "$sb/g_am3" "$sb/a6" --quiet
[ "$RC" = 1 ]; chk $? "§1.1 mutation: adoption records a too-low count -> ratchet still FAILs (mutant detectable)"

# F2 mutants
mkgate "$sb/g_am4" "$src/scripts/gates/$OR.sh" 's/\[ "\$\{newcnt\[\$rel\]:-0\}" -gt 0 \]/[ 0 -gt 0 ]/'
mkrepo "$sb/f2m1" 3; pushorigin "$sb/f2m1"; printf 'def test_sneak():\n    assert 9\n' > "$sb/f2m1/test_sneak.py"; commit "$sb/f2m1" sneak
run "$sb/g_am4" "$sb/f2m1" --adopt-new-files --reason x
[ "$RC" = 0 ]; chk $? "§1.1 mutation: new-function adoption refusal removed -> sneak adopted (mutant detectable)"
mkgate "$sb/g_am5" "$src/scripts/gates/$OR.sh" 's/^        base_ref="\$nsb"$/        base_ref="HEAD~1"/'
mkrepo "$sb/f2m2" 9; pushorigin "$sb/f2m2"; printf '\ndef test_e():\n    assert 5\n' >> "$sb/f2m2/test_legacy.py"; commit "$sb/f2m2" e
for i in 1 2 3; do "${GIT[@]}" -C "$sb/f2m2" commit -q --allow-empty -m "empty$i" >/dev/null 2>&1; done
run "$sb/g_am5" "$sb/f2m2" --quiet
[ "$RC" = 0 ]; chk $? "§1.1 mutation: sliding HEAD~1 base restored -> empty commits hide the new function (mutant detectable)"

# ── determinism x3, idempotency, concurrency, performance ---------------------------------------------------------------
t0=$(date +%s%N); hs=""
for i in 1 2 3; do run "$sb/g_new" "$sb/n1" --quiet; hs="$hs $(printf '%s\n%s' "$RC" "$OUT" | sha256sum | cut -c1-16)"; done
t1=$(date +%s%N)
[ "$(printf '%s\n' $hs | sort -u | wc -l)" = 1 ]; chk $? "determinism: 3 identical outputs ($hs )"
[ $(( (t1 - t0) / 1000000 )) -lt 30000 ]; chk $? "performance: 3 ratchet runs in $(( (t1 - t0) / 1000000 )) ms (< 30 s budget)"
before=$(cd "$sb/n1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
run "$sb/g_new" "$sb/n1" --quiet
after=$(cd "$sb/n1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
[ "$before" = "$after" ]; chk $? "idempotency: a gate run writes nothing into the scanned repo"
( for i in 1 2 3 4; do run "$sb/g_new" "$sb/n1" --quiet; printf '%s\n' "$RC"; done ) | sort -u > "$sb/conc.out" &
( run "$sb/g_new" "$sb/n2" --quiet; echo $RC >> "$sb/conc2.out" ) &
wait
[ "$(cat "$sb/conc.out")" = 1 ]; chk $? "chaos: concurrent runs agree"

# ── e2e canon root (working-tree prune lib; expected total derived from the same lib via the baseline) -----------------
cb="$src/config/oracle_ratchet_baseline.txt"
if [ -f "$cb" ]; then
    tot=$(awk -F'\t' '!/^#/ && NF==2 {s+=$2} END{print s+0}' "$cb")
    run "$sb/g_new" "$src" --quiet
    [ "$RC" = 0 ] && grep -q "ratchet total=$tot " <<<"$OUT"; chk $? "e2e canon root: ratchet PASS with live total == baseline total ($tot) (rc=$RC)"
    run "$sb/g_new" "$src" --quiet --strict
    grep -q "FAIL — $tot test function" <<<"$OUT"; chk $? "e2e canon root: strict mode count == baseline total ($tot)"
else
    bad "canon baseline $cb missing"
fi
# consumer-shaped: canon vendored as a submodule of a consumer -> baseline missing in the consumer = BLIND
mkdir -p "$sb/cons"; git -C "$sb/cons" init -q; printf 'def test_c():\n    assert 1\n' > "$sb/cons/test_c.py"; commit "$sb/cons" init
run "$sb/g_new" "$sb/cons" --quiet
[ "$RC" = 2 ]; chk $? "consumer-shaped root without a baseline -> rc=2 BLIND"
markpushed "$sb/cons"; run "$sb/g_new" "$sb/cons" --quiet --write-baseline; run "$sb/g_new" "$sb/cons" --quiet
[ "$RC" = 0 ]; chk $? "consumer adopts: --write-baseline then ratchet PASS (rc=$RC)"

# ── B1 (delta review 2026-11-03): a trailing `# oracle:` on the LAST BODY LINE of one test is not the NEXT test's annotation ──
mkdir -p "$sb/b1a" "$sb/b1b" "$sb/b1c" "$sb/b1d"
printf 'def test_a():\n    assert 1  # oracle: SPECIFIED\ndef test_b():\n    assert 2\n' > "$sb/b1a/test_x.py"
run "$sb/g_new" "$sb/b1a" --strict
[ "$RC" != 0 ] && grep -q $'\tunannotated=1\t\|unannotated=1' <<<"$OUT"; chk $? "B1 RED->GREEN: top-level test_b right after test_a's trailing annotation is NOT annotated under --strict (rc=$RC)"
printf 'class T:\n    def test_a(self):\n        assert 1  # oracle: SPECIFIED\n    def test_b(self):\n        assert 2\n' > "$sb/b1b/test_x.py"
run "$sb/g_new" "$sb/b1b" --strict
[ "$RC" != 0 ] && grep -q 'unannotated=1' <<<"$OUT"; chk $? "B1: method test_b inside a class is NOT annotated by test_a's trailing annotation (rc=$RC)"
# golden-FALSE: genuine comment-only annotation directly above the def, with a decorator in between, still counts
printf 'def test_a():\n    assert 1  # oracle: SPECIFIED\n# oracle: DERIVED\n@deco\ndef test_b():\n    assert 2\n# oracle: HUMAN\ndef test_c():\n    assert 3\ndef test_d():  # oracle: INVARIANT\n    assert 4\n' > "$sb/b1c/test_x.py"
run "$sb/g_new" "$sb/b1c" --strict
[ "$RC" = 0 ] && grep -q 'unannotated=0' <<<"$OUT"; chk $? "B1 golden-FALSE: comment-only/decorator-prefixed/inline-def-line annotations still count (rc=$RC)"
# CRLF source: a present annotation is recognised
printf 'def test_a():\r\n    # oracle: SPECIFIED\r\n    assert 1\r\n' > "$sb/b1d/test_x.py"
run "$sb/g_new" "$sb/b1d" --strict
[ "$RC" = 0 ] && grep -q 'unannotated=0' <<<"$OUT"; chk $? "B1 CRLF: annotation in a CRLF file is recognised (rc=$RC)"
mkgate "$sb/g_b1crlf" "$src/scripts/gates/$OR.sh" 's#sub\(/\\r\$/, ""\); ##'
cmp -s "$sb/g_b1crlf/scripts/gates/$OR.sh" "$src/scripts/gates/$OR.sh" && bad "B1 CRLF mutation did not apply"
run "$sb/g_b1crlf" "$sb/b1d" --strict
[ "$RC" != 0 ]; chk $? "B1 CRLF §1.1 mutation: \\r not stripped -> annotation missed (mutant detectable, rc=$RC)"
# rule 3 false flag: editing ONLY test_a's last line must not mark the adjacent test_b modified
mkrepo "$sb/b1e" ""
printf 'def test_a():\n    assert 1  # oracle: SPECIFIED\ndef test_b():\n    assert 2\n' > "$sb/b1e/test_legacy.py"
printf '# baseline\ntest_legacy.py\t1\n' > "$sb/b1e/config/oracle_ratchet_baseline.txt"
commit "$sb/b1e" fixture; markpushed "$sb/b1e"
sed -i 's/assert 1  # oracle/assert 1 == 1  # oracle/' "$sb/b1e/test_legacy.py"; commit "$sb/b1e" edit_a
run "$sb/g_new" "$sb/b1e" --quiet
[ "$RC" = 0 ] && grep -q 'new_or_modified_unannotated=0' <<<"$OUT"; chk $? "B1 rule 3: editing only test_a's last line does not flag the unannotated neighbour test_b (rc=$RC)"
# paired mutation: the above-def zone reverts to "stop only at blank/def/class" -> B1 fixtures flip
mkgate "$sb/g_b1m" "$src/scripts/gates/$OR.sh" 's#if \(raw !~ /\^\[ \\t\]\*\[\#@\]/\) return 0#if (raw ~ /^[ \\t]*$/) return 0#; s#return lead\(raw\) == di#return 1#'
cmp -s "$sb/g_b1m/scripts/gates/$OR.sh" "$src/scripts/gates/$OR.sh" && bad "B1 mutation did not apply"
run "$sb/g_b1m" "$sb/b1a" --strict
[ "$RC" = 0 ]; chk $? "B1 §1.1 mutation: above-def zone reverted -> false PASS returns (mutant detectable, rc=$RC)"
# window-only mutant (the annotation scan stays fixed): the 3-line window reaches into the previous test body again
mkgate "$sb/g_b1w" "$src/scripts/gates/$OR.sh"
python3 - "$sb/g_b1w/scripts/gates/$OR.sh" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
a="if (!above_ok(kl, indent)) break\n                    wstart = k"
assert a in s; open(p,"w").write(s.replace(a,"if (kl ~ /^[ \\t]*$/) break\n                    wstart = k"))
PY
run "$sb/g_b1w" "$sb/b1e" --quiet
[ "$RC" = 1 ]; chk $? "B1 §1.1 mutation: window reaches into the prior body -> rule-3 false flag returns (mutant detectable, rc=$RC)"

# ── paired §1.1 mutations of the oracle gate ----------------------------------------------------------------------------
mut() { # name sed-expr ; builds a mutant gate and returns via MG
    mkgate "$sb/m_$1" "$src/scripts/gates/$OR.sh" "$2"; MG="$sb/m_$1"
    cmp -s "$sb/m_$1/scripts/gates/$OR.sh" "$src/scripts/gates/$OR.sh" && { bad "mutation $1 did not apply"; return 1; }; return 0
}
if mut over 's/\[ "\$\{cnt\[\$rel\]\}" -gt "\$b" \]/[ "${cnt[$rel]}" -gt 999999 ]/'; then
    run "$MG" "$sb/r_over" --quiet; [ "$RC" = 0 ]; chk $? "§1.1 mutation: baseline comparison neutralised -> the over-baseline case flips to PASS (mutant detectable)"
fi
if mut newchk 's/isnew = "NEW"; break/isnew = "OLD"; break/'; then
    run "$MG" "$sb/n1" --quiet; [ "$RC" = 0 ]; chk $? "§1.1 mutation: new-function check disabled -> the new-function case flips to PASS"
fi
if mut missing 's/elif \[ "\$write_baseline" != 1 \]; then/elif false; then/'; then
    run "$MG" "$sb/b1" --quiet; [ "$RC" != 2 ]; chk $? "§1.1 mutation: missing-baseline guard removed -> no longer BLIND (rc=$RC)"
fi
if mut raise 's/\[ "\$have_base" = 1 \] \|\| break/:/; s/if \[ "\$\{cnt\[\$rel\]\}" -gt "\$b" \]; then up=/if false; then up=/'; then
    printf '\ndef test_q():\n    assert 1\n' >> "$sb/r_eq/test_legacy.py"
    run "$MG" "$sb/r_eq" --write-baseline; [ "$RC" = 0 ]; chk $? "§1.1 mutation: raise-guard removed -> --write-baseline raises the baseline (mutant detectable)"
fi

# canon marker (round 3, M1): Constitution.md with the anchor heading AND scripts/gates -- an empty file named Constitution.md is not a canon
canonmark() { mkdir -p "$1/scripts/gates"; : > "$1/scripts/gates/.keep"; printf '# Constitution\n\n### §11.4.1 — FAIL-bluffs are equally forbidden\n' > "$1/Constitution.md"; }
# round 3 mutants: I2 (newer --base accepted) and I3 (only origin searched)
if mut i2 's/ \|\| ! git -C "\$root" merge-base --is-ancestor "\$_bs" "\$nsb" 2>\/dev\/null//'; then
    run "$MG" "$sb/n7" --quiet --base HEAD; [ "$RC" != 2 ]; chk $? "§1.1 mutation: newer-than-nonsliding --base accepted -> the I2 refusal test flips (mutant detectable, rc=$RC)"
fi
if mut i3 "s#'refs/remotes/\*/main' 'refs/remotes/\*/master'#'refs/remotes/origin/main'#"; then
    run "$MG" "$sb/n8" --quiet; git -C "$sb/n8" update-ref refs/remotes/github_x/main HEAD~3; run "$MG" "$sb/n8" --quiet; [ "$RC" = 2 ]; chk $? "§1.1 mutation: only origin searched -> github_x-only checkout goes BLIND (mutant detectable, rc=$RC)"
fi

# ═══ (B) consumer-only gates: standalone-canon honest SKIP ═══════════════════════════════════════════════════════════
OD=cm_opendesign_ui_system; CG=cm_codegraph_mcp_health
gd="$sb/gb"; mkdir -p "$gd/scripts/gates" "$gd/scripts/lib" "$gd/scripts/codegraph"
cp "$src/scripts/gates/$OD.sh" "$src/scripts/gates/$CG.sh" "$gd/scripts/gates/"
cp "$src/scripts/lib/default_scan_root.sh" "$gd/scripts/lib/"
cp "$src/scripts/codegraph/codegraph_mcp_health.py" "$gd/scripts/codegraph/"
odrun() { OUT=$(cd "$sb" && bash "$gd/scripts/gates/$OD.sh" --root "$1" "${@:2}" 2>&1); RC=$?; }
cgrun() { OUT=$(cd "$sb" && bash "$gd/scripts/gates/$CG.sh" --project "$1" "${@:2}" 2>&1); RC=$?; }

# OpenDesign: canon-like (hex theme sources, no token artifact, no OpenDesign manifest, light+dark words)
mkdir -p "$sb/odc/styles" "$sb/odc/tests/visual"; printf '.a{color:#112233} /* light */ /* dark */\n' > "$sb/odc/styles/s.css"; : > "$sb/odc/tests/visual/x"; canonmark "$sb/odc"
odrun "$sb/odc"
[ "$RC" = 1 ]; chk $? "RED: canon-like root without the declaration fails closed (rc=$RC)"
odrun "$sb/odc" --standalone-canon
[ "$RC" = 3 ] && grep -q $'^OD-VERDICT\tSKIP\treason=topology_unsupported' <<<"$OUT"; chk $? "GREEN: --standalone-canon -> honest SKIP rc=3 + VERDICT topology_unsupported"
# the same flag must NOT hide a real consumer violation
mkdir -p "$sb/odk/styles"; printf '.a{color:#112233} /* light */\n' > "$sb/odk/styles/s.css"; printf '{"tokens":{}}\n' > "$sb/odk/tokens.json"; canonmark "$sb/odk"
odrun "$sb/odk" --standalone-canon
[ "$RC" = 1 ] && ! grep -q 'OD-VERDICT.SKIP' <<<"$OUT"; chk $? "chaos/dual: token artifact present + flag -> audited, still FAILs (rc=$RC)"
mkdir -p "$sb/odm/styles"; printf '.a{color:#112233}\n' > "$sb/odm/styles/s.css"; printf '{"dependencies":{"open-design":"1"}}\n' > "$sb/odm/package.json"; canonmark "$sb/odm"
odrun "$sb/odm" --standalone-canon
[ "$RC" = 1 ] && ! grep -q 'OD-VERDICT.SKIP' <<<"$OUT"; chk $? "dual: OpenDesign declared in a manifest + flag -> audited, still FAILs (rc=$RC)"
# clean consumer passes and flag does not change that
mkdir -p "$sb/odp/styles" "$sb/odp/tests/visual"; printf '.a{color:var(--c)} /* light */ /* dark */\n' > "$sb/odp/styles/s.css"; printf '{}\n' > "$sb/odp/tokens.json"; printf '{"dependencies":{"open-design":"1"}}\n' > "$sb/odp/package.json"; : > "$sb/odp/tests/visual/x"; canonmark "$sb/odp"
odrun "$sb/odp" --standalone-canon; [ "$RC" = 0 ] && grep -q $'^OD-VERDICT\tPASS' <<<"$OUT"; chk $? "golden-FALSE: clean token-bound consumer + flag -> PASS (rc=$RC)"
# security: ambient env cannot turn FAIL into SKIP; hostile root name
OUT=$(cd "$sb" && STANDALONE_CANON=1 OD_STANDALONE_CANON=1 bash "$gd/scripts/gates/$OD.sh" --root "$sb/odc" 2>&1); RC=$?
[ "$RC" = 1 ]; chk $? "security: no environment opt-in exists (ambient variables do not SKIP)"
mkdir -p "$sb/od h;x/styles"; canonmark "$sb/od h;x"; printf '.a{color:#112233}\n' > "$sb/od h;x/styles/s.css"; odrun "$sb/od h;x" --standalone-canon
[ "$RC" = 3 ] && [ ! -e "$sb/od h" ] || [ "$RC" = 3 ]; chk $? "security: hostile root name handled (rc=$RC)"
# determinism x3 + idempotency
hs=""; for i in 1 2 3; do odrun "$sb/odc" --standalone-canon; hs="$hs $(printf '%s\n%s' "$RC" "$OUT" | sha256sum | cut -c1-12)"; done
[ "$(printf '%s\n' $hs | sort -u | wc -l)" = 1 ]; chk $? "determinism: OpenDesign SKIP output identical x3"

# CodeGraph: canon-like = an index database but NO .mcp.json (the real canon on a host that indexed it)
mkdir -p "$sb/cgc/.codegraph"; printf 'x' > "$sb/cgc/.codegraph/codegraph.db"; canonmark "$sb/cgc"
cgrun "$sb/cgc"
[ "$RC" != 0 ] && [ "$RC" != 3 ]; chk $? "RED: canon-like project with an index but no declared MCP server fails closed without the declaration (rc=$RC)"
cgrun "$sb/cgc" --standalone-canon
[ "$RC" = 3 ] && grep -q $'^CG-VERDICT\tSKIP\treason=topology_unsupported' <<<"$OUT"; chk $? "GREEN: --standalone-canon -> honest SKIP rc=3 + VERDICT topology_unsupported"
# consumer that HAS the surface (.mcp.json) but violates it (wrapper path missing) still FAILs with the flag
mkdir -p "$sb/cgk/.codegraph"; printf 'x' > "$sb/cgk/.codegraph/codegraph.db"; canonmark "$sb/cgk"
printf '{"mcpServers":{"codegraph":{"command":"bash","args":["%s/nowhere/codegraph_mcp.sh"]}}}\n' "$sb" > "$sb/cgk/.mcp.json"
cgrun "$sb/cgk" --standalone-canon
[ "$RC" = 1 ] && ! grep -q 'CG-VERDICT.SKIP' <<<"$OUT"; chk $? "dual: .mcp.json present + flag -> audited, violation still FAILs (rc=$RC)"
# --mcp-json pointing at an existing file wins over the declaration too
printf '{"mcpServers":{"codegraph":{"command":"bash","args":["%s/nowhere/w.sh"]}}}\n' "$sb" > "$sb/alt.json"
cgrun "$sb/cgc" --standalone-canon --mcp-json "$sb/alt.json"
[ "$RC" = 1 ]; chk $? "dual: explicit --mcp-json file + flag -> audited (rc=$RC)"
# ambient env opt-in absent
OUT=$(cd "$sb" && STANDALONE_CANON=1 bash "$gd/scripts/gates/$CG.sh" --project "$sb/cgc" 2>&1); RC=$?
[ "$RC" != 3 ]; chk $? "security: no environment opt-in for the CodeGraph SKIP"
hs=""; for i in 1 2 3; do cgrun "$sb/cgc" --standalone-canon; hs="$hs $(printf '%s\n%s' "$RC" "$OUT" | sha256sum | cut -c1-12)"; done
[ "$(printf '%s\n' $hs | sort -u | wc -l)" = 1 ]; chk $? "determinism: CodeGraph SKIP output identical x3"

# F5 (review 2026-11-01): --standalone-canon requires canon identity (Constitution.md at the root, root not a vendored submodule)
mkdir -p "$sb/od_nc/styles" "$sb/cg_nc/.codegraph"; printf '.a{color:#112233}\n' > "$sb/od_nc/styles/s.css"; printf 'x' > "$sb/cg_nc/.codegraph/codegraph.db"
odrun "$sb/od_nc" --standalone-canon
[ "$RC" = 2 ] && ! grep -q 'OD-VERDICT.SKIP' <<<"$OUT"; chk $? "F5 RED: --standalone-canon on a non-canon root (no Constitution.md) refused, not SKIP (od rc=$RC)"
cgrun "$sb/cg_nc" --standalone-canon
[ "$RC" = 2 ] && ! grep -q 'CG-VERDICT.SKIP' <<<"$OUT"; chk $? "F5 RED: --standalone-canon on a non-canon project (no Constitution.md) refused, not SKIP (cg rc=$RC)"
# a vendored canon (Constitution.md present but root is a submodule of a superproject) is not a canon root either
vend_sub() { # $1 = dir that becomes a submodule of a throwaway superproject
    local sup="$1.super" sm="$1.smsrc"
    git init -q "$sm"; canonmark "$sm"; mkdir -p "$sm/styles" "$sm/.codegraph"; printf '.a{color:#112233}\n' > "$sm/styles/s.css"; printf 'x' > "$sm/.codegraph/codegraph.db"
    "${GIT[@]}" -C "$sm" add -A >/dev/null 2>&1; "${GIT[@]}" -C "$sm" commit -qm i >/dev/null 2>&1
    git init -q "$sup"; "${GIT[@]}" -C "$sup" -c protocol.file.allow=always submodule add -q "$sm" constitution >/dev/null 2>&1
}
vend_sub "$sb/vd"
odrun "$sb/vd.super/constitution" --standalone-canon
[ "$RC" = 2 ] && ! grep -q 'OD-VERDICT.SKIP' <<<"$OUT"; chk $? "F5 vendored canon (submodule of a consumer) is not a canon root: refused (od rc=$RC)"
cgrun "$sb/vd.super/constitution" --standalone-canon
[ "$RC" = 2 ] && ! grep -q 'CG-VERDICT.SKIP' <<<"$OUT"; chk $? "F5 vendored canon refused (cg rc=$RC)"
# M1 (round 3): an EMPTY / stray Constitution.md (no anchor heading, no scripts/gates) is not a canon marker
mkdir -p "$sb/od_em/styles"; printf '.a{color:#112233}\n' > "$sb/od_em/styles/s.css"; : > "$sb/od_em/Constitution.md"
odrun "$sb/od_em" --standalone-canon
[ "$RC" = 2 ] && ! grep -q 'OD-VERDICT.SKIP' <<<"$OUT"; chk $? "M1 RED: empty Constitution.md is not a canon marker: refused (od rc=$RC)"
mkdir -p "$sb/od_hd/styles" "$sb/od_hd/scripts/gates"; printf '.a{color:#112233}\n' > "$sb/od_hd/styles/s.css"; printf '### §11.4.1 — x\n' > "$sb/od_hd/Constitution.md"; rm -rf "$sb/od_hd/scripts"
odrun "$sb/od_hd" --standalone-canon
[ "$RC" = 2 ]; chk $? "M1: heading but no scripts/gates is not a canon marker (rc=$RC)"
cp -r "$gd" "$sb/gb_m7"; sed -i "s/ \&\& \[ -d \"\$d\/scripts\/gates\" \] || return 1/ || return 1/; /grep -q -m1 -E/d" "$sb/gb_m7/scripts/lib/default_scan_root.sh"
OUT=$(cd "$sb" && bash "$sb/gb_m7/scripts/gates/$OD.sh" --root "$sb/od_em" --standalone-canon 2>&1); RC=$?
[ "$RC" = 3 ]; chk $? "§1.1 mutation: strong canon marker removed -> empty Constitution.md SKIPs (mutant detectable, rc=$RC)"
# §1.1 mutations of the two gates
cp -r "$gd" "$sb/gb_m1"; sed -i 's/\[ "\$standalone_decl" = 1 \]; then/[ "$standalone_decl" = 99 ]; then/' "$sb/gb_m1/scripts/gates/$OD.sh"
OUT=$(cd "$sb" && bash "$sb/gb_m1/scripts/gates/$OD.sh" --root "$sb/odc" --standalone-canon 2>&1); RC=$?
[ "$RC" != 3 ]; chk $? "§1.1 mutation: OpenDesign SKIP branch disabled -> no SKIP (mutant detectable)"
cp -r "$gd" "$sb/gb_m2"; sed -i 's/if \[ ! -f "\$mcp_json" \]; then/if true; then/' "$sb/gb_m2/scripts/gates/$CG.sh"
OUT=$(cd "$sb" && bash "$sb/gb_m2/scripts/gates/$CG.sh" --project "$sb/cgk" --standalone-canon 2>&1); RC=$?
[ "$RC" = 3 ]; chk $? "§1.1 mutation: CodeGraph SKIP made unconditional -> hides the consumer violation (mutant detectable, rc=$RC)"
cp -r "$gd" "$sb/gb_m3"; sed -i 's/\[ -z "\$od_manifest_decl" \]/true/' "$sb/gb_m3/scripts/gates/$OD.sh"
OUT=$(cd "$sb" && bash "$sb/gb_m3/scripts/gates/$OD.sh" --root "$sb/odm" --standalone-canon 2>&1); RC=$?
[ "$RC" = 3 ]; chk $? "§1.1 mutation: manifest-declaration guard removed -> hides a declared-OpenDesign violation (mutant detectable)"

cp -r "$gd" "$sb/gb_m4"; sed -i 's/cm_is_canon_root "\$root"/true/' "$sb/gb_m4/scripts/gates/$OD.sh"
OUT=$(cd "$sb" && bash "$sb/gb_m4/scripts/gates/$OD.sh" --root "$sb/od_nc" --standalone-canon 2>&1); RC=$?
[ "$RC" = 3 ]; chk $? "§1.1 mutation: OpenDesign canon-identity check removed -> non-canon root SKIPs (mutant detectable)"
cp -r "$gd" "$sb/gb_m5"; sed -i 's/cm_is_canon_root "\$proj_dir"/true/' "$sb/gb_m5/scripts/gates/$CG.sh"
OUT=$(cd "$sb" && bash "$sb/gb_m5/scripts/gates/$CG.sh" --project "$sb/cg_nc" --standalone-canon 2>&1); RC=$?
[ "$RC" = 3 ]; chk $? "§1.1 mutation: CodeGraph canon-identity check removed -> non-canon project SKIPs (mutant detectable)"
cp -r "$gd" "$sb/gb_m6"; sed -i 's/\[ -z "\$super" \] || return 1/:/' "$sb/gb_m6/scripts/lib/default_scan_root.sh"
OUT=$(cd "$sb" && bash "$sb/gb_m6/scripts/gates/$OD.sh" --root "$sb/vd.super/constitution" --standalone-canon 2>&1); RC=$?
[ "$RC" = 3 ]; chk $? "§1.1 mutation: vendored-submodule exclusion removed -> vendored canon SKIPs (mutant detectable)"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
