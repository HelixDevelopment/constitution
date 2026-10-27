#!/usr/bin/env bash
# run_all.sh — runs every tests/jev/test_*.sh in a sandboxed HOME and prints one
# summary line per test. Exit 0 only if all pass; 2 if zero tests matched (a
# blind harness is never a pass). Each test is self-contained and may also be run
# directly: `bash tests/jev/test_<name>.sh`.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Isolation (a bootstrap that inherits the real home writes ~/.local/state/jev,
# ~/.config/jev, ~/.local/share/helix and may clone over the network): every
# path the wizard reads is pinned under a throwaway HOME and git cannot reach
# the network.
REAL_HOME="${HOME:-}"
export HOME; HOME="$(mktemp -d)"; trap 'rm -rf "$HOME"' EXIT
export JEV_STATE_DIR="$HOME/.local/state/jev" JEV_CONFIG_DIR="$HOME/.config/jev" \
       JEV_BOOTSTRAP_HOME="$HOME/.local/share/helix" JEV_EVIDENCE_DIR="$HOME/.jev" \
       CMA_PROVIDERS_DIR="$HOME/.local/share/claude-multi-account/providers" \
       GIT_SSH_COMMAND=/bin/false
[ "$HOME" != "$REAL_HOME" ] || { echo "FATAL: failed to isolate HOME" >&2; exit 2; }
ran=0; bad=0
for t in "$HERE"/test_*.sh; do
  [ -e "$t" ] || continue
  ran=$((ran+1))
  if nice -n 10 timeout 600 bash "$t" >"$HOME/out.$ran" 2>&1; then
    printf 'PASS %s\n' "$(basename "$t")"
  else
    bad=$((bad+1)); printf 'FAIL %s\n' "$(basename "$t")"; grep -E 'FAIL' "$HOME/out.$ran" | head -8 | sed 's/^/     /'
  fi
done
[ "$ran" -gt 0 ] || { echo "FATAL: zero tests matched — NOT a pass" >&2; exit 2; }
printf 'ran %d, failed %d\n' "$ran" "$bad"
[ "$bad" -eq 0 ]
