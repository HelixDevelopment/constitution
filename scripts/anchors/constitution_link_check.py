#!/usr/bin/env python3
"""constitution_link_check.py — verify every §-citation in a corpus of files
resolves against constitution_index.yaml. See
specs/003-reorganize-constitution-yaml/contracts/link-checker-cli.md.
"""
import argparse, glob, os, re, sys
import yaml

# Restricted to the §11.4.M family per contracts/link-checker-cli.md's own
# stated scope (L-001/L-006: "a citation §11.4.M" / "a §11.4\.\d+ regex over
# prose text") — the plan's own literal `r'§(\d+(?:\.\d+)+)'` was BROADER
# than its contract and, run for real, wrongly flagged 3057 citations to a
# DIFFERENT numbering family (§1.1 — the mutation-testing convention with
# zero heading-form definition anywhere, per this same corpus's own earlier
# regression-fix finding; §2.1/§9.2/§12.6/§7.1 — other top-level sections
# outside this feature's §11.4.x-Anchor scope) as UNRESOLVED, none of which
# the contract ever asked this checker to verify. An optional trailing
# dotted-letter suffix is captured too, so a real sub-anchor id like
# `§11.4.10.A` resolves DIRECTLY against the index rather than only via the
# L-004 parent-stripping fallback (§11.4.10.A is itself a genuine, distinct
# heading in this corpus, not a mere sub-clause of §11.4.10). A trailing
# PARENTHESIZED sub-clause suffix (e.g. `§11.4.4(b)`) is deliberately left
# OUTSIDE the character class — the match naturally stops at `11.4.4`,
# which is exactly L-004's parent-id resolution, achieved with no extra code.
CITATION_RE = re.compile(r'§(11\.4(?:\.\d+)+(?:\.[A-Za-z])?)')
FABRICATED_NEEDLE = "99999"  # L-003's negative control: guaranteed absent from any real index


def _resolve(anchor_id: str, known_ids: set) -> bool:
    if anchor_id in known_ids:
        return True
    # L-004: a sub-clause citation (e.g. "11.4.115.G") resolves to its parent anchor.
    parts = anchor_id.split(".")
    while len(parts) > 3:
        parts = parts[:-1]
        if ".".join(parts) in known_ids:
            return True
    return False


def _selftest(known_ids: set) -> bool:
    real_id = sorted(known_ids)[0]
    if not _resolve(real_id, known_ids):
        sys.stderr.write(f"FATAL: positive control {real_id} did not resolve — instrument blind\n")
        return False
    print(f"positive control resolved: {real_id}")
    if _resolve(FABRICATED_NEEDLE, known_ids):
        sys.stderr.write(f"FATAL: negative control {FABRICATED_NEEDLE} wrongly resolved — over-broad matcher\n")
        return False
    print(f"negative control correctly unresolved: {FABRICATED_NEEDLE}")
    return True


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--index", required=True)
    p.add_argument("--corpus", nargs="+", required=True)
    p.add_argument("--selftest", action="store_true")
    args = p.parse_args()

    with open(args.index) as f:
        idx = yaml.safe_load(f)
    known_ids = {a["id"] for a in idx["anchors"]}

    if args.selftest and not _selftest(known_ids):
        sys.exit(2)

    unresolved = []
    for target in args.corpus:
        paths = glob.glob(os.path.join(target, "**", "*.md"), recursive=True) \
            if os.path.isdir(target) else [target]
        for path in paths:
            with open(path, errors="replace") as f:
                text = f.read()
            for m in CITATION_RE.finditer(text):
                if not _resolve(m.group(1), known_ids):
                    unresolved.append((path, m.group(1)))

    if unresolved:
        for path, cid in unresolved[:50]:
            print(f"UNRESOLVED: §{cid} in {path}")
        print(f"{len(unresolved)} unresolved citation(s)")
        sys.exit(1)
    print("all citations resolved")
    sys.exit(0)


if __name__ == "__main__":
    main()
