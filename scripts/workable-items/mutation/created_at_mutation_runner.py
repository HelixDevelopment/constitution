#!/usr/bin/env python3
"""Paired-mutation runner for CON-339 (items.created_at preserved by every
lifecycle command; `restore-created-at`).

Each mutant is an exact, unique source replacement. For every mutant the runner
builds a private mirror of the constitution tree (the mirror and the
replacement are the ones states_mutation_runner.py uses, loaded from that file),
applies the mutant to the copy, and runs

    go test -count=1 -run '^(TestCON339_|TestRestoreCreatedAt)' ./cmd/workable-items/

The mutant is KILLED when that run fails and the package still compiles. The
unmutated mirror must PASS first (control); a mutant whose anchor is absent or
not unique is a runner failure (STALE), and a mutant that does not compile is a
runner failure (BUILD-BROKEN), never counted as killed.

Exit 0 only when the control passes and every mutant is killed.

Usage: python3 -I created_at_mutation_runner.py [--only NAME[,NAME...]] [--list] [--keep]
Evidence: one line per mutant on stdout, `KILLED|SURVIVED|STALE|BUILD-BROKEN <name> ...`.
Evidence class: gate-logic / unit (section 11.4.289) — the real engine tests on
real SQLite files.
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = "cmd/workable-items"
RUN = "^(TestCON339_|TestRestoreCreatedAt)"

_spec = importlib.util.spec_from_file_location("states_mutation_runner",
                                               os.path.join(HERE, "states_mutation_runner.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)
build_mirror, apply = _base.build_mirror, _base.apply

# (name, file relative to the module, exact old text, new text, intent)
MUTANTS = [
    # --- close (root cause 1)
    ("close-insert-omits-created-at", PKG + "/crud.go",
     "representation, destination, logic_group, created_at, `+statesInsertCols+`)",
     "representation, destination, logic_group, last_modified, `+statesInsertCols+`)",
     "close re-inserts without created_at (the column default stamps the close time)"),
    ("close-reads-now", PKG + "/crud.go",
     "SELECT created_at FROM items WHERE atm_id=? AND current_location='Issues' AND representation=?",
     "SELECT datetime('now') FROM items WHERE atm_id=? AND current_location='Issues' AND representation=?",
     "close carries the current time instead of the row's created_at"),
    # --- md-to-db (root cause 2)
    ("md-to-db-insert-omits-created-at", PKG + "/db.go",
     "representation, closure_date, round, commit_ref, created_at, ` + statesInsertCols + `)",
     "representation, closure_date, round, commit_ref, last_modified, ` + statesInsertCols + `)",
     "md-to-db re-inserts without created_at"),
    ("md-to-db-coalesce-inverted", PKG + "/db.go",
     "COALESCE(?, datetime('now'))",
     "COALESCE(datetime('now'), ?)",
     "md-to-db always stamps the sync time"),
    ("md-to-db-no-arg", PKG + "/db.go",
     "\t\t\tcreatedAt = *v\n",
     "\t\t\t_ = v\n",
     "the snapshot value never reaches the INSERT"),
    ("md-to-db-ignores-prior", PKG + "/db.go",
     "\t\tif _, ok := snap[k]; !ok {\n\t\t\tsnap[k] = v\n",
     "\t\tif false {\n\t\t\tsnap[k] = v\n",
     "the caller's snapshot is dropped (a Markdown move Issues->Fixed loses created_at)"),
    ("md-to-db-sync-passes-nil", PKG + "/sync.go",
     "replaceDocumentWithSnapshot(db, \"Fixed\", items, segs, snap)",
     "replaceDocumentWithSnapshot(db, \"Fixed\", items, segs, nil)",
     "sync md-to-db takes no snapshot across its two transactions"),
    ("lookup-no-exact", PKG + "/db.go",
     "\tif v, ok := s[createdAtKey(id, loc, rep)]; ok {\n",
     "\tif v, ok := s[createdAtKey(id, loc, rep)]; ok && false {\n",
     "an existing row takes the item's earliest value instead of its own"),
    ("lookup-latest", PKG + "/db.go",
     "\t\t\tif best == nil || v < *best {\n",
     "\t\t\tif best == nil || v > *best {\n",
     "a moved row takes the item's latest value"),
    ("lookup-no-fallback", PKG + "/db.go",
     "\t\t}\n\t}\n\treturn best\n}",
     "\t\t}\n\t}\n\treturn nil\n}",
     "a row that changed document gets the column default"),
    # --- restore-created-at
    ("restore-no-dispatch", PKG + "/main.go",
     "\tcase \"restore-created-at\":\n\t\trunRestoreCreatedAt(args[1:])\n",
     "",
     "the subcommand is not reachable from the command line"),
    ("restore-skip-sha-compare", PKG + "/restore_created_at.go",
     "\tif gotSHA != *evidenceSHA {\n",
     "\tif false && gotSHA != *evidenceSHA {\n",
     "the evidence sha256 is not compared"),
    ("restore-skip-live-db-check", PKG + "/restore_created_at.go",
     "\tif os.SameFile(evInfo, liveInfo) {\n",
     "\tif false && os.SameFile(evInfo, liveInfo) {\n",
     "the live database attests its own value"),
    ("restore-skip-wal-check", PKG + "/restore_created_at.go",
     "err == nil && si.Size() > 0 {\n",
     "err == nil && si.Size() > 0 && false {\n",
     "an evidence file with un-checkpointed WAL content is read as if complete"),
    ("restore-evidence-not-immutable", PKG + "/restore_created_at.go",
     "RawQuery: \"mode=ro&immutable=1\"",
     "RawQuery: \"\"",
     "the evidence file is opened read-write and grows sidecars"),
    ("restore-skip-identity-match", PKG + "/restore_created_at.go",
     "\t\tif r.typ != target.typ || r.title != target.title {\n",
     "\t\tif false {\n",
     "another item's evidence attests this item's value"),
    ("restore-skip-attestation", PKG + "/restore_created_at.go",
     "\tif attest == \"\" {\n\t\tsort.Strings(recorded)\n",
     "\tif false {\n\t\tsort.Strings(recorded)\n",
     "a value the evidence does not record is accepted"),
    ("restore-skip-first-event-bound", PKG + "/restore_created_at.go",
     "\tif newT.After(first) {\n",
     "\tif false && newT.After(first) {\n",
     "a value later than the item's first history row is accepted"),
    ("restore-skip-current-bound", PKG + "/restore_created_at.go",
     "\tif newT.After(curT) {\n",
     "\tif false && newT.After(curT) {\n",
     "a restore may move created_at later"),
    ("restore-no-history-ok", PKG + "/restore_created_at.go",
     "\tif n == 0 {\n\t\treturn rcaRefuse(\"NO-HISTORY\"",
     "\tif n < 0 {\n\t\treturn rcaRefuse(\"NO-HISTORY\"",
     "an item with no history row is not reported as NO-HISTORY (its zero-time bound refuses with a misleading code)"),
    ("restore-no-audit-row", PKG + "/restore_created_at.go",
     "\tif err := recordHistory(tx, *id, \"Updated\", *by, audit, evRaw); err != nil {\n",
     "\tif _, err := audit, error(nil); err != nil {\n",
     "the restore writes no item_history row"),
    ("restore-by-ignored", PKG + "/restore_created_at.go",
     "recordHistory(tx, *id, \"Updated\", *by, audit, evRaw)",
     "recordHistory(tx, *id, \"Updated\", \"AI\", audit, evRaw)",
     "--by is not recorded"),
    ("restore-dry-run-writes", PKG + "/restore_created_at.go",
     "\tif *dryRun {\n",
     "\tif false && *dryRun {\n",
     "--dry-run writes"),
    ("restore-already-rewrites", PKG + "/restore_created_at.go",
     "\tif target.created == *value {\n",
     "\tif false && target.created == *value {\n",
     "a repeated restore writes another audit row"),
    ("restore-evidence-id-ignored", PKG + "/restore_created_at.go",
     "\tevID := *evidenceID\n",
     "\tevID := \"\"\n\t_ = evidenceID\n",
     "--evidence-id is ignored"),
    ("restore-ambiguous-picks-first", PKG + "/restore_created_at.go",
     "\tswitch len(found) {\n",
     "\tswitch min(len(found), 1) {\n",
     "an item with two rows is restored on the first one found"),
    ("restore-db-missing-creates", PKG + "/restore_created_at.go",
     "\tif err != nil || !liveInfo.Mode().IsRegular() {\n",
     "\tif false && (err != nil || !liveInfo.Mode().IsRegular()) {\n",
     "a missing live database is created by the open"),
]


def run_tests(module_copy):
    env = dict(os.environ, GOPROXY="off", GOFLAGS=os.environ.get("GOFLAGS", ""))
    p = subprocess.run(["go", "test", "-count=1", "-run", RUN, "./" + PKG + "/"],
                       cwd=module_copy, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=1800)
    failed = [l.strip() for l in p.stdout.splitlines() if l.startswith("--- FAIL") or l.startswith("FAIL\t")]
    buildfail = "[build failed]" in p.stdout or "[setup failed]" in p.stdout
    return p.returncode, failed, buildfail, p.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--list", action="store_true", help="print the mutant names and exit")
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    if a.list:
        for m in MUTANTS:
            print("%s\t%s\t%s" % (m[0], m[1], m[4]))
        return 0
    only = set(x for x in a.only.split(",") if x)
    unknown = only - set(m[0] for m in MUTANTS)
    if unknown:
        print("unknown mutant(s): " + ",".join(sorted(unknown)))
        return 2
    work = tempfile.mkdtemp(prefix="created_at_mut_")
    rc = 0
    try:
        ctl = build_mirror(os.path.join(work, "control"))
        code, failed, _, out = run_tests(ctl)
        if code != 0:
            print("CONTROL FAILED (unmutated tests must pass):\n" + out)
            return 2
        print("CONTROL PASS unmutated " + RUN)
        killed = survived = 0
        for name, rel, old, new, intent in MUTANTS:
            if only and name not in only:
                continue
            mc = build_mirror(os.path.join(work, name))
            err = apply(mc, rel, old, new)
            if err:
                print("STALE %s: %s" % (name, err))
                rc = 1
                continue
            code, failed, buildfail, out = run_tests(mc)
            if code == 0:
                survived += 1
                rc = 1
                print("SURVIVED %s (%s)" % (name, intent))
            elif buildfail:
                rc = 1
                print("BUILD-BROKEN %s (a mutant must compile to count as killed):\n%s" % (name, out[-2000:]))
            else:
                killed += 1
                tests = sorted(set(f.split()[2] for f in failed if f.startswith("--- FAIL")))
                print("KILLED %s (%s) by %s" % (name, intent, ",".join(tests) or "package FAIL"))
        print("SUMMARY killed=%d survived=%d verdict=%s" % (killed, survived, "PASS" if rc == 0 else "FAIL"))
        return rc
    finally:
        if a.keep:
            print("kept mirrors under " + work)
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
