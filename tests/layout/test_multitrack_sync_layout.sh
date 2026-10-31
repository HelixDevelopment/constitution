#!/usr/bin/env bash
# tests/layout/test_multitrack_sync_layout.sh — `multitrack_constitution_sync.sh
# for-alias` fast-forwards the worktree's constitution in BOTH layouts and logs
# SKIPPED-no-constitution (never a silent no-op) when there is none.
# Test double (gate-logic class, §11.4.289): the alias -> worktree resolver is a
# stub printing a fixed sandbox path; the sync itself is the REAL script doing
# a REAL fast-forward against a local bare upstream.
# Usage: bash tests/layout/test_multitrack_sync_layout.sh
LT_SUITE="multitrack_sync_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

ENG="$LT_SB/engine"
mkdir -p "$ENG/scripts/multitrack" "$ENG/scripts/lib"
cp "$LAYOUT_SRC_ROOT/scripts/multitrack/multitrack_constitution_sync.sh" "$ENG/scripts/multitrack/"
[ -f "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" ] && cp "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" "$ENG/scripts/lib/"
cat > "$ENG/scripts/multitrack/multitrack_resolve_worktree.sh" <<'STUB'
#!/usr/bin/env bash
# TEST DOUBLE: prints the worktree named by LAYOUT_WT.
[ "${1:-}" = resolve ] && printf '%s\n' "${LAYOUT_WT:?}"
STUB
SYNC="$ENG/scripts/multitrack/multitrack_constitution_sync.sh"
export MTCS_LOG_DIR="$LT_SB/mtlog"

URL="$(lt_make_const_upstream mt)"
for rel in submodules/constitution constitution; do
    tag="[$rel]"
    WT="$LT_SB/wt $(printf '%s' "$rel" | tr / _)"
    mkdir -p "$(dirname "$WT/$rel")"
    lt_git clone -q "$URL" "$WT/$rel"
    lt_git -C "$WT/$rel" checkout -q -B main origin/HEAD 2>/dev/null || lt_git -C "$WT/$rel" checkout -q -B main
    lt_git -C "$WT/$rel" branch -q --set-upstream-to=origin/main main 2>/dev/null || true
    before="$(git -C "$WT/$rel" rev-parse HEAD)"
    lt_bump_const_upstream mt
    out="$(LAYOUT_WT="$WT" bash "$SYNC" for-alias claudeX 2>/dev/null)"; rc=$?
    after="$(git -C "$WT/$rel" rev-parse HEAD)"
    lt_check "$tag for-alias exits 0 (rc=$rc)" test "$rc" -eq 0
    lt_check "$tag constitution fast-forwarded (SYNCED, HEAD moved)" \
        eval 'grep -q "SYNCED" <<<"$out" && test "$before" != "$after"'
    out2="$(LAYOUT_WT="$WT" bash "$SYNC" for-alias claudeX 2>/dev/null)"
    lt_check "$tag idempotent: second run reports ALREADY-CURRENT" grep -q 'ALREADY-CURRENT' <<<"$out2"
done

# I2: an ambient CONSTITUTION_DIR (another checkout) must NOT beat the worktree.
WTO="$LT_SB/wt override"; OTHER="$LT_SB/other_const"
lt_git clone -q "$URL" "$WTO/submodules/constitution"
lt_git clone -q "$URL" "$OTHER"
for d in "$WTO/submodules/constitution" "$OTHER"; do
    lt_git -C "$d" checkout -q -B main origin/main 2>/dev/null
    lt_git -C "$d" branch -q --set-upstream-to=origin/main main 2>/dev/null || true
done
wb="$(git -C "$WTO/submodules/constitution" rev-parse HEAD)"; ob="$(git -C "$OTHER" rev-parse HEAD)"
lt_bump_const_upstream mt
out="$(CONSTITUTION_DIR="$OTHER" LAYOUT_WT="$WTO" bash "$SYNC" for-alias claudeX 2>/dev/null)"; rc=$?
wa="$(git -C "$WTO/submodules/constitution" rev-parse HEAD)"; oa="$(git -C "$OTHER" rev-parse HEAD)"
lt_check "CONSTITUTION_DIR elsewhere: the WORKTREE's constitution is synced (rc=$rc)" test "$wb" != "$wa"
lt_check "CONSTITUTION_DIR elsewhere: the override checkout is left untouched" test "$ob" = "$oa"

NONE="$LT_SB/wt_none"; mkdir -p "$NONE"
out="$(LAYOUT_WT="$NONE" bash "$SYNC" for-alias claudeX 2>/dev/null)"; rc=$?
lt_check "no constitution: exit 0 + logged SKIPPED-no-constitution (never silent)" \
    eval 'test "$rc" -eq 0 && grep -q "SKIPPED-no-constitution" <<<"$out"'
lt_summary
