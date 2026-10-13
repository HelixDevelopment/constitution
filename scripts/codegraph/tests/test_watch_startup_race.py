#!/usr/bin/env python3
# ============================================================================
# test_watch_startup_race.py — RED-then-GREEN regression test for
# index_watch.py's cold-start lock-file race (§11.4.115/§11.4.224).
#
# Bug (found live, 2026-09-25): index_watch.py's main() loop exits the
# instant ANY sample reports verdict NOT_RUNNING (line: `if a.once or
# s["verdict"] == "NOT_RUNNING": return code(s)`). sample() classifies
# NOT_RUNNING purely from whether `.codegraph/codegraph.lock` currently
# names a live "codegraph"-cmdline process. On a genuine cold start the
# supervisor backgrounds the watcher at essentially the same instant it
# launches the indexer -- if the watcher's FIRST sample lands before the
# indexer has written its lock file, read_lock_pid() returns None, alive
# is False, verdict is NOT_RUNNING, and the watcher exits forever, one
# sample after being born, with the indexer never actually observed --
# leaving a live, multi-hour bulk index run with ZERO stall detection
# (the exact §11.4.232(C) liveness-truth-source property this tool exists
# to provide). Reproduced live: watcher pid 440251 logged exactly one
# line ("NOT_RUNNING ... pid: null ... db=0.00GB") and was gone.
#
# Fix: a bounded startup-grace window (a few consecutive not-alive
# samples) before a NEVER-yet-seen-alive indexer is treated as terminal;
# a genuinely-stopped indexer that WAS previously seen alive (or that
# stays absent past the grace window) still resolves NOT_RUNNING exactly
# as before -- this is additive-only, never masks a real absence.
#
# Anti-bluff: this test imports sample() directly (unit-level, no
# subprocess launch, no time.sleep-based race) and drives it through the
# exact byte-for-byte sequence a cold start produces: lock-file-absent
# sample(s), then lock-file-present-and-alive sample. RED on the
# unpatched module, GREEN after the fix -- run this file directly.
# ============================================================================
import importlib.util
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_PATH = os.path.join(HERE, "..", "index_watch.py")


def load_module():
    spec = importlib.util.spec_from_file_location("index_watch_under_test", MODULE_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_lock(proj, pid):
    with open(os.path.join(proj, ".codegraph", "codegraph.lock"), "w") as f:
        f.write(str(pid))


def main():
    mod = load_module()
    failures = []

    # ---- Case 1: cold-start race -- first sample has NO lock file yet ----
    # (indexer hasn't written it) but a real "codegraph"-cmdline process IS
    # about to appear. The watcher must NOT conclude NOT_RUNNING on sample 1.
    with tempfile.TemporaryDirectory() as proj:
        os.makedirs(os.path.join(proj, ".codegraph", "index_runs"))
        s1 = mod.sample(proj, None, stall_min=10.0)
        if s1["verdict"] != "STARTING":
            failures.append(
                f"CASE1 sample1 (no lock file yet): expected STARTING, got {s1['verdict']!r} "
                f"-- this IS the bug: a cold-start race would kill the watcher here"
            )
        # A second still-cold sample: still no lock file. Must still retry
        # (within the grace window), not give up yet.
        s2 = mod.sample(proj, s1, stall_min=10.0)
        if s2["verdict"] == "NOT_RUNNING":
            failures.append(
                f"CASE1 sample2 (still no lock, within grace): expected STARTING/retry, "
                f"got NOT_RUNNING -- grace window too short or absent"
            )
        # Now the indexer "arrives": real process, cmdline contains
        # "codegraph" (matches sample()'s alive check), lock file written.
        proc = subprocess.Popen(
            [sys.executable, "-c",
             "import time; time.sleep(30)  # codegraph_fake_indexer_marker"],
        )
        try:
            time.sleep(0.1)  # let exec() replace the process image before /proc read
            write_lock(proj, proc.pid)
            s3 = mod.sample(proj, s2, stall_min=10.0)
            if not s3["alive"]:
                failures.append(
                    "CASE1 sample3 (lock now present, real live proc): expected alive=True, "
                    f"got alive=False (pid={s3['pid']})"
                )
            if s3["verdict"] not in ("STARTING", "PROGRESSING"):
                failures.append(
                    f"CASE1 sample3: expected a non-terminal verdict once the indexer is "
                    f"genuinely alive, got {s3['verdict']!r}"
                )
        finally:
            proc.terminate()
            proc.wait(timeout=5)

    # ---- Case 2: genuine absence must still resolve NOT_RUNNING ----
    # (the fix must be additive-only -- it must not mask a real "never
    # started at all" case forever).
    with tempfile.TemporaryDirectory() as proj:
        os.makedirs(os.path.join(proj, ".codegraph", "index_runs"))
        prev = None
        last = None
        for _ in range(20):  # far more than any reasonable grace window
            last = mod.sample(proj, prev, stall_min=10.0)
            prev = last
        if last["verdict"] != "NOT_RUNNING":
            failures.append(
                f"CASE2 (indexer genuinely never appears, 20 consecutive samples): "
                f"expected eventual NOT_RUNNING, got {last['verdict']!r} -- grace window "
                f"must be bounded, not infinite"
            )

    # ---- Case 3: a real stop AFTER having genuinely run must still be
    # terminal on the very next sample (no grace re-granted mid-run). ----
    with tempfile.TemporaryDirectory() as proj:
        os.makedirs(os.path.join(proj, ".codegraph", "index_runs"))
        proc = subprocess.Popen(
            [sys.executable, "-c",
             "import time; time.sleep(30)  # codegraph_fake_indexer_marker"],
        )
        try:
            time.sleep(0.1)  # let exec() replace the process image before /proc read
            write_lock(proj, proc.pid)
            s1 = mod.sample(proj, None, stall_min=10.0)
            if not s1["alive"]:
                failures.append("CASE3 setup: expected alive=True while the fake indexer runs")
        finally:
            proc.terminate()
            proc.wait(timeout=5)
        # lock file now points at a dead pid -- real stop, must be terminal
        # immediately (no fresh grace period just because it once ran).
        s2 = mod.sample(proj, s1, stall_min=10.0)
        if s2["verdict"] != "NOT_RUNNING":
            failures.append(
                f"CASE3 (indexer WAS alive, now genuinely stopped): expected immediate "
                f"NOT_RUNNING, got {s2['verdict']!r} -- a real stop must never be masked"
            )

    if failures:
        print("RED (bug present / fix incomplete):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("GREEN: cold-start grace present, genuine-absence still resolves, "
          "post-alive stop still terminal immediately (3/3 cases)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
