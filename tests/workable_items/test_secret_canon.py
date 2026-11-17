#!/usr/bin/env python3
"""tests/workable_items/test_secret_canon.py -- contracts of the shared credential primitive
scripts/workable-items/secret_canon.py (round 11, review r10 item 1).

Documentation (section 11.4.18): docs/guides/intake_lint_guide.md, section "Credential shapes".

WHAT  Loads the module named on the command line (a path; the mutation suites pass a mutated copy) and
      checks one contract per part of the primitive (decoding, fold, words, vocabulary, layout, value).
      A contract names an input and the hit or no-hit the part must give. These pin the knobs a fixture
      row reaches only through the lint's own rules (the lint reports the shared hits only when none of
      its named rules fired, so a weakened shared part can hide behind a named rule there).
      Control needles first (section 11.4.273): a plain key=value must be read, a prose line must not.
OUTPUT  One line per contract (its id and description, never the text), then "RESULT: pass=N fail=M".
USAGE   test_secret_canon.py [<path-of-secret_canon.py>]
EXIT    0 every contract holds; 1 a contract failed; 2 load error; 3 BLIND (a control needle failed).
EVIDENCE CLASS  gate-logic only (section 11.4.289). Every value is FAKE and built from fragments.
"""
import base64
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V = "FA" + "KE" + "c11" + "Qz7wX"      # 12 characters, fake
PW = "pass" + "word"


def load(path):
    spec = importlib.util.spec_from_file_location("secret_canon_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def b64(s):
    return base64.b64encode(s.encode()).decode()


def contracts(C):
    hit = lambda t: bool(C.hits(t))  # noqa: E731
    rules = lambda t: {r for r, _ in C.hits(t)}  # noqa: E731
    return [
        # K1 decoding
        ("K1-b64-short", "base64 of an 11-character assignment is decoded", lambda: hit("x " + b64("pw=" + "Kq7Zx9w!") + " y")),
        ("K1-b64-colon", "base64 of a colon assignment is decoded", lambda: hit("x " + b64(PW + ":" + V) + " y")),
        ("K1-b64-run16", "a base64 run of exactly 16 characters is decoded", lambda: len(b64("pw=" + "Kq7Zx9w!A")) == 16 and hit("x " + b64("pw=" + "Kq7Zx9w!A") + " y")),
        ("K1-fixpoint", "five percent layers are decoded", lambda: hit(_pct(PW + "=" + V, 5))),
        ("K1-brace-escape", "\\u{70} escapes are decoded", lambda: hit("".join("\\u{%x}" % ord(c) for c in PW) + "=" + V)),
        ("K1-long-escape", "\\U00000070 escapes are decoded", lambda: hit("".join("\\U%08x" % ord(c) for c in PW) + "=" + V)),
        ("K1-join-amp", "literals joined by & are joined", lambda: hit(PW + '="' + V[:5] + '" & "' + V[5:] + '"')),
        ("K1-join-tilde", "literals joined by ~ are joined", lambda: hit(PW + '="' + V[:5] + '" ~ "' + V[5:] + '"')),
        ("K1-layer-view", "a single-decoder view keeps a hit the full fixpoint over-decodes (percent key, base64-looking value)",
         lambda: hit("%70ass" + "word=" + b64("fake value 12"))),
        ("K1-b64-specials", "base64 of an assignment with many special characters (54% alphanumeric) is decoded",
         lambda: hit("x " + b64("pw:=K!7@x#9$q") + " y")),
        # K2 fold
        ("K2-mn-mark", "a combining mark inside a key is dropped", lambda: hit("páss" + "word=" + V)),
        ("K2-mc-mark", "a spacing mark standing for a letter is read by the wildcard", lambda: hit("pো" + "ssword=" + V)),
        ("K2-cherokee-s", "the Cherokee small s folds to s", lambda: hit("paꮪ" + "sword=" + V)),
        ("K2-cherokee-s-many", "Cherokee small s folds even when the wildcard cannot cover it",
         lambda: hit("\u4e00a\uabaa\uabaa\u4e00\u4e00rd=" + V)),
        ("K2-wildcard-half", "a word that is mostly non-ASCII is not a lookalike key",
         lambda: not hit("\u4e00\u4e01\u4e02\u4e03\u4e04\u4e05\u4e06d=" + V)),
        # K3 words
        ("K3-dot-split", "pass.word is one key", lambda: hit("pass." + "word=" + V)),
        ("K3-three-part", "mot de passe is one key", lambda: hit("mot de " + "passe=" + V)),
        ("K3-squash", "p_a_s_s_w_o_r_d is one key", lambda: hit("_".join(PW) + "=" + V)),
        ("K3-number-gap", "a count after a kind name is not part of the key (gcp-api-key 24, private-key 12)",
         lambda: not hit("rows by kind: gcp-api-key 24, private-key 12, curl-auth-user 8, github-pat 1.")),
        ("K3-number-attached", "a number attached to the key still extends it (api_key_24=V, key24=V)",
         lambda: hit("api_key_24=" + V) and hit("key24=" + V)),
        # K4 vocabulary and tails
        ("K4-fingerprint-tail", "a fingerprint tail is not a key", lambda: not hit(PW + "_fingerprint=" + V)),
        ("K4-sha-tail", "a sha256 tail is not a key", lambda: not hit(PW + "_sha256=" + V)),
        ("K4-substring", "bypass and secretary are not keys", lambda: not hit("bypass=" + V) and not hit("secretary=" + V)),
        ("K4-pin4", "a 4-digit pin is read", lambda: hit("pin=" + "4821")),
        # K5 layout
        ("K5-set-after-semicolon", "set after a semicolon is a set command", lambda: hit("x; set " + PW + " " + V)),
        ("K5-r-arrow", "the R <<- arrow is an assignment", lambda: hit(PW + ' <<- "' + V + '"')),
        ("K5-triple-quote", "a triple-quoted value is read (no own knob: the quote reader reads it)", lambda: hit(PW + " = " + "'" * 3 + V + "'" * 3) and hit(PW + ' = """' + V + '"""')),
        ("K4-value-tail", "a value suffix extends the key (password_value=V)", lambda: hit(PW + "_value=" + V)),
        ("K5-table", "a table row is read", lambda: hit("| " + PW + " | " + V + " |")),
        ("K5-colon-value", "a value holding a colon is read whole", lambda: "canonical-key" in rules(PW + "=" + "Qz7k:Wm4R")),
        # K6 value
        ("K6-ticket", "a ticket id after a generic key is not a value", lambda: not hit("token=" + "ABCD-1234")),
        ("K6-version", "a version after a generic key is not a value (also at 8 or more characters, past the length floor)",
         lambda: not hit("token=" + "v1.2.3") and not hit("token=" + "v12.34.5678") and not hit("token=" + "1.22.333-rc4")),
        ("K6-ref", "a vault reference is not a value", lambda: not hit(PW + "=" + "vault:kv/data/db#pw")),
        ("K6-ref-uri", "a URI reference with an unlisted scheme is not a value", lambda: not hit(PW + "=" + "gcpsm://projects/p1/secrets/s1")),
        ("K6-url-placeholder", "a URL user-info placeholder is not a value", lambda: not hit("'  https://<user>:<" + PW + ">@<host>/<path>'")),
        ("K6-url-value", "a URL user-info value is read", lambda: "canonical-url" in rules("https://u:" + V + "@h/x")),
        ("K6-short", "a 7-character value is not read", lambda: not hit(PW + "=" + V[:7])),
        ("K6-ident-label", "an identifier with a mixed part after a short key is not a value (PASS: case_one_a1b2)",
         lambda: not hit("PA" + "SS: case_one_a1b2") and not hit("pw" + "=test_login_2fa")),
        ("K4-join-negative", "a short key attached to a word that makes an English word is not a key (byPass, oAuth, bypwd)",
         lambda: not hit("by" + "Pass=" + V) and not hit("o" + "Auth=" + V) and not hit("by" + "pwd=" + V) and hit("db" + "Pass=" + V)),
        ("K3-suffix-single", "the suffix rules read one written word only (x bypwd is not xbypwd; ldappwd is a key)",
         lambda: not hit("x by" + "pwd=" + V + " y") and hit("ldap" + "pwd=" + V)),
        ("K5-short-colon-label", "a short key, a colon and an unquoted value is a label; quoted it is read",
         lambda: not hit("pw" + ": " + V) and hit("pw" + ': "' + V + '"') and hit("pw" + "=" + V)),
        ("K6-ref-name", "a secret-store reference by name is not a value (kms:DB_PASSWORD, k8s:DB_PASSWORD)",
         lambda: not hit(PW + ": kms:DB_" + PW.upper()) and not hit(PW + "=k8s:DB_" + PW.upper()) and hit(PW + "=Ab:CDEF_9x")),
        ("K6-ident-random", "a random mixed string after a short key is read (no word part)",
         lambda: hit("pw" + "=zq7_k9w2x")),
    ]


def _pct(s, n):
    """n percent layers: every character encoded once, then the % sign encoded n-1 more times."""
    s = "".join("%%%02X" % ord(c) for c in s)
    for _ in range(n - 1):
        s = s.replace("%", "%25")
    return s


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(HERE, "..", "..", "scripts", "workable-items", "secret_canon.py")
    try:
        C = load(path)
    except Exception as e:  # noqa: BLE001 - any load failure is a usage error of this oracle
        print("LOAD ERROR: %s" % type(e).__name__)
        return 2
    if not C.hits(PW + "=" + V) or C.hits("a plain line with password and token words, no value"):
        print("BLIND: a control needle failed")
        return 3
    ok = bad = 0
    for cid, desc, fn in contracts(C):
        try:
            good = bool(fn())
        except Exception as e:  # noqa: BLE001 - a crash breaks the contract
            good = False
            desc += " (raised %s)" % type(e).__name__
        if good:
            ok += 1
            print("PASS %s %s" % (cid, desc))
        else:
            bad += 1
            print("FAIL %s %s" % (cid, desc))
    print("RESULT: pass=%d fail=%d" % (ok, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
