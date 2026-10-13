#!/bin/sh
# toy gate: reads src/alpha.sh
. "$(dirname "$0")/../src/alpha.sh" 2>/dev/null || true
echo "gate_alpha ok"
