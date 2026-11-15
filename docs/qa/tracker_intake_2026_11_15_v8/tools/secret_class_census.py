#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_15_v8/tools/secret_class_census.py -- enumerate the keyed-credential
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
    for label, text, exp in members():
        c["members"] += 1
        got = bool(hits(m, "x " + text + " y"))
        if exp == "HIT":
            if got:
                c["hit"] += 1
                v = "HIT"
            else:
                c["gap"] += 1
                v = "GAP"
                print("MISMATCH GAP %s" % label)
        else:
            if got:
                c["fp"] += 1
                v = "FP"
                print("MISMATCH FP %s (%s)" % (label, exp))
            else:
                c["neg" if exp == "negative" else "bnd"] += 1
                v = "MISS-" + exp
        if listing:
            print("MEMBER %s %s" % (v, label))
    print("RESULT: members=%d hit=%d miss_negative=%d miss_boundary=%d gap=%d fp=%d"
          % (c["members"], c["hit"], c["neg"], c["bnd"], c["gap"], c["fp"]))
    return 0 if c["gap"] == 0 and c["fp"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
