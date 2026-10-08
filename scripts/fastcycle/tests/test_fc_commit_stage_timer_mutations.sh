#!/bin/bash
# Purpose : paired §1.1 mutation runner for test_fc_commit_stage_timer_red.sh (T048 restart
#           round-1). Each mutation re-introduces one real defect into a COPY of
#           scripts/commit_all.sh -- the reviewer's MA / MB / MG verbatim in intent, plus the
#           fixer's own for every new fix (exit flush, env leak, source-only suppression,
#           dry-run network read-back, aggregate-rc push result) and the round-3 reviewer's
#           CN1..CN4 (child exit flush, ls-remote bound, UNKNOWN tip, tips on a failed push)
#           verbatim in intent -- runs the UNMODIFIED test
#           against that copy (FC_COMMIT_STAGE_COMMIT_ALL), and requires a non-zero exit AND a
#           "NOT ok" line naming the expected scenario: a mutant killed for an unrelated reason
#           does not count.
# Usage   : bash test_fc_commit_stage_timer_mutations.sh   (exit 0 = every mutant killed for the
#           right reason, 1 = a survivor / wrong-reason kill, 2 = setup error)
#           FC_CST_MUTANTS="MA MG" -- run only the named mutants.
# Runtime : ~2 min per mutant (the full hermetic test runs once per mutant) -- run it in the
#           background (§11.4.89). No network; nothing outside mktemp is written.
# Every anchor below is LITERAL source text of commit_all.sh -- never expanded here.
# shellcheck disable=SC2016
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
CA="$ROOT/scripts/commit_all.sh"
TEST="$HERE/test_fc_commit_stage_timer_red.sh"
[ -f "$CA" ] && [ -f "$TEST" ] || { echo "FATAL: commit_all.sh / test not found"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 required"; exit 2; }
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
fail=0
want_run() { [ -z "${FC_CST_MUTANTS:-}" ] && return 0; case " $FC_CST_MUTANTS " in *" $1 "*) return 0 ;; esac; return 1; }

# mutate <id> <expected NOT-ok substring> <python transform reading/writing $SRC/$DST>
mutate() {
  local id="$1" want="$2" py="$3" mut out rc
  want_run "$id" || return 0
  mut="$TMP/commit_all_$id.sh"; out="$TMP/$id.out"
  if ! SRC="$CA" DST="$mut" python3 -c "$py"; then echo "NOT ok $id: transform failed (anchor not found exactly once)"; fail=1; return; fi
  if cmp -s "$CA" "$mut"; then echo "NOT ok $id: mutation produced an identical file"; fail=1; return; fi
  FC_COMMIT_STAGE_COMMIT_ALL="$mut" bash "$TEST" >"$out" 2>&1; rc=$?
  if [ "$rc" != 0 ] && grep '^NOT ok' "$out" | grep -qF -- "$want"; then
    echo "ok   $id killed (rc=$rc): $(grep '^NOT ok' "$out" | grep -F -- "$want" | head -n1 | cut -c1-160)"
  else
    echo "NOT ok $id SURVIVED or killed for the wrong reason (rc=$rc, wanted NOT ok naming '$want')"
    grep '^NOT ok' "$out" | head -3
    fail=1
  fi
}
REPL='
import os,sys
s=open(os.environ["SRC"]).read(); a=os.environ["A"]; b=os.environ["B"]
if s.count(a)!=1: sys.exit(1)
open(os.environ["DST"],"w").write(s.replace(a,b,1))'
rmut() { A="$3" B="$4" mutate "$1" "$2" "$REPL"; }

# control: the unmutated commit_all.sh passes through the same path
if want_run control; then
  if FC_COMMIT_STAGE_COMMIT_ALL="$CA" bash "$TEST" >"$TMP/control.out" 2>&1; then echo "ok   control: unmutated commit_all.sh passes through the mutation path"
  else echo "NOT ok control: unmutated commit_all.sh FAILS through the mutation path"; grep '^NOT ok' "$TMP/control.out" | head -3; exit 1; fi
fi

# Reviewer MA: strip every _fc_stage_* call outside do_push()/_fc_record_remote_tips()/wrappers.
mutate MA "A: executed-stage rows wrong" '
import os,re
lines=open(os.environ["SRC"]).read().split("\n"); out=[]; skip=None
for l in lines:
    if re.match(r"^(do_push|_fc_record_remote_tips|_fc_stage_start|_fc_stage_end)\(\) \{",l): skip=True
    elif re.match(r"^[A-Za-z_][A-Za-z0-9_]*\(\) \{",l): skip=False
    if not skip and re.match(r"^\s*_fc_stage_(start|end)( |$)",l):
        l=re.sub(r"_fc_stage_(start|end).*$",":",l)
    out.append(l)
open(os.environ["DST"],"w").write("\n".join(out))'
# Reviewer MB: the detached push child emits no per-remote rows (default push path).
rmut MB "B: the default (detached) push path never wrote" \
  '        _fc_record_remote_tips "$_br" post-push
        exit "$_rc"' '        exit "$_rc"'
# Reviewer MG: the timer path rewrites COMMIT_MESSAGE and stages a marker file.
rmut MG "C: unexpected commit content" \
  '_fc_stage_start() {
    command -v fc_timer_start >/dev/null 2>&1 || return 0' '_fc_stage_start() {
    COMMIT_MESSAGE="${COMMIT_MESSAGE:-} [timed]"; echo x > "$AOSP_ROOT/.fc_marker"; git -C "$AOSP_ROOT" add -f .fc_marker 2>/dev/null || true
    command -v fc_timer_start >/dev/null 2>&1 || return 0'
# Fixer MX-I2: the one EXIT-trap flush is never installed.
rmut MXI2 "D: rc=" \
  '    if command -v fc_timer_install_exit_flush >/dev/null 2>&1; then
        fc_timer_install_exit_flush
    fi' '    :'
# Fixer MX-m7: FC_TIMER_* exported to every descendant again.
rmut MXm7 "B (m7)" \
  'export -n FC_TIMER_TSV FC_TIMER_RUN_ID FC_TIMER_CANDIDATE_FINGERPRINT 2>/dev/null || true' \
  'export FC_TIMER_TSV FC_TIMER_RUN_ID FC_TIMER_CANDIDATE_FINGERPRINT'
# Fixer MX-m8: a COMMIT_ALL_SOURCE_ONLY harness writes into the project's real qa-results again.
rmut MXm8 "H: " \
  '        FC_TIMING=0
    fi
    fc_timer_init' '        :
    fi
    fc_timer_init'
# Fixer MX-m5: --dry-run performs the network read-back again.
rmut MXm5 "G: rc=" \
  '_fc_stage_end --extra "remote=$remote;tip=not_read_dry_run;result=dry-run"' \
  '_fc_stage_end --extra "remote=$remote;tip=$(_fc_ls_remote_tip "$remote" "$branch");result=dry-run"'
# Fixer MX-m6: per-remote result inferred from the aggregate rc (always ok).
rmut MXm6 "J: rc=" \
  '        case " ${PUSH_SKIP_REMOTES:-} " in
            *" $remote "*) result=skipped_by_policy ;;
            *) if [ -n "$local_tip" ] && [ "$tip" = "$local_tip" ]; then result=ok; else result=tip_mismatch; fi ;;
        esac' '        result=ok'
# Fixer MX-env: the detached child no longer receives the run binding (rows land elsewhere).
rmut MXenv "B: the default (detached) push path never wrote" \
  'nohup env FC_TIMER_TSV="${FC_TIMER_TSV:-}" FC_TIMER_RUN_ID="${FC_TIMER_RUN_ID:-}"' 'nohup env FC_TIMER_RUN_ID="${FC_TIMER_RUN_ID:-}"'

# Round-3 reviewer CN1: the detached child no longer installs its exit flush.
rmut CN1 "L: the detached child died mid-frame" \
  '        if [ -f "$_fc_lib" ]; then
            . "$_fc_lib"
            fc_timer_install_exit_flush
        fi' '        if [ -f "$_fc_lib" ]; then
            . "$_fc_lib"
        fi'
# Round-3 reviewer CN2: the ls-remote read-back is no longer time-bounded.
rmut CN2 "N: elapsed" \
  'tip="$(timeout "${FC_LS_REMOTE_TIMEOUT_S:-15}" git -C "$AOSP_ROOT" ls-remote' \
  'tip="$(git -C "$AOSP_ROOT" ls-remote'
# Round-3 reviewer CN3: an UNKNOWN (unreachable) tip is recorded result=ok.
rmut CN3 "M: unreachable upstream row" \
  '*) if [ -n "$local_tip" ] && [ "$tip" = "$local_tip" ]; then result=ok; else result=tip_mismatch; fi ;;' \
  '*) if [ "$tip" = UNKNOWN ] || { [ -n "$local_tip" ] && [ "$tip" = "$local_tip" ]; }; then result=ok; else result=tip_mismatch; fi ;;'
# Round-3 reviewer CN4: the detached child records per-remote tips only when the push succeeded.
rmut CN4 "M: a FAILED detached push recorded no per-remote rows" \
  '        _fc_record_remote_tips "$_br" post-push
        exit "$_rc"' '        [ "$_rc" -eq 0 ] && _fc_record_remote_tips "$_br" post-push
        exit "$_rc"'

echo
if [ "$fail" = 0 ]; then echo "=== COMMIT STAGE TIMER MUTATIONS: ALL KILLED ==="; else echo "=== COMMIT STAGE TIMER MUTATIONS: SURVIVORS ABOVE ==="; fi
exit "$fail"
