#!/usr/bin/env bash
# =============================================================================
# test_baseline_replay_r2_findings.sh -- permanent regression guard for the
# T048 restart ROUND-2 review of cycle/baseline_replay.sh
# (docs/qa/t048_restart_round2_20261008/V4_baseline.md, findings V4-1, V4-2,
# V4-4, V4-5, V4-8, V4-9, V4-10, V4-12 and the whitespace member of the V4-6
# class).
#
# Every case drives the REAL script through its real CLI against small,
# hermetic, throwaway git repos. Every case that stops the tool checks the
# PROCESS TABLE after the tool exits: nothing the tool started may still be
# running at the moment the tool's main pid is gone (a later sweep would hide a
# tool that exits before its cleanup finished, V4-12/N4).
#
# Defect classes (§11.4.276(C) inventory, see the fixer report):
#   D  host safety: processes the tool started that outlive it (V4-1 nested
#      process groups / sessions, V4-8 orphan watchdog sleep, V4-9 selfcheck
#      without traps), and disk exhaustion (V4-4 no lock + the object store's
#      filesystem never checked, V4-5 the refusal path never exercised).
#   A  a value read as something it is not: V4-2 (a gate's own exit >=129
#      recorded as "terminated by signal N"), whitespace-only ids read as ids.
#   C  evidence integrity: V4-10 (per-run logs of one phase must be distinct).
#   B  wrong-commit selection: the tie rule (N6) and the literal --grep (N10).
#
# Env:
#   FC_BR_UNDER_TEST  path of the baseline_replay.sh to test (default: the real
#                     file). The paired-mutation runner points this at a mutant.
#   R2_ONLY           space-separated case tags to run (default: all).
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
want() {
  [ -z "${R2_ONLY:-}" ] && return 0
  case " $R2_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}

WORK="$(mktemp -d)"
# Every process a case starts carries "r2t-$$" in its argv (exec -a or an
# argument), so leftovers can be found and reaped by name. §11.4.263: only a
# validated integer > 1 whose /proc cmdline still names this run's marker is
# ever signalled.
MARK="r2t-$$"
HOLDER_PID=""

# marker_pids <substring>: live (non-zombie) pids whose cmdline contains it,
# excluding this shell.
marker_pids() {
  local p st
  for p in /proc/[0-9]*; do
    p="${p#/proc/}"
    [ "$p" = "$$" ] && continue
    st="$(awk '{print $3}' "/proc/$p/stat" 2>/dev/null)" || continue
    [ -n "$st" ] && [ "$st" != Z ] || continue
    tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -qF -- "$1" && echo "$p"
  done
}
reap_marker() {
  local p
  for p in $(marker_pids "$MARK"); do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    [ "$p" -gt 1 ] && kill -KILL "$p" 2>/dev/null
  done
}
# sess_pids: live pids whose session id is $SESS_WANT (stat fields read after
# the last ') ' so a comm with spaces cannot shift them: state ppid pgrp session).
sess_pids() {
  local p s rest
  for p in /proc/[0-9]*; do
    p="${p#/proc/}"
    s="$(cat "/proc/$p/stat" 2>/dev/null)" || continue
    rest="${s##*) }"
    # shellcheck disable=SC2086 # rest is space-separated stat fields, split on purpose
    set -- $rest
    [ "${1:-}" = Z ] && continue
    [ "${4:-x}" = "$SESS_WANT" ] && echo "$p"
  done
}
# descendants_of <pid>: live descendants (by ppid chain, which setsid does not
# change), one per line as "pid cmdline".
descendants_of() {
  python3 - "$1" <<'PY2'
import os, sys
root = sys.argv[1]
ppid, cmd = {}, {}
for p in os.listdir("/proc"):
    if not p.isdigit():
        continue
    try:
        st = open("/proc/%s/stat" % p).read()
        f = st[st.rindex(") ") + 2:].split()
        if f[0] == "Z":
            continue
        ppid[p] = f[1]
        cmd[p] = open("/proc/%s/cmdline" % p, "rb").read().replace(b"\0", b" ").decode(errors="replace").strip()
    except (OSError, ValueError, IndexError):
        pass
out, todo = [], [root]
while todo:
    cur = todo.pop()
    for c, pp in ppid.items():
        if pp == cur:
            out.append(c); todo.append(c)
for c in out:
    print(c, cmd.get(c, ""))
PY2
}
cleanup_all() {
  reap_marker
  case "$HOLDER_PID" in ''|*[!0-9]*) ;; *) [ "$HOLDER_PID" -gt 1 ] && kill -KILL "$HOLDER_PID" 2>/dev/null ;; esac
  rm -rf "$WORK"
}
trap cleanup_all EXIT

# jget <json-file> <python-expr over d>: the JSON is read from the file; the
# expression is always a literal written in THIS test file (never data), so the
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
mk_repo() {
  mkdir -p "$1"; g init -q "$1"; echo hello >"$1/f.txt"
  g -C "$1" add f.txt; g -C "$1" commit -q -m "base commit"
}
wt_count() { git -C "$1" worktree list --porcelain 2>/dev/null | grep -c '^worktree '; }
alive() {
  local st
  st="$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" || return 1
  [ -n "$st" ] && [ "$st" != Z ]
}
wait_for_lines() { # <file> <n> <tenths>
  local i=0
  while [ "$i" -lt "$3" ]; do
    [ -f "$1" ] && [ "$(wc -l <"$1")" -ge "$2" ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
wait_gone() { # <pid> <tenths>
  local i=0
  while [ "$i" -lt "$2" ]; do
    alive "$1" || return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
# RBGS: run the script as the leader of a NEW session (setsid; no fork here,
# because the backgrounded subshell is not a process-group leader), so that $!
# is the script's main pid AND its session id: after it exits, `sess_pids $!`
# lists anything the script left behind in its own session (e.g. an orphaned
# watchdog `sleep`, V4-8).
RBGS() {
  local repo="$1" wtr="$2" out="$3"; shift 3
  exec setsid bash "$SCRIPT" replay --commit "$(git -C "$repo" rev-parse HEAD)" \
    --repo-root "$repo" --worktree-root "$wtr" --min-free-kb 0 --out "$out" "$@"
}
R() {
  local repo="$1" wtr="$2" out="$3"; shift 3
  bash "$SCRIPT" replay --commit "$(git -C "$repo" rev-parse HEAD)" \
    --repo-root "$repo" --worktree-root "$wtr" --min-free-kb 0 --out "$out" "$@"
}
leftover_sess() { SESS_WANT="$1"; sess_pids | tr '\n' ' '; }

[ -f "$SCRIPT" ] || { echo "NOT ok script under test not found: $SCRIPT"; exit 1; }
command -v setsid >/dev/null 2>&1 || { echo "NOT ok setsid(1) not found -- the session checks cannot run"; exit 1; }

# =============================================================================
# V4-1: a gate that starts children in their OWN process group (a nested
# `timeout`, as the real pre-build gate does 51 times) or their own SESSION
# (`setsid`) must not leave them running after the tool is stopped.
# =============================================================================
if want V4-1; then
  REPO="$WORK/v41"; mk_repo "$REPO"
  T="$MARK-v41"
  cat >"$WORK/v41_gate.sh" <<SH
#!/bin/bash
timeout 60 bash -c 'exec -a "$T-timeout-child" sleep 100' &
setsid bash -c 'exec -a "$T-setsid-child" sleep 100' &
echo x >>"$WORK/v41.calls"
wait
SH
  chmod +x "$WORK/v41_gate.sh"
  RBGS "$REPO" "$WORK/v41_wt" "$WORK/v41.json" --gate-cmd "$WORK/v41_gate.sh" --cold-runs 2 --warm-runs 0 --timeout-s 60 >/dev/null 2>&1 &
  MAIN=$!
  if wait_for_lines "$WORK/v41.calls" 1 100; then
    sleep 0.5
    BEFORE="$(marker_pids "$T" | wc -l)"
    kill -TERM "$MAIN"
    wait_gone "$MAIN" 250; wait "$MAIN" 2>/dev/null; mrc=$?
    AFTER_PIDS="$(marker_pids "$T" | tr '\n' ' ')"
    AFTER="$(marker_pids "$T" | wc -l)"
    SESS_LEFT="$(leftover_sess "$MAIN")"
    if [ "$BEFORE" -ge 3 ] && [ "$AFTER" = 0 ] && [ -z "$SESS_LEFT" ] && [ "$(wt_count "$REPO")" = 1 ] && [ "$mrc" = 143 ]; then
      ok "[V4-1] TERM to the main pid stops the gate AND its nested-timeout and setsid children ($BEFORE -> 0 processes, exit $mrc)"
    else
      bad "[V4-1] after TERM: gate-descendant processes before=$BEFORE after=$AFTER ($AFTER_PIDS) session-leftovers='$SESS_LEFT' worktrees=$(wt_count "$REPO") main-rc=$mrc -- children of the gate outlived the tool"
    fi
  else
    bad "[V4-1] the gate never started (setup failure)"; kill -TERM "$MAIN" 2>/dev/null; wait "$MAIN" 2>/dev/null
  fi
  reap_marker
fi

# =============================================================================
# V4-2: a gate that RAN and itself exited 255 / 130 is a genuine FAIL. Exit
# codes >= 129 cannot tell "exited 128+N" from "killed by signal N", so the tool
# must never claim a signal it did not itself deliver.
# =============================================================================
if want V4-2; then
  REPO="$WORK/v42"; mk_repo "$REPO"
  for code in 255 130 137; do
    printf '#!/bin/sh\nexit %s\n' "$code" >"$WORK/v42_$code.sh"; chmod +x "$WORK/v42_$code.sh"
    R "$REPO" "$WORK/v42_wt" "$WORK/v42_$code.json" --gate-cmd "$WORK/v42_$code.sh" --cold-runs 1 --warm-runs 0 >/dev/null 2>&1; rc=$?
    V="$(jget "$WORK/v42_$code.json" 'd["verdict_set"]["cold"]')"
    RS="$(jget "$WORK/v42_$code.json" 'd["runs"][0]["verdict_reason"]')"
    case "$RS" in *signal*) sig=1 ;; *) sig=0 ;; esac
    if [ "$rc" = 0 ] && [ "$V" = '["FAIL"]' ] && [ "$sig" = 0 ] && case "$RS" in *"exit $code"*) true ;; *) false ;; esac; then
      ok "[V4-2] a gate that itself exits $code is a FAIL ('$RS'), never an invented signal"
    else
      bad "[V4-2] gate exit $code: rc=$rc verdict_set=$V reason='$RS' -- a real FAIL was recorded as UNMEASURED / a signal the harness never sent"
    fi
  done
  R "$REPO" "$WORK/v42_wt" "$WORK/v42_det.json" --gate-cmd "$WORK/v42_255.sh" --cold-runs 1 --warm-runs 1 --determinism-check >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ] && [ "$(jget "$WORK/v42_det.json" 'd.get("deterministic")')" = true ]; then
    ok "[V4-2] an always-255 gate is deterministically FAIL (exit 0, deterministic=true)"
  else
    bad "[V4-2] always-255 gate --determinism-check: rc=$rc deterministic=$(jget "$WORK/v42_det.json" 'd.get("deterministic")')"
  fi
fi

# =============================================================================
# V4-5: the disk-floor refusal itself. --min-free-kb above the real free space
# must refuse with exit 4, print the real df numbers, and create no worktree.
# =============================================================================
if want V4-5; then
  REPO="$WORK/v45"; mk_repo "$REPO"
  HUGE=999999999999999
  bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/v45_wt" --min-free-kb "$HUGE" --gate-cmd true --cold-runs 1 --warm-runs 0 \
    --out "$WORK/v45.json" >/dev/null 2>"$WORK/v45.err"; rc=$?
  AVAIL="$(sed -n 's/.*: \([0-9][0-9]*\)KB available, \([0-9][0-9]*\)KB required.*/\1/p' "$WORK/v45.err" | head -1)"
  REQ="$(sed -n 's/.*: \([0-9][0-9]*\)KB available, \([0-9][0-9]*\)KB required.*/\2/p' "$WORK/v45.err" | head -1)"
  DF="$(df -Pk "$WORK/v45_wt" 2>/dev/null | awk 'NR==2{print $4}')"
  NEAR=0
  if [ -n "$AVAIL" ] && [ -n "$DF" ]; then
    D=$((AVAIL - DF)); [ "$D" -lt 0 ] && D=$((-D))
    [ "$D" -le 1048576 ] && NEAR=1   # within 1 GiB of a df taken a moment later
  fi
  LEFT="$(find "$WORK/v45_wt" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
  if [ "$rc" = 4 ] && [ "$REQ" = "$HUGE" ] && [ "$NEAR" = 1 ] && [ "$LEFT" = 0 ] && [ "$(wt_count "$REPO")" = 1 ] && [ ! -e "$WORK/v45.json" ]; then
    ok "[V4-5] --min-free-kb above the free space is refused (exit 4) with the real df numbers (${AVAIL}KB available), no worktree or log dir created"
  else
    bad "[V4-5] disk floor: rc=$rc available='$AVAIL' (df now $DF) required='$REQ' entries-under-worktree-root=$LEFT worktrees=$(wt_count "$REPO") report-written=$([ -e "$WORK/v45.json" ] && echo yes || echo no) -- the refusal path is broken ($(head -c 300 "$WORK/v45.err"))"
  fi
  # the git object store's filesystem has its own floor (V4-4): submodule
  # objects land under <git-common-dir>/worktrees/<n>/modules, not under
  # --worktree-root.
  bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/v45_wt" --min-free-kb 0 --min-free-kb-objects "$HUGE" --gate-cmd true \
    --cold-runs 1 --warm-runs 0 --out "$WORK/v45b.json" >/dev/null 2>"$WORK/v45b.err"; rc=$?
  LEFT="$(find "$WORK/v45_wt" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
  if [ "$rc" = 4 ] && grep -q "object store" "$WORK/v45b.err" && grep -q "${HUGE}KB required" "$WORK/v45b.err" && [ "$LEFT" = 0 ]; then
    ok "[V4-4] the filesystem of the git object store is checked too (exit 4 when it is short, nothing created)"
  else
    bad "[V4-4] object-store floor: rc=$rc entries=$LEFT -- the filesystem that receives submodule objects is never checked ($(head -c 300 "$WORK/v45b.err"))"
  fi
  # control: the same replay with both floors at 0 runs
  bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
    --worktree-root "$WORK/v45_wt" --min-free-kb 0 --min-free-kb-objects 0 --gate-cmd true \
    --cold-runs 1 --warm-runs 0 --out "$WORK/v45c.json" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ]; then
    ok "[V4-5] control: with both floors at 0 the same replay runs (exit 0)"
  else
    bad "[V4-5] control: the replay with both floors at 0 failed rc=$rc -- the refusals above prove nothing"
  fi
fi

# =============================================================================
# V4-4: one replay at a time per repository (the free-space check is only
# meaningful when nobody else is about to consume the same space).
# =============================================================================
if want V4-4; then
  REPO="$WORK/v44"; mk_repo "$REPO"
  LOCKF="$(git -C "$REPO" rev-parse --absolute-git-dir)/fc_baseline_replay.lock"
  flock -n "$LOCKF" bash -c "echo held >'$WORK/v44.held'; exec -a '$MARK-lockholder' sleep 30" &
  HOLDER_PID=$!
  if wait_for_lines "$WORK/v44.held" 1 50; then
    bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
      --worktree-root "$WORK/v44_wt" --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 0 \
      --out "$WORK/v44.json" >/dev/null 2>"$WORK/v44.err"; rc=$?
    LEFT="$(find "$WORK/v44_wt" -maxdepth 1 -name 'replay.*' 2>/dev/null | wc -l)"
    if [ "$rc" = 4 ] && grep -q "another baseline_replay" "$WORK/v44.err" && [ "$LEFT" = 0 ] && [ ! -e "$WORK/v44.json" ]; then
      ok "[V4-4] a second replay of the same repository is refused while the first holds the lock (exit 4, nothing created)"
    else
      bad "[V4-4] concurrent replay: rc=$rc worktrees-created=$LEFT -- two replays can pass the free-space check together ($(head -c 300 "$WORK/v44.err"))"
    fi
    # flock(1) runs its command as a child that inherits the locked fd: both
    # the flock process and that child (named $MARK-lockholder) must go.
    case "$HOLDER_PID" in ''|*[!0-9]*) ;; *) [ "$HOLDER_PID" -gt 1 ] && kill -KILL "$HOLDER_PID" 2>/dev/null ;; esac
    reap_marker
    wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""
    bash "$SCRIPT" replay --commit "$(git -C "$REPO" rev-parse HEAD)" --repo-root "$REPO" \
      --worktree-root "$WORK/v44_wt" --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 0 \
      --out "$WORK/v44b.json" >/dev/null 2>&1; rc=$?
    if [ "$rc" = 0 ]; then
      ok "[V4-4] control: once the lock is released the replay runs (exit 0)"
    else
      bad "[V4-4] control: replay after release failed rc=$rc"
    fi
  else
    bad "[V4-4] could not take the test lock (setup failure)"
  fi
fi

# =============================================================================
# V4-10: every run of one phase cites its OWN log, holding THAT run's output.
# =============================================================================
if want V4-10; then
  REPO="$WORK/v410"; mk_repo "$REPO"
  cat >"$WORK/v410_gate.sh" <<SH
#!/bin/bash
n=0
[ -f "$WORK/v410_ctr" ] && n=\$(cat "$WORK/v410_ctr")
n=\$((n + 1)); echo "\$n" >"$WORK/v410_ctr"
echo "run-output-\$n"
exit 0
SH
  chmod +x "$WORK/v410_gate.sh"
  R "$REPO" "$WORK/v410_wt" "$WORK/v410.json" --gate-cmd "$WORK/v410_gate.sh" --cold-runs 3 --warm-runs 2 >/dev/null 2>&1; rc=$?
  RES="$(python3 - "$WORK/v410.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
runs = d["runs"]
paths = [r["log_path"] for r in runs]
bad = []
if len(runs) != 5:
    bad.append("runs=%d" % len(runs))
if len(set(paths)) != len(paths):
    bad.append("shared log paths %s" % paths)
for i, r in enumerate(runs, 1):
    try:
        body = open(r["log_path"]).read()
    except OSError as e:
        bad.append("unreadable %s" % r["log_path"]); continue
    if body.strip() != "run-output-%d" % i:
        bad.append("%s/%d log holds %r, want run-output-%d" % (r["phase"], r["run_index"], body.strip(), i))
print("OK" if not bad else "; ".join(bad))
PY
)"
  if [ "$rc" = 0 ] && [ "$RES" = OK ]; then
    ok "[V4-10] 3 cold + 2 warm runs cite 5 distinct logs, each holding exactly its own run's output"
  else
    bad "[V4-10] per-run evidence: rc=$rc $RES"
  fi
fi

# =============================================================================
# V4-12 (N4) + V4-8 + V4-9: TERM to the main pid while the gate IGNORES TERM.
# When the main pid is gone, the gate must already be dead, the worktree gone,
# nothing left in the tool's session (no orphan watchdog sleep), and no temp
# file left in TMPDIR.
# =============================================================================
if want V4-12; then
  REPO="$WORK/v412"; mk_repo "$REPO"
  mkdir -p "$WORK/v412_tmp"
  T="$MARK-v412"
  {
    echo '#!/bin/bash'
    echo "trap '' TERM"
    echo "echo x >>\"$WORK/v412.calls\""
    echo "echo \$\$ >\"$WORK/v412.pid\""
    echo "exec -a \"$T-gate\" sleep 30"
  } >"$WORK/v412_gate.sh"
  chmod +x "$WORK/v412_gate.sh"
  TMPDIR="$WORK/v412_tmp" RBGS "$REPO" "$WORK/v412_wt" "$WORK/v412.json" --gate-cmd "$WORK/v412_gate.sh" --cold-runs 2 --warm-runs 0 --timeout-s 60 >/dev/null 2>&1 &
  MAIN=$!
  if wait_for_lines "$WORK/v412.calls" 1 100; then
    GPID="$(cat "$WORK/v412.pid")"
    kill -TERM "$MAIN"
    wait_gone "$MAIN" 300; wait "$MAIN" 2>/dev/null; mrc=$?
    # measured at the moment the main pid is gone -- no grace period
    GA=no; alive "$GPID" && GA=yes
    WTN="$(wt_count "$REPO")"
    DIRS="$(find "$WORK/v412_wt" -maxdepth 1 -type d -name 'replay.*' 2>/dev/null | wc -l)"
    SL="$(leftover_sess "$MAIN")"
    TMPN="$(find "$WORK/v412_tmp" -mindepth 1 2>/dev/null | wc -l)"
    CALLS="$(wc -l <"$WORK/v412.calls")"
    if [ "$GA" = no ] && [ "$WTN" = 1 ] && [ "$DIRS" = 0 ] && [ -z "$SL" ] && [ "$TMPN" = 0 ] && [ "$CALLS" = 1 ] && [ "$mrc" = 143 ]; then
      ok "[V4-12/N4] when the main pid exits, the TERM-ignoring gate is already dead, the worktree removed, nothing left in its session and no temp file left"
    else
      bad "[V4-12/N4] at main exit: gate alive=$GA worktrees=$WTN replay-dirs=$DIRS session-leftovers='$SL' tmp-entries=$TMPN gate-calls=$CALLS main-rc=$mrc -- the tool exited before its cleanup finished, or left processes/files behind"
    fi
  else
    bad "[V4-12/N4] the gate never started (setup failure)"; kill -TERM "$MAIN" 2>/dev/null; wait "$MAIN" 2>/dev/null
  fi
  reap_marker
fi

# =============================================================================
# V4-12 (N12): a SECOND signal to the replay subshell while its cleanup is still
# waiting for a TERM-ignoring gate must not let it exit early: when the main pid
# is gone, the gate must already be dead.
# =============================================================================
child_bash_of() {
  local c
  # shellcheck disable=SC2013 # the children file is one space-separated line of pids
  for c in $(cat "/proc/$1/task/$1/children" 2>/dev/null); do
    [ "$(cat "/proc/$c/comm" 2>/dev/null)" = bash ] && { echo "$c"; return 0; }
  done
  return 1
}
if want N12; then
  REPO="$WORK/n12"; mk_repo "$REPO"
  T="$MARK-n12"
  {
    echo '#!/bin/bash'
    echo "trap '' TERM"
    echo "echo x >>\"$WORK/n12.calls\""
    echo "echo \$\$ >\"$WORK/n12.pid\""
    echo "exec -a \"$T-gate\" sleep 30"
  } >"$WORK/n12_gate.sh"
  chmod +x "$WORK/n12_gate.sh"
  RBGS "$REPO" "$WORK/n12_wt" "$WORK/n12.json" --gate-cmd "$WORK/n12_gate.sh" --cold-runs 1 --warm-runs 0 --timeout-s 60 >/dev/null 2>&1 &
  MAIN=$!
  if wait_for_lines "$WORK/n12.calls" 1 100; then
    GPID="$(cat "$WORK/n12.pid")"
    SUB="$(child_bash_of "$MAIN")"
    case "$SUB" in ''|*[!0-9]*) SUB="" ;; esac
    if [ -n "$SUB" ] && [ "$SUB" -gt 1 ]; then
      kill -HUP "$SUB"; sleep 1; kill -HUP "$SUB" 2>/dev/null
    fi
    wait_gone "$MAIN" 300; wait "$MAIN" 2>/dev/null
    GA=no; alive "$GPID" && GA=yes
    if [ -n "$SUB" ] && [ "$GA" = no ] && [ "$(wt_count "$REPO")" = 1 ]; then
      ok "[V4-12/N12] a second HUP during cleanup does not end it early: the gate is dead when the tool exits"
    else
      bad "[V4-12/N12] second HUP during cleanup: subshell=$SUB gate alive at tool exit=$GA worktrees=$(wt_count "$REPO") -- the cleanup was cut short and the gate outlived the tool"
    fi
  else
    bad "[V4-12/N12] the gate never started (setup failure)"; kill -TERM "$MAIN" 2>/dev/null; wait "$MAIN" 2>/dev/null
  fi
  reap_marker
fi

# =============================================================================
# V4-9: the selfcheck subcommand is stoppable too: TERM during its timeout
# check leaves no process in its session and no temp file.
# =============================================================================
if want V4-9; then
  # HUP as well as TERM: bash runs its EXIT trap on a default-disposition TERM but
  # NOT on a default-disposition HUP, so only the HUP case can tell whether
  # selfcheck installed its own handlers.
  for SIG in TERM HUP; do
    case "$SIG" in TERM) WANT_RC=143 ;; HUP) WANT_RC=129 ;; esac
    TD="$WORK/v49_tmp_$SIG"; mkdir -p "$TD"
    TMPDIR="$TD" setsid bash "$SCRIPT" selfcheck --out "$WORK/v49_$SIG.json" >/dev/null 2>&1 &
    MAIN=$!
    # wait for selfcheck's last check (`sleep 5` under a 1 s timeout) to be
    # running, and signal at once: that sleep lives at most 1 s, so detection
    # must be fast (two pgrep calls, not a /proc scan) for a leak to be visible.
    i=0; SEEN=""
    while [ "$i" -lt 400 ]; do
      for c in $(pgrep -P "$MAIN" 2>/dev/null); do
        for q in $(pgrep -P "$c" -x sleep 2>/dev/null); do
          tr '\0' ' ' <"/proc/$q/cmdline" 2>/dev/null | grep -qx 'sleep 5 ' && SEEN="$q"
        done
      done
      [ -n "$SEEN" ] && break
      sleep 0.02; i=$((i + 1))
    done
    kill -s "$SIG" "$MAIN"
    wait_gone "$MAIN" 150; wait "$MAIN" 2>/dev/null; mrc=$?
    # first, before any slow scan: is the check's sleep still running?
    SLEEP_LEFT=no; [ -n "$SEEN" ] && alive "$SEEN" && SLEEP_LEFT=yes
    SL="$(leftover_sess "$MAIN")"
    TMPN="$(find "$TD" -mindepth 1 2>/dev/null | wc -l)"
    if [ -n "$SEEN" ] && [ "$SLEEP_LEFT" = no ] && [ -z "$SL" ] && [ "$TMPN" = 0 ] && [ "$mrc" = "$WANT_RC" ]; then
      ok "[V4-9] SIG$SIG during selfcheck stops its running check (no leftover sleep, nothing left in the session, no temp file, exit $mrc)"
    else
      bad "[V4-9] selfcheck under SIG$SIG: check-seen=${SEEN:-none} sleep-left=$SLEEP_LEFT session-leftovers='$SL' tmp-entries=$TMPN rc=$mrc (want $WANT_RC)"
    fi
  done
fi

# =============================================================================
# N6: on an exact author-time tie the first commit git log lists (the most
# recently committed) is kept -- the documented rule.
# =============================================================================
if want N6; then
  REPO="$WORK/n6"; mk_repo "$REPO"
  export GIT_AUTHOR_DATE="2026-07-01T10:00:00+00:00"
  echo a >>"$REPO/f.txt"; g -C "$REPO" add f.txt
  GIT_COMMITTER_DATE="2026-07-01T10:00:00+00:00" g -C "$REPO" commit -q -m "ATM-60 first"
  echo b >>"$REPO/f.txt"; g -C "$REPO" add f.txt
  GIT_COMMITTER_DATE="2026-07-01T11:00:00+00:00" g -C "$REPO" commit -q -m "ATM-60 second"
  unset GIT_AUTHOR_DATE
  WANT_SHA="$(git -C "$REPO" rev-parse HEAD)"
  bash "$SCRIPT" freeze --item ATM-60 --repo-root "$REPO" --out "$WORK/n6.json" >/dev/null 2>&1; rc=$?
  GOT="$(jget "$WORK/n6.json" 'd.get("commit")')"
  if [ "$rc" = 0 ] && [ "$GOT" = "$WANT_SHA" ]; then
    ok "[N6] an exact author-time tie keeps the first-listed (most recently committed) commit"
  else
    bad "[N6] tie rule: rc=$rc got=$GOT want=$WANT_SHA (subject $(jget "$WORK/n6.json" 'd.get("commit_subject")'))"
  fi
fi

# =============================================================================
# N10: the item id is searched as a LITERAL string (git log -F): an id holding a
# regex bracket must still find its own commit.
# =============================================================================
if want N10; then
  REPO="$WORK/n10"; mk_repo "$REPO"
  echo a >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "fix ATM[7] literal id"
  WANT_SHA="$(git -C "$REPO" rev-parse HEAD)"
  echo b >>"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "ATM7 decoy that a regex would match"
  bash "$SCRIPT" freeze --item 'ATM[7]' --repo-root "$REPO" --out "$WORK/n10.json" >/dev/null 2>&1; rc=$?
  GOT="$(jget "$WORK/n10.json" 'd.get("commit")')"
  if [ "$rc" = 0 ] && [ "$GOT" = "$WANT_SHA" ]; then
    ok "[N10] an id with regex metacharacters (ATM[7]) is matched literally to its own commit"
  else
    bad "[N10] literal id ATM[7]: rc=$rc got=$GOT want=$WANT_SHA -- the id was used as a regular expression"
  fi
fi

# =============================================================================
# WS: whitespace-only / whitespace-carrying item ids are not ids (V4-6 class).
# =============================================================================
if want WS; then
  REPO="$WORK/ws"; mk_repo "$REPO"
  bash "$SCRIPT" freeze --item '   ' --repo-root "$REPO" --out "$WORK/ws1.json" >/dev/null 2>&1; rc1=$?
  bash "$SCRIPT" freeze --item 'ATM-1 ATM-2' --repo-root "$REPO" --out "$WORK/ws2.json" >/dev/null 2>&1; rc2=$?
  python3 -c 'import json,sys; json.dump({"items":[{"item_id":" "}]}, open(sys.argv[1],"w"))' "$WORK/ws_sample.json"
  bash "$SCRIPT" replay-sample --sample "$WORK/ws_sample.json" --gate-cmd true --cold-runs 1 --warm-runs 0 \
    --repo-root "$REPO" --worktree-root "$WORK/ws_wt" --min-free-kb 0 --out "$WORK/ws3.json" >/dev/null 2>&1; rc3=$?
  if [ "$rc1" = 2 ] && [ "$rc2" = 2 ] && [ "$rc3" = 4 ] && [ ! -e "$WORK/ws1.json" ] && [ ! -e "$WORK/ws3.json" ]; then
    ok "[WS] whitespace-only / whitespace-carrying item ids are refused (freeze exit 2, replay-sample exit 4)"
  else
    bad "[WS] whitespace ids: freeze '   ' rc=$rc1, freeze 'ATM-1 ATM-2' rc=$rc2, replay-sample [' '] rc=$rc3 -- a blank id was searched as if it named an item"
  fi
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
