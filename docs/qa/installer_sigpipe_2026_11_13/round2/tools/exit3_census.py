"""exit3_census.py LOG... — per run_all.sh log and per suite: the checks that expected exit 0 and got exit 3, and the
installer's free-space refusal text, where the suite kept it. A suite's lines end at its summary line
"<name>: PASS <n> FAIL <m>". Control needles: in each log the summary-line count must be at least one, and the
pattern for an exit-3 check must match the needle line below and not the negative needle, or the census is BLIND.
Exit 0 written, 3 blind.
"""
import re
import sys

SUMMARY = re.compile(r"^([A-Za-z0-9_.-]+): PASS (\d+) FAIL (\d+)$")
EXIT3 = re.compile(r"^\s*FAIL .*\(expected \[0\] got \[3\]\)$")
SPACE = "less than 1 GiB free on the project filesystem"

POS = "  FAIL fallback to second upstream exit 0 (expected [0] got [3])"
NEG = "  FAIL fallback to second upstream exit 0 (expected [0] got [1])"
if not EXIT3.match(POS) or EXIT3.match(NEG):
    print("BLIND: the exit-3 pattern fails its control needles")
    sys.exit(3)

blind = False
for path in sys.argv[1:]:
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    name = path.rsplit("/", 1)[-1]
    n3 = sp = 0
    rows, summaries = [], 0
    for line in lines:
        if EXIT3.match(line):
            n3 += 1
        if SPACE in line:
            sp += 1
        m = SUMMARY.match(line)
        if m:
            summaries += 1
            if n3 or sp:
                rows.append("  %-22s PASS %s FAIL %s; expected 0 got 3: %d; free-space refusal text: %d"
                            % (m.group(1), m.group(2), m.group(3), n3, sp))
            n3 = sp = 0
    if summaries == 0:
        blind = True
        print("%s: BLIND (no suite summary line)" % name)
        continue
    total3 = sum(int(r.split("got 3: ")[1].split(";")[0]) for r in rows)
    totalsp = sum(int(r.rsplit(": ", 1)[1]) for r in rows)
    print("%s: %d suites; checks that expected 0 and got 3: %d; free-space refusal text: %d"
          % (name, summaries, total3, totalsp))
    for r in rows:
        print(r)
sys.exit(3 if blind else 0)
