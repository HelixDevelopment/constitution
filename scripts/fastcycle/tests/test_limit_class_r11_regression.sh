#!/bin/bash
# Purpose : T140 Round 11 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/limit_class.py`
#           -- findings I1 (operational/near_cap/kind had zero type
#           validation and silently misclassified an alias), I3 (a stale
#           --out survived a handled refusal) and I4 (AR-005's "a named
#           reset means cap even with a retry-after" rule and the
#           timezone-offset preservation were never pinned by any test;
#           plus the encoded decision for the ambiguous "weekly limit +
#           retry-after + no date" signal).
#
# Every case runs the REAL tool; every rule is then deleted/weakened in a
# throwaway copy and the SAME case re-run -- the mutant must give the
# wrong answer. Negative controls prove no check is a blanket refusal.
#
# Producer != Verifier (section 11.4.240): cases derived from the round-10
# reviewer's findings text and DEC-14/AR-005's wording.
# SC2015: `ok`/`notok` always return 0 (they end in `echo`), so `A && ok || notok`
# can never run both branches.
# shellcheck disable=SC2015
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/limit_class.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

fail=0
pass=0
failx() { fail=1; }
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { failx; echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R11 regression guard (limit_class.py): control needle ==="
for p in "$IMPL" "$LIB" "$EXLIB"; do
  [ -f "$p" ] || notok "control needle: $p not found"
done
python3 -c "import zoneinfo; zoneinfo.ZoneInfo('Asia/Aqtau')" 2>/dev/null \
  || notok "control needle: tzdata for Asia/Aqtau is not available on this host (offset checks would be blind)"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, tzdata present"

build_copy() {
  mkdir -p "$1/orchestration" "$1/lib"
  cp "$IMPL" "$1/orchestration/limit_class.py"
  cp "$LIB" "$1/lib/fc_common.py"
  cp "$EXLIB" "$1/lib/fc_entry.py"
}
mutate() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:]
c = open(p, encoding="utf-8").read()
if c.count(old) != 1:
    print("anchor count=%d for %r" % (c.count(old), old))
    sys.exit(1)
open(p, "w", encoding="utf-8").write(c.replace(old, new))
PYEOF
}

# place_rc IMPL FIXTURE -> "<rc> <assignment_alias_counts json or NO_DOC>"
place_rc() {
  local o="$TMP/p.$RANDOM.json"
  python3 "$1" place --fixture "$2" --out "$o" >/dev/null 2>&1
  local rc=$?
  if [ -f "$o" ]; then
    echo "$rc $(python3 -c "import json,sys; print(json.dumps(json.load(open('$o')).get('assignment_alias_counts'), sort_keys=True))")"
  else
    echo "$rc NO_DOC"
  fi
}
# classify IMPL SIGNAL -> "<class> <resets_at>"
classify() {
  local o="$TMP/c.$RANDOM.json"
  python3 "$1" --signal "$2" --out "$o" >/dev/null 2>&1
  python3 -c "import json; d=json.load(open('$o')); print(d['class'], d['resets_at'])" 2>/dev/null || echo "NO_DOC -"
}

mkfx() {  # mkfx NAME ALIASES_JSON
  printf '{"task_id":"r11","verb":"place","live_agents":4,"aliases":%s}' "$2" > "$TMP/$1.json"
}

# ---------------------------------------------------------------------------
# I1
# ---------------------------------------------------------------------------
echo
echo "=== I1: positive control -- a well-formed roster places normally ==="
mkfx good '[{"alias":"claude1","kind":"native","operational":false,"near_cap":false},{"alias":"claude2","kind":"native","operational":true,"near_cap":false},{"alias":"deepseek","kind":"provider","operational":true,"near_cap":false}]'
R=$(place_rc "$IMPL" "$TMP/good.json")
[ "$R" = '0 {"claude2": 2, "deepseek": 2}' ] && ok "I1 golden roster -> $R" || notok "I1 golden roster: $R"

echo
echo "=== I1: wrong-typed operational / near_cap / kind are REFUSED (rc=2), never coerced ==="
mkfx op_str '[{"alias":"claude1","kind":"native","operational":"false","near_cap":false},{"alias":"claude2","kind":"native","operational":true,"near_cap":false}]'
mkfx nc_null '[{"alias":"claude1","kind":"native","operational":true,"near_cap":null},{"alias":"claude2","kind":"native","operational":true,"near_cap":false}]'
mkfx kind_list '[{"alias":"claude1","kind":["native"],"operational":true,"near_cap":false},{"alias":"claude2","kind":"native","operational":true,"near_cap":false}]'
mkfx kind_weird '[{"alias":"claude1","kind":"weird","operational":true,"near_cap":false},{"alias":"claude2","kind":"native","operational":true,"near_cap":false}]'
mkfx op_int '[{"alias":"claude1","kind":"native","operational":1,"near_cap":false},{"alias":"claude2","kind":"native","operational":true,"near_cap":false}]'
for c in op_str nc_null kind_list kind_weird op_int; do
  R=$(place_rc "$IMPL" "$TMP/$c.json")
  [ "$R" = "2 NO_DOC" ] && ok "I1 $c -> rc=2, no placement written" || notok "I1 $c: $R"
done

# ---------------------------------------------------------------------------
# I4
# ---------------------------------------------------------------------------
echo
echo "=== I4: AR-005 -- a NAMED reset means cap even WITH a retry-after ==="
SIG_RESET_AND_RA='HTTP 429 rate_limit_error on alias claude1; retry-after: 30; resets 2026-09-29 20:00 Asia/Aqtau'
R=$(classify "$IMPL" "$SIG_RESET_AND_RA")
[ "$R" = "cap 2026-09-29T20:00:00+05:00" ] && ok "I4 reset+retry-after -> $R (cap, offset preserved)" \
  || notok "I4 reset+retry-after: $R"

echo
echo "=== I4: timezone offset preserved (no retry-after case too) ==="
R=$(classify "$IMPL" 'API weekly-limit 429 on alias claude1 (resets 2026-09-29 20:00 Asia/Aqtau)')
[ "$R" = "cap 2026-09-29T20:00:00+05:00" ] && ok "I4 named reset -> $R" || notok "I4 named reset: $R"

echo
echo "=== I4 decision: weekly-limit phrase + retry-after + NO date -> cap (resets_at UNKNOWN) ==="
SIG_WEEKLY_RA='429 weekly usage limit reached for alias claude1; retry-after: 3600'
R=$(classify "$IMPL" "$SIG_WEEKLY_RA")
[ "$R" = "cap UNKNOWN" ] && ok "I4 weekly phrase + retry-after, no date -> $R" || notok "I4 weekly+retry-after: $R"

echo
echo "=== I4 negative control: a plain short throttle stays rate-limited ==="
SIG_PLAIN_RA='HTTP 429 rate_limit_error; retry-after: 12 (seconds)'
R=$(classify "$IMPL" "$SIG_PLAIN_RA")
[ "$R" = "rate-limited UNKNOWN" ] && ok "I4 plain 429 + retry-after -> $R" || notok "I4 plain throttle: $R"

# ---------------------------------------------------------------------------
# I3
# ---------------------------------------------------------------------------
echo
echo "=== I3: stale --out removed on a handled place refusal ==="
printf '{"refused":false,"assignment_alias_counts":{"STALE":9}}' > "$TMP/stale.json"
python3 "$IMPL" place --fixture "$TMP/op_str.json" --out "$TMP/stale.json" >/dev/null 2>&1
RC=$?
if [ "$RC" = 2 ] && ! grep -q STALE "$TMP/stale.json" 2>/dev/null; then
  ok "I3 place refusing a malformed fixture (rc=2): the previous placement verdict is gone"
else
  notok "I3 place refusal: rc=$RC stale_left=$(grep -c STALE "$TMP/stale.json" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# guard viability
# ---------------------------------------------------------------------------
echo
echo "=== guard viability (paired mutations) ==="
mutp() {  # mutp NAME OLD NEW FIXTURE WANT_MUTANT_PREFIX
  local d="$TMP/mut_$1"
  build_copy "$d"
  if ! mutate "$d/orchestration/limit_class.py" "$2" "$3" >"$d.log" 2>&1; then
    notok "mutation $1: anchor not found ($(cat "$d.log"))"; return
  fi
  local real mutant
  real=$(place_rc "$IMPL" "$4")
  mutant=$(place_rc "$d/orchestration/limit_class.py" "$4")
  if [ "$real" = "2 NO_DOC" ] && [[ "$mutant" == "$5"* ]]; then
    ok "mutation $1: caught -- real '$real' vs mutant '$mutant'"
  else
    notok "mutation $1: real='$real' mutant='$mutant' (want mutant $5...)"
  fi
}
mutc() {  # mutc NAME OLD NEW SIGNAL WANT_REAL WANT_MUTANT
  local d="$TMP/mut_$1"
  build_copy "$d"
  if ! mutate "$d/orchestration/limit_class.py" "$2" "$3" >"$d.log" 2>&1; then
    notok "mutation $1: anchor not found ($(cat "$d.log"))"; return
  fi
  local real mutant
  real=$(classify "$IMPL" "$4")
  mutant=$(classify "$d/orchestration/limit_class.py" "$4")
  if [ "$real" = "$5" ] && [ "$mutant" = "$6" ]; then
    ok "mutation $1: caught -- real '$real' vs mutant '$mutant'"
  else
    notok "mutation $1: real='$real' (want $5) mutant='$mutant' (want $6)"
  fi
}
mutp I1_bool_fields '                if bool_field in entry and not isinstance(entry[bool_field], bool):' \
    '                if False:' "$TMP/op_str.json" "0 "
mutp I1_bool_fields_nearcap '                if bool_field in entry and not isinstance(entry[bool_field], bool):' \
    '                if False:' "$TMP/nc_null.json" "0 "
mutp I1_kind '                if not isinstance(kind_val, str) or kind_val not in KNOWN_ALIAS_KINDS:' \
    '                if False:' "$TMP/kind_list.json" "0 "
mutc I4_reset_means_cap '        if (not has_retry_after) or reset_named or periodic_cap_named:' \
    '        if (not has_retry_after) or periodic_cap_named:' "$SIG_RESET_AND_RA" \
    "cap 2026-09-29T20:00:00+05:00" "rate-limited UNKNOWN"
mutc I4_tz_offset '        return dt.isoformat()' '        return naive_iso' "$SIG_RESET_AND_RA" \
    "cap 2026-09-29T20:00:00+05:00" "cap 2026-09-29T20:00:00"
mutc I4_weekly_phrase '        if (not has_retry_after) or reset_named or periodic_cap_named:' \
    '        if (not has_retry_after) or reset_named:' "$SIG_WEEKLY_RA" "cap UNKNOWN" "rate-limited UNKNOWN"

D="$TMP/mut_I3"
build_copy "$D"
if mutate "$D/orchestration/limit_class.py" '            invalidate_stale_out(getattr(place_args, "out", None))' \
    '            pass' >"$D.log" 2>&1; then
  printf '{"refused":false,"assignment_alias_counts":{"STALE":9}}' > "$TMP/stale2.json"
  python3 "$D/orchestration/limit_class.py" place --fixture "$TMP/op_str.json" --out "$TMP/stale2.json" >/dev/null 2>&1
  if grep -q STALE "$TMP/stale2.json" 2>/dev/null; then
    ok "mutation I3_invalidate: caught -- without the post-parse invalidation the stale verdict survives"
  else
    notok "mutation I3_invalidate SURVIVED"
  fi
else
  notok "mutation I3_invalidate: anchor not found ($(cat "$D.log"))"
fi

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R11 REGRESSION GUARD (limit_class.py): ALL CHECKS PASS ==="
  exit 0
else
  echo "=== R11 REGRESSION GUARD (limit_class.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
