#!/usr/bin/env bash
# tests/test_run_full_suite_mutations.sh -- paired section 1.1 mutations for the full-suite runner.
# Copies the runner (wrapper, engine, safe_rm helper) into a mktemp tree, applies ONE mutation at a
# time to the engine (an exact string replacement that must occur exactly once), and runs
# tests/test_run_full_suite.sh against the mutated copy (FSR_RUNNER). Each mutant MUST make the
# self-test fail; the unmutated copy MUST pass first (baseline), otherwise nothing is concluded.
# M1-M6 are the reviewer-authored mutants of review round 1 (rc 137 as PASS, resume ignores sha,
# TIMEOUT dropped from the failing set, exit-0 SKIP word undetected, --rerun-nonpass ignored);
# R1-R6 are the reviewer-authored mutants of review round 2 (resume ignores the runner hash, tree
# change not failing, census needle skipped, any dict accepted as a record, rm_tree containment off,
# R5 timer firing not recorded); M7+ are the author's own. A mutant counts as KILLED only when the self-test
# exits non-zero AND prints at least one `FAIL ` check line (a crash with no failing check is not a
# kill). Usage: bash tests/test_run_full_suite_mutations.sh [MUTANT_ID...]
# Removed as EQUIVALENT (measured surviving in round 3, reasoned equivalent, not claimed killed):
#   M9  `any(c.get("f")>0 for c in counts)` -> False: line_counts() already returns FAIL for any line
#       with a failed>0 binding, so that check cannot decide a verdict.
#   M13 drop the `*_test.sh` name pattern: the broader rule (a .sh whose name contains `test`)
#       still lists every such file.
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
M2	return (o["unit"] == u["id"] and o["sha"] == sha and	return (o["unit"] == u["id"] and
M3	BAD = ("FAIL", "TIMEOUT", "ERROR")	BAD = ("FAIL", "ERROR")
M5	        if w.startswith("skip"):	        if w.startswith("skipX"):
M6	                if not (rerun and lv != "PASS"):	                if True:
M7	and o["tree"] == tree and	and
M8	            return "ERROR", "zero_tests", "summary", last_counts	            return "PASS", "", "summary", last_counts
M9b	    amb_fail = any(f > 0 for f in fails)	    amb_fail = False
M10	        if p != path:	        if p not in path:
M11	    env = {k: os.environ[k] for k in ENV_BASE if k in os.environ}	    env = dict(os.environ)
M12	    leaked = reap_token(token)	    leaked = 0
M14	    for f in sorted(set(by) - want):	    for f in []:
M15	                    add(path, "-", [], tier, False, "heavy_excluded (member of %s)" % cover)	                    add(path, "bash", [], tier, True)
M16	[] if heavy_mode else ["--quick"]	[]
M17	        run = heavy_mode or not eff_heavy(r)	        run = True
M18	        return 4\n    if cats	        return 0\n    if cats
M19	        return 5\n    if cats	        return 0\n    if cats
M20	        return "ERROR", "killed_by_signal_%d" % -rc, "exit-code", None	        return "TIMEOUT", "killed_by_signal_%d" % -rc, "exit-code", None
M21	            raise Fatal(2, "--out %s is inside the repository root; suites	            pass  # raise Fatal(2, "--out %s is inside the repository root; suites
M22	if not re.match(r"^[1-9][0-9]{0,5}$", v):	if not re.match(r"^[0-9]{1,6}$", v):
M23	        if term_skip and p > 0:	        if False:
M24	            if needle in env.split(b"\\0"):	            if False:
M25	        if HEAVY_NAME.search(b) and tier != "heavy" and not o:	        if False:
M26	                if r[3] == "default" and r[0] not in q:	                if False:
M27	        if sig.startswith("reason:"):\n            if reason == sig[len("reason:"):]:\n                return tid\n        elif sig in logtext:	        if True:
M28	        return 6\n	        return 0\n
M29	            if overflow and not timed_out:	            if False:
M30	        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)	        pass
M31	            if o["seq"] != n or o["prev"] != want_prev:	            if False:
M32	        h.update(b"I" + f.encode())\n        h.update(file_digest(os.path.join(root, f)))	        pass
M33	                     "git status --porcelain=v1 -z --untracked-files=all; git diff HEAD	                     "true; git status --porcelain=v1 -z --untracked-files=all >/dev/null; git diff HEAD >/dev/null
M34	        flip = len(set(r["verdict"] for r in mine)) > 1	        flip = False
M35	        if o["log"] in logs:	        if False:
M36	        c = None if CHECKLINE.match(l) else line_counts(l)	        c = line_counts(l)
R1	 and o["runner_hash"] == rhash	
R2	    if tree_end != tree:\n        out("RESULT: FAIL	    if False:\n        out("RESULT: FAIL
R3	    census_needle(scratch)\n	    pass\n
R4	    if not isinstance(o, dict) or o.get("schema") != SCHEMA:\n        return False\n	    if not isinstance(o, dict):\n        return False\n    return True\n
R5	                    timed_out, term_at = True, now	                    term_at = now
R6	    if not real.startswith(sreal + os.sep) or not os.path.basename(real).startswith("fsr_"):	    if False:
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
  else
    nfail=$(grep -c '^FAIL ' "$d.log")
    if [ "$nfail" -gt 0 ]; then echo "killed $id ($nfail failing check(s))"; killed=$((killed+1))
    else echo "SURVIVED $id (self-test exited non-zero with no FAIL line: $(tail -1 "$d.log"))"; survived=$((survived+1)); fi
  fi
done <<< "$MUTANTS"
echo "SUMMARY mutants=$((killed+survived+bad)) killed=$killed survivors=$survived not_applicable=$bad"
[ "$survived" -eq 0 ] && [ "$bad" -eq 0 ]
