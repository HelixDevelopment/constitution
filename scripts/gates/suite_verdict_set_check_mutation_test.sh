#!/usr/bin/env bash
# suite_verdict_set_check_mutation_test.sh — §1.1 paired-mutation test for suite_verdict_set_check.sh, the
# consumer-side reader of the covenant-propagation suite and the credential-scan suite (round-4 review N6/N7).
#
# ── Part A: the checker's rules, on fixed output fixtures ─────────────────────
#   CG0 valid covenant output (named entries + one gate, consistent)              -> VALID
#   CG1 ACCOUNTING entry missing (the RX1 shape)                                   -> INVALID
#   CG2 an entry printed with rc 1, summary "0 non-zero", rc 0 (an uncounted failure) -> INVALID
#   CG3 summary line missing                                                       -> INVALID
#   CG4 suite exit code 1                                                          -> INVALID
#   CG5 an entry printed twice                                                     -> INVALID
#   CG6 suite dir without the engine, no named entries (a consumer's stub sandbox) -> VALID   (§11.4.201(1))
#   CS0 valid credscan output                                                      -> VALID
#   CS1 `PASS: (z) … PAIR NOT DEMONSTRATED` (the RX3 shape)                        -> INVALID
#   CS2 a FAIL line printed while RESULT counts 0 failed (SM4 shape)               -> INVALID
#   CS3 the (x) verdict line missing                                               -> INVALID
#   CS4 the sandbox-inner `(z) not re-entered` line instead of a (z) verdict       -> INVALID
#   CS5 RESULT line missing                                                        -> INVALID
# Six checker mutants (exact old -> new, once, the copy still parses), each must turn its fixture VALID:
#   K1 named-entry requirement off -> CG1   K2 entry-rc vs tally cross-check off -> CG2   K3 rc check off -> CG4
#   K4 (z) PAIR VALID rule off -> CS1       K5 credscan PASS/FAIL line cross-check off -> CS2
#   K6 the required (x)/(y) verdict lines off -> CS3
#
# ── Part B: end to end, the reviewer's mutants VERBATIM on real suite copies ──
# Covenant: a sandbox holding the REAL suite and engine (+ libs), stub ACCOUNTING / VERDICT-SET self-tests
# that pass, and a one-row stub pack whose gate passes; run with INNER unset. The compact self-test is a
# passing stub in RB0 and RX1 and the REAL one in RX1+SA1+ME1 (where its failure is the point).
#   RB0 unmutated                                    -> suite rc 0, checker VALID
#   RX1 ACCOUNTING guard `-z` -> `-n`                -> the entry vanishes, suite rc 0, checker INVALID
#   RX1+SA1+ME1 (the round-3 survivor)               -> suite rc 0 with a failing SELFTEST line, checker INVALID
# Credscan: a sandbox holding the REAL suite, library, its three sub-suites and the core-literal guard set.
#   RC0 unmutated                                    -> suite rc 0, checker VALID
#   RX3 (z) check -> `if true` + SM4 + library mutant MX1b -> checker INVALID
#   RX3c RX3 + (z)'s own PAIR VALID case neutralised (the round-3 survivor shape, one more edit) -> checker INVALID
# The credscan runs set CORE_LITERAL_CD_INNER=1 (the (y) sub-suite's fixture-consumer section is proven by the
# real suite run, not repeated here).
#
# Honest boundary (§11.4.6): the checker proves the printed verdict set is complete and self-consistent, not
# that the suite printed the truth; a suite edited to forge a consistent set passes (see the checker header).
# Usage: suite_verdict_set_check_mutation_test.sh
# Exit: 0 all demonstrated · 1 not demonstrated · 2 environment error.
# Wired: covenant_propagation_suite.sh `gates` runs it as CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK.
# Side-effects: a mktemp sandbox under $TMPDIR, removed on exit. The real tree is never edited.
# Classification: universal (§11.4.17). SECURITY: mutant text is built from fragments; no contiguous
# AKIA-shaped literal is written by this file.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CHK="$HERE/suite_verdict_set_check.sh"
SUITE="$HERE/covenant_propagation_suite.sh"
ENGINE="$HERE/lib/covenant_propagation_engine.sh"
ST="$HERE/covenant_propagation_engine_compact_mutation_test.sh"
PACK="$HERE/covenant_propagation_anchors.tsv"
H="$(cd "$HERE/../hooks" 2>/dev/null && pwd)"
CSUITE="$H/test_credential_scan_lib.sh"; LIB="$H/credential_scan_lib.sh"
AKIA="$H/test_credential_scan_lib_akia_literal_free.sh"; META="$H/test_credential_scan_lib_subsuite_mutation_test.sh"
CORE="$HERE/cm_core_scripts_project_literal_free_mutation_test.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
for f in "$CHK" "$SUITE" "$ENGINE" "$ST" "$PACK" "$HERE/lib/pointer_carrier.sh" "$HERE/lib/covenant_propagation_mutation_engine.sh" \
         "$CSUITE" "$LIB" "$AKIA" "$META" "$CORE"; do
    [ -f "$f" ] || { echo "ENV: missing $f"; exit 2; }
done
SUMS="$(sha256sum "$CHK" "$SUITE" "$ENGINE" "$CSUITE" "$LIB")"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/verdict_set_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT INT TERM
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
echo "=== §1.1 paired mutation for suite_verdict_set_check.sh ==="

# ---------------------------------------------------------------- Part A: fixtures
FX="$TMPD/fx"; mkdir -p "$FX/eng/lib" "$FX/noeng"; : > "$FX/eng/lib/covenant_propagation_engine.sh"
e() { printf '%-36s %-5s %s\n' "$1" "$2" "$3"; }
cg_body() { # $1 accounting(yes|no) $2 gate-line rc $3 nonzero-count in the summary $4 dup(yes|no)
    e GATE EXIT VERDICT; e "------------------------------------" "-----" "----------------------------------"
    e CM-COVENANT-PROPAGATION-ENGINE-SELFTEST 0 "=== MUTATION PAIR VALID ==="
    [ "$1" = yes ] && e CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING 0 "=== ACCOUNTING PAIR VALID ==="
    e CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK 0 "=== VERDICT-SET CHECK PAIR VALID ==="
    e CM-COVENANT-114-999-PROPAGATION "$2" "fixture gate"
    [ "$4" = yes ] && e CM-COVENANT-114-999-PROPAGATION 0 "fixture gate"
    local n=3; [ "$1" = yes ] && n=4; [ "$4" = yes ] && n=$((n+1))
    echo "----------------------------------------------------------------------"
    echo "suite(gates): $n entries, $((n-$3)) exit-0, $3 non-zero — over 8 carrier(s)"
}
cg_body yes 0 0 no > "$FX/CG0"; cg_body no 0 0 no > "$FX/CG1"; cg_body yes 1 0 no > "$FX/CG2"
grep -v '^suite(gates)' "$FX/CG0" > "$FX/CG3"; cp "$FX/CG0" "$FX/CG4"; cg_body yes 0 0 yes > "$FX/CG5"
{ e GATE EXIT VERDICT; e "------------------------------------" "-----" "----------------------------------"
  e cm_covenant_114_900_propagation.sh 0 "stub"; e cm_covenant_114_901_propagation.sh 0 "stub"
  echo "----------------------------------------------------------------------"
  echo "suite(gates): 2 entries, 2 exit-0, 0 non-zero — over unknown carrier(s)"; } > "$FX/CG6"
cs_body() { # $1 z-text $2 extra-fail(yes|no) $3 x(yes|no) $4 result(yes|no)
    echo "== credential_scan_lib.sh — self-validating golden fixtures =="
    echo "PASS: (a) fixture"; echo "PASS: (b) fixture"
    [ "$3" = yes ] && echo "PASS: (x) AKIA-literal-free sub-suite (rc=0, 10 sub-checks passed, 0 failed)"
    [ "$2" = yes ] && echo "FAIL: (x) AKIA-literal-free sub-suite (rc=1, 9 PASS / 1 FAIL line(s)) -- last lines:"
    echo "PASS: (y) core-scripts project-literal-free sub-suite (rc=0, 23 sub-checks passed, 0 failed)"
    printf '%s\n' "$1"
    local p=4; [ "$3" = yes ] && p=5
    case "$1" in INFO:*) p=$((p-1)) ;; esac
    [ "$4" = yes ] && echo "== RESULT: $p passed, 0 failed =="
    return 0
}
ZOK='PASS: (z) sub-suite wiring meta-test: === SUB-SUITE WIRING PAIR VALID: 7 directions demonstrated, 6 wiring mutants seen ==='
ZND='PASS: (z) sub-suite wiring meta-test: === SUB-SUITE WIRING PAIR NOT DEMONSTRATED: 7 failure(s) ==='
ZIN='INFO: (z) sub-suite wiring meta-test not re-entered inside its own sandbox'
cs_body "$ZOK" no yes yes > "$FX/CS0"; cs_body "$ZND" no yes yes > "$FX/CS1"; cs_body "$ZOK" yes yes yes > "$FX/CS2"
cs_body "$ZOK" no no yes > "$FX/CS3"; cs_body "$ZIN" no yes yes > "$FX/CS4"; cs_body "$ZOK" no yes no > "$FX/CS5"
# fixture -> profile rc suite-dir expected
FIXTURES="CG0 covenant-gates 0 eng VALID
CG1 covenant-gates 0 eng INVALID
CG2 covenant-gates 0 eng INVALID
CG3 covenant-gates 0 eng INVALID
CG4 covenant-gates 1 eng INVALID
CG5 covenant-gates 0 eng INVALID
CG6 covenant-gates 0 noeng VALID
CS0 credscan-suite 0 eng VALID
CS1 credscan-suite 0 eng INVALID
CS2 credscan-suite 0 eng INVALID
CS3 credscan-suite 0 eng INVALID
CS4 credscan-suite 0 eng INVALID
CS5 credscan-suite 0 eng INVALID"
verdict_of() { # $1 checker  $2 fixture id -> VALID|INVALID|ERR<rc>
    local line prof rc sd
    line="$(printf '%s\n' "$FIXTURES" | awk -v id="$2" '$1 == id')"
    prof="$(echo "$line" | awk '{print $2}')"; rc="$(echo "$line" | awk '{print $3}')"; sd="$(echo "$line" | awk '{print $4}')"
    bash "$1" --profile "$prof" --rc "$rc" --suite-dir "$FX/$sd" --file "$FX/$2" > "$TMPD/chk.out" 2>&1
    case $? in 0) echo VALID ;; 1) echo INVALID ;; *) echo "ERR$?" ;; esac
}
while read -r id prof rc sd want; do
    got="$(verdict_of "$CHK" "$id")"
    [ "$got" = "$want" ] && ok "$id ($prof) -> $got" || bad "$id ($prof) -> $got (expected $want): $(head -2 "$TMPD/chk.out" | tr '\n' ' ')"
done <<<"$FIXTURES"
KC="$TMPD/chk_copy.sh"
kpair() { # $1 id  $2 fixture  $3 old  $4 new
    cp "$CHK" "$KC"
    if ! edit "$KC" "$3" "$4"; then bad "$1: checker mutant not applied exactly once (or the copy no longer parses) — re-anchor it"; return; fi
    [ "$(verdict_of "$KC" "$2")" = VALID ] && ok "$1: $2 reads VALID under the mutant — seen" \
        || bad "$1: $2 still INVALID under the mutant — the rule is not load-bearing for this fixture alone"
}
kpair K1 CG1 'if [ -z "$got" ]; then invalid "named entry missing: $name"' 'if [ -z "$got" ]; then : "named entry missing: $name"'
kpair K2 CG2 '[ "$n_nonzero" -eq "$B" ] || invalid' 'true || invalid'
kpair K3 CG4 '[ "$RC" = 0 ] || invalid' 'true || invalid'
kpair K4 CS1 '[ "$zv" = 1 ] && [ "$zn" = 0 ] || invalid' 'true || invalid'
kpair K5 CS2 '[ "$n_fail" -eq "$F" ] || invalid' 'true || invalid'
kpair K6 CS3 '[ "$c" = 1 ] || invalid' 'true || invalid'

# ---------------------------------------------------------------- Part B: covenant suite, end to end
SB="$TMPD/gates"; ROOTD="$TMPD/root"; STUBPACK="$TMPD/stub_pack.tsv"
mkdir -p "$SB/lib" "$ROOTD"
cp "$ENGINE" "$HERE/lib/pointer_carrier.sh" "$HERE/lib/covenant_propagation_mutation_engine.sh" "$SB/lib/"
cp "$SUITE" "$ST" "$PACK" "$SB/"
# the compact self-test needs the first data-pack row's gate wrapper and mutation wrapper beside it
GATE_NAME="$(awk -F'\t' '/^#/{next} NF>=2 && $1!="" {print $1; exit}' "$PACK")"
ANCHOR="$(awk -F'\t' -v g="$GATE_NAME" '/^#/{next} $1==g {print $2; exit}' "$PACK")"
for w in "$HERE/cm_covenant_114_${ANCHOR#11.4.}_propagation.sh" "$HERE/cm_covenant_114_${ANCHOR#11.4.}_propagation_mutation_test.sh"; do
    [ -f "$w" ] || { echo "ENV: missing $w"; exit 2; }; cp "$w" "$SB/"
done
printf 'CM-COVENANT-114-999-PROPAGATION\t11.4.999\n' > "$STUBPACK"
printf '#!/usr/bin/env bash\necho "✅ CM-COVENANT-114-999-PROPAGATION: sandbox stub gate"\nexit 0\n' > "$SB/cm_covenant_114_999_propagation.sh"
printf '#!/usr/bin/env bash\necho "=== ACCOUNTING PAIR VALID: sandbox stub ==="\nexit 0\n' > "$SB/covenant_propagation_suite_accounting_mutation_test.sh"
printf '#!/usr/bin/env bash\necho "=== VERDICT-SET CHECK PAIR VALID: sandbox stub ==="\nexit 0\n' > "$SB/suite_verdict_set_check_mutation_test.sh"
cov_run() { # -> R_RC, R_V (checker verdict), R_OUT
    R_OUT="$(env -u COVENANT_PROPAGATION_CARRIERS -u COVENANT_PROPAGATION_SUITE_INNER COVENANT_PROPAGATION_ANCHORS="$STUBPACK" \
             bash "$SB/covenant_propagation_suite.sh" gates --root "$ROOTD" 2>&1)"; R_RC=$?
    printf '%s\n' "$R_OUT" | bash "$CHK" --profile covenant-gates --rc "$R_RC" --suite-dir "$SB" > "$TMPD/chk.out" 2>&1
    case $? in 0) R_V=VALID ;; 1) R_V=INVALID ;; *) R_V=ERR ;; esac
}
reset_cov() { # $1 real|stub compact self-test (stub = passes at once; the real one runs about 18 s clean)
    cp "$SUITE" "$SB/covenant_propagation_suite.sh"; cp "$ENGINE" "$SB/lib/covenant_propagation_engine.sh"
    if [ "${1:-stub}" = real ]; then cp "$ST" "$SB/"
    else printf '#!/usr/bin/env bash\necho "=== MUTATION PAIR VALID: sandbox stub ==="\nexit 0\n' > "$SB/$(basename "$ST")"; fi
}
reset_cov; cov_run
[ "$R_RC" = 0 ] && [ "$R_V" = VALID ] && ok "RB0 unmutated covenant suite -> rc 0, checker VALID" \
    || bad "RB0 unmutated covenant suite -> rc $R_RC, checker $R_V (expected 0 / VALID): $(head -2 "$TMPD/chk.out" | tr '\n' ' ')"
RX1_OLD='&& [ -z "${COVENANT_PROPAGATION_SUITE_INNER:-}" ]; then'
RX1_NEW='&& [ -n "${COVENANT_PROPAGATION_SUITE_INNER:-}" ]; then'
reset_cov
if edit "$SB/covenant_propagation_suite.sh" "$RX1_OLD" "$RX1_NEW"; then
    cov_run
    if [ "$R_RC" = 0 ] && [ "$R_V" = INVALID ] && grep -q 'named entry missing: CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING' "$TMPD/chk.out"; then
        ok "RX1 (verbatim) ACCOUNTING entry silenced -> suite rc 0, checker INVALID (named entry missing)"
    else bad "RX1 -> suite rc $R_RC, checker $R_V: $(head -2 "$TMPD/chk.out" | tr '\n' ' ')"; fi
else bad "RX1 mutant text not applied exactly once — re-anchor it"; fi
reset_cov real
if edit "$SB/covenant_propagation_suite.sh" "$RX1_OLD" "$RX1_NEW" \
   && edit "$SB/covenant_propagation_suite.sh" 'if [ "$rc" -ne 0 ]; then bad=$((bad+1)); fi' 'if false; then bad=$((bad+1)); fi' \
   && edit "$SB/lib/covenant_propagation_engine.sh" 'if [ "${_cpe_tcount:-0}" -eq 1 ]; then' 'if [ "${_cpe_tcount:-0}" -ge 1 ]; then'; then
    cov_run
    st="$(printf '%s\n' "$R_OUT" | awk '$1=="CM-COVENANT-PROPAGATION-ENGINE-SELFTEST"{print $2}')"
    if [ "$R_RC" = 0 ] && [ "${st:-0}" != 0 ] && [ "$R_V" = INVALID ]; then
        ok "RX1+SA1+ME1 (the round-3 survivor) -> suite rc 0 with SELFTEST rc $st, checker INVALID"
    else bad "RX1+SA1+ME1 -> suite rc $R_RC, SELFTEST rc ${st:--}, checker $R_V (expected 0 / non-zero / INVALID)"; fi
else bad "RX1+SA1+ME1: a mutant text was not applied exactly once — re-anchor it"; fi

# ---------------------------------------------------------------- Part B: credscan suite, end to end
CS="$TMPD/cs"; CH="$CS/scripts/hooks"; CG="$CS/scripts/gates"; mkdir -p "$CH" "$CG"
CORE_FILES="$(sed -n 's/^FILES="\(.*\)"$/\1/p' "$CORE" | head -1)"
[ -n "$CORE_FILES" ] || { echo "ENV: core-literal guard set (FILES=) not found"; exit 2; }
reset_cs() {
    cp "$CSUITE" "$LIB" "$AKIA" "$META" "$CH/"; cp "$CORE" "$CG/"
    local g; for g in $CORE_FILES; do mkdir -p "$CS/$(dirname "$g")"; cp "$ROOT/$g" "$CS/$g"; done
}
cs_run() {
    R_OUT="$(cd "$CS" && env -u CREDSCAN_SUBSUITE_META_INNER CORE_LITERAL_CD_INNER=1 bash "$CH/test_credential_scan_lib.sh" 2>&1)"; R_RC=$?
    printf '%s\n' "$R_OUT" | bash "$CHK" --profile credscan-suite --rc "$R_RC" > "$TMPD/chk.out" 2>&1
    case $? in 0) R_V=VALID ;; 1) R_V=INVALID ;; *) R_V=ERR ;; esac
}
reset_cs; cs_run
[ "$R_RC" = 0 ] && [ "$R_V" = VALID ] && ok "RC0 unmutated credscan suite -> rc 0, checker VALID" \
    || bad "RC0 unmutated credscan suite -> rc $R_RC, checker $R_V: $(head -3 "$TMPD/chk.out" | tr '\n' ' ')"
a="AK""IA"; d="1234567890""123456"
rx3() {
    edit "$CH/test_credential_scan_lib.sh" 'if [ "$_z_rc" -eq 0 ]; then' 'if true; then' \
    && edit "$CH/test_credential_scan_lib.sh" ': $((fail += 1))' ': $((fail += 0))' \
    && edit "$CH/credential_scan_lib.sh" "='^${a}''${d}\$'" "='^${a}''[0-9]{16}\$'"
}
reset_cs
if rx3; then
    cs_run
    [ "$R_V" = INVALID ] && ok "RX3 (verbatim: (z) forced + SM4 + MX1b) -> suite rc $R_RC, checker INVALID" \
        || bad "RX3 -> suite rc $R_RC, checker $R_V (expected INVALID)"
else bad "RX3: a mutant text was not applied exactly once — re-anchor it"; fi
reset_cs
if rx3 && edit "$CH/test_credential_scan_lib.sh" '*"PAIR VALID"*) ok "(z) sub-suite wiring meta-test: $_z_v" ;;' '*) ok "(z) sub-suite wiring meta-test: $_z_v" ;;'; then
    cs_run
    if [ "$R_RC" = 0 ] && [ "$R_V" = INVALID ] && grep -q 'PAIR VALID' "$TMPD/chk.out"; then
        ok "RX3c (RX3 + (z)'s own verdict case neutralised) -> suite rc 0, checker INVALID on the (z) verdict"
    else bad "RX3c -> suite rc $R_RC, checker $R_V: $(head -3 "$TMPD/chk.out" | tr '\n' ' ')"; fi
else bad "RX3c: a mutant text was not applied exactly once — re-anchor it"; fi

[ "$(sha256sum "$CHK" "$SUITE" "$ENGINE" "$CSUITE" "$LIB")" = "$SUMS" ] && ok "tracked checker, suites, engine and library unchanged" \
    || bad "a tracked file changed during the test"
if [ "$fails" -eq 0 ]; then echo "=== VERDICT-SET CHECK PAIR VALID: 13 fixtures, 6 checker mutants seen, RX1 / RX1+SA1+ME1 / RX3 / RX3c caught end to end ==="; exit 0; fi
echo "=== VERDICT-SET CHECK PAIR NOT DEMONSTRATED: $fails failure(s) ==="; exit 1
