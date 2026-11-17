#!/usr/bin/env bash
# jev-start-gate.sh — the GATED start process of scripts/jev/jev-place.sh (§11.4.291, round 14, review R13-B1).
#
# Usage (only jev-place.sh runs it, as a background child, OUTSIDE the lease lock):
#   jev-start-gate.sh <fifo> <out> <seconds> <llmctl> start <profile>
#
# The start process exists BEFORE the start intent that names it is written, and it runs `llmctl start` only after it
# reads the word `go` from <fifo>, which jev-place.sh writes only AFTER the registry write that holds the starting mark
# and the start intent naming THIS process (pid + start time). So every `llmctl start` that runs is named by a durable
# intent, and an intent names a process whose life covers the whole start:
#   * before `go`: this process waits on the gate. It opens <fifo> read-write (never blocks), reopens it read-only
#     through /proc/self/fd (never blocks: a writer exists) and closes the read-write descriptor, so jev-place.sh, which
#     holds <fifo> open read-write, is the ONLY writer. When jev-place.sh dies (SIGKILL, OOM) or cancels (it writes
#     `no`, or anything else), the read returns end-of-file or another word and this process exits 79 WITHOUT running
#     llmctl. It never waits for anything else, so its life before `go` never outlasts jev-place.sh.
#   * after `go`: it writes <out>.went (read by jev-place.sh: llmctl did run) and replaces itself (exec, same pid) with
#     `timeout --kill-after=2 <seconds> <llmctl> start <profile>`. `timeout` (GNU and uutils alike, measured
#     2026-11-17) makes its own process group, so the group id is this pid: the bounded llmctl call and every process
#     it forks stay in the process group named by the intent until they exit.
# jev-place.sh judges the start in flight while this pid (with its start time) lives or its process group has a member
# (child_running there). Exit codes: 79 the gate closed, llmctl was NOT run; otherwise the exit code of `timeout`
# (llmctl's own, or 124 / 137 on the time limit), exactly as the bounded call of earlier rounds.
# Honest limit (§11.4.6): a process that llmctl starts in ANOTHER process group or session (a systemd job, a daemon
# that calls setsid) is not seen by the group check; whether a real `llmctl start` leaves such work behind when its
# client is killed is UNCONFIRMED (gate-logic evidence only, the stub llmctl of tests/jev/fixtures/bin-place).
f="${1:-}"; o="${2:-}"; t="${3:-}"
[ -n "$f" ] && [ -n "$o" ] && [ -n "$t" ] && [ "$#" -ge 4 ] || exit 79
shift 3
exec 4<>"$f" || exit 79
exec 3</proc/self/fd/4 || exit 79
exec 4>&-
IFS= read -r w <&3 || exit 79
[ "$w" = go ] || exit 79
exec 3<&-
: > "$o.went" || exit 79
exec timeout --kill-after=2 "$t" "$@" >"$o" 2>"$o.err" </dev/null
