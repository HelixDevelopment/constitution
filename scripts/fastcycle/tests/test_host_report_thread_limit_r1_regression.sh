#!/bin/sh
# Purpose : CON-109 review finding F2-1 regression guard for
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
#           FC_GUARD_PROC_LIMITS fixtures pin soft != hard values. Paired
#           mutations on a copy of the tool prove each part is load-bearing.
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

# read IMPL [PATHPREFIX] [LIMITSFILE|-] -> "ulim<TAB>unlimited"
read_lim() {
  _impl=$1 _pre=${2:-} _lf=${3:--}
  (
    unset FC_GUARD_ULIMIT_U FC_GUARD_PROC_LIMITS
    [ "$_lf" = - ] || FC_GUARD_PROC_LIMITS=$_lf
    [ "$_lf" = - ] || export FC_GUARD_PROC_LIMITS
    FC_GUARD_THREADS=100; export FC_GUARD_THREADS
    [ -z "$_pre" ] || PATH="$_pre:$PATH"
    python3 - "$_impl" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("host_report_under_test", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
u, t, unl = m._read_ulimit_threads()
print("%s\t%s" % (u, unl))
PYEOF
  )
}
TAB=$(printf '\t')

# L1 live read under a dash-like sh.
R=$(read_lim "$IMPL" "$TMP/dashlike")
if [ "$R" = "$SOFT${TAB}False" ]; then ok "L1 dash-like sh: live soft limit read = $SOFT (not unmeasured)"
else notok "L1 dash-like sh: expected '$SOFT False', got '$R'"; fi
# L2 real dash, when installed.
if command -v dash >/dev/null 2>&1; then
  mkdir -p "$TMP/realdash"; ln -s "$(command -v dash)" "$TMP/realdash/sh"
  if PATH="$TMP/realdash:$PATH" sh -c 'ulimit -u' >/dev/null 2>&1; then
    echo "info: this dash accepts 'ulimit -u'; L2 does not discriminate here"
  fi
  R=$(read_lim "$IMPL" "$TMP/realdash")
  if [ "$R" = "$SOFT${TAB}False" ]; then ok "L2 real dash as sh: live soft limit read = $SOFT"
  else notok "L2 real dash as sh: expected '$SOFT False', got '$R'"; fi
else
  echo "SKIP: L2 dash not installed (hardware_not_present-class: tool absent)"
fi
# L3 the same under the host's own sh (bash or dash, whatever it is).
R=$(read_lim "$IMPL")
if [ "$R" = "$SOFT${TAB}False" ]; then ok "L3 host sh ($REALSH): live soft limit read = $SOFT"
else notok "L3 host sh: expected '$SOFT False', got '$R'"; fi

# Fixtures: soft != hard so a hard-limit read is caught.
mklim() { printf 'Limit                     Soft Limit           Hard Limit           Units     \nMax cpu time              unlimited            unlimited            seconds   \nMax processes             %s               %s               processes \nMax open files            1024                 524288               files     \n' "$1" "$2" > "$3"; }
mklim 4242 99999 "$TMP/lim_num"
mklim unlimited unlimited "$TMP/lim_unl"
printf 'Limit                     Soft Limit           Hard Limit           Units     \nMax open files            1024                 524288               files     \n' > "$TMP/lim_none"
R=$(read_lim "$IMPL" "$TMP/dashlike" "$TMP/lim_num")
if [ "$R" = "4242${TAB}False" ]; then ok "L4 fixture soft 4242 / hard 99999 -> 4242 (the soft value)"
else notok "L4 expected '4242 False', got '$R'"; fi
R=$(read_lim "$IMPL" "$TMP/dashlike" "$TMP/lim_unl")
if [ "$R" = "None${TAB}True" ]; then ok "L5 fixture 'unlimited' -> unlimited (never 0)"
else notok "L5 expected 'None True', got '$R'"; fi
R=$(read_lim "$IMPL" "$TMP/dashlike" "$TMP/lim_none")
if [ "$R" = "None${TAB}False" ]; then ok "L6 no 'Max processes' line + dash-like sh -> unmeasured (None), never guessed"
else notok "L6 expected 'None False', got '$R'"; fi
if command -v bash >/dev/null 2>&1; then
  mkdir -p "$TMP/bashsh"; ln -s "$(command -v bash)" "$TMP/bashsh/sh"
  BU=$(bash -c 'ulimit -u')
  R=$(read_lim "$IMPL" "$TMP/bashsh" "$TMP/lim_none")
  if [ "$R" = "$BU${TAB}False" ]; then ok "L7 no 'Max processes' line + bash as sh -> 'ulimit -u' fallback = $BU"
  else notok "L7 expected '$BU False', got '$R'"; fi
else
  echo "SKIP: L7 bash not installed"
fi

# L8 end to end: probe_thread_headroom under the dash-like sh is measured.
R=$(
  unset FC_GUARD_ULIMIT_U FC_GUARD_PROC_LIMITS
  PATH="$TMP/dashlike:$PATH" python3 - "$IMPL" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("host_report_under_test", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.probe_thread_headroom().get("reason"))
PYEOF
)
if [ -n "$R" ] && [ "$R" != unmeasured ] && [ "$R" != None ]; then ok "L8 probe_thread_headroom under dash-like sh: reason '$R' (measured)"
else notok "L8 probe_thread_headroom under dash-like sh: reason '$R' (expected a measured reason)"; fi

# --- paired mutations (each on a fresh copy of the tool) ---
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
# M1: the pre-fix read (`sh -c "ulimit -u"` only).
M=$(mk_mutant M1_ulimit_only 'ulim = _read_nproc_soft()' \
  'rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
        ulim = out.strip() if rc == 0 and out else None')
if [ -z "$M" ]; then notok "mutation M1_ulimit_only: anchor not unique in the tool"
else
  R=$(read_lim "$M" "$TMP/dashlike")
  if [ "$R" = "$SOFT${TAB}False" ]; then notok "mutation M1_ulimit_only SURVIVED"
  else ok "mutation M1_ulimit_only: caught -- mutant read '$R'"; fi
fi
# M2: read the HARD column instead of the soft one.
M=$(mk_mutant M2_hard_column 'return parts[2]' 'return parts[3]')
if [ -z "$M" ]; then notok "mutation M2_hard_column: anchor not unique in the tool"
else
  R=$(read_lim "$M" "$TMP/dashlike" "$TMP/lim_num")
  if [ "$R" = "4242${TAB}False" ]; then notok "mutation M2_hard_column SURVIVED"
  else ok "mutation M2_hard_column: caught -- mutant read '$R'"; fi
fi
# M3: drop the `ulimit -u` fallback.
M=$(mk_mutant M3_no_fallback 'rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
    return out.strip() if rc == 0 and out else None' 'return None')
if [ -z "$M" ]; then notok "mutation M3_no_fallback: anchor not unique in the tool"
elif ! command -v bash >/dev/null 2>&1; then echo "SKIP: M3 needs bash"
else
  R=$(read_lim "$M" "$TMP/bashsh" "$TMP/lim_none")
  if [ "$R" = "$BU${TAB}False" ]; then notok "mutation M3_no_fallback SURVIVED"
  else ok "mutation M3_no_fallback: caught -- mutant read '$R'"; fi
fi

echo "=== host_report thread limit regression guard (CON-109 F2-1): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
