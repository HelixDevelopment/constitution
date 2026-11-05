#!/bin/bash
# test_review_record_subclause_sweep.sh
#
# T048 restart, V3 round 4, structural item (3) (R4-F3; constitution
# 11.4.276(C)/(D), 11.4.194(6)(d)): the DYNAMIC half of the guard meta-check.
#
# For EVERY guard sub-clause the analyzer derives from the source
# (lib/review_record_guard_analyzer.py: guarded set = the call graph of
# cmd_gate/cmd_record; every decision construct; every and/or operand), ONE
# mutant flipping just that sub-clause is built in a scratch mirror and the
# FULL review_record suite set is run against it (no early exit). The
# sub-clause's ISOLATING CASES are the checks that PASS on the unmutated
# control and do not PASS on that mutant -- measured, never hand-claimed.
#
# Output: a kill ledger (default fixtures/review_record_subclause_kills.tsv)
# bound to the sha256 of review_record.py, the analyzer and every suite, so
# test_review_record_guard_table.sh can prove it is FRESH and COMPLETE
# without re-running the sweep. Any edit to the tool, the analyzer or a suite
# makes the ledger stale (the guard table then FAILS until this is re-run).
#
# Usage : bash test_review_record_subclause_sweep.sh [-j 1|2] [--out FILE] [ID...]
#         (ID... restricts the sweep to those sub-clauses and writes no ledger
#         unless --out is given -- for iterating on one guard)
# Exit  : 0 control GREEN and every swept mutant KILLED; 1 a SURVIVED or
#         ERROR mutant (listed), or a RED control; 2 usage/setup error.
# Cost  : about 25 s per mutant; ~330 mutants at -j 2 is about 70 minutes --
#         run it in the background (constitution 11.4.89).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"
ANALYZER="$HERE/lib/review_record_guard_analyzer.py"
# cheapest first: a mutant stops at the FIRST suite that fails (its lost PASS
# lines are the isolating cases recorded); only survivors pay for every suite.
SUITES="test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh test_review_record_gate_authority_r4_regression.sh test_review_record_subclause_cases.sh test_review_record_gate_authority_r1_regression.sh test_review_record_gate_authority_r2_regression.sh test_review_record_gate_authority_r3_regression.sh"

JOBS=2; OUT=""; IDS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -j) JOBS="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    -*) echo "usage: $0 [-j 1|2] [--out FILE] [ID...]" >&2; exit 2 ;;
    *) IDS+=("$1"); shift ;;
  esac
done
case "$JOBS" in 1|2) ;; *) echo "-j must be 1 or 2 (constitution 12.6)" >&2; exit 2 ;; esac
if [ "${#IDS[@]}" -eq 0 ] && [ -z "$OUT" ]; then OUT="$HERE/fixtures/review_record_subclause_kills.tsv"; fi

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+rwx "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM

# SNAP: one snapshot of the tool, analyzer and suites taken at start, so an
# edit made while the sweep runs can never mix two versions into one ledger.
SNAP="$S/snap"
mkdir -p "$SNAP/review" "$SNAP/tests/lib" "$SNAP/tests/fixtures"
cp "$TOOL" "$SNAP/review/review_record.py"
cp "$ANALYZER" "$HERE/lib/review_record_genuine.sh" "$SNAP/tests/lib/"
cp -r "$HERE/fixtures/review_record" "$HERE/fixtures/review_record_finding_layer" "$SNAP/tests/fixtures/"
for t in $SUITES; do cp "$HERE/$t" "$SNAP/tests/"; done
TOOL="$SNAP/review/review_record.py"; ANALYZER="$SNAP/tests/lib/review_record_guard_analyzer.py"
build_mirror() { # build_mirror DIR
  mkdir -p "$1"
  cp -r "$SNAP/review" "$SNAP/tests" "$1/"
}
# run_all DIR [stop] -> DIR/<suite>.log + DIR/<suite>.rc; with "stop", stops
# after the first failing suite (later suites get no .log/.rc).
run_all() {
  local t rc
  for t in $SUITES; do
    timeout 300 bash "$1/tests/$t" >"$1/$t.log" 2>&1
    rc=$?
    echo "$rc" > "$1/$t.rc"
    if [ "${2:-}" = stop ] && [ "$rc" -ne 0 ]; then return 0; fi
  done
}
# pass_ids DIR -> one "suite::normalised PASS text" per line, sorted unique
pass_ids() {
  # shellcheck disable=SC2086 # $SUITES is a deliberately word-split list of file names
  python3 - "$1" $SUITES <<'PY'
import os, re, sys
d, suites = sys.argv[1], sys.argv[2:]
out = set()
for t in suites:
    try:
        lines = open(os.path.join(d, t + ".log"), encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    for line in lines:
        m = re.match(r"^PASS(?:\[\d+\])?: (.*)$", line)
        if not m:
            continue
        text = re.sub(r"/tmp/\S+", "<P>", m.group(1))
        text = re.sub(r"\d{5,}", "<N>", text)
        out.add("%s::%s" % (t, text[:90]))
for x in sorted(out):
    print(x)
PY
}

echo "== control: unmutated mirror must be fully GREEN =="
build_mirror "$S/control"
run_all "$S/control"
for t in $SUITES; do
  if [ "$(cat "$S/control/$t.rc")" != "0" ]; then
    echo "NOT ok control RED at $t -- kills would be meaningless"; tail -20 "$S/control/$t.log"; exit 1
  fi
done
pass_ids "$S/control" > "$S/control.pass"
echo "ok control GREEN: $(wc -l < "$S/control.pass") passing checks across $(echo "$SUITES" | wc -w) suites"

python3 "$ANALYZER" list "$TOOL" > "$S/subclauses.tsv" || { echo "analyzer failed" >&2; exit 2; }
if [ "${#IDS[@]}" -gt 0 ]; then
  awk -F'\t' 'NR==FNR{w[$1]=1; next} ($1 in w)' <(printf '%s\n' "${IDS[@]}") "$S/subclauses.tsv" > "$S/todo.tsv"
else cp "$S/subclauses.tsv" "$S/todo.tsv"; fi
echo "== sweeping $(wc -l < "$S/todo.tsv") sub-clause mutants at -j $JOBS =="

# shellcheck disable=SC2329 # invoked through `bash -c` by xargs below
worker() { # worker ID -> $S/res/<ID>.tsv : id status n killers
  local id="$1" m="$S/m/$1"
  mkdir -p "$m"
  build_mirror "$m"
  if ! python3 "$ANALYZER" mutate "$TOOL" "$id" "$m/review/review_record.py" 2>"$m/mutate.err"; then
    printf '%s\tERROR\t0\t%s\n' "$id" "$(tr '\n\t' '  ' < "$m/mutate.err")" > "$S/res/$id.tsv"; return
  fi
  run_all "$m" stop
  local any_red=0 t
  : > "$m/ran"
  for t in $SUITES; do
    [ -f "$m/$t.rc" ] || continue
    printf '%s::\n' "$t" >> "$m/ran"
    [ "$(cat "$m/$t.rc")" != "0" ] && any_red=1
  done
  pass_ids "$m" > "$m/pass"
  local killers n
  # only checks of the suites that actually ran on this mutant can be "lost"
  killers=$(LC_ALL=C comm -23 <(grep -F -f "$m/ran" "$S/control.pass") "$m/pass")
  n=$(printf '%s' "$killers" | grep -c . || true)
  if [ "$any_red" -eq 1 ] && [ "$n" -gt 0 ]; then
    printf '%s\tKILLED\t%s\t%s\n' "$id" "$n" "$(printf '%s\n' "$killers" | head -3 | tr '\n\t' '| ')" > "$S/res/$id.tsv"
  elif [ "$any_red" -eq 1 ]; then
    printf '%s\tKILLED\t0\tsuite exit non-zero without a lost PASS line\n' "$id" > "$S/res/$id.tsv"
  else
    printf '%s\tSURVIVED\t0\t-\n' "$id" > "$S/res/$id.tsv"
  fi
  chmod -R u+rwx "$m" 2>/dev/null; rm -rf "$m"
}
export -f worker build_mirror run_all pass_ids
export S TOOL ANALYZER SUITES HERE SNAP
mkdir -p "$S/res" "$S/m"
# shellcheck disable=SC2016 # $1/$S expand in the child bash, not here
cut -f1 "$S/todo.tsv" | xargs -P "$JOBS" -I{} bash -c 'worker "$1"; echo "  done $1 $(cut -f2 "$S/res/$1.tsv")"' _ {}

EQUIV="$HERE/fixtures/review_record_equivalent_subclauses.tsv"
FAIL=0
: > "$S/rows.tsv"
while IFS="$(printf '\t')" read -r id fn _kind line leaf repl; do
  if [ ! -f "$S/res/$id.tsv" ]; then echo "NOT ok $id: no result"; FAIL=1; continue; fi
  IFS="$(printf '\t')" read -r _id status n killers < "$S/res/$id.tsv"
  if [ "$status" = "SURVIVED" ] && [ -f "$EQUIV" ] \
     && awk -F'\t' -v i="$id" -v l="$leaf" '$1==i && $2==l {f=1} END {exit !f}' "$EQUIV"; then
    echo "ok $id SURVIVED but listed EQUIVALENT (reason in $(basename "$EQUIV"))"
  elif [ "$status" != "KILLED" ]; then
    echo "NOT ok $id $status ($fn line $line: $leaf -> $repl)"; FAIL=1
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$leaf" "$repl" "$status" "$n" "$killers" >> "$S/rows.tsv"
done < "$S/todo.tsv"

if [ -n "$OUT" ]; then
  {
    echo "# review_record sub-clause kill ledger -- generated by test_review_record_subclause_sweep.sh; do not edit"
    echo "# tool_sha256=$(sha256sum "$TOOL" | cut -d' ' -f1)"
    echo "# analyzer_sha256=$(sha256sum "$ANALYZER" | cut -d' ' -f1)"
    echo "# genuine_sha256=$(sha256sum "$SNAP/tests/lib/review_record_genuine.sh" | cut -d' ' -f1)"
    for t in $SUITES; do echo "# suite $t sha256=$(sha256sum "$SNAP/tests/$t" | cut -d' ' -f1)"; done
    echo "# columns: id<TAB>leaf<TAB>replacement<TAB>status<TAB>n_isolating_cases<TAB>first isolating cases"
    cat "$S/rows.tsv"
  } > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  echo "ledger written: $OUT ($(wc -l < "$S/rows.tsv") rows)"
fi
echo ""
[ "$FAIL" -eq 0 ] && { echo "== sub-clause sweep: every mutant KILLED =="; exit 0; }
echo "== sub-clause sweep: SURVIVED/ERROR mutants above (each needs an isolating case, or an EQUIVALENT entry with its reason in the guard table) =="; exit 1
