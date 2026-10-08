#!/bin/bash
# test_review_record_gate_authority_mutations.sh
#
# Paired-mutation runner (constitution 1.1 / 11.4.115(F) / 11.4.276(D)) for the
# review_record.py verdict-authority fix (T048 restart round 1, R7 B1/B2).
#
# For EVERY mutation below: a scratch mirror of the fastcycle review/ + the
# review_record test suites is built, ONE exact-text mutation is applied to
# the mirror's review_record.py (the mutation must match >= 1 site, else it is
# an ERROR -- a mutation that no longer applies proves nothing), and the
# review_record suites are run against the mirror. KILLED = at least one suite
# exits non-zero. The runner FAILS on any SURVIVED or ERROR mutation, and on a
# control (unmutated) mirror that is not fully GREEN (a red control makes every
# "kill" meaningless). The live tree is never modified.
#
# Mutations R7-M1..R7-M5 are the independent reviewer's own five (R7 B2),
# re-expressed against the new code shape with identical semantics:
#   R7-M1 drop the zero-findings condition from coverage
#   R7-M2 replace verdict=="GO" with True in coverage
#   R7-M3 record rewrites a zero-finding NO-GO verdict to GO
#   R7-M4 gate picks the EARLIEST round instead of the latest
#   R7-M5 record silently lowers source-defect to process-doc
# Mutations O* are this fix's own, one per guarded condition of the class.
#
# Usage : bash test_review_record_gate_authority_mutations.sh [MUTATION_ID...]
# Exit  : 0 control GREEN and every mutation KILLED; 1 otherwise; 2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM

SUITES="test_review_record_gate_authority_r1_regression.sh test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh"

build_mirror() { # build_mirror DIR
  mkdir -p "$1/review" "$1/tests/lib" "$1/tests/fixtures"
  cp "$FC/review/review_record.py" "$1/review/"
  cp "$HERE/lib/review_record_genuine.sh" "$1/tests/lib/"
  cp -r "$HERE/fixtures/review_record" "$HERE/fixtures/review_record_finding_layer" "$1/tests/fixtures/"
  for t in $SUITES; do cp "$HERE/$t" "$1/tests/"; done
}

run_suites() { # run_suites DIR -> prints the first failing suite (empty if all pass)
  local t
  for t in $SUITES; do
    if ! timeout 300 bash "$1/tests/$t" >"$1/$t.log" 2>&1; then
      echo "$t"
      return 0
    fi
  done
  return 0
}

# MUTATIONS: id <TAB> python-literal old <TAB> python-literal new
MUTATIONS="$S/mutations.tsv"
cat > "$MUTATIONS" <<'EOF'
R7-M1	'if not (verdict == "GO" and len(findings) == 0):'	'if not (verdict == "GO"):'
R7-M2	'if not (verdict == "GO" and len(findings) == 0):'	'if not (True and len(findings) == 0):'
R7-M3	'    reviewer, err = _validated_reviewer(verdict_doc)\n'	'    if not raw_findings:\n        verdict = "GO"\n    reviewer, err = _validated_reviewer(verdict_doc)\n'
R7-M4	'if cur is None or rec["round"] > cur[0]["round"]:'	'if cur is None or rec["round"] < cur[0]["round"]:'
R7-M5	'    if isinstance(value, str) and value in FINDING_LAYERS:\n        return value, None'	'    if isinstance(value, str) and value in FINDING_LAYERS:\n        return ("process-doc" if value == "source-defect" else value), None'
O1-ledger-label	'    if not label_ok:'	'    if False:'
O2-body-hash	'if rec.get("body_hash") != _body_hash_of(rec):'	'if False:'
O3-dispatch-reuse	'if len(ctx["dispatch_use"].get(reviewer["dispatch_id"], ())) > 1:'	'if False:'
O4-precheck-all-pass	'if pre.get("all_pass") is not True:'	'if False:'
O5-precheck-schema	'if pre.get("schema") != PRECHECK_SCHEMA:'	'if False:'
O6-same-round-conflict	'if len(idents) > 1:'	'if False:'
O7-evidence-base-dir	'base_real = os.path.realpath(base_dir) if base_dir else root_real'	'base_real = root_real'
O8-record-round-budget	'    if a.round > budget:'	'    if False:'
O9-bool-round	'if not isinstance(verdict_round, int) or isinstance(verdict_round, bool):'	'if not isinstance(verdict_round, int):'
O10-seam-tier	'if ctx["seam"] in HIGH_BLAST_SEAMS and tier != "capability":'	'if False:'
O11-producer-is-reviewer	'        if producer_id == reviewer["dispatch_id"]:'	'        if False:'
O12-backfill-history	'    if source == "backfill":\n        return False, "backfill rows record history only and are never gate coverage"\n    if source != "live":'	'    if source not in ("live", "backfill"):'
O13-slice-coverage	'if set(got) != wanted or any(v != "GO" for v in got.values()):'	'if False:'
O14-reviewer-required	'if err or reviewer is None:'	'if err:'
O15-record-vs-evidence	'if (rec.get("verdict") != verdict or rec_layers != ev_layers'	'if (False'
O16-owner-uid	'            if st.st_uid == euid:'	'            if False:'
O17-hash-compare	'    return actual_sha256 == evidence_sha256'	'    return True'
O18-containment	'    if common != root_real:\n        return False'	'    if False:\n        return False'
O19-evidence-round	'if ev_round is not None and (isinstance(ev_round, bool) or ev_round != rec["round"]):'	'if False:'
O20-gate-round-budget	'if rec["round"] > ctx["round_budget"]:'	'if False:'
O21-producer-required	'if not isinstance(producer, str) or producer.strip() in ("", "UNKNOWN"):'	'if False:'
O22-slice-go-source-defect	'            if layer is None or layer == "source-defect":'	'            if layer == "source-defect":'
O23-reviewer-matches-cli	'        if reviewer["model"] != a.tier or reviewer["effort"] != a.effort:'	'        if False:'
O24-designated-tier	'if not (reviewer["model"] == DESIGNATED_TIER and reviewer["effort"] == DESIGNATED_EFFORT):'	'if False:'
EOF

apply_mutation() { # apply_mutation FILE OLD_PYLIT NEW_PYLIT -> 0 applied, 1 marker miss
  python3 - "$1" "$2" "$3" <<'PY'
import ast, sys
path, old, new = sys.argv[1], ast.literal_eval(sys.argv[2]), ast.literal_eval(sys.argv[3])
src = open(path, encoding="utf-8").read()
if old not in src:
    sys.exit(1)
open(path, "w", encoding="utf-8").write(src.replace(old, new))
PY
}

FAIL=0
echo "== control: unmutated mirror must be fully GREEN =="
build_mirror "$S/control"
FIRST_RED=$(run_suites "$S/control")
if [ -n "$FIRST_RED" ]; then
  echo "NOT ok control mirror is RED at $FIRST_RED -- kills would be meaningless"
  tail -20 "$S/control/$FIRST_RED.log"
  exit 1
fi
echo "ok control mirror GREEN across: $SUITES"

WANT=" $* "
while IFS="$(printf '\t')" read -r id old new; do
  [ -n "$id" ] || continue
  if [ "$#" -gt 0 ] && [ "${WANT#* "$id" }" = "$WANT" ]; then continue; fi
  m="$S/m_$id"
  build_mirror "$m"
  if ! apply_mutation "$m/review/review_record.py" "$old" "$new"; then
    echo "NOT ok $id ERROR (MARKER_MISS: mutation target text not found -- re-derive it)"
    FAIL=1; continue
  fi
  KILLER=$(run_suites "$m")
  if [ -n "$KILLER" ]; then
    echo "ok $id KILLED by $KILLER"
  else
    echo "NOT ok $id SURVIVED every suite"
    FAIL=1
  fi
  chmod -R u+w "$m" 2>/dev/null; rm -rf "$m"
done < "$MUTATIONS"

echo ""
[ "$FAIL" -eq 0 ] && { echo "== all mutations KILLED =="; exit 0; }
echo "== mutation runner FAILED (see NOT ok lines) =="; exit 1
