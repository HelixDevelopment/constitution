#!/usr/bin/env python3
"""Paired-mutation runner for the §11.4.292 reproduction / investigation states.

Each mutant is an exact, unique source replacement. For every mutant the runner
builds a private mirror of the constitution tree (everything symlinked except a
COPY of scripts/workable-items), applies the mutant to the copy, and runs

    go test -count=1 -run '^TestStates' ./cmd/workable-items/

The mutant is KILLED when that run fails. The unmutated mirror must PASS first
(control), and a mutant whose anchor is absent or not unique is a runner
failure (a stale mutant is never silently skipped).

Exit 0 only when the control passes and every mutant is killed.

Usage: python3 -I states_mutation_runner.py [--only NAME[,NAME...]] [--keep]
Evidence: one line per mutant on stdout, `KILLED|SURVIVED|STALE <name> ...`.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)                      # scripts/workable-items
ROOT = os.path.dirname(os.path.dirname(MODULE))     # constitution root
PKG = "cmd/workable-items"

# (name, file relative to the module, exact old text, new text, intent)
MUTANTS = [
    ("drop-validate-states", PKG + "/sync.go",
     "func statesValidation(db *sql.DB, items []item, violations *[]string) (bool, error) {\n",
     "func statesValidation(db *sql.DB, items []item, violations *[]string) (bool, error) {\n\treturn true, nil\n",
     "validate runs no state invariant"),
    ("drop-record-problems", PKG + "/states.go",
     "func stateRecordProblems(r stateRecord, resolveEvidence bool) []string {\n",
     "func stateRecordProblems(r stateRecord, resolveEvidence bool) []string {\n\treturn nil\n",
     "no record invariant (evidence, blocker, details-need-state)"),
    ("drop-desync-detector", PKG + "/states.go",
     "func stateColumnBodyDesyncs(items []item) []string {\n",
     "func stateColumnBodyDesyncs(items []item) []string {\n\treturn nil\n",
     "column<->body desync never reported"),
    ("export-ignores-green-command", PKG + "/states.go",
     "\tfor _, kv := range details {\n\t\tif kv[1] == \"\" {\n",
     "\tfor _, kv := range details {\n\t\tif kv[0] == \"green-command\" {\n\t\t\tcontinue\n\t\t}\n\t\tif kv[1] == \"\" {\n",
     "the rendered record drops one field"),
    ("export-summary-drops-investigation", PKG + "/states.go",
     "func invSummaryCell(r stateRecord) string {\n\treturn r.norm().InvState\n",
     "func invSummaryCell(r stateRecord) string {\n\treturn \"\"\n",
     "the summary loses the Investigation column value"),
    ("export-no-records", PKG + "/states.go",
     "\tif representation == \"table\" {\n\t\treturn body\n\t}\n\twant = want.norm()\n",
     "\tif representation != \"\" {\n\t\treturn body\n\t}\n\twant = want.norm()\n",
     "db->md / add / update never write the record lines"),
    ("lossy-parse-env", PKG + "/states.go",
     "\tcase \"env\":\n\t\tr.ReproEnv = val\n",
     "\tcase \"env\":\n\t\t_ = val\n",
     "md->db drops reproduction env"),
    ("lossy-parse-codespan-padding", PKG + "/states.go",
     "\t\t\t\tcontent = content[1 : len(content)-1]\n",
     "\t\t\t\tcontent = content[1:]\n",
     "a padded code span parses back with a trailing space"),
    ("lossy-md-to-db", PKG + "/parse.go",
     "\tit.States = parseStateLines(body).rec\n",
     "\t_ = parseStateLines\n",
     "md->db never fills the state columns"),
    ("wrong-closed-set-go-drops-blocked", PKG + "/states.go",
     "\treproNotReproducible, reproBlocked,\n}",
     "\treproNotReproducible,\n}",
     "Go reproduction set loses a value the schema keeps"),
    ("wrong-closed-set-go-adds-verified", PKG + "/states.go",
     "\tinvRootCauseUnconfirmed, invClosedNoDefect,\n}",
     "\tinvRootCauseUnconfirmed, invClosedNoDefect, \"VERIFIED\",\n}",
     "Go investigation set gains a value the schema rejects"),
    ("wrong-closed-set-schema", PKG + "/schema_embed.sql",
     "'root-cause-unconfirmed', 'closed-no-defect'",
     "'root-cause-unconfirmed', 'closed-no-defect', 'VERIFIED'",
     "schema CHECK accepts a value outside the Go set"),
    ("allow-verified-with-unreproduced", PKG + "/states.go",
     "\t\t\tif label, why := reproLabel(st); label != labelReproduced {\n",
     "\t\t\tif label, why := reproLabel(st); false && label != labelReproduced {\n",
     "C1 removed: a VERIFIED closure with an UNREPRODUCED record passes"),
    ("label-ignores-env", PKG + "/states.go",
     "\t\t\t{\"red-command\", r.ReproRedCmd}, {\"env\", r.ReproEnv},\n",
     "\t\t\t{\"red-command\", r.ReproRedCmd},\n",
     "REPRODUCED without a recorded environment"),
    ("drop-preventive-closure-check", PKG + "/states_cli.go",
     "\tif !verifiedClosureStatus(newStatus) {\n\t\treturn nil\n\t}\n\tg, err := loadClosureGate(db)\n",
     "\tif true {\n\t\treturn nil\n\t}\n\tg, err := loadClosureGate(db)\n",
     "close / move never refuse an UNREPRODUCED VERIFIED closure"),
    ("drop-armed-c2", PKG + "/states.go",
     "\t\t} else if g.armed && it.Type == \"Bug\" && !g.isExempt(it) {\n",
     "\t\t} else if false && g.armed && it.Type == \"Bug\" && !g.isExempt(it) {\n",
     "an armed gate accepts a record-less closed Bug"),
    ("import-partial-write", PKG + "/states_cli.go",
     "\tif len(problems) > 0 {\n\t\tfmt.Fprintf(os.Stderr, \"states import: %d problem(s); nothing written:\\n\", len(problems))\n",
     "\tif false {\n\t\tfmt.Fprintf(os.Stderr, \"states import: %d problem(s); nothing written:\\n\", len(problems))\n",
     "import writes the good rows of a bad file"),
    ("import-restamps-unchanged", PKG + "/states_cli.go",
     "\t\tr.ReproUpdatedAt, r.ReproUpdatedBy = cur.ReproUpdatedAt, cur.ReproUpdatedBy\n",
     "\t\tr.ReproUpdatedAt, r.ReproUpdatedBy = at, by\n",
     "an unchanged block is re-stamped when the other block changes"),
    ("skip-states-migration", PKG + "/db.go",
     "func migrateStatesColumns(db *sql.DB) error {\n",
     "func migrateStatesColumns(db *sql.DB) error {\n\tif true {\n\t\treturn nil\n\t}\n",
     "a pre-v8 DB is never migrated"),
]


def build_mirror(dest):
    """Mirror ROOT under dest: symlink every entry except scripts/, symlink every
    scripts/ entry except workable-items/, COPY workable-items (minus bin/)."""
    os.makedirs(os.path.join(dest, "scripts"))
    for name in os.listdir(ROOT):
        if name == "scripts":
            continue
        os.symlink(os.path.join(ROOT, name), os.path.join(dest, name))
    scripts = os.path.join(ROOT, "scripts")
    for name in os.listdir(scripts):
        if name == "workable-items":
            continue
        os.symlink(os.path.join(scripts, name), os.path.join(dest, "scripts", name))
    shutil.copytree(MODULE, os.path.join(dest, "scripts", "workable-items"),
                    ignore=shutil.ignore_patterns("bin", "mutation"))
    return os.path.join(dest, "scripts", "workable-items")


def apply(module_copy, rel, old, new):
    path = os.path.join(module_copy, rel)
    with open(path, encoding="utf-8") as f:
        src = f.read()
    n = src.count(old)
    if n != 1:
        return "anchor found %d times in %s (want exactly 1)" % (n, rel)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src.replace(old, new, 1))
    return ""


def run_tests(module_copy):
    env = dict(os.environ, GOPROXY="off", GOFLAGS=os.environ.get("GOFLAGS", ""))
    p = subprocess.run(["go", "test", "-count=1", "-run", "^TestStates", "./" + PKG + "/"],
                       cwd=module_copy, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=900)
    failed = [l.strip() for l in p.stdout.splitlines() if l.startswith("--- FAIL") or l.startswith("FAIL\t")]
    buildfail = "[build failed]" in p.stdout or "[setup failed]" in p.stdout
    return p.returncode, failed, buildfail, p.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    only = set(x for x in a.only.split(",") if x)
    work = tempfile.mkdtemp(prefix="states_mut_")
    rc = 0
    try:
        ctl = build_mirror(os.path.join(work, "control"))
        code, failed, _, out = run_tests(ctl)
        if code != 0:
            print("CONTROL FAILED (unmutated tests must pass):\n" + out)
            return 2
        print("CONTROL PASS unmutated ^TestStates")
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
                tests = [f.split()[2] for f in failed if f.startswith("--- FAIL")]
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
