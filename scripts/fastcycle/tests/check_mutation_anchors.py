#!/usr/bin/env python3
"""check_mutation_anchors.py -- STATIC anchor-drift census of the fastcycle paired-mutation suites.

Why (carry review round 1, F2): two mutation anchors had drifted from the code they mutate (R5-F2c in
test_fastcycle_r6_mutations.sh; mutation B of test_baseline_replay_worktree_cleanup.sh). The runners do refuse a
drifted anchor, but only when they REACH that mutant -- for the r6 runner that is up to ~1.5 h into the run. This
census applies every anchor pair of every mutant (in order, exactly as the runners do) to the files under test in
memory, in about a second, and fails on the first look instead of at the end.

What it reads:
  * test_fastcycle_r6_mutations.sh -- its embedded Python up to `def replica():` (the MUTS / EQUIVS / CONTROLS
    definitions only; nothing is run), executed with FC / TESTS set.
  * test_baseline_replay_worktree_cleanup.sh -- every `mk_mutant NAME (rel $'old' $'new')...` call, decoded with the
    bash $'...' escapes it uses.
A pair drifts when its anchor occurs != 1 times in the (progressively mutated) target -- the runners' own rule.

NOT covered (stated so the census is never cited for them; CON-120 review F112-1): every other paired-mutation suite,
in particular test_select_sample_r5_regression.sh (its run_mutant anchors on cycle/select_sample.py). Those suites
refuse a drifted anchor only when their own mutation leg reaches it ("could not be applied (anchor drifted)"), so the
evidence for their anchors is that leg's output, never this census.

Control needles (§11.4.273): a pair whose anchor is a string known ABSENT must be counted as drift, and the first
MUTS pair must be found; otherwise the instrument is BLIND and the census exits 2 (never a clean 0).

Usage: check_mutation_anchors.py [--fc DIR] [--tests DIR]   (defaults: this file's ../ and ./)
Exit: 0 every anchor matches exactly once; 1 at least one drifted (each named on a DRIFT line); 2 blind / unreadable.
Read-only: it never writes a file.
"""
import os
import re
import sys


def _arg(name, default):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        print("usage: --fc DIR / --tests DIR need a value", file=sys.stderr)
        sys.exit(2)
    return default


HERE = os.path.dirname(os.path.abspath(__file__))
FC = os.path.abspath(_arg("--fc", os.path.dirname(HERE)))
TESTS = os.path.abspath(_arg("--tests", HERE))
RUNNER = os.path.join(TESTS, "test_fastcycle_r6_mutations.sh")
CLEANUP = os.path.join(TESTS, "test_baseline_replay_worktree_cleanup.sh")


def target_path(rel):
    # the census file is mutated in the r6 replica as tests/check_safepath_census.py
    if rel.startswith("tests/"):
        return os.path.join(TESTS, rel[len("tests/"):])
    return os.path.join(FC, rel)


def apply(rel, pairs, cache):
    """the runners' rule: each anchor, in order, must occur exactly once in the progressively mutated text"""
    p = target_path(rel)
    if p not in cache:
        cache[p] = open(p).read()
    src = cache[p]
    for i, (old, new) in enumerate(pairs):
        n = src.count(old)
        if n != 1:
            return "pair %d of %s: anchor matched %d times: %r" % (i, rel, n, old[:80])
        src = src.replace(old, new, 1)
    return None


def load_runner():
    t = open(RUNNER).read()
    a = t.index("<<'PYEOF'\n") + len("<<'PYEOF'\n")
    b = t.index("\ndef replica():", a)
    g = {"__name__": "anchor_census"}
    saved = sys.argv
    sys.argv = ["runner", FC, TESTS]
    try:
        exec(compile(t[a:b], RUNNER, "exec"), g)
    finally:
        sys.argv = saved
    return g["MUTS"], g["EQUIVS"]


_ESC = {"n": "\n", "t": "\t", "\\": "\\", "'": "'", '"': '"', "r": "\r", "a": "\a", "e": "\x1b"}


def bash_ansi_c(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s) and s[i + 1] in _ESC:
            out.append(_ESC[s[i + 1]]); i += 2
        else:
            out.append(c); i += 1
    return "".join(out)


TOKEN = re.compile(r"(cycle/\S+|lib/\S+)|\$'((?:\\.|[^'\\])*)'")


def load_cleanup():
    t = open(CLEANUP).read()
    muts = []
    for m in re.finditer(r"^\s*if mk_mutant (\w+) (.*?); then", t, re.S | re.M):
        toks = [(a or None, None if a else bash_ansi_c(b)) for a, b in TOKEN.findall(m.group(2))]
        groups, cur = {}, None
        for path, lit in toks:
            if path:
                cur = path; groups.setdefault(cur, [])
            elif cur is not None:
                groups[cur].append(lit)
        for rel, lits in groups.items():
            if len(lits) % 2:
                muts.append(("cleanup-" + m.group(1), rel, None))
            else:
                muts.append(("cleanup-" + m.group(1), rel, list(zip(lits[0::2], lits[1::2]))))
    return muts


def main():
    try:
        muts, equivs = load_runner()
        cmuts = load_cleanup()
    except (OSError, ValueError, KeyError, SyntaxError) as e:
        print("BLIND: cannot read the mutation suites: %r" % (e,))
        return 2
    # control needles: an absent anchor IS drift; the first real anchor IS found
    if apply(muts[0][1], [("\x00anchor-census-needle-never-present\x00", "")], {}) is None:
        print("BLIND: the absent-anchor needle was not reported as drift")
        return 2
    if apply(muts[0][1], muts[0][2][:1], {}) is not None:
        print("BLIND: the first MUTS anchor (%s) is not found -- wrong tree?" % muts[0][0])
        return 2
    if not cmuts:
        print("BLIND: no mk_mutant call parsed from %s" % CLEANUP)
        return 2
    drift, n = [], 0
    for row in list(muts) + list(equivs):
        mid, rel, pairs = row[0], row[1], row[2]
        n += len(pairs)
        why = apply(rel, pairs, {})
        if why:
            drift.append((mid, why))
    for mid, rel, pairs in cmuts:
        if pairs is None:
            drift.append((mid, "odd number of $'...' literals for %s (parse error)" % rel))
            continue
        n += len(pairs)
        why = apply(rel, pairs, {})
        if why:
            drift.append((mid, why))
    for mid, why in drift:
        print("DRIFT %s: %s" % (mid, why))
    print("SUMMARY mutants=%d equivs=%d cleanup=%d pairs=%d drift=%d needle=ok"
          % (len(muts), len(equivs), len(cmuts), n, len(drift)))
    return 1 if drift else 0


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:  # noqa: BLE001 -- an instrument crash is BLIND (2), never read as drift (1) or clean (0)
        print("BLIND: the census crashed: %r" % (e,))
        rc = 2
    sys.exit(rc)
