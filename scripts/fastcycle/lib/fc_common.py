#!/usr/bin/env python3
"""fc_common.py - shared conventions for spec-004 fastcycle tools (contracts/common-conventions.md C-001..C-004).

Purpose: canonical JSON emit, body_hash (excluding run_meta), control needles, determinism check, --as-of guard.
Also exports (T140 Round 6, importable helpers, no CLI subcommand of their own): `strict_loads(text)` -- parses
JSON rejecting non-finite constants (NaN/Infinity/-Infinity) and duplicate keys, the ONE shared PARSE-TIME
point every sibling tool reads caller-controlled JSON through (section 11.4.250 -- rejecting a non-finite
constant here, once, closes every downstream write-site crash it would otherwise cause); `SAFE_EXCEPTIONS` --
a shared (TypeError, ValueError, OSError, OverflowError) tuple every sibling tool ORs onto its own narrower
except-clauses instead of independently guessing one; `is_strict_nonneg_int(v)` -- a shared "is this a genuine,
non-negative JSON integer" predicate (rejects bool, rejects negative) for every "is this a valid count/id"
check.
Usage:   fc_common.py emit --schema S --body-json J [--run-meta-json J] --out P [--code 0|1|3|4]
         fc_common.py body-hash --doc P [--verify]
         fc_common.py needle --present L --fabricated L --haystack L
         fc_common.py determinism-check -- CMD...   (CMD writes its doc to $FC_OUT)
         fc_common.py require-as-of [--windowed] [--as-of YYYY-MM-DD]
Exit:    0 ok, 1 finding, 2 usage/config/unparseable input, 3 self-test failed (no result file), 4 BLIND.
         Exit 4 has two producers, told apart by the file: `emit --code 4` writes a doc flagged "BLIND":true (C-001 row 4);
         an uncaught internal error also exits 4 (no honest verdict possible; C-001 has no other row for a tool fault -
         never 1, reserved for findings, never a code outside the table) but writes NO file.
         Result files honour the caller's umask (mode 0666 & ~umask). --schema must match <tool>/v<N>.
         Non-finite numbers (NaN, Infinity, 1e999) are refused everywhere (exit 2).
         determinism-check: 0 stable, 1 body_hash/rc mismatch (diff printed), 3 command self-test failed, 4 no honest verdict.
         Each command run is bounded (FC_DETERMINISM_TIMEOUT_S, default 60) and its whole process group reaped: timeout -> 4.
         Legitimate command codes per C-001: 0 and 1 (each with a JSON-object doc) are verdicts, 3 is a self-test failure;
         EVERY other code (2 usage/config, 4 BLIND, 5, 70, 128+, signal death), a missing command, or a missing/non-JSON
         doc is not a verdict -> 4, even if the two runs agree.
         needle: numbers compare by value (1 == 1.0), a bool never equals a number, a str never equals a number (C-004).
         run_meta (emit) must be a JSON object; an empty or non-object value is refused (exit 2), never read as absent.
         body-hash --verify: 0 stored body_hash equals the recomputed one (hash printed), 1 mismatch (both printed), 2 bad input,
         unencodable doc, no stored string body_hash, or a stored body_hash that is not exactly
         64 lowercase hex chars (upper/mixed case, padded, short, long, non-hex are MALFORMED = 2, never a mismatch 1). run_meta never affects the hash. Without --verify: prints the hash.
Side-effects: emit writes --out (except code 3). Python stdlib only.
"""
import argparse
import datetime
import errno
import hashlib
import json
import difflib
import os
import re
import shlex
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import uuid

# C-002: body_hash covers the canonical doc EXCLUDING run_meta (and body_hash itself, which it fills in).
# schema and BLIND ARE hashed. Reserved keys may not appear in a caller-supplied body.
EXCLUDED = ("run_meta", "body_hash")
HASH_RE = re.compile(r"[0-9a-f]{64}")  # C-002: a valid body_hash is exactly 64 lowercase hex chars
RESERVED = ("schema", "run_meta", "body_hash", "BLIND")
EXIT_INTERNAL = 4  # C-001: BLIND (no honest verdict); see header
# Sentinel _run_bounded returns instead of an int (real rc) or None (timed out) when a command's real exit
# status is genuinely unobtainable: SIGCHLD was inherited as SIG_IGN in THIS process so the kernel
# auto-reaped/discarded the leader's status the instant it exited, before it could ever be observed (see
# _run_bounded / _leader_reap_honest). Deliberately an opaque object -- never an int, never None -- so
# `rc is NO_HONEST_VERDICT` can never accidentally match a real return code or collide with the timeout case.
NO_HONEST_VERDICT = object()
# determinism-check bounds each command run (C-001: "could not look" is exit 4, never a silent stall).
# operator-tunable default, no measured basis: the contract states no bound. Override: FC_DETERMINISM_TIMEOUT_S
# (positive integer, 1..999999 seconds; anything else is refused, exit 2). SIGTERM first, SIGKILL after the grace.
DETERMINISM_TIMEOUT_DEFAULT_S = 60
DETERMINISM_KILL_AFTER_S = 2
TIMEOUT_RE = re.compile(r"[0-9]{1,6}")
SCHEMA_RE = re.compile(r"[A-Za-z0-9._-]+/v[0-9]+")

# T140 Round 6 review (section 11.4.250 heuristic-tower/primitive-defect): the
# realistic catch-all surface every fastcycle orchestration tool needs when
# defensively wrapping code that touches caller-controlled JSON shapes,
# filesystem paths, and numeric fields it did not itself validate -- built
# from what Round 6 review actually found crashing UNCAUGHT across THREE
# sibling tools (handoff.py, limit_class.py, custody_sweep.py) in ONE round,
# never guessed in advance: TypeError/ValueError (a field has the wrong JSON
# shape/value -- the pre-existing narrow catch every one of Rounds 1-5 already
# used), OSError (a read/write touches an unreadable/unwritable/missing path,
# e.g. a dangling symlink under a re-hashed dependency tree, or an unwritable
# --out directory -- section 11.4.201(11) artifact-usability), OverflowError
# (a caller-supplied integer too large to convert to float, e.g. Python
# int -> float inside a math.ceil() division). A SINGLE SHARED tuple, not
# three independently-guessed per-file catch-lists (section 11.4.227
# reuse-not-reinvention; section 11.4.250 -- three files each narrowing their
# own except-clause by trial and error, one crash site at a time across
# rounds, is exactly the compensating-heuristic-tower pattern that anchor
# forbids). Deliberately NEVER includes BaseException/Exception/
# KeyboardInterrupt/SystemExit, nor tool-specific exceptions a caller already
# handles with its own distinct message (e.g. KeyError for "field genuinely
# missing" vs TypeError for "field present with the wrong type") -- those stay
# each tool's own, narrower, more diagnosable except-clause; SAFE_EXCEPTIONS
# is the MINIMUM shared floor every tool ORs its own exceptions onto, not a
# replacement for a tool's own more specific handling. An internal error
# outside this set stays uncaught by design (no honest verdict is ever
# silently swallowed into a fabricated finding, section 11.4.6).
SAFE_EXCEPTIONS = (TypeError, ValueError, OSError, OverflowError)


def safe_killpg(pgid, sig):
    """Section 11.4.263 MANDATORY guard: NEVER signal pgid <= 1
    (killpg(1, sig) == kill(-1, sig) == signal every process in the
    caller's own session -- the forced-logout class of incident that
    anchor exists to prevent). Returns True if the signal was actually
    sent, False if refused or the process group was already gone.

    T085 Round 3 R3-I1: the ONE shared primitive every "kill a traced/
    gated subprocess's WHOLE process group" call site in this tool
    family now uses -- originally authored in
    gates/lib/io_trace_build_map.py (T085 Round 2 B-R2-3), promoted here
    (section 11.4.227 reuse-not-reinvention) when
    gates/batch_bisect.py's run_gate_on_tree() needed the IDENTICAL
    guard for the SAME class of fix (a gate script that backgrounds a
    detached grandchild must never be allowed to leave it running after
    the gate's own run is considered complete, on EITHER a timeout OR a
    normal return). io_trace_build_map.py keeps its own
    `_safe_killpg` name as a thin alias to this function (so its
    existing §11.4.263 unit test, which calls `mod._safe_killpg(...)`
    directly by that name, is unaffected) -- this is the single
    underlying implementation both now share."""
    if not isinstance(pgid, int) or pgid <= 1:
        sys.stderr.write(
            "fc_common: REFUSING os.killpg(pgid=%r) -- pgid must be an "
            "int > 1 (section 11.4.263)\n" % (pgid,)
        )
        return False
    try:
        os.killpg(pgid, sig)
        return True
    except ProcessLookupError:
        return False


# ---------------------------------------------------------------------------
# T085 Round 5: namespace-based device sandbox (section 11.4.227 shared
# primitive -- the FIRST of the Round 4 reviewer's four "build these as
# shared primitives, not more patches" recommendations). Closes R4-B1
# (BLOCKING): the PATH/env-only sandbox io_trace_build_map.py built at
# T085 Round 3 (R3-B1) was independently reproduced, by the Round 4
# reviewer, as bypassable TWO ways against the committed code:
#   (1) an absolute-path invocation built from a NON-"adb"-named
#       environment variable (e.g. "$ANDROID_HOME/platform-tools/a""db",
#       the command-name text split so neither "adb" nor the full
#       command ever appears as a contiguous substring anywhere the
#       classifier or the env-key-contains-"adb" DENYLIST could see);
#   (2) a raw TCP socket connecting DIRECTLY to the real adb server's
#       127.0.0.1:5037, with no adb binary involved at all -- a pure
#       network action no PATH/env manipulation can ever observe or
#       stop.
# Neither bypass is closed by restricting WHAT NAME can be found
# (PATH/env); both are closed by making the underlying ACTION itself
# impossible: a fresh, UNPRIVILEGED Linux user+network+mount namespace
# (`unshare --map-root-user --net --mount`, empirically confirmed
# working WITHOUT root on this host -- CONFIG_USER_NS unprivileged user
# namespaces) gives the sandboxed process its own loopback interface
# (DOWN by default, no routes configured) -- connecting to
# 127.0.0.1:ANY-PORT from inside it fails with ENETUNREACH regardless of
# which binary, real absolute-path or otherwise, attempts it -- plus its
# own private mount namespace with /dev/bus/usb (when present on this
# host) bind-mounted over by an empty directory, closing direct-USB
# device-node access for a tool that bypasses the TCP adb-server
# protocol entirely (fastboot's USB transport). This is LAYERED ON TOP
# OF, never instead of, the pre-existing PATH-stub (closes bare command
# names) and the new ALLOWLISTED environment (closes the specific
# ANDROID_HOME-style absolute-path construction even before network
# isolation would) -- three independent layers, each closing a DIFFERENT
# bypass class, matching this project's own documented "sandbox the
# ACTION, not merely the lookup" principle (io_trace_build_map.py's
# T085 Round 3 R3-B1 remediation note, which this module's own
# device_sandbox_namespace_available() self-test below extends from "a
# fake binary in the way" to "the underlying syscall path is actually
# severed").
# ---------------------------------------------------------------------------

DEVICE_REACHING_BINARIES = (
    "adb", "fastboot", "upgrade_tool", "rkdeveloptool", "uhubctl",
    "tuya_control", "tuya-cli",
)

_DEVICE_SANDBOX_STUB_TEMPLATE = (
    "#!/bin/sh\n"
    "echo \"device-sandbox: BLOCKED invocation of '%s' (args: $*) -- \"\\\n"
    "\"device-mutating binaries are never reachable inside this sandbox \"\\\n"
    "\"(section 11.4.252/11.4.263)\" >&2\n"
    "exit 97\n"
)


def build_device_sandbox_bin_dir(sandbox_dir, binaries=DEVICE_REACHING_BINARIES):
    """Populates `sandbox_dir` with a stub executable for every name in
    `binaries`. Each stub writes an honest refusal message to stderr and
    exits 97 -- it never execs, never forwards args, and never performs
    any device action of any kind. Idempotent. Returns sandbox_dir.

    Shared (section 11.4.227) promotion of the per-tool stub-writer
    originally authored, under a leading-underscore private name, in
    gates/lib/io_trace_build_map.py (T085 Round 3 R3-B1) -- this is now
    the ONE implementation every "deny PATH access to a device-reaching
    binary name" call site in this tool family uses."""
    os.makedirs(sandbox_dir, exist_ok=True)
    for name in binaries:
        stub_path = os.path.join(sandbox_dir, name)
        with open(stub_path, "w") as fh:
            fh.write(_DEVICE_SANDBOX_STUB_TEMPLATE % name)
        os.chmod(stub_path, 0o755)
    return sandbox_dir


# T085 Round 5 R4-B1: an ALLOWLIST, never a denylist -- the pre-fix
# io_trace_build_map.py `_sandboxed_env()` started from a COPY of the
# FULL inherited environment and subtracted only names CONTAINING "adb";
# ANDROID_HOME contains no such substring and therefore survived
# untouched, letting "$ANDROID_HOME/platform-tools/a""db" resolve to the
# REAL binary. This list is deliberately small and the env below is
# built FROM SCRATCH every call -- any variable not named here
# (ANDROID_HOME, ANDROID_SDK_ROOT, ANDROID_ADB_SERVER_PORT, or anything
# else the calling shell happens to have set) is simply never present in
# the sandboxed child's environment at all, regardless of its name.
DEVICE_SANDBOX_ENV_ALLOWLIST = (
    "HOME", "LANG", "LANGUAGE", "LC_ALL", "LC_CTYPE", "TMPDIR", "TERM",
    "USER", "LOGNAME", "SHELL", "PWD",
)
# Standard system dirs so coreutils/util-linux (mount, mktemp, cat, sh,
# ...) resolve normally inside the sandbox; the sandbox's own stub dir
# is ALWAYS prepended ahead of these by device_sandbox_env() below, so a
# bare `adb` (or any other DEVICE_REACHING_BINARIES name) resolves to
# the stub FIRST, never a real system-installed one.
_DEVICE_SANDBOX_SAFE_PATH = "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"


def device_sandbox_env(sandbox_bin_dir, allowlist=DEVICE_SANDBOX_ENV_ALLOWLIST, base_env=None):
    """Returns a FRESH env dict (never a mutation of, nor built by
    subtracting entries from, the caller's own environment) containing
    ONLY the `allowlist` names that are present in `base_env` (default:
    os.environ), plus PATH forced to `sandbox_bin_dir` + the standard
    system dirs, plus ADB forced to the stub's own absolute path (kept
    as additional defense-in-depth for this corpus's
    `ADB="${ADB:-adb}"` idiom, even though the allowlist alone already
    denies ANDROID_HOME and every other non-allowlisted variable)."""
    src = os.environ if base_env is None else base_env
    env = {k: src[k] for k in allowlist if k in src}
    env["PATH"] = sandbox_bin_dir + os.pathsep + _DEVICE_SANDBOX_SAFE_PATH
    env["ADB"] = os.path.join(sandbox_bin_dir, "adb")
    return env


DEVICE_SANDBOX_HIDE_PATHS = ("/dev/bus/usb",)


class DeviceSandboxUnavailable(RuntimeError):
    """Raised by wrap_device_sandbox_argv() when the namespace-isolation
    precondition this sandbox depends on could not be PROVEN on this
    host (unshare missing, unprivileged user namespaces disabled, or the
    live connect-is-refused self-test below did not hold). Callers MUST
    treat this as a fail-closed signal -- refuse to run the command at
    all in default (sandboxed) mode, NEVER silently fall back to a
    weaker PATH/env-only sandbox without saying so (section
    11.4.201(4): the conservative-safe default on an unresolvable safety
    signal)."""


_device_sandbox_available_cache = None  # None = not probed yet this process


def device_sandbox_namespace_available(force_probe=False):
    """Returns True only if a REAL, LIVE self-test confirms this host's
    unprivileged user+network namespace isolation genuinely cuts off
    loopback TCP connectivity -- NEVER inferred from `unshare`'s mere
    presence on PATH, nor from a bare `unshare --net true` rc==0 (which
    proves only that namespace CREATION succeeded, not that
    connectivity is genuinely severed -- section 11.4.201 forbids
    trusting a proxy signal for a safety-critical condition, and a bare
    exit-code check here could not even distinguish "the probe ran and
    confirmed isolation" from "unshare itself failed before the probe
    ever ran", since util-linux tools commonly share the same nonzero
    exit code for unrelated failures).

    The self-test: bind a REAL TCP listener on an ephemeral loopback
    port in THIS process, then spawn `unshare --map-root-user --net
    --mount` wrapping a second process that attempts to connect to that
    EXACT port and prints an unambiguous, prefixed marker string
    ("DEVICE_SANDBOX_PROBE:BLOCKED" or "...CONNECTED") to its own
    stdout -- never relying on exit code alone. Isolation is confirmed
    held ONLY when that exact "BLOCKED" marker is observed; any other
    outcome (unshare missing/failed, the probe crashed, a timeout, the
    "CONNECTED" marker, unparseable output) is honestly reported as
    unavailable. Cached per-process (module-level) after the first call
    unless `force_probe=True`.

    Test-only escape hatch: `FC_DEVICE_SANDBOX_TEST_FORCE_UNAVAILABLE=1`
    forces this function to return False WITHOUT ever actually probing
    the host, letting a test exercise main()'s fail-closed refusal path
    deterministically (disabling unprivileged user namespaces for real
    would require a host-wide, root-level sysctl change this project's
    own §12 host-safety mandate forbids doing as a side effect of a
    single test run). This is checked BEFORE the cache (so it always
    takes effect the instant it is set) and is never read by any
    production code path -- only this function's own regression tests
    set it."""
    if os.environ.get("FC_DEVICE_SANDBOX_TEST_FORCE_UNAVAILABLE") == "1":
        return False
    global _device_sandbox_available_cache
    if _device_sandbox_available_cache is not None and not force_probe:
        return _device_sandbox_available_cache

    if shutil.which("unshare") is None:
        _device_sandbox_available_cache = False
        return False

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    result = False
    try:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        probe_py = (
            "import socket,sys\n"
            "s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)\n"
            "s.settimeout(2)\n"
            "try:\n"
            "    s.connect(('127.0.0.1', %d))\n"
            "    print('DEVICE_SANDBOX_PROBE:CONNECTED')\n"
            "except OSError as e:\n"
            "    print('DEVICE_SANDBOX_PROBE:BLOCKED:' + str(e))\n"
        ) % port
        try:
            probe = subprocess.run(
                ["unshare", "--map-root-user", "--net", "--mount",
                 "--", sys.executable, "-c", probe_py],
                timeout=10, env={"PATH": _DEVICE_SANDBOX_SAFE_PATH},
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
            )
            result = "DEVICE_SANDBOX_PROBE:BLOCKED:" in (probe.stdout or "")
        except (OSError, subprocess.TimeoutExpired):
            result = False
    finally:
        listener.close()

    _device_sandbox_available_cache = result
    return result


def wrap_device_sandbox_argv(cmd, hide_paths=DEVICE_SANDBOX_HIDE_PATHS):
    """Returns a NEW argv list that, when subprocess.Popen'd, runs `cmd`
    (a list) inside a fresh unprivileged user+network+mount namespace,
    with every EXISTING path in `hide_paths` bind-mounted over by an
    empty, freshly-created temp directory BEFORE `cmd` itself starts (a
    path that does not exist on this host is silently skipped, never an
    error -- not every host has /dev/bus/usb; a bind-mount failure for
    an existing path is also never fatal to the whole sandbox --
    `|| true` -- since network isolation, this primitive's PRIMARY
    guarantee, does not depend on it).

    Raises DeviceSandboxUnavailable if device_sandbox_namespace_available()
    returns False -- callers MUST NOT catch this and silently degrade to
    a weaker sandbox; see that function's and DeviceSandboxUnavailable's
    own docstrings.

    Deliberately changes ONLY how `cmd` is isolated -- the returned argv
    is still a plain list the caller Popen()s exactly as it would `cmd`
    itself (an existing caller's own start_new_session=True / env= /
    timeout / process-group-kill handling, e.g.
    io_trace_build_map.py's retrace(), needs NO changes of its own:
    `unshare`'s own pid becomes the group leader, and `_safe_killpg()`
    already kills the WHOLE group, including every process `unshare`
    itself went on to exec/fork)."""
    if not device_sandbox_namespace_available():
        raise DeviceSandboxUnavailable(
            "device namespace sandbox unavailable on this host (unshare "
            "missing, unprivileged user namespaces disabled, or the "
            "live loopback-isolation self-test did not confirm "
            "connectivity is severed) -- refusing to run inside a "
            "sandbox that cannot be proven to isolate network/mount "
            "access; see fc_common.device_sandbox_namespace_available()"
        )
    hide_sh_parts = [
        'if [ -e %s ]; then d=$(mktemp -d); mount --bind "$d" %s 2>/dev/null || true; fi'
        % (shlex.quote(p), shlex.quote(p))
        for p in hide_paths
    ]
    inner_sh = "; ".join(hide_sh_parts + ['exec "$@"'])
    return [
        "unshare", "--map-root-user", "--net", "--mount", "--",
        "sh", "-c", inner_sh, "device-sandbox-inner",
    ] + list(cmd)


# ---------------------------------------------------------------------------
# T085 Round 5: ONE shared, cgroup-reaping gate runner (section 11.4.227
# shared primitive -- the SECOND of the Round 4 reviewer's four "build
# these as shared primitives, not more patches" recommendations). Closes
# R4-I2 (IMPORTANT): "the orphaned-child-process fix was applied only at
# the two places Round 3 named" (io_trace_build_map.py's retrace(),
# batch_bisect.py's run_gate_on_tree()) -- seven OTHER gate-execution
# sites (gate_audit.run_gate, gate_runner_shard run-shard,
# catchset_compare x2, flake_ledger, gate_runner_order, backstop_run)
# each independently ran a bare `subprocess.run(cmd, timeout=...)` with
# NO process isolation at all, so even a direct, non-timeout-path child
# process could leave a backgrounded grandchild running past the gate's
# own return. WORSE, the review also found a gap at BOTH of the
# "already-fixed" sites: a grandchild that calls `setsid()` escapes a
# process-GROUP-only kill entirely (setsid() creates a brand-new
# session and process group, detaching the grandchild from the one
# start_new_session=True + killpg() can still reach) -- reproduced live
# in batch_bisect ("wrote its marker 2.5s after the call had already
# returned PASS").
#
# Fixed with a Linux cgroup v2 "scope" per gate invocation: unlike
# process-GROUP membership, cgroup membership is INHERITED by every
# fork() and is UNCHANGED by setsid()/exec() -- a process can leave its
# process group via setsid() but can never leave its cgroup except by
# an explicit, privileged move. Writing "1" to a cgroup's `cgroup.kill`
# file (Linux 5.14+) therefore kills EVERY process still a member of it
# -- confirmed, empirically, to close EXACTLY this gap (a setsid()'d
# grandchild backgrounded inside a cgroup-scoped gate was killed before
# its own 3s sleep completed; the identical script OUTSIDE a cgroup, or
# cleaned up only via killpg(), survives). This is the PRIMARY
# mechanism; the pre-existing start_new_session=True + killpg() cleanup
# is KEPT as a secondary, defense-in-depth layer (closes the ordinary,
# non-setsid case even faster, and remains the FULL mechanism on a host
# without cgroup v2 delegation -- see the honestly-reported `mechanism`
# field below, never silently claimed stronger than it is).
# ---------------------------------------------------------------------------

_CGROUP_KILL_FILENAME = "cgroup.kill"
_CGROUP_PROCS_FILENAME = "cgroup.procs"


def _own_cgroup_v2_base():
    """Returns the absolute path of THIS process's own cgroup v2
    directory under the unified hierarchy (/sys/fs/cgroup/<path from
    /proc/self/cgroup>), or None if cgroup v2 is not mounted, this
    process is on the v1 (multi-hierarchy) layout instead, or its own
    cgroup line could not be parsed. Read FRESH every call, never
    cached -- a long-lived process's own cgroup CAN change (e.g. an
    external supervisor moves it), and every caller of this function
    must always target the CURRENT, real location."""
    try:
        with open("/proc/self/cgroup", "r", encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
    # cgroup v2 unified hierarchy: exactly one line, "0::<path>" (empty
    # middle field). A v1/hybrid host reports multiple numbered lines
    # with non-empty controller-name middle fields instead -- this
    # function deliberately returns None for that layout rather than
    # guessing at a v1 equivalent (cgroup.kill is a v2-only interface
    # file; this primitive does not attempt a v1 fallback).
    for line in lines:
        parts = line.split(":", 2)
        if len(parts) == 3 and parts[0] == "0" and parts[1] == "":
            return os.path.normpath("/sys/fs/cgroup" + parts[2])
    return None


_cgroup_runner_available_cache = None


def cgroup_runner_available(force_probe=False):
    """Returns True only if a REAL, LIVE self-test confirms this
    process can create a writable cgroup v2 child directory under its
    own delegated subtree, move a genuine child process into it via
    `cgroup.procs`, and actually kill that process via `cgroup.kill` --
    NEVER inferred from the mere presence of a cgroup v2 mount or a
    writable-looking parent directory (section 11.4.201: a safety-
    relevant capability is measured, never assumed from a proxy
    signal). Cached per-process unless `force_probe=True`.

    Test-only escape hatch:
    FC_CGROUP_RUNNER_TEST_FORCE_UNAVAILABLE=1 forces this function to
    return False WITHOUT ever probing, letting a test exercise
    run_gate_reaped()'s process-group-only fallback path
    deterministically (mirrors device_sandbox_namespace_available()'s
    identical, already-reviewed pattern) -- never read by any
    production code path."""
    if os.environ.get("FC_CGROUP_RUNNER_TEST_FORCE_UNAVAILABLE") == "1":
        return False
    global _cgroup_runner_available_cache
    if _cgroup_runner_available_cache is not None and not force_probe:
        return _cgroup_runner_available_cache

    base = _own_cgroup_v2_base()
    if base is None or not os.path.isdir(base):
        _cgroup_runner_available_cache = False
        return False

    probe_dir = os.path.join(base, "fc-cgroup-probe-%d-%s" % (os.getpid(), uuid.uuid4().hex[:8]))
    try:
        os.mkdir(probe_dir)
    except OSError:
        _cgroup_runner_available_cache = False
        return False

    result = False
    try:
        kill_file = os.path.join(probe_dir, _CGROUP_KILL_FILENAME)
        procs_file = os.path.join(probe_dir, _CGROUP_PROCS_FILENAME)
        if os.access(kill_file, os.W_OK) and os.access(procs_file, os.W_OK):
            marker_dir = tempfile.mkdtemp(prefix="fc-cgroup-probe-marker-")
            try:
                marker = os.path.join(marker_dir, "survived")
                proc = subprocess.Popen([
                    "sh", "-c",
                    "echo $$ > %s; sleep 5; echo survived > %s"
                    % (shlex.quote(procs_file), shlex.quote(marker)),
                ])
                deadline = time.monotonic() + 3
                present = False
                while time.monotonic() < deadline:
                    try:
                        with open(procs_file, encoding="utf-8") as fh:
                            if str(proc.pid) in fh.read().split():
                                present = True
                                break
                    except OSError:
                        pass
                    time.sleep(0.05)
                if present:
                    with open(kill_file, "w", encoding="utf-8") as fh:
                        fh.write("1")
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=5)
                    time.sleep(0.2)
                    result = not os.path.exists(marker)
                else:
                    proc.kill()
                    proc.wait(timeout=5)
            finally:
                shutil.rmtree(marker_dir, ignore_errors=True)
    finally:
        try:
            os.rmdir(probe_dir)
        except OSError:
            pass

    _cgroup_runner_available_cache = result
    return result


class GateRunResult:
    """Return shape of run_gate_reaped() below. `mechanism` is ALWAYS
    the mechanism that GENUINELY ran for this call -- "cgroup" or
    "process-group" -- never claimed stronger than what actually
    applied (section 11.4.6)."""
    __slots__ = ("returncode", "stdout", "stderr", "timed_out", "error", "mechanism")

    def __init__(self, returncode, stdout, stderr, timed_out, error, mechanism):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr
        self.timed_out = timed_out
        self.error = error
        self.mechanism = mechanism


def run_gate_reaped(cmd, timeout_s, env=None, cwd=None, text=True):
    """THE shared gate-execution primitive (section 11.4.227 -- the
    Round 4 reviewer's explicit "ONE shared gate runner ... used at
    EVERY gate-execution site" recommendation). Runs `cmd` (a list) with
    a bounded timeout and reaps EVERY descendant process on return --
    normal OR timeout -- including a setsid()-detached grandchild a
    process-group-only kill cannot reach (see this module's own section
    header above for the full R4-I2 rationale).

    Returns a GateRunResult:
      - normal completion: returncode=int, stdout/stderr captured,
        timed_out=False, error=None.
      - timeout: returncode=None, stdout/stderr empty, timed_out=True,
        error=None.
      - could not even launch (OSError): returncode=None, stdout/stderr
        empty, timed_out=False, error=the exception.
    `.mechanism` ("cgroup" or "process-group") reports which reaping
    mechanism genuinely ran for THIS call -- see cgroup_runner_available()
    for how that is decided, honestly, never assumed.

    Honest boundary (section 11.4.6): cgroup availability is verified
    ONCE per process (cgroup_runner_available(), cached) via its own
    real self-test, not re-verified on every individual call -- a
    per-call re-verification would add real latency to every gate
    invocation across a suite that can run hundreds of them for a
    guarantee cgroup_runner_available() already measured for the whole
    process's lifetime on this host."""
    empty = "" if text else b""
    use_cgroup = cgroup_runner_available()
    cgroup_path = None
    launch_cmd = list(cmd)

    if use_cgroup:
        base = _own_cgroup_v2_base()
        candidate = os.path.join(base, "fc-gate-%d-%s" % (os.getpid(), uuid.uuid4().hex[:8]))
        try:
            os.mkdir(candidate)
        except OSError:
            # TOCTOU loss of the precondition between the process-wide
            # self-test and this specific call -- fall back honestly
            # rather than raise; `mechanism` below reports the truth.
            use_cgroup = False
        else:
            cgroup_path = candidate
            procs_file = os.path.join(cgroup_path, _CGROUP_PROCS_FILENAME)
            launch_cmd = [
                "sh", "-c",
                'echo $$ > %s 2>/dev/null; exec "$@"' % shlex.quote(procs_file),
                "gate-cgroup-inner",
            ] + list(cmd)

    mechanism = "cgroup" if use_cgroup else "process-group"

    try:
        proc = subprocess.Popen(
            launch_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=text, start_new_session=True, env=env, cwd=cwd,
        )
    except OSError as exc:
        if cgroup_path is not None:
            try:
                os.rmdir(cgroup_path)
            except OSError:
                pass
        return GateRunResult(None, empty, empty, False, exc, mechanism)

    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=timeout_s)
    except subprocess.TimeoutExpired:
        timed_out = True
        stdout, stderr = empty, empty
        safe_killpg(proc.pid, signal.SIGKILL)
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            pass
    else:
        # Kill the WHOLE process group even on this NORMAL return path
        # (T085 Round 3 R3-I1 pattern) -- closes the ordinary,
        # non-setsid case; a group that is already empty simply raises
        # ProcessLookupError, swallowed inside safe_killpg().
        safe_killpg(proc.pid, signal.SIGKILL)

    if cgroup_path is not None:
        # The PRIMARY cleanup: kills every member regardless of
        # session/process-group, including a setsid()-detached
        # grandchild the killpg() calls above cannot reach.
        try:
            with open(os.path.join(cgroup_path, _CGROUP_KILL_FILENAME), "w", encoding="utf-8") as fh:
                fh.write("1")
        except OSError:
            pass
        # Best-effort drain before rmdir -- a cgroup that still has a
        # member (a process resisting SIGKILL, vanishingly rare) simply
        # fails rmdir (EBUSY) and is left for later reclaim; never
        # treated as fatal to this function's own result.
        for _ in range(20):
            try:
                with open(os.path.join(cgroup_path, _CGROUP_PROCS_FILENAME), encoding="utf-8") as fh:
                    if not fh.read().strip():
                        break
            except OSError:
                break
            time.sleep(0.05)
        try:
            os.rmdir(cgroup_path)
        except OSError:
            pass

    return GateRunResult(
        None if timed_out else proc.returncode,
        stdout, stderr, timed_out, None, mechanism,
    )


def is_strict_nonneg_int(v):
    """True iff `v` is a genuine, non-negative JSON integer.

    REJECTS a Python `bool` (bool is a subclass of int in Python, so a bare
    `isinstance(v, int)` check wrongly accepts `True`/`False` as valid
    counts/ids -- T140 Round 6 review finding R6-I2,
    orchestration/limit_class.py's own `live_agents` field: a fixture with
    `live_agents: true` silently passed the pre-existing "must be a JSON
    integer" check and was then treated as `1` by `range(True)`). REJECTS a
    negative value (a negative count/id is never valid anywhere this helper
    is used). Deliberately narrower than "any non-negative number" -- a JSON
    float, even one with an integral value (e.g. `3.0`), is REJECTED too:
    every documented field this helper guards is a JSON *integer*, not a
    JSON number in general (a caller passing `3.0` for a field the schema
    calls out as `int` is a shape violation, not a value this tool should
    silently coerce).

    Shared (section 11.4.227 reuse-not-reinvention; section 11.4.250
    heuristic-tower) so every fastcycle tool that needs "is this a valid
    count/id" answers it IDENTICALLY, instead of each guessing its own
    `isinstance()` check independently and re-discovering the bool-is-a-
    subclass-of-int footgun one file at a time."""
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def body_hash_of(doc):
    body = {k: v for k, v in doc.items() if k not in EXCLUDED}
    return hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


# T085 Round 3 R3-B3: a process-wide monotonic counter so two
# atomic_backup_and_replace() calls landing within the SAME wall-clock
# millisecond (possible on a fast host / in a tight test loop) still get
# distinct backup_path names -- timestamp+pid alone is not guaranteed
# unique across rapid successive calls from one process.
_ATOMIC_BACKUP_COUNTER = 0
# T085 Round 5 (Minor finding 1): bounded retry count for the
# O_CREAT|O_EXCL-guarded backup-path collision loop below -- a genuine
# collision (the SAME timestamp+pid+counter already in use, e.g. a
# leftover from a prior crashed run, or an adversarial pre-planted
# symlink at that exact name) is retried with a freshly bumped counter
# rather than ever falling through to a copy that could clobber an
# existing symlink's target; bounded so a persistently hostile/broken
# directory cannot hang this function forever.
_ATOMIC_BACKUP_MAX_RETRIES = 8


def atomic_backup_and_replace(target_path, new_text, backup_tag="bak"):
    """The ONE shared primitive, for every "hardlink the pre-op bytes,
    then atomically replace the live file's content" site in this tool
    family, that replaces the hardlink-then-truncate-in-place anti-
    pattern (`os.link(target, backup)` followed by `open(target, "w")`)
    which silently DESTROYS the backup it just took: `os.link()` makes
    `backup` and `target` the SAME inode, so writing THROUGH `target` in
    place rewrites the bytes `backup` also sees. Confirmed as a real,
    reproduced bug at TWO independent call sites before this helper
    existed:
      - constitution/scripts/fastcycle/gates/batch_bisect.py's
        `cmd_wip_caps()` --apply path (T085 Round 2 B-R2-5, fixed by
        hand with the SAME write-temp-then-os.replace() pattern this
        function now generalises).
      - constitution/scripts/fastcycle/gates/lib/backstop_compare.py's
        `apply_force_full()` (T085 Round 3 R3-B3: reproduced live on a
        drifting gate map -- the map and its `.bak-*` shared one inode,
        and the "backup" held the POST-write content, the pre-op bytes
        gone -- an un-fixed sibling of B-R2-5 in a file the Round 2
        remediation itself had touched, in-scope, and never searched
        for this exact pattern in).
    A full repository search (`grep -rn "os\\.link(" --include=*.py`,
    T085 Round 3) confirmed these were the ONLY two first-party call
    sites of this anti-pattern anywhere in this tree; both now route
    through this ONE function so the bug class cannot recur a third
    time in a third call site (section 11.4.227 reuse-not-reinvention;
    section 11.4.250 heuristic-tower -- one shared primitive, not two
    independently-maintained hand-fixes that can drift apart again).

    Guarantees:
      1. `backup_path`'s bytes are -- and STAY -- `target_path`'s
         content EXACTLY as it was immediately before this call (never
         an empty/truncated/new-content copy): achieved by NEVER
         truncating `target_path` (or its resolved real path, see (4))
         in place. The new content always lands in a FRESH temp file in
         the SAME directory (`tempfile.mkstemp()`, so `os.replace()`
         stays on one filesystem and is genuinely atomic), which is
         then `os.replace()`'d over the live path -- the hardlinked
         `backup_path` keeps pointing at the OLD inode, completely
         untouched by that replace.
      2. `backup_path` is UNIQUE per call (millisecond timestamp + pid +
         a monotonic in-process counter) -- a SECOND call against the
         SAME `target_path` (e.g. a second `--apply` run) NEVER collides
         with, and is never silently skipped in favour of, a prior
         call's backup path (the `batch_bisect.py` pre-fix behaviour:
         a fixed, non-unique backup filename made `os.link()` raise
         `FileExistsError` on the second run, which was then silently
         swallowed -- the SECOND run's pre-op bytes were never captured
         at all, while the report still named the stale first-run
         `backup_path` as if it covered them).
      3. `target_path`'s ORIGINAL mode bits are preserved on the
         replacement file -- `tempfile.mkstemp()` defaults to mode
         0600, so without this, every apply would silently TIGHTEN
         `target_path`'s permissions (e.g. 0644 -> 0600) as a side
         effect of nothing but taking a backup.
      4. If `target_path` is itself a SYMLINK, the write targets the
         symlink's RESOLVED real path instead of the symlink itself --
         `target_path` stays a symlink pointing at the (now-updated)
         real file, rather than being silently replaced by a plain
         regular file (what a bare `os.replace()` on a symlink path
         would do: replace the symlink entry itself, breaking whatever
         it was intentionally pointing at).
      5. Falls back to a real byte-for-byte copy (`shutil.copy2`) for
         the backup when hardlinking is unsupported (e.g. the backup
         would land on a different filesystem) -- the existing
         documented section 9.2 fallback, unchanged by this helper.

    T085 Round 5 (Minor finding 1): the fallback-copy step above used to
    run unconditionally whenever `os.link()` raised ANY `OSError` --
    including `FileExistsError`, which it conflated with "hardlinking is
    unsupported here" even though it actually means "something is
    ALREADY sitting at `backup_path`". Demonstrated (frozen clock):
    `shutil.copy2(src, dst)` on a `dst` that is ALREADY a symlink does
    not replace the symlink entry -- it opens `dst` for writing, which
    FOLLOWS the symlink and overwrites whatever it points at. Closed,
    together with two related gaps the same review named:
      - `backup_path` is now created via `os.open(..., O_CREAT|O_EXCL)`
        (never silently overwritten, never followed if it is a
        symlink); on a genuine collision the attempt is retried with a
        freshly bumped counter (bounded, `_ATOMIC_BACKUP_MAX_RETRIES`)
        rather than ever falling through to a copy that could clobber
        an unrelated existing path.
      - the new content is now `fh.flush()` + `os.fsync()`'d before
        `os.replace()`, and the containing directory is ALSO fsync'd
        after the replace -- durability-complete temp-then-rename
        (section 11.4.205(6)), not merely atomic-looking.
      - on ANY failure after the backup was taken, the (now-unneeded)
        backup is best-effort removed too (never masking the real
        exception) -- `target_path` itself is NEVER touched before
        `os.replace()` succeeds, so a failed call leaves nothing new
        behind, backup included.
      - the original file's owner (uid/gid) is ALSO best-effort
        preserved on the replacement (silently ignored when this
        process lacks the privilege to chown, e.g. not running as
        root) -- HONEST RESIDUAL (section 11.4.6): extended attributes
        (xattrs) are NOT preserved by this helper; none of this
        project's own call sites write xattr-bearing files, and adding
        full xattr copy support is out of this fix's scope.

    Returns `backup_path`. Raises `OSError` on a genuine I/O failure --
    this function never silently swallows a write failure; the fresh
    temp file (and, per the above, an unneeded backup) is removed on
    that path so no stray file is left behind."""
    global _ATOMIC_BACKUP_COUNTER

    real_target = os.path.realpath(target_path) if os.path.islink(target_path) else target_path
    out_dir = os.path.dirname(os.path.abspath(real_target)) or "."

    try:
        with open(real_target, "rb") as fh:
            orig_bytes = fh.read()
    except OSError:
        orig_bytes = None  # target does not exist yet / unreadable -- hardlink/copy below will raise honestly

    backup_path = None
    last_exc = None
    for _attempt in range(_ATOMIC_BACKUP_MAX_RETRIES):
        _ATOMIC_BACKUP_COUNTER += 1
        candidate = "%s.%s-%d-%d-%d" % (
            real_target, backup_tag, int(time.time() * 1000), os.getpid(), _ATOMIC_BACKUP_COUNTER,
        )
        try:
            os.link(real_target, candidate)
            backup_path = candidate
            break
        except FileExistsError as exc:
            last_exc = exc
            continue  # genuine name collision -- retry with a freshly bumped counter, never fall through to copy
        except OSError:
            # Hardlinking genuinely unsupported here (e.g. cross-filesystem) -- fall back to a
            # real byte-for-byte copy, but via the SAME O_CREAT|O_EXCL-guarded path so an
            # existing symlink/file at `candidate` is refused rather than followed/overwritten.
            try:
                fd = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
            except FileExistsError as exc2:
                last_exc = exc2
                continue
            try:
                with os.fdopen(fd, "wb") as bfh:
                    bfh.write(orig_bytes if orig_bytes is not None else b"")
                    bfh.flush()
                    os.fsync(bfh.fileno())
                shutil.copystat(real_target, candidate)
            except OSError:
                try:
                    os.unlink(candidate)
                except OSError:
                    pass
                raise
            backup_path = candidate
            break
    if backup_path is None:
        raise OSError(
            "atomic_backup_and_replace: could not create a unique backup path after "
            "%d attempts (last error: %s)" % (_ATOMIC_BACKUP_MAX_RETRIES, last_exc)
        )

    try:
        orig_stat = os.stat(real_target)
        orig_mode = stat.S_IMODE(orig_stat.st_mode)
    except OSError:
        orig_stat = None
        orig_mode = None

    fd, tmp_path = tempfile.mkstemp(dir=out_dir, prefix=".atomic_backup_write.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(new_text)
            fh.flush()
            os.fsync(fh.fileno())
        if orig_mode is not None:
            os.chmod(tmp_path, orig_mode)
        if orig_stat is not None:
            try:
                os.chown(tmp_path, orig_stat.st_uid, orig_stat.st_gid)
            except OSError:
                pass  # not running with chown privilege -- best-effort only
        os.replace(tmp_path, real_target)
        try:
            dir_fd = os.open(out_dir, os.O_DIRECTORY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError:
            pass  # directory fsync is a durability nicety, never fatal to a successful replace
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        try:
            os.unlink(backup_path)  # the backup is now unneeded -- best-effort cleanup, never masks the real error
        except OSError:
            pass
        raise

    return backup_path


def _nofollow_opener(path, flags):
    """Custom `open()` opener (see `merkle_over_dir_lstat` below): adds
    `O_NOFOLLOW` to the flags Python's own `open()` builtin would
    otherwise pass to the real `os.open()` syscall, where the platform
    exposes that flag (Linux/BSD; silently unavailable on platforms that
    do not define `os.O_NOFOLLOW`, e.g. Windows -- `merkle_over_dir_lstat`'s
    own preceding `os.lstat` check is its real, platform-independent
    defense; `O_NOFOLLOW` here closes only the narrow TOCTOU window
    between that `lstat` and this `open`, section 11.4.6 honest
    boundary: it defends against nothing else)."""
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return os.open(path, flags)


def merkle_over_dir_lstat(root):
    """T140 Round 10 independent review finding I2 (section 11.4.250
    heuristic-tower/primitive-defect, section 11.4.227 reuse-not-
    reinvention): the ONE shared, lstat-based, symlink-NON-following
    MerkleRoot tree hasher every fastcycle tool that hashes a directory
    tree now uses -- landed here, in `fc_common.py`, rather than as
    another independently-reimplemented per-tool copy (the retired
    `orchestration/handoff.py::_merkle_over_dir` was exactly such a copy,
    and the defect this function closes was specific to that copy's own
    unguarded, following `open()` deep inside its own tree walk).

    The defect this closes (T140 ADDENDUM 114, verbatim): "The realpath
    check only covers `current_dir`. `_merkle_over_dir` then opens every
    entry with a following `open()`. Nested file symlink,
    `tree_current/d/pw -> /etc/passwd`: passes the check, and
    `/etc/passwd`'s bytes are hashed ... That makes the tool a hash
    oracle for arbitrary readable files ... `tree_current/d/z ->
    /dev/zero`: an unbounded read ... an OOM hazard (section 12) ... A
    FIFO under the tree: the tool hung until `timeout` (rc=124)." The
    caller's own top-level containment check (`os.path.realpath` against
    `tree_current/`'s own root, still correct and unchanged -- see
    `orchestration/handoff.py`'s own `cmd_resume_check`) only resolves
    the SINGLE, top-level `locator` path once; it says nothing about
    entries genuinely INSIDE that tree that are THEMSELVES symlinks,
    which is exactly what this function now refuses to follow, at any
    depth, ever.

    sha256 over the sorted list of (relative-path, ContentAddress) pairs
    of every REGULAR FILE under `root` (data-model.md sec0 MerkleRoot
    convention: "pairs sorted bytewise by path; empty set is a distinct,
    valid root"), where:
      - `os.walk(root, followlinks=False)` never DESCENDS into a
        symlinked directory in the first place (without this, a
        symlinked SUBTREE, not merely one file, would be silently walked
        as if it were real) -- this alone is not sufficient, since
        `os.walk` still reports a NON-directory symlink as an ordinary
        filename, which is why every entry is ALSO explicitly re-checked
        below.
      - every entry `os.walk` reports is inspected via `os.lstat`
        (NEVER `os.stat`, NEVER a following `open()`) before this
        function decides what it is -- a genuine TOCTOU window exists
        between this `lstat` and any subsequent `open()`, closed for
        regular files by `_nofollow_opener` above (`O_NOFOLLOW`); for a
        symlink entry there is no subsequent open at all (see next
        bullet), so no such window exists for that case.
      - a symlink entry (file OR directory symlink alike -- `os.walk`
        reports a directory symlink as a `dirnames` entry it will not
        descend into, which would otherwise silently DROP it from the
        Merkle set entirely, its own honesty gap per section 11.4.6: a
        symlinked directory's mere presence is still a real, hashable
        fact about this tree) is hashed from its OWN link text
        (`os.readlink()`), exactly as git hashes a symlink blob -- its
        TARGET is NEVER read, opened, or followed, at any depth. This is
        the ONE change that structurally closes BOTH the `/etc/passwd`
        hash-oracle finding AND the `/dev/zero` unbounded-read finding:
        neither can be reached at all once a symlink's target is simply
        never opened.
      - a non-regular, non-symlink entry (FIFO, socket, device, ...) is
        refused outright -- raises `OSError` (never `ValueError`;
        matching `os.lstat`'s own exception class, so every caller of
        this function that already wraps it in `except OSError` -- e.g.
        `orchestration/handoff.py`'s own `cmd_resume_check` check (2) --
        needs NO changes of its own to also catch this) naming the path
        and its real mode -- rather than ever being `open()`-ed. This is
        what structurally closes the FIFO-hang finding: `os.lstat`
        identifies the FIFO BEFORE any `open()` is attempted, so the
        blocking `open()` that previously hung this tool until `timeout`
        is simply never reached.
      - a regular file is opened via `_nofollow_opener` above (Python's
        own `open(..., opener=...)` hook -- lets Python's `open()`
        builtin manage the resulting file object's lifecycle normally,
        rather than this function hand-managing a raw `os.open()` fd).

    A non-existent `root` yields the empty-set root -- an honest, real
    ContentAddress that will (correctly) mismatch any non-empty recorded
    one, never a crash."""
    pairs = []
    if os.path.isdir(root):
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            for name in sorted(dirnames) + sorted(filenames):
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, root).replace(os.sep, "/")
                try:
                    st = os.lstat(full)
                except OSError as exc:
                    raise OSError(exc.errno, "cannot lstat %r under tree %r: %s" % (rel, root, exc))
                mode = st.st_mode
                if stat.S_ISLNK(mode):
                    link_text = os.readlink(full)
                    digest = "sha256:" + hashlib.sha256(link_text.encode("utf-8", "surrogateescape")).hexdigest()
                    pairs.append((rel, digest))
                    continue
                if name in dirnames:
                    # A real (non-symlink) directory -- os.walk descends
                    # into it on a later iteration; it contributes no leaf
                    # entry of its own (the pre-existing, file-only
                    # convention every checked-in fixture's own
                    # expected_verdict.json was derived against).
                    continue
                if not stat.S_ISREG(mode):
                    raise OSError(errno.EINVAL, "refusing non-regular, non-symlink entry %r under tree "
                                                 "%r (mode=%s) -- this hasher never opens a FIFO/socket/"
                                                 "device node" % (rel, root, oct(mode)))
                try:
                    with open(full, "rb", opener=_nofollow_opener) as fh:
                        data = fh.read()
                except OSError as exc:
                    raise OSError(exc.errno, "cannot read %r under tree %r: %s" % (rel, root, exc))
                digest = "sha256:" + hashlib.sha256(data).hexdigest()
                pairs.append((rel, digest))
    pairs.sort(key=lambda p: p[0].encode("utf-8"))
    body = [[p, c] for p, c in pairs]
    return "sha256:" + hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


def _no_dups(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen:
            raise ValueError("duplicate key %r" % k)
        seen[k] = v
    return seen


def _bad_const(name):
    raise ValueError("non-canonical JSON constant %s" % name)


def _finite_float(text):
    val = float(text)
    if val != val or val in (float("inf"), float("-inf")):
        raise ValueError("non-finite number %s" % text)
    return val


def strict_loads(text):
    try:
        return json.loads(text, object_pairs_hook=_no_dups, parse_constant=_bad_const, parse_float=_finite_float)
    except RecursionError:
        raise ValueError("JSON nesting too deep")


def _json_arg(text, name):
    try:
        return strict_loads(text)
    except ValueError as exc:
        print("fc_common: bad JSON for %s: %s" % (name, exc), file=sys.stderr)
        sys.exit(2)


def cmd_emit(a):
    body = _json_arg(a.body_json, "--body-json")
    if not isinstance(body, dict):
        print("fc_common: --body-json must be an object", file=sys.stderr)
        return 2
    bad = [k for k in RESERVED if k in body]
    if bad:
        print("fc_common: reserved body key(s) refused: %s" % ", ".join(bad), file=sys.stderr)
        return 2
    meta = {} if a.run_meta_json is None else _json_arg(a.run_meta_json, "--run-meta-json")
    if not isinstance(meta, dict):
        print("fc_common: --run-meta-json must be an object", file=sys.stderr)
        return 2
    if a.code == 3:
        print("fc_common: self-test failed; no result file written", file=sys.stderr)
        return 3
    if not SCHEMA_RE.fullmatch(a.schema):
        print("fc_common: --schema must match <tool>/v<N>, got %r" % a.schema, file=sys.stderr)
        return 2
    doc = dict(body)
    doc["schema"] = a.schema
    if a.code == 4:
        doc["BLIND"] = True
    try:
        doc["body_hash"] = body_hash_of(doc)
        doc["run_meta"] = meta
        data = (canon(doc) + "\n").encode("utf-8")
    except (UnicodeEncodeError, ValueError) as exc:
        print("fc_common: body not encodable as UTF-8: %s" % exc, file=sys.stderr)
        return 2
    out_dir = os.path.dirname(os.path.abspath(a.out))
    try:
        fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".fc_emit.")
        try:
            umask = os.umask(0)
            os.umask(umask)
            os.fchmod(fd, 0o666 & ~umask)
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)
            os.replace(tmp, a.out)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    except OSError as exc:
        print("fc_common: cannot write --out: %s" % exc, file=sys.stderr)
        return 2
    return a.code


def cmd_body_hash(a):
    try:
        with open(a.doc, encoding="utf-8") as fh:
            doc = strict_loads(fh.read())
    except (OSError, ValueError) as exc:
        print("fc_common: cannot read doc: %s" % exc, file=sys.stderr)
        return 2
    if not isinstance(doc, dict):
        print("fc_common: doc must be a JSON object", file=sys.stderr)
        return 2
    try:
        recomputed = body_hash_of(doc)
    except (UnicodeEncodeError, ValueError) as exc:
        print("fc_common: body not encodable as UTF-8: %s" % exc, file=sys.stderr)
        return 2
    if not a.verify:
        print(recomputed)
        return 0
    stored = doc.get("body_hash")
    if not isinstance(stored, str) or not stored:
        print("fc_common: --verify needs a stored string body_hash in the doc", file=sys.stderr)
        return 2
    if not HASH_RE.fullmatch(stored):
        print("fc_common: --verify: stored body_hash is not 64 lowercase hex characters", file=sys.stderr)
        return 2
    if stored != recomputed:
        print("fc_common: body_hash mismatch: stored=%s recomputed=%s" % (stored, recomputed))
        return 1
    print(recomputed)
    return 0


def _scalar(x):
    return x is None or isinstance(x, (str, int, float, bool))


def cmd_needle(a):
    present = _json_arg(a.present, "--present")
    fabricated = _json_arg(a.fabricated, "--fabricated")
    hay_l = _json_arg(a.haystack, "--haystack")
    for name, val in (("--present", present), ("--fabricated", fabricated), ("--haystack", hay_l)):
        if not isinstance(val, list) or any(not _scalar(x) for x in val):
            print("fc_common: %s must be a JSON list of scalars (str/int/float/bool/null)" % name, file=sys.stderr)
            return 2
    if not present or not fabricated:
        print("fc_common: needle sets must be non-empty", file=sys.stderr)
        return 3
    # membership: numbers by value (JSON has one number type: 1 == 1.0); a bool never equals a number (C-004)
    def key(x):
        return ("bool", x) if isinstance(x, bool) else ("num", x) if isinstance(x, (int, float)) else (type(x).__name__, x)
    hay = {key(x) for x in hay_l}
    missing = [x for x in present if key(x) not in hay]
    found_fab = [x for x in fabricated if key(x) in hay]
    if missing or found_fab:
        print("fc_common: needle FAIL missing=%s fabricated_found=%s" % (missing, found_fab), file=sys.stderr)
        return 3
    return 0


def _group_alive(pgid):
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _reap_group(proc, pgid):
    """TERM the command's whole process group, SIGKILL after the grace; leave no member (C-001: no orphan).

    `pgid` is the pid `_run_bounded` gave Popen(start_new_session=True): on POSIX that call makes the
    child its own session AND process-group leader, so pgid == the child's own pid.

    FIXED (waitid/WNOWAIT handoff, T014 round-10 MINOR-7): `_run_bounded` no longer reaps the leader
    itself -- it detects completion via os.waitid(..., WNOWAIT) (see `_leader_exited_unreaped`), which
    never consumes the zombie, so by the time this function's very first line runs
    (`os.killpg(pgid, SIGTERM)`) the leader is, ordinarily, EITHER still genuinely running (trivially
    valid pgid) OR already exited but not yet reaped -- a zombie, whose pid (and therefore pgid, since it
    is the group leader) the kernel cannot reuse until something reaps it for real, which does not happen
    until later in THIS function (`proc.poll()`/`proc.wait()` below). This closes, completely, what used
    to be a real (if narrow) window here: `_run_bounded` previously reaped the leader via
    `proc.wait(timeout=...)` BEFORE calling this function, so this line's `os.killpg` could in
    principle already have been signalling a pgid the kernel had freed for reuse.

    FIXED (SIGCHLD-inherited-as-SIG_IGN hazard): there is a THIRD case the paragraph above does not cover
    on its own -- the leader may ALSO already have been auto-reaped by the kernel with no zombie ever
    created at all (SIGCHLD inherited as SIG_IGN in this process; POSIX says such a process's children
    "shall not be transformed into zombie processes when they terminate", and CPython's own
    `Popen.poll()`/`wait()` silently treat that ECHILD as `returncode = 0` -- a fabricated, not a real,
    verdict). In that case `pgid` here is NOT provably still valid -- the kernel may have already reused
    it -- so this function's `os.killpg(pgid, SIGTERM)` is best-effort cleanup only, exactly as it already
    is for a genuinely-stale pgid (see the pid-reuse discussion below); the correctness fix for THIS
    specific hazard lives entirely in `_run_bounded`, which resets SIGCHLD to SIG_DFL before every spawn
    (so the kernel keeps a real zombie to begin with) and independently confirms, via
    `_leader_reap_honest()`, that any exit `_leader_exited_unreaped` reports really was a real zombie and
    not this ECHILD case -- if it was not, `_run_bounded` returns `NO_HONEST_VERDICT` and never lets this
    function's `proc.returncode` (which may by then be CPython's own fabricated 0) reach the caller,
    regardless of what this function does with the (possibly already-stale) pgid.

    Residual, NOT closed the same way (verified, not merely asserted -- see below): the loop just below
    still detects the leader's OWN exit via `proc.poll()`, which -- being a single `waitpid(WNOHANG)`
    syscall that checks-and-reaps atomically, with zero gap between "detected" and "reaped" -- is
    already the tightest possible "is it done" step there is; swapping it for a two-step
    `waitid(WNOWAIT)`-then-`wait()` sequence would WIDEN this specific step's own window (two separate
    calls instead of one), not narrow it, for no benefit. The real residual sits downstream of that
    reap: if a straggler descendant (not the leader) is still alive, the loop keeps polling
    `_group_alive(pgid)` for up to `DETERMINISM_KILL_AFTER_S` more seconds before the eventual
    `os.killpg(pgid, SIGKILL)` -- and THAT signal, sent however long after the leader was reaped, is
    subject to the identical class of pgid-recycling risk as the now-fixed handoff above, just with a
    wall-clock window bounded by the grace period instead of "a few bytecode instructions". This CANNOT
    be closed by deferring the leader's OWN reap the same way `_run_bounded` now does for its handoff
    (i.e. keeping it a zombie through the whole grace-period wait, then deciding on the escalation
    afterwards): measured directly on this host (`os.killpg(pgid, 0)` / `os.kill(pid, 0)` against a
    real, exited-but-unreaped zombie) -- a zombie leader STILL answers a group-existence probe as
    "alive" (the kernel keeps a zombie's slot fully addressable until reaped), so `_group_alive()` would
    report the group busy for the *entire* grace period on EVERY invocation, even when it is genuinely
    already quiet -- confirmed to regress the measured "graceful TERM exit is noticed promptly" bound
    this suite pins (a leader that exits within the grace period would then never short-circuit, always
    paying the full `DETERMINISM_KILL_AFTER_S`). Closing this residual for real would need either
    per-descendant pid tracking (a materially different "signal the whole group" primitive than this
    function's) or re-validating pgid identity via /proc (e.g. comparing /proc/<pgid>/stat's starttime
    across the wait) -- both of which this function's own design already declines, for the identical
    reason given below for the (now-closed) handoff gap: on any host with a realistic pid_max, the
    kernel reissuing this EXACT number inside even a multi-second window remains astronomically
    unlikely -- the R6b pid-reuse test (tests/test_check_deps.sh) can only force it deterministically by
    shrinking pid_max inside a fresh Linux pid namespace. Left as a documented, bounded (by
    `DETERMINISM_KILL_AFTER_S`), not-further-closed residual, narrower in scope than before this fix
    (the handoff gap above is now fully closed; only this loop's own escalation path retains any window
    at all) rather than fabricated shut.

    pidfd correction (verified, not merely re-asserted): a pidfd-based redesign was previously dismissed
    here on the grounds that "pidfd signals ONE pid, not a group". That claim is WRONG as stated on a
    kernel/glibc new enough to expose it: this host (Linux 6.12.41, glibc 2.43) ships
    `PIDFD_SIGNAL_PROCESS_GROUP` (confirmed present in
    /usr/include/linux-default/include/linux/pidfd.h and /usr/include/sys/pidfd.h), a
    `pidfd_send_signal(2)` flag documented for exactly this purpose -- signalling the WHOLE process
    group of the process a pidfd refers to, through a single, race-free, stable file-descriptor
    reference (pidfd_send_signal(2): "a PID file descriptor is a stable reference to a specific
    process; if that process terminates, pidfd_send_signal() fails with the error ESRCH" -- it can
    never misfire against a recycled pid). What remains true, and keeps this out of scope here:
    CPython's `os` module on this build (3.13) does not yet wrap `os.pidfd_send_signal` (only
    `os.pidfd_open` is exposed), so using this flag from pure Python stdlib still needs `ctypes` or a
    raw syscall; and adopting it would still mean holding a pidfd open across the child's whole
    lifetime and signalling through it in place of a numeric pgid -- i.e. still the larger redesign this
    function's docstring already declines for this fix's scope, replacing rather than hardening the
    current primitive -- not a claim that no such fix could ever exist.
    """
    if pgid <= 1:  # never signal pgid <= 1 (kill(-1) = every process of the user)
        return
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    end = time.monotonic() + DETERMINISM_KILL_AFTER_S
    while time.monotonic() < end:
        if proc.poll() is not None and not _group_alive(pgid):
            return
        time.sleep(0.05)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()


def _leader_exited_unreaped(pid):
    """True if `pid` has already exited but is not yet reaped, checked via os.waitid(..., WNOWAIT) so the
    check itself never consumes the zombie: kept a zombie, its pid (and, for a process spawned with
    start_new_session=True -- a session/group leader -- therefore its pgid too) cannot be reused by the
    kernel until something later reaps it for real. Returns False while it is still running (nothing is
    consumed either way, matching a plain, side-effect-free poll). A ChildProcessError (no such child
    left to wait for -- already reaped by someone else, or never our child at all) is treated as
    "exited": either way nothing is left running under that pid, and distinguishing those two cases
    further is not this call's job.
    """
    try:
        info = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    except ChildProcessError:
        return True
    return info is not None


def _leader_reap_honest(pid):
    """True iff `pid`'s exit (as just reported by `_leader_exited_unreaped()`) is backed by a REAL,
    confirmed zombie the kernel is still holding for us -- i.e. NOT the ChildProcessError/ECHILD branch of
    that function (already reaped by someone else / never truly our child / -- the case this exists to
    catch -- SIGCHLD inherited as SIG_IGN in this process, so POSIX has the kernel auto-reap the child and
    discard its exit status the INSTANT it terminates, without ever creating a zombie to observe at all).

    Side-effect-free (os.waitid(..., WNOWAIT), same as `_leader_exited_unreaped`) and safe to call again
    right after that function already reported the leader exited for the same pid: WNOWAIT never consumes,
    so both calls observe the identical, unchanged kernel state -- this is a second, independent read of
    the same fact, not a race against the first.

    `_run_bounded` calls this exactly once, at the moment it is about to trust `proc.returncode`, so it can
    fail closed (return `NO_HONEST_VERDICT`) instead of accepting CPython's own silent
    `Popen.poll()`/`wait()` ECHILD -> `returncode = 0` fallback (CPython's own `subprocess.Popen`
    documents this: "This happens if SIGCLD is set to be ignored ... This child is dead, we can't get the
    status.") for a status that is genuinely gone -- never a real verdict, however clean it looks.
    """
    try:
        os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    except ChildProcessError:
        return False
    return True


# _run_bounded's own bounded-completion poll interval. Matches _reap_group's pinned 0.05s interval for
# file-wide consistency; no test here (nor any real use of --code-controlled command completion) needs
# finer precision than this, and CPython's OWN internal Popen.wait(timeout=...) degrades to a comparably
# coarse adaptive-backoff poll for longer waits anyway (waitpid has no OS-level timeout primitive).
RUN_BOUNDED_POLL_S = 0.05


def _run_bounded(cmd, env, timeout_s):
    """Run cmd in its own session; return its rc, NO_HONEST_VERDICT, or None on timeout. The whole group is
    reaped either way.

    Detects the leader's own exit via `_leader_exited_unreaped()` (os.waitid WNOWAIT) instead of a
    reaping `proc.wait(timeout=...)`, so the leader is NEVER reaped here -- `_reap_group()` is the sole
    place that ever performs the real (destructive) reap of the leader. By the time this function hands
    off to it (in the `finally` below, on every path: finished-in-time, timed-out, or an unexpected
    exception from the poll loop itself), the leader is, ordinarily, either still genuinely running or a
    confirmed-but-still-zombie exit, so `_reap_group()`'s own first action (`os.killpg(pgid, SIGTERM)`) is
    normally sent to a provably still-valid pgid. This closes the handoff race `_reap_group()`'s own
    docstring describes: previously this function's `proc.wait(timeout=timeout_s)` reaped the leader
    BEFORE `_reap_group()` ran, so its SIGTERM could in principle already have been signalling a pgid the
    kernel had freed for reuse.

    FIXED (SIGCHLD-inherited-as-SIG_IGN hazard, independently reproduced and confirmed): a caller that has
    SIGCHLD=SIG_IGN in effect before spawning this process (POSIX preserves SIG_IGN across exec, so e.g.
    `signal.signal(signal.SIGCHLD, signal.SIG_IGN)` then `os.execvp("python3", [... "determinism-check",
    ...])` carries it straight into this interpreter) makes the kernel auto-reap and discard ANY child we
    spawn the instant it exits -- no zombie is EVER created for us to observe, regardless of how fast this
    function polls. `_leader_exited_unreaped()`'s ChildProcessError branch already treats that the same as
    a genuine exit (by design, for its own narrower "is anything still running" question), and CPython's
    own `Popen.poll()`/`wait()` -- called later, inside `_reap_group()`, to obtain the REAL destructive
    reap and rc -- silently fabricate `returncode = 0` on the identical ECHILD condition, so an
    ALWAYS-FAILING command could be reported as a stable, clean rc=0: a PASS-bluff. Two changes close this,
    together: (1) SIGCHLD is reset to SIG_DFL in THIS process, unconditionally, before every spawn below --
    regardless of what this process inherited -- so the kernel keeps a genuine zombie for the child this
    function itself is responsible for reaping; (2) belt-and-suspenders, in case that reset were ever
    undone or bypassed by something outside this function's control, `_leader_reap_honest()` independently
    re-confirms (a second, non-destructive WNOWAIT probe) that the exit just observed really was a real
    zombie and not this ECHILD case -- if it was not, this function returns `NO_HONEST_VERDICT` and NEVER
    lets `proc.returncode` (which may by then already be CPython's own fabricated 0) reach the caller,
    regardless of anything `_reap_group()` does afterward with the (possibly by-then-stale) pgid.

    Honest residual: this closes the hazard completely for the ONE child this function itself spawns and
    reaps (the leader) -- it says nothing about, and cannot fix, SIGCHLD handling inside the COMMAND UNDER
    TEST's own further descendants, which is that command's own business, not this harness's.
    """
    # Reset SIGCHLD to its default disposition in THIS process, unconditionally, before spawning: see the
    # "FIXED (SIGCHLD-inherited-as-SIG_IGN hazard...)" paragraph above. Idempotent; safe to call on every
    # invocation (cmd_determinism calls this function twice, once per run) regardless of what this process
    # inherited or what a prior call already set it to.
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    proc = subprocess.Popen(cmd, env=env, start_new_session=True)
    exited = False
    no_honest_verdict = False
    try:
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            if _leader_exited_unreaped(proc.pid):
                exited = True
                no_honest_verdict = not _leader_reap_honest(proc.pid)
                break
            time.sleep(RUN_BOUNDED_POLL_S)
    finally:
        _reap_group(proc, proc.pid)
    if no_honest_verdict:
        return NO_HONEST_VERDICT
    return proc.returncode if exited else None


def _timeout_from_env():
    raw = os.environ.get("FC_DETERMINISM_TIMEOUT_S")
    if raw is None:
        return DETERMINISM_TIMEOUT_DEFAULT_S
    if not TIMEOUT_RE.fullmatch(raw) or int(raw) < 1:
        print("fc_common: FC_DETERMINISM_TIMEOUT_S must be a positive integer of at most 6 digits, got %r" % raw,
              file=sys.stderr)
        return None
    return int(raw)


def cmd_determinism(a):
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    if not cmd:
        print("fc_common: no command given", file=sys.stderr)
        return 2
    timeout_s = _timeout_from_env()
    if timeout_s is None:
        return 2
    runs = []
    with tempfile.TemporaryDirectory() as tmp:
        for i in (1, 2):
            out = os.path.join(tmp, "run%d.json" % i)
            env = dict(os.environ, FC_OUT=out, LC_ALL="C")
            try:
                rc = _run_bounded(cmd, env, timeout_s)
            except OSError as exc:
                print("fc_common: cannot run command: %s" % exc, file=sys.stderr)
                return 4
            if rc is NO_HONEST_VERDICT:
                # SIGCHLD was inherited as SIG_IGN (or some other cause put this process's own reaping of
                # the leader into the ECHILD state): no real exit status was ever obtainable, so this is
                # never a verdict, never rc=0, however clean CPython's own Popen.poll()/wait() may have
                # looked internally -- see _run_bounded / _leader_reap_honest.
                print("fc_common: no honest verdict: command run %d exit status unobtainable "
                      "(SIGCHLD disposition prevented reaping)" % i, file=sys.stderr)
                return 4
            if rc is None:
                print("fc_common: no honest verdict: command run %d timed out after %ds" % (i, timeout_s), file=sys.stderr)
                return 4
            if rc == 3:
                print("fc_common: command self-test failed (rc=3) run %d" % i, file=sys.stderr)
                return 3
            if rc not in (0, 1) or not os.path.exists(out):
                print("fc_common: no honest verdict: command run %d rc=%d doc_present=%s"
                      % (i, rc, os.path.exists(out)), file=sys.stderr)
                return 4
            try:
                with open(out, encoding="utf-8") as fh:
                    doc = strict_loads(fh.read())
                if not isinstance(doc, dict):
                    raise ValueError("doc is not a JSON object")
            except (OSError, ValueError) as exc:
                print("fc_common: command run %d wrote an unreadable doc: %s" % (i, exc), file=sys.stderr)
                return 4
            body = {k: v for k, v in doc.items() if k not in EXCLUDED}
            runs.append((rc, body_hash_of(doc), json.dumps(body, sort_keys=True, indent=1, ensure_ascii=False)))
    if runs[0][:2] != runs[1][:2]:
        print("fc_common: nondeterministic rc/body_hash %s/%s != %s/%s" % (runs[0][0], runs[0][1], runs[1][0], runs[1][1]),
              file=sys.stderr)
        diff = list(difflib.unified_diff(runs[0][2].splitlines(), runs[1][2].splitlines(), "run1", "run2", lineterm="", n=1))
        for line in diff[:40]:
            print(line, file=sys.stderr)
        return 1
    return 0


def cmd_as_of(a):
    if a.windowed and not a.as_of:
        print("fc_common: windowed tool requires --as-of YYYY-MM-DD (no default to today)", file=sys.stderr)
        return 2
    if a.as_of is not None:
        try:
            if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", a.as_of):
                raise ValueError("not YYYY-MM-DD")
            datetime.date.fromisoformat(a.as_of)
        except ValueError:
            print("fc_common: bad --as-of date", file=sys.stderr)
            return 2
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="fc_common")
    sub = p.add_subparsers(dest="cmd_name", required=True)
    e = sub.add_parser("emit")
    e.add_argument("--schema", required=True)
    e.add_argument("--body-json", required=True)
    e.add_argument("--run-meta-json")
    e.add_argument("--out", required=True)
    e.add_argument("--code", type=int, default=0, choices=(0, 1, 3, 4))
    b = sub.add_parser("body-hash")
    b.add_argument("--doc", required=True)
    b.add_argument("--verify", action="store_true")
    n = sub.add_parser("needle")
    n.add_argument("--present", required=True)
    n.add_argument("--fabricated", required=True)
    n.add_argument("--haystack", required=True)
    d = sub.add_parser("determinism-check")
    d.add_argument("cmd", nargs=argparse.REMAINDER)
    r = sub.add_parser("require-as-of")
    r.add_argument("--windowed", action="store_true")
    r.add_argument("--as-of")
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0
    table = {"emit": cmd_emit, "body-hash": cmd_body_hash, "needle": cmd_needle,
             "determinism-check": cmd_determinism, "require-as-of": cmd_as_of}
    try:
        return table[a.cmd_name](a)
    except Exception as exc:  # C-001: an internal error is never a finding (1)
        print("fc_common: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return EXIT_INTERNAL


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
