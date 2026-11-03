#!/bin/sh
# =============================================================================
# cm_instrument_trap_scan_mutation_test.sh — paired §1.1 mutation for
# CM-INSTRUMENT-TRAP-SCAN (T231; the mutation T215 names).
#
# ── The mutation ────────────────────────────────────────────────────────────
# Disable ONE class matcher (trap_greedy_display_transform) in an out-of-repo copy of
# constitution/scripts/gates/lib/instrument_trap_scan.sh, then assert that
# scripts/testing/anti_slop/us2_trap_scan_red.sh FAILs and that it misses
# EXACTLY that fixture — the other four classes must still be flagged, which is
# what makes the flip attributable to this matcher and not to general breakage
# (§11.4.194(6)(d)).
#
# ── Why class 5 and not class 3 ─────────────────────────────────────────────
# The gate's own control needle is a class-3 (trap_inverted_match) fixture, so
# removing class 3 blinds the scanner entirely and it correctly refuses to
# report on ANY file. That is right behaviour but a useless mutation: every
# fixture would fail and the flip would prove nothing about one matcher. Class 5
# is outside the needle's path, so the scanner stays sighted and misses EXACTLY
# the one fixture — which is what T215 asks this mutation to demonstrate.
#
# ── Why the matcher is EDITED rather than switched off ──────────────────────
# The library carries no env-var suppression knob, on purpose: a scanner that
# can be blinded by an environment variable IS the defect it exists to detect.
# So the mutation edits code, which is also what §11.4.115(F) requires — a
# mutation that only deletes the literal strings the gate greps for is a
# refused tautology.
#
# ── Single-resource-owner (§11.4.84) ────────────────────────────────────────
# Everything runs in an out-of-repo mktemp -d staged with the SAME directory
# depth as the repository, so the gate under test resolves its own libraries
# and fixtures exactly as the tracked one does. The tracked library is never
# edited; its sha256 is compared before and after.
#
# Usage : sh cm_instrument_trap_scan_mutation_test.sh   (rc 0 = pair valid)
# =============================================================================

set -u

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
LIB="$SELF_DIR/lib/instrument_trap_scan.sh"
GATE="$SELF_DIR/cm_instrument_trap_scan.sh"
TEST="$SELF_DIR/fixtures/instrument_trap_scan/us2_trap_scan_red.sh"
FIXTURES="$SELF_DIR/fixtures/instrument_trap_scan/traps"

fails=0
say() { printf '%s\n' "$*"; }
ok()  { say "  [ok]   $*"; }
bad() { fails=$((fails + 1)); say "  [FAIL] $*"; }

for f in "$LIB" "$GATE" "$TEST"; do
    [ -f "$f" ] || { say "PAIR-NOT-DEMONSTRATED: required file absent: $f"; exit 1; }
done
[ -d "$FIXTURES" ] || { say "PAIR-NOT-DEMONSTRATED: fixtures absent: $FIXTURES"; exit 1; }

sum_before=$(sha256sum "$LIB" | cut -d' ' -f1)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_its_mut.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

# Stage the gate, its libraries and its canon-owned fixtures together inside $TMP.
STAGE="$TMP/root"
mkdir -p "$STAGE/constitution/scripts/gates/lib" "$STAGE/constitution/scripts/gates/fixtures/instrument_trap_scan" || exit 2
cp "$GATE" "$STAGE/constitution/scripts/gates/" || exit 2
cp "$SELF_DIR"/lib/*.sh "$STAGE/constitution/scripts/gates/lib/" || exit 2
cp -r "$FIXTURES" "$STAGE/constitution/scripts/gates/fixtures/instrument_trap_scan/traps" || exit 2
MUT_GATE="$STAGE/constitution/scripts/gates/$(basename "$GATE")"
MUT_LIB="$STAGE/constitution/scripts/gates/lib/$(basename "$LIB")"

say '=== T231 paired §1.1 mutation for CM-INSTRUMENT-TRAP-SCAN ==='
say "tracked library (READ-ONLY to this harness): $LIB"
say "mutating an out-of-repo copy at:            $MUT_LIB"

run_t215() {  # <outfile> -> rc of the test
    env US2_TRAP_SCAN="$MUT_GATE" US2_TRAP_FIXTURES="$STAGE/constitution/scripts/gates/fixtures/instrument_trap_scan/traps" \
        sh "$TEST" > "$1" 2>&1
    return $?
}

# --- direction 0 --------------------------------------------------------------
say '--- direction 0: unmutated staged copy -> T215 must PASS ---'
run_t215 "$TMP/base.out"; base_rc=$?
if [ "$base_rc" -eq 0 ]; then ok "T215 PASSes against the staged, unmutated scanner (rc=0)"
else bad "T215 rc=$base_rc against the UNMUTATED scanner — there is nothing for the mutation to flip. Output tail:"; sed -n '$!d;p' "$TMP/base.out"; fi

# --- the mutation -------------------------------------------------------------
say '--- disabling the trap_greedy_display_transform class matcher in the copy ---'
awk '
  /emit\("trap_greedy_display_transform"\)/ {
      print "            # MUTATED: trap_greedy_display_transform no longer emits"
      next
  }
  { print }
' "$MUT_LIB" > "$MUT_LIB.new" && mv "$MUT_LIB.new" "$MUT_LIB"

if sh -n "$MUT_LIB" 2>/dev/null; then ok "the mutated copy still parses — the flip is behavioural, not a syntax error"
else bad "the mutated copy no longer parses; a crash is not the behaviour change this pair claims"; fi
n_left=$(grep -Ec 'emit\("trap_greedy_display_transform"\)' "$MUT_LIB" || true)
if [ "${n_left:-1}" -eq 0 ]; then ok "the trap_greedy_display_transform matcher no longer emits in the copy"
else bad "the matcher still emits in the copy (${n_left}) — the mutation did not apply"; fi
# Assert on distinct CLASS NAMES, not on emit-site COUNT: one class legitimately
# has two emit sites, so a count comparison would be brittle in a way that has
# nothing to do with the property being asserted.
n_other=0
for _c in trap_pipeline_exit_status trap_relative_date_predicate trap_inverted_match trap_query_class_mismatch; do
    _h=$(grep -Ec "emit\\(\"${_c}\"\\)" "$MUT_LIB" || true)
    [ "${_h:-0}" -gt 0 ] && n_other=$((n_other + 1))
done
if [ "$n_other" -eq 4 ]; then ok "the other four classes still emit — the mutation is surgical"
else bad "expected 4 surviving classes, found ${n_other}"; fi

# --- direction 1: the test must FAIL, and miss EXACTLY that fixture -----------
say '--- direction 1: matcher disabled -> T215 must FAIL on bad_05 specifically ---'
run_t215 "$TMP/mut.out"; mut_rc=$?
if [ "$mut_rc" -ne 0 ]; then ok "T215 FAILs against the mutated scanner (rc=$mut_rc)"
else bad "T215 still PASSes with a class matcher REMOVED — its per-class assertions are not load-bearing"; fi

miss=$(grep -Ec 'FAIL\] bad_05_greedy_display_transform\.sh' "$TMP/mut.out" || true)
if [ "${miss:-0}" -gt 0 ]; then ok "the failure names bad_05_greedy_display_transform.sh — the missed fixture is EXACTLY the disabled class"
else bad "T215 failed but did not name bad_05_greedy_display_transform.sh; the flip is not attributable to the disabled matcher (§11.4.194(6)(d))"; fi

for other in bad_01_pipeline_exit_status.sh bad_02_relative_date_predicate.sh \
             bad_03_inverted_match.sh bad_04_query_class_mismatch.sh; do
    n=$(grep -Ec "FAIL\] ${other}" "$TMP/mut.out" || true)
    if [ "${n:-0}" -eq 0 ]; then ok "$other is still flagged — the other classes were not collaterally broken"
    else bad "$other also stopped being flagged; the mutation was not surgical"; fi
done

# --- direction 2: restore -----------------------------------------------------
say '--- direction 2: restore -> T215 must PASS again ---'
cp "$LIB" "$MUT_LIB" || exit 2
run_t215 "$TMP/res.out"; res_rc=$?
if [ "$res_rc" -eq 0 ]; then ok "T215 PASSes again after restore — the flip tracks the mutation in BOTH directions"
else bad "T215 rc=$res_rc after restore; a one-way flip does not demonstrate a pair"; fi

sum_after=$(sha256sum "$LIB" | cut -d' ' -f1)
if [ "$sum_before" = "$sum_after" ]; then ok "tracked library unchanged (sha256 $sum_after) — single-resource-owner respected (§11.4.84)"
else bad "the TRACKED library changed during this run ($sum_before -> $sum_after)"; fi

say ''
if [ "$fails" -eq 0 ]; then say '=== MUTATION PAIR VALID — T215 per-class assertions are load-bearing on the matchers ==='; exit 0; fi
say "=== PAIR NOT DEMONSTRATED ($fails failed) ==="
exit 1
