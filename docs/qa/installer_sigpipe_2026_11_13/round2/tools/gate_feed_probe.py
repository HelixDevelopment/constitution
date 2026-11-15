"""gate_feed_probe.py GATE — loads the Python of the no-push gate (the text between `<<'PYGATE'` and `PYGATE`,
without its final sys.exit line) and runs the full scan (a)+(b)+(c) and the raw scan (c) alone on four texts: a
multi-line printf/echo literal piped into bash/sh, one redirected to a file, and the help-text shape. Shows that a
printed literal the raw scan masks is still refused by (a) when its output feeds a shell or a file. Read-only."""
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<<'PYGATE'\n(.*?)\nPYGATE\n", text, re.S)
src = m.group(1).replace("sys.exit(main(sys.argv[1:]))", "")
g = {"__name__": "probe"}
exec(compile(src, "gatepy", "exec"), g)
cases = [
    "printf '%s\\n' 'a\ngit push\nb' | bash\n",
    "echo 'a\ngit push\nb' | sh\n",
    "printf '%s\\n' 'a\ngit push\nb' >f.sh\n",
    "printf '%s\\n' 'usage:\ngit push is never run\nend' >&2\n",
]
for c in cases:
    full = g["scan_text"](c)
    raw = g["raw_only"](c)
    print("%-62s full: %-90s raw (c) alone: %s" % (repr(c), "; ".join(sorted(set(x[2] for x in full))) if full else "PASS",
                                                 "; ".join(x[2] for x in raw) if raw else "no finding (masked)"))
