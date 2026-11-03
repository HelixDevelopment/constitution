#!/usr/bin/env bash
# test_security.sh — SECURITY tests for the installer: flag/URL/path injection, refusal of symlinked
# governance files, credential hygiene (no secret value ever printed, logged or written to the report),
# root refusal, and curl|bash TRUNCATION SAFETY proven by really truncating the script at many byte offsets
# and executing each prefix exactly like a broken download would be executed (stdin into bash).
# The root case uses HELIX_INSTALLER_TEST_EUID=0, a seam that can only make the installer STRICTER
# (it can declare root, never hide it): UNIT-class evidence, labelled so.
# Usage: bash tests/install/test_security.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=security
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off)

echo "# flag injection is rejected before anything runs"
P="$SB/p"; new_project "$P"; s0="$(project_state "$P")"
inj() { # description expected-rc args...
  local d="$1" want="$2"; shift 2
  run_installer "$P" "$@"
  eq "$d -> exit $want" "$want" "$RC"
  check "$d: no PWNED marker" eval '[ ! -e "$SB/PWNED" ] && [ ! -e "$P/PWNED" ]'
}
inj "agent with ;"            2 "${BASE[@]}" --upstream-url "$UP" --agent "x;touch $SB/PWNED"
inj "agent command subst"     2 --non-interactive --run-setup off --upstream-url "$UP" --agent '$(touch PWNED)'
inj "ext:: transport url"     2 "${BASE[@]}" --upstream-url "ext::sh -c touch% $SB/PWNED"
inj "--upload-pack as url"    2 "${BASE[@]}" --upstream-url "--upload-pack=touch $SB/PWNED"
inj "url with backticks"      2 "${BASE[@]}" --upstream-url 'https://x/`touch PWNED`'
inj "ref option-like"         2 "${BASE[@]}" --upstream-url "$UP" --ref "--upload-pack=touch $SB/PWNED"
inj "model with ;"            2 "${BASE[@]}" --upstream-url "$UP" --model 'sonnet;touch PWNED'
inj "timeout non-numeric"     2 "${BASE[@]}" --upstream-url "$UP" --timeout-sec '1;touch PWNED'
inj "upstream key unknown"    2 "${BASE[@]}" --upstream 'github;touch PWNED'
inj "report path with newline" 2 "${BASE[@]}" --upstream-url "$UP" --report-json $'/tmp/a\nb'
eq "injection attempts wrote nothing" "$s0" "$(project_state "$P")"

echo "# --restore: hostile backups and manifest entries are refused (IMPORTANT-4)"
RP="$SB/rp"; new_project "$RP"; RBK="$RP/.constitution-install-backup"
mkbk() { # NAME — a fresh, untracked, mode-700 backup dir owned by the user
  mkdir -p "$RBK/$1/files"; chmod 700 "$RBK" "$RBK/$1" "$RBK/$1/files"; : >"$RBK/$1/manifest.txt"; }
addent() { # NAME ENTRY [CONTENT] — manifest line + its file under files/
  printf '%s\n' "$2" >>"$RBK/$1/manifest.txt"; mkdir -p "$RBK/$1/files/$(dirname "$2")"
  printf '%s\n' "${3:-from backup}" >"$RBK/$1/files/$2"; }
gcfg0="$(sha256sum <"$RP/.git/config")"
# the fsmonitor payload: if .git/config were overwritten, the next git command in the project would run it
EVILCFG="$(printf '[core]\n\trepositoryformatversion = 0\n\tfsmonitor = touch %s/PWNED-FSMONITOR\n' "$SB")"
mkbk e1; addent e1 .git/config "$EVILCFG"
for ent in ./.git/config a/../.git/config .GIT/config .git./config '.git /config' .git//config sub/.git/config; do
  printf '%s\n' "$ent" >>"$RBK/e1/manifest.txt"; done
run_installer "$RP" --restore "$RBK/e1"; eq "--restore with only .git entries: exit 0 (entries skipped)" 0 "$RC"
check "--restore names the refused .git entry" grep -q 'unsafe manifest entry' <<<"$OUT"
check "--restore reports 0 restored" grep -q 'restored 0 file' <<<"$OUT"
eq ".git/config unchanged after hostile --restore" "$gcfg0" "$(sha256sum <"$RP/.git/config")"
git -C "$RP" status --porcelain >/dev/null 2>&1
check "core.fsmonitor never executed (no PWNED-FSMONITOR)" eval '[ ! -e "$SB/PWNED-FSMONITOR" ]'
mkbk e2; for ent in submodules/constitution/Constitution.md SUBMODULES/Constitution/x constitution/CLAUDE.md \
  ./constitution/x .constitution-install-backup/e1/manifest.txt /etc/passwd ../x a/../../x $'a\x01b.md'; do
  printf '%s\n' "$ent" >>"$RBK/e2/manifest.txt"; done
run_installer "$RP" --restore "$RBK/e2"; eq "--restore with constitution/abs/.. entries: exit 0" 0 "$RC"
check "--restore e2 restored nothing" grep -q 'restored 0 file' <<<"$OUT"
check "no file appeared under constitution/" eval '[ ! -e "$RP/constitution" ]'
# precise ".." check (M4): a name that merely contains two dots is legal
mkbk ok1; addent ok1 'a..b.md' 'dots ok'; addent ok1 'docs/x..y/z.md' 'nested ok'
run_installer "$RP" --restore "$RBK/ok1"; eq "--restore a..b.md: exit 0" 0 "$RC"
eq "a..b.md restored" 'dots ok' "$(cat "$RP/a..b.md" 2>/dev/null)"
eq "docs/x..y/z.md restored" 'nested ok' "$(cat "$RP/docs/x..y/z.md" 2>/dev/null)"
# a backup file that is a symlink is not copied (it could point anywhere)
mkbk s1; printf 'CLAUDE.md\n' >"$RBK/s1/manifest.txt"; ln -s /etc/hostname "$RBK/s1/files/CLAUDE.md"
run_installer "$RP" --restore "$RBK/s1"; eq "--restore symlinked backup file: exit 0" 0 "$RC"
check "symlinked backup file not restored" eval '[ ! -L "$RP/CLAUDE.md" ]'
# the backup directory itself must be private, owned by the user and untracked
mkbk m1; addent m1 m1.md; chmod 755 "$RBK/m1"
run_installer "$RP" --restore "$RBK/m1"; eq "--restore backup dir mode 755: refused exit 2" 2 "$RC"
check "mode refusal explained" grep -q 'mode 700' <<<"$OUT"
check "mode-755 backup restored nothing" eval '[ ! -e "$RP/m1.md" ]'
mkbk l1; addent l1 l1.md; ln -s "$RBK/l1" "$RBK/l1link"
run_installer "$RP" --restore "$RBK/l1link"; eq "--restore through a symlinked backup dir: refused exit 2" 2 "$RC"
mkbk n1; mkdir -p "$RBK/n1/deeper/files"; chmod 700 "$RBK/n1/deeper"; printf 'n1.md\n' >"$RBK/n1/deeper/manifest.txt"; printf x >"$RBK/n1/deeper/files/n1.md"
run_installer "$RP" --restore "$RBK/n1/deeper"; eq "--restore nested deeper than one stamp dir: refused exit 2" 2 "$RC"
# a COMMITTED backup (someone pushed a booby-trapped backup dir into the repository) is refused outright
TP="$SB/tp"; new_project "$TP"; TBK="$TP/.constitution-install-backup/evil"
mkdir -p "$TBK/files/.git"; printf '%s\n' "$EVILCFG" >"$TBK/files/.git/config"; printf 'CLAUDE.md\n' >"$TBK/manifest.txt"
mkdir -p "$TBK/files"; printf 'trap\n' >"$TBK/files/CLAUDE.md"; chmod 700 "$TP/.constitution-install-backup" "$TBK" "$TBK/files"
git -C "$TP" add -f .constitution-install-backup; git -C "$TP" commit -qm evil-backup
tcfg0="$(sha256sum <"$TP/.git/config")"
run_installer "$TP" --restore "$TBK"; eq "--restore of a backup tracked by git: refused exit 2" 2 "$RC"
check "tracked refusal explained" grep -q 'tracked by git' <<<"$OUT"
eq "tracked backup: .git/config unchanged" "$tcfg0" "$(sha256sum <"$TP/.git/config")"
check "tracked backup: CLAUDE.md not written" eval '[ ! -e "$TP/CLAUDE.md" ] || ! grep -q trap "$TP/CLAUDE.md"'
git -C "$TP" status --porcelain >/dev/null 2>&1
check "tracked backup: fsmonitor never executed" eval '[ ! -e "$SB/PWNED-FSMONITOR" ]'
# an absolute entry is refused even when a matching backup copy exists (it is never re-rooted into the project)
mkbk a1; printf '/abs-entry.md\n' >"$RBK/a1/manifest.txt"; printf 'abs\n' >"$RBK/a1/files/abs-entry.md"
run_installer "$RP" --restore "$RBK/a1"; eq "--restore absolute entry with a backup copy: exit 0" 0 "$RC"
check "absolute entry refused by name" grep -q 'unsafe manifest entry: /abs-entry.md' <<<"$OUT"
check "absolute entry: nothing restored into the project" eval '[ ! -e "$RP/abs-entry.md" ]'
# a ".." entry is refused even when files/../NAME exists: it would land OUTSIDE the project
mkbk d1; printf '../outside-d1.md\n' >"$RBK/d1/manifest.txt"; printf 'escape\n' >"$RBK/d1/outside-d1.md"
run_installer "$RP" --restore "$RBK/d1"; eq "--restore ../ entry with a reachable copy: exit 0" 0 "$RC"
check ".. entry refused by name" grep -q 'unsafe manifest entry: ../outside-d1.md' <<<"$OUT"
check ".. entry: nothing written outside the project" eval '[ ! -e "$SB/outside-d1.md" ]'
# a backup the installer itself creates is private (700) and therefore restorable
BKP="$SB/bkp"; new_project "$BKP"
o="$(cd "$BKP" && umask 022 && HELIX_INSTALLER_LIB_MODE=1 bash -c '. "$1"; set +e; hi_init_state; hi_gx_bin; O_ROOT="$2"
     hi_backup_dir >/dev/null && printf "\nBK=%s\n" "$S_BK"' x "$INSTALLER" "$BKP" 2>&1)"   # hi_backup_dir prints its path with no newline
bkd="$(sed -n 's/^BK=//p' <<<"$o")"
check "hi_backup_dir created a backup dir" eval '[ -n "$bkd" ] && [ -d "$bkd/files" ]'
eq "installer-made backup dir is mode 700 (umask 022)" 700 "$(stat -c %a "$bkd" 2>/dev/null)"
eq "installer-made backup files/ is mode 700 (umask 022)" 700 "$(stat -c %a "$bkd/files" 2>/dev/null)"
printf 'kept.md\n' >"$bkd/manifest.txt"; printf 'kept\n' >"$bkd/files/kept.md"
run_installer "$BKP" --restore "$bkd"; eq "installer-made backup is accepted by --restore (exit 0)" 0 "$RC"
eq "installer-made backup: file restored" kept "$(cat "$BKP/kept.md" 2>/dev/null)"
# control needle: a normal, private, untracked backup is restored
mkbk good; addent good restored-good.md 'good'
run_installer "$RP" --restore "$RBK/good"; eq "control needle: normal --restore exit 0" 0 "$RC"
eq "control needle: normal file restored" good "$(cat "$RP/restored-good.md" 2>/dev/null)"

echo "# hostile but legal project path (spaces, \$(), quotes) is handled as data"
HP="$SB/we ird \$(touch PWNED) 'q'"; new_project "$HP"
run_installer "$HP" "${BASE[@]}" --upstream-url "$UP"
eq "hostile path install exit 0" 0 "$RC"; eq "hostile path gitlink" "$V0" "$(gitlink "$HP")"
check "hostile path: no PWNED anywhere" eval '[ -z "$(find "$SB" -name PWNED -print -quit)" ]'

echo "# symlinked governance file is never edited through the link"
SP="$SB/sym"; new_project "$SP"; printf 'outside original\n' >"$SB/outside.md"; ln -s "$SB/outside.md" "$SP/CLAUDE.md"
git -C "$SP" add CLAUDE.md; git -C "$SP" commit -qm link; s0="$(project_state "$SP")"
run_installer "$SP" "${BASE[@]}" --upstream-url "$UP"
eq "symlinked CLAUDE.md -> exit 3" 3 "$RC"
eq "outside file untouched" "outside original" "$(cat "$SB/outside.md")"
eq "symlink refusal wrote nothing" "$s0" "$(project_state "$SP")"

echo "# credentials are never printed or stored"
export ANTHROPIC_API_KEY="sk-ant-SENTINEL-AAA111" TYPESAFE_API_KEY="SENTINEL-BBB222" OPENROUTER_API_KEY="SENTINEL-CCC333"
CP="$SB/cred"; new_project "$CP"
run_installer "$CP" "${BASE[@]}" --upstream-url "https://u:SENTINEL-PW-DDD444@127.0.0.1:9/x.git" --upstream-url "$UP" --report-json "$SB/cred.json"
eq "credential-url fallback install exit 0" 0 "$RC"
check "no sentinel in console output" eval '! printf "%s" "$OUT" | grep -q SENTINEL'
check "no sentinel in report or backups" eval '! grep -rq SENTINEL "$SB/cred.json" "$CP/.constitution-install-backup"'
check "no sentinel in written governance files" eval '! grep -q SENTINEL "$CP/CLAUDE.md" "$CP/AGENTS.md"'
unset ANTHROPIC_API_KEY TYPESAFE_API_KEY OPENROUTER_API_KEY

echo "# root refusal (UNIT seam: HELIX_INSTALLER_TEST_EUID=0 can only add the restriction)"
RP="$SB/root"; new_project "$RP"; s0="$(project_state "$RP")"
OUT="$(cd "$RP" && HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_EUID=0 bash "$INSTALLER" "${BASE[@]}" --upstream-url "$UP" 2>&1)"; RC=$?
eq "root without --yes -> exit 3" 3 "$RC"; eq "root refusal wrote nothing" "$s0" "$(project_state "$RP")"
OUT="$(cd "$RP" && HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_EUID=0 bash "$INSTALLER" "${BASE[@]}" --upstream-url "$UP" --yes --dry-run 2>&1)"; RC=$?
eq "root with --yes proceeds (dry-run) exit 0" 0 "$RC"
OUT="$(cd "$RP" && HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_EUID=1000 bash "$INSTALLER" --print-snippets 2>&1)"; RC=$?
eq "non-zero test euid is ignored (cannot hide real root)" 0 "$RC"

echo "# truncated download never runs anything"
size="$(wc -c <"$INSTALLER")"
offsets=(); for ((k=1; k<size; k+=397)); do offsets+=("$k"); done
# size-1 drops only the final newline: the sentinel call is then complete (a full script), so stop at size-2
for ((k=size-120; k<size-1; k++)); do offsets+=("$k"); done
TP="$SB/trunc"; new_project "$TP"; s0="$(project_state "$TP")"; bad=0; ran=0
for k in "${offsets[@]}"; do
  head -c "$k" "$INSTALLER" >"$SB/t.sh"
  o="$(cd "$TP" && bash -s -- "${BASE[@]}" --upstream-url "$UP" <"$SB/t.sh" 2>&1)"; ran=$((ran+1))
  # bash's own syntax-error message quotes the cut source line ("bash: line N: `...submodule add...'"): that is
  # not the installer starting work, so those lines are left out of the output check
  if [ -e "$TP/submodules" ] || [ "$(project_state "$TP")" != "$s0" ] \
     || printf '%s\n' "$o" | grep -v '^bash: line [0-9]*: ' | grep -q 'Installing\|submodule add'; then
    bad=$((bad+1)); echo "    truncation offset $k changed the project or started work"; fi
done
eq "truncated prefixes executed: none had any effect (of ${#offsets[@]})" 0 "$bad"
check "truncation loop really ran" eval '[ "$ran" -gt 150 ]'
o="$(cd "$TP" && bash -s -- "${BASE[@]}" --upstream-url "$UP" <"$INSTALLER" 2>&1)"; rc=$?
eq "positive control: the complete script with the same args installs" 0 "$rc"
eq "positive control gitlink" "$V0" "$(gitlink "$TP")"

echo "# truncated download with NO argument (plain curl | bash) never runs anything"
# Same prefixes, no argument, the interactive input closed (HELIX_INSTALLER_TTY=/dev/null): a prefix must
# print no installer line and create no file in a fresh empty directory.
Z="$SB/zeroarg"; mkdir "$Z"; badz=0; ranz=0
zrun() { (cd "$Z" && HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TTY=/dev/null timeout 60 bash -s 2>&1 <"$1"); }
for k in "${offsets[@]}"; do
  head -c "$k" "$INSTALLER" >"$SB/t.sh"; o="$(zrun "$SB/t.sh")"; ranz=$((ranz+1))
  if [ -n "$(ls -A "$Z")" ] || grep -q '^\[constitution\]' <<<"$o"; then
    badz=$((badz+1)); echo "    zero-arg truncation offset $k ran the installer or wrote a file"; fi
done
eq "zero-arg truncated prefixes: none ran (of ${#offsets[@]})" 0 "$badz"
check "zero-arg loop really ran" eval '[ "$ranz" -gt 150 ]'
o="$(zrun "$INSTALLER")"
check "control needle: the complete file with no argument does run (prints an installer line)" grep -q '^\[constitution\]' <<<"$o"
check "control needle: the complete file is not mistaken for a truncated one" eval '! grep -q "incomplete script" <<<"$o"'
check "control needle run wrote nothing (input closed before any change)" eval '[ -z "$(ls -A "$Z")" ]'
echo "# test switches are not honoured outside test mode (M-3)"
LP="$SB/libmode"; new_project "$LP"
OUT="$(cd "$LP" && HELIX_INSTALLER_LIB_MODE=1 bash "$INSTALLER" "${BASE[@]}" --upstream-url "$UP" --dry-run 2>&1)"; RC=$?
check "ambient HELIX_INSTALLER_LIB_MODE=1 while RUN: a warning names it" grep -q 'ignoring HELIX_INSTALLER_LIB_MODE' <<<"$OUT"
eq "ambient HELIX_INSTALLER_LIB_MODE=1: the dry run still runs (exit 0)" 0 "$RC"
check "ambient HELIX_INSTALLER_LIB_MODE=1: the plan is printed (not a silent no-op)" grep -q '^\[constitution\]' <<<"$OUT"
OUT="$(HELIX_UPDATER_LIB_MODE=1 bash "$UPDATER" --help 2>&1)"; RC=$?
check "ambient HELIX_UPDATER_LIB_MODE=1 while RUN: a warning names it" grep -q 'ignoring HELIX_UPDATER_LIB_MODE' <<<"$OUT"
eq "ambient HELIX_UPDATER_LIB_MODE=1: --help still runs (exit 0)" 0 "$RC"
OUT="$(cd "$RP" && HELIX_INSTALLER_TEST_EUID=0 bash "$INSTALLER" "${BASE[@]}" --upstream-url "$UP" --dry-run 2>&1)"; RC=$?
check "HELIX_INSTALLER_TEST_EUID without HELIX_INSTALLER_TEST=1: warned" grep -q 'ignoring HELIX_INSTALLER_TEST_EUID' <<<"$OUT"
eq "HELIX_INSTALLER_TEST_EUID without test mode: ignored (dry run exit 0)" 0 "$RC"
if command -v setsid >/dev/null 2>&1; then
  printf 'y\ny\ny\ny\ny\ny\ny\ny\n' >"$SB/answers"
  OUT="$(cd "$RP" && HELIX_INSTALLER_TTY="$SB/answers" timeout 60 setsid -w bash "$INSTALLER" --run-setup off --upstream-url "$UP" --dry-run </dev/null 2>&1)"; RC=$?
  check "HELIX_INSTALLER_TTY without HELIX_INSTALLER_TEST=1: warned" grep -q 'ignoring HELIX_INSTALLER_TTY' <<<"$OUT"
  eq "HELIX_INSTALLER_TTY without test mode: the file is not used as the terminal (no tty -> exit 2)" 2 "$RC"
  check "... and says there is no terminal" grep -q 'no terminal' <<<"$OUT"
else
  ok "SKIP: setsid not present (topology_unsupported): the HELIX_INSTALLER_TTY case needs a process without a terminal"
fi

echo "# '... | sh' never runs a file named like the shell from the current directory (M-4)"
if [ -z "$(sh -c 'printf %s "${BASH_VERSION:-}"')" ]; then
  D="$SB/shplant"; mkdir "$D"
  printf 'echo PWNED\n# __helix_installer_eof__\n' >"$D/sh"
  OUT="$(cd "$D" && sh <"$INSTALLER" 2>&1)"; RC=$?
  check "a planted ./sh with the marker did not run" eval '! grep -q PWNED <<<"$OUT"'
  eq "piped into sh: refused with exit 2" 2 "$RC"
  check "piped into sh: the message says to pipe into bash" grep -q 'bash -s' <<<"$OUT"
  OUT="$(cd "$D" && sh "$INSTALLER" --print-snippets 2>&1)"; RC=$?
  eq "control: sh PATH/install_constitution.sh re-executes under bash (exit 0)" 0 "$RC"
  check "control: ... and says so" grep -q 're-executing under bash' <<<"$OUT"
else
  ok "SKIP: /bin/sh is bash here (topology_unsupported): the POSIX re-exec block never runs"
fi

finish
