#!/usr/bin/env python3
"""cm_submodule_pin_not_downgraded_members.py — mechanical member-mutant generator for CM-SUBMODULE-PIN-NOT-DOWNGRADED
(CON-046 round 8; §11.4.274 mechanical work in a script, §11.4.194(6)(d), §11.4.276(C) class-exhaustive enumeration).

Why it exists: three review rounds in a row (R5, R6-1/R6-2, R7-2/R7-3) found guard members below the granularity of the
hand-written inventory (a `case` alternative, a regex quantifier, the half of a `strip()`, one operand of an `&&` chain).
This script enumerates those members MECHANICALLY from the gate's own text, so the next layer is not left to a reviewer.

What it enumerates (one single-line edit per mutant; the closed operator set, nothing else is claimed):
  CASEALT  every alternative of a `case` pattern `a|b|c)`: that alternative dropped
  RXQ      every member of a bash `=~` regex: each quantifier ({m,n} {m,} {m} + ) loosened and tightened, each anchor
           (^ $) dropped, each part of a bracket class with two or more parts dropped, [1-9] widened to [0-9]
  STRIP    every python `.strip()`: replaced by `.lstrip()` and by `.rstrip()`
  CMP      every operator of a single-bracket test `[ x OP y ]` (the body may contain `]`, e.g. `${a[@]}`; it ends at
           the first ` ]`): = <-> !=, -ge -gt -le -lt to their neighbours, -z <-> -n
  CMPS     every operator of a `[[ x OP y ]]` test that is not a regex match (round 9, review F5): < <-> >, = and ==
           -> !=, != -> =, the numeric operators and -z / -n as for CMP
  ANDOR    every operand of a shell `&&` / `||` chain that is a test: dropped (forced true before `&&`, forced false before `||`)
  PYBOOL   every operand of a python ` or ` / ` and ` chain in the authoriser check: dropped
  NEG      every `if ! ` / `elif ! `: the `!` dropped
  NORM     (round 12, review r11 F1) every Unicode normalisation / casing member of the python authoriser check: each
           `unicodedata.normalize(FORM, x)` call dropped ON ITS OWN (-> x), each `.casefold()` swapped for `.lower()`
           (and `.lower()` / `.upper()` for `.casefold()`), and the normaliser `f(..)` (round 14: or the case-
           preserving skeleton `e(..)`) dropped on each operand of an `==` compare on its own. The census of the class (every normalisation / casing / locale path of the gate
           and the hook) is docs/qa/con046_review/r12_runs/norm_census.py; what it finds outside this kind is stated
           there (none in the round-12 gate)
  NORMCLS  (round 13, review r12 R12-1) for each `.casefold()` and each class of CF_CLASSES (the KILLABLE casefold-only
           characters that change the equality, keyed casefold length / general category / first word of the name):
           that one class lowered with `.lower()` instead, every other character still casefolded. The suite checks
           CF_CLASSES against its own whole-code-space enumeration on every run (META exit 2 on a difference)
A mutant that does not parse (`bash -n`) is listed as `nonviable` and not run (it is not a member, it is a syntax error).

Usage:
  cm_submodule_pin_not_downgraded_members.py list <gate>            -> TSV: name, line, kind, before, after, viable
  cm_submodule_pin_not_downgraded_members.py emit <gate> <dir>      -> writes <dir>/<name>.sh per viable mutant; prints
                                                                      the same TSV
  cm_submodule_pin_not_downgraded_members.py cfclasses              -> CF_CLASSES, one per line
The name is `gen-<kind>-<sha1 of (line text, kind, occurrence)>[:10]`, so it is stable across edits of OTHER lines.
Exit 0 ok, 2 usage / unreadable gate. Deterministic: the same gate text always yields the same list (sorted by line).
Honest boundary (§11.4.6): the operator set above is a floor, not every possible mutation; it closes the member classes
the reviews found, and the hand-written inventory (cm_submodule_pin_not_downgraded_inventory.tsv) still owns the rest.
"""
import hashlib, os, re, subprocess, sys

# round 13 (R12-2 redesign): the KILLABLE casefold-only classes of Unicode 16.0 (python 3.14) under the gate's NFKC-class
# caseless pipeline plus the pinned confusables skeleton, measured by the suite's enumeration (the 12 other classes have
# no observable class-lowering mutant; FOLD13ALL kills the whole-casefold one)
CF_CLASSES = ['1/Ll/CHEROKEE', '1/Ll/CYRILLIC', '1/Ll/GREEK', '1/Lu/CHEROKEE', '1/Mn/COMBINING', '2/Ll/LATIN']

def code_lines(text):
    lines = text.split('\n')
    try:
        s = lines.index('set -uo pipefail')
    except ValueError:
        sys.exit(2)
    out = []
    py = False
    for i in range(s, len(lines)):
        x = lines[i]
        if x.startswith("IDPY='"):
            py = True
            continue
        if not x.strip() or x.lstrip().startswith('#'):
            continue
        out.append((i, x, py))
        if py and x.startswith('sys.exit'):
            py = False
    return lines, out

def top_level_ops(x):
    """offsets of top-level ' && ' / ' || ' (outside quotes, $( ), { }, [[ ]] is fine since && never appears inside)"""
    res = []; q = None; depth = 0; i = 0
    while i < len(x):
        c = x[i]
        if q:
            if c == '\\' and q == '"':
                i += 2; continue
            if c == q:
                q = None
        elif c in '"\'':
            q = c
        elif c in '({':
            depth += 1
        elif c in ')}':
            depth = max(0, depth - 1)
        elif x.startswith(' && ', i) or x.startswith(' || ', i):
            res.append((i, x[i + 1:i + 3], depth))
        i += 1
    return res

# a test is `[[ body ]]` (body up to the first ` ]]`) or `[ body ]` (body up to the first ` ]`, not followed by `]`);
# round 9 (review F5): the body may contain `]` (`${a[@]}`, `${dstat[0]}`), which the round-8 `[^\]]` excluded
TEST = re.compile(r'(!\s+)?(?:\[\[ (?:(?! \]\]).)+? \]\]|(?<!\[)\[ (?:(?! \]).)+? \](?!\]))')
SB = re.compile(r'(?<!\[)\[ ((?:(?! \]).)+?) \](?!\])')
DB = re.compile(r'\[\[ ((?:(?! \]\]).)+?) \]\]')
OPMAP = {'=': ['!='], '!=': ['='], '-ge': ['-gt'], '-gt': ['-ge'], '-le': ['-lt'], '-lt': ['-le']}

def gen_line(i, x, py):
    muts = []  # (kind, before, after)
    def sub(kind, start, end, rep):
        muts.append((kind, x, x[:start] + rep + x[end:]))
    if not py:
        # CASEALT
        for m in re.finditer(r'(?:^|(?<=\s)|(?<=;))((?:[^\s()|;]+\|)+[^\s()|;]+)\)', x):
            alts = m.group(1).split('|')
            pos = m.start(1)
            for k, a in enumerate(alts):
                rest = alts[:k] + alts[k + 1:]
                sub('CASEALT', m.start(1), m.end(1), '|'.join(rest))
        # RXQ: bash =~ regexes (the token after =~ up to ' ]]')
        for m in re.finditer(r'=~ (\S+) \]\]', x):
            rs, re_ = m.start(1), m.end(1); r = m.group(1)
            def rsub(a, b, rep):
                sub('RXQ', rs + a, rs + b, rep)
            for q in re.finditer(r'\{(\d+),(\d+)\}', r):
                a, b = int(q.group(1)), int(q.group(2))
                rsub(q.start(), q.end(), '{%d,%d}' % (a, b + 1))
                if b > a: rsub(q.start(), q.end(), '{%d,%d}' % (a, b - 1))
                rsub(q.start(), q.end(), '{%d,%d}' % (a + 1, b) if a + 1 <= b else '{%d}' % b)
            for q in re.finditer(r'\{(\d+),\}', r):
                a = int(q.group(1))
                rsub(q.start(), q.end(), '{%d}' % a)
                if a > 0: rsub(q.start(), q.end(), '{%d,}' % (a - 1))
            for q in re.finditer(r'\{(\d+)\}', r):
                a = int(q.group(1))
                rsub(q.start(), q.end(), '{%d,}' % a)
                if a > 0: rsub(q.start(), q.end(), '{%d}' % (a - 1))
            for q in re.finditer(r'(?<=\])\+', r):
                rsub(q.start(), q.end(), '*')
            if r.startswith('^'): rsub(0, 1, '')
            if r.endswith('$'): rsub(len(r) - 1, len(r), '')
            for q in re.finditer(r'\[([^\]]+)\]', r):
                parts = re.findall(r'.-.|.', q.group(1))
                if len(parts) >= 2:
                    for k in range(len(parts)):
                        rsub(q.start(), q.end(), '[' + ''.join(parts[:k] + parts[k + 1:]) + ']')
                if q.group(1) == '1-9': rsub(q.start(), q.end(), '[0-9]')
        # CMP in single-bracket tests
        for kind, rx, opre, opmap in (
                ('CMP', SB, r' (=|!=|-ge|-gt|-le|-lt) ', OPMAP),
                ('CMPS', DB, r' (==|=|!=|<|>|-ge|-gt|-le|-lt) ',
                 dict(OPMAP, **{'==': ['!='], '=': ['!='], '<': ['>'], '>': ['<']}))):
            for m in rx.finditer(x):
                body = m.group(1); bs = m.start(1)
                if kind == 'CMPS' and ' =~ ' in ' ' + body + ' ':
                    continue  # a regex match: RXQ owns it
                for q in re.finditer(opre, ' ' + body + ' '):
                    op = q.group(1); a = bs + q.start(1) - 1; b = a + len(op)
                    for rep in opmap[op]:
                        sub(kind, a, b, rep)
                for q in re.finditer(r'(^|\s)(-z|-n) ', body):
                    a = bs + q.start(2)
                    sub(kind, a, a + 2, '-n' if q.group(2) == '-z' else '-z')
        # ANDOR
        ops = top_level_ops(x)
        for (o, kind, depth) in ops:
            left = x[:o]
            lm = None
            for t in TEST.finditer(left):
                if t.end() == len(left): lm = t
            if lm:
                sub('ANDOR', lm.start(), o + 4, '')  # drop the left test and its operator
            right = x[o + 4:]
            rm = TEST.match(right)
            if rm and kind == '&&':
                end = o + 4 + rm.end()
                tail = x[end:]
                if tail.startswith(' ||') or tail.startswith(';') or tail.startswith(' &&') or tail == '':
                    sub('ANDOR', o, end, '')
        # NEG
        for m in re.finditer(r'(?:^|\s)(?:el)?if (! )', x):
            sub('NEG', m.start(1), m.end(1), '')
    else:
        for m in re.finditer(r'\.strip\(\)', x):
            sub('STRIP', m.start(), m.end(), '.lstrip()')
            sub('STRIP', m.start(), m.end(), '.rstrip()')
        cm = re.match(r'^(\s*if not )(.*)(: return \d+)$', x)
        if cm:
            ops = cm.group(2).split(' or ')
            for k in range(len(ops)):
                rest = ops[:k] + ops[k + 1:]
                muts.append(('PYBOOL', x, cm.group(1) + ' or '.join(rest) + cm.group(3)))
        am = re.search(r'any\((i\.strip\(\)) and ([fe]\(i\.strip\(\)\)==[fe]\(a\))', x)
        if am:
            muts.append(('PYBOOL', x, x[:am.start(1)] + am.group(2) + x[am.end(2):]))
            muts.append(('PYBOOL', x, x[:am.start(1)] + am.group(1) + x[am.end(2):]))
        # NORM (round 12, review r11 F1): every Unicode normalisation / casing member of the authoriser check
        for m in re.finditer(r'unicodedata\.normalize\("(?:NFC|NFD|NFKC|NFKD)", ', x):
            close = match_paren(x, x.index('(', m.start()))
            if close is not None:
                sub('NORM', m.start(), close + 1, x[m.end():close])  # that one normalize call dropped
        for m in re.finditer(r'\.(casefold|lower|upper)\(\)', x):
            for rep in {'casefold': ['lower'], 'lower': ['casefold'], 'upper': ['casefold']}[m.group(1)]:
                sub('NORM', m.start(), m.end(), '.%s()' % rep)
            if m.group(1) == 'casefold':
                o = match_paren_back(x, m.start() - 1)
                if o is not None:
                    st = o
                    while st > 0 and (x[st - 1].isalnum() or x[st - 1] in '_.'):
                        st -= 1
                    op = x[st:m.start()]
                    for k in CF_CLASSES:
                        ln, cat, word = k.split('/')
                        rep = ('"".join(c.lower() if (len(c.casefold())==%s and unicodedata.category(c)=="%s" and '
                               '(unicodedata.name(c,"?")+" ").split()[0]=="%s") else c.casefold() for c in %s)'
                               % (ln, cat, word, op))
                        sub('NORMCLS', st, m.end(), rep)
        for m in re.finditer(r'(?<![\w.])[fe]\(', x):  # round 14: e (the case-preserving skeleton) like f
            close = match_paren(x, m.end() - 1)
            if close is not None and (x.startswith('==', close + 1) or x[:m.start()].endswith('==')):
                sub('NORM', m.start(), close + 1, x[m.end():close])  # the normaliser dropped on that operand only
    return muts

def match_paren(x, i):
    """index of the ')' matching the '(' at x[i], or None (one line, quotes respected)"""
    if i < 0 or i >= len(x) or x[i] != '(':
        return None
    depth = 0; q = None; j = i
    while j < len(x):
        c = x[j]
        if q:
            if c == '\\':
                j += 2; continue
            if c == q:
                q = None
        elif c in '"\'':
            q = c
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return None

def match_paren_back(x, j):
    """index of the '(' matching the ')' at x[j], or None (one line, no quote handling needed for the operand)"""
    if j < 0 or x[j] != ')':
        return None
    depth = 0
    while j >= 0:
        if x[j] == ')':
            depth += 1
        elif x[j] == '(':
            depth -= 1
            if depth == 0:
                return j
        j -= 1
    return None

def build(gate):
    try:
        text = open(gate, encoding='utf-8').read()
    except OSError:
        sys.exit(2)
    lines, cl = code_lines(text)
    rows = []; seen = set()
    for i, x, py in cl:
        occ = {}
        for kind, before, after in gen_line(i, x, py):
            if after == before or (i, after) in seen:
                continue
            seen.add((i, after))
            k = (kind, after); occ[k] = occ.get(k, 0) + 1
            h = hashlib.sha1(('%s\0%s\0%s' % (before, kind, after)).encode('utf-8')).hexdigest()[:10]
            name = 'gen-%s-%s' % (kind.lower(), h)
            mut = lines[:i] + [after] + lines[i + 1:]
            rows.append((name, i + 1, kind, before, after, '\n'.join(mut)))
    return rows

def viable(src):
    p = subprocess.run(['bash', '-n'], input=src.encode('utf-8'), capture_output=True)
    return p.returncode == 0

def main():
    if sys.argv[1:] == ['cfclasses']:
        print('\n'.join(CF_CLASSES)); return
    if len(sys.argv) < 3 or sys.argv[1] not in ('list', 'emit') or (sys.argv[1] == 'emit' and len(sys.argv) != 4):
        print('usage: cm_submodule_pin_not_downgraded_members.py list <gate> | emit <gate> <dir>', file=sys.stderr); sys.exit(2)
    rows = build(sys.argv[2])
    names = [r[0] for r in rows]
    if len(set(names)) != len(names):
        print('duplicate generated name', file=sys.stderr); sys.exit(2)
    d = sys.argv[3] if sys.argv[1] == 'emit' else None
    for name, ln, kind, before, after, src in rows:
        v = viable(src)
        if d and v:
            with open(os.path.join(d, name + '.sh'), 'w', encoding='utf-8') as f:
                f.write(src)
        esc = lambda s: s.replace('\\', '\\\\').replace('\t', '\\t')
        print('\t'.join([name, str(ln), kind, esc(before.strip()), esc(after.strip()), 'viable' if v else 'nonviable']))

if __name__ == '__main__':
    main()
