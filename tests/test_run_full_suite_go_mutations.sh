#!/usr/bin/env bash
# tests/test_run_full_suite_go_mutations.sh -- paired section 1.1 mutations for the Go-unit classification of the
# full-suite runner (go_test_needs_network and its wiring). Copies the runner into a mktemp tree, applies ONE mutant
# (one or more exact string replacements, each anchor must occur exactly once) and runs
# tests/test_run_full_suite_go.sh against the copy (FSR_RUNNER), restricted to the cases that pin the mutated axis
# (FSR_GO_CASES; P, the classifier table, always runs). The unmutated copy must pass the WHOLE file first
# (baseline). A mutant counts as KILLED only when the test exits non-zero AND prints at least one `FAIL ` line AND the
# mutated runner did not crash (a Python traceback in the log makes the mutant BAD, never killed).
#
# One mutant per axis (structural round 3 of the full-suite fix vehicle, review round 2 G5 / G7b):
#   GM1  rc guard dropped (rc 0 / 2 examined)                    GM2  incomplete output examined
#   GM3  vendor/ guard dropped (vendor axis)                      GM4  offline-policy guard dropped
#   GM5  unknown output line ignored (mixed real failure axis)    GM6  a network line alone suffices
#   GM7  no network line needed                                   GM9  vendor/ looked up at the repo root
#   GM12 module names dropped (case-escaped naming axis)          GM15 workspace shape not recognised
#   GM16 graph-level abort line not recognised                    GM17 go.sum gap read as "needs network"
#                                                                      (replace / cached-with-go.sum-gap /
#                                                                      GONOSUMDB-GOSUMDB axes: the I4-1 / G7b class)
#   GM19 grammar off AND no network line needed (build-tags axis: a real FAIL of a runnable unit, review G5)
#   GMF  unit GOFLAGS=-mod=mod (GOFLAGS axis: the policy is read from the env the unit really ran with)
#   GMP  classifier expects GOPROXY=direct (GOPROXY axis: off is the runner's policy, a host file:// never reaches it)
#   GMT  `go.mod requires go >=` read as a network line (toolchain axis)
#   GMM  the unit command reaches a nested module (multi-module axis)
#   GM21 vendor guard widened to a bare vendor/ directory (A14)
# Reasoned EQUIVALENT, not listed (each with its differential; see the guide):
#   GM8  drop `verdict == "FAIL"` in main: a non-FAIL verdict has rc 0 (judge_exit0) or rc 77 / >= 124, which the
#        classifier's own rc != 1 guard refuses (GM1 is the killed mutant of that guard).
#   GM10 go_env built from GO_POLICY instead of the unit's env: identical while unit_env sets the policy; GMF is the
#        killed mutant that changes the env the unit really runs with.
#   GM20 (reviewer RG1) `complete = True`: tried as a mutant and it SURVIVES fixture A13 (a 1.5 MB log from a real
#        failure plus an uncached dependency in another package): equivalent for the shapes measured, because
#        `overflow` already makes the verdict ERROR before the classifier and Go prints every failing package's own
#        `FAIL<TAB>pkg<TAB>time` line, which is outside the grammar. A13 stays as a regression fixture (it pins FAIL
#        for a big log); the classifier's own completeness test is P11 (killed GM2).
#   GM22 (reviewer RG2) `[setup failed]` widened to `[setup|build failed]`: equivalent for the shapes Go prints
#        (`[build failed]` comes with compile or vet lines, which are outside the grammar). UNCONFIRMED: no Go
#        version prints `[build failed]` with only grammar lines (measured on Go 1.26.8 only).
#   GM23 (RG3) package header `^# \S+$` widened to `^# .*$`: equivalent, a test cannot print a header line without
#        Go also printing an out-of-grammar `FAIL<TAB>pkg<TAB>time` line.
#   GM24 (RG17) the policy check accepting an unset variable: unreachable, unit_env always sets GOPROXY and GOFLAGS.
#   GM25 (RG23) `if fetch is not None` -> `if fetch`: fail-closed (an empty module list stays FAIL); whether Go can
#        print a lookup-disabled line with no module is UNCONFIRMED, so the branch has no fixture.
#   retract axis: go test does not consult retractions (A10 measured PASS); no classifier code is specific to it.
# Usage: bash tests/test_run_full_suite_go_mutations.sh [MUTANT_ID...]. Exit 0 = baseline passes, every selected
# mutant is killed.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v go >/dev/null 2>&1 || { echo "SUMMARY mutants=0 (skipped: go not installed) reason=topology_unsupported"; exit 77; }
W=$(mktemp -d "${TMPDIR:-/tmp}/rfs_gomut.XXXXXX") || exit 2
: "${W:?}"
. "$HERE/scripts/lib/safe_rm.sh" || exit 2
trap 'chmod -R u+w "${W:?}" 2>/dev/null; TMPDIR="$(dirname "$W")" safe_rm_rf "${W:?}" >/dev/null 2>&1' EXIT

# id <TAB> cases <TAB> old <TAB> new [<TAB> old2 <TAB> new2 ...]   (python escapes \n \t decoded)
MUTANTS=$(cat <<'EOF'
GM1	P	    if rc != 1 or not complete or vendored:	    if not complete or vendored:
GM2	P	    if rc != 1 or not complete or vendored:	    if rc != 1 or vendored:
GM3	A8	    if rc != 1 or not complete or vendored:	    if rc != 1 or not complete:
GM4	P	    if any(env.get(k) != v for k, v in GO_POLICY.items()):	    if False:
GM5	A6	        return None\n    if not (net and failed):	        continue\n    if not (net and failed):
GM6	P	    if not (net and failed):	    if not net:
GM7	P	    if not (net and failed):	    if False:
GM9	A8	os.path.join(ROOT, u["path"], "vendor", "modules.txt")	os.path.join(ROOT, "vendor", "modules.txt")
GM12	A5	            names.add("%s@%s" % (m.group(1), m.group(2)))	            pass
GM15	A7	\.go:\d+:\d+: (?:(?P<b>[^\s:]+@[^\s:]+): )?)"	\.go:\d+:\d+: (?P<b>))"
GM16	P	GO_ABORT_NET = re.compile(r"^go: [^\s:]+@[^\s:]+: module lookup disabled by GOPROXY=off$")	GO_ABORT_NET = re.compile(r"^$NEVER")
GM17	A2,A3,A4	r"module lookup disabled by GOPROXY=off$")\nGO_ABORT_NET	r"(?:module lookup disabled by GOPROXY=off|missing go\.sum entry.*)$")\nGO_ABORT_NET	        return None\n    if not (net and failed):	        if ln.startswith("\\t"):\n            continue\n        return None\n    if not (net and failed):
GM19	A1,A6	        return None\n    if not (net and failed):	        continue\n    if False:
GMF	A2,A5	"GOFLAGS": "-mod=readonly",\n                    "GOPROXY": "off"	"GOFLAGS": "-mod=mod",\n                    "GOPROXY": "off"
GMP	A5	GO_POLICY = {"GOPROXY": "off", "GOFLAGS": "-mod=readonly"}	GO_POLICY = {"GOPROXY": "direct", "GOFLAGS": "-mod=readonly"}
GMT	A9	        m = GO_NET_LINE.match(ln)\n        if m:	        m = GO_NET_LINE.match(ln) or re.match(r"^go: go\\.mod requires go >= .*(?P<a>)(?P<b>)$", ln)\n        if m:\n            failed = True
GMM	A11	["go", "test", "-count=1", "./..."]	["go", "test", "-count=1", "./...", "./sub/..."]
GM21	A14	vendored = os.path.isfile(os.path.join(ROOT, u["path"], "vendor", "modules.txt"))	vendored = os.path.isdir(os.path.join(ROOT, u["path"], "vendor"))
EOF
)

prep() { # $1 dir: fresh copy of the runner
  mkdir -p "$1/scripts/full_suite" "$1/scripts/lib"
  cp "$HERE/scripts/run_full_suite.sh" "$1/scripts/"
  cp "$HERE/scripts/full_suite/run_full_suite.py" "$1/scripts/full_suite/"
  cp "$HERE/scripts/lib/safe_rm.sh" "$HERE/scripts/lib/protected_paths.list" "$1/scripts/lib/"
}
gotest() { # $1 dir $2 cases ("" = all) -> rc of the Go test file against that copy
  FSR_RUNNER="$1/scripts/run_full_suite.sh" FSR_GO_CASES="$2" bash "$HERE/tests/test_run_full_suite_go.sh" >"$1.log" 2>&1
}

prep "$W/base"
if gotest "$W/base" ""; then echo "ok   baseline: unmutated copy passes the whole Go test file ($(tail -1 "$W/base.log"))"
else echo "FAIL baseline: unmutated copy fails ($(grep -m3 '^FAIL ' "$W/base.log" | tr '\n' ' ')); nothing concluded"; exit 1; fi

killed=0; survived=0; bad=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id=${line%%$'\t'*}; rest=${line#*$'\t'}; cases=${rest%%$'\t'*}; pairs=${rest#*$'\t'}
  if [ $# -gt 0 ]; then case " $* " in *" $id "*) ;; *) continue;; esac; fi
  d="$W/$id"; prep "$d"
  if ! python3 -I - "$d/scripts/full_suite/run_full_suite.py" "$pairs" <<'PY'
import sys
p, pairs = sys.argv[1], sys.argv[2].split("\t")
dec = lambda s: s.encode().decode("unicode_escape")
if len(pairs) % 2:
    sys.exit("odd number of old/new fields")
s = open(p).read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    old, new = dec(old), dec(new)
    if s.count(old) != 1:
        sys.exit("mutation anchor occurs %d times: %r" % (s.count(old), old[:70]))
    s = s.replace(old, new)
open(p, "w").write(s)
compile(s, p, "exec")
PY
  then echo "BAD  $id: mutation not applicable"; bad=$((bad+1)); continue; fi
  if gotest "$d" "$cases"; then echo "SURVIVED $id (cases $cases)"; survived=$((survived+1))
  elif grep -q '^Traceback\|Error: \|PatternError' "$d.log"; then
    echo "BAD  $id: the mutated runner crashed, so its failing checks prove nothing ($(grep -m1 'Error' "$d.log"))"; bad=$((bad+1))
  else
    nfail=$(grep -c '^FAIL ' "$d.log")
    if [ "$nfail" -gt 0 ]; then echo "killed $id by $cases ($nfail failing check(s): $(grep -m2 '^FAIL ' "$d.log" | cut -c6-90 | tr '\n' ';'))"; killed=$((killed+1))
    else echo "SURVIVED $id (exited non-zero with no FAIL line: $(tail -1 "$d.log"))"; survived=$((survived+1)); fi
  fi
done <<< "$MUTANTS"
echo "SUMMARY mutants=$((killed+survived+bad)) killed=$killed survivors=$survived not_applicable=$bad"
[ "$survived" -eq 0 ] && [ "$bad" -eq 0 ]
