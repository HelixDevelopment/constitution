#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016  # T_NAME, OUT and RC are shared with lib.sh; literal $ / backticks are test data
# test_provenance.sh — round-2 security review findings, replayed through the REAL engine CLI:
#   P1 forged wiring entry over a user's own command file (IMPORTANT-1): wiring entries are bound to
#      the local HMAC wiring record or to an on-disk managed-by marker; anything else is refused
#   P2 portable wiring: project-relative entries and relative Claude links; wire, commit, clone, then
#      verify / unwire / disable inside the clone (IMPORTANT-2)
#   P3 catalog revocation enforced by wire and enable (IMPORTANT-3)
#   P4 agent-side execution constructs in command bodies must be declared (IMPORTANT-4)
#   P5 reviewer mutation gaps M01 M03 M12 M13 M15 M16 M17 M20 M24 M26 (IMPORTANT-5) and the MINOR list
# Real engine, real git, real files in a mktemp sandbox; $HOME is never touched.
# Usage: bash tests/extensions/test_provenance.sh   (exit 0 iff every assertion passed)
T_NAME=provenance
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
: "${SB:?}"
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
INST="$R/extensions/_installed"
e() { eng --root "$R" --project-root "$P" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
sha() { sha256sum "$1" | cut -c1-64; }
DIGEST() { bash "$ENGINE" --json validate "$1" 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("sha256",""))'; }
mkext() { # DIR ID — valid one-command extension with id ID (copy of the labelled hello-fixture)
  copy_fixture hello-fixture "$1"
  python3 -I - "$1" "$2" <<'PY'
import os, sys
d, i = sys.argv[1], sys.argv[2]
p = os.path.join(d, "extension.yml"); s = open(p).read()
s = s.replace("id: hello-fixture", "id: " + i).replace("- name: hello-fixture", "- name: " + i)
open(p, "w").write(s)
os.rename(os.path.join(d, "commands", "hello-fixture"), os.path.join(d, "commands", i))
PY
}
yrep() { python3 -I - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, ("anchor not unique", old)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
lockedit() { # PROJECT ID PYEXPR — edits one lock entry `e` with a python statement
  python3 -I - "$1/.constitution/extensions.lock.yml" "$2" "$3" "$(dirname "$ENGINE")" <<'PY'
import sys
p, eid, stmt, d = sys.argv[1:5]
sys.path.insert(0, d)
import ext_yaml
doc = ext_yaml.parse(open(p).read(), max_bytes=1 << 26, max_lines=10**6, max_nodes=10**7)
for e in doc["extensions"]:
    if e["id"] == eid:
        exec(stmt)
open(p, "w").write(ext_yaml.dump(doc))
PY
}
W="$P/.constitution/extensions.wiring.yml"
plant() { # agent id command path root sha256 — one file entry (no shell quoting of values needed)
  mkdir -p "$P/.constitution"
  printf 'wiring_version: "1"\nentries:\n  - agent: "%s"\n    command: "%s"\n    id: "%s"\n    kind: "file"\n    path: "%s"\n    root: "%s"\n    sha256: "%s"\n    target: null\n' \
    "$1" "$3" "$2" "$4" "$5" "$6" >"$W"
}

echo "### P1 forged wiring entry over a user's own command file (exact attack)"
mkdir -p "$P/.opencode/commands"; printf 'my own command, written by the user\n' >"$P/.opencode/commands/mine.md"
cp "$P/.opencode/commands/mine.md" "$SB/mine.bak"
for form in absolute relative; do
  if [ "$form" = absolute ]; then plant opencode ghost mine "$P/.opencode/commands/mine.md" "$P" "$(sha "$P/.opencode/commands/mine.md")"
  else plant opencode ghost mine ".opencode/commands/mine.md" "." "$(sha "$P/.opencode/commands/mine.md")"; fi
  e unwire --agent all; check "P1 $form: unwire over a forged entry refused" test "$RC" -ne 0
  check "P1 $form: user's own command file survives unwire" cmp -s "$P/.opencode/commands/mine.md" "$SB/mine.bak"
  e verify; eq "P1 $form: verify reports the forged entry (5)" 5 "$RC"
done
has "P1 refusal explains the missing binding" "not bound" "$OUT"
has "P1 verify names an id that is not in the lock" "not in the lock" "$OUT"
# forged signed record: a wiring.json written without the key must not bind the entry. The key must exist
# (enable writes it), otherwise a missing key alone would reject the record and the MAC check would be untested.
e enable hello-fixture --yes; eq "P1 enable bundled" 0 "$RC"
check "P1 state key exists before the forged record" test -f "$P/.constitution/extensions.state/key"
python3 -I - "$P/.constitution/extensions.state/wiring.json" "$(sha "$P/.opencode/commands/mine.md")" <<'PY'
import json, sys
p, h = sys.argv[1:3]
ent = {"agent": "opencode", "command": "mine", "id": "ghost", "kind": "file", "path": ".opencode/commands/mine.md",
       "root": ".", "sha256": h, "target": None}
open(p, "w").write(json.dumps({"entries": [ent], "mac": "0" * 64}))
PY
e unwire --agent all; check "P1 forged signed record (no key) does not bind" test "$RC" -ne 0
check "P1 user file survives forged signed record" cmp -s "$P/.opencode/commands/mine.md" "$SB/mine.bak"
e verify; has "P1 verify reports the forged signed record" "integrity check" "$OUT"
rm -f "$P/.constitution/extensions.state/wiring.json"
# the same attack against wire: a forged entry with the user's sha for a real enabled command
printf 'my notes about hello\n' >"$P/.opencode/commands/hello-fixture.md"; cp "$P/.opencode/commands/hello-fixture.md" "$SB/hello.bak"
for form in absolute relative; do
  if [ "$form" = absolute ]; then plant opencode hello-fixture hello-fixture "$P/.opencode/commands/hello-fixture.md" "$P" "$(sha "$SB/hello.bak")"
  else plant opencode hello-fixture hello-fixture ".opencode/commands/hello-fixture.md" "." "$(sha "$SB/hello.bak")"; fi
  e wire --agent opencode; check "P1 $form: wire over a forged entry refused" test "$RC" -ne 0
  check "P1 $form: user's file not overwritten by wire" cmp -s "$P/.opencode/commands/hello-fixture.md" "$SB/hello.bak"
  e unwire hello-fixture --agent opencode; check "P1 $form: unwire of the forged real-id entry refused" test "$RC" -ne 0
  check "P1 $form: user's file not deleted by unwire" cmp -s "$P/.opencode/commands/hello-fixture.md" "$SB/hello.bak"
done
rm -f "$W" "$P/.opencode/commands/hello-fixture.md"
e wire --agent all; eq "P1 normal wire after cleanup" 0 "$RC"
check "P1 local signed wiring record written" test -f "$P/.constitution/extensions.state/wiring.json"
e verify; eq "P1 verify after normal wire" 0 "$RC"
# R11-relative: the same entries rewritten to the old absolute format (as an older engine wrote them)
cp "$W" "$SB/wiring_rel.bak"
python3 -I - "$W" "$P" <<'PY'
import sys
p, proj = sys.argv[1:3]
out = []
for ln in open(p).read().split("\n"):
    s = ln.strip()
    if s.startswith('root: "'):
        ln = ln.replace('root: "."', 'root: "%s"' % proj)
    elif s.startswith('path: "'):
        ln = ln.replace('path: "', 'path: "%s/' % proj, 1)
    out.append(ln)
open(p, "w").write("\n".join(out))
PY
check "P1 old-format wiring file has absolute paths" grep -q "root: \"$P\"" "$W"
e verify; eq "P1 old absolute-format wiring refused by verify (5)" 5 "$RC"
has "P1 old format named as non-portable" "non-portable" "$OUT"
cp "$SB/wiring_rel.bak" "$W"
e verify; eq "P1 verify after restoring the relative wiring" 0 "$RC"
e unwire --agent all; eq "P1 normal unwire" 0 "$RC"
check "P1 normal unwire removed the engine's shim" test ! -e "$P/.gemini/commands/hello-fixture.toml"
check "P1 user's mine.md untouched throughout" cmp -s "$P/.opencode/commands/mine.md" "$SB/mine.bak"
e disable hello-fixture; eq "P1 disable" 0 "$RC"

echo "### P2 portable wiring: wire, commit, clone, verify/unwire/disable in the clone"
R2="$SB/croot2"; make_root "$R2"; copy_fixture hello-fixture "$R2/extensions/hello-fixture"
git -C "$R2" add -A && git -C "$R2" commit -q -m "bundle fixture"
PC="$SB/pc"; make_project "$PC"
git -C "$PC" submodule add -q "$R2" constitution 2>/dev/null; eq "P2 submodule add" 0 "$?"
git -C "$PC" commit -q -m "add constitution"
ec() { eng --root "$PC/constitution" --project-root "$PC" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
mkext "$SB/pinst" pinst
ec enable hello-fixture --yes; eq "P2 enable bundled" 0 "$RC"
ec add "$SB/pinst" --waiver-id WP2 --yes; eq "P2 add installed" 0 "$RC"
ec enable pinst --yes; eq "P2 enable installed" 0 "$RC"
ec wire --agent all; eq "P2 wire all" 0 "$RC"
lt="$(readlink "$PC/.claude/skills/hello-fixture")"
case "$lt" in /*) nok "P2 claude link target is relative (got $lt)";; *) ok "P2 claude link target is relative";; esac
hasnt "P2 wiring file holds no absolute sandbox path" "$SB" "$(cat "$PC/.constitution/extensions.wiring.yml")"
git -C "$PC" add -A .constitution .claude .opencode .gemini .qwen .pi && git -C "$PC" commit -q -m "wired"
eq "P2 commit of wired state" 0 "$?"
CL="$SB/clone"; git clone -q --recurse-submodules "$PC" "$CL" 2>/dev/null; eq "P2 clone" 0 "$?"
ecl() { eng --root "$CL/constitution" --project-root "$CL" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
check "P2 clone: claude link resolves inside the clone" test -f "$CL/.claude/skills/hello-fixture/SKILL.md"
rl="$(realpath "$CL/.claude/skills/hello-fixture")"
case "$rl" in "$CL"/*) ok "P2 clone link resolves under the clone";; *) nok "P2 clone link resolves to $rl";; esac
ecl verify; check "P2 clone verify fails before re-consent (R17)" test "$RC" -ne 0
hasnt "P2 clone verify never says 'outside the project'" "outside the project" "$OUT"
has "P2 clone names the missing installed tree" "_installed" "$OUT"
has "P2 clone message is actionable (git-ignored)" "git-ignored" "$OUT"
ecl enable hello-fixture --yes; eq "P2 clone re-consent bundled" 0 "$RC"
ecl verify hello-fixture; eq "P2 clone verify bundled after re-consent" 0 "$RC"
ecl unwire --agent all; eq "P2 clone unwire" 0 "$RC"
check "P2 clone: bundled claude link removed" test ! -L "$CL/.claude/skills/hello-fixture"
check "P2 clone: installed (dangling) claude link removed" test ! -L "$CL/.claude/skills/pinst"
check "P2 clone: installed opencode shim removed" test ! -e "$CL/.opencode/commands/pinst.md"
check "P2 clone: bundled gemini shim removed" test ! -e "$CL/.gemini/commands/hello-fixture.toml"
ecl disable hello-fixture; eq "P2 clone disable bundled" 0 "$RC"
ecl disable pinst; eq "P2 clone disable installed" 0 "$RC"
ec verify; eq "P2 original checkout still verifies" 0 "$RC"

echo "### P3 catalog revocation enforced by wire and enable"
P3="$SB/p3"; make_project "$P3"
e3() { eng --root "$R" --project-root "$P3" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
e3 enable hello-fixture --yes; eq "P3 enable before revocation" 0 "$RC"
printf '{"schema_version":"1.0","catalog":{"id":"c","install_allowed":true,"trust_tier":"community"},"revoked":[{"id":"hello-fixture","version":"*","reason":"TEST revocation"}],"extensions":{}}' >"$SB/rev.json"
e3 catalog "$SB/rev.json"; eq "P3 import revoking catalog" 0 "$RC"
e3 wire --agent all; eq "P3 wire of a revoked extension refused (3)" 3 "$RC"; has "P3 wire names the revocation" "revoked" "$OUT"
check "P3 no shim written for a revoked extension" test ! -e "$P3/.claude/skills/hello-fixture"
check "P3 no opencode shim for a revoked extension" test ! -e "$P3/.opencode/commands/hello-fixture.md"
P3b="$SB/p3b"; make_project "$P3b"
eng --root "$R" --project-root "$P3b" catalog "$SB/rev.json"
eng --root "$R" --project-root "$P3b" enable hello-fixture --yes; eq "P3 enable of a revoked extension refused (3)" 3 "$RC"
check "P3 revoked enable wrote no lock" sh -c '! grep -q hello-fixture "$1" 2>/dev/null' _ "$P3b/.constitution/extensions.lock.yml"

echo "### P4 agent-side execution constructs in command bodies"
P4="$SB/p4"; make_project "$P4"
e4() { eng --root "$R" --project-root "$P4" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
n=0
for kind in 'shell:!{date}' 'shell:!`date`' 'files:@{/etc/hosts}' 'files:read @/etc/hosts now' 'files:see @./notes.md' 'shell:FM'; do
  n=$((n+1)); cls="${kind%%:*}"; body="${kind#*:}"; D="$SB/ax$n"; mkext "$D" "ax$n"
  S="$D/commands/ax$n/SKILL.md"
  if [ "$body" = FM ]; then yrep "$S" 'argument-hint: "[name]"' 'argument-hint: "[name]"
allowed-tools: Bash(date)'
  else printf '\nRun this: %s\n' "$body" >>"$S"; fi
  e4 validate "$D"; eq "P4 [$cls ${body:0:20}] undeclared construct: validate fails (1)" 1 "$RC"
  if [ "$cls" = shell ]; then has "P4 [$body] names agent_shell" "agent_shell" "$OUT"; else has "P4 [$body] names reads_files" "reads_files" "$OUT"; fi
  e4 add "$D" --waiver-id WP4 --yes; eq "P4 [$cls ${body:0:20}] undeclared construct: add refused (3)" 3 "$RC"
  check "P4 [$cls ${body:0:20}] not installed" test ! -e "$INST/ax$n"
  key=agent_shell; [ "$cls" = files ] && key=reads_files
  yrep "$D/extension.yml" "  executes: []" "  executes: []
  $key:
    - ax$n"
  e4 validate "$D"; eq "P4 [$cls ${body:0:20}] declared construct validates (0)" 0 "$RC"
done
OUT="$(bash "$ENGINE" --root "$R" --project-root "$P4" --json add "$SB/ax1" --waiver-id WP4 --yes </dev/null 2>"$SB/consent.err")"; RC=$?
eq "P4 declared shell construct installs" 0 "$RC"
has "P4 consent lists agent-shell even with --json (stderr)" "agent-shell:ax1" "$(cat "$SB/consent.err")"
e4 enable ax1 --yes; eq "P4 enable declared" 0 "$RC"; has "P4 enable consent lists agent-shell" "agent-shell:ax1" "$OUT"
e4 wire ax1 --agent gemini; eq "P4 wire declared" 0 "$RC"
has "P4 consented construct copied into the gemini shim" '!{date}' "$(cat "$P4/.gemini/commands/ax1.toml")"
e4 unwire --agent all; e4 remove ax1 --yes; eq "P4 cleanup" 0 "$RC"
mkext "$SB/axd" axd; printf '\nmail a@b.example or x_y@host.invalid\n' >>"$SB/axd/commands/axd/SKILL.md"
e4 validate "$SB/axd"; eq "P4 an e-mail address is not file injection (0)" 0 "$RC"
mkext "$SB/axm" axm; printf '\nhi @someone\n' >>"$SB/axm/commands/axm/SKILL.md"
e4 validate "$SB/axm"; eq "B1 an @word at a token start is file injection unless declared (round 4 class rule) (1)" 1 "$RC"
mkext "$SB/axu" axu; yrep "$SB/axu/extension.yml" "  executes: []" "  executes: []
  agent_shell:
    - not-a-command"
e4 validate "$SB/axu"; eq "P4 agent_shell naming an unknown command fails (1)" 1 "$RC"
# bundled extension with an undeclared construct: enable refuses
R4="$SB/croot4"; make_root "$R4"; copy_fixture hello-fixture "$R4/extensions/hello-fixture"
P4b="$SB/p4b"; make_project "$P4b"
printf '\n!{id}\n' >>"$R4/extensions/hello-fixture/commands/hello-fixture/SKILL.md"
eng --root "$R4" --project-root "$P4b" enable hello-fixture --yes; eq "P4 bundled undeclared construct: enable refused (3)" 3 "$RC"
# enabled, then a constitution update adds an undeclared construct and the lock is refreshed: wire refuses
R5="$SB/croot5"; make_root "$R5"; copy_fixture hello-fixture "$R5/extensions/hello-fixture"
P5="$SB/p5"; make_project "$P5"
e5() { eng --root "$R5" --project-root "$P5" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
e5 enable hello-fixture --yes; eq "P4 enable clean bundled" 0 "$RC"
printf '\n!{id}\n' >>"$R5/extensions/hello-fixture/commands/hello-fixture/SKILL.md"
e5 lock; eq "P4 lock refuses to refresh an enabled entry that gained an undeclared construct (3)" 3 "$RC"
has "M3 a refused refresh says the lock is only partially written" "PARTIALLY written" "$OUT"
hasnt "M3 no unqualified 'lock written:' when an entry was refused" "lock written:" "$OUT"
e5 wire --agent all; eq "P4 wire refuses after the refused refresh (5)" 5 "$RC"
check "P4 no shim written" test ! -e "$P5/.opencode/commands/hello-fixture.md"
check "P4 no shim written for undeclared construct" test ! -e "$P5/.gemini/commands/hello-fixture.toml"
# I2: a Claude shim links to a consented snapshot, so a constitution update cannot reach the agent before a new
# consent: the shim keeps serving the consented text, verify and lock refuse, enable + wire switch to the new text
R7="$SB/croot7"; make_root "$R7"; copy_fixture hello-fixture "$R7/extensions/hello-fixture"
P7="$SB/p7"; make_project "$P7"
e7() { eng --root "$R7" --project-root "$P7" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
e7 enable hello-fixture --yes; eq "I2 enable" 0 "$RC"
e7 wire --agent claude; eq "I2 wire claude" 0 "$RC"
S7="$P7/.claude/skills/hello-fixture/SKILL.md"
old7="$(cat "$S7")"
case "$(realpath "$P7/.claude/skills/hello-fixture")" in
  "$(realpath "$P7")/.constitution/extensions.snapshots/"*) ok "I2 claude shim resolves into the snapshot store";;
  *) nok "I2 claude shim resolves to $(realpath "$P7/.claude/skills/hello-fixture")";; esac
printf '\nI2 UPDATED TEXT\n' >>"$R7/extensions/hello-fixture/commands/hello-fixture/SKILL.md"
eq "I2 shim still serves the consented text after the update" "$old7" "$(cat "$S7")"
e7 verify hello-fixture; eq "I2 verify reports the change (5)" 5 "$RC"
e7 lock; eq "I2 lock refreshes a change that adds no capability (0)" 0 "$RC"
eq "I2 shim unchanged after lock (only wire changes what the agent sees)" "$old7" "$(cat "$S7")"
e7 wire --agent claude; eq "I2 wire after the refresh" 0 "$RC"
has "I2 shim serves the new text after wire" "I2 UPDATED TEXT" "$(cat "$S7")"
printf '\n!{id}\n' >>"$R7/extensions/hello-fixture/commands/hello-fixture/SKILL.md"
e7 lock; eq "I2 lock refuses a change that adds an undeclared construct (3)" 3 "$RC"
e7 wire --agent claude; check "I2 wire refuses it" test "$RC" -ne 0
hasnt "I2 the agent never sees the undeclared construct" '!{id}' "$(cat "$S7")"
printf '%s\n' "$(sed '$d' "$R7/extensions/hello-fixture/commands/hello-fixture/SKILL.md")" \
  >"$SB/s7.tmp" && cat "$SB/s7.tmp" >"$R7/extensions/hello-fixture/commands/hello-fixture/SKILL.md"
e7 lock; eq "I2 lock after the construct is removed again" 0 "$RC"
n7="$(find "$P7/.constitution/extensions.snapshots" -mindepth 3 -maxdepth 3 -type d | wc -l)"
eq "I2 the superseded snapshot was removed" 1 "$n7"
e7 verify hello-fixture; eq "I2 verify clean after re-wire" 0 "$RC"
e7 unwire --agent claude; eq "I2 unwire" 0 "$RC"
check "I2 snapshot store emptied by unwire" test -z "$(find "$P7/.constitution/extensions.snapshots" -mindepth 1 2>/dev/null)"
# capabilities changed since consent: wire refuses, verify reports (M26)
R6="$SB/croot6"; make_root "$R6"; copy_fixture hello-fixture "$R6/extensions/hello-fixture"
P6="$SB/p6"; make_project "$P6"
e6() { eng --root "$R6" --project-root "$P6" "$@"; hasnt "no traceback: $*" "Traceback" "$OUT"; }
e6 enable hello-fixture --yes; eq "M26 enable" 0 "$RC"
yrep "$R6/extensions/hello-fixture/extension.yml" "  network: []" "  network:
    - example.org"
e6 lock; e6 verify hello-fixture; eq "M26 capabilities changed since consent: verify (5)" 5 "$RC"
has "M26 message" "capabilities changed since consent" "$OUT"
e6 wire --agent all; eq "P4 wire refuses when capabilities changed since consent (5)" 5 "$RC"
check "P4 no shim when consent is stale" test ! -e "$P6/.claude/skills/hello-fixture"

echo "### P5 reviewer mutation gaps"
mkdir -p "${P}-evil"
e enable hello-fixture --yes
e wire --agent opencode --target "${P}-evil"; eq "M01 sibling directory sharing the project prefix refused (3)" 3 "$RC"
check "M01 nothing written in the sibling" test ! -e "${P}-evil/.opencode"
# M03: nonce file readable by others -> test seams stay inert
NM="$SB/nm"; mkdir -p "$NM"; PN="$NM/p"; make_project "$PN"
printf '%s\n' "$CONSTITUTION_EXT_TEST_NONCE" >"$NM/.constitution-ext-test-nonce"; chmod 644 "$NM/.constitution-ext-test-nonce"
OUT="$(CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT=enable:locked bash "$ENGINE" --root "$R" --project-root "$PN" enable hello-fixture --yes </dev/null 2>&1)"; RC=$?
eq "M03 group/other-readable nonce file: kill seam inert (enable completes)" 0 "$RC"
# M12: disable must not re-sign a tampered entry
mkext "$SB/m12" m12; e add "$SB/m12" --waiver-id W12 --yes; eq "M12 setup add" 0 "$RC"
lockedit "$P" m12 'e["enabled"] = True; e["consent"] = {"capabilities": ["command:m12", "network:evil.example"], "mode": "tty"}'
e disable m12; eq "M12 disable of a tampered entry still disables (0)" 0 "$RC"
e verify m12; eq "M12 disable did not launder the tampered consent (5)" 5 "$RC"; has "M12 names consent" "consent" "$OUT"
e remove m12 --yes
# M13: state key readable by others
mkext "$SB/m13" m13; e add "$SB/m13" --waiver-id W13 --yes
chmod 644 "$P/.constitution/extensions.state/key"
e verify m13; eq "M13 state key with mode 0644 fails verify (5)" 5 "$RC"; has "M13 names the mode" "0600" "$OUT"
chmod 600 "$P/.constitution/extensions.state/key"; e remove m13 --yes
# M16: an installed extension may not take a bundled id
mkext "$SB/m16" hello-fixture; echo shadow >"$SB/m16/shadow.txt"
e add "$SB/m16" --waiver-id W16 --yes; eq "M16 installed extension with a bundled id refused (3)" 3 "$RC"; has "M16 says bundled" "bundled" "$OUT"
check "M16 nothing installed" test ! -e "$INST/hello-fixture"
# M17: a discovery-only catalog never installs
mkext "$SB/m17src" catx; M17SHA="$(ext_git_repo "$SB/m17src" "$SB/m17repo")"; M17D="$(DIGEST "$SB/m17repo")"
P7="$SB/p7"; make_project "$P7"
printf '{"schema_version":"1.0","catalog":{"id":"disc","install_allowed":false,"trust_tier":"community"},"revoked":[],"extensions":{"catx":{"latest":"1.0.0","releases":{"1.0.0":{"url":"file://%s","git_sha":"%s","sha256":"%s"}}}}}' \
  "$SB/m17repo" "$M17SHA" "$M17D" >"$SB/disc.json"
eng --root "$R" --project-root "$P7" catalog "$SB/disc.json"; eq "M17 import discovery-only catalog" 0 "$RC"
eng --root "$R" --project-root "$P7" add catx --yes; eq "M17 install from a discovery-only catalog refused (3)" 3 "$RC"
has "M17 says discovery-only" "discovery-only" "$OUT"; check "M17 nothing installed" test ! -e "$INST/catx"
# M20: the installed copy never keeps source modes
mkext "$SB/m20" m20; chmod 600 "$SB/m20/commands/m20/SKILL.md"; printf '#!/bin/sh\n' >"$SB/m20/tool.sh"; chmod 775 "$SB/m20/tool.sh"
e add "$SB/m20" --waiver-id W20 --yes; eq "M20 add" 0 "$RC"
eq "M20 installed regular file mode normalised to 644" 644 "$(stat -c %a "$INST/m20/commands/m20/SKILL.md")"
eq "M20 installed executable mode normalised to 755" 755 "$(stat -c %a "$INST/m20/tool.sh")"
e remove m20 --yes
# M24: a gitlink (submodule) entry in a git source is refused
mkext "$SB/m24src" m24; M24SHA="$(ext_git_repo "$SB/m24src" "$SB/m24repo")"
git -C "$SB/m24repo" update-index --add --cacheinfo "160000,$M24SHA,sub" && git -C "$SB/m24repo" commit -q -m gitlink
M24SHA="$(git -C "$SB/m24repo" rev-parse HEAD)"
e add "file://$SB/m24repo" --sha "$M24SHA" --waiver-id W24 --yes; eq "M24 gitlink in a git source refused (3)" 3 "$RC"
has "M24 names submodules" "submodule" "$OUT"; check "M24 nothing installed" test ! -e "$INST/m24"

echo "### P6 MINOR findings"
TOK="$(fake_token gh)"
e add "$SB/m12" --waiver-id "$TOK" --yes; eq "secret-shaped --waiver-id refused (2)" 2 "$RC"; hasnt "waiver token not echoed" "$TOK" "$OUT"
SK="$(fake_token sk)"; e add "$SB/m12" --waiver-id "${SK:0:40}" --yes; eq "sk- shaped --waiver-id refused (2)" 2 "$RC"
hasnt "W12-style waiver never recorded secret" "$TOK" "$(cat "$P/.constitution/extensions.lock.yml" "$P/.constitution/extensions.audit.log" 2>/dev/null)"
e add "https://example.invalid/x.git?private_token=plainvalue77" --sha "$(printf 'a%.0s' $(seq 40))" --sha256 "$(printf '0%.0s' $(seq 64))" --yes
eq "query-string token in URL refused (3)" 3 "$RC"; hasnt "query-string token not echoed" "plainvalue77" "$OUT"
e --dry-run add "https://example.invalid/x.git?ref=main&access_token=plainvalue88" --sha "$(printf 'a%.0s' $(seq 40))" --sha256 "$(printf '0%.0s' $(seq 64))" --yes
hasnt "dry-run never echoes a query token" "plainvalue88" "$OUT"
e --dry-run add "https://example.invalid/x.git?ref=plainvalue99" --sha "$(printf 'a%.0s' $(seq 40))" --sha256 "$(printf '0%.0s' $(seq 64))" --yes
eq "dry-run of an allowed query URL succeeds (0)" 0 "$RC"; has "dry-run says what it would clone" "would clone" "$OUT"
hasnt "dry-run redacts every query value" "plainvalue99" "$OUT"; has "dry-run shows the redaction marker" "<redacted>" "$OUT"
mkext "$SB/gs" gsx; GSHA="$(ext_git_repo "$SB/gs" "$SB/gsrepo")"
e add "file://$SB/gsrepo" --sha "$GSHA" --yes; eq "git source with --sha but no content sha256 refused (3)" 3 "$RC"; has "names --sha256" "sha256" "$OUT"
e add "file://$SB/gsrepo" --sha "$GSHA" --sha256 "$(DIGEST "$SB/gsrepo")" --yes; eq "git source with --sha and --sha256 installs" 0 "$RC"
e remove gsx --yes
PA="$SB/pa"; make_project "$PA"; mkdir -p "$PA/.constitution"; echo outside >"$SB/audit_target"
ln -s "$SB/audit_target" "$PA/.constitution/extensions.audit.log"
eng --root "$R" --project-root "$PA" enable hello-fixture --yes; check "symlinked audit log refused up front" test "$RC" -ne 0
check "symlinked audit log: nothing written (no lock)" test ! -e "$PA/.constitution/extensions.lock.yml"
eq "symlinked audit log target untouched" outside "$(cat "$SB/audit_target")"
mkext "$P/vendor/inproj" inproj; e add "$P/vendor/inproj" --dev --waiver-id WIP --yes; eq "in-project --dev source installs" 0 "$RC"
lk="$(cat "$P/.constitution/extensions.lock.yml")"; has "in-project source recorded project-relative" "vendor/inproj" "$lk"
hasnt "in-project source not recorded as an absolute path" "$P/vendor/inproj" "$lk"
e remove inproj --yes
mkext "$SB/bv" bv; e add "$SB/bv" --waiver-id WBV --yes
lockedit "$P" bv "e['version'] = '1.0.0' + chr(0x202e) + 'x'"
e verify bv; eq "lock string with bidi char fails verify (5)" 5 "$RC"
hasnt "verify never prints a raw bidi character" "$(printf '\342\200\256')" "$OUT"; has "verify escapes it" '\u202e' "$OUT"
e remove bv --yes
RN="$SB/rootnoext"; make_root "$RN"; rmdir "$RN/extensions" 2>/dev/null || { rm -f "$RN/extensions/.keep"; rmdir "$RN/extensions"; }
eng --root "$RN" --project-root "$P3" list; eq "root without extensions/ still lists (lock taken on the root)" 0 "$RC"
# R13: the lock is on the constitution root itself, so a holder of the root lock blocks the engine even
# while <root>/extensions/ does not exist (a lock on extensions/ alone could not be taken there)
python3 -I -c 'import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDONLY); fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close(); time.sleep(float(sys.argv[3]))' "$RN" "$SB/rootheld" 8 &
HOLDER=$!
for _ in $(seq 100); do [ -e "$SB/rootheld" ] && break; sleep 0.1; done
check "R13 root lock holder started" test -e "$SB/rootheld"
OUT="$(timeout 3 bash "$ENGINE" --root "$RN" --project-root "$P3" list </dev/null 2>&1)"; RC=$?
eq "R13 engine waits for the root lock (timeout 124)" 124 "$RC"
wait "$HOLDER"
eng --root "$RN" --project-root "$P3" list; eq "R13 engine runs after the root lock is released" 0 "$RC"
finish
