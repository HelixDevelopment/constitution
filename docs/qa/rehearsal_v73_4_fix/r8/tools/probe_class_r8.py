"""Class-enumeration probe (fixer r8): new members of 'the checker's model of markup/Unicode disagrees with the
reader's'. Runs REPO's checker on each body; prints the checker verdict and the expected verdict. FAKE values only.

Usage: python3 -I probe_class_r8.py REPO WORKDIR
The first row is a control that must be ACCEPTED and the second a control that must be REFUSED; a row whose verdict
differs from the expected one is marked "<-- MEMBER OPEN". Last line: PROBE_CLASS_R8 open=N (N rows differ)."""
import sys, os, importlib.util
repo = sys.argv[1]; work = sys.argv[2]
sys.path.insert(0, os.path.join(repo, "tests/release"))
import pvl_fixture as F
spec = importlib.util.spec_from_file_location("ck", os.path.join(repo, "scripts/validation/check_provisional_verification_lines.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fx = F.make_root(work); ctx = F.checker_ctx(m, fx)
G = F.line()
def second(word, colon=":"):
    return G + "\n\n**" + word + colon + "** provisional -- job: FAKE -- checks: FAKE pass=999\n"
cases = [
 ("control GOOD alone", G + "\n", "ACCEPT"),
 ("control plain duplicate", second("Verification"), "REFUSE"),
 ("F11 continuation line appended", G + "\n-- checks: FAKE pass=999\n", "REFUSE"),
 ("F11 inline comment spans into next line", G + " -- note x <!--\n-->-- checks: FAKE pass=999\n", "REFUSE"),
 ("F11 hard break then text", G + " -- note x\\\nchecks: FAKE pass=999\n", "REFUSE"),
 ("F11 GFM table delimiter after line", G + "\n|---|\n", "REFUSE"),
 ("F11 emphasis in note", G + " -- note see _x_ here\n", "REFUSE"),
 ("F11 entity in note", G + " -- note a &lt; b\n", "REFUSE"),
 ("F3 GFM footnote def before line", "[^1]: x\n" + G + "\n", "REFUSE"),
 ("F3 GFM footnote def after line", G + "\n\n[^1]: **Verification:** provisional -- checks: FAKE pass=999\n", "REFUSE"),
 ("colon U+2236 RATIO", second("Verification", "∶"), "REFUSE"),
 ("colon U+A789", second("Verification", "꞉"), "REFUSE"),
 ("colon U+0589", second("Verification", "։"), "REFUSE"),
 ("colon U+02F8", second("Verification", "˸"), "REFUSE"),
 ("letter U+13D9 Cherokee V", second("Ꮩerification"), "REFUSE"),
 ("letter U+0585 Armenian o", second("Verificatiօn"), "REFUSE"),
 ("mark U+0323 dot below", second("Verificaṭion"), "REFUSE"),
 ("upper Cyrillic TE", second("VERIFICAТION"), "REFUSE"),
 ("F5 raw HTML in image alt", G + "\n\n![<span hidden>x</span>](u)\n", "REFUSE"),
 ("F5 raw HTML in link text", G + "\n\n[<span hidden>x</span>](u)\n", "REFUSE"),
 ("F1 complete comment alone", G + "\n\n<!-- x -->\n", "REFUSE"),
]
bad = 0
for n, b, want in cases:
    r = m.check_body(b, ctx=ctx)
    got = "ACCEPT" if r is None else "REFUSE"
    bad += got != want
    print("%-44s checker=%s want=%s %s" % (n, got, want, "" if got == want else "<-- MEMBER OPEN"))
for st in ("Ready for testing", "Ready for te️sting", "Reаdy for testing", "In te͏sting"):
    k = m.status_key(st)
    got = "PROVISIONAL" if k in m.PROVISIONAL_KEYS else "SKIPPED"
    bad += got != "PROVISIONAL"
    print("status %-40r reads=%s want=PROVISIONAL %s" % (st, got, "" if got == "PROVISIONAL" else "<-- MEMBER OPEN"))
print("PROBE_CLASS_R8 open=%d" % bad)
