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
