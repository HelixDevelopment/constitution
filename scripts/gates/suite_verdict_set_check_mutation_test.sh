#!/usr/bin/env bash
# suite_verdict_set_check_mutation_test.sh — §1.1 paired-mutation test for suite_verdict_set_check.sh, the
# consumer-side reader of the covenant-propagation suite and the credential-scan suite (round-4 review N6/N7,
# rebuilt as a rule table in round 6 after round-5 review N16/N17: a rule must not exist without a fixture
# and a mutant of its own, and the test FAILs when the checker grows a rule id the table does not list).
#
# ── Part A: the rule table (every rule id of the checker, one row or more each) ──
# For every row: the fixture is INVALID under the real checker with EXACTLY the listed rule id(s) and no other
# (so the fixture isolates the rule), and each listed checker mutant (applied to a copy: the rule line's test
# replaced by `true`, or the exact edit named) turns that fixture VALID (so the rule line is load-bearing).
# A real checker carrying any of these mutants therefore FAILs this test (the fixture no longer reads INVALID).
#
#   rule id          fixture                                                        mutant(s)
#   R-RC     cov     CG0 read with --rc 1                                          R-RC line off
#   R-RC     cs      CS0 read with --rc 1                                          R-RC line off
#   R-INNER  cov     CG0 + `INNER-MODE: COVENANT_PROPAGATION_SUITE_INNER …`        R-INNER line off
#   R-INNER  cs      CS0 + `INNER-MODE: CORE_LITERAL_CD_INNER …` (relayed by (y))   R-INNER line off
#   R-INNER  cs      CS0 + `INNER-MODE: CREDSCAN_SUBSUITE_META_INNER …`            R-INNER line off
#   C-SUM            CG0 without the summary line                                  C-SUM line off
#   C-SUM            CG0 with the summary line twice                               C-SUM line off
#   C-B0             summary `4 entries, 3 exit-0, 1 non-zero`, gate row rc 1      C-B0 line off
#   C-ENB            summary `4 entries, 3 exit-0, 0 non-zero`                     C-ENB line off
#   C-RULES          the header underline printed twice                           C-RULES line off
#   C-INT            the gate row's rc printed as `0.0`                           C-INT line off
#   C-ROWS           summary counts 5 entries, 4 rows printed                      C-ROWS line off
#   C-NZ             gate row rc 1, summary `0 non-zero` (an uncounted failure)    C-NZ line off
#   C-DUP            the gate row printed twice, summary counts 5                  C-DUP line off
#   C-NAMED          ENGINE-SELFTEST row missing                                   C-NAMED rule off; that name dropped from the list
#   C-NAMED          SUITE-ACCOUNTING row missing (the RX1 shape)                  C-NAMED rule off; that name dropped from the list
#   C-NAMED          VERDICT-SET-CHECK row missing                                 C-NAMED rule off; that name dropped (= reviewer RV5)
#   S-RES            CS0 without the RESULT line                                   S-RES line off
#   S-RES            CS0 with the RESULT line twice                                S-RES line off
#   S-F0             RESULT `… 1 failed` with one FAIL line printed                S-F0 line off
#   S-NP             one PASS line more than RESULT counts                         S-NP line off
#   S-NF             a FAIL line printed while RESULT counts 0 failed              S-NF line off
#   S-X              the (x) verdict line missing                                  S-X line off
#   S-Y              the (y) verdict line missing                                  S-Y line off
#   S-ZV             the (z) verdict line missing                                  S-ZV line off
#   S-ZN             a second (z) PASS line saying NOT DEMONSTRATED                S-ZN line off
#   S-ZV+S-ZN        `PASS: (z) … PAIR NOT DEMONSTRATED` alone (the RX3 shape)      both lines off together
# Negative controls (§11.4.201(1)): CG0 and CS0 read VALID.
#
# ── Part B: end to end on real suite copies ──────────────────────────────────────
# Covenant (sandbox: the REAL suite and engine + libs, stub ACCOUNTING / VERDICT-SET self-tests that pass, a
# one-row stub pack whose gate passes; the compact self-test is a passing stub except in RX1+SA1+ME1):
#   RB0 unmutated                                   -> suite rc 0, checker VALID
#   RX1 ACCOUNTING guard `-z` -> `-n` (verbatim)    -> suite rc 0, checker INVALID [C-NAMED]
#   RX1+SA1+ME1 (the round-3 survivor)              -> suite rc 0 with a failing SELFTEST row, checker INVALID
#   RV5 (reviewer, round 5, verbatim): the suite's VERDICT-SET guard `= ""` -> `!= ""` -> the real checker reads
#       INVALID [C-NAMED]; the checker copy with VERDICT-SET-CHECK dropped from its list reads that output VALID
#       (the list member is what catches it end to end; Part A row C-NAMED/verdict-set pins it)
#   IN1 COVENANT_PROPAGATION_SUITE_INNER inherited from the caller's environment -> checker INVALID with
#       [R-INNER] among the reasons (the suite announces its inner mode; without the announcement only C-NAMED
#       would remain and this row FAILs)
# Credential-scan (sandbox: the REAL suite, library, AKIA sub-suite and (z) meta-test; the core-literal (y)
# sub-suite is a passing stub in RC0 / RX3 / RX3c / IN3, where (y) is not under test, and the REAL one in IN2*):
#   RC0 unmutated                                   -> suite rc 0, checker VALID
#   RX3 (z) forced + SM4 + MX1b (verbatim)          -> checker INVALID
#   RX3c RX3 + (z)'s own PAIR VALID case neutralised -> suite rc 0, checker INVALID [S-ZV]
#   IN2 CORE_LITERAL_CD_INNER inherited (= reviewer RV2, round 5, verbatim) with the REAL (y) -> the suite relays
#       the core-literal test's `INNER-MODE:` line, checker INVALID [R-INNER]
#   IN2r the relay line removed from the suite copy -> the line is gone (the relay is load-bearing)
#   IN2m the announcement removed from the core-literal copy -> the line is gone (the announcement is load-bearing)
#   IN3 CREDSCAN_SUBSUITE_META_INNER inherited      -> checker INVALID with [R-INNER] among the reasons
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
SUMS="$(sha256sum "$CHK" "$SUITE" "$ENGINE" "$CSUITE" "$LIB" "$CORE")"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/verdict_set_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT INT TERM
fails=0; nrows=0; nmut=0
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
rule_off() { # $1 file  $2 rule id -> the one `<test> || invalid <ID> …` line's test becomes `true`; rc 0 iff exactly one
    python3 - "$1" "$2" <<'PY' || return 1
import re, sys
p, rid = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
pat = re.compile(r'^([ \t]*)(\S.*?) \|\| invalid ' + re.escape(rid) + r' ', re.M)
if len(pat.findall(s)) != 1:
    sys.exit(3)
s = pat.sub(lambda mo: mo.group(1) + 'true || invalid ' + rid + ' ', s, count=1)
open(p, 'w', encoding='utf-8').write(s)
PY
    bash -n "$1"
}
drop_name() { # $1 file  $2 name -> the name removed from the checker's one `for name in …; do` list
    python3 - "$1" "$2" <<'PY' || return 1
import re, sys
p, name = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
lines = [i for i, l in enumerate(s.split('\n')) if re.match(r'^\s*for name in .*; do\s*$', l)]
if len(lines) != 1:
    sys.exit(3)
ls = s.split('\n'); l = ls[lines[0]]
head, rest = l.split('for name in ', 1); names, tail = rest.split('; do', 1)
toks = names.split()
if toks.count(name) != 1:
    sys.exit(4)
toks.remove(name)
ls[lines[0]] = head + 'for name in ' + ' '.join(toks) + '; do' + tail
open(p, 'w', encoding='utf-8').write('\n'.join(ls))
PY
    bash -n "$1"
}
echo "=== §1.1 paired mutation for suite_verdict_set_check.sh ==="

# ---------------------------------------------------------------- Part A: fixtures
FX="$TMPD/fx"; mkdir -p "$FX"
e() { printf '%-36s %-5s %s\n' "$1" "$2" "$3"; }
HDR_U="$(e "------------------------------------" "-----" "----------------------------------")"
FOOT="----------------------------------------------------------------------"
cg() { # $1 named rows to omit (SELFTEST|ACCOUNTING|VERDICT)  $2 gate rc  $3 summary text|NONE|TWICE  $4 dupgate|dblhdr|''
    e GATE EXIT VERDICT
    printf '%s\n' "$HDR_U"; [ "$4" = dblhdr ] && printf '%s\n' "$HDR_U"
    case " $1 " in *" SELFTEST "*) ;; *) e CM-COVENANT-PROPAGATION-ENGINE-SELFTEST 0 "=== MUTATION PAIR VALID ===" ;; esac
    case " $1 " in *" ACCOUNTING "*) ;; *) e CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING 0 "=== ACCOUNTING PAIR VALID ===" ;; esac
    case " $1 " in *" VERDICT "*) ;; *) e CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK 0 "=== VERDICT-SET CHECK PAIR VALID ===" ;; esac
    e CM-COVENANT-114-999-PROPAGATION "$2" "fixture gate"
    [ "$4" = dupgate ] && e CM-COVENANT-114-999-PROPAGATION 0 "fixture gate"
    printf '%s\n' "$FOOT"
    case "$3" in
        NONE) ;;
        TWICE) echo "suite(gates): 4 entries, 4 exit-0, 0 non-zero — over 8 carrier(s)"
               echo "suite(gates): 4 entries, 4 exit-0, 0 non-zero — over 8 carrier(s)" ;;
        *) echo "suite(gates): $3 — over 8 carrier(s)" ;;
    esac
    return 0
}
cg ""         0   "4 entries, 4 exit-0, 0 non-zero" ""      > "$FX/CG0"
{ echo "INNER-MODE: COVENANT_PROPAGATION_SUITE_INNER set — the ACCOUNTING and VERDICT-SET self-test entries are skipped"; cat "$FX/CG0"; } > "$FX/CG_INNER"
cg ""         0   NONE                              ""      > "$FX/CG_SUM0"
cg ""         0   TWICE                             ""      > "$FX/CG_SUM2"
cg ""         1   "4 entries, 3 exit-0, 1 non-zero" ""      > "$FX/CG_B0"
cg ""         0   "4 entries, 3 exit-0, 0 non-zero" ""      > "$FX/CG_ENB"
cg ""         0   "4 entries, 4 exit-0, 0 non-zero" dblhdr  > "$FX/CG_RULES"
cg ""         0.0 "4 entries, 4 exit-0, 0 non-zero" ""      > "$FX/CG_INT"
cg ""         0   "5 entries, 5 exit-0, 0 non-zero" ""      > "$FX/CG_ROWS"
cg ""         1   "4 entries, 4 exit-0, 0 non-zero" ""      > "$FX/CG_NZ"
cg ""         0   "5 entries, 5 exit-0, 0 non-zero" dupgate > "$FX/CG_DUP"
cg SELFTEST   0   "3 entries, 3 exit-0, 0 non-zero" ""      > "$FX/CG_NSELF"
cg ACCOUNTING 0   "3 entries, 3 exit-0, 0 non-zero" ""      > "$FX/CG_NACC"
cg VERDICT    0   "3 entries, 3 exit-0, 0 non-zero" ""      > "$FX/CG_NVS"
XL='PASS: (x) AKIA-literal-free sub-suite (rc=0, 10 sub-checks passed, 0 failed)'
YL='PASS: (y) core-scripts project-literal-free sub-suite (rc=0, 34 sub-checks passed, 0 failed)'
ZOK='PASS: (z) sub-suite wiring meta-test: === SUB-SUITE WIRING PAIR VALID: 7 directions demonstrated, 6 wiring mutants seen ==='
ZND='PASS: (z) sub-suite wiring meta-test: === SUB-SUITE WIRING PAIR NOT DEMONSTRATED: 7 failure(s) ==='
cs() { # $1 RESULT line ('' = none)  $2.. body lines
    local res="$1"; shift
    echo "== credential_scan_lib.sh — self-validating golden fixtures =="
    printf '%s\n' "$@"; echo ""
    [ -n "$res" ] && printf '%s\n' "$res"
    return 0
}
R5='== RESULT: 5 passed, 0 failed =='; R4='== RESULT: 4 passed, 0 failed =='
cs "$R5" "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$YL" "$ZOK" > "$FX/CS0"
cs "$R5" "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "INNER-MODE: CORE_LITERAL_CD_INNER set — M1-M11 and the CD consumer-data section are skipped" "$YL" "$ZOK" > "$FX/CS_INNERY"
cs "$R5" "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$YL" "$ZOK" "INNER-MODE: CREDSCAN_SUBSUITE_META_INNER set — (z) not re-entered" > "$FX/CS_INNERZ"
cs ""    "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$YL" "$ZOK" > "$FX/CS_RES0"
{ cat "$FX/CS0"; echo "$R5"; } > "$FX/CS_RES2"
cs '== RESULT: 5 passed, 1 failed ==' "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$YL" "$ZOK" "FAIL: (c) fixture" > "$FX/CS_F0"
cs "$R5" "PASS: (a) fixture" "PASS: (b) fixture" "PASS: (c) fixture" "$XL" "$YL" "$ZOK" > "$FX/CS_NP"
cs "$R5" "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "FAIL: (c) fixture" "$YL" "$ZOK" > "$FX/CS_NF"
cs "$R4" "PASS: (a) fixture" "PASS: (b) fixture" "$YL" "$ZOK" > "$FX/CS_X"
cs "$R4" "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$ZOK" > "$FX/CS_Y"
cs "$R4" "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$YL" > "$FX/CS_ZV"
cs '== RESULT: 6 passed, 0 failed ==' "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$YL" "$ZOK" "$ZND" > "$FX/CS_ZN"
cs "$R5" "PASS: (a) fixture" "PASS: (b) fixture" "$XL" "$YL" "$ZND" > "$FX/CS_RX3"
# row-id fixture profile rc expected-rule-ids(comma; '-' = VALID) mutants(';' list of off:<ID> | named-off | drop:<NAME>, '+' joins)
TABLE="NC-COV CG0 covenant-gates 0 - -
NC-CS CS0 credscan-suite 0 - -
R-RC/cov CG0 covenant-gates 1 R-RC off:R-RC
R-RC/cs CS0 credscan-suite 1 R-RC off:R-RC
R-INNER/cov CG_INNER covenant-gates 0 R-INNER off:R-INNER
R-INNER/cs-y CS_INNERY credscan-suite 0 R-INNER off:R-INNER
R-INNER/cs-z CS_INNERZ credscan-suite 0 R-INNER off:R-INNER
C-SUM/none CG_SUM0 covenant-gates 0 C-SUM off:C-SUM
C-SUM/twice CG_SUM2 covenant-gates 0 C-SUM off:C-SUM
C-B0 CG_B0 covenant-gates 0 C-B0 off:C-B0
C-ENB CG_ENB covenant-gates 0 C-ENB off:C-ENB
C-RULES CG_RULES covenant-gates 0 C-RULES off:C-RULES
C-INT CG_INT covenant-gates 0 C-INT off:C-INT
C-ROWS CG_ROWS covenant-gates 0 C-ROWS off:C-ROWS
C-NZ CG_NZ covenant-gates 0 C-NZ off:C-NZ
C-DUP CG_DUP covenant-gates 0 C-DUP off:C-DUP
C-NAMED/selftest CG_NSELF covenant-gates 0 C-NAMED named-off;drop:CM-COVENANT-PROPAGATION-ENGINE-SELFTEST
C-NAMED/accounting CG_NACC covenant-gates 0 C-NAMED named-off;drop:CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING
C-NAMED/verdict-set CG_NVS covenant-gates 0 C-NAMED named-off;drop:CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK
S-RES/none CS_RES0 credscan-suite 0 S-RES off:S-RES
S-RES/twice CS_RES2 credscan-suite 0 S-RES off:S-RES
S-F0 CS_F0 credscan-suite 0 S-F0 off:S-F0
S-NP CS_NP credscan-suite 0 S-NP off:S-NP
S-NF CS_NF credscan-suite 0 S-NF off:S-NF
S-X CS_X credscan-suite 0 S-X off:S-X
S-Y CS_Y credscan-suite 0 S-Y off:S-Y
S-ZV CS_ZV credscan-suite 0 S-ZV off:S-ZV
S-ZN CS_ZN credscan-suite 0 S-ZN off:S-ZN
RX3-shape CS_RX3 credscan-suite 0 S-ZN,S-ZV off:S-ZV+off:S-ZN"
ids_of() { sed -n 's/^VERDICT-SET: INVALID \[\([A-Z0-9-]*\)\].*/\1/p' "$1" | sort -u | paste -sd, -; }
run_chk() { # $1 checker  $2 fixture  $3 profile  $4 rc -> echo VALID|INVALID|ERR<rc>; ids in $TMPD/ids
    bash "$1" --profile "$3" --rc "$4" --file "$FX/$2" > "$TMPD/chk.out" 2>&1; local r=$?
    ids_of "$TMPD/chk.out" > "$TMPD/ids"
    case $r in 0) echo VALID ;; 1) echo INVALID ;; *) echo "ERR$r" ;; esac
}
apply_mut() { # $1 copy  $2 spec -> rc 0 iff every part applied exactly once
    local spec="$2" part rest
    while [ -n "$spec" ]; do
        part="${spec%%+*}"; rest="${spec#*+}"; [ "$rest" = "$spec" ] && rest=""
        case "$part" in
            off:*)     rule_off "$1" "${part#off:}" || return 1 ;;
            named-off) edit "$1" 'else invalid C-NAMED "named entry missing: $name"; fi' 'else :; fi' || return 1 ;;
            drop:*)    drop_name "$1" "${part#drop:}" || return 1 ;;
            *) return 1 ;;
        esac
        spec="$rest"
    done
}
KC="$TMPD/chk_copy.sh"
while read -r id fx prof rc want muts; do
    nrows=$((nrows + 1))
    got="$(run_chk "$CHK" "$fx" "$prof" "$rc")"; ids="$(cat "$TMPD/ids")"
    if [ "$want" = - ]; then
        [ "$got" = VALID ] && ok "$id: $fx -> VALID (negative control)" || bad "$id: $fx -> $got [$ids] (expected VALID)"
        continue
    fi
    if [ "$got" = INVALID ] && [ "$ids" = "$want" ]; then ok "$id: $fx -> INVALID [$ids] (isolated)"
    else bad "$id: $fx -> $got [$ids] (expected INVALID [$want] and no other rule)"; continue; fi
    IFS=';' read -r -a mlist <<<"$muts"
    for m in "${mlist[@]}"; do
        cp "$CHK" "$KC"
        if ! apply_mut "$KC" "$m"; then bad "$id: checker mutant '$m' not applied exactly once (or the copy no longer parses) — re-anchor it"; continue; fi
        nmut=$((nmut + 1))
        g2="$(run_chk "$KC" "$fx" "$prof" "$rc")"
        [ "$g2" = VALID ] && ok "$id: mutant '$m' -> $fx reads VALID — the rule line is load-bearing" \
            || bad "$id: mutant '$m' -> $fx still $g2 [$(cat "$TMPD/ids")] — the rule is not load-bearing for its own fixture"
    done
done <<<"$TABLE"
# every rule id the checker emits has at least one row (a new rule without a row FAILs here)
nids=0; RIDS="$(grep -oE 'invalid [A-Z]+-[A-Z0-9]+ ' "$CHK" | awk '{print $2}' | sort -u)"
for rid in $RIDS; do
    nids=$((nids + 1))
    printf '%s\n' "$TABLE" | awk -v r="$rid" '{n = split($5, a, ","); for (i = 1; i <= n; i++) if (a[i] == r) f = 1} END {exit !f}' \
        && ok "rule $rid has a row" || bad "rule $rid has no row in the table — a new rule needs a fixture and a mutant"
done
# control needle: the extraction must see the known rule ids R-RC and S-ZN (one per end of the file) and many more
# (here-strings, not `printf | grep -q`: under `set -o pipefail` an early-exiting grep -q can SIGPIPE the producer and read as failure — CM-SIGPIPE-PIPEFAIL-CLASS)
if [ "$nids" -ge 10 ] && grep -qx R-RC <<<"$RIDS" && grep -qx S-ZN <<<"$RIDS"; then
    ok "control needle: $nids rule ids read from the checker (R-RC and S-ZN among them)"
else bad "control needle BLIND: $nids rule id(s) read from the checker"; fi

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
cov_run() { # $1 checker ('' = the real one)  $2 optional env assignment -> R_RC, R_V, R_OUT; ids in $TMPD/ids
    R_OUT="$(env -u COVENANT_PROPAGATION_CARRIERS -u COVENANT_PROPAGATION_SUITE_INNER COVENANT_PROPAGATION_ANCHORS="$STUBPACK" ${2:+"$2"} \
             bash "$SB/covenant_propagation_suite.sh" gates --root "$ROOTD" 2>&1)"; R_RC=$?
    printf '%s\n' "$R_OUT" | bash "${1:-$CHK}" --profile covenant-gates --rc "$R_RC" > "$TMPD/chk.out" 2>&1
    case $? in 0) R_V=VALID ;; 1) R_V=INVALID ;; *) R_V=ERR ;; esac
    ids_of "$TMPD/chk.out" > "$TMPD/ids"
}
reset_cov() { # $1 real|stub compact self-test (stub = passes at once; the real one runs about 18 s clean)
    cp "$SUITE" "$SB/covenant_propagation_suite.sh"; cp "$ENGINE" "$SB/lib/covenant_propagation_engine.sh"
    if [ "${1:-stub}" = real ]; then cp "$ST" "$SB/"
    else printf '#!/usr/bin/env bash\necho "=== MUTATION PAIR VALID: sandbox stub ==="\nexit 0\n' > "$SB/$(basename "$ST")"; fi
}
has_id() { case ",$(cat "$TMPD/ids")," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
reset_cov; cov_run
[ "$R_RC" = 0 ] && [ "$R_V" = VALID ] && ok "RB0 unmutated covenant suite -> rc 0, checker VALID" \
    || bad "RB0 unmutated covenant suite -> rc $R_RC, checker $R_V (expected 0 / VALID): $(head -2 "$TMPD/chk.out" | tr '\n' ' ')"
RX1_OLD='&& [ -z "${COVENANT_PROPAGATION_SUITE_INNER:-}" ]; then'
RX1_NEW='&& [ -n "${COVENANT_PROPAGATION_SUITE_INNER:-}" ]; then'
reset_cov
if edit "$SB/covenant_propagation_suite.sh" "$RX1_OLD" "$RX1_NEW"; then
    cov_run
    if [ "$R_RC" = 0 ] && [ "$R_V" = INVALID ] && grep -q 'named entry missing: CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING' "$TMPD/chk.out"; then
        ok "RX1 (verbatim) ACCOUNTING entry silenced -> suite rc 0, checker INVALID [$(cat "$TMPD/ids")]"
    else bad "RX1 -> suite rc $R_RC, checker $R_V: $(head -2 "$TMPD/chk.out" | tr '\n' ' ')"; fi
else bad "RX1 mutant text not applied exactly once — re-anchor it"; fi
reset_cov real
if edit "$SB/covenant_propagation_suite.sh" "$RX1_OLD" "$RX1_NEW" \
   && edit "$SB/covenant_propagation_suite.sh" 'if [ "$rc" -ne 0 ]; then bad=$((bad+1)); fi' 'if false; then bad=$((bad+1)); fi' \
   && edit "$SB/lib/covenant_propagation_engine.sh" 'if [ "${_cpe_tcount:-0}" -eq 1 ]; then' 'if [ "${_cpe_tcount:-0}" -ge 1 ]; then'; then
    cov_run
    st="$(printf '%s\n' "$R_OUT" | awk '$1=="CM-COVENANT-PROPAGATION-ENGINE-SELFTEST"{print $2}')"
    if [ "$R_RC" = 0 ] && [ "${st:-0}" != 0 ] && [ "$R_V" = INVALID ]; then
        ok "RX1+SA1+ME1 (the round-3 survivor) -> suite rc 0 with SELFTEST rc $st, checker INVALID [$(cat "$TMPD/ids")]"
    else bad "RX1+SA1+ME1 -> suite rc $R_RC, SELFTEST rc ${st:--}, checker $R_V (expected 0 / non-zero / INVALID)"; fi
else bad "RX1+SA1+ME1: a mutant text was not applied exactly once — re-anchor it"; fi
# RV5 (reviewer, round 5, verbatim): the suite's VERDICT-SET guard inverted, and the checker list without that name
reset_cov
if edit "$SB/covenant_propagation_suite.sh" '&& [ "${COVENANT_PROPAGATION_SUITE_INNER:-}" = "" ]; then' \
                                            '&& [ "${COVENANT_PROPAGATION_SUITE_INNER:-}" != "" ]; then'; then
    cov_run
    if [ "$R_RC" = 0 ] && [ "$R_V" = INVALID ] && grep -q 'named entry missing: CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK' "$TMPD/chk.out"; then
        ok "RV5 suite half: VERDICT-SET entry silenced -> suite rc 0, real checker INVALID [$(cat "$TMPD/ids")]"
    else bad "RV5 suite half -> suite rc $R_RC, checker $R_V [$(cat "$TMPD/ids")] (expected 0 / INVALID, VERDICT-SET named missing)"; fi
    cp "$CHK" "$KC"
    if drop_name "$KC" CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK; then
        cov_run "$KC"
        [ "$R_V" = VALID ] && ok "RV5 checker half: the checker copy without VERDICT-SET-CHECK in its list reads that output VALID — the list member is what catches it (Part A row C-NAMED/verdict-set pins it)" \
            || bad "RV5 checker half: the mutated checker still reads $R_V [$(cat "$TMPD/ids")]"
    else bad "RV5 checker-half mutant not applied exactly once — re-anchor it"; fi
else bad "RV5 suite-half mutant text not applied exactly once — re-anchor it"; fi
# IN1: the inner flag inherited from the environment
reset_cov; cov_run "" COVENANT_PROPAGATION_SUITE_INNER=1
if [ "$R_V" = INVALID ] && has_id R-INNER; then ok "IN1 COVENANT_PROPAGATION_SUITE_INNER inherited -> checker INVALID [$(cat "$TMPD/ids")] (R-INNER present)"
else bad "IN1 COVENANT_PROPAGATION_SUITE_INNER inherited -> checker $R_V [$(cat "$TMPD/ids")] (expected INVALID with R-INNER: does the suite still announce its inner mode?)"; fi

# ---------------------------------------------------------------- Part B: credscan suite, end to end
CS="$TMPD/cs"; CH="$CS/scripts/hooks"; CG="$CS/scripts/gates"; mkdir -p "$CH" "$CG"
CORE_FILES="$(sed -n 's/^FILES="\(.*\)"$/\1/p' "$CORE" | head -1)"
[ -n "$CORE_FILES" ] || { echo "ENV: core-literal guard set (FILES=) not found"; exit 2; }
CORE_STUB='#!/usr/bin/env bash
# sandbox stub of the core-literal (y) sub-suite: (y) is not under test in RC0 / RX3 / RX3c / IN3
FILES="scripts/hooks/credential_scan_lib.sh"
for i in 1 2 3 4 5 6 7 8 9 10; do echo "PASS: stub check $i"; done
echo "SUMMARY pass=10 fail=0"; exit 0'
reset_cs() { # $1 stub|real core-literal sub-suite
    cp "$CSUITE" "$LIB" "$AKIA" "$META" "$CH/"
    if [ "${1:-stub}" = real ]; then
        cp "$CORE" "$CG/"
        local g; for g in $CORE_FILES; do mkdir -p "$CS/$(dirname "$g")"; cp "$ROOT/$g" "$CS/$g"; done
    else printf '%s\n' "$CORE_STUB" > "$CG/$(basename "$CORE")"; fi
}
cs_run() { # $@ optional env assignments -> R_RC, R_V, R_OUT; ids in $TMPD/ids
    R_OUT="$(cd "$CS" && env -u CREDSCAN_SUBSUITE_META_INNER -u CORE_LITERAL_CD_INNER "$@" bash "$CH/test_credential_scan_lib.sh" 2>&1)"; R_RC=$?
    printf '%s\n' "$R_OUT" | bash "$CHK" --profile credscan-suite --rc "$R_RC" > "$TMPD/chk.out" 2>&1
    case $? in 0) R_V=VALID ;; 1) R_V=INVALID ;; *) R_V=ERR ;; esac
    ids_of "$TMPD/chk.out" > "$TMPD/ids"
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
    [ "$R_V" = INVALID ] && ok "RX3 (verbatim: (z) forced + SM4 + MX1b) -> suite rc $R_RC, checker INVALID [$(cat "$TMPD/ids")]" \
        || bad "RX3 -> suite rc $R_RC, checker $R_V (expected INVALID)"
else bad "RX3: a mutant text was not applied exactly once — re-anchor it"; fi
reset_cs
if rx3 && edit "$CH/test_credential_scan_lib.sh" '*"PAIR VALID"*) ok "(z) sub-suite wiring meta-test: $_z_v" ;;' '*) ok "(z) sub-suite wiring meta-test: $_z_v" ;;'; then
    cs_run
    if [ "$R_RC" = 0 ] && [ "$R_V" = INVALID ] && has_id S-ZV; then
        ok "RX3c (RX3 + (z)'s own verdict case neutralised) -> suite rc 0, checker INVALID [$(cat "$TMPD/ids")]"
    else bad "RX3c -> suite rc $R_RC, checker $R_V: $(head -3 "$TMPD/chk.out" | tr '\n' ' ')"; fi
else bad "RX3c: a mutant text was not applied exactly once — re-anchor it"; fi
# IN2 (= reviewer RV2, round 5, verbatim): CORE_LITERAL_CD_INNER inherited, with the REAL (y) sub-suite
inner_line() { printf '%s\n' "$R_OUT" | grep -c '^INNER-MODE: CORE_LITERAL_CD_INNER '; }
reset_cs real; cs_run CORE_LITERAL_CD_INNER=1
if [ "$(inner_line)" = 1 ] && [ "$R_V" = INVALID ] && has_id R-INNER; then
    ok "IN2 (RV2 verbatim) CORE_LITERAL_CD_INNER inherited -> the suite relays the core-literal INNER-MODE line, checker INVALID [$(cat "$TMPD/ids")]"
else bad "IN2 CORE_LITERAL_CD_INNER inherited -> relayed line count $(inner_line), checker $R_V [$(cat "$TMPD/ids")] (expected 1 / INVALID with R-INNER)"; fi
# IN2r / IN2m: the relay and the announcement each carry that line ((z) skipped by its own inner flag: fast)
reset_cs real
if edit "$CH/test_credential_scan_lib.sh" "    printf '%s\\n' \"\$out\" | grep -E '^INNER-MODE: ' || true" "    :"; then
    cs_run CORE_LITERAL_CD_INNER=1 CREDSCAN_SUBSUITE_META_INNER=1
    [ "$(inner_line)" = 0 ] && ok "IN2r relay removed from the suite copy -> the core-literal INNER-MODE line is gone (the relay is load-bearing)" \
        || bad "IN2r relay removed -> the line is still printed ($(inner_line)) — something else prints it"
else bad "IN2r: relay mutant not applied exactly once — re-anchor it"; fi
reset_cs real
if edit "$CG/$(basename "$CORE")" '[ -z "${CORE_LITERAL_CD_INNER:-}" ] || echo "INNER-MODE: CORE_LITERAL_CD_INNER' ': || echo "INNER-MODE: CORE_LITERAL_CD_INNER'; then
    cs_run CORE_LITERAL_CD_INNER=1 CREDSCAN_SUBSUITE_META_INNER=1
    [ "$(inner_line)" = 0 ] && ok "IN2m announcement removed from the core-literal copy -> the line is gone (the announcement is load-bearing)" \
        || bad "IN2m announcement removed -> the line is still printed ($(inner_line))"
else bad "IN2m: announcement mutant not applied exactly once — re-anchor it"; fi
# IN3: CREDSCAN_SUBSUITE_META_INNER inherited
reset_cs; cs_run CREDSCAN_SUBSUITE_META_INNER=1
if [ "$R_V" = INVALID ] && has_id R-INNER; then ok "IN3 CREDSCAN_SUBSUITE_META_INNER inherited -> checker INVALID [$(cat "$TMPD/ids")] (R-INNER present)"
else bad "IN3 CREDSCAN_SUBSUITE_META_INNER inherited -> checker $R_V [$(cat "$TMPD/ids")] (expected INVALID with R-INNER: does the suite still announce its inner mode?)"; fi

[ "$(sha256sum "$CHK" "$SUITE" "$ENGINE" "$CSUITE" "$LIB" "$CORE")" = "$SUMS" ] && ok "tracked checker, suites, engine, library and core-literal test unchanged" \
    || bad "a tracked file changed during the test"
if [ "$fails" -eq 0 ]; then echo "=== VERDICT-SET CHECK PAIR VALID: $nrows rule-table rows, $nmut checker mutants seen, RX1 / RX1+SA1+ME1 / RV5 / IN1 / RX3 / RX3c / IN2 (RV2) / IN2r / IN2m / IN3 demonstrated end to end ==="; exit 0; fi
echo "=== VERDICT-SET CHECK PAIR NOT DEMONSTRATED: $fails failure(s) ==="; exit 1
