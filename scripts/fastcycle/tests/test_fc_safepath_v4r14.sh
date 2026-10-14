#!/usr/bin/env bash
# fastcycle-timeout-s: 900
# =============================================================================
# test_fc_safepath_v4r14.sh -- T048 V4 round 14 (round-7 review of the round-13 pack: NO-GO, V4R14-1 IMPORTANT
# source-defect -- a POSIX-ACL write grant to another user passed as "group-private"; V4R14-2 MINOR census escapes;
# V4R14-3 MINOR doc overclaims + the /tmp lock pre-plant; NIT-A RV7-06; NIT-B replay-sample's --exclusive).
# Operator decision 2026-10-13: a scoped follow-up structural item with a FRESH review budget (ATM-1041 follow-up).
#
# V4R14-1 is closed as a CLASS (§11.4.276(C)): "a group-private / ownership certification that ignores a non-mode-bit
# access grant". Each member below is either CLOSED (a row, with a REAL foreign uid where the oracle needs one) or
# SCOPED OUT with its reason in docs/qa/v4_round8_20261013/CONVERGENCE.md.
#
# The foreign uid is REAL: a subordinate uid of this user (unshare --map-users=auto ... setpriv --reuid/--regid
# --clear-groups), a distinct kernel uid with NO group of ours -- not a simulation. On a host without subordinate ids
# the rows that need it print SKIP (not counted). Rows marked SIMULATED inject a kernel answer the host cannot be made
# to give (an unreadable xattr) and say so.
#
# [R14ACL-grant]      fixture control: `setfacl -m u:<foreign>:rwx D` on a 0700 directory of ours really lets the
#                     foreign uid create in D (the oracle that the grant is genuine), and is refused without it.
# [R14ACL-check]      `safepath check --exclusive D` -> 4 (round 13: 0, the regression V4R14-1).
# [R14ACL-mkdir]      `safepath mkdir --exclusive D/ns` -> 4, nothing made.
# [R14ACL-write]      `safepath write --text precious D report` -> 4, nothing written.
# [R14ACL-walk]       D on a PATH (`safepath check D/sub`) -> 4, the reason names the extended ACL and the remedy.
# [R14ACL-attack]     end to end: whatever the helper answered, the foreign uid could not rename / plant inside a
#                     directory the helper CERTIFIED as this user's alone (round 13 certified it; it was planted).
# [R14ACL-default]    a 0770 private-group directory carrying ONLY a default ACL (no access ACL) -> no exemption (4):
#                     the conservative member (system.posix_acl_default counts like every system.* name).
# [R14ACL-cleared]    `setfacl -b` on the same directories -> 0 again (check / mkdir / write): the umask-002 exemption
#                     is kept for a directory WITHOUT an ACL (no false refusal; V4R13-1 stays closed).
# [R14ACL-masknow]    an ACL whose MASK grants no write (setfacl ... m::rx; mode 0750) -> 0, and the foreign uid
#                     really cannot create in it: an ACL that grants nothing is not refused.
# [R14ACL-sticky]     1770 + an ACL grant: trusted as a PARENT (`check D/x` -> 0: the sticky bit stops the foreign uid
#                     renaming our x -- shown by a REAL foreign `mv`), refused as a NAMESPACE (--exclusive -> 4).
# [R14ACL-inherit]    a directory with a DEFAULT ACL granting the foreign uid rwx (+ traverse): what THIS tool creates
#                     in it (open_owned_file 0600, safepath mkdir --exclusive 0700) gets the inherited entry MASKED by
#                     the creation mode -- the foreign uid cannot write the file nor create in the directory (real).
# [R14ACL-unreadable] SIMULATED: listxattr failing (ENOTSUP, EACCES, EIO) -> no exemption (FAIL CLOSED); ref None
#                     -> no exemption; a system.nfs4_acl / system.richacl name -> no exemption.
# [R14ACL-synthetic]  _trusted_ok / _owned_ok on synthetic stat results with _acl_free False: a private-group 0775 /
#                     0770 directory WITH an ACL is not trusted / not a namespace.
# [R14SGID-*]         setgid directories: 2770 in this user's private group -> a namespace (0); 2770 in a group with
#                     another member -> 4 (the group rule, unchanged by setgid).
# [R14HARDLINK]       fs.protected_hardlinks: the foreign uid cannot hard-link a 0600 file of ours (real `ln`).
# [R14LOCK-preplant]  V4R14-3: a lock directory others may create names in (1777) with the per-filesystem lock name
#                     PRE-PLANTED by the foreign uid -> the replay's locks are taken in $HOME/.cache/fc_baseline_replay/
#                     locks (proved, this user's alone), not BLIND 4 forever; the planted file untouched.
# [R14LOCK-own]       a lock directory of this user's alone is used as it is ($HOME/.cache not created).
# [R14LOCK-nohome]    the stated BOUNDARY: no home (round 15: no PASSWORD-DATABASE home, FAKE_PWHOME="" in the driver)
#                     + a pre-planted name -> BLIND 4 (never runs unlocked). Round 15: these rows give the driver
#                     FAKE_PWHOME (the password-database home stands in for $HOME, V4R15-1; test_fc_safepath_v4r15.sh).
# [R14LOCK-0640]      NIT-A (RV7-06): an old 0640 / 0660 lock file (group bits only) is REPLACED while held.
# [R14SAMPLE-wtroot-sticky] NIT-B (RV7-10): replay-sample with a --worktree-root of ours that is 1777 -> BLIND 4,
#                     nothing made in it (behavioural: the --exclusive proof of replay-sample's own site).
# [R14CENSUS-*]       the census self-test refuses each of the round-7 reviewer's 7 escapes (and the class members
#                     added with them) for the rule written for it; the round-13 census does NOT (RED, recorded in the
#                     evidence pack, not re-run here).
#
# Env: FC_BR_UNDER_TEST / FC_SUP_UNDER_TEST / FC_CENSUS_UNDER_TEST -- the files under test (the paired-mutation runner
#      points them at a replica); R14_ONLY -- space-separated row groups (ACL CLASS LOCK SH CENSUS).
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
tally() { # count the ok / NOT ok lines a python block printed; a missing end marker is a FAILED row
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
  [ -z "${R14_ONLY:-}" ] && return 0
  case " $R14_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}
NS=(unshare --map-users=auto --map-groups=auto --map-root-user)
FX() { "${NS[@]}" setpriv --reuid=1000 --regid=1000 --clear-groups "$@"; }   # the REAL foreign uid
# under /tmp itself (not $TMPDIR): the foreign uid must be able to TRAVERSE to the fixtures
WORK="$(mktemp -d /tmp/fc_r14.XXXXXX)"
chmod 711 "$WORK"
export FC_REPLAY_LOCK_DIR="$WORK/locks"
mkdir -p "$FC_REPLAY_LOCK_DIR"; chmod 700 "$FC_REPLAY_LOCK_DIR"
cleanup() {
  "${NS[@]}" rm -rf "$WORK" >/dev/null 2>&1
  chmod -R u+rwx "$WORK" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT
_FC_SUPERVISOR="$(dirname "$SCRIPT")/fc_supervisor.py"
eval "$(grep -m1 '^_fc_safe()' "$SCRIPT")"
# the foreign uid, as the KERNEL sees it (a file it creates) -- never assumed
mkdir "$WORK/probe"; chmod 1777 "$WORK/probe"
FUID=""
if FX sh -c ': >"$1/p"' sh "$WORK/probe" 2>/dev/null; then
  FUID="$(stat -c %u "$WORK/probe/p")"
  [ "$FUID" != "$(id -u)" ] || FUID=""
fi
HAVE_ACL=""
mkdir "$WORK/aclprobe"
if command -v setfacl >/dev/null 2>&1 && setfacl -m u:65534:r "$WORK/aclprobe" 2>/dev/null; then HAVE_ACL=1; fi
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
if want ACL; then
  if [ -z "$FUID" ] || [ -z "$HAVE_ACL" ]; then
    echo "SKIP [R14ACL-*] no subordinate uid ($FUID) or no POSIX ACL support ($HAVE_ACL) on this host -- not counted"
  else
    A="$WORK/acl"; mkdir "$A"; chmod 711 "$A"
    # ---- the fixture is a GENUINE grant (control both ways) ----
    mkdir "$A/noacl"; chmod 700 "$A/noacl"
    FX sh -c ': >"$1/x"' sh "$A/noacl" 2>/dev/null; rc0=$?
    mkdir "$A/D"; chmod 700 "$A/D"; mkdir "$A/D/sub"; chmod 700 "$A/D/sub"; setfacl -m "u:$FUID:rwx" "$A/D"
    FX sh -c ': >"$1/fx" && mv "$1/fx" "$1/fx2"' sh "$A/D" 2>/dev/null; rc1=$?
    if [ "$rc0" != 0 ] && [ "$rc1" = 0 ] && [ "$(stat -c %u "$A/D/fx2" 2>/dev/null)" = "$FUID" ]; then
      ok "[R14ACL-grant] fixture: the foreign uid $FUID CREATES and RENAMES in D after setfacl u:$FUID:rwx (mode $(stat -c %a "$A/D")), and cannot without the ACL"
    else
      bad "[R14ACL-grant] fixture not genuine: without ACL rc=$rc0 (want !=0), with ACL rc=$rc1 (want 0)"
    fi
    FX rm -f "$A/D/fx2" 2>/dev/null
    # ---- the helper refuses it, every entry point ----
    _fc_safe check --exclusive "$A/D" >/dev/null 2>"$A/c.err"; rc=$?
    [ "$rc" = 4 ] && ok "[R14ACL-check] safepath check --exclusive <a 0700 dir + ACL u:$FUID:rwx> -> 4 (round 13: 0)" \
      || bad "[R14ACL-check] rc=$rc (want 4) $(head -c 160 "$A/c.err")"
    _fc_safe mkdir --exclusive "$A/D/ns" >/dev/null 2>"$A/m.err"; rc=$?
    [ "$rc" = 4 ] && [ ! -e "$A/D/ns" ] && ok "[R14ACL-mkdir] safepath mkdir --exclusive D/ns -> 4, nothing made" \
      || bad "[R14ACL-mkdir] rc=$rc made=$([ -e "$A/D/ns" ] && echo yes || echo no) $(head -c 160 "$A/m.err")"
    _fc_safe write --text precious "$A/D" report >/dev/null 2>"$A/w.err"; rc=$?
    [ "$rc" = 4 ] && [ ! -e "$A/D/report" ] && ok "[R14ACL-write] safepath write --text precious D report -> 4, nothing written" \
      || bad "[R14ACL-write] rc=$rc written=$([ -e "$A/D/report" ] && echo yes || echo no) $(head -c 160 "$A/w.err")"
    # D on a path: refused by the trusted-parent rule, the reason names the ACL (only when the group is private:
    # otherwise the group rule already refuses it, with its own reason)
    if [ "$PRIV_OK" = yes ]; then
      _fc_safe check "$A/D/sub" >/dev/null 2>"$A/p.err"; rc=$?
      [ "$rc" = 4 ] && grep -q "extended ACL" "$A/p.err" && grep -q "setfacl -b" "$A/p.err" \
        && ok "[R14ACL-walk] D on a PATH (check D/sub) -> 4, the reason names the extended ACL and the remedy" \
        || bad "[R14ACL-walk] rc=$rc $(head -c 240 "$A/p.err")"
    else
      echo "SKIP [R14ACL-walk] this user's primary group has another member -- not counted"
    fi
    # ---- end to end: nothing the helper certified can be planted in ----
    R="$A/E"; mkdir "$R"; chmod 700 "$R"; setfacl -m "u:$FUID:rwx" "$R"
    cert=no
    if _fc_safe mkdir --exclusive "$R/ns" >/dev/null 2>&1 && _fc_safe write --text precious "$R" report >/dev/null 2>&1; then
      cert=yes
    fi
    FX sh -c 'mv "$1/report" "$1/report.stolen" 2>/dev/null; ln -s /etc/passwd "$1/report" 2>/dev/null; mv "$1/ns" "$1/ns.x" 2>/dev/null; mkdir "$1/ns" 2>/dev/null; :' sh "$R"
    planted="$(find "$R" -mindepth 1 -maxdepth 1 -uid "$FUID" -printf '%f ' 2>/dev/null)"
    if [ "$cert" = no ]; then
      ok "[R14ACL-attack] the helper did NOT certify the ACL-shared directory (mkdir --exclusive / write refused); the foreign uid's plants there [${planted}] were never trusted by this tool"
    else
      bad "[R14ACL-attack] the helper CERTIFIED an ACL-shared directory as this user's alone, and the foreign uid planted [${planted}] in it"
    fi
    # ---- default ACL only: the conservative member ----
    if [ "$PRIV_OK" = yes ]; then
      mkdir "$A/Dd"; chmod 770 "$A/Dd"; setfacl -d -m "u:$FUID:rwx" "$A/Dd"
      x="$(getfattr -d -m - "$A/Dd" 2>/dev/null | grep -c posix_acl_access)"
      _fc_safe check --exclusive "$A/Dd" >/dev/null 2>&1; rc=$?
      [ "$rc" = 4 ] && [ "$x" = 0 ] \
        && ok "[R14ACL-default] a 0770 private-group directory with ONLY a default ACL (no access ACL) -> 4 (no exemption: every system.* name counts)" \
        || bad "[R14ACL-default] rc=$rc access-acl-names=$x (want 4, 0)"
      # ---- cleared: the exemption comes back (V4R13-1 stays closed) ----
      setfacl -b "$A/Dd"; chmod 770 "$A/Dd"
      setfacl -b "$A/D"; chmod 770 "$A/D"
      _fc_safe check --exclusive "$A/Dd" >/dev/null 2>&1; r1=$?
      _fc_safe mkdir --exclusive "$A/D/ns2" >/dev/null 2>&1; r2=$?
      _fc_safe write --text t "$A/D" report2 >/dev/null 2>&1; r3=$?
      _fc_safe check "$A/D/sub" >/dev/null 2>&1; r4=$?
      [ "$r1$r2$r3$r4" = 0000 ] && [ -d "$A/D/ns2" ] && [ -f "$A/D/report2" ] \
        && ok "[R14ACL-cleared] after setfacl -b the same 0770 private-group directories are accepted again (check --exclusive / mkdir --exclusive / write / as a parent: 0 0 0 0)" \
        || bad "[R14ACL-cleared] rc=$r1 $r2 $r3 $r4 (want 0 0 0 0)"
    else
      echo "SKIP [R14ACL-default / R14ACL-cleared] this user's primary group has another member -- not counted"
    fi
    # ---- an ACL whose mask grants no write: not refused (no false positive) ----
    mkdir "$A/M"; chmod 750 "$A/M"; setfacl -m "u:$FUID:rwx,m::rx" "$A/M"
    FX sh -c ': >"$1/fx"' sh "$A/M" 2>/dev/null; rcf=$?
    _fc_safe check --exclusive "$A/M" >/dev/null 2>&1; rc=$?
    [ "$rc" = 0 ] && [ "$rcf" != 0 ] && [ "$(stat -c %a "$A/M")" = 750 ] \
      && ok "[R14ACL-masknow] an ACL whose mask grants no write (mode 750): the foreign uid really cannot create in it, and check --exclusive -> 0" \
      || bad "[R14ACL-masknow] check=$rc (want 0) foreign-create=$rcf (want !=0) mode=$(stat -c %a "$A/M")"
    # ---- sticky + ACL: a trusted PARENT (the sticky bit, shown by a real foreign mv), never a namespace ----
    mkdir "$A/S"; chmod 1770 "$A/S"; mkdir "$A/S/x"; chmod 700 "$A/S/x"; setfacl -m "u:$FUID:rwx" "$A/S"
    FX sh -c ': >"$1/fz"' sh "$A/S" 2>/dev/null; rcc=$?
    FX sh -c 'mv "$1/x" "$1/x.away"' sh "$A/S" 2>/dev/null; rcm=$?
    _fc_safe check "$A/S/x" >/dev/null 2>&1; r1=$?
    _fc_safe check --exclusive "$A/S" >/dev/null 2>&1; r2=$?
    [ "$rcc" = 0 ] && [ "$rcm" != 0 ] && [ -d "$A/S/x" ] && [ "$r1" = 0 ] && [ "$r2" = 4 ] \
      && ok "[R14ACL-sticky] 1770 + ACL grant: the foreign uid CAN create (rc $rcc) but CANNOT rename our x (rc $rcm) -- so x is trusted through it (check -> 0) and S is no namespace (--exclusive -> 4)" \
      || bad "[R14ACL-sticky] foreign create=$rcc (want 0) rename=$rcm (want !=0) check=$r1 (want 0) --exclusive=$r2 (want 4)"
    FX rm -f "$A/S/fz" 2>/dev/null
    # ---- inherited from a default ACL: masked by the creation mode of what THIS tool makes ----
    mkdir "$A/I"; chmod 700 "$A/I"; setfacl -m "u:$FUID:x" "$A/I"; setfacl -d -m "u:$FUID:rwx" "$A/I"
    python3 -I - "$SUP" "$A/I" <<'PY' 2>"$A/i.err"
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("fcsup", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
fd = m.open_owned_file(os.path.join(sys.argv[2], "made"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode=0o600)
os.write(fd, b"ours"); os.close(fd)
PY
    rcp=$?
    _fc_safe mkdir --exclusive "$A/I/nsd" >/dev/null 2>&1; rcd=$?
    FX sh -c 'printf x >>"$1/made"' sh "$A/I" 2>/dev/null; fw=$?
    FX sh -c ': >"$1/nsd/fx"' sh "$A/I" 2>/dev/null; fc=$?
    inh="$(getfacl -p "$A/I/made" 2>/dev/null | grep -c "^user:$FUID:rwx")"
    [ "$rcp" = 0 ] && [ "$rcd" = 0 ] && [ "$fw" != 0 ] && [ "$fc" != 0 ] && [ "$inh" = 1 ] && [ "$(cat "$A/I/made")" = ours ] \
      && ok "[R14ACL-inherit] in a directory with a default ACL u:$FUID:rwx, the file (0600) and the namespace (0700) THIS tool makes inherit the entry MASKED: the foreign uid cannot write the file nor create in the namespace (both refused, real)" \
      || bad "[R14ACL-inherit] open=$rcp mkdir=$rcd (want 0 0) foreign write=$fw create=$fc (want !=0 !=0) inherited-entry=$inh content=$(cat "$A/I/made" 2>/dev/null) $(head -c 160 "$A/i.err")"
  fi
fi

# =============================================================================
if want CLASS; then
  C="$WORK/class"; mkdir "$C"; chmod 711 "$C"
  cat >"$WORK/class.py" <<'PY'
import importlib.util, os, sys, errno, stat as st_
spec = importlib.util.spec_from_file_location("fcsup", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
C = sys.argv[2]
euid, egid = os.geteuid(), os.getegid()
def ok(t): print("ok " + t)
def bad(t): print("NOT ok " + t)
def fake(mode, uid, gid):
    return os.stat_result((mode, 1, 1, 1, uid, gid, 0, 0, 0, 0))
# ---- [R14ACL-synthetic] ----
real_gp, real_af = m._group_private, m._acl_free
try:
    m._group_private = lambda gid: True
    m._acl_free = lambda ref: False                    # the directory CARRIES an ACL (or it cannot be read)
    for tid, mode, want in (("own775", 0o40775, False), ("own770", 0o40770, False), ("own755", 0o40755, True),
                            ("own1775", 0o41775, True)):
        got = m._trusted_ok(fake(mode, euid, egid), 7)
        (ok if got == want else bad)("[R14ACL-synthetic-trust-%s] _trusted_ok(mode %o, ours, a PRIVATE group, WITH an "
                                     "ACL) = %s (want %s)" % (tid, mode & 0o7777, got, want))
    for tid, mode, want in (("own770", 0o40770, False), ("own750", 0o40750, True)):
        got = m._owned_ok(fake(mode, euid, egid), st_.S_ISDIR, m.DIR_FORBID, 7)
        (ok if got == want else bad)("[R14ACL-synthetic-owned-%s] _owned_ok(mode %o, ours, a PRIVATE group, WITH an "
                                     "ACL) = %s (want %s)" % (tid, mode & 0o7777, got, want))
    m._acl_free = lambda ref: True
    got = m._owned_ok(fake(0o40770, euid, egid), st_.S_ISDIR, m.DIR_FORBID, 7)
    (ok if got is True else bad)("[R14ACL-synthetic-owned-noacl] control: the same 0770 WITHOUT an ACL = %s (want True)" % got)
finally:
    m._group_private, m._acl_free = real_gp, real_af
# ---- [R14ACL-unreadable] SIMULATED kernel answers (the host cannot be made to fail listxattr on demand) ----
d = os.path.join(C, "u"); os.mkdir(d, 0o700)
fd = os.open(d, os.O_PATH)
real_lx = os.listxattr
try:
    (ok if m._acl_free(fd) is True else bad)("[R14ACL-unreadable-control] a real directory without an ACL: _acl_free = True")
    (ok if m._acl_free(None) is False else bad)("[R14ACL-unreadable-none] ref None -> _acl_free = False (no exemption)")
    for code in (errno.ENOTSUP, errno.EACCES, errno.EIO, errno.EBADF):
        def lx(*a, _c=code, **k):
            raise OSError(_c, os.strerror(_c))
        os.listxattr = lx
        got = m._acl_free(fd)
        (ok if got is False else bad)("[R14ACL-unreadable-%s] SIMULATED listxattr -> %s: _acl_free = %s (want False: "
                                      "FAIL CLOSED)" % (errno.errorcode[code], errno.errorcode[code], got))
    for names in (["system.nfs4_acl"], ["system.richacl"], ["security.selinux", "system.posix_acl_default"],
                  ["system.cifs_acl"]):
        os.listxattr = lambda *a, _n=names, **k: list(_n)
        got = m._acl_free(fd)
        (ok if got is False else bad)("[R14ACL-names-%s] SIMULATED listxattr -> %s: _acl_free = %s (want False)"
                                      % (names[-1].split(".")[1], names, got))
    os.listxattr = lambda *a, **k: ["security.selinux", "user.note"]
    got = m._acl_free(fd)
    (ok if got is True else bad)("[R14ACL-names-nonsystem] SIMULATED listxattr -> security.selinux, user.note "
                                 "(grant nothing): _acl_free = %s (want True)" % got)
finally:
    os.listxattr = real_lx
    os.close(fd)
print("R14CLASS-ran")
PY
  tally R14CLASS-ran < <(python3 -I "$WORK/class.py" "$SUP" "$C" 2>&1)
  # ---- setgid directories ----
  if [ "$PRIV_OK" = yes ]; then
    mkdir "$C/g1"; chmod 2770 "$C/g1"
    _fc_safe check --exclusive "$C/g1" >/dev/null 2>&1; rc=$?
    [ "$rc" = 0 ] && ok "[R14SGID-private] a 2770 directory in this user's private group -> a namespace (0)" \
      || bad "[R14SGID-private] rc=$rc (want 0)"
  else
    echo "SKIP [R14SGID-private] this user's primary group has another member -- not counted"
  fi
  if [ -n "$SHARED_GID" ]; then
    mkdir "$C/g2"; chgrp "$SHARED_GID" "$C/g2"; chmod 2770 "$C/g2"
    _fc_safe check --exclusive "$C/g2" >/dev/null 2>&1; rc=$?
    [ "$rc" = 4 ] && ok "[R14SGID-shared] a 2770 directory in a group with another member ($SHARED_GID) -> 4" \
      || bad "[R14SGID-shared] rc=$rc (want 4)"
  else
    echo "SKIP [R14SGID-shared] no shared group -- not counted"
  fi
  # ---- hard links: the foreign uid cannot link a 0600 file of ours ----
  if [ -n "$FUID" ]; then
    mkdir "$C/h"; chmod 711 "$C/h"; echo secret >"$C/h/f"; chmod 600 "$C/h/f"
    mkdir "$C/drop"; chmod 1777 "$C/drop"
    FX sh -c 'ln "$1" "$2/l"' sh "$C/h/f" "$C/drop" 2>/dev/null; rc=$?
    FX sh -c ': >"$1/ctl"' sh "$C/drop" 2>/dev/null; rcc=$?
    [ "$rc" != 0 ] && [ ! -e "$C/drop/l" ] && [ "$rcc" = 0 ] \
      && ok "[R14HARDLINK] the foreign uid cannot hard-link a 0600 file of ours (fs.protected_hardlinks=$(cat /proc/sys/fs/protected_hardlinks)); control: it can create in the drop directory" \
      || bad "[R14HARDLINK] ln rc=$rc (want !=0) control rc=$rcc (want 0)"
  else
    echo "SKIP [R14HARDLINK] no subordinate uid -- not counted"
  fi
fi

# =============================================================================
if want LOCK; then
  L="$WORK/lock"; mkdir "$L"; chmod 711 "$L"
  cat >"$WORK/lock.py" <<'PY'
import importlib.util, os, sys, types, fcntl
spec = importlib.util.spec_from_file_location("fcsup", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
mode, lock_dir, fspath = sys.argv[2], sys.argv[3], sys.argv[4]
m.say = lambda msg: sys.stderr.write("say: %s\n" % msg)
if "FAKE_PWHOME" in os.environ:          # round 15 (V4R15-1): the home is read from the PASSWORD DATABASE; this driver
    m._passwd_home = lambda: os.environ["FAKE_PWHOME"]   # seam stands in for it (the supervisor has no env input)
if mode == "take":
    try:
        fds = m._take_locks(types.SimpleNamespace(lock=[], lock_fs=[fspath], lock_dir=lock_dir))
    except SystemExit as e:
        print("EXIT %s" % e.code)
        sys.exit(0)
    for fd in fds:
        print("LOCKED %s" % os.readlink("/proc/self/fd/%d" % fd))
elif mode == "one":
    fd = m._lock_one(lock_dir, "t")
    st = os.fstat(fd)
    print("MODE %o INO %d" % (st.st_mode & 0o777, st.st_ino))
PY
  dev="$(stat -c %d "$WORK")"
  lname="fc_baseline_replay.fs-$dev.lock"
  if [ -n "$FUID" ]; then
    SH1="$L/shared"; mkdir "$SH1"; chmod 1777 "$SH1"
    FX sh -c ': >"$1/$2"' sh "$SH1" "$lname" 2>/dev/null
    H="$L/home"; mkdir "$H"; chmod 700 "$H"
    out="$(HOME="$H" FAKE_PWHOME="$H" python3 -I "$WORK/lock.py" "$SUP" take "$SH1" "$WORK" 2>"$L/p.err")"
    want_path="$H/.cache/fc_baseline_replay/locks/$lname"
    [ "$(stat -c %u "$SH1/$lname" 2>/dev/null)" = "$FUID" ] && grep -qx "LOCKED $want_path" <<<"$out" \
      && [ "$(stat -c '%u %a' "$want_path")" = "$(id -u) 600" ] \
      && ok "[R14LOCK-preplant] the per-filesystem lock name PRE-PLANTED by uid $FUID in a 1777 lock directory: the lock is taken in \$HOME/.cache/fc_baseline_replay/locks (ours, 0600), not BLIND 4; the planted file untouched" \
      || bad "[R14LOCK-preplant] out=[$out] planted-owner=$(stat -c %u "$SH1/$lname" 2>/dev/null) $(head -c 200 "$L/p.err")"
    out="$(env -u HOME FAKE_PWHOME= python3 -I "$WORK/lock.py" "$SUP" take "$SH1" "$WORK" 2>"$L/n.err")"
    [ "$out" = "EXIT 4" ] && grep -q "cannot open the replay lock file" "$L/n.err" \
      && ok "[R14LOCK-nohome] the stated boundary: no \$HOME and the name pre-planted -> BLIND 4 (refused, never run unlocked)" \
      || bad "[R14LOCK-nohome] out=[$out] $(head -c 200 "$L/n.err")"
  else
    echo "SKIP [R14LOCK-preplant / R14LOCK-nohome] no subordinate uid -- not counted"
  fi
  OWN="$L/own"; mkdir "$OWN"; chmod 700 "$OWN"; H2="$L/home2"; mkdir "$H2"; chmod 700 "$H2"
  out="$(HOME="$H2" FAKE_PWHOME="$H2" python3 -I "$WORK/lock.py" "$SUP" take "$OWN" "$WORK" 2>"$L/o.err")"
  grep -qx "LOCKED $OWN/$lname" <<<"$out" && [ ! -e "$H2/.cache" ] \
    && ok "[R14LOCK-own] a lock directory of this user's alone is used as it is (\$HOME/.cache not created)" \
    || bad "[R14LOCK-own] out=[$out] cache=$([ -e "$H2/.cache" ] && echo made || echo no) $(head -c 200 "$L/o.err")"
  for md in 640 660; do
    f="$L/old$md.lock"; : >"$f"; chmod "$md" "$f"; ino="$(stat -c %i "$f")"
    out="$(python3 -I "$WORK/lock.py" "$SUP" one "$f" "$WORK" 2>&1)"
    st="$(stat -c '%a %i' "$f")"
    [ "${st% *}" = 600 ] && [ "${st#* }" != "$ino" ] && grep -q "^MODE 600 " <<<"$out" \
      && ok "[R14LOCK-0$md] an old 0$md lock file (group bits only) is REPLACED while held: now 0600, a new inode (NIT-A, RV7-06)" \
      || bad "[R14LOCK-0$md] after: mode/ino=$st (old ino $ino) out=[$out]"
  done
fi

# =============================================================================
g() { git -c user.email=t@t.t -c user.name=t "$@"; }
mk_repo() { mkdir -p "$1"; g init -q "$1"; echo hello >"$1/f.txt"; g -C "$1" add f.txt; g -C "$1" commit -q -m "base commit"; }
if want SH; then
  S="$WORK/sh"; mkdir -p "$S"; chmod 711 "$S"
  REPO="$S/repo"; mk_repo "$REPO"
  WTS="$S/wts"; mkdir "$WTS"; chmod 1777 "$WTS"
  printf '{"items": []}\n' >"$S/sample.json"
  bash "$SCRIPT" replay-sample --sample "$S/sample.json" --repo-root "$REPO" --worktree-root "$WTS" --min-free-kb 0 --min-free-kb-objects 0 \
    --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/s.json" >/dev/null 2>"$S/s.err"; rc=$?
  [ "$rc" = 4 ] && [ -z "$(ls -A "$WTS")" ] && [ ! -e "$S/s.json" ] && grep -q "trusted-parent rule" "$S/s.err" \
    && ok "[R14SAMPLE-wtroot-sticky] replay-sample with a --worktree-root of ours that is 1777 -> BLIND 4, nothing made in it (NIT-B: behavioural)" \
    || bad "[R14SAMPLE-wtroot-sticky] rc=$rc made=[$(ls -A "$WTS" | tr '\n' ' ')] $(head -c 240 "$S/s.err")"
fi

# =============================================================================
if want CENSUS; then
  out="$(FC_SUP_UNDER_TEST="$SUP" FC_BR_UNDER_TEST="$SCRIPT" python3 "$CENSUS" --self-test 2>&1)"; rc=$?
  n="$(sed -n 's/^SELFTEST cases=\([0-9]*\) failed=\([0-9]*\)$/\1 \2/p' <<<"$out")"
  [ "$rc" = 0 ] && [ "${n% *}" -ge 132 ] 2>/dev/null && [ "${n#* }" = 0 ] \
    && ok "[R14CENSUS-self] the census self-test: cases/failed = $n (>= 132 cases)" \
    || bad "[R14CENSUS-self] rc=$rc cases/failed=$n $(grep -m3 '^NOT-ok' <<<"$out" | tr '\n' ' ' | cut -c1-300)"
  for needle in 'py REFUSES   os.unlink.__call__(p)' 'py REFUSES   type(os).__getattribute__(os, "unlink")(p)' \
                'py REFUSES   select.__builtins__["open"](p, "w")' 'py REFUSES   argparse.FileType("w")(p)' \
                'sh REFUSES   printf -v _wr %s /etc; rm -rf "$_wr/x"' \
                'sh REFUSES   local -n _rvref=_wr; _rvref=/etc; rm -rf "$_wr"' \
                'sh REFUSES   unset _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"'; do
    if grep -qxF "ok $needle" <<<"$out"; then
      ok "[R14CENSUS-escape] refused for its own rule: ${needle#* REFUSES   }"
    else
      bad "[R14CENSUS-escape] NOT refused (or not by its rule): ${needle#* REFUSES   }"
    fi
  done
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
