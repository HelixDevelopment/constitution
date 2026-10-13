#!/usr/bin/env bash
# fastcycle-timeout-s: 900
# test_foundational_mutations.sh -- T013 paired 1.1 mutations for the fastcycle foundation.
# Purpose : prove T007/T009/T011 are load-bearing: each mutation neuters ONE decision in a
#           scratch COPY of the tree and the paired test MUST flip to FAIL.
# Usage   : bash test_foundational_mutations.sh   (exit 0 = control green + every mutation caught; 1 = a control or mutation check failed; 2 = HUP/INT/TERM received)
# Safety  : mutates only mktemp copies; the real tree is never touched (11.4.84).
# Controls: the unmutated copy must PASS each owning test first (one control run per DISTINCT
#           test file, not per mutation); each mutation must actually change the file (cmp), so a
#           sed that matched nothing cannot read as "caught" (11.4.273). A mutated run's non-zero
#           exit alone is NOT sufficient to call a mutation "caught" (round-11 remediation,
#           MINOR-6): every mut() call also carries an EXPECTED-MARKER -- a literal fixed string
#           that must appear in THAT check's own FAIL/NOT-ok output line (a "FAIL[N]:"/"PASS[N]:"
#           numbered-check prefix is first normalised to a bare "FAIL:"/"PASS:" one, so no marker
#           ever has to encode a check's own shiftable numeric index) -- so a mutation counts as
#           caught only when the run failed for the SPECIFIC reason it targets, never merely
#           "something, somewhere, exited non-zero" (indistinguishable from an unrelated flake or a
#           transient host-load failure -- the exact class of bug this same round fixed elsewhere,
#           see IMPORTANT-2 in lib/host_guard.sh).
# Cost    : the 6 controls + 15 mutated runs are independent jobs on separate tree copies, run in
#           parallel bounded by lib/host_guard.sh (12.6/12.12; falls back to serial if the guard
#           cannot answer). Mutated runs of the harness test use FC_TEST_FAILFAST=1 (stop at the
#           first failure; a caught mutation needs only one).
# M7/M8   : test_foundational_mutations_kill_tree.sh and its sibling
#           test_foundational_mutations_descendants_filter.sh extract+source this driver's OWN
#           kill_tree() / descendants() SEPARATELY (each stubbing out the OTHER function -- a
#           shimmed ps/kill, never a real signal -- 11.4.263) and independently prove (M7)
#           kill_tree()'s own TERM/KILL-stage pid<=1 guard is load-bearing (round 8 left it
#           UNPINNED) AND (M8) descendants()'s own closure-membership pid<=1 filter is
#           load-bearing (its regression coverage was ADDED here: a combined test of both
#           functions together let a regression in EITHER one hide behind the OTHER's still-correct
#           guard -- killed here without touching a real process).
# M12     : test_foundational_mutations_killtree_root_guard.sh (round-11 remediation, IMPORTANT-3)
#           pins kill_tree()'s ROOT-argument guard chain directly -- by calling kill_tree with
#           root=1/0/-1 itself, never merely as one of the descendant pids the M7/M8/M11 tests
#           above exercise -- because neither those, nor D6 in test_run_all.sh (whose roots come
#           from `jobs -rp`, always > 1 in practice), ever drives kill_tree's OWN root argument
#           through the 0/1 boundary that guard exists to enforce.
# M13/M14 : lib/host_guard.sh's exhaust()/unreadable() precedence (T014 round-10 BLOCKING-1) has its
#           OWN two guards independently pinned here: M13 weakens unreadable()'s early-return on an
#           already-recorded *_exhausted reason (order (a): exhausted-then-unreadable would
#           otherwise relax N back up from 0 to 1); M14 weakens exhaust()'s guard to ALSO defer to
#           an already-recorded unreadable_* reason (order (b): unreadable-then-exhausted would
#           otherwise never let the later, correctly-confirmed exhaustion override it). Both are
#           caught by tests/test_host_guard_red.sh's own T014/B1 order-(a)/order-(b) regression
#           checks.
# M15     : lib/fc_common.py's _leader_reap_honest() (T014 round-11 BLOCKING-1, the WNOWAIT
#           reap-handoff belt-and-suspenders layer) weakened to always report "honest" even on a
#           genuine ChildProcessError (the SIGCHLD-inherited-as-SIG_IGN hazard) is caught by
#           tests/test_fc_common_red.sh's own round-8 belt-and-suspenders check -- NOT by its
#           sibling CLI-level round-8 check, which this mutation alone does not affect (the
#           _run_bounded SIGCHLD reset that check exercises end-to-end already prevents the hazard
#           from ever occurring in that specific scenario, so _leader_reap_honest's OWN independent
#           detection role there never gets exercised regardless of what this mutation does to it --
#           verified directly: removing the SIGCHLD reset line ALONE reproduces the identical,
#           still-honest NO_HONEST_VERDICT outcome via this same belt-and-suspenders detection and is
#           therefore NOT a discriminating mutation on its own -- registered here as the mutation
#           that IS caught, not the one first suggested).
# Bound   : the `fastcycle-timeout-s` header above (read by run_all.sh) is 900 s. Basis: measured
#           2026-09-27 on the 64-CPU dev host at load average ~40: the previous serial form took
#           425 s (12 full test runs), i.e. it overran the 240 s default; the parallel form
#           measured 68 s at load average ~38 (2026-09-27, evidence in
#           qa-results/fastcycle/foundational/remediation/round6_harness_green.txt). 900 s is
#           >2x the old serial worst case and >13x the parallel measurement: a bound, not a target.
# shellcheck disable=SC2016  # file-wide: every `mut` line's 5th argument is a single-quoted sed
# expression whose $-vars name a symbol in the MUTATED file, not this script -- they must stay
# literal (never expand here) to be passed through to sed intact; verified this directive's
# file-wide scope works correctly even placed after this header/before the first statement.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
# Signals (R7-F3): a HUP/INT/TERM takes every RUNNING job AND its whole descendant tree (the owning tests, their
# `timeout` children, ...) down: TERM first, then KILL after a 3 s grace, so nothing keeps running on the deleted
# scratch copies. Only pids that are plain integers > 1 are ever signalled (11.4.263). Exit 2 after a signal.
# shellcheck disable=SC2329  # sed-extracted+sourced by tests/test_foundational_mutations_descendants_filter.sh
descendants() { ps -eo pid=,ppid= 2>/dev/null | awk -v r="$1" '{ pp[$1] = $2; o[NR] = $1 }
  END { w[r] = 1; ch = 1; while (ch) { ch = 0; for (i = 1; i <= NR; i++) { q = o[i]; if (!(q in w) && (pp[q] in w) && q ~ /^[0-9]+$/ && q + 0 > 1) { w[q] = 1; ch = 1 } } } for (q in w) print q }'; }
# shellcheck disable=SC2329  # sed-extracted+sourced by tests/test_foundational_mutations_kill_tree.sh; also
# called below at cleanup() (trap-invoked, itself flagged the same way -- see that disable for the root cause)
kill_tree() {
  local r=$1 pids p i alive
  case $r in ''|*[!0-9]*) return 0 ;; esac
  [ "$r" -gt 1 ] || return 0
  pids=$(descendants "$r")
  for p in $pids; do case $p in ''|*[!0-9]*) continue ;; esac; [ "$p" -gt 1 ] && kill -s TERM "$p" 2>/dev/null; done
  i=0
  while [ "$i" -lt 30 ]; do
    alive=0; for p in $pids; do kill -0 "$p" 2>/dev/null && alive=1; done
    [ "$alive" -eq 0 ] && break
    sleep 0.1; i=$((i + 1))
  done
  for p in $pids; do case $p in ''|*[!0-9]*) continue ;; esac; [ "$p" -gt 1 ] && kill -s KILL "$p" 2>/dev/null; done
  return 0
}
# shellcheck disable=SC2329  # invoked via `trap cleanup EXIT` on the very next line (bareword trap +
# this script's own unconditional trailing `exit $fail` hides the trap-call from static analysis --
# same root cause as the SC2329 false-positives fixed this cycle in the sibling test files)
cleanup() { local p; for p in $(jobs -rp); do kill_tree "$p"; done; wait 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
trap 'cleanup; exit 2' HUP INT TERM
fails=0

run() { case "$1" in *_red.sh) case "$1" in *host_guard*|*triple*) sh "$1" ;; *) bash "$1" ;; esac ;; *) bash "$1" ;; esac; }

# Parallelism: host_guard clamps 9 requested jobs (each test is a thread-hungry process tree).
MAXJ=$(sh "$SRC/lib/host_guard.sh" 9 --kind jobs --threads-per-job 8 2>/dev/null | sed -n 's/^N=//p')
case $MAXJ in ''|*[!0-9]*) MAXJ=1 ;; esac
[ "$MAXJ" -ge 1 ] || MAXJ=1
throttle() { while [ "$(jobs -rp | wc -l)" -ge "$MAXJ" ]; do wait -n 2>/dev/null || true; done; }

control_job() { # id test-relpath
  cp -R "$SRC" "$W/c_$1"
  if run "$W/c_$1/$2" >/dev/null 2>&1; then echo 0 >"$W/c_$1.rc"; else echo 1 >"$W/c_$1.rc"; fi
}
mut_job() { # id test-relpath target-relpath sed-expr [marker]
  cp -R "$SRC" "$W/m_$1"
  cp "$W/m_$1/$3" "$W/m_$1.orig"
  sed -i "$4" "$W/m_$1/$3"
  if cmp -s "$W/m_$1.orig" "$W/m_$1/$3"; then echo NOCHANGE >"$W/m_$1.rc"; return; fi
  if FC_TEST_FAILFAST=1 run "$W/m_$1/$2" >"$W/m_$1.log" 2>&1; then echo 0 >"$W/m_$1.rc"; return; fi
  # Normalise a numbered-check "FAIL[N]:"/"PASS[N]:" prefix to a bare "FAIL:"/"PASS:" one, so a
  # marker (below) never has to encode a check's own shiftable numeric index (11.4.6 -- pinning an
  # index would be a guess about suite layout, not the mutation's own effect).
  sed -E 's/^(FAIL|PASS)\[[0-9]+\]:/\1:/' "$W/m_$1.log" >"$W/m_$1.norm"
  if [ -z "${5:-}" ]; then echo 1 >"$W/m_$1.rc"
  elif grep -qF -- "$5" "$W/m_$1.norm"; then echo 1 >"$W/m_$1.rc"
  else echo MARKER_MISS >"$W/m_$1.rc"; fi
}

CHECKS=()   # "name|controlid"
ctl() { throttle; control_job "$1" "$2" & }
mut() { # name controlid test target expr [marker]
  CHECKS+=("$1|$2"); throttle; mut_job "$1" "$3" "$4" "$5" "${6:-}" &
}

ctl fc tests/test_fc_common_red.sh
ctl th tests/test_triple_harness_red.sh
ctl hg tests/test_host_guard_red.sh
ctl km tests/test_foundational_mutations_kill_tree.sh
ctl df tests/test_foundational_mutations_descendants_filter.sh
ctl kg tests/test_foundational_mutations_killtree_root_guard.sh
mut M1-body_hash-includes-run_meta fc tests/test_fc_common_red.sh lib/fc_common.py 's/^EXCLUDED = ("run_meta", "body_hash")$/EXCLUDED = ("body_hash",)/' 'FAIL: body_hash equal across differing run_meta'
mut M2-harness-ignores-golden-bad th tests/test_triple_harness_red.sh tests/lib/triple_harness.sh 's/\[ "\$a" -eq 1 \] \&\& ok=true || ok=false/ok=true/' 'FAIL badpass (golden-bad rc 0)'
mut M3-host_guard-hardcoded-64 hg tests/test_host_guard_red.sh lib/host_guard.sh 's/\[ "\$n" -lt 1 \] \&\& n=1 ;;/n=64 ;;/' 'FAIL: within all limits keeps request'
mut M4-harness-golden-good-always-ok th tests/test_triple_harness_red.sh tests/lib/triple_harness.sh 's/\[ "\$a" -eq 0 \] \&\& ok=true || ok=false/ok=true/' 'FAIL negrefuse (neg-control rc 1)'
mut M5-schema-excluded-from-hash fc tests/test_fc_common_red.sh lib/fc_common.py 's/^EXCLUDED = ("run_meta", "body_hash")$/EXCLUDED = ("run_meta", "body_hash", "schema")/' 'FAIL: schema participates in body_hash'
mut M6-BLIND-excluded-from-hash fc tests/test_fc_common_red.sh lib/fc_common.py 's/^EXCLUDED = ("run_meta", "body_hash")$/EXCLUDED = ("run_meta", "body_hash", "BLIND")/' 'FAIL: BLIND doc hash differs from clean doc hash'
mut M7-driver-killtree-term-guard-weakened km tests/test_foundational_mutations_kill_tree.sh tests/test_foundational_mutations.sh 's/\[ "\$p" -gt 1 \] \&\& kill -s TERM/[ "$p" -gt 0 ] \&\& kill -s TERM/' 'NOT ok kill_tree TERM-signals pid 1'
mut M8-descendants-closure-filter-removed df tests/test_foundational_mutations_descendants_filter.sh tests/test_foundational_mutations.sh 's#(pp\[q\] in w) && q ~ /\^\[0-9\]+\$/ && q + 0 > 1)#(pp[q] in w))#' 'NOT ok descendants() includes pid 1 in the closure (regression: the ballooning-closure hazard)'
mut M9-host_guard-exhaust-floors-to-one hg tests/test_host_guard_red.sh lib/host_guard.sh 's/^  n=0; reason=\$1$/  n=1; reason=$1/' 'FAIL: F4/B3 active(9)>cap(6): already exhausted, refuses entirely'
# M10 (round-11 remediation, MINOR-6): weakens host_guard.sh's I1 fix by gating the ENTIRE memory-
# ceiling check behind `[ "$mem_per" -gt 0 ]` (never merely skipping the PER-JOB-sized reduction the
# way the pre-fix I1 bug did). Verified directly: with no --per-job-mem-kb (mem_per=0) this makes
# the outer `if isnum "$mtot" && isnum "$mav"` condition FALSE even when both are genuinely
# readable, so execution falls to its own `else unreadable unreadable_memory` branch -- the
# mutated run's actual observed shape is "N=1 REASON=unreadable_memory" (falsely claiming readable
# memory values are unreadable), NOT the original pre-fix I1 bug's shape ("N=<request>
# REASON=none", the ceiling silently never consulted at all). Still correctly caught by
# test_host_guard_red.sh's own T-REMED/I1 check either way, since neither shape matches that
# check's expected N=0 REASON=memory_ceiling_exhausted.
mut M10-host_guard-memory-ceiling-gated-behind-per-job hg tests/test_host_guard_red.sh lib/host_guard.sh 's/^if isnum "\$mtot" \&\& isnum "\$mav"; then$/if isnum "$mtot" \&\& isnum "$mav" \&\& [ "$mem_per" -gt 0 ]; then/' 'FAIL: T-REMED/I1 99% memory used, no per-job flag => ceiling checked, refuses entirely'
mut M11-driver-killtree-kill-guard-weakened km tests/test_foundational_mutations_kill_tree.sh tests/test_foundational_mutations.sh 's/\[ "\$p" -gt 1 \] \&\& kill -s KILL/[ "$p" -gt 0 ] \&\& kill -s KILL/' 'NOT ok kill_tree KILL-signals pid 1'
mut M12-driver-killtree-root-guard-weakened kg tests/test_foundational_mutations_killtree_root_guard.sh tests/test_foundational_mutations.sh 's/\[ "\$r" -gt 1 \] || return 0/[ "$r" -gt 0 ] || return 0/' 'NOT ok kill_tree(root=1) signalled something (root guard bypassed)'
mut M13-host_guard-unreadable-ignores-exhausted hg tests/test_host_guard_red.sh lib/host_guard.sh '/^unreadable() {/,/^}/s/\*_exhausted) return/NEVER_M13_MATCH) return/' 'FAIL: T014/B1(a) exhausted-then-unreadable: N=0 thread_headroom_exhausted preserved'
mut M14-host_guard-exhaust-overridden-by-unreadable hg tests/test_host_guard_red.sh lib/host_guard.sh '/^exhaust() {/,/^}/s/\*_exhausted) return/*_exhausted|unreadable_*) return/' 'FAIL: T014/B1(b) unreadable-then-exhausted: N=0 thread_headroom_exhausted, not unreadable_nproc'
mut M15-fc_common-leader_reap_honest-always-true fc tests/test_fc_common_red.sh lib/fc_common.py '/^def _leader_reap_honest(pid):/,/^def _run_bounded/s/^        return False$/        return True/' 'FAIL: SIGCHLD belt-and-suspenders: _leader_reap_honest independently fails closed even if the reset itself is bypassed'
wait

for c in "${CHECKS[@]}"; do
  name=${c%%|*}; ctl_id=${c##*|}
  cr=$(cat "$W/c_$ctl_id.rc" 2>/dev/null || echo MISSING); mr=$(cat "$W/m_$name.rc" 2>/dev/null || echo MISSING)
  if [ "$cr" != 0 ]; then echo "FAIL $name: control (unmutated) test does not pass (control $ctl_id rc=$cr)"; fails=$((fails+1))
  elif [ "$mr" = NOCHANGE ]; then echo "FAIL $name: mutation changed nothing (needle failed)"; fails=$((fails+1))
  elif [ "$mr" = 0 ]; then echo "FAIL $name: mutation NOT caught (bluff gate)"; fails=$((fails+1))
  elif [ "$mr" = MARKER_MISS ]; then echo "FAIL $name: mutated run failed, but NOT for the expected reason (marker mismatch -- a different/flaky failure, not proof THIS mutation's own defect was what got caught)"; fails=$((fails+1))
  elif [ "$mr" = 1 ]; then echo "ok   $name: mutation caught"
  else echo "FAIL $name: no result recorded (mutation job died: [$mr])"; fails=$((fails+1)); fi
done

if [ "$fails" -eq 0 ]; then echo "PASS foundational mutations (${#CHECKS[@]}/${#CHECKS[@]})"; exit 0; fi
echo "FAILED: $fails"; exit 1
