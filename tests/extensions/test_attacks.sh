#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_attacks.sh — adversarial attacks against the REAL engine CLI, one block per attack class from
# the independent security review (B1-B4, I1-I3, the RM1-RM8 survivor rules and the MINOR findings).
# Each block plants a hostile input, runs the engine, and asserts the SECURE behaviour: refusal with
# the right exit code, no deletion or write outside the managed paths, no secret echoed, no
# extension or git-config code executed, and no Python traceback on any output.
# Real engine, real git, real files in a mktemp sandbox; $HOME is never touched.
# Usage: bash tests/extensions/test_attacks.sh   (exit 0 iff every assertion passed)
T_NAME=attacks
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
: "${SB:?}"
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
INST="$R/extensions/_installed"
e() { eng --root "$R" --project-root "$P" "$@"; notb "$*"; }
notb() { hasnt "no traceback: $1" "Traceback" "$OUT"; }
# mkext DIR ID — a valid one-command extension with id ID (copy of the labelled hello-fixture)
mkext() {
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
sha() { sha256sum "$1" | cut -c1-64; }
DIGEST() { bash "$ENGINE" --json validate "$1" 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("sha256",""))'; }
W="$P/.constitution/extensions.wiring.yml"
plant_wiring() { # agent kind path sha256 target
  mkdir -p "$P/.constitution"
  printf 'wiring_version: "1"\nentries:\n  - agent: "%s"\n    command: "a1"\n    id: "a1"\n    kind: "%s"\n    path: "%s"\n    root: "%s"\n    sha256: %s\n    target: %s\n' \
    "$1" "$2" "$3" "$P" "$4" "$5" >"$W"
}

relp() { python3 -I -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$P"; }
plant_wiring_rel() { # agent kind relpath sha256 target  (current project-relative format, root ".")
  mkdir -p "$P/.constitution"
  printf 'wiring_version: "1"\nentries:\n  - agent: "%s"\n    command: "a1"\n    id: "a1"\n    kind: "%s"\n    path: "%s"\n    root: "."\n    sha256: %s\n    target: %s\n' \
    "$1" "$2" "$3" "$4" "$5" >"$W"
}

echo "### B1r wiring-file path injection, current relative format"
echo victim >"$SB/victim_r.txt"
plant_wiring_rel opencode file "$(relp "$SB/victim_r.txt")" "\"$(sha "$SB/victim_r.txt")\"" null
e unwire --agent all; check "B1r unwire with ../ outside entry refused" test "$RC" -ne 0
check "B1r outside victim survives" test -f "$SB/victim_r.txt"
e verify; eq "B1r verify refuses planted relative wiring (5)" 5 "$RC"
cp "$P/README.md" "$SB/readme_r.bak"
plant_wiring_rel opencode file "README.md" "\"$(sha "$P/README.md")\"" null
e unwire --agent all; check "B1r in-project non-shim relative path refused" test "$RC" -ne 0
check "B1r project README survives" cmp -s "$P/README.md" "$SB/readme_r.bak"
mkdir -p "$P/.claude/skills"; ln -s "$SB" "$P/.claude/skills/a1"
plant_wiring_rel claude symlink ".claude/skills/a1" null "\"$(relp "$SB")\""
e unwire --agent all; check "B1r relative foreign symlink target refused" test "$RC" -ne 0
check "B1r foreign link survives" test -L "$P/.claude/skills/a1"
rm -f "$P/.claude/skills/a1" "$W"
# the same entry with the engine's managed-by marker in the file, so R20 binds it and only R11 stands in the way
mkdir -p "$P/notes"; printf '# managed-by: constitution_ext id=a1 command=a1\nkeep me\n' >"$P/notes/a1.md"; cp "$P/notes/a1.md" "$SB/notes_a1.bak"
plant_wiring_rel opencode file "notes/a1.md" "\"$(sha "$P/notes/a1.md")\"" null
e unwire --agent all; eq "B1r marked file at a non-shim path refused (5)" 5 "$RC"
has "B1r refusal names the shim-path rule" "not the shim path" "$OUT"
check "B1r marked non-shim file survives" cmp -s "$P/notes/a1.md" "$SB/notes_a1.bak"
rm -f "$W" "$P/notes/a1.md"

echo "### B1 wiring-file path injection"
echo victim >"$SB/victim.txt"
plant_wiring opencode file "$SB/victim.txt" "\"$(sha "$SB/victim.txt")\"" null
e unwire --agent all; check "B1 unwire with planted outside entry refused (nonzero)" test "$RC" -ne 0
check "B1 outside victim survives unwire" test -f "$SB/victim.txt"
has "B1 message names the wiring file" "wiring" "$OUT"
e verify; eq "B1 verify refuses planted wiring (5)" 5 "$RC"
cp "$P/README.md" "$SB/readme.bak"
plant_wiring opencode file "$P/README.md" "\"$(sha "$P/README.md")\"" null
e unwire --agent all; check "B1 in-project non-shim path refused" test "$RC" -ne 0
check "B1 project README survives" cmp -s "$P/README.md" "$SB/readme.bak"
mkdir -p "$P/.opencode/commands"; printf 'x\n' >"$P/.opencode/commands/a1.md"
plant_wiring opencode file "$P/.opencode/commands/a1.md" "\"$(sha "$P/.opencode/commands/a1.md")\"" null
yrep "$W" '"a1"
    kind' '"../../etc"
    kind'
e unwire --agent all; check "B1 hostile command name in wiring refused" test "$RC" -ne 0
check "B1 shim-shaped file survives hostile-name entry" test -f "$P/.opencode/commands/a1.md"
mkdir -p "$P/.claude/skills"; ln -s "$SB" "$P/.claude/skills/a1"
plant_wiring claude symlink "$P/.claude/skills/a1" null "\"$SB\""
e unwire --agent all; check "B1 symlink entry with foreign target refused" test "$RC" -ne 0
check "B1 foreign link survives" test -L "$P/.claude/skills/a1"
rm -f "$P/.claude/skills/a1" "$P/.opencode/commands/a1.md"
mkext "$SB/b1ext" a1; e add "$SB/b1ext" --waiver-id WB1 --yes; eq "B1 setup add" 0 "$RC"
plant_wiring opencode file "$SB/victim.txt" "\"$(sha "$SB/victim.txt")\"" null
e remove a1 --yes; check "B1 remove with planted entry refused" test "$RC" -ne 0
check "B1 victim survives remove" test -f "$SB/victim.txt"
e disable a1; check "B1 disable with planted entry refused" test "$RC" -ne 0
check "B1 victim survives disable" test -f "$SB/victim.txt"
rm -f "$W"; e remove a1 --yes; eq "B1 cleanup remove" 0 "$RC"
mkdir -p "$SB/outdir"
e enable hello-fixture --yes; eq "B1 enable bundled" 0 "$RC"
e wire --agent opencode --target "$SB/outdir"; eq "B1 wire --target outside project refused (3)" 3 "$RC"
check "B1 nothing written outside" test ! -e "$SB/outdir/.opencode"
mkdir -p "$SB/elsewhere"; ln -s "$SB/elsewhere" "$P/.gemini"
e wire --agent gemini --target "$P"; eq "B1 wire through symlinked agent dir refused (3)" 3 "$RC"
check "B1 nothing written through the symlink" test ! -e "$SB/elsewhere/commands"
rm -f "$P/.gemini"
e wire --agent all --target "$P"; eq "B1 normal wire still works" 0 "$RC"
e verify; eq "B1 verify after normal wire" 0 "$RC"
e unwire --agent all --target "$P"; eq "B1 normal unwire" 0 "$RC"
check "B1 normal unwire removed the shim" test ! -e "$P/.pi/prompts/hello-fixture.md"

echo "### B2 journal path injection"
mkext "$SB/b2ext" a7; e add "$SB/b2ext" --waiver-id WB2 --yes; eq "B2 setup add" 0 "$RC"
TXN="$P/.constitution/extensions.txn"
printf '{"op":"add","id":"nobody","final":"%s","sha256":"%s"}' "$INST/a7" "$(printf '0%.0s' $(seq 64))" >"$TXN"
e list; eq "B2 list with unbound journal rc 0" 0 "$RC"
check "B2 a7 survives unbound journal" test -d "$INST/a7"
has "B2 loud message about the journal" "journal" "$OUT"
e verify a7; eq "B2 a7 still verifies" 0 "$RC"
printf '[1,2,3]' >"$TXN"; e list; check "B2 a7 survives non-object journal" test -d "$INST/a7"; has "B2 non-object journal reported" "journal" "$OUT"
printf 'garbage{' >"$TXN"; e list; check "B2 a7 survives garbage journal" test -d "$INST/a7"
mkdir -p "$SB/vdir"; echo v >"$SB/vdir/f"
printf '{"op":"remove","id":"a7","final":"%s","aux":"%s"}' "$INST/a7" "$SB/vdir" >"$TXN"
e list; check "B2 aux outside _installed not touched" test -f "$SB/vdir/f"; check "B2 a7 survives" test -d "$INST/a7"
printf '{"op":"remove","id":"ghost","final":"%s","aux":"%s"}' "$INST/ghost" "$INST/a7" >"$TXN"
e list; check "B2 aux naming another extension not deleted" test -d "$INST/a7"
printf '{"op":"add","id":"a7","final":"%s","sha256":"%s"}' "$INST/a7" "$(printf 'f%.0s' $(seq 64))" >"$TXN"
e list; check "B2 add journal with different sha never deletes a locked tree" test -d "$INST/a7"
e verify a7; eq "B2 a7 verifies after all planted journals" 0 "$RC"
rm -f "$TXN"
check "B2 generated .gitignore exists" test -f "$P/.constitution/.gitignore"
gi="$(cat "$P/.constitution/.gitignore" 2>/dev/null)"
has "B2 .gitignore lists the journal" "extensions.txn" "$gi"; has "B2 .gitignore lists tmp files" "*.tmp-*" "$gi"
has "B2 .gitignore lists the local state" "extensions.state/" "$gi"
e remove a7 --yes; eq "B2 cleanup" 0 "$RC"

echo "### B3 concurrent add of the same id with different content"
conc() { # N rounds
  local n="$1" rounds="$2" r i wins tb P2
  for r in $(seq 1 "$rounds"); do
    P2="$SB/cproj_${n}_$r"; make_project "$P2"
    for i in $(seq 1 "$n"); do mkext "$SB/cc_${n}_${r}_$i" cc; echo "variant $i" >"$SB/cc_${n}_${r}_$i/variant.txt"; done
    for i in $(seq 1 "$n"); do
      ( bash "$ENGINE" --root "$R" --project-root "$P2" add "$SB/cc_${n}_${r}_$i" --waiver-id X --yes >"$SB/co_$i" 2>&1; echo $? >"$SB/cr_$i" ) &
    done
    wait
    wins=0; tb=0
    for i in $(seq 1 "$n"); do [ "$(cat "$SB/cr_$i")" = 0 ] && wins=$((wins+1)); grep -q Traceback "$SB/co_$i" && tb=$((tb+1)); done
    eq "B3 n=$n round $r: exactly one winner" 1 "$wins"
    eq "B3 n=$n round $r: no traceback" 0 "$tb"
    eng --root "$R" --project-root "$P2" verify cc; eq "B3 n=$n round $r: verify rc 0" 0 "$RC"
    check "B3 n=$n round $r: no journal left" test ! -e "$P2/.constitution/extensions.txn"
    eng --root "$R" --project-root "$P2" remove cc --yes; eq "B3 n=$n round $r: cleanup" 0 "$RC"
  done
}
conc 2 "${EXT_CONC_ROUNDS:-4}"; conc 8 "${EXT_CONC_ROUNDS:-3}"

echo "### B4 embedded git repositories"
mkext "$SB/b4a" b4a; mkdir -p "$SB/b4a/sub"; git -C "$SB/b4a/sub" init -q
git -C "$SB/b4a/sub" config core.fsmonitor "touch $SB/FSMON_RAN #"
e add "$SB/b4a" --waiver-id W --yes; eq "B4 nested .git refused (3)" 3 "$RC"; check "B4 not installed" test ! -e "$INST/b4a"
e add "$SB/b4a" --dev --waiver-id W --yes; eq "B4 nested .git refused with --dev (3)" 3 "$RC"
mkext "$SB/b4b" b4b; mkdir -p "$SB/b4b/x/.GIT"; echo x >"$SB/b4b/x/.GIT/config"
e add "$SB/b4b" --waiver-id W --yes; eq "B4 .GIT (case) refused (3)" 3 "$RC"
mkext "$SB/b4c" b4c; mkdir -p "$SB/b4c/x/objects"; echo 'ref: refs/heads/main' >"$SB/b4c/x/HEAD"; printf '[core]\n' >"$SB/b4c/x/config"
e add "$SB/b4c" --waiver-id W --yes; eq "B4 bare-repo triple refused (3)" 3 "$RC"
mkext "$SB/b4d" b4d; SHA_D="$(ext_git_repo "$SB/b4d" "$SB/b4drepo")"
e add "$SB/b4drepo" --waiver-id W --yes; eq "B4 local git repo as source installs via git path" 0 "$RC"
check "B4 installed git source has no .git" test ! -e "$INST/b4d/.git"
e remove b4d --yes
check "B4 fsmonitor never ran" test ! -e "$SB/FSMON_RAN"

echo "### I1 credentials in source URLs"
TOK="$(fake_token gh)"
e add "https://user:${TOK}@example.invalid/x.git" --sha "$(printf 'a%.0s' $(seq 40))" --yes
eq "I1 userinfo URL refused (3)" 3 "$RC"; hasnt "I1 token not echoed" "$TOK" "$OUT"
e add "https://${TOK}@example.invalid/x.git" --sha "$(printf 'a%.0s' $(seq 40))" --yes; eq "I1 token-as-user refused (3)" 3 "$RC"
e add "https://example.invalid/x.git?t=${TOK}" --sha "$(printf 'a%.0s' $(seq 40))" --yes
eq "I1 secret-shaped URL refused (3)" 3 "$RC"; hasnt "I1 token not echoed (query)" "$TOK" "$OUT"
check "I1 token never in lock" sh -c '! grep -q "$1" "$2" 2>/dev/null' _ "$TOK" "$P/.constitution/extensions.lock.yml"
printf '{"schema_version":"1.0","catalog":{"id":"c","install_allowed":true,"trust_tier":"community"},"revoked":[],"extensions":{"x":{"releases":{"1.0.0":{"url":"https://u:%s@example.invalid/x.git","sha256":"%s"}}}}}' \
  "$TOK" "$(printf 'a%.0s' $(seq 64))" >"$SB/cat_cred.json"
e catalog "$SB/cat_cred.json"; eq "I1 catalog URL with userinfo refused (1)" 1 "$RC"; hasnt "I1 catalog token not echoed" "$TOK" "$OUT"

echo "### I2 git environment and config scrubbing"
mkext "$SB/i2src" i2; printf '* filter=evil\n' >"$SB/i2src/.gitattributes"
SHA_I2="$(ext_git_repo "$SB/i2src" "$SB/i2repo")"
git config --file "$GIT_CONFIG_GLOBAL" filter.evil.smudge "sh -c 'touch $SB/FILTER_RAN; cat'"
git config --file "$GIT_CONFIG_GLOBAL" filter.evil.clean cat
git config --file "$GIT_CONFIG_GLOBAL" filter.evil.required true
e add "file://$SB/i2repo" --sha "$SHA_I2" --sha256 "$(DIGEST "$SB/i2repo")" --yes; eq "I2 install with hostile global filter ok" 0 "$RC"
check "I2 global filter driver never ran" test ! -e "$SB/FILTER_RAN"
e remove i2 --yes
git config --file "$GIT_CONFIG_GLOBAL" --remove-section filter.evil
mkext "$SB/i2c" i2c; SHA_C="$(ext_git_repo "$SB/i2c" "$SB/i2crepo")"
pre="$(git -C "$P" rev-parse HEAD)"
OUT="$(GIT_DIR="$P/.git" GIT_WORK_TREE="$P" bash "$ENGINE" --root "$R" --project-root "$P" add "file://$SB/i2crepo" --sha "$SHA_C" --sha256 "$(DIGEST "$SB/i2crepo")" --yes </dev/null 2>&1)"; RC=$?
eq "I2 inherited GIT_DIR does not misdirect (install ok)" 0 "$RC"; notb "I2 GIT_DIR"
check "I2 installed from the right repo" test -f "$INST/i2c/extension.yml"
eq "I2 project repo untouched" "$pre" "$(git -C "$P" rev-parse HEAD)"
e remove i2c --yes
mkext "$SB/i2s" i2s; (cd "$SB/i2s" && ln -s extension.yml alias)
SHA_S="$(ext_git_repo "$SB/i2s" "$SB/i2srepo")"
e add "file://$SB/i2srepo" --sha "$SHA_S" --waiver-id WI2S --yes; eq "I2 symlink blob in git source refused (3)" 3 "$RC"
check "I2 symlink source not installed" test ! -e "$INST/i2s"

echo "### I3 lock tampering against the local state record"
mkext "$SB/i3" i3; e add "$SB/i3" --waiver-id WI3 --yes; eq "I3 setup add" 0 "$RC"
LK="$P/.constitution/extensions.lock.yml"; cp "$LK" "$SB/lk.bak"
e verify i3; eq "I3 untampered verifies" 0 "$RC"
tamper() { python3 -I - "$LK" "$1" "$(dirname "$ENGINE")" <<'PY'
import sys
p, what, d = sys.argv[1:4]
sys.path.insert(0, d)
import ext_yaml
doc = ext_yaml.parse(open(p).read(), max_bytes=1 << 26, max_lines=10**6, max_nodes=10**7)
for e in doc["extensions"]:
    if e["id"] != "i3":
        continue
    if what == "enabled":
        e["enabled"] = True; e["components"] = {"hooks": "none", "mcp": "none"}
    elif what == "consent":
        e["consent"] = {"capabilities": ["command:i3", "network:evil.example"], "mode": "tty"}
    elif what == "waiver":
        e["waiver_id"] = None
    elif what == "source":
        e["source"]["kind"] = "git"; e["source"]["sha"] = "0" * 40
open(p, "w").write(ext_yaml.dump(doc))
PY
}
for t in enabled consent waiver source; do
  cp "$SB/lk.bak" "$LK"; tamper "$t"; e verify i3; eq "I3 tampered $t fails verify (5)" 5 "$RC"; has "I3 $t message is precise" "$t" "$OUT"
done
cp "$SB/lk.bak" "$LK"; e verify i3; eq "I3 restored lock verifies" 0 "$RC"
mv "$P/.constitution/extensions.state/i3.json" "$SB/i3.rec"
e verify i3; eq "I3 missing state record fails verify (5)" 5 "$RC"; has "I3 names the state record" "state record" "$OUT"
mv "$SB/i3.rec" "$P/.constitution/extensions.state/i3.json"
cp "$P/.constitution/extensions.state/i3.json" "$SB/i3.rec"
python3 -I - "$P/.constitution/extensions.state/i3.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["entry"]["enabled"] = True
open(p, "w").write(json.dumps(d))
PY
e verify i3; eq "I3 record forged without the key fails verify (5)" 5 "$RC"
cp "$SB/lk.bak" "$LK"; cp "$SB/i3.rec" "$P/.constitution/extensions.state/i3.json"
tamper enabled
python3 -I - "$LK" "$P/.constitution/extensions.state/i3.json" "$(dirname "$ENGINE")" <<'PY2'
import json, sys
lk, rp, d = sys.argv[1:4]; sys.path.insert(0, d)
import ext_yaml
doc = ext_yaml.parse(open(lk).read(), max_bytes=1 << 26, max_lines=10**6, max_nodes=10**7)
rec = json.load(open(rp))
rec["entry"] = [x for x in doc["extensions"] if x["id"] == "i3"][0]  # consistent forgery, old MAC kept
open(rp, "w").write(json.dumps(rec))
PY2
e verify i3; eq "I3 lock+record forged consistently without the key fails verify (5)" 5 "$RC"
has "I3 consistent forgery named as integrity failure" "integrity" "$OUT"
cp "$SB/lk.bak" "$LK"; cp "$SB/i3.rec" "$P/.constitution/extensions.state/i3.json"
key="$(stat -c %a "$P/.constitution/extensions.state/key")"; eq "I3 key file mode 0600" 600 "$key"
check "I3 state dir ignored by git" sh -c 'git -C "$1" check-ignore -q .constitution/extensions.state/key' _ "$P"
check "I3 lock not ignored by git" sh -c '! git -C "$1" check-ignore -q .constitution/extensions.lock.yml' _ "$P"

echo "### RM1 transport helpers inside an otherwise allowed URL"
e add "file://$SB/x::y" --sha "$(printf 'a%.0s' $(seq 40))" --yes; eq "RM1 '::' refused (3)" 3 "$RC"; has "RM1 names transport helpers" "transport" "$OUT"

echo "### RM6 consent without a terminal and without CONSTITUTION_EXT_NO_TTY"
mkext "$SB/rm6" rm6
OUT="$(env -u CONSTITUTION_EXT_NO_TTY setsid -w bash "$ENGINE" --root "$R" --project-root "$P" add "$SB/rm6" --waiver-id W6 </dev/null 2>&1)"; RC=$?
eq "RM6 no tty, no --yes refused (3)" 3 "$RC"; has "RM6 says consent" "consent" "$OUT"; check "RM6 not installed" test ! -e "$INST/rm6"

echo "### RM7 file names starting with '-'"
mkext "$SB/rm7" rm7; echo x >"$SB/rm7/-rf"
e add "$SB/rm7" --waiver-id W7 --yes; eq "RM7 leading-dash file refused (3)" 3 "$RC"

echo "### MINOR hardlinks, huge integers, bidi/C1, trust tier, symlinked state, dir count"
mkext "$SB/hl" hl; echo outside >"$SB/hl_target"; ln "$SB/hl_target" "$SB/hl/linked.txt"
e add "$SB/hl" --waiver-id W --yes; eq "hardlinked file refused (3)" 3 "$RC"; check "hardlink not installed" test ! -e "$INST/hl"
mkext "$SB/hi" hi; printf 'x_big: %s\n' "$(printf '9%.0s' $(seq 5000))" >>"$SB/hi/extension.yml"
e validate "$SB/hi"; eq "5000-digit integer: clean failure (1)" 1 "$RC"
mkext "$SB/hv" hv; yrep "$SB/hv/extension.yml" "  version: 1.0.0" "  version: 1$(printf '0%.0s' $(seq 4999)).0.0"
e validate "$SB/hv"; eq "5000-digit semver: clean failure (1)" 1 "$RC"
mkext "$SB/hc" hc; yrep "$SB/hc/extension.yml" "  anchors:" "  constitution_version: \">=1$(printf '0%.0s' $(seq 4999))\"
  anchors:"
e validate "$SB/hc"; eq "5000-digit constraint: clean failure (1)" 1 "$RC"
mkext "$SB/bd" bd; yrep "$SB/bd/extension.yml" "  writes: []" "  writes:
    - \"docs/$(printf '‮')txt.exe\""
e validate "$SB/bd"; eq "bidi override refused (1)" 1 "$RC"
mkext "$SB/bd2" bd2; yrep "$SB/bd2/extension.yml" "  author: constitution tests" "  author: \"evil$(printf '\u202e')gnp.exe\""
e validate "$SB/bd2"; eq "bidi override in a text field refused (1)" 1 "$RC"; has "names bidi" "bidi" "$OUT"
mkext "$SB/c1" c1x; yrep "$SB/c1/extension.yml" "  writes: []" "  writes:
    - \"a$(printf '\u009b')31mRED\""
e validate "$SB/c1"; eq "C1 control refused (1)" 1 "$RC"
mkext "$SB/tt" tt; yrep "$SB/tt/extension.yml" "trust_tier: community" "trust_tier: builtin"
e validate "$SB/tt"; eq "self-declared builtin trust tier refused (1)" 1 "$RC"
mkext "$SB/tc" tcm; e add "$SB/tc" --waiver-id W --yes; eq "trust: add" 0 "$RC"
engj --root "$R" --project-root "$P" --json info tcm; eq "installed trust tier assigned by engine" community "$(jget "$OUT" trust_tier)"
engj --root "$R" --project-root "$P" --json info hello-fixture; eq "bundled trust tier assigned by engine" builtin "$(jget "$OUT" trust_tier)"
e remove tcm --yes
mkext "$SB/dc" dc; python3 -I -c 'import os,sys; [os.makedirs(os.path.join(sys.argv[1],"d","x%04d"%i)) for i in range(2100)]' "$SB/dc"
e validate "$SB/dc"; eq "too many directories refused (1)" 1 "$RC"
P3="$SB/symproj"; make_project "$P3"; echo outside >"$SB/lock_target"
mkdir -p "$P3/.constitution"; ln -s "$SB/lock_target" "$P3/.constitution/extensions.lock.yml"
mkext "$SB/sy" sy
eng --root "$R" --project-root "$P3" add "$SB/sy" --waiver-id W --yes; notb symlock
check "symlinked lock: add fails" test "$RC" -ne 0
eq "symlinked lock target untouched" outside "$(cat "$SB/lock_target")"
P4="$SB/symproj2"; make_project "$P4"; mkdir -p "$SB/state_elsewhere"; ln -s "$SB/state_elsewhere" "$P4/.constitution"
eng --root "$R" --project-root "$P4" enable hello-fixture --yes; notb symstate
check "symlinked state dir refused" test "$RC" -ne 0
eq "nothing written through symlinked state dir" 0 "$(find "$SB/state_elsewhere" -mindepth 1 | wc -l)"
P5="$SB/symproj3"; make_project "$P5"; mkdir -p "$P5/.constitution"; echo outside >"$SB/audit_target"
ln -s "$SB/audit_target" "$P5/.constitution/extensions.audit.log"
eng --root "$R" --project-root "$P5" enable hello-fixture --yes; notb symaudit
eq "symlinked audit log target untouched" outside "$(cat "$SB/audit_target")"
P6="$SB/symproj4"; make_project "$P6"; mkdir -p "$P6/.constitution"
printf 'lock_version: "1"\nextensions: []\n' >"$SB/foreign_lock"; ln -s "$SB/foreign_lock" "$P6/.constitution/extensions.lock.yml"
eng --root "$R" --project-root "$P6" verify; notb symread
eq "lock read through a symlink refused (5)" 5 "$RC"

echo "### MINOR test seams and version override outside a sandbox"
mkext "$SB/ts" ts
OUT="$(CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT=add:staged CONSTITUTION_EXT_TEST_NONCE= bash "$ENGINE" --root "$R" --project-root "$P" add "$SB/ts" --waiver-id W --yes </dev/null 2>&1)"; RC=$?
eq "kill seam inert without the sandbox nonce (add completes)" 0 "$RC"
e remove ts --yes
P5="$SB/deep/nonsandbox"; mkdir -p "$SB/deep"; make_project "$P5"
OUT="$(CONSTITUTION_EXT_CONSTITUTION_VERSION=999.0 bash "$ENGINE" --root "$R" --project-root "$P5" list </dev/null 2>&1)"; RC=$?
eq "version override refused outside a test sandbox (3)" 3 "$RC"; has "version override warning is loud" "CONSTITUTION_EXT_CONSTITUTION_VERSION" "$OUT"
OUT="$(CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT=enable:locked bash "$ENGINE" --root "$R" --project-root "$P5" enable hello-fixture --yes </dev/null 2>&1)"; RC=$?
eq "kill seam inert outside the sandbox even with the nonce env" 0 "$RC"

echo "### MINOR catalog robustness and revocation retention"
printf '{"broken' >"$P/.constitution/extensions.catalog.json"
mkext "$SB/cj" cj; e add "$SB/cj" --waiver-id W --yes; check "corrupt catalog: add fails cleanly" test "$RC" -ne 0
e verify; check "corrupt catalog: verify fails cleanly" test "$RC" -ne 0
rm -f "$P/.constitution/extensions.catalog.json"
printf '{"schema_version":"1.0","catalog":{"id":"c","install_allowed":true,"trust_tier":"community"},"revoked":[{"id":"cj","version":"1.0.0","reason":"TEST"}],"extensions":{}}' >"$SB/cr1.json"
printf '{"schema_version":"1.0","catalog":{"id":"c","install_allowed":true,"trust_tier":"community"},"revoked":[],"extensions":{}}' >"$SB/cr2.json"
e catalog "$SB/cr1.json"; eq "catalog with revocation imported" 0 "$RC"
e catalog "$SB/cr2.json"; eq "second catalog imported" 0 "$RC"; has "kept revocations reported" "kept" "$OUT"
e add "$SB/cj" --waiver-id W --yes; eq "previous revocation still honoured (3)" 3 "$RC"
e catalog "$SB/cr2.json" --replace; eq "explicit --replace" 0 "$RC"; has "--replace warns about dropped revocations" "dropped" "$OUT"
e add "$SB/cj" --waiver-id W --yes; eq "add after explicit replace" 0 "$RC"; e remove cj --yes

echo "### MINOR wire never overwrites a user-edited recorded shim"
e wire hello-fixture --agent pi --target "$P"; eq "wire pi" 0 "$RC"
printf 'user edit\n' >>"$P/.pi/prompts/hello-fixture.md"; cp "$P/.pi/prompts/hello-fixture.md" "$SB/edited"
e wire hello-fixture --agent pi --target "$P"; eq "re-wire over user-edited shim refused (3)" 3 "$RC"
check "user edit preserved" cmp -s "$P/.pi/prompts/hello-fixture.md" "$SB/edited"
rm -f "$P/.pi/prompts/hello-fixture.md"; e unwire --agent pi --target "$P"

echo "### MINOR YAML 1.1 ambiguous scalars"
for v in "010" "0x10" "yes" "No" "on" "1.0" "1_000" "2026-10-29" ".inf" "+5"; do
  mkext "$SB/ya" ya; yrep "$SB/ya/extension.yml" "  author: constitution tests" "  author: $v"
  e validate "$SB/ya"; eq "ambiguous plain scalar [$v] refused (1)" 1 "$RC"
  safe_rm_rf "${SB:?}/ya"
done

echo "### EXTRA shim directory symlinked out of the project (R11 contained)"
mkdir -p "$SB/outside2"; echo keep >"$SB/outside2/a1.md"
rm -rf "${P:?}/.opencode"; ln -s "$SB/outside2" "$P/.opencode"
plant_wiring opencode file "$P/.opencode/a1.md" "\"$(sha "$SB/outside2/a1.md")\"" null
mkdir -p "$SB/outside2/commands"; cp "$SB/outside2/a1.md" "$SB/outside2/commands/a1.md"
plant_wiring opencode file "$P/.opencode/commands/a1.md" "\"$(sha "$SB/outside2/commands/a1.md")\"" null
e unwire --agent all; check "EXTRA unwire through symlinked shim dir refused" test "$RC" -ne 0
check "EXTRA outside file survives" test -f "$SB/outside2/commands/a1.md"
plant_wiring_rel opencode file ".opencode/commands/a1.md" "\"$(sha "$SB/outside2/commands/a1.md")\"" null
e unwire --agent all; check "EXTRA relative unwire through symlinked shim dir refused" test "$RC" -ne 0
check "EXTRA outside file survives relative entry" test -f "$SB/outside2/commands/a1.md"
printf '# managed-by: constitution_ext id=a1 command=a1\nkeep me\n' >"$SB/outside2/commands/a1.md"; cp "$SB/outside2/commands/a1.md" "$SB/outside_a1.bak"
plant_wiring_rel opencode file ".opencode/commands/a1.md" "\"$(sha "$SB/outside2/commands/a1.md")\"" null
e unwire --agent all; eq "EXTRA marked outside file behind symlinked shim dir refused (5)" 5 "$RC"
has "EXTRA refusal names the containment rule" "outside the project" "$OUT"
check "EXTRA marked outside file survives" cmp -s "$SB/outside2/commands/a1.md" "$SB/outside_a1.bak"
rm -f "$W" "$P/.opencode"

echo "### EXTRA tampered lock entries cannot be wired, enabled or laundered (R17)"
e enable hello-fixture --yes; eq "EXTRA enable bundled" 0 "$RC"
cp "$LK" "$SB/lk2.bak"
python3 -I - "$LK" "$(dirname "$ENGINE")" <<'PY2'
import sys
p, d = sys.argv[1:3]; sys.path.insert(0, d)
import ext_yaml
doc = ext_yaml.parse(open(p).read(), max_bytes=1 << 26, max_lines=10**6, max_nodes=10**7)
for x in doc["extensions"]:
    if x["id"] == "hello-fixture":
        x["sha256"] = "0" * 64
open(p, "w").write(ext_yaml.dump(doc))
PY2
e lock; e verify hello-fixture; eq "EXTRA lock does not launder a tampered bundled entry (5)" 5 "$RC"
cp "$SB/lk2.bak" "$LK"; tamper enabled
e wire i3 --agent pi --target "$P"; eq "EXTRA wire refuses a tampered entry" 5 "$RC"
check "EXTRA no shim for tampered entry" test ! -e "$P/.pi/prompts/i3.md"
cp "$SB/lk2.bak" "$LK"; tamper consent
e enable i3 --yes; eq "EXTRA enable refuses over a tampered entry (5)" 5 "$RC"
cp "$SB/lk2.bak" "$LK"
echo tampered >>"$INST/i3/commands/i3/SKILL.md"; e lock; has "EXTRA lock reports (not launders) a changed installed tree" "not refreshed" "$OUT"
e verify i3; eq "EXTRA changed installed tree still fails verify (5)" 5 "$RC"
cp "$SB/i3/commands/i3/SKILL.md" "$INST/i3/commands/i3/SKILL.md"
cp "$SB/lk2.bak" "$LK"; e verify; eq "EXTRA restored lock verifies" 0 "$RC"
check "extension code never executed" test ! -e "$SB/HOOK_RAN"
finish
