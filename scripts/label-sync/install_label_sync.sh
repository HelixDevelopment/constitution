#!/usr/bin/env bash
# scripts/label-sync/install_label_sync.sh
#
# Purpose : The AUTO-WIRING installer of the label-sync system (§11.4.228(D) /
#           §11.4.164 / §11.4.75). Merges the label-sync hook entries — and the
#           statusLine entry — into a TARGET Claude Code settings.json so every
#           consumer that pulls the constitution behaves identically, with no
#           hand editing:
#             SessionStart      -> hooks/label-sync-session-start.sh
#             UserPromptSubmit  -> hooks/label-sync-prompt.sh
#             PreToolUse (Agent|Task) -> hooks/label-sync-agent-register.sh
#             SubagentStart     -> hooks/label-sync-subagent-start.sh
#             SubagentStop      -> hooks/label-sync-subagent-stop.sh
#             Stop              -> hooks/label-sync-stop.sh
#             SessionEnd        -> hooks/label-sync-session-end.sh
#             PostModelSwitch   -> hooks/label-sync-model-switch.sh   (opt-in: --with-model-switch)
#             statusLine        -> render/statusline.sh   (skipped with --no-statusline)
#           The merge is STRUCTURAL (jq), PRESERVES every existing key and every
#           existing hook, NEVER duplicates (an entry of ours is recognised by its
#           script name, de-duplicated and refreshed in place), is IDEMPOTENT
#           (apply x N => byte-identical file, no extra backup), writes a BACKUP
#           before the first change, and REFUSES a settings file that is not
#           valid JSON. A foreign statusLine is never clobbered.
#           DEFAULT IS --dry-run: nothing is written and a unified diff is shown.
# Usage   : install_label_sync.sh [--apply | --dry-run] [--platform claude|all]
#                  [--scope project|user] [--project-root DIR]
#                  [--home DIR | --config-dir DIR | --settings FILE]
#                  [--constitution-root DIR] [--render-path FILE]
#                  [--no-statusline] [--with-model-switch] [--uninstall] [--brief]
#   --scope project (default) target <project-root>/.claude/settings.json; hook
#                   commands use `bash "$CLAUDE_PROJECT_DIR/<rel>/..."` when the
#                   constitution lives inside the project (portable, tracked,
#                   BY REFERENCE per §11.4.28/§11.4.177), else absolute paths.
#   --scope user    target <config-dir>/settings.json (config-dir = --config-dir,
#                   else $CLAUDE_CONFIG_DIR, else <home>/.claude); absolute paths.
#   --home DIR      treat DIR as $HOME for --scope user (tests use a temp dir; the
#                   process $HOME is never written).
#   --platform all  also reports the platforms this installer does NOT wire
#                   (opencode / gemini / qwen: no Claude-style hook interface) —
#                   an honest SKIP, never a pretended install.
#   --uninstall     remove our entries (and our statusLine) — the rollback; with
#                   --apply it writes (with backup), else shows the diff.
#   --brief         one-line plan instead of the full diff (used by post_update_hook.sh).
# Inputs  : args; the existing settings file (read-only unless --apply); env
#           CLAUDE_PROJECT_DIR / CLAUDE_CONFIG_DIR / HOME as described above.
# Outputs : stdout: diff / plan / verdict lines. stderr: refusals.
# Exit    : 0 ok (incl. "already wired" and dry-run) | 1 refused: settings file is
#           not valid JSON (or not an object) | 2 usage error or precondition
#           unmet at --apply (statusLine renderer or a hook script missing,
#           jq absent) — nothing written. 2 is never a pass.
# Side-effects: ONLY with --apply: writes <settings>.label-sync.bak.<UTC-ts>[.n]
#           (copy of the previous file) then atomically replaces the settings file
#           (temp file in the same directory + mv). Never touches anything else.
# Deps    : bash, jq, diff, cp, mv, date, realpath.
# Rollback: restore the backup (`cp <settings>.label-sync.bak.<ts> <settings>`) or
#           run this script with --uninstall --apply.
# Cross-refs: §11.4.228(D), §11.4.164, §11.4.109 (wire guards by reference),
#           §11.4.201 (assert real conditions), docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
CONST_ROOT="$(cd "$HERE/../.." && pwd -P)"

apply=0; platform=claude; scope=project; project_root=""; home_override=""; cfg_dir=""; settings_file=""
render_path=""; no_status=0; with_model=0; uninstall=0; brief=0

usage() { sed -n '/^# Usage/,/^# Inputs/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
need_arg() { [ $# -ge 2 ] || usage; }
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1; shift ;;
    --dry-run) apply=0; shift ;;
    --platform) need_arg "$@"; platform="$2"; shift 2 ;;
    --scope) need_arg "$@"; scope="$2"; shift 2 ;;
    --project-root) need_arg "$@"; project_root="$2"; shift 2 ;;
    --home) need_arg "$@"; home_override="$2"; shift 2 ;;
    --config-dir) need_arg "$@"; cfg_dir="$2"; shift 2 ;;
    --settings) need_arg "$@"; settings_file="$2"; shift 2 ;;
    --constitution-root) need_arg "$@"; CONST_ROOT="$2"; shift 2 ;;
    --render-path) need_arg "$@"; render_path="$2"; shift 2 ;;
    --no-statusline) no_status=1; shift ;;
    --with-model-switch) with_model=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    --brief) brief=1; shift ;;
    -h|--help) usage ;;
    *) echo "install_label_sync: unknown argument '$1'" >&2; usage ;;
  esac
done
case "$platform" in claude|all) ;; *) echo "install_label_sync: unknown --platform '$platform' (claude|all)" >&2; exit 2 ;; esac
case "$scope" in project|user) ;; *) echo "install_label_sync: unknown --scope '$scope' (project|user)" >&2; exit 2 ;; esac
command -v jq >/dev/null 2>&1 || { echo "install_label_sync: jq is required" >&2; exit 2; }

[ -n "$render_path" ] || render_path="$CONST_ROOT/scripts/label-sync/render/statusline.sh"

# ---- target settings file -------------------------------------------------
[ -n "$project_root" ] || project_root="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -n "$settings_file" ]; then target="$settings_file"
elif [ "$scope" = project ]; then target="$project_root/.claude/settings.json"
else
  if [ -n "$cfg_dir" ]; then target="$cfg_dir/settings.json"
  elif [ -n "$home_override" ]; then target="$home_override/.claude/settings.json"
  elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then target="$CLAUDE_CONFIG_DIR/settings.json"
  else target="${HOME:-/tmp}/.claude/settings.json"; fi
fi

# ---- hook command prefix: portable $CLAUDE_PROJECT_DIR form when possible ----
prefix="$CONST_ROOT"; portable=0
if [ "$scope" = project ] && [ -z "$settings_file" ]; then
  pr="${project_root%/}"
  case "$CONST_ROOT" in "$pr"/*) prefix="\$CLAUDE_PROJECT_DIR/${CONST_ROOT#"$pr"/}"; portable=1 ;; esac
fi
hk() { printf 'bash "%s/scripts/label-sync/hooks/%s"' "$prefix" "$1"; }
sl_cmd() {
  local r="$render_path"
  [ "$portable" = 1 ] && case "$r" in "${project_root%/}"/*) r="\$CLAUDE_PROJECT_DIR/${r#"${project_root%/}"/}" ;; esac
  printf 'bash "%s"' "$r"
}

# ---- desired spec ---------------------------------------------------------
spec="$(jq -nc \
  --arg ss "$(hk label-sync-session-start.sh)"   --arg up "$(hk label-sync-prompt.sh)" \
  --arg ar "$(hk label-sync-agent-register.sh)"  --arg sa "$(hk label-sync-subagent-start.sh)" \
  --arg so "$(hk label-sync-subagent-stop.sh)"   --arg st "$(hk label-sync-stop.sh)" \
  --arg se "$(hk label-sync-session-end.sh)"     --arg ms "$(hk label-sync-model-switch.sh)" \
  --argjson wm "$with_model" '
  def h($c): {type:"command",command:$c,timeout:5};
  [ {event:"SessionStart",     matcher:"*",          script:"label-sync-session-start.sh",   hook:h($ss)},
    {event:"UserPromptSubmit", matcher:null,         script:"label-sync-prompt.sh",          hook:h($up)},
    {event:"PreToolUse",       matcher:"Agent|Task", script:"label-sync-agent-register.sh",  hook:h($ar)},
    {event:"SubagentStart",    matcher:"*",          script:"label-sync-subagent-start.sh",  hook:h($sa)},
    {event:"SubagentStop",     matcher:"*",          script:"label-sync-subagent-stop.sh",   hook:h($so)},
    {event:"Stop",             matcher:null,         script:"label-sync-stop.sh",            hook:h($st)},
    {event:"SessionEnd",       matcher:"*",          script:"label-sync-session-end.sh",     hook:h($se)} ]
  + (if $wm==1 then [ {event:"PostModelSwitch", matcher:"*", script:"label-sync-model-switch.sh", hook:h($ms)} ] else [] end)')"

# ---- read + validate the current settings ---------------------------------
if [ -e "$target" ]; then
  if ! jq -e 'type=="object"' "$target" >/dev/null 2>&1; then
    echo "install_label_sync: REFUSED — $target is not a valid JSON object; not touching it. Fix or move the file, then re-run." >&2
    exit 1
  fi
  cur="$(jq . "$target")"
else
  cur='{}'
fi

# ---- the structural merge (install) / removal (uninstall) ------------------
JQ_LIB='
def isours($sc): ((.command // "") | contains("label-sync/hooks/" + $sc));
def isanyours: ((.command // "") | test("label-sync/hooks/label-sync-[a-z-]+\\.sh"));
def positions($e; $sc): [ .hooks[$e] | to_entries[] | .key as $gi | (.value.hooks // []) | to_entries[] | select(.value|isours($sc)) | [$gi,.key] ];
'
install_prog="$JQ_LIB"'
reduce $spec[] as $s (.;
  .hooks = (.hooks // {}) | .hooks[$s.event] = (.hooks[$s.event] // [])
  | positions($s.event; $s.script) as $p
  | if ($p|length)==0 then
      ( [ .hooks[$s.event] | to_entries[] | select((.value.matcher // "") == ($s.matcher // "")) | .key ] | .[0] ) as $gi
      | if $gi == null then
          .hooks[$s.event] += [ ( (if $s.matcher != null then {matcher:$s.matcher} else {} end) + {hooks:[$s.hook]} ) ]
        else .hooks[$s.event][$gi].hooks += [$s.hook] end
    else
      reduce ($p[1:] | reverse)[] as $d (.; del(.hooks[$s.event][$d[0]].hooks[$d[1]]))
      | .hooks[$s.event][$p[0][0]].hooks[$p[0][1]] = $s.hook
    end)
| if $sl == null then . else
    ( if .statusLine == null then .statusLine = $sl
      elif (.statusLine == $sl) or (.statusLine|isanyours or ((.command // "")|contains("label-sync")) ) then .statusLine = $sl
      else . end ) end'
uninstall_prog="$JQ_LIB"'
(if .hooks then
   .hooks |= with_entries(
       .value |= ( map( if (.hooks|type)=="array" then (.hooks |= map(select(isanyours|not))) else . end )
                   | map(select((.hooks|type)!="array" or (.hooks|length)>0)) ) )
   | .hooks |= with_entries(select((.value|length)>0))
   | (if (.hooks|length)==0 then del(.hooks) else . end)
 else . end)
| (if (.statusLine != null) and ((.statusLine == $sl) or ((.statusLine.command // "")|contains("label-sync"))) then del(.statusLine) else . end)'

sl_json="$(jq -nc --arg c "$(sl_cmd)" '{type:"command",command:$c}')"      # the entry WE would wire
[ "$no_status" = 1 ] && [ "$uninstall" = 0 ] && sl_json='null'                  # --no-statusline: leave statusLine alone

if [ "$uninstall" = 1 ]; then
  new="$(printf '%s' "$cur" | jq --argjson sl "$sl_json" "$uninstall_prog")" || { echo "install_label_sync: jq merge failed" >&2; exit 2; }
else
  new="$(printf '%s' "$cur" | jq --argjson spec "$spec" --argjson sl "$sl_json" "$install_prog")" || { echo "install_label_sync: jq merge failed" >&2; exit 2; }
fi

# ---- foreign statusLine note ----------------------------------------------
if [ "$uninstall" = 0 ] && [ "$no_status" = 0 ]; then
  if [ "$(printf '%s' "$cur" | jq '(.statusLine != null) and ((.statusLine.command // "")|contains("label-sync")|not)')" = true ]; then
    echo "note: existing statusLine in $target is not label-sync's — left untouched (preserve-everything rule); label-sync statusLine NOT wired."
  fi
fi

# ---- platforms ------------------------------------------------------------
if [ "$platform" = all ]; then
  echo "platform claude: handled by this run."
  echo "platform opencode/gemini/qwen: SKIP — no Claude-style hook/statusLine interface wired by this installer (UNSUPPORTED here); label-sync state is still readable on those platforms via scripts/label-sync/labelctl.sh."
fi

# ---- unchanged? -----------------------------------------------------------
if [ "$new" = "$cur" ]; then
  echo "label-sync: $target already $([ "$uninstall" = 1 ] && echo clean || echo wired) — no change."
  exit 0
fi

# ---- dry-run: show, do not write ------------------------------------------
if [ "$apply" = 0 ]; then
  if [ "$brief" = 1 ]; then
    n="$(diff <(printf '%s\n' "$cur") <(printf '%s\n' "$new") | grep -c '^[<>]')"
    echo "label-sync: WOULD $([ "$uninstall" = 1 ] && echo remove || echo wire) label-sync hooks in $target ($n changed line(s)). Dry-run: nothing written. Re-run with --apply (or set LABEL_SYNC_AUTOWIRE=apply for post_update_hook.sh)."
  else
    diff -u --label "$target (current)" --label "$target (after)" <(printf '%s\n' "$cur") <(printf '%s\n' "$new")
    echo "label-sync: dry-run — nothing written. Re-run with --apply to write (a backup is made first)."
  fi
  if [ "$uninstall" = 0 ] && [ "$no_status" = 0 ] && [ ! -f "$render_path" ]; then
    echo "note: statusLine renderer not found: $render_path — --apply will refuse (exit 2) until it exists, or use --no-statusline."
  fi
  exit 0
fi

# ---- apply: preconditions (assert the REAL conditions, §11.4.201) ----------
if [ "$uninstall" = 0 ]; then
  if [ "$no_status" = 0 ] && [ "$(printf '%s' "$new" | jq --argjson sl "$sl_json" '.statusLine == $sl')" = true ] && [ ! -f "$render_path" ]; then
    echo "install_label_sync: statusLine renderer missing: $render_path — refusing to wire a statusLine that cannot run. Nothing written. (Provide it, or pass --no-statusline to wire the hooks only.)" >&2
    exit 2
  fi
  for s in label-sync-session-start label-sync-prompt label-sync-agent-register label-sync-subagent-start label-sync-subagent-stop label-sync-stop label-sync-session-end; do
    [ -f "$CONST_ROOT/scripts/label-sync/hooks/$s.sh" ] || { echo "install_label_sync: hook script missing: $CONST_ROOT/scripts/label-sync/hooks/$s.sh — nothing written." >&2; exit 2; }
  done
fi

mkdir -p "$(dirname "$target")" || { echo "install_label_sync: cannot create $(dirname "$target")" >&2; exit 2; }
if [ -e "$target" ]; then
  ts="$(date -u +%Y%m%dT%H%M%SZ)"; bak="$target.label-sync.bak.$ts"; n=0
  while [ -e "$bak" ]; do n=$((n + 1)); bak="$target.label-sync.bak.$ts.$n"; done
  cp -p "$target" "$bak" || { echo "install_label_sync: backup failed — nothing written." >&2; exit 2; }
  echo "backup: $bak"
fi
tmp="$(mktemp "$target.XXXXXX")" || { echo "install_label_sync: cannot create temp file" >&2; exit 2; }
printf '%s\n' "$new" >"$tmp"
if ! jq -e 'type=="object"' "$tmp" >/dev/null 2>&1; then rm -f "${tmp:?}"; echo "install_label_sync: produced invalid JSON — aborted, target untouched." >&2; exit 2; fi
mv "$tmp" "$target" || { rm -f "${tmp:?}"; echo "install_label_sync: could not replace $target" >&2; exit 2; }
echo "label-sync: $([ "$uninstall" = 1 ] && echo removed || echo wired) hooks in $target"
exit 0
