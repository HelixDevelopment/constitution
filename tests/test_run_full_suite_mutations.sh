#!/usr/bin/env bash
# tests/test_run_full_suite_mutations.sh -- paired section 1.1 mutations for the full-suite runner.
# Copies the runner (wrapper, engine, safe_rm helper) into a mktemp tree, applies ONE mutation at a
# time to the engine (an exact string replacement that must occur exactly once), and runs
# tests/test_run_full_suite.sh against the mutated copy (FSR_RUNNER). Each mutant MUST make the
# self-test fail; the unmutated copy MUST pass first (baseline), otherwise nothing is concluded.
# M1-M6 are the reviewer-authored mutants of review round 1 (rc 137 as PASS, resume ignores sha,
# TIMEOUT dropped from the failing set, exit-0 VERDICT: SKIP undetected, --rerun-nonpass ignored);
# M7+ are the author's own. Usage: bash tests/test_run_full_suite_mutations.sh [MUTANT_ID...]
# Exit 0 = baseline passes and every selected mutant is killed.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/rfs_mut.XXXXXX") || exit 2
: "${W:?}"
. "$HERE/scripts/lib/safe_rm.sh" || exit 2
trap 'TMPDIR="$(dirname "$W")" safe_rm_rf "${W:?}" >/dev/null 2>&1' EXIT

# id <TAB> old <TAB> new   (python string escapes \n \t are decoded)
MUTANTS=$(cat <<'EOF'
M1	    if rc in (124, 137):\n        return "ERROR", "rc_%d_without_runner_timeout" % rc, "exit-code", None	    if rc in (124, 137):\n        return "PASS", "", "exit-code", None
M2	return o["unit"] == u["id"] and o["sha"] == sha and	return o["unit"] == u["id"] and
M3	BAD = ("FAIL", "TIMEOUT", "ERROR")	BAD = ("FAIL", "ERROR")
M5	        if w == "SKIP":	        if w == "SKIPX":
M6	                if not (rerun and lv != "PASS"):	                if True:
M7	and o["tree"] == tree and	and
M8	            return "FAIL", "zero_checks_run", "summary", counts	            return "PASS", "", "summary", counts
M9	        if f > 0:\n            return "FAIL", "summary_reports_failures"	        if f > 10 ** 9:\n            return "FAIL", "summary_reports_failures"
M10	        if p != path:	        if p not in path:
M11	    env = {k: os.environ[k] for k in ENV_BASE if k in os.environ}	    env = dict(os.environ)
M12	    leaked = reap_token(token)	    leaked = 0
M13	SH_PATTERNS = (re.compile(r"^test_.*\\.sh$"), re.compile(r"^.*_test\\.sh$"),	SH_PATTERNS = (re.compile(r"^test_.*\\.sh$"),
M14	    for f in sorted(set(by) - want):	    for f in []:
M15	                    add(path, "-", [], tier, False, "heavy_excluded (member of %s)" % cover)\n            continue	                    add(path, "-", [], tier, False, "heavy_excluded (member of %s)" % cover)\n            add(path, "bash", [], tier, True)\n            continue
M16	[] if heavy_mode else ["--quick"]	[]
M17	        run = heavy_mode or not eff_heavy(r)	        run = True
M18	            % (cats["NOT-RUN"], ", interrupted" if interrupted else "", tail))\n        return 4	            % (cats["NOT-RUN"], ", interrupted" if interrupted else "", tail))\n        return 0
M19	"run with --include-heavy" % (cats["SKIPPED-heavy"], tail))\n        return 5	"run with --include-heavy" % (cats["SKIPPED-heavy"], tail))\n        return 0
M20	        return "ERROR", "killed_by_signal_%d" % -rc, "exit-code", None	        return "TIMEOUT", "killed_by_signal_%d" % -rc, "exit-code", None
M21	    if outdir == root or outdir.startswith(root + os.sep):	    if False:
M22	if not re.match(r"^[1-9][0-9]{0,5}$", v):	if not re.match(r"^[0-9]{1,6}$", v):
M23	    m = WORD.match(term)	    m = next((WORD.match(x.strip()) for x in lines if WORD.match(x.strip())), None)
M24	            if needle in env.split(b"\\0"):	            if False:
M25	        if HEAVY_NAME.search(b) and tier != "heavy" and not o:	        if False:
M26	            if r[3] == "default" and not mentions(rest, r[0]):	            if False:
M27	        if sig.startswith("reason:"):\n            if reason == sig[len("reason:"):]:\n                return tid\n        elif sig in logtext:	        if True:
EOF
)

prep() { # $1 dir: fresh copy of the runner
  mkdir -p "$1/scripts/full_suite" "$1/scripts/lib"
  cp "$HERE/scripts/run_full_suite.sh" "$1/scripts/"
  cp "$HERE/scripts/full_suite/run_full_suite.py" "$1/scripts/full_suite/"
  cp "$HERE/scripts/lib/safe_rm.sh" "$HERE/scripts/lib/protected_paths.list" "$1/scripts/lib/"
}
selftest() { # $1 dir -> rc of the self-test against that copy
  FSR_RUNNER="$1/scripts/run_full_suite.sh" bash "$HERE/tests/test_run_full_suite.sh" >"$1.log" 2>&1
}

prep "$W/base"
if selftest "$W/base"; then echo "ok   baseline: unmutated copy passes the self-test"
else echo "FAIL baseline: unmutated copy fails ($(tail -1 "$W/base.log")); nothing concluded"; exit 1; fi

killed=0; survived=0; bad=0
while IFS=$'\t' read -r id old new; do
  [ -n "$id" ] || continue
  if [ $# -gt 0 ]; then case " $* " in *" $id "*) ;; *) continue;; esac; fi
  d="$W/$id"; prep "$d"
  if ! python3 -I - "$d/scripts/full_suite/run_full_suite.py" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
dec = lambda s: s.encode().decode("unicode_escape")
old, new = dec(old), dec(new)
s = open(p).read()
if s.count(old) != 1:
    sys.exit("mutation anchor occurs %d times" % s.count(old))
open(p, "w").write(s.replace(old, new))
PY
  then echo "BAD  $id: mutation not applicable"; bad=$((bad+1)); continue; fi
  if selftest "$d"; then echo "SURVIVED $id"; survived=$((survived+1))
  else echo "killed $id ($(grep -c '^FAIL ' "$d.log") failing check(s))"; killed=$((killed+1)); fi
done <<< "$MUTANTS"
echo "SUMMARY mutants=$((killed+survived+bad)) killed=$killed survivors=$survived not_applicable=$bad"
[ "$survived" -eq 0 ] && [ "$bad" -eq 0 ]
