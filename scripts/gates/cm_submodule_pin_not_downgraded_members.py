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
  CMP      every operator of a single-bracket test `[ x OP y ]`: = <-> !=, -ge -gt -le -lt to their neighbours, -z <-> -n
  ANDOR    every operand of a shell `&&` / `||` chain that is a test: dropped (forced true before `&&`, forced false before `||`)
  PYBOOL   every operand of a python ` or ` / ` and ` chain in the authoriser check: dropped
  NEG      every `if ! ` / `elif ! `: the `!` dropped
A mutant that does not parse (`bash -n`) is listed as `nonviable` and not run (it is not a member, it is a syntax error).

Usage:
  cm_submodule_pin_not_downgraded_members.py list <gate>            -> TSV: name, line, kind, before, after, viable
  cm_submodule_pin_not_downgraded_members.py emit <gate> <dir>      -> writes <dir>/<name>.sh per viable mutant; prints
                                                                      the same TSV
The name is `gen-<kind>-<sha1 of (line text, kind, occurrence)>[:10]`, so it is stable across edits of OTHER lines.
Exit 0 ok, 2 usage / unreadable gate. Deterministic: the same gate text always yields the same list (sorted by line).
Honest boundary (§11.4.6): the operator set above is a floor, not every possible mutation; it closes the member classes
the reviews found, and the hand-written inventory (cm_submodule_pin_not_downgraded_inventory.tsv) still owns the rest.
"""
import hashlib, os, re, subprocess, sys

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

TEST = re.compile(r'(!\s+)?\[\[? [^\]]*? \]\]?')

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
        for m in re.finditer(r'(?<!\[)\[ ([^\]]*?) \](?!\])', x):
            body = m.group(1); bs = m.start(1)
            for q in re.finditer(r' (=|!=|-ge|-gt|-le|-lt) ', ' ' + body + ' '):
                op = q.group(1); a = bs + q.start(1) - 1; b = a + len(op)
                for rep in {'=': ['!='], '!=': ['='], '-ge': ['-gt'], '-gt': ['-ge'], '-le': ['-lt'], '-lt': ['-le']}[op]:
                    sub('CMP', a, b, rep)
            for q in re.finditer(r'(^|\s)(-z|-n) ', body):
                a = bs + q.start(2)
                sub('CMP', a, a + 2, '-n' if q.group(2) == '-z' else '-z')
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
        am = re.search(r'any\((i\.strip\(\)) and (f\(i\.strip\(\)\)==f\(a\))', x)
        if am:
            muts.append(('PYBOOL', x, x[:am.start(1)] + am.group(2) + x[am.end(2):]))
            muts.append(('PYBOOL', x, x[:am.start(1)] + am.group(1) + x[am.end(2):]))
    return muts

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
