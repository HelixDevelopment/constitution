#!/usr/bin/env bash
# Toy VACUOUS gate: no possible input drives it to a non-zero exit — it is
# structurally incapable of failing (unconditional `exit 0`, ignores its
# argument entirely). Used to prove gate_audit.py's classifier can DETECT
# vacuity, not merely assume every gate that runs is "executing" — the
# control needle for the classifier's negative class.
set -euo pipefail
echo "gate_vacuous: PASS (always)"
exit 0
