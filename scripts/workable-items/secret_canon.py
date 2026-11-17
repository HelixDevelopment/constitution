"""scripts/workable-items/secret_canon.py -- the ONE shared credential rule set of the intake lint and
the evidence-pack leak scan (round 11, review r10 finding 1).

Documentation (section 11.4.18): docs/guides/intake_lint_guide.md, section "Canonical form (round 11)".
Class inventory: docs/qa/tracker_intake_2026_11_16_v11/class_inventory.md.

WHY   Rounds 7 to 10 closed the secret class one spelling, one encoding and one layout at a time; every
      review found the next member. This module replaces that with one primitive that is class-wide by
      construction:
        1. DECODE  every text is read in up to SECRET_LAYERS decoded layers (escapes of every common
           syntax, percent and %u, HTML entities, CSS escapes, Unicode names, NUL bytes, quoted-printable
           soft breaks, joined string literals, and whole hex / base32 / base64 runs replaced in place);
        2. FOLD    each view is folded to one canonical form: NFKC, format characters removed, combining
           marks removed, lookalike letters of other scripts (Cyrillic, Greek, small capitals, any letter
           whose Unicode name is LATIN ... LETTER X) mapped to Latin; case is kept for word splitting and
           dropped for matching;
        3. WORDS   the folded view is split into words (letters and digits of any script), camelCase is
           split, and a run of single letters separated by at most one separator ("p a s s", "p_a_s_s",
           "p.a.s.s") is squashed into one word; a key is then matched on the words joined WITHOUT their
           separators, so "pass_word", "mot de passe", "palavra-passe" and "p-a-s-s-w-o-r-d" are one
           keyword each;
        4. KEY     one vocabulary (STRONG, SHORT, QUALIFIED) decides whether a word sequence is a
           credential key; a following attached word cancels it unless it is in TAIL_OK (a value
           or environment suffix), a number or a version: an allow-list, so a property word nobody
           listed (password_fingerprint, token_foo) cancels the key too;
        5. VALUE   the value is read after the key with one layout reader (any assignment operator, a
           separator comma, a space, a YAML block indicator, one line break) or from a name/value record
           in either order; one value classifier (credential_value) decides.
      The lint and the leak scan both call hits(); the scan keeps its own independent value-shape
      detectors (vendor token prefixes, URL user-info, tool flags, pgpass lines) and the lint keeps its
      token shapes, so a value with no key is still found by a second reader.
API   hits(text) -> list of (rule, value) ; rule is "canonical-key" or "canonical-record"
      canonical_views(text) -> list of folded views ; key_tier(words) ; credential_value(tier, v, op)
SAFETY  No value is ever printed by this module.
EVIDENCE CLASS  gate-logic only (section 11.4.289).
"""
import base64
import binascii
import html
import re
import unicodedata

SECRET_LAYERS = 3        # decoded layers on top of the input
SECRET_MAX_VIEWS = 24    # cap on views per input
SECRET_MAX_LEN = 200000  # longer inputs are read in windows of this size (overlapping)
SQUASH_MIN = 3           # a run of at least this many single letters is squashed into one word
JOIN_MAX = 4             # a keyword may be written as at most this many words

# ---- vocabulary -----------------------------------------------------------------------------------
# STRONG: the word for "password" (or an equally strong credential noun) in any spelling; matched on the
# folded, lower-cased, separator-free form. A word that ENDS with a strong word of 6 letters or more is a
# key too (PGPASSWORD, dbpassword, mypassphrase).
_STRONG_RAW = (
    "password", "passwd", "passphrase", "passwort", "kennwort", "contrasena", "contrasenya", "contrasinal",
    "senha", "palavrapasse", "wachtwoord", "lozinka", "salasana", "credential", "credentials", "motdepasse",
    "parola", "haslo", "has\u0142o", "heslo", "jelszo", "jelsz\u00f3", "geslo", "parool", "passord", "losenord",
    "l\u00f6senord", "adgangskode", "kodeord", "sifre", "\u015fifre", "sifra", "\u0161ifra", "katasandi",
    "wagwoord", "sandi", "parolja", "slaptazodis", "slapta\u017eodis", "lykilor\u00f0", "lykilord", "nenosiri",
    "salasona", "salas\u00f5na", "matkhau", "m\u1eadtkh\u1ea9u", "clave", "contrase\u00f1a", "passwortes",
    "parole", "parolo", "pasahitza", "sifra", "fjal\u00ebkalim", "fjalekalim", "gesla", "kupiaumiko",
    "securestring", "bindpw", "rootpw",
    "\u043f\u0430\u0440\u043e\u043b\u044c",                    # ru, uk, be
    "\u043b\u043e\u0437\u0438\u043d\u043a\u0430",              # sr, hr (Cyrillic)
    "\u043f\u0430\u0440\u043e\u043b\u0430",                    # bg, mk
    "\u043d\u0443\u0443\u0446\u04af\u0433",                    # mn: nuuts ug (joined)
    "\u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03c2",              # el: kodikos
    "\u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03c3\u03c0\u03c1\u03bf\u03c3\u03b2\u03b1\u03c3\u03b7\u03c2",  # el (joined)
    "\u5bc6\u7801", "\u5bc6\u78bc", "\u53e3\u4ee4",              # zh
    "\u30d1\u30b9\u30ef\u30fc\u30c9",                          # ja
    "\ube44\ubc00\ubc88\ud638", "\uc554\ud638",              # ko
    "\u05e1\u05d9\u05e1\u05de\u05d4",                          # he
    "\u092a\u093e\u0938\u0935\u0930\u094d\u0921",            # hi
    "\u0e23\u0e2b\u0e31\u0e2a\u0e1c\u0e48\u0e32\u0e19",      # th: rahat phan
    "\u0643\u0644\u0645\u0629\u0627\u0644\u0645\u0631\u0648\u0631",  # ar: kalimat al-murur (joined)
    "\u0643\u0644\u0645\u0647\u0627\u0644\u0633\u0631",      # ar variant (joined)
    "\u0631\u0645\u0632\u0639\u0628\u0648\u0631",            # fa: ramz-e obur (joined)
    "\u06af\u0630\u0631\u0648\u0627\u0698\u0647",            # fa: gozarvazhe
    "\u067e\u0627\u0633\u0648\u0631\u0688",                  # ur
    "\u09aa\u09be\u09b8\u0993\u09af\u09bc\u09be\u09b0\u09cd\u09a1",  # bn
    "\u0b95\u0b9f\u0bb5\u0bc1\u0b9a\u0bcd\u0b9a\u0bca\u0bb2\u0bcd",  # ta: kadavuchol
    "\u10de\u10d0\u10e0\u10dd\u10da\u10d8",                  # ka: paroli
    "\u0563\u0561\u0572\u057f\u0576\u0561\u0562\u0561\u057c",  # hy: gaghtnabar
)
# SHORT: a value with a letter and a digit (or a special character); whole words only
_SHORT_RAW = ("pwd", "pw", "pass", "passw", "pword", "pswd", "psw", "passcode", "auth", "session", "sid",
              "cookie", "key", "requirepass", "masterauth")
# GENERIC: a value of 8 characters after "=", a letter and a digit after any other separator
_GENERIC_RAW = ("secret", "secrets", "token", "creds", "cred")
# QUALIFIED compounds that are strong keys (written as one word or as two)
_QUALIFIED_RAW = ("apikey", "secretkey", "privatekey", "accesskey", "authtoken", "accesstoken", "refreshtoken",
                  "clientsecret", "apisecret", "apitoken", "bearertoken", "idtoken", "sessiontoken",
                  "secretword", "accountkey", "sharedkey", "signingkey", "masterkey")
# DIRECTIVES: config-file keys written "key VALUE" with no operator (ldap.conf, slapd.conf, redis.conf)
DIRECTIVES = frozenset({"bindpw", "rootpw", "requirepass", "masterauth"})
# a word that ENDS with one of these (and has at least 2 letters before it) is a short key: bindpw,
# rootpw, ldappwd, dbpw. "pass" is NOT a suffix (bypass, compass, surpass, trespass).
_SHORT_SUFFIX = ("pwd", "pw", "passwd", "pswd")
# qualified: "key", "token", "secret" after one of these words
_QUAL_KEY = {"secret", "private", "access", "api", "signing", "encryption", "master", "client", "shared", "app",
             "hmac", "jwt", "aes", "crypt", "crypto", "admin", "root", "ssh", "gpg", "pgp", "rsa", "otp",
             "totp", "mfa", "recovery", "kms", "license", "licence", "deploy", "webhook", "service", "auth"}
_QUAL_TOKEN = {"auth", "access", "refresh", "bearer", "api", "oauth", "app", "bot", "personal", "deploy",
               "service", "github", "gitlab", "slack", "npm", "pypi", "webhook", "jwt", "client", "admin",
               "security", "discord", "telegram", "hf", "ci", "runner", "private", "secret", "master", "root"}
# a word written ATTACHED to a short key that makes an English word, not a key (byPass, oAuth, BYPWD,
# compass, trespass): ported from the round-10 lint (SHORT_JOIN_NEGATIVE), lost in the round-11 rewrite
# and found by the census class "p-joined-bypass" / "p-joined-oauth" / "camel-short-neg"
SHORT_JOIN_NEGATIVE = frozenset({"by", "o", "com", "sur", "tres", "over", "under", "im", "en", "mis", "re", "pre",
                                 "out", "up", "bi", "ex"})
# a word before "key" that makes it something other than a credential
KEY_NEGATIVE = {"public", "pub", "foreign", "primary", "sort", "partition", "hash", "cache", "map", "dict", "row",
                "lookup", "idempotency", "unique", "composite", "natural", "surrogate", "routing", "shard", "object",
                "group", "config", "registry", "translation", "i18n", "react", "item", "field", "column", "index",
                "json", "yaml", "sorting", "keyboard", "hot", "short", "cut", "home", "end", "dedup", "join",
                "match", "node", "entry", "the", "a", "page", "next", "continuation", "cursor", "pagination",
                "lexer", "parser", "design", "sync", "input", "output", "max", "min", "csrf", "xsrf", "stop",
                "special", "pad", "mask", "music", "piano", "door", "car", "house", "main", "this", "that"}
# a word after the key word that does not cancel it (DB_PASSWORD_VALUE, password_plain)
TAIL_OK = {"value", "val", "str", "string", "plain", "plaintext", "raw", "b64", "base64", "literal",
           "prod", "production", "dev", "development", "staging", "stage", "qa", "uat", "local", "live",
           "primary", "secondary", "old", "new", "current", "previous", "next", "backup", "admin", "root",
           "default", "main", "master", "ro", "rw"}
_TAIL_VERSION = re.compile(r"^v?[0-9]+$")
# record selectors and record value fields (name/value pairs in either order)
_SELECTOR_FIELDS = {"name", "key", "id", "parameter", "parameterkey", "variable", "var", "envname", "keyname",
                    "type"}
_VALUE_FIELDS = {"value", "parametervalue", "secretvalue", "val", "secretstring"}

# ---- folding ---------------------------------------------------------------------------------------
_CONF = {
    # Cyrillic
    "\u0430": "a", "\u0435": "e", "\u043e": "o", "\u0440": "p", "\u0441": "c", "\u0443": "y", "\u0445": "x",
    "\u0456": "i", "\u0458": "j", "\u0455": "s", "\u0501": "d", "\u051b": "q", "\u051d": "w", "\u04bb": "h",
    "\u0410": "A", "\u0412": "B", "\u0415": "E", "\u041a": "K", "\u041c": "M", "\u041d": "H", "\u041e": "O",
    "\u0420": "P", "\u0421": "C", "\u0422": "T", "\u0425": "X", "\u0406": "I", "\u0408": "J", "\u0405": "S",
    "\u04ae": "Y", "\u0423": "Y",
    # Greek
    "\u03b1": "a", "\u03bf": "o", "\u03c1": "p", "\u03b9": "i", "\u03ba": "k", "\u03bd": "v",
    "\u03c4": "t", "\u03c5": "u", "\u03c7": "x", "\u03c9": "w", "\u03b2": "b", "\u03b7": "n",
    "\u0391": "A", "\u0392": "B", "\u0395": "E", "\u0396": "Z", "\u0397": "H", "\u0399": "I", "\u039a": "K",
    "\u039c": "M", "\u039d": "N", "\u039f": "O", "\u03a1": "P", "\u03a4": "T", "\u03a5": "Y", "\u03a7": "X",
    # Latin letters without a decomposition
    "\u0131": "i", "\u0237": "j", "\u017f": "s", "\u0142": "l", "\u0141": "L", "\u00f8": "o", "\u00d8": "O",
    "\u0111": "d", "\u0110": "D", "\u00f0": "d", "\u00d0": "D", "\u00fe": "th", "\u00df": "ss", "\u0127": "h",
    "\u00e6": "ae", "\u0153": "oe",
}
# the confusable skeleton of the round-10 lint (Coptic, Cherokee, Armenian, Lisu, more Cyrillic), the
# same table, now owned here
_SKELETON = {
    # Coptic
    "\u2c80": "A", "\u2c81": "a", "\u2c82": "B", "\u2c88": "E", "\u2c8e": "H", "\u2c92": "I",
    "\u2c93": "i", "\u2c94": "K", "\u2c95": "k", "\u2c98": "M", "\u2c9a": "N", "\u2c9e": "O",
    "\u2c9f": "o", "\u2ca2": "P", "\u2ca3": "p", "\u2ca4": "C", "\u2ca5": "c", "\u2ca6": "T",
    "\u2ca8": "Y", "\u2ca9": "y", "\u2cac": "X", "\u2cad": "x", "\u2cb0": "W", "\u2cb1": "w",
    # Cherokee capitals and their small letters (U+AB70 + (capital - U+13A0))
    "\u13aa": "A", "\uab7a": "a", "\u13f4": "B", "\u13df": "C", "\uabaf": "c", "\u13a0": "D",
    "\uab70": "d", "\u13ac": "E", "\uab7c": "e", "\u13c0": "G", "\uab90": "g", "\u13bb": "H",
    "\uab8b": "h", "\u13ab": "J", "\uab7b": "j", "\u13e6": "K", "\uabb6": "k", "\u13de": "L",
    "\uabae": "l", "\u13b7": "M", "\uab87": "m", "\u13e2": "P", "\uabb2": "p", "\u13a1": "R",
    "\uab71": "r", "\u13da": "S", "\uabaa": "s", "\u13a2": "T", "\uab72": "t", "\u13d9": "V",
    "\uaba9": "v", "\u13b3": "W", "\uab83": "w", "\u13c3": "Z", "\uab93": "z",
    # Armenian
    "\u0585": "o", "\u0555": "O", "\u057d": "u", "\u054d": "U", "\u0578": "n", "\u0570": "h",
    "\u0581": "g", "\u0566": "q", "\u053c": "L",
    # Lisu
    "\ua4ee": "A", "\ua4d0": "B", "\ua4da": "C", "\ua4d3": "D", "\ua4f0": "E", "\ua4dd": "F",
    "\ua4d6": "G", "\ua4e7": "H", "\ua4f2": "I", "\ua4d9": "J", "\ua4d7": "K", "\ua4e1": "L",
    "\ua4df": "M", "\ua4e0": "N", "\ua4f3": "O", "\ua4d1": "P", "\ua4e3": "R", "\ua4e2": "S",
    "\ua4d4": "T", "\ua4f4": "U", "\ua4e6": "V", "\ua4ea": "W", "\ua4eb": "X", "\ua4ec": "Y",
    "\ua4dc": "Z",
    # more Cyrillic
    "\u04cf": "l", "\u0461": "w", "\u0460": "W", "\u0475": "v", "\u0474": "V", "\u0491": "r",
    "\u051c": "W", "\u0412": "B",
}
_CONF.update(_SKELETON)
_LATIN_NAME = re.compile(r"^LATIN (?:(SMALL|CAPITAL) )?LETTER (?:SMALL CAPITAL )?([A-Z]|ALPHA|DOTLESS [IJ]|LONG S|"
                         r"OPEN [EO]|SCRIPT [A-Z]|IOTA|UPSILON|TURNED [A-Z]|REVERSED [A-Z]|STRETCHED [A-Z])$")
_LATIN_WORD = {"ALPHA": "a", "IOTA": "i", "UPSILON": "u", "LONG S": "s"}
_FOLD_CACHE = {}


MC_MARK = "\u01c3"


def _fold_char(ch):
    r = _FOLD_CACHE.get(ch)
    if r is not None:
        return r
    if ch in _CONF:
        r = _CONF[ch]
    elif ord(ch) < 128:
        r = ch
    else:
        cat = unicodedata.category(ch)
        # Mc too: an Indic vowel sign is not a word character; the vocabulary is folded the same way
        if cat in ("Mn", "Me", "Cf") or ch in "\u115f\u1160\u3164\uffa0\u00ad":
            r = ""
        elif cat == "Mc":
            # a spacing mark stands where a letter stood (p<vowel sign>ssword): one placeholder letter, so the
            # one-letter wildcard reads it; a run of marks is collapsed to one in fold()
            r = MC_MARK
        else:
            m = _LATIN_NAME.match(unicodedata.name(ch, ""))
            if m:
                w = _LATIN_WORD.get(m.group(2), m.group(2)[-1])
                r = w.upper() if m.group(1) == "CAPITAL" else w.lower()
            else:
                r = ch
    _FOLD_CACHE[ch] = r
    return r


def fold(text):
    """NFKC, then NFD, then each character folded: combining marks and format characters dropped,
    lookalikes mapped to Latin. Case is kept (for camelCase splitting)."""
    t = unicodedata.normalize("NFKC", text)
    if t.isascii():
        return t
    t = unicodedata.normalize("NFD", t)
    t = "".join(_fold_char(c) for c in t)
    t = re.sub(MC_MARK + "{2,}", MC_MARK, t)
    return unicodedata.normalize("NFC", t)


def _key(word):
    return fold(word).lower()


STRONG = frozenset(re.sub(r"[\W_]+", "", _key(w)) for w in _STRONG_RAW)
STRONG_SUFFIX = tuple(sorted((w for w in STRONG if len(w) >= 6 and w.isascii()), key=len, reverse=True))
SHORT = frozenset(_SHORT_RAW)
GENERIC = frozenset(_GENERIC_RAW)
QUALIFIED = frozenset(_QUALIFIED_RAW)

# ---- decoding layers ---------------------------------------------------------------------------------
_ESC = re.compile(r"\\N\{([A-Za-z0-9 \-]{2,80})\}|\\u\{([0-9A-Fa-f]{1,6})\}|\\U([0-9A-Fa-f]{8})|\\u([0-9A-Fa-f]{4})"
                  r"|\\x\{([0-9A-Fa-f]{1,6})\}|\\x([0-9A-Fa-f]{2})|%u([0-9A-Fa-f]{4})|\\([0-7]{3})"
                  r"|\\([0-9A-Fa-f]{1,6}) ?(?![0-9A-Fa-f])|\\([\\/\"'])")
_PCT = re.compile(r"%([0-9A-Fa-f]{2})")
_JOIN = re.compile(r"([\"'])\s*(?:\+|\.\.?|\|\||&|~)?\s*\1")
_QP = re.compile(r"=\r?\n")
_HEX = re.compile(r"(?<![0-9A-Za-z])(?:[0-9A-Fa-f]{2}){8,}(?![0-9A-Za-z])")
_B32 = re.compile(r"(?<![0-9A-Za-z])(?:[A-Z2-7]{8}){2,}(?:[A-Z2-7]{2,7}=*)?(?![0-9A-Za-z=])")
_B64U = re.compile(r"(?<![0-9A-Za-z_-])(?=[A-Za-z0-9_-]*[_-])(?:[A-Za-z0-9_-]{4}){3,}[A-Za-z0-9_-]{0,3}(?![0-9A-Za-z_=-])")
_B64 = re.compile(r"(?<![0-9A-Za-z+/])(?:[A-Za-z0-9+/]{4}){2,}(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?(?![0-9A-Za-z+/=])")


def _unesc(m):
    g = m.groups()
    try:
        if g[0] is not None:
            return unicodedata.lookup(g[0])
        for i in (1, 2, 3, 4, 5, 6, 8):
            if g[i] is not None:
                return chr(int(g[i], 16))
        if g[7] is not None:
            return chr(int(g[7], 8))
        return g[9]
    except (KeyError, ValueError, OverflowError):
        return m.group(0)


def _printable(b):
    try:
        s = b.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not s or any(ord(c) < 32 and c not in "\t\n\r" for c in s):
        return None
    if sum(1 for c in s if c.isalnum()) * 2 < len(s):
        return None
    return s


def _blob(m, dec):
    try:
        b = dec(m.group(0))
    except (binascii.Error, ValueError):
        return m.group(0)
    s = _printable(b)
    return s if s is not None else m.group(0)


def _b32(s):
    return base64.b32decode(s + "=" * (-len(s) % 8))


_DECODERS = (
    lambda t: _ESC.sub(_unesc, t),
    lambda t: _PCT.sub(lambda m: chr(int(m.group(1), 16)), t),
    lambda t: html.unescape(t) if "&" in t else t,
    lambda t: t.replace("\x00", ""),
    lambda t: _QP.sub("", t),
    lambda t: _JOIN.sub("", t),
    lambda t: _HEX.sub(lambda m: _blob(m, bytes.fromhex), t),
    lambda t: _B32.sub(lambda m: _blob(m, _b32), t),
    lambda t: _B64.sub(lambda m: _blob(m, base64.b64decode), t),
    lambda t: _B64U.sub(lambda m: _blob(m, lambda x: base64.urlsafe_b64decode(x + "=" * (-len(x) % 4))), t),
)


def canonical_views(text):
    """The input and its decoded layers (each decoder alone, then everything to a fixpoint), folded."""
    seen = []
    frontier = [text]
    for _layer in range(SECRET_LAYERS + 1):
        nxt = []
        for t in frontier:
            if t in seen:
                continue
            seen.append(t)
            if len(seen) >= SECRET_MAX_VIEWS:
                break
            for d in _DECODERS:
                u = d(t)
                if u != t and u not in seen and u not in nxt:
                    nxt.append(u)
        frontier = nxt
        if not frontier or len(seen) >= SECRET_MAX_VIEWS:
            break
    # the full fixpoint of every decoder together
    t = text
    for _ in range(16):
        u = t
        for d in _DECODERS:
            u = d(u)
        if u == t:
            break
        t = u
    if t not in seen:
        seen.append(t)
    out = []
    for v in seen:
        f = fold(v)
        if f not in out:
            out.append(f)
    return out


# ---- words --------------------------------------------------------------------------------------------
_WORD = re.compile(r"[^\W_]+")
_CAMEL = re.compile(r"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")
_IDGAP = re.compile(r"^(?:[_.\-]|)$")           # inside one identifier
_JOINGAP = re.compile(r"^[ \t_.\-\u00b7]{0,2}$")  # may still be one keyword


def words(view):
    """[(word, start, end)] with camelCase split and single-letter runs squashed."""
    raw = []
    for m in _WORD.finditer(view):
        s = m.start()
        parts = _CAMEL.split(m.group(0))
        for p in parts:
            raw.append((p, s, s + len(p)))
            s += len(p)
    out = []
    i = 0
    while i < len(raw):
        j = i
        while (j + 1 < len(raw) and len(raw[j][0]) == 1 and len(raw[j + 1][0]) == 1
               and raw[j + 1][1] - raw[j][2] <= 1 and raw[j][0].isalpha()
               and _JOINGAP.match(view[raw[j][2]:raw[j + 1][1]])):
            j += 1
        if j - i + 1 >= SQUASH_MIN:
            out.append(("".join(w for w, _, _ in raw[i:j + 1]), raw[i][1], raw[j][2]))
            i = j + 1
        else:
            out.append(raw[i])
            i += 1
    return out


def _strip_digits(w):
    return w.rstrip("0123456789") or w


def _wild(w, h):
    """w (folded) matches h when every ASCII letter of w agrees and every non-ASCII letter is a wildcard,
    and at least half of w is ASCII: a lookalike letter that is not in the skeleton."""
    if len(w) != len(h) or w.isascii():
        return False
    asc = sum(1 for c in w if c.isascii())
    return asc * 2 >= len(w) and all(c == d or not c.isascii() for c, d in zip(w, h))


def word_tier(joined, prev, single=True):
    """The tier of one candidate key word (already folded, lower-cased, separator-free), or None.
    single: the candidate is ONE written word; the suffix rules (dbpassword, ldappwd) read only such a
    word, never a form joined across parts (x bypwd is not the key xbypwd, round 11 census)."""
    w = _strip_digits(joined)
    if w in STRONG or w in QUALIFIED:
        return "strong"
    if not w.isascii():
        for h in STRONG_SUFFIX:
            if _wild(w, h) or (len(w) > len(h) and _wild(w[-len(h):], h)):
                return "strong"
        for h in SHORT | GENERIC:
            if _wild(w, h):
                return "short" if h in SHORT else "generic"
    for h in STRONG_SUFFIX:
        if single and w.endswith(h) and len(w) > len(h) and w.isascii():
            return "strong"
    if w == "key":
        if prev in _QUAL_KEY:
            return "strong"
        return None if prev in KEY_NEGATIVE else "short"
    if w in ("token", "tokens"):
        if prev in _QUAL_TOKEN or prev.endswith("id"):
            return "strong"
        if prev in KEY_NEGATIVE:
            return None
    if w == "secret" and prev:
        return "strong" if prev in _QUAL_KEY else "generic"
    if w in SHORT:
        return "short"
    if w in GENERIC:
        return "generic"
    for h in _SHORT_SUFFIX:
        if single and w.endswith(h) and len(w) - len(h) >= 2 and w.isalpha() and w[:-len(h)] not in SHORT_JOIN_NEGATIVE:
            return "short"
    if w == "pin" or w == "pincode":
        return "numeric"
    return None


def key_spans(view):
    """[(tier, key_start, key_end)] for every credential key in a folded view: the key word(s) may be
    written in up to JOIN_MAX parts; a following attached word that names a property cancels the key."""
    ws = words(view)
    out = []
    lows = [w.lower() for w, _, _ in ws]
    for i in range(len(ws)):
        best = None
        for k in range(1, JOIN_MAX + 1):
            j = i - k + 1
            if j < 0:
                break
            # every gap inside the candidate must be at most two separator characters
            if k > 1 and not _JOINGAP.match(view[ws[j][2]:ws[j + 1][1]]):
                break
            # a number is never a fragment of a split key word: "key 24" (a count after a kind name) is
            # not the key key24, while key24 and key_24 written as one identifier still are (round 11,
            # a false positive on a list of kind names with counts in the landed tracker)
            if k > 1 and lows[j + 1].isdigit() and re.search(r"\s", view[ws[j][2]:ws[j + 1][1]]):
                break
            joined = "".join(lows[j:i + 1])
            prev = lows[j - 1] if j > 0 and _IDGAP.match(view[ws[j - 1][2]:ws[j][1]]) else ""
            t = word_tier(joined, prev, k == 1)
            # a short key attached with no separator to a word that makes an English word (byPass, oAuth)
            if t == "short" and j > 0 and view[ws[j - 1][2]:ws[j][1]] == "" and lows[j - 1] in SHORT_JOIN_NEGATIVE:
                t = None
            if t:
                best = (t, ws[j][1], ws[i][2])
                break  # the shortest spelling: setPassword is the key Password after "set"
        if not best:
            continue
        # the identifier continues after the key: a value suffix (TAIL_OK), a number or a version extends
        # the key; any other attached word stops it there, and since every reader of a span needs the
        # value (or the end of the name) right at the span's end, that word leaves the key without a value
        # (password_fingerprint=V, token_foo=V are not read). No separate "cancel" flag: it changed nothing
        # (round 11, mutant SM12c on every fixture, probe row and contract).
        e = best[2]
        q = i + 1
        while q < len(ws) and _IDGAP.match(view[e:ws[q][1]]):
            nw = lows[q]
            if not (nw in TAIL_OK or nw.isdigit() or _TAIL_VERSION.match(nw)):
                break
            e = ws[q][2]
            q += 1
        out.append((best[0], best[1], e))
    return out


# ---- the value classifier ----------------------------------------------------------------------------
_PLACEHOLDER_WORDS = {
    "changeme", "change_me", "change-me", "changeit", "replaceme", "replace_me", "placeholder", "redacted",
    "example", "examples", "sample", "dummy", "password", "passwd", "passphrase", "secret", "token",
    "required", "optional", "none", "null", "nil", "undefined", "true", "false", "enabled", "disabled",
    "rotated", "unset", "notset", "default", "hidden", "omitted", "removed", "changed", "provided",
    "yes", "no", "on", "off", "strict", "strong",
}
_PLACEHOLDER = re.compile(r"(?i)^(?:your|my|enter|insert|put|some)[-_.]|[-_.](?:here|goes[-_]here|placeholder)$"
                          r"|^<[^<>]*>$|^\{\{.*\}\}$|^\[[^\[\]]*\]$|redacted|\bmasked\b")
_MASK = re.compile(r"^[xX*.#\s\u2022-]+$")
_PATH = re.compile(r"^(?:/|~/|~$|\./|\.\./)")
_REF = re.compile(r"(?i)^(?:\$|%[A-Za-z_(]|\$\{|\{\{|<%|env:|file:|secret:|secrets:|vault:|op:|ssm:|sops:|keyring:|"
                  r"cmd:|exec:|ref\+|arn:aws|@[A-Za-z][\w.]*\()")
# a secret-store reference by name: any lower-case scheme, a colon, an upper-case variable name
# (kms:DB_PASSWORD, k8s:DB_PASSWORD); the census class L50 "ref-scheme" lists ten schemes, the rule is
# the shape, not the list
_REF_NAME = re.compile(r"^[a-z][a-z0-9+.-]{0,15}:[A-Z][A-Z0-9_]{2,}$")
_SQ_LITERAL = re.compile(r"^\$[A-Za-z0-9]{7,}$")
_ASSIGN_OPS = ("=", ":=", "::=", "?=", "+=", "=>", "<-", "<<-", "\uff1d")
_REF_URI = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]{1,}:(?://)?\S*[/#]")
_CODE_CALL = re.compile(r"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s*[(\[]")
_CODE_ATTR = re.compile(r"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+$")
# an identifier: lower-case alphanumeric parts joined by _ . -, starting with a letter, with at least one
# part that is a word of three or more letters (case_one_a1b2, test_login_2fa, lint_suite_2); a random
# string has no such word part (zq7_k9w2x). Round 11: the parts were letters-then-digits only, so a test
# label such as case_one_a1b2 after a short key (PASS:) was read as a value.
_IDENT = re.compile(r"^(?=(?:[a-z0-9]+[_.-])*[a-z]{3,}(?:[_.-]|$))[a-z][a-z0-9]*(?:[_.-][a-z0-9]+)+$")
_TICKET = re.compile(r"^[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}$")
_VERSION = re.compile(r"^v?[0-9]+(?:\.[0-9]+){1,3}(?:[-+][0-9A-Za-z][0-9A-Za-z.-]*)?$")
_SPECIAL = set("!@#%^&*+=?~|;:<>,")


def is_placeholder(v):
    """A mask, a placeholder word or a placeholder shape (<x>, {{x}}, [x], your_x, x_here, redacted)."""
    v = v.strip()
    return bool(_MASK.match(v)) or v.lower() in _PLACEHOLDER_WORDS or bool(_PLACEHOLDER.search(v))


def credential_value(tier, v, quoted, op="="):
    """Is v a credential value after a key of this tier? quoted: the quote character the value was written
    in ("" or False when unquoted); op: the separator between key and value ("" for a bare space)."""
    v = v.strip()
    if tier == "numeric":
        return bool(re.fullmatch(r"[0-9]{4,12}", v))
    if len(v) < 8 or len(v) > 4096:
        return False
    if is_placeholder(v):
        return False
    literal = quoted == "'" and bool(_SQ_LITERAL.match(v)) and any(c.isupper() for c in v) \
        and any(c.islower() for c in v) and any(c.isdigit() for c in v)
    if _PATH.match(v) or _REF_URI.match(v) or _REF_NAME.match(v) or (_REF.match(v) and not literal):
        return False
    if v[0] in "-<>{[(|":
        return False
    if tier in ("short", "generic") and v[0] == ".":
        return False
    if "\t" in v or (" " in v and not (quoted and tier == "strong" and op in _ASSIGN_OPS + (":",))):
        return False
    if not quoted and (_CODE_CALL.match(v) or (_CODE_ATTR.match(v) and not any(c.isdigit() for c in v))):
        return False
    has_l = any(c.isalpha() for c in v)
    has_d = any(c.isdigit() for c in v)
    has_s = any(c in _SPECIAL for c in v)
    if tier == "short" or (tier == "generic" and op not in _ASSIGN_OPS):
        if not has_l or not (has_d or has_s):
            return False
    # a short key then a colon and an unquoted value is a label (PASS: case_one, pw: see below), the
    # round-7 census boundary B (boundary-short-colon-unquoted); quoted, or with = and the other
    # operators, it is read
    if tier == "short" and not quoted and op in (":", "\uff1a"):
        return False
    if tier in ("short", "generic") and (_IDENT.match(v) or _TICKET.match(v) or _VERSION.match(v)):
        return False
    if tier == "space":  # a value after a bare space or a tab: letter AND digit, not an identifier
        if not (has_l and has_d) or _IDENT.match(v) or _TICKET.match(v) or _VERSION.match(v):
            return False
    if not (has_l or has_d):
        return False
    return True


# ---- the layout reader -------------------------------------------------------------------------------
# after the key: an optional key closer (quote, bracket), then an operator, then the value
_AFTER = re.compile(
    r"(?P<close>[\"'`]?\]?[\"'`]?\)?)"
    r"(?P<op>[ \t]*(?:::=|:=|\?=|\+=|!=|=>|<<-|<-|==|=|:|,|\||\(|\uff1d|\uff1a)[ \t]*|[ \t]+)"
    r"(?P<block>[|>][-+0-9]*[ \t]*\r?\n[ \t]*|\r?\n[ \t]*(?=[\"'`]))?"
    r"(?P<open>[(\[]?[ \t]*(?:[bBrRuUfF]{1,2}(?=[\"'`]))?)"
    r"(?:(?P<q>[\"'`])(?P<qv>(?:\\[^\n]|(?!(?P=q))[^\n\\]){0,4096})(?P=q)|(?P<uv>[^\s\"'`,;)\]}|]{1,4096}))")
_DEFAULT_EXP = re.compile(r"^\$\{\w{1,128}:?[-=](?P<v>[^}]{1,4096})\}?$")
# the same, a quoted value read without backslash escapes (a value that ends in a backslash)
_AFTER_RAW = re.compile(_AFTER.pattern.replace(r"(?:\\[^\n]|(?!(?P=q))[^\n\\]){0,4096}", r"[^\n]{0,4096}?"))
_LINEBREAK_VALUE = re.compile(r"[ \t]*:[ \t]*\r?\n[ \t]+(?:(?P<q>[\"'`])(?P<qv>[^\n]{0,4096}?)(?P=q)|(?P<uv>\S+))")


def _value_after(view, end):
    m = _AFTER.match(view, end) or _AFTER_RAW.match(view, end)
    if not m:
        m = _LINEBREAK_VALUE.match(view, end)
        if not m:
            return None
        op = ":"
    else:
        op = m.group("op").strip(" \t")
        if m.group("op") and "\t" in m.group("op") and not op:
            op = "\t"
    if m.group("q") is not None:
        return m.group("qv"), m.group("q"), op, m.end()
    v = m.group("uv")
    d = _DEFAULT_EXP.match(v)
    if d:  # ${DB_PASSWORD:-VALUE}: the default is a literal
        return d.group("v"), "", op, m.end()
    return v, "", op, m.end()


_REC_FIELD = re.compile(r"(?P<f>[A-Za-z][A-Za-z_]{0,30})[\"'`]?[ \t]*[:=][ \t]*(?:(?P<q>[\"'`])(?P<qv>[^\n\"'`]{0,4096})(?P=q)"
                        r"|(?P<uv>[^\s\"'`,;()\[\]{}]{1,4096}))")


def _record_hits(view):
    """name/value records in either order: a selector field whose value is a credential key, and a value
    field in the same record (the same {...} or the next lines of one list item)."""
    out = []
    for chunk in re.split(r"[}\]]|\n[ \t]*-[ \t]|\n\s*\n", view):
        fields = [(m.group("f").lower().replace("_", ""), m.group("qv") if m.group("q") else m.group("uv"),
                   m.group("q") is not None) for m in _REC_FIELD.finditer(chunk)]
        sel = [v for f, v, _ in fields if f in _SELECTOR_FIELDS]
        if not sel:
            continue
        tier = None
        for v in sel:
            last = re.split(r"[/:]", v)[-1]
            for t, s, e in key_spans(last):
                if e == len(last.rstrip()):
                    tier = t
        if not tier:
            continue
        for f, v, q in fields:
            if f in _VALUE_FIELDS and credential_value("strong" if tier == "strong" else "short", v, "x" if q else ""):
                out.append(("canonical-record", v))
    return out


# tools whose credential argument has no key word: (pattern, value group). Matched on the folded view.
_TOOL_FORMS = [re.compile(p) for p in (
    r"(?i)(?<![\w-])(?:-u|--user)[ \t=]+[^\s:@]{1,256}:(?P<v>[^\s@\"'`]{1,4096})",            # curl -u u:V
    r"(?i)\b(?:mysql|mysqldump|mysqladmin|mariadb)\b[^\n]{0,256}?(?<![\w-])-p(?P<v>[^\s\"'`]{1,4096})",
    r"(?i)\bsshpass\b[ \t]+-p[ \t]*(?P<v>[^\s\"'`]{1,4096})",
    r"(?i)\bidentified[ \t]+(?:with[ \t]+\w+[ \t]+)?by[ \t]+(?P<q>[\"'`])(?P<v>[^\n]{1,4096}?)(?P=q)",
    r"(?i)\bhtpasswd[ \t]+-\w*b\w*[ \t]+\S+[ \t]+\S+[ \t]+(?P<v>\S+)",
    r"(?i)(?<![\w-])-pass(?:in|out)?[ \t]+pass:(?P<v>\S+)",
    r"(?i)\bredis-cli\b[^\n]{0,256}?(?<![\w-])-a[ \t]+(?P<v>[^\s\"'`]{1,4096})",
    r"(?i)\b(?:docker|podman|buildah|skopeo|helm|oras|nerdctl)[ \t]+(?:registry[ \t]+)?login\b[^\n]{0,256}?(?<![\w-])-p[ \t]+(?P<v>[^\s\"'`]{1,4096})",
    r"(?i)\b(?:mongo|mongosh|mongodump|mongorestore|mongoexport|mongoimport)\b[^\n]{0,256}?(?<![\w-])-p[ \t]+(?P<v>[^\s\"'`]{1,4096})",
    r"(?i)\blogin[ \t]+\S+[ \t]+pass(?:word|wd)?[ \t]+(?P<v>\S+)",                         # netrc
    r"(?i)\bauthorization\s*[:=]\s*(?:bearer|basic|token|digest|apikey|key|sso-key)\s+(?P<v>[A-Za-z0-9._~+/=:-]{8,4096})",
    r"(?m)^[ \t]*[^\s:#]+:(?:\d{1,5}|\*):[^\s:]+:[^\s:]+:(?P<v>\S+?)[ \t]*\r?$",            # pgpass
)]
# mysql -p is case-sensitive: -P is the port
_TOOL_FORMS[1] = re.compile(r"\b(?i:mysql|mysqldump|mysqladmin|mariadb)\b[^\n]{0,256}?(?<![\w-])-p(?P<v>[^\s\"'`]{1,4096})")
_URL = re.compile(r"(?i)(?<![\w+.-])[a-z][a-z0-9+.-]*://[^/\s:@\[\]]*:(?P<v>[^\s@/]+)@")
_XML_EL = re.compile(r"<(?P<k>[\w.:-]{1,256})(?:\s[^<>]*)?>\s*(?P<v>[^<>\s]{1,4096})\s*</(?P=k)\s*>")
_XML_ATTR = re.compile(r"(?i)<(?P<o>[\w:.-]+)\s[^<>]*?\b(?:key|name|id)\s*=\s*([\"'])(?P<k>[\w.:-]{1,256})\2[^<>]*?"
                       r"(?:\bvalue\s*=\s*([\"'])(?P<v>[^\"'<>]{1,4096})\4[^<>]*>|>\s*(?P<t>[^<>\s]{1,4096})\s*</(?P=o)\s*>)")


def _line_start(view, s):
    ls = view.rfind("\n", 0, s) + 1
    pre = view[ls:s].strip()
    return pre == "" or pre.lower().endswith(("login", "user")) or bool(re.fullmatch(r"(?i)[\w.\-]+\s+login\s+\S+", pre))


def _tool_hits(view):
    out = []
    for rx in _TOOL_FORMS:
        for m in rx.finditer(view):
            v = m.group("v")
            if credential_value("space", v, "") or credential_value("short", v, "'"):
                out.append(("canonical-tool", v))
    for m in _URL.finditer(view):
        v = m.group("v")
        if len(v) >= 6 and v[0] not in "${<[(" and not is_placeholder(v) and not re.fullmatch(r"(?i)x+|\*+|port|password|pass", v) \
                and not re.fullmatch(r"\d{1,5}", v):
            out.append(("canonical-url", v))
    for rx in (_XML_EL, _XML_ATTR):
        for m in rx.finditer(view):
            k = m.group("k")
            v = m.group("v") if m.group("v") is not None else (m.groupdict().get("t") or "")
            ks = key_spans(k)
            if ks and ks[-1][2] == len(k) and credential_value(
                    "strong" if ks[-1][0] == "strong" else "short", v, "x"):
                out.append(("canonical-xml", v))
    return out


_SETTER_BEFORE = re.compile(r"(?i)(?:\bset|\bput|\bwith)(?:_[a-z]{1,12}){0,2}_?$")
_SET_CMD_BEFORE = re.compile(r"(?i)(?:^|[;\[{\n])[ \t]*(?:set|setenv|export|set[ \t]+-[gx]x?)[ \t]+$")


def _ident_key(view, s, e):
    """The key is written as an identifier (several parts, a separator, upper case, a flag prefix)."""
    k = view[s:e]
    return bool(re.search(r"[_.\-]", k)) or (k.isupper() and len(k) > 3) or bool(_CAMEL.search(k)) \
        or view[max(0, s - 2):s] in ("--",) or view[max(0, s - 1):s] in (".", "_", "-")


def _view_hits(view):
    out = _tool_hits(view)
    for tier, s, e in key_spans(view):
        got = _value_after(view, e)
        if not got:
            continue
        v, quoted, op, vend = got
        vt = tier
        if op == "(" and not _SETTER_BEFORE.search(view[:s]):
            continue
        if op == "|" and not re.match(r"[ \t]*`?\|?[ \t]*`?", view[:s][-3:] + " "):
            continue
        if op == "|":
            vt = "space"
        elif op == "" and not quoted:
            # a bare space: a strong key written as an identifier, a flag (--secret-string VALUE), a
            # shell or Tcl set command (set token VALUE), or a config directive (bindpw VALUE)
            flag = view[max(0, s - 2):s] == "--" and (s < 3 or view[s - 3] in " \t\n")
            if not ((tier == "strong" and _ident_key(view, s, e)) or flag
                    or _SET_CMD_BEFORE.search(view[:s])
                    or re.sub(r"\W", "", view[s:e].lower()) in DIRECTIVES and _line_start(view, s)):
                continue
            vt = "space"
        elif op in ("", "\t") and quoted:
            vt = "space" if tier == "strong" else "none"
        elif op == "\t":
            vt = "space" if tier == "strong" else "none"
        if vt != "none" and credential_value(vt if vt != "space" else "space", v, quoted, op):
            out.append(("canonical-key", v))
            continue
        if op == "!=":  # make's shell assignment: a credential anywhere in the command
            for tok in re.findall(r"[^\s\"'`]{8,}", view[vend:view.find("\n", vend) if "\n" in view[vend:] else None]):
                if credential_value("space", tok, False):
                    out.append(("canonical-key", tok))
                    break
    out += _record_hits(view)
    return out


def hits(text):
    """(rule, value) for every credential the canonical primitive finds in text, deduplicated."""
    if not text:
        return []
    chunks = [text] if len(text) <= SECRET_MAX_LEN else [
        text[i:i + SECRET_MAX_LEN] for i in range(0, len(text), SECRET_MAX_LEN // 2)]
    seen = []
    for c in chunks:
        for view in canonical_views(c):
            for h in _view_hits(view):
                if h not in seen:
                    seen.append(h)
    return seen
