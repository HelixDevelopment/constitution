#!/usr/bin/env python3
"""batch_bisect.py - related-change batching with bisection + DEC-21 WIP
caps (spec-004 "fast-dev-cycles", User Story 2; plan.md T-C06; tasks.md
T072; SC-002, FR-005). Guarded by
constitution/scripts/fastcycle/tests/test_batch_bisect_red.sh (T056), per
its own header comment the AUTHORITATIVE, mechanically-checked wire format
(no contracts/*.md file names T-C06 -- plan.md's own "Plan tools that no
contract in this directory covers" list says so explicitly, and
common-conventions.md's C-001..C-007 cross-cutting rules are still applied
here as the house baseline even though no dedicated contract exists).

=============================================================================
Subcommand 1: `run` -- batch validation + bisection (T056's binding wire
format, defined in that RED test's own header comment, UNCONFIRMED by any
contract file, binding-if-adopted, mirroring T051's precedent):

    batch_bisect.py run --batch <batch.json> --base-tree <dir> \\
        --patches <dir> --gate <gate.sh> --out <result.json> \\
        [--determinism-check]

batch.json: {"batch_id": str, "changes": [{"change_id": str,
             "target_file": str, "patch": str}, ...]}
result.json (ALWAYS written on a real verdict, C-002 canonical JSON +
             body_hash/run_meta/schema): {"schema": "batch-bisect/v1",
    "batch_id": ..., "batch_verdict": "PASS"|"FAIL",
    "per_change": {change_id: "PASS"|"FAIL", ...}, "culprits": [change_id],
    "gate_invocations": int, "bisection_mode": "bisect"|"exhaustive",
    "body_hash": ..., "run_meta": {...}}

Exit codes (C-001, and T056's own header: "exit code communicates the
batch OUTCOME, never whether bisection itself succeeded"):
  0 = batch_verdict PASS (result.json written)
  1 = batch_verdict FAIL (result.json ALWAYS still written on a FAIL --
      T056's own header: "bisection still runs and result.json is still
      written on FAIL"); ALSO used for a --determinism-check mismatch
      (a genuine finding, reusing 1 exactly as the sibling
      gates/catchset_compare.py's cmd_compare already does)
  2 = usage/config error (bad --batch JSON, missing/unreadable
      --base-tree/--patches/--gate, duplicate change_id, a change naming
      a patch file absent from --patches) -- no result.json written
  3 = self-test failed: the control needle (the UNPATCHED base_tree must
      itself PASS gate.sh -- §11.4.201/§11.4.273's baseline-sanity
      needle, the same role CS-003 plays for catchset_compare's corpus)
      did not hold -- the gate/corpus combination is not trustworthy this
      run; NO result.json written (C-001 row 3)
  4 = BLIND: the disposable tree could not be built/read (filesystem
      failure) -- no honest verdict possible; no result.json written

Algorithm (deliberately NOT the reference bisector's exhaustive
single-change isolation -- gates/tests/lib/bb_ref_bisect.py's own
docstring is explicit that its exhaustive approach exists only to PROVE
the fixtures, "not search efficiency"; this is the real T-C06 tool, so it
does the real thing: RECURSIVE BISECTION, O(log n) typical gate
invocations rather than O(n)):

  1. Control needle: build a disposable tree from --base-tree with ZERO
     changes applied and run --gate on it. It MUST PASS (unpatched
     baseline sanity) or this run self-test-fails (exit 3, no output).
  2. Build the FULL batch tree (every change applied) and run --gate ->
     batch_verdict.
  3. batch_verdict == PASS: every change's per_change is PASS (by
     construction -- the full set already ran clean, so no member alone
     could differ under this run's own soundness argument below),
     culprits = [].
  4. batch_verdict == FAIL: recursive halving (`isolate()` below) narrows
     to the culprit(s) in O(log n) typical gate runs: split the FAILing
     (sub)set in two, test each half; a half that PASSES marks every one
     of its members PASS WITHOUT a further gate run (the halving
     shortcut); a half that FAILS recurses (base case: a size-1 set's own
     already-known verdict IS its solo verdict, no re-test needed).

  SOUNDNESS of the halving shortcut ("a PASSing half means every member
  of it is individually clean, without solo-testing each"): this holds
  exactly when every change's effect on the gate is INDEPENDENT of every
  OTHER change in the batch -- concretely here, when no two changes in
  the batch name the SAME --target_file (T056's own fixture corpus
  documents this invariant explicitly: gate.sh's header says "each
  targets a distinct file, so they never collide"; change_c_bad.sh's own
  header repeats it). This tool does NOT blindly assume that holds for an
  arbitrary caller-supplied batch.json: it checks for a duplicate
  target_file across the batch UP FRONT and, if found, disables the
  halving shortcut entirely and falls back to EXHAUSTIVE per-change solo
  isolation (identical semantics to bb_ref_bisect.py) for that run,
  recorded honestly in result.json's "bisection_mode" field
  ("bisect" vs "exhaustive") -- never silently trusting an assumption the
  input itself could violate (§11.4.6/§11.4.201).

  Either path terminates in a per_change map whose value for EVERY change
  is, by construction, exactly its SOLO-isolation verdict (apply only
  that one change to --base-tree, nothing else) -- the identical
  definition bb_ref_bisect.py uses and the exact property T056's
  bb_per_change_matches_individual fixture checks ("per-change verdicts
  equal individual runs").

=============================================================================
Subcommand 2: `wip-caps` -- DEC-21 WIP caps, written into
config/fastcycle/thresholds.yaml (tasks.md T072: "WIP caps per DEC-21
written into config/fastcycle/thresholds.yaml from the T041 throughput
figures"). No contract or wire format exists for this subcommand either
(same "no contract in this directory" gap as `run`); defined here.

    batch_bisect.py wip-caps --thresholds <thresholds.yaml> \\
        [--metrics <queue_metrics.json>] [--apply]

HONEST SCOPE GAP (§11.4.6, carried forward verbatim from T056's own
EVIDENCE line, re-confirmed by this task's own search): DEC-21
(research.md) sets each queue's WIP cap "from the measured throughput of
that queue (T-A09)"; its OWN "initial cap is the current median WIP of
the queue" and it is "lowered in steps while throughput is watched,
raised back if throughput falls." T-A09's real tool
(cycle/cycle_report.py, tasks.md T041, [x] landed) computes PER-ITEM
touch/wait/tokens, not a per-queue median-WIP or throughput figure -- and
T056's own EVIDENCE line records, as of this writing, "DEC-21's WIP-cap
clause depends on unmeasured T-A09 throughput data, explicitly handed to
T-C06's implementer." A direct search of specs/004-fast-dev-cycles/ for
"T041" (this task's own instruction) turns up no recorded throughput
number anywhere -- config/fastcycle/thresholds.yaml's wip_caps section is
`UNMEASURED # T-A09` for all three queues today, and it stays that way
here: this subcommand NEVER invents a number (§11.4.6). When given real
per-queue metrics (--metrics, schema documented at load_metrics() below)
it applies DEC-21's own literal formula (initial cap = that queue's
current median WIP); when it is not given one -- the true, current state
of this project -- it re-affirms the honest UNMEASURED placeholder with
an explicit, named gap comment rather than silently leaving the file
alone or guessing a number. This satisfies both halves of this task's own
instruction: "if truly unfindable, add the WIP-cap key with an honest
placeholder value and a comment naming the gap ... never silently omit
it."

--apply is required to actually rewrite --thresholds (C-006: "Any write
is behind an explicit --apply flag and a backup marker (§9.2)"); without
it, wip-caps is read-only and reports what WOULD be written. A §9.2
hardlinked pre-op backup of --thresholds is taken before any --apply
write.

Exit codes: 0 = report/write succeeded (regardless of whether any queue
is still UNMEASURED -- that is an honest, not an error, state); 2 =
usage/config error (missing --thresholds, unreadable --metrics JSON, a
thresholds.yaml missing the wip_caps: block).
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers (identical
# import-by-path pattern to closure/escape_classify.py -- constitution
# /scripts/fastcycle has no __init__.py anywhere, matching this tree's
# existing flat-script layout).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of


class TargetPathEscapeError(OSError):
    """T085 Round 2 B-R2-5(a): raised by build_tree() when a change's
    target_file would resolve OUTSIDE the disposable tree it is being
    copied into -- an absolute target_file (os.path.join silently DISCARDS
    the tmp prefix for an absolute second argument) or a '..'-escaping
    relative one lets an attacker-or-buggy batch.json write anywhere on
    the filesystem a real victim file became 'PWNED' when reproduced live
    before this fix (§11.4.199). Subclasses OSError so every EXISTING
    `except OSError` call site around build_tree()/verdict_for() already
    maps this to EXIT_BLIND (no result.json written, no partial/untrusted
    verdict) with no further call-site changes needed; cmd_run() ALSO
    validates every change's target_file syntactically UP FRONT (before
    any tree is built at all, alongside the existing --patches existence
    check) so the common case is refused as a clean EXIT_USAGE before this
    defense-in-depth check is ever reached."""


def is_safe_relative_target(rel_path):
    """T085 Round 2 B-R2-5(a): True iff rel_path is safe to join under ANY
    directory root via os.path.join(root, rel_path) without escaping that
    root -- never an absolute path (os.path.join(root, '/etc/passwd')
    returns '/etc/passwd', discarding root entirely -- reproduced live),
    never containing a '..' path segment that walks back out of root."""
    if not isinstance(rel_path, str) or not rel_path:
        return False
    if os.path.isabs(rel_path):
        return False
    normalized = os.path.normpath(rel_path)
    if normalized == os.pardir or normalized.startswith(os.pardir + os.sep):
        return False
    # normpath collapses a leading '/' away on POSIX for a relative-looking
    # string like 'a/../../b' -> '../b', already caught above; an embedded
    # '..' that stays net-non-escaping (e.g. 'a/../b' -> 'b') is fine.
    return True


SCHEMA = "batch-bisect/v1"
WIP_CAPS_SCHEMA = "batch-bisect-wip-caps/v1"

EXIT_OK = 0
EXIT_FAIL_OR_FINDING = 1
EXIT_USAGE = 2
EXIT_SELFTEST = 3
EXIT_BLIND = 4

# The three DEC-21 queues (research.md's own enumeration: "per track, per
# review queue, per device-flash queue"), matching thresholds.yaml's
# existing wip_caps: keys byte-for-byte.
WIP_QUEUES = ("per_track", "review_queue", "device_flash_queue")


# ---------------------------------------------------------------------------
# `run` -- batch/tree/gate mechanics
# ---------------------------------------------------------------------------
def load_batch(path):
    """Reads + structurally validates --batch. Returns the parsed dict or
    None with an explanatory message already written to stderr (caller
    exits 2). Validated here rather than trusted blind (§11.4.6): a
    missing change_id/target_file/patch, a non-list changes, or a
    duplicate change_id is a usage error, not a silent partial batch."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            batch = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write("batch_bisect run: cannot read/parse --batch %s: %s\n" % (path, exc))
        return None
    if not isinstance(batch, dict):
        sys.stderr.write("batch_bisect run: --batch %s must be a JSON object\n" % path)
        return None
    batch_id = batch.get("batch_id")
    changes = batch.get("changes")
    if not isinstance(batch_id, str) or not batch_id:
        sys.stderr.write("batch_bisect run: --batch %s missing string 'batch_id'\n" % path)
        return None
    if not isinstance(changes, list) or not changes:
        sys.stderr.write("batch_bisect run: --batch %s 'changes' must be a non-empty list\n" % path)
        return None
    seen_ids = set()
    for i, ch in enumerate(changes):
        if not isinstance(ch, dict):
            sys.stderr.write("batch_bisect run: changes[%d] is not an object\n" % i)
            return None
        for key in ("change_id", "target_file", "patch"):
            if not isinstance(ch.get(key), str) or not ch.get(key):
                sys.stderr.write("batch_bisect run: changes[%d] missing string '%s'\n" % (i, key))
                return None
        cid = ch["change_id"]
        if cid in seen_ids:
            sys.stderr.write("batch_bisect run: duplicate change_id %r in --batch %s\n" % (cid, path))
            return None
        seen_ids.add(cid)
    return batch


def build_tree(base_tree_dir, patches_dir, changes):
    """Disposable tempdir: a fresh copy of every file in base_tree_dir,
    then each change's patch file copied over base_tree/<target_file>
    (identical semantics to bb_ref_bisect.py's build_tree, deliberately --
    the per-change model this whole corpus/tool pair shares). Raises
    OSError on a real filesystem failure (caller maps that to exit 4
    BLIND -- never a silent empty tree)."""
    tmp = tempfile.mkdtemp(prefix="batch_bisect_")
    for entry in os.listdir(base_tree_dir):
        src = os.path.join(base_tree_dir, entry)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(tmp, entry))
    tmp_real = os.path.realpath(tmp)
    patches_dir_real = os.path.realpath(patches_dir)
    for ch in changes:
        src = os.path.join(patches_dir, ch["patch"])
        dst = os.path.join(tmp, ch["target_file"])
        # T085 Round 2 B-R2-5(a) defense-in-depth: cmd_run() already
        # refuses an unsafe target_file syntactically before reaching
        # here (the common path); this realpath-based check is the
        # authoritative one -- it also catches any direct compute_
        # batch_result() caller that bypassed cmd_run()'s own validation.
        dst_real = os.path.realpath(dst)
        if dst_real != tmp_real and not dst_real.startswith(tmp_real + os.sep):
            shutil.rmtree(tmp, ignore_errors=True)
            raise TargetPathEscapeError(
                "change %r target_file %r resolves to %r, OUTSIDE the "
                "disposable tree %r -- refusing to write (T085 Round 2 "
                "B-R2-5(a))" % (ch.get("change_id"), ch["target_file"], dst_real, tmp_real)
            )
        # T085 Round 3 m5 (MINOR): the pre-fix version above checked
        # ONLY the write-side target_file for containment -- a change's
        # `patch` field (the READ side, joined onto patches_dir) was
        # never checked at all, so a `patch` value such as
        # `"../../../../etc/passwd"` (or any path escaping patches_dir)
        # would be happily shutil.copy2()'d into the disposable tree,
        # copying an arbitrary readable file from anywhere the process
        # can read. Mirrors the SAME realpath-containment check above,
        # applied to the read side.
        src_real = os.path.realpath(src)
        if src_real != patches_dir_real and not src_real.startswith(patches_dir_real + os.sep):
            shutil.rmtree(tmp, ignore_errors=True)
            raise TargetPathEscapeError(
                "change %r patch %r resolves to %r, OUTSIDE patches_dir "
                "%r -- refusing to read (T085 Round 3 m5)"
                % (ch.get("change_id"), ch["patch"], src_real, patches_dir_real)
            )
        shutil.copy2(src, dst)
    return tmp


# T085 Round 2 MINOR: a hung/misbehaving --gate previously had no bound --
# a single stuck gate invocation could wedge this tool (and, transitively,
# anything driving it) indefinitely. Mirrors gate_audit.py's own
# run_gate() timeout convention (§12/§11.4.225 host-safety).
GATE_TIMEOUT_SECONDS = 120


def run_gate_on_tree(gate_path, tree_dir):
    """Runs --gate against tree_dir; returns ("PASS"|"FAIL", raw_rc). A
    gate that exceeds GATE_TIMEOUT_SECONDS is treated as FAIL (a timed-out
    gate cannot have genuinely validated the tree -- it is never silently
    read as PASS) with raw_rc -1, distinguishable from a real exit code.

    T085 Round 3 R3-I1 (IMPORTANT): the pre-fix `subprocess.run(...,
    timeout=...)` above (a) never put the gate in its OWN process group,
    so even ITS OWN timeout path could only kill the direct `gate_path`
    child, never a backgrounded grandchild the gate script spawned, and
    (b) applied NO cleanup at all on a normal (non-timeout) return --
    the SAME class of bug io_trace_build_map.py's retrace() had
    (T085 Round 2 B-R2-3 only fixed its timeout path; Round 3 R3-I1
    closed its normal-return path too). Fixed identically here: the gate
    now runs in its own session/process group
    (start_new_session=True, so proc.pid IS the pgid), and
    fc_common.safe_killpg() -- the SAME shared §11.4.263-guarded
    primitive io_trace_build_map.py now also uses (section 11.4.227
    reuse-not-reinvention) -- is called to kill the WHOLE group on
    EVERY return path: timeout, a genuine OSError, AND a normal
    (non-timeout) completion. See io_trace_build_map.retrace()'s own
    docstring for why calling safe_killpg() after the direct child has
    already been reaped is still safe (POSIX never reuses a process
    group id while any member remains alive in it)."""
    try:
        proc = subprocess.Popen(
            [gate_path, tree_dir], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
        )
    except OSError:
        return "FAIL", -1

    try:
        proc.communicate(timeout=GATE_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        fc_common.safe_killpg(proc.pid, signal.SIGKILL)
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        return "FAIL", -1

    # T085 Round 3 R3-I1: kill the WHOLE process group even on this
    # NORMAL (non-timeout) return path -- a gate script that backgrounds
    # a detached grandchild and then itself exits cleanly must not be
    # allowed to leave that grandchild running after this function
    # returns.
    fc_common.safe_killpg(proc.pid, signal.SIGKILL)

    return ("PASS" if proc.returncode == 0 else "FAIL"), proc.returncode


class GateRunner(object):
    """Owns the base_tree/patches/gate paths + a running gate_invocations
    counter (result.json's own transparency field: how many gate runs the
    bisection actually cost, proving the halving shortcut is genuinely
    cheaper than exhaustive isolation whenever it is used)."""

    def __init__(self, base_tree_dir, patches_dir, gate_path):
        self.base_tree_dir = base_tree_dir
        self.patches_dir = patches_dir
        self.gate_path = gate_path
        self.gate_invocations = 0

    def verdict_for(self, changes):
        """Builds a fresh disposable tree with exactly `changes` applied,
        runs the gate once, tears the tree down, returns "PASS"|"FAIL"."""
        tree = build_tree(self.base_tree_dir, self.patches_dir, changes)
        try:
            verdict, _rc = run_gate_on_tree(self.gate_path, tree)
        finally:
            shutil.rmtree(tree, ignore_errors=True)
        self.gate_invocations += 1
        return verdict


def has_duplicate_target_file(changes):
    seen = set()
    for ch in changes:
        tf = ch["target_file"]
        if tf in seen:
            return True
        seen.add(tf)
    return False


def isolate_bisect(runner, changes, known_verdict):
    """Recursive halving, O(log n) typical gate invocations. `changes` is
    non-empty; `known_verdict` is the ALREADY-COMPUTED verdict for
    exactly this subset (the caller tested it once before recursing --
    never re-tested here, so no subset is ever gate-run twice).

    PASS shortcut: every member of a PASSing subset is assigned PASS
    without a further gate run (sound only because of the no-duplicate-
    target_file precondition the caller already checked -- see the
    module docstring's SOUNDNESS note).
    FAIL + size 1: the base case -- a size-1 subset's own verdict IS its
    solo-isolation verdict already (no further gate run needed).
    FAIL + size > 1: split in half, test each half once, recurse into
    whichever half(s) FAILed."""
    if known_verdict == "PASS":
        return {c["change_id"]: "PASS" for c in changes}
    if len(changes) == 1:
        return {changes[0]["change_id"]: "FAIL"}
    mid = len(changes) // 2
    left, right = changes[:mid], changes[mid:]
    left_v = runner.verdict_for(left)
    right_v = runner.verdict_for(right)
    result = {}
    result.update(isolate_bisect(runner, left, left_v))
    result.update(isolate_bisect(runner, right, right_v))
    return result


def isolate_exhaustive(runner, changes):
    """Safe fallback when the no-duplicate-target_file precondition does
    NOT hold: solo-isolate every change individually (identical semantics
    to bb_ref_bisect.py's own exhaustive algorithm) -- O(n) gate
    invocations, but correct regardless of any cross-change interaction
    this run cannot rule out."""
    result = {}
    for ch in changes:
        result[ch["change_id"]] = runner.verdict_for([ch])
    return result


def compute_batch_result(batch, base_tree_dir, patches_dir, gate_path):
    """The whole `run` computation, side-effect-free w.r.t. the caller's
    filesystem beyond disposable tempdirs (each torn down before
    returning). Returns (doc_without_schema_hash_runmeta, exit_code) or
    (None, EXIT_SELFTEST) if the control needle fails, or
    (None, EXIT_BLIND) on a real filesystem failure building a tree."""
    changes = batch["changes"]
    runner = GateRunner(base_tree_dir, patches_dir, gate_path)

    # Control needle (§11.4.201/§11.4.273): the UNPATCHED base_tree alone
    # must PASS the gate before ANY verdict this run computes can be
    # trusted -- proves the gate/corpus combination is not itself broken.
    try:
        needle_verdict = runner.verdict_for([])
    except OSError:
        return None, EXIT_BLIND
    if needle_verdict != "PASS":
        sys.stderr.write(
            "batch_bisect run: control needle FAILED -- the unpatched "
            "--base-tree does not PASS --gate on its own; the gate/corpus "
            "combination is not trustworthy this run (exit 3, no result.json)\n"
        )
        return None, EXIT_SELFTEST

    try:
        batch_verdict = runner.verdict_for(changes)
    except OSError:
        return None, EXIT_BLIND

    if batch_verdict == "PASS":
        per_change = {c["change_id"]: "PASS" for c in changes}
        bisection_mode = "n/a"
    else:
        try:
            if has_duplicate_target_file(changes):
                bisection_mode = "exhaustive"
                per_change = isolate_exhaustive(runner, changes)
            else:
                bisection_mode = "bisect"
                per_change = isolate_bisect(runner, changes, batch_verdict)
        except OSError:
            return None, EXIT_BLIND

    culprits = sorted(cid for cid, v in per_change.items() if v == "FAIL")

    # Internal consistency guard (defensive, never expected to fire given
    # the construction above -- a bare assertion would be silently
    # swallowed by `python -O`, so this is a real, always-active check):
    # a FAIL batch must name >=1 culprit and vice versa.
    if (batch_verdict == "FAIL") != bool(culprits):
        sys.stderr.write(
            "batch_bisect run: INTERNAL inconsistency -- batch_verdict=%s "
            "but culprits=%r; refusing to emit an untrustworthy result "
            "(exit 4, no result.json)\n" % (batch_verdict, culprits)
        )
        return None, EXIT_BLIND

    doc = {
        "batch_id": batch["batch_id"],
        "batch_verdict": batch_verdict,
        "per_change": per_change,
        "culprits": culprits,
        "gate_invocations": runner.gate_invocations,
        "bisection_mode": bisection_mode,
    }
    exit_code = EXIT_OK if batch_verdict == "PASS" else EXIT_FAIL_OR_FINDING
    return doc, exit_code


def write_result(out_path, doc, run_meta):
    full = dict(doc)
    full["schema"] = SCHEMA
    full["body_hash"] = body_hash_of({**full})
    full["run_meta"] = run_meta
    data = (canon(full) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".batch_bisect.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def cmd_run(args):
    if not os.path.isdir(args.base_tree):
        sys.stderr.write("batch_bisect run: --base-tree not a directory: %s\n" % args.base_tree)
        return EXIT_USAGE
    if not os.path.isdir(args.patches):
        sys.stderr.write("batch_bisect run: --patches not a directory: %s\n" % args.patches)
        return EXIT_USAGE
    if not os.access(args.gate, os.X_OK):
        sys.stderr.write("batch_bisect run: --gate is not executable: %s\n" % args.gate)
        return EXIT_USAGE

    batch = load_batch(args.batch)
    if batch is None:
        return EXIT_USAGE
    for ch in batch["changes"]:
        patch_path = os.path.join(args.patches, ch["patch"])
        if not os.path.isfile(patch_path):
            sys.stderr.write(
                "batch_bisect run: change %r names patch %r, not found under --patches %s\n"
                % (ch["change_id"], ch["patch"], args.patches)
            )
            return EXIT_USAGE
        # T085 Round 2 B-R2-5(a): reject a change whose target_file would
        # escape the disposable tree BEFORE any tree is ever built (an
        # absolute path, or a '..'-escaping relative one) -- reproduced
        # live as a real write outside batch_bisect's own scratch tree.
        if not is_safe_relative_target(ch["target_file"]):
            sys.stderr.write(
                "batch_bisect run: change %r target_file %r is unsafe -- "
                "it must be a relative path that does not escape the "
                "disposable tree (absolute paths and '..'-escaping "
                "segments are refused, T085 Round 2 B-R2-5(a))\n"
                % (ch["change_id"], ch["target_file"])
            )
            return EXIT_USAGE

    doc, exit_code = compute_batch_result(batch, args.base_tree, args.patches, args.gate)
    if doc is None:
        return exit_code

    if args.determinism_check:
        doc2, exit_code2 = compute_batch_result(batch, args.base_tree, args.patches, args.gate)
        if doc2 is None:
            sys.stderr.write(
                "batch_bisect run: --determinism-check: second run could not "
                "produce a result (exit %d) -- no honest verdict, treating as "
                "nondeterministic (exit 1)\n" % exit_code2
            )
            return EXIT_FAIL_OR_FINDING
        h1 = body_hash_of(doc)
        h2 = body_hash_of(doc2)
        if h1 != h2:
            sys.stderr.write(
                "batch_bisect run: --determinism-check FAILED: two consecutive "
                "runs produced different bodies (%s != %s)\n" % (h1, h2)
            )
            return EXIT_FAIL_OR_FINDING

    run_meta = {"host": os.uname().nodename if hasattr(os, "uname") else "unknown"}
    try:
        write_result(args.out, doc, run_meta)
    except OSError as exc:
        sys.stderr.write("batch_bisect run: cannot write --out %s: %s\n" % (args.out, exc))
        return EXIT_USAGE

    if exit_code == EXIT_OK:
        print("batch_bisect run: batch %s PASS (%d gate invocation(s), mode=%s) -- %s written"
              % (batch["batch_id"], doc["gate_invocations"], doc["bisection_mode"], args.out))
    else:
        print("batch_bisect run: batch %s FAIL -- culprit(s) %s (%d gate invocation(s), mode=%s) -- %s written"
              % (batch["batch_id"], ", ".join(doc["culprits"]), doc["gate_invocations"], doc["bisection_mode"], args.out))
    return exit_code


# ---------------------------------------------------------------------------
# `wip-caps` -- DEC-21 WIP caps written into thresholds.yaml (see module
# docstring's HONEST SCOPE GAP note).
# ---------------------------------------------------------------------------
def load_metrics(path):
    """--metrics schema (defined here, no contract exists -- see module
    docstring): {"queues": {"<queue_key>": {"median_wip": <int>}, ...}}.
    A queue key absent from the file, or one with no integer median_wip,
    is left UNMEASURED (never guessed, §11.4.6). Returns the parsed dict
    or None with a stderr message already written (caller exits 2)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            metrics = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write("batch_bisect wip-caps: cannot read/parse --metrics %s: %s\n" % (path, exc))
        return None
    if not isinstance(metrics, dict) or not isinstance(metrics.get("queues"), dict):
        sys.stderr.write("batch_bisect wip-caps: --metrics %s missing object 'queues'\n" % path)
        return None
    return metrics


# Matches a wip_caps: sub-key line in thresholds.yaml, e.g.
#   "  per_track: UNMEASURED             # T-A09"
# or, once a real figure lands, "  per_track: 4                    # T-A09".
# Captures (indent, key, trailing-comment-including-leading-#-or-empty).
_WIP_LINE_RE = re.compile(
    r"^(?P<indent>[ \t]+)(?P<key>per_track|review_queue|device_flash_queue):"
    r"[ \t]*(?P<value>\S+)(?P<rest>[ \t]*(?:#.*)?)$"
)

GAP_COMMENT = "# T-A09 UNMEASURED -- no throughput figure recorded yet (T056 EVIDENCE, DEC-21); see gates/batch_bisect.py wip-caps"


def compute_wip_caps(metrics):
    """DEC-21's own literal formula: 'the initial cap is the current
    median WIP of the queue.' Returns {queue: (value_str, source_note)}
    for the 3 WIP_QUEUES -- value_str is either a decimal integer string
    (a real cap) or the literal 'UNMEASURED'."""
    caps = {}
    for q in WIP_QUEUES:
        entry = (metrics or {}).get("queues", {}).get(q) if metrics else None
        median = entry.get("median_wip") if isinstance(entry, dict) else None
        if isinstance(median, int) and not isinstance(median, bool) and median >= 0:
            caps[q] = (str(median), "DEC-21 initial cap = current median WIP (--metrics)")
        else:
            caps[q] = ("UNMEASURED", "T-A09 throughput/median-WIP not yet measured (honest gap, §11.4.6)")
    return caps


def apply_wip_caps_to_text(text, caps):
    """Line-level rewrite (never a full YAML round-trip -- thresholds.yaml
    carries load-bearing inline `# T-A09` / `# T-A10` comments a
    yaml.safe_dump would silently discard). Replaces the VALUE of each
    matched wip_caps: sub-key line, preserving indentation and appending
    the honest gap comment when the value is still UNMEASURED (or keeping
    the file's own existing comment when a real number is written).
    Returns (new_text, matched_keys)."""
    matched = set()
    out_lines = []
    for line in text.splitlines(keepends=True):
        m = _WIP_LINE_RE.match(line.rstrip("\n"))
        if m and m.group("key") in caps:
            key = m.group("key")
            matched.add(key)
            value, _source = caps[key]
            rest = m.group("rest")
            if value == "UNMEASURED" and "#" not in rest:
                rest = "  " + GAP_COMMENT
            newline = "\n" if line.endswith("\n") else ""
            out_lines.append("%s%s: %s%s%s" % (m.group("indent"), key, value, rest, newline))
        else:
            out_lines.append(line)
    return "".join(out_lines), matched


def cmd_wip_caps(args):
    if not os.path.isfile(args.thresholds):
        sys.stderr.write("batch_bisect wip-caps: --thresholds not found: %s\n" % args.thresholds)
        return EXIT_USAGE
    with open(args.thresholds, "r", encoding="utf-8") as fh:
        text = fh.read()
    if "wip_caps:" not in text:
        sys.stderr.write("batch_bisect wip-caps: --thresholds %s has no 'wip_caps:' block\n" % args.thresholds)
        return EXIT_USAGE

    metrics = None
    if args.metrics:
        metrics = load_metrics(args.metrics)
        if metrics is None:
            return EXIT_USAGE

    caps = compute_wip_caps(metrics)
    report = {
        "schema": WIP_CAPS_SCHEMA,
        "thresholds_path": args.thresholds,
        "caps": {q: {"value": v, "source": s} for q, (v, s) in caps.items()},
        "applied": bool(args.apply),
    }

    new_text, matched = apply_wip_caps_to_text(text, caps)
    missing = set(WIP_QUEUES) - matched
    if missing:
        sys.stderr.write(
            "batch_bisect wip-caps: --thresholds %s wip_caps: block is missing key(s) %s -- "
            "leaving the file untouched for those keys (never inventing a line, §11.4.6)\n"
            % (args.thresholds, ", ".join(sorted(missing)))
        )

    if args.apply:
        # §9.2 pre-op backup + atomic rewrite, via the ONE shared primitive
        # every "hardlink-backup-then-replace-the-live-file" call site in
        # this tool family now uses (fc_common.atomic_backup_and_replace(),
        # T085 Round 3 R3-B3). This single call closes THREE issues the
        # hand-rolled version above had:
        #   - T085 Round 2 B-R2-5 (the original hardlink-then-truncate-in-
        #     place bug: os.link() makes backup_path the SAME inode as
        #     args.thresholds, so writing args.thresholds in place silently
        #     overwrote the "backup" too) -- already fixed by hand here,
        #     now delegated to the shared primitive instead of a second,
        #     independently-maintained copy of the same fix.
        #   - T085 Round 3 m2 (MINOR): the pre-fix `backup_path` here was a
        #     FIXED name (args.thresholds + ".pre-wip-caps.bak"), so a
        #     SECOND --apply run hit `FileExistsError` on the hardlink and
        #     silently `pass`ed -- the second run's pre-op bytes were NEVER
        #     backed up at all, while `report["backup_path"]` still named
        #     the stale first-run path as if it covered them. The shared
        #     primitive's backup_path is unique per call (timestamp+pid+
        #     counter), so every apply genuinely captures its own pre-op
        #     bytes, never silently skipped.
        #   - T085 Round 3 m3 (MINOR): `tempfile.mkstemp()` defaults to
        #     mode 0600, so the pre-fix `os.replace(tmp_path, ...)` would
        #     silently TIGHTEN args.thresholds's permissions (e.g. 0644 ->
        #     0600) on every apply, and would replace a symlink target
        #     with a plain regular file if args.thresholds were itself a
        #     symlink. The shared primitive preserves the original mode
        #     bits and resolves a symlink to its real path before writing,
        #     so the symlink itself is never replaced.
        backup_path = fc_common.atomic_backup_and_replace(
            args.thresholds, new_text, backup_tag="pre-wip-caps.bak"
        )
        report["backup_path"] = backup_path
        print("batch_bisect wip-caps: wrote %s (backup: %s)" % (args.thresholds, backup_path))
    else:
        print("batch_bisect wip-caps: --apply not given -- read-only report only (C-006)")

    print(json.dumps(report, sort_keys=True, indent=2))
    return EXIT_OK


# ---------------------------------------------------------------------------
# argparse
# ---------------------------------------------------------------------------
def build_parser():
    p = argparse.ArgumentParser(prog="batch_bisect.py")
    sub = p.add_subparsers(dest="subcommand", required=True)

    run_p = sub.add_parser("run")
    run_p.add_argument("--batch", required=True)
    run_p.add_argument("--base-tree", required=True)
    run_p.add_argument("--patches", required=True)
    run_p.add_argument("--gate", required=True)
    run_p.add_argument("--out", required=True)
    run_p.add_argument("--determinism-check", action="store_true")
    run_p.set_defaults(func=cmd_run)

    wip_p = sub.add_parser("wip-caps")
    wip_p.add_argument("--thresholds", required=True)
    wip_p.add_argument("--metrics")
    wip_p.add_argument("--apply", action="store_true")
    wip_p.set_defaults(func=cmd_wip_caps)

    return p


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
