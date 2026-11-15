"""amp_scan.py ROOT FILE... — lists every ${name/...} and ${name//...} pattern substitution in the given files (paths
relative to ROOT) and reports those whose text contains `&`. With bash's patsub_replacement on, `&` in the
replacement stands for the matched text; the install scripts turn the option off, so only such a substitution could
behave differently. A positive control (a line with `&` in the replacement) must be found and a negative control
(the same line without it) must not, or the scan is reported BLIND. Exit 0 scanned with no `&`, 1 found, 3 blind.
"""
import os
import re
import sys

START = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?/")


def expansions(line):
    for m in START.finditer(line):
        depth, i = 1, m.end()
        while i < len(line) and depth:
            c = line[i]
            if c == "\\":
                i += 2
                continue
            depth += c == "{"
            depth -= c == "}"
            i += 1
        yield line[m.start():i]


def scan(text):
    total, amp = 0, []
    for n, line in enumerate(text.splitlines(), 1):
        for e in expansions(line):
            total += 1
            if "&" in e:
                amp.append((n, e))
    return total, amp


pos = scan('x=${s//a/&&}\n')
neg = scan('x=${s//a/b}\n')
if pos != (1, [(1, "${s//a/&&}")]) or neg != (1, []):
    print("BLIND: control needles failed: positive %r, negative %r" % (pos, neg))
    sys.exit(3)
print("controls: positive needle found, negative needle not found")
root, found = sys.argv[1], 0
for rel in sys.argv[2:]:
    total, amp = scan(open(os.path.join(root, rel), encoding="utf-8").read())
    print("%-40s %3d pattern substitutions, %d with '&'" % (rel, total, len(amp)))
    for n, e in amp:
        print("  line %d: %s" % (n, e))
    found += len(amp)
print("RESULT: %s" % ("no '&' in any pattern substitution" if found == 0 else "%d with '&'" % found))
sys.exit(1 if found else 0)
