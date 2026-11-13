#!/usr/bin/env bash
# cm_sync_upstreams_ff_only_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SYNC-UPSTREAMS-FF-ONLY.
# Copies the real engine + wrapper into a throwaway root, applies ONE mutation per case, and runs the gate on it.
#   PASS-expected : GOLDEN (the unmodified engine)
#   FAIL-expected : PUSH-IN-WRITE (push added to WRITE_SUBCOMMANDS) · RESET-IN-READ (reset added to READ_SUBCOMMANDS)
#                   · CATFILE-IN-READ (cat-file back on the read list) · NO-PLUS-CHECK (+refspec no longer refused)
#                   · MERGE-ANY / CHECKOUT-ANY (shape not enforced) · SECOND-SPAWN (an os.system call added)
#                   · NO-CHECK-IN-CHOKE (proc_run_git no longer calls check_git_args) · CHECKED-REBOUND
#                   · ARGS-REBOUND · ARGV-NOT-GIT-ARGV (Popen argv not git_argv(git_bin, repo, checked))
#                   · NO-PGID-GUARD (pgid > 1 removed) · NO-ISOLATED-PY (wrapper runs python3 without -I)
#                   · REFUSE-ALL (check_git_args refuses every call: the control needle must catch it)
#                   · R1-MERGE-FF · R2-GETATTR-SPAWN · FROM-IMPORT · IMPORT-ALIAS · IMPORTLIB-IMPORT · MODULE-ALIAS
#                   · DUNDER · SHADOW · GLOBAL-STMT
#                   · K01-POPEN-ALIAS (Popen bound to a name, then called) · K02-POPEN-MAP (Popen passed to map)
#                   · K03-KILLPG-ALIAS (killpg aliased, no guard) · K04-HOOKS-MERGE (hooksPath dropped for merge /
#                   checkout only: the per-verb runtime argv check) · POPEN-OUTSIDE (Popen called in another def)
#                   · NESTED-DEF-POPEN (Popen in a def nested inside proc_run_git) · KILLPG-ELSEWHERE
#                   · KILL-ATTR (p.kill() added) · SECOND-CHOKE-CALL (proc_run_git called twice)
#                   · CHOKE-REBOUND (proc_run_git redefined) · RUN-AS-VALUE (a .run passed on uncalled)
#                   · COMPUTED-ARGS (a call site passes a computed list) · NO-OK-DECLARED (a site loses ok=)
#                   · OK-NOT-LITERAL · POPEN-SHELL-KW · NO-HOOKSPATH / NO-FSMONITOR (a safe -c pair dropped)
#                   · NO-OPTIONAL-LOCKS (K14) · K16-ENV (GIT_CONFIG_PARAMETERS kept) · S1-REDACT (userinfo cut at the
#                   first '@') · NO-REFMAP · PRUNE-IN-FETCH · MIRROR-REFSPEC · FORCED-TAGS (fetch_args made unsafe)
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
  if [ "$rc" = "$want" ]; then echo "ok   $label (rc=$rc)$( [ "$rc" = 1 ] && printf " :: %s" "$(printf "%s\n" "$out" | grep -m1 FAIL | sed "s/^[^—]*— //" | cut -c1-90)")"; else echo "BAD  $label: rc=$rc expected $want"; echo "$out" | sed 's/^/     /'; bad=1; fi
}
case_ GOLDEN 0 none "" ""
case_ PUSH-IN-WRITE 1 py 'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add"}' 'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add", "push"}'
case_ RESET-IN-READ 1 py '"remote", "config", "symbolic-ref"}' '"remote", "config", "symbolic-ref", "reset"}'
case_ CATFILE-IN-READ 1 py '"remote", "config", "symbolic-ref"}' '"remote", "config", "symbolic-ref", "cat-file"}'
case_ NO-PLUS-CHECK 1 py 'if a.startswith("+"):' 'if a.startswith("+") and False:'
case_ MERGE-ANY 1 py 'if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):' 'if False:'
case_ CHECKOUT-ANY 1 py 'if len(rest) != 3 or rest[0] != "--quiet" or rest[1] != "--detach" or not SHA_RE.match(rest[2]):' 'if False:'
case_ SECOND-SPAWN 1 py 'def now_utc():' 'def _x():
    os.system("true")


def now_utc():'
case_ NO-CHECK-IN-CHOKE 1 py '    checked = check_git_args(args)
' '    checked = list(args)
'
case_ CHECKED-REBOUND 1 py '    checked = check_git_args(args)
' '    checked = check_git_args(args)
    checked = ["push"]
'
case_ ARGS-REBOUND 1 py '    checked = check_git_args(args)
' '    checked = check_git_args(args)
    args = ["push"]
'
case_ ARGV-NOT-GIT-ARGV 1 py 'p = subprocess.Popen(git_argv(git_bin, repo, checked),' 'p = subprocess.Popen([git_bin, "-C", repo] + list(checked),'
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
case_ IMPORTLIB-IMPORT 1 py 'import subprocess
' 'import subprocess
import importlib
'
case_ MODULE-ALIAS 1 py 'def now_utc():' '_SP = subprocess


def now_utc():'
case_ DUNDER 1 py 'def now_utc():' 'def _d():
    return os.__dict__


def now_utc():'
case_ SHADOW 1 py 'def now_utc():' 'def eval(x):
    return x


def now_utc():'
case_ GLOBAL-STMT 1 py 'def now_utc():' 'def _g():
    global SAFE_CONFIG
    SAFE_CONFIG = ()


def now_utc():'
case_ K01-POPEN-ALIAS 1 py 'def now_utc():' 'def _k01():
    _sp = subprocess.Popen
    return _sp(["true"]).wait()


def now_utc():'
case_ K02-POPEN-MAP 1 py 'def now_utc():' 'def _k02():
    return list(map(subprocess.Popen, [["true"]]))


def now_utc():'
case_ K03-KILLPG-ALIAS 1 py 'def now_utc():' 'def _k03(p):
    _k = os.killpg
    _k(os.getpgid(p.pid), signal.SIGKILL)


def now_utc():'
case_ K04-HOOKS-MERGE 1 py '    for kv in SAFE_CONFIG:
        cmd += ["-c", kv]' '    for kv in SAFE_CONFIG:
        if args and args[0] in ("merge", "checkout") and kv.startswith("core.hooksPath"):
            continue
        cmd += ["-c", kv]'
case_ POPEN-OUTSIDE 1 py 'def now_utc():' 'def _p():
    return subprocess.Popen(["true"])


def now_utc():'
case_ NESTED-DEF-POPEN 1 py '    checked = check_git_args(args)
' '    checked = check_git_args(args)

    def _n():
        return subprocess.Popen(["true"])
'
case_ KILLPG-ELSEWHERE 1 py 'def now_utc():' 'def _k():
    os.killpg(os.getpid(), signal.SIGKILL)


def now_utc():'
case_ KILL-ATTR 1 py '        proc_kill_group(p)
' '        proc_kill_group(p)
        p.kill()
'
case_ SECOND-CHOKE-CALL 1 py 'def now_utc():' 'def _c():
    return proc_run_git("git", "/", ["status"], {}, 1)


def now_utc():'
case_ CHOKE-REBOUND 1 py 'def now_utc():' 'proc_run_git = None


def now_utc():'
case_ RUN-AS-VALUE 1 py 'def now_utc():' 'def _r(r):
    f = r.run
    return f


def now_utc():'
case_ COMPUTED-ARGS 1 py '["ls-files", "-s", "-z"], ok=(0,))' 'list(("ls-files", "-s", "-z")), ok=(0,))'
case_ NO-OK-DECLARED 1 py '    names = g_out(r, p, ["remote"], ok=(0,))' '    names = g_out(r, p, ["remote"])'
case_ OK-NOT-LITERAL 1 py '["ls-files", "-s", "-z"], ok=(0,))' '["ls-files", "-s", "-z"], ok=tuple(range(256)))'
case_ POPEN-SHELL-KW 1 py 'start_new_session=True)' 'start_new_session=True, shell=False)'
case_ NO-HOOKSPATH 1 py '"core.hooksPath=/dev/null", ' ""
case_ NO-FSMONITOR 1 py '"core.fsmonitor=false", ' ""
case_ NO-OPTIONAL-LOCKS 1 py '    return cmd + ["--no-optional-locks"] + list(args)' '    return cmd + list(args)'
case_ K16-ENV 1 py '"SSH_ASKPASS", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",' '"SSH_ASKPASS", "GIT_CONFIG_COUNT",'
case_ S1-REDACT 1 py '        at = text.rfind("@", start, end)' '        at = text.find("@", start, end)'
case_ NO-REFMAP 1 py '"--refmap=", "--", remote' '"--", remote'
case_ PRUNE-IN-FETCH 1 py '"fetch", "--no-prune", "--no-prune-tags"' '"fetch", "--prune", "--no-prune-tags"'
case_ MIRROR-REFSPEC 1 py '"+refs/heads/*:refs/remotes/%s/*" % remote' '"+refs/heads/*:refs/heads/*"'
case_ FORCED-TAGS 1 py 'a.append("refs/tags/*:refs/tags/*")' 'a.append("+refs/tags/*:refs/tags/*")'
case_ SYNTAX 2 py 'def classify(ahead, behind):' 'def classify(ahead, behind'
case_ MISSING 2 none "" ""
echo "cases: $n"
[ "$bad" = 0 ] && echo "CM-SYNC-UPSTREAMS-FF-ONLY mutation test: PASS ($n cases)" || echo "CM-SYNC-UPSTREAMS-FF-ONLY mutation test: FAIL"
exit "$bad"
