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
# Scope (V3 round 4, R4-F3 -- REPLACED, not extended): every guard SUB-CLAUSE
# is now mutated mechanically by test_review_record_subclause_sweep.sh (one
# AST-derived mutant per and/or operand of every decision construct in the
# call graph of cmd_gate/cmd_record), so the round-1..3 FIXER-authored
# mutations (O1..O24, R2-*, G-*-off) that the sweep subsumes were removed
# from this list. What remains here is what the sweep cannot generate:
#   R7-M1..M5      the round-1 reviewer's (R7 B2) VERBATIM;
#   V3-N4/6/8/11/12 the round-2 reviewer's surviving non-equivalent ones;
#   R3-M1..M11     the round-3 reviewer's (zz_r3_reviewer_mutations.sh);
#   R4-A..R4-I     the round-4 reviewer's (zz_r4_reviewer_mutations.sh)
#                  VERBATIM, except R4-C (re-expressed: its target line --
#                  the per-unit tier path list -- was REPLACED by the whole-
#                  store walk; the re-expression drops every non-record file
#                  from that walk, the same defect on the new structure);
#   G-T-LINK-EDGE-off, G-E-NONBLOCK-off   data-flow guards (not decision
#                  constructs) bound to these by the guard table.
# Obsoleted by structural replacement this round (their target code no
# longer exists; the replacing code's sub-clauses are swept): V3-N1/N2
# (_principal_can_replace), R3-M4/M5 (_uid_gids / group membership -- any
# group write is now foreign), R3-M8 (_aggregate_tier -- one store tier per
# run), R4-B (the ev_reals merge line -- ev_reals is consumed only before the
# merge, by _orphaned_evidence).
# EQUIVALENT (recorded in the guard table with the reason): R3-M12 (merge
# representative), R4-G (".." in _resolution_chain: `cur` is always reached
# by descent from /, so the parent is already in `dirs` -- the reviewer's
# own classification).
#
# Usage : bash test_review_record_gate_authority_mutations.sh [MUTATION_ID...]
# Exit  : 0 control GREEN and every mutation KILLED; 1 otherwise; 2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM

SUITES="test_review_record_gate_authority_r4_regression.sh test_review_record_gate_authority_r3_regression.sh test_review_record_gate_authority_r1_regression.sh test_review_record_gate_authority_r2_regression.sh test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh"

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
V3-N4-precheck-batch	'if _batch_key(pre.get("batch_id")) != _batch_key(rec.get("batch_id")):'	'if False:'
V3-N6-record-layers	'if (rec.get("verdict") != verdict or rec_layers != ev_layers'	'if (rec.get("verdict") != verdict'
V3-N8-binding-bool-round	'    if not isinstance(rnd, int) or isinstance(rnd, bool) or rnd < 1:'	'    if not isinstance(rnd, int) or rnd < 1:'
V3-N11-gate-producer-is-reviewer	'    if producer == reviewer["dispatch_id"]:\n        return False'	'    if False:\n        return False'
V3-N12-record-model-effort	'            or rec.get("model_tier") != reviewer["model"] or rec.get("effort") != reviewer["effort"]):'	'            or False):'
R3-M1-earliest-listing	'rec, path = listing[-1]'	'rec, path = listing[0]'
R3-M2-latest-always	'is_latest = rec is live[-1][0]'	'is_latest = True'
R3-M3-batchkey-str	'    return _canon(batch_id)'	'    return str(batch_id)'
R3-M6-label-last-row-only	'    for _ev, desc in rows:'	'    for _ev, desc in rows[-1:]:'
R3-M7-missing-event-is-complete	'event = row.get("event") if isinstance(row.get("event"), str) else None'	'event = row.get("event") if isinstance(row.get("event"), str) else "complete"'
R3-M9-record-base-unchecked	'        for key in ("review_base", "review_head"):'	'        for key in ("review_head",):'
R3-M10-collect-bool-round	'            if not isinstance(rnd, int) or isinstance(rnd, bool):'	'            if not isinstance(rnd, int):'
R3-M11-complete-anywhere	'    if events[-1] != "complete":'	'    if "complete" not in events:'
R4-A-merge-paths-dropped	'        merged["paths"] = sorted({p for r, _p in members for p in r["paths"]})\n'	'        merged["paths"] = list(merged["paths"])\n'
R4-C-store-tier-records-only	'        paths.extend(os.path.join(dirpath, n) for n in sorted(dirnames) + sorted(filenames))'	'        paths.extend(os.path.join(dirpath, n) for n in sorted(filenames) if n.endswith(".json"))'
R4-D-ledger-dupkey-ignored	'            except _DuplicateKeyError:\n                raise\n'	'            except _DuplicateKeyError:\n                continue\n'
R4-E-evidence-dupkey-allowed	'        doc = json.loads(data.decode("utf-8"), object_pairs_hook=_strict_object)'	'        doc = json.loads(data.decode("utf-8"))'
R4-F-record-dispatch-unchecked	'            or rec.get("reviewer_dispatch_id") != reviewer["dispatch_id"]\n'	'            or False\n'
R4-H-dispatch-reuse-ignores-batch	'used.setdefault(reviewer["dispatch_id"], set()).add((_batch_key(rec["batch_id"]), rec["round"]))'	'used.setdefault(reviewer["dispatch_id"], set()).add((rec["round"],))'
R4-I-binding-padding-allowed	'    if not isinstance(bid, str) or not bid.strip() or bid != bid.strip():'	'    if not isinstance(bid, str) or not bid.strip():'
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
