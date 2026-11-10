#!/bin/bash
# test_review_record_resolution_ground_truth.sh
#
# CON-033 round 4, STRUCTURAL round for the path-resolution class (review
# R2-F2, R3-F1, R3-F2; constitution 11.4.276(B)/(C)/(E), 11.4.245): the
# capability tier of review/review_record.py stands on _resolution_chain, a
# component-by-component walk that must see EXACTLY the inodes the kernel
# uses when it opens the path. Round 3 proved that walk only against cases a
# fixer wrote; one listed "equivalent" mutant (G-T-DOT#1) and one reviewer
# mutant (RVR3b) gave an unsound "capability". This suite takes the ground
# truth from the kernel itself, not from a reading of the code:
#
#   K0  an empty path raises (the kernel: ENOENT), never names the cwd.
#   T0  _path_tier names an empty or absent path "missing" (before any walk).
#   K1  LEAF ORACLE. For every path of a generated grid (components ".",
#       "..", plain names, relative / absolute / dot-laden / chained
#       symlinks, links to files with a trailing "/", a trailing "/" on the
#       path itself; up to three components) the leaf _resolution_chain
#       returns must be the inode os.stat() (the kernel's own resolution, as
#       open() does it) returns, and _resolution_chain must raise exactly
#       when os.stat() raises.
#   K2  CHAIN ORACLE. On the same grid, the directories and the looked-up
#       entries (`dirs`, `edges`) must equal those of an independent walk in
#       which the KERNEL performs every lookup and every "..":
#       openat(dirfd, name, O_PATH|O_NOFOLLOW) / fstatat / readlinkat
#       (os.open / os.stat / os.readlink with dir_fd). Only the splicing of
#       a link's target into the remaining components is shared knowledge;
#       which directory ".." names, and which inode each name is, come from
#       the kernel. Compared by (st_dev, st_ino), as multisets.
#   K3  PATH STRINGS. Every directory path in `dirs` and the leaf path are
#       real names of the inodes recorded for them (os.lstat of the string
#       gives the same inode): _owner_only_error reads ACLs through them.
#   N   NEEDLES (section 11.4.273): the grid contains paths on which a
#       LEXICAL resolver (os.path.abspath, the round-3 code) lands on another
#       inode than the kernel, paths through "X/./.." and paths with a
#       trailing slash on a file -- otherwise K1/K2 would prove nothing.
#   T1  TIER, ".": a link "X/./../tgt" whose real target tgt is
#       group-writable, next to an owner-only X/tgt, is instance (round-3
#       G-T-DOT#1 mutant: capability); T1r the false-refusal direction: the
#       same link with no X/tgt and an owner-only tgt is capability.
#   T2  TIER, a symlink in the MIDDLE of the path followed by "..": the path
#       ".../safe/link/../f" with link -> a directory inside ./evil opens
#       evil/f; a group-writable evil/f is instance even when safe/f is
#       owner-only (round-3 code: capability); T2r the reverse: the kernel
#       path exists only through the link, and is capability.
#   T3  TIER, trailing slash: "f/" for a regular file does not resolve
#       (instance); "d/" for an owner-only directory is capability.
#   T4  TIER, relative paths: a relative path gives the same tier and reason
#       as its absolute spelling (unsafe and safe variants).
#   T5  TIER, sub/../f: the directory holding f is group-writable: instance
#       (control T5c: owner-only, capability).
#   T7  TIER, an access ACL on a directory in the MIDDLE of the chain (not
#       the deepest one) is instance (control T7c: the ACL removed is
#       capability). The ACL is written with setxattr (a named-user entry
#       plus a mask, so the kernel stores it); a filesystem without ACLs
#       makes T7 a SKIP: the suite then exits 77, never 0.
#
# Every case calls the REAL module in-process with an injected runner uid
# (the evidence owner is the uid that created the files; no chown needed).
# Exit 0 all passed; 1 a check failed; 2 setup error (no non-root uid, no
# owner-only temp base); 77 every check that ran passed but T7 could not run
# (no ACL support on the temp filesystem): SKIP, never PASS.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../review/review_record.py"
[ -f "$TOOL" ] || { echo "setup: missing $TOOL" >&2; exit 2; }
if [ "$(id -u)" -eq 0 ]; then echo "setup: running as root; this suite needs a non-root uid" >&2; exit 2; fi
umask 022
S=""
for base in "${TMPDIR:-}" /tmp; do
  [ -n "$base" ] && [ -d "$base" ] && [ -w "$base" ] || continue
  S=$(mktemp -d "$base/rr_resolution_gt.XXXXXX") && break
done
[ -n "$S" ] || { echo "setup: no writable temp base" >&2; exit 2; }
trap 'chmod -R u+rwx "${S:?}" 2>/dev/null; rm -rf -- "${S:?}"' EXIT
chmod 0755 "$S"

timeout 240 python3 - "$TOOL" "$S" <<'PY'
import importlib.util, itertools, os, stat, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
B = os.path.realpath(sys.argv[2])
PASS = FAIL = 0
def ok(m):
    global PASS; PASS += 1; print("PASS: " + m)
def bad(m):
    global FAIL; FAIL += 1; print("FAIL: " + m)
ino = lambda st: (st.st_dev, st.st_ino)

# ---------------------------------------------------------------- the grid
G = os.path.join(B, "grid")
for d in ["", "a", "a/sub", "a/sub/deep", "b", "evil", "evil/sub"]:
    os.makedirs(os.path.join(G, d), exist_ok=True)
for f in ["x", "a/x", "a/sub/x", "b/x", "evil/x", "evil/sub/x"]:
    with open(os.path.join(G, f), "w") as fh:
        fh.write(f)
LINKS = {"a/Lrel": "sub", "a/Labs": G + "/evil/sub", "a/Lup": "../b", "a/Ldot": "./sub/./deep/..",
         "a/Lfile": "x", "a/Lfileslash": "x/", "a/Ldirslash": "sub/", "a/Lchain": "Lrel",
         "a/sub/Lparent": "..", "evil/Lback": "../a", "a/Ldotup": "./sub/../../evil", "a/Lloop": "Lloop"}
for l, t in LINKS.items():
    os.symlink(t, os.path.join(G, l))
COMPS = ["a", "b", "sub", "x", ".", "..", "Lrel", "Labs", "Lup", "Ldot", "Lfile", "Lfileslash",
         "Ldirslash", "Lchain", "Lparent", "Lback", "Ldotup", "Lloop"]

def kernel_leaf(p):
    try:
        return ino(os.stat(p))
    except OSError:
        return None

def kernel_chain(p):
    """The traversal, with the kernel doing every lookup and every '..'."""
    if kernel_leaf(p) is None:
        return None
    flags = os.O_PATH | os.O_NOFOLLOW
    root = os.open("/", os.O_PATH | os.O_DIRECTORY)
    fds = [root]
    cur = root
    dirs, edges = [ino(os.fstat(root))], []
    pending = [c for c in (p if p.startswith("/") else os.getcwd() + "/" + p).split("/") if c]
    leaf = ino(os.fstat(root))
    try:
        while pending:
            c = pending.pop(0)
            if c == ".":
                continue
            if c == "..":
                cur = os.open("..", os.O_PATH | os.O_DIRECTORY, dir_fd=cur); fds.append(cur)
                st = os.fstat(cur); dirs.append(ino(st)); leaf = ino(st)
                continue
            st = os.stat(c, dir_fd=cur, follow_symlinks=False)
            edges.append((ino(os.fstat(cur)), ino(st)))
            if stat.S_ISLNK(st.st_mode):
                t = os.readlink(c, dir_fd=cur)
                if t.startswith("/"):
                    cur = root
                pending = [x for x in t.split("/") if x] + pending
                continue
            if stat.S_ISDIR(st.st_mode):
                cur = os.open(c, flags | os.O_DIRECTORY, dir_fd=cur); fds.append(cur)
                dirs.append(ino(st))
            leaf = ino(st)
        return leaf, sorted(set(dirs)), sorted(edges)
    finally:
        for fd in fds:
            os.close(fd)

def mine(p):
    try:
        leaf, st, dirs, edges = rr._resolution_chain(p)
    except OSError:
        return None
    return leaf, st, dirs, edges

n = k1 = k2 = k3 = 0
lexical = dotdot_x = trail_file = 0
samples = {"K1": [], "K2": [], "K3": []}
for k in (1, 2, 3):
    for combo in itertools.product(COMPS, repeat=k):
        for trail in ("", "/"):
            p = G + "/" + "/".join(combo) + trail
            n += 1
            kl = kernel_leaf(p)
            # needles: the grid must hold the paths that break a lexical resolver
            try:
                lx = ino(os.stat(os.path.abspath(p)))
            except OSError:
                lx = None
            if kl is not None and lx is not None and lx != kl:
                lexical += 1
            if "." in combo and ".." in combo:
                dotdot_x += 1
            if trail and kl is None and combo[-1] in ("x", "Lfile"):
                trail_file += 1
            m = mine(p)
            ml = None if m is None else ino(m[1])
            if ml != kl:
                k1 += 1; samples["K1"].append((p[len(G):], kl is not None, ml is not None))
                continue
            if m is None:
                continue
            kc = kernel_chain(p)
            got = (ino(m[1]), sorted(set(ino(v) for v in m[2].values())),
                   sorted((ino(m[2][d]), ino(c)) for d, c in m[3]))
            if kc is None or got != kc:
                k2 += 1; samples["K2"].append(p[len(G):])
            names = [(d, v) for d, v in m[2].items()] + [(m[0], m[1])]
            if any(ino(os.lstat(s)) != ino(v) for s, v in names):
                k3 += 1; samples["K3"].append(p[len(G):])
print("grid: %d paths; needles: lexical-differs %d, '.'+'..' %d, trailing-slash-on-file %d" % (n, lexical, dotdot_x, trail_file))
if lexical > 0 and dotdot_x > 0 and trail_file > 0:
    ok("N: the grid holds paths a lexical resolver gets wrong (%d), '.'+'..' paths (%d) and trailing slashes on files (%d)" % (lexical, dotdot_x, trail_file))
else:
    bad("N: the grid lacks a needle class (lexical %d, dot-dotdot %d, trailing %d): K1/K2 would prove nothing" % (lexical, dotdot_x, trail_file))
try:
    rr._resolution_chain("")
    bad("K0: an empty path resolved (the kernel gives ENOENT for '')")
except OSError:
    try:
        os.stat("")
        bad("K0: os.stat('') did not fail on this host (needle)")
    except OSError:
        ok("K0: an empty path raises, as the kernel's os.stat('') does (never the current directory)")
(ok if k1 == 0 else bad)("K1: the leaf equals the kernel's (os.stat) on all %d paths, and raises exactly where the kernel fails (%d differ: %s)" % (n, k1, samples["K1"][:5]))
(ok if k2 == 0 else bad)("K2: dirs and looked-up entries equal the openat walk's on every resolving path (%d differ: %s)" % (k2, samples["K2"][:5]))
(ok if k3 == 0 else bad)("K3: every recorded directory path and leaf path names its recorded inode (%d differ: %s)" % (k3, samples["K3"][:5]))

# ---------------------------------------------------------------- tier cases
me = os.geteuid()
runner = me + 100000 if me + 100000 != 65534 else me + 100001
def tier(paths):
    t, why = rr._path_tier(paths, 65534, me, runner_uid=runner, ranges=[], getpw=lambda u: object())
    return t, (why or "")
def mk(path, mode, data="x"):
    with open(path, "w") as fh:
        fh.write(data)
    os.chmod(path, mode)
def expect(label, got, want, desc):
    (ok if got[0] == want[0] and want[1] in got[1] else bad)("%s: %s (got %s, want %s containing %r)" % (label, desc, got, want[0], want[1]))

# T0: an empty or absent evidence path is named as missing, before any walk
# (G-T-PATH-PRESENT: without it '' reaches the walk and is named "does not
# resolve", which tells the operator a different thing).
for p_ in ("", None):
    expect("T0", tier([p_]), ("instance", "an evidence path is missing"),
           "an evidence path %r is instance, named missing" % (p_,))

# T1 / T1r: "X/./../tgt" -- "." must not change what the following ".." names
T = os.path.join(B, "t1"); os.mkdir(T)
os.mkdir(os.path.join(T, "X")); mk(os.path.join(T, "X", "tgt"), 0o644); mk(os.path.join(T, "tgt"), 0o666)
os.symlink("X/./../tgt", os.path.join(T, "link"))
expect("T1", tier([os.path.join(T, "link")]), ("instance", os.path.join(T, "tgt") + " is group- or other-writable"),
       "a link X/./../tgt whose real target tgt is group-writable is instance, even with an owner-only X/tgt")
T = os.path.join(B, "t1r"); os.mkdir(T)
os.mkdir(os.path.join(T, "X")); mk(os.path.join(T, "tgt"), 0o644)
os.symlink("X/./../tgt", os.path.join(T, "link"))
expect("T1r", tier([os.path.join(T, "link")]), ("capability", ""),
       "the same link with no X/tgt and an owner-only tgt is capability (false-refusal direction)")
os.symlink("X/./././../tgt", os.path.join(T, "link3"))
expect("T1r3", tier([os.path.join(T, "link3")]), ("capability", ""), "repeated '.' before '..' is capability as well")

# T2 / T2r: a symlink in the middle of the path, then ".."
T = os.path.join(B, "t2"); os.mkdir(T)
for d in ("safe", "evil", "evil/in"):
    os.mkdir(os.path.join(T, d))
mk(os.path.join(T, "safe", "f"), 0o644); mk(os.path.join(T, "evil", "f"), 0o664)
os.symlink(os.path.join(T, "evil", "in"), os.path.join(T, "safe", "link"))
p = os.path.join(T, "safe", "link", "..", "f")
assert ino(os.stat(p)) == ino(os.stat(os.path.join(T, "evil", "f")))
expect("T2", tier([p]), ("instance", os.path.join(T, "evil", "f") + " is group- or other-writable"),
       "safe/link/../f opens evil/f (link -> evil/in); a group-writable evil/f is instance although safe/f is owner-only")
os.chmod(os.path.join(T, "evil", "f"), 0o644); os.unlink(os.path.join(T, "safe", "f"))
expect("T2r", tier([p]), ("capability", ""),
       "the reverse: safe/f does not exist, the kernel path through the link does, and it is owner-only: capability")
os.chmod(os.path.join(T, "safe"), 0o775)
expect("T2s", tier([p]), ("instance", "directory %s is writable by others" % os.path.join(T, "safe")),
       "the directory holding the link (safe) is group-writable: instance, although the walk leaves it by the link")
os.chmod(os.path.join(T, "safe"), 0o755)

# T3: trailing slash
T = os.path.join(B, "t3"); os.mkdir(T)
mk(os.path.join(T, "f"), 0o644); os.mkdir(os.path.join(T, "d"))
expect("T3", tier([os.path.join(T, "f") + "/"]), ("instance", "does not resolve"),
       "f/ for a regular file does not resolve (the kernel says ENOTDIR): instance")
os.symlink("f/", os.path.join(T, "lslash"))
expect("T3l", tier([os.path.join(T, "lslash")]), ("instance", "does not resolve"),
       "a link whose target 'f/' names a regular file does not resolve: instance")
expect("T3d", tier([os.path.join(T, "d") + "/"]), ("capability", ""), "d/ for an owner-only directory is capability")
expect("T3c", tier([os.path.join(T, "f")]), ("capability", ""), "control: f without the slash is capability")

# T4: relative paths give the absolute spelling's verdict
T = os.path.join(B, "t4"); os.mkdir(T)
mk(os.path.join(T, "good"), 0o644); mk(os.path.join(T, "bad"), 0o664)
old = os.getcwd(); os.chdir(T)
try:
    for name in ("good", "bad"):
        rel, ab = tier([name]), tier([os.path.join(T, name)])
        (ok if rel[0] == ab[0] and rel[0] == ("capability" if name == "good" else "instance") else bad)(
            "T4-%s: the relative path gives the absolute path's tier (%s vs %s)" % (name, rel, ab))
finally:
    os.chdir(old)

# T5: a directory reached by ".." is still owner-checked
T = os.path.join(B, "t5"); os.mkdir(T)
os.mkdir(os.path.join(T, "sub")); mk(os.path.join(T, "f"), 0o644)
os.chmod(T, 0o775)
expect("T5", tier([os.path.join(T, "sub", "..", "f")]), ("instance", "directory %s is writable by others" % T),
       "sub/../f: the directory holding f is group-writable: instance")
os.chmod(T, 0o755)
expect("T5c", tier([os.path.join(T, "sub", "..", "f")]), ("capability", ""), "control: the same path with that directory owner-only is capability")

# T7: an ACL on a middle directory of the chain
import errno, struct
T = os.path.join(B, "t7"); os.mkdir(T); os.mkdir(os.path.join(T, "mid")); mk(os.path.join(T, "mid", "f"), 0o644)
acl = struct.pack("<I", 2) + b"".join(struct.pack("<HHI", tag, perm, uid) for tag, perm, uid in
      ((0x01, 7, 0xFFFFFFFF), (0x02, 4, 65534), (0x04, 5, 0xFFFFFFFF), (0x10, 5, 0xFFFFFFFF), (0x20, 5, 0xFFFFFFFF)))
SKIPPED = 0
try:
    os.setxattr(T, "system.posix_acl_access", acl)
except OSError as exc:
    if exc.errno in (errno.ENOTSUP, errno.EOPNOTSUPP):
        SKIPPED += 1; print("SKIP: T7 -- the temp filesystem stores no POSIX ACLs (%s)" % exc)
    else:
        bad("T7: setxattr failed: %s" % exc)
else:
    expect("T7", tier([os.path.join(T, "mid", "f")]), ("instance", "directory %s carries a POSIX ACL" % T),
           "an access ACL on a middle directory of the chain (not the deepest) is instance")
    os.removexattr(T, "system.posix_acl_access")
    expect("T7c", tier([os.path.join(T, "mid", "f")]), ("capability", ""), "control: the same chain with the ACL removed is capability")

print("== Summary: ok %d / NOT ok %d ==" % (PASS, FAIL))
if FAIL:
    sys.exit(1)
if SKIPPED:
    print("SKIP reason=proof_legs_skipped"); sys.exit(77)
sys.exit(0)
PY
rc=$?
case "$rc" in
  0|77) exit "$rc" ;;
  1) exit 1 ;;
  *) echo "FAIL: the ground-truth harness ended with rc $rc (timeout or crash)"; exit 1 ;;
esac
