#!/usr/bin/env bash
# fastcycle-timeout-s: 900
# =============================================================================
# test_fc_safepath_v4r15.sh -- ATM-1220 r9 (fixer round 15; independent review round 1 of the fresh budget:
# qa-results/fastcycle/reviews/atm1220_r8_review_20261014.md, NO-GO, 3 MINOR + 2 NIT).
#
# [R15LOCK-home-env]   V4R15-1 (source-defect): two _take_locks of the SAME user on the SAME filesystem, lock dir a
#                      1777 directory (the /tmp default class), whose environment $HOME DIFFERS: the second MUST be
#                      refused (BLIND 4 "another ... replay is running") -- the lock lives under the PASSWORD-DATABASE
#                      home, never $HOME. RED on 655ff86 (both LOCKED, in two different directories).
# [R15LOCK-home-same]  control: the same with the SAME $HOME -> the second refused (holds on 655ff86 too).
# [R15LOCK-pwhome]     _passwd_home() == the password database's home for this uid, whatever $HOME says (unset,
#                      relative, another directory).
# [R15LOCK-nopasswd]   REAL: a uid with no password-database entry -> _passwd_home() == ''. (Inside the user namespace
#                      FX uses, uid 1000 IS this user's passwd entry; the row uses namespace uid 54321, which has none --
#                      checked with getent, never assumed.)
# [R15LOCK-cache-shared] RV8-02: <passwd home>/.cache/fc_baseline_replay/locks pre-made 1777 -> REFUSED (BLIND 4),
#                      never used (no lock file made in it).
# [R15LOCK-lockdir-sharedgroup] RV8-03: a lock directory of ours, 1770 (trusted as a PARENT through the sticky bit,
#                      so the walk accepts it), in a group with ANOTHER member -> not ours alone (a member may create
#                      the predictable name first): the lock is taken in <passwd home>/.cache/..., not in it.
# [R15LOCK-lockdir-privgroup] control (V4R13-1 parity): a 0770 lock directory in this user's PRIVATE group, no ACL ->
#                      used as it is; a 1770 one WITH an ACL grant -> redirected (the ref threading at
#                      _private_lock_dir). (A 0770 group-shared or ACL directory WITHOUT the sticky bit is refused
#                      earlier, by the trusted-parent rule itself: BLIND 4.)
# [R15EXCL-mkdir-0775] RV8-05: `safepath mkdir --exclusive D` on an EXISTING 0775 private-group directory -> 0; the
#                      same directory with an ACL -> 4.
# [R15EXCL-mkdtemp-0775] RV8-04: `safepath mkdtemp --exclusive-parent D p.` on an EXISTING 0775 private-group
#                      directory -> 0 (a 0700 directory made in it); with an ACL -> 4, nothing made.
# [R15CENSUS-self]     the census self-test (>= its current case count, 0 failed).
# [R15CENSUS-rv8-sh]   every shell needle of the round-8 reviewer's census probe (rv8_review/cen/sh_needles.txt +
#                      n2.txt), VERBATIM, is refused by the self-test (V4R15-2, RV8-07); the class-closing rules:
#                      a NAME read through the lexer's quote removal, a non-literal NAME in any name position
#                      refused, every assignment form of a proved variable refused, and every SUFFIXED use of a proved
#                      variable must be ${V:?} (an empty value can then never become "/suffix").
# [R15CENSUS-rv8-py]   every Python needle of the reviewer's probe, VERBATIM, has the verdict the census states for it.
# [R15CENSUS-heredoc]  a here-document whose delimiter is UNQUOTED is expanded by the shell: `${_wr:=/etc}` in its body
#                      is refused AT ITS LINE; the same text under a QUOTED delimiter is data (not refused) -- control.
# [R15CENSUS-param-guard] the ${V:?} rule also binds a param-tagged operand: the real script with its ledger mktemp
#                      reverted to "$_FC_TMPDIR/ledger..." -> a VIOLATION at that line (the unmodified script: 0).
# [R15LOCK-noxdg]      the V4R15-1 CLASS member $XDG_RUNTIME_DIR (cron does not set it): a real `replay-sample` with
#                      FC_REPLAY_LOCK_DIR unset and XDG_RUNTIME_DIR = a private directory of ours takes its per-
#                      filesystem lock under the password-database home, NOT in $XDG_RUNTIME_DIR (round 14 did).
#
# Env: FC_BR_UNDER_TEST / FC_SUP_UNDER_TEST / FC_CENSUS_UNDER_TEST -- the files under test (the paired-mutation runner
#      points them at a replica); R15_ONLY -- space-separated row groups (LOCK EXCL CENSUS SH).
# Exit: 0 every row held; 1 otherwise. A row that needs a host fact this host lacks prints SKIP (not counted).
# NOTE: the LOCK rows that exercise the real password-database home take a lock file under that home's
#       .cache/fc_baseline_replay/locks (that is the behaviour under test); the lock is released at the row's end.
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
want() {
  [ -z "${R15_ONLY:-}" ] && return 0
  case " $R15_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}
NS=(unshare --map-users=auto --map-groups=auto --map-root-user)
FX() { "${NS[@]}" setpriv --reuid=1000 --regid=1000 --clear-groups "$@"; }   # the REAL foreign uid
# under /tmp itself (not $TMPDIR): the foreign uid must be able to TRAVERSE to the fixtures
WORK="$(mktemp -d /tmp/fc_r15.XXXXXX)"
chmod 711 "$WORK"
export FC_REPLAY_LOCK_DIR="$WORK/locks"
mkdir -p "$FC_REPLAY_LOCK_DIR"; chmod 700 "$FC_REPLAY_LOCK_DIR"
HOLD_PID=""
cleanup() {
  [ -n "$HOLD_PID" ] && kill "$HOLD_PID" 2>/dev/null
  "${NS[@]}" rm -rf "$WORK" >/dev/null 2>&1
  chmod -R u+rwx "$WORK" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT
_FC_SUPERVISOR="$(dirname "$SCRIPT")/fc_supervisor.py"
eval "$(grep -m1 '^_fc_safe()' "$SCRIPT")"
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
PWHOME="$(getent passwd "$(id -u)" | cut -d: -f6)"

# the lock driver: take (print LOCKED <path> / EXIT <code>), hold (take, print, then wait for stdin EOF), pwhome.
# FAKE_PWHOME (only where a row says so) replaces the PASSWORD-DATABASE lookup -- a test seam set in THIS driver, never
# read by the supervisor itself (it has no environment input for its home: V4R15-1).
cat >"$WORK/lock.py" <<'PY'
import importlib.util, os, sys, types
spec = importlib.util.spec_from_file_location("fcsup", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
mode = sys.argv[2]
m.say = lambda msg: sys.stderr.write("say: %s\n" % msg)
if "FAKE_PWHOME" in os.environ:
    m._passwd_home = lambda: os.environ["FAKE_PWHOME"]
if mode == "pwhome":
    f = getattr(m, "_passwd_home", None)
    print("PWHOME %s" % (f() if f else "<absent>"))
    sys.exit(0)
lock_dir, fspath = sys.argv[3], sys.argv[4]
try:
    fds = m._take_locks(types.SimpleNamespace(lock=[], lock_fs=[fspath], lock_dir=lock_dir))
except SystemExit as e:
    print("EXIT %s" % e.code, flush=True)
    sys.exit(0)
for fd in fds:
    print("LOCKED %s" % os.readlink("/proc/self/fd/%d" % fd), flush=True)
if mode == "hold":
    sys.stdin.read()
PY
dev="$(stat -c %d "$WORK")"
lname="fc_baseline_replay.fs-$dev.lock"

# holds the lock in the background with HOME=$1 until hold_stop; returns 0 once it is held
hold_start() {
  rm -f "$WORK/gate" "$WORK/h.out"; mkfifo "$WORK/gate"
  HOME="$1" python3 -I "$WORK/lock.py" "$SUP" hold "$2" "$WORK" <"$WORK/gate" >"$WORK/h.out" 2>"$WORK/h.err" &
  HOLD_PID=$!
  exec 7>"$WORK/gate"
  local _i
  for _i in $(seq 1 100); do
    grep -q "^LOCKED\|^EXIT" "$WORK/h.out" 2>/dev/null && break
    sleep 0.1
  done
  grep -q "^LOCKED" "$WORK/h.out"
}
hold_stop() { exec 7>&-; wait "$HOLD_PID" 2>/dev/null; HOLD_PID=""; }

# =============================================================================
if want LOCK; then
  L="$WORK/lock"; mkdir "$L"; chmod 711 "$L"
  SH1="$L/shared"; mkdir "$SH1"; chmod 1777 "$SH1"
  H1="$L/h1"; H2="$L/h2"; mkdir "$H1" "$H2"; chmod 700 "$H1" "$H2"
  # ---- V4R15-1: different $HOME, same user, same filesystem ----
  if hold_start "$H1" "$SH1"; then
    first="$(cat "$WORK/h.out")"
    out="$(HOME="$H2" python3 -I "$WORK/lock.py" "$SUP" take "$SH1" "$WORK" 2>"$L/e2.err")"
    hold_stop
    [ "$out" = "EXIT 4" ] && grep -q "another baseline_replay replay is running" "$L/e2.err" \
      && ok "[R15LOCK-home-env] two replays of uid $(id -u) on one filesystem, \$HOME=$H1 vs \$HOME=$H2: the second is REFUSED (BLIND 4) -- one lock file per user and filesystem (first: $first)" \
      || bad "[R15LOCK-home-env] first=[$first] second=[$out] (want EXIT 4) $(head -c 200 "$L/e2.err")"
  else
    hold_stop
    bad "[R15LOCK-home-env] the first replay did not take its lock: $(cat "$WORK/h.out" "$WORK/h.err" | head -c 300)"
  fi
  if hold_start "$H1" "$SH1"; then
    out="$(HOME="$H1" python3 -I "$WORK/lock.py" "$SUP" take "$SH1" "$WORK" 2>"$L/e3.err")"
    hold_stop
    [ "$out" = "EXIT 4" ] && grep -q "another baseline_replay replay is running" "$L/e3.err" \
      && ok "[R15LOCK-home-same] control: the same \$HOME -> the second is REFUSED (BLIND 4)" \
      || bad "[R15LOCK-home-same] second=[$out] (want EXIT 4) $(head -c 200 "$L/e3.err")"
  else
    hold_stop
    bad "[R15LOCK-home-same] the first replay did not take its lock: $(cat "$WORK/h.out" "$WORK/h.err" | head -c 300)"
  fi
  # ---- the lookup itself: the password database, never $HOME ----
  a="$(HOME="$H2" python3 -I "$WORK/lock.py" "$SUP" pwhome 2>&1)"
  b="$(env -u HOME python3 -I "$WORK/lock.py" "$SUP" pwhome 2>&1)"
  c="$(HOME=relative python3 -I "$WORK/lock.py" "$SUP" pwhome 2>&1)"
  [ -n "$PWHOME" ] && [ "$a" = "PWHOME $PWHOME" ] && [ "$b" = "$a" ] && [ "$c" = "$a" ] \
    && ok "[R15LOCK-pwhome] _passwd_home() = $PWHOME (getent passwd) with \$HOME=another dir / unset / relative" \
    || bad "[R15LOCK-pwhome] getent=[$PWHOME] HOME=H2:[$a] unset:[$b] relative:[$c]"
  if [ -n "$FUID" ]; then
    cp "$SUP" "$WORK/sup_copy.py"; chmod 644 "$WORK/sup_copy.py" "$WORK/lock.py"
    out="$("${NS[@]}" setpriv --reuid=54321 --regid=54321 --clear-groups env -u FAKE_PWHOME HOME=/ \
      python3 -I "$WORK/lock.py" "$WORK/sup_copy.py" pwhome 2>&1)"
    hasent="$(getent passwd 54321 >/dev/null && echo yes || echo no)"
    [ "$hasent" = no ] && [ "$out" = "PWHOME " ] \
      && ok "[R15LOCK-nopasswd] REAL: a uid with no password-database entry (namespace uid 54321) -> _passwd_home() = '' (the stated boundary branch)" \
      || bad "[R15LOCK-nopasswd] entry=$hasent out=[$out]"
  else
    echo "SKIP [R15LOCK-nopasswd] no subordinate uid -- not counted"
  fi
  # ---- RV8-02: a pre-made SHARED cache lock directory is never used ----
  H3="$L/h3"; mkdir -p "$H3/.cache/fc_baseline_replay/locks"; chmod 700 "$H3" "$H3/.cache" "$H3/.cache/fc_baseline_replay"
  chmod 1777 "$H3/.cache/fc_baseline_replay/locks"
  out="$(FAKE_PWHOME="$H3" python3 -I "$WORK/lock.py" "$SUP" take "$SH1" "$WORK" 2>"$L/c.err")"
  made="$(ls -A "$H3/.cache/fc_baseline_replay/locks")"
  [ "$out" = "EXIT 4" ] && [ -z "$made" ] && grep -q "per-user lock directory" "$L/c.err" \
    && ok "[R15LOCK-cache-shared] RV8-02: <home>/.cache/fc_baseline_replay/locks pre-made 1777 -> REFUSED (BLIND 4), nothing made in it" \
    || bad "[R15LOCK-cache-shared] out=[$out] made=[$made] $(head -c 200 "$L/c.err")"
  # ---- RV8-03: a group-shared 0770 lock directory of ours is not ours alone ----
  H4="$L/h4"; mkdir "$H4"; chmod 700 "$H4"
  if [ -n "$SHARED_GID" ]; then
    GS="$L/gshared"; mkdir "$GS"; chgrp "$SHARED_GID" "$GS"; chmod 1770 "$GS"
    out="$(FAKE_PWHOME="$H4" python3 -I "$WORK/lock.py" "$SUP" take "$GS" "$WORK" 2>"$L/g.err")"
    [ "$out" = "LOCKED $H4/.cache/fc_baseline_replay/locks/$lname" ] && [ ! -e "$GS/$lname" ] \
      && ok "[R15LOCK-lockdir-sharedgroup] RV8-03: a 1770 lock directory of ours in group $SHARED_GID (another member) -> redirected to <home>/.cache/..., nothing made in it" \
      || bad "[R15LOCK-lockdir-sharedgroup] out=[$out] in-shared=$([ -e "$GS/$lname" ] && echo yes || echo no) $(head -c 200 "$L/g.err")"
  else
    echo "SKIP [R15LOCK-lockdir-sharedgroup] no shared group -- not counted"
  fi
  if [ "$PRIV_OK" = yes ]; then
    H5="$L/h5"; mkdir "$H5"; chmod 700 "$H5"
    GP="$L/gpriv"; mkdir "$GP"; chmod 770 "$GP"
    out="$(FAKE_PWHOME="$H5" python3 -I "$WORK/lock.py" "$SUP" take "$GP" "$WORK" 2>"$L/p.err")"
    if [ "$out" = "LOCKED $GP/$lname" ] && [ ! -e "$H5/.cache" ]; then
      r1=ok
    else
      r1="out=[$out] cache=$([ -e "$H5/.cache" ] && echo made || echo no)"
    fi
    if [ -n "$HAVE_ACL" ]; then
      GA="$L/gacl"; mkdir "$GA"; chmod 1700 "$GA"; setfacl -m u:65534:rwx "$GA"
      out="$(FAKE_PWHOME="$H5" python3 -I "$WORK/lock.py" "$SUP" take "$GA" "$WORK" 2>"$L/a.err")"
      if [ "$out" = "LOCKED $H5/.cache/fc_baseline_replay/locks/$lname" ] && [ ! -e "$GA/$lname" ]; then
        r2=ok
      else
        r2="acl: out=[$out] $(head -c 160 "$L/a.err")"
      fi
    else
      r2=ok; echo "SKIP [R15LOCK-lockdir-privgroup ACL half] no POSIX ACL support -- not counted"
    fi
    [ "$r1" = ok ] && [ "$r2" = ok ] \
      && ok "[R15LOCK-lockdir-privgroup] a 0770 lock directory in this user's PRIVATE group (no ACL) is used as it is; a sticky one WITH an ACL grant (mode $(stat -c %a "$L/gacl" 2>/dev/null)) is redirected to <home>/.cache/..." \
      || bad "[R15LOCK-lockdir-privgroup] $r1 / $r2"
  else
    echo "SKIP [R15LOCK-lockdir-privgroup] this user's primary group has another member -- not counted"
  fi
fi

# =============================================================================
if want EXCL; then
  if [ "$PRIV_OK" = yes ]; then
    E="$WORK/excl"; mkdir "$E"; chmod 711 "$E"
    mkdir "$E/P"; chmod 775 "$E/P"
    _fc_safe mkdir --exclusive "$E/P" >"$E/m.out" 2>"$E/m.err"; r1=$?
    _fc_safe mkdtemp --exclusive-parent "$E/P" p. >"$E/t.out" 2>"$E/t.err"; r2=$?
    t="$(cat "$E/t.out")"
    [ "$r1" = 0 ] && [ "$(cat "$E/m.out")" = "$E/P" ] \
      && ok "[R15EXCL-mkdir-0775] RV8-05: safepath mkdir --exclusive on an EXISTING 0775 directory in this user's private group -> 0 (no umask-002 false refusal at ensure_dir's exclusive check)" \
      || bad "[R15EXCL-mkdir-0775] rc=$r1 (want 0) $(head -c 200 "$E/m.err")"
    [ "$r2" = 0 ] && [ -d "$t" ] && [ "$(stat -c %a "$t")" = 700 ] && [ "${t%/*}" = "$E/P" ] \
      && ok "[R15EXCL-mkdtemp-0775] RV8-04: safepath mkdtemp --exclusive-parent on an EXISTING 0775 private-group directory -> 0, a 0700 directory made in it" \
      || bad "[R15EXCL-mkdtemp-0775] rc=$r2 (want 0) made=[$t] $(head -c 200 "$E/t.err")"
    if [ -n "$HAVE_ACL" ]; then
      mkdir "$E/Q"; chmod 775 "$E/Q"; setfacl -m u:65534:rwx "$E/Q"
      _fc_safe mkdir --exclusive "$E/Q" >/dev/null 2>&1; r3=$?
      _fc_safe mkdtemp --exclusive-parent "$E/Q" p. >/dev/null 2>&1; r4=$?
      [ "$r3$r4" = 44 ] && [ -z "$(ls -A "$E/Q")" ] \
        && ok "[R15EXCL-acl] the same 0775 private-group directory WITH an ACL grant: mkdir --exclusive -> 4, mkdtemp --exclusive-parent -> 4, nothing made" \
        || bad "[R15EXCL-acl] rc=$r3 $r4 (want 4 4) contents=[$(ls -A "$E/Q" | tr '\n' ' ')]"
    else
      echo "SKIP [R15EXCL-acl] no POSIX ACL support -- not counted"
    fi
  else
    echo "SKIP [R15EXCL-*] this user's primary group has another member -- not counted"
  fi
fi

# =============================================================================
if want CENSUS; then
  out="$(FC_SUP_UNDER_TEST="$SUP" FC_BR_UNDER_TEST="$SCRIPT" python3 "$CENSUS" --self-test 2>&1)"; rc=$?
  n="$(sed -n 's/^SELFTEST cases=\([0-9]*\) failed=\([0-9]*\)$/\1 \2/p' <<<"$out")"
  [ "$rc" = 0 ] && [ "${n% *}" -ge 200 ] 2>/dev/null && [ "${n#* }" = 0 ] \
    && ok "[R15CENSUS-self] the census self-test: cases/failed = $n (>= 200 cases)" \
    || bad "[R15CENSUS-self] rc=$rc cases/failed=$n $(grep -m3 '^NOT-ok' <<<"$out" | tr '\n' ' ' | cut -c1-300)"
  # the round-8 reviewer's shell needles, VERBATIM (rv8_review/cen/sh_needles.txt + n2.txt): every one REFUSED
  miss=""; nn=0
  while IFS= read -r needle; do
    [ -n "$needle" ] || continue
    nn=$((nn+1))
    grep -qxF "ok sh REFUSES   $needle" <<<"$out" || miss="$miss | $needle"
  done <<'NEEDLES'
printf -v _wr %s /etc; rm -rf "$_wr/x"
rm -f "$_FC_TMPDIR/x"
local _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"
local _wr; rm -rf "$_wr/x"
(( _FC_TMPDIR = 0 )); rm -rf "$_FC_TMPDIR/x"
let _FC_TMPDIR=0; rm -rf "$_FC_TMPDIR/x"
: "${_wr:=/etc}"; rm -rf "$_wr/x"
wait -n -p _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"
select _FC_TMPDIR in /etc; do break; done; rm -rf "$_FC_TMPDIR/x"
_FC_TMPDIR[0]=/etc; rm -rf "$_FC_TMPDIR/x"
printf -v '_FC_TMPDIR' %s /etc; rm -rf "$_FC_TMPDIR/x"
n=_FC_TMPDIR; printf -v "$n" %s /etc; rm -rf "$_FC_TMPDIR/x"
n=_FC_TMPDIR; unset "$n"; rm -rf "$_FC_TMPDIR/x"
n=_FC_TMPDIR; declare -g "$n=/etc"; rm -rf "$_FC_TMPDIR/x"
n=_FC_TMPDIR; read -r "$n" <<<"/etc"; rm -rf "$_FC_TMPDIR/x"
coproc _FC_TMPDIR { :; }; rm -rf "$_FC_TMPDIR/x"
unset "_FC_TMPDIR"; rm -rf "$_FC_TMPDIR/x"
unset -v -- _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"
declare +n _x; typeset -n _y=_wr; _y=/etc; rm -rf "$_wr"
local -- _FC_TMPDIR=""; rm -rf "$_FC_TMPDIR/x"
_FC_TMPDIR=""; rm -rf "$_FC_TMPDIR/x"
printf -v"_FC_TMPDIR" %s /etc; rm -rf "$_FC_TMPDIR/x"
command printf -v _FC_TMPDIR %s /etc; rm -rf "$_FC_TMPDIR/x"
builtin unset _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"
declare -gn _r=_wr; _r=/etc; rm -rf "$_wr"
local -rn _r2=_FC_TMPDIR
NEEDLES
  [ -z "$miss" ] && [ "$nn" = 26 ] \
    && ok "[R15CENSUS-rv8-sh] all $nn of the round-8 reviewer's shell census needles (verbatim) are REFUSED by the self-test" \
    || bad "[R15CENSUS-rv8-sh] n=$nn not refused:$miss"
  miss=""; nn=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    nn=$((nn+1))
    grep -qxF "ok py $line" <<<"$out" || miss="$miss | $line"
  done <<'NEEDLES'
REFUSES   os.unlink.__call__(p)
ACCEPTS   os.close(fd)
REFUSES   locals()["os"].unlink(p)
REFUSES   dir(os)
REFUSES   help(os)
ACCEPTS   sys.stderr.buffer.raw
ACCEPTS   sys.stdout.reconfigure()
ACCEPTS   signal.signal(signal.SIGTERM, lambda *a: None)
ACCEPTS   json.loads(p, object_hook=None)
ACCEPTS   _st.S_IMODE(0)
ACCEPTS   [o for o in (1,)]
ACCEPTS   print("x", file=sys.stderr)
REFUSES   breakpoint()
ACCEPTS   memoryview(b"x")
REFUSES   (lambda: 0).__code__
ACCEPTS   super
ACCEPTS   (yield)
REFUSES   os.fspath(p)
REFUSES   os.path.join(p, "x").__len__
REFUSES   time.sleep.__self__
REFUSES   importlib.util.spec_from_file_location("x", p)
REFUSES   subprocess.run(["true"])
NEEDLES
  [ -z "$miss" ] && [ "$nn" = 22 ] \
    && ok "[R15CENSUS-rv8-py] all $nn of the round-8 reviewer's Python census needles (verbatim) have their stated verdict" \
    || bad "[R15CENSUS-rv8-py] n=$nn wrong verdict:$miss"
  # ---- an unquoted here-document body is expanded (and assigns); a quoted one is data ----
  HD="$WORK/hd.sh"; cp "$SCRIPT" "$HD"
  base=$(( $(wc -l <"$HD") ))
  printf '\n_needle_hd() {\n  cat <<EOF\n${_wr:=/etc}\nEOF\n  cat <<'"'"'EOF'"'"'\n${_FC_TMPDIR:=/etc}\nEOF\n}\n' >>"$HD"
  bad_line=$((base + 4)); ctl_line=$((base + 7))
  [ "$(sed -n "${bad_line}p" "$HD")" = '${_wr:=/etc}' ] && [ "$(sed -n "${ctl_line}p" "$HD")" = '${_FC_TMPDIR:=/etc}' ] || bad "[R15CENSUS-heredoc] fixture lines wrong"
  hout="$(FC_SUP_UNDER_TEST="$SUP" python3 "$CENSUS" --br "$HD" 2>&1)"
  hb="$(grep -c "^VIOLATION hd.sh:$bad_line .*default assignment" <<<"$hout")"
  hc="$(grep -c "^VIOLATION hd.sh:$ctl_line " <<<"$hout")"
  hall="$(grep -c "^VIOLATION" <<<"$hout")"
  [ "$hb" = 1 ] && [ "$hc" = 0 ] && [ "$hall" = 1 ] \
    && ok "[R15CENSUS-heredoc] \${_wr:=/etc} in an UNQUOTED here-document body is refused at its line ($bad_line); the same under <<'EOF' is data (control: not refused)" \
    || bad "[R15CENSUS-heredoc] at-line=$hb (want 1) quoted=$hc (want 0) total=$hall (want 1) $(grep -m3 '^VIOLATION' <<<"$hout" | cut -c1-200 | tr '\n' ' ')"
  # ---- the ${V:?} rule binds a param-tagged operand too ----
  PG="$WORK/pg.sh"
  sed 's#mktemp "${_FC_TMPDIR:?}/ledger\.#mktemp "$_FC_TMPDIR/ledger.#' "$SCRIPT" >"$PG"
  pl="$(grep -n 'mktemp "\$_FC_TMPDIR/ledger\.' "$PG" | cut -d: -f1)"
  pout="$(FC_SUP_UNDER_TEST="$SUP" python3 "$CENSUS" --br "$PG" 2>&1)"; prc=$?
  FC_SUP_UNDER_TEST="$SUP" python3 "$CENSUS" --br "$SCRIPT" >/dev/null 2>&1; crc=$?
  [ -n "$pl" ] && [ "$prc" = 1 ] && grep -q "^VIOLATION pg.sh:$pl _fc_ledger_add " <<<"$pout" && [ "$crc" = 0 ] \
    && ok "[R15CENSUS-param-guard] the ledger mktemp reverted to \"\$_FC_TMPDIR/ledger...\" (a param-tagged operand) is a VIOLATION at line $pl; the script under test: 0 violations" \
    || bad "[R15CENSUS-param-guard] line=[$pl] reverted rc=$prc (want 1) under-test rc=$crc (want 0) $(grep -m2 '^VIOLATION' <<<"$pout" | cut -c1-200 | tr '\n' ' ')"
fi

# =============================================================================
g() { git -c user.email=t@t.t -c user.name=t "$@"; }
if want SH; then
  S="$WORK/sh"; mkdir -p "$S"; chmod 711 "$S"
  REPO="$S/repo"; mkdir -p "$REPO"; g init -q "$REPO"; echo hello >"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "base commit"
  WTR="$S/wts"; mkdir "$WTR"; chmod 700 "$WTR"
  XDG="$S/xdg"; mkdir "$XDG"; chmod 700 "$XDG"
  printf '{"items": []}\n' >"$S/sample.json"
  sdev="$(stat -c %d "$WTR")"
  env -u FC_REPLAY_LOCK_DIR XDG_RUNTIME_DIR="$XDG" bash "$SCRIPT" replay-sample --sample "$S/sample.json" --repo-root "$REPO" \
    --worktree-root "$WTR" --min-free-kb 0 --min-free-kb-objects 0 --gate-cmd true --cold-runs 1 --warm-runs 0 \
    --out "$S/s.json" >/dev/null 2>"$S/s.err"; rc=$?
  inx="$(ls -A "$XDG" | tr '\n' ' ')"
  [ "$rc" = 0 ] && [ -z "$inx" ] && [ -f "$PWHOME/.cache/fc_baseline_replay/locks/fc_baseline_replay.fs-$sdev.lock" ] \
    && ok "[R15LOCK-noxdg] replay-sample with FC_REPLAY_LOCK_DIR unset and XDG_RUNTIME_DIR=$XDG: rc 0, nothing in \$XDG_RUNTIME_DIR, the per-filesystem lock under $PWHOME/.cache/fc_baseline_replay/locks" \
    || bad "[R15LOCK-noxdg] rc=$rc in-xdg=[$inx] home-lock=$([ -f "$PWHOME/.cache/fc_baseline_replay/locks/fc_baseline_replay.fs-$sdev.lock" ] && echo yes || echo no) $(head -c 300 "$S/s.err")"
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
