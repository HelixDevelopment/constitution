"""RED controls for the fixture self-check (round 9): each control breaks one invariant of
tests/workable_items/secret_shape_fixtures.py in a temporary copy and requires the self-check to exit 1;
the unmutated copy must exit 0. Prints one line per control and a RESULT line; exit 0 only when every
control behaves.

usage: selfcheck_red.py FIXTURES_PY
EVIDENCE CLASS  gate-logic only (section 11.4.289)."""
import os
import subprocess
import sys
import tempfile

(path,) = sys.argv[1:]
src = open(path, encoding="utf-8").read()
CONTROLS = [
    ("unmutated", None, None, 0),
    ("duplicate-label", "    ('r9-adopt-lr1-prefix-joined-head',",
     "    ('r9-adopt-rv10-omicron-short-key', 'sessi\\u03bfn=' + V8, \"hit\"),\n    ('r9-adopt-lr1-prefix-joined-head',", 1),
    ("hit-row-without-rules", "    'r9-adopt-lr1-prefix-joined-head': ", "    'r9-adopt-lr1-prefix-joined-headZZ': ", 1),
    ("reviewer-negatives-short", "\ndef selfcheck():", "\nR9_NEG.pop()\n\ndef selfcheck():", 1),
]
bad = 0
with tempfile.TemporaryDirectory() as d:
    for name, old, new, want in CONTROLS:
        s = src
        if old is not None:
            if s.count(old) != 1:
                print("STALE %s: occurs %d times" % (name, s.count(old)))
                bad += 1
                continue
            s = s.replace(old, new)
        p = os.path.join(d, "fixtures_%s.py" % name.replace("-", "_"))
        open(p, "w", encoding="utf-8").write(s)
        r = subprocess.run([sys.executable, "-I", p], capture_output=True, text=True)
        last = (r.stdout.strip().splitlines() or [""])[-1]
        ok = r.returncode == want and last.startswith("RESULT ")  # a crash is not a check
        print("%s %s rc=%d want=%d | %s" % ("OK" if ok else "BAD", name, r.returncode, want, last))
        bad += 0 if ok else 1
print("RESULT controls=%d bad=%d" % (len(CONTROLS), bad))
sys.exit(1 if bad else 0)
