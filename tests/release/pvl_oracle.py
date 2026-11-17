#!/usr/bin/env python3
"""tests/release/pvl_oracle.py -- a second, independent implementation of the verification-line grammar of
scripts/validation/check_provisional_verification_lines.py (CON-423 r5), for the property test.

It shares no code with the checker: each field is one regular expression written from the grammar in
docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md section 2, and every reference is resolved by its own small code.
It reads one LINE (not a body: the line model is tested by tests/release/pvl_linemodel.py).

API: accepts(line, ctx) -> bool, ctx a dict with keys root (a real directory or None), items ({id: status}), item_id,
created (date or None), today (date), window (int days), targets (set of (kind, id) or None).
Self-check: python3 -I tests/release/pvl_oracle.py --selftest WORKDIR builds the fixture root of pvl_fixture.py under
WORKDIR and asserts that the golden line is accepted and that each golden-bad line (one defect each) is refused, so a
blind oracle (accepting everything or nothing) fails before any harness trusts it. Prints `ORACLE-SELFTEST good=1
bad=N wrong=K` and exits 0 when K is 0, 1 otherwise, 64 on a usage error.
"""
import datetime
import os
import re

FIELD = r"(?:: | )"
SEP = r"(?: -- | \u2014 )"
LINE = re.compile(
    r"\*\*Verification:\*\* provisional(?: \(section 11\.4\.290\))?"
    + SEP + r"job" + FIELD + r"(?P<job>.*?)"
    + SEP + r"checks" + FIELD + r"(?P<checks>.*?)"
    + SEP + r"layer" + FIELD + r"(?P<layer>.*?)"
    + SEP + r"target" + FIELD + r"(?P<target>.*?)"
    + SEP + r"artifact" + FIELD + r"(?P<artifact>.*?)"
    + SEP + r"due" + FIELD + r"(?P<due>[^ ]*)"
    + r"(?:" + SEP + r"note" + FIELD + r"(?P<note>.*))?", re.S)

P = r"[A-Za-z0-9_.+-]+"
PATH = r"%s(?:/%s)*" % (P, P)
INT = r"(?:0|[1-9][0-9]{0,9})"
WORD = r"[A-Za-z0-9_.:/+-]{1,64}"
INVOC = re.compile(r"(?P<env>(?:[A-Z_][A-Z0-9_]{0,63}=\S+ )*)(?P<run>bash|sh|python3 -I|python3) (?P<script>%s)(?P<args>(?: \S+)*)" % PATH)
TRACKER = re.compile(r"[A-Z][A-Z0-9]{1,15}-[0-9]{1,9}")
RESULT = re.compile(r"(?P<subj>\S+)(?P<terms>(?: (?:pass|fail|skip|killed|survived|rc|verdict)=\S+)+)")
LAYERS = {"user-visible", "runtime", "artifact", "source", "host-only", "live-target", "gate-logic"}
TTERM = re.compile(r"host|repo checkout|scratch clone|remote (?P<r>[a-z0-9_]{1,64})"
                   r"|(?P<k>board|device|container|vm|runner) (?P<i>[A-Za-z0-9][A-Za-z0-9._:-]{0,63})")
ATERM = re.compile(r"main|main@[0-9a-f]{7,64}|commit [0-9a-f]{7,64}|merge [0-9a-f]{7,64}|tag [A-Za-z0-9][A-Za-z0-9._-]{0,63}")
DUE = re.compile(r"(\d{4})-(\d\d)-(\d\d)(T(\d\d):(\d\d)(:(\d\d))?(Z|[+-]\d\d:\d\d)?)?")


def _ascii(s):
    return all(0x20 <= ord(c) <= 0x7E for c in s)


def _under(root, rel, want_file):
    if root is None:
        return None
    if rel == ".":
        return None if want_file else root
    if not re.fullmatch(PATH, rel) or ".." in rel.split("/") or "." in rel.split("/"):
        return None
    real = os.path.realpath(root + "/" + rel)
    if not real.startswith(root + os.sep):
        return None
    if want_file:
        return real if os.path.isfile(real) else None
    return real if os.path.lexists(real) and os.path.exists(real) else None


def _mentions(path, word):
    with open(path, "rb") as fh:
        data = fh.read(4 * 1024 * 1024).decode("utf-8", "replace")
    i = data.find(word)
    edge = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")
    while i >= 0:
        before = data[i - 1] if i > 0 else ""
        after = data[i + len(word)] if i + len(word) < len(data) else ""
        if before not in edge and after not in edge:
            return True
        i = data.find(word, i + 1)
    return False


def _val(root, script, v):
    return bool(re.fullmatch(INT, v) or _under(root, v, False) or (re.fullmatch(WORD, v) and _mentions(script, v)))


def _job(v, ctx, subj):
    if TRACKER.fullmatch(v):
        ok = v != ctx["item_id"] and ctx["items"].get(v) in ("Queued", "In progress", "Operator-blocked")
        if ok:
            subj.add(v)
        return ok
    root = ctx["root"]
    if root is None:
        return False
    for inv in v.split("; "):
        m = INVOC.fullmatch(inv)
        if not m:
            return False
        script = m.group("script")
        real = _under(root, script, True)
        if not real:
            return False
        exts = (".py",) if m.group("run").startswith("python3") else (".sh", ".bash")
        if not any(script.endswith(e) for e in exts):
            return False
        subj.add(script)
        for e in m.group("env").split(" "):
            if not e:
                continue
            name, _, val = e.partition("=")
            if not _mentions(real, name) or not _val(root, real, val):
                return False
        args = m.group("args")[1:].split(" ") if m.group("args") else []
        for a in args:
            if re.fullmatch(INT, a):
                continue
            om = re.fullmatch(r"(-[A-Za-z]|--[a-z][a-z0-9-]*)(=(.+))?", a)
            if a.startswith("-"):
                if not om or not _mentions(real, om.group(1)):
                    return False
                if om.group(3) is not None and not _val(root, real, om.group(3)):
                    return False
                continue
            if _under(root, a, False):
                continue
            if "/" in a or a.startswith("."):
                return False
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]{0,63}", a) and re.search(r"\d", a) and _mentions(real, a):
                subj.add(a)
                continue
            return False
    return True


def _checks(v, subj):
    for res in v.split("; "):
        m = RESULT.fullmatch(res)
        if not m or m.group("subj") not in subj:
            return False
        seen = []
        for t in m.group("terms").split(" ")[1:]:
            k, _, val = t.partition("=")
            seen.append(k)
            if k == "verdict":
                if val not in ("PASS", "FAIL", "BLIND", "SKIP"):
                    return False
            elif not re.fullmatch(INT, val) or (k == "rc" and int(val) > 255):
                return False
        if len(seen) != len(set(seen)) or not set(seen) & {"pass", "fail", "skip", "killed", "survived"}:
            return False
    return True


def _layer(v):
    ws = v.split(" plus ")
    return all(w in LAYERS for w in ws) and len(set(ws)) == len(ws)


def _target(v, ctx):
    ts = v.split(", ")
    if len(set(ts)) != len(ts):
        return False
    for t in ts:
        m = TTERM.fullmatch(t)
        if not m:
            return False
        if m.group("r") and not _under(ctx["root"], "upstreams/" + m.group("r") + ".sh", True):
            return False
        if m.group("k"):
            if ctx["targets"] is None or (m.group("k"), m.group("i")) not in ctx["targets"]:
                return False
    return True


def _artifact(v):
    ts = v.split(", ")
    if len(set(ts)) != len(ts):
        return False
    for t in ts:
        if not ATERM.fullmatch(t):
            return False
        if t.startswith("tag ") and not re.search(r"\d", t[4:]):
            return False
    return True


def _due(v, ctx):
    m = DUE.fullmatch(v)
    if not m or ctx["created"] is None:
        return False
    try:
        d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if m.group(4):
            h, mi = int(m.group(5)), int(m.group(6))
            s = int(m.group(8)) if m.group(8) else 0
            if h > 23 or mi > 59 or s > 59:
                return False
            z = m.group(9)
            if z and z != "Z":
                zh, zm = int(z[1:3]), int(z[4:6])
                if zh > 23 or zm > 59:
                    return False
    except ValueError:
        return False
    return ctx["created"] <= d <= ctx["today"] + datetime.timedelta(days=ctx["window"])


def accepts(line, ctx):
    if len(line) > 4096:
        return False
    m = LINE.fullmatch(line)
    if not m:
        return False
    g = m.groupdict()
    for k in ("job", "checks", "layer", "target", "artifact", "due"):
        if not g[k] or not _ascii(g[k]) or " -- " in g[k] or " \u2014 " in g[k]:
            return False
    if g["note"] is not None and (not _ascii(g["note"]) or not re.search(r"[A-Za-z0-9]", g["note"])):
        return False
    subj = set()
    return (_job(g["job"], ctx, subj) and _checks(g["checks"], subj) and _layer(g["layer"]) and _target(g["target"], ctx)
            and _artifact(g["artifact"]) and _due(g["due"], ctx))


def _selftest(work):
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import pvl_fixture as F
    fx = F.make_root(work)
    bad = [F.line(job="TBD"), F.line(job="CON-778"), F.line(job="bash tests/x.sh", checks="tests/x.sh pass=1"),
           F.line(checks="tests/t.sh"), F.line(layer="somewhere"), F.line(target="board T9"),
           F.line(artifact="HEAD"), F.line(due="2026-10-31"), F.line(due="2027-01-16"), F.line(note="?"),
           F.line(target="h\u043est"), F.line() + ".", F.line().replace(" -- checks", " -- layer: x -- checks", 1)]
    wrong = 0
    if not accepts(F.line(), fx):
        wrong += 1
        print("ORACLE-SELFTEST-WRONG golden line refused")
    for b in bad:
        if accepts(b, fx):
            wrong += 1
            print("ORACLE-SELFTEST-WRONG accepted %r" % b)
    print("ORACLE-SELFTEST good=1 bad=%d wrong=%d" % (len(bad), wrong))
    return 0 if wrong == 0 else 1


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3 or sys.argv[1] != "--selftest":
        sys.stderr.write("usage: pvl_oracle.py --selftest WORKDIR\n")
        sys.exit(64)
    sys.exit(_selftest(sys.argv[2]))
