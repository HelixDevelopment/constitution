#!/usr/bin/env python3
"""tests/sync/test_mutations.py -- §1.1 paired-mutation suite for scripts/sync/sync_all_upstreams.py.

Each mutant is ONE textual change of the engine (its anchor must occur exactly once, otherwise the harness
fails: a mutant that silently does not apply would be counted as killed). The mutated engine + wrapper are
copied to a scratch directory; the unit suite runs first (SYNC_ENGINE_PY), and when the mutant survives it,
the suite named for that mutant runs against the mutated wrapper (SX_ENGINE). KILLED = some suite exits
non-zero. A SURVIVOR makes this file exit 1, unless the mutant is listed in EQUIVALENT with the reason.

Usage: python3 -I tests/sync/test_mutations.py [--only M07,M15]   Exit 0 all killed, 1 a survivor/harness error.
Runs suites sequentially at the caller's priority (run it under `nice -n 10`); scratch under $TMPDIR.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ENGINE = os.path.join(REPO, "scripts", "sync", "sync_all_upstreams.py")
WRAPPER = os.path.join(REPO, "scripts", "sync", "sync_all_upstreams.sh")

# (id, what it breaks, old, new, suite run when the unit suite does not kill it)
MUTANTS = [
    ("M01", "+refspec allowed", 'if a.startswith("+"):', 'if False:', "integration"),
    ("M02", "transport helper :: allowed", 'if "::" in a:', 'if False:', "integration"),
    ("M03", "push on the write allow-list", 'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add"}',
     'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add", "push"}', "integration"),
    ("M04", "merge shape not enforced", 'if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):',
     'if False:', "integration"),
    ("M05", "checkout shape not enforced",
     'if len(rest) != 3 or rest[0] != "--quiet" or rest[1] != "--detach" or not SHA_RE.match(rest[2]):', 'if False:',
     "integration"),
    ("M06", "add path not checked", 'if len(rest) != 2 or rest[0] != "--" or not safe_relpath(rest[1]):', 'if False:',
     "integration"),
    ("M07", "fetch option prefix not enforced", 'if tail[:2] != allowed:', 'if False:', "integration"),
    ("M08", "URL userinfo not redacted", 't = _USERINFO.sub(r"\\1", str(text))', 't = str(text)', "security"),
    ("M09", "tokens not redacted", 't = _TOKENS.sub("[REDACTED]", t)', 't = t', "security"),
    ("M10", "git may prompt", 'env["GIT_TERMINAL_PROMPT"] = "0"', 'env["GIT_TERMINAL_PROMPT"] = "1"', "security"),
    ("M11", "ambient GIT_DIR kept", 'if k in _SCRUB or ', 'if k in () or ', "security"),
    ("M12", "jobs ceiling 64", 'ceiling = max(1, min(8, (cpus or 1) // 2))', 'ceiling = max(1, min(64, (cpus or 1) // 2))',
     "perf"),
    ("M13", "behind classified as ahead", 'if ahead == 0:\n        return "behind"', 'if ahead == 0:\n        return "ahead"',
     "integration"),
    ("M14", "newest = first, not the linear maximum", 'if all(o == c or ancestor(o, c) for o in uniq):', 'if True:',
     "integration"),
    ("M15", "MERGE_HEAD not detected", 'names = ("MERGE_HEAD", ', 'names = (', "integration"),
    ("M16", "dirty tree not detected", 'rec["dirty"] = (st[0] != 0) or bool(st[1].strip())', 'rec["dirty"] = False',
     "integration"),
    ("M17", "dirty tree does not block integration", 'x.startswith(("dirty-tree", "in-progress",', 'x.startswith(("in-progress",',
     "integration"),
    ("M18", "fast-forward without consent",
     'if rec.get("local_vs_target") == "behind" and consent.get("integrate"):', 'if rec.get("local_vs_target") == "behind":',
     "ui"),
    ("M19", "dry-run fetches", 'mode in ("check", "apply") and not a.no_fetch', 'mode in ("check", "apply", "dry-run") and not a.no_fetch',
     "integration"),
    ("M20", "--no-fetch ignored", '"fetch": mode in ("check", "apply") and not a.no_fetch,', '"fetch": mode in ("check", "apply"),',
     "integration"),
    ("M21", "third-party pins advanced without the flag",
     '\n                    and (rec.get("own_org") or advance_third_party))', ')', "integration"),
    ("M22", "children never follow", 'new_links = gitlinks(r, repo.abspath)', 'new_links = {}', "integration"),
    ("M23", "pin not on main not reported", 'elif not on_main:\n            pin["state"] = "not-on-main"',
     'elif False:\n            pin["state"] = "not-on-main"', "integration"),
    ("M24", "unfetchable pin reported at-main", 'pin["state"] = "unfetchable"', 'pin["state"] = "at-main"', "integration"),
    ("M25", "timestamp enters the canonical hash", 'VOLATILE = {"started", ', 'VOLATILE = {', "determinism"),
    ("M26", "--out inside the work tree allowed", 'if out_dir == root or out_dir.startswith(root + os.sep):', 'if False:',
     "integration"),
    ("M27", "lock per process (no mutual exclusion)", '"helix-sync-upstreams.lock")',
     '"helix-sync-upstreams.lock.%d" % os.getpid())', "chaos"),
    ("M28", "behind reported as exit 0", 'elif any_behind:', 'elif False:', "integration"),
    ("M29", "third-party pin behind counts as an update",
     'if pin.get("state") == "behind-main" and rec.get("own_org"):', 'if pin.get("state") == "behind-main":', "integration"),
    ("M30", "root not on main not reported", 'reasons.append("root-not-on-" + branch)', 'pass', "integration"),
    ("M31", "control needle always fails", 'ok = bool(n and', 'ok = False and bool(n and', "integration"),
    ("M32", "timeout does not kill the process group", 'os.killpg(pgid, signal.SIGKILL)', 'pass', "chaos"),
    ("M33", "failed fetch not reported unreachable", 'if rem.get("fetch") in ("failed", "timeout"):', 'if False:', "chaos"),
    ("M34", "Enter means yes", 'in ("y", "yes")', 'in ("y", "yes", "")', "ui"),
    ("M35", "dirty child followed", 'if c.rec.get("head_before") != old or c.rec.get("dirty") or c.rec.get("in_progress"):',
     'if c.rec.get("head_before") != old:', "integration"),
    ("M36", "follow only under the fast-forward consent (pin consent ignored)",
     'if not (consent.get("integrate") or consent.get("pins")):', 'if not consent.get("integrate"):', "ui"),
    ("M37", "follow consent guard removed",
     '        if not (consent.get("integrate") or consent.get("pins")):\n            continue\n', '', "ui"),
]
# id -> proof. A mutant listed here may survive; it is reported EQUIVALENT, never KILLED.
EQUIVALENT = {
    "M37": "follow_children acts only when the parent's gitlink at a path differs from the one read at discovery "
           "(new != old). In one run a repository's gitlinks change only by (a) `merge --ff-only` in it, guarded by "
           "consent 'integrate'; (b) its own pin advance (`checkout --detach` in it), guarded by consent 'pins'; or "
           "(c) its own follow, guarded by this same check in the call for ITS parent. By induction over depth, "
           "new != old implies integrate or pins was granted, so the guard can never be the deciding condition; it "
           "is kept as defence in depth.",
}

SUITES = {s: os.path.join(HERE, "test_%s.sh" % s) for s in
          ("integration", "security", "chaos", "ui", "e2e", "determinism", "perf", "full_automation")}


def run(cmd, env, timeout):
    t = time.monotonic()
    try:
        p = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace"), time.monotonic() - t
    except subprocess.TimeoutExpired as e:
        return 124, (e.stdout or b"").decode("utf-8", "replace"), time.monotonic() - t


def main(argv):
    only = None
    if len(argv) == 2 and argv[0] == "--only":
        only = set(argv[1].split(","))
    src = open(ENGINE, encoding="utf-8").read()
    scratch = tempfile.mkdtemp(prefix="sync_mut.", dir=os.environ.get("TMPDIR") or None)
    killed, survivors, errors, rows = 0, [], [], []
    try:
        for mid, what, old, new, suite in MUTANTS:
            if only and mid not in only:
                continue
            if src.count(old) != 1:
                errors.append("%s: anchor occurs %d times" % (mid, src.count(old)))
                print("ERROR %s anchor occurs %d times" % (mid, src.count(old)))
                continue
            d = os.path.join(scratch, mid)
            os.makedirs(d)
            open(os.path.join(d, "sync_all_upstreams.py"), "w", encoding="utf-8").write(src.replace(old, new))
            shutil.copy(WRAPPER, os.path.join(d, "sync_all_upstreams.sh"))
            env = dict(os.environ, SYNC_ENGINE_PY=os.path.join(d, "sync_all_upstreams.py"),
                       SX_ENGINE=os.path.join(d, "sync_all_upstreams.sh"))
            rc, out, dur = run([sys.executable, "-I", os.path.join(HERE, "test_unit.py")], env, 120)
            by = "unit"
            if rc == 0:
                rc, out, dur2 = run(["bash", SUITES[suite]], env, 600)
                by, dur = suite, dur + dur2
            if rc != 0:
                killed += 1
                verdict = "KILLED"
            elif mid in EQUIVALENT:
                verdict = "EQUIVALENT"
            else:
                verdict = "SURVIVED"
                survivors.append(mid)
            rows.append((mid, verdict, by, "%.1f" % dur, what))
            print("%-4s %-10s by %-12s %6ss  %s" % rows[-1], flush=True)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)   # scratch made by mkdtemp above, under $TMPDIR
    total = len(rows)
    print("sync-mutations: mutants %d killed %d equivalent %d survived %d harness-errors %d"
          % (total, killed, sum(1 for r in rows if r[1] == "EQUIVALENT"), len(survivors), len(errors)))
    return 0 if not survivors and not errors and total > 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
