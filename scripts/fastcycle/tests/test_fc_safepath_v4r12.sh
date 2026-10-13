#!/usr/bin/env bash
# fastcycle-timeout-s: 900
# =============================================================================
# test_fc_safepath_v4r12.sh -- T048 V4 round 12 (round-5 review of the round-11 pack: NO-GO, V4R12-1 MINOR
# source-defect, V4R12-2 MINOR test-instrumentation, V4R12-3 process-doc, NIT). §11.4.276(E) STRUCTURAL round for the
# V4R11-1 class at the PARENT level: ONE trusted-parent rule (fc_supervisor.py _trusted_ok / _walk), used by the
# supervisor AND -- through `fc_supervisor.py safepath` (_fc_safe) -- by baseline_replay.sh. This file holds the rows
# that need the SHELL half or a real replay; the module-level rows are [R12*] in test_fc_supervisor_unit.sh.
#
# [R12LINT]          tests/check_safepath_census.py: every path operation of BOTH files under test is routed through
#                    the helpers, proved-private, or a closed, checked exemption -- the closure-by-construction guard.
#   [R12LINT-ctl-*]  the lint's own needles: a raw `os.unlink(path)` added to the module, a plain redirect into a path
#                    under an unproved variable, an unknown tag, a param tag on an unlisted variable -> each FAILS it.
# [R12PARITY-*]      the SHELL helper (_fc_safe check, extracted from the script under test) and the module (_walk)
#                    give the SAME verdict on every row of a table written from the RULE: ours 0755 / sticky / root's
#                    TMPDIR chain / a link of ours -> trusted; ours 0777 / another uid's 0755 / 1777 / a dir below one /
#                    another uid's link / a missing path -> refused.
# [R12CLI-*]         `_fc_safe write` (the shell's INTERRUPTED path) and `_fc_safe rmtree`: a planted symlink at the name,
#                    a 0777 directory, a parent another uid controls -> refused, the target untouched; control: written.
# [R12SH-plant]      THE REVIEWER'S REPRO, END TO END, as a RED row: --worktree-root whose replay-logs directory another
#                    (real, subordinate) uid owns 0777; during the first gate run that uid renames the run-log directory
#                    away and plants a symlink to a victim directory. Round 11 (ac99eba): the second run's log is written
#                    THROUGH the symlink (victim/cold_2.log). Round 12: the replay refuses (BLIND 4) before creating
#                    anything there; the victim stays empty.
# [R12SH-wtroot-foreign] [R12SH-tmpdir-foreign]  a --worktree-root / a TMPDIR another uid owns -> BLIND 4, nothing made.
# [R12SH-wtroot-sticky] a --worktree-root of ours mode 1777: a trusted PARENT, but a NAMESPACE must be ours alone -> 4.
# [R12SH-workerinit] a worker handed a temp directory of ours writable by others -> refused (BLIND 4) before any work.
# [R12SH-needle]     control: the same replay under trusted directories runs and writes its report (exit 0).
#
# Env: FC_BR_UNDER_TEST / FC_SUP_UNDER_TEST -- the files under test (the paired-mutation runner points them at a
#      replica); R12_ONLY -- space-separated row groups (LINT PARITY CLI SH).
# Exit: 0 every row held; 1 otherwise. A row that needs a subordinate uid and cannot get one prints SKIP (not counted).
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"
SUP="${FC_SUP_UNDER_TEST:-$FC/cycle/fc_supervisor.py}"
CENSUS="${FC_CENSUS_UNDER_TEST:-$HERE/check_safepath_census.py}"   # round 13: the census itself can be a mutant
[ -f "$SCRIPT" ] || { echo "NOT ok script under test not found: $SCRIPT"; exit 1; }
[ -f "$SUP" ] || { echo "NOT ok supervisor under test not found: $SUP"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }
want() {
  [ -z "${R12_ONLY:-}" ] && return 0
  case " $R12_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}
NS=(unshare --map-users=auto --map-groups=auto --map-root-user)
WORK="$(mktemp -d "${TMPDIR:-/tmp}/fc_r12.XXXXXX")"
chmod 755 "$WORK"            # traversable by the subordinate uid that plays "another user"
export FC_REPLAY_LOCK_DIR="$WORK/locks"
mkdir -p "$FC_REPLAY_LOCK_DIR"
cleanup() {
  "${NS[@]}" rm -rf "$WORK" >/dev/null 2>&1
  chmod -R u+rwx "$WORK" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT
foreign() { # chown each path to a subordinate uid (real: through a user namespace); 0 when all of them are foreign
  "${NS[@]}" chown -h 1000:1000 "$@" >/dev/null 2>&1 || return 1
  local p
  for p in "$@"; do [ "$(stat -c %u "$p")" != "$(id -u)" ] || return 1; done
  return 0
}
as_foreign() { # run a command as the subordinate uid (host uid 100999) -- the group stays ours so it can traverse
  "${NS[@]}" setpriv --reuid=1000 "$@"
}

# =============================================================================
if want LINT; then
  if out="$(FC_SUP_UNDER_TEST="$SUP" FC_BR_UNDER_TEST="$SCRIPT" python3 "$CENSUS" 2>&1)"; then
    ok "[R12LINT] every path operation of the files under test is routed / proved-private / a checked exemption: $(tail -1 <<<"$out" | cut -c1-160)"
  else
    bad "[R12LINT] $(grep -m3 '^VIOLATION' <<<"$out" | tr '\n' ' ' | cut -c1-400) ($(tail -1 <<<"$out" | cut -c1-120))"
  fi
  L="$WORK/lint"; mkdir -p "$L"
  # needle 1: a raw path operation added to the module
  python3 - "$SUP" "$L/sup_raw.py" <<'PY'
import sys
s = open(sys.argv[1]).read()
anchor = "def _gc_at(pfd, names, boot, held):\n    n = 0\n"
assert s.count(anchor) == 1
open(sys.argv[2], "w").write(s.replace(anchor, anchor + "    os.listdir('/tmp')\n"))
PY
  if FC_SUP_UNDER_TEST="$L/sup_raw.py" FC_BR_UNDER_TEST="$SCRIPT" python3 "$CENSUS" >"$L/o1" 2>&1; then
    bad "[R12LINT-ctl-py] a raw os.listdir('/tmp') added to the module was NOT flagged"
  else
    grep -q "^VIOLATION .* _gc_at os.listdir" "$L/o1" \
      && ok "[R12LINT-ctl-py] a raw os.listdir added to the module FAILS the lint ($(grep -m1 '_gc_at os.listdir' "$L/o1" | cut -c1-90))" \
      || bad "[R12LINT-ctl-py] the lint failed, but not on the injected call: $(grep -m2 VIOLATION "$L/o1")"
  fi
  # needle 2: a plain redirect into a path under an unproved variable (the round-5 INTERRUPTED shape)
  awk '{print} /^do_one_replay\(\) \{/ && !d {print "  printf x >\"$out_path/INTERRUPTED\" 2>/dev/null"; d=1}' "$SCRIPT" >"$L/br_raw.sh"
  if FC_SUP_UNDER_TEST="$SUP" FC_BR_UNDER_TEST="$L/br_raw.sh" python3 "$CENSUS" >"$L/o2" 2>&1; then
    bad "[R12LINT-ctl-sh] a plain redirect into \$out_path/INTERRUPTED was NOT flagged"
  else
    grep -q "^VIOLATION .* do_one_replay redirect>" "$L/o2" \
      && ok "[R12LINT-ctl-sh] a plain redirect into a path under an unproved variable FAILS the lint ($(grep -m1 'do_one_replay redirect>' "$L/o2" | cut -c1-90))" \
      || bad "[R12LINT-ctl-sh] the lint failed, but not on the injected redirect: $(grep -m2 VIOLATION "$L/o2")"
  fi
  # needle 3: an unknown exemption tag; needle 4: a param tag on a variable that is not listed
  sed 's/# safepath:devnull/# safepath:trustme/' "$SUP" >"$L/sup_tag.py"
  if FC_SUP_UNDER_TEST="$L/sup_tag.py" FC_BR_UNDER_TEST="$SCRIPT" python3 "$CENSUS" >"$L/o3" 2>&1; then
    bad "[R12LINT-ctl-tag] an unknown safepath tag was accepted"
  else
    grep -q "unknown safepath tag 'trustme'" "$L/o3" && ok "[R12LINT-ctl-tag] an exemption tag outside the closed set FAILS the lint" \
      || bad "[R12LINT-ctl-tag] failed for another reason: $(grep -m1 VIOLATION "$L/o3")"
  fi
  awk '{print} /^run_replay_isolated\(\) \{/ && !d {print "  # safepath:param"; print "  printf x >\"$commit\""; d=1}' "$SCRIPT" >"$L/br_param.sh"
  if FC_SUP_UNDER_TEST="$SUP" FC_BR_UNDER_TEST="$L/br_param.sh" python3 "$CENSUS" >"$L/o4" 2>&1; then
    bad "[R12LINT-ctl-param] a param tag on an unlisted variable was accepted"
  else
    grep -q "tagged param but" "$L/o4" && ok "[R12LINT-ctl-param] a param tag on a variable PARAMS does not list FAILS the lint" \
      || bad "[R12LINT-ctl-param] failed for another reason: $(grep -m1 VIOLATION "$L/o4")"
  fi
fi

# =============================================================================
# the shell half of the helper, extracted from the script under test, run with the supervisor next to it (exactly as
# the script itself runs it: $SCRIPT_DIR/fc_supervisor.py)
_FC_SUPERVISOR="$(dirname "$SCRIPT")/fc_supervisor.py"
eval "$(grep -m1 '^_fc_safe()' "$SCRIPT")"
declare -F _fc_safe >/dev/null || bad "[R12PARITY] _fc_safe() is not defined in the script under test"

if want PARITY; then
  P="$WORK/par"; mkdir -p "$P"; chmod 755 "$P"
  mkdir "$P/own755"; chmod 755 "$P/own755"
  mkdir "$P/own777"; chmod 777 "$P/own777"
  mkdir "$P/own1777"; chmod 1777 "$P/own1777"
  mkdir "$P/tgt"; ln -s "$P/tgt" "$P/mylink"
  mkdir "$P/f755" "$P/f1777" "$P/fmid" "$P/fmid/inner" "$P/fl"
  chmod 1777 "$P/f1777"; chmod 755 "$P/fmid/inner"
  ln -s "$P/tgt" "$P/fl/theirlink"
  HAVE_F=1
  foreign "$P/f755" "$P/f1777" "$P/fmid" "$P/fl/theirlink" || HAVE_F=0
  rows="own755:$P/own755:trusted own1777:$P/own1777:trusted rootsticky:${TMPDIR:-/tmp}:trusted mylink:$P/mylink:trusted"
  rows="$rows own777:$P/own777:refused missing:$P/nope/x:refused"
  if [ "$HAVE_F" = 1 ]; then
    rows="$rows f755:$P/f755:refused f1777:$P/f1777:refused fmid:$P/fmid/inner:refused flink:$P/fl/theirlink:refused"
  else
    echo "SKIP [R12PARITY-f755/-f1777/-fmid/-flink] no subordinate uid available -- not counted"
  fi
  for row in $rows; do
    id="${row%%:*}"; rest="${row#*:}"; path="${rest%:*}"; wantv="${rest##*:}"
    _fc_safe check "$path" >/dev/null 2>"$P/$id.err"; src=$?
    pyv="$(python3 -I - "$SUP" "$path" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("fcsup", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
try:
    fd, _ = m._walk(sys.argv[2]); m.os.close(fd); print("trusted")
except OSError:
    print("refused")
PY
)"
    case "$src" in 0) shv=trusted ;; 4) shv=refused ;; *) shv="rc=$src" ;; esac
    if [ "$shv" = "$pyv" ] && [ "$shv" = "$wantv" ]; then
      ok "[R12PARITY-$id] shell _fc_safe check and the module's _walk agree with the rule: $shv"
    else
      bad "[R12PARITY-$id] shell=$shv module=$pyv rule=$wantv ($(head -c 160 "$P/$id.err"))"
    fi
  done
fi

# =============================================================================
if want CLI; then
  C="$WORK/cli"; mkdir -p "$C"; chmod 755 "$C"
  mkdir -m 700 "$C/ok"
  _fc_safe write --text "hello" "$C/ok" INTERRUPTED >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(cat "$C/ok/INTERRUPTED" 2>/dev/null)" = hello ] \
    && ok "[R12CLI-write-needle] control: _fc_safe write into a 0700 directory of ours writes the text" \
    || bad "[R12CLI-write-needle] rc=$rc content=$(cat "$C/ok/INTERRUPTED" 2>/dev/null)"
  mkdir -m 700 "$C/link"; mkdir "$C/victim"; ln -s "$C/victim/INTERRUPTED" "$C/link/INTERRUPTED"
  _fc_safe write --text "x" "$C/link" INTERRUPTED >/dev/null 2>&1; rc=$?
  [ "$rc" = 4 ] && [ ! -e "$C/victim/INTERRUPTED" ] \
    && ok "[R12CLI-write-link] a symlink planted at the name -> refused (4), nothing created through it" \
    || bad "[R12CLI-write-link] rc=$rc victim created=$([ -e "$C/victim/INTERRUPTED" ] && echo yes || echo no)"
  mkdir "$C/d777"; chmod 777 "$C/d777"
  _fc_safe write --text "x" "$C/d777" INTERRUPTED >/dev/null 2>&1; rc=$?
  [ "$rc" = 4 ] && [ ! -e "$C/d777/INTERRUPTED" ] \
    && ok "[R12CLI-write-dirmode] a directory of ours writable by others (0777) -> refused (4), nothing written" \
    || bad "[R12CLI-write-dirmode] rc=$rc"
  mkdir "$C/fpar"; mkdir -m 700 "$C/fpar/run"; chmod 777 "$C/fpar"
  if foreign "$C/fpar"; then
    _fc_safe write --text "x" "$C/fpar/run" INTERRUPTED >/dev/null 2>&1; rc=$?
    [ "$rc" = 4 ] && [ ! -e "$C/fpar/run/INTERRUPTED" ] \
      && ok "[R12CLI-write-parent] a 0700 directory of ours whose PARENT another uid owns -> refused (4)" \
      || bad "[R12CLI-write-parent] rc=$rc"
  else
    echo "SKIP [R12CLI-write-parent] no subordinate uid available -- not counted"
  fi
  mkdir -p "$C/tree/sub" "$C/keep"; echo k >"$C/keep/k"; ln -s "$C/keep" "$C/tree/sub/lnk"
  _fc_safe rmtree "$C/tree" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ ! -e "$C/tree" ] && [ "$(cat "$C/keep/k")" = k ] \
    && ok "[R12CLI-rmtree] _fc_safe rmtree removes a tree holding a symlink to elsewhere; the target is untouched" \
    || bad "[R12CLI-rmtree] rc=$rc tree gone=$([ -e "$C/tree" ] && echo no || echo yes)"
fi

# =============================================================================
g() { git -c user.email=t@t.t -c user.name=t "$@"; }
mk_repo() { mkdir -p "$1"; g init -q "$1"; echo hello >"$1/f.txt"; g -C "$1" add f.txt; g -C "$1" commit -q -m "base commit"; }
if want SH; then
  S="$WORK/sh"; mkdir -p "$S"; chmod 755 "$S"
  REPO="$S/repo"; mk_repo "$REPO"
  HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
  # ---- needle ----
  WTN="$S/wt_needle"
  bash "$SCRIPT" replay --commit "$HEAD_SHA" --repo-root "$REPO" --worktree-root "$WTN" --min-free-kb 0 \
    --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/needle.json" >/dev/null 2>"$S/needle.err"; rc=$?
  [ "$rc" = 0 ] && [ -s "$S/needle.json" ] \
    && ok "[R12SH-needle] control: a replay under trusted directories runs and writes its report (exit 0)" \
    || bad "[R12SH-needle] rc=$rc report=$([ -s "$S/needle.json" ] && echo yes || echo no) $(head -c 300 "$S/needle.err")"
  # ---- the reviewer's repro, end to end (RED on ac99eba) ----
  WTR="$S/wtr"; mkdir -p "$WTR/replay-logs"; chmod 755 "$WTR"; chmod 777 "$WTR/replay-logs"
  VICTIM="$S/victim"; mkdir "$VICTIM"; chmod 777 "$VICTIM"
  if foreign "$WTR/replay-logs"; then
    cat >"$S/gate.sh" <<'GATE'
#!/bin/bash
# the gate is innocent; ANOTHER uid acts while it runs: it swaps every run-log directory under the replay-logs
# directory it owns for a symlink to the victim (once)
[ -e "$R12_STATE/swapped" ] && exit 0
: >"$R12_STATE/swapped"
for d in "$R12_RL"/*.*; do
  case "$d" in *.moved) continue ;; esac
  unshare --map-users=auto --map-groups=auto --map-root-user setpriv --reuid=1000 \
    sh -c 'mv "$1" "$1.moved" && ln -s "$2" "$1"' sh "$d" "$R12_VICTIM"
done
exit 0
GATE
    mkdir -p "$S/state"
    R12_STATE="$S/state" R12_RL="$WTR/replay-logs" R12_VICTIM="$VICTIM" \
      bash "$SCRIPT" replay --commit "$HEAD_SHA" --repo-root "$REPO" --worktree-root "$WTR" --min-free-kb 0 \
      --gate-cmd "bash $S/gate.sh" --cold-runs 2 --warm-runs 0 --out "$S/plant.json" >/dev/null 2>"$S/plant.err"; rc=$?
    through="$(ls -A "$VICTIM" 2>/dev/null | tr '\n' ' ')"
    made="$(ls -A "$WTR/replay-logs" 2>/dev/null | tr '\n' ' ')"
    if [ -z "$through" ] && [ -z "$made" ] && [ "$rc" = 4 ] && grep -q "trusted-parent rule" "$S/plant.err"; then
      ok "[R12SH-plant] a replay-logs directory another uid owns (0777): the replay refuses (BLIND 4, the trusted-parent rule) before creating anything in it; nothing reaches the victim"
    else
      bad "[R12SH-plant] rc=$rc written THROUGH the planted symlink into the victim: [${through}] made in the foreign directory: [${made}] ($(grep -m1 -i 'blind\|trusted' "$S/plant.err" | cut -c1-160))"
    fi
  else
    echo "SKIP [R12SH-plant] no subordinate uid available -- not counted"
  fi
  # ---- a --worktree-root another uid owns ----
  WTF="$S/wtf"; mkdir "$WTF"; chmod 777 "$WTF"
  if foreign "$WTF"; then
    bash "$SCRIPT" replay --commit "$HEAD_SHA" --repo-root "$REPO" --worktree-root "$WTF" --min-free-kb 0 \
      --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/wtf.json" >/dev/null 2>"$S/wtf.err"; rc=$?
    [ "$rc" = 4 ] && [ -z "$(ls -A "$WTF")" ] \
      && ok "[R12SH-wtroot-foreign] a --worktree-root another uid owns (0777) -> BLIND 4, nothing created in it" \
      || bad "[R12SH-wtroot-foreign] rc=$rc made=[$(ls -A "$WTF" | tr '\n' ' ')] $(head -c 200 "$S/wtf.err")"
  else
    echo "SKIP [R12SH-wtroot-foreign] no subordinate uid available -- not counted"
  fi
  # ---- a --worktree-root of ours that is sticky + world-writable: trusted as a PARENT, but not this user's ALONE ----
  WTS="$S/wts"; mkdir "$WTS"; chmod 1777 "$WTS"
  bash "$SCRIPT" replay --commit "$HEAD_SHA" --repo-root "$REPO" --worktree-root "$WTS" --min-free-kb 0 \
    --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/wts.json" >/dev/null 2>"$S/wts.err"; rc=$?
  [ "$rc" = 4 ] && [ -z "$(ls -A "$WTS")" ] && grep -q "trusted-parent rule" "$S/wts.err" \
    && ok "[R12SH-wtroot-sticky] a --worktree-root of ours that is 1777 (others may create names in it) -> BLIND 4: a namespace must be this user's ALONE" \
    || bad "[R12SH-wtroot-sticky] rc=$rc made=[$(ls -A "$WTS" | tr '\n' ' ')] $(head -c 200 "$S/wts.err")"
  # ---- a TMPDIR another uid owns ----
  TF="$S/tmpf"; mkdir "$TF"; chmod 777 "$TF"
  if foreign "$TF"; then
    TMPDIR="$TF" bash "$SCRIPT" replay --commit "$HEAD_SHA" --repo-root "$REPO" --worktree-root "$S/wt_tf" \
      --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 0 --out "$S/tf.json" >/dev/null 2>"$S/tf.err"; rc=$?
    [ "$rc" = 4 ] && [ -z "$(ls -A "$TF")" ] \
      && ok "[R12SH-tmpdir-foreign] a TMPDIR another uid owns (0777) -> BLIND 4, no temp / state directory made in it" \
      || bad "[R12SH-tmpdir-foreign] rc=$rc made=[$(ls -A "$TF" | tr '\n' ' ')] $(head -c 200 "$S/tf.err")"
  else
    echo "SKIP [R12SH-tmpdir-foreign] no subordinate uid available -- not counted"
  fi
  # ---- the worker's own proof of its temp directory ----
  WT7="$S/fc_baseline_replay.w777"; mkdir "$WT7"; chmod 777 "$WT7"
  WS7="$S/fc_baseline_replay.state.w777"; mkdir -m 700 "$WS7"
  # a direct child of THIS shell: its parent pid is $$, which is what the worker checks against FC_BR_SUPERVISOR_PID
  FC_BR_SUPERVISED=1 FC_BR_SUPERVISOR_PID=$$ FC_BR_TMPDIR="$WT7" FC_BR_STATEDIR="$WS7" \
    bash "$SCRIPT" selfcheck --out "$S/w7.json" >/dev/null 2>"$S/w7.err"; rc=$?
  [ "$rc" = 4 ] && grep -q "trusted-parent rule" "$S/w7.err" && [ ! -e "$S/w7.json" ] \
    && ok "[R12SH-workerinit] a worker handed a temp directory of ours writable by others (0777) refuses (BLIND 4) before any work" \
    || bad "[R12SH-workerinit] rc=$rc $(head -c 200 "$S/w7.err")"
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
