"""tests/workable_items/secret_shape_fixtures.py -- the shared credential-shape fixtures (round 8, review
findings N1 to N4).

Documentation (section 11.4.18): docs/guides/intake_lint_guide.md, section "Credential shapes".

WHAT  One list, FIXTURES, of (label, text, want, detail):
        want "hit"  a credential shape: the intake lint must report it with EXACTLY the rule names in
                    detail (a tuple), and the independent leak scan must report it too
        want "miss" not a credential, or a member outside the lint's class: the lint must report no SECRET
                    rule; detail names why ("negative") or the section-B row of
                    docs/qa/tracker_intake_2026_11_15_v8/class_inventory.md ("B1" ...)
      Two oracles read these rows: tests/workable_items/test_secret_shapes.py (the lint) and the leak
      scan's own test (docs/qa/tracker_intake_2026_11_15_v8/tools/leak_scan_test.py). The two scanners
      share no code, only these rows, so a shape one of them cannot see fails that scanner's test.
SOURCES  rv-pos-* and rv-neg-* are the round-8 reviewer's probe lists (probes/probe_r8.py, 51 shapes and
      52 lookalikes), rv-bs-* the reviewer's six backslash values (probes/probe_bs.py), copied verbatim;
      the other rows are the round-8 fixer's own (the new rules, the reviewer mutants RL3 to RL10 and the
      round-7 needles).
SAFETY  Every string is assembled from fragments at import time; no row is a real credential, and no
      scanner prints a row's text (labels only, section 11.4.10).
EVIDENCE CLASS  gate-logic only (section 11.4.289).
"""

PW = "pass" + "word"
V = "Qz7" + "kWm4" + "Rt9p"          # 11 chars, letter + digit
VL = "zqx" + "wvbn" + "mkjh"         # 11 letters only
VS = "Qz7k" + "Wm4!" + "R@t9"        # special chars
V8 = "Zq7" * 2 + "Zq"                # 8 chars, letter + digit
AWS = "AK" + "IA" + "Q" * 16

# ---- the reviewer's 51 credential shapes (probe_r8.py POS), verbatim; want and detail are the round-8 rule
RV_POS = [
    ("rv-pos-php-define", "define('DB_" + PW.upper() + "', '" + V + "');", "hit"),
    ("rv-pos-getenv-default-py", "os.environ.get('DB_" + PW.upper() + "', '" + V + "')", "hit"),
    ("rv-pos-getenv-default-go", 'cfg.Get("' + PW + '", "' + V + '")', "hit"),
    ("rv-pos-setter-java", "ds.set" + PW.capitalize() + '("' + V + '");', "hit"),
    ("rv-pos-ctor-kw-space", PW + ' = "' + V + '"', "hit"),
    ("rv-pos-dotnet-appsettings", '<add key="' + PW.capitalize() + '" value="' + V + '"/>', "hit"),
    ("rv-pos-xml-entry-key", '<entry key="' + PW + '">' + V + '</entry>', "hit"),
    ("rv-pos-mysql-p-joined", "mysql -uroot -p" + V + " db", "hit"),
    ("rv-pos-sshpass-p", "sshpass -p " + V + " ssh h", "hit"),
    ("rv-pos-curl-u", "curl -u admin:" + V + " https://h/x", "hit"),
    ("rv-pos-value-with-other-quote", PW + '="ab\'' + "cd" + "7Qz9k" + '"', "hit"),
    ("rv-pos-value-with-backslash-json", '"' + PW + '": "ab\\\\' + "cd7Qz9k" + '"', "hit"),
    ("rv-pos-value-unicode-escape", '"' + PW + '": "\\u0041' + "bc7Qz9kx" + '"', "hit"),
    ("rv-pos-yaml-block-scalar", PW + ": |\n  " + V, "hit"),
    ("rv-pos-yaml-folded", PW + ": >-\n  " + V, "hit"),
    ("rv-pos-urlencoded-eq", "q?" + PW + "%3D" + V, "hit"),
    ("rv-pos-json-escaped-colon", '{\\"' + PW + '\\":\\"' + V + '\\"}', "hit"),
    ("rv-pos-homoglyph-cyrillic-a", "p\u0430ss" + "word=" + V, "hit"),
    ("rv-pos-zwsp-inside-key", "pass\u200bword=" + V, "hit"),
    ("rv-pos-soft-hyphen-key", "pass\u00adword=" + V, "hit"),
    ("rv-pos-tag-char-key", "pass\U000E0041word=" + V, "hit"),
    ("rv-pos-nbsp-separator", PW + "\u00a0=\u00a0" + V, "hit"),
    ("rv-pos-ideographic-space-flag", "--" + PW + "\u3000" + V, "hit"),
    ("rv-pos-fullwidth-equals", PW + "\uff1d" + V, "hit"),
    ("rv-pos-math-bold-key", "\U0001d429\U0001d41a\U0001d42c\U0001d42c\U0001d430\U0001d428\U0001d42b\U0001d41d=" + V, "hit"),
    ("rv-pos-circled-letters", "\u24df\u24d0\u24e2\u24e2\u24e6\u24de\u24e1\u24d3=" + V, "hit"),
    ("rv-pos-tab-separator", PW + "\t=\t" + V, "hit"),
    ("rv-pos-crlf-line", PW + "=" + V + "\r\n", "hit"),
    ("rv-pos-value-starts-hash", PW + "=#" + "Qz7kWm4R", "hit"),
    ("rv-pos-value-starts-dollar-literal", PW + "='$" + "Qz7kWm4R'", "hit"),
    ("rv-pos-value-starts-gt", "DB_" + PW.upper() + "=>" + V, "hit"),
    ("rv-pos-value-7-chars", PW + "=" + "Qz7kWm4", "B10"),
    ("rv-pos-pwd-letters-only", "MYSQL_PWD=" + VL, "B1"),
    ("rv-pos-pass-colon-quoted-special", 'pass: "' + VS + '"', "hit"),
    ("rv-pos-special-chars-unquoted", PW + "=" + VS, "hit"),
    ("rv-pos-special-in-url", "postgres://u:" + "Qz7k#Wm4@h/db", "hit"),
    ("rv-pos-url-digits-pw", "redis://:" + "12345678" + "@h:6379", "hit"),
    ("rv-pos-url-upper-scheme", "HTTPS://u:" + V + "@h/", "hit"),
    ("rv-pos-key-word", "key=" + V, "B9"),
    ("rv-pos-pin-key", "pin=" + "48213977", "B9"),
    ("rv-pos-cookie-session", "Cookie: session=" + V + V, "B9"),
    ("rv-pos-bearer-short", "Authorization: Bearer " + V, "B12"),
    ("rv-pos-x-api-key-lower", "x-api-key: " + V, "hit"),
    ("rv-pos-token-letters-colon", "token: " + VL, "B4"),
    ("rv-pos-pgpass-line", "h:5432:db:u:" + V, "hit"),
    ("rv-pos-kubectl-flag", "--from-literal=" + PW + "=" + V, "hit"),
    ("rv-pos-env-json-array", '["' + PW.upper() + '", "' + V + '"]', "hit"),
    ("rv-pos-ini-quoted-semicolon", PW + " = '" + V + ";x'", "hit"),
    ("rv-pos-passwd-key", "passwd=" + V, "hit"),
    ("rv-pos-auth-token-camel", "authToken=" + V, "hit"),
    ("rv-pos-secretKey-camel", "secretKey: " + V, "hit"),
]

# ---- the reviewer's 52 benign lookalikes (probe_r8.py NEG), verbatim: none may be reported
RV_NEG = [
    ("rv-neg-env-ref", PW + "=$DB_" + PW.upper()),
    ("rv-neg-brace-ref", PW + ": ${PASS}"),
    ("rv-neg-mask", PW + ': "********"'),
    ("rv-neg-placeholder-angle", PW + "=<redacted>"),
    ("rv-neg-placeholder-upper", "DB_" + PW.upper() + "=YOUR_" + PW.upper() + "_HERE"),
    ("rv-neg-placeholder-changeme", "DB_" + PW.upper() + "=changeme"),
    ("rv-neg-your-api-key-here", "API_KEY=your_api_key_here"),
    ("rv-neg-prose-required", PW + ": required"),
    ("rv-neg-prose-optional", PW + ": optional"),
    ("rv-neg-py-environ", "api_key = os.environ[\"API_KEY\"]"),
    ("rv-neg-py-getpass", PW + " = getpass.getpass()"),
    ("rv-neg-py-request-form", PW + " = request.form['" + PW + "']"),
    ("rv-neg-py-settings", "secret_key = settings.SECRET_KEY"),
    ("rv-neg-py-gen-token", "auth_token = generate_token()"),
    ("rv-neg-passwd-path", "passwd: /etc/passwd"),
    ("rv-neg-nsswitch", "passwd:         files systemd"),
    ("rv-neg-password-hash-col", PW + "_hash = sha256(" + PW + ")"),
    ("rv-neg-passwordless", PW + "less login enabled"),
    ("rv-neg-password-reset-url", PW + "_reset_url=/reset"),
    ("rv-neg-flag-file", "--" + PW + "-file /run/secrets/db"),
    ("rv-neg-flag-ref", "--" + PW + ' "$PW"'),
    ("rv-neg-gh-actions", "token: ${{ secrets.GITHUB_TOKEN }}"),
    ("rv-neg-jinja", PW + ': "{{ vault_' + PW + ' }}"'),
    ("rv-neg-pyformat", PW + ' = "%(' + PW + ')s"'),
    ("rv-neg-auth-true", "AUTH=true"),
    ("rv-neg-pass-label", "PASS: test_case_01"),
    ("rv-neg-bypass", "bypass=abc12345"),
    ("rv-neg-compass", "compass=north123"),
    ("rv-neg-prose-is", "the " + PW + " is stored in the vault"),
    ("rv-neg-prose-policy", PW + " policy2026 applies"),
    ("rv-neg-netrc-prose", "login as root " + PW + " required"),
    ("rv-neg-xml-ref", "<" + PW + ">${DB_PASS}</" + PW + ">"),
    ("rv-neg-xml-example", "<token>example</token>"),
    ("rv-neg-url-port", "http://localhost:8080/api@v2"),
    ("rv-neg-url-host-port-placeholder", "http://host:port/users/@me"),
    ("rv-neg-url-ipv6", "http://[fe80::1]:8080/x@y"),
    ("rv-neg-url-env", "https://oauth2:${CI_JOB_TOKEN}@gitlab.example/x"),
    ("rv-neg-url-gh-actions", "https://x-access-token:${{ secrets.T }}@github.com/x"),
    ("rv-neg-ssh-git", "git@github.com:org/repo.git"),
    ("rv-neg-mailto", "mailto:someone@example.com"),
    ("rv-neg-token-prose", "token: rotated"),
    ("rv-neg-fat-arrow-short", "'" + PW + "' => $pw"),
    ("rv-neg-test-name", "test_" + PW + "_validation_fails"),
    ("rv-neg-css-class", 'class="' + PW + '-field1"'),
    ("rv-neg-i18n-key", PW + ".label=Password"),
    ("rv-neg-sql-column", "SELECT " + PW + "_hash FROM users"),
    ("rv-neg-docs-flag-usage", "--" + PW + " PASSWORD"),
    ("rv-neg-kv-none", PW + "=None"),
    ("rv-neg-pass-through", "pass-through mode2 enabled"),
    ("rv-neg-credentials-path", "credentials: ~/.aws/credentials"),
    ("rv-neg-credentials-file", "credentials=/etc/app/creds.json"),
    ("rv-neg-api-key-header-name", "X-Api-Key header is required"),
]

# ---- the reviewer's six backslash values (probe_bs.py), verbatim: the round-7 regression (N1)
_BS_V = "Qz7k" + "Wm4R"
RV_BS = [
    ("rv-bs-dq-backslash-mid", PW + '="ab\\' + _BS_V + '"'),
    ("rv-bs-json-escaped-bs", '"' + PW + '": "ab\\\\' + _BS_V + '"'),
    ("rv-bs-json-u-escape", '"' + PW + '": "\\u00e9' + _BS_V + '"'),
    ("rv-bs-yaml-dq-escape", PW + ': "a\\tb' + _BS_V + '"'),
    ("rv-bs-sq-backslash", PW + "='C:\\\\x" + _BS_V + "'"),
    ("rv-bs-api-key-json-bs", '"api_key": "' + _BS_V + '\\/' + _BS_V + '"'),
]

# ---- the fixer's own rows (round 8): one positive and one negative per new rule and per front-end
# stage, the shapes the reviewer mutants RL3 to RL10 need, and more members of the class's dimensions
OWN = [
    # backslash values in every quoting (N1): the value class allows an escape sequence
    ("own-bs-backtick", PW + " = `ab\\" + V8 + "`", "hit"),
    ("own-bs-single-mid", PW + "='a\\b" + V8 + "'", "hit"),
    ("own-bs-escaped-quote-inside", PW + '="ab\\"' + V8 + '"', "hit"),
    ("own-bs-unquoted-mid", PW + "=ab\\" + V8, "hit"),
    ("own-bs-short-key", "DB_PA" + 'SS="a\\b' + V8 + '"', "hit"),
    ("own-bs-json-in-string", '{\\"' + PW + '\\": \\"a\\\\\\\\b' + V8 + '\\"}', "hit"),
    ("own-bs-ref-still-ref", PW + '="$\\{DB_PW}"', "negative"),
    # argument pair (N2)
    ("own-argpair-sq", "define('" + PW + "', '" + V8 + "')", "hit"),
    ("own-argpair-backtick", "get(`api_" + "key`, `" + V8 + "`)", "hit"),
    ("own-argpair-short", "cfg.get('db_pa" + "ss', '" + V8 + "')", "hit"),
    ("own-argpair-empty-default", "os.environ.get('DB_" + PW.upper() + "', '')", "negative"),
    ("own-argpair-placeholder", "cfg.get('" + PW + "', 'changeme')", "negative"),
    ("own-argpair-word-key", "log('bypass', '" + V8 + "')", "negative"),
    ("own-argpair-message", "t('" + PW + "', 'Enter the code')", "B15"),
    ("own-argpair-generic-letters", "get('tok" + "en', 'rotation')", "negative"),
    # setter call (N2)
    ("own-setter-snake", "client.set_api_" + "key('" + V8 + "')", "hit"),
    ("own-setter-ref", "ds.setPass" + "word(\"${PW}\")", "negative"),
    ("own-setter-builder", "builder.pass" + "word(\"" + V8 + "\")", "B16"),
    # XML key/value attribute pair (N2)
    ("own-xmlattr-param-name", '<param name="db_pass' + 'word" value="' + V8 + '"/>', "hit"),
    ("own-xmlattr-ref", '<add key="Pass' + 'word" value="$(DB_PW)"/>', "negative"),
    ("own-xmlattr-other-key", '<add key="Pass' + 'wordPolicy" value="' + V8 + '"/>', "negative"),
    ("own-xmlattr-entry-mismatch", '<entry key="pass' + 'word">' + V8 + '</other>', "negative"),
    # a tool's short flag (N2)
    ("own-shortflag-mysqldump", "mysqldump -h db -p" + V8 + " app", "hit"),
    ("own-shortflag-mysql-prompt", "mysql -u root -p app_database", "B17"),
    ("own-shortflag-mysql-port", "mysql -h db -P3306" + "ab", "negative"),
    ("own-shortflag-sshpass-joined", "sshpass -p" + V8 + " ssh h", "hit"),
    ("own-shortflag-sshpass-env", "sshpass -e ssh h", "negative"),
    ("own-shortflag-curl-user", "curl --user bob:" + V8 + " https://h", "hit"),
    ("own-shortflag-curl-ref", "curl -u bob:$TOKEN https://h", "negative"),
    # YAML block scalar (N2)
    ("own-yaml-literal-keep", "api_" + "key: |+\n    " + V8, "hit"),
    ("own-yaml-generic", "tok" + "en: >\n  " + V8, "hit"),
    ("own-yaml-ref", PW + ": |\n  ${DB_PW}", "negative"),
    ("own-yaml-generic-letters", "tok" + "en: |\n  rotationword", "negative"),
    # pgpass (N2)
    ("own-pgpass-star", "*:*:*:u:" + V8, "hit"),
    ("own-pgpass-time", "12:30:45:678:" + "abcdefgh", "negative"),
    # percent-encoded separators and keys (N2)
    ("own-pct-key", "q?pass%77ord=" + V8, "hit"),
    ("own-pct-colon", "pass" + "word%3A%20" + V8, "hit"),
    ("own-pct-ref", "q?" + PW + "%3D%24%7BPW%7D", "negative"),
    # URL schemes in any case (N2)
    ("own-url-mixed-scheme", "Postgres://u:" + V8 + "@h/db", "hit"),
    ("own-url-upper-mask", "HTTPS://u:xxxxxxxx@h/", "negative"),
    ("own-url-xmask", "https://u:" + "x" * 8 + "@h/", "negative"),
    # format characters and lookalikes in a key (N2): SECRET reports them, not only CONTROL-CHAR
    ("own-zwnj-key", "pass\u200cword=" + V8, "hit"),
    ("own-bidi-key", "pass\u202eword=" + V8, "hit"),
    ("own-bom-key", "\ufeff" + PW + "=" + V8, "hit"),
    ("own-greek-omicron", "passw\u03bfrd=" + V8, "hit"),
    ("own-cyrillic-upper", "\u0420ASSWORD=" + V8, "hit"),
    ("own-cyrillic-prose", "\u043f\u0430\u0440\u043e\u043b\u044c " + V8, "negative"),
    ("own-armenian-lookalike", "passw\u0585rd=" + V8, "B18"),
    # single-quoted '$' literal
    ("own-dollar-literal-ref-upper", PW + "='$DB_PASS'", "negative"),
    ("own-dollar-literal-ref-lower", PW + "='$db_pass1'", "negative"),
    ("own-dollar-literal-dq", PW + '="$' + "Qz7kWm4R" + '"', "B19"),
    # code expressions, placeholders, paths (N4)
    ("own-code-call-arg", PW + " = load_secret(" + PW + ")", "negative"),
    ("own-code-attr-digit", PW + "=cfg.db2pass", "hit"),
    ("own-placeholder-here", "API_KEY=paste_key_here", "negative"),
    ("own-placeholder-my", "TOKEN=my-token-1", "negative"),
    ("own-path-dot", PW + "=./secrets/db1.txt", "negative"),
    ("own-path-quoted", PW + ': "/run/secrets/db1"', "B13"),
    # password-space: an identifier key, not a prose word
    ("own-space-upper", "set -gx " + PW.upper() + " " + V8, "hit"),
    ("own-space-title-prose", PW.capitalize() + " reset2026 works", "B14"),
    # reviewer mutant RL5: a tab between the key and the value
    ("own-rl5-tab-space", "DB_" + PW.upper() + "\t" + V8, "hit"),
    ("own-rl5-tab-flag", "--" + PW + "\t" + V8, "hit"),
    # RL3: a quoted value without a space is password-assign only, never password-assign-spaced
    ("own-rl3-no-space", "api_" + 'key = "' + V8 + '"', "hit"),
    # RL4: the XML closing tag must close the opening key
    ("own-rl4-xml-mismatch", "<" + PW + ">" + V8 + "</note>", "negative"),
    # RL6: a generic key's value needs a letter, digits only are a number
    ("own-rl6-digits-colon", "tok" + "en: 123456789", "negative"),
    ("own-rl6-digits-flag", "--tok" + "en 123456789", "negative"),
    ("own-rl6-digits-xml", "<tok" + "en>123456789</tok" + "en>", "negative"),
    # RL7: an x mask in a URL is not a password
    ("own-rl7-url-xmask-upper", "https://u:XXXXXXXX@h/x", "negative"),
    # RL8: a --flag needs a boundary before its dashes
    ("own-rl8-joined-dashes", "abc--tok" + "en " + V8, "negative"),
    # RL10: every rule found on a surface is reported, not only the first
    ("own-rl10-two-rules", AWS + " and " + PW + ' = "' + V8 + '"', "hit"),
    ("own-rl10-three-rules", "DB_" + PW.upper() + "=" + V8 + " --tok" + "en " + V8 + ' <add key="api_' + 'key" value="' + V8 + '"/>', "hit"),
    # one row for each keyed rule the rows above do not reach
    ("own-spaced-value", PW + ' = "Qz7k Wm4R t9"', "hit"),
    ("own-secret-colon", "tok" + "en: " + V8, "hit"),
    ("own-netrc", "machine h login u " + PW + " " + V8, "hit"),
    ("own-escaped-key", '"\\u0070ass' + 'word": "' + V8 + '"', "hit"),
    ("own-space-multipart", "client_" + "secret " + V8, "hit"),
    ("own-short-dot", "DB_PA" + "SS=.env.local1", "negative"),
    ("own-generic-quoted-letters", "tok" + 'en = "rotationword"', "hit"),
    ("own-pwd-ld", "MYSQL_" + "PWD=" + V8, "hit"),
    ("own-auth-ld", "AU" + "TH=" + V8, "hit"),
    ("own-xml-element", "<" + PW + ">" + V8 + "</" + PW + ">", "hit"),
    # mutation survivors of the first round-8 harness run (LR3, LR5, R8-18, R8-34)
    # LR3: an unquoted value starting with ">" is a shell redirect, not a credential
    ("own-lr3-redirect", "DB_PA" + "SSWORD= >build2.log", "negative"),
    # LR5: a JSON string inside a JSON string (escaped quotes around key and value)
    ("own-lr5-double-escaped", "{" + "\\" * 3 + '"' + PW + "\\" * 3 + '":' + "\\" * 3 + '"' + V + "\\" * 3 + '"}', "hit"),
    # R8-18: an upper-case -P is the mysql port flag, never the password flag
    ("own-r818-port", "mysql -h db -P33060123 app", "negative"),
    ("own-r818-port-letters", "mysql -P3306x1y2z3w app", "negative"),
    # R8-34: percent decoding also runs over the escape-decoded view
    ("own-r834-escape-then-percent", "pa%73s" + "\\" + "x77ord=" + V, "hit"),
    ("own-r834-json-escape-then-percent", '"pa%73s' + "\\" + 'u0077ord": "' + V + '"', "hit"),
]

FIXTURES = (
    [(lb, t, "hit" if w == "hit" else "miss", w) for lb, t, w in RV_POS]
    + [(lb, t, "miss", "negative") for lb, t in RV_NEG]
    + [(lb, t, "hit", None) for lb, t in RV_BS]
    + [(lb, t, "hit" if w == "hit" else "miss", w) for lb, t, w in OWN]
)

# the exact rule names the lint reports for each "hit" row (frozen in round 8; a change is a reviewed edit)
EXPECT_RULES = {
    "rv-pos-php-define": ('argument-pair',),
    "rv-pos-getenv-default-py": ('argument-pair',),
    "rv-pos-getenv-default-go": ('argument-pair',),
    "rv-pos-setter-java": ('setter-call',),
    "rv-pos-ctor-kw-space": ('password-assign',),
    "rv-pos-dotnet-appsettings": ('xml-attribute-pair',),
    "rv-pos-xml-entry-key": ('xml-attribute-pair',),
    "rv-pos-mysql-p-joined": ('short-flag-value',),
    "rv-pos-sshpass-p": ('short-flag-value',),
    "rv-pos-curl-u": ('short-flag-value',),
    "rv-pos-value-with-other-quote": ('password-assign',),
    "rv-pos-value-with-backslash-json": ('password-assign',),
    "rv-pos-value-unicode-escape": ('password-assign',),
    "rv-pos-yaml-block-scalar": ('yaml-block-scalar',),
    "rv-pos-yaml-folded": ('yaml-block-scalar',),
    "rv-pos-urlencoded-eq": ('password-assign-unquoted',),
    "rv-pos-json-escaped-colon": ('password-assign',),
    "rv-pos-homoglyph-cyrillic-a": ('password-assign-unquoted',),
    "rv-pos-zwsp-inside-key": ('password-assign-unquoted',),
    "rv-pos-soft-hyphen-key": ('password-assign-unquoted',),
    "rv-pos-tag-char-key": ('password-assign-unquoted',),
    "rv-pos-nbsp-separator": ('password-assign-unquoted',),
    "rv-pos-ideographic-space-flag": ('password-flag-space', 'password-space',),
    "rv-pos-fullwidth-equals": ('password-assign-unquoted',),
    "rv-pos-math-bold-key": ('password-assign-unquoted',),
    "rv-pos-circled-letters": ('password-assign-unquoted',),
    "rv-pos-tab-separator": ('password-assign-unquoted',),
    "rv-pos-crlf-line": ('password-assign-unquoted',),
    "rv-pos-value-starts-hash": ('password-assign-unquoted',),
    "rv-pos-value-starts-dollar-literal": ('password-assign',),
    "rv-pos-value-starts-gt": ('password-assign-unquoted',),
    "rv-pos-pass-colon-quoted-special": ('short-key-assign',),
    "rv-pos-special-chars-unquoted": ('password-assign-unquoted',),
    "rv-pos-special-in-url": ('url-userinfo-password',),
    "rv-pos-url-digits-pw": ('url-userinfo-password',),
    "rv-pos-url-upper-scheme": ('url-userinfo-password',),
    "rv-pos-x-api-key-lower": ('password-colon-unquoted',),
    "rv-pos-pgpass-line": ('pgpass-line',),
    "rv-pos-kubectl-flag": ('password-assign-unquoted',),
    "rv-pos-env-json-array": ('argument-pair',),
    "rv-pos-ini-quoted-semicolon": ('password-assign',),
    "rv-pos-passwd-key": ('password-assign-unquoted',),
    "rv-pos-auth-token-camel": ('password-assign-unquoted',),
    "rv-pos-secretKey-camel": ('password-colon-unquoted',),
    "rv-bs-dq-backslash-mid": ('password-assign',),
    "rv-bs-json-escaped-bs": ('password-assign',),
    "rv-bs-json-u-escape": ('password-assign',),
    "rv-bs-yaml-dq-escape": ('password-assign',),
    "rv-bs-sq-backslash": ('password-assign',),
    "rv-bs-api-key-json-bs": ('password-assign',),
    "own-bs-backtick": ('password-assign',),
    "own-bs-single-mid": ('password-assign',),
    "own-bs-escaped-quote-inside": ('password-assign',),
    "own-bs-unquoted-mid": ('password-assign-unquoted',),
    "own-bs-short-key": ('short-key-assign',),
    "own-bs-json-in-string": ('password-assign',),
    "own-argpair-sq": ('argument-pair',),
    "own-argpair-backtick": ('argument-pair',),
    "own-argpair-short": ('argument-pair',),
    "own-setter-snake": ('setter-call',),
    "own-xmlattr-param-name": ('xml-attribute-pair',),
    "own-shortflag-mysqldump": ('short-flag-value',),
    "own-shortflag-sshpass-joined": ('short-flag-value',),
    "own-shortflag-curl-user": ('short-flag-value',),
    "own-yaml-literal-keep": ('yaml-block-scalar',),
    "own-yaml-generic": ('yaml-block-scalar',),
    "own-pgpass-star": ('pgpass-line',),
    "own-pct-key": ('password-assign-unquoted',),
    "own-pct-colon": ('password-colon-unquoted',),
    "own-url-mixed-scheme": ('url-userinfo-password',),
    "own-zwnj-key": ('password-assign-unquoted',),
    "own-bidi-key": ('password-assign-unquoted',),
    "own-bom-key": ('password-assign-unquoted',),
    "own-greek-omicron": ('password-assign-unquoted',),
    "own-cyrillic-upper": ('password-assign-unquoted',),
    "own-code-attr-digit": ('password-assign-unquoted',),
    "own-space-upper": ('password-space',),
    "own-rl5-tab-space": ('password-space',),
    "own-rl5-tab-flag": ('password-flag-space', 'password-space',),
    "own-rl3-no-space": ('password-assign',),
    "own-rl10-two-rules": ('aws-access-key-id', 'password-assign',),
    "own-rl10-three-rules": ('password-assign-unquoted', 'password-flag-space', 'xml-attribute-pair',),
    "own-spaced-value": ('password-assign-spaced',),
    "own-secret-colon": ('secret-colon-unquoted',),
    "own-netrc": ('password-netrc',),
    "own-escaped-key": ('password-assign',),
    "own-space-multipart": ('password-space',),
    "own-generic-quoted-letters": ('password-assign',),
    "own-pwd-ld": ('short-key-assign',),
    "own-auth-ld": ('short-key-assign',),
    "own-xml-element": ('xml-credential-element',),
    "own-lr5-double-escaped": ('password-assign',),
    "own-r834-escape-then-percent": ('password-assign-unquoted',),
    "own-r834-json-escape-then-percent": ('password-assign',),
}

# control needles of the oracle itself: a known member and a prose line (section 11.4.273)
CONTROL_POSITIVE = "DB_" + PW.upper() + "=" + V8
CONTROL_NEGATIVE = "a plain line with no credential"
