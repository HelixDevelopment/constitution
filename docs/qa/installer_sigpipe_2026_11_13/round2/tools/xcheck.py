import collections, subprocess, sys
# cross-check sigscan --pipes against shenum PIPE rows: per file, multiset of (reader, class)
W, root, files = sys.argv[1], sys.argv[2], sys.argv[3:]
ALLOW = {"hi_text_filter", "hi_scrub", "hi_mark_hash", "hi_newest_tag"}
def norm_shenum(r):
    name, cls = r.rsplit(":", 1)
    name = name.split("+")[-1]
    if name.startswith("*syntax."):
        return ("compound", "UNKNOWN")
    m = {"ALL": "ALL", "EARLY": "EARLY", "EARLY?": "EARLY", "INTERP": "UNKNOWN", "COMPOUND": "UNKNOWN", "DYNAMIC": "UNKNOWN", "UNKNOWN": "UNKNOWN"}
    if cls == "FUNC":
        return (name, "ALL" if name in ALLOW else "UNKNOWN")
    if name == "DYNAMIC":
        name = "dynamic"
    return (name, m[cls])
def norm_scan(what, cls):
    if what.endswith(" (allowed function)"):
        what = what[:-len(" (allowed function)")]
    if what.startswith("compound"):
        what = "compound"
    if what == "until-loop":
        what = "while-loop"
    if what.startswith("dynamic command"):
        what = "dynamic"
    return (what, "EARLY" if cls.startswith("EARLY") else cls)
ok = True
for f in files:
    sh = subprocess.run([W + "/tools/shenum/shenum", f], cwd=root, capture_output=True, text=True).stdout
    a = collections.Counter()
    for row in sh.splitlines():
        c = row.split("\t")
        if c[3] != "PIPE":
            continue
        rd = c[6].split(" readers=", 1)[1].split(" | ", 1)[0]
        for r in rd.split(","):
            a[norm_shenum(r)] += 1
    sc = subprocess.run(["python3", "-I", W + "/tools/sigscan.py", "--allow-func", ",".join(sorted(ALLOW)), "--pipes", f], cwd=root, capture_output=True, text=True)
    b = collections.Counter()
    for row in sc.stdout.splitlines():
        c = row.split("\t")
        if len(c) != 5:
            print("BAD ROW", row); ok = False; continue
        b[norm_scan(c[3], c[4])] += 1
    same = a == b
    ok = ok and same and sc.returncode == 0
    print("%-40s shenum=%3d sigscan=%3d rc=%d %s" % (f, sum(a.values()), sum(b.values()), sc.returncode, "SAME" if same else "DIFF"))
    if not same:
        print("  only shenum:", dict(a - b)); print("  only sigscan:", dict(b - a))
print("XCHECK", "PASS" if ok else "FAIL")
