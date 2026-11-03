#!/usr/bin/env python3
"""credscan.py - COUNTS-ONLY credential-shape scanner with baseline ratchet.

Purpose : find credential-shaped values persisted in local transcripts/history/
          scratch/repo trees WITHOUT ever printing, logging or storing a value.
Usage   : credscan.py scan     [--root P ...] [--json] [--default-roots]
          credscan.py baseline [--root P ...] --baseline F   (counts only)
          credscan.py check    [--root P ...] --baseline F   (ratchet)
          credscan.py selftest
Exit    : 0 ok | 1 ratchet violated | 2 usage/config error | 3 BLIND (control needle
          not seen: a zero is not evidence, section 11.4.273) | 4 internal error
          | 5 PARTIAL (unreadable/oversize entries: the zero is not evidence) | 124/137 wrapper
          Cache: --cache F keeps a counts-only per-file cache keyed on mtime/size/ino/dev/ctime
          and a hash of this source; checkpointed every 60 s and on SIGTERM.
Output  : per-file {path, counts-per-class}; classes: github gitlab sk jev_gateway
          bearer aws pem.  Never a value, prefix or hash of a value.
Design  : spans are consumed in class priority order so one token counts once;
          placeholder/low-entropy shapes are rejected (golden-bad). Symlinked
          directories ARE followed (~/.claude-*/projects are symlinks).
"""
import argparse, json, math, os, re, stat, sys, tempfile, random, string

CLASSES = ["github", "gitlab", "sk", "aws", "pem", "jev_gateway", "bearer"]  # priority order
HIGH_CONF = {"github", "gitlab", "sk", "aws", "pem"}
RX = {
    "github": re.compile(r"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{50,255})(?![A-Za-z0-9_])"),
    "gitlab": re.compile(r"(?<![A-Za-z0-9_-])glpat-[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])"),
    "sk": re.compile(r"(?<![A-Za-z0-9_-])sk-(?:ant-|proj-)?[A-Za-z0-9_-]{32,}(?![A-Za-z0-9_-])"),
    "aws": re.compile(r"(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])"),
    "pem": re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    # shape of the Jev/llmctl gateway key: short alpha prefix + separator + >=96 b64url chars
    "jev_gateway": re.compile(r"[A-Za-z0-9_-]{99,}"),  # run finder; JEV_SHAPE decides
    "bearer": re.compile(r"(?i)\bbearer[ \t]+([A-Za-z0-9._~+/=-]{24,})"),
}
JEV_SHAPE = re.compile(r"[A-Za-z]{2,8}[-_][A-Za-z0-9_-]{96,}")
PLACEHOLDER = re.compile(r"(?i)(x{6,}|\*{4,}|your[-_]|example|dummy|fake|placeholder|changeme|change_me|redacted|<[^>]*>|\$\{?[A-Za-z_]|\.{3}|test|sample)")

def entropy_ok(s):
    body = re.sub(r"^[A-Za-z]{2,8}[-_]", "", s)
    if len(set(body)) < 10:
        return False
    c = {}
    for ch in body: c[ch] = c.get(ch, 0) + 1
    h = -sum(v / len(body) * math.log2(v / len(body)) for v in c.values())
    return h >= 3.0

PREFILTER = re.compile(r"gh[pousr]_|github_pat_|glpat-|sk-|AKIA|ASIA|-----BEGIN|(?i:bearer)|[A-Za-z0-9_-]{99}")

def count_line(line, counts):
    """Counts credential-shaped tokens in a line into counts. Returns nothing sensitive."""
    if not PREFILTER.search(line):
        return
    consumed = []
    for cls in CLASSES:
        for m in RX[cls].finditer(line):
            a, b = m.span()
            if any(a < e and b > s for s, e in consumed):
                continue
            tok = m.group(1) if cls == "bearer" else m.group(0)
            if cls == "jev_gateway" and not JEV_SHAPE.fullmatch(tok):
                continue
            if cls != "pem" and (PLACEHOLDER.search(tok) or not entropy_ok(tok)):
                continue
            consumed.append((a, b))
            counts[cls] = counts.get(cls, 0) + 1

def scan_text(text):
    counts = {}
    for ln in text.splitlines():
        count_line(ln, counts)
    return counts

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "vendor"}
MAX_BYTES = int(os.environ.get("CREDSCAN_MAX_BYTES", 4 * 1024 * 1024 * 1024))   # hard ceiling; big files are streamed, not skipped
CHUNK = 8 * 1024 * 1024        # streaming read size
MAX_UNBROKEN = 32 * 1024 * 1024   # a run with no newline longer than this is cut (a token spanning the cut is missed)

def iter_files(root, errs=None):
    """Yield file paths under root. errs (a list) receives one entry per directory that could not be listed."""
    if os.path.isfile(root):
        yield root; return
    seen = set()
    def onerror(e):
        if errs is not None: errs.append(getattr(e, "filename", None))
    for dp, dns, fns in os.walk(root, followlinks=True, onerror=onerror):
        try: rp = os.path.realpath(dp)
        except OSError: continue
        if rp in seen: dns[:] = []; continue
        seen.add(rp)
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            yield os.path.join(dp, fn)

def scan_file(path):
    """Return (counts, skip_reason). skip_reason is None, "oversize", "binary", "special" or "unreadable".
    A skipped file is reported, never silently dropped: a zero must mean "looked", not "could not look"."""
    counts = {}
    try:
        st = os.stat(path)
        if not stat.S_ISREG(st.st_mode): return None, "special"
        if st.st_size > MAX_BYTES: return None, "oversize"
        with open(path, "rb") as f:
            if b"\0" in f.read(4096): return None, "binary"
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            carry = ""
            while True:
                buf = f.read(CHUNK)
                if not buf:
                    break
                buf = carry + buf
                cut = buf.rfind("\n")
                if cut < 0:
                    if len(buf) < MAX_UNBROKEN: carry = buf; continue
                    cut = len(buf) - 1
                part, carry = buf[:cut + 1], buf[cut + 1:]
                if PREFILTER.search(part):      # C-speed skip of chunks that cannot hold a token
                    for ln in part.splitlines():
                        count_line(ln, counts)
            if carry and PREFILTER.search(carry):
                for ln in carry.splitlines():
                    count_line(ln, counts)
    except (OSError, ValueError):
        try:
            if os.path.islink(path) and not os.path.exists(path): return None, "dangling"
        except OSError: pass
        return None, "unreadable"
    return counts, None

def synth(kind):
    """Runtime-assembled synthetic token of the given class (the source never holds a scannable literal)."""
    R = random.Random(11)
    al = string.ascii_letters + string.digits
    r = lambda n, a=al: "".join(R.choice(a) for _ in range(n))
    if kind in ("pos", "github"): return "gh" + "p_" + r(36)
    if kind == "neg": return "s" + "k-" + r(48)
    if kind == "sk": return "s" + "k-" + r(48)
    if kind == "gitlab": return "gl" + "pat-" + r(24, al + "_-")
    if kind == "aws": return "AK" + "IA" + r(16, string.ascii_uppercase + string.digits)
    if kind == "pem": return "-----BEGIN " + "RSA PRIVATE KEY-----"
    if kind == "jev_gateway": return "ab" + "c_" + r(100, al + "_-")
    if kind == "bearer": return "Bear" + "er " + r(40)
    raise KeyError(kind)

def control():
    """Same-path needles. Every class must be counted exactly once in text AND through the real
    file-reading path; a clean string must count nothing. Section 11.4.273(f): a set criterion
    is needled for every member. CREDSCAN_FAULT_BLIND_CLASS=<class|file_path> injects blindness (tests)."""
    fault = os.environ.get("CREDSCAN_FAULT_BLIND_CLASS") or ("github" if os.environ.get("CREDSCAN_FAULT_BLIND") == "1" else "")
    classes = {}
    for cls in CLASSES:
        classes[cls] = scan_text("x " + synth(cls) + " y").get(cls, 0) == 1 and fault != cls
    fd, tmp = tempfile.mkstemp(prefix="credscan_ctl.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("clean line\n" + "x " + synth("github") + " y\n")
        c, why = scan_file(tmp)
        file_ok = why is None and c == {"github": 1} and fault != "file_path"
    finally:
        os.unlink(tmp)
    neg = scan_text("x " + "q" * 40 + " y") == {}
    return {"positive_seen": all(classes.values()) and file_ok, "negative_clean": neg,
            "classes_missing": sorted(k for k, v in classes.items() if not v), "file_path_seen": file_ok}

def default_roots():
    h = os.path.expanduser("~")
    rs = [h + "/.claude-shared/projects", h + "/.claude-shared/history.jsonl", h + "/.cache/claude-tmp/secrets"]
    return [r for r in rs if os.path.exists(r)]

def _version():
    import hashlib
    try: src = open(os.path.abspath(__file__), "rb").read()      # the whole counting logic, not only the regexes
    except OSError: src = b""
    return hashlib.sha256(src + repr(MAX_BYTES).encode()).hexdigest()[:16]

def load_cache(path):
    """Counts-only incremental cache {path: [mtime_ns, size, ino, dev, ctime_ns, counts|null, skip|null]}; any doubt -> empty."""
    try:
        d = json.load(open(path))
        if d.get("schema") == 1 and d.get("version") == _version() and isinstance(d.get("files"), dict):
            ok = {}
            for k, e in d["files"].items():       # a malformed entry is a miss, never an error
                if (isinstance(e, list) and len(e) == 7 and all(isinstance(x, int) for x in e[:5])
                        and (e[5] is None or (isinstance(e[5], dict) and all(isinstance(v, int) for v in e[5].values())))
                        and e[6] in (None, "oversize", "binary", "special")):
                    ok[k] = e
            return ok
    except (OSError, ValueError, AttributeError): pass
    return {}

def save_cache(path, files):
    tmp = "%s.%d.tmp" % (path, os.getpid())
    try: os.unlink(tmp)
    except FileNotFoundError: pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as f: json.dump({"schema": 1, "version": _version(), "counts_only": True, "files": files}, f)
    os.replace(tmp, path)

def scan_cached(p, cache, newcache):
    try: st = os.stat(p); key = [st.st_mtime_ns, st.st_size, st.st_ino, st.st_dev, st.st_ctime_ns]   # ctime cannot be set from user space
    except OSError: return scan_file(p)
    e = cache.get(p)
    if e and e[:5] == key:
        newcache[p] = e; return e[5] or {}, e[6]
    c, why = scan_file(p)
    if why not in ("unreadable", "dangling"): newcache[p] = key + [c if c else None, why]; scan_cached.fresh += 1
    return c, why

scan_cached.fresh = 0

def run_scan(roots, cache_path=None):
    cache = load_cache(cache_path) if cache_path else {}
    newcache = {}
    files, total = [], 0
    skipped = {"binary": 0, "oversize": 0, "special": 0, "unreadable": 0, "dangling": 0}
    roots_unreadable = 0
    import signal, time
    last = [time.monotonic()]
    def checkpoint(final=False):
        if cache_path and scan_cached.fresh:
            data = newcache if final else {**cache, **newcache}    # interim: keep not-yet-visited valid entries
            try: save_cache(cache_path, data)
            except OSError: pass
            scan_cached.fresh = 0
        last[0] = time.monotonic()
    old = None
    if cache_path:       # a killed first run must keep its progress: SIGTERM -> checkpoint -> exit 143
        def _term(sig, frm): checkpoint(); os._exit(143)
        try: old = signal.signal(signal.SIGTERM, _term)
        except ValueError: old = None
    try:
        for root in roots:
            errs = []
            for p in iter_files(root, errs):
                c, why = scan_cached(p, cache, newcache) if cache_path else scan_file(p)
                if cache_path and time.monotonic() - last[0] > 60: checkpoint()
                if why: skipped[why] += 1
                elif c:
                    files.append({"path": p, "counts": c}); total += sum(c.values())
            skipped["unreadable"] += len(errs)
            roots_unreadable += sum(1 for e in errs if e == root)
        scan_cached.fresh = max(scan_cached.fresh, 1) if cache_path else 0
        checkpoint(True)
    finally:
        if old is not None: signal.signal(signal.SIGTERM, old)
    return {"control": control(), "total": total, "skipped": skipped, "roots_unreadable": roots_unreadable, "files": sorted(files, key=lambda f: f["path"])}

def write_status(path, state, code, res=None, violations=0):
    """Counts-only status record for unattended runs (never a value, never a path list)."""
    if not path: return
    import time
    d = {"state": state, "exit": code, "violations": violations, "time": int(time.time())}
    if res is not None:
        d["total"] = res["total"]; d["files_with_findings"] = len(res["files"]); d["skipped"] = res["skipped"]
    tmp = path + ".tmp"
    try: os.unlink(tmp)
    except FileNotFoundError: pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as f: json.dump(d, f, sort_keys=True)
    os.chmod(tmp, 0o600); os.replace(tmp, path)

def agg(res):
    d = {}
    for f in res["files"]:
        for k, v in f["counts"].items():
            d.setdefault(f["path"], {})[k] = v
    return d

def main(argv):
    ap = argparse.ArgumentParser(prog="credscan")
    ap.add_argument("cmd", choices=["scan", "baseline", "check", "selftest"])
    ap.add_argument("--root", action="append", default=[])
    ap.add_argument("--default-roots", action="store_true")
    ap.add_argument("--baseline")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--status-file")
    ap.add_argument("--cache", help="counts-only incremental cache file (unchanged files are not re-read)")
    a = ap.parse_args(argv)
    if a.cmd == "selftest":
        return selftest()
    roots = list(a.root) + (default_roots() if a.default_roots or not a.root else [])
    if a.cmd in ("baseline", "check") and not a.baseline:
        print("--baseline required", file=sys.stderr); return 2
    missing = [r for r in roots if not os.path.exists(r)]
    if not roots or missing:
        for r in missing: print("root does not exist: %s (a zero over a missing root is not evidence)" % r, file=sys.stderr)
        if not roots: print("no roots to scan (none given and no default root exists)", file=sys.stderr)
        write_status(a.status_file, "roots_missing", 2); return 2
    if a.cmd == "check" and not os.path.exists(a.baseline):
        print("baseline missing: %s (refusing to create one unattended)" % a.baseline, file=sys.stderr)
        write_status(a.status_file, "baseline_missing", 2); return 2
    res = run_scan(roots, a.cache)
    c = res["control"]
    if not (c["positive_seen"] and c["negative_clean"]):
        print("BLIND: control needle failed (%s); result is not evidence" % json.dumps(c), file=sys.stderr)
        write_status(a.status_file, "blind", 3, res); return 3
    if a.cmd == "scan":
        if a.json: print(json.dumps(res, indent=1))
        else:
            for f in res["files"]:
                print("%s\t%s" % (f["path"], ",".join("%s=%d" % kv for kv in sorted(f["counts"].items()))))
            sk = res["skipped"]
            if sum(sk.values()): print("SKIPPED\tbinary=%d\toversize=%d\tspecial=%d\tunreadable=%d\tdangling=%d" % (sk["binary"], sk["oversize"], sk["special"], sk["unreadable"], sk["dangling"]))
            print("TOTAL\t%d" % res["total"])
        return 0
    if a.cmd == "baseline":
        d = os.path.dirname(os.path.abspath(a.baseline))
        os.makedirs(d, mode=0o700, exist_ok=True)
        with open(a.baseline, "w") as f:
            json.dump({"schema": 1, "counts_only": True, "files": agg(res)}, f, indent=1, sort_keys=True)
        os.chmod(a.baseline, 0o600)
        if res["skipped"]["unreadable"] or res["skipped"]["oversize"] or res.get("roots_unreadable"):
            print("WARNING: baseline taken from a partial scan (unreadable=%d oversize=%d); it is under-counted" % (res["skipped"]["unreadable"], res["skipped"]["oversize"]), file=sys.stderr)
        print("baseline written: %d files, total %d" % (len(res["files"]), res["total"])); return 0
    # check
    try:
        base = json.load(open(a.baseline))["files"]
        if not isinstance(base, dict) or not all(isinstance(cl, dict) and all(isinstance(v, int) for v in cl.values()) for cl in base.values()):
            raise ValueError("bad baseline shape")
    except (OSError, ValueError, KeyError, TypeError):
        print("baseline missing/invalid", file=sys.stderr)
        write_status(a.status_file, "baseline_invalid", 2, res); return 2
    if os.environ.get("CREDSCAN_FAULT_CRASH") == "1": raise RuntimeError("injected crash")
    cur, bad = agg(res), []
    for p, cl in cur.items():
        for k, v in cl.items():
            b = base.get(p, {}).get(k, 0)
            if v > b: bad.append((p, k, b, v))
    for p, k, b, v in bad:
        print("RATCHET-VIOLATION\t%s\t%s\tbaseline=%d\tnow=%d" % (p, k, b, v))
    shrunk = sum(1 for p, cl in base.items() for k, v in cl.items() if cur.get(p, {}).get(k, 0) < v)
    sk = res["skipped"]
    print("check: %d violations, %d entries below baseline (re-baseline to lock in); skipped binary=%d oversize=%d special=%d unreadable=%d dangling=%d"
          % (len(bad), shrunk, sk["binary"], sk["oversize"], sk["special"], sk["unreadable"], sk["dangling"]))
    code = 1 if bad else 0
    state = "ratchet_violated" if bad else "ok"
    if not bad and (sk["unreadable"] or sk["oversize"] or res.get("roots_unreadable")):
        # a scan that could not look at part of its scope is not a clean result (11.4.273(c))
        print("PARTIAL: %d entries could not be read, %d oversize skipped (%d roots); the zero is not evidence" % (sk["unreadable"], sk["oversize"], res.get("roots_unreadable", 0)), file=sys.stderr)
        state, code = "partial", 5
    write_status(a.status_file, state, code, res, len(bad))
    return code

def selftest():
    ok = True
    def t(name, cond):
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name); ok = ok and cond
    t("golden-good github", scan_text(synth("pos")) == {"github": 1})
    t("golden-good sk", scan_text(synth("neg")) == {"sk": 1})
    t("golden-bad placeholder", scan_text("gh" + "p_" + "x" * 36) == {})
    t("negative-control clean", scan_text("nothing here " + "a" * 5) == {})
    t("control needle (all classes + file path)", control()["positive_seen"] and control()["negative_clean"])
    return 0 if ok else 1

def guarded(argv):
    """An internal error must never look like a ratchet violation (exit 1) nor leave a stale "ok"."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:   # noqa: BLE001 - last line of defence for unattended runs
        print("credscan: internal error (%s)" % type(e).__name__, file=sys.stderr)
        for i, v in enumerate(argv):
            tgt = argv[i + 1] if v == "--status-file" and i + 1 < len(argv) else (v.split("=", 1)[1] if v.startswith("--status-file=") else None)
            if tgt:
                try: write_status(tgt, "error", 4)
                except Exception: pass
        return 4

if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
