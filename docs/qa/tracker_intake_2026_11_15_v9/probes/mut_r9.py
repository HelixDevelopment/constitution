"""Reviewer r9 mutants. Each: exactly-once text replacement in a copy; run the vehicle's own harness/suites."""
import os, subprocess, sys, tempfile

ROOT = sys.argv[1]
OUT = sys.argv[2]
LINT = os.path.join(ROOT, "scripts/workable-items/intake_lint.py")
REMINT = os.path.join(ROOT, "scripts/workable-items/remint_ids.py")
CENSUS = os.path.join(ROOT, "docs/qa/tracker_intake_2026_11_15_v8/tools/secret_class_census.py")
env = dict(os.environ, TMPDIR="/mnt/DATA1TB/claude-work/tmp")

LM = [
    ("RV1 Cf strip narrowed to ZWSP", 'unicodedata.category(ch) != "Cf")', 'ch != "\\u200b")'),
    ("RV2 escape view without NFKC", "d = _clean(unicodedata.normalize(\"NFKC\", _ESC.sub(_unescape, t)))", "d = _clean(_ESC.sub(_unescape, t))"),
    ("RV3 \\x escapes not decoded", "u[0-9A-Fa-f]{4}|x[0-9A-Fa-f]{2}|", "u[0-9A-Fa-f]{4}|"),
    ("RV4 min value length 8->9", "    if len(v) < 8:\n        return False\n    if _MASK.match(v):", "    if len(v) < 9:\n        return False\n    if _MASK.match(v):"),
    ("RV5 mask regex unanchored at end", 'r"^[xX*.#\\s-]+$"', 'r"^[xX*.#\\s-]+"'),
    ("RV6 percent not a reference start", '_REF_START = "$<{%"', '_REF_START = "$<{"'),
    ("RV7 placeholder suffix -here dropped", "[-_.](?:here|goes[-_]here|placeholder)$", "[-_.](?:goes[-_]here|placeholder)$"),
    ("RV8 URL digit-start password treated as port", 'if re.match(r"\\d+/", v):', 'if re.match(r"\\d+", v):'),
    ("RV9 pgpass wildcard port dropped", r"[^\s:#]+:(?:\d{1,5}|\*):", r"[^\s:#]+:(?:\d{1,5}):"),
    ("RV10 Greek omicron unfolded", '"\\u03b1": "a", "\\u03bf": "o",', '"\\u03b1": "a",'),
    ("RV11 upper-case identifier key needs >8 chars", "(key.isupper() and len(key) > 3)", "(key.isupper() and len(key) > 8)"),
    ("RV12 tab allowed inside a value", 'if any(c in v for c in " \\t") and not allow_space:', 'if any(c in v for c in " ") and not allow_space:'),
    ("RV13 percent view only when at start", "if SECRET_DECODE_PERCENT and _PCT.search(t):", "if SECRET_DECODE_PERCENT and _PCT.match(t):"),
    ("RV14 stripe restricted-key prefix dropped", r"\b[rs]k_(?:live|test)_", r"\bsk_(?:live|test)_"),
    ("RV15 telegram id min 8->9 digits", r"\b\d{8,10}:AA", r"\b\d{9,10}:AA"),
    ("RV16 xml close-tag check removed", '        if m.group("ctag") != m.group("otag"):\n            continue\n        if credential_value(tier, v, "<"):',
     '        if credential_value(tier, v, "<"):'),
    ("RV17 flag usage placeholder accepts lower case", 'if re.fullmatch(r"[A-Z][A-Z0-9_]*", v):', 'if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", v):'),
    ("RV18 code-attr exclusion ignores digits", "(_CODE_ATTR.match(v) and not any(c.isdigit() for c in v))", "_CODE_ATTR.match(v)"),
    ("RV19 short-key '>' guard dropped", '    if tier == "short" and v[0] in ".>":\n        return False\n', ""),
    ("RV20 single-quoted $literal allowed for double quotes", "if not (quote == \"'\" and v[0] == \"$\"", "if not (quote in \"'\\\"\" and v[0] == \"$\""),
]
RM = [
    ("RW1 next free id skips one", "start = max(num(i) for i in T if rx.fullmatch(i)) + 1", "start = max(num(i) for i in T if rx.fullmatch(i)) + 2"),
    ("RW2 collision with target id not refused", "                if new in T:\n                    refuse(", "                if new in T and False:\n                    refuse("),
    ("RW3 foreign span upper bound exclusive", "return n in nums or any(lo <= n <= hi for lo, hi in spans)", "return n in nums or any(lo <= n < hi for lo, hi in spans)"),
    ("RW4 path check ignores slash before id", '    if before == "/" or after[:1] == "/" or re.match(r"\\.\\w", after):', '    if after[:1] == "/" or re.match(r"\\.\\w", after):'),
    ("RW5 token boundary allows trailing dash", 'tok = re.compile(r"(?<![\\w-])" + p + r"-([0-9]+)\\b(?!-)")', 'tok = re.compile(r"(?<![\\w-])" + p + r"-([0-9]+)\\b")'),
    ("RW6 width from last own id", 'width = len(own[0].rsplit("-", 1)[1])', 'width = 2'),
    ("RW7 vehicle-stay collision not refused", "                if new in stay:\n", "                if new in stay and False:\n"),
    ("RW8 between-range connector dropped", r"(\s+(?i:and)\s+)", r"(\s+(?i:andx)\s+)"),
]


def mk(src, old, new, dst):
    s = open(src).read()
    n = s.count(old)
    if n != 1:
        return "STALE(%d)" % n
    open(dst, "w").write(s.replace(old, new))
    return None


def run(cmd, extra_env, timeout=3600):
    e = dict(env, **extra_env)
    p = subprocess.run(cmd, env=e, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    return p.returncode, p.stdout.decode(errors="replace")


with tempfile.TemporaryDirectory(dir="/mnt/DATA1TB/claude-work/tmp") as td, open(OUT, "w") as out:
    for mid, old, new in LM:
        dst = os.path.join(td, "lint_%s.py" % mid.split()[0])
        st = mk(LINT, old, new, dst)
        if st:
            out.write("%s %s\n" % (st, mid)); out.flush(); continue
        rc, log = run(["bash", "tests/workable_items/test_intake_lint.sh"],
                      {"INTAKE_LINT": dst, "INTAKE_LINT_EXTRA": "--no-selfcheck", "INTAKE_LINT_FAILFAST": "1"})
        ff = next((l for l in log.splitlines() if l.startswith("FAIL")), "")[:90]
        rc2, log2 = run(["python3", "-I", CENSUS, dst], {}, timeout=3600)
        last = log2.strip().splitlines()[-1][:80] if log2.strip() else ""
        rc3, nd = run(["python3", "-I", dst, "--db", os.path.join(td, "none.db"), "--ids", "X-1"], {})
        needle = "BLIND: control needle failed" in nd
        killed = rc != 0
        out.write("%s %s | suite rc=%d first=%s | census rc=%d %s | needle=%s\n" % (
            "KILLED" if (killed or rc2 != 0 or needle) else "SURVIVED", mid, rc, ff, rc2, last, needle))
        out.flush()
    for mid, old, new in RM:
        dst = os.path.join(td, "remint_%s.py" % mid.split()[0])
        st = mk(REMINT, old, new, dst)
        if st:
            out.write("%s %s\n" % (st, mid)); out.flush(); continue
        rc, log = run(["bash", "tests/workable_items/test_remint_ids.sh"], {"REMINT_IDS": dst, "REMINT_IDS_FAILFAST": "1"})
        ff = next((l for l in log.splitlines() if l.startswith("FAIL")), "")[:90]
        killed = rc == 1 and ff
        out.write("%s %s | suite rc=%d first=%s\n" % ("KILLED" if killed else "SURVIVED", mid, rc, ff))
        out.flush()
