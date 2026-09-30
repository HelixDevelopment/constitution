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

T085 Round 2 remediation (2026-09-30, B-R2-3, DEVICE-SAFETY CRITICAL): the
Round 1 implementation above ran EVERY `*.sh` script under
`--sections-dir` (default `device/rockchip/rk3588/tests/`, 1244 scripts
recursively, 475 of which contain `adb`/`rm -rf`/`settings put`/reboot/
flash/power-cycle commands per a live grep of the real tree) on the HOST
with NO refusal and NO opt-in -- a real risk to attached physical boards
(this project's own D1/D2 devices, per CLAUDE.md). Fixed by three
independent changes, each proven ONLY against a scratch/mock corpus this
module's own regression test constructs in an isolated tmp dir -- NEVER
against the real `device/rockchip/rk3588/tests/` tree, per §11.4.199 (the
Round 2 reviewer correctly refused to run this against real devices, and
so does this fix's own verification):

  1. `classify_device_mutating()` below refuses (SKIPs, never traces) any
     script whose content matches a documented device-mutating pattern
     set (adb invocations, reboot/flash/power-cycle commands, `settings
     put`, `upgrade_tool`/`rkdeveloptool`/`fastboot`, raw `dd`/`mkfs`, and
     an `rm -rf` target that is NOT clearly a locally-scoped scratch
     variable) UNLESS `--allow-device-scripts` is passed. A skipped
     script is recorded with trace_status "skipped-device" and an honest
     `skip_reason` -- never silently traced, never silently dropped
     without a record (§11.4.6).
  2. `retrace()` now launches the traced process in its OWN process group
     (`start_new_session=True`) and, on timeout, kills the WHOLE group via
     `os.killpg()` -- not just the direct `sh` child -- closing the
     grandchild-survives-the-timeout gap (e.g. a traced `sleep 30`
     backgrounded by the gate script kept running after the prior
     `subprocess.run(..., timeout=...)` call returned). Per the MANDATORY
     §11.4.263 process-group signal-safety guard, `_safe_killpg()` below
     validates `isinstance(pgid, int) and pgid > 1` before every
     `os.killpg()` call -- this module NEVER signals pgid <= 1.
  3. The hash-based cache hit check in `main()` now requires BOTH the
     sha256 to match AND the persisted `trace_status` to be "ok" before
     treating a script as a cache hit. A script whose last recorded
     status was "error" or "timeout" is ALWAYS re-attempted on the next
     run (even with an unchanged hash) -- it is never silently served as
     a permanent cache hit with stale/empty reads-writes (the pre-fix
     `cached_hash()` returned only the sha256, so a timeout/error row with
     an unchanged hash was indistinguishable from a genuine "ok" hit).

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
import re
import signal
import sqlite3
import subprocess
import sys
import time

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_BLIND = 4

DEFAULT_TIMEOUT = 15

# T085 Round 2 B-R2-3: device-mutating pattern set, derived from a live grep
# of the real device/rockchip/rk3588/tests/*.sh corpus (439/1066 top-level
# scripts match at least one of these classes as of 2026-09-30). Each
# pattern is a (name, compiled-regex) pair; a match on ANY pattern flags the
# script as device-mutating. This is intentionally CONSERVATIVE (broad,
# over-inclusive) per §11.4.201(4)'s safe-default-on-an-unresolvable-signal
# -- a benign script wrongly skipped is a minor annoyance (opt back in with
# --allow-device-scripts); a genuinely device-mutating script wrongly
# traced on a host with attached boards is a real-hardware safety incident.
_DEVICE_PATTERNS = [
    ("adb-invocation", re.compile(r"\badb\b")),
    ("reboot", re.compile(r"\breboot\b")),
    ("settings-put", re.compile(r"\bsettings\s+put\b")),
    ("flash-tooling", re.compile(r"\b(upgrade_tool|rkdeveloptool|fastboot)\b")),
    ("flash-script", re.compile(r"\bflash\.sh\b")),
    ("raw-block-io", re.compile(r"\bdd\s+(if|of)=|\bmkfs\.")),
    ("power-cycle", re.compile(r"\bpower[_-]?cycle\b", re.IGNORECASE)),
    ("factory-reset", re.compile(r"\bfactory[_-]?reset\b|\bwipe_data\b", re.IGNORECASE)),
    ("tuya-power-control", re.compile(r"\btuya_control\b|\btuya\.env\b")),
]

# An `rm -rf` target is EXEMPT from the device-mutating classification only
# when the deleted token itself looks like a locally-scoped scratch
# variable -- the naming convention actually used across the real corpus
# (TMP/TEMP/TMPDIR/TMPD/TMPROOT/SCRATCH/WORK/EVID*/_tmp*, case-insensitive,
# as a substring of the `rm -rf` argument token). Anything else (a bare
# path, `/`, or a variable with no scratch-like name) is treated as
# device/host-mutating and refused by default -- "rm -rf outside a scratch
# tree" from the Round 2 finding, operationalised against this corpus's own
# real naming discipline rather than an invented narrow list.
_SCRATCH_VAR_RE = re.compile(
    r"(TMP|TEMP|TMPDIR|TMPD|TMPROOT|SCRATCH|WORK|EVID|_tmp)", re.IGNORECASE
)
_RM_RF_RE = re.compile(r"rm\s+-rf\s+(?:--\s+)?(\S+)")


def classify_device_mutating(script_text):
    """Returns (is_device_mutating, reason_or_None). Pure text
    classification -- never executes the script. A single match is
    sufficient to flag; the FIRST matching reason is reported (a script may
    match more than one class, but one honest reason is enough to explain
    the skip)."""
    for name, pattern in _DEVICE_PATTERNS:
        if pattern.search(script_text):
            return True, name
    for m in _RM_RF_RE.finditer(script_text):
        target = m.group(1)
        if not _SCRATCH_VAR_RE.search(target):
            return True, f"rm-rf-outside-scratch-tree({target})"
    return False, None


def _safe_killpg(pgid, sig):
    """§11.4.263 MANDATORY guard: NEVER signal pgid <= 1 (killpg(1, sig) ==
    kill(-1, sig) == signal every process in the caller's session -- the
    forced-logout class of incident that anchor exists to prevent). Returns
    True if the signal was actually sent, False if refused or the process
    group was already gone."""
    if not isinstance(pgid, int) or pgid <= 1:
        sys.stderr.write(
            f"io_trace_build_map: REFUSING os.killpg(pgid={pgid!r}) -- "
            f"pgid must be an int > 1 (§11.4.263)\n"
        )
        return False
    try:
        os.killpg(pgid, sig)
        return True
    except ProcessLookupError:
        return False


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


def cached_row(conn, script_path):
    """Returns (sha256, trace_status) for the persisted row, or (None, None)
    if no row exists yet. T085 Round 2 B-R2-3: callers MUST check BOTH
    fields before treating a row as a valid cache hit -- a row's sha256 can
    match the current file content while its trace_status is "error" or
    "timeout" from a PRIOR failed attempt, and such a row must never be
    read as "already successfully traced, nothing to do" (that is the bug
    this fix closes: a timeout/error result was previously served as a
    cache hit forever, with empty reads/writes silently treated as real
    data)."""
    row = conn.execute(
        "SELECT sha256, trace_status FROM io_map WHERE script_path = ?",
        (script_path,),
    ).fetchone()
    return (row[0], row[1]) if row else (None, None)


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
    genuinely trace (§11.4.6).

    T085 Round 2 B-R2-3: the traced process runs in its OWN process group
    (start_new_session=True) so that, on timeout, the ENTIRE group -- not
    merely the direct `sh` child -- is killed via `os.killpg()` (guarded by
    §11.4.263's mandatory pgid>1 validation, `_safe_killpg()`). The
    pre-fix `subprocess.run(..., timeout=...)` killed only the direct
    child; a grandchild the traced gate script backgrounds (e.g. a
    `sleep 30 &`) survived the timeout and kept running after this
    function returned."""
    try:
        proc = subprocess.Popen(
            ["sh", tool, "trace", script_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True,
        )
    except OSError as exc:
        sys.stderr.write(f"io_trace_build_map: {script_path}: retrace raised: {exc}\n")
        return "error", [], []

    try:
        stdout, _stderr = proc.communicate(timeout=timeout_s)
    except subprocess.TimeoutExpired:
        _safe_killpg(proc.pid, signal.SIGKILL)
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            pass  # group refused to die within the reap grace window; report timeout regardless
        return "timeout", [], []
    except Exception as exc:  # noqa: BLE001 - report, never crash the whole pass
        sys.stderr.write(f"io_trace_build_map: {script_path}: retrace raised: {exc}\n")
        _safe_killpg(proc.pid, signal.SIGKILL)
        return "error", [], []

    if proc.returncode != 0:
        return "error", [], []
    try:
        parsed = json.loads(stdout.strip().splitlines()[-1]) if stdout.strip() else None
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
    parser.add_argument(
        "--allow-device-scripts", action="store_true", default=False,
        help=(
            "T085 Round 2 B-R2-3: explicit opt-in required to trace a "
            "script matching the device-mutating pattern set (adb, "
            "reboot, settings put, flash/power-cycle tooling, rm -rf "
            "outside a scratch tree). Absent this flag such scripts are "
            "SKIPPED with an honest reason recorded, never traced."
        ),
    )
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
    skipped_device = 0

    for script_path in scripts:
        try:
            digest = sha256_file(script_path)
        except OSError as exc:
            sys.stderr.write(f"io_trace_build_map: {script_path}: cannot read for hashing: {exc}\n")
            continue

        # T085 Round 2 B-R2-3: classify BEFORE any cache/retrace decision,
        # from the CURRENT file content, every run -- a script that
        # becomes device-mutating after an edit is caught immediately, and
        # one that stops matching is no longer skipped, with no stale
        # classification cached anywhere.
        if not args.allow_device_scripts:
            try:
                with open(script_path, "r", errors="replace") as fh:
                    text = fh.read()
            except OSError as exc:
                sys.stderr.write(f"io_trace_build_map: {script_path}: cannot read for classification: {exc}\n")
                text = ""
            is_device, reason = classify_device_mutating(text)
            if is_device:
                skipped_device += 1
                upsert(conn, script_path, digest, "skipped-device", [], [])
                conn.commit()
                sys.stderr.write(
                    f"io_trace_build_map: SKIPPING {script_path} -- device-mutating "
                    f"pattern matched ({reason}); re-run with --allow-device-scripts "
                    f"to trace it (never done automatically -- §12/§11.4.225 "
                    f"host-safety, §11.4.263)\n"
                )
                continue

        # T085 Round 2 B-R2-3: a cache HIT requires the sha256 to match AND
        # the persisted trace_status to be "ok" -- a prior "error"/"timeout"
        # row is ALWAYS re-attempted, never served as a stale permanent hit.
        prior_sha, prior_status = cached_row(conn, script_path)
        if prior_sha == digest and prior_status == "ok":
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
        f"{hits} cache hit(s) (sha256 unchanged AND trace_status=ok), "
        f"{retraced} re-traced ({ok_count} ok, {error_count} error, "
        f"{timeout_count} timeout), {skipped_device} skipped as "
        f"device-mutating (re-run with --allow-device-scripts to trace "
        f"them). Persisted to {args.db}."
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
