#!/usr/bin/env python3
# ============================================================================
# test_bulk_classify_mutate.py — mutant table for the sync BULK-classification fix
# ============================================================================
# Purpose      Single-edit mutants of codegraph_safe.sh / codegraph_safe_helper.py, each of
#              which MUST turn the named unit case(s) of test_unit_safe.sh RED (paired
#              §1.1 mutation: a test that cannot fail is decoration). Consumed by
#              test_bulk_classify_mutations.sh.
# Usage        test_bulk_classify_mutate.py --list                 (id<TAB>red-cases<TAB>what)
#              test_bulk_classify_mutate.py --apply <id> <copy-dir> (edits the copy in place)
# Inputs       a COPY of the codegraph tooling dir (never the real tree)
# Outputs      exit 0 applied (anchor found EXACTLY once) / 1 anchor missing or ambiguous / 2 usage
# Side effects edits files under <copy-dir> only
# Dependencies python3 (stdlib)
# Cross-refs   test_unit_safe.sh U31-U43, ../codegraph_safe.sh, ../codegraph_safe_helper.py
# ============================================================================
import os
import sys

SAFE = "codegraph_safe.sh"
HELP = "codegraph_safe_helper.py"

# id, file, anchor (must occur exactly once), replacement, RED cases, description
MUTANTS = [
    ("MB1", SAFE,
     '1) say "sync classification: BULK (reason=pending>=threshold; $pout)" ;;',
     '1) BULK=0; say "sync classification: INCREMENTAL (reason=pending>=threshold; $pout)" ;;',
     "U31,U33",
     "big backlog still INCREMENTAL (the original 2026-09-24 defect)"),
    ("MB2", SAFE,
     '*) say "sync classification: BULK (reason=pending-probe UNKNOWN',
     '*) BULK=0; say "sync classification: INCREMENTAL (reason=pending-probe UNKNOWN',
     "U36",
     "UNKNOWN backlog read as small (fail-open)"),
    ("MB3", SAFE,
     '--bulk) FORCE_BULK=1; shift ;;',
     '--bulk) FORCE_BULK=0; shift ;;',
     "U34",
     "--bulk flag ignored"),
    ("MB4", SAFE,
     '[ "$PATCHES" = all ] || pargs="--patches $PATCHES --print-bin"',
     '[ "$PATCHES" = all ] || pargs="--print-bin"',
     "U38",
     "--patches not forwarded to the patch tool"),
    ("MB5", SAFE,
     'PATCHES="${CG_SAFE_PATCHES:-fkidx1,resolve1}"',
     'PATCHES="${CG_SAFE_PATCHES:-all}"',
     "U38",
     "default patch set widened to the untested patches (lockfix1, datafrag1)"),
    ("MB6", HELP,
     "where status = 'pending' limit ?",
     "where status in ('pending','failed') limit ?",
     "U35",
     "probe counts failed retry-tail rows as pending"),
    ("MB7", HELP,
     "limit ?)\", (cap,)).fetchone()[0]",
     "limit ?)\", (10**12,)).fetchone()[0]",
     "U37",
     "probe unbounded (full COUNT over the pending rows)"),
    ("MB8", HELP,
     "hit = n >= threshold",
     "hit = n > threshold",
     "U31,U41",
     "threshold exclusive (off-by-one)"),
    ("MB9", HELP,
     'res("pending_zero", pn == 0,',
     'res("pending_zero", True,',
     "U39",
     "verify no longer asserts pending==0"),
    ("MB10", HELP,
     'f["nodes_present"] = c.execute("select 1 from nodes limit 1").fetchone() is not None',
     'f["nodes_present"] = c.execute("select count(*) from nodes").fetchone()[0] > 0',
     "U42",
     "dbinfo COUNT(*)s the nodes table again"),
    ("MB11", HELP,
     'res("pending_zero", False, f"cannot evaluate pending',
     'res("pending_zero", True, f"cannot evaluate pending',
     "U36",
     "verify fail-open when pending cannot be evaluated"),
]


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--list":
        for mid, _f, _a, _r, red, what in MUTANTS:
            print(f"{mid}\t{red}\t{what}")
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "--apply":
        mid, d = sys.argv[2], sys.argv[3]
        for m in MUTANTS:
            if m[0] != mid:
                continue
            path = os.path.join(d, m[1])
            src = open(path, encoding="utf-8").read()
            n = src.count(m[2])
            if n != 1:
                print(f"anchor for {mid} occurs {n} times in {m[1]} (need exactly 1)", file=sys.stderr)
                return 1
            open(path, "w", encoding="utf-8").write(src.replace(m[2], m[3]))
            return 0
        print(f"unknown mutant {mid}", file=sys.stderr)
        return 1
    print("usage: --list | --apply <id> <copy-dir>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
