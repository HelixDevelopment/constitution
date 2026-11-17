"""locale_probe.py <workdir> <gate>: does the REAL gate's verdict depend on the caller's locale (census class L)?
For each of the four bash `=~` range sites (census rows 190, 191, 257, 260) one waiver case is built whose field holds a
non-ASCII character that glibc's en_US.UTF-8 collation puts inside the ASCII range of that site, plus an ASCII control
case; each case runs the gate under LC_ALL=C.UTF-8 and LC_ALL=en_US.UTF-8. Prints one line per case:
<case> C.UTF-8=<rc> en_US.UTF-8=<rc> [differs]. Exit 0 always (it measures; it does not judge).
Locale names are checked first: a locale that `locale -a` does not list makes the probe print BLIND and exit 2."""
import datetime, os, subprocess, sys
w, gate = sys.argv[1], sys.argv[2]
LOCS = ["C.UTF-8", "en_US.UTF-8"]
have = subprocess.run(["locale", "-a"], capture_output=True, text=True).stdout.lower().replace("-", "").split()
for l in LOCS:
    if l.lower().replace("-", "") not in have:
        print("BLIND: locale %s not installed" % l); sys.exit(2)
base_env = dict(os.environ, GIT_AUTHOR_NAME="p", GIT_AUTHOR_EMAIL="p@x", GIT_COMMITTER_NAME="p",
                GIT_COMMITTER_EMAIL="p@x", GIT_CONFIG_NOSYSTEM="1", HOME=os.path.join(w, "home"), TZ="UTC")
os.makedirs(base_env["HOME"], exist_ok=True)
def g(*a, cwd=None):
    return subprocess.run(["git", *a], cwd=cwd, env=base_env, check=True, capture_output=True, text=True).stdout.strip()
g("config", "--global", "protocol.file.allow", "always")
up = os.path.join(w, "up"); os.makedirs(up); g("init", "-q", "-b", "main", cwd=up)
shas = []
for i in range(3):
    open(os.path.join(up, "f"), "w").write(str(i)); g("add", "f", cwd=up); g("commit", "-q", "-m", str(i), cwd=up)
    shas.append(g("rev-parse", "HEAD", cwd=up))
exp = (datetime.datetime.now(datetime.timezone.utc).date() + datetime.timedelta(days=10)).isoformat()
SUP = "²³¹"            # superscript two, three, one
CASES = [  # name, config text (BASE commit), item, expiry
    ("item-ascii-control", "", "CON-046", exp),
    ("item-superscript-digits", "", "CON-" + SUP, exp),
    ("prefix-ascii-control", "item_prefix=AB\n", "AB-046", exp),
    ("prefix-latin1-upper", "item_prefix=ÀB\n", "ÀB-046", exp),
    ("days-ascii-control", "max_waiver_days=30\n", "CON-046", exp),
    ("days-superscript", "max_waiver_days=¹30\n", "CON-046", exp),
    ("expiry-superscript-year", "", "CON-046", "²" + exp[1:]),
]
for k, (name, conf, item, ex) in enumerate(CASES):
    sp = os.path.join(w, "sp%d" % k); os.makedirs(sp); g("init", "-q", "-b", "main", cwd=sp)
    g("submodule", "add", "-q", up, "sub", cwd=sp)
    if conf:
        open(os.path.join(sp, ".submodule_pin_gate.conf"), "w", encoding="utf-8").write(conf)
        g("add", ".submodule_pin_gate.conf", cwd=sp)
    g("commit", "-q", "-m", "add", cwd=sp)
    base = g("rev-parse", "HEAD", cwd=sp)
    g("checkout", "-q", shas[0], cwd=os.path.join(sp, "sub")); g("add", "sub", cwd=sp)
    row = "\t".join(["sub", shas[2], shas[0], "ops", ex, item, base]) + "\n"
    open(os.path.join(sp, ".submodule_pin_waivers"), "w", encoding="utf-8").write(row)
    g("add", ".submodule_pin_waivers", cwd=sp)
    rcs = []
    for loc in LOCS:
        env = dict(base_env, LC_ALL=loc)
        r = subprocess.run(["bash", gate, "--root", sp], env=env, capture_output=True, text=True)
        rcs.append(r.returncode)
    print("%s C.UTF-8=%d en_US.UTF-8=%d%s" % (name, rcs[0], rcs[1], "  differs" if rcs[0] != rcs[1] else ""))
