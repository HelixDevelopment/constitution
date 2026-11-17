"""catpos14.py - R13-1 survey: does the AUTHPOS14 fixture set kill every per-position / off-by-one variant of the
gate's category-C check?

usage: python3 -I catpos14.py <gate>

The category-C expression is read VERBATIM from the gate's IDPY (the `any(unicodedata.category(c)...for c in a)` term
of the malformed-authoriser line). Each variant replaces the iterated sequence `a` (or the predicate) with a
narrower form. The fixture set is the AUTHPOS14 shape: one representative of each of Cc, Cf, Co, Cn placed at the
start, the middle and the end of `release-mgr` (12 strings), plus positions 1 and -2 (the off-by-one neighbours).
A variant is KILLED when at least one fixture gives a different truth value from the real expression; the real
expression must be True on every fixture (control). Exit 0 when every variant is killed by the 12 AUTHPOS14
strings alone, 1 otherwise, 2 BLIND (expression not found)."""
import re, sys, unicodedata
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'any\(unicodedata\.category\(c\)\.startswith\("C"\) for c in a\)', src)
if not m: print('BLIND: category-C expression not found in the gate'); sys.exit(2)
real = m.group(0)
reps = {'Cc': '\u0007', 'Cf': '​', 'Co': '', 'Cn': '͸'}
for k, c in reps.items(): assert unicodedata.category(c) == k, (k, unicodedata.category(c))
base = 'release-mgr'
def place(c, pos):
    return {'start': c + base, 'middle': base[:5] + c + base[5:], 'end': base + c,
            'pos1': base[0] + c + base[1:], 'pos-2': base[:-1] + c + base[-1:]}[pos]
authpos = [place(c, p) for c in reps.values() for p in ('start', 'middle', 'end')]
extra = [place(c, p) for c in reps.values() for p in ('pos1', 'pos-2')]
seqs = ['a[1:]', 'a[:-1]', 'a[1:-1]', 'a[2:]', 'a[:-2]', 'a[::2]', 'a[1::2]', 'a[:1]', 'a[-1:]', 'a[:len(a)//2]',
        'a[len(a)//2:]', 'a.strip()', 'a[0:len(a)-1]', 'a.lower()[1:]', 'set(a[1:])', 'a[:5]', 'a[5:]', 'reversed(a[1:])']
cat = 'unicodedata.category(c).startswith("C")'
preds = [real.replace(cat, 'unicodedata.category(c).startswith("Cc")'), real.replace(cat, 'unicodedata.category(c) in ("Cc","Cf")'),
         real.replace(cat, 'unicodedata.category(c) in ("Cf","Co","Cn")'), real.replace('any(', 'all(')]
# a.strip() is EQUIVALENT inside the gate line: the same line returns 3 on a!=a.strip() before this term, and every
# whitespace character of category C (\t \n \v \f \r \x1c-\x1f \x85) is removed by strip(); measured below.
EQUIV = {'a.strip()'}
variants = [(s, real.replace('for c in a)', 'for c in %s)' % s)) for s in seqs] + [('pred:' + p, p) for p in preds]
ev = lambda expr, a: eval(expr, {'unicodedata': unicodedata, 'a': a})
ctrl = [a for a in authpos + extra if not ev(real, a)]
print('real expression:', real); print('control (real True on all 26 fixtures):', 'OK' if not ctrl else 'FAIL %r' % ctrl)
if ctrl: sys.exit(1)
surv = 0
for name, expr in variants:
    k12 = [a for a in authpos if ev(expr, a) != ev(real, a)]
    k26 = [a for a in authpos + extra if ev(expr, a) != ev(real, a)]
    st = 'killed' if k12 else ('killed-only-by-off-by-one' if k26 else 'SURVIVES')
    if not k12 and name in EQUIV:
        ws = [chr(i) for i in range(0x110000) if chr(i).isspace() and unicodedata.category(chr(i)).startswith('C')]
        ok = all(('x' + w + 'y').strip() == 'x' + w + 'y' and (w + 'x').strip() == 'x' for w in ws)
        st = 'EQUIVALENT(strip-conjunct; C-whitespace %d, interior kept, edge stripped: %s)' % (len(ws), ok)
        if not ok: surv += 1
    elif not k12: surv += 1
    print('%-36s %-26s by AUTHPOS14 %2d/12, with off-by-one %2d/20' % (name, st, len(k12), len(k26)))
print('variants', len(variants), 'not killed by AUTHPOS14:', surv)
sys.exit(0 if surv == 0 else 1)
