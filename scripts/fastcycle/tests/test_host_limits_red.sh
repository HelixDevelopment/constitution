#!/bin/bash
# T144 RED test (SpecKit-004 "fast-dev-cycles", User Story 6, plan task T-F04,
# contract host-resource-attribution.md HR-005/HR-006) for
# `host/host_report.py limits` and `limits-diff`.
#
# Per tasks.md T144's own line:
#   golden-bad: a speed-up configured above the thread cap is refused by the check
#     (i.e. the probe deliberately requests more than the real thread
#     headroom, and the check reports `enforced: true` -- the over-cap
#     request WAS refused/clamped, never silently honoured).
#   control needle: a synthetic load throttling a test scope is detected via
#     §11.4.225 cpu.stat deltas with a quiet-phase control.
#
# `limits` reuses the EXISTING, already-landed lib/host_guard.sh for the
# §12.6/§12.12/§11.4.58 enforcement probes (never a config read -- HR-005),
# inheriting its FC_GUARD_* injectable-override convention through the
# child process's environment, so this test can pin a fixed, deterministic
# host state exactly as host_guard.sh's own test suite already does.
#
# `limits-diff` weakened-limit detection is exercised against two
# hand-constructed limits.json documents (a derived oracle, §11.4.245 --
# never produced by calling `limits` itself for this half of the test).

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

# --- ample host state (mirrors host_guard.sh's own test suite AMPLE fixture) ---
AMPLE="FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_ACTIVE_AGENTS=1 FC_GUARD_NPROC=8"

OUT="$WORK/limits_before.json"
# shellcheck disable=SC2086
env $AMPLE python3 "$TOOL" limits --speedup t144-probe --phase before --out "$OUT" \
  >"$WORK/o1.log" 2>"$WORK/e1.log"
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$OUT" ]; then
  ok "limits (ample host state): exit 0, output written"
else
  bad "limits (ample host state): expected exit 0 + output, got rc=$rc stderr=$(cat "$WORK/e1.log")"
fi

if [ -f "$OUT" ]; then
  python3 - "$OUT" <<'PYEOF'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
fail = 0
def bad(m):
    global fail
    print("FAIL:", m); fail = 1
def ok(m):
    print("PASS:", m)

limits = doc.get("limits")
if not isinstance(limits, dict):
    bad("limits doc has no top-level 'limits' object")
    print("SUMMARY pass=0 fail=1"); sys.exit(1)

for name in ("memory_ceiling", "thread_headroom", "agent_cap", "job_cap"):
    row = limits.get(name)
    if not isinstance(row, dict) or "enforced" not in row:
        bad("limits.%s missing or has no 'enforced' field" % name)
        continue
    if row["enforced"] is not True:
        bad("limits.%s expected enforced: true against a huge synthetic over-budget probe, got %r"
            % (name, row.get("enforced")))
    else:
        ok("limits.%s: enforced: true (over-cap request genuinely refused/clamped)" % name)
    rn, gn = row.get("requested_n"), row.get("returned_n")
    if isinstance(rn, int) and isinstance(gn, int) and gn < rn:
        ok("limits.%s: returned_n (%r) < requested_n (%r) -- real clamp proof" % (name, gn, rn))
    else:
        bad("limits.%s: expected returned_n < requested_n, got requested_n=%r returned_n=%r"
            % (name, rn, gn))

sys.exit(1 if fail else 0)
PYEOF
  [ $? -eq 0 ] && ok "limits doc: all three enforcement checks proven with a real clamp" \
                || bad "limits doc: enforcement-check shape/values"
fi

if [ "$rc" -eq 0 ]; then
  echo "SUMMARY (limits phase 1) pass=$PASS fail=$FAIL so far"
fi

# --- limits-diff: identical before/after -> exit 0 ---
OUT2="$WORK/limits_after_same.json"
# shellcheck disable=SC2086
env $AMPLE python3 "$TOOL" limits --speedup t144-probe --phase after --out "$OUT2" \
  >"$WORK/o2.log" 2>"$WORK/e2.log"
python3 "$TOOL" limits-diff --before "$OUT" --after "$OUT2" >"$WORK/diff1.log" 2>&1
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
