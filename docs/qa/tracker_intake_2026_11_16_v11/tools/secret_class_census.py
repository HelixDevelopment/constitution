#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_16_v10/tools/secret_class_census.py -- enumerate the keyed-credential
class (round 7, review finding F1; round 8, review findings N1 and N2; section 11.4.276(C)) and run every member through the SECRET patterns
of an intake lint, so that the class is measured, not sampled.

usage: secret_class_census.py LINT_PY [--list]
  LINT_PY  the intake_lint.py to measure (for a RED run: the round-6 copy)
  --list   print one line per member (label and verdict), not only the mismatches

The class is the product of these dimensions (every string is assembled from fragments at run time, so
this file holds no credential-shaped literal; only labels are printed, never a generated string):
  key      LONG (password, passwd, passphrase, pwd-free strong names, *_token, credentials ...),
           GENERIC (secret, token), SHORT (pwd, pass, auth), in lower, UPPER and Title case
  prefix   none, joined by "_", "-", "." or by nothing ("PG" + key; SHORT keys: none, "_", "-" only,
           and "by"/"o" joined by nothing as negatives: bypass, oauth)
  keyquote none, ", ', an escaped \\"
  sep      =, " = ", :, " : ", :=, =>, and the full-width colon and equals sign
  valquote none, ", ', a backtick, an escaped \\"
  value    letter+digit (9), letters only (10), with a space inside (quoted only), 7 characters, a
           reference ($VAR, <x>, {x}, %X%), a mask (*, x), a path (/...), and (round 8, N1) a value
           holding a backslash
plus the separate members: whitespace after the key, a --flag with a space, netrc, an XML element (with
and without attributes), a URL user-info password (plain, short, with "/", empty user name) and its
negatives (a port before a path, a mask, a reference), and an HTTP header (X-Api-Key, X-Auth-Token).
Round 8 (N2) adds: the argument-pair separator ", " (quoted key and value, PHP define, getenv default,
a JSON array), the setter call, the key/value XML attribute pair, a tool's short flag (mysql -p, sshpass
-p, curl -u), the YAML block scalar, the pgpass line, the percent-encoded separators %3D and %3A, the URL
scheme in upper and mixed case, a key carrying a format character (zero-width space and joiner, soft
hyphen, a tag character, a bidi control, a byte-order mark) or a Cyrillic or Greek lookalike letter, and
negatives for placeholders, code expressions and paths (review N4).
Round 9 (review r9 F1) adds the dimensions the round-9 reviewer's shapes showed missing: a key SUFFIX
(_PROD, _V2, 2, _BASE) and the property suffixes that make a key a non-key (_policy, _count, _hash, less);
a string PREFIX before the value quote (b, f, r, rb); string CONCATENATION (adjacent, +, ., ||); ENCODING
LAYERS on the key (HTML entities, a double percent layer, an octal escape, an escaped full-width letter)
and on the value (hex escapes); INVISIBLE marks inside a key (combining marks, the grapheme joiner,
variation selectors, a Hangul filler); Latin LOOKALIKES (alpha, small capitals, Armenian, Cherokee);
camelCase short keys (userPass) and their English-word negatives (byPass, oAuth); bracket keys; QUALIFIED
keys (signing, encryption, master, account key) and the non-credential qualifiers (public key, page
token); bare short keys (key, session, cookie, pin); more tool flags; a quoted value after whitespace (SQL);
the Authorization header with any scheme; secret-manager references; identifier values; a tab inside a
value; the value-length boundary at exactly 8 characters.

The expected verdict of every member follows the rule written in class_inventory.md section L (round 7):
HIT, or MISS with the reason "negative" (a reference, a mask, a short value, a path, a word that is not a
key) or "boundary" (a member named in the honest boundary). A mismatch is either a GAP (expected HIT,
missed) or an FP (expected MISS, reported).

Control needles, before any member is read: a known member must be found and a prose line must not be;
when either fails the instrument is blind and nothing is reported.
Output: `MISMATCH <GAP|FP> <label>` lines (and, with --list, `MEMBER <verdict> <label>` lines), then
`RESULT: members=N hit=N miss_negative=N miss_boundary=N gap=N fp=N`.
Exit: 0 no mismatch; 1 a mismatch; 2 usage; 3 a control needle failed or the lint could not be loaded.
Evidence class: gate-logic only (section 11.4.289).
"""
import importlib.machinery
import importlib.util
import sys
import unicodedata

import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
PW = "pass" + "word"
V_MIX = "Zq7" * 3                      # nine characters, a letter and a digit
V_LET = "corr" + "ecthors"             # eleven letters
V_SPC = "corr" + "ect horse " + "7bat"  # a value with spaces
V_SHORT = "Zq7" * 2 + "Z"              # seven characters
REFS = {"ref-dollar": "$" + "{DB_PW}", "ref-angle": "<" + "your-pw>", "ref-brace": "{" + "pw}",
        "ref-percent": "%" + "PW%"}
MASKS = {"mask-stars": "*" * 10, "mask-x": "x" * 10}
V_PATH = "/srv/" + "u1/app"
V_BS = "ab" + "\\" + V_MIX              # a value holding one backslash (round 8, N1)

LONG = [PW, "pass" + "wd", "pass" + "phrase", "api_" + "key", "api" + "key", "api-" + "key", "api." + "key",
        "secret_" + "key", "access_" + "key", "private_" + "key", "client_" + "secret", "auth_" + "token",
        "access_" + "token", "refresh_" + "token", "bearer_" + "token", "session_" + "token", "api_" + "token",
        "id_" + "token", "oauth_" + "token", "app_" + "token", "credential", "credentials"]
GENERIC = ["sec" + "ret", "tok" + "en"]
SHORT = ["pw" + "d", "pa" + "ss", "au" + "th"]


def cases(k):
    return sorted({k, k.upper(), k[:1].upper() + k[1:]})


def tier_keys():
    for tier, keys in (("LONG", LONG), ("GENERIC", GENERIC), ("SHORT", SHORT)):
        for k in keys:
            for kk in cases(k):
                yield tier, kk


PREFIX_LS = [("p-none", ""), ("p-under", "DB_"), ("p-dash", "X-"), ("p-dot", "cfg."), ("p-joined", "PG")]
PREFIX_S = [("p-none", ""), ("p-under", "MYSQL_"), ("p-dash", "x-")]
PREFIX_S_NEG = [("p-joined-bypass", "by"), ("p-joined-oauth", "o")]
KEYQ = [("kq-none", ""), ("kq-dq", '"'), ("kq-sq", "'"), ("kq-esc", '\\"')]
SEPS = [("eq", "="), ("eq-sp", " = "), ("colon", ":"), ("colon-sp", " : "), ("walrus", ":="),
        ("fat-arrow", "=>"), ("fw-colon", "："), ("fw-eq", "＝")]
VALQ = [("vq-none", ""), ("vq-dq", '"'), ("vq-sq", "'"), ("vq-bt", "`"), ("vq-esc", '\\"')]


def colon_like(sep):
    return sep in ("colon", "colon-sp", "fw-colon")


def values():
    yield "v-mix", V_MIX
    yield "v-let", V_LET
    yield "v-space", V_SPC
    yield "v-short", V_SHORT
    yield "v-path", V_PATH
    yield "v-bs", V_BS
    for n, v in REFS.items():
        yield n, v
    for n, v in MASKS.items():
        yield n, v


def expect_keyed(tier, sep, vq, vname):
    """The rule of class_inventory.md section L for a keyed assignment: HIT, or a MISS reason."""
    quoted = vq != "vq-none"
    if vname in ("v-short",) or vname.startswith("ref-") or vname.startswith("mask-"):
        return "negative"
    if vname == "v-path":
        return "negative" if tier == "SHORT" else "boundary-path"  # B13 (round 8, N4): a path is not read
    if vname == "v-space":
        if not quoted:
            return "boundary-unquoted-space"   # the first word only is read; under 8 characters here
        return "HIT" if tier == "LONG" else "boundary-space-generic-short"
    if tier == "LONG":
        return "HIT"
    if tier == "GENERIC":
        if colon_like(sep) and not quoted and vname == "v-let":
            return "boundary-generic-colon-letters"
        return "HIT"
    # SHORT
    if vname == "v-let":
        return "boundary-short-letters"
    if colon_like(sep) and not quoted:
        return "boundary-short-colon-unquoted"
    return "HIT"


def members():
    for tier, k in tier_keys():
        prefixes = PREFIX_LS if tier != "SHORT" else PREFIX_S + PREFIX_S_NEG
        for pn, p in prefixes:
            for kqn, kq in KEYQ:
                if kq and pn != "p-none":
                    continue  # a quoted key carries no prefix in this census (JSON keys are whole names)
                for sn, s in SEPS:
                    for vqn, vq in VALQ:
                        for vn, v in values():
                            if vn == "v-space" and vqn == "vq-none":
                                continue
                            text = kq.join(["", p + k, ""]) + s + vq + v + vq
                            exp = expect_keyed(tier, sn, vqn, vn)
                            if pn.startswith("p-joined-"):
                                exp = "negative"
                            label = "keyed %s %s %s %s %s %s %s" % (tier, k, pn, kqn, sn, vqn, vn)
                            yield label, text, exp
    # whitespace after the key (not a separator): LONG with a letter and a digit only
    for tier, k in tier_keys():
        for vn, v in (("v-mix", V_MIX), ("v-let", V_LET)):
            ident = tier == "SHORT" or k.isupper() or any(c in k for c in "_.-")
            exp = "HIT" if (tier == "LONG" and vn == "v-mix" and ident) else "boundary-whitespace"
            yield "space %s %s %s" % (tier, k, vn), "DB_" + k + " " + v if tier == "SHORT" else k + " " + v, exp
    # a --flag and a space: LONG any value, GENERIC and SHORT a letter and a digit; an upper-case placeholder
    for tier, k in tier_keys():
        for vn, v in (("v-mix", V_MIX), ("v-let", V_LET), ("v-sq-mix", "'" + V_MIX + "'"),
                      ("v-placeholder", PW.upper() + "_X"), ("ref-dollar", REFS["ref-dollar"]),
                      ("mask-stars", MASKS["mask-stars"])):
            if vn in ("v-placeholder", "ref-dollar", "mask-stars"):
                exp = "negative"
            elif vn == "v-let" and tier != "LONG":
                exp = "boundary-flag-letters"
            else:
                exp = "HIT"
            for fn, f in (("flag", "--"), ("flag-prefixed", "--db-")):
                yield "flag %s %s %s %s" % (fn, tier, k, vn), "mysql " + f + k.lower() + " " + v + " -h x", exp
    # netrc
    for k in (PW, "pass" + "wd"):
        for vn, v, exp in (("v-mix", V_MIX, "HIT"), ("v-let", V_LET, "HIT"), ("ref-dollar", REFS["ref-dollar"], "negative"),
                           ("mask-stars", MASKS["mask-stars"], "negative")):
            yield "netrc %s %s" % (k, vn), "machine h1 login u1 " + k + " " + v, exp
    # XML element
    for tier, k in tier_keys():
        for an, a in (("plain", ""), ("attr", ' type="x"')):
            for pn, p in (("p-none", ""), ("p-under", "db_")):
                for vn, v in (("v-mix", V_MIX), ("v-let", V_LET), ("ref-dollar", REFS["ref-dollar"]),
                              ("mask-x", MASKS["mask-x"]), ("v-short", V_SHORT)):
                    if vn in ("ref-dollar", "mask-x", "v-short"):
                        exp = "negative"
                    elif vn == "v-let" and tier != "LONG":
                        exp = "boundary-xml-letters"
                    else:
                        exp = "HIT"
                    t = p + k
                    yield ("xml %s %s %s %s %s" % (tier, k, an, pn, vn)), "<" + t + a + ">" + v + "</" + t + ">", exp
    # URL user-info
    u = [("url-plain", "https://" + "u1:" + V_MIX + "@h/x", "HIT"),
         ("url-short", "https://" + "u1:" + "pw" + "@h/x", "HIT"),
         ("url-slash", "https://" + "u1:" + "ab/" + V_MIX + "@h/x", "HIT"),
         ("url-empty-user", "redis://" + ":" + V_MIX + "@h:6379/0", "HIT"),
         ("url-scheme-plus", "git+ssh://" + "bob:" + V_MIX + "@h/r", "HIT"),
         ("url-port-path-neg", "https://" + "h:8080/" + "a/@b", "negative"),
         ("url-mask-neg", "https://" + "u1:" + "****" + "@h/x", "negative"),
         ("url-ref-neg", "https://" + "u1:" + "$" + "{PW}@h/x", "negative"),
         ("url-no-pass-neg", "ssh://" + "git@h/r", "negative")]
    for n, t, exp in u:
        yield "url %s" % n, t, exp
    # HTTP headers
    for hn, h in (("x-api-key", "X-Api" + "-Key"), ("x-auth-token", "X-Auth" + "-Token"),
                  ("x-token", "X-" + "Token")):
        yield "header %s v-mix" % hn, h + ": " + V_MIX, "HIT"
    # ---- round 8 (N2) members -------------------------------------------------------------------
    def vexp(tier, vn):
        if vn in ("v-short",) or vn.startswith("ref-") or vn.startswith("mask-"):
            return "negative"
        if vn == "v-let" and tier != "LONG":
            return "boundary-letters"
        return "HIT"
    VSET = (("v-mix", V_MIX), ("v-let", V_LET), ("v-bs", V_BS), ("v-short", V_SHORT),
            ("ref-dollar", REFS["ref-dollar"]), ("mask-stars", MASKS["mask-stars"]))
    # argument pair: a quoted key, ", ", a quoted value (define, getenv default, a JSON array)
    for tier, k in tier_keys():
        for qn, q in (("dq", '"'), ("sq", "'"), ("bt", "`")):
            for wn, w in (("define", "define(%s)"), ("get", "cfg.get(%s)"), ("array", "[%s]")):
                for vn, v in VSET:
                    pair = q + k + q + ", " + q + v + q
                    yield "argpair %s %s %s %s %s" % (tier, k, qn, wn, vn), w % pair, vexp(tier, vn)
    # a setter call: setPassword("v"), set_api_key('v')
    for k, sn in ((PW, "camel"), ("api_" + "key", "snake"), ("client_" + "secret", "snake")):
        name = "set" + k[:1].upper() + k[1:] if sn == "camel" else "set_" + k
        for qn, q in (("dq", '"'), ("sq", "'")):
            for vn, v in VSET:
                yield "setter %s %s %s" % (name, qn, vn), "ds." + name + "(" + q + v + q + ")", vexp("LONG", vn)
    # a key/value XML attribute pair and the entry element
    for tier, k in tier_keys():
        for vn, v in VSET:
            yield "xmlattr add %s %s %s" % (tier, k, vn), '<add key="' + k + '" value="' + v + '"/>', vexp(tier, vn)
            yield "xmlattr entry %s %s %s" % (tier, k, vn), '<entry key="' + k + '">' + v + "</entry>", vexp(tier, vn)
    # a tool's short flag
    for vn, v in VSET:
        e = "negative" if vexp("LONG", vn) == "negative" else "HIT"
        yield "shortflag mysql-joined %s" % vn, "mysql -uroot -p" + v + " db", e
        yield "shortflag sshpass-space %s" % vn, "sshpass -p " + v + " ssh h", e
        yield "shortflag sshpass-joined %s" % vn, "sshpass -p" + v + " ssh h", e
        yield "shortflag curl-u %s" % vn, "curl -u bob:" + v + " https://h", e
        yield "shortflag curl-user %s" % vn, "curl --user bob:" + v + " https://h", e
    yield "shortflag mysql-spaced-prompt", "mysql -u root -p app_database", "boundary-mysql-spaced"
    yield "shortflag mysql-port-neg", "mysql -h db -P" + "3306ab", "negative"
    # a YAML block scalar
    for tier, k in tier_keys():
        for ind in ("|", ">", "|-", ">-", "|+"):
            for vn, v in VSET:
                yield "yamlblock %s %s %s %s" % (tier, k, ind, vn), k + ": " + ind + "\n  " + v, vexp(tier, vn)
    # a pgpass line (host:port:db:user:password, read as a whole line)
    for hn, h in (("host", "h:5432:db:u:"), ("star", "*:*:*:u:")):
        for vn, v in VSET:
            e = "negative" if vexp("LONG", vn) == "negative" else "HIT"
            if vn == "v-let":
                e = "boundary-pgpass-letters"  # B20
            yield "pgpass %s %s" % (hn, vn), "\n" + h + v + "\n", e
    # percent-encoded separators
    for tier, k in tier_keys():
        for sn, sep in (("pct-eq", "%3D"), ("pct-eq-lower", "%3d"), ("pct-colon", "%3A%20")):
            for vn, v in (("v-mix", V_MIX), ("ref-dollar", "%24%7BPW%7D")):
                e = "negative" if vn != "v-mix" else ("HIT" if tier != "SHORT" or sn != "pct-colon" else "boundary-short-colon-unquoted")
                yield "percent %s %s %s %s" % (tier, k, sn, vn), "q?" + k + sep + v, e
    # the URL scheme in any case
    for sc in ("https", "HTTPS", "Https", "POSTGRES", "Redis", "GIT+SSH"):
        yield "url-case %s plain" % sc, sc + "://u1:" + V_MIX + "@h/x", "HIT"
        yield "url-case %s mask-neg" % sc, sc + "://u1:" + "x" * 8 + "@h/x", "negative"
        yield "url-case %s ref-neg" % sc, sc + "://u1:$" + "{PW}@h/x", "negative"
    # a key carrying a format character or a lookalike letter (the front end removes or folds it)
    OBF = (("zwsp", "​"), ("zwnj", "‌"), ("zwj", "‍"), ("soft-hyphen", "­"),
           ("tag-a", "\U000E0041"), ("bidi-rlo", "‮"), ("bom", "﻿"), ("word-joiner", "⁠"))
    for tier, k in tier_keys():
        if tier == "SHORT":
            continue
        for on, o in OBF:
            kk = k[:2] + o + k[2:]
            yield "obfuscated %s %s %s" % (tier, k, on), kk + "=" + V_MIX, "HIT"
        LOOK = {"a": "а", "e": "е", "o": "о", "p": "р", "c": "с", "x": "х",
                "A": "А", "E": "Е", "O": "О", "P": "Р", "C": "С", "T": "Т"}
        for i, ch in enumerate(k):
            if ch in LOOK:
                yield "lookalike %s %s pos%d" % (tier, k, i), k[:i] + LOOK[ch] + k[i + 1:] + "=" + V_MIX, "HIT"
                break
    # placeholders, code expressions and paths after a strong key (review N4)
    for vn, v in (("changeme", "change" + "me"), ("your-here", "YOUR_" + PW.upper() + "_HERE"),
                  ("your-lower", "your_api_" + "key_here"), ("my-token", "my-" + "token-1"),
                  ("environ", 'os.environ["API_KEY"]'), ("getpass", "getpass.getpass()"),
                  ("settings", "settings.SECRET_KEY"), ("call", "generate_token()"),
                  ("form", "request.form['x']"), ("path-dot", "./secrets/db1"), ("path-home", "~/.aws/k1"),
                  ("none", "None"), ("required", "required"), ("optional", "optional")):
        for sn, sep in (("eq", "="), ("colon", ": ")):
            yield "nonvalue %s %s" % (vn, sn), "DB_" + PW.upper() + sep + v, "negative"
    # prose, words that are not keys
    for n, t in (("prose-1", "the " + PW + " was rotated yesterday"),
                 ("prose-2", "Pass" + "word: none"),
                 ("prose-3", "Tok" + "en: obtained from the host at run time"),
                 ("prose-4", PW + "less login is enabled for everyone"),
                 ("prose-5", "api_" + "key_file: /etc/app/k.pem"),
                 ("prose-6", "PA" + "SS: case_one_" + "a1"),
                 ("prose-7", "the " + PW + " manager stores it"),
                 ("prose-8", "au" + "th: required")):
        yield "prose %s" % n, t, "negative"


def members_r9():
    """The round-9 dimensions (review r9 F1). Expected verdicts follow class_inventory.md section L, v9."""
    PWU = PW.upper()
    V8 = "Zq7" * 2 + "Zq"            # exactly eight characters (the length boundary; review r9 RV4)
    yield "len8 strong eq", PW + "=" + V8, "HIT"
    yield "len8 strong quoted", PW + ' = "' + V8 + '"', "HIT"
    # a key suffix after a credential key (Rails SECRET_KEY_BASE, DB_PASSWORD_PROD, API_KEY_V2, password2)
    SUFFIX_KEYS = [PWU, PW, "pass" + "wd", "API_" + "KEY", "api" + "Key", "SECRET_" + "KEY", "AUTH_" + "TOKEN",
                   "client_" + "secret", "credential"]
    for k in SUFFIX_KEYS:
        for sn, suf in (("prod", "_PROD"), ("v2", "_V2"), ("digit", "2"), ("us-digit", "_1"), ("base", "_BASE"),
                        ("dot-env", ".prod"), ("dash", "-staging")):
            for sep in ("=", ": ", ' = "'):
                end = '"' if sep.endswith('"') else ""
                yield "suffix %s %s %r v-mix" % (k, sn, sep), k + suf + sep + V_MIX + end, "HIT"
                yield "suffix %s %s %r v-let" % (k, sn, sep), k + suf + sep + V_LET + end, "HIT"
    for k, gen in ((PW, False), (PWU, False), ("tok" + "en", True), ("sec" + "ret", True), ("api_" + "key", False)):
        for sn, suf in (("policy", "_policy"), ("count", "_count"), ("hash", "_hash"), ("file", "_file"),
                        ("length", "_length"), ("url", "_url"), ("hits", "_hits"), ("less", "less")):
            yield "suffix-neg %s %s" % (k, sn), k + suf + "=" + V_MIX, "negative"
    # a string prefix before the value quote
    for k, tier in ((PW, "LONG"), ("tok" + "en", "GENERIC"), ("api_" + "key", "LONG"), ("pw" + "d", "SHORT")):
        for pre in ("b", "f", "r", "rb", "B", "u"):
            for q in ('"', "'"):
                yield "strprefix %s %s %s v-mix" % (k, pre, q), k + " = " + pre + q + V_MIX + q, "HIT"
                exp = "HIT" if tier != "SHORT" else "boundary-short-letters"
                yield "strprefix %s %s %s v-let" % (k, pre, q), k + " = " + pre + q + V_LET + q, exp
    # string concatenation of the value
    a, b = V_MIX[:5], V_MIX[5:]
    for k in (PW, "api_" + "key", "DB_" + PWU):
        for on, op in (("adjacent", " "), ("plus", " + "), ("dot", " . "), ("pipes", " || "), ("tight-plus", "+")):
            for q in ('"', "'"):
                yield "concat %s %s %s" % (k, on, q), k + " = " + q + a + q + op + q + b + q, "HIT"
    # encoding layers on the key, and on the value
    yield "layer html-entity-json", "{&quot;" + PW + "&quot;: &quot;" + V_MIX + "&quot;}", "HIT"
    yield "layer html-numeric-key", "pass&#119;" + "ord=" + V_MIX, "HIT"
    yield "layer html-hex-key", "pass&#x77;" + "ord=" + V_MIX, "HIT"
    yield "layer html-named-sep", PW + "&equals;" + V_MIX, "HIT"
    yield "layer double-percent", "pass%2577" + "ord=" + V_MIX, "HIT"
    yield "layer double-percent-sep", PW + "%253D" + V_MIX, "HIT"
    yield "layer octal-key", "\\160" + "assword=" + V_MIX, "HIT"
    yield "layer hex-escape-value", PW + '="\\x5a' + V_MIX + '"', "HIT"
    yield "layer escaped-fullwidth-key", '{"\\uff50' + "ass" + 'word": "' + V_MIX + '"}', "HIT"
    yield "layer html-ref-neg", "{&quot;" + PW + "&quot;: &quot;$" + "{PW}&quot;}", "negative"
    # invisible marks inside a key
    for mn, mk in (("combining-acute", "\u0301"), ("cgj", "\u034f"), ("vs16", "\ufe0f"), ("vs1", "\ufe00"),
                   ("mongolian-fvs", "\u180b"), ("hangul-filler", "\u3164"), ("combining-dot", "\u0307")):
        for k in (PW, "api_" + "key", "tok" + "en", "client_" + "secret"):
            yield "invisible %s %s" % (k, mn), k[:3] + mk + k[3:] + "=" + V_MIX, "HIT"
    # Latin lookalikes (B18 in the class from round 9)
    for ln, word in (("alpha", "p\u0251ss" + "word"), ("small-caps", "\u1d18\u1d00\ua731\ua731\u1d21\u1d0f\u0280\u1d05"),
                     ("armenian-o", "passw\u0585rd"), ("cherokee-p", "\u13e2ass" + "word"),
                     ("dotless-i-none", "credent\u0131al"), ("long-s", "pa\u017fs" + "word")):
        yield "lookalike-latin %s" % ln, word + "=" + V_MIX, "HIT"
    # camelCase short keys, and English words that join a short key
    for pre in ("user", "admin", "db", "root", "mysql", "redis"):
        for k in ("Pass", "Pwd", "Auth"):
            yield "camel-short %s%s v-mix" % (pre, k), pre + k + "=" + V_MIX, "HIT"
            yield "camel-short %s%s v-let" % (pre, k), pre + k + "=" + V_LET, "boundary-short-letters"
    for w in ("byPass", "BYPASS", "compass", "COMPASS", "oAuth", "OAUTH", "trespass", "surpass", "bypass"):
        yield "camel-short-neg %s" % w, w + "=" + V_MIX, "negative"
    # bracket keys
    for k in ("config[" + PW + "]", 'os.environ["DB_' + PWU + '"]', "cfg['api_" + "key']", "env[" + PWU + "][0]"):
        yield "bracket %s" % k, k + "=" + V_MIX, "HIT"
        yield "bracket-ref %s" % k, k + "=$" + "{X}", "negative"
    # qualified keys
    for k in ("SIGNING_" + "KEY", "signing" + "Key", "encryption_" + "key", "ENCRYPTION_" + "KEY", "MASTER_" + "KEY",
              "Account" + "Key", "jwt_" + "secret", "HMAC_" + "KEY", "app_" + "secret", "webhook_" + "secret",
              "private" + "Key", "refresh" + "Token", "ACCESS_" + "TOKEN"):
        yield "qualified %s v-mix" % k, k + "=" + V_MIX, "HIT"
        yield "qualified %s v-let" % k, k + "=" + V_LET, "HIT"
        yield "qualified %s colon v-let" % k, k + ": " + V_LET, "HIT"
    for k in ("public_" + "key", "PUBLIC_" + "KEY", "primary_" + "key", "sort" + "Key", "page_" + "token",
              "next" + "Token", "cache_" + "key", "foreign_" + "key", "csrf_" + "token", "partition_" + "key"):
        yield "qualified-neg %s" % k, k + "=" + V_MIX, "negative"
    # bare short keys (B9 in the class from round 9) and the numeric PIN
    for k in ("key", "KEY", "session", "sid", "cookie", "Cookie"):
        yield "short-bare %s v-mix" % k, k + "=" + V_MIX, "HIT"
        yield "short-bare %s v-let" % k, k + "=" + V_LET, "boundary-short-letters"
    yield "header cookie-session", "Cookie: session=" + V_MIX + V_MIX, "HIT"
    for k in ("pin", "PIN"):
        yield "pin %s digits" % k, k + "=" + "48213977", "HIT"
        yield "pin %s four" % k, k + "=" + "4821", "HIT"
        yield "pin %s three-neg" % k, k + "=" + "482", "negative"
        yield "pin %s letters-neg" % k, k + "=" + V_LET, "negative"
    # tool flags
    VS = (("v-mix", V_MIX, "HIT"), ("ref-dollar", REFS["ref-dollar"], "negative"), ("mask-stars", MASKS["mask-stars"], "negative"))
    for vn, v, e in VS:
        yield "tool redis-cli %s" % vn, "redis-cli -h db -a " + v + " ping", e
        yield "tool docker-login %s" % vn, "docker login -u bot -p " + v + " r.example", e
        yield "tool mongosh %s" % vn, "mongosh --username bot -p " + v, e
        yield "tool htpasswd %s" % vn, "htpasswd -b /etc/x.htpasswd admin " + v, e
        yield "tool htpasswd-c %s" % vn, "htpasswd -cb /etc/x.htpasswd admin " + v, e
        yield "tool openssl-passout %s" % vn, "openssl pkcs12 -export -passout pass:" + v + " -out x.p12", e
        yield "tool openssl-passin %s" % vn, "openssl rsa -passin pass:" + v + " -in k", e
        yield "tool sqlcmd %s" % vn, "sqlcmd -S db -U sa -P " + v, e
        yield "tool smbclient %s" % vn, "smbclient //h/s -U bob%" + v, e
        yield "tool gpg-passphrase %s" % vn, "gpg --batch --passphrase " + v + " -d x.gpg", e
    # a quoted value after whitespace (SQL)
    for t in ("ALTER USER app WITH " + PWU + " '%s';", "CREATE USER app IDENTIFIED BY '%s';",
              "create role r with " + PW + " '%s'", PW + ' "%s"'):
        yield "space-quoted %s v-mix" % t.split()[0], t % V_MIX, "HIT"
        yield "space-quoted %s v-let" % t.split()[0], t % V_LET, "boundary-space-quoted-letters"
    # the Authorization header, any scheme
    for sc in ("ApiKey", "Token", "Bearer", "SSWS", "Key", "Digest-x"):
        yield "authz %s v-mix" % sc, "Authorization: " + sc + " " + V_MIX, "HIT"
        yield "authz %s v-let" % sc, "Authorization: " + sc + " " + V_LET, "boundary-authz-letters"
    yield "authz bearer-16", "Authorization: Bearer " + V_MIX + "1234567", "HIT"
    # secret-manager references and identifier values (review r9 F5)
    for rn, r in (("vault", "vault:secret/data/db#" + PW), ("ref-plus", "ref+awsssm://prod/db/" + PW),
                  ("op", "op://vault/item/field1"), ("keyvault", "@Microsoft.KeyVault(SecretUri=https://kv/s/db)"),
                  ("gcp-sm", "sm://projects/p1/secrets/db"), ("arn", "arn:aws:secretsmanager:eu-1:123:secret:db1")):
        yield "reference %s colon" % rn, PW + ": " + r, "negative"
        yield "reference %s eq" % rn, PW + "=" + r, "negative"
    for vn, v in (("suite", "lint_suite_2"), ("dashed", "cache-v2-entry"), ("dotted", "build.step2.done")):
        yield "identifier pass %s" % vn, "result pass=" + v + " fail=0", "negative"
        yield "identifier token %s" % vn, "tok" + "en=" + v, "negative"
    # a tab inside a value is a table cell (review r9 RV12)
    yield "tab-in-value pwd", "pw" + 'd="col1\tcol2val9"', "negative"
    yield "tab-in-value password", PW + '="col1\tcol2val9"', "negative"


# ---- round 10 (review r9 R9-1 to R9-4): the classes the round-10 front end claims, each member tagged with
# its class (class_inventory.md of the v10 pack, rows L36 to L52), so that the census COUNTS every class it
# claims and a class with no member is a BLIND census, not a silent zero
import base64 as _b64
import itertools as _it

V10 = "Zq7" * 3 + "Wm4"                  # twelve characters, a letter and a digit (fake)
_SEP10 = [("eq", "="), ("eq-sp", " = "), ("colon-sp", ": ")]


def _pct10(s, n):
    for i in range(n):
        s = "".join("%%%02X" % ord(c) for c in s) if i == 0 else s.replace("%", "%25")
    return s


# the word for "password" in other languages, written here again (the lint keeps its own list)
NATIVE10 = ["пароль", "лозинка",
            "парола", "κωδικος",
            "密码", "密碼", "パスワード", "비밀번호",
            "암호", "סיסמה", "पासवर्ड",
            "parola", "haslo", "hasło", "heslo", "jelszo", "geslo", "parool", "passord", "losenord",
            "adgangskode", "kodeord", "sifre", "sifra", "katasandi", "motdepasse", "wagwoord", "sandi", "parolja"]
# confusable letters for the letters of "password", by script (an own list: Coptic, Cherokee small and
# capital, Armenian, Lisu, Cyrillic)
SKEL10 = {"p": ["ⲣ", "ꮲ"], "a": ["ⲁ", "ꭺ"], "s": ["ꮪ"], "w": ["ⲱ", "ꮃ", "ѡ"],
          "o": ["ⲟ", "օ"], "r": ["ꭱ"], "d": ["ꭰ"],
          "P": ["Ⲣ", "Ꮲ", "ꓑ"], "A": ["Ⲁ", "Ꭺ", "ꓮ"], "S": ["Ꮪ", "ꓢ"],
          "W": ["Ⲱ", "Ꮃ", "ꓪ", "Ѡ", "Ԝ"], "O": ["Ⲟ", "Օ", "ꓳ"],
          "R": ["Ꭱ", "ꓣ"], "D": ["Ꭰ", "ꓓ"]}
ZETA = "ζ"                          # a non-ASCII letter no fold maps


def members_r10():
    """(class, label, text, expected) for every round-10 class member."""
    # L36 split heads
    for k in ("pass_" + "word", "pass-" + "word", "pass" + "Word", "PASS_" + "WORD", "Pass." + "Word",
              "mot_de_" + "passe", "mot-de-" + "passe", "secret_" + "word"):
        for sn, s in _SEP10:
            yield "L36", "split %s %s mix" % (k, sn), k + s + V10, "HIT"
            yield "L36", "split %s %s short" % (k, sn), k + s + V10[:7], "negative"
    # L37 stand-in letters in a head: at most half (every position set of password and token)
    for head, lim in ((PW, 4), ("tok" + "en", 2)):
        for k in range(1, len(head) + 1):
            for pos in _it.combinations(range(len(head)), k):
                w = "".join(ZETA if i in pos else c for i, c in enumerate(head))
                yield "L37", "standin %s k=%d %s" % (head[:3], k, "".join(map(str, pos))), w + "=" + V10, \
                    "HIT" if k <= lim else "boundary-standins-over-half"
    # L38 an identifier-shaped value after a strong key, a generic key
    for vn, v in (("snake", "dbpass_prod2"), ("dash", "app-cred-v2"), ("dot", "svc.key.prod9")):
        yield "L38", "ident strong %s" % vn, PW + "=" + v, "HIT"
        yield "L38", "ident generic %s" % vn, "tok" + "en=" + v, "negative"
    # L39 a colon inside a value: a credential unless it is a URI with / or #
    for vn, v, e in (("colon", "Qz7k:Wm4Rt9p", "HIT"), ("two-colons", "ab9:cd8:ef7x", "HIT"),
                     ("uri-slash", "vlt:secret/db9x", "negative"), ("uri-hash", "kv:item#field9", "negative")):
        yield "L39", "colon-value %s" % vn, PW + "=" + v, e
    # L40 escapes of every form on every letter of the key
    forms = [("u4", lambda c: "\\u%04x" % ord(c)), ("ubrace", lambda c: "\\u{%x}" % ord(c)),
             ("U8", lambda c: "\\U%08x" % ord(c)), ("xbrace", lambda c: "\\x{%x}" % ord(c)),
             ("x2", lambda c: "\\x%02x" % ord(c)), ("oct", lambda c: "\\%03o" % ord(c))]
    for fn, f in forms:
        for i in range(len(PW)):
            yield "L40", "escape %s pos%d" % (fn, i), PW[:i] + f(PW[i]) + PW[i + 1:] + "=" + V10, "HIT"
    # L41 base64 of a whole assignment
    for kn, line in (("pw", PW + "=" + V10), ("dbpw", "DB_" + PW.upper() + "=" + V10), ("colon", PW + ": " + V10)):
        raw = line.encode()
        yield "L41", "base64 std %s" % kn, _b64.b64encode(raw).decode(), "HIT"
        yield "L41", "base64 nopad %s" % kn, _b64.b64encode(raw).decode().rstrip("="), "HIT"
        yield "L41", "base64 urlsafe %s" % kn, _b64.urlsafe_b64encode(raw + b"??>").decode(), "HIT"
    for pn, prose in (("hello", b"hello world, nothing here at all"), ("csv", b"a,b,c,d,e,f,g,h,i,j,k,l")):
        yield "L41", "base64 prose %s" % pn, _b64.b64encode(prose).decode(), "negative"
    # L42 percent and entity layers on the key, past the closure depth
    for n in range(1, 9):
        yield "L42", "percent depth%d" % n, _pct10(PW, n) + "=" + V10, "HIT"
    ent = "".join("&#%d;" % ord(c) for c in PW)
    for n in range(1, 4):
        yield "L42", "entity-in-percent depth%d" % n, _pct10(ent, n) + "=" + V10, "HIT"
    yield "L42", "entity no-semicolon", "&#112" + "assword=" + V10, "HIT"
    yield "L42", "entity named equals", PW + "&equals;" + V10, "HIT"
    # L43 confusable skeleton letters (one per member, in place)
    for i, c in enumerate(PW):
        for alt in SKEL10[c]:
            yield "L43", "skeleton low pos%d U+%04X" % (i, ord(alt)), PW[:i] + alt + PW[i + 1:] + "=" + V10, "HIT"
    PWU = PW.upper()
    for i, c in enumerate(PWU):
        for alt in SKEL10[c]:
            yield "L43", "skeleton up pos%d U+%04X" % (i, ord(alt)), PWU[:i] + alt + PWU[i + 1:] + "=" + V10, "HIT"
    # L44 the multilingual lexicon
    for wi, w in enumerate(NATIVE10):
        for sn, s in _SEP10 + [("fat-arrow", " => ")]:
            yield "L44", "native %02d %s mix" % (wi, sn), w + s + V10, "HIT"
            yield "L44", "native %02d %s short" % (wi, sn), w + s + V10[:7], "negative"
        yield "L44", "native %02d prose" % wi, w + " is required here", "negative"
    # L45 table rows
    for kn, k in (("long", PW), ("generic", "tok" + "en"), ("api", "api_" + "key")):
        for ln, (lead, bt) in (("lead", ("| ", "")), ("nolead", ("", "")), ("backtick", ("| ", "`"))):
            row = lead + bt + k + bt + " | " + bt + "%s" + bt + " |"
            yield "L45", "table %s %s mix" % (kn, ln), "\n" + row % V10 + "\n", "HIT"
            yield "L45", "table %s %s words" % (kn, ln), "\n" + row % "description" + "\n", "negative"
            yield "L45", "table %s %s short" % (kn, ln), "\n" + row % V10[:7] + "\n", "negative"
    # L46 set statements (Tcl, Expect)
    for kn, k in (("long", PW), ("generic", "tok" + "en"), ("secret", "sec" + "ret")):
        yield "L46", "set %s mix" % kn, "\nset " + k + " " + V10 + "\n", "HIT"
        yield "L46", "set %s semicolon" % kn, "\nset " + k + " " + V10 + "; puts ok\n", "HIT"
        yield "L46", "set %s two-words" % kn, "\nset " + k + " policy strict\n", "negative"
    # L47 the R arrows
    for an, a in (("left", " <- "), ("super", " <<- ")):
        for q in ('"', "'"):
            yield "L47", "arrow %s %s" % (an, "dq" if q == '"' else "sq"), PW + a + q + V10 + q, "HIT"
    # L48 triple quotes, parenthesised and joined literals
    for qn, q in (("dq3", '"""'), ("sq3", "'''")):
        yield "L48", "triple %s" % qn, PW + " = " + q + V10 + q, "HIT"
    yield "L48", "paren single", PW + ' = ("' + V10 + '")', "HIT"
    yield "L48", "paren split newline", PW + ' = ("' + V10[:6] + '"\n    "' + V10[6:] + '")', "HIT"
    for on, op in (("plus", "+"), ("dot", "."), ("dotdot", ".."), ("pipes", "||"), ("amp", "&"), ("tilde", "~")):
        yield "L48", "join %s" % on, PW + ' = "' + V10[:6] + '" ' + op + ' "' + V10[6:] + '"', "HIT"
        yield "L48", "join %s newline" % on, PW + ' = "' + V10[:6] + '" ' + op + '\n "' + V10[6:] + '"', "HIT"
    # L49 the type= attribute key
    for tn, t in (("input", '<input type="' + PW + '" value="%s">'), ("id", '<param id="' + PW + '" value="%s"/>')):
        yield "L49", "attr %s mix" % tn, t % V10, "HIT"
        yield "L49", "attr %s short" % tn, t % V10[:7], "negative"
    # L50 tickets, versions and secret-store references
    for kn, k in (("token", "tok" + "en"), ("key", "key"), ("short", "DB_PA" + "SS")):
        for vn, v in (("ticket", "CON-1234"), ("ticket2", "AB12-9"), ("ver", "6.4.0-rc1-build42"),
                      ("ver-v", "v1.2.3-beta4")):
            yield "L50", "value %s %s" % (kn, vn), k + "=" + v, "negative"
    for rn in ("env", "file", "secret", "vault", "sops", "ssm", "keyring", "op", "k8s", "kms"):
        yield "L50", "ref-scheme %s" % rn, PW + ": " + rn + ":DB_" + PW.upper(), "negative"
    # L51 digest key tails
    for tail in ("sha", "sha1", "sha256", "sha512", "md5", "checksum", "fingerprint"):
        for kn, k in (("pw", PW), ("token", "tok" + "en"), ("key", "key")):
            yield "L51", "digest %s %s" % (kn, tail), k + "_" + tail + "=" + "0a1b2c3d4e5f" * 4, "negative"
    # L52 spacing marks inside a key (Devanagari, the lint strips Mc with the other marks)
    for sn, s in _SEP10:
        yield "L52", "mc-key hindi %s" % sn, NATIVE10[10] + s + V10, "HIT"
        yield "L52", "mc-key latin-with-mc %s" % sn, "paाss" + "word" + s + V10, "HIT"


R10_CLASSES = ("L36", "L37", "L38", "L39", "L40", "L41", "L42", "L43", "L44", "L45", "L46", "L47", "L48", "L49",
               "L50", "L51", "L52")


def load(path):
    loader = importlib.machinery.SourceFileLoader("lint_under_census", path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


def hits(m, text):
    scan = getattr(m, "secret_hits", None)
    if scan is not None:
        return [n for n, _ in scan(text)]
    t = unicodedata.normalize("NFKC", text) if getattr(m, "SECRET_NFKC", False) else text
    return [n for n, rx in m.SECRET_PATTERNS if rx.search(t)]


def main(argv):
    if not argv or argv[0].startswith("-"):
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    try:
        m = load(argv[0])
    except Exception as e:  # any load failure is a blind instrument
        print("BLIND: the lint could not be loaded: %s" % type(e).__name__)
        return 3
    listing = "--list" in argv[1:]
    if not hits(m, "x DB_" + PW.upper() + "=" + V_MIX + " y"):
        print("BLIND: the positive control needle was not found")
        return 3
    if hits(m, "the " + PW + " was rotated yesterday"):
        print("BLIND: the negative control needle was reported")
        return 3
    print("control needles: PASS (a known member found, a prose line not reported)")
    c = {"members": 0, "hit": 0, "neg": 0, "bnd": 0, "gap": 0, "fp": 0}
    import itertools
    per = {k: [0, 0, 0, 0] for k in R10_CLASSES}  # members, hit, gap, fp
    tagged = (("", lb, tx, ex) for lb, tx, ex in itertools.chain(members(), members_r9()))
    for cls, label, text, exp in itertools.chain(tagged, members_r10()):
        c["members"] += 1
        if cls:
            per[cls][0] += 1
        got = bool(hits(m, "x " + text + " y"))
        if exp == "HIT":
            if got:
                c["hit"] += 1
                v = "HIT"
                if cls:
                    per[cls][1] += 1
            else:
                c["gap"] += 1
                v = "GAP"
                if cls:
                    per[cls][2] += 1
                print("MISMATCH GAP %s" % label)
        else:
            if got:
                c["fp"] += 1
                v = "FP"
                if cls:
                    per[cls][3] += 1
                print("MISMATCH FP %s (%s)" % (label, exp))
            else:
                c["neg" if exp == "negative" else "bnd"] += 1
                v = "MISS-" + exp
        if listing:
            print("MEMBER %s %s" % (v, label))
    empty = [k for k in R10_CLASSES if per[k][0] == 0]
    for k in R10_CLASSES:
        print("CLASS %s members=%d hit=%d gap=%d fp=%d" % (k, per[k][0], per[k][1], per[k][2], per[k][3]))
    if empty:
        print("BLIND: a claimed class has no member: %s" % ",".join(empty))
        return 3
    print("RESULT: members=%d hit=%d miss_negative=%d miss_boundary=%d gap=%d fp=%d"
          % (c["members"], c["hit"], c["neg"], c["bnd"], c["gap"], c["fp"]))
    return 0 if c["gap"] == 0 and c["fp"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
