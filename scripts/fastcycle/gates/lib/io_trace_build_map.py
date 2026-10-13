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

T085 Round 5 remediation (2026-10-02, R4-B1 BLOCKING + R4-I2 recurrence
+ shared-primitive mandate): the Round 3 PATH/env-only sandbox above was
independently reproduced bypassable TWO ways by the Round 4 reviewer
against the committed code -- (1) an absolute-path invocation built
from a NON-"adb"-named environment variable (e.g. "$ANDROID_HOME/
platform-tools/a""db", split so the literal string "adb" never appears
contiguous anywhere the classifier or the OLD env-key-contains-"adb"
DENYLIST could see), and (2) a raw TCP socket connecting DIRECTLY to
the real adb server's 127.0.0.1:5037, with no adb binary involved at
all. Both printed real device serials when reproduced against the real
host adb server before this fix. Per the Round 4 reviewer's explicit
"before Round 5" recommendation, this is fixed with a SHARED,
namespace-based primitive in fc_common.py
(fc_common.wrap_device_sandbox_argv / device_sandbox_env /
device_sandbox_namespace_available -- see that module's own extensive
docstrings) rather than another narrow patch here: every retrace()
call, in default (non---allow-device-scripts) mode, now ALSO runs
inside a fresh, unprivileged Linux user+network+mount namespace
(unshare --map-root-user --net --mount) with /dev/bus/usb (when
present) bind-mounted over by an empty directory. Network isolation
makes the underlying ACTION -- not merely the lookup -- impossible:
connecting to 127.0.0.1:ANY-PORT inside the namespace fails with
ENETUNREACH regardless of which binary, real absolute-path or
otherwise, attempts it; this holds EVEN IF a future caller somehow
fails to strip an ANDROID_HOME-style variable from its own env
(defense-in-depth, independently verified in testing). The PATH-stub
(this file, still here) and the ALLOWLISTED environment
(fc_common.device_sandbox_env(), replacing the OLD denylist-based
`_sandboxed_env()` below, now a thin alias) remain as additional,
layered defenses -- each closes a DIFFERENT bypass class, matching
this file's own "sandbox the ACTION, not merely the lookup" principle.
FAIL-CLOSED: if the namespace-isolation precondition cannot be PROVEN
on this host (fc_common.device_sandbox_namespace_available() returns
False -- unshare missing, unprivileged user namespaces disabled, or
the live self-test did not hold), main() REFUSES to run in default
(sandboxed) mode at all -- it NEVER silently falls back to the weaker
PATH/env-only sandbox that this exact round proved bypassable.

Usage: io_trace_build_map.py --sections-dir <dir> --db <sqlite-path>
                              --tool <path-to-io_trace.sh>
                              [--per-script-timeout SECONDS]

Exit codes: 0 the pass completed (regardless of individual per-script
trace/error/timeout outcomes -- those are reported, not fatal); 2 usage
error (missing --sections-dir/--db/--tool, or --sections-dir does not
exist); 4 BLIND (the sqlite DB could not be opened/created, OR -- T085
Round 5 -- the namespace-based device sandbox's safety precondition
could not be proven on this host in default mode; see
--allow-device-scripts to explicitly opt out of sandboxing entirely).
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

# ---------------------------------------------------------------------------
# T085 Round 3 R3-I1: wiring to the shared safe_killpg() primitive
# (identical import-by-path pattern to gates/batch_bisect.py's own
# fc_common wiring -- this file lives one directory deeper, under
# gates/lib/, so the relative hop to scripts/fastcycle/lib/ is
# "../../lib" rather than batch_bisect.py's "../lib"; constitution/
# scripts/fastcycle has no __init__.py anywhere, matching this tree's
# existing flat-script layout).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

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
#
# T085 Round 3 R3-B1 (BLOCKING, 2026-10-02): independently re-measured
# against the REAL default corpus (device/rockchip/rk3588/tests/, 1244
# scripts) and confirmed the Round 2 patterns above classified 675/1244 as
# NOT device-mutating by text alone -- including the project's own real
# `test_api_proxy_pinning_census.sh`, which reaches `adb` ONLY through a
# sourced library's `ADB="${ADB:-adb}"` variable, never the literal word
# `adb`. The patterns below are widened to catch every shape the Round 3
# review demonstrated as unflagged on this real corpus (indirect `${ADB}`/
# `$ADB`-style variable references regardless of case; `rm -Rf`/`rm -fr`/
# any flag-order+case variant, not only the literal `-rf` token; `find ...
# -delete`; `reboot` embedded in an identifier such as `helper_reboot.sh`
# -- `\breboot\b` never matched because `_` is a word character, so there
# is no boundary between `_` and `r`; `svc`/`pm` on-device command verbs;
# `uhubctl`; `systemctl`; a wide process-group kill (`kill -9 -1` /
# `killall`, itself the exact §11.4.263 incident class); writing to a
# `/sys/.../authorized` USB-port-power node). THIS classifier remains a
# text-only, inherently-incomplete deny-list (a dynamically-constructed
# command name, e.g. string concatenation at runtime, can defeat ANY text
# pattern by construction) -- it is retained ONLY as a SECONDARY, defense-
# in-depth signal (an honest early skip-with-reason for the common/
# observed shapes). The PRIMARY defense against a classifier false
# negative is the device-reaching-binary SANDBOX every retrace() call runs
# under by default -- see _build_device_sandbox()/_sandboxed_env() below
# and this module's own top-of-file remediation note.
_DEVICE_PATTERNS = [
    # Case-insensitive, and matches BOTH the literal command name `adb`
    # AND any `$VAR`/`${VAR}` reference whose variable name CONTAINS "adb"
    # (covers this corpus's own ADB / REC_ADB / ADB_BIN_NAME /
    # ADB_TUNE_ADB_BIN_NAME naming conventions, none of which the pre-Round-3
    # case-sensitive-literal-only `\badb\b` pattern could ever see).
    ("adb-invocation", re.compile(r"\badb\b|\$\{?\w*adb\w*\b", re.IGNORECASE)),
    # Substring (no \b boundary) -- `_`/`.`/digits are all \w, so a prior
    # \breboot\b missed `helper_reboot.sh`, `do_reboot()`, etc.
    ("reboot", re.compile(r"reboot", re.IGNORECASE)),
    ("settings-put", re.compile(r"\bsettings\s+put\b", re.IGNORECASE)),
    ("flash-tooling", re.compile(r"\b(upgrade_tool|rkdeveloptool|fastboot)\b", re.IGNORECASE)),
    ("flash-script", re.compile(r"\bflash\.sh\b", re.IGNORECASE)),
    ("raw-block-io", re.compile(r"\bdd\s+(if|of)=|\bmkfs\.", re.IGNORECASE)),
    ("power-cycle", re.compile(r"power[_-]?cycle", re.IGNORECASE)),
    ("factory-reset", re.compile(r"factory[_-]?reset|wipe_data", re.IGNORECASE)),
    ("tuya-power-control", re.compile(r"\btuya_control\b|\btuya\.env\b|\btuya-cli\b", re.IGNORECASE)),
    ("find-delete", re.compile(r"\bfind\b[^\n]*-delete\b", re.IGNORECASE)),
    ("usb-hub-control", re.compile(r"\buhubctl\b", re.IGNORECASE)),
    ("host-service-control", re.compile(r"\bsystemctl\b", re.IGNORECASE)),
    # Signalling an entire process group / every process by name --
    # exactly the §11.4.263 forced-logout incident class.
    ("wide-process-signal", re.compile(r"\bkill\s+-\w+\s+-1\b|\bkillall\b", re.IGNORECASE)),
    ("sys-usb-authorized-write", re.compile(r"/sys/[^\s]*\bauthorized\b", re.IGNORECASE)),
    # On-device shell verbs this corpus's `${ADB} ... shell <verb>` idiom
    # embeds -- the adb-invocation pattern above already catches every
    # `${ADB}`-wrapped instance, this is additional defense-in-depth for a
    # bare occurrence of the verb itself.
    ("device-shell-verb", re.compile(r"\bsvc\s+\w+\s+\w+|\bpm\s+(clear|uninstall|grant|revoke|disable)\b", re.IGNORECASE)),
]

# An `rm -rf`-class target is EXEMPT from the device-mutating
# classification ONLY when it is STRUCTURALLY a reference to a known
# scratch mechanism -- NEVER merely because some substring of an arbitrary
# literal path happens to spell a scratch-sounding word. T085 Round 3
# R3-B1: the pre-fix `_SCRATCH_VAR_RE.search(target)` was a case-
# insensitive SUBSTRING search over the whole target token, so
# `/srv/network_share` (contains "work"), `/var/tmp_important_data`
# (contains "tmp") and `"$HOME"/Documents/evidence` (contains "evid") all
# FALSELY exempted themselves -- reproduced live by the Round 3 reviewer.
# Fixed: a target is scratch-exempt iff EITHER (a) it is a shell variable
# REFERENCE (`$NAME`/`${NAME}`/`${NAME:-...}`) whose variable NAME, taken
# as a WHOLE (never a substring of something else), starts with one of the
# documented scratch roots, OR (b) it is a LITERAL path genuinely rooted
# under a known system temp directory (`/tmp/...`, `/var/tmp/...`) -- never
# a path that merely CONTAINS one of these words anywhere in a human-
# readable directory name.
_SCRATCH_VAR_NAME_RE = re.compile(
    r"^(TMP\w*|TEMP\w*|TMPDIR\w*|TMPD\w*|TMPROOT\w*|SCRATCH\w*|WORK\w*|EVID\w*|_TMP\w*)$",
    re.IGNORECASE,
)
_SCRATCH_PATH_PREFIX_RE = re.compile(r"^/(tmp|var/tmp)/")
# Matches `rm` followed by ANY short-flag bundle (e.g. -rf, -fr, -Rf, -RF,
# -vrf) or the two long-flag spellings in either order; the caller checks
# the captured short-flag bundle itself contains both 'r' and 'f' before
# treating it as a recursive-force removal (so `rm -r` alone, or `rm -f`
# alone, does not spuriously match).
_RM_RF_SHORT_RE = re.compile(r"\brm\s+-([a-zA-Z]+)\s+(?:--\s+)?(\S+)")
_RM_RF_LONG_RE = re.compile(
    r"\brm\s+(?:--recursive\s+--force|--force\s+--recursive|-r\s+-f|-f\s+-r)\s+(?:--\s+)?(\S+)",
    re.IGNORECASE,
)


def _is_scratch_target(token):
    """True only if `token` (an `rm -rf`-class argument) is STRUCTURALLY a
    reference to a documented scratch mechanism -- see the module-level
    comment above _SCRATCH_VAR_NAME_RE for the exact R3-B1 bug this
    replaces (a loose substring match over an arbitrary literal path)."""
    t = token.strip()
    if len(t) >= 2 and t[0] == t[-1] and t[0] in ("'", '"'):
        t = t[1:-1]
    m = re.match(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)", t)
    if m:
        return bool(_SCRATCH_VAR_NAME_RE.match(m.group(1)))
    return bool(_SCRATCH_PATH_PREFIX_RE.match(t))


def _rm_rf_targets(text):
    """Yields every target token of an `rm` invocation whose combined
    flags include BOTH recursive and force, in any flag-bundling style
    (-rf, -fr, -Rf, -RF, -vrf, -r -f, -f -r, --recursive --force, ...).
    T085 Round 3 R3-B1: the pre-fix regex matched ONLY the exact literal
    `-rf` token (lowercase, that exact order), so `rm -Rf`, `rm -fr`, etc
    all sailed through entirely unmatched (never even reaching the
    scratch-exemption check at all)."""
    for m in _RM_RF_SHORT_RE.finditer(text):
        flags = m.group(1).lower()
        if "r" in flags and "f" in flags:
            yield m.group(2)
    for m in _RM_RF_LONG_RE.finditer(text):
        yield m.group(1)


def classify_device_mutating(script_text):
    """Returns (is_device_mutating, reason_or_None). Pure text
    classification -- never executes the script. A single match is
    sufficient to flag; the FIRST matching reason is reported (a script may
    match more than one class, but one honest reason is enough to explain
    the skip).

    T085 Round 3 R3-B1 honest boundary (§11.4.6): this classifier is, BY
    CONSTRUCTION, a deny-list over OBSERVED text shapes -- it can NEVER be
    structurally complete (a command name built from runtime string
    concatenation, read from a data file, or otherwise never appearing as
    a contiguous substring in the script's OWN text is invisible to any
    text scan, no matter how many patterns are added). This function is
    therefore the SECONDARY, defense-in-depth layer only; the PRIMARY
    safety mechanism is the device-sandbox every retrace() call runs
    under by default regardless of what this function returns -- see
    _build_device_sandbox()/_sandboxed_env() below."""
    for name, pattern in _DEVICE_PATTERNS:
        if pattern.search(script_text):
            return True, name
    for target in _rm_rf_targets(script_text):
        if not _is_scratch_target(target):
            return True, f"rm-rf-outside-scratch-tree({target})"
    return False, None


# -----------------------------------------------------------------------
# T085 Round 3 R3-B1 (BLOCKING, PRIMARY defense): the device-reaching-
# binary sandbox.
# -----------------------------------------------------------------------
# classify_device_mutating() above is a text-only pattern scan and is
# therefore NEVER a complete safety mechanism on its own -- confirmed by
# the Round 3 review: 675/1244 of this project's REAL
# device/rockchip/rk3588/tests/*.sh corpus classified as NOT
# device-mutating by text alone, including a real script
# (test_api_proxy_pinning_census.sh) that reaches `adb` -s <real D1
# serial> ... shell svc wifi disable / pm clear / force-stop / MITM-CA-
# install entirely through a SOURCED library's `ADB="${ADB:-adb}"`
# variable. "Never trust pattern-matching alone for something this
# dangerous" (the Round 3 reviewer's own words): EVERY script this module
# actually hands to retrace() in the default (no --allow-device-scripts)
# mode now runs with `adb`/`fastboot`/`upgrade_tool`/`rkdeveloptool`/
# `uhubctl`/`tuya_control`/`tuya-cli` replaced, on that CHILD PROCESS's
# OWN environment only (never this harness's own, never any OTHER
# subprocess's), by a stub that writes an honest refusal to stderr and
# exits nonzero -- it NEVER forwards to the real binary and NEVER
# touches a device, regardless of what the classifier above decided.
# When --allow-device-scripts IS passed, the operator has explicitly
# opted in to real device-script tracing (the documented purpose of that
# flag) and the sandbox is correctly NOT applied -- sandboxing an
# explicit, deliberate device-tracing run would just break the flag.
# T085 Round 5 (R4-B1): `_DEVICE_REACHING_BINARIES` / `_build_device_sandbox`
# / `_sandboxed_env` are now thin aliases to the ONE shared implementation
# in fc_common.py (section 11.4.227 reuse-not-reinvention -- the Round 4
# reviewer's explicit "ONE shared primitive ... not more patches"
# mandate). Kept under this module's own original names, as plain
# aliases, so nothing else in this file (or any existing caller) needs
# to change. `_sandboxed_env` (OLD denylist-based: copy-the-whole-
# environment-and-subtract-"adb"-named-keys) is REPLACED, not merely
# aliased, by fc_common.device_sandbox_env (ALLOWLIST-based, built from
# scratch -- see that function's own docstring for exactly why the OLD
# denylist shape is what let ANDROID_HOME survive untouched and enabled
# R4-B1's absolute-path bypass).
_DEVICE_REACHING_BINARIES = fc_common.DEVICE_REACHING_BINARIES
_build_device_sandbox = fc_common.build_device_sandbox_bin_dir
_sandboxed_env = fc_common.device_sandbox_env


# T085 Round 3 R3-I1: `_safe_killpg` is now a thin alias to the ONE
# shared implementation, `fc_common.safe_killpg()` (section 11.4.227
# reuse-not-reinvention -- batch_bisect.py's run_gate_on_tree() needed
# the IDENTICAL §11.4.263 guard for the SAME class of fix). Kept under
# this module's own original name so every existing call site below, and
# this module's own §11.4.263 unit test (which calls `mod._safe_killpg`
# directly by that name), continue to work completely unchanged -- see
# fc_common.safe_killpg()'s own docstring for the full guarantee.
_safe_killpg = fc_common.safe_killpg


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


def retrace(tool, script_path, timeout_s, env=None, use_namespace_sandbox=False):
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

    `env`: T085 Round 3 R3-B1 -- when given (main()'s default,
    no-device-safety-sandbox-bypass mode; see _sandboxed_env() above),
    the traced child process runs with THIS environment instead of
    inheriting the harness's own -- every device-reaching binary name is
    unreachable regardless of how the script spells the lookup. `None`
    (the default, and what main() passes when --allow-device-scripts was
    given) means "inherit this process's own environment unchanged",
    matching subprocess.Popen's own documented default and this
    function's pre-Round-3 behaviour exactly.

    `use_namespace_sandbox`: T085 Round 5 (R4-B1 BLOCKING) -- when True
    (main()'s default, no-opt-out mode; see module docstring), the traced
    argv is wrapped via fc_common.wrap_device_sandbox_argv() so it runs
    inside a fresh, unprivileged Linux user+network+mount namespace in
    ADDITION to the PATH-stub + allowlisted-`env` layers above -- this is
    the PRIMARY defense against the Round 4 reviewer's two reproduced
    bypasses (an absolute-path invocation built from an un-denylisted
    env var; a raw socket connecting directly to the real adb server),
    neither of which the PATH/env-only sandbox alone could ever stop,
    since both act on a REAL binary/socket reachable by NAME or address
    rather than through a lookup this process's own env/PATH controls.
    main() has already confirmed (ONCE, before any retrace() call --
    fc_common.device_sandbox_namespace_available()) that this host can
    actually provide the isolation before ever passing
    use_namespace_sandbox=True, so wrap_device_sandbox_argv() below is
    not expected to raise DeviceSandboxUnavailable in normal operation;
    if it somehow does (a TOCTOU loss of the precondition mid-run), that
    is treated exactly like any other OSError from this function's own
    Popen() call just below -- an honest "error" trace_status, never a
    silently-unsandboxed fallback execution.

    T085 Round 2 B-R2-3: the traced process runs in its OWN process group
    (start_new_session=True) so that, on timeout, the ENTIRE group -- not
    merely the direct `sh` child -- is killed via `os.killpg()` (guarded by
    §11.4.263's mandatory pgid>1 validation, `_safe_killpg()`). The
    pre-fix `subprocess.run(..., timeout=...)` killed only the direct
    child; a grandchild the traced gate script backgrounds (e.g. a
    `sleep 30 &`) survived the timeout and kept running after this
    function returned.

    T085 Round 3 R3-I1: the Round 2 fix above killed the process group
    ONLY on the timeout path -- a gate script that backgrounds a detached
    grandchild (e.g. `( sleep 4; dangerous_cmd ) >/dev/null 2>&1 &`) and
    then itself returns NORMALLY (exit 0, well within --per-script-
    timeout) left that grandchild running, untouched, in the SAME
    process group -- reproduced live: the orphan's own marker file was
    written 4s AFTER retrace() had already returned. Fixed: the WHOLE
    group is now killed on every return path, not only the timeout one.

    T085 Round 5 (R4-I2, defense-in-depth): the Round 3 fix above STILL
    could not reach a grandchild that calls setsid() (a brand-new
    session + process group, invisible to killpg()) -- confirmed, this
    exact class of gap, as still open at BOTH of the Round 3 "fixed"
    sites (this module and batch_bisect.py). This function now delegates
    its whole launch/timeout/reap lifecycle to the ONE shared primitive,
    fc_common.run_gate_reaped() (section 11.4.227), which reaps via a
    Linux cgroup v2 scope when available (cgroup membership is immune to
    setsid()/exec(), unlike process-GROUP membership) and falls back,
    honestly, to the SAME process-group-only mechanism this function
    used before otherwise. This composes cleanly with
    use_namespace_sandbox=True: Linux namespaces (network/mount) and
    cgroups are orthogonal kernel mechanisms -- `unshare`'s own process,
    and everything it goes on to exec/fork inside the new namespaces,
    remains a member of whatever cgroup it was moved into, so
    cgroup.kill reaches it exactly the same as an un-sandboxed
    invocation."""
    cmd = ["sh", tool, "trace", script_path]
    if use_namespace_sandbox:
        try:
            cmd = fc_common.wrap_device_sandbox_argv(cmd)
        except fc_common.DeviceSandboxUnavailable as exc:
            sys.stderr.write(f"io_trace_build_map: {script_path}: retrace raised: {exc}\n")
            return "error", [], []

    result = fc_common.run_gate_reaped(cmd, timeout_s=timeout_s, env=env)
    if result.timed_out:
        return "timeout", [], []
    if result.error is not None:
        sys.stderr.write(f"io_trace_build_map: {script_path}: retrace raised: {result.error}\n")
        return "error", [], []
    if result.returncode != 0:
        return "error", [], []
    try:
        parsed = json.loads(result.stdout.strip().splitlines()[-1]) if result.stdout.strip() else None
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

    # T085 Round 3 R3-B1 / Round 5 R4-B1 (BLOCKING, PRIMARY defense): build
    # the device-reaching-binary sandbox ONCE per build-map run, UNLESS
    # the operator explicitly opted into real device-script tracing via
    # --allow-device-scripts -- see _build_device_sandbox()/
    # _sandboxed_env()'s own module-level comment for why this is one
    # LAYER of defense (never the classify_device_mutating() deny-list
    # above, which is SECONDARY, defense-in-depth only, and can never be
    # structurally complete). `sandbox_env` is passed to EVERY retrace()
    # call below regardless of what classify_device_mutating() decided
    # for that particular script -- so even a script the classifier
    # wrongly lets through (a confirmed, real, measured 675/1244
    # false-negative rate on this project's own corpus) can never reach
    # a real device-mutating binary.
    #
    # T085 Round 5 (R4-B1): the PATH-stub + allowlisted-env layers above
    # are no longer sufficient on their own -- the Round 4 reviewer
    # reproduced TWO bypasses (absolute-path-via-unlisted-env-var; raw
    # socket to the real adb server) that act on a REAL binary/socket by
    # NAME or ADDRESS, neither reachable only "through a lookup". The
    # PRIMARY defense is now the namespace-based sandbox
    # (fc_common.wrap_device_sandbox_argv, applied inside retrace() via
    # `use_namespace_sandbox=True` below) which isolates the underlying
    # ACTION (network/mount access), not merely the lookup. Its safety
    # PRECONDITION -- that this host can actually provide that isolation
    # -- is confirmed EXACTLY ONCE here, before any script is ever
    # retraced, via a REAL, LIVE self-test
    # (fc_common.device_sandbox_namespace_available() -- never inferred
    # from `unshare`'s mere presence on PATH). If that precondition does
    # NOT hold, this run REFUSES to proceed in default (sandboxed) mode
    # at all -- it NEVER silently falls back to the PATH/env-only
    # sandbox this exact round proved bypassable (§11.4.201(4): the
    # conservative-safe default on an unresolvable safety signal).
    sandbox_dir = None
    sandbox_env = None
    use_namespace_sandbox = False
    if not args.allow_device_scripts:
        if not fc_common.device_sandbox_namespace_available():
            sys.stderr.write(
                "io_trace_build_map: REFUSING to run in default (sandboxed) "
                "mode -- the namespace-based device sandbox's safety "
                "precondition could not be confirmed on this host (unshare "
                "missing, unprivileged user namespaces disabled, or the "
                "live loopback-isolation self-test did not hold). This is a "
                "fail-closed refusal (§11.4.201(4)): the PATH/env-only "
                "sandbox alone was independently proven bypassable (T085 "
                "Round 4 R4-B1) and is never used as a silent fallback. "
                "Either fix the host's namespace-isolation support, or "
                "re-run with --allow-device-scripts to explicitly opt out "
                "of sandboxing entirely (never done automatically).\n"
            )
            return EXIT_BLIND
        sandbox_dir = tempfile.mkdtemp(prefix="fastcycle-device-sandbox-")
        _build_device_sandbox(sandbox_dir)
        sandbox_env = _sandboxed_env(sandbox_dir)
        use_namespace_sandbox = True

    try:
        for script_path in scripts:
            try:
                digest = sha256_file(script_path)
            except OSError as exc:
                sys.stderr.write(f"io_trace_build_map: {script_path}: cannot read for hashing: {exc}\n")
                continue

            # T085 Round 2 B-R2-3: classify BEFORE any cache/retrace
            # decision, from the CURRENT file content, every run -- a
            # script that becomes device-mutating after an edit is caught
            # immediately, and one that stops matching is no longer
            # skipped, with no stale classification cached anywhere.
            # T085 Round 3 R3-B1: this classification is now a SECONDARY
            # signal only (an early, honest skip-with-reason for the
            # common/observed shapes) -- a script that is NOT classified
            # device-mutating here still runs inside the sandbox built
            # above (see the retrace() call below), which is the PRIMARY
            # defense against exactly this classifier's own known,
            # measured incompleteness.
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

            # T085 Round 2 B-R2-3: a cache HIT requires the sha256 to
            # match AND the persisted trace_status to be "ok" -- a prior
            # "error"/"timeout" row is ALWAYS re-attempted, never served
            # as a stale permanent hit.
            prior_sha, prior_status = cached_row(conn, script_path)
            if prior_sha == digest and prior_status == "ok":
                hits += 1
                continue
            retraced += 1
            status, reads, writes = retrace(
                args.tool, script_path, args.per_script_timeout, env=sandbox_env,
                use_namespace_sandbox=use_namespace_sandbox,
            )
            upsert(conn, script_path, digest, status, reads, writes)
            if status == "ok":
                ok_count += 1
            elif status == "timeout":
                timeout_count += 1
            else:
                error_count += 1
            conn.commit()
    finally:
        if sandbox_dir is not None:
            shutil.rmtree(sandbox_dir, ignore_errors=True)

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
