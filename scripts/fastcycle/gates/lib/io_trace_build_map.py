#!/usr/bin/env python3
"""io_trace_build_map.py -- builds/refreshes the persisted gate->inputs map
(SpecKit-004 "fast-dev-cycles", User Story 2; plan.md T-C02; tasks.md T066;
invoked by gates/io_trace.sh's `build-map` subcommand -- see that file's
own header comment for the full CLI contract and design rationale).

T085 Round 1 remediation (2026-09-30, B2): `io_trace.sh build-map` has,
since T066 landed, called `python3 $HERE/lib/io_trace_build_map.py ...` --
but this module never existed (confirmed: `git log --all -- '**/
io_trace_build_map.py'` was empty). Running `build-map` therefore failed
immediately with `python3: can't open file ... [Errno 2] No such file or
directory`, rc=2, reproduced live before this fix (§11.4.199) --
T066's own recorded evidence text calling it "a genuine, functional
implementation" was false. This file is that missing implementation.

Design (per io_trace.sh's own header, the binding CLI contract this
module implements): iterates every `*.sh` script under `--sections-dir`
(recursively), computes each script's content sha256, and re-traces
(via `<--tool> trace <script>`, i.e. gates/io_trace.sh's own `trace`
subcommand -- never a second, divergent strace-invocation implementation)
ONLY a script whose hash differs from -- or is absent from -- the
persisted map at `--db` (a small sqlite3 DB; sqlite3 is Python stdlib,
no new dependency). Prints a traced-only summary (this project does not
yet ship a separate "declared inputs" source to diff against, stated
honestly per io_trace.sh's own header -- §11.4.6, never a fabricated
comparison).

Host-safety (§12 / §11.4.225): `--sections-dir`'s real, current on-disk
population (device/rockchip/rk3588/tests/) is 1000+ scripts, the large
majority of which are ON-DEVICE tests (require a physical RK3588 board
attached over ADB) -- tracing one with no device connected can print a
usage error, block waiting on a device, or otherwise misbehave in ways
this tool cannot predict per-script. Every trace attempt is therefore run
under a bounded per-script TIMEOUT (`--per-script-timeout`, default 15s,
matching gate_audit.py's own `run_gate()` timeout convention) and its
outcome is recorded HONESTLY as one of PASS/error/timeout in the
persisted map -- a script that cannot be traced (timeout, nonzero exit,
unparseable output) is never silently skipped nor silently credited with
an empty/fabricated reads-writes set; it is recorded with its real
`trace_status` and the run continues to the next script (one hung/failing
script never aborts the whole build-map pass).

Usage: io_trace_build_map.py --sections-dir <dir> --db <sqlite-path>
                              --tool <path-to-io_trace.sh>
                              [--per-script-timeout SECONDS]

Exit codes: 0 the pass completed (regardless of individual per-script
trace/error/timeout outcomes -- those are reported, not fatal); 2 usage
error (missing --sections-dir/--db/--tool, or --sections-dir does not
exist); 4 BLIND (the sqlite DB could not be opened/created).
"""
import argparse
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import time

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_BLIND = 4

DEFAULT_TIMEOUT = 15


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def find_scripts(sections_dir):
    """Every *.sh under sections_dir, recursively, sorted for determinism."""
    found = []
    for dirpath, dirnames, filenames in os.walk(sections_dir):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if name.endswith(".sh"):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


def open_db(db_path):
    db_dir = os.path.dirname(os.path.abspath(db_path))
    if db_dir:
        os.makedirs(db_dir, exist_ok=True)
    try:
        conn = sqlite3.connect(db_path)
    except sqlite3.Error as exc:
        sys.stderr.write(f"io_trace_build_map: cannot open --db {db_path}: {exc}\n")
        sys.exit(EXIT_BLIND)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS io_map (
            script_path TEXT PRIMARY KEY,
            sha256 TEXT NOT NULL,
            trace_status TEXT NOT NULL,
            reads_json TEXT NOT NULL,
            writes_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.commit()
    return conn


def cached_hash(conn, script_path):
    row = conn.execute(
        "SELECT sha256 FROM io_map WHERE script_path = ?", (script_path,)
    ).fetchone()
    return row[0] if row else None


def upsert(conn, script_path, sha256, trace_status, reads, writes):
    conn.execute(
        """
        INSERT INTO io_map (script_path, sha256, trace_status, reads_json, writes_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(script_path) DO UPDATE SET
            sha256=excluded.sha256,
            trace_status=excluded.trace_status,
            reads_json=excluded.reads_json,
            writes_json=excluded.writes_json,
            updated_at=excluded.updated_at
        """,
        (
            script_path,
            sha256,
            trace_status,
            json.dumps(reads, sort_keys=True),
            json.dumps(writes, sort_keys=True),
            time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        ),
    )


def retrace(tool, script_path, timeout_s):
    """Runs `<tool> trace <script_path>` (gates/io_trace.sh's own `trace`
    subcommand -- the single source of truth for the strace invocation,
    never re-implemented here) with a bounded timeout. Returns
    (trace_status, reads, writes). trace_status is one of:
      "ok"      -- exit 0, stdout parsed as {"reads":[...],"writes":[...]}
      "error"   -- nonzero exit or unparseable stdout (real reason logged
                    to stderr, never silently swallowed)
      "timeout" -- exceeded --per-script-timeout
    A non-"ok" status ALWAYS carries empty reads/writes -- this module
    never fabricates a plausible-looking result for a script it could not
    genuinely trace (§11.4.6)."""
    try:
        proc = subprocess.run(
            ["sh", tool, "trace", script_path],
            capture_output=True, text=True, timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        return "timeout", [], []
    except Exception as exc:  # noqa: BLE001 - report, never crash the whole pass
        sys.stderr.write(f"io_trace_build_map: {script_path}: retrace raised: {exc}\n")
        return "error", [], []

    if proc.returncode != 0:
        return "error", [], []
    try:
        parsed = json.loads(proc.stdout.strip().splitlines()[-1]) if proc.stdout.strip() else None
    except (json.JSONDecodeError, IndexError):
        parsed = None
    if not isinstance(parsed, dict) or "reads" not in parsed or "writes" not in parsed:
        return "error", [], []
    return "ok", parsed.get("reads", []), parsed.get("writes", [])


def main(argv):
    parser = argparse.ArgumentParser(prog="io_trace_build_map.py")
    parser.add_argument("--sections-dir", required=True)
    parser.add_argument("--db", required=True)
    parser.add_argument("--tool", required=True)
    parser.add_argument("--per-script-timeout", type=float, default=DEFAULT_TIMEOUT)
    args = parser.parse_args(argv[1:])

    if not os.path.isdir(args.sections_dir):
        sys.stderr.write(f"io_trace_build_map: --sections-dir not found: {args.sections_dir}\n")
        return EXIT_USAGE
    if not os.path.isfile(args.tool):
        sys.stderr.write(f"io_trace_build_map: --tool not found: {args.tool}\n")
        return EXIT_USAGE

    conn = open_db(args.db)
    scripts = find_scripts(args.sections_dir)

    hits = 0
    retraced = 0
    ok_count = 0
    error_count = 0
    timeout_count = 0

    for script_path in scripts:
        try:
            digest = sha256_file(script_path)
        except OSError as exc:
            sys.stderr.write(f"io_trace_build_map: {script_path}: cannot read for hashing: {exc}\n")
            continue
        prior = cached_hash(conn, script_path)
        if prior == digest:
            hits += 1
            continue
        retraced += 1
        status, reads, writes = retrace(args.tool, script_path, args.per_script_timeout)
        upsert(conn, script_path, digest, status, reads, writes)
        if status == "ok":
            ok_count += 1
        elif status == "timeout":
            timeout_count += 1
        else:
            error_count += 1
        conn.commit()

    total = len(scripts)
    print(
        f"build-map: {total} script(s) under {args.sections_dir} -- "
        f"{hits} cache hit(s) (sha256 unchanged), {retraced} re-traced "
        f"({ok_count} ok, {error_count} error, {timeout_count} timeout). "
        f"Persisted to {args.db}."
    )
    print(
        "build-map: this project does not yet ship a separate 'declared "
        "inputs' source for gate scripts to diff against -- this is a "
        "traced-only summary, stated honestly rather than fabricating a "
        "declared-vs-traced comparison (§11.4.6)."
    )
    conn.close()
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
