#!/usr/bin/env python3
"""enumerate_decision_mutants.py -- mechanical decision-point mutation census.

Purpose : CON-158 / CON-147 round 6 (review of fsfix5, section 11.4.274): the
          class "a reviewer mutant of the guarded script survives" recurred in
          rounds 3, 4 and 5 because each round's paired-mutant table was
          written by hand. This tool enumerates the decision points of a fixed
          set of target scripts that are matched by its closed list of
          single-edit operators (the operators below), runs each mutant against the target's
          regression test in a scratch copy of scripts/, and reports each
          mutant KILLED, SURVIVED, or EQUIVALENT (only with a recorded proof in
          the equivalence ledger). Scope, stated honestly (CON-159, review
          fsfix6 m1): "survived=0" means no OPERATOR-generated survivor, not
          that every decision point is covered. Real decision-point mutants no
          operator generates exist (negating a bare `if cmd; then`, an awk field
          shift, a str.replace count of 0, `head -N`, dropping a `|| assign`);
          they were killed by hand-written tests, and are not proved by this tool.
Targets : (closed list, stated scope)
          meta         scripts/validation/meta_test_verification.sh, whole file;
                       test: test_meta_test_verification_r1_regression.sh with
                       MTV_REG_PINS_ONLY=1 (the paired-mutant section skipped:
                       this tool supplies the mutants).
          host_guard   scripts/fastcycle/lib/host_guard.sh, whole file;
                       test: scripts/fastcycle/tests/test_host_guard_red.sh (sh).
          host_report  scripts/fastcycle/host/host_report.py, ONLY the function
                       _read_nproc_soft (the CON-147 change); the rest of the
                       file is not in scope; test:
                       test_host_report_thread_limit_r1_regression.sh.
Operators: drop `|| return N`; flip `return 0/1`; flip `exit N`; drop a `trap`
          line; drop one signal of a multi-signal trap; drop a redirect
          (`2>/dev/null`, `2>&1`, `> "file"`); shift a numeric comparison
          bound by +-1 (`NF >= 4`, `>= 4`); change `>=`/`<=` to the strict
          form; flip `=`/`!=` and `==`/`!=`; flip `-eq -ne -ge -gt -le -lt`;
          flip `-n`/`-z`; drop `!`; drop `&& continue` / `|| continue`;
          swap `ok`/`notok` calls; flip `is None`/`is not None`, `in`/`not in`;
          shift an integer index or slice bound by +-1. Comment lines are
          skipped. One mutant = one edit at one occurrence.
Verdicts: KILLED (test exit != 0), KILLED-TIMEOUT (the test did not finish in
          the target's budget), SURVIVED (test exit 0), EQUIVALENT (survived and
          its key is in the ledger with a proof), INVALID (the mutant does not
          parse; not counted). A target whose UNMUTATED copy does not pass is
          BLIND (control needle failed) and no mutant of it is judged.
          A ledger entry whose key is no longer generated is STALE (the ledger
          must not rot).
Ledger  : scripts/validation/decision_mutants_equivalent.tsv, columns
          key, target, rule, original line (stripped), proof.
Usage   : python3 -I enumerate_decision_mutants.py [--target NAME]... [--list]
            [--only KEY]... [--out FILE] [--root DIR]
          python3 -I enumerate_decision_mutants.py --selftest
          Exit 0 when no mutant SURVIVED, no target was BLIND and no ledger
          entry is STALE; 1 otherwise; 2 on usage or setup error. The last line
          is the summary line. One mutant runs at a time (host safety).
"""
import argparse
import ast
import hashlib
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LEDGER_REL = "scripts/validation/decision_mutants_equivalent.tsv"

TARGETS = {
    "meta": {
        "path": "scripts/validation/meta_test_verification.sh",
        "test": ["bash", "scripts/validation/test_meta_test_verification_r1_regression.sh"],
        "env": {"MTV_REG_PINS_ONLY": "1"},
        "parse": ["bash", "-n"],
        "timeout": 900,
        "lines": None,
    },
    "host_guard": {
        "path": "scripts/fastcycle/lib/host_guard.sh",
        "test": ["sh", "scripts/fastcycle/tests/test_host_guard_red.sh"],
        "env": {},
        "parse": ["sh", "-n"],
        "timeout": 600,
        "lines": None,
    },
    "host_report": {
        "path": "scripts/fastcycle/host/host_report.py",
        "test": ["bash", "scripts/fastcycle/tests/test_host_report_thread_limit_r1_regression.sh"],
        "env": {},
        "parse": None,  # py_compile
        "timeout": 600,
        "lines": ("function", "_read_nproc_soft"),
    },
}


# --- operators: (name, compiled regex, function(match) -> list of replacement strings)
def _alts(*xs):
    return lambda m: list(xs)


def _num_shift(m):
    n = int(m.group(2))
    out = [m.group(1) + str(n + 1)]
    if n > 0:
        out.append(m.group(1) + str(n - 1))
    return out


def _exit_flip(m):
    n = int(m.group(1))
    return ["exit %d" % (1 if n == 0 else 0)] + (["exit 1"] if n not in (0, 1) else [])


def _idx_shift(m):
    n = int(m.group(1))
    out = ["[%d" % (n + 1)]
    if n > 0:
        out.append("[%d" % (n - 1))
    return out


RULES = [
    ("drop_or_return", re.compile(r"\s*\|\|\s*return\s+\d+"), _alts("")),
    ("return_flip", re.compile(r"\breturn [01]\b(?![.\d])"),
     lambda m: ["return 1" if m.group(0).endswith("0") else "return 0"]),
    ("exit_flip", re.compile(r"\bexit (\d+)\b"), _exit_flip),
    ("drop_continue", re.compile(r"\s*(?:&&|\|\|)\s*continue\b"), _alts("")),
    ("drop_redirect", re.compile(r"\s+2>/dev/null|\s+2>&1|\s+2?>\s*\"[^\"]+\""), _alts("")),
    ("num_bound_shift", re.compile(r"((?:NF|len\([^)]*\)|\$#)\s*(?:>=|<=|==|>|<|-ge|-gt|-le|-lt|-eq)\s*)(\d+)"),
     _num_shift),
    ("strict_bound", re.compile(r"(?<![<>=!])>=(?!=)|(?<![<>=!])<=(?!=)"),
     lambda m: [m.group(0)[0]]),
    ("shell_test_cmp", re.compile(r"(?<=\s)-(eq|ne|ge|gt|le|lt)(?=\s)"),
     lambda m: [{"eq": "-ne", "ne": "-eq", "ge": "-gt", "gt": "-ge", "le": "-lt", "lt": "-le"}[m.group(1)]]),
    ("str_cmp_flip", re.compile(r"(?<=\S)\s(?:!=|=)\s(?=\S)"),
     lambda m: [" = " if "!" in m.group(0) else " != "]),
    ("py_eq_flip", re.compile(r"\s(?:==|!=)\s"), lambda m: [" != " if "==" in m.group(0) else " == "]),
    ("nz_flip", re.compile(r"\[ -([nz]) "), lambda m: ["[ -%s " % ("z" if m.group(1) == "n" else "n")]),
    ("drop_bang", re.compile(r"(?:\[\[?|\bif|\bwhile|&&|\|\|)\s+!\s"),
     lambda m: [m.group(0).replace("!", "", 1).replace("  ", " ")]),
    ("ok_notok_swap", re.compile(r"(?<![\w-])(notok|ok)(?= \")"),
     lambda m: ["ok" if m.group(1) == "notok" else "notok"]),
    ("is_none_flip", re.compile(r"\bis not None\b|\bis None\b"),
     lambda m: ["is None" if "not" in m.group(0) else "is not None"]),
    ("in_flip", re.compile(r"(?<!not)\s+in\s+\(|\s+not in\s+\("),
     lambda m: [" in (" if "not" in m.group(0) else " not in ("]),
    ("index_shift", re.compile(r"\[(\d+)(?=[\]:])"), _idx_shift),
    ("drop_guard_conjunct", re.compile(r"\[\[? -[defnrsxz] [^\]]*\]\]? && "), _alts("")),
    ("drop_finish", re.compile(r"(?<![\w-])finish(?=\s*(?:;|$))"), _alts(":")),
]
# Rules whose match must lie OUTSIDE double quotes (double quotes hold messages;
# awk programs are single-quoted and stay in scope).
DQ_SENSITIVE = {"num_bound_shift", "strict_bound", "shell_test_cmp", "str_cmp_flip", "py_eq_flip",
                "in_flip", "is_none_flip", "index_shift", "exit_flip", "return_flip"}
# str_cmp_flip is a shell `test` operator: only on a line with `[ ` or `[[ `.
SHELL_TEST_ONLY = {"str_cmp_flip"}


def code_regions(line):
    """(end of code before a trailing comment, set of offsets inside double quotes)."""
    sq = dq = False
    dqpos = set()
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and not sq:
            if dq:
                dqpos.update((i, i + 1))
            i += 2
            continue
        if ch == "'" and not dq:
            sq = not sq
        elif ch == '"' and not sq:
            dq = not dq
            dqpos.add(i)
        elif ch == "#" and not sq and not dq and (i == 0 or line[i - 1] in " \t"):
            return i, dqpos
        elif dq:
            dqpos.add(i)
        i += 1
    return len(line), dqpos


def is_comment(line):
    s = line.lstrip()
    return s.startswith("#") and not s.startswith("#!")


def trap_mutants(line):
    """drop the whole trap line; drop one signal of a multi-signal trap."""
    out = []
    m = re.match(r"^(\s*)trap\s+(\S+|'[^']*')\s+([A-Z ]+)\s*$", line.rstrip("\n"))
    if re.match(r"^\s*trap\s", line):
        indent = re.match(r"^(\s*)", line).group(1)
        out.append(("drop_trap", indent + ":\n"))
    if m:
        sigs = m.group(3).split()
        if len(sigs) > 1:
            for s in sigs:
                rest = " ".join(x for x in sigs if x != s)
                out.append(("drop_trap_signal", "%strap %s %s\n" % (m.group(1), m.group(2), rest)))
    # an inline `trap '' A B C;` inside a function body
    for im in re.finditer(r"trap '' ([A-Z]+(?: [A-Z]+)+);", line):
        sigs = im.group(1).split()
        for s in sigs:
            rest = " ".join(x for x in sigs if x != s)
            out.append(("drop_trap_signal", line[:im.start()] + "trap '' %s;" % rest + line[im.end():]))
        out.append(("drop_trap_inline", line[:im.start()] + line[im.end():].lstrip()))
    return out


def line_mutants(line):
    """All single-edit mutants of one line: list of (rule, new_line)."""
    if is_comment(line) or not line.strip():
        return []
    out = trap_mutants(line)
    end, dqpos = code_regions(line)
    shell_test = ("[ " in line[:end]) or ("[[ " in line[:end])
    for name, rx, gen in RULES:
        if name in SHELL_TEST_ONLY and not shell_test:
            continue
        for m in rx.finditer(line):
            if m.start() >= end or (name in DQ_SENSITIVE and m.start() in dqpos):
                continue
            for rep in gen(m):
                new = line[:m.start()] + rep + line[m.end():]
                if new != line:
                    out.append((name, new))
    seen, uniq = set(), []
    for r, n in out:
        if n not in seen:
            seen.add(n)
            uniq.append((r, n))
    return uniq


def mutant_key(target, lineno_text, rule, new_text, occ):
    h = hashlib.sha256("\0".join([target, lineno_text.strip(), rule, new_text.strip(), str(occ)]).encode())
    return h.hexdigest()[:12]


def scope_lines(text, spec):
    lines = text.splitlines(keepends=True)
    if spec is None:
        return range(len(lines))
    kind, name = spec
    assert kind == "function"
    tree = ast.parse(text)
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == name:
            body0 = node.body[0]
            start = node.body[1].lineno if (isinstance(body0, ast.Expr) and isinstance(
                getattr(body0, "value", None), ast.Constant) and len(node.body) > 1) else body0.lineno
            return range(start - 1, node.end_lineno)
    raise SystemExit("function %s not found" % name)


def enumerate_target(name, root):
    t = TARGETS[name]
    text = open(os.path.join(root, t["path"]), encoding="utf-8").read()
    lines = text.splitlines(keepends=True)
    muts, count = [], {}
    for i in scope_lines(text, t["lines"]):
        for rule, new in line_mutants(lines[i]):
            base = (lines[i].strip(), rule, new.strip())
            occ = count.get(base, 0)
            count[base] = occ + 1
            key = mutant_key(name, lines[i], rule, new, occ)
            mt = "".join(lines[:i]) + new + "".join(lines[i + 1:])
            muts.append({"key": key, "target": name, "lineno": i + 1, "rule": rule,
                         "old": lines[i].rstrip("\n"), "new": new.rstrip("\n"), "text": mt})
    return muts


def read_ledger(root):
    p = os.path.join(root, LEDGER_REL)
    led = {}
    if not os.path.exists(p):
        return led
    for n, raw in enumerate(open(p, encoding="utf-8"), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        f = raw.rstrip("\n").split("\t")
        if len(f) != 5 or not f[4].strip():
            raise SystemExit("ledger line %d malformed (want 5 tab-separated fields, proof non-empty)" % n)
        led[f[0]] = {"target": f[1], "rule": f[2], "old": f[3], "proof": f[4]}
    return led


def run_bounded(cmd, cwd, env, timeout):
    p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = p.communicate()
        return None, out.decode("utf-8", "replace")


def parses(t, path, cwd):
    if t["parse"] is None:
        r = subprocess.run([sys.executable, "-I", "-m", "py_compile", path], cwd=cwd,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        r = subprocess.run(t["parse"] + [path], cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0


def make_scratch(root, base):
    files = subprocess.run(["git", "-C", root, "ls-files", "-z", "--", "scripts"], check=True,
                           stdout=subprocess.PIPE).stdout.split(b"\0")
    for f in files:
        if not f:
            continue
        rel = f.decode()
        src = os.path.join(root, rel)
        if not os.path.isfile(src) or os.path.islink(src):
            if os.path.islink(src):
                os.makedirs(os.path.dirname(os.path.join(base, rel)), exist_ok=True)
                os.symlink(os.readlink(src), os.path.join(base, rel))
            continue
        dst = os.path.join(base, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)


def main(argv):
    ap = argparse.ArgumentParser(description="decision-point mutation census (see the module docstring)")
    ap.add_argument("--target", action="append", choices=sorted(TARGETS))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--out")
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    targets = a.target or ["meta", "host_guard", "host_report"]
    ledger = read_ledger(a.root)
    allm = []
    for name in targets:
        allm.extend(enumerate_target(name, a.root))
    keys = {m["key"] for m in allm}
    if len(keys) != len(allm):
        print("setup error: mutant keys are not unique")
        return 2
    if a.list:
        for m in allm:
            print("%s\t%s:%d\t%s\t%s\t->\t%s" % (m["key"], m["target"], m["lineno"], m["rule"],
                                                m["old"].strip(), m["new"].strip()))
        print("=== decision mutants: listed=%d ===" % len(allm))
        return 0
    if a.only:
        allm = [m for m in allm if m["key"] in a.only]
    res = {"KILLED": 0, "KILLED-TIMEOUT": 0, "SURVIVED": 0, "EQUIVALENT": 0, "INVALID": 0, "BLIND": 0,
           "STALE": 0}
    rows = []
    outfh = open(a.out, "w", encoding="utf-8") if a.out else None

    def emit(line):
        print(line, flush=True)
        if outfh:
            outfh.write(line + "\n")
            outfh.flush()
    tmpbase = tempfile.mkdtemp(prefix="decision_mutants.")
    try:
        # named "constitution": some tests resolve the tree as <parent>/constitution/scripts
        # (the layout of a consumer's constitution submodule), measured on host_report's test.
        work = os.path.join(tmpbase, "constitution")
        make_scratch(a.root, work)
        env = dict(os.environ)
        for name in targets:
            t = TARGETS[name]
            tpath = os.path.join(work, t["path"])
            orig = open(tpath, encoding="utf-8").read()
            e = dict(env, **t["env"])
            t0 = time.monotonic()
            rc, out = run_bounded(t["test"], work, e, t["timeout"])
            if rc != 0:
                emit("BLIND\t%s\tcontrol needle: the unmutated copy's test exit %r: %s"
                     % (name, rc, out.strip().splitlines()[-1:] if out.strip() else ""))
                res["BLIND"] += 1
                continue
            emit("CONTROL\t%s\tunmutated copy passes (%.0f s)" % (name, time.monotonic() - t0))
            for m in [x for x in allm if x["target"] == name]:
                with open(tpath, "w", encoding="utf-8") as fh:
                    fh.write(m["text"])
                try:
                    if not parses(t, tpath, work):
                        v = "INVALID"
                    else:
                        rc, out = run_bounded(t["test"], work, e, t["timeout"])
                        if rc is None:
                            v = "KILLED-TIMEOUT"
                        elif rc != 0:
                            v = "KILLED"
                        elif m["key"] in ledger:
                            v = "EQUIVALENT"
                        else:
                            v = "SURVIVED"
                finally:
                    with open(tpath, "w", encoding="utf-8") as fh:
                        fh.write(orig)
                res[v] += 1
                emit("%s\t%s\t%s:%d\t%s\t%s\t->\t%s" % (v, m["key"], name, m["lineno"], m["rule"],
                                                       m["old"].strip(), m["new"].strip()))
        gen = {m["key"] for m in enumerate_all(a.root, targets)}
        for k, ent in ledger.items():
            if ent["target"] in targets and k not in gen:
                res["STALE"] += 1
                emit("STALE\t%s\t%s\tledger entry no longer generated: %s" % (k, ent["target"], ent["old"]))
    finally:
        shutil.rmtree(tmpbase, ignore_errors=True)
    summary = "=== decision mutants: " + " ".join("%s=%d" % (k.lower(), v) for k, v in res.items()) + " ==="
    emit(summary)
    if outfh:
        outfh.close()
    return 0 if res["SURVIVED"] == 0 and res["BLIND"] == 0 and res["STALE"] == 0 else 1


def enumerate_all(root, targets):
    out = []
    for n in targets:
        out.extend(enumerate_target(n, root))
    return out


def selftest():
    fails, passes = [], []

    def chk(name, cond):
        print(("ok " if cond else "NOT ok ") + name)
        (passes if cond else fails).append(name)
    sample = [
        '    mkdir -p "${r}/x" || return 1\n',
        "trap 'exit 143' TERM\n",
        "cleanup() { trap '' HUP INT TERM; rm -rf -- \"${W:?}\"; }\n",
        "  _v=$(awk '/^Max processes[ \\t]/ && NF >= 4 { print $3; exit }' \"$f\" 2>/dev/null)\n",
        '        [ "$(basename -- "${s}")" = "${T}" ] && continue\n',
        '    [ "${fail}" = 0 ] && exit 0\n',
        "                    if len(parts) >= 4:\n",
        "                        return parts[2]\n",
        "    if c.count(old) != 1:\n",
        "# a comment || return 1\n",
        '    notok "x"\n',
        '    if [ -n "$a" ] && [ "$b" -ge 1 ]; then\n',
    ]
    sample += [
        'clamp() { # value is >=1 here\n',
        '    [ "$req" -ge 1 ] || die "requested N must be >= 1"\n',
        '    parts = line.split()\n',
        '    R1="$(build_root m1)" || { notok "x"; finish; }\n',
        '    [ -n "${W:-}" ] && [ -d "${W}" ] && rm -rf -- "${W:?}"\n',
    ]
    got = {i: line_mutants(l) for i, l in enumerate(sample)}
    rules = {i: {r for r, _ in v} for i, v in got.items()}
    chk("drop_or_return on '|| return 1'", "drop_or_return" in rules[0])
    chk("drop_trap on a trap line", "drop_trap" in rules[1])
    chk("drop_trap_signal x3 on the inline cleanup trap",
        sum(1 for r, _ in got[2] if r == "drop_trap_signal") == 3)
    chk("num_bound_shift NF>=4 -> 5 and 3",
        {n.strip() for r, n in got[3] if r == "num_bound_shift"} >= {
            l.strip() for l in (sample[3].replace("NF >= 4", "NF >= 5"), sample[3].replace("NF >= 4", "NF >= 3"))})
    chk("drop_redirect on 2>/dev/null", "drop_redirect" in rules[3])
    chk("drop_continue and str_cmp_flip on the skip line", {"drop_continue", "str_cmp_flip"} <= rules[4])
    chk("exit_flip on exit 0", any(n.strip().endswith("exit 1") for r, n in got[5] if r == "exit_flip"))
    chk("python len bound shift and strict bound", {"num_bound_shift", "strict_bound"} <= rules[6])
    chk("index_shift on parts[2]", any("parts[3]" in n for r, n in got[7] if r == "index_shift"))
    chk("py_eq_flip on != 1", any("== 1" in n for r, n in got[8] if r == "py_eq_flip"))
    chk("comment lines skipped", got[9] == [])
    chk("ok_notok_swap", any(n.strip() == 'ok "x"' for r, n in got[10]))
    chk("nz_flip and shell_test_cmp", {"nz_flip", "shell_test_cmp"} <= rules[11])
    chk("no mutant inside a trailing comment", got[12] == [])
    chk("no strict_bound inside a double-quoted message",
        all("must be > 1" not in n for _, n in got[13]) and any(r == "shell_test_cmp" for r, _ in got[13]))
    chk("no str_cmp_flip on a python assignment", "str_cmp_flip" not in rules[14])
    chk("drop_finish on '; finish;'", "drop_finish" in rules[15])
    chk("drop_guard_conjunct on '[ -n ... ] &&' and '[ -d ... ] &&'",
        sum(1 for r, _ in got[16] if r == "drop_guard_conjunct") == 2)
    chk("every mutant differs from its line", all(n != sample[i] for i, v in got.items() for _, n in v))
    k1 = mutant_key("t", sample[0], "drop_or_return", "x", 0)
    chk("keys are stable", k1 == mutant_key("t", sample[0], "drop_or_return", "x", 0))
    chk("keys depend on the occurrence", k1 != mutant_key("t", sample[0], "drop_or_return", "x", 1))
    src = 'def f():\n    """doc."""\n    if a >= 4:\n        return 1\n\ndef g():\n    return b >= 2\n'
    rng = scope_lines(src, ("function", "f"))
    chk("function scope covers f's body only (lines 3..4)", list(rng) == [2, 3])
    d = tempfile.mkdtemp(prefix="dm_selftest.")
    try:
        os.makedirs(os.path.join(d, "scripts", "validation"))
        p = os.path.join(d, LEDGER_REL)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("# header\nabc\tmeta\tdrop_continue\tline\tproof text\n")
        chk("ledger parses", read_ledger(d) == {"abc": {"target": "meta", "rule": "drop_continue",
                                                        "old": "line", "proof": "proof text"}})
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("abc\tmeta\tdrop_continue\tline\t \n")
        try:
            read_ledger(d)
            chk("a ledger entry without a proof is refused", False)
        except SystemExit:
            chk("a ledger entry without a proof is refused", True)
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print("=== decision mutants selftest: pass=%d fail=%d ===" % (len(passes), len(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
