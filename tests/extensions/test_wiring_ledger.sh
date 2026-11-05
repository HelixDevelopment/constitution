#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_wiring_ledger.sh — ownership-redesign WAVE 1 (docs/design/extension_engine_ownership_redesign.md,
# section 5.2 ledger, 5.3 reference file, section 9 inventory/adopt/backup/rollback).
# Tests the REAL scripts/constitution_ext/wiring_ledger.py (no mocks, §11.4.289) on real files, real
# symlinks and real flock contention in a mktemp sandbox; every run gets its own scratch HOME.
# Test-first (§11.4.224): written before the module. Paired mutations: test_wiring_ledger_mutations.sh.
# Usage: bash tests/extensions/test_wiring_ledger.sh   (exit 0 iff every assertion passed)
T_NAME=wiring-ledger
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
: "${SB:?}"
IMPL="${WIRING_LEDGER_IMPL:-$REPO/scripts/constitution_ext/wiring_ledger.py}"
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"
mkdir -p "$SB/home"
wl() { OUT="$(env HOME="$SB/home" SOURCE_DATE_EPOCH=1700000000 python3 -I "$IMPL" --project "$P" --root "$R" "$@" </dev/null 2>"$SB/err")"; RC=$?; ERR="$(cat "$SB/err")"; }
wlp() { # same but for another project dir given first
  local p="$1"; shift
  OUT="$(env HOME="$SB/home" SOURCE_DATE_EPOCH=1700000000 python3 -I "$IMPL" --project "$p" --root "$R" "$@" </dev/null 2>"$SB/err")"; RC=$?; ERR="$(cat "$SB/err")"
}
LED="$P/.constitution/wiring.json"; LOC="$P/.constitution/extensions.state/wiring.local.json"; KEY="$P/.constitution/extensions.state/key"
state_of() { wl classify --path "$1"; jget "$OUT" state; }

# ── 1. record + classify: ours ────────────────────────────────────────────
mkdir -p "$P/.claude/skills" "$R/skills/alpha"; printf 'a\n' >"$R/skills/alpha/SKILL.md"
rootfp() { printf '%s%s%s' "$(tree_fp "$R/skills")" "$(tree_fp "$R/scripts")" "$(sha256sum "$R/Constitution.md")"; }   # everything except the shared extensions/ dir the refs file legitimately writes
ROOT_FP_BEFORE="$(rootfp)"
ln -s "../../../croot/skills/alpha" "$P/.claude/skills/alpha"
eq "untracked link is consumer-owned" consumer-owned "$(state_of .claude/skills/alpha)"
wl record --id sk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink
eq "record rc 0" 0 "$RC"
eq "recorded link is ours" ours "$(state_of .claude/skills/alpha)"
check "tracked ledger exists" test -f "$LED"
check "local signed file exists" test -f "$LOC"
eq "state key is 0600" 600 "$(stat -c %a "$KEY")"
has "row names the constitution root" "$R" "$(cat "$LED")"
hasnt "tracked ledger carries no mac/key" "mac" "$(cat "$LED")"
has "local file carries a mac" '"mac"' "$(cat "$LOC")"
wl record --id sk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink
eq "second identical record rc 0" 0 "$RC"
H1="$(sha256sum "$LED" | cut -c1-64)"
wl record --id sk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink
eq "no-op run leaves ledger byte-identical (idempotent)" "$H1" "$(sha256sum "$LED" | cut -c1-64)"
wl record --id sk-other --producer installer --agent claude --path .claude/skills/alpha --kind symlink
eq "second id for an already-recorded path refused" 3 "$RC"
wl record --id sk-gone --producer installer --agent claude --path .claude/skills/nothere --kind symlink
eq "record of an absent path refused" 3 "$RC"

# ── 2. diverged ───────────────────────────────────────────────────────────
rm "$P/.claude/skills/alpha"; ln -s "../../README.md" "$P/.claude/skills/alpha"
eq "retargeted recorded link is diverged" diverged "$(state_of .claude/skills/alpha)"
wl classify --path .claude/skills/alpha; eq "diverged is not replaceable" false "$(jget "$OUT" replace_ok)"
rm "$P/.claude/skills/alpha"; ln -s "../../../croot/skills/alpha" "$P/.claude/skills/alpha"
eq "restored link is ours again" ours "$(state_of .claude/skills/alpha)"
wl classify --path .claude/skills/alpha; eq "ours is replaceable" true "$(jget "$OUT" replace_ok)"

# ── 3. copied ledger / other checkout ─────────────────────────────────────
cp "$LOC" "$SB/loc.keep"
rm "$LOC"
eq "no local signature -> other-checkout" other-checkout "$(state_of .claude/skills/alpha)"
wl classify --path .claude/skills/alpha; eq "other-checkout not replaceable" false "$(jget "$OUT" replace_ok)"
cp "$SB/loc.keep" "$LOC"
python3 -I - "$LOC" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["mac"] = "0" * 64; json.dump(d, open(f, "w"))
PY
eq "forged local mac -> other-checkout" other-checkout "$(state_of .claude/skills/alpha)"
cp "$SB/loc.keep" "$LOC"
eq "restored local file -> ours" ours "$(state_of .claude/skills/alpha)"
python3 -I - "$LED" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["rows"][0]["constitution_root"] = "/elsewhere/other"; json.dump(d, open(f, "w"))
PY
eq "tracked row for another constitution root -> other-checkout" other-checkout "$(state_of .claude/skills/alpha)"
python3 -I - "$LED" "$R" <<'PY'
import json, sys
f, r = sys.argv[1:3]; d = json.load(open(f)); d["rows"][0]["constitution_root"] = r; d["rows"][0]["agent"] = "pi"; json.dump(d, open(f, "w"))
PY
eq "row edited in the tracked file and not re-signed -> other-checkout" other-checkout "$(state_of .claude/skills/alpha)"
cp "$SB/loc.keep" "$LOC"
# restore the exact tracked bytes by re-recording from a clean state
rm -f "$LED" "$LOC"
wl record --id sk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink
eq "ledger rebuilt" ours "$(state_of .claude/skills/alpha)"

# root binding on its own: a VALIDLY signed row made under another constitution root is not ours here
R2="$SB/croot2"; make_root "$R2"
printf 'b\n' >"$P/rb.md"
OUT="$(env HOME="$SB/home" python3 -I "$IMPL" --project "$P" --root "$R2" record --id rb --producer installer --agent claude --path rb.md --kind file </dev/null 2>&1)"; RC=$?
eq "record under a second root rc 0" 0 "$RC"
eq "validly signed row of another root -> other-checkout" other-checkout "$(state_of rb.md)"
wl forget --id rb; rm -f "$P/rb.md"
# a hostile row elsewhere in the ledger blocks even an unrelated record (nothing is rewritten)
cp "$LED" "$SB/led.keep0"
python3 -I - "$LED" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["rows"].append(dict(d["rows"][0], id="evil", path="../x")); json.dump(d, open(f, "w"))
PY
printf 'u\n' >"$P/unrelated.md"
wl record --id unrel --producer installer --agent claude --path unrelated.md --kind file
eq "unrelated record refused while the ledger holds a hostile row" 3 "$RC"
cp "$SB/led.keep0" "$LED"; rm -f "$P/unrelated.md"

# a missing/forged local file must not be re-signed by a later record (no laundering)
cp "$LOC" "$SB/loc.keep2"; rm "$LOC"
mkdir -p "$P/.pi/prompts"; printf 'p\n' >"$P/.pi/prompts/p.md"
wl record --id pi-p --producer installer --agent pi --path .pi/prompts/p.md --kind file
eq "record after a lost local file rc 0" 0 "$RC"
eq "the new row is ours" ours "$(state_of .pi/prompts/p.md)"
eq "the old unsigned row stays other-checkout (not laundered)" other-checkout "$(state_of .claude/skills/alpha)"
wl forget --id pi-p; rm -f "$P/.pi/prompts/p.md"
cp "$SB/loc.keep2" "$LOC"
eq "original signature restored -> ours" ours "$(state_of .claude/skills/alpha)"

# ── 4. file + json-entry kinds ────────────────────────────────────────────
mkdir -p "$P/.opencode/commands"; printf 'cmd body\n' >"$P/.opencode/commands/x.md"
wl record --id oc-x --producer engine:hello --agent opencode --path .opencode/commands/x.md --kind file
eq "file record rc 0" 0 "$RC"
eq "file is ours" ours "$(state_of .opencode/commands/x.md)"
printf 'cmd body edited by consumer\n' >"$P/.opencode/commands/x.md"
eq "edited file is diverged" diverged "$(state_of .opencode/commands/x.md)"
TOK="$(fake_token gh)"
cat >"$P/.claude/settings.json" <<JSON
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"$R/scripts/hooks/action_prefix_expand.sh","x":"$TOK"}]}]},"other":1}
JSON
wl record --id hook-ups --producer installer --agent claude --path .claude/settings.json --kind json-entry --json-path hooks.UserPromptSubmit.0
eq "json-entry record rc 0" 0 "$RC"
eq "json-entry is ours" ours "$(state_of .claude/settings.json)"
python3 -I - "$P/.claude/settings.json" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["other"] = 2; json.dump(d, open(f, "w"))
PY
wl classify --path .claude/settings.json
eq "changing a sibling key leaves our entry ours" ours "$(jget "$OUT" state)"
python3 -I - "$P/.claude/settings.json" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"] = "/moved/x.sh"; json.dump(d, open(f, "w"))
PY
eq "changing our entry makes it diverged" diverged "$(state_of .claude/settings.json)"
# rebind: only with the expected old fingerprint, and only when the row was valid
wl status; OLDFP="$(python3 -I -c 'import json,sys; print([r for r in json.loads(sys.argv[1])["rows"] if r["id"]=="hook-ups"][0]["fingerprint"])' "$OUT")"
wl rebind --id hook-ups --old-fingerprint "0000"
eq "rebind with the wrong old fingerprint refused" 3 "$RC"
wl rebind --id hook-ups --old-fingerprint "$OLDFP"
eq "rebind with the right old fingerprint ok" 0 "$RC"
eq "after rebind the rewritten entry is ours" ours "$(state_of .claude/settings.json)"
# secrets: ledger holds digests only
SEC="$(cat "$LED" "$LOC" 2>/dev/null)"
hasnt "no secret-shaped value in tracked or local ledger" "$TOK" "$SEC"
printf '%s\n' "$TOK" >"$SB/needle.txt"
check "control needle: the scan finds a seeded token" grep -q "$TOK" "$SB/needle.txt"

# ── 5. hostile paths ──────────────────────────────────────────────────────
for bad in "../outside" "/etc/passwd" ".claude/../../x" "a//b" "" "." ; do
  wl record --id hostile --producer installer --agent claude --path "$bad" --kind file
  eq "hostile path [$bad] refused" 3 "$RC"
done
mkdir -p "$SB/outside"; printf 'o\n' >"$SB/outside/f"
ln -s "$SB/outside" "$P/.evil"
wl record --id evil --producer installer --agent claude --path .evil/f --kind file
eq "symlinked parent resolving outside the project refused" 3 "$RC"
wl record --id bad/id --producer installer --agent claude --path README.md --kind file
eq "id with a slash refused" 3 "$RC"
wl record --id weird --producer nobody --agent claude --path README.md --kind file
eq "unknown producer refused" 3 "$RC"
wl record --id weirdk --producer installer --agent claude --path README.md --kind socket
eq "unknown kind refused" 3 "$RC"

# ── 6. hostile / malformed tracked ledger ─────────────────────────────────
cp "$LED" "$SB/led.keep"
printf '{not json' >"$LED"
wl status; eq "malformed ledger refuses status" 3 "$RC"
wl record --id z --producer installer --agent claude --path README.md --kind file; eq "malformed ledger refuses record" 3 "$RC"
check "malformed ledger left untouched" test "$(cat "$LED")" = "{not json"
python3 -I - "$SB/led.keep" "$LED" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][0]["path"] = "../escape"; json.dump(d, open(sys.argv[2], "w"))
PY
wl status; eq "ledger row with .. path refuses everything" 3 "$RC"
cp "$SB/led.keep" "$LED"
wl status; eq "restored ledger readable" 0 "$RC"

# ── 7. forget ─────────────────────────────────────────────────────────────
wl forget --id oc-x; eq "forget rc 0" 0 "$RC"
eq "forgotten path is consumer-owned" consumer-owned "$(state_of .opencode/commands/x.md)"
check "forget never deletes the file" test -f "$P/.opencode/commands/x.md"

# ── 8. inventory (read-only) and adopt (D6) ───────────────────────────────
IP="$SB/inv"; make_project "$IP"
mkdir -p "$IP/submodules" "$IP/.claude/skills" "$IP/.agents/skills" "$IP/skills" "$IP/.opencode/commands" "$SB/usercfg/skills/mine"
ln -s "$R" "$IP/submodules/constitution"
ln -s "../../submodules/constitution/skills/alpha" "$IP/.claude/skills/alpha"
ln -s "../submodules/constitution/skills/alpha" "$IP/skills/alpha"
ln -s "$SB/usercfg/skills/mine" "$IP/.claude/skills/mine"     # the user's own link
ln -s "../../submodules/constitution/skills/alpha" "$IP/.agents/skills/alpha"
printf '# managed-by: constitution_ext id=hello command=hello\nbody\n' >"$IP/.opencode/commands/hello.md"
printf 'my own command\n' >"$IP/.opencode/commands/mine.md"
mkdir -p "$IP/.claude"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/old/path/scripts/hooks/action_prefix_expand.sh"}]},{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}\n' >"$IP/.claude/settings.json"
git -C "$IP" add -A >/dev/null 2>&1; git -C "$IP" commit -qm inv >/dev/null 2>&1
INVFP="$(tree_fp "$IP")"
wlp "$IP" inventory
eq "inventory rc 0" 0 "$RC"
eq "inventory is read-only (tree checksum unchanged)" "$INVFP" "$(tree_fp "$IP")"
check "inventory wrote no ledger" test ! -e "$IP/.constitution/wiring.json"
PATHS="$(python3 -I -c 'import json,sys; print(" ".join(sorted(c["path"] for c in json.loads(sys.argv[1])["candidates"])))' "$OUT")"
has "inventory finds the claude link" ".claude/skills/alpha" "$PATHS"
has "inventory finds the legacy skills/ link" "skills/alpha" "$PATHS"
has "inventory finds the .agents link" ".agents/skills/alpha" "$PATHS"
has "inventory finds the marker file" ".opencode/commands/hello.md" "$PATHS"
has "inventory finds the hook entry" ".claude/settings.json" "$PATHS"
hasnt "inventory does not list the user's own link" ".claude/skills/mine" "$PATHS"
hasnt "inventory does not list the user's own file" ".opencode/commands/mine.md" "$PATHS"
wlp "$IP" adopt
eq "non-interactive adopt without a flag rc 0" 0 "$RC"
check "D6: adopts nothing by default" test ! -e "$IP/.constitution/wiring.json"
has "adopt reports zero adopted" '"adopted": 0' "$OUT"
wlp "$IP" adopt --only .claude/skills/alpha
eq "adopt --only rc 0" 0 "$RC"
wlp "$IP" classify --path .claude/skills/alpha; eq "adopted item is ours" ours "$(jget "$OUT" state)"
wlp "$IP" classify --path skills/alpha; eq "other candidates stay consumer-owned" consumer-owned "$(jget "$OUT" state)"
wlp "$IP" adopt --only .claude/skills/mine; eq "adopting a non-candidate is refused" 3 "$RC"
wlp "$IP" adopt --adopt all-matching
eq "adopt all-matching rc 0" 0 "$RC"
wlp "$IP" status
NROWS="$(python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])["rows"]))' "$OUT")"
eq "all-matching adopted the 5 candidates (incl. the earlier one)" 5 "$NROWS"
wlp "$IP" classify --path .claude/skills/mine; eq "user link never adopted" consumer-owned "$(jget "$OUT" state)"
wlp "$IP" classify --path .claude/settings.json; eq "hook entry adopted as json-entry (ours)" ours "$(jget "$OUT" state)"
wlp "$IP" adopt --adopt bogus; eq "unknown adopt mode refused" 3 "$RC"

# ── 9. backup / rollback ──────────────────────────────────────────────────
BP="$SB/bk"; make_project "$BP"
mkdir -p "$BP/.claude/skills" "$BP/.opencode/commands"
ln -s "$R/skills/alpha" "$BP/.claude/skills/alpha"
printf 'orig\n' >"$BP/.opencode/commands/c.md"
printf '{"a":1}\n' >"$BP/.claude/settings.json"
wlp "$BP" record --id bk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink
wlp "$BP" backup --path .opencode/commands/c.md --path .claude/settings.json --path .claude/skills/alpha
eq "backup rc 0" 0 "$RC"
BDIR="$(jget "$OUT" backup_dir)"
has "backup dir is under .constitution-install-backup" ".constitution-install-backup/" "$BDIR"
check "backup manifest exists" test -f "$BDIR/manifest.json"
BFP="$(tree_fp "$BP/.opencode")$(cat "$BP/.claude/settings.json" | sha256sum)$(readlink "$BP/.claude/skills/alpha")"
LEDBK="$(sha256sum "$BP/.constitution/wiring.json" | cut -c1-64)"
# the "run": change files, add a link + row, add a new file row
printf 'changed\n' >"$BP/.opencode/commands/c.md"; printf '{"a":2}\n' >"$BP/.claude/settings.json"
rm "$BP/.claude/skills/alpha"; ln -s "../../README.md" "$BP/.claude/skills/alpha"
ln -s "$R/skills/alpha" "$BP/.claude/skills/new"
wlp "$BP" record --id bk-new --producer installer --agent claude --path .claude/skills/new --kind symlink
printf 'made by run\n' >"$BP/.opencode/commands/made.md"
wlp "$BP" record --id bk-made --producer installer --agent opencode --path .opencode/commands/made.md --kind file
printf 'consumer edit\n' >"$BP/.opencode/commands/made.md"      # now diverged
wlp "$BP" rollback --backup "$BDIR"
eq "rollback rc 0" 0 "$RC"
eq "file restored byte-for-byte" "orig" "$(cat "$BP/.opencode/commands/c.md")"
eq "json restored byte-for-byte" '{"a":1}' "$(cat "$BP/.claude/settings.json")"
eq "symlink restored (same target text)" "$R/skills/alpha" "$(readlink "$BP/.claude/skills/alpha")"
eq "ledger restored byte-for-byte" "$LEDBK" "$(sha256sum "$BP/.constitution/wiring.json" | cut -c1-64)"
check "link created by the run (still matching its row) was unlinked" test ! -L "$BP/.claude/skills/new"
check "diverged file created by the run is left alone" test -f "$BP/.opencode/commands/made.md"
has "report names the left-alone diverged path" ".opencode/commands/made.md" "$OUT"
wlp "$BP" status; eq "status after rollback rc 0" 0 "$RC"
hasnt "rows created after the backup are gone" "bk-new" "$OUT"
# tampered manifest -> refuse, change nothing
wlp "$BP" backup --path .opencode/commands/c.md; BD2="$(jget "$OUT" backup_dir)"
printf 'X\n' >>"$BD2/files/.opencode/commands/c.md" 2>/dev/null || printf 'X\n' >>"$(find "$BD2" -type f -name c.md | head -1)"
printf 'live\n' >"$BP/.opencode/commands/c.md"
wlp "$BP" rollback --backup "$BD2"
eq "rollback with a tampered backup file refused" 3 "$RC"
wlp "$BP" backup --path .opencode/commands/c.md; BD3="$(jget "$OUT" backup_dir)"
python3 -I - "$BD3/manifest.json" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["rows_at_backup"] = []; json.dump(d, open(f, "w"))
PY
wlp "$BP" rollback --backup "$BD3"
eq "rollback with an edited (unsigned) manifest refused" 3 "$RC"
eq "refused rollback changed nothing" live "$(cat "$BP/.opencode/commands/c.md")"
wlp "$BP" rollback --backup "$SB/nonexistent"; eq "rollback of a missing backup refused" 3 "$RC"
wlp "$BP" rollback --backup "$SB"; eq "rollback of a dir without manifest refused" 3 "$RC"
wlp "$BP" backup --path ../outside; eq "backup of a hostile path refused" 3 "$RC"

# ── 9b. review fixes F1-F5 (rollback safety, backup ignore, usage errors, mutant killers) ──────────────
# F1: rollback unlinks ONLY rows that classify as ours (local HMAC + root binding)
F1P="$SB/f1"; make_project "$F1P"; printf 'mine\n' >"$F1P/consumer.txt"
wlp "$F1P" backup --path base.txt; F1B="$(jget "$OUT" backup_dir)"
wlp "$F1P" record --id f1-row --producer installer --agent claude --path consumer.txt --kind file
rm "$F1P/.constitution/extensions.state/wiring.local.json"          # a tracked row with NO local signature
wlp "$F1P" rollback --backup "$F1B"
eq "F1 rollback of an unsigned row rc 0" 0 "$RC"
eq "F1 consumer file with a matching tracked row is NOT deleted" mine "$(cat "$F1P/consumer.txt" 2>/dev/null)"
has "F1 report names it left alone" "consumer.txt" "$(printf '%s' "$OUT" | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["left_alone"]))')"
hasnt "F1 report does not list it as unlinked" 'consumer.txt' "$(printf '%s' "$OUT" | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["unlinked"]))')"
# F1b: a row signed here but bound to ANOTHER constitution root is not ours either
F1Q="$SB/f1q"; make_project "$F1Q"; printf 'mine\n' >"$F1Q/consumer.txt"; R2="$SB/croot2"; make_root "$R2"
wlp "$F1Q" backup --path base.txt; F1QB="$(jget "$OUT" backup_dir)"
wlp "$F1Q" record --id f1q-row --producer installer --agent claude --path consumer.txt --kind file
OUT="$(env HOME="$SB/home" python3 -I "$IMPL" --project "$F1Q" --root "$R2" rollback --backup "$F1QB" </dev/null 2>"$SB/err")"; RC=$?
eq "F1b rollback from another root rc 0" 0 "$RC"
eq "F1b consumer file bound to another root is NOT deleted" mine "$(cat "$F1Q/consumer.txt" 2>/dev/null)"
# F1c control: a genuinely ours row IS unlinked (so the guard is not just 'never delete')
F1C="$SB/f1c"; make_project "$F1C"; printf 'made\n' >"$F1C/made.txt"
wlp "$F1C" backup --path base.txt; F1CB="$(jget "$OUT" backup_dir)"
wlp "$F1C" record --id f1c-row --producer installer --agent claude --path made.txt --kind file
wlp "$F1C" rollback --backup "$F1CB"; check "F1c control: an ours row created after the backup is unlinked" test ! -e "$F1C/made.txt"

# F2: rollback is atomic — every row path and restore target is checked before the first change
F2P="$SB/f2"; make_project "$F2P"; printf 'base\n' >"$F2P/base.txt"
wlp "$F2P" backup --path base.txt; F2B="$(jget "$OUT" backup_dir)"
printf 'a\n' >"$F2P/a.txt"; wlp "$F2P" record --id f2-a --producer installer --agent claude --path a.txt --kind file
printf 'z\n' >"$F2P/z.txt"; wlp "$F2P" record --id f2-z --producer installer --agent claude --path z.txt --kind file
printf 'changed\n' >"$F2P/base.txt"
head -c 17000000 /dev/zero >>"$F2P/z.txt"                           # consumer grew it past the fingerprint limit
wlp "$F2P" rollback --backup "$F2B"
eq "F2a oversize created-later file: rollback rc 0 (left alone, not an abort)" 0 "$RC"
check "F2a oversize file left in place" test -s "$F2P/z.txt"
eq "F2a base restored" base "$(cat "$F2P/base.txt")"
check "F2a the ours row a.txt unlinked" test ! -e "$F2P/a.txt"
has "F2a oversize file reported left alone" "z.txt" "$(printf '%s' "$OUT" | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["left_alone"]))')"
# F2b: a restore target that is a symlink leaf refuses the WHOLE rollback before any change
F2Q="$SB/f2q"; make_project "$F2Q"; printf 'base\n' >"$F2Q/base.txt"; printf 'outside\n' >"$SB/f2q.out"
wlp "$F2Q" backup --path base.txt; F2QB="$(jget "$OUT" backup_dir)"
printf 'a\n' >"$F2Q/a.txt"; wlp "$F2Q" record --id f2q-a --producer installer --agent claude --path a.txt --kind file
rm "$F2Q/base.txt"; ln -s "$SB/f2q.out" "$F2Q/base.txt"
LEDQ="$(sha256sum "$F2Q/.constitution/wiring.json" | cut -c1-64)"
wlp "$F2Q" rollback --backup "$F2QB"
eq "F2b symlink leaf at a restore target: refused rc 3" 3 "$RC"
check "F2b nothing changed: a.txt still there" test -f "$F2Q/a.txt"
eq "F2b nothing changed: ledger byte-identical" "$LEDQ" "$(sha256sum "$F2Q/.constitution/wiring.json" | cut -c1-64)"
eq "F2b the symlink target was not written through" outside "$(cat "$SB/f2q.out")"
check "F2b the link is still a link" test -L "$F2Q/base.txt"
# F2c: a hostile tracked row path (.git/x) is left alone, never an abort halfway and never touched
F2R="$SB/f2r"; make_project "$F2R"; printf 'base\n' >"$F2R/base.txt"
wlp "$F2R" backup --path base.txt; F2RB="$(jget "$OUT" backup_dir)"
printf 'a\n' >"$F2R/a.txt"; wlp "$F2R" record --id f2r-a --producer installer --agent claude --path a.txt --kind file
python3 -I - "$F2R/.constitution/wiring.json" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["rows"].append(dict(d["rows"][0], id="f2r-git", path=".git/x")); json.dump(d, open(f, "w"))
PY
printf 'gitfile\n' >"$F2R/.git/x"; printf 'changed\n' >"$F2R/base.txt"
wlp "$F2R" rollback --backup "$F2RB"
eq "F2c hostile .git row rc 0" 0 "$RC"
eq "F2c .git/x untouched" gitfile "$(cat "$F2R/.git/x")"
eq "F2c base restored (rollback ran to completion)" base "$(cat "$F2R/base.txt")"

# F3: the backup directory is never committable (self-contained .gitignore, works without .git/info/exclude)
F3P="$SB/f3"; make_project "$F3P"; mkdir -p "$F3P/.claude"; printf '{"k":"v"}\n' >"$F3P/.claude/settings.json"
wlp "$F3P" backup --path .claude/settings.json
eq "F3 backup rc 0" 0 "$RC"
check "F3 backup base has a .gitignore" test -f "$F3P/.constitution-install-backup/.gitignore"
eq "F3 git sees no backup path (even with --untracked-files=all)" "" "$(git -C "$F3P" status --porcelain --untracked-files=all | grep 'constitution-install-backup')"
check "F3 control needle: git does see the real untracked settings file" sh -c "git -C '$F3P' status --porcelain --untracked-files=all | grep -q 'settings.json'"

# F4: usage errors and non-UTF8 paths are clean
wl record --id u1 --producer installer --agent claude --kind file
eq "F4 record without --path is a usage error (rc 2)" 2 "$RC"
hasnt "F4 no traceback" "Traceback" "$ERR"
wl classify; eq "F4 classify without --path is a usage error (rc 2)" 2 "$RC"
NU="$SB/$(printf 'nu\377dir')"; mkdir -p "$NU"
OUT="$(env HOME="$SB/home" python3 -I "$IMPL" --project "$NU" --root "$R" refs add --id nu --record-digest d1 </dev/null 2>"$SB/err")"; RC=$?
hasnt "F4 non-UTF8 project path: no traceback" "Traceback" "$(cat "$SB/err")"
eq "F4 non-UTF8 project path: refs add works (rc 0)" 0 "$RC"
OUT="$(env HOME="$SB/home" python3 -I "$IMPL" --project "$NU" --root "$R" refs count --id nu </dev/null 2>"$SB/err")"; eq "F4 non-UTF8 path recorded once" 1 "$(jget "$OUT" count)"
OUT="$(env HOME="$SB/home" python3 -I "$IMPL" --project "$NU" --root "$R" refs remove --id nu </dev/null 2>"$SB/err")"; eq "F4 non-UTF8 path removed" 0 "$(jget "$OUT" count)"

# F5: tests that kill the reviewer's surviving mutants
F5P="$SB/f5"; make_project "$F5P"; printf 'x\n' >"$F5P/f.txt"
wlp "$F5P" record --id f5-a --producer installer --agent claude --path f.txt --kind file
chmod 644 "$F5P/.constitution/extensions.state/key"
wlp "$F5P" record --id f5-b --producer installer --agent claude --path README.md --kind file
eq "F5 key with mode 0644 is refused (key-mode check)" 3 "$RC"
chmod 600 "$F5P/.constitution/extensions.state/key"
wlp "$F5P" record --id f5-b --producer installer --agent claude --path README.md --kind file; eq "F5 control: key 0600 accepted" 0 "$RC"
wlp "$F5P" record --id f5-g --producer installer --agent claude --path .git/config --kind file
eq "F5 record of a .git path refused (reserved-path check)" 3 "$RC"
wlp "$F5P" backup --path .git/config; eq "F5 backup of a .git path refused" 3 "$RC"
mkdir -p "$R/extensions/_installed"; printf '%s\td\n' "$SB/f5p" >"$SB/f5ref.dat"
ln -s "$SB/f5ref.dat" "$R/extensions/_installed/nf.refs"
wl refs count --id nf
eq "F5 refs file that is a symlink is not READ through (O_NOFOLLOW)" 3 "$RC"
rm "$R/extensions/_installed/nf.refs"
# domain separation: a local-ledger MAC must not validate as a backup-manifest MAC (reason text proves which check fired)
python3 -I - "$F5P/.constitution/extensions.state/wiring.local.json" "$SB/forged-bk" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1])); os.makedirs(sys.argv[2], exist_ok=True)
m = dict(d["rows"]); m["mac"] = d["mac"]; json.dump(m, open(os.path.join(sys.argv[2], "manifest.json"), "w"))
PY
wlp "$F5P" rollback --backup "$SB/forged-bk"
eq "F5 forged manifest built from the local MAC refused" 3 "$RC"
has "F5 refused by the signature check (domain strings differ)" "signature is invalid" "$ERR"

# ── 9c. re-review M1-M4: rollback preflight covers the ledger target, json-entry guard, restore-target probes ──
la() { printf '%s' "$OUT" | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }
if [ "$(id -u)" -ne 0 ]; then
  # M1a: backup WITHOUT a ledger, a row created later, then the .constitution dir becomes unwritable
  G1="$SB/g1"; make_project "$G1"; printf 'base\n' >"$G1/base.txt"
  wlp "$G1" backup --path base.txt; G1B="$(jget "$OUT" backup_dir)"
  printf 'made\n' >"$G1/made.txt"; wlp "$G1" record --id g1-made --producer installer --agent claude --path made.txt --kind file
  printf 'changed\n' >"$G1/base.txt"; chmod 555 "$G1/.constitution"
  wlp "$G1" rollback --backup "$G1B"
  eq "M1a unwritable ledger dir: rollback refused rc 3" 3 "$RC"
  check "M1a nothing changed: the created-later file is still there (no partial apply)" test -f "$G1/made.txt"
  eq "M1a nothing changed: base.txt not restored" changed "$(cat "$G1/base.txt")"
  has "M1a refusal names the unwritable directory" "not a writable directory" "$ERR"
  chmod 755 "$G1/.constitution"
  wlp "$G1" rollback --backup "$G1B"
  eq "M1a control: after the permission is fixed the rerun converges" 0 "$RC"
  check "M1a control: created-later file unlinked" test ! -e "$G1/made.txt"
  check "M1a control: ledger removed (backup had none)" test ! -e "$G1/.constitution/wiring.json"
  # M1b: backup HAS a ledger (atomic_write into an unwritable dir would fail mid-apply)
  G2="$SB/g2"; make_project "$G2"; printf 'base\n' >"$G2/base.txt"; printf 'o\n' >"$G2/o.txt"
  wlp "$G2" record --id g2-o --producer installer --agent claude --path o.txt --kind file
  wlp "$G2" backup --path base.txt; G2B="$(jget "$OUT" backup_dir)"
  printf 'made\n' >"$G2/made.txt"; wlp "$G2" record --id g2-made --producer installer --agent claude --path made.txt --kind file
  chmod 555 "$G2/.constitution"
  wlp "$G2" rollback --backup "$G2B"
  eq "M1b unwritable ledger dir with a backed-up ledger: refused rc 3" 3 "$RC"
  check "M1b nothing changed: made.txt still there" test -f "$G2/made.txt"
  chmod 755 "$G2/.constitution"
  # N3b: restore target in an unwritable directory refuses the whole rollback
  G3="$SB/g3"; make_project "$G3"; mkdir -p "$G3/d"; printf 'base\n' >"$G3/d/f.txt"
  wlp "$G3" backup --path d/f.txt; G3B="$(jget "$OUT" backup_dir)"
  printf 'made\n' >"$G3/made.txt"; wlp "$G3" record --id g3-made --producer installer --agent claude --path made.txt --kind file
  chmod 555 "$G3/d"
  wlp "$G3" rollback --backup "$G3B"
  eq "N3b restore target in an unwritable dir: refused rc 3" 3 "$RC"
  check "N3b nothing changed: made.txt still there" test -f "$G3/made.txt"
  chmod 755 "$G3/d"
  # N4: an ours created-later row inside an unwritable directory is left alone (reported), rollback still rc 0
  G4="$SB/g4"; make_project "$G4"; mkdir -p "$G4/d"; printf 'base\n' >"$G4/base.txt"
  wlp "$G4" backup --path base.txt; G4B="$(jget "$OUT" backup_dir)"
  printf 'made\n' >"$G4/d/made.txt"; wlp "$G4" record --id g4-made --producer installer --agent claude --path d/made.txt --kind file
  chmod 555 "$G4/d"
  wlp "$G4" rollback --backup "$G4B"
  eq "N4 rollback rc 0" 0 "$RC"
  check "N4 file in an unwritable dir is still there" test -f "$G4/d/made.txt"
  has "N4 reported as left alone with the reason" "directory is not writable" "$(la left_alone)"
  chmod 755 "$G4/d"
else
  ok "M1/N3b/N4 skipped: running as root (permission bits not enforced)"
fi
# M4: preflight creates nothing — a refusal leaves no new directory behind
G5="$SB/g5"; make_project "$G5"; mkdir -p "$G5/d"; printf 'base\n' >"$G5/d/f.txt"
wlp "$G5" backup --path d/f.txt; G5B="$(jget "$OUT" backup_dir)"
rm "$G5/d/f.txt"; rmdir "$G5/d"; printf 'blocker\n' >"$G5/d"        # a FILE where the restore target's parent must be
wlp "$G5" rollback --backup "$G5B"
eq "N3a restore target whose ancestor is a file: refused rc 3" 3 "$RC"
eq "N3a the blocking file is untouched" blocker "$(cat "$G5/d")"
# N9: a created-later json-entry row is never removed by rollback (the consumer's whole settings file survives)
G6="$SB/g6"; make_project "$G6"; mkdir -p "$G6/.claude"; printf '{"hooks":{"UserPromptSubmit":[{"command":"x"}]}}\n' >"$G6/.claude/settings.json"
wlp "$G6" backup --path base.txt; G6B="$(jget "$OUT" backup_dir)"
wlp "$G6" record --id g6-hook --producer installer --agent claude --path .claude/settings.json --kind json-entry --json-path hooks.UserPromptSubmit.0
eq "N9 record rc 0" 0 "$RC"
wlp "$G6" rollback --backup "$G6B"
eq "N9 rollback rc 0" 0 "$RC"
check "N9 the consumer's settings.json survives" test -f "$G6/.claude/settings.json"
has "N9 reported left alone: json entry never removed" "json entry" "$(la left_alone)"
# N8: a path that is in the backup is restored, never first unlinked (report shows restored, not unlinked)
G7="$SB/g7"; make_project "$G7"; printf 'base\n' >"$G7/x.txt"
wlp "$G7" backup --path x.txt; G7B="$(jget "$OUT" backup_dir)"
wlp "$G7" record --id g7-x --producer installer --agent claude --path x.txt --kind file
wlp "$G7" rollback --backup "$G7B"
eq "N8 rollback rc 0" 0 "$RC"
eq "N8 x.txt is not reported unlinked" "[]" "$(la unlinked)"
has "N8 x.txt is reported restored" "x.txt" "$(la restored)"
eq "N8 x.txt content is the backed-up one" base "$(cat "$G7/x.txt")"
# N11: the ledger file replaced by a directory refuses the rollback before any change
G8="$SB/g8"; make_project "$G8"; printf 'base\n' >"$G8/base.txt"; printf 'o\n' >"$G8/o.txt"
wlp "$G8" record --id g8-o --producer installer --agent claude --path o.txt --kind file
wlp "$G8" backup --path base.txt; G8B="$(jget "$OUT" backup_dir)"
printf 'made\n' >"$G8/made.txt"; rm "$G8/base.txt"
rm "$G8/.constitution/extensions.state/wiring.local.json"; mkdir "$G8/.constitution/extensions.state/wiring.local.json"
wlp "$G8" rollback --backup "$G8B"
eq "N11 wiring.local.json is now a directory: refused rc 3" 3 "$RC"
check "N11 nothing changed: made.txt still there" test -f "$G8/made.txt"
check "N11 nothing changed: base.txt was not restored" test ! -e "$G8/base.txt"
has "N11 refusal says directory" "directory" "$ERR"
# N2: a symlinked wiring.local.json is never written through
G9="$SB/g9"; make_project "$G9"; printf 'base\n' >"$G9/base.txt"; printf 'o\n' >"$G9/o.txt"
wlp "$G9" record --id g9-o --producer installer --agent claude --path o.txt --kind file
wlp "$G9" backup --path base.txt; G9B="$(jget "$OUT" backup_dir)"
printf 'made\n' >"$G9/made.txt"; printf 'victim\n' >"$SB/g9.victim"; rm "$G9/base.txt"
rm "$G9/.constitution/extensions.state/wiring.local.json"; ln -s "$SB/g9.victim" "$G9/.constitution/extensions.state/wiring.local.json"
wlp "$G9" rollback --backup "$G9B"
eq "N2 symlinked wiring.local.json: refused rc 3" 3 "$RC"
eq "N2 the symlink target was not written through" victim "$(cat "$SB/g9.victim")"
check "N2 nothing changed: made.txt still there" test -f "$G9/made.txt"
check "N2 nothing changed: base.txt was not restored" test ! -e "$G9/base.txt"

# ── 10. reference file (D5) with flock ────────────────────────────────────
RF="$R/extensions/_installed/hello.refs"
wl refs add --id hello --record-digest d1
eq "refs add rc 0" 0 "$RC"
check "refs file lives at _installed/<id>.refs" test -f "$RF"
wl refs count --id hello; eq "count 1" 1 "$(jget "$OUT" count)"
wl refs add --id hello --record-digest d1; wl refs count --id hello; eq "same project twice counts once" 1 "$(jget "$OUT" count)"
wlp "$IP" refs add --id hello --record-digest d2; wl refs count --id hello; eq "second project -> 2" 2 "$(jget "$OUT" count)"
wl refs list --id hello; has "list shows the project realpath" "$IP" "$OUT"
wl refs remove --id hello; wl refs count --id hello; eq "remove one -> 1" 1 "$(jget "$OUT" count)"
wl refs remove --id hello; wl refs count --id hello; eq "removing an absent entry is a no-op" 1 "$(jget "$OUT" count)"
wlp "$IP" refs remove --id hello; wl refs count --id hello; eq "last remove -> 0" 0 "$(jget "$OUT" count)"
wl refs remove --id hello; check "refs file removed at count 0" test ! -e "$RF"
wl refs add --id "../x" --record-digest d; eq "refs id with .. refused" 3 "$RC"
wl refs add --id hello; eq "refs add without digest refused" 3 "$RC"
mkdir -p "$R/extensions/_installed"; ln -s "$SB/outside/f" "$R/extensions/_installed/lnk.refs"
wl refs add --id lnk --record-digest d; eq "refs file that is a symlink refused" 3 "$RC"
check "symlink target untouched" test "$(cat "$SB/outside/f")" = "o"
rm "$R/extensions/_installed/lnk.refs"
# concurrent adds: 24 distinct projects at once, one shared refs file
for i in $(seq 1 24); do mkdir -p "$SB/cp$i"; done
for i in $(seq 1 24); do
  ( env HOME="$SB/home" python3 -I "$IMPL" --project "$SB/cp$i" --root "$R" refs add --id conc --record-digest "d$i" >/dev/null 2>&1 ) &
done
wait
wl refs count --id conc; eq "24 concurrent adds all land (flock)" 24 "$(jget "$OUT" count)"
LINES="$(wc -l <"$R/extensions/_installed/conc.refs")"; eq "refs file has exactly 24 intact lines" 24 "$LINES"
for i in $(seq 1 24); do
  ( env HOME="$SB/home" python3 -I "$IMPL" --project "$SB/cp$i" --root "$R" refs remove --id conc >/dev/null 2>&1 ) &
done
wait
wl refs count --id conc; eq "24 concurrent removes leave 0" 0 "$(jget "$OUT" count)"
# a corrupt line is reported, not silently dropped
printf 'garbage line\n' >"$R/extensions/_installed/bad.refs"
wl refs count --id bad; eq "corrupt refs file refused" 3 "$RC"

# ── 9d. wave 2 review round 2: F3 (check: never-wired vs ledger-lost), F4 (SOURCE_DATE_EPOCH refused, never a traceback) ──
# F3: a never-wired project is ok (golden-FALSE); a checkout holding local signatures whose tracked rows are gone is NOT
H1P="$SB/h1"; make_project "$H1P"
wlp "$H1P" check
eq "F3 never wired: check rc 0 (golden-FALSE, nothing to own)" 0 "$RC"
eq "F3 never wired: no orphan signatures" "[]" "$(jget "$OUT" orphans)"
mkdir -p "$H1P/.claude/skills"; ln -s "$R/skills/alpha" "$H1P/.claude/skills/alpha"
wlp "$H1P" record --id h1-a --producer installer --agent claude --path .claude/skills/alpha --kind symlink
wlp "$H1P" check; eq "F3 control: wired and intact, rc 0" 0 "$RC"
rm "$H1P/.constitution/wiring.json"
wlp "$H1P" check
eq "F3 tracked ledger deleted while this checkout still signs a row: check rc 1" 1 "$RC"
has "F3 the lost row is named" "h1-a" "$OUT"
has "F3 the state says the tracked row is missing" "tracked-row-missing" "$OUT"
eq "F3 ok is false" false "$(jget "$OUT" ok)"
wlp "$H1P" forget --id h1-a; eq "F3 forget of a row the ledger no longer has is refused" 3 "$RC"
# after a legitimate forget the signature goes too, so check is ok again (no false positive)
wlp "$H1P" record --id h1-a --producer installer --agent claude --path .claude/skills/alpha --kind symlink
wlp "$H1P" forget --id h1-a; wlp "$H1P" check
eq "F3 after a real forget: check rc 0 (golden-FALSE)" 0 "$RC"
# F4: SOURCE_DATE_EPOCH that is not a non-negative integer of seconds, or is out of range, is refused rc 3
H2P="$SB/h2"; make_project "$H2P"; printf 'b\n' >"$H2P/b.txt"
sde() { local v="$1"; shift; OUT="$(env HOME="$SB/home" SOURCE_DATE_EPOCH="$v" python3 -I "$IMPL" --project "$H2P" --root "$R" "$@" </dev/null 2>"$SB/err")"; RC=$?; ERR="$(cat "$SB/err")"; }
sde abc backup --path b.txt
eq "F4 backup with SOURCE_DATE_EPOCH=abc: refused rc 3" 3 "$RC"
hasnt "F4 abc: no Python traceback" "Traceback" "$ERR"
has "F4 abc: the refusal names the variable" "SOURCE_DATE_EPOCH" "$ERR"
check "F4 abc: no backup directory was made" test ! -e "$H2P/.constitution-install-backup"
sde 99999999999999999999 backup --path b.txt
eq "F4 backup with an out-of-range SOURCE_DATE_EPOCH: refused rc 3" 3 "$RC"
hasnt "F4 out of range: no Python traceback" "Traceback" "$ERR"
check "F4 out of range: no backup directory was made" test ! -e "$H2P/.constitution-install-backup"
mkdir -p "$H2P/.claude/skills"; ln -s "$R/skills/alpha" "$H2P/.claude/skills/alpha"
sde abc record --id h2-a --producer installer --agent claude --path .claude/skills/alpha --kind symlink
eq "F4 record refuses the same bad value the same way (rc 3, not silently ignored)" 3 "$RC"
check "F4 record wrote no ledger" test ! -e "$H2P/.constitution/wiring.json"
sde "" backup --path b.txt; eq "F4 control: an empty SOURCE_DATE_EPOCH means the clock (rc 0)" 0 "$RC"
sde 1700000000 record --id h2-a --producer installer --agent claude --path .claude/skills/alpha --kind symlink
eq "F4 control: a valid value is accepted" 0 "$RC"

# ── 11. determinism and meta ──────────────────────────────────────────────
DS=()
for n in 1 2 3; do
  DP="$SB/det$n"; make_project "$DP"; mkdir -p "$DP/.claude/skills"; ln -s "$R/skills/alpha" "$DP/.claude/skills/alpha"
  wlp "$DP" record --id d --producer installer --agent claude --path .claude/skills/alpha --kind symlink
  DS+=("$(sha256sum "$DP/.constitution/wiring.json" | cut -c1-64)")
done
eq "three runs give identical tracked-ledger hashes (1=2)" "${DS[0]}" "${DS[1]}"
eq "three runs give identical tracked-ledger hashes (2=3)" "${DS[1]}" "${DS[2]}"
eq "the constitution tree is unchanged by the whole suite" "$ROOT_FP_BEFORE" "$(rootfp)"
check "gitignore covers the local state" grep -q 'extensions.state/' "$P/.constitution/.gitignore"
finish
