"""Re-judge bodies the reviewer tools flag only under pandoc-md-export, with the export reader's smart mapping.
Usage: python -I adjudicate.py REPO OUT.txt JSON...  A body is SHOWN when pandoc markdown-yaml_metadata_block writes
exactly one top-level <p> whose text starts with Verification: and equals the body's own verification line after the
smart mapping, and the label (read through ICU, the blockstate oracle's label_like) appears nowhere else in the page.
Other output (a line block, a definition list, a span elsewhere) is listed, not judged."""
import importlib.util, json, re, shutil, subprocess, sys
repo, out, files = sys.argv[1], sys.argv[2], sys.argv[3:]
sys.argv = ["x"]
sp = importlib.util.spec_from_file_location("bs", repo + "/tests/release/pvl_blockstate.py")
bs = importlib.util.module_from_spec(sp); sp.loader.exec_module(bs)
exe = shutil.which("pandoc")
res = {"flagged": 0, "shown": 0, "not_shown": 0}
lines = []
for f in files:
    for r in json.load(open(f)):
        if not r.get("danger") or r.get("checker") != "ACCEPT":
            continue
        res["flagged"] += 1
        body = r["body"]
        vl = [l for l in body.replace("\r\n", "\n").split("\n") if l.startswith("**Verification:** provisional")]
        want = bs.smart_text(" ".join(vl[0].replace("**", "").split())) if len(vl) == 1 else None
        html = subprocess.run([exe, "-f", "markdown-yaml_metadata_block", "-t", "html"], input=body,
                              capture_output=True, text=True, timeout=60).stdout
        w = bs._Walk(); w.feed(html); w.close()
        vps, rest = [], list(w.other)
        for tag, texts, kids in w.top:
            norm = " ".join("".join(texts).split())
            if tag == "p" and kids[:1] == ["strong"] and norm.startswith("Verification:"):
                vps.append(norm); rest.append(norm[len("Verification:"):])
            else:
                rest.append("".join(texts))
        ok = want is not None and vps == [want] and not any(bs.label_like(x) for x in rest)
        res["shown" if ok else "not_shown"] += 1
        lines.append("%s %s %s other=%s" % ("SHOWN" if ok else "NOT-SHOWN", f.rsplit("/", 1)[-1], r["name"][:44],
                                            ",".join(sorted(set(w.bad)))[:80] or "-"))
open(out, "w").write("\n".join(lines + ["ADJUDICATE flagged=%(flagged)d shown=%(shown)d not_shown=%(not_shown)d" % res]) + "\n")
print("ADJUDICATE flagged=%(flagged)d shown=%(shown)d not_shown=%(not_shown)d" % res)
