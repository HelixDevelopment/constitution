#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_ownership_e01.sh — ownership redesign WAVE 2, item E01 (docs/design/extension_engine_ownership_redesign.md,
# section 5.3, defect P10 / plan F-1): the "installed by THIS checkout" fact is written ONLY by `add`, signed with
# the per-checkout key and bound to the constitution root realpath and the installed tree identity (device, inode,
# digest). `enable` refreshes consent only and never creates the fact; `remove` requires a valid fact.
# Real engine, real files, real git repos (§11.4.289). Test-first (§11.4.224): written before the engine change.
# Paired mutations: test_ownership_e01_mutations.sh.
T_NAME=ownership-e01
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
: "${SB:?}"
R="$SB/croot"; P1="$SB/p1"; P2="$SB/p2"; make_root "$R"; make_project "$P1"; make_project "$P2"
H="$SB/src"; copy_fixture hooks-fixture "$H"; copy_fixture hello-fixture "$R/extensions/hello-fixture"
INST="$R/extensions/_installed"
e1() { eng --root "$R" --project-root "$P1" "$@"; }
e2() { eng --root "$R" --project-root "$P2" "$@"; }
SD2="$P2/.constitution/extensions.state"; SD1="$P1/.constitution/extensions.state"
FACT="hooks-fixture.added.json"
# sign_fact PROJECT_STATE_DIR JSON-BODY -> writes a validly signed fact file (the test reads the sandbox key)
sign_fact() {
  python3 -I - "$1" "$2" <<'PY'
import hashlib, hmac, json, os, sys
sd, body = sys.argv[1], json.loads(sys.argv[2])
key = open(os.path.join(sd, "key"), "rb").read().strip()
msg = b"added-fact\0" + json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
doc = dict(body, mac=hmac.new(key, msg, hashlib.sha256).hexdigest())
p = os.path.join(sd, "hooks-fixture.added.json")
open(p, "w").write(json.dumps(doc, sort_keys=True) + "\n"); os.chmod(p, 0o600)
PY
}
good_body() { # project-state-dir -> the correct body for the tree currently at INST/hooks-fixture
  python3 -I - "$R" "$INST/hooks-fixture" "$1" <<'PY'
import json, os, sys
root, tree, sd = sys.argv[1:4]
old = json.load(open(os.path.join(sd, "hooks-fixture.added.json")))
st = os.lstat(tree)
print(json.dumps({"id": "hooks-fixture", "root": os.path.realpath(root), "sha256": old["sha256"], "dev": st.st_dev, "ino": st.st_ino}))
PY
}

echo "### E01 add writes the fact"
e2 add "$H" --dev --waiver-id WD --yes; eq "setup: P2 adds" 0 "$RC"
check "E01 add wrote <id>.added.json in the state dir" test -f "$SD2/$FACT"
eq "E01 fact file is mode 0600" 600 "$(stat -c %a "$SD2/$FACT" 2>/dev/null)"
eq "E01 fact is bound to the constitution root realpath" "$(realpath "$R")" "$(jget "$(cat "$SD2/$FACT")" root)"
has "E01 fact names the tree identity" '"ino"' "$(cat "$SD2/$FACT")"
hasnt "E01 fact holds no secret key material" "$(cat "$SD2/key")" "$(cat "$SD2/$FACT")"

echo "### E01 the F-1 attack: copied lock, then enable, then remove"
mkdir -p "$P1/.constitution"; cp "$P2/.constitution/extensions.lock.yml" "$P1/.constitution/extensions.lock.yml"
e1 enable hooks-fixture --yes
check "E01 enable did NOT create the add-only fact in the second clone" test ! -e "$SD1/$FACT"
e1 remove hooks-fixture --yes
eq "E01 remove after enable in a copied-lock clone is refused (rc 3)" 3 "$RC"
check "E01 the shared tree is intact" test -f "$INST/hooks-fixture/extension.yml"
e2 verify hooks-fixture; eq "E01 the real owner still verifies" 0 "$RC"

echo "### E01 enable by the owner keeps the fact and the owner can still remove"
e2 enable hooks-fixture --yes; eq "E01 owner enable rc 0" 0 "$RC"
check "E01 fact still there after owner enable" test -f "$SD2/$FACT"

echo "### E01 forged / mismatched facts are refused"
cp "$SD2/$FACT" "$SB/fact.good"
# bad MAC
python3 -I - "$SD2/$FACT" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["mac"] = "0" * 64; open(p, "w").write(json.dumps(d) + "\n")
PY
e2 remove hooks-fixture --yes; eq "E01 fact with a bad MAC refused" 3 "$RC"
check "E01 tree intact after bad-MAC refusal" test -f "$INST/hooks-fixture/extension.yml"
# validly signed but for another root
cp "$SB/fact.good" "$SD2/$FACT"
sign_fact "$SD2" "$(good_body "$SD2" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d["root"]="/somewhere/else"; print(json.dumps(d))')"
e2 remove hooks-fixture --yes; eq "E01 fact signed for another constitution root refused" 3 "$RC"
check "E01 tree intact after wrong-root refusal" test -f "$INST/hooks-fixture/extension.yml"
# validly signed but for another content digest
cp "$SB/fact.good" "$SD2/$FACT"
sign_fact "$SD2" "$(good_body "$SD2" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d["sha256"]="0"*64; print(json.dumps(d))')"
e2 remove hooks-fixture --yes; eq "E01 fact for another digest refused" 3 "$RC"
# legacy install: no fact at all
rm -f "$SD2/$FACT"
e2 remove hooks-fixture --yes; eq "E01 no fact (installed before facts existed): refused rc 3" 3 "$RC"
has "E01 the refusal says what is missing" "fact" "$OUT"
check "E01 tree intact" test -f "$INST/hooks-fixture/extension.yml"
# control: the genuine fact is accepted
cp "$SB/fact.good" "$SD2/$FACT"
# validly signed but for another tree identity (inode): the lock entry is dropped, the tree is left in place
sign_fact "$SD2" "$(good_body "$SD2" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d["ino"]+=1; print(json.dumps(d))')"
e2 remove hooks-fixture --yes
eq "E01 fact for another tree identity: remove drops only the lock entry (rc 0)" 0 "$RC"
check "E01 the tree it could not prove is left in place" test -f "$INST/hooks-fixture/extension.yml"
has "E01 the decision is reported" "left in place" "$OUT"
safe_rm_rf "${INST:?}/hooks-fixture"
e2 add "$H" --dev --waiver-id WD --yes; eq "E01 setup: fresh add" 0 "$RC"
e2 remove hooks-fixture --yes; eq "E01 control: the genuine owner with the genuine fact removes (rc 0)" 0 "$RC"
check "E01 control: tree gone" test ! -e "$INST/hooks-fixture"
check "E01 control: fact deleted with the lock entry" test ! -e "$SD2/$FACT"

echo "### E01 an add killed after the lock was written rolls the fact forward"
KP="$SB/kp"; make_project "$KP"
OUT="$(CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT=add:locked bash "$ENGINE" --root "$R" --project-root "$KP" add "$H" --dev --waiver-id WD --yes </dev/null 2>&1)"; RC=$?
check "E01 the add was killed at add:locked (journal left behind)" test -f "$KP/.constitution/extensions.txn"
e_kp() { eng --root "$R" --project-root "$KP" "$@"; }
check "E01 before recovery the fact is not there yet" test ! -e "$KP/.constitution/extensions.state/$FACT"
e_kp list >/dev/null; e_kp lock >/dev/null     # a read-only run never recovers; a mutating run does
check "E01 after recovery the fact exists" test -f "$KP/.constitution/extensions.state/$FACT"
e_kp remove hooks-fixture --yes; eq "E01 the recovered owner can remove (rc 0)" 0 "$RC"
finish
