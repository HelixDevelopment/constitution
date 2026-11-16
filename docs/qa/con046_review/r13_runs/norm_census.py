#!/usr/bin/env python3
"""norm_census.py - control-needled census of every Unicode normalisation / casing / locale path of the
CM-SUBMODULE-PIN-NOT-DOWNGRADED gate and its hook (CON-046 round 12, review r11 F1, §11.4.276(C), §11.4.273; extended in round 13, review r12 R12-1/N1/R12-3).

Usage: norm_census.py <gate> <hook> <members.py> <inventory.tsv>
Prints one TSV row per hit (file, line, class, token, text) and a summary. Exit 0 = census done and every class-N
member is covered by a generated NORM mutant; 1 = a class-N member has no NORM mutant (or a NORM count mismatch);
2 = the instrument is blind (a control needle failed) or an input is unreadable.

A line inside the gate's python block (IDPY='...') is searched for classes N and E only, every other code line
for B, L and E (a python `utf-8` is not a shell range). Classes (the closed token set this census searches; a class it does not search is not claimed):
  N  python Unicode normalisation / casing: unicodedata.normalize(FORM, ..), .casefold(), .lower(), .upper(),
     .title(), .swapcase(), .capitalize(), and the normaliser `f(..)` applied to an operand of `==`
  B  bash / tool casing operators: ${v^^} ${v^} ${v,,} ${v,} ${v~~} ${v~}, declare/typeset -l/-u, shopt nocasematch /
     nocaseglob, tr with a case class or letter range, awk tolower/toupper/IGNORECASE, grep -i / --ignore-case,
     sed .../I, sort -f, uniq -i
  L  locale-dependent character ranges and classes: a bracket expression holding A-Z, a-z, 0-9 (or any letter/digit
     range) or a [:class:] inside a bash `=~` regex or a `case` pattern; and any LC_* / LANG assignment or reference
  E  encoding paths: .decode(..) / .encode(..), iconv, uconv
  C  (round 13) a string collation compare `[[ x < y ]]` / `[[ x > y ]]` (locale collation order)
  W  (round 13) python whitespace stripping .strip( / .lstrip( / .rstrip( (what counts as whitespace is Unicode-wide)
  U  (round 13) python Unicode property lookups unicodedata.category( / unicodedata.name(
Round 13 coverage rules, besides NORM: every class-W / class-U / class-C line of the gate has an inventory row whose
anchor sits on that line (or a generated STRIP / CMPS member on it); the gate's `export LC_ALL=C` comes before its
first class-L range / class-C compare; every `.casefold()` line carries one generated NORMCLS mutant per casefold-only
class, and the generator's class list equals this census's own enumeration over the whole code space.
Each token's regex is needled on its own synthetic line (set coverage, §11.4.273(f)); a fabricated token and a plain
line must give 0 hits (negative controls); the real `.casefold()` of the gate must be found in place (in-situ needle).
"""
import re, subprocess, sys

TOK = [
    ('N', 'normalize', re.compile(r'unicodedata\.normalize\("(?:NFC|NFD|NFKC|NFKD)", '), 'unicodedata.normalize("NFKD", s)'),
    ('N', 'casefold', re.compile(r'\.casefold\(\)'), 's.casefold()'),
    ('N', 'lower', re.compile(r'\.lower\(\)'), 's.lower()'),
    ('N', 'upper', re.compile(r'\.upper\(\)'), 's.upper()'),
    ('N', 'title', re.compile(r'\.title\(\)'), 's.title()'),
    ('N', 'swapcase', re.compile(r'\.swapcase\(\)'), 's.swapcase()'),
    ('N', 'capitalize', re.compile(r'\.capitalize\(\)'), 's.capitalize()'),
    ('N', 'f-operand', re.compile(r'(?<![\w.])f\([^()]*(?:\([^()]*\))?[^()]*\)==|==f\('), 'x f(i)==f(a) y'),
    ('B', 'param-case', re.compile(r'\$\{[#!]?\w+(?:\[[^\]]*\])?(?:\^\^?|,,?|~~?)[^}]*\}'), 'echo "${v^^}" "${w,}" "${z~~}"'),
    ('B', 'declare-case', re.compile(r'\b(?:declare|typeset|local)\s+-[a-zA-Z]*[lu]'), 'declare -l v'),
    ('B', 'shopt-nocase', re.compile(r'\bshopt\s+-s\s+(?:nocasematch|nocaseglob)'), 'shopt -s nocasematch'),
    ('B', 'tr-case', re.compile(r'\btr\b[^|;]*(?:\[:(?:upper|lower):\]|[A-Za-z]-[A-Za-z])'), "tr '[:upper:]' '[:lower:]'"),
    ('B', 'awk-case', re.compile(r'\b(?:tolower|toupper)\(|\bIGNORECASE\b'), 'awk "{print tolower($1)}"'),
    ('B', 'grep-i', re.compile(r'\bgrep\b(?:\s+-[a-zA-Z]+)*\s+-[a-zA-Z]*i[a-zA-Z]*\b|\bgrep\b[^|;]*--ignore-case'), 'grep -qi x'),
    ('B', 'sed-I', re.compile(r'\bsed\b[^|;]*/I[gp;\'" ]'), "sed 's/a/b/I' f"),
    ('B', 'sort-f', re.compile(r'\bsort\b[^|;]*\s-[a-zA-Z]*f|\buniq\b[^|;]*\s-[a-zA-Z]*i'), 'sort -f x'),
    ('L', 'range-in-regex', re.compile(r'=~\s+\S*\[[^\]]*(?:[A-Za-z0-9]-[A-Za-z0-9]|\[:[a-z]+:\])'), '[[ $v =~ ^[a-f0-9]+$ ]]'),
    ('L', 'range-in-case', re.compile(r'(?:^|\s|\()(?:[^\s()|]*\[[^\]]*(?:[A-Za-z0-9]-[A-Za-z0-9]|\[:[a-z]+:\])[^\s()|]*\|?)+\)'), '  [A-Z]*) x ;;'),
    ('L', 'locale-var', re.compile(r'\b(?:LC_[A-Z]+|LANG|LANGUAGE)\b'), 'LC_ALL=C sort'),
    ('C', 'collate-compare', re.compile(r'\[\[[^\]]*\s[<>]\s'), '[[ "$e" < "$today" ]]'),
    ('W', 'strip', re.compile(r'\.(?:l|r)?strip\('), 'a.lstrip() i.strip(" ")'),
    ('U', 'unicode-property', re.compile(r'unicodedata\.(?:category|name)\('), 'unicodedata.category(c)'),
    ('E', 'codec', re.compile(r'\.(?:de|en)code\(|\b(?:iconv|uconv)\b'), 'x.decode("utf-8")'),
]
NEG_FAB = 'zqxnormtoken(q) and plain text with no token'

def code_lines(path):
    try:
        L = open(path, encoding='utf-8').read().split('\n')
    except OSError:
        sys.exit(2)
    out = []; py = False
    for i, x in enumerate(L):
        if x.startswith("IDPY='"):
            py = True
            continue
        s = x.lstrip()
        if not s or s.startswith('#'):
            continue
        out.append((i + 1, x, py))
        if py and x.startswith('sys.exit'):
            py = False
    return out

def scan(line, py=None):
    """py=None: every class (needles); py=True: python classes N, E; py=False: shell classes B, L, E"""
    ok = {None: 'NBLECWU', True: 'NEWU', False: 'BLEC'}[py]
    return [(c, n) for c, n, rx, _ in TOK if c in ok for _m in rx.finditer(line)]

def main():
    if len(sys.argv) != 5:
        print('usage: norm_census.py <gate> <hook> <members.py> <inventory.tsv>', file=sys.stderr); sys.exit(2)
    gate, hook, mem, invp = sys.argv[1:5]
    blind = []
    for c, n, rx, needle in TOK:          # positive control per member of the token set
        if not rx.search(needle):
            blind.append('needle %s/%s not found on its own line' % (c, n))
    if scan(NEG_FAB):                       # negative control
        blind.append('fabricated line gave hits: %s' % scan(NEG_FAB))
    rows = []
    for path in (gate, hook):
        for ln, x, py in code_lines(path):
            for c, n in scan(x, py):
                rows.append((path.rsplit('/', 1)[-1], ln, c, n, x.strip()))
    if not any(r[3] == 'casefold' and r[0].endswith('.sh') for r in rows):
        blind.append('in-situ needle: the gate\'s .casefold() was not found')
    for r in rows:
        print('\t'.join(map(str, r)))
    cnt = {}
    for r in rows:
        cnt[(r[2], r[3])] = cnt.get((r[2], r[3]), 0) + 1
    print('# hits per class/token: ' + ', '.join('%s/%s=%d' % (k[0], k[1], v) for k, v in sorted(cnt.items())))
    print('# tokens searched: %d (each needled on its own line), negative control: 0 hits' % len(TOK))
    if blind:
        for b in blind:
            print('BLIND: ' + b)
        sys.exit(2)
    # coverage: every class-N member of the gate must have one generated NORM mutant on its line
    p = subprocess.run([sys.executable, '-I', mem, 'list', gate], capture_output=True, text=True)
    if p.returncode != 0:
        print('BLIND: member generator failed rc %d' % p.returncode); sys.exit(2)
    norm = {}; gk = {}
    for l in p.stdout.splitlines():
        f = l.split('\t')
        if len(f) >= 3:
            gk.setdefault((int(f[1]), f[2]), 0); gk[(int(f[1]), f[2])] += 1
        if len(f) >= 3 and f[2] == 'NORM':
            norm[int(f[1])] = norm.get(int(f[1]), 0) + 1
    # a member = one normalize call, one casing call, or one `f(..)` operand of `==` (the lambda definition is not one)
    gname = gate.rsplit('/', 1)[-1]
    want = {}
    for r in rows:
        if r[0] == gname and r[2] == 'N' and r[3] != 'f-operand':
            want[r[1]] = want.get(r[1], 0) + 1
    for ln in sorted({r[1] for r in rows if r[0] == gname and r[3] == 'f-operand'}):
        x = next(r[4] for r in rows if r[1] == ln and r[0] == gname)
        ops = [m for m in re.finditer(r'(?<![\w.])f\(', x)]
        want[ln] = want.get(ln, 0) + len(ops)
    bad = 0
    for ln in sorted(set(want) | set(norm)):
        w, h = want.get(ln, 0), norm.get(ln, 0)
        print('# NORM coverage line %d: members %d, generated NORM mutants %d%s' % (ln, w, h, '' if w == h else '  MISMATCH'))
        bad |= w != h
    # round 13: W / U / C lines covered by an inventory row anchored on the line (or a generated STRIP / CMPS member)
    gtext = open(gate, encoding='utf-8').read()
    invl = set()
    try:
        for l in open(invp, encoding='utf-8').read().split('\n'):
            f = l.split('\t')
            if len(f) == 6 and not f[0].startswith('#') and not f[0].startswith('H'):
                a = f[1].replace('<NL>', '\n'); k = gtext.find(a)
                if k >= 0:
                    invl.add(gtext[:k].count('\n') + 1)
    except OSError:
        print('BLIND: inventory unreadable'); sys.exit(2)
    if not invl:
        print('BLIND: no inventory anchor resolved'); sys.exit(2)
    for r in rows:
        if r[0] == gname and r[2] in 'WUC':
            ok = r[1] in invl or gk.get((r[1], 'STRIP'), 0) or gk.get((r[1], 'CMPS'), 0)
            print('# %s coverage line %d (%s): %s' % (r[2], r[1], r[3], 'covered' if ok else 'NOT COVERED'))
            bad |= not ok
    # round 13: the locale pin precedes every class-L range and class-C compare of the gate
    pin = [r[1] for r in rows if r[0] == gname and r[3] == 'locale-var' and r[4] == 'export LC_ALL=C']
    sites = [r[1] for r in rows if r[0] == gname and r[2] in 'LC' and r[3] != 'locale-var']
    if len(pin) != 1 or not sites:
        print('# locale pin: %d pin lines, %d range/compare sites  MISMATCH' % (len(pin), len(sites))); bad = 1
    else:
        okp = pin[0] < min(sites)
        print('# locale pin line %d, first range/compare site line %d: %s' % (pin[0], min(sites), 'ok' if okp else 'PIN AFTER A SITE'))
        bad |= not okp
    # round 13 (R12-2 redesign): NORMCLS per casefold line == the KILLABLE casefold-only classes under the gate's
    # pipeline (k = NFKD(casefold(NFD)), the pinned skeleton table next to the gate, fixpoint), enumerated here
    # independently of the suite
    import unicodedata as u, os
    N = u.normalize; T = {}
    for l in open(os.path.join(os.path.dirname(gate), 'cm_submodule_pin_not_downgraded_confusables.tsv'), encoding='utf-8').read().split('\n')[:-1]:
        x, y = l.split('\t'); T[chr(int(x, 16))] = ''.join(chr(int(z, 16)) for z in y.split())
    def mk(fold):
        k = lambda t: N('NFKD', fold(N('NFD', t)))
        g = lambda t: k(N('NFD', ''.join(T.get(c, c) for c in N('NFD', k(t)))))
        def f(t):
            for _ in range(8):
                v = g(t)
                if v == t: return v
                t = v
            raise ValueError('unsettled')
        return f
    ff = mk(str.casefold); gg = mk(str.lower)
    key = lambda c: '%d/%s/%s' % (len(c.casefold()), u.category(c), u.name(c, '?').split()[0])
    D = {}
    for cp in range(0x110000):
        c = chr(cp)
        if 0xD800 <= cp <= 0xDFFF or u.category(c).startswith('C') or ff(c) == gg(c) or gg(c) == gg(ff(c)):
            continue
        D.setdefault(key(c), []).append(c)
    cls = set()
    for kk, cs in D.items():
        x = ' '.join(cs); X = mk(lambda t, kk=kk: ''.join(c.lower() if key(c) == kk else c.casefold() for c in t))
        if X(x) != X(ff(x)): cls.add(kk)
    if '2/Ll/LATIN' not in cls or '1/Mn/COMBINING' not in cls:
        print('BLIND: the casefold-only enumeration lost its needle (sharp s / U+0345 class)'); sys.exit(2)
    q = subprocess.run([sys.executable, '-I', mem, 'cfclasses'], capture_output=True, text=True)
    gen = set(q.stdout.split())
    print('# killable casefold-only classes: %d enumerated (of %d), %d in the generator%s' % (len(cls), len(D), len(gen), '' if cls == gen else '  MISMATCH'))
    bad |= cls != gen
    for ln in sorted({r[1] for r in rows if r[0] == gname and r[3] == 'casefold'}):
        h = gk.get((ln, 'NORMCLS'), 0)
        print('# NORMCLS line %d: %d mutants for %d classes%s' % (ln, h, len(cls), '' if h == len(cls) else '  MISMATCH'))
        bad |= h != len(cls)
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
