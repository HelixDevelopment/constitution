#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_round10.sh — regressions for the round-10 review of the extensions engine:
#   F1 an act on the shared _installed root needs proof that THIS project owns the target (remove of an id that
#      is not in this project's lock; remove when the tree is not the one the lock pinned);
#   F2 the add journal is HMAC-signed; a forged or unsigned one is left in place and refuses add/remove;
#   A4 a symlinked _installed (or extensions/) is refused, nothing behind the link is touched;
#   m10 the staging sweep never touches a directory whose pid is alive;
#   D1 a trash directory left in place (unproven) keeps its state record.
# Real engine, real files, no test doubles.
T_NAME=round10
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
R="$SB/croot"; P1="$SB/p1"; P2="$SB/p2"; make_root "$R"; make_project "$P1"; make_project "$P2"
H="$SB/src"; copy_fixture hooks-fixture "$H"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
INST="$R/extensions/_installed"
e1() { eng --root "$R" --project-root "$P1" "$@"; }
e2() { eng --root "$R" --project-root "$P2" "$@"; }

echo "### F1 remove of an id absent from this project's lock"
e2 add "$H" --dev --waiver-id WD --yes; eq "setup: P2 adds" 0 "$RC"
e1 remove hooks-fixture --yes
check "F1 P1 remove is refused (non-zero)" test "$RC" != 0
has "F1 says why" "not in this project's lock" "$OUT"
check "F1 P2's tree still there" test -f "$INST/hooks-fixture/extension.yml"
e2 verify hooks-fixture; eq "F1 P2 still verifies" 0 "$RC"
e1 enable hooks-fixture --yes; check "F1 P1 enable refused" test "$RC" != 0
e1 disable hooks-fixture; check "F1 P1 disable leaves the tree" test -f "$INST/hooks-fixture/extension.yml"
e1 wire hooks-fixture; check "F1 P1 wire refused" test "$RC" != 0
e1 unwire hooks-fixture; check "F1 P1 unwire leaves the tree" test -f "$INST/hooks-fixture/extension.yml"
e2 verify hooks-fixture; eq "F1 P2 verifies after all of P1's commands" 0 "$RC"

echo "### F1b remove when the tree is not the one this project's lock pinned"
e2 remove hooks-fixture --yes; eq "setup: P2 removes its own" 0 "$RC"
e1 add "$H" --dev --waiver-id WD --yes; eq "setup: P1 adds" 0 "$RC"
e2 add "$H" --dev --waiver-id WD --yes; check "F1b a second project cannot add over P1's tree (clear refusal)" test "$RC" != 0
has "F1b refusal explains" "shared constitution root" "$OUT"
# another project replaces the shared tree with different content (a new version of the same id)
mkdir -p "$SB/old"; mv "$INST/hooks-fixture" "$SB/old/t"; mkdir "$INST/hooks-fixture"
cp -R "$SB/old/t/." "$INST/hooks-fixture/"; echo '# changed by another project' >>"$INST/hooks-fixture/extension.yml"
e1 remove hooks-fixture --yes; eq "F1b P1 remove drops its own lock entry (0)" 0 "$RC"
check "F1b tree it cannot prove is its own is kept" test -f "$INST/hooks-fixture/extension.yml"
has "F1b says so" "left in place" "$OUT"
check "F1b P1 lock no longer names it" test -z "$(grep -s hooks-fixture "$P1/.constitution/extensions.lock.yml")"
rm -rf "${INST:?}/hooks-fixture"

echo "### F1c control: remove of an id in the lock whose tree matches deletes it"
e1 add "$H" --dev --waiver-id WD --yes; eq "setup" 0 "$RC"
e1 remove hooks-fixture --yes; eq "F1c remove ok" 0 "$RC"
check "F1c tree gone" test ! -e "$INST/hooks-fixture"

echo "### F2 the add journal is signed"
e1 add "$H" --dev --waiver-id WD --yes; eq "setup add" 0 "$RC"
TXN="$P1/.constitution/extensions.txn"
FID="$(python3 -I -c 'import os,sys; s=os.lstat(sys.argv[1]); print(__import__("json").dumps([s.st_dev,s.st_ino,s.st_mtime_ns]))' "$INST/hooks-fixture")"
e1 remove hooks-fixture --yes; eq "setup remove" 0 "$RC"
# another project's tree sits at final; a hand-written, unsigned add journal names its identity
e2 verify hooks-fixture >/dev/null 2>&1
mkdir "$INST/hooks-fixture"; cp -R "$H/." "$INST/hooks-fixture/"
FID="$(python3 -I -c 'import os,sys,json; s=os.lstat(sys.argv[1]); print(json.dumps([s.st_dev,s.st_ino,s.st_mtime_ns]))' "$INST/hooks-fixture")"
printf '{"op":"add","id":"hooks-fixture","final":"%s","sha256":"%s","record":{},"ident":%s}' "$INST/hooks-fixture" "$(printf 'a%.0s' $(seq 64))" "$FID" >"$TXN"
e1 lock; check "F2 lock refuses to overwrite a bad journal" test "$RC" != 0
check "F2 unsigned add journal did not delete the tree" test -f "$INST/hooks-fixture/extension.yml"
has "F2 warns" "unsigned" "$OUT"
check "F2 journal left in place" test -f "$TXN"
e1 add "$SB/none" --dev --yes; check "F2 add refuses while it is present" test "$RC" != 0
rm -f "$TXN"
printf '{"op":"add","id":"hooks-fixture","final":"%s","sha256":"%s","record":{},"ident":%s,"mac":"%s"}' "$INST/hooks-fixture" "$(printf 'a%.0s' $(seq 64))" "$FID" "$(printf 'b%.0s' $(seq 64))" >"$TXN"
e1 lock
check "F2 journal with a forged mac did not delete the tree" test -f "$INST/hooks-fixture/extension.yml"
check "F2 forged-mac journal left in place" test -f "$TXN"
rm -f "$TXN"; rm -rf "${INST:?}/hooks-fixture"
echo "### F2 positive: a real interrupted add is still rolled back"
CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT=add:renamed bash "$ENGINE" --root "$R" --project-root "$P1" add "$H" --dev --waiver-id WD --yes </dev/null >/dev/null 2>&1
eq "F2 killed (137)" 137 "$?"
check "F2 journal has a mac" grep -q '"mac"' "$TXN"
e1 lock; eq "F2 recovery ok" 0 "$RC"
check "F2 own tree rolled back" test ! -e "$INST/hooks-fixture"

echo "### A4 symlinked _installed"
mkdir -p "$SB/elsewhere/.staging-999999-deadbeef"; echo precious >"$SB/elsewhere/.staging-999999-deadbeef/f"
rm -rf "${INST:?}"; ln -s "$SB/elsewhere" "$INST"
e1 lock; check "A4 lock refuses (non-zero)" test "$RC" != 0
has "A4 says why" "symlink" "$OUT"
check "A4 staging dir behind the link untouched" test -f "$SB/elsewhere/.staging-999999-deadbeef/f"
e1 add "$H" --dev --waiver-id WD --yes; check "A4 add refuses" test "$RC" != 0
check "A4 nothing installed behind the link" test ! -e "$SB/elsewhere/hooks-fixture"
rm -f "$INST"

echo "### m10 staging sweep spares a live pid"
mkdir -p "$INST"
sleep 300 & LIVE=$!
mkdir "$INST/.staging-$LIVE-deadbeef"; echo x >"$INST/.staging-$LIVE-deadbeef/f"
mkdir "$INST/.staging-4194000-cafebabe"; echo x >"$INST/.staging-4194000-cafebabe/f"
e1 lock; eq "m10 lock ok" 0 "$RC"
check "m10 live-pid staging dir kept" test -f "$INST/.staging-$LIVE-deadbeef/f"
check "m10 control: dead-pid staging dir swept" test ! -e "$INST/.staging-4194000-cafebabe"
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
e1 lock
check "m10 dead pid now swept" test ! -e "$INST/.staging-$LIVE-deadbeef"

echo "### D1 an unproven trash keeps the state record"
SD="$P1/.constitution/extensions.state"; mkdir -p "$SD"
printf '{}' >"$SD/ghost-fixture.json"
mkdir "$INST/.trash-999998-cafebabe"; echo precious >"$INST/.trash-999998-cafebabe/f"
printf '{"op":"remove","id":"ghost-fixture","final":"%s","aux":"%s"}' "$INST/ghost-fixture" "$INST/.trash-999998-cafebabe" >"$TXN"; sign_journal "$TXN" "$P1"
e1 lock
check "D1 trash kept" test -f "$INST/.trash-999998-cafebabe/f"
check "D1 record kept with it" test -f "$SD/ghost-fixture.json"
rm -rf "${INST:?}/.trash-999998-cafebabe"
printf '{"op":"remove","id":"ghost-fixture","final":"%s","aux":"%s"}' "$INST/ghost-fixture" "$INST/.trash-999997-cafebabe" >"$TXN"; sign_journal "$TXN" "$P1"
e1 lock
check "D1 control: no trash at all -> record completed away" test ! -e "$SD/ghost-fixture.json"
finish
