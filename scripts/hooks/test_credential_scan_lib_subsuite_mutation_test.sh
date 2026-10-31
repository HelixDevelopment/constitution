#!/usr/bin/env bash
# test_credential_scan_lib_subsuite_mutation_test.sh — §1.1 paired-mutation test for the SUB-SUITE WIRING
# of test_credential_scan_lib.sh (its `_sub_run` helper and the (x)/(y) calls).
#
# ── Why it exists ───────────────────────────────────────────────────────────
# Round-3 review N2 of the remedy batch: the sub-suite wiring had no mutation guard. Reviewer mutant RM4
# neutralised the exit-code capture in `_sub_run` (`|| rc=$?` -> `|| true`); with the exit code as the only
# channel, the library mutant MX1b (the AKIA placeholder carrier widened from its one named value to a
# 16-digit class) then scored 95/0. `_sub_run` now reads two channels (exit code, and the sub-suite's own
# PASS/FAIL lines); this test holds each channel and the wiring in place.
#
# ── What it does ────────────────────────────────────────────────────────────
# It rebuilds a REDUCED copy of the suite in a sandbox: the suite's own header (load guards, ok/bad, the
# work dir) up to the `trap … EXIT` line, plus its sub-suite section from `_sub_run() {` to the end —
# verbatim, so the code under test is the real code, without the ~90 fixture cases. The sandbox also holds
# copies of the library, the AKIA sub-suite, the core-literal sub-suite and the files it scans.
# A run is CAUGHT when the suite exits non-zero, its RESULT line counts >= 1 failure, and it prints a
# `FAIL: (x)` line.
#
#   D0  real (x) + real (y), library unchanged           -> rc 0, PASS (x), PASS (y)
#   D1  REAL (x) on the library mutant MX1b               -> caught
#   NC  (x) replaced by a stub: PASS line, exit 0         -> rc 0   (false-positive guard)
#   D2  stub: PASS line, exit 1                           -> caught (exit-code channel)
#   D3  stub: PASS + FAIL line, exit 0                    -> caught (FAIL-line channel)
#   D4  stub: no PASS line, exit 0                        -> caught (a sub-suite that checked nothing)
#   D5  (x) file absent                                   -> caught (missing is a FAIL, never a skip)
#
# Then six wiring mutants are applied to the reduced copy (exact old -> new, once, still parses); each must
# turn its named direction into a NOT-caught run:
#   SM1 (=RM4) exit-code capture `|| rc=$?` -> `|| true`          flips D2
#   SM2 FAIL-line channel `-eq 0` -> `-ge 0`                       flips D3
#   SM3 PASS-line floor `-ge 1` -> `-ge 0`                         flips D4
#   SM4 `_sub_run` failure tally `+= 1` -> `+= 0`                  flips D1 (the real MX1b path)
#   SM5 missing-(x) branch tally `+ 1` -> `+ 0`                    flips D5
#   SM6 the (x) call replaced by `true`                            flips D1
#
# Honest boundary (§11.4.6, round-4 review N7): this test holds each channel of `_sub_run` and the (x)/(y)
# calls; it does NOT hold the outer suite's (z) accounting, which runs only outside this sandbox. A double
# edit that neutralises (z)'s verdict check AND one `_sub_run` seam (reviewer mutant RX3: `(z)` forced to
# PASS plus SM4) is caught by two other layers, not by this file: (z) itself requires the "PAIR VALID"
# verdict line, and the consumer reads the suite output through suite_verdict_set_check.sh (profile
# credscan-suite), whose paired test suite_verdict_set_check_mutation_test.sh applies RX3 verbatim.
# The (y) sub-suite runs here with CORE_LITERAL_CD_INNER=1 (its fixture-consumer section CD and its M1-M11
# cases are skipped in this sandbox; the outer suite's own (y) run executes them).
#
# Usage: test_credential_scan_lib_subsuite_mutation_test.sh
# Exit: 0 every direction and every mutant demonstrated · 1 not demonstrated · 2 environment error.
# Wired: test_credential_scan_lib.sh runs it as sub-case (z), counted with ok/bad (not through _sub_run).
# Side-effects: a mktemp sandbox under $TMPDIR, removed on exit. The real tree is never edited.
# Classification: universal (§11.4.17). SECURITY: the mutant text is built from fragments; no contiguous
# AKIA-shaped literal is written by this file.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SUITE="$HERE/test_credential_scan_lib.sh"
LIB="$HERE/credential_scan_lib.sh"
AKIA="$HERE/test_credential_scan_lib_akia_literal_free.sh"
CORE="$HERE/../gates/cm_core_scripts_project_literal_free_mutation_test.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
for f in "$SUITE" "$LIB" "$AKIA" "$CORE"; do [ -f "$f" ] || { echo "ENV: missing $f"; exit 2; }; done

HEAD_END="trap 'rm -rf \"\$WORK\"' EXIT"
SUB_START='_sub_run() { # $1 label  $2.. command'
n_he="$(grep -cxF "$HEAD_END" "$SUITE")"; n_ss="$(grep -cxF "$SUB_START" "$SUITE")"
[ "$n_he" = 1 ] && [ "$n_ss" = 1 ] || { echo "ENV: section markers not found exactly once (header end: $n_he, sub-suite start: $n_ss) — re-anchor"; exit 2; }
SUM_SUITE="$(sha256sum "$SUITE" | cut -d' ' -f1)"; SUM_LIB="$(sha256sum "$LIB" | cut -d' ' -f1)"

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/credscan_subsuite_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT INT TERM
SB="$TMPD/sb"; H="$SB/scripts/hooks"; G="$SB/scripts/gates"
mkdir -p "$H" "$G"
REDUCED="$TMPD/reduced_suite.sh"
awk -v he="$HEAD_END" -v ss="$SUB_START" '
    !done_head { print; if ($0 == he) done_head = 1; next }
    $0 == ss { in_sub = 1 }
    in_sub { print }' "$SUITE" > "$REDUCED"
cp "$LIB" "$H/credential_scan_lib.sh"
cp "$CORE" "$G/"
# the core-literal sub-suite scans its guard set under --root; copy exactly that set
CORE_FILES="$(sed -n 's/^FILES="\(.*\)"$/\1/p' "$CORE" | head -1)"
[ -n "$CORE_FILES" ] || { echo "ENV: core-literal guard set (FILES=) not found in $CORE"; exit 2; }
for g in $CORE_FILES; do
    [ -f "$ROOT/$g" ] || { echo "ENV: guard-set file missing: $ROOT/$g"; exit 2; }
    mkdir -p "$SB/$(dirname "$g")"; cp "$ROOT/$g" "$SB/$g"
done
[ -f "$H/credential_scan_lib.sh" ] || { echo "ENV: library copy missing"; exit 2; }

fails=0
ok()  { echo "  [ok]   $*"; }
bad() { fails=$((fails + 1)); echo "  [FAIL] $*"; }
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
restore_suite() { cp "$REDUCED" "$H/test_credential_scan_lib.sh"; }
set_lib() { # clean | mx1b
    cp "$LIB" "$H/credential_scan_lib.sh"
    [ "$1" = mx1b ] || return 0
    local a="AK""IA" d="1234567890""123456"
    edit "$H/credential_scan_lib.sh" "='^${a}''${d}\$'" "='^${a}''[0-9]{16}\$'"
}
set_x() { # real | pass | rconly | failline | nopass | absent
    rm -f "$H/test_credential_scan_lib_akia_literal_free.sh"
    local body
    case "$1" in
        real)     cp "$AKIA" "$H/"; return 0 ;;
        absent)   return 0 ;;
        pass)     body='echo "PASS: stub check"; exit 0' ;;
        rconly)   body='echo "PASS: stub check"; exit 1' ;;
        failline) body='echo "PASS: stub check"; echo "FAIL: stub check"; exit 0' ;;
        nopass)   body='echo "stub ran, checked nothing"; exit 0' ;;
    esac
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$H/test_credential_scan_lib_akia_literal_free.sh"
}
set_y() { # real | pass
    rm -f "$G/cm_core_scripts_project_literal_free_mutation_test.sh"
    if [ "$1" = real ]; then cp "$CORE" "$G/"
    else printf '#!/usr/bin/env bash\necho "PASS: stub core check"\nexit 0\n' > "$G/cm_core_scripts_project_literal_free_mutation_test.sh"; fi
}
run() { # sets R_RC R_FAILED R_X (PASS|FAIL|-) R_Y R_OUT
    R_OUT="$(cd "$SB" && env CREDSCAN_SUBSUITE_META_INNER=1 CORE_LITERAL_CD_INNER=1 bash "$H/test_credential_scan_lib.sh" 2>&1)"; R_RC=$?
    R_FAILED="$(printf '%s\n' "$R_OUT" | sed -n 's/^== RESULT: [0-9]* passed, \([0-9]*\) failed ==$/\1/p' | tail -1)"
    R_FAILED="${R_FAILED:--}"
    if grep -q '^FAIL: (x)' <<<"$R_OUT"; then R_X=FAIL; elif grep -q '^PASS: (x)' <<<"$R_OUT"; then R_X=PASS; else R_X=-; fi
    if grep -q '^FAIL: (y)' <<<"$R_OUT"; then R_Y=FAIL; elif grep -q '^PASS: (y)' <<<"$R_OUT"; then R_Y=PASS; else R_Y=-; fi
}
caught() { [ "$R_RC" -ne 0 ] && [ "$R_FAILED" != "-" ] && [ "$R_FAILED" -ge 1 ] && [ "$R_X" = FAIL ]; }
desc() { echo "rc=$R_RC failed=$R_FAILED (x)=$R_X (y)=$R_Y"; }

echo "=== §1.1 paired mutation for the sub-suite wiring of test_credential_scan_lib.sh ==="
dir_d0() { set_lib clean; set_x real; set_y real; run; }
dir_d1() { set_lib mx1b || return 9; set_x real; set_y pass; run; }
dir_nc() { set_lib clean; set_x pass; set_y pass; run; }
dir_d2() { set_lib clean; set_x rconly; set_y pass; run; }
dir_d3() { set_lib clean; set_x failline; set_y pass; run; }
dir_d4() { set_lib clean; set_x nopass; set_y pass; run; }
dir_d5() { set_lib clean; set_x absent; set_y pass; run; }

restore_suite
dir_d0
if [ "$R_RC" -eq 0 ] && [ "$R_FAILED" = 0 ] && [ "$R_X" = PASS ] && [ "$R_Y" = PASS ]; then ok "D0: real (x)+(y) on the unchanged library -> $(desc)"
else bad "D0: real (x)+(y) on the unchanged library -> $(desc) (expected rc 0, both PASS) — nothing below would mean anything"; printf '%s\n' "$R_OUT" | tail -n 8; fi
if dir_d1; then caught && ok "D1 real path: library mutant MX1b through the REAL (x) -> $(desc)" || bad "D1: MX1b through the real (x) -> $(desc) — not caught"
else bad "D1: library mutant MX1b could not be applied exactly once (re-anchor it to the library)"; fi
dir_nc
if [ "$R_RC" -eq 0 ] && [ "$R_FAILED" = 0 ] && [ "$R_X" = PASS ]; then ok "NC: passing stub sub-suite -> $(desc): no false refusal (§11.4.201(1))"
else bad "NC: passing stub sub-suite -> $(desc) (expected rc 0, (x) PASS)"; fi
dir_d2; caught && ok "D2: stub exits 1 with only a PASS line -> $(desc)" || bad "D2: exit-code channel -> $(desc) — not caught"
dir_d3; caught && ok "D3: stub exits 0 with a FAIL line -> $(desc)" || bad "D3: FAIL-line channel -> $(desc) — not caught"
dir_d4; caught && ok "D4: stub exits 0 with no PASS line -> $(desc)" || bad "D4: PASS-line floor -> $(desc) — not caught"
dir_d5; caught && ok "D5: (x) sub-suite absent -> $(desc)" || bad "D5: missing sub-suite -> $(desc) — not caught"

pair() { # $1 id  $2 direction fn  $3 old  $4 new
    restore_suite
    if ! edit "$H/test_credential_scan_lib.sh" "$3" "$4"; then bad "$1: mutant text not applied exactly once (or the copy no longer parses) — re-anchor it"; return; fi
    "$2"
    if caught; then bad "$1: $2 is STILL caught under the mutant ($(desc)) — the mutant SURVIVES"
    else ok "$1: $2 no longer caught under the mutant ($(desc)) — seen"; fi
}
pair SM1 dir_d2 'out="$("$@" 2>&1)" || rc=$?' 'out="$("$@" 2>&1)" || true'
pair SM2 dir_d3 '[ "$nfail" -eq 0 ]' '[ "$nfail" -ge 0 ]'
pair SM3 dir_d4 '[ "$npass" -ge 1 ]' '[ "$npass" -ge 0 ]'
pair SM4 dir_d1 ': $((fail += 1))' ': $((fail += 0))'
pair SM5 dir_d5 'echo "FAIL: (x) AKIA-literal-free sub-suite missing: $_sub_akia"; fail=$((fail + 1))' \
                'echo "FAIL: (x) AKIA-literal-free sub-suite missing: $_sub_akia"; fail=$((fail + 0))'
pair SM6 dir_d1 '_sub_run "(x) AKIA-literal-free sub-suite" env CREDSCAN_LIB_UNDER_TEST="$LIB" bash "$_sub_akia"' 'true'

restore_suite; dir_d1
caught && ok "RESTORED: the unmutated reduced copy catches MX1b again ($(desc))" || bad "RESTORED: $(desc)"
[ "$(sha256sum "$SUITE" | cut -d' ' -f1)" = "$SUM_SUITE" ] && [ "$(sha256sum "$LIB" | cut -d' ' -f1)" = "$SUM_LIB" ] \
  && ok "tracked suite + library unchanged" || bad "a tracked file changed during the test"

if [ "$fails" -eq 0 ]; then echo "=== SUB-SUITE WIRING PAIR VALID: 7 directions demonstrated, 6 wiring mutants seen ==="; exit 0; fi
echo "=== SUB-SUITE WIRING PAIR NOT DEMONSTRATED: $fails failure(s) ==="; exit 1
