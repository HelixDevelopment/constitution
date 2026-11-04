#!/usr/bin/env python3
"""units_pin_refresh.py -- compute (and optionally record) the BINARY_PINS.tsv row of the units helper.

r12 (ATM-1217 review G3). A source edit under units_helper/ changes the source hash, and on a reference toolchain
(one any pin row names) the gate refuses a source hash with no row. This tool is the one way to add the row:

  python3 lib/units_pin_refresh.py            # print the row for the current source and the go on PATH
  python3 lib/units_pin_refresh.py --write    # also replace this toolchain's row(s) in BINARY_PINS.tsv
  python3 lib/units_pin_refresh.py --once ... # one build instead of two (the mutant harness; no reproducibility proof)

It builds the helper TWICE, each time from an empty private GOCACHE/GOPATH/HOME, with the gate's own flags
(-trimpath -buildvcs=false CGO_ENABLED=0 -mod=vendor GOPROXY=off GOTOOLCHAIN=local, env -i, the gate's memory cap),
and refuses (exit 1) when the two binaries differ: a pin is only recorded for a reproducible build.
Exit: 0 row printed (and written), 1 build failed or not reproducible, 2 environment (no go, unreadable source).
Recording a new pin is a review act: the row names the binary every later gate run must equal.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import precheck_pack_run as m  # noqa: E402


def build(go, work):
    """One build into <work>/units from empty caches under <work>; -> sha256 of the binary."""
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.path.join(work, "home"),
           "GOCACHE": os.path.join(work, "gocache"), "GOPATH": os.path.join(work, "gopath"), "GOPROXY": "off",
           "GOTOOLCHAIN": "local", "GOFLAGS": "-mod=vendor", "CGO_ENABLED": "0", "GOENV": "off", "GOTELEMETRY": "off"}
    os.makedirs(env["HOME"])
    out = os.path.join(work, "units")
    argv = (m._cap_prefix(m.UNITS_BUILD_MEM_MIB) + ["env", "-i"] + ["%s=%s" % (k, env[k]) for k in sorted(env)]
            + [go, "build", "-trimpath", "-buildvcs=false", "-o", out, "."])
    p = subprocess.run(argv, cwd=m._UNITS_SRC, capture_output=True, timeout=m.UNITS_BUILD_TIMEOUT,
                       env=m._runner_env())
    if p.returncode != 0 or not os.path.isfile(out):
        raise RuntimeError("build failed (rc=%d): %s" % (p.returncode, m._txt(p.stderr)[:300]))
    return m._file_sha256(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--write", action="store_true", help="replace this toolchain's row(s) in BINARY_PINS.tsv")
    ap.add_argument("--once", action="store_true", help="one build (no reproducibility proof; test harness only)")
    a = ap.parse_args()
    go = shutil.which("go")
    if not go:
        print("units_pin_refresh: go is not on PATH", file=sys.stderr)
        return 2
    try:
        src = m._units_source_hash()
        ver, plat = m._go_toolchain(go)
    except (OSError, m._UnitsError) as exc:
        print("units_pin_refresh: %s" % exc, file=sys.stderr)
        return 2
    shas = []
    for _ in range(1 if a.once else 2):
        work = tempfile.mkdtemp(prefix="units-pin-")
        try:
            shas.append(build(go, work))
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
            print("units_pin_refresh: %s" % exc, file=sys.stderr)
            return 1
        finally:
            shutil.rmtree(work, ignore_errors=True)
    if len(set(shas)) != 1:
        print("units_pin_refresh: the build is not reproducible: %s" % " ".join(shas), file=sys.stderr)
        return 1
    row = "%s %s %s %s" % (src, ver, plat, shas[0])
    print(row)
    if a.write:
        path = os.path.join(m._UNITS_SRC, m.UNITS_PINS)
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
        keep = [ln for ln in lines if ln.startswith("#") or not ln.strip()
                or ln.split()[1:3] != [ver, plat]]
        with open(path + ".tmp", "w", encoding="utf-8") as fh:
            fh.write("\n".join(keep + [row]) + "\n")
        os.replace(path + ".tmp", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
