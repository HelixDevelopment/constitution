#!/usr/bin/env python3
"""Round 12 RED/GREEN driver for the network-spawn gate (channel_census.py netgate).

Usage: run_red.py CENSUS_PY FIXTURE_DIR REPO_DIR OUT_FILE

Runs CENSUS_PY netgate on every fixture of the round-11 reviewer (50 scripts: 47 that must be a finding, three
that must pass), on the four unmodified release scripts (REAL_SCRIPTS, must pass) and on the reviewer's added-line
mutants RM30, RM30b, RM31, RM32, RM33, RM34 applied to a copy of the four release scripts: 57 cases. Prints one line per case and a summary; exit 0 when every case has the expected
verdict, 1 otherwise. A hermetic run: python3 -I, a fixed environment, no network.
"""
import os
import shutil
import subprocess
import sys
import tempfile

CLEAN = {"CTRL_NEG_clean", "G19_jq_free", "G28_rcnet_tempenv_secret"}
ANCHOR = '  RMAIN[$r]="$t"\n'
ADDED = {
    "RM30": '  command -p git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n',
    "RM30b": '  command -p git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :; hash -r\n',
    "RM31": '  "git" fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n',
    "RM32": '  >/dev/null 2>&1 git fetch -q --no-tags "$r" refs/heads/main || :\n',
    "RM33": '  git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n',
    "RM34": '  /usr/bin/git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n',
}
SCRIPTS = ["scripts/release/derive_release_facts.sh", "scripts/release/redact_cut.sh",
           "scripts/release/tag_and_release.sh", "scripts/release_publish_gitea.sh"]
ENV = {"PATH": os.environ.get("RED_GATE_PATH", "/usr/local/bin:/usr/bin:/bin"), "LANG": "C.UTF-8"}


def gate(census, paths):
    p = subprocess.run([sys.executable, "-I", census, "netgate"] + paths, capture_output=True, text=True,
                       env=ENV, timeout=120)
    return p.returncode, (p.stdout + p.stderr).strip().replace("\n", " | ")


def main():
    census, fxdir, repo, out = sys.argv[1:5]
    rows, bad = [], 0
    for f in sorted(os.listdir(fxdir)):
        if not f.endswith(".sh"):
            continue
        name = f[:-3]
        rc, o = gate(census, [os.path.join(fxdir, f)])
        want = 0 if name in CLEAN else 1
        ok = rc == want
        bad += not ok
        rows.append("%-5s %-34s want_rc=%d rc=%d :: %s" % ("OK" if ok else "MISS", name, want, rc, o[:220]))
    rc0, o0 = gate(census, [os.path.join(repo, s) for s in SCRIPTS])
    ok = rc0 == 0
    bad += not ok
    rows.append("%-5s %-34s want_rc=0 rc=%d :: %s" % ("OK" if ok else "MISS", "REAL_SCRIPTS", rc0, o0[:220]))
    tmp = tempfile.mkdtemp(prefix="red_rm.")
    try:
        for mid, line in ADDED.items():
            d = os.path.join(tmp, mid)
            for s in SCRIPTS:
                os.makedirs(os.path.dirname(os.path.join(d, s)), exist_ok=True)
                shutil.copy(os.path.join(repo, s), os.path.join(d, s))
            p = os.path.join(d, "scripts/release/tag_and_release.sh")
            t = open(p).read()
            if t.count(ANCHOR) != 1:
                rows.append("ERROR %s anchor count %d" % (mid, t.count(ANCHOR)))
                bad += 1
                continue
            open(p, "w").write(t.replace(ANCHOR, ANCHOR + line))
            rc, o = gate(census, [os.path.join(d, s) for s in SCRIPTS])
            ok = rc == 1
            bad += not ok
            rows.append("%-5s %-34s want_rc=1 rc=%d :: %s" % ("OK" if ok else "MISS", mid, rc, o[:220]))
    finally:
        shutil.rmtree(tmp)
    n = len(rows)
    rows.append("SUMMARY cases=%d expected=%d unexpected=%d" % (n, n - bad, bad))
    open(out, "w").write("\n".join(rows) + "\n")
    print("\n".join(rows[-1:]))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
