"""Build tests/install/test_sigpipe.sh from the template: embeds tools/sigscan.py and the needle block.

usage: python3 -I build_test.py TEMPLATE SIGSCAN OUT
The scanner text must contain no single quote (it is embedded in a single-quoted bash literal).
"""
import sys

SQ = chr(39)

# (needle line, flagged by the scanner?)
NEEDLES = [
    ("printf " + SQ + "%s\\n" + SQ + ' "$x" | grep -q y', True),
    ("x | LC_ALL=C grep -q y", True),
    ("x | grep -m1 y >/dev/null", True),
    ("x |& grep -q y", True),
    ("x | egrep -q y", True),
    ("x | command grep -q y", True),
    ("x | \\grep -q y", True),
    ("x | fgrep -q y", True),
    ("x | head -n1", True),
    ("x | awk " + SQ + "/y/ { print; exit }" + SQ, True),
    ("x | sed -n " + SQ + "/y/{p;q}" + SQ, True),
    ("x | grep --quiet y", True),
    ("x | grep -l y", True),
    ("x | some_unknown_command", True),
    ('v="$(x | grep -q y)"', True),
    ("x | while read -r l; do break; done", True),
    ("x | sort -c", True),
    ('grep -q y <<<"$x"', True),
    ("cat <<EOF", True),
    ("body | grep -q not-code", False),
    ("EOF", False),
    ("x \\", False),
    ("  | grep -q y", True),
    ("x |", True),
    ("  grep -q y", False),
    ("case a in a|b) : ;; esac", False),
    ("echo $(( 1 | 2 ))", False),
    ("[[ a == b || c == d ]] && :", False),
    ("false || grep -q y file", False),
    ("# x | grep -q y", False),
    ("echo " + SQ + "x | grep -q y" + SQ, False),
    ('echo "x | grep -q y"', False),
    ("x | awk " + SQ + "{ n++ } END { print n; exit }" + SQ, False),
    ("x | sed -n p", False),
    ("x | grep -c y", False),
    ("x | while read -r l; do :; done", False),
    ("x | hi_scrub", False),
    ("x | cat", False),
    ("x | LC_ALL=C sort -u", False),
    ("x | timeout 5 grep -q y", True),
    ("x | env LC_ALL=C grep -q y", True),
    ("x | tail -n 1", False),
]


def shq(s):
    return SQ + s.replace(SQ, SQ + "\\" + SQ + SQ) + SQ


def main(tmpl, scan, out):
    t = open(tmpl, encoding="utf-8").read()
    s = open(scan, encoding="utf-8").read()
    if SQ in s:
        raise SystemExit("the scanner contains a single quote")
    lines = ["printf '%s\\n' \\"]
    for i, (n, _) in enumerate(NEEDLES):
        lines.append("  " + shq(n) + (" \\" if i < len(NEEDLES) - 1 else ' >"$N"'))
    expect = " ".join(str(i + 1) for i, (_, f) in enumerate(NEEDLES) if f)
    for key, val in (("@@SIGSCAN@@", s.rstrip("\n")), ("@@NEEDLES@@", "\n".join(lines)),
                     ("@@NEEDLE_EXPECT@@", expect), ("@@NEEDLE_COUNT@@", str(len(NEEDLES)))):
        if t.count(key) != 1:
            raise SystemExit("placeholder %s: %d" % (key, t.count(key)))
        t = t.replace(key, val)
    open(out, "w", encoding="utf-8").write(t)


main(*sys.argv[1:])
