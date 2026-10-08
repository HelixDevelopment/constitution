#!/bin/bash
# review_record_genuine.sh -- sourced helper for the review_record.py gate
# regression suites (T048 restart round-1 R7 B1/B2/I1-I3 remediation).
#
# Purpose: build a GENUINE live ReviewVerdictRecord the only way a real one
#          is ever produced -- by running the REAL `review_record.py record`
#          CLI over a real batch.json, a real precheck/v1 precheck.json, a
#          reviewer-authored verdict.json carrying the reviewer's own
#          identity block, and a dispatch-ledger row for that reviewer's
#          dispatch. Nothing here re-implements or text-extracts any gate
#          logic (constitution 11.4.276(D)): every assertion a caller makes
#          is made against the real tool's real stdout/rc/output files.
#
# Usage (after `. this-file`):
#   RR_TOOL=<path to review_record.py>   (required)
#   RR_WORK=<scratch dir for inputs>     (required)
#   RR_LEDGER=<dispatch-ledger JSONL>    (required)
#   rr_ledger_row DISPATCH_ID MODEL EFFORT
#       appends one ledger row whose 11.4.182 label names MODEL/EFFORT.
#   rr_genuine OUT_JSON BATCH CHANGE ROUND VERDICT FINDINGS_JSON DISPATCH \
#              [extra record args...]
#       writes inputs under $RR_WORK/<basename OUT_JSON>/, appends a ledger
#       row for DISPATCH (opus/xhigh) unless RR_SKIP_LEDGER=1, and runs the
#       real `record` CLI with --producer-id ${RR_PRODUCER-PRODUCER-MAIN}
#       (RR_PRODUCER set but empty passes an empty producer id).
#       Sets RR_RC to record's exit status. Optional knobs (env):
#         RR_PRECHECK_ALL_PASS (default true), RR_PRECHECK_SCHEMA (default
#         precheck/v1), RR_SLICES (JSON list for batch "slices", default []),
#         RR_SLICE_VERDICTS (JSON for verdict "slice_verdicts", default
#         unset), RR_REVIEWER_MODEL/RR_REVIEWER_EFFORT (default opus/xhigh),
#         RR_NO_REVIEWER=1 (omit the reviewer block entirely).
#
# Exit: functions return 0; record's own rc is reported via RR_RC.

rr_ledger_row() {
  python3 - "$RR_LEDGER" "$1" "$2" "$3" <<'PY'
import json, sys
path, key, model, effort = sys.argv[1:5]
row = {"ts": "2026-10-08T00:00:00Z", "event": "in-flight", "key": key,
       "tool_name": "Agent",
       "description": "(T1/main - claude5 - %s - %s) item=ATM-1041 [REVIEW] fixture" % (model, effort)}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row) + "\n")
PY
}

rr_genuine() {
  local out="$1" batch="$2" change="$3" round="$4" verdict="$5" findings="$6" dispatch="$7"
  shift 7
  local name d
  name="$(basename "$out" .json)"
  d="$RR_WORK/$name"
  mkdir -p "$d"
  python3 - "$d" "$batch" "$change" "$round" "$verdict" "$findings" "$dispatch" <<'PY'
import json, os, sys
d, batch, change, rnd, verdict, findings, dispatch = sys.argv[1:8]
env = os.environ
slices = json.loads(env.get("RR_SLICES", "[]"))
with open(os.path.join(d, "batch.json"), "w", encoding="utf-8") as fh:
    json.dump({"batch_id": batch, "changes": [change], "slices": slices}, fh)
pre = {"batch_id": batch, "all_pass": env.get("RR_PRECHECK_ALL_PASS", "true") == "true",
       "checks": []}
schema = env.get("RR_PRECHECK_SCHEMA", "precheck/v1")
if schema != "<none>":
    pre["schema"] = schema
with open(os.path.join(d, "precheck.json"), "w", encoding="utf-8") as fh:
    json.dump(pre, fh)
v = {"round": int(rnd), "verdict": verdict, "findings": json.loads(findings)}
if env.get("RR_NO_REVIEWER") != "1":
    v["reviewer"] = {"dispatch_id": dispatch,
                     "model": env.get("RR_REVIEWER_MODEL", "opus"),
                     "effort": env.get("RR_REVIEWER_EFFORT", "xhigh")}
if "RR_SLICE_VERDICTS" in env:
    v["slice_verdicts"] = json.loads(env["RR_SLICE_VERDICTS"])
with open(os.path.join(d, "verdict.json"), "w", encoding="utf-8") as fh:
    json.dump(v, fh)
PY
  if [ "${RR_SKIP_LEDGER:-0}" != "1" ]; then
    rr_ledger_row "$dispatch" opus xhigh
  fi
  python3 "$RR_TOOL" record --batch "$d/batch.json" --round "$round" \
    --verdict-file "$d/verdict.json" --precheck "$d/precheck.json" \
    --tier opus --effort xhigh --producer-id "${RR_PRODUCER-PRODUCER-MAIN}" \
    --out "$out" "$@" >"$d/record.out" 2>"$d/record.err"
  # shellcheck disable=SC2034  # RR_RC is consumed by the sourcing test
  RR_RC=$?
  return 0
}
