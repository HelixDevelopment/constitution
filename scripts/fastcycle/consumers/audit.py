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
import json
import os
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
    exists = sh(["git", "-C", const_root, "cat-file", "-e", gitlink])
    # cat-file -e prints nothing on success; sh() returns "" (falsy-looking
    # but not None) on success, None on failure/timeout.
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
    for project in projects:
        report = audit_one(project, const_root)
        safe_name = project["project_id"].replace("/", "__")
        out_path = os.path.join(args.out, "%s.json" % safe_name)
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(report, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        written += 1

    # CA-010 (T177 Round 1 I8 fix): re-derive the written set
    # INDEPENDENTLY from disk -- glob --out's real directory content and
    # read each report's OWN `project_id` field -- rather than trusting
    # the write loop's own running counter compared against a count
    # derived from the SAME in-memory `projects` list it just iterated.
    # A count-vs-count check like the prior `written != len(projects)`
    # is tautological by construction: a mutation that truncates the
    # iterated list (e.g. `for project in projects[:-1]:`) moves BOTH
    # sides of that comparison in lockstep and can never be caught,
    # confirmed live by reproducing the reviewer's exact mutation before
    # writing this fix. `expected_ids` is captured ONCE, above, from the
    # untouched --consumers document, so it is immune to any such
    # in-loop truncation.
    on_disk_ids = set()
    for out_path in glob.glob(os.path.join(args.out, "*.json")):
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


def cmd_summary(args):
    with open(args.consumers, "r", encoding="utf-8") as fh:
        consumers_doc = json.load(fh)
    projects = consumers_doc.get("projects", [])
    known_ids = {p["project_id"] for p in projects}
    audit_files = glob.glob(os.path.join(args.audits, "*.json"))
    migration_files = glob.glob(os.path.join(args.migrations, "*.json")) if args.migrations and os.path.isdir(args.migrations) else []

    # T177 Round 1 B4 fix: coverage MUST be counted by DISTINCT
    # enumerated project_id, never by raw FILE count -- the prior code
    # counted one unit per migration-record FILE and one unit per
    # audit-record FILE, so N duplicate copies of a single project's
    # record (a stray re-run leftover, a defect that writes the same id
    # twice) inflated the numerator by N, and `coverage` could read 1.0
    # on a directory holding only copies of ONE real record (reproduced
    # live: 19 copies of one migration record + 19 empty audit files
    # gave coverage=1.0 exit=0). `outcome_by_id` is keyed by
    # project_id, so a duplicate file for the SAME id contributes
    # exactly once (last-write-wins by lexicographic filename order, an
    # arbitrary but deterministic tiebreak); a record naming a
    # project_id OUTSIDE the enumerated set is rejected and reported,
    # never silently counted.
    outcome_by_id = {}
    unknown_ids_seen = set()
    for mf in sorted(migration_files):
        try:
            with open(mf, "r", encoding="utf-8") as fh:
                rec = json.load(fh)
        except (OSError, ValueError):
            continue
        pid = rec.get("project_id")
        if not pid:
            continue
        if pid not in known_ids:
            unknown_ids_seen.add(pid)
            continue
        outcome_by_id[pid] = "MIGRATED" if rec.get("outcome") == "MIGRATED" else rec.get("not_migrated_reason", "UNKNOWN")

    migrated_ids = {pid for pid, outcome in outcome_by_id.items() if outcome == "MIGRATED"}
    migrated = len(migrated_ids)
    not_migrated_by_reason = {}
    for pid, outcome in outcome_by_id.items():
        if outcome == "MIGRATED":
            continue
        not_migrated_by_reason[outcome] = not_migrated_by_reason.get(outcome, 0) + 1
    not_migrated_total = sum(not_migrated_by_reason.values())

    # `audited` likewise counts DISTINCT enumerated ids with a real
    # report on disk, never raw file count (the same B4 defect class).
    audited_ids = set()
    for af in audit_files:
        try:
            with open(af, "r", encoding="utf-8") as fh:
                arec = json.load(fh)
        except (OSError, ValueError):
            continue
        apid = arec.get("project_id")
        if apid in known_ids:
            audited_ids.add(apid)

    coverage = (migrated + not_migrated_total) / len(projects) if projects else 0.0

    doc = {
        "schema": "summary/v1",
        "projects": len(projects),
        "audited": len(audited_ids),
        "migrated": migrated,
        "not_migrated_by_reason": not_migrated_by_reason,
        "coverage": coverage,
    }
    if unknown_ids_seen:
        doc["unknown_ids_ignored"] = sorted(unknown_ids_seen)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
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
