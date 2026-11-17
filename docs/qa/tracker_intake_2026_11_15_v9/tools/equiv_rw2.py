"""Equivalence evidence for the re-mint mutant RW2 (round 9, review r9 F4): the refusal "new id ... already
exists in the target" in make_plan cannot fire, so removing it (RW2: `if new in T and False:`) changes no
answer.

usage: equiv_rw2.py REMINT_IDS_PY [--cases N]

ARGUMENT  rx = <prefix>-[0-9]+ and every new id is "%s-%0*d" % (prefix, width, start + k), so every new id
  fullmatches rx. start = max(num(i) for i in T if rx.fullmatch(i)) + 1, so start + k is larger than the
  number of every target key that fullmatches rx. A target key equal to a new id would fullmatch rx and
  have the same number; there is none. A target key that does not fullmatch rx is a different string.
CHECK  The three source lines that compute width, start and the map are read from the tool by their exact
  text (each must occur once, else STALE, exit 2) and executed with the tool's own num() on N random cases:
  targets of mixed widths, other prefixes, prefixes that are a prefix of another ("C" and "CON"), and own
  lists of mixed widths. Every case must give no new id in T. A control needle runs the same lines with
  `+ 1` changed to `+ 0` (a start that can collide) and must find a collision, else the check is blind
  (exit 3). Exit 0: no new id in T on any case; 1: a collision (RW2 is not equivalent).
EVIDENCE CLASS  gate-logic only (section 11.4.289)."""
import random
import re
import sys

args = sys.argv[1:]
cases = 200000
if "--cases" in args:
    k = args.index("--cases")
    cases = int(args[k + 1])
    del args[k:k + 2]
(path,) = args
src = open(path, encoding="utf-8").read()
LINES = ('            width = len(own[0].rsplit("-", 1)[1])',
         '            start = max(num(i) for i in T if rx.fullmatch(i)) + 1',
         '            m = {o: "%s-%0*d" % (prefix, width, start + k) for k, o in enumerate(minted)}')
GUARD = '                if new in T:\n                    refuse('
for x in LINES + (GUARD, "def num(iid):\n    return int(iid.rsplit(\"-\", 1)[1])\n"):
    if src.count(x) != 1:
        print("STALE: %r occurs %d times" % (x[:60], src.count(x)))
        sys.exit(2)


def num(iid):
    return int(iid.rsplit("-", 1)[1])


CODE = compile("\n".join(x.strip() for x in LINES), "remint_ids.make_plan", "exec")
CTL = compile("\n".join(x.strip() for x in LINES).replace(") + 1", ") + 0"), "control", "exec")
rng = random.Random(20261115)


def case():
    prefix = rng.choice(["CON", "C", "WZ", "AB"])
    others = [p for p in ("CON", "C", "WZ", "AB", "CONX", "XCON") if p != prefix]
    T = set()
    for _ in range(rng.randint(1, 12)):
        n = rng.randint(0, 1200)
        w = rng.choice([1, 2, 3, 4])
        T.add("%s-%0*d" % (prefix, w, n))
    for _ in range(rng.randint(0, 5)):
        T.add("%s-%0*d" % (rng.choice(others), rng.choice([1, 3]), rng.randint(0, 5000)))
    own = sorted(("%s-%0*d" % (prefix, rng.choice([1, 2, 3, 4]), rng.randint(0, 1500))
                  for _ in range(rng.randint(1, 6))), key=num)
    minted = [o for o in own if rng.random() < 0.8] or own[:1]
    return prefix, T, own, minted


def run(code, prefix, T, own, minted):
    g = {"num": num, "rx": re.compile(re.escape(prefix) + r"-[0-9]+"), "prefix": prefix, "own": own,
         "minted": minted, "T": T, "max": max, "len": len, "enumerate": enumerate}
    exec(code, g)
    return any(new in T for new in g["m"].values())


ctl = sum(run(CTL, *case()) for _ in range(2000))
print("CONTROL needle (start = max + 0): collisions=%d %s" % (ctl, "ok" if ctl else "BLIND"))
if not ctl:
    sys.exit(3)
rng = random.Random(20261115)
bad = sum(run(CODE, *case()) for _ in range(cases))
print("RESULT cases=%d collisions=%d" % (cases, bad))
sys.exit(1 if bad else 0)
