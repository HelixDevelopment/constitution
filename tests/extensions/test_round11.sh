#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_round11.sh — regressions for the round-11 review of the extensions engine:
#   F3 remove needs this checkout's own signed state record (a copied lock proves nothing);
#   F4 the remove journal is HMAC-signed like the add journal; unsigned/forged ones are left in place.
# Real engine, real files, no test doubles.
T_NAME=round11
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
R="$SB/croot"; P1="$SB/p1"; P2="$SB/p2"; make_root "$R"; make_project "$P1"; make_project "$P2"
H="$SB/src"; copy_fixture hooks-fixture "$H"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
INST="$R/extensions/_installed"
e1() { eng --root "$R" --project-root "$P1" "$@"; }
e2() { eng --root "$R" --project-root "$P2" "$@"; }

echo "### F3 a copied lock does not authorise removal"
e2 add "$H" --dev --waiver-id WD --yes; eq "setup: P2 adds" 0 "$RC"
mkdir -p "$P1/.constitution"; cp "$P2/.constitution/extensions.lock.yml" "$P1/.constitution/extensions.lock.yml"
e1 remove hooks-fixture --yes
eq "F3 P1 remove refused with rc 3" 3 "$RC"
check "F3 P2's tree intact" test -f "$INST/hooks-fixture/extension.yml"
e2 verify hooks-fixture; eq "F3 P2 still verifies" 0 "$RC"
# P1 with a state dir and its own key but no record for the id
e1 lock >/dev/null 2>&1
e1 remove hooks-fixture --yes; eq "F3 still refused once P1 has its own key" 3 "$RC"
check "F3 tree still intact" test -f "$INST/hooks-fixture/extension.yml"
echo "### F3 control: the owner removes"
e2 remove hooks-fixture --yes; eq "F3 P2 remove ok" 0 "$RC"
check "F3 tree gone" test ! -e "$INST/hooks-fixture"

echo "### F4 the remove journal is signed"
e1 add "$H" --dev --waiver-id WD --yes; eq "setup: P1 adds" 0 "$RC"
TXN="$P1/.constitution/extensions.txn"
mkdir -p "$INST/.trash-999998-cafebabe"; echo precious >"$INST/.trash-999998-cafebabe/f"
printf '{"op":"remove","id":"hooks-fixture","final":"%s","aux":"%s"}' "$INST/hooks-fixture" "$INST/.trash-999998-cafebabe" >"$TXN"
e1 lock
has "F4 warns about the unsigned remove journal" "unsigned" "$OUT"
check "F4 unsigned journal left in place" test -f "$TXN"
check "F4 trash untouched" test -f "$INST/.trash-999998-cafebabe/f"
check "F4 tree untouched" test -f "$INST/hooks-fixture/extension.yml"
e1 remove hooks-fixture --yes; check "F4 remove refuses while it is present" test "$RC" != 0
e1 add "$SB/none" --dev --yes; check "F4 add refuses while it is present" test "$RC" != 0
printf '{"op":"remove","id":"hooks-fixture","final":"%s","aux":"%s","mac":"%s"}' "$INST/hooks-fixture" "$INST/.trash-999998-cafebabe" "$(printf 'b%.0s' $(seq 64))" >"$TXN"
e1 lock
check "F4 forged-mac journal left in place" test -f "$TXN"
check "F4 trash still untouched" test -f "$INST/.trash-999998-cafebabe/f"
rm -f "$TXN"; rm -rf "${INST:?}/.trash-999998-cafebabe"
echo "### F4 positive: a real interrupted remove is still recovered"
CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT=remove:trashed bash "$ENGINE" --root "$R" --project-root "$P1" remove hooks-fixture --yes </dev/null >/dev/null 2>&1
eq "F4 killed (137)" 137 "$?"
check "F4 journal carries a mac" grep -q '"mac"' "$TXN"
e1 lock; eq "F4 recovery ok" 0 "$RC"
check "F4 tree restored by rollback" test -f "$INST/hooks-fixture/extension.yml"
check "F4 journal consumed" test ! -e "$TXN"
finish
