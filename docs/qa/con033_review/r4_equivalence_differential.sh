#!/usr/bin/env bash
# r4_equivalence_differential.sh -- CON-033 round 4: refute-by-differential
# every EQUIVALENT claim in
# scripts/fastcycle/tests/fixtures/review_record_equivalent_subclauses.tsv.
#
# For each claimed-equivalent sub-clause (and one positive-control sub-clause
# per guarded function, one the kill ledger lists KILLED) it compares the
# original tool with the mutant in three ways:
#   1. corpus, function level: every call of the guarded function made while
#      the 12 review_record suites run (r4_eq_trace.py);
#   2. corpus, CLI level: every main(argv) invocation of those suites,
#      replayed on the mutant in a forked child (exit status, stdout, stderr,
#      written body);
#   3. crafted grids (r4_eq_grid.py): direct function-input grids and crafted
#      CLI invocations aimed at each claim's reasoning.
# A claim is REFUTED at a level when at least one input differs there. A
# control that shows no difference at any level means the harness is blind,
# and the run fails.
#
# Usage: bash r4_equivalence_differential.sh OUTDIR
#   Writes OUTDIR/summary.tsv, OUTDIR/corpus/*.json, OUTDIR/grid.json,
#   OUTDIR/suites_{control,traced}.tsv. Exit 0 = ran and every control saw a
#   difference; 1 = a control was blind, or tracing changed a suite status;
#   2 = setup error. The verdict per claim is in summary.tsv; it is a
#   measurement, not a pass/fail of this script.
set -u
OUT="${1:?usage: r4_equivalence_differential.sh OUTDIR}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
FC="$ROOT/scripts/fastcycle"
T="$FC/tests"
SUITES="test_review_record_store_tier_all_entries_regression.sh test_review_record_resolution_ground_truth.sh test_review_record_round_budget_boundary_regression.sh test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh test_review_record_gate_authority_r4_regression.sh test_review_record_subclause_cases.sh test_review_record_gate_authority_r1_regression.sh test_review_record_gate_authority_r2_regression.sh test_review_record_gate_authority_r3_regression.sh"
CONTROLS="G-A-BINDING-EQUAL#5 G-D-LIVE-REVIEWED#2 G-E-HASH-SHAPE#1 G-V-LISTS#2 G-NL-NONE-BOOL#2 G-T-OWNER-DECLARED#3 G-T-PRODUCER-DECLARED#3 G-FL-NULL#1 G-SV-ABSENT#2 G-CF-MARKER-MATCH#4 G-R-BATCH-CHANGES-OK#2 G-RV-ABSENT#2"
mkdir -p "$OUT/corpus" || exit 2
OUT="$(cd "$OUT" && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/rr_eqdiff.XXXXXX")" || exit 2
W="${W:?}"
ANALYZER="$T/lib/review_record_guard_analyzer.py"

python3 "$ANALYZER" list "$FC/review/review_record.py" > "$W/sc.tsv" || exit 2
{ cut -f1 "$T/fixtures/review_record_equivalent_subclauses.tsv"; printf '%s\n' $CONTROLS; } > "$W/want.txt"
awk -F'\t' 'NR==FNR{w[$1]=1; next} ($1 in w){print $1"\t"$2}' "$W/want.txt" "$W/sc.tsv" > "$W/ids.tsv"
if [ "$(wc -l < "$W/ids.tsv")" != "$(wc -l < "$W/want.txt")" ]; then
  echo "setup: some ids are not sub-clauses of the current tool:" >&2
  comm -23 <(sort "$W/want.txt") <(cut -f1 "$W/ids.tsv" | sort) >&2; exit 2
fi
mkdir -p "$W/eq"
while IFS=$'\t' read -r id _fn; do
  python3 "$ANALYZER" mutate "$FC/review/review_record.py" "$id" "$W/eq/${id//#/_}.py" || { echo "setup: mutate $id failed" >&2; exit 2; }
done < "$W/ids.tsv"

snapshot() { # snapshot DIR
  mkdir -p "$1/review" "$1/tests/lib" "$1/tests/fixtures"
  cp "$FC/review/review_record.py" "$1/review/"
  cp "$ANALYZER" "$T/lib/review_record_genuine.sh" "$1/tests/lib/"
  cp -r "$T/fixtures/review_record" "$T/fixtures/review_record_finding_layer" "$1/tests/fixtures/"
  for t in $SUITES; do cp "$T/$t" "$1/tests/"; done
}
snapshot "$W/control"
snapshot "$W/traced"
cp "$HERE/r4_eq_trace.py" "$W/traced/r4_eq_trace.py"
mkdir -p "$W/log"
python3 - "$W/traced/review/review_record.py" "$W" <<'PY' || exit 2
import sys
p, w = sys.argv[1], sys.argv[2]
src = open(p, encoding="utf-8").read()
tail = 'if __name__ == "__main__":\n    sys.exit(main(sys.argv[1:]))\n'
assert src.endswith(tail), "tool tail changed"
hook = ('if __name__ == "__main__":\n'
        '    import importlib.util as _iu, os as _os\n'
        '    _os.environ.setdefault("RR_EQ_DIR", %r); _os.environ.setdefault("RR_EQ_IDS", %r)\n'
        '    _os.environ.setdefault("RR_EQ_LOG", %r)\n'
        '    _sp = _iu.spec_from_file_location("r4_eq_trace", %r)\n'
        '    _tr = _iu.module_from_spec(_sp); _sp.loader.exec_module(_tr)\n'
        '    sys.exit(_tr.install(globals())(sys.argv[1:]))\n'
        % (w + "/eq", w + "/ids.tsv", w + "/log", w + "/traced/r4_eq_trace.py"))
open(p, "w", encoding="utf-8").write(src[:-len(tail)] + hook)
PY

run_suites() { # run_suites DIR -> stdout "suite<TAB>rc"
  local t rc
  for t in $SUITES; do
    timeout 900 bash "$1/tests/$t" > "$1/$t.log" 2>&1; rc=$?
    printf '%s\t%s\n' "$t" "$rc"
  done
}
echo "== control suites (untraced) =="
run_suites "$W/control" | tee "$OUT/suites_control.tsv"
echo "== traced suites (original + per-call differential) =="
run_suites "$W/traced" | tee "$OUT/suites_traced.tsv"
cp "$W"/log/*.json "$OUT/corpus/" 2>/dev/null
TRACE_OK=1
if ! cmp -s "$OUT/suites_control.tsv" "$OUT/suites_traced.tsv"; then
  echo "NOT ok tracing changed a suite status -- the corpus differential is not a faithful replay" >&2; TRACE_OK=0
fi
for t in $SUITES; do cp "$W/traced/$t.log" "$OUT/corpus/$t.log"; done

echo "== crafted grids =="
python3 -I "$HERE/r4_eq_grid.py" "$FC/review/review_record.py" "$W/eq" "$W/ids.tsv" "$W/grid" > "$OUT/grid.json" \
  || { echo "NOT ok grid harness failed" >&2; exit 1; }

python3 - "$OUT" "$W/ids.tsv" "$CONTROLS" "$TRACE_OK" <<'PY'
import glob, json, os, sys
out, idsf, controls, trace_ok = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4] == "1"
ids = [l.split("\t")[0] for l in open(idsf).read().splitlines()]
agg = {"fn": {}, "cli": {}}
for f in glob.glob(os.path.join(out, "corpus", "*.json")):
    st = json.load(open(f))
    for lvl in ("fn", "cli"):
        for i, s in st.get(lvl, {}).items():
            a = agg[lvl].setdefault(i, {"calls": 0, "differ": 0, "rc_differ": 0, "first": []})
            a["calls"] += s["calls"]; a["differ"] += s["differ"]; a["rc_differ"] += s.get("rc_differ", 0)
            a["first"] = (a["first"] + s["first"])[:3]
grid = json.load(open(os.path.join(out, "grid.json")))
blind = []
with open(os.path.join(out, "summary.tsv"), "w") as fh:
    fh.write("id\trole\tcorpus_fn_calls\tcorpus_fn_differ\tcorpus_cli_calls\tcorpus_cli_differ\tcorpus_cli_rc_differ"
             "\tgrid_fn_inputs\tgrid_fn_differ\tgrid_cli_inputs\tgrid_cli_differ\tgrid_cli_rc_differ\n")
    for i in ids:
        f, c, g = agg["fn"].get(i, {}), agg["cli"].get(i, {}), grid.get(i, {})
        role = "control" if i in controls else "claim"
        row = [i, role, f.get("calls", 0), f.get("differ", 0), c.get("calls", 0), c.get("differ", 0),
               c.get("rc_differ", 0), g.get("fn_inputs", 0), g.get("fn_differ", 0), g.get("cli_inputs", 0),
               g.get("cli_differ", 0), g.get("cli_rc_differ", 0)]
        fh.write("\t".join(str(x) for x in row) + "\n")
        if role == "control" and not (f.get("differ", 0) or c.get("differ", 0) or g.get("fn_differ", 0)
                                      or g.get("cli_differ", 0)):
            blind.append(i)
json.dump(agg, open(os.path.join(out, "corpus_aggregate.json"), "w"), indent=1, sort_keys=True)
print(open(os.path.join(out, "summary.tsv")).read())
if blind:
    print("NOT ok blind controls (no difference anywhere): %s" % " ".join(blind))
    sys.exit(1)
if not trace_ok:
    sys.exit(1)
print("ok every control differs somewhere; tracing preserved every suite status")
PY
rc=$?
chmod -R u+rwx "$W" 2>/dev/null; rm -rf "${W:?}"
exit "$rc"
