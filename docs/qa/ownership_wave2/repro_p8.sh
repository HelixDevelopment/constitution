#!/usr/bin/env bash
# repro_p8.sh — WIT-C01 evidence (ownership redesign, defect P8, section 11.4.102 / 11.4.115): reproduces, on the
# PRE-FIX generator (commit 1afdfc6^, "prune first, then write"), how the tracked generated command sets end up
# incomplete, and shows the current generator (atomic, stage then rename) does not. Everything runs in a mktemp
# sandbox; the real tree is only read (`git show`). Usage: bash docs/qa/ownership_wave2/repro_p8.sh [OLD_REV]
# Output: counts per agent after (A) a registry that fails validation, (B) a SIGKILL during generation.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OLD_REV="${1:-1afdfc6^}"
. "$REPO/scripts/lib/safe_rm.sh"
SB="$(mktemp -d)"; : "${SB:?}"; SB="$(realpath -e "$SB")"; export SAFE_RM_ALLOWED_ROOTS="$SB"
trap 'safe_rm_rf "${SB:?}"' EXIT
mk() { # DIR GENERATOR_SOURCE(old|new)
  mkdir -p "$1/scripts" "$1/actions" "$1/plugins/helix/commands"
  cp "$REPO/scripts/action_prefix_lib.sh" "$1/scripts/"; cp "$REPO/actions/registry.yaml" "$1/actions/"
  if [ "$2" = old ]; then git -C "$REPO" show "$OLD_REV:scripts/generate_agent_prefix_commands.sh" >"$1/scripts/generate_agent_prefix_commands.sh"
  else cp "$REPO/scripts/generate_agent_prefix_commands.sh" "$1/scripts/"; fi
}
counts() { printf 'plugin=%s gemini=%s qwen=%s codex=%s' "$(ls "$1"/plugins/helix/commands/*.md 2>/dev/null | wc -l)" \
  "$(ls "$1"/actions/generated/gemini/*.toml 2>/dev/null | wc -l)" "$(ls "$1"/actions/generated/qwen/*.toml 2>/dev/null | wc -l)" \
  "$(ls "$1"/actions/generated/codex/*.md 2>/dev/null | wc -l)"; }
N="$(grep -c '^  - name:' "$REPO/actions/registry.yaml" 2>/dev/null || echo '?')"
echo "registry actions (name: lines): $N"
for which in old new; do
  d="$SB/$which"; mk "$d" "$which"
  bash "$d/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1
  echo "[$which] baseline after a clean run:        $(counts "$d")"
  cp "$d/actions/registry.yaml" "$SB/reg.good"
  printf 'this is: [not a valid registry\n' >"$d/actions/registry.yaml"
  bash "$d/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1; rc=$?
  echo "[$which] (A) invalid registry, generator rc=$rc: $(counts "$d")"
  cp "$SB/reg.good" "$d/actions/registry.yaml"; bash "$d/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1
  for ms in 150 400 800; do
    ( bash "$d/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1 & pid=$!; sleep "0.$(printf '%03d' "$ms")"; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null )
    echo "[$which] (B) SIGKILL after ${ms}ms:          $(counts "$d")"
    cp "$SB/reg.good" "$d/actions/registry.yaml"; bash "$d/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1
  done
done
