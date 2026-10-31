#!/bin/bash
# Purpose : Regression for the canon self-scan item 1 (docs/design/canon_self_scan_triage_2026_10_31.md):
#           closure/reopen_rate.py is_retroactive_registration() and cycle/select_sample.py
#           detect_retroactive_registration() wrapped a timestamp subtraction in `except Exception:
#           return False`, so an item whose Opened/closure created_at was missing or malformed was
#           silently treated as an ordinary closure: the reopen rate moved (measured RED: Bug closed 3
#           rate 0.333333 instead of 2 / 0.0 with the retroactive item excluded) with no trace, exit 0.
#           Contract after the fix (hand-derived, §11.4.245 SPECIFIED oracle):
#             - reopen_rate.py still COUNTS such an item (retroactivity cannot be proven) but LISTS it
#               under `unparseable_timestamps` (per type and overall) and warns on stderr, exit 0.
#             - select_sample.classify_exclusions() EXCLUDES it with an explicit "unparseable-timestamp"
#               reason (a duration sample cannot rest on a corrupt timestamp), never silently keeps it.
#             - a well-formed export is byte-identical in behaviour (no new key).
# Test types: unit (tri-state), integration (classify_exclusions), e2e (real CLI), security/chaos
#           (hostile value shapes), determinism x3, idempotency, paired §1.1 mutation (bare-except revert).
# Usage   : bash test_unparseable_timestamp_regression.sh   exit 0 = all hold.
set -u
export CONSTITUTION_JEV_HOOK=off
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
fail=0
chk() { if [ "$2" = 1 ]; then echo "ok $1"; else echo "NOT ok $1"; fail=1; fi; }
FIX="$FC/tests/fixtures/reopen_rate/negative_control_retroactive/tracker_export.json"

mkbad() { # out value-as-python-expr
  python3 - "$FIX" "$1" "$2" <<'E'
import json, sys
src, out, val = sys.argv[1], sys.argv[2], eval(sys.argv[3])
d = json.load(open(src))
for r in d["item_history"]:
    if r["atm_id"] == "NB-001" and r["event_type"] == "Fixed":
        if val is KeyError:
            del r["created_at"]
        else:
            r["created_at"] = val
json.dump(d, open(out, "w"))
E
}

run_rr() { # tool-dir export out
  python3 "$1/closure/reopen_rate.py" --as-of 2026-07-31 --window-days 30 --tracker-export "$2" --out "$3"
}
jget() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))" "$1" "$2"; }

# --- e2e: malformed closure timestamp -> counted AND listed AND warned
mkbad "$TMP/bad.json" "'not-a-timestamp'"
run_rr "$FC" "$TMP/bad.json" "$TMP/o1.json" >"$TMP/o1.out" 2>"$TMP/o1.err"; rc=$?
chk "e2e: exit 0 (rc=$rc)" "$([ $rc = 0 ] && echo 1)"
chk "e2e: overall lists NB-001 as unparseable" "$([ "$(jget "$TMP/o1.json" "d['overall'].get('unparseable_timestamps')")" = "['NB-001']" ] && echo 1)"
chk "e2e: Bug block lists NB-001" "$([ "$(jget "$TMP/o1.json" "d['by_type']['Bug'].get('unparseable_timestamps')")" = "['NB-001']" ] && echo 1)"
chk "e2e: item still counted (Bug closed 3, not silently 2)" "$([ "$(jget "$TMP/o1.json" "d['by_type']['Bug']['closed']")" = 3 ] && echo 1)"
chk "e2e: stderr warns and names the item" "$(grep -q 'unparseable' "$TMP/o1.err" && grep -q NB-001 "$TMP/o1.err" && echo 1)"

# --- control: well-formed export unchanged (negative control, no new key)
run_rr "$FC" "$FIX" "$TMP/ok.json" >/dev/null 2>"$TMP/ok.err"
chk "control: well-formed export has no unparseable key" "$([ "$(jget "$TMP/ok.json" "'unparseable_timestamps' in d['overall'] or 'unparseable_timestamps' in d['by_type']['Bug']")" = False ] && echo 1)"
chk "control: retroactive NB-001 still excluded" "$([ "$(jget "$TMP/ok.json" "[e['item_id'] for e in d['overall']['excluded_retroactive']]")" = "['NB-001']" ] && echo 1)"
chk "control: no warning on stderr" "$([ ! -s "$TMP/ok.err" ] && echo 1)"

# --- security/chaos: hostile value shapes never crash and are never silent
# (a list/dict value crashes loudly earlier, in dedup_history -- separate pre-existing finding, not silent)
for v in "None" "12345" "1.5" "True" "''" "'2026-13-45T99:99:99Z'" "KeyError"; do
  mkbad "$TMP/h.json" "$v"
  run_rr "$FC" "$TMP/h.json" "$TMP/h.out.json" >/dev/null 2>"$TMP/h.err"; rc=$?
  chk "chaos [$v]: exit 0 and listed (rc=$rc)" "$([ $rc = 0 ] && [ "$(jget "$TMP/h.out.json" "d['overall'].get('unparseable_timestamps')")" = "['NB-001']" ] && ! grep -q Traceback "$TMP/h.err" && echo 1)"
done

# --- determinism x3 + idempotency
h1=$(jget "$TMP/o1.json" "d['body_hash']")
same=1
for i in 1 2 3; do
  run_rr "$FC" "$TMP/bad.json" "$TMP/o_$i.json" >/dev/null 2>&1
  [ "$(jget "$TMP/o_$i.json" "d['body_hash']")" = "$h1" ] || same=0
done
chk "determinism x3: identical body_hash" "$same"
run_rr "$FC" "$TMP/bad.json" "$TMP/o1.json" >/dev/null 2>&1
chk "idempotency: re-run over its own output path, same hash" "$([ "$(jget "$TMP/o1.json" "d['body_hash']")" = "$h1" ] && echo 1)"

# --- integration: select_sample classify_exclusions + unit tri-state
py_out=$(python3 - "$FC" <<'E'
import sys
fc = sys.argv[1]
sys.path.insert(0, fc + "/cycle"); sys.path.insert(0, fc + "/closure")
import select_sample as ss, reopen_rate as rr
def h(c):
    return [{"event_type": "Opened", "created_at": "2026-07-05T10:00:00Z"},
            {"event_type": "Fixed", "created_at": c}]
res = []
for name, c, want in (("retro", "2026-07-05T10:00:30Z", "retroactive"), ("normal", "2026-07-06T10:00:00Z", "normal"),
                      ("bad", "garbage", "unparseable"), ("none", None, "unparseable"), ("int", 5, "unparseable")):
    a, b = ss.retroactive_state(h(c)), rr.retroactive_state(h(c))
    res.append("%s:%s" % (name, "ok" if a == b == want else "MISMATCH(%s,%s,want %s)" % (a, b, want)))
ex = ss.classify_exclusions({"A": h("garbage"), "B": h("2026-07-06T10:00:00Z")}, {"A", "B"}, 99)
res.append("excl:%s" % ("ok" if ex["A"] and ex["A"].startswith("unparseable-timestamp") and ex["B"] is None else "BAD %r" % ex))
res.append("bool-compat:%s" % ("ok" if (ss.detect_retroactive_registration(h("garbage")) is False and rr.is_retroactive_registration(h("2026-07-05T10:00:30Z")) is True) else "BAD"))
print(" ".join(res))
E
)
echo "$py_out"
chk "unit+integration: tri-state parity, exclusion reason, bool wrappers" "$(case "$py_out" in *MISMATCH*|*BAD*) ;; *ok*) echo 1;; esac)"

# --- paired §1.1 mutation: revert the fix to the bare except in a sandbox copy -> the e2e check MUST fail
MUT="$TMP/mut"; mkdir -p "$MUT"; cp -r "$FC/closure" "$FC/cycle" "$FC/lib" "$MUT/" 2>/dev/null
for f in "$FC"/*.py; do [ -e "$f" ] && cp "$f" "$MUT/"; done
python3 - "$MUT/closure/reopen_rate.py" <<'E'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'except (KeyError, ValueError, TypeError, AttributeError):\n        return "unparseable"'
assert a in s
open(p, "w").write(s.replace(a, 'except Exception:\n        return "normal"'))
E
run_rr "$MUT" "$TMP/bad.json" "$TMP/mut.json" >/dev/null 2>&1
mutlist=$(jget "$TMP/mut.json" "d['overall'].get('unparseable_timestamps')" 2>/dev/null)
chk "mutation: bare-except revert is DETECTED (listing disappears -> check fails)" "$([ "$mutlist" != "['NB-001']" ] && echo 1)"

[ $fail = 0 ] && echo "ALL OK" || echo "FAILED"
exit $fail
