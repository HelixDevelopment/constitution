#!/usr/bin/env bash
# test_mcp_register_hardening.sh — review findings I-1, I-2, I-3 (+ M-1..M-3) for the
# jev MCP template port. Drives the REAL skills/jev-decision-layer/register.sh and the
# REAL scripts/post_update_hook.sh inside sandboxes; nothing touches the real home.
#   R. I-1 repair: an old v71-era `jev` entry holding an unexpanded ${...} placeholder
#      is removed from .mcp.json (backup first, other servers kept, valid JSON,
#      idempotent) by register.sh AND by the post-update hook when
#      mcp/jev-decisions.json was deleted. A user-customised jev entry (no placeholder)
#      is never touched.
#   A. I-2 atomic refusal: every rc-2 path leaves the sandbox tree byte-identical.
#   K. I-3 JEV_KEY_VAR must be a shell variable NAME; a key-shaped value is refused
#      and is never echoed.
#   S. M-1 single-pass substitution, M-2 JEV_MODE honoured, M-3 control characters.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
command -v jq >/dev/null 2>&1 || { assert_skip "jq absent"; finish; exit $?; }
command -v git >/dev/null 2>&1 || { assert_skip "git absent"; finish; exit $?; }
REG="$REPO/skills/jev-decision-layer/register.sh"
ROOTS=()
cleanup() { local r; for r in "${ROOTS[@]:-}"; do [ -n "$r" ] && rm -rf "$r"; done; }
trap cleanup EXIT
mk() { local d; d="$(mktemp -d)"; ROOTS+=("$d"); printf '%s' "$d"; }

# tree_sum <dir> : listing of every dir and every file with its checksum.
tree_sum() {
  ( cd "$1" && { find . -type d | LC_ALL=C sort; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum; } )
}
OLD_ENTRY='{"type":"stdio","command":"python3","args":["${CLAUDE_TOOLKIT_DIR}/scripts/jev_mcp.py"],"env":{"JEV_BASE_URL":"${JEV_BASE_URL}","JEV_CA_FILE":"${JEV_CA_FILE}"}}'
seed_old() { # seed_old <file> : old jev entry plus an unrelated server
  jq -n --argjson e "$OLD_ENTRY" '{mcpServers:{other:{command:"x",args:["a"]},jev:$e}}' > "$1"
}

# ── R1. register.sh repairs a stale entry ────────────────────────────────────
S="$(mk)"; mkdir -p "$S/.claude"; seed_old "$S/.mcp.json"
JEV_HOME="$S" JEV_TEST=1 JEV_NOW_EPOCH=1700000001 CLAUDE_TOOLKIT_DIR=/opt/tk bash "$REG" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "R1 register.sh rc 0 over a stale entry"
assert_file_exists "$S/.mcp.json.prejev.1700000001" "R1 timestamped backup of the old file exists"
assert_contains "$S/.mcp.json.prejev.1700000001" '${CLAUDE_TOOLKIT_DIR}' "R1 backup holds the ORIGINAL stale content"
assert_not_contains "$S/.mcp.json" '${' "R1 no unexpanded placeholder remains in .mcp.json"
assert_eq "/opt/tk/scripts/jev_mcp.py" "$(jq -r '.mcpServers.jev.args[0]' "$S/.mcp.json")" "R1 jev re-rendered with an absolute toolkit path"
assert_eq "a" "$(jq -r '.mcpServers.other.args[0]' "$S/.mcp.json")" "R1 unrelated server kept"
cp "$S/.mcp.json" "$S/after1"
JEV_HOME="$S" JEV_TEST=1 JEV_NOW_EPOCH=1700000002 CLAUDE_TOOLKIT_DIR=/opt/tk bash "$REG" >/dev/null 2>&1
assert_eq "$(sha256sum < "$S/after1")" "$(sha256sum < "$S/.mcp.json")" "R1 idempotent: second run changes nothing"
assert_file_absent "$S/.mcp.json.prejev.1700000002" "R1 second run makes no further backup"

# R1b user-customised jev entry without any placeholder is left alone
S="$(mk)"; mkdir -p "$S/.claude"
printf '%s\n' '{"mcpServers":{"jev":{"command":"python3","args":["/custom/jev_mcp.py"]}}}' > "$S/.mcp.json"
JEV_HOME="$S" bash "$REG" >/dev/null 2>&1
assert_eq "/custom/jev_mcp.py" "$(jq -r '.mcpServers.jev.args[0]' "$S/.mcp.json")" "R1b a clean user entry is never replaced"

# ── R2. the post-update hook repairs it when mcp/jev-decisions.json was deleted ─
base="$(mk)"; HOST_C="$base/const"; HOST_P="$base/proj"
mkdir -p "$HOST_C/scripts/jev" "$HOST_P/home"
cp "$REPO/scripts/post_update_hook.sh" "$HOST_C/scripts/post_update_hook.sh"
cp "$HERE/fixtures-shared/jev_scripts/bootstrap.sh" "$HOST_C/scripts/jev/bootstrap.sh"
printf '# c\n' > "$HOST_C/Constitution.md"; mkdir -p "$HOST_C/mcp"
printf '{"mcpServers":{"jev":%s}}\n' "$OLD_ENTRY" > "$HOST_C/mcp/jev-decisions.json"
unset TYPESAFE_BASE_URL JEV_BASE_URL   # hermetic: an ambient hosted base must not decide the S2 enforce case (r6 m6-2 reads the process env)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git -C "$HOST_C" init -q && git -C "$HOST_C" add -A && git -C "$HOST_C" commit -q -m v71
git -C "$HOST_C" rm -q mcp/jev-decisions.json && git -C "$HOST_C" commit -q -m v72
seed_old "$HOST_P/.mcp.json"; seed_old "$HOST_P/home/.mcp.json"
run_hook_host
assert_rc 0 "$HOOK_RC" "R2 hook rc 0"
assert_eq "false" "$(jq '.mcpServers | has("jev")' "$HOST_P/.mcp.json")" "R2 stale jev removed from the project .mcp.json"
assert_eq "x" "$(jq -r '.mcpServers.other.command' "$HOST_P/.mcp.json")" "R2 unrelated server kept in the project file"
assert_eq "false" "$(jq '.mcpServers | has("jev")' "$HOST_P/home/.mcp.json")" "R2 stale jev removed from ~/.mcp.json too"
nb="$(find "$HOST_P" -maxdepth 2 -name '.mcp.json.prejev*' | wc -l)"
assert_eq "2" "$nb" "R2 a timestamped backup was taken of each repaired file"
sum1="$(tree_sum "$HOST_P")"
run_hook_host
# only compare the .mcp.json files and backup count (hook.out / stub logs legitimately change)
assert_eq "2" "$(find "$HOST_P" -maxdepth 2 -name '.mcp.json.prejev*' | wc -l)" "R2 idempotent: no new backup on a second run"
assert_eq "false" "$(jq '.mcpServers | has("jev")' "$HOST_P/.mcp.json")" "R2 still absent after a second run"
: "$sum1"

# R2b hook leaves a clean user-customised jev entry alone
printf '%s\n' '{"mcpServers":{"jev":{"command":"python3","args":["/custom/jev_mcp.py"]}}}' > "$HOST_P/.mcp.json"
run_hook_host
assert_eq "/custom/jev_mcp.py" "$(jq -r '.mcpServers.jev.args[0]' "$HOST_P/.mcp.json")" "R2b hook never removes a clean user entry"

# ── A. I-2: rc 2 means nothing changed ──────────────────────────────────────
mkbox() { local d; d="$(mk)"; mkdir -p "$d/.claude" "$d/.kimi-code" "$d/.config/opencode"
  printf '{"x":1}\n' > "$d/.claude/settings.json"; printf '{"mcpServers":{}}\n' > "$d/.mcp.json"; printf '%s' "$d"; }
# shellcheck disable=SC2016  # the ${...} sequences are the literal test payload
for case_ in 'JEV_BASE_URL=https://${HOME}' 'CLAUDE_TOOLKIT_DIR=/opt/${JEV_BASE_URL}' 'JEV_MODEL=a${B}c'; do
  B="$(mkbox)"; before="$(tree_sum "$B")"
  env JEV_HOME="$B" "$case_" bash "$REG" >/dev/null 2>&1; rc=$?
  assert_rc 2 "$rc" "A placeholder-shaped value ($case_ ) refused with rc 2"
  assert_eq "$before" "$(tree_sum "$B")" "A rc 2 left the whole sandbox tree byte-identical"
done

# ── K. I-3: JEV_KEY_VAR must be a variable NAME ─────────────────────────────
fake="sk-""FAKE""-0123456789""abcdef"
B="$(mkbox)"; before="$(tree_sum "$B")"
out="$(JEV_HOME="$B" JEV_KEY_VAR="$fake" bash "$REG" 2>&1)"; rc=$?
assert_rc 2 "$rc" "K key-shaped JEV_KEY_VAR refused with rc 2"
assert_eq "$before" "$(tree_sum "$B")" "K refusal wrote nothing"
case "$out" in *"$fake"*) fail "K the offending value was echoed" ;; *) ok "K the offending value is never echoed" ;; esac
case "$out" in *JEV_KEY_VAR*) ok "K message names the variable" ;; *) fail "K message should name JEV_KEY_VAR" ;; esac
for bad in '1ABC' 'A-B' 'A B' '' ; do
  B="$(mkbox)"; before="$(tree_sum "$B")"
  if [ -z "$bad" ]; then JEV_HOME="$B" JEV_KEY_VAR="" bash "$REG" >/dev/null 2>&1; else JEV_HOME="$B" JEV_KEY_VAR="$bad" bash "$REG" >/dev/null 2>&1; fi
  rc=$?
  # empty = default applies (${VAR:-}), so only the non-empty invalid ones must refuse
  if [ -n "$bad" ]; then assert_rc 2 "$rc" "K invalid name [$bad] refused"; assert_eq "$before" "$(tree_sum "$B")" "K [$bad] wrote nothing"
  else assert_rc 0 "$rc" "K empty JEV_KEY_VAR falls back to the default"; fi
done
B="$(mkbox)"; JEV_HOME="$B" JEV_KEY_VAR=MY_KEY_2 bash "$REG" >/dev/null 2>&1
assert_eq "MY_KEY_2" "$(jq -r '.mcpServers.jev.env.JEV_KEY_VAR' "$B/.mcp.json")" "K a valid name is accepted and rendered"

# ── S. minor findings ───────────────────────────────────────────────────────
B="$(mkbox)"; mkdir -p "$B/.config/jev"; printf '%s' '{"per_type":{"gate":{"threshold":0.9,"promoted":true}}}' > "$B/.config/jev/jev-thresholds.json"   # calibrated: enforce is honoured
seed_local_detection "$B/det.json" decide-x
HOME="$B" JEV_TEST=1 JEV_NOW_EPOCH=1700000000 JEV_BASE_URL=https://127.0.0.1:8095 JEV_DETECTION_FILE="$B/det.json" JEV_CONFIG_DIR="$B/.config/jev" JEV_REQUIRE_VALIDATED_CMD=true JEV_DECISION_PROFILES=decide-x JEV_HOME="$B" JEV_MODE=enforce bash "$REG" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "S2 JEV_MODE=enforce accepted"
assert_eq "enforce" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$B/.mcp.json")" "S2 operator JEV_MODE (calibrated) honoured in the rendered entry"
assert_contains "$B/.config/jev/env" "JEV_MODE=enforce" "S2 operator JEV_MODE honoured in the env file"
B="$(mkbox)"; before="$(tree_sum "$B")"
JEV_HOME="$B" JEV_MODE=bogus bash "$REG" >/dev/null 2>&1; rc=$?
assert_rc 2 "$rc" "S2 JEV_MODE outside shadow|enforce refused"
assert_eq "$before" "$(tree_sum "$B")" "S2 refusal wrote nothing"
B="$(mkbox)"; before="$(tree_sum "$B")"
JEV_HOME="$B" JEV_MODEL="$(printf 'x\nJEV_MODE=enforce')" bash "$REG" >/dev/null 2>&1; rc=$?
assert_rc 2 "$rc" "S3 newline in a value refused"
assert_eq "$before" "$(tree_sum "$B")" "S3 refusal wrote nothing"

finish
