#!/usr/bin/env bash
# fastcycle-timeout-s: 300
# =============================================================================
# test_fc_safepath_gitenv_scrub.sh -- CON-402 fallout (audit F1, 2026-11-16): the path-operation census
# tests/check_safepath_census.py models exactly ONE form of the CON-402 file-level git-env scrub per language and stays
# fail-closed for every other shape.
#
# Root cause measured on cc51c320 (3/3) and toggled: CON-402 (3281d92e) put `import os as _ge_os` + the environ.pop
# loop into cycle/fc_supervisor.py and the canonical `for _ge_v in ...; do unset "$_ge_v"; done` line into
# cycle/baseline_replay.sh; the census refused both (an unmodelled import; a non-literal NAME of unset), so
# test_fc_safepath_v4r12..v4r15 failed. Reverting the two scrub hunks made the census PASS again.
#
# [GE-real]   the files under test pass the census, with exactly one EXEMPT scrub row per file.
# [GE-py-*]   reshaped Python scrubs are refused: the import alone, a second body statement, a for-else, a
#             non-literal word list, a lowercase word, a displaced pair, another use of _ge_os, another pop.
# [GE-sh-*]   reshaped shell scrubs are refused: a $WORD, an extra unset operand, an indented line, a PROVED variable
#             or BASH among the words (desugared, then refused by the ordinary unset rules); a canonical line inside a
#             here-document body is text (no EXEMPT row).
# [GE-sh-attr-*, GE-sh-sole-*]  CON-450 round 2 (review F1-A, the class): an attribute on the helper variable (declare /
#             local / typeset -l -u -c -i, also through a quoted, escaped, brace or glob NAME) or any other use of
#             `_ge_v` makes the census refuse the desugar (the loop could unset other names; measured in bash).
# [GE-sh-gf-*] golden-false controls: an attribute on another plain NAME, IFS, `unset -v` of a non-proved name are
#             accepted (the new rules do not over-refuse, section 11.4.201(1)).
# [GE-sh-trailing-code, GE-sh-unset-trusted-*, GE-py-expr-first, GE-py-os-receiver]  review F1-B / F1-E / F1-C.
# [GE-mut-*]  paired mutants of the census itself (each must make at least one row above fail).
#
# Env: FC_CENSUS_UNDER_TEST / FC_SUP_UNDER_TEST / FC_BR_UNDER_TEST -- the files under test.
# Exit: 0 every row held; 1 otherwise.
# =============================================================================
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
CENSUS="${FC_CENSUS_UNDER_TEST:-$HERE/check_safepath_census.py}"
SUP="${FC_SUP_UNDER_TEST:-$FC/cycle/fc_supervisor.py}"
BR="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"
for f in "$CENSUS" "$SUP" "$BR"; do
  [ -f "$f" ] || { echo "NOT ok file under test not found: $f"; exit 1; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/fc_gescrub.XXXXXX")" || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf -- "${WORK:?}"' EXIT
python3 - "$CENSUS" "$SUP" "$BR" "${WORK:?}" <<'PY'
import os, re, subprocess, sys
census, sup, br, work = sys.argv[1:5]
SUP_SRC = open(sup, encoding="utf-8").read()
BR_SRC = open(br, encoding="utf-8").read()
CEN_SRC = open(census, encoding="utf-8").read()
fails = 0
passes = 0


def ok(m):
    global passes
    passes += 1
    print("ok " + m)


def bad(m):
    global fails
    fails += 1
    print("NOT ok " + m)


PY_PAIR = re.compile(r'^import os as _ge_os[^\n]*\nfor _ge_v in "([A-Z_ ]+)"\.split\(\): _ge_os\.environ\.pop\(_ge_v, None\)$', re.M)
SH_LINE = re.compile(r'^for _ge_v in ([A-Z_ ]+); do unset "\$_ge_v"; done; unset _ge_v[^\n]*$', re.M)
mp, ms = PY_PAIR.search(SUP_SRC), SH_LINE.search(BR_SRC)
if not mp or not ms:
    print("NOT ok control needle: the canonical scrub is not found in the files under test (py=%s sh=%s)" % (bool(mp), bool(ms)))
    sys.exit(1)
WORDS = mp.group(1)
PAIR = mp.group(0)
LINE = ms.group(0)


def run(cen, sup_text=None, br_text=None, tag="x"):
    s = os.path.join(work, tag + ".py")
    b = os.path.join(work, tag + ".sh")
    open(s, "w", encoding="utf-8").write(SUP_SRC if sup_text is None else sup_text)
    open(b, "w", encoding="utf-8").write(BR_SRC if br_text is None else br_text)
    p = subprocess.run([sys.executable, cen, "--sup", s, "--br", b], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def py_variant(new_pair):
    assert SUP_SRC.count(PAIR) == 1
    return SUP_SRC.replace(PAIR, new_pair)


def sh_variant(new_line):
    assert BR_SRC.count(LINE) == 1
    return BR_SRC.replace(LINE, new_line)


IMP = "import os as _ge_os"
POP = "_ge_os.environ.pop(_ge_v, None)"
LOOP = 'for _ge_v in "%s".split(): %s' % (WORDS, POP)
PY_CASES = {
    "GE-py-import-alone": IMP,
    "GE-py-second-stmt": 'for _ge_v in "%s".split():\n    %s\n    os.unlink("/fake/victim")' % (WORDS, POP),
    "GE-py-for-else": 'for _ge_v in "%s".split():\n    %s\nelse:\n    os.unlink("/fake/victim")' % (WORDS, POP),
    "GE-py-nonliteral": 'for _ge_v in " ".join(sys.argv).split(): ' + POP,
    "GE-py-lowercase": 'for _ge_v in "GIT_DIR fake_lower".split(): ' + POP,
    "GE-py-other-pop": 'for _ge_v in "%s".split(): _ge_os.environ.pop("GIT_DIR", None)' % WORDS,
    "GE-py-other-method": 'for _ge_v in "%s".split(): _ge_os.environ.clear(_ge_v, None)' % WORDS,
}
PY_CASES["GE-py-os-receiver"] = 'for _ge_v in "%s".split(): os.environ.pop(_ge_v, None)' % WORDS   # review F1-C (RM6)
PY_FULL = {   # whole-pair replacements (the import line included)
    "GE-py-displaced": "_FAKE_FIRST = 1\n" + IMP + "\n" + LOOP,
    "GE-py-later-use": IMP + "\n" + LOOP + "\n_ge_alias = _ge_os",
    "GE-py-second-pair": IMP + "\n" + LOOP + "\n" + IMP + "\n" + LOOP,
    "GE-py-other-module": "import shutil as _ge_os\n" + LOOP,
}
SH_CASES = {
    "GE-sh-dollar-word": 'for _ge_v in GIT_DIR $FAKE_NAME; do unset "$_ge_v"; done; unset _ge_v',
    "GE-sh-extra-operand": 'for _ge_v in GIT_DIR; do unset "$_ge_v" "$FAKE_NAME"; done; unset _ge_v',
    "GE-sh-indented": '  for _ge_v in GIT_DIR; do unset "$_ge_v"; done; unset _ge_v',
    "GE-sh-proved-word": 'for _ge_v in GIT_DIR _FC_TMPDIR; do unset "$_ge_v"; done; unset _ge_v',
    "GE-sh-bash-word": 'for _ge_v in GIT_DIR BASH; do unset "$_ge_v"; done; unset _ge_v',
    # review F1-B: code after `unset _ge_v` on the canonical line (the desugar would drop it from the analysis)
    "GE-sh-trailing-code": 'for _ge_v in GIT_DIR; do unset "$_ge_v"; done; unset _ge_v; rm -f "$FAKE_TARGET"',
}
WT = LINE.replace("for _ge_v in ", "for _ge_v in WT_PATH ", 1)
# id: (text inserted before the line, inside a function?, the line, True = refused by the NEW rule ("NOT desugared") /
#      a str = refused with that text in the output / False = golden-false, must be accepted)
SH_INSERT = {
    "GE-sh-attr-declare-l": ("declare -l _ge_v", False, WT, True),       # review S1 (same construction)
    "GE-sh-attr-local-l-func": ("local -l _ge_v", True, WT, True),       # review S13 (same construction)
    "GE-sh-attr-typeset-c": ("typeset -c _ge_v", False, LINE, True),
    "GE-sh-attr-declare-i": ("declare -i _ge_v", False, LINE, True),
    "GE-sh-attr-backslash": ("declare -l _ge\\_v", False, WT, True),
    "GE-sh-attr-dquote": ('declare -l "_ge"_v', False, WT, True),
    "GE-sh-attr-brace": ("declare -l _ge_{v,w}", False, WT, True),
    "GE-sh-attr-glob": ("declare -l _ge_?", False, WT, True),
    "GE-sh-sole-readonly": ("readonly _ge_v", False, LINE, True),
    "GE-sh-sole-assign": ("_ge_v=x", False, LINE, True),
    "GE-sh-unset-trusted-f": ("unset -f _fc_safe", False, LINE, "unset of the trusted function"),
    "GE-sh-unset-trusted-plain": ("unset _fc_safe", False, LINE, "unset of the trusted function"),
    "GE-sh-gf-other-attr": ("declare -l _rv_other", False, LINE, False),
    "GE-sh-gf-ifs": ("IFS=_", False, LINE, False),
    "GE-sh-gf-unset-v": ("unset -v _fc_safe", False, LINE, False),
}


def no_docstring_expr_first():
    """review F1-C (RM3): the module docstring replaced by an ordinary expression statement before the pair"""
    import ast
    t = ast.parse(SUP_SRC)
    d = t.body[0]
    assert isinstance(d, ast.Expr) and isinstance(d.value, ast.Constant) and isinstance(d.value.value, str)
    ls = SUP_SRC.split("\n")
    return "\n".join(ls[:d.lineno - 1] + ['len("x")'] + ls[d.end_lineno:])


def sh_insert(text, fn, line):
    body = text + "\n" + line
    return sh_variant(("_rvf() {\n%s\n}\n_rvf" % body) if fn else body)


def _refused(r):
    return r[0] == 1 and "VIOLATION" in r[1], "rc=%d %s" % (
        r[0], " | ".join(l for l in r[1].splitlines() if l.startswith("VIOLATION"))[:200])


def cases(cen):
    """[(name, thunk -> (held, detail))] -- every row of the suite, evaluated lazily"""
    out = []

    def real():
        rc, o = run(cen, tag="real")
        ex = [l for l in o.splitlines() if l.startswith("EXEMPT") and "git-env scrub" in l]
        return (rc == 0 and len(ex) == 2 and sum("fc_supervisor" in l or ".py:" in l for l in ex) == 1,
                "rc=%d scrub_rows=%d %s" % (rc, len(ex), " | ".join(l for l in o.splitlines() if l.startswith("VIOLATION"))[:300]))
    out.append(("GE-real", real))
    for k, v in PY_CASES.items():
        out.append((k, lambda k=k, v=v: _refused(run(cen, sup_text=py_variant(IMP + "\n" + v), tag=k))))
    for k, v in PY_FULL.items():
        out.append((k, lambda k=k, v=v: _refused(run(cen, sup_text=py_variant(v), tag=k))))
    out.append(("GE-py-expr-first", lambda: _refused(run(cen, sup_text=no_docstring_expr_first(), tag="expr-first"))))
    for k, v in SH_CASES.items():
        out.append((k, lambda k=k, v=v: _refused(run(cen, br_text=sh_variant(v), tag=k))))
    for k, (text, fn, line, want) in SH_INSERT.items():
        def t(k=k, text=text, fn=fn, line=line, want=want):
            rc, o = run(cen, br_text=sh_insert(text, fn, line), tag=k)
            if want is False:
                return rc == 0, "rc=%d (golden-false: must be accepted)" % rc
            needle = "NOT desugared" if want is True else want
            return rc == 1 and needle in o, "rc=%d refusal-reason-present=%s" % (rc, needle in o)
        out.append((k, t))

    def heredoc():   # a canonical line inside a here-document body is TEXT: no EXEMPT row, the census still passes
        hd = BR_SRC.rstrip("\n") + "\n: <<'FAKE_HD_END'\n" + LINE + "\nFAKE_HD_END\n"
        rc, o = run(cen, br_text=hd, tag="heredoc")
        ex = [l for l in o.splitlines() if l.startswith("EXEMPT") and "git-env scrub" in l]
        return rc == 0 and len(ex) == 2, "rc=%d scrub_rows=%d" % (rc, len(ex))
    out.append(("GE-sh-heredoc-text", heredoc))
    return out


def suite(cen, first=(), stop=False):
    """{case: (held, detail)}; stop=True returns at the first row that does not hold, trying the rows named in
    `first` first (any broken row kills a mutant; the order only saves time)"""
    res = {}
    cs = cases(cen)
    cs = [c for c in cs if c[0] in first] + [c for c in cs if c[0] not in first]
    for name, th in cs:
        res[name] = th()
        if stop and not res[name][0]:
            break
    return res


base = suite(census)
for k, (held, d) in base.items():
    (ok if held else bad)("[%s] %s" % (k, d))

# ---- paired mutants of the census (each must break at least one row) ----
MUTANTS = {
    "GE-mut-no-body-len": ("and not loop.orelse and len(loop.body) == 1 and isinstance(loop.body[0], ast.Expr)):",
                           "and not loop.orelse and isinstance(loop.body[0], ast.Expr)):"),
    "GE-mut-no-orelse": ("and not loop.orelse and len(loop.body) == 1", "and len(loop.body) == 1"),
    "GE-mut-no-word-check": ("    if not words or not all(_GE_WORD.match(w) for w in words):\n        return None\n", ""),
    "GE-mut-no-literal-iter": ("and not it.args and not it.keywords and isinstance(it.func.value, ast.Constant)\n            and isinstance(it.func.value.value, str)):",
                               "and not it.args and not it.keywords):"),
    "GE-mut-no-seed": ('    unmodelled = {"_ge_os"} if ge is not None else set()', "    unmodelled = set()"),
    "GE-mut-no-del": ("        del tree.body[ge:ge + 2]\n", ""),
    "GE-mut-anywhere": ("    imp, loop = body[i], body[i + 1]\n",
                        "    i = next((k for k in range(len(body) - 1) if isinstance(body[k], ast.Import)\n"
                        "              and body[k].names[0].asname == \"_ge_os\"), i)\n    imp, loop = body[i], body[i + 1]\n"),
    "GE-mut-sh-indent": ("""_GE_SH = re.compile(r'^for _ge_v in""", """_GE_SH = re.compile(r'^\\s*for _ge_v in"""),
    "GE-mut-sh-no-heredoc": ("        if m and no not in inside:", "        if m:"),
    "GE-mut-sh-drop-words": ('            out[no - 1] = "unset %s; unset _ge_v" % m.group(1)', '            out[no - 1] = "unset _ge_v"'),
    # reviewer-style mutants (not derived from a case written first)
    "GE-mut-any-module": ('len(imp.names) == 1 and imp.names[0].name == "os"', "len(imp.names) == 1"),
    "GE-mut-any-method": ('isinstance(c.func, ast.Attribute) and c.func.attr == "pop"', "isinstance(c.func, ast.Attribute)"),
    "GE-mut-pop-target": ("and len(c.args) == 2 and isinstance(c.args[0], ast.Name) and c.args[0].id == \"_ge_v\"",
                          "and len(c.args) == 2"),
}
MUTANTS.update({
    # CON-450 round 2 (review F1-A / F1-B / F1-C / F1-E): the new rules and the review's surviving mutants
    "GE-mut-blockers-ignored": ("    if ge_blockers:                                       # fail-closed",
                                "    if False:                                       # fail-closed"),
    "GE-mut-no-sole-use": ('        if no not in ge and "_ge_v" in raw and not _GE_SH.match(raw):',
                           '        if False:'),
    "GE-mut-no-attr-rule": ('        if not (letters & (_GE_ATTR | {"$"})):\n            continue',
                            '        if True:\n            continue'),
    "GE-mut-attr-name-exact": ('            if not _GE_NAME.match(nm) or nm == "_ge_v":', '            if nm == "_ge_v":'),
    "GE-mut-attr-any-name": ('            if not _GE_NAME.match(nm) or nm == "_ge_v":', '            if True:'),
    "GE-mut-attr-nameref-only": ('_GE_ATTR = set("lucin")', '_GE_ATTR = set("n")'),
    "GE-mut-unset-trusted": ('                    if _unq(o) in SH_TRUSTED_FUNCS:', '                    if False:'),
    "GE-mut-RM2-trailing-anything": ("unset _ge_v(?:[ \\t]+#.*)?$')", "unset _ge_v(?:.*)?$')"),
    "GE-mut-RM3-any-expr-first": ("    i = 1 if (body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant)\n"
                                  "              and isinstance(body[0].value.value, str)) else 0",
                                  "    i = 1 if (body and isinstance(body[0], ast.Expr)) else 0"),
    "GE-mut-RM6-any-receiver": ('and isinstance(c.func.value.value, ast.Name) and c.func.value.value.id == "_ge_os"',
                                'and isinstance(c.func.value.value, ast.Name)'),
})
KILLERS = {   # rows tried first (time only; any broken row kills)
    "GE-mut-blockers-ignored": ("GE-sh-attr-declare-l",), "GE-mut-no-sole-use": ("GE-sh-sole-readonly",),
    "GE-mut-no-attr-rule": ("GE-sh-attr-backslash",), "GE-mut-attr-name-exact": ("GE-sh-attr-backslash",),
    "GE-mut-attr-any-name": ("GE-sh-gf-other-attr",), "GE-mut-attr-nameref-only": ("GE-sh-attr-backslash",),
    "GE-mut-unset-trusted": ("GE-sh-unset-trusted-f",), "GE-mut-RM2-trailing-anything": ("GE-sh-trailing-code",),
    "GE-mut-RM3-any-expr-first": ("GE-py-expr-first",), "GE-mut-RM6-any-receiver": ("GE-py-os-receiver",),
}
for name, (old, new) in MUTANTS.items():
    n = CEN_SRC.count(old)
    if n != 1:
        bad("[%s] mutation anchor found %d times (expected 1) -- source drifted" % (name, n))
        continue
    mp_ = os.path.join(work, name + "_census.py")
    open(mp_, "w", encoding="utf-8").write(CEN_SRC.replace(old, new))
    r = suite(mp_, first=KILLERS.get(name, ()), stop=True)
    broken = sorted(k for k, (held, _d) in r.items() if not held)
    if broken:
        ok("[%s] KILLED by %s" % (name, ",".join(broken)))
    else:
        bad("[%s] SURVIVED: every row still holds with the mutant" % name)
print("SUMMARY pass=%d fail=%d" % (passes, fails))
sys.exit(1 if fails else 0)
PY
