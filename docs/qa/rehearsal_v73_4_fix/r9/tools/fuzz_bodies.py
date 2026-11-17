"""Regenerate the bodies of the reviewer's fuzz_b.py and write those the checker ACCEPTS as adjudicate.py input.
Usage: python -I fuzz_bodies.py FUZZ_B.py TREE WORK OUT.json"""
import json, sys
fz, tree, work, out = sys.argv[1:5]
src = open(fz, encoding="utf-8").read().split("\nrows, acc, ref, danger = ")[0]
sys.argv = [fz, tree, work, out]
ns = {"__name__": "fz", "__file__": fz}
exec(compile(src, fz, "exec"), ns)  # noqa: S102 -- the reviewer's own generator, up to its loop
rows = []
for fr in ns["FRAGS"]:
    for pos, tpl in ns["positions"](fr):
        b = tpl.replace("@", ns["G"])
        if ns["M"].check_body(b, ctx=ns["CTX"]) is None:
            rows.append({"name": "%r %s" % (fr, pos), "checker": "ACCEPT", "danger": True, "body": b})
json.dump(rows, open(out, "w"))
print("FUZZ-BODIES accepted=%d" % len(rows))
