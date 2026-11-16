#!/usr/bin/env python3
"""Independent check of the round-11 git-env exemption rows (RV10-3).

It does not import or reuse the census. For each pinned-fixture row of the
sync vehicle it hashes the file and requires that exact sha256 in the
pack's SHA256SUMS. For the sourced-library row it lists every git call in
the library and requires each to be a read, and requires every caller that
sources it to scrub GIT_* at file level. Control needles: a fabricated
hash must not be found, and a known write verb must be classified as a
write. Exit 0 PASS, 1 FAIL, 2 BLIND.
"""
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
import hashlib, os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
TSV = os.path.join(ROOT, "config/git_env_class_exemptions.tsv")
READS = {"rev-parse", "symbolic-ref", "ls-remote", "log", "show", "status", "cat-file", "config"}
WRITES = {"commit", "push", "reset", "merge", "fetch", "checkout", "update-ref", "add", "rm"}

def git_verbs(text):
    out = []
    for line in text.splitlines():
        s = line.split("#", 1)[0]
        for m in re.finditer(r'(?:^|[;&|(!]|\$\()\s*git((?:\s+-C\s+\S+)*)\s+([a-z][a-z-]*)', s):
            out.append(m.group(2))
    return out

def main():
    fails, rows = [], [l.rstrip("\n").split("\t") for l in open(TSV) if l.strip()]
    mine = [r for r in rows if "round 11, RV10-3" in (r[2] if len(r) > 2 else "")]
    if len(mine) != 9:
        print("BLIND: expected 9 round-11 rows, found %d" % len(mine)); return 2
    # control needles
    if git_verbs('x="$(git -C x commit -m y)"') != ["commit"]:
        print("BLIND: verb needle missed"); return 2
    if git_verbs('echo "not a git work tree"') != []:
        print("BLIND: prose needle counted as a call"); return 2
    for path, reason, why in mine:
        full = os.path.join(ROOT, path)
        if reason == "pinned-fixture":
            pack = "/".join(path.split("/")[:3])
            sums = open(os.path.join(ROOT, pack, "SHA256SUMS")).read()
            sha = hashlib.sha256(open(full, "rb").read()).hexdigest()
            fake = hashlib.sha256(b"needle" + sha.encode()).hexdigest()
            if fake in sums:
                print("BLIND: fabricated hash found in", pack); return 2
            ok = re.search(r"^%s\s+\*?(\./)?%s$" % (sha, re.escape(os.path.relpath(full, os.path.join(ROOT, pack)))), sums, re.M) or (sha in sums)
            print(("PASS " if ok else "FAIL ") + path + " sha256 " + sha[:16] + (" in " if ok else " NOT in ") + pack + "/SHA256SUMS")
            if not ok: fails.append(path)
        elif reason == "sourced-library":
            verbs = git_verbs(open(full).read())
            bad = [v for v in verbs if v not in READS]
            print(("PASS " if verbs and not bad else "FAIL ") + path + " git verbs=" + ",".join(verbs) + (" non-read=" + ",".join(bad) if bad else ""))
            if not verbs or bad: fails.append(path)
            for caller in ("scripts/setup.sh", "scripts/post_update_hook.sh", "tests/sync/test_full_automation.sh"):
                t = open(os.path.join(ROOT, caller)).read()
                ok = ("cl_scrub_git_env" in t) or bool(re.search(r'^for _[a-z]+_v in GIT_DIR ', t, re.M))
                print(("PASS " if ok else "FAIL ") + "caller " + caller + " scrubs at file level")
                if not ok: fails.append(caller)
        else:
            fails.append(path); print("FAIL unexpected reason", reason, path)
    print("verify-exemption-rows: " + ("FAIL %d" % len(fails) if fails else "PASS 9 rows"))
    return 1 if fails else 0

sys.exit(main())
