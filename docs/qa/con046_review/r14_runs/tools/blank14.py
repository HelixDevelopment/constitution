"""blank14.py - census of the authorisers of ONE code point that the gate refuses as blank (rc 3): not category C, not
stripped, f(c).split() empty; f loaded verbatim from the gate (gatefns14). usage: blank14.py <gate> <table>"""
import sys, unicodedata, collections
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gatefns14 as GF
ns = GF.load(sys.argv[1], sys.argv[2]); f = ns['f']
c = collections.Counter(); emp = collections.Counter(); xs = []
for i in range(0x110000):
    ch = chr(i)
    if 0xd800 <= i <= 0xdfff or unicodedata.category(ch).startswith('C') or ch != ch.strip(): continue
    try: s = f(ch)
    except ValueError: continue
    if not s.split():
        c[unicodedata.category(ch)] += 1
        if s == '': emp[unicodedata.category(ch)] += 1
        else: xs.append('%04X' % i)
print('refused blank (non-C, not stripped):', sum(c.values()), dict(sorted(c.items())), 'empty', sum(emp.values()), 'whitespace-only', len(xs), xs[:20])
print('U+2800:', repr(f('⠀')), 'U+3164:', repr(f('ㅤ')), 'U+1D159:', unicodedata.category('\U0001d159'), repr(f('\U0001d159')))
