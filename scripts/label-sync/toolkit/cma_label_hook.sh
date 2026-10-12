#!/usr/bin/env bash
# scripts/label-sync/toolkit/cma_label_hook.sh
#
# Purpose : SOURCEABLE integration of the label-sync ALIAS-SWITCH SIGNAL into the
#           claude-multi-account toolkit (~/.local/share/claude-multi-account/
#           aliases.sh). It WRAPS the toolkit's two launchers —
#             cma_run            (native aliases claude1..N; alias = the
#                                 basename of $CLAUDE_CONFIG_DIR, `.claude-<alias>`)
#             cma_run_provider   (provider aliases deepseek, xiaomi, ...; alias =
#                                 the provider id; model = CMA_PROVIDER_MODEL
#                                 read — never sourced — from the provider's
#                                 .env, the same single source of truth the
#                                 labeler uses)
#           — so that LAUNCHING or RESUMING a session under an alias publishes
#           `alias_switch` (label-sync-alias-switch.sh) BEFORE the session
#           starts. Every follower label then re-renders on the next snapshot,
#           and the SessionStart hook (label-sync-session-start.sh) republishes
#           the subtree of a session resumed under a different alias.
#           The wrapper is transparent: arguments, environment, working
#           directory and the launcher's exit status are preserved; it prints
#           nothing; any failure of the label tooling is swallowed — a launch is
#           NEVER blocked or delayed by label-sync (first launch on a host with
#           no built binary only kicks a detached background build).
# Usage   : in ~/.bashrc / ~/.zshrc AFTER aliases.sh has been sourced:
#             source /path/to/constitution/scripts/label-sync/toolkit/cma_label_hook.sh
#           Idempotent: sourcing twice (or re-sourcing aliases.sh then this file
#           again) never double-wraps (`cma_label_hook_rewrap` re-applies).
#           NEVER executed directly (it must define functions in the caller's shell).
# Inputs  : env CLAUDE_CONFIG_DIR (native alias), HOME (provider registry),
#           LABEL_SYNC_DIR/LABEL_SYNC_BIN/LABEL_SYNC_DISABLE=1 (kill switch).
# Outputs : none (silent). Defines: cma_label_hook_rewrap, _cma_label_* helpers;
#           redefines cma_run / cma_run_provider as thin wrappers.
# Exit    : sourcing returns 0 always; wrapped launchers return the original's status.
# Side-effects: publishes one `alias_switch` event per launch (state dir only).
#           Does NOT read/echo provider API keys (only the one CMA_PROVIDER_MODEL
#           line is extracted with sed). Does NOT edit any file under $HOME.
# Deps    : bash (or zsh with bash-compatible function syntax), sed.
# Honest limitation (§11.4.6): the active alias is operator-GLOBAL by design
#           (CONTRACT §4.1) — launching a second terminal under another alias
#           flips the active alias for every follower; sessions bound to their own
#           alias by the SessionStart hook keep their own label.
# Cross-refs: §11.4.182, CONTRACT §4, docs/label-sync/HOOKS.md (install text).
# Classification: universal (§11.4.17).

(return 0 2>/dev/null) || { echo "cma_label_hook.sh must be SOURCED, not executed" >&2; exit 2; }

_CMA_LABEL_TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
_CMA_LABEL_SYNC_DIR="$(cd "$_CMA_LABEL_TOOLKIT_DIR/.." && pwd)"

# _cma_label_publish <alias> [model] — fail-soft, silent, synchronous.
_cma_label_publish() {
  [ "${LABEL_SYNC_DISABLE:-}" = 1 ] && return 0
  [ -n "${1:-}" ] || return 0
  local sw="$_CMA_LABEL_SYNC_DIR/hooks/label-sync-alias-switch.sh"
  [ -f "$sw" ] || return 0
  local bin="${LABEL_SYNC_BIN:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/constitution-label-sync/bin}/labelctl"
  if [ ! -x "$bin" ]; then
    # first use on this host: never make a launch wait for `go build`
    if [ "${LABEL_SYNC_NO_BUILD:-}" != 1 ] && command -v go >/dev/null 2>&1; then
      ( setsid nice -n 10 bash "$_CMA_LABEL_SYNC_DIR/labelctl.sh" --build >/dev/null 2>&1 </dev/null & ) >/dev/null 2>&1
    fi
    return 0
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 bash "$sw" "$1" ${2:+--model "$2"} >/dev/null 2>&1 </dev/null || true
  else
    bash "$sw" "$1" ${2:+--model "$2"} >/dev/null 2>&1 </dev/null || true
  fi
  return 0
}

# _cma_label_provider_model <id> — read ONLY the CMA_PROVIDER_MODEL line.
_cma_label_provider_model() {
  local f="${HOME:-}/.local/share/claude-multi-account/providers/$1.env"
  [ -r "$f" ] || return 0
  sed -n "s/^CMA_PROVIDER_MODEL='\([^']*\)'.*/\1/p" "$f" 2>/dev/null | head -n1
}

_cma_label_pre_native() {
  local base alias=""
  base="$(basename "${CLAUDE_CONFIG_DIR:-}" 2>/dev/null)"
  case "$base" in .claude-?*) alias="${base#.claude-}" ;; esac
  _cma_label_publish "$alias"
}

_cma_label_pre_provider() {
  local id="" a
  for a in "$@"; do case "$a" in --force) ;; -*) break ;; *) id="$a"; break ;; esac; done
  [ -n "$id" ] || return 0
  _cma_label_publish "$id" "$(_cma_label_provider_model "$id")"
}

# _cma_label_wrap <function-name> <pre-hook-function>
# Renames the existing toolkit function to _cma_label_orig_<name> and installs a
# wrapper. A function that already contains our pre-hook marker is left alone.
_cma_label_wrap() {
  local name="$1" pre="$2" body
  declare -F "$name" >/dev/null 2>&1 || return 0              # toolkit not loaded: nothing to wrap
  body="$(declare -f "$name")"
  case "$body" in *"$pre"*) return 0 ;; esac                  # already wrapped
  eval "$(printf '%s\n' "$body" | sed "1s/^$name *()/_cma_label_orig_$name ()/")"
  eval "$name() { $pre \"\$@\"; _cma_label_orig_$name \"\$@\"; }"
  return 0
}

cma_label_hook_rewrap() {
  _cma_label_wrap cma_run _cma_label_pre_native
  _cma_label_wrap cma_run_provider _cma_label_pre_provider
  return 0
}
cma_label_hook_rewrap
return 0 2>/dev/null || true
