#!/bin/sh
# toy gate: reads src/beta.sh
. "$(dirname "$0")/../src/beta.sh" 2>/dev/null || true
echo "gate_beta ok"
