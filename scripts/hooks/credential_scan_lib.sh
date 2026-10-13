# shellcheck shell=bash
# =============================================================================
# credential_scan_lib.sh — project-AGNOSTIC shared credential-leak scan library
# (§11.4.10 credentials-handling + §11.4.75 mechanical enforcement Layer 1 +
#  §11.4.201 guards-assert-the-real-condition — carrier-strips prevent the
#  FALSE-POSITIVE refusal that is itself a FAIL-bluff).
#
# Purpose:
#   Provides the two credential detectors + the binary-skip helper + a
#   convenience whole-file scanner, so any consuming project's pre-commit hook
#   can INHERIT the detectors BY REFERENCE (§11.4.28 / §11.4.177) instead of
#   copying them. Detector-1 = keyword-anchored / known-token-format value
#   patterns WITH two §11.4.201 carrier-strips — #7 (value-starts-with a
#   $ / < / % / { sigil, baked into the pattern) and #8 (placeholder-value
#   allowlist + base64-image data-URI, applied by _helix_cred_detector1_real_hit)
#   so a `PASSWORD={CHANGE_ME}` template line, a `SECRET={…must_not_leak}` fixture
#   marker, and a `data:image/png;base64,…` blob are NOT flagged while a genuine
#   `password: {hunter2hunter2}` / `AKIA…` leak still is. Detector-2 =
#   email+password-shape adjacency heuristic WITH four
#   §11.4.201 carrier-strips (git SSH remotes, systemd `@N.service` units,
#   Java/Android object references `@pkg.CamelCaseClass`, Java `$$`-synthetic
#   tokens) that assert the REAL condition — a genuine `user@company.com : <pw>`
#   leak is UNTOUCHED, so both a false-positive refusal AND a false-negative
#   pass are mechanically prevented.
#
#   ZERO project literals: no credential SoT path, no project / vendor name,
#   no device serial, no region endpoint. The consumer supplies the allowlist
#   filter + the REFUSED message; this library supplies only the detectors.
#
# Usage:
#   . "$REPO_ROOT/constitution/scripts/hooks/credential_scan_lib.sh"
#   # Then either use the exported patterns directly against STAGED content:
#   if git show ":$f" | grep -Eiq "$HELIX_CRED_VALUE_PATTERN"; then hit=1; fi
#   if ! helix_cred_is_binary_skip "$f"; then
#     if awk "$HELIX_CRED_ADJACENCY_AWK" < <(git show ":$f"); then hit=1; fi
#   fi
#   # ...or scan a file on disk end-to-end:
#   helix_cred_scan_file "$path" && echo "credential found" || echo "clean"
#
# Inputs:
#   Sourced into a bash shell. helix_cred_is_binary_skip / helix_cred_scan_file
#   take a single path argument.
#
# Outputs / return codes:
#   HELIX_CRED_VALUE_PATTERN     — ERE for detector-1 (grep -Ei).
#   HELIX_CRED_ADJACENCY_AWK     — awk program for detector-2. Exit 0 = an
#                                  offending line found, exit 1 = clean.
#   helix_cred_is_binary_skip P  — returns 0 if P's extension is a binary blob
#                                  that MUST NOT be text-scanned by detector-2,
#                                  else 1.
#   helix_cred_scan_file P        — returns 0 if a credential is found, 1 if
#                                  clean. Runs detector-1 then (if P is not a
#                                  binary-skip extension) detector-2.
#
# Side-effects:
#   None. Sourcing sets read-only-by-convention pattern variables + defines
#   two functions. It does NOT change shell options (safe to source from any
#   hook regardless of its `set` flags).
#
# Dependencies:
#   bash, grep (ERE, -i, -q), awk.
#
# Cross-references:
#   Self-validating fixtures:  constitution/scripts/hooks/test_credential_scan_lib.sh
#   Reference consumer:        <project>/scripts/git_hooks/pre-commit
#   Constitution:              §11.4.10 / §11.4.10.A / §11.4.75 / §11.4.201 /
#                              §11.4.28 / §11.4.177 / §11.4.107(10) / §1.1.
# =============================================================================

# --- Detector 1: keyword-anchored value / known-token-format patterns --------
# Conservative set covering common API-token / key / secret / password
# assignment forms. Used with `grep -Ei`.
#
# §11.4.201 carrier-strip #9 (sk- LEFT TOKEN BOUNDARY). The OpenAI `sk-` prefix is
# only TWO letters + a hyphen, so an unanchored `sk-[0-9A-Za-z]{20,}` also matches
# the TAIL of any identifier ending in "sk" that is followed by '-' and 20+
# alphanumerics. Forensic FP: an Android `pm path` capture
# ".../com.example.mediakiosk-<install-token>==/base.apk" — the "sk" is the tail
# of the package name "mediakio[sk]" and the base64url install-token supplies the
# run (kiosk / disk / task / desk all trip it). The left boundary
# `(^|[^0-9A-Za-z])` asserts the REAL condition — a genuine key in the observed
# leak shapes stands at a token boundary (line start, whitespace, '=', quote, or
# '_', none of which are [0-9A-Za-z]). Coverage of that boundary CLASS is proven by
# golden-good (m) + the golden-bad (8)/(8a)/(8b)/(8c) class-spread guard in
# test_credential_scan_lib.sh, whose fixtures are PROGRAMMATICALLY enumerated over
# every printable-ASCII non-alphanumeric byte (plus TAB, a control byte and a
# high-byte form) so a narrowing of the class cannot pass them.
# HONEST BOUNDARY (§11.4.6 / §11.4.194(2)) — this is a TRADE, not a free win, and
# the earlier "cannot weaken real-secret detection" claim was FALSE. MEASURED
# counterexample (2026-08-03): a genuine key immediately preceded by an ANSI-SGR
# escape (`ESC[32m` + `sk-…`) has 'm' — an ALPHANUMERIC — as its preceding byte, so
# the unanchored pre-fix pattern CAUGHT it while this boundary MISSES it. The class
# is LIVE in this tree, not hypothetical: 14 tracked files under docs/ carry ESC
# bytes (e.g. docs/CONTINUATION_data/phase38*.txt), so an ANSI-coloured capture is a
# real carrier shape. The trade is still the right one — GNU `\b` MISSES the very
# same case (measured), and the false positive this removed was a proven
# §11.4.201(1) FAIL-bluff that refused real commits — but the residual
# ANSI/control-prefix gap is STATED here and TRACKED as ATM-989 in the
# workable-items SSoT (§11.4.93 / §11.4.197 — the follow-up carries the RED-first
# fixture + the both-directions §11.4.201 acceptance criteria), never silently
# claimed absent.
# PORTABILITY (§11.4.201(7)(c) — the path is part of the instrument): the boundary
# is written in POSIX ERE, NOT `\b`. `\b` is a GNU/PCRE extension that BSD/macOS
# `grep -E` does not honour, where it would silently match nothing and turn a real
# `sk-` leak into a FALSE NEGATIVE (a §11.4 PASS-bluff). The `(^|[^0-9A-Za-z])`
# form is portable ERE and behaves identically on every grep. It CONSUMES the
# preceding character, which is harmless: the extracted match is only tested
# against the `^`-anchored placeholder carrier (#8a), which an `sk-` token never
# matches either way.
# --- Detector 1 alternative #27: PLURAL credential keyword, ASSIGNMENT only ---
# §11.4.201(2) FALSE-NEGATIVE cure, MEASURED 2026-09-08 (HXC-352). Every keyword
# in the alternation above is SINGULAR, so `API_KEYS=<v>`, `PASSWORDS=<v>`,
# `SECRETS=<v>`, `ACCESS_TOKENS=<v>`, `CLIENT_SECRETS=<v>`, `AUTH_TOKENS=<v>` and
# `PASSWDS=<v>` all read CLEAN while the singular `API_KEY=<v>` is caught. A
# scanner that names `password` and misses `passwords` reports clean and the leak
# ships — the §11.4.201 false-negative direction.
#
# THE NARROWING IS LOAD-BEARING, AND IT IS MEASURED. The obvious repair —
# appending `s?` to the keyword group of the generic `[[:space:]]*[:=]`
# alternative — was BUILT and REFUTED against the 644-file tracked corpus: it
# opens 11 NEW false-positive refusals (141 -> 152 flagged files) because a PLURAL
# keyword before a COLON is how code names a COLLECTION of keys, not a secret
# (`APIKeys: map[string]string{`, `Secrets: HashiCorp …`). Trading false negatives
# for false-positive refusals is the §11.4.201(1) FAIL-bluff, not a fix.
# What ships is ASSIGNMENT-ONLY: plural keyword + `=`, space-padding permitted,
# COLON NOT. Corpus 141 -> 141: zero new false positives, zero lost catches.
# The space-padded `=` was itself the measured choice — the tighter `s=` (no
# padding) missed `PASSWORDS = <secret>` and `passwords = "<secret>"`; the padded
# form catches both and cost 2 corpus false positives, BOTH of them
# `apiKeys = &APIKeys{}` Go composite literals, cured by carrier-strip #21 below.
# The elvis/or-fallback alternative above likewise admits the plural keyword.
# Evidence: docs/qa/hxc352_plural_credential_pattern_20260908T201833Z/
# remediation_20260908T204420Z/ (7d_corpus_delta_matrix.txt carries every count
# quoted here; 7b_falsification_matrix.log carries the per-mutation proof)..
# Golden fixtures + falsifying mutations: case (26) in test_credential_scan_lib.sh.
#
# WHY WIDENING THE CARRIER-STRIPS WITH `s?` IS SAFE — BY SYMMETRY. It is NOT
# because "a strip can only remove a false positive": that claim is FALSE in
# general, since a strip removes a detector HIT and, if the hit was a TRUE
# positive, manufactures a false NEGATIVE. The real argument is structural: every
# widened carrier is `^(<keyword>)s?<separator>…`, so the `s?` can consume only an
# `s` standing between the keyword and the separator, and the ONLY extracts that
# carry such an `s` are the ones the plural alternative itself produces. The
# widened strip therefore fires on `<kw>s=<v>` exactly when the un-widened strip
# fired on `<kw>=<v>` — the plural masking surface EQUALS the pre-existing
# singular one, adding no new class. Probed 2026-09-08; no counter-example could
# be constructed.
#
# HONEST RESIDUALS (§11.4.6 — stated, never silently omitted):
#   (1) COLON config style (`api_keys: <secret>` in YAML) is NOT caught; catching
#       it is exactly what produced the 11 false positives above.
#   (2) `SECRET_KEY=<v>`, `DJANGO_SECRET_KEY=<v>` and `SECRET_KEYS=<v>` are NOT
#       caught, BEFORE and AFTER this change alike: `secret` must be followed
#       DIRECTLY by a separator, so an intervening `_KEY` defeats the keyword.
#       A PRE-EXISTING gap of the same defect class, NOT introduced here and NOT
#       closed here; it is a separate work item, never claimed fixed.
#   (3) one standing corpus false positive: a spec file whose prose quotes an
#       `APIKeys=` fixture value. It is genuinely credential-shaped; adding that
#       value to the placeholder vocabulary would be over-fitting, so it is
#       recorded rather than hidden. Consequence, stated precisely: any consumer
#       scanning that file treats it as a hit — the §11.4.268 evidence-stream
#       redactor would REDACT a captured stream containing it, and a commit seam
#       wired to this library (none in this checkout) would REFUSE the commit —
#       until the fixture value is made placeholder-shaped.
HELIX_CRED_VALUE_PATTERN='(AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36}|gho_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{22,}|xox[baprs]-[0-9A-Za-z-]{10,}|(^|[^0-9A-Za-z])sk-[0-9A-Za-z]{20,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)s?[[:space:]]*[:=].{0,80}(\?:|\|\|)[[:space:]]*["'"'"'][^"'"'"']{8,}["'"'"']|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*["'"'"']?[^[:space:]"'"'"'$<%{][^[:space:]"'"'"']{7,}|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)s[[:space:]]*=[[:space:]]*["'"'"']?[^[:space:]"'"'"'$<%{][^[:space:]"'"'"']{7,})'

# --- Detector 1 carrier-strip #8: placeholder-value + base64-image data-URI ---
# §11.4.201 carrier-strip #8a (placeholder-value allowlist). A recognised secret
# KEYWORD whose VALUE is a config-template placeholder / test-fixture marker
# (CHANGE_ME / CHANGEME / PLACEHOLDER / EXAMPLE / DUMMY / REDACTED / TODO / TBD /
# FIXME / xxx+ / your[_-]... / ...must_not_leak...) is a template or fixture
# token, NEVER a real secret. (Values that start with $ / < / % / { are ALREADY
# excluded by carrier-strip #7 in HELIX_CRED_VALUE_PATTERN, so <xliff…> / $VAR /
# %1$s never reach detector-1 — this strip covers the remaining literal
# placeholders that DO start with a normal character.) A real secret is NEVER a
# literal placeholder token, so the strip is TIGHT — it cannot weaken real-secret
# detection: a value that is anything OTHER than a whole placeholder token (e.g.
# hunter2hunter2, AKIA…, xxxsecret1) survives and is still flagged. Applied by
# _helix_cred_detector1_real_hit, which drops any detector-1 match whose whole
# "keyword<sep>value" reads as keyword + placeholder-value. Proven by golden-good
# scenarios (i)/(j) + every golden-bad in test_credential_scan_lib.sh (§11.4.107(10)).
#
# §11.4.201 carrier-strip #8a-SUFFIX (placeholder ROOT + descriptive suffix).
# Forensic FP (2026-08-03): a signing-credentials TEMPLATE whose placeholder values
# name the field they stand in for —
#   DEVELOPMENT.storePassword={CHANGE_ME_DEVELOPMENT_STORE_PASSWORD}
# — was REFUSED at the commit seam. The `$`-anchored alternation above matches ONLY
# a BARE `CHANGE_ME`, so `CHANGE_ME` + `_DEVELOPMENT_STORE_PASSWORD` survived the
# strip and read as a real secret: a §11.4.201(1) FALSE-POSITIVE REFUSAL, itself a
# FAIL-bluff. The `<ROOT>_<WHAT_GOES_HERE>` form is the dominant real-world template
# convention, so the strip was structurally incomplete, not merely unlucky.
# WHY THIS CANNOT WEAKEN REAL-SECRET DETECTION (by construction, not by heuristic):
# the value must BEGIN with a recognised not-yet-filled-in marker, and a string that
# begins with a literal `CHANGE_ME` / `PLACEHOLDER` / `TODO` marker is not a working
# credential — appending a real secret after `CHANGE_ME_` yields a mangled string
# that authenticates nowhere. This is prefix-anchoring on an INTENT marker, NOT an
# entropy guess: entropy is deliberately NOT used as the discriminator because the
# library's own golden-bad `hunter2hunter2` is LOW-entropy and MUST stay caught.
# TIGHTENING (both deliberate, both golden-proven):
#   (a) the `[_-]` separator is MANDATORY (`+`, not `*`), so the documented
#       golden-bad `xxxsecret1` — root-shaped prefix, NO separator — still SURVIVES
#       and is still flagged;
#   (b) `xxx+` is DELIBERATELY EXCLUDED from the suffix-capable root set: three
#       letters is too generic a prefix to carry the intent-marker argument, and
#       `xxxsecret1` depends on it staying strict.
# Roots admitted here are only those that UNAMBIGUOUSLY mean "not filled in".
# `your[_-]…` and `…must_not_leak…` already carry their own affix forms above.
#
# §11.4.201 carrier-strip #8a-ELLIPSIS (documentation ELIDED-value placeholder).
# Forensic FP (2026-08-19): a `# Usage` comment documenting how to invoke a script —
#   ANTHROPIC_API_KEY=sk-ant-... bash scripts/e2e-agent-claude.sh
# — was REFUSED at the commit seam. The keyword branch of detector-1 sees
# `API_KEY={sk-ant-...}` (keyword + `=` + a 10-char non-space value) and none of the
# alternations above matches a value whose secret characters have been ELIDED with a
# trailing ellipsis, so the doc placeholder read as a real secret: a §11.4.201(1)
# FALSE-POSITIVE REFUSAL, itself a FAIL-bluff. `<PREFIX->...` is the dominant
# real-world convention for documenting a token in a usage line (sk-ant-... /
# sk-... / ghp_...), so the strip was structurally incomplete, not merely unlucky.
# WHY THIS CANNOT WEAKEN REAL-SECRET DETECTION (by construction, not by heuristic):
# the value must END in a literal ellipsis, i.e. the secret characters are LITERALLY
# ABSENT — replaced by dots. A string ending in `...` is not a working credential; it
# authenticates nowhere. This is the same INTENT-marker argument as #8a-SUFFIX
# (elision marker, NOT an entropy guess: entropy is deliberately NOT the
# discriminator because the library's own golden-bad `hunter2hunter2` is LOW-entropy
# and MUST stay caught).
# TIGHTENING (deliberate, golden-proven): the `[_-]` separator immediately before the
# dots is MANDATORY, so only the truncated-PREFIX idiom is stripped. A value with no
# separator before the ellipsis (`AKIA...`, `abc123...`) still SURVIVES and is still
# flagged — fail-closed on the ambiguous shape (§11.4.201 conservative-safe default).
# Covers the ASCII `...` and the UTF-8 `…` forms. Proven by the golden-good /
# golden-bad / negative-control fixtures (n) below and in
# <project>/scripts/git_hooks/fixtures/credscan_ellipsis_fp_proof.sh (§11.4.107(10)).
# PLURAL (`s?`) — added 2026-09-08 with detector alternative #27. Safe by the
# SYMMETRY argument stated in the #27 block above (a widened strip fires on
# `<kw>s=<v>` exactly when the un-widened one fired on `<kw>=<v>`), NOT by the
# false "a strip can only remove a false positive" claim. Falsifying fixture:
# case (26) in test_credential_scan_lib.sh — removing this `s?` makes it FAIL.
HELIX_CRED_PLACEHOLDER_CARRIER='^(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)s?[[:space:]]*[:=][[:space:]]*["'"'"']?(change_?me|placeholder|example|dummy|redacted|todo|tbd|fixme|xxx+|your[_-][a-z0-9._-]*|[a-z0-9._-]*must_not_leak[a-z0-9._-]*|(change_?me|placeholder|example|dummy|redacted|todo|tbd|fixme)([_-][a-z0-9]+)+|[a-z0-9_-]*[_-](\.{3,}|…))["'"'"']?$'

# §11.4.201 carrier-strip #8b (base64-image data-URI). A data:image/…;base64,<blob>
# embeds a long base64 run of image bytes that can RANDOMLY contain a token-shaped
# substring (AKIA… / AIza… / sk-…). The blob is image data, never a credential.
# The whole data-URI region is BLANKED before detector-1 runs (mirrors the detector-2
# gsub strips), so an incidental token-shape inside the blob is not flagged while a
# real token OUTSIDE any data-URI on the same line is untouched. Covers base64
# (+ / =) and base64url (- _) alphabets. Proven by golden-good (k).
HELIX_CRED_BASE64_IMAGE_CARRIER='data:image/[^;]*;base64,[A-Za-z0-9+/=_-]+'

# §11.4.201 carrier-strip #33 (HTML-RENDERED keyword=value, closing tag
# absorbed into the extracted value). Forensic FP (2026-10-05, measured):
# docs/requests/history.html -- the §11.4.65 HTML twin of docs/requests/
# history.md -- renders a markdown-backtick-wrapped illustration
# `` `API_KEY=x` `` as `<code>API_KEY=x</code>,`. The keyword-value branch of
# HELIX_CRED_VALUE_PATTERN requires 8+ non-space/non-quote characters after
# the `=`; the bare markdown illustration (`x`, 1 char) never matches on its
# own, but `<`/`>` are not excluded from the value char class, so the HTML
# closing tag + trailing punctuation that immediately follows in the
# RENDERED export (`</code>,`, 8 chars) pads the SAME illustration past the
# 8-char floor: `API_KEY=x</code>,` reads as a real secret -- a §11.4.201(1)
# FALSE-POSITIVE REFUSAL, itself a FAIL-bluff, that exists ONLY in the
# rendered HTML twin and not in its own markdown source.
#
# SAFETY -- the whole HTML closing-tag region is BLANKED before detector-1
# runs (the SAME mechanism #8b already uses for base64 data-URIs, mirrors
# detector-2's own carrier-strip #22 "one optional HTML end tag" tolerance
# for the SAME markdown-to-HTML rendering class). Blanking a closing tag can
# only ever SHORTEN an extracted value, never lengthen one, so a genuine
# secret long enough to be real on its own (8+ chars BEFORE the tag) still
# matches and is STILL CAUGHT once the tag is removed
# (`api_key=hunter2hunter2</code>` blanks to `api_key=hunter2hunter2 `, still
# 14 chars, still flagged) -- only an illustration value SHORT ENOUGH that the
# tag itself was the only thing padding it past the floor is exempted.
# Proven by golden-good scenario (t) + the (real secret immediately followed
# by an HTML closing tag) golden-bad falsifying control (t-neg) in
# test_credential_scan_lib.sh (§11.4.107(10)).
HELIX_CRED_HTML_CLOSE_TAG_CARRIER='</[A-Za-z][A-Za-z0-9]*>'

# --- Detector 2: email-adjacency plaintext-credential heuristic --------------
# The keyword-anchored detector-1 only sees a recognised secret KEYWORD followed
# by a value; it CANNOT see a password committed as a bare token adjacent to an
# email/username (e.g. "email@x.com / <password>" or "email@x.com:<password>")
# because there the "key" is an email, not a keyword. This awk detector closes
# that class GENERICALLY: an email address on a line, followed (after separators)
# by a password-SHAPED token — length 6..128, contains a letter AND (a digit OR a
# strong special), NOT itself an email/phone/filename/redaction-placeholder.
# No real secret value is embedded; the shape heuristic is validated against a
# golden-good / golden-bad fixture pair in test_credential_scan_lib.sh (§11.4.107(10)).
# Exit 0 = an offending line found, exit 1 = clean.

# --- Detector 1 carrier-strip #18: self-referential identifier value ---
# §11.4.201 carrier-strip #18 (IDENTIFIER-REFERENCE value). A struct-literal or
# keyword-argument field whose VALUE is the SAME identifier as its KEY —
# `Password: {password}`, `apiKey = {apiKey},`, `client_secret: {client_secret}` —
# is a VARIABLE REFERENCE, never a literal secret. The variable itself is
# populated elsewhere (typically os.Getenv), so the line NAMES where a
# credential comes from; it does not CONTAIN one. That is the §11.4.201(7)(a)
# carrier-vs-thing distinction applied to credentials.
#
# Why detector-1 fires without this strip: HELIX_CRED_VALUE_PATTERN makes the
# surrounding quote OPTIONAL (`["']?`), so `Password: {password}` parses as
# keyword + separator + a 9-character "value" (`password}`) and matches the
# generic assignment alternative. FORENSIC (2026-08-20): this blocked a commit
# on three Go integration harnesses whose only "secret" was the literal word
# `password}`. All three already matched at HEAD, so ANY commit touching them
# was blocked — a §11.4.201(1) false-positive refusal in the most
# safety-critical gate in the tree.
#
# SAFETY — the strip is deliberately as narrow as it can be: the value must be
# the SAME keyword as the key, optionally followed by ONE struct-literal
# punctuation character. `Password: {hunter2secret}` does NOT match (value !=
# key) and is still caught. `password = "AKIA..."` does NOT match and is still
# caught. Enumerated per keyword because ERE has no backreferences, so
# "value equals key" cannot be expressed generically.
# PLURAL SYMMETRY (2026-09-08, §11.4.201(1)). Before detector alternative #27
# existed, `passwords=passwords` was never DETECTED, so this strip needed no
# plural form. With #27 it IS detected, and the singular-only strip left
# `passwords=passwords` and `api_keys=api_keys` as HITS while `password=password`
# and `api_key=api_key` stayed clean — a false-positive class the singular form
# explicitly exempts (MEASURED 2026-09-08). `s?` on BOTH sides restores symmetry:
# value-equals-key is a VARIABLE REFERENCE in the plural exactly as in the
# singular. Falsifying fixture: case (26) in test_credential_scan_lib.sh.
HELIX_CRED_IDENTIFIER_REFERENCE_CARRIER='^(passwords?[[:space:]]*[:=][[:space:]]*passwords?|passwds?[[:space:]]*[:=][[:space:]]*passwds?|secrets?[[:space:]]*[:=][[:space:]]*secrets?|api[_-]?keys?[[:space:]]*[:=][[:space:]]*api[_-]?keys?|access[_-]?tokens?[[:space:]]*[:=][[:space:]]*access[_-]?tokens?|auth[_-]?tokens?[[:space:]]*[:=][[:space:]]*auth[_-]?tokens?|client[_-]?secrets?[[:space:]]*[:=][[:space:]]*client[_-]?secrets?)[},;[:space:]]*$'

# --- Detector 1 carrier-strip #24: PLACEHOLDER elvis/or FALLBACK literal ---
# §11.4.201 companion to the new elvis/or-fallback detector alternative. That
# alternative exists so `password = System.getenv("X") ?: "<real secret>"` is
# CAUGHT even though carrier-strip #20 exempts the env-lookup call itself
# (MEASURED 2026-08-26: without it the #20 strip turned a real fallback secret
# from HIT into CLEAN — a catch REGRESSION, which §11.4.201 ranks strictly worse
# than the false positive #20 cures). This strip keeps that alternative honest in
# the other direction: a fallback that is a config-template PLACEHOLDER
# (`?: "CHANGE_ME"`) is not a secret and must not refuse the commit.
HELIX_CRED_FALLBACK_PLACEHOLDER_CARRIER='(\?:|\|\|)[[:space:]]*["'"'"']?(change_?me|changeme|placeholder|example|dummy|redacted|todo|tbd|fixme|xxx+|your[_-][a-z0-9._-]*|[a-z0-9._-]*must_not_leak[a-z0-9._-]*)["'"'"']?[,;)}[:space:]]*$'

# --- Detector 1 carrier-strip #20: ENVIRONMENT-LOOKUP value ---
# §11.4.201 carrier-strip #20 (ENV-LOOKUP CALL value). A secret keyword whose
# VALUE is an environment-read CALL EXPRESSION — `storePassword =
# System.getenv(`, `password = os.Getenv(`, `secret: process.env.X` — NAMES
# where a credential comes from; it does not CONTAIN one. That is the
# §11.4.201(7)(a) carrier-vs-thing distinction, the same one carrier-strip #18
# already applies to a self-referential identifier value.
#
# Why detector-1 fires without this strip: HELIX_CRED_VALUE_PATTERN makes the
# surrounding quote OPTIONAL and stops the value at the first quote/space, so
# `storePassword = System.getenv("X") ?: ""` parses as keyword + separator + a
# 14-character "value" (`System.getenv(`) and matches the generic assignment
# alternative. FORENSIC (2026-08-26, MEASURED): a Kotlin Android signing block
# produced EIGHT such matches (4 signingConfigs x storePassword+keyPassword),
# every one of them the literal `System.getenv(` (sha256 e9ef39fffec5, len 14),
# blocking every commit that touched the file — a §11.4.201(1) false-positive
# refusal. NOTE the two OTHER hypotheses were MEASURED FALSE and are NOT what
# this strip cures: `keyAlias` is not a detector-1 keyword at all (0 matches),
# and an empty-string `?: ""` fallback can never match because the value pattern
# forbids a value STARTING with a quote.
#
# SAFETY — enumerated env-read idioms ONLY, whole-value anchored. A literal
# assignment `keyPassword = "Hunter2Hunter2!"` does NOT match (the value is not
# an env-read call) and is still caught. A value merely CONTAINING "env"
# (`password = envelope123`) does NOT match — the idioms are enumerated, never
# a bare `env` substring, so this cannot be widened by accident.
# HONEST BOUNDARY (§11.4.6): a real secret placed in an elvis FALLBACK on the
# same line (`= System.getenv("X") ?: "realsecret"`) is not caught by detector-1
# either BEFORE or AFTER this strip — `grep -Eio` stops the value at the first
# quote and no keyword precedes the fallback, so the fallback was never in
# detector-1's reach. This strip therefore removes a false positive without
# weakening any catch that previously existed; the fallback gap is PRE-EXISTING
# and is stated here rather than silently inherited. Golden-bad fixture (20-bad)
# pins the literal-assignment catch.
# PLURAL (`s?`) — added 2026-09-08 with detector alternative #27. Safe by the
# SYMMETRY argument stated in the #27 block above (a widened strip fires on
# `<kw>s=<v>` exactly when the un-widened one fired on `<kw>=<v>`), NOT by the
# false "a strip can only remove a false positive" claim. Falsifying fixture:
# case (26) in test_credential_scan_lib.sh — removing this `s?` makes it FAIL.
HELIX_CRED_ENV_LOOKUP_CARRIER='^(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)s?[[:space:]]*[:=][[:space:]]*((java\.lang\.)?system\.getenv\(|os\.getenv\(|getenv\(|os\.environ(\[|\.get\()|process\.env[.[][A-Za-z0-9_.]*|env\[|environment\.getenvironmentvariable\()$'

# --- Detector 1 carrier-strip #25: GENERIC ACCESSOR / METHOD-CALL value -----
# 11.4.201(1) false-positive cure, MEASURED 2026-08-27. #20 exempts env-lookup
# CALL expressions but as an ENUMERATED list (System.getenv( / os.Getenv( /
# process.env.X). The same STRUCTURAL class appears for any accessor call, e.g.
# Kotlin JSON parsing:   password = obj.optString("password", "")
# which detector-1 extracts as the value 'password = obj.optString(' and flags.
# This refused a clean tree at the pre-commit seam (8 staged files, all carriers:
# a NanoKVM device model plus its red-baseline copies).
#
# SAFETY (the #24 lesson -- a strip must NEVER turn a REAL secret CLEAN): a
# credential LITERAL never ends in an opening paren. password = "AKIA..."
# extracts as 'password = "AKIA' and does NOT match -> still caught. The
# elvis/or-fallback alternative (#24) is a SEPARATE detector alternative, so
# password = foo() ?: "<real secret>" is still caught. The value must be an
# identifier chain terminated by an opening paren and nothing else (end-anchored).
# PLURAL (`s?`) — added 2026-09-08 with detector alternative #27. Safe by the
# SYMMETRY argument stated in the #27 block above (a widened strip fires on
# `<kw>s=<v>` exactly when the un-widened one fired on `<kw>=<v>`), NOT by the
# false "a strip can only remove a false positive" claim. Falsifying fixture:
# case (26) in test_credential_scan_lib.sh — removing this `s?` makes it FAIL.
HELIX_CRED_ACCESSOR_CALL_CARRIER='^(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)s?[[:space:]]*[:=][[:space:]]*[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)*\($'

# --- Detector 1 carrier-strip #21: PASCALCASE SYMBOL-REFERENCE value ---
# §11.4.201 carrier-strip #21 (TYPE / SYMBOL NAME value). A secret keyword whose
# VALUE is a bare PascalCase symbol ending in the credential noun —
# `secret: OptionCPairingSecret,`, `token = SessionToken)`, `apiKey: BackendKey`
# — is a TYPE NAME in a function signature or struct literal, never a literal
# secret. This is carrier-strip #18 generalised from "value IS the key" to
# "value is a symbol NAMED FOR the key".
#
# FORENSIC (2026-08-26, MEASURED): a design document quoting a Kotlin signature
# `pair(host, pairingPort, secret: OptionCPairingSecret, ourPublicKey)` matched
# detector-1 in BOTH its .md and its .html export. NOTE the prose hypothesis was
# MEASURED FALSE: the match is not narrative English, it is exactly the extracted
# token `secret: OptionCPairingSecret,`.
#
# SAFETY — deliberately the narrowest form that covers the class, and applied
# CASE-SENSITIVELY (grep -Ev, NOT -Eiv) because the discriminator IS the case:
#   * value must START uppercase and be LETTERS ONLY — a real secret carrying a
#     digit or a special (`Hunter2Hunter2!`, `abc-123-def`) can never match;
#   * value must END in the capitalised credential noun (Secret/Password/Passwd/
#     Token/Key) — an arbitrary CamelCase word does not qualify;
#   * value must carry TWO CamelCase humps BEFORE that noun. MEASURED during
#     this change (adversarial self-probe, §11.4.194(6)(d)): the one-hump form
#     also skipped `secret = SuperSecret` / `secret: MySecret`, which are weak
#     but PLAUSIBLE real secrets, so the one-hump form was rejected and this
#     two-hump floor adopted. Both now stay CAUGHT (golden-bad 21-bad-2/-3);
#   * only ONE trailing struct-literal punctuation character is tolerated.
# `secret: Hunter2Secret` does NOT match (digit). `secret: hunter` does NOT match
# (lowercase initial, no noun suffix). Both are still caught. Under `-i` the
# uppercase-initial test would collapse and the strip WOULD over-match, so the
# case-sensitive grep is load-bearing, not cosmetic.
# PLURAL + COMPOSITE-LITERAL (2026-09-08, §11.4.201(1)). Two measured
# false-positive classes that the singular form exempts but the plural did not:
#   * `apiKeys=DefaultAPIKey` was a HIT while `apiKey=DefaultAPIKey` was clean —
#     cured by `s?` after the keyword AND after the trailing credential noun;
#   * `apiKeys = &APIKeys{}` — a Go composite literal, i.e. a TYPE reference and
#     precisely this strip's subject — was the ONLY corpus cost (2 tracked files)
#     of admitting the space-padded plural assignment in #27. An optional leading
#     `&` and a trailing `{}` cure it; corpus 141 -> 141, zero lost catches. A
#     `&Type{}` composite literal is never a literal secret value.
# UNCHANGED by the widening, and re-MEASURED after it: the two-hump floor and the
# case-sensitive application still hold — `secret = SuperSecret` and
# `secret: SuperSecretValue` remain CAUGHT. Falsifying fixtures: case (26) in
# test_credential_scan_lib.sh — removing either the `s?` or the `&`/`{}` form
# makes them FAIL.
HELIX_CRED_SYMBOL_REFERENCE_CARRIER='^[A-Za-z_.-]*([Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy])s?[[:space:]]*[:=][[:space:]]*&?[A-Z][a-z]*[A-Z][A-Za-z]*(Secret|Password|Passwd|Token|Key)s?(\{\})?[,;)}]?$'

# §11.4.201 carrier-strip #32 (AKIA SELF-TEST GOLDEN-BAD PLACEHOLDER LITERAL).
# Forensic FP (2026-10-04/05, measured): docs/requests/history.md — a §11.4.208
# append-only operator-request-history ledger — captures, verbatim, a prior
# subagent's forensic hand-back report DISCUSSING this very scanner's own AKIA
# detector branch and quoting, as prose analysis, the EXACT literal value this
# file's own documentation comments (above, lines 18/178/228/242/282/357-358/826)
# already cite as THEIR chosen golden-bad placeholder example:
# `AKIA1234567890123456`. The AKIA branch of HELIX_CRED_VALUE_PATTERN carries no
# keyword gate (unlike the password/secret/api_key branches), so detector-1
# extracts the bare token with no surrounding line context to strip against, and
# no EXISTING carrier in this pipeline is shaped to recognise one SPECIFIC named
# literal value (every other carrier here strips a SHAPE/CLASS). The value
# therefore survived every carrier above as a false hit: a §11.4.201(1)
# FALSE-POSITIVE REFUSAL, itself a FAIL-bluff — refusing the very ledger entry
# that documents this scanner's own test fixtures.
#
# SAFETY — NAME-anchored on the EXACT literal, start-to-end, never a shape or
# prefix match (the narrowest carrier in this file, by design): the sixteen
# characters after `AKIA` are PURELY SEQUENTIAL ascending digits
# (1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6) — a form no genuine AWS-issued access-key ID
# ever takes (real AWS key-id suffixes are base32-like pseudo-random over
# [0-9A-Z], never a monotonic digit run, and this project's OWN other AKIA
# golden-bad fixtures — `AKIA1234567890ABCDEF`, `AKIAIOSFODNN7...`,
# `AKIAQ7X2M4B8N1V5C3Z9` in test_credential_scan_lib.sh — are all letter-mixed
# and therefore untouched by this anchor). The regex is a bare `^…$` literal
# string match with no alternation and no wildcard: a DIFFERENT 16-character
# AKIA-shaped suffix — including one built from the SAME ten digits in a
# different order, or carrying even a single letter, or a single digit removed
# or added — does NOT match and is STILL CAUGHT (golden-bad falsifying
# control). This cannot create a blind spot for a real key: it exempts exactly
# one named constant, never a pattern class. Proven by golden-good scenario (s)
# + the (real, non-sequential 16-char AKIA suffix) golden-bad falsifying
# control (s-neg) in test_credential_scan_lib.sh (§11.4.107(10)).
HELIX_CRED_AKIA_PLACEHOLDER_CARRIER='^AKIA1234567890123456$'

HELIX_CRED_ADJACENCY_AWK='
{
  line = $0
  # §11.4.201 carrier-strip #34 (HTML-ENTITY-ENCODED quote/punctuation
  # RECOVERY). The §11.4.65 HTML export of a markdown doc entity-encodes
  # literal punctuation (`"` -> `&quot;`, `'"'"'` -> `&#39;` / `&apos;`,
  # `<` -> `&lt;`, `>` -> `&gt;`, `&` -> `&amp;`), so a shell fragment that
  # reads as a quoted variable reference in its OWN markdown source
  # (`"$NEW_TREE"`, exempted by carrier-strip #27s `"` end-anchor) renders as
  # `&quot;$NEW_TREE&quot;` in the HTML twin. The adjacency-window tokenizer
  # below splits on `;` (among other delimiters), so the CLOSING `&quot;`
  # fragments separate into their own tokens while the OPENING `&quot;`
  # immediately before `$NEW_TREE` has no delimiter between it and the
  # variable name in that split segment, so it glues on as `$NEW_TREE&quot`
  # -- a shape carrier-strip #27s end-anchor does not recognise (it expects a
  # literal `"`, not a five-character HTML entity), so the SAME shell-variable
  # reference that is correctly exempted in markdown reads as password-shaped
  # in HTML: a §11.4.201(1) FALSE-POSITIVE REFUSAL, itself a FAIL-bluff, that
  # exists ONLY in the rendered export. FORENSIC (2026-10-05, measured):
  # docs/requests/history.html quoting `git -c user.email=fastcycle-migrate@
  # example.invalid commit-tree &quot;$NEW_TREE&quot; ...` (itself a prior
  # subagent hand-back discussing carrier-strip #27s own forensic origin).
  #
  # SAFETY -- this is RECOVERY, not a strip: each entity is decoded back to
  # the LITERAL character it represents (the real condition this whole
  # pipeline already asserts for raw markdown), so every carrier above and
  # below runs on the SAME text it would see in the un-rendered source --
  # nothing is blanked or made more permissive, the pipeline is simply shown
  # the real quote mark its own markdown source always had. A real password
  # that happens to be spelled with the literal five-character substring
  # `&quot;` (vanishingly unlikely, and already handled identically in the
  # markdown source since the entity decodes to the SAME shape a markdown
  # leak already has) is unaffected -- no detection narrows. `&amp;` decodes
  # LAST (via the `\&`-escaped gsub replacement, so a literal ampersand is
  # inserted rather than gsubs own matched-text substitution) so a
  # doubly-escaped `&amp;quot;` (a literal ampersand followed by literal text
  # `quot;` in the source) does not spuriously decode into a quote. Proven by
  # golden-good scenario (u) + the (real password near an email, carrying a
  # literal `&quot;` substring) golden-bad in test_credential_scan_lib.sh
  # (§11.4.107(10)).
  # §11.4.201 carrier-strip #35 (ITERATIVE entity-decode, bounded 3 passes).
  # A single decode pass only resolves ONE level of HTML-entity escaping, in
  # pipeline order -- a DOUBLY-escaped tag (`&amp;lt;/code&amp;gt;`, produced
  # when a report already containing `&lt;/code&gt;` is itself quoted into a
  # LATER report and re-exported to HTML) decodes the outer `&amp;` -> `&`
  # LAST in the chain, so the newly-revealed `&lt;`/`&gt;` is never re-run
  # through the EARLIER `&lt;`/`&gt;` rules in that same pass -- carrier strip 33 own
  # closing-tag blank then cannot see it either, since it is still entity
  # form. Forensic FP (2026-10-05, measured, discovered chasing #33/#34 own
  # fix as it recursed through docs/requests/history.md live append-only
  # §11.4.210 ledger): a status report quoting carrier strip #33 forensic text
  # (which itself quotes `<code>API_KEY=x</code>,`) got logged, exported,
  # QUOTED AGAIN by a later report, and exported again -- two full escape
  # levels deep, surviving as `API_KEY=x&lt;/code&gt;,`. Looping the SAME
  # three decode rounds (bounded at 3, not unbounded, so a pathological input
  # cannot spin this loop forever) resolves up to 3 nesting levels; deeper
  # nesting is an honest residual (§11.4.6) a future round extends the bound
  # for, never silently assumed closed. Proven by golden-good scenario (w) +
  # the (real secret behind a TRIPLE-escaped tag, still 1 level past the
  # bound) golden-bad falsifying control (w-neg) in
  # test_credential_scan_lib.sh (§11.4.107(10)).
  for (_hc_pass = 0; _hc_pass < 3; _hc_pass++) {
    gsub(/&quot;/, "\"", line)
    gsub(/&#39;/, sprintf("%c", 39), line)
    gsub(/&apos;/, sprintf("%c", 39), line)
    gsub(/&lt;/, "<", line)
    gsub(/&gt;/, ">", line)
    gsub(/&amp;/, "\\&", line)
  }
  # §11.4.201 carrier-strip #1: a git SSH remote URL (form git@<host>:<org>/<repo>[.git])
  # is NOT an email+password adjacency — its "email" is the conventional git@<host>
  # SSH user and its "password-shaped" token is an org/repo name that may contain
  # digits (real forensic false-positive: a repo remote list in a doc). Blank the
  # whole remote-URL substring BEFORE the email match so the heuristic asserts the
  # REAL condition. The org/repo "/" is REQUIRED, so a genuine git@<host>:<secret>
  # with no slash is still scanned and detector-1 (value-pattern) is untouched.
  # Proven by golden-good scenario (a) in test_credential_scan_lib.sh.
  # §11.4.201 carrier-strip #22 (MARKUP-SPLIT git remote). An HTML export of a
  # doc that mentions a git SSH remote is mailto-autolinked by the exporter, so
  # `git@host:org/repo` becomes `<a href="mailto:git@host">git@host</a>:org/repo`
  # and an END TAG now sits between the host and the ":". That split defeats the
  # contiguous strip below, and the org name (digits + letters) then reads as a
  # password-shaped token adjacent to the "email". FORENSIC (2026-08-26,
  # MEASURED): the offending token was the GitHub org name, not the address.
  # Tolerating ONE optional HTML end tag at exactly that position restores the
  # REAL condition; the org/repo "/" is still REQUIRED, so a genuine
  # git@<host>:<secret> with no slash is still scanned.
  gsub("git@[A-Za-z0-9.-]+(</[A-Za-z][A-Za-z0-9]*>)?:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+", " ", line)
  # §11.4.201 carrier-strip #31: the `ssh://git@<host>/<org>/<repo>[.git]` URL
  # FORM (slash after host, not the SCP-like colon the strip above covers) is
  # the SAME git-remote-is-not-a-credential case, just a different URL shape.
  # Forensic FP (2026-10-05, measured via the email-adjacency awk programs own
  # debug instrumentation): `scripts/testing/test_commit_all_owned_cascade.sh` line
  # 142, the quoted _submodule_org call on ssh://git@github.com/ATMOSphere1234321/repo.git
  # — this projects real GitHub org "ATMOSphere1234321" (letters+digits)
  # survived un-stripped and read as a password-shaped token adjacent to the
  # git@ "email", REFUSING a legitimate commit. The org/repo "/" is still
  # REQUIRED (mirrors the strip above), so a genuine `ssh://git@<host>/<secret>`
  # with no second slash is still scanned.
  gsub("ssh://git@[A-Za-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+", " ", line)
  # §11.4.201 carrier-strip #2: a systemd user-instance unit name (form
  # user@<uid>.service / <name>@<N>.service) is email-SHAPED (local@digits.service,
  # ".service" reads as a TLD) but is NOT an email — it appears verbatim in every
  # §12 host-session-safety forensic note ("user@1000.service was SIGKILLed
  # (status=9/KILL)"), where the adjacent "status=9" (letter+digit+"=") looks like
  # a password to the heuristic. A systemd unit is never a credential carrier, so
  # blank the whole unit token BEFORE the email match (mirrors the git@ strip).
  # A real email lands on a real TLD, so genuine "user@company.com : <pw>" is
  # untouched. Proven by golden-good scenario (b) in test_credential_scan_lib.sh.
  gsub("[A-Za-z0-9._%+-]+@[0-9]+\\.service", " ", line)
      # 11.4.201 carrier-strip #26: sed substitute expression with @ delimiters.
      # MEASURED 2026-08-27: a mutation-testing line of the form
      #     sed -e 0s@MessageDigest.isEqual(a, b)@true@0 "SRC"
      # (0 = single quote) makes s@MessageDigest.isEqual email-SHAPED: local part s,
      # domain MessageDigest, TLD isEqual. The adjacency heuristic therefore flagged a
      # mutation-testing script as a credential leak - a 11.4.201(1) false-positive
      # refusal at the pre-commit seam, which is a FAIL-bluff exactly as a false pass
      # is a PASS-bluff.
      # The distinguishing feature vs a real address is the THREE-@ sed structure
      # preceded by a lone one-letter sed command (s or y), which a genuine email
      # never has. Blank the whole sed expression BEFORE the email match (mirrors the
      # git@ / systemd-unit / Java-object-ref strips above), so a REAL email elsewhere
      # on the same line is untouched and still evaluated.
      gsub("(^|[^A-Za-z0-9._%+-])[sy]@[^@]*@[^@]*@", " ", line)
  # §11.4.201 carrier-strip #3: a Java/Android object reference (form
  # <pkg.Class>@<pkg>.<CamelCaseClass>[$$SyntheticLambda<N>][@<hex-hashcode>])
  # is email-SHAPED — its "@<pkg>.Class" reads as local@domain.TLD where the
  # "TLD" is a CamelCase ClassName (AudioManager, ExternalSyntheticLambda). These
  # appear verbatim in every captured logcat (MediaFocusControl clientId=...),
  # in agent task-notification quotes, and in a request-history log (§11.4.208).
  # The distinguishing feature vs a real email is the final dotted component:
  # a Java ClassName is CamelCase ("[A-Z][a-z]..."), a real email TLD is lowercase
  # (.com) or all-caps (.COM) — neither matches [A-Z][a-z]. Blank the whole ref
  # BEFORE the email match so the heuristic asserts the REAL condition. A genuine
  # "user@company.com : <pw>" (lowercase TLD) is UNTOUCHED. Proven by golden-good
  # scenario (c) + golden-bad (email+password) in test_credential_scan_lib.sh.
  gsub("[A-Za-z0-9._%+$-]+@[A-Za-z0-9._$-]*\\.[A-Z][a-z][A-Za-z0-9_$]*", " ", line)
  # §11.4.201 carrier-strip #4: any Java synthetic token ("...$$ExternalSyntheticLambda13")
  # is never a credential — blank $$-bearing tokens outright.
  gsub("[A-Za-z0-9_$.]*\\$\\$[A-Za-z0-9_$.]*", " ", line)
  if (match(line, /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+/)) {
    rest = substr(line, RSTART + RLENGTH)
    # §11.4.201 carrier-strip #6: an email-adjacency credential (email:pass,
    # email / pass, email  pass) has the password IMMEDIATELY adjacent to the
    # email — every documented leak form and every golden-bad fixture places the
    # password within ~25 chars. A long PROSE line where an email co-occurs with
    # DISTANT technical tokens (config keys, code identifiers, product names in a
    # bug report) is NOT a credential. Restrict the scan to a compact adjacency
    # window after the email; a genuine leaked password fits well within it
    # (proven by the golden-bad fixtures), while a real forensic-record line — an
    # attestation discussion with an email early in the line then unrelated
    # platform/config tokens (SoC name, integrity-check flag, boot-state
    # property) far beyond it — falls outside. Detector-1 (keyword-value) is
    # untouched and still catches a widely-separated keyword=value leak.
    rest = substr(rest, 1, 48)
    n = split(rest, toks, "[[:space:]/:|,;()]+")
    for (i = 1; i <= n; i++) {
      t = toks[i]
      if (length(t) < 6 || length(t) > 128) continue
      if (tolower(t) ~ /redacted|changeme|placeholder|yourpassword|your-password|your_password|xxxxxxxx|dummy/) continue
      # §11.4.201 carrier-strip #23 (MARKUP-WRAPPED email self-reference). The
      # email-is-not-a-password skip below is ^...$ anchored against the RAW
      # token, so an HTML mailto autolink defeats it: the exporter emits the
      # address TWICE, `<a href="mailto:E">E</a>`, the first copy satisfies the
      # email match and the second arrives at this loop still wearing its markup
      # (`">E<`), which the anchored test cannot recognise as an email. FORENSIC
      # (2026-08-26, MEASURED): 6 of 7 offending HTML exports tripped on exactly
      # that `">E<` token. Strip the surrounding markup punctuation BEFORE the
      # anchored comparison. The cleaned form is used ONLY for the is-it-an-email
      # test — the password-shape tests below still run on the RAW token — so a
      # real password wearing the same markup (`">Hunter2Hunter2!<`) does not
      # clean to an email, is NOT skipped, and is still refused.
      tnm = t
      gsub(/^["<>=&;]+/, "", tnm); gsub(/["<>=&;]+$/, "", tnm)
      if (tnm ~ /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+$/) continue
      if (t ~ /^[-+0-9(). _]+$/) continue
      # §11.4.201 carrier-strip #29 (MARKDOWN-BACKTICK-WRAPPED filename). The
      # file-extension-suffix skip immediately below is a bare `$`-anchored
      # check with no tolerance for a trailing markdown closing backtick, so a
      # doc that names a script inside backticks — `` `scripts/commit_all.sh` ``
      # — has its "/"-delimited tail token arrive here as `commit_all.sh\``
      # (the closing backtick still attached; the OPENING backtick was already
      # consumed by the PRECEDING "/"-delimited token). The trailing backtick
      # defeats the `$` end-anchor, so the recognised-extension skip never
      # fires and the filename reads as password-shaped. FORENSIC
      # (2026-10-04, MEASURED): `docs/requests/history.md`, a prose line
      # reading "note: `scripts/commit_all.sh` hardcodes a stale ... co-author
      # line", within the 48-char adjacency window of an UNRELATED
      # `noreply@anthropic.com` co-author-trailer address earlier on the same
      # physical line — tripped exactly this way, refusing the commit.
      # SAFETY — the recognised-extension SET and the `$`-anchoring are
      # otherwise UNCHANGED; only ONE optional trailing backtick is now
      # tolerated at the position the end-anchor already sits. A real secret
      # that happens to end in one of these literal extensions is ALREADY
      # exempted by this (pre-existing, previously unlabeled) check regardless
      # of this widening — this strip does not enlarge the recognised-extension
      # set, it only lets that pre-existing recognition survive one layer of
      # markdown code-span wrapping, mirroring the "one optional HTML end tag
      # at exactly that position" tolerance carrier-strip #22 already applies
      # to a different markup-split shape.
      #
      # KNOWN GAP (2026-10-04, fix-forward on an independent Opus-xhigh
      # review, §11.4.6/§11.4.201 — stated honestly, not silently left
      # implicit): the token split above already removes "/" as a delimiter
      # (see the `split(rest, toks, ...)` call above this loop), so a real
      # path like `scripts/commit_all.sh` and a literal secret that merely
      # ENDS in one of these extensions (e.g. a password `Hunt3r!.sh`) arrive
      # at this check as the IDENTICAL shape — there is no path-separator
      # signal left to distinguish them. This gap is PRE-EXISTING (the bare,
      # non-backtick-wrapped form `Hunt3r!.sh` was ALREADY exempted by this
      # same extension check before this carrier-strip existed); the only
      # new effect of this widening is that the BACKTICK-WRAPPED form of that
      # same pre-existing gap now ALSO escapes (empirically verified in-session:
      # `` `Hunt3r!.sh` `` adjacent to an email was HIT before this
      # carrier-strip, is CLEAN after it). Tightening this check to require a
      # genuine path signal would need changing the delimiter set itself
      # (out of scope for this carrier-strip, and risks new regressions of
      # its own) — recorded here as an honest, bounded, pre-existing
      # limitation rather than fixed under this change. Proven by golden-good scenario (o)
      # + the (real password near an email, no recognised-extension suffix)
      # golden-bad in test_credential_scan_lib.sh (§11.4.107(10)).
      if (t ~ /\.(md|html|pdf|docx|sh|txt|json|ya?ml|xml|png|jpe?g|gif|svg|log|go|py|kt|java|cpp|ts|js|tsv|csv|db|c|h)`?$/) continue
      # §11.4.201 carrier-strip #27 (SHELL-VARIABLE-REFERENCE token). A git
      # `-c user.email=<name>@example.invalid` identity flag (the RFC 2606
      # reserved documentation TLD the git-fixture helpers use for
      # throwaway test/tool commits, never a real credential) is frequently
      # followed, within the adjacency window, by a double-quoted shell
      # variable reference such as `"$NEW_TREE"` or `"$LOCAL_HEAD"` — the
      # token is ALL-CAPS-with-underscores (hasLetter) wrapped in `"` with a
      # literal `$` sigil, and `$` is itself one of the hasSpec characters, so
      # the heuristic misreads an ordinary shell interpolation as a
      # password-shaped token immediately after an "email". FORENSIC
      # (2026-10-02, MEASURED): `constitution/scripts/fastcycle/consumers/
      # migrate.sh`, its `git -c user.email=fastcycle-migrate@example.invalid
      # commit-tree "$NEW_TREE" -p "$LOCAL_HEAD"` line tripped exactly this
      # way. A shell variable reference is never a credential value — skip a
      # token that is ENTIRELY an (optionally fd-redirect-prefixed, optionally
      # double-quoted) `$NAME` form (bare `$`, `${...}`, and quoted variants
      # all reduce to this shape once markup/quote stripping above has run).
      # The leading `[0-9]*>>?` tolerates a shell fd-redirect operator
      # (`2>"$LOG"`, `>>"$OUT"`) immediately preceding the variable — common
      # throughout this codebase and, UNMEASURED but genuinely possible given
      # the fixed-width 48-char adjacency window above, the token MAY be
      # TRUNCATED mid-identifier (`2>"$MI` for a real `2>"$MIGRATE_SCRATCH/..`
      # redirect) — FORENSIC (2026-10-02, MEASURED): the SAME migrate.sh line
      # continues ` 2>"$MIGRATE_SCRATCH/committree.err")`, and the window cut
      # it to the token `2>"$MI`, which the FIRST version of this fix (no
      # redirect-prefix tolerance) still missed. A real password never takes
      # this `[redirect]["]$IDENT` shape (a digit-prefixed `$` sigil is not a
      # credential character sequence any known leak format uses), so this
      # is NOT a weakening of the heuristic for genuine secrets — a real
      # password containing a literal `$` character survives this check
      # unless its WHOLE token (partial-or-truncated included) is this exact
      # shell-reference shape, which a genuine secret value never is. Proven
      # by golden-good scenario (f) + golden-bad (real email+password
      # containing a `$`) in test_credential_scan_lib.sh (§11.4.107(10)).
      if (t ~ /^([0-9]*>>?)?"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?$/) continue
      # §11.4.201 carrier-strip #28 (MARKDOWN-BACKTICK-WRAPPED shell-variable-
      # reference token — a MARKUP variant of carrier-strip #27 directly
      # above, the same relationship carrier-strip #22 bears to #1 and #23
      # bears to the bare email-self-reference check). The carrier-strip #27
      # shell-reference shape is `^...$`-anchored against the RAW token, with
      # no tolerance for a markdown code-span backtick, so a doc that wraps
      # the SAME shell interpolation in backticks — `` `"$COMMIT_MSG"` `` — defeats the
      # anchor on whichever side the 48-char adjacency window truncation (or
      # the "/" / ":" / "," token delimiters) leaves attached. FORENSIC
      # (2026-10-04, MEASURED): `docs/requests/history.md`, a prose line
      # reading `sat on the same physical line as \`"$COMMIT_MSG"\`, which the
      # line-scoped adjacency heuristic misread` — tripped exactly this way
      # (the window truncated the token to `` `"$COMMIT_MSG `` before the
      # closing quote/backtick were ever reached), refusing the commit.
      # SAFETY — the ONLY widening is one optional leading AND one optional
      # trailing literal backtick at the positions the existing `"` / `$NAME`
      # anchors already sit; the INNER shape (an optional fd-redirect prefix,
      # an optional `"`, a `$` sigil, an identifier made ONLY of
      # letters/digits/underscore, an optional `}` / `"`) is BYTE-IDENTICAL to
      # the carrier-strip #27 pattern — not re-derived, not loosened. By the
      # same symmetry argument the carrier-strip #27 plural widening already
      # relies on (documented at carrier-strip #27 / alternative #27 above):
      # this strip fires on a backtick-wrapped token exactly when the
      # un-widened #27 pattern already
      # fired on that same token with its wrapping backtick(s) removed — it
      # adds no new VALUE class the inner pattern did not already accept, it
      # only lets that acceptance survive one layer of markdown code-span
      # wrapping. A real password wearing the same markup
      # (`` `Hunter2Hunter2!` ``) does not reduce to the `$NAME` shape (it
      # carries no `$` sigil at all) and is still refused.
      #
      # KNOWN GAP (2026-10-04, fix-forward on an independent Opus-xhigh
      # review, §11.4.6/§11.4.201 — stated honestly, not silently left
      # implicit): a password that itself happens to be shaped EXACTLY like a
      # bare `$IDENTIFIER` reference (e.g. `$ecretPass1` — a `$` sigil
      # followed only by letters/digits/underscore, no other password-shaped
      # character) is indistinguishable from a real shell-variable reference
      # by this check, same as its un-widened #27 counterpart. This gap is
      # PRE-EXISTING (the bare, non-backtick-wrapped form `$ecretPass1` was
      # ALREADY exempted by carrier-strip #27 before this widening existed);
      # the only new effect of this strip is that the BACKTICK-WRAPPED form of that
      # same pre-existing gap now ALSO escapes (empirically verified
      # in-session: `` `$ecretPass1` `` adjacent to an email was HIT before
      # this carrier-strip, is CLEAN after it). The realistic exploit surface
      # is narrow — the ENTIRE token, once unwrapped, must reduce to exactly
      # `$name` with no other character — recorded here as an honest, bounded,
      # pre-existing limitation rather than fixed under this change. Proven by
      # golden-good scenario (p) + the (real email+password containing a `$`,
      # markdown-backtick-wrapped) golden-bad in test_credential_scan_lib.sh
      # (§11.4.107(10)).
      if (t ~ /^`?([0-9]*>>?)?"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?`?$/) continue
      # §11.4.201 carrier-strip #30 (GIT IDENTITY-KEY value: user.name /
      # user.email). A git identity CONFIG KEY — `user.name=<value>` or
      # `user.email=<value>` — is never itself a credential: these fields hold
      # a commit author display NAME / ADDRESS, used only for attribution,
      # never for authentication. FORENSIC (2026-10-04, MEASURED):
      # `docs/requests/history.md` quotes a selftest-isolation bug report
      # listing the git-config keys an un-isolated scratch repo picked up from
      # its parent environment, including a markdown-backtick-wrapped
      # `` `user.name=custody_sweep selftest` `` bullet, within the 48-char
      # adjacency window of an UNRELATED `user.email=...@example.invalid`
      # line earlier in the same prose paragraph. The "/" + space token
      # delimiters split this into `` `user.name=custody_sweep `` and
      # `selftest\``; the FIRST of those carries the underscore from the key
      # itself (one of the hasSpec characters), so the heuristic misread an ordinary
      # git-config KEY NAME as a password-shaped token adjacent to an email.
      #
      # SAFETY — DELIBERATELY NARROW, by CONSTRUCTION, never by heuristic (the
      # §11.4.201(7)(a) carrier-vs-thing distinction applied to git-config
      # keys): the match requires the LITERAL, closed-set key string
      # `user.name` or `user.email` — never a prefix match, never a wildcard
      # over `*.name`/`*.email`, never a substring test — so this strip is
      # STRUCTURALLY INCAPABLE of matching any OTHER git-config key, in
      # particular NONE of the RCE-vector keys a sibling instrument
      # (the repo_verify.py CA-026 finding) specifically watches for
      # (`core.sshCommand`, `credential.helper`, `remote.<name>.uploadpack`,
      # `url.*.insteadOf`) — those require entirely different literal keywords
      # this regex never contains, so this strip cannot create a blind spot
      # for that class even in principle, and it does NOT widen, touch, or
      # otherwise interact with the repo_verify.py own, separate RCE-vector
      # check in any way.
      # The VALUE itself is additionally restricted to letters, underscore,
      # dot and hyphen — explicitly EXCLUDING every digit and every one of
      # `! # $ % ^ & * ( ) + =` and `@` — so a value that is anything other
      # than a bare name/slug still SURVIVES this strip and is still flagged.
      # HONEST RESIDUAL (§11.4.6, stated not silently assumed closed): a
      # credential deliberately smuggled into `user.name=`/`user.email=`
      # would need to be assembled from ONLY letters/underscore/dot/hyphen
      # with NO digit at all to evade this check — a narrower residual than
      # the one already accepted at carrier-strips #18/#21/#25 for the SAME
      # class of risk (an identifier- or symbol-shaped "value" that is
      # technically still a valid string for a secret to take). `user.name=
      # AKIA1234567890123456` and `user.name=hunter2hunter2` (digit present)
      # are NOT exempted by this strip and are still caught. Proven by
      # golden-good scenario (q) + the (real user.name value carrying a
      # digit) golden-bad in test_credential_scan_lib.sh (§11.4.107(10)).
      tgid = t
      gsub(/^`+/, "", tgid); gsub(/`+$/, "", tgid)
      if (tgid ~ /^user\.(name|email)=[A-Za-z_.-]*$/) continue
      # §11.4.201 carrier-strip #5: a Markdown-emphasized plain WORD (**BROWSERS**,
      # *note*, `code`) is prose emphasis in a doc, NOT a password. The ** / * / `
      # emphasis runs make the "hasSpec" test below read an ordinary word as
      # password-shaped. Strip leading/trailing * and backtick runs; if what
      # remains is a pure ASCII word (all letters, NO digit, NO non-markdown
      # special), it is not password-shaped. A real password near an email carries
      # a digit or a non-markdown special (Passw0rd!, **MyP@ss1**) and SURVIVES this
      # strip (its de-emphasized form is not pure-alpha), so detector-2 still
      # refuses it — detector-1 is untouched. Forensic FP: docs/Issues.md:3794
      # bug-report line "<reporter-address> ... **BROWSERS**". Proven by
      # golden-good scenario (e) + the (real-password-near-email) golden-bad in
      # test_credential_scan_lib.sh (§11.4.107(10)).
      tclean = t
      gsub(/^[*`]+/, "", tclean); gsub(/[*`]+$/, "", tclean)
      if (tclean ~ /^[A-Za-z]+$/) continue
      hasLetter = (t ~ /[A-Za-z]/)
      hasDigit  = (t ~ /[0-9]/)
      hasSpec   = (t ~ /[!#$%^&*()=+_]/)
      if (hasLetter && (hasDigit || hasSpec)) { found = 1; exit }
    }
  }
}
END { exit(found ? 0 : 1) }
'

# --- Binary-skip helper ------------------------------------------------------
# Returns 0 (skip detector-2) if the path extension is a binary blob that MUST
# NOT be text-scanned by the adjacency detector (they do not tokenise as text;
# DOCX/PDF are compressed anyway). Includes SQLite DB extensions (db/sqlite/
# sqlite3/db-wal/db-shm) — feeding a binary .db to awk as TEXT is a §11.4.201
# false-positive vector (random bytes adjacent to an embedded email/username
# match the password-shape heuristic). Detector-1 (grep) still runs on these;
# only the adjacency detector is skipped.
helix_cred_is_binary_skip() {
  case "$1" in
    *.pdf|*.docx|*.png|*.jpg|*.jpeg|*.gif|*.ico|*.zip|*.tar|*.xz|*.gz|*.bz2|*.woff|*.woff2|*.ttf|*.otf|*.so|*.bin|*.img|*.apk|*.jar|*.class|*.dll|*.dylib|*.mp4|*.mkv|*.wav|*.mp3|*.webp|*.pyc|*.db|*.sqlite|*.sqlite3|*.db-wal|*.db-shm)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# --- Detector-1 real-hit test (applies carrier-strip #8) ---------------------
# Returns 0 iff a TEXT file contains a detector-1 (keyword / known-token-format)
# match that is a REAL secret — i.e. one that SURVIVES carrier-strip #8: base64
# image data-URIs (#8b) are blanked first, then every detector-1 match is checked
# and any placeholder-value carrier (#8a) is dropped; a surviving non-placeholder
# match is a real hit. Binary blobs do NOT use this path (helix_cred_scan_file
# runs the raw grep for them — the #8 carriers are text constructs, and running
# sed/grep -o over a binary is a §11.4.201 false-positive vector).
# STREAM variant: reads candidate content on STDIN and applies the SAME
# #8b data-URI blank → detector-1 value-pattern extract (grep -Eio, so the
# extracted MATCH is `keyword<sep>value`, e.g. `PASSWORD={CHANGE_ME}`, not the whole
# host line) → #8a placeholder strip → survivor test. Any consumer that scans a
# STREAM rather than a path — a pre-commit hook reading `git show :FILE`, the
# commit_all.sh cascade credscan — MUST use THIS, never a raw
# `grep -Eiq "$HELIX_CRED_VALUE_PATTERN"`: the raw grep BYPASSES the #8a
# placeholder carrier-strip and false-positive-REFUSES a legitimate mid-line
# `PASSWORD={CHANGE_ME}` template/example/tracker-item line (§11.4.201(1)
# false-positive-refusal = a FAIL-bluff, exactly as a false-negative pass is a
# PASS-bluff). ONE implementation feeds both the file variant and every stream
# consumer, so the two cannot drift (§11.4.227). Exit 0 = a real hit survives, 1 =
# clean. The #8a strip is tight (a real secret is never a whole placeholder
# token), so this never weakens real-secret detection — proven by the golden-bad
# fixtures in test_credential_scan_lib.sh (§11.4.201(2) / §11.4.107(10)).
helix_cred_detector1_real_hit_stream() {
  # `-a` on the extraction: a BINARY stream (a staged .db/.so/.apk with an
  # embedded plaintext secret, or text carrying a stray NUL) must still yield its
  # keyword=value matches. Without `-a`, GNU grep on binary prints "binary file
  # matches" to STDERR with EMPTY stdout, so `grep -Eio` extracts nothing → the
  # secret would pass CLEAN at the pre-commit seam where the old raw `grep -Eiq`
  # caught it (§11.4.201(2) false negative — Fable review B2, proven). #8a stays
  # tight (it strips only whole placeholder-shaped tokens, `$`-anchored), so `-a`
  # cannot weaken real-secret detection. #34 (HTML-entity decode), #8b
  # (data-URI blank) and #33 (HTML closing-tag blank) run first, IN THAT
  # ORDER: entity-decode MUST precede the closing-tag blank, because a tag
  # that only EXISTS as the entity-escaped form `&lt;/code&gt;` (prose that
  # LITERALLY describes an HTML tag, as opposed to a markdown code-span the
  # exporter rendered INTO a real tag — the #33 forensic case) is not a
  # `</[A-Za-z]+>` shape until it is decoded; #33's blank alone cannot see it.
  # FORENSIC (2026-10-05, measured, SAME DAY as #33/#34's own forensic FPs):
  # a later status report quoting #33's own forensic text (which itself
  # quotes the literal illustration `<code>API_KEY=x</code>,`) was captured
  # into docs/requests/history.md by the §11.4.210 auto-capture hook, then
  # the markdown-to-HTML export correctly entity-escaped those ALREADY-
  # LITERAL angle brackets for safe HTML display (`&lt;code&gt;API_KEY=x
  # &lt;/code&gt;,`) -- detector-1's extraction pipeline had no entity-decode
  # stage of its own (only detector-2's awk program did, via carrier-strip
  # #34), so the escaped tag was never recognised as a tag and the
  # illustration again padded past the 8-char floor: the SAME #33 defect
  # class, reached through a DIFFERENT rendering path. SAFETY identical to
  # #34's own (decode-is-recovery, not a strip -- see #34's doc comment on
  # HELIX_CRED_ADJACENCY_AWK above for the full argument, not duplicated
  # here per §11.4.227 no-drift); sharing ONE conceptual carrier (#34) across
  # BOTH detectors via two mechanical implementations (an awk gsub chain for
  # the line-oriented detector-2, a sed substitution chain here for the
  # stream-oriented detector-1) is itself the no-drift discipline applied to
  # a cross-cutting carrier. Proven by golden-good scenario (v) + the (real
  # secret immediately followed by a doubly-entity-escaped HTML closing tag)
  # golden-bad falsifying control (v-neg) in test_credential_scan_lib.sh
  # (§11.4.107(10)).
  # carrier-strip #35: the SAME bounded-3-pass iterative entity-decode as
  # detector-2's awk program above (shared conceptual carrier, two mechanical
  # implementations per §11.4.227 no-drift -- see that comment for the full
  # double-escaping forensic argument, not duplicated here).
  _helix_cred_d1_matches="$(
    sed -E "s/&quot;/\"/g; s/&#39;/'/g; s/&apos;/'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&quot;/\"/g; s/&#39;/'/g; s/&apos;/'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&quot;/\"/g; s/&#39;/'/g; s/&apos;/'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s#${HELIX_CRED_BASE64_IMAGE_CARRIER}# #g; s#${HELIX_CRED_HTML_CLOSE_TAG_CARRIER}# #g" 2>/dev/null \
      | grep -Eioa "$HELIX_CRED_VALUE_PATTERN" 2>/dev/null
  )"
  # No detector-1 match at all (after #8b) → not a real hit.
  [ -n "$_helix_cred_d1_matches" ] || return 1
  # Drop #8a placeholder-value carriers; a surviving match is a real secret.
  # VERDICT WITHOUT a short-circuiting `| grep -q`: under `set -o pipefail` a
  # `grep -q` that exits 0 at the FIRST survivor SIGPIPE-kills the upstream grep,
  # so the pipeline exits 141 → wrongly CLEAN on a LARGE credential dump (>~64 KB
  # of matches crossing the pipe buffer) (§11.4.201(2) false negative — Fable
  # review B1, proven with a 60k-line probe). Capture survivors into a variable
  # (no pipe short-circuit → no SIGPIPE), then test for any non-whitespace
  # survivor with a case glob. `|| true`: grep -v exits 1 when EVERY match is a
  # placeholder (all stripped) = clean, which must not abort under `set -e`.
  _helix_cred_d1_survivors="$(
    printf '%s\n' "$_helix_cred_d1_matches" \
      | grep -Eiv "$HELIX_CRED_PLACEHOLDER_CARRIER" 2>/dev/null \
      | grep -Eiv "$HELIX_CRED_IDENTIFIER_REFERENCE_CARRIER" 2>/dev/null \
      | grep -Eiv "$HELIX_CRED_ENV_LOOKUP_CARRIER" 2>/dev/null \
      | grep -Eiv "$HELIX_CRED_ACCESSOR_CALL_CARRIER" 2>/dev/null \
      | grep -Ev  "$HELIX_CRED_SYMBOL_REFERENCE_CARRIER" 2>/dev/null \
      | grep -Eiv "$HELIX_CRED_FALLBACK_PLACEHOLDER_CARRIER" 2>/dev/null \
      | grep -Ev  "$HELIX_CRED_AKIA_PLACEHOLDER_CARRIER" 2>/dev/null || true
  )"
  case "$_helix_cred_d1_survivors" in
    *[![:space:]]*) return 0 ;;   # a real (non-placeholder) secret survived
    *)              return 1 ;;   # clean
  esac
}

# FILE variant: delegates to the stream variant so the two share ONE
# implementation of the #8b/extract/#8a/survivor pipeline (§11.4.227 no-drift).
_helix_cred_detector1_real_hit() {
  helix_cred_detector1_real_hit_stream < "$1"
}

# --- Whole-file convenience scanner ------------------------------------------
# Scans a file ON DISK end-to-end. Returns 0 if a credential is found, 1 if
# clean (or the path is unreadable). Runs detector-1 (grep value-pattern), then
# — only if the path is NOT a binary-skip extension — detector-2 (adjacency awk).
# The consuming pre-commit hook scans STAGED content via `git show` and therefore
# uses the exported patterns + helix_cred_is_binary_skip directly rather than
# this helper; this helper is for on-disk scans (golden fixtures, ad-hoc checks).
helix_cred_scan_file() {
  # §11.4.201 carrier-strip #19 (DETECTOR SELF-DEFINITION). This library and its
  # test suite necessarily CONTAIN secret-shaped strings — the detector regexes
  # themselves plus deliberate golden-BAD doc examples (`password: {hunter2hunter2}`,
  # `PASSWORD={CHANGE_ME}`, `AKIA…`). Scanning them flags the very file that defines
  # the scan, so the detector blocks its OWN maintenance: FORENSIC (2026-08-20)
  # this file HIT at HEAD, meaning no commit touching it could ever pass the
  # §11.4.10 seam. That is a §11.4.201(1) false-positive refusal, and it is the
  # bootstrap case every real secret scanner exempts (gitleaks/trufflehog do not
  # scan their own rule files).
  #
  # SAFETY — the exemption is NAME + DEFINITION proven: never name alone, and
  # never a MENTION. Each canonical basename carries its OWN proof, because the
  # two files legitimately differ (the suite defines NO detector pattern —
  # measured: `HELIX_CRED_VALUE_PATTERN=` occurs 0x in it), and every proof is
  # LINE-ANCHORED at an assignment / function-definition form, which a comment
  # can never satisfy (a comment line begins with `#`, excluded by the
  # `^[[:space:]]*` anchor). A file merely RENAMED to credential_scan_lib.sh that
  # merely NAMES these tokens in prose is therefore scanned normally.
  #
  # FORENSIC (2026-08-25, §11.4.201(7)(a) carrier-vs-thing INSIDE the scanner):
  # the previous form was `grep -q A || grep -q B`, unanchored, with B a bare
  # FUNCTION NAME that occurs in this library's own comments — so any file
  # renamed to credential_scan_lib.sh carrying `# helix_cred_scan_file` in a
  # COMMENT was exempted with a real secret (reproduced 3-way). Swapping `||`
  # for `&&` does NOT fix it and is a second bluff in the opposite direction:
  # measured, it (a) still lets a carrier through when the comment names BOTH
  # tokens, and (b) DE-EXEMPTS test_credential_scan_lib.sh (0 pattern hits),
  # resurrecting the §11.4.201(1) false-positive refusal this block exists to
  # cure. Only per-basename ANCHORED DEFINITION proofs are correct in both
  # directions.
  case "$(basename -- "${1:-}")" in
    credential_scan_lib.sh)
      # DEFINES the detector: anchored ASSIGNMENT of the value pattern AND an
      # anchored DEFINITION of this very function.
      if grep -Eq '^[[:space:]]*HELIX_CRED_VALUE_PATTERN=' "${1:-}" 2>/dev/null \
         && grep -Eq '^[[:space:]]*helix_cred_scan_file[[:space:]]*\([[:space:]]*\)' "${1:-}" 2>/dev/null; then
        return 1
      fi
      ;;
    test_credential_scan_lib.sh)
      # IS the golden suite: anchored DEFINITIONS of both of its oracle
      # functions (assert_clean / assert_caught — the two entry points every
      # golden fixture routes through) AND an anchored, executable (non-comment)
      # CALL of the scanner they drive.
      if grep -Eq '^[[:space:]]*assert_clean[[:space:]]*\([[:space:]]*\)' "${1:-}" 2>/dev/null \
         && grep -Eq '^[[:space:]]*assert_caught[[:space:]]*\([[:space:]]*\)' "${1:-}" 2>/dev/null \
         && grep -Eq '^[[:space:]]*(if[[:space:]]+)?!?[[:space:]]*helix_cred_scan_file[[:space:]]' "${1:-}" 2>/dev/null; then
        return 1
      fi
      ;;
  esac
  _helix_cred_path="$1"
  [ -f "$_helix_cred_path" ] || return 1
  # Binary blobs: detector-1 raw grep ONLY (carrier-strip #8 covers text
  # constructs, and detector-2 is skipped for binaries as before).
  if helix_cred_is_binary_skip "$_helix_cred_path"; then
    grep -Eiq "$HELIX_CRED_VALUE_PATTERN" "$_helix_cred_path" 2>/dev/null && return 0
    return 1
  fi
  # (1) keyword-anchored / known-token-format value scan WITH carrier-strip #8
  #     (placeholder-value + base64-image data-URI carriers removed).
  if _helix_cred_detector1_real_hit "$_helix_cred_path"; then
    return 0
  fi
  # (2) email-adjacency heuristic. awk exit 0 = offending line found.
  if awk "$HELIX_CRED_ADJACENCY_AWK" "$_helix_cred_path" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
