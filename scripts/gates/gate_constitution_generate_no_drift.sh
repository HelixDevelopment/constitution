#!/usr/bin/env bash
# gate_constitution_generate_no_drift.sh — §11.4.135 standing regression guard (legacy entry point).
# Fails if the committed constitution/groups/*.md + constitution_index.yaml
# have drifted from a fresh `constitution_generate.py check` against the
# committed constitution/Constitution.md.
#
# V5 F3 dedup: the check itself now lives in ONE implementation,
# cm_constitution_index_fresh.sh (CM-CONSTITUTION-INDEX-FRESH, pre-build wired, mutation-paired).
# This file only delegates, so the two can no longer drift apart. Exit codes are that gate's:
# 0 fresh, 1 drift, 2 BLIND (previously the raw generator rc under `set -e`).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$here/scripts/gates/cm_constitution_index_fresh.sh" --root "$here" "$@"
