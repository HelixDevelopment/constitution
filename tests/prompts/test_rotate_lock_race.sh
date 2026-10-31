#!/usr/bin/env bash
# test_rotate_lock_race.sh — the rotation lock is an EXCLUSIVE create (review round 6,
# conductor finding: `mkdir` of uutils coreutils 0.8.0 is not exclusive; measured, two
# simultaneous mkdir of one path both succeed in 45-86 of 200 rounds).
# R rounds (default 20) of N concurrent rotations (default 8, distinct NAMEs, one barrier).
# The winner is held for ROTATE_RACE_HOLD seconds after it took the lock (test seam
# ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=after_lock with ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC),
# so every other run reaches the lock while it is held. Per round the oracle requires:
#   exactly ONE run exits 0, every other run exits 3, exactly ONE new archive exists,
#   the numbered history is gap-free and unique, no lock is left behind.
# Also: a stale lock in the legacy directory form (dead owner) is still reclaimed, and a
# FIFO / symlink planted as the claim file is refused without being opened.
# Env: ROTATE_RACE_ROUNDS, ROTATE_RACE_N, ROTATE_RACE_HOLD, ROTATE_RACE_SCRIPT (script under test).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="${ROTATE_RACE_ROUNDS:-20}"; N="${ROTATE_RACE_N:-8}"; HOLD="${ROTATE_RACE_HOLD:-2}"
SCRIPT="${ROTATE_RACE_SCRIPT:-$ROTATE}"
[ -r "$SCRIPT" ] || { no "rotate script present"; summary lock_race; exit 1; }
# control: the script under test rotates at all (a broken script would "refuse" every run)
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc ctl >"$S/new.md"
bash "$SCRIPT" ctl_one --source "$S/new.md" --dir "$D" >"$S/o" 2>&1 && cmp -s "$D/latest.md" "$S/new.md" \
  && ok "control: one plain rotation succeeds" || { no "control: a plain rotation fails: $(cat "$S/o")"; summary lock_race; exit 1; }
bad_rounds=0
for round in $(seq 1 "$R"); do
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc "race$round" >"$S/new.md"
  before="$(ls "$D" | grep -cE '^[0-9]+_')"
  for i in $(seq 1 "$N"); do
    ( while [ ! -e "$S/go" ]; do :; done
      ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=after_lock ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC="$HOLD" \
        bash "$SCRIPT" "r$i" --source "$S/new.md" --dir "$D" >"$S/o$i" 2>&1; echo $? >"$S/rc$i" ) &
  done
  sleep 0.3; : >"$S/go"; wait
  win=0; ref=0; other=""
  for i in $(seq 1 "$N"); do
    case "$(cat "$S/rc$i")" in 0) win=$((win + 1)) ;; 3) ref=$((ref + 1)) ;; *) other="$other r$i=$(cat "$S/rc$i")" ;; esac
  done
  after="$(ls "$D" | grep -cE '^[0-9]+_')"
  scan="$(ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 bash -c '. "$1"; rsp_scan_numbering "$2" 2>&1 && echo CLEAN' _ "$SCRIPT" "$D")"
  if [ "$win" -eq 1 ] && [ "$ref" -eq $((N - 1)) ] && [ -z "$other" ] && [ $((after - before)) -eq 1 ] \
     && grep -q '^CLEAN$' <<<"$scan" && [ ! -e "$D/.rotate.lock" ] && [ ! -L "$D/.rotate.lock" ]; then
    :
  else
    bad_rounds=$((bad_rounds + 1))
    printf 'round %s: winners=%s refused=%s other=[%s] new_archives=%s lock_left=%s scan=%s files=%s\n' \
      "$round" "$win" "$ref" "$other" "$((after - before))" "$([ -e "$D/.rotate.lock" ] && echo yes || echo no)" \
      "$(tr '\n' ' ' <<<"$scan" | cut -c1-120)" "$(ls "$D" | tr '\n' ' ')"
  fi
done
[ "$bad_rounds" -eq 0 ] && ok "lock race: $R rounds x $N concurrent rotations, exactly one winner each, history gap-free" \
  || no "lock race: $bad_rounds of $R rounds broke mutual exclusion"

# a stale lock in the legacy DIRECTORY form whose owner is dead is still reclaimed
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc stale >"$S/new.md"
mkdir "$D/.rotate.lock"; printf '999999 deadbeef\n' >"$D/.rotate.lock/pid"; touch -d '1 hour ago' "$D/.rotate.lock"
bash "$SCRIPT" after_stale --source "$S/new.md" --dir "$D" >"$S/o" 2>&1; rc=$?
[ "$rc" -eq 0 ] && cmp -s "$D/latest.md" "$S/new.md" && [ ! -e "$D/.rotate.lock" ] \
  && ok "stale legacy lock directory (dead owner) reclaimed, rotation done" || no "stale legacy lock rc=$rc: $(cat "$S/o")"
# a lock directory being created right now (no pid yet, young) is not stolen
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc young >"$S/new.md"; mkdir "$D/.rotate.lock"
bash "$SCRIPT" young_one --source "$S/new.md" --dir "$D" >"$S/o" 2>&1; rc=$?
[ "$rc" -eq 3 ] && [ -d "$D/.rotate.lock" ] && ! cmp -s "$D/latest.md" "$S/new.md" \
  && ok "young lock without a pid is not stolen (rc=3)" || no "young lock rc=$rc: $(cat "$S/o")"
# a FIFO or a symlink planted as the claim file is refused and never opened
for kind in fifo symlink; do
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc "$kind" >"$S/new.md"; mkdir "$D/.rotate.lock"
  if [ "$kind" = fifo ]; then mkfifo "$D/.rotate.lock/pid"; else ln -s "$S/victim" "$D/.rotate.lock/pid"; fi
  touch -d '1 hour ago' "$D/.rotate.lock"
  timeout 20 bash "$SCRIPT" "k_$kind" --source "$S/new.md" --dir "$D" >"$S/o" 2>&1; rc=$?
  [ "$rc" -eq 3 ] && [ ! -e "$S/victim" ] && ! cmp -s "$D/latest.md" "$S/new.md" \
    && ok "$kind planted as the lock's pid file: refused (rc=3), nothing written through it" || no "$kind pid file rc=$rc: $(cat "$S/o")"
done
# a run that passed its checks, then waited while another rotation finished, re-checks the
# history under the lock and refuses (no duplicate number, no stale target)
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc late_b >"$S/b.md"; prompt_doc first_a >"$S/a.md"
( ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=before_lock ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=3 \
    bash "$SCRIPT" late_b --source "$S/b.md" --dir "$D" >"$S/ob" 2>&1; echo $? >"$S/rcb" ) &
sleep 1; bash "$SCRIPT" first_a --source "$S/a.md" --dir "$D" >"$S/oa" 2>&1; rca=$?; wait
scan="$(ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 bash -c '. "$1"; rsp_scan_numbering "$2" 2>&1 && echo CLEAN' _ "$SCRIPT" "$D")"
[ "$rca" -eq 0 ] && [ "$(cat "$S/rcb")" -eq 3 ] && cmp -s "$D/latest.md" "$S/a.md" && [ ! -e "$D/03_late_b.md" ] \
  && grep -q '^CLEAN$' <<<"$scan" && [ ! -e "$D/.rotate.lock" ] \
  && ok "late run re-checks the history under the lock and refuses (rc=3), history gap-free" \
  || no "late run: a=$rca b=$(cat "$S/rcb") files=$(ls "$D" | tr '\n' ' ') out=$(cat "$S/ob")"
# unit: rsp_claim_lock itself never opens an existing pid (FIFO would block, symlink would
# write through) and creates it exactly once
S="$(mk_sandbox)"; mkdir "$S/lk"; mkfifo "$S/lk/pid"
timeout 10 env ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 bash -c '. "$1"; rsp_claim_lock "$2" id1' _ "$SCRIPT" "$S/lk"; rc=$?
[ "$rc" -eq 1 ] && ok "rsp_claim_lock refuses an existing FIFO pid without opening it (rc=1)" || no "rsp_claim_lock FIFO rc=$rc (124 = it opened and blocked)"
S="$(mk_sandbox)"; mkdir "$S/lk"; ln -s "$S/victim" "$S/lk/pid"
ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 bash -c '. "$1"; rsp_claim_lock "$2" id1' _ "$SCRIPT" "$S/lk"; rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$S/victim" ] && ok "rsp_claim_lock refuses a dangling symlink pid, nothing written through it" || no "rsp_claim_lock symlink rc=$rc victim=$([ -e "$S/victim" ] && echo written || echo absent)"
S="$(mk_sandbox)"
r1="$(ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 bash -c '. "$1"; rsp_claim_lock "$2" id1; echo $?' _ "$SCRIPT" "$S/lk")"
r2="$(ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 bash -c '. "$1"; rsp_claim_lock "$2" id2; echo $?' _ "$SCRIPT" "$S/lk")"
[ "$r1" = 0 ] && [ "$r2" = 1 ] && [ "$(cat "$S/lk/pid")" = id1 ] && ok "rsp_claim_lock: first claim wins, second refused, pid unchanged" || no "rsp_claim_lock sequential r1=$r1 r2=$r2 pid=$(cat "$S/lk/pid" 2>/dev/null)"
# deterministic exclusion: A and B both pass the pre-lock checks (paused at before_lock), both
# pass the claim's existence check; A creates pid first (B is still in the claim window) and
# holds the lock; B's create must then fail (O_EXCL), A completes alone
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc det_a >"$S/a.md"; prompt_doc det_b >"$S/b.md"
( ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT='before_lock claim_window after_lock' ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=1 \
    bash "$SCRIPT" det_a --source "$S/a.md" --dir "$D" >"$S/oa" 2>&1; echo $? >"$S/rca" ) &
sleep 0.3
( ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT='before_lock claim_window' ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=1 \
    bash "$SCRIPT" det_b --source "$S/b.md" --dir "$D" >"$S/ob" 2>&1; echo $? >"$S/rcb" ) &
wait
[ "$(cat "$S/rca")" = 0 ] && [ "$(cat "$S/rcb")" = 3 ] && cmp -s "$D/latest.md" "$S/a.md" && [ ! -e "$D/04_det_b.md" ] && [ ! -e "$D/03_det_b.md" ] && [ ! -e "$D/.rotate.lock" ] \
  && ok "deterministic: two runs inside the claim window, the second create fails (A=0, B=3)" \
  || no "deterministic claim: A=$(cat "$S/rca") B=$(cat "$S/rcb") files=$(ls -A "$D" | tr '\n' ' ') A:$(tail -n1 "$S/oa") B:$(tail -n1 "$S/ob")"
# the uutils failure mode made deterministic: a PATH shim whose mkdir never fails on an
# existing directory (like `mkdir -p`); B's mkdir "succeeds" while A holds the lock, and the
# lock must still exclude B
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc nx_a >"$S/a.md"; prompt_doc nx_b >"$S/b.md"
mkdir "$S/bin"; printf '#!/bin/sh\nexec "%s" -p "$@"\n' "$(command -v mkdir)" >"$S/bin/mkdir"; chmod +x "$S/bin/mkdir"
( PATH="$S/bin:$PATH" ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT='before_lock after_lock' ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=1 \
    bash "$SCRIPT" nx_a --source "$S/a.md" --dir "$D" >"$S/oa" 2>&1; echo $? >"$S/rca" ) &
sleep 0.3
( PATH="$S/bin:$PATH" ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=before_lock ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=1 \
    bash "$SCRIPT" nx_b --source "$S/b.md" --dir "$D" >"$S/ob" 2>&1; echo $? >"$S/rcb" ) &
wait
[ "$(cat "$S/rca")" = 0 ] && [ "$(cat "$S/rcb")" = 3 ] && cmp -s "$D/latest.md" "$S/a.md" && [ ! -e "$D/03_nx_b.md" ] && [ ! -e "$D/04_nx_b.md" ] \
  && ok "non-exclusive mkdir (shim): the lock still excludes the second run (A=0, B=3)" \
  || no "non-exclusive mkdir: A=$(cat "$S/rca") B=$(cat "$S/rcb") files=$(ls -A "$D" | tr '\n' ' ')"
# a symlink planted in the claim window (after the existence check, before the create) is
# detected after the create: the claim fails and the lock is not taken
S="$(mk_sandbox)"; mkdir "$S/lk"
( ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=claim_window ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=2 ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 \
    bash -c '. "$1"; rsp_claim_lock "$2" idX; echo $? >"$3"' _ "$SCRIPT" "$S/lk" "$S/rc" ) &
sleep 1; ln -s /dev/null "$S/lk/pid"; wait
[ "$(cat "$S/rc")" = 1 ] && ok "symlink planted inside the claim window: claim refused (rc=1)" || no "claim-window symlink: rc=$(cat "$S/rc")"
# documentation no longer claims that mkdir is atomic/exclusive
grep -qiE 'mkdir is atomic' "$SCRIPT" && no "the script still claims mkdir is atomic" || ok "no 'mkdir is atomic' claim in the script"
summary lock_race
