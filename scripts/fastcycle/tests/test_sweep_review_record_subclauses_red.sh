#!/bin/bash
# fastcycle-timeout-s: 1200
# test_sweep_review_record_subclauses_red.sh
#
# CON-033 round 2, review I5: the sweep generator (sweep_review_record_subclauses.sh)
# must never report success when it did not sweep, and must never write a
# tracked file unless told to. Before round 2, an interrupted sweep (its trap
# deleted the work dir and did not exit) printed "every mutant KILLED" with
# exit 0, an empty sub-clause list did the same, and the default run rewrote
# the tracked ledger in place through a ".tmp" sibling in fixtures/.
#
# This test drives the REAL sweep script in a scratch copy of the tests tree
# whose nine suites are replaced by a small stand-in (this is a test of the
# sweep's OWN control logic, section 11.4.289(C)(2), so a stand-in suite is
# allowed here; the real suites are exercised by the real sweep run). The
# stand-in prints one PASS line and exits 0 when it sees the unmutated
# review_record.py (by sha256), and exits 1 otherwise, so every real mutant
# the analyzer builds is KILLED and the control is GREEN.
#
#   S1 an interrupt (TERM to the sweep's process group after the first mutant
#      result) exits 143, never prints the success line, writes no ledger and
#      leaves no .tmp next to the requested --out path;
#   S2 an ID list that matches no sub-clause is a failure, not a clean sweep;
#   S3 a full default run (no --out) exits 0 and writes its ledger to a temp
#      file, never to the tracked fixture (whose sha256 stays the same);
#   C  control: the stand-in suite really distinguishes the control from a
#      mutant (otherwise S3's "every mutant KILLED" would prove nothing).
#
# Exit 0 = all checks passed; 1 = a check failed; 2 = setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
SWEEP_SRC="$HERE/sweep_review_record_subclauses.sh"
PASS=0; FAIL=0
ok()  { echo "ok $*"; PASS=$((PASS + 1)); }
bad() { echo "NOT ok $*"; FAIL=$((FAIL + 1)); }

for f in "$SWEEP_SRC" "$FC/review/review_record.py" "$HERE/lib/review_record_guard_analyzer.py" \
         "$HERE/lib/review_record_genuine.sh"; do
  [ -f "$f" ] || { echo "setup: missing $f" >&2; exit 2; }
done
T=$(mktemp -d) || { echo "setup: mktemp" >&2; exit 2; }
trap 'chmod -R u+rwx "${T:?}" 2>/dev/null; rm -rf -- "${T:?}"' EXIT
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"

# --- the scratch tree: <T>/fc/{review,tests} -----------------------------------
mkdir -p "$T/fc/review" "$T/fc/tests/lib" "$T/fc/tests/fixtures"
cp "$FC/review/review_record.py" "$T/fc/review/"
cp "$SWEEP_SRC" "$T/fc/tests/sweep_review_record_subclauses.sh"
cp "$HERE/lib/review_record_guard_analyzer.py" "$HERE/lib/review_record_genuine.sh" "$T/fc/tests/lib/"
cp -r "$HERE/fixtures/review_record" "$HERE/fixtures/review_record_finding_layer" "$T/fc/tests/fixtures/"
[ -f "$HERE/fixtures/review_record_equivalent_subclauses.tsv" ] && \
  cp "$HERE/fixtures/review_record_equivalent_subclauses.tsv" "$T/fc/tests/fixtures/"
printf '# stand-in tracked ledger\n' > "$T/fc/tests/fixtures/review_record_subclause_kills.tsv"
TRACKED_SHA=$(sha256sum "$T/fc/tests/fixtures/review_record_subclause_kills.tsv" | cut -d' ' -f1)
WANT=$(sha256sum "$FC/review/review_record.py" | cut -d' ' -f1)
SUITES=$(sed -n 's/^SUITES="\(.*\)"$/\1/p' "$SWEEP_SRC")
[ -n "$SUITES" ] || { echo "setup: cannot read SUITES from the sweep" >&2; exit 2; }
for s in $SUITES; do
  cat > "$T/fc/tests/$s" <<EOF
#!/bin/bash
h=\$(cd "\$(dirname "\$0")/.." && pwd)
[ -n "\${SWEEP_FAKE_SLEEP:-}" ] && sleep "\$SWEEP_FAKE_SLEEP"
if [ "\$(sha256sum "\$h/review/review_record.py" | cut -d' ' -f1)" = "$WANT" ]; then
  echo "PASS: stand-in $s sees the unmutated tool"; exit 0
fi
exit 1
EOF
done
SW="$T/fc/tests/sweep_review_record_subclauses.sh"

# --- C: the stand-in tells a mutant from the control ----------------------------
first=$(cd "$T/fc/tests" && python3 lib/review_record_guard_analyzer.py list ../review/review_record.py 2>/dev/null | head -1 | cut -f1)
if [ -z "$first" ]; then
  bad "C: the analyzer lists no sub-clause (instrument blind)"
else
  mkdir -p "$T/cm/review" "$T/cm/tests"
  cp "$T/fc/tests/"test_*.sh "$T/cm/tests/"
  python3 "$T/fc/tests/lib/review_record_guard_analyzer.py" mutate "$T/fc/review/review_record.py" "$first" "$T/cm/review/review_record.py" 2>/dev/null
  s1=$(echo "$SUITES" | awk '{print $1}')
  bash "$T/fc/tests/$s1" >/dev/null 2>&1; crc=$?
  bash "$T/cm/tests/$s1" >/dev/null 2>&1; mrc=$?
  if [ "$crc" = 0 ] && [ "$mrc" = 1 ]; then ok "C: the stand-in suite passes the control (rc=0) and fails mutant $first (rc=1)"
  else bad "C: the stand-in suite does not discriminate (control rc=$crc, mutant $first rc=$mrc)"; fi
fi

# --- S1: interrupt --------------------------------------------------------------
OUT1="$T/out1/ledger.tsv"; mkdir -p "$T/out1"
s1out=$(SWEEP_FAKE_SLEEP=0.3 python3 - "$SW" "$OUT1" <<'PY'
import os, signal, subprocess, sys, time
sw, out = sys.argv[1], sys.argv[2]
p = subprocess.Popen(["bash", sw, "-j", "1", "--out", out], stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, start_new_session=True)
buf = b""
deadline = time.time() + 600
sent = False
while True:
    line = p.stdout.readline()
    if not line:
        break
    buf += line
    if not sent and line.startswith(b"  done "):
        if p.pid > 1:
            os.killpg(p.pid, signal.SIGTERM)
        sent = True
    if time.time() > deadline:
        if p.pid > 1:
            os.killpg(p.pid, signal.SIGKILL)
        break
rc = p.wait()
sys.stdout.write("RC=%d SENT=%s\n" % (rc, sent))
sys.stdout.write(buf.decode("utf-8", "replace"))
PY
)
s1rc=$(printf '%s\n' "$s1out" | sed -n '1s/^RC=\(-\{0,1\}[0-9]*\) .*/\1/p')
if printf '%s\n' "$s1out" | head -1 | grep -q 'SENT=True'; then
  [ "$s1rc" = 143 ] && ok "S1: an interrupted sweep exits 143" || bad "S1: an interrupted sweep exits $s1rc (want 143)"
  if printf '%s\n' "$s1out" | grep -q 'every mutant KILLED'; then bad "S1: an interrupted sweep printed the success line"
  else ok "S1: an interrupted sweep does not print the success line"; fi
  [ ! -e "$OUT1" ] && ok "S1: no ledger was written" || bad "S1: a ledger was written by an interrupted sweep"
  _tmps=$(find "$T/out1" -maxdepth 1 -name '*.tmp' | wc -l)
  if [ "$_tmps" -ne 0 ]; then bad "S1: a .tmp file was left next to the --out path"
  else ok "S1: no .tmp file next to the --out path"; fi
else
  bad "S1: the sweep produced no mutant result to interrupt after (output: $(printf '%s' "$s1out" | tail -3 | tr '\n' '|'))"
fi

# --- S2: an ID list matching nothing --------------------------------------------
s2out=$(bash "$SW" -j 1 NO_SUCH_SUBCLAUSE_ID 2>&1); s2rc=$?
if [ "$s2rc" != 0 ] && ! printf '%s\n' "$s2out" | grep -q 'every mutant KILLED'; then
  ok "S2: an ID list matching no sub-clause fails (rc=$s2rc) and does not claim a clean sweep"
else
  bad "S2: an empty sweep was reported clean (rc=$s2rc: $(printf '%s' "$s2out" | tail -2 | tr '\n' '|'))"
fi

# --- S3: a full default run -----------------------------------------------------
s3out=$(bash "$SW" -j 2 2>&1); s3rc=$?
led=$(printf '%s\n' "$s3out" | sed -n 's/^ledger written: \(.*\) ([0-9]* rows)$/\1/p')
[ "$s3rc" = 0 ] && ok "S3: a full default run exits 0" || bad "S3: a full default run exits $s3rc ($(printf '%s' "$s3out" | grep 'NOT ok' | head -3 | tr '\n' '|'))"
printf '%s\n' "$s3out" | grep -q 'every mutant KILLED' && ok "S3: it reports every mutant KILLED" || bad "S3: no success line"
if [ -n "$led" ] && [ -s "$led" ] && case "$led" in "$T/fc/tests/fixtures/"*) false ;; *) true ;; esac; then
  ok "S3: the ledger went to a temp file ($led), not into fixtures/"
else
  bad "S3: the default ledger path is '$led' (want a non-empty temp file outside fixtures/)"
fi
[ "$(sha256sum "$T/fc/tests/fixtures/review_record_subclause_kills.tsv" | cut -d' ' -f1)" = "$TRACKED_SHA" ] \
  && ok "S3: the tracked ledger is unchanged" || bad "S3: the tracked ledger was rewritten by a default run"
nrows=$(grep -vc '^#' "$led" 2>/dev/null || echo 0)
nsub=$(cd "$T/fc/tests" && python3 lib/review_record_guard_analyzer.py list ../review/review_record.py 2>/dev/null | grep -c .)
[ "$nrows" -gt 0 ] && [ "$nrows" = "$nsub" ] && ok "S3: the ledger has one row per sub-clause ($nrows)" \
  || bad "S3: ledger rows $nrows != sub-clauses $nsub"

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
