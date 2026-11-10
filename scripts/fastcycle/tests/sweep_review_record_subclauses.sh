#!/bin/bash
# sweep_review_record_subclauses.sh  (renamed from test_review_record_subclause_sweep.sh,
# CON-033 round 2, review I5: it is a ~70-minute GENERATOR, not a test; under
# the test_* name run_all.sh ran it under its 240 s default bound, where it
# always ended rc=124. It is now outside run_all's test_*.sh glob and is run on
# demand or by a scheduled runner; test_review_record_guard_table.sh proves the
# tracked ledger FRESH and COMPLETE without running it. The comments in the
# files the ledger hashes were moved to the new name at the round-3
# regeneration.)
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
# Output: a kill ledger bound to the sha256 of review_record.py, the analyzer and every suite, so
# test_review_record_guard_table.sh can prove it is FRESH and COMPLETE
# without re-running the sweep. Any edit to the tool, the analyzer or a suite
# makes the ledger stale (the guard table then FAILS until this is re-run).
#
# Usage : bash sweep_review_record_subclauses.sh [-j 1|2] [--out FILE] [ID...]
#         Without --out the ledger goes to a NEW temp file (its path is
#         printed); the TRACKED ledger is rewritten only when it is named:
#           --out scripts/fastcycle/tests/fixtures/review_record_subclause_kills.tsv
#         (ID... restricts the sweep to those sub-clauses and writes no ledger
#         unless --out is given -- for iterating on one guard)
# Exit  : 0 control GREEN, every swept mutant has a result and is KILLED (or
#         listed EQUIVALENT); 77 the same, but a control suite exited 77 (it
#         skipped proof legs on this host): SKIP, never PASS (CON-033 round 3,
#         review R2-F3); 1 a SURVIVED or ERROR mutant (listed), a missing
#         result, or a RED control; 2 usage/setup error; 129/130/143 when
#         interrupted by HUP/INT/TERM (an interrupted sweep never reports
#         success and writes no ledger).
# Cost  : about 25 s per mutant; ~330 mutants at -j 2 is about 70 minutes --
#         run it in the background (constitution 11.4.89).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"
ANALYZER="$HERE/lib/review_record_guard_analyzer.py"
# cheapest first: a mutant stops at the FIRST suite that fails (its lost PASS
# lines are the isolating cases recorded); only survivors pay for every suite.
SUITES="test_review_record_store_tier_all_entries_regression.sh test_review_record_resolution_ground_truth.sh test_review_record_round_budget_boundary_regression.sh test_review_record_red.sh test_review_record_finding_layer_red.sh test_review_record_evidence_hash_r5_regression.sh test_review_record_backfill_evidence_r2_regression.sh test_review_record_gate_authority_r4_regression.sh test_review_record_subclause_cases.sh test_review_record_gate_authority_r1_regression.sh test_review_record_gate_authority_r2_regression.sh test_review_record_gate_authority_r3_regression.sh"

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
if [ "${#IDS[@]}" -eq 0 ] && [ -z "$OUT" ]; then
  # Never a tracked file by default (CON-033 round 2, review I5).
  OUT=$(mktemp "${TMPDIR:-/tmp}/review_record_subclause_kills.XXXXXX") || { echo "cannot create the ledger temp file" >&2; exit 2; }
fi

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
_sweep_cleanup() { chmod -R u+rwx "${S:?}" 2>/dev/null; rm -rf -- "${S:?}"; }
trap '_sweep_cleanup' EXIT
# An interrupt EXITS with the conventional status (the EXIT trap then cleans
# up). Before round 2 the trap only deleted $S and the script carried on: the
# result loop read nothing and the sweep printed "every mutant KILLED" with
# exit 0 (review I5, reproduced with SIGTERM after 2 of 343 mutants).
trap 'echo "sweep interrupted (HUP): no ledger written" >&2; exit 129' HUP
trap 'echo "sweep interrupted (INT): no ledger written" >&2; exit 130' INT
trap 'echo "sweep interrupted (TERM): no ledger written" >&2; exit 143' TERM

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
# after the first suite whose status differs from the control's (later suites
# get no .log/.rc). A suite's status is its exit code: 0 PASS, 77 SKIP (a
# proof leg could not run on this host), anything else FAIL (CON-033 round 3,
# review R2-F3). A mutant is red on a suite whose status differs from the
# control's for that suite; 77 on both is not a kill.
run_all() {
  local t rc
  for t in $SUITES; do
    timeout 300 bash "$1/tests/$t" >"$1/$t.log" 2>&1
    rc=$?
    echo "$rc" > "$1/$t.rc"
    if [ "${2:-}" = stop ] && [ "$rc" != "$(cat "$S/control/$t.rc")" ]; then return 0; fi
  done
}
# pass_ids DIR -> one "suite::normalised PASS text" per line, sorted unique
pass_ids() {
  # shellcheck disable=SC2086 # $SUITES is a deliberately word-split list of file names
  python3 - "$1" $SUITES <<'PY'
import os, re, sys
d, suites = sys.argv[1], sys.argv[2:]
# Paths that differ from run to run are not checks (CON-033 round 4, review
# R3-F4): every mirror lives under a fresh temp directory, so a PASS line
# that merely names a file under $TMPDIR or $HOME (or /tmp) differs between
# the control and a mutant and was counted as an "isolating case". Each of
# those prefixes -- as given and resolved -- is replaced, longest first.
PREFIXES = set()
for raw in (os.environ.get("TMPDIR"), os.environ.get("HOME"), "/tmp"):
    if raw and raw.strip("/"):
        PREFIXES.add(raw.rstrip("/"))
        PREFIXES.add(os.path.realpath(raw).rstrip("/"))
PREFIXES = sorted((p for p in PREFIXES if p.strip("/")), key=len, reverse=True)
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
        text = m.group(1)
        for pre in PREFIXES:
            text = re.sub(re.escape(pre) + r"\S*", "<P>", text)
        text = re.sub(r"\d{5,}", "<N>", text)
        out.add("%s::%s" % (t, text[:90]))
for x in sorted(out):
    print(x)
PY
}

echo "== control: unmutated mirror must be fully GREEN =="
build_mirror "$S/control"
run_all "$S/control"
CONTROL_SKIP=""
for t in $SUITES; do
  case "$(cat "$S/control/$t.rc")" in
    0) ;;
    77) CONTROL_SKIP="$CONTROL_SKIP $t"
        echo "SKIP control: $t skipped proof legs on this host: $(grep '^SKIP: ' "$S/control/$t.log" | cut -d' ' -f2 | tr '\n' ' ')" ;;
    *) echo "NOT ok control RED at $t (rc $(cat "$S/control/$t.rc")) -- kills would be meaningless"; tail -20 "$S/control/$t.log"; exit 1 ;;
  esac
done
pass_ids "$S/control" > "$S/control.pass"
echo "ok control GREEN: $(wc -l < "$S/control.pass") passing checks across $(echo "$SUITES" | wc -w) suites${CONTROL_SKIP:+ -- with skipped proof legs in:$CONTROL_SKIP}"

python3 "$ANALYZER" list "$TOOL" > "$S/subclauses.tsv" || { echo "analyzer failed" >&2; exit 2; }
if [ "${#IDS[@]}" -gt 0 ]; then
  awk -F'\t' 'NR==FNR{w[$1]=1; next} ($1 in w)' <(printf '%s\n' "${IDS[@]}") "$S/subclauses.tsv" > "$S/todo.tsv"
else cp "$S/subclauses.tsv" "$S/todo.tsv"; fi
N_TODO=$(grep -c . "$S/todo.tsv" || true)
if [ "$N_TODO" -eq 0 ]; then echo "NOT ok no sub-clause to sweep (analyzer list empty, or no ID matched)" >&2; exit 1; fi
echo "== sweeping $N_TODO sub-clause mutants at -j $JOBS =="

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
    [ "$(cat "$m/$t.rc")" != "$(cat "$S/control/$t.rc")" ] && any_red=1
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
# Every swept sub-clause must have produced a row (a result loop that read a
# truncated or missing todo list must never look like a clean sweep).
N_ROWS=$(grep -c . "$S/rows.tsv" || true)
if [ "$N_ROWS" -ne "$N_TODO" ]; then
  echo "NOT ok result count $N_ROWS != swept sub-clause count $N_TODO"; FAIL=1
fi

if [ -n "$OUT" ] && [ "$N_ROWS" -ne "$N_TODO" ]; then
  echo "no ledger written: the sweep is incomplete"
elif [ -n "$OUT" ]; then
  {
    echo "# review_record sub-clause kill ledger -- generated by sweep_review_record_subclauses.sh; do not edit"
    echo "# control_skipped_suites=${CONTROL_SKIP:- none}"
    echo "# tool_sha256=$(sha256sum "$TOOL" | cut -d' ' -f1)"
    echo "# analyzer_sha256=$(sha256sum "$ANALYZER" | cut -d' ' -f1)"
    echo "# genuine_sha256=$(sha256sum "$SNAP/tests/lib/review_record_genuine.sh" | cut -d' ' -f1)"
    for t in $SUITES; do echo "# suite $t sha256=$(sha256sum "$SNAP/tests/$t" | cut -d' ' -f1)"; done
    echo "# columns: id<TAB>leaf<TAB>replacement<TAB>status<TAB>n_isolating_cases<TAB>first isolating cases"
    cat "$S/rows.tsv"
  } > "$S/ledger.tmp" && mv "$S/ledger.tmp" "$OUT"
  echo "ledger written: $OUT ($(wc -l < "$S/rows.tsv") rows)"
fi
echo ""
if [ "$FAIL" -eq 0 ] && [ -n "$CONTROL_SKIP" ]; then
  echo "== sub-clause sweep: every mutant KILLED, but the control skipped proof legs in:$CONTROL_SKIP (SKIP, not PASS) =="
  echo "SKIP reason=control_proof_legs_skipped"; exit 77
fi
[ "$FAIL" -eq 0 ] && { echo "== sub-clause sweep: every mutant KILLED =="; exit 0; }
echo "== sub-clause sweep: SURVIVED/ERROR mutants above (each needs an isolating case, or an EQUIVALENT entry with its reason in the guard table) =="; exit 1
