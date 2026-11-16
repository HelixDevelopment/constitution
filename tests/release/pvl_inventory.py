#!/usr/bin/env python3
"""tests/release/pvl_inventory.py -- the character-class probe grid of check_provisional_verification_lines.py, built
FROM the class inventory and from the Unicode database of the running Python (CON-423 review r3, round 4).

Usage:
  python3 -I tests/release/pvl_inventory.py CHECKER              full sweep (every member of every class)
  python3 -I tests/release/pvl_inventory.py CHECKER --classes    the class ids, one per line
Imported by tests/release/pvl_grid.py: sample_cases() gives a fixed, deterministic sample of the same cases for the
database grid (the paired mutants run against that sample). Not a test entry point; run by
tests/release/test_provisional_verification_lines.sh (P12).

Section 11.4.289(C)(2): gate-logic fixtures (FAKE values). Every class of CLASSES below is a row of
docs/qa/rehearsal_v73_4_fix/r4/class_inventory.md (the test compares the two lists in both directions). A class
names a SOURCE: a predicate over every code point 0..0x10FFFF (enumerated here, from unicodedata, at run time) or a
fixed list; and a FLOOR, the member count measured at landing (Unicode 16.0.0, Python 3.14); a class with fewer members than its floor
is a FAIL, so coverage cannot shrink without a visible change of this file. Each member is placed into one or more
CASES (a field, a value built from the member, and the expectation: REJ any refusal of that field, OK accepted).
Large classes (unassigned, private use, letters of other scripts) are SAMPLED deterministically: every member of the
Basic Multilingual Plane where stated, and otherwise the first and last member and every 97th; the sampled count is
printed beside the member count.

Output: `INV-FAIL <class> U+XXXX <field> <value> want=<REJ|OK> got=<reason|accepted>` (at most 10 per class), one
`CLASS <id> members=N sampled=S cases=C mismatches=M floor=F` line per class, then
`FOLD-CLOSURE code_points=1114112 folds_to_invisible=0` (no visible character's fold holds an invisible one, which
is why the checker removes them once, before the fold), then
`INVENTORY classes=K members=N cases=C mismatches=M below_floor=B unicode=<version>`. Exit 0 with no mismatch and every floor met,
1 otherwise, 64 usage.
"""
import importlib.util
import string
import sys
import unicodedata

WORDS = ("TBD", "TODO", "TBA", "XXX", "FIXME")
GOOD = "3 passed"  # a complete checks value (golden FALSE base)

# the reviewer's separators of review r3 (bin/probe_r3b.py), kept verbatim beside the classes
REVIEW_SEPS = ["/", "·", ",", "|", "+", "~", ":", "=", "•", "․", "。", "‐", "‑", "‒", "–", "−", "・", "*", "'", "\"",
               "#", "!", "&", " . ", "\t", "__", "..", ". "]

# (id, title, floor) -- the floor is the member count measured on Unicode 16.0.0 at landing; a newer Unicode may add
# members (never fewer for these predicates, except Cn, which shrinks as Unicode assigns code points: its floor is set
# low on purpose and the sampled count is reported)
CLASSES = [
    ("U01", "Default_Ignorable_Code_Point (written-out ranges; U+3164 HANGUL FILLER, U+FFA0, U+115F, U+1160, VS, tags)", 4174),
    ("U02", "Cf format characters (incl. bidi controls U+200E U+200F U+202A..U+202E U+2066..U+2069, U+061C)", 170),
    ("U03", "Cc control characters except TAB", 64),
    ("U04", "Cs surrogates (U+D800..U+DFFF; unit level only, the database cannot hold one)", 2048),
    ("U05", "Co private use (BMP all, planes 15 and 16 sampled)", 137468),
    ("U06", "Cn unassigned (sampled)", 800000),
    ("U07", "Zl and Zp line and paragraph separators", 2),
    ("U08", "Zs space separators and TAB (separators of tokens)", 18),
    ("U09", "variation selectors U+FE00..U+FE0F and U+E0100..U+E01EF (also in U01)", 256),
    ("U10", "tags block U+E0000..U+E007F (also in U01)", 128),
    ("U11", "bidi controls (also in U02)", 12),
    ("U12", "combining marks Mn Mc Me (not default-ignorable)", 2238),
    ("U13", "fillers and blanks: HANGUL FILLER family, BRAILLE PATTERN BLANK, IDEOGRAPHIC SPACE", 6),
    ("U14", "compatibility forms of one ASCII letter or digit (full-width, mathematical, enclosed, super/subscript, "
            "modifier, Roman numeral one-letter forms)", 1123),
    ("U15", "full-width and half-width forms U+FF00..U+FFEF (letters and digits fold by NFKC; the rest separate)", 225),
    ("U16", "enclosed alphanumerics U+2460..U+24FF and U+1F100..U+1F1FF", 360),
    ("U17", "Latin ligatures and digraphs (NFKC to letters, or named LIGATURE / DIGRAPH / AE OE IJ)", 59),
    ("U18", "decimal digits of other scripts (Nd, not ASCII, not a U14 form)", 670),
    ("U19", "letters of scripts outside Latin, Cyrillic, Greek (sampled per script)", 137798),
    ("U20", "Latin letters outside ASCII that NFKD does not reduce to ASCII (small capitals, strokes, IPA)", 717),
    ("U21", "Cyrillic and Greek letters (declared scripts; mixing with Latin in one word is refused)", 1085),
    ("U22", "punctuation and symbols P* S* that are not a U14 form (separators of tokens)", 8417),
    ("U23", "ASCII punctuation, space and TAB, and the reviewer's separators of review r3", 34),
]


def load(path):
    spec = importlib.util.spec_from_file_location("pvl_checker", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def di_ranges():
    """The Default_Ignorable_Code_Point ranges of Unicode DerivedCoreProperties.txt (independent copy of the oracle)."""
    return ((0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5),
            (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x206F), (0x3164, 0x3164),
            (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3),
            (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF))


def is_di(o):
    return any(lo <= o <= hi for lo, hi in di_ranges())


def nfkc1(ch):
    """The letters and digits of the NFKC form of one character, marks removed."""
    n = unicodedata.normalize("NFKD", ch)
    n = "".join(c for c in n if unicodedata.category(c) not in ("Mn", "Mc", "Me"))
    return "".join(c for c in unicodedata.normalize("NFKC", n) if c.isalnum())


def scripts_after_fold(ch):
    """The scripts (first word of the Unicode name) of the letters of ch after the checker's fold (NFKD, marks
    removed, NFKC). The classes U19 to U21 are defined on these, not on the raw character: U+00B5 MICRO SIGN folds to
    a GREEK letter, U+0149 to U+02BC MODIFIER LETTER APOSTROPHE plus n (a letter outside the declared scripts)."""
    n = unicodedata.normalize("NFKD", ch)
    n = unicodedata.normalize("NFKC", "".join(c for c in n if unicodedata.category(c) not in ("Mn", "Mc", "Me")))
    return {unicodedata.name(c, "UNNAMED").split()[0] for c in n if c.isalpha() and not c.isascii()}


def sample(members, every=97):
    if len(members) <= 2 * every:
        return list(members)
    return sorted(set(members[::every]) | {members[0], members[-1]})


def build():
    """{class id: (members, sampled members, cases)}; a case is (field, value, want)."""
    cps = [chr(o) for o in range(0x110000)]
    cat = {ch: unicodedata.category(ch) for ch in cps}
    out = {}

    def add(cid, members, smp, cases):
        out[cid] = (members, smp, cases)

    def invisible_cases(chars):
        cs = []
        for ch in chars:
            cs.append(("checks", "3 pas%ssed" % ch, "REJ"))           # inside a complete value
            cs.append(("checks", "T%sBD later" % ch, "REJ"))          # inside a placeholder word
        return cs

    di = [ch for ch in cps if is_di(ord(ch))]
    add("U01", di, di, invisible_cases(di) + [("layer", "artifact" + ch, "REJ") for ch in di] +
        [("checks", ch * 3, "REJ") for ch in di])
    cf = [ch for ch in cps if cat[ch] == "Cf"]
    add("U02", cf, cf, invisible_cases(cf) + [("target", ch + " host", "REJ") for ch in cf])
    cc = [ch for ch in cps if cat[ch] == "Cc" and ch != "\t"]
    add("U03", cc, cc, invisible_cases(cc))
    cs = [ch for ch in cps if cat[ch] == "Cs"]
    add("U04", cs, sample(cs, 31), invisible_cases(sample(cs, 31)))
    co = [ch for ch in cps if cat[ch] == "Co"]
    co_s = [ch for ch in co if ord(ch) < 0x10000] + sample([ch for ch in co if ord(ch) >= 0x10000], 997)
    add("U05", co, co_s, invisible_cases(co_s))
    cn = [ch for ch in cps if cat[ch] == "Cn"]
    cn_s = [ch for ch in cn if ord(ch) < 0x10000] + sample([ch for ch in cn if ord(ch) >= 0x10000], 997)
    add("U06", cn, cn_s, invisible_cases(cn_s))
    zlp = [ch for ch in cps if cat[ch] in ("Zl", "Zp")]
    add("U07", zlp, zlp, invisible_cases(zlp))
    zs = [ch for ch in cps if cat[ch] == "Zs"] + ["\t"]
    add("U08", zs, zs, [("checks", "T%sB%sD later" % (ch, ch), "REJ") for ch in zs] +
        [("checks", "3%spassed" % ch, "OK") for ch in zs] + [("target", "every%shost" % ch, "OK") for ch in zs])
    vs = [chr(o) for o in list(range(0xFE00, 0xFE10)) + list(range(0xE0100, 0xE01F0))]
    add("U09", vs, vs, invisible_cases(vs))
    tags = [chr(o) for o in range(0xE0000, 0xE0080)]
    add("U10", tags, tags, invisible_cases(tags) + [("checks", "TBD" + "".join(tags[0x41:0x44]), "REJ")])
    bidi = [chr(o) for o in (0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068,
                             0x2069)]
    add("U11", bidi, bidi, invisible_cases(bidi) + [("checks", "‮DBT later", "REJ")])
    marks = [ch for ch in cps if cat[ch] in ("Mn", "Mc", "Me") and not is_di(ord(ch))]
    add("U12", marks, marks, [("checks", "T%sBD later" % m, "REJ") for m in marks] +
        [("checks", "3 pas%ssed" % m, "OK") for m in marks])
    fill = [chr(o) for o in (0x3164, 0x115F, 0x1160, 0xFFA0, 0x2800, 0x3000)]
    add("U13", fill, fill, [("checks", ch * 3, "REJ") for ch in fill] + [("target", ch + " host", "REJ")
                                                                         for ch in fill[:4]] +
        [("checks", "pending%s host" % ch, "REJ") for ch in fill])

    compat, compat_cases = [], []
    for ch in cps:
        if ch.isascii() or cat[ch] in ("Cs", "Co", "Cn") or is_di(ord(ch)):
            continue
        a = nfkc1(ch)
        if len(a) == 1 and a.isascii() and unicodedata.normalize("NFKC", ch) != ch:
            compat.append(ch)
            up = a.upper()
            for w in WORDS:
                if up in w:
                    i = w.index(up)
                    compat_cases.append(("checks", w[:i] + ch + w[i + 1:] + " later", "REJ"))
                    break
            else:
                if a == "0":
                    compat_cases.append(("checks", "T%sD%s later" % (ch, ch), "REJ"))
                elif a == "1":
                    compat_cases.append(("checks", "F%sXME later" % ch, "REJ"))
                else:
                    compat_cases.append(("checks", "3 passed %s" % ch, "OK"))
    add("U14", compat, compat, compat_cases)
    fw = [chr(o) for o in range(0xFF00, 0xFFF0) if cat[chr(o)] != "Cn"]
    fw_cases = []
    for ch in fw:
        a = nfkc1(ch)
        if len(a) == 1 and a.isascii():
            fw_cases.append(("checks", "3 passed %s" % ch, "OK" if not is_di(ord(ch)) else "REJ"))
        elif not a and not is_di(ord(ch)):
            fw_cases.append(("checks", "T%sB%sD later" % (ch, ch), "REJ"))
        else:
            fw_cases.append(("checks", "3 passed %s" % ch, "REJ" if is_di(ord(ch)) else "ANY"))
    add("U15", fw, fw, fw_cases)
    enc = [chr(o) for o in list(range(0x2460, 0x2500)) + list(range(0x1F100, 0x1F200)) if cat[chr(o)] != "Cn"]
    add("U16", enc, enc, [("checks", "%s%s%s later" % (ch, ch, ch), "ANY") for ch in enc] +
        [("checks", "⒯⒝⒟ later", "REJ"), ("checks", "ⓉⒷⒹ", "REJ"), ("checks", "\U0001F143\U0001F131\U0001F133", "REJ")])
    lig = [ch for ch in cps if not ch.isascii() and cat[ch].startswith("L") and (
        (len(nfkc1(ch)) >= 2 and nfkc1(ch).isascii() and nfkc1(ch).isalpha()) or
        (unicodedata.name(ch, "").startswith("LATIN") and any(
            w in unicodedata.name(ch, "").split() for w in ("LIGATURE", "DIGRAPH", "AE", "OE", "IJ"))))]
    lig_cases = [("checks", "3 passed %s" % ch, "OK") for ch in lig]
    lig_cases += [("checks", "ﬁxme later", "REJ"), ("checks", "3 passed ﬁxme", "REJ")]
    add("U17", lig, lig, lig_cases)
    nd = [ch for ch in cps if cat[ch] == "Nd" and not ch.isascii() and ch not in compat]
    nd_cases = []
    for ch in nd:
        nd_cases.append(("checks", "3 passed %s" % ch, "REJ"))
        if unicodedata.decimal(ch) == 0:
            nd_cases.append(("checks", "T%sD%s later" % (ch, ch), "REJ"))
            nd_cases.append(("due", "2%s26-11-23" % ch, "REJ"))
    add("U18", nd, nd, nd_cases)
    declared = ("LATIN", "CYRILLIC", "GREEK")
    fold_sc = {ch: scripts_after_fold(ch) for ch in cps if ch.isalpha() and not ch.isascii()}
    other = [ch for ch, sc in fold_sc.items() if ch not in compat and ch not in lig and not is_di(ord(ch)) and
             sc - set(declared)]
    per_script = {}
    for ch in other:
        per_script.setdefault(unicodedata.name(ch, "UNNAMED").split()[0], []).append(ch)
    other_s = sorted({c for v in per_script.values() for c in v[:3] + v[-1:]} | set(sample(other)))
    add("U19", other, other_s, [("checks", "3 passed %s" % ch, "REJ") for ch in other_s] +
        [("target", "%s host" % ch, "REJ") for ch in other_s[::7]])
    latin = [ch for ch, sc in fold_sc.items() if ch not in compat and ch not in lig and sc == {"LATIN"}]
    lat_cases = []
    for ch in latin:
        lat_cases.append(("checks", "3 passed %s" % ch, "OK"))
        words = unicodedata.name(ch).split()
        if "LETTER" in words:
            base = next((w for w in words[words.index("LETTER") + 1:] if len(w) == 1), None)
            for w in WORDS:
                if base and base in w:
                    i = w.index(base)
                    lat_cases.append(("checks", w[:i] + ch + w[i + 1:] + " later", "REJ"))
                    break
    add("U20", latin, latin, lat_cases)
    cg = [ch for ch, sc in fold_sc.items() if ch not in compat and ch not in lig and sc and
          sc <= {"CYRILLIC", "GREEK"} and len(sc) == 1]
    cg_cases = []
    for ch in cg:
        cg_cases.append(("checks", "3 passed %s%s" % (ch, ch), "OK"))   # a word of one declared script
        cg_cases.append(("checks", "3 passed x%s" % ch, "REJ"))          # mixed with Latin in one word
    cg_cases += [("checks", "ТBD later", "REJ"), ("checks", "ТОDО later", "REJ"),
                 ("job", "рending x.sh", "REJ")]
    add("U21", cg, cg, cg_cases)
    punct = [ch for ch in cps if cat[ch][0] in "PS" and not ch.isascii() and not nfkc1(ch) and not is_di(ord(ch))]
    p_cases = []
    for ch in punct:
        p_cases.append(("checks", "T%sB%sD later" % (ch, ch), "REJ"))
        p_cases.append(("checks", "every suite T%sB%sD" % (ch, ch), "REJ"))
        p_cases.append(("checks", "3 passed %s 4 failed" % ch, "OK"))
    add("U22", punct, punct, p_cases)
    seps = list(string.punctuation) + [" ", "\t"]
    s_cases = []
    for sep in seps + REVIEW_SEPS:
        for w in WORDS:
            v = sep.join(w)
            for f, pre, post in (("checks", "", " later"), ("target", "", " host"), ("artifact", "", " build"),
                                 ("job", "", " bash a.sh"), ("checks", "every suite ", "")):
                s_cases.append((f, pre + v + post, "REJ"))
        if sep not in ("-", "—"):
            s_cases.append(("checks", "3 passed%s4 failed" % sep, "OK"))
    add("U23", seps, seps, s_cases)
    return out


def run_case(m, f, v):
    return m.field_problem(f, v, None)


def sample_cases():
    """A fixed sample of the inventory cases for the database grid: (name, field, value, want) with want None (accept)
    or "field '<f>' " (any refusal of that field). Characters a database line cannot hold (surrogates, line breaks)
    are left out of the sample (they stay in the full sweep)."""
    picked = []
    for cid, (_, _, cases) in sorted(build().items()):
        good = [c for c in cases if c[2] != "ANY" and not any(
            unicodedata.category(ch) == "Cs" or ch in "\n\r\x0b\x0c\x1c\x1d\x1e\x85  " for ch in c[1])]
        for k, (f, v, want) in enumerate(good[:: max(1, len(good) // 12)][:12]):
            picked.append(("inv:%s:%d" % (cid, k), f, v, None if want == "OK" else "field '%s' " % f))
    return picked


def main(argv):
    if len(argv) == 3 and argv[2] == "--classes":
        for cid, _, _ in CLASSES:
            print(cid)
        return 0
    if len(argv) != 2:
        sys.stderr.write("usage: pvl_inventory.py CHECKER [--classes]\n")
        return 64
    m = load(argv[1])
    data = build()
    total_m = total_c = total_x = 0
    bad_floor = 0
    for cid, title, floor in CLASSES:
        members, smp, cases = data[cid]
        mism = 0
        for f, v, want in cases:
            got = run_case(m, f, v)
            if want == "ANY":
                continue
            ok = (got is None) if want == "OK" else (got is not None)
            if not ok:
                mism += 1
                if mism <= 10:
                    lead = next((ch for ch in v if not ch.isascii()), v[:1])
                    print("INV-FAIL %s U+%04X %s %r want=%s got=%s" % (cid, ord(lead), f, v, want, got or "accepted"))
        floor_ok = len(members) >= floor
        bad_floor += not floor_ok
        print("CLASS %s members=%d sampled=%d cases=%d mismatches=%d floor=%d%s"
              % (cid, len(members), len(smp), len(cases), mism, floor, "" if floor_ok else " BELOW-FLOOR"))
        total_m += len(members)
        total_c += len(cases)
        total_x += mism
    closure = 0
    if not (hasattr(m, "is_invisible") and hasattr(m, "clean")):
        print("INV-FAIL FOLD-CLOSURE BLIND the checker has no is_invisible/clean (cannot check the fold closure)")
        print("FOLD-CLOSURE BLIND")
        closure = 1
    for o in range(0x110000 if closure == 0 else 0):
        ch = chr(o)
        if m.is_invisible(ch):
            continue
        v, gone = m.clean(ch)
        if gone or any(m.is_invisible(c) for c in v):
            closure += 1
            if closure <= 10:
                print("INV-FAIL FOLD-CLOSURE U+%04X folds to an invisible character" % o)
    if hasattr(m, "clean"):
        print("FOLD-CLOSURE code_points=1114112 folds_to_invisible=%d" % closure)
    total_x += closure
    print("INVENTORY classes=%d members=%d cases=%d mismatches=%d below_floor=%d unicode=%s"
          % (len(CLASSES), total_m, total_c, total_x, bad_floor, unicodedata.unidata_version))
    return 0 if total_x == 0 and bad_floor == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
