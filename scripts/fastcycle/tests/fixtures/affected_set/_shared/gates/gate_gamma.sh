#!/bin/sh
# toy gate: reads src/shared_lib.sh
. "$(dirname "$0")/../src/shared_lib.sh" 2>/dev/null || true
echo "gate_gamma ok"
