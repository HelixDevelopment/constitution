#!/usr/bin/env bash
# ============================================================================
# test_codegraph_mcp_preflight_mutations.sh — paired §1.1 mutation proof for codegraph_mcp_preflight.sh
# ============================================================================
# Purpose      Each mutant re-opens exactly one hole in a COPY of codegraph_mcp_preflight.sh; the named case(s) of
#              tests/test_codegraph_mcp_preflight.sh MUST turn FAIL (mutant KILLED). A survivor = a test blind to that hole.
# Usage        bash test_codegraph_mcp_preflight_mutations.sh [Y1 Y2 ...]   (default: all)
# Inputs       TMPDIR, STOCK_SRC (forwarded)        Outputs  per-mutant KILLED/SURVIVED + SUMMARY; exit 1 on survivor/baseline failure
# Side effects copies under $TMPDIR/cg_mcpf_mut.*; nothing tracked
# Cross-refs   test_codegraph_mcp_preflight.sh, test_codegraph_mcp_preflight_mutate.py, constitution §1.1
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/cg_mcpf_mut.XXXXXX")"
IDS=("$@"); [ "${#IDS[@]}" -gt 0 ] || IDS=(Y1 Y2 Y3 Y4 Y5 Y6)
survivors=0; killed=0
copy_tree() { mkdir -p "$1"; ( cd "$CG_DIR" && cp -a codegraph_mcp_preflight.sh codegraph_mcp.sh fk_index_patch.py runner_patches tests codegraph_mcp_probe.py "$1"/ ); rm -rf "$1"/runner_patches/__pycache__ "$1"/tests/__pycache__; }
copy_tree "$W/base"
CG_DIR="$W/base" bash "$W/base/tests/test_codegraph_mcp_preflight.sh" > "$W/base.out" 2>&1; BRC=$?
grep -E '^RESULT' "$W/base.out" | cut -c1-100
[ "$BRC" -eq 0 ] || { echo "BASELINE FAILED (rc=$BRC) — mutation result would be meaningless"; exit 1; }
for id in "${IDS[@]}"; do
    d="$W/$id"; copy_tree "$d"
    exp="$(python3 "$HERE/test_codegraph_mcp_preflight_mutate.py" "$id" "$d" 2>"$W/$id.mut.err")" || { echo "MUTANT $id ERROR $(cat "$W/$id.mut.err")"; survivors=$((survivors+1)); continue; }
    CG_DIR="$d" ONLY="$exp" bash "$d/tests/test_codegraph_mcp_preflight.sh" > "$W/$id.out" 2>&1; rc=$?
    all=1; for r in ${exp//,/ }; do grep -q "^RESULT $r FAIL" "$W/$id.out" || all=0; done
    if [ "$rc" -ne 0 ] && [ "$all" -eq 1 ]; then killed=$((killed+1)); echo "MUTANT $id KILLED (expected FAIL: $exp)"
    else survivors=$((survivors+1)); echo "MUTANT $id SURVIVED rc=$rc expected_fail=$exp :: $(grep -E '^RESULT' "$W/$id.out" | cut -c1-60 | tr '\n' ';')"; fi
done
echo "SUMMARY mutants=$((killed+survivors)) killed=$killed survivors=$survivors workdir=$W"
[ "$survivors" -eq 0 ]
