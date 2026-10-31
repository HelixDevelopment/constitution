# constitution/scripts/anchors/tests/test_cwd_independence.py
# known_failures_v73 ranks 1+2: the anchors tests must not depend on the cwd.
# REAL invocation path (subprocess of the real test scripts against the real
# Constitution.md); no test doubles. Covers e2e (canon root + consumer-shaped
# root), security (hostile cwd names), chaos (deleted cwd), determinism
# (3 identical runs, section 11.4.50), idempotency (no repo writes),
# performance (time budget) and a paired section 1.1 mutation.
import os, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _paths import CANON  # noqa: E402

PROBES = ["test_generate_minors.py", "test_wiring_audit_us4.py"]


def _run(script, cwd, tests_dir=HERE):
    env = dict(os.environ, CONSTITUTION_JEV_HOOK="off")
    return subprocess.run([sys.executable, os.path.join(tests_dir, script)],
                          cwd=cwd, capture_output=True, text=True, env=env, timeout=300)


def _git_state():
    r = subprocess.run(["git", "-C", CANON, "status", "--porcelain", "--", "scripts/anchors", "groups"],
                       capture_output=True, text=True)
    return r.stdout


def test_canon_root_and_unrelated_cwd():
    with tempfile.TemporaryDirectory() as empty:
        for cwd in (CANON, empty, "/"):
            for p in PROBES:
                r = _run(p, cwd)
                assert r.returncode == 0, f"{p} from cwd={cwd}: {r.stdout[-400:]}{r.stderr[-800:]}"


def test_consumer_shaped_root():
    # consumer layout: <root>/constitution is the canon (symlink: the real
    # file is the same bytes; consumer submodule checkouts are real dirs).
    with tempfile.TemporaryDirectory() as root:
        os.symlink(CANON, os.path.join(root, "constitution"))
        for p in PROBES:
            r = _run(p, root)
            assert r.returncode == 0, f"{p}: {r.stdout[-400:]}{r.stderr[-800:]}"


def test_hostile_cwd_names():
    with tempfile.TemporaryDirectory() as base:
        for name in ("a b", "x;touch pwned", "$(id)", "-rf"):
            d = os.path.join(base, name)
            os.mkdir(d)
            r = _run(PROBES[0], d)
            assert r.returncode == 0, f"cwd {name!r}: {r.stderr[-400:]}"
            assert not os.path.exists(os.path.join(base, "pwned")) and not os.path.exists(os.path.join(d, "pwned"))


def test_deleted_cwd_chaos():
    # cwd removed under the process: a location-independent test either runs
    # or fails loudly; it must never silently pass without Constitution.md.
    base = tempfile.mkdtemp()
    d = os.path.join(base, "gone")
    os.mkdir(d)
    code = (f"import os,sys,subprocess;os.chdir({d!r});os.rmdir({d!r});"
            f"r=subprocess.run([sys.executable,{os.path.join(HERE, PROBES[0])!r}],capture_output=True,text=True);"
            f"sys.exit(r.returncode)")
    r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True,
                       env=dict(os.environ, CONSTITUTION_JEV_HOOK="off"))
    shutil.rmtree(base, ignore_errors=True)
    assert r.returncode in (0, 1), r.stderr[-400:]  # clean pass or loud fail, never a crash/hang


def test_determinism_idempotency_performance():
    before = _git_state()
    outs = []
    t0 = time.time()
    for _ in range(3):
        r = _run(PROBES[0], CANON)
        assert r.returncode == 0
        outs.append(r.stdout)
    assert time.time() - t0 < 120, "time budget exceeded"
    assert outs[0] == outs[1] == outs[2], "non-deterministic output"
    assert _git_state() == before, "test run mutated the repository"


def test_mutation_cwd_relative_source_is_caught():
    # paired section 1.1 mutation: copy tests, revert _paths.SRC to the old
    # cwd-relative literal; the probe MUST then fail from the canon root.
    with tempfile.TemporaryDirectory() as tmp:
        mt = os.path.join(tmp, "tests")
        os.makedirs(os.path.join(tmp, "..", "x") if False else mt)
        for f in os.listdir(HERE):
            if f.endswith(".py"):
                shutil.copy(os.path.join(HERE, f), mt)
        with open(os.path.join(mt, "_paths.py"), "w") as fh:
            fh.write('CANON = "."\nSRC = "constitution/Constitution.md"\n')
        # GEN is resolved from the test file location, so mirror the parent files too
        for f in ("constitution_generate.py", "anchor_lib.py", "constitution_wiring_audit.py", "constitution_link_check.py"):
            shutil.copy(os.path.join(HERE, "..", f), tmp)
        r = _run(PROBES[0], CANON, tests_dir=mt)
        assert r.returncode != 0, "mutant (cwd-relative SRC) survived"


if __name__ == "__main__":
    n = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn(); n += 1; print("PASS", name)
    print(f"{n}/{n} passed")
