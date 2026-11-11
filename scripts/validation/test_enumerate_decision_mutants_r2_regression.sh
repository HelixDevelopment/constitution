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
#           CON-217 (review fu_a m2, reviewer mutant RG): kill_session must refuse sid 1,
#             0, -5 and "7" with ValueError BEFORE any signal; os.kill is replaced by a
#             record-and-refuse stub for these calls (unit scope), so a mutated guard
#             can never signal anything; the stub is restored afterwards.
#           CON-218 (review fu_a m3, reviewer mutant RI): main() itself is driven on a
#             synthetic target (a temp git root with one sh script, its test, and a
#             ledger entry for the one mutant the test kills); it must print the STALE
#             line and return 1. Control: the same run without the ledger entry
#             returns 0 with no STALE line.
#           CON-220 (review fu_a n2): a ledger key whose mutant is KILLED-TIMEOUT is
#             STALE too (a hang refutes "behaves like the original", or at least
#             leaves the equivalence proof unconfirmed; fail closed).
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
check("n2 KILLED-TIMEOUT mutant with a ledger entry is stale (CON-220)", em.is_stale_killed("KILLED-TIMEOUT", "k1", led) is True)
check("n2 KILLED-TIMEOUT mutant without a ledger entry is not stale (CON-220)", em.is_stale_killed("KILLED-TIMEOUT", "zz", led) is False)
# CON-217: section 11.4.263 refusal, os.kill stubbed so nothing can be signalled
kills = []
def _refuse(pid, sig):
    kills.append((pid, sig)); raise PermissionError("stubbed os.kill: refused")
_real_kill = em.os.kill
em.os.kill = _refuse
try:
    for bad_sid in (1, 0, -5, "7"):
        try:
            em.kill_session(bad_sid); raised = False
        except ValueError:
            raised = True
        except Exception:  # the stub refused: the guard let a signal through
            raised = False
        check("n1 kill_session(%r) refused with ValueError (CON-217)" % (bad_sid,), raised)
finally:
    em.os.kill = _real_kill
check("n1 kill_session refusals sent zero signals (CON-217)", kills == [], "kills=%r" % (kills,))
# CON-218: main() on a synthetic target
import subprocess, contextlib, io
syn = os.path.join(tmp, "synroot"); os.makedirs(os.path.join(syn, "scripts", "validation"))
open(os.path.join(syn, "scripts", "syn.sh"), "w").write('#!/bin/sh\n[ -n "$1" ] || exit 3\nexit 0\n')
open(os.path.join(syn, "scripts", "test_syn.sh"), "w").write('sh scripts/syn.sh a\n')
subprocess.run(["git", "init", "-q", syn], check=True)
subprocess.run(["git", "-C", syn, "add", "scripts"], check=True)
em.TARGETS["syn"] = {"path": "scripts/syn.sh", "test": ["sh", "scripts/test_syn.sh"], "env": {},
                     "parse": ["sh", "-n"], "timeout": 60, "lines": None}
nz = [m for m in em.enumerate_target("syn", syn) if m["rule"] == "nz_flip"]
check("m3 synthetic target yields exactly one nz_flip mutant", len(nz) == 1, "n=%d" % len(nz))
key = nz[0]["key"] if nz else "none"
ledp = os.path.join(syn, em.LEDGER_REL)
def run_main(with_entry):
    with open(ledp, "w") as fh:
        if with_entry:
            fh.write("%s\tsyn\tnz_flip\t%s\tclaimed equivalent (planted by the test)\n" % (key, nz[0]["old"].strip() if nz else ""))
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = em.main(["--target", "syn", "--root", syn, "--only", key])
    return rc, buf.getvalue()
rc, out = run_main(True)
stale = [l for l in out.splitlines() if l.startswith("STALE\t%s\t" % key) and "mutant is KILLED" in l]
check("m3 main(): KILLED mutant with a ledger entry prints its STALE line (CON-218)", len(stale) == 1, "out=%r" % (out[-400:],))
check("m3 main(): ... and returns 1 (CON-218)", rc == 1, "rc=%r" % (rc,))
rc0, out0 = run_main(False)
check("m3 control: no ledger entry -> main() returns 0, no STALE line", rc0 == 0 and "STALE" not in out0 and ("KILLED\t%s" % key) in out0, "rc=%r out=%r" % (rc0, out0[-400:]))
del em.TARGETS["syn"]
sys.exit(1 if bad else 0)
PY
run() { python3 -I "$TMP/drv.py" "$1" "$TMP" 2>&1; }
OUT=$(run "$ENUM"); RC=$?
printf '%s\n' "$OUT" | sed 's/^/  | /'
if [ $RC = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^ok ')" = 18 ]; then ok "unmutated tool: all 18 checks pass"
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
mut M2_stale_ignores_verdict 'return verdict in ("KILLED", "KILLED-TIMEOUT") and key in ledger' 'return False'
mut M3_stale_any_verdict 'return verdict in ("KILLED", "KILLED-TIMEOUT") and key in ledger' 'return key in ledger'
# reviewer mutants of the fu_a review, verbatim: RG drops the sid <= 1 refusal, RI disables the STALE call site.
mut RG_drop_sid_le_1_refusal 'if not isinstance(sid, int) or sid <= 1:' 'if not isinstance(sid, int):'
mut RI_stale_call_site_off 'if is_stale_killed(v, m["key"], ledger):' 'if False and is_stale_killed(v, m["key"], ledger):'
# CON-220: the pre-fix classifier (KILLED only).
mut M4_stale_ignores_timeout 'return verdict in ("KILLED", "KILLED-TIMEOUT") and key in ledger' 'return verdict == "KILLED" and key in ledger'

echo "=== enumerate_decision_mutants r2 (CON-162 n1 n2): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
