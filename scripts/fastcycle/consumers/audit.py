#!/usr/bin/env python3
"""audit.py - consumer audit (T-G04/T171; contract
consumer-audit-and-migration.md CA-010..CA-012; guarded by
tests/test_consumer_audit_red.sh, T167; FR-024, SC-010).

Subcommands:
  audit   --config <fastcycle.yaml> --consumers <consumers.json>
          --workdir <dir> --out <audit_dir/>
  summary --consumers <consumers.json> --audits <audit_dir/>
          --migrations <dir> --out <summary.json>

CA-010: exactly one ConsumerAuditReport per project in --consumers,
including projects this host cannot reach at all (UNMEASURED fields with
missing_instrument, never a silent 0/None); the written set is verified
by INDEPENDENTLY re-deriving it from disk (every report file's OWN
`project_id` field, re-globbed after the write loop) and comparing
against the project ids read from --consumers -- never by comparing the
write loop's own running counter against a count derived from the SAME
in-memory list it iterated (T177 Round 1 I8: that comparison is
tautological by construction -- a mutation that truncates the iterated
list moves both sides in lockstep and can never be caught by a bare
count check). Any enumerated id with no matching report on disk => exit
1, naming the missing id(s).

CA-011: measurements reuse the same tools this feature already uses
elsewhere -- constitution_pointer + behind_head_by via
`git -C <constitution_root> rev-list --count <gitlink>..HEAD` (the SAME
mechanism T167's own live control needle proves sound), preamble_bytes via
either the local CLAUDE.md's real byte size or (no local checkout) the
GitHub Contents API's own reported `size` field for that file --
Measured<int> in both cases. cleanliness is genuinely measured for every
local checkout via `git status --porcelain` (T177 Round 1 I7 -- the prior
docstring claimed this call without the code ever making it).
gate_suite_runtime, registry_defect_present, mechanism_presence and
pull_validate_time_seconds have no cross-repo instrument yet and are
recorded UNMEASURED with missing_instrument, never coerced to a fake
value (C-001 false-null guard). migration_effort is ALWAYS labelled
"ESTIMATE:<hours>", NEVER "Measured:" (T177 Round 1 I7 -- it is derived
from behind_head_by via a fixed hours-per-commit heuristic, not an
actual measured duration, regardless of whether behind_head_by itself
was measured).

Per data-model.md #13.2, `count(reports) = count(projects)` -- for a
project with MULTIPLE local checkouts (T177 Round 1 I9: a consumer can
be checked out more than once, e.g. via separate git worktrees on
separate tracks, and those checkouts can genuinely diverge), the ONE
report's top-level fields (constitution_pointer, behind_head_by,
measurements) describe `local_checkouts[0]` as before, and a NEW
`local_checkouts_detail` array carries a per-checkout breakdown (path,
constitution_pointer, behind_head_by, cleanliness) for EVERY known
checkout, not only the first -- never silently auditing one checkout and
treating it as authoritative for all.

CA-012: read-only. A local checkout is inspected with `git ls-tree` /
`git status --porcelain` only (never `checkout`, `pull`, `fetch --prune`,
or any write); a remote-only project is read via the GitHub Contents API
(no clone at all). --workdir exists for a future clone-based path
(consumers this host has no local checkout of but wants file-level
inspection for) and is currently unused when the GitHub API alone
suffices, which it does for every measurement CA-011 currently defines.
"""
import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("audit.py: PyYAML is required (python3 -m pip install pyyaml)", file=sys.stderr)
    sys.exit(2)


def load_config(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh)
    except OSError as exc:
        print("audit.py: cannot read --config %s: %s" % (path, exc), file=sys.stderr)
        sys.exit(2)
    return cfg or {}


def repo_root_of_config(config_path):
    # fastcycle.yaml's own header: "Paths below are relative to this
    # project's root (the directory containing this file's grandparent
    # `config/`)" -- config/fastcycle/fastcycle.yaml -> up 2 = repo root.
    config_dir = os.path.dirname(os.path.abspath(config_path))
    return os.path.dirname(os.path.dirname(config_dir))


def sh(args, cwd=None, timeout=20):
    try:
        proc = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout


def measure_behind(const_root, gitlink):
    if not gitlink:
        return None
    # cat-file -e prints nothing and exits 0 iff the object exists (T177
    # Round 3 minor: a leftover duplicate `exists = sh(...)` call whose
    # result was never read is removed).
    proc = subprocess.run(["git", "-C", const_root, "cat-file", "-e", gitlink], capture_output=True, timeout=20)
    if proc.returncode != 0:
        return None
    out = sh(["git", "-C", const_root, "rev-list", "--count", "%s..HEAD" % gitlink])
    if out is None:
        return None
    out = out.strip()
    if not out.isdigit():
        return None
    return int(out)


def gh_contents(project_id, path):
    try:
        proc = subprocess.run(
            ["gh", "api", "repos/%s/contents/%s" % (project_id, path)],
            capture_output=True, text=True, timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    try:
        return json.loads(proc.stdout)
    except ValueError:
        return None


def risk_and_effort(behind):
    if behind is None:
        return "MEDIUM", "behind_head_by UNMEASURED -- risk cannot be lower-bounded, defaults to MEDIUM pending measurement", None
    if behind <= 50:
        risk, reason = "LOW", "behind_head_by=%d (<=50)" % behind
    elif behind <= 200:
        risk, reason = "MEDIUM", "behind_head_by=%d (51-200)" % behind
    else:
        risk, reason = "HIGH", "behind_head_by=%d (>200)" % behind
    effort_hours = max(1, round(behind / 50.0, 1))
    return risk, reason, effort_hours


def measure_cleanliness(checkout):
    """Returns ("clean"|"dirty", measured: bool) -- T177 Round 1 I7: a
    genuine `git status --porcelain` measurement (the docstring's
    existing, pre-this-fix claim that CA-012 already did this was false
    until now; the call did not exist anywhere in this module)."""
    out = sh(["git", "-C", checkout, "status", "--porcelain=v1"])
    if out is None:
        return None, False
    return ("clean" if out.strip() == "" else "dirty"), True


def _is_real_checkout(path):
    return bool(path) and (os.path.isdir(os.path.join(path, ".git")) or os.path.isfile(os.path.join(path, ".git")))


def audit_checkout_detail(checkout, const_root):
    """Per-checkout breakdown for local_checkouts_detail (T177 Round 1
    I9): one entry per KNOWN local checkout, never only checkouts[0] --
    a consumer with multiple local checkouts (e.g. separate git
    worktrees on separate tracks) can genuinely diverge, and auditing
    only the first silently hides that."""
    detail = {"path": checkout, "constitution_pointer": None, "behind_head_by": "UNMEASURED", "cleanliness": "UNMEASURED"}
    if not _is_real_checkout(checkout):
        detail["cleanliness"] = "UNMEASURED"
        return detail
    out = sh(["git", "-C", checkout, "ls-tree", "HEAD", "constitution"])
    gitlink = None
    if out:
        parts = out.split()
        if len(parts) >= 3:
            gitlink = parts[2]
    detail["constitution_pointer"] = gitlink
    if gitlink:
        behind = measure_behind(const_root, gitlink)
        detail["behind_head_by"] = behind if behind is not None else "UNMEASURED"
    clean, measured = measure_cleanliness(checkout)
    detail["cleanliness"] = clean if measured else "UNMEASURED"
    return detail


def audit_one(project, const_root):
    project_id = project["project_id"]
    consumer_kind = project.get("consumer_kind", "submodule")
    local_checkouts = project.get("local_checkouts") or []

    gitlink = None
    preamble_bytes = None
    preamble_measured = False
    behind = None
    cleanliness = "UNMEASURED"
    gaps = []
    measurements = {}
    local_checkouts_detail = [audit_checkout_detail(c, const_root) for c in local_checkouts]

    if consumer_kind == "text-only-inheritance":
        gaps.append({
            "area": "constitution-pointer",
            "finding": "text-only inheritance: no constitution submodule gitlink to measure",
            "evidence": "consumer_kind=text-only-inheritance (enumerate.sh)",
        })
        measurements["gate_suite_runtime"] = {"value": None, "missing_instrument": "no gate suite in a text-only consumer"}
        measurements["registry_defect_present"] = {"value": None, "missing_instrument": "no owned tracker DB to inspect cross-repo"}
        measurements["mechanism_presence"] = {"value": None, "missing_instrument": "no cross-repo mechanism-wiring instrument yet"}
        measurements["pull_validate_time_seconds"] = {"value": None, "missing_instrument": "requires a live scratch clone + pull + validate run, not performed by a read-only audit pass (CA-012)"}
        local_ok = local_checkouts and os.path.isdir(local_checkouts[0])
        if local_ok:
            claude_md = os.path.join(local_checkouts[0], "CLAUDE.md")
            if os.path.isfile(claude_md):
                preamble_bytes = os.path.getsize(claude_md)
                preamble_measured = True
            clean, measured = measure_cleanliness(local_checkouts[0])
            cleanliness = clean if measured else "UNMEASURED"
        risk, risk_reason, effort = risk_and_effort(None)
        measurements["preamble_bytes"] = {"value": preamble_bytes, "measured": preamble_measured}
        measurements["cleanliness"] = {"value": cleanliness if cleanliness != "UNMEASURED" else None, "measured": cleanliness != "UNMEASURED"}
        return {
            "project_id": project_id,
            "constitution_pointer": None,
            "behind_head_by": "UNMEASURED",
            "gaps": gaps,
            "migration_effort": "ESTIMATE:0.5",
            "risk": risk,
            "risk_reason": risk_reason,
            "measurements": measurements,
            "local_checkouts_detail": local_checkouts_detail,
        }

    local_ok = _is_real_checkout(local_checkouts[0]) if local_checkouts else False
    if local_ok:
        checkout = local_checkouts[0]
        out = sh(["git", "-C", checkout, "ls-tree", "HEAD", "constitution"])
        if out:
            parts = out.split()
            if len(parts) >= 3:
                gitlink = parts[2]
        claude_md = os.path.join(checkout, "CLAUDE.md")
        if os.path.isfile(claude_md):
            preamble_bytes = os.path.getsize(claude_md)
            preamble_measured = True
        clean, measured = measure_cleanliness(checkout)
        cleanliness = clean if measured else "UNMEASURED"
    else:
        doc = gh_contents(project_id, "constitution")
        if doc and doc.get("type") == "submodule":
            gitlink = doc.get("sha")
        claude_doc = gh_contents(project_id, "CLAUDE.md")
        if claude_doc and "size" in claude_doc:
            preamble_bytes = claude_doc["size"]
            preamble_measured = True

    if gitlink:
        behind = measure_behind(const_root, gitlink)
        if behind is None:
            gaps.append({
                "area": "constitution-pointer",
                "finding": "gitlink %s is not resolvable in this host's constitution clone (fetch needed)" % gitlink,
                "evidence": "git -C %s cat-file -e %s" % (const_root, gitlink),
            })
    else:
        gaps.append({
            "area": "constitution-pointer",
            "finding": "could not resolve a constitution gitlink for this project (unreachable)",
            "evidence": "local checkout absent and gh api contents/constitution did not return a submodule entry",
        })

    measurements["gate_suite_runtime"] = {"value": None, "missing_instrument": "no cross-repo gate-suite-log instrument yet"}
    measurements["registry_defect_present"] = {"value": None, "missing_instrument": "no cross-repo tracker-DB instrument yet"}
    measurements["mechanism_presence"] = {"value": None, "missing_instrument": "no cross-repo mechanism-wiring instrument yet"}
    measurements["pull_validate_time_seconds"] = {"value": None, "missing_instrument": "requires a live scratch clone + pull + validate run, not performed by a read-only audit pass (CA-012)"}
    measurements["preamble_bytes"] = {"value": preamble_bytes, "measured": preamble_measured}
    measurements["cleanliness"] = {"value": cleanliness if cleanliness != "UNMEASURED" else None, "measured": cleanliness != "UNMEASURED"}

    risk, risk_reason, effort = risk_and_effort(behind)
    # T177 Round 1 I7: migration_effort is ALWAYS an ESTIMATE, never
    # "Measured:" -- it is derived from behind_head_by via a fixed
    # hours-per-commit heuristic (risk_and_effort's own `behind / 50.0`),
    # which is an estimate regardless of whether behind_head_by itself
    # was genuinely measured. The prior code labelled it "Measured:"
    # whenever behind_head_by was known, directly contradicting this
    # module's own docstring ("migration_effort is an ESTIMATE ...
    # labelled explicitly, never presented as Measured").
    return {
        "project_id": project_id,
        "constitution_pointer": gitlink,
        "behind_head_by": behind if behind is not None else "UNMEASURED",
        "gaps": gaps,
        "migration_effort": "ESTIMATE:%s" % (effort if effort is not None else "1"),
        "risk": risk,
        "risk_reason": risk_reason,
        "measurements": measurements,
        "local_checkouts_detail": local_checkouts_detail,
    }


def cmd_audit(args):
    cfg = load_config(args.config)  # noqa: F841 (loaded for CA-011 future tool paths; validated present)
    const_root = os.path.join(repo_root_of_config(args.config), "constitution")
    with open(args.consumers, "r", encoding="utf-8") as fh:
        consumers_doc = json.load(fh)
    projects = consumers_doc.get("projects", [])
    expected_ids = {p["project_id"] for p in projects}

    os.makedirs(args.out, exist_ok=True)
    written = 0
    written_paths = []
    for project in projects:
        report = audit_one(project, const_root)
        safe_name = project["project_id"].replace("/", "__")
        out_path = os.path.join(args.out, "%s.json" % safe_name)
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(report, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        written += 1
        written_paths.append(out_path)

    # CA-010 (T177 Round 1 I8 fix): re-derive the written set
    # INDEPENDENTLY from disk -- read each report's OWN `project_id`
    # field back -- rather than trusting the write loop's own running
    # counter compared against a count derived from the SAME in-memory
    # `projects` list it just iterated. A count-vs-count check like the
    # prior `written != len(projects)` is tautological by construction:
    # a mutation that truncates the iterated list (e.g.
    # `for project in projects[:-1]:`) moves BOTH sides of that
    # comparison in lockstep and can never be caught, confirmed live by
    # reproducing the reviewer's exact mutation before writing this fix.
    # `expected_ids` is captured ONCE, above, from the untouched
    # --consumers document, so it is immune to any such in-loop
    # truncation.
    #
    # T177 Round 2 R2-I6 fix: re-derive from `written_paths` (the paths
    # THIS RUN actually wrote), never a blind `glob.glob(--out/*.json)`
    # of the whole directory -- a REUSED --out directory can hold stale
    # files left over from a PREVIOUS run, and globbing silently papers
    # over a truncated-iteration mutation with a leftover file the
    # CURRENT run never touched (reproduced live: the reviewer's own
    # `projects[:-1]` mutant still globbed a stale prior-run file for the
    # dropped project and reported "wrote 1 ... verified 2/2"). Re-reading
    # each WRITTEN path's own content still independently verifies the
    # file's CONTENT matches what was intended, per the original I8
    # reasoning; it is the SET of paths considered, not the read-back
    # itself, that changes.
    on_disk_ids = set()
    for out_path in written_paths:
        try:
            with open(out_path, "r", encoding="utf-8") as fh:
                rec = json.load(fh)
        except (OSError, ValueError):
            continue
        rec_id = rec.get("project_id")
        if rec_id:
            on_disk_ids.add(rec_id)

    missing_ids = expected_ids - on_disk_ids
    if missing_ids:
        print(
            "audit.py: CA-010 report coverage mismatch: %d/%d enumerated project(s) have no ConsumerAuditReport on disk: %s"
            % (len(expected_ids) - len(missing_ids), len(expected_ids), ", ".join(sorted(missing_ids))),
            file=sys.stderr,
        )
        sys.exit(1)
    print(
        "audit.py: wrote %d ConsumerAuditReport(s) to %s (verified %d/%d enumerated project_id(s) present on disk)"
        % (written, args.out, len(expected_ids & on_disk_ids), len(expected_ids))
    )
    sys.exit(0)


# data-model.md #13.3 closed vocabulary (CA-019). A NOT-MIGRATED record is
# counted toward SC-010 coverage ONLY when its reason is EXACTLY one of
# these DEC-25 forms -- T177 Round 3 finding 1.
MIGRATION_STEPS = (
    "preflight", "backup", "fetch", "gitlink-bump", "post-update-hook",
    "consumer-gates", "wiring", "review", "commit", "push", "verify",
)
MIGRATION_REASONS = (
    "dirty-local", "unreachable", "divergent-branches", "no-write-access",
    "outside-migration-scope", "operator-blocked", "backup-failed",
    "consumer-gates-red", "out-of-scope-diff", "no-commit-wrapper",
    "review-no-go", "remote-rejected", "non-fast-forward",
    "verification-not-clean",
)
_REASON_RE = re.compile(r"^NOT-MIGRATED \(([a-z-]+): ([a-z-]+)\)$")


_SHA_ADDR_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def _verification_problem(v, base_dir):
    """None when `v` is a genuine CA-026 double-verify pair whose cited
    evidence still exists on disk BYTE-FOR-BYTE; otherwise the invalid
    class name. T177 Round 5 (round-4 I1 M1 + I3): the record's
    `content_address` is RE-DERIVED from the cited report file's actual
    bytes -- a shape-valid `sha256:<64 hex>` string that addresses
    anything else (the reviewer's mutation hashed the PATH STRING) is
    refused, and so is a record whose own `overall`/`body_hash` claim
    disagrees with what the cited report file itself says."""
    if not (isinstance(v, list) and len(v) == 2 and all(isinstance(e, dict) for e in v)):
        return "record-missing-verification-evidence"
    if not all(e.get("overall") == "CLEAN" for e in v):
        return "record-missing-verification-evidence"
    if not (v[0].get("body_hash") and v[0].get("body_hash") == v[1].get("body_hash")):
        return "record-missing-verification-evidence"
    for e in v:
        addr = e.get("content_address")
        path = e.get("path")
        if not (isinstance(addr, str) and _SHA_ADDR_RE.match(addr)) or not (isinstance(path, str) and path):
            return "record-missing-verification-evidence"
        real = path if os.path.isabs(path) else os.path.join(base_dir, path)
        try:
            with open(real, "rb") as fh:
                raw = fh.read()
        except OSError:
            return "record-verification-evidence-unverifiable"
        if "sha256:" + hashlib.sha256(raw).hexdigest() != addr:
            return "record-verification-evidence-mismatch"
        try:
            report = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            return "record-verification-evidence-mismatch"
        if not isinstance(report, dict) or report.get("overall") != e.get("overall") or report.get("body_hash") != e.get("body_hash"):
            return "record-verification-evidence-mismatch"
    return None


def classify_migration_record(rec, base_dir="."):
    """Returns (valid: bool, key: str). A VALID record is one this summary
    may count toward coverage; key is "MIGRATED" or the exact closed-set
    not_migrated_reason. An INVALID record is never counted; key names why:

      record-missing-verification-evidence -- MIGRATED with no genuine
          double-CLEAN, equal-body_hash verification pair carrying a
          sha256 content address + path per report (#13.3 "verification
          ... required iff MIGRATED");
      record-verification-evidence-unverifiable -- the cited report file
          does not exist / cannot be read (relative paths resolve against
          the record file's own directory);
      record-verification-evidence-mismatch -- the cited report's REAL
          bytes do not hash to the recorded content_address, or the report
          itself says something other than the record claims (T177 Round
          5, round-4 I1 M1 / I3);
      record-missing-review-ref -- MIGRATED with no `review_ref` (#13.3
          "required iff MIGRATED"; T177 Round 5 I3 -- enforced, data model
          not amended);
      record-missing-backup-marker -- MIGRATED with no `backup_marker`
          {path, content_address sha256:<64 hex>} (#13.3, §9.2). Only the
          marker's SHAPE is checked: the backup directory itself is a
          disposable §9.2 mirror and may legitimately be pruned later, so
          its absence on disk is not evidence of a false claim;
      nonconforming-reason -- NOT-MIGRATED whose reason is not EXACTLY a
          closed-set DEC-25 form (e.g. the reviewer's repro records that
          carried only {"project_id": ...} and were previously counted as
          not-migrated with reason "UNKNOWN");
      local-git-error-vocabulary-gap -- a well-formed DEC-25 record whose
          reason is migrate.sh's own `local-git-error` (a local git failure
          no closed-set reason describes; T177 Round 3 N2). Still never
          counted, but reported in its OWN bucket so an operator can tell
          a tool-side git failure from a malformed record (round-4 MINOR);
      dry-run-only -- a dry run (CA-028: "planned diff and preflight
          verdict only") is not a migration outcome at all; migrate.sh
          writes outcome DRY-RUN, and the legacy "NOT-MIGRATED (preflight:
          dry-run)" form older runs wrote is classified the same way;
      missing-or-unknown-outcome -- anything else.
    """
    outcome = rec.get("outcome")
    if outcome == "MIGRATED":
        problem = _verification_problem(rec.get("verification"), base_dir)
        if problem:
            return False, problem
        rref = rec.get("review_ref")
        if not (isinstance(rref, str) and rref.strip()):
            return False, "record-missing-review-ref"
        bm = rec.get("backup_marker")
        if not (isinstance(bm, dict) and isinstance(bm.get("path"), str) and bm.get("path")
                and isinstance(bm.get("content_address"), str) and _SHA_ADDR_RE.match(bm["content_address"])):
            return False, "record-missing-backup-marker"
        return True, "MIGRATED"
    if outcome == "DRY-RUN":
        return False, "dry-run-only"
    if outcome == "NOT-MIGRATED":
        reason = rec.get("not_migrated_reason")
        if reason == "NOT-MIGRATED (preflight: dry-run)":
            return False, "dry-run-only"
        if reason == "NOT-MIGRATED (dirty-local)":
            return True, reason
        m = _REASON_RE.match(reason or "")
        if m and m.group(1) in MIGRATION_STEPS and m.group(2) in MIGRATION_REASONS and m.group(2) != "dirty-local":
            return True, reason
        if m and m.group(1) in MIGRATION_STEPS and m.group(2) == "local-git-error":
            return False, "local-git-error-vocabulary-gap"
        return False, "nonconforming-reason"
    return False, "missing-or-unknown-outcome"


def cmd_summary(args):
    with open(args.consumers, "r", encoding="utf-8") as fh:
        consumers_doc = json.load(fh)
    projects = consumers_doc.get("projects", [])
    known_ids = {p["project_id"] for p in projects}
    audit_files = glob.glob(os.path.join(args.audits, "*.json"))
    migration_files = glob.glob(os.path.join(args.migrations, "*.json")) if args.migrations and os.path.isdir(args.migrations) else []

    # T177 Round 3 finding 1(c): a consumers file written by a DEGRADED
    # enumeration (enumerate.sh exit 5 -- some orgs/repos could not be
    # probed) holds a project set that is real but INCOMPLETE. Its
    # `projects` list is therefore NOT a trustworthy SC-010 denominator:
    # 19/19 over a set that silently lost projects is a false 1.0. The
    # previous code never read `source_reachability` at all. A degraded
    # file now makes the summary refuse (coverage_trusted=false, exit 1),
    # naming every degraded probe; a file with NO source_reachability
    # block at all (hand-written, or pre-B1) is recorded as "unrecorded"
    # and likewise never trusted as complete -- the absence of a
    # reachability record is not evidence of reachability (§11.4.201(6)).
    #
    # T177 Round 5 (round-4 I2): "complete" now requires BOTH degraded-probe
    # lists to be genuinely PRESENT as lists. Round 3 only required the
    # parent key: `"source_reachability": {}` (present but empty) read as
    # complete via `reach.get(...) or []`, and a hand-written MIGRATED
    # record then yielded coverage_trusted=true on a project set nobody
    # proved complete. A block missing either list, or holding a non-list,
    # is "incomplete" -- never trusted, exactly like an absent block.
    reach = consumers_doc.get("source_reachability")
    degraded = []
    if not isinstance(reach, dict):
        enumeration_reachability = "unrecorded"
    elif not (isinstance(reach.get("github_degraded"), list) and isinstance(reach.get("gitlab_degraded"), list)):
        enumeration_reachability = "incomplete"
    else:
        degraded = list(reach["github_degraded"]) + list(reach["gitlab_degraded"])
        enumeration_reachability = "degraded" if degraded else "complete"

    # T177 Round 1 B4: counted by DISTINCT enumerated project_id, never by
    # file count; out-of-set ids are reported, never counted.
    #
    # T177 Round 3 finding 1 (supersedes Round 2's mtime-wins rule): only
    # VALID records (classify_migration_record) count. Duplicate files for
    # one project are resolved by CONTENT, never by file metadata: if every
    # valid record for a project agrees on (outcome, reason, commit) it
    # counts once; if two valid records DISAGREE the project is reported in
    # `conflicting_records` and is NOT covered -- mtime and filename order
    # are both properties of the copy, not of the migration (a `cp`, a
    # checkout, or a `touch` reorders them), so neither can decide which
    # claim is true. Invalid records never count and never override a
    # valid one; they are listed in `invalid_records_by_class`.
    #
    # OPERATIONAL CONSTRAINT (T177 Round 5, round-4 I6): --migrations must
    # hold exactly ONE record per project. Content-based dedup cannot tell
    # an honest RETRY history (an earlier valid `dirty-local` record left
    # beside a later valid MIGRATED record for the same project) from two
    # contradictory claims, so such a history is reported as conflicting
    # and the project as uncovered. That fails SAFE (never silently
    # trusted); the remedy is for re-runs to overwrite the project's
    # previous record (migrate.sh --out <same path>), never accumulate.
    valid_by_id = {}
    invalid_by_id = {}
    unknown_ids_seen = set()
    unreadable = []
    for mf in sorted(migration_files):
        try:
            with open(mf, "r", encoding="utf-8") as fh:
                rec = json.load(fh)
        except (OSError, ValueError):
            unreadable.append(os.path.basename(mf))
            continue
        if not isinstance(rec, dict):
            unreadable.append(os.path.basename(mf))
            continue
        pid = rec.get("project_id")
        if not pid:
            continue
        if pid not in known_ids:
            unknown_ids_seen.add(pid)
            continue
        valid, key = classify_migration_record(rec, os.path.dirname(os.path.abspath(mf)))
        if valid:
            valid_by_id.setdefault(pid, set()).add((key, rec.get("commit") or ""))
        else:
            invalid_by_id.setdefault(pid, []).append(key)

    migrated = 0
    not_migrated_by_reason = {}
    conflicting = {}
    for pid, sigs in valid_by_id.items():
        if len(sigs) > 1:
            conflicting[pid] = sorted("%s@%s" % (k, c or "-") for k, c in sigs)
            continue
        key = next(iter(sigs))[0]
        if key == "MIGRATED":
            migrated += 1
        else:
            not_migrated_by_reason[key] = not_migrated_by_reason.get(key, 0) + 1
    covered = migrated + sum(not_migrated_by_reason.values())

    invalid_records_by_class = {}
    for pid, keys in invalid_by_id.items():
        for k in keys:
            invalid_records_by_class[k] = invalid_records_by_class.get(k, 0) + 1

    # `audited` likewise counts DISTINCT enumerated ids with a real
    # report on disk, never raw file count (the same B4 defect class).
    audited_ids = set()
    for af in audit_files:
        try:
            with open(af, "r", encoding="utf-8") as fh:
                arec = json.load(fh)
        except (OSError, ValueError):
            continue
        apid = arec.get("project_id") if isinstance(arec, dict) else None
        if apid in known_ids:
            audited_ids.add(apid)

    coverage = covered / len(projects) if projects else 0.0
    uncovered = sorted(known_ids - {pid for pid in valid_by_id if pid not in conflicting})
    coverage_trusted = enumeration_reachability == "complete" and not conflicting

    doc = {
        "schema": "summary/v1",
        "projects": len(projects),
        "audited": len(audited_ids),
        "migrated": migrated,
        "not_migrated_by_reason": not_migrated_by_reason,
        "coverage": coverage,
        "coverage_trusted": coverage_trusted,
        "enumeration_reachability": enumeration_reachability,
        "uncovered_ids": uncovered,
    }
    if degraded:
        doc["enumeration_degraded"] = degraded
    if conflicting:
        doc["conflicting_records"] = conflicting
    if invalid_records_by_class:
        doc["invalid_records_by_class"] = invalid_records_by_class
    if unreadable:
        doc["unreadable_record_files"] = sorted(unreadable)
    if unknown_ids_seen:
        doc["unknown_ids_ignored"] = sorted(unknown_ids_seen)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    if not coverage_trusted:
        why = []
        if enumeration_reachability == "degraded":
            why.append("the consumers file comes from a DEGRADED enumeration (%d probe(s) failed) -- its project set is incomplete" % len(degraded))
        elif enumeration_reachability == "unrecorded":
            why.append("the consumers file carries no source_reachability block -- completeness of its project set is unknown")
        elif enumeration_reachability == "incomplete":
            why.append("the consumers file's source_reachability block lacks a github_degraded and/or gitlab_degraded LIST -- completeness of its project set is unproven")
        if conflicting:
            why.append("%d project(s) have conflicting valid records: %s" % (len(conflicting), ", ".join(sorted(conflicting))))
        print("audit.py summary: coverage NOT trusted: %s" % "; ".join(why), file=sys.stderr)
        sys.exit(1)
    sys.exit(0 if coverage == 1.0 else 1)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("audit")
    a.add_argument("--config", required=True)
    a.add_argument("--consumers", required=True)
    a.add_argument("--workdir", required=True)
    a.add_argument("--out", required=True)
    a.set_defaults(func=cmd_audit)

    s = sub.add_parser("summary")
    s.add_argument("--consumers", required=True)
    s.add_argument("--audits", required=True)
    s.add_argument("--migrations", required=True)
    s.add_argument("--out", required=True)
    s.set_defaults(func=cmd_summary)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
