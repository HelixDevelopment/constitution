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
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

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

    Returns `backup_path`. Raises `OSError` on a genuine I/O failure --
    this function never silently swallows a write failure; the fresh
    temp file is removed on that path so no stray `.atomic_backup_write.*`
    file is left behind."""
    global _ATOMIC_BACKUP_COUNTER

    real_target = os.path.realpath(target_path) if os.path.islink(target_path) else target_path
    out_dir = os.path.dirname(os.path.abspath(real_target)) or "."

    _ATOMIC_BACKUP_COUNTER += 1
    backup_path = "%s.%s-%d-%d-%d" % (
        real_target,
        backup_tag,
        int(time.time() * 1000),
        os.getpid(),
        _ATOMIC_BACKUP_COUNTER,
    )
    try:
        os.link(real_target, backup_path)
    except OSError:
        shutil.copy2(real_target, backup_path)

    try:
        orig_mode = stat.S_IMODE(os.stat(real_target).st_mode)
    except OSError:
        orig_mode = None

    fd, tmp_path = tempfile.mkstemp(dir=out_dir, prefix=".atomic_backup_write.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(new_text)
        if orig_mode is not None:
            os.chmod(tmp_path, orig_mode)
        os.replace(tmp_path, real_target)
    except OSError:
        try:
            os.unlink(tmp_path)
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
