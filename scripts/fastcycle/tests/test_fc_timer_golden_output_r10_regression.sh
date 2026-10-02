#!/bin/bash
# T048 round-10 independent review findings regression guard for
# test_fc_timer_golden_output.sh (round-11 remediation).
#
# R10-B1 (Blocking, verbatim): "the R8-B1 symptom persists whenever the
# flake lands in FC1" -- a real flake landing ONLY in FC1 (never touching
# FC0a or FC0b) cannot be explained by the FC0a-vs-FC0b noise floor (that
# noise pair only sees FC0a/FC0b, never FC1), so it still produced an
# unconditional FAIL even after round 8/9's fix. Fix (round 11): a
# checked-in known_flaky_gates.tsv registry, every entry tied to a tracked
# defect report; a registered gate's verdict line is EXCLUDED from BOTH
# sides of the comparison BEFORE it runs, symmetric regardless of which
# member the flake lands in.
# R10-I1 (Important): the FR-002 commit-result (exit-code) check had no
# noise-floor treatment at all. Fix: the SAME "noise-floor member FC0b also
# diverges, landing on the EXACT SAME value FC1 recorded" discipline the
# verdict-set comparison uses, applied to the exit-code scalar.
# R10-I2 (Important): the round-9 SKIP-not-PASS commitment (R8-B1) was
# unguarded -- a mutant converting the SKIP branch into an unconditional
# PASS survived every existing suite, because the old expect_skip() in
# test_fc_timer_golden_output_r4_regression.sh checked only rc=0 plus the
# NOISE-FLOOR line, and a PASS gives the identical rc=0 and the identical
# NOISE-FLOOR line (it is computed and echoed BEFORE the pass/skip/fail
# decision). Fix (in THIS round, landed directly in r4_regression.sh's own
# expect_skip(), not duplicated here): also assert the FR-002/T-A01 line's
# own PASS[.../SKIP[.../FAIL[... marker is genuinely SKIP.
# R10-M3 (Minor): only the FC0a-vs-FC0b overlap pairing (Q4 in
# test_fc_timer_golden_output_r8_regression.sh) had a forged-overlap
# fixture; the FC0a-vs-FC1 and FC0b-vs-FC1 pairs were logically covered
# (pairwise check, any genuine three-way overlap implies a pairwise one)
# but untested. This file parameterises Q4 over the other two pairs (Q6,
# Q7) with their own guard-viability mutations.
# R10-M4 (Minor): `concurrency` was never validated against its own closed
# set {concurrent, sequential} -- a missing/duplicated/garbled value made
# BOTH the per-member-isolation refusal AND the sequential-tree-changed
# refusal never fire (both compare against the literal string "sequential"),
# letting a tree-changed capture with an unresolvable concurrency value sail
# through to TRIPLET_STATE=valid printing the false "ran concurrently" claim.
# Fix: validate the closed set once, early, before anything downstream
# relies on the value.
#
# R10-M1 (stale header comment) and R10-M5 (evidence owed, no code change)
# have no test surface of their own and are not covered here. R10-M2 (the
# allow-list evasion finding) is in a DIFFERENT file
# (test_metatest_per_mutant_r4_regression.sh) and is fixed + regression-
# guarded there, not in this file.
#
# HOW THIS FILE TESTS: every case runs the REAL harness (with a stand-in
# pre-build, lib/golden_triplet_fixture.sh) and the REAL golden test end to
# end, exactly like the r7/r8 regression files. Mutations are applied to a
# COPY of the real golden test (never the live file) via the SAME
# content-anchored `mutate()`/`mrun()` pattern those files use, with the
# exact anchor text extracted at RUN TIME from the real file via `grep -F`
# (never hand-transcribed) so a future edit to the real file's wording
# cannot silently desynchronise this file's anchors from reality.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/golden_triplet_fixture.sh
# (not a shellcheck directive -- plain comment) precheck's shellcheck invocation runs
# without -x; this harness sources its sibling lib file via a runtime-computed $HERE
# path shellcheck cannot statically follow without -x regardless of the source= line
# shellcheck disable=SC1091
. "$HERE/lib/golden_triplet_fixture.sh"
REAL_GOLDEN="$GT_GOLDEN"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
gt_init "$TMP/work"

for f in "$GT_HARNESS" "$REAL_GOLDEN"; do
  # intentional ok/bad control-needle idiom; ok()/bad() are print-only reporters that always return 0, so the || branch never spuriously fires
  # shellcheck disable=SC2015
  [ -f "$f" ] && ok "control needle: $f resolves" || bad "control needle: $f missing"
done

SAME="$TMP/fix_same"
for m in FC0a FC0b FC1; do printf '  ✓ CM-ONE: same\n' | gt_member_text "$SAME" "$m"; done

capture() {  # OUT FIX RUNID PREFIX [harness args...]
  local out="$1" fix="$2" runid="$3" prefix="${4:-t}"; shift 4
  if ! gt_capture "$fix" "$out" "$prefix" "$runid" "$@"; then
    bad "harness failed for $out: $(tail -n 3 "$out/.capture.log")"; return 1
  fi
  gt_promote "$out/${prefix}_${runid}.triplet"
}
set_key() { sed -i "s|^$2=.*|$2=$3|" "$1"; }   # MANIFEST KEY VALUE
has() { grep -qF -- "$2" "$1"; }

_force_tree_change() {
  local mf="$1"
  set_key "$mf" tree_head_end "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  set_key "$mf" tree_status_sha256_end "1111111111111111111111111111111111111111111111111111111111111111"
}

# triplet NAME FC0a-text FC0b-text FC1-text [EVIDENCE-DIR-ENV-VAR] -- real
# harness capture + promotion, with its OWN known-flaky registry env var
# left unset here (callers set FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV themselves
# via gt_golden's own VAR=VALUE arguments, exactly like
# FC_TIMER_GOLDEN_EVIDENCE_DIR already is).
triplet() {
  local name="$1" fix="$TMP/fix_$1" out="$TMP/ev_$1" runid="2026100${2}T000000Z"
  printf '%s\n' "$3" | gt_member_text "$fix" FC0a
  printf '%s\n' "$4" | gt_member_text "$fix" FC0b
  printf '%s\n' "$5" | gt_member_text "$fix" FC1
  gt_capture "$fix" "$out" t "$runid" || { bad "($name) harness failed: $(tail -n 3 "$out/.capture.log")"; return 1; }
  gt_promote "$out/t_${runid}.triplet"
}

# =============================================================================
# R10-B1: known-flaky-gate registry, with a TEST-LOCAL registry (never the
# shipped known_flaky_gates.tsv) so these cases are decoupled from its
# content.
# =============================================================================
REG_TSV="$TMP/custom_known_flaky.tsv"
# T048 round 12 (R12-M2): the golden test now REFUSES any row whose
# defect_doc does not exist (resolved relative to the parent repo root) or
# whose expires date is missing/elapsed -- so this test-local row needs a
# REAL, already-existing doc path (never "docs/requests/fake.md", which
# never existed) and a non-elapsed expires column. The doc chosen is a
# stand-in ONLY because it is guaranteed to exist on this tree -- this row
# is not actually about that defect; see R12-M2's cases further below for
# the dedicated empty-reason/missing-doc/elapsed-expiry refusal coverage.
printf 'gate_id\treason\tdefect_doc\texpires\nCM-FLAKY-TEST-GATE\tsynthetic test-only flaky gate\tdocs/requests/t048_round4_defect1_spk512_bridge_report.md\t2099-01-01\n' > "$REG_TSV"

B_BASE='  ✓ CM-ONE: first
  ✗ CM-TWO: second'
# Gate-id-FIRST shape, matching the REAL pre_build_verification.sh verdict
# line shape ("<GATE-ID>: description...   <checkmark> result text") that
# _fc_filter_known_flaky()'s leading-token match depends on -- NOT the
# checkmark-first synthetic shape other fixtures in this suite use (that
# shape is fine for content the registry is never meant to touch).
B_FLAKY_LINE='CM-FLAKY-TEST-GATE: registered flaky gate description...   ✓ ok text'
B_UNREG_LINE='CM-UNREGISTERED-GATE: not on any registry...   ✓ ok text'

echo "=== (B1) R10-B1 exact reproduction: a REGISTERED gate's line exists ONLY in FC1 (never in FC0a/FC0b) -- excluded, overall PASS ==="
triplet B1 1 "$B_BASE" "$B_BASE" "$B_BASE
$B_FLAKY_LINE"
gt_golden "$TMP/b1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_B1" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$REG_TSV"; rc=$?
if [ "$rc" = 0 ] && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*IDENTICAL.*excluding known-flaky' "$TMP/b1.out" \
   && has "$TMP/b1.out" "CM-FLAKY-TEST-GATE" && ! grep -qE '^SKIP\[[0-9]+\]: FR-002/T-A01' "$TMP/b1.out" \
   && ! grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/b1.out"; then
  ok "(B1) a registered gate's line present ONLY in FC1 is excluded before comparison; the REST is identical -> genuine PASS (not a SKIP-after-the-fact), citing the excluded gate id"
else
  bad "(B1) rc=$rc; $(grep -E 'FR-002/T-A01|INFO: excluded' "$TMP/b1.out" | head -5)"
fi

echo "=== (B2) non-loophole control: the SAME shape with an UNREGISTERED gate id still FAILs (point 3: never a blanket loophole) ==="
triplet B2 2 "$B_BASE" "$B_BASE" "$B_BASE
$B_UNREG_LINE"
gt_golden "$TMP/b2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_B2" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$REG_TSV"; rc=$?
if [ "$rc" = 1 ] && has "$TMP/b2.out" "NOISE-FLOOR: changed=1 noise_explained=0 not_explained=1" \
   && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/b2.out"; then
  ok "(B2) an UNregistered gate's own FC1-only line is NOT excluded and still FAILs exactly as before the registry mechanism -- not a blanket loophole"
else
  bad "(B2) rc=$rc; $(grep -E 'NOISE-FLOOR|FR-002/T-A01' "$TMP/b2.out" | head -5)"
fi

echo "=== (B3) guard-viability: bypassing/emptying the registry on the SAME (B1) fixture reproduces the pre-fix false FAIL ==="
EMPTY_TSV="$TMP/empty_known_flaky.tsv"
: > "$EMPTY_TSV"
gt_golden "$TMP/b3.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_B1" FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV="$EMPTY_TSV"; rc=$?
if [ "$rc" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/b3.out" && ! has "$TMP/b3.out" "INFO: excluded"; then
  ok "(B3) with the registry bypassed (empty file) the IDENTICAL (B1) fixture reproduces the pre-fix FC1-side false FAIL -- the registry mechanism is genuinely load-bearing, not coincidental"
else
  bad "(B3) BLIND: rc=$rc; $(grep -E 'FR-002/T-A01|INFO: excluded' "$TMP/b3.out" | head -5)"
fi

echo "=== (B4) end-to-end with the REAL shipped registry (no env override): a REAL registered gate id, FC1-only ==="
triplet B4 4 "$B_BASE" "$B_BASE" "$B_BASE
CM-SPK512-BRIDGE-SECLABEL-SHELL: SPK-512 toggle text...   ✓ ok"
gt_golden "$TMP/b4.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_B4"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/b4.out" "CM-SPK512-BRIDGE-SECLABEL-SHELL" \
   && grep -qE '^PASS\[[0-9]+\]: FR-002/T-A01.*IDENTICAL.*excluding known-flaky' "$TMP/b4.out"; then
  ok "(B4) the REAL shipped known_flaky_gates.tsv (default path, no env override) correctly excludes a real registered gate id end to end"
else
  bad "(B4) rc=$rc; $(grep -E 'FR-002/T-A01|INFO: excluded' "$TMP/b4.out" | head -5)"
fi

echo "=== (B5) end-to-end with the REAL shipped registry: an unregistered gate id still FAILs (default path, not a blanket loophole) ==="
triplet B5 5 "$B_BASE" "$B_BASE" "$B_BASE
$B_UNREG_LINE"
gt_golden "$TMP/b5.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/ev_B5"; rc=$?
if [ "$rc" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002/T-A01' "$TMP/b5.out"; then
  ok "(B5) the REAL shipped registry does not exclude an unregistered gate id -- still FAILs"
else
  bad "(B5) rc=$rc; $(grep -E 'FR-002/T-A01' "$TMP/b5.out" | head -5)"
fi

# =============================================================================
# R10-I1: exit-code noise floor.
# =============================================================================
echo "=== (E1) R10-I1 exact reproduction: FC0a stays 1, FC0b and FC1 BOTH exit 0 -- exit mismatch fully explained, SKIP not FAIL ==="
# T048 round 19 (R18-I1): the member exit codes below are the stand-in's
# REAL exit codes (gt_member_exit, written into a private copy of the
# shared fixture BEFORE capture), no longer post-capture manifest edits --
# the stand-in now prints a realistic "Failed: N" summary line consistent
# with its own exit code, which a manifest-only exit edit would contradict.
cp -r "$SAME" "$TMP/fix_e1"; gt_member_exit "$TMP/fix_e1" FC0b 0; gt_member_exit "$TMP/fix_e1" FC1 0
capture "$TMP/e1" "$TMP/fix_e1" 20261010T000000Z t
gt_golden "$TMP/e1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/e1"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/e1.out" "IDENTICAL" \
   && grep -qE "^SKIP\[[0-9]+\]: FR-002 commit result: with-timers exit status \(0\) differs from without-timers exit status \(1\), but this SAME run's own noise-floor member FC0b ALSO exited 0" "$TMP/e1.out"; then
  ok "(E1) exit-code mismatch fully explained by the noise-floor member (FC0b also exited 0, matching FC1) is an honest SKIP, never a FAIL"
else
  bad "(E1) rc=$rc; $(grep -E 'commit result' "$TMP/e1.out" | head -3)"
fi

echo "=== (E2) exact-match discipline: FC0b diverges too, but to a DIFFERENT value than FC1 -- NOT noise-explained, still FAILs ==="
cp -r "$SAME" "$TMP/fix_e2"; gt_member_exit "$TMP/fix_e2" FC0b 2; gt_member_exit "$TMP/fix_e2" FC1 0
capture "$TMP/e2" "$TMP/fix_e2" 20261010T010000Z t
gt_golden "$TMP/e2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/e2"; rc=$?
if [ "$rc" = 1 ] && grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result: with-timers exit status \(0\) equals without-timers exit status \(1\) \(noise-floor member FC0b exited 2\) -- MISMATCH, not explained' "$TMP/e2.out"; then
  ok "(E2) FC0b diverging to a DIFFERENT value than FC1 is NOT treated as noise-explained -- the exact-match requirement is enforced, still FAILs"
else
  bad "(E2) rc=$rc; $(grep -E 'commit result' "$TMP/e2.out" | head -3)"
fi

mutate() {
  local name="$1" anchor="$2" repl="$3" hits
  hits="$(grep -cF -- "$anchor" "$REAL_GOLDEN" || true)"
  if [ "$hits" != 1 ]; then bad "($name) control needle: anchor found $hits times (want 1): $anchor"; return 1; fi
  ANCHOR="$anchor" REPL="$repl" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$REAL_GOLDEN" "$TMP/golden_$name.sh"
}
mrun() { GT_GOLDEN="$TMP/golden_$1.sh" gt_golden "$2" FC_TIMER_GOLDEN_EVIDENCE_DIR="$3"; }

echo "=== (M-E) guard-viability: loosen the exit noise-floor elif to accept ANY FC0b divergence (drop the exact-match-to-FC1 requirement) -- (E2) must wrongly flip to SKIP ==="
# T048 round 14 (m5): hoisted into their own narrowly-scoped assignments --
# a `# shellcheck disable` placed directly above an `if ...; then ... fi`
# compound command suppresses that code for the WHOLE if-block body, wider
# than the single literal line that actually needs it.
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
_ME_ANCHOR='elif [ "$_exn" != "$_ex0" ] && [ "$_exn" = "$_ex1" ]; then'
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
_ME_REPL='elif [ "$_exn" != "$_ex0" ]; then'
if mutate E "$_ME_ANCHOR" "$_ME_REPL"; then
  GT_GOLDEN="$TMP/golden_E.sh" gt_golden "$TMP/me2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/e2"
  if grep -qE '^SKIP\[[0-9]+\]: FR-002 commit result' "$TMP/me2.out"; then
    ok "(M-E) without the exact-match-to-FC1 requirement, the mutant WRONGLY treats (E2)'s unrelated FC0b divergence as noise-explained -- the exact-match discipline is genuinely load-bearing"
  else
    bad "(M-E) BLIND: $(grep -E 'commit result' "$TMP/me2.out" | head -3)"
  fi
fi

echo "=== (M-E1) guard-viability: disable the noise-floor SKIP branch entirely (force it to FAIL) -- (E1) must wrongly flip to FAIL ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
ELIF_SKIP_ANCHOR="$(grep -F 'skip "FR-002 commit result: with-timers exit status ($_ex1) differs from without-timers exit status ($_ex0)' "$REAL_GOLDEN" | sed -E 's/^[[:space:]]+//')"
if [ -n "$ELIF_SKIP_ANCHOR" ] && mutate E1 "$ELIF_SKIP_ANCHOR" 'chk "FR-002 commit result: MUTANT forced FAIL instead of honest SKIP" "0"'; then
  GT_GOLDEN="$TMP/golden_E1.sh" gt_golden "$TMP/me1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/e1"
  if grep -qE '^FAIL\[[0-9]+\]: FR-002 commit result: MUTANT forced FAIL' "$TMP/me1.out"; then
    ok "(M-E1) without the noise-floor elif branch, (E1)'s genuinely-explained exit mismatch WRONGLY FAILs -- the R10-I1 fix is genuinely load-bearing"
  else
    bad "(M-E1) BLIND: $(grep -E 'commit result' "$TMP/me1.out" | head -3)"
  fi
else
  bad "(M-E1) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R10-M3: the other two overlap pairs (Q4 in the r8 regression file only
# forged an FC0a-vs-FC0b overlap).
# =============================================================================
echo "=== (Q6) R10-M3: a manifest claiming concurrency=sequential with a FORGED FC0b-vs-FC1 overlap (FC0a disjoint from both) is refused ==="
capture "$TMP/q6" "$SAME" 20261010T020000Z t --sequential
Q6MF="$TMP/q6/t_20261010T020000Z.triplet"
set_key "$Q6MF" member.FC0a.started_epoch 1000
set_key "$Q6MF" member.FC0a.finished_epoch 1005
set_key "$Q6MF" member.FC0b.started_epoch 1010
set_key "$Q6MF" member.FC0b.finished_epoch 1020
set_key "$Q6MF" member.FC1.started_epoch 1015
set_key "$Q6MF" member.FC1.finished_epoch 1025
set_key "$Q6MF" started_epoch 1000
set_key "$Q6MF" finished_epoch 1025
gt_golden "$TMP/q6.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q6"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q6.out" "contradicts its own recorded timing" && ! has "$TMP/q6.out" "IDENTICAL"; then
  ok "(Q6) a sequential manifest with a forged FC0b-vs-FC1 overlap (FC0a disjoint from both) is refused, naming the contradiction"
else
  bad "(Q6) rc=$rc; $(grep -E 'INFO:|SKIP' "$TMP/q6.out" | head -5)"
fi

echo "=== (Q7) R10-M3: a manifest claiming concurrency=sequential with a FORGED FC0a-vs-FC1 overlap (FC0b disjoint from both) is refused ==="
capture "$TMP/q7" "$SAME" 20261010T030000Z t --sequential
Q7MF="$TMP/q7/t_20261010T030000Z.triplet"
set_key "$Q7MF" member.FC0a.started_epoch 1000
set_key "$Q7MF" member.FC0a.finished_epoch 1020
set_key "$Q7MF" member.FC1.started_epoch 1010
set_key "$Q7MF" member.FC1.finished_epoch 1030
set_key "$Q7MF" member.FC0b.started_epoch 1040
set_key "$Q7MF" member.FC0b.finished_epoch 1050
set_key "$Q7MF" started_epoch 1000
set_key "$Q7MF" finished_epoch 1050
gt_golden "$TMP/q7.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/q7"; rc=$?
if [ "$rc" = 0 ] && has "$TMP/q7.out" "contradicts its own recorded timing" && ! has "$TMP/q7.out" "IDENTICAL"; then
  ok "(Q7) a sequential manifest with a forged FC0a-vs-FC1 overlap (FC0b disjoint from both) is refused, naming the contradiction"
else
  bad "(Q7) rc=$rc; $(grep -E 'INFO:|SKIP' "$TMP/q7.out" | head -5)"
fi

echo "=== (M-Q6) guard-viability: drop the FC0b-vs-FC1 overlap term -- (Q6) must wrongly be accepted ==="
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
Q6_ANCHOR="$(grep -F '_fc_ranges_overlap "$_ep_b_s" "$_ep_b_f" "$_ep_1_s" "$_ep_1_f"; then' "$REAL_GOLDEN")"
# T048 round 14 (m5): hoisted into its own narrowly-scoped assignment -- a
# `# shellcheck disable` placed directly above an `if ...; then ... fi`
# compound command suppresses that code for the WHOLE if-block body, wider
# than the single literal substitution that actually needs it.
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
Q6_REPL="$(printf '%s' "$Q6_ANCHOR" | sed -E 's/\|\| _fc_ranges_overlap.*\$_ep_1_f"/|| false/')"
if [ -n "$Q6_ANCHOR" ] && mutate Q6 "$Q6_ANCHOR" "$Q6_REPL"; then
  mrun Q6 "$TMP/mq6.out" "$TMP/q6"
  if has "$TMP/mq6.out" "IDENTICAL" && ! has "$TMP/mq6.out" "contradicts its own recorded timing"; then
    ok "(M-Q6) without the FC0b-vs-FC1 overlap term, the mutant WRONGLY accepts (Q6)'s forged-overlapping manifest -- that term is genuinely load-bearing"
  else
    bad "(M-Q6) BLIND: $(grep -E 'INFO:|SKIP' "$TMP/mq6.out" | head -5)"
  fi
else
  bad "(M-Q6) could not construct the mutation (anchor not found)"
fi

echo "=== (M-Q7) guard-viability: drop the FC0a-vs-FC1 overlap term -- (Q7) must wrongly be accepted ==="
# intentional literal grep -F / sed anchor pattern with an embedded escaped single quote -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC1003,SC2016
Q7_ANCHOR="$(grep -F '_fc_ranges_overlap "$_ep_a_s" "$_ep_a_f" "$_ep_1_s" "$_ep_1_f" \' "$REAL_GOLDEN")"
# T048 round 14 (m5): hoisted into its own narrowly-scoped assignment (see
# the Q6_REPL comment above for why).
# intentional literal grep -F / sed anchor pattern -- the string must NOT expand, that is the point of the mutation anchor
# shellcheck disable=SC2016
Q7_REPL="$(printf '%s' "$Q7_ANCHOR" | sed -E 's/\|\| _fc_ranges_overlap.*\$_ep_1_f" \\/|| false \\/')"
if [ -n "$Q7_ANCHOR" ] && mutate Q7 "$Q7_ANCHOR" "$Q7_REPL"; then
  mrun Q7 "$TMP/mq7.out" "$TMP/q7"
  if has "$TMP/mq7.out" "IDENTICAL" && ! has "$TMP/mq7.out" "contradicts its own recorded timing"; then
    ok "(M-Q7) without the FC0a-vs-FC1 overlap term, the mutant WRONGLY accepts (Q7)'s forged-overlapping manifest -- that term is genuinely load-bearing"
  else
    bad "(M-Q7) BLIND: $(grep -E 'INFO:|SKIP' "$TMP/mq7.out" | head -5)"
  fi
else
  bad "(M-Q7) could not construct the mutation (anchor not found)"
fi

# =============================================================================
# R10-M4: concurrency closed-set validation.
# =============================================================================
echo "=== (C1) R10-M4: an INVALID concurrency value ('garbage') with a forced tree change is REFUSED, never silently treated as concurrent ==="
capture "$TMP/c1" "$SAME" 20261010T040000Z t --sequential
C1MF="$TMP/c1/t_20261010T040000Z.triplet"
_force_tree_change "$C1MF"
set_key "$C1MF" concurrency garbage
gt_golden "$TMP/c1.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/c1"; rc=$?
if [ "$rc" = 1 ] && has "$TMP/c1.out" "not one of the closed set" && ! has "$TMP/c1.out" "ran concurrently" && ! has "$TMP/c1.out" "IDENTICAL"; then
  ok "(C1) a garbled concurrency value is refused (FAIL) naming the closed-set violation, never silently compared"
else
  bad "(C1) rc=$rc; $(grep -E 'FAIL|INFO:' "$TMP/c1.out" | head -5)"
fi

echo "=== (C2) R10-M4: a DUPLICATED concurrency key (so _mf_get returns empty) with a forced tree change is REFUSED the same way ==="
capture "$TMP/c2" "$SAME" 20261010T050000Z t --sequential
C2MF="$TMP/c2/t_20261010T050000Z.triplet"
_force_tree_change "$C2MF"
printf 'concurrency=sequential\n' >> "$C2MF"
gt_golden "$TMP/c2.out" FC_TIMER_GOLDEN_EVIDENCE_DIR="$TMP/c2"; rc=$?
if [ "$rc" = 1 ] && has "$TMP/c2.out" "not one of the closed set" && ! has "$TMP/c2.out" "ran concurrently" && ! has "$TMP/c2.out" "IDENTICAL"; then
  ok "(C2) a duplicated concurrency key (ambiguous -> _mf_get returns empty) is refused the same way as a garbled value"
else
  bad "(C2) rc=$rc; $(grep -E 'FAIL|INFO:' "$TMP/c2.out" | head -5)"
fi

echo "=== (M-C1) guard-viability: bypass the new closed-set validation entirely -- (C1) must reproduce the pre-fix false 'ran concurrently' claim ==="
if mutate C1 '    concurrent|sequential) : ;;' '    concurrent|sequential|*) : ;;  # MUTANT: * now matches too, bypassing the refusal branch below'; then
  mrun C1 "$TMP/mc1.out" "$TMP/c1"
  if has "$TMP/mc1.out" "IDENTICAL" && ! has "$TMP/mc1.out" "not one of the closed set"; then
    ok "(M-C1) with the closed-set validation bypassed, the mutant reproduces the pre-fix behaviour -- it no longer refuses (C1)'s garbled-concurrency manifest and WRONGLY compares it, printing a false IDENTICAL verdict for a value that was never proven to be either concurrent or sequential; the validation is genuinely load-bearing"
  else
    bad "(M-C1) BLIND: $(grep -E 'FAIL|INFO:' "$TMP/mc1.out" | head -5)"
  fi
else
  bad "(M-C1) could not construct the mutation (anchor not found)"
fi

echo
if [ "$fail" = 0 ]; then echo "=== T048 ROUND-10 FINDINGS REGRESSION GUARD (R10-B1/I1/M3/M4): ALL CHECKS PASS ==="; else echo "=== T048 ROUND-10 FINDINGS REGRESSION GUARD (R10-B1/I1/M3/M4): FAILURES ABOVE ==="; fi
exit "$fail"
