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
# Ambient tool-location, endpoint, key and mode overrides must not leak into the hermetic tests
# (observed 2026-10-24: with LLMCTL_DIR exported, test_post_update_hook_trigger.sh [3b] and
# test_gate_pairs.sh [CM-JEV-BOOTSTRAP-IDEMPOTENT] failed; both pass with it unset). Key VALUES in
# the caller's environment would also be picked up by hosted-key discovery.
unset LLMCTL_DIR CLAUDE_TOOLKIT_DIR LLMCTL_ENDPOINT LLMCTL_DECIDE_PORT LLMCTL_CACERT LLMCTL_API_KEY \
      TYPESAFE_API_KEY OPENROUTER_API_KEY JEV_API_KEY JEV_API_KEYS_FILE CMA_KEYS_FILE CMA_JEV_PINS_FILE \
      JEV_KEY_VAR JEV_MODE JEV_GATE JEV_GATE_FAIL JEV_BASE_URL JEV_CA_FILE JEV_DETECTION_FILE JEV_PROBE_CMD \
      JEV_BEFORE JEV_AFTER JEV_DECISIONS JEV_HOSTED_PROBE JEV_HOME JEV_FIXTURE_ROOT JEV_EVIDENCE_WINDOW_START \
      LLMCTL_STATUS_JSON LLMCTL_CAPACITY_JSON FIXTURE_ENDPOINTS \
      JEV_TEST JEV_REQUIRE_VALIDATED_CMD JEV_DECISION_PROFILES JEV_PINS_FILE JEV_MODEL TYPESAFE_BASE_URL JEV_SKIP_VALIDATION JEV_DETECTION_MAX_AGE JEV_STATUS_NO_VALIDATE JEV_NOW_EPOCH
REAL_HOME="${HOME:-}"
# Hermetic: an operator key in the caller environment must never decide a test verdict.
unset TYPESAFE_API_KEY OPENROUTER_API_KEY LLMCTL_API_KEY
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
