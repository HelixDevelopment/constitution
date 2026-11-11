#!/bin/bash
# Purpose : CON-161 regression guard for probe_thread_headroom() in
#           scripts/fastcycle/host/host_report.py (review fsfix6 m3, reviewer
#           mutants Y4, Y5 and Y6). The only test that runs in a canon checkout
#           (test_host_report_thread_limit_r1_regression.sh) pins the soft limit
#           READ, not the arithmetic, so these survived: Y4 (per_job = headroom
#           instead of headroom + 1), Y5 (headroom = ulim - 1 instead of
#           ulim - thr), Y6 (drop the `thr is None` guard: an unreadable thread
#           count becomes an uncaught TypeError in `host_report.py limits`).
#           test_host_limits_red.sh, which asserts returned_n, SKIPs outside a
#           consumer layout.
# Usage   : bash test_host_report_probe_thread_headroom_r2_regression.sh
#           Exit 0 when every check passes, 1 otherwise; the last line is the summary.
# Method  : the REAL host_report.py imported by path, the REAL host_guard.sh it
#           calls; FC_GUARD_ULIMIT_U / FC_GUARD_THREADS (the tool's own test
#           inputs) fix the two numbers. Cases: HEADROOM (1000,900 -> 100, 101),
#           EXHAUSTED (100,150 -> -50, 1), ZERO (1000,1000 -> 0, 1), UNLIMITED,
#           THREADS_UNREADABLE (threads "xyz" -> unmeasured, no exception),
#           ULIMIT_UNREADABLE, PS_FAILS (CON-216: FC_GUARD_THREADS unset and a
#           PATH shim `ps` that exits 3 -> unmeasured; the old pipeline
#           `ps ... | wc -l` read a failed ps as 0 threads, headroom = the whole
#           soft limit). Paired mutants on a copy of the tool (the checked
#           tree is never changed); control needle: the unmutated copy passes.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
IMPL="$HERE/../host/host_report.py"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }
TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/bin" && printf '#!/bin/sh\nexit 3\n' > "$TMP/bin/ps" && chmod +x "$TMP/bin/ps" \
  || { echo "NOT ok ps shim setup failed"; exit 1; }
[ -f "$IMPL" ] || { echo "NOT ok control needle: $IMPL not found"; exit 1; }

cat > "$TMP/drv.py" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("hr", sys.argv[1]); hr = importlib.util.module_from_spec(spec); spec.loader.exec_module(hr)
cases = [
 ("HEADROOM", "1000", "900", dict(enforced=True, reason="thread_headroom", returned_n=1, thread_headroom=100, threads_per_job_probed=101)),
 ("EXHAUSTED", "100", "150", dict(enforced=True, reason="thread_headroom_exhausted", returned_n=0, thread_headroom=-50, threads_per_job_probed=1)),
 ("ZERO", "1000", "1000", dict(enforced=True, reason="thread_headroom_exhausted", returned_n=0, thread_headroom=0, threads_per_job_probed=1)),
 ("UNLIMITED", "unlimited", "5", dict(enforced=None, reason="unlimited_ulimit")),
 ("THREADS_UNREADABLE", "1000", "xyz", dict(enforced=None, reason="unmeasured", note="ulimit_or_threads_unreadable")),
 ("ULIMIT_UNREADABLE", "abc", "5", dict(enforced=None, reason="unmeasured", note="ulimit_or_threads_unreadable")),
 # CON-216: threads NOT given, so the tool runs ps; the shim ps (first on PATH) exits 3.
 ("PS_FAILS", "1000", None, dict(enforced=None, reason="unmeasured", note="ulimit_or_threads_unreadable")),
]
shim = sys.argv[2]
base_path = os.environ.get("PATH", "")
bad = 0
for name, u, t, want in cases:
    os.environ["FC_GUARD_ULIMIT_U"] = u
    if t is None:
        os.environ.pop("FC_GUARD_THREADS", None); os.environ["PATH"] = shim + os.pathsep + base_path
    else:
        os.environ["FC_GUARD_THREADS"] = t; os.environ["PATH"] = base_path
    try:
        got = hr.probe_thread_headroom()
    except Exception as e:  # an uncaught error is a failure of the case, not of the driver
        got = {"EXC": repr(e)}
    sub = {k: got.get(k, "<absent>") for k in want}
    good = sub == want
    print(("ok " if good else "NOT ok ") + "%s got=%r want=%r" % (name, sub if "EXC" not in got else got, want))
    bad += 0 if good else 1
sys.exit(1 if bad else 0)
PY
run() { python3 -I "$TMP/drv.py" "$1" "$TMP/bin" 2>&1; }
OUT=$(run "$IMPL"); RC=$?
if [ $RC = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^ok ')" = 7 ]; then ok "unmutated tool: all 7 cases pass"
else notok "unmutated tool: $(printf '%s' "$OUT" | tr '\n' '|')"; fi

mut() { # $1 name $2 old $3 new [$4 start-def $5 end-def]  (applied inside one function only, exactly once)
  cp "$IMPL" "$TMP/m.py"
  python3 -I - "$TMP/m.py" "$2" "$3" "${4:-def probe_thread_headroom}" "${5:-def probe_agent_cap}" <<'PY' || { notok "mutant $1: edit did not apply (blind)"; return; }
import sys
p, old, new, a, b = sys.argv[1:6]
s = open(p, encoding="utf-8").read()
i = s.index(a); j = s.index(b)
body = s[i:j]
assert body.count(old) == 1, "pattern count %d" % body.count(old)
open(p, "w", encoding="utf-8").write(s[:i] + body.replace(old, new) + s[j:])
PY
  if run "$TMP/m.py" >/dev/null; then notok "mutant $1 SURVIVED"; else ok "mutant $1 killed"; fi
}
mut Y4_per_job_not_plus_1   'per_job = headroom + 1 if headroom > 0 else 1' 'per_job = headroom if headroom > 0 else 1'
mut Y5_headroom_minus_1     'headroom = ulim - thr' 'headroom = ulim - 1'
mut Y6_drop_thr_none_guard  'if ulim is None or thr is None:' 'if ulim is None:'
mut Y9_drop_unlimited       'if unlimited:' 'if False:'
mut Y10_floor_not_one       'if headroom > 0 else 1' 'if headroom > 0 else 2'
# CON-216: reviewer mutant RD (fu_a review), verbatim intent: a failed ps reads as "0" threads.
mut RD_failed_ps_reads_zero 'and out is not None else None' 'and out is not None else "0"' 'def _read_ulimit_threads' 'def _read_active_agents'

echo "=== host_report probe_thread_headroom r2: pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
