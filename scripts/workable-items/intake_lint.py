#!/usr/bin/env python3
# scripts/workable-items/intake_lint.py -- read-only CONTENT lint for a set of workable items
# (an intake batch) in a workable-items SQLite database.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md (user guide and manual).
#
# WHY  `workable-items validate` and `diff` prove the closed sets, the description floor and the
#   DB-to-Markdown sync. They do not read what a description SAYS, and they do not compare the
#   body_md header lines with their source columns. The independent reviews of the 2026-11-12
#   tracker-intake vehicle found wrong tracker facts that passed validate and diff. This lint checks
#   those classes for a SELECTED set of items, deterministically, and never writes.
#
# USAGE
#   python3 -I scripts/workable-items/intake_lint.py --db <db> (--origin <text> | --ids <A,B,..>)...
#           [--prefix CON] [--require-dup-check] [--repo-root DIR] [--rendered DIR | --no-rendered]
#           [--skip-check CODES] [--embeddings] [--no-selfcheck]
#   --origin TEXT    select every item whose description contains TEXT (repeatable)
#   --ids LIST       select these item ids (comma list, repeatable)
#   --prefix P       id prefix of this tracker (default: the most common prefix in the DB); a prefix
#                    that no item of the DB carries is BLIND (the id checks could not see)
#   --require-dup-check
#                    every selected item must carry a `Duplicate check (section 11.4.214):` line
#                    with a verdict from {DISTINCT, DISTINCT-but-similar, SAME-DEFECT, UNDECIDED}
#   --embeddings     print every id embedded in the selected items' text (title, description and the
#                    state text columns; own / foreign / main / unknown) as TSV and exit 0
#   --repo-root DIR  enable PATH-MISSING and the evidence-file checks of STATE-EVIDENCE against this
#                    checkout; the rendered documents default to DIR/docs
#   --rendered DIR   scan the rendered Issues.md, Fixed.md, Issues_Summary.md and Fixed_Summary.md in
#                    DIR (the published sink): the section of each selected item and the summary rows
#                    whose id cell names it. A selected item that appears in none of them is BLIND.
#   --no-rendered    do not scan rendered documents (the RESULT line says rendered=none)
#   --skip-check C   comma list of finding codes not to report (repeatable; an unknown code is a
#                    usage error); a skipped code must be stated wherever the result is cited
#   --no-selfcheck   skip the built-in control needles (tests only; never in a gate)
#
# SURFACES  SECRET, EPHEMERAL and CONTROL-CHAR read every text surface of a selected item: the title,
#   the description, body_md (every line, the header lines included), every other column of `items`
#   (enumerated from the row, so a new column is read without a code change), the item's
#   obsolete_details, operator_block_details and item_history rows, and the rendered lines (above).
#   One finding per (code, item, pattern) names every surface the pattern was found on. One control
#   needle per surface runs in the self-check.
#
# CHECKS (finding codes; each finding is one line `FINDING <code> <item> <detail>`)
#   XREF-DANGLING    an id of this tracker named in the title, the description or a state text column
#                    (a range `A..B` names every id in it) does not exist and is not declared foreign
#   XREF-LABEL       `<id> (<label>)`: no significant label word is in the target's title, or more
#                    than a third of the significant label words occur nowhere in the target's title
#                    or description
#   XREF-UNLABELLED  an id of another existing item written without a label, in a clause that shares
#                    no significant word with the target's title
#   FOREIGN-STALE    a `Foreign ids` line declares an id the rest of the item never names
#   STATE-PROSE      a closed reproduction/investigation state word in prose, or a hand-written
#                    `**Reproduction:**` / `**Investigation:**` line in the description, disagrees with
#                    the item's state column (section 11.4.294(A): the column is the source)
#   STATE-EVIDENCE   a reproduction state that needs evidence (reproduced-*, not-reproducible-with-
#                    evidence) has no evidence path or no 64-hex sha256 in reproduction_env; an
#                    investigation state that needs evidence (root-cause-found-with-evidence,
#                    closed-no-defect) has no evidence path or no sha256; a blocked state has no
#                    blocker; with --repo-root: the evidence file is missing or its sha256 differs
#   SECTIONS         a section 11.4.148 marker is missing (What, Affected scope, Reproduction /
#                    context, Acceptance criteria, Parent / links)
#   BODY-SYNC        body_md is not the engine rendering of its sources: empty, the description not in
#                    it, text before or after the rendered parts, the heading, or any header line that
#                    differs from its source (Status, Type, Severity, Created-By, Assigned-To,
#                    Reproduction, Investigation and Obsolete-Details exactly; Evidence must be the
#                    evidence of a closure row; Reopened-Details the last Reopened row;
#                    Operator-Block-Details the item's row), a key written twice, or a key outside
#                    the engine's set. The table in docs/guides/intake_lint_guide.md lists every key.
#   SECRET           a credential-shaped string on any surface (pattern name printed, never the match;
#                    section 11.4.10)
#   EPHEMERAL        a session-scratchpad location, a /tmp path, a mktemp-shaped name, a .bundle file,
#                    a home directory path, a session store directory, or a bare review_*.md /
#                    *_lander_items.md name (not under docs/) on a line with no `(ephemeral` note
#   CONTROL-CHAR     NUL, a C0 control other than tab and newline, DEL, a C1 control, U+2028 or U+2029,
#                    or a Unicode format character (category Cf: bidi overrides and isolates, the BOM,
#                    the soft hyphen, zero-width characters, tag characters); the earliest one is named
#                    on any surface; a tab or newline in the title
#   SHARED-PATH      a file named in the item's Affected-scope section is named by an OPEN item outside
#                    the selection, and the Duplicate check line does not name that item
#   DUP-CHECK        (--require-dup-check) the line is missing or its verdict is outside the closed set;
#                    (always) a SAME-DEFECT verdict that names no id
#   DUP-SAME-OPEN    the verdict is SAME-DEFECT of X but the item is not Obsolete duplicate-of X
#   DUP-HEAD         the verdict is SAME-DEFECT of X but X is not the single open head: X is closed, or
#                    another open item is, or may be, a head of the same defect (section 11.4.214(0)):
#                    its own Duplicate check line names X with SAME-DEFECT or UNDECIDED (any case), or
#                    it names X, or X names it, in a duplicate clause (candidate, undecided, duplicate,
#                    same defect, second / canonical / open head; any case), or it carries an
#                    obsolete_details row duplicate-of X while open and has no stale-row note
#   DUP-UNDECIDED    the verdict is UNDECIDED but names no candidate id, or the item is closed
#   DUP-STATUS       the item is Obsolete duplicate-of but its verdict is not SAME-DEFECT
#   OBSOLETE-STALE   an obsolete_details row on an item that is not Obsolete, with no
#                    `Stale obsolete_details row (...)` note naming an existing open item
#   PATH-MISSING     (--repo-root) a cited docs/qa/ or docs/operator_decisions/ path does not exist
#
# EXIT  0 no finding; 1 findings; 2 usage error; 3 BLIND (database unreadable, a required table
#   missing, a non-text value, empty selection, a prefix no item carries, a selected item absent from
#   every rendered document, any crash of the lint, or a built-in control needle failed: the
#   instrument could not see, so no verdict is given).
# EVIDENCE CLASS  gate-logic only (section 11.4.289): it reads text, it does not prove an item true.
import argparse
import base64
import binascii
import functools
import hashlib
import html
import os
import re
import sqlite3
import sys
import importlib.util as _ilu
import unicodedata
import urllib.parse

import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)


def _load_canon():
    """The ONE shared credential rule set (round 11): secret_canon.py next to this file (a mutation copy
    gets its own copy next to it). Missing means BLIND, never a silent pass."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "secret_canon.py")
    spec = _ilu.spec_from_file_location("secret_canon_%x" % (hash(path) & 0xFFFFFFFF), path)
    if spec is None or not os.path.isfile(path):
        raise ImportError("secret_canon.py not found next to the lint: " + path)
    mod = _ilu.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CANON = _load_canon()

STOP = set(
    "the a an on in of to is and or for with by from not no as at be it its this that are was when "
    "into than then there their these those over under after again only also each every item items "
    "vehicle review issue issues sync same other another says said already whose must change changes "
    "class instance level different symptom related parent links both have here need needs "
    "owed which where while about against before being does done like more most much such some what "
    "they them will would should could".split()
)
REPRO_TOKENS = [
    "reproduced-live",
    "reproduced-host-fixture",
    "not-reproducible-with-evidence",
    "blocked-no-device-with-recorded-blocker",
    "blocked-no-device",
    "UNREPRODUCED",
]
INV_TOKENS = ["root-cause-found-with-evidence", "root-cause-unconfirmed", "closed-no-defect"]
INV_STATES = ["not-started", "in-progress"] + INV_TOKENS
UNREPRO_FAMILY = {"UNREPRODUCED", "not-reproducible-with-evidence", "blocked-no-device-with-recorded-blocker"}
REPRO_NEEDS_EVIDENCE = {"reproduced-live", "reproduced-host-fixture", "not-reproducible-with-evidence"}
INV_NEEDS_EVIDENCE = {"root-cause-found-with-evidence", "closed-no-defect"}
SECTION_MARKERS = [
    ("What", re.compile(r"^\*\*What\b[^*]*:\*\*", re.M)),
    ("Affected scope", re.compile(r"^\*\*Affected scope / file-scope manifest:\*\*", re.M)),
    ("Reproduction / context", re.compile(r"^\*\*Reproduction / context:\*\*", re.M)),
    ("Acceptance criteria", re.compile(r"^\*\*Acceptance criteria:\*\*", re.M)),
    ("Parent / links", re.compile(r"^Parent / links:", re.M)),
]
# Credential shapes (section 11.4.10). Round 10 (review r9 R9-1 to R9-4, section 11.4.276(C)): the
# front end DECODES TO A FIXPOINT (one more view: every transform applied again until nothing changes,
# so a percent, entity or escape layer of any depth up to SECRET_FIXPOINT_STEPS is read), decodes the
# brace and long escapes (\u{70}, \U00000070, \x{70}), every HTML character reference html.unescape
# changes (also a numeric one without its semicolon), base64 runs that decode to printable text holding
# '=' or ':', triple-quoted strings and a parenthesised literal after a separator, and joins literals
# across newlines; the lookalike fold gains a CONFUSABLE SKELETON table (Coptic, Cherokee, Armenian,
# Lisu, more Cyrillic) and the wildcard reads a word whose letters are at least half ASCII letters in
# place; the key classifier gains a MULTILINGUAL lexicon (the word for password in other languages, in
# its own script, folded like a key) and SPLIT HEADS (pass_word, pass-word, passWord read as password);
# "word" is no longer a property word; new extractors read a markdown table row, a Tcl/Expect set
# command, an R '<-' assignment and an HTML input's type/id attribute; the value classifier treats a
# ticket id, a version string and a reference scheme (env:, file:, ...) as non-values and a hash
# suffix (_sha256, _md5) as a property. The class and its census: class_inventory.md of
# docs/qa/tracker_intake_2026_11_16_v10 (L36 to L52).
# Round 9 (review r9 finding F1, section 11.4.276(E): replace, do not
# layer): round 8 matched the KEY of a keyed credential against lists of spellings written into every
# extractor's regular expression, so every spelling outside the lists (a suffix after the key, a camelCase
# short key, a key in brackets, a qualified "key") was a silent miss. Round 9 keeps the three stages and
# replaces the key half of stage 2 by a structural classifier:
#   1. a FRONT END (secret_views) that makes the views the rules read: NFKC; every format character (Cf),
#      every combining and enclosing mark (Mn, Me, after an NFKD decomposition, so an accent or an
#      invisible mark such as U+034F or a variation selector inside a key is removed) and the Hangul
#      fillers removed; the Cyrillic and Greek lookalike table and a Latin-by-name fold (small capitals,
#      Latin alpha, dotless i, long s) applied; then, as a closure of up to three layers, the views with
#      escapes decoded (\uXXXX, \xHH, octal \NNN, \\, \/, \", \'), percent-encoding decoded (so a double
#      %25 layer is two steps), HTML entities decoded, and adjacent string literals joined ("ab" "cd",
#      "ab" + "cd", 'ab' . 'cd', 'ab' || 'cd');
#   2. EXTRACTORS (KEYED_EXTRACTORS) that find a KEY TOKEN and its value in one syntax each (an
#      assignment, an argument pair, a setter call, a --flag, whitespace, a quoted value after whitespace,
#      netrc, an XML element, an XML key/value attribute pair, a YAML block scalar, a pgpass line, a URL
#      user-info password, an Authorization header, a tool's own password flag). The key token is any
#      identifier-like token (letters, digits, "_", ".", "-", bracketed subscripts); key_tier() splits it
#      into words (camelCase, snake_case, kebab-case, dots, brackets, letter-digit boundaries) and decides
#      the tier from the words: a head word (password, passphrase, credential, secret, token, a qualified
#      key such as signing/encryption/master/account/api/private key, a short head such as pwd, pass,
#      auth, key, session, cookie) followed only by words that do not name a PROPERTY of the credential
#      (policy, count, hash, file, length, url ...: META_WORDS), so DB_PASSWORD_PROD, API_KEY_V2,
#      password2, SECRET_KEY_BASE, userPass, config[password] are keys and password_policy, token_count,
#      passwordless, secret_hits are not. A non-ASCII letter the folds do not know may stand for one letter
#      of a long head (an Armenian or Cherokee lookalike);
#   3. a VALUE CLASSIFIER (credential_value) that decides whether the value is a credential: long enough,
#      not a reference (including a secret-manager reference such as vault:..., ref+...://...,
#      @Microsoft.KeyVault(...)), a mask, a placeholder, a code expression or a path, and, for the generic
#      and short key tiers, holding a letter and a digit and not an identifier such as lint_suite_2.
# Every rule has a positive and a negative control needle in selfcheck(). The class, its census and its
# boundary are docs/qa/tracker_intake_2026_11_15_v9/class_inventory.md; the shared fixtures that both the
# lint and the independent leak scan are tested against are tests/workable_items/secret_shape_fixtures.py.
SECRET_NFKC = True
SECRET_STRIP_FORMAT = True
SECRET_STRIP_MARKS = True
SECRET_FOLD = True
SECRET_FOLD_LATIN_NAMES = True
SECRET_DECODE_ESCAPES = True
SECRET_DECODE_PERCENT = True
SECRET_DECODE_ENTITIES = True
SECRET_JOIN_LITERALS = True
SECRET_DECODE_BASE64 = True
SECRET_TRIPLE_QUOTES = True
SECRET_PAREN_LITERAL = True
SECRET_FIXPOINT = True
SECRET_SPLIT_HEADS = True
SECRET_SPLIT_KEYS = True
SECRET_WILDCARD = True
SECRET_VIEW_LAYERS = 3
# round 11: the shared canonical rule set (secret_canon.py) behind the named extractors
SECRET_CANONICAL = True
CANON_RULE_NAMES = ("canonical-key", "canonical-record", "canonical-tool", "canonical-url", "canonical-xml")
SECRET_MAX_VIEWS = 24
# the fixpoint view: at most this many rounds of every transform (each round must change the text)
SECRET_FIXPOINT_STEPS = 64
# ---- the key words (stage 2's key classifier) ------------------------------------------------------
# strong heads: any value of 8 or more characters. NATIVE_STRONG_HEADS (round 10, review r9 R9-1): the
# word for "password" in other languages, in its own script and in its Latin spelling; they are folded
# by the front end's own _clean below (so a Cyrillic word is compared as the front end sees it) and
# added to STRONG_HEADS there. Multi-word forms are written joined (motdepasse = mot de passe) and are
# found by the split-head reading (mot_de_passe).
NATIVE_STRONG_HEADS = (
    "\u043f\u0430\u0440\u043e\u043b\u044c",                    # ru, uk, be: parol'
    "\u043b\u043e\u0437\u0438\u043d\u043a\u0430",              # sr, hr (Cyrillic): lozinka
    "\u043f\u0430\u0440\u043e\u043b\u0430",                    # bg, mk: parola
    "\u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03c2",              # el: kodikos
    "\u5bc6\u7801", "\u5bc6\u78bc",                          # zh: mima
    "\u30d1\u30b9\u30ef\u30fc\u30c9",                          # ja: pasuwaado
    "\ube44\ubc00\ubc88\ud638", "\uc554\ud638",              # ko: bimilbeonho, amho
    "\u05e1\u05d9\u05e1\u05de\u05d4",                          # he: sisma
    "\u092a\u093e\u0938\u0935\u0930\u094d\u0921",            # hi: paasvard
    "parola", "haslo", "has\u0142o", "heslo", "jelszo", "geslo", "parool", "passord",
    "losenord", "adgangskode", "kodeord", "sifre", "sifra", "katasandi", "motdepasse",
    "wagwoord", "sandi", "parolja",
)
STRONG_HEADS = frozenset({"password", "passwd", "passphrase", "passwort", "kennwort", "contrasena", "senha",
                          "wachtwoord", "lozinka", "salasana", "credential", "credentials"})
# a word may END with a strong head (PGPASSWORD, dbpasswd, mypassphrase, pgcredential); "passwordless"
# does not end with a head and is not a key
SUFFIX_HEADS = tuple(sorted(STRONG_HEADS, key=len, reverse=True))
# generic heads: an "=" value of 8 characters, a colon value with a letter and a digit
GENERIC_HEADS = frozenset({"secret", "token", "creds"})
# short heads: a value with a letter and a digit; the word must be a whole word (bypass, oauth, compass,
# keyword are words, not keys), except in an all-upper-case shell name (DBPASS)
SHORT_HEADS = frozenset({"pwd", "pass", "pw", "auth", "key", "session", "sid", "cookie"})
UPPER_SUFFIX_SHORT = ("pass", "pwd")
# a word joined to a short head (camelCase or an all-upper name) that makes an English word, not a key:
# byPass, BYPASS, compass, oAuth, trespass, surpass
SHORT_JOIN_NEGATIVE = frozenset({"by", "o", "com", "sur", "tres", "over", "under", "im", "en", "mis", "re", "pre",
                                 "out", "up", "bi", "en", "ex"})
# numeric heads: a value of digits only (a PIN)
NUMERIC_HEADS = frozenset({"pin"})
# a word before "key", "token" or "secret" that makes it a credential (strong), or a word that makes it
# something else (a public key, a database key, a page token)
KEY_QUALIFIERS = frozenset({"secret", "private", "access", "api", "signing", "sign", "encryption", "encrypt",
                            "enc", "master", "account", "client", "shared", "app", "application", "session",
                            "auth", "hmac", "jwt", "aes", "crypt", "crypto", "cipher", "decryption", "storage",
                            "service", "admin", "root", "consumer", "subscription", "webhook", "license",
                            "licence", "deploy", "ssh", "gpg", "pgp", "rsa", "ecdsa", "otp", "totp", "mfa",
                            "recovery", "wrapping", "kms"})
KEY_NEGATIVE = frozenset({"public", "pub", "foreign", "primary", "sort", "partition", "hash", "cache", "map",
                          "dict", "row", "lookup", "idempotency", "unique", "composite", "natural",
                          "surrogate", "routing", "shard", "object", "group", "config", "registry",
                          "translation", "i18n", "react", "item", "field", "column", "index", "json",
                          "yaml", "sorting", "keyboard", "hot", "short", "cut", "home", "end", "dedup",
                          "join", "match", "node", "entry", "the", "a"})
TOKEN_QUALIFIERS = frozenset({"auth", "access", "refresh", "bearer", "session", "api", "id", "oauth", "app",
                              "bot", "personal", "deploy", "service", "github", "gitlab", "slack", "npm",
                              "pypi", "registry", "webhook", "jwt", "client", "user", "admin", "security",
                              "sas", "discord", "telegram", "hf", "ci", "runner", "trigger", "private",
                              "secret", "master", "root"})
TOKEN_NEGATIVE = frozenset({"page", "next", "continuation", "cancellation", "cursor", "pagination", "lexer",
                            "parser", "design", "sync", "input", "output", "max", "min", "eos", "bos", "pad",
                            "unk", "special", "stop", "sep", "cls", "mask", "end", "start", "the", "a",
                            "csrf", "xsrf"})
SECRET_QUALIFIERS = frozenset({"client", "app", "application", "consumer", "shared", "webhook", "jwt", "api",
                               "signing", "session", "cookie", "hmac", "oauth", "aws", "encryption", "master",
                               "root", "bot"})
# a word after the head that names a property of the credential, not the credential itself
META_WORDS = frozenset({
    "policy", "policies", "count", "counts", "hits", "hit", "hash", "hashed", "digest", "file", "files", "path",
    "paths", "dir", "length", "len", "size", "min", "max", "type", "types", "kind", "url", "uri", "endpoint",
    "host", "field", "fields", "name", "names", "label", "header", "reset", "expiry", "expires",
    "expiration", "expire", "ttl", "age", "rotation", "rotate", "rotated", "rule", "rules", "hint", "prompt",
    "enabled", "disabled", "required", "optional", "set", "changed", "strength", "salt", "algorithm", "algo",
    "format", "mode", "regex", "pattern", "lifetime", "timeout", "history", "attempts", "retries", "command",
    "cmd", "env", "var", "variable", "ref", "reference", "id", "ids", "version", "manager", "store", "vault",
    "provider", "source", "scope", "scopes", "audience", "issuer", "owner", "location", "prefix", "suffix",
    "list", "map", "table", "column", "check", "checks", "test", "tests", "validator", "validation", "valid",
    "verified", "verify", "input", "output", "box", "form", "button", "page", "screen", "text",
    "placeholder", "generator", "less", "usage", "limit", "limits", "budget", "budgets", "spent", "used",
    "cost", "costs", "rate", "estimate", "estimates", "stats", "metrics", "lookup", "error", "errors", "status",
    "state", "flow", "grant", "endpoint", "server", "service", "helper", "util", "utils", "cache", "dump",
    "log", "logs", "event", "events", "length", "chars", "char", "count", "number", "num", "scan", "scanner",
    "scanning", "leak", "leaks", "shape", "shapes", "class", "census", "fixture", "fixtures", "rows", "row",
    "words", "case", "cases", "needle", "needles", "pair", "pairs", "line", "lines", "only", "free",
    # digests: key_parts() splits a letter-digit boundary, so sha256 and md5 reach this set as "sha" and "md"
    "field", "storage", "sha", "md", "checksum", "fingerprint",
    "ui", "dialog", "modal", "visible", "visibility", "toggle", "show", "hidden", "auth",
})
# ---- stage 1: the front end -------------------------------------------------------------------------
_FOLD = str.maketrans({
    "\u0430": "a", "\u0435": "e", "\u043e": "o", "\u0440": "p", "\u0441": "c", "\u0443": "y", "\u0445": "x",
    "\u0456": "i", "\u0458": "j", "\u0455": "s", "\u0501": "d", "\u051b": "q", "\u051d": "w", "\u04bb": "h",
    "\u0410": "A", "\u0412": "B", "\u0415": "E", "\u041a": "K", "\u041c": "M", "\u041d": "H", "\u041e": "O",
    "\u0420": "P", "\u0421": "C", "\u0422": "T", "\u0425": "X", "\u0406": "I", "\u0408": "J", "\u0405": "S",
    "\u03b1": "a", "\u03bf": "o", "\u03c1": "p", "\u03c4": "t", "\u03ba": "k", "\u03bd": "v", "\u03b9": "i",
    "\u0391": "A", "\u0392": "B", "\u0395": "E", "\u0396": "Z", "\u0397": "H", "\u0399": "I", "\u039a": "K",
    "\u039c": "M", "\u039d": "N", "\u039f": "O", "\u03a1": "P", "\u03a4": "T", "\u03a5": "Y", "\u03a7": "X",
    "\u0131": "i", "\u0261": "g", "\u217c": "l", "\u2170": "i",
})
# The confusable skeleton (round 10, review r9 R9-1): letters of other scripts that are drawn like a
# Latin letter and that NFKC keeps, taken from the Unicode confusables data for the scripts a key is
# spelled with in practice: Coptic, Cherokee (capital and small), Armenian, Lisu and more Cyrillic. A
# letter of these scripts NOT in this table is read by the wildcard (_like) when the word is at least
# half ASCII letters; an all-lookalike word of letters outside the table is section-B row B40.
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
_FOLD.update(str.maketrans(_SKELETON))
# Latin letters that NFKC keeps, folded by their Unicode name: LATIN LETTER SMALL CAPITAL P, LATIN SMALL
# LETTER ALPHA, LATIN SMALL LETTER DOTLESS J, LATIN SMALL LETTER LONG S, ...
_LATIN_NAME = re.compile(r"^LATIN (?:(SMALL|CAPITAL) )?LETTER (?:SMALL CAPITAL )?([A-Z]|ALPHA|DOTLESS [IJ]|LONG S|"
                         r"OPEN [EO]|SCRIPT [A-Z]|IOTA|UPSILON|TURNED [A-Z]|REVERSED [A-Z])$")
_LATIN_WORD = {"ALPHA": "a", "IOTA": "i", "UPSILON": "u", "LONG S": "s"}
# the invisible letters a key can carry that are neither a format character nor a mark
_FILLERS = frozenset("\u115f\u1160\u3164\uffa0")
_ESC = re.compile(r"\\(u\{[0-9A-Fa-f]{1,6}\}|U[0-9A-Fa-f]{8}|u[0-9A-Fa-f]{4}|x\{[0-9A-Fa-f]{1,6}\}|x[0-9A-Fa-f]{2}|[0-7]{3}|[\\/\"'])")
_PCT = re.compile(r"%[0-9A-Fa-f]{2}")
# base64 runs of 16 characters or more (standard or URL-safe alphabet)
_B64 = re.compile(r"(?<![A-Za-z0-9+/=_-])(?:[A-Za-z0-9+/_-]{4}){4,}(?:[A-Za-z0-9+/_-]{2}(?:==)?|[A-Za-z0-9+/_-]{3}=?)?(?![A-Za-z0-9+/=_-])")
_TRIPLE = re.compile(r"\"\"\"|'''")
# a parenthesised literal after a separator: = ("ab"\n "cd")
_PAREN = re.compile(r"((?:=|:=|:|<-|=>)[ \t]*)\(\s*([\"'`][^()]{0,1024}?[\"'`])\s*\)")
# a closing quote, an optional concatenation operator and an opening quote of the same kind between two
# value characters: "ab" "cd", "ab" + "cd", 'ab' . 'cd', 'ab' || 'cd'
_JOIN = re.compile(r"(?<=[^\s\"'`\\])([\"'])\s*(?:\+|\.\.?|\|\||&|~)?\s*\1(?=[^\s\"'`,;:)\]}])")


@functools.lru_cache(maxsize=4096)
def _latin_fold(ch):
    m = _LATIN_NAME.match(unicodedata.name(ch, ""))
    if not m:
        return ch
    word = m.group(2)
    out = _LATIN_WORD.get(word, word[-1])
    return out.upper() if m.group(1) == "CAPITAL" else out.lower()


def _clean(t):
    """Remove the format characters, the marks and the fillers, and fold the lookalikes (the per-view
    step of the front end)."""
    if t.isascii():
        return t
    if SECRET_STRIP_MARKS:
        t = unicodedata.normalize("NFKD", t)
    if SECRET_STRIP_FORMAT or SECRET_STRIP_MARKS:
        drop = set()
        if SECRET_STRIP_FORMAT:
            drop.add("Cf")
        if SECRET_STRIP_MARKS:
            drop |= {"Mn", "Me", "Mc"}  # Mc (round 10): an Indic vowel sign is not a \w character
        t = "".join(ch for ch in t if unicodedata.category(ch) not in drop and ch not in _FILLERS)
    if SECRET_STRIP_MARKS:
        t = unicodedata.normalize("NFKC", t)
    if SECRET_FOLD:
        t = t.translate(_FOLD)
    if SECRET_FOLD_LATIN_NAMES and not t.isascii():
        t = "".join(ch if ch.isascii() else _latin_fold(ch) for ch in t)
    return t


# the native-script strong heads, as the front end sees them (round 10)
STRONG_HEADS = STRONG_HEADS | frozenset(_clean(unicodedata.normalize("NFKC", w)).lower() for w in NATIVE_STRONG_HEADS)
SUFFIX_HEADS = tuple(sorted(STRONG_HEADS, key=len, reverse=True))


def _unescape(m):
    s = m.group(1)
    if s[0] in "uUx":
        n = int(s[1:].strip("{}"), 16)
        return chr(n) if n <= 0x10FFFF else m.group(0)
    if s[0].isdigit():
        return chr(int(s, 8))
    return s


def _v_escapes(t):
    return _ESC.sub(_unescape, t) if SECRET_DECODE_ESCAPES and "\\" in t else None


def _v_percent(t):
    return urllib.parse.unquote(t) if SECRET_DECODE_PERCENT and _PCT.search(t) else None


def _v_entities(t):
    if not SECRET_DECODE_ENTITIES or "&" not in t:
        return None
    d = html.unescape(t)
    return d if d != t else None


def _v_join(t):
    return _JOIN.sub("", t) if SECRET_JOIN_LITERALS and _JOIN.search(t) else None


def _b64_text(m):
    s = m.group(0)
    try:
        b = base64.b64decode(s + "=" * (-len(s) % 4), altchars=b"-_" if ("-" in s or "_" in s) else None, validate=True)
        d = b.decode("utf-8")
    except (binascii.Error, ValueError):
        return s
    if len(d) < 8 or not re.search(r"[=:]", d) or not all(c.isprintable() or c in "\t\n" for c in d):
        return s
    return d


def _v_base64(t):
    if not SECRET_DECODE_BASE64 or not _B64.search(t):
        return None
    d = _B64.sub(_b64_text, t)
    return d if d != t else None


def _v_triple(t):
    return _TRIPLE.sub(lambda m: m.group(0)[0], t) if SECRET_TRIPLE_QUOTES and _TRIPLE.search(t) else None


def _v_paren(t):
    return _PAREN.sub(r"\1\2", t) if SECRET_PAREN_LITERAL and _PAREN.search(t) else None


_TRANSFORMS = (_v_escapes, _v_percent, _v_entities, _v_join, _v_base64, _v_triple, _v_paren)


def _fixpoint(t):
    """Every transform applied again, in order, until a round changes nothing (at most
    SECRET_FIXPOINT_STEPS rounds): a percent, entity or escape layer of any depth."""
    for _step in range(SECRET_FIXPOINT_STEPS):
        before = t
        for f in _TRANSFORMS:
            d = f(t)
            if d is not None:
                t = _clean(unicodedata.normalize("NFKC", d))
        if t == before:
            break
    return t


def secret_views(text):
    """The views of a surface that the credential rules read (stage 1). The decoding transforms are
    applied as a closure of up to SECRET_VIEW_LAYERS layers (an entity inside a percent-encoded value, a
    double percent layer), every new view NFKC-normalised and cleaned again."""
    t = unicodedata.normalize("NFKC", text) if SECRET_NFKC else text
    t = _clean(t)
    views = [t]
    frontier = [t]
    for _layer in range(SECRET_VIEW_LAYERS):
        new = []
        for v in frontier:
            for f in _TRANSFORMS:
                d = f(v)
                if d is None:
                    continue
                d = _clean(unicodedata.normalize("NFKC", d))
                if d not in views and len(views) < SECRET_MAX_VIEWS:
                    views.append(d)
                    new.append(d)
        if not new:
            break
        frontier = new
    if SECRET_FIXPOINT:
        fp = _fixpoint(t)
        if fp not in views:
            views.append(fp)
    return views


# ---- stage 2, the key half: key tokens and their tier -----------------------------------------------
_CAMEL = re.compile(r"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=[A-Za-z])(?=[0-9])|(?<=[0-9])(?=[A-Za-z])")
_WSPLIT = re.compile(r"[\W_]+")


def key_parts(tok):
    """The words of a key token, each with a flag: True when it is joined to the word before it without a
    separator (a camelCase hump or a letter-digit boundary), False after a separator (_, -, ., brackets,
    quotes, $) or at the start."""
    out = []
    for part in _WSPLIT.split(tok):
        if not part:
            continue
        subs = _CAMEL.sub(" ", part).split() if SECRET_SPLIT_KEYS else [part]
        out += [(w.lower(), k > 0) for k, w in enumerate(subs)]
    return out


def key_words(tok):
    """The words of a key token: split at camelCase humps, letter-digit boundaries, and every character
    that is not a letter or a digit."""
    return [w for w, _ in key_parts(tok)]


def _like(w, h):
    """w spells the head h: equal, or (a lookalike the folds do not know) of the same length, for a head
    of five letters or more, where every ASCII character of w is h's letter in place, every other
    character is a non-ASCII letter, and those stand-in letters are at most half of the word (round 10,
    review r9 R9-1: three or four stand-ins in password, two in token)."""
    if w == h:
        return True
    if not SECRET_WILDCARD or w.isascii() or len(w) != len(h) or len(h) < 5:
        return False
    odd = 0
    for a, b in zip(w, h):
        if a == b:
            continue
        if a.isascii() or not a.isalpha():
            return False
        odd += 1
    return 2 * odd <= len(h)


def _ends_like(w, h):
    return len(w) > len(h) and _like(w[-len(h):], h)


_TIER_RANK = {"strong": 4, "generic": 3, "short": 2, "numeric": 1}


def _qualified(prev, w, head, quals, loose=False):
    """head after a qualifier word (api key), joined to a qualifier (apikey), or after a word that ends with a
    qualifier of three letters or more (PGapi_key reads as "p gapi key"). loose (the previous word was split
    off a run of capitals, or the key is all capitals) also admits a two-letter qualifier at the end of the
    previous word: "PGid_token" splits as "p gid token" and "PGID_TOKEN" as "pgid token", and the camel
    split cannot tell "PG id" from "P Gid" (round 9 census). The safer reading counts it as qualified."""
    n = 2 if loose else 3
    if w == head:
        return prev in quals or any(len(q) >= n and prev.endswith(q) for q in quals)
    if w.endswith(head):
        pre = w[:-len(head)]
        return pre in quals or any(len(q) >= 3 and pre.endswith(q) for q in quals)
    return False


def _word_tier(ws, i, upper):
    w, joined = ws[i]
    prev = ws[i - 1][0] if i > 0 else ""
    if any(_like(w, h) for h in STRONG_HEADS) or any(_ends_like(w, h) for h in SUFFIX_HEADS):
        return "strong"
    if w == "key" or (w.endswith("key") and len(w) > 3):
        if _qualified(prev, w, "key", KEY_QUALIFIERS):
            return "strong"
        if w == "key":
            return None if prev in KEY_NEGATIVE else "short"
        return None
    for head, quals, neg in (("token", TOKEN_QUALIFIERS, TOKEN_NEGATIVE), ("secret", SECRET_QUALIFIERS, frozenset())):
        if _like(w, head) or (w.endswith(head) and len(w) > len(head)):
            if _qualified(prev, w, head, quals, loose=(i > 0 and ws[i - 1][1]) or upper):
                return "strong"
            if _like(w, head):
                return None if prev in neg else "generic"
            pre = w[:-len(head)]
            return None if pre in neg or any(len(n) >= 4 and pre.endswith(n) for n in neg) else "generic"
    if w in GENERIC_HEADS:
        return "generic"
    if w in SHORT_HEADS:
        return None if joined and prev in SHORT_JOIN_NEGATIVE else "short"
    if upper and len(w) > 4 and w.endswith(UPPER_SUFFIX_SHORT):
        pre = w[:-4] if w.endswith("pass") else w[:-3]
        return None if pre in SHORT_JOIN_NEGATIVE else "short"
    if w in NUMERIC_HEADS:
        return "numeric"
    return None


def _tail_ok(tail):
    return all(x.isdigit() or re.fullmatch(r"v[0-9]+", x) or x not in META_WORDS for x in tail)


@functools.lru_cache(maxsize=65536)
def key_tier(tok):
    """The tier of a key token ("strong", "generic", "short", "numeric") or None: the strongest head word
    whose following words name no property of the credential."""
    ws = key_parts(tok)
    upper = bool(re.fullmatch(r"[A-Z0-9_]+", tok)) and any(c.isalpha() for c in tok)
    best = None
    for i in range(len(ws)):
        t = _word_tier(ws, i, upper)
        if t and _tail_ok([w for w, _ in ws[i + 1:]]) and (best is None or _TIER_RANK[t] > _TIER_RANK[best]):
            best = t
    if best != "strong" and SECRET_SPLIT_HEADS:
        # a strong head written in two or three parts: pass_word, pass-word, passWord, mot_de_passe
        for i in range(len(ws)):
            for j in (i + 2, i + 3):
                if j <= len(ws) and _tail_ok([w for w, _ in ws[j:]]):
                    joined = "".join(w for w, _ in ws[i:j])
                    if any(_like(joined, h) for h in STRONG_HEADS):
                        return "strong"
    return best


# ---- stage 3: the value classifier ------------------------------------------------------------------
_PLACEHOLDER_WORDS = {
    "changeme", "change_me", "change-me", "changeit", "replaceme", "replace_me", "placeholder", "redacted",
    "example", "examples", "sample", "dummy", "password", "passwd", "passphrase", "secret", "token",
    "required", "optional", "none", "null", "nil", "undefined", "true", "false", "enabled", "disabled",
    "rotated", "unset", "notset", "default", "hidden", "omitted", "removed", "changed", "provided",
}
_PLACEHOLDER = re.compile(r"(?i)^(?:your|my|enter|insert|put|some)[-_.]|[-_.](?:here|goes[-_]here|placeholder)$")
_CODE_CALL = re.compile(r"^[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)*\s*[(\[]")
_CODE_ATTR = re.compile(r"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+$")
_PATH = re.compile(r"^(?:/|~/|~$|\./|\.\./)")
_MASK = re.compile(r"^[xX*.#\s-]+$")
_REF_START = "$<{%"
# a secret-manager or URI reference: vault:secret/data/db#k, ref+awsssm://p/k, op://vault/item,
# @Microsoft.KeyVault(SecretUri=...)
_REF_URI = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]{1,}:(?://)?\S*[/#]")
_REF_ANNOT = re.compile(r"^@[A-Za-z][\w.]*\(")
# an Amazon resource name (arn:aws:secretsmanager:...:secret:name)
_REF_ARN = re.compile(r"^arn:aws[\w-]*:[\w-]+:")
# an identifier, not a credential, after a generic or short key: lint_suite_2, cache-v2-entry
_IDENT_VALUE = re.compile(r"^[a-z]+[0-9]*(?:[_.-](?:[a-z]+[0-9]*|[0-9]+))+$")
# round 10 (review r9 R9-4): a ticket id (CON-1234) and a version (6.4.0-rc1-build42, v1.2.3-beta4) after a
# generic or short key; a reference with a secret-store scheme (env:DB_PASSWORD, file:..., op:...) after any key
_TICKET_VALUE = re.compile(r"^[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}$")
_VERSION_VALUE = re.compile(r"^v?[0-9]+(?:\.[0-9]+){1,3}(?:[-+][0-9A-Za-z][0-9A-Za-z.-]*)?$")
_REF_SCHEME = re.compile(r"(?i)^(?:env|file|secret|secrets|vault|sops|ssm|keyring|keychain|op|cmd|exec|gcpsm|"
                         r"awssm|azkv|k8s|kms):[A-Za-z_$]")


def _has_ld(v):
    return any(c.isdigit() for c in v) and any(c.isalpha() for c in v)


def credential_value(tier, v, quote, allow_space=False, generic_ld=True):
    """Stage 3: is v (the raw value an extractor found) a credential? tier is "strong", "generic",
    "short" or "numeric"; quote is the quote character the value was written in ("" when unquoted). A
    short-key value always needs a letter and a digit, a generic-key value unless generic_ld is False (an
    "=" assignment); a numeric-key value is digits only (a PIN, four digits or more)."""
    if tier == "numeric":
        return bool(re.fullmatch(r"[0-9]{4,12}", v))
    if len(v) < 8:
        return False
    if _MASK.match(v):
        return False
    if v[0] in _REF_START:
        # a single-quoted '$...' is a literal in shell; a value of mixed case with a digit is not a
        # variable name (references are written UPPER_SNAKE or lower_snake)
        if not (quote == "'" and v[0] == "$" and re.fullmatch(r"\$[A-Za-z0-9]{7,}", v)
                and any(c.isupper() for c in v) and any(c.islower() for c in v) and any(c.isdigit() for c in v)):
            return False
    if "\t" in v:
        return False  # a tab inside a value is a table cell, also after a strong key (review r9 RV12)
    if " " in v and not allow_space:
        return False
    low = v.lower()
    if low in _PLACEHOLDER_WORDS or _PLACEHOLDER.search(v):
        return False
    if _PATH.match(v):
        return False
    if _REF_URI.match(v) or _REF_ANNOT.match(v) or _REF_ARN.match(v) or _REF_SCHEME.match(v):
        return False
    if not quote and (_CODE_CALL.match(v) or (_CODE_ATTR.match(v) and not any(c.isdigit() for c in v))):
        return False
    if (tier == "short" or (tier == "generic" and generic_ld)) and not _has_ld(v):
        return False
    if tier in ("short", "generic") and _IDENT_VALUE.match(v):
        return False
    if tier in ("short", "generic") and (_TICKET_VALUE.match(v) or _VERSION_VALUE.match(v)):
        return False
    if tier == "short" and v[0] in ".>":
        return False
    return True


def _tier(m):
    if "key" in m.groupdict() and m.group("key") is not None:
        return key_tier(m.group("key"))
    return "strong"


# ---- stage 2, the extractors ------------------------------------------------------------------------
# a key token: a letter or "_", then letters, digits, "_", ".", "-", then bracketed subscripts
# (config[password], os.environ["DB_PASSWORD"]); it does not start after a letter, digit, "_" or "."
_KTOK = r"(?P<key>[^\W\d][\w.\-]{0,255}(?:\[\s*\\?[\"'`]?[\w.\-]{1,255}\\?[\"'`]?\s*\]){0,4})"
_KBEG = r"(?<![\w.])"
# the key may be quoted, also with an escaped quote (JSON written inside a string)
_KQ = r"(?:\\?[\"'`])?"
# a quoted value: an optional string prefix (b"", f'', r"", rb''), then up to the same closing quote; an
# escape sequence (\\, \", \u00e9, \/) is part of it
_QPRE = r"(?P<sp>(?<![\w])[bBrRuUfF]{1,2})?"
_QVAL = _QPRE + r"\\?(?P<q>[\"'`])(?P<v>(?:\\[^\n]|(?!\\?(?P=q))[^\n\\])*)\\?(?P=q)"
_SEP_Q = r"\s*(?::=|=>|<<-|<-|:|=)\s*"


def _x_assign_quoted(view):
    """key [quote] (:=|=>|:|=) "value": password-assign, password-assign-spaced, short-key-assign."""
    for m in _RX_ASSIGN_Q.finditer(view):
        tier, v, q = _tier(m), m.group("v"), m.group("q")
        if tier is None:
            continue
        if tier in ("short", "numeric"):
            if credential_value(tier, v, q):
                yield "short-key-assign", m.group(0)
        elif re.search(r"[ \t]", v):
            if tier == "strong" and credential_value("strong", v.strip(), q, allow_space=True) and v.strip():
                yield "password-assign-spaced", m.group(0)
        elif credential_value(tier, v, q, generic_ld=False):
            yield "password-assign", m.group(0)


def _x_assign_unquoted(view):
    """key [quote] (:=|=>|=) value: password-assign-unquoted, short-key-assign. The value is read in a
    lookahead, so a key inside the value (AccountName=x;AccountKey=v) is read too."""
    for m in _RX_ASSIGN_U.finditer(view):
        tier, v = _tier(m), m.group("v")
        if tier is None or v[:1] in "'\"`(\\[>" or not v:
            continue
        if tier in ("short", "numeric"):
            v = re.split(r"[,;&]", v)[0]
            if credential_value(tier, v, ""):
                yield "short-key-assign", m.group(0) + v
        elif credential_value(tier, v, "", generic_ld=False):
            yield "password-assign-unquoted", m.group(0) + v


def _x_colon_unquoted(view):
    """key [quote] : value: password-colon-unquoted (strong), secret-colon-unquoted (generic)."""
    for m in _RX_COLON_U.finditer(view):
        tier, v = _tier(m), m.group("v")
        if not v or v[:1] in "'\"`(\\[":
            continue
        if tier == "strong" and credential_value("strong", v, ""):
            yield "password-colon-unquoted", m.group(0) + v
        elif tier == "generic" and credential_value("generic", v, ""):
            yield "secret-colon-unquoted", m.group(0) + v


def _x_argument_pair(view):
    """('KEY', 'VALUE'): define(), os.environ.get(key, default), cfg.Get(), a JSON array pair."""
    for m in _RX_ARGPAIR.finditer(view):
        tier, v, q = _tier(m), m.group("v"), m.group("q")
        if tier and credential_value(tier, v, q):
            yield "argument-pair", m.group(0)


def _x_setter(view):
    """setPassword("VALUE"), set_api_key('VALUE')."""
    for m in _RX_SETTER.finditer(view):
        tier, v, q = _tier(m), m.group("v"), m.group("q")
        if tier in ("strong", "generic") and credential_value(tier, v, q):
            yield "setter-call", m.group(0)


def _x_flag_space(view):
    """--password VALUE, --db-token VALUE (a letter and a digit after a generic or short key)."""
    for m in _RX_FLAG.finditer(view):
        tier, v = _tier(m), m.group("v").strip("'\"`")
        if tier is None or tier == "numeric":
            continue
        if re.fullmatch(r"[A-Z][A-Z0-9_]*", v):
            continue  # a usage-line placeholder: --password PASSWORD
        if v[:1] in "(-[":
            continue
        if credential_value(tier, v, "'" if m.group("v")[:1] == "'" else ""):
            yield "password-flag-space", m.group(0) + m.group("v")


def _x_short_flag(view):
    """A tool's own password flag: mysql -pVALUE (joined; "-p VALUE" is a prompt and a database name),
    sshpass -p VALUE, curl -u USER:VALUE, redis-cli -a VALUE, docker login -p VALUE, mongosh -p VALUE,
    htpasswd -b FILE USER VALUE, openssl -passout pass:VALUE, sqlcmd -P VALUE, smbclient -U USER%VALUE."""
    for rx in _TOOL_FLAGS:
        for m in rx.finditer(view):
            v = m.group("v").strip("'\"`")
            if credential_value("strong", v, ""):
                yield "short-flag-value", m.group(0)


def _x_space(view):
    """DB_PASSWORD VALUE (fish set -x), password<TAB>VALUE (a TSV row): a strong key written as an
    identifier (a prefix, a key name of several parts such as client_secret, or upper case) and
    whitespace, or any strong key and a tab; then a value with a letter and a digit. "password policy2026"
    and "Password reset2026" are prose (section-B row B14)."""
    for m in _RX_SPACE.finditer(view):
        key, sep, v = m.group("key"), m.group("sep"), m.group("v")
        if v[:1] in "$<{%'\"`(\\[/~-" or key_tier(key) != "strong":
            continue
        ws = key_words(key)
        ident = len(ws) > 1 or (key.isupper() and len(key) > 3) or bool(re.search(r"[_.-]", key)) or "\t" in sep
        if ident and _has_ld(v) and credential_value("strong", v, ""):
            yield "password-space", m.group(0)


def _x_space_quoted(view):
    """A strong key, whitespace and a QUOTED value: ALTER USER u WITH PASSWORD 'VALUE',
    CREATE USER u IDENTIFIED BY 'VALUE', password "VALUE"; the value needs a letter and a digit."""
    for m in _RX_SPACE_Q.finditer(view):
        v, q = m.group("v"), m.group("q")
        tier = "strong" if m.group("key") is None else key_tier(m.group("key"))
        if tier == "strong" and _has_ld(v) and credential_value("strong", v, q):
            yield "password-space-quoted", m.group(0)


def _x_netrc(view):
    for m in _RX_NETRC.finditer(view):
        if credential_value("strong", m.group("v"), "netrc"):
            yield "password-netrc", m.group(0)


def _x_xml_element(view):
    """<password>VALUE</password>, <db_token type="x">VALUE</db_token>."""
    for m in _RX_XML_EL.finditer(view):
        tier, v = _tier(m), m.group("v")
        if tier is None or m.group("ctag") != m.group("key"):
            continue
        if credential_value(tier, v, "<"):
            yield "xml-credential-element", m.group(0)


def _x_xml_attr(view):
    """<add key="Password" value="VALUE"/>, <param name="token" value="VALUE"/>,
    <entry key="password">VALUE</entry>."""
    for m in _RX_XML_ATTR_V.finditer(view):
        tier = _tier(m)
        if tier and credential_value(tier, m.group("v"), m.group("q2")):
            yield "xml-attribute-pair", m.group(0)
    for m in _RX_XML_ATTR_T.finditer(view):
        tier = _tier(m)
        if tier and m.group("ctag") == m.group("otag") and credential_value(tier, m.group("v"), "<"):
            yield "xml-attribute-pair", m.group(0)


def _x_yaml_block(view):
    """password: |  (or >-) with the value on the next, indented line; the value's first word is read
    (a value with a space inside is section-B row B15). A short key needs a letter and a digit."""
    for m in _RX_YAML_BLOCK.finditer(view):
        tier, v = _tier(m), m.group("v").split()[0]
        if tier and credential_value(tier, v, "|"):
            yield "yaml-block-scalar", m.group(0)


def _x_pgpass(view):
    """host:port:database:user:password (a ~/.pgpass line). The password needs a letter and a digit: the
    five-field colon shape is also a time stamp or a log field (a letters-only value is section-B row B20)."""
    for m in _RX_PGPASS.finditer(view):
        v = m.group("v")
        if _has_ld(v) and credential_value("strong", v, ""):
            yield "pgpass-line", m.group(0)


def _x_url(view):
    """scheme://user:PASSWORD@host (any case of the scheme; the user may be empty)."""
    for m in _RX_URL.finditer(view):
        v = m.group("v")
        if v[0] in "$<{%*" or re.fullmatch(r"[xX*]+", v):
            continue  # a reference or a mask
        if re.match(r"\d+/", v):
            continue  # a port and a path (h:8080/...)
        if "/" in v and (v.endswith("/") or not _has_ld(v)):
            continue  # a path segment before an @ (http://host:port/users/@me)
        yield "url-userinfo-password", m.group(0)


def _x_table_row(view):
    """| password | VALUE | (a markdown or plain table row whose first cell is a key): the value needs a
    letter and a digit (a table cell is mostly a word)."""
    for m in _RX_TABLE.finditer(view):
        tier, v = _tier(m), m.group("v")
        if tier and tier != "numeric" and _has_ld(v) and credential_value(tier, v, ""):
            yield "table-row-pair", m.group(0)


def _x_set_command(view):
    """set password VALUE (Tcl, Expect): a statement of exactly three words; the value needs a letter and
    a digit."""
    for m in _RX_SET_CMD.finditer(view):
        tier, v = _tier(m), m.group("v")
        if tier in ("strong", "generic") and _has_ld(v) and credential_value(tier, v, ""):
            yield "set-command", m.group(0)


def _x_authorization(view):
    """Authorization: <scheme> VALUE for any scheme but Basic (ApiKey, Token, a short Bearer); a value of
    8 characters with a letter and a digit. A Bearer or Token value of 20 characters or more is the
    bearer-token rule's."""
    for m in _RX_AUTHZ.finditer(view):
        scheme, v = m.group("scheme").lower(), m.group("v")
        if scheme == "basic" or (scheme in ("bearer", "token") and len(v) >= 20):
            continue
        if credential_value("generic", v, ""):
            yield "authorization-header", m.group(0)


_RX_ASSIGN_Q = re.compile(r"(?i)" + _KBEG + _KTOK + _KQ + _SEP_Q + _QVAL)
_RX_ASSIGN_U = re.compile(r"(?i)" + _KBEG + _KTOK + _KQ + r"\s*(?::=|=>|=)\s*(?=(?P<v>[^\s'\"`]{0,1024}))")
_RX_COLON_U = re.compile(r"(?i)" + _KBEG + _KTOK + _KQ + r"\s*:(?!=)\s*(?=(?P<v>[^\s'\"`,;]{0,1024}))")
_RX_ARGPAIR = re.compile(
    r"(?i)(?P<kq>[\"'`])" + _KTOK + r"(?P=kq)\s*,\s*(?P<q>[\"'`])(?P<v>(?:\\[^\n]|(?!(?P=q))[^\n\\])*)(?P=q)")
_RX_SETTER = re.compile(
    r"(?<![A-Za-z0-9])set_?(?P<key>[A-Za-z][\w]*?)\s*\(\s*(?P<q>[\"'`])(?P<v>(?:\\[^\n]|(?!(?P=q))[^\n\\])*)(?P=q)\s*\)")
_RX_FLAG = re.compile(r"(?i)(?<![\w-])--(?P<key>[\w.-]{1,256}?)\s+(?=\\?(?P<v>[\"'`]?[^\s\"'`]{1,1024}))")
_TOOL_FLAGS = [re.compile(p) for p in (
    r"\b(?:mysql|mysqldump|mysqladmin|mysqlimport|mysqlsh|mariadb(?:-dump)?)\b[^\n|;&]*?\s-p(?P<v>[^\s-][^\s]*)",
    r"\bsshpass\b[^\n|;&]*?\s-p\s*(?P<v>[^\s-]\S*)",
    r"\bcurl\b[^\n|;&]*?\s(?:-u|--user)\s+[\"']?[^\s:\"']+:(?P<v>[^\s\"'@]+)",
    r"\bredis-cli\b[^\n|;&]*?\s-a\s+(?P<v>[^\s-]\S*)",
    r"\bdocker\s+login\b[^\n|;&]*?\s-p\s+(?P<v>[^\s-]\S*)",
    r"\b(?:mongo|mongosh|mongodump|mongorestore|mongoexport|mongoimport)\b[^\n|;&]*?\s-p\s+(?P<v>[^\s-]\S*)",
    r"\bhtpasswd\s+-[A-Za-z]*b[A-Za-z]*\s+(?:-\S+\s+)*[^\s-]\S*\s+[^\s-]\S*\s+(?P<v>[^\s-]\S*)",
    r"(?<![\w-])-(?:pass|passin|passout)\s+pass:(?P<v>\S+)",
    r"\bsqlcmd\b[^\n|;&]*?\s-P\s+(?P<v>[^\s-]\S*)",
    r"\bsmbclient\b[^\n|;&]*?\s-U\s+[^\s%]+%(?P<v>\S+)",
)]
_RX_SPACE = re.compile(r"(?i)(?<![\w.-])(?P<key>[^\W\d][\w.-]{0,255})(?P<sep>[ \t]+)(?=(?P<v>[^\s'\"`,;]{1,1024}))")
_RX_SPACE_Q = re.compile(r"(?i)(?:" + _KBEG + _KTOK + r"|\bidentified\s+by)[ \t]+" + _QVAL)
_RX_NETRC = re.compile(r"(?i)\blogin\s+\S+\s+pass(?:word|wd)\s+(?P<v>\S+)")
_RX_XML_EL = re.compile(r"(?i)<" + _KTOK.replace("[\\w.\\-]{0,255}", "[\\w.\\-:]{0,255}", 1) + r"(?:\s[^<>]*)?>\s*(?P<v>[^<>\s]+)\s*</(?P<ctag>[\w.:-]+)\s*>")
_ATTR_KEY = r"\b(?:key|name|type|id)\s*=\s*(?P<q1>[\"'])(?P<key>[\w.:-]+)(?P=q1)"
_RX_XML_ATTR_V = re.compile(r"(?i)<[\w:.-]+\s[^<>]*?" + _ATTR_KEY + r"[^<>]*?\bvalue\s*=\s*(?P<q2>[\"'])(?P<v>[^\"'<>]*)(?P=q2)")
_RX_XML_ATTR_T = re.compile(r"(?i)<(?P<otag>[\w:.-]+)\s[^<>]*?" + _ATTR_KEY + r"[^<>]*>\s*(?P<v>[^<>\s]+)\s*</(?P<ctag>[\w:.-]+)\s*>")
_RX_YAML_BLOCK = re.compile(r"(?im)" + _KBEG + _KTOK + _KQ + r"[ \t]*:[ \t]*[|>][-+0-9]*[ \t]*\r?\n[ \t]+(?P<v>\S[^\n]*)")
_RX_PGPASS = re.compile(r"(?m)^[ \t]*[^\s:#]+:(?:\d{1,5}|\*):[^\s:]+:[^\s:]+:(?P<v>\S+?)[ \t]*\r?$")
_RX_URL = re.compile(r"(?i)(?<![\w+.-])[a-z][a-z0-9+.-]*://[^/\s:@\[\]]*:(?P<v>[^\s@]+)@")
_RX_TABLE = re.compile(r"(?im)^[ \t]*\|?[ \t]*`?" + _KTOK + r"`?[ \t]*\|[ \t]*`?(?P<v>[^|`\s]{1,1024})`?[ \t]*(?:\||$)")
_RX_SET_CMD = re.compile(r"(?im)(?:^|[;\[{])[ \t]*set[ \t]+" + _KTOK + r"[ \t]+(?P<v>[^\s;\]}\"'`]{1,1024})[ \t]*(?=$|[;\]}])")
_RX_AUTHZ = re.compile(r"(?i)\bauthorization\s*[:=]\s*(?P<scheme>[A-Za-z][\w-]*)\s+(?P<v>[A-Za-z0-9._~+/=-]+)")

# the extractors (stage 2) and the rule names each can report
KEYED_EXTRACTORS = [
    (_x_url, ("url-userinfo-password",)),
    (_x_assign_quoted, ("password-assign", "password-assign-spaced", "short-key-assign")),
    (_x_assign_unquoted, ("password-assign-unquoted", "short-key-assign")),
    (_x_colon_unquoted, ("password-colon-unquoted", "secret-colon-unquoted")),
    (_x_argument_pair, ("argument-pair",)),
    (_x_setter, ("setter-call",)),
    (_x_flag_space, ("password-flag-space",)),
    (_x_short_flag, ("short-flag-value",)),
    (_x_space, ("password-space",)),
    (_x_space_quoted, ("password-space-quoted",)),
    (_x_netrc, ("password-netrc",)),
    (_x_xml_element, ("xml-credential-element",)),
    (_x_xml_attr, ("xml-attribute-pair",)),
    (_x_yaml_block, ("yaml-block-scalar",)),
    (_x_pgpass, ("pgpass-line",)),
    (_x_authorization, ("authorization-header",)),
    (_x_table_row, ("table-row-pair",)),
    (_x_set_command, ("set-command",)),
]
# the token shapes: a vendor prefix or a fixed format (stage 2 for a credential that carries no key)
SECRET_PATTERNS = [
    ("aws-access-key-id", re.compile(r"\b(?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA)[0-9A-Z]{16}\b")),
    ("aws-secret-assign", re.compile(r"(?i)aws_?secret_?access_?key\s*[:=]\s*['\"]?[A-Za-z0-9/+]{40}")),
    ("github-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    ("github-fine-grained-pat", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{30,}\b")),
    ("gitlab-pat", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
    ("gitlab-other-token", re.compile(r"\bgl(?:dt|ptt|rt|soat|cbt|imt|agent)-[A-Za-z0-9_-]{20,}\b")),
    ("gcp-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("private-key-block", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----")),
    ("huggingface-token", re.compile(r"\bhf_[A-Za-z0-9]{30,}\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+")),
    ("slack-token", re.compile(r"\bxox[abposre]-[A-Za-z0-9-]{10,}\b")),
    ("openai-anthropic-key", re.compile(r"\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{32,}\b")),
    ("bearer-token", re.compile(r"(?i)authorization:\s*(?:bearer|token)\s+[A-Za-z0-9._~+/=-]{20,}")),
    ("basic-auth", re.compile(r"(?i)authorization:\s*basic\s+[A-Za-z0-9+/=]{8,}")),
    ("stripe-key", re.compile(r"\b[rs]k_(?:live|test)_[A-Za-z0-9]{20,}\b")),
    ("npm-token", re.compile(r"\bnpm_[A-Za-z0-9]{36}\b")),
    ("telegram-bot-token", re.compile(r"\b\d{8,10}:AA[A-Za-z0-9_-]{33}\b")),
]
# the rules whose shape is a whole line (their needles are written on a line of their own)
LINE_RULES = {"pgpass-line", "table-row-pair", "set-command"}
SECRET_RULE_NAMES = [n for n, _ in SECRET_PATTERNS] + [n for _, ns in KEYED_EXTRACTORS for n in ns if n != "short-key-assign"] + ["short-key-assign"]
EPHEMERAL_PATTERNS = [
    ("scratchpad", re.compile(r"scratchpad|/\.cache/claude-tmp/", re.I)),
    ("tmp-path", re.compile(r"(?<![\w.-])/(?:var/)?tmp/[^\s,;)`'\"]+")),
    ("mktemp-default", re.compile(r"(?<![\w.-])tmp\.(?!X{10})[A-Za-z0-9]{10}(?![\w-])")),
    # a mktemp-style suffix: 4 to 12 letters and digits, mixed (an upper-case letter or a digit, and a
    # lower-case letter), or all lower-case when the name is a directory (followed by a slash)
    ("mktemp-dir", re.compile(
        r"(?<![\w/.-])[\w-]+\.(?:(?=[A-Za-z0-9]{0,11}[A-Z0-9])(?=[A-Za-z0-9]{0,11}[a-z])[A-Za-z0-9]{4,12}"
        r"(?=[/,;):\s]|$)|[a-z]{4,12}(?=/))")),
    ("bundle-file", re.compile(r"[\w./-]+\.bundle\b")),
    ("bare-review-file", re.compile(r"(?<![\w/.-])(?:review_[\w-]+\.(?:md|txt)|[\w-]+_lander_items\.md|review_[\w-]+_logs/)")),
    # a home directory of a named user, or a dotted directory under ~ (agent and tool state)
    ("home-path", re.compile(r"(?<![\w.-])(?:/(?:home|Users)/[\w.-]+/|~/\.[\w-]+/)")),
    # an agent session store (transcripts, todo lists, shell snapshots)
    ("session-store", re.compile(r"\.claude[\w-]*/(?:projects|todos|shell-snapshots)/")),
]
# NUL, C0 other than tab and newline, DEL, C1, and the two Unicode line separators
CONTROL_CHAR = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f\u2028\u2029]")
# the invisible characters that are not Cf (round 9, review r9 F1): COMBINING GRAPHEME JOINER, the Hangul
# fillers, the Khmer inherent vowels, the Mongolian free variation selectors and the variation selectors;
# a key spelled with one of them reads as a different key to a pattern and the same key to a reader
INVISIBLE_CHAR = re.compile("[\u034f\u115f\u1160\u17b4\u17b5\u180b-\u180f\u3164\ufe00-\ufe0f\uffa0\U000e0100-\U000e01ef]")


def control_char(text):
    """The earliest control character, line separator or format character (Cf) in text, or None. Cf
    holds the bidi overrides and isolates (Trojan Source), the BOM, the soft hyphen, the zero-width
    characters and the tag characters, which change what a reader sees without being visible; and the
    invisible characters that are not Cf (INVISIBLE_CHAR: variation selectors, the combining grapheme
    joiner, the Hangul fillers)."""
    if text.isascii():
        cm = CONTROL_CHAR.search(text)
        return cm.group(0) if cm else None
    for ch in text:
        if CONTROL_CHAR.match(ch) or unicodedata.category(ch) == "Cf" or INVISIBLE_CHAR.match(ch):
            return ch
    return None
CODES = {
    "XREF-DANGLING", "XREF-LABEL", "XREF-UNLABELLED", "FOREIGN-STALE", "STATE-PROSE", "STATE-EVIDENCE",
    "SECTIONS", "BODY-SYNC", "SECRET", "EPHEMERAL", "CONTROL-CHAR", "SHARED-PATH", "DUP-CHECK",
    "DUP-SAME-OPEN", "DUP-HEAD", "DUP-UNDECIDED", "DUP-STATUS", "OBSOLETE-STALE", "PATH-MISSING",
}
DUP_LINE = re.compile(r"^Duplicate check \(section 11\.4\.214\):\s*(\S+)(.*)$", re.M)
DUP_VERDICTS = {"DISTINCT", "DISTINCT-but-similar", "SAME-DEFECT", "UNDECIDED"}
DUP_LINK_VERDICTS = {"SAME-DEFECT", "UNDECIDED"}
DUP_WORDS = re.compile(r"(?i)\b(?:candidates?|undecided|duplicates?|same[- ]defect|(?:second|canonical|open|two|other) heads?)\b")
FOREIGN_LINE = re.compile(r"^Foreign ids\b[^:]*:(.*)$", re.M)
STALE_NOTE = re.compile(r"^Stale obsolete_details row \(([^)]*)\)", re.M)
# the match may end with a sentence dot ("see docs/qa/x/e.txt."); PATH-MISSING strips it (round-3
# review LC9: with the end class [\w/] the strip was dead code, so its mutant could not die)
EVIDENCE_PATH = re.compile(r"(?<![\w./-])(docs/(?:qa|operator_decisions)/[\w./-]*[\w/.])")
PATH_IN_SCOPE = re.compile(r"(?<![\w.-])((?:[\w.-]+/)*[\w.-]+\.(?:sh|py|go|tsv|yaml|yml|json))\b")
SHA_RX = re.compile(r"(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])")
# keys of the header block the engine renders into body_md (renderItemBody and the closure, reopen,
# block and obsolete-details paths); Reopens-count is legacy (no current engine path writes it)
BODY_KEYS = {
    "Status", "Type", "Severity", "Created-By", "Assigned-To", "Evidence", "Reproduction", "Investigation",
    "Obsolete-Details", "Reopened-Details", "Operator-Block-Details", "Reopens-count",
}
EXACT_KEYS = ["Status", "Type", "Severity", "Created-By", "Assigned-To", "Reproduction", "Investigation", "Obsolete-Details"]
CLOSURE_EVENTS = {"Fixed", "Implemented", "Completed", "Obsolete"}
LINE_SEPARATORS = re.compile("[\r\x0b\x0c\x1c\x1d\x1e\x85  ]")
CLAUSE_SPLIT = re.compile(r"[;\n]|\.(?=\s|$)")
MAX_RANGE = 200
REQUIRED_TABLES = ("items", "obsolete_details", "operator_block_details", "item_history")
ITEM_COLUMNS = [
    "atm_id", "type", "status", "severity", "title", "description", "forensic_anchor", "closure_criteria",
    "composes_with", "destination", "logic_group", "created_by", "assigned_to", "current_location", "body_md",
    "representation", "closure_date", "round", "commit_ref", "parent_atm_id", "session_ref",
    "reproduction_state", "reproduction_surface", "reproduction_evidence", "reproduction_red_cmd",
    "reproduction_green_cmd", "reproduction_env", "reproduction_signature", "reproduction_blocker",
    "reproduction_updated_at", "reproduction_updated_by", "investigation_state", "investigation_root_cause",
    "investigation_evidence", "investigation_updated_at", "investigation_updated_by", "created_at",
    "last_modified",
]
STATE_TEXT_COLS = ["reproduction_red_cmd", "reproduction_green_cmd", "reproduction_env",
                   "reproduction_signature", "reproduction_blocker", "investigation_root_cause"]
RENDERED_FILES = ["Issues.md", "Fixed.md", "Issues_Summary.md", "Fixed_Summary.md"]
RENDERED_ID_CELL = re.compile(r"^([A-Za-z][A-Za-z0-9]*-[0-9]+)(?: — |$)")
RENDERED_HEADING = re.compile(r"^## ([A-Za-z][A-Za-z0-9]*-[0-9]+)(?: — |\. )")
STATE_SEP = " — "


class Blind(Exception):
    """The instrument could not see: no verdict (exit 3)."""


def words(s):
    return {t for t in re.split(r"[^a-z0-9_]+", s.lower()) if len(t) >= 4 and t not in STOP and not t.isdigit()}


def id_re(prefix):
    # ASCII digits: \d also reads fullwidth and other Unicode digits (round 4, R4-5)
    return re.compile(r"(?<![\w-])" + re.escape(prefix) + r"-([0-9]+)\b(?!-)")


def range_re(prefix):
    p = re.escape(prefix)
    return re.compile(r"(?<![\w-])" + p + r"-([0-9]+)\.\." + p + r"-([0-9]+)\b(?!-)")


def ids_in(text, prefix):
    """Every id named in text: each token, plus the interior of each range `P-a..P-b` (0 < b-a <= 200).
    Returns a dict id -> count."""
    out = {}
    for m in id_re(prefix).finditer(text):
        out[m.group(0)] = out.get(m.group(0), 0) + 1
    for m in range_re(prefix).finditer(text):
        a, b = int(m.group(1)), int(m.group(2))
        if 0 < b - a <= MAX_RANGE:
            w = len(m.group(1))
            for n in range(a + 1, b):
                iid = "%s-%0*d" % (prefix, w, n)
                out[iid] = out.get(iid, 0) + 1
    return out


def col(r, name):
    """A column value as text ("" for NULL)."""
    v = r.get(name)
    return "" if v is None else str(v)


def state_text(r):
    return "\n".join(col(r, c) for c in STATE_TEXT_COLS if col(r, c))


def strip_structured_state_lines(desc):
    return "\n".join(
        l for l in desc.split("\n") if not (l.startswith("**Reproduction:**") or l.startswith("**Investigation:**"))
    )


def scope_section(desc):
    m = re.search(r"^\*\*Affected scope / file-scope manifest:\*\*\n(.*?)(?:\n\n|\Z)", desc, re.S | re.M)
    return m.group(1) if m else ""


def foreign_ids(desc, prefix):
    out = set()
    for m in FOREIGN_LINE.finditer(desc):
        out |= set(ids_in(m.group(1), prefix))
    return out


def text_without_foreign_line(desc):
    return FOREIGN_LINE.sub("", desc)


def clause_at(text, start, end):
    # scan the whole text: an endpos bound makes `$` match at the bound, so the dot before the end of a
    # range (`FX-001..FX-003`) read as a sentence end and the range end lost its clause (round 4)
    s = 0
    for m in CLAUSE_SPLIT.finditer(text):
        if m.end() > start:
            break
        s = m.end()
    m = CLAUSE_SPLIT.search(text, end)
    return text[s:m.start() if m else len(text)]


def line_at(text, pos):
    s = text.rfind("\n", 0, pos) + 1
    e = text.find("\n", pos)
    return text[s:e if e >= 0 else len(text)]


def exempt_line(text, pos):
    """An unlabelled id on a `Duplicate check` line or a `Stale obsolete_details row` note is judged by
    the DUP-* and OBSOLETE-STALE checks, not by XREF-UNLABELLED."""
    line = line_at(text, pos)
    return bool(DUP_LINE.match(line) or STALE_NOTE.match(line))


# ---- engine renderings (a port of scripts/workable-items/cmd/workable-items/states.go) -------------

def encode_code_span(v):
    """encodeCodeSpan: the fence is one backtick longer than the longest backtick run; a value that
    starts or ends with a backtick is padded with one space on each side."""
    run = best = 0
    for ch in v:
        run = run + 1 if ch == "`" else 0
        best = max(best, run)
    fence = "`" * (best + 1)
    if v.startswith("`") or v.endswith("`"):
        return fence + " " + v + " " + fence
    return fence + v + fence


def details(pairs):
    out = []
    for key, val in pairs:
        if val == "":
            continue
        out.append(STATE_SEP + key + " " + (val if key in ("surface", "updated") else encode_code_span(val)))
    return "".join(out)


def repro_details(r):
    return [("surface", col(r, "reproduction_surface")), ("evidence", col(r, "reproduction_evidence")),
            ("red-command", col(r, "reproduction_red_cmd")), ("green-command", col(r, "reproduction_green_cmd")),
            ("env", col(r, "reproduction_env")), ("signature", col(r, "reproduction_signature")),
            ("blocker", col(r, "reproduction_blocker")), ("updated", col(r, "reproduction_updated_at")),
            ("by", col(r, "reproduction_updated_by"))]


def repro_label(r):
    """reproLabel: REPRODUCED only for a live or host-fixture state with every required detail, no
    UNCONFIRMED value, and not a host fixture on a live-target surface."""
    st = col(r, "reproduction_state") or "UNSET"
    if st not in ("reproduced-live", "reproduced-host-fixture"):
        return "UNREPRODUCED"
    d = dict(repro_details(r))
    if any(d[k] == "" for k in ("surface", "evidence", "red-command", "env", "signature")):
        return "UNREPRODUCED"
    if st == "reproduced-host-fixture" and d["surface"] == "live-target":
        return "UNREPRODUCED"
    if any(v.startswith("UNCONFIRMED") for _, v in repro_details(r)):
        return "UNREPRODUCED"
    return "REPRODUCED"


def repro_line(r):
    st = col(r, "reproduction_state") or "UNSET"
    if st == "UNSET":
        return None
    head = "none" + STATE_SEP + "UNREPRODUCED" if st == "UNREPRODUCED" else st + STATE_SEP + repro_label(r)
    return "**Reproduction:** " + head + details(repro_details(r))


def inv_line(r):
    st = col(r, "investigation_state") or "UNSET"
    if st == "UNSET":
        return None
    return "**Investigation:** " + st + details([
        ("root-cause", col(r, "investigation_root_cause")), ("evidence", col(r, "investigation_evidence")),
        ("updated", col(r, "investigation_updated_at")), ("by", col(r, "investigation_updated_by"))])


def obsolete_line(od):
    return "**Obsolete-Details:** Since: %s; Reason: %s; Superseding-item: %s; Triple-check evidence: %s" % (
        col(od, "since"), col(od, "reason"), col(od, "superseding_item"), col(od, "triple_check_evidence"))


def reopened_rows(r):
    return [h for h in r["hist"] if h.get("event_type") == "Reopened"]


def reopen_line(h):
    return "**Reopened-Details:** By: %s On: %s Reason: %s Evidence: %s" % (
        col(h, "by"), col(h, "on_date"), col(h, "reason"), col(h, "evidence_path"))


def closure_evidence(r):
    out = {col(h, "evidence_path") for h in r["hist"] if h.get("event_type") in CLOSURE_EVENTS}
    if r["od"]:
        out.add(col(r["od"], "triple_check_evidence"))
    return out - {""}


def expected_lines(r):
    """The exact header line each EXACT_KEYS key must carry, or None when it must be absent."""
    exp: "dict[str, str | None]" = {"Status": "**Status:** %s" % col(r, "status"), "Type": "**Type:** %s" % col(r, "type")}
    for key, name in (("Severity", "severity"), ("Created-By", "created_by"), ("Assigned-To", "assigned_to")):
        v = col(r, name)
        exp[key] = "**%s:** %s" % (key, v) if v.strip() else None
    exp["Reproduction"] = repro_line(r)
    exp["Investigation"] = inv_line(r)
    exp["Obsolete-Details"] = obsolete_line(r["od"]) if col(r, "status").startswith("Obsolete") and r["od"] else None
    return exp


def engine_body(r):
    """The body the engine renders for a row (fixtures of the self-check): heading, the header block
    with every key the sources give, then the description."""
    exp = expected_lines(r)
    hdr = [x for x in (exp[k] for k in ("Status", "Type")) if x]
    ev = sorted(closure_evidence(r))
    if ev:
        hdr.append("**Evidence:** " + ev[0])
    hdr += [x for x in (exp[k] for k in EXACT_KEYS[2:]) if x]
    rr = reopened_rows(r)
    if rr:
        hdr.append(reopen_line(rr[-1]))
    if r["obd"]:
        hdr.append("**Operator-Block-Details:** WHAT: %s" % col(r["obd"], "what"))
    return "## %s — %s\n\n%s\n\n%s\n\n" % (r["id"], r["title"], "\n".join(hdr), r["description"])


def body_problems(r):
    """BODY-SYNC in both directions: body_md must be the engine rendering of the item's sources."""
    b, d = r["body"], r["description"]
    if not b:
        return ["body_md is empty"]
    if b.find(d) < 0:
        return ["description is not contained in body_md"]
    # parse the rendered prefix first (heading, header block, one blank line); the description must
    # start right after it. Searching for the description first would find a description equal to the
    # title inside the heading.
    m = re.match(r"## (\S+) — ([^\n]*)\n\n((?:\*\*[A-Za-z-]+:\*\*[^\n]*\n)*)\n", b)
    out = []
    if not m or not b.startswith(d, m.end()):
        out.append("body_md carries text before the description outside the heading and header block")
        return out
    suf = b[m.end() + len(d):]
    if suf.strip():
        out.append("body_md carries text after the description: %r" % suf.strip()[:40])
    if m.group(1) != r["id"] or m.group(2) != r["title"]:
        out.append("body_md heading disagrees with the id or title column")
    hdr = {}
    # split on "\n" only: str.splitlines() also splits on U+2028, U+0085, \r and others, which the
    # header pattern lets through inside a line; such a line is a finding, never a crash
    for line in m.group(3).split("\n")[:-1]:
        if LINE_SEPARATORS.search(line):
            out.append("body_md header line carries a line separator other than a newline: %r" % line[:40])
        km = re.match(r"\*\*([A-Za-z-]+):\*\*", line)
        if km is None:  # unreachable while the header pattern holds; a finding, never a crash
            out.append("body_md header line does not start with a key: %r" % line[:40])
            continue
        key = km.group(1)
        if key not in BODY_KEYS:
            out.append("body_md header key %s is not an engine key" % key)
        if key in hdr:
            out.append("body_md header key %s is written twice" % key)
            continue
        hdr[key] = line
    exp = expected_lines(r)
    for key in EXACT_KEYS:
        want, have = exp[key], hdr.get(key)
        if want is None and have is not None:
            out.append("body_md has %s line while its source gives none" % ("an " + key if key[0] in "AEIOU" else "a " + key))
        elif want is not None and have is None:
            out.append("body_md lacks the %s line its source gives" % key)
        elif want is not None and have != want:
            out.append("body_md %s line differs from its source" % key)
    if "Evidence" in hdr and hdr["Evidence"][len("**Evidence:** "):] not in closure_evidence(r):
        out.append("body_md Evidence line names no closure evidence of the item")
    if "Reopened-Details" in hdr:
        rr = reopened_rows(r)
        if not rr:
            out.append("body_md has a Reopened-Details line but the item has no Reopened history row")
        elif hdr["Reopened-Details"] != reopen_line(rr[-1]):
            out.append("body_md Reopened-Details line differs from the last Reopened history row")
    if "Operator-Block-Details" in hdr:
        o = r["obd"]
        if o is None:
            out.append("body_md has an Operator-Block-Details line but the item has no operator_block_details row")
        elif not hdr["Operator-Block-Details"].startswith("**Operator-Block-Details:** WHAT: %s" % col(o, "what")):
            out.append("body_md Operator-Block-Details line differs from the item's row")
    if "Reopens-count" in hdr and hdr["Reopens-count"] != "**Reopens-count:** %d" % len(reopened_rows(r)):
        out.append("body_md Reopens-count line differs from the number of Reopened history rows")
    return out


# ---- surfaces ---------------------------------------------------------------------------------------

def surfaces(r, rendered):
    """(surface name, text) for every text surface of an item (see SURFACES in the header)."""
    yield "title", r["title"]
    yield "description", r["description"]
    yield "body_md", r["body"]
    for name in r["_cols"]:
        if name in ("title", "description", "body_md"):
            continue
        v = r.get(name)
        if v is not None:
            yield "items." + name, str(v)
    for table, row in (("obsolete_details", r["od"]), ("operator_block_details", r["obd"])):
        for name, v in sorted((row or {}).items()):
            if name != "atm_id" and v is not None:
                yield "%s.%s" % (table, name), str(v)
    for h in r["hist"]:
        for name, v in sorted(h.items()):
            if name not in ("atm_id", "id") and v is not None:
                yield "item_history[%s].%s" % (h.get("id"), name), str(v)
    for fname, line in rendered.get(r["id"], []):
        yield "rendered:" + fname, line


def secret_hits(text):
    """(rule name, match) for every credential rule found in text: the token shapes and the keyed
    extractors, over every view of the front end (secret_views). The match is for its caller to mask,
    never to print. The leak scan of the evidence pack is a SEPARATE implementation (round 8, N2)."""
    views = secret_views(text)
    found = {}
    for t in views:
        for name, pat in SECRET_PATTERNS:
            if name not in found:
                m = pat.search(t)
                if m:
                    found[name] = m.group(0)
        for ex, _names in KEYED_EXTRACTORS:
            for name, s in ex(t):
                if name not in found:
                    found[name] = s
    for name in SECRET_RULE_NAMES:
        if name in found:
            yield name, found[name]
    # round 11 (review r10 finding 1): the shared canonical primitive closes the class; it is reported by
    # its own rule names only where none of the named extractors above read the text, so a shape keeps
    # the rule that names it and a form no extractor knows is still a finding
    if not found and SECRET_CANONICAL:
        seen = set()
        for name, s in CANON.hits(text):
            if name not in seen:
                seen.add(name)
                yield name, s


def scan_surfaces(r, rendered):
    """SECRET, EPHEMERAL and CONTROL-CHAR over every surface: one finding per (code, pattern)."""
    hits = {}

    def hit(code, name, surface, shown=""):
        key = (code, name)
        if key not in hits:
            hits[key] = (shown, [])
        if surface not in hits[key][1]:
            hits[key][1].append(surface)

    for surface, text in surfaces(r, rendered):
        for name, _ in secret_hits(text):
            hit("SECRET", name, surface)
        # an "(ephemeral" note exempts its own line only
        for line in text.split("\n"):
            if "(ephemeral" in line:
                continue
            for name, pat in EPHEMERAL_PATTERNS:
                em = pat.search(line)
                if em:
                    hit("EPHEMERAL", name, surface, em.group(0)[:60])
        ch = control_char(text)
        if ch:
            hit("CONTROL-CHAR", "U+%04X" % ord(ch), surface)
        if surface == "title" and ("\n" in text or "\t" in text):
            hit("CONTROL-CHAR", "newline or tab in the title", surface)
    out = []
    for (code, name), (shown, where) in sorted(hits.items()):
        label = name + (": " + shown if shown else "")
        out.append((code, r["id"], "%s on %s" % (label, ",".join(where))))
    return out


# ---- state evidence ---------------------------------------------------------------------------------

def state_evidence_problems(r, fs):
    """STATE-EVIDENCE (section 11.4.294(C)); fs is None or an object with exists(rel) and sha256(rel)."""
    out = []
    rs = col(r, "reproduction_state") or "UNSET"
    if rs in REPRO_NEEDS_EVIDENCE:
        out += evidence_problems("reproduction", rs, col(r, "reproduction_evidence"),
                                 col(r, "reproduction_env"), fs)
    if rs == "blocked-no-device-with-recorded-blocker" and not col(r, "reproduction_blocker").strip():
        out.append("reproduction_state %s without a reproduction_blocker" % rs)
    ivs = col(r, "investigation_state") or "UNSET"
    if ivs in INV_NEEDS_EVIDENCE:
        out += evidence_problems("investigation", ivs, col(r, "investigation_evidence"),
                                 col(r, "investigation_root_cause") + " " + col(r, "investigation_evidence"), fs)
    return out


def evidence_problems(block, state, path, sha_text, fs):
    out = []
    shas = set(SHA_RX.findall(sha_text))
    if not path:
        out.append("%s_state %s without an evidence path" % (block, state))
    if not shas:
        out.append("%s_state %s carries no evidence sha256" % (block, state))
    if fs is not None and path:
        if not fs.exists(path):
            out.append("%s evidence %s does not exist" % (block, path))
        elif shas and fs.sha256(path) not in shas:
            out.append("%s evidence sha256 differs from the file %s" % (block, path))
    return out


class RepoFS:
    def __init__(self, root):
        self.root = root

    def exists(self, rel):
        return os.path.isfile(os.path.join(self.root, rel))

    def sha256(self, rel):
        h = hashlib.sha256()
        with open(os.path.join(self.root, rel), "rb") as f:
            for chunk in iter(lambda: f.read(1 << 16), b""):
                h.update(chunk)
        return h.hexdigest()


# ---- duplicate heads --------------------------------------------------------------------------------

def is_open(o):
    return o["location"] == "Issues" and not o["status"].startswith("Obsolete")


def links_as_duplicate(text, target, prefix):
    """True when text names target as a possible duplicate: on its Duplicate check line with a
    SAME-DEFECT or UNDECIDED verdict (any case), or outside that line in a clause with a duplicate
    word (any case). A Duplicate check line with any other verdict does not count."""
    for m in id_re(prefix).finditer(text):
        if m.group(0) != target:
            continue
        line = line_at(text, m.start())
        dl = DUP_LINE.match(line)
        if dl:
            if dl.group(1).rstrip(";,.:").upper() in DUP_LINK_VERDICTS:
                return True
            continue
        if DUP_WORDS.search(clause_at(text, m.start(), m.end())):
            return True
    return False


def competing_heads(head, all_items, exclude, prefix):
    """Open items other than head that are, or may be, a second head of the same defect."""
    out = {}
    hid = head["id"]
    for y, o in all_items.items():
        if y in exclude or y == hid or not is_open(o):
            continue
        if links_as_duplicate(o["description"], hid, prefix):
            out[y] = "%s names %s as a duplicate" % (y, hid)
        elif links_as_duplicate(head["description"], y, prefix):
            out[y] = "%s names %s as a duplicate" % (hid, y)
        elif (o["obsolete_reason"] == "duplicate-of" and o["obsolete_superseding"] == hid
              and not STALE_NOTE.search(o["description"])):
            out[y] = "%s is open with an obsolete_details row duplicate-of %s" % (y, hid)
    return out


# ---- the lint ---------------------------------------------------------------------------------------

def lint_items(sel, all_items, prefix, require_dup, repo_root=None, exists=None, rendered=None, fs=None):
    """sel: list of rows; all_items: dict id -> row (first location). Returns a list of findings.
    exists(rel) decides PATH-MISSING (default: the path exists under repo_root); fs gives the
    evidence-file checks of STATE-EVIDENCE (default: RepoFS(repo_root) when repo_root is set)."""
    if repo_root and exists is None:
        exists = lambda rel: os.path.exists(os.path.join(repo_root, rel))
    if repo_root and fs is None and repo_root != "<needle>":
        fs = RepoFS(repo_root)
    rendered = rendered or {}
    rx = id_re(prefix)
    findings = []
    sel_ids = {r["id"] for r in sel}
    open_others = [r for i, r in all_items.items() if i not in sel_ids and r["location"] == "Issues"]
    for r in sel:
        iid, desc = r["id"], r["description"]
        fids = foreign_ids(desc, prefix)
        body_text = r["title"] + "\n" + text_without_foreign_line(desc)
        named = set(ids_in(body_text + "\n" + state_text(r), prefix))
        # XREF-DANGLING (tokens and range interiors, title, description and state text columns)
        for ref in sorted(named):
            if ref not in fids and ref not in all_items:
                findings.append(("XREF-DANGLING", iid, ref))
        # an id written with non-ASCII digits is no id of this tracker and no reader can follow it
        for u in sorted({u.group(0) for u in re.finditer(r"(?<![\w-])" + re.escape(prefix) + r"-(\d+)",
                                                          body_text + "\n" + state_text(r)) if not u.group(1).isascii()}):
            findings.append(("XREF-DANGLING", iid, "%s (non-ASCII digits)" % u))
        # XREF-LABEL / XREF-UNLABELLED (explicit tokens)
        for m in rx.finditer(body_text):
            ref = m.group(0)
            if ref in fids or ref not in all_items or ref == iid:
                continue
            target = all_items[ref]
            tw = words(target["title"])
            lab = re.match(r"\s*\(([^()]{2,80})\)", body_text[m.end():])
            if lab:
                lw = words(lab.group(1))
                if lw:
                    missing = lw - (tw | words(target["description"]))
                    if not (lw & tw) or 3 * len(missing) > len(lw):
                        findings.append(("XREF-LABEL", iid, "%s (%s) vs title: %s" % (ref, lab.group(1), target["title"][:60])))
            elif not exempt_line(body_text, m.start()):
                cw = words(rx.sub(" ", clause_at(body_text, m.start(), m.end())))
                if not (cw & tw):
                    findings.append(("XREF-UNLABELLED", iid, "%s without a label in a clause that shares no title word: %s" % (ref, target["title"][:60])))
        for f in sorted(fids - named):
            findings.append(("FOREIGN-STALE", iid, f))
        # STATE-PROSE
        prose = strip_structured_state_lines(desc)
        rs, ivs = r["repro"] or "UNSET", r["inv"] or "UNSET"
        for tok in REPRO_TOKENS:
            for _ in re.finditer(r"(?<![\w-])" + re.escape(tok) + r"(?![\w-])", prose):
                canon = "blocked-no-device-with-recorded-blocker" if tok == "blocked-no-device" else tok
                ok = (rs in UNREPRO_FAMILY) if canon == "UNREPRODUCED" else (rs == canon)
                if not ok:
                    findings.append(("STATE-PROSE", iid, "prose says %s, reproduction_state is %s" % (tok, rs)))
                break
        for tok in INV_TOKENS:
            if re.search(r"(?<![\w-])" + re.escape(tok) + r"(?![\w-])", prose) and ivs != tok:
                findings.append(("STATE-PROSE", iid, "prose says %s, investigation_state is %s" % (tok, ivs)))
        for m in re.finditer(r"\bInvestigation:\s*([\w-]+)", prose):
            if m.group(1) in INV_STATES and m.group(1) != ivs:
                findings.append(("STATE-PROSE", iid, "prose says Investigation: %s, investigation_state is %s" % (m.group(1), ivs)))
        # STATE-PROSE, structured form: a `**Reproduction:**` / `**Investigation:**` line written into the
        # description must name the column's state (reviewer mutant M11)
        for line in desc.split("\n"):
            if line.startswith("**Reproduction:**"):
                toks = [t for t in REPRO_TOKENS if re.search(r"(?<![\w-])" + re.escape(t) + r"(?![\w-])", line)]
                tok = toks[0] if toks else None
                canon = "blocked-no-device-with-recorded-blocker" if tok == "blocked-no-device" else tok
                ok = canon is not None and ((rs in UNREPRO_FAMILY) if canon == "UNREPRODUCED" else (rs == canon))
                if not ok:
                    findings.append(("STATE-PROSE", iid, "structured line says %s, reproduction_state is %s" % (tok, rs)))
            elif line.startswith("**Investigation:**"):
                toks = [t for t in INV_STATES if re.search(r"(?<![\w-])" + re.escape(t) + r"(?![\w-])", line)]
                if not toks or toks[0] != ivs:
                    findings.append(("STATE-PROSE", iid, "structured line says %s, investigation_state is %s" % (toks[0] if toks else None, ivs)))
        # STATE-EVIDENCE
        for p in state_evidence_problems(r, fs):
            findings.append(("STATE-EVIDENCE", iid, p))
        # SECTIONS
        for name, pat in SECTION_MARKERS:
            if not pat.search(desc):
                findings.append(("SECTIONS", iid, "missing: " + name))
        # BODY-SYNC (both directions, every header key)
        for p in body_problems(r):
            findings.append(("BODY-SYNC", iid, p))
        # SECRET, EPHEMERAL, CONTROL-CHAR on every surface
        findings += scan_surfaces(r, rendered)
        # PATH-MISSING (only with --repo-root): a cited evidence path under docs/qa/ or
        # docs/operator_decisions/ must exist in the repository (section 11.4.215)
        if repo_root and exists is not None:
            for m in EVIDENCE_PATH.finditer(desc):
                rel = m.group(1).rstrip(".,;:)")
                if not exists(rel):
                    findings.append(("PATH-MISSING", iid, rel))
        # OBSOLETE-STALE
        if r["obsolete_reason"] is not None and not r["status"].startswith("Obsolete"):
            note = STALE_NOTE.search(desc)
            ok = False
            if note:
                for m in rx.finditer(note.group(1)):
                    o = all_items.get(m.group(0))
                    if o and is_open(o):
                        ok = True
            if not ok:
                findings.append(("OBSOLETE-STALE", iid, "obsolete_details row (%s) on a %s item" % (r["obsolete_reason"], r["status"])))
        # DUP-*
        dl = DUP_LINE.search(desc)
        dup_named = {m.group(0) for m in rx.finditer(dl.group(0))} if dl else set()
        verdict = dl.group(1).rstrip(";,.:") if dl else None
        if require_dup:
            if not dl:
                findings.append(("DUP-CHECK", iid, "no `Duplicate check (section 11.4.214):` line"))
            elif verdict not in DUP_VERDICTS:
                findings.append(("DUP-CHECK", iid, "verdict %r not in the closed set" % dl.group(1)))
        closed_dup = r["status"].startswith("Obsolete") and r["obsolete_reason"] == "duplicate-of"
        if dl is not None and verdict == "SAME-DEFECT":
            hm = re.match(r"\s*of\s+(" + re.escape(prefix) + r"-[0-9]+)\b", dl.group(2))
            head = hm.group(1) if hm else None
            if head is None:
                findings.append(("DUP-CHECK", iid, "SAME-DEFECT names no id (`SAME-DEFECT of <id>`)"))
            if not (closed_dup and head is not None and r["obsolete_superseding"] == head):
                findings.append(("DUP-SAME-OPEN", iid, "SAME-DEFECT of %s but not Obsolete duplicate-of %s" % (head, head)))
            t = all_items.get(head) if head else None
            if t is not None:
                if not is_open(t):
                    findings.append(("DUP-HEAD", iid, "%s is not an open head (status %s): resolve the chain (section 11.4.214(0))" % (head, t["status"])))
                else:
                    others = competing_heads(t, all_items, {iid}, prefix)
                    for y in sorted(others):
                        findings.append(("DUP-HEAD", iid, "more than one head (section 11.4.214(0)): %s" % others[y]))
        elif verdict == "UNDECIDED":
            cands = {x for x in dup_named if x != iid}
            if not cands:
                findings.append(("DUP-UNDECIDED", iid, "UNDECIDED names no candidate id"))
            if r["status"].startswith("Obsolete") or r["location"] != "Issues":
                findings.append(("DUP-UNDECIDED", iid, "UNDECIDED but the item is closed (%s); mint-with-link keeps it open" % r["status"]))
        if closed_dup and verdict != "SAME-DEFECT":
            findings.append(("DUP-STATUS", iid, "Obsolete duplicate-of %s but the verdict is %s" % (r["obsolete_superseding"], verdict)))
        # SHARED-PATH
        names = {p.rsplit("/", 1)[-1] for p in PATH_IN_SCOPE.findall(scope_section(desc))}
        names = {n for n in names if len(n) >= 8}
        for o in open_others:
            otext = o["title"] + "\n" + o["description"]
            hit = sorted(n for n in names if re.search(r"(?<![\w.-])" + re.escape(n) + r"(?![\w-])", otext))
            if hit and o["id"] not in dup_named:
                findings.append(("SHARED-PATH", iid, "%s also named by open %s" % (hit[0], o["id"])))
    return findings


def embeddings(sel, all_items, prefix):
    sel_ids = {r["id"] for r in sel}
    rows = []
    for r in sel:
        fids = foreign_ids(r["description"], prefix)
        counts = ids_in(r["title"] + "\n" + r["description"] + "\n" + state_text(r), prefix)
        for ref in sorted(counts):
            ns = "foreign" if ref in fids else ("own" if ref in sel_ids else ("main" if ref in all_items else "unknown"))
            rows.append((r["id"], ref, ns, counts[ref]))
    return rows


# ---- loading ----------------------------------------------------------------------------------------

def make_row(cols, od=None, obd=None, hist=(), names=None):
    """An item row: every column under its own name, plus the aliases the checks read."""
    r = dict(cols)
    r["_cols"] = list(names if names is not None else cols.keys())
    r["id"] = cols["atm_id"]
    r["body"] = cols.get("body_md") or ""
    r["location"] = cols["current_location"]
    r["repro"] = cols.get("reproduction_state")
    r["inv"] = cols.get("investigation_state")
    r["od"], r["obd"], r["hist"] = od, obd, list(hist)
    r["obsolete_reason"] = od["reason"] if od else None
    r["obsolete_superseding"] = od["superseding_item"] if od else None
    return r


def check_values(table, rows):
    """A BLOB anywhere, or a non-text title, description, status or location, is BLIND (a crash or a
    false null otherwise)."""
    for row in rows:
        for name, v in row.items():
            if isinstance(v, (bytes, bytearray, memoryview)):
                raise Blind("a BLOB value in %s.%s (row %s)" % (table, name, row.get("atm_id")))
        if table == "items":
            for name in ("title", "description", "status", "current_location"):
                if not isinstance(row.get(name), str):
                    raise Blind("item %s has a NULL or non-text %s" % (row.get("atm_id"), name))
            if row.get("body_md") is not None and not isinstance(row["body_md"], str):
                raise Blind("item %s has a non-text body_md" % row.get("atm_id"))


def load(db):
    """(items, extras): every item (its first location row) with its obsolete_details,
    operator_block_details and item_history rows, and the rows of its other locations. A missing
    required table, an unreadable table, a non-text value or a non-empty -wal sidecar is BLIND."""
    wal = db + "-wal"
    if os.path.isfile(wal) and os.path.getsize(wal) > 0:
        raise Blind("%s has a non-empty -wal sidecar; checkpoint it first" % db)
    # the path is quoted: `?` and `#` in a file name are not URI syntax (round 4, R4-9)
    con = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(db)), uri=True)
    try:
        tables = {r[0] for r in con.execute("select name from sqlite_master where type='table'")}
        missing = [t for t in REQUIRED_TABLES if t not in tables]
        if missing:
            raise Blind("required table(s) missing: " + ",".join(missing))
        con.row_factory = sqlite3.Row
        od_rows = [dict(r) for r in con.execute("select * from obsolete_details")]
        obd_rows = [dict(r) for r in con.execute("select * from operator_block_details")]
        hist_rows = [dict(r) for r in con.execute("select * from item_history order by id")]
        cur = con.execute("select * from items order by atm_id, current_location")
        names = [d[0] for d in cur.description]
        item_rows = [dict(r) for r in cur]
    finally:
        con.close()
    for table, rows in (("obsolete_details", od_rows), ("operator_block_details", obd_rows),
                        ("item_history", hist_rows), ("items", item_rows)):
        check_values(table, rows)
    od = {r["atm_id"]: r for r in od_rows}
    obd = {r["atm_id"]: r for r in obd_rows}
    hist = {}
    for h in hist_rows:
        hist.setdefault(h["atm_id"], []).append(h)
    items, extras = {}, {}
    for row in item_rows:
        i = row["atm_id"]
        r = make_row(row, od.get(i), obd.get(i), hist.get(i, ()), names)
        if i in items:  # a second location row is linted too (round 4, R4-6), never dropped
            extras.setdefault(i, []).append(r)
            continue
        items[i] = r
    return items, extras


def load_rendered(d):
    """id -> [(file, line)]: the lines of each item's section in Issues.md / Fixed.md and the summary
    rows whose id cell names it. Returns (map, files read)."""
    out, read = {}, []
    for fname in RENDERED_FILES:
        p = os.path.join(d, fname)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError) as e:
            raise Blind("rendered document unreadable: %s (%s)" % (fname, e))
        read.append(fname)
        if fname.endswith("_Summary.md"):
            for line in text.split("\n"):
                if not line.startswith("|"):
                    continue
                for cell in line.split("|"):
                    cm = RENDERED_ID_CELL.match(cell.strip())
                    if cm:
                        out.setdefault(cm.group(1), []).append((fname, line))
                        break
        else:
            cur = None
            for line in text.split("\n"):
                if line.startswith("## "):
                    hm = RENDERED_HEADING.match(line)
                    cur = hm.group(1) if hm else None
                if cur:
                    out.setdefault(cur, []).append((fname, line))
    if not read:
        raise Blind("no rendered document in %s" % d)
    return out, read


# ---- self-check -------------------------------------------------------------------------------------

def secret_needles():
    """(name, positive at the pattern's minimum, negative just below it); assembled from fragments so
    that this file never carries a credential-shaped literal."""
    a, q = "a", "Q"
    v8 = "Zq7" * 2 + "Zq"  # eight characters, neither a mask nor a reference
    return [
        ("aws-access-key-id", "AK" + "IA" + q * 16, "AK" + "IA" + q * 15),
        ("aws-secret-assign", "aws_secret_" + "access_key = " + a * 40, "aws_secret_" + "access_key = " + a * 39),
        ("github-token", "gh" + "p_" + a * 30, "gh" + "p_" + a * 29),
        ("github-fine-grained-pat", "github" + "_pat_" + a * 30, "github" + "_pat_" + a * 29),
        ("gitlab-pat", "gl" + "pat-" + a * 20, "gl" + "pat-" + a * 19),
        ("gitlab-other-token", "gl" + "rt-" + a * 20, "gl" + "rt-" + a * 19),
        ("gcp-api-key", "AI" + "za" + a * 35, "AI" + "za" + a * 34),
        ("private-key-block", "-----BEGIN " + "RSA PRIVATE" + " KEY-----", "-----BEGIN " + "RSA PUBLIC" + " KEY-----"),
        ("huggingface-token", "hf" + "_" + a * 30, "hf" + "_" + a * 29),
        ("jwt", "ey" + "J" + a * 8 + ".ey" + "J" + a * 8 + ".x", "ey" + "J" + a * 7 + ".ey" + "J" + a * 7 + ".x"),
        ("slack-token", "xo" + "xb-" + "1" * 10, "xo" + "xb-" + "1" * 9),
        ("openai-anthropic-key", "s" + "k-" + a * 32, "s" + "k-" + a * 31),
        ("url-userinfo-password", "https://u:" + "p" + "@h", "https://u:" + "$" + "P@h"),
        ("bearer-token", "Authorization: " + "Bearer " + a * 20, "Authorization: " + "Bearer " + a * 19),
        ("password-assign", "pass" + "word = '" + v8 + "'", "pass" + "word = '" + v8[:7] + "'"),
        ("password-assign-unquoted", "DB_PASS" + "WORD=" + v8, "DB_PASS" + "WORD=" + v8[:7]),
        ("password-colon-unquoted", "pass" + "word: " + v8, "pass" + "word: " + v8[:7]),
        ("secret-colon-unquoted", "tok" + "en: " + v8, "tok" + "en: " + "Zqzqzqzq"),
        ("password-assign-spaced", "pass" + "word = '" + "ab cd ef" + "'", "pass" + "word = '" + "ab cd e" + "'"),
        ("short-key-assign", "DB_PA" + "SS=" + v8, "DB_PA" + "SS=" + v8[:7]),
        ("password-flag-space", "--pass" + "word " + v8, "--pass" + "word " + v8[:7]),
        ("password-space", "DB_PASS" + "WORD " + v8, "DB_PASS" + "WORD " + v8[:7]),
        ("argument-pair", "define('DB_PASS" + "WORD', '" + v8 + "')", "define('DB_PASS" + "WORD', '" + v8[:7] + "')"),
        ("setter-call", "ds.setPass" + "word(\"" + v8 + "\")", "ds.setPass" + "word(\"" + v8[:7] + "\")"),
        ("short-flag-value", "mysql -uroot -p" + v8 + " db", "mysql -uroot -p" + v8[:7] + " db"),
        ("xml-attribute-pair", "<add key=\"Pass" + "word\" value=\"" + v8 + "\"/>", "<add key=\"Pass" + "word\" value=\"" + v8[:7] + "\"/>"),
        ("yaml-block-scalar", "pass" + "word: |\n  " + v8, "pass" + "word: |\n  " + v8[:7]),
        ("pgpass-line", "h:5432:db:u:" + v8, "h:5432:db:u:" + v8[:7]),
        ("password-netrc", "login u pass" + "word " + "abcdefgh", "login u pass" + "word " + "abcdefg"),
        ("xml-credential-element", "<pass" + "word>" + v8 + "</pass" + "word>", "<pass" + "word>" + v8[:7] + "</pass" + "word>"),
        ("basic-auth", "Authorization: " + "Basic " + a * 8, "Authorization: " + "Basic " + a * 7),
        ("stripe-key", "s" + "k_" + "live_" + a * 20, "s" + "k_" + "live_" + a * 19),
        ("npm-token", "np" + "m_" + a * 36, "np" + "m_" + a * 35),
        ("telegram-bot-token", "123456789" + ":AA" + a * 33, "123456789" + ":AA" + a * 32),
        ("password-space-quoted", "WITH PASS" + "WORD '" + v8 + "'", "WITH PASS" + "WORD '" + v8[:7] + "'"),
        ("authorization-header", "Authorization: " + "ApiKey " + v8, "Authorization: " + "ApiKey " + v8[:7]),
        ("table-row-pair", "| pass" + "word | " + v8 + " |", "| pass" + "word | " + v8[:7] + " |"),
        ("set-command", "set pass" + "word " + v8, "set pass" + "word " + v8[:7]),
    ]


NEEDLE_SHA = "ab" * 32
NEEDLE_FILES = {"docs/qa/needle_present/x.txt": NEEDLE_SHA, "docs/operator_decisions/needle_present.md": "cd" * 32}


class NeedleFS:
    def exists(self, rel):
        return rel in NEEDLE_FILES

    def sha256(self, rel):
        return NEEDLE_FILES[rel]


GOOD_DESC = (
    "**What:** a needle.\n\n**Affected scope / file-scope manifest:**\nx/needle_only.sh\n\n"
    "**Reproduction / context:**\nnone\n\n**Acceptance criteria:**\nnone\n\nParent / links: ZZ-1 (the needle umbrella, the parent of this one); see ZZ-4 for the needle range\n"
    "Duplicate check (section 11.4.214): DISTINCT\n"
    "Context: ZZ-8..ZZ-10 of another tracker; evidence docs/qa/needle_present/x.txt; see x.bundle (ephemeral: a scratch file)\n"
    "Foreign ids (another tracker): ZZ-8..ZZ-10\n"
    "**Reproduction:** reproduced-live — REPRODUCED"
)
GOOD_KW = {
    "atm_id": "ZZ-2", "title": "Needle good item", "status": "Queued", "current_location": "Issues", "type": "Task",
    "severity": "Low", "created_by": "AI", "representation": "section", "description": GOOD_DESC,
    "reproduction_state": "reproduced-live", "reproduction_surface": "host-only",
    "reproduction_evidence": "docs/qa/needle_present/x.txt", "reproduction_red_cmd": "bash x/needle_only.sh",
    "reproduction_env": "needle host; evidence sha256 " + NEEDLE_SHA, "reproduction_signature": "needle `signature`",
    "reproduction_updated_at": "2026-11-13T00:00:00Z", "reproduction_updated_by": "needle",
}


def fx(**kw):
    """A fixture row; body_md is the engine rendering unless given."""
    od, obd, hist = kw.pop("od", None), kw.pop("obd", None), kw.pop("hist", ())
    cols = {c: None for c in ITEM_COLUMNS}
    cols.update(kw)
    r = make_row(cols, od, obd, hist, ITEM_COLUMNS)
    if "body_md" not in kw:
        r["body_md"] = r["body"] = engine_body(r)
    return r


def var(**kw):
    return fx(**dict(GOOD_KW, **kw))


def raw_body(row, body):
    row = dict(row)
    row["body_md"] = row["body"] = body
    return row


def canon_needles():
    """(rule, positive, negative) for the canonical rules a fixture row reaches behind the extractors."""
    v = "Ne" + "ed1e" + "Zq9x"
    pw = "pass" + "word"
    spaced = "_".join(pw)
    return [
        ("canonical-key", spaced + "=" + v, spaced + "_policy=" + v),
        ("canonical-record", '{"key": "' + pw + '", "value": "' + v + '"}', '{"key": "' + pw + '", "value": "<redacted>"}'),
    ]


def selfcheck():
    """Control needles (section 11.4.201(7)(b)): every check must stay silent on the golden-good
    texts and fire on its golden-bad text; every secret pattern must fire on its positive needle and
    stay silent on its negative one; each scanned surface must carry a planted needle to a finding
    that names that surface. Returns a list of failed needle names."""
    umb = fx(atm_id="ZZ-1", title="Needle umbrella", description="umbrella", status="Queued", current_location="Issues", type="Task")
    rng = fx(atm_id="ZZ-4", title="Needle range holder", description="range holder", status="Queued", current_location="Issues", type="Task")
    good = var()
    allitems = {"ZZ-1": umb, "ZZ-2": good, "ZZ-4": rng}
    ex = NEEDLE_FILES.__contains__
    fs = NeedleFS()
    failed = []

    def run(row, items, rendered=None):
        return lint_items([row], items, "ZZ", True, "<needle>", ex, rendered, fs)

    d = GOOD_DESC
    od_dup = {"atm_id": "ZZ-2", "since": "2026-11-13", "reason": "duplicate-of", "superseding_item": "ZZ-1",
              "triple_check_evidence": "docs/qa/needle_present/x.txt"}
    close_rows = [{"id": 7, "atm_id": "ZZ-2", "event_type": "Obsolete", "by": "AI", "on_date": "2026-11-13",
                   "reason": "duplicate-of", "evidence_path": "docs/qa/needle_present/x.txt"}]
    reopen_rows = [{"id": 8, "atm_id": "ZZ-2", "event_type": "Reopened", "by": "AI", "on_date": "2026-11-13",
                    "reason": "design-reconsidered", "evidence_path": "docs/qa/needle_present/x.txt"}]
    dup_good = var(status="Obsolete", current_location="Fixed", od=od_dup, hist=close_rows,
                   description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1"))
    und_good = var(description=d.replace(": DISTINCT", ": UNDECIDED; candidate duplicates ZZ-1 and ZZ-4"))
    stale_good = var(status="Reopened", od=od_dup, hist=close_rows + reopen_rows,
                     description=d + "\nStale obsolete_details row (engine gap ZZ-4): kept by the engine")
    od_good = var(description=d.replace("docs/qa/needle_present/x.txt", "docs/operator_decisions/needle_present.md"),
                  reproduction_evidence="docs/operator_decisions/needle_present.md",
                  reproduction_env="needle host; evidence sha256 " + "cd" * 32)
    blocked_good = var(status="Operator-blocked", obd={"atm_id": "ZZ-2", "what": "needle block", "why_exhausted_alternatives": "w",
                                                     "unblock_condition": "[A] u", "who": "operator"})
    punct_good = var(description=d.replace("evidence docs/qa/needle_present/x.txt;", "evidence docs/qa/needle_present/x.txt. Also "
                                           "(docs/qa/needle_present/x.txt), docs/qa/needle_present/x.txt:"))
    distinct_link_good = fx(atm_id="ZZ-4", title="Needle range holder", status="Queued", current_location="Issues", type="Task",
                            description="range holder\nDuplicate check (section 11.4.214): DISTINCT (ZZ-1 is a different defect)")
    rendered_good = {"ZZ-2": [("Issues.md", "## ZZ-2 — Needle good item"), ("Issues_Summary.md", "| ZZ-2 | Task | needle |")]}
    # the end of a range keeps the clause it stands in (round 4: an endpos bound read `..` as a sentence end)
    range_mid = fx(atm_id="ZZ-3", title="Needle range middle", description="range middle", status="Queued",
                   current_location="Issues", type="Task")
    range_good = var(description=d + "\nthe needle umbrella to the needle range holder, ZZ-1..ZZ-4")
    for name, row, extra, rnd in (("golden-good", good, {}, None), ("golden-good-duplicate", dup_good, {}, None),
                                  ("golden-good-range-end-clause", range_good, {"ZZ-3": range_mid}, None),
                                  ("golden-good-undecided", und_good, {}, None), ("golden-good-stale-noted", stale_good, {}, None),
                                  ("golden-good-decision-path", od_good, {}, None), ("golden-good-blocked", blocked_good, {}, None),
                                  ("golden-good-trailing-punctuation", punct_good, {}, None),
                                  ("golden-good-head-distinct-link", dup_good, {"ZZ-4": distinct_link_good}, None),
                                  ("golden-good-rendered", good, {}, rendered_good)):
        got = run(row, dict(allitems, **dict({"ZZ-2": row}, **extra)), rnd)
        if got:
            failed.append("%s (%s)" % (name, ",".join(sorted({f[0] for f in got}))))
    gb = engine_body(good)
    head_umb = fx(atm_id="ZZ-1", title="Needle umbrella", description="umbrella; candidate duplicate ZZ-4, merge UNDECIDED",
                  status="Queued", current_location="Issues", type="Task")
    bad_cases = {
        "XREF-DANGLING": (var(description=d.replace("ZZ-1 (the needle umbrella, the parent of this one)", "ZZ-19")), {}),
        "XREF-DANGLING/range": (var(description=d.replace("Foreign ids (another tracker): ZZ-8..ZZ-10", "Foreign ids (another tracker): ZZ-8, ZZ-10")), {}),
        "XREF-DANGLING/range-interior-150": (var(description=d + "\nsee ZZ-4..ZZ-160 for the needle range", reproduction_signature="sig"), {}),
        "XREF-DANGLING/state-column": (var(reproduction_red_cmd="bash x/needle_only.sh ZZ-77"), {}),
        "XREF-LABEL": (var(description=d.replace("(the needle umbrella, the parent of this one)", "(GitHub issues sync)")), {}),
        "XREF-LABEL/one-shared-word": (var(description=d.replace("(the needle umbrella, the parent of this one)", "(umbrella of github runners)")), {}),
        "XREF-UNLABELLED": (var(description=d.replace("see ZZ-4 for the needle range", "related ZZ-4, not a parent")), {}),
        "FOREIGN-STALE": (var(description=d.replace("tracker): ZZ-8..ZZ-10", "tracker): ZZ-8..ZZ-10, ZZ-7")), {}),
        "STATE-PROSE": (var(description=d + "\nReproduction state: UNREPRODUCED."), {}),
        "STATE-PROSE/structured": (var(reproduction_state=None), {}),
        "STATE-PROSE/structured-investigation": (var(description=d + "\n**Investigation:** in-progress"), {}),
        "STATE-EVIDENCE": (var(reproduction_env="needle host"), {}),
        "STATE-EVIDENCE/sha-mismatch": (var(reproduction_env="needle host; evidence sha256 " + "ef" * 32), {}),
        "STATE-EVIDENCE/missing-file": (var(reproduction_evidence="docs/qa/needle_absent/x.txt"), {}),
        "STATE-EVIDENCE/investigation": (var(investigation_state="root-cause-found-with-evidence", investigation_root_cause="needle cause",
                                             investigation_evidence="docs/qa/needle_present/x.txt"), {}),
        "STATE-EVIDENCE/blocker": (var(reproduction_state="blocked-no-device-with-recorded-blocker",
                                       description=d.replace("**Reproduction:** reproduced-live — REPRODUCED", "")), {}),
        "SECTIONS": (var(description=d.replace("**Acceptance criteria:**", "Acceptance:")), {}),
        "BODY-SYNC": (raw_body(good, "something else"), {}),
        "BODY-SYNC/empty": (raw_body(good, ""), {}),
        "BODY-SYNC/header-line-separator": (raw_body(good, gb.replace("**Status:** Queued\n", "**Status:** Queued x\n")), {}),
        "BODY-SYNC/extra-paragraph": (raw_body(good, gb + "Update: already fixed; no work owed.\n"), {}),
        "BODY-SYNC/heading-id": (raw_body(good, gb.replace("## ZZ-2 — ", "## ZZ-3 — ")), {}),
        "BODY-SYNC/status-second": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Status:** Fixed\n")), {}),
        "BODY-SYNC/status-value": (raw_body(good, gb.replace("**Status:** Queued", "**Status:** Queued later")), {}),
        "BODY-SYNC/type": (raw_body(good, gb.replace("**Type:** Task", "**Type:** Bug")), {}),
        "BODY-SYNC/severity": (raw_body(good, gb.replace("**Severity:** Low", "**Severity:** Critical")), {}),
        "BODY-SYNC/created-by": (raw_body(good, gb.replace("**Created-By:** AI", "**Created-By:** User")), {}),
        "BODY-SYNC/assigned-to-extra": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Assigned-To:** someone\n")), {}),
        "BODY-SYNC/severity-missing": (raw_body(good, gb.replace("**Severity:** Low\n", "")), {}),
        "BODY-SYNC/reproduction-detail": (raw_body(good, gb.replace("needle `signature`", "other `signature`")), {}),
        "BODY-SYNC/investigation-extra": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Investigation:** in-progress\n")), {}),
        "BODY-SYNC/obsolete-missing": (raw_body(dup_good, engine_body(dup_good).replace(obsolete_line(od_dup) + "\n", "")), {}),
        "BODY-SYNC/obsolete-content": (raw_body(dup_good, engine_body(dup_good).replace("Superseding-item: ZZ-1", "Superseding-item: ZZ-4")), {}),
        "BODY-SYNC/obsolete-on-open": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n" + obsolete_line(od_dup) + "\n")), {}),
        "BODY-SYNC/evidence": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Evidence:** docs/qa/needle_present/x.txt\n")), {}),
        "BODY-SYNC/reopened-without-row": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n" + reopen_line(reopen_rows[0]) + "\n")), {}),
        "BODY-SYNC/block-without-row": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Operator-Block-Details:** WHAT: x\n")), {}),
        "BODY-SYNC/unknown-key": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Priority:** P1\n")), {}),
        "SECRET": (var(description=d + "\nkey AK" + "IA" + "ABCDEFGHIJKLMNOP"), {}),
        "SECRET/state-column": (var(reproduction_env="needle host; evidence sha256 " + NEEDLE_SHA + "; key AK" + "IA" + "ABCDEFGHIJKLMNOP"), {}),
        "EPHEMERAL": (var(description=d + "\nsee review_x_r1.md"), {}),
        "EPHEMERAL/note-needs-parenthesis": (var(description=d + "\nan ephemeral copy at /tmp/needle/x"), {}),
        "EPHEMERAL/mktemp-default": (var(description=d + "\nlog at /tmp/tmp." + "k3Jx9QvT2a" + "/out.txt"), {}),
        "EPHEMERAL/mktemp-default-lowercase": (var(description=d + "\nwork dir tmp." + "qwertyuiop" + " kept"), {}),
        "EPHEMERAL/lowercase-dir": (var(description=d + "\nsee scratch." + "zobh" + "/c"), {}),
        "EPHEMERAL/4-char": (var(description=d + "\nsee scratch." + "Ab3d" + " for it"), {}),
        "EPHEMERAL/home-path": (var(description=d + "\nfile /ho" + "me/needleuser/x.txt"), {}),
        "EPHEMERAL/home-dotdir": (var(description=d + "\nfile ~/.needle" + "tool/x.txt"), {}),
        "EPHEMERAL/session-store": (var(description=d + "\nfile .claude-needle/" + "projects/abc/x.jsonl"), {}),
        "EPHEMERAL/state-column": (var(reproduction_red_cmd="bash /tmp/" + "needle/x.sh"), {}),
        "CONTROL-CHAR/title": (var(title="Needle good item"), {}),
        "CONTROL-CHAR/nul": (var(description=d + "\nnul\x00here"), {}),
        "CONTROL-CHAR/title-tab": (var(title="Needle\tgood item"), {}),
        "CONTROL-CHAR/bidi": (var(description=d + "\nbidi\u202ehere"), {}),
        "XREF-DANGLING/non-ascii-digits": (var(description=d + "\nsee ZZ-\uff13"), {}),
        "DUP-CHECK": (var(description=d.replace(": DISTINCT", ": PROBABLY")), {}),
        "DUP-SAME-OPEN": (var(description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1")), {}),
        "DUP-SAME-OPEN/wrong-head": (var(status="Obsolete", current_location="Fixed", od=dict(od_dup, superseding_item="ZZ-4"),
                                         hist=close_rows, description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1")), {}),
        "DUP-SAME-OPEN/head-is-first-id": (var(status="Obsolete", current_location="Fixed", od=dict(od_dup, superseding_item="ZZ-4"),
                                               hist=close_rows, description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1 (see also ZZ-4)")), {}),
        "DUP-HEAD": (dup_good, {"ZZ-1": head_umb}),
        "DUP-HEAD/head-closed": (dup_good, {"ZZ-1": fx(atm_id="ZZ-1", title="Needle umbrella", description="umbrella",
                                                      status="Fixed", current_location="Fixed", type="Task")}),
        "DUP-HEAD/lowercase": (dup_good, {"ZZ-1": fx(atm_id="ZZ-1", title="Needle umbrella", status="Queued", current_location="Issues", type="Task",
                                                    description="umbrella; candidate ZZ-4, merge undecided")}),
        "DUP-HEAD/wording": (dup_good, {"ZZ-1": fx(atm_id="ZZ-1", title="Needle umbrella", status="Queued", current_location="Issues", type="Task",
                                                  description="umbrella; ZZ-4 is a possible second head, open question")}),
        "DUP-HEAD/reverse": (dup_good, {"ZZ-4": fx(atm_id="ZZ-4", title="Needle range holder", status="Queued", current_location="Issues", type="Task",
                                                  description="range holder\nDuplicate check (section 11.4.214): undecided; candidate ZZ-1")}),
        "DUP-HEAD/stale-row": (dup_good, {"ZZ-4": fx(atm_id="ZZ-4", title="Needle range holder", status="Reopened", current_location="Issues", type="Task",
                                                    description="range holder", od=dict(od_dup, atm_id="ZZ-4"))}),
        "DUP-UNDECIDED": (var(description=d.replace(": DISTINCT", ": UNDECIDED")), {}),
        "DUP-STATUS": (var(status="Obsolete", current_location="Fixed", od=od_dup, hist=close_rows,
                           description=d.replace(": DISTINCT", ": UNDECIDED; candidate ZZ-1")), {}),
        "OBSOLETE-STALE": (var(status="Reopened", od=od_dup, hist=close_rows + reopen_rows), {}),
        "SHARED-PATH": (good, {"ZZ-3": fx(atm_id="ZZ-3", title="other open", description="touches x/needle_only.sh",
                                         status="Queued", current_location="Issues", type="Task")}),
        "PATH-MISSING": (var(description=d.replace("needle_present", "needle_absent_zz9")), {}),
        "PATH-MISSING/decisions": (var(description=od_good["description"].replace("needle_present.md", "needle_absent.md"),
                                       reproduction_evidence="docs/operator_decisions/needle_present.md",
                                       reproduction_env="needle host; evidence sha256 " + "cd" * 32), {}),
    }
    # Each golden-bad case names the check it proves: a finding of the case's code is not enough,
    # because a second check under the same code can catch the same text (round 4: the line-separator
    # case was also caught by the Status-value compare, so switching the separator check off left the
    # needle silent). The finding must carry the named check's own message text.
    check_text = {
        "XREF-DANGLING": "ZZ-19", "XREF-DANGLING/range": "ZZ-9", "XREF-DANGLING/range-interior-150": "ZZ-100",
        "XREF-DANGLING/state-column": "ZZ-77", "XREF-LABEL": "(GitHub issues sync) vs title",
        "XREF-LABEL/one-shared-word": "(umbrella of github runners) vs title",
        "XREF-UNLABELLED": "without a label in a clause", "FOREIGN-STALE": "ZZ-7",
        "STATE-PROSE": "prose says UNREPRODUCED", "STATE-PROSE/structured": "structured line says reproduced-live",
        "STATE-PROSE/structured-investigation": "structured line says in-progress",
        "STATE-EVIDENCE": "reproduction_state reproduced-live carries no evidence sha256",
        "STATE-EVIDENCE/sha-mismatch": "sha256 differs from the file", "STATE-EVIDENCE/missing-file": "does not exist",
        "STATE-EVIDENCE/investigation": "investigation_state root-cause-found-with-evidence carries no evidence",
        "STATE-EVIDENCE/blocker": "without a reproduction_blocker", "SECTIONS": "missing: Acceptance criteria",
        "BODY-SYNC": "description is not contained in body_md", "BODY-SYNC/empty": "body_md is empty",
        "BODY-SYNC/header-line-separator": "line separator other than a newline",
        "BODY-SYNC/extra-paragraph": "text after the description", "BODY-SYNC/heading-id": "heading disagrees",
        "BODY-SYNC/status-second": "key Status is written twice",
        "BODY-SYNC/status-value": "Status line differs from its source", "BODY-SYNC/type": "Type line differs",
        "BODY-SYNC/severity": "Severity line differs", "BODY-SYNC/created-by": "Created-By line differs",
        "BODY-SYNC/assigned-to-extra": "has an Assigned-To line while its source gives none",
        "BODY-SYNC/severity-missing": "lacks the Severity line", "BODY-SYNC/reproduction-detail": "Reproduction line differs",
        "BODY-SYNC/investigation-extra": "has an Investigation line while",
        "BODY-SYNC/obsolete-missing": "lacks the Obsolete-Details line",
        "BODY-SYNC/obsolete-content": "Obsolete-Details line differs",
        "BODY-SYNC/obsolete-on-open": "has an Obsolete-Details line while",
        "BODY-SYNC/evidence": "Evidence line names no closure evidence",
        "BODY-SYNC/reopened-without-row": "no Reopened history row",
        "BODY-SYNC/block-without-row": "no operator_block_details row", "BODY-SYNC/unknown-key": "is not an engine key",
        "SECRET": "aws-access-key-id on description", "SECRET/state-column": "items.reproduction_env",
        "EPHEMERAL": "bare-review-file:", "EPHEMERAL/note-needs-parenthesis": "tmp-path: /tmp/needle/x on",
        "EPHEMERAL/mktemp-default": "mktemp-default: tmp.k3Jx9QvT2a",
        "EPHEMERAL/mktemp-default-lowercase": "mktemp-default: tmp.qwertyuiop",
        "EPHEMERAL/lowercase-dir": "mktemp-dir: scratch.zobh", "EPHEMERAL/4-char": "mktemp-dir: scratch.Ab3d",
        "EPHEMERAL/home-path": "home-path: /home/needleuser/", "EPHEMERAL/home-dotdir": "home-path: ~/.needletool/",
        "EPHEMERAL/session-store": "session-store:", "EPHEMERAL/state-column": "items.reproduction_red_cmd",
        "CONTROL-CHAR/title": "U+2028 on title", "CONTROL-CHAR/nul": "U+0000",
        "CONTROL-CHAR/title-tab": "newline or tab in the title", "DUP-CHECK": "not in the closed set",
        "CONTROL-CHAR/bidi": "U+202E", "XREF-DANGLING/non-ascii-digits": "(non-ASCII digits)",
        "DUP-SAME-OPEN": "but not Obsolete duplicate-of ZZ-1", "DUP-SAME-OPEN/wrong-head": "but not Obsolete duplicate-of ZZ-1",
        "DUP-SAME-OPEN/head-is-first-id": "but not Obsolete duplicate-of ZZ-1",
        "DUP-HEAD": "ZZ-1 names ZZ-4 as a duplicate", "DUP-HEAD/head-closed": "is not an open head",
        "DUP-HEAD/lowercase": "ZZ-1 names ZZ-4 as a duplicate", "DUP-HEAD/wording": "ZZ-1 names ZZ-4 as a duplicate",
        "DUP-HEAD/reverse": "ZZ-4 names ZZ-1 as a duplicate", "DUP-HEAD/stale-row": "is open with an obsolete_details row",
        "DUP-UNDECIDED": "names no candidate id", "DUP-STATUS": "but the verdict is UNDECIDED",
        "OBSOLETE-STALE": "on a Reopened item", "SHARED-PATH": "also named by open ZZ-3",
        "PATH-MISSING": "needle_absent_zz9", "PATH-MISSING/decisions": "needle_absent.md",
    }
    if set(check_text) != set(bad_cases):  # a case without its check text, or a text without a case
        failed.append("golden-bad/check-text-map")
    for code, (row, extra) in bad_cases.items():
        items = dict(allitems, **{"ZZ-2": row})
        items.update(extra)
        want = check_text.get(code, "\0")
        if not any(f[0] == code.split("/")[0] and want in f[2] for f in run(row, items)):
            failed.append(code)
    # one needle per surface: a planted credential shape, ephemeral path and control character must be
    # reported with that surface named
    key = "AK" + "IA" + "ABCDEFGHIJKLMNOP"
    planted = {
        "title": lambda s: var(title="Needle good item " + s),
        "description": lambda s: var(description=d + "\n" + s),
        "body_md": lambda s: raw_body(good, gb.replace("\n\n" + d, "\n\n" + d + "\n" + s, 1)),
        "items.reproduction_signature": lambda s: var(reproduction_signature="needle " + s),
        "items.closure_criteria": lambda s: var(closure_criteria=s),
        "obsolete_details.triple_check_evidence": lambda s: var(status="Reopened", od=dict(od_dup, triple_check_evidence=s),
                                                                description=d + "\nStale obsolete_details row (engine gap ZZ-4): kept"),
        "operator_block_details.why_exhausted_alternatives": lambda s: var(
            status="Operator-blocked", obd={"atm_id": "ZZ-2", "what": "w", "why_exhausted_alternatives": s, "unblock_condition": "u", "who": "o"}),
        "item_history[9].reason": lambda s: var(hist=[{"id": 9, "atm_id": "ZZ-2", "event_type": "Updated", "by": "AI", "reason": s}]),
    }
    for surface, make in planted.items():
        for code, s in (("SECRET", key), ("EPHEMERAL", "/tmp/" + "needle/x"), ("CONTROL-CHAR", "x\x07y")):
            row = make(s)
            got = [f for f in run(row, dict(allitems, **{"ZZ-2": row})) if f[0] == code]
            if not any(surface in f[2].split(" on ", 1)[-1].split(",") for f in got):
                failed.append("surface/%s/%s" % (code, surface))
    for code, s in (("SECRET", key), ("EPHEMERAL", "/tmp/" + "needle/x"), ("CONTROL-CHAR", "x\x07y")):
        rnd = {"ZZ-2": [("Issues.md", "## ZZ-2 — Needle good item"), ("Issues_Summary.md", "| ZZ-2 | " + s + " |")]}
        got = [f for f in run(good, allitems, rnd) if f[0] == code]
        if not any("rendered:Issues_Summary.md" in f[2] for f in got):
            failed.append("surface/%s/rendered" % code)
    for name, pos, neg in secret_needles():
        wrap = ("x\n", "\ny") if name in LINE_RULES else ("x ", " y")  # a whole-line shape needs its own line
        got_pos = [n for n, _ in secret_hits(wrap[0] + pos + wrap[1])]
        got_neg = [n for n, _ in secret_hits(wrap[0] + neg + wrap[1])]
        if name not in SECRET_RULE_NAMES or name not in got_pos or name in got_neg:
            failed.append("SECRET/" + name)
    if sorted(n for n, _, _ in secret_needles()) != sorted(SECRET_RULE_NAMES):
        failed.append("SECRET/needle-count")
    # round 11: the canonical rule set behind the extractors, with a positive no extractor reads and a
    # negative of the same spelling
    for name, pos, neg in canon_needles():
        got_pos = [n for n, _ in secret_hits(pos)]
        got_neg = [n for n, _ in secret_hits(neg)]
        if name not in got_pos or got_neg:
            failed.append("SECRET/" + name)
    return failed


# ---- main -------------------------------------------------------------------------------------------

def main(argv):
    ap = argparse.ArgumentParser(prog="intake_lint.py", add_help=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--origin", action="append", default=[])
    ap.add_argument("--ids", action="append", default=[])
    ap.add_argument("--prefix")
    ap.add_argument("--require-dup-check", action="store_true")
    ap.add_argument("--embeddings", action="store_true")
    ap.add_argument("--no-selfcheck", action="store_true")
    ap.add_argument("--skip-check", action="append", default=[])
    ap.add_argument("--repo-root")
    ap.add_argument("--rendered")
    ap.add_argument("--no-rendered", action="store_true")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    if not a.origin and not a.ids:
        print("intake_lint: give --origin or --ids", file=sys.stderr)
        return 2
    skip = set()
    for lst in a.skip_check:
        skip |= {x.strip() for x in lst.split(",") if x.strip()}
    unknown = sorted(skip - CODES)
    if unknown:
        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)
        return 2
    if a.repo_root and not os.path.isdir(a.repo_root):
        print("intake_lint: --repo-root is not a directory: %s" % a.repo_root, file=sys.stderr)
        return 2
    if a.rendered and a.no_rendered:
        print("intake_lint: --rendered and --no-rendered exclude each other", file=sys.stderr)
        return 2
    rendered_dir = None
    if not a.no_rendered:
        rendered_dir = a.rendered or (os.path.join(a.repo_root, "docs") if a.repo_root else None)
    if not a.no_selfcheck:
        bad = selfcheck()
        if bad:
            print("BLIND: control needle failed: " + ",".join(bad), file=sys.stderr)
            return 3
    if not os.path.isfile(a.db):
        print("BLIND: database not found: %s" % a.db, file=sys.stderr)
        return 3
    want = set()
    for lst in a.ids:
        want |= {x.strip() for x in lst.split(",") if x.strip()}
    # a crash is never a result: any unexpected error is BLIND (exit 3), never a traceback read as a
    # finding (exit 1) or a silent pass; the selection runs inside this block too (M-3)
    rows, raw, files = [], [], []
    try:
        items, extras = load(a.db)
        if not items:
            raise Blind("database holds no items")
        counts = {}
        for i in items:
            p = i.rsplit("-", 1)[0]
            counts[p] = counts.get(p, 0) + 1
        prefix = a.prefix or max(sorted(counts), key=lambda k: counts[k])
        if not any(id_re(prefix).fullmatch(i) for i in items):
            raise Blind("no item in the database carries the prefix %s: the id checks could not see" % prefix)
        missing = sorted(want - set(items))
        if missing:
            raise Blind("selected ids not in the database: " + ",".join(missing))
        sel = [r for i, r in sorted(items.items()) if i in want or any(o in r["description"] for o in a.origin)]
        if not sel:
            raise Blind("the selection is empty")
        rendered = {}
        if rendered_dir:
            rendered, files = load_rendered(rendered_dir)
            unseen = sorted(r["id"] for r in sel if r["id"] not in rendered)
            if unseen:
                raise Blind("selected item(s) absent from every rendered document: " + ",".join(unseen[:5]))
        if a.embeddings:
            rows = embeddings(sel, items, prefix)
        else:
            raw = lint_items(sel, items, prefix, a.require_dup_check, a.repo_root, rendered=rendered)
            for r in sel:
                for e in extras.get(r["id"], ()):
                    for f in lint_items([e], dict(items, **{r["id"]: e}), prefix, a.require_dup_check, a.repo_root,
                                        rendered=rendered):
                        if f not in raw:
                            raw.append((f[0], f[1], "%s [%s row]" % (f[2], e["location"])))
    except Blind as e:
        print("BLIND: %s" % e, file=sys.stderr)
        return 3
    except Exception as e:  # noqa: BLE001 -- the point is to catch every class of crash
        print("BLIND: the lint crashed (%s: %s): no verdict" % (type(e).__name__, str(e)[:200]), file=sys.stderr)
        return 3
    if a.embeddings:
        print("item\tembedded_id\tnamespace\tcount")
        for row in rows:
            print("%s\t%s\t%s\t%d" % row)
        return 0
    findings = []
    for f in raw:
        if f[0] not in skip and f not in findings:
            findings.append(f)
    for code, iid, detail in findings:
        print("FINDING %s %s %s" % (code, iid, detail))
    print("RESULT: %s selected=%d findings=%d prefix=%s rendered=%s" % (
        "PASS" if not findings else "FAIL", len(sel), len(findings), prefix, ",".join(files) or "none"))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
