#!/usr/bin/env bash
# tests/gates/test_default_scan_root.sh — known_failures_v73 rank 3.
# Scanner gates must default their scan root from WHERE THE GATE LIVES, never
# from the caller's cwd ("..").  REAL invocation path: the real gate scripts
# and real lib are copied into git sandboxes (no test doubles); a standalone
# canon checkout and a consumer-shaped checkout (canon as a real git
# submodule) are built with real git.  Covers integration/e2e, security (hostile
# cwd names), chaos (missing --root target), determinism (3 runs), time budget,
# precedence (explicit --root wins), and a paired section 1.1 mutation.
set -uo pipefail
export CONSTITUTION_JEV_HOOK=off
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
canon_src="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
chk() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

GATES="cm_oracle_strategy_named_and_independent cm_dangerous_combination_fail_closed cm_killpg_pgid_guard cm_test_mock_pid_explicit_int cm_opendesign_ui_system cm_covenant_114_167_propagation"

mkcanon() { # $1 = dir ; builds a minimal real-git canon with the real gates + lib
    mkdir -p "$1/scripts/gates" "$1/scripts/lib"
    for g in $GATES; do cp "$canon_src/scripts/gates/$g.sh" "$1/scripts/gates/"; done
    cp "$canon_src/scripts/lib/default_scan_root.sh" "$1/scripts/lib/"
    printf 'def test_unannotated():\n    assert 1 == 1\n' > "$1/test_canon_marker.py"
    printf 'try { x(); } catch (e) {}\n' > "$1/canon_marker.js"
    git -C "$1" init -q 2>/dev/null
    git -C "$1" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
    git -C "$1" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
}

# ---- standalone canon with a foreign sibling next to it -------------------
mkdir -p "$sb/parent/sibling"
printf 'def test_sibling_unannotated():\n    assert 1\n' > "$sb/parent/sibling/test_sibling_marker.py"
printf 'try { y(); } catch (e) {}\n' > "$sb/parent/sibling/sibling_marker.js"
mkcanon "$sb/parent/canon"

o="$sb/o1"; ( cd "$sb/parent/canon" && bash scripts/gates/cm_oracle_strategy_named_and_independent.sh >"$o" 2>&1 ); rc=$?
[ "$rc" = 1 ] && grep -q "test_canon_marker.py" "$o" && ! grep -q "sibling" "$o"; chk $? "e2e oracle gate, standalone canon, no --root: scans canon only (rc=1, canon marker found, sibling NOT scanned)"
o="$sb/o2"; ( cd "$sb/parent/canon" && bash scripts/gates/cm_dangerous_combination_fail_closed.sh >"$o" 2>&1 ); rc=$?
[ "$rc" = 1 ] && grep -q "canon_marker.js" "$o" && ! grep -q "sibling" "$o"; chk $? "e2e dangerous-combination gate, standalone canon, no --root: scans canon only"

# cwd-independence: from an unrelated cwd, an outside cwd, and a hostile-named cwd the SAME root results
mkdir -p "$sb/a b;touch pwned"
for cwd in "$sb/parent" "$sb/a b;touch pwned" "/"; do
    o="$sb/o3"; ( cd "$cwd" && bash "$sb/parent/canon/scripts/gates/cm_oracle_strategy_named_and_independent.sh" >"$o" 2>&1 ); rc=$?
    [ "$rc" = 1 ] && grep -q "test_canon_marker.py" "$o" && ! grep -q "sibling" "$o"; chk $? "security/cwd-independence: cwd='$cwd' still scans canon only"
done
[ ! -e "$sb/pwned" ] && [ ! -e "$sb/a b;touch pwned/pwned" ]; chk $? "security: hostile cwd name executed nothing"

# precedence: explicit --root and env both beat the default
o="$sb/o4"; bash "$sb/parent/canon/scripts/gates/cm_oracle_strategy_named_and_independent.sh" --root "$sb/parent/sibling" >"$o" 2>&1
grep -q "test_sibling_marker.py" "$o" && ! grep -q "test_canon_marker.py" "$o"; chk $? "precedence: explicit --root wins over the default"
o="$sb/o5"; ORACLE_GUARD_ROOT="$sb/parent/sibling" bash "$sb/parent/canon/scripts/gates/cm_oracle_strategy_named_and_independent.sh" >"$o" 2>&1
grep -q "test_sibling_marker.py" "$o"; chk $? "precedence: env override wins over the default"

# chaos: missing explicit root is a loud environment error, not a silent default
bash "$sb/parent/canon/scripts/gates/cm_oracle_strategy_named_and_independent.sh" --root "$sb/does-not-exist" >"$sb/o6" 2>&1; rc=$?
[ "$rc" = 2 ]; chk $? "chaos: nonexistent --root -> rc=2 (no silent fallback)"

# determinism + time budget (3 identical runs)
t0=$(date +%s); h=""
for i in 1 2 3; do h="$h $( cd "$sb/parent/canon" && bash scripts/gates/cm_oracle_strategy_named_and_independent.sh 2>&1 | sha256sum | cut -c1-16)"; done
t1=$(date +%s)
[ "$(echo $h | tr ' ' '\n' | sort -u | wc -l)" = 1 ]; chk $? "determinism: 3 identical outputs ($h )"
[ $((t1-t0)) -lt 60 ]; chk $? "performance: 3 runs in $((t1-t0))s (< 60s budget)"
# idempotency: the gate wrote nothing into the sandbox canon
[ -z "$(git -C "$sb/parent/canon" status --porcelain)" ]; chk $? "idempotency: gate runs leave the scanned repo untouched"

# ---- consumer-shaped: canon vendored as a real git submodule ---------------
mkdir -p "$sb/consumer"; git -C "$sb/consumer" init -q
printf 'def test_consumer_unannotated():\n    assert 1\n' > "$sb/consumer/test_consumer_marker.py"
git -C "$sb/consumer" -c protocol.file.allow=always -c user.email=t@t -c user.name=t submodule add -q "$sb/parent/canon" constitution >/dev/null 2>&1
git -C "$sb/consumer" -c user.email=t@t -c user.name=t commit -qam sub >/dev/null 2>&1
o="$sb/o7"; ( cd "$sb/consumer/constitution" && bash scripts/gates/cm_oracle_strategy_named_and_independent.sh >"$o" 2>&1 ); rc=$?
[ "$rc" = 1 ] && grep -q "test_consumer_marker.py" "$o"; chk $? "e2e consumer-shaped (submodule): default root = consumer superproject"
o="$sb/o8"; ( cd "$sb/consumer" && bash constitution/scripts/gates/cm_oracle_strategy_named_and_independent.sh >"$o" 2>&1 ); rc=$?
[ "$rc" = 1 ] && grep -q "test_consumer_marker.py" "$o"; chk $? "e2e consumer-shaped, cwd=consumer root: same default root"

# ---- lib unit: exact resolved paths ----------------------------------------
want="$(cd "$sb/parent/canon" && pwd -P)"
got="$(bash -c '. "$1/scripts/lib/default_scan_root.sh"; cm_default_scan_root "$1/scripts/gates"' _ "$sb/parent/canon")"
[ "$got" = "$want" ]; chk $? "unit: standalone canon resolves to itself"
want="$(cd "$sb/consumer" && pwd -P)"
got="$(bash -c '. "$1/scripts/lib/default_scan_root.sh"; cm_default_scan_root "$1/scripts/gates"' _ "$sb/consumer/constitution")"
[ "$got" = "$want" ]; chk $? "unit: submodule canon resolves to superproject"
bash -c '. "$1/scripts/lib/default_scan_root.sh"; cm_default_scan_root "$2"' _ "$sb/parent/canon" "" >/dev/null 2>&1; [ $? = 1 ]; chk $? "unit: empty gate dir -> rc=1, no guess"
got="$(GIT_DIR=/nonexistent bash -c '. "$1/scripts/lib/default_scan_root.sh"; cm_default_scan_root "$1/scripts/gates"' _ "$sb/parent/canon")"
[ "$got" = "$(cd "$sb/parent/canon" && pwd -P)" ]; chk $? "security: ambient GIT_DIR cannot redirect the resolver"

# ---- all six gates: no cwd-relative default left, all use the lib ----------
for g in $GATES; do
    f="$canon_src/scripts/gates/$g.sh"
    ! grep -nE 'root="\$\{[A-Z_]+:-\.\.\}"' "$f" >/dev/null && grep -q default_scan_root.sh "$f"; chk $? "static (source-level only): $g has no ':-..' root default and sources the resolver"
done

# ---- paired section 1.1 mutation: restore the cwd-relative default ---------
mkdir -p "$sb/parent/mut"; mkcanon "$sb/parent/mut"
sed -i 's|root="${ORACLE_GUARD_ROOT:-}"|root="${ORACLE_GUARD_ROOT:-..}"|' "$sb/parent/mut/scripts/gates/cm_oracle_strategy_named_and_independent.sh"
o="$sb/o9"; ( cd "$sb/parent/mut" && bash scripts/gates/cm_oracle_strategy_named_and_independent.sh >"$o" 2>&1 )
grep -q "sibling" "$o"; chk $? "mutation: restoring ':-..' makes the gate scan the sibling (test would catch the regression)"

echo "-----"; echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]
