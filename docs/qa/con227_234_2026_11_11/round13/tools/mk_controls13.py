#!/usr/bin/env python3
"""Round 13: rebuild tests/release/netgate_controls.jsonl.
- the round-12 controls are kept (same names, same bodies); their patterns are re-derived from the round-13 analyser
  (the reason text changed); the seven round-12 pass controls the positive shape now refuses are kept as finding
  controls NAME_r12shape and their pass controls get the shape the real scripts use (names on the pin's name list,
  pinned awk and sed programs, sort -V, sqlite3 -safe first, exec of fd 4)
- added: the round-12 reviewer's oracle cases (cases_r1/r2/r2b, deduplicated by name) and discriminating fixtures,
  the MR5 and MR10 fixtures, and the round-13 fixer's own fixtures (cases_r13.json); @SB@ and @PORT@ (sandbox path and
  loopback port of the oracle) are replaced by the fixed literals /nonexistent/sb and 9 (the gate never runs them)
A pattern is the first finding that is not the name-list finding (else the name-list finding), up to " | " (never
script text), at most 110 characters; every pattern is checked to occur in the output it came from.
usage: mk_controls13.py REPO CASEDIR OUT.jsonl WORKDIR"""
import json, os, subprocess, sys

repo, casedir, out, work = sys.argv[1:5]
cen = os.path.join(repo, "tests/release/channel_census.py")
pin = os.path.join(repo, "tests/release/netgate_pin.tsv")
H = "#!/usr/bin/env bash\nrc_net git status\n"
NEWPASS = {
    "G28_rcnet_tempenv_secret": H + "M3W_GITEA_TOKEN=v rc_net git fetch origin\n",
    "CP01_sed_ranges": H + "sed 's/ $//' f\nsed '/^$/d' f\nsed -n '2,29p' \"$0\"\nsed 's/^ *//' f\n",
    "CP02_awk_or_regex": H + "awk -F '\\t' -v t=x '$2==t{print $1; exit}' f\nawk '/^## /{print substr($0,4); exit}' f\n",
    "CP03_sort_and_sqlite": H + "printf '%s\\n' b a | sort -V\nprintf '%s\\n' b a | sort\n"
                            "sqlite3 -safe -readonly -batch -noheader db 'select 1'\n",
    "CP05_builtins": H + "f() { local - ; local x; unset -v x; }\nf\ncommand -v git >/dev/null\n",
    "CP06_names": H + "printf '%s\\n' x\nread -r -d '' k <f\nx=$(( 1 + 2 ))\ndeclare -A OK\n",
    "CP08_exec_redirections": H + "exec 9<&-\n{ exec 3>/dev/null; } 2>/dev/null\nexec 4>&1\nexec 1>&4 4>&-\n",
}


def run(name, body):
    d = os.path.join(work, name)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, name + ".sh")
    open(p, "w").write(body)
    r = subprocess.run(["/usr/bin/python3", "-I", cen, "netgate", "--pin", pin, "--analyser-only", p],
                       env={"PATH": "/nonexistent", "LANG": "C.UTF-8"}, capture_output=True, text=True)
    return r.returncode, r.stdout


# the reason a control is about, where the first finding is another one (a mutant of that rule must fail the control)
PREFER = {"D7_awk_attached_f": "the option -f/dev/stdin", "D9_sort_compress_sep": "sort that can run a command",
          "G15_alias": "builtin alias", "O45_dev_tcp": "a redirection to a device file",
          "CI04_dev_tcp": "a redirection to a device file", "R94_ctrl_dev_tcp": "a redirection to a device file"}


def pattern(o, name):
    fl = [l[8:] for l in o.splitlines() if l.startswith("FINDING ")]
    pref = [f for f in fl if PREFER[name] in f] if name in PREFER else []
    pref = pref or [f for f in fl if "not on the name list of the pin" not in f] or fl
    if not pref:
        return ""
    p = pref[0].split(" | ")[0][:110]
    assert p in o
    return p


rows = []
for l in open(os.path.join(repo, "tests/release/netgate_controls.jsonl")):
    r = json.loads(l)
    if r["want"] == "pass" and r["name"] in NEWPASS:
        old = dict(r, name=r["name"] + "_r12shape", want="finding",
                   src=r.get("src", "") + "; round 13: the round-12 pass shape, refused by the positive shape")
        rows.append(old)
        r = dict(r, body=NEWPASS[r["name"]], src="round 13: the shape the real scripts use")
    rows.append(r)
seen = {r["name"] for r in rows}
for f, src in (("cases_r1.json", "reviewer-r12 oracle"), ("cases_r2.json", "reviewer-r12 oracle"),
               ("cases_r2b.json", "reviewer-r12 oracle"), ("cases_r13.json", "")):
    for c in json.load(open(os.path.join(casedir, f))):
        if c["name"] in seen:
            continue
        seen.add(c["name"])
        s = src or ("reviewer-r12 discriminate" if c["name"].startswith(("D", "MR")) else "fixer-r13")
        rows.append({"body": c["body"].replace("@SB@", "/nonexistent/sb").replace("@PORT@", "9"), "name": c["name"],
                     "pattern": "", "src": s, "want": "pass" if c["name"] == "R92_ctrl_neg_clean" else "finding"})
bad = 0
with open(out, "w") as fh:
    for r in rows:
        rc, o = run(r["name"], r["body"])
        if r["want"] == "pass":
            r["pattern"] = ""
            if rc != 0:
                bad += 1
                print("PASS-CONTROL-FAILS", r["name"], o.splitlines()[0][:150])
        else:
            r["pattern"] = pattern(o, r["name"])
            if rc != 1 or not r["pattern"]:
                bad += 1
                print("FINDING-CONTROL-PASSES", r["name"], rc)
        fh.write(json.dumps({k: r[k] for k in ("body", "name", "pattern", "src", "want")}, ensure_ascii=False,
                            sort_keys=True) + "\n")
        print("%-40s %-7s %s" % (r["name"], r["want"], r["pattern"][:100]))
print("rows=%d bad=%d finding=%d pass=%d" % (len(rows), bad, sum(r["want"] == "finding" for r in rows),
                                             sum(r["want"] == "pass" for r in rows)))
