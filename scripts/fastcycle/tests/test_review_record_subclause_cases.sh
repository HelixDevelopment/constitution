#!/bin/bash
# test_review_record_subclause_cases.sh
#
# T048 restart, V3 round 4, R4-F3 (constitution 11.4.276(D), 11.4.194(6)(d)):
# ISOLATING cases for guard sub-clauses that the mechanical sweep
# (test_review_record_subclause_sweep.sh) found SURVIVING every earlier
# suite. Each case below is named after the sub-clause id it isolates
# (<GUARD-ID>#<n>, as printed by lib/review_record_guard_analyzer.py list)
# and holds every OTHER condition of that guard, so flipping only that
# sub-clause changes the observed outcome. The kill ledger records which
# check actually lost its PASS on each mutant -- the label here is a
# pointer for humans, the ledger is the evidence.
#
# Every case drives the REAL `review_record.py record` / `backfill` / `gate`
# CLI (or, where only an internal function can reach the sub-clause, the real
# module's own function in-process on real files). Nothing re-implements
# guarded logic (constitution 11.4.276(D)).
#
# Usage : bash test_review_record_subclause_cases.sh
# Exit  : 0 all checks pass; 1 any failed; 2 scratch dir unusable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
# shellcheck disable=SC2034 # RR_TOOL is consumed by the sourced lib/review_record_genuine.sh
RR_TOOL="$FC/review/review_record.py"
# shellcheck source=lib/review_record_genuine.sh
# shellcheck disable=SC1091 # sourced helper is linted on its own
. "$HERE/lib/review_record_genuine.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1: $4"; else bad "$1: got '$2' want '$3' ($4)"; fi; }

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+rwx "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM
chmod 755 "$S"
RR_WORK="$S/work"; mkdir -p "$RR_WORK"
NONE='[]'

fresh_case() {
  CASE="$S/$1"; mkdir -p "$CASE/records"
  RR_LEDGER="$CASE/ledger.jsonl"; : > "$RR_LEDGER"
  REC="$CASE/records"
}
gate() {
  G_OUT=$(python3 "$RR_TOOL" gate --change "$1" --records "$REC" --dispatch-ledger "$RR_LEDGER" "${@:2}" 2>&1)
  G_RC=$?
}
covered()   { [ "$G_RC" -eq 0 ] && printf '%s\n' "$G_OUT" | grep -q "^COVERED $1 "; }
uncovered() { [ "$G_RC" -eq 1 ] && printf '%s\n' "$G_OUT" | grep -q "^UNCOVERED $1"; }
has()       { printf '%s\n' "$G_OUT" | grep -q -- "$1"; }
blind()     { [ "$G_RC" -eq 4 ] && has "$1"; }
edit() { # edit REC_JSON PY_STMT [rehash]
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
reforge_ev() { # reforge_ev REC_JSON PY_STMT: rewrite the archived verdict (v -> raw), re-point, re-hash
  python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
p, stmt = sys.argv[1], sys.argv[2]
d = json.load(open(p)); base = os.path.dirname(p)
old = os.path.join(base, d["verdict_evidence"])
v = json.load(open(old)); raw = None
exec(stmt)
if raw is None:
    raw = json.dumps(v).encode()
os.remove(old)
sha = hashlib.sha256(raw).hexdigest()
open(os.path.join(base, sha + ".verdict-evidence"), "wb").write(raw)
d["verdict_evidence"] = sha + ".verdict-evidence"; d["verdict_evidence_sha256"] = sha
body = {k: x for k, x in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
}
backfill() { # backfill OUT_JSON SPEC_JSON -> the REAL `backfill` CLI
  printf '%s\n' "$2" > "$CASE/bf_spec.json"
  python3 "$RR_TOOL" backfill --input "$CASE/bf_spec.json" --out "$1" >/dev/null 2>"$CASE/bf.err"
}
# rec_cli ARGS... -> runs the real `record` CLI, sets R_RC / R_ERR


echo "== review_record guard sub-clause isolating cases (V3 round 4, R4-F3) =="

# --- _admit_backfill -------------------------------------------------------
fresh_case bcs
rr_genuine "$REC/r1.json" B-BCS c-bcs 1 GO "$NONE" D-BCS
backfill "$REC/h.json" '{"review_id":"R-H","batch_id":"B-OTHER","round":1,"verdict":"NO-GO","findings":[],"source_evidence":"UNKNOWN"}'
gate c-bcs
if covered c-bcs; then ok "G-B-CHANGES-SHAPE#1: a backfill row with change_ids \"UNKNOWN\" (no change_ids in its spec) is admitted, not refused as malformed"
else bad "G-B-CHANGES-SHAPE#1: rc=$G_RC out=$G_OUT"; fi
edit "$REC/h.json" 'd["change_ids"]=["c-bcs", 7]' rehash
gate c-bcs
if blind "h.json" && has "backfill change_ids must be"; then ok "G-B-CHANGES-SHAPE#3: a backfill change_ids list holding a non-string is inadmissible (exit 4)"
else bad "G-B-CHANGES-SHAPE#3: rc=$G_RC out=$G_OUT"; fi

# --- _admit_live -------------------------------------------------------------
fresh_case ewf
rr_genuine "$REC/r1.json" B-EWF c-ewf 1 GO "$NONE" D-EWF
reforge_ev "$REC/r1.json" 'v["findings"] = "none"'
gate c-ewf
if blind "r1.json" && has "no well-formed verdict/findings"; then ok "G-A-EVIDENCE-WELLFORMED#2: archived evidence whose findings is not a list is inadmissible (named)"
else bad "G-A-EVIDENCE-WELLFORMED#2: rc=$G_RC out=$G_OUT"; fi

fresh_case beq
RR_CHANGES='["a","b"]' rr_genuine "$REC/r1.json" B-BEQ a 1 GO "$NONE" D-BEQ
cp "$REC/r1.json" "$CASE/r1.pristine"
edit "$REC/r1.json" 'd["change_ids"]="ab"' rehash
gate a
if blind "r1.json" && has "disagree with the reviewer's review binding"; then ok "G-A-BINDING-EQUAL#2: a record whose change_ids is the STRING \"ab\" (sorts to the binding [a, b]) is inadmissible"
else bad "G-A-BINDING-EQUAL#2: rc=$G_RC out=$G_OUT"; fi
cp "$CASE/r1.pristine" "$REC/r1.json"
edit "$REC/r1.json" 'd["change_ids"]=[1, "a"]' rehash
gate a
if blind "r1.json" && has "disagree with the reviewer's review binding"; then ok "G-A-BINDING-EQUAL#3: a record change_ids holding a non-string is refused as a binding disagreement (never an internal error)"
else bad "G-A-BINDING-EQUAL#3: rc=$G_RC out=$G_OUT"; fi

fresh_case fe4
rr_genuine "$REC/r1.json" B-FE4 c-fe4 1 GO "$NONE" D-FE4
edit "$REC/r1.json" 'd["model_tier"]="sonnet"' rehash
gate c-fe4
if blind "r1.json" && has "record fields disagree"; then ok "G-A-FIELDS-EQUAL#4: a record whose model_tier (alone) differs from the reviewer's evidence is inadmissible"
else bad "G-A-FIELDS-EQUAL#4: rc=$G_RC out=$G_OUT"; fi

# --- _evidence_bytes_verified ------------------------------------------------
fresh_case hs1
rr_genuine "$REC/r1.json" B-HS1 c-hs1 1 GO "$NONE" D-HS1
edit "$REC/r1.json" 'd["verdict_evidence_sha256"]=None' rehash
gate c-hs1
if blind "r1.json" && has "verdict_evidence missing or not hash-verifiable"; then ok "G-E-HASH-SHAPE#1: a null evidence pin is refused as not hash-verifiable (never an internal error)"
else bad "G-E-HASH-SHAPE#1: rc=$G_RC out=$G_OUT"; fi
fresh_case hm1
rr_genuine "$REC/r1.json" B-HM1 c-hm1 1 GO "$NONE" D-HM1
python3 - "$REC/r1.json" <<'PY'
import hashlib, json, os, sys
p = sys.argv[1]; d = json.load(open(p)); base = os.path.dirname(p)
os.remove(os.path.join(base, d["verdict_evidence"]))
sha = hashlib.sha256(b"").hexdigest()
open(os.path.join(base, sha + ".verdict-evidence"), "wb").close()
d["verdict_evidence"] = sha + ".verdict-evidence"; d["verdict_evidence_sha256"] = sha
body = {k: x for k, x in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
gate c-hm1
if blind "r1.json" && has "verdict_evidence missing or not hash-verifiable"; then ok "G-E-HASH-MATCH#1: an EMPTY archive carrying the empty-content hash is refused as not hash-verifiable"
else bad "G-E-HASH-MATCH#1: rc=$G_RC out=$G_OUT"; fi

# --- _extract_slice_lines ------------------------------------------------------
fresh_case sle
RR_SLICES='[5, {"lines":[1]}, {"slice_id":"S9"}, {"slice_id":"S1","lines":[2]}]' rr_genuine "$REC/r1.json" B-SLE c-sle 1 GO "$NONE" D-SLE
SL=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["slice_lines"]))' "$REC/r1.json" 2>/dev/null)
expect "G-SL-ENTRIES#1-3" "$RR_RC $SL" '0 [{"lines": [2], "slice_id": "S1"}]' \
  "a batch slice that is not an object, lacks slice_id, or lacks lines is skipped (record rc 0, only S1 kept)"

# --- _gate_batch_qualifies -----------------------------------------------------
fresh_case dt1
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-DT1 c-dt1 1 GO "$NONE" D-DT1
rr_ledger_row D-DT1 sonnet xhigh
reforge_ev "$REC/r1.json" 'v["reviewer"]["model"] = "sonnet"'
edit "$REC/r1.json" 'd["model_tier"]="sonnet"' rehash
gate c-dt1
if uncovered c-dt1 && has "reviewer tier/effort sonnet/xhigh is not opus/xhigh"; then ok "G-Q-DESIGNATED-TIER#1: a consistent sonnet/xhigh review (evidence, record and ledger all say sonnet) is never coverage"
else bad "G-Q-DESIGNATED-TIER#1: rc=$G_RC out=$G_OUT"; fi

fresh_case qpn
rr_genuine "$REC/r1.json" B-QPN c-qpn 1 GO "$NONE" D-QPN
edit "$REC/r1.json" 'd["producer_id"]=5' rehash
gate c-qpn
if uncovered c-qpn && has "record names no producer identity"; then ok "G-Q-PRODUCER-NAMED#1: a non-string producer identity is 'no producer' (never an internal error)"
else bad "G-Q-PRODUCER-NAMED#1: rc=$G_RC out=$G_OUT"; fi

fresh_case qms
rr_genuine "$REC/r1.json" B-QMS c-qms 1 GO "$NONE" D-QMS
edit "$REC/r1.json" 'd["slice_lines"]="UNKNOWN"' rehash
gate c-qms
if covered c-qms; then ok "G-Q-MULTI-SLICE#1: a slice_lines that is not a list declares no slices (COVERED, never an internal error)"
else bad "G-Q-MULTI-SLICE#1: rc=$G_RC out=$G_OUT"; fi

fresh_case qes
rr_genuine "$REC/r1.json" B-QES c-qes 1 GO "$NONE" D-QES
reforge_ev "$REC/r1.json" 'v["slice_verdicts"] = ["S1"]'
gate c-qes
if uncovered c-qes && has "a reviewer slice verdict is not GO"; then ok "G-Q-EVIDENCE-SLICES-GO#3: a reviewer slice verdict that is not an object refuses coverage (never an internal error)"
else bad "G-Q-EVIDENCE-SLICES-GO#3: rc=$G_RC out=$G_OUT"; fi

# G-Q-SEAM-TIER: the decision with the store tier stubbed to capability (unit
# level: the real cmd_gate, only _store_tier replaced -- capability is not
# reachable through the CLI on a host without a second real account).
fresh_case qst
rr_genuine "$REC/r1.json" B-QST c-qst 1 GO "$NONE" D-QST
QST=$(python3 - "$RR_TOOL" "$REC" "$RR_LEDGER" <<'PY'
import argparse, contextlib, importlib.util, io, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
rr._store_tier = lambda *a, **k: ("capability", None)
out = []
for seam in ("release-tag", "ordinary"):
    a = argparse.Namespace(change="c-qst", records=sys.argv[2], dispatch_ledger=sys.argv[3], seam=seam,
                           round_budget=None, producer_uid=None, evidence_owner_uid=None)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = rr.cmd_gate(a)
    out.append("%d:%s" % (rc, buf.getvalue().strip().split(" independence=")[-1]))
print(" ".join(out))
PY
)
expect G-Q-SEAM-TIER#2 "$QST" "0:capability seam=release-tag 0:capability seam=ordinary" \
  "with the store tier at capability, a genuine GO is COVERED at release-tag (the high-blast seam does not refuse capability)"

# --- _gate_change_verdict ------------------------------------------------------
fresh_case vbl
rr_genuine "$REC/r1.json" B-VBL c-vbl 1 NO-GO '[{"id":"F","severity":"BLOCKING","finding_layer":"source-defect"}]' D-VBL
gate c-vbl
if uncovered c-vbl && ! has "backfilled"; then ok "G-V-BACKFILL-LISTS#1: a live NO-GO is reported as a live refusal, never as a backfilled round"
else bad "G-V-BACKFILL-LISTS#1: rc=$G_RC out=$G_OUT"; fi
fresh_case vbb1
rr_genuine "$REC/r1.json" B-VBB c-vbb 1 GO "$NONE" D-VBB1
backfill "$REC/h.json" '{"review_id":"R","batch_id":"B-VBB","round":3,"verdict":"NO-GO","findings":[],"change_ids":["c-vbb"],"source_evidence":"UNKNOWN"}'
gate c-vbb
if uncovered c-vbb && has "backfilled round 3 is not a zero-finding GO"; then ok "G-V-BACKFILL-BLOCKS#1: a zero-finding backfill NO-GO still blocks (the verdict decides, not the finding count)"
else bad "G-V-BACKFILL-BLOCKS#1: rc=$G_RC out=$G_OUT"; fi
fresh_case vbb2
rr_genuine "$REC/r1.json" B-VBB c-vbb 1 GO "$NONE" D-VBB2
backfill "$REC/h.json" '{"review_id":"R","batch_id":"B-VBB","round":3,"verdict":"GO","findings":[{"id":"H","severity":"MINOR"}],"change_ids":["c-vbb"],"source_evidence":"UNKNOWN"}'
gate c-vbb
if uncovered c-vbb && has "backfilled round 3 is not a zero-finding GO"; then ok "G-V-BACKFILL-BLOCKS#2: a backfill GO that still carries findings blocks"
else bad "G-V-BACKFILL-BLOCKS#2: rc=$G_RC out=$G_OUT"; fi

# --- _gate_collect_records -----------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  fresh_case cls
  rr_genuine "$REC/r1.json" B-CLS c-cls 1 GO "$NONE" D-CLS
  mkdir "$REC/hide"; chmod 000 "$REC/hide"
  gate c-cls; chmod 755 "$REC/hide"
  if blind "a record hidden in it cannot be ruled out"; then ok "G-C-LISTED#1: the RECORD walk itself names an unlistable directory (exit 4)"
  else bad "G-C-LISTED#1: rc=$G_RC out=$G_OUT"; fi
fi
fresh_case cir
rr_genuine "$REC/r1.json" B-CIR c-cir 1 GO "$NONE" D-CIR
edit "$REC/r1.json" 'd["round"]="1"' rehash
gate c-cir
if blind "non-integer round"; then ok "G-C-INT-ROUND#1: a string round is refused at collection as a non-integer round"
else bad "G-C-INT-ROUND#1: rc=$G_RC out=$G_OUT"; fi

# --- _has_acl / _owner_only_error ACL sub-clauses --------------------------------
ACL=$(python3 - "$RR_TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
print(rr._has_acl("/nonexistent/no/such/path"), rr._has_acl("/etc/hostname"))
PY
)
expect G-ACL-UNLISTABLE#1 "$ACL" "True False" "an inode whose xattrs cannot be listed (ENOENT) counts as carrying an ACL; a plain file does not"
if command -v setfacl >/dev/null 2>&1 && NOBODY=$(python3 -c 'import pwd; print(pwd.getpwnam("nobody").pw_uid)' 2>/dev/null) \
   && DAEMON=$(python3 -c 'import pwd; print(pwd.getpwnam("daemon").pw_uid)' 2>/dev/null) && [ "$(id -u)" -ne 0 ]; then
  T="$S/acl"; mkdir -p "$T/d" "$T/e"; chmod 755 "$T" "$T/d" "$T/e"
  echo x > "$T/d/f"; chmod 644 "$T/d/f"; echo x > "$T/e/f"; chmod 644 "$T/e/f"
  if setfacl -m "u:$NOBODY:r" "$T/d/f" 2>/dev/null && setfacl -m "u:$NOBODY:rx" "$T/e" 2>/dev/null; then
    AT=$(python3 - "$RR_TOOL" "$T" "$NOBODY" "$DAEMON" "$(id -u)" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
t, nb, dm, me = sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
r1 = rr._path_tier([t + "/d/f"], nb, me, runner_uid=dm)
r2 = rr._path_tier([t + "/e/f"], nb, me, runner_uid=dm)
print(r1[0], "ACL" in (r1[1] or ""), r2[0], "directory" in (r2[1] or "") and "ACL" in (r2[1] or ""))
PY
)
    expect G-T-LEAF-DIR-NO-ACL "$AT" "instance True instance True" \
      "a read-only ACL entry (no group-write mask) on the evidence file, or on a chain directory, makes the tier instance"
  else echo "NOTE: setfacl refused by this filesystem -- G-T-LEAF/DIR-NO-ACL cases SKIPPED"; fi
else echo "NOTE: setfacl or nobody/daemon unavailable -- G-T-LEAF/DIR-NO-ACL cases SKIPPED"; fi

# --- _load_ledger ----------------------------------------------------------------
fresh_case lrs
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-LRS c-lrs 1 GO "$NONE" D-LRS
{ echo 'not json at all'; echo '[1, 2]'; echo '{"key": ["x"], "event": "complete"}'; } >> "$RR_LEDGER"
rr_ledger_row D-LRS opus xhigh
gate c-lrs
if covered c-lrs; then ok "G-L-ROW-SHAPE#1/#2, G-L-SKIP-UNPARSEABLE#1: an unparseable line, a non-object row and a row whose key is not a string are ignored -- the genuine rows still authenticate"
else bad "G-L-ROW-SHAPE/SKIP: rc=$G_RC out=$G_OUT"; fi

# --- _normalize_line via the REAL record classifier ---------------------------
fresh_case nl
mkdir -p "$CASE/in"
printf '{"batch_id":"B-NL","changes":["c-nl"]}\n' > "$CASE/in/batch.json"
printf '{"schema":"precheck/v1","batch_id":"B-NL","all_pass":true,"checks":[{"check":"already-fixed-markers","evidence":{"markers":[{"file":"a.sh","line":87},{"file":"b.sh","line":1}]}}]}\n' > "$CASE/in/precheck.json"
printf '{"round":1,"verdict":"NO-GO","findings":[{"id":"F1","file":"a.sh","line":"87"},{"id":"F2","file":"b.sh","line":true}]}\n' > "$CASE/in/verdict.json"
python3 "$RR_TOOL" record --batch "$CASE/in/batch.json" --round 1 --verdict-file "$CASE/in/verdict.json" \
  --precheck "$CASE/in/precheck.json" --tier opus --effort xhigh --out "$CASE/nl.json" >/dev/null 2>&1
NL=$(python3 -c 'import json,sys; print(" ".join(f["id"]+"="+f["class"] for f in json.load(open(sys.argv[1]))["findings"]))' "$CASE/nl.json" 2>/dev/null)
expect "G-NL-STR#1,G-NL-DIGITS#1,G-NL-NONE-BOOL#2" "$NL" "F1=false-positive F2=judgment" \
  "a string line \"87\" matches marker line 87 (false-positive); a boolean line true never matches marker line 1"

# --- _owner_declaration_error: a non-integer owner -------------------------------
OD=$(python3 - "$RR_TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
r = rr._owner_declaration_error("4242", 65534, 1000, [], lambda u: object())
print("declared" in (r or ""))
PY
)
expect G-T-OWNER-DECLARED#3 "$OD" True "a non-integer evidence-owner value is 'not declared' (never a TypeError)"

# =============================================================================
# V3 round 4, fixer F-C5 (respawn): isolating cases for the sub-clauses the
# FULL mechanical sweep (test_review_record_subclause_sweep.sh, run 2026-10-08)
# found SURVIVING every suite. Each holds every other condition of its guard.
# =============================================================================
ME=$(id -u)
S1='[{"slice_id":"S1","lines":[1]}]'

# --- _validated_slice_verdicts, through the REAL `record` CLI ------------------
sv_case() { # sv_case NAME SLICE_VERDICTS_JSON -> RR_RC, SV_ERR
  fresh_case "sv_$1"
  RR_SLICES="$S1" RR_SLICE_VERDICTS="$2" rr_genuine "$REC/r1.json" "B-SV$1" "c-sv$1" 1 GO "$NONE" "D-SV$1"
  SV_ERR=$(cat "$RR_WORK/r1/record.err" 2>/dev/null)
  rm -rf "$RR_WORK/r1"
}
sv_case list 5
if [ "$RR_RC" -eq 2 ] && printf '%s' "$SV_ERR" | grep -q "'slice_verdicts' must be a JSON list"; then
  ok "G-SV-LIST#1: a non-list slice_verdicts (5) is a usage error (exit 2, named), never an internal error"
else bad "G-SV-LIST#1: rc=$RR_RC err=$SV_ERR"; fi
sv_case entry '[5]'
if [ "$RR_RC" -eq 2 ] && printf '%s' "$SV_ERR" | grep -q "slice verdict entry must be an object"; then
  ok "G-SV-ENTRY-OBJECT#1: a slice verdict entry that is not an object is refused (exit 2, named)"
else bad "G-SV-ENTRY-OBJECT#1: rc=$RR_RC err=$SV_ERR"; fi
sv_case known '[{"slice_id":["S1"],"verdict":"GO"}]'
if [ "$RR_RC" -eq 2 ] && printf '%s' "$SV_ERR" | grep -q "names unknown slice"; then
  ok "G-SV-KNOWN-SLICE#1: a non-string slice_id (a list) is an unknown slice (exit 2), never an unhashable-type crash"
else bad "G-SV-KNOWN-SLICE#1: rc=$RR_RC err=$SV_ERR"; fi
sv_case once '[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S1","verdict":"GO"}]'
if [ "$RR_RC" -eq 2 ] && printf '%s' "$SV_ERR" | grep -q "more than one slice verdict"; then
  ok "G-SV-ONCE#1: two (agreeing) verdicts for one slice are refused (exit 2)"
else bad "G-SV-ONCE#1: rc=$RR_RC err=$SV_ERR"; fi
sv_case closed '[{"slice_id":"S1","verdict":"MAYBE"}]'
if [ "$RR_RC" -eq 2 ] && printf '%s' "$SV_ERR" | grep -q "verdict must be GO or NO-GO"; then
  ok "G-SV-CLOSED-SET#1: a slice verdict outside {GO, NO-GO} is refused (exit 2)"
else bad "G-SV-CLOSED-SET#1: rc=$RR_RC err=$SV_ERR"; fi
fresh_case sv_null
RR_SLICE_VERDICTS=null rr_genuine "$REC/r1.json" B-SVN c-svn 1 GO "$NONE" D-SVN
gate c-svn
if [ "$RR_RC" -eq 0 ] && covered c-svn; then ok "G-SV-ABSENT#2: slice_verdicts null is the same as absent (record exit 0, gate COVERED)"
else bad "G-SV-ABSENT#2: record rc=$RR_RC gate rc=$G_RC out=$G_OUT"; fi
fresh_case sv_nogo
RR_SLICES="$S1" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"NO-GO"}]' \
  rr_genuine "$REC/r1.json" B-SVG c-svg 1 NO-GO '[{"id":"F1","slice_id":"S1","finding_layer":"source-defect"}]' D-SVG
if [ "$RR_RC" -eq 0 ]; then ok "G-SV-GO-SLICE-FINDING#2: a source-defect finding in a NO-GO slice is legitimate (record exit 0) -- only GO slices refuse it"
else bad "G-SV-GO-SLICE-FINDING#2: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi

# --- _parse_optional_json, through the REAL `record` CLI -----------------------
fresh_case pj
rr_genuine "$REC/r1.json" B-PJ c-pj 1 GO "$NONE" D-PJ --tokens '{bad'
if [ "$RR_RC" -eq 2 ] && grep -q "bad JSON for --tokens" "$RR_WORK/r1/record.err"; then
  ok "G-PJ-BAD#1: malformed --tokens JSON is a usage error (exit 2, named), never a traceback"
else bad "G-PJ-BAD#1: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi

# --- _validated_reviewer: reviewer null is reviewer-less, never malformed ---------
fresh_case rvnull
mkdir -p "$CASE/in"
printf '{"round":1,"verdict":"GO","findings":[],"batch_id":"B-RVN","change_ids":["c-rvn"],"review_base":"1111111111111111111111111111111111111111","review_head":"2222222222222222222222222222222222222222","reviewer":null}\n' > "$CASE/in/v.json"
RR_VERDICT_FROM="$CASE/in/v.json" rr_genuine "$REC/r1.json" B-RVN c-rvn 1 GO "$NONE" D-RVN
gate c-rvn
if [ "$RR_RC" -eq 0 ] && uncovered c-rvn && has "names no reviewer identity"; then
  ok "G-RV-ABSENT#2: a verdict with \"reviewer\": null is recorded (exit 0) as reviewer-less and never covers"
else bad "G-RV-ABSENT#2: record rc=$RR_RC gate rc=$G_RC out=$G_OUT"; fi

# --- reviewer identity / review binding shapes, through the REAL gate -------------
bind_case() { # bind_case NAME PY_STMT_ON_v EXPECTED_SUBSTRING
  fresh_case "bd_$1"
  rr_genuine "$REC/r1.json" "B-BD$1" "c-bd$1" 1 GO "$NONE" "D-BD$1"
  reforge_ev "$REC/r1.json" "$2"
  gate "c-bd$1"
  if blind "$3"; then ok "binding/reviewer shape $1: $2 -> inadmissible (exit 4: $3)"
  else bad "binding/reviewer shape $1 ($2): rc=$G_RC out=$G_OUT"; fi
}
bind_case b1 'v["batch_id"] = 5' "review binding batch_id must be"
bind_case b2 'v["batch_id"] = ""' "review binding batch_id must be"
bind_case c1 'v["change_ids"] = "cX"' "review binding change_ids must be"
bind_case c2 'v["change_ids"] = []' "review binding change_ids must be"
bind_case c3 'v["change_ids"] = [5]' "review binding change_ids must be"
bind_case c4 'v["change_ids"] = [""]' "review binding change_ids must be"
bind_case c5 'v["change_ids"] = [" cX"]' "review binding change_ids must be"
bind_case r1 'v["round"] = "1"' "review binding round must be"
bind_case r2 'v["round"] = True' "review binding round must be"
bind_case r3 'v["round"] = 0' "review binding round must be"
bind_case k1 'v["review_base"] = 5' "review binding review_base must be"
bind_case k2 'v["review_base"] = "XYZ"' "review binding review_base must be"
bind_case v1 'v["reviewer"]["model"] = 5' "'reviewer.model' must be a non-empty string"
bind_case v2 'v["reviewer"]["model"] = "  "' "'reviewer.model' must be a non-empty string"

# --- G-Q-MULTI-SLICE#1: a non-list slice_lines declares no slices EVEN when the
#     reviewer's evidence carries (GO) slice verdicts ------------------------------
fresh_case qms2
RR_SLICES="$S1" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"}]' rr_genuine "$REC/r1.json" B-QM2 c-qm2 1 GO "$NONE" D-QM2
edit "$REC/r1.json" 'd["slice_lines"]="UNKNOWN"' rehash
gate c-qm2
if covered c-qm2; then ok "G-Q-MULTI-SLICE#1: slice_lines \"UNKNOWN\" (len 7, not a list) is not a multi-slice batch -- the GO slice verdict covers"
else bad "G-Q-MULTI-SLICE#1 (evidence slices): rc=$G_RC out=$G_OUT"; fi

# --- tier internals, in-process on REAL files (unit level, 11.4.27(A)) ------------
TIER=$(cd "$S" && timeout 20 python3 - "$RR_TOOL" "$S" "$ME" <<'PY'
import importlib.util, os, stat, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
d, me = sys.argv[2], int(sys.argv[3])
other = me + 12345
pw = lambda u: object()
f = os.path.join(d, "tier_probe"); open(f, "w").write("x"); os.chmod(f, 0o644)
out = {}
# G-T-RUNNER-NOT-ROOT#1: a root runner is instance even when every other clause holds
out["runner"] = (rr._path_tier([f], 65534, me, runner_uid=other, ranges=[], getpw=pw)[0],
                 rr._path_tier([f], 65534, me, runner_uid=0, ranges=[], getpw=pw)[0])
# G-T-PRODUCER-DECLARED#2/#3: a bool / str producer is not a declared uid
out["prod"] = (rr._path_tier(["/etc/hostname"], True, 0, runner_uid=1000, ranges=[], getpw=pw)[0],
               rr._path_tier(["/etc/hostname"], "65534", 0, runner_uid=1000, ranges=[], getpw=pw)[0])
# G-T-SUBID-KNOWN#1: unknowable host subordinate ranges -> instance, with that reason
real = rr._subid_ranges
rr._subid_ranges = lambda: (None, "unknowable-probe")
out["subid"] = rr._path_tier(["/etc/hostname"], 65534, 0, runner_uid=1000, ranges=None, getpw=pw)
rr._subid_ranges = real
# G-T-LINK-SPLIT#1: a relative symlink resolves to its target file
tgt = os.path.join(d, "ls_target"); open(tgt, "w").write("y")
lnk = os.path.join(d, "ls_link"); os.symlink("ls_target", lnk)
ch = rr._resolution_chain(lnk)
out["split"] = (ch[0] == os.path.realpath(tgt), stat.S_ISREG(ch[1].st_mode))
# G-T-LINK-LOOP#1: a symlink loop raises (never spins)
lp = os.path.join(d, "lp"); os.symlink("lp", lp)
try:
    rr._resolution_chain(lp); out["loop"] = "no-raise"
except OSError as exc:
    out["loop"] = "too many levels" in str(exc)
# G-T-STORE-LISTED#1: an unlistable directory in the store -> instance, named
st = os.path.join(d, "st_store"); os.mkdir(st, 0o755)
open(os.path.join(st, "r.json"), "w").write("{}"); os.chmod(os.path.join(st, "r.json"), 0o644)
led = os.path.join(d, "st_ledger"); open(led, "w").write(""); os.chmod(led, 0o644)
hid = os.path.join(st, "hid"); os.mkdir(hid, 0o755)
ctrl = rr._store_tier(st, led, 65534, me, runner_uid=other, ranges=[], getpw=pw)[0]
os.chmod(hid, 0)
blind = rr._store_tier(st, led, 65534, me, runner_uid=other, ranges=[], getpw=pw)
os.chmod(hid, 0o755)
out["store"] = (ctrl, blind[0], "cannot list" in (blind[1] or ""))
# G-SUB-LINE-WELLFORMED#2/#3: a non-numeric start or count -> unknowable
def w(n, t):
    p = os.path.join(d, n); open(p, "w").write(t); return p
nss = w("ns_files2", "subid: files\n")
out["subline"] = (rr._subid_ranges((w("sb1", "milos:abc:5\n"),), nss)[0] is None,
                  rr._subid_ranges((w("sb2", "milos:5:abc\n"),), nss)[0] is None)
# G-ACL-PLATFORM#1: a platform with no listxattr counts as carrying an ACL (conservative)
del rr.os.listxattr
out["acl"] = rr._has_acl(f)
# G-E-READ#1: an OSError while reading the evidence is a refusal, never a crash
import hashlib
ev = os.path.join(d, "ev_read"); open(ev, "wb").write(b"zz")
sha = hashlib.sha256(b"zz").hexdigest()
good = rr._evidence_bytes_verified("ev_read", sha, None, d, d)[0] == b"zz"
def boom(*a, **k): raise OSError(5, "EIO probe")
rr.os.fdopen = boom
out["read"] = (good, rr._evidence_bytes_verified("ev_read", sha, None, d, d) == (None, None))
for k in ("runner", "prod", "subid", "split", "loop", "store", "subline", "acl", "read"):
    print("%s=%s" % (k, out[k]))
PY
)
row() { printf '%s\n' "$TIER" | grep "^$1=" | cut -d= -f2-; }
if [ "$ME" -eq 0 ]; then echo "NOTE: running as root -- tier internals cases SKIPPED"
else
  expect G-T-RUNNER-NOT-ROOT#1 "$(row runner)" "('capability', 'instance')" "a root runner is instance; the same evidence with a non-root runner is capability (control)"
  expect G-T-PRODUCER-DECLARED#2/#3 "$(row prod)" "('instance', 'instance')" "a bool (True) or string ('65534') producer uid is not declared (never uid 1, never a TypeError)"
  expect G-T-SUBID-KNOWN#1 "$(row subid)" "('instance', 'unknowable-probe')" "unknowable subordinate-id ranges degrade to instance with that reason (never a TypeError)"
  expect G-T-LINK-SPLIT#1 "$(row split)" "(True, True)" "a relative symlink resolves to its regular target file"
  expect G-T-LINK-LOOP#1 "$(row loop)" "True" "a symlink loop raises 'too many levels' (a mutant that never counts hops hangs and is killed by timeout)"
  expect G-T-STORE-LISTED#1 "$(row store)" "('capability', 'instance', True)" "a chmod-000 directory in the store makes it instance, named (control: listable -> capability)"
  expect G-SUB-LINE-WELLFORMED#2/#3 "$(row subline)" "(True, True)" "a subordinate-id line with a non-numeric start or count makes the ranges unknowable"
  expect G-ACL-PLATFORM#1 "$(row acl)" "True" "without os.listxattr an inode counts as carrying an ACL"
  expect G-E-READ#1 "$(row read)" "(True, True)" "an OSError reading verified evidence is a refusal (control: the same file verifies when readable)"
fi

# --- record-side: _write_record failure paths, classify_finding, markers ----------
fresh_case wr
mkdir -p "$CASE/in"
printf '{"batch_id":"B-WR","changes":["c-wr"]}\n' > "$CASE/in/batch.json"
printf '{"round":1,"verdict":"NO-GO","findings":[{"id":"F\\ud800"}]}\n' > "$CASE/in/enc.json"
printf '{"round":1,"verdict":"GO","findings":[]}\n' > "$CASE/in/go.json"
rec_raw() { # rec_raw VERDICT OUT [PRECHECK] -> W_RC, W_ERR
  local pre=()
  [ -n "${3:-}" ] && pre=(--precheck "$3")
  W_ERR=$(python3 "$RR_TOOL" record --batch "$CASE/in/batch.json" --round 1 --verdict-file "$1" "${pre[@]}" \
    --tier opus --effort xhigh --out "$2" 2>&1 >/dev/null)
  W_RC=$?
}
rec_raw "$CASE/in/enc.json" "$CASE/enc.json"
if [ "$W_RC" -eq 2 ] && printf '%s' "$W_ERR" | grep -q "body not encodable"; then
  ok "G-W-ENCODE#1: a body holding a lone surrogate (finding id \"F\\ud800\") is refused as not encodable (exit 2), never a traceback"
else bad "G-W-ENCODE#1: rc=$W_RC err=$W_ERR"; fi
mkdir -p "$CASE/outdir/x"
rec_raw "$CASE/in/go.json" "$CASE/outdir"
if [ "$W_RC" -eq 2 ] && printf '%s' "$W_ERR" | grep -q "cannot write --out" && [ -z "$(find "$CASE" -maxdepth 1 -name '.review_record.*')" ]; then
  ok "G-W-WRITE#1: --out naming an existing directory is refused (exit 2, named) and leaves no temp file behind"
else bad "G-W-WRITE#1: rc=$W_RC err=$W_ERR"; fi
printf '{"schema":"precheck/v1","batch_id":"B-WR","all_pass":true,"checks":[5,{"check":"other","evidence":{"markers":[{"file":"a.sh","line":87}]}}]}\n' > "$CASE/in/pre.json"
printf '{"round":1,"verdict":"NO-GO","findings":[{"id":"F1","file":"a.sh","line":87},{"id":"F2","rule":"   "},{"id":"F3","rule":"SC2086"}]}\n' > "$CASE/in/cls.json"
rec_raw "$CASE/in/cls.json" "$CASE/cls.json" "$CASE/in/pre.json"
CLS=$(python3 -c 'import json,sys; print(" ".join(f["id"]+"="+f["class"] for f in json.load(open(sys.argv[1]))["findings"]))' "$CASE/cls.json" 2>/dev/null)
expect "G-MK-CHECK#1/#2,G-CF-RULE#2" "$W_RC:$CLS" "0:F1=judgment F2=judgment F3=mechanical" \
  "a non-object check entry is skipped (no crash); markers of a check that is not already-fixed-markers never make a false-positive; a whitespace-only rule is not mechanical (control: a real rule is)"

# --- cmd_record usage/refusal paths, through the REAL `record` CLI ---------------
fresh_case rc
RI="$CASE/in"; mkdir -p "$RI"
B40=1111111111111111111111111111111111111111; H40=2222222222222222222222222222222222222222
printf '{"batch_id":"B-RC","changes":["c-rc"]}\n' > "$RI/batch.json"
jv() { printf '%s\n' "$2" > "$RI/$1"; }  # jv NAME JSON
jv go.json '{"round":1,"verdict":"GO","findings":[]}'
rr() { # rr VERDICT [extra args...] -> X_RC, X_ERR, output at $CASE/x.json
  rm -f "$CASE/x.json"
  X_ERR=$(python3 "$RR_TOOL" record --batch "${XB:-$RI/batch.json}" --round "${XR:-1}" --verdict-file "$RI/$1" \
    --tier opus --effort xhigh --out "${XO:-$CASE/x.json}" "${@:2}" 2>&1 >/dev/null)
  X_RC=$?
}
want() { # want LABEL RC SUBSTRING TEXT
  if [ "$X_RC" -eq "$2" ] && printf '%s' "$X_ERR" | grep -qF -- "$3"; then ok "$1: $4"
  else bad "$1: rc=$X_RC (want $2) err=$X_ERR"; fi
}
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(eval(sys.argv[2])))' "$CASE/x.json" "$1" 2>/dev/null; }

jv r0.json '{"round":0,"verdict":"GO","findings":[]}'
XR=0 rr r0.json; want G-R-ROUND-MIN#1 2 "--round must be >= 1" "--round 0 is a usage error even when the verdict file also says round 0"
XB="$RI/no_such_batch.json" rr go.json; want G-R-BATCH-LOAD#1 2 "cannot read/parse" "an unreadable --batch is named as unreadable (never 'not an object')"
printf '[]\n' > "$RI/batch_list.json"
XB="$RI/batch_list.json" rr go.json; want G-R-BATCH-OBJECT#1 2 "--batch must be a JSON object" "a --batch that is a JSON list is refused (exit 2), never an AttributeError"
jv vlist.json '[]'
rr vlist.json; want G-R-VERDICT-OBJECT#1 2 "--verdict-file must be a JSON object" "a verdict file that is a JSON list is refused (exit 2)"
jv vf.json '{"round":1,"verdict":"GO","findings":"none"}'
rr vf.json; want G-R-FINDINGS-LIST#1 2 "'findings' must be a JSON list" "a non-list findings value is refused (exit 2)"
jv vc.json '{"round":1,"verdict":"MAYBE","findings":[]}'
rr vc.json; want G-R-VERDICT-CLOSED#1 2 "must carry a 'verdict' field of 'GO' or 'NO-GO'" "a verdict outside {GO, NO-GO} is refused (exit 2)"
jv vnr.json '{"verdict":"GO","findings":[]}'
rr vnr.json; want G-R-VROUND-PRESENT#1 2 "must carry the reviewer's own 'round'" "a verdict without its own round is refused as round-less (named)"
jv vsr.json '{"round":"1","verdict":"GO","findings":[]}'
rr vsr.json; want G-R-VROUND-INT#1 2 "'round' must be an integer" "a string round \"1\" is refused as non-integer (never a silent mismatch)"
jv v2.json '{"round":2,"verdict":"GO","findings":[]}'
rr v2.json; want G-R-VROUND-MATCH#1 2 "does not match --verdict-file's own 'round'" "--round 1 with a verdict that says round 2 is refused"
rr go.json --reviewer-mutations '{bad'; want G-R-RM-BAD#1 2 "bad JSON for --reviewer-mutations" "malformed --reviewer-mutations JSON is a usage error (exit 2)"
jv vfs.json '{"round":1,"verdict":"NO-GO","findings":[5]}'
rr vfs.json; want G-R-FINDING-SHAPE#1 2 "malformed finding entry" "a finding that is not an object is refused (exit 2), never a TypeError"
jv vfi.json '{"round":1,"verdict":"NO-GO","findings":[{"severity":"HIGH"}]}'
rr vfi.json; want G-R-FINDING-SHAPE#2 2 "malformed finding entry (missing 'id')" "a finding without an id is refused (exit 2)"
printf '{not json\n' > "$RI/pre_bad.json"
rr go.json --precheck "$RI/pre_bad.json"; want G-R-PRECHECK-LOAD#1 2 "cannot read/parse" "an unparseable --precheck is refused (exit 2), never treated as consulted"
XO="$CASE/no_dir/x.json" rr go.json; want G-R-ARCHIVE-WRITE#1 2 "could not archive evidence alongside --out" "an --out whose directory does not exist is refused (exit 2) before anything is written"

# defaults and derived flags written into the record
rr go.json
expect "G-R-PRODUCER-DEFAULT#4,G-R-TOKENS-DEFAULT#1,G-R-RM-DEFAULT#1" "$X_RC:$(field '[d["producer_id"], d["tokens"], d["reviewer_mutations"], d["first_round_go"]]')" \
  '0:["UNKNOWN", "UNMEASURED", "UNKNOWN", true]' "no --producer-id/--tokens/--reviewer-mutations records the honest literals; round-1 zero-finding GO is first_round_go"
XR=2 rr v2.json
expect G-R-FIRST-ROUND-GO#1 "$X_RC:$(field 'd["first_round_go"]')" "0:false" "a round-2 zero-finding GO is not first_round_go"
jv vng.json '{"round":1,"verdict":"NO-GO","findings":[]}'
rr vng.json
expect G-R-FIRST-ROUND-GO#2 "$X_RC:$(field 'd["first_round_go"]')" "0:false" "a round-1 zero-finding NO-GO is not first_round_go"
jv vgf.json '{"round":1,"verdict":"GO","findings":[{"id":"F1","finding_layer":"process-doc"}]}'
rr vgf.json
expect G-R-FIRST-ROUND-GO#3 "$X_RC:$(field 'd["first_round_go"]')" "0:false" "a round-1 GO that still carries a finding is not first_round_go"
# --precheck from ANOTHER directory is honoured (the batch directory holds none)
mkdir -p "$CASE/elsewhere"; printf '{"schema":"precheck/v1","batch_id":"B-RC","all_pass":true,"checks":[]}\n' > "$CASE/elsewhere/p.json"
rr go.json --precheck "$CASE/elsewhere/p.json"
expect G-R-PRECHECK-PATH#1 "$X_RC:$(field 'd["precheck_used"]')" "0:true" "an explicit --precheck outside the batch directory is the one consulted"
# slice data the record carries
printf '{"batch_id":"B-RC","changes":["c-rc"],"slices":[{"slice_id":"S1","lines":[1]}]}\n' > "$RI/batch_s.json"
jv vsl.json '{"round":1,"verdict":"NO-GO","findings":[{"id":"F1","slice_id":"S1","finding_layer":"process-doc"}],"slice_verdicts":[{"slice_id":"S1","verdict":"NO-GO"}]}'
XB="$RI/batch_s.json" rr vsl.json
expect "G-R-SLICE-EMIT#1,G-R-SLICE-VERDICTS-EMIT#1" "$X_RC:$(field '[d["findings"][0].get("slice_id"), d.get("slice_verdicts")]')" \
  '0:["S1", [{"slice_id": "S1", "verdict": "NO-GO"}]]' "a finding's slice_id and the reviewer's slice verdicts are carried into the record"
# classify_finding: same line, different file / same file, different line
printf '{"schema":"precheck/v1","batch_id":"B-RC","all_pass":true,"checks":[{"check":"already-fixed-markers","evidence":{"markers":[{"file":"b.sh","line":87},{"file":"a.sh","line":1}]}}]}\n' > "$RI/pre_mk.json"
jv vmk.json '{"round":1,"verdict":"NO-GO","findings":[{"id":"F1","file":"a.sh","line":87}]}'
rr vmk.json --precheck "$RI/pre_mk.json"
expect "G-CF-MARKER-MATCH#4/#5" "$X_RC:$(field 'd["findings"][0]["class"]')" '0:"judgment"' \
  "a marker on the same line of ANOTHER file, or on another line of the same file, never makes a false-positive"

# --- reviewer / batch binding refusals (record side) ---------------------------
fresh_case rcb
RR_REVIEWER_EFFORT=high rr_genuine "$REC/r1.json" B-RCB c-rcb 1 GO "$NONE" D-RCB
if [ "$RR_RC" -eq 1 ] && grep -q "disagrees with --tier/--effort" "$RR_WORK/r1/record.err"; then
  ok "G-R-REVIEWER-MATCHES-CLI#2: a reviewer effort (high) that disagrees with --effort xhigh is refused (exit 1)"
else bad "G-R-REVIEWER-MATCHES-CLI#2: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi
rm -rf "$RR_WORK/r1"
RR_CHANGES='"c"' RR_V_CHANGES='["c"]' rr_genuine "$REC/r1.json" B-RCB c 1 GO "$NONE" D-RCB2
if [ "$RR_RC" -eq 1 ] && grep -q "covers only what it reviewed" "$RR_WORK/r1/record.err"; then
  ok "G-R-BATCH-CHANGES-OK#1,G-R-BINDING-BATCH#2: a batch whose changes is the STRING \"c\" (sorts to the bound [\"c\"]) is refused"
else bad "G-R-BATCH-CHANGES-OK#1: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi
rm -rf "$RR_WORK/r1"
RR_CHANGES='["c", 5]' RR_V_CHANGES='["c"]' rr_genuine "$REC/r1.json" B-RCB c 1 GO "$NONE" D-RCB3
if [ "$RR_RC" -eq 1 ] && grep -q "covers only what it reviewed" "$RR_WORK/r1/record.err"; then
  ok "G-R-BATCH-CHANGES-OK#2: a batch change list holding a non-string is refused as a binding mismatch, never a TypeError"
else bad "G-R-BATCH-CHANGES-OK#2: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi
rm -rf "$RR_WORK/r1"
RR_BATCH_HEAD=$H40 RR_BATCH_BASE=$B40 rr_genuine "$REC/r1.json" B-RCB c-rcb4 1 GO "$NONE" D-RCB4
if [ "$RR_RC" -eq 0 ]; then ok "G-R-BINDING-COMMITS#2: a batch that declares the SAME review_base/review_head as the binding is accepted (false-refusal guard)"
else bad "G-R-BINDING-COMMITS#2: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi

# --- G-T-DOTDOT#1: ".." in a link target steps back through a directory it does
#     not look anything up in -- a foreign-writable directory merely passed
#     through (".." cannot be replaced by its writers) does not refuse ---------
DD=$(timeout 20 python3 - "$RR_TOOL" "$S" "$ME" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
d, me = os.path.join(sys.argv[2], "dd_probe"), int(sys.argv[3])
os.mkdir(d, 0o755)
fw = os.path.join(d, "fw"); os.mkdir(fw); os.chmod(fw, 0o777)
t = os.path.join(d, "tgt"); open(t, "w").write("x"); os.chmod(t, 0o644)
via = os.path.join(d, "via_dotdot"); os.symlink("fw/../tgt", via)
into = os.path.join(d, "into_fw"); os.symlink("fw/tgt2", into)
t2 = os.path.join(fw, "tgt2"); open(t2, "w").write("y"); os.chmod(t2, 0o644)
pw = lambda u: object()
a = rr._path_tier([via], 65534, me, runner_uid=me + 12345, ranges=[], getpw=pw)[0]
b = rr._path_tier([into], 65534, me, runner_uid=me + 12345, ranges=[], getpw=pw)[0]
print(a, b)
PY
)
if [ "$ME" -eq 0 ]; then echo "NOTE: running as root -- G-T-DOTDOT#1 SKIPPED"
else expect G-T-DOTDOT#1 "$DD" "capability instance" \
  "a link through fw/../tgt with fw mode 777 is capability (control: a file looked up INSIDE the 777 directory is instance)"; fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
