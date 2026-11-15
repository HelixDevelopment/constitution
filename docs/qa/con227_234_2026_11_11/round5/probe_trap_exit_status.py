#!/usr/bin/env python3
"""J6 probe (round 5): is "trap 'exit 143' TERM" (and 'exit 129' HUP) observable?

Round 4 recorded the mutants that remove these traps (S11 in the tag script, Q12 in the publisher) as
EQUIVALENT ("no observable difference"). This probe shows that claim was wrong: the exit status differs.
A bash script that waits on a foreground child is signalled once the child runs (a READY file is the
handshake, no fixed sleep). With the trap, bash defers the trap until the child ends and then exits 143
(129 for HUP) through its own exit path; without it, bash is killed by the signal and the parent sees
"killed by signal" (Python: returncode -15 or -1). A shell's own `wait` reports both cases as 128 + the
signal number, which is why the round-4 harness could not tell them apart.

Usage: python3 -I probe_trap_exit_status.py WORKDIR
Prints one line per case; exit 0 when the two cases differ for both signals, else 1.
"""
import os
import signal
import subprocess
import sys
import time

work = sys.argv[1]
os.makedirs(work, exist_ok=True)
res = {}
for trap in ("with-trap", "without-trap"):
    for sig, code in (("TERM", 143), ("HUP", 129)):
        ready = os.path.join(work, "ready.%s.%s.%d" % (trap, sig, os.getpid()))
        prefix = "trap 'exit %d' %s; " % (code, sig) if trap == "with-trap" else ""
        script = prefix + "sh -c ': >\"$1\"; sleep 2' sh \"$READY\"; echo after"
        p = subprocess.Popen(["bash", "-c", script], env=dict(os.environ, READY=ready),
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(200):
            if os.path.exists(ready):
                break
            time.sleep(0.05)
        p.send_signal(getattr(signal, "SIG" + sig))
        rc = p.wait(timeout=30)
        res[(trap, sig)] = rc
        print("%-13s SIG%s: returncode %d" % (trap, sig, rc))
differ = all(res[("with-trap", s)] != res[("without-trap", s)] for s in ("TERM", "HUP"))
print("RESULT:", "the exit status DIFFERS (the trap is observable)" if differ else "no difference")
sys.exit(0 if differ else 1)
