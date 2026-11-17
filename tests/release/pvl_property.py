#!/usr/bin/env python3
"""tests/release/pvl_property.py -- the closed-world property test of
scripts/validation/check_provisional_verification_lines.py (CON-423 r5).

Usage: python3 -I tests/release/pvl_property.py CHECKER WORKDIR [SEED [N]]   (default seed 290423, N 3000)
1. GENERATE: N random sentences of the grammar over the fixture of tests/release/pvl_fixture.py (every rule of
   docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md section 2 has a generator branch). Each must be accepted by the
   checker AND by the independent oracle tests/release/pvl_oracle.py (completeness: the checker refuses no sentence).
2. PERTURB: every sentence is changed in 6 random ways (insert, delete or replace one character from a pool of ASCII
   and non-ASCII code points, swap two fields, change the case of one letter, put a vocabulary word of another script
   or field in place of a word). For every result the checker and the oracle must agree.
3. CLOSED WORLD: accepted by the checker => accepted by the oracle (the oracle reads the grammar only), counted over 1
   and 2; any line the checker accepts that the oracle refuses is a hole.
Output: PROP-FAIL lines (at most 40), then
`PROPERTY seed=S sentences=N perturbed=P agree=A agree_accepted=B checker_only=X oracle_only=Y sentences_refused=Z`
(B: perturbed lines both accept, so the perturbations reach both verdicts). Exit 0 when X, Y
and Z are 0; 1 otherwise; 2 when the checker cannot be loaded. The same seed gives the same lines (deterministic).
"""
import datetime
import importlib.util
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvl_fixture as F  # noqa: E402
import pvl_oracle  # noqa: E402

V = F.VOCAB
POOL = ([chr(c) for c in range(0x20, 0x7F)] + ["—", "–", " ", "​", "⁠", "е", "а",
        "ѕ", "ο", "－", "　", " ", "\u001c", "\t", "\r", "é", "\U0001F170", "ㅤ",
        "﻿", "‮"])


def sentence(r):
    """One random sentence of the grammar."""
    subjects = []
    if r.random() < 0.12:
        tid = r.choice(V["trackers"])
        job, subjects = tid, [tid]
    else:
        invs = []
        for _ in range(r.choice((1, 1, 1, 2, 3))):
            script = r.choice(sorted(V["scripts"]))
            runner = V["scripts"][script]
            if runner == "python3":
                runner = r.choice(("python3", "python3 -I"))
            elif r.random() < 0.2:
                runner = "sh"
            words = []
            for _ in range(r.choice((0, 0, 1, 2))):
                words.append("%s=%s" % (r.choice(V["env"][script]), val(r, script)))
            words += [runner, script]
            subjects.append(script)
            for _ in range(r.choice((0, 1, 2, 3))):
                k = r.random()
                if k < 0.3:
                    o = r.choice(V["options"][script])
                    words.append(o if r.random() < 0.6 or o.startswith("-") and len(o) == 2 else o + "=" + val(r, script))
                elif k < 0.55:
                    s = r.choice(V["selectors"][script])
                    words.append(s)
                    subjects.append(s)
                elif k < 0.8:
                    words.append(r.choice(V["paths"]))
                else:
                    words.append(str(r.choice((0, 1, 7, 42, 9999999999))))
            invs.append(" ".join(words))
        job = "; ".join(invs)
    results = []
    for subj in r.sample(subjects, k=r.randint(1, len(set(subjects)))) if subjects else []:
        keys = r.sample(["pass", "fail", "skip", "killed", "survived"], k=r.randint(1, 3))
        if r.random() < 0.4:
            keys.append("rc")
        if r.random() < 0.4:
            keys.append("verdict")
        r.shuffle(keys)
        terms = []
        for k in keys:
            if k == "rc":
                terms.append("rc=%d" % r.choice((0, 1, 255)))
            elif k == "verdict":
                terms.append("verdict=" + r.choice(("PASS", "FAIL", "BLIND", "SKIP")))
            else:
                terms.append("%s=%d" % (k, r.choice((0, 1, 3, 120))))
        results.append(subj + " " + " ".join(terms))
    checks = "; ".join(dict.fromkeys(results))
    layer = " plus ".join(r.sample(["user-visible", "runtime", "artifact", "source", "host-only", "live-target",
                                    "gate-logic"], k=r.randint(1, 3)))
    tpool = ["host", "repo checkout", "scratch clone"] + ["remote " + x for x in V["remotes"]] + [
        "%s %s" % t for t in sorted(F.TARGETS)]
    target = ", ".join(r.sample(tpool, k=r.randint(1, 3)))
    hexv = lambda: "".join(r.choice("0123456789abcdef") for _ in range(r.randint(7, 40)))
    apool = ["main", "main@" + hexv(), "commit " + hexv(), "merge " + hexv(), "tag v%d.%d" % (r.randint(0, 99), r.randint(0, 9))]
    artifact = ", ".join(r.sample(apool, k=r.randint(1, 2)))
    d = F.CREATED + datetime.timedelta(days=r.randint(0, (F.TODAY - F.CREATED).days + F.WINDOW))
    due = d.isoformat()
    if r.random() < 0.3:
        due += "T%02d:%02d" % (r.randint(0, 23), r.randint(0, 59))
        if r.random() < 0.5:
            due += ":%02d" % r.randint(0, 59)
        if r.random() < 0.5:
            due += r.choice(("Z", "+01:00", "-05:30", "+23:59"))
    sep = r.choice((" -- ", " — "))
    colon = r.choice((": ", " "))
    head = "**Verification:** provisional" + r.choice(("", " (section 11.4.290)"))
    parts = ["%s%s%s" % (k, colon if r.random() < 0.8 else r.choice((": ", " ")), v)
             for k, v in zip(F.ORDER, (job, checks, layer, target, artifact, due))]
    if r.random() < 0.25:
        parts.append("note " + r.choice(("scheduled by the operator", "see CON-777 -- nightly", "x1")))
    return head + sep + sep.join(parts)


def val(r, script):
    k = r.random()
    if k < 0.4:
        return str(r.choice((0, 3, 60)))
    if k < 0.7:
        return r.choice([p for p in V["paths"] if p != "."])
    return r.choice(V["words"][script])


def perturb(r, s):
    k = r.randrange(6)
    i = r.randrange(len(s))
    if k == 0:
        return s[:i] + r.choice(POOL) + s[i:]
    if k == 1:
        return s[:i] + s[i + 1:]
    if k == 2:
        return s[:i] + r.choice(POOL) + s[i + 1:]
    if k == 3:
        sep = " — " if " — " in s else " -- "
        p = s.split(sep)
        if len(p) > 3:
            a, b = r.sample(range(1, len(p)), 2)
            p[a], p[b] = p[b], p[a]
        return sep.join(p)
    if k == 4:
        letters = [j for j, c in enumerate(s) if c.isalpha()]
        j = r.choice(letters)
        return s[:j] + s[j].swapcase() + s[j + 1:]
    words = s.split(" ")
    j = r.randrange(len(words))
    pool = sum(V["options"].values(), []) + sum(V["selectors"].values(), []) + sum(V["words"].values(), []) + \
        sorted(V["scripts"]) + V["paths"] + V["trackers"] + ["host", "main", "pass=1", "rc=0", "plus", "CON-778"]
    words[j] = r.choice(pool)
    return " ".join(words)


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: pvl_property.py CHECKER WORKDIR [SEED [N]]\n")
        return 2
    seed = int(argv[3]) if len(argv) > 3 else 290423
    n = int(argv[4]) if len(argv) > 4 else 3000
    try:
        spec = importlib.util.spec_from_file_location("pvl_checker", argv[1])
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
    except Exception as exc:  # noqa: BLE001
        print("PROPERTY-BLIND cannot load the checker: %s" % exc)
        return 2
    os.makedirs(argv[2], exist_ok=True)
    fx = F.make_root(argv[2])
    ctx = F.checker_ctx(m, fx)
    r = random.Random(seed)
    shown = agree = c_only = o_only = refused = perturbed = both_accept = 0

    def show(msg):
        nonlocal shown
        if shown < 40:
            print(msg)
        shown += 1

    for _ in range(n):
        s = sentence(r)
        got = m.check_line(s, ctx)
        if got is not None or not pvl_oracle.accepts(s, fx):
            refused += 1
            show("PROP-FAIL sentence refused (checker: %s; oracle: %s): %r" % (got, pvl_oracle.accepts(s, fx), s[:200]))
        for _ in range(6):
            t = perturb(r, s)
            perturbed += 1
            c, o = m.check_line(t, ctx) is None, pvl_oracle.accepts(t, fx)
            if c == o:
                agree += 1
                both_accept += c
            elif c:
                c_only += 1
                show("PROP-FAIL checker accepts, oracle refuses (a hole): %r" % t[:200])
            else:
                o_only += 1
                show("PROP-FAIL oracle accepts, checker refuses (%s): %r" % (m.check_line(t, ctx), t[:200]))
    print("PROPERTY seed=%d sentences=%d perturbed=%d agree=%d agree_accepted=%d checker_only=%d oracle_only=%d "
          "sentences_refused=%d" % (seed, n, perturbed, agree, both_accept, c_only, o_only, refused))
    return 0 if c_only == o_only == refused == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
