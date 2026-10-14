#!/usr/bin/env bash
# covenant_propagation_suite_accounting_mutation_test.sh — §1.1 paired-mutation test for the FAILURE
# ACCOUNTING of covenant_propagation_suite.sh (`gates` mode): a failing engine self-test, or a failing
# accounting self-test, must reach the suite's exit code, its "N non-zero" summary tally and its printed
# entry line. The consumer's CM-COVENANT-PROPAGATION-SUITE gate reads exactly those (rc + tally).
#
# ── Why it exists ───────────────────────────────────────────────────────────
# Round-3 review N1 of the remedy batch: the SELFTEST entry's accounting line had no paired mutation.
# Reviewer mutant RM1 rewrote it to `if false; then …`; on its own that changes nothing visible, but
# together with an engine mutant (ME1) the suite printed "0 non-zero", rc 0, and the consumer gate read
# PASS while the engine self-test was failing. The consumer's own suite mutation test only rewrites the
# gate loop's accounting line, so nothing caught RM1.
#
# ── What it does ────────────────────────────────────────────────────────────
# It copies the REAL suite, the REAL engine (+ its two lib siblings), the REAL compact self-test, the real
# data pack and the first row's two wrappers into a sandbox. The suite runs in `gates` mode with
# COVENANT_PROPAGATION_ANCHORS pointing at a one-row stub pack whose single gate exits 0, so the suite's
# result depends only on the self-test entries. Runs set COVENANT_PROPAGATION_SUITE_INNER=1 except D5.
#
#   NC  stub self-test exits 0, engine clean         -> suite rc 0, "0 non-zero"   (false-positive guard)
#   D1  REAL compact self-test, engine mutant ME1    -> suite rc 1, tally >= 1, SELFTEST entry rc != 0
#   D2  stub self-test exits 1                       -> caught (same three signals)
#   D3  self-test file absent (engine present)       -> caught (entry rc 2)
#   D5  INNER unset, accounting self-test is a stub that exits 1 -> caught on the ACCOUNTING entry
#
# Then seven accounting mutants are applied to the sandbox suite copy (exact old -> new text, applied
# exactly once, the copy still parses) and each must turn its named direction into a NOT-caught run:
#   SA1 (=RM1) SELFTEST `if [ "$rc" -ne 0 ]` -> `if false`                    flips D2
#   SA2 SELFTEST rc capture `rc=$?` -> `rc=0`                                 flips D2
#   SA3 missing-self-test branch `rc=2` -> `rc=0`                             flips D3
#   SA4 SELFTEST block guard points at a file that never exists (skipped)     flips D2
#   SA5 final `|| exit 1` -> `|| exit 0`                                      flips D2
#   SA6 `bad=0` re-inserted before the gate loop (tally reset)                flips D2
#   SA7 ACCOUNTING entry `case` line neutralised                              flips D5
# A clean real-engine run of the compact self-test is NOT repeated here: the suite's own SELFTEST entry
# is that run (about 18 s); this test only needs the failing direction, which exits within seconds.
#
# Honest boundary (§11.4.6): this test holds each accounting seam ONE edit at a time. It does not catch a
# change that removes the ACCOUNTING entry itself (reviewer mutant RX1: its guard inverted, so the entry
# simply vanishes and nothing is counted), nor a double mutant that silences the ACCOUNTING `case` line and
# one of the SA1-SA6 seams together. Those shapes are visible in the printed lines and are caught one layer
# up: the consumer reads the suite output through suite_verdict_set_check.sh (profile covenant-gates), which
# requires the named entries and cross-checks printed entry rcs against the tally; its paired test
# (suite_verdict_set_check_mutation_test.sh) applies RX1, and RX1 + SA1 + engine mutant ME1, verbatim.
#
# Usage: covenant_propagation_suite_accounting_mutation_test.sh
# Exit: 0 every direction and every mutant demonstrated · 1 not demonstrated · 2 environment error.
# Wired: covenant_propagation_suite.sh `gates` mode runs it as CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING.
# Side-effects: a mktemp sandbox under $TMPDIR, removed on exit. The real tree is never edited.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SUITE="$HERE/covenant_propagation_suite.sh"
ENGINE="$HERE/lib/covenant_propagation_engine.sh"
ST="$HERE/covenant_propagation_engine_compact_mutation_test.sh"
PACK="$HERE/covenant_propagation_anchors.tsv"
for f in "$SUITE" "$ENGINE" "$ST" "$PACK" "$HERE/lib/pointer_carrier.sh" "$HERE/lib/covenant_propagation_mutation_engine.sh"; do
    [ -f "$f" ] || { echo "ENV: missing $f"; exit 2; }
done
GATE_NAME="$(awk -F'\t' '/^#/{next} NF>=2 && $1!="" {print $1; exit}' "$PACK")"
ANCHOR="$(awk -F'\t' -v g="$GATE_NAME" '/^#/{next} $1==g {print $2; exit}' "$PACK")"
SLUG="${ANCHOR#11.4.}"
WRAP="$HERE/cm_covenant_114_${SLUG}_propagation.sh"
MWRAP="$HERE/cm_covenant_114_${SLUG}_propagation_mutation_test.sh"
[ -n "$GATE_NAME" ] && [ -f "$WRAP" ] && [ -f "$MWRAP" ] || { echo "ENV: no usable gate row/wrappers for '$GATE_NAME'"; exit 2; }

SUM_SUITE="$(sha256sum "$SUITE" | cut -d' ' -f1)"
SUM_ENGINE="$(sha256sum "$ENGINE" | cut -d' ' -f1)"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cps_accounting_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT INT TERM
SB="$TMPD/gates"; ROOTD="$TMPD/root"; STUBPACK="$TMPD/stub_pack.tsv"
mkdir -p "$SB/lib" "$ROOTD"
cp "$ENGINE" "$HERE/lib/pointer_carrier.sh" "$HERE/lib/covenant_propagation_mutation_engine.sh" "$SB/lib/"
cp "$PACK" "$WRAP" "$MWRAP" "$SB/"
printf 'CM-COVENANT-114-999-PROPAGATION\t11.4.999\n' > "$STUBPACK"
printf '#!/usr/bin/env bash\necho "✅ CM-COVENANT-114-999-PROPAGATION: sandbox stub gate"\nexit 0\n' > "$SB/cm_covenant_114_999_propagation.sh"
# the suite's VERDICT-SET-CHECK entry runs when INNER is unset (D5 and SA7): a passing stub keeps those runs
# about the ACCOUNTING entry alone (round-4: the entry was added after this test).
printf '#!/usr/bin/env bash\necho "=== VERDICT-SET CHECK PAIR VALID: sandbox stub ==="\nexit 0\n' > "$SB/suite_verdict_set_check_mutation_test.sh"

fails=0
ok()  { echo "  [ok]   $*"; }
bad() { fails=$((fails + 1)); echo "  [FAIL] $*"; }

SB_SUITE="$SB/covenant_propagation_suite.sh"
SB_ST="$SB/covenant_propagation_engine_compact_mutation_test.sh"
SB_AT="$SB/covenant_propagation_suite_accounting_mutation_test.sh"
restore_suite() { cp "$SUITE" "$SB_SUITE"; }
set_engine() { # clean | me1
    cp "$ENGINE" "$SB/lib/covenant_propagation_engine.sh"
    [ "$1" = me1 ] || return 0
    edit "$SB/lib/covenant_propagation_engine.sh" \
      'if [ "${_cpe_tcount:-0}" -eq 1 ]; then' \
      'if [ "${_cpe_tcount:-0}" -ge 1 ]; then'
}
set_selftest() { # real | ok | fail | absent
    rm -f "$SB_ST"
    case "$1" in
        real)   cp "$ST" "$SB_ST" ;;
        ok)     printf '#!/usr/bin/env bash\necho "=== MUTATION PAIR VALID: sandbox stub ==="\nexit 0\n' > "$SB_ST" ;;
        fail)   printf '#!/usr/bin/env bash\necho "=== MUTATION PAIR NOT DEMONSTRATED: sandbox stub ==="\nexit 1\n' > "$SB_ST" ;;
        absent) : ;;
    esac
}
set_accounting_stub() { # fail | none
    rm -f "$SB_AT"
    [ "$1" = fail ] && printf '#!/usr/bin/env bash\necho "=== ACCOUNTING NOT DEMONSTRATED: sandbox stub ==="\nexit 1\n' > "$SB_AT"
    return 0
}
edit() { # $1 file  $2 old  $3 new -> rc 0 iff exactly one replacement and the file still parses
    python3 - "$1" "$2" "$3" <<'PY' || return 1
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
if s.count(old) != 1:
    sys.exit(3)
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
    bash -n "$1"
}
# run <inner:1|0> -> sets R_RC R_TALLY R_ST R_AC (entry rcs; "-" when the entry line is absent)
run() {
    local out
    if [ "$1" = 1 ]; then
        out="$(env -u COVENANT_PROPAGATION_CARRIERS COVENANT_PROPAGATION_ANCHORS="$STUBPACK" \
               COVENANT_PROPAGATION_SUITE_INNER=1 bash "$SB_SUITE" gates --root "$ROOTD" 2>&1)"; R_RC=$?
    else
        out="$(env -u COVENANT_PROPAGATION_CARRIERS -u COVENANT_PROPAGATION_SUITE_INNER \
               COVENANT_PROPAGATION_ANCHORS="$STUBPACK" bash "$SB_SUITE" gates --root "$ROOTD" 2>&1)"; R_RC=$?
    fi
    R_TALLY="$(printf '%s\n' "$out" | sed -n 's/^suite(gates): .*, \([0-9]*\) non-zero.*/\1/p' | tail -1)"
    R_ST="$(printf '%s\n' "$out" | awk '$1=="CM-COVENANT-PROPAGATION-ENGINE-SELFTEST"{print $2}' | tail -1)"
    R_AC="$(printf '%s\n' "$out" | awk '$1=="CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING"{print $2}' | tail -1)"
    R_ST="${R_ST:--}"; R_AC="${R_AC:--}"; R_TALLY="${R_TALLY:--}"
    R_OUT="$out"
}
# caught <entry var value> -> rc 0 iff the failure reached exit code, tally and the entry line
caught() { [ "$R_RC" -ne 0 ] && [ "$R_TALLY" != "-" ] && [ "$R_TALLY" -ge 1 ] && [ "$1" != "-" ] && [ "$1" != 0 ]; }
desc() { echo "rc=$R_RC tally=$R_TALLY selftest_entry=$R_ST accounting_entry=$R_AC"; }

echo "=== §1.1 paired mutation for covenant_propagation_suite.sh failure accounting ==="
# ---- directions on the unmutated suite copy ----------------------------------------------------------
dir_nc() { set_engine clean; set_selftest ok; set_accounting_stub none; run 1; }
dir_d1() { set_engine me1 || return 9; set_selftest real; set_accounting_stub none; run 1; }
dir_d2() { set_engine clean; set_selftest fail; set_accounting_stub none; run 1; }
dir_d3() { set_engine clean; set_selftest absent; set_accounting_stub none; run 1; }
dir_d5() { set_engine clean; set_selftest ok; set_accounting_stub fail; run 0; }

restore_suite
dir_nc
if [ "$R_RC" -eq 0 ] && [ "$R_TALLY" = 0 ] && [ "$R_ST" = 0 ]; then ok "NC: passing stub self-test -> $(desc): the suite does not refuse a clean input (§11.4.201(1))"
else bad "NC: passing stub self-test -> $(desc) (expected rc 0, tally 0, entry 0) — any 'caught' below would be meaningless"; fi
if dir_d1; then
    if caught "$R_ST" && grep -q '^CM-COVENANT-PROPAGATION-ENGINE-SELFTEST .*NOT DEMONSTRATED' <<<"$R_OUT"; then
        ok "D1 real path: REAL compact self-test on engine mutant ME1 -> $(desc), entry verdict 'NOT DEMONSTRATED'"
    else bad "D1 real path: REAL compact self-test on engine mutant ME1 -> $(desc) — the engine failure does not reach the suite verdict"; fi
else bad "D1: engine mutant ME1 could not be applied exactly once (re-anchor it to the engine)"; fi
dir_d2; caught "$R_ST" && ok "D2: failing stub self-test -> $(desc)" || bad "D2: failing stub self-test -> $(desc) — not caught"
dir_d3; caught "$R_ST" && ok "D3: absent self-test -> $(desc)" || bad "D3: absent self-test -> $(desc) — not caught"
dir_d5; caught "$R_AC" && ok "D5: failing accounting self-test (INNER unset) -> $(desc)" || bad "D5: failing accounting self-test -> $(desc) — not caught"

# ---- mutants on the suite copy ----------------------------------------------------------------------
pair() { # $1 id  $2 direction fn  $3 entry (st|ac)  $4 old  $5 new
    local id="$1" dir="$2" which="$3" v
    restore_suite
    if ! edit "$SB_SUITE" "$4" "$5"; then bad "$id: mutant text not applied exactly once (or the copy no longer parses) — re-anchor it"; return; fi
    "$dir"
    if [ "$which" = ac ]; then v="$R_AC"; else v="$R_ST"; fi
    if caught "$v"; then bad "$id: $dir is STILL caught under the mutant ($(desc)) — the mutant SURVIVES, the seam is not load-bearing"
    else ok "$id: $dir no longer caught under the mutant ($(desc)) — seen"; fi
}
pair SA1 dir_d2 st 'if [ "$rc" -ne 0 ]; then bad=$((bad+1)); fi' 'if false; then bad=$((bad+1)); fi'
pair SA2 dir_d2 st 'out="$(env -u COVENANT_PROPAGATION_CARRIERS bash "$_st" 2>&1)"; rc=$?' \
                   'out="$(env -u COVENANT_PROPAGATION_CARRIERS bash "$_st" 2>&1)"; rc=0'
pair SA3 dir_d3 st 'rc=2; verdict="engine self-test missing: $_st"' 'rc=0; verdict="engine self-test missing: $_st"'
pair SA4 dir_d2 st 'if [ "$MODE" = "gates" ] && [ -f "${HERE}/lib/covenant_propagation_engine.sh" ]; then' \
                   'if [ "$MODE" = "gates" ] && [ -f "${HERE}/lib/__never_present__" ]; then'
pair SA5 dir_d2 st '[ "$bad" -eq 0 ] || exit 1' '[ "$bad" -eq 0 ] || exit 0'
pair SA6 dir_d2 st "while IFS=\$'\\t' read -r gate anchor; do" "bad=0
while IFS=\$'\\t' read -r gate anchor; do"
pair SA7 dir_d5 ac 'case "$rc" in 0) ;; *) bad=$((bad+1)) ;; esac' 'case "$rc" in 0) ;; *) bad=$((bad+0)) ;; esac'

# ---- restore + untouched ----------------------------------------------------------------------------
restore_suite; dir_d2
caught "$R_ST" && ok "RESTORED: unmutated copy catches the failing self-test again ($(desc))" || bad "RESTORED: $(desc)"
[ "$(sha256sum "$SUITE" | cut -d' ' -f1)" = "$SUM_SUITE" ] && [ "$(sha256sum "$ENGINE" | cut -d' ' -f1)" = "$SUM_ENGINE" ] \
  && ok "tracked suite + engine unchanged (suite sha256 $SUM_SUITE)" || bad "a tracked file changed during the test"

if [ "$fails" -eq 0 ]; then echo "=== ACCOUNTING PAIR VALID: 5 directions demonstrated, 7 accounting mutants seen ==="; exit 0; fi
echo "=== ACCOUNTING PAIR NOT DEMONSTRATED: $fails failure(s) ==="; exit 1
