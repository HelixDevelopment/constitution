#!/usr/bin/env bash
# Purpose : in-process unit cases for the tier decision legs of review_record.py that no other
#           suite pinned (CON-033 review R5-F4, R5-F5, R5-F6; reviewer mutants RV5-C, RV5-D,
#           RV5-A adopted verbatim in test_review_record_gate_authority_mutations.sh):
#           _has_acl on every listxattr failure errno, _subid_ranges on every nsswitch
#           `subid:` shape, _owner_only_error on the sticky-directory entry allowance.
#           Unit class (section 11.4.289(C)(1)): the functions are driven directly, with the
#           failing syscall injected -- there is no real-system equivalent for "listxattr
#           fails with EIO". Exit 0 pass, 1 fail, 2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="${RR_TOOL_UNDER_TEST:-$HERE/../review/review_record.py}"
[ -f "$TOOL" ] || { echo "setup: missing $TOOL" >&2; exit 2; }
PASS=0; FAIL=0
ok()  { echo "PASS: $*"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }
W=$(mktemp -d) || exit 2
trap 'rm -rf -- "${W:?}"' EXIT
OUT=$(python3 - "$TOOL" "$W" <<'PY'
import errno, importlib.util, os, stat, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
W = sys.argv[2]
res = []
def rec(name, got, want):
    res.append("%s\t%s\t%r\t%r" % ("PASS" if got == want else "FAIL", name, got, want))

# --- R5-F4 / RV5-C: _has_acl on every listxattr failure ---------------------------
real = os.listxattr
def inject(e):
    def f(path, follow_symlinks=True):
        raise OSError(e, os.strerror(e))
    return f
probe = os.path.join(W, "p"); open(probe, "w").write("x")
for name in ("EACCES", "EIO", "ENOENT", "EPERM", "ESTALE", "EINVAL", "ENOMEM", "ELOOP", "ENAMETOOLONG"):
    os.listxattr = inject(getattr(errno, name))
    rec("G-ACL-ERRNO %s counts as carrying an ACL" % name, rr._has_acl(probe), True)
for name in ("ENOTSUP", "EOPNOTSUPP"):
    os.listxattr = inject(getattr(errno, name))
    rec("G-ACL-ERRNO %s (no xattrs on this filesystem) is no ACL" % name, rr._has_acl(probe), False)
for names, want in (([], False), (["system.posix_acl_access"], True), (["user.x"], False),
                    (["user.x", "system.posix_acl_access"], True), (["system.posix_acl_default"], False)):
    os.listxattr = lambda p, follow_symlinks=True, n=names: n
    rec("G-ACL-NAME listing %r" % names, rr._has_acl(probe), want)
os.listxattr = real
saved = os.listxattr; del os.listxattr
rec("G-ACL-PLATFORM no listxattr counts as carrying an ACL", rr._has_acl(probe), True)
os.listxattr = saved

# --- R5-F5 / RV5-D: _subid_ranges on every nsswitch subid: shape ------------------
def nss(text):
    p = os.path.join(W, "nss_%d" % len(res)); open(p, "w").write(text); return p
sub = os.path.join(W, "subuid"); open(sub, "w").write("milos:100000:65536\n")
def r(text):
    got, why = rr._subid_ranges((sub,), nss(text))
    return "ranges" if got is not None else "unknown"
for text, want in (("subid: files\n", "ranges"), ("subid: files sss\n", "unknown"),
                   ("subid: sss files\n", "unknown"), ("subid: sss\n", "unknown"),
                   ("subid: files # sss\n", "ranges"), ("passwd: sss\nsubid: files\n", "ranges"),
                   ("subid: files files\n", "ranges"), ("subid:\n", "ranges"), ("", "ranges"),
                   ("  subid:   files   sss  \n", "unknown"), ("subid: files\nsubid: sss\n", "unknown"),
                   ("# subid: sss\nsubid: files\n", "ranges"), ("subid: compat\n", "unknown"),
                   ("passwd: files sss\n", "ranges")):
    rec("G-SUB-NSS-FILES-ONLY nsswitch %r" % text, r(text), want)
rec("G-SUB-NSS-FILES-ONLY a mixed 'files sss' line gives (None, reason)",
    rr._subid_ranges((sub,), nss("subid: files sss\n"))[0], None)
rec("G-SUB-NSS-ABSENT a missing nsswitch.conf grants no source restriction",
    rr._subid_ranges((sub,), os.path.join(W, "no_such_nss"))[0], [(100000, 65536)])
rec("G-SUB-NSS-READABLE an unreadable nsswitch.conf (a directory) is unknown",
    rr._subid_ranges((sub,), W)[0], None)

# --- R5-F6 / RV5-A: the sticky-directory entry allowance --------------------------
me = os.geteuid(); owner = me
leaf = os.path.join(W, "leaf"); open(leaf, "w").write("x")
def st(mode, uid):
    return os.stat_result((mode, 1, 1, 1, uid, 0, 0, 0, 0, 0))
leaf_st = st(stat.S_IFREG | 0o644, owner)
D = W   # a real directory: _has_acl(D) lists its xattrs; only the stat is synthetic
def err(dir_mode, child_uid, dir_uid=0):
    chain = (leaf, leaf_st, {D: st(stat.S_IFDIR | dir_mode, dir_uid)}, [(D, st(stat.S_IFDIR | 0o755, child_uid))])
    return rr._owner_only_error(chain, owner) is None
STICKY_WW = 0o1777
rec("G-T-DIR-FOREIGN-WRITE sticky world-writable dir, entry owned by root: ok", err(STICKY_WW, 0), True)
rec("G-T-DIR-FOREIGN-WRITE sticky world-writable dir, entry owned by the owner: ok", err(STICKY_WW, owner), True)
rec("G-T-DIR-FOREIGN-WRITE sticky world-writable dir, entry owned by another uid: refused", err(STICKY_WW, owner + 12345), False)
rec("G-T-DIR-FOREIGN-WRITE NON-sticky world-writable dir, entry owned by root: refused", err(0o777, 0), False)
rec("G-T-DIR-FOREIGN-WRITE NON-sticky world-writable dir, entry owned by the owner: refused", err(0o777, owner), False)
rec("G-T-DIR-FOREIGN-WRITE sticky group-writable dir, entry owned by root: ok", err(0o1775, 0), True)
rec("G-T-DIR-FOREIGN-WRITE owner-only dir, any entry owner: ok", err(0o755, owner + 12345), True)
rec("G-T-DIR-OWNED a directory owned by another uid is refused", err(0o755, 0, dir_uid=owner + 12345), False)

# --- R6 structural round: survivors of mutate_tier_legs.py (stage 2) --------------
# invalid UTF-8 in nsswitch.conf / a subuid file is unknown, never a crash or a grant
bn = os.path.join(W, "nss_bad"); open(bn, "wb").write(b"subid: files\n\xff\xfe\n")
rec("G-SUB-NSS-READABLE invalid UTF-8 nsswitch.conf is unknown", rr._subid_ranges((sub,), bn)[0], None)
bs = os.path.join(W, "subuid_bad"); open(bs, "wb").write(b"milos:100000:65536\n\xff\xfe\n")
rec("G-SUB-FILE-READABLE invalid UTF-8 subuid file is unknown", rr._subid_ranges((bs,), nss("subid: files\n"))[0], None)
rec("G-SUB-FILE-READABLE an unreadable subuid file (a directory) is unknown", rr._subid_ranges((W,), nss("subid: files\n"))[0], None)
why = rr._subid_ranges((sub,), nss("subid: files sss\n"))[1]
rec("G-SUB-NSS-FILES-ONLY the reason names every source of the line", "files sss" in (why or ""), True)
# listxattr must be asked about the inode itself, never what a symlink points at
seen = []
def spy(path, follow_symlinks=True):
    seen.append(follow_symlinks); return []
os.listxattr = spy
rr._has_acl(probe)
os.listxattr = real
rec("G-ACL-UNLISTABLE listxattr is called with follow_symlinks=False", seen, [False])
# on Linux ENOTSUP and EOPNOTSUPP are one errno, so narrowing the tuple to either is equivalent
rec("errno.ENOTSUP == errno.EOPNOTSUPP on this platform (equivalence proof of the two tuple mutants)",
    errno.ENOTSUP == errno.EOPNOTSUPP or sys.platform != "linux", True)
# symlink budget: the kernel follows at most 40 links, the 41st is ELOOP
def chain_of(n, tag):
    d = os.path.join(W, tag); os.mkdir(d)
    tgt = os.path.join(d, "f"); open(tgt, "w").write("x")
    prev = "f"
    for k in range(n, 0, -1):
        os.symlink(prev, os.path.join(d, "l%d" % k)); prev = "l%d" % k
    return os.path.join(d, "l1")
def resolves(p):
    try: rr._resolution_chain(p); return True
    except OSError: return False
def kernel(p):
    try: os.stat(p); return True
    except OSError: return False
for n in (1, 39, 40, 41, 42):
    p = chain_of(n, "chain%d" % n)
    rec("G-T-LINK-LOOP %d chained symlinks: resolver agrees with the kernel" % n, resolves(p), kernel(p))
rec("G-T-LINK-LOOP exactly 40 links resolve", resolves(chain_of(40, "c40b")), True)
rec("G-T-LINK-LOOP 41 links do not", resolves(chain_of(41, "c41b")), False)
# a leaf that is neither a regular file nor a directory is refused
ff = os.path.join(W, "fifo"); os.mkfifo(ff)
rec("G-T-LEAF-TYPE a FIFO leaf does not resolve", resolves(ff), False)
# passwd lookups that raise OverflowError (a uid beyond the C range) are "not an account"
def getpw_over(u): raise OverflowError("uid")
def getpw_key(u): raise KeyError(u)
def getpw_ok(u): return object()
for nm, g in (("OverflowError", getpw_over), ("KeyError", getpw_key)):
    rec("G-T-OWNER-IN-PASSWD %s means not an account" % nm,
        isinstance(rr._owner_declaration_error(2000, 3000, 1000, [], g), str), True)
    rec("G-T-PRODUCER-KNOWN %s means not an account" % nm,
        rr._path_tier([], 3000, 2000, 1000, [], g)[0], "instance")
rec("G-T-PRODUCER-DECLARED producer uid 1 is a declared non-root producer",
    rr._path_tier([], 1, 2000, 1000, [], getpw_ok), ("capability", None))
rec("G-T-PRODUCER-DECLARED producer uid 0 is refused",
    rr._path_tier([], 0, 2000, 1000, [], getpw_ok)[0], "instance")

# --- R6-F1 (round 7): the gate's call site binds the store tier to the RIGHT arguments ------
# Reviewer mutant RV6-E passed --records where --dispatch-ledger belongs: a producer-owned ledger
# then stood beside a "capability" verdict. The real cmd_gate is driven (no tier logic stubbed
# out of it except the tier function, replaced by a spy that records its arguments) at EVERY
# high-blast seam and at the ordinary one. Unit class (11.4.289(C)(1)): the spy is the unit
# under observation's collaborator; the real-process leg is R4-CAP8 in the r4 suite.
import argparse, contextlib, io
def run_gate(seam, rec, led, producer=1234, owner=5678):
    calls = []
    orig = rr._store_tier
    def spy(records_dir, ledger_path, producer_uid, owner_uid, *more, **kw):
        calls.append((records_dir, ledger_path, producer_uid, owner_uid, more, kw)); return ("capability", None)
    rr._store_tier = spy
    ns = argparse.Namespace(change="c1", round_budget=None, records=rec, dispatch_ledger=led,
                            producer_uid=producer, evidence_owner_uid=owner, seam=seam)
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            rc = rr.cmd_gate(ns)
    finally:
        rr._store_tier = orig
    return calls, rc
grec = os.path.join(W, "gate_records"); os.mkdir(grec)
gled = os.path.join(W, "gate_ledger.jsonl"); open(gled, "w").write("")
for seam in ("ordinary",) + tuple(rr.HIGH_BLAST_SEAMS):
    calls, rc = run_gate(seam, grec, gled)
    rec("G-G-TIER-CALL gate(%s) calls _store_tier exactly once" % seam, len(calls), 1)
    rec("G-G-TIER-CALL gate(%s) passes (records, dispatch_ledger, producer_uid, evidence_owner_uid) in that order" % seam,
        calls[0][:4] if calls else None, (grec, gled, 1234, 5678))
rec("G-G-TIER-CALL the records directory and the dispatch ledger are different paths (the check can tell them apart)", grec != gled, True)

# --- R6-F4 (round 7): the DEFAULT sub-id file list is exercised, subgid included ----------
import builtins
fake = {"/etc/nsswitch.conf": "subid: files\n", "/etc/subuid": "u:100000:65536\n", "/etc/subgid": "g:300000:65536\n"}
real_open = builtins.open
def fake_open(p, *a, **k):
    if p in fake:
        return io.StringIO(fake[p])
    return real_open(p, *a, **k)
builtins.open = fake_open
try:
    got = rr._subid_ranges()
finally:
    builtins.open = real_open
rec("G-SUB-DEFAULT-FILES the default call reads /etc/subuid AND /etc/subgid", got, ([(100000, 65536), (300000, 65536)], None))
rec("G-SUB-DEFAULT-FILES the default list is exactly the two files", tuple(rr._SUBID_FILES), ("/etc/subuid", "/etc/subgid"))
for line in res: print(line)
PY
)
RC=$?
[ "$RC" -eq 0 ] || { echo "setup: python driver failed rc=$RC"; echo "$OUT"; exit 2; }
while IFS=$'\t' read -r v name got want; do
  if [ "$v" = PASS ]; then ok "$name"; else bad "$name -- got $got want $want"; fi
done <<<"$OUT"
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
