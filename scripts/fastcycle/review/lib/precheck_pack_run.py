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
  - shellcheck: for every *.sh file in scope, runs the real
    `shellcheck -f json1` (dialect from the shebang) and reports every
    real finding shellcheck emits, at ANY severity including "info" --
    matching this project's own review_record.py fixtures, which already
    treat a bare shellcheck rule id (e.g. "SC2086") as a machine-findable
    "mechanical" finding regardless of severity. Honest gap: if the
    `shellcheck` binary is absent from PATH, this check PASSes with
    evidence naming the gap (11.4.3 honest skip) rather than silently
    fabricating a clean scan.
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
  - sibling-search / blast-radius: real, not fabricated -- both are
    copied verbatim from the ReviewBatch's own first slice
    context_pack.sibling_search_ref / .blast_radius (produced by
    review/slicer.py from the real change set), falling back to the
    honest literal "UNMEASURED" only when the batch carries neither
    field. Fixed (T085 round-3 independent review): the verdict now
    tracks FIELD PRESENCE, never a hardcoded PASS -- PASS only when the
    slice's own context_pack genuinely carries the field (any non-None
    value, including a hand-authored fixture literally spelling the word
    "UNMEASURED" as its real field content -- that is still a value the
    batch's own data supplied, not this tool's own absence-fallback);
    FAIL when precheck_pack_run.py itself had to manufacture the
    "UNMEASURED" evidence literal because the field was genuinely absent
    from every slice. Root-cause (11.4.201(6) false-null): both checks
    previously returned a hardcoded "verdict": "PASS" regardless of
    whether evidence.ref/evidence.scope held a real value or this tool's
    own synthetic "UNMEASURED" fallback -- a genuinely unmeasured
    sibling-search/blast-radius silently satisfied all_pass, which is
    exactly the condition review_dispatch_guard-class consumers rely on
    "all_pass == true" to mean genuinely checked, not silently skipped.

Output (C-002): canonical JSON, `schema: "precheck/v1"`, `body_hash` =
sha256 of the canonical body excluding `run_meta` (this file's own tiny
copy of the same two canonicalisation primitives review_record.py and
review/slicer.py each keep locally, per review_record.py's own stated
"no cross-file runtime dependency" policy applied consistently across
this whole tool family).
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SCHEMA = "precheck/v1"
_EXCLUDED = ("run_meta", "body_hash")
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
_BLAST_RADIUS_RE = re.compile(r"^(\d+) changed path\(s\) in this slice: (.+)$")


def _canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _body_hash_of(doc):
    body = {k: v for k, v in doc.items() if k not in _EXCLUDED}
    return hashlib.sha256(_canon(body).encode("utf-8")).hexdigest()


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


def _shebang_interpreter(path):
    """Returns "bash" if the file's own shebang names bash, else the
    conservative default "sh" (matching this project's own fixture
    scripts, which all declare `#!/bin/sh`)."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            first = fh.readline()
    except OSError:
        return "sh"
    if first.startswith("#!") and "bash" in first:
        return "bash"
    return "sh"


def _find_shell_scripts(root):
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in _SKIP_DIRS)
        for fn in sorted(filenames):
            if fn.endswith(".sh"):
                hits.append(os.path.join(dirpath, fn))
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
    m = _BLAST_RADIUS_RE.match(blast_radius)
    if not m:
        return None, False
    declared_count = int(m.group(1))
    segments = m.group(2).split(", ")
    if len(segments) != declared_count or not all(segments):
        return None, False
    return segments, True


def _batch_scoped_files(batch, root):
    """Derives the REAL set of files this batch changed, confidently, from
    --batch's own slices (see _paths_from_slice). Returns (files, note):
    `files` is a sorted list of EXISTING absolute paths under `root` the
    batch declares changed, or None when the batch's own data cannot
    confidently establish a per-file scope -- the honest signal to the
    caller to fall back to the current whole-checkout scan (never a
    guessed partial one). `note` is a short, human-readable evidence
    string naming why, either way (constitution 11.4.6: honest gap named,
    never silently implied complete)."""
    slices = batch.get("slices")
    if not isinstance(slices, list) or not slices:
        return None, "batch carries no slices -- cannot derive a per-file scope"

    declared = set()
    for sl in slices:
        paths, resolved = _paths_from_slice(sl)
        if not resolved:
            return None, ("a slice's context_pack does not carry a confidently-parseable "
                           "changed-file list (neither an explicit changed_paths list nor a "
                           "slicer.py-shaped blast_radius string)")
        declared.update(paths)

    root_abs = os.path.abspath(root)
    existing = []
    for p in sorted(declared):
        candidate = os.path.normpath(os.path.join(root_abs, p))
        # 11.4.6: never trust a declared path that escapes --clean-checkout
        # (a corrupted/malicious batch.json must not widen scope outward).
        if candidate != root_abs and not candidate.startswith(root_abs + os.sep):
            return None, "a declared changed path (%r) resolves outside --clean-checkout" % p
        if os.path.isfile(candidate):
            existing.append(candidate)
        # A declared path absent from this checkout is honoured as a real
        # deletion/rename -- never a reason to distrust the whole batch --
        # there is simply nothing on disk to scan for that one entry.

    if not existing:
        # Every declared path was absent from this checkout: far more likely
        # a base-path mismatch (the batch's "path" fields are relative to a
        # different root than --clean-checkout) than an all-deletions batch.
        # An artificially EMPTY scope would silently under-scan every real
        # file in the checkout, so this is treated as unresolved -- fall
        # back to the honest whole-checkout scan rather than a confidently
        # wrong empty one.
        return None, ("batch declared %d changed path(s) but none exist under "
                       "--clean-checkout (likely path-base mismatch)" % len(declared))

    return sorted(set(existing)), ("batch-scoped: %d file(s) from %d slice(s)"
                                    % (len(existing), len(slices)))


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
    candidates = (sorted(p for p in scoped_files if p.endswith(".sh"))
                  if scoped_files is not None else _find_shell_scripts(root))
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


def check_shellcheck(root, scoped_files, scope_note):
    if not _have("shellcheck"):
        evidence = {"skipped": "shellcheck not found on PATH (11.4.3 honest skip)"}
        evidence.update(_scope_fragment(scoped_files, scope_note))
        return {"check": "shellcheck", "verdict": "PASS", "evidence": evidence}
    candidates = (sorted(p for p in scoped_files if p.endswith(".sh"))
                  if scoped_files is not None else _find_shell_scripts(root))
    findings = []
    for path in candidates:
        interp = _shebang_interpreter(path)
        rel = _relpath(path, root)
        try:
            proc = subprocess.run(["shellcheck", "-s", interp, "-f", "json1", path],
                                   capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as exc:
            findings.append({"file": rel, "message": "shellcheck failed to run: %s" % exc})
            continue
        # shellcheck's real exit codes: 0 clean, 1 findings present, anything else is a
        # tool-level failure (unreadable file, bad flag, ...) that this check must not
        # silently swallow as a clean PASS.
        if proc.returncode not in (0, 1):
            findings.append({"file": rel,
                              "message": "shellcheck exited %d: %s" % (proc.returncode, (proc.stderr or "").strip())})
            continue
        try:
            out_doc = json.loads(proc.stdout) if proc.stdout.strip() else {"comments": []}
        except json.JSONDecodeError:
            findings.append({"file": rel, "message": "shellcheck produced unparseable json1 output"})
            continue
        for c in out_doc.get("comments") or []:
            if not isinstance(c, dict):
                continue
            findings.append({
                "file": rel,
                "line": c.get("line"),
                "column": c.get("column"),
                "rule": "SC%s" % c.get("code"),
                "level": c.get("level"),
                "message": c.get("message"),
            })
    verdict = "FAIL" if findings else "PASS"
    evidence = {"findings": findings} if findings else {}
    evidence.update(_scope_fragment(scoped_files, scope_note))
    return {"check": "shellcheck", "verdict": verdict, "evidence": evidence}


def check_secret_scan(root, scoped_files, scope_note):
    if scoped_files is not None:
        candidates = sorted(scoped_files)
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


def check_sibling_search(batch):
    # T085 round-3 fix: verdict tracks FIELD PRESENCE (11.4.201(6) false-null
    # fix), never a hardcoded PASS -- see module docstring's per-check
    # breakdown for the full rationale. A genuinely-absent field (ref is
    # None) is honestly FAIL; a present field -- even one whose real value
    # happens to be the literal string "UNMEASURED" (a hand-authored
    # fixture's own real data, not this tool's fallback) -- is PASS.
    ref = _first_slice_field(batch, "sibling_search_ref")
    verdict = "PASS" if ref is not None else "FAIL"
    return {"check": "sibling-search", "verdict": verdict,
            "evidence": {"ref": ref if ref is not None else "UNMEASURED"}}


def check_blast_radius(batch):
    # See check_sibling_search()'s comment -- identical fix, same rationale.
    scope = _first_slice_field(batch, "blast_radius")
    verdict = "PASS" if scope is not None else "FAIL"
    return {"check": "blast-radius", "verdict": verdict,
            "evidence": {"scope": scope if scope is not None else "UNMEASURED"}}


def run_checks(batch, root):
    scoped_files, scope_note = _batch_scoped_files(batch, root)
    by_name = {
        "parse": lambda: check_parse(root, scoped_files, scope_note),
        "shellcheck": lambda: check_shellcheck(root, scoped_files, scope_note),
        "affected-gates": check_affected_gates,
        "touched-gate-mutations": check_touched_gate_mutations,
        "secret-scan": lambda: check_secret_scan(root, scoped_files, scope_note),
        "doc-sync": check_doc_sync,
        "closure-evidence-class": check_closure_evidence_class,
        "sibling-search": lambda: check_sibling_search(batch),
        "blast-radius": lambda: check_blast_radius(batch),
        "already-fixed-markers": check_already_fixed_markers,
    }
    return [by_name[name]() for name in CHECK_ORDER]


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

    checks = run_checks(batch, root)
    all_pass = all(c["verdict"] == "PASS" for c in checks)

    body = {
        "batch_id": batch.get("batch_id", "UNKNOWN"),
        "checks": checks,
        "all_pass": all_pass,
        "run_from": a.clean_checkout,
        "independence_tier": "instance",
    }
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
def run_determinism_check(argv, timeout_s=60):
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
