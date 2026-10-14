#!/bin/bash
# test_review_record_gate_authority_r3_regression.sh
#
# T048 restart, independent review ROUND 3, area V3
# (docs/qa/t048_restart_round3_20261008/V3_review_record.md) -- STRUCTURAL
# round (constitution 11.4.276(E)): the defect class "the gate trusts
# record-supplied fields" recurred for the third time (R1-B1, R2-F1, R3-F2),
# so the decision structure was replaced, not patched:
#
#   (1) RECORD AS POINTER. `gate` admits EVERY record under --records before
#       any selection: body_hash, and every selection field (batch_id,
#       change_ids, round, review_base/review_head, verdict, layers,
#       reviewer, source) re-derived from the reviewer's archived evidence.
#       Any record that fails admission -> exit 4 naming it; an archived
#       reviewer verdict that no admitted record points at (a removed or
#       relabelled record) -> exit 4 naming it. Selection and the decision
#       use only evidence-derived fields.                        (R3-F2)
#   (2) CAPABILITY needs THREE distinct principals: neither the declared
#       producer uid NOR the uid running `gate` may own, write or replace
#       (symlink-aware, incl. the directory holding any link) any evidence
#       path; an unknown producer uid is "instance". On a single-uid host the
#       runner owns the evidence, so the answer is always "instance",
#       whatever --producer-uid says.                           (R3-F1, m3)
#   (3) Isolating cases for the round-3 reviewer mutations R3-M3..M12.
#   (4) Minors: duplicate JSON keys refused (m2); byte-identical duplicate
#       records decided independently of filename (m1); records symlinked
#       outside --records refused (m3).
#
# Every CLI case drives the REAL `review_record.py record` / `gate`. The tier
# cases call the real module's own functions in-process on REAL files with
# real owners and modes (root-owned /etc/hostname for the third-principal
# positive control) -- nothing re-implemented (constitution 11.4.276(D)).
# Case labels (R3-xx) are the ids the guard table
# (test_review_record_guard_table.sh) binds each guard to.
#
# Usage : bash test_review_record_gate_authority_r3_regression.sh
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
expect() { # expect LABEL GOT WANT TEXT
  if [ "$2" = "$3" ]; then ok "$1: $4"; else bad "$1: got '$2' want '$3' ($4)"; fi
}

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM
chmod 755 "$S"
RR_WORK="$S/work"; mkdir -p "$RR_WORK"
NONE='[]'
SD='[{"id":"F1","severity":"BLOCKING","finding_layer":"source-defect"}]'
ME=$(id -u)

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
blind()     { [ "$G_RC" -eq 4 ] && has "$1"; }   # exit 4 naming $1

# edit REC_JSON PY_STMT [rehash]: apply PY_STMT to the record dict `d`;
# with a 3rd arg "rehash" recompute body_hash the way an attacker would.
edit() {
  python3 - "$1" "$2" "${3:-}" <<'PY'
import hashlib, json, sys
p, stmt, mode = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
exec(stmt)
if mode == "rehash":
    body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
    d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
}
# tier PRODUCER RUNNER PATH...: the real module's _independence_tier.
tier() {
  python3 - "$RR_TOOL" "$@" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
print(rr._independence_tier(sys.argv[4:], int(sys.argv[2]), runner_uid=int(sys.argv[3])))
PY
}

echo "== V3 round-3 regression: record-as-pointer + three-principal capability =="

# --- control (honest P3): B1 r1 GO, B1 r2 genuine NO-GO, B9 r1 GO for cY ----
p3_case() { # p3_case NAME -> genuine P3 tree in $REC
  fresh_case "$1"
  rr_genuine "$REC/b1r1.json" B1 cY 1 GO "$NONE" "D-$1-A"
  rr_genuine "$REC/b1r2.json" B1 cY 2 NO-GO "$SD" "D-$1-B"
  rr_genuine "$REC/b9r1.json" B9 cY 1 GO "$NONE" "D-$1-C"
}
p3_case ctl
gate cY
if uncovered cY && has "B1"; then ok "R3-CTL: honest P3 -- B1's genuine round-2 NO-GO blocks cY despite B9's GO (rc 1)"
else bad "R3-CTL: rc=$G_RC out=$G_OUT"; fi

# --- R3-F2: one-key edits to the genuine NO-GO record (no rehash) -----------
p3_case e1; edit "$REC/b1r2.json" 'd["change_ids"]=["cOTHER"]'; gate cY
if blind "b1r2.json"; then ok "R3-E1: NO-GO record change_ids edited to [cOTHER] -> exit 4 naming the record (was COVERED by B9)"
else bad "R3-E1: rc=$G_RC out=$G_OUT"; fi
p3_case e2; edit "$REC/b1r2.json" 'd["round"]=0'; gate cY
if blind "b1r2.json"; then ok "R3-E2: NO-GO record round edited to 0 -> exit 4 naming the record"
else bad "R3-E2: rc=$G_RC out=$G_OUT"; fi
p3_case e3; edit "$REC/b1r2.json" 'd["source"]="backfill"; d["verdict"]="GO"; d["findings"]=[]'; gate cY
if blind "b1r2.json"; then ok "R3-E3: NO-GO record relabelled backfill/GO/[] -> exit 4 naming the record"
else bad "R3-E3: rc=$G_RC out=$G_OUT"; fi
fresh_case e4
rr_genuine "$REC/b1r1.json" B1 cY 1 GO "$NONE" D-E4A
rr_genuine "$REC/b1r2.json" B1 cY 2 NO-GO "$SD" D-E4B
edit "$REC/b1r2.json" 'd["round"]=-1'; gate cY
if blind "b1r2.json"; then ok "R3-E4: single batch, NO-GO record round edited to -1 -> exit 4 (was COVERED by its own round 1)"
else bad "R3-E4: rc=$G_RC out=$G_OUT"; fi

# --- the same edits WITH a recomputed body_hash (selection fields re-derived)
p3_case e5; edit "$REC/b1r2.json" 'd["change_ids"]=["cOTHER"]' rehash; gate cY
if blind "b1r2.json" && has "binding"; then ok "R3-E5: change_ids edit + re-hash -> exit 4 (record copy differs from the reviewer's binding)"
else bad "R3-E5: rc=$G_RC out=$G_OUT"; fi
p3_case e6; edit "$REC/b1r2.json" 'd["round"]=0' rehash; gate cY
if blind "b1r2.json"; then ok "R3-E6: round edit + re-hash -> exit 4 (round re-derived from evidence)"
else bad "R3-E6: rc=$G_RC out=$G_OUT"; fi
p3_case e7; edit "$REC/b1r2.json" 'd["source"]="backfill"; d["verdict"]="GO"; d["findings"]=[]' rehash; gate cY
if blind "b1r2.json" && has "live-only"; then ok "R3-E7: relabel to backfill + re-hash keeping the evidence pointer -> exit 4 (a backfill row never carries live evidence)"
else bad "R3-E7: rc=$G_RC out=$G_OUT"; fi
p3_case e8
edit "$REC/b1r2.json" 'd["source"]="backfill"; d["verdict"]="GO"; d["findings"]=[]; [d.pop(k) for k in list(d) if k.startswith(("verdict_evidence","precheck_evidence","reviewer_"))]' rehash
gate cY
if blind "orphan" && has "verdict-evidence"; then ok "R3-E8: relabel to backfill + re-hash + pointer dropped -> exit 4 (the NO-GO archive is now orphaned)"
else bad "R3-E8: rc=$G_RC out=$G_OUT"; fi
p3_case e9; rm "$REC/b1r2.json"; gate cY
if blind "orphan"; then ok "R3-E9: deleting the NO-GO record but not its archived verdict -> exit 4 (orphaned reviewer evidence)"
else bad "R3-E9: rc=$G_RC out=$G_OUT"; fi
# admitted boundary (11.4.6): deleting the record AND its archive leaves no trace.
p3_case e10
EV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict_evidence"])' "$REC/b1r2.json")
rm "$REC/b1r2.json" "$REC/$EV"; gate cY
if covered cY; then ok "R3-E10 (documented boundary): deleting record + archive is undetectable without a 11.4.268 chain -- COVERED, as the docstring states"
else bad "R3-E10: boundary claim no longer matches behaviour (update the docstring): rc=$G_RC out=$G_OUT"; fi
# every failing record is named, not just the first
p3_case e11
edit "$REC/b1r2.json" 'd["round"]=0'; edit "$REC/b9r1.json" 'd["round"]=0'; gate cY
if blind "b1r2.json" && has "b9r1.json"; then ok "R3-E11: every inadmissible record is named on refusal (both edited records listed)"
else bad "R3-E11: rc=$G_RC out=$G_OUT"; fi
# the decision ignores the queried change: an edit elsewhere still blinds the run
p3_case e12; edit "$REC/b9r1.json" 'd["change_ids"]=["cZZ"]'; gate cQUERY
if blind "b9r1.json"; then ok "R3-E12: admission runs before selection -- a tampered record blinds the gate even for an unrelated change"
else bad "R3-E12: rc=$G_RC out=$G_OUT"; fi

# --- R3-M10: a record whose round is boolean true -------------------------
fresh_case m10
rr_genuine "$REC/r1.json" B-M10 c-m10 1 GO "$NONE" D-M10
edit "$REC/r1.json" 'd["round"]=True' rehash; gate c-m10
if blind "non-integer round"; then ok "R3-M10: a record with round=true is refused at collection (exit 4, 'non-integer round')"
else bad "R3-M10: rc=$G_RC out=$G_OUT"; fi

# --- R3-M9: batch-declared review_base differs from the reviewer's ---------
fresh_case m9
RR_BATCH_BASE=6666666666666666666666666666666666666666 rr_genuine "$REC/r1.json" B-M9 c-m9 1 GO "$NONE" D-M9
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r1.json" ] && grep -q "review_base" "$RR_WORK/r1/record.err"; then
  ok "R3-M9: record refuses a verdict whose review_base differs from the batch's declared base"
else bad "R3-M9: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi

# --- R3-M7 / R3-M11: ledger event rules ------------------------------------
fresh_case m7
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-M7 c-m7 1 GO "$NONE" D-M7
RR_LEDGER_EVENTS="dispatched" rr_ledger_row D-M7 opus xhigh
printf '%s\n' '{"key":"D-M7","description":"(T1/main - claude5 - opus - xhigh) item=ATM-1041"}' >> "$RR_LEDGER"
gate c-m7
if uncovered c-m7 && has "ledger"; then ok "R3-M7: a ledger row with no event never counts as 'complete'"
else bad "R3-M7: rc=$G_RC out=$G_OUT"; fi
fresh_case m11
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-M11 c-m11 1 GO "$NONE" D-M11
RR_LEDGER_EVENTS="dispatched complete in-flight" rr_ledger_row D-M11 opus xhigh
gate c-m11
if uncovered c-m11 && has "latest event"; then ok "R3-M11: dispatched -> complete -> in-flight does not authenticate (the LATEST row must be complete; ATM-858 D1)"
else bad "R3-M11: rc=$G_RC out=$G_OUT"; fi

# --- R3-M3: batch identity 1 (backfill, int) vs "1" (live, str) -----------
fresh_case m3
echo "# genuine historical notes" > "$REC/notes.md"
printf '%s\n' '{"review_id":"R-M3","batch_id":1,"round":1,"verdict":"NO-GO","source_evidence":"notes.md","change_ids":["c-m3"],"findings":[{"id":"H1","severity":"BLOCKING"}]}' > "$CASE/bf.json"
python3 "$RR_TOOL" backfill --input "$CASE/bf.json" --out "$REC/bf.json" >/dev/null 2>&1
rr_genuine "$REC/live.json" 1 c-m3 2 GO "$NONE" D-M3
gate c-m3
if [ "$RR_RC" -eq 0 ] && uncovered c-m3; then ok "R3-M3: backfill batch 1 (int) and live batch \"1\" (str) are different batches -- the historical NO-GO still blocks"
else bad "R3-M3: rc_record=$RR_RC rc=$G_RC out=$G_OUT"; fi

# --- m2: duplicate JSON keys ------------------------------------------------
fresh_case dk
rr_genuine "$REC/r1.json" B-DK c-dk 1 NO-GO "$SD" D-DK
rm -f "$REC/r1.json" "$REC"/*.verdict-evidence "$REC"/*.precheck-evidence
python3 - "$RR_WORK/r1/verdict.json" <<'PY'
import json, sys
p = sys.argv[1]; s = json.dumps(json.load(open(p)))
open(p, "w").write(s[:-1] + ', "verdict": "GO", "findings": []}')
PY
python3 "$RR_TOOL" record --batch "$RR_WORK/r1/batch.json" --round 1 --verdict-file "$RR_WORK/r1/verdict.json" \
  --precheck "$RR_WORK/r1/precheck.json" --tier opus --effort xhigh --producer-id P --out "$REC/r1.json" >/dev/null 2>"$CASE/dk.err"
RC=$?
if [ "$RC" -eq 2 ] && [ ! -f "$REC/r1.json" ] && grep -q "duplicate" "$CASE/dk.err"; then ok "R3-DK1: a verdict file with a duplicate 'verdict' key is refused by record (2)"
else bad "R3-DK1: rc=$RC err=$(cat "$CASE/dk.err")"; fi
# gate side: a duplicate-key archive (swapped in with a correct hash) is inadmissible.
fresh_case dk2
rr_genuine "$REC/r1.json" B-DK2 c-dk2 1 GO "$NONE" D-DK2
python3 - "$REC/r1.json" <<'PY'
import hashlib, json, os, sys
p = sys.argv[1]; d = json.load(open(p)); base = os.path.dirname(p)
old = os.path.join(base, d["verdict_evidence"])
s = json.dumps(json.load(open(old)))
raw = (s[:-1] + ', "verdict": "GO"}').encode()
os.remove(old)
sha = hashlib.sha256(raw).hexdigest()
open(os.path.join(base, sha + ".verdict-evidence"), "wb").write(raw)
d["verdict_evidence"] = sha + ".verdict-evidence"; d["verdict_evidence_sha256"] = sha
body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
gate c-dk2
if blind "r1.json" && has "parse"; then ok "R3-DK2: archived reviewer evidence with a duplicate key is inadmissible (exit 4)"
else bad "R3-DK2: rc=$G_RC out=$G_OUT"; fi

# --- m1 / R3-M12: byte-identical duplicates are decided by content ----------
fresh_case dup
rr_genuine "$REC/a.json" B-DUP c-dup 1 GO "$NONE" D-DUP
mkdir -p "$REC/0" "$REC/z"
cp "$REC/a.json" "$REC/0/a.json"; gate c-dup; RC_A=$G_RC; OUT_A=$G_OUT
rm -rf "$REC/0"; cp "$REC/a.json" "$REC/z/a.json"; gate c-dup
if [ "$RC_A" -eq 4 ] && printf '%s\n' "$OUT_A" | grep -q "0/a.json" && blind "z/a.json"; then
  ok "R3-M12a: an identical copy without its evidence is refused (exit 4) whether it sorts first (0/) or last (z/)"
else bad "R3-M12a: A rc=$RC_A $OUT_A | B rc=$G_RC $G_OUT"; fi
cp "$REC"/*.verdict-evidence "$REC"/*.precheck-evidence "$REC/z/"
mkdir -p "$REC/0"; cp "$REC/z/"* "$REC/0/"
gate c-dup
if covered c-dup; then ok "R3-M12b: identical copies each carrying their own evidence are one verdict, COVERED"
else bad "R3-M12b: rc=$G_RC out=$G_OUT"; fi

# --- m3: a record symlinked from outside --records -------------------------
fresh_case sym
rr_genuine "$REC/r1.json" B-SYM c-sym 1 GO "$NONE" D-SYM
mkdir -p "$CASE/outside"; mv "$REC/r1.json" "$CASE/outside/r1.json"; ln -s "$CASE/outside/r1.json" "$REC/r1.json"
gate c-sym
if blind "outside --records"; then ok "R3-SYM: a record whose real path lies outside --records is refused (exit 4)"
else bad "R3-SYM: rc=$G_RC out=$G_OUT"; fi

# --- R3-F1: capability on THIS single-uid host is never reachable ---------
if [ "$ME" -eq 0 ]; then
  echo "NOTE: running as root -- tier cases SKIPPED (os modes cannot bound root)"
elif ! NOBODY=$(python3 -c 'import pwd; print(pwd.getpwnam("nobody").pw_uid)' 2>/dev/null) \
     || ! DAEMON=$(python3 -c 'import pwd; print(pwd.getpwnam("daemon").pw_uid)' 2>/dev/null); then
  echo "NOTE: no 'nobody'/'daemon' account -- tier cases SKIPPED (need two non-runner uids)"
else
  fresh_case tcli; chmod 755 "$CASE"
  rr_genuine "$REC/r1.json" B-T c-t 1 GO "$NONE" D-T
  chmod -R a-w "$REC" "$RR_LEDGER"; chmod 555 "$CASE"
  gate c-t --seam release-tag --producer-uid "$NOBODY"; RC_A=$G_RC; OUT_A=$G_OUT
  gate c-t --seam qa-deploy --producer-uid 4000000; RC_B=$G_RC; OUT_B=$G_OUT
  gate c-t --seam manual-qa-handoff --producer-uid "$ME"; RC_C=$G_RC; OUT_C=$G_OUT
  gate c-t --producer-uid "$NOBODY"
  chmod 755 "$CASE"; chmod -R u+w "$REC" "$RR_LEDGER"
  if [ "$RC_A" -eq 1 ] && printf '%s\n' "$OUT_A" | grep -q "achieved instance" \
     && [ "$RC_B" -eq 1 ] && printf '%s\n' "$OUT_B" | grep -q "achieved instance" \
     && [ "$RC_C" -eq 1 ] && printf '%s\n' "$OUT_C" | grep -q "achieved instance" \
     && covered c-t && has "independence=instance"; then
    ok "R3-T1: on a single-uid host a declared producer uid (nobody / unknown 4000000 / own) never yields capability -- every high-blast seam refuses; ordinary seam reports instance"
  else bad "R3-T1: A rc=$RC_A $OUT_A | B rc=$RC_B $OUT_B | C rc=$RC_C $OUT_C | ord rc=$G_RC $G_OUT"; fi

  # in-process, real ownership: /etc/hostname is root-owned in root-owned dirs.
  T="$S/tier"; mkdir -p "$T/d755" "$T/w777"; chmod 755 "$T" "$T/d755"
  echo x > "$T/d755/f"; chmod 644 "$T/d755/f"
  echo x > "$T/d755/g"; chmod 664 "$T/d755/g"
  ln -s /etc/hostname "$T/d755/link"
  ln -s /etc/hostname "$T/w777/link"; chmod 777 "$T/w777"
  R1=$(tier "$NOBODY" "$DAEMON" /etc/hostname)
  R2=$(tier 4000000 "$DAEMON" /etc/hostname)
  R3=$(tier "$NOBODY" "$ME" /etc/hostname "$T/d755/f")
  R4=$(tier "$ME" "$NOBODY" "$T/d755/f")
  R5=$(tier "$NOBODY" "$NOBODY" /etc/hostname)
  R6=$(tier "$NOBODY" 0 /etc/hostname)
  R7=$(tier "$NOBODY" "$DAEMON" "$T/d755/f")
  R8=$(tier "$NOBODY" 4000000 "$T/d755/g")
  R9=$(tier "$NOBODY" "$DAEMON" "$T/w777/link")
  R10=$(tier "$NOBODY" "$DAEMON" "$T/d755/link")
  chmod 700 "$T/w777"
  expect R3-T2 "$R1" capability "positive control -- producer nobody, runner daemon, root-owned evidence -> capability (three real principals)"
  expect R3-T3 "$R2" "instance" "an unknown producer uid (4000000) never raises the tier -> instance"
  expect R3-T4 "$R3" "instance" "evidence owned by the uid running gate -> instance (the runner could be the producer)"
  expect R3-T5 "$R4" "instance" "evidence owned by the declared producer -> instance"
  expect R3-T6 "$R5" "instance" "producer uid == runner uid -> instance"
  expect R3-T7 "$R6" "instance" "a root runner can write everything -> instance"
  expect R3-T8 "$R7" "capability" "evidence owned by a THIRD uid ($ME), unwritable by producer and runner -> capability"
  expect R3-T9 "$R8" "instance" "runner of unknown group membership + group-writable evidence -> instance (conservative)"
  expect R3-T10 "$R9" "instance" "a symlink held in a world-writable non-sticky directory can be replaced -> instance"
  expect R3-T11 "$R10" "capability" "(control) the same symlink in a 755 third-party directory -> capability"

  # supplementary group membership counts (R3-M4)
  SUPG=$(python3 -c 'import os; g=[x for x in os.getgroups() if x != os.getgid()]; print(g[0] if g else "")')
  if [ -n "$SUPG" ]; then
    echo x > "$T/sg"; chgrp "$SUPG" "$T/sg"; chmod 064 "$T/sg"
    SG=$(python3 - "$RR_TOOL" "$T/sg" "$ME" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
uid = int(sys.argv[3])
print(rr._writable_by(os.stat(sys.argv[2]), sys.argv[2], uid, rr._uid_gids(uid)))
PY
)
    chmod 644 "$T/sg"
    expect R3-T12 "$SG" "True" "write access through a SUPPLEMENTARY group (gid $SUPG) is detected"
  else echo "NOTE: this uid has no supplementary group -- R3-T12 SKIPPED"; fi
fi

# --- R3-M8: the reported tier is the weakest achieved ----------------------
AG=$(python3 - "$RR_TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
print(rr._aggregate_tier(["capability", "instance"]), rr._aggregate_tier(["capability", "capability"]))
PY
)
expect R3-M8 "$AG" "instance capability" "the COVERED line reports the WEAKEST tier achieved across covering batches"

# =============================================================================
# Isolating cases for the remaining guards (guard table, 11.4.276(D)): each
# case below fails if ITS guard alone is removed -- most by asserting the
# guard's own refusal message, so a later guard catching the same input with
# a different reason does not mask the removal.
# =============================================================================

# reforge_ev REC_JSON PY_STMT_ON_RAW: replace the record's archived verdict with
# raw bytes `raw` computed by PY_STMT (given `v`, the parsed original), remove
# the original archive, re-point and re-hash the record (a complete forgery).
reforge_ev() {
  python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
p, stmt = sys.argv[1], sys.argv[2]
d = json.load(open(p)); base = os.path.dirname(p)
old = os.path.join(base, d["verdict_evidence"])
v = json.load(open(old)); raw = None
exec(stmt)
os.remove(old)
sha = hashlib.sha256(raw).hexdigest()
open(os.path.join(base, sha + ".verdict-evidence"), "wb").write(raw)
d["verdict_evidence"] = sha + ".verdict-evidence"; d["verdict_evidence_sha256"] = sha
body = {k: x for k, x in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
}

# --- collection guards ------------------------------------------------------
fresh_case c1; printf '{"batch_id": ' > "$REC/bad.json"; gate cC
if blind "bad.json" && has "cannot read/parse"; then ok "R3-C1: a record file that does not parse is named (exit 4, parse failure)"
else bad "R3-C1: rc=$G_RC out=$G_OUT"; fi
fresh_case c2; printf '[]\n' > "$REC/arr.json"; gate cC
if blind "arr.json" && has "not a JSON object"; then ok "R3-C2: a record that is not a JSON object is named (exit 4)"
else bad "R3-C2: rc=$G_RC out=$G_OUT"; fi
fresh_case c3; printf '{"batch_id":"B","verdict":"GO"}\n' > "$REC/part.json"; gate cC
if blind "part.json" && has "missing required field"; then ok "R3-C3: a record missing required fields is named (exit 4)"
else bad "R3-C3: rc=$G_RC out=$G_OUT"; fi

# --- admission guards ------------------------------------------------------
fresh_case awf
rr_genuine "$REC/r1.json" B-AWF c-awf 1 GO "$NONE" D-AWF
reforge_ev "$REC/r1.json" 'v["verdict"] = "MAYBE"; raw = json.dumps(v).encode()'
gate c-awf
if blind "r1.json" && has "no well-formed verdict"; then ok "R3-A1: archived evidence whose verdict is outside {GO, NO-GO} is inadmissible (named reason)"
else bad "R3-A1: rc=$G_RC out=$G_OUT"; fi
fresh_case arv
rr_genuine "$REC/r1.json" B-ARV c-arv 1 GO "$NONE" D-ARV
reforge_ev "$REC/r1.json" 'v["reviewer"] = "someone"; raw = json.dumps(v).encode()'
gate c-arv
if blind "r1.json" && has "'reviewer' must be a JSON object"; then ok "R3-A2: archived evidence with a malformed reviewer block is inadmissible (named reason)"
else bad "R3-A2: rc=$G_RC out=$G_OUT"; fi
fresh_case aobj
rr_genuine "$REC/r1.json" B-AOBJ c-aobj 1 GO "$NONE" D-AOBJ
reforge_ev "$REC/r1.json" 'raw = b"[1, 2]"'
gate c-aobj
if blind "r1.json" && has "does not parse as a JSON object"; then ok "R3-A3: archived evidence that is a JSON array is inadmissible (named reason)"
else bad "R3-A3: rc=$G_RC out=$G_OUT"; fi
# placeholder citation: a REAL file literally named UNKNOWN with the right hash
fresh_case aph
rr_genuine "$REC/r1.json" B-APH c-aph 1 GO "$NONE" D-APH
python3 - "$REC/r1.json" <<'PY'
import hashlib, json, os, sys
p = sys.argv[1]; d = json.load(open(p)); base = os.path.dirname(p)
old = os.path.join(base, d["verdict_evidence"]); raw = open(old, "rb").read(); os.remove(old)
open(os.path.join(base, "UNKNOWN"), "wb").write(raw)
d["verdict_evidence"] = "UNKNOWN"
body = {k: x for k, x in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
gate c-aph
if blind "r1.json" && has "verdict_evidence missing"; then ok "R3-A4: an evidence citation reading 'UNKNOWN' is a placeholder, never a file -- even when a matching file of that name exists"
else bad "R3-A4: rc=$G_RC out=$G_OUT"; fi
# a FIFO planted as the evidence must not hang the gate
fresh_case fifo
rr_genuine "$REC/r1.json" B-FIFO c-fifo 1 GO "$NONE" D-FIFO
EVF=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict_evidence"])' "$REC/r1.json")
rm -f "$REC/$EVF"; mkfifo "$REC/$EVF"
G_OUT=$(timeout 20 python3 "$RR_TOOL" gate --change c-fifo --records "$REC" --dispatch-ledger "$RR_LEDGER" 2>&1); G_RC=$?
if blind "r1.json" && has "verdict_evidence missing"; then ok "R3-A5: a FIFO planted as evidence is refused promptly (exit 4), never a hang"
else bad "R3-A5: rc=$G_RC (124 = hung) out=$G_OUT"; fi
rm -f "$REC/$EVF"
# backfill admission
fresh_case bfa
echo "# genuine historical notes" > "$REC/notes.md"
printf '%s\n' '{"review_id":"R-BFA","batch_id":"B-BFA","round":1,"verdict":"NO-GO","source_evidence":"notes.md","change_ids":["c-bfa"],"findings":[{"id":"H1","severity":"BLOCKING"}]}' > "$CASE/bf.json"
python3 "$RR_TOOL" backfill --input "$CASE/bf.json" --out "$REC/bf.json" >/dev/null 2>&1
cp "$REC/bf.json" "$CASE/bf.pristine"
edit "$REC/bf.json" 'd["verdict"]="GO"; d["findings"]=[]'; gate c-bfa
if blind "bf.json" && has "body_hash"; then ok "R3-B1: an edited backfill row (no re-hash) is inadmissible (exit 4, body_hash)"
else bad "R3-B1: rc=$G_RC out=$G_OUT"; fi
cp "$CASE/bf.pristine" "$REC/bf.json"
edit "$REC/bf.json" 'd["change_ids"]="c-bfa"' rehash; gate c-bfa
if blind "bf.json" && has "backfill change_ids must be"; then ok "R3-B2: a backfill row whose change_ids is not a list (nor UNKNOWN) is inadmissible, never silently dropped from the listing"
else bad "R3-B2: rc=$G_RC out=$G_OUT"; fi

# --- ledger + qualification guards -----------------------------------------
fresh_case l1
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-L1 c-l1 1 GO "$NONE" D-L1
RR_LEDGER_EVENTS="dispatched complete" rr_ledger_row D-OTHER opus xhigh
gate c-l1
if uncovered c-l1 && has "has no dispatch-ledger row"; then ok "R3-L1: a reviewer dispatch absent from a non-empty ledger is refused (named: no dispatch-ledger row)"
else bad "R3-L1: rc=$G_RC out=$G_OUT"; fi
fresh_case q1
rr_genuine "$REC/r1.json" B-Q1 c-q1 1 GO "$NONE" D-Q1
rm -f "$REC"/*.precheck-evidence; gate c-q1
if uncovered c-q1 && has "precheck_evidence missing"; then ok "R3-Q1: a record whose archived precheck is gone is not coverage (named reason)"
else bad "R3-Q1: rc=$G_RC out=$G_OUT"; fi

# --- gate CLI guards --------------------------------------------------------
fresh_case g
G_OUT=$(python3 "$RR_TOOL" gate --change ' , ' --records "$REC" 2>&1); G_RC=$?
if [ "$G_RC" -eq 2 ] && has "at least one change id"; then ok "R3-G1: --change naming no change id is a usage error (2)"
else bad "R3-G1: rc=$G_RC out=$G_OUT"; fi
G_OUT=$(python3 "$RR_TOOL" gate --change cG --records "$REC" --round-budget 9 2>&1); G_RC=$?
if [ "$G_RC" -eq 2 ] && has "round-budget must be within"; then ok "R3-G2: gate --round-budget outside 5..7 is a usage error (2)"
else bad "R3-G2: rc=$G_RC out=$G_OUT"; fi
G_OUT=$(python3 "$RR_TOOL" gate --change cG --records "$CASE/does-not-exist" 2>&1); G_RC=$?
if [ "$G_RC" -eq 4 ] && has "not a readable directory"; then ok "R3-G3: a missing --records directory is BLIND (4), never 'uncovered'"
else bad "R3-G3: rc=$G_RC out=$G_OUT"; fi
gate cG
if uncovered cG && has "no record lists this change"; then ok "R3-G4: a change no record lists is UNCOVERED (rc 1), never COVERED by an empty set"
else bad "R3-G4: rc=$G_RC out=$G_OUT"; fi

# --- binding / reviewer validators (record side) ----------------------------
fresh_case bd
printf '%s\n' '{"round":1,"verdict":"GO","findings":[],"batch_id":"B-BD1","change_ids":["c-bd1"],"review_head":"2222222","reviewer":{"dispatch_id":"D-BD1","model":"opus","effort":"xhigh"}}' > "$CASE/v_bd1.json"
RR_VERDICT_FROM="$CASE/v_bd1.json" rr_genuine "$REC/r1.json" B-BD1 c-bd1 1 GO "$NONE" D-BD1
if [ "$RR_RC" -eq 2 ] && grep -q "missing field(s): review_base" "$RR_WORK/r1/record.err"; then ok "R3-BD1: a binding missing a field is named as missing (2)"
else bad "R3-BD1: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi
RR_V_BATCH=' B-BD2 ' rr_genuine "$REC/r2.json" B-BD2 c-bd2 1 GO "$NONE" D-BD2
if [ "$RR_RC" -eq 2 ] && grep -q "batch_id must be a non-empty, unpadded string" "$RR_WORK/r2/record.err"; then ok "R3-BD2: a padded binding batch_id is a usage error (2)"
else bad "R3-BD2: rc=$RR_RC err=$(cat "$RR_WORK/r2/record.err")"; fi
RR_V_CHANGES='[]' rr_genuine "$REC/r3.json" B-BD3 c-bd3 1 GO "$NONE" D-BD3
if [ "$RR_RC" -eq 2 ] && grep -q "change_ids must be a non-empty list" "$RR_WORK/r3/record.err"; then ok "R3-BD3: an empty binding change_ids is a usage error (2)"
else bad "R3-BD3: rc=$RR_RC err=$(cat "$RR_WORK/r3/record.err")"; fi
RR_CHANGES='["c-bd4","c-bd4"]' rr_genuine "$REC/r4.json" B-BD4 c-bd4 1 GO "$NONE" D-BD4
if [ "$RR_RC" -eq 2 ] && grep -q "lists a change twice" "$RR_WORK/r4/record.err"; then ok "R3-BD4: a binding listing a change twice is a usage error (2)"
else bad "R3-BD4: rc=$RR_RC err=$(cat "$RR_WORK/r4/record.err")"; fi
mkdir -p "$RR_WORK/rv1"
printf '{"batch_id":"B-RV1","changes":["c-rv1"]}\n' > "$RR_WORK/rv1/batch.json"
printf '{"round":1,"verdict":"GO","findings":[],"reviewer":"x"}\n' > "$RR_WORK/rv1/v.json"
python3 "$RR_TOOL" record --batch "$RR_WORK/rv1/batch.json" --round 1 --verdict-file "$RR_WORK/rv1/v.json" \
  --tier opus --effort xhigh --out "$REC/rv1.json" >/dev/null 2>"$RR_WORK/rv1/err"; RC=$?
if [ "$RC" -eq 2 ] && grep -q "'reviewer' must be a JSON object" "$RR_WORK/rv1/err"; then ok "R3-RV1: a non-object reviewer block is a usage error (2)"
else bad "R3-RV1: rc=$RC err=$(cat "$RR_WORK/rv1/err")"; fi
printf '{"round":1,"verdict":"GO","findings":[],"reviewer":{"dispatch_id":" ","model":"opus","effort":"xhigh"}}\n' > "$RR_WORK/rv1/v2.json"
python3 "$RR_TOOL" record --batch "$RR_WORK/rv1/batch.json" --round 1 --verdict-file "$RR_WORK/rv1/v2.json" \
  --tier opus --effort xhigh --out "$REC/rv2.json" >/dev/null 2>"$RR_WORK/rv1/err2"; RC=$?
if [ "$RC" -eq 2 ] && [ ! -f "$REC/rv2.json" ] && grep -q "reviewer.dispatch_id' must be a non-empty string" "$RR_WORK/rv1/err2"; then ok "R3-RV2: a blank reviewer dispatch_id is a usage error (2)"
else bad "R3-RV2: rc=$RC err=$(cat "$RR_WORK/rv1/err2")"; fi
# a reviewer-less verdict that carries a binding is held to it at record time
RR_NO_REVIEWER=1 RR_V_CHANGES='["c-other"]' rr_genuine "$REC/r5.json" B-BD5 c-bd5 1 GO "$NONE" D-BD5
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r5.json" ] && grep -q "bound to" "$RR_WORK/r5/record.err"; then ok "R3-BD5: a reviewer-less verdict carrying a binding for other changes is refused (1)"
else bad "R3-BD5: rc=$RR_RC err=$(cat "$RR_WORK/r5/record.err")"; fi

# --- unit probes (11.4.27(A): synthetic stat on real paths) ----------------
# The independence-tier helpers need ownership layouts a single-uid host
# cannot create (a file owned by X in a directory X neither owns nor can
# write). These unit cases call the REAL functions with stat records built
# from a real file's stat, ownership/mode fields replaced -- unit level only.
UNIT=$(python3 - "$RR_TOOL" "$S" <<'PY'
import importlib.util, os, stat, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
real = os.path.join(sys.argv[2], "unit_probe")
open(real, "w").write("x")
base = os.stat(real)
def st(uid, gid, mode):
    f = list(base); f[0] = mode; f[4] = uid; f[5] = gid
    return os.stat_result(f)
REG, DIR = stat.S_IFREG, stat.S_IFDIR
X, Y = 4242, 4343   # principal X, unrelated owner Y
out = []
out.append(rr._writable_by(st(Y, Y, REG | 0o444), real, 0, {0}))            # U-ROOT
out.append(rr._writable_by(st(X, X, REG | 0o600), real, X, {X}))            # U-OWNER-BIT
out.append(rr._writable_by(st(Y, Y, REG | 0o602), real, X, {X}))            # U-OTHER-BIT
out.append(rr._writable_by(st(Y, 77, REG | 0o464), real, X, {X, 77}))       # U-GROUP-BIT
out.append(rr._writable_by(st(Y, 77, REG | 0o464), real, X, {X}))           # control: not in group
def chain(leaf, d):
    return (real, leaf, {"/": d}, [("/", leaf)])
out.append(rr._principal_can_replace(chain(st(X, X, REG | 0o444), st(Y, Y, DIR | 0o755)), X, {X}))  # U-LEAF-OWNER
out.append(rr._principal_can_replace(chain(st(Y, Y, REG | 0o666), st(Y, Y, DIR | 0o755)), X, {X}))  # U-LEAF-WRITABLE
out.append(rr._principal_can_replace(chain(st(Y, Y, REG | 0o444), st(X, X, DIR | 0o555)), X, {X}))  # U-DIR-OWNER
out.append(rr._principal_can_replace(chain(st(Y, Y, REG | 0o444), st(Y, Y, DIR | 0o777)), X, {X}))  # U-DIR-WRITABLE
out.append(rr._principal_can_replace(chain(st(Y, Y, REG | 0o444), st(Y, Y, DIR | 0o1777)), X, {X})) # control: sticky, foreign entry
out.append(rr._principal_can_replace(chain(st(Y, Y, REG | 0o444), st(Y, Y, DIR | 0o755)), X, {X}))  # control: nothing
try:
    out.append(rr._independence_tier([None, "/etc/hostname"], 65534, runner_uid=2))  # U-NONE-PATH
except Exception as exc:
    out.append("raised:%s" % type(exc).__name__)
print(" ".join(str(o) for o in out))
PY
)
# shellcheck disable=SC2086 # word-splitting the probe results is intended
set -- $UNIT
expect R3-U-ROOT "${1:-}" True "a root principal can write any inode"
expect R3-U-OWNER-BIT "${2:-}" True "the owner write bit grants write"
expect R3-U-OTHER-BIT "${3:-}" True "the other write bit grants write"
expect R3-U-GROUP-BIT "${4:-}" True "the group write bit grants write to a group member"
expect R3-U-GROUP-CTL "${5:-}" False "control: the group write bit does not grant write to a non-member"
expect R3-U-LEAF-OWNER "${6:-}" True "owning the evidence file (even read-only, in a foreign dir) can replace it"
expect R3-U-LEAF-WRITABLE "${7:-}" True "a writable evidence file can be replaced"
expect R3-U-DIR-OWNER "${8:-}" True "owning a directory on the chain can replace the evidence"
expect R3-U-DIR-WRITABLE "${9:-}" True "a writable non-sticky directory on the chain can replace the evidence"
expect R3-U-STICKY-CTL "${10:-}" False "control: a sticky directory protects an entry the principal does not own"
expect R3-U-CLEAN-CTL "${11:-}" False "control: no ownership/write path -> cannot replace"
expect R3-U-NONE-PATH "${12:-}" instance "a missing evidence path yields instance, never a crash or capability"

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
