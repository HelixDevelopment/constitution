"""Reviewer mutants (round-9 review of v9). Each is one exact-once text replacement in a COPY.
Lint mutants: killers = test_secret_shapes.py, fixture self-check, census (gap/fp), reviewer probe (verdict
vector differs from the unmutated lint). Re-mint mutants: listed only (run by rev_remint_mut.sh in a
worktree copy). Usage: rev_mutants.py <v9 root> <outdir> lint|list-remint"""
import os, subprocess, sys, hashlib

ROOT, OUT, MODE = sys.argv[1], sys.argv[2], sys.argv[3]
LINT = os.path.join(ROOT, "scripts/workable-items/intake_lint.py")
PACK = os.path.join(ROOT, "docs/qa/tracker_intake_2026_11_15_v9")
PROBE = "/mnt/DATA1TB/claude-work/scratch/rev_ti9b.ynLd/tools/probe_v9.py"
env = dict(os.environ, TMPDIR="/mnt/DATA1TB/claude-work/tmp")

LM = [
    ("XL1 view layers 3->2", "SECRET_VIEW_LAYERS = 3", "SECRET_VIEW_LAYERS = 2"),
    ("XL2 CGJ U+034F not an invisible char", 'INVISIBLE_CHAR = re.compile("[\\u034f', 'INVISIBLE_CHAR = re.compile("['),
    ("XL3 'word' removed from META_WORDS", '"word", "words",', '"words",'),
    ("XL4 wildcard admits 3 odd letters", "return odd <= 2", "return odd <= 3"),
    ("XL5 wildcard for 4-letter heads", "or len(h) < 5:", "or len(h) < 4:"),
    ("XL6 identifier value excluded after strong keys too",
     '    if tier in ("short", "generic") and _IDENT_VALUE.match(v):',
     '    if _IDENT_VALUE.match(v):'),
    ("XL7 'public' not a key negative", '"public", "pub",', '"pub",'),
    ("XL8 'csrf' not a token negative", '"csrf", "xsrf"', '"xsrf"'),
    ("XL9 reference URI needs no / or #", r'r"^[A-Za-z][A-Za-z0-9+.-]{1,}:(?://)?\S*[/#]"', r'r"^[A-Za-z][A-Za-z0-9+.-]{1,}:(?://)?\S*"'),
    ("XL10 PIN needs 5 digits", "[0-9]{4,12}", "[0-9]{5,12}"),
    ("XL11 join view: no concatenation operator", r"(?:\+|\.|\|\|)?", ""),
    ("XL12 Hangul filler U+3164 kept in a key", '_FILLERS = frozenset("ᅟᅠㅤﾠ")', '_FILLERS = frozenset("ᅟᅠﾠ")'),
    ("XL13 entity view needs the '&' only", "if SECRET_DECODE_ENTITIES and \"&\" in t and _ENT.search(t)", "if SECRET_DECODE_ENTITIES and \"&\" in t"),
    ("XL14 max views 24->4", "SECRET_MAX_VIEWS = 24", "SECRET_MAX_VIEWS = 4"),
]

def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return p.returncode, p.stdout + p.stderr

def probe_vec(lint_path):
    rc, out = run([sys.executable, "-I", PROBE, lint_path, os.path.join(PACK, "tools/leak_scan.py")])
    vec = "\n".join(l.split(" scan=")[0] for l in out.splitlines() if l.startswith(("POS", "NEG")))
    return rc, hashlib.sha256(vec.encode()).hexdigest()[:16], out

def killers(lint_path, base_vec=None):
    res = []
    rc, out = run([sys.executable, "-I", os.path.join(ROOT, "tests/workable_items/test_secret_shapes.py"), lint_path])
    res.append(("shapes", rc != 0, out.strip().splitlines()[-1] if out.strip() else ""))
    rc, out = run([sys.executable, "-I", os.path.join(PACK, "tools/secret_class_census.py"), lint_path])
    last = out.strip().splitlines()[-1] if out.strip() else ""
    res.append(("census", rc != 0 or "gap=0 fp=0" not in last, last))
    rc, vec, out = probe_vec(lint_path)
    res.append(("probe", base_vec is not None and vec != base_vec, vec))
    return res

if MODE == "lint":
    src = open(LINT, encoding="utf-8").read()
    os.makedirs(OUT, exist_ok=True)
    ctl = os.path.join(OUT, "control_intake_lint.py")
    open(ctl, "w", encoding="utf-8").write(src)
    _, base_vec, _ = probe_vec(ctl)
    kc = killers(ctl, base_vec)
    print("CONTROL", " ".join("%s=%s" % (n, "KILL" if k else "ok") for n, k, _ in kc), "probe_vec=" + base_vec)
    for mid, old, new in LM:
        n = src.count(old)
        if n != 1:
            print("STALE %s count=%d" % (mid, n)); continue
        p = os.path.join(OUT, "m_%s.py" % mid.split()[0])
        open(p, "w", encoding="utf-8").write(src.replace(old, new))
        ks = killers(p, base_vec)
        killed = [n_ for n_, k, _ in ks if k]
        print("%s %s killers=%s | %s" % ("KILLED" if killed else "SURVIVED", mid, ",".join(killed) or "-",
                                         " ; ".join("%s:%s" % (n_, d[:70]) for n_, _, d in ks)))
