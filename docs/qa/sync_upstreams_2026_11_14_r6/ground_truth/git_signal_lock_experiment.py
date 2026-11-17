#!/usr/bin/env python3
"""Ground truth for RV5-1 (review round 6): which signal lets git clean up after a slow write?
A real `git merge --ff-only` and a real `git checkout --detach` are slowed by a smudge filter (sleep 2 per
file, 6 files) and their OWN process group (start_new_session, pgid == pid > 1, section 11.4.263) is sent
SIGTERM or SIGKILL 3 s after start. Recorded: git's exit status, whether .git/index.lock is left, and the
first status lines. Usage: python3 -I git_signal_lock_experiment.py REPO_CLONE"""
import os
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(sys.argv[1], "scripts", "sync"))
import robustness_checks as RC  # noqa: E402

print("git:", subprocess.run([RC.GIT, "--version"], capture_output=True, text=True).stdout.strip())
for op in ("merge", "checkout"):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        box = RC.Box("gt_%s_%d" % (op, sig))
        try:
            r_url, r_seed = box.bare("HelixDevelopment", "root")
            work = box.clone(r_url, "p")
            with open(os.path.join(r_seed, ".gitattributes"), "w") as f:
                f.write("*.slow filter=slow\n")
            for i in range(6):
                with open(os.path.join(r_seed, "f%d.slow" % i), "w") as f:
                    f.write("x%d\n" % i)
            box.git(r_seed, "add", ".")
            box.git(r_seed, "commit", "-q", "-m", "slow")
            box.git(r_seed, "push", "-q", "origin", "HEAD:main")
            box.git(work, "fetch", "-q", "origin")
            box.git(work, "config", "filter.slow.smudge", "sleep 2; cat")
            box.git(work, "config", "filter.slow.clean", "cat")
            tgt = box.git(work, "rev-parse", "origin/main")
            argv = [RC.GIT, "-C", work] + (["merge", "--ff-only", tgt] if op == "merge"
                                          else ["checkout", "--quiet", "--detach", tgt])
            p = subprocess.Popen(argv, env=box.env, start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(3)
            lock_during = os.path.exists(os.path.join(work, ".git", "index.lock"))
            pg = os.getpgid(p.pid)
            if isinstance(pg, int) and pg > 1 and pg == p.pid:
                os.killpg(pg, sig)
            p.wait()
            time.sleep(0.5)
            st = box.git(work, "status", "--porcelain=v1", check=False).splitlines()
            print("op=%s signal=%s rc=%s lock_during=%s index_lock_left=%s status_lines=%d first=%s"
                  % (op, signal.Signals(sig).name, p.returncode, lock_during,
                     os.path.exists(os.path.join(work, ".git", "index.lock")), len(st), st[:2]))
        finally:
            box.cleanup()
