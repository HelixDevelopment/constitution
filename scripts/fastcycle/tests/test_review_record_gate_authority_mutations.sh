#!/bin/bash
# test_review_record_gate_authority_mutations.sh
#
# Paired-mutation runner (constitution 1.1 / 11.4.115(F) / 11.4.276(D)) for the
# review_record.py verdict-authority fix (T048 restart round 1, R7 B1/B2).
#
# For EVERY mutation below: a scratch mirror of the fastcycle review/ + the
# review_record test suites is built, ONE exact-text mutation is applied to
# the mirror's review_record.py (the mutation must match EXACTLY one site, else it is
# an ERROR -- a mutation that no longer applies proves nothing), and the
# review_record suites are run against the mirror. KILLED = at least one suite
# exits non-zero. The runner FAILS on any SURVIVED or ERROR mutation, and on a
# control (unmutated) mirror that is not fully GREEN (a red control makes every
# "kill" meaningless). The live tree is never modified.
#
# Mutation sets (every id below is bound to a guard by the guard table in
# test_review_record_guard_table.sh, which FAILS when a guard lacks a case or
# a mutation, or when a mutation does not land on its guard's source lines):
#   R7-M1..M5   the round-1 reviewer's own five (R7 B2);
#   O1..O24     the round-1 fixer's, one per guarded condition;
#   V3-N*       the round-2 reviewer's surviving non-equivalent mutations;
#   R2-*        the round-2 fixer's, one per new guarded condition;
#   R3-M1..M11  the round-3 reviewer's (zz_r3_reviewer_mutations.sh) VERBATIM;
#   G-*-off     the round-3 structural fixer's: one per guard tag that no
#               earlier mutation isolated (each disables exactly the `if`
#               under its "# guard: <id>" tag).
# Re-expressed in round 3 (same semantics, the code moved to the record-as-
# pointer admission / three-principal tier): O2 (live body_hash, now in
# _admit_live), O14 (reviewer required, now on the admitted unit), O16 ->
# leaf owner, V3-N1 -> writable chain directory, V3-N2 -> writable leaf,
# R2-B4 -> admission binding required, R2-T1 -> sticky exemption, R2-T3 ->
# the runner principal (was "rate vs producer, not runner"; the round-3 model
# rates BOTH).
#
# EQUIVALENT (not run; each recorded in the guard table with its reason):
#   R3-M12 (dedupe keeps the last path) -- byte-identical copies now MERGE
#     into one unit carrying every copy's paths, and every copy is admitted
#     on its own first, so the representative chosen cannot change any
#     decision (R3-M12a/b prove the order independence directly);
#   G-E-HASH-SHAPE -- a value that is not 64 lowercase hex can never equal a
#     sha256 hexdigest, so G-E-HASH-MATCH refuses the same inputs;
#   G-E-SELF-CITATION -- a file cannot carry its own content hash (V3 N9);
#   G-E-REGULAR -- with O_NONBLOCK, a directory read raises (caught) and a
#     FIFO reads empty (refused by G-E-HASH-MATCH); device nodes need root
#     to create inside --records.
# Also not listed (unchanged from round 2): N14 (label regex is findall +
# exactly-one), N15 (precheck_used: missing evidence is refused anyway).
#
# Usage : bash test_review_record_gate_authority_mutations.sh [MUTATION_ID...]
# Exit  : 0 control GREEN and every mutation KILLED; 1 otherwise; 2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM

SUITES="test_review_record_gate_authority_r3_regression.sh test_review_record_gate_authority_r1_regression.sh test_review_record_gate_authority_r2_regression.sh test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh"

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
O2-body-hash	'    # guard: G-A-BODY-HASH\n    if rec.get("body_hash") != _body_hash_of(rec):'	'    # guard: G-A-BODY-HASH\n    if False:'
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
O14-reviewer-required	'    if reviewer is None:\n        return False, "verdict evidence names no reviewer'	'    if False:\n        return False, "verdict evidence names no reviewer'
O15-record-vs-evidence	'if (rec.get("verdict") != verdict or rec_layers != ev_layers'	'if (False'
O16-leaf-owner	'    if leaf_st.st_uid == uid:'	'    if False:'
O17-hash-compare	'    if not data or hashlib.sha256(data).hexdigest() != evidence_sha256:'	'    if not data:'
O18-containment	'    if common != root_real:\n        return None, None'	'    if False:\n        return None, None'
O19-evidence-round	'    if binding["round"] != rec["round"]:'	'    if False:'
O20-gate-round-budget	'if rec["round"] > ctx["round_budget"]:'	'if False:'
O21-producer-required	'if not isinstance(producer, str) or producer.strip() in ("", "UNKNOWN"):'	'if False:'
O22-slice-go-source-defect	'            if layer is None or layer == "source-defect":'	'            if layer == "source-defect":'
O23-reviewer-matches-cli	'        if reviewer["model"] != a.tier or reviewer["effort"] != a.effort:'	'        if False:'
O24-designated-tier	'if not (reviewer["model"] == DESIGNATED_TIER and reviewer["effort"] == DESIGNATED_EFFORT):'	'if False:'
V3-N1-tier-dir-writable	'        if _writable_by(dst, dpath, uid, gids) and not'	'        if False and not'
V3-N2-tier-leaf-writable	'    if _writable_by(leaf_st, leaf, uid, gids):'	'    if False:'
V3-N4-precheck-batch	'if _batch_key(pre.get("batch_id")) != _batch_key(rec.get("batch_id")):'	'if False:'
V3-N6-record-layers	'if (rec.get("verdict") != verdict or rec_layers != ev_layers'	'if (rec.get("verdict") != verdict'
V3-N8-binding-bool-round	'    if not isinstance(rnd, int) or isinstance(rnd, bool) or rnd < 1:'	'    if not isinstance(rnd, int) or rnd < 1:'
V3-N11-gate-producer-is-reviewer	'    if producer == reviewer["dispatch_id"]:\n        return False'	'    if False:\n        return False'
V3-N12-record-model-effort	'            or rec.get("model_tier") != reviewer["model"] or rec.get("effort") != reviewer["effort"]):'	'            or False):'
R2-B1a-record-binding-batch	'        if (batch.get("batch_id") != binding["batch_id"] or not b_ok_changes'	'        if (not b_ok_changes'
R2-B1b-record-binding-changes	'                or sorted(b_changes) != binding["change_ids"]):'	'                or False):'
R2-B2-record-binding-commits	'            if key in batch and batch.get(key) != binding[key]:'	'            if False:'
R2-B3-record-binding-required	'        binding, err = _validated_binding(verdict_doc)\n        if err:'	'        binding, err = _validated_binding(verdict_doc)\n        if False:'
R2-B4-gate-binding-required	'    # guard: G-A-BINDING-PRESENT\n    if err:'	'    # guard: G-A-BINDING-PRESENT\n    if False:'
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
R2-T1-tier-sticky-exemption	'_writable_by(dst, dpath, uid, gids) and not (dst.st_mode & stat.S_ISVTX and child_st.st_uid != uid)'	'_writable_by(dst, dpath, uid, gids)'
R2-T2-tier-acl	'    return _has_acl(path)'	'    return False'
R2-T3-tier-runner-principal	'principals = ((producer_uid, producer_gids), (runner_uid, _uid_gids(runner_uid)))'	'principals = ((producer_uid, producer_gids),)'
R3-M1-earliest-listing	'rec, path = listing[-1]'	'rec, path = listing[0]'
R3-M2-latest-always	'is_latest = rec is members[-1][0]'	'is_latest = True'
R3-M3-batchkey-str	'    return _canon(batch_id)'	'    return str(batch_id)'
R3-M4-primary-group-only	'    gids = {pw.pw_gid}\n'	'    gids = {pw.pw_gid}\n    return gids\n'
R3-M5-unknown-groups-not-conservative	'if mode & stat.S_IWGRP and (gids is None or st.st_gid in gids):'	'if mode & stat.S_IWGRP and (gids is not None and st.st_gid in gids):'
R3-M6-label-last-row-only	'    for _ev, desc in rows:'	'    for _ev, desc in rows[-1:]:'
R3-M7-missing-event-is-complete	'event = row.get("event") if isinstance(row.get("event"), str) else None'	'event = row.get("event") if isinstance(row.get("event"), str) else "complete"'
R3-M8-tier-report-any	'tier = "capability" if all('	'tier = "capability" if any('
R3-M9-record-base-unchecked	'        for key in ("review_base", "review_head"):'	'        for key in ("review_head",):'
R3-M10-collect-bool-round	'            if not isinstance(rnd, int) or isinstance(rnd, bool):'	'            if not isinstance(rnd, int):'
R3-M11-complete-anywhere	'    if events[-1] != "complete":'	'    if "complete" not in events:'
G-T-ROOT-off	'    # guard: G-T-ROOT\n    if uid == 0:'	'    # guard: G-T-ROOT\n    if False:'
G-T-OWNER-BIT-off	'    # guard: G-T-OWNER-BIT\n    if st.st_uid == uid and mode & stat.S_IWUSR:'	'    # guard: G-T-OWNER-BIT\n    if False:'
G-T-GROUP-BIT-off	'    # guard: G-T-GROUP-BIT\n    if mode & stat.S_IWGRP and (gids is None or st.st_gid in gids):'	'    # guard: G-T-GROUP-BIT\n    if False:'
G-T-OTHER-BIT-off	'    # guard: G-T-OTHER-BIT\n    if mode & stat.S_IWOTH:'	'    # guard: G-T-OTHER-BIT\n    if False:'
G-T-DIR-OWNER-off	'        # guard: G-T-DIR-OWNER\n        if dst.st_uid == uid:'	'        # guard: G-T-DIR-OWNER\n        if False:'
G-T-PRODUCER-IS-RUNNER-off	'    # guard: G-T-PRODUCER-IS-RUNNER\n    if producer_uid == runner_uid:'	'    # guard: G-T-PRODUCER-IS-RUNNER\n    if False:'
G-T-PRODUCER-KNOWN-off	'    # guard: G-T-PRODUCER-KNOWN\n    if producer_gids is None:'	'    # guard: G-T-PRODUCER-KNOWN\n    if False:'
G-T-PATH-PRESENT-off	'            # guard: G-T-PATH-PRESENT\n            if path is None:'	'            # guard: G-T-PATH-PRESENT\n            if False:'
G-T-PRINCIPAL-CAN-REPLACE-off	'                # guard: G-T-PRINCIPAL-CAN-REPLACE\n                if _principal_can_replace(chain, uid, gids):'	'                # guard: G-T-PRINCIPAL-CAN-REPLACE\n                if False:'
G-C-CONTAINED-off	'            # guard: G-C-CONTAINED\n            if os.path.commonpath([root_real, real]) != root_real:'	'            # guard: G-C-CONTAINED\n            if False:'
G-C-PARSE-off	'            # guard: G-C-PARSE\n            if err:'	'            # guard: G-C-PARSE\n            if False:'
G-C-OBJECT-off	'            # guard: G-C-OBJECT\n            if not isinstance(doc, dict):'	'            # guard: G-C-OBJECT\n            if False:'
G-C-REQUIRED-off	'            # guard: G-C-REQUIRED\n            if missing:'	'            # guard: G-C-REQUIRED\n            if False:'
G-A-EVIDENCE-VERIFIED-off	'    # guard: G-A-EVIDENCE-VERIFIED\n    if ev is None:'	'    # guard: G-A-EVIDENCE-VERIFIED\n    if False:'
G-A-EVIDENCE-WELLFORMED-off	'    # guard: G-A-EVIDENCE-WELLFORMED\n    if verdict not in ("GO", "NO-GO") or not isinstance(findings, list):'	'    # guard: G-A-EVIDENCE-WELLFORMED\n    if False:'
G-A-REVIEWER-WELLFORMED-off	'    # guard: G-A-REVIEWER-WELLFORMED\n    if err:'	'    # guard: G-A-REVIEWER-WELLFORMED\n    if False:'
G-A-EVIDENCE-OBJECT-off	'    # guard: G-A-EVIDENCE-OBJECT\n    if not isinstance(doc, dict):'	'    # guard: G-A-EVIDENCE-OBJECT\n    if False:'
G-A-SOURCE-off	'    # guard: G-A-SOURCE\n    if source != "backfill":'	'    # guard: G-A-SOURCE\n    if False:'
G-B-BODY-HASH-off	'    # guard: G-B-BODY-HASH\n    if rec.get("body_hash") != _body_hash_of(rec):'	'    # guard: G-B-BODY-HASH\n    if False:'
G-B-NO-LIVE-FIELDS-off	'    # guard: G-B-NO-LIVE-FIELDS\n    if carried:'	'    # guard: G-B-NO-LIVE-FIELDS\n    if False:'
G-B-CHANGES-SHAPE-off	'    # guard: G-B-CHANGES-SHAPE\n    if cids != "UNKNOWN" and (not isinstance(cids, list) or any(not isinstance(c, str) for c in cids)):'	'    # guard: G-B-CHANGES-SHAPE\n    if False:'
G-O-ORPHAN-off	'            # guard: G-O-ORPHAN\n            if fn.endswith(_VERDICT_EVIDENCE_SUFFIX) and os.path.realpath(path) not in referenced:'	'            # guard: G-O-ORPHAN\n            if False:'
G-L-PRESENT-off	'    # guard: G-L-PRESENT\n    if not path:'	'    # guard: G-L-PRESENT\n    if False:'
G-L-HAS-ROWS-off	'    # guard: G-L-HAS-ROWS\n    if not rows:'	'    # guard: G-L-HAS-ROWS\n    if False:'
G-Q-LEDGER-READABLE-off	'    # guard: G-Q-LEDGER-READABLE\n    if ctx["ledger"] is None:'	'    # guard: G-Q-LEDGER-READABLE\n    if False:'
G-Q-LEDGER-AUTH-off	'    # guard: G-Q-LEDGER-AUTH\n    if reason:'	'    # guard: G-Q-LEDGER-AUTH\n    if False:'
G-Q-PRECHECK-USED-off	'    # guard: G-Q-PRECHECK-USED\n    if record.get("precheck_used") is not True:'	'    # guard: G-Q-PRECHECK-USED\n    if False:'
G-Q-PRECHECK-VERIFIED-off	'        # guard: G-Q-PRECHECK-VERIFIED\n        if pre is None:'	'        # guard: G-Q-PRECHECK-VERIFIED\n        if False:'
G-G-CHANGE-NAMED-off	'    # guard: G-G-CHANGE-NAMED\n    if not targets:'	'    # guard: G-G-CHANGE-NAMED\n    if False:'
G-G-BUDGET-RANGE-off	'    # guard: G-G-BUDGET-RANGE\n    if err:'	'    # guard: G-G-BUDGET-RANGE\n    if False:'
G-G-RECORDS-DIR-off	'    # guard: G-G-RECORDS-DIR\n    if not os.path.isdir(a.records):'	'    # guard: G-G-RECORDS-DIR\n    if False:'
G-G-ADMISSION-off	'    # guard: G-G-ADMISSION\n    if failures:'	'    # guard: G-G-ADMISSION\n    if False:'
G-G-ORPHANS-off	'    # guard: G-G-ORPHANS\n    if orphans:'	'    # guard: G-G-ORPHANS\n    if False:'
G-G-CONFLICTS-off	'    # guard: G-G-CONFLICTS\n    if conflicts:'	'    # guard: G-G-CONFLICTS\n    if False:'
G-E-NAMED-off	'    # guard: G-E-NAMED\n    if not isinstance(evidence, str) or not evidence.strip():'	'    # guard: G-E-NAMED\n    if False:'
G-E-PLACEHOLDER-off	'    # guard: G-E-PLACEHOLDER\n    if evidence.strip().upper() in ("UNKNOWN", "N/A", "TBD"):'	'    # guard: G-E-PLACEHOLDER\n    if False:'
G-RV-OBJECT-off	'    # guard: G-RV-OBJECT\n    if not isinstance(rv, dict):'	'    # guard: G-RV-OBJECT\n    if False:'
G-RV-FIELDS-off	'        # guard: G-RV-FIELDS\n        if not isinstance(val, str) or not val.strip():'	'        # guard: G-RV-FIELDS\n        if False:'
G-BD-PRESENT-off	'    # guard: G-BD-PRESENT\n    if missing:'	'    # guard: G-BD-PRESENT\n    if False:'
G-BD-BATCH-SHAPE-off	'    # guard: G-BD-BATCH-SHAPE\n    if not isinstance(bid, str) or not bid.strip() or bid != bid.strip():'	'    # guard: G-BD-BATCH-SHAPE\n    if False:'
G-BD-CHANGES-DISTINCT-off	'    # guard: G-BD-CHANGES-DISTINCT\n    if len(set(cids)) != len(cids):'	'    # guard: G-BD-CHANGES-DISTINCT\n    if False:'
G-R-DESIGNATED-TIER-off	'    # guard: G-R-DESIGNATED-TIER\n    if a.tier != DESIGNATED_TIER or (not effort_capability_gap and a.effort != DESIGNATED_EFFORT):'	'    # guard: G-R-DESIGNATED-TIER\n    if False:'
G-T-PRODUCER-DECLARED-off	'    # guard: G-T-PRODUCER-DECLARED\n    if (producer_uid is None or isinstance(producer_uid, bool)\n            or not isinstance(producer_uid, int) or producer_uid <= 0):'	'    # guard: G-T-PRODUCER-DECLARED\n    if False:'
G-BD-CHANGES-SHAPE-off	'    # guard: G-BD-CHANGES-SHAPE\n    if (not isinstance(cids, list) or not cids'	'    # guard: G-BD-CHANGES-SHAPE\n    if (False'
G-G-UNCOVERED-off	'        if blockers or not covering:'	'        if blockers:'
G-T-LINK-EDGE-off	'        # guard: G-T-LINK-EDGE\n        edges.append((cur, st))\n'	'        # guard: G-T-LINK-EDGE\n        if not stat.S_ISLNK(st.st_mode):\n            edges.append((cur, st))\n'
G-E-NONBLOCK-off	'os.O_RDONLY | os.O_NONBLOCK | getattr'	'os.O_RDONLY | getattr'
EOF

apply_mutation() { # apply_mutation FILE OLD_PYLIT NEW_PYLIT -> 0 applied, 1 marker miss
  python3 - "$1" "$2" "$3" <<'PY'
import ast, sys
path, old, new = sys.argv[1], ast.literal_eval(sys.argv[2]), ast.literal_eval(sys.argv[3])
src = open(path, encoding="utf-8").read()
if src.count(old) != 1:  # absent, or ambiguous (would mutate more than one site)
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
    echo "NOT ok $id ERROR (MARKER_MISS: mutation target text not found exactly once -- re-derive it)"
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
