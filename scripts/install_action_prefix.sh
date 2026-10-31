#!/usr/bin/env bash
# scripts/install_action_prefix.sh
#
# Idempotent installer that wires the universal "ACTION_NAME ::" prompt-prefix
# system (§11.4.140) into a consuming project: (1) registers the Claude Code
# UserPromptSubmit hook in the project's .claude/settings.json (referencing the
# constitution path BY REFERENCE — never copying the hook, per §11.4.80), and
# (2) regenerates the per-agent slash commands via
# scripts/generate_agent_prefix_commands.sh.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
#   Make the action-prefix system load out-of-the-box (the §11.4.75 install seam)
#   for any project that includes the constitution submodule.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/install_action_prefix.sh [PROJECT_ROOT]
#     PROJECT_ROOT defaults to the current working directory.
#   Re-running is safe + idempotent (the hook entry is added once).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   $1 (optional)            : project root (default: $PWD)
#   $HELIX_ACTION_REGISTRY   : optional registry override, forwarded to the gen.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   <project>/.claude/settings.json   : UserPromptSubmit hook entry added/kept.
#   actions/generated/<agent>/*       : regenerated slash commands.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Edits the project's .claude/settings.json (creating it if absent). A backup
#   is written to .claude/settings.json.bak before any modification. Files are
#   replaced by mktemp+rename (never written through); an existing settings.json keeps
#   its mode (stat -L), a NEW settings.json/.bak gets 0666 & ~umask. A hard-linked
#   settings.json only draws a warning. Invalid JSON is refused on both jq and python paths.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   jq (REQUIRED for safe JSON merge of settings.json). python3 fallback if jq
#   is absent. scripts/generate_agent_prefix_commands.sh.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (mandate), §11.4.75 (out-of-the-box install seam),
#   §11.4.80 (inherit-by-reference — hook path points at the constitution),
#   §11.4.28 (decoupling), §11.4.67 (parse-clean).
#
# Classification: universal (§11.4.17)

set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
const_root="$(cd "$self_dir/.." >/dev/null 2>&1 && pwd)"
project_root="${1:-$PWD}"
project_root="$(cd "$project_root" >/dev/null 2>&1 && pwd)"

hook_abs="$const_root/scripts/hooks/action_prefix_expand.sh"
[ -x "$hook_abs" ] || chmod +x "$hook_abs" 2>/dev/null || true
if [ ! -f "$hook_abs" ]; then
  echo "install_action_prefix: hook not found: $hook_abs" >&2
  exit 1
fi

# Compute the hook command as a RELATIVE path from the project root when the
# constitution lives under it (the by-reference inherit pattern); otherwise use
# the absolute path. Either way we NEVER copy the hook into the project.
hook_cmd="$hook_abs"
case "$const_root" in
  "$project_root"/*) hook_cmd="${const_root#"$project_root"/}/scripts/hooks/action_prefix_expand.sh" ;;
esac

settings_dir="$project_root/.claude"
settings="$settings_dir/settings.json"
# Containment BEFORE any write (mkdir/cp/mv): .claude, settings.json, .bak and .tmp must all
# resolve (symlinks followed, may not exist yet) strictly inside the project, else REFUSE.
proj_real="$(cd "$project_root" && pwd -P)"
for _p in "$settings_dir" "$settings" "$settings.bak" "$settings.tmp"; do
  _r="$(readlink -m -- "$_p" 2>/dev/null)" || _r=""
  case "$_r" in
    "$proj_real"/*) ;;
    *) echo "install_action_prefix: $_p resolves outside the project — REFUSED, nothing written" >&2; exit 1 ;;
  esac
done
mkdir -p "$settings_dir"
settings_dir_real="$(cd "$settings_dir" && pwd -P)"
case "$settings_dir_real" in
  "$proj_real"/*) ;;
  *) echo "install_action_prefix: $settings_dir resolves outside the project — REFUSED" >&2; exit 1 ;;
esac

# KNOWN LIMIT (TOCTOU): the containment and link-count checks above/below run BEFORE the writes; a
# local attacker who can swap a path component between check and use is NOT defended against
# (no openat/O_NOFOLLOW chain in shell). Hard links are handled by never writing THROUGH an
# existing inode: every file we create is a fresh mktemp file renamed into place (rename replaces
# the directory entry, it never follows or truncates the old inode).
# A settings.json with more than one hard link (for example after a `cp -al` snapshot) is NOT
# refused: nothing here writes through the inode (fresh mktemp inode + rename only, so the other
# links keep the old content); we only warn so the operator knows the other links stay stale.
if [ -e "$settings" ] && [ "$(stat -L -c %h -- "$settings" 2>/dev/null || echo 1)" -gt 1 ]; then
  echo "install_action_prefix: WARNING $settings has more than one hard link; it is replaced by a new file (rename), the other links keep the old content" >&2
fi

# Mode handling: mktemp creates 0600. A NEW file gets the umask-respecting mode (0666 & ~umask);
# an EXISTING file keeps its own mode (stat -L: follows a symlink, so a link to a 0644 file yields 644).
new_mode="$(printf '%03o' $(( 0666 & ~$(umask) )))"

# Seed an empty settings.json if missing (fresh inode, renamed into place).
if [ ! -f "$settings" ]; then
  _seed="$(mktemp "$settings_dir/.settings.seed.XXXXXX")" || exit 1
  printf '{}\n' > "$_seed" && chmod "$new_mode" "$_seed" && mv -f -- "$_seed" "$settings" || { rm -f -- "$_seed"; exit 1; }
fi
settings_mode="$(stat -L -c %a -- "$settings")"

# Backup via a fresh inode too: a pre-existing (possibly hard-linked) .bak is replaced, never written.
_bak="$(mktemp "$settings_dir/.settings.bak.XXXXXX")" || exit 1
if [ -e "$settings.bak" ]; then _bak_mode="$(stat -L -c %a -- "$settings.bak" 2>/dev/null || echo "$new_mode")"; else _bak_mode="$new_mode"; fi
cp -f -- "$settings" "$_bak" && chmod "$_bak_mode" "$_bak" && mv -f -- "$_bak" "$settings.bak" || { rm -f -- "$_bak"; exit 1; }

merge_with_jq() {
  local tmp
  tmp="$(mktemp "$settings_dir/.settings.new.XXXXXX")" || return 1
  if jq --arg cmd "$hook_cmd" '
    .hooks = (.hooks // {})
    | .hooks.UserPromptSubmit = (.hooks.UserPromptSubmit // [])
    # Only add our matcher group if no existing entry already references the hook.
    | if (.hooks.UserPromptSubmit
          | map(.hooks // [] | map(.command // "") | any(. == $cmd))
          | any(.)) then .
      else
        .hooks.UserPromptSubmit += [
          { "hooks": [ { "type": "command", "command": $cmd } ] }
        ]
      end
  ' "$settings" > "$tmp" && chmod "$settings_mode" "$tmp" && mv -f -- "$tmp" "$settings"; then
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

merge_with_python() {
  HELIX_HOOK_CMD="$hook_cmd" python3 - "$settings" <<'PYEOF'
import json, os, sys, tempfile
path = sys.argv[1]
cmd = os.environ["HELIX_HOOK_CMD"]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception as exc:
    sys.stderr.write("install_action_prefix: settings.json is not valid JSON (%s) - REFUSED, left unchanged\n" % exc)
    sys.exit(1)
if not isinstance(data, dict):
    sys.stderr.write("install_action_prefix: settings.json top level is not an object - REFUSED, left unchanged\n")
    sys.exit(1)
hooks = data.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])
def already():
    for grp in ups:
        for h in grp.get("hooks", []):
            if h.get("command") == cmd:
                return True
    return False
if not already():
    ups.append({"hooks": [{"type": "command", "command": cmd}]})
# Write a fresh inode next to the target and rename it into place: never write through the old inode.
mode = os.stat(path).st_mode & 0o7777
fd, tmp = tempfile.mkstemp(prefix=".settings.new.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, path)
except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PYEOF
}

if command -v jq >/dev/null 2>&1; then
  merge_with_jq || { echo "install_action_prefix: jq merge FAILED, settings.json left UNCHANGED (backup at $settings.bak)" >&2; exit 1; }
elif command -v python3 >/dev/null 2>&1; then
  merge_with_python || { echo "install_action_prefix: python merge FAILED, settings.json left UNCHANGED (backup at $settings.bak)" >&2; exit 1; }
else
  echo "install_action_prefix: need jq OR python3 to edit settings.json safely" >&2
  echo "install_action_prefix: settings.json left UNCHANGED (backup at $settings.bak)" >&2
  exit 1
fi

# Regenerate the per-agent slash commands (best-effort; non-fatal).
if [ -x "$const_root/scripts/generate_agent_prefix_commands.sh" ]; then
  env -u HELIX_ACTION_OUT_ROOT bash "$const_root/scripts/generate_agent_prefix_commands.sh" || \
    echo "install_action_prefix: slash-command generation reported a warning" >&2
fi

echo "install_action_prefix: wired UserPromptSubmit hook -> $hook_cmd" >&2
echo "install_action_prefix:   settings: $settings (backup: $settings.bak)" >&2
echo "install_action_prefix: done." >&2
