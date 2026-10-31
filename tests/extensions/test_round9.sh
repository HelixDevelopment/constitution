#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_round9.sh — regressions for the independent review of the extensions engine (E1, round 8):
#   S1 a remove journal acts on a trash-shaped directory only when it can prove it is the tree it moved (identity
#      recorded in the journal); two reproductions through the real CLI, plus the positive path;
#   T1 the suites must pass under a non-canonical TMPDIR (a symlinked directory, a path with '..').
# Real engine, real files, no test doubles.
T_NAME=round9
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
HERE="$REPO/tests/extensions"
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
H="$SB/src"; copy_fixture hooks-fixture "$H"
INST="$R/extensions/_installed"
TXN="$P/.constitution/extensions.txn"
e() { eng --root "$R" --project-root "$P" "$@"; }
kill_at() { local st="$1"; shift
  OUT="$(CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT="$st" bash "$ENGINE" --root "$R" --project-root "$P" "$@" </dev/null 2>&1)"; RC=$?
}

echo "### S1 reproduction (a): lock holds the id, tree absent, journal names a foreign trash directory"
e add "$H" --dev --waiver-id WD --yes; eq "setup add" 0 "$RC"; [ "$RC" = 0 ] || echo "$OUT"
mv "$INST/hooks-fixture" "$SB/parked"
mkdir "$INST/.trash-999999-deadbeef"; echo foreign >"$INST/.trash-999999-deadbeef/f"
printf '{"op":"remove","id":"hooks-fixture","final":"%s","aux":"%s"}' "$INST/hooks-fixture" "$INST/.trash-999999-deadbeef" >"$TXN"; sign_journal "$TXN" "$P"
e lock
check "S1a foreign trash NOT renamed into _installed/<id>" test ! -e "$INST/hooks-fixture"
check "S1a foreign trash kept where it was" test -f "$INST/.trash-999999-deadbeef/f"
has "S1a says why" "cannot prove" "$OUT"
rm -rf "${INST:?}/.trash-999999-deadbeef" "$TXN" 2>/dev/null
mv "$SB/parked" "$INST/hooks-fixture"
e verify hooks-fixture; eq "S1a extension still verifies" 0 "$RC"

echo "### S1 reproduction (b): journal for an id that is not in the lock names another project's trash"
mkdir "$INST/.trash-999998-cafebabe"; echo precious >"$INST/.trash-999998-cafebabe/f"
printf '{"op":"remove","id":"ghost-fixture","final":"%s","aux":"%s"}' "$INST/ghost-fixture" "$INST/.trash-999998-cafebabe" >"$TXN"; sign_journal "$TXN" "$P"
e lock
check "S1b foreign trash NOT deleted" test -f "$INST/.trash-999998-cafebabe/f"
has "S1b says why" "cannot prove" "$OUT"
check "S1b journal consumed" test ! -e "$TXN"
e lock
check "S1b control (no journal): trash still kept" test -f "$INST/.trash-999998-cafebabe/f"
rm -rf "${INST:?}/.trash-999998-cafebabe"

echo "### S1 positive: the journal's own trash is still restored / completed"
kill_at remove:trashed remove hooks-fixture --yes; eq "killed after trashing (137)" 137 "$RC"
check "journal records an identity" grep -q '"ident"' "$TXN"
e lock; eq "recovery ok" 0 "$RC"
check "own trash restored to _installed/<id>" test -d "$INST/hooks-fixture"
e verify hooks-fixture; eq "restored tree verifies" 0 "$RC"
kill_at remove:locked remove hooks-fixture --yes; eq "killed after the lock commit (137)" 137 "$RC"
e lock; eq "completion recovery ok" 0 "$RC"
check "own trash deleted on completion" test -z "$(find "$INST" -maxdepth 1 -name '.trash-*')"
check "tree gone" test ! -e "$INST/hooks-fixture"

echo "### T1 suites pass under a non-canonical TMPDIR (symlink + '..')"
mkdir -p "$SB/ncreal"; ln -s "$SB/ncreal" "$SB/nclink"
for s in determinism provenance integration; do
  out="$(TMPDIR="$SB/nclink/../nclink" bash "$HERE/test_$s.sh" 2>&1)"; rc=$?
  eq "T1 test_$s under a non-canonical TMPDIR (rc)" 0 "$rc"
  has "T1 test_$s reports FAIL 0" "FAIL 0" "$out"
done
finish
