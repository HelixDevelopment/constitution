#!/usr/bin/env bash
# fastcycle-timeout-s: 900
# =============================================================================
# test_fc_safepath_v4r13.sh -- T048 V4 round 13 (round-6 review of the round-12 pack: NO-GO, V4R13-1 MINOR
# source-defect, V4R13-2 / V4R13-3 MINOR test-instrumentation, V4R13-4 process-doc, NITs 1-5). The LAST budget round
# (§11.4.276: R_max = 7). Rows:
#
# [R13TRUST-*]   _trusted_ok, clause by clause, on SYNTHETIC stat results (a pure function: no root needed) -- root's
#                0777 non-sticky -> refused (RV6-15), root's 1777 / 0755 -> trusted, ours 0775 whose group has another
#                member -> refused (RV6-02), ours 0775 whose group is ours alone -> trusted (V4R13-1), ours 0777 / 1777.
# [R13GROUP-*]   _group_private against the REAL group database, each expectation computed here independently
#                (grp / pwd): this user's own primary group, a group with another member (wheel-like), a group whose
#                member list is only this user but another account's PRIMARY group (users-like), a group that is not
#                this user's at all (tty-like: a setgid program of it could write) -> only the first is private.
# [R13REAL-*]    the same on REAL directories (chgrp to a group of ours): group-writable + shared group -> _walk refuses
#                and SAYS "writable by group <gid>" with the remedy; + private group -> trusted.
# [R13WALK-*]    NIT-5: `<untrusted dir>/..` names the proved parent -> trusted; `<untrusted dir>/x` still refused.
# [R13RM-*]      _rmtree_at refuses any name that is not ONE plain entry ('..', '.', 'a/b'): a parent's contents are
#                never reached (RV6-11's consequence); the TOP directory swapped between the look and the open is not
#                cleared (RV6-06); an empty directory swapped in under the name before the final rmdir is not removed
#                (RV6-05); `safepath rmtree D/x/..` -> 4 with the REAL reason ("no final name", NIT-3).
# [R13EXCL-*]    `safepath check --exclusive` refuses a directory of ours that is 1777 (trusted as a parent, not ours
#                ALONE) and root's /usr (RV6-07); the worker handed a 1777 temp dir of ours refuses (RV6-08).
# [R13LOCK-*]    NIT-1: lock files are made 0600; an old 0644 lock file is REPLACED while its lock is held (the old
#                inode stays locked: a replay that opened it before still finds it busy); another uid cannot open it.
# [R13CLI-newline] NIT-4: a path argument holding a newline -> 4, nothing created.
# [R13UMASK-*]   V4R13-1 END TO END: the DEFAULT flow (no --worktree-root) on a repository made under umask 002 (dirs
#                0775, group = this user's own) -> exit 0 and a report (round 6: BLIND 4); the same with the
#                repository directory's group set to one with another member -> BLIND 4 naming the group and the
#                path, and the BLIND line names the --worktree-root it could not create (V4R13-1(b), not empty).
# [R13MSG-sites] V4R13-1(b): no site assigns `_fc_safe mkdir --exclusive` over the variable its message prints.
# [R13CENSUS-self] tests/check_safepath_census.py --self-test: every needle (the round-6 reviewer's 24 Python + 32
#                shell forms and round 13's own) REFUSED on its own line, every control ACCEPTED.
#
# Env: FC_BR_UNDER_TEST / FC_SUP_UNDER_TEST -- the files under test (the paired-mutation runner points them at a
#      replica); R13_ONLY -- space-separated row groups (PY CLI SH LOCK CENSUS).
# Exit: 0 every row held; 1 otherwise. A row that needs a host fact this host lacks prints SKIP (not counted).
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"
SUP="${FC_SUP_UNDER_TEST:-$FC/cycle/fc_supervisor.py}"
CENSUS="${FC_CENSUS_UNDER_TEST:-$HERE/check_safepath_census.py}"
[ -f "$SCRIPT" ] || { echo "NOT ok script under test not found: $SCRIPT"; exit 1; }
[ -f "$SUP" ] || { echo "NOT ok supervisor under test not found: $SUP"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }
tally() { # count the ok / NOT ok lines a python block printed; $1 = the block's last line: if it is missing (the
  # block crashed part-way, e.g. on code without a helper it calls), that is a FAILED row, never a silent pass
  local l done=0
  while IFS= read -r l; do
    case "$l" in
      "ok "*) PASS=$((PASS+1)); echo "$l" ;;
      "NOT ok "*) FAIL=$((FAIL+1)); echo "$l" ;;
      "$1") done=1 ;;
      *) echo "$l" ;;
    esac
  done
  [ "$done" = 1 ] || bad "[$1] the python block did not run to its end (crashed or killed) -- its remaining rows did not run"
}
want() {
  [ -z "${R13_ONLY:-}" ] && return 0
  case " $R13_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}
NS=(unshare --map-users=auto --map-groups=auto --map-root-user)
WORK="$(mktemp -d "${TMPDIR:-/tmp}/fc_r13.XXXXXX")"
chmod 755 "$WORK"
export FC_REPLAY_LOCK_DIR="$WORK/locks"
mkdir -p "$FC_REPLAY_LOCK_DIR"
cleanup() {
  "${NS[@]}" rm -rf "$WORK" >/dev/null 2>&1
  chmod -R u+rwx "$WORK" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT
_FC_SUPERVISOR="$(dirname "$SCRIPT")/fc_supervisor.py"
eval "$(grep -m1 '^_fc_safe()' "$SCRIPT")"
# a group of this user's that has ANOTHER member (gr_mem, or another account's primary group) -- found independently
SHARED_GID="$(python3 -I - <<'PY'
import grp, os, pwd
me = pwd.getpwuid(os.geteuid()).pw_name
for g in os.getgroups():
    try:
        gr = grp.getgrgid(g)
    except KeyError:
        continue
    if [u for u in gr.gr_mem if u != me] or [p for p in pwd.getpwall() if p.pw_gid == g and p.pw_uid != os.geteuid()]:
        print(g)
        break
PY
)"
PRIV_OK="$(python3 -I - <<'PY'
import grp, os, pwd
me = pwd.getpwuid(os.geteuid()).pw_name
g = os.getegid()
print("yes" if not [u for u in grp.getgrgid(g).gr_mem if u != me] and
      not [p for p in pwd.getpwall() if p.pw_gid == g and p.pw_uid != os.geteuid()] else "no")
PY
)"

# =============================================================================
if want PY; then
  P="$WORK/py"; mkdir -p "$P"; chmod 755 "$P"
  cat >"$WORK/py.py" <<'PY'
import importlib.util, os, sys, grp, pwd, stat as st_
spec = importlib.util.spec_from_file_location("fcsup", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
P, SG, PRIV = sys.argv[2], sys.argv[3], sys.argv[4] == "yes"
me = pwd.getpwuid(os.geteuid()).pw_name
euid, egid = os.geteuid(), os.getegid()
def ok(t): print("ok " + t)
def bad(t): print("NOT ok " + t)
def fake(mode, uid, gid):
    return os.stat_result((mode, 1, 1, 1, uid, gid, 0, 0, 0, 0))
# independent expectation of "private": nobody but me in gr_mem, nobody else's primary group, and it is mine
def indep_private(g):
    try:
        gr = grp.getgrgid(g)
    except KeyError:
        return False
    return (g == egid or g in os.getgroups()) and not [u for u in gr.gr_mem if u != me] and \
        not [p for p in pwd.getpwall() if p.pw_gid == g and p.pw_uid != euid]
# ---- [R13TRUST-*] the rule, clause by clause (synthetic stat: _trusted_ok is a pure function of it) ----
real_gp = m._group_private
real_af = getattr(m, "_acl_free", None)            # round 14 (V4R14-1): these rows are about a directory with NO ACL
if real_af is not None:
    m._acl_free = lambda ref: True
try:
    m._group_private = lambda gid: False             # a group with another member
    for tid, mode, uid, want in (("root777", 0o40777, 0, False), ("root1777", 0o41777, 0, True),
                                 ("root755", 0o40755, 0, True), ("root775-shared", 0o40775, 0, False),
                                 ("own775-shared", 0o40775, euid, False), ("own777", 0o40777, euid, False),
                                 ("own1777", 0o41777, euid, True), ("own755", 0o40755, euid, True),
                                 ("other755", 0o40755, euid + 1 if euid + 1 else 2, False)):
        got = m._trusted_ok(fake(mode, uid, 4242))
        (ok if got == want else bad)("[R13TRUST-%s] _trusted_ok(mode %o, uid %d, a SHARED group) = %s (want %s)"
                                     % (tid, mode & 0o7777, uid, got, want))
    m._group_private = lambda gid: True              # a group holding only this user
    for tid, mode, uid, want in (("own775-private", 0o40775, euid, True), ("own777-private", 0o40777, euid, False),
                                 ("root775-private", 0o40775, 0, True), ("own2775-private", 0o42775, euid, True)):
        got = m._trusted_ok(fake(mode, uid, egid))
        (ok if got == want else bad)("[R13TRUST-%s] _trusted_ok(mode %o, uid %d, a PRIVATE group) = %s (want %s)"
                                     % (tid, mode & 0o7777, uid, got, want))
    # the namespace check (open_owned_dir's _owned_ok): the same group exemption, never for other-write
    for tid, mode, want in (("own770", 0o40770, True), ("own707", 0o40707, False), ("own777", 0o40777, False)):
        got = m._owned_ok(fake(mode, euid, egid), st_.S_ISDIR, m.DIR_FORBID)
        (ok if got == want else bad)("[R13OWNED-%s] _owned_ok(mode %o, ours, a PRIVATE group) = %s (want %s)"
                                     % (tid, mode & 0o7777, got, want))
finally:
    m._group_private = real_gp
    if real_af is not None:
        m._acl_free = real_af
# ---- [R13GROUP-*] the real group database ----
m._GROUP_PRIVATE.clear()
want = indep_private(egid)
got = m._group_private(egid)
(ok if got == want else bad)("[R13GROUP-own] this user's primary group %d: private=%s (independent: %s)" % (egid, got, want))
if SG:
    got = m._group_private(int(SG))
    (ok if got is False else bad)("[R13GROUP-shared] group %s has another member: private=%s (want False)" % (SG, got))
else:
    print("SKIP [R13GROUP-shared] this user is in no group with another member -- not counted")
prim = [g for g in os.getgroups() if g != egid and
        not [u for u in grp.getgrgid(g).gr_mem if u != me] and
        [p for p in pwd.getpwall() if p.pw_gid == g and p.pw_uid != euid]]
if prim:
    got = m._group_private(prim[0])
    (ok if got is False else bad)("[R13GROUP-primary] group %d: its member list names only this user, but it is "
                                  "another account's PRIMARY group -> private=%s (want False)" % (prim[0], got))
else:
    print("SKIP [R13GROUP-primary] no group of this user is only another account's primary group -- not counted")
mine = set(os.getgroups()) | {egid}
alien = [g.gr_gid for g in grp.getgrall() if g.gr_gid not in mine and not g.gr_mem and
         not [p for p in pwd.getpwall() if p.pw_gid == g.gr_gid]]
if alien:
    got = m._group_private(alien[0])
    (ok if got is False else bad)("[R13GROUP-notours] group %d (no member, nobody's primary group, but NOT this "
                                  "user's: a setgid program of it could write) -> private=%s (want False)" % (alien[0], got))
else:
    print("SKIP [R13GROUP-notours] no memberless group outside this user's -- not counted")
got = m._group_private(2147480001)
(ok if got is False else bad)("[R13GROUP-unknown] a gid the database does not know -> private=%s (want False)" % got)
# ---- [R13REAL-*] real directories ----
def walk_v(p):
    try:
        fd, _r = m._walk(p); os.close(fd); return "trusted"
    except OSError as e:
        return "refused: %s" % e
if SG:
    d = os.path.join(P, "gshared"); os.mkdir(d); os.chown(d, -1, int(SG)); os.chmod(d, 0o775)
    os.mkdir(os.path.join(d, "x"), 0o700)
    v = walk_v(os.path.join(d, "x"))
    (ok if v.startswith("refused") and ("writable by group %s" % SG) in v and "chmod g-w" in v else bad)(
        "[R13REAL-shared] a 0775 directory whose group (%s) has another member, on the path -> refused, the reason "
        "names the group and the remedy: %s" % (SG, v[:200]))
else:
    print("SKIP [R13REAL-shared] no shared group -- not counted")
if PRIV:
    d = os.path.join(P, "gpriv"); os.mkdir(d); os.chmod(d, 0o775)
    os.mkdir(os.path.join(d, "x"), 0o700)
    v = walk_v(os.path.join(d, "x"))
    (ok if v == "trusted" else bad)("[R13REAL-private] a 0775 directory whose group is this user's alone -> %s" % v[:160])
else:
    print("SKIP [R13REAL-private] this user's primary group has another member -- not counted")
# ---- [R13WALK-*] NIT-5 ----
g7 = os.path.join(P, "g777"); os.mkdir(g7); os.chmod(g7, 0o777)
os.mkdir(os.path.join(P, "sib"), 0o755)
v = walk_v(os.path.join(g7, "..", "sib"))
(ok if v == "trusted" else bad)("[R13WALK-dotdot-untrusted] <a 0777 dir>/../sib names the proved parent's sib -> %s" % v[:140])
os.mkdir(os.path.join(g7, "in"), 0o755)
v = walk_v(os.path.join(g7, "in"))
(ok if v.startswith("refused") else bad)("[R13WALK-untrusted-mid] <a 0777 dir>/in is still refused -> %s" % v[:140])
v = walk_v(os.path.join(g7, "in", "..", "..", "sib"))
(ok if v.startswith("refused") else bad)("[R13WALK-untrusted-deep] <0777>/in/../../sib: `in` is entered (no `..` right "
                                         "after the 0777 dir) -> refused: %s" % v[:120])
# ---- [R13RM-*] _rmtree_at ----
D = os.path.join(P, "rmD"); os.mkdir(D); os.mkdir(os.path.join(D, "x")); open(os.path.join(D, "precious"), "w").write("P")
pfd, _r = m._walk(os.path.join(D, "x"))
try:
    res = {n: m._rmtree_at(pfd, n) for n in ("..", ".", "", "a/b", "../precious")}
finally:
    os.close(pfd)
intact = os.path.isfile(os.path.join(D, "precious")) and os.path.isdir(os.path.join(D, "x"))
(ok if intact and not any(res.values()) else bad)(
    "[R13RM-name-guard] _rmtree_at(<fd of D/x>, '..' / '.' / '' / 'a/b' / '../precious') refuses each (%r); D's "
    "content intact=%s" % (res, intact))
# RV6-06: the TOP directory swapped between the look and the open
T = os.path.join(P, "topswap"); os.mkdir(T); os.mkdir(os.path.join(T, "tree")); open(os.path.join(T, "tree", "f"), "w").write("t")
V = os.path.join(P, "victim6"); os.mkdir(V); open(os.path.join(V, "keep"), "w").write("K")
real_open = os.open
state = {"done": False}
def spy_open(p, *a, **k):
    if p == "tree" and k.get("dir_fd") is not None and not state["done"]:
        state["done"] = True
        os.rename(os.path.join(T, "tree"), os.path.join(T, "tree.away"))
        os.rename(V, os.path.join(T, "tree"))
    return real_open(p, *a, **k)
pfd, _r = m._walk(T)
os.open = spy_open
try:
    r6 = m._rmtree_at(pfd, "tree")
finally:
    os.open = real_open
    os.close(pfd)
kept = os.path.join(T, "tree", "keep")
(ok if state["done"] and os.path.isfile(kept) else bad)(
    "[R13RM-top-swap] the top directory replaced (by a directory holding `keep`) between the look and the open is "
    "NOT cleared: keep %s (rmtree -> %s)" % ("intact" if os.path.isfile(kept) else "DELETED", r6))
# RV6-05: an EMPTY directory swapped in under the name before the final rmdir
T2 = os.path.join(P, "finswap"); os.mkdir(T2); os.mkdir(os.path.join(T2, "tree"))
E = os.path.join(P, "emptyvictim"); os.mkdir(E)
real_stat = os.stat
cnt = {"n": 0}
def spy_stat(p, *a, **k):
    if p == "tree" and k.get("dir_fd") is not None:
        cnt["n"] += 1
        if cnt["n"] == 2:                      # the identity re-check before the final rmdir
            os.rename(os.path.join(T2, "tree"), os.path.join(T2, "tree.away"))
            os.rename(E, os.path.join(T2, "tree"))
    return real_stat(p, *a, **k)
pfd, _r = m._walk(T2)
os.stat = spy_stat
try:
    r5 = m._rmtree_at(pfd, "tree")
finally:
    os.stat = real_stat
    os.close(pfd)
(ok if cnt["n"] >= 2 and os.path.isdir(os.path.join(T2, "tree")) else bad)(
    "[R13RM-final-identity] an empty directory swapped in under the name before the final rmdir is NOT removed "
    "(the rmdir checks dev+ino): still there=%s (rmtree -> %s, looks=%d)" % (os.path.isdir(os.path.join(T2, "tree")), r5, cnt["n"]))
print("R13PY-ran")
PY
  tally R13PY-ran < <(python3 -I "$WORK/py.py" "$SUP" "$P" "$SHARED_GID" "$PRIV_OK" 2>&1)
fi

# =============================================================================
if want CLI; then
  C="$WORK/cli"; mkdir -p "$C/D/x"; chmod 755 "$C"; echo P >"$C/D/precious"
  _fc_safe rmtree "$C/D/x/.." >/dev/null 2>"$C/rm.err"; rc=$?
  [ "$rc" = 4 ] && [ -f "$C/D/precious" ] && [ -d "$C/D/x" ] && grep -q "no final name" "$C/rm.err" \
    && ok "[R13RM-dotdot-cli] safepath rmtree D/x/.. -> 4, D's content intact, the reason said (NIT-3): $(head -c 120 "$C/rm.err")" \
    || bad "[R13RM-dotdot-cli] rc=$rc precious=$([ -f "$C/D/precious" ] && echo intact || echo DELETED) err=$(head -c 200 "$C/rm.err")"
  nl="$C/a
b"
  _fc_safe mkdir "$nl" >/dev/null 2>"$C/nl.err"; rc=$?
  [ "$rc" = 4 ] && [ ! -e "$C/a" ] && [ ! -e "$nl" ] && grep -q newline "$C/nl.err" \
    && ok "[R13CLI-newline] a path argument holding a newline -> 4, nothing created (NIT-4)" \
    || bad "[R13CLI-newline] rc=$rc $(head -c 160 "$C/nl.err")"
  mkdir "$C/own1777"; chmod 1777 "$C/own1777"
  _fc_safe check "$C/own1777" >/dev/null 2>&1; rc1=$?
  _fc_safe check --exclusive "$C/own1777" >/dev/null 2>&1; rc2=$?
  _fc_safe check --exclusive /usr >/dev/null 2>&1; rc3=$?
  _fc_safe check /usr >/dev/null 2>&1; rc4=$?
  [ "$rc1" = 0 ] && [ "$rc2" = 4 ] && [ "$rc3" = 4 ] && [ "$rc4" = 0 ] \
    && ok "[R13EXCL-check] check: a 1777 dir of ours and root's /usr are trusted (0, 0); --exclusive refuses both (4, 4): trusted as a parent, not this user's ALONE" \
    || bad "[R13EXCL-check] own1777: check=$rc1 --exclusive=$rc2; /usr: --exclusive=$rc3 check=$rc4 (want 0 4 4 0)"
fi

# =============================================================================
g() { git -c user.email=t@t.t -c user.name=t "$@"; }
mk_repo() { mkdir -p "$1"; g init -q "$1"; echo hello >"$1/f.txt"; g -C "$1" add f.txt; g -C "$1" commit -q -m "base commit"; }
if want SH; then
  S="$WORK/sh"; mkdir -p "$S"; chmod 755 "$S"
  # ---- the worker handed a temp directory of ours that is 1777 (trusted as a parent; NOT ours alone) ----
  WT7="$S/fc_baseline_replay.w1777"; mkdir "$WT7"; chmod 1777 "$WT7"
  WS7="$S/fc_baseline_replay.state.w1777"; mkdir -m 700 "$WS7"
  FC_BR_SUPERVISED=1 FC_BR_SUPERVISOR_PID=$$ FC_BR_TMPDIR="$WT7" FC_BR_STATEDIR="$WS7" \
    bash "$SCRIPT" selfcheck --out "$S/w7.json" >/dev/null 2>"$S/w7.err"; rc=$?
  [ "$rc" = 4 ] && grep -q "trusted-parent rule" "$S/w7.err" && [ ! -e "$S/w7.json" ] \
    && ok "[R13EXCL-workerinit] a worker handed a 1777 temp directory of ours (passes the non-exclusive check) refuses (BLIND 4): it must be this user's ALONE" \
    || bad "[R13EXCL-workerinit] rc=$rc $(head -c 200 "$S/w7.err")"
  # ---- V4R13-1: the DEFAULT flow on a umask-002 repository ----
  if [ "$PRIV_OK" = yes ]; then
    U="$S/u002"
    ( umask 002; mkdir -p "$U/work"; mk_repo "$U/work/repo" )
    HEAD_SHA="$(git -C "$U/work/repo" rev-parse HEAD)"
    m1="$(stat -c %a "$U/work")"
    ( umask 002; bash "$SCRIPT" replay --commit "$HEAD_SHA" --repo-root "$U/work/repo" --min-free-kb 0 --min-free-kb-objects 0 \
        --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$U/out/u.json" >/dev/null 2>"$S/u.err" ); rc=$?
    [ "$m1" = 775 ] && [ "$rc" = 0 ] && [ -s "$U/out/u.json" ] \
      && ok "[R13UMASK-default] the DEFAULT flow (no --worktree-root) on a repository made under umask 002 (dirs $m1, group: this user's own) -> exit 0, report written (round 6: BLIND 4)" \
      || bad "[R13UMASK-default] dir mode=$m1 rc=$rc report=$([ -s "$U/out/u.json" ] && echo yes || echo no) $(head -c 300 "$S/u.err")"
  else
    echo "SKIP [R13UMASK-default] this user's primary group has another member -- not counted"
  fi
  if [ -n "$SHARED_GID" ]; then
    U2="$S/ushared"
    mkdir -p "$U2/work"; mk_repo "$U2/work/repo"
    chgrp "$SHARED_GID" "$U2/work" && chmod 775 "$U2/work"
    HEAD2="$(git -C "$U2/work/repo" rev-parse HEAD)"
    bash "$SCRIPT" replay --commit "$HEAD2" --repo-root "$U2/work/repo" --min-free-kb 0 --min-free-kb-objects 0 \
      --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/us.json" >/dev/null 2>"$S/us.err"; rc=$?
    [ "$rc" = 4 ] && [ ! -e "$U2/work/repo/.fc_worktrees" ] && grep -q "writable by group $SHARED_GID" "$S/us.err" \
      && grep -q "chmod g-w" "$S/us.err" \
      && grep -q -- "cannot create --worktree-root $U2/work/repo/.fc_worktrees," "$S/us.err" \
      && ok "[R13UMASK-shared] a repository directory group-writable for a group with another member ($SHARED_GID) -> BLIND 4: the reason names the group and the remedy; the BLIND line names the --worktree-root (not empty)" \
      || bad "[R13UMASK-shared] rc=$rc made=$([ -e "$U2/work/repo/.fc_worktrees" ] && echo yes || echo no) $(head -c 400 "$S/us.err")"
    # replay-sample's site (V4R13-1(b)): its BLIND line names the --worktree-root it could not create
    printf '{"items": []}\n' >"$S/sample.json"
    bash "$SCRIPT" replay-sample --sample "$S/sample.json" --repo-root "$U2/work/repo" --min-free-kb 0 --min-free-kb-objects 0 \
      --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/uss.json" >/dev/null 2>"$S/uss.err"; rc=$?
    [ "$rc" = 4 ] && grep -q -- "replay-sample: cannot create --worktree-root $U2/work/repo/.fc_worktrees," "$S/uss.err" \
      && ok "[R13MSG-sample] replay-sample's BLIND line names the --worktree-root it could not create (V4R13-1(b))" \
      || bad "[R13MSG-sample] rc=$rc $(grep -m1 -i 'worktree-root' "$S/uss.err" | cut -c1-200)"
  else
    echo "SKIP [R13UMASK-shared / R13MSG-sample] no group of this user's has another member -- not counted"
  fi
  # ---- RV6-14's premise: a replay-logs directory of ours that is 1777 -> refused (by the --exclusive mkdir AND by the
  # --exclusive-parent mkdtemp right after it: either alone refuses, which is why RV6-14 is an EQUIVALENT mutant) ----
  RL="$S/wtlogs"; mkdir -m 700 "$RL"; mkdir "$RL/replay-logs"; chmod 1777 "$RL/replay-logs"
  REPO3="$S/repo3"; mk_repo "$REPO3"; HEAD3="$(git -C "$REPO3" rev-parse HEAD)"
  bash "$SCRIPT" replay --commit "$HEAD3" --repo-root "$REPO3" --worktree-root "$RL" --min-free-kb 0 --min-free-kb-objects 0 \
    --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/rl.json" >/dev/null 2>"$S/rl.err"; rc=$?
  [ "$rc" = 4 ] && [ -z "$(ls -A "$RL/replay-logs")" ] && grep -q "trusted-parent rule" "$S/rl.err" \
    && ok "[R13SH-logs1777] a replay-logs directory of ours that is 1777 (others may create names in it) -> BLIND 4, nothing made in it" \
    || bad "[R13SH-logs1777] rc=$rc made=[$(ls -A "$RL/replay-logs" | tr '\n' ' ')] $(head -c 200 "$S/rl.err")"
  # ---- V4R13-1(b), every site: the helper's answer never overwrites the variable its message prints ----
  n_bad="$(grep -c 'worktree_root="$(_fc_safe mkdir' "$SCRIPT")"
  n_new="$(grep -c '_wr="$(_fc_safe mkdir --exclusive "$worktree_root")"' "$SCRIPT")"
  [ "$n_bad" = 0 ] && [ "$n_new" = 3 ] \
    && ok "[R13MSG-sites] all 3 --worktree-root sites prove into _wr and print the caller's value (none assigns over it)" \
    || bad "[R13MSG-sites] assigning sites left=$n_bad, _wr sites=$n_new (want 0 / 3)"
fi

# =============================================================================
if want LOCK; then
  L="$WORK/lock"; mkdir -p "$L"; chmod 755 "$L"
  cat >"$WORK/lock.py" <<'PY'
import importlib.util, os, sys, fcntl, subprocess
spec = importlib.util.spec_from_file_location("fcsup", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
L = sys.argv[2]
def ok(t): print("ok " + t)
def bad(t): print("NOT ok " + t)
def child(fn):
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(r)
        try:
            out = repr(fn())
        except SystemExit as e:
            out = "exit %r" % (e.code,)
        except BaseException as e:   # noqa
            out = "raise %s" % e
        os.write(w, out.encode()); os._exit(0)
    os.close(w)
    data = b""
    while True:
        b = os.read(r, 4096)
        if not b:
            break
        data += b
    os.close(r); os.waitpid(pid, 0)
    return data.decode()
# a fresh lock file: 0600
p1 = os.path.join(L, "fresh.lock")
def fresh():
    m._lock_one(p1, "t")
    return (oct(os.stat(p1).st_mode & 0o777), len(m._OLD_LOCKS))
r = child(fresh)
(ok if r == "('0o600', 0)" else bad)("[R13LOCK-0600] a lock file is CREATED 0600 (others cannot open it to hold the flock) "
                                     "-- no replacement was needed for a fresh one (mode, replaced) = %s" % r)
# an old 0644 lock file: replaced while held; an fd opened on the old inode BEFORE stays blocked
p2 = os.path.join(L, "old.lock")
fd = os.open(p2, os.O_RDWR | os.O_CREAT, 0o644); os.fchmod(fd, 0o644); os.close(fd)
old_ino = os.stat(p2).st_ino
pre = os.open(p2, os.O_RDONLY)                     # what another reader opened while the file was 0644
rd, wr = os.pipe()
pid = os.fork()
if pid == 0:
    os.close(rd)
    try:
        m._lock_one(p2, "t")
        os.write(wr, b"held")
    except SystemExit:
        os.write(wr, b"exit")
    os.close(wr)
    import time
    time.sleep(5)                                   # hold the locks while the parent probes
    os._exit(0)
os.close(wr)
msg = os.read(rd, 16)
st = os.stat(p2)
try:
    fcntl.flock(pre, fcntl.LOCK_EX | fcntl.LOCK_NB)
    old_free = True
except BlockingIOError:
    old_free = False
nf = os.open(p2, os.O_RDONLY)
try:
    fcntl.flock(nf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    new_free = True
except BlockingIOError:
    new_free = False
os.close(nf); os.close(pre); os.close(rd)
os.kill(pid, 9); os.waitpid(pid, 0)
(ok if msg == b"held" and st.st_ino != old_ino and st.st_mode & 0o777 == 0o600 else bad)(
    "[R13LOCK-migrate] an old 0644 lock file of ours is REPLACED while its lock is held: new inode=%s, mode %o (%s)"
    % (st.st_ino != old_ino, st.st_mode & 0o777, msg))
(ok if not old_free else bad)("[R13LOCK-old-held] an fd opened on the OLD lock file before the replacement still finds it "
                              "locked (else two replays could run at once): free=%s" % old_free)
(ok if not new_free else bad)("[R13LOCK-new-held] the new lock file at the name is locked: free=%s" % new_free)
print("R13LOCK-ran")
PY
  tally R13LOCK-ran < <(python3 -I "$WORK/lock.py" "$SUP" "$L" 2>&1)
  # another (real, subordinate) uid cannot open a lock file this tool made
  LF="$L/fresh.lock"
  CF="$L/control644"; : >"$CF"; chmod 644 "$CF"
  if [ -f "$LF" ] && unshare --map-users=auto --map-groups=auto --map-root-user setpriv --reuid=1000 \
      sh -c 'exec 9<"$1"' sh "$CF" 2>/dev/null; then   # control: the instrument CAN open a 0644 file
    if unshare --map-users=auto --map-groups=auto --map-root-user setpriv --reuid=1000 \
        sh -c 'exec 9<"$1"' sh "$LF" 2>/dev/null; then
      bad "[R13LOCK-foreign] another uid OPENED the lock file (it could hold the flock forever)"
    else
      ok "[R13LOCK-foreign] another (real, subordinate) uid cannot open the 0600 lock file (control: it opens a 0644 file)"
    fi
  else
    echo "SKIP [R13LOCK-foreign] no subordinate uid available (or its control open failed) -- not counted"
  fi
fi

# =============================================================================
if want CENSUS; then
  out="$(FC_SUP_UNDER_TEST="$SUP" FC_BR_UNDER_TEST="$SCRIPT" python3 "$CENSUS" --self-test 2>&1)"; rc=$?
  n="$(sed -n 's/^SELFTEST cases=\([0-9]*\) failed=\([0-9]*\)$/\1 \2/p' <<<"$out")"
  if [ "$rc" = 0 ] && [ "${n% *}" -ge 100 ] 2>/dev/null && [ "${n#* }" = 0 ]; then
    ok "[R13CENSUS-self] the census refuses every needle on its own line and accepts every control: cases/failed = $n"
  else
    bad "[R13CENSUS-self] rc=$rc cases/failed=$n $(grep -m3 '^NOT-ok' <<<"$out" | tr '\n' ' ' | cut -c1-300)"
  fi
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
