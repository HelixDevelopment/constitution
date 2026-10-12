#!/usr/bin/env bash
# scripts/label-sync/adapters/qwen/qwen-hook.sh
#
# Purpose : Qwen Code hook -> label bus. Qwen Code is a Gemini-CLI fork; it is
#           treated as hook-compatible and delegates to gemini/gemini-hook.sh with
#           the agent name `qwen`.
# Usage   : configured under `hooks` in ~/.qwen/settings.json (see
#           docs/label-sync/ADAPTERS.md). stdin = the hook JSON.
# Inputs/Outputs/Mapping: identical to gemini/gemini-hook.sh.
# Exit    : ALWAYS 0 (identical to gemini/gemini-hook.sh).
# STATUS  : UNCONFIRMED — Qwen Code is NOT installed on the host this was written
#           on; hook-compatibility with Gemini CLI is an assumption (§11.4.6).
#           The guaranteed path is generic/label-agent-run.sh.
# Side-effects: labelctl calls. Deps: bash, jq.
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export LABEL_SYNC_HOOK_AGENT=qwen
exec bash "$HERE/../gemini/gemini-hook.sh"
