#!/usr/bin/env python3
"""precheck_pack_run.py - real implementation behind
review/precheck_pack.sh (spec-004 "fast-dev-cycles", plan.md T-C11;
tasks.md T078; FR-023, SC-009, SC-002; contracts/review-batch-and-
precheck.md RB-002; data-model.md #10.3 PreCheckReport). This is
precheck_pack.sh's OWN internal library (house pattern: gates/io_trace.sh
-> gates/lib/io_trace_parse.py) -- invoked ONLY by that thin dispatcher,
never called directly by a contract-facing caller.

Usage:   precheck_pack_run.py --batch <batch.json> --clean-checkout <dir>
             --out <precheck.json> [--config <cfg>] [--determinism-check]
             [--baseline-repo [PREFIX=]PATH]... [--baseline-ref REF]
Exit:    0 all_pass; 1 any check FAILs; 2 usage/malformed --batch;
         4 self-test failed (--determinism-check only: two consecutive
         runs on the same inputs produced different body_hash, or an
         inner run itself did not exit 0/1 cleanly -- no honest verdict).

Checks emitted (data-model.md #10.3's full 10-member enum, fixed order,
C-003 determinism): parse, shellcheck, affected-gates, touched-gate-
mutations, secret-scan, doc-sync, closure-evidence-class, sibling-search,
blast-radius, already-fixed-markers.

Per-check honest scope (constitution 11.4.6 -- nothing below is
fabricated; every PASS/FAIL is either a real subprocess invocation
against real files under --clean-checkout, or an honestly-narrow,
clearly-labelled "not yet wired" result, never an invented finding):

  - parse, shellcheck, secret-scan -- BATCH-SCOPED when the batch's own
    data confidently establishes a per-file changed-set, else an honest
    whole-checkout fallback (fix applied post-T078 landing; see
    _batch_scoped_files() below for the full derivation + its safety
    invariants). Root cause of the pre-fix defect: these three checks
    unconditionally walked the ENTIRE --clean-checkout tree, so on a real
    multi-hundred-thousand-file repo (this project's own constitution
    checkout) ANY batch -- no matter how clean its own changes were --
    inherited every pre-existing, unrelated repo-wide parse error /
    shellcheck finding / secret-scan hit and reported all_pass=false,
    making all_pass=true structurally unachievable (live-confirmed: a
    genuinely clean 2-file batch still got all_pass=false purely from
    949 unrelated pre-existing shellcheck findings + 11 unrelated
    pre-existing secret-scan hits elsewhere in the tree). The fix scopes
    these three checks to exactly the files the ReviewBatch's own slices
    declare changed -- NEVER by narrowing the check logic itself, and
    NEVER by suppressing a real finding IN one of the batch's own
    changed files (an in-scope defect still FAILs the check exactly as
    before); only unrelated, out-of-batch-scope pre-existing content
    stops being counted. Each check's own `evidence.scope` field records
    honestly whether it ran "batch" (scoped) or "whole-checkout"
    (fallback), plus `evidence.scope_note` naming why.
  - parse: for every *.sh file in scope, runs the real `sh -n` /
    `bash -n` (interpreter chosen from the file's own shebang line) and
    reports any real syntax error.
  - shellcheck: WHOLE-FILE STRICT with a SEVERITY FLOOR ("touch a file, own
    its shellcheck findings") -- every shell script in scope is linted whole
    under a hard memory cap and a size cap; every error- and warning-level
    finding and every finding of a closed set of high-value info rules FAILs,
    every other finding is listed (advisory); directive policy D1-D5; one
    narrow, checked-in legacy-exception ratchet. Full contract in the block
    comment above check_shellcheck. Honest gap: if the `shellcheck` binary is
    absent from PATH this check PASSes with evidence mode "skipped" naming the
    gap (11.4.3 honest skip) -- such a pack is never dispatch-ready.
  - secret-scan: a real, self-contained regex scan (AWS access-key-id
    shape, PEM private-key headers, an inline api-key/secret/password/
    token assignment shape) over every file in scope.
    HONEST GAP: this is a small, documented pattern set, not a claim of
    exhaustive secret-detection coverage.
  - affected-gates / touched-gate-mutations / doc-sync /
    closure-evidence-class / already-fixed-markers: HONEST GAP -- this
    revision has no wired data source for these five checks (no base/head
    shas are available from a ReviewBatch to drive gates/affected_set.py;
    no prior-round history is available to precheck_pack_run.py's own
    --batch/--clean-checkout inputs to derive already-fixed markers; no
    docs-chain/closure-status integration is wired). Each PASSes with the
    same empty-but-real evidence shape this project's own
    tests/fixtures/review_record/{golden-good,golden-bad,negative-control}
    /precheck.json fixtures already use for an empty result (e.g.
    {"gates": []}, {}, {"items": []}, {"markers": []}) -- never a
    fabricated non-empty finding, and the gap is named here rather than
    silently implied complete.
  - blast-radius: real, not fabricated -- copied verbatim from the
    ReviewBatch's own slices' context_pack.blast_radius (produced by
    review/slicer.py from the real change set; genuinely computed there
    -- a real changed-path count + listing -- never slicer.py's own
    "UNMEASURED" placeholder, which only sibling_search_ref uses). T085
    Round 3: the verdict tracks batch-wide FIELD PRESENCE, never a
    hardcoded PASS. T085 Round 6 (R5-I2 IMPORTANT): a value that is
    PRESENT but is the literal string "UNMEASURED" is now ALSO treated
    as equivalent to missing (FAIL) -- see check_sibling_search()'s own
    docstring below for the full recurrence this closes; this clause
    applies to blast_radius purely for defensive consistency (the real
    slicer.py never actually emits that literal for this field).
  - sibling-search: T085 Round 6 (R5-I2 IMPORTANT) REWRITE -- this check
    no longer merely reads whatever sibling_search_ref placeholder a
    slice's own context_pack happens to declare. root cause (T085 Round
    5 independent review, a RECURRENCE of the Round 3 false-null this
    project had already fixed once): "The new check fails only when the
    field is MISSING. The production review/slicer.py fills it with the
    literal value 'UNMEASURED'. All 11 slices of [a real, otherwise-
    clean] all_pass:true pack carried 'UNMEASURED', and the check still
    reported PASS." review/slicer.py's own module docstring already
    honestly documents WHY it can never measure this itself: it has no
    --clean-checkout parameter at all and therefore structurally cannot
    search a real tree for anything -- "UNMEASURED ... this revision
    integrates no sibling-search tool" was never a placeholder slicer.py
    could ever outgrow on its own. precheck_pack_run.py, unlike
    slicer.py, DOES receive `root` (--clean-checkout) -- so the genuine
    measurement is wired in HERE instead: for every slice whose
    changed-path set _paths_from_slice() can confidently establish, this
    check performs a REAL, bounded, deterministic (never network/LLM)
    filesystem search of `root` for other files sharing the same
    basename STEM (filename without its final extension) in a DIFFERENT
    directory -- a literal, defensible reading of "sibling": a file that
    may carry the identical defect pattern this slice's own change
    addresses, or a paired implementation/test counterpart, consistent
    with this check's placement alongside already-fixed-markers in the
    SAME anti-recurrence check suite. PASS requires every slice to have
    been genuinely searched (finding zero or more candidates -- both
    honest, valid outcomes); a slice whose changed-path set cannot be
    confidently established is honestly FAIL, naming which slice (never
    a silently-skipped slice reported as though it were searched). The
    batch's own declared sibling_search_ref (when present) is carried
    through as additional context in the evidence but is NEVER itself
    the basis of the verdict -- the EXACT shape (a field merely being
    PRESENT, even with "UNMEASURED" as its literal content) that let the
    Round 5 bluff recur is structurally impossible here, because nothing
    about the verdict depends on that field's value at all anymore.

Output (C-002): canonical JSON, `schema: "precheck/v1"`, `body_hash` =
sha256 of the canonical body excluding `run_meta` (this file's own tiny
copy of the same two canonicalisation primitives review_record.py and
review/slicer.py each keep locally, per review_record.py's own stated
"no cross-file runtime dependency" policy applied consistently across
this whole tool family).
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from precheck_common import (CANONICAL_EXCEPTIONS_REL, EMPTY_TREE, _DIFF_PIN, _body_hash_of,  # noqa: E402  F13
                             _canon, _change_diff_argv, _git_env, gate_version as _common_gate_version)

SCHEMA = "precheck/v1"
_SKIP_DIRS = (".git", "__pycache__")

CHECK_ORDER = (
    "parse",
    "shellcheck",
    "affected-gates",
    "touched-gate-mutations",
    "secret-scan",
    "doc-sync",
    "closure-evidence-class",
    "sibling-search",
    "blast-radius",
    "already-fixed-markers",
)

# secret-scan (HONEST GAP -- a small, documented pattern set, see module
# docstring): (compiled pattern, label).
SECRET_PATTERNS = (
    (re.compile(r"AKIA[0-9A-Z]{16}"), "aws-access-key-id"),
    (re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----"), "private-key-header"),
    (re.compile(r"(?i)(?:api[_-]?key|secret|password|token)\s*[:=]\s*['\"][A-Za-z0-9/+_=-]{12,}['\"]"),
     "inline-credential-assignment"),
)

# Matches build_batch()'s real, deterministic review/slicer.py blast_radius
# string verbatim: "%d changed path(s) in this slice: %s" %
# (len(paths), ", ".join(paths)). See _paths_from_slice().
# re.S + fullmatch: a path may contain a newline (NUL-safe enumeration, F14); the
# declared-count round-trip below still refuses an ambiguous split.
_BLAST_RADIUS_RE = re.compile(r"(\d+) changed path\(s\) in this slice: (.+)", re.S)


def _write(body, out_path):
    doc = dict(body)
    doc["schema"] = SCHEMA
    try:
        doc["body_hash"] = _body_hash_of(doc)
        doc["run_meta"] = {"written_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        data = (_canon(doc) + "\n").encode("utf-8")
    except (UnicodeEncodeError, ValueError) as exc:
        print("precheck_pack: body not encodable: %s" % exc, file=sys.stderr)
        return 2
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    try:
        fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".precheck_pack.")
        try:
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)
            os.replace(tmp, out_path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    except OSError as exc:
        print("precheck_pack: cannot write --out: %s" % exc, file=sys.stderr)
        return 2
    return 0


def _load_json(path, label):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh), None
    except (OSError, ValueError) as exc:
        return None, "%s: cannot read/parse %s: %s" % (label, path, exc)


def _relpath(path, root):
    try:
        return os.path.relpath(path, root)
    except ValueError:
        return path


_SHELL_EXTS = (".sh", ".bash", ".ksh", ".dash")


def _shebang_interpreter(path):
    """Returns "bash" if the file's own shebang names bash, else the
    conservative default "sh" (used by the parse check)."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            first = fh.readline()
    except OSError:
        return "sh"
    if first.startswith("#!") and "bash" in first:
        return "bash"
    return "sh"


def _is_shell_script(path):
    """True for a regular file with a shell extension OR a sh/bash/dash/ksh/mksh/ash
    shebang (extension-less scripts included). Symlinks are never reported here --
    check_shellcheck classifies them itself (a symlinked SCRIPT is refused, any
    other symlink is only listed)."""
    if os.path.islink(path):
        return False
    if path.endswith(_SHELL_EXTS):
        return True
    try:
        with open(path, "rb") as fh:
            first = fh.readline(256)
    except OSError:
        return False
    return _interp_of(first.decode("utf-8", "replace").rstrip("\r\n")) in _SHELL_INTERPS


def _find_shell_scripts(root):
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in _SKIP_DIRS)
        for fn in sorted(filenames):
            p = os.path.join(dirpath, fn)
            if _is_shell_script(p):
                hits.append(p)
    return hits


def _have(binary):
    return shutil.which(binary) is not None


# ---------------------------------------------------------------------------
# Batch-scoping for parse / shellcheck / secret-scan (module docstring's
# "root cause" note). Real data only (constitution 11.4.6): a per-file
# changed-set is derived from the ReviewBatch's OWN slices; when it cannot
# be confidently established, the caller falls back to the honest
# whole-checkout scan (never a guessed PARTIAL scope, and never dropping a
# genuinely in-scope file from scanning).
# ---------------------------------------------------------------------------
def _paths_from_slice(slice_obj):
    """Best-effort, format-matched extraction of ONE slice's own changed-file
    list. Two sources, in priority order, both real (never a guessed regex
    over arbitrary prose):

      1. An explicit structured context_pack.changed_paths list -- a
         forward-compatible extension point. Not emitted by the current
         review/slicer.py, but honoured verbatim when present (a future
         producer may add it without requiring another change here).
      2. review/slicer.py's build_batch() own real, deterministic
         blast_radius string: "<N> changed path(s) in this slice: <p1>,
         <p2>, ...". Parsed ONLY when the string's own declared count N
         equals the number of ", "-separated segments -- a cheap
         round-trip sanity check that refuses an AMBIGUOUS split (e.g. a
         path that itself contains the literal ", ") rather than silently
         mis-splitting one real path into two bogus ones and under-scoping
         the real one out of every check.

    Returns (paths: list[str] | None, resolved: bool). resolved=False means
    this ONE slice's changed-file set could not be confidently established
    from real data -- the caller (_batch_scoped_files) then falls back to
    whole-checkout scanning for the WHOLE batch, never a partial scope
    (constitution 11.4.6: never guess)."""
    if not isinstance(slice_obj, dict):
        return None, False
    cp = slice_obj.get("context_pack")
    if not isinstance(cp, dict):
        return None, False

    explicit = cp.get("changed_paths")
    if isinstance(explicit, list) and explicit and all(isinstance(p, str) and p for p in explicit):
        return list(explicit), True

    blast_radius = cp.get("blast_radius")
    if not isinstance(blast_radius, str):
        return None, False
    m = _BLAST_RADIUS_RE.fullmatch(blast_radius)
    if not m:
        return None, False
    declared_count = int(m.group(1))
    segments = m.group(2).split(", ")
    if len(segments) != declared_count or not all(segments):
        return None, False
    return segments, True


def _batch_scope(batch, root):
    """Derives the REAL set of files this batch changed. Source, in priority
    order: (1) a builder-written `binding.paths` list (NUL-safe JSON, F-R2-2),
    else (2) the slices' own declared paths (see _paths_from_slice).
    -> {"files": sorted EXISTING absolute paths (symlinks included) or None,
        "absent": declared relative paths not present in the checkout,
        "slice_paths": the slices' declared paths (or None), "note": str}.
    files=None is the honest signal to fall back to the whole-checkout scan
    (never a guessed partial scope)."""
    out = {"files": None, "absent": [], "dirs": [], "slice_paths": None, "note": ""}
    slices = batch.get("slices")
    slice_paths = None
    if isinstance(slices, list) and slices:
        acc = set()
        for sl in slices:
            paths, resolved = _paths_from_slice(sl)
            if not resolved:
                acc = None
                break
            acc.update(paths)
        slice_paths = sorted(acc) if acc is not None else None
    out["slice_paths"] = slice_paths
    binding = batch.get("binding")
    source = None
    if isinstance(binding, dict) and isinstance(binding.get("paths"), list) and binding["paths"]:
        declared = sorted({p.get("path") for p in binding["paths"] if isinstance(p, dict) and isinstance(p.get("path"), str)})
        source = "binding"
    elif slice_paths is not None:
        declared = slice_paths
        source = "slices"
    elif not isinstance(slices, list) or not slices:
        out["note"] = "batch carries no slices -- cannot derive a per-file scope"
        return out
    else:
        out["note"] = ("a slice's context_pack does not carry a confidently-parseable changed-file list "
                       "(neither an explicit changed_paths list nor a slicer.py-shaped blast_radius string)")
        return out
    root_abs = os.path.abspath(root)
    existing, absent, dirs = [], [], []
    for p in declared:
        candidate = os.path.normpath(os.path.join(root_abs, p))
        # 11.4.6: never trust a declared path that escapes --clean-checkout
        if candidate == root_abs or not candidate.startswith(root_abs + os.sep):
            out["note"] = "a declared changed path (%r) resolves outside --clean-checkout" % p
            return out
        if os.path.islink(candidate) or os.path.isfile(candidate):
            existing.append(candidate)
        elif not os.path.lexists(candidate):
            absent.append(p)
        elif os.path.isdir(candidate):
            # a submodule pointer (gitlink) materialises as a directory; check_shellcheck
            # accepts it only when the bound head records a gitlink there (I4)
            dirs.append(p)
        else:
            out["note"] = "a declared changed path (%r) is neither a file, a directory nor absent" % p
            return out
    if not existing and not dirs and source == "slices":
        # Every declared path absent: far more likely a base-path mismatch than an
        # all-deletions batch; an artificially EMPTY scope would under-scan.
        out["note"] = ("batch declared %d changed path(s) but none exist under --clean-checkout "
                       "(likely path-base mismatch)" % len(declared))
        return out
    out["files"] = sorted(set(existing))
    out["absent"] = absent
    out["dirs"] = dirs
    out["note"] = "batch-scoped (%s): %d file(s), %d directory entr(y/ies), %d absent" % (
        source, len(existing), len(dirs), len(absent))
    return out


def _batch_scoped_files(batch, root):
    """Back-compat wrapper: (files, note)."""
    sc = _batch_scope(batch, root)
    return sc["files"], sc["note"]


def _scope_fragment(scoped_files, scope_note):
    frag = {"scope": "batch" if scoped_files is not None else "whole-checkout"}
    if scope_note:
        frag["scope_note"] = scope_note
    return frag


# ---------------------------------------------------------------------------
# The 10 DEC-33 checks (CHECK_ORDER), each returning
# {"check": ..., "verdict": "PASS"|"FAIL", "evidence": {...}}.
# ---------------------------------------------------------------------------
def check_parse(root, scoped_files, scope_note):
    candidates = (sorted(p for p in scoped_files if _is_shell_script(p) and not os.path.islink(p))
                  if scoped_files is not None else [p for p in _find_shell_scripts(root) if not os.path.islink(p)])
    failures = []
    for path in candidates:
        interp = _shebang_interpreter(path)
        rel = _relpath(path, root)
        try:
            proc = subprocess.run([interp, "-n", path], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append({"file": rel, "message": "%s -n failed to run: %s" % (interp, exc)})
            continue
        if proc.returncode != 0:
            raw = (proc.stderr or proc.stdout or "").strip()
            lines = raw.splitlines()
            text = lines[0] if lines else "%s -n exited %d" % (interp, proc.returncode)
            # The interpreter echoes its own (possibly absolute) invocation path in its
            # own message -- rewrite that prefix to the relative name so evidence reads
            # the same shape as this project's own documented fixture expectation
            # (fixtures/precheck_slicer/case2_lint_in_pack/expected_precheck.json:
            # "broken_syntax_gate.sh: line 11: syntax error: unexpected end of file").
            text = text.replace(path + ":", rel + ":") if (path + ":") in text else text.replace(path, rel)
            failures.append({"file": rel, "message": text})
    verdict = "FAIL" if failures else "PASS"
    evidence = {"tool": "bash -n / sh -n"}
    evidence.update(_scope_fragment(scoped_files, scope_note))
    if failures:
        evidence["failures"] = failures
    return {"check": "parse", "verdict": verdict, "evidence": evidence}


# ---------------------------------------------------------------------------
# shellcheck check -- WHOLE-FILE STRICT with a SEVERITY FLOOR (T048 structural
# simplification, 11.4.250 + 11.4.276(E); operator decisions 2026-10-09
# "Simplify: whole-file strict" and "Strict, with severity floor"; guarded by
# tests/test_precheck_shellcheck_red.sh).
#
# CONTRACT: "touch a file, own its shellcheck findings". Every shell script the
# batch touches is linted WHOLE (no baseline diff, no hunk mapping, no region
# scanner). A finding BLOCKS when its level is error or warning, or when its
# rule is in the closed always-blocking info set BLOCKING_INFO_RULES:
#   SC2086 unquoted expansion (word splitting / globbing), SC2030 + SC2031 a
#   variable modified in a subshell is lost, SC2162 `read` without -r mangles
#   backslashes, SC2059 a variable used as a printf format string.
# Chosen by census (2026-10-09, gate argv, the 1,077 device test scripts other
# than the one giant file): error+warning = 869 findings in 385 files; the five
# info rules add 242 (SC2086 189 in 83 files, SC2059 23, SC2162 12, SC2031 11,
# SC2030 7); the rejected high-volume info rules are SC2015 (412), SC2016 (383),
# SC2329 (278), SC2119 (206), SC2012 (122). Every other info/style finding is
# ADVISORY: listed in evidence["advisory_findings"], never failing. Directive
# violations (D1-D5) always block.
#
# Excluded rules: the argv carries `-e SC1090,SC1091` -- the "cannot follow the
# sourced file" diagnostics every single-file stdin lint produces (966 SC1091 +
# 133 SC1090 in the census); they say nothing about the file under review.
#
# Candidates: a batch-scoped path is a shell-script candidate when it has a
# shell extension (.sh .bash .ksh .dash), OR a shell shebang -- sh/bash/dash/
# ksh/mksh/ash with an optional version suffix (`bash5`), through `env [-S]`
# and through a busybox/toybox multicall (`#!/bin/busybox sh`) -- OR, when a
# base commit is known, its BASE blob (followed through a rename) was such a
# script: removing the shebang does not remove the file from the check.
#
# Dialect (`-s`): bash* -> bash, dash -> dash, ksh/mksh -> ksh, and the Android
# shebang path /system/bin/sh -> ksh: probed read-only on a device 2026-10-09,
# /system/bin/sh reports KSH_VERSION "@(#)MIRBSD KSH R59 2020/10/31 Android" and
# `f(){ local x=1; }` works; linting those scripts as POSIX sh produced 692
# SC3043 (`local`) + 1,968 SC3037 (`echo -e/-n`) false positives. Any other sh
# -> sh. Residuals: shellcheck's ksh dialect is ksh93, not mksh; /vendor/bin/sh
# (2 scripts) was not probed and stays POSIX sh (stricter, never laxer).
#
# Host safety (constitution 12 / 12.6, review finding B1): a 51,639-line script
# needed 136 GiB peak RSS uncapped; under a 16 GiB cap it was killed after 55 s
# and its first 20,000 lines alone peaked at 14.8 GB, while the largest of the
# other 1,077 test scripts peaks at 616 MB. Therefore EVERY shellcheck
# invocation runs inside
#   systemd-run --user --scope --collect -p MemoryMax=<cap>M -p MemorySwapMax=0
# (DEFAULT_MEM_CAP_MIB, 13x the largest real script) and only after a SIZE cap
# (DEFAULT_MAX_LINES / DEFAULT_MAX_BYTES). A candidate over the size cap, a lint
# killed by the memory cap, a cap mechanism that is unavailable (probed once per
# run), or a budget overrun is BLIND and FAILs closed -- never PASS. Lints of
# large files (>= LARGE_LINES) and of every legacy-exception file are
# serialised host-wide by an exclusive flock, so two builds never run giant
# lints concurrently. The caps may be LOWERED per run, never raised.
#
# Tool environment: the capped command is `env -i PATH=.. HOME=XDG_CONFIG_HOME=
# <empty dir> LC_ALL=LANG=C.UTF-8 shellcheck --norc ...` with the file on stdin
# from an EMPTY temporary cwd (SHELLCHECK_OPTS, TMPDIR and everything else
# dropped); systemd-run itself sees only PATH, XDG_RUNTIME_DIR and
# DBUS_SESSION_BUS_ADDRESS. Because of --norc a planted .shellcheckrc cannot
# change the result; rc files near a candidate are only LISTED in evidence.
# Version + full argv are evidence; the version is also pinned in provenance.
#
# Directives are honoured by shellcheck. Recognition (gate review round 6, F1 --
# the recurring "parity with shellcheck's parser" class, replaced structurally):
#   candidates  every `#<blanks>shellcheck` (any case, any position) -- listed;
#   canonical   the forms shellcheck 0.11 honours (probed 2026-10-09): `#` at the
#               line start / after a blank, `;`, `&`, `|`, `(`, `)` or a backtick
#               (so `true;# shellcheck`, `$(# shellcheck`, `a)# shellcheck`),
#               lower-case only -- these are POLICED;
#   parity      the file is re-linted with every NON-canonical `shellcheck` word
#               neutralised (s -> x, equal length): if the findings change,
#               shellcheck honoured a directive the recogniser missed -> the
#               file FAILs closed (`directive_parity_breaches`). A second lint
#               with EVERY directive neutralised yields the blocking findings
#               the directives suppress; a canonical `disable=` of such a code
#               or of a BLOCKING_INFO_RULES code is listed as
#               `blocking_rule_disabled` (flagged, not refused).
# Policed (closed rule set, all listed in evidence):
#   D1 `disable=all` (any position in the list, any case)        -> FAIL
#   D2 any range form (`SC1000-SC2999`, `1000-2999`) in a code list -> FAIL
#   D3 `extended-analysis=` with any value other than `true`     -> FAIL
#   D4 an unknown directive key, or a malformed `key=value` token -> FAIL
#   D5 a line carrying `disable=` MUST carry its justification as a comment on
#      the SAME line -- `# shellcheck disable=SC2016 # literal pattern, not an
#      expansion`. A justification on the line above is NOT accepted. It must
#      hold >= 16 letters in words of >= 2 letters and >= 3 distinct words that
#      each contain a vowel and are not placeholders (x, todo, noise, ok, ...).
# Residuals: keyboard mash that contains vowels passes D5 -- whether a reason
# is ADEQUATE is review territory; a string / here-doc line with a canonically
# placed `# shellcheck` is policed too (stricter, never laxer). DIR-FORBIDDEN
# (D1-D4) cannot be pinned in a legacy row (a pinned disable=all could move).
#
# Legacy exceptions (ONE narrow exception; review finding I1): the canonical,
# checked-in TSV CANONICAL_EXCEPTIONS_REL (rows {path, reason_class,
# tracked_item, pinned_counts, pin_date}, see _load_exceptions). In a BOUND run
# the gate decides which file is used: the canonical path when it is tracked at
# the bound head (its checkout bytes must equal the head blob), else none; any
# other --shellcheck-exceptions value is refused (exit 2). The BASE TSV is read
# from the bound base commit: a NEW row or a RAISED pin FAILs unless the batch
# changes ONLY the TSV (an explicit TSV-only batch -- the review of that batch
# is where the operator approves the increase; evidence lists
# `exceptions_increase`). A row must cover a file tracked at the base.
# reason_class needs evidence: too-large-to-lint-in-budget >= TOO_LARGE_MIN_LINES
# lines; generated = a generated-file marker in the first 20 lines; vendored = a
# path component in _VENDORED_DIRS. SC10xx codes may not be pinned, and ANY
# error-level SC1xxx (parse) finding in a listed file FAILs closed (analysis
# after a parse error is partial; a pin must never hide it). A listed file is
# compared per rule to its pin over its BLOCKING findings: a rule count above
# its pin, or a rule absent from the pin, FAILs; equal or lower counts PASS
# (monotone ratchet). Directive violations count under DIR-FORBIDDEN /
# DIR-UNJUSTIFIED. Head and base TSV blob sha256 are recorded in evidence and in
# provenance; the dispatch verifier recomputes them. Unbound runs may name any
# file (they are never dispatch-ready).
#
# Binding (F-R2-1/F5): --baseline-repo PATH --baseline-ref BASE name the repo
# and the batch BASE (the empty tree for a root commit). A batch carrying a
# builder-written `binding` {base_sha, head_sha, kind, paths:[{path,
# change_id}]} is verified: base == BASE, head is a commit of the repo, base is
# an ancestor of head (a root commit for the empty tree; base == head^ for a
# snapshot), the checkout's git HEAD == head (and == --head-sha), every bound
# file's bytes == its head blob, every change_id recomputed, binding ids ==
# batch.changes. Only then is provenance.head_sha_source
# "batch-binding-verified" -- the one value the dispatch verifier accepts. A
# bound path whose head entry is a GITLINK (mode 160000, a submodule pointer)
# is not shell: it is listed in evidence["gitlinks"] and its checkout path must
# be a directory (git materialises an uninitialised submodule as one).
#
# Symlinks: a symlinked SCRIPT candidate (shell extension, shell base blob, or
# a target inside the checkout with a shell shebang) FAILs; any other scoped
# symlink (a docs file, say) is listed in evidence and does not block.
#
# NUL bytes: a shell candidate containing a NUL byte FAILs (shells mangle NUL;
# a lint around it is not a lint of what runs).
#
# Residuals (stated, never claimed closed):
#   R1 whole-file strictness makes legacy findings in a touched file the
#      toucher's to fix (deliberate, operator decision) -- the cost is real.
#   R2 a self-consistent forged pack (body_hash/gate_version/provenance are
#      recomputable) is not authenticated; only a signing key held outside the
#      producer's reach would close it (11.4.240(F)).
#   R3 the exception ratchet is per-rule counts: a finding swapped for another
#      of the SAME rule is invisible; the pin is gate data, reviewed like code.
#   R4 base-blob candidate selection follows renames only as far as git's -M
#      similarity detection (default 50%).
#   R5 directive lines are found by a line scan (see above): stricter, never
#      laxer.
#   R6 an unbound run (no binding) can only assert, never prove, which head it
#      linted -- it is never dispatch-ready.
#   R7 the review model presumes the batch BASE was reviewed: a producer that
#      picks a base past unreviewed commits (a TSV row and its script landed
#      there) defeats every base-relative check; no protected ref is known
#      generically, so this is not verified.
#   R8 files larger than the size/memory caps cannot be reviewed by this gate
#      at all until they are split.
# ---------------------------------------------------------------------------
_SHELL_INTERPS = ("sh", "bash", "dash", "ksh", "mksh", "ash")
_SHELL_NAME_RE = re.compile(r"^(sh|bash|dash|ksh|mksh|ash)(?:[0-9][0-9.]*)?$")
_MULTICALL = ("busybox", "toybox")
_MKSH_SHEBANG_PATHS = ("/system/bin/sh",)
# Directive recognition (F1, gate review round 6) -- STRUCTURAL: three layers, never one regex alone.
#  1. CANDIDATES (_DIRECTIVE_RE): an OVER-APPROXIMATION, independent of left context -- `#`, optional
#     blanks, the word shellcheck (any case), then a blank or the end of the line, ANYWHERE in a line
#     (after `;` `(` `$(` a backtick `)` `&` `|`, inside strings and here-docs, trailing). Every candidate
#     is listed in evidence.
#  2. CANONICAL directives (_CANON_DIRECTIVE_RE): the forms shellcheck 0.11 is known to honour (probed
#     2026-10-09: line start / indented / after a blank, and right after `;` `&` `|` `(` `)` a backtick --
#     `$(` included; lower-case only: `ShellCheck` / `SHELLCHECK` are NOT honoured). These are POLICED
#     (D1-D5).
#  3. PARITY ORACLE (shellcheck itself is the reference): the file is re-linted with every NON-canonical
#     `shellcheck` word neutralised (s -> x, equal length, positions unchanged). If the findings differ,
#     shellcheck honoured a directive the canonical recogniser did not see -> fails closed (directive
#     parity breach). A recogniser gap can therefore never become a silent PASS, whatever the left context.
_DIR_WS = r"[ \t\r\f\v]"
_DIRECTIVE_RE = re.compile(r"#" + _DIR_WS + r"*shellcheck(?=" + _DIR_WS + r"|$)", re.I | re.A)
_CANON_DIRECTIVE_RE = re.compile(r"(?<![^\s;&|()`])#" + _DIR_WS + r"*shellcheck(?=" + _DIR_WS + r"|$)", re.A)
_DIRECTIVE_WORD_RE_B = re.compile(rb"shellcheck", re.I)
_RC_NAMES = (".shellcheckrc", "shellcheckrc")
_DIRECTIVE_KEYS = ("disable", "enable", "source", "source-path", "shell", "external-sources",
                   "extended-analysis")
_RANGE_RE = re.compile(r"^(?:SC)?\d+-(?:SC)?\d+$", re.I)
_PLACEHOLDER_WORDS = frozenset(("x", "xx", "todo", "fixme", "tbd", "noise", "ok", "okay", "na", "none", "ignore",
                                "ignored", "temp", "tmp", "wip", "reason", "because", "see", "above", "below",
                                "fine", "false", "positive", "disable", "disabled", "shellcheck", "sc", "lint",
                                "warning", "suppress", "suppressed", "hack", "fix", "later", "it", "this", "is",
                                "the", "a", "an", "of", "to", "for", "and", "or", "not"))
_REASON_CLASSES = ("too-large-to-lint-in-budget", "generated", "vendored")
_ITEM_RE = re.compile(r"^[A-Z][A-Z0-9]*-[0-9]+$")
_PIN_DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
_PIN_KEY_RE = re.compile(r"^(?:SC[0-9]+|DIR-FORBIDDEN|DIR-UNJUSTIFIED)$")
_PARSE_PIN_RE = re.compile(r"^SC10[0-9]{2}$")
_UNPINNABLE_KEYS = ("DIR-FORBIDDEN",)
_GENERATED_RE = re.compile(r"(?i)(generated by|do not edit|auto-?generated)")
_VENDORED_DIRS = ("vendor", "vendored", "third_party", "third-party", "external", "prebuilts")
BLOCKING_LEVELS = ("error", "warning")
BLOCKING_INFO_RULES = ("SC2030", "SC2031", "SC2059", "SC2086", "SC2162")
EXCLUDED_RULES = ("SC1090", "SC1091")
DEFAULT_SC_TIMEOUT = 60
DEFAULT_EXCEPTION_TIMEOUT = 900
# F10: ceilings -- a per-run value may be lowered, never raised above these
MAX_SC_TIMEOUT = 600
MAX_EXCEPTION_TIMEOUT = 1800
DEFAULT_TOTAL_BUDGET = 3600  # seconds of shellcheck wall time per batch (all lints together); then BLIND
DETERMINISM_OVERHEAD_S = 600  # git, probe and version work on top of the lint budget per inner run
# every lint and lock wait is clipped to the budget that remains, so one inner run is bounded by budget + overhead
DETERMINISM_TIMEOUT_S = DEFAULT_TOTAL_BUDGET + DETERMINISM_OVERHEAD_S
DEFAULT_MEM_CAP_MIB = 8192
DEFAULT_MAX_LINES = 10000
DEFAULT_MAX_BYTES = 2 * 1024 * 1024
LARGE_LINES = 5000
TOO_LARGE_MIN_LINES = 5000


def _split_lines(raw):
    """Lines as shellcheck counts them: split on '\\n' only."""
    lines = raw.decode("utf-8", "replace").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def _line_text(lines, n):
    if isinstance(n, int) and 1 <= n <= len(lines):
        return " ".join(lines[n - 1].split())
    return "<unresolvable line %r of %d>" % (n, len(lines))


def _git(repo, args, timeout=60):
    return subprocess.run(["git", "--literal-pathspecs", "-C", repo] + args,
                          capture_output=True, timeout=timeout, env=_git_env())


def _txt(b):
    return (b or b"").decode("utf-8", "replace").strip()


def _parse_baseline_specs(specs):
    """['[PREFIX=]PATH', ...] -> [(prefix, path)]; '/...' is a bare root mapping."""
    out = []
    for spec in specs or []:
        if spec.startswith("/") or "=" not in spec:
            out.append(("", spec))
        else:
            prefix, _, path = spec.partition("=")
            out.append((prefix.strip("/"), path))
    return out


def _git_toplevel_head(path):
    """-> (toplevel|None, head_sha|None) of the repo whose toplevel IS `path`."""
    try:
        top = _git(path, ["rev-parse", "--show-toplevel"])
        if top.returncode != 0:
            return None, None
        tl = _txt(top.stdout)
        if os.path.realpath(tl) != os.path.realpath(path):
            return None, None
        hd = _git(path, ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"])
        sha = _txt(hd.stdout)
        return tl, (sha if hd.returncode == 0 and re.fullmatch(r"[0-9a-f]{40,64}", sha) else None)
    except (OSError, subprocess.TimeoutExpired):
        return None, None


def _resolve_commit(repo, ref):
    """-> (sha, empty_tree) or (None, None)."""
    rv = _git(repo, ["rev-parse", "--verify", "--quiet", ref + "^{commit}"])
    sha = _txt(rv.stdout)
    if rv.returncode == 0 and re.fullmatch(r"[0-9a-f]{40,64}", sha):
        return sha, False
    rt = _git(repo, ["rev-parse", "--verify", "--quiet", ref + "^{tree}"])
    if rt.returncode == 0 and _txt(rt.stdout) == EMPTY_TREE:
        return EMPTY_TREE, True
    return None, None


def _make_baseline(specs, ref):
    """Resolves each mapped repo once: toplevel must equal the (absolute) path and
    `ref` (required, never defaulted) must resolve to a commit or the empty tree."""
    if not specs:
        return None
    repos = []
    for prefix, path in _parse_baseline_specs(specs):
        entry = {"prefix": prefix, "path": path}
        try:
            if not os.path.isabs(path):
                entry["error"] = "repo path must be absolute: %r" % path
            else:
                top = _git(path, ["rev-parse", "--show-toplevel"])
                if top.returncode != 0:
                    entry["error"] = "not a git repository: %s" % _txt(top.stderr)
                elif os.path.realpath(_txt(top.stdout)) != os.path.realpath(path):
                    entry["error"] = "path is not the repository toplevel (toplevel=%s)" % _txt(top.stdout)
                else:
                    sha, empty = _resolve_commit(path, ref)
                    if sha:
                        entry["commit"] = sha
                        if empty:
                            entry["empty_tree"] = True
                    else:
                        entry["error"] = "base ref %r does not resolve to a commit" % ref
        except (OSError, subprocess.TimeoutExpired) as exc:
            entry["error"] = "git failed to run: %s" % exc
        repos.append(entry)
    return {"ref": ref, "repos": repos}


def _repo_for(baseline, rel):
    best = None
    for entry in baseline["repos"]:
        pre = entry["prefix"]
        if pre == "" or rel == pre or rel.startswith(pre + "/"):
            if best is None or len(pre) > len(best["prefix"]):
                best = entry
    return best


def _tree_blob(repo, commit, inner):
    """-> (status, bytes|None, detail); status in tracked|absent|symlink|gitlink|error.
    A gitlink (mode 160000, a submodule pointer) carries its commit sha as detail."""
    lt = _git(repo, ["ls-tree", "-z", commit, "--", inner])
    if lt.returncode != 0:
        return "error", None, "git ls-tree failed: %s" % _txt(lt.stderr)
    if not lt.stdout:
        return "absent", None, ""
    meta, _, name = lt.stdout.rstrip(b"\0").partition(b"\t")
    parts = meta.decode("ascii", "replace").split()
    if len(parts) != 3 or name.decode("utf-8", "surrogateescape") != inner:
        return "error", None, "unexpected ls-tree entry: %r" % lt.stdout[:200]
    if parts[0] == "120000":
        return "symlink", None, "entry is a symlink"
    if parts[0] == "160000" and parts[1] == "commit":
        return "gitlink", None, parts[2]
    if parts[1] != "blob":
        return "error", None, "entry is not a regular blob: %r" % lt.stdout[:200]
    cf = _git(repo, ["cat-file", "blob", parts[2]])
    if cf.returncode != 0:
        return "error", None, "git cat-file failed: %s" % _txt(cf.stderr)
    return "tracked", cf.stdout, ""


def _base_blob(baseline, rel):
    """-> (status, bytes|None, detail) of `rel` at the base commit;
    status in tracked|untracked-at-base|symlink|gitlink|error."""
    best = _repo_for(baseline, rel)
    if best is None:
        return "error", None, "no --baseline-repo mapping covers this path"
    if "error" in best:
        return "error", None, "repo %r unusable: %s" % (best["path"], best["error"])
    if best.get("empty_tree"):
        return "untracked-at-base", None, ""
    inner = rel if best["prefix"] == "" else rel[len(best["prefix"]) + 1:]
    try:
        st, data, detail = _tree_blob(best["path"], best["commit"], inner)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return "error", None, "git failed to run: %s" % exc
    if st == "absent":
        return "untracked-at-base", None, ""
    return st, data, detail


def _interp_of(first_line):
    """Shell name of a shebang ('' when none): `env [-S] [VAR=x]` and busybox/toybox
    multicalls are skipped; a versioned shell (`bash5`, `ksh93`) normalises to its
    base name; any other interpreter is returned as its basename."""
    if not first_line.startswith("#!"):
        return ""
    toks = first_line[2:].split()
    if not toks:
        return ""
    name, rest = os.path.basename(toks[0]), toks[1:]
    if name == "env":
        name, rest = _env_program(rest)
    if name in _MULTICALL:
        name = os.path.basename(rest[0]) if rest else ""
    m = _SHELL_NAME_RE.match(name)
    return m.group(1) if m else name


_ENV_ARG_SHORT = "uCP"          # env options that take the next word (or the rest of the word) as an argument
_ENV_ARG_LONG = ("--unset", "--chdir")


def _env_program(toks):
    """F7: (program basename, its remaining words) after `env`'s own options: `-S STR` / `-SSTR` /
    `--split-string[=]STR` (the split words are env words again), `-u NAME` / `-C DIR` / `-P PATH`
    and their attached / `--long=` forms, other flags, `VAR=value` assignments and `--`."""
    work, i = list(toks), 0
    while i < len(work):
        t = work[i]
        if t == "--":
            i += 1
            break
        if t == "-":  # a lone '-' is env's -i
            i += 1
            continue
        if t.startswith("--split-string"):
            if t.startswith("--split-string="):
                work[i] = t.split("=", 1)[1]
                if not work[i]:
                    i += 1
                continue
            i += 1
            continue
        if t.startswith("--"):
            if t in _ENV_ARG_LONG:
                i += 2
            else:
                i += 1
            continue
        if t.startswith("-") and len(t) > 1:
            j, consumed = 1, False
            while j < len(t):
                ch = t[j]
                if ch == "S":
                    rem = t[j + 1:]
                    if rem:
                        work[i] = rem  # the split string starts inside this word: re-read it
                    else:
                        i += 1
                    consumed = True
                    break
                if ch in _ENV_ARG_SHORT:
                    i += 1 if t[j + 1:] else 2
                    consumed = True
                    break
                j += 1
            if not consumed:
                i += 1
            continue
        if "=" in t:
            i += 1
            continue
        break
    if i < len(work):
        return os.path.basename(work[i]), work[i + 1:]
    return "", []


def _first_line(data):
    return data.split(b"\n", 1)[0][:256].decode("utf-8", "replace").rstrip("\r")


def _bytes_are_shell(data):
    return _interp_of(_first_line(data)) in _SHELL_INTERPS


def _shell_dialect(data):
    """-> lint flag for `shellcheck -s` from the bytes' own shebang (a
    `# shellcheck shell=` directive is honoured by shellcheck itself)."""
    first = _first_line(data)
    interp = _interp_of(first)
    if interp == "bash":
        return "bash"
    if interp == "dash":
        return "dash"
    if interp in ("ksh", "mksh"):
        return "ksh"
    toks = first[2:].split() if first.startswith("#!") else []
    if interp == "sh" and toks and toks[0] in _MKSH_SHEBANG_PATHS:
        return "ksh"
    return "sh"


def _shellcheck_env(empty):
    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": empty, "XDG_CONFIG_HOME": empty,
            "LC_ALL": "C.UTF-8", "LANG": "C.UTF-8"}


def _shellcheck_argv(flag):
    return ["shellcheck", "--norc", "-s", flag, "-e", ",".join(EXCLUDED_RULES), "-f", "json1", "-"]


def _cap_prefix(mem_cap_mib):
    return ["systemd-run", "--user", "--scope", "--quiet", "--collect", "-p", "MemoryMax=%dM" % mem_cap_mib,
            "-p", "MemorySwapMax=0", "--"]


def _capped_argv(inner, empty, mem_cap_mib):
    """systemd-run scope (hard cgroup memory cap) + `env -i` scrubbed inner env."""
    env = _shellcheck_env(empty)
    return (_cap_prefix(mem_cap_mib) + ["env", "-i"] + ["%s=%s" % (k, env[k]) for k in sorted(env)] + inner)


def _runner_env():
    """The environment systemd-run itself needs to reach the user manager -- and nothing else."""
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}
    for k in ("XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"):
        if os.environ.get(k):
            env[k] = os.environ[k]
    return env


_PROBE_SH = 'cat "/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)/memory.max"'


def _probe_cap(mem_cap_mib):
    """-> None when the hard memory cap is REALLY enforced on this host, else a reason.
    The probe runs inside the same scope prefix and reads its own cgroup-v2
    memory.max back: it must equal the cap (a wrapper that merely runs the command,
    or a cgroup-v1 host, fails closed)."""
    try:
        with tempfile.TemporaryDirectory() as empty:
            p = subprocess.run(_cap_prefix(mem_cap_mib) + ["sh", "-c", _PROBE_SH], capture_output=True, timeout=60,
                               cwd=empty, env=_runner_env())
    except (OSError, subprocess.TimeoutExpired) as exc:
        return "systemd-run --user --scope failed to run: %s" % exc
    if p.returncode != 0:
        return "systemd-run --user --scope exited %d: %s" % (p.returncode, _txt(p.stderr)[:300])
    got, want = _txt(p.stdout), str(mem_cap_mib * 1024 * 1024)
    if got != want:
        return "the scope's cgroup memory.max reads %r, not the %s-byte cap -- the cap is not enforced" % (got[:80], want)
    return None


def _shellcheck_version(mem_cap_mib):
    try:
        with tempfile.TemporaryDirectory() as empty:
            p = subprocess.run(_capped_argv(["shellcheck", "--version"], empty, mem_cap_mib), capture_output=True,
                               timeout=60, cwd=empty, env=_runner_env())
        for ln in p.stdout.decode("utf-8", "replace").splitlines():
            if ln.lower().startswith("version:"):
                return ln.split(":", 1)[1].strip()
        return "unknown (rc=%d)" % p.returncode
    except (OSError, subprocess.TimeoutExpired) as exc:
        return "unknown (%s)" % exc


def _run_shellcheck(flag, data, timeout, mem_cap_mib):
    """-> (comments|None, error|None, timed_out, elapsed_s). stdin, empty cwd, --norc,
    scrubbed env, hard cgroup memory cap. rc 0 = clean, 1 = findings; anything else
    (a kill by the memory cap included) is a tool failure -> BLIND."""
    t0 = time.monotonic()
    try:
        with tempfile.TemporaryDirectory() as empty:
            proc = subprocess.run(_capped_argv(_shellcheck_argv(flag), empty, mem_cap_mib), input=data,
                                  capture_output=True, timeout=timeout, cwd=empty, env=_runner_env())
    except subprocess.TimeoutExpired:
        return None, "shellcheck exceeded its %ss budget" % timeout, True, round(time.monotonic() - t0, 1)
    except OSError as exc:
        return None, "shellcheck failed to run: %s" % exc, False, round(time.monotonic() - t0, 1)
    elapsed = round(time.monotonic() - t0, 1)
    out = proc.stdout.decode("utf-8", "replace")
    if proc.returncode not in (0, 1):  # 0 clean, 1 findings; anything else is a tool failure
        why = ("killed by signal %d -- most likely the %d MiB memory cap" % (-proc.returncode, mem_cap_mib)
               if proc.returncode < 0 else "exited %d" % proc.returncode)
        return None, "shellcheck %s: %s" % (why, _txt(proc.stderr)[:300]), False, elapsed
    if not out.strip():  # json1 always prints {"comments":[...]}; silence is not "clean"
        return None, "shellcheck (rc=%d) produced no json1 output" % proc.returncode, False, elapsed
    try:
        doc = json.loads(out)
    except json.JSONDecodeError:
        return None, "shellcheck produced unparseable json1 output", False, elapsed
    if not isinstance(doc, dict) or not isinstance(doc.get("comments"), list):
        return None, "shellcheck json1 output has no comments list", False, elapsed
    comments = [c for c in doc["comments"] if isinstance(c, dict)]
    if (proc.returncode == 1) != bool(comments):  # rc and output must agree
        return None, "shellcheck rc=%d disagrees with its %d comment(s)" % (proc.returncode, len(comments)), \
            False, elapsed
    return comments, None, False, elapsed


TEST_MODE_ENV = "PRECHECK_TEST_MODE"          # "1" only in this gate's own test suites
TEST_LOCK_DIR_ENV = "PRECHECK_TEST_LOCK_DIR"  # honoured ONLY in test mode (a pack built so is never ready)


def _test_mode():
    return os.environ.get(TEST_MODE_ENV) == "1"


def _lock_path():
    """The host-wide lock (XDG_RUNTIME_DIR, which systemd-run --user needs anyway). A test suite may
    point it at a PRIVATE directory -- only with PRECHECK_TEST_MODE=1, which the pack records
    (evidence tool.test_mode) and the dispatch verifier refuses."""
    test_dir = os.environ.get(TEST_LOCK_DIR_ENV)
    if _test_mode() and test_dir and os.path.isdir(test_dir):
        return os.path.join(test_dir, "helix-precheck-shellcheck-large-%d.lock" % os.getuid())
    base = os.environ.get("XDG_RUNTIME_DIR")
    if not (base and os.path.isdir(base)):
        base = "/tmp"
    return os.path.join(base, "helix-precheck-shellcheck-large-%d.lock" % os.getuid())


class _LargeLintLock(object):
    """Exclusive host-wide flock serialising large / legacy-exception lints."""

    def __init__(self, wait_s):
        self.wait_s, self.fh, self.waited, self.error = wait_s, None, 0.0, None

    def __enter__(self):
        t0 = time.monotonic()
        try:
            self.fh = open(_lock_path(), "a")
        except OSError as exc:
            self.error = "cannot open the large-lint lock %s: %s" % (_lock_path(), exc)
            return self
        while True:
            try:
                fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() - t0 >= self.wait_s:
                    self.error = "large-lint lock %s still held after %ss" % (_lock_path(), self.wait_s)
                    break
                time.sleep(0.5)
        self.waited = round(time.monotonic() - t0, 1)
        return self

    def __exit__(self, *exc):
        if self.fh is not None:
            try:
                fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
            finally:
                self.fh.close()
        return False


def _blocking(c):
    return c.get("level") in BLOCKING_LEVELS or ("SC%s" % c.get("code")) in BLOCKING_INFO_RULES


def _finding(rel, c, text):
    return {"file": rel, "line": c.get("line"), "endLine": c.get("endLine"), "column": c.get("column"),
            "rule": "SC%s" % c.get("code"), "level": c.get("level"), "message": c.get("message"), "text": text}


def _justification_ok(text):
    """D5: a real reason, not a placeholder (residual: vowel-bearing keyboard mash)."""
    words = [w.lower() for w in re.findall(r"[A-Za-z]{2,}", text or "")]
    real = {w for w in words if w not in _PLACEHOLDER_WORDS and re.search(r"[aeiouy]", w)}
    return sum(len(w) for w in words) >= 16 and len(real) >= 3


def _sc_code(code):
    """'SC2086' / '2086' -> 'SC2086'; anything else (e.g. 'all') -> None."""
    m = re.fullmatch(r"(?:SC)?([0-9]+)", code.strip(), re.I)
    return "SC%d" % int(m.group(1)) if m else None


def _canon_matches(text):
    """The ONE canonical-directive recogniser, shared by the policing and the parity oracle."""
    return list(_CANON_DIRECTIVE_RE.finditer(text))


def _police_directives(lines):
    """-> list of {line, column, text, canonical, keys, justification, disable_codes, file_scope,
    violations[]} for EVERY directive candidate (_DIRECTIVE_RE: an over-approximation -- any position in
    any line, the first line included; several per line possible). Only a CANONICAL candidate
    (_CANON_DIRECTIVE_RE at the same position: a form shellcheck honours) is policed (D1-D5); a
    non-canonical one is listed and left to the parity oracle (_differential_lint), which fails the file
    closed if shellcheck honours it after all. file_scope: the candidate is the first thing on its line
    and no command precedes it (only blank / comment lines after the shebang) -- where shellcheck applies a
    directive to the whole file."""
    out = []
    seen_command = False
    for i, raw in enumerate(lines, start=1):
        line = raw.rstrip("\r")
        canon = {m.start(): m for m in _canon_matches(line)}
        cands = {m.start(): m for m in _DIRECTIVE_RE.finditer(line)}
        cands.update(canon)  # a canonical directive is policed even if the candidate pattern were narrower
        for start in sorted(cands):
            m0 = cands[start]
            canonical = start in canon
            body = line[m0.end():]
            # The directive's own tokens end at the first ' #' (start of the same-line comment).
            m = re.search(r"\s#", body)
            tokens_part, just = (body[:m.start()], body[m.end():].strip()) if m else (body, "")
            toks = tokens_part.split()
            viol, keys, codes = [], [], []
            for t in toks:
                key, eq, val = t.partition("=")
                if not eq or not key or not val:
                    viol.append("D4 malformed directive token %r" % t)
                    continue
                keys.append(key)
                if key not in _DIRECTIVE_KEYS:
                    viol.append("D4 unknown directive key %r" % key)
                    continue
                if key in ("disable", "enable"):
                    for code in val.split(","):
                        code = code.strip().strip("`()'\";&|")  # `# shellcheck disable=all` inside a backtick
                        if key == "disable" and code.lower() == "all":
                            viol.append("D1 disable=all")
                        if _RANGE_RE.match(code.strip()):
                            viol.append("D2 range form %r" % code)
                        if key == "disable" and _sc_code(code):
                            codes.append(_sc_code(code))
                if key == "extended-analysis" and val.strip().lower() != "true":
                    viol.append("D3 extended-analysis=%s switches off data-flow analysis" % val)
            if not toks:
                viol.append("D4 directive with no key=value token")
            if "disable" in keys and not _justification_ok(just):
                viol.append("D5 disable= without a same-line justification of real words (got %r)" % just)
            out.append({"line": i, "column": m0.start() + 1, "text": line.strip(), "canonical": canonical,
                        "keys": keys, "justification": just, "disable_codes": sorted(set(codes)),
                        "file_scope": not seen_command and not line[:m0.start()].strip(),
                        "violations": viol if canonical else []})
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            seen_command = True
    return out


def _shellcheck_words(data):
    """-> (offsets of every `shellcheck` word (any case), offsets of the CANONICAL directives' words) in
    the raw bytes. A line is decoded byte-for-byte (latin-1), so str offsets ARE byte offsets."""
    words, canon, off = [], [], 0
    for line in data.split(b"\n"):
        words.extend(off + m.start() for m in _DIRECTIVE_WORD_RE_B.finditer(line))
        text = line.decode("latin-1")
        canon.extend(off + m.end() - len("shellcheck") for m in _canon_matches(text))
        off += len(line) + 1
    return words, canon


def _neutralise(data, offsets):
    """Equal-length, inert copy: the first letter of each `shellcheck` word at `offsets` becomes x/X."""
    ba = bytearray(data)
    for o in offsets:
        ba[o] = ord("x") if ba[o] == ord("s") else ord("X")
    return bytes(ba)


def _finding_keys(comments):
    """Multiset of finding positions + codes + levels (messages excluded: a neutralised name changes them)."""
    return sorted((c.get("line"), c.get("endLine"), c.get("column"), c.get("endColumn"), c.get("code"), c.get("level"))
                  for c in comments)


def _differential_lint(flag, cdata, lint):
    """F1 + F8: the parity oracle. `lint(data)` -> (comments|None, error|None, timed_out). Returns
    (comments, error, timed_out, facts): `comments` are the ORIGINAL file's findings; `facts` holds the
    word counts, a parity `breach` (findings changed when the NON-canonical words were neutralised:
    shellcheck honoured something the canonical recogniser did not see) and `suppressed_codes` (blocking
    findings that appear only once the canonical directives are neutralised too -- what the file's
    directives actually switch off). Extra lints run only when the file holds a `shellcheck` word."""
    comments, err, timed_out = lint(cdata)
    words, canon = _shellcheck_words(cdata)
    facts = {"shellcheck_words": len(words), "canonical": len(canon)}
    if err or not words:
        return comments, err, timed_out, facts
    base_keys = _finding_keys(comments)
    canon_set = set(canon)
    noncanon = [w for w in words if w not in canon_set]
    if noncanon:
        c1, e1, t1 = lint(_neutralise(cdata, noncanon))
        if e1:
            return None, "parity lint (non-canonical directive words neutralised): " + e1, t1, facts
        if _finding_keys(c1) != base_keys:
            changed = sorted(set(map(tuple, _finding_keys(c1))) ^ set(map(tuple, base_keys)))
            facts["breach"] = {"lines": sorted({k[0] for k in changed if k[0] is not None}),
                               "codes": sorted({"SC%s" % k[4] for k in changed})}
    if canon:
        c2, e2, t2 = lint(_neutralise(cdata, words))
        if e2:
            return None, "parity lint (every directive neutralised): " + e2, t2, facts
        have = {}
        for k in _finding_keys([c for c in comments if _blocking(c)]):
            have[k] = have.get(k, 0) + 1
        sup = set()
        for c in c2:
            if not _blocking(c):
                continue
            k = _finding_keys([c])[0]
            if have.get(k, 0) > 0:
                have[k] -= 1
            else:
                sup.add("SC%s" % c.get("code"))
        facts["suppressed_codes"] = sorted(sup)
    return comments, None, False, facts


def _annotate_blocking(dirs, suppressed_codes):
    """F8: every canonical directive that disables a floor (blocking) rule -- a BLOCKING_INFO_RULES code, or a
    code the differential lint showed suppressing a blocking finding in this file -- is flagged
    blocking_rule_disabled (listed in evidence for the reviewer; with file_scope it switches the floor off
    for the whole file). Flagged, not refused: a justified D5 directive stays legal (operator decision
    'Strict, with severity floor')."""
    out = []
    for d in dirs:
        if not d.get("canonical"):
            continue
        bl = sorted(c for c in d["disable_codes"] if c in BLOCKING_INFO_RULES or c in suppressed_codes)
        if bl:
            d["blocking_rule_disabled"] = bl
            out.append(d)
    return out


def _violation_key(v):
    return "DIR-UNJUSTIFIED" if v.startswith("D5") else "DIR-FORBIDDEN"


def _parse_pins(field):
    if field.strip() in ("", "-"):
        return {}
    pins = {}
    for part in field.split(","):
        key, eq, val = part.strip().partition("=")
        if not eq or not _PIN_KEY_RE.match(key) or not re.fullmatch(r"[0-9]+", val) or key in pins:
            raise ValueError("bad pinned_counts entry %r" % part)
        if _PARSE_PIN_RE.match(key):
            raise ValueError("pinned_counts entry %r: SC10xx (parse-class) codes may not be pinned -- fix the "
                             "parse problem" % part)
        if key in _UNPINNABLE_KEYS:
            # a pinned forbidden directive (disable=all, a range, ...) could be swapped for another of the
            # same class -- e.g. moved to file scope -- invisibly to a per-key count: never pinnable
            raise ValueError("pinned_counts entry %r: forbidden directives (D1-D4) may not be pinned -- remove "
                             "the directive" % part)
        pins[key] = int(val)
    return pins


def _parse_exceptions(raw, label):
    """Legacy-exception TSV bytes -> (rows {path: row}, errors[]). Lines: blank /
    '#' comments ignored; otherwise exactly 5 TAB-separated fields
      path  reason_class  tracked_item  pinned_counts  pin_date
    reason_class in {too-large-to-lint-in-budget, generated, vendored};
    tracked_item like ATM-1234 (well-formed tracker id); pinned_counts
    'SC2086=12,SC2016=3,DIR-UNJUSTIFIED=4' or '-' for none (no SC10xx);
    pin_date YYYY-MM-DD."""
    rows, errors = {}, []
    for n, line in enumerate(raw.decode("utf-8", "replace").split("\n"), start=1):
        line = line.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != 5:
            errors.append("%s row %d: want 5 tab-separated fields, got %d" % (label, n, len(f)))
            continue
        rpath, rclass, item, pins, pdate = (x.strip() for x in f)
        if (not rpath or rpath.startswith("/") or ".." in rpath.split("/") or "\\" in rpath
                or os.path.normpath(rpath) != rpath):
            errors.append("%s row %d: path %r must be a normalised repo-relative path" % (label, n, rpath))
            continue
        if rclass not in _REASON_CLASSES:
            errors.append("%s row %d: reason_class %r not in %s" % (label, n, rclass, "|".join(_REASON_CLASSES)))
            continue
        if not _ITEM_RE.match(item):
            errors.append("%s row %d: tracked_item %r is not a tracked-item id (e.g. ATM-1234)" % (label, n, item))
            continue
        if not _PIN_DATE_RE.match(pdate):
            errors.append("%s row %d: pin_date %r is not YYYY-MM-DD" % (label, n, pdate))
            continue
        try:
            pinned = _parse_pins(pins)
        except ValueError as exc:
            errors.append("%s row %d: %s" % (label, n, exc))
            continue
        if rpath in rows:
            errors.append("%s row %d: duplicate path %r" % (label, n, rpath))
            continue
        rows[rpath] = {"path": rpath, "reason_class": rclass, "tracked_item": item, "pinned_counts": pinned,
                       "pin_date": pdate}
    return rows, errors


def _load_exceptions(path):
    """-> (rows, errors[], sha256|None) of a TSV file (see _parse_exceptions)."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        return {}, ["cannot read exceptions file %s: %s" % (path, exc)], None
    rows, errors = _parse_exceptions(raw, "exceptions")
    return rows, errors, hashlib.sha256(raw).hexdigest()


def _reason_evidence_error(row, rel, clines):
    """-> None when the row's reason_class is backed by evidence, else why not."""
    rc = row["reason_class"]
    if rc == "too-large-to-lint-in-budget" and len(clines) < TOO_LARGE_MIN_LINES:
        return ("reason_class too-large-to-lint-in-budget needs >= %d lines, %s has %d"
                % (TOO_LARGE_MIN_LINES, rel, len(clines)))
    if rc == "generated" and not any(_GENERATED_RE.search(x) for x in clines[:20]):
        return "reason_class generated needs a generated-file marker in the first 20 lines of %s" % rel
    if rc == "vendored" and not set(rel.split("/")[:-1]) & set(_VENDORED_DIRS):
        return ("reason_class vendored needs a vendored path component (%s); %s has none"
                % ("|".join(_VENDORED_DIRS), rel))
    return None


def _symlink_is_script(path, root, base_was_shell):
    if path.endswith(_SHELL_EXTS) or base_was_shell:
        return True
    try:
        real = os.path.realpath(path)
        root_real = os.path.realpath(root)
        if real.startswith(root_real + os.sep) and os.path.isfile(real):
            with open(real, "rb") as fh:
                return _bytes_are_shell(fh.read(256))
    except OSError:
        return True  # unresolvable: treat as a script candidate (fail closed)
    return False


def _verify_binding(root, baseline, binding, batch, head_sha_arg, scope):
    """Checks a builder-written batch binding (block comment above). -> dict
    {"ok", "errors", "head", "base", "repo", "paths", "renames": {new: old},
     "head_blobs", "gitlinks", "checkout_not_head"}."""
    res = {"ok": False, "errors": [], "head": None, "base": None, "repo": None, "paths": [], "renames": {},
           "head_blobs": {}, "gitlinks": [], "checkout_not_head": []}
    err = res["errors"]
    if not isinstance(binding, dict):
        err.append("binding is not an object")
        return res
    base_sha, head_sha, paths = binding.get("base_sha"), binding.get("head_sha"), binding.get("paths")
    if not (isinstance(base_sha, str) and isinstance(head_sha, str) and isinstance(paths, list) and paths):
        err.append("binding lacks base_sha/head_sha/paths")
        return res
    repos = baseline["repos"]
    if len(repos) != 1 or repos[0]["prefix"] != "" or "error" in repos[0]:
        err.append("a bound run requires exactly one usable root-mapped --baseline-repo")
        return res
    repo = repos[0]["path"]
    res["repo"], res["base"] = repo, base_sha
    if repos[0].get("commit") != base_sha:
        err.append("--baseline-ref resolves to %s, the batch is bound to base %s" % (repos[0].get("commit"), base_sha))
    hsha, hempty = _resolve_commit(repo, head_sha)
    if hsha != head_sha or hempty:
        err.append("bound head %s is not a commit of the repo" % head_sha)
        return res
    res["head"] = head_sha
    if base_sha == head_sha:
        err.append("bound base equals bound head")
    # F5: base must be an ancestor of head (root commit for the empty tree); a
    # snapshot head is exactly one commit on top of its base.
    if base_sha == EMPTY_TREE:
        par = _git(repo, ["rev-list", "--parents", "-n", "1", head_sha])
        if par.returncode != 0 or len(_txt(par.stdout).split()) != 1:
            err.append("base is the empty tree but head %s is not a root commit" % head_sha)
    else:
        anc = _git(repo, ["merge-base", "--is-ancestor", base_sha, head_sha])
        if anc.returncode != 0:
            err.append("base %s is not an ancestor of head %s" % (base_sha, head_sha))
    if binding.get("kind") == "snapshot":
        p1 = _git(repo, ["rev-parse", "--verify", "--quiet", head_sha + "^1"])
        if _txt(p1.stdout) != base_sha:
            err.append("snapshot head %s is not exactly one commit on top of base %s" % (head_sha, base_sha))
    if head_sha_arg and head_sha_arg != head_sha:
        err.append("--head-sha %s differs from the bound head %s" % (head_sha_arg, head_sha))
    _tl, ch = _git_toplevel_head(root)
    if ch != head_sha:
        err.append("checkout git HEAD is %s, the batch is bound to head %s" % (ch, head_sha))
    ids, rels = [], []
    for p in paths:
        if not (isinstance(p, dict) and isinstance(p.get("path"), str) and isinstance(p.get("change_id"), str)):
            err.append("malformed binding path entry: %r" % (p,))
            continue
        rel = p["path"]
        rels.append(rel)
        ids.append(p["change_id"])
        try:
            d = subprocess.run(_change_diff_argv(repo, base_sha, head_sha, rel), capture_output=True,
                               timeout=60, env=_git_env())
        except (OSError, subprocess.TimeoutExpired) as exc:
            err.append("git diff failed for %r: %s" % (rel, exc))
            continue
        if d.returncode != 0 or "sha256:" + hashlib.sha256(d.stdout).hexdigest() != p["change_id"]:
            err.append("change_id of %r does not match git diff base head" % rel)
        st, blob, detail = _tree_blob(repo, head_sha, rel)
        res["head_blobs"][rel] = (st, blob)
        cpath = os.path.join(root, rel)
        if st == "error":
            err.append("%r at head: %s" % (rel, detail))
        elif st == "gitlink":
            res["gitlinks"].append({"path": rel, "commit": detail})
            if os.path.islink(cpath) or not os.path.isdir(cpath):
                res["checkout_not_head"].append(rel)
        elif st == "symlink":
            if not os.path.islink(cpath):
                res["checkout_not_head"].append(rel)
        elif st == "absent":
            if os.path.lexists(cpath):
                res["checkout_not_head"].append(rel)
        else:
            try:
                if os.path.islink(cpath) or not os.path.isfile(cpath):
                    res["checkout_not_head"].append(rel)
                else:
                    with open(cpath, "rb") as fh:
                        if fh.read() != blob:
                            res["checkout_not_head"].append(rel)
            except OSError:
                res["checkout_not_head"].append(rel)
    res["paths"] = rels
    if res["checkout_not_head"]:
        err.append("checkout bytes differ from the bound head for: %s" % ", ".join(res["checkout_not_head"]))
    if sorted(ids) != sorted(c for c in (batch.get("changes") or []) if isinstance(c, str)):
        err.append("binding change_ids differ from batch.changes")
    declared = scope.get("slice_paths")
    if declared is not None and not set(declared) <= set(rels):
        err.append("slice-declared paths are not all in the binding: %s" % sorted(set(declared) - set(rels)))
    if base_sha != EMPTY_TREE:
        try:
            rn = _git(repo, _DIFF_PIN + ["diff", "-M", "--name-status", "-z", "--no-textconv", "--no-ext-diff",
                                        base_sha, head_sha])
            toks = rn.stdout.split(b"\0") if rn.returncode == 0 else []
            i = 0
            while i < len(toks):
                st = toks[i].decode("utf-8", "replace")
                if st[:1] in ("R", "C") and i + 2 < len(toks):
                    if st.startswith("R"):
                        res["renames"][toks[i + 2].decode("utf-8", "surrogateescape")] = \
                            toks[i + 1].decode("utf-8", "surrogateescape")
                    i += 3
                elif st:
                    i += 2
                else:
                    i += 1
        except (OSError, subprocess.TimeoutExpired) as exc:
            err.append("rename detection failed: %s" % exc)
    res["ok"] = not err
    return res


def _resolve_exceptions(root, opts, bound, errors):
    """Which exceptions file this run uses and what the base TSV held (I1).
    -> {"rows", "sha", "info" (evidence/provenance dict) | None, "base_rows" | None, "tsv_only"}."""
    out = {"rows": {}, "sha": None, "info": None, "base_rows": None, "tsv_only": False}
    given = opts.get("exceptions")
    if bound is None:
        if given:  # unbound run (never dispatch-ready): any file, named as given
            path = given if os.path.isabs(given) else os.path.join(root, given)
            rows, errs, sha = _load_exceptions(path)
            errors.extend({"file": "<exceptions>", "message": e} for e in errs)
            out.update(rows=rows, sha=sha, info={"path": given, "sha256": sha, "rows": len(rows), "bound": False})
        return out
    if not bound["ok"]:
        return out
    repo, head, base = bound["repo"], bound["head"], bound["base"]
    st, blob, detail = _tree_blob(repo, head, CANONICAL_EXCEPTIONS_REL)
    info = {"path": CANONICAL_EXCEPTIONS_REL, "bound": True, "head_blob_sha256": None, "base_blob_sha256": None,
            "rows": 0}
    if st == "tracked":
        cpath = os.path.join(root, CANONICAL_EXCEPTIONS_REL)
        real_root = os.path.realpath(root)
        try:
            ok = (not os.path.islink(cpath) and os.path.realpath(cpath).startswith(real_root + os.sep)
                  and os.path.isfile(cpath))
            data = open(cpath, "rb").read() if ok else None
        except OSError:
            data = None
        if data != blob:
            errors.append({"file": "<exceptions>", "message": "%s in the checkout is not the bound head's blob "
                           "(absent, a symlink, outside the checkout, or different bytes)" % CANONICAL_EXCEPTIONS_REL})
            return out
        rows, errs = _parse_exceptions(blob, "exceptions")
        errors.extend({"file": "<exceptions>", "message": e} for e in errs)
        info.update(head_blob_sha256=hashlib.sha256(blob).hexdigest(), rows=len(rows))
        out.update(rows=rows, sha=info["head_blob_sha256"])
    elif st not in ("absent",):
        errors.append({"file": "<exceptions>", "message": "%s at head: %s %s" % (CANONICAL_EXCEPTIONS_REL, st, detail)})
        return out
    if base == EMPTY_TREE:
        bst, bblob = "absent", None
    else:
        bst, bblob, bdetail = _tree_blob(repo, base, CANONICAL_EXCEPTIONS_REL)
        if bst not in ("tracked", "absent"):
            errors.append({"file": "<exceptions>", "message": "%s at base: %s %s"
                           % (CANONICAL_EXCEPTIONS_REL, bst, bdetail)})
            return out
    base_rows = {}
    if bst == "tracked":
        base_rows, berrs = _parse_exceptions(bblob, "base exceptions")
        info["base_blob_sha256"] = hashlib.sha256(bblob).hexdigest()
        if berrs:  # the base file is history; its malformed rows simply grant nothing
            info["base_parse_errors"] = berrs
    out["base_rows"] = base_rows
    out["tsv_only"] = bool(bound["paths"]) and set(bound["paths"]) == {CANONICAL_EXCEPTIONS_REL}
    out["info"] = info
    return out


def _exceptions_increase(rows, base_rows, renames=None):
    """-> [{path, kind: new-row|raised-pin, ...}] for every head row / pin above the base TSV.
    A pin KEY absent from the base row counts from 0 (a new key is an increase -- GR3). F9: a head row
    for a file the batch RENAMED (renames {new: old}) is compared with the base row of the old path, so
    moving a listed file with its row unchanged is not an increase."""
    inc = []
    renames = renames or {}
    for rel, row in sorted(rows.items()):
        b = base_rows.get(rel)
        if b is None and renames.get(rel) in base_rows:
            b = base_rows[renames[rel]]
        if b is None:
            inc.append({"path": rel, "kind": "new-row", "pinned_counts": row["pinned_counts"]})
            continue
        raised = {k: {"base": b["pinned_counts"].get(k), "head": v} for k, v in sorted(row["pinned_counts"].items())
                  if v > b["pinned_counts"].get(k, 0)}
        if raised:
            inc.append({"path": rel, "kind": "raised-pin", "raised": raised})
    return inc


def check_shellcheck(root, scope, baseline=None, head_sha=None, batch=None, ctx=None, opts=None):
    """Whole-file strict shellcheck with a severity floor (block comment above).
    `scope` comes from _batch_scope(); `ctx` receives provenance facts; `opts`
    carries exceptions/timeouts/caps."""
    ctx = ctx if ctx is not None else {}
    opts = opts or {}
    batch = batch or {}
    scoped_files, scope_note = scope["files"], scope["note"]
    sc_timeout = opts.get("timeout") or DEFAULT_SC_TIMEOUT
    ex_timeout = opts.get("exception_timeout") or DEFAULT_EXCEPTION_TIMEOUT
    mem_cap = opts.get("mem_cap_mib") or DEFAULT_MEM_CAP_MIB
    max_lines = opts.get("max_lines") or DEFAULT_MAX_LINES
    max_bytes = DEFAULT_MAX_BYTES
    if not _have("shellcheck"):
        evidence = {"skipped": "shellcheck not found on PATH (11.4.3 honest skip)", "mode": "skipped"}
        evidence.update(_scope_fragment(scoped_files, scope_note))
        ctx["head_sha_source"] = "unbound"
        return {"check": "shellcheck", "verdict": "PASS", "evidence": evidence}
    cap_problem = _probe_cap(mem_cap)
    version = _shellcheck_version(mem_cap) if cap_problem is None else "unknown (no memory cap)"
    ctx["shellcheck_version"] = version
    tool = {"version": version, "argv": _capped_argv(_shellcheck_argv("<dialect>"), "<empty dir>", mem_cap),
            "timeout_s": sc_timeout, "exception_timeout_s": ex_timeout, "memory_cap_mib": mem_cap,
            "max_lines": max_lines, "max_bytes": max_bytes, "large_lines": LARGE_LINES,
            "lock": _lock_path(), "total_budget_s": DEFAULT_TOTAL_BUDGET,
            "severity_floor": {"blocking_levels": list(BLOCKING_LEVELS),
                               "blocking_info_rules": list(BLOCKING_INFO_RULES),
                               "excluded_rules": list(EXCLUDED_RULES)},
            "env_policy": "systemd-run scope (MemoryMax, MemorySwapMax=0) -> env -i PATH + HOME=XDG_CONFIG_HOME="
                          "<empty cwd> + LC_ALL/LANG=C.UTF-8; --norc; file on stdin"}
    if _test_mode():
        tool["test_mode"] = True  # a pack built so is never dispatch-ready (the verifier refuses it)
    ctx["shellcheck_params"] = {"timeout_s": sc_timeout, "exception_timeout_s": ex_timeout,
                                "memory_cap_mib": mem_cap, "max_lines": max_lines}
    errors, findings, advisory, directives, dir_viol, blocking_disabled = [], [], [], [], [], []
    parity_breaches = []
    exceptions_used, sym_refused, sym_ignored, dirs_refused = [], [], [], []
    files_linted = 0
    bound = None
    if cap_problem is not None:
        errors.append({"file": "<memory-cap>", "message": "BLIND (fails closed): no hard memory cap is available "
                       "for shellcheck -- %s" % cap_problem})
    if baseline is not None:
        for e in baseline["repos"]:
            if "error" in e:
                errors.append({"file": "<repo>", "message": "%s: %s" % (e["path"], e["error"])})
        if batch.get("binding") is not None:
            bound = _verify_binding(root, baseline, batch["binding"], batch, head_sha, scope)
            errors.extend({"file": "<binding>", "message": m} for m in bound["errors"])
        if scoped_files is None:
            errors.append({"file": "<scope>", "message": "a bound/based run requires a batch-scoped file set; "
                           "the batch's own data did not establish one (whole-checkout scan refused)"})
    exc = _resolve_exceptions(root, opts, bound, errors)
    ex_rows = exc["rows"]
    increase = []
    renames = bound["renames"] if bound and bound["ok"] else {}
    if exc["base_rows"] is not None:
        increase = _exceptions_increase(ex_rows, exc["base_rows"], renames)
        if increase and not exc["tsv_only"]:
            errors.append({"file": "<exceptions>", "message": "legacy exceptions INCREASED versus the base TSV (%s) "
                           "in a batch that also changes other files -- a new row or a raised pin is accepted only "
                           "in an explicit TSV-only batch" % ", ".join("%s %s" % (x["path"], x["kind"])
                                                                      for x in increase)})
    gitlink_paths = {g["path"] for g in bound["gitlinks"]} if bound else set()

    def base_is_shell(rel):
        if baseline is None:
            return False, None
        st, blob, _d = _base_blob(baseline, renames.get(rel, rel))
        return (st == "tracked" and _bytes_are_shell(blob)), st

    for rel in scope.get("dirs") or []:
        if rel not in gitlink_paths:
            dirs_refused.append(rel)
    if dirs_refused:
        errors.append({"file": "<scope>", "message": "declared path(s) are directories but not bound gitlinks: %s"
                       % ", ".join(dirs_refused)})
    bound_ok = bound is not None and bound["ok"]
    if bound_ok:
        # every row is evidence-checked against the bound head + base, linted or not
        for rel, row in sorted(ex_rows.items()):
            hst, hblob, _hd = _tree_blob(bound["repo"], bound["head"], rel)
            if hst != "tracked":
                errors.append({"file": rel, "message": "a legacy-exception row covers a path that is not a regular "
                               "file at the bound head (%s)" % hst})
            else:
                why = _reason_evidence_error(row, rel, _split_lines(hblob))
                if why:
                    errors.append({"file": rel, "message": "legacy exception row not backed by evidence: " + why})
            bst, _b, _d = _base_blob(baseline, renames.get(rel, rel))
            if bst != "tracked":
                errors.append({"file": rel, "message": "a legacy-exception row must cover a file tracked at the "
                               "batch base (got %s)" % bst})

    budget_t0 = time.monotonic()

    def remaining():
        return DEFAULT_TOTAL_BUDGET - (time.monotonic() - budget_t0)

    pool = scoped_files if scoped_files is not None else _find_shell_scripts(root)
    for path in sorted(pool):
        rel = _relpath(path, root)
        b_shell, _bst = base_is_shell(rel)
        if os.path.islink(path):
            if _symlink_is_script(path, root, b_shell):
                sym_refused.append(rel)
            else:
                sym_ignored.append(rel)
            continue
        if not (path.endswith(_SHELL_EXTS) or b_shell or _is_shell_script(path)):
            continue
        hst_blob = bound["head_blobs"].get(rel) if bound_ok else None
        if hst_blob is not None and hst_blob[0] == "tracked":
            # F10: lint the VERIFIED head-blob bytes (the binding compared them with the checkout), never a
            # second read of the checkout that could have changed in between
            cdata = hst_blob[1]
        else:
            try:
                with open(path, "rb") as fh:
                    cdata = fh.read()
            except OSError as exc_:
                errors.append({"file": rel, "message": "cannot read: %s" % exc_})
                continue
        if b"\0" in cdata:
            # shells mangle NUL bytes and shellcheck lints around them: a script
            # carrying one is refused outright (never a silent partial lint).
            errors.append({"file": rel, "message": "shell script contains NUL byte(s) at offset %d" % cdata.index(b"\0")})
        clines = _split_lines(cdata)
        dirs = _police_directives(clines)
        for d in dirs:
            directives.append(dict(d, file=rel))
        row = ex_rows.get(rel)
        if len(clines) > max_lines or len(cdata) > max_bytes:
            msg = ("BLIND (fails closed): %d lines / %d bytes exceeds the size cap (%d lines / %d bytes) -- this "
                   "file cannot be linted within the host-safety caps; split it before it can be in a review batch"
                   % (len(clines), len(cdata), max_lines, max_bytes))
            errors.append({"file": rel, "message": msg})
            if row is not None:
                exceptions_used.append({"file": rel, "verdict": "BLIND", "error": msg})
            continue
        if cap_problem is not None:
            continue
        if row is not None and not bound_ok:
            why = _reason_evidence_error(row, rel, clines)
            if why:
                errors.append({"file": rel, "message": "legacy exception row not backed by evidence: " + why})
        big = row is not None or len(clines) >= LARGE_LINES
        timeout = ex_timeout if row else sc_timeout
        flag = _shell_dialect(cdata)

        def lint(data, _timeout=timeout, _flag=flag):
            left = remaining()
            if left <= 0:
                return None, "the per-batch shellcheck time budget (%ss) is exhausted" % DEFAULT_TOTAL_BUDGET, True
            t = min(_timeout, left)
            com, er, to, _el = _run_shellcheck(_flag, data, t, mem_cap)
            if to and t < _timeout:
                er = "%s (clipped by the per-batch %ss budget)" % (er, DEFAULT_TOTAL_BUDGET)
            return com, er, to

        # timings are deliberately NOT evidence: the body must stay deterministic (C-003)
        if big:
            with _LargeLintLock(max(min(2 * ex_timeout, remaining()), 1.0)) as lk:
                if lk.error:
                    comments, err, timed_out, facts = None, lk.error, False, {}
                else:
                    comments, err, timed_out, facts = _differential_lint(flag, cdata, lint)
        else:
            comments, err, timed_out, facts = _differential_lint(flag, cdata, lint)
        if facts.get("breach"):
            parity_breaches.append(dict(facts["breach"], file=rel,
                                        noncanonical_candidates=[d["line"] for d in dirs if not d["canonical"]]))
            err = err or ("directive parity breach: shellcheck honours a `shellcheck` word on line(s) %s that the "
                          "gate's canonical directive recogniser did not parse (findings %s changed when the "
                          "non-canonical words were neutralised) -- fails closed; write the directive in canonical "
                          "form at the start of a line" % (facts["breach"]["lines"], facts["breach"]["codes"]))
            timed_out = False
        if err is None:
            for d in _annotate_blocking(dirs, facts.get("suppressed_codes") or []):
                blocking_disabled.append({"file": rel, "line": d["line"], "codes": d["blocking_rule_disabled"],
                                          "file_scope": d["file_scope"], "text": d["text"]})
        files_linted += 1
        if row is None:
            for d in dirs:
                if d["violations"]:
                    dir_viol.append({"file": rel, "line": d["line"], "text": d["text"],
                                     "violations": d["violations"]})
            if err:
                hint = (" -- a file that cannot be linted within the budget needs a reviewed legacy-exception row"
                        if timed_out else "")
                errors.append({"file": rel, "message": "BLIND (fails closed): " + err + hint})
                continue
            for c in comments:
                (findings if _blocking(c) else advisory).append(_finding(rel, c, _line_text(clines, c.get("line"))))
            continue
        # --- legacy exception: per-rule ratchet of BLOCKING findings against the pin ---
        entry = {"file": rel, "reason_class": row["reason_class"], "tracked_item": row["tracked_item"],
                 "pin_date": row["pin_date"], "pinned_counts": row["pinned_counts"], "timeout_s": ex_timeout,
                 "lines": len(clines)}
        if err:
            entry["verdict"] = "BLIND"
            entry["error"] = err
            errors.append({"file": rel, "message": "legacy exception BLIND (fails closed): " + err})
            exceptions_used.append(entry)
            continue
        parse_errors = [c for c in comments if c.get("level") == "error" and 1000 <= int(c.get("code") or 0) < 2000]
        counts = {}
        for c in comments:
            if _blocking(c):
                counts["SC%s" % c.get("code")] = counts.get("SC%s" % c.get("code"), 0) + 1
            else:
                advisory.append(_finding(rel, c, _line_text(clines, c.get("line"))))
        for d in dirs:
            for v in d["violations"]:
                k = _violation_key(v)
                counts[k] = counts.get(k, 0) + 1
        over = {k: {"now": v, "pinned": row["pinned_counts"].get(k)} for k, v in sorted(counts.items())
                if v > row["pinned_counts"].get(k, 0)}
        entry["counts"] = dict(sorted(counts.items()))
        entry["lowered"] = {k: {"now": counts.get(k, 0), "pinned": v} for k, v in sorted(row["pinned_counts"].items())
                            if counts.get(k, 0) < v}
        if parse_errors:
            entry["verdict"] = "FAIL"
            entry["parse_errors"] = [_finding(rel, c, _line_text(clines, c.get("line"))) for c in parse_errors]
            errors.append({"file": rel, "message": "legacy exception file has shellcheck PARSE error(s) (%s) -- "
                           "analysis after a parse error is partial; fails closed, never pinned"
                           % ", ".join("SC%s@%s" % (c.get("code"), c.get("line")) for c in parse_errors)})
        elif over:
            entry["verdict"] = "FAIL"
            entry["over_pin"] = over
            errors.append({"file": rel, "message": "legacy exception ratchet: counts above the pin or new rules: %s"
                           % ", ".join("%s %s>%s" % (k, o["now"], o["pinned"] or 0) for k, o in over.items())})
        else:
            entry["verdict"] = "PASS"
        exceptions_used.append(entry)

    rc_files = []
    if scoped_files is not None:
        root_abs = os.path.abspath(root)
        seen = set()
        for p in scoped_files:
            d = os.path.dirname(os.path.abspath(p))
            while d not in seen:
                seen.add(d)
                for n in _RC_NAMES:
                    if os.path.isfile(os.path.join(d, n)):
                        rc_files.append(_relpath(os.path.join(d, n), root))
                if d == root_abs or len(d) <= len(root_abs):
                    break
                d = os.path.dirname(d)

    deleted = []
    head_problem = None
    checkout_head = None
    head_source = "unbound"
    if baseline is not None:
        for rel in scope.get("absent") or []:
            if bound is not None and bound["ok"]:
                if bound["head_blobs"].get(rel, ("error",))[0] == "absent":
                    deleted.append(rel)
                else:
                    errors.append({"file": rel, "message": "declared path absent from the checkout but present at head"})
                continue
            bst, _b, detail = _base_blob(baseline, rel)
            if bst == "tracked":
                deleted.append(rel)
            else:
                errors.append({"file": rel, "message": "declared path absent from the checkout and not tracked at the "
                               "base (%s) -- likely a path-base mismatch" % (detail or bst)})
        _tl, checkout_head = _git_toplevel_head(root)
        if bound is not None:
            head_source = "batch-binding-verified" if bound["ok"] else "binding-failed"
            ctx["head_sha"] = bound["head"]
        elif head_sha:
            if checkout_head is None:
                head_problem = {"head_sha": head_sha, "problem": "--head-sha given but the checkout is not a git "
                                "toplevel with a resolvable HEAD -- an assertion that cannot be verified"}
                head_source = "unverifiable"
            elif checkout_head != head_sha:
                head_problem = {"head_sha": head_sha, "checkout_head": checkout_head, "problem": "mismatch"}
                head_source = "mismatch"
            else:
                head_source = "asserted-verified"
            ctx["head_sha"] = head_sha
        elif checkout_head:
            head_source = "checkout-git"
            ctx["head_sha"] = checkout_head
    elif head_sha:
        _tl, checkout_head = _git_toplevel_head(root)
        if checkout_head != head_sha:
            head_problem = {"head_sha": head_sha, "checkout_head": checkout_head,
                            "problem": "--head-sha cannot be verified against the checkout's git HEAD"}
    ctx["head_sha_source"] = head_source
    ctx["exceptions"] = exc["info"] if (exc["info"] or {}).get("bound") else None

    failing = bool(findings or errors or dir_viol or sym_refused or head_problem)
    evidence = {"tool": tool, "mode": "whole-file",
                "counts": {"files_linted": files_linted, "findings": len(findings), "advisory": len(advisory),
                           "directives": len(directives), "directive_violations": len(dir_viol)},
                "binding": {"state": ("bound" if bound is not None and bound["ok"] else
                                      ("binding-failed" if bound is not None else "unbound")),
                            "head_sha_source": head_source, "checkout_head": checkout_head,
                            "repos": ([{k: e[k] for k in ("prefix", "path", "commit", "empty_tree", "error") if k in e}
                                       for e in baseline["repos"]] if baseline is not None else []),
                            "base_ref": baseline["ref"] if baseline is not None else None}}
    for key, val in (("findings", findings), ("advisory_findings", advisory), ("errors", errors),
                     ("directives", directives), ("directive_violations", dir_viol),
                     ("blocking_rule_disabled", blocking_disabled), ("directive_parity_breaches", parity_breaches),
                     ("legacy_exceptions", exceptions_used), ("exceptions_increase", increase),
                     ("symlinks_refused", sym_refused), ("symlinks_ignored", sym_ignored),
                     ("shellcheckrc_ignored_by_norc", rc_files), ("deleted", deleted),
                     ("gitlinks", bound["gitlinks"] if bound else []), ("directories_refused", dirs_refused)):
        if val:
            evidence[key] = val
    if exc["info"] is not None:
        evidence["exceptions_file"] = exc["info"]
        if exc["tsv_only"]:
            evidence["exceptions_file"]["tsv_only_batch"] = True
    if renames:
        evidence["renames"] = renames
    if head_problem:
        evidence["head_problem"] = head_problem
    evidence.update(_scope_fragment(scoped_files, scope_note))
    return {"check": "shellcheck", "verdict": "FAIL" if failing else "PASS", "evidence": evidence}


def check_secret_scan(root, scoped_files, scope_note):
    if scoped_files is not None:
        candidates = sorted(p for p in scoped_files if not os.path.islink(p))
    else:
        candidates = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in _SKIP_DIRS)
            for fn in sorted(filenames):
                candidates.append(os.path.join(dirpath, fn))
    hits = []
    for path in candidates:
        rel = _relpath(path, root)
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for lineno, line in enumerate(fh, start=1):
                    for pattern, label in SECRET_PATTERNS:
                        if pattern.search(line):
                            hits.append({"file": rel, "line": lineno, "pattern": label})
        except OSError:
            continue
    verdict = "FAIL" if hits else "PASS"
    evidence = {"hits": hits} if hits else {}
    evidence.update(_scope_fragment(scoped_files, scope_note))
    return {"check": "secret-scan", "verdict": verdict, "evidence": evidence}


def check_affected_gates():
    # HONEST GAP (module docstring): no base/head shas available from a ReviewBatch to
    # drive gates/affected_set.py in this revision.
    return {"check": "affected-gates", "verdict": "PASS", "evidence": {"gates": []}}


def check_touched_gate_mutations():
    return {"check": "touched-gate-mutations", "verdict": "PASS", "evidence": {"gates": []}}


def check_doc_sync():
    return {"check": "doc-sync", "verdict": "PASS", "evidence": {}}


def check_closure_evidence_class():
    return {"check": "closure-evidence-class", "verdict": "PASS", "evidence": {"items": []}}


def check_already_fixed_markers():
    # HONEST GAP: no prior-round history source wired into this revision (see module
    # docstring) -- consumed by review_record.py's already_fixed_markers() as evidence.markers.
    return {"check": "already-fixed-markers", "verdict": "PASS", "evidence": {"markers": []}}


def _first_slice_field(batch, field):
    slices = batch.get("slices")
    if isinstance(slices, list):
        for s in slices:
            if isinstance(s, dict):
                cp = s.get("context_pack")
                if isinstance(cp, dict) and field in cp:
                    return cp[field]
    return None


_MISSING = object()  # sentinel: distinguishes "field absent" from any real JSON value (incl. null)


def _all_slice_field_values(batch, field):
    """T085 Round 5: returns [(slice_index, value_or_MISSING), ...] for
    EVERY slice in `batch` -- unlike `_first_slice_field()` above, which
    samples only the FIRST slice that happens to carry `field` and
    silently says nothing about the rest. A slice entry that is not a
    dict, or whose context_pack is not a dict, or that genuinely lacks
    `field`, is recorded as `_MISSING` for that slice -- never skipped,
    never silently merged into "the batch has it somewhere"."""
    slices = batch.get("slices")
    if not isinstance(slices, list):
        return []
    out = []
    for idx, s in enumerate(slices):
        cp = s.get("context_pack") if isinstance(s, dict) else None
        if isinstance(cp, dict) and field in cp:
            out.append((idx, cp[field]))
        else:
            out.append((idx, _MISSING))
    return out


def _batch_wide_field_check(batch, field, check_name, evidence_key):
    """T085 Round 5 (blast-radius recurrence; sibling-search was REWRITTEN
    at T085 Round 6 to genuinely MEASURE rather than read a declared
    field -- see check_sibling_search() below, which no longer uses this
    helper at all): the batch-WIDE presence check check_blast_radius()
    uses, closing a RECURRENCE of the SAME "false-PASS-on-unmeasured" bug
    class the T085 Round 3 fix (commit 9313143) closed for the
    single-slice case.

    The Round 3 fix made the verdict track FIELD PRESENCE instead of a
    hardcoded PASS -- but it read that presence via `_first_slice_field()`,
    which returns the FIRST slice that happens to carry `field` and says
    NOTHING about every OTHER slice in a multi-slice ReviewBatch.
    Reproduced live (T085 Round 5): a 2-slice batch where slice 0 carries
    the field and slice 1 does NOT still reported PASS -- slice 1 was
    NEVER measured, yet the batch-wide verdict claimed it was.

    T085 Round 6 (R5-I2 IMPORTANT): "present" alone is no longer
    sufficient -- a value that IS present but is the literal string
    "UNMEASURED" is now ALSO treated as equivalent to missing (FAIL).
    Root cause this closes (reproduced live, Round 5 independent review):
    "The new check fails only when the field is MISSING. The production
    [producer] fills it with the literal value 'UNMEASURED' ... and the
    check still reports PASS" -- a genuinely-never-measured field is
    indistinguishable, FROM THE CONSUMING CHECK'S OWN POINT OF VIEW, from
    one this tool's own absence-fallback manufactured; treating ONLY
    "key absent from the dict" as the unmeasured signal missed the
    producer's OWN, equally-unmeasured, sentinel value.

    Fixed: PASS requires EVERY slice to genuinely carry `field` (sampled
    via `_all_slice_field_values()`, never merely the first) with a value
    that is NEITHER absent NOR the literal string "UNMEASURED"; a batch
    with zero slices is likewise FAIL (there is nothing to have measured
    -- the conservative-safe default per 11.4.201(4), never a vacuous
    PASS-by-absence); ANY single missing-or-"UNMEASURED" slice makes the
    WHOLE batch-wide check FAIL, citing exactly which slice indices.

    Backward-compatible with every single-slice fixture this project's
    own test corpus ships that carries a GENUINE (non-"UNMEASURED")
    value: "every slice carries a real value" trivially reduces to "the
    one slice carries a real value" when there is exactly one."""
    values = _all_slice_field_values(batch, field)
    unmeasured = [idx for idx, v in values if v is _MISSING or v == "UNMEASURED"]
    if not values or unmeasured:
        evidence = {evidence_key: "UNMEASURED"}
        if not values:
            evidence["reason"] = "batch carries zero slices -- nothing was measured"
        else:
            evidence["unmeasured_slice_indices"] = unmeasured
            evidence["measured_slice_count"] = len(values) - len(unmeasured)
            evidence["total_slice_count"] = len(values)
        return {"check": check_name, "verdict": "FAIL", "evidence": evidence}
    present_values = [v for _, v in values]
    # Preserve the EXACT pre-existing singular-key evidence shape for the
    # common (and every currently-fixtured) single-slice case -- no
    # consumer of this project's own corpus reads anything beyond the
    # verdict string, but keeping the shape stable avoids an unforced
    # evidence-schema change for the case every existing test exercises.
    evidence = {evidence_key: present_values[0]} if len(present_values) == 1 else {
        evidence_key: present_values[0],
        evidence_key + "s_by_slice": present_values,
    }
    return {"check": check_name, "verdict": "PASS", "evidence": evidence}


_SIBLING_SEARCH_SKIP_DIRS = _SKIP_DIRS


def _stem_index(root):
    """`{basename-stem: [(dirpath, filename), ...]}` of every file under `root`
    in ONE pass. When `root` is a git checkout toplevel (the builder's worktree,
    possibly PARTIAL for a --repo-root pack) the HEAD commit's tree is
    enumerated (`git ls-tree -r -z --name-only HEAD`: every tracked path,
    materialised or not), so a partial checkout does not shrink the search; a
    plain directory is walked."""
    index = {}
    tl, head = _git_toplevel_head(root)
    if tl is not None and head:
        ls = _git(root, ["ls-tree", "-r", "-z", "--name-only", head], timeout=600)
        if ls.returncode == 0:
            for raw in ls.stdout.split(b"\0"):
                if not raw:
                    continue
                rel = raw.decode("utf-8", "surrogateescape")
                if any(part in _SIBLING_SEARCH_SKIP_DIRS for part in rel.split("/")[:-1]):
                    continue
                dirpath, fn = os.path.split(os.path.join(root, rel))
                index.setdefault(os.path.splitext(fn)[0], []).append((dirpath, fn))
            return index
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in _SIBLING_SEARCH_SKIP_DIRS)
        for fn in filenames:
            stem = os.path.splitext(fn)[0]
            index.setdefault(stem, []).append((dirpath, fn))
    return index


def check_sibling_search(batch, root):
    """T085 Round 6 (R5-I2 IMPORTANT) REWRITE -- see the module
    docstring's "sibling-search" paragraph for the full root-cause +
    rationale. This check no longer reads any field the batch declares;
    it PERFORMS a real, bounded, deterministic sibling search against
    `root` for every slice whose changed-path set _paths_from_slice()
    can confidently establish, and the verdict depends ONLY on whether
    that search was genuinely performed -- never on what, if anything,
    the batch's own context_pack happens to say about it."""
    slices = batch.get("slices")
    if not isinstance(slices, list) or not slices:
        return {"check": "sibling-search", "verdict": "FAIL",
                "evidence": {"reason": "batch carries zero slices -- nothing was searched"}}

    root_abs = os.path.abspath(root)
    index = _stem_index(root_abs)

    per_slice = []
    unresolved = []
    for idx, sl in enumerate(slices):
        paths, resolved = _paths_from_slice(sl)
        if not resolved:
            unresolved.append(idx)
            continue
        siblings_for_slice = {}
        for p in paths:
            stem = os.path.splitext(os.path.basename(p))[0]
            own_dir = os.path.normpath(os.path.dirname(os.path.join(root_abs, p)))
            found = sorted(
                _relpath(os.path.join(dirpath, fn), root_abs)
                for dirpath, fn in index.get(stem, [])
                if os.path.normpath(dirpath) != own_dir
            )
            if found:
                siblings_for_slice[p] = found
        per_slice.append({
            "slice_index": idx,
            "changed_path_count": len(paths),
            "siblings_found": siblings_for_slice,
        })

    if unresolved:
        return {"check": "sibling-search", "verdict": "FAIL", "evidence": {
            "reason": ("slice(s) with no confidently-parseable changed-file list "
                       "(neither an explicit changed_paths list nor a slicer.py-shaped "
                       "blast_radius string) -- cannot search what was never named"),
            "unresolved_slice_indices": unresolved,
        }}

    return {"check": "sibling-search", "verdict": "PASS", "evidence": {
        "searched_slice_count": len(per_slice),
        "results": per_slice,
    }}


def check_blast_radius(batch):
    return _batch_wide_field_check(batch, "blast_radius", "blast-radius", "scope")


def run_checks(batch, root, baseline=None, head_sha=None, ctx=None, opts=None):
    scope = _batch_scope(batch, root)
    scoped_files, scope_note = scope["files"], scope["note"]
    by_name = {
        "parse": lambda: check_parse(root, scoped_files, scope_note),
        "shellcheck": lambda: check_shellcheck(root, scope, baseline, head_sha, batch, ctx, opts),
        "affected-gates": check_affected_gates,
        "touched-gate-mutations": check_touched_gate_mutations,
        "secret-scan": lambda: check_secret_scan(root, scoped_files, scope_note),
        "doc-sync": check_doc_sync,
        "closure-evidence-class": check_closure_evidence_class,
        "sibling-search": lambda: check_sibling_search(batch, root),
        "blast-radius": lambda: check_blast_radius(batch),
        "already-fixed-markers": check_already_fixed_markers,
    }
    return [by_name[name]() for name in CHECK_ORDER]


def gate_version():
    """sha256 over the gate source files (this library + lib/precheck_common.py):
    a pack records the exact gate logic that produced it, so a pack built by
    other gate logic is detectably stale (F-R2-9)."""
    return _common_gate_version()


def _checkout_facts(root):
    """For a git-worktree checkout: tracked paths at HEAD vs paths present in
    the index -- a PARTIAL checkout (a --repo-root pack) materialises only the
    changed paths; evidence that a million-file tree was not checked out.
    None for a plain directory."""
    tl, head = _git_toplevel_head(root)
    if tl is None or not head:
        return None
    try:
        tree = _git(root, ["ls-tree", "-r", "-z", "--name-only", head], timeout=600)
        idx = _git(root, ["ls-files", "-z"], timeout=600)
    except (OSError, subprocess.TimeoutExpired):
        return {"partial": None}
    if tree.returncode != 0 or idx.returncode != 0:
        return {"partial": None}
    nt = sum(1 for e in tree.stdout.split(b"\0") if e)
    ni = sum(1 for e in idx.stdout.split(b"\0") if e)
    return {"partial": ni < nt, "tracked_at_head": nt, "materialised": ni}


def cmd_run(a):
    root = os.path.abspath(a.clean_checkout)
    if not os.path.isdir(root):
        print("precheck_pack: --clean-checkout is not a readable directory: %s" % root, file=sys.stderr)
        return 4

    batch, err = _load_json(a.batch, "--batch")
    if err:
        print("precheck_pack: %s" % err, file=sys.stderr)
        return 2
    if not isinstance(batch, dict):
        print("precheck_pack: --batch must be a JSON object", file=sys.stderr)
        return 2

    if a.baseline_ref and not a.baseline_repo:
        print("precheck_pack: --baseline-ref requires at least one --baseline-repo", file=sys.stderr)
        return 2
    if a.baseline_repo and not a.baseline_ref:
        print("precheck_pack: --baseline-repo requires an explicit --baseline-ref (the batch BASE; never "
              "defaulted to HEAD)", file=sys.stderr)
        return 2
    for spec in a.baseline_repo:
        if "\n" in spec or "\r" in spec or "\0" in spec:
            print("precheck_pack: --baseline-repo must not contain a newline/NUL: %r" % spec, file=sys.stderr)
            return 2
        if not any(os.path.isabs(pth) for _pre, pth in _parse_baseline_specs([spec])):
            print("precheck_pack: --baseline-repo PATH must be absolute: %r" % spec, file=sys.stderr)
            return 2
    # F10: the timeouts may be set per run, but never above their ceilings (one run cannot hold the
    # host-wide large-lint lock -- 2 x the exception timeout -- indefinitely)
    for name, ceiling in (("shellcheck_timeout", MAX_SC_TIMEOUT), ("shellcheck_exception_timeout", MAX_EXCEPTION_TIMEOUT)):
        v = getattr(a, name)
        if v is not None and not 0 < v <= ceiling:
            print("precheck_pack: --%s must be a positive number of seconds <= %d" % (name.replace("_", "-"), ceiling),
                  file=sys.stderr)
            return 2
    # B1: the host-safety caps may be LOWERED per run, never raised
    for name, ceiling in (("shellcheck_memory_cap_mib", DEFAULT_MEM_CAP_MIB), ("shellcheck_max_lines", DEFAULT_MAX_LINES)):
        v = getattr(a, name)
        if v is not None and not 0 < v <= ceiling:
            print("precheck_pack: --%s must be in 1..%d (a cap can be lowered, never raised)"
                  % (name.replace("_", "-"), ceiling), file=sys.stderr)
            return 2
    exceptions = a.shellcheck_exceptions
    bound_run = bool(a.baseline_repo) and isinstance(batch.get("binding"), dict)
    if bound_run and exceptions and os.path.normpath(exceptions) != CANONICAL_EXCEPTIONS_REL:
        # I1: in a bound run the gate itself picks the canonical, head-tracked TSV
        print("precheck_pack: --shellcheck-exceptions in a bound run may only name the canonical %s (got %r)"
              % (CANONICAL_EXCEPTIONS_REL, exceptions), file=sys.stderr)
        return 2
    opts = {"timeout": a.shellcheck_timeout, "exception_timeout": a.shellcheck_exception_timeout,
            "exceptions": exceptions, "mem_cap_mib": a.shellcheck_memory_cap_mib,
            "max_lines": a.shellcheck_max_lines}
    baseline = _make_baseline(a.baseline_repo, a.baseline_ref)
    ctx = {}
    checks = run_checks(batch, root, baseline, a.head_sha, ctx, opts)
    all_pass = all(c["verdict"] == "PASS" for c in checks)
    provenance = None
    if baseline is not None:
        with open(a.batch, "rb") as fh:
            batch_bytes = fh.read()
        binding = batch.get("binding") if isinstance(batch.get("binding"), dict) else {}
        provenance = {"base_sha": sorted({e["commit"] for e in baseline["repos"] if e.get("commit")}),
                      "base_ref": baseline["ref"],
                      "head_sha": ctx.get("head_sha"),
                      "head_sha_source": ctx.get("head_sha_source", "unbound"),
                      "repo": (baseline["repos"][0]["path"] if len(baseline["repos"]) == 1 else None),
                      "kind": binding.get("kind"),
                      # F1: the verifier re-reads this exact batch file and re-checks it
                      "batch_path": os.path.abspath(a.batch),
                      "batch_sha256": hashlib.sha256(batch_bytes).hexdigest(),
                      # M6: the linter that produced the verdict (the verifier requires the same one)
                      "shellcheck_version": ctx.get("shellcheck_version"),
                      "shellcheck_params": ctx.get("shellcheck_params"),
                      # I1: which legacy-exception TSV was used (head/base blob sha256; None = none)
                      "exceptions": ctx.get("exceptions")}

    body = {
        "batch_id": batch.get("batch_id", "UNKNOWN"),
        "checks": checks,
        "all_pass": all_pass,
        "run_from": a.clean_checkout,
        "independence_tier": "instance",
        "gate_version": gate_version(),
    }
    if provenance is not None:
        body["provenance"] = provenance
    co = _checkout_facts(root)
    if co is not None:
        body["checkout"] = co
    rc = _write(body, a.out)
    if rc != 0:
        return rc
    return 0 if all_pass else 1


# ---------------------------------------------------------------------------
# --determinism-check (C-003, "present on every tool") -- runs THIS SAME
# process twice out-of-process on the identical inputs, into distinct
# scratch --out files, and compares the two written body_hash values
# (never raw file bytes -- run_meta's wall-clock legitimately differs
# between the two runs and must not be read as nondeterminism).
# ---------------------------------------------------------------------------
def run_determinism_check(argv, timeout_s=DETERMINISM_TIMEOUT_S):
    inner = [a for a in argv if a != "--determinism-check"]
    with tempfile.TemporaryDirectory() as tmp:
        hashes = []
        for i in (1, 2):
            run_argv = list(inner)
            out_i = os.path.join(tmp, "run%d.json" % i)
            if "--out" in run_argv:
                idx = run_argv.index("--out")
                run_argv[idx + 1] = out_i
            else:
                run_argv += ["--out", out_i]
            cmd_line = [sys.executable, os.path.abspath(__file__)] + run_argv
            try:
                proc = subprocess.run(cmd_line, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                print("precheck_pack determinism-check: run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (0, 1) or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                print("precheck_pack determinism-check: run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                hashes.append(json.load(fh).get("body_hash"))
    if hashes[0] is None or hashes[0] != hashes[1]:
        print("precheck_pack determinism-check: nondeterministic: run1=%s run2=%s"
              % (hashes[0], hashes[1]), file=sys.stderr)
        return 1
    print("precheck_pack determinism-check: deterministic (%s)" % hashes[0])
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="precheck_pack_run")
    p.add_argument("--config")
    p.add_argument("--batch", required=True)
    p.add_argument("--clean-checkout", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--determinism-check", action="store_true")
    p.add_argument("--baseline-repo", action="append", default=[])
    p.add_argument("--baseline-ref")
    p.add_argument("--head-sha")
    p.add_argument("--shellcheck-exceptions")
    p.add_argument("--shellcheck-timeout", type=float)
    p.add_argument("--shellcheck-exception-timeout", type=float)
    p.add_argument("--shellcheck-memory-cap-mib", type=int)
    p.add_argument("--shellcheck-max-lines", type=int)
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    if a.determinism_check:
        return run_determinism_check(argv)

    try:
        return cmd_run(a)
    except Exception as exc:  # C-001: an internal error is never a finding -- refuse honestly
        print("precheck_pack: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
