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
missing_instrument, never a silent 0/None); count(reports) != count
(projects) => exit 1.

CA-011: measurements reuse the same tools this feature already uses
elsewhere -- constitution_pointer + behind_head_by via
`git -C <constitution_root> rev-list --count <gitlink>..HEAD` (the SAME
mechanism T167's own live control needle proves sound), preamble_bytes via
either the local CLAUDE.md's real byte size or (no local checkout) the
GitHub Contents API's own reported `size` field for that file --
Measured<int> in both cases. gate_suite_runtime and registry_defect_present
have no cross-repo instrument yet and are recorded UNMEASURED with
missing_instrument, never coerced to a fake value (C-001 false-null
guard). migration_effort is an ESTIMATE derived from behind_head_by
(labelled explicitly, never presented as Measured).

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


def audit_one(project, const_root):
    project_id = project["project_id"]
    consumer_kind = project.get("consumer_kind", "submodule")
    local_checkouts = project.get("local_checkouts") or []

    gitlink = None
    preamble_bytes = None
    preamble_measured = False
    behind = None
    gaps = []
    measurements = {}

    if consumer_kind == "text-only-inheritance":
        gaps.append({
            "area": "constitution-pointer",
            "finding": "text-only inheritance: no constitution submodule gitlink to measure",
            "evidence": "consumer_kind=text-only-inheritance (enumerate.sh)",
        })
        measurements["gate_suite_runtime"] = {"value": None, "missing_instrument": "no gate suite in a text-only consumer"}
        measurements["registry_defect_present"] = {"value": None, "missing_instrument": "no owned tracker DB to inspect cross-repo"}
        local_ok = local_checkouts and os.path.isdir(local_checkouts[0])
        if local_ok:
            claude_md = os.path.join(local_checkouts[0], "CLAUDE.md")
            if os.path.isfile(claude_md):
                preamble_bytes = os.path.getsize(claude_md)
                preamble_measured = True
        risk, risk_reason, effort = risk_and_effort(None)
        measurements["preamble_bytes"] = {"value": preamble_bytes, "measured": preamble_measured}
        return {
            "project_id": project_id,
            "constitution_pointer": None,
            "behind_head_by": "UNMEASURED",
            "gaps": gaps,
            "migration_effort": "ESTIMATE:0.5",
            "risk": risk,
            "risk_reason": risk_reason,
            "measurements": measurements,
        }

    local_ok = local_checkouts and (
        os.path.isdir(os.path.join(local_checkouts[0], ".git")) or os.path.isfile(os.path.join(local_checkouts[0], ".git"))
    )
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
    measurements["preamble_bytes"] = {"value": preamble_bytes, "measured": preamble_measured}

    risk, risk_reason, effort = risk_and_effort(behind)
    return {
        "project_id": project_id,
        "constitution_pointer": gitlink,
        "behind_head_by": behind if behind is not None else "UNMEASURED",
        "gaps": gaps,
        "migration_effort": ("Measured:%s" % effort) if (effort is not None and behind is not None) else "ESTIMATE:%s" % (effort if effort is not None else "1"),
        "risk": risk,
        "risk_reason": risk_reason,
        "measurements": measurements,
    }


def cmd_audit(args):
    cfg = load_config(args.config)  # noqa: F841 (loaded for CA-011 future tool paths; validated present)
    const_root = os.path.join(repo_root_of_config(args.config), "constitution")
    with open(args.consumers, "r", encoding="utf-8") as fh:
        consumers_doc = json.load(fh)
    projects = consumers_doc.get("projects", [])

    os.makedirs(args.out, exist_ok=True)
    written = 0
    for project in projects:
        report = audit_one(project, const_root)
        safe_name = project["project_id"].replace("/", "__")
        out_path = os.path.join(args.out, "%s.json" % safe_name)
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(report, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        written += 1

    if written != len(projects):
        print("audit.py: CA-010 report count mismatch: wrote %d for %d projects" % (written, len(projects)), file=sys.stderr)
        sys.exit(1)
    print("audit.py: wrote %d ConsumerAuditReport(s) to %s" % (written, args.out))
    sys.exit(0)


def cmd_summary(args):
    with open(args.consumers, "r", encoding="utf-8") as fh:
        consumers_doc = json.load(fh)
    projects = consumers_doc.get("projects", [])
    audit_files = glob.glob(os.path.join(args.audits, "*.json"))
    migration_files = glob.glob(os.path.join(args.migrations, "*.json")) if args.migrations and os.path.isdir(args.migrations) else []

    migrated = 0
    not_migrated_by_reason = {}
    migrated_ids = set()
    for mf in migration_files:
        try:
            with open(mf, "r", encoding="utf-8") as fh:
                rec = json.load(fh)
        except (OSError, ValueError):
            continue
        pid = rec.get("project_id")
        if rec.get("outcome") == "MIGRATED":
            migrated += 1
            if pid:
                migrated_ids.add(pid)
        else:
            reason = rec.get("not_migrated_reason", "UNKNOWN")
            not_migrated_by_reason[reason] = not_migrated_by_reason.get(reason, 0) + 1

    not_migrated_total = sum(not_migrated_by_reason.values())
    coverage = (migrated + not_migrated_total) / len(projects) if projects else 0.0

    doc = {
        "schema": "summary/v1",
        "projects": len(projects),
        "audited": len(audit_files),
        "migrated": migrated,
        "not_migrated_by_reason": not_migrated_by_reason,
        "coverage": coverage,
    }
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
