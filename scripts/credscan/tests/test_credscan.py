#!/usr/bin/env python3
"""Test-first suite for credscan.py / credscan_hook.py (real CLI invocation path).
Synthetic credential-shaped values are assembled at runtime from pieces so this
file itself never contains a scannable token (and prints none)."""
import json, os, subprocess, sys, tempfile, unittest, random, string, shutil, atexit
_SESSION = tempfile.mkdtemp(prefix="credscan_suite.")
tempfile.tempdir = _SESSION
def _onerr(fn, path, exc):
    try: os.chmod(os.path.dirname(path), 0o700); os.chmod(path, 0o700); fn(path)
    except OSError: pass
atexit.register(lambda: shutil.rmtree(_SESSION, onerror=_onerr))
HERE = os.path.dirname(os.path.abspath(__file__))
SCAN = os.path.join(HERE, "..", "credscan.py")
HOOK = os.path.join(HERE, "..", "credscan_hook.py")
R = random.Random(7)
def rnd(n, alpha=string.ascii_letters + string.digits):
    return "".join(R.choice(alpha) for _ in range(n))
def fake(kind):
    if kind == "github": return "gh" + "p_" + rnd(36)
    if kind == "github_pat": return "github" + "_pat_" + rnd(82, string.ascii_letters + string.digits + "_")
    if kind == "gitlab": return "gl" + "pat-" + rnd(20, string.ascii_letters + string.digits + "_-")
    if kind == "sk": return "s" + "k-" + rnd(48)
    if kind == "jev": return "ab" + "c_" + rnd(100, string.ascii_letters + string.digits + "_-")
    if kind == "bearer": return "Bear" + "er " + rnd(40)
    if kind == "aws": return "AK" + "IA" + rnd(16, string.ascii_uppercase + string.digits)
    raise KeyError(kind)
def run(*a, stdin=None, env=None):
    e = dict(os.environ); e.update(env or {})
    return subprocess.run([sys.executable, "-I", *a], input=stdin, capture_output=True, text=True, env=e)

class Scan(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_t.")
        self.vals = []
    def w(self, name, lines):
        p = os.path.join(self.t, name)
        with open(p, "w") as f: f.write("\n".join(lines) + "\n")
        return p
    def scan(self, *extra):
        return run(SCAN, "scan", "--root", self.t, "--json", *extra)
    def assertNoValue(self, r):
        for v in self.vals: self.assertNotIn(v, r.stdout + r.stderr)
    def test_golden_good_each_class_counted(self):
        for kind, cls in [("github","github"),("github_pat","github"),("gitlab","gitlab"),("sk","sk"),("jev","jev_gateway"),("bearer","bearer"),("aws","aws")]:
            with self.subTest(kind=kind):
                v = fake(kind); self.vals.append(v)
                self.w("a_%s.jsonl" % kind, ['{"text": "out: %s done"}' % v])
                r = self.scan()
                self.assertEqual(r.returncode, 0, r.stderr)
                d = json.loads(r.stdout)
                total = sum(f["counts"].get(cls, 0) for f in d["files"] if f["path"].endswith("a_%s.jsonl" % kind))
                self.assertEqual(total, 1, (kind, d))
                self.assertNoValue(r)
    def test_golden_bad_placeholders_not_counted(self):
        self.w("ph.txt", ["token=gh" + "p_" + "x" * 36, "key=s" + "k-" + "x" * 40, "s" + "k-ant-your-key-here", "Bear" + "er " + "<token>", "gl" + "pat-" + "XXXXXXXXXXXXXXXXXXXX", "Bear" + "er " + "$TOKEN_VALUE_FROM_ENV_VAR_X"])
        d = json.loads(self.scan().stdout)
        self.assertEqual(sum(sum(f["counts"].values()) for f in d["files"]), 0, d)
    def test_placeholder_word_inside_high_entropy_token_rejected(self):
        self.w("pw.txt", ["gh" + "p_" + rnd(20) + "example" + rnd(9)])
        self.assertEqual(json.loads(self.scan().stdout)["total"], 0)
    def test_negative_control_clean_tree_zero(self):
        self.w("clean.txt", ["hello world", "ordinary text " + rnd(30)])
        d = json.loads(self.scan().stdout)
        self.assertEqual(d["total"], 0)
    def test_control_needle_reported_and_failing_when_blind(self):
        self.w("c.txt", ["x"])
        d = json.loads(self.scan().stdout)
        self.assertTrue(d["control"]["positive_seen"] and d["control"]["negative_clean"])
        r = run(SCAN, "scan", "--root", self.t, "--json", env={"CREDSCAN_FAULT_BLIND": "1"})
        self.assertEqual(r.returncode, 3, "blind instrument must exit 3 (BLIND), not report clean")
    def test_symlinked_dir_followed(self):
        real = tempfile.mkdtemp(prefix="credscan_real.")
        v = fake("github"); self.vals.append(v)
        open(os.path.join(real, "s.jsonl"), "w").write(v + "\n")
        os.symlink(real, os.path.join(self.t, "lnk"))
        d = json.loads(self.scan().stdout)
        self.assertEqual(d["total"], 1, d)
    def test_output_never_contains_value_even_on_text_format(self):
        v = fake("sk"); self.vals.append(v)
        self.w("t.txt", ["a " + v + " b"])
        r = run(SCAN, "scan", "--root", self.t)
        self.assertNoValue(r); self.assertIn("sk", r.stdout)
    def test_mutation_probe_dedup_overlap(self):
        v = fake("github_pat"); self.vals.append(v)
        self.w("o.txt", [v])
        d = json.loads(self.scan().stdout)
        self.assertEqual(d["total"], 1, "one token must not be double counted by overlapping classes")

class Ratchet(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_r."); self.b = os.path.join(self.t, "base.json")
        self.f = os.path.join(self.t, "x.txt")
    def put(self, n):
        open(self.f, "w").write("\n".join(fake("github") for _ in range(n)) + "\n")
    def test_ratchet_pass_equal_fail_increase_pass_decrease_and_baseline_counts_only(self):
        self.put(2)
        self.assertEqual(run(SCAN, "baseline", "--root", self.t, "--baseline", self.b).returncode, 0)
        raw = open(self.b).read()
        d = json.loads(raw)
        for v in [l.strip() for l in open(self.f)]: self.assertNotIn(v, raw)
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", self.b).returncode, 0)
        self.put(3)
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", self.b).returncode, 1)
        self.put(1)
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", self.b).returncode, 0)
    def test_new_file_with_hits_fails_and_missing_baseline_is_error(self):
        self.put(1)
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", self.b).returncode, 2)
        run(SCAN, "baseline", "--root", self.t, "--baseline", self.b)
        open(os.path.join(self.t, "y.txt"), "w").write(fake("sk") + "\n")
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", self.b).returncode, 1)

class Hook(unittest.TestCase):
    def test_userprompt_blocks_high_confidence(self):
        v = fake("github")
        r = run(HOOK, stdin=json.dumps({"hook_event_name": "UserPromptSubmit", "prompt": "use " + v}))
        self.assertEqual(r.returncode, 0); self.assertNotIn(v, r.stdout + r.stderr)
        self.assertEqual(json.loads(r.stdout)["decision"], "block")
    def test_userprompt_clean_silent(self):
        r = run(HOOK, stdin=json.dumps({"hook_event_name": "UserPromptSubmit", "prompt": "hello"}))
        self.assertEqual((r.returncode, r.stdout.strip()), (0, ""))
    def test_posttool_warns_with_counts_only(self):
        v = fake("gitlab")
        r = run(HOOK, stdin=json.dumps({"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_response": {"stdout": v}}))
        self.assertNotIn(v, r.stdout + r.stderr)
        o = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertEqual(o["hookEventName"], "PostToolUse"); self.assertIn("gitlab", o["additionalContext"])
    def test_warn_mode_never_blocks_prompt(self):
        v = fake("github")
        r = run(HOOK, stdin=json.dumps({"hook_event_name": "UserPromptSubmit", "prompt": v}), env={"CREDSCAN_HOOK_MODE": "warn"})
        self.assertNotEqual(json.loads(r.stdout).get("decision"), "block")
    def test_malformed_input_fails_open_exit0(self):
        r = run(HOOK, stdin="not json")
        self.assertEqual(r.returncode, 0)


class Honesty(unittest.TestCase):
    """A zero must mean "looked and found nothing", never "could not look" (section 11.4.273)."""
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_h.")
    def test_missing_root_is_a_usage_error_not_a_clean_zero(self):
        r = run(SCAN, "scan", "--root", os.path.join(self.t, "does-not-exist"))
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("does not exist", r.stderr)
    def test_check_with_missing_root_is_error_even_with_a_valid_baseline(self):
        b = os.path.join(self.t, "b.json")
        self.assertEqual(run(SCAN, "baseline", "--root", self.t, "--baseline", b).returncode, 0)
        r = run(SCAN, "check", "--root", os.path.join(self.t, "gone"), "--baseline", b)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
    def test_files_that_could_not_be_scanned_are_counted_and_reported(self):
        open(os.path.join(self.t, "bin.dat"), "wb").write(b"\0\1\2" + b"x" * 100)
        big = os.path.join(self.t, "big.txt"); open(big, "w").write("y" * 5000)
        unreadable = os.path.join(self.t, "locked.txt"); open(unreadable, "w").write("z\n"); os.chmod(unreadable, 0)
        try:
            r = run(SCAN, "scan", "--root", self.t, "--json", env={"CREDSCAN_MAX_BYTES": "1000"})
        finally:
            os.chmod(unreadable, 0o600)
        self.assertEqual(r.returncode, 0, r.stderr)
        sk = json.loads(r.stdout)["skipped"]
        self.assertEqual((sk["binary"], sk["oversize"], sk["unreadable"]), (1, 1, 1), sk)
    def test_text_output_and_check_mention_skipped(self):
        open(os.path.join(self.t, "bin.dat"), "wb").write(b"\0" * 10)
        self.assertIn("SKIPPED\t", run(SCAN, "scan", "--root", self.t).stdout)
        b = os.path.join(self.t, "b.json"); run(SCAN, "baseline", "--root", self.t, "--baseline", b)
        self.assertIn("skipped", run(SCAN, "check", "--root", self.t, "--baseline", b).stdout)

class StatusFile(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_s."); self.b = os.path.join(self.t, "base.json")
        self.st = os.path.join(self.t, "status.json"); self.f = os.path.join(self.t, "x.txt")
    def read(self):
        return json.load(open(self.st))
    def test_check_writes_counts_only_status_0600_ok_and_violation(self):
        v = fake("github"); open(self.f, "w").write(v + "\n")
        run(SCAN, "baseline", "--root", self.t, "--baseline", self.b)
        r = run(SCAN, "check", "--root", self.t, "--baseline", self.b, "--status-file", self.st)
        self.assertEqual(r.returncode, 0)
        d = self.read(); self.assertEqual((d["exit"], d["violations"], d["state"]), (0, 0, "ok"))
        self.assertEqual(oct(os.stat(self.st).st_mode & 0o777), "0o600")
        open(self.f, "a").write(fake("github") + "\n")
        r = run(SCAN, "check", "--root", self.t, "--baseline", self.b, "--status-file", self.st)
        self.assertEqual(r.returncode, 1)
        d = self.read(); self.assertEqual((d["exit"], d["violations"], d["state"]), (1, 1, "ratchet_violated"))
        self.assertNotIn(v, open(self.st).read())
    def test_status_records_missing_baseline_and_blind(self):
        open(self.f, "w").write("hello\n")
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", self.b, "--status-file", self.st).returncode, 2)
        self.assertEqual(self.read()["state"], "baseline_missing")
        run(SCAN, "baseline", "--root", self.t, "--baseline", self.b)
        r = run(SCAN, "check", "--root", self.t, "--baseline", self.b, "--status-file", self.st, env={"CREDSCAN_FAULT_BLIND": "1"})
        self.assertEqual(r.returncode, 3); self.assertEqual(self.read()["state"], "blind")

class TimerWrapper(unittest.TestCase):
    """The unit's ExecStart: lock + env + check. Real invocation path, real files."""
    WRAP = os.path.join(HERE, "..", "credscan_check_timer.sh")
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_w."); self.state = os.path.join(self.t, "state")
        self.root = os.path.join(self.t, "root"); os.mkdir(self.root)
        open(os.path.join(self.root, "a.txt"), "w").write("nothing\n")
        self.env = {"CREDSCAN_STATE_DIR": self.state, "CREDSCAN_ROOTS": self.root}
    def wrap(self, **extra):
        e = dict(os.environ); e.update(self.env); e.update(extra)
        return subprocess.run(["bash", self.WRAP], capture_output=True, text=True, env=e)
    def test_refuses_without_baseline_and_never_creates_one(self):
        r = self.wrap()
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.state, "baseline.json")), "an unattended run must not silently accept the current exposure")
        self.assertEqual(json.load(open(os.path.join(self.state, "status.json")))["state"], "baseline_missing")
    def test_ok_then_violation_exit_codes_and_status(self):
        os.makedirs(self.state, mode=0o700)
        self.assertEqual(run(SCAN, "baseline", "--root", self.root, "--baseline", os.path.join(self.state, "baseline.json")).returncode, 0)
        self.assertEqual(self.wrap().returncode, 0)
        v = fake("sk"); open(os.path.join(self.root, "leak.txt"), "w").write(v + "\n")
        r = self.wrap()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertNotIn(v, r.stdout + r.stderr + open(os.path.join(self.state, "status.json")).read())
        self.assertEqual(json.load(open(os.path.join(self.state, "status.json")))["state"], "ratchet_violated")
    def test_overlapping_run_is_skipped_not_failed(self):
        import fcntl
        os.makedirs(self.state, mode=0o700)
        run(SCAN, "baseline", "--root", self.root, "--baseline", os.path.join(self.state, "baseline.json"))
        fh = open(os.path.join(self.state, "lock"), "w"); fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            r = self.wrap()
        finally:
            fh.close()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr); self.assertIn("already running", r.stdout + r.stderr)
    def test_state_dir_is_0700(self):
        self.wrap()
        self.assertEqual(oct(os.stat(self.state).st_mode & 0o777), "0o700")

class Units(unittest.TestCase):
    D = os.path.join(HERE, "..", "systemd")
    def read(self, n): return open(os.path.join(self.D, n)).read()
    def test_service_is_low_priority_and_bounded(self):
        s = self.read("credscan-check.service")
        for need in ("Nice=19", "IOSchedulingClass=idle", "CPUSchedulingPolicy=idle", "MemoryMax=", "TimeoutStartSec=", "Type=oneshot", "ExecStart="):
            self.assertIn(need, s)
        self.assertNotIn("settings.json", s)
    def test_timer_is_thirty_minutes(self):
        t = self.read("credscan-check.timer")
        self.assertIn("OnUnitActiveSec=30min", t); self.assertIn("OnBootSec=", t); self.assertIn("WantedBy=timers.target", t)
    def test_installer_dry_run_prints_plan_and_changes_nothing(self):
        home = tempfile.mkdtemp(prefix="credscan_home.")
        r = subprocess.run(["bash", os.path.join(HERE, "..", "install_timer.sh"), "--dry-run"], capture_output=True, text=True, env=dict(os.environ, HOME=home))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("credscan-check.timer", r.stdout)
        self.assertEqual(os.listdir(home), [], "dry-run must not write anything")

class Round2(unittest.TestCase):
    """Findings of independent review round 1."""
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_r2."); self.b = os.path.join(self.t, "b.json")
    def test_B1_unreadable_directory_is_counted_not_silent(self):
        root = os.path.join(self.t, "root"); os.makedirs(os.path.join(root, "locked"))
        open(os.path.join(root, "locked", "x.txt"), "w").write(fake("github") + "\n")
        os.chmod(os.path.join(root, "locked"), 0)
        try:
            r = run(SCAN, "scan", "--root", root, "--json")
        finally:
            os.chmod(os.path.join(root, "locked"), 0o700)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertGreaterEqual(json.loads(r.stdout)["skipped"]["unreadable"], 1)
    def test_B1_unreadable_root_is_counted(self):
        root = os.path.join(self.t, "root"); os.makedirs(root); os.chmod(root, 0)
        try:
            r = run(SCAN, "scan", "--root", root, "--json")
        finally:
            os.chmod(root, 0o700)
        self.assertGreaterEqual(json.loads(r.stdout)["skipped"]["unreadable"], 1)
    def test_B2_crash_is_not_exit_1_and_status_is_not_stale(self):
        root = os.path.join(self.t, "root"); os.makedirs(root)
        open(os.path.join(root, "a.txt"), "w").write(fake("sk") + "\n")
        st = os.path.join(self.t, "st.json")
        json.dump({"state": "ok", "exit": 0}, open(st, "w"))
        json.dump({"schema": 1, "files": []}, open(self.b, "w"))   # wrong shape: list
        r = run(SCAN, "check", "--root", root, "--baseline", self.b, "--status-file", st)
        self.assertNotEqual(r.returncode, 1, r.stderr)
        self.assertEqual(r.returncode, 2)
        self.assertEqual(json.load(open(st))["state"], "baseline_invalid")
    def test_B2_unexpected_exception_exits_4_and_writes_error_status(self):
        root = os.path.join(self.t, "root"); os.makedirs(root)
        st = os.path.join(self.t, "st.json"); json.dump({"state": "ok"}, open(st, "w"))
        run(SCAN, "baseline", "--root", root, "--baseline", self.b)
        r = run(SCAN, "check", "--root", root, "--baseline", self.b, "--status-file", st, env={"CREDSCAN_FAULT_CRASH": "1"})
        self.assertEqual(r.returncode, 4); self.assertEqual(json.load(open(st))["state"], "error")
    def test_I1_control_needle_covers_every_class_and_the_file_path(self):
        for cls in ("github", "gitlab", "sk", "aws", "pem", "jev_gateway", "bearer", "file_path"):
            r = run(SCAN, "scan", "--root", self.t, env={"CREDSCAN_FAULT_BLIND_CLASS": cls})
            self.assertEqual(r.returncode, 3, (cls, r.stdout, r.stderr))
        self.assertEqual(run(SCAN, "scan", "--root", self.t).returncode, 0)
    def test_I1_pem_header_is_counted(self):
        f = os.path.join(self.t, "k.txt"); open(f, "w").write("-----BEGIN " + "RSA PRIVATE KEY-----\n")
        self.assertEqual(json.loads(run(SCAN, "scan", "--root", f, "--json").stdout)["total"], 1)
    def test_I2_fifo_does_not_hang_and_is_counted(self):
        root = os.path.join(self.t, "root"); os.makedirs(root); os.mkfifo(os.path.join(root, "pipe"))
        try:
            r = subprocess.run([sys.executable, "-I", SCAN, "scan", "--root", root, "--json"], capture_output=True, text=True, timeout=20)
        except subprocess.TimeoutExpired:
            self.fail("scan hung on a FIFO")
        self.assertEqual(json.loads(r.stdout)["skipped"]["special"], 1)
    def test_I5_baseline_mode_0600(self):
        run(SCAN, "baseline", "--root", self.t, "--baseline", self.b)
        self.assertEqual(oct(os.stat(self.b).st_mode & 0o777), "0o600")
    def test_I5_symlink_loop_terminates_and_counts_once(self):
        root = os.path.join(self.t, "root"); os.makedirs(root)
        open(os.path.join(root, "a.txt"), "w").write(fake("github") + "\n")
        os.symlink(root, os.path.join(root, "loop"))
        r = subprocess.run([sys.executable, "-I", SCAN, "scan", "--root", root, "--json"], capture_output=True, text=True, timeout=20)
        self.assertEqual(json.loads(r.stdout)["total"], 1)
    def test_I5_status_contains_skipped(self):
        st = os.path.join(self.t, "st.json")
        run(SCAN, "baseline", "--root", self.t, "--baseline", self.b)
        run(SCAN, "check", "--root", self.t, "--baseline", self.b, "--status-file", st)
        self.assertIn("skipped", json.load(open(st)))
    def test_I5_blind_needle_is_real_not_only_injected(self):
        # M1 mutation guard: the positive control must be computed, never constant True
        src = open(SCAN).read()
        self.assertNotIn("pos = True", src)
    def test_I6_baseline_creates_missing_parent_dir_0700(self):
        b = os.path.join(self.t, "newdir", "sub", "b.json")
        r = run(SCAN, "baseline", "--root", self.t, "--baseline", b)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(oct(os.stat(os.path.dirname(b)).st_mode & 0o777), "0o700")

class WrapperRound2(unittest.TestCase):
    WRAP = os.path.join(HERE, "..", "credscan_check_timer.sh")
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_w2."); self.state = os.path.join(self.t, "state")
        self.root = os.path.join(self.t, "root"); os.mkdir(self.root); open(os.path.join(self.root, "a"), "w").write("x\n")
    def wrap(self, env=None, drop=()):
        e = dict(os.environ); e.update({"CREDSCAN_STATE_DIR": self.state, "CREDSCAN_ROOTS": self.root}); e.update(env or {})
        for k in drop: e.pop(k, None)
        return subprocess.run(["bash", self.WRAP], capture_output=True, text=True, env=e)
    def test_I3_missing_flock_is_error_not_skip(self):
        bindir = os.path.join(self.t, "bin"); os.mkdir(bindir)
        for tool in ("bash", "python3", "dirname", "mkdir", "chmod", "timeout", "nice", "ionice", "mv", "printf", "date"):
            src = subprocess.run(["bash", "-c", "command -v " + tool], capture_output=True, text=True).stdout.strip()
            if src: os.symlink(src, os.path.join(bindir, tool))
        r = self.wrap(env={"PATH": bindir})
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertNotIn("already running", r.stdout + r.stderr)
    def test_I7_unset_home_without_state_dir_is_exit_2(self):
        r = self.wrap(drop=("HOME", "CREDSCAN_STATE_DIR"))
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
    def test_B2_wrapper_marks_running_before_scan(self):
        # a stale "ok" must not survive a killed run: the wrapper writes state=running first
        os.makedirs(self.state, mode=0o700)
        json.dump({"state": "ok", "exit": 0}, open(os.path.join(self.state, "status.json"), "w"))
        r = self.wrap()   # no baseline -> scan refuses; status must be replaced either way
        self.assertNotEqual(json.load(open(os.path.join(self.state, "status.json")))["state"], "ok")
    def test_minor_timeout_status_has_time(self):
        os.makedirs(self.state, mode=0o700)
        run(SCAN, "baseline", "--root", self.root, "--baseline", os.path.join(self.state, "baseline.json"))
        bindir = os.path.join(self.t, "slow"); os.makedirs(bindir)
        open(os.path.join(bindir, "python3"), "w").write("#!/bin/sh\nexec sleep 30\n"); os.chmod(os.path.join(bindir, "python3"), 0o755)
        self.wrap(env={"CREDSCAN_TIMEOUT": "1", "PATH": bindir + ":" + os.environ["PATH"]})
        d = json.load(open(os.path.join(self.state, "status.json")))
        self.assertEqual(d["state"], "timeout"); self.assertIn("time", d)
    def test_minor_seed_baseline_is_validated(self):
        home = tempfile.mkdtemp(prefix="credscan_h2."); bad = os.path.join(home, "bad.json"); open(bad, "w").write("{}")
        r = subprocess.run(["bash", os.path.join(HERE, "..", "install_timer.sh"), "--seed-baseline", bad],
                           capture_output=True, text=True, env=dict(os.environ, HOME=home, CREDSCAN_STATE_DIR=os.path.join(home, "st")))
        self.assertNotEqual(r.returncode, 0); self.assertFalse(os.path.exists(os.path.join(home, "st", "baseline.json")))
    def test_I4_no_consumer_path_in_hub_units(self):
        for n in ("credscan-check.service", "credscan-check.timer"):
            t = open(os.path.join(HERE, "..", "systemd", n)).read()
            self.assertNotIn("catalogizer", t); self.assertNotIn("Persistent=", t)

class Round3(unittest.TestCase):
    """Findings of independent review round 2."""
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_r3."); self.b = os.path.join(self.t, "b.json"); self.st = os.path.join(self.t, "st.json")
        self.root = os.path.join(self.t, "root"); os.makedirs(self.root); open(os.path.join(self.root, "a"), "w").write("x\n")
        run(SCAN, "baseline", "--root", self.root, "--baseline", self.b)
    def state(self): return json.load(open(self.st))
    def test_B1_unreadable_root_is_partial_not_ok(self):
        os.chmod(self.root, 0)
        try: r = run(SCAN, "check", "--root", self.root, "--baseline", self.b, "--status-file", self.st)
        finally: os.chmod(self.root, 0o700)
        self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
        self.assertEqual(self.state()["state"], "partial")
    def test_B1_unreadable_subdir_is_partial(self):
        d = os.path.join(self.root, "locked"); os.makedirs(d); os.chmod(d, 0)
        try: r = run(SCAN, "check", "--root", self.root, "--baseline", self.b, "--status-file", self.st)
        finally: os.chmod(d, 0o700)
        self.assertEqual(r.returncode, 5); self.assertEqual(self.state()["state"], "partial")
    def test_B1_dangling_symlink_is_not_a_false_refusal(self):
        os.symlink(os.path.join(self.t, "nonexistent"), os.path.join(self.root, "dangling"))
        r = run(SCAN, "check", "--root", self.root, "--baseline", self.b, "--status-file", self.st)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.state()["state"], "ok"); self.assertEqual(self.state()["skipped"]["dangling"], 1)
        self.assertEqual(self.state()["skipped"]["unreadable"], 0)
    def test_minor_status_file_equals_form_on_crash(self):
        json.dump({"state": "ok", "exit": 0}, open(self.st, "w"))
        r = run(SCAN, "check", "--root", self.root, "--baseline", self.b, "--status-file=" + self.st, env={"CREDSCAN_FAULT_CRASH": "1"})
        self.assertEqual(r.returncode, 4); self.assertEqual(self.state()["state"], "error")
    def test_I1_streaming_buffers_bounded_by_unit_memory(self):
        out = subprocess.run([sys.executable, "-I", "-c", "import sys;sys.path.insert(0,%r);import credscan;print(credscan.CHUNK, credscan.MAX_UNBROKEN)" % os.path.join(HERE, "..")],
                             capture_output=True, text=True).stdout.split()
        chunk, unbroken = int(out[0]), int(out[1])
        # worst-case working set ~ (carry + chunk) * a few copies must stay far below MemoryMax=1G
        self.assertLessEqual((chunk + unbroken) * 5, 512 * 1024 * 1024)
    def test_minor_baseline_mode_0600_under_any_umask(self):
        e = dict(os.environ)
        p = os.path.join(self.t, "nb.json")
        subprocess.run(["bash", "-c", "umask 000; exec \"$0\" -I \"$1\" baseline --root \"$2\" --baseline \"$3\"", sys.executable, SCAN, self.root, p], env=e, capture_output=True)
        self.assertEqual(os.stat(p).st_mode & 0o777, 0o600)

class WrapperRound3(unittest.TestCase):
    WRAP = WrapperRound2.WRAP
    wrap = WrapperRound2.wrap
    def fake_python(self, body):
        bindir = os.path.join(self.t, "fbin"); os.makedirs(bindir, exist_ok=True)
        p = os.path.join(bindir, "python3"); open(p, "w").write("#!/bin/sh\n" + body + "\n"); os.chmod(p, 0o755)
        return bindir
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_w3."); self.state = os.path.join(self.t, "state"); os.makedirs(self.state, mode=0o700)
        self.root = os.path.join(self.t, "root"); os.mkdir(self.root); open(os.path.join(self.root, "a"), "w").write("x\n")
        run(SCAN, "baseline", "--root", self.root, "--baseline", os.path.join(self.state, "baseline.json"))
    def status(self): return json.load(open(os.path.join(self.state, "status.json")))
    def test_killed_run_is_not_left_running(self):
        fb = self.fake_python("kill -9 $$")
        r = self.wrap(env={"PATH": fb + ":" + os.environ["PATH"]})
        self.assertEqual(r.returncode, 137, r.stdout + r.stderr)
        self.assertEqual(self.status()["state"], "killed"); self.assertEqual(self.status()["exit"], 137)
    def test_engine_import_failure_exit1_is_not_left_running(self):
        fb = self.fake_python("exit 1")
        r = self.wrap(env={"PATH": fb + ":" + os.environ["PATH"]})
        self.assertEqual(self.status()["state"], "error")
    def test_running_marker_is_written_before_the_scan(self):
        fb = self.fake_python('cat "$CREDSCAN_STATE_DIR/status.json" > "$CREDSCAN_STATE_DIR/seen.json"; exit 0')
        self.wrap(env={"PATH": fb + ":" + os.environ["PATH"]})
        self.assertEqual(json.load(open(os.path.join(self.state, "seen.json")))["state"], "running")

class Round4(unittest.TestCase):
    """Throughput/oversize/cache findings of review round 3."""
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="credscan_r4.")
    def test_big_file_is_streamed_not_skipped_and_boundary_token_found(self):
        v1, v2 = fake("github"), fake("sk")
        p = os.path.join(self.t, "big.jsonl")
        with open(p, "w") as f:
            line = "x" * 1023 + "\n"
            for i in range(8 * 1024 - 1): f.write(line)          # ~8 MiB, then an odd-length line so the chunk cut falls mid-line
            f.write("y" * 500 + " pre " + v1 + " post\n")
            for i in range(12 * 1024): f.write(line)
            f.write(v2)              # last line has NO trailing newline
        r = run(SCAN, "scan", "--root", self.t, "--json")
        d = json.loads(r.stdout)
        self.assertEqual(d["total"], 2, d.get("skipped"))
        self.assertEqual(d["skipped"]["oversize"], 0)
        for v in (v1, v2): self.assertNotIn(v, r.stdout + r.stderr)
    def test_oversize_above_ceiling_makes_check_partial(self):
        with open(os.path.join(self.t, "f.txt"), "w") as f: f.write("x" * 4096 + "\n")
        base = os.path.join(self.t, "b.json")
        run(SCAN, "baseline", "--root", self.t, "--baseline", base)
        r = run(SCAN, "check", "--root", self.t, "--baseline", base, env={"CREDSCAN_MAX_BYTES": "100"})
        self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
    def test_baseline_warns_when_partial(self):
        with open(os.path.join(self.t, "f.txt"), "w") as f: f.write("x" * 4096 + "\n")
        r = run(SCAN, "baseline", "--root", self.t, "--baseline", os.path.join(self.t, "b.json"), env={"CREDSCAN_MAX_BYTES": "100"})
        self.assertIn("WARNING", r.stderr)
    def test_cache_skips_unchanged_and_rescans_changed(self):
        v = fake("github")
        p = os.path.join(self.t, "a.txt")
        open(p, "w").write("nothing\n")
        cache = os.path.join(tempfile.mkdtemp(prefix="credscan_c."), "cache.json")
        base = os.path.join(self.t, "b.json")
        run(SCAN, "baseline", "--root", self.t, "--baseline", base)
        r1 = run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache)
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertEqual(oct(os.stat(cache).st_mode & 0o777), "0o600")
        c = json.load(open(cache)); self.assertTrue(c["counts_only"])
        self.assertNotIn(v, open(cache).read())
        # poison the cache entry: a cache hit must trust it (proves the file was NOT re-read)
        key = [k for k in c["files"] if k.endswith("a.txt")][0]
        c["files"][key][5] = {"sk": 1}; json.dump(c, open(cache, "w"))
        r2 = run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache)
        self.assertEqual(r2.returncode, 1, "cache hit must not re-read an unchanged file")
        # change the file: size/mtime differ -> rescanned, poison gone, token found
        open(p, "w").write("now " + v + "\n")
        r3 = run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache)
        self.assertEqual(r3.returncode, 1); self.assertNotIn(v, r3.stdout + r3.stderr)
        d = json.loads(run(SCAN, "scan", "--root", self.t, "--json", "--cache", cache).stdout)
        self.assertEqual(d["total"], 1)
    def test_cache_rescans_when_size_changes_even_if_mtime_same(self):
        p = os.path.join(self.t, "a.txt"); open(p, "w").write("nothing\n")
        st = os.stat(p); cache = os.path.join(self.t, "c.json")
        base = os.path.join(self.t, "b.json"); run(SCAN, "baseline", "--root", self.t, "--baseline", base)
        run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache)
        open(p, "w").write("now " + fake("github") + "\n"); os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache).returncode, 1)
    def test_cache_misses_when_content_replaced_with_same_size_and_mtime(self):
        p = os.path.join(self.t, "a.txt"); v = fake("github"); open(p, "w").write("n" * len(v) + "\n")
        st = os.stat(p); cache = os.path.join(self.t, "c.json")
        base = os.path.join(self.t, "b.json"); run(SCAN, "baseline", "--root", self.t, "--baseline", base)
        run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache)
        q = p + ".new"; open(q, "w").write(v + "\n"); os.utime(q, ns=(st.st_atime_ns, st.st_mtime_ns)); os.replace(q, p)   # new inode, same size+mtime
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache).returncode, 1)
    def test_cache_invalid_when_source_logic_changes(self):
        import importlib.util
        outs = []
        for extra in ("", "\n# changed logic\n"):
            d = tempfile.mkdtemp(prefix="credscan_v."); src = open(SCAN).read() + extra
            open(os.path.join(d, "credscan.py"), "w").write(src)
            outs.append(subprocess.run([sys.executable, "-I", "-c", "import sys;sys.path.insert(0,%r);import credscan;print(credscan._version())" % d], capture_output=True, text=True).stdout)
        self.assertNotEqual(outs[0], outs[1])
    def test_malformed_cache_entry_is_a_miss_not_an_error(self):
        open(os.path.join(self.t, "a.txt"), "w").write("nothing\n")
        cache = os.path.join(self.t, "c.json"); base = os.path.join(self.t, "b.json")
        run(SCAN, "baseline", "--root", self.t, "--baseline", base); run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache)
        c = json.load(open(cache)); k = [x for x in c["files"] if x.endswith("a.txt")][0]
        c["files"][k] = [1, 2, 3, 4, 5, "bad", None]; json.dump(c, open(cache, "w"))
        self.assertEqual(run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache).returncode, 0)
    def test_sigterm_checkpoints_cache_progress(self):
        import signal, time
        for i in range(50): open(os.path.join(self.t, "f%d.txt" % i), "w").write("x\n")
        cache = os.path.join(self.t, "c.json")
        slow = tempfile.mkdtemp(prefix="credscan_s."); d = os.path.join(slow, "credscan.py")
        src = open(SCAN).read().replace("def scan_file(path):", "def scan_file(path):\n    import time; time.sleep(0.2)", 1)
        self.assertIn("time.sleep(0.2)", src); open(d, "w").write(src)
        pr = subprocess.Popen([sys.executable, "-I", d, "scan", "--root", self.t, "--cache", cache], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2.5); pr.send_signal(signal.SIGTERM); rc = pr.wait(10)
        self.assertEqual(rc, 143)
        files = json.load(open(cache))["files"]; self.assertTrue(0 < len(files) < 50, len(files))
    def test_corrupt_or_foreign_cache_is_ignored(self):
        open(os.path.join(self.t, "a.txt"), "w").write("nothing\n")
        cache = os.path.join(self.t, "c.json"); open(cache, "w").write("{not json")
        base = os.path.join(self.t, "b.json"); run(SCAN, "baseline", "--root", self.t, "--baseline", base)
        r = run(SCAN, "check", "--root", self.t, "--baseline", base, "--cache", cache)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.load(open(cache))["schema"], 1)
    def test_wrapper_nonzero_when_error_recorded_after_python_exit0(self):
        state = tempfile.mkdtemp(prefix="credscan_w."); bindir = tempfile.mkdtemp(prefix="credscan_fb.")
        open(os.path.join(bindir, "python3"), "w").write("#!/bin/sh\nexit 0\n"); os.chmod(os.path.join(bindir, "python3"), 0o755)
        os.makedirs(os.path.join(state), exist_ok=True)
        run_env = dict(os.environ, CREDSCAN_STATE_DIR=state, CREDSCAN_ROOTS=self.t, PATH=bindir + ":" + os.environ["PATH"])
        base = os.path.join(state, "baseline.json"); run(SCAN, "baseline", "--root", self.t, "--baseline", base)
        os.chmod(base, 0o600)
        r = subprocess.run(["bash", os.path.join(HERE, "..", "credscan_check_timer.sh")], env=run_env, capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)

class Selftest(unittest.TestCase):
    def test_selftest_passes(self):
        r = run(SCAN, "selftest"); self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
if __name__ == "__main__": unittest.main()
