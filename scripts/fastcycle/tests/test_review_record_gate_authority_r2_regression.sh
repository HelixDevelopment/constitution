#!/bin/bash
# test_review_record_gate_authority_r2_regression.sh
#
# T048 restart, independent review ROUND 2, area V3
# (docs/qa/t048_restart_round2_20261008/V3_review_record_gate_authority.md):
# regression suite for the defect CLASS "the gate lets a producer obtain
# COVERED for its own work at ordinary seams" in review/review_record.py.
#
# Class members enumerated (constitution 11.4.276(C)), each with a case below:
#   P1  replay of a genuine reviewer GO onto a different batch/change set
#       (reviewer evidence not bound to what it covers)            -> F1, m1
#   P1x the binding fields themselves: batch_id, change_ids, round (mandatory,
#       integer, non-bool), review_base/review_head (commit-shaped, equal to
#       the record's copies and to the batch's own declaration)     -> F1, N8
#   P2  an invented / unfinished dispatch authenticating through the ledger:
#       only dispatched->complete rows authenticate; crashed/failed/
#       in-flight-latest never do; exactly one 11.4.182 label per row, and
#       every row of the dispatch names the same designated model/effort -> m4
#   P3  a reviewer NO-GO bypassed by another batch listing the same change:
#       coverage is a function of EVERY batch that lists the change   -> F2
#   T   the independence tier rated against the PRODUCER uid, never the uid
#       running gate; unknown producer -> never "capability"        -> F3, N1, N2
#   S   remaining single-condition guards without an isolating case:
#       precheck batch binding (N4), gate-side producer==reviewer (N11),
#       record-vs-evidence consistency for layers/model/effort (m3: N6, N12).
#
# Every case drives the REAL `review_record.py record` / `gate` CLI. The tier
# cases call the real module's own _independence_tier() in-process on REAL
# files with real modes and real owners -- no os.geteuid substitution, no
# re-implemented logic (constitution 11.4.276(D)). The forged-record cases
# edit the real artifacts `record` wrote (re-hashing them exactly as an
# attacker would) and then run the real gate.
#
# Usage : bash test_review_record_gate_authority_r2_regression.sh
# Exit  : 0 all checks pass; 1 any check failed; 2 scratch dir unusable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
# shellcheck disable=SC2034 # RR_TOOL is consumed by the sourced lib/review_record_genuine.sh
RR_TOOL="$FC/review/review_record.py"
# shellcheck source=lib/review_record_genuine.sh
# shellcheck disable=SC1091 # sourced helper is linted on its own; the precheck pack runs shellcheck without -x
. "$HERE/lib/review_record_genuine.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM
RR_WORK="$S/work"; mkdir -p "$RR_WORK"
NONE='[]'
SD='[{"id":"F1","severity":"BLOCKING","finding_layer":"source-defect"}]'

fresh_case() {
  CASE="$S/$1"; mkdir -p "$CASE/records"
  RR_LEDGER="$CASE/ledger.jsonl"; : > "$RR_LEDGER"
  REC="$CASE/records"
}
gate() { # gate CHANGE [extra args] -> sets G_RC, G_OUT
  G_OUT=$(python3 "$RR_TOOL" gate --change "$1" --records "$REC" --dispatch-ledger "$RR_LEDGER" "${@:2}" 2>&1)
  G_RC=$?
}
covered()   { [ "$G_RC" -eq 0 ] && printf '%s\n' "$G_OUT" | grep -q "^COVERED $1 "; }
uncovered() { [ "$G_RC" -eq 1 ] && printf '%s\n' "$G_OUT" | grep -q "^UNCOVERED $1"; }
has()       { printf '%s\n' "$G_OUT" | grep -q -- "$1"; }

# rehash REC_JSON PY_STMT: edit a record the way an attacker would (apply the
# statement to dict `d`, then recompute body_hash so the integrity check
# passes) -- the gate must still refuse from the reviewer's evidence.
rehash() {
  python3 - "$1" "$2" <<'PY'
import hashlib, json, sys
p, stmt = sys.argv[1], sys.argv[2]
d = json.load(open(p))
exec(stmt)
body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
}
# reforge REC_JSON PY_STMT: rewrite the ARCHIVED reviewer evidence (apply the
# statement to dict `v`), re-archive it content-addressed, and re-point +
# re-hash the record -- a complete single-uid forgery of the evidence chain.
reforge() {
  python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
p, stmt = sys.argv[1], sys.argv[2]
d = json.load(open(p)); base = os.path.dirname(p)
v = json.load(open(os.path.join(base, d["verdict_evidence"])))
exec(stmt)
raw = json.dumps(v).encode()
sha = hashlib.sha256(raw).hexdigest()
open(os.path.join(base, sha + ".verdict-evidence"), "wb").write(raw)
d["verdict_evidence"] = sha + ".verdict-evidence"; d["verdict_evidence_sha256"] = sha
body = {k: x for k, x in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
}

echo "== V3 round-2 regression: no producer self-coverage at ordinary seams =="

# --- control: a genuine bound reviewer GO is COVERED -------------------------
fresh_case ctl
rr_genuine "$REC/r1.json" B2 c2 1 GO "$NONE" D-CTL
gate c2
if [ "$RR_RC" -eq 0 ] && covered c2; then ok "CTL: genuine, bound reviewer GO for (B2,[c2]) is COVERED"
else bad "CTL: rc_record=$RR_RC err=$(cat "$RR_WORK/r1/record.err") rc=$G_RC out=$G_OUT"; fi
CTL_VERDICT="$RR_WORK/r1/verdict.json"

# --- P1: replay B2's genuine verdict onto the producer's own batch -----------
fresh_case p1
RR_SKIP_LEDGER=1 RR_VERDICT_FROM="$CTL_VERDICT" rr_genuine "$REC/rx.json" BX cX 1 GO "$NONE" D-CTL
cp "$S/ctl/ledger.jsonl" "$RR_LEDGER"
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/rx.json" ] && grep -q "bound to" "$RR_WORK/rx/record.err"; then
  ok "P1: record refuses (rc 1, nothing written) to attach a verdict bound to (B2,[c2]) to batch BX/[cX]"
else bad "P1: rc=$RR_RC exists=$([ -f "$REC/rx.json" ] && echo y || echo n) err=$(cat "$RR_WORK/rx/record.err")"; fi
gate cX
if uncovered cX; then ok "P1b: gate cX after the replay attempt is UNCOVERED"
else bad "P1b: rc=$G_RC out=$G_OUT"; fi

# P1c: bypass `record` -- hand-edit a genuine record to claim BX/[cX] and re-hash it.
fresh_case p1c
rr_genuine "$REC/r1.json" B2 c2 1 GO "$NONE" D-P1C
rehash "$REC/r1.json" 'd["batch_id"]="BX"; d["change_ids"]=["cX"]; d["review_id"]="REV-BX-1"'
gate cX
if uncovered cX && has "binding"; then ok "P1c: a re-hashed record re-pointed at BX/[cX] is refused from the reviewer's own binding"
else bad "P1c: rc=$G_RC out=$G_OUT"; fi
# P1d: widen the change set instead (B2 kept, cX added).
fresh_case p1d
rr_genuine "$REC/r1.json" B2 c2 1 GO "$NONE" D-P1D
rehash "$REC/r1.json" 'd["change_ids"]=["c2","cX"]'
gate cX
if uncovered cX && has "binding"; then ok "P1d: adding cX to a genuine record's change_ids is refused (bound set is {c2})"
else bad "P1d: rc=$G_RC out=$G_OUT"; fi

# P1h: re-point ONLY the batch id (change set kept) -- the binding, not just
# the precheck, must refuse it (reason names the binding).
fresh_case p1h
rr_genuine "$REC/r1.json" B2 c2 1 GO "$NONE" D-P1H
rehash "$REC/r1.json" 'd["batch_id"]="BX"; d["review_id"]="REV-BX-1"'
gate c2
if uncovered c2 && has "binding"; then ok "P1h: a record re-pointed at another batch id (same changes) is refused from the reviewer's binding"
else bad "P1h: rc=$G_RC out=$G_OUT"; fi

# P1i: replay onto a batch with the SAME change set but another batch id.
fresh_case p1i
RR_SKIP_LEDGER=1 RR_VERDICT_FROM="$CTL_VERDICT" rr_genuine "$REC/r1.json" B-OTHER c2 1 GO "$NONE" D-CTL
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r1.json" ] && grep -q "bound to" "$RR_WORK/r1/record.err"; then
  ok "P1i: record refuses a (B2,[c2]) verdict attached to batch B-OTHER with the same change set"
else bad "P1i: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi

# P1e: a reviewer-identified verdict with no binding at all is refused at record time.
fresh_case p1e
RR_NO_BINDING=1 rr_genuine "$REC/r1.json" B-P1E c-p1e 1 GO "$NONE" D-P1E
if [ "$RR_RC" -eq 2 ] && [ ! -f "$REC/r1.json" ] && grep -q "binding" "$RR_WORK/r1/record.err"; then
  ok "P1e: record refuses (rc 2) a reviewer verdict carrying no review binding"
else bad "P1e: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi

# P1f: change-set mismatch at record time (batch {a,b}, verdict bound to {a}).
fresh_case p1f
RR_CHANGES='["c-a","c-b"]' RR_V_CHANGES='["c-a"]' rr_genuine "$REC/r1.json" B-P1F c-a 1 GO "$NONE" D-P1F
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r1.json" ]; then ok "P1f: record refuses a batch whose change set differs from the reviewed set"
else bad "P1f: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi
RR_CHANGES='["c-a","c-b"]' rr_genuine "$REC/r2.json" B-P1F2 c-a 1 GO "$NONE" D-P1F2
gate c-b
if [ "$RR_RC" -eq 0 ] && covered c-b; then ok "P1f (negative control): a two-change batch reviewed as exactly that set is COVERED for c-b"
else bad "P1f-n: rc_record=$RR_RC rc=$G_RC out=$G_OUT"; fi

# P1g: commit binding -- batch declares review_head X, verdict reviewed Y.
fresh_case p1g
RR_BATCH_HEAD=3333333333333333333333333333333333333333 rr_genuine "$REC/r1.json" B-P1G c-p1g 1 GO "$NONE" D-P1G
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r1.json" ] && grep -q "review_head" "$RR_WORK/r1/record.err"; then
  ok "P1g: record refuses a verdict whose review_head differs from the batch's declared head"
else bad "P1g: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi
RR_V_HEAD=not-a-commit rr_genuine "$REC/r2.json" B-P1G2 c-p1g2 1 GO "$NONE" D-P1G2
if [ "$RR_RC" -eq 2 ]; then ok "P1g2: a non-commit-shaped review_head is a usage error (2)"
else bad "P1g2: rc=$RR_RC"; fi
# record copies diverging from the (re-forged) evidence head
fresh_case p1g3
rr_genuine "$REC/r1.json" B-P1G3 c-p1g3 1 GO "$NONE" D-P1G3
reforge "$REC/r1.json" 'v["review_head"]="4444444444444444444444444444444444444444"'
gate c-p1g3
if uncovered c-p1g3 && has "binding"; then ok "P1g3: evidence head differing from the record's review_head is refused"
else bad "P1g3: rc=$G_RC out=$G_OUT"; fi

fresh_case p1g4
rr_genuine "$REC/r1.json" B-P1G4 c-p1g4 1 GO "$NONE" D-P1G4
reforge "$REC/r1.json" 'v["review_base"]="5555555555555555555555555555555555555555"'
gate c-p1g4
if uncovered c-p1g4 && has "binding"; then ok "P1g4: evidence base differing from the record's review_base is refused"
else bad "P1g4: rc=$G_RC out=$G_OUT"; fi

# --- round mandatory (m1) and integer-only at gate time (N8) -----------------
fresh_case rnd
RR_V_NO_ROUND=1 rr_genuine "$REC/r1.json" B-RND c-rnd 1 GO "$NONE" D-RND
if [ "$RR_RC" -eq 2 ] && [ ! -f "$REC/r1.json" ] && grep -q "round" "$RR_WORK/r1/record.err"; then
  ok "m1: record refuses (rc 2) a verdict file with no 'round'"
else bad "m1: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi
fresh_case rnd2
rr_genuine "$REC/r1.json" B-RND2 c-rnd2 1 GO "$NONE" D-RND2
reforge "$REC/r1.json" 'del v["round"]'
gate c-rnd2
if uncovered c-rnd2 && has "round"; then ok "m1b: archived evidence with no 'round' is refused at gate time"
else bad "m1b: rc=$G_RC out=$G_OUT"; fi
fresh_case rnd3
rr_genuine "$REC/r1.json" B-RND3 c-rnd3 1 GO "$NONE" D-RND3
reforge "$REC/r1.json" 'v["round"]=True'
gate c-rnd3
if uncovered c-rnd3 && has "round"; then ok "N8: archived evidence with round=true (bool) is refused at gate time"
else bad "N8: rc=$G_RC out=$G_OUT"; fi

# --- P3: a NO-GO in one batch is not overridden by another batch (F2) -------
fresh_case p3
rr_genuine "$REC/b1r1.json" B1 cY 1 GO "$NONE" D-P3A
rr_genuine "$REC/b1r2.json" B1 cY 2 NO-GO "$SD" D-P3B
gate cY; RC_A=$G_RC
rr_genuine "$REC/b9r1.json" B9 cY 1 GO "$NONE" D-P3C
gate cY
if [ "$RC_A" -eq 1 ] && uncovered cY && has "B1"; then ok "P3: B1's latest NO-GO on cY still blocks after a genuine GO in another batch B9 (named in the reason)"
else bad "P3: rcA=$RC_A rc=$G_RC out=$G_OUT"; fi
fresh_case p3n
rr_genuine "$REC/b1r1.json" B1 cY 1 NO-GO "$SD" D-P3NA
rr_genuine "$REC/b1r2.json" B1 cY 2 GO "$NONE" D-P3NB
rr_genuine "$REC/b9r1.json" B9 cY 1 GO "$NONE" D-P3NC
gate cY
if covered cY; then ok "P3n (negative control): every batch listing cY has a qualifying latest GO -> COVERED"
else bad "P3n: rc=$G_RC out=$G_OUT"; fi
# a change dropped from batch A after an unresolved NO-GO keeps blocking ...
fresh_case p3d
rr_genuine "$REC/a1.json" BA cZ 1 NO-GO "$SD" D-P3DA
rr_genuine "$REC/a2.json" BA cW 2 GO "$NONE" D-P3DB
rr_genuine "$REC/b1.json" BB cZ 1 GO "$NONE" D-P3DC
gate cZ
if uncovered cZ && has "BA" && has "later round dropped it"; then ok "P3d: cZ dropped from batch BA after BA's NO-GO on it is still blocked by BA"
else bad "P3d: rc=$G_RC out=$G_OUT"; fi
# ... but a change dropped after a GO on it does not (11.4.201(1) false-refusal guard).
fresh_case p3e
rr_genuine "$REC/a1.json" BA cZ 1 GO "$NONE" D-P3EA
rr_genuine "$REC/a2.json" BA cW 2 GO "$NONE" D-P3EB
rr_genuine "$REC/b1.json" BB cZ 1 GO "$NONE" D-P3EC
gate cZ
if covered cZ; then ok "P3e (negative control): cZ dropped from BA after a qualifying GO on it does not block BB's coverage"
else bad "P3e: rc=$G_RC out=$G_OUT"; fi

# ... and a change whose only batch dropped it after a GO is not covered.
fresh_case p3f
rr_genuine "$REC/a1.json" BA cZ 1 GO "$NONE" D-P3FA
rr_genuine "$REC/a2.json" BA cW 2 GO "$NONE" D-P3FB
gate cZ
if uncovered cZ && has "dropped"; then ok "P3f: a change dropped from its only batch's latest round is UNCOVERED (the latest round no longer covers it)"
else bad "P3f: rc=$G_RC out=$G_OUT"; fi
# a backfilled historical NO-GO on the change blocks a live GO elsewhere.
fresh_case p3g
echo "# genuine historical notes" > "$REC/notes.md"
printf '%s\n' '{"review_id":"R-BFQ","batch_id":"B-HIST","round":1,"verdict":"NO-GO","source_evidence":"notes.md","model_tier":"opus","effort":"xhigh","change_ids":["cQ"],"findings":[{"id":"H1","severity":"BLOCKING"}]}' > "$CASE/bf.json"
python3 "$RR_TOOL" backfill --input "$CASE/bf.json" --out "$REC/bf.json" >/dev/null 2>&1
rr_genuine "$REC/live.json" B-LIVE cQ 1 GO "$NONE" D-P3G
gate cQ
if uncovered cQ && has "B-HIST"; then ok "P3g: a backfilled historical NO-GO on cQ blocks a live GO in another batch"
else bad "P3g: rc=$G_RC out=$G_OUT"; fi

# a backfilled historical zero-finding GO is neutral: it neither covers nor
# blocks a live GO elsewhere (11.4.201(1) false-refusal guard).
fresh_case p3h
echo "# genuine historical notes" > "$REC/notes.md"
printf '%s\n' '{"review_id":"R-BFH","batch_id":"B-HIST","round":1,"verdict":"GO","source_evidence":"notes.md","model_tier":"opus","effort":"xhigh","change_ids":["cH"],"findings":[]}' > "$CASE/bf.json"
python3 "$RR_TOOL" backfill --input "$CASE/bf.json" --out "$REC/bf.json" >/dev/null 2>&1
rr_genuine "$REC/live.json" B-LIVE cH 1 GO "$NONE" D-P3H
gate cH
if covered cH; then ok "P3h (negative control): a backfilled historical zero-finding GO does not block a live GO elsewhere"
else bad "P3h: rc=$G_RC out=$G_OUT"; fi

# --- P2/m4: ledger events -----------------------------------------------------
for evset in "dispatched in-flight crashed" "dispatched in-flight" "dispatched failed complete" "complete"; do
  fresh_case "led_$(printf '%s' "$evset" | tr ' ' '_')"
  RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-LED c-led 1 GO "$NONE" D-LED
  RR_LEDGER_EVENTS="$evset" rr_ledger_row D-LED opus xhigh
  gate c-led
  if uncovered c-led && has "ledger"; then ok "m4: dispatch ledger events [$evset] never authenticate a reviewer"
  else bad "m4 [$evset]: rc=$G_RC out=$G_OUT"; fi
done
fresh_case led_ok
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-LEDOK c-ledok 1 GO "$NONE" D-LEDOK
RR_LEDGER_EVENTS="dispatched in-flight complete" rr_ledger_row D-LEDOK opus xhigh
gate c-ledok
if covered c-ledok; then ok "m4 (negative control): dispatched -> in-flight -> complete authenticates"
else bad "m4-n: rc=$G_RC out=$G_OUT"; fi
# label injection: a row carrying two labels (first one forged) is ambiguous.
fresh_case led_inj
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-INJ c-inj 1 GO "$NONE" D-INJ
python3 - "$RR_LEDGER" <<'PY'
import json, sys
desc = "(T1/main - claude5 - opus - xhigh) note (T1/main - claude5 - sonnet - low) item=ATM-1041"
with open(sys.argv[1], "a") as fh:
    for ev in ("dispatched", "complete"):
        fh.write(json.dumps({"event": ev, "key": "D-INJ", "description": desc}) + "\n")
PY
gate c-inj
if uncovered c-inj && has "label"; then ok "m4: a ledger row carrying more than one 11.4.182 label is refused (ambiguous)"
else bad "m4-inj: rc=$G_RC out=$G_OUT"; fi
# every row of the dispatch must name the designated model/effort.
fresh_case led_mix
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-MIX c-mix 1 GO "$NONE" D-MIX
RR_LEDGER_EVENTS="dispatched" rr_ledger_row D-MIX opus high
RR_LEDGER_EVENTS="complete" rr_ledger_row D-MIX opus xhigh
gate c-mix
if uncovered c-mix && has "label"; then ok "m4: a dispatch whose dispatched row names opus-high is not rescued by an opus-xhigh complete row"
else bad "m4-mix: rc=$G_RC out=$G_OUT"; fi

# --- N4: precheck from another batch ------------------------------------------
fresh_case n4
RR_PRECHECK_BATCH=B-OTHER rr_genuine "$REC/r1.json" B-N4 c-n4 1 GO "$NONE" D-N4
gate c-n4
if [ "$RR_RC" -eq 0 ] && uncovered c-n4 && has "precheck belongs"; then ok "N4: a precheck archived for another batch never qualifies"
else bad "N4: rc_record=$RR_RC rc=$G_RC out=$G_OUT"; fi

# --- N11: gate-side producer == reviewer --------------------------------------
fresh_case n11
rr_genuine "$REC/r1.json" B-N11 c-n11 1 GO "$NONE" D-N11
rehash "$REC/r1.json" 'd["producer_id"]="D-N11"'
gate c-n11
if uncovered c-n11 && has "self-certification"; then ok "N11: a record whose producer identity equals the reviewer dispatch is refused by gate"
else bad "N11: rc=$G_RC out=$G_OUT"; fi

# --- m3: record copies must equal the reviewer evidence (N6, N12) ------------
fresh_case n6
rr_genuine "$REC/r1.json" B-N6 c-n6 1 GO "$NONE" D-N6
rehash "$REC/r1.json" 'd["findings"]=[{"id":"FX","severity":"NIT","class":"judgment","finding_layer":"process-doc"}]'
gate c-n6
if uncovered c-n6 && has "disagree"; then ok "N6: a record whose findings/layers differ from the reviewer evidence is refused"
else bad "N6: rc=$G_RC out=$G_OUT"; fi
fresh_case n12
rr_genuine "$REC/r1.json" B-N12 c-n12 1 GO "$NONE" D-N12
rehash "$REC/r1.json" 'd["effort"]="?"; d["effort_capability_gap"]=True'
gate c-n12
if uncovered c-n12 && has "disagree"; then ok "N12: a record whose effort differs from the reviewer evidence is refused"
else bad "N12: rc=$G_RC out=$G_OUT"; fi

# --- T: independence tier rated against the PRODUCER uid (F3, N1, N2) --------
if [ "$(id -u)" -eq 0 ]; then
  echo "NOTE: running as root -- tier cases SKIPPED (os modes cannot bound root)"
elif ! NOBODY=$(python3 -c 'import pwd; print(pwd.getpwnam("nobody").pw_uid)' 2>/dev/null); then
  echo "NOTE: no 'nobody' account on this host -- tier cases SKIPPED (no second uid to stand in for a producer)"
else
  ME=$(id -u)
  T="$S/tier"; mkdir -p "$T/ro" "$T/open"; chmod 755 "$S" "$T" "$T/ro"
  echo x > "$T/ro/f"; chmod 644 "$T/ro/f"
  echo x > "$T/ro/w"; chmod 666 "$T/ro/w"
  echo x > "$T/open/f"; chmod 644 "$T/open/f"; chmod 777 "$T/open"
  TIER=$(python3 - "$RR_TOOL" "$T" "$NOBODY" "$ME" <<'PY'
import importlib.util, sys
tool, t, nobody, me = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
spec = importlib.util.spec_from_file_location("rr", tool)
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
tier = rr._independence_tier
print(" ".join([
    tier([t + "/ro/f"], nobody),    # foreign-owned, not writable, parents safe
    tier([t + "/ro/w"], nobody),    # mode 666: writable by the producer (N2)
    tier([t + "/open/f"], nobody),  # parent dir 777: producer can replace it (N1)
    tier([t + "/ro/f"], me),        # producer OWNS the evidence
    tier([t + "/ro/f"], None),      # producer unknown
    tier([t + "/ro/f"], 0),         # producer is root
    tier(["/proc/self/cmdline"], me),  # producer-OWNED read-only file in a producer-owned read-only dir
]))
PY
)
  chmod 700 "$T/open"
  if [ "$TIER" = "capability instance instance instance instance instance instance" ]; then
    ok "T: tier vs producer uid -- capability only for producer-foreign, producer-unwritable evidence in producer-unwritable dirs ($TIER)"
  else bad "T: got '$TIER' want 'capability instance instance instance instance instance instance'"; fi
  # control needle for the /proc case: the node really is producer-owned and
  # carries no write bit, as does its directory (so only ownership decides).
  PM=$(python3 -c 'import os; p=os.path.realpath("/proc/self/cmdline"); s=os.stat(p); d=os.stat(os.path.dirname(p)); print(s.st_uid, oct(s.st_mode & 0o222), d.st_uid, oct(d.st_mode & 0o222))')
  if [ "$PM" = "$ME 0o0 $ME 0o0" ]; then ok "T-needle: /proc/<pid>/cmdline and its dir are producer-owned with no write bit ($PM)"
  else bad "T-needle: /proc ownership/mode premise does not hold on this host: $PM"; fi
  # ACL: a POSIX ACL granting the producer write access must defeat capability.
  echo x > "$T/ro/acl"; chmod 644 "$T/ro/acl"
  if command -v setfacl >/dev/null 2>&1 && setfacl -m "u:$NOBODY:rw" "$T/ro/acl" 2>/dev/null; then
    ACLT=$(python3 -c 'import importlib.util,sys; sp=importlib.util.spec_from_file_location("rr",sys.argv[1]); rr=importlib.util.module_from_spec(sp); sp.loader.exec_module(rr); print(rr._independence_tier([sys.argv[2]], int(sys.argv[3])))' "$RR_TOOL" "$T/ro/acl" "$NOBODY")
    ACLC=$(python3 -c 'import importlib.util,sys; sp=importlib.util.spec_from_file_location("rr",sys.argv[1]); rr=importlib.util.module_from_spec(sp); sp.loader.exec_module(rr); print(rr._independence_tier([sys.argv[2]], int(sys.argv[3])))' "$RR_TOOL" "$T/ro/f" "$NOBODY")
    if [ "$ACLT" = "instance" ] && [ "$ACLC" = "capability" ]; then ok "T-ACL: an ACL granting the producer write access defeats capability (control without ACL: capability)"
    else bad "T-ACL: acl=$ACLT control=$ACLC"; fi
  else echo "NOTE: setfacl absent or refused by this filesystem -- T-ACL SKIPPED"; fi
  # CLI: release-tag passes only when the gate is told who the producer is.
  fresh_case tcli
  chmod 755 "$CASE"
  rr_genuine "$REC/r1.json" B-T c-t 1 GO "$NONE" D-T
  chmod -R a-w "$REC" "$RR_LEDGER"; chmod 555 "$CASE"
  gate c-t --seam release-tag; RC_A=$G_RC; OUT_A=$G_OUT
  gate c-t --seam release-tag --producer-uid "$NOBODY"; RC_B=$G_RC; OUT_B=$G_OUT
  gate c-t --seam release-tag --producer-uid "$ME"
  chmod 755 "$CASE"; chmod -R u+w "$REC" "$RR_LEDGER"
  if [ "$RC_A" -eq 1 ] && printf '%s\n' "$OUT_A" | grep -q "achieved instance" \
     && [ "$RC_B" -eq 0 ] && printf '%s\n' "$OUT_B" | grep -q "independence=capability" \
     && uncovered c-t; then
    ok "T-CLI: release-tag refuses with no --producer-uid, passes with a producer uid that cannot write the evidence, refuses when the producer owns it"
  else bad "T-CLI: A rc=$RC_A $OUT_A | B rc=$RC_B $OUT_B | C rc=$G_RC $G_OUT"; fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
