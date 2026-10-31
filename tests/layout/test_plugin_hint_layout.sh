#!/usr/bin/env bash
# tests/layout/test_plugin_hint_layout.sh — when the `claude` CLI is absent,
# scripts/install_cli_agent_plugins.sh prints the one-time operator command with
# the constitution path AS IT IS in the project (./submodules/constitution or the
# legacy ./constitution), never a basename guess.
# Runs the REAL installer on a sandbox COPY of the constitution, with a PATH that
# has no `claude` (nothing can reach the operator's real plugin state) and
# CLAUDE_CONFIG_DIR inside the sandbox.
# Usage: bash tests/layout/test_plugin_hint_layout.sh
LT_SUITE="plugin_hint_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

export CLAUDE_CONFIG_DIR="$LT_SB/claude-config"; mkdir -p "$CLAUDE_CONFIG_DIR"
SAFE_PATH="/usr/bin:/bin"

make_const() {
    local d="$1" x
    mkdir -p "$d/scripts/lib"
    for x in .claude-plugin plugins actions skills Constitution.md; do cp -a "$LAYOUT_SRC_ROOT/$x" "$d/$x"; done
    for x in action_prefix_lib.sh generate_agent_prefix_commands.sh install_cli_agent_plugins.sh \
             portable_symlink_lib.sh install_action_prefix.sh; do
        [ -f "$LAYOUT_SRC_ROOT/scripts/$x" ] && cp -a "$LAYOUT_SRC_ROOT/scripts/$x" "$d/scripts/$x"
    done
    [ -f "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" ] && cp -a "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" "$d/scripts/lib/"
    return 0
}

for rel in submodules/constitution constitution; do
    P="$LT_SB/hint $(printf '%s' "$rel" | tr / _)"
    mkdir -p "$P"; make_const "$P/$rel"
    ( cd "$P" && PATH="$SAFE_PATH" bash "$rel/scripts/install_cli_agent_plugins.sh" "$P" >"$LT_SB/o" 2>"$LT_SB/e" ); rc=$?
    lt_check "[$rel] hint names ./$rel (rc=$rc)" grep -qF "claude plugin marketplace add ./$rel" "$LT_SB/e"
    [ "$rel" = constitution ] || lt_check "[$rel] hint is not the basename-only ./constitution" \
        eval '! grep -qE "marketplace add \./constitution$" "$LT_SB/e"'
done
lt_summary
