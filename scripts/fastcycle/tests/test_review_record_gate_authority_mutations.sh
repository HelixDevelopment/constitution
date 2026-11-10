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
# is now mutated mechanically by sweep_review_record_subclauses.sh (one
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
#                  constructs) bound to these by the guard table;
#   RVR1/RVR3b     the round-3 reviewer's store-tier ledger mutants;
#   RF-chain-*     CON-033 round 4 (structural): refactor-style rewrites of
#                  _resolution_chain (realpath/abspath first, an unresolved
#                  relative start, "." as a lookup, a dropped trailing slash,
#                  a reordered walk, edges kept for the leaf only, the last
#                  or first link edge dropped, only the deepest directory
#                  checked, an absolute link target resolved from `cur`).
#                  The sweep flips one operand at a time and cannot write
#                  these; test_review_record_resolution_ground_truth.sh (a
#                  kernel oracle: os.stat for the leaf, an openat walk for
#                  every directory and entry) kills them.
# Obsoleted by structural replacement this round (their target code no
# longer exists; the replacing code's sub-clauses are swept): V3-N1/N2
# (_principal_can_replace), R3-M4/M5 (_uid_gids / group membership -- any
# group write is now foreign), R3-M8 (_aggregate_tier -- one store tier per
# run), R4-B (the ev_reals merge line -- ev_reals is consumed only before the
# merge, by _orphaned_evidence).
# EQUIVALENT (recorded in the guard table with the reason): R3-M12 (merge
# representative). R4-G (".." in _resolution_chain) was listed equivalent
# until CON-033 round 4; the walk now follows the kernel (".." looks up the
# parent of the directory reached so far, after symlinks), and the sweep's
# G-T-DOTDOT#1 mutant is killed by the ground-truth suite, so the claim is
# withdrawn.
#
# R4-C and the environment (CON-033 round 2, review I4): the R4-CAP cases of
# the r4 suite, which kill R4-C, need `podman unshare` AND a writable
# directory whose whole chain is root-owned; with TMPDIR under a home
# directory there is none, they SKIP, and R4-C survived every suite. The
# first suite below, test_review_record_store_tier_all_entries_regression.sh,
# kills R4-C with no podman and no root-owned chain (in-process, injected
# runner uid, chmod only); since CON-033 round 3 (review R2-F2) it also
# kills RVM-B / RVM-B2 (the dispatch ledger or the records directory dropped
# from the store roots, guard G-T-STORE-ROOTS), which only R4-CAP5 killed
# before. test_review_record_guard_table.sh is deliberately
# NOT a suite here: its kill-ledger freshness check (M4) fails on ANY edit of
# review_record.py, so it would "kill" every mutant by construction and prove
# nothing (section 11.4.245, 11.4.201).
#
# Usage : bash test_review_record_gate_authority_mutations.sh [MUTATION_ID...]
# Exit  : 0 control GREEN and every mutation KILLED; 77 every mutation KILLED
#         but a control suite skipped proof legs (SKIP, not PASS); 1 otherwise;
#         2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM

SUITES="test_review_record_store_tier_all_entries_regression.sh test_review_record_resolution_ground_truth.sh test_review_record_round_budget_boundary_regression.sh test_review_record_gate_authority_r4_regression.sh test_review_record_gate_authority_r3_regression.sh test_review_record_gate_authority_r1_regression.sh test_review_record_gate_authority_r2_regression.sh test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh"

build_mirror() { # build_mirror DIR
  mkdir -p "$1/review" "$1/tests/lib" "$1/tests/fixtures"
  cp "$FC/review/review_record.py" "$1/review/"
  cp "$HERE/lib/review_record_genuine.sh" "$1/tests/lib/"
  cp -r "$HERE/fixtures/review_record" "$HERE/fixtures/review_record_finding_layer" "$1/tests/fixtures/"
  for t in $SUITES; do cp "$HERE/$t" "$1/tests/"; done
}

# Suite status (CON-033 round 3, review R2-F3): a suite exits 0 (PASS), 77
# (SKIP: every check that ran passed, but a proof leg could not run on this
# host) or anything else (FAIL). The control must be 0 or 77 for every suite;
# a 77 is reported, and makes the runner's own result SKIP (exit 77), never
# PASS. A mutant is KILLED by a suite whose status DIFFERS from the control's
# status for that suite: a 77 on both is not a kill (nothing more ran), and a
# 0 on a suite the control skipped is not a pass either way.
run_control() { # run_control DIR -> writes $S/control.rc ("suite rc" lines)
  local t rc
  : > "$S/control.rc"
  for t in $SUITES; do
    timeout 300 bash "$1/tests/$t" >"$1/$t.log" 2>&1; rc=$?
    echo "$t $rc" >> "$S/control.rc"
  done
}
run_suites() { # run_suites DIR -> prints "suite (rc N, control M)" of the first suite whose status differs from the control's (empty if none)
  local t rc want
  for t in $SUITES; do
    timeout 300 bash "$1/tests/$t" >"$1/$t.log" 2>&1; rc=$?
    want=$(awk -v t="$t" '$1==t {print $2}' "$S/control.rc")
    if [ "$rc" != "$want" ]; then
      echo "$t (rc $rc, control $want)"
      return 0
    fi
  done
  return 0
}

# CON-033 round 2 adopted the reviewer's mutants RM1..RM3 (section 11.4.276(D)):
# RM1 (gate and record side: refuse the last legal round) is killed by
# test_review_record_round_budget_boundary_regression.sh; RM2 and RM3 by the r1/r4
# suites (reviewer's run). RM4 (G-V-BACKFILL-SUPERSEDED `>` to `>=`) is NOT listed:
# it is EQUIVALENT by reading. The two operators differ only when a live and a
# backfill unit of one batch have the same round; _gate_same_round_conflicts()
# runs before the decision phase and leaves at most one unit per
# (batch key, round) -- different bodies exit 4 (G-G-CONFLICTS), identical bodies
# merge into one unit, which cannot be both live and backfill. Not confirmed by
# execution.
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
RVM-B-store-tier-ledger-dropped	'    paths = [records_dir, ledger_path]'	'    paths = [records_dir]'
RVM-B2-store-tier-records-dir-dropped	'    paths = [records_dir, ledger_path]'	'    paths = [ledger_path]'
R4-D-ledger-dupkey-ignored	'            except _DuplicateKeyError:\n                raise\n'	'            except _DuplicateKeyError:\n                continue\n'
R4-E-evidence-dupkey-allowed	'        doc = json.loads(data.decode("utf-8"), object_pairs_hook=_strict_object)'	'        doc = json.loads(data.decode("utf-8"))'
R4-F-record-dispatch-unchecked	'            or rec.get("reviewer_dispatch_id") != reviewer["dispatch_id"]\n'	'            or False\n'
R4-H-dispatch-reuse-ignores-batch	'used.setdefault(reviewer["dispatch_id"], set()).add((_batch_key(rec["batch_id"]), rec["round"]))'	'used.setdefault(reviewer["dispatch_id"], set()).add((rec["round"],))'
R4-I-binding-padding-allowed	'    if not isinstance(bid, str) or not bid.strip() or bid != bid.strip():'	'    if not isinstance(bid, str) or not bid.strip():'
G-T-LINK-EDGE-off	'        # guard: G-T-LINK-EDGE\n        edges.append((cur, st))\n'	'        # guard: G-T-LINK-EDGE\n        if not stat.S_ISLNK(st.st_mode):\n            edges.append((cur, st))\n'
G-E-NONBLOCK-off	'os.O_RDONLY | os.O_NONBLOCK | getattr'	'os.O_RDONLY | getattr'
RM1-gate-round-budget-last-round	'    if rec["round"] > ctx["round_budget"]:'	'    if rec["round"] >= ctx["round_budget"]:'
RM1-record-round-budget-last-round	'    if a.round > budget:'	'    if a.round >= budget:'
RM2-dispatch-reuse-limit	'    if len(ctx["dispatch_use"].get(reviewer["dispatch_id"], ())) > 1:'	'    if len(ctx["dispatch_use"].get(reviewer["dispatch_id"], ())) > 2:'
RM3-subid-range-start	'        if start <= owner_uid < start + count:'	'        if start < owner_uid < start + count:'
RVR3b-store-tier-ledger-realpath	'    paths = [records_dir, ledger_path]'	'    paths = [records_dir, os.path.realpath(ledger_path) if ledger_path else ledger_path]'
RVR1-store-tier-ledger-dirname	'    paths = [records_dir, ledger_path]'	'    paths = [records_dir, os.path.dirname(ledger_path)]'
RF-chain-realpath-first	'    start = path if path.startswith("/") else os.getcwd() + "/" + path\n'	'    start = os.path.realpath(path)\n'
RF-chain-abspath-lexical	'    start = path if path.startswith("/") else os.getcwd() + "/" + path\n'	'    start = os.path.abspath(path)\n'
RF-chain-relative-unresolved	'    start = path if path.startswith("/") else os.getcwd() + "/" + path\n'	'    start = "/" + path\n'
RF-chain-dot-is-lookup	'        if comp == ".":\n            continue\n'	'        if False:\n            continue\n'
RF-chain-trailing-slash-dropped	'    if text.endswith("/"):\n'	'    if False:\n'
RF-chain-link-target-trailing-dropped	'            pending = _path_components(target) + pending\n'	'            pending = [c for c in target.split("/") if c] + pending\n'
RF-chain-walk-reordered	'        comp = pending.pop(0)\n'	'        comp = pending.pop()\n'
RF-chain-edges-leaf-only	'        edges.append((cur, st))\n'	'        if not pending:\n            edges.append((cur, st))\n'
RF-chain-edges-drop-last	'    for dpath, child_st in edges:\n'	'    for dpath, child_st in edges[:-1]:\n'
RF-chain-edges-drop-first-link	'        # guard: G-T-LINK-EDGE\n        edges.append((cur, st))\n'	'        # guard: G-T-LINK-EDGE\n        if not (stat.S_ISLNK(st.st_mode) and hops == 0):\n            edges.append((cur, st))\n'
RF-chain-dirs-last-only	'    for dpath, dst in sorted(dirs.items()):\n'	'    for dpath, dst in sorted(dirs.items())[-1:]:\n'
RF-chain-abs-target-from-cur	'            if target.startswith("/"):\n                cur = "/"\n'	'            if target.startswith("/"):\n                cur = cur\n'
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
run_control "$S/control"
CONTROL_SKIP=""
while read -r t rc; do
  case "$rc" in
    0) ;;
    77) CONTROL_SKIP="$CONTROL_SKIP $t"
        echo "SKIP control: $t skipped proof legs on this host: $(grep '^SKIP: ' "$S/control/$t.log" | cut -d' ' -f2 | tr '\n' ' ')" ;;
    *) echo "NOT ok control mirror is RED at $t (rc $rc) -- kills would be meaningless"
       tail -20 "$S/control/$t.log"
       exit 1 ;;
  esac
done < "$S/control.rc"
if [ -z "$CONTROL_SKIP" ]; then echo "ok control mirror GREEN across: $SUITES"
else echo "ok control mirror GREEN (no suite failed) across: $SUITES -- with skipped proof legs in:$CONTROL_SKIP"; fi

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
if [ "$FAIL" -eq 0 ] && [ -n "$CONTROL_SKIP" ]; then
  echo "== all mutations KILLED, but the control skipped proof legs in:$CONTROL_SKIP (SKIP, not PASS) =="
  echo "SKIP reason=control_proof_legs_skipped"; exit 77
fi
[ "$FAIL" -eq 0 ] && { echo "== all mutations KILLED =="; exit 0; }
echo "== mutation runner FAILED (see NOT ok lines) =="; exit 1
