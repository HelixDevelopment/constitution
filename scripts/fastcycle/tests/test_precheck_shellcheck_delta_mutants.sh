#!/bin/sh
# fastcycle-timeout-s: 7200
# =============================================================================
# test_precheck_shellcheck_delta_mutants.sh (ATM-1217 r3)
# Paired 1.1 mutation harness for test_precheck_shellcheck_baseline_delta.sh.
# Each mutant is a one-place semantic break of the baseline-delta rule, its
# dispatchers or its seams with the round-5/6 gate, applied to a SCRATCH COPY of
# the review tree; the suite is run against that copy (FC_OVERRIDE) and the mutant
# is KILLED when the suite exits 1 (a case failed). Exit 2 (environment) or any
# other code is reported INVALID-RUN, never counted as a kill. A SURVIVOR means a
# rule with no teeth -> exit 1.
#
# A mutant whose search string does not occur exactly once is INVALID (never a
# kill): a stale mutant is decoration, not proof.
#
# M01-M21: the r2 mutant set, re-targeted at the r3 code (where the r2 mechanism
# was dropped as redundant with the round-6 gate, the mutant targets the round-6
# mechanism that now carries the property -- see r3/DESIGN.md section 6).
# S01-S08: new mutants on the MERGE SEAMS between the delta rule and the round-6 gate.
#
# Usage: sh test_precheck_shellcheck_delta_mutants.sh [-j N]   (default -j 4)
# =============================================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
JOBS=4
[ "${1:-}" = "-j" ] && JOBS=${2:-4}
SUITE="$HERE/test_precheck_shellcheck_baseline_delta.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

cat >"$TMP/mutants.py" <<'PYEOF'
RUN = "lib/precheck_pack_run.py"
BRUN = "lib/precheck_pack_build_run.py"
SH = "precheck_pack.sh"
BUILD = "precheck_pack_build.sh"
MUTANTS = [
 ("M01-key-includes-raw-line", RUN,
  '    return ("SC%s" % c.get("code"), msg, _line_text(lines, c.get("line")))',
  '    return ("SC%s" % c.get("code"), msg, _line_text(lines, c.get("line")), c.get("line"))'),
 ("M02-set-not-multiset", RUN,
  "        n_old = min(len(occ), budget.get(k, 0))",
  "        n_old = len(occ) if k in budget else 0"),
 ("M03-rc-empty-read-as-clean", RUN,
  '    if not out.strip():  # json1 always prints {"comments":[...]}; silence is not "clean"',
  '    if not out.strip():\n        out = "{\\"comments\\": []}"\n    if False:'),
 ("M04-timeout-hardcoded", RUN,
  "    sc_timeout = opts.get(\"timeout\") or _default_sc_timeout(rule)",
  "    sc_timeout = 30"),
 ("M05-floor-ignored-in-delta", RUN,
  "        blocking = [c for c in comments if _blocking(c)]",
  "        blocking = list(comments)"),
 ("M06-new-file-passes", RUN,
  "                (findings if _blocking(c) else advisory).append(f_)",
  "                (findings if _blocking(c) and dfile is None else advisory).append(f_)"),
 ("M07-rename-ignored", RUN,
  "            base_rel = renames.get(rel, rel)",
  "            base_rel = rel"),
 ("M08-window-reported-as-full", RUN,
  '        dfile["state"] = "window"',
  '        dfile["state"] = "full"'),
 ("M09-unlintable-window-ignored", RUN,
  "        if any(1000 <= int(c.get(\"code\") or 0) < 2000 for c in com):",
  "        if False:"),
 ("M10-memory-cap-not-applied-to-delta-lints", RUN,
  "            t = min(sc_timeout, left)\n            com, er, to, _el = _run_shellcheck(_flag, data, t, mem_cap)",
  "            t = min(sc_timeout, left)\n            com, er, to, _el = _run_shellcheck(_flag, data, t, 8192)"),
 ("M11-no-base-reads-as-delta", RUN,
  '    delta_on = rule == "baseline-delta" and baseline is not None',
  '    delta_on = rule == "baseline-delta"'),
 ("M12-unchanged-shortcut-inverted", RUN,
  '        return ("unchanged" if blob == cdata else "delta"), blob, ""',
  '        return ("unchanged" if blob != cdata else "delta"), blob, ""'),
 ("M13-new-directive-violation-ignored", RUN,
  "                dir_viol.append(rec)",
  "                pass"),
 ("M14-timeout-ceiling-not-refused", RUN,
  '    for name, ceiling in (("shellcheck_timeout", MAX_SC_TIMEOUT), ("shellcheck_exception_timeout", MAX_EXCEPTION_TIMEOUT)):',
  "    for name, ceiling in ():"),
 ("M15-window-base-side-dropped", RUN,
  "    hw, bw = _windows(hl, new_r), _windows(bl, old_r)",
  "    hw, bw = _windows(hl, new_r), []"),
 ("M16-window-line-not-translated", RUN,
  "                    c[k] = c[k] + off",
  "                    c[k] = c[k]"),
 ("M17-whole-file-window-guard-removed", RUN,
  "    if head_failed and len(hw) == 1 and hw[0][0] == 1 and hw[0][1] >= len(hl):",
  "    if False:"),
 ("M18-cli-timeout-ignored", RUN,
  '    sc_timeout = opts.get("timeout") or _default_sc_timeout(rule)',
  '    sc_timeout = _default_sc_timeout(rule)'),
 ("M19-dispatcher-drops-rule", SH,
  'if [ -n "$SC_RULE" ]; then set -- "$@" --shellcheck-rule "$SC_RULE"; fi',
  ":"),
 ("M20-base-failure-read-as-clean", RUN,
  '        if berr:\n            delta_window(rel, dfile, cdata, bdata, flag, False, True, ["base: " + berr], False)\n            return',
  '        if berr:\n            return'),
 ("M21-build-wrapper-drops-rule", BUILD,
  'if [ -n "$SC_RULE" ]; then set -- "$@" --shellcheck-rule "$SC_RULE"; fi',
  ":"),
 ("S01-exception-row-goes-delta", RUN,
  "        if delta_on and row is None:",
  "        if delta_on:"),
 ("S02-forbidden-directive-tolerated", RUN,
  '        if d["violations"] and all(v.startswith("D5") for v in d["violations"]):',
  '        if d["violations"]:'),
 ("S03-delta-default-timeout-not-rule-aware", RUN,
  '    return DEFAULT_SC_TIMEOUT_DELTA if rule == "baseline-delta" else DEFAULT_SC_TIMEOUT',
  "    return DEFAULT_SC_TIMEOUT"),
 ("S04-cache-ignores-rule", BRUN,
  '    if tool.get("rule", gate.DEFAULT_SC_RULE) != rule:  # ATM-1217: the rule changes the verdict',
  "    if False:"),
 ("S05-size-cap-blind-not-windowed", RUN,
  '            if dstate == "delta" and cap_problem is None and (len(clines) > max_lines or len(cdata) > max_bytes):',
  "            if False:"),
 ("S07-verifier-refuses-delta-mode", BRUN,
  '        if mode == "baseline-delta":',
  '        if False:'),
 ("S08-verifier-accepts-inconsistent-delta", BRUN,
  '            if rule != "baseline-delta" or dl.get("base_resolved") is not True or not dl.get("rule_id"):',
  '            if False:'),
 ("S06-delta-default-rule", RUN,
  'DEFAULT_SC_RULE = "whole-file"',
  'DEFAULT_SC_RULE = "baseline-delta"'),
]
PYEOF

python3 - "$TMP/mutants.py" "$TMP/list.tsv" <<'PY'
import sys
ns = {}
exec(open(sys.argv[1]).read(), ns)
with open(sys.argv[2], "w") as fh:
    for i, (n, f, o, w) in enumerate(ns["MUTANTS"]):
        fh.write("%d\t%s\t%s\n" % (i, n, f))
PY

run_one() { # <idx> <name> <file>
    idx=$1; name=$2; rel=$3
    d="$TMP/m$idx"
    mkdir -p "$d"
    cp -R "$FC/review" "$d/review"
    python3 - "$TMP/mutants.py" "$idx" "$d/review/$rel" <<'PY'
import sys
ns = {}
exec(open(sys.argv[1]).read(), ns)
_, _, old, new = ns["MUTANTS"][int(sys.argv[2])]
p = sys.argv[3]
s = open(p).read()
if s.count(old) != 1:
    print("needle found %d times" % s.count(old), file=sys.stderr)
    sys.exit(3)
open(p, "w").write(s.replace(old, new))
PY
    rc=$?
    if [ "$rc" -eq 3 ]; then echo "INVALID $name (search string not found exactly once)"; return; fi
    FC_OVERRIDE="$d" sh "$SUITE" >"$d/suite.log" 2>&1
    src=$?
    case $src in
        0) echo "SURVIVED $name" ;;
        1) echo "KILLED   $name ($(grep -c '^NOT ok' "$d/suite.log") case(s) failed)" ;;
        *) echo "INVALID-RUN $name (suite exit $src)"; tail -n 3 "$d/suite.log" ;;
    esac
}

N=$(wc -l <"$TMP/list.tsv")
running=0
: >"$TMP/results.txt"
while IFS='	' read -r idx name rel; do
    ( run_one "$idx" "$name" "$rel" >>"$TMP/results.txt" ) &
    running=$((running+1))
    if [ "$running" -ge "$JOBS" ]; then wait; running=0; fi
done <"$TMP/list.tsv"
wait

sort "$TMP/results.txt"
KILLED=$(grep -c '^KILLED' "$TMP/results.txt")
SURV=$(grep -c '^SURVIVED' "$TMP/results.txt")
INV=$(grep -c '^INVALID' "$TMP/results.txt")
echo "== mutants: $N total, $KILLED killed, $SURV survived, $INV invalid =="
[ "$SURV" -eq 0 ] && [ "$INV" -eq 0 ] && [ "$KILLED" -eq "$N" ] || exit 1
exit 0
