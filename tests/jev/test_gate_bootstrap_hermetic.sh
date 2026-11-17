#!/usr/bin/env bash
# tests/jev/test_gate_bootstrap_hermetic.sh (round 4, review R3-2)
# CM-JEV-BOOTSTRAP-IDEMPOTENT must give the same verdict whatever the CALLER's environment holds: decision keys
# exported, JEV_HOSTED_PROBE=1, a key file named by JEV_API_KEYS_FILE, a real-looking llmctl / claude-providers /
# curl / agent CLI first on PATH, a CLAUDE_CONFIG_DIR. Before round 4 the gate copied the caller's PATH and keys
# into its bootstrap runs, went RED with an exported key, and could call the real tools.
# Every key value below is FAKE (never a real credential, §11.4.10). The spies below only record that they were
# called; they never reach a network. Evidence class: gate-logic (§11.4.289(C)(2)), not live proof of anything.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
GATE="${JEV_HERMETIC_GATE_UNDER_TEST:-$REPO/scripts/gates/cm_jev_bootstrap_idempotent.sh}"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '[hermetic] ok: %s\n' "$*"; }
no() { fail=$((fail+1)); printf '[hermetic] FAIL: %s\n' "$*"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/jev_hermetic.XXXXXX"); T="${T:?mktemp failed}"
cleanup() { case "$T" in */jev_hermetic.*) rm -rf -- "${T:?}";; esac; }
trap cleanup EXIT
mkdir -p "$T/spy" "$T/cfg"; : > "$T/spy.log"
for s in llmctl claude-providers curl wget claude kimi opencode; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\nexit 0\n' "$s" "$T/spy.log" > "$T/spy/$s"; chmod +x "$T/spy/$s"
done
# CONTROL NEEDLE: a spy records a call it receives (else an empty log below proves nothing, §11.4.273).
PATH="$T/spy:$PATH" llmctl decide status --json >/dev/null 2>&1
if [ "$(grep -c '^llmctl decide status --json$' "$T/spy.log")" = 1 ]; then ok "control: a spy records its call"; else no "control: the spy did not record its call (blind spy)"; fi
: > "$T/spy.log"
printf 'export TYPESAFE_API_KEY=fake-typesafe-0000000000000000\n' > "$T/keys.sh"; chmod 0600 "$T/keys.sh"

run_gate() { # run_gate <label> <with-keys 0|1> -> sets RC, OUT
  local with="$2"
  if [ "$with" = 1 ]; then
    OUT=$(env PATH="$T/spy:$PATH" CLAUDE_CONFIG_DIR="$T/cfg" JEV_HOSTED_PROBE=1 JEV_API_KEYS_FILE="$T/keys.sh" \
      TYPESAFE_API_KEY=fake-typesafe-1111111111111111 OPENROUTER_API_KEY=fake-openrouter-2222222222222222 \
      LLMCTL_API_KEY=fake-llmctl-3333333333333333 JEV_API_KEY=fake-jev-4444444444444444 \
      JEV_BASE_URL=https://jev.example.invalid LLMCTL_DIR="$T/nope" CLAUDE_TOOLKIT_DIR="$T/nope" \
      timeout --kill-after=10 600 bash "$GATE" 2>&1); RC=$?
  else
    OUT=$(env -u TYPESAFE_API_KEY -u OPENROUTER_API_KEY -u LLMCTL_API_KEY -u JEV_API_KEY -u JEV_API_KEYS_FILE \
      -u JEV_HOSTED_PROBE PATH="$T/spy:$PATH" CLAUDE_CONFIG_DIR="$T/cfg" \
      timeout --kill-after=10 600 bash "$GATE" 2>&1); RC=$?
  fi
}

for with in 1 0; do
  label=$([ "$with" = 1 ] && echo "fake keys + hosted probe exported" || echo "no keys exported")
  : > "$T/spy.log"
  run_gate "$label" "$with"
  if [ "$RC" = 0 ]; then ok "$label: gate GREEN (rc 0)"; else no "$label: gate rc $RC; last lines: $(printf '%s\n' "$OUT" | tail -n 4 | tr '\n' '|')"; fi
  if [ ! -s "$T/spy.log" ]; then ok "$label: no spy (llmctl / claude-providers / curl / agent CLI on the caller's PATH) was called"
  else no "$label: the gate's runs called the caller's tools: $(cut -d' ' -f1-3 "$T/spy.log" | sort -u | paste -sd, -)"; fi
  if [ -z "$(ls -A "$T/cfg")" ]; then ok "$label: the caller's CLAUDE_CONFIG_DIR was not written"; else no "$label: the caller's CLAUDE_CONFIG_DIR was written: $(ls -A "$T/cfg" | paste -sd, -)"; fi
  if printf '%s' "$OUT" | grep -q 'fake-[a-z]*-[0-9]\{16\}'; then no "$label: a fake key value was printed"; else ok "$label: no key value printed"; fi
done
printf '[hermetic] pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" = 0 ]
