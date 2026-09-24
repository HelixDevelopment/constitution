#!/usr/bin/env python3
# ============================================================================
# index_watch.py — progress-PROVEN monitor for a running `codegraph index|init`
# (constitution §11.4.232 liveness truth-source, §11.4.78 / §11.4.80)
# ============================================================================
#
# Purpose
#   "Process is alive" is NOT progress (§11.4.201(6)/(7)). The stock 60 s
#   liveness watchdog only sees the event loop; the failure this tool exists for
#   (a prior bulk-window stall incident) kept the event loop healthy for 2h14m while ONE store-writer
#   thread burned a core reading ~1.6 GB/s and writing nothing. This monitor
#   proves progress from four independent signals and flags a stall with the
#   exact signature:
#
#       progress signals (any one advancing = progressing):
#         1. files stored   — max(rowid) of the `files` table  (read-only)
#         2. DB file size   — grows while rows are inserted
#         3. log progress   — latest `N/M (P%)` line of the verbose log
#         4. write activity — /proc/<pid>/io write_bytes delta of the worker
#       plus context: hottest-thread CPU (the store writer), rchar delta.
#
#   Verdicts:  PROGRESSING | STALL_HOT (no progress + a thread >=50% CPU: the
#   bulk-window stall signature) | STALL_IDLE (no progress, nothing hot: wedged) |
#   NOT_RUNNING (lock holder gone; reports index_state) | STARTING.
#
# Usage
#   index_watch.py --project DIR [--once] [--interval 60] [--stall-min 10]
#                  [--json-out FILE] [--quiet]
#   --once        one sample (uses the persisted previous sample for deltas)
#   loop mode     samples every --interval seconds until the process ends;
#                 exit 0 index complete, 4 process ended without a complete index
#
# Exit codes (--once): 0 PROGRESSING/STARTING, 3 STALL_*, 4 NOT_RUNNING+incomplete,
#                      5 NOT_RUNNING+complete (index_state == complete)
#   The stall clock is persisted, so a --once caller (cron/hook) still detects a
#   stall that spans many invocations.
#
# Inputs   <DIR>/.codegraph/{codegraph.lock,codegraph.db,index_runs/*.log}
# Outputs  <DIR>/.codegraph/index_runs/watch_state.json (atomic), stdout summary
# Side effects  none on the index (read-only DB open, /proc reads)
#
# Cross-references  bulk-window stall, fk_cascade_probe.py, fk_index_patch.py,
#   constitution §11.4.232(C)/(E), §11.4.201, §11.4.273 (every reading is a
#   measurement from the live process, never inferred from liveness alone).
# ============================================================================
import argparse
import glob
import json
import os
import re
import sqlite3
import sys
import time

PROG_RE = re.compile(r"\[(\d+(?:\.\d+)?)s\]\s+([\d,]+)/([\d,]+)\s+\((\d+)%\)")
PHASE_RE = re.compile(r"Phase:\s*(\w+)")
CLK = os.sysconf("SC_CLK_TCK")

# Cold-start lock-file race: the supervisor backgrounds this watcher at
# essentially the same instant it launches the indexer. If the watcher's
# first sample(s) land before the indexer has written .codegraph/codegraph.lock,
# read_lock_pid() returns None and alive is False -- but the indexer is about
# to exist, not absent. Without a bounded retry window, main()'s
# `verdict == NOT_RUNNING -> exit` collapses the watcher one sample after
# birth, before it ever observes a live indexer (found live 2026-09-25,
# constitution/scripts/codegraph/tests/test_watch_startup_race.py). This
# grace is consecutive-not-alive-samples-since-birth, not wall-clock, so it
# is independent of --interval; it never re-arms once alive has genuinely
# been observed even once (a real stop after a real run is always terminal
# on the very next sample).
STARTUP_GRACE_SAMPLES = 3


def read_lock_pid(proj):
    try:
        return int(open(os.path.join(proj, ".codegraph", "codegraph.lock")).read().strip())
    except (OSError, ValueError):
        return None


def real_cmdline(pid):
    try:
        return open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return None


def proc_io(pid):
    d = {}
    try:
        for ln in open(f"/proc/{pid}/io"):
            k, v = ln.split(":")
            d[k.strip()] = int(v)
    except OSError:
        pass
    return d


def thread_cpu(pid):
    out = {}
    try:
        for t in os.listdir(f"/proc/{pid}/task"):
            try:
                s = open(f"/proc/{pid}/task/{t}/stat").read()
                comm = s[s.index("(") + 1:s.rindex(")")]
                f = s[s.rindex(")") + 2:].split()
                out[t] = (comm, int(f[11]) + int(f[12]))
            except (OSError, ValueError, IndexError):
                pass
    except OSError:
        pass
    return out


def db_stats(proj):
    p = os.path.join(proj, ".codegraph", "codegraph.db")
    st = {"db_size": None, "db_mtime": None, "files": None, "nodes": None, "index_state": None}
    try:
        s = os.stat(p)
        st["db_size"], st["db_mtime"] = s.st_size, s.st_mtime
    except OSError:
        return st
    try:
        c = sqlite3.connect(f"file:{p}?mode=ro", uri=True, timeout=3)
        c.execute("pragma busy_timeout=3000")
        st["files"] = c.execute("select max(rowid) from files").fetchone()[0]
        st["nodes"] = c.execute("select max(rowid) from nodes").fetchone()[0]
        try:
            r = c.execute("select value from project_metadata where key='index_state'").fetchone()
            st["index_state"] = r[0] if r else None
        except sqlite3.Error:
            pass
        c.close()
    except sqlite3.Error:
        pass  # BUSY during a commit is normal; size/mtime still give a signal
    return st


def latest_log(proj):
    logs = sorted(glob.glob(os.path.join(proj, ".codegraph", "index_runs", "*.log")), key=os.path.getmtime)
    return logs[-1] if logs else None


def log_progress(path):
    if not path:
        return None, None, None
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            fh.seek(max(0, size - 65536))
            tail = fh.read().decode("utf-8", "replace")
    except OSError:
        return None, None, None
    prog = None
    for m in PROG_RE.finditer(tail):
        prog = (int(m.group(2).replace(",", "")), int(m.group(3).replace(",", "")), int(m.group(4)))
    phase = None
    for m in PHASE_RE.finditer(tail):
        phase = m.group(1)
    return prog, phase, os.path.getmtime(path)


def sample(proj, prev, stall_min):
    now = time.time()
    pid = read_lock_pid(proj)
    cmd = real_cmdline(pid) if pid else None
    alive = bool(cmd and "codegraph" in cmd)
    db = db_stats(proj)
    log = latest_log(proj)
    prog, phase, log_mtime = log_progress(log)
    io = proc_io(pid) if alive else {}
    cpu = thread_cpu(pid) if alive else {}
    cur = {"t": now, "pid": pid, "alive": alive, "db": db, "log": log, "phase": phase,
           "progress": prog, "io": io, "cpu": {k: v[1] for k, v in cpu.items()}}
    dt = (now - prev["t"]) if prev else None
    hot_name, hot_pct, rchar_mb_s = None, 0.0, 0.0
    if prev and dt and dt > 0 and alive and prev.get("pid") == pid:
        best = (0, None)
        for tid, (comm, ticks) in cpu.items():
            d = ticks - prev["cpu"].get(tid, ticks)
            if d > best[0]:
                best = (d, comm)
        hot_pct = best[0] / CLK / dt * 100
        hot_name = best[1]
        rchar_mb_s = (io.get("rchar", 0) - prev["io"].get("rchar", 0)) / dt / 1e6 if prev.get("io") else 0.0
    progressed = False
    if not prev or prev.get("pid") != pid:
        progressed = True
    else:
        pdb = prev["db"]
        progressed = any([
            (db["files"] or 0) > (pdb.get("files") or 0),
            (db["db_size"] or 0) > (pdb.get("db_size") or 0),
            prog is not None and (prev.get("progress") is None or prog[0] > prev["progress"][0]),
            io.get("write_bytes", 0) > prev.get("io", {}).get("write_bytes", 0) + 4096,
        ])
    last_progress_t = now if progressed else (prev or {}).get("last_progress_t", now)
    cur["last_progress_t"] = last_progress_t
    stalled_s = now - last_progress_t
    ever_alive = alive or bool((prev or {}).get("ever_alive"))
    not_alive_streak = 0 if alive else (prev or {}).get("not_alive_streak", 0) + 1
    if not alive:
        if not ever_alive and not_alive_streak <= STARTUP_GRACE_SAMPLES:
            verdict = "STARTING"
        else:
            verdict = "NOT_RUNNING"
    elif prev is None:
        verdict = "STARTING"
    elif stalled_s >= stall_min * 60:
        verdict = "STALL_HOT" if hot_pct >= 50 else "STALL_IDLE"
    else:
        verdict = "PROGRESSING"
    cur.update({"verdict": verdict, "stalled_s": round(stalled_s), "hot_thread": hot_name,
                "hot_cpu_pct": round(hot_pct, 1), "rchar_mb_s": round(rchar_mb_s, 1),
                "ever_alive": ever_alive, "not_alive_streak": not_alive_streak})
    return cur


def summary(s):
    pr = s["progress"]
    pstr = f"{pr[0]:,}/{pr[1]:,} ({pr[2]}%)" if pr else "-"
    db = s["db"]
    return (f"{time.strftime('%H:%M:%S')} {s['verdict']:<11} phase={s['phase'] or '-'} log={pstr} "
            f"files_stored={db['files'] if db['files'] is not None else '-'} db={((db['db_size'] or 0) / 1e9):.2f}GB "
            f"hot={s['hot_thread'] or '-'}@{s['hot_cpu_pct']}% read={s['rchar_mb_s']}MB/s stalled={s['stalled_s']}s "
            f"state={db['index_state'] or '-'}")


def main():
    ap = argparse.ArgumentParser(description="Progress-proven monitor for codegraph index/init")
    ap.add_argument("--project", required=True)
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--interval", type=int, default=60)
    ap.add_argument("--stall-min", type=float, default=10.0)
    ap.add_argument("--json-out")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    proj = os.path.abspath(a.project)
    state_path = os.path.join(proj, ".codegraph", "index_runs", "watch_state.json")
    os.makedirs(os.path.dirname(state_path), exist_ok=True)

    def load():
        try:
            return json.load(open(state_path))
        except (OSError, ValueError):
            return None

    def save(s):
        tmp = state_path + ".tmp"
        json.dump(s, open(tmp, "w"))
        os.replace(tmp, state_path)

    def code(s):
        v = s["verdict"]
        if v in ("PROGRESSING", "STARTING"):
            return 0
        if v.startswith("STALL"):
            return 3
        return 5 if s["db"]["index_state"] == "complete" else 4

    prev = load()
    while True:
        s = sample(proj, prev, a.stall_min)
        save(s)
        if not a.quiet:
            print(summary(s), flush=True)
        if a.json_out:
            json.dump(s, open(a.json_out, "w"), indent=2)
        if a.once or s["verdict"] == "NOT_RUNNING":
            return code(s)
        prev = s
        time.sleep(a.interval)


if __name__ == "__main__":
    sys.exit(main())
