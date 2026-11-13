#!/usr/bin/env bash
# cm_sync_upstreams_ff_only_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SYNC-UPSTREAMS-FF-ONLY.
# Copies the real engine + wrapper into a throwaway root, applies ONE mutation per case, and runs the gate on it.
#   PASS-expected : GOLDEN (the unmodified engine)
#   FAIL-expected : PUSH-IN-WRITE (push added to WRITE_SUBCOMMANDS) · RESET-IN-READ (reset added to READ_SUBCOMMANDS)
#                   · NO-PLUS-CHECK (+refspec no longer refused) · MERGE-ANY (merge shape not enforced)
#                   · CHECKOUT-ANY (checkout shape not enforced) · SECOND-SPAWN (an os.system call added)
#                   · NO-CHECK-IN-RUN (Runner.run no longer calls check_git_args) · NO-PGID-GUARD (pgid > 1 removed)
#                   · NO-ISOLATED-PY (wrapper runs python3 without -I) · REFUSE-ALL (check_git_args refuses every
#                   call: the control needle must catch it)
#                   · R1-MERGE-FF (merge --ff accepted) · R2-GETATTR-SPAWN (a spawn hidden behind getattr)
#                   · FROM-IMPORT · IMPORT-ALIAS · MODULE-ALIAS (a module bound to a name) · DUNDER (os.__dict__)
#                   · SHADOW (a def named eval) · KILLPG-ELSEWHERE · CMD-REBOUND (cmd reassigned before Popen)
#                   · ARGV-NOT-GIT-ARGV (Popen argv not from git_argv) · COMPUTED-ARGS (a call site passes a
#                   computed list) · POPEN-SHELL-KW · NO-HOOKSPATH / NO-FSMONITOR (a safe -c pair dropped)
#                   · NO-REFMAP · PRUNE-IN-FETCH · MIRROR-REFSPEC · FORCED-TAGS (fetch_args made unsafe)
#   BLIND-expected (rc 2): SYNTAX (engine unparseable) · MISSING (engine absent)
# Usage: cm_sync_upstreams_ff_only_mutation_test.sh   Exit: 0 proof holds · 1 misclassified · 2 env error.
# Side-effects: temp dir under $TMPDIR (trap-cleaned with safe_rm_rf). Dependencies: bash, python3.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
gate="${GATE_UNDER_TEST:-$here/cm_sync_upstreams_ff_only.sh}"
[ -r "$gate" ] && [ -r "$repo/scripts/sync/sync_all_upstreams.py" ] || { echo "META: gate or engine missing" >&2; exit 2; }
# shellcheck source=../lib/safe_rm.sh
. "$repo/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_sync_ff_mut.XXXXXX")" || exit 2
export SAFE_RM_ALLOWED_ROOTS="$tmp"
trap 'safe_rm_rf "${tmp:?}" >/dev/null 2>&1' EXIT
bad=0; n=0
# case LABEL EXPECTED_RC FILE(py|sh|none) OLD NEW
case_() {
  local label="$1" want="$2" which="$3" old="$4" new="$5" d="$tmp/$1"
  mkdir -p "$d/scripts/sync"
  cp "$repo/scripts/sync/sync_all_upstreams.py" "$repo/scripts/sync/sync_all_upstreams.sh" "$d/scripts/sync/"
  if [ "$which" != none ]; then
    local f="$d/scripts/sync/sync_all_upstreams.$which"
    if ! python3 -I -c 'import sys
p,o,n=sys.argv[1:4]; s=open(p).read()
if s.count(o)!=1: sys.exit(3)
open(p,"w").write(s.replace(o,n))' "$f" "$old" "$new"; then
      echo "META: $label: mutation anchor not found exactly once"; bad=1; return
    fi
  fi
  [ "$label" = MISSING ] && rm -f -- "$d/scripts/sync/sync_all_upstreams.py"
  local out rc; out="$(bash "$gate" --root "$d" 2>&1)"; rc=$?; n=$((n+1))
  if [ "$rc" = "$want" ]; then echo "ok   $label (rc=$rc)"; else echo "BAD  $label: rc=$rc expected $want"; echo "$out" | sed 's/^/     /'; bad=1; fi
}
case_ GOLDEN 0 none "" ""
case_ PUSH-IN-WRITE 1 py 'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add"}' 'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add", "push"}'
case_ RESET-IN-READ 1 py '"for-each-ref", "merge-base", "remote", "config", "symbolic-ref"}' '"for-each-ref", "merge-base", "remote", "config", "symbolic-ref", "reset"}'
case_ NO-PLUS-CHECK 1 py 'if a.startswith("+"):' 'if a.startswith("+") and False:'
case_ MERGE-ANY 1 py 'if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):' 'if False:'
case_ CHECKOUT-ANY 1 py 'if len(rest) != 3 or rest[0] != "--quiet" or rest[1] != "--detach" or not SHA_RE.match(rest[2]):' 'if False:'
case_ SECOND-SPAWN 1 py 'def now_utc():' 'def _x():
    os.system("true")


def now_utc():'
case_ NO-CHECK-IN-RUN 1 py '        try:
            check_git_args(args)
        except GitRefused as e:
            self._unanswered(repo, args, "refused")
            return 125, "", "refused: %s" % e
' ''
case_ NO-PGID-GUARD 1 py 'if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:' 'if isinstance(pgid, int) and pgid == p.pid:'
case_ NO-ISOLATED-PY 1 sh 'exec python3 -I -B' 'exec python3 -B'
case_ REFUSE-ALL 1 py '    sub, rest = args[0], list(args[1:])' '    raise GitRefused("all")'
case_ R1-MERGE-FF 1 py 'if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):' 'if len(rest) != 2 or rest[0] not in ("--ff-only", "--ff") or not SHA_RE.match(rest[1]):'
case_ R2-GETATTR-SPAWN 1 py 'def now_utc():' 'def _hidden():
    getattr(subprocess, "call")(["true"])


def now_utc():'
case_ FROM-IMPORT 1 py 'import subprocess
' 'import subprocess
from os import system
'
case_ IMPORT-ALIAS 1 py 'import subprocess
' 'import subprocess as subprocess
'
case_ MODULE-ALIAS 1 py 'def now_utc():' '_SP = subprocess


def now_utc():'
case_ DUNDER 1 py 'def now_utc():' 'def _d():
    return os.__dict__


def now_utc():'
case_ SHADOW 1 py 'def now_utc():' 'def eval(x):
    return x


def now_utc():'
case_ KILLPG-ELSEWHERE 1 py 'def now_utc():' 'def _k():
    os.killpg(os.getpid(), signal.SIGKILL)


def now_utc():'
case_ CMD-REBOUND 1 py '        cmd = git_argv(self.git, repo, args)
' '        cmd = git_argv(self.git, repo, args)
        cmd = ["sh", "-c", "true"]
'
case_ ARGV-NOT-GIT-ARGV 1 py '        cmd = git_argv(self.git, repo, args)
' '        cmd = [self.git, "-C", repo] + list(args)
'
case_ COMPUTED-ARGS 1 py '["ls-files", "-s", "-z"])' 'list(("ls-files", "-s", "-z")))'
case_ POPEN-SHELL-KW 1 py 'start_new_session=True)' 'start_new_session=True, shell=False)'
case_ NO-HOOKSPATH 1 py '"core.hooksPath=/dev/null", ' ''
case_ NO-FSMONITOR 1 py '"core.fsmonitor=false", ' ''
case_ NO-REFMAP 1 py '"--refmap=", "--", remote' '"--", remote'
case_ PRUNE-IN-FETCH 1 py '"fetch", "--no-prune", "--no-prune-tags"' '"fetch", "--prune", "--no-prune-tags"'
case_ MIRROR-REFSPEC 1 py '"+refs/heads/*:refs/remotes/%s/*" % remote' '"+refs/heads/*:refs/heads/*"'
case_ FORCED-TAGS 1 py 'a.append("refs/tags/*:refs/tags/*")' 'a.append("+refs/tags/*:refs/tags/*")'
case_ SYNTAX 2 py 'def classify(ahead, behind):' 'def classify(ahead, behind'
case_ MISSING 2 none "" ""
echo "cases: $n"
[ "$bad" = 0 ] && echo "CM-SYNC-UPSTREAMS-FF-ONLY mutation test: PASS ($n cases)" || echo "CM-SYNC-UPSTREAMS-FF-ONLY mutation test: FAIL"
exit "$bad"
