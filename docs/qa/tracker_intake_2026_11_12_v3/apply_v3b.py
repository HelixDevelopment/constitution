#!/usr/bin/env python3
# docs/qa/tracker_intake_2026_11_12_v3/apply_v3b.py -- one-shot data change of the tracker-intake
# vehicle, round 3, second step: carries out operator decision 8 of
# docs/operator_decisions/2026-11-12_relayed_decisions.md (2026-11-13, relayed, not verbatim):
# CON-243 and CON-262 are one defect; CON-262 is the canonical head (section 11.4.214: older, open,
# carries the measured census); CON-243 and CON-308 are closed Obsolete duplicate-of CON-262.
#
# Every change goes through the workable-items engine (update, close, obsolete-details); nothing
# writes the SQLite file directly. The script refuses to run unless the database holds the exact
# texts it was written against (each replaced text occurs exactly once, CON-243 and CON-262 are
# Queued, CON-308 is Reopened), so a second run changes nothing and exits 1.
#
# Usage: python3 -I apply_v3b.py --wi <workable-items binary> --db docs/workable_items.db [--dry-run]
# Run from the repository root. Exit: 0 applied; 1 precondition failed (nothing written); 2 usage;
# 3 an engine call failed (the calls before it stay applied; the log names the failed call).
# Evidence class: gate-logic only (section 11.4.289); it records tracker text, it proves no defect.
import argparse
import sqlite3
import subprocess
import sys

REC = "docs/operator_decisions/2026-11-12_relayed_decisions.md"
DEC = "operator decision 2026-11-13 (relayed, not verbatim; " + REC + ", decision 8)"
UMB = "umbrella CON-299 (tracker intake umbrella)"

# CON-262: its round-2/round-3 context paragraph is replaced (it said UNDECIDED and owed)
OLD_262 = (
    "Context added 2026-11-13 by the tracker-intake vehicle (umbrella CON-299; section 11.4.214, link only for an "
    "open match): the retest vehicle (lander list docs/qa/tracker_intake_2026_11_12/sources/rtfix_lander_items.md, "
    "item C-2) makes six fastcycle units exit 77 with reason=topology_unsupported in the canon-alone layout, so "
    "run_all.sh reports FAIL for them while run_full_suite.sh reports SKIP. CON-308 (run_all.sh counts rc 77 as "
    "FAIL, lander item C-2), which records this, was closed duplicate-of this item in round 2 of the intake vehicle "
    "and reopened on 2026-11-13: the match has two open heads, this item and CON-243, so its verdict is UNDECIDED "
    "with candidate links to both (section 11.4.214(0) and (3)); the operator decision whether CON-243 and this item "
    "are one defect is owed (docs/operator_decisions/2026-11-12_relayed_decisions.md). A paired mutant for the "
    "run_all.sh mapping of 77 belongs to this item's acceptance. Candidate duplicate: CON-243 (the same run_all.sh "
    "behaviour plus tier awareness); merge UNDECIDED (section 11.4.214(3)).")
NEW_262 = (
    "Context added 2026-11-13 by the tracker-intake vehicle (" + UMB + "; section 11.4.214): the retest vehicle "
    "(lander list docs/qa/tracker_intake_2026_11_12/sources/rtfix_lander_items.md, item C-2) makes six fastcycle "
    "units exit 77 with reason=topology_unsupported in the canon-alone layout, so run_all.sh reports FAIL for them "
    "while run_full_suite.sh reports SKIP. By " + DEC + ", this item and CON-243 (run_all.sh counts exit 77 as FAIL, "
    "tier awareness) are one defect, and this item is the canonical head: it is older (created 2026-11-06 against "
    "2026-11-11), open, and it carries the measured census and the acceptance. CON-243 and CON-308 (run_all.sh "
    "counts rc 77 as FAIL, lander item C-2) are closed duplicate-of this item.\n"
    "Acceptance carried from CON-243 (run_all.sh tier awareness for the heavy L29 test), so that nothing of it is "
    "lost: run_all.sh does not run the heavy L29 test in the default tier, or reports it as a heavy-tier SKIP with "
    "its reason. A paired mutant for the run_all.sh mapping of 77 belongs to this item's acceptance.")

OLD_243 = (
    "Context added 2026-11-13 by the tracker-intake vehicle (umbrella CON-299; section 11.4.214, link only for an "
    "open match): candidate duplicates CON-262 (wider SKIP class, run_all.sh labels exit 77 FAIL) and CON-308 "
    "(run_all.sh counts rc 77 as FAIL, from the retest lander list item C-2); merge UNDECIDED (section "
    "11.4.214(3)). The operator decision whether this item and CON-262 are one defect is owed "
    "(docs/operator_decisions/2026-11-12_relayed_decisions.md).")
NEW_243 = (
    "Duplicate check (section 11.4.214): SAME-DEFECT of CON-262 (wider SKIP class, run_all.sh labels exit 77 FAIL), "
    "by " + DEC + ". CON-262 is the canonical head: it is older, open, and it carries the measured census. The tier "
    "awareness asked here is carried into the acceptance of CON-262, so nothing of this item is lost.\n"
    "Context (2026-11-13, tracker-intake vehicle, " + UMB + "): CON-308 (run_all.sh counts rc 77 as FAIL, lander "
    "item C-2) is closed duplicate-of the same head.")

OLD_308_DUP = (
    "Duplicate check (section 11.4.214): UNDECIDED; candidate duplicates CON-262 (wider SKIP class, run_all.sh labels "
    "exit 77 FAIL) and CON-243 (run_all.sh counts exit 77 as FAIL, tier awareness). Both are open and neither is "
    "linked duplicate-of the other, so the match has two distinct heads: section 11.4.214(0) gives UNDECIDED and "
    "clause (3) gives mint-with-link, never a closure onto one head. The operator decision whether CON-243 and "
    "CON-262 are one defect is owed (docs/operator_decisions/2026-11-12_relayed_decisions.md, section Owed "
    "decisions); once it is recorded this item is closed duplicate-of the surviving head.")
NEW_308_DUP = (
    "Duplicate check (section 11.4.214): SAME-DEFECT of CON-262 (wider SKIP class, run_all.sh labels exit 77 FAIL), "
    "by " + DEC + " that CON-243 (run_all.sh counts exit 77 as FAIL, tier awareness) and CON-262 are one defect: "
    "CON-243 is closed duplicate-of CON-262, so the match has a single open head. Round 3 kept this item open as "
    "UNDECIDED (two open heads, section 11.4.214(0)) until that decision.")
OLD_308_STALE = (
    "\nStale obsolete_details row (CON-340, reopen leaves the obsolete_details row): the row duplicate-of CON-262 from "
    "the round-2 closure stays because no engine command removes it; it is not a closure, the status column and the "
    "Duplicate check line above are the source.")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--wi", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    c = sqlite3.connect("file:%s?mode=ro" % a.db, uri=True)
    row = {r[0]: (r[1], r[2]) for r in c.execute(
        "select atm_id, status, description from items where atm_id in ('CON-243','CON-262','CON-308')")}
    c.close()
    want = {"CON-243": "Queued", "CON-262": "Queued", "CON-308": "Reopened"}
    bad = [i for i in want if i not in row or row[i][0] != want[i]]
    if bad:
        print("precondition: status not as expected for " + ",".join(bad) + ": nothing written")
        return 1
    plan = {"CON-262": [(OLD_262, NEW_262)], "CON-243": [(OLD_243, NEW_243)],
            "CON-308": [(OLD_308_DUP, NEW_308_DUP), (OLD_308_STALE, "")]}
    new = {}
    for iid, reps in plan.items():
        d = row[iid][1]
        for old, rep in reps:
            if d.count(old) != 1:
                print("precondition: %s holds the replaced text %d times (want 1): nothing written" % (iid, d.count(old)))
                return 1
            d = d.replace(old, rep)
        new[iid] = d

    def call(args):
        print("$ workable-items " + " ".join(x if len(x) < 90 else "<%d chars>" % len(x) for x in args))
        if a.dry_run:
            return
        p = subprocess.run([a.wi] + args, capture_output=True, text=True)
        out = (p.stdout + p.stderr).strip()
        print("  -> rc=%d %s" % (p.returncode, out[:300]))
        if p.returncode != 0:
            raise SystemExit(3)

    for iid in ("CON-262", "CON-243", "CON-308"):
        call(["update", "--db", a.db, "--id", iid, "--description", new[iid]])
    for iid in ("CON-243", "CON-308"):
        call(["close", iid, "--db", a.db, "--status", "obsolete", "--evidence", REC])
        call(["obsolete-details", iid, "--db", a.db, "--since", "2026-11-13", "--reason", "duplicate-of",
              "--superseding", "CON-262", "--evidence", REC])
    print("RESULT: %s" % ("DRY-RUN" if a.dry_run else "APPLIED"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
