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
print(json.dumps({"id": "hooks-fixture", "root": os.path.realpath(root), "sha256": old["sha256"], "dev": st.st_dev, "ino": st.st_ino,
                  "via": old.get("via", "add"), "attest": old.get("attest")}))
PY
}

echo "### E01 add writes the fact"
e2 add "$H" --dev --waiver-id WD --yes; eq "setup: P2 adds" 0 "$RC"
check "E01 add wrote <id>.added.json in the state dir" test -f "$SD2/$FACT"
eq "E01 fact file is mode 0600" 600 "$(stat -c %a "$SD2/$FACT" 2>/dev/null)"
eq "E01 fact is bound to the constitution root realpath" "$(realpath "$R")" "$(jget "$(cat "$SD2/$FACT")" root)"
has "E01 fact names the tree identity" '"ino"' "$(cat "$SD2/$FACT")"
hasnt "E01 fact holds no secret key material" "$(cat "$SD2/key")" "$(cat "$SD2/$FACT")"
eq "E01 a fact made by add says so (via add)" add "$(jget "$(cat "$SD2/$FACT")" via)"
eq "E01 a fact made by add carries no attestation" null "$(jget "$(cat "$SD2/$FACT")" attest)"

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
# pty_adopt PROJECT ATTEST TYPED [ID] -> runs adopt-install ID (default hooks-fixture) with a controlling pty (pty.fork, CONSTITUTION_EXT_NO_TTY
# unset; PTY_NO_TTY=1 keeps it set to 1) and types TYPED at the "Type the extension id" prompt. Sets OUT (pty output), RC (engine exit code) and
# PTY_PROMPT (True when the prompt was seen before anything was typed). The child is killed after 60 s.
pty_adopt() {
  local res
  local envop=(-u CONSTITUTION_EXT_NO_TTY); [ "${PTY_NO_TTY:-0}" = 1 ] && envop=(CONSTITUTION_EXT_NO_TTY=1)
  res="$(env "${envop[@]}" python3 -I - "$3" bash "$ENGINE" --root "$R" --project-root "$1" adopt-install "${4:-hooks-fixture}" --waiver-id "$2" <<'PY'
import os, pty, select, signal, sys, time
typed, argv = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
buf, sent, st = b"", False, None
deadline = time.time() + 60
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            d = os.read(fd, 4096)
        except OSError:
            d = b""
        if d:
            buf += d
            if not sent and b"Type the extension id" in buf:
                os.write(fd, (typed + "\n").encode()); sent = True
            continue
    w, s = os.waitpid(pid, os.WNOHANG)
    if w:
        st = s
        break
if st is None:
    os.kill(pid, signal.SIGKILL); _, st = os.waitpid(pid, 0)
sys.stdout.write(buf.decode("utf-8", "replace").replace("\r", ""))
print("\nPTY_PROMPT=%s PTY_RC=%d" % (sent, os.waitstatus_to_exitcode(st)))
PY
)"
  OUT="$res"; RC="$(printf '%s\n' "$res" | sed -n 's/.*PTY_RC=\(-\{0,1\}[0-9]*\)$/\1/p' | tail -1)"
  PTY_PROMPT="$(printf '%s\n' "$res" | sed -n 's/^PTY_PROMPT=\([A-Za-z]*\) .*/\1/p' | tail -1)"
}
# pty_refused LABEL PROJECT ID WANT_RC FACT_PATH -> the same refusal with an operator at a terminal who would type
# the right id: the refusal comes BEFORE the prompt (no prompt shown), so a precondition check is not masked by
# the no-terminal refusal (review round 2: mutants E12 and E17 survived while every refusal case had no tty).
pty_refused() {
  pty_adopt "$2" OPS-1 "$3" "$3"
  eq "$1 (operator at a terminal, right id ready): rc $4" "$4" "$RC"
  eq "$1: refused before the confirmation prompt" False "$PTY_PROMPT"
  check "$1: no fact written" test ! -e "$5"
}

# ── wave 2 review round 2 ─────────────────────────────────────────────────────────────────────────────────
# Q1 / F2 (operator decision 2026-11-05): an install made before E01 has a lock entry and a state record but no
# fact. Nothing is adopted implicitly (D6): re-add stays a no-op; the only way to make it removable is an explicit,
# operator-attested `adopt-install <id> --waiver-id <ref>` that writes a fact marked "adopt".
echo "### R2 Q1 legacy install: refusal names adopt-install; adopt-install is explicit and attested"
P3="$SB/p3"; make_project "$P3"; SD3="$P3/.constitution/extensions.state"
e3() { eng --root "$R" --project-root "$P3" "$@"; }
e3 add "$H" --dev --waiver-id WD --yes; eq "R2 setup: P3 adds" 0 "$RC"
rm -f "$SD3/$FACT"                                  # what an install made by a pre-E01 engine looks like
e3 remove hooks-fixture --yes; eq "R2 legacy: remove refused rc 3" 3 "$RC"
has "R2 legacy: the refusal names the next step (adopt-install)" "adopt-install hooks-fixture" "$OUT"
hasnt "R2 legacy: the refusal no longer claims only the add checkout can remove it" "Only the checkout that ran" "$OUT"
has "R2 legacy: the refusal says a copy of the checkout carries the fact too" "copy" "$OUT"
e3 add "$H" --dev --waiver-id WD --yes; eq "R2 legacy: re-add is still a no-op (rc 0)" 0 "$RC"
check "R2 legacy: re-add created no fact (nothing adopted implicitly, D6)" test ! -e "$SD3/$FACT"
has "R2 legacy: re-add points at adopt-install" "adopt-install" "$OUT"
e3 adopt-install hooks-fixture; eq "R2 adopt-install without an attestation reference: usage rc 2" 2 "$RC"
check "R2 no fact after the usage error" test ! -e "$SD3/$FACT"
e3 adopt-install hooks-fixture --waiver-id OPS-1; eq "R2 adopt-install without a terminal (CONSTITUTION_EXT_NO_TTY=1): rc 3" 3 "$RC"
check "R2 no fact without confirmation" test ! -e "$SD3/$FACT"
# R3 A1 (operator decision 2026-11-05, safe default 11.4.101): confirmation is the /dev/tty prompt only; no flag
# replaces it, and no refusal names a bypass flag
has "R3 A1 the no-terminal refusal says an operator at a terminal is needed" "an operator at a terminal" "$OUT"
hasnt "R3 A1 the no-terminal refusal names no bypass flag (--yes)" "--yes" "$OUT"
has "R3 A1 the no-terminal refusal says nothing was adopted" "nothing adopted" "$OUT"
e3 adopt-install hooks-fixture --waiver-id OPS-1 --yes; eq "R3 A1 adopt-install does not accept --yes (usage rc 2)" 2 "$RC"
has "R3 A1 the --yes refusal is the usage error" "does not accept --yes" "$OUT"
check "R3 A1 no fact after adopt-install --yes" test ! -e "$SD3/$FACT"
# no controlling terminal at all (setsid, NO_TTY unset): the /dev/tty open fails; same refusal, no bypass named
OUT="$(env -u CONSTITUTION_EXT_NO_TTY setsid -w bash "$ENGINE" --root "$R" --project-root "$P3" adopt-install hooks-fixture --waiver-id OPS-1 </dev/null 2>&1)"; RC=$?
eq "R3 A1 no controlling terminal: rc 3" 3 "$RC"
has "R3 A1 the /dev/tty refusal says an operator at a terminal is needed" "an operator at a terminal" "$OUT"
hasnt "R3 A1 the /dev/tty refusal names no bypass flag (--yes)" "--yes" "$OUT"
check "R3 A1 no fact without a controlling terminal" test ! -e "$SD3/$FACT"
e3 adopt-install hooks-fixture --waiver-id OPS-1 --dry-run; eq "R2 adopt-install dry-run rc 0" 0 "$RC"
check "R2 dry-run wrote no fact" test ! -e "$SD3/$FACT"
e3 adopt-install hooks-fixture --waiver-id 'ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; eq "R2 a token-shaped attestation reference is refused (rc 2)" 2 "$RC"
has "R2 the token refusal is about the reference, not a flag" "waiver" "$OUT"
# R3 R2: drive the real /dev/tty prompt through a pty (reviewer attack a2_tty_confirm.sh)
pty_adopt "$P3" OPS-1 not-the-id
eq "R3 R2 a wrong id typed at the tty prompt: rc 3" 3 "$RC"
eq "R3 R2 the tty prompt was shown" True "$PTY_PROMPT"
has "R3 R2 a wrong id is refused as not confirmed" "attestation not confirmed" "$OUT"
check "R3 R2 no fact after a wrong id" test ! -e "$SD3/$FACT"
pty_adopt "$P3" OPS-1 ""
eq "R3 R2 an empty answer at the tty prompt: rc 3" 3 "$RC"
check "R3 R2 no fact after an empty answer" test ! -e "$SD3/$FACT"
# review round 3 N3: reviewer mutants RN1 (substring match), RN2 (case-insensitive), RN3 (NO_TTY knob ignored)
pty_adopt "$P3" OPS-1 hooks-fixture-extra
eq "R4 N3 a superstring of the id (hooks-fixture-extra) at the tty prompt: rc 3" 3 "$RC"
eq "R4 N3 the prompt was shown for the superstring case" True "$PTY_PROMPT"
check "R4 N3 no fact after a superstring of the id" test ! -e "$SD3/$FACT"
pty_adopt "$P3" OPS-1 HOOKS-FIXTURE
eq "R4 N3 a case variant of the id (HOOKS-FIXTURE) at the tty prompt: rc 3" 3 "$RC"
eq "R4 N3 the prompt was shown for the case-variant case" True "$PTY_PROMPT"
check "R4 N3 no fact after a case variant of the id" test ! -e "$SD3/$FACT"
PTY_NO_TTY=1 pty_adopt "$P3" OPS-1 hooks-fixture
eq "R4 N3 CONSTITUTION_EXT_NO_TTY=1 at a real terminal, right id ready: rc 3" 3 "$RC"
eq "R4 N3 CONSTITUTION_EXT_NO_TTY=1: no prompt is shown" False "$PTY_PROMPT"
has "R4 N3 CONSTITUTION_EXT_NO_TTY=1: the refusal says terminal prompts are disabled" "terminal prompts are disabled" "$OUT"
check "R4 N3 no fact with CONSTITUTION_EXT_NO_TTY=1 at a terminal" test ! -e "$SD3/$FACT"
pty_adopt "$P3" OPS-1 hooks-fixture
eq "R2 adopt-install with attestation and the id typed at the tty: rc 0" 0 "$RC"
eq "R3 R2 the tty prompt was shown before the fact was written" True "$PTY_PROMPT"
check "R2 adopt-install wrote the fact" test -f "$SD3/$FACT"
eq "R2 the fact is marked adopted, not added" adopt "$(jget "$(cat "$SD3/$FACT")" via)"
eq "R2 the fact records the attestation reference" OPS-1 "$(jget "$(cat "$SD3/$FACT")" attest)"
eq "R2 the adopted fact is mode 0600" 600 "$(stat -c %a "$SD3/$FACT" 2>/dev/null)"
has "R2 the audit log records adopt-install with its attestation" '"op": "adopt-install"' "$(cat "$P3/.constitution/extensions.audit.log")"
has "R2 the audit line names the attestation" "OPS-1" "$(grep adopt-install "$P3/.constitution/extensions.audit.log")"
H3="$(sha256sum "$SD3/$FACT" | cut -c1-64)"
e3 adopt-install hooks-fixture --waiver-id OPS-2; eq "R2 adopt-install over a valid fact: rc 0, nothing to do" 0 "$RC"
eq "R2 the valid fact is not rewritten" "$H3" "$(sha256sum "$SD3/$FACT" | cut -c1-64)"
e3 remove hooks-fixture --yes; eq "R2 after adoption the checkout removes it (rc 0)" 0 "$RC"
check "R2 tree gone after remove of the adopted install" test ! -e "$INST/hooks-fixture"
check "R2 adopted fact deleted with the lock entry" test ! -e "$SD3/$FACT"
e3 adopt-install hooks-fixture --waiver-id OPS-1; eq "R2 adopt-install of an id not in the lock: rc 3" 3 "$RC"
pty_refused "R3 adopt-install of an id not in the lock" "$P3" hooks-fixture 3 "$SD3/$FACT"

echo "### R2 Q1 adopt-install refuses what it cannot check"
P4="$SB/p4"; make_project "$P4"; SD4="$P4/.constitution/extensions.state"
e4() { eng --root "$R" --project-root "$P4" "$@"; }
e4 add "$H" --dev --waiver-id WD --yes; eq "R2 setup: P4 adds" 0 "$RC"
rm -f "$SD4/$FACT"
P5="$SB/p5"; make_project "$P5"; mkdir -p "$P5/.constitution"; cp "$P4/.constitution/extensions.lock.yml" "$P5/.constitution/"
e5() { eng --root "$R" --project-root "$P5" "$@"; }
e5 adopt-install hooks-fixture --waiver-id OPS-1; eq "R2 copied lock with no state record: adopt-install refused rc 3" 3 "$RC"
check "R2 no fact in the copied-lock clone" test ! -e "$P5/.constitution/extensions.state/$FACT"
pty_refused "R3 copied lock with no state record" "$P5" hooks-fixture 3 "$P5/.constitution/extensions.state/$FACT"
printf 'tampered\n' >>"$INST/hooks-fixture/extension.yml"
e4 adopt-install hooks-fixture --waiver-id OPS-1; eq "R2 tree differs from the lock: adopt-install refused rc 5" 5 "$RC"
check "R2 no fact for a tree that does not verify" test ! -e "$SD4/$FACT"
pty_refused "R3 tree differs from the lock" "$P4" hooks-fixture 5 "$SD4/$FACT"
mv "$INST/hooks-fixture" "$SB/moved-tree"
e4 adopt-install hooks-fixture --waiver-id OPS-1; eq "R2 tree absent: adopt-install refused rc 3" 3 "$RC"
ln -s "$SB/moved-tree" "$INST/hooks-fixture"
e4 adopt-install hooks-fixture --waiver-id OPS-1; eq "R2 tree is a symlink: adopt-install refused rc 3" 3 "$RC"
check "R2 no fact through a symlinked tree" test ! -e "$SD4/$FACT"
pty_refused "R3 tree is a symlink" "$P4" hooks-fixture 3 "$SD4/$FACT"
rm "$INST/hooks-fixture"; safe_rm_rf "${SB:?}/moved-tree"
printf '{"forged": true}\n' >"$SD4/$FACT"; chmod 600 "$SD4/$FACT"
mkdir -p "$INST"; e4 adopt-install hooks-fixture --waiver-id OPS-1
eq "R2 adopt-install over a fact that does not verify: refused rc 3" 3 "$RC"
check "R2 an existing fact that does not verify is never overwritten" grep -q forged "$SD4/$FACT"
rm -f "$SD4/$FACT"

# a BUNDLED lock entry whose tree now sits under _installed (the bundled copy left the root) is not adoptable
P9="$SB/p9"; make_project "$P9"
eng --root "$R" --project-root "$P9" enable hello-fixture --yes; eq "R2 setup: P9 enables the bundled hello-fixture" 0 "$RC"
mv "$R/extensions/hello-fixture" "$INST/hello-fixture"
eng --root "$R" --project-root "$P9" adopt-install hello-fixture --waiver-id OPS-1
eq "R2 a bundled lock entry is never adopted as an install (rc 3)" 3 "$RC"
check "R2 no fact for a bundled entry" test ! -e "$P9/.constitution/extensions.state/hello-fixture.added.json"
pty_refused "R3 a bundled lock entry" "$P9" hello-fixture 3 "$P9/.constitution/extensions.state/hello-fixture.added.json"
mv "$INST/hello-fixture" "$R/extensions/hello-fixture"

echo "### R2 F6 a symlink at a per-id state path fails closed BEFORE anything is staged"
for leaf in "$FACT" hooks-fixture.json; do
  P6="$SB/p6-${leaf%%.*}${leaf#*.}"; P6="${P6//./_}"; make_project "$P6"; mkdir -p -m 700 "$P6/.constitution/extensions.state"
  printf 'victim\n' >"$SB/victim"; ln -s "$SB/victim" "$P6/.constitution/extensions.state/$leaf"
  eng --root "$R" --project-root "$P6" add "$H" --dev --waiver-id WD --yes
  eq "R2 F6 $leaf is a symlink: add refused rc 5" 5 "$RC"
  eq "R2 F6 $leaf: the symlink target was not written" victim "$(cat "$SB/victim")"
  check "R2 F6 $leaf: no tree was installed" test ! -e "$INST/hooks-fixture"
  check "R2 F6 $leaf: no journal left behind" test ! -e "$P6/.constitution/extensions.txn"
  check "R2 F6 $leaf: no lock entry" sh -c "! grep -q hooks-fixture '$P6/.constitution/extensions.lock.yml' 2>/dev/null"
done

echo "### R2 F7 recovery that deletes the state record deletes the fact too"
P7="$SB/p7"; make_project "$P7"; SD7="$P7/.constitution/extensions.state"
e7() { eng --root "$R" --project-root "$P7" "$@"; }
e7 add "$H" --dev --waiver-id WD --yes; eq "R2 setup: P7 adds" 0 "$RC"
OUT="$(CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT=commit:lock-written bash "$ENGINE" --root "$R" --project-root "$P7" remove hooks-fixture --yes </dev/null 2>&1)"; RC=$?
check "R2 F7 the remove was killed after the lock was written (journal left)" test -f "$P7/.constitution/extensions.txn"
check "R2 F7 precondition: lock entry already gone" sh -c "! grep -q hooks-fixture '$P7/.constitution/extensions.lock.yml'"
check "R2 F7 precondition: the fact is still there before recovery" test -f "$SD7/$FACT"
e7 lock >/dev/null
check "R2 F7 remove-journal recovery deleted the state record" test ! -e "$SD7/hooks-fixture.json"
check "R2 F7 remove-journal recovery deleted the fact" test ! -e "$SD7/$FACT"
check "R2 F7 the tree is gone" test ! -e "$INST/hooks-fixture"
# commit journals are unsigned and are written by enable/disable/lock (outer=False); a hand-made one with a delete
# stands in for an interrupted commit whose lock no longer names the id (constructed precondition, real code path)
P8="$SB/p8"; make_project "$P8"; SD8="$P8/.constitution/extensions.state"
e8() { eng --root "$R" --project-root "$P8" "$@"; }
e8 add "$H" --dev --waiver-id WD --yes; eq "R2 setup: P8 adds" 0 "$RC"
rm "$P8/.constitution/extensions.lock.yml"
printf '{"op": "commit", "records": [], "deletes": ["hooks-fixture"]}' >"$P8/.constitution/extensions.txn"
check "R2 F7 precondition: fact present before the commit-journal recovery" test -f "$SD8/$FACT"
e8 lock >/dev/null
check "R2 F7 commit-journal recovery deleted the state record" test ! -e "$SD8/hooks-fixture.json"
check "R2 F7 commit-journal recovery deleted the fact" test ! -e "$SD8/$FACT"
safe_rm_rf "${INST:?}/hooks-fixture"

echo "### R3 A1 the P10 chain stays closed: copied lock + enable + adopt-install without a terminal keeps the tree"
# reviewer attack a1_adopt_after_enable.sh: P10 installs; P11 is another project holding a copy of P10's tracked lock
# (the P10 precondition) and runs enable, which writes a valid signed state record. Round 2 let P11 then run
# adopt-install --waiver-id X --yes and remove the shared tree. Now no non-interactive path adopts.
P10="$SB/p10"; P11="$SB/p11"; make_project "$P10"; make_project "$P11"
e10() { eng --root "$R" --project-root "$P10" "$@"; }; e11() { eng --root "$R" --project-root "$P11" "$@"; }
e10 add "$H" --dev --waiver-id WD --yes; eq "R3 A1 setup: P10 adds" 0 "$RC"
mkdir -p "$P11/.constitution"; cp "$P10/.constitution/extensions.lock.yml" "$P11/.constitution/"
e11 enable hooks-fixture --yes; eq "R3 A1 setup: P11 enable on the copied lock writes a state record" 0 "$RC"
check "R3 A1 precondition: P11 holds a state record" test -f "$P11/.constitution/extensions.state/hooks-fixture.json"
e11 remove hooks-fixture --yes; eq "R3 A1 P11 remove refused (no install fact)" 3 "$RC"
hasnt "R3 A1 the remove refusal names no bypass flag for adopt-install" "adopt-install hooks-fixture --waiver-id <ref> --yes" "$OUT"
e11 adopt-install hooks-fixture --waiver-id NOT-AN-OPERATOR --yes; eq "R3 A1 P11 adopt-install --yes is a usage error" 2 "$RC"
e11 adopt-install hooks-fixture --waiver-id NOT-AN-OPERATOR; eq "R3 A1 P11 adopt-install without a terminal refused" 3 "$RC"
check "R3 A1 P11 holds no install fact" test ! -e "$P11/.constitution/extensions.state/$FACT"
e11 remove hooks-fixture --yes; eq "R3 A1 P11 remove still refused" 3 "$RC"
check "R3 A1 the shared tree P10 installed is still there" test -d "$INST/hooks-fixture"
e10 verify hooks-fixture; eq "R3 A1 P10 still verifies its install" 0 "$RC"
e10 remove hooks-fixture --yes; eq "R3 A1 cleanup: P10 removes its own install" 0 "$RC"
finish
