#!/bin/bash
# baseline_replay.sh - SC-002/SC-005 gate-replay harness (spec-004
# "fast-dev-cycles", User Story 1, T043; plan.md T-A10, T-H02;
# contracts/common-conventions.md C-001..C-007). Guarded by
# constitution/scripts/fastcycle/tests/test_baseline_replay_red.sh (T024).
#
# Purpose: given a sample item (or a select_sample.py output doc), FREEZE
# its "relevant work landed here" commit + tree hash, then REPLAY a
# caller-named gate command against an isolated checkout of that frozen
# commit, >=N times cold and >=N times warm, recording per-run timing +
# verdict + per-type medians -- the T-A10 "before" baseline every later
# SC-002 (gate speed) / SC-005 (cycle-time) claim in this initiative is
# measured against. This is an OPEN-GAP tool (contracts/common-
# conventions.md's own "Tool map" note lists "$FC/cycle/baseline_replay.sh
# (T-A10/T-H02)" among the tools no contract in that directory covers --
# "their interface, output and RED fixtures are fixed by the plan task
# text until a contract is written"); this script follows plan.md T-A10's
# own text plus C-001..C-007.
#
# =============================================================================
# FOUR SUBCOMMANDS
# =============================================================================
#   freeze --item ID [--repo-root DIR] [--db-path PATH] --out PATH
#       Resolve ID's frozen {commit, tree} via subject-only `git log`
#       search (see FREEZE MECHANISM below). Read-only, zero disk writes
#       beyond --out.
#   selfcheck --out PATH
#       C-004 control-needle self-test for THIS script's OWN verdict
#       classification (a real `true` MUST classify PASS, a real `false`
#       MUST classify FAIL) -- run automatically, inline, before every
#       `replay`; exposed standalone so a caller can verify the instrument
#       in isolation. Exit 3 on failure (C-001 row 3).
#   replay --commit SHA --tree SHA --gate-cmd "CMD..." [--cold-runs 10]
#       [--warm-runs 10] [--repo-root DIR] [--worktree-root DIR]
#       [--min-free-kb K] [--timeout-s N] --out PATH
#       Isolate a `git worktree` checkout of SHA (see DISK SAFETY below),
#       run CMD inside it cold-runs+warm-runs times sequentially, record
#       per-run {start_ns,end_ns,duration_ms,exit_code,verdict}, remove the
#       worktree (always, via trap), write the canonical report.
#   replay-sample --sample PATH --gate-cmd "CMD..." [--cold-runs 10]
#       [--warm-runs 10] [--repo-root DIR] [--worktree-root DIR]
#       [--min-free-kb K] [--timeout-s N] --out PATH
#       Read a select_sample.py (T043 sibling) output doc's `items` array;
#       for each, freeze then replay; an item whose freeze is UNMEASURED
#       is SKIPPED with the reason recorded (never silently dropped,
#       DEC-03's own "never silently dropped" language applied here);
#       aggregate per-type medians.
#
# =============================================================================
# FREEZE MECHANISM (design judgment call, documented per task instruction)
# =============================================================================
# "The exact commit the item's relevant work landed on" is resolved by
# reusing `$FC/cycle/cycle_report.py`'s (T041, already reviewed)
# `git_subject_matches()` definition VERBATIM, reimplemented here in shell:
# `git log --all -i --grep=<id> --pretty=format:%H|%aI|%cI|%s`, filtered in
# a second pass to lines whose SUBJECT (4th field, not the full message
# git --grep searches) literally contains the item id -- git's own --grep
# matches the full commit message, and a body-only mention is materially
# weaker evidence of "this IS the commit" than a subject mention (verified
# 2026-09-28 against this exact repo: `git log --all -i --grep=ATM-953`
# returns 3 commits, only 1 of which -- f1abb59e, subject "...ATM-953
# video-to-TV..." -- names ATM-953 in its subject; the other 2 are
# body-only mentions of an UNRELATED change). Of the surviving subject
# matches, the LATEST by author date is chosen (matches cycle_report.py's
# own `commit_push` stage END instant -- the commit that closed out the
# item's commit-push activity is the natural "landed here" point). Verified
# live 2026-09-28: ATM-953 -> commit f1abb59eac851e560a49b9fb4465297f84d66bae,
# tree 7160a3865cfeb4922f18530239921c2870d45185 (matches its own
# Fixed/2026-07-28 closure date exactly). Zero surviving subject matches ->
# UNMEASURED (exit 0 from `freeze`; the ABSENCE of a resolvable commit is
# an honest, correctly-recorded result, not an error -- matching
# cycle_report.py's own UNMEASURED-is-legitimate convention), never a
# silent fall-back to HEAD or any other guessed commit (S11.4.6).
#
# =============================================================================
# DISK SAFETY (a genuine host-safety finding made while designing this
# tool, documented in full because it changes the tool's own defaults --
# S11.4.6/S12.6)
# =============================================================================
# Two measurements taken directly against THIS host before writing this
# script's worktree-creation logic:
#   (1) `git worktree add` for THIS project materialises a FULL checkout of
#       every tracked file at the target commit. Measured directly against
#       one of this repo's OWN pre-existing agent worktrees
#       (.claude/worktrees/agent-a17eb3df7db2f148a, excluding its .git):
#       49 GB. This repo's root filesystem (/mnt/track1, mapper
#       track_crypt1) had 108 GB free at measurement time, with THREE such
#       worktrees already present (~147 GB already committed to them) --
#       creating a FOURTH full checkout for a mere bounded/representative
#       demonstration would be a real, avoidable host-disk-exhaustion risk
#       (S12.6), not a reasonable default for anything short of a genuine
#       T045 production run.
#   (2) `/tmp` on this host is `tmpfs` -- RAM-BACKED, not disk-backed --
#       measured at 126 GB total / 101 GB already used / 25 GB free at
#       measurement time. Defaulting `--worktree-root` under `/tmp` (a
#       tempting, "obviously scratch" choice) would therefore risk WRITING
#       A MULTI-GIGABYTE CHECKOUT INTO RAM, exactly the class of host-
#       session-safety disaster this project's own Constitution S12
#       documents multiple forensic OOM incidents about.
# Consequence for THIS script's defaults: `--worktree-root` defaults to
# `<repo-root>/.fc_worktrees` (a sibling of the EXISTING, already-
# precedented `.claude/worktrees/` pattern this exact repo already uses --
# `git worktree list` shows three such worktrees today -- confirmed
# disk-backed, same filesystem as the repo itself, NEVER tmpfs); a caller
# pointing `--worktree-root` at a known-disk-backed `/tmp` on a DIFFERENT
# host may still do so explicitly. `--min-free-kb` (default:
# DEFAULT_MIN_FREE_KB = 67 GiB = 70254592 KiB, derived from the two
# measurements this file documents -- ~49 GiB superproject checkout + ~7.4
# GiB submodules -- plus 10 GiB headroom; T048 restart round 1, R6-F10: the
# earlier 10 GiB default was five times smaller than the checkout it guards;
# operator-tunable for a different project) is checked
# via `df -Pk` against the worktree-root's OWN filesystem immediately
# before every `git worktree add`; insufficient free space REFUSES (exit
# 4, BLIND -- "could not measure", never a silent skip of the check) with
# the real `df` numbers printed, before any checkout is attempted.
#
# =============================================================================
# COLD vs WARM (honest boundary, S11.4.6 -- stated per task instruction)
# =============================================================================
# T-A10's own text: "replay ... >=10 times cold and >=10 times warm ...
# Token baseline...". Investigated 2026-09-28: `$FC/gates/verdict_cache.py`
# (T068, the ONLY app-level caching mechanism plan.md names anywhere in
# this initiative) does NOT exist in this tree yet (US2, a LATER user
# story). With no cache mechanism to warm, this script's `cold` and `warm`
# phases are, RIGHT NOW, mechanically IDENTICAL operations (same gate
# command, same frozen worktree, run sequentially) -- the only difference
# either phase could exhibit today is the OS's own filesystem page cache,
# which this script does NOT attempt to control (no `posix_fadvise`/cache-
# drop step) since doing so would need root and is out of this task's
# scope. This is recorded HONESTLY in every `replay`/`replay-sample`
# report's `cache_mechanism` field rather than silently pretending a real
# distinction exists. Once T068 lands, `--gate-cmd` (or a companion
# `--warm-cmd`) is this script's existing hook point for a real cache-
# warm-up step -- no interface change needed then.
#
# =============================================================================
# EXIT CODES (C-001's uniform table)
# =============================================================================
# 0 report written (a per-run gate FAIL is recorded DATA, not a harness
#   exit-code failure -- this script measures gate outcomes, it does not
#   itself judge them); 1 `--determinism-check` genuinely differs -- the
#   two internal re-runs of the SAME frozen {commit, tree, gate-cmd} this
#   script itself performs (C-003; NOT a delegation to fc_common.py's
#   generic byte-identical wrapper -- see DETERMINISM below) produced
#   different `verdict_set`s, a real determinism defect (S11.4.50); 2
#   usage/config error; 3 selfcheck (C-004 control needle) failed -- the
#   verdict-classification instrument is not trustworthy this run,
#   nothing else runs; 4 BLIND -- git failed or commit/tree unresolvable,
#   worktree/submodule creation failed, disk pre-flight refused, tracker DB
#   present but unreadable, a gate run that could not be STARTED
#   (HARNESS_ERROR; the report is still written), any replay-sample item that
#   could not be measured for a harness reason (report still written), or
#   --determinism-check runs that never completed (deterministic=null).
#   Verdicts per run (closed set): PASS | FAIL | UNMEASURED | HARNESS_ERROR,
#   see classify_run(); median_ms is over PASS runs only (R6-F9).
#
# =============================================================================
# DETERMINISM (C-003; T024 RED-test contract stub 1/3) -- HONEST BOUNDARY,
# a real design correction made after directly testing the first draft
# =============================================================================
# `replay`'s report embeds REAL wall-clock measurements (start_ns/end_ns/
# duration_ms/median_ms) inside its hashed body -- that data is
# INHERENTLY non-deterministic between two separate invocations (real
# timing jitter always differs), so this tool does NOT compose with
# fc_common.py's generic byte-identical-`body_hash` `determinism-check`
# the way cycle_report.py / select_sample.py's own timing-free bodies
# correctly do -- verified directly: an earlier draft that DID delegate
# to the generic mechanism reported "nondeterministic" on its very first
# real run against a real scratch repo (2026-09-28), even though nothing
# was actually wrong. T024's own RED-test contract stub 1/3 already says
# what THIS tool's determinism means: "two independent invocations ...
# MUST produce the SAME verdict SET (per-item PASS/FAIL/SKIP
# classification, compared as a set, never merely as equal counts)".
# `replay --determinism-check` therefore runs the SAME frozen
# {commit, tree, gate-cmd} TWICE internally and compares ONLY the two
# runs' `verdict_set` fields (never the timing fields); exit 0 = both
# invocations give one identical verdict per phase, exit 1 = genuinely
# differs (a real determinism defect, S11.4.50) -- including a phase whose
# verdict set holds MORE than one verdict inside a single invocation (a
# within-run flake, T048 restart round 1 R6-F7), exit 4 = some run never
# completed or never started (no determinism verdict, deterministic=null);
# zero runs are refused (exit 2). Both verdict sets are printed either way
# AND (as of T043 round-2 review finding N5) writing the same
# `baseline-replay-determinism/v1` document to the mandatory `--out`
# PATH every other subcommand already writes to.
#
# =============================================================================
# SAFETY (C-006)
# =============================================================================
# Read-only on the CALLER's live working tree at all times: every
# checkout happens in an isolated `git worktree`, never `git checkout`/
# `reset`/`stash`/`clean` against the repo the caller invoked this script
# from. Worktree cleanup (`git worktree remove --force`, needed because
# the replayed gate may leave scratch files inside its own checkout) is
# unconditional (bash `trap ... EXIT` plus explicit HUP/INT/QUIT/TERM
# handlers) and FIRST stops the running gate / submodule process group
# (_fc_kill_child, §11.4.263-guarded) -- this script never leaves an orphan
# worktree or an orphan gate run behind, matching S11.4.14 (leave the target
# quiescent). T048 restart round 1 (R6-F11): stopping the main script used to
# leave every remaining scheduled gate run going as an orphan.
#
# HONEST BOUNDARY (S11.4.6): `--gate-cmd "CMD..."` is a single string this
# script word-splits on whitespace (parse_gate_cmd: `read -r -a`, with NO
# pathname expansion -- T048 restart round 1 replaced the earlier unquoted
# expansions, which also glob-expanded each word) into an argv array before
# exec'ing it -- CMD and every one of its own arguments MUST NOT contain
# embedded whitespace (e.g. a path with a space in it). This is a real,
# stated limitation, not a silent one; every sibling $FC tool that accepts
# a shell command string (this is the first) will need the same note or a
# genuine array-CLI redesign once a caller hits it.
#
# Dependencies: bash (arrays), git, python3 (stdlib only -- JSON assembly
# + fc_common's canon/body_hash_of, matching every sibling $FC tool),
# coreutils `date`/`df`/`timeout`.
set -u

# --- resolve this script's own directory, independent of caller's cwd ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_REPO_ROOT="$(cd "$FC/../../.." && pwd)"

die() { echo "baseline_replay: $*" >&2; exit 2; }
blind() { echo "baseline_replay: BLIND: $*" >&2; exit 4; }

isnum() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }

usage() {
  cat >&2 <<'EOF'
Usage:
  baseline_replay.sh freeze --item ID [--repo-root DIR] [--db-path PATH] --out PATH
  baseline_replay.sh selfcheck --out PATH
  baseline_replay.sh replay --commit SHA --tree SHA --gate-cmd "CMD..."
      [--cold-runs N] [--warm-runs N] [--repo-root DIR] [--worktree-root DIR]
      [--min-free-kb K] [--timeout-s N] --out PATH [--determinism-check]
  baseline_replay.sh replay-sample --sample PATH --gate-cmd "CMD..."
      [--cold-runs N] [--warm-runs N] [--repo-root DIR] [--worktree-root DIR]
      [--min-free-kb K] [--timeout-s N] --out PATH
EOF
  exit 2
}

[ $# -ge 1 ] || usage
SUBCMD=$1; shift

# ---------------------------------------------------------------------------
# now_ns -- date +%s%N, validated all-decimal (matches fc_timer.sh's own
# _fc_timer_now_ns convention exactly, for cross-tool consistency).
# ---------------------------------------------------------------------------
now_ns() {
  local ns
  ns="$(date +%s%N 2>/dev/null)" || { echo "baseline_replay: 'date +%s%N' failed" >&2; return 2; }
  case "$ns" in ''|*[!0-9]*) echo "baseline_replay: 'date +%s%N' produced a non-numeric timestamp ('$ns') -- needs GNU date" >&2; return 2 ;; esac
  printf '%s' "$ns"
}

# ---------------------------------------------------------------------------
# Disk floor default (T048 restart round 1, R6-F10). The DISK SAFETY section
# above and the submodule comment in do_one_replay() document a full checkout of
# this project at ~49 GiB plus ~7.4 GiB of submodules. The earlier 10 GiB
# default was 5x below that, so the check passed with far too little room and
# the checkout itself could exhaust the disk. Derivation: 49 GiB + 8 GiB
# (7.4 rounded up) + 10 GiB headroom = 67 GiB = 67 * 1048576 KiB. Still a
# caller-tunable flag: a different project passes its own measured size.
# ---------------------------------------------------------------------------
DEFAULT_MIN_FREE_KB=70254592

# ---------------------------------------------------------------------------
# Child-process tracking (T048 restart round 1, R6-F11). Every long-running
# child this script starts (a gate run, the submodule update) is launched as
# `timeout ... &`. GNU timeout (without --foreground) puts itself in a NEW
# process group whose id is its own pid, and the command it runs stays in that
# group, so `$!` is both the timeout pid and the group id. _FC_CHILD_PGID holds
# it while the child runs (a GLOBAL, never a function local: a signal handler
# can fire after the launching function's locals are gone). _FC_REPLAY_PID is the
# background subshell that runs do_one_replay() (see run_replay_isolated()).
# ---------------------------------------------------------------------------
_FC_CHILD_PGID=""
_FC_REPLAY_PID=""

# _fc_kill_child: stop the tracked child group, if any, and reap it.
# §11.4.263: the id is used only when it is a decimal integer > 1 -- never 0, 1,
# empty or anything a mock/default could produce (kill -- -1 would signal every
# process of this user). TERM goes to the whole group first; timeout itself
# answers TERM by escalating to KILL after its own --kill-after (5 s), and a
# 10 s watchdog sends KILL to the group if even that does not happen. The
# watchdog's output is sent to /dev/null and it is not run inside a command
# substitution, so its orphaned `sleep` can never hold a pipe open (the
# shell-instrument footgun recorded under §11.4.201(12)).
_fc_kill_child() {
  local pg="${_FC_CHILD_PGID:-}"
  _FC_CHILD_PGID=""
  case "$pg" in ''|*[!0-9]*) return 0 ;; esac
  [ "$pg" -gt 1 ] || return 0
  kill -s TERM -- "-$pg" 2>/dev/null || kill -s TERM "$pg" 2>/dev/null
  ( sleep 10; kill -s KILL -- "-$pg" 2>/dev/null ) >/dev/null 2>&1 &
  local dog=$!
  wait "$pg" 2>/dev/null
  kill -s KILL "$dog" 2>/dev/null
  # Final sweep for anything left in the group (a gate child that ignored TERM
  # after timeout itself was killed). Harmless when the group is already empty.
  kill -s KILL -- "-$pg" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Verdicts (closed set, T048 restart round 1, R6-F8):
#   PASS          the gate ran and exited 0
#   FAIL          the gate ran and exited non-zero (including its OWN 124/126/127)
#   UNMEASURED    the gate did not finish: killed by --timeout-s, or by a signal
#   HARNESS_ERROR the gate never ran: cd into the worktree failed, the command was
#                 not found / not executable (exec failed), or timeout(1) itself
#                 failed (exit 125)
# The earlier rule "rc 0 = PASS, anything else = FAIL" recorded a missing or
# non-executable gate as a real gate FAIL with a real-looking median (the live
# 126-in-6 ms case documented in collect_baseline.py) -- a §11.4.1 FAIL-bluff.
# Whether the gate ran is now OBSERVED, not inferred from the exit code: the
# launcher `exec`s the gate with `shopt -s execfail`, so a failed exec returns
# to the launcher, which writes a marker file before exiting.
#
# classify_run RC MARKER DURATION_MS TIMEOUT_MS -> prints "VERDICT|reason"
# A 124/137 counts as a timeout ONLY when the run lasted at least the timeout;
# a gate that itself exits 124 quickly is a genuine FAIL.
# ---------------------------------------------------------------------------
classify_run() {
  local rc="$1" mk="$2" dur="$3" tmo_ms="$4"
  case "$mk" in
    cd_failed|exec_failed) printf 'HARNESS_ERROR|%s' "$mk"; return 0 ;;
  esac
  if [ "$rc" = 125 ]; then printf 'HARNESS_ERROR|timeout(1) itself failed (exit 125)'; return 0; fi
  if { [ "$rc" = 124 ] || [ "$rc" = 137 ]; } && [ "$dur" -ge "$tmo_ms" ]; then
    printf 'UNMEASURED|timed out (exit %s after %sms, limit %sms)' "$rc" "$dur" "$tmo_ms"; return 0
  fi
  if [ "$rc" -ge 129 ]; then printf 'UNMEASURED|terminated by signal %s' "$((rc - 128))"; return 0; fi
  if [ "$rc" = 0 ]; then printf 'PASS|exit 0'; else printf 'FAIL|exit %s' "$rc"; fi
}

# ---------------------------------------------------------------------------
# run_gate_once CWD TIMEOUT_S LOG -- CMD...
# Runs CMD once inside CWD, bounded by TIMEOUT_S, stdout+stderr to LOG, and sets
# RG_START_NS RG_END_NS RG_DURATION_MS RG_RC RG_VERDICT RG_REASON. Returns 4 only
# when the clock or a temp file cannot be obtained (BLIND).
#
# T043 round-4 finding B1 (kept): the gate is BACKGROUNDED and `wait`ed on, never
# run as a foreground command, because bash defers a trapped signal until a
# foreground command finishes; `wait` returns as soon as a trapped signal
# arrives, so the HUP/QUIT/INT/TERM handlers run promptly.
# T048 restart round 1 (R6-F11): the backgrounded command is `timeout` itself
# (no wrapping subshell), so `$!` is the gate's process GROUP and the signal
# handlers can stop the gate, not only the shell around it.
# ---------------------------------------------------------------------------
run_gate_once() {
  local cwd="$1" tmo="$2" log="$3"
  shift 3
  [ "${1:-}" = -- ] && shift
  local marker
  marker="$(mktemp)" || { echo "baseline_replay: mktemp failed (TMPDIR unusable)" >&2; return 4; }
  RG_START_NS="$(now_ns)" || { rm -f "$marker"; return 4; }
  # shellcheck disable=SC2016 # $1/$2/$@ expand in the launcher bash, not here
  timeout --kill-after=5 "${tmo}s" "$BASH" -c '
m=$1
cd -- "$2" || { printf cd_failed >"$m"; exit 127; }
shift 2
shopt -s execfail
exec "$@"
printf exec_failed >"$m"
exit 127' fc-gate "$marker" "$cwd" "$@" >"$log" 2>&1 </dev/null &
  _FC_CHILD_PGID=$!
  wait "$_FC_CHILD_PGID"
  RG_RC=$?
  _FC_CHILD_PGID=""
  RG_END_NS="$(now_ns)" || { rm -f "$marker"; return 4; }
  RG_DURATION_MS=$(( (RG_END_NS - RG_START_NS) / 1000000 ))
  [ "$RG_DURATION_MS" -ge 0 ] || RG_DURATION_MS=0
  local mk=""
  [ -s "$marker" ] && mk="$(cat "$marker")"
  rm -f "$marker"
  local cls
  cls="$(classify_run "$RG_RC" "$mk" "$RG_DURATION_MS" "$((tmo * 1000))")"
  RG_VERDICT="${cls%%|*}"
  RG_REASON="${cls#*|}"
  return 0
}

# ---------------------------------------------------------------------------
# selfcheck: C-004 control needle for the verdict instrument. T048 restart
# round 1 (R6-F20): it used to round-trip only the pure classifier on the exit
# codes of `true`/`false`, so the real run path (background launch, timeout,
# exec-failure detection) -- where F8 lived -- was never exercised. It now runs
# REAL gates through run_gate_once() and checks each verdict:
#   true -> PASS; false -> FAIL; a command that exits 127 itself -> FAIL;
#   a command that does not exist -> HARNESS_ERROR; `sleep 5` under a 1 s
#   timeout -> UNMEASURED.
# Sets SC_CHECKS (one "name|ok|got|want" line per check); returns 0 iff all ok.
# ---------------------------------------------------------------------------
run_selfcheck() {
  SC_CHECKS=""
  local d all_ok=1
  d="$(mktemp -d)" || { echo "baseline_replay: selfcheck: mktemp -d failed" >&2; return 1; }
  _sc_one() { # name want timeout cmd...
    local name="$1" want="$2" tmo="$3"
    shift 3
    if ! run_gate_once "$d" "$tmo" "$d/$name.log" -- "$@"; then
      SC_CHECKS="${SC_CHECKS}${name}|false|BLIND|${want}"$'\n'; all_ok=0; return
    fi
    if [ "$RG_VERDICT" = "$want" ]; then
      SC_CHECKS="${SC_CHECKS}${name}|true|${RG_VERDICT}|${want}"$'\n'
    else
      SC_CHECKS="${SC_CHECKS}${name}|false|${RG_VERDICT}|${want}"$'\n'
      echo "baseline_replay: selfcheck FAILED: $name classified $RG_VERDICT ($RG_REASON), expected $want" >&2
      all_ok=0
    fi
  }
  _sc_one true_pass PASS 30 true
  _sc_one false_fail FAIL 30 false
  _sc_one own_exit_127_fail FAIL 30 "$BASH" -c 'exit 127'
  _sc_one exec_failure_harness_error HARNESS_ERROR 30 fc-selfcheck-no-such-command-6b1f
  _sc_one timeout_unmeasured UNMEASURED 1 sleep 5
  rm -rf "$d"
  unset -f _sc_one
  [ "$all_ok" = 1 ]
}

# ---------------------------------------------------------------------------
# git_subject_freeze REPO_ROOT ITEM_ID
# Sets FZ_SHA FZ_TREE FZ_ADATE FZ_SUBJECT FZ_COUNT (FZ_SHA=UNMEASURED when no
# subject matches) and returns 0; returns 4 with FZ_ERR set when git itself
# fails. Runs in the CALLER's shell (never inside $(...)) so the globals survive.
#
# T048 restart round 1 fixes:
#  - R6-F3: `git log ... 2>/dev/null || raw=""` turned "not a repository", "git
#    missing" or a corrupt repo into "no commit found" with exit 0. Now the repo
#    is checked first and a failing git log / rev-parse is BLIND (exit 4). Only a
#    SUCCESSFUL git log with no subject match is UNMEASURED.
#  - R6-F4: "latest by author date" compared %aI STRINGS, which order wrongly
#    across timezone offsets (12:00+05:00 = 07:00Z sorts after 09:00+00:00). It
#    now compares %at (epoch seconds). On an exact tie the commit git log lists
#    first (the most recently committed) is kept.
#  - R6-F19: the old `for line in $raw` loop word-split AND pathname-expanded
#    every line; it is now a `read -r` loop over a here-string (no globbing).
#  - `--grep` is given `-F`: the item id is a literal string, never a regex.
# ---------------------------------------------------------------------------
git_subject_freeze() {
  local root="$1" item_id="$2"
  FZ_SHA=UNMEASURED; FZ_TREE=UNMEASURED; FZ_ADATE=""; FZ_SUBJECT=""; FZ_COUNT=0; FZ_ERR=""
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    FZ_ERR="not a git repository (or git unavailable): $root"
    return 4
  fi
  local errf raw rc
  errf="$(mktemp)" || { FZ_ERR="mktemp failed"; return 4; }
  raw="$(git -C "$root" log --all -i -F --grep="$item_id" --pretty=format:'%H%x1f%at%x1f%aI%x1f%s' 2>"$errf")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    FZ_ERR="git log failed (exit $rc): $(head -c 500 "$errf")"
    rm -f "$errf"
    return 4
  fi
  rm -f "$errf"
  # T043 round-4 finding B2 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # a plain substring case-match (`*"$item_id"*`) makes ATM-95 match
  # ATM-953, ATM-103 match ATM-1038, etc. -- reproduced on this project's
  # own real history: `--item ATM-103` silently froze commit fd5585c7's
  # "...ATM-1038 option b" subject with exit 0, no BLIND, no warning.
  # This is exactly the "silent fall-back to any other guessed commit"
  # §11.4.6 forbids. Fixed with a token-boundary regex: the item id must
  # be bounded by a non-alnum-non-hyphen char (or string start) on the
  # left and a non-digit char (or string end) on the right, so ATM-103
  # can never match inside ATM-1038 or ATM-953.
  local item_re
  item_re="$(printf '%s' "$item_id" | sed 's/[][\.^$*+?(){}|]/\\&/g')"
  local best_at="" sha at adate subject
  while IFS=$'\x1f' read -r sha at adate subject; do
    [ -n "$sha" ] || continue
    if ! isnum "$at"; then
      FZ_ERR="git log returned a non-numeric author timestamp '$at' for $sha"
      return 4
    fi
    if [[ "$subject" =~ (^|[^A-Za-z0-9-])${item_re}([^0-9]|$) ]]; then
      FZ_COUNT=$((FZ_COUNT + 1))
      if [ -z "$best_at" ] || [ "$at" -gt "$best_at" ]; then
        best_at="$at"; FZ_SHA="$sha"; FZ_ADATE="$adate"; FZ_SUBJECT="$subject"
      fi
    fi
  done <<<"$raw"
  [ "$FZ_SHA" = UNMEASURED ] && return 0
  FZ_TREE="$(git -C "$root" rev-parse --verify --quiet "${FZ_SHA}^{tree}" 2>/dev/null)"
  if [ -z "$FZ_TREE" ]; then
    FZ_ERR="cannot resolve the tree of $FZ_SHA (corrupt or partial object store)"
    FZ_TREE=UNMEASURED
    return 4
  fi
  return 0
}

# ---------------------------------------------------------------------------
# emit_doc schema body_json out_path -- via fc_common.py (C-002).
# T048 restart round 1 (R6-F12): emit_doc no longer reads FC_OUT. FC_OUT (set by
# fc_common.py determinism-check) is honoured ONCE, at the top level, for the
# subcommand's own --out (see the dispatch at the end of this file); before, every
# internal emit honoured it, so replay-sample's internal per-item freeze wrote
# into the caller's FC_OUT instead of its own temp file and every item was then
# recorded as a harness error with exit 0.
# ---------------------------------------------------------------------------
emit_doc() {
  local schema="$1" body_json="$2" out_path="$3"
  mkdir -p "$(dirname "$out_path")" 2>/dev/null
  local run_meta
  run_meta="$(python3 -c 'import json,platform; print(json.dumps({"host": platform.node()}))')"
  python3 "$FC/lib/fc_common.py" emit --schema "$schema" --body-json "$body_json" \
    --run-meta-json "$run_meta" --out "$out_path"
  return $?
}

# ---------------------------------------------------------------------------
# freeze_to_body ITEM REPO_ROOT DB_PATH -> sets FZ_BODY (JSON) and returns 0, or
# prints the reason and returns 4 (BLIND). T048 restart round 1 (R6-F5): every
# value reaches Python through argv (a quoted heredoc is the program text), never
# spliced into Python source -- a subject containing `\N` used to be a Python
# SyntaxError (exit 2) and `\t` was silently turned into a TAB.
# ---------------------------------------------------------------------------
freeze_to_body() {
  local item="$1" repo_root="$2" db_path="$3"
  local item_type="UNKNOWN" item_type_note=""
  if [ -f "$db_path" ]; then
    # An existing but unreadable tracker DB is BLIND (header EXIT CODES row 4),
    # never silently UNKNOWN; an item simply absent from a readable DB is UNKNOWN.
    item_type="$(python3 - "$db_path" "$item" <<'PY' 2>/dev/null
import sqlite3, sys
try:
    conn = sqlite3.connect('file:%s?mode=ro' % sys.argv[1], uri=True)
    row = conn.execute('SELECT type FROM items WHERE atm_id = ? LIMIT 1', (sys.argv[2],)).fetchone()
except Exception:
    sys.exit(4)
print(row[0] if row else 'UNKNOWN')
PY
)" || { echo "baseline_replay: BLIND: tracker DB $db_path exists but cannot be read" >&2; return 4; }
  else
    item_type_note="tracker DB not present at $db_path"
  fi
  if ! git_subject_freeze "$repo_root" "$item"; then
    echo "baseline_replay: BLIND: freeze $item: $FZ_ERR" >&2
    return 4
  fi
  FZ_BODY="$(python3 - "$item" "$item_type" "$item_type_note" "$FZ_SHA" "$FZ_TREE" "$FZ_ADATE" \
      "$FZ_SUBJECT" "$FZ_COUNT" "$repo_root" <<'PY'
import json, sys
item, itype, inote, sha, tree, adate, subject, count, root = sys.argv[1:10]
body = {"item_id": item, "item_type": itype, "candidate_commit_count": int(count)}
if inote:
    body["item_type_note"] = inote
if sha == "UNMEASURED":
    body.update(commit="UNMEASURED", tree="UNMEASURED",
                missing_instrument="no git log commit whose SUBJECT line references %s was found "
                                   "under --all (repo_root=%s)" % (item, root))
else:
    body.update(commit=sha, tree=tree, commit_author_date=adate, commit_subject=subject)
print(json.dumps(body))
PY
)" || { echo "baseline_replay: BLIND: cannot assemble the freeze body for $item" >&2; return 4; }
  return 0
}

# =============================================================================
# freeze
# =============================================================================
cmd_freeze() {
  local item="" repo_root="" db_path="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --item) [ $# -ge 2 ] || die "freeze: --item needs a value"; item="$2"; shift 2 ;;
      --repo-root) [ $# -ge 2 ] || die "freeze: --repo-root needs a value"; repo_root="$2"; shift 2 ;;
      --db-path) [ $# -ge 2 ] || die "freeze: --db-path needs a value"; db_path="$2"; shift 2 ;;
      --out) [ $# -ge 2 ] || die "freeze: --out needs a value"; out="$2"; shift 2 ;;
      *) die "freeze: unknown argument: $1" ;;
    esac
  done
  [ -n "$item" ] || die "freeze: --item is required"
  case "$item" in *$'\n'*|*$'\r'*) die "freeze: --item must be a single line" ;; esac
  [ -n "$out" ] || die "freeze: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$db_path" ] || db_path="$repo_root/docs/workable_items.db"
  freeze_to_body "$item" "$repo_root" "$db_path" || return 4
  emit_doc "baseline-replay-freeze/v1" "$FZ_BODY" "$out"
}

# =============================================================================
# selfcheck
# =============================================================================
cmd_selfcheck() {
  local out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) [ $# -ge 2 ] || die "selfcheck: --out needs a value"; out="$2"; shift 2 ;;
      *) die "selfcheck: unknown argument: $1" ;;
    esac
  done
  [ -n "$out" ] || die "selfcheck: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  command -v timeout >/dev/null 2>&1 || blind "timeout(1) not found -- cannot bound a gate run"
  local sc_rc=0
  run_selfcheck || sc_rc=3
  local body
  body="$(python3 - "$SC_CHECKS" "$sc_rc" <<'PY'
import json, sys
checks = []
for line in sys.argv[1].splitlines():
    if not line:
        continue
    name, ok, got, want = line.split("|", 3)
    checks.append({"name": name, "ok": ok == "true", "got": got, "want": want})
print(json.dumps({"result": "ok" if sys.argv[2] == "0" else "FAILED", "checks": checks}))
PY
)"
  [ "$sc_rc" = 0 ] || return 3
  emit_doc "baseline-replay-selfcheck/v1" "$body" "$out"
}

# =============================================================================
# _fc_submodule_reference_update SRC TGT
#   T048 round-3 review finding R3-B1 fix (2026-09-30): the round-2
#   `--reference "$repo_root"` invocation was proven, by live measurement
#   (git 2.50.1, file:// transport, see the comment above the call site
#   below for the exact numbers), to be a NO-OP for object reuse -- a
#   single `--reference <path>` passed to `git submodule update` is
#   handed to git-clone(1) VERBATIM for EVERY submodule being cloned; it
#   is NEVER expanded to `<path>/.git/modules/<name>` per submodule (that
#   round-2 claim was independently re-tested this dispatch and is FALSE
#   for this codepath -- see below). Registering the SUPERPROJECT's own
#   `.git/objects` as an alternate buys nothing, because a submodule's
#   blobs/trees/commits were never stored there in the first place; they
#   live at `<repo>/.git/modules/<name>/objects`, a COMPLETELY SEPARATE
#   object store one directory level down. (git DOES have a genuine
#   feature for automatic per-submodule alternate resolution --
#   `-c submodule.alternateLocation=superproject` -- but it is wired only
#   into the `git clone --recurse-submodules --reference <path>`
#   codepath; re-tested live this dispatch with THIS git version and
#   confirmed it has NO effect on a `git submodule update --init
#   --recursive --reference <path>` call against an ALREADY-EXISTING
#   checkout, which is what a `git worktree add`-based replay needs, so
#   it cannot be used here.)
#
#   This function does manually what `--reference` alone does not:
#   submodule-BY-submodule, computing THAT submodule's own already-
#   fetched object store under SRC's git-common-dir (`git -C "$SRC"
#   rev-parse --git-common-dir` -- resolves correctly even when $SRC is
#   ITSELF a linked worktree of some other checkout, since
#   `--git-common-dir` always resolves to the shared repo, never a
#   per-worktree path; verified live) and passing THAT specific path as
#   `--reference` for a single-submodule `git submodule update --init --
#   <path>` call. It then RECURSES into any submodule that itself
#   declares a `.gitmodules` (a nested submodule), using SRC/<path> --
#   the corresponding already-checked-out submodule directory inside
#   SRC -- as the new source: a nested submodule's own object store
#   lives at `<parent's-git-common-dir>/modules/<nested-name>`, which
#   `git -C "$SRC/<path>" rev-parse --git-common-dir` resolves to
#   directly (verified live against a real 2-level-nested scratch
#   fixture: 0 objects transferred at BOTH the top-level AND the nested
#   level).
#
#   Degrades safely per submodule, independently: a submodule SRC has
#   never fetched (its `.git/modules/<name>` does not exist under SRC's
#   git-common-dir) gets NO `--reference` flag at all and falls through
#   to a normal network clone for THAT submodule only -- verified live,
#   exit 0, unaffected. A submodule whose remote is genuinely
#   unreachable still correctly fails non-zero regardless of whether a
#   `--reference` was supplied (verified live: --reference never removes
#   the need to negotiate refs with the remote; it only avoids
#   re-transferring objects the remote and the reference already agree
#   on) -- so this function preserves the exact "refuse to run gate_cmd
#   against a partially-checked-out tree" semantics the caller below
#   already depends on.
#
#   TGT is the linked worktree checkout ($wt_path) whose OWN
#   .gitmodules (at the frozen commit) is walked; SRC is the tree to
#   borrow already-fetched submodule objects from (initially $repo_root,
#   then recursively SRC's own corresponding submodule directory).
#   Returns the first non-zero exit encountered (or 0).
# =============================================================================
# invoked indirectly: exported with export -f and run via bash -c in a child shell below
# shellcheck disable=SC2329
_fc_submodule_reference_update() {
  local src="$1" tgt="$2"
  [ -f "$tgt/.gitmodules" ] || return 0

  local src_common=""
  src_common="$(git -C "$src" rev-parse --git-common-dir 2>/dev/null)" || src_common=""
  if [ -n "$src_common" ]; then
    case "$src_common" in
      /*) : ;;
      *) src_common="$(cd "$src" 2>/dev/null && cd "$src_common" 2>/dev/null && pwd)" || src_common="" ;;
    esac
  fi

  local list_file
  list_file="$(mktemp)" || return 1
  git -C "$tgt" config -f .gitmodules --get-regexp '^submodule\..*\.path$' >"$list_file" 2>/dev/null

  local key path name ref_path rc=0
  # false positive: the loop only READS list_file via the redirect; rm -f merely unlinks it on early return, nothing is written through the pipeline
  # shellcheck disable=SC2094
  while IFS=' ' read -r key path; do
    [ -n "$key" ] || continue
    name="${key#submodule.}"
    name="${name%.path}"
    ref_path=""
    if [ -n "$src_common" ] && [ -d "$src_common/modules/$name" ]; then
      ref_path="$src_common/modules/$name"
    fi
    # T048 restart round 1 (R6-F15): `-c protocol.file.allow=never` alone does
    # NOT hold against the environment -- measured: `GIT_ALLOW_PROTOCOL=file git
    # -c protocol.file.allow=never submodule update --init` cloned a file://
    # submodule (rc=0), because GIT_ALLOW_PROTOCOL, when set, REPLACES the whole
    # protocol.*.allow policy. The env vars that can re-open a protocol are
    # removed for this one call (never touching the caller's own environment).
    if [ -n "$ref_path" ]; then
      env -u GIT_ALLOW_PROTOCOL -u GIT_PROTOCOL_FROM_USER -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
        git -c protocol.ext.allow=never -c protocol.file.allow=never \
        -C "$tgt" submodule update --init --quiet --reference "$ref_path" -- "$path"
    else
      env -u GIT_ALLOW_PROTOCOL -u GIT_PROTOCOL_FROM_USER -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
        git -c protocol.ext.allow=never -c protocol.file.allow=never \
        -C "$tgt" submodule update --init --quiet -- "$path"
    fi
    rc=$?
    [ "$rc" -eq 0 ] || { rm -f "$list_file"; return "$rc"; }

    if [ -f "$tgt/$path/.gitmodules" ]; then
      _fc_submodule_reference_update "$src/$path" "$tgt/$path"
      rc=$?
      [ "$rc" -eq 0 ] || { rm -f "$list_file"; return "$rc"; }
    fi
  done <"$list_file"
  rm -f "$list_file"
  return 0
}

# =============================================================================
# One frozen-commit replay: creates+removes exactly one worktree, runs
# gate_cmd cold_runs+warm_runs times inside it. Prints the JSON body on
# stdout (caller decides schema/out). Returns 0 on a successfully-measured
# run (gate PASS/FAIL is data, not a harness failure), 4 on BLIND.
# =============================================================================
# printf %q pre-quotes the values into the trap string on purpose: it must expand NOW (repo_root/wt_path are function locals, out of scope when the trap fires) and %q makes it safe; function-level on purpose: a directive between the printf and the trap line would break the worktree-cleanup mutation tests' exact-text anchors
# shellcheck disable=SC2064
do_one_replay() {
  local commit="$1" tree="$2" repo_root="$3" worktree_root="$4" min_free_kb="$5"
  local timeout_s="$6" cold_runs="$7" warm_runs="$8"
  shift 8
  local gate_cmd=("$@")

  [ ${#gate_cmd[@]} -ge 1 ] || { echo "baseline_replay: replay: --gate-cmd must be non-empty" >&2; return 4; }

  mkdir -p "$worktree_root" 2>/dev/null || { echo "baseline_replay: cannot create --worktree-root $worktree_root" >&2; return 4; }
  local free_kb
  free_kb="$(df -Pk "$worktree_root" 2>/dev/null | awk 'NR==2{print $4}')"
  isnum "$free_kb" || { echo "baseline_replay: cannot read free disk space for $worktree_root (df failed)" >&2; return 4; }
  if [ "$free_kb" -lt "$min_free_kb" ]; then
    echo "baseline_replay: BLIND: insufficient free disk at $worktree_root: ${free_kb}KB available, ${min_free_kb}KB required (--min-free-kb) -- refusing to create a worktree checkout" >&2
    return 4
  fi

  local wt_path
  wt_path="$(mktemp -d "$worktree_root/replay.XXXXXX")" || { echo "baseline_replay: mktemp -d under $worktree_root failed" >&2; return 4; }
  rmdir "$wt_path" 2>/dev/null  # git worktree add requires the target NOT already exist

  # `cleanup()` is invoked via the EXIT trap on EVERY path out of this
  # function, including every early `return 4` BELOW THIS POINT (i.e.
  # every `return 4` between this comment and the explicit `cleanup
  # "$repo_root" "$wt_path"; trap - EXIT` success-path call further down
  # this same function -- a SYMBOLIC reference, not a line-number literal,
  # deliberately: a hardcoded citation here drifted stale once already
  # (T043 round-3 review finding F2, 2026-09-28 -- an earlier version of
  # this comment cited specific line numbers that were already wrong by
  # the time of that review, off by exactly the number of lines an
  # UNRELATED later edit to this same function had since added; a
  # symbolic "below this point, until the explicit cleanup call" reference
  # cannot go stale the same way). bash pops a function's
  # `local` bindings as part of `return`, but the EXIT trap fires
  # AFTERWARD in the (sub)shell that is exiting -- so any of
  # do_one_replay's OWN `local` variables that cleanup() referenced
  # (repo_root, wt_path, and a since-removed `cleanup_done` done-guard)
  # were already gone by the time the trap-invoked cleanup() body tried to
  # read them under `set -u`, crashing with "unbound variable" BEFORE the
  # real `git worktree remove` / `rm -rf` below ever ran -- silently
  # leaking the worktree on disk. Independently reproduced for both the
  # done-guard and for $wt_path itself (a mismatched---tree run left an
  # orphaned `replay.XXXXXX` worktree + directory behind).
  #
  # Fixed by passing the two paths cleanup() needs as EXPLICIT ARGUMENTS
  # baked into the trap command STRING at `trap` REGISTRATION time via
  # `printf %q` (shell-safe quoting for ANY byte a path can legally
  # contain, including an embedded single quote -- a naive
  # `"cleanup '$repo_root' '$wt_path'"` form, which this fix used at
  # first, still leaks on a path containing `'`: the unescaped quote
  # breaks the trap command's own quoting and the resulting parse error
  # pre-empts cleanup() exactly like the original bug, independently
  # reproduced and fixed per T043 round-2 review finding N1). `%q`
  # expands immediately at `trap` REGISTRATION time (not at trap-fire
  # time), so the fired trap command is a fully literal, correctly-quoted
  # string with no variable lookups left to perform, and cleanup() no
  # longer depends on do_one_replay's own local-variable lifetime at all,
  # for ANY path value. This also makes cleanup() safely callable twice
  # (once explicitly via `cleanup "$repo_root" "$wt_path"; trap - EXIT`
  # on the success path, once via the EXIT trap on an early return):
  # `git worktree remove --force` is a no-op (stderr already discarded)
  # on an already-removed worktree, and `rm -rf` is a no-op on a missing
  # path.
  cleanup() {
    local rr="$1" wp="$2"
    _fc_kill_child
    git -C "$rr" worktree remove --force "$wp" >/dev/null 2>&1
    rm -rf "$wp" 2>/dev/null
  }
  local _cleanup_trap_cmd
  printf -v _cleanup_trap_cmd 'cleanup %q %q' "$repo_root" "$wt_path"
  trap "$_cleanup_trap_cmd" EXIT
  # T043 round-4 finding B1 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # bash does NOT run the EXIT trap when it dies from an un-handled SIGHUP
  # or SIGQUIT (unlike SIGINT/SIGTERM, independently reproduced as already
  # safe via bash's default disposition -- both correctly run the EXIT
  # trap with no explicit handling needed). SIGHUP is the realistic case
  # (an SSH disconnect, a tmux server dying, a closed terminal) and, per
  # this script's own DISK SAFETY note, each orphan is a full checkout
  # (~49 GB). Fixed by converting HUP/QUIT into an explicit `exit`, which
  # DOES run the already-registered EXIT trap (standard 128+signal exit
  # codes).
  # Call cleanup() DIRECTLY inside the signal handler itself -- rather
  # than `exit N` and relying on that subsequently triggering the EXIT
  # trap -- so this fix has NO dependency on exactly when/whether bash
  # gets around to running a deferred EXIT trap after a non-EXIT signal's
  # own `exit`. `trap - EXIT HUP QUIT` first, so the handler cannot
  # re-enter itself and cleanup() is never invoked twice concurrently.
  # Computed independently from repo_root/wt_path directly (never by
  # string-concatenating onto $_cleanup_trap_cmd above) so this block
  # stays self-contained: mutating the EXIT-trap-registration block above
  # (e.g. §1.1's own paired-mutation test, which reverts it to the
  # original buggy form) must not ALSO collaterally break this
  # DIFFERENT, unrelated fix by removing a variable this block secretly
  # depended on.
  #
  # T048 restart round 1 (R6-F11): (a) cleanup() now FIRST stops the tracked
  # child process group (_fc_kill_child) -- before, a HUP to this subshell
  # removed the worktree while the gate kept running inside the deleted
  # directory; (b) INT and TERM get the same explicit handler (TERM is what the
  # main shell forwards, see _fc_main_on_signal); (c) the handler first IGNORES
  # every terminating signal, so a second signal that lands while cleanup() is
  # still waiting for a slow-to-die gate cannot abort the cleanup half-way and
  # leak the worktree (with a bare `exit 129` handler a second HUP inside the
  # EXIT-trap cleanup exits the shell on the spot).
  local _sig_cleanup_cmd
  printf -v _sig_cleanup_cmd "trap '' HUP INT QUIT TERM; trap - EXIT; cleanup %q %q" "$repo_root" "$wt_path"
  trap "$_sig_cleanup_cmd; exit 129" HUP
  trap "$_sig_cleanup_cmd; exit 130" INT
  trap "$_sig_cleanup_cmd; exit 131" QUIT
  trap "$_sig_cleanup_cmd; exit 143" TERM

  if ! git -C "$repo_root" worktree add --detach --quiet "$wt_path" "$commit" >/dev/null 2>&1; then
    echo "baseline_replay: BLIND: git worktree add failed for commit $commit at $wt_path" >&2
    return 4
  fi

  # T048 restart round 1 (R6-F3, same class): a failed rev-parse used to leave
  # actual_tree empty and the report then carried an empty tree; a frozen tree of
  # "UNMEASURED" silently switched the match check off. Now an unresolvable tree
  # is BLIND, `--tree UNMEASURED` is refused by the argument parser, and the
  # report says whether the tree was actually verified (tree_verified).
  local actual_tree tree_verified=false
  actual_tree="$(git -C "$wt_path" rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null)"
  if [ -z "$actual_tree" ]; then
    echo "baseline_replay: BLIND: cannot resolve the checked-out tree for commit $commit at $wt_path" >&2
    return 4
  fi
  if [ -n "$tree" ]; then
    if [ "$actual_tree" != "$tree" ]; then
      echo "baseline_replay: BLIND: checked-out tree ($actual_tree) != frozen tree ($tree) for commit $commit" >&2
      return 4
    fi
    tree_verified=true
  fi

  # T048 remediation (finding F9, BLOCKING, 2026-09-29 -- systematic-debugging
  # per §11.4.102): `git worktree add --detach` above checks out ONLY the
  # superproject tree -- every git-submodule gitlink (160000 mode entry;
  # this repo has 28 direct submodules incl. device/rockchip/atmosphere/
  # presenter, .../smarttube-player, tools/helixqa/HelixQA, constitution --
  # plus their own nested submodules) is left as an EMPTY placeholder
  # directory in the new worktree. pre_build_verification.sh (line 65: `set
  # -euo pipefail`) reads files out of those submodules (independently
  # verified: PRESENTER_SRC="device/rockchip/atmosphere/presenter/Presenter/
  # src/main/java/com/atmosphere/presenter", CC83's helper awk's
  # "$PRESENTER_SRC/PresenterService.kt"; smarttube-player/SharedModules and
  # .../MediaServiceCore are also read by name, e.g. line ~29471). On THIS
  # host, GNU Awk 5.1.0 exits status 2 -- not 1 -- when its input file does
  # not exist ("awk: fatal: cannot open file ... for reading", independently
  # reproduced: `awk '{print}' /nonexistent 2>&1; echo $?` -> exit 2). CC83
  # captures that failing command's output via a plain assignment
  # (`_cc83_body="$(_cc83_onvideostopped_body ...)"`, itself an `awk ...
  # 2>/dev/null` call) -- under `set -e`, a failing command substitution on
  # the right-hand side of a plain variable assignment DOES trigger errexit
  # (assignment statements are not one of bash's documented `set -e`
  # exemptions, unlike an `if`/`while` condition or a `&&`/`||` operand), so
  # pre_build_verification.sh dies immediately, mid-check, with exit status
  # 2 -- NEVER reaching its own coded `exit 0`/`exit 1` paths. Reproduced
  # twice, deterministically, by hand: an isolated `git worktree add
  # --detach` checkout of ATM-799's frozen commit (07f9b2dd) with NO
  # submodule init dies at CC83 in 4.7s with exit 2, matching this baseline
  # run's own recorded `{"exit_code":2,...}` for every one of the 14
  # cold+warm runs across all 7 duration-eligible items (durations ranging
  # 4.1s-263s ONLY because each frozen commit's version of the script
  # reaches ITS OWN first missing-submodule-file check at a different
  # line/point in an otherwise-successful run, not because of a timeout --
  # `timeout`'s own failure codes are 124/125/126/127/137, never bare 2).
  # THE FIX: make the isolated worktree a faithful replica of what
  # pre_build_verification.sh actually expects to run against (a normal,
  # fully-submoduled checkout of the commit -- the ONLY context this
  # 41k-line gate script was ever written/tested for) by initialising every
  # submodule (direct + nested, since smarttube-player's own checks read
  # ITS nested SharedModules/MediaServiceCore) before running gate_cmd.
  # SECOND CORRECTION (T048 round-2 review finding F9, 2026-09-30 -- the
  # FIRST correction, immediately below, remains fully accurate and
  # unchanged): the claim originally here -- that a linked worktree's
  # submodule `.git/modules` is part of this repo's COMMON git dir,
  # automatically SHARED with the main checkout -- is ALSO WRONG,
  # independently discovered live in a LATER dispatch's own end-to-end
  # proof runs (a real `do_one_replay()` call genuinely stalled 950+
  # CPU-seconds on a real network fetch of `submodules/open_design` despite
  # $repo_root already having that exact submodule fully fetched): a
  # linked worktree's submodule git-dirs live under the PER-WORKTREE
  # `.git/worktrees/<name>/modules/<submodule>` path, NOT the shared
  # `.git/modules/<submodule>` this comment used to claim. `--recursive`
  # alone does NOT reuse the main checkout's already-fetched submodule
  # objects at all -- see `_fc_submodule_reference_update()` (defined
  # above `do_one_replay`, invoked a few lines below at the actual
  # submodule-update call site) for what genuinely closes this gap
  # (T048 round-3 review finding R3-B1: a bare `--reference "$repo_root"`
  # was ALSO tried and independently proven, by live measurement, to be
  # a no-op here -- see that function's own comment + the invocation
  # site's comment for the full correction and the live verification
  # that proved the bug, the false round-2 fix, AND the real fix).
  # HONEST CORRECTION (§11.4.6 -- an earlier draft of this comment claimed
  # "no clone, no network" unconditionally and was WRONG; independently
  # observed live via `ps aux` during this fix's own end-to-end proof
  # runs): when a FROZEN commit (an OLD one especially) pins a submodule
  # SHA that was never locally fetched, `git submodule update --init`
  # does NOT fail or go BLIND -- it does exactly what it is designed to
  # do and performs a REAL network clone of that submodule (observed live:
  # `git submodule--helper clone ... git@github.com:ATMOSphere1234321/
  # ATMOSphere-Lampa.git` and, separately, `...ATMOSphere-SmartTube.git`,
  # each followed by a real `git index-pack ... on the-factory` transfer).
  # That is CORRECT, intended git behaviour, not a bug -- the fetched
  # objects land in the shared `.git/modules/<name>/` object store, so the
  # cost is paid ONCE per missing submodule SHA across the life of this
  # repo's local clone, never repeated for that same SHA again (later
  # do_one_replay calls, this run or a future one, reuse it). It is,
  # however, a genuinely SLOW one-time cost for a large submodule (e.g.
  # smarttube-player's tracked history, ~2.2 GiB working-tree size) --
  # observed adding SEVERAL MINUTES to a single do_one_replay call the
  # first time a historical commit needs it. The BLIND path below is for
  # the genuine failure case only (network unreachable, auth rejected, or
  # the pinned SHA truly gone from every configured remote) -- never for
  # "needs a network fetch", which is expected, cacheable, and correct.
  # Measured disk cost once fully cached: `du -sh` on all 28 direct
  # submodule paths in the MAIN checkout (which already recurses through
  # their own nested content) is ~7.4 GiB total, ON TOP OF the ~49 GiB
  # superproject checkout. (An earlier version of this sentence called that
  # "well inside the --min-free-kb 10 GiB headroom" -- false: 49 + 7.4 GiB is
  # more than five times 10 GiB. T048 restart round 1, R6-F10 raised the
  # default floor to DEFAULT_MIN_FREE_KB = 67 GiB, derived from these two
  # measurements plus 10 GiB headroom.)
  #
  # T048 remediation, signal-safety hardening added AFTER independently
  # observing the multi-minute network-clone cost above IN THIS SAME
  # dispatch's own end-to-end proof runs: the SAME T043 round-4 finding B1
  # class (a plain FOREGROUND command defers any trapped HUP/QUIT signal
  # -- and, empirically re-confirmed live during this exact investigation,
  # can leave a git-worktree-remove needed EVEN for a plain TERM sent to
  # only the top-level script process while a `git submodule--helper`
  # grandchild keeps running detached, reparented, and orphaned) applies
  # here just as much as it did to the gate-cmd run below -- this step can
  # now take LONGER than the gate-cmd itself on a stale local checkout.
  # Fixed the identical way: BACKGROUND the command + `wait` on it
  # explicitly (promptly interruptible by a pending trapped signal,
  # unlike a synchronous foreground pipeline) and bound it with `timeout`
  # (reusing the caller's own --timeout-s knob rather than adding a new
  # CLI flag) so a genuine network stall cannot hang this step forever.
  #
  # Security remediation (T048 review, 2026-09-29): `$commit` here is
  # always EITHER a SHA `cmd_freeze` resolved via `git log --all --grep`
  # against THIS repo's own already-fetched local history, or an
  # operator-supplied `--commit` argument -- in both cases `git -C
  # "$repo_root" worktree add --detach "$wt_path" "$commit"` a few lines
  # above ALREADY required that commit's TREE to be a valid, already-
  # present object in $repo_root's local object store (worktree add never
  # fetches; an unreachable SHA fails there with BLIND before this line is
  # ever reached). So $commit itself is never unvalidated external input.
  # $commit's TREE CONTENT, however, is only as trustworthy as this repo's
  # own history -- and its .gitmodules is ordinary versioned content, so a
  # submodule path this specific commit introduces (one with no prior
  # `submodule.<name>.url` already recorded in the shared `.git/config`
  # from the main checkout's own real `git submodule init`) has its
  # fetch URL read straight out of THAT COMMIT's .gitmodules with no
  # allowlist check. Git's own `ext::` submodule-URL remote-code-execution
  # class (the CVE-2017-1000117 family) is denied by this host's git 2.50.1
  # default (`protocol.ext.allow=user`, confirmed via `git config --get`
  # returning unset -- i.e. the compiled-in default, "deny for an
  # operation like this one that did not explicitly opt in"), so this is
  # belt-and-braces defense-in-depth, not a bypass of an otherwise-open
  # hole: pin `ext`/`file` to `never` explicitly on THIS invocation only
  # (never touching the caller's global git config) so a future git
  # version or a differently-configured host cannot re-open it. An ambient
  # `GIT_ALLOW_PROTOCOL` / `GIT_CONFIG_*` environment override is NOT stopped
  # by `-c` alone (an earlier version of this comment claimed it was; measured
  # false, T048 restart round 1 R6-F15) -- those variables are removed with
  # `env -u` on the call itself inside _fc_submodule_reference_update(). `file`
  # is denied too -- a crafted local-path submodule URL pointing at an
  # attacker-writable bare repo is the same class of risk as `ext::`, and
  # this project's own real submodules (confirmed via `.gitmodules`) are
  # exclusively `git@github.com:...` SSH URLs, so neither protocol is ever
  # legitimately needed here.
  # T048 round-2 review finding F9 (2026-09-30, §11.4.102 root-cause
  # investigation): a linked worktree's `git submodule update --init
  # --recursive` clones EACH submodule into its OWN per-worktree git-dir
  # (`.git/worktrees/<name>/modules/<submodule>`, NOT the shared common
  # `.git/modules/<submodule>` every earlier draft of this file's own
  # comments assumed) -- reproduced live: a real do_one_replay() run
  # genuinely stalled 950+ CPU-seconds on a real network `git index-pack`
  # for `submodules/open_design`, even though $repo_root (the MAIN
  # checkout this worktree was created FROM) already has that exact
  # submodule fully fetched at `.git/modules/submodules/open_design`.
  # T048 round-3 review finding R3-B1 (2026-09-30, CORRECTS the round-2
  # text that used to sit here): the round-2 claim that a bare
  # `--reference "$repo_root"` makes "git's own submodule-clone machinery
  # automatically resolve `<reference>/.git/modules/<name>`" is FALSE --
  # independently re-measured live this dispatch (git 2.50.1, file://
  # transport, `git count-objects` before/after, exactly the round-3
  # reviewer's own methodology): a fresh submodule clone transferred the
  # IDENTICAL object count with `--reference "$repo_root"` as with no
  # `--reference` at all (both fetch everything over the wire), while
  # referencing the submodule's OWN store directly
  # (`"$repo_root"/.git/modules/<name>`) transferred ZERO objects. A
  # single `--reference <path>` on `git submodule update` is passed to
  # git-clone(1) verbatim for every submodule being cloned; it is never
  # expanded per-submodule on this codepath. (git DOES have a genuine
  # `-c submodule.alternateLocation=superproject` feature for automatic
  # per-submodule alternate resolution, but it is wired only into `git
  # clone --recurse-submodules --reference <path>`'s initial-clone
  # codepath -- re-tested live and confirmed it has NO effect on a
  # `submodule update --init --recursive --reference <path>` call
  # against an ALREADY-EXISTING checkout, which is what a `git worktree
  # add`-based replay needs here.) Fixed by `_fc_submodule_reference_
  # update()` (defined above `do_one_replay`) which loops submodule-BY-
  # submodule, computing and passing EACH submodule's own already-
  # fetched store under $repo_root's git-common-dir individually
  # (`git -C "$repo_root" rev-parse --git-common-dir` -- resolves
  # correctly even when $repo_root is itself a linked worktree, since
  # `--git-common-dir` always resolves to the shared repo, not a
  # per-worktree path) as that ONE submodule's `--reference` --
  # RECURSING into any submodule that itself declares its own
  # `.gitmodules` (a nested submodule) using $repo_root's OWN
  # already-checked-out copy of that submodule as the new reference
  # source, since a nested submodule's store lives at
  # `<parent-store>/modules/<nested-name>`, which `rev-parse
  # --git-common-dir` composes correctly from within that checked-out
  # directory (verified live against a real 2-level-nested scratch
  # fixture: 0 objects transferred at BOTH the top-level AND the nested
  # level). Degrades safely per submodule, independently, exactly as the
  # round-2 text claimed for its own (broken) form: a submodule
  # $repo_root has never fetched gets no `--reference` flag and falls
  # through to a normal network clone for THAT submodule only (verified
  # live, exit 0, unaffected); a submodule whose remote is genuinely
  # unreachable still correctly fails non-zero regardless of whether a
  # `--reference` was supplied (verified live: `--reference` never
  # removes the need to negotiate refs with the remote -- it only avoids
  # re-transferring objects the remote and the reference already
  # agree on), preserving the exact "refuse to run gate_cmd against a
  # partially-checked-out tree" semantics the caller below depends on.
  # `--reference` (not `--reference-if-able`) is deliberate: this git
  # version's `submodule update` does not recognise the `-if-able` form
  # at all (confirmed live: real exit 1, a usage error).
  # T048 restart round 1 (R6-F11): `timeout` is backgrounded directly (no
  # wrapping subshell), so `$!` is its process GROUP and a signal handler can
  # stop the whole `git submodule--helper clone` tree via _fc_kill_child, not
  # just the shell around it. The helper function is exported only for this one
  # child and un-exported again, so the GATE never inherits it.
  export -f _fc_submodule_reference_update
  # the bash -c body is single-quoted on purpose: $1/$2 must expand in the child shell, not here
  # shellcheck disable=SC2016
  timeout --kill-after=5 "${timeout_s}s" \
      "$BASH" -c '_fc_submodule_reference_update "$1" "$2"' fc-submodule "$repo_root" "$wt_path" \
      >/dev/null 2>&1 </dev/null &
  _FC_CHILD_PGID=$!
  wait "$_FC_CHILD_PGID"
  local submodule_rc=$?
  _FC_CHILD_PGID=""
  export -fn _fc_submodule_reference_update
  if [ "$submodule_rc" -ne 0 ]; then
    echo "baseline_replay: BLIND: git submodule update --init --recursive failed (exit $submodule_rc$( [ "$submodule_rc" = 124 ] || [ "$submodule_rc" = 137 ] && echo ", timed out after ${timeout_s}s")) for commit $commit at $wt_path (a frozen submodule SHA may be absent from the local object store, or a network fetch stalled -- refusing to run gate_cmd against a partially-checked-out tree)" >&2
    return 4
  fi

  # T048 remediation (finding F9 continued): after the submodule fix above,
  # a SECOND, DISTINCT missing-prerequisite class was independently
  # reproduced for the "slow" items (ATM-610/611/627/277/SPK-609, 170-263s
  # elapsed vs. the "fast" CC83 class' 4-5s): a pre-build gate this project
  # runs can itself contain a "cmd; rc=$?" style SEQUENTIAL (`;`), not
  # errexit-exempt, inline sub-script invocation (contrast this SAME file's
  # own later "§11.4.1-safe live-run" harness check, which deliberately
  # uses the errexit-EXEMPT `if cmd; then rc=0; else rc=$?; fi` form
  # instead) whose sub-script is DESIGNED to exit 2 as an honest SKIP when
  # a single, project-defined, gitignored host-build prerequisite is
  # absent -- a tool git NEVER tracks and that a bare `git worktree add`
  # checkout therefore NEVER has, while this project's own long-lived,
  # repeatedly-built dev tree (the environment T045's cited "~18.9 min per
  # full run" evidence-block figure was measured against) has it sitting
  # around from a PRIOR build, since nothing in this project's normal
  # workflow ever `make clean`s host tools. So the SKIP=2 the isolated
  # worktree hits here is real to the worktree, but NOT representative of
  # the environment this gate's timing was ever measured or is meant to be
  # measured against. Rather than chasing every gate's own inline
  # sub-script sites for a similar gap (a full project-side audit found
  # this class affects exactly one such site; every OTHER inline
  # sub-script run in this file already uses the errexit-exempt `if`-form),
  # compile the ONE confirmed, cheap, self-contained, no-network host tool
  # this isolated worktree is missing -- IF the caller has named one via
  # the two `FC_REPLAY_HOSTTOOL_*` env vars below. §11.4.28(B): this
  # generic replay machinery takes any such project-specific prerequisite
  # as caller-supplied DATA, never a hardcoded literal path -- leaving
  # either env var unset makes this whole step an honest no-op. BOUNDED,
  # not a slippery slope toward replicating a full project build: this
  # project's own concrete instance names a single ~1575-line file, ~1s to
  # compile, verified independently (`cc -O2` on it exits 0, its own
  # `--help` runs, and the gate that needed it genuinely PASSes against it
  # afterward instead of SKIPping). A compile failure is treated exactly
  # like the worktree-add/submodule-update failures above -- an honest
  # BLIND (unmeasurable), never silently absorbed.
  local _rt_src="" _rt_bin=""
  if [ -n "${FC_REPLAY_HOSTTOOL_SRC:-}" ] && [ -n "${FC_REPLAY_HOSTTOOL_BIN:-}" ]; then
    _rt_src="$wt_path/${FC_REPLAY_HOSTTOOL_SRC}"
    _rt_bin="$wt_path/${FC_REPLAY_HOSTTOOL_BIN}"
  fi
  if [ -n "$_rt_src" ] && [ -f "$_rt_src" ] && [ ! -x "$_rt_bin" ]; then
    # Security remediation (T048 review, 2026-09-29): symlink-follow-write
    # guard. $wt_path is a disposable `git worktree add --detach` checkout
    # of $commit (an arbitrary, possibly-historical commit from this
    # repo's own local history -- see the submodule-fetch comment above
    # for why $commit itself is never unvalidated external input, though
    # its TREE CONTENT is still only as trustworthy as this repo's own
    # history). Git tracks symlinks as ordinary blobs (mode 120000), so
    # nothing here prevents SOME commit in that history from having
    # checked out the configured host-tool's containing directory (or the
    # source/binary leaf entries themselves) as a symlink pointing OUTSIDE
    # this worktree -- `cc -O2 -o "$_rt_bin" "$_rt_src"` would then
    # transparently follow that symlink and CREATE or OVERWRITE an
    # attacker-chosen file anywhere the invoking user can write, driven
    # entirely by tree content this script never authored. Refuse (BLIND)
    # rather than follow: canonicalize the source file's containing
    # directory with `pwd -P` (resolves every symlink component, unlike a
    # plain path-string prefix check) and verify the RESULT still lives
    # strictly inside $wt_path's own canonical path before compiling
    # anything; independently also refuse if either the source or the
    # binary path itself is a symlink LEAF (a legitimate directory
    # containing a symlinked single file, which the directory-containment
    # check alone would not catch).
    local _rt_dir _rt_dir_real wt_path_real
    _rt_dir="$(dirname "$_rt_src")"
    _rt_dir_real="$(cd "$_rt_dir" 2>/dev/null && pwd -P)"
    wt_path_real="$(cd "$wt_path" 2>/dev/null && pwd -P)"
    if [ -z "$_rt_dir_real" ] || [ -z "$wt_path_real" ] || \
       { [ "$_rt_dir_real" != "$wt_path_real" ] && \
         [ "${_rt_dir_real#"$wt_path_real"/}" = "$_rt_dir_real" ]; } || \
       [ -L "$_rt_src" ] || [ -L "$_rt_bin" ]; then
      echo "baseline_replay: BLIND: configured host-tool path (FC_REPLAY_HOSTTOOL_SRC=${FC_REPLAY_HOSTTOOL_SRC}, FC_REPLAY_HOSTTOOL_BIN=${FC_REPLAY_HOSTTOOL_BIN}) resolves OUTSIDE the isolated worktree (worktree is ${wt_path_real:-$wt_path}) for commit $commit -- refusing to compile through what appears to be a git-tracked symlink escaping the disposable checkout, which could otherwise write an attacker-chosen file anywhere the invoking user can write" >&2
      return 4
    fi
    if ! cc -O2 -o "$_rt_bin" "$_rt_src" >/dev/null 2>&1; then
      echo "baseline_replay: BLIND: host-tool compile failed for $_rt_src at $wt_path (FC_REPLAY_HOSTTOOL_SRC names a gitignored host-build prerequisite the caller's gate_cmd needs; without it, that gate's own inline sub-run can crash the whole gate under set -e via an honest exit-2 SKIP the wrapper cannot safely capture)" >&2
      return 4
    fi
  fi

  # T048 remediation (finding F9 continued -- the output-discarding
  # hardening asked for independently of the root cause fix above): the
  # gate-cmd's combined stdout+stderr used to go straight to `/dev/null`
  # (a prior version of this line), so a future crash/hang/unexpected
  # nonzero exit had NO captured evidence to diagnose from without
  # re-running the whole (multi-minute) replay by hand. Every run gets its
  # own persistent log file, recorded in its JSON row (captured-evidence
  # citation per §11.4.5).
  # T048 restart round 1 (R6-F6): the earlier name
  # `${commit:0:12}_${phase}_${idx}.log` directly under replay-logs/ was NOT
  # unique -- the two internal runs of --determinism-check, a re-run, and two
  # sample items frozen to the same commit all wrote the same paths, so run 2
  # overwrote run 1's evidence and the recorded log_path cited the wrong run
  # (measured: run 1's cold_1.log contained run 2's output). Each do_one_replay
  # call now creates its OWN fresh directory with mktemp -d (unique by
  # construction, never reused), a sibling of $wt_path so cleanup() -- which
  # only removes $wt_path -- never touches it. The directory is recorded as the
  # report's log_dir.
  mkdir -p "$worktree_root/replay-logs" 2>/dev/null || { echo "baseline_replay: cannot create run-log directory $worktree_root/replay-logs" >&2; return 4; }
  local run_log_dir
  run_log_dir="$(mktemp -d "$worktree_root/replay-logs/${commit:0:12}.XXXXXX")" || { echo "baseline_replay: cannot create a unique run-log directory under $worktree_root/replay-logs" >&2; return 4; }

  local rows='[]' harness_error=0
  local phase run_idx n_runs run_log
  for phase in cold warm; do
    if [ "$phase" = cold ]; then n_runs="$cold_runs"; else n_runs="$warm_runs"; fi
    run_idx=1
    # A HARNESS_ERROR means the gate could not be started at all; repeating the
    # same failed launch measures nothing, so the loop stops at the first one.
    while [ "$run_idx" -le "$n_runs" ] && [ "$harness_error" = 0 ]; do
      run_log="$run_log_dir/${phase}_${run_idx}.log"
      run_gate_once "$wt_path" "$timeout_s" "$run_log" -- "${gate_cmd[@]}" || return 4
      [ "$RG_VERDICT" = HARNESS_ERROR ] && harness_error=1
      rows="$(python3 - "$rows" "$phase" "$run_idx" "$RG_START_NS" "$RG_END_NS" "$RG_DURATION_MS" \
          "$RG_RC" "$RG_VERDICT" "$RG_REASON" "$run_log" <<'PY'
import json, sys
a = sys.argv
rows = json.loads(a[1])
rows.append({"phase": a[2], "run_index": int(a[3]), "start_ns": int(a[4]), "end_ns": int(a[5]),
             "duration_ms": int(a[6]), "exit_code": int(a[7]), "verdict": a[8], "verdict_reason": a[9],
             "log_path": a[10]})
print(json.dumps(rows))
PY
)" || { echo "baseline_replay: cannot record run row" >&2; return 4; }
      run_idx=$((run_idx + 1))
    done
  done

  cleanup "$repo_root" "$wt_path"
  trap - EXIT HUP INT QUIT TERM

  # Report body. T048 restart round 1:
  #  - R6-F5: every value is passed through argv; the program text is a quoted
  #    heredoc, so no data is ever parsed as Python source.
  #  - R6-F9: median_ms is computed over PASS runs ONLY. A FAIL may be a crash
  #    that stopped part-way (the documented F9 forensic: 14 runs that all
  #    crashed with exit 2 after 4-263 s), and UNMEASURED / HARNESS_ERROR runs
  #    never completed; none of them is a measurement of how long the gate
  #    takes. The per-verdict breakdown keeps the FAIL durations visible
  #    (by_verdict) without letting them into the baseline.
  python3 - "$rows" "$commit" "$actual_tree" "$tree_verified" "$cold_runs" "$warm_runs" \
      "$min_free_kb" "$timeout_s" "$run_log_dir" "$harness_error" "${gate_cmd[@]}" <<'PY'
import json, statistics, sys
a = sys.argv
rows = json.loads(a[1])
commit, tree, tree_verified = a[2], a[3], a[4] == "true"
cold_runs, warm_runs, min_free_kb, timeout_s = int(a[5]), int(a[6]), int(a[7]), int(a[8])
log_dir, harness_error, gate_cmd = a[9], a[10] == "1", a[11:]
def med(vals):
    return int(round(statistics.median(vals))) if vals else "UNMEASURED"
phases = ("cold", "warm")
median_ms = {p: med([r["duration_ms"] for r in rows if r["phase"] == p and r["verdict"] == "PASS"])
             for p in phases}
by_verdict = {}
for p in phases:
    by_verdict[p] = {}
    for v in sorted({r["verdict"] for r in rows if r["phase"] == p}):
        d = [r["duration_ms"] for r in rows if r["phase"] == p and r["verdict"] == v]
        by_verdict[p][v] = {"n_runs": len(d), "median_ms": med(d)}
verdict_set = {p: sorted({r["verdict"] for r in rows if r["phase"] == p}) for p in phases}
print(json.dumps({
    "commit": commit, "tree": tree, "tree_verified": tree_verified, "gate_cmd": gate_cmd,
    "cold_runs": cold_runs, "warm_runs": warm_runs, "min_free_kb": min_free_kb, "timeout_s": timeout_s,
    "cache_mechanism": "none (T068 verdict_cache.py not landed in this tree, verified 2026-09-28)",
    "median_basis": "PASS runs only (FAIL/UNMEASURED/HARNESS_ERROR excluded, see by_verdict)",
    "log_dir": log_dir, "harness_error": harness_error,
    "runs": rows, "median_ms": median_ms, "by_verdict": by_verdict, "verdict_set": verdict_set,
}))
PY
}

# =============================================================================
# run_replay_isolated BODY_FILE do_one_replay-args...
# T048 restart round 1 (R6-F11a): do_one_replay used to run inside `$(...)`. A
# TERM sent to the main script killed the main shell but NOT that
# command-substitution subshell, which kept running EVERY remaining scheduled
# gate run as an orphan (measured: a run started 8 s after the TERM; in
# production up to 20 runs x 30 min). It now runs as a background job whose pid
# the main shell holds (_FC_REPLAY_PID), its body is written to a file, and the
# main shell's own signal handlers (_fc_main_on_signal) forward TERM to it and
# wait for its cleanup. TERM is forwarded for every signal: a background job of
# a non-interactive shell ignores INT and QUIT, and its TERM handler performs the
# same cleanup.
# =============================================================================
run_replay_isolated() {
  local body_file="$1"
  shift
  do_one_replay "$@" >"$body_file" &
  _FC_REPLAY_PID=$!
  wait "$_FC_REPLAY_PID"
  local rc=$?
  _FC_REPLAY_PID=""
  return "$rc"
}

# invoked only from the trap strings installed by _fc_install_main_traps below
# shellcheck disable=SC2329
_fc_main_on_signal() {
  trap '' HUP INT QUIT TERM
  local code="$1" p="${_FC_REPLAY_PID:-}"
  _fc_kill_child   # a selfcheck gate run happens in the main shell itself
  case "$p" in ''|*[!0-9]*) p="" ;; esac
  if [ -n "$p" ] && [ "$p" -gt 1 ]; then
    kill -s TERM "$p" 2>/dev/null
    wait "$p" 2>/dev/null
  fi
  exit "$code"
}

_fc_install_main_traps() {
  trap '_fc_main_on_signal 129' HUP
  trap '_fc_main_on_signal 130' INT
  trap '_fc_main_on_signal 131' QUIT
  trap '_fc_main_on_signal 143' TERM
}

# parse_gate_cmd STR -> sets GATE_ARGV. Word-splits on whitespace WITHOUT
# pathname expansion (T048 restart round 1, R6-F19 class: the old unquoted
# `$gate_cmd_str` expansions also glob-expanded every word against the caller's
# cwd). HONEST BOUNDARY (unchanged): an argument cannot itself contain
# whitespace.
parse_gate_cmd() {
  case "$1" in *$'\n'*|*$'\r'*) die "--gate-cmd must be a single line" ;; esac
  GATE_ARGV=()
  read -r -a GATE_ARGV <<<"$1"
  [ "${#GATE_ARGV[@]}" -ge 1 ] || die "--gate-cmd must name a command"
}

# validate_run_counts COLD WARM TIMEOUT_S MIN_FREE_KB (T048 restart round 1:
# R6-F7 zero runs, R6-F18 --timeout-s 0 which DISABLES timeout(1)).
validate_run_counts() {
  isnum "$1" || die "--cold-runs must be a non-negative integer"
  isnum "$2" || die "--warm-runs must be a non-negative integer"
  [ $(( $1 + $2 )) -ge 1 ] || die "--cold-runs + --warm-runs must be at least 1 (zero runs measure nothing)"
  { isnum "$3" && [ "$3" -ge 1 ]; } || die "--timeout-s must be a positive integer (0 would disable the bound)"
  isnum "$4" || die "--min-free-kb must be a non-negative integer"
  command -v timeout >/dev/null 2>&1 || blind "timeout(1) not found -- cannot bound a gate run"
}

# body_field FILE EXPR -> prints a field of a JSON body file (data read from the
# file, the expression is always a literal from this script).
body_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = d
for k in sys.argv[2].split("."):
    v = v[k]
print(json.dumps(v) if not isinstance(v, str) else v)
PY
}

# =============================================================================
# replay
# =============================================================================
cmd_replay() {
  local commit="" tree="" gate_cmd_str="" cold_runs=10 warm_runs=10
  local repo_root="" worktree_root="" min_free_kb="$DEFAULT_MIN_FREE_KB" timeout_s=1800 out=""
  local determinism_check=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --determinism-check) determinism_check=1; shift; continue ;;
    esac
    [ $# -ge 2 ] || die "replay: $1 needs a value"
    case "$1" in
      --commit) commit="$2" ;;
      --tree) tree="$2" ;;
      --gate-cmd) gate_cmd_str="$2" ;;
      --cold-runs) cold_runs="$2" ;;
      --warm-runs) warm_runs="$2" ;;
      --repo-root) repo_root="$2" ;;
      --worktree-root) worktree_root="$2" ;;
      --min-free-kb) min_free_kb="$2" ;;
      --timeout-s) timeout_s="$2" ;;
      --out) out="$2" ;;
      *) die "replay: unknown argument: $1" ;;
    esac
    shift 2
  done
  [ -n "$commit" ] || die "replay: --commit is required"
  [ -n "$gate_cmd_str" ] || die "replay: --gate-cmd is required"
  [ -n "$out" ] || die "replay: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  # T048 restart round 1 (R6-F3 class): a freeze that could not resolve the tree
  # must never switch the tree-match check off. Omit --tree to replay without a
  # tree check (recorded as tree_verified=false); never pass UNMEASURED.
  [ "$tree" = UNMEASURED ] && die "replay: --tree UNMEASURED refused -- the frozen tree was never resolved; omit --tree explicitly to replay without a tree check"
  validate_run_counts "$cold_runs" "$warm_runs" "$timeout_s" "$min_free_kb"
  parse_gate_cmd "$gate_cmd_str"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$worktree_root" ] || worktree_root="$repo_root/.fc_worktrees"
  # T043 round-4 finding B3 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # a RELATIVE --worktree-root resolves against the CALLER's cwd for
  # mktemp/rev-parse/df/the gate's own `cd`, but against $repo_root for
  # `git -C "$repo_root" worktree add` -- two different base directories
  # for the SAME value, silently pointing at two different locations.
  # Fixed the SAME way repo_root already is, two lines up: resolve to an
  # absolute, canonical path up front so every later consumer (mktemp,
  # df, git -C, the gate's cd) agrees on the SAME directory.
  mkdir -p "$worktree_root" 2>/dev/null || die "replay: cannot create --worktree-root $worktree_root"
  worktree_root="$(cd "$worktree_root" 2>/dev/null && pwd)" || die "replay: cannot resolve --worktree-root $worktree_root to an absolute path"

  _fc_install_main_traps
  run_selfcheck || return 3

  local body1 body2
  body1="$(mktemp)" || blind "mktemp failed"
  run_replay_isolated "$body1" "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
    "$timeout_s" "$cold_runs" "$warm_runs" "${GATE_ARGV[@]}" || { rm -f "$body1"; return 4; }

  if [ "$determinism_check" = 1 ]; then
    # DETERMINISM (C-003). `replay`'s report embeds real wall-clock timing, so
    # a byte-identical body comparison can never pass (verified 2026-09-28);
    # this flag replays the SAME frozen {commit, tree, gate-cmd} twice and
    # compares the VERDICTS. T048 restart round 1 (R6-F7) tightened the rule:
    #  - a phase whose verdict set holds more than one verdict inside ONE
    #    invocation is itself non-deterministic (an alternating PASS/FAIL gate
    #    with --cold-runs 2 gave {"cold":["FAIL","PASS"]} twice and used to be
    #    reported deterministic);
    #  - both phases are compared (a warm-only difference is a difference);
    #  - a run that never completed (UNMEASURED) or never started
    #    (HARNESS_ERROR) gives NO verdict: deterministic=null, exit 4 --
    #    "could not measure, twice" is not "deterministic";
    #  - zero runs are refused by validate_run_counts (a check over nothing
    #    cannot fail).
    body2="$(mktemp)" || blind "mktemp failed"
    run_replay_isolated "$body2" "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
      "$timeout_s" "$cold_runs" "$warm_runs" "${GATE_ARGV[@]}" || { rm -f "$body1" "$body2"; return 4; }
    local det_body det_rc emit_rc
    det_body="$(python3 - "$body1" "$body2" <<'PY'
import json, sys
b1, b2 = (json.load(open(p)) for p in sys.argv[1:3])
phases = ("cold", "warm")
vs1, vs2 = b1["verdict_set"], b2["verdict_set"]
out = {"run1_verdict_set": vs1, "run2_verdict_set": vs2,
       "run1_log_dir": b1["log_dir"], "run2_log_dir": b2["log_dir"]}
unmeasurable = sorted({r["verdict"] for b in (b1, b2) for r in b["runs"]
                       if r["verdict"] in ("UNMEASURED", "HARNESS_ERROR")})
if unmeasurable:
    out.update(deterministic=None,
               reason="no determinism verdict: run(s) classified %s" % ",".join(unmeasurable))
    print(json.dumps(out))
    sys.exit(4)
flaky = sorted({p for b in (b1, b2) for p in phases if len(b["verdict_set"].get(p, [])) > 1})
differs = sorted({p for p in phases if vs1.get(p, []) != vs2.get(p, [])})
det = not flaky and not differs
out.update(deterministic=det, within_run_flaky_phases=flaky, differing_phases=differs)
print(json.dumps(out))
sys.exit(0 if det else 1)
PY
)"
    det_rc=$?
    rm -f "$body1" "$body2"
    echo "$det_body"
    # T043 round-3 review finding F3(c): a --out write failure is always
    # surfaced, and escalates a would-be exit 0 to 4 (a caller must never see
    # exit 0 when the mandatory --out contract was not honoured).
    emit_doc "baseline-replay-determinism/v1" "$det_body" "$out"
    emit_rc=$?
    if [ "$emit_rc" != 0 ]; then
      echo "baseline_replay: WARNING: writing the --determinism-check result to --out ($out) failed (emit_doc exit $emit_rc) -- the determinism verdict printed above is still accurate, but the mandatory --out contract was not honored" >&2
      [ "$det_rc" = 0 ] && return 4
    fi
    return "$det_rc"
  fi

  local body herr
  body="$(cat "$body1")"
  herr="$(body_field "$body1" harness_error)"
  rm -f "$body1"
  emit_doc "baseline-replay/v1" "$body" "$out" || return $?
  # R6-F8: a gate that could not even be started is BLIND (exit 4), never a
  # recorded "gate FAIL" with exit 0. The report is still written as evidence.
  if [ "$herr" = true ]; then
    echo "baseline_replay: BLIND: the gate command could not be started (HARNESS_ERROR, see the report's runs[].verdict_reason)" >&2
    return 4
  fi
  return 0
}

# =============================================================================
# replay-sample
# =============================================================================
cmd_replay_sample() {
  local sample="" gate_cmd_str="" cold_runs=10 warm_runs=10
  local repo_root="" worktree_root="" min_free_kb="$DEFAULT_MIN_FREE_KB" timeout_s=1800 out=""
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "replay-sample: $1 needs a value"
    case "$1" in
      --sample) sample="$2" ;;
      --gate-cmd) gate_cmd_str="$2" ;;
      --cold-runs) cold_runs="$2" ;;
      --warm-runs) warm_runs="$2" ;;
      --repo-root) repo_root="$2" ;;
      --worktree-root) worktree_root="$2" ;;
      --min-free-kb) min_free_kb="$2" ;;
      --timeout-s) timeout_s="$2" ;;
      --out) out="$2" ;;
      *) die "replay-sample: unknown argument: $1" ;;
    esac
    shift 2
  done
  [ -n "$sample" ] || die "replay-sample: --sample is required"
  [ -n "$gate_cmd_str" ] || die "replay-sample: --gate-cmd is required"
  [ -n "$out" ] || die "replay-sample: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  validate_run_counts "$cold_runs" "$warm_runs" "$timeout_s" "$min_free_kb"
  parse_gate_cmd "$gate_cmd_str"
  [ -f "$sample" ] || blind "--sample file not found: $sample"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$worktree_root" ] || worktree_root="$repo_root/.fc_worktrees"
  # T043 round-4 finding B3: resolve --worktree-root to one absolute path up
  # front (see cmd_replay).
  mkdir -p "$worktree_root" 2>/dev/null || die "replay-sample: cannot create --worktree-root $worktree_root"
  worktree_root="$(cd "$worktree_root" 2>/dev/null && pwd)" || die "replay-sample: cannot resolve --worktree-root $worktree_root to an absolute path"
  local db_path="$repo_root/docs/workable_items.db"

  _fc_install_main_traps
  run_selfcheck || return 3

  # Item ids are read as NUL-separated DATA (R6-F5: the sample path used to be
  # spliced into Python source, and ids were split on newlines).
  local ids_file entries_file
  ids_file="$(mktemp)" || blind "mktemp failed"
  entries_file="$(mktemp)" || blind "mktemp failed"
  python3 - "$sample" >"$ids_file" <<'PY' || { rm -f "$ids_file" "$entries_file"; blind "--sample is not a readable select_sample.py output doc (an object with an 'items' list of {item_id: <non-empty single-line string>})"; }
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("items") if isinstance(doc, dict) else None
if not isinstance(items, list):
    sys.exit(4)
for it in items:
    iid = it.get("item_id") if isinstance(it, dict) else None
    if not isinstance(iid, str) or not iid or "\n" in iid or "\r" in iid or "\0" in iid:
        sys.exit(4)
    sys.stdout.write(iid + "\0")
PY

  local item_id n_harness=0
  while IFS= read -r -d '' item_id; do
    local entry_kind="" commit="" tree="" body_file="" reason=""
    if ! freeze_to_body "$item_id" "$repo_root" "$db_path"; then
      entry_kind=harness; reason="freeze BLIND: ${FZ_ERR:-tracker DB unreadable}"
    elif [ "$FZ_SHA" = UNMEASURED ]; then
      entry_kind=skipped; reason="freeze UNMEASURED (no subject-matching commit found)"
    else
      commit="$FZ_SHA"; tree="$FZ_TREE"
      body_file="$(mktemp)" || blind "mktemp failed"
      if run_replay_isolated "$body_file" "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
           "$timeout_s" "$cold_runs" "$warm_runs" "${GATE_ARGV[@]}"; then
        entry_kind=replayed
      else
        entry_kind=harness; reason="replay harness error rc=$?"
      fi
    fi
    [ "$entry_kind" = harness ] && n_harness=$((n_harness + 1))
    python3 - "$entry_kind" "$item_id" "$commit" "$tree" "$reason" "$body_file" >>"$entries_file" <<'PY' || blind "cannot record the replay-sample entry for an item"
import json, sys
kind, iid, commit, tree, reason, body_file = sys.argv[1:7]
e = {"item_id": iid}
if kind == "replayed":
    b = json.load(open(body_file))
    e.update(skipped=False, skip_reason=None, commit=b["commit"], tree=b["tree"],
             tree_verified=b["tree_verified"], median_ms=b["median_ms"], verdict_set=b["verdict_set"],
             log_dir=b["log_dir"], harness_error=b["harness_error"])
else:
    e.update(skipped=True, skip_reason=reason, harness_error=(kind == "harness"))
    if commit:
        e.update(commit=commit, tree=tree)
print(json.dumps(e))
PY
    if [ "$entry_kind" = replayed ] && [ "$(body_field "$body_file" harness_error)" = true ]; then
      n_harness=$((n_harness + 1))
    fi
    [ -n "$body_file" ] && rm -f "$body_file"
  done <"$ids_file"
  rm -f "$ids_file"

  local body
  body="$(python3 - "$sample" "$cold_runs" "$warm_runs" "$entries_file" "${GATE_ARGV[@]}" <<'PY'
import json, sys
a = sys.argv
items = [json.loads(l) for l in open(a[4]) if l.strip()]
print(json.dumps({"sample_path": a[1], "gate_cmd": a[5:], "cold_runs": int(a[2]),
                  "warm_runs": int(a[3]), "items": items}))
PY
)" || { rm -f "$entries_file"; blind "cannot assemble the replay-sample report"; }
  rm -f "$entries_file"
  emit_doc "baseline-replay-sample/v1" "$body" "$out" || return $?
  # R6-F3/F8/F12 class: an item that could not be measured because the HARNESS
  # failed (freeze BLIND, worktree/submodule failure, a gate that never started)
  # is recorded per item AND makes the whole run exit 4, never exit 0.
  if [ "$n_harness" -gt 0 ]; then
    echo "baseline_replay: BLIND: $n_harness sample item(s) could not be measured because the harness failed (see items[].skip_reason / harness_error in the report)" >&2
    return 4
  fi
  return 0
}

# T048 restart round 1 (R6-F12): FC_OUT (set by fc_common.py determinism-check
# for the command it re-runs) redirects THIS invocation's top-level --out only.
# It is captured once here and then removed from the environment, so no internal
# emit and no child process -- in particular the replayed gate, which may itself
# be an FC tool -- ever sees it.
_FC_OUT_OVERRIDE="${FC_OUT:-}"
unset FC_OUT

case "$SUBCMD" in
  freeze) cmd_freeze "$@"; exit $? ;;
  selfcheck) cmd_selfcheck "$@"; exit $? ;;
  replay) cmd_replay "$@"; exit $? ;;
  replay-sample) cmd_replay_sample "$@"; exit $? ;;
  *) usage ;;
esac
