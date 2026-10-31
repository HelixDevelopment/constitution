#!/usr/bin/env bash
# ============================================================================
# guard-evidence-store-write.sh — PreToolUse guard: a PRODUCER may not write the
# evidence/verdict store directly (T122, spec 002; FR-031 / FR-008, layer 1).
#
# §11.4.69 FEATURE: permission_grant
#
# ---------------------------------------------------------------------------
# WHAT THIS IS — and, stated first because it is the honest part, WHAT IT IS NOT
# ---------------------------------------------------------------------------
# This is BEST-EFFORT PREVENTION, layered UNDER the reader-side detection in
# scripts/lib/critical_blocker_gate.sh (T118). It is NEVER a substitute for it.
#
# THE MEASURED BYPASS, NAMED HERE RATHER THAN IMPLIED AWAY (§11.4.6):
#   A Write/Edit matcher sees Write and Edit tool calls. ONE LEVEL OF
#   INDIRECTION defeats it entirely — a Bash call that appends (`printf … >>
#   store`), a helper script, a symlink, an editor invoked through a shell —
#   none of those present as a Write to the store path, and none of them is
#   blocked here. Research D-3 measured exactly this: a satisfy row forged by a
#   single plain `>>` redirection bypassed the append function and was accepted
#   with rc=0.
#
#   That is WHY the guarantee lives in the READER. T118 checks authorship on
#   every READ, so a forged row is caught no matter how it was written. This
#   hook only raises the cost of the most direct path. A bypass that is NAMED is
#   a stated limit; a bypass that is implied away is a bluff — and the test
#   suite (test_guard_evidence_store_write.sh) ASSERTS this bypass still
#   succeeds, so the coverage claim is a measured fact rather than a hope.
#
# ---------------------------------------------------------------------------
# THE RULE
# ---------------------------------------------------------------------------
#   BLOCK (exit 2) a Write/Edit/MultiEdit/NotebookEdit whose target is in the
#   evidence-store path class WHEN the harness-supplied session id is recorded
#   as a PRODUCER for some item in that store.
#   ALLOW (exit 0) everything else — a non-producer session, a path outside the
#   class, a non-write tool. A false-positive block is rated exactly as
#   seriously as a false pass (§11.4.201(1)): this hook sits on the operator's
#   working path, and one that blocks legitimate edits gets switched off, taking
#   the real coverage with it.
#   FAIL CLOSED (exit 2) when the registry cannot be read: with no way to
#   establish who the producer is, an authorization surface refuses (§11.4.252).
#
# Configuration (consumer DATA, never hardcoded logic):
#   GESW_REGISTRY  — evidence store to consult. Default: the repo's
#                    docs/requests/critical_blockers.jsonl.
#
# Contract: stdin = the PreToolUse JSON payload; exit 0 = allow, 2 = block.
# ============================================================================
set -uo pipefail

PAYLOAD="$(cat || true)"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# <repo>/submodules/constitution/scripts/hooks or <repo>/constitution/scripts/hooks
# -> <repo>, through the ONE layout resolver (scripts/lib/constitution_layout.sh).
# Without the lib (a stray copy of this file) the legacy ../../.. guess is kept;
# a wrong guess still fails CLOSED below, never open.
REPO_GUESS=""
if [ -f "$HOOK_DIR/../lib/constitution_layout.sh" ]; then
  # shellcheck source=../lib/constitution_layout.sh
  . "$HOOK_DIR/../lib/constitution_layout.sh"
  # An ambient GIT_DIR & co. must not choose the repository whose registry is
  # guarded (round 8); silent: this runs on every tool call.
  cl_scrub_git_env quiet
  REPO_GUESS="$(cl_project_root_of "$HOOK_DIR/../.." 2>/dev/null)" || REPO_GUESS=""
fi
[ -n "$REPO_GUESS" ] || REPO_GUESS="$(cd "$HOOK_DIR/../../.." 2>/dev/null && pwd || printf '')"
REGISTRY="${GESW_REGISTRY:-${CLAUDE_PROJECT_DIR:-$REPO_GUESS}/docs/requests/critical_blockers.jsonl}"

# --- JSON string-field reader (jq when present; awk otherwise) ---------------
# Same extractor shape as the sibling guards, so one reviewer's understanding
# transfers across all of them.
json_field() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | jq -r ".. | objects | select(has(\"$key\")) | .\"$key\"" 2>/dev/null | head -1
    return 0
  fi
  printf '%s' "$PAYLOAD" | awk -v key="$key" '
    BEGIN { RS="\0" }
    {
      idx = index($0, "\"" key "\"")
      if (idx == 0) { exit }
      rest = substr($0, idx + length(key) + 2)
      sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") { exit }
      rest = substr(rest, 2)
      out = ""; i = 1; n = length(rest)
      while (i <= n) {
        c = substr(rest, i, 1)
        if (c == "\\") { out = out substr(rest, i+1, 1); i += 2; continue }
        if (c == "\"") break
        out = out c; i++
      }
      printf "%s", out
    }'
}

TOOL="$(json_field tool_name)"
SESSION="$(json_field session_id)"
TARGET="$(json_field file_path)"
[ -n "$TARGET" ] || TARGET="$(json_field notebook_path)"

# --- (1) not a write-class tool => not our business -------------------------
case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit) : ;;
  *) exit 0 ;;
esac

# --- (2) target outside the evidence-store path class => allow --------------
# The class is matched on the RESOLVED path, by basename, so a relative and an
# absolute reference to the same store are the same target. This is a
# structural match on the store's identity, not a substring search for a word
# that other filenames also contain (§11.4.201(7)(a)).
[ -n "$TARGET" ] || exit 0
in_class=0
case "$(basename -- "$TARGET")" in
  critical_blockers.jsonl) in_class=1 ;;
esac
if [ "$in_class" -eq 0 ] && [ -n "${GESW_REGISTRY:-}" ]; then
  # An explicitly configured store is in its own class regardless of basename,
  # so a fixture store under any name is still protected.
  [ "$TARGET" = "$GESW_REGISTRY" ] && in_class=1
fi
[ "$in_class" -eq 1 ] || exit 0

# --- (3) fail CLOSED when the store cannot be read --------------------------
if [ ! -r "$REGISTRY" ]; then
  printf 'BLOCKED (guard-evidence-store-write): the evidence store %s could not be read, so the producer for this item cannot be established. An authorization surface refuses rather than guesses (§11.4.252 fail-closed). Fix the path/permissions, or set GESW_REGISTRY.\n' "$REGISTRY" >&2
  exit 2
fi

# --- (4) is this session recorded as a PRODUCER in that store? --------------
# No session id => nothing to attribute => allow (a false block on an
# unattributable call would fire on every unrelated write).
[ -n "$SESSION" ] || exit 0
if grep -qF "\"producer_session_id\":\"$SESSION\"" "$REGISTRY" 2>/dev/null; then
  printf 'BLOCKED (guard-evidence-store-write): session %s is recorded as a PRODUCER in %s and may not write the evidence store directly — a producer that can write its own verdict is not a verified verdict (FR-031/FR-008). Have the verifier seam append the row.\n\nSTATED LIMIT (§11.4.6): this hook sees Write/Edit calls only. One level of indirection (a Bash append, a helper script, a symlink) is NOT blocked here — the guarantee is the reader-side authorship check in scripts/lib/critical_blocker_gate.sh, which runs on every READ regardless of how a row was written.\n' \
    "$SESSION" "$REGISTRY" >&2
  exit 2
fi

exit 0
