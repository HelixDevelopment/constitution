#!/usr/bin/env python3
# docs/qa/tracker_intake_2026_11_12_v3/apply_v3.py -- one-shot data fix of the tracker-intake vehicle,
# round 3 (after the round-2 independent review NO-GO in
# docs/qa/tracker_intake_2026_11_12_v3/sources/review_tracker_intake_v2.md).
#
# Every change goes through the workable-items engine (add, reopen, update); nothing writes the
# SQLite file directly. The script refuses to run unless the database holds the exact texts it was
# written against (each replaced text must occur exactly once, CON-308 must still be Obsolete, the
# new titles must not exist), so a second run, or a run on another database, changes nothing and
# exits 1.
#
# Usage: python3 -I apply_v3.py --wi <workable-items binary> --db docs/workable_items.db
#        [--by <states-updated-by handle>] [--dry-run] [--inventory OUT.tsv]
#   --inventory  write the duplicate-check inventory of the new items (each new item against every
#                open item, by significant title+What word overlap and shared file names) and exit
# Run from the repository root. Exit: 0 applied; 1 precondition failed (nothing written); 2 usage;
# 3 an engine call failed (the calls before it stay applied; the log names the failed call).
# Evidence class: gate-logic only (section 11.4.289); it records tracker text, it proves no defect.
import argparse
import re
import sqlite3
import subprocess
import sys

ORIGIN_LINE = ("Origin: tracker-intake vehicle 2026-11-12 (sections 11.4.202, 11.4.210, 11.4.148, 11.4.197, 11.4.214); "
               "intake only, not a fix. Ids minted here on base 02c10935 are re-minted by the lander if they collide "
               "(section 11.4.214).")
V3 = "docs/qa/tracker_intake_2026_11_12_v3/"
REVIEW = V3 + "sources/review_tracker_intake_v2.md"
REC = "docs/operator_decisions/2026-11-12_relayed_decisions.md"
REPRO = V3 + "engine_repro.txt"
INCIDENT = V3 + "inventory/r2_1_reopen.txt"
METHOD = (" Method: every open item compared by title and What-line word overlap and by shared file names "
          "(" + V3 + "inventory/dup_candidates_v3.tsv).")
UMB = "umbrella CON-299 (tracker intake umbrella)"
ENGINE_OTHERS = ("CON-336 (workable-items add history attribution) and CON-337 (workable-items fail-open on update "
                 "and add) are other engine defects")
REPRO_CTX = ("Reproduced on the host on a scratch copy of docs/workable_items.db at 63f80e52, every write through the "
             "engine: " + REPRO + " section {sec} (script engine_repro.sh in the same directory, checksums in its "
             "SHA256SUMS). The cause is not investigated; the source file named in the scope is read from the command "
             "table only.")


def new_items():
    """(key, type, severity, title, description, signature, section) -- ids are minted in this order."""
    g = []
    g.append(("G1", "Bug", "Low", "workable-items close rewrites created_at to the time of the close (round-2 review R2-9)",
              "**What:** The engine `close` command sets the item's created_at to the time of the close. Measured on a "
              "copy: created_at read 2026-11-12 22:48:51 before the close and the close time after it. Every closed item "
              "loses its creation time, which distorts age, lead-time and burn-down figures. CON-308 (run_all.sh rc 77 counted "
              "as FAIL) is one such item: its round-2 close moved created_at from 2026-11-12 22:48:51 to 2026-11-13 "
              "11:27:03, and no engine command restores it.\n\n"
              "**Affected scope / file-scope manifest:**\nscripts/workable-items/cmd/workable-items/crud.go (the close "
              "command; the exact line is UNCONFIRMED); its tests\n\n"
              "**Reproduction / context:**\n" + REPRO_CTX.format(sec="G1") + "\n\n"
              "**Acceptance criteria:**\nclose keeps created_at; a test with a paired mutant pins it; a recorded decision "
              "says whether the created_at of items closed earlier is restored from their history rows.\n\n"
              "Parent / links: round-2 review of this vehicle (" + REVIEW + ", finding R2-9); " + UMB + "\n"
              "Duplicate check (section 11.4.214): DISTINCT (no open item names close and created_at); " + ENGINE_OTHERS +
              "." + METHOD + "\n" + ORIGIN_LINE,
              "created_at after close equals the close time, not the creation time", "G1"))
    g.append(("G2", "Bug", "Low",
              "workable-items reopen leaves the obsolete_details row and the Obsolete-Details body line on a Reopened item, and validate accepts it (R2-9)",
              "**What:** After `reopen` of an Obsolete item the item is Reopened in Issues, but its obsolete_details row "
              "(reason and superseding id of the earlier closure) stays, its body still shows an Obsolete-Details line, "
              "and validate reports OK. A reader or a tool that trusts the row sees a closure that no longer holds. No "
              "engine command removes the row.\n\n"
              "**Affected scope / file-scope manifest:**\nscripts/workable-items/cmd/workable-items/mutate.go (reopen), "
              "scripts/workable-items/cmd/workable-items/obsolete.go; validate; their tests\n\n"
              "**Reproduction / context:**\n" + REPRO_CTX.format(sec="G2 and G3") + " Found on CON-308 (run_all.sh rc 77 "
              "counted as FAIL), which round 3 reopened (R2-1).\n\n"
              "**Acceptance criteria:**\nreopen removes or archives the obsolete_details row in the same transaction and "
              "records it in the history; validate fails on an obsolete_details row of an item that is not Obsolete; "
              "tests with paired mutants pin both.\n\n"
              "Parent / links: round-2 review of this vehicle (" + REVIEW + ", finding R2-9); " + UMB + "\n"
              "Duplicate check (section 11.4.214): DISTINCT (no open item names reopen and obsolete_details); "
              "{G3} (update drops the Reopened-Details line) and {G4} (superseding id that does not exist) are other "
              "defects of the same commands." + METHOD + "\n" + ORIGIN_LINE,
              "after reopen of an Obsolete item the obsolete_details row is still present and validate exits 0", "G2"))
    g.append(("G3", "Bug", "Low",
              "workable-items update re-renders the body header and drops the Reopened-Details and Evidence lines that reopen wrote",
              "**What:** `reopen` writes Reopened-Details and Evidence lines into the body header. A later `update "
              "--description` re-renders the header from the columns and drops both lines; only the history row keeps "
              "the reopen. The published Issues.md then shows no reopen record for the item.\n\n"
              "**Affected scope / file-scope manifest:**\nscripts/workable-items/cmd/workable-items/crud.go (update and "
              "the body rendering), scripts/workable-items/cmd/workable-items/mutate.go (reopen); their tests\n\n"
              "**Reproduction / context:**\n" + REPRO_CTX.format(sec="G3") + "\n\n"
              "**Acceptance criteria:**\nthe reopen record survives any later update, either as a column the renderer "
              "reads or by the renderer reading the history; a test with a paired mutant pins it.\n\n"
              "Parent / links: found while fixing round-2 review finding R2-1 (" + REVIEW + "); " + UMB + "\n"
              "Duplicate check (section 11.4.214): DISTINCT; {G2} (reopen leaves the obsolete_details row) is another "
              "defect of the same commands." + METHOD + "\n" + ORIGIN_LINE,
              "the body header keys after update lack Reopened-Details while the history keeps the reopen row", "G3"))
    g.append(("G4", "Bug", "Low",
              "workable-items obsolete-details and validate accept a superseding item that does not exist (round-2 review R2-6, D7a)",
              "**What:** `obsolete-details --reason duplicate-of --superseding <id>` writes the row when no item has "
              "that id, and validate then reports OK. A duplicate-of link can point at nothing, which section 11.4.214 "
              "chain resolution cannot follow.\n\n"
              "**Affected scope / file-scope manifest:**\nscripts/workable-items/cmd/workable-items/obsolete.go; "
              "validate; their tests\n\n"
              "**Reproduction / context:**\n" + REPRO_CTX.format(sec="G4") + " The round-2 reviewer saw the validate "
              "half with a hand-edited copy (mutant D7a); G4 reproduces both halves through the engine.\n\n"
              "**Acceptance criteria:**\nobsolete-details refuses a superseding id that is not an item (an anchor letter "
              "or 'none' stays legal); validate fails on such a row; tests with paired mutants pin both.\n\n"
              "Parent / links: round-2 review of this vehicle (" + REVIEW + ", finding R2-6); " + UMB + "\n"
              "Duplicate check (section 11.4.214): DISTINCT; {G2} (reopen leaves the obsolete_details row) is another "
              "defect of the same commands." + METHOD + "\n" + ORIGIN_LINE,
              "obsolete-details with a superseding id that is not an item exits 0 and validate exits 0", "G4"))
    return g


CON308_PARENT_OLD = "related CON-092, CON-098; umbrella CON-299"
CON308_PARENT_NEW = ("related CON-092 (fastcycle consumer-data guard), CON-098 (fastcycle tests that fail in the batch); "
                     + UMB)
CON308_DUP_NEW = (
    "Duplicate check (section 11.4.214): UNDECIDED; candidate duplicates CON-262 (wider SKIP class, run_all.sh labels "
    "exit 77 FAIL) and CON-243 (run_all.sh counts exit 77 as FAIL, tier awareness). Both are open and neither is linked "
    "duplicate-of the other, so the match has two distinct heads: section 11.4.214(0) gives UNDECIDED and clause (3) "
    "gives mint-with-link, never a closure onto one head. The operator decision whether CON-243 and CON-262 are one "
    "defect is owed (" + REC + ", section Owed decisions); once it is recorded this item is closed duplicate-of the "
    "surviving head. CON-145 and CON-261 name run_all.sh for other defects." + METHOD.replace("dup_candidates_v3.tsv", "")
    .replace("What-line", "description") + "\n"
    "Reopen record (section 11.4.34): reopened 2026-11-13 by AI, reason design-reconsidered, evidence " + INCIDENT +
    "; round 2 had closed it duplicate-of CON-262 (wider SKIP class) on one of the two open heads (round-2 review "
    "finding R2-1, " + REVIEW + "). The engine drops the Reopened-Details body line when the description is updated "
    "({G3}, update drops the Reopened-Details line), so the record is kept here and in the item history.\n"
    "Stale obsolete_details row ({G2}, reopen leaves the obsolete_details row): the row duplicate-of CON-262 from the "
    "round-2 closure stays because no engine command removes it; it is not a closure, the status column and the "
    "Duplicate check line above are the source.")
CON262_OLD = "The duplicate CON-308 that recorded this is closed Obsolete, duplicate-of this item."
CON262_NEW = ("CON-308 (run_all.sh counts rc 77 as FAIL, lander item C-2), which records this, was closed duplicate-of "
              "this item in round 2 of the intake vehicle and reopened on 2026-11-13: the match has two open heads, this "
              "item and CON-243, so its verdict is UNDECIDED with candidate links to both (section 11.4.214(0) and (3)); "
              "the operator decision whether CON-243 and this item are one defect is owed (" + REC + ").")
CON243_APPEND = (
    "\n\nContext added 2026-11-13 by the tracker-intake vehicle (umbrella CON-299; section 11.4.214, link only for an "
    "open match): candidate duplicates CON-262 (wider SKIP class, run_all.sh labels exit 77 FAIL) and CON-308 "
    "(run_all.sh counts rc 77 as FAIL, from the retest lander list item C-2); merge UNDECIDED (section 11.4.214(3)). "
    "The operator decision whether this item and CON-262 are one defect is owed (" + REC + ").")
CON299_OLD = "CON-338 (content lint wiring). UNKNOWN:"
CON299_NEW = ("CON-338 (content lint wiring). Round-2 review follow-ups (" + REVIEW + "): CON-308 (run_all.sh rc 77 "
              "counted as FAIL) reopened with an UNDECIDED verdict (R2-1); {G1} (close rewrites created_at) and {G2} "
              "(reopen leaves the obsolete_details row) for R2-9; {G3} (update drops the Reopened-Details line); {G4} "
              "(superseding item that does not exist) for R2-6. UNKNOWN:")
RELABEL = {
    "CON-304": [("umbrella CON-299; related CON-092, CON-093, CON-102\n",
                 "umbrella CON-299; related CON-092 (fastcycle consumer-data guard), CON-093 (fastcycle tests missing "
                 "consumer data), CON-102 (fastcycle consumer-data helper test)\n")],
    "CON-309": [("lander item C-3; related CON-092; umbrella",
                 "lander item C-3; related CON-092 (fastcycle consumer-data guard, section-level skip); umbrella")],
    "CON-314": [("CON-271 (commits whose Roadmap-Item trailer is not an engine id; another vehicle)",
                 "CON-271 (commits whose Roadmap-Item is not an item id; another vehicle)")],
    "CON-329": [("CON-271 (commits whose Roadmap-Item trailer is not an engine id; another vehicle)",
                 "CON-271 (commits whose Roadmap-Item is not an item id; another vehicle)")],
    "CON-321": [("CON-227 (other reviewer survivors, of the rel734 change, in the same script)",
                 "CON-227 (the other surviving reviewer mutants of tag_and_release.sh, from vehicle rel734)")],
    "CON-328": [("CON-227 (the rel734 reviewer survivors that the same family of tests must kill)",
                 "CON-227 (surviving reviewer mutants of tag_and_release.sh that the same family of tests must kill)")],
}
SHA_FAILOPEN = "fb1eaea4ec1634a399a55d2ad11e1bbe51e4889cbe2c6e4033752efd21684866"
ENV_OLD = "scratch copy of docs/workable_items.db at 1a307322; engine built from that tree"


def fill(text, ids):
    for k, v in ids.items():
        text = text.replace("{" + k + "}", v)
    if re.search(r"\{G\d\}", text):
        raise SystemExit("internal: an id placeholder is left in a text")
    return text


def one(text, old, iid):
    n = text.count(old)
    if n != 1:
        raise ValueError("%s: expected exactly one occurrence, found %d: %r" % (iid, n, old[:70]))


STOP = set("the a an on in of to is and or for with by from not no as at be it its this that are was when into "
           "item items workable engine what review round after before which measured every does section follow "
           "only both then still shows sets read time".split())


def sig_words(s):
    return {t for t in re.split(r"[^a-z0-9_]+", s.lower()) if len(t) >= 4 and t not in STOP and not t.isdigit()}


def inventory(db, out):
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    rows = list(con.execute("select atm_id, title, description from items where current_location='Issues' order by atm_id"))
    con.close()
    lines = ["new_item\topen_item\tshared_words\tshared_files\topen_title"]
    for key, _t, _s, title, desc, _sig, _sec in new_items():
        what = desc.split("\n\n", 1)[0]
        nw = sig_words(title + " " + what)
        nf = set(re.findall(r"[\w-]+\.(?:go|sh|py)\b", desc))
        scored = []
        for iid, otitle, odesc in rows:
            ow = sig_words(otitle + " " + odesc.split("\n\n", 1)[0])
            of = set(re.findall(r"[\w-]+\.(?:go|sh|py)\b", odesc))
            sw, sf = nw & ow, nf & of
            if sw or sf:
                scored.append((len(sf) * 3 + len(sw), iid, sw, sf, otitle))
        for score, iid, sw, sf, otitle in sorted(scored, key=lambda x: (-x[0], x[1]))[:8]:
            lines.append("%s\t%s\t%s\t%s\t%s" % (key, iid, ",".join(sorted(sw)), ",".join(sorted(sf)), otitle[:100]))
    open(out, "w").write("\n".join(lines) + "\n")
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--wi")
    ap.add_argument("--db", required=True)
    ap.add_argument("--by", default="Claude (tracker-intake round-3 fixer, Opus 5.5)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--inventory")
    a = ap.parse_args(argv)
    if a.inventory:
        return inventory(a.db, a.inventory)
    if not a.wi:
        print("usage: --wi is required", file=sys.stderr)
        return 2
    con = sqlite3.connect("file:%s?mode=ro" % a.db, uri=True)
    desc = {i: d for i, d in con.execute("select atm_id, description from items")}
    status = {i: s for i, s in con.execute("select atm_id, status from items")}
    titles = {t for (t,) in con.execute("select title from items")}
    env = {i: e for i, e in con.execute("select atm_id, reproduction_env from items where atm_id in ('CON-336','CON-337')")}
    nums = [int(i.split("-")[1]) for i in desc if i.startswith("CON-")]
    con.close()
    try:
        if not status.get("CON-308", "").startswith("Obsolete"):
            raise ValueError("CON-308 is not Obsolete (status %r)" % status.get("CON-308"))
        for _k, _t, _s, title, _d, _g, _c in new_items():
            if title in titles:
                raise ValueError("an item titled %r already exists" % title[:60])
        plan = {}
        d = desc["CON-308"]
        one(d, CON308_PARENT_OLD, "CON-308")
        dl = [l for l in d.split("\n") if l.startswith("Duplicate check (section 11.4.214): SAME-DEFECT of CON-262")]
        if len(dl) != 1:
            raise ValueError("CON-308: the round-2 SAME-DEFECT line is not there exactly once")
        plan["CON-308"] = d.replace(CON308_PARENT_OLD, CON308_PARENT_NEW).replace(dl[0], CON308_DUP_NEW)
        one(desc["CON-262"], CON262_OLD, "CON-262")
        plan["CON-262"] = desc["CON-262"].replace(CON262_OLD, CON262_NEW)
        if CON243_APPEND.strip() in desc["CON-243"]:
            raise ValueError("CON-243 already carries the appended text")
        plan["CON-243"] = desc["CON-243"] + CON243_APPEND
        one(desc["CON-299"], CON299_OLD, "CON-299")
        plan["CON-299"] = desc["CON-299"].replace(CON299_OLD, CON299_NEW)
        for iid, pairs in RELABEL.items():
            t = desc[iid]
            for old, new in pairs:
                one(t, old, iid)
                t = t.replace(old, new)
            plan[iid] = t
        for iid in ("CON-336", "CON-337"):
            if env.get(iid) != ENV_OLD:
                raise ValueError("%s: reproduction_env is not the round-2 text" % iid)
    except (ValueError, KeyError) as e:
        print("precondition: %s" % e, file=sys.stderr)
        return 1

    def call(args):
        print("$ workable-items " + " ".join(x if len(x) < 90 else "<%d chars>" % len(x) for x in args))
        if a.dry_run:
            return
        p = subprocess.run([a.wi] + args, capture_output=True, text=True)
        out = (p.stdout + p.stderr).strip()
        print("  -> rc=%d %s" % (p.returncode, out[:300]))
        if p.returncode != 0:
            raise SystemExit(3)

    # 1. new items first, so the other texts can name their ids
    ids = {}
    nxt = max(nums) + 1
    for key, typ, sev, title, _d, _sig, _sec in new_items():
        ids[key] = "CON-%03d" % nxt
        nxt += 1
    for key, typ, sev, title, d, sig, sec in new_items():
        args = ["add", typ, sev, "--db", a.db, "--id", ids[key], "--title", title, "--description", fill(d, ids),
                "--created-by", "Claude",
                "--reproduction-state", "reproduced-host-fixture", "--investigation-state", "not-started",
                "--states-updated-by", a.by, "--reproduction-surface", "host-only", "--reproduction-evidence", REPRO,
                "--reproduction-env", "scratch copy of docs/workable_items.db at 63f80e52; engine built from that tree",
                "--reproduction-signature", sig,
                "--reproduction-red-cmd", "bash " + V3 + "engine_repro.sh <workable-items binary> <scratch copy of "
                "docs/workable_items.db> <open item id> <obsolete item id> (section " + sec + ")"]
        call(args)
    # 2. R2-1: reopen CON-308 (mint-with-link keeps it open), then its description
    call(["reopen", "--db", a.db, "--id", "CON-308", "--why", "design-reconsidered", "--who", "AI", "--when", "2026-11-13",
          "--incident", INCIDENT])
    for iid in sorted(plan):
        call(["update", "--db", a.db, "--id", iid, "--description", fill(plan[iid], ids)])
    # 3. R2-11: the evidence sha256 into the state lines of CON-336 and CON-337
    for iid in ("CON-336", "CON-337"):
        call(["update", "--db", a.db, "--id", iid, "--reproduction-env",
              ENV_OLD + "; evidence sha256 " + SHA_FAILOPEN, "--states-updated-by", a.by])
    print("new ids: " + ", ".join("%s=%s" % kv for kv in sorted(ids.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
