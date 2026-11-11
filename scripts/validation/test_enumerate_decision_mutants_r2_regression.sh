#!/bin/bash
# Purpose : CON-162 regression guard for scripts/validation/enumerate_decision_mutants.py
#           (review fsfix6 nits n1 and n2).
#           n1: run_bounded killed only its own process GROUP on a timeout, but GNU
#               `timeout` starts a NEW process group, so its children kept running
#               for up to 125 s into the next mutant. Now every process of the
#               run's SESSION is killed (the session id is kept across setpgid).
#           n2: a ledger entry went STALE only when its key was no longer generated;
#               an entry whose mutant is later KILLED (its equivalence proof is now
#               false) was accepted silently. is_stale_killed() flags it.
# Usage   : bash test_enumerate_decision_mutants_r2_regression.sh
#           Exit 0 when every check passes, 1 otherwise; the last line is the summary.
# Method  : the REAL tool imported by path. n1 runs the real run_bounded on a command
#           that starts `timeout 100 sleep 97` and then inspects /proc for processes
#           left in that session. n2 calls the real classifier. Paired mutants on a
#           copy of the tool; control needle: a fabricated session id has no members (the
#           scan finds the real leftovers on the pre-fix tool: RED left=[timeout, sleep]).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ENUM="$HERE/enumerate_decision_mutants.py"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }
TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 1; }
SIDFILE="$TMP/sid"
cleanup() { # only processes of the session this test started
  if [ -s "$SIDFILE" ]; then
    sid=$(cat "$SIDFILE")
    case $sid in ''|*[!0-9]*|0|1) ;; *)
      for d in /proc/[0-9]*; do
        p=${d#/proc/}
        [ "$(awk '{ print $6 }' "$d/stat" 2>/dev/null)" = "$sid" ] && kill -KILL "$p" 2>/dev/null
      done ;;
    esac
  fi
  rm -rf "${TMP:?}"
}
trap cleanup EXIT

cat > "$TMP/drv.py" <<'PY'
import importlib.util, os, sys, time
spec = importlib.util.spec_from_file_location("em", sys.argv[1]); em = importlib.util.module_from_spec(spec); spec.loader.exec_module(em)
tmp = sys.argv[2]; sidfile = os.path.join(tmp, "sid"); bad = 0
def session_members(sid):
    out = []
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            st = open("/proc/%s/stat" % d).read()
            rest = st[st.rindex(")") + 2:].split()
            if rest[3] == str(sid) and rest[0] != "Z":
                out.append(int(d))
        except (OSError, ValueError, IndexError):
            pass
    return out
def check(name, good, detail=""):
    global bad
    print(("ok " if good else "NOT ok ") + name + (" " + detail if detail else ""))
    bad += 0 if good else 1
# n1: timeout's child group
cmd = ["bash", "-c", 'echo $$ > "%s"; timeout 100 sleep 97 >/dev/null 2>&1 & wait' % sidfile]
rc, _ = em.run_bounded(cmd, tmp, dict(os.environ), 3)
check("n1 run_bounded reports the timeout (rc None)", rc is None, "rc=%r" % (rc,))
sid = int(open(sidfile).read().strip())
left = session_members(sid)
check("n1 no process of the run's session survives the timeout kill", not left, "left=%r" % (left,))
check("n1 control needle: a fabricated session id has no members", session_members(2147483000) == [])
# n2: a ledger entry whose mutant is KILLED is stale
led = {"k1": {"target": "meta", "rule": "r", "old": "o", "proof": "p"}}
check("n2 KILLED mutant with a ledger entry is stale", em.is_stale_killed("KILLED", "k1", led) is True)
check("n2 EQUIVALENT mutant with a ledger entry is not stale", em.is_stale_killed("EQUIVALENT", "k1", led) is False)
check("n2 KILLED mutant without a ledger entry is not stale", em.is_stale_killed("KILLED", "zz", led) is False)
check("n2 SURVIVED mutant with a ledger entry is not stale (reported as survived/equivalent)", em.is_stale_killed("SURVIVED", "k1", led) is False)
sys.exit(1 if bad else 0)
PY
run() { python3 -I "$TMP/drv.py" "$1" "$TMP" 2>&1; }
OUT=$(run "$ENUM"); RC=$?
printf '%s\n' "$OUT" | sed 's/^/  | /'
if [ $RC = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^ok ')" = 7 ]; then ok "unmutated tool: all 7 checks pass"
else notok "unmutated tool fails ($(printf '%s\n' "$OUT" | grep -c '^NOT ok ') failing)"; fi

mut() { # $1 name $2 old $3 new (exactly one occurrence in the whole file)
  cp "$ENUM" "$TMP/m.py"
  python3 -I - "$TMP/m.py" "$2" "$3" <<'PY' || { notok "mutant $1: edit did not apply (blind)"; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, "pattern count %d" % s.count(old)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if run "$TMP/m.py" >/dev/null; then notok "mutant $1 SURVIVED"; else ok "mutant $1 killed"; fi
}
mut M1_kill_group_only   'kill_session(p.pid)' 'os.killpg(p.pid, signal.SIGKILL)'   # killpg-gate:allow mutant replacement text passed as a string argument, not a call
mut M2_stale_ignores_verdict 'return verdict == "KILLED" and key in ledger' 'return False'
mut M3_stale_any_verdict 'return verdict == "KILLED" and key in ledger' 'return key in ledger'

echo "=== enumerate_decision_mutants r2 (CON-162 n1 n2): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
