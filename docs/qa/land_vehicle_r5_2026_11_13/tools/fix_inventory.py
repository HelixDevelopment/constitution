import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
rep = [
 ("| R5-R04b, V14, R5-RM31 |", "| R5-R04b, R5-RB, V14, R5-RM31 |"),
 ("| R5-K01, R5-R04 |", "| R5-K01, SH0 |"),
 ("| V15 (content swap of a listed path), V15b (extra path), V8d |", "| V15 (two modes: `swap`, the content of a listed path is swapped; `extra`, an extra path is staged), V8d |"),
 ("| R5-N1a, R5-N1b, R5-N1c |", "| R5-N1 (both `ours` settings), R5-N1c |"),
 ("| U6, U7, S-state tests |", "| U9, U9b, U9c, U9d, U15 |"),
 ("| R5-F10a/b, S5g, S5g-b |", "| R5-F10, S5g, S5g-b |"),
 ("| L6, U-item tests |", "| L6, U8b |"),
 ("| R5-F7a/b/c, U12 |", "| R5-F7, U12 |"),
 ("| L6, U-key tests |", "| L6 |"),
 ("| U-name tests |", "| U12 |"),
 ("| R5-F9, R5-RM25, R5-RM03 |", "| R5-F9 (including `../docs/x`), R5-F2a and R5-F2c (glob patterns) |"),
 ("| V8, R5-RM06, R5-RM23 |", "| V8a, V8b, V8c, V8d, R5-RM06, R5-RM23 |"),
 ("| R13 (round-4 reviewer scenario) |", "| no suite test (a gap): only the round-4 reviewer's scenario R13 exercised it |"),
]
for a, b in rep:
    n = s.count(a)
    if n != 1:
        sys.exit("count %d for %r" % (n, a))
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
print("ok", len(rep))
