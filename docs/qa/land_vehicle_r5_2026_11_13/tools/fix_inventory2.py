import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
rep = [
 ("| R5-R04b, R5-RB, V14, R5-RM31 |", "| R5-R04b, R5-RB, R5-F1g (a global `insteadOf` at prepare: refused before the first fetch), V14, R5-RM31 |"),
 ("| R5-F3b, V3b |", "| R5-F3b, R5-F3c, R5-F3d, V3b |"),
 ("| R5-F2z |", "| R5-F2z (tracker files), R5-F2zh (trailers in the history) |"),
 ("| R5-RM15 |", "| R5-RM15, R5-F2n |"),
]
for a, b in rep:
    n = s.count(a)
    if n != 1:
        sys.exit("count %d for %r" % (n, a))
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
print("ok", len(rep))
