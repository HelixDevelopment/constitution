#!/usr/bin/env python3
"""scripts/sync/robustness_checks.py -- the body of tests/sync/test_robustness.sh (review round 4 findings).

Behavioural checks that drive the REAL engine (the wrapper in $SX_ENGINE, default scripts/sync/
sync_all_upstreams.sh) through its real invocation path against REAL git repositories in a sandbox
(tempfile.mkdtemp under $TMPDIR; file:// and 127.0.0.1 only, no network, no forge, nothing in $HOME).

Evidence class (section 11.4.289): LIVE-class for the engine and git. Some checks stand a small program in for a
HOSTILE REMOTE or a USER (labelled per check as "fixture"): a remote.<name>.uploadpack program that writes a
long or hostile stderr, hangs, or prints an Authorization header; an askpass / ext:: helper that records it was
run; scripts/sync/race_git_shim.py, which acts as a user between the engine's inspection and its write and then
runs the real git. None of them replaces the engine or git.

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
    """V13 / P42: the lock path is a symbolic link to a file that does not exist: exit 7, the target never made."""
    r_url, r_seed = box.bare("HelixDevelopment", "solo")
    work = box.clone(r_url, "w")
    target = box.p("LOCK_TARGET_CREATED")
    os.symlink(target, os.path.join(work, ".git", "helix-sync-upstreams.lock"))
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work, "--quiet")
    ok("lock_symlink.exit_7", rc == 7, "rc=%s" % rc)
    ok("lock_symlink.target_not_created", not os.path.exists(target))
    # P27 (round 5): the same link planted at a SUBMODULE's lock (its git common dir), taken by lock_repositories
    work2, a_seed, r_seed, s1, s2, r1, r2 = pinned_tree(box)
    common = box.git(os.path.join(work2, "libs/a"), "rev-parse", "--path-format=absolute", "--git-common-dir")
    target2 = box.p("SUB_LOCK_TARGET_CREATED")
    os.symlink(target2, os.path.join(common, "helix-sync-upstreams.lock"))
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work2, "--quiet")
    ok("lock_symlink.submodule_exit_7", rc == 7, "rc=%s" % rc)
    ok("lock_symlink.submodule_target_not_created", not os.path.exists(target2))
    os.unlink(os.path.join(common, "helix-sync-upstreams.lock"))  # control: without the link the run proceeds
    rc, so, se, rep, _ = box.run("--check", "--no-fetch", "--root", work2, "--quiet")
    ok("lock_symlink.control_no_link_runs", rc != 7, "rc=%s" % rc)


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
