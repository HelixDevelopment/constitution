#!/usr/bin/env python3
"""cm_submodule_pin_not_downgraded_sites.py - site census and site-table lint for CM-SUBMODULE-PIN-NOT-DOWNGRADED.

CON-046 round 11 (CON-194; review r10 section 7, §11.4.276(C)/(E)(3)): the fixtures of the paired mutation test are
derived from a SITE TABLE, not chosen per reported site. A site is one exact-compare token (a shell test `[ ]` / `[[ ]]`,
a case statement or case arm, an awk comparison, a python comparison, strip(), `in`, startswith) or one character-set
token (IFS=, read -d '', awk -F, the \\036 / \\037 / \\0 separators, a ${var%%pattern} / ${var#pattern} / ${var//x/}
split, a NUL check, a `date` call) in the gate's code (from `set -uo pipefail` on) or in the hook.

Usage:
  cm_submodule_pin_not_downgraded_sites.py census <gate> <hook>
      print one line per site: <file>:<line> TAB <kind> TAB <token>
  cm_submodule_pin_not_downgraded_sites.py lint static <gate> <hook> <table> <test> <inventory>
  cm_submodule_pin_not_downgraded_sites.py lint dynamic <gate> <hook> <table> <test> <inventory> <dirs.tsv> <eqok>
      static:  S0 every row has 8 fields and a unique id; S1 every census site has exactly one row and every row is a
               census site (matched on line and token, the n-th equal token on a line by the nth column); S2 a row's
               anchor occurs in exactly one code line; S3 a data row (class sha, path, ident, date, num, text, charset)
               names vector keys that occur in the test's want (or `nc` with a reason saying "not constructible" or
               "equivalent") and at least one registered mutant or proof (an `nc` row may name `-`); S4 an internal
               row (rc, flag, mode, env, empty) names inventory ids that exist (a struct row: a case statement or loop test that
               decides nothing by itself names none, with a reason); S5 every named mutant / proof is
               registered in the test. Census needles (§11.4.201(7)(b)): known token counts on three known lines and on
               three fabricated lines; a wrong needle is a finding, so a blind census cannot pass.
      dynamic: every mutant a data row names was killed (it has a direction in dirs.tsv) and every proof passed.
Exit: 0 clean, 1 findings, 2 usage. Read-only. Deps: python3.
Table columns (TAB): id, anchor (a fixed string occurring in exactly one code line; ids H.. anchor in the hook), token,
nth, class, gen (vector keys, comma list; `nc`; or inventory ids for internal classes), mutants (comma list or -),
reason.
"""
import re, sys

SH = [('test2', r'\[\[ .+? \]\]'), ('test1', r'(?<![\[\w])\[ (?!\[)[^\n]*? \](?!\])'),
      ('case', r'\bcase "?\$[\w#?]+"? in'), ('ifs', r"\bIFS=(?:\$'[^']*'|)(?=\s)"), ('readd', r"-d ''"),
      ('pstrip', r'\$\{\w+(?:%%|##|%|#)[^}]*\}'), ('psub', r'\$\{\w+//[^}]*\}'),
      ('arm', r'(?:^\s+|\bin |;; )([-\w\'"*#$ ?|.]+?)\)(?= |$)')]
AWK = [('awkcmp', r'(?:\$\w+""|\$\w+|\bNF|\bNR|\bi)\s*(?:==|!=|<=|>=|>|<)\s*(?:\w+""|\$?\w+|"")'),
       ('awkre', r'(?:\$\w+\s*!?~\s*)?/\^#/'), ('awkfs', r"-F'\\t'"), ('awksep', r'"\\03[67]"'),
       ('nulck', r"tr -cd '\\000'"), ('datecall', r'\bdate [-+]'), ('nulsep', r"printf '%s\\0[^']*'"),
       ('wsplit', r'\bfor \w+ in \$\w+;|\bset -- \$\w+'), ('awkdfs', r"\bawk '"), ('mapfile', r'\bmapfile -t'),
       ('datasub', r'\b(?:ctext|t|wtext)="\$\('), ('readlink', r'readlink -f'), ('pwdp', r'\bpwd -P'),
       ('gitcmp', r'merge-base --is-ancestor')]
PYR = [('pycmp', r'[\w.()\[\]"]+\s*(?:!=|==)\s*[\w.()\[\]"]+'), ('pyin', r'"[^"]" in \w'), ('pystrip', r'\b\w\.strip\(\)'),
       ('pycat', r'\.startswith\("C"\)'), ('pysplit', r'split\(b"\\0"\)'), ('pydec', r'decode\("utf-8"\)'),
       ('pynot', r'\bnot a\b'), ('pyfold', r'casefold\(\)'), ('pynfc', r'normalize\("NFC", s\)')]
DATA = {'sha', 'path', 'ident', 'date', 'num', 'text', 'charset'}
INTERNAL = {'rc', 'flag', 'mode', 'env', 'empty'}
STRUCT = {'struct'}


def code_lines(path, startpat):
    L = open(path, encoding='utf-8').read().split('\n')
    s = next(i for i, x in enumerate(L) if x == startpat) if startpat else 0
    out = []; py = False
    for i in range(s, len(L)):
        x = L[i]
        if x.startswith("IDPY='"):
            py = True; continue
        if py:
            if x.startswith('sys.exit'): py = False
            if x.strip() and not x.lstrip().startswith('#'): out.append((i + 1, x, 'py'))
            continue
        if not x.strip() or x.lstrip().startswith('#'): continue
        out.append((i + 1, x, 'sh'))
    return out


def scrub(x):
    # message text never decides a verdict: the quoted bodies of WHY= SPENT= conferr= echo and blind0/blindmsg go
    x = re.sub(r'\b(WHY|SPENT|conferr)="(?:[^"\\]|\\.)*"', '', x)
    x = re.sub(r'\becho "(?:[^"\\]|\\.)*"', '', x)
    x = re.sub(r'\bblind(?:0|msg) "(?:[^"\\]|\\.)*"(?: "(?:[^"\\]|\\.)*")*', '', x)
    return x


def census_lines(lines):
    res = []
    for n, x, lang in lines:
        y = scrub(x)
        for k, p in (PYR if lang == 'py' else SH + AWK):
            for m in re.finditer(p, y):
                t = m.group(1) if m.groups() else m.group(0)
                if k == 'arm':
                    if ' in ' in t: t = t.split(' in ', 1)[1]
                    t = t.strip()
                res.append((n, k, t))
    return res


def census(gate, hook):
    g = code_lines(gate, 'set -uo pipefail'); h = code_lines(hook, None)
    return g, h, [('gate',) + r for r in census_lines(g)] + [('hook',) + r for r in census_lines(h)]


def lint(mode, gate, hook, table, test, inv, dirs=None, eqok=None):
    g, h, sites = census(gate, hook)
    bad = []
    T = open(test, encoding='utf-8').read()
    reg = set(re.findall(r'^  (?:mutant|mutf|hkmutf|eqp) ([^ \n]+)', T, re.M))
    # generated member mutants are registered through the ledger
    reg |= set(re.findall(r'^  (?:mutant|mutf|hkmutf|eqp|mutpath) ([^ \n]+)', T, re.M))
    wantkeys = set()
    for m in re.finditer(r'^want\+?="([^"]*)"', T, re.M):
        wantkeys |= {t.split('=', 1)[0] for t in m.group(1).split()}
    invids = set(l.split('\t', 1)[0] for l in open(inv, encoding='utf-8') if l.strip() and not l.startswith('#'))
    rows = []
    for ln in open(table, encoding='utf-8'):
        ln = ln.rstrip('\n')
        if not ln or ln.startswith('#'): continue
        f = ln.split('\t')
        if len(f) != 8:
            bad.append(f'S0 row {f[0]} has {len(f)} fields'); continue
        rows.append(f)
    ids = [f[0] for f in rows]
    for d in sorted(set(i for i in ids if ids.count(i) > 1)): bad.append(f'S0 duplicate id {d}')
    # map census sites to (file, line, token) -> count
    want = {}
    for fil, n, k, t in sites: want[(fil, n, t)] = want.get((fil, n, t), 0) + 1
    got = {}
    for rid, anc, tok, nth, cls, gen, mut, why in rows:
        fil, L = ('hook', h) if rid.startswith('H') else ('gate', g)
        hits = [n for n, x, _ in L if anc in x]
        if len(hits) != 1:
            bad.append(f'S2 {rid}: anchor occurs on {len(hits)} code lines'); continue
        n = hits[0]
        try: k = int(nth)
        except ValueError: bad.append(f'S0 {rid}: nth {nth!r}'); continue
        if want.get((fil, n, tok), 0) < k:
            bad.append(f'S1 {rid}: token {tok!r} #{k} is not a census site on {fil} line {n}'); continue
        got.setdefault((fil, n, tok), set()).add(k)
        ms = [m for m in mut.split(',') if m and m != '-']
        for m in ms:
            if m not in reg: bad.append(f'S5 {rid}: mutant/proof {m} not registered')
        keys = [x for x in gen.split(',') if x and x != '-']
        if cls in DATA:
            if 'nc' in keys:
                if not re.search(r'not constructible|equivalent', why): bad.append(f'S3 {rid}: nc without a "not constructible" / "equivalent" reason')
                for x in keys:
                    if x != 'nc' and x not in wantkeys: bad.append(f'S3 {rid}: fixture key {x} not in want')
            else:
                if not keys: bad.append(f'S3 {rid}: data row without a fixture key')
                for x in keys:
                    if x not in wantkeys: bad.append(f'S3 {rid}: fixture key {x} not in want')
                if not ms: bad.append(f'S3 {rid}: data row without a mutant or proof')
        elif cls in INTERNAL:
            if not keys: bad.append(f'S4 {rid}: internal row without an inventory id')
            for x in keys:
                if x not in invids: bad.append(f'S4 {rid}: inventory id {x} does not exist')
        elif cls in STRUCT:
            if keys or ms: bad.append(f'S4 {rid}: struct row names fixtures or mutants')
            if len(why) < 20: bad.append(f'S4 {rid}: struct row without a reason')
        else:
            bad.append(f'S0 {rid}: class {cls!r}')
    for key, c in sorted(want.items()):
        have = got.get(key, set())
        if have != set(range(1, c + 1)):
            bad.append(f'S1 {key[0]} line {key[1]} token {key[2]!r}: {c} site(s), rows for #{sorted(have)}')
    # census needles: known lines and fabricated lines
    def cnt(lines, pat):
        hit = [r for r in census_lines([l for l in lines if pat in l[1]])]
        return len(hit) if len([l for l in lines if pat in l[1]]) == 1 else -1
    nv = [cnt(g, 'NF==7 && $1!~/^#/ && $1""==p""'), cnt(g, 'return 10 if any(i.strip()'), cnt(g, '[ "$bs" = "$basec" ] ||')]
    if nv != [9, 3, 1]: bad.append(f'NEEDLE known lines {nv} != [9, 3, 1]')
    fab = census_lines([(1, '  [ "$x" = "$y" ] && [[ "$z" =~ ^a$ ]] || exit 1', 'sh'), (2, '  echo "[ a = b ]"', 'sh'),
                        (3, '  for k in $kids; do', 'sh')])
    if len(fab) != 3: bad.append(f'NEEDLE fabricated lines: {len(fab)} sites != 3')
    if mode == 'dynamic':
        D = {}
        try:
            for ln in open(dirs): n_, _, d = ln.rstrip('\n').partition('\t'); D[n_] = set(d.split(',')) - {'-'}
        except OSError: D = {}
        ok = set(open(eqok).read().split()) if eqok else set()
        if not D: bad.append('DYN BLIND: no mutant directions recorded')
        for rid, anc, tok, nth, cls, gen, mut, why in rows:
            if cls not in DATA: continue
            for m in [m for m in mut.split(',') if m and m != '-']:
                if m in ok: continue
                if not D.get(m): bad.append(f'DYN {rid}: mutant {m} was not killed (or did not run)')
    print(f'site lint {mode}: sites {sum(want.values())}, rows {len(rows)}, data rows '
          f'{sum(1 for r in rows if r[4] in DATA)}, needles {nv}+({len(fab)}), findings {len(bad)}')
    for b in bad: print('BAD  site lint ' + b)
    return 1 if bad else 0


def main(a):
    if len(a) >= 3 and a[0] == 'census':
        _, _, s = census(a[1], a[2])
        for fil, n, k, t in s: print(f'{fil}:{n}\t{k}\t{t}')
        return 0
    if len(a) == 7 and a[:2] == ['lint', 'static']:
        return lint('static', *a[2:])
    if len(a) == 9 and a[:2] == ['lint', 'dynamic']:
        return lint('dynamic', *a[2:])
    print(__doc__, file=sys.stderr); return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
