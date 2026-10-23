#!/usr/bin/env bash
# Fixture claude_toolkit scripts/install.sh (run ONLY with --install-tools).
set -euo pipefail
printf '%s\n' "claude_toolkit/scripts/install.sh" >> "${STUB_LOG:-/tmp}/installers.log" 2>/dev/null || true
