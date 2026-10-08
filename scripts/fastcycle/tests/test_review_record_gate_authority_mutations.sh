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
# Mutations V3-N* are the round-2 reviewer's (V3) surviving non-equivalent
# mutations, re-expressed against the round-2 code with identical semantics;
# R2-* are the round-2 fix's own, one per new guarded condition. O12 is
# re-targeted at the round-2 decision point (a backfill zero-finding GO is
# neutral history, never coverage and never a block).
#
# Not listed (equivalent, recorded in the round-2 fixer report): V3 N3
# (None path), N9 (self-citation: a file cannot contain its own hash), N14
# (label regex: now findall + exactly-one), N15 (precheck_used: missing
# evidence is refused anyway); the explicit 'round is None' message in
# record (refused with exit 2 by the integer check / binding either way);
# the 'root producer' and 'unknown producer' shortcuts in _independence_tier
# (_writable_by already treats uid 0 as all-writable, and a non-int uid is
# refused by the same clause -- they cannot change a tier on any host); the
# read-once/O_NOFOLLOW evidence open (a TOCTOU race is not reproducible
# deterministically in a test).
#
# Usage : bash test_review_record_gate_authority_mutations.sh [MUTATION_ID...]
# Exit  : 0 control GREEN and every mutation KILLED; 1 otherwise; 2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM

SUITES="test_review_record_gate_authority_r1_regression.sh test_review_record_gate_authority_r2_regression.sh test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh"

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
R7-M4	'members.sort(key=lambda rp: rp[0]["round"])'	'members.sort(key=lambda rp: -rp[0]["round"])'
R7-M5	'    if isinstance(value, str) and value in FINDING_LAYERS:\n        return value, None'	'    if isinstance(value, str) and value in FINDING_LAYERS:\n        return ("process-doc" if value == "source-defect" else value), None'
O1-ledger-label	'        if labels[0] != (model, effort):'	'        if False:'
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
O12-backfill-history	'        if rec.get("source") == "backfill":'	'        if False:'
O13-slice-coverage	'if set(got) != wanted or any(v != "GO" for v in got.values()):'	'if False:'
O14-reviewer-required	'if err or reviewer is None:'	'if err:'
O15-record-vs-evidence	'if (rec.get("verdict") != verdict or rec_layers != ev_layers'	'if (False'
O16-owner-uid	'                if node_st.st_uid == producer_uid:'	'                if False:'
O17-hash-compare	'    if not data or hashlib.sha256(data).hexdigest() != evidence_sha256:'	'    if not data:'
O18-containment	'    if common != root_real:\n        return None, None'	'    if False:\n        return None, None'
O19-evidence-round	'    if binding["round"] != rec["round"]:'	'    if False:'
O20-gate-round-budget	'if rec["round"] > ctx["round_budget"]:'	'if False:'
O21-producer-required	'if not isinstance(producer, str) or producer.strip() in ("", "UNKNOWN"):'	'if False:'
O22-slice-go-source-defect	'            if layer is None or layer == "source-defect":'	'            if layer == "source-defect":'
O23-reviewer-matches-cli	'        if reviewer["model"] != a.tier or reviewer["effort"] != a.effort:'	'        if False:'
O24-designated-tier	'if not (reviewer["model"] == DESIGNATED_TIER and reviewer["effort"] == DESIGNATED_EFFORT):'	'if False:'
V3-N1-tier-parent-writable	'                elif _writable_by(node_st, node, producer_uid, gids):'	'                elif False:'
V3-N2-tier-file-writable	'                if child_st is None:\n                    if _writable_by(node_st, node, producer_uid, gids):'	'                if child_st is None:\n                    if False:'
V3-N4-precheck-batch	'if _batch_key(pre.get("batch_id")) != _batch_key(rec.get("batch_id")):'	'if False:'
V3-N6-record-layers	'if (rec.get("verdict") != verdict or rec_layers != ev_layers'	'if (rec.get("verdict") != verdict'
V3-N8-binding-bool-round	'    if not isinstance(rnd, int) or isinstance(rnd, bool) or rnd < 1:'	'    if not isinstance(rnd, int) or rnd < 1:'
V3-N11-gate-producer-is-reviewer	'    if producer == reviewer["dispatch_id"]:\n        return False'	'    if False:\n        return False'
V3-N12-record-model-effort	'            or rec.get("model_tier") != reviewer["model"] or rec.get("effort") != reviewer["effort"]):'	'            or False):'
R2-B1a-record-binding-batch	'        if (batch.get("batch_id") != binding["batch_id"] or not b_ok_changes'	'        if (not b_ok_changes'
R2-B1b-record-binding-changes	'                or sorted(b_changes) != binding["change_ids"]):'	'                or False):'
R2-B2-record-binding-commits	'            if key in batch and batch.get(key) != binding[key]:'	'            if False:'
R2-B3-record-binding-required	'        binding, err = _validated_binding(verdict_doc)\n        if err:'	'        binding, err = _validated_binding(verdict_doc)\n        if False:'
R2-B4-gate-binding-required	'    binding, err = _validated_binding(ev)\n    if err:\n        return False, "verdict evidence %s" % err'	'    binding, err = _validated_binding(ev)\n    if err:\n        binding = {"batch_id": rec["batch_id"], "change_ids": sorted(rec.get("change_ids") or []), "round": rec["round"], "review_base": rec.get("review_base"), "review_head": rec.get("review_head")}'
R2-B5-gate-binding-batch	'    if (_batch_key(binding["batch_id"]) != _batch_key(rec["batch_id"])'	'    if (False'
R2-B6-gate-binding-changes	'            or sorted(rec_changes) != binding["change_ids"]'	'            or False'
R2-B7-gate-binding-head	'            or rec.get("review_head") != binding["review_head"]):'	'            or False):'
R2-B8-gate-binding-base	'            or rec.get("review_base") != binding["review_base"]'	'            or False'
R2-B9-commit-shape	'        if not isinstance(val, str) or not _COMMIT_RE.fullmatch(val):'	'        if not isinstance(val, str):'
R2-C1-open-nogo-in-any-batch-blocks	'        elif not ok:\n            blockers.append'	'        elif False:\n            blockers.append'
R2-C3-dropped-is-not-coverage	'        if ok and is_latest:\n            covering.append'	'        if ok:\n            covering.append'
R2-C4-backfill-nogo-blocks	'            if not (rec.get("verdict") == "GO" and not rec.get("findings")):'	'            if False:'
R2-L1-ledger-bad-events	'    if bad:\n        return "dispatch-ledger events'	'    if False:\n        return "dispatch-ledger events'
R2-L2-ledger-dispatched-row	'    if "dispatched" not in events:'	'    if False:'
R2-L3-ledger-latest-complete	'    if events[-1] != "complete":'	'    if False:'
R2-L4-ledger-one-label	'        if len(labels) != 1:'	'        if False:'
R2-T1-tier-sticky-exemption	'                    if not (node_st.st_mode & stat.S_ISVTX and child_st.st_uid != producer_uid):'	'                    if True:'
R2-T2-tier-acl	'    return _has_acl(path)'	'    return False'
R2-T3-tier-vs-runner-uid	'    gids = _uid_gids(producer_uid)\n'	'    producer_uid = os.geteuid() + 1\n    gids = _uid_gids(producer_uid)\n'
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
