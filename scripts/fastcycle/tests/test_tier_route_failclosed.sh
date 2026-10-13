#!/usr/bin/env bash
# test_tier_route_failclosed.sh -- T121 review finding regression test
# (SpecKit-004, US4). Proves context/tier_route.py FAILS CLOSED on the two
# input shapes the independent T121 review found routed silently:
#   F-TR2 (safety): a fixture with NO `is_review_class` key (or a non-bool
#     value) was routed to the default tier with exit 0 -- a review-class
#     task could reach a cheap tier merely by omitting the flag
#     (constitution 11.4.252 fail-closed-on-dangerous-combination,
#     11.4.231(E) review pin). Must now be a usage error (exit 2).
#   F-TR1: a no-verifier fixture carrying `default_tier: "haiku"` routed to
#     haiku (exit 0) -- the fixture could override the 11.4.231(A) default
#     working tier the safety-net branch exists to guarantee, including to a
#     tier 11.4.231(D.1) prohibits here. Must now be a usage error (exit 2).
# Golden-FALSE controls (11.4.201(1)): the unmodified negative-control
# fixture MUST still route to sonnet with exit 0, and the unmodified review
# fixture MUST still be refused with exit 1 -- a fix that refuses
# everything fails this test.
# Hermetic: every mutated fixture is written under a mktemp dir, removed on
# exit; the checked-in fixtures are never modified.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TR="$HERE/../context/tier_route.py"
FX="$HERE/fixtures/tier_route"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "ok   $*"; pass=$((pass+1)); }
bad(){ echo "FAIL $*"; fail=$((fail+1)); }

run(){ # $1=fixture -> sets RC and OUT
  OUT="$TMP/out.$RANDOM.json"
  python3 "$TR" route --fixture "$1" --out "$OUT" >/dev/null 2>"$TMP/err"
  RC=$?
}
mutate(){ # $1=src $2=dst $3=python expr on d
  python3 - "$1" "$2" "$3" <<'E'
import json,sys
d=json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(d,open(sys.argv[2],'w'))
E
}

# control needle: the tool and fixtures must exist, else the zeros below are blind
[ -f "$TR" ] && [ -f "$FX/tr_negctrl_no_verifier.json" ] && [ -f "$FX/tr_bad_review_routed_cheap.json" ] \
  || { echo "BLIND: tool or fixtures missing"; exit 4; }

# 1 golden-FALSE: unmodified negctrl -> exit 0, final_tier sonnet
run "$FX/tr_negctrl_no_verifier.json"
if [ "$RC" -eq 0 ] && python3 -c "import json;assert json.load(open('$OUT'))['final_tier']=='sonnet'" 2>/dev/null
then ok "negctrl unmodified routes to sonnet (rc=0)"; else bad "negctrl unmodified rc=$RC"; fi

# 2 golden-FALSE: unmodified review fixture -> refused exit 1
run "$FX/tr_bad_review_routed_cheap.json"
[ "$RC" -eq 1 ] && ok "review fixture unmodified refused (rc=1)" || bad "review fixture rc=$RC (want 1)"

# 3 F-TR2: review fixture with is_review_class removed -> must NOT route (exit 2)
mutate "$FX/tr_bad_review_routed_cheap.json" "$TMP/norc.json" "d.pop('is_review_class',None)"
run "$TMP/norc.json"
[ "$RC" -eq 2 ] && ok "F-TR2 missing is_review_class -> usage error (rc=2)" || bad "F-TR2 missing is_review_class rc=$RC (want 2)"

# 4 F-TR2: is_review_class as a non-bool truthy string -> exit 2
mutate "$FX/tr_bad_review_routed_cheap.json" "$TMP/strrc.json" "d['is_review_class']='yes'"
run "$TMP/strrc.json"
[ "$RC" -eq 2 ] && ok "F-TR2 non-bool is_review_class -> usage error (rc=2)" || bad "F-TR2 non-bool is_review_class rc=$RC (want 2)"

# 5 F-TR2 sibling: has_deterministic_verifier missing -> exit 2
mutate "$FX/tr_negctrl_no_verifier.json" "$TMP/nohdv.json" "d.pop('has_deterministic_verifier',None)"
run "$TMP/nohdv.json"
[ "$RC" -eq 2 ] && ok "missing has_deterministic_verifier -> usage error (rc=2)" || bad "missing has_deterministic_verifier rc=$RC (want 2)"

# 6 F-TR1: default_tier overridden to haiku -> exit 2
mutate "$FX/tr_negctrl_no_verifier.json" "$TMP/haiku.json" "d['default_tier']='haiku'"
run "$TMP/haiku.json"
[ "$RC" -eq 2 ] && ok "F-TR1 default_tier=haiku -> usage error (rc=2)" || bad "F-TR1 default_tier=haiku rc=$RC (want 2)"

# 7 F-TR1: default_tier overridden to opus -> exit 2 (override of any kind)
mutate "$FX/tr_negctrl_no_verifier.json" "$TMP/opus.json" "d['default_tier']='opus'"
run "$TMP/opus.json"
[ "$RC" -eq 2 ] && ok "F-TR1 default_tier=opus -> usage error (rc=2)" || bad "F-TR1 default_tier=opus rc=$RC (want 2)"

# 8 default_tier absent entirely -> still the constitution default sonnet
mutate "$FX/tr_negctrl_no_verifier.json" "$TMP/nodt.json" "d.pop('default_tier',None)"
run "$TMP/nodt.json"
if [ "$RC" -eq 0 ] && python3 -c "import json;assert json.load(open('$OUT'))['final_tier']=='sonnet'" 2>/dev/null
then ok "absent default_tier -> sonnet (rc=0)"; else bad "absent default_tier rc=$RC"; fi

echo "RESULT: $pass PASS / $fail FAIL"
[ "$fail" -eq 0 ]
