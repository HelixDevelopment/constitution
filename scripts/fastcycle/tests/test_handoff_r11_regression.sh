#!/bin/bash
# Purpose : T140 Round 11 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/handoff.py`
#           -- findings I2 (an all-fields-missing record was VALID),
#           I3 (a stale --out survived a handled refusal) and I5 (the
#           DONE-with-pending rule and the one-phase-skip transition were
#           never exercised by any fixture), plus the MINOR `random`
#           keyword gap.
#
# Every case runs the REAL tool; every rule is then deleted/weakened in a
# throwaway copy and the SAME case re-run -- the mutant must give the
# wrong answer while the real tool gives the right one. Negative controls
# (golden-good records) prove no check is a blanket refusal.
#
# Producer != Verifier (section 11.4.240): cases derived from the round-10
# reviewer's findings text, not from handoff.py's own code paths.
# SC2015: `ok`/`notok` always return 0 (they end in `echo`), so `A && ok || notok`
# can never run both branches.
# shellcheck disable=SC2015
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/handoff.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"
RRDIR="$FC/tests/fixtures/resume_revalidate"

fail=0
pass=0
failx() { fail=1; }
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { failx; echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R11 regression guard (handoff.py): control needle ==="
for p in "$IMPL" "$LIB" "$EXLIB" "$RRDIR/rr_negctrl_all_unchanged/handoff.json"; do
  [ -e "$p" ] || notok "control needle: $p not found"
done
[ "$fail" = 0 ] && ok "control needle: implementation, libs and the negative-control fixture resolve"

build_copy() {
  mkdir -p "$1/orchestration" "$1/lib"
  cp "$IMPL" "$1/orchestration/handoff.py"
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

# seal JSON_IN JSON_OUT : recompute handoff_id + body_hash so the record is
# SELF-CONSISTENT (the two hash checks pass) -- isolating the shape check.
seal() {
  python3 - "$LIB" "$1" "$2" <<'PYEOF'
import hashlib, importlib.util, json, sys
spec = importlib.util.spec_from_file_location("fc_common", sys.argv[1])
fc = importlib.util.module_from_spec(spec); spec.loader.exec_module(fc)
doc = json.load(open(sys.argv[2]))
doc.pop("handoff_id", None); doc.pop("body_hash", None); doc.pop("run_meta", None)
doc["handoff_id"] = "sha256:" + hashlib.sha256(fc.canon(doc).encode("utf-8")).hexdigest()
doc["body_hash"] = fc.body_hash_of(doc)
json.dump(doc, open(sys.argv[3], "w"))
PYEOF
}

# outcome IMPL SUBCMD HANDOFF -> prints "<rc> <outcome-or-safe> <reasons/mismatches joined>"
outcome() {
  local impl="$1" sub="$2" h="$3" o="$TMP/o.$RANDOM.json"
  python3 "$impl" "$sub" --handoff "$h" --out "$o" >/dev/null 2>&1
  local rc=$?
  python3 - "$o" "$rc" <<'PYEOF'
import json, sys
o, rc = sys.argv[1:]
try:
    d = json.load(open(o))
except Exception:
    print(rc, "NO_DOC", "-"); sys.exit()
if "outcome" in d:
    print(rc, d["outcome"], "|".join(d.get("mismatches", [])))
else:
    print(rc, "SAFE" if d.get("safe_to_resume_without_reverification") else "UNSAFE",
          "|".join(r.get("class", "?") for r in d.get("unsafe_reasons", [])))
PYEOF
}

# ---------------------------------------------------------------------------
# I2: validate/verify shape check
# ---------------------------------------------------------------------------
echo
echo "=== I2: positive control -- a genuine 'write' record validates VALID ==="
mkdir -p "$TMP/w"
printf 'partial bytes\n' > "$TMP/w/part.txt"
python3 "$IMPL" write --item-id ATM-1 --agent-key k1 --alias claude1 --model sonnet --effort high \
    --phase IMPLEMENT --partial-artefacts part.txt --handoff "$TMP/w/handoff.json" --out "$TMP/w/wr.json" \
    >/dev/null 2>&1
R=$(outcome "$IMPL" validate "$TMP/w/handoff.json")
[[ "$R" == "0 VALID"* ]] && ok "I2 golden write->validate: $R" || notok "I2 golden write->validate: $R"

echo
echo "=== I2: a record holding only {schema:\"whatever\"} (self-consistent hashes) ==="
printf '{"schema":"whatever"}' > "$TMP/raw_min.json"
seal "$TMP/raw_min.json" "$TMP/w/min.json"
for sub in validate verify; do
  R=$(outcome "$IMPL" "$sub" "$TMP/w/min.json")
  if [[ "$R" == "1 INVALID"* ]] && [[ "$R" == *"missing_required_field:item_id"* ]] \
      && [[ "$R" == *"missing_required_field:partial_artefacts"* ]] && [[ "$R" == *"schema:expected="* ]]; then
    ok "I2 $sub minimal record -> INVALID naming every missing field + the schema"
  else
    notok "I2 $sub minimal record: $R"
  fi
done

echo
echo "=== I2: complete record but WRONG schema / missing partial_artefacts / wrong type ==="
python3 - "$TMP/w/handoff.json" "$TMP" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); t = sys.argv[2]
a = dict(d); a["schema"] = "handoff/v999"; json.dump(a, open(t + "/raw_badschema.json", "w"))
b = dict(d); del b["partial_artefacts"]; json.dump(b, open(t + "/raw_nopart.json", "w"))
c = dict(d); c["verified"] = "not-a-list"; json.dump(c, open(t + "/raw_badtype.json", "w"))
PYEOF
seal "$TMP/raw_badschema.json" "$TMP/w/badschema.json"
seal "$TMP/raw_nopart.json" "$TMP/w/nopart.json"
seal "$TMP/raw_badtype.json" "$TMP/w/badtype.json"
R=$(outcome "$IMPL" validate "$TMP/w/badschema.json")
[[ "$R" == "1 INVALID schema:expected="* ]] && ok "I2 wrong schema -> $R" || notok "I2 wrong schema: $R"
R=$(outcome "$IMPL" validate "$TMP/w/nopart.json")
[[ "$R" == "1 INVALID missing_required_field:partial_artefacts" ]] && ok "I2 no partial_artefacts -> $R" \
  || notok "I2 no partial_artefacts: $R"
R=$(outcome "$IMPL" validate "$TMP/w/badtype.json")
[[ "$R" == "1 INVALID malformed:verified:expected-list:got-str" ]] && ok "I2 verified not a list -> $R" \
  || notok "I2 verified not a list: $R"

# ---------------------------------------------------------------------------
# I5: resume-check DONE-with-pending + one-phase-skip transition
# ---------------------------------------------------------------------------
mkcase() {  # mkcase NAME PYTHON-EXPR-MUTATING-d
  rm -rf "${TMP:?}/${1:?}"; cp -r "$RRDIR/rr_negctrl_all_unchanged" "$TMP/$1"
  python3 - "$TMP/$1/handoff.json" "$2" <<'PYEOF'
import json, sys
p, expr = sys.argv[1:]
d = json.load(open(p))
exec(expr)
json.dump(d, open(p, "w"))
PYEOF
}
echo
echo "=== I5: resume-check negative controls stay SAFE ==="
R=$(outcome "$IMPL" resume-check "$RRDIR/rr_negctrl_all_unchanged/handoff.json")
[[ "$R" == "0 SAFE"* ]] && ok "I5 negctrl (IMPLEMENT->VERIFY, adjacent) -> $R" || notok "I5 negctrl: $R"
mkcase done_empty 'd["phase"]="DONE"; d["verified"][0]["phase"]="DEPLOY"; d["pending"]=[]'
R=$(outcome "$IMPL" resume-check "$TMP/done_empty/handoff.json")
[[ "$R" == "0 SAFE"* ]] && ok "I5 DONE with EMPTY pending (DEPLOY->DONE) -> $R" || notok "I5 DONE empty pending: $R"

echo
echo "=== I5: phase DONE with pending non-empty ==="
mkcase done_pending 'd["phase"]="DONE"; d["verified"][0]["phase"]="DEPLOY"'
R=$(outcome "$IMPL" resume-check "$TMP/done_pending/handoff.json")
[[ "$R" == "1 UNSAFE inconsistent-internal-state" ]] && ok "I5 DONE+pending -> $R" || notok "I5 DONE+pending: $R"

echo
echo "=== I5: a ONE-phase skip (IMPLEMENT -> DEPLOY, VERIFY skipped) ==="
mkcase skip_one 'd["phase"]="DEPLOY"'
R=$(outcome "$IMPL" resume-check "$TMP/skip_one/handoff.json")
[[ "$R" == "1 UNSAFE inconsistent-transition" ]] && ok "I5 one-phase skip -> $R" || notok "I5 one-phase skip: $R"

echo
echo "=== MINOR: a pending step naming 'random' is nondeterministic-replay ==="
mkcase rnd 'd["pending"]=[{"step":"pick a random sample of rows","precondition":"none"}]'
R=$(outcome "$IMPL" resume-check "$TMP/rnd/handoff.json")
[[ "$R" == "1 UNSAFE nondeterministic-replay" ]] && ok "random keyword -> $R" || notok "random keyword: $R"

# ---------------------------------------------------------------------------
# I3: a stale --out never survives a handled (post-parse) refusal
# ---------------------------------------------------------------------------
echo
echo "=== I3: stale --out removed on a handled refusal ==="
stale() { printf '{"schema":"handoff-validate/v1","outcome":"VALID","mismatches":[],"body_hash":"STALE"}' > "$1"; }
stale "$TMP/s1.json"
python3 "$IMPL" validate --handoff "$TMP/does_not_exist.json" --out "$TMP/s1.json" >/dev/null 2>&1
RC=$?
if [ "$RC" = 2 ] && ! grep -q STALE "$TMP/s1.json" 2>/dev/null; then
  ok "I3 validate on a missing --handoff file (rc=2): the previous VALID report is gone"
else
  notok "I3 validate missing --handoff: rc=$RC stale_left=$(grep -c STALE "$TMP/s1.json" 2>/dev/null)"
fi
stale "$TMP/s2.json"
python3 "$IMPL" write --item-id ATM-1 --agent-key k1 --alias a --model m --effort e --phase PLAN \
    --partial-artefacts missing.txt --handoff "$TMP/w/h2.json" --out "$TMP/s2.json" >/dev/null 2>&1
RC=$?
if [ "$RC" = 1 ] && ! grep -q STALE "$TMP/s2.json" 2>/dev/null; then
  ok "I3 write refusing a missing partial artefact (rc=1): the previous report is gone"
else
  notok "I3 write refusal: rc=$RC stale_left=$(grep -c STALE "$TMP/s2.json" 2>/dev/null)"
fi
mkfifo "$TMP/fifo_out"
python3 "$IMPL" validate --handoff "$TMP/does_not_exist.json" --out "$TMP/fifo_out" >/dev/null 2>&1
[ -p "$TMP/fifo_out" ] && ok "I3 safety: a non-regular --out (FIFO) is never removed" \
  || notok "I3 safety: the FIFO --out was removed"

# ---------------------------------------------------------------------------
# guard viability
# ---------------------------------------------------------------------------
mut() {  # mut NAME OLD NEW SUBCMD HANDOFF WANT_REAL_PREFIX WANT_MUTANT_PREFIX
  local d="$TMP/mut_$1"
  build_copy "$d"
  if ! mutate "$d/orchestration/handoff.py" "$2" "$3" >"$d.log" 2>&1; then
    notok "mutation $1: anchor not found ($(cat "$d.log"))"; return
  fi
  local real mutant
  real=$(outcome "$IMPL" "$4" "$5")
  mutant=$(outcome "$d/orchestration/handoff.py" "$4" "$5")
  if [[ "$real" == "$6"* ]] && [[ "$mutant" == "$7"* ]]; then
    ok "mutation $1: caught -- real '$real' vs mutant '$mutant'"
  else
    notok "mutation $1: real='$real' (want $6...) mutant='$mutant' (want $7...)"
  fi
}
echo
echo "=== guard viability (paired mutations) ==="
mut I2_schema '    if doc.get("schema") != SCHEMA_HANDOFF:' '    if False:' \
    validate "$TMP/w/badschema.json" "1 INVALID" "0 VALID"
mut I2_fields '    for field, want_type in HO001_REQUIRED_FIELDS:' '    for field, want_type in ():' \
    validate "$TMP/w/nopart.json" "1 INVALID" "0 VALID"
mut I2_types '        elif not isinstance(doc[field], want_type):' '        elif False:' \
    validate "$TMP/w/badtype.json" "1 INVALID" "0 VALID"
mut I5_done_pending '        if doc.get("phase") in TERMINAL_PHASES and doc.get("pending"):' '        if False:' \
    resume-check "$TMP/done_pending/handoff.json" "1 UNSAFE" "0 SAFE"
mut I5_off_by_one_skip '            if i_cur > i_last + 1:' '            if i_cur > i_last + 2:' \
    resume-check "$TMP/skip_one/handoff.json" "1 UNSAFE" "0 SAFE"
mut I5_off_by_one_adjacent '            if i_cur > i_last + 1:' '            if i_cur > i_last:' \
    resume-check "$RRDIR/rr_negctrl_all_unchanged/handoff.json" "0 SAFE" "1 UNSAFE"
mut MINOR_random_kw '"llm-generated", "random", "nondeterministic"' '"llm-generated", "nondeterministic"' \
    resume-check "$TMP/rnd/handoff.json" "1 UNSAFE" "0 SAFE"

# I3 mutation: drop the post-parse invalidation -> the stale report survives.
D="$TMP/mut_I3"
build_copy "$D"
if mutate "$D/orchestration/handoff.py" '        invalidate_stale_out(getattr(a, "out", None))
        return handler(a)' '        return handler(a)' >"$D.log" 2>&1; then
  stale "$TMP/s3.json"
  python3 "$D/orchestration/handoff.py" validate --handoff "$TMP/does_not_exist.json" --out "$TMP/s3.json" >/dev/null 2>&1
  if grep -q STALE "$TMP/s3.json" 2>/dev/null; then
    ok "mutation I3_invalidate: caught -- without the post-parse invalidation the stale VALID report survives"
  else
    notok "mutation I3_invalidate SURVIVED: stale report gone even without the fix"
  fi
else
  notok "mutation I3_invalidate: anchor not found ($(cat "$D.log"))"
fi

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R11 REGRESSION GUARD (handoff.py): ALL CHECKS PASS ==="
  exit 0
else
  echo "=== R11 REGRESSION GUARD (handoff.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
