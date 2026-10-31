#!/usr/bin/env bash
# test_rotate_hardening.sh — regression tests for the review round 1 findings of
# rotate_setup_prompt.sh and the setup-prompt gate (each test was written first and
# observed RED against the unfixed scripts):
#   I1  non-ASCII NAME refused (rc=2) under the host UTF-8 locale and under LC_ALL=C;
#       gate verdict identical under both locales
#   I2  recovery refuses (rc=3) when the re-run asks for a DIFFERENT --source
#   I3  a symlinked .rotate.lock is refused; files outside the setup dir survive
#   I7  recovery never overwrites a latest.md that changed after the crash (R1)
#   I8  ln fallback never clobbers an existing archive (R3); a stale lock whose pid
#       was reused by a non-rotation process is recovered, not refused (R2)
#   M1  release refuses a lock whose identity is not ours
#   M3  --require-clean-git refuses a dirty or non-git setup directory
#   +   recovery refuses a staged file whose checksum does not match the journal
# Sandboxed under mktemp -d; no network; $HOME untouched.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

[ -r "$ROTATE" ] || { no "rotate script present"; summary hardening; exit 1; }

UTF8="$(locale -a 2>/dev/null | grep -iE '^en_US\.utf-?8$' | head -n1)"
[ -n "$UTF8" ] || UTF8="C.UTF-8"
dead_pid() { local p; true & p=$!; wait "$p"; printf '%s\n' "$p"; }

# --- I1: non-ASCII names ------------------------------------------------------
for nm in 'é' 'ß' 'ｍｙ_ｎａｍｅ' 'a_é' 'naïve'; do
  for loc in "$UTF8" C; do
    S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; before="$(tree_digest "$D")"
    LC_ALL="$loc" LANG="$loc" bash "$ROTATE" "$nm" --dir "$D" >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 2 ] && ok "I1 name '$nm' refused rc=2 under LC_ALL=$loc" || no "I1 name '$nm' under $loc rc=$rc (want 2)"
    [ "$(tree_digest "$D")" = "$before" ] && ok "I1 name '$nm' under $loc wrote nothing" || no "I1 name '$nm' under $loc changed the tree"
  done
done
G="$(mk_sandbox)"; mk_setup_dir "$G" >/dev/null; mkdir -p "$G/scripts"; printf '#!/bin/sh\n# --help\n' >"$G/scripts/real.sh"
printf '# x\n\n## PROMPT\n\n```\nbash submodules/constitution/scripts/real.sh --help\n```\n' >"$G/docs/prompts/setup/latest.md"
prompt_doc u >"$G/docs/prompts/setup/03_é.md"
v1="$(LC_ALL="$UTF8" LANG="$UTF8" bash "$GATE" --root "$G" 2>&1 | tail -n1)"; r1=$?
v2="$(LC_ALL=C LANG=C bash "$GATE" --root "$G" 2>&1 | tail -n1)"
[ "$v1" = "$v2" ] && ok "I1 gate verdict locale-independent ($v1)" || no "I1 gate verdict differs: $UTF8='$v1' C='$v2'"
case "$v1" in "VERDICT: FAIL"*) ok "I1 gate FAILs on non-ASCII history name" ;; *) no "I1 gate verdict on 03_é.md: $v1" ;; esac

# --- I2: recovery with a different --source ------------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc AAA >"$S/a.md"; prompt_doc BBB >"$S/b.md"
ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_link bash "$ROTATE" foo --source "$S/a.md" --dir "$D" >/dev/null 2>&1
out="$(bash "$ROTATE" foo --source "$S/b.md" --dir "$D" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "I2 re-run with a different --source refused rc=3" || no "I2 rc=$rc: $out"
cmp -s "$D/latest.md" "$S/a.md" && ok "I2 latest.md holds the interrupted run's content (recovery finished)" || no "I2 latest.md not A"
grep -q 'differs' <<<"$out" && ok "I2 message says the content differs" || no "I2 message: $out"
[ ! -e "$D/.rotate.lock" ] && ok "I2 lock cleared" || no "I2 lock left"
# same source after crash still completes rc=0 (no regression)
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc AAA >"$S/a.md"
ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_stage bash "$ROTATE" foo --source "$S/a.md" --dir "$D" >/dev/null 2>&1
expect_rc "I2 same --source after crash completes" 0 bash "$ROTATE" foo --source "$S/a.md" --dir "$D"
# no --source on the re-run while the interrupted run had one: refused
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc AAA >"$S/a.md"
ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_link bash "$ROTATE" foo --source "$S/a.md" --dir "$D" >/dev/null 2>&1
expect_rc "I2 re-run without --source after a --source crash refused" 3 bash "$ROTATE" foo --dir "$D"

# --- I3: symlinked lock ------------------------------------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; O="$S/outside"; mkdir -p "$O"
dead_pid >"$O/pid"; printf 'canary-staged\n' >"$O/staged"; printf 'name=x\ntarget=03_x.md\n' >"$O/journal"
printf 'canary\n' >"$O/canary"
ln -s "$O" "$D/.rotate.lock"; before="$(tree_digest "$O")"; lbefore="$(cat "$D/latest.md")"
expect_rc "I3 symlinked .rotate.lock refused" 3 bash "$ROTATE" x --dir "$D"
[ "$(tree_digest "$O")" = "$before" ] && ok "I3 outside directory untouched (pid, staged, journal, canary)" || no "I3 outside files changed: $(ls -A "$O" | tr '\n' ' ')"
[ "$(cat "$D/latest.md")" = "$lbefore" ] && ok "I3 latest.md untouched" || no "I3 latest.md changed"
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; printf 'not a dir\n' >"$D/.rotate.lock"
expect_rc "I3 .rotate.lock that is a plain file refused" 3 bash "$ROTATE" x --dir "$D"
[ "$(cat "$D/.rotate.lock")" = "not a dir" ] && ok "I3 plain-file lock left untouched" || no "I3 plain-file lock modified"

# --- I7 (R1): latest.md changed after the crash ------------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc NEW >"$S/n.md"
ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_link bash "$ROTATE" r1 --source "$S/n.md" --dir "$D" >/dev/null 2>&1
rm -f "$D/latest.md"; prompt_doc HUMAN_EDIT >"$D/latest.md"   # a person replaced latest.md (new inode)
before="$(tree_digest "$D")"
expect_rc "I7 recovery refuses when latest.md changed after the crash" 3 bash "$ROTATE" r1 --source "$S/n.md" --dir "$D"
[ "$(tree_digest "$D")" = "$before" ] && ok "I7 nothing changed (human edit preserved)" || no "I7 tree changed"
grep -q HUMAN_EDIT "$D/latest.md" && ok "I7 latest.md still holds the human edit" || no "I7 human edit lost"

# --- staged checksum mismatch ------------------------------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc NEW >"$S/n.md"
ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_link bash "$ROTATE" st --source "$S/n.md" --dir "$D" >/dev/null 2>&1
prompt_doc TAMPERED >"$D/.rotate.lock/staged"; lbefore="$(cat "$D/latest.md")"
expect_rc "staged file not matching the journal checksum refused" 3 bash "$ROTATE" st --source "$S/n.md" --dir "$D"
[ "$(cat "$D/latest.md")" = "$lbefore" ] && ok "tampered staged file never installed" || no "tampered staged installed"
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc NEW >"$S/n.md"
ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_link bash "$ROTATE" sl --source "$S/n.md" --dir "$D" >/dev/null 2>&1
rm -f "$D/.rotate.lock/staged"; ln -s "$S/n.md" "$D/.rotate.lock/staged"
expect_rc "staged symlink refused" 3 bash "$ROTATE" sl --source "$S/n.md" --dir "$D"
[ ! -L "$D/latest.md" ] && ok "latest.md never became a symlink" || no "latest.md is a symlink"

# --- I8 (R3): ln fails and the archive name appears meanwhile -------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc NEW >"$S/n.md"; SH="$S/shim"; mkdir -p "$SH"
cat >"$SH/ln" <<'SHIM'
#!/usr/bin/env bash
# test shim: a concurrent writer creates the archive name, then the hard link fails
for a in "$@"; do last="$a"; done
printf 'canary-archive\n' >"$last"
exit 1
SHIM
chmod +x "$SH/ln"
PATH="$SH:$PATH" bash "$ROTATE" r3 --source "$S/n.md" --dir "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "I8 fallback archive refuses an existing target (rc=$rc)" || no "I8 fallback rc=0"
[ "$(cat "$D/03_r3.md" 2>/dev/null)" = "canary-archive" ] && ok "I8 existing 03_r3.md never clobbered" || no "I8 03_r3.md clobbered: $(head -c 60 "$D/03_r3.md" 2>/dev/null)"
grep -q 'current' "$D/latest.md" && ok "I8 latest.md not replaced after a failed archive" || no "I8 latest.md replaced"
# ln fails without a race: the copy fallback archives correctly
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc NEW >"$S/n.md"; SH="$S/shim"; mkdir -p "$SH"
printf '#!/bin/sh\nexit 1\n' >"$SH/ln"; chmod +x "$SH/ln"; old="$(cat "$D/latest.md")"
PATH="$SH:$PATH" bash "$ROTATE" cp_fb --source "$S/n.md" --dir "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$D/03_cp_fb.md")" = "$old" ] && cmp -s "$D/latest.md" "$S/n.md" \
  && ok "I8 copy fallback archives and installs (rc=0)" || no "I8 copy fallback rc=$rc"

# --- I8 (R2): pid reused by a non-rotation process -----------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; old="$(cat "$D/latest.md")"
sleep 30 & SP=$!
mkdir "$D/.rotate.lock"; printf '%s\n' "$SP" >"$D/.rotate.lock/pid"; printf 'name=gone\ntarget=03_gone.md\n' >"$D/.rotate.lock/journal"
touch -d '1 hour ago' "$D/.rotate.lock"
out="$(bash "$ROTATE" r2 --dir "$D" 2>&1)"; rc=$?
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
[ "$rc" -eq 0 ] && ok "I8 stale lock with a reused (non-rotation) pid recovered" || no "I8 reused pid rc=$rc: $out"
[ -f "$D/03_r2.md" ] && [ "$(cat "$D/03_r2.md")" = "$old" ] && ok "I8 rotation done after recovery" || no "I8 no 03_r2.md"

# --- M1: release refuses a lock that is not ours -------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; mkdir "$D/.rotate.lock"; printf '12345 othernonce\n' >"$D/.rotate.lock/pid"
( ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 . "$ROTATE"; RSP_LOCK_ID="$$ mynonce"; rsp_release_lock "$D/.rotate.lock" ) >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && [ -f "$D/.rotate.lock/pid" ] && ok "M1 release refuses a lock with another identity" || no "M1 foreign lock released (rc=$rc)"

# --- M3: --require-clean-git --------------------------------------------------------
S="$(mk_sandbox)"; git -C "$S" init -q; D="$(mk_setup_dir "$S")"; git -C "$S" add -A; git -C "$S" commit -q -m i
expect_rc "M3 clean git tree accepted" 0 bash "$ROTATE" clean_one --require-clean-git --dir "$D"
git -C "$S" add -A; git -C "$S" commit -q -m r
printf 'edit\n' >>"$D/01_old.md"; before="$(tree_digest "$D")"
expect_rc "M3 dirty setup directory refused" 3 bash "$ROTATE" dirty_one --require-clean-git --dir "$D"
[ "$(tree_digest "$D")" = "$before" ] && ok "M3 refusal wrote nothing" || no "M3 refusal changed the tree"
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
expect_rc "M3 non-git directory refused with --require-clean-git" 3 bash "$ROTATE" nogit --require-clean-git --dir "$D"
expect_rc "M3 non-git directory accepted without the flag" 0 bash "$ROTATE" nogit --dir "$D"

summary hardening
