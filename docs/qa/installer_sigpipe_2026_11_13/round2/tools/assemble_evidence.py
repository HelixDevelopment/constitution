"""assemble_evidence.py W E DEST [--draft] — assembles the round-2 evidence directory of CON-PENDING-INSTALLER-SIGPIPE.

W     the scratch workspace (tools/, final/, stage/, bashes/, image_bash_versions.txt)
E     the evidence run directory (out/ with the lane logs, coA/ the frozen clone of the fix commit)
DEST  docs/qa/installer_sigpipe_2026_11_13/round2 in the vehicle checkout; it is emptied of files this script
      writes and filled again, so the script can be re-run.

It copies every evidence file into DEST with the scratch paths replaced by <scratch> (and any other home-directory
path by ~), renders README.md from stage/README.round2.tmpl.md and stage/limits.md, and writes SHA256SUMS.
--draft renders "(pending)" for lane results that do not exist yet; without it a missing input is an error.
Exit 0 written, 1 a required input is missing or a placeholder is left in README.md, 2 usage.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

if len(sys.argv) not in (4, 5) or (len(sys.argv) == 5 and sys.argv[4] != "--draft"):
    print(__doc__.strip().splitlines()[0], file=sys.stderr)
    sys.exit(2)
W, E, DEST = (os.path.abspath(a) for a in sys.argv[1:4])
DRAFT = len(sys.argv) == 5
OUT = os.path.join(E, "out")
FINAL = os.path.join(W, "final")
TOOLS = os.path.join(W, "tools")
missing = []

VERSIONS = ["5.0.17", "5.1.4", "5.1.16", "5.2.15", "5.2.26", "5.2.37", "host"]
# bash copies used in this round: version -> (image id, image name). Every image was already on the host; nothing
# was pulled. The host bash is /usr/bin/bash.
SOURCES = [
    ("3.2.57", "031109e9f704", "docker.io/library/bash:3.2"),
    ("5.0.17", "40876b9dd828", "docker.io/dperson/openvpn-client:latest"),
    ("5.1.4", "4c6a3895fd98", "docker.io/atmoz/sftp:latest"),
    ("5.1.16", "ac1502203bff", "docker.io/library/mongo:7"),
    ("5.2.15", "43f84a0b210f", "mirror.gcr.io/library/debian:bookworm-slim"),
    ("5.2.26", "8c7e4042cd99", "docker.io/grafana/grafana:11.3.1"),
    ("5.2.37", "596c6d80c879", "docker.io/library/debian:trixie-slim"),
]


HOME_DIR = "/" + "home" + "/"   # spelled in two parts so that this file, copied into the evidence, scrubs to itself
SCRATCH_RE = re.compile(re.escape(HOME_DIR) + r"[^/\s]+/\.cache/claude-tmp/[^\s'\"`)\]]*")
HOMEDIR_RE = re.compile(re.escape(HOME_DIR) + r"[^/\s'\"`]+")


def scrub(text):
    text = text.replace(W, "<scratch>")
    return HOMEDIR_RE.sub("~", SCRATCH_RE.sub("<scratch>", text))


def read(path, need=True):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        if need and not DRAFT:
            missing.append(path)
        return None


written = []


def put(rel, text):
    p = os.path.join(DEST, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(scrub(text))
    written.append(rel)


def copy(src, rel, need=True):
    t = read(src, need)
    if t is not None:
        put(rel, t)
    return t


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def cell(s):
    return scrub(s).replace("|", "\\|").strip()


def vkey(v):
    return (9, 9, 9) if v == "host" else tuple(int(x) for x in v.split("."))


def tsv(path):
    t = read(path)
    if not t:
        return []
    rows = [l.split("\t") for l in t.splitlines() if l.strip()]
    return [dict(zip(rows[0], r)) for r in rows[1:]]


# ---- clear what an earlier run wrote (only files this script writes: everything under DEST) ----
# DEST must be the round-2 directory inside a checkout under W; anything else is refused before a file is touched.
if not (DEST.endswith(os.sep + os.path.join("docs", "qa", "installer_sigpipe_2026_11_13", "round2"))
        and DEST.startswith(W + os.sep)):
    print("assemble_evidence: refusing DEST outside W/.../docs/qa/installer_sigpipe_2026_11_13/round2: " + DEST,
          file=sys.stderr)
    sys.exit(2)
if os.path.isdir(DEST):
    for root, dirs, files in os.walk(DEST, topdown=False):
        for n in files:
            os.unlink(os.path.join(root, n))
        for n in dirs:
            os.rmdir(os.path.join(root, n))
os.makedirs(DEST, exist_ok=True)

# the fix commit every measurement in this directory was taken on: the frozen clone coA
HEAD = subprocess.run(["git", "-C", os.path.join(E, "coA"), "rev-parse", "HEAD"], capture_output=True,
                      text=True).stdout.strip()
if not re.fullmatch(r"[0-9a-f]{40}", HEAD):
    missing.append(os.path.join(E, "coA") + " (no commit)")
HEAD8 = HEAD[:8] if HEAD else "(unknown)"

# ---- inventory ----
for n in ("shenum_base.tsv", "shenum_new.tsv", "sigscan_base.txt", "sigscan_new.txt", "xcheck_base.txt",
          "xcheck_new.txt", "inventory_counts.md"):
    copy(os.path.join(FINAL, n), "inventory/" + n)
sh_a, sh_b = os.path.join(TOOLS, "shenum", "shenum"), os.path.join(FINAL, "shenum_rebuild")
lines = ["# shenum: the binary used for the inventory and an offline rebuild from the same source must be identical"]
for label, p in (("used", sh_a), ("rebuild", sh_b)):
    if os.path.exists(p):
        mod = subprocess.run(["go", "version", "-m", p], capture_output=True, text=True).stdout
        lines.append("%s sha256 %s" % (label, sha256(p)))
        lines += ["  " + x.strip() for x in mod.splitlines() if x.strip().startswith(("go", "path", "mod", "dep"))]
    else:
        missing.append(p)
if os.path.exists(sh_a) and os.path.exists(sh_b):
    lines.append("RESULT: %s" % ("IDENTICAL" if sha256(sh_a) == sha256(sh_b) else "DIFFERENT"))
put("inventory/shenum_rebuild.txt", "\n".join(lines) + "\n")

# the committed tests/install/test_sigpipe.sh must be the build of the template with the embedded scanner
co_test = os.path.join(E, "coA", "tests", "install", "test_sigpipe.sh")
tmp_out = os.path.join(E, "out", ".rebuilt_check.sh")
r = subprocess.run([sys.executable, "-I", os.path.join(TOOLS, "build_test.py"), os.path.join(TOOLS, "test_sigpipe.tmpl.sh"),
                    os.path.join(TOOLS, "sigscan.py"), tmp_out], capture_output=True, text=True)
same = r.returncode == 0 and os.path.exists(tmp_out) and sha256(tmp_out) == sha256(co_test)
put("inventory/sigpipe_check_rebuild.txt",
    "# tools/build_sigpipe_check.py tools/sigscan_check_template.sh.txt tools/sigscan.py OUT (the two first files\n"
    "# are build_test.py and test_sigpipe.tmpl.sh, renamed in this directory), compared with\n"
    "# tests/install/test_sigpipe.sh of %s\nbuild rc=%d\ncommitted sha256 %s\nrebuilt   sha256 %s\nRESULT: %s\n"
    % (HEAD8, r.returncode, sha256(co_test), sha256(tmp_out) if os.path.exists(tmp_out) else "-",
       "IDENTICAL" if same else "DIFFERENT"))
if not same:
    missing.append("inventory/sigpipe_check_rebuild.txt: the rebuilt test differs from the committed one")
if os.path.exists(tmp_out):
    os.unlink(tmp_out)

# ---- compare ----
for n in ("byte_identity.txt", "caller_shell_compare_host.txt"):
    copy(os.path.join(FINAL, n), "compare/" + n)
for n in ("herestring_storage.txt", "notemp_emulation.txt", "awk_strnum.txt", "old_bash_version_gate.txt",
          "base_notemp_help.txt", "patsub_amp_scan.txt", "reset_facts.txt"):
    copy(os.path.join(FINAL, "facts", n), "compare/" + n)

# ---- the no-push gate (section 9) ----
GATE = os.path.join(FINAL, "gate")
for n in ("gate_by_commit.txt", "gate_mask_mutants.tsv", "gate_mask_mutants_run1.tsv", "mutation_test.txt",
          "printed_literal_feeds.txt"):
    copy(os.path.join(GATE, n), "gate/" + n)
gbc = read(os.path.join(GATE, "gate_by_commit.txt")) or ""
gt = ["| Commit | Subject | Gate result | Exit |", "|---|---|---|---|"]
for blk in re.split(r"^== ", gbc, flags=re.M)[1:]:
    head_line, _, body = blk.partition("\n")
    sha, _, subj = head_line.partition(" ")
    res = re.search(r"CM-INSTALLER-NO-PUSH-NO-FORCE: (PASS|FAIL|BLIND)( \(\d+ finding\(s\)\))?", body)
    ex = re.search(r"^\s*exit=(\d+)", body, re.M)
    full = subprocess.run(["git", "-C", os.path.join(W, "repo"), "log", "-1", "--format=%s", sha], capture_output=True,
                          text=True).stdout.strip()
    gt.append("| %s | %s | %s | %s |" % (sha[:8], cell(full or subj), (res.group(1) + (res.group(2) or "")) if res else "?",
                                         ex.group(1) if ex else "?"))
if len(gt) == 2:
    gt = ["(missing)"]


def rows_of(path):
    t = read(path) or ""
    lines = [l for l in t.splitlines() if l.strip() and not l.startswith("#")]
    if not lines:
        return {}
    hdr = lines[0].split("\t")
    return {r[0]: dict(zip(hdr, r)) for r in (l.split("\t") for l in lines[1:])}


gm2 = rows_of(os.path.join(GATE, "gate_mask_mutants.tsv"))
gm1 = rows_of(os.path.join(GATE, "gate_mask_mutants_run1.tsv"))
gm = ["| ID | Mutation | First run | Second run (two needles added) |", "|---|---|---|---|"]
for k in sorted(gm2, key=lambda x: (x != "control", x)):
    gm.append("| %s | %s | %s | %s |" % (k, cell(gm2[k].get("mutation", "")), gm1.get(k, {}).get("result", "-"),
                                         gm2[k].get("result", "?")))
gm_alive = [k for k, r in gm2.items() if k != "control" and not r.get("result", "").startswith("KILLED")]
gm.append("")
gm.append("Second run: %d of %d mutants killed%s; the control (unmutated copy) %s." % (
    len([k for k in gm2 if k != "control"]) - len(gm_alive), len([k for k in gm2 if k != "control"]),
    (", NOT KILLED: " + ", ".join(gm_alive)) if gm_alive else "", gm2.get("control", {}).get("result", "?")))
mt = read(os.path.join(GATE, "mutation_test.txt")) or ""
mm = re.search(r"^(META (PASS|FAIL)[^\n]*)$", mt, re.M)
gate_meta = "`%s`" % mm.group(1) if mm else "(missing)"
if not mm:
    missing.append(os.path.join(GATE, "mutation_test.txt") + " (no META line)")

# ---- the superseded runs on 58815d75 and the exit-3 sentinel (section 10) ----
SUP = os.path.join(FINAL, "superseded_58815d75")
if os.path.isdir(SUP):
    for n in sorted(os.listdir(SUP)):
        copy(os.path.join(SUP, n), "runs/superseded_58815d75/" + n)
else:
    missing.append(SUP)
copy(os.path.join(FINAL, "exit3_census.txt"), "runs/superseded_58815d75/exit3_census.txt")
for n in ("sentinel.tsv", "host_samples.tsv"):
    copy(os.path.join(OUT, n), "runs/" + n)
for n in ("sentinel.err", "sentinel.tsv.done"):
    copy(os.path.join(OUT, n), "runs/" + n, need=False)
sent_fail = sorted(n for n in os.listdir(OUT) if re.fullmatch(r"sentinel_fail_\d+\.txt", n)) if os.path.isdir(OUT) else []
for n in sent_fail:
    copy(os.path.join(OUT, n), "runs/" + n)
probes = tsv(os.path.join(OUT, "sentinel.tsv"))
samples = tsv(os.path.join(OUT, "host_samples.tsv"))
serr = read(os.path.join(OUT, "sentinel.err"), need=False)
sdone = read(os.path.join(OUT, "sentinel.tsv.done"), need=False)
if probes and samples:
    kinds = {}
    for p in probes:
        kinds.setdefault(p["kind"], []).append(p)
    bad = [p for p in probes if p["rc"] != "0"]
    av = [(int(s["avail_kb"]), s["time"]) for s in samples if s.get("avail_kb", "").isdigit()]
    lo, hi = (min(av), max(av)) if av else ((0, "?"), (0, "?"))
    la = [float(s["load1"]) for s in samples if re.fullmatch(r"[0-9.]+", s.get("load1", ""))]
    space_hits = sum("less than 1 GiB free" in (read(os.path.join(OUT, n)) or "") for n in sent_fail)
    sentinel_txt = (
        " Result: %d probes from %s to %s (%s)%s; %s. Free space on that file system during the re-run: between "
        "%.1f GiB (%s) and %.1f GiB; load between %.0f and %.0f; below 1 GiB in %d of %d samples "
        "(`runs/sentinel.tsv`, `runs/host_samples.tsv`)." % (
            len(probes), probes[0]["time"], probes[-1]["time"],
            ", ".join("%d %s" % (len(v), k) for k, v in sorted(kinds.items())),
            "" if sdone else "; the sentinel wrote no end line: it stopped at the same time as lane B (its last probe 2026-11-14T10:05:01Z, the last write to lane B's run-3 log 2026-11-14T10:06:04Z), when the agent session that started both had been ended",
            ("%d did not exit 0 (exit status %s; outputs in `runs/sentinel_fail_<n>.txt`, %d with the free-space "
             "refusal)" % (len(bad), ", ".join(sorted({p["rc"] for p in bad})), space_hits)) if bad
            else "every probe exited 0",
            lo[0] / 1048576.0, lo[1], hi[0] / 1048576.0, min(la) if la else 0, max(la) if la else 0,
            sum(1 for a, _ in av if a < 1048576), len(av)))
    if serr:
        sentinel_txt += " The sentinel reported: %s." % cell(serr.strip())
else:
    sentinel_txt = " Result: (pending)."
exit3_note = (read(os.path.join(W, "stage", "exit3_note.md")) or "").strip() + sentinel_txt

# ---- kill tables ----
copy(os.path.join(OUT, "anchors.txt"), "kill/anchors.txt")
for n in ("kill_table", "kill_table_n23", "kill_table_twins", "kill_table_twins_5.0.17", "kill_table_nostop"):
    copy(os.path.join(OUT, n + ".tsv"), "kill/%s.tsv" % n)
    copy(os.path.join(OUT, n + ".log"), "kill/%s.log" % n)


def check_text(r):
    s = r.get("first_failing_check", "")
    m = re.match(r"(\S+) \(scan exit (\d+)\):", s)
    if m:
        return "static scan of `%s` (scan exit %s)" % (m.group(1), m.group(2))
    return s


main_rows = tsv(os.path.join(OUT, "kill_table.tsv")) + tsv(os.path.join(OUT, "kill_table_n23.tsv"))
kt = ["| ID | Mutation | bash | Verdict | Section | First failing check |", "|---|---|---|---|---|---|"]
for r in main_rows:
    kt.append("| %s | %s | %s | %s | %s | %s |" % (r["id"], cell(r["mutation"]), r["bash"], r["verdict"], r["section"],
                                                   cell(check_text(r))))
n_main = len({r["id"] for r in main_rows})
n_killed = len({r["id"] for r in main_rows if r["verdict"] == "KILLED"})
kt.append("")
kt.append("%d mutants, %d killed on every bash they ran on (`kill/kill_table.tsv`, `kill/kill_table_n23.tsv`; anchors: "
          "`kill/anchors.txt`)." % (n_main, n_killed) if main_rows else "(pending)")
if main_rows and any(r["verdict"] != "KILLED" for r in main_rows):
    kt.append("NOT KILLED: " + ", ".join("%s on %s (%s)" % (r["id"], r["bash"], r["verdict"]) for r in main_rows
                                         if r["verdict"] != "KILLED"))

twin_rows = tsv(os.path.join(OUT, "kill_table_twins.tsv"))
# the second twin run (kill_table_twins_5.0.17.tsv) repeated N04t, N05t and N27t on the host bash and ran them on
# 5.0.17; its rows are marked so the host repeats do not read as duplicates of the first run
for r in tsv(os.path.join(OUT, "kill_table_twins_5.0.17.tsv")):
    r = dict(r)
    r["bash"] = r["bash"] + " (second twin run)"
    twin_rows.append(r)
tt = ["| ID | Mutation | bash | Verdict | Sections with a FAIL (FAIL lines) | First failing check |",
      "|---|---|---|---|---|---|"]
# N22t is an equivalent mutant (README section 8, facts/reset_facts.txt): reported as such, never counted as killed
EQUIV = {"N22t"}
for r in twin_rows:
    v = r["verdict"]
    if r["id"] in EQUIV and v == "SURVIVED":
        v = "SURVIVED: EQUIVALENT (section 4, fact 10)"
    tt.append("| %s | %s | %s | %s | %s | %s |" % (r["id"], cell(r["mutation"]), r["bash"], v, r["section"],
                                                   cell(check_text(r))))
if not twin_rows:
    tt = ["(pending)"]
elif any(r["verdict"] != "KILLED" and not (r["id"] in EQUIV and r["verdict"] == "SURVIVED") for r in twin_rows):
    tt.append("")
    tt.append("NOT KILLED: " + ", ".join("%s on %s (%s)" % (r["id"], r["bash"], r["verdict"]) for r in twin_rows
                                         if r["verdict"] != "KILLED"
                                         and not (r["id"] in EQUIV and r["verdict"] == "SURVIVED")))

ns_rows = tsv(os.path.join(OUT, "kill_table_nostop.tsv"))
if ns_rows:
    note = ("Three main mutants that die first on a section-2 check were also run to the end (`--no-stop`, "
            "`kill/kill_table_nostop.tsv`): " +
            "; ".join("%s %s, sections %s" % (r["id"], r["verdict"], r["section"]) for r in ns_rows) + ".")
else:
    note = "(pending: N04, N05 and N26 run to the end)"

# ---- runs ----
for n in ("lane_a.log", "lane_b.log", "lane_c.log", "load.log"):
    copy(os.path.join(OUT, n), "runs/" + n)
sig = {}
for v in VERSIONS:
    for k in (1, 2, 3):
        p = os.path.join(OUT, "sigpipe_%s_r%d.txt" % (v, k))
        t = copy(p, "runs/sigpipe_%s_r%d.txt" % (v, k))
        if t is None:
            continue
        m = re.search(r"^sigpipe: PASS (\d+) FAIL (\d+)$", t, re.M)
        s = re.search(r"^rc=(\d+) secs=(\d+)$", t, re.M)
        b = re.search(r"^bash=(\S+)", t, re.M)
        sig[(v, k)] = (m.groups() if m else None, s.groups() if s else None, b.group(1) if b else "?")
st = ["| bash | run 1 | run 2 | run 3 |", "|---|---|---|---|"]
counts = set()
for v in VERSIONS:
    row, label = [], v
    for k in (1, 2, 3):
        if (v, k) not in sig:
            row.append("(pending)")
            continue
        m, s, b = sig[(v, k)]
        label = b.split("(")[0] + (" (host)" if v == "host" else "")
        counts.add(m)
        row.append("PASS %s FAIL %s, rc %s, %s s" % (m + s) if m and s else "no summary line")
    st.append("| %s | %s |" % (label, " | ".join(row)))
st.append("")
st.append("Every run reports the same counts: %s." % (
    "yes, PASS %s FAIL %s" % next(iter(counts)) if len(counts) == 1 and None not in counts else "NO (see the logs)"))

lb = read(os.path.join(OUT, "lane_b.log")) or ""
rt = ["| bash | run | result | seconds | no-push gate, its meta-test | `test_agent` \"timeout honoured (< 20 s)\" |",
      "|---|---|---|---|---|---|"]
per_suite = []


def section_of(log, name):
    m = re.search(r"^=== %s\n(.*?)(?=^=== |\Z)" % re.escape(name), log, re.M | re.S)
    return m.group(1) if m else ""


for m in re.finditer(r"runall (\S+) r(\d) rc=(\d+) secs=(\d+) bash=(\S+) (RUN_ALL: .*)$", lb, re.M):
    v, k, rc, secs, bver, res = m.groups()
    log = read(os.path.join(OUT, "runall_%s_r%s.log" % (v, k))) or ""
    to = re.findall(r"^\s*(ok|FAIL)\s+timeout honoured \(< 20 s\)", log, re.M)
    g = re.search(r"CM-INSTALLER-NO-PUSH-NO-FORCE: (PASS|FAIL|BLIND)", section_of(log, "cm_installer_no_push_no_force.sh"))
    gm_ = re.search(r"^META (PASS|FAIL)", section_of(log, "cm_installer_no_push_no_force_mutation_test.sh"), re.M)
    rt.append("| %s | %s | %s | %s | %s | %s |" % (bver.split("(")[0] + (" (host)" if v == "host" else ""), k,
                                                  cell(res), secs, "%s, META %s" % (g.group(1) if g else "not found",
                                                                                     gm_.group(1) if gm_ else "not found"),
                                                  ", ".join(to) if to else "not printed"))
    counts_line = ";".join("%s: PASS %s FAIL %s" % x for x in re.findall(r"^(\S+): PASS (\d+) FAIL (\d+)$", log, re.M))
    per_suite.append("runall_%s_r%s %s" % (v, k, counts_line))
    if rc != "0":
        put("runs/runall_%s_r%s.log" % (v, k), log)
if per_suite:
    put("runs/runall_per_suite_counts.txt", "\n".join(per_suite) + "\n")
if "lane B done" not in lb:
    # the last run of lane B (5.2.37 r3) was cut when the agent session that ran the lane was ended (weekly API
    # limit); its partial log is kept, and the run is not counted
    part = read(os.path.join(OUT, "runall_5.2.37_r3.log"), need=False)
    if part is not None:
        put("runs/runall_5.2.37_r3.partial.log", part)
        done_suites = re.findall(r"^=== (\S+) OK \(", part, re.M)
        rt.append("| 5.2.37 | 3 | not finished: the agent session that ran lane B was ended (weekly API limit) during "
                  "this run; %d FAIL lines up to then, suites finished: %s (`runs/runall_5.2.37_r3.partial.log`); "
                  "not counted | | | |" % (len(re.findall(r"^\s*FAIL\s", part, re.M)), ", ".join(done_suites) or "none"))
    else:
        rt.append("| (pending) | | | | | |")
rt.append("")
rt.append("Per-suite PASS/FAIL counts of every run: `runs/runall_per_suite_counts.txt`; the full log is kept only for "
          "a run that failed.")
if len({x.split(" ", 1)[1] for x in per_suite}) > 1:
    rt.append("The per-suite counts differ between runs; see the file.")
elif per_suite:
    rt.append("The per-suite counts are the same in every run.")

SHORT = ["test_cli_agent_plugins", "test_install_cli_agent_plugins_ownership", "test_action_prefix_grammar",
         "meta_test_action_prefix_grammar", "test_setup_prompt_round4"]
sh = ["| suite | bash | run 1 | run 2 | run 3 |", "|---|---|---|---|---|"]
for name in SHORT:
    for v in ("host", "5.2.37"):
        row = []
        for k in (1, 2, 3):
            src = os.path.join(OUT, "short_%s__%s__r%d.txt" % (name, v, k))
            t = copy(src, "short/short_%s__%s__r%d.txt" % (name, v, k))
            if t is None:
                row.append("(pending)")
                continue
            rcm = re.search(r"^rc=(\d+) secs=(\d+)", t, re.M)
            summ = [l.strip() for l in t.splitlines() if re.search(r"\b(PASS|FAIL|passed|failed)\b.*\d", l)
                    and not l.startswith("rc=")]
            row.append("rc %s, %s s; %s" % (rcm.group(1), rcm.group(2), summ[-1] if summ else "no summary line")
                       if rcm else "no rc line")
        sh.append("| `%s` | %s | %s |" % (name, v, " | ".join(cell(x) for x in row)))
lc = read(os.path.join(OUT, "lane_c.log"), need=False) or ""
st_lines = re.findall(r"coA status after (\S+ r\d): (\d+) changed", lc)
if st_lines:
    sh.append("")
    sh.append("Changed paths in the frozen clone after each pass (the meta-test restores what it mutates): " +
              ", ".join("%s %s" % x for x in st_lines) + ".")

loads = []
for l in (read(os.path.join(OUT, "load.log")) or "").splitlines():
    p = l.split()
    if len(p) >= 2:
        loads.append(float(p[1]))
load_range = ("between %.0f and %.0f (1-minute average, sampled every 5 minutes, `runs/load.log`)"
              % (min(loads), max(loads)) if loads else "(pending)")

# ---- perf, landing, f9 ----
copy(os.path.join(FINAL, "perf_push_changed.txt"), "perf/perf_push_changed.txt")
copy(os.path.join(FINAL, "trial_merge_A.txt"), "landing/trial_merge.txt")
copy(os.path.join(FINAL, "verify_c3.txt"), "landing/manifest_verify.txt")
copy(os.path.join(FINAL, "verify_base.txt"), "landing/manifest_verify_base.txt")
copy(os.path.join(FINAL, "f9_search.sh"), "f9/f9_search.sh")
copy(os.path.join(FINAL, "f9_search.txt"), "f9/f9_search.txt")

# ---- tools (renamed so the full-suite census does not read them as tests) ----
for src, rel in (("sigscan.py", "sigscan.py"), ("xcheck.py", "xcheck.py"), ("kill_table_runner.py", "kill_table_runner.py"),
                 ("byte_identity.sh", "byte_identity.sh"), ("timing.sh", "timing.sh"), ("timing_cost.sh", "timing_cost.sh"),
                 ("lane_a.sh", "lane_a.sh"), ("lane_b.sh", "lane_b.sh"), ("lane_c.sh", "lane_c.sh"),
                 ("bash_facts.sh", "bash_facts.sh"), ("assemble_evidence.py", "assemble_evidence.py"),
                 ("amp_scan.py", "amp_scan.py"), ("byte_identity_run.sh", "byte_identity_run.sh"),
                 ("inventory.sh", "inventory.sh"), ("inventory_counts.py", "inventory_counts.py"),
                 ("reset_facts.sh", "reset_facts.sh"), ("gate_by_commit.sh", "gate_by_commit.sh"),
                 ("gate_mask_mutants.py", "gate_mask_mutants.py.txt"), ("gate_feed_probe.py", "gate_feed_probe.py"),
                 ("exit3_sentinel.sh", "exit3_sentinel.sh"), ("exit3_census.py", "exit3_census.py"),
                 ("trial_merge.sh", "trial_merge.sh"),
                 ("build_test.py", "build_sigpipe_check.py"), ("test_sigpipe.tmpl.sh", "sigscan_check_template.sh.txt"),
                 ("shenum/main.go", "shenum_main.go.txt"), ("shenum/go.mod", "shenum_go.mod.txt"),
                 ("shenum/go.sum", "shenum_go.sum.txt")):
    copy(os.path.join(TOOLS, src), "tools/" + rel)
copy(os.path.join(FINAL, "caller_shell_compare.sh"), "tools/caller_shell_compare.sh")

# ---- bash sources ----
bs = ["# bash copies used in round 2: version, sha256 of the binary, image id, image (already on the host, not pulled)"]
for v, iid, img in SOURCES:
    p = os.path.join(W, "bashes", v, "bash.bin")
    bs.append("%-7s %s %s %s" % (v, sha256(p) if os.path.exists(p) else "MISSING", iid, img))
hv = subprocess.run(["/usr/bin/bash", "-c", "echo $BASH_VERSION"], capture_output=True, text=True).stdout.strip()
bs.append("%-7s %s host /usr/bin/bash (%s)" % ("host", sha256("/usr/bin/bash"), hv))
put("bash_sources.txt", "\n".join(bs) + "\n")

# ---- here-string table ----
hs = read(os.path.join(FINAL, "facts", "herestring_storage.txt")) or ""
ht = []
for l in hs.splitlines():
    if l.startswith("#") or ":" not in l:
        continue
    ver, rest = l.split(":", 1)
    left, _, right = rest.partition("|")
    cells = [x.split(":") for x in left.split()]
    comp = [x.split(":") for x in right.split()]
    if not ht:
        ht.append("| bash | " + " | ".join(c[0] for c in cells) + " | BASH_COMPAT=50, 100 | BASH_COMPAT=50, 102400 |")
        ht.append("|---" * (len(cells) + 3) + "|")
    v = ver.split("(")[0]
    ht.append("| %s | %s | %s |" % (v + (" (host)" if v == hv.split("(")[0] else ""), " | ".join(c[1] for c in cells),
                                    " | ".join(c[2] for c in comp)))
ht = ht[:2] + sorted(ht[2:], key=lambda row: vkey(row.split("|")[1].strip().split(" ")[0])) if ht else ["(missing)"]

# ---- F9: the test_round8 commit (section 13) ----
TR8 = os.path.join(W, "tr8")
OTHER = os.path.join(os.path.dirname(W), "tr8.9L1GJp")                    # the other agent's proposal and trials
REVIEW = os.path.join(os.path.dirname(W), "review_installer_sigpipe.K0SeAS", "probes")
E3 = (read(os.path.join(FINAL, "EVDIR3")) or "").strip()
OUT3 = os.path.join(E3, "out")
TR8_HEAD = subprocess.run(["git", "-C", os.path.join(E3, "coT"), "rev-parse", "HEAD"], capture_output=True,
                          text=True).stdout.strip() if E3 else ""
if not re.fullmatch(r"[0-9a-f]{40}", TR8_HEAD):
    missing.append(os.path.join(E3, "coT") + " (no commit)")
TR8_HEAD8 = TR8_HEAD[:8] if TR8_HEAD else "(unknown)"
for src, rel in (("needles_red_proposed.txt", "red_proposed_probe_pipe_form.txt"),
                 ("red_drain_group_vs_session.txt", "red_group_drain_misses_own_group_member.txt"),
                 ("pgid_race_probe.txt", "pgid_before_setsid_probe.txt"),
                 ("gate_no_push_wt.txt", "gate_no_push_on_the_change.txt"),
                 ("sc_old.txt", "shellcheck_warnings_before.txt"), ("sc_new.txt", "shellcheck_warnings_after.txt")):
    copy(os.path.join(TR8, src), "tr8/" + rel)
TR8V = ["host", "5.0.17", "5.2.37"]
nd = ["| bash | run 1 | run 2 | run 3 |", "|---|---|---|---|"]
for v in TR8V:
    row = []
    for k in (1, 2, 3):
        t = copy(os.path.join(TR8, "session", "needles_%s.%d.txt" % (v, k)), "tr8/needles_%s_r%d.txt" % (v, k))
        m = re.search(r"^needles: (PASS \d+ FAIL \d+)$", t or "", re.M)
        row.append(m.group(1) if m else "(missing)")
    nd.append("| %s | %s |" % (v, " | ".join(row)))
tm = {}
for v in TR8V:
    copy(os.path.join(TR8, "session", "tr8_mutants_%s.log" % v), "tr8/mutants_%s.log" % v)
    copy(os.path.join(TR8, "session", "tr8_mutants_%s.tsv" % v), "tr8/mutants_%s.tsv" % v)
    tm[v] = {r["id"]: r for r in tsv(os.path.join(TR8, "session", "tr8_mutants_%s.tsv" % v))}
mt8 = ["| ID | Mutation | " + " | ".join(TR8V) + " | First failing needle (host) |", "|---" * (len(TR8V) + 3) + "|"]
for mid in sorted(tm.get("host", {}), key=lambda x: int(x[2:])):
    r = tm["host"][mid]
    mt8.append("| %s | %s | %s | %s |" % (mid, cell(r["mutation"]), " | ".join(tm[v].get(mid, {}).get("verdict", "?")
                                                                               for v in TR8V),
                                          cell(r["first failing needle"])))
alive8 = ["%s on %s" % (mid, v) for v in TR8V for mid, r in tm[v].items() if r["verdict"] != "KILLED"]
mt8.append("")
mt8.append("%d mutants on %d bash versions: %s." % (len(tm.get("host", {})), len(TR8V),
                                                    "NOT KILLED: " + ", ".join(alive8) if alive8 else "every one killed"))
# the other agent's material, unchanged (paths scrubbed)
for src, rel in (("proposed_test_round8.diff", "proposed_test_round8.diff"),
                 ("runs/git_lock_race_1.jsonl", "git_lock_race_1.jsonl"),
                 ("runs/timeout_probe_e7.jsonl", "timeout_probe_e7.jsonl"),
                 ("runs/e7_strace_uutils.txt", "e7_strace_uutils.txt"), ("runs/e7_strace_gnu.txt", "e7_strace_gnu.txt")):
    copy(os.path.join(OTHER, src), "tr8/other_agent/" + rel)
b20 = []
for k in range(1, 21):
    t = read(os.path.join(OTHER, "runs", "base20", "run%d.log" % k)) or ""
    m = re.findall(r"^round8: PASS \d+ FAIL \d+$", t, re.M)
    b20.append("run%-2d %s" % (k, m[-1] if m else "(no summary line)"))
put("tr8/other_agent/base20_results.txt", "# the unchanged test_round8.sh run 20 times by the other agent (logs "
    "runs/base20/run<n>.log, not copied): the last summary line of each\n" + "\n".join(b20) + "\n")
races = {}
for l in (read(os.path.join(OTHER, "runs", "git_lock_race_1.jsonl")) or "").splitlines():
    try:
        r = json.loads(l)
    except ValueError:
        continue
    races.setdefault(r.get("arm"), []).append(bool(r.get("lock_left")))
race_txt = ", ".join("%s arm: lock left in %d of %d" % (a, sum(v), len(v)) for a, v in sorted(races.items())) \
    or "(missing)"
b20_pass = sum(1 for x in b20 if x.endswith("PASS 86 FAIL 0"))
# lanes T and U: test_round8 alone and run_all.sh --quick on the frozen clones of the test_round8 commit
for n in ("lane_t.log", "lane_u.log", "load.log"):
    copy(os.path.join(OUT3, n), "tr8/runs/" + n)
lt = (read(os.path.join(OUT3, "lane_t.log")) or "") + (read(os.path.join(OUT3, "lane_u.log")) or "")
r8 = ["| bash | run | exit status | result | seconds |", "|---|---|---|---|---|"]
for m in re.finditer(r"round8 (\S+) r(\d) rc=(\d+) secs=(\d+) bash=(\S+) ?(.*)$", lt, re.M):
    v, k, rc, secs, bver, res = m.groups()
    copy(os.path.join(OUT3, "round8_%s_r%s.log" % (v, k)), "tr8/runs/round8_%s_r%s.log" % (v, k))
    r8.append("| %s | %s | %s | %s | %s |" % (bver.split("(")[0] + (" (host)" if v == "host" else ""), k, rc,
                                             cell(res) or "no summary line", secs))
if "lane T done" not in lt:
    r8.append("| (pending) | | | | |")
ra8 = ["| bash | run | result | seconds | `test_round8` in this run | `test_agent` \"timeout honoured (< 20 s)\" |",
       "|---|---|---|---|---|---|"]
ps8 = []
for m in re.finditer(r"runall (\S+) r(\d) rc=(\d+) secs=(\d+) bash=(\S+) ?(.*)$", lt, re.M):
    v, k, rc, secs, bver, res = m.groups()
    res = res or "no RUN_ALL summary line (rc=%s)" % rc
    log = read(os.path.join(OUT3, "runall_%s_r%s.log" % (v, k))) or ""
    to = re.findall(r"^\s*(ok|FAIL)\s+timeout honoured \(< 20 s\)", log, re.M)
    r8c = re.findall(r"^round8: (PASS \d+ FAIL \d+)$", log, re.M)
    ra8.append("| %s | %s | %s | %s | %s | %s |" % (bver.split("(")[0] + (" (host)" if v == "host" else ""), k,
                                                   cell(res), secs, r8c[-1] if r8c else "not found",
                                                   ", ".join(to) if to else "not printed"))
    ps8.append("runall_%s_r%s %s" % (v, k, ";".join("%s: PASS %s FAIL %s" % x for x in
                                                   re.findall(r"^(\S+): PASS (\d+) FAIL (\d+)$", log, re.M))))
    if rc != "0":
        put("tr8/runs/runall_%s_r%s.log" % (v, k), log)
if ps8:
    put("tr8/runs/runall_per_suite_counts.txt", "\n".join(ps8) + "\n")
if "lane T done" not in lt or "lane U done" not in lt:
    ra8.append("| (pending) | | | | | |")
ra8.append("")
ra8.append("Per-suite counts: `tr8/runs/runall_per_suite_counts.txt`; the full log is kept only for a run that failed.")
loads3 = [float(l.split()[1]) for l in (read(os.path.join(OUT3, "load.log")) or "").splitlines() if len(l.split()) >= 2]
load3 = ("between %.0f and %.0f (`tr8/runs/load.log`)" % (min(loads3), max(loads3))) if loads3 else "(pending)"

# ---- the review's alternative patch (section 14) ----
ALTX = os.path.join(W, "altx")
for n in ("edge_marks_alt_vs_head.txt", "edge_marks_alt_vs_negctl.txt", "repro_harness_head.txt",
          "notemp_r1_head_alt.txt", "alt_patch_vs_head_source.txt", "NOTE_repro_harness_head_notemp50.txt",
          "repro_harness_head_notemp50.INVALID.txt"):
    copy(os.path.join(ALTX, n), "altpatch/" + n)
copy(os.path.join(REVIEW, "alt_patch", "repro_harness_alt.txt"), "altpatch/review_repro_harness_alt.txt")
copy(os.path.join(REVIEW, "alt_patch", "hi_push_changed.diff"), "altpatch/review_alt_patch.diff")
neg = subprocess.run(["diff", os.path.join(ALTX, "install_constitution.head.sh"),
                      os.path.join(ALTX, "install_constitution.negctl.sh")], capture_output=True, text=True).stdout
put("altpatch/negative_control_installer.diff", "# the negative-control installer: the head with the after-marks "
    "removed from the Z check (diff head negctl)\n" + neg)
if not neg.strip():
    missing.append("altpatch negative control: no difference between head and negctl")
for n in ("notemp_run.sh",):
    copy(os.path.join(ALTX, n), "tools/" + n)
for n, rel in (("tr8_needles.sh", "tr8_needles.sh"), ("tr8_mutants.py", "tr8_mutants.py.txt"),
               ("lane_t.sh", "lane_t.sh"), ("lane_u.sh", "lane_u.sh")):
    copy(os.path.join(TOOLS, n), "tools/" + rel)
nt = read(os.path.join(ALTX, "notemp_r1_head_alt.txt")) or ""
alt_rows = ["| bash | installer | condition | here-string readable (needle) | Z refused, 4 sizes | moved ref seen | changed L seen | unchanged marks proceed |",
            "|---|---|---|---|---|---|---|---|"]
for blk in re.split(r"^== ", nt, flags=re.M)[1:]:
    hdr = blk.splitlines()[0]
    hm = re.match(r"bash=(\S+) installer=(\S+) \((\w+)\) mode=(\S+)", hdr)
    if not hm:
        continue
    z = re.findall(r"Z=(refused|missed)", blk)
    mv = re.findall(r"moved_ref_rc=(\d)", blk)
    cl = re.findall(r"changed_L_rc=(\d)", blk)
    un = re.findall(r"unchanged_rc=(\d)", blk)
    rd = re.search(r"needle_small_herestring_readable=(\w+)", blk)
    alt_rows.append("| %s | %s | %s | %s | %d of %d | %d of %d | %d of %d | %d of %d |" % (
        hm.group(1), {"r1": "round 1 (6f28765c)", "head": "head (%s)" % HEAD8, "alt": "review's alternative"}.get(
            hm.group(2), hm.group(2)), {"temp": "temporary file writable", "notemp": "no temporary file"}.get(
            hm.group(4), hm.group(4)), rd.group(1) if rd else "?", z.count("refused"), len(z), mv.count("0"), len(mv),
        cl.count("0"), len(cl), un.count("1"), len(un)))
if "notemp_run: done" not in nt:
    missing.append(os.path.join(ALTX, "notemp_r1_head_alt.txt") + " (not finished)")

# ---- README ----
tmpl = read(os.path.join(W, "stage", "README.round2.tmpl.md"))
limits = read(os.path.join(W, "stage", "limits.md"))
bi = read(os.path.join(FINAL, "byte_identity.txt")) or ""
inv = read(os.path.join(FINAL, "inventory_counts.md")) or ""

DESC = [
    ("README.md", "this document"), ("SHA256SUMS", "sha256 of every other file"),
    ("bash_sources.txt", "where each bash copy came from, with its sha256"),
    ("inventory/shenum_rebuild.txt", "offline rebuild of shenum, identical binary"),
    ("inventory/shenum_", "the AST inventory rows (base and head)"), ("inventory/sigscan_", "scanner findings (base: 49, head: 0)"),
    ("inventory/xcheck_", "cross-check of the two instruments"), ("inventory/inventory_counts.md", "the counts table of section 5"),
    ("inventory/sigpipe_check_rebuild.txt", "the template build equals tests/install/test_sigpipe.sh"),
    ("compare/reset_facts.txt", "section 4, facts 9 and 10"), ("gate/", "section 9"),
    ("runs/superseded_58815d75/", "the runs on 58815d75, stopped and not counted (section 10)"),
    ("runs/sentinel*", "the exit-3 sentinel beside lane B (section 10)"),
    ("runs/host_samples.tsv", "host samples of the sentinel, one per minute"),
    ("landing/manifest_verify_base.txt", "run_full_suite.sh --verify-manifest on main bd0036bd alone"),
    ("compare/patsub_amp_scan.txt", "section 15, item 15"), ("compare/byte_identity.txt", "section 7"), ("compare/caller_shell_compare_host.txt", "section 7, caller shell"),
    ("compare/", "section 4 facts, produced by tools/bash_facts.sh"),
    ("kill/", "section 8 (tsv: one row per mutant; log: the same rows with the control run)"),
    ("runs/sigpipe_", "test_sigpipe.sh output, one file per bash and run"),
    ("runs/runall_", "run_all.sh results"), ("runs/lane_", "lane logs (start, end, exit status of every run)"),
    ("runs/load.log", "host load samples"), ("short/", "short-suite output, one file per suite, bash and run"),
    ("perf/", "section 11"), ("landing/trial_merge.txt", "section 12"),
    ("landing/manifest_verify.txt", "run_full_suite.sh --verify-manifest on the fix commit"),
    ("tr8/red_", "section 13: the RED runs on the proposal (its lock probe, its group drain)"),
    ("tr8/pgid_before_setsid_probe.txt", "section 13: could the loop read the test's own group as the installer's"),
    ("tr8/gate_no_push_on_the_change.txt", "CM-INSTALLER-NO-PUSH-NO-FORCE on the working tree with the change"),
    ("tr8/shellcheck_", "shellcheck warnings of test_round8.sh before and after the change (the same set)"),
    ("tr8/needles_", "section 13: the control needles, three runs per bash"),
    ("tr8/mutants_", "section 13: mutants TM1 to TM12 (tsv: one row per mutant; log: with the control run)"),
    ("tr8/other_agent/", "the other agent's proposal and trials (unchanged except paths)"),
    ("tr8/runs/", "section 13: test_round8.sh alone and run_all.sh --quick on the test_round8 commit"),
    ("altpatch/", "section 14: the review's alternative patch against the head"),
    ("runs/runall_5.2.37_r3.partial.log", "the unfinished last run of lane B (section 10)"),
    ("f9/", "section 13"), ("tools/", "the scripts that produced this directory (renamed so that the suite census "
                                     "does not count them as tests)"),
]


def describe(rel):
    for pre, d in DESC:
        if rel == pre or (pre.endswith(("/", "_")) and rel.startswith(pre)) or \
                (pre.endswith("*") and rel.startswith(pre[:-1])):
            return d
    return ""


files = sorted(set(written) | {"README.md", "SHA256SUMS"})
by_desc = {}
for rel in files:
    by_desc.setdefault(describe(rel), []).append(rel)
fl = ["| Path | What it is |", "|---|---|"]
for d, rels in sorted(by_desc.items(), key=lambda kv: kv[1][0]):
    if len(rels) > 3:
        shown = "`%s*` (%d files)" % (os.path.commonprefix(rels), len(rels))
    else:
        shown = ", ".join("`%s`" % r for r in rels)
    fl.append("| %s | %s |" % (shown, d or "-"))

rep = {
    "{{HERESTRING_TABLE}}": "\n".join(ht),
    "{{INVENTORY_TABLE}}": inv.strip(),
    "{{BYTE_IDENTITY}}": "```\n" + bi.strip() + "\n```",
    "{{KILL_TABLE}}": "\n".join(kt),
    "{{TWIN_TABLE}}": "\n".join(tt),
    "{{NOSTOP_NOTE}}": note,
    "{{LOAD_RANGE}}": load_range,
    "{{SIGPIPE_TABLE}}": "\n".join(st),
    "{{RUNALL_TABLE}}": "\n".join(rt),
    "{{SHORT_TABLE}}": "\n".join(sh),
    "{{LIMITS}}": (limits or "").strip(),
    "{{FILES}}": "\n".join(fl),
    "{{GATE_BY_COMMIT}}": "\n".join(gt),
    "{{GM_TABLE}}": "\n".join(gm),
    "{{GATE_META}}": gate_meta,
    "{{EXIT3_NOTE}}": exit3_note,
    "{{TR8_NEEDLES}}": "\n".join(nd),
    "{{TR8_MUTANTS}}": "\n".join(mt8),
    "{{TR8_ROUND8}}": "\n".join(r8),
    "{{TR8_RUNALL}}": "\n".join(ra8),
    "{{TR8_LOAD}}": load3,
    "{{RACE}}": race_txt,
    "{{B20}}": "%d of 20" % b20_pass,
    "{{ALT_TABLE}}": "\n".join(alt_rows),
}
# {{HEAD}} last: the limits and the exit-3 note carry it too
rep_last = {"{{HEAD}}": HEAD8, "{{TR8_HEAD}}": TR8_HEAD8}
doc = tmpl or ""
for k, v in list(rep.items()) + list(rep_last.items()):
    doc = doc.replace(k, v)
put("README.md", doc)
left = re.findall(r"\{\{[A-Z0-9_]+\}\}", doc)

# ---- SHA256SUMS ----
sums = []
for root, _, fs in os.walk(DEST):
    for n in fs:
        rel = os.path.relpath(os.path.join(root, n), DEST)
        if rel != "SHA256SUMS":
            sums.append("%s  %s" % (sha256(os.path.join(root, n)), rel))
with open(os.path.join(DEST, "SHA256SUMS"), "w", encoding="utf-8") as f:
    f.write("\n".join(sorted(sums, key=lambda s: s.split("  ", 1)[1])) + "\n")

for p in missing:
    print("missing input: " + p, file=sys.stderr)
for k in left:
    print("placeholder left: " + k, file=sys.stderr)
print("assemble_evidence: %d files written to %s%s" % (len(sums) + 1, DEST, " (draft)" if DRAFT else ""))
sys.exit(1 if (missing or left) else 0)
