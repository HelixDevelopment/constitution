#!/bin/sh
# toy gate: reads docs/README.md, layer=docs
cat "$(dirname "$0")/../docs/README.md" >/dev/null 2>&1 || true
echo "gate_docsync ok"
