#!/usr/bin/env bash
# codegraph_mcp_serve.sh — the `command` target for this project's CodeGraph
# MCP server entry (.mcp.json), so every agent working in this repo gets
# CodeGraph's real query tools (codegraph_explore / codegraph_node / etc.)
# as first-class MCP tools, not only as a raw CLI an agent has to already
# know to invoke manually via Bash.
#
# WHY THIS EXISTS (2026-09-25, operator mandate: "do not set caps for
# codegraph and lumen ... indexed space exposed and used by all agents").
# A direct `.mcp.json` entry naming the bare `codegraph` command resolves
# whatever `codegraph` happens to be first on $PATH — the STOCK, unpatched
# build. This project's own codegraph_safe.sh NEVER trusts stock for a bulk
# index/sync (a documented 2026-09-23 incident: stock indexing can hang/
# corrupt on this project's scale) and instead resolves a PATCHED runner
# (fk_index_patch.py) before every write operation. This wrapper removes
# the same uncertainty for MCP serving at negligible cost: it
# resolves the SAME patched runner codegraph_safe.sh would use (falling
# back to stock ONLY when the patch tool itself says stock is proven safe,
# never on an unresolved/ambiguous signal — §11.4.201 fail-closed), so the
# MCP server always runs the one binary this project has actually tested,
# and stays correct automatically across a future `codegraph upgrade`
# (the runner path is re-derived every launch, never hardcoded).
#
# CONTRACT: `.mcp.json`'s codegraph entry command is THIS script (no args
# needed — it always serves the CURRENT project directory via $CLAUDE_PROJECT_DIR
# when set, else the parent project's root resolved submodule-aware, else its
# own toplevel, else cwd); it execs `<resolved-runner> serve --mcp --path
# <project> --no-watch` so stdio passthrough is exact (MCP requires an
# unbuffered, uninterrupted stdio pipe — no wrapper output may reach stdout,
# only exec, never a subshell that could buffer).
#
# --no-watch IS MANDATORY, NOT OPTIONAL (forensic incident, 2026-09-25).
# `serve --mcp` is NOT a passive read-only server: with its file watcher
# enabled it auto-syncs (WRITES) the database on detected file changes. A
# first version of this wrapper omitted --no-watch; a single ~5s manual test
# of it against this project's live checkout spawned a DETACHED daemon (it
# re-parents to init and outlives its own launching process/timeout — this
# is CodeGraph's own architecture, `codegraph daemon` is documented as a
# persistent background service) that held codegraph.db/-wal/-shm open with
# an active write-capable file watcher for the ~2 minutes until it was found
# and killed — concurrently with an in-flight BULK INDEX run also writing to
# the SAME database, which then hard-crashed with "Failed to index: database
# is locked" after ~85 minutes of progress. Root cause: two writers, one
# database, no coordination between them (codegraph_safe.sh's own
# single-writer flock/lock discipline governs ITS OWN launches only — an MCP
# server started via .mcp.json launches completely outside that mechanism).
# --no-watch makes this server a TRUE query-only reader (per its own --help:
# "Disable the file watcher (no auto-sync)") that can safely run PERMANENTLY
# alongside future bulk index/sync operations without risk of this class of
# collision recurring. A permanently-registered MCP server WILL eventually
# overlap with a future bulk run — the two-writer collision is not a one-off
# testing artifact, it is the exact risk profile production use creates, so
# an occasionally-stale query view (never auto-refreshing) is the correct
# trade against a database corruption/crash risk. `codegraph sync` (or a
# fresh query after the agent knows a sync completed) is how staleness gets
# cleared, deliberately, not automatically.
#
# TESTING THIS SCRIPT SAFELY: never invoke it directly against this
# project's LIVE checkout while any bulk index/sync might be in flight —
# `serve --mcp`'s daemon persists past its parent process's death/timeout,
# so a killed test invocation does NOT guarantee the daemon it may have
# spawned died too; always verify with `pgrep -af 'serve --mcp'` /
# `fuser .codegraph/codegraph.db` afterward and kill anything found. Prefer
# testing against an isolated scratch project directory (see
# tests/test_codegraph_mcp_serve.sh) so a testing mistake can never reach
# the real database.
#
# FAIL-SAFE: if patched-runner resolution genuinely cannot proceed (patch
# tool errors, no receipt, version mismatch) this script exits non-zero
# rather than silently falling back to an unverified binary — an MCP
# server that fails closed and refuses to start is loud and diagnosable;
# one that starts against the wrong binary is a silent correctness risk.
#
# DECOUPLING (§11.4.177/§11.4.28): lives in the constitution submodule,
# inherited BY REFERENCE. The only project-specific piece is the .mcp.json
# entry that points at this script's checked-out path — the script itself
# takes no project literal (project dir is discovered, never hardcoded).
#
# Cross-refs: codegraph_safe.sh (resolve_runner(), the logic this mirrors),
# fk_index_patch.py, tests/test_codegraph_mcp_serve.sh.
# Classification: universal.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_TOOL="${CG_SAFE_PATCH_TOOL:-$HERE/fk_index_patch.py}"
HELPER="${CG_SAFE_HELPER:-$HERE/codegraph_safe_helper.py}"
STOCK="${CODEGRAPH_BIN:-codegraph}"
PATCHES="${CG_SAFE_PATCHES:-fkidx1,resolve1}"

# Project directory: prefer $CLAUDE_PROJECT_DIR (set by Claude Code for every
# MCP server launch), else the CONSUMING project's root (this script lives
# INSIDE the constitution submodule — a plain `git rev-parse --show-toplevel`
# from here resolves to the SUBMODULE's own root, not the parent project's;
# `--show-superproject-working-tree` is the submodule-aware resolution and is
# tried first), else the submodule's own toplevel (the standalone-checkout
# case), else cwd — never a hardcoded path (§11.4.177, reused verbatim by
# every consuming project).
P="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$P" ]; then
    P="$(cd "$HERE" && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
fi
if [ -z "$P" ]; then
    P="$(cd "$HERE" && git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -n "$P" ] || P="$(pwd)"

die() { echo "codegraph_mcp_serve: $*" >&2; exit 1; }

# run_tool <file> <args...> — execute directly when executable, else via its
# interpreter (.py -> python3, else bash). MIRRORS codegraph_safe.sh's own
# run_tool() verbatim — $PATCH_TOOL/$HELPER default to real .py scripts in
# production but tests substitute .sh stubs (§11.4.27); hardcoding `python3`
# here (an earlier bug) force-fed a shell-script stub to the Python
# interpreter and broke every test that resolves a runner.
run_tool() {
    local f="$1"; shift
    if [ -x "$f" ]; then "$f" "$@"; else
        case "$f" in *.py) python3 "$f" "$@" ;; *) bash "$f" "$@" ;; esac
    fi
}

command -v "$STOCK" >/dev/null 2>&1 || die "codegraph not found on PATH (set \$CODEGRAPH_BIN to override)"
SV="$("$STOCK" --version 2>/dev/null | head -n 1 | tr -d ' \r')"
[ -n "$SV" ] || die "cannot read stock codegraph version via '$STOCK --version'"

RUNNER=""
if [ -f "$PATCH_TOOL" ] || [ -x "$PATCH_TOOL" ]; then
    pargs="--patches $PATCHES --print-bin"
    out="$(run_tool "$PATCH_TOOL" $pargs 2>&1)"; rc=$?
    case "$rc" in
        0)  RUNNER="$(printf '%s\n' "$out" | tail -n 1)"
            [ -x "$RUNNER" ] || die "REFUSED: runner path from patch tool is not executable: $RUNNER"
            rdir="$(cd "$(dirname "$RUNNER")/.." && pwd)"
            if [ -f "$HELPER" ] || [ -x "$HELPER" ]; then
                run_tool "$HELPER" receipt "$rdir" "$SV" >/dev/null 2>&1 \
                    || die "REFUSED: runner $RUNNER has no valid RUNNER_RECEIPT.json for stock version $SV"
            fi
            rv="$("$RUNNER" --version 2>/dev/null | head -n 1 | tr -d ' \r')"
            [ "$rv" = "$SV" ] || die "REFUSED: runner version '$rv' != stock version '$SV' — re-derive the runner (fk_index_patch.py)"
            ;;
        3)  RUNNER="$STOCK" ;;  # patch tool: stock proven safe for this version — no ambiguity
        *)  die "REFUSED: fk_index_patch.py could not resolve a safe runner (exit $rc): $(printf '%s' "$out" | tail -n 2 | tr '\n' ' ')" ;;
    esac
else
    die "REFUSED: neither the patch tool nor python3 is available to verify which codegraph binary is safe to serve — refusing to guess"
fi

exec "$RUNNER" serve --mcp --path "$P" --no-watch
