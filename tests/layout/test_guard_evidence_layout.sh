#!/usr/bin/env bash
# tests/layout/test_guard_evidence_layout.sh — the evidence-store guard must
# find the CONSUMER's registry (<project>/docs/requests/critical_blockers.jsonl)
# from its own location in BOTH layouts, with no CLAUDE_PROJECT_DIR set.
# Discriminator: a NON-producer write is ALLOWED (exit 0) only when the guard
# reads the real registry; a wrong default path makes it fail closed (exit 2).
# Usage: bash tests/layout/test_guard_evidence_layout.sh
LT_SUITE="guard_evidence_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

payload() { printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$2" "$1"; }

for rel in submodules/constitution constitution; do
    tag="[$rel]"
    P="$LT_SB/g $(printf '%s' "$rel" | tr / _)"
    mkdir -p "$P/$rel/scripts/hooks" "$P/$rel/scripts/lib" "$P/docs/requests"
    printf '# C\n' > "$P/$rel/Constitution.md"
    cp "$LAYOUT_SRC_ROOT/scripts/hooks/guard-evidence-store-write.sh" "$P/$rel/scripts/hooks/"
    [ -f "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" ] && \
        cp "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" "$P/$rel/scripts/lib/"
    REG="$P/docs/requests/critical_blockers.jsonl"
    printf '{"blocker_id":"B-X","event":"satisfy","author_session_id":"SESS-V","producer_session_id":"SESS-PRODUCER"}\n' > "$REG"
    G="$P/$rel/scripts/hooks/guard-evidence-store-write.sh"
    payload "$REG" SESS-OTHER | ( unset CLAUDE_PROJECT_DIR GESW_REGISTRY; bash "$G" ) >/dev/null 2>"$LT_SB/e1"; rc=$?
    lt_check "$tag non-producer write ALLOWED (guard found <project>/docs/requests) rc=$rc" test "$rc" -eq 0
    payload "$REG" SESS-PRODUCER | ( unset CLAUDE_PROJECT_DIR GESW_REGISTRY; bash "$G" ) >/dev/null 2>"$LT_SB/e2"; rc=$?
    lt_check "$tag producer write BLOCKED as PRODUCER (not as unreadable) rc=$rc" \
        eval 'test "$rc" -eq 2 && grep -q "recorded as a PRODUCER" "$LT_SB/e2"'
    payload "$REG" SESS-OTHER | ( export CLAUDE_PROJECT_DIR="$P"; bash "$G" ) >/dev/null 2>&1; rc=$?
    lt_check "$tag CLAUDE_PROJECT_DIR still takes precedence rc=$rc" test "$rc" -eq 0
done

lt_summary
