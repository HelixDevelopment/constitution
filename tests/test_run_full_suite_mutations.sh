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
# dirty tree + KNOWN is exit 10, a failing git status reads dirty=unknown); G1-G4 guard the WIT-C02 per-unit
# fingerprint of the generated command sets (ownership wave 2 review r2: gen field, inode, mtime, after-unit check;
# RMb = the reviewer's mutant of review r2, the vendored constitution/ prefix; I1/I2 re-pinned by section 39 in
# round 3; re-anchored in CON-030 round 5 to the structured QuickIdent.gen field); M7+ are the author's own; M30a-M30n guard CON-030 (submodule paths read whole: the
# sub_paths / topology parser, the known-path set from `git ls-files -s -z`, the newline-joined quick identity; they
# are unrelated to the lock mutant M30, the ids are selected by exact token) and RA RB RF are the reviewer-authored
# mutants of CON-030 review r1 (section 11.4.276(D)). CON-030 round 3 (review r2, structural round): the quick
# identity became a structure (QuickIdent), so M30b (identity fields joined by a space), M30m (partition instead of
# rpartition of `<path>=<value>`) and M30n (`?` searched in the whole text) are removed with the text they mutated;
# G3D (the round-2 dict check, whose root `status` key a submodule `status` overwrote) and G3R (unknown checked on
# the root only) take their place; M32 X4 X5 M30a M30i M30l RB are re-anchored to the round-3 code with the same
# change; RV1-RV8 are the reviewer-authored mutants of review r2 (RV3 RV7 RV8 re-anchored to the structural code:
# unknown never detected, a path label without repr(), unknown-at-both-ends not reported); Q1-Q13 guard the class
# members fixed in round 3 (the `?` Go-module marker, unframed tree hash, `#` and non-UTF-8 census names, CR-safe
# table readers, the newline-path and doubly-named gaps, bytes symlink targets, the old `<absent>` marker, path
# display and surrogateescape decoding). CON-030 round 4 (review r3, structural round again): Q5 Q5k Q5x Q5c are
# re-anchored to the ONE governance reader gov_lines (universal-newline split, refusal dropped, read_roster reading
# its file by itself with splitlines() = the H2 mutant, CRLF tolerance dropped); M2 is re-anchored to the structured
# key; H1a-H1d guard the structured unit key (joined id compared again = the H1 mutant, the display and key
# refusals of plan(), args dropped from the key); H2a H2b the reader (manifest read with splitlines(), C1 and the
# Unicode separators dropped from the class); H3a-H3d the output escaping (raw stdout = the H3 mutant, raw
# summary.txt, CR names listed again, the escape itself dropped); RW1-RW6 are the reviewer-authored mutants of
# review r3, adopted verbatim (RW6 re-anchored: the joined uid it mutated is display-only now, so it drops the
# args from the structured key instead). A mutant counts as KILLED only when the self-test
# exits non-zero AND prints at least one `FAIL ` check line (a crash with no failing check is not a
# kill). Usage: bash tests/test_run_full_suite_mutations.sh [MUTANT_ID...]
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
M2	return (rec_key(o) == u["key"] and o["sha"] == sha and	return (rec_key(o) == u["key"] and
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
M32	        hrec(h, b"I", f)\n        hrec(h, b"D", file_digest(os.path.join(os.fsencode(root), f)))	        pass
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
X4	            if body is not None and hashlib.sha256(body).hexdigest() == o["log_sha256"]:	            if True:
X5	        hrec(h, b"U", f)\n        hrec(h, b"D", file_digest(os.path.join(os.fsencode(root), f)))	        hrec(h, b"U", f)
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
I1	            if qid != qid0 or ident_unknown(qid):\n                id_changed = "before unit	            if False:\n                id_changed = "before unit
I2	    if not id_changed:\n        qid = quick_ident(root, subs0)	    if False:\n        qid = quick_ident(root, subs0)
I3	    if id_changed:\n        out("RESULT: FAIL (%sidentity	    if False:\n        out("RESULT: FAIL (%sidentity
L1	    if os.path.islink(path):\n        return set(), "operator roster	    if False:\n        return set(), "operator roster
L2	    if os.path.islink(lock_path):	    if False:
Z4	    if dirty:\n        out("RESULT: PARTIAL-DIRTY-TREE	    if dirty and not known_n:\n        out("RESULT: PARTIAL-DIRTY-TREE
Z7	        dirty.append("git status failed (rc %d / %d): the tree state is unknown" % (st.returncode, fe.returncode))\n	
M30a	        parsed = parse_sub_status(line, known)\n        if parsed is not None and parsed[0] != "-" and parsed[2] not in out_:\n            out_.append(parsed[2])	        f = line[1:].split()\n        if line[:1] != "-" and len(f) >= 2:\n            out_.append(f[1])
M30c	        flag, sha, path = parsed\n	        flag, rest = line[0], line[1:].split()\n        sha, path = rest[0], rest[1]\n
M30d	                        "[ (<describe>)]): %r" % line)\n            continue	                        "[ (<describe>)]): %r" % line)\n            gaps.pop()\n            continue
M30e	            if d and " " not in d and rest[:i] in known:	            if d and " " not in d and "(" not in d and ")" not in d and rest[:i] in known:
M30f	        if rest in known:\n            cands.add	        if True:\n            cands.add
M30g	    return cands.pop() if len(cands) == 1 else None	    return cands.pop() if cands else None
M30h	        if flag in (" ", "+") and i >= 0	        if i >= 0
M30i	    return [l for l in os.fsdecode(stdout).split("\\n") if l]	    return [l for l in os.fsdecode(stdout).splitlines() if l]
M30j	                    todo.append(full)	                    pass
M30k	"config", "-f", ".gitmodules", "--null", "--get-regexp",	"config", "-f", ".gitmodules", "--get-regexp",
M30l	    for rec in os.fsdecode(git(root, "ls-files", "-s", "-z", binary=True)).split("\\0"):	    for rec in git(root, "ls-files", "-s").split("\\n"):
RA	    for w in (40, 64):	    for w in (40,):
RB	        if parsed is not None and parsed[0] != "-" and parsed[2] not in out_:\n            out_.append(parsed[2])	        if parsed is not None and parsed[2] not in out_:\n            out_.append(parsed[2])
RF	            out_.append(parsed[2])	            out_.append(parsed[2].strip())
G3D	    return q.status is None or any(v is None for _p, v in q.heads)	    return None in dict([(p or ".", v) for p, v in q.heads] + [("status", q.status)]).values()
G3R	    return q.status is None or any(v is None for _p, v in q.heads)	    return q.status is None or q.heads[0][1] is None
RV1	        if flag in (" ", "+") and i >= 0 and rest.endswith(")"):	        if flag in (" ", "+") and i >= 0:
RV2	            if d and " " not in d and rest[:i] in known:	            if " " not in d and rest[:i] in known:
RV3	    return q.status is None or any(v is None for _p, v in q.heads)	    return False
RV4	                if os.path.lexists(os.path.join(root, full, ".git")):	                if True:
RV5	        i = rest.rfind(" (")	        i = rest.find(" (")
RV6	        if nl and val.rstrip("/"):\n            paths.append(val.rstrip("/"))	        if nl and val.rstrip("/"):\n            paths.append(val.strip().rstrip("/"))
RV7	    return "root HEAD" if field[1] is None else "submodule %r" % (field[1],)	    return "root HEAD" if field[1] is None else "submodule %s" % (field[1],)
RV8	 for (k, va), (_k, vb) in zip(fa, fb) if va != vb or vb is None)	 for (k, va), (_k, vb) in zip(fa, fb) if va != vb)
Q1	    for m in sorted(set(mm for mm in (go_module(root, g) for g in gofiles) if mm is not None)):	    for m in sorted(set(mm for mm in (go_module(root, g) for g in gofiles) if mm is not None and not mm.startswith("?"))):
Q2	        h.update(tag + b"%d:" % len(data))	        h.update(tag)
Q3	        if f.startswith("#"):	        if False:
Q4	        if f != os.fsencode(f).decode("utf-8", "replace"):	        if False:
Q5	    for n, line in enumerate(text.split("\\n"), 1):	    for n, line in enumerate(text.splitlines(), 1):
Q5k	        if mm:\n            raise GovLineError(path, n, mm.group(0))	        if False:\n            raise GovLineError(path, n, mm.group(0))
Q5x	    try:\n        lines = gov_lines(path)\n    except GovLineError as e:\n        # review r3 H2	    try:\n        lines = list(enumerate(open(path, errors="replace").read().splitlines(), 1))\n    except GovLineError as e:\n        # review r3 H2
Q5c	        if line.endswith("\\r"):\n            line = line[:-1]\n        mm = LINE_BREAKERS	        if False:\n            line = line[:-1]\n        mm = LINE_BREAKERS
Q6	    for path in sorted(x for x in known if "\\n" in x):	    for path in []:
Q7	        if path in seen:	        if False:
Q8	            return b"L" + os.readlink(p)	            return b"L" + os.readlink(os.fsdecode(p)).encode()
Q9	        return None\n\n\ndef hrec	        return b"<absent>"\n\n\ndef hrec
Q10	    return os.fsencode(path).decode("utf-8", "backslashreplace")	    return path
Q11	        for rec in os.fsdecode(p.stdout).split("\\0"):\n            meta, tab, path = rec.partition("\\t")\n            if not tab or not meta.startswith("160000 "):	        for rec in p.stdout.decode(errors="replace").split("\\0"):\n            meta, tab, path = rec.partition("\\t")\n            if not tab or not meta.startswith("160000 "):
Q12	    raw = os.fsdecode(git(root, "ls-files", "-co", "--exclude-standard", "-z", binary=True))	    raw = git(root, "ls-files", "-co", "--exclude-standard", "-z", binary=True).decode(errors="replace")
Q13	        if parsed is not None and parsed[0] != "-" and parsed[2] not in out_:	        if parsed is not None and parsed[0] != "-":
H1a	    return (rec_key(o) == u["key"] and o["sha"] == sha	    return (o["unit"] == u["id"] and o["sha"] == sha
H1b	        if u["id"] in ids:	        if False:
H1c	        if u["key"] in keys:	        if False:
H1d	        units.append({"id": uid, "key": (path, tuple(args)),	        units.append({"id": uid, "key": (path, ()),
H2a	        lines = gov_lines(path)\n    except GovLineError as e:\n        raise Fatal(3, "manifest	        lines = list(enumerate(open(path).read().splitlines(), 1))\n    except GovLineError as e:\n        raise Fatal(3, "manifest
H2b	LINE_BREAKERS = re.compile("[\\x00-\\x08\\x0a-\\x1f\\x7f-\\x9f\\u2028\\u2029]")	LINE_BREAKERS = re.compile("[\\x00-\\x08\\x0a-\\x1f\\x7f]")
H3a	    sys.stdout.write(esc_out(msg) + "\\n")	    sys.stdout.write(msg + "\\n")
H3b	        fh.write("".join(esc_out(l) + "\\n" for l in summ))	        fh.write("".join(l + "\\n" for l in summ))
H3c	        bad = LINE_BREAKERS.search(f) or ("\\t" if "\\t" in f else None)	        bad = re.search("[\\n\\t]", f)
H3d	    s = LINE_BREAKERS.sub(one, s)	    pass
RW1	    return q.status is None or any(v is None for _p, v in q.heads)	    return any(v is None for _p, v in q.heads)
RW2	    status = hashlib.sha256(st.stdout).hexdigest()[:16] if st.returncode == 0 else None	    status = "s"
RW3	    status = hashlib.sha256(st.stdout).hexdigest()[:16] if st.returncode == 0 else None	    status = hashlib.sha256(st.stdout).hexdigest()[:16]
RW4	        h.update(tag + b"-;")	        h.update(tag + b"0:")
RW5	        if path in seen:	        if path in seen and flag == " ":
RW6	    return (rec_key(o) == u["key"] and	    return (rec_key(o)[0] == u["key"][0] and
G1	    return QuickIdent(tuple(heads), status, gen_fingerprint(root))	    return QuickIdent(tuple(heads), status, "g")
G2	                hrec(h, b"i", b"%d" % st.st_ino)	                hrec(h, b"i", b"%d" % 0)
G3	                hrec(h, b"m", b"%d" % st.st_mtime_ns)	                hrec(h, b"m", b"%d" % 0)
G4	            if qid != qid0 or ident_unknown(qid):  # review r4 K5	            if False:  # review r4 K5
RMb	    for pre in ("", "constitution"):	    for pre in ("",):
EOF
)

# An id names exactly one row: selection by id would otherwise run every row that shares it.
dups=$(printf '%s\n' "$MUTANTS" | cut -f1 | grep -v '^$' | sort | uniq -d)
if [ -n "$dups" ]; then echo "FAIL mutant table: duplicate id(s): $(echo $dups)"; exit 2; fi

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
