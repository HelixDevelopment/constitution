#!/bin/bash
# fastcycle-timeout-s: 600
# test_review_record_skip_status_red.sh
#
# CON-033 round 3, review R2-F3 (constitution 11.4.3, 11.4.289(E)): a
# review_record suite whose proof legs cannot run on this host printed a
# "NOTE: ... SKIPPED" line and exited 0, so every runner that reads the exit
# status counted it as PASS. That is what hid R2-F2 (the R4-CAP legs skip
# without podman and an all-root-owned chain, and RVM-B survived).
#
# Now a suite that skips a proof leg names it on a "SKIP: <leg> -- <why>"
# line and exits 77 (SKIP); the mutation runner and the sub-clause sweep
# accept a 77 control, say which suites skipped, count a mutant as killed
# only when a suite's status DIFFERS from the control's, and exit 77 (SKIP,
# not PASS) when every mutant is killed but the control skipped legs.
#
#   K1  r4 with podman unavailable (a failing `podman` first on PATH) exits
#       77, names R4-CAP-needle and R4-CAP1..R4-CAP7 on SKIP lines, fails no
#       check, and ends with "SKIP reason=proof_legs_skipped";
#   K2  subclause_cases with setfacl refused (a failing `setfacl` on PATH)
#       exits 77 and names G-T-LEAF-NO-ACL and G-T-DIR-NO-ACL;
#   K3  r2 with setfacl refused exits 77 and names T-ACL;
#   K4  the full-suite runner's judge reads that exit as SKIP with the reason
#       proof_legs_skipped (never PASS);
#   M1  mutation runner, stand-in suites: one suite always exits 77, the
#       others tell a mutant from the control -> exit 77, every mutation
#       KILLED, the skipping suite named;
#   M2  the same, but no suite tells the mutant apart (77 on both sides, 0 on
#       both sides) -> the mutant SURVIVED, exit 1 (a 77 is not a kill);
#   M3  a control suite that exits 1 -> "control mirror is RED", exit 1;
#   M4  every stand-in exits 0 on the control and 1 on a mutant -> exit 0.
#
# The M cases drive the REAL runner in a scratch copy of the tests tree whose
# suites are replaced by stand-ins (a test of the runner's own control logic,
# section 11.4.289(C)(2)); the K cases run the REAL suites. The sweep's
# handling of 77 is covered by test_sweep_review_record_subclauses_red.sh.
#
# Exit 0 = all checks passed; 1 = a check failed; 2 = setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
RUNNER_SRC="$HERE/test_review_record_gate_authority_mutations.sh"
PASS=0; FAIL=0
ok()  { echo "ok $*"; PASS=$((PASS + 1)); }
bad() { echo "NOT ok $*"; FAIL=$((FAIL + 1)); }
for f in "$RUNNER_SRC" "$FC/review/review_record.py" "$HERE/lib/review_record_genuine.sh" \
         "$HERE/test_review_record_gate_authority_r4_regression.sh" \
         "$HERE/test_review_record_subclause_cases.sh" \
         "$HERE/test_review_record_gate_authority_r2_regression.sh" \
         "$FC/../full_suite/run_full_suite.py"; do
  [ -f "$f" ] || { echo "setup: missing $f" >&2; exit 2; }
done
if [ "$(id -u)" -eq 0 ]; then echo "setup: running as root; the K cases need a non-root uid" >&2; exit 2; fi
T=$(mktemp -d) || { echo "setup: mktemp" >&2; exit 2; }
trap 'chmod -R u+rwx "${T:?}" 2>/dev/null; rm -rf -- "${T:?}"' EXIT
mkdir -p "$T/shim" "$T/tmp"
printf '#!/bin/sh\nexit 1\n' > "$T/shim/podman"
printf '#!/bin/sh\nexit 1\n' > "$T/shim/setfacl"
chmod 755 "$T/shim/podman" "$T/shim/setfacl"

# expect_skip ID OUTPUT RC LEG...  -> the suite exited 77, failed nothing, named every LEG
expect_skip() {
  local id="$1" out="$2" rc="$3" leg miss=""; shift 3
  for leg in "$@"; do
    printf '%s\n' "$out" | grep -qF "SKIP: $leg -- " || miss="$miss $leg"
  done
  if [ "$rc" = 77 ] && [ -z "$miss" ] && printf '%s\n' "$out" | grep -q 'NOT ok 0 ==' \
     && [ "$(printf '%s\n' "$out" | tail -1)" = "SKIP reason=proof_legs_skipped" ]; then
    ok "$id: exit 77 (SKIP), no failed check, every skipped leg named ($*)"
  else
    bad "$id: rc=$rc (want 77), missing SKIP lines:${miss:- none}, last line '$(printf '%s\n' "$out" | tail -1)'"
  fi
}

out=$(PATH="$T/shim:$PATH" bash "$HERE/test_review_record_gate_authority_r4_regression.sh" 2>&1); rc=$?
expect_skip K1 "$out" "$rc" R4-CAP-needle R4-CAP1 R4-CAP2 R4-CAP3 R4-CAP4 R4-CAP5 R4-CAP6 R4-CAP7
out=$(PATH="$T/shim:$PATH" bash "$HERE/test_review_record_subclause_cases.sh" 2>&1); rc=$?
expect_skip K2 "$out" "$rc" G-T-LEAF-NO-ACL G-T-DIR-NO-ACL
out=$(PATH="$T/shim:$PATH" bash "$HERE/test_review_record_gate_authority_r2_regression.sh" 2>&1); rc=$?
expect_skip K3 "$out" "$rc" T-ACL

J=$(python3 - "$FC/../full_suite/run_full_suite.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rfs", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
v = m.judge(77, False, "== Summary: ok 3 / NOT ok 0 ==\nSKIP reason=proof_legs_skipped\n", "bash")
print(v[0], v[1])
PY
)
[ "$J" = "SKIP proof_legs_skipped" ] && ok "K4: the full-suite judge reads exit 77 as SKIP (proof_legs_skipped)" \
  || bad "K4: the full-suite judge gives '$J' for exit 77"

# --- M: the mutation runner with stand-in suites ---------------------------------
mkdir -p "$T/fc/review" "$T/fc/tests/lib" "$T/fc/tests/fixtures"
cp "$FC/review/review_record.py" "$T/fc/review/"
cp "$RUNNER_SRC" "$T/fc/tests/test_review_record_gate_authority_mutations.sh"
cp "$HERE/lib/review_record_genuine.sh" "$T/fc/tests/lib/"
cp -r "$HERE/fixtures/review_record" "$HERE/fixtures/review_record_finding_layer" "$T/fc/tests/fixtures/"
WANT=$(sha256sum "$FC/review/review_record.py" | cut -d' ' -f1)
SUITES=$(sed -n 's/^SUITES="\(.*\)"$/\1/p' "$RUNNER_SRC")
[ -n "$SUITES" ] || { echo "setup: cannot read SUITES from the runner" >&2; exit 2; }
SKIPPER=$(echo "$SUITES" | awk '{print $2}')
for s in $SUITES; do
  cat > "$T/fc/tests/$s" <<EOF
#!/bin/bash
# stand-in for $s (RUNNER_FAKE: skip | constant | red-control | unset)
h=\$(cd "\$(dirname "\$0")/.." && pwd)
mode=\${RUNNER_FAKE:-}
same=0; [ "\$(sha256sum "\$h/review/review_record.py" | cut -d' ' -f1)" = "$WANT" ] && same=1
if [ "$s" = "$SKIPPER" ] && { [ "\$mode" = skip ] || [ "\$mode" = constant ]; }; then
  echo "PASS: stand-in"; echo "SKIP: FAKE-LEG -- stand-in"; echo "SKIP reason=proof_legs_skipped"; exit 77
fi
[ "\$mode" = constant ] && { echo "PASS: stand-in"; exit 0; }
[ "\$mode" = red-control ] && [ "$s" = "$SKIPPER" ] && { echo "FAIL: stand-in"; exit 1; }
[ "\$same" = 1 ] && { echo "PASS: stand-in"; exit 0; }
exit 1
EOF
done
RN="$T/fc/tests/test_review_record_gate_authority_mutations.sh"
IDS=$(sed -n '/^R7-M1\t/,/^EOF$/p' "$RUNNER_SRC" | grep -v '^EOF$' | cut -f1 | head -2 | tr '\n' ' ')
NMUT=$(sed -n '/^R7-M1\t/,/^EOF$/p' "$RUNNER_SRC" | grep -vc '^EOF$')
[ -n "$IDS" ] && [ "$NMUT" -gt 0 ] || { echo "setup: cannot read the runner's mutation ids" >&2; exit 2; }

m1=$(RUNNER_FAKE=skip TMPDIR="$T/tmp" bash "$RN" 2>&1); m1rc=$?
nk=$(printf '%s\n' "$m1" | grep -c '^ok .* KILLED by ')
if [ "$m1rc" = 77 ] && [ "$nk" = "$NMUT" ] && printf '%s\n' "$m1" | grep -q "^SKIP control: $SKIPPER skipped proof legs on this host: FAKE-LEG" \
   && printf '%s\n' "$m1" | grep -q 'all mutations KILLED, but the control skipped proof legs in:' \
   && [ "$(printf '%s\n' "$m1" | tail -1)" = "SKIP reason=control_proof_legs_skipped" ]; then
  ok "M1: a control suite that exits 77 is accepted and named; all $NMUT mutations KILLED; the runner exits 77 (SKIP, not PASS)"
else
  bad "M1: rc=$m1rc (want 77), killed $nk of $NMUT: $(printf '%s\n' "$m1" | grep -E 'NOT ok|SKIP|==' | head -4 | tr '\n' '|')"
fi
# shellcheck disable=SC2086 # IDS is a deliberately word-split id list
m2=$(RUNNER_FAKE=constant TMPDIR="$T/tmp" bash "$RN" $IDS 2>&1); m2rc=$?
if [ "$m2rc" = 1 ] && [ "$(printf '%s\n' "$m2" | grep -c 'SURVIVED every suite')" = 2 ] && ! printf '%s\n' "$m2" | grep -q 'KILLED by'; then
  ok "M2: a suite that exits 77 on the control AND on the mutant is not a kill (both mutations SURVIVED, exit 1)"
else
  bad "M2: rc=$m2rc (want 1): $(printf '%s\n' "$m2" | grep -E 'ok|==' | head -4 | tr '\n' '|')"
fi
# shellcheck disable=SC2086
m3=$(RUNNER_FAKE=red-control TMPDIR="$T/tmp" bash "$RN" $IDS 2>&1); m3rc=$?
if [ "$m3rc" = 1 ] && printf '%s\n' "$m3" | grep -q "control mirror is RED at $SKIPPER (rc 1)"; then
  ok "M3: a control suite that exits 1 is RED, exit 1"
else bad "M3: rc=$m3rc: $(printf '%s\n' "$m3" | head -3 | tr '\n' '|')"; fi
# shellcheck disable=SC2086
m4=$(TMPDIR="$T/tmp" bash "$RN" $IDS 2>&1); m4rc=$?
if [ "$m4rc" = 0 ] && printf '%s\n' "$m4" | grep -q '^ok control mirror GREEN across' \
   && [ "$(printf '%s\n' "$m4" | grep -c 'KILLED by')" = 2 ] && printf '%s\n' "$m4" | grep -q '== all mutations KILLED =='; then
  ok "M4: every control suite 0 and every mutant told apart -> exit 0 (PASS)"
else bad "M4: rc=$m4rc: $(printf '%s\n' "$m4" | grep -E 'ok|==' | head -4 | tr '\n' '|')"; fi

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
