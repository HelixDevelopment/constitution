"""Equivalence evidence for a surviving lint mutant (round 9, F4; round 10 adds the members_r10() census members;
round 11: the shared module secret_canon.py is copied next to the mutant, and the round-10 reviewer rows of
tests/workable_items/secret_shape_fixtures_r11.py join the corpus). Applies one textual edit to a copy of
the lint and compares, on a corpus, (1) the secret views and (2) the secret rule names of the original
and the mutant. Prints counts and labels only, never a text.

usage: equiv_check.py LINT CENSUS FIXTURES OLD NEW [--fuzz N] [--codepoints]
  OLD and NEW are the edit, written as in the mutation harness (\\n is a newline, \\\\n a literal
  backslash-n). The corpus: every census member, every fixture
  row, N seeded random strings over an alphabet of quotes, backslashes, separators, key fragments,
  escapes and non-ASCII letters, and with --codepoints every code point of the BMP and the
  supplementary planes inserted inside a key ("pass<c>word=" + value) and before it.
A control needle runs first: the same harness with an edit that is known to change the answer
(SECRET_FOLD off) must report a difference; otherwise the harness is blind (exit 3).
Exit 0: no difference (the mutant is equivalent on this corpus); 1: a difference; 2: stale edit."""
import hashlib, importlib.util, os, random, shutil, sys, tempfile

args = sys.argv[1:]
fuzz = 0
cps = "--codepoints" in args
args = [a for a in args if a != "--codepoints"]
if "--fuzz" in args:
    k = args.index("--fuzz")
    fuzz = int(args[k + 1])
    del args[k:k + 2]
lint, census, fixtures, old, new = args


def unesc(t):  # the harness rule: "\\\\n" (two backslashes) is a literal backslash-n; "\\n" is a newline
    return t.replace("\\\\n", "\0").replace("\\n", "\n").replace("\0", "\\n")


old, new = unesc(old), unesc(new)


def load(p, name):
    spec = importlib.util.spec_from_file_location(name, p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def mutant(o, n):
    src = open(lint, encoding="utf-8").read()
    if src.count(o) != 1:
        return None
    d = tempfile.mkdtemp(dir=os.environ.get("TMPDIR"))
    p = os.path.join(d, "mut.py")
    open(p, "w", encoding="utf-8").write(src.replace(o, n))
    shutil.copy(os.path.join(os.path.dirname(os.path.abspath(lint)), "secret_canon.py"), d)
    m = load(p, "mut_%d" % abs(hash(n)))
    shutil.rmtree(d)
    return m


A = load(lint, "orig")
C = load(census, "census")
F = load(fixtures, "fixtures")
V8 = "Zq7" * 2 + "Zq"


def corpus():
    for gen in (C.members, C.members_r9, C.members_r10):
        for m in gen():
            yield m[2] if len(m) == 4 else m[1]
    r11 = load(os.path.join(os.path.dirname(os.path.abspath(fixtures)), "secret_shape_fixtures_r11.py"), "fixtures_r11")
    for _lb, t in r11.POS + r11.NEG + r11.EXTRA_POS:
        yield t
    for row in F.FIXTURES:
        yield row[1]
    rnd = random.Random(20261115)
    alpha = ['"', "'", "`", "\\", "\\\\", '\\"', "\\u00", "\\x7", "%2", "%25", "&#", "&quot;", "=", ":", " ",
             "\t", "pass", "word", "token", "key", "api_", "Zq7", "9", "{", "}", "[", "]", "ｐ", "а",
             "ο", "́", "͏", "​", "️", "ᴘ", "b", "f", "r", "+", "."]
    for _ in range(fuzz):
        yield "".join(rnd.choice(alpha) for _ in range(rnd.randint(4, 30)))
    if cps:
        for c in range(0x80, 0x110000):
            if 0xD800 <= c <= 0xDFFF:
                continue
            ch = chr(c)
            yield "pass" + ch + "word=" + V8
            yield ch + "password=" + V8


def compare(B, limit=None):
    n = dv = dh = 0
    for t in corpus():
        n += 1
        if A.secret_views(t) != B.secret_views(t):
            dv += 1
        if sorted(x for x, _ in A.secret_hits(t)) != sorted(x for x, _ in B.secret_hits(t)):
            dh += 1
            if limit is not None and dh >= limit:
                break
    return n, dv, dh


ctl = mutant("SECRET_FOLD = True", "SECRET_FOLD = False")
if ctl is None:
    print("BLIND: control edit is stale")
    sys.exit(3)
_, _, cdh = compare(ctl, limit=1)
print("EDIT edit_sha256=%s" % hashlib.sha256((old + "|||" + new).encode("utf-8")).hexdigest())
print("CONTROL needle (SECRET_FOLD off): hit_differences>=%d %s" % (cdh, "ok" if cdh else "BLIND"))
if not cdh:
    sys.exit(3)
B = mutant(old, new)
if B is None:
    print("STALE: the edit does not match exactly once")
    sys.exit(2)
n, dv, dh = compare(B)
print("RESULT corpus=%d view_differences=%d hit_differences=%d fuzz=%d codepoints=%s" % (n, dv, dh, fuzz, cps))
sys.exit(1 if dh else 0)
