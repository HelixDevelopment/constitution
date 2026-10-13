#!/bin/sh
# toy gate: DECLARES only src/declared_only.sh but ACTUALLY reads
# src/secret_extra.sh too -- the undeclared-read fixture's whole point.
cat "$(dirname "$0")/../src/declared_only.sh" >/dev/null 2>&1 || true
cat "$(dirname "$0")/../src/secret_extra.sh" >/dev/null 2>&1 || true
echo "gate_undeclared ok"
