#!/usr/bin/env bash
# gate_constitution_generate_no_drift.sh — §11.4.135 standing regression guard.
# Fails if the committed constitution/groups/*.md + constitution_index.yaml
# have drifted from a fresh `constitution_generate.py check` against the
# committed constitution/Constitution.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$here/scripts/anchors/constitution_generate.py" check \
  --source "$here/Constitution.md" \
  --groups-dir "$here/groups" \
  --index-out "$here/constitution_index.yaml"
