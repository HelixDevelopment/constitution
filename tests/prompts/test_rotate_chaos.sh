#!/usr/bin/env bash
# test_rotate_chaos.sh — CHAOS tests: the rotation is killed (SIGKILL via the
# test-only seam ROTATE_SETUP_PROMPT_TEST_KILL_AT, honoured only with
# ROTATE_SETUP_PROMPT_TEST_MODE=1) or interrupted (SIGINT/SIGTERM while paused at
# ROTATE_SETUP_PROMPT_TEST_PAUSE_AT) at every stage, then re-run. The re-run must
# recover to a consistent state: latest.md present, exactly one archive of the old
# content, no stray lock or temp file, and no file content lost.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -r "$ROTATE" ] || { no "rotate script present"; summary chaos; exit 1; }

all_contents() { cat "$1"/*.md 2>/dev/null | sha256sum | cut -d' ' -f1; }

for stage in after_lock after_journal after_stage after_link after_rename; do
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc fresh_"$stage" >"$S/new.md"
  old="$(cat "$D/latest.md")"
  ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT="$stage" \
    bash "$ROTATE" crash_rot --source "$S/new.md" --dir "$D" >/dev/null 2>&1; krc=$?
  [ "$krc" -eq 137 ] && ok "[$stage] killed by SIGKILL (rc=137)" || no "[$stage] kill seam rc=$krc"
  [ -f "$D/latest.md" ] && ok "[$stage] latest.md present right after crash" || no "[$stage] latest.md missing after crash"
  # re-run the same request: must recover and complete
  out="$(bash "$ROTATE" crash_rot --source "$S/new.md" --dir "$D" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "[$stage] re-run rc=0" || no "[$stage] re-run rc=$rc: $out"
  [ "$(cat "$D/03_crash_rot.md" 2>/dev/null)" = "$old" ] && ok "[$stage] old content archived as 03" || no "[$stage] 03 archive wrong/missing"
  cmp -s "$D/latest.md" "$S/new.md" && ok "[$stage] latest.md = new content" || no "[$stage] latest.md wrong"
  [ ! -e "$D/.rotate.lock" ] && ok "[$stage] no lock left" || no "[$stage] lock left"
  n="$(cd "$D" && ls -A | wc -l)"; [ "$n" -eq 4 ] && ok "[$stage] exactly 4 files" || no "[$stage] $n entries: $(ls -A "$D" | tr '\n' ' ')"
  [ ! -e "$D/04_crash_rot.md" ] && ok "[$stage] no duplicate archive" || no "[$stage] duplicate 04 archive"
done

# crash, then re-run with a DIFFERENT name: the interrupted rotation is finished first
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc n1 >"$S/n1.md"; prompt_doc n2 >"$S/n2.md"
old="$(cat "$D/latest.md")"
ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_link bash "$ROTATE" one --source "$S/n1.md" --dir "$D" >/dev/null 2>&1
expect_rc "re-run with another name after crash" 0 bash "$ROTATE" two --source "$S/n2.md" --dir "$D"
[ "$(cat "$D/03_one.md")" = "$old" ] && cmp -s "$D/04_two.md" "$S/n1.md" && cmp -s "$D/latest.md" "$S/n2.md" \
  && ok "interrupted rotation finished, then the new one applied (03_one, 04_two, latest=n2)" || no "mixed recovery wrong: $(ls "$D" | tr '\n' ' ')"

# SIGINT and SIGTERM while paused after the link step; then re-run
for sig in INT TERM; do
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc s"$sig" >"$S/new.md"; old="$(cat "$D/latest.md")"
  # env --default-signal: a background job of a non-interactive shell starts with
  # SIGINT ignored, and bash cannot trap a signal ignored on entry; restore it.
  ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=after_link \
    env --default-signal=INT bash "$ROTATE" sig_rot --source "$S/new.md" --dir "$D" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 100); do [ -f "$D/03_sig_rot.md" ] && break; sleep 0.05; done
  # a second rotation while the first holds the lock is refused (live lock)
  expect_rc "[$sig] concurrent rotation refused while lock is live" 3 bash "$ROTATE" other --dir "$D"
  kill -s "$sig" "$pid"; wait "$pid"; src=$?
  [ "$src" -ne 0 ] && ok "[$sig] interrupted process exited non-zero ($src)" || no "[$sig] interrupted process exited 0"
  expect_rc "[$sig] re-run recovers" 0 bash "$ROTATE" sig_rot --source "$S/new.md" --dir "$D"
  [ "$(cat "$D/03_sig_rot.md")" = "$old" ] && cmp -s "$D/latest.md" "$S/new.md" && [ ! -e "$D/.rotate.lock" ] \
    && ok "[$sig] consistent after recovery" || no "[$sig] inconsistent after recovery"
done

# test seams are inert without TEST_MODE=1
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
ROTATE_SETUP_PROMPT_TEST_KILL_AT=after_link bash "$ROTATE" inert --dir "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -f "$D/03_inert.md" ] && ok "kill seam ignored without TEST_MODE" || no "kill seam active without TEST_MODE rc=$rc"

summary chaos
