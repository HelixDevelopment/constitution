#!/usr/bin/env bash
# scripts/generate_agent_prefix_commands.sh
#
# Generate the per-agent LAYER-2 slash-command equivalents of every registry
# action (§11.4.140). For agents that expose generated/custom commands but no
# pre-submit hook (Gemini CLI, Qwen Code, OpenAI Codex CLI), a `/background ...`
# slash command is the mechanical convenience that mirrors the free-form
# `BACKGROUND :: ...` prefix the LAYER-1 carrier block already makes work.
#
# Adding a new registry action → re-run this generator → its slash command appears
# for every supported agent. No per-action code change (registry is data).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
#   Emit, for each action NAME in actions/registry.yaml:
#     plugins/helix/commands/<name>.md       (Claude Code plugin slash command)
#     actions/generated/gemini/<name>.toml   (Gemini CLI custom command)
#     actions/generated/qwen/<name>.toml     (Qwen Code custom command)
#     actions/generated/codex/<name>.md      (OpenAI Codex CLI prompts/ file)
#   Each embeds the action's expansion text and forwards the user's argument
#   (the actual task) after it.
#
#   Claude Code (§11.4.140 forms 3 + 4): the plugin `helix` exposes every action
#   as BOTH a bare command `/<name>` (form 3 — honored unless a host built-in
#   collides) AND the plugin-namespaced `/helix:<name>` (form 4 — ALWAYS
#   unambiguous; Claude Code's own plugin namespacing IS the `PREFIX::ACTION`
#   escape). A `default-<name>` alias is ALSO emitted for cross-agent parity, so
#   `/default-<name>` is a collision-free invocation on EVERY agent.
#   Bare-name collisions are declared as data in the registry
#   (`slash_conflicts:`) and surfaced in each command's frontmatter/body — the
#   plugin NEVER silently shadows a host command (Claude Code resolves a
#   colliding bare name to its own built-in; the user types `/helix:<name>`).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash scripts/generate_agent_prefix_commands.sh
#   HELIX_ACTION_REGISTRY=/path/to/registry.yaml \
#       bash scripts/generate_agent_prefix_commands.sh
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   $HELIX_ACTION_REGISTRY (optional) registry path; defaults via the library.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Generated command files under actions/generated/<agent>/ (overwritten each
#   run; deterministic; safe to re-run), plus the two README.md files.
#   Transient: staging dirs `.gen.XXXXXX` inside each destination dir (commands/,
#   gemini/, qwen/, codex/, plugins/helix/, actions/generated/); removed on exit
#   (also on TERM/INT); a kill -9 leaves them, and the next run reaps them.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates/overwrites files under actions/generated/ and plugins/helix/commands/
#   (atomic per-file rename from the staging dirs; stale marker-carrying files are
#   pruned only after the new set is in place). Holds an exclusive flock on
#   actions/generated for the whole run (concurrent runs queue; HELIX_GEN_LOCK_WAIT
#   seconds, default 300, then fail closed). Reaps leftover `.gen.*` dirs of dead runs.
#   Aborts with nothing changed on an invalid registry, zero actions, an action whose
#   expansion cannot be looked up, or a staged-file count that differs from the
#   registry's action count x 2 per agent. No network.
#   Honest limit: each file is replaced atomically, but the SET is not one transaction. A FIRST-EVER run
#   (no previous output) or a newly added action killed in the middle of the commit loop leaves some
#   agents with the new file and others without it until the next run completes (re-run to converge);
#   already existing files are always either their previous or their new version.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   scripts/action_prefix_lib.sh, flock(1).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (mandate), §11.4.28 (decoupling), §11.4.67 (parse-clean).
#
# Classification: universal (§11.4.17)

set -euo pipefail

gen_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=/dev/null
. "$gen_dir/action_prefix_lib.sh"

const_root="$(cd "$gen_dir/.." >/dev/null 2>&1 && pwd)"
# $HELIX_ACTION_OUT_ROOT redirects ALL generated output (tests / dry-runs point it
# at a sandbox). Without it, output always lands in this constitution checkout —
# so pointing $HELIX_ACTION_REGISTRY at a foreign registry would otherwise rewrite
# the REAL command tree from it. Input and output are now independently steerable.
gen_root="${HELIX_ACTION_OUT_ROOT:-$const_root}"
out_root="$gen_root/actions/generated"
# Claude Code plugin: the commands ARE the plugin's slash commands, so they are
# generated straight into the plugin tree (single source of truth — no copy).
claude_plugin_dir="$gen_root/plugins/helix"
claude_cmd_dir="$claude_plugin_dir/commands"
# HELIX_GEN_LOCK_WAIT: whole seconds, 0..99999. Set-but-empty, non-integer or negative fails closed
# BEFORE anything is created (an unvalidated value reaches flock -w and is misread or errors obscurely).
gen_lock_wait="${HELIX_GEN_LOCK_WAIT-300}"
case "$gen_lock_wait" in
  ''|*[!0-9]*|??????*) echo "generate_agent_prefix_commands: HELIX_GEN_LOCK_WAIT must be a whole number of seconds (0-99999), got '${gen_lock_wait}'; aborting (nothing changed)" >&2; exit 2 ;;
esac
mkdir -p "$out_root/gemini" "$out_root/qwen" "$out_root/codex" "$claude_cmd_dir"

# ATOMIC generation (11.4.224 / 9.2). Forensic: the former prune-then-write order
# left tracked command files missing after a kill mid-run. Now: (1) every output
# is written into a staging dir INSIDE its destination dir (same filesystem, so the
# final mv is an atomic rename), (2) validated against the registry's action count,
# (3) renamed into place one file at a time, and only THEN (4) marker-carrying files
# that are not in the staged set are pruned. A kill at any point leaves every
# previously-generated file in place.
# Concurrency: an exclusive flock on the output root serialises runs (bounded wait,
# HELIX_GEN_LOCK_WAIT seconds, default 300; fail closed on timeout). Because the lock is
# held for the whole run, any .gen.* dir found at start belongs to a dead run (kill
# released its lock) and is reaped; a live sibling's staging dir is never touched.
apx_marker='Generated by scripts/generate_agent_prefix_commands.sh'
# Test-only checkpoint hook: honoured ONLY with HELIX_TEST_MODE=1 and a pause dir under the
# temp root. Polls for $dir/release.<point> every 0.1 s (max 60 s) so a TERM trap fires promptly.
gen_pause() {
  [ "${HELIX_TEST_MODE:-}" = 1 ] && [ "${HELIX_GEN_PAUSE_AT:-}" = "$1" ] && [ -n "${HELIX_GEN_PAUSE_DIR:-}" ] || return 0
  local real tmp i
  tmp="$(readlink -m -- "${TMPDIR:-/tmp}")"; real="$(readlink -m -- "$HELIX_GEN_PAUSE_DIR")"
  [ "$tmp" != "/" ] && [ "${real#"$tmp"/}" != "$real" ] || return 0
  : > "$real/reached.$1"
  for ((i = 0; i < 600; i++)); do [ -e "$real/release.$1" ] && return 0; sleep 0.1; done
}
# Staging-dir removal. scripts/lib/safe_rm.sh (11.4.287) is deliberately NOT sourced:
# this generator is copied ALONE (with action_prefix_lib.sh) into sandboxes by
# CM-CLI-AGENT-PLUGINS-WIRED and tests/test_cli_agent_plugins.sh, where lib/ is absent.
# Instead the target is constrained here: it must be a real (non-symlink) directory whose
# basename is exactly .gen.XXXXXX, and the variable is ${VAR:?}-guarded.
apx_rm_stage() {
  local p="${1:?apx_rm_stage: empty path}"
  case "${p##*/}" in .gen.??????) ;; *) echo "generate_agent_prefix_commands: refusing to remove non-staging path: $p" >&2; return 1 ;; esac
  [ -d "$p" ] && [ ! -L "$p" ] || { echo "generate_agent_prefix_commands: refusing to remove non-directory or symlink: $p" >&2; return 1; }
  rm -rf -- "${p:?}"
}

command -v flock >/dev/null 2>&1 || { echo "generate_agent_prefix_commands: flock is required; aborting (nothing changed)" >&2; exit 1; }
exec 9< "$out_root" || { echo "generate_agent_prefix_commands: cannot open $out_root for locking; aborting" >&2; exit 1; }
flock -w "$gen_lock_wait" 9 || { echo "generate_agent_prefix_commands: timed out waiting for the output-root lock; aborting (nothing changed)" >&2; exit 1; }

dest_dirs=("$claude_cmd_dir" "$out_root/gemini" "$out_root/qwen" "$out_root/codex" "$claude_plugin_dir" "$out_root")
# Reap stray staging dirs. We hold the exclusive lock, and every live run holds it for its whole
# life, so a conforming real directory (.gen.XXXXXX) found here belongs to a dead run. Anything
# else named .gen.* (a file, a symlink, a dir of another name shape) is NOT ours: warn, leave it
# untouched, and carry on (apx_rm_stage refuses it) -- a stray never blocks or pollutes a run.
for _d in "${dest_dirs[@]}"; do
  for _o in "$_d"/.gen.*; do
    { [ -e "$_o" ] || [ -L "$_o" ]; } || continue
    apx_rm_stage "$_o" || echo "generate_agent_prefix_commands: left stray non-staging path in place: $_o" >&2
  done
done
stages=()
apx_cleanup() { local s; for s in "${stages[@]}"; do apx_rm_stage "$s" || true; done; }
# bash runs the EXIT trap on TERM/INT/HUP too (verified by test (4)); only kill -9 skips it.
trap apx_cleanup EXIT
stage_claude="$(mktemp -d "$claude_cmd_dir/.gen.XXXXXX")"; stages+=("$stage_claude")
stage_gemini="$(mktemp -d "$out_root/gemini/.gen.XXXXXX")"; stages+=("$stage_gemini")
stage_qwen="$(mktemp -d "$out_root/qwen/.gen.XXXXXX")"; stages+=("$stage_qwen")
stage_codex="$(mktemp -d "$out_root/codex/.gen.XXXXXX")"; stages+=("$stage_codex")
stage_plugin="$(mktemp -d "$claude_plugin_dir/.gen.XXXXXX")"; stages+=("$stage_plugin")
stage_root="$(mktemp -d "$out_root/.gen.XXXXXX")"; stages+=("$stage_root")

# Commit every staged file of STAGE into DEST (atomic per-file rename).
apx_commit() {
  local stg="$1" dest="$2" f b
  [ -d "$dest" ] || { echo "generate_agent_prefix_commands: commit destination is not a directory: $dest" >&2; return 1; }
  for f in "$stg"/*; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    # -T: never treat an existing destination directory as "move INTO it" (silent mis-placement).
    mv -fT -- "$f" "$dest/$b" || { echo "generate_agent_prefix_commands: commit failed moving $b into $dest" >&2; return 1; }
    [ -f "$dest/$b" ] && [ ! -e "$f" ] || { echo "generate_agent_prefix_commands: commit of $b into $dest not confirmed" >&2; return 1; }
  done
  return 0
}
apx_commit_all() { apx_commit "$@" || { echo "generate_agent_prefix_commands: commit aborted; every file is either its previous or its new version (nothing deleted)" >&2; exit 1; }; }
# PRUNE stale artefacts AFTER the new set is in place: an action REMOVED from the
# registry must not leave its command file behind (a silent lie). Only files that
# carry our GENERATED marker AND whose basename is not in the staged set are
# deleted; hand-written files are never touched (9.2).
apx_prune() {  # $1=dir $2=staged-name-list (newline separated) $3=glob-ext
  local dir="$1" keep="$2" ext="$3" f b
  for f in "$dir"/*."$ext"; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    printf '%s\n' "$keep" | grep -qxF -- "$b" && continue
    if grep -qs "$apx_marker" "$f"; then rm -f -- "$f"; fi
  done
}

# Lowercase a NAME for the slash-command filename / token.
apx_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Read one scalar/list field of an action from the registry (data, not code —
# §11.4.28). Prints empty on any failure; callers fall back to a generic value.
# `slash_conflicts` is emitted space-separated.
apx_gen_field() {
  local name="$1" field="$2" reg
  reg="$(apx_registry_path)" || return 0
  python3 - "$reg" "$name" "$field" <<'PYEOF' 2>/dev/null || true
import sys
try:
    import yaml
except Exception:
    sys.exit(0)
reg, name, field = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(reg) as fh:
        doc = yaml.safe_load(fh) or {}
except Exception:
    sys.exit(0)
for a in (doc.get("actions") or []):
    if a.get("name") == name:
        v = a.get(field)
        if v is None:
            break
        if isinstance(v, (list, tuple)):
            print(" ".join(str(x) for x in v))
        else:
            print(" ".join(str(v).split()))
        break
PYEOF
}

if ! apx_validate_registry >/dev/null 2>&1; then
  echo "generate_agent_prefix_commands: registry failed validation; aborting" >&2
  exit 1
fi

# Per-agent emit helpers. Each emits ONE command file under <agent>/<basename>
# embedding the expansion + the agent's forward-arg token. `$1`=basename,
# `$2`=display-name, `$3`=expansion.
apx_emit_toml() {  # for Gemini + Qwen (identical TOML shape, {{args}} forward)
  local dir="$1" base="$2" disp="$3" exp="$4"
  {
    printf '# Generated by scripts/generate_agent_prefix_commands.sh (§11.4.140). DO NOT EDIT.\n'
    printf '# Source of truth: actions/registry.yaml action %s.\n' "$disp"
    printf 'description = "Action-prefix %s: run the task with the registered expansion applied."\n' "$disp"
    printf 'prompt = """\n'
    printf '%s\n\n' "$exp"
    printf '{{args}}\n'
    printf '"""\n'
  } > "$dir/$base.toml"
}
apx_emit_codex_md() {  # OpenAI Codex CLI prompt file ($ARGUMENTS forward)
  local dir="$1" base="$2" disp="$3" exp="$4"
  {
    printf '<!-- Generated by scripts/generate_agent_prefix_commands.sh (§11.4.140). DO NOT EDIT. -->\n'
    printf '<!-- Source of truth: actions/registry.yaml action %s. -->\n\n' "$disp"
    printf '%s\n\n' "$exp"
    printf '$ARGUMENTS\n'
  } > "$dir/$base.md"
}

# Claude Code plugin slash command (YAML frontmatter + $ARGUMENTS forward).
#   $1=dir $2=basename $3=display-name $4=expansion $5=description
#   $6=space-separated colliding host command names ("" when none)
apx_emit_claude_md() {
  local dir="$1" base="$2" disp="$3" exp="$4" desc="$5" conflicts="$6"
  {
    printf -- '---\n'
    # Quote + escape the description so a `:` inside it can never break YAML.
    printf 'description: "%s"\n' "$(printf '%s' "$desc" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf 'argument-hint: "[the task — everything after the action name]"\n'
    printf -- '---\n\n'
    printf '<!-- Generated by scripts/generate_agent_prefix_commands.sh (§11.4.140). DO NOT EDIT. -->\n'
    printf '<!-- Source of truth: actions/registry.yaml action %s. Re-run the generator to update. -->\n\n' "$disp"
    if [ -n "$conflicts" ]; then
      printf '<!-- CONFLICT (registry `slash_conflicts`): the bare form `/%s` collides with a host\n' "$base"
      printf '     built-in (%s). Claude Code resolves the bare name to its OWN built-in; invoke this\n' "$conflicts"
      printf '     action as `/helix:%s` (always unambiguous) or `/default-%s`. This plugin NEVER\n' "$base" "$base"
      printf '     silently shadows a host command. -->\n\n'
    fi
    printf '%s\n\n' "$exp"
    printf '$ARGUMENTS\n'
  } > "$dir/$base.md"
}

count=0
# Expected number of actions comes from the registry itself (not from this loop).
n_actions="$(apx_list_actions | grep -c . || true)"
[ "$n_actions" -ge 1 ] || { echo "generate_agent_prefix_commands: registry lists no actions; aborting (nothing changed)" >&2; exit 1; }
claude_rows=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  expansion="$(apx_lookup_expansion "$name")" || { echo "generate_agent_prefix_commands: no expansion for action $name; aborting (nothing changed)" >&2; exit 1; }
  lc="$(apx_lc "$name")"

  # Per-action metadata (data-driven; generic fallbacks keep this non-fatal).
  summary="$(apx_gen_field "$name" summary)"
  [ -n "$summary" ] || summary="Action-prefix $name: run the task with the registered expansion applied."
  conflicts="$(apx_gen_field "$name" slash_conflicts)"

  # ── Form 3 — bare slash command `/<name>` ────────────────────────────────
  #   Claude Code: plugins/helix/commands/<name>.md  (also gives /helix:<name>)
  #   Gemini CLI : .gemini/commands/<name>.toml
  #   Qwen Code  : .qwen/commands/<name>.toml
  #   Codex CLI  : prompts/<name>.md
  apx_emit_claude_md "$stage_claude" "$lc" "$name" "$expansion" "$summary" "$conflicts"
  apx_emit_toml    "$stage_gemini" "$lc" "$name" "$expansion"
  apx_emit_toml    "$stage_qwen"   "$lc" "$name" "$expansion"
  apx_emit_codex_md "$stage_codex"  "$lc" "$name" "$expansion"

  # ── Form 4 — namespaced slash command `/DEFAULT::<name>` ──────────────────
  # `::` is NOT a legal character in these agents' command names (the command
  # name is its filename / token), so we emit a `default-<name>` ALIAS that maps
  # to the identical expansion. Collision fallback: if `/<name>` (form 3) ever
  # collides with a host built-in command on a given agent, this alias is the
  # always-safe invocation (it mirrors the form-4 `/DEFAULT::<name>` semantics
  # the agent cannot express literally). Same expansion → equivalence preserved.
  ns_base="default-$lc"
  apx_emit_claude_md "$stage_claude" "$ns_base" "DEFAULT::$name" "$expansion" \
    "$summary (collision-free alias of /$lc)" ""
  apx_emit_toml    "$stage_gemini" "$ns_base" "DEFAULT::$name" "$expansion"
  apx_emit_toml    "$stage_qwen"   "$ns_base" "DEFAULT::$name" "$expansion"
  apx_emit_codex_md "$stage_codex"  "$ns_base" "DEFAULT::$name" "$expansion"

  # A summary may legitimately contain `|` (e.g. "{Bug | Feature | Task}"), which
  # would break the markdown table — escape it for the cell.
  summary_cell="$(printf '%s' "$summary" | sed 's/|/\\|/g')"
  if [ -n "$conflicts" ]; then
    claude_rows="${claude_rows}| \`/helix:${lc}\` | \`/${lc}\` **COLLIDES** with host \`${conflicts}\` → use \`/helix:${lc}\` or \`/default-${lc}\` | ${summary_cell} |
"
  else
    claude_rows="${claude_rows}| \`/${lc}\` | \`/helix:${lc}\` · \`/default-${lc}\` | ${summary_cell} |
"
  fi

  count=$((count+1))
done <<APXEOF
$(apx_list_actions)
APXEOF

# Plugin README — regenerated so the command inventory can never drift from the
# registry (§11.4.12 / §11.4.60 always-in-sync).
{
  printf '# `helix` — Claude Code plugin (action directives + commands)\n\n'
  printf '**GENERATED** by `scripts/generate_agent_prefix_commands.sh` from `actions/registry.yaml`.\n'
  printf 'DO NOT EDIT BY HAND — add a registry row and re-run the generator.\n\n'
  printf 'Every registered §11.4.140 action is exposed as a Claude Code slash command.\n\n'
  printf '| Invoke | Always-unambiguous form | What it does |\n'
  printf '|---|---|---|\n'
  printf '%s\n' "$claude_rows"
  printf '## Conflict rule (§11.4.140)\n\n'
  printf 'A bare `/<name>` is honored ONLY when it does not collide with a host built-in\n'
  printf '(declared as data in the registry `slash_conflicts:` field). The plugin-namespaced\n'
  printf '`/helix:<name>` is ALWAYS unambiguous — Claude Code plugin namespacing IS the\n'
  printf '§11.4.140 form-4 `PREFIX::ACTION` escape. `/default-<name>` is a third,\n'
  printf 'collision-free form that works identically on every supported CLI agent.\n\n'
  printf 'The plugin NEVER silently shadows a host command: on a collision Claude Code\n'
  printf 'resolves the bare name to its own built-in, and the colliding command file says so.\n\n'
  printf 'Install: see `docs/actions/QUICKSTART_INSTALL.md` (one command, or fully automatic\n'
  printf 'on every constitution pull via `scripts/post_update_hook.sh` per §11.4.164).\n'
} > "$stage_plugin/README.md"

# A small README so the generated tree is self-explaining + the install script
# knows where to symlink/copy from.
{
  printf '# Generated action-prefix slash commands (§11.4.140)\n\n'
  printf 'Auto-generated by `scripts/generate_agent_prefix_commands.sh` from\n'
  printf '`actions/registry.yaml`. DO NOT EDIT BY HAND — re-run the generator.\n\n'
  printf 'Two slash forms per action (GRAMMAR_ADDENDUM §11.4.140):\n\n'
  printf '%s\n' '- **`<name>`** — the bare slash form 3 `/<name>`.'
  printf '%s\n' '- **`default-<name>`** — the namespaced slash form 4 `/DEFAULT::<name>`'
  printf '%s\n' '  alias (these agents disallow `::` in a command name). It maps to the'
  printf '%s\n' '  IDENTICAL expansion, so `/<name>` ≡ `/default-<name>`. **Collision'
  printf '%s\n' '  fallback:** if `/<name>` ever collides with a host built-in command on'
  printf '%s\n' '  a given agent, invoke `/default-<name>` (the always-safe form-4'
  printf '%s\n\n' '  equivalent).'
  printf 'Per-agent install targets (the install script wires these by reference):\n\n'
  printf '| Agent | Source here | Install location (consuming project) |\n'
  printf '|---|---|---|\n'
  printf '| Gemini CLI | `gemini/<name>.toml`, `gemini/default-<name>.toml` | `.gemini/commands/` |\n'
  printf '| Qwen Code  | `qwen/<name>.toml`, `qwen/default-<name>.toml`     | `.qwen/commands/` |\n'
  printf '| Codex CLI  | `codex/<name>.md`, `codex/default-<name>.md`       | `prompts/` |\n\n'
  printf 'Generated %s action(s) (each as a bare + a `default-` namespaced command).\n' "$count"
} > "$stage_root/README.md"

# Validate the staged set against the REGISTRY's action count before touching the real
# tree: every action must have produced a bare + a default- file for each agent. A count
# derived from the same loop that stages the files would be circular, so the expectation
# comes from apx_list_actions (n_actions); zero actions and any dropped / colliding
# (lowercase) action abort with nothing changed.
for _d in "$stage_claude" "$stage_gemini" "$stage_qwen" "$stage_codex"; do
  _n="$(find "$_d" -maxdepth 1 -type f | wc -l)"
  if [ "$_n" -ne $((n_actions*2)) ]; then
    echo "generate_agent_prefix_commands: staged $_n file(s) in ${_d##*/}, expected $((n_actions*2)) (${n_actions} registry action(s)); aborting (nothing changed)" >&2
    exit 1
  fi
done
[ "$count" -eq "$n_actions" ] || { echo "generate_agent_prefix_commands: generated $count of $n_actions action(s); aborting (nothing changed)" >&2; exit 1; }
[ -s "$stage_plugin/README.md" ] && [ -s "$stage_root/README.md" ] || { echo "generate_agent_prefix_commands: empty staged README; aborting (nothing changed)" >&2; exit 1; }
keep_claude="$(ls "$stage_claude")"; keep_gemini="$(ls "$stage_gemini")"
keep_qwen="$(ls "$stage_qwen")"; keep_codex="$(ls "$stage_codex")"
gen_pause after_stage
_i=0
for _pair in "$stage_claude:$claude_cmd_dir" "$stage_gemini:$out_root/gemini" "$stage_qwen:$out_root/qwen" "$stage_codex:$out_root/codex"; do
  apx_commit_all "${_pair%%:*}" "${_pair#*:}"
  _i=$((_i+1)); [ "$_i" -eq 2 ] && gen_pause mid_commit
done
apx_commit_all "$stage_plugin" "$claude_plugin_dir"
apx_commit_all "$stage_root" "$out_root"
gen_pause before_prune
apx_prune "$claude_cmd_dir" "$keep_claude" md
apx_prune "$out_root/gemini" "$keep_gemini" toml
apx_prune "$out_root/qwen" "$keep_qwen" toml
apx_prune "$out_root/codex" "$keep_codex" md

echo "generate_agent_prefix_commands: generated $count action(s) under $out_root" >&2
