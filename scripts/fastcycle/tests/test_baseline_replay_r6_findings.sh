#!/usr/bin/env bash
# =============================================================================
# test_baseline_replay_r6_findings.sh -- permanent regression guard for the
# T048 restart round-1 review of cycle/baseline_replay.sh
# (docs/qa/t048_restart_round1_20261008/R6_baseline_replay.md, findings
# F3-F12, F14, F15, F18-F20).
#
# Every case drives the REAL script through its real CLI against small,
# hermetic, throwaway git repos (never this project's own multi-GB tree, never a
# real network): no case re-implements or text-extracts the logic it guards.
#
# Defect classes covered (the fixer's class inventory, §11.4.276(C)):
#   A  absence/failure read as a valid result -- F3 (git failure = "no commit"),
#      F7 (zero runs / within-run flake / UNMEASURED runs read as deterministic),
#      F8 (harness failure recorded as a gate FAIL), F12 (FC_OUT leaking into
#      internal emits), F18 (--timeout-s 0 disables the bound), --tree UNMEASURED
#      disabling the tree check.
#   B  wrong-commit selection -- F4 (lexical %aI compare across offsets).
#   C  evidence integrity -- F5 (data interpolated into Python source), F6
#      (per-run log names colliding), F9 (FAIL runs inside median_ms).
#   D  host safety -- F10 (disk floor 5x below the checkout size), F11 (gate /
#      submodule children surviving TERM/HUP).
#   E  unguarded fixes -- F14 (submodule reference update, host-tool compile +
#      symlink guard, protocol pins, replay-sample), F15 (GIT_ALLOW_PROTOCOL),
#      F20 (selfcheck never exercised the real run path).
#
# Env:
#   FC_BR_UNDER_TEST  path of the baseline_replay.sh to test (default: the real
#                     file). The paired-mutation runner points this at a mutant.
#   R6_ONLY           space-separated case tags to run (default: all), e.g.
#                     "F4 F7c". Lets the mutation runner run one case quickly.
# Exit: 0 every selected case held; 1 any NOT ok.
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }
want() { # want <tag>: is this case selected?
  [ -z "${R6_ONLY:-}" ] && return 0
  case " $R6_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}

WORK="$(mktemp -d)"
HTTP_PID=""
# Pids of test gate processes this file started; reaped at exit. Only ever a
# validated integer > 1 whose /proc cmdline still names this run's own work dir
# is signalled (§11.4.263: never a pgid/pid <= 1, never a stale reused pid).
STRAY_PIDS=""
cleanup_all() {
  local p
  for p in $STRAY_PIDS $HTTP_PID; do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    [ "$p" -gt 1 ] || continue
    if tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -qF "$WORK"; then
      kill -KILL "$p" 2>/dev/null
    fi
  done
  rm -rf "$WORK"
}
trap cleanup_all EXIT

# jget <json-file> <python-expr over d>: prints the expression value. The JSON
# data is read from the file (never interpolated into Python source); the
# expression is always a literal written in THIS test file, never data, so the
# eval() below evaluates only test-authored code.
jget() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("<unreadable>")
    sys.exit(0)
v = eval(sys.argv[2], {"d": d})
print(json.dumps(v) if not isinstance(v, str) else v)
PY
}

g() { git -c user.email=t@t.t -c user.name=t "$@"; }

# mk_repo <dir> : one-commit repo with f.txt
mk_repo() {
  mkdir -p "$1"
  g init -q "$1"
  echo hello >"$1/f.txt"
  g -C "$1" add f.txt
  g -C "$1" commit -q -m "base commit"
}

wt_count() { git -C "$1" worktree list --porcelain 2>/dev/null | grep -c '^worktree '; }

# alive <pid>: running and not a zombie
alive() {
  local st
  st="$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" || return 1
  [ -n "$st" ] && [ "$st" != Z ]
}

wait_for_lines() { # wait_for_lines <file> <n> <tenths>
  local i=0
  while [ "$i" -lt "$3" ]; do
    [ -f "$1" ] && [ "$(wc -l <"$1")" -ge "$2" ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

wait_gone() { # wait_gone <pid> <tenths>
  local i=0
  while [ "$i" -lt "$2" ]; do
    alive "$1" || return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

# replay helper: R <repo> <wtroot> <out> [extra args...]
# RBG: the same, but `exec`s the script so that, when the caller backgrounds it
# with `RBG ... &`, $! is the SCRIPT's own main shell pid (a backgrounded shell
# function would otherwise be a wrapper subshell of THIS test, and a signal sent
# to $! would never reach the script at all).
RBG() {
  local repo="$1" wtr="$2" out="$3"; shift 3
  exec bash "$SCRIPT" replay --commit "$(git -C "$repo" rev-parse HEAD)" \
    --repo-root "$repo" --worktree-root "$wtr" --min-free-kb 0 --out "$out" "$@"
}
R() {
  local repo="$1" wtr="$2" out="$3"; shift 3
  bash "$SCRIPT" replay --commit "$(git -C "$repo" rev-parse HEAD)" \
    --repo-root "$repo" --worktree-root "$wtr" --min-free-kb 0 --out "$out" "$@"
}

[ -f "$SCRIPT" ] || { echo "NOT ok script under test not found: $SCRIPT"; exit 1; }

# =============================================================================
# F3: a git failure must be BLIND (exit 4), never "no commit found" (exit 0).
# =============================================================================
if want F3; then
  NOTREPO="$WORK/f3_notrepo"; mkdir -p "$NOTREPO"
  OUT="$WORK/f3.json"
  bash "$SCRIPT" freeze --item ATM-1 --repo-root "$NOTREPO" --out "$OUT" >/dev/null 2>"$WORK/f3.err"; rc=$?
  if [ "$rc" = 4 ] && [ ! -s "$OUT" ]; then
    ok "[R6-F3] freeze against a non-repository is BLIND (exit 4, no UNMEASURED doc written): $(head -c 200 "$WORK/f3.err")"
  else
    bad "[R6-F3] freeze against a non-repository returned rc=$rc commit=$(jget "$OUT" 'd.get("commit")') -- a git failure was read as 'no commit found'"
  fi
  # control: a REAL repo with no matching subject IS an honest UNMEASURED, exit 0
  mk_repo "$WORK/f3_repo"
  bash "$SCRIPT" freeze --item ATM-404 --repo-root "$WORK/f3_repo" --out "$OUT" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ] && [ "$(jget "$OUT" 'd["commit"]')" = UNMEASURED ]; then
    ok "[R6-F3] control: a real repo with no subject match is an honest UNMEASURED (exit 0)"
  else
    bad "[R6-F3] control: a real repo with no subject match gave rc=$rc commit=$(jget "$OUT" 'd.get("commit")')"
  fi
  # replay must refuse an UNMEASURED tree instead of silently skipping the tree check
  bash "$SCRIPT" replay --commit "$(git -C "$WORK/f3_repo" rev-parse HEAD)" --tree UNMEASURED \
    --repo-root "$WORK/f3_repo" --worktree-root "$WORK/f3_wt" --min-free-kb 0 \
    --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$WORK/f3r.json" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 2 ]; then
    ok "[R6-F3] replay --tree UNMEASURED is refused (exit 2) -- the tree check cannot be disabled by an unresolved freeze"
  else
    bad "[R6-F3] replay --tree UNMEASURED returned rc=$rc -- an unresolved tree silently disabled the tree-match check"
  fi
fi

# =============================================================================
# F4: "latest by author date" must compare instants, not %aI strings.
# ATM-7 @ 12:00+05:00 (= 07:00Z) vs ATM-7 @ 09:00+00:00 (= 09:00Z): the
# 09:00Z commit is the later one. Its COMMITTER date is set EARLIER, so
# "first line of git log" and "lexical %aI" both pick the wrong commit.
# =============================================================================
if want F4; then
  REPO="$WORK/f4"; mk_repo "$REPO"
  echo b >>"$REPO/f.txt"; g -C "$REPO" add f.txt
  GIT_AUTHOR_DATE="2026-01-01T09:00:00+00:00" GIT_COMMITTER_DATE="2026-01-01T10:00:00+00:00" \
    g -C "$REPO" commit -q -m "ATM-7 the later instant"
  LATER="$(git -C "$REPO" rev-parse HEAD)"
  echo c >>"$REPO/f.txt"; g -C "$REPO" add f.txt
  GIT_AUTHOR_DATE="2026-01-01T12:00:00+05:00" GIT_COMMITTER_DATE="2026-01-01T11:00:00+00:00" \
    g -C "$REPO" commit -q -m "ATM-7 the earlier instant"
  OUT="$WORK/f4.json"
  bash "$SCRIPT" freeze --item ATM-7 --repo-root "$REPO" --out "$OUT" >/dev/null 2>&1; rc=$?
  GOT="$(jget "$OUT" 'd.get("commit")')"
  if [ "$rc" = 0 ] && [ "$GOT" = "$LATER" ] && [ "$(jget "$OUT" 'd.get("candidate_commit_count")')" = 2 ]; then
    ok "[R6-F4] freeze picks the latest author INSTANT across timezone offsets ($GOT)"
  else
    bad "[R6-F4] freeze picked $GOT (rc=$rc), expected the 09:00Z commit $LATER -- lexical %aI / log-order selection froze the wrong commit"
  fi
fi

# =============================================================================
# F5: values are passed to Python as DATA (argv/stdin), never spliced into source.
# =============================================================================
if want F5; then
  REPO="$WORK/f5"; mk_repo "$REPO"
  # shellcheck disable=SC1003 # the backslashes are literal on purpose
  S1='ATM-1 fix \t parse'
  # shellcheck disable=SC1003
  S2='ATM-2 regex a\N b'
  for s in "$S1" "$S2"; do
    echo x >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "$s"
  done
  for pair in "ATM-1|$S1" "ATM-2|$S2"; do
    id="${pair%%|*}"; subj="${pair#*|}"
    OUT="$WORK/f5_$id.json"
    bash "$SCRIPT" freeze --item "$id" --repo-root "$REPO" --out "$OUT" >/dev/null 2>"$WORK/f5.err"; rc=$?
    GOT="$(jget "$OUT" 'd.get("commit_subject")')"
    if [ "$rc" = 0 ] && [ "$GOT" = "$subj" ]; then
      ok "[R6-F5] subject with a literal backslash escape round-trips byte-exact ($id: '$GOT')"
    else
      bad "[R6-F5] $id: rc=$rc subject='$GOT' expected '$subj' -- the subject was decoded as Python source ($(head -c 200 "$WORK/f5.err"))"
    fi
  done
  # an item id carrying a quote must reach the JSON verbatim, not crash the emitter
  echo y >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "ATM-3'q quoted id"
  OUT="$WORK/f5_q.json"
  bash "$SCRIPT" freeze --item "ATM-3'q" --repo-root "$REPO" --out "$OUT" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ] && [ "$(jget "$OUT" 'd.get("item_id")')" = "ATM-3'q" ] && [ "$(jget "$OUT" 'd.get("commit_subject")')" = "ATM-3'q quoted id" ]; then
    ok "[R6-F5] an item id containing a quote is carried as data (item_id and subject exact)"
  else
    bad "[R6-F5] item id with a quote: rc=$rc item_id=$(jget "$OUT" 'd.get("item_id")')"
  fi
  # a worktree root containing a backslash escape must appear verbatim in log_path
  # shellcheck disable=SC1003
  WTR="$WORK/f5_wt\tdir"
  R "$REPO" "$WTR" "$WORK/f5r.json" --gate-cmd true --cold-runs 1 --warm-runs 0 >/dev/null 2>"$WORK/f5r.err"; rc=$?
  LP="$(jget "$WORK/f5r.json" 'd["runs"][0]["log_path"]')"
  case "$LP" in
    "$WTR"/*) good_lp=1 ;;
    *) good_lp=0 ;;
  esac
  if [ "$rc" = 0 ] && [ "$good_lp" = 1 ] && [ -f "$LP" ]; then
    ok "[R6-F5] a log path containing a literal backslash escape is recorded verbatim and exists ($LP)"
  else
    bad "[R6-F5] log path with a backslash: rc=$rc log_path='$LP' -- the rows JSON was decoded twice ($(head -c 200 "$WORK/f5r.err"))"
  fi
fi

# =============================================================================
# F6 + F7: determinism check -- evidence logs never overwrite each other, a
# within-run flake is NOT deterministic, zero runs are refused, the WARM phase
# is compared too, and a run that could not be measured is never "deterministic".
# =============================================================================
mk_counter_gate() { # mk_counter_gate <path> <counter> <python-expr over n deciding PASS>
  cat >"$1" <<SH
#!/bin/bash
n=0
[ -f "$2" ] && n=\$(cat "$2")
n=\$((n + 1))
echo "\$n" >"$2"
echo "call \$n"
python3 -c 'import sys; n=int(sys.argv[1]); sys.exit(0 if ($3) else 1)' "\$n"
SH
  chmod +x "$1"
}

if want F6; then
  REPO="$WORK/f6"; mk_repo "$REPO"
  mk_counter_gate "$WORK/f6_gate.sh" "$WORK/f6_ctr" "True"
  OUT="$WORK/f6.json"
  R "$REPO" "$WORK/f6_wt" "$OUT" --gate-cmd "$WORK/f6_gate.sh" --cold-runs 1 --warm-runs 1 --determinism-check >/dev/null 2>&1; rc=$?
  LOGS="$(find "$WORK/f6_wt/replay-logs" -type f -name '*.log' 2>/dev/null | sort)"
  NLOGS="$(printf '%s\n' "$LOGS" | grep -c . )"
  CALLS="$(find "$WORK/f6_wt/replay-logs" -type f -name '*.log' -exec cat {} + 2>/dev/null | sort | tr '\n' ',')"
  if [ "$rc" = 0 ] && [ "$NLOGS" = 4 ] && [ "$CALLS" = "call 1,call 2,call 3,call 4," ]; then
    ok "[R6-F6] determinism-check keeps all 4 per-run evidence logs distinct (none overwritten): $CALLS"
  else
    bad "[R6-F6] determinism-check left $NLOGS logs with contents '$CALLS' (rc=$rc) -- run 2 overwrote run 1's evidence"
  fi
fi

if want F7a; then
  REPO="$WORK/f7a"; mk_repo "$REPO"
  mk_counter_gate "$WORK/f7a_gate.sh" "$WORK/f7a_ctr" "n % 2 == 1"
  OUT="$WORK/f7a.json"
  R "$REPO" "$WORK/f7a_wt" "$OUT" --gate-cmd "$WORK/f7a_gate.sh" --cold-runs 2 --warm-runs 0 --determinism-check >/dev/null 2>&1; rc=$?
  if [ "$rc" = 1 ] && [ "$(jget "$OUT" 'd.get("deterministic")')" = false ]; then
    ok "[R6-F7a] a gate that alternates PASS/FAIL inside each invocation is reported NON-deterministic (exit 1)"
  else
    bad "[R6-F7a] an alternating PASS/FAIL gate gave rc=$rc deterministic=$(jget "$OUT" 'd.get("deterministic")') -- a set-per-phase comparison hid the flake"
  fi
fi

if want F7b; then
  REPO="$WORK/f7b"; mk_repo "$REPO"
  R "$REPO" "$WORK/f7b_wt" "$WORK/f7b.json" --gate-cmd true --cold-runs 0 --warm-runs 0 --determinism-check >/dev/null 2>&1; rc=$?
  R "$REPO" "$WORK/f7b_wt" "$WORK/f7b2.json" --gate-cmd true --cold-runs 0 --warm-runs 0 >/dev/null 2>&1; rc2=$?
  if [ "$rc" = 2 ] && [ "$rc2" = 2 ]; then
    ok "[R6-F7b] zero total runs are refused as a usage error (determinism-check rc=$rc, plain replay rc=$rc2)"
  else
    bad "[R6-F7b] zero runs accepted (determinism-check rc=$rc, plain replay rc=$rc2) -- a check over nothing cannot fail"
  fi
fi

if want F7c; then
  REPO="$WORK/f7c"; mk_repo "$REPO"
  # calls: 1=run1 cold, 2=run1 warm, 3=run2 cold, 4=run2 warm -> only warm differs
  mk_counter_gate "$WORK/f7c_gate.sh" "$WORK/f7c_ctr" "n != 4"
  OUT="$WORK/f7c.json"
  R "$REPO" "$WORK/f7c_wt" "$OUT" --gate-cmd "$WORK/f7c_gate.sh" --cold-runs 1 --warm-runs 1 --determinism-check >/dev/null 2>&1; rc=$?
  if [ "$rc" = 1 ] && [ "$(jget "$OUT" 'd.get("deterministic")')" = false ]; then
    ok "[R6-F7c] a difference in the WARM phase only is detected (exit 1)"
  else
    bad "[R6-F7c] a warm-only difference gave rc=$rc deterministic=$(jget "$OUT" 'd.get("deterministic")') -- only the cold phase was compared"
  fi
fi

if want F7d; then
  REPO="$WORK/f7d"; mk_repo "$REPO"
  OUT="$WORK/f7d.json"
  R "$REPO" "$WORK/f7d_wt" "$OUT" --gate-cmd "sleep 5" --timeout-s 1 --cold-runs 1 --warm-runs 0 --determinism-check >/dev/null 2>&1; rc=$?
  if [ "$rc" = 4 ] && [ "$(jget "$OUT" 'd.get("deterministic")')" = null ]; then
    ok "[R6-F7d] runs that could not be measured (timed out) give no determinism verdict (exit 4, deterministic=null)"
  else
    bad "[R6-F7d] two all-UNMEASURED invocations gave rc=$rc deterministic=$(jget "$OUT" 'd.get("deterministic")') -- 'could not measure' twice was read as deterministic"
  fi
fi

# =============================================================================
# F8: harness failures are never recorded as a gate FAIL; timeouts are UNMEASURED;
# a gate's OWN exit 124/127 is a genuine FAIL.
# =============================================================================
if want F8; then
  REPO="$WORK/f8"; mk_repo "$REPO"
  OUT="$WORK/f8a.json"
  R "$REPO" "$WORK/f8_wt" "$OUT" --gate-cmd nosuchcmd_r6_xyz --cold-runs 2 --warm-runs 0 >/dev/null 2>"$WORK/f8a.err"; rc=$?
  V="$(jget "$OUT" 'd["verdict_set"]["cold"]')"
  M="$(jget "$OUT" 'd["median_ms"]["cold"]')"
  N="$(jget "$OUT" 'len(d["runs"])')"
  if [ "$rc" = 4 ] && [ "$V" = '["HARNESS_ERROR"]' ] && [ "$M" = UNMEASURED ] && [ "$N" = 1 ]; then
    ok "[R6-F8] a gate command that does not exist is HARNESS_ERROR (exit 4, no median, stopped after the first such run)"
  else
    bad "[R6-F8] not-found gate: rc=$rc verdict_set=$V median=$M runs=$N -- a harness failure was recorded as gate data"
  fi
  printf '#!/bin/sh\nexit 0\n' >"$WORK/f8_noexec.sh"; chmod -x "$WORK/f8_noexec.sh"
  R "$REPO" "$WORK/f8_wt" "$WORK/f8b.json" --gate-cmd "$WORK/f8_noexec.sh" --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
  if [ "$rc" = 4 ] && [ "$(jget "$WORK/f8b.json" 'd["verdict_set"]["cold"]')" = '["HARNESS_ERROR"]' ]; then
    ok "[R6-F8] a non-executable gate file is HARNESS_ERROR (exit 4) -- the live 126-in-6ms case"
  else
    bad "[R6-F8] non-executable gate: rc=$rc verdict_set=$(jget "$WORK/f8b.json" 'd["verdict_set"]')"
  fi
  printf '#!/bin/sh\nexit 127\n' >"$WORK/f8_127.sh"; chmod +x "$WORK/f8_127.sh"
  printf '#!/bin/sh\nexit 124\n' >"$WORK/f8_124.sh"; chmod +x "$WORK/f8_124.sh"
  R "$REPO" "$WORK/f8_wt" "$WORK/f8c.json" --gate-cmd "$WORK/f8_127.sh" --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
  R "$REPO" "$WORK/f8_wt" "$WORK/f8d.json" --gate-cmd "$WORK/f8_124.sh" --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc2=$?
  if [ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ "$(jget "$WORK/f8c.json" 'd["verdict_set"]["cold"]')" = '["FAIL"]' ] \
     && [ "$(jget "$WORK/f8d.json" 'd["verdict_set"]["cold"]')" = '["FAIL"]' ]; then
    ok "[R6-F8] a gate that RAN and itself exited 127 or 124 is a genuine FAIL, not a harness error / timeout"
  else
    bad "[R6-F8] gate's own exit 127/124: rc=$rc/$rc2 sets=$(jget "$WORK/f8c.json" 'd["verdict_set"]')/$(jget "$WORK/f8d.json" 'd["verdict_set"]')"
  fi
fi

if want F8t; then
  REPO="$WORK/f8t"; mk_repo "$REPO"
  R "$REPO" "$WORK/f8t_wt" "$WORK/f8t.json" --gate-cmd "sleep 5" --timeout-s 1 --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ] && [ "$(jget "$WORK/f8t.json" 'd["verdict_set"]["cold"]')" = '["UNMEASURED"]' ] \
     && [ "$(jget "$WORK/f8t.json" 'd["median_ms"]["cold"]')" = UNMEASURED ]; then
    ok "[R6-F8t] a gate killed by --timeout-s is UNMEASURED and excluded from the median"
  else
    bad "[R6-F8t] timed-out gate: rc=$rc set=$(jget "$WORK/f8t.json" 'd["verdict_set"]') median=$(jget "$WORK/f8t.json" 'd["median_ms"]')"
  fi
fi

# =============================================================================
# F9: median_ms is computed over completed PASS runs only -- a crashed/FAILed run
# must never become part of the "gate speed" baseline.
# =============================================================================
if want F9; then
  REPO="$WORK/f9"; mk_repo "$REPO"
  cat >"$WORK/f9_gate.sh" <<SH
#!/bin/bash
n=0
[ -f "$WORK/f9_ctr" ] && n=\$(cat "$WORK/f9_ctr")
n=\$((n + 1)); echo "\$n" >"$WORK/f9_ctr"
[ "\$n" -le 2 ] && exit 2
sleep 0.8; exit 0
SH
  chmod +x "$WORK/f9_gate.sh"
  R "$REPO" "$WORK/f9_wt" "$WORK/f9.json" --gate-cmd "$WORK/f9_gate.sh" --cold-runs 3 --warm-runs 0 >/dev/null 2>&1; rc=$?
  M="$(jget "$WORK/f9.json" 'd["median_ms"]["cold"]')"
  if [ "$rc" = 0 ] && [ "$M" != UNMEASURED ] && [ "$M" -ge 700 ] 2>/dev/null; then
    ok "[R6-F9] median_ms uses the completed PASS run only (${M}ms), not the two fast crashes"
  else
    bad "[R6-F9] median_ms=$M (rc=$rc) -- two crashed (exit 2) runs were pooled into the gate-speed median"
  fi
fi

# =============================================================================
# F10: the default disk floor covers the checkout size the script itself documents
# (~49 GiB checkout + ~7.4 GiB submodules = 59139687 KiB rounded up).
# =============================================================================
if want F10; then
  REPO="$WORK/f10"; mk_repo "$REPO"
  bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/f10_wt" --gate-cmd true --cold-runs 1 --warm-runs 0 \
    --out "$WORK/f10.json" >/dev/null 2>"$WORK/f10.err"; rc=$?
  FLOOR=59139687
  if [ "$rc" = 0 ]; then
    USED="$(jget "$WORK/f10.json" 'd.get("min_free_kb")')"
  else
    USED="$(sed -n 's/.*KB available, \([0-9]*\)KB required.*/\1/p' "$WORK/f10.err")"
  fi
  if [ -n "$USED" ] && [ "$USED" -ge "$FLOOR" ] 2>/dev/null; then
    ok "[R6-F10] default --min-free-kb ($USED KiB) covers the documented ~49 GiB checkout + ~7.4 GiB submodules (>= $FLOOR) (rc=$rc)"
  else
    bad "[R6-F10] default --min-free-kb is '$USED' (rc=$rc), below the documented checkout size $FLOOR KiB -- the guard cannot prevent the hazard it documents"
  fi
fi

# =============================================================================
# F11: stopping the tool must stop the gate (and every later scheduled run).
# =============================================================================
mk_sleep_gate() { # mk_sleep_gate <path> <pidfile> <callsfile> [ignore-term]
  {
    echo '#!/bin/bash'
    [ "${4:-}" = ignore-term ] && echo "trap '' TERM"
    echo "echo x >>\"$3\""
    echo "echo \$\$ >\"$2\""
    echo "exec -a \"r6-test-sleep $WORK\" sleep 30"
  } >"$1"
  chmod +x "$1"
}

child_bash_of() { # first bash child of <pid>
  local c
  # shellcheck disable=SC2013 # the children file is one space-separated line of pids
  for c in $(cat "/proc/$1/task/$1/children" 2>/dev/null); do
    [ "$(cat "/proc/$c/comm" 2>/dev/null)" = bash ] && { echo "$c"; return 0; }
  done
  return 1
}

if want F11a; then
  REPO="$WORK/f11a"; mk_repo "$REPO"
  mk_sleep_gate "$WORK/f11a_gate.sh" "$WORK/f11a.pid" "$WORK/f11a.calls"
  RBG "$REPO" "$WORK/f11a_wt" "$WORK/f11a.json" --gate-cmd "$WORK/f11a_gate.sh" --cold-runs 3 --warm-runs 0 --timeout-s 60 >/dev/null 2>&1 &
  MAIN=$!
  if wait_for_lines "$WORK/f11a.calls" 1 100; then
    GPID="$(cat "$WORK/f11a.pid")"; STRAY_PIDS="$STRAY_PIDS $GPID"
    kill -TERM "$MAIN"
    wait_gone "$MAIN" 200; wait "$MAIN" 2>/dev/null; mrc=$?
    wait_gone "$GPID" 50
    sleep 1.5
    CALLS="$(wc -l <"$WORK/f11a.calls")"
    if ! alive "$GPID" && [ "$CALLS" = 1 ] && [ "$(wt_count "$REPO")" = 1 ] && [ "$mrc" = 143 ]; then
      ok "[R6-F11a] TERM to the main pid stops the running gate, starts no further scheduled run, removes the worktree (exit $mrc)"
    else
      bad "[R6-F11a] after TERM to the main pid: gate alive=$(alive "$GPID" && echo yes || echo no) gate-calls=$CALLS worktrees=$(wt_count "$REPO") main-rc=$mrc -- the replay kept running orphaned"
    fi
  else
    bad "[R6-F11a] the gate never started (setup failure)"; kill -TERM "$MAIN" 2>/dev/null; wait "$MAIN" 2>/dev/null
  fi
fi

if want F11b; then
  REPO="$WORK/f11b"; mk_repo "$REPO"
  mk_sleep_gate "$WORK/f11b_gate.sh" "$WORK/f11b.pid" "$WORK/f11b.calls"
  RBG "$REPO" "$WORK/f11b_wt" "$WORK/f11b.json" --gate-cmd "$WORK/f11b_gate.sh" --cold-runs 1 --warm-runs 0 --timeout-s 60 >/dev/null 2>&1 &
  MAIN=$!
  if wait_for_lines "$WORK/f11b.calls" 1 100; then
    GPID="$(cat "$WORK/f11b.pid")"; STRAY_PIDS="$STRAY_PIDS $GPID"
    SUB="$(child_bash_of "$MAIN")"
    case "$SUB" in ''|*[!0-9]*) SUB="" ;; esac
    if [ -n "$SUB" ] && [ "$SUB" -gt 1 ]; then kill -HUP "$SUB"; fi
    wait_gone "$GPID" 150
    wait_gone "$MAIN" 150; wait "$MAIN" 2>/dev/null
    if [ -n "$SUB" ] && ! alive "$GPID" && [ "$(wt_count "$REPO")" = 1 ]; then
      ok "[R6-F11b] HUP to the replay subshell kills the gate before removing its worktree (no gate left running in a deleted cwd)"
    else
      bad "[R6-F11b] after HUP to the replay subshell ($SUB): gate alive=$(alive "$GPID" && echo yes || echo no) worktrees=$(wt_count "$REPO")"
    fi
  else
    bad "[R6-F11b] the gate never started (setup failure)"; kill -TERM "$MAIN" 2>/dev/null; wait "$MAIN" 2>/dev/null
  fi
fi

if want F11c; then
  # A second HUP landing while the first HUP's cleanup is still waiting for a
  # TERM-ignoring gate must not abort the cleanup half-way.
  REPO="$WORK/f11c"; mk_repo "$REPO"
  mk_sleep_gate "$WORK/f11c_gate.sh" "$WORK/f11c.pid" "$WORK/f11c.calls" ignore-term
  RBG "$REPO" "$WORK/f11c_wt" "$WORK/f11c.json" --gate-cmd "$WORK/f11c_gate.sh" --cold-runs 1 --warm-runs 0 --timeout-s 60 >/dev/null 2>&1 &
  MAIN=$!
  if wait_for_lines "$WORK/f11c.calls" 1 100; then
    GPID="$(cat "$WORK/f11c.pid")"; STRAY_PIDS="$STRAY_PIDS $GPID"
    SUB="$(child_bash_of "$MAIN")"
    case "$SUB" in ''|*[!0-9]*) SUB="" ;; esac
    if [ -n "$SUB" ] && [ "$SUB" -gt 1 ]; then
      kill -HUP "$SUB"; sleep 1; kill -HUP "$SUB" 2>/dev/null
    fi
    wait_gone "$GPID" 250
    wait_gone "$MAIN" 250; wait "$MAIN" 2>/dev/null
    LEFT="$(find "$WORK/f11c_wt" -maxdepth 1 -type d -name 'replay.*' 2>/dev/null | wc -l)"
    if [ -n "$SUB" ] && ! alive "$GPID" && [ "$(wt_count "$REPO")" = 1 ] && [ "$LEFT" = 0 ]; then
      ok "[R6-F11c] a second HUP during cleanup does not abort it (TERM-ignoring gate killed, worktree removed)"
    else
      bad "[R6-F11c] second HUP during cleanup: gate alive=$(alive "$GPID" && echo yes || echo no) worktrees=$(wt_count "$REPO") leftover-dirs=$LEFT"
    fi
  else
    bad "[R6-F11c] the gate never started (setup failure)"; kill -TERM "$MAIN" 2>/dev/null; wait "$MAIN" 2>/dev/null
  fi
fi

# =============================================================================
# F12 + F14(replay-sample) + F5(replay-sample) + F6(cross-item): replay-sample
# end to end, under an ambient FC_OUT (the fc_common determinism-check env).
# =============================================================================
if want F12; then
  REPO="$WORK/f12"; mk_repo "$REPO"
  echo a >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "ATM-20 sampled item"
  C20="$(git -C "$REPO" rev-parse HEAD)"
  echo b >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "ATM-7'q quoted id"
  C7="$(git -C "$REPO" rev-parse HEAD)"
  echo c >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "ATM-21 ATM-22 one commit for two items"
  python3 - "$WORK/f12_sample.json" <<'PY'
import json, sys
json.dump({"items": [{"item_id": "ATM-20"}, {"item_id": "ATM-404"}, {"item_id": "ATM-7'q"},
                     {"item_id": "ATM-21"}, {"item_id": "ATM-22"}]}, open(sys.argv[1], "w"))
PY
  # shellcheck disable=SC2016 # ${FC_OUT-unset} must expand inside the GATE, not here
  printf '#!/bin/sh\necho "${FC_OUT-unset}" >>"%s"\nexit 0\n' "$WORK/f12_gate_env" >"$WORK/f12_gate.sh"
  chmod +x "$WORK/f12_gate.sh"
  FC_OUT="$WORK/f12_fcout.json" bash "$SCRIPT" replay-sample --sample "$WORK/f12_sample.json" \
    --gate-cmd "$WORK/f12_gate.sh" --cold-runs 1 --warm-runs 0 --repo-root "$REPO" \
    --worktree-root "$WORK/f12_wt" --min-free-kb 0 --out "$WORK/f12_out.json" >/dev/null 2>"$WORK/f12.err"; rc=$?
  D="$WORK/f12_fcout.json"
  SCHEMA="$(jget "$D" 'd.get("schema")')"
  S20="$(jget "$D" '[i for i in d["items"] if i["item_id"]=="ATM-20"][0]')"
  if [ "$rc" = 0 ] && [ "$SCHEMA" = baseline-replay-sample/v1 ] \
     && [ "$(jget "$D" '[i for i in d["items"] if i["item_id"]=="ATM-20"][0]["commit"]')" = "$C20" ] \
     && [ "$(jget "$D" '[i for i in d["items"] if i["item_id"]=="ATM-20"][0]["skipped"]')" = false ]; then
    ok "[R6-F12] under an ambient FC_OUT the top-level doc goes to FC_OUT and internal freezes are unaffected (ATM-20 replayed at $C20)"
  else
    bad "[R6-F12] under FC_OUT: rc=$rc schema=$SCHEMA ATM-20=$S20 -- FC_OUT leaked into the internal freeze emits ($(head -c 200 "$WORK/f12.err"))"
  fi
  if [ -f "$WORK/f12_gate_env" ] && [ "$(sort -u "$WORK/f12_gate_env")" = unset ]; then
    ok "[R6-F12] the gate command never inherits FC_OUT (it cannot clobber the tool's own report)"
  else
    bad "[R6-F12] the gate saw FC_OUT='$(sort -u "$WORK/f12_gate_env" 2>/dev/null | tr '\n' ' ')'"
  fi
  if true; then
    if [ "$(jget "$D" '[i for i in d["items"] if i["item_id"]=="ATM-404"][0]["skipped"]')" = true ] \
       && [ "$(jget "$D" '[i for i in d["items"] if i["item_id"]=="ATM-7'"'"'q"][0]["commit"]')" = "$C7" ]; then
      ok "[R6-F14s] replay-sample: an unmatched item is skipped with a reason; a quote-carrying id is replayed at its own commit"
    else
      bad "[R6-F14s] replay-sample items: $(jget "$D" '[(i["item_id"], i.get("skipped"), i.get("skip_reason")) for i in d["items"]]')"
    fi
    LD21="$(jget "$D" '[i for i in d["items"] if i["item_id"]=="ATM-21"][0].get("log_dir")')"
    LD22="$(jget "$D" '[i for i in d["items"] if i["item_id"]=="ATM-22"][0].get("log_dir")')"
    if [ -n "$LD21" ] && [ "$LD21" != None ] && [ "$LD21" != "$LD22" ] && [ -d "$LD21" ] && [ -d "$LD22" ]; then
      ok "[R6-F6] two items frozen to the SAME commit keep separate evidence log dirs"
    else
      bad "[R6-F6] two items frozen to the same commit share/lack a log dir ('$LD21' vs '$LD22')"
    fi
  fi
fi

# =============================================================================
# F14 / F15: submodule init through _fc_submodule_reference_update, served over
# a localhost dumb-HTTP server (file:// is pinned to never, so it cannot be the
# fixture transport). Proves (a) every submodule incl. a nested one is checked
# out, (b) the worktree's submodule object store borrows the main checkout's
# already-fetched store via an alternates entry (the R3-B1 reference fix), and
# (c) the protocol pins hold even under GIT_ALLOW_PROTOCOL / GIT_CONFIG_* env.
# =============================================================================
start_http() { # start_http <dir> -> sets HTTP_PID HTTP_URL
  python3 -u -m http.server --bind 127.0.0.1 --directory "$1" 0 >"$WORK/http.log" 2>&1 &
  HTTP_PID=$!
  local i=0 port=""
  while [ "$i" -lt 50 ]; do
    port="$(sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' "$WORK/http.log" | head -1)"
    [ -n "$port" ] && break
    sleep 0.1; i=$((i + 1))
  done
  HTTP_URL="http://127.0.0.1:$port"
  [ -n "$port" ]
}

if want F14sub || want F15; then
  SRV="$WORK/srv"; mkdir -p "$SRV"
  if start_http "$SRV"; then
    U="$HTTP_URL"
    mk_repo "$WORK/nwork"; g clone -q --bare "$WORK/nwork" "$SRV/nested.git"; git -C "$SRV/nested.git" update-server-info
    mk_repo "$WORK/swork"; echo s >"$WORK/swork/s.txt"; g -C "$WORK/swork" add s.txt
    g -C "$WORK/swork" submodule add -q "$U/nested.git" nested; g -C "$WORK/swork" commit -q -m "sub with nested"
    g clone -q --bare "$WORK/swork" "$SRV/sub.git"; git -C "$SRV/sub.git" update-server-info
    SUPER="$WORK/super"; mk_repo "$SUPER"
    g -C "$SUPER" submodule add -q "$U/sub.git" sub
    g -C "$SUPER" submodule update --init --recursive -q
    g -C "$SUPER" commit -q -m "ATM-30 super with submodules"
    SUBSTORE="$SUPER/.git/modules/sub/objects"
    cat >"$WORK/sub_gate.sh" <<SH
#!/bin/bash
test -f sub/s.txt || { echo "sub not checked out"; exit 1; }
test -f sub/nested/f.txt || { echo "nested not checked out"; exit 1; }
alt="\$(git -C sub rev-parse --absolute-git-dir)/objects/info/alternates"
grep -qxF "$SUBSTORE" "\$alt" || { echo "no alternates entry for $SUBSTORE in \$alt"; exit 1; }
exit 0
SH
    chmod +x "$WORK/sub_gate.sh"
    if want F14sub; then
      R "$SUPER" "$WORK/sub_wt" "$WORK/sub.json" --gate-cmd "$WORK/sub_gate.sh" --cold-runs 1 --warm-runs 0 --timeout-s 60 >/dev/null 2>"$WORK/sub.err"; rc=$?
      if [ "$rc" = 0 ] && [ "$(jget "$WORK/sub.json" 'd["verdict_set"]["cold"]')" = '["PASS"]' ]; then
        ok "[R6-F14sub] submodules (incl. nested) are initialised in the isolated worktree, borrowing the main checkout's object store"
      else
        bad "[R6-F14sub] submodule replay: rc=$rc verdict=$(jget "$WORK/sub.json" 'd.get("verdict_set")') log=$(cat "$(jget "$WORK/sub.json" 'd["runs"][0]["log_path"]')" 2>/dev/null | head -c 300) err=$(head -c 300 "$WORK/sub.err")"
      fi
    fi
    if want F15; then
      # a commit whose .gitmodules names a file:// submodule must be refused even
      # when the ambient environment tries to re-open the file protocol.
      FSUP="$WORK/fsuper"; mk_repo "$FSUP"
      g -C "$FSUP" -c protocol.file.allow=always submodule add -q "file://$WORK/nwork" fsub
      g -C "$FSUP" commit -q -m "ATM-31 file submodule"
      rm -rf "$FSUP/.git/modules/fsub"  # force a real clone attempt in the worktree
      GIT_ALLOW_PROTOCOL="file" R "$FSUP" "$WORK/f15_wt" "$WORK/f15a.json" --gate-cmd true --cold-runs 1 --warm-runs 0 --timeout-s 30 >/dev/null 2>&1; rca=$?
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
        R "$FSUP" "$WORK/f15_wt" "$WORK/f15b.json" --gate-cmd true --cold-runs 1 --warm-runs 0 --timeout-s 30 >/dev/null 2>&1; rcb=$?
      R "$FSUP" "$WORK/f15_wt" "$WORK/f15c.json" --gate-cmd true --cold-runs 1 --warm-runs 0 --timeout-s 30 >/dev/null 2>&1; rcc=$?
      if [ "$rca" = 4 ] && [ "$rcb" = 4 ] && [ "$rcc" = 4 ]; then
        ok "[R6-F15] a file:// submodule is refused (BLIND) with and without GIT_ALLOW_PROTOCOL=file / GIT_CONFIG_* overrides"
      else
        bad "[R6-F15] file:// submodule: GIT_ALLOW_PROTOCOL rc=$rca GIT_CONFIG_* rc=$rcb plain rc=$rcc (expected 4/4/4) -- an ambient env var re-opened the pinned protocol"
      fi
    fi
  else
    bad "[R6-F14sub/F15] could not start the localhost http fixture server"
  fi
fi

# =============================================================================
# F14: host-tool compile + its symlink-escape guard.
# =============================================================================
if want F14ht; then
  if command -v cc >/dev/null 2>&1; then
    REPO="$WORK/ht"; mk_repo "$REPO"; mkdir -p "$REPO/tools"
    printf '#include <stdio.h>\nint main(void){puts("hosttool-ok");return 0;}\n' >"$REPO/tools/t.c"
    g -C "$REPO" add tools/t.c; g -C "$REPO" commit -q -m "ATM-40 host tool"
    FC_REPLAY_HOSTTOOL_SRC=tools/t.c FC_REPLAY_HOSTTOOL_BIN=tools/t \
      R "$REPO" "$WORK/ht_wt" "$WORK/ht.json" --gate-cmd ./tools/t --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
    if [ "$rc" = 0 ] && [ "$(jget "$WORK/ht.json" 'd["verdict_set"]["cold"]')" = '["PASS"]' ]; then
      ok "[R6-F14ht] the caller-named host tool is compiled inside the worktree before the gate runs"
    else
      bad "[R6-F14ht] host-tool compile: rc=$rc verdict=$(jget "$WORK/ht.json" 'd.get("verdict_set")')"
    fi
    # directory escape: tools/ is a tracked symlink to a directory outside the worktree
    OUTSIDE="$WORK/outside_dir"; mkdir -p "$OUTSIDE"
    printf 'int main(void){return 0;}\n' >"$OUTSIDE/t.c"
    REPO="$WORK/ht2"; mk_repo "$REPO"; ln -s "$OUTSIDE" "$REPO/tools"
    g -C "$REPO" add tools; g -C "$REPO" commit -q -m "ATM-41 symlinked dir"
    FC_REPLAY_HOSTTOOL_SRC=tools/t.c FC_REPLAY_HOSTTOOL_BIN=tools/t \
      R "$REPO" "$WORK/ht2_wt" "$WORK/ht2.json" --gate-cmd true --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
    if [ "$rc" = 4 ] && [ ! -e "$OUTSIDE/t" ]; then
      ok "[R6-F14ht] a host-tool directory symlinked OUTSIDE the worktree is refused (BLIND), nothing written outside"
    else
      bad "[R6-F14ht] symlinked host-tool dir: rc=$rc outside-binary-written=$([ -e "$OUTSIDE/t" ] && echo yes || echo no)"
    fi
    # leaf escape: tools/t is a symlink to a file outside the worktree
    OUT2="$WORK/outside_leaf"; mkdir -p "$OUT2"; : >"$OUT2/victim"
    REPO="$WORK/ht3"; mk_repo "$REPO"; mkdir -p "$REPO/tools"
    printf 'int main(void){return 0;}\n' >"$REPO/tools/t.c"; ln -s "$OUT2/victim" "$REPO/tools/t"
    g -C "$REPO" add tools; g -C "$REPO" commit -q -m "ATM-42 symlinked leaf"
    FC_REPLAY_HOSTTOOL_SRC=tools/t.c FC_REPLAY_HOSTTOOL_BIN=tools/t \
      R "$REPO" "$WORK/ht3_wt" "$WORK/ht3.json" --gate-cmd true --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
    # The binary leaf is a dangling-or-not symlink: -x on it may be false, so the
    # compile step is reached; the guard must refuse rather than write through it.
    if [ "$rc" = 4 ] && [ ! -s "$OUT2/victim" ]; then
      ok "[R6-F14ht] a host-tool binary path that is a symlink leaf is refused (BLIND), the outside file untouched"
    else
      bad "[R6-F14ht] symlinked host-tool leaf: rc=$rc victim-size=$(wc -c <"$OUT2/victim")"
    fi
  else
    echo "SKIP [R6-F14ht] no C compiler (cc) on this host -- host-tool compile path not exercisable here"
  fi
fi

# =============================================================================
# F18: --timeout-s 0 would DISABLE timeout(1); it must be refused.
# =============================================================================
if want F18; then
  REPO="$WORK/f18"; mk_repo "$REPO"
  R "$REPO" "$WORK/f18_wt" "$WORK/f18.json" --gate-cmd true --cold-runs 1 --warm-runs 0 --timeout-s 0 >/dev/null 2>&1; rc=$?
  if [ "$rc" = 2 ]; then
    ok "[R6-F18] --timeout-s 0 is refused (exit 2)"
  else
    bad "[R6-F18] --timeout-s 0 accepted (rc=$rc) -- 'timeout 0s' runs the gate with no bound"
  fi
fi

# =============================================================================
# F19: a subject with glob characters round-trips (no pathname expansion).
# =============================================================================
if want F19; then
  REPO="$WORK/f19"; mk_repo "$REPO"
  SUBJ='ATM-50 fix [ab]* globs'
  echo z >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "$SUBJ"
  bash "$SCRIPT" freeze --item ATM-50 --repo-root "$REPO" --out "$WORK/f19.json" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ] && [ "$(jget "$WORK/f19.json" 'd.get("commit_subject")')" = "$SUBJ" ]; then
    ok "[R6-F19] a subject containing glob characters round-trips exactly"
  else
    bad "[R6-F19] glob subject: rc=$rc subject=$(jget "$WORK/f19.json" 'd.get("commit_subject")')"
  fi
fi

# =============================================================================
# F20: selfcheck exercises the REAL gate-run path (background run, timeout,
# exec failure), not only the pure classifier on true/false.
# =============================================================================
if want F20; then
  bash "$SCRIPT" selfcheck --out "$WORK/f20.json" >/dev/null 2>"$WORK/f20.err"; rc=$?
  NAMES="$(jget "$WORK/f20.json" 'sorted(c["name"] for c in d.get("checks", []) if c.get("ok") is True)')"
  case "$NAMES" in
    *exec_failure_harness_error*timeout_unmeasured*) has=1 ;;
    *) has=0 ;;
  esac
  if [ "$rc" = 0 ] && [ "$has" = 1 ]; then
    ok "[R6-F20] selfcheck runs real gates through the real run path: $NAMES"
  else
    bad "[R6-F20] selfcheck rc=$rc checks=$NAMES -- it never exercises the background/timeout/exec-failure run path"
  fi
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
