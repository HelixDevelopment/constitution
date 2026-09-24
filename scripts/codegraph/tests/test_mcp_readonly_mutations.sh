#!/usr/bin/env bash
# ============================================================================
# test_mcp_readonly_mutations.sh — paired §1.1 mutation proof for patch mcpro1
# ============================================================================
# Purpose      Prove tests/test_mcp_readonly.sh is not decoration: each mutant re-opens exactly one
#              hole in a COPY of the tooling and the named test case(s) MUST turn FAIL (mutant KILLED).
#              A surviving mutant = a test that cannot see that hole = release blocker.
# Usage        bash test_mcp_readonly_mutations.sh [M0 M1 ...]   (default: all)
# Inputs       TMPDIR (default /tmp); STOCK_SRC optional (forwarded to the test)
# Outputs      per-mutant KILLED/SURVIVED lines + SUMMARY; exit 1 if any survivor or baseline failure
# Side effects copies of fk_index_patch.py runner_patches tests under $TMPDIR/cg_mcp_mut.*; nothing tracked
# Cross-refs   test_mcp_readonly.sh, test_mcp_readonly_mutate.py, constitution §1.1 / §11.4.115(F)
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/cg_mcp_mut.XXXXXX")"
IDS=("$@"); [ "${#IDS[@]}" -gt 0 ] || IDS=(M0 M1 M3 M4 M5 M6 M7 M8 M9 M10)
survivors=0; killed=0
copy_tree() { mkdir -p "$1"; ( cd "$CG_DIR" && cp -a fk_index_patch.py runner_patches tests codegraph_mcp_probe.py "$1"/ ); rm -rf "$1"/runner_patches/__pycache__ "$1"/tests/__pycache__; }
copy_tree "$W/base"
ONLY_ALL="R1,R3,R5,R6,R7,R9,R10,R11,R12,R13"
CG_DIR="$W/base" ONLY="$ONLY_ALL" bash "$W/base/tests/test_mcp_readonly.sh" > "$W/base.out" 2>&1; BRC=$?
grep -E '^RESULT' "$W/base.out" | cut -c1-110
if [ "$BRC" -ne 0 ]; then echo "BASELINE FAILED (rc=$BRC) — mutation result would be meaningless"; exit 1; fi
for id in "${IDS[@]}"; do
    d="$W/$id"; copy_tree "$d"
    exp="$(python3 "$HERE/test_mcp_readonly_mutate.py" "$id" "$d" 2>"$W/$id.mut.err")" || { echo "MUTANT $id ERROR $(cat "$W/$id.mut.err")"; survivors=$((survivors+1)); continue; }
    CG_DIR="$d" ONLY="$exp" bash "$d/tests/test_mcp_readonly.sh" > "$W/$id.out" 2>&1; rc=$?
    all=1; for r in ${exp//,/ }; do grep -q "^RESULT $r FAIL" "$W/$id.out" || all=0; done
    if [ "$rc" -ne 0 ] && [ "$all" -eq 1 ]; then killed=$((killed+1)); echo "MUTANT $id KILLED (expected FAIL: $exp)"
    else survivors=$((survivors+1)); echo "MUTANT $id SURVIVED rc=$rc expected_fail=$exp :: $(grep -E '^RESULT' "$W/$id.out" | cut -c1-70 | tr '\n' ';')"; fi
done
echo "SUMMARY mutants=$((killed+survivors)) killed=$killed survivors=$survivors workdir=$W"
[ "$survivors" -eq 0 ]
