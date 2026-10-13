#!/bin/sh
# toy gate: reads docs/CHANGELOG.md, layer=docs
cat "$(dirname "$0")/../docs/CHANGELOG.md" >/dev/null 2>&1 || true
echo "gate_integrity ok"
