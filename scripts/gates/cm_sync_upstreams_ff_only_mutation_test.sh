#!/usr/bin/env bash
# cm_sync_upstreams_ff_only_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SYNC-UPSTREAMS-FF-ONLY.
# Copies the real engine + wrapper into a throwaway root, applies ONE mutation per case, and runs the gate on it.
#   PASS-expected : GOLDEN (the unmodified engine)
#   FAIL-expected : PUSH-IN-WRITE (push added to WRITE_SUBCOMMANDS) · RESET-IN-READ (reset added to READ_SUBCOMMANDS)
#                   · CATFILE-IN-READ (cat-file back on the read list) · NO-PLUS-CHECK (+refspec no longer refused)
#                   · MERGE-ANY / CHECKOUT-ANY (shape not enforced) · R12-* (round 12: bare id / ref name
#                   where an object is named, exact-name rule off, DWIM upstream lookup, any lookup pattern) · SECOND-SPAWN (an os.system call added)
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
#                   first '@'; round 5: anchors follow the linear _strip_line / the SAFE_CONFIG with core.askPass=) · NO-REFMAP · PRUNE-IN-FETCH · MIRROR-REFSPEC · FORCED-TAGS (fetch_args made unsafe)
#                   review round 3 (the reviewer's mutants, verbatim): X01-STATUS-OK128 · X02-DIRECT-MERGE ·
#                   X02B-DIRECT-MERGE-RECORDED · X04-OR-TRUE · X05-WINDOW-48 · X06-OK-ALL · X07-HOOKS-OVERRIDE
#                   round 6 (RV5-1 signal point, re-anchored KILL-ATTR / KILLPG-ELSE / KILLPG-REBIND / KILLPG-SIG9):
#                   KILLPG-SIGKILL-ONLY · KILLPG-ORDER-REVERSED · KILLPG-SIGINT · KILLPG-SIG-REBOUND ·
#                   SELECT-OUTSIDE · WAITID-OUTSIDE · UPDATE-STRATEGY-OK-128 · CONFIG-WRITE-SHAPE
#                   round 4 (own static shapes of the same classes): KILLPG-OR · KILLPG-NOT · KILLPG-GE1 ·
#                   KILLPG-EXTRA-TERM · KILLPG-ELSE · KILLPG-REBIND · KILLPG-OWN-GROUP (getpgid(0)) · KILLPG-SIG9 ·
#                   NO-NEW-SESSION · OK-128-AT-READ (bounded but not the oracle's) · OK-TWO · WANT-DROPPED ·
#                   FETCH-ELSEWHERE · WRITE-VIA-CONST · CFG-CASE-OVERRIDE · CFG-EXTRA-KEY · TRACE-KEPT ·
#                   CURL-VERBOSE-KEPT · AUTH-NOT-REDACTED · REDACT-URL-LINEWISE · REPORT-KEY-RAW · REGISTRY-OFF ·
#                   ARGPARSE-RAW · SITE-MOVED (a read moved into a lambda: another scope); round 9 re-anchored
#                   COMPUTED-ARGS, OK-NOT-LITERAL, X06-OK-ALL, OK-128-AT-READ, OK-TWO to index_gitlinks' new form
#                   (final=final), same meaning
#   FAIL-expected, the GATE mutated (its oracle is load-bearing in both directions): ORACLE-ROW-DROPPED (a call
#                   site with no row) · ORACLE-CLASS-WRONG (a row whose exit-128 class contradicts its ok=)
#   BLIND-expected (rc 2): SYNTAX (engine unparseable) · MISSING (engine absent)
# Usage: cm_sync_upstreams_ff_only_mutation_test.sh   Exit: 0 proof holds · 1 misclassified · 2 env error.
# Side-effects: temp dir under $TMPDIR (trap-cleaned with safe_rm_rf). Dependencies: bash, python3.
# Classification: universal (§11.4.17).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
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
  if [ "$rc" = "$want" ]; then echo "ok   $label (rc=$rc)$( [ "$rc" = 1 ] && printf " :: %s" "$(first_fail "$out")")"; else echo "BAD  $label: rc=$rc expected $want"; echo "$out" | sed 's/^/     /'; bad=1; fi
}
# first_fail TEXT — the first FAIL line, after its "— ", 90 characters; pure bash over a here-string (no
# `| grep -m1` under pipefail: an early-exiting reader returns 141; review round 3, class F)
first_fail() { local l; while IFS= read -r l; do case "$l" in *FAIL*) l="${l#*— }"; printf '%s' "${l:0:90}"; return 0 ;; esac; done <<<"$1"; }
case_ GOLDEN 0 none "" ""
case_ PUSH-IN-WRITE 1 py 'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add"}' 'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add", "push"}'
case_ RESET-IN-READ 1 py '"remote", "config", "symbolic-ref"}' '"remote", "config", "symbolic-ref", "reset"}'
case_ CATFILE-IN-READ 1 py '"remote", "config", "symbolic-ref"}' '"remote", "config", "symbolic-ref", "cat-file"}'
case_ NO-PLUS-CHECK 1 py 'if a.startswith("+"):' 'if a.startswith("+") and False:'
case_ MERGE-ANY 1 py 'if len(rest) != 2 or rest[0] != "--ff-only" or not _exact_obj(rest[1]):' 'if False:'
case_ CHECKOUT-ANY 1 py 'if len(rest) != 3 or rest[0] != "--quiet" or rest[1] != "--detach" or not _exact_obj(rest[2]):' 'if False:'
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
case_ R1-MERGE-FF 1 py 'if len(rest) != 2 or rest[0] != "--ff-only" or not _exact_obj(rest[1]):' 'if len(rest) != 2 or rest[0] not in ("--ff-only", "--ff") or not _exact_obj(rest[1]):'
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
case_ KILL-ATTR 1 py '        ended_by = proc_kill_group(p, WRITE_KILL_GRACE if level == 0 else KILL_GRACE)
' '        ended_by = proc_kill_group(p, WRITE_KILL_GRACE if level == 0 else KILL_GRACE)
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
case_ COMPUTED-ARGS 1 py '["ls-files", "-s", "-z"], ok=(0,), final=final)' 'list(("ls-files", "-s", "-z")), ok=(0,), final=final)'
case_ NO-OK-DECLARED 1 py '    names = g_out(r, p, ["remote"], ok=(0,))' '    names = g_out(r, p, ["remote"])'
case_ OK-NOT-LITERAL 1 py '["ls-files", "-s", "-z"], ok=(0,), final=final)' '["ls-files", "-s", "-z"], ok=tuple(range(256)), final=final)'
case_ POPEN-SHELL-KW 1 py 'start_new_session=True)' 'start_new_session=True, shell=False)'
case_ NO-HOOKSPATH 1 py '"core.hooksPath=/dev/null", ' ""
case_ NO-FSMONITOR 1 py '"core.fsmonitor=false", ' ""
case_ NO-OPTIONAL-LOCKS 1 py '    return cmd + ["--no-optional-locks"] + list(args)' '    return cmd + list(args)'
case_ K16-ENV 1 py '"SSH_ASKPASS", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",' '"SSH_ASKPASS", "GIT_CONFIG_COUNT",'
case_ S1-REDACT 1 py '    at = line.rfind("@")' '    at = line.find("@")'
case_ NO-REFMAP 1 py '"--refmap=", "--", remote' '"--", remote'
case_ PRUNE-IN-FETCH 1 py '"fetch", "--no-prune", "--no-prune-tags"' '"fetch", "--prune", "--no-prune-tags"'
case_ MIRROR-REFSPEC 1 py '"+refs/heads/*:refs/remotes/%s/*" % remote' '"+refs/heads/*:refs/heads/*"'
case_ FORCED-TAGS 1 py 'a.append("refs/tags/*:refs/tags/*")' 'a.append("+refs/tags/*:refs/tags/*")'
case_ X01-STATUS-OK128 1 py '    st = r.run(p, STATUS_ARGS, ok=(0,))
    if not st.answered:' '    st = r.run(p, STATUS_ARGS, ok=(0, 128))
    if not st.answered:'
case_ X02-DIRECT-MERGE 1 py '                res = write_git(r, repo, "fast-forward", rec["target"])' '                res = "done" if r.run(p, ["merge", "--ff-only", rec["target"]], ok=(0,)).rc == 0 else "failed"'
case_ X02B-DIRECT-MERGE-RECORDED 1 py '                res = write_git(r, repo, "fast-forward", rec["target"])' '                _x = r.run(p, ["merge", "--ff-only", rec["target"]], ok=(0, 1, 128)); rec["actions"].append({"op": "fast-forward", "to": rec["target"], "rc": _x.rc, "error": ""}); res = "done" if (_x.answered and _x.rc == 0) else "failed"'
case_ X04-OR-TRUE 1 py '    if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:' '    if isinstance(pgid, int) and (pgid > 1 or True):'
case_ X05-WINDOW-48 1 py '    at = line.rfind("@")' '    at = line.rfind("@", 0, line.find("://") + 48)'
case_ X06-OK-ALL 1 py '    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0,), final=final)' "    res = r.run(repo, [\"ls-files\", \"-s\", \"-z\"], ok=($(seq -s ', ' 0 255)), final=final)"
case_ X07-HOOKS-OVERRIDE 1 py '"fetch.recurseSubmodules=false", "core.askPass=",' '"fetch.recurseSubmodules=false", "core.askPass=", "core.hooksPath=.githooks",'
case_ KILLPG-OR 1 py 'if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:' 'if isinstance(pgid, int) and pgid > 1 or pgid == p.pid:'
case_ KILLPG-NOT 1 py 'if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:' 'if not (isinstance(pgid, int) and pgid > 1 and pgid == p.pid):'
case_ KILLPG-GE1 1 py 'if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:' 'if isinstance(pgid, int) and pgid >= 1 and pgid == p.pid:'
case_ KILLPG-EXTRA-TERM 1 py 'if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:' 'if isinstance(pgid, int) and pgid > 1 and pgid == p.pid and pgid != 2:'
case_ KILLPG-ELSE 1 py '        if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:
            try:' '        if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:
            pass
        else:
            try:'
case_ KILLPG-REBIND 1 py '        if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:' '        pgid = 1
        if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:'
case_ KILLPG-OWN-GROUP 1 py '        pgid = os.getpgid(p.pid)' '        pgid = os.getpgid(0)'
case_ KILLPG-SIG9 1 py '    for sig in (signal.SIGTERM, signal.SIGKILL):' '    for sig in (signal.SIGTERM, 9):'
# round 6 (RV5-1): the signal point sends SIGTERM, then SIGKILL, nothing else, in that order, from one loop
case_ KILLPG-SIGKILL-ONLY 1 py '    for sig in (signal.SIGTERM, signal.SIGKILL):' '    for sig in (signal.SIGKILL,):'
case_ KILLPG-ORDER-REVERSED 1 py '    for sig in (signal.SIGTERM, signal.SIGKILL):' '    for sig in (signal.SIGKILL, signal.SIGTERM):'
case_ KILLPG-SIGINT 1 py '                os.killpg(pgid, sig)' '                os.killpg(pgid, signal.SIGINT)'
case_ KILLPG-SIG-REBOUND 1 py '                os.killpg(pgid, sig)' '                sig = signal.SIGKILL
                os.killpg(pgid, sig)'
case_ SELECT-OUTSIDE 1 py 'def now_utc():' 'def _s():
    return select.select([], [], [], 0)


def now_utc():'
case_ WAITID-OUTSIDE 1 py 'def now_utc():' 'def _w(pid):
    return os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)


def now_utc():'
case_ UPDATE-STRATEGY-OK-128 1 py '    cf = r.run(repo, ["config", "-z", "--get-regexp", r"^submodule\..*\.update$"], ok=(0, 1))' '    cf = r.run(repo, ["config", "-z", "--get-regexp", r"^submodule\..*\.update$"], ok=(0, 1, 128))'
case_ CONFIG-WRITE-SHAPE 1 py '    cf = r.run(repo, ["config", "-z", "--get-regexp", r"^submodule\..*\.update$"], ok=(0, 1))' '    cf = r.run(repo, ["config", "-z", "--unset-all", r"^submodule\..*\.update$"], ok=(0, 1))'
case_ NO-NEW-SESSION 1 py 'stderr=subprocess.PIPE, env=env, start_new_session=True)' 'stderr=subprocess.PIPE, env=env, start_new_session=False)'
case_ OK-128-AT-READ 1 py '    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0,), final=final)' '    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0, 128), final=final)'
case_ OK-TWO 1 py '    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0,), final=final)' '    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0, 2), final=final)'
case_ WANT-DROPPED 1 py '["rev-parse", "--verify", "-q", "HEAD^{commit}"], ok=(0, 1), want=SHA_RE, final=final)' '["rev-parse", "--verify", "-q", "HEAD^{commit}"], ok=(0, 1), final=final)'
case_ FETCH-ELSEWHERE 1 py 'def now_utc():' 'def _f(r, p):
    return r.run(p, fetch_args("origin", False), ok=(0, 1, 128))


def now_utc():'
case_ WRITE-VIA-CONST 1 py 'def now_utc():' '_FF = ["merge", "--ff-only"]


def _w(r, p):
    return r.run(p, _FF, ok=(0,))


def now_utc():'
case_ CFG-CASE-OVERRIDE 1 py '"fetch.recurseSubmodules=false", "core.askPass=",' '"fetch.recurseSubmodules=false", "core.askPass=", "CORE.HOOKSPATH=.githooks",'
case_ CFG-EXTRA-KEY 1 py '"fetch.recurseSubmodules=false", "core.askPass=",' '"fetch.recurseSubmodules=false", "core.askPass=", "core.sshCommand=sh",'
case_ TRACE-KEPT 1 py 'k in _SCRUB or k.startswith("GIT_TRACE") or ' 'k in _SCRUB or '
case_ CURL-VERBOSE-KEPT 1 py '"GIT_CURL_VERBOSE", ' ''
case_ AUTH-NOT-REDACTED 1 py '_AUTH.sub(r"\1[REDACTED]", strip_userinfo(text))' 'strip_userinfo(text)'
case_ REDACT-URL-LINEWISE 1 py '        u = u[:m.end()] + u[at + 1:]
' '        pass
'
case_ REPORT-KEY-RAW 1 py '            rk = redact(k)  # a key' '            rk = k  # a key'
case_ REGISTRY-OFF 1 py '        _KNOWN.update(p for p in pieces if len(p) >= 8)' '        pass'
case_ ARGPARSE-RAW 1 py '(self.prog, redact(message))' '(self.prog, message)'
case_ SITE-MOVED 1 py '    names = g_out(r, p, ["remote"], ok=(0,))' '    names = (lambda: g_out(r, p, ["remote"], ok=(0,)))()'
# round 9: the errno / stat modules added for the path-access layer are allow-listed by exact name only
case_ STAT-NAME-UNLISTED 1 py '        if not stat.S_ISREG(st.st_mode):' '        if not stat.filemode(st.st_mode):'
case_ ERRNO-ALIASED 1 py 'import errno' 'import errno as e_'
# the GATE mutated: its oracle must be load-bearing in both directions
gcase_() {
  local label="$1" old="$2" new="$3" d="$tmp/$1" g="$tmp/$1.gate.sh"
  mkdir -p "$d/scripts/sync"
  cp "$repo/scripts/sync/sync_all_upstreams.py" "$repo/scripts/sync/sync_all_upstreams.sh" "$d/scripts/sync/"
  if ! python3 -I -c 'import sys
p,o,n,q=sys.argv[1:5]; s=open(p).read()
if s.count(o)!=1: sys.exit(3)
open(q,"w").write(s.replace(o,n))' "$gate" "$old" "$new" "$g"; then
    echo "META: $label: gate anchor not found exactly once"; bad=1; return
  fi
  local out rc; out="$(bash "$g" --root "$d" 2>&1)"; rc=$?; n=$((n+1))
  if [ "$rc" = 1 ]; then echo "ok   $label (rc=$rc) :: $(first_fail "$out")"; else echo "BAD  $label: rc=$rc expected 1"; bad=1; fi
}
gcase_ ORACLE-ROW-DROPPED '    ("index_gitlinks", "['"'"'ls-files'"'"', '"'"'-s'"'"', '"'"'-z'"'"']", (0,), "-", "blind"),
' ''
gcase_ ORACLE-CLASS-WRONG '    ("index_gitlinks", "['"'"'ls-files'"'"', '"'"'-s'"'"', '"'"'-z'"'"']", (0,), "-", "blind"),' '    ("index_gitlinks", "['"'"'ls-files'"'"', '"'"'-s'"'"', '"'"'-z'"'"']", (0,), "-", "failed"),'
# review round 11 (RV10-3): the canonical git-env scrub is the only alias allowed, in its exact form only
case_ R11-SCRUB-SYSTEM 1 py '_ge_os.environ.pop(_ge_v, None)' '_ge_os.system(_ge_v)'
case_ R11-SCRUB-ALIAS-ELSEWHERE 1 py 'def now_utc():' 'def _y():
    return _ge_os.getcwd()


def now_utc():'
# another module under the scrub alias does not even load (subprocess has no environ): BLIND, never PASS
case_ R11-SCRUB-OTHER-MODULE 2 py 'import os as _ge_os' 'import subprocess as _ge_os'
case_ R11-SCRUB-LOOPVAR-ELSEWHERE 1 py 'def now_utc():' 'def _z():
    return _ge_v


def now_utc():'
# review round 12 (the ref-resolution class, RV11-1): an object named by a bare id or by a ref name, the exact-name
# rule switched off, the upstream resolved by rev-parse's lookup rules again -> the gate FAILs
case_ R12-MERGE-BARE-ID 1 py '["merge", "--ff-only", obj(target)]' '["merge", "--ff-only", target]'
case_ R12-CHECKOUT-BARE-ID 1 py '["checkout", "--quiet", "--detach", obj(target)]' '["checkout", "--quiet", "--detach", target]'
case_ R12-NO-OBJECT-NAMES 1 py '    check_object_names(sub, rest)
' ''
case_ R12-OBJ-BARE 1 py 'return sha + "^{commit}" if isinstance(sha, str) and SHA_RE.fullmatch(sha) else INVALID_OBJ' 'return sha if isinstance(sha, str) and SHA_RE.fullmatch(sha) else INVALID_OBJ'
case_ R12-UPSTREAM-DWIM 1 py '        res, sha = resolve_ref_exact(r, p, "refs/remotes/%s/%s" % (rem["_name"], branch), notes)' '        res = r.run(p, ["rev-parse", "--verify", "-q", "refs/remotes/%s/%s^{commit}" % (rem["_name"], branch)], ok=(0, 1), want=SHA_RE)
        sha = res.text()'
case_ R12-EXACT-ANY-PATTERN 1 py 'and valid_branch_name(ref[len("refs/"):])' ''
case_ R12-NO-PIN 1 py '    env.update(OBJECT_VISIBILITY_PIN)
' ''
# review round 13 (RV12-1, RV12-2, RV12-3): the symref field dropped from either lookup, the literal-path pin
# dropped, a rev-list shape without '--' -> the gate FAILs
case_ R13-EXACT-NO-SYMREF 1 py 'FER_EXACT_FORMAT = "%(refname)%00%(symref)%00' 'FER_EXACT_FORMAT = "%(refname)%00%(refname)%00'
case_ R13-CONTAINS-NO-SYMREF 1 py 'FER_CONTAINS_FORMAT = "%(refname)%00%(symref)"' 'FER_CONTAINS_FORMAT = "%(refname)%00%(refname)"'
case_ R13-NO-LITERAL-PIN 1 py '    env.update(PATH_LITERAL_PIN)
' ''
case_ R13-LITERAL-NOT-SCRUBBED 1 py '"GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS",' ''
case_ R13-REVLIST-NO-DDASH 1 py '["rev-list", "--count", "HEAD", "--"]' '["rev-list", "--count", "HEAD"]'
case_ R13-CONTAINS-OLD-FORMAT 1 py '["for-each-ref", "--contains", obj(gitlink), "--format=" + FER_CONTAINS_FORMAT, "refs/remotes"]' '["for-each-ref", "--contains", obj(gitlink), "--format=%(refname)", "refs/remotes"]'
# review round 14 (RV13-4, reviewer mutant RV13J): HEAD accepted beside an id in the rev-list range -> the gate FAILs
case_ R14-REVLIST-HEAD-BESIDE-ID 1 py '                 and all(_exact_obj(x) for x in rng)):' '                 and all(_exact_obj(x) or x == "HEAD" for x in rng)):'
case_ SYNTAX 2 py 'def classify(ahead, behind):' 'def classify(ahead, behind'
case_ MISSING 2 none "" ""
echo "cases: $n"
[ "$bad" = 0 ] && echo "CM-SYNC-UPSTREAMS-FF-ONLY mutation test: PASS ($n cases)" || echo "CM-SYNC-UPSTREAMS-FF-ONLY mutation test: FAIL"
exit "$bad"
