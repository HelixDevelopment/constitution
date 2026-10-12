#!/usr/bin/env bash
# scripts/label-sync/adapters/install_adapters.sh
#
# Purpose : Idempotent installer of the label-sync CLI-agent adapters into every
#           DETECTED agent's own configuration (§11.4.228(D): detect platforms,
#           wire, self-validate, idempotent, dry-run-capable). Per agent it edits
#           exactly one config file via _edit_config.py, which refuses invalid
#           JSON/TOML/YAML, never clobbers a user's own setting, backs up before
#           every change and writes atomically.
# Usage   : install_adapters.sh [--dry-run | --apply] [--remove]
#                [--home DIR] [--agents auto|kimi,opencode,crush,aider,codex,gemini,qwen]
#                [--list] [--quiet]
#           DEFAULT IS --dry-run: nothing is written unless --apply is given.
#           --remove (with --apply) strips the managed wiring (rollback).
#           --home DIR   resolve EVERY path under DIR instead of $HOME and ignore
#                        the HOME/XDG_*/KIMI_CODE_HOME env — the test mode: a
#                        run with --home can never touch the real home.
#           --agents     `auto` (default) = agents detected by `command -v <bin>`
#                        or an existing config dir under the home; or an explicit
#                        comma list (wired even when not detected).
#           --list       print the detection table and exit.
#           Config files (relative to the home):
#             kimi     .kimi-code/config.toml       ([[hooks]] x6 events)
#             opencode .config/opencode/opencode.json  (plugin file:// URL)
#             crush    .config/crush/crush.json     (hooks.PreToolUse)
#             aider    .aider.conf.yml              (notifications-command)
#             codex    .codex/config.toml           (notify)            UNCONFIRMED
#             gemini   .gemini/settings.json        (hooks)             UNCONFIRMED
#             qwen     .qwen/settings.json          (hooks)             UNCONFIRMED
#           Claude Code is NOT handled here: its hooks are installed by
#           ../install_label_sync.sh (HOOKS stream).
# Inputs  : flags; env HOME, XDG_CONFIG_HOME, KIMI_CODE_HOME (ignored with --home).
# Outputs : one status line per agent on stdout (`<agent> <status> <path> [detail]`)
#           and a summary. status: created|updated|unchanged|removed|absent|
#           would-created|would-updated|would-removed|conflict|invalid|skip|not-detected.
# Exit    : 0 all requested agents OK (not-detected agents are NOT failures)
#           1 at least one agent REFUSED (invalid existing config / conflict) —
#             that file is untouched
#           2 cannot determine (python3/PyYAML missing, adapters dir broken, usage).
#           2 is never a pass.
# Side-effects: --apply only: backup `<cfg>.label-sync.bak.<UTC>` + atomic write.
#           Idempotent: a second --apply is byte-identical and writes no backup.
# Deps    : bash, python3>=3.11 (+PyYAML for aider).
# Hook seam: post_update_hook.sh (§11.4.164/§11.4.228(D)) calls
#           `install_adapters.sh --apply` (the HOOKS stream owns that wiring).
# Cross-refs: §11.4.228, §11.4.164, §11.4.18, §11.4.10, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
mode=dry-run remove=0 home_arg="" agents=auto list=0 quiet=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) mode=dry-run; shift ;;
    --apply) mode=apply; shift ;;
    --remove) remove=1; shift ;;
    --home) home_arg="${2:-}"; shift 2 ;;
    --agents) agents="${2:-}"; shift 2 ;;
    --list) list=1; shift ;;
    --quiet) quiet=1; shift ;;
    -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install_adapters: unknown option '$1'" >&2; exit 2 ;;
  esac
done

if [ -n "$home_arg" ]; then
  [ -d "$home_arg" ] || { echo "install_adapters: --home '$home_arg' is not a directory" >&2; exit 2; }
  H="$(cd "$home_arg" && pwd)"
  CFG="$H/.config"            # --home pins XDG_CONFIG_HOME too: the real env never leaks in
  KIMI_HOME="$H/.kimi-code"
else
  H="${HOME:-}"
  [ -n "$H" ] && [ -d "$H" ] || { echo "install_adapters: HOME unusable" >&2; exit 2; }
  CFG="${XDG_CONFIG_HOME:-$H/.config}"
  KIMI_HOME="${KIMI_CODE_HOME:-$H/.kimi-code}"
fi

ALL=(kimi opencode crush aider codex gemini qwen)
cfg_file() {
  case "$1" in
    kimi) echo "$KIMI_HOME/config.toml" ;;
    opencode) echo "$CFG/opencode/opencode.json" ;;
    crush) echo "$CFG/crush/crush.json" ;;
    aider) echo "$H/.aider.conf.yml" ;;
    codex) echo "$H/.codex/config.toml" ;;
    gemini) echo "$H/.gemini/settings.json" ;;
    qwen) echo "$H/.qwen/settings.json" ;;
  esac
}
cfg_dir() { # the directory whose existence marks an agent as present
  case "$1" in
    kimi) echo "$KIMI_HOME" ;;
    opencode) echo "$CFG/opencode" ;;
    crush) echo "$CFG/crush" ;;
    aider) echo "$H/.aider.conf.yml" ;;
    codex) echo "$H/.codex" ;;
    gemini) echo "$H/.gemini" ;;
    qwen) echo "$H/.qwen" ;;
  esac
}
bin_of() { case "$1" in kimi) echo kimi ;; opencode) echo opencode ;; crush) echo crush ;; aider) echo aider ;; codex) echo codex ;; gemini) echo gemini ;; qwen) echo qwen ;; esac; }
detected() { # agent -> prints how, returns 0 when detected
  local b; b="$(bin_of "$1")"
  if [ -z "$home_arg" ] && command -v "$b" >/dev/null 2>&1; then echo "binary:$(command -v "$b")"; return 0; fi
  if [ -e "$(cfg_dir "$1")" ]; then echo "config:$(cfg_dir "$1")"; return 0; fi
  return 1
}

if [ "$list" = 1 ]; then
  for a in "${ALL[@]}"; do
    if how="$(detected "$a")"; then printf '%-9s detected     %s\n' "$a" "$how"; else printf '%-9s not-detected\n' "$a"; fi
  done
  exit 0
fi

command -v python3 >/dev/null 2>&1 || { echo "install_adapters: python3 not found — cannot determine" >&2; exit 2; }
for f in lib/label-adapter-event.sh lib/adapter_lib.sh kimi/kimi-hook.sh crush/crush-hook.sh aider/aider-notify.sh codex/codex-notify.sh gemini/gemini-hook.sh qwen/qwen-hook.sh opencode/label-sync.mjs _edit_config.py; do
  [ -r "$HERE/$f" ] || { echo "install_adapters: adapter file missing: $f — cannot determine" >&2; exit 2; }
done

if [ "$agents" = auto ]; then
  want=()
  for a in "${ALL[@]}"; do detected "$a" >/dev/null && want+=("$a"); done
  skipped=()
  for a in "${ALL[@]}"; do detected "$a" >/dev/null || skipped+=("$a"); done
else
  IFS=',' read -r -a want <<<"$agents"
  skipped=()
  for a in "${want[@]}"; do
    case " ${ALL[*]} " in *" $a "*) ;; *) echo "install_adapters: unknown agent '$a'" >&2; exit 2 ;; esac
  done
fi

emode="$mode"
if [ "$remove" = 1 ]; then emode="remove-dry"; [ "$mode" = apply ] && emode="remove"; fi
rc=0
for a in "${want[@]}"; do
  line="$(python3 "$HERE/_edit_config.py" --kind "$a" --file "$(cfg_file "$a")" --adapters-dir "$HERE" --mode "$emode")"
  r=$?
  [ "$quiet" = 1 ] || echo "$line"
  case "$r" in
    0) ;;
    1) [ "$rc" = 2 ] || rc=1 ;;
    *) rc=2 ;;
  esac
done
if [ "$quiet" != 1 ]; then
  for a in "${skipped[@]}"; do echo "$a not-detected"; done
  echo "install_adapters: mode=$emode agents=${want[*]:-none} exit=$rc"
  [ "$mode" = dry-run ] && echo "install_adapters: DRY-RUN — nothing was written; re-run with --apply"
fi
exit "$rc"
