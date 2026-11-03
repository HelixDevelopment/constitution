#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_round12.sh — regression for A3: a staging/trash directory name with an out-of-range pid must not make
# every mutating command crash (OverflowError in os.kill). Real engine, real files, no test doubles.
T_NAME=round12
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
R="$SB/croot"; P1="$SB/p1"; make_root "$R"; make_project "$P1"
H="$SB/src"; copy_fixture hooks-fixture "$H"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
INST="$R/extensions/_installed"
e1() { eng --root "$R" --project-root "$P1" "$@"; }

echo "### A3 control: a mutating command works with no odd directories"
e1 add "$H" --dev --waiver-id WD --yes; eq "A3 setup add" 0 "$RC"

echo "### A3 out-of-range pid in a staging/trash name"
BIGS="$INST/.staging-99999999999999999999999-deadbeef"
BIGT="$INST/.trash-99999999999999999999999-deadbeef"
mkdir -p "$BIGS" "$BIGT"; echo keep >"$BIGS/f"; echo keep >"$BIGT/f"
e1 lock; eq "A3 lock does not crash" 0 "$RC"
hasnt "A3 no traceback/OverflowError" "OverflowError" "$OUT"
check "A3 oversized staging left in place" test -f "$BIGS/f"
check "A3 oversized trash left in place" test -f "$BIGT/f"
has "A3 a warning names the directory" "$BIGS" "$OUT"
e1 verify hooks-fixture; eq "A3 verify still ok" 0 "$RC"
e1 remove hooks-fixture --yes; eq "A3 remove still works" 0 "$RC"

echo "### A3 control: a dead in-range staging dir is still swept"
DEAD="$INST/.staging-4194300-cafebabe"; mkdir -p "$DEAD"; echo x >"$DEAD/f"
e1 lock; eq "A3 lock ok" 0 "$RC"
check "A3 dead in-range staging swept" test ! -e "$DEAD"
finish
