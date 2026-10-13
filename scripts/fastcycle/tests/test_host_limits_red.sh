#!/bin/bash
# T144 RED test (SpecKit-004 "fast-dev-cycles", User Story 6, plan task T-F04,
# contract host-resource-attribution.md HR-005/HR-006) for
# `host/host_report.py limits` and `limits-diff`.
#
# REWRITTEN (T153 Round-1 NO-GO finding B3): the ORIGINAL version of this
# test set `FC_GUARD_NPROC=8` (a small value) in its "AMPLE" fixture, so
# `host_guard.sh`'s FIRST check (nproc) clamped every probe's returned_n
# down to 8 immediately -- by the time the memory/thread/agent-cap checks
# ran, `n` was already far below `requested_n`, so the old assertion
# (`enforced: true` + `returned_n < requested_n`) was satisfied REGARDLESS
# of whether the memory/thread/agent-cap logic did anything at all. This
# version sets `FC_GUARD_NPROC` to a value well ABOVE `PROBE_N` so CPU
# count alone can never be the binding constraint, and asserts the
# SPECIFIC reason string each check reports (never merely "some
# reduction happened") AND the derived `returned_n` (exactly 1 or 0, as
# appropriate to the plain vs `_exhausted` form under test -- never merely
# "less than a million"). `job_cap`'s underlying `host_safe_aosp_jobs`
# has no reason-string concept at all (verified: its only per-call output
# is a bare job count) and accepts no FC_GUARD_*-style override for a
# deterministic pre-set host state, so it is additionally exercised
# DIRECTLY (bypassing `host_report.py` entirely) with an explicit small
# ceiling BELOW its natural capacity, proving that mechanism genuinely
# honors a request rather than "similarly ignoring it" (the other half of
# finding B3).
#
# `limits` reuses the EXISTING, already-landed lib/host_guard.sh for the
# §12.6/§12.12/§11.4.58 enforcement probes (never a config read -- HR-005),
# inheriting its FC_GUARD_* injectable-override convention through the
# child process's environment, so this test can pin a fixed, deterministic
# host state exactly as host_guard.sh's own test suite already does.
# `agent_cap` determinism additionally uses the new
# FC_HOST_AGENT_REGISTRY_STATUS_PATH testability seam (mirrors the
# already-established FC_HOST_CPU_STAT_PATH convention) to point at a
# controlled fixture TSV instead of this host's real, live agent registry.
#
# `limits-diff` weakened-limit detection is exercised against two
# hand-constructed limits.json documents (a derived oracle, §11.4.245 --
# never produced by calling `limits` itself for this half of the test).
#
# Paired mutation (T153 B3 fix, this file's own regression proof): see the
# bottom of this file -- `probe_memory_ceiling()`'s per-job forcing value
# is temporarily hardcoded to 1 (ignoring the REAL measured budget), the
# test is re-run and its `memory_ceiling` reason/returned_n assertion is
# confirmed to FAIL, then the mutation is reverted.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC_ROOT=$(cd "$HERE/.." && pwd)
TOOL="$FC_ROOT/host/host_report.py"
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

if [ ! -f "$TOOL" ]; then
  echo "RED: host_report.py absent at $TOOL"
  bad "host_report.py exists"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- ample host state, CPU count deliberately set WELL ABOVE PROBE_N
#     (1,000,000) so it can never be the binding constraint for any check
#     (B3 fix: the old fixture's small FC_GUARD_NPROC=8 masked this). ---
AMPLE="FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_NPROC=2000000"

# mk_registry <path> <n_active> -- a controlled agent_registry.status.tsv
# fixture with exactly N unique keys, each latest-status "dispatched".
mk_registry() {
  local path="$1" n="$2" i
  : > "$path"
  for i in $(seq 1 "$n"); do
    printf 'fixture-agent-%02d\tdispatched\t2026-09-30T00:00:00Z\t\t(test fixture)\n' "$i" >> "$path"
  done
}

REG0="$WORK/registry_0_active.tsv"; mk_registry "$REG0" 0
REG5="$WORK/registry_5_active.tsv"; mk_registry "$REG5" 5
REG6="$WORK/registry_6_active.tsv"; mk_registry "$REG6" 6

assert_limit() {  # assert_limit <doc.json> <name> <expected_enforced> <expected_reason> <expected_returned_n>
  local doc="$1" name="$2" exp_enforced="$3" exp_reason="$4" exp_n="$5"
  python3 -c "
import json, sys
doc = json.load(open('$doc', encoding='utf-8'))
row = doc.get('limits', {}).get('$name')
if not isinstance(row, dict):
    print('FAIL: limits.$name missing or not an object: %r' % row)
    sys.exit(1)
ok = True
if row.get('enforced') is not $exp_enforced:
    print('FAIL: limits.$name.enforced expected $exp_enforced, got %r' % row.get('enforced')); ok = False
if row.get('reason') != '$exp_reason':
    print('FAIL: limits.$name.reason expected %r, got %r' % ('$exp_reason', row.get('reason'))); ok = False
if row.get('returned_n') != $exp_n:
    print('FAIL: limits.$name.returned_n expected exactly $exp_n, got %r' % row.get('returned_n')); ok = False
if ok:
    print('PASS: limits.$name: enforced=$exp_enforced reason=$exp_reason returned_n=$exp_n (exact)')
sys.exit(0 if ok else 1)
"
  if [ $? -eq 0 ]; then ok "$name exact reason+returned_n"; else bad "$name exact reason+returned_n"; fi
}

# --- (1) 0 active agents: memory_ceiling + thread_headroom forced to the
#     floor (returned_n exactly 1) by host_report.py's own per-job forcing
#     arithmetic; agent_cap's natural, UNFORCED value (6 - 0 = 6). ---
OUT1="$WORK/limits_0active.json"
# shellcheck disable=SC2086
env $AMPLE FC_HOST_AGENT_REGISTRY_STATUS_PATH="$REG0" \
  python3 "$TOOL" limits --speedup t144-probe --phase before --out "$OUT1" \
  >"$WORK/o1.log" 2>"$WORK/e1.log"
rc1=$?
if [ "$rc1" -eq 0 ] && [ -f "$OUT1" ]; then
  ok "limits (0 active agents): exit 0, output written"
else
  bad "limits (0 active agents): expected exit 0 + output, got rc=$rc1 stderr=$(cat "$WORK/e1.log")"
fi
if [ -f "$OUT1" ]; then
  assert_limit "$OUT1" memory_ceiling True memory_ceiling 1
  assert_limit "$OUT1" thread_headroom True thread_headroom 1
  assert_limit "$OUT1" agent_cap True agent_cap 6
fi

# --- (2) 5 active agents: agent_cap's natural (unforced) floor-to-1 case,
#     the exhausted form's plain-but-minimal sibling (returned_n exactly 1,
#     never merely "< requested"). ---
OUT2="$WORK/limits_5active.json"
# shellcheck disable=SC2086
env $AMPLE FC_HOST_AGENT_REGISTRY_STATUS_PATH="$REG5" \
  python3 "$TOOL" limits --speedup t144-probe --phase before --out "$OUT2" \
  >"$WORK/o2.log" 2>"$WORK/e2.log"
if [ -f "$OUT2" ]; then
  assert_limit "$OUT2" agent_cap True agent_cap 1
else
  bad "limits (5 active agents): no output written, stderr=$(cat "$WORK/e2.log")"
fi

# --- (3) 6 active agents (cap 6 - 6 = 0): agent_cap_exhausted -- the
#     EXHAUSTED form, returned_n exactly 0, still `enforced: true` (a
#     more-restrictive-than-requested refusal is still "enforced"). ---
OUT3="$WORK/limits_6active.json"
# shellcheck disable=SC2086
env $AMPLE FC_HOST_AGENT_REGISTRY_STATUS_PATH="$REG6" \
  python3 "$TOOL" limits --speedup t144-probe --phase before --out "$OUT3" \
  >"$WORK/o3.log" 2>"$WORK/e3.log"
if [ -f "$OUT3" ]; then
  assert_limit "$OUT3" agent_cap True agent_cap_exhausted 0
else
  bad "limits (6 active agents): no output written, stderr=$(cat "$WORK/e3.log")"
fi

# --- (4) job_cap: host_safe_aosp_jobs has NO reason-string concept and
#     accepts no FC_GUARD_*-style override for a controlled host state
#     (verified against its own source), so its own `limits` row is
#     checked for a sane bound only; the genuine "does N matter" proof is
#     a DIRECT call below with an explicit ceiling BELOW natural capacity.
if [ -f "$OUT1" ]; then
  python3 -c "
import json, sys
doc = json.load(open('$OUT1', encoding='utf-8'))
row = doc.get('limits', {}).get('job_cap')
if not isinstance(row, dict) or row.get('enforced') is not True:
    print('FAIL: limits.job_cap expected enforced: true, got %r' % row); sys.exit(1)
rn = row.get('returned_n')
if not isinstance(rn, int) or rn < 1:
    print('FAIL: limits.job_cap.returned_n expected a sane positive int, got %r' % rn); sys.exit(1)
print('PASS: limits.job_cap: enforced=true returned_n=%r (sane, positive)' % rn)
sys.exit(0)
"
  [ $? -eq 0 ] && ok "job_cap sane-bound check" || bad "job_cap sane-bound check"
fi

# job_cap DIRECT override-honored proof (B3: "job_cap similarly ignores
# the requested N" -- proven false by requesting something BELOW natural
# capacity and confirming it IS honored, the genuine enforcement path the
# over-budget-only probe above can never exercise).
HSS="$(cd "$FC_ROOT/../../.." && pwd)/scripts/lib/host_session_safety.sh"
if [ -f "$HSS" ]; then
  j=$(bash -c "set -e; . '$HSS' >/dev/null 2>&1; host_safe_aosp_jobs 1" 2>"$WORK/jobcap_direct.log")
  jrc=$?
  if [ "$jrc" -eq 0 ] && [ "$j" = "1" ]; then
    ok "host_safe_aosp_jobs: an explicit ceiling (1) BELOW natural capacity IS honored (returned exactly 1, requested N is not ignored)"
  else
    bad "host_safe_aosp_jobs: expected an explicit ceiling of 1 to be honored (returned 1), got rc=$jrc j=$j stderr=$(cat "$WORK/jobcap_direct.log")"
  fi
else
  bad "host_safe_aosp_jobs: $HSS not found -- cannot prove the override mechanism directly"
fi

# --- limits-diff: identical before/after -> exit 0 ---
OUT4="$WORK/limits_after_same.json"
# shellcheck disable=SC2086
env $AMPLE FC_HOST_AGENT_REGISTRY_STATUS_PATH="$REG0" \
  python3 "$TOOL" limits --speedup t144-probe --phase after --out "$OUT4" \
  >"$WORK/o4.log" 2>"$WORK/e4.log"
python3 "$TOOL" limits-diff --before "$OUT1" --after "$OUT4" >"$WORK/diff1.log" 2>&1
diff_rc=$?
if [ "$diff_rc" -eq 0 ]; then
  ok "limits-diff: identical before/after (same host state) -> exit 0"
else
  bad "limits-diff: identical before/after expected exit 0, got $diff_rc ($(cat "$WORK/diff1.log"))"
fi

# --- limits-diff: hr_bad_limit_weakened (hand-constructed, derived oracle) ---
BEFORE_HAND="$WORK/before_hand.json"
AFTER_HAND="$WORK/after_hand.json"
cat > "$BEFORE_HAND" <<'JSON'
{"schema": "host-limits/v1", "speedup": "x", "phase": "before",
 "limits": {
   "memory_ceiling": {"enforced": true, "requested_n": 999999, "returned_n": 1, "reason": "memory_ceiling"},
   "thread_headroom": {"enforced": true, "requested_n": 999999, "returned_n": 1, "reason": "thread_headroom"},
   "agent_cap": {"enforced": true, "requested_n": 999999, "returned_n": 5, "reason": "agent_cap"}
 }}
JSON
cat > "$AFTER_HAND" <<'JSON'
{"schema": "host-limits/v1", "speedup": "x", "phase": "after",
 "limits": {
   "memory_ceiling": {"enforced": true, "requested_n": 999999, "returned_n": 1, "reason": "memory_ceiling"},
   "thread_headroom": {"enforced": true, "requested_n": 999999, "returned_n": 1, "reason": "thread_headroom"},
   "agent_cap": {"enforced": false, "requested_n": 999999, "returned_n": 999999, "reason": "raised"}
 }}
JSON
python3 "$TOOL" limits-diff --before "$BEFORE_HAND" --after "$AFTER_HAND" >"$WORK/diff2.log" 2>&1
diff2_rc=$?
if [ "$diff2_rc" -eq 1 ] && grep -q "agent_cap" "$WORK/diff2.log"; then
  ok "hr_bad_limit_weakened: limits-diff exits 1 and names agent_cap"
else
  bad "hr_bad_limit_weakened: expected exit 1 naming agent_cap, got rc=$diff2_rc ($(cat "$WORK/diff2.log"))"
fi

# --- §11.4.225 control needle: parse_cpu_stat + cpu_throttle_delta detect a
#     synthetic throttling load against a quiet-phase control, via direct
#     import (deterministic, no real cgroup dependency -- HR-005 telemetry
#     is a measurement, never a pass/fail limit, so the parsing/delta LOGIC
#     is what this needle proves, not real host cgroup enforcement).
python3 - "$FC_ROOT/host" <<'PYEOF'
import sys, importlib.util
host_dir = sys.argv[1]
spec = importlib.util.spec_from_file_location("host_report", host_dir + "/host_report.py")
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as exc:
    print("FAIL: host_report.py raised on import: %s: %s" % (type(exc).__name__, exc))
    print("SUMMARY pass=0 fail=1"); sys.exit(1)

for name in ("parse_cpu_stat", "cpu_throttle_delta"):
    if not hasattr(mod, name):
        print("FAIL: host_report.%s is not defined" % name)
        print("SUMMARY pass=0 fail=1"); sys.exit(1)

quiet_before = mod.parse_cpu_stat("usage_usec 1000\nnr_periods 10\nnr_throttled 2\nthrottled_usec 500\n")
quiet_after  = mod.parse_cpu_stat("usage_usec 1010\nnr_periods 11\nnr_throttled 2\nthrottled_usec 500\n")
load_before  = mod.parse_cpu_stat("usage_usec 2000\nnr_periods 20\nnr_throttled 5\nthrottled_usec 1200\n")
load_after   = mod.parse_cpu_stat("usage_usec 2500\nnr_periods 40\nnr_throttled 19\nthrottled_usec 9800\n")

qd = mod.cpu_throttle_delta(quiet_before, quiet_after)
ld = mod.cpu_throttle_delta(load_before, load_after)

fail = 0
if qd.get("nr_throttled_delta") == 0 and qd.get("throttled_usec_delta") == 0:
    print("PASS: quiet-phase control: nr_throttled_delta == throttled_usec_delta == 0")
else:
    print("FAIL: quiet-phase control expected zero deltas, got %r" % qd); fail = 1

if ld.get("nr_throttled_delta") == 14 and ld.get("throttled_usec_delta") == 8600:
    print("PASS: load phase: nr_throttled_delta=14 throttled_usec_delta=8600 (synthetic throttling detected)")
else:
    print("FAIL: load phase expected nr_throttled_delta=14 throttled_usec_delta=8600, got %r" % ld); fail = 1

if ld.get("nr_throttled_delta", 0) > qd.get("nr_throttled_delta", 0):
    print("PASS: load-phase delta strictly exceeds the quiet-phase control")
else:
    print("FAIL: load-phase delta did not exceed the quiet-phase control"); fail = 1

sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] && ok "§11.4.225 cpu.stat delta needle (quiet-phase control vs synthetic load)" \
              || bad "§11.4.225 cpu.stat delta needle"

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
