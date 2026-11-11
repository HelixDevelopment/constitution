#!/bin/sh
# Purpose : CON-147 review finding F2-1 regression guard for
#           `constitution/scripts/fastcycle/host/host_report.py`: the live soft
#           RLIMIT_NPROC used by `_read_ulimit_threads()` (and so by
#           `probe_thread_headroom()` / `host_report.py limits`) is read from
#           the kernel's own record, /proc/self/limits, the same way
#           lib/host_guard.sh reads it, and `sh -c "ulimit -u"` is only a
#           fallback. Before the fix the read was `sh -c "ulimit -u"` only, so
#           on a host whose /bin/sh is dash (no `ulimit -u`) the thread
#           headroom was always reported "unmeasured".
# Usage   : sh test_host_report_thread_limit_r1_regression.sh   (or bash)
#           Exit 0 when every check passes, 1 otherwise. The last line is the
#           summary line.
# Inputs  : none. Uses a temp dir; never this project's repo state.
# Method  : the REAL host_report.py, imported by path. A PATH shim `sh` that
#           rejects `ulimit -u` the way dash does makes the dash case the same
#           on every host; real dash is also used when it is installed.
#           FC_GUARD_PROC_LIMITS fixtures pin soft != hard values.
#           Fixture axes (CON-147 review round 2, finding R2-F2-A: a fixture on
#           which a partial implementation gives the same answer as the correct
#           one proves nothing): WHOSE limits (this process, lowered with
#           setrlimit to a value pid 1 does not have, versus pid 1), WHICH
#           column (soft 4242 / hard 99999), WHICH source wins (file before
#           `ulimit -u`, FC_GUARD_ULIMIT_U before both), a MISSING or
#           UNREADABLE limits file (fallback to `ulimit -u`), no Max processes
#           line, `unlimited`. Paired mutations on a copy of the tool: each
#           must fail at least the functional check named for it.
set -u

ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/host/host_report.py"
LIB="$FC/lib/fc_common.py"
GUARD="$FC/lib/host_guard.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }

TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf "${TMP:?}"' EXIT

for p in "$IMPL" "$LIB" "$GUARD"; do [ -f "$p" ] || notok "control needle: $p not found"; done
[ "$fail" = 0 ] && ok "control needle: host_report.py, fc_common.py, host_guard.sh resolve"

# The expected live soft value, read independently by the test itself.
SOFT=$(awk '/^Max processes[ \t]/ { print $3; exit }' /proc/self/limits 2>/dev/null)
if [ -n "$SOFT" ]; then ok "control needle: live soft 'Max processes' = $SOFT (read by the test)"
else notok "control needle: /proc/self/limits has no readable 'Max processes' line on this host"; fi

# Dash-like `sh`: rejects `ulimit -u` exactly as dash does, forwards everything else.
REALSH=$(command -v sh)
mkdir -p "$TMP/dashlike"
cat > "$TMP/dashlike/sh" <<EOF
#!$REALSH
case "\$*" in *"ulimit -u"*) echo "sh: 1: ulimit: Illegal option -u" >&2; exit 2 ;; esac
exec $REALSH "\$@"
EOF
chmod +x "$TMP/dashlike/sh"
if PATH="$TMP/dashlike:$PATH" sh -c 'ulimit -u' >/dev/null 2>&1; then
  notok "shim self-check: dash-like sh still accepts 'ulimit -u'"
else ok "shim self-check: dash-like sh rejects 'ulimit -u'"; fi

# The live soft/hard values of THIS process and pid 1's soft value.
CURH=$(awk '/^Max processes[ \t]/ { print $4; exit }' /proc/self/limits 2>/dev/null)
P1S=$(awk '/^Max processes[ \t]/ { print $3; exit }' /proc/1/limits 2>/dev/null)
THR=$(ps -L --no-headers -U "$(id -ru)" 2>/dev/null | wc -l)
TAB=$(printf '\t')

# run_py IMPL [PATHPREFIX] [LIMITSFILE|-] [ULIMIT_U|-] [SOFT:HARD|-] -- python body on stdin
# Imports IMPL and runs the body with `m` bound to the module. SOFT:HARD lowers
# RLIMIT_NPROC of the python process itself (setrlimit, then exec).
run_py() {
  _impl=$1 _pre=${2:-} _lf=${3:--} _uu=${4:--} _rl=${5:--}
  _body=$(cat)
  (
    unset FC_GUARD_ULIMIT_U FC_GUARD_PROC_LIMITS
    [ "$_lf" = - ] || { FC_GUARD_PROC_LIMITS=$_lf; export FC_GUARD_PROC_LIMITS; }
    [ "$_uu" = - ] || { FC_GUARD_ULIMIT_U=$_uu; export FC_GUARD_ULIMIT_U; }
    FC_GUARD_THREADS=100; export FC_GUARD_THREADS
    [ -z "$_pre" ] || PATH="$_pre:$PATH"
    if [ "$_rl" = - ]; then set -- python3; else
      set -- python3 -c 'import os, resource, sys
s, h = (int(x) for x in sys.argv[1].split(":"))
resource.setrlimit(resource.RLIMIT_NPROC, (s, h))
os.execvp(sys.argv[2], sys.argv[2:])' "$_rl" python3
    fi
    "$@" - "$_impl" "$_body" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("host_report_under_test", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
exec(sys.argv[2])
PYEOF
  )
}
LIM_BODY='u, t, unl = m._read_ulimit_threads(); print("%s\t%s" % (u, unl))'
# read IMPL [PATHPREFIX] [LIMITSFILE|-] [ULIMIT_U|-] [SOFT:HARD|-] -> "ulim<TAB>unlimited"
read_lim() { echo "$LIM_BODY" | run_py "$@"; }

# Fixtures: soft != hard so a hard-limit read is caught.
mklim() { printf 'Limit                     Soft Limit           Hard Limit           Units     \nMax cpu time              unlimited            unlimited            seconds   \nMax processes             %s               %s               processes \nMax open files            1024                 524288               files     \n' "$1" "$2" > "$3"; }
mklim 4242 99999 "$TMP/lim_num"
mklim unlimited unlimited "$TMP/lim_unl"
printf 'Limit                     Soft Limit           Hard Limit           Units     \nMax open files            1024                 524288               files     \n' > "$TMP/lim_none"
cp "$TMP/lim_num" "$TMP/lim_unreadable"; chmod 000 "$TMP/lim_unreadable"
UNREADABLE=yes; cat "$TMP/lim_unreadable" >/dev/null 2>&1 && UNREADABLE=no

printf 'Max processes 4242\n' > "$TMP/lim_short"
printf 'Max processes 4242\nMax processes             8888                 99999                processes\n' > "$TMP/lim_short_full"
printf 'Max processes\t5151\t88888\tprocesses\n' > "$TMP/lim_tabs"
printf 'Max processes             6161                 99999                processes\nMax processes             7171                 99999                processes\n' > "$TMP/lim_dup"
printf 'Max processesX            4242                 99999                processes\n' > "$TMP/lim_prefix"
mklim unlimited 99999 "$TMP/lim_soft_unl"
mklim 3131 unlimited "$TMP/lim_hard_unl"
HAVE_BASH=no
if command -v bash >/dev/null 2>&1; then
  HAVE_BASH=yes
  mkdir -p "$TMP/bashsh"; ln -s "$(command -v bash)" "$TMP/bashsh/sh"
  BU=$(bash -c 'ulimit -u')
  [ "$BU" != 4242 ] || notok "control needle: bash 'ulimit -u' equals the fixture value 4242; L4B cannot discriminate"
fi
HAVE_DASH=no
if command -v dash >/dev/null 2>&1; then
  HAVE_DASH=yes; mkdir -p "$TMP/realdash"; ln -s "$(command -v dash)" "$TMP/realdash/sh"
fi

# Lowered limit for the WHOSE-limits leg: above this user's live thread count,
# below this process's hard limit, and different from pid 1's soft value.
RL=-
case "$CURH" in ''|*[!0-9]*) CURHN=999999999 ;; *) CURHN=$CURH ;; esac
case "$THR" in ''|*[!0-9]*) THR=0 ;; esac
LS=$((THR + 3000)); [ "$LS" != "$P1S" ] || LS=$((LS + 1))
LH=$((LS + 1000)); [ "$LH" -le "$CURHN" ] || LH=$CURHN
if [ "$LS" -lt "$LH" ]; then
  RL="$LS:$LH"
  GOT=$(echo 'print(open("/proc/self/limits").read())' | run_py "$IMPL" - - - "$RL" | awk '/^Max processes[ \t]/ { print $3 ":" $4; exit }')
  if [ "$GOT" = "$RL" ] && [ "$LS" != "$P1S" ]; then
    ok "control needle: setrlimit leg lowers this process to $RL (pid 1 soft '$P1S', user threads $THR)"
  else
    notok "control needle: setrlimit leg read '$GOT', wanted '$RL' (pid 1 soft '$P1S')"; RL=-
  fi
else
  echo "SKIP: P1 cannot lower RLIMIT_NPROC below the hard limit $CURH on this host (topology_unsupported)"
fi

# battery IMPL MODE: every functional check. MODE=report prints ok/NOT ok;
# MODE=collect prints only the ids of the checks that FAILED.
battery() {
  _bi=$1 _bm=$2 BF=""
  chk() {  # ID PASS(0|1) MESSAGE
    if [ "$2" = 0 ]; then [ "$_bm" = report ] && ok "$1 $3"
    else BF="$BF $1"; [ "$_bm" = report ] && notok "$1 $3"; fi
  }
  R=$(read_lim "$_bi" "$TMP/dashlike")
  [ "$R" = "$SOFT${TAB}False" ]; chk L1 $? "dash-like sh: live soft limit read = '$R' (want $SOFT, not unmeasured)"
  if [ "$HAVE_DASH" = yes ]; then
    R=$(read_lim "$_bi" "$TMP/realdash")
    [ "$R" = "$SOFT${TAB}False" ]; chk L2 $? "real dash as sh: live soft limit read = '$R' (want $SOFT)"
  fi
  R=$(read_lim "$_bi")
  [ "$R" = "$SOFT${TAB}False" ]; chk L3 $? "host sh ($REALSH): live soft limit read = '$R' (want $SOFT)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_num")
  [ "$R" = "4242${TAB}False" ]; chk L4 $? "fixture soft 4242 / hard 99999 -> '$R' (want the soft value 4242)"
  if [ "$HAVE_BASH" = yes ]; then
    R=$(read_lim "$_bi" "$TMP/bashsh" "$TMP/lim_num")
    [ "$R" = "4242${TAB}False" ]; chk L4B $? "fixture 4242 with a working 'ulimit -u' ($BU) -> '$R' (the file wins, want 4242)"
  fi
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_unl")
  [ "$R" = "None${TAB}True" ]; chk L5 $? "fixture 'unlimited' -> '$R' (want unlimited, never 0)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_none")
  [ "$R" = "None${TAB}False" ]; chk L6 $? "no 'Max processes' line + dash-like sh -> '$R' (want unmeasured, never guessed)"
  if [ "$HAVE_BASH" = yes ]; then
    R=$(read_lim "$_bi" "$TMP/bashsh" "$TMP/lim_none")
    [ "$R" = "$BU${TAB}False" ]; chk L7 $? "no 'Max processes' line + bash as sh -> '$R' (want the 'ulimit -u' fallback $BU)"
    R=$(read_lim "$_bi" "$TMP/bashsh" "$TMP/does_not_exist")
    [ "$R" = "$BU${TAB}False" ]; chk X1 $? "limits file MISSING + bash as sh -> '$R' (want the 'ulimit -u' fallback $BU)"
    if [ "$UNREADABLE" = yes ]; then
      R=$(read_lim "$_bi" "$TMP/bashsh" "$TMP/lim_unreadable")
      [ "$R" = "$BU${TAB}False" ]; chk X3 $? "limits file UNREADABLE (mode 000) + bash as sh -> '$R' (want the fallback $BU)"
    fi
  fi
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/does_not_exist")
  [ "$R" = "None${TAB}False" ]; chk X2 $? "limits file MISSING + dash-like sh -> '$R' (want unmeasured)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_num" 777)
  [ "$R" = "777${TAB}False" ]; chk O1 $? "FC_GUARD_ULIMIT_U=777 over a 4242 file -> '$R' (want the override 777)"
  if [ "$RL" != - ]; then
    R=$(read_lim "$_bi" "$TMP/dashlike" - - "$RL")
    [ "$R" = "$LS${TAB}False" ]; chk P1 $? "this process lowered to $RL, pid 1 soft $P1S -> '$R' (want THIS process's soft $LS)"
  fi
  if [ "$RL" != - ] && [ "$HAVE_BASH" = yes ]; then
    R=$(read_lim "$_bi" "$TMP/bashsh" "$TMP/does_not_exist" - "$RL")
    [ "$R" = "$LS${TAB}False" ]; chk RX1 $? "reviewer: lowered to $RL + limits file MISSING + bash as sh -> '$R' (want fallback SOFT $LS)"
    R=$(read_lim "$_bi" "$TMP/bashsh" "$TMP/lim_unreadable" - "$RL")
    [ "$R" = "$LS${TAB}False" ]; chk RX2 $? "reviewer: lowered to $RL + limits file UNREADABLE + bash as sh -> '$R' (want fallback SOFT $LS)"
  fi
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_short")
  [ "$R" = "None${TAB}False" ]; chk RX3 $? "reviewer: malformed 'Max processes' line (2 fields) + dash-like sh -> '$R' (want unmeasured, no crash)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_short_full")
  [ "$R" = "8888${TAB}False" ]; chk RX9 $? "round 5 (F8): a three-field 'Max processes' line, then a full one (soft 8888) -> '$R' (want 8888; host_guard.sh's awk reads the same line)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_tabs")
  [ "$R" = "5151${TAB}False" ]; chk RX4 $? "reviewer: TAB-separated line soft 5151 hard 88888 -> '$R' (want 5151)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_dup")
  [ "$R" = "6161${TAB}False" ]; chk RX5 $? "reviewer: first of two 'Max processes' lines (6161 then 7171) -> '$R' (want the first, 6161)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_prefix")
  [ "$R" = "None${TAB}False" ]; chk RX6 $? "reviewer: only 'Max processesX' line -> '$R' (want unmeasured, the prefix guard)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_soft_unl")
  [ "$R" = "None${TAB}True" ]; chk RX7 $? "reviewer: soft unlimited / hard 99999 -> '$R' (want unlimited)"
  R=$(read_lim "$_bi" "$TMP/dashlike" "$TMP/lim_hard_unl")
  [ "$R" = "3131${TAB}False" ]; chk RX8 $? "reviewer: soft 3131 / hard unlimited -> '$R' (want 3131)"
  R=$(echo 'print(m.probe_thread_headroom().get("reason"))' | (unset FC_GUARD_THREADS; run_py "$_bi" "$TMP/dashlike"))
  [ -n "$R" ] && [ "$R" != unmeasured ] && [ "$R" != None ]
  chk L8 $? "probe_thread_headroom under dash-like sh: reason '$R' (want a measured reason)"
  [ "$_bm" = collect ] && printf '%s' "$BF"
  return 0
}

battery "$IMPL" report

# --- paired mutations (each a copy of the tool; each must fail its named check) ---
mk_mutant() {  # NAME OLD NEW -> prints the mutant path, or "" when the anchor is not unique
  _d="$TMP/mut_$1"
  mkdir -p "$_d/host" "$_d/lib"
  cp "$IMPL" "$_d/host/host_report.py"; cp "$LIB" "$_d/lib/fc_common.py"; cp "$GUARD" "$_d/lib/host_guard.sh"
  if python3 - "$_d/host/host_report.py" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:]
c = open(p, encoding="utf-8").read()
if c.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(c.replace(old, new))
PYEOF
  then echo "$_d/host/host_report.py"; fi
}
mutation() {  # NAME "NAMED IDS" OLD NEW   (a named id absent on this host is not required)
  _m=$(mk_mutant "$1" "$3" "$4")
  if [ -z "$_m" ]; then notok "mutation $1: anchor not unique in the tool (not a catch)"; return; fi
  _got=$(battery "$_m" collect)
  _miss=""
  for _e in $2; do case " $_got " in *" $_e "*) ;; *) _miss="$_miss $_e" ;; esac; done
  if [ -z "$_got" ]; then notok "mutation $1 SURVIVED every functional check"
  elif [ -n "$_miss" ]; then notok "mutation $1: caught by$_got but NOT by its named check(s)$_miss"
  else ok "mutation $1: caught by$_got (named: $2)"; fi
}
NEED_BASH() { [ "$HAVE_BASH" = yes ] && echo "$1"; }
NEED_RL() { [ "$RL" != - ] && echo "$1"; }
NEED_UNR() { [ "$HAVE_BASH" = yes ] && [ "$UNREADABLE" = yes ] && echo "$1"; }

# M1: the pre-fix read (`sh -c "ulimit -u"` only).
mutation M1_ulimit_only "L1" 'ulim = _read_nproc_soft()' \
  'rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
        ulim = out.strip() if rc == 0 and out else None'
# M2: read the HARD column instead of the soft one.
mutation M2_hard_column "L4" 'return parts[2]' 'return parts[3]'
# M3: drop the `ulimit -u` fallback. (L6 is not named: with no line and a
# dash-like sh the correct tool also gives None, so L6 cannot tell them apart.)
mutation M3_no_fallback "$(NEED_BASH L7) $(NEED_BASH X1)" 'rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
    return out.strip() if rc == 0 and out else None' 'return None'
# HR1 (round-2 reviewer): no fallback when the file is missing or unreadable.
if [ "$HAVE_BASH" = yes ]; then
  mutation HR1_missing_file_no_fallback "X1 $(NEED_UNR X3)" '    except OSError:
        pass
    rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)' '    except OSError:
        return None
    rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)'
else echo "SKIP: HR1 needs bash as sh for a working fallback"; fi
# HR2 (round-2 reviewer): read pid 1's limits instead of this process's.
if [ "$RL" != - ]; then
  mutation HR2_pid1_limits "P1" 'path = os.environ.get("FC_GUARD_PROC_LIMITS", "/proc/self/limits")' \
    'path = os.environ.get("FC_GUARD_PROC_LIMITS", "/proc/1/limits")'
else echo "SKIP: HR2 needs the setrlimit leg (topology_unsupported)"; fi
# HR3 (round-2 reviewer): try `ulimit -u` before the file.
if [ "$HAVE_BASH" = yes ]; then
  mutation HR3_ulimit_first "L4B" '    try:
        with open(path, encoding="utf-8", errors="replace") as fh:' '    rc0, out0, _e0 = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
    if rc0 == 0 and out0 and out0.strip():
        return out0.strip()
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:'
else echo "SKIP: HR3 needs bash as sh"; fi
# M4: ignore the FC_GUARD_ULIMIT_U override.
mutation M4_override_ignored "O1" 'ulim = os.environ.get("FC_GUARD_ULIMIT_U")' 'ulim = None'


# ---- reviewer round-3 mutants (adopted verbatim, CON-147 round 4) ----
mutation RVH1_fallback_hard_column "RX1" 'rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
    return out.strip()' 'rc, out, _err = run_cmd(["sh", "-c", "ulimit -Hu"], timeout=10)
    return out.strip()'
mutation RVH2_parent_limits "P1" 'path = os.environ.get("FC_GUARD_PROC_LIMITS", "/proc/self/limits")' 'path = os.environ.get("FC_GUARD_PROC_LIMITS", "/proc/%d/limits" % os.getppid())'
mutation RVH3_last_but_one "L4" 'return parts[2]' 'return parts[-2]'
mutation RVH4_name_column "L1" 'return parts[2]' 'return parts[1]'
mutation RVH5_fnf_only "X3" '                        return parts[2]
    except OSError:
        pass' '                        return parts[2]
    except FileNotFoundError:
        pass'
mutation RVH6_no_len_guard "RX3" '                    if len(parts) >= 4:
                        return parts[2]' '                    return parts[2]'
mutation RVH7_no_prefix_guard "RX6" 'if line.startswith("Max processes") and line[13:14] in (" ", "\t"):' 'if line.startswith("Max processes"):'
mutation RVH8_last_match "RX5" '                    if len(parts) >= 4:
                        return parts[2]
    except OSError:
        pass' '                    if len(parts) >= 4:
                        globals()["_lastm"] = parts[2]
        if globals().get("_lastm"):
            return globals()["_lastm"]
    except OSError:
        pass'
mutation RVH9_unlimited_as_zero "L5" 'unlimited = (ulim == "unlimited")' 'unlimited = False; ulim = "0" if ulim == "unlimited" else ulim'
mutation RVH10_bash_explicit "L6" 'rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
    return out.strip()' 'rc, out, _err = run_cmd(["bash", "-c", "ulimit -u"], timeout=10)
    return out.strip()'
mutation RVH11_space_only_sep "RX4" 'if line.startswith("Max processes") and line[13:14] in (" ", "\t"):' 'if line.startswith("Max processes "):'
# RVH12 (reviewer: `return out.strip() if out else None`, ignoring the exit status)
# is EQUIVALENT, not a survivor to kill: when `ulimit -u` fails (dash) its error
# goes to stderr and stdout is empty, so the result is None either way.

echo "=== host_report thread limit regression guard (CON-147 F2-1): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
