#!/usr/bin/env python3
"""scripts/sync/robustness_checks.py -- the body of tests/sync/test_robustness.sh (review round 4 findings).

Behavioural checks that drive the REAL engine (the wrapper in $SX_ENGINE, default scripts/sync/
sync_all_upstreams.sh) through its real invocation path against REAL git repositories in a sandbox
(tempfile.mkdtemp under $TMPDIR; file:// and 127.0.0.1 only, no network, no forge, nothing in $HOME).

Evidence class (section 11.4.289): gate-logic / unit class (section 11.4.289(C)(2)): the real engine and the real git
binary, against local file:// repositories only; nothing here is evidence of forge behaviour (ssh keys, rate limits,
server-side refusals), which stays UNCONFIRMED. Some checks stand a small program in for a
HOSTILE REMOTE or a USER (labelled per check as "fixture"): a remote.<name>.uploadpack program that writes a
long or hostile stderr, hangs, or prints an Authorization header; an askpass / ext:: helper that records it was
run; scripts/sync/race_git_shim.py, which acts as a user between the engine's inspection and its write and then
runs the real git; scripts/sync/inproc_driver.py (round 7), which loads the real engine module and injects ONE
environment fault (a signal, the clock, the kernel) at a point no outside program can hit in time. None of them
replaces the engine or git.

Hostile text (long lines, control characters, credential-shaped strings) is built here, in Python, never in a
shell heredoc. Clean-up goes through scripts/lib/safe_rm.sh (safe_rm_rf, restricted to the sandbox). A process
is signalled only when the test started it (its own pid), or, for a leaked descendant, after its
/proc/<pid>/cmdline is read and found to name the sandbox (section 11.4.263).

Usage: python3 -I scripts/sync/robustness_checks.py [--only NAME,NAME] [--list]
Exit 0 every check passed, 1 a check failed, 2 the sandbox could not be built.
"""
import fcntl
import http.server
import json
import os
import resource
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ENGINE = os.environ.get("SX_ENGINE") or os.path.join(REPO, "scripts", "sync", "sync_all_upstreams.sh")
SHIM = os.path.join(HERE, "race_git_shim.py")
GIT = shutil.which("git")
PY = sys.executable or "/usr/bin/python3"
PASS, FAIL = [], []


def ok(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print("  %s %s%s" % ("ok  " if cond else "FAIL", name, "" if cond else "  (%s)" % detail), flush=True)


def write_exec(path, text):
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, 0o755)


class Box:
    """One sandbox: bare remotes, producer clones, working clones, evidence dirs; real git only."""
    def __init__(self, name):
        self.root = tempfile.mkdtemp(prefix="helix-sync-robust.%s." % name, dir=os.environ.get("TMPDIR") or None)
        for d in ("remotes", "seed", "work", "out", "shim", "cache", "bin"):
            os.makedirs(os.path.join(self.root, d))
        self.gitconfig = self.p("gitconfig")
        with open(self.gitconfig, "w") as f:
            f.write("[init]\n\tdefaultBranch = main\n[protocol \"file\"]\n\tallow = always\n"
                    "[advice]\n\tdetachedHead = false\n[user]\n\tname = sync-robust\n"
                    "\temail = sync@example.invalid\n")
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "SXR_", "SSH_ASKPASS"))}
        self.env.update({"GIT_CONFIG_GLOBAL": self.gitconfig, "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0",
                         "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
                         "GIT_CEILING_DIRECTORIES": os.path.dirname(self.root), "LC_ALL": "C",
                         "XDG_CACHE_HOME": self.p("cache")})
        self.n = 0

    def p(self, *parts):
        return os.path.join(self.root, *parts)

    def git(self, cwd, *args, check=True):
        r = subprocess.run([GIT, "-C", cwd] + list(args), env=self.env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True)
        if check and r.returncode != 0:
            raise RuntimeError("git %s in %s: %s" % (args, cwd, r.stderr.strip()))
        return r.stdout.strip()

    def bare(self, org, name):
        d = self.p("remotes", org, name + ".git")
        os.makedirs(os.path.dirname(d), exist_ok=True)
        self.git(self.root, "init", "-q", "--bare", d)
        w = self.p("seed", org + "-" + name)
        self.git(self.root, "init", "-q", w)
        with open(os.path.join(w, "README"), "w") as f:
            f.write(name + "\n")
        self.git(w, "add", "README")
        self.git(w, "commit", "-q", "-m", "init " + name)
        self.git(w, "remote", "add", "origin", "file://" + d)
        self.git(w, "push", "-q", "origin", "main")
        return "file://" + d, w

    def commit(self, w, msg, fname="CHANGES"):
        with open(os.path.join(w, fname), "a") as f:
            f.write(msg + "\n")
        self.git(w, "add", fname)
        self.git(w, "commit", "-q", "-m", msg)
        self.git(w, "push", "-q", "origin", "HEAD:main")
        return self.git(w, "rev-parse", "HEAD")

    def add_sub(self, w, url, path):
        self.git(w, "-c", "protocol.file.allow=always", "submodule", "add", "-q", url, path)
        self.git(w, "commit", "-q", "-m", "add " + path)
        self.git(w, "push", "-q", "origin", "HEAD:main")

    def clone(self, url, name):
        d = self.p("work", name)
        self.git(self.root, "-c", "protocol.file.allow=always", "clone", "-q", "--recurse-submodules", url, d)
        return d

    def shim(self):
        """A `git` on PATH that runs race_git_shim.py (which then runs the real git)."""
        write_exec(self.p("shim", "git"), "#!/bin/sh\nexec %s -I %s \"$@\"\n" % (PY, SHIM))
        return self.p("shim")

    def engine_argv(self, *args):
        self.n += 1
        out = self.p("out", "r%d" % self.n)
        return ["bash", ENGINE] + list(args) + ["--run-id", "r%d" % self.n], out

    def run(self, *args, env=None, path_prefix=None, out=True, timeout=600):
        """Runs the engine; returns (rc, stdout, stderr, report or None, seconds)."""
        argv, o = self.engine_argv(*args)
        if out:
            argv += ["--out", o]
        e = dict(self.env)
        if env:
            e.update(env)
        if path_prefix:
            e["PATH"] = path_prefix + os.pathsep + e.get("PATH", "")
        t = time.monotonic()
        r = subprocess.run(argv, env=e, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
        rep = None
        try:
            with open(os.path.join(o, "sync_report.json"), encoding="utf-8") as f:
                rep = json.load(f)
        except (OSError, ValueError):
            pass
        return r.returncode, r.stdout, r.stderr, rep, time.monotonic() - t

    def cleanup(self):
        for dp, dn, fn in os.walk(self.root):
            for d in dn:
                try:
                    os.chmod(os.path.join(dp, d), 0o700)
                except OSError:
                    pass
        subprocess.run(["bash", "-c", '. "$1/scripts/lib/safe_rm.sh"; SAFE_RM_ALLOWED_ROOTS="$2" safe_rm_rf "${2:?}"',
                        "_", REPO, self.root], check=False)


def rec(rep, path):
    for r in (rep or {}).get("repos", []):
        if r.get("path") == path:
            return r
    return {}


def blob_of(box, rc_out, rc_err, out_dir):
    parts = [rc_out, rc_err]
    for n in ("sync_report.json", "sync_report.tsv"):
        try:
            with open(os.path.join(out_dir, n), encoding="utf-8") as f:
                parts.append(f.read())
        except OSError:
            pass
    return "\n".join(parts)


def pinned_tree(box):
    """root (org HelixDevelopment) with own-org submodule libs/a; a working clone; then upstream a moves (S2) and
    root records libs/a@S2 (R2). Returns (work, a_seed, r_seed, s1, s2, r1, r2)."""
    a_url, a_seed = box.bare("HelixDevelopment", "a")
    r_url, r_seed = box.bare("HelixDevelopment", "root")
    box.add_sub(r_seed, a_url, "libs/a")
    work = box.clone(r_url, "p")
    s1 = box.git(os.path.join(work, "libs/a"), "rev-parse", "HEAD")
    r1 = box.git(work, "rev-parse", "HEAD")
    s2 = box.commit(a_seed, "a: upstream S2")
    sub_seed = os.path.join(r_seed, "libs/a")
    box.git(r_seed, "-c", "protocol.file.allow=always", "submodule", "update", "-q", "--init", "--", "libs/a")
    box.git(sub_seed, "fetch", "-q", "origin")
    box.git(sub_seed, "checkout", "-q", s2)
    box.git(r_seed, "add", "libs/a")
    box.git(r_seed, "commit", "-q", "-m", "root: R2 bumps libs/a")
    box.git(r_seed, "push", "-q", "origin", "HEAD:main")
    r2 = box.git(r_seed, "rev-parse", "HEAD")
    return work, a_seed, r_seed, s1, s2, r1, r2


def race_env(box, action, on, target, **extra):
    e = {"SXR_GIT": GIT, "SXR_ACTION": action, "SXR_ON": on, "SXR_TARGET": target, "SXR_MARK": box.p("mark")}
    e.update(extra)
    return e


# ───────────────────────── RV4-1: every write precondition re-read at write time ─────────────────────────
def c_race_commit_detached_sub(box):
    """P01 model. Fixture: the race shim (a user) commits on the detached submodule after inspection."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    sub = os.path.join(work, "libs/a")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "commit", "fetch@" + work, sub))
    user = open(box.p("mark.sha")).read().strip() if os.path.exists(box.p("mark.sha")) else None
    ok("race_commit.action_fired", user is not None)
    ok("race_commit.user_commit_still_checked_out", box.git(sub, "rev-parse", "HEAD") == user,
       "sub HEAD %s user %s" % (box.git(sub, "rev-parse", "HEAD"), user))
    a = rec(rep, "libs/a")
    ok("race_commit.not_reported_updated", a.get("result") != "updated", a.get("result"))
    ok("race_commit.run_not_applied", rc != 0 and "RESULT: APPLIED" not in so, "rc=%s" % rc)
    ok("race_commit.refusal_recorded", "head-changed" in json.dumps(a.get("actions")), a.get("actions"))


def c_race_switch_root_branch(box):
    """P02 model. Fixture: the user switches the root to a new branch 'topic' after inspection."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "switch-branch", "fetch@" + os.path.join(work, "libs/a"), work))
    topic = box.git(work, "rev-parse", "refs/heads/topic", check=False)
    main = box.git(work, "rev-parse", "refs/heads/main")
    ok("race_switch.action_fired", bool(topic))
    ok("race_switch.topic_not_moved", topic == r1, "topic %s r1 %s r2 %s" % (topic, r1, r2))
    ok("race_switch.main_not_moved", main == r1)
    ok("race_switch.run_not_applied", rc != 0, "rc=%s" % rc)
    ok("race_switch.refusal_recorded", "branch-changed" in json.dumps(rec(rep, ".").get("actions")),
       rec(rep, ".").get("actions"))


def c_race_branch_in_sub(box):
    """P04 model. Fixture: the user checks out a branch in the detached submodule after inspection."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    sub = os.path.join(work, "libs/a")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "checkout-branch", "fetch@" + work, sub))
    br = box.git(sub, "symbolic-ref", "-q", "--short", "HEAD", check=False)
    ok("race_sub_branch.action_fired", os.path.exists(box.p("mark")))
    ok("race_sub_branch.submodule_still_on_branch", br == "user-branch", "branch now %r" % br)
    ok("race_sub_branch.head_not_moved", box.git(sub, "rev-parse", "HEAD") == s1)


def c_race_control_commit_on_main(box):
    """P03 model (control: ff-only already refuses this; it must stay so)."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "commit", "fetch@" + os.path.join(work, "libs/a"), work))
    user = open(box.p("mark.sha")).read().strip() if os.path.exists(box.p("mark.sha")) else None
    ok("race_control.user_commit_kept_on_main", user is not None and box.git(work, "rev-parse", "main") == user)
    ok("race_control.not_applied", rc != 0, "rc=%s" % rc)


def c_race_other_writer_reported(box):
    """P05 model (round 5). Fixture: an --apply run while the user commits on the root after inspection read its
    HEAD (a --check run writes nothing and re-reads no head, so only --apply can see the move). The root's head moved,
    but not to anything this run wrote: the record must say so (head-changed-during-run, moved, changed_by_other),
    never present the move as this run's update."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "commit", "fetch@" + os.path.join(work, "libs/a"), work))
    user = open(box.p("mark.sha")).read().strip() if os.path.exists(box.p("mark.sha")) else None
    root = rec(rep, ".")
    ok("race_other.action_fired_control", user is not None and box.git(work, "rev-parse", "HEAD") == user)
    ok("race_other.head_moved_recorded", root.get("moved") is True and root.get("head_after") == user,
       "moved %s head_after %s user %s" % (root.get("moved"), root.get("head_after"), user))
    ok("race_other.reason_head_changed_during_run", "head-changed-during-run" in root.get("reasons", []),
       root.get("reasons"))
    ok("race_other.changed_by_other", root.get("changed_by_other") is True, root.get("changed_by_other"))
    ok("race_other.not_reported_updated", root.get("result") != "updated" and rc != 0 and "RESULT: APPLIED" not in so,
       "rc=%s result=%s" % (rc, root.get("result")))


def c_autostash_race(box):
    """V02. Fixture: the user edits a tracked file the fast-forward changes, at the engine's merge call (after
    every guard); the repository config asks for merge.autoStash. The engine's -c merge.autoStash=false makes
    the merge refuse; an autostash would stash, move HEAD and leave conflict state behind."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    box.commit(r_seed, "upstream edits README", fname="README")
    box.git(work, "config", "merge.autoStash", "true")
    before = box.git(work, "rev-parse", "HEAD")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "touch-file", "merge@" + work, work, SXR_FILE="README"))
    ok("autostash.action_fired", os.path.exists(box.p("mark")))
    ok("autostash.head_not_moved", box.git(work, "rev-parse", "HEAD") == before)
    ok("autostash.no_stash_created", box.git(work, "stash", "list") == "")
    ok("autostash.user_edit_kept", "user edit made" in open(os.path.join(work, "README")).read())
    ok("autostash.failed_verdict", rc == 1, "rc=%s" % rc)
    # RV7-2 / mutant RV7E: git ended the write itself with a declared non-zero status: its marker is removed
    ok("autostash.no_marker_after_answered_failure", not os.path.exists(os.path.join(work, ".git", MARKER)))


def c_sigterm_during_write(box):
    """RV4-5 + 'never a silent half-applied state'. Fixture: the race shim sends SIGTERM to the engine (its parent,
    cmdline verified) at the merge call, then runs the real merge; the write must complete, the run must stop
    there, write its report and say INTERRUPTED (exit 8) with the move recorded."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "sigterm-parent", "merge@" + work, work))
    t_end = time.monotonic() + 20  # the shim writes its marker after its one-second pause (it may outlive the run)
    while not os.path.exists(box.p("mark.signalled")) and time.monotonic() < t_end:
        time.sleep(0.2)
    time.sleep(1)
    ok("sigterm_write.signal_sent", os.path.exists(box.p("mark.signalled")))
    ok("sigterm_write.exit_8", rc == 8, "rc=%s stderr=%s" % (rc, se[-300:]))
    ok("sigterm_write.result_line", "RESULT: INTERRUPTED exit=8" in so, so[-200:])
    ok("sigterm_write.report_written", rep is not None and rep.get("verdict") == "INTERRUPTED")
    root = rec(rep, ".")
    ok("sigterm_write.move_recorded", root.get("moved") is True and root.get("head_after") == r2,
       "moved=%s head_after=%s r2=%s" % (root.get("moved"), root.get("head_after"), r2))
    ok("sigterm_write.root_really_at_r2", box.git(work, "rev-parse", "HEAD") == r2)
    ok("sigterm_write.no_traceback", "Traceback" not in se)


def hang_remote(box, name):
    """A file:// remote whose upload-pack program records its pid and then sleeps (fixture: a hanging remote)."""
    r_url, r_seed = box.bare("HelixDevelopment", name)
    work = box.clone(r_url, "w_" + name)
    prog = box.p("bin", "hang_" + name)
    write_exec(prog, "#!%s -I\nimport os, time\nopen(%r, 'w').write(str(os.getpid()))\ntime.sleep(120)\n"
               % (PY, box.p("hang_" + name + ".pid")))
    box.git(work, "config", "remote.origin.uploadpack", prog)
    return work, box.p("hang_" + name + ".pid"), prog


def alive_ours(pid, needle):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            return needle.encode() in f.read()
    except OSError:
        return False


def c_signal_during_fetch(box, sig, label):
    """P18 / P19 model: a signal while a fetch hangs. The engine must stop the fetch's process group, write its
    report and exit 8 (INTERRUPTED) quickly, with no traceback and no orphaned descendant."""
    work, pidfile, prog = hang_remote(box, label)
    argv, o = box.engine_argv("--check", "--root", work, "--quiet", "--timeout", "100", "--deadline", "200")
    argv += ["--out", o]
    p = subprocess.Popen(argv, env=box.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    t_end = time.monotonic() + 60
    while not os.path.exists(pidfile) and time.monotonic() < t_end and p.poll() is None:
        time.sleep(0.1)
    hang_pid = int(open(pidfile).read()) if os.path.exists(pidfile) else None
    ok("%s.fetch_hanging" % label, hang_pid is not None)
    t0 = time.monotonic()
    p.send_signal(sig)  # the engine process itself (bash exec'd python3: same pid), started by this test
    try:
        so, se = p.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        p.kill()
        so, se = p.communicate()
    dt = time.monotonic() - t0
    time.sleep(0.5)
    orphan = hang_pid is not None and alive_ours(hang_pid, prog)
    if orphan:  # clean up a leaked descendant: our own sandbox program, verified by its cmdline (one pid)
        os.kill(hang_pid, signal.SIGKILL)
    ok("%s.exits_fast" % label, dt < 15, "%.1fs" % dt)
    ok("%s.exit_8" % label, p.returncode == 8, "rc=%s" % p.returncode)
    ok("%s.no_traceback" % label, "Traceback" not in se, se[-300:])
    ok("%s.no_orphan" % label, not orphan)
    try:
        rep = json.load(open(os.path.join(o, "sync_report.json")))
    except (OSError, ValueError):
        rep = None
    ok("%s.report_interrupted" % label, rep is not None and rep.get("verdict") == "INTERRUPTED")


def c_no_new_call_after_stop(box):
    """P14 model (round 5). Fixture: the race shim sends SIGTERM to the engine at the root's fetch (--jobs 1, so the
    submodule's calls come later) and logs every git call it sees. After the stop, the engine may only run its final
    head reads (rev-parse, symbolic-ref); every other call must be refused before a process is started."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    log = box.p("calls.log")
    rc, so, se, rep, _ = box.run("--check", "--jobs", "1", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "sigterm-parent", "fetch@" + work, work, SXR_LOG=log))
    lines = [l.split("\t") for l in open(log).read().splitlines()] if os.path.exists(log) else []
    before = [l for l in lines if len(l) == 3 and l[2] == "before"]
    after = [l for l in lines if len(l) == 3 and l[2] == "after"]
    ok("no_new_call.control_trigger_seen", ["fetch", os.path.realpath(work), "before"] in lines, lines[:6])
    ok("no_new_call.control_interrupted", rc == 8 and (rep or {}).get("verdict") == "INTERRUPTED", "rc=%s" % rc)
    started = [l for l in after if l[0] not in ("rev-parse", "symbolic-ref")]
    ok("no_new_call.only_final_reads_after_stop", not started, started[:6])
    # a call started after the stop is killed at once (its process group), usually before the shim can even log
    # it: the engine's own count of started calls (git_calls) must equal the calls the shim saw. A --check run
    # writes nothing, so it has no final head reads either.
    calls = (rep or {}).get("git_calls")
    ok("no_new_call.no_call_started_after_stop", calls == len(lines),
       "git_calls %s, calls seen by the shim %d (before %d after %d)" % (calls, len(lines), len(before), len(after)))


def c_final_read_capped_after_stop(box):
    """P33 model (round 5). Fixture: SIGTERM at the root's fetch of an --apply run (--jobs 1), and every rev-parse
    started after it hangs 45 s (the shim). The final head reads after a stop run with at most 10 s each, so the run
    ends well before two hung reads could finish; without the cap each would get the normal 60 s limit."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    log = box.p("calls.log")
    t = time.monotonic()
    rc, so, se, rep, _ = box.run("--apply", "--jobs", "1", "--root", work, "--quiet", "--timeout", "15",
                                 path_prefix=box.shim(),
                                 env=race_env(box, "sigterm-parent", "fetch@" + work, work, SXR_LOG=log,
                                              SXR_HANG_AFTER="rev-parse:45"))
    dt = time.monotonic() - t
    after = [l.split("\t")[0] for l in open(log).read().splitlines() if l.endswith("\tafter")] \
        if os.path.exists(log) else []
    root = rec(rep, ".")
    ok("final_cap.control_interrupted", rc == 8 and (rep or {}).get("verdict") == "INTERRUPTED", "rc=%s" % rc)
    ok("final_cap.control_final_reads_started_and_hung", after.count("rev-parse") >= 2, after)
    ok("final_cap.ends_within_cap", dt < 40, "%.1fs" % dt)
    ok("final_cap.timed_out_read_recorded", "unresolved:rev-parse:timeout" in root.get("reasons", [])
       and root.get("head_unreadable") is True, root.get("reasons"))


def c_sigterm_fetch(box):
    c_signal_during_fetch(box, signal.SIGTERM, "sigterm_fetch")


def c_sigint_fetch(box):
    c_signal_during_fetch(box, signal.SIGINT, "sigint_fetch")


# ───────────────────────── RV4-2: a gitlink the user staged ─────────────────────────
def c_staged_gitlink(box):
    """P32 model: the user staged libs/a at X; --advance-pins must not replace it and must say why."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    sub = os.path.join(work, "libs/a")
    # the root's own upstream does not move: only the child's upstream (S2 exists) -> pin behind-main
    box.git(work, "fetch", "-q", "origin")
    box.git(work, "update-ref", "refs/remotes/origin/main", r1)
    box.git(r_seed, "push", "-q", "-f", "origin", r1 + ":main")
    x = box.commit(a_seed, "a: S3 (upstream moves again)")
    box.git(sub, "fetch", "-q", "origin")
    box.git(sub, "checkout", "-q", "--detach", s2)
    box.git(work, "add", "libs/a")  # the user stages libs/a at S2 (not committed)
    box.git(sub, "checkout", "-q", "--detach", s2)
    staged = box.git(work, "ls-files", "-s", "libs/a").split()[1]
    rc, so, se, rep, _ = box.run("--apply", "--advance-pins", "--root", work, "--quiet")
    now = box.git(work, "ls-files", "-s", "libs/a").split()[1]
    ok("staged_gitlink.index_untouched", now == staged == s2, "staged %s now %s s2 %s x %s" % (staged, now, s2, x))
    ok("staged_gitlink.reason_reported", "gitlink-staged:libs/a" in rec(rep, ".").get("reasons", []),
       rec(rep, ".").get("reasons"))
    ok("staged_gitlink.attention", rc == 4, "rc=%s" % rc)


# ───────────────────────── RV4-3 / RV4-4: bounded, linear handling of what a remote sends ─────────────────────────
def stderr_remote(box, name, body_py):
    r_url, r_seed = box.bare("HelixDevelopment", name)
    work = box.clone(r_url, "w_" + name)
    box.commit(r_seed, "upstream moves")
    prog = box.p("bin", "emit_" + name)
    write_exec(prog, "#!%s -I\nimport os, sys\n%s\nos._exit(1)\n" % (PY, body_py))
    box.git(work, "config", "remote.origin.uploadpack", prog)
    return work


def c_escaped_grandchild_after_exit(box):
    """M53 model (F8, round 5). Fixture: the remote's upload-pack program starts a grandchild in its own session that
    keeps git's STDERR pipe open for 40 s, then runs the real upload-pack, so git itself answers and exits at once.
    The engine must stop reading as soon as git has exited: the fetch answers (the remote is reachable, the root is
    behind) within a few seconds, not after --timeout. The grandchild is signalled afterwards by pid only, after its
    /proc cmdline shows this fixture's marker (section 11.4.263)."""
    r_url, r_seed = box.bare("HelixDevelopment", "escaper")
    work = box.clone(r_url, "w_escaper")
    box.commit(r_seed, "upstream moves")
    marker = "helixsyncescaper%d" % os.getpid()
    pidf = box.p("escaper.pid")
    prog = box.p("bin", "escaper_uploadpack")
    write_exec(prog, "#!%s -I\nimport os, sys\npid = os.fork()\nif pid == 0:\n    os.setsid()\n"
               "    if os.fork():\n        os._exit(0)\n    fd = os.open(os.devnull, os.O_RDWR)\n"
               "    os.dup2(fd, 0)\n    os.dup2(fd, 1)\n    open(%r, 'w').write(str(os.getpid()))\n"
               "    os.execv(%r, [%r, '-I', '-c', 'import time; time.sleep(40)', %r])\n"
               "os.waitpid(pid, 0)\nos.execv(%r, [%r, 'upload-pack'] + sys.argv[1:])\n"
               % (PY, pidf, PY, PY, marker, GIT, GIT))
    box.git(work, "config", "remote.origin.uploadpack", prog)
    rc, so, se, rep, dt = box.run("--check", "--root", work, "--quiet", "--timeout", "15", "--deadline", "60")
    gpid = 0
    try:
        gpid = int(open(pidf).read().strip())
    except (OSError, ValueError):
        pass
    alive = gpid > 1 and alive_ours(gpid, marker)
    ok("escaped_after_exit.control_grandchild_alive_after_run", alive, "pid %s" % gpid)
    ok("escaped_after_exit.answer_not_waiting_for_the_pipe", dt < 10, "%.1fs rc=%s" % (dt, rc))
    root = rec(rep, ".") if rep else {}
    states = [x.get("state") for x in root.get("remotes", [])]
    ok("escaped_after_exit.remote_reachable", states == ["ok"] or (states and "unreachable" not in states),
       "states %s rc=%s" % (states, rc))
    ok("escaped_after_exit.root_behind_exit_3", rc == 3 and root.get("result") == "behind",
       "rc=%s result=%s" % (rc, root.get("result")))
    if alive and gpid > 1:
        try:
            os.kill(gpid, signal.SIGTERM)
        except OSError:
            pass


def c_long_stderr_line(box):
    """P05 model. Fixture: a remote program writes ONE 256 KiB stderr line and fails. The run must finish within
    its --deadline plus a small grace, not spend minutes redacting."""
    work = stderr_remote(box, "longline", "os.write(2, b'remote: ' + b'abc' * (256 * 1024 // 3) + b'\\n')")
    rc, so, se, rep, dt = box.run("--check", "--root", work, "--quiet", "--timeout", "10", "--deadline", "10")
    ok("long_line.bounded_time", dt < 25, "%.1fs rc=%s" % (dt, rc))
    ok("long_line.report_written", rep is not None, "rc=%s" % rc)


def c_huge_stderr_memory(box):
    """RV4-4 model. Fixture: a remote program writes 160 MiB to stderr in 1 MiB chunks and fails. The engine's peak
    memory must stay far below the stream size (a capped reader, not a buffer of everything)."""
    work = stderr_remote(box, "huge", "c = (b'x' * 1023 + b'\\n') * 1024\nfor _ in range(160):\n    os.write(2, c)")
    argv, o = box.engine_argv("--check", "--root", work, "--quiet", "--timeout", "60", "--deadline", "120")
    argv += ["--out", o]
    probe = ("import resource, subprocess, sys\n"
             "r = subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
             "print(r.returncode, resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)\n")
    r = subprocess.run([PY, "-I", "-c", probe] + argv, env=box.env, stdout=subprocess.PIPE, text=True, timeout=600)
    rc, kib = (r.stdout.split() + ["?", "0"])[:2]
    ok("huge_stderr.peak_rss_bounded", int(kib) < 150 * 1024, "maxrss %s KiB rc=%s" % (kib, rc))
    ok("huge_stderr.run_ended_with_report", os.path.exists(os.path.join(o, "sync_report.json")), "rc=%s" % rc)


# ───────────────────────── RV4-6 / RV4-7: the environment and config that could re-enable prompts / helpers ─────────
class _Auth401(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="sync-robust"')
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a):
        pass


def with_401(fn):
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Auth401)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        return fn("http://127.0.0.1:%d/x.git" % srv.server_address[1])
    finally:
        srv.shutdown()


def recorder(box, name):
    marker = box.p(name + ".ran")
    prog = box.p("bin", name)
    write_exec(prog, "#!%s -I\nimport sys\nopen(%r, 'a').write(' '.join(sys.argv[1:]) + '\\n')\nprint('typed')\n"
               % (PY, marker))
    return prog, marker


def c_askpass_all_routes(box):
    """P13 / P43 model (rows D7-D13 of the ground truth). Fixture: a 401 http remote and askpass recorders; no
    route may run a prompt program: repository core.askPass, GIT_ASKPASS, SSH_ASKPASS."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    cfg_prog, cfg_mark = recorder(box, "core_askpass")
    env_prog, env_mark = recorder(box, "git_askpass")
    ssh_prog, ssh_mark = recorder(box, "ssh_askpass")
    box.git(work, "config", "core.askPass", cfg_prog)

    def go(url):
        box.git(work, "remote", "add", "mirror", url)
        return box.run("--check", "--root", work, "--quiet", "--timeout", "15", "--deadline", "60",
                       env={"GIT_ASKPASS": env_prog, "SSH_ASKPASS": ssh_prog, "SSH_ASKPASS_REQUIRE": "force",
                            "DISPLAY": ":0"})
    rc, so, se, rep, _ = with_401(go)
    ok("askpass.core_askPass_not_run", not os.path.exists(cfg_mark))
    ok("askpass.GIT_ASKPASS_not_run", not os.path.exists(env_mark))
    ok("askpass.SSH_ASKPASS_not_run", not os.path.exists(ssh_mark))
    m = [x for x in rec(rep, ".").get("remotes", []) if x.get("name") == "mirror"]
    ok("askpass.remote_reported_unreachable_auth", bool(m) and m[0].get("state") == "unreachable",
       m[0] if m else rep)


def c_askpass_ssh_only(box):
    """V16 / P43 exact model: only SSH_ASKPASS in the caller's environment (no GIT_ASKPASS, no core.askPass)."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    ssh_prog, ssh_mark = recorder(box, "ssh_askpass_only")

    def go(url):
        box.git(work, "remote", "add", "mirror", url)
        return box.run("--check", "--root", work, "--quiet", "--timeout", "15", "--deadline", "60",
                       env={"SSH_ASKPASS": ssh_prog})
    with_401(go)
    ok("askpass_ssh_only.not_run", not os.path.exists(ssh_mark))


def ext_remote(box, name):
    r_url, r_seed = box.bare("HelixDevelopment", name)
    work = box.clone(r_url, "w_" + name)
    helper, marker = recorder(box, "ext_" + name)
    box.git(work, "remote", "add", "evil", "ext::%s %%S" % helper)
    return work, marker


def c_ext_env_allow(box):
    """P12 model (row D2): an ambient GIT_ALLOW_PROTOCOL naming ext must not let a configured ext:: remote run."""
    work, marker = ext_remote(box, "envallow")
    rc, so, se, rep, _ = box.run("--check", "--root", work, "--quiet", "--timeout", "15", "--deadline", "60",
                                 env={"GIT_ALLOW_PROTOCOL": "ext:file"})
    ok("ext_env.helper_not_run", not os.path.exists(marker))


def c_ext_repo_allow(box):
    """V01 (row D3): the repository config says protocol.ext.allow=always; the engine's -c pair must win."""
    work, marker = ext_remote(box, "repoallow")
    box.git(work, "config", "protocol.ext.allow", "always")
    rc, so, se, rep, _ = box.run("--check", "--root", work, "--quiet", "--timeout", "15", "--deadline", "60")
    ok("ext_repo.helper_not_run", not os.path.exists(marker))


def c_protocol_from_user(box):
    """Row D5: an ambient GIT_PROTOCOL_FROM_USER=0 would refuse a file:// remote whose config says
    protocol.file.allow=user; the engine scrubs it, so the run is deterministic: the remote is fetched."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    box.git(work, "config", "protocol.file.allow", "user")
    rc, so, se, rep, _ = box.run("--check", "--root", work, "--quiet", env={"GIT_PROTOCOL_FROM_USER": "0"})
    o = [x for x in rec(rep, ".").get("remotes", []) if x.get("name") == "origin"]
    ok("protocol_from_user.fetched", bool(o) and o[0].get("fetch") == "ok", o)


def c_trace_env(box):
    """GIT_TRACE* in the caller's environment: no trace file is written (it would carry URLs and traffic)."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    t1, t2 = box.p("trace1"), box.p("trace2")
    box.run("--check", "--root", work, "--quiet", env={"GIT_TRACE": t1, "GIT_TRACE_PACKET": t2,
                                                       "GIT_TRACE2_EVENT": t1 + ".ev"})
    ok("trace_env.no_trace_file", not any(os.path.exists(x) for x in (t1, t2, t1 + ".ev")))


def c_auth_header_redacted(box):
    """V04. The engine reports git's stderr only for a write that failed (the last 300 characters of it); a fetch's
    stderr is classified, never printed. So the fixture makes a WRITE fail with an Authorization line on stderr:
    upstream adds a file with a `filter=leak` attribute, the clone's config has a required smudge filter `lk` (on
    PATH) that prints a control needle, then an Authorization header line, and fails; `--apply` fast-forwards and the
    merge fails. The needle must be in the report (the stderr was seen: no false null, round 5) and the credential
    value must not. A user-configured filter running during a merge is a stated boundary; here it is the stderr
    source, nothing else."""
    url, seed = box.bare("HelixDevelopment", "authf")
    work = box.clone(url, "w_authf")
    with open(os.path.join(seed, ".gitattributes"), "w") as f:
        f.write("*.dat filter=leak\n")
    with open(os.path.join(seed, "x.dat"), "w") as f:
        f.write("data\n")
    box.git(seed, "add", ".gitattributes", "x.dat")
    box.git(seed, "commit", "-q", "-m", "a filtered file")
    box.git(seed, "push", "-q", "origin", "HEAD:main")
    tok = "U2VjcmV0" + "VmFsdWU5"
    needle = "helixauthneedle"
    write_exec(box.p("bin", "lk"), "#!%s -I\nimport os\nos.write(2, b'%s\\nAuthorization: Basic %s\\n')\nos._exit(1)\n"
               % (PY, needle, tok))
    box.git(work, "config", "filter.leak.smudge", "lk")
    box.git(work, "config", "filter.leak.required", "true")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--timeout", "15", "--deadline", "60",
                                 path_prefix=box.p("bin"))
    blob = so + se + json.dumps(rep or {})
    ok("auth_header.control_needle_seen", needle in blob and "Authorization: [REDACTED]" in blob, "rc=%s" % rc)
    ok("auth_header.value_redacted", tok not in blob and rep is not None, "rc=%s" % rc)
    ok("auth_header.failed_merge_exit_1", rc == 1, "rc=%s" % rc)


def c_registered_8char_secret(box):
    """V17. A remote URL's 8-character password is remembered: a remote NAMED like it is shown redacted."""
    pw = "Pw8chars"
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    box.git(work, "remote", "add", pw, "http://frank:%s@127.0.0.1:9/x.git" % pw)
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work)
    tsv = open(os.path.join(box.p("out", "r%d" % box.n), "sync_report.tsv")).read() if rep else ""
    ok("secret8.absent_everywhere", rep is not None and pw not in so + se + json.dumps(rep) + tsv)


def c_control_chars_in_url(box):
    """V18. A configured remote URL holding DEL and C1 controls is shown with '?' (decoded report and TSV)."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    box.git(work, "remote", "add", "odd", "file:///nonexistent/a\x7fb\u009bc")
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work)
    url = [x.get("url", "") for x in rec(rep, ".").get("remotes", []) if x.get("name") == "odd"]
    tsv = open(os.path.join(box.p("out", "r%d" % box.n), "sync_report.tsv")).read() if rep else ""
    bad = [c for c in "".join(url) + tsv + so + se if 0x7f <= ord(c) <= 0x9f]
    ok("ctrl_url.url_reported", bool(url), rep)
    ok("ctrl_url.no_del_or_c1", not bad, [hex(ord(c)) for c in bad])


# ───────────────────────── blocking reasons (V08, V09, V22) ─────────────────────────
def c_invalid_remote_blocks(box):
    """V08 / P39b: a remote the engine cannot fetch (invalid name, url only) blocks the fast-forward."""
    for name in ("bad.lock", "-dash"):
        r_url, r_seed = box.bare("HelixDevelopment", "solo_" + name.strip("-.").replace(".", "_"))
        work = box.clone(r_url, "w_" + name.strip("-."))
        box.commit(r_seed, "upstream moves")
        with open(os.path.join(work, ".git", "config"), "a") as f:
            f.write('[remote "%s"]\n\turl = %s\n' % (name, r_url))
        before = box.git(work, "rev-parse", "HEAD")
        rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet")
        ok("invalid_remote[%s].not_moved" % name, box.git(work, "rev-parse", "HEAD") == before)
        ok("invalid_remote[%s].attention" % name, rc == 4, "rc=%s" % rc)


def child_on_branch_tree(box, setup):
    a_url, a_seed = box.bare("HelixDevelopment", "a")
    r_url, r_seed = box.bare("HelixDevelopment", "root")
    box.add_sub(r_seed, a_url, "libs/a")
    work = box.clone(r_url, "p")
    sub = os.path.join(work, "libs/a")
    box.git(sub, "checkout", "-q", "-B", "main", "origin/main")
    box.commit(a_seed, "a: upstream moves (child behind)")
    setup(work, r_seed, r_url)
    before = box.git(sub, "rev-parse", "HEAD")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet")
    return box.git(sub, "rev-parse", "HEAD") == before, rc


def c_diverged_upstreams_block(box):
    """V09 / P40: the root's two remotes have diverged mains: nothing below it moves."""
    def diverge(work, r_seed, r_url):
        mirror = box.p("remotes", "other", "mirror.git")
        os.makedirs(os.path.dirname(mirror))
        box.git(box.root, "clone", "-q", "--bare", r_url[len("file://"):], mirror)
        tmp = box.p("seed", "mirror_w")
        box.git(box.root, "clone", "-q", "file://" + mirror, tmp)
        box.commit(tmp, "mirror-only commit")
        box.commit(r_seed, "origin-only commit")
        box.git(work, "remote", "add", "mirror", "file://" + mirror)
    held, rc = child_on_branch_tree(box, diverge)
    ok("diverged.child_held", held)
    ok("diverged.attention", rc == 4, "rc=%s" % rc)


def c_no_upstream_main_blocks(box):
    """V22 / P41: the root's only remote has no branch main: nothing below it moves."""
    def no_main(work, r_seed, r_url):
        empty = box.p("remotes", "other", "nomain.git")
        os.makedirs(os.path.dirname(empty))
        box.git(box.root, "clone", "-q", "--bare", r_url[len("file://"):], empty)
        box.git(empty, "branch", "-q", "-m", "main", "trunk")
        box.git(work, "remote", "set-url", "origin", "file://" + empty)
        box.git(work, "update-ref", "-d", "refs/remotes/origin/main")
    held, rc = child_on_branch_tree(box, no_main)
    ok("no_upstream_main.child_held", held)
    ok("no_upstream_main.attention", rc == 4, "rc=%s" % rc)


# ───────────────────────── RV4-8 / RV4-11 / RV4-12 / RV4-13 / RV4-15 ─────────────────────────
def c_lock_symlink(box):
    """V13 / P42: the lock path is a symbolic link to a file that does not exist: the lock cannot be opened, which is
    not "another run" (review round 6, RV5-2): FAILED exit 1 with its own message; the target is never made."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    target = box.p("LOCK_TARGET_CREATED")
    os.symlink(target, os.path.join(work, ".git", "helix-sync-upstreams.lock"))
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    ok("lock_symlink.exit_1", rc == 1 and "cannot open the run lock" in se, "rc=%s" % rc)
    ok("lock_symlink.target_not_created", not os.path.exists(target))
    # P27 (round 5): the same link planted at a SUBMODULE's lock (its git common dir), taken by lock_repositories
    work2, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    common = box.git(os.path.join(work2, "libs/a"), "rev-parse", "--path-format=absolute", "--git-common-dir")
    target2 = box.p("SUB_LOCK_TARGET_CREATED")
    os.symlink(target2, os.path.join(common, "helix-sync-upstreams.lock"))
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work2, "--quiet")
    ok("lock_symlink.submodule_exit_1", rc == 1 and "cannot open the run lock" in se, "rc=%s" % rc)
    ok("lock_symlink.submodule_target_not_created", not os.path.exists(target2))
    os.unlink(os.path.join(common, "helix-sync-upstreams.lock"))  # control: without the link the run proceeds
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work2, "--quiet")
    ok("lock_symlink.control_no_link_runs", rc not in (1, 7), "rc=%s" % rc)


def c_lock_overlap(box):
    """P17 model: a run rooted at the submodule holds ITS lock; a run over the whole tree must not proceed."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    common = box.git(os.path.join(work, "libs/a"), "rev-parse", "--path-format=absolute", "--git-common-dir")
    fd = os.open(os.path.join(common, "helix-sync-upstreams.lock"), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet")
    finally:
        os.close(fd)
    ok("lock_overlap.exit_7", rc == 7, "rc=%s" % rc)
    ok("lock_overlap.root_not_moved", box.git(work, "rev-parse", "HEAD") == r1)


def c_out_unwritable_before(box):
    """RV4-8: an --out that cannot be written is refused BEFORE any write (exit 2, nothing moved)."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    box.commit(r_seed, "upstream moves")
    ro = box.p("ro")
    os.makedirs(ro)
    os.chmod(ro, 0o500)
    before = box.git(work, "rev-parse", "HEAD")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", "--out", os.path.join(ro, "ev"), out=False)
    ok("out_unwritable.exit_2", rc == 2, "rc=%s" % rc)
    ok("out_unwritable.not_moved", box.git(work, "rev-parse", "HEAD") == before)
    # P24 (round 5): the directory itself already exists and cannot be written; creating it succeeds (exist_ok),
    # so only the probe file can find out before the run writes the project
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", "--out", ro, out=False)
    ok("out_unwritable.existing_dir_exit_2", rc == 2, "rc=%s" % rc)
    ok("out_unwritable.existing_dir_not_moved", box.git(work, "rev-parse", "HEAD") == before)
    os.chmod(ro, 0o700)  # control: the same directory made writable is accepted and the run moves the project
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", "--out", ro, out=False)
    ok("out_unwritable.control_writable_dir_accepted", rc == 0 and box.git(work, "rev-parse", "HEAD") != before,
       "rc=%s" % rc)


def c_out_lost_after_write(box):
    """RV4-8: the evidence directory becomes unwritable after the write (fixture: the race shim, at the merge call).
    The run must not end with the usage code: FAILED (exit 1), and stderr names the move."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    target = box.commit(r_seed, "upstream moves")
    o = box.p("out", "lost")
    os.makedirs(o)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", "--out", o, out=False,
                                 path_prefix=box.shim(), env=race_env(box, "chmod-out", "merge@" + work, o))
    ok("out_lost.moved", box.git(work, "rev-parse", "HEAD") == target)
    ok("out_lost.exit_1", rc == 1, "rc=%s" % rc)
    ok("out_lost.move_on_stderr", target[:12] in se, se[-400:])


def c_default_out_inside_tree(box):
    """P16 / P34 model: the default evidence directory resolving inside the work tree (XDG_CACHE_HOME a symlink into
    the tree, or relative) is refused; no report file lands in the project."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    link = box.p("cache_link")
    os.symlink(os.path.join(work, "cachedir"), link)
    os.makedirs(os.path.join(work, "cachedir"))
    rc1, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet", out=False,
                                  env={"XDG_CACHE_HOME": link})
    found = []
    for dp, dn, fn in os.walk(work):
        if ".git" in dp.split(os.sep):
            continue
        found += [os.path.join(dp, f) for f in fn if f.startswith("sync_report")]
    ok("default_out_symlink.refused", rc1 == 2, "rc=%s" % rc1)
    ok("default_out.nothing_in_tree", not found, found)


def c_default_out_relative(box):
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    e = dict(box.env, XDG_CACHE_HOME="relcache")
    argv, o = box.engine_argv("--check", "--no-fetch", "--quiet")
    r = subprocess.run(argv, env=e, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300)
    found = []
    for dp, dn, fn in os.walk(work):
        if ".git" in dp.split(os.sep):
            continue
        found += [os.path.join(dp, f) for f in fn if f.startswith("sync_report")]
    ok("default_out_relative.refused", r.returncode == 2, "rc=%s" % r.returncode)
    ok("default_out_relative.nothing_in_tree", not found, found)
    # P29 (round 5): run from a directory OUTSIDE the tree (--root names the tree), so the inside-the-tree check
    # cannot be what refuses: a relative cache dir must be refused on its own, and nothing written where the run started
    elsewhere = box.p("elsewhere")
    os.makedirs(elsewhere)
    argv, o = box.engine_argv("--check", "--no-fetch", "--quiet", "--root", work)
    r = subprocess.run(argv, env=e, cwd=elsewhere, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300)
    ok("default_out_relative.outside_cwd_refused", r.returncode == 2, "rc=%s" % r.returncode)
    ok("default_out_relative.outside_cwd_nothing_written", os.listdir(elsewhere) == [], os.listdir(elsewhere))
    e2 = dict(box.env, XDG_CACHE_HOME=box.p("abscache"))  # control: an absolute cache dir is accepted from there
    argv, o = box.engine_argv("--check", "--no-fetch", "--quiet", "--root", work)
    r = subprocess.run(argv, env=e2, cwd=elsewhere, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300)
    ok("default_out_relative.control_absolute_accepted", r.returncode == 0 and os.path.isdir(box.p("abscache")),
       "rc=%s" % r.returncode)


def c_unsafe_gitlink_paths(box):
    """P22 model: gitlinks at paths the engine will not use ('-dash', 'back\\slash') are reported, never omitted."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    sha = box.git(work, "rev-parse", "HEAD")
    for path in ("-dash", "back\\slash"):
        box.git(work, "update-index", "--add", "--cacheinfo", "160000,%s,%s" % (sha, path))
    box.git(work, "commit", "-q", "-m", "odd gitlinks")
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    paths = {r.get("path"): r for r in (rep or {}).get("repos", [])}
    for path in ("-dash", "back\\slash"):
        r = paths.get(path, {})
        ok("unsafe_path[%s].reported" % path, (r.get("pin") or {}).get("state") == "unsafe-path", r or sorted(paths))
        ok("unsafe_path[%s].attention" % path, "pin-unsafe-path" in r.get("reasons", []), r.get("reasons"))


def c_outside_parent(box):
    """RV4-15: a submodule reached through a symbolic link that leaves its parent's work tree is not inspected."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    elsewhere = box.p("elsewhere")
    os.makedirs(elsewhere)
    os.rename(os.path.join(work, "libs"), os.path.join(elsewhere, "libs"))
    os.symlink(os.path.join(elsewhere, "libs"), os.path.join(work, "libs"))
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    a = rec(rep, "libs/a")
    ok("outside_parent.not_inspected", a.get("initialised") is False and (a.get("pin") or {}).get("state")
       == "outside-parent", a)
    ok("outside_parent.attention", "pin-outside-parent" in a.get("reasons", []), a.get("reasons"))


# ───────────────────────── review round 6 (RV5-1 .. RV5-10) ─────────────────────────
MARKER = "helix-sync-upstreams.write-in-progress"


def slow_tree(box, n, smudge, root_name="slowroot"):
    """A root whose upstream adds ``n`` files under a smudge filter the USER configured in the working clone (the
    git-lfs shape; fixture: the filter command, e.g. 'sleep 2; cat'). Returns (work, before, target)."""
    r_url, r_seed = box.bare("HelixDevelopment", root_name)
    work = box.clone(r_url, "w_" + root_name)
    with open(os.path.join(r_seed, ".gitattributes"), "w") as f:
        f.write("*.slow filter=slow\n")
    for i in range(n):
        with open(os.path.join(r_seed, "f%d.slow" % i), "w") as f:
            f.write("payload %d\n" % i)
    box.git(r_seed, "add", ".")
    box.git(r_seed, "commit", "-q", "-m", "slow files")
    box.git(r_seed, "push", "-q", "origin", "HEAD:main")
    box.git(work, "config", "filter.slow.smudge", smudge)
    box.git(work, "config", "filter.slow.clean", "cat")
    return work, box.git(work, "rev-parse", "HEAD"), box.git(r_seed, "rev-parse", "HEAD")


def c_write_outlives_deadline(box):
    """RV5-1 (deadline member). A fast-forward whose checkout takes ~8 s (4 files x 2 s smudge) starts with a run
    deadline of 4 s: the write must FINISH (never killed by the deadline), git must clean up, the post-write verify
    must still run (final reads after the deadline), the move must be recorded and the marker removed."""
    work, before, target = slow_tree(box, 4, "sleep 2; cat")
    rc, so, se, rep, t = box.run("--apply", "--root", work, "--deadline", "4", "--quiet", timeout=300)
    root = rec(rep, ".")
    gitdir = os.path.join(work, ".git")
    ok("write_deadline.control_slow", t >= 7, "%.1fs" % t)
    ok("write_deadline.head_at_target", box.git(work, "rev-parse", "HEAD") == target)
    ok("write_deadline.no_index_lock", not os.path.exists(os.path.join(gitdir, "index.lock")))
    ok("write_deadline.tree_clean", box.git(work, "status", "--porcelain=v1") == "",
       box.git(work, "status", "--porcelain=v1")[:300])
    ok("write_deadline.move_recorded", root.get("moved") is True and root.get("head_after") == target,
       "moved %s head_after %s" % (root.get("moved"), root.get("head_after")))
    ok("write_deadline.not_unresolved", not [x for x in root.get("reasons", []) if x.startswith("unresolved")],
       root.get("reasons"))
    ok("write_deadline.applied", rc == 0 and root.get("result") == "updated", "rc=%s result=%s" % (rc, root.get("result")))
    ok("write_deadline.marker_removed", not os.path.exists(os.path.join(gitdir, MARKER)))


def c_write_timeout_term_first(box):
    """RV5-1 (the bounded member). --write-timeout 3 against a ~8 s checkout: the write is ended, by SIGTERM first
    (git removes its own index.lock), reported write-killed with recovery steps (FAILED, exit 1), and the
    write-in-progress marker stays, so the NEXT run attributes the leftovers to the killed write instead of blaming
    the user; after the user recovers, an --apply clears the marker."""
    work, before, target = slow_tree(box, 4, "sleep 2; cat")
    gitdir = os.path.join(work, ".git")
    rc, so, se, rep, t = box.run("--apply", "--root", work, "--write-timeout", "3", timeout=300)
    root = rec(rep, ".")
    ok("write_timeout.failed_exit_1", rc == 1 and (rep or {}).get("verdict") == "FAILED", "rc=%s" % rc)
    ok("write_timeout.ended_before_finish", t < 30, "%.1fs" % t)
    ok("write_timeout.reason_write_killed", "write-killed:fast-forward" in root.get("reasons", []), root.get("reasons"))
    acts = [a for a in root.get("actions", []) if a.get("op") == "fast-forward"]
    ok("write_timeout.term_sufficed", bool(acts) and "SIGTERM" in str(acts[-1].get("error", "")), acts)
    ok("write_timeout.no_index_lock_after_term", not os.path.exists(os.path.join(gitdir, "index.lock")))
    ok("write_timeout.head_not_moved", box.git(work, "rev-parse", "HEAD") == before)
    ok("write_timeout.recovery_steps", any("write-killed" in s and "stash" in s for s in (rep or {}).get("next_steps", [])),
       (rep or {}).get("next_steps"))
    ok("write_timeout.recovery_printed", "recovery" in se, se[-400:])
    ok("write_timeout.marker_kept", os.path.exists(os.path.join(gitdir, MARKER)))
    dirty = box.git(work, "status", "--porcelain=v1") != ""
    ok("write_timeout.control_leftovers_present", dirty)
    # the next run: the leftovers are attributed to the killed write, never plain dirty-tree / in-progress
    rc2, so2, se2, rep2, _ = box.run("--apply", "--root", work, "--quiet", timeout=300)
    r2 = rec(rep2, ".")
    reasons = r2.get("reasons", [])
    ok("write_timeout.rerun_attributes", "write-interrupted-earlier:fast-forward" in reasons, reasons)
    ok("write_timeout.rerun_no_plain_dirty_tree", "dirty-tree" not in reasons and "dirty-tree-since-write-interrupted"
       in reasons, reasons)
    ok("write_timeout.rerun_attention_not_moved", rc2 == 4 and box.git(work, "rev-parse", "HEAD") == before,
       "rc=%s" % rc2)
    # the user recovers as the steps say (stash the leftovers), then an --apply clears the marker and integrates
    box.git(work, "stash", "push", "-q", "--include-untracked", "-m", "helix-sync-write-killed")
    box.git(work, "config", "filter.slow.smudge", "cat")
    rc3, so3, se3, rep3, _ = box.run("--apply", "--root", work, "--quiet", timeout=300)
    ok("write_timeout.recovered_apply", rc3 == 0 and box.git(work, "rev-parse", "HEAD") == target, "rc=%s" % rc3)
    ok("write_timeout.marker_cleared", not os.path.exists(os.path.join(gitdir, MARKER)))
    ok("write_timeout.marker_clear_noted", "write-marker-cleared" in str(rec(rep3, ".").get("notes")),
       rec(rep3, ".").get("notes"))


def c_write_timeout_kill_after_grace(box):
    """RV5-1: a write whose smudge filter ignores SIGTERM (trap '' TERM) is still ended within the bound: git itself
    ends on SIGTERM (its own handler), the group is then swept with SIGKILL; the report names the signal that ended
    git and lists any lock left behind. (A leader that ignores SIGTERM itself, ended by SIGKILL after the grace
    period, is proven by the unit test RoundSix / KillGroup: git cannot be made to ignore it.)"""
    work, before, target = slow_tree(box, 3, "trap '' TERM; sleep 4; cat", "slowkill")
    rc, so, se, rep, t = box.run("--apply", "--root", work, "--write-timeout", "2", "--quiet", timeout=300)
    root = rec(rep, ".")
    acts = [a for a in root.get("actions", []) if a.get("op") == "fast-forward"]
    ok("write_kill.failed_exit_1", rc == 1, "rc=%s" % rc)
    ok("write_kill.reason", "write-killed:fast-forward" in root.get("reasons", []), root.get("reasons"))
    ok("write_kill.named_signal", bool(acts) and ("SIGKILL" in str(acts[-1].get("error")) or
                                                    "SIGTERM" in str(acts[-1].get("error"))), acts)
    ok("write_kill.locks_listed_when_left", (not os.path.exists(os.path.join(work, ".git", "index.lock")))
       or "index.lock" in str(acts[-1].get("locks_left") if acts else ""), acts)
    ok("write_kill.bounded", t < 90, "%.1fs" % t)


def c_marker_after_success(box):
    """RV5-1: an ordinary successful fast-forward leaves no write-in-progress marker behind."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    box.commit(r_seed, "upstream moves")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet")
    ok("marker_success.applied", rc == 0, "rc=%s" % rc)
    ok("marker_success.no_marker", not os.path.exists(os.path.join(work, ".git", MARKER)))


def c_stale_marker_on_clean_current_tree(box):
    """RV5-1 / Q09. A marker left by an earlier run whose write left nothing (the tree is clean and current, so this
    run writes nothing that would replace the marker): --check keeps it and says so; --apply removes it and notes it;
    neither blames the user nor blocks the repository."""
    r_url, r_seed = box.bare("HelixDevelopment", "stale")
    work = box.clone(r_url, "w")
    marker = os.path.join(work, ".git", MARKER)
    with open(marker, "w") as f:
        json.dump({"op": "fast-forward", "target": "0" * 40, "run_id": "earlier", "started": "2026-11-14T00:00:00Z"}, f)
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    root = rec(rep, ".")
    ok("stale_marker.check_keeps", os.path.exists(marker))
    ok("stale_marker.check_notes_present", "write-marker-present" in str(root.get("notes")), root.get("notes"))
    ok("stale_marker.check_not_blocked", rc == 0 and not [x for x in root.get("reasons", []) if "write-" in x],
       "rc=%s %s" % (rc, root.get("reasons")))
    rc, so, se, rep, _ = box.run("--apply", "--no-fetch", "--root", work, "--quiet")
    root = rec(rep, ".")
    ok("stale_marker.apply_clears", not os.path.exists(marker))
    ok("stale_marker.apply_notes_cleared", "write-marker-cleared:fast-forward-left-nothing" in str(root.get("notes")),
       root.get("notes"))
    ok("stale_marker.apply_current", rc == 0, "rc=%s" % rc)


def c_switch_at_merge(box):
    """RV5-4 / reviewer R01. Fixture: the user switches the root to a new branch at the moment the merge call starts
    (after every pre-write re-read). git's merge then moves the NEW branch; the post-write verify must see that the
    branch changed and report it (FAILED, exit 1), never as this run's update."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "switch-branch", "merge@" + os.path.realpath(work), work))
    root = rec(rep, ".")
    ok("switch_at_merge.fired", os.path.exists(box.p("mark")))
    ok("switch_at_merge.reported", "branch-changed-during-write" in json.dumps(root.get("actions")), root.get("actions"))
    ok("switch_at_merge.not_updated", rc == 1 and root.get("result") == "failed", "rc=%s %s" % (rc, root.get("result")))


def pin_behind_tree(box):
    """root upstream does not move; the child's upstream moved (S2): the pin is behind main (--advance-pins)."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    box.git(work, "fetch", "-q", "origin")
    box.git(work, "update-ref", "refs/remotes/origin/main", r1)
    box.git(r_seed, "push", "-q", "-f", "origin", r1 + ":main")
    return work, s1, s2, r1


def c_sigterm_during_pin_checkout(box):
    """RV5-4 / reviewer R14 + R21. SIGTERM arrives inside the advance-pin's checkout: the write finishes as ONE write
    (child at S2, parent index staged at S2 by the final 'add', the action verified), exit 8."""
    work, s1, s2, r1 = pin_behind_tree(box)
    sub = os.path.realpath(os.path.join(work, "libs/a"))
    rc, so, se, rep, _ = box.run("--apply", "--advance-pins", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "sigterm-parent", "checkout@" + sub, work))
    t_end = time.monotonic() + 20
    while not os.path.exists(box.p("mark.signalled")) and time.monotonic() < t_end:
        time.sleep(0.2)
    staged = box.git(work, "ls-files", "-s", "libs/a").split()[1]
    pin = [a for a in rec(rep, "libs/a").get("actions") or [] if a.get("op") == "advance-pin"]
    ok("sigterm_pin.signalled", os.path.exists(box.p("mark.signalled")))
    ok("sigterm_pin.exit_8", rc == 8, "rc=%s" % rc)
    ok("sigterm_pin.child_at_s2", box.git(sub, "rev-parse", "HEAD") == s2)
    ok("sigterm_pin.index_staged_s2", staged == s2, "staged %s s1 %s s2 %s" % (staged, s1, s2))
    ok("sigterm_pin.action_verified", bool(pin) and "why" not in pin[-1] and pin[-1].get("staged_rc") == 0, pin)


def c_marker_after_inspection(box):
    """RV5-4 / reviewer R29. Fixture: the user starts 'git bisect' (BISECT_LOG appears) after inspection, before the
    write: the write-time re-check must see it; the root is NOT fast-forwarded under a running bisect (exit 4)."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "touch-file", "fetch@" + work, work,
                                              SXR_FILE=os.path.join(".git", "BISECT_LOG")))
    root = rec(rep, ".")
    ok("marker_inspect.fired", os.path.exists(os.path.join(work, ".git", "BISECT_LOG")))
    ok("marker_inspect.root_not_moved", box.git(work, "rev-parse", "HEAD") == r1)
    ok("marker_inspect.attention", rc == 4 and "write-blocked:tree-changed-before-write" in root.get("reasons", []),
       "rc=%s %s" % (rc, root.get("reasons")))


def c_wrote_then_other_moved(box):
    """RV5-4 / reviewer R36 + R37. The engine fast-forwards the root, then the user commits on top (fixture: the
    shim commits at the child's follow-pin checkout). The head moved, but not to what this run wrote: attention
    (exit 4, head-changed-during-run, changed_by_other), never 'updated'."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    env = race_env(box, "commit", "checkout@" + os.path.realpath(os.path.join(work, "libs/a")), work)
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(), env=env)
    user = open(box.p("mark.sha")).read().strip() if os.path.exists(box.p("mark.sha")) else None
    root = rec(rep, ".")
    ok("wrote_then_other.fired", user is not None and box.git(work, "rev-parse", "HEAD^") == r2)
    ok("wrote_then_other.reason", "head-changed-during-run" in root.get("reasons", []), root.get("reasons"))
    ok("wrote_then_other.changed_by_other", root.get("changed_by_other") is True)
    ok("wrote_then_other.attention", rc == 4 and root.get("result") == "attention", "rc=%s %s" % (rc, root.get("result")))


def c_staged_gitlink_root_behind(box):
    """RV5-3. The user staged a new gitlink for libs/a in the root; the root's fast-forward changes libs/a. The
    write must be blocked BEFORE git (write-blocked:gitlink-staged-would-change, attention exit 4), the stage kept.
    Control: the same stage with a fast-forward that does not touch libs/a moves the root and keeps the stage."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    sub = os.path.join(work, "libs/a")
    with open(os.path.join(sub, "USER"), "w") as f:
        f.write("u\n")
    box.git(sub, "add", "USER")
    box.git(sub, "commit", "-q", "-m", "user work")
    u = box.git(sub, "rev-parse", "HEAD")
    box.git(work, "add", "libs/a")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet")
    root = rec(rep, ".")
    ok("staged_root.attention_exit_4", rc == 4, "rc=%s %s" % (rc, root.get("actions")))
    ok("staged_root.blocked_before_write", "write-blocked:gitlink-staged-would-change" in root.get("reasons", []),
       root.get("reasons"))
    ok("staged_root.root_not_moved", box.git(work, "rev-parse", "HEAD") == r1)
    ok("staged_root.stage_kept", u in box.git(work, "ls-files", "-s", "libs/a"))
    # control: the fast-forward does not touch libs/a
    a_url, a2 = box.bare("HelixDevelopment", "a2")
    r_url2, r_seed2 = box.bare("HelixDevelopment", "root2")
    box.add_sub(r_seed2, a_url, "libs/a")
    work2 = box.clone(r_url2, "p2")
    r22 = box.commit(r_seed2, "root2: other file")
    sub2 = os.path.join(work2, "libs/a")
    with open(os.path.join(sub2, "USER"), "w") as f:
        f.write("u\n")
    box.git(sub2, "add", "USER")
    box.git(sub2, "commit", "-q", "-m", "user work")
    u2 = box.git(sub2, "rev-parse", "HEAD")
    box.git(work2, "add", "libs/a")
    rc2, so2, se2, rep2, _ = box.run("--apply", "--root", work2, "--quiet")
    ok("staged_root.control_moved", box.git(work2, "rev-parse", "HEAD") == r22, "rc=%s" % rc2)
    ok("staged_root.control_stage_kept", u2 in box.git(work2, "ls-files", "-s", "libs/a"))


def c_lock_open_error(box):
    """RV5-2. A lock that cannot be OPENED (read-only submodule git dir, no lock file yet; read-only root git dir) is
    not 'another sync run': its own message, FAILED exit 1. Control: writable, the run proceeds."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    gd = box.git(os.path.join(work, "libs/a"), "rev-parse", "--path-format=absolute", "--git-common-dir")
    lock = os.path.join(gd, "helix-sync-upstreams.lock")
    if os.path.exists(lock):
        os.unlink(lock)
    os.chmod(gd, 0o555)
    try:
        rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    finally:
        os.chmod(gd, 0o755)
    ok("lock_open.sub_exit_1", rc == 1, "rc=%s" % rc)
    ok("lock_open.sub_own_message", "cannot open the run lock" in se and "another sync run" not in se, se[-300:])
    rlock = os.path.join(work, ".git", "helix-sync-upstreams.lock")
    if os.path.exists(rlock):
        os.unlink(rlock)
    os.chmod(os.path.join(work, ".git"), 0o555)
    try:
        rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    finally:
        os.chmod(os.path.join(work, ".git"), 0o755)
    ok("lock_open.root_exit_1", rc == 1, "rc=%s" % rc)
    ok("lock_open.root_own_message", "cannot open the run lock" in se and "another sync run" not in se, se[-300:])
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    ok("lock_open.control_runs", rc not in (1, 7), "rc=%s" % rc)


def c_ctrl_c_at_prompt(box):
    """RV5-5. Ctrl-C at an --interactive prompt (a real pty is the controlling terminal) ends the run promptly:
    exit 8, nothing moved; it never waits for Enter."""
    import pty
    import select as _select
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    argv, o = box.engine_argv("--apply", "--interactive", "--root", work)
    argv += ["--out", o]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(argv[0], argv, dict(box.env))
    buf = b""

    def drain(sec, until=None):
        nonlocal buf
        end = time.monotonic() + sec
        while time.monotonic() < end:
            if until and until in buf:
                return
            r, _, _ = _select.select([fd], [], [], 0.2)
            if r:
                try:
                    c = os.read(fd, 4096)
                except OSError:
                    return
                if not c:
                    return
                buf += c
    drain(30, b"[y/N]")
    ok("ctrl_c.prompted", b"[y/N]" in buf, buf[-200:])
    os.write(fd, b"\x03")
    t0 = time.monotonic()
    code, done = None, False
    while time.monotonic() - t0 < 15:
        drain(0.5)
        wpid, st = os.waitpid(pid, os.WNOHANG)
        if wpid:
            code, done = os.waitstatus_to_exitcode(st), True
            break
    dt = time.monotonic() - t0
    if not done:
        os.kill(pid, signal.SIGKILL)  # our own child (pty.fork), one pid, never a group
        os.waitpid(pid, 0)
    ok("ctrl_c.ends_without_enter", done and dt < 10, "done=%s %.1fs" % (done, dt))
    ok("ctrl_c.exit_8", code == 8, "code=%s" % code)
    ok("ctrl_c.nothing_moved", box.git(work, "rev-parse", "HEAD") == r1 and
       box.git(os.path.join(work, "libs/a"), "rev-parse", "HEAD") == s1)


def c_update_none_not_followed(box):
    """RV5-7 / SYNC-R5-OPEN-1. A child whose submodule.<name>.update is 'none' (in .git/config) is never checked out
    by the engine: the root fast-forwards, the child stays, and the report says why (not silently followed)."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    box.git(work, "config", "submodule.libs/a.update", "none")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet")
    a = rec(rep, "libs/a")
    ok("update_none.root_moved", box.git(work, "rev-parse", "HEAD") == r2, "rc=%s" % rc)
    ok("update_none.child_not_followed", box.git(os.path.join(work, "libs/a"), "rev-parse", "HEAD") == s1)
    ok("update_none.reason", "not-followed:update-none" in a.get("reasons", []), a.get("reasons"))
    ok("update_none.attention", rc == 4, "rc=%s" % rc)
    # .gitmodules form (update = none committed upstream; name != path)
    # the upstream itself commits update = rebase in .gitmodules (R3): the root fast-forwards to R3, the child
    # (pinned S2 there) is not checked out by the engine
    work2, a_seed2, r_seed2, s12, s22, r12, r22 = pinned_tree(Box2(box))
    box.git(r_seed2, "config", "--file", ".gitmodules", "submodule.libs/a.update", "rebase")
    box.git(r_seed2, "add", ".gitmodules")
    box.git(r_seed2, "commit", "-q", "-m", "root: R3 update = rebase")
    box.git(r_seed2, "push", "-q", "origin", "HEAD:main")
    r32 = box.git(r_seed2, "rev-parse", "HEAD")
    rc2, so2, se2, rep2, _ = box.run("--apply", "--root", work2, "--quiet")
    a2 = rec(rep2, "libs/a")
    ok("update_none.gitmodules_root_moved", box.git(work2, "rev-parse", "HEAD") == r32, "rc=%s" % rc2)
    ok("update_none.gitmodules_rebase_not_followed", box.git(os.path.join(work2, "libs/a"), "rev-parse", "HEAD") == s12,
       "rc=%s %s" % (rc2, a2.get("actions")))
    ok("update_none.gitmodules_reason", "not-followed:update-rebase" in a2.get("reasons", []), a2.get("reasons"))
    # control: no update setting, the child follows
    work3, a_seed3, r_seed3, s13, s23, r13, r23 = pinned_tree(Box2(box, "3"))
    rc3, so3, se3, rep3, _ = box.run("--apply", "--root", work3, "--quiet")
    ok("update_none.control_follows", rc3 == 0 and box.git(os.path.join(work3, "libs/a"), "rev-parse", "HEAD") == s23,
       "rc=%s" % rc3)


class Box2:
    """A second fixture namespace inside the same sandbox (other remote / clone names)."""
    def __init__(self, box, tag="2"):
        self._b, self._t = box, tag

    def __getattr__(self, n):
        return getattr(self._b, n)

    def bare(self, org, name):
        return self._b.bare(org, name + self._t)

    def clone(self, url, name):
        return self._b.clone(url, name + self._t)


def c_interrupted_fetch_labels(box):
    """RV5-6. SIGTERM at the root's fetch (--jobs 1): the remotes whose fetch was refused are 'not-fetched-
    interrupted', never 'unreachable' (no remote was contacted) and never 'no-upstream-main'."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    rc, so, se, rep, _ = box.run("--check", "--jobs", "1", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "sigterm-parent", "fetch@" + work, work))
    reasons = sum((x.get("reasons", []) for x in (rep or {}).get("repos", [])), [])
    fetch = [m.get("fetch") for x in (rep or {}).get("repos", []) for m in x.get("remotes", [])]
    ok("interrupted_labels.exit_8", rc == 8, "rc=%s" % rc)
    ok("interrupted_labels.no_unreachable", not [x for x in reasons if x.startswith("unreachable:")], reasons)
    ok("interrupted_labels.no_no_upstream", not [x for x in reasons if x.startswith("no-upstream-")], reasons)
    ok("interrupted_labels.labelled", "not-fetched-interrupted" in fetch, fetch)


def c_blind_beats_failed(box):
    """SYNC-R5-OPEN-5 / M73 by an assertion (not a timeout). The merge fails (the user edits a file the
    fast-forward changes at the merge call: rc 1, failed) and then the final head read answers garbage (fixture:
    the shim prints a non-object-id and exits 0). A failure judged next to a call with no answer is BLIND (exit 6)."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    box.commit(r_seed, "upstream edits README", fname="README")
    rc, so, se, rep, _ = box.run("--apply", "--root", work, "--quiet", path_prefix=box.shim(),
                                 env=race_env(box, "touch-file", "merge@" + work, work, SXR_FILE="README",
                                              SXR_GARBAGE_AFTER="rev-parse"))
    root = rec(rep, ".")
    ok("blind_failed.fired", os.path.exists(box.p("mark")))
    ok("blind_failed.malformed_recorded", "unresolved:rev-parse:malformed-output" in root.get("reasons", []),
       root.get("reasons"))
    ok("blind_failed.blind_exit_6", rc == 6 and root.get("result") == "blind", "rc=%s %s" % (rc, root.get("result")))


# ───────────────────────── review round 7 (RV6-1 .. RV6-3) ─────────────────────────
DRIVER = os.path.join(HERE, "inproc_driver.py")
ENGINE_PY = os.path.join(os.path.dirname(os.path.abspath(ENGINE)), "sync_all_upstreams.py")


def inproc(box, fault, *args):
    """Runs the engine module next to $SX_ENGINE in-process under scripts/sync/inproc_driver.py with ONE fault (a
    signal, the clock or the kernel, at a point no outside program can hit in time; fixture). Returns
    (rc, stdout, stderr, driver record, report)."""
    argv, o = box.engine_argv(*args)
    argv = [PY, "-I", DRIVER, ENGINE_PY, fault] + argv[2:] + ["--out", o]
    r = subprocess.run(argv, env=box.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=600)
    drv = {}
    for line in r.stdout.splitlines():
        if line.startswith("DRIVER "):
            drv = json.loads(line[7:])
    rep = None
    try:
        with open(os.path.join(o, "sync_report.json"), encoding="utf-8") as f:
            rep = json.load(f)
    except (OSError, ValueError):
        pass
    return drv.get("rc"), r.stdout, r.stderr, drv, rep


def c_refused_write_leaves_no_marker(box):
    """RV6-1. A write that is refused before git starts (a stop signal or the run deadline landing just before or
    just after the write's marker is written; a git process the kernel cannot start) leaves NO marker: the write
    never started, so a later run must never attribute the user's own edits to 'an interrupted write'. For the
    'before' faults the marker is not even written. Covers both write call sites of write_git (fast-forward merge
    and the pin checkout)."""
    cases = [("stop-after-marker", "ff"), ("deadline-after-marker", "ff"), ("stop-before-marker", "ff"),
             ("deadline-before-marker", "ff"), ("spawn-fails-write", "ff"), ("stop-after-marker", "pin"),
             ("deadline-after-marker", "pin"), ("spawn-fails-write", "pin")]
    for i, (fault, kind) in enumerate(cases):
        tag = "%s.%s" % (kind, fault)
        if kind == "ff":
            r_url, r_seed = box.bare("HelixDevelopment", "rw%d" % i)
            work = box.clone(r_url, "rw%d" % i)
            before = box.git(work, "rev-parse", "HEAD")
            box.commit(r_seed, "upstream moves")
            rc, so, se, drv, rep = inproc(box, fault, "--apply", "--root", work, "--quiet")
            repo_dir = work
            want_op = "fast-forward"
        else:
            sub_box = Box("refused_pin%d" % i)  # pin_behind_tree uses fixed names: one sandbox per pin case
            try:
                work, s1, s2, r1 = pin_behind_tree(sub_box)
                repo_dir = os.path.join(work, "libs/a")
                before = sub_box.git(repo_dir, "rev-parse", "HEAD")
                rc, so, se, drv, rep = inproc(sub_box, fault, "--apply", "--advance-pins", "--root", work, "--quiet")
                want_op = "advance-pin"
                check_refused(sub_box, tag, fault, repo_dir, work, before, rc, se, drv, want_op, "libs/a")
            finally:
                sub_box.cleanup()
            continue
        check_refused(box, tag, fault, repo_dir, work, before, rc, se, drv, want_op, ".")


def check_refused(box, tag, fault, repo_dir, work, before, rc, se, drv, want_op, rel):
    gitdir = box.git(repo_dir, "rev-parse", "--absolute-git-dir")
    ok("refused_marker.%s.ran" % tag, rc is not None, "rc=%s stderr=%s" % (rc, se[-300:]))
    ok("refused_marker.%s.not_moved" % tag, box.git(repo_dir, "rev-parse", "HEAD") == before)
    ok("refused_marker.%s.no_marker" % tag, not os.path.exists(os.path.join(gitdir, MARKER)))
    if fault.endswith("before-marker"):
        ok("refused_marker.%s.marker_never_written" % tag, drv.get("markers") == [], drv)
    else:
        ok("refused_marker.%s.marker_was_written" % tag, drv.get("markers") == [want_op], drv)
    with open(os.path.join(repo_dir, "README"), "a") as f:  # the user's own work, made after the refused run
        f.write("user work after the refused run\n")
    rc2, so2, se2, rep2, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    reasons = rec(rep2, rel).get("reasons", [])
    ok("refused_marker.%s.user_edit_is_users" % tag, "dirty-tree" in reasons, reasons)
    ok("refused_marker.%s.not_blamed_on_engine" % tag, not [x for x in reasons if "write-interrupted" in x],
       reasons)


def c_refused_stage_pin_leaves_no_marker(box):
    """RV6-1 (second write site). The stage-pin 'add' of an advance-pin is refused (a second stop signal right after
    its marker is written): the add never started, so the parent's marker is removed; the child's move and the
    unstaged pin are reported by this run, and a later run does not blame the user's root edit on the engine."""
    work, s1, s2, r1 = pin_behind_tree(box)
    sub = os.path.join(work, "libs/a")
    rc, so, se, drv, rep = inproc(box, "hardstop-after-stage-marker", "--apply", "--advance-pins", "--root", work,
                                  "--quiet")
    a = rec(rep, "libs/a")
    pin = [x for x in a.get("actions") or [] if x.get("op") == "advance-pin"]
    ok("refused_stage.markers", drv.get("markers") == ["advance-pin", "stage-pin"], drv)
    ok("refused_stage.child_moved", box.git(sub, "rev-parse", "HEAD") == s2)
    ok("refused_stage.not_staged", box.git(work, "ls-files", "-s", "libs/a").split()[1] == s1)
    ok("refused_stage.reported_unresolved", bool(pin) and str(pin[-1].get("why", "")).startswith("unresolved:"), pin)
    ok("refused_stage.no_parent_marker", not os.path.exists(os.path.join(work, ".git", MARKER)))
    ok("refused_stage.no_child_marker", not os.path.exists(
        os.path.join(box.git(sub, "rev-parse", "--absolute-git-dir"), MARKER)))
    with open(os.path.join(work, "README"), "a") as f:
        f.write("user work\n")
    rc2, so2, se2, rep2, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    reasons = rec(rep2, ".").get("reasons", [])
    ok("refused_stage.user_edit_is_users", "dirty-tree" in reasons, reasons)
    ok("refused_stage.not_blamed_on_engine", not [x for x in reasons if "write-interrupted" in x], reasons)
    # the second signal lands BEFORE the stage-pin marker would be written: the marker is never written at all
    box2 = Box("refused_stage_before")
    try:
        work2, s1b, s2b, r1b = pin_behind_tree(box2)
        rc3, so3, se3, drv3, rep3 = inproc(box2, "hardstop-before-stage-marker", "--apply", "--advance-pins",
                                           "--root", work2, "--quiet")
        ok("refused_stage.before.child_moved", box2.git(os.path.join(work2, "libs/a"), "rev-parse", "HEAD") == s2b)
        ok("refused_stage.before.stage_marker_never_written", drv3.get("markers") == ["advance-pin"], drv3)
        ok("refused_stage.before.no_parent_marker", not os.path.exists(os.path.join(work2, ".git", MARKER)))
        ok("refused_stage.before.not_staged", box2.git(work2, "ls-files", "-s", "libs/a").split()[1] == s1b)
    finally:
        box2.cleanup()
    # review round 13 (mutant S04): since RV12-2 the stop above is refused at the parent's pre-add index read, so
    # the marker site's own pre-check is no longer reached there. The stop lands right AFTER that read answered: the
    # stage-pin marker must still never be written, the add never runs, the pin is not staged
    box3 = Box("refused_stage_after_pre_index")
    try:
        work3, s1c, s2c, r1c = pin_behind_tree(box3)
        rc4, so4, se4, drv4, rep4 = inproc(box3, "hardstop-after-pre-index", "--apply", "--advance-pins",
                                           "--root", work3, "--quiet")
        pin3 = [x for x in (rec(rep4, "libs/a") or {}).get("actions") or [] if x.get("op") == "advance-pin"]
        ok("refused_stage.after_pre_index.fired", drv4.get("fired") == [os.path.realpath(work3)], drv4)
        ok("refused_stage.after_pre_index.stage_marker_never_written", drv4.get("markers") == ["advance-pin"], drv4)
        ok("refused_stage.after_pre_index.no_parent_marker", not os.path.exists(os.path.join(work3, ".git", MARKER)))
        ok("refused_stage.after_pre_index.not_staged",
           box3.git(work3, "ls-files", "-s", "libs/a").split()[1] == s1c)
        ok("refused_stage.after_pre_index.reported_unresolved",
           bool(pin3) and str(pin3[-1].get("why", "")).startswith("unresolved:"), pin3)
    finally:
        box3.cleanup()


def c_marker_and_lock_on_clean_tree(box):
    """RV6-2 (reviewer discriminator). What a SIGKILLed write leaves (ground truth, git 2.53: the write's marker
    plus git's index.lock) on an otherwise clean tree: the lock is attributed to the interrupted write
    ('in-progress-since-write-interrupted:index.lock' with 'write-interrupted-earlier:fast-forward'), never reported
    as the user's own operation. Control: the same lock with no marker is the user's ('in-progress:index.lock')."""
    r_url, r_seed = box.bare("HelixDevelopment", "ml")
    work = box.clone(r_url, "ml")
    gd = os.path.join(work, ".git")
    with open(os.path.join(gd, MARKER), "w") as f:
        json.dump({"op": "fast-forward", "target": "0" * 40, "run_id": "x", "started": "x"}, f)
    open(os.path.join(gd, "index.lock"), "w").close()
    ok("marker_lock.control_tree_clean", box.git(work, "status", "--porcelain=v1", "--untracked-files=normal") == "")
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    reasons = rec(rep, ".").get("reasons", [])
    ok("marker_lock.exit_4", rc == 4, "rc=%s" % rc)
    ok("marker_lock.attributed", "write-interrupted-earlier:fast-forward" in reasons and
       "in-progress-since-write-interrupted:index.lock" in reasons, reasons)
    ok("marker_lock.not_users", "in-progress:index.lock" not in reasons, reasons)
    ok("marker_lock.marker_kept", os.path.exists(os.path.join(gd, MARKER)))
    os.unlink(os.path.join(gd, MARKER))
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    reasons = rec(rep, ".").get("reasons", [])
    ok("marker_lock.control_users", "in-progress:index.lock" in reasons and
       not [x for x in reasons if "write-interrupted" in x], reasons)


def c_flock_error_not_another_run(box):
    """RV6-3. A run lock whose flock fails with an error other than 'held' (ENOLCK; fixture: the kernel) is not
    'another sync run': FAILED exit 1 with its own message, for the root lock and for a per-repository lock.
    Control: EWOULDBLOCK on the per-repository lock is another run (exit 7)."""
    work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    for fault, want_rc, want_msg in (("flock-error-root", 1, "cannot take the run lock"),
                                     ("flock-error-repo", 1, "cannot take the run lock"),
                                     ("flock-held-repo", 7, "another sync run holds")):
        rc, so, se, drv, rep = inproc(box, fault, "--check", "--no-fetch", "--root", work, "--quiet")
        ok("flock_error.%s.exit_%d" % (fault, want_rc), rc == want_rc, "rc=%s %s" % (rc, se[-300:]))
        ok("flock_error.%s.message" % fault, want_msg in se, se[-300:])
        if want_rc != 7:
            ok("flock_error.%s.not_another_run" % fault, "another sync run" not in se, se[-300:])
            ok("flock_error.%s.result_failed" % fault, "RESULT: FAILED exit=1" in so, so[-300:])


# ───────────────────────── review round 8 (RV7-1 .. RV7-3: the marker state machine) ─────────────────────────
def two_pin_tree(box):
    """root with TWO own-org submodules libs/a, libs/b whose pins are behind main (both upstreams moved, the root
    did not record it): --advance-pins advances both, so the root's git dir takes two stage-pin writes in ONE run.
    Returns (work, a0, b0, a2, b2)."""
    a_url, a_seed = box.bare("HelixDevelopment", "a")
    b_url, b_seed = box.bare("HelixDevelopment", "b")
    r_url, r_seed = box.bare("HelixDevelopment", "root")
    box.git(r_seed, "-c", "protocol.file.allow=always", "submodule", "add", "-q", a_url, "libs/a")
    box.git(r_seed, "-c", "protocol.file.allow=always", "submodule", "add", "-q", b_url, "libs/b")
    box.git(r_seed, "commit", "-q", "-m", "add subs")
    box.git(r_seed, "push", "-q", "origin", "HEAD:main")
    work = box.clone(r_url, "p")
    a2 = box.commit(a_seed, "a moves")
    b2 = box.commit(b_seed, "b moves")
    a0 = box.git(os.path.join(work, "libs/a"), "rev-parse", "HEAD")
    b0 = box.git(os.path.join(work, "libs/b"), "rev-parse", "HEAD")
    return work, a0, b0, a2, b2


def spawns_ok(name, drv):
    """Every write git the driver saw start held, at that moment, the marker its own write created (never a
    foreign one, never none): the path-wise invariant of round 8."""
    sp = drv.get("spawns") or []
    bad = [x for x in sp if not (x.get("marker") and x.get("own") and not x.get("planted"))]
    ok(name + ".every_write_held_its_own_marker", not bad, bad or sp)
    return sp


def c_sibling_kill(box):
    """RV7-1 (reviewer probe probes/sibling_kill_probe.py, as a check). Two siblings advance; the FIRST stage-pin
    'add' into the root is ended by its own limit and SIGKILLed (fixture: the kernel; index.lock left). The second
    sibling must NOT write into the root's git dir (it holds a killed write): it is blocked BEFORE its own child is
    moved; the killed write's marker is kept unchanged; a later run attributes the root's index.lock to it."""
    work, a0, b0, a2, b2 = two_pin_tree(box)
    gd = os.path.join(work, ".git")
    rc, so, se, drv, rep = inproc(box, "kill-first-add", "--apply", "--advance-pins", "--root", work, "--quiet")
    sp = spawns_ok("sibling_kill", drv)
    b = rec(rep, "libs/b")
    ok("sibling_kill.exit_1", rc == 1, "rc=%s %s" % (rc, se[-300:]))
    ok("sibling_kill.one_add_only", [x["sub"] for x in sp].count("add") == 1, sp)
    ok("sibling_kill.a_moved", box.git(os.path.join(work, "libs/a"), "rev-parse", "HEAD") == a2)
    ok("sibling_kill.b_not_moved", box.git(os.path.join(work, "libs/b"), "rev-parse", "HEAD") == b0)
    ok("sibling_kill.b_blocked_before_move", {"op": "none", "why": "blocked:parent-earlier-write-unresolved:"
                                              "write-killed", "for": "advance-pin"} in (b.get("actions") or []),
       b.get("actions"))
    ok("sibling_kill.marker_kept", os.path.exists(os.path.join(gd, MARKER)))
    try:
        with open(os.path.join(gd, MARKER), encoding="utf-8") as f:
            op = json.load(f).get("op")
    except (OSError, ValueError):
        op = None
    ok("sibling_kill.marker_is_the_killed_writes", op == "stage-pin", op)
    ok("sibling_kill.lock_left", os.path.exists(os.path.join(gd, "index.lock")))
    rc2, so2, se2, rep2, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    reasons = rec(rep2, ".").get("reasons", [])
    ok("sibling_kill.later_run_attributes", "write-interrupted-earlier:stage-pin" in reasons and
       "in-progress-since-write-interrupted:index.lock" in reasons, reasons)
    ok("sibling_kill.not_blamed_on_user", "in-progress:index.lock" not in reasons, reasons)
    box2 = Box("sibling_control")  # control: the same tree, no fault: both pins staged, nothing left
    try:
        w2, a0c, b0c, a2c, b2c = two_pin_tree(box2)
        rc3, so3, se3, drv3, rep3 = inproc(box2, "none", "--apply", "--advance-pins", "--root", w2, "--quiet")
        spawns_ok("sibling_kill.control", drv3)
        ok("sibling_kill.control_exit_0", rc3 == 0, "rc=%s %s" % (rc3, se3[-300:]))
        ok("sibling_kill.control_both_staged", box2.git(w2, "ls-files", "-s", "libs/a").split()[1] == a2c and
           box2.git(w2, "ls-files", "-s", "libs/b").split()[1] == b2c)
        ok("sibling_kill.control_nothing_left", not os.path.exists(os.path.join(w2, ".git", MARKER)) and
           not os.path.exists(os.path.join(w2, ".git", "index.lock")))
    finally:
        box2.cleanup()


def c_sibling_wipe(box):
    """RV7-1, the run's own memory: as sibling_kill, then the root's marker AND index.lock are removed before the
    second sibling starts (fixture: someone cleans up mid-run). Nothing on disk says a write was killed; the run's
    marker state (write-killed) still blocks the second sibling before its child moves."""
    work, a0, b0, a2, b2 = two_pin_tree(box)
    rc, so, se, drv, rep = inproc(box, "kill-first-add-then-wipe", "--apply", "--advance-pins", "--root", work,
                                  "--quiet")
    sp = spawns_ok("sibling_wipe", drv)
    b = rec(rep, "libs/b")
    ok("sibling_wipe.one_add_only", [x["sub"] for x in sp].count("add") == 1, sp)
    ok("sibling_wipe.b_not_moved", box.git(os.path.join(work, "libs/b"), "rev-parse", "HEAD") == b0)
    ok("sibling_wipe.b_blocked_by_state", {"op": "none", "why": "blocked:parent-earlier-write-unresolved:"
                                           "write-killed", "for": "advance-pin"} in (b.get("actions") or []),
       b.get("actions"))


def c_parent_lock(box):
    """RV7-1, step 3a: a user's index.lock appears in the ROOT's git dir after inspection, before an advance-pin
    starts (fixture: the driver creates it). The child must not be moved (its pin could not be staged); the lock
    is never removed by the engine; the block is reported."""
    work, s1, s2, r1 = pin_behind_tree(box)
    sub = os.path.join(work, "libs/a")
    before = box.git(sub, "rev-parse", "HEAD")
    rc, so, se, drv, rep = inproc(box, "lock-pinparent", "--apply", "--advance-pins", "--root", work, "--quiet")
    sp = drv.get("spawns") or []
    a = rec(rep, "libs/a")
    ok("parent_lock.not_exit_0", rc not in (0, None), "rc=%s %s" % (rc, se[-200:]))
    ok("parent_lock.child_not_moved", box.git(sub, "rev-parse", "HEAD") == before)
    ok("parent_lock.no_write_started", not sp, sp)
    ok("parent_lock.blocked_before_move", {"op": "none", "why": "blocked:parent-in-progress:index.lock",
                                           "for": "advance-pin"} in (a.get("actions") or []), a.get("actions"))
    ok("parent_lock.lock_kept", os.path.exists(os.path.join(work, ".git", "index.lock")))
    b = Box("parent_lock_late")  # the lock appears AFTER step 3a, while the child's checkout runs
    try:
        w2, s1b, s2b, r1b = pin_behind_tree(b)
        rc2, so2, se2, drv2, rep2 = inproc(b, "lock-parent-at-pin-checkout", "--apply", "--advance-pins", "--root",
                                           w2, "--quiet")
        sp2 = drv2.get("spawns") or []
        a2 = rec(rep2, "libs/a")
        acts = a2.get("actions") or []
        ok("parent_lock.late.exit_1", rc2 == 1, "rc=%s %s" % (rc2, se2[-200:]))
        ok("parent_lock.late.no_add_started", [x["sub"] for x in sp2] == ["checkout"], sp2)
        ok("parent_lock.late.stage_blocked_reported", any(x.get("op") == "advance-pin" and
                                                          x.get("why") == "blocked:in-progress:index.lock"
                                                          for x in acts), acts)
        ok("parent_lock.late.child_failed", a2.get("failed") is True, a2)
        ok("parent_lock.late.lock_kept_no_marker", os.path.exists(os.path.join(w2, ".git", "index.lock")) and
           not os.path.exists(os.path.join(w2, ".git", MARKER)))
    finally:
        b.cleanup()


def site_tree(box, site):
    """(work, repo dir of the write at ``site``, git dir that write targets, engine args) for ff / pin / follow /
    stage / pinparent."""
    if site == "ff":
        r_url, r_seed = box.bare("HelixDevelopment", "solo")
        work = box.clone(r_url, "w")
        box.commit(r_seed, "upstream moves")
        return work, work, os.path.join(work, ".git"), ["--apply"]
    if site == "follow":
        work, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
        sub = os.path.join(work, "libs/a")
        return work, sub, box.git(sub, "rev-parse", "--absolute-git-dir"), ["--apply"]
    work, s1, s2, r1 = pin_behind_tree(box)
    sub = os.path.join(work, "libs/a")
    if site == "pin":
        return work, sub, box.git(sub, "rev-parse", "--absolute-git-dir"), ["--apply", "--advance-pins"]
    return work, sub, os.path.join(work, ".git"), ["--apply", "--advance-pins"]  # stage, pinparent


def c_marker_preexisting(box):
    """RV7-1 / RV7-3, every write site x 'a marker that this write did not create is already there when the write
    starts' (fixture: a foreign marker planted by the driver). plant-<site>: before the write asks for its marker;
    race-<site>: in the window after begin_write's checks, before the marker is created (only O_EXCL sees it);
    swap-<site>: right after the marker was created, before git starts (Runner.run's token check sees it). For
    every case: the foreign marker's bytes are unchanged, no write git starts into that git dir, the write is
    reported (never silent). pinparent: the marker is in the ROOT's git dir before an advance-pin starts: the
    child is not moved at all."""
    cases = [(k, s_) for k in ("plant", "race", "swap") for s_ in ("ff", "pin", "follow", "stage")]
    cases.append(("plant", "pinparent"))
    for i, (kind, site) in enumerate(cases):
        tag = "%s-%s" % (kind, site)
        b = Box("pre_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, site)
            before = b.git(repo_dir, "rev-parse", "HEAD")
            rc, so, se, drv, rep = inproc(b, tag, *(args + ["--root", work, "--quiet"]))
            sp = drv.get("spawns") or []
            intact = drv.get("planted_intact") or {}
            ok("marker_pre.%s.planted" % tag, len(intact) == 1, drv)
            ok("marker_pre.%s.foreign_marker_intact" % tag, bool(intact) and all(intact.values()), intact)
            into = [x for x in sp if os.path.realpath(x["gitdir"]) == os.path.realpath(gd) and
                    (x["sub"] == "add") == (site in ("stage", "pinparent"))]
            ok("marker_pre.%s.no_write_into_that_git_dir" % tag, not into, into)
            spawns_ok("marker_pre.%s" % tag, drv)
            ok("marker_pre.%s.not_exit_0" % tag, rc not in (0, None), "rc=%s %s" % (rc, se[-200:]))
            if site in ("ff", "pin", "follow", "pinparent"):
                ok("marker_pre.%s.not_moved" % tag, b.git(repo_dir, "rev-parse", "HEAD") == before)
            whys = [str(a.get("why")) for x in (rep or {}).get("repos", []) for a in (x.get("actions") or [])]
            ok("marker_pre.%s.reported" % tag, any("write-marker" in w or "write-marker-not-ours" in w for w in whys),
               whys)
        except Exception as e:  # a fixture that could not be built is a failure, never a pass
            ok("marker_pre.%s.fixture" % tag, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_stop_pin_marker(box):
    """RV7-2 / mutant RV7C. One stop signal while the advance-pin checkout runs (fixture: the signal, in-process):
    the second half of the write (the stage-pin add) still runs, HOLDING its marker in the root's git dir while it
    runs (spawn audit), the pin is staged, nothing is left afterwards, exit 8."""
    work, s1, s2, r1 = pin_behind_tree(box)
    rc, so, se, drv, rep = inproc(box, "stop-at-pin-checkout", "--apply", "--advance-pins", "--root", work, "--quiet")
    sp = spawns_ok("stop_pin", drv)
    ok("stop_pin.exit_8", rc == 8, "rc=%s %s" % (rc, se[-300:]))
    ok("stop_pin.add_ran", [x["sub"] for x in sp] == ["checkout", "add"], sp)
    ok("stop_pin.staged_s2", box.git(work, "ls-files", "-s", "libs/a").split()[1] == s2)
    ok("stop_pin.nothing_left", not os.path.exists(os.path.join(work, ".git", MARKER)) and
       not os.path.exists(os.path.join(box.git(os.path.join(work, "libs/a"), "rev-parse", "--absolute-git-dir"),
                                       MARKER)))


# ───────────────────────────── review round 9 (RV8-1 .. RV8-4) ─────────────────────────────
# The lock files git itself creates for each engine write (ground truth, git 2.53, strace + stale-lock matrix:
# docs/qa/sync_upstreams_2026_11_15_r9/ground_truth/). "common/" = the git common dir; else the write's git dir.
SITE_LOCKS = {
    "ff": ["index.lock", "HEAD.lock", "ORIG_HEAD.lock", "AUTO_MERGE.lock", "common/packed-refs.lock",
           "common/refs/heads/main.lock"],
    "pin": ["index.lock", "HEAD.lock", "AUTO_MERGE.lock", "common/packed-refs.lock"],
    "follow": ["index.lock", "HEAD.lock", "AUTO_MERGE.lock", "common/packed-refs.lock"],
}


def lock_path(box, repo_dir, gd, rel):
    if rel.startswith("common/"):
        common = box.git(repo_dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
        return os.path.join(common, rel[len("common/"):])
    return os.path.join(gd, rel)


def plant_file(path, data=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


EARLIER = json.dumps({"op": "fast-forward", "target": "0" * 40, "run_id": "earlier", "write_id": "earlier:1:1",
                      "started": "2026-11-15T00:00:00Z"}).encode()


def all_notes(rep):
    return [n for x in (rep or {}).get("repos", []) for n in (x.get("notes") or [])]


def c_stale_lock_matrix(box):
    """RV8-1. A STALE lock that git takes for the write (every one of SITE_LOCKS, measured) is in the write's git dir
    or common dir before an --apply run, with and (fast-forward) without an earlier-run marker. Ground truth: git
    itself, given a stale HEAD.lock or branch ref lock, rewrites the index and work tree and then fails (exit 128):
    a HALF-APPLIED write. The engine must refuse the write BEFORE git starts: nothing moved, the tree exactly as
    before (git status empty), the lock untouched, the lock named in the reasons; an earlier marker is KEPT (never
    'left-nothing'). Golden-FALSE (section 11.4.201(1)): a lock git does NOT take for this write (another branch's
    ref lock, config.lock) does not block the fast-forward."""
    cases = [(site, rel, mk) for site in ("ff", "pin", "follow") for rel in SITE_LOCKS[site]
             for mk in ((False, True) if site == "ff" else (False,))]
    for i, (site, rel, mk) in enumerate(cases):
        tag = "%s.%s%s" % (site, rel.replace("/", "_"), ".marker" if mk else "")
        b = Box("lockm_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, site)
            before = b.git(repo_dir, "rev-parse", "HEAD")
            lk = lock_path(b, repo_dir, gd, rel)
            plant_file(lk)
            if mk:
                plant_file(os.path.join(gd, MARKER), EARLIER)
            rc, so, se, rep, _ = b.run(*(args + ["--root", work, "--quiet"]), timeout=300)
            ok("lock_matrix.%s.not_moved" % tag, b.git(repo_dir, "rev-parse", "HEAD") == before)
            st = b.git(repo_dir, "status", "--porcelain=v1", "--untracked-files=normal")
            ok("lock_matrix.%s.no_half_write" % tag, st == "", repr(st))
            ok("lock_matrix.%s.lock_untouched" % tag, os.path.isfile(lk) and os.path.getsize(lk) == 0)
            ok("lock_matrix.%s.not_exit_0" % tag, rc not in (0, None), "rc=%s" % rc)
            name = rel[len("common/"):] if rel.startswith("common/") else rel
            reasons = [y for x in (rep or {}).get("repos", []) for y in (x.get("reasons") or [])]
            ok("lock_matrix.%s.lock_named" % tag, any(name in y for y in reasons), reasons)
            if mk:
                ok("lock_matrix.%s.marker_kept" % tag, os.path.isfile(os.path.join(gd, MARKER)))
                notes = all_notes(rep)
                ok("lock_matrix.%s.never_left_nothing" % tag, not [n for n in notes if "left-nothing" in n], notes)
        except Exception as e:  # a fixture that could not be built is a failure, never a pass
            ok("lock_matrix.%s.fixture" % tag, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()
    for i, rel in enumerate(("common/refs/heads/other.lock", "common/config.lock")):
        b = Box("lockf_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, "ff")
            plant_file(lock_path(b, repo_dir, gd, rel))
            rc, so, se, rep, _ = b.run(*(args + ["--root", work, "--quiet"]), timeout=300)
            tag = rel.replace("/", "_")
            ok("lock_matrix.golden_false.%s.exit_0" % tag, rc == 0, "rc=%s %s" % (rc, se[-300:]))
            ok("lock_matrix.golden_false.%s.moved" % tag,
               b.git(repo_dir, "rev-parse", "HEAD") == b.git(repo_dir, "rev-parse", "origin/main"))
        except Exception as e:
            ok("lock_matrix.golden_false.%d.fixture" % i, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_worktree_locks(box):
    """RV8-1, linked worktree (reviewer's UNCONFIRMED case, probed): the root is a LINKED worktree on main; its git
    dir is <common>/worktrees/<id> (index, HEAD, ORIG_HEAD, AUTO_MERGE locks there) while the branch ref lock and
    packed-refs.lock are in the common dir. A stale lock in EITHER place git takes for the write blocks it before
    git starts (no half-write). Golden-FALSE: the MAIN worktree's own HEAD.lock (<common>/HEAD.lock) is not taken by
    the linked worktree's fast-forward (measured) and does not block it."""
    for i, (where, name, blocks) in enumerate((("common", "refs/heads/main.lock", True),
                                               ("common", "packed-refs.lock", True),
                                               ("wt", "HEAD.lock", True), ("wt", "index.lock", True),
                                               ("common", "HEAD.lock", False))):
        tag = "%s_%s" % (where, name.replace("/", "_"))
        b = Box("wt_%d" % i)
        try:
            r_url, r_seed = b.bare("HelixDevelopment", "wtroot")
            main_wt = b.clone(r_url, "mw")
            b.git(main_wt, "checkout", "-q", "-b", "side")
            wt = b.p("work", "lw")
            b.git(main_wt, "worktree", "add", "-q", wt, "main")
            b.commit(r_seed, "upstream moves")
            common = os.path.join(main_wt, ".git")
            wgd = b.git(wt, "rev-parse", "--absolute-git-dir")
            ok("worktree.%s.fixture_split" % tag, os.path.realpath(wgd) != os.path.realpath(common), wgd)
            lk = os.path.join(common if where == "common" else wgd, name)
            before = b.git(wt, "rev-parse", "HEAD")
            plant_file(lk)
            rc, so, se, rep, _ = b.run("--apply", "--root", wt, "--quiet", timeout=300)
            st = b.git(wt, "status", "--porcelain=v1", "--untracked-files=normal")
            if blocks:
                ok("worktree.%s.not_moved" % tag, b.git(wt, "rev-parse", "HEAD") == before)
                ok("worktree.%s.no_half_write" % tag, st == "", repr(st))
                ok("worktree.%s.not_exit_0" % tag, rc not in (0, None), "rc=%s" % rc)
            else:
                ok("worktree.%s.golden_false_exit_0" % tag, rc == 0, "rc=%s %s" % (rc, se[-300:]))
                ok("worktree.%s.golden_false_moved" % tag,
                   b.git(wt, "rev-parse", "HEAD") == b.git(wt, "rev-parse", "origin/main"))
            ok("worktree.%s.lock_untouched" % tag, os.path.isfile(lk))
        except Exception as e:
            ok("worktree.%s.fixture" % tag, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def make_kind(path, kind):
    """Put a filesystem object of ``kind`` at ``path`` (fixture: a user, another program, or a broken disk)."""
    if kind == "fifo":
        os.mkfifo(path)
    elif kind == "dir":
        os.mkdir(path)
    elif kind == "symlink":
        os.symlink("/dev/zero", path)
    elif kind == "dangling":
        os.symlink(path + ".nowhere", path)
    elif kind == "socket":
        import socket
        old = os.getcwd()
        os.chdir(os.path.dirname(path))  # AF_UNIX paths are limited to ~107 bytes: bind by the relative name
        try:
            so_ = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            so_.bind(os.path.basename(path))
            so_.close()
        finally:
            os.chdir(old)


def kind_now(path):
    import stat as st_
    try:
        m = os.lstat(path).st_mode
    except OSError:
        return "absent"
    return ("fifo" if st_.S_ISFIFO(m) else "dir" if st_.S_ISDIR(m) else "symlink" if st_.S_ISLNK(m) else
            "socket" if st_.S_ISSOCK(m) else "regular" if st_.S_ISREG(m) else "other")


def c_marker_path_kinds(box):
    """RV8-2 / RV8-4 and the class "a filesystem object that is not a regular file at the marker path": a FIFO (the
    r8 engine blocked forever in open(), every mode, the post-update hook's --check included), a directory (r8:
    IsADirectoryError in --apply), a symbolic link to /dev/zero, a dangling symbolic link, a socket. Every mode
    ends within a bound (60 s), the object is never opened, removed or replaced, nothing moves, the run is ATTENTION
    (exit 4) with the marker path named, and a report is written."""
    for i, (kind, mode) in enumerate([(k, m) for k in ("fifo", "dir", "symlink", "dangling", "socket")
                                      for m in ("check", "apply", "dry-run")]):
        tag = "%s.%s" % (kind, mode)
        b = Box("mk_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, "ff")
            before = b.git(work, "rev-parse", "HEAD")
            mp = os.path.join(gd, MARKER)
            make_kind(mp, "dangling" if kind == "dangling" else kind)
            want_kind = "symlink" if kind == "dangling" else kind
            margs = {"check": ["--check", "--no-fetch"], "apply": ["--apply"], "dry-run": ["--dry-run"]}[mode]
            try:
                rc, so, se, rep, secs = b.run(*(margs + ["--root", work, "--quiet", "--deadline", "40"]), timeout=60)
                hung = False
            except subprocess.TimeoutExpired:
                rc, so, se, rep, hung = None, "", "", None, True
            ok("marker_kind.%s.bounded" % tag, not hung, "the run did not end within 60 s")
            ok("marker_kind.%s.untouched" % tag, kind_now(mp) == want_kind, kind_now(mp))
            ok("marker_kind.%s.not_moved" % tag, b.git(work, "rev-parse", "HEAD") == before)
            ok("marker_kind.%s.exit_4" % tag, rc == 4, "rc=%s %s" % (rc, se[-300:]))
            reasons = rec(rep, ".").get("reasons", []) if rep else []
            ok("marker_kind.%s.named" % tag, any("write-marker" in y for y in reasons), reasons)
        except Exception as e:
            ok("marker_kind.%s.fixture" % tag, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_lock_path_kinds(box):
    """RV8-2 class, the run lock path: a FIFO or a socket at <common>/helix-sync-upstreams.lock is not this
    engine's lock file: the run ends within a bound, FAILED exit 1 'cannot open the run lock', the object untouched,
    nothing moved. Control: a directory there is refused the same way."""
    for i, kind in enumerate(("fifo", "socket", "dir")):
        b = Box("lk_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, "ff")
            before = b.git(work, "rev-parse", "HEAD")
            lp = os.path.join(gd, "helix-sync-upstreams.lock")
            make_kind(lp, kind)
            try:
                rc, so, se, rep, secs = b.run("--apply", "--root", work, "--quiet", "--deadline", "40", timeout=60)
                hung = False
            except subprocess.TimeoutExpired:
                rc, so, se, hung = None, "", "", True
            ok("lock_kind.%s.bounded" % kind, not hung)
            ok("lock_kind.%s.exit_1" % kind, rc == 1, "rc=%s %s" % (rc, se[-300:]))
            ok("lock_kind.%s.cannot_open" % kind, "cannot open the run lock" in se, se[-300:])
            ok("lock_kind.%s.untouched" % kind, kind_now(lp) == kind, kind_now(lp))
            ok("lock_kind.%s.not_moved" % kind, b.git(work, "rev-parse", "HEAD") == before)
        except Exception as e:
            ok("lock_kind.%s.fixture" % kind, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_half_write(box):
    """RV8-1, the second half: a write that git ANSWERS with a failure after it already changed the tree (fixture:
    another git process holds HEAD.lock or the branch ref lock while the engine's write runs, then ends; ground truth:
    git rewrites the index and work tree, then exits 128). The marker is KEPT ('write-left-changes'), the run is
    FAILED, and the NEXT run attributes the leftovers to that write (write-interrupted-earlier, ...-since-write-
    interrupted), never to the user. Golden-FALSE: the same at ORIG_HEAD.lock / index.lock, where git refuses before
    changing anything (measured): the marker is removed and the next run blames nothing on a write."""
    for i, (rel, site, changes) in enumerate((("HEAD.lock", "ff", True), ("common/refs/heads/main.lock", "ff", True),
                                              ("HEAD.lock", "pin", True), ("ORIG_HEAD.lock", "ff", False),
                                              ("index.lock", "ff", False))):
        tag = "%s.%s" % (site, rel.replace("/", "_"))
        b = Box("hw_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, site)
            rc, so, se, drv, rep = inproc(b, "lockspawn:%s:%s" % (rel, site), *(args + ["--root", work, "--quiet"]))
            st = b.git(repo_dir, "status", "--porcelain=v1", "--untracked-files=normal")
            ok("half_write.%s.fixture_effect" % tag, bool(st) == changes, repr(st))
            ok("half_write.%s.not_exit_0" % tag, rc not in (0, None), "rc=%s %s" % (rc, se[-300:]))
            mp = os.path.join(gd, MARKER)
            whys = [str(a.get("why")) for x in (rep or {}).get("repos", []) for a in (x.get("actions") or [])]
            if changes:
                ok("half_write.%s.marker_kept" % tag, os.path.isfile(mp))
                ok("half_write.%s.reported" % tag, any("write-left-changes" in w for w in whys), whys)
                # U17: the run is FAILED (exit 1) and the repository's result is "failed", never only attention
                hit = [x for x in (rep or {}).get("repos", []) if x.get("write_left_changes")]
                ok("half_write.%s.exit_failed" % tag, rc == 1, "rc=%s" % rc)
                ok("half_write.%s.repo_result_failed" % tag, bool(hit) and all(x.get("result") == "failed" for x in hit),
                   [(x.get("path"), x.get("result")) for x in hit])
            else:
                ok("half_write.%s.golden_false_marker_removed" % tag, not os.path.lexists(mp))
            rc2, so2, se2, rep2, _ = b.run("--check", "--no-fetch", "--root", work, "--quiet", timeout=300)
            reasons = [y for x in (rep2 or {}).get("repos", []) for y in (x.get("reasons") or [])]
            if changes:
                ok("half_write.%s.next_run_attributes" % tag,
                   any(y.startswith("write-interrupted-earlier:") for y in reasons) and
                   any("since-write-interrupted" in y for y in reasons), reasons)
            else:
                ok("half_write.%s.golden_false_nothing_attributed" % tag,
                   not [y for y in reasons if "write-interrupted" in y], reasons)
        except Exception as e:
            ok("half_write.%s.fixture" % tag, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_marker_vanish(box):
    """RV8-3 / reviewer mutant W03: the write's own marker is REMOVED after it was created and before git starts
    (fixture: another program, in-process). Runner.run's token check must refuse: no write git starts into that
    git dir (spawn audit), the refusal is reported ('write-marker-not-ours'), nothing moves, not exit 0."""
    for i, site in enumerate(("ff", "pin", "follow", "stage")):
        b = Box("van_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, site)
            before = b.git(repo_dir, "rev-parse", "HEAD")
            rc, so, se, drv, rep = inproc(b, "vanish-" + site, *(args + ["--root", work, "--quiet"]))
            sp = drv.get("spawns") or []
            into = [x for x in sp if os.path.realpath(x["gitdir"]) == os.path.realpath(gd) and
                    (x["sub"] == "add") == (site == "stage")]
            ok("vanish.%s.no_write_without_marker" % site, not into, into)
            ok("vanish.%s.every_spawn_marked" % site, not [x for x in sp if not x.get("marker")], sp)
            ok("vanish.%s.not_exit_0" % site, rc not in (0, None), "rc=%s %s" % (rc, se[-200:]))
            if site != "stage":
                ok("vanish.%s.not_moved" % site, b.git(repo_dir, "rev-parse", "HEAD") == before)
            whys = [str(a.get("why")) for x in (rep or {}).get("repos", []) for a in (x.get("actions") or [])]
            ok("vanish.%s.reported" % site, any("write-marker-not-ours" in w for w in whys), whys)
        except Exception as e:
            ok("vanish.%s.fixture" % site, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_earlier_marker_lock_apply(box):
    """RV8-3 / reviewer mutant W01: an earlier-run marker plus a lock git takes for the write, on an otherwise clean,
    CURRENT tree, in --apply (the mode that may clear an earlier marker): the marker is KEPT (the lock is that
    write's leftover), noted 'write-marker-kept', never 'left-nothing'; the lock is attributed to the earlier write.
    Control: the same marker with no lock and nothing else is cleared (it left nothing)."""
    for i, rel in enumerate(("index.lock", "HEAD.lock", "ORIG_HEAD.lock", "AUTO_MERGE.lock", "packed-refs.lock",
                             "refs/heads/main.lock", None)):
        tag = (rel or "control").replace("/", "_")
        b = Box("eml_%d" % i)
        try:
            r_url, r_seed = b.bare("HelixDevelopment", "eml")
            work = b.clone(r_url, "eml")
            gd = os.path.join(work, ".git")
            plant_file(os.path.join(gd, MARKER), EARLIER)
            if rel:
                plant_file(os.path.join(gd, rel))
            rc, so, se, rep, _ = b.run("--apply", "--root", work, "--quiet", timeout=300)
            notes = all_notes(rep)
            if rel:
                ok("earlier_lock.%s.marker_kept" % tag, os.path.isfile(os.path.join(gd, MARKER)))
                ok("earlier_lock.%s.noted_kept" % tag, any(n.startswith("write-marker-kept") for n in notes), notes)
                ok("earlier_lock.%s.never_left_nothing" % tag, not [n for n in notes if "left-nothing" in n], notes)
                reasons = rec(rep, ".").get("reasons", [])
                ok("earlier_lock.%s.attributed" % tag, "write-interrupted-earlier:fast-forward" in reasons and
                   any(y.startswith("in-progress-since-write-interrupted:") and rel in y for y in reasons), reasons)
            else:
                ok("earlier_lock.control.cleared", not os.path.lexists(os.path.join(gd, MARKER)))
                ok("earlier_lock.control.noted", any("left-nothing" in n for n in notes), notes)
        except Exception as e:
            ok("earlier_lock.%s.fixture" % tag, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_marker_unremovable(box):
    """RV8-4 class, the clear path: an earlier-run marker over a clean, current tree in --apply, in a git dir where it
    cannot be removed (the git dir is read-only: EACCES). The marker is KEPT and noted 'write-marker-kept:cannot-
    remove:...', never 'cleared ... left-nothing'; the run does not crash (no internal error) and ends."""
    b = Box("unrm")
    gd = None
    try:
        r_url, r_seed = b.bare("HelixDevelopment", "unrm")
        work = b.clone(r_url, "unrm")
        gd = os.path.join(work, ".git")
        plant_file(os.path.join(gd, MARKER), EARLIER)
        plant_file(os.path.join(gd, "helix-sync-upstreams.lock"))  # the run lock exists: only the clear is refused
        os.chmod(gd, 0o555)
        rc, so, se, rep, _ = b.run("--apply", "--no-fetch", "--root", work, "--quiet", timeout=300)
        notes = all_notes(rep)
        ok("marker_unremovable.no_internal_error", "internal error" not in se, se[-300:])
        ok("marker_unremovable.kept", os.path.isfile(os.path.join(gd, MARKER)))
        ok("marker_unremovable.noted", any(n.startswith("write-marker-kept:cannot-remove:failed:EACCES")
                                           for n in notes), notes)
        ok("marker_unremovable.never_left_nothing", not [n for n in notes if "left-nothing" in n], notes)
    except Exception as e:
        ok("marker_unremovable.fixture", False, "%s: %s" % (type(e).__name__, e))
    finally:
        if gd:
            os.chmod(gd, 0o755)
        b.cleanup()


# ───────────────────────── review round 10 (RV9-1 .. RV9-6) ─────────────────────────
# RV9-1, class "a lock or marker path built from a parameter": every parameter the engine substitutes into a path
# it checks before a write: the BRANCH ({branch} of refs/heads/{branch}.lock), the GIT DIR of the write (per
# worktree: <common>/worktrees/<id>, so the worktree id too), the COMMON DIR, and the fixed NAMES joined to each
# (the git-dir locks, MERGE_HEAD and the other operation names, the write marker, the run lock). Each has a check
# here that a wrong substitution fails: a lock at the right path blocks, the same name at a wrong path does not.
BRANCHES = ("main", "dev", "feature/x", "Dev", "Feature/X")  # round 11 (RV10-2 / AA01): mixed case too


def branch_tree(box, layout, br, name="brt"):
    """A root checked out on branch ``br`` one commit behind its upstream ``br``. layout 'plain': a clone (git dir ==
    common dir); 'wt': a LINKED worktree of a clone whose own worktree is on 'side' (git dir
    <common>/worktrees/<id>). Returns (work, gitdir, common, args)."""
    r_url, r_seed = box.bare("HelixDevelopment", name)
    if br != "main":
        box.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/" + br)
    clone = box.clone(r_url, "c_" + name)
    if layout == "plain":
        if br != "main":
            box.git(clone, "checkout", "-q", "-b", br, "--track", "origin/" + br)
        work = clone
    else:
        box.git(clone, "checkout", "-q", "-b", "side")
        work = box.p("work", "lw_" + name)
        if br == "main":
            box.git(clone, "worktree", "add", "-q", work, "main")
        else:
            box.git(clone, "worktree", "add", "-q", "--track", "-b", br, work, "origin/" + br)
    box.commit(r_seed, "upstream moves")
    if br != "main":
        box.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/" + br)
    gd = box.git(work, "rev-parse", "--absolute-git-dir")
    common = box.git(work, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if (os.path.realpath(gd) != os.path.realpath(common)) != (layout == "wt"):
        raise RuntimeError("fixture layout %s: git dir %s common %s" % (layout, gd, common))
    if box.git(work, "symbolic-ref", "--short", "HEAD") != br:
        raise RuntimeError("fixture not on %s" % br)
    return work, gd, common, ["--apply", "--branch", br, "--root", work, "--quiet"]


def label_of(layout, name):
    return ("common:" + name) if layout == "wt" else name


def assert_blocked(tag, b, work, before, rc, rep, lk=None, want_reason=None):
    st = b.git(work, "status", "--porcelain=v1", "--untracked-files=normal")
    ok(tag + ".not_moved", b.git(work, "rev-parse", "HEAD") == before)
    ok(tag + ".no_half_write", st == "", repr(st))
    ok(tag + ".exit_4", rc == 4, "rc=%s" % rc)
    if lk:
        ok(tag + ".lock_untouched", os.path.isfile(lk) and os.path.getsize(lk) == 0)
    reasons = [y for x in (rep or {}).get("repos", []) for y in (x.get("reasons") or [])]
    if want_reason:
        ok(tag + ".reason", want_reason in reasons, reasons)
    return reasons


def assert_moved(tag, b, work, rc, se, br):
    ok(tag + ".golden_false_exit_0", rc == 0, "rc=%s %s" % (rc, se[-300:]))
    ok(tag + ".golden_false_moved", b.git(work, "rev-parse", "HEAD") == b.git(work, "rev-parse", "origin/" + br))


def c_branch_lock_class(box):
    """RV9-1 (reviewer mutant Z04 survived: every lock test used branch main). The branch ref lock git takes for a
    fast-forward is <common>/refs/heads/<CHECKED-OUT BRANCH>.lock, for a plain clone and for a linked worktree, for
    'main', a non-main name and a hierarchical name. A stale one blocks before git starts (exit 4, no write, tree
    clean, the lock named by its label). Golden-FALSE (section 11.4.201(1)): the ref lock of ANOTHER branch (main
    when the root is on another branch; the last name component of feature/x; dev when on main) does not block.
    With an earlier-run marker the marker is KEPT (never cleared 'left-nothing') for a non-main branch too."""
    for layout in ("plain", "wt"):
        for i, br in enumerate(BRANCHES):
            name = "refs/heads/%s.lock" % br
            tag = "branch_lock.%s.%s" % (layout, br.replace("/", "_"))
            b = Box("bl_%s_%d" % (layout, i))
            try:
                work, gd, common, args = branch_tree(b, layout, br)
                before = b.git(work, "rev-parse", "HEAD")
                lk = os.path.join(common, name)
                plant_file(lk)
                rc, so, se, rep, _ = b.run(*args, timeout=300)
                assert_blocked(tag, b, work, before, rc, rep, lk, "in-progress:" + label_of(layout, name))
            except Exception as e:
                ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
            finally:
                b.cleanup()
            others = {"main": ("refs/heads/dev.lock",), "dev": ("refs/heads/main.lock",),
                      "feature/x": ("refs/heads/main.lock", "refs/heads/x.lock", "refs/heads/feature.lock",
                                    "refs/heads/feature_x.lock"),
                      # round 11 (RV10-2): the same name in another CASE is another branch's lock
                      "Dev": ("refs/heads/dev.lock", "refs/heads/DEV.lock", "refs/heads/main.lock"),
                      "Feature/X": ("refs/heads/feature/x.lock", "refs/heads/Feature/x.lock",
                                    "refs/heads/feature/X.lock", "refs/heads/X.lock")}[br]
            for j, other in enumerate(others):
                tagf = "%s.golden_false.%s" % (tag, other.replace("/", "_"))
                b = Box("blf_%s_%d_%d" % (layout, i, j))
                try:
                    work, gd, common, args = branch_tree(b, layout, br)
                    plant_file(os.path.join(common, other))
                    rc, so, se, rep, _ = b.run(*args, timeout=300)
                    assert_moved(tagf, b, work, rc, se, br)
                except Exception as e:
                    ok(tagf + ".fixture", False, "%s: %s" % (type(e).__name__, e))
                finally:
                    b.cleanup()
            if br == "main":
                continue
            tagm = tag + ".earlier_marker"
            b = Box("blm_%s_%d" % (layout, i))
            try:
                work, gd, common, args = branch_tree(b, layout, br)
                before = b.git(work, "rev-parse", "HEAD")
                plant_file(os.path.join(gd, MARKER), EARLIER)
                plant_file(os.path.join(common, name))
                rc, so, se, rep, _ = b.run(*args, timeout=300)
                assert_blocked(tagm, b, work, before, rc, rep)
                ok(tagm + ".marker_kept", os.path.isfile(os.path.join(gd, MARKER)))
                notes = all_notes(rep)
                ok(tagm + ".never_left_nothing", not [n for n in notes if "left-nothing" in n], notes)
            except Exception as e:
                ok(tagm + ".fixture", False, "%s: %s" % (type(e).__name__, e))
            finally:
                b.cleanup()


def c_worktree_param_class(box):
    """RV9-1, the other parameters of the class, in a linked worktree (git dir <common>/worktrees/<id> != common
    dir): the GIT DIR (and with it the worktree id), the COMMON DIR and the names joined to each. Blocks: HEAD.lock,
    MERGE_HEAD and a FIFO at the write-marker path in THIS worktree's git dir; packed-refs.lock in the common dir;
    an earlier-run marker in this worktree's git dir plus index.lock there (attributed, marker kept). Golden-FALSE:
    the same names in ANOTHER worktree's git dir (a second linked worktree: a different worktree id) and in the
    main worktree's git dir (== the common dir: its HEAD.lock, MERGE_HEAD, marker) do not block, and the main
    worktree's marker is left untouched."""
    cases = (("own", "HEAD.lock", "plain", True), ("own", "MERGE_HEAD", "plain", True),
             ("own", MARKER, "fifo", True), ("own", MARKER + "+index.lock", "earlier", True),
             ("common", "packed-refs.lock", "plain", True),
             ("other", "HEAD.lock", "plain", False), ("other", "index.lock", "plain", False),
             ("other", "MERGE_HEAD", "plain", False), ("other", MARKER, "fifo", False),
             ("common", "HEAD.lock", "plain", False), ("common", "MERGE_HEAD", "plain", False),
             ("common", MARKER, "earlier", False), ("common", MARKER, "fifo", False))
    for i, (where, name, kind, blocks) in enumerate(cases):
        tag = "wt_param.%s.%s.%s" % (where, name.replace("/", "_").replace("+", "_"), kind)
        b = Box("wtp_%d" % i)
        try:
            work, gd, common, args = branch_tree(b, "wt", "feature/x", "wtp")
            clone = b.p("work", "c_wtp")
            other = b.p("work", "lw_other")
            b.git(clone, "worktree", "add", "-q", "-b", "other", other, "side")
            ogd = b.git(other, "rev-parse", "--absolute-git-dir")
            ok(tag + ".fixture_ids_differ", os.path.realpath(ogd) != os.path.realpath(gd), (ogd, gd))
            base = {"own": gd, "other": ogd, "common": common}[where]
            before = b.git(work, "rev-parse", "HEAD")
            main_name = name.split("+")[0]
            path = os.path.join(base, main_name)
            if kind == "fifo":
                os.mkfifo(path)
            elif kind == "earlier":
                plant_file(path, EARLIER)
                if "+" in name:
                    plant_file(os.path.join(base, name.split("+")[1]))
            else:
                plant_file(path)
            rc, so, se, rep, _ = b.run(*args, timeout=120)
            if blocks:
                reasons = assert_blocked(tag, b, work, before, rc, rep)
                if kind == "earlier":
                    ok(tag + ".marker_kept", os.path.isfile(path))
                    ok(tag + ".attributed", "write-interrupted-earlier:fast-forward" in reasons, reasons)
                elif kind == "fifo":
                    ok(tag + ".named", "in-progress:write-marker-path-not-a-file:fifo" in reasons, reasons)
                    ok(tag + ".untouched", kind_now(path) == "fifo", kind_now(path))
                else:
                    want = "in-progress:" + ("common:" if where == "common" else "") + main_name
                    ok(tag + ".named", want in reasons, reasons)
            else:
                assert_moved(tag, b, work, rc, se, "feature/x")
                ok(tag + ".golden_false_untouched", kind_now(path) == ("fifo" if kind == "fifo" else "regular"),
                   kind_now(path))
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


HOLDER = ("import fcntl, os, sys\nfd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)\n"
          "fcntl.flock(fd, fcntl.LOCK_EX)\nsys.stdout.write('held\\n')\nsys.stdout.flush()\nsys.stdin.read()\n")


def c_run_lock_common(box):
    """RV9-1, the run lock: one run per repository, keyed by the COMMON dir (RV4-11), so a run over the main
    worktree and a run over a linked worktree of the same repository exclude each other. Fixture: a holder process
    (started here, ended here) flocks <common>/helix-sync-upstreams.lock; a run rooted at the linked worktree exits
    7 (LOCKED) and changes nothing. Golden-FALSE: the same file name held in the linked worktree's OWN git dir is
    not the run lock: the run proceeds (exit 0, moved)."""
    for where, locked in (("common", True), ("own", False)):
        tag = "run_lock.%s" % where
        b = Box("rl_%s" % where)
        p = None
        try:
            work, gd, common, args = branch_tree(b, "wt", "dev", "rl")
            path = os.path.join(common if where == "common" else gd, "helix-sync-upstreams.lock")
            before = b.git(work, "rev-parse", "HEAD")
            p = subprocess.Popen([PY, "-I", "-c", HOLDER, path], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 text=True)
            ok(tag + ".holder_ready", p.stdout.readline().strip() == "held")
            rc, so, se, rep, _ = b.run(*args, timeout=120)
            if locked:
                ok(tag + ".exit_7", rc == 7, "rc=%s %s" % (rc, se[-300:]))
                ok(tag + ".not_moved", b.git(work, "rev-parse", "HEAD") == before)
            else:
                assert_moved(tag, b, work, rc, se, "dev")
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            if p is not None:
                p.stdin.close()  # the holder (our own child) ends when its stdin closes
                p.wait(timeout=30)
            b.cleanup()


def nth_call(log, sub, repo):
    """How many calls of ``sub`` in ``repo`` the engine made, from the race shim's call log."""
    n = 0
    for line in open(log, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 2 and f[0] == sub and f[1] == os.path.realpath(repo):
            n += 1
    return n


def c_write_time_lock_race(box):
    """RV9-1 + RV9-4 (reviewer mutants Z04, Z07, the site of begin_write). A lock git takes for the write appears
    AFTER inspection (fixture: the race shim, another git process): (a) at the fetch, so the write-time step-1
    re-check must name it: the action reason is exactly 'blocked:tree-changed-before-write'; (b) at the LAST read
    before the write (step 4's symbolic-ref, after step 1 passed), so begin_write's own re-check must catch it: the
    action reason is exactly 'blocked:in-progress:<label>'. Plain clone on 'dev' and linked worktree on 'feature/x'
    (the branch ref lock, a common-dir lock and, in the worktree, its own HEAD.lock). Either way: exit 4, nothing
    moved, tree clean. Without the lock (control) the same run fast-forwards."""
    cases = [("plain", "dev", "common", "refs/heads/dev.lock"), ("wt", "feature/x", "common", "refs/heads/feature/x.lock"),
             ("wt", "feature/x", "common", "packed-refs.lock"), ("wt", "feature/x", "own", "HEAD.lock"),
             ("plain", "dev", "own", "index.lock")]
    for i, (layout, br, where, name) in enumerate(cases):
        # the number of symbolic-ref calls before the write, measured on a control run of the same tree
        b = Box("wtr_ctl_%d" % i)
        nsym = None
        try:
            work, gd, common, args = branch_tree(b, layout, br, "wtr")
            log = b.p("calls.log")
            rc, so, se, rep, _ = b.run(*args, path_prefix=b.shim(), env={"SXR_GIT": GIT, "SXR_LOG": log}, timeout=300)
            assert_moved("write_race.%d.control" % i, b, work, rc, se, br)
            nsym = nth_call(log, "symbolic-ref", work) - 1  # the last one is step 6's verify, after the write
            ok("write_race.%d.control_calls" % i, nsym >= 2, nsym)
        except Exception as e:
            ok("write_race.%d.control.fixture" % i, False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()
        if not nsym:
            continue
        for at in ("fetch", "last-read"):
            tag = "write_race.%s.%s.%s.%s.%s" % (layout, br.replace("/", "_"), where, name.replace("/", "_"), at)
            b = Box("wtr_%d_%s" % (i, at))
            try:
                work, gd, common, args = branch_tree(b, layout, br, "wtr")
                lk = os.path.join(common if where == "common" else gd, name)
                before = b.git(work, "rev-parse", "HEAD")
                sub, nth = ("fetch", 1) if at == "fetch" else ("symbolic-ref", nsym)
                env = race_env(b, "plant", "%s@%s" % (sub, work), work, SXR_PLANT=lk, SXR_NTH=str(nth))
                rc, so, se, rep, _ = b.run(*args, path_prefix=b.shim(), env=env, timeout=300)
                ok(tag + ".fired", os.path.exists(b.p("mark")) and os.path.isfile(lk))
                assert_blocked(tag, b, work, before, rc, rep, lk)
                label = label_of(layout, name) if where == "common" else name
                want = "blocked:tree-changed-before-write" if at == "fetch" else "blocked:in-progress:" + label
                whys = [str(a.get("why")) for x in (rep or {}).get("repos", []) for a in (x.get("actions") or [])]
                ok(tag + ".reason", want in whys, whys)
            except Exception as e:
                ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
            finally:
                b.cleanup()


def c_marker_read_status_class(box):
    """RV9-2 (reviewer mutant Z11), the class "every status the marker read can return": a marker larger than the
    read cap (5 kB of valid JSON) and a marker that cannot be read (mode 0000) are an earlier write of an UNKNOWN
    op, never "no marker": --check notes 'write-marker-present:unknown-left-nothing' on a clean tree and predicts
    nothing it would not do; --apply (the tree is clean, nothing else is in progress) clears it as
    'write-marker-cleared:unknown-left-nothing' and fast-forwards (exit 0). Control: invalid JSON reads the same."""
    big = json.loads(EARLIER.decode())
    big["pad"] = "x" * 5000
    for kind in ("too_large", "unreadable", "invalid_json"):
        for mode in ("--check", "--apply"):
            tag = "marker_read.%s.%s" % (kind, mode[2:])
            b = Box("mr_%s_%s" % (kind, mode[2:]))
            try:
                r_url, r_seed = b.bare("HelixDevelopment", "mr")
                work = b.clone(r_url, "mr")
                b.commit(r_seed, "upstream moves")
                mp = os.path.join(work, ".git", MARKER)
                plant_file(mp, json.dumps(big).encode() if kind == "too_large" else
                           b"{not json" if kind == "invalid_json" else EARLIER)
                if kind == "unreadable":
                    os.chmod(mp, 0)
                ok(tag + ".fixture_size", kind != "too_large" or os.path.getsize(mp) > 4096)
                rc, so, se, rep, _ = b.run(mode, "--root", work, "--quiet", timeout=300)
                notes = all_notes(rep)
                if mode == "--check":
                    ok(tag + ".exit_3", rc == 3, "rc=%s %s" % (rc, se[-300:]))
                    ok(tag + ".noted_unknown", "write-marker-present:unknown-left-nothing" in notes, notes)
                    ok(tag + ".marker_untouched", os.path.lexists(mp))
                else:
                    ok(tag + ".exit_0", rc == 0, "rc=%s %s" % (rc, se[-300:]))
                    ok(tag + ".cleared_noted", "write-marker-cleared:unknown-left-nothing" in notes, notes)
                    ok(tag + ".marker_removed", not os.path.lexists(mp))
                    ok(tag + ".moved", b.git(work, "rev-parse", "HEAD") == b.git(work, "rev-parse", "origin/main"))
            except Exception as e:
                ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
            finally:
                b.cleanup()


def c_work_tree_only_half_write(box):
    """RV9-6, the STATED LIMIT, pinned live (review round 10 tried a 'git status must stay empty' check and withdrew
    it: the autostash race, a user's edit between step 1 and the write, would then be blamed on the write). A write
    git ANSWERS with a failure that left HEAD and the index unchanged but changed the WORK TREE (fixture model: the
    write leaves an untracked file, then git refuses at a held index.lock / ORIG_HEAD.lock) is read as settled: the
    marker is removed and the run is FAILED (exit 1). Nothing is lost: the file stays, and the next run reports the
    tree dirty. Golden-FALSE: the same refusal with no work-tree change, identical outcome. When the follow-up
    (content compared with the target tree) lands, the 'worktree_changed' rows flip to marker_kept."""
    for i, (rel, wt) in enumerate((("index.lock", True), ("ORIG_HEAD.lock", True), ("index.lock", False))):
        tag = "wt_only.%s.%s" % (rel.replace(".", "_"), "worktree_changed_known_limit" if wt else "golden_false")
        b = Box("wto_%d" % i)
        try:
            work, repo_dir, gd, args = site_tree(b, "ff")
            rc, so, se, drv, rep = inproc(b, "lockspawn:%s:ff%s" % (rel, ":wt" if wt else ""),
                                          *(args + ["--root", work, "--quiet"]))
            st = b.git(repo_dir, "status", "--porcelain=v1", "--untracked-files=normal")
            ok(tag + ".fixture_effect", st == ("?? stray_by_write.txt" if wt else ""), repr(st))
            ok(tag + ".head_not_moved", b.git(repo_dir, "rev-parse", "HEAD") != b.git(repo_dir, "rev-parse",
                                                                                         "origin/main"))
            whys = [str(a.get("why")) for x in (rep or {}).get("repos", []) for a in (x.get("actions") or [])]
            ok(tag + ".marker_removed", not os.path.lexists(os.path.join(gd, MARKER)))
            ok(tag + ".not_reported_left_changes", not [w for w in whys if "write-left-changes" in w], whys)
            ok(tag + ".exit_failed", rc == 1, "rc=%s %s" % (rc, se[-300:]))
            if wt:
                rc2, so2, se2, rep2, _ = b.run("--check", "--no-fetch", "--root", work, "--quiet", timeout=300)
                reasons = [y for x in (rep2 or {}).get("repos", []) for y in (x.get("reasons") or [])]
                ok(tag + ".next_run_sees_dirty", any("dirty" in y for y in reasons), reasons)
                ok(tag + ".file_kept", os.path.isfile(os.path.join(repo_dir, "stray_by_write.txt")))
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


# ───────────────────────── review round 11 (RV10-1 .. RV10-7) ─────────────────────────
# RV10-1, the SOURCE of the branch parameter: 'git symbolic-ref --short HEAD' DISAMBIGUATES. With a tag or a
# remote named like the checked-out branch it answers 'heads/dev', and round 10 put that string into the branch-lock
# path (refs/heads/heads/dev.lock). The engine now reads the FULL ref and strips refs/heads/. Each fixture below
# first PROVES its precondition (that --short really answers the disambiguated name), so a check that passes here
# is a check that ran on the shape that broke round 10, never on an approximation (section 11.4.199).

def branch_shape_tree(box, layout, shape, name):
    """A root on branch 'dev' (or the shape's own branch) one commit behind its upstream, plus the shape:
    'tag'    a tag 'dev' beside branch dev;
    'remote' a second remote NAMED 'dev' (same upstream) with refs/remotes/dev/HEAD (measured, git 2.53: this does NOT
             make --short ambiguous, it still answers 'dev'; kept as a same-named-remote case, the engine must work);
    'toplevel_ref' a ref refs/dev beside branch dev (measured: --short answers 'heads/dev', like a tag);
    'heads_dev_upstream' (the reviewer's probe) tag 'dev' beside branch dev, and the upstream has a branch named
             'heads/dev' that is ahead; the run asks for --branch heads/dev;
    'literal' the checked-out branch is LITERALLY 'heads/dev' (refs/heads/heads/dev), tracking origin/heads/dev;
    'case'   branches 'dev' and 'Dev' both exist; the root is on 'Dev'.
    Returns (work, gitdir, common, branch the root is on, --branch value, label of that branch's ref lock)."""
    br = {"literal": "heads/dev", "case": "Dev"}.get(shape, "dev")
    r_url, r_seed = box.bare("HelixDevelopment", name)
    box.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/" + br)
    if shape == "case":
        box.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/dev")
    clone = box.clone(r_url, "c_" + name)
    if layout == "plain":
        box.git(clone, "checkout", "-q", "-b", br, "--track", "origin/" + br)
        work = clone
    else:
        box.git(clone, "checkout", "-q", "-b", "side")
        work = box.p("work", "lw_" + name)
        box.git(clone, "worktree", "add", "-q", "--track", "-b", br, work, "origin/" + br)
    if shape == "case":
        box.git(work, "branch", "-q", "dev", "origin/dev")
    if shape in ("tag", "heads_dev_upstream"):
        box.git(work, "tag", "dev")
    if shape == "toplevel_ref":
        box.git(work, "update-ref", "refs/dev", "HEAD")
    if shape == "remote":
        box.git(work, "remote", "add", "dev", r_url)
        box.git(work, "fetch", "-q", "dev")
        box.git(work, "remote", "set-head", "dev", "main")
    box.commit(r_seed, "upstream moves")
    box.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/" + br)
    want = br
    if shape == "heads_dev_upstream":
        box.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/heads/dev")
        want = "heads/dev"
    gd = box.git(work, "rev-parse", "--absolute-git-dir")
    common = box.git(work, "rev-parse", "--path-format=absolute", "--git-common-dir")
    full = box.git(work, "symbolic-ref", "-q", "HEAD")
    short = box.git(work, "symbolic-ref", "--short", "-q", "HEAD")
    if full != "refs/heads/" + br:
        raise RuntimeError("fixture not on %s: %s" % (br, full))
    # the precondition of round 10's defect, proved on the fixture itself: --short is ambiguous here
    expect_short = {"tag": "heads/dev", "toplevel_ref": "heads/dev", "heads_dev_upstream": "heads/dev"}.get(shape, br)
    if short != expect_short:
        raise RuntimeError("fixture precondition: --short answered %r, expected %r" % (short, expect_short))
    lock = "refs/heads/%s.lock" % br
    return work, gd, common, br, want, label_of(layout, lock)


def c_branch_name_shapes(box):
    """RV10-1 / RV10-2: a branch with a same-named TAG, a same-named top-level ref (refs/dev), a same-named REMOTE, the reviewer's 'heads/dev'
    upstream branch, a branch LITERALLY named heads/dev, and two branches that differ only in CASE; a plain clone
    and a linked worktree. (a) A stale ref lock of the CHECKED-OUT branch blocks: exit 4, reason in-progress:<label>,
    no write, a clean tree, the lock untouched. (b) Golden-FALSE: the same tree without that lock (or with the lock
    of the OTHER name: refs/heads/dev.lock while on Dev or on heads/dev) fast-forwards, exit 0. The reviewer's shape
    asks for --branch heads/dev while the root is on dev: never that branch, so exit 4 root-not-on-heads/dev, no
    write, with and without the stale refs/heads/dev.lock (round 10 left 'M  f' there)."""
    for layout in ("plain", "wt"):
        for shape in ("tag", "toplevel_ref", "remote", "heads_dev_upstream", "literal", "case"):
            for variant in ("own_lock", "no_lock", "other_lock"):
                if variant == "other_lock" and shape not in ("literal", "case"):
                    continue
                tag = "branch_shape.%s.%s.%s" % (layout, shape, variant)
                b = Box("bs_%s_%s_%s" % (layout, shape, variant))
                try:
                    work, gd, common, br, want, label = branch_shape_tree(b, layout, shape, "bs")
                    before = b.git(work, "rev-parse", "HEAD")
                    lk = None
                    if variant == "own_lock":
                        lk = os.path.join(common, "refs", "heads", *(br + ".lock").split("/"))
                    elif variant == "other_lock":
                        lk = os.path.join(common, "refs", "heads", "dev.lock")
                    if lk:
                        plant_file(lk)
                    rc, so, se, rep, _ = b.run("--apply", "--branch", want, "--root", work, "--quiet", timeout=300)
                    if shape == "heads_dev_upstream":
                        assert_blocked(tag, b, work, before, rc, rep, lk, "root-not-on-heads/dev")
                    elif variant == "own_lock":
                        assert_blocked(tag, b, work, before, rc, rep, lk, "in-progress:" + label)
                    else:
                        assert_moved(tag, b, work, rc, se, br)
                        ok(tag + ".still_on_branch", b.git(work, "symbolic-ref", "-q", "HEAD") == "refs/heads/" + br)
                        if lk:
                            ok(tag + ".golden_false_lock_untouched", os.path.isfile(lk))
                    names = [x.get("branch") for x in (rep or {}).get("repos", []) if x.get("kind") == "root"]
                    ok(tag + ".branch_recorded_exactly", names == [br], names)
                except Exception as e:
                    ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
                finally:
                    b.cleanup()


def c_branch_param_shapes(box):
    """RV10-1 class, the other source of the branch: --branch. A value git would refuse as a branch name (a
    trailing '/', '.lock', '..', a '.' component, 'HEAD', '//', a leading '-', '@{') and a non-ASCII value are a
    usage error (exit 2) BEFORE any git call: no fetch, no write. Golden-FALSE: 'origin/dev', a valid branch name,
    is accepted and gives the normal answer for a root on main (attention root-not-on-origin/dev, exit 4). A root
    checked out on a NON-ASCII branch (cafe with an accent) is reported root-not-on-main with no write."""
    b = Box("bp")
    try:
        r_url, r_seed = b.bare("HelixDevelopment", "bp")
        work = b.clone(r_url, "bp")
        b.commit(r_seed, "upstream moves")
        for i, val in enumerate(("dev/", "dev.lock", "dev..x", "dev/.x", "HEAD", "dev//x", "-dev", "dev@{1}",
                                 "café", "dev\nx")):
            tag = "branch_param.bad_%d" % i
            refs0 = b.git(work, "for-each-ref", "--format=%(objectname) %(refname)")
            rc, so, se, rep, _ = b.run("--apply", "--branch=" + val, "--root", work, "--quiet", timeout=120)
            ok(tag + ".exit_2", rc == 2, "%r rc=%s %s" % (val, rc, se[-200:]))
            ok(tag + ".nothing_fetched", b.git(work, "for-each-ref", "--format=%(objectname) %(refname)") == refs0, val)
            ok(tag + ".no_report", rep is None, val)
        rc, so, se, rep, _ = b.run("--check", "--no-fetch", "--branch", "origin/dev", "--root", work, "--quiet",
                                   timeout=120)
        reasons = [y for x in (rep or {}).get("repos", []) for y in (x.get("reasons") or [])]
        ok("branch_param.golden_false.exit_4", rc == 4, "rc=%s" % rc)
        ok("branch_param.golden_false.reason", "root-not-on-origin/dev" in reasons, reasons)
    except Exception as e:
        ok("branch_param.fixture", False, "%s: %s" % (type(e).__name__, e))
    finally:
        b.cleanup()
    b = Box("bpu")
    try:
        r_url, r_seed = b.bare("HelixDevelopment", "bpu")
        work = b.clone(r_url, "bpu")
        b.git(work, "checkout", "-q", "-b", "café")
        b.commit(r_seed, "upstream moves")
        before = b.git(work, "rev-parse", "HEAD")
        rc, so, se, rep, _ = b.run("--apply", "--root", work, "--quiet", timeout=300)
        reasons = [y for x in (rep or {}).get("repos", []) for y in (x.get("reasons") or [])]
        ok("branch_param.unicode_root.exit_4", rc == 4, "rc=%s %s" % (rc, se[-200:]))
        ok("branch_param.unicode_root.reason", "root-not-on-main" in reasons, reasons)
        ok("branch_param.unicode_root.not_moved", b.git(work, "rev-parse", "HEAD") == before)
        ok("branch_param.unicode_root.branch_recorded",
           [x.get("branch") for x in rep["repos"] if x.get("kind") == "root"] == ["café"])
    except Exception as e:
        ok("branch_param.unicode_root.fixture", False, "%s: %s" % (type(e).__name__, e))
    finally:
        b.cleanup()


def c_marker_foreign_op(box):
    """RV10-7 (reviewer mutant AA10): a marker that is valid JSON but whose op is OUTSIDE the closed vocabulary (a
    tab, a newline and a fake report line in it) is an earlier write of an UNKNOWN op: --check notes exactly
    'write-marker-present:unknown-left-nothing', and no note, reason or terminal line carries the planted text.
    Golden-FALSE: a marker with the known op fast-forward is attributed to fast-forward."""
    planted = "fast-forward\tCURRENT\n[sync-upstreams] . current -"
    for kind, op in (("foreign", planted), ("known", "fast-forward")):
        tag = "marker_foreign.%s" % kind
        b = Box("mf_" + kind)
        try:
            r_url, r_seed = b.bare("HelixDevelopment", "mf")
            work = b.clone(r_url, "mf")
            b.commit(r_seed, "upstream moves")
            m = json.loads(EARLIER.decode())
            m["op"] = op
            plant_file(os.path.join(work, ".git", MARKER), json.dumps(m).encode())
            rc, so, se, rep, _ = b.run("--check", "--root", work, timeout=300)
            notes = all_notes(rep)
            want = "unknown" if kind == "foreign" else "fast-forward"
            ok(tag + ".exit_3", rc == 3, "rc=%s %s" % (rc, se[-200:]))
            ok(tag + ".noted", "write-marker-present:%s-left-nothing" % want in notes, notes)
            text = json.dumps(rep) + so + se
            ok(tag + ".planted_text_absent", "CURRENT\\n[sync" not in text and "[sync-upstreams] . current -" not in so,
               so[-300:])
            ok(tag + ".notes_one_line", all("\t" not in n and "\n" not in n for n in notes), notes)
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


# ───────────── review round 12: ref resolution is exact, object visibility is real history ─────────────
def reasons_of(rep):
    return [y for x in (rep or {}).get("repos", []) for y in (x.get("reasons") or [])]


def dwim_tree(b, shape, name):
    """A root on branch 'dev' whose remote has NO dev any more (deleted upstream, the remote-tracking ref removed),
    and a LOCAL ref literally named refs/remotes/origin/dev under refs/tags/ ('tag') or refs/heads/ ('branch') that
    points at a local commit ahead of dev. git's name lookup ('rev-parse refs/remotes/origin/dev', the rules of
    git-rev-parse(1) 'SPECIFYING REVISIONS') falls back to refs/tags/<name> and refs/heads/<name> when the exact ref is
    absent. Returns (work, before, planted_sha)."""
    r_url, r_seed = b.bare("HelixDevelopment", name)
    b.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/dev")
    work = b.clone(r_url, "c_" + name)
    b.git(work, "checkout", "-q", "-b", "dev", "--track", "origin/dev")
    b.git(r_seed, "push", "-q", "origin", ":refs/heads/dev")
    b.git(work, "update-ref", "-d", "refs/remotes/origin/dev")
    before = b.git(work, "rev-parse", "HEAD")
    b.git(work, "checkout", "-q", "-b", "tmpx")
    with open(os.path.join(work, "LOCAL"), "w") as f:
        f.write("local only\n")
    b.git(work, "add", "LOCAL")
    b.git(work, "commit", "-q", "-m", "local only")
    planted = b.git(work, "rev-parse", "HEAD")
    b.git(work, "checkout", "-q", "dev")
    b.git(work, "branch", "-q", "-D", "tmpx")
    if shape == "tag":
        b.git(work, "tag", "refs/remotes/origin/dev", planted)
    else:
        b.git(work, "branch", "-q", "refs/remotes/origin/dev", planted)
    return work, before, planted


def c_ref_resolution_exact(box):
    """RV11-1 (round-11 reviewer, logs/probes_r11_dwim.txt): the upstream of <remote>/<branch> is the EXACT ref
    refs/remotes/<remote>/<branch>, never what git's name lookup falls back to. A local tag or branch named
    refs/remotes/origin/dev, with the exact ref absent, is NOT the upstream: no move in any mode, the repository
    has no upstream dev (exit 4, reason no-upstream-dev). r11: --apply --no-fetch fast-forwarded dev to the local
    commit (rc 0 'updated'); --check / --dry-run said 'behind' (rc 3). Golden-FALSE (section 11.4.201(1)): with the
    exact remote-tracking ref present AND a planted tag of the same name at a local commit, the engine moves to the
    remote's commit, never to the planted one."""
    for shape in ("tag", "branch"):
        for mode in (["--apply", "--no-fetch"], ["--check", "--no-fetch"], ["--dry-run"]):
            tag = "ref_exact.%s.%s" % (shape, mode[0].lstrip("-"))
            b = Box("rx_%s_%s" % (shape, mode[0].lstrip("-")))
            try:
                work, before, planted = dwim_tree(b, shape, "rx")
                rc, so, se, rep, _ = b.run(*(mode + ["--branch", "dev", "--root", work, "--quiet"]), timeout=300)
                head = b.git(work, "rev-parse", "HEAD")
                ok(tag + ".not_moved", head == before, "head %s planted %s" % (head, planted))
                ok(tag + ".never_the_planted_ref", head != planted)
                ok(tag + ".exit_4", rc == 4, "rc=%s %s" % (rc, se[-200:]))
                ok(tag + ".reason", "no-upstream-dev" in reasons_of(rep), reasons_of(rep))
                ok(tag + ".still_on_dev", b.git(work, "symbolic-ref", "-q", "HEAD") == "refs/heads/dev")
            except Exception as e:
                ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
            finally:
                b.cleanup()
    tag = "ref_exact.golden_false"
    b = Box("rx_gf")
    try:
        work, gd, common, args = branch_tree(b, "plain", "dev", name="rxgf")
        b.git(work, "fetch", "-q", "origin")
        want = b.git(work, "rev-parse", "refs/remotes/origin/dev")
        b.git(work, "checkout", "-q", "-b", "tmpx")
        with open(os.path.join(work, "LOCAL"), "w") as f:
            f.write("local only\n")
        b.git(work, "add", "LOCAL")
        b.git(work, "commit", "-q", "-m", "local only")
        planted = b.git(work, "rev-parse", "HEAD")
        b.git(work, "checkout", "-q", "dev")
        b.git(work, "branch", "-q", "-D", "tmpx")
        b.git(work, "tag", "refs/remotes/origin/dev", planted)
        rc, so, se, rep, _ = b.run("--apply", "--no-fetch", "--branch", "dev", "--root", work, "--quiet", timeout=300)
        ok(tag + ".exit_0", rc == 0, "rc=%s %s" % (rc, se[-300:]))
        ok(tag + ".moved_to_remote", b.git(work, "rev-parse", "HEAD") == want)
    except Exception as e:
        ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
    finally:
        b.cleanup()


def c_checkout_target_exact(box):
    """Round 12 (found by the class enumeration of the ref-resolution class, section 11.4.276(C)): the pin write
    'git checkout --detach <sha>' takes a LOCAL BRANCH whose name is that 40-hex string before the object (measured,
    git 2.53: HEAD became the branch's commit). A submodule with a branch named exactly the target gitlink, pointing
    at the old pin, must still end DETACHED at the target with --advance-pins (exit 0, the parent index staged at the
    target). r11: the checkout attached HEAD to the branch, the pin did not move to the target."""
    tag = "checkout_exact"
    try:
        work, s1, s2, r1 = pin_behind_tree(box)
        sub = os.path.realpath(os.path.join(work, "libs/a"))
        box.git(sub, "fetch", "-q", "origin")
        box.git(sub, "branch", "-q", s2, s1)  # a branch NAMED the target's object id, pointing at the old pin
        rc, so, se, rep, _ = box.run("--apply", "--advance-pins", "--root", work, "--quiet", timeout=300)
        head = box.git(sub, "rev-parse", "HEAD")
        sym = box.git(sub, "symbolic-ref", "-q", "HEAD", check=False)
        staged = box.git(work, "ls-files", "-s", "libs/a").split()[1]
        ok(tag + ".exit_0", rc == 0, "rc=%s %s" % (rc, se[-300:]))
        ok(tag + ".at_target", head == s2, "head %s s1 %s s2 %s" % (head, s1, s2))
        ok(tag + ".detached", sym == "", repr(sym))
        ok(tag + ".staged_target", staged == s2, "staged %s" % staged)
        ok(tag + ".hex_branch_untouched", box.git(sub, "rev-parse", "refs/heads/" + s2) == s1)
    except Exception as e:
        ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))


def engine_py():
    return os.path.join(os.path.dirname(os.path.abspath(ENGINE)), "sync_all_upstreams.py")


def c_object_visibility(box):
    """RV11-2 (round-11 reviewer, logs/probe_noreplace.txt, probe_replace.txt, probe_graft.txt): ancestry is read
    on the REAL history. A local commit L and a fetched upstream U that diverged stay diverged when a replace ref
    ('git replace --graft U L') or a graft ('<git dir>/info/grafts', or GIT_GRAFT_FILE) pretends that L is U's
    parent: no write, exit 4, reason local-diverged, L still on the branch. Shapes: replace ref with no variable;
    replace ref with the user's GIT_NO_REPLACE_OBJECTS=1 given to the ENGINE itself (python3 -I on the .py, the way
    the reviewer ran it; the wrapper unsets the variable before the engine starts); replace ref plus the repository
    config core.useReplaceRefs=true; info/grafts; GIT_GRAFT_FILE (engine run directly). r10 honoured replace refs and
    grafts; r11 also dropped the user's GIT_NO_REPLACE_OBJECTS=1 and fast-forwarded off L in every shape.
    Golden-FALSE: an unrelated replace ref (one blob for another) on an ordinary behind tree does not stop the
    fast-forward."""
    for shape in ("replace", "replace_env_noreplace", "replace_config_on", "info_grafts", "graft_file_env"):
        tag = "objvis." + shape
        b = Box("ov_" + shape)
        try:
            work, gd, common, args = branch_tree(b, "plain", "dev", name="ov")
            with open(os.path.join(work, "LOCAL"), "w") as f:
                f.write("local only\n")
            b.git(work, "add", "LOCAL")
            b.git(work, "commit", "-q", "-m", "local only L")
            L = b.git(work, "rev-parse", "HEAD")
            b.git(work, "fetch", "-q", "origin")
            U = b.git(work, "rev-parse", "refs/remotes/origin/dev")
            env, direct = None, False
            if shape.startswith("replace"):
                b.git(work, "replace", "--graft", U, L)
            if shape == "replace_env_noreplace":
                env, direct = {"GIT_NO_REPLACE_OBJECTS": "1"}, True
            if shape == "replace_config_on":
                b.git(work, "config", "core.useReplaceRefs", "true")
            if shape == "info_grafts":
                os.makedirs(os.path.join(gd, "info"), exist_ok=True)
                with open(os.path.join(gd, "info", "grafts"), "w") as f:
                    f.write("%s %s\n" % (U, L))
            if shape == "graft_file_env":
                gf = b.p("grafts")
                with open(gf, "w") as f:
                    f.write("%s %s\n" % (U, L))
                env, direct = {"GIT_GRAFT_FILE": gf}, True
            if direct:
                argv, o = b.engine_argv(*args)
                argv = [PY, "-I", engine_py()] + argv[2:] + ["--out", o]
                e = dict(b.env)
                e.update(env)
                r = subprocess.run(argv, env=e, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300)
                rc, se = r.returncode, r.stderr
                try:
                    with open(os.path.join(o, "sync_report.json"), encoding="utf-8") as f:
                        rep = json.load(f)
                except (OSError, ValueError):
                    rep = None
            else:
                rc, so, se, rep, _ = b.run(*args, timeout=300)
            head = b.git(work, "rev-parse", "HEAD")
            real = subprocess.run([GIT, "--no-replace-objects", "-C", work, "merge-base", "--is-ancestor", L, "HEAD"],
                                  env=dict(b.env, GIT_GRAFT_FILE="/dev/null"), stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL).returncode
            ok(tag + ".not_moved", head == L, "head %s L %s U %s" % (head, L, U))
            ok(tag + ".local_commit_kept", real == 0, "merge-base rc %s" % real)
            ok(tag + ".exit_4", rc == 4, "rc=%s %s" % (rc, se[-300:]))
            ok(tag + ".reason", "local-diverged" in reasons_of(rep), reasons_of(rep))
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()
    tag = "objvis.golden_false"
    b = Box("ov_gf")
    try:
        work, gd, common, args = branch_tree(b, "plain", "dev", name="ovgf")
        p1, p2 = b.p("blob1"), b.p("blob2")
        with open(p1, "w") as f:
            f.write("one\n")
        with open(p2, "w") as f:
            f.write("two\n")
        h1 = b.git(work, "hash-object", "-w", p1)
        h2 = b.git(work, "hash-object", "-w", p2)
        b.git(work, "replace", h1, h2)
        rc, so, se, rep, _ = b.run(*args, timeout=300)
        assert_moved(tag, b, work, rc, se, "dev")
    except Exception as e:
        ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
    finally:
        b.cleanup()


# ───────── review round 13: ref names git does not take literally, paths git reads as patterns ─────────
def symref_tree(b, kind, name):
    """A root on dev, origin/dev at A (fetched), and a local-only commit X on refs/heads/evil. Then the remote-tracking
    ref refs/remotes/origin/dev is made a SYMBOLIC ref: to refs/heads/evil ('branch'), to a tag at X ('tag'), or to
    another remote's ref refs/remotes/other/dev at X ('other'). for-each-ref prints the exact refname for it but the
    value is the target's (measured, git 2.53, ground_truth/gt_raw_git.txt). Returns (work, before, x)."""
    r_url, r_seed = b.bare("HelixDevelopment", name)
    b.git(r_seed, "push", "-q", "origin", "HEAD:refs/heads/dev")
    work = b.clone(r_url, "c_" + name)
    b.git(work, "checkout", "-q", "-b", "dev", "--track", "origin/dev")
    before = b.git(work, "rev-parse", "HEAD")
    b.git(work, "checkout", "-q", "-b", "evil")
    with open(os.path.join(work, "LOCAL"), "w") as f:
        f.write("local only\n")
    b.git(work, "add", "LOCAL")
    b.git(work, "commit", "-q", "-m", "local only X")
    x = b.git(work, "rev-parse", "HEAD")
    b.git(work, "checkout", "-q", "dev")
    if kind == "branch":
        b.git(work, "symbolic-ref", "refs/remotes/origin/dev", "refs/heads/evil")
    elif kind == "tag":
        b.git(work, "tag", "t-evil", x)
        b.git(work, "symbolic-ref", "refs/remotes/origin/dev", "refs/tags/t-evil")
    else:
        b.git(work, "update-ref", "refs/remotes/other/dev", x)
        b.git(work, "symbolic-ref", "refs/remotes/origin/dev", "refs/remotes/other/dev")
    return work, before, x


def c_symbolic_tracking_ref(box):
    """RV12-1 (round-12 reviewer, probes/p_symref.py): a SYMBOLIC ref at the exact name refs/remotes/<r>/<b> is not
    the upstream. Its value is whatever it points at (a local branch, a tag, another remote's ref), so the remote has
    no readable <b>: nothing moves, exit 4, reasons symbolic-tracking-ref:origin and no-upstream-dev, in every mode.
    r12: --apply --no-fetch fast-forwarded dev to the local commit X (rc 0), --check / --dry-run said 'behind'
    (rc 3). Golden-FALSE (section 11.4.201(1)): every clone carries the symbolic ref refs/remotes/origin/HEAD; an
    ordinary behind tree with it still fast-forwards (exit 0)."""
    for kind in ("branch", "tag", "other"):
        for mode in (["--apply", "--no-fetch"], ["--check", "--no-fetch"], ["--dry-run"], ["--apply"]):
            m = "_".join(x.lstrip("-") for x in mode)
            tag = "symref.%s.%s" % (kind, m)
            b = Box("sy_%s_%s" % (kind, m))
            try:
                work, before, x = symref_tree(b, kind, "sy")
                rc, so, se, rep, _ = b.run(*(mode + ["--branch", "dev", "--root", work, "--quiet"]), timeout=300)
                head = b.git(work, "rev-parse", "HEAD")
                rs = reasons_of(rep)
                ok(tag + ".not_moved", head == before, "head %s x %s" % (head, x))
                ok(tag + ".never_the_target", head != x)
                if mode == ["--apply"]:
                    # the fetch rewrites the ref as a plain remote-tracking ref of the real remote (which has dev at
                    # A = the local dev): the honest outcome is 'current', exit 0, still never X
                    ok(tag + ".exit_0_or_4", rc in (0, 4), "rc=%s %s %s" % (rc, rs, se[-200:]))
                else:
                    ok(tag + ".exit_4", rc == 4, "rc=%s %s" % (rc, se[-200:]))
                    ok(tag + ".reason_symbolic", "symbolic-tracking-ref:origin" in rs, rs)
                    ok(tag + ".reason_no_upstream", "no-upstream-dev" in rs, rs)
            except Exception as e:
                ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
            finally:
                b.cleanup()
    tag = "symref.golden_false"
    b = Box("sy_gf")
    try:
        work, gd, common, args = branch_tree(b, "plain", "dev", name="sygf")
        b.git(work, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/dev", check=False)
        ok(tag + ".origin_head_is_symbolic",
           b.git(work, "symbolic-ref", "-q", "refs/remotes/origin/HEAD", check=False) != "")
        rc, so, se, rep, _ = b.run(*args, timeout=300)
        assert_moved(tag, b, work, rc, se, "dev")
    except Exception as e:
        ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
    finally:
        b.cleanup()


def pushed_local_pin_tree(b, symref):
    """A parent whose committed AND pushed gitlink for 'sub' is a commit L that exists only in the submodule's local
    branch 'local' (never pushed). With symref, the submodule's refs/remotes/origin/main is a SYMBOLIC ref to
    refs/heads/local, so 'for-each-ref --contains L refs/remotes' lists origin/main. Returns (work, L)."""
    s_url, s_seed = b.bare("HelixDevelopment", "sub")
    r_url, r_seed = b.bare("HelixDevelopment", "par")
    b.add_sub(r_seed, s_url, "sub")
    work = b.clone(r_url, "c_par")
    sp = os.path.join(work, "sub")
    b.git(sp, "checkout", "-q", "-b", "local")
    with open(os.path.join(sp, "LOCAL"), "w") as f:
        f.write("local only\n")
    b.git(sp, "add", "LOCAL")
    b.git(sp, "commit", "-q", "-m", "local only L")
    L = b.git(sp, "rev-parse", "HEAD")
    b.git(work, "add", "--", "sub")
    b.git(work, "commit", "-q", "-m", "pin sub at local-only L")
    b.git(work, "push", "-q", "origin", "HEAD:main")
    if symref:
        b.git(sp, "symbolic-ref", "refs/remotes/origin/main", "refs/heads/local")
    return work, L


def c_pin_symbolic_ref(box):
    """RV12-1, second half (round-12 reviewer, probes/p_pinsym_pushed.py): a gitlink is 'on a remote' only through
    a REAL remote-tracking ref. A symbolic refs/remotes/origin/main that points at a local branch holding the pin
    does not make the pin fetchable: --check --no-fetch reports the pin not-on-any-remote, exit 4. r12: state
    at-main, exit 0 CURRENT. Control (the same tree without the symbolic ref): not-on-any-remote, exit 4 (both
    versions)."""
    for symref in (True, False):
        tag = "pin_symref.%s" % ("symbolic" if symref else "control")
        b = Box("ps_%s" % symref)
        try:
            work, L = pushed_local_pin_tree(b, symref)
            rc, so, se, rep, _ = b.run("--check", "--no-fetch", "--root", work, "--quiet", timeout=300)
            pin = (rec(rep, "sub") or {}).get("pin") or {}
            ok(tag + ".exit_4", rc == 4, "rc=%s %s" % (rc, se[-200:]))
            ok(tag + ".pin_not_on_any_remote", pin.get("state") == "not-on-any-remote", pin)
            ok(tag + ".reason", "pin-not-on-any-remote" in reasons_of(rep), reasons_of(rep))
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def two_sub_tree(b, a_path, b_path, name):
    """A parent with two own-org submodules at the paths a_path and b_path. Then A's upstream moves (the parent's pin
    of A is behind A's main: --advance-pins stages it), and B gets a LOCAL commit on a branch (B's checkout differs
    from its pin; never to be staged). Returns (work, a_new, b_pin, b_local)."""
    a_url, a_seed = b.bare("HelixDevelopment", name + "a")
    s_url, s_seed = b.bare("HelixDevelopment", name + "b")
    r_url, r_seed = b.bare("HelixDevelopment", name + "r")
    b.add_sub(r_seed, a_url, a_path)
    b.add_sub(r_seed, s_url, b_path)
    work = b.clone(r_url, "c_" + name)
    a_new = b.commit(a_seed, "a moves")
    bp = os.path.join(work, b_path)
    b_pin = b.git(bp, "rev-parse", "HEAD")
    b.git(bp, "checkout", "-q", "-B", "main")
    with open(os.path.join(bp, "LOCAL"), "w") as f:
        f.write("local only\n")
    b.git(bp, "add", "LOCAL")
    b.git(bp, "commit", "-q", "-m", "local B")
    return work, a_new, b_pin, b.git(bp, "rev-parse", "HEAD")


def staged(b, work, path):
    for line in b.git(work, "ls-files", "-s", "-z").split("\0"):
        meta, _, p = line.partition("\t")
        if p == path:
            return meta.split()[1]
    return None


def c_pathspec_literal(box):
    """RV12-2 (round-12 reviewer, probes/p_pathspec.py, p_icase_wrap.py, p_magic.py): the stage-pin 'git add --
    <path>' is a PATHSPEC; without GIT_LITERAL_PATHSPECS=1 git matches globs (lib[1] also matches lib1, lib* also
    libB), magic, and the caller's GIT_ICASE_PATHSPECS (lib also matches LIB). Only the advanced pin A is staged;
    B's local commit is never staged. r12: B staged in each shape. Shapes: lib[1]/lib1, lib*/libB, lib/LIB with
    GIT_ICASE_PATHSPECS=1 through the wrapper (the wrapper does not drop it) and given to the engine directly.
    Golden-FALSE: liba/libb (no pattern character), the same result as before the change."""
    for shape, a_path, b_path, env in (("bracket", "lib[1]", "lib1", None), ("star", "lib*", "libB", None),
                                       ("icase_wrapper", "lib", "LIB", {"GIT_ICASE_PATHSPECS": "1"}),
                                       ("icase_direct", "lib", "LIB", {"GIT_ICASE_PATHSPECS": "1"}),
                                       ("golden_false", "liba", "libb", None)):
        tag = "pathspec." + shape
        b = Box("pl_" + shape)
        try:
            work, a_new, b_pin, b_local = two_sub_tree(b, a_path, b_path, "pl")
            args = ["--apply", "--advance-pins", "--root", work, "--quiet"]
            if shape == "icase_direct":
                argv, o = b.engine_argv(*args)
                argv = [PY, "-I", engine_py()] + argv[2:] + ["--out", o]
                r = subprocess.run(argv, env=dict(b.env, **env), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, timeout=300)
                rc, se = r.returncode, r.stderr
            else:
                rc, so, se, rep, _ = b.run(*args, env=env, timeout=300)
            ok(tag + ".a_staged_new", staged(b, work, a_path) == a_new, "a %s want %s" % (staged(b, work, a_path),
                                                                              a_new))
            ok(tag + ".b_not_staged", staged(b, work, b_path) == b_pin,
               "b %s pin %s local %s" % (staged(b, work, b_path), b_pin, b_local))
            ok(tag + ".exit_4", rc == 4, "rc=%s %s" % (rc, se[-200:]))  # B's local-ahead is ATTENTION
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_head_file(box):
    """RV12-3 (round-12 reviewer, probes/p_extra.py head_file): a tracked work-tree FILE named HEAD makes
    'git rev-list --count HEAD' ambiguous (rc 128: 'ambiguous argument'); every rev-list shape ends with '--'.
    r12: exit 6 BLIND (unresolved:rev-list:rc:128) on a current tree. Now: exit 0 CURRENT."""
    tag = "head_file"
    try:
        r_url, r_seed = box.bare("HelixDevelopment", "hf")
        with open(os.path.join(r_seed, "HEAD"), "w") as f:
            f.write("a file named HEAD\n")
        box.git(r_seed, "add", "--", "HEAD")
        box.git(r_seed, "commit", "-q", "-m", "file named HEAD")
        box.git(r_seed, "push", "-q", "origin", "HEAD:main")
        work = box.clone(r_url, "c_hf")
        for mode in (["--check", "--no-fetch"], ["--check"], ["--apply"]):
            rc, so, se, rep, _ = box.run(*(mode + ["--root", work, "--quiet"]), timeout=300)
            m = "_".join(x.lstrip("-") for x in mode)
            ok(tag + "." + m + ".exit_0", rc == 0, "rc=%s %s %s" % (rc, reasons_of(rep), se[-200:]))
            ok(tag + "." + m + ".no_unresolved", not [x for x in reasons_of(rep) if x.startswith("unresolved")],
               reasons_of(rep))
    except Exception as e:
        ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))


def c_stage_pin_verified(box):
    """RV12-2, the generic guard: after the stage-pin add, the parent's index must differ from its state before the
    add in EXACTLY the gitlink. Fixture: the race shim (a user) writes and stages a file in the parent at the
    engine's add. The engine cannot claim it staged only the pin: the action is failed with
    'stage-pin-not-exact:other-entries' naming the other path, a non-zero exit, the user's staged file kept as
    staged. Control: the same tree without the action stages the pin and reports no such reason."""
    for racing in (True, False):
        tag = "stage_verify.%s" % ("race" if racing else "control")
        b = Box("sv_%s" % racing)
        try:
            work, s1, s2, r1 = pin_behind_tree(b)
            env, pre = None, None
            if racing:
                env = race_env(b, "stage-path", "add@" + os.path.realpath(work), work, SXR_FILE="user_staged.txt")
                pre = b.shim()
            rc, so, se, rep, _ = b.run("--apply", "--advance-pins", "--root", work, "--quiet", env=env,
                                       path_prefix=pre, timeout=300)
            rs = reasons_of(rep)
            acts = [a for a in (rec(rep, "libs/a") or {}).get("actions") or [] if a.get("op") == "advance-pin"]
            if racing:
                ok(tag + ".fired", os.path.exists(b.p("mark")))
                ok(tag + ".reason", "stage-pin-not-exact:other-entries" in rs, rs)
                ok(tag + ".why", bool(acts) and acts[-1].get("why") == "stage-pin-not-exact:other-entries", acts)
                ok(tag + ".names_other", bool(acts) and "user_staged.txt" in (acts[-1].get("staged_other") or []),
                   acts)
                ok(tag + ".nonzero", rc != 0, "rc=%s" % rc)
                ok(tag + ".not_applied", (rep or {}).get("verdict") not in (None, "APPLIED"), (rep or {}).get("verdict"))
                ok(tag + ".user_file_still_staged", staged(b, work, "user_staged.txt") is not None)
            else:
                ok(tag + ".exit_0", rc == 0, "rc=%s %s %s" % (rc, rs, se[-200:]))
                ok(tag + ".no_reason", not [x for x in rs if x.startswith("stage-pin-not-exact")], rs)
                ok(tag + ".staged_target", staged(b, work, "libs/a") == s2)
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


def c_stage_pin_pre_index_unread(box):
    """RV12-2 (round 13, mutant AE12): the parent's index read BEFORE the stage-pin add gives no answer. Fixture: the
    race shim plants a harmless file at the child's checkout, and every later 'ls-files' hangs 75 s, past the
    engine's local limit (--timeout 15: a local read gets max(15, 60) = 60 s). The engine must not stage the pin
    against nothing: the action records 'unresolved:stage-pin-pre-index' with no add run, the parent's index keeps
    the old gitlink, the run is not APPLIED and exits non-zero. Control: the same tree with no shim stages the pin (rc 0)."""
    for hang in (True, False):
        tag = "pre_index.%s" % ("hang" if hang else "control")
        b = Box("pi_%s" % hang)
        try:
            work, s1, s2, r1 = pin_behind_tree(b)
            sub = os.path.realpath(os.path.join(work, "libs/a"))
            env, pre = None, None
            if hang:
                env = race_env(b, "plant", "checkout@" + sub, work, SXR_PLANT=b.p("planted_nothing"),
                               SXR_HANG_AFTER="ls-files:75")
                pre = b.shim()
            rc, so, se, rep, _ = b.run("--apply", "--advance-pins", "--root", work, "--quiet", "--timeout", "15",
                                       env=env, path_prefix=pre, timeout=400)
            acts = [a for a in (rec(rep, "libs/a") or {}).get("actions") or [] if a.get("op") == "advance-pin"]
            if hang:
                ok(tag + ".fired", os.path.exists(b.p("mark")))
                ok(tag + ".why", bool(acts) and acts[-1].get("why") == "unresolved:stage-pin-pre-index", acts)
                ok(tag + ".no_add_ran", bool(acts) and "staged_rc" not in acts[-1], acts)
                ok(tag + ".index_kept_old_pin", staged(b, work, "libs/a") == s1, staged(b, work, "libs/a"))
                ok(tag + ".nonzero", rc != 0, "rc=%s" % rc)
                ok(tag + ".not_applied", (rep or {}).get("verdict") not in (None, "APPLIED"),
                   (rep or {}).get("verdict"))
            else:
                ok(tag + ".exit_0", rc == 0, "rc=%s %s" % (rc, se[-200:]))
                ok(tag + ".staged_target", staged(b, work, "libs/a") == s2)
        except Exception as e:
            ok(tag + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            b.cleanup()


CHECKS = [
    ("race_commit", c_race_commit_detached_sub), ("race_switch", c_race_switch_root_branch),
    ("race_sub_branch", c_race_branch_in_sub), ("race_control", c_race_control_commit_on_main),
    ("race_other", c_race_other_writer_reported),
    ("autostash", c_autostash_race), ("sigterm_write", c_sigterm_during_write),
    ("no_new_call", c_no_new_call_after_stop),
    ("final_cap", c_final_read_capped_after_stop),
    ("sigterm_fetch", c_sigterm_fetch), ("sigint_fetch", c_sigint_fetch),
    ("staged_gitlink", c_staged_gitlink), ("escaped_after_exit", c_escaped_grandchild_after_exit),
    ("long_line", c_long_stderr_line), ("huge_stderr", c_huge_stderr_memory),
    ("askpass", c_askpass_all_routes), ("askpass_ssh_only", c_askpass_ssh_only), ("ext_env", c_ext_env_allow),
    ("ext_repo", c_ext_repo_allow), ("protocol_from_user", c_protocol_from_user), ("trace_env", c_trace_env),
    ("auth_header", c_auth_header_redacted), ("secret8", c_registered_8char_secret),
    ("ctrl_url", c_control_chars_in_url), ("invalid_remote", c_invalid_remote_blocks),
    ("diverged", c_diverged_upstreams_block), ("no_upstream_main", c_no_upstream_main_blocks),
    ("lock_symlink", c_lock_symlink), ("lock_overlap", c_lock_overlap), ("out_unwritable", c_out_unwritable_before),
    ("out_lost", c_out_lost_after_write), ("default_out_symlink", c_default_out_inside_tree),
    ("default_out_relative", c_default_out_relative), ("unsafe_path", c_unsafe_gitlink_paths),
    ("outside_parent", c_outside_parent),
    # review round 6
    ("write_deadline", c_write_outlives_deadline), ("write_timeout", c_write_timeout_term_first),
    ("write_kill", c_write_timeout_kill_after_grace), ("marker_success", c_marker_after_success),
    ("switch_at_merge", c_switch_at_merge), ("sigterm_pin", c_sigterm_during_pin_checkout),
    ("marker_inspect", c_marker_after_inspection), ("wrote_then_other", c_wrote_then_other_moved),
    ("staged_root", c_staged_gitlink_root_behind), ("lock_open", c_lock_open_error), ("ctrl_c", c_ctrl_c_at_prompt),
    ("update_none", c_update_none_not_followed), ("interrupted_labels", c_interrupted_fetch_labels),
    ("blind_failed", c_blind_beats_failed), ("stale_marker", c_stale_marker_on_clean_current_tree),
    # review round 7
    ("refused_marker", c_refused_write_leaves_no_marker), ("refused_stage", c_refused_stage_pin_leaves_no_marker),
    ("marker_lock", c_marker_and_lock_on_clean_tree), ("flock_error", c_flock_error_not_another_run),
    # review round 8
    ("sibling_kill", c_sibling_kill), ("sibling_wipe", c_sibling_wipe), ("marker_pre", c_marker_preexisting),
    ("stop_pin", c_stop_pin_marker), ("parent_lock", c_parent_lock),
    # review round 9
    ("lock_matrix", c_stale_lock_matrix), ("worktree_locks", c_worktree_locks), ("marker_kind", c_marker_path_kinds),
    ("lock_kind", c_lock_path_kinds), ("half_write", c_half_write), ("marker_vanish", c_marker_vanish),
    ("earlier_lock", c_earlier_marker_lock_apply), ("marker_unremovable", c_marker_unremovable),
    # review round 10
    ("branch_lock", c_branch_lock_class), ("wt_param", c_worktree_param_class), ("run_lock", c_run_lock_common),
    ("write_race", c_write_time_lock_race), ("marker_read", c_marker_read_status_class),
    ("wt_only", c_work_tree_only_half_write),
    # review round 11
    ("branch_shape", c_branch_name_shapes), ("branch_param", c_branch_param_shapes),
    ("marker_foreign", c_marker_foreign_op),
    # review round 12
    ("ref_exact", c_ref_resolution_exact), ("checkout_exact", c_checkout_target_exact),
    ("objvis", c_object_visibility),
    # review round 13
    ("symref", c_symbolic_tracking_ref), ("pin_symref", c_pin_symbolic_ref), ("pathspec", c_pathspec_literal),
    ("head_file", c_head_file), ("stage_verify", c_stage_pin_verified), ("pre_index", c_stage_pin_pre_index_unread),
]


def main(argv):
    if argv == ["--list"]:
        print("\n".join(n for n, _ in CHECKS))
        return 0
    only = None
    if argv[:1] == ["--only"] and len(argv) == 2:
        only = set(argv[1].split(","))
    elif argv:
        print("usage: robustness_checks.py [--only NAME,NAME] [--list]", file=sys.stderr)
        return 2
    if not GIT:
        print("sync-robustness: BLIND - git not found")
        return 2
    for name, fn in CHECKS:
        if only and name not in only:
            continue
        print("== %s" % name, flush=True)
        box = Box(name)
        try:
            fn(box)
        except Exception as e:  # a fixture that could not be built is a failure, never a pass
            ok(name + ".fixture", False, "%s: %s" % (type(e).__name__, e))
        finally:
            box.cleanup()
    print("sync-robustness: PASS %d FAIL %d" % (len(PASS), len(FAIL)))
    return 0 if not FAIL and PASS else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
