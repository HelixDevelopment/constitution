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
# R5 timer firing not recorded); X1-X9 are the reviewer-authored mutants of review round 3 (any verdict
# string accepted, window 8->2, KNOWN without the log sha256 check, untracked content not hashed, pgid<=1
# refusal dropped); V*, E*, S*, K*, T*, C* guard the round-4 parser, excluded audit, status consumption,
# PASS-FULL-WITH-KNOWN, topology preflight and census additions; O2 O5 O7 O9 are the reviewer-authored
# mutants of review round 4 that survived; D*, S5-S8, Y*, W* guard the round-5 fixes (drift / dirty tree /
# identity, status read but not decided, crash words / CR residue / TAP TODO, operator roster + chained
# acceptance lines); I1-I3 L1 L2 Z4 Z7 guard the round-6 fixes of review r5 (identity verified before
# every unit and at the end, symlinked roster / lock refused, and the reviewer's surviving M4 / M7 pinned:
# dirty tree + KNOWN is exit 10, a failing git status reads dirty=unknown); G1-G4 guard the WIT-C02 per-unit fingerprint of the generated command sets
# (ownership wave 2 review r2: gen field, inode, mtime, after-unit check; RMb = the reviewer's mutant of
# review r2, the vendored constitution/ prefix; I1/I2 re-pinned by section 39 in round 3); L3 guards CON-235 (--accept-excluded-change refuses a symlinked lock); M7+ are the author's own. F47a-F47c guard CON-047 F047-1/F047-2 (`+tracked` accepts a foreign
# tracked token; a closed item read as open; an empty DB read as clean). A mutant counts as KILLED only when the self-test
# exits non-zero AND prints at least one `FAIL ` check line (a crash with no failing check is not a
# kill). Usage: bash tests/test_run_full_suite_mutations.sh [MUTANT_ID...]
# A MUTANTS table whose ids are not unique is refused with exit 2 before anything runs (CON-236;
# guarded by tests/test_run_full_suite_mutations_table.sh).
# Removed with the round-3 parser they targeted (round 4 replaced the parser, section 11.4.276(E)):
#   M5 M8 M9b M23 M36 (their anchors no longer exist; V1-V11 take their place).
# Removed as EQUIVALENT (measured surviving in round 3, reasoned equivalent, not claimed killed):
#   M13 drop the `*_test.sh` name pattern: the broader rule (a .sh whose name contains `test`)
#       still lists every such file.
#   (round 5, not added) drop the recursive `submodule foreach` status in tree_ident: the root
#       `git status --ignore-submodules=none` already reports a dirty submodule as ` M <path>`
#       (measured 2026-11-04), so the foreach only adds detail; reasoned equivalent for detection.
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
M6	                if not (rerun and lv != "PASS"):	                if True:
M7	and o["tree"] == tree and	and
M10	        if p != path:	        if p not in path:
M11	    env = {k: os.environ[k] for k in ENV_BASE if k in os.environ}	    env = dict(os.environ)
M12	    leaked = reap_token(token)	    leaked = 0
M14	    for f in sorted(set(by) - want):	    for f in []:
M15	                    add(path, "-", [], tier, False, "heavy_excluded (member of %s)" % cover)	                    add(path, "bash", [], tier, True)
M16	[] if heavy_mode else ["--quick"]	[]
M17	        run = heavy_mode or not eff_heavy(r)\n        add(path, runner, [], tier, run,	        run = True\n        add(path, runner, [], tier, run,
M18	        return 4\n    if cats	        return 0\n    if cats
M19	        return 5\n    if cats	        return 0\n    if cats
M20	        return "ERROR", "killed_by_signal_%d" % -rc, "exit-code", None	        return "TIMEOUT", "killed_by_signal_%d" % -rc, "exit-code", None
M21	            raise Fatal(2, "--out %s is inside the repository root; suites	            pass  # raise Fatal(2, "--out %s is inside the repository root; suites
M22	if not re.match(r"^[1-9][0-9]{0,5}$", v):	if not re.match(r"^[0-9]{1,6}$", v):
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
R1	 and o["runner_hash"] == rhash	
R2	    if tree_end != tree:\n        out("RESULT: FAIL	    if False:\n        out("RESULT: FAIL
R3	    census_needle(scratch)\n	    pass\n
R4	    if not isinstance(o, dict) or o.get("schema") != SCHEMA:\n        return False\n	    if not isinstance(o, dict):\n        return False\n    return True\n
R5	                    timed_out, term_at = True, now	                    term_at = now
R6	    if not real.startswith(sreal + os.sep) or not os.path.basename(real).startswith("fsr_"):	    if False:
X1	    return o["verdict"] in VERDICTS	    return True
X3	WIN = 12	WIN = 2
X4	            if hashlib.sha256(body).hexdigest() == o["log_sha256"]:	            if True:
X5	        h.update(b"U" + f.encode())\n        h.update(file_digest(os.path.join(root, f)))	        h.update(b"U" + f.encode())
X9	    if not isinstance(pgid, int) or pgid <= 1 or pgid == os.getpgrp():	    if not isinstance(pgid, int):
V1	        l = CTRL.sub("", ESC.sub("", l)).rstrip()	        l = l.rstrip()
V2	        if "\\r" in l:\n            over, l = l.rsplit("\\r", 1)	        if False:\n            pass
V3	    if any(k == "tapfail" for k, _ in cls):\n        return "FAIL", "tap_not_ok", "summary", None	    if False:\n        pass
V4	    if any(k == "headfail" for k, _ in cls):\n        return "FAIL", "summary_word_FAIL", "summary", None	    if False:\n        pass
V5	        if any(v == "FAIL" for _i, _inf, (v, _r) in sums[:-1]):	        if False:
V6	        if any(i > li or i in rw for i in fails):	        if False:
V7	    if fails:\n        return "ERROR", "unparsed_fail_signal", "summary", None	    if False:\n        pass
V8	    if (p or 0) == 0 and (t is None or t == 0 or (s or 0) >= (t or 0)) and skipish and "p" not in st:	    if False:
V9	    if left:\n        return None	    if False:\n        return None
V10	            if not BOUNDFAIL.search(bare):\n                return "other", None	            if True:\n                return "other", None
V11	        li, linfo, (lv, lr) = sums[-1]	        li, linfo, (lv, lr) = sums[0]
E1	    if added or removed or changed:	    if False:
E2	        if ex:\n            return ["excluded set	        if False:\n            return ["excluded set
E3	                if m.group(1) not in EXCL_CATS:	                if False:
E4	                if (name_test(b) or GO_PATTERN.match(b)) and not o:	                if False:
E5	        summ.append("EXCLUDED  %s  (%s)" % (p_, note))	        pass
S1	        if table is self.invoked and not self.consumed:	        if False:
S2	            elif path in alone:	            elif False:
S3	    return lit_text(cmds[0][1][0]) in ABSORB	    return False
S4	                    c = self.errexit or _reads_status(nxt)	                    c = _reads_status(nxt)
K1	        return 7	        return 0
T1	    if gaps and not allow_topo:	    if False:
T2	        if flag == "-":	        if False:
T3	        return 8	        return 0
C1	        if JS_EXT.search(b):\n            scripts[f] = "js"\n            continue	        if False:\n            pass
C2	            if u["runner"] in ("node", "bats") and shutil.which(u["runner"], path=unit_env_path()) is None:	            if False:
C3	    return "." not in b and (in_tdir or TEST_KEYWORD.search(b) is not None)	    return "." not in b and in_tdir
O2	    if "f" in st or info["c_fail"]:	    if "f" in st:
O5	    if last is None or last != excl_set_hash(sorted((p_, h) for p_, h in body.items())):	    if last is None:
O7	        if kid and not flip:\n            known_n += 1	        if kid:\n            known_n += 1
O9	    if p.returncode != 0:\n        msg = p.stderr	    if False:\n        msg = p.stderr
D1	        if flag == "+":	        if False:
D2	    if dirty:\n        out("RESULT: PARTIAL-DIRTY-TREE	    if False:\n        out("RESULT: PARTIAL-DIRTY-TREE
D3	    elif dirty:\n        h = hashlib.sha256	    elif False:\n        h = hashlib.sha256
D4	, len(ex), ident))	, len(ex), ""))
S5	        if neg and cons != "cond":	        if False:
S6	            cv = False if all(	            cv = "cond" if all(
S7	                    if c is True and not self.errexit and not _status_decides(items, i + 1):	                    if False:
S8	                    c = "all" if _status_decides(items, i + 1) else self.errexit	                    c = "all"
Y1	FAILTOK = _AnyRe(_FAILWORD, _CRASH_I, _CRASH_K)	FAILTOK = _AnyRe(_FAILWORD)
Y2	    rw = {i - off for i in resid if i >= off}	    rw = set()
Y3	    if TAPTODO.match(line.strip()):\n        return "other", None	    if False:\n        return "other", None
W1	    if prob or who not in ids:\n        raise Fatal(3	    if False:\n        raise Fatal(3
W2	    if who not in ids:\n        return "excluded set last accepted by %r, who	    if False:\n        return "excluded set last accepted by %r, who
W3	    if t.returncode != 0 or d.returncode != 0:	    if False:
W4	        if ch != acc_chain(prev, ts, who, seth, rows):	        if False:
W5	    if excl_who:\n        out("RESULT: PARTIAL-EXCLUSIONS-UNACCEPTED	    if False:\n        out("RESULT: PARTIAL-EXCLUSIONS-UNACCEPTED
I1	            if qid != qid0 or "?" in qid:\n                id_changed = "before unit	            if False:\n                id_changed = "before unit
I2	    if not id_changed:\n        qid = quick_ident(root, subs0)	    if False:\n        qid = quick_ident(root, subs0)
I3	    if id_changed:\n        out("RESULT: FAIL (%sidentity	    if False:\n        out("RESULT: FAIL (%sidentity
L1	    if os.path.islink(path):\n        return set(), "operator roster	    if False:\n        return set(), "operator roster
L2	    if os.path.islink(lock_path):\n        return ["%s is a symlink	    if False:\n        return ["%s is a symlink
L3	    if os.path.islink(lock_path):\n        # CON-235	    if False:\n        # CON-235
Z4	    if dirty:\n        out("RESULT: PARTIAL-DIRTY-TREE	    if dirty and not known_n:\n        out("RESULT: PARTIAL-DIRTY-TREE
Z7	        dirty.append("git status failed (rc %d / %d): the tree state is unknown" % (st.returncode, fe.returncode))\n	
G1	    parts.append("gen=%s" % gen_fingerprint(root))	    pass
G2	"%s %s %d %d %d %s\\0" % (os.path.relpath(p, root), kind, st.st_ino,	"%s %s %d %d %d %s\\0" % (os.path.relpath(p, root), kind, 0,
G3	                                                     st.st_mtime_ns, st.st_size, dig)).encode())	                                                     0, st.st_size, dig)).encode())
G4	            if qid != qid0 or "?" in qid:\n                id_changed = "after unit	            if False:\n                id_changed = "after unit
RMb	    for pre in ("", "constitution"):	    for pre in ("",):
F47a	                if ids != {tid}:	                if tid not in ids:
F47b	        elif r[1] != "Issues":	        elif False:
F47c	    if not total:	    if False:
F47d	        if r is None:\n            stale += 1	        if r is None:\n            pass
F47e	        elif r[1] != "Issues":	        elif r[1] == "Fixed":
EOF
)

# CON-236: every mutant id occurs once; a repeated id is refused before the baseline or any mutant runs.
dup_ids=$(printf '%s\n' "$MUTANTS" | cut -f1 | grep -v '^$' | sort | uniq -d | tr '\n' ' ' | sed 's/ $//')
if [ -n "$dup_ids" ]; then echo "FAIL mutant table: duplicate mutant id(s): $dup_ids (each id must occur once; nothing was run)"; exit 2; fi

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
