#!/usr/bin/env python3
"""Round 13: write round13/README.md from the draft by filling its <<FILL:...>> fields from the evidence files in
the round13 directory. Every number in a filled field is read from a file; a claim of the draft that the files do
not support (golden-FALSE not 0 findings, a suite with a FAIL, a RED/GREEN name set that differs, an unknown file
in the directory) stops the fill with exit 1 and nothing is written.
usage: fill13.py ROUND13_DIR DRAFT OUT [--standing]   (--standing: the standing run is done; fill its result)"""
import hashlib, os, re, sys

r13, draft, out = sys.argv[1:4]
standing = "--standing" in sys.argv[4:]
P = lambda *a: os.path.join(r13, *a)  # noqa: E731
errors = []


def need(cond, msg):
    if not cond:
        errors.append(msg)


def lines(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read().splitlines()


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


# --- the oracle table -----------------------------------------------------------------------------------------
def oracle(path):
    rows = []
    for ln in lines(path):
        a = ln.split("\t")
        if len(a) >= 3 and a[0] in ("BYPASS", "CAUGHT", "NO-LEAK", "ERROR"):
            rows.append((a[0], a[1], a[2]))
    return rows


def tally(rows):
    c = {}
    for v, _, _ in rows:
        c[v] = c.get(v, 0) + 1
    return ", ".join("%d %s" % (c[k], k) for k in ("BYPASS", "CAUGHT", "NO-LEAK", "ERROR") if k in c)


O = P("oracle")
red = {k: oracle(os.path.join(O, "r12.%s.txt" % k)) for k in
       ("cases_r1", "cases_r2", "cases_r2b", "cases_r13", "cases_r13b", "cases_r13c", "cases_r13d", "cases_r13e")}
green = {k: oracle(os.path.join(O, "r13.%s.txt" % k)) for k in ("cases_r1", "cases_r2", "cases_r2b", "cases_r13_all")}
# the round-13 fixtures: RED is the union of the part runs, by name, first run wins (O65-O67 are in two parts)
red13, seen = [], set()
for k in ("cases_r13", "cases_r13b", "cases_r13c", "cases_r13d", "cases_r13e"):
    for r in red[k]:
        if r[1] not in seen:
            seen.add(r[1])
            red13.append(r)
g13 = green["cases_r13_all"]
need({r[1] for r in red13} == {r[1] for r in g13}, "RED and GREEN round-13 fixture names differ")
need(len(g13) == 85, "round-13 GREEN has %d fixtures, not 85" % len(g13))
groups = [("the round-12 reviewer, batch 1 (`cases_r1.json`)", red["cases_r1"], green["cases_r1"]),
          ("the round-12 reviewer, batch 2 (`cases_r2.json`, `cases_r2b.json`)", red["cases_r2"] + red["cases_r2b"],
           green["cases_r2"] + green["cases_r2b"]),
          ("the fixer, round 13 (`cases_r13_all.json`; RED from the five part files)", red13, g13)]
allg = [r for _, _, g in groups for r in g]
for _, rr, gg in groups:
    need(len(rr) == len(gg), "a RED and a GREEN group differ in size")
need(all(r[2].split("=")[1].split("/")[0] == r[2].split("=")[1].split("/")[1] for _, rr, gg in groups for r in rr + gg),
     "a fixture gives a different gate rc with the two PATHs")
gbad = [r for r in allg if r[0] == "BYPASS" or r[0] == "ERROR"]
need(not gbad, "GREEN has a BYPASS or ERROR row: %s" % [r[1] for r in gbad])
gno = sorted({r[1] for r in allg if r[0] == "NO-LEAK"})
need(gno == ["R92_ctrl_neg_clean"], "GREEN NO-LEAK rows other than R92_ctrl_neg_clean: %s" % gno)
rev = [x.strip() for x in lines(os.path.join(O, "rev_names.txt")) if x.strip()]
gv = {r[1]: r[0] for r in allg}
need(len(rev) == 32 and all(gv.get(n) == "CAUGHT" for n in rev), "a reviewer bypass is not CAUGHT in GREEN")
rv13 = [r[1] for r in red13 if r[0] == "BYPASS"]
tab = ["| Fixtures | Rows | Round-12 gate `dd095a3f` (RED) | Round-13 gate (GREEN) |", "|---|---|---|---|"]
for label, rr, gg in groups:
    tab.append("| %s | %d | %s | %s |" % (label, len(gg), tally(rr), tally(gg)))
tot_r = [r for _, rr, _ in groups for r in rr]
tab.append("| all | %d | %s | %s |" % (len(allg), tally(tot_r), tally(allg)))
ORACLE_TABLE = "\n".join(tab) + (
    "\n\nThe 48 reviewer rows are 45 fixtures (R06, R07 and R14 are in both of its batches). Round-13 fixtures the "
    "round-12 gate passes with a leak or a loopback connection: %s." % ", ".join(rv13))

# --- golden-FALSE and lint ------------------------------------------------------------------------------------
gn = lines(P("golden_netgate_normalpath.txt"))
need(gn and gn[-1] == "NETGATE layer=pin+analyser invocations=128 network_through_rc_net=51 findings=0",
     "golden-FALSE last line: %r" % (gn[-1] if gn else None))
need(sum(1 for x in gn if x.startswith("SITE\t")) == 128, "golden-FALSE SITE lines != 128")
need(not any(x.startswith("FINDING") for x in gn), "golden-FALSE has a FINDING line")
need(open(P("golden_netgate_normalpath.txt"), "rb").read() == open(P("golden_netgate_emptypath.txt"), "rb").read(),
     "golden-FALSE differs between the two PATHs")
ln_ = lines(P("lint_normalpath.txt"))
need(ln_ and ln_[-1] == "CENSUS invocations=128 rows=124 secret_lines=13 findings=0", "lint last line: %r" % ln_[-1:])
need(open(P("lint_normalpath.txt"), "rb").read() == open(P("lint_emptypath.txt"), "rb").read(),
     "lint differs between the two PATHs")
GOLDEN_FILES = "`golden_netgate_normalpath.txt`, `golden_netgate_emptypath.txt`; the lint: `lint_normalpath.txt`, " \
               "`lint_emptypath.txt`"

# --- the suites -------------------------------------------------------------------------------------------------
SUITES = [("redact", "test_redact_cut"), ("channel", "test_channel_census"), ("derive", "test_derive_release_facts"),
          ("publish", "test_publish_gitea"), ("tag", "test_tag_and_release"), ("render", "test_render_release_entry")]


def summary(path):
    d = {}
    for ln in lines(path):
        a = ln.split("\t")
        if len(a) == 7:
            d[a[0]] = a
    return d


s1, s2 = summary(P("suites_run1.tsv")), summary(P("suites_run2.tsv"))
st = ["| Suite | Run 1 | Run 2 | Same verdict lines (digits normalised) |", "|---|---|---|---|"]
for short, s in SUITES:
    a, b = s1.get(s), s2.get(s)
    need(a is not None and b is not None, "suite %s missing in a summary" % s)
    if a is None or b is None:
        continue
    need(a[1] == "0" and b[1] == "0" and a[4] == "0" and b[4] == "0", "suite %s rc or FAIL not 0" % s)

    def norm(run):
        return sorted(re.sub(r"[0-9]+", "N", x) for x in lines(P("green_%s_run%d.txt" % (s[len("test_"):], run)))
                      if re.match(r"(PASS|FAIL|SKIP)", x))
    same = norm(1) == norm(2)
    need(same, "suite %s verdict lines differ between the runs" % s)
    st.append("| %s (`%s.sh`) | rc %s, pass=%s fail=%s, %s | rc %s, pass=%s fail=%s, %s | %s |" % (
        short, s, a[1], a[3], a[4], a[2], b[1], b[3], b[4], b[2], "yes" if same else "NO"))
SUITES_TABLE = "\n".join(st) + "\n\nOutputs: `green_<suite>_run1.txt`, `green_<suite>_run2.txt`; summaries " \
    "`suites_run1.tsv`, `suites_run2.tsv` (rc, seconds, PASS and FAIL counts, RESULT line)."

# --- mutants ------------------------------------------------------------------------------------------------------
sl = lines(P("mutations_stale_only_round13.txt"))
res = [x for x in sl if x.startswith("RESULT")]
applies = sum(1 for x in sl if re.match(r"PASS \S+ applies$", x))
need(res and "stale=0" in res[-1], "STALE_ONLY: %r" % res[-1:])
STALE = "%d apply, 0 stale (`mutations_stale_only_round13.txt`)" % applies
pre = [x.split("\t") for x in lines(P("mutants_targeted_r13.tsv"))]
pre = [a for a in pre if a and a[0] != "PRESCREEN-DONE"]
pm = [a[0] for a in pre if len(a) >= 4 and a[3] == "match"]
pn = [a[0] for a in pre if not (len(a) >= 4 and a[3] == "match")]
need(len(pre) == 104, "targeted pre-run has %d mutants, not 104" % len(pre))
PRESCREEN = "%d of %d killed by a FAIL line of their property%s" % (
    len(pm), len(pre), "" if not pn else "; not by their property: " + ", ".join(pn))
pl = lines(P("pn13_probe.txt"))
need(pl and pl[-1] == "pairs=10 same_refusal=10 tables_written=0", "pn13 probe: %r" % pl[-1:])
PN13 = "10 of 10 pairs give the same `REFUSED` line with rc 1, no table written"
nr8 = [a for a in pre if a[0] == "NR8"]
need(nr8 and nr8[0][3] == "match", "NR8 not killed by its property in the final pre-run")
NR8 = "final pre-run: killed by its property, %s FAIL lines" % (nr8[0][2] if nr8 else "?")
if standing:
    ss = lines(P("standing_summary.txt"))
    head = ss[0] if ss else ""
    need(head.startswith("DONE "), "standing summary is not DONE")
    STANDING = "The whole harness ran on commit A as a transient systemd user service; summary `standing_summary.txt`:" \
        "\n\n```\n%s\n```\n\nFull output: `mutations_full_r13.txt`." % "\n".join(ss)
else:
    STANDING = "PENDING. The whole harness runs on this commit (commit A) as a transient systemd user service " \
        "(`tools/launch_standing13.sh`: `systemd-run --user`, `TasksMax=3000`, `env -i`, `nice -n 10`); commit B adds " \
        "its output (`mutations_full_r13.txt`, `standing_summary.txt`) and fills this paragraph."

# --- O3 -----------------------------------------------------------------------------------------------------------
o3s, o3m = P("r12_standing_summary.txt"), P("r12_standing_mutations_partial.txt")
ml = lines(o3m)
O3 = "`r12_standing_summary.txt` (sha256 `%s`) and `r12_standing_mutations_partial.txt` (sha256 `%s`): %d PASS " \
     "lines (%d controls, %d killed), %d FAIL lines" % (
         sha(o3s), sha(o3m), sum(1 for x in ml if x.startswith("PASS ")), sum(1 for x in ml if x.startswith("PASS control")),
         sum(1 for x in ml if re.match(r"PASS .* killed", x)), sum(1 for x in ml if x.startswith("FAIL")))

# --- other checks -------------------------------------------------------------------------------------------------
ck = {}
for ln in lines(P("checks.tsv")):
    a = ln.split("\t")
    if len(a) == 3:
        ck[a[0]] = a
need(set(ck) == {"golden_netgate", "lint", "shellcheck", "pyright", "verify_manifest", "gate_ledger_ratchet"},
     "checks.tsv rows: %s" % sorted(ck))
for k, a in ck.items():
    need(a[1] in ("0", "0/0"), "check %s rc %s" % (k, a[1]))
sp = lines(P("sshd_probe_green_round13.txt"))
need(sp and sp[-1] == "SUMMARY cases=36 clean=36 leak=0 blind=0", "sshd probe: %r" % sp[-1:])
rows = [("golden-FALSE, both PATHs", ck.get("golden_netgate", ["", "", ""])[2], "`golden_netgate_*.txt`"),
        ("census lint, both PATHs", ck.get("lint", ["", "", ""])[2], "`lint_*.txt`"),
        ("shellcheck -S warning", "rc %s; %s" % (ck.get("shellcheck", ["", "?", ""])[1], ck.get("shellcheck", ["", "", ""])[2]),
         "`shellcheck.txt`"),
        ("pyright", ck.get("pyright", ["", "", ""])[2], "`pyright.txt`"),
        ("`scripts/run_full_suite.sh --verify-manifest`", ck.get("verify_manifest", ["", "", ""])[2], "`verify_manifest.txt`"),
        ("gate ledger ratchet", ck.get("gate_ledger_ratchet", ["", "", ""])[2], "`gate_ledger_ratchet.txt`"),
        ("LIVE loopback sshd probe (round 11's `probe_sendenv_leak_sshd.sh` on this tree)", sp[-1] if sp else "",
         "`sshd_probe_green_round13.txt`")]
CHECKS_TABLE = "| Check | Result | File |\n|---|---|---|\n" + "\n".join(
    "| %s | %s | %s |" % (a, b.replace("|", "\\|"), c) for a, b, c in rows)

# --- files --------------------------------------------------------------------------------------------------------
DESC = {
    "README.md": "this file", "SHA256SUMS": "sha256 of every other file of this directory",
    "threat_model.md": "goal, failure model, the three layers and what each proves, the positive shapes, residuals",
    "class_inventory.md": "the controls by class (generated)", "make_class_inventory.py": "writes class_inventory.md",
    "round12_sums_before_f3_correction.txt": "`../round12/SHA256SUMS` before the F3 notes",
    "mutants.md": "every mutant: what it breaks, its property, the pre-run and standing-run result",
    "mutants_targeted_r13.tsv": "the targeted pre-run on the final tree (one line per mutant)",
    "mutants_targeted_r13_first.tsv": "the first targeted pre-run, before the last edits (100 mutants; NR8, AN34, AN37 not killed)",
    "mutations_stale_only_round13.txt": "`STALE_ONLY=1` run of the harness",
    "pn13_probe.txt": "the probe behind the PN13 equivalence",
    "suites_run1.tsv": "suite summary, run 1", "suites_run2.tsv": "suite summary, run 2",
    "golden_netgate_normalpath.txt": "netgate --pin --sites on the release files, normal PATH",
    "golden_netgate_emptypath.txt": "the same with PATH=/nonexistent",
    "lint_normalpath.txt": "census lint, normal PATH", "lint_emptypath.txt": "census lint, PATH=/nonexistent",
    "shellcheck.txt": "shellcheck -S warning", "pyright.txt": "pyright", "verify_manifest.txt": "--verify-manifest",
    "gate_ledger_ratchet.txt": "gate ledger ratchet", "checks.tsv": "one line per check above",
    "sshd_probe_green_round13.txt": "LIVE loopback sshd probe",
    "r12_standing_summary.txt": "O3: the summary file of the round-12 standing run, as it was left",
    "r12_standing_mutations_partial.txt": "O3: the partial output of the round-12 standing run",
    "mutations_full_r13.txt": "the standing run of the whole harness on commit A",
    "standing_summary.txt": "its summary",
    "b2_investigation": "why B2 was not killed by its property in the standing run: the probes, the harness "
                        "`--only B2` runs at both descriptor limits, their outputs and `commands.md`",
    "oracle": "RED and GREEN oracle results (`r12.*.txt`, `r13.*.txt`), the mutants on the round-12 gate "
              "(`discr.log`, `mr5_mr10.txt`; `d2b_mr2.txt`: MR2 against `D2b_mapfile_C_attached`, from "
              "`tools/cases_d2b.json`), NR8 on the gate (`nr8.cases_r13d.txt`), the reviewer's 32 names "
              "(`rev_names.txt`)",
    "tools": "the scripts and fixture files behind this evidence (oracle, mutant spec, pre-run, probes, runners)",
}
fl = []
for n in sorted(os.listdir(r13)):
    if n.startswith("green_") and n.endswith(".txt"):
        continue
    need(n in DESC, "file without a description: %s" % n)
    fl.append("- `%s%s`: %s" % (n, "/" if os.path.isdir(P(n)) else "", DESC.get(n, "?")))
fl.append("- `green_<suite>_run1.txt`, `green_<suite>_run2.txt`: the six suites, twice")
FILES = "\n".join(fl)

text = open(draft, encoding="utf-8").read()
for k, v in (("ORACLE_TABLE", ORACLE_TABLE), ("GOLDEN_FILES", GOLDEN_FILES), ("SUITES_TABLE", SUITES_TABLE),
             ("STALE", STALE), ("PRESCREEN", PRESCREEN), ("PN13", PN13), ("NR8", NR8), ("STANDING", STANDING),
             ("O3", O3), ("CHECKS_TABLE", CHECKS_TABLE), ("FILES", FILES)):
    need(text.count("<<FILL:%s>>" % k) == 1, "field %s not exactly once in the draft" % k)
    text = text.replace("<<FILL:%s>>" % k, v)
need("<<FILL:" not in text, "an unfilled field is left")
if errors:
    for e in errors:
        print("FILL-ERROR " + e)
    sys.exit(1)
with open(out, "w", encoding="utf-8") as fh:
    fh.write(text)
print("FILLED %s" % out)
