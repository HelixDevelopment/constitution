#!/usr/bin/env python3
"""tests/workable_items/test_secret_frontend.py -- function contracts of the lint's credential front end
(round 10, review r9 R9-3).

Documentation (section 11.4.18): docs/guides/intake_lint_guide.md, section "Credential shapes".

WHAT  The shared fixture rows (secret_shape_fixtures.py) judge the lint end to end. Some knobs of the
      front end cannot be reached that way, because another stage already decides the row (a four-letter
      key word is a short key, so no row of it ever reaches the stand-in reading). This file calls the
      front-end functions directly and pins each knob the round-9 reviewer's mutants XL2, XL4 and XL5
      changed, and the round-10 additions:
        C1  control_char(): the combining grapheme joiner U+034F and every other INVISIBLE_CHAR member
            is reported (XL2), and a plain letter is not;
        C2  _like(): stand-in letters are at most half of the head (XL4 and its stricter twin): four of
            eight in password pass, five fail; two of five in token pass, three fail;
        C3  _like(): no stand-in reading for a head of four letters or fewer (XL5);
        C4  _like(): an ASCII letter in the wrong place, or a non-letter, never passes;
        C5  secret_views(): the fixpoint view decodes a percent layer of depth 8, and the view count stays
            at or below SECRET_MAX_VIEWS for a deep input;
        C6  every NATIVE_STRONG_HEADS word is a strong head after the front end's own cleaning;
        C7  credential_value(): a ticket id and a version after a generic key are not credentials, after
            a strong key a colon-bearing value with no / or # is one (XL9);
        C8  html.unescape-gated entity view: a text whose only "&" is not an entity yields no new view.
      Control needles run first (section 11.4.273): the lint must report a known member and not a prose
      line, otherwise the run is BLIND (exit 3).
OUTPUT  "PASS <name>" / "FAIL <name>: <why>" per contract (never a fixture's value), then
        "RESULT: pass=N fail=M".
USAGE   test_secret_frontend.py <path-of-intake_lint.py>
EXIT    0 all contracts hold; 1 a contract failed; 2 usage or load error; 3 BLIND.
EVIDENCE CLASS  gate-logic only (section 11.4.289).
"""
import importlib.util
import os
import sys


def load(path):
    spec = importlib.util.spec_from_file_location("intake_lint_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main(argv):
    if len(argv) == 1:  # no argument: the lint of this checkout (the full-suite runner calls it this way)
        argv = [argv[0], os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                                      "scripts", "workable-items", "intake_lint.py")]
    if len(argv) != 2 or argv[1].startswith("-"):
        print("usage: test_secret_frontend.py <path-of-intake_lint.py>", file=sys.stderr)
        return 2
    try:
        m = load(argv[1])
    except Exception as exc:  # noqa: BLE001 - any load failure is a setup error
        print("setup: cannot load: %s" % type(exc).__name__, file=sys.stderr)
        return 2
    pw = "pass" + "word"
    val = "FA" + "KE" + "v4" + "lu3Zq9"
    if not list(m.secret_hits(pw + "=" + val)) or list(m.secret_hits("a plain prose line, nothing here")):
        print("BLIND: a control needle failed; no contract judged")
        return 3

    res = []

    def check(name, cond, why=""):
        res.append((name, bool(cond), why))

    # C1 invisible characters (XL2)
    for cp in (0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x180B, 0x180F, 0x3164, 0xFE00, 0xFE0F, 0xFFA0,
               0xE0100, 0xE01EF):
        ch = chr(cp)
        check("C1 control_char reports U+%04X" % cp, m.control_char("a" + ch + "b") == ch)
    check("C1 control_char silent on a plain letter", m.control_char("plain text") is None)

    # C2 / C3 / C4 the stand-in reading (_like); the stand-in letters are Greek letters the folds do not
    # map onto these places (the function is called directly, before any fold)
    sub = "\u03b6"  # GREEK SMALL LETTER ZETA: a letter, not ASCII
    def standin(h, k):
        return sub * k + h[k:]
    check("C2 password with 4 of 8 stand-ins", m._like(standin(pw, 4), pw))
    check("C2 password with 5 of 8 stand-ins fails", not m._like(standin(pw, 5), pw))
    tok = "tok" + "en"
    check("C2 token with 2 of 5 stand-ins", m._like(standin(tok, 2), tok))
    check("C2 token with 3 of 5 stand-ins fails", not m._like(standin(tok, 3), tok))
    check("C2 equal word always passes", m._like(pw, pw))
    check("C3 four-letter head: one stand-in fails", not m._like(standin("pass", 1), "pass"))
    check("C3 three-letter head: one stand-in fails", not m._like(standin("pin", 1), "pin"))
    check("C4 ASCII letter out of place fails", not m._like("x" + pw[1:], pw))
    check("C4 a non-letter stand-in fails", not m._like("1" + pw[1:], pw))
    check("C4 a different length fails", not m._like(sub + pw, pw))

    # C5 fixpoint and the view cap
    deep = pw
    for i in range(8):
        deep = "".join("%%%02X" % ord(c) for c in deep) if i == 0 else deep.replace("%", "%25")
    views = m.secret_views(deep + "=" + val)
    check("C5 fixpoint view decodes 8 percent layers", any(v.startswith(pw + "=") for v in views))
    check("C5 view count within SECRET_MAX_VIEWS", len(views) <= m.SECRET_MAX_VIEWS + 1,
          "views=%d cap=%d" % (len(views), m.SECRET_MAX_VIEWS))
    check("C5 fixpoint step bound is set", isinstance(m.SECRET_FIXPOINT_STEPS, int) and m.SECRET_FIXPOINT_STEPS >= 8)

    # C6 the multilingual lexicon, as the front end sees each word
    import unicodedata
    missing = [i for i, w in enumerate(m.NATIVE_STRONG_HEADS)
               if m._clean(unicodedata.normalize("NFKC", w)).lower() not in m.STRONG_HEADS]
    check("C6 every native head is a strong head", not missing, "indexes %s" % missing)
    check("C6 lexicon holds at least 28 words", len(m.NATIVE_STRONG_HEADS) >= 28)

    # C7 value classifier
    check("C7 ticket id after a generic key is not a credential", not m.credential_value("generic", "CON-1234", ""))
    check("C7 version after a generic key is not a credential", not m.credential_value("generic", "6.4.0-rc1-build42", ""))
    check("C7 secret-store reference is not a credential", not m.credential_value("strong", "env:DB_" + pw.upper(), ""))
    check("C7 colon value with no / or # after a strong key is a credential (XL9)",
          m.credential_value("strong", "Qz7k:Wm4Rt9p", ""))
    check("C7 identifier value after a strong key is a credential (XL6)", m.credential_value("strong", "dbpass_prod2", ""))

    # C8 entity view only on a real entity
    check("C8 bare ampersand gives no entity view", m._v_entities("a & b") is None)
    check("C8 a numeric entity gives a view", m._v_entities("&#112;") == "p")

    # C9 the decoding closure is not subsumed by the fixpoint: on these inputs the composed fixpoint
    # decodes a layer the wrong way round and only a closure view of depth 2 or 3 holds the key (found by
    # docs/qa/tracker_intake_2026_11_16_v10/tools/equiv_check.py's fuzz generator, seed 20261115, while
    # testing whether the closure could be removed: runs/equiv_CLOSURE0.txt, hit_differences=36). They are
    # random strings over the generator's alphabet, not credentials. Mutants OL9 (one layer) and R8-34
    # (first view of a layer only) are killed here.
    witnesses = [
        '[Zq7[}"b=:}\\\\pass\\&quot;"=\u034f}{\\u00%25 =.\u0301}\uff50\\\u1d18%2\\"',
        '{\ufe0f\u034f\u200b+\\u00`key\u034f}:\u0430  passZq7\u200b\u200bapi_=\uff50=\uff50&quot;\\".9%25}',
        'Zq7Zq7\u03bf9{keykey]\\u00&#\ufe0ftoken:\t&quot;"&quot;api_r\\"key&quot;\u1d18\\"',
    ]
    for i, w in enumerate(witnesses, 1):
        check("C9 closure witness %d is reported" % i, list(m.secret_hits(w)))

    # C10 (round 11, review r10 item 2): the lint's own named rule must report these shapes; the shared
    # primitive (secret_canon.py) would report them too, as a canonical-* fallback, so a weakened named
    # rule shows up here as a CHANGED rule name. Reviewer mutants LM3, LM4, LM7, LM8, LM9, LM11, LM12,
    # LM13, LM16, LM17 are killed here (LM2 and LM15 are equivalent, see the harness).
    import base64
    vv = "Kq7" + "Zx9wPL3mn"
    pwk = "pass" + "word"
    def named(text, want):
        got = sorted({r for r, _ in m.secret_hits(text)})
        return got == sorted(want), "got %s" % ",".join(got)
    b64 = lambda t: base64.b64encode(t.encode()).decode()  # noqa: E731
    for name, text, want in (
            ("C10 base64 colon form (LM3)", "x " + b64(pwk + ": " + vv) + " y", ["password-colon-unquoted"]),
            ("C10 base64 run of 16 (LM4)", "x " + b64("pw=" + "Kq7Zx9w!A") + " y", ["short-key-assign"]),
            ("C10 ticket prefix is not a ticket (LM7)", "tok" + "en=ABCD-12x9Qzk", ["password-assign-unquoted"]),
            ("C10 a bare number is not a version (LM8)", "sec" + "ret=123456789", ["password-assign-unquoted"]),
            ("C10 ref scheme needs a name after the colon (LM9)", "tok" + "en=kms:9Qz7wXk2a", ["password-assign-unquoted"]),
            ("C10 set after a semicolon (LM11)", "x; set " + pwk + " " + vv, ["set-command"]),
            ("C10 table row without a closing pipe (LM12)", "| " + pwk + " | " + vv, ["table-row-pair"]),
            ("C10 literals joined by & (LM13)", pwk + '="' + vv[:4] + '" & "' + vv[4:] + '"', ["password-assign"]),
            ("C10 literals joined by ~ (LM13)", pwk + '="' + vv[:4] + '" ~ "' + vv[4:] + '"', ["password-assign"]),
            ("C10 attribute key id (LM16)", '<input id="' + pwk + '" value="' + vv + '">', ["xml-attribute-pair"]),
            ("C10 parenthesised literal over 12 characters (LM17)", pwk + ' = ("' + vv + 'xyz")', ["password-assign"])):
        ok, why = named(text, want)
        check(name, ok, why)

    passed = sum(1 for _, ok, _ in res if ok)
    for name, ok, why in res:
        print(("PASS %s" % name) if ok else ("FAIL %s: %s" % (name, why or "contract broken")))
    print("RESULT: pass=%d fail=%d" % (passed, len(res) - passed))
    return 0 if passed == len(res) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
