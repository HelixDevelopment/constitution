#!/usr/bin/env python3
"""Check the vendored per-character table against ICU's whole-string skeleton on N random strings (seeded)."""
import random, sys, unicodedata
sys.path.insert(0, sys.argv[1]); import gen_confusables as G  # tools dir
G.init('78')
T = {}
for l in open(sys.argv[2], encoding='utf-8'):
    a, b = l.rstrip('\n').split('\t'); T[chr(int(a, 16))] = ''.join(chr(int(x, 16)) for x in b.split())
N = lambda f, s: unicodedata.normalize(f, s)
skel = lambda s: N('NFD', ''.join(T.get(c, c) for c in N('NFD', s)))
rnd = random.Random(int(sys.argv[3])); pool = [chr(int(l.split('\t')[0], 16)) for l in open(sys.argv[2])] + list('abcmilos rn01Il')
bad = 0; n = int(sys.argv[4])
for i in range(n):
    s = ''.join(rnd.choice(pool) for _ in range(rnd.randint(1, 6)))
    if skel(s) != G.skel(s): bad += 1; print('DIFF', [hex(ord(c)) for c in s]) if bad < 5 else None
print('strings %d differ %d' % (n, bad))
