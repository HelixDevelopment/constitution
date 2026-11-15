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
V9 = "FAKE" + "va1ue9Zq"           # the round-9 reviewer's value: 12 chars, letter + digit, says FAKE
B64_9 = "RkFL" + "RXZhMXVlOVpx"     # the round-9 reviewer's base64-looking fake

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
    # B9 and B12 came into the class in round 9 (review r9 F1: the safer reading, documented in
    # class_inventory.md); these rows were "miss" rows of section B before
    ("rv-pos-key-word", "key=" + V, "hit"),
    ("rv-pos-pin-key", "pin=" + "48213977", "hit"),
    ("rv-pos-cookie-session", "Cookie: session=" + V + V, "hit"),
    ("rv-pos-bearer-short", "Authorization: Bearer " + V, "hit"),
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
    ("own-armenian-lookalike", "passw\u0585rd=" + V8, "hit"),  # B18 in the class from round 9
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
    # round 9: the reviewer mutant RV2 (an escaped full-width key needs NFKC after the escape view) and
    # RV12 (a tab inside a value is a table cell, not a credential: a false-positive guard)
    ("own-rv2-escaped-fullwidth-key", '{"\\uff50ass' + 'word": "' + V8 + '"}', "hit"),
    ("own-rv12-tab-in-value", "pw" + 'd="col1\tcol2val9"', "negative"),
]

# ---- the round-9 reviewer's 50 credential shapes (probes/probe_r9.py POS), verbatim (rebuilt from
# fragments, value V9 / B64_9); every one is in the lint's class from round 9 on
R9_POS = [
    ('r9-pos-p01-key-suffix', 'DB_P' + 'ASSW' + 'ORD_' + 'PROD' + '=' + V9),
    ('r9-pos-p02-key-suffix-apikey-v2', 'API_' + 'KEY_' + 'V2=' + V9),
    ('r9-pos-p03-py-bytes', 'pass' + 'word' + '=b"' + V9 + '"'),
    ('r9-pos-p04-py-fstring', 'toke' + 'n = ' + "f'" + V9 + "'"),
    ('r9-pos-p05-py-raw', 'api_' + 'key ' + '= r"' + V9 + '"'),
    ('r9-pos-p06-split-concat-c', 'pass' + 'word' + ' = "' + 'FAKE' + 'va" ' + '"1ue' + '9Zq"'),
    ('r9-pos-p07-split-concat-plus', 'pass' + 'word' + ' = "' + 'FAKE' + 'va" ' + '+ "1' + 'ue9Z' + 'q"'),
    ('r9-pos-p08-sql-identified-by', 'CREA' + 'TE U' + 'SER ' + 'app ' + 'IDEN' + 'TIFI' + 'ED B' + "Y '" + V9 + "';"),
    ('r9-pos-p09-sql-with-password', 'ALTE' + 'R US' + 'ER a' + 'pp W' + 'ITH ' + 'PASS' + 'WORD' + " '" + V9 + "';"),
    ('r9-pos-p10-openssl-pass', 'open' + 'ssl ' + 'pkcs' + '12 -' + 'expo' + 'rt -' + 'pass' + 'out ' + 'pass' + ':' + V9 + ' -ou' + 't x.' + 'p12'),
    ('r9-pos-p11-redis-cli-a', 'redi' + 's-cl' + 'i -h' + ' db ' + '-a ' + V9 + ' pin' + 'g'),
    ('r9-pos-p12-docker-login-p', 'dock' + 'er l' + 'ogin' + ' -u ' + 'bot ' + '-p ' + V9 + ' reg' + 'istr' + 'y.ex' + 'ampl' + 'e'),
    ('r9-pos-p13-azure-accountkey', 'Defa' + 'ultE' + 'ndpo' + 'ints' + 'Prot' + 'ocol' + '=htt' + 'ps;A' + 'ccou' + 'ntNa' + 'me=x' + ';Acc' + 'ount' + 'Key=' + B64_9 + '==;'),
    ('r9-pos-p14-camel-userpass', 'user' + 'Pass' + '=' + V9),
    ('r9-pos-p15-camel-adminpwd', 'admi' + 'nPwd' + '=' + V9),
    ('r9-pos-p16-html-entity-json', '{&qu' + 'ot;p' + 'assw' + 'ord&' + 'quot' + ';: &' + 'quot' + ';' + V9 + '&quo' + 't;}'),
    ('r9-pos-p17-html-numeric-key', 'pass' + '&#11' + '9;or' + 'd=' + V9),
    ('r9-pos-p18-double-percent', 'pass' + '%257' + '7ord' + '=' + V9),
    ('r9-pos-p19-octal-escape-key', '\\160' + 'assw' + 'ord=' + V9),
    ('r9-pos-p20-combining-mark', 'pa\u0301s' + 'swor' + 'd=' + V9),
    ('r9-pos-p21-cgj-in-key', 'pass' + '\u034fwor' + 'd=' + V9),
    ('r9-pos-p22-variation-selector', 'pass' + '\ufe0fwor' + 'd=' + V9),
    ('r9-pos-p23-latin-alpha', 'p\u0251ss' + 'word' + '=' + V9),
    ('r9-pos-p24-small-caps', '\u1d18\u1d00\ua731\ua731' + '\u1d21\u1d0f\u0280\u1d05' + '=' + V9),
    ('r9-pos-p25-armenian-o', 'pass' + 'w\u0585rd' + '=' + V9),
    ('r9-pos-p26-cherokee-mixed', '\u13e2ass' + 'word' + '=' + V9),
    ('r9-pos-p27-german-key', 'pass' + 'wort' + '=' + V9),
    ('r9-pos-p28-signing-key', 'SIGN' + 'ING_' + 'KEY=' + V9),
    ('r9-pos-p29-encryption-key', 'encr' + 'ypti' + 'on_k' + 'ey: ' + V9),
    ('r9-pos-p30-master-key', 'MAST' + 'ER_K' + 'EY=' + V9),
    ('r9-pos-p31-bearer-16', 'Auth' + 'oriz' + 'atio' + 'n: B' + 'eare' + 'r ' + V9 + '123'),
    ('r9-pos-p32-authorization-apikey', 'Auth' + 'oriz' + 'atio' + 'n: A' + 'piKe' + 'y ' + V9 + V9),
    ('r9-pos-p33-htpasswd-b', 'htpa' + 'sswd' + ' -b ' + '/etc' + '/ngi' + 'nx/.' + 'htpa' + 'sswd' + ' adm' + 'in ' + V9),
    ('r9-pos-p34-toml-inline-table', 'db =' + ' { u' + 'ser ' + '= "x' + '", p' + 'assw' + 'ord ' + '= "' + V9 + '" }'),
    ('r9-pos-p35-ini-colon-space-key', 'Pass' + 'word' + ' = ' + V9),
    ('r9-pos-p36-k8s-stringdata-json', '{"st' + 'ring' + 'Data' + '":{"' + 'DB_P' + 'ASS"' + ':"' + V9 + '"}}'),
    ('r9-pos-p37-env-json-escaped-twice', '"{\\\\' + '\\"pa' + 'sswo' + 'rd\\\\' + '\\":\\' + '\\\\"' + V9 + '\\\\\\"' + '}"'),
    ('r9-pos-p38-uuencoded-url-at', 'http' + 's://' + 'bot:' + V9 + '%40x' + '@git' + '.exa' + 'mple' + '/r.g' + 'it'),
    ('r9-pos-p39-line-continuation', 'pass' + 'word' + '=FAK' + 'Eva1' + '\\\nue' + '9Zq'),
    ('r9-pos-p40-hex-escape-value', 'pass' + 'word' + '="\\x' + '46\\x' + '41\\x' + '4b\\x' + '45va' + '1ue9' + 'Zq"'),
    ('r9-pos-p41-mongo-p', 'mong' + 'osh ' + '--us' + 'erna' + 'me b' + 'ot -' + 'p ' + V9),
    ('r9-pos-p42-psql-conninfo', 'psql' + " 'ho" + 'st=d' + 'b us' + 'er=b' + 'ot p' + 'assw' + 'ord=' + V9 + ' dbn' + 'ame=' + "x'"),
    ('r9-pos-p43-unicode-escape-key-json', '{"pa' + 'ss\\u' + '0077' + 'ord"' + ': "' + V9 + '"}'),
    ('r9-pos-p44-fullwidth-equals', 'pass' + 'word' + '\uff1d' + V9),
    ('r9-pos-p45-nbsp-around-sep', 'pass' + 'word' + '\xa0=\xa0' + V9),
    ('r9-pos-p46-tab-sep-tsv', 'pass' + 'word' + '\t' + V9),
    ('r9-pos-p47-key-in-brackets', 'conf' + 'ig[p' + 'assw' + 'ord]' + '=' + V9),
    ('r9-pos-p48-js-object-noquote', '{pas' + 'swor' + "d:'" + V9 + "'}"),
    ('r9-pos-p49-go-struct-backtick', 'Pass' + 'word' + ': `' + V9 + '`,'),
    ('r9-pos-p50-gpg-passphrase', 'gpg ' + '--ba' + 'tch ' + '--pa' + 'ssph' + 'rase' + ' ' + V9 + ' -d ' + 'x.gp' + 'g'),
]
# ---- the round-9 reviewer's 20 lookalikes (probes/probe_r9.py NEG), verbatim: none may be reported
R9_NEG = [
    ('r9-neg-n01-vault-ref', 'pass' + 'word' + ': va' + 'ult:' + 'secr' + 'et/d' + 'ata/' + 'db#p' + 'assw' + 'ord'),
    ('r9-neg-n02-sops-enc', 'pass' + 'word' + ': EN' + 'C[AE' + 'S256' + '_GCM' + ',dat' + 'a:ab' + 'c,iv' + ':def' + ',tag' + ':ghi' + ',typ' + 'e:st' + 'r]'),
    ('r9-neg-n03-test-report', 'resu' + 'lt p' + 'ass=' + 'lint' + '_sui' + 'te_2' + ' fai' + 'l=0'),
    ('r9-neg-n04-ref-plus', 'pass' + 'word' + ': re' + 'f+aw' + 'sssm' + '://p' + 'rod/' + 'db/p' + 'assw' + 'ord'),
    ('r9-neg-n05-k8s-secretkeyref', 'pass' + 'word' + ': se' + 'cret' + 'KeyR' + 'ef.n' + 'ame'),
    ('r9-neg-n06-helm-tpl', 'pass' + 'word' + ': "{' + '{ .V' + 'alue' + 's.db' + '.pas' + 'swor' + 'd }}' + '"'),
    ('r9-neg-n07-gha-secret', 'toke' + 'n: $' + '{{ s' + 'ecre' + 'ts.G' + 'ITHU' + 'B_TO' + 'KEN ' + '}}'),
    ('r9-neg-n08-erb', 'pass' + 'word' + ': <%' + '= EN' + "V['D" + 'B_PA' + 'SSWO' + "RD']" + ' %>'),
    ('r9-neg-n09-placeholder-angle', 'pass' + 'word' + '=<yo' + 'ur-d' + 'b-pa' + 'sswo' + 'rd>'),
    ('r9-neg-n10-masked', 'pass' + 'word' + '=***' + '****' + '****' + '****' + '*'),
    ('r9-neg-n11-getenv', 'pass' + 'word' + ' = o' + 's.ge' + 'tenv' + "('DB" + '_PAS' + 'SWOR' + "D')"),
    ('r9-neg-n12-prose-rule-name', 'the ' + 'pass' + 'word' + '-ass' + 'ign-' + 'unqu' + 'oted' + ' rul' + 'e fi' + 'red'),
    ('r9-neg-n13-token-count', 'toke' + 'n_co' + 'unt=' + '1234' + '5678' + '90'),
    ('r9-neg-n14-url-port', 'http' + '://l' + 'ocal' + 'host' + ':808' + '0/pa' + 'th@v' + '2'),
    ('r9-neg-n15-file-flag', '--pa' + 'sswo' + 'rd-f' + 'ile ' + '/run' + '/sec' + 'rets' + '/db'),
    ('r9-neg-n16-pass-ok', 'PASS' + ': te' + 'st_p' + 'assw' + 'ord_' + 'rota' + 'tion' + '_202' + '6'),
    ('r9-neg-n17-hash-field', 'pass' + 'word' + '_has' + 'h=$a' + 'rgon' + '2id$' + 'v=19' + '$m=6' + '5536'),
    ('r9-neg-n18-doc-example', 'toke' + 'n=ex' + 'ampl' + 'e'),
    ('r9-neg-n19-commit-sha-word', 'the ' + 'secr' + 'et h' + 'its ' + 'were' + ' 235' + ' (se' + 'cret' + '_hit' + 's=23' + '5)'),
    ('r9-neg-n20-azure-keyvault-ref', 'pass' + 'word' + ': @M' + 'icro' + 'soft' + '.Key' + 'Vaul' + 't(Se' + 'cret' + 'Uri=' + 'http' + 's://' + 'kv/s' + 'ecre' + 'ts/d' + 'b)'),
]

# ---- round 9, F4: rows that pin the reviewer's surviving mutants and the round-9 key rules (each row names
# the mutant it kills; the values are the fakes above)
R9_ADOPT = [
    ('r9-adopt-rv2-escaped-fullwidth-key', '{"\\uff50ass' + 'word": "' + V9 + '"}', "hit"),
    ('r9-adopt-rv12-tab-inside-value', 'pwd="col1\tcol2val9"', "negative"),
    ('r9-adopt-rv13-percent-not-at-start', 'x=1 pass%77' + 'ord=' + V9, "hit"),
    ('r9-adopt-rv4-short-key-length-8', 'pwd=' + V8, "hit"),
    ('r9-adopt-ol1-two-letter-qualifier', 'PGid_tok' + 'en: ' + VL, "hit"),
    ('r9-adopt-ol1-two-letter-qualifier-upper', 'PGID_TOK' + 'EN: ' + VL, "hit"),
    # the first round-9 harness run left six mutants alive on surfaces no row held (each row names it)
    ('r9-adopt-rv10-omicron-short-key', 'sessi\u03bfn=' + V8, "hit"),       # RV10, R8-2: a short head has no wildcard
    ('r9-adopt-r85-cyrillic-a-short-key', 'p\u0430ss=' + V8, "hit"),        # R8-5
    ('r9-adopt-ol4-public-key', 'public_' + 'key=' + V8, "negative"),         # OL4: KEY_NEGATIVE
    ('r9-adopt-r825-your-mixed-case', 'pass' + 'word=your_' + 'Secret99', "negative"),  # R8-25: not an identifier
    ('r9-adopt-r830-underscore-key-space', '_pass' + 'word ' + V8, "hit"),   # R8-30: one key word, a separator
    ('r9-adopt-r834-second-view-of-a-layer', 'x\\x41 pass%2526%2523119;ord=' + V9, "hit"),  # R8-34
    # the stale mutants of the first round-9 harness run, remapped onto the round-9 key classifier
    ('r9-adopt-lr1-prefix-joined-head', 'PGPASS' + 'WORD=' + V8, "hit"),     # LR1: SUFFIX_HEADS
    ('r9-adopt-lr18-credentials-key', 'credent' + 'ials=' + V8, "hit"),     # LR18: credential(s)
    ('r9-adopt-lr19-dot-joined-api-key', 'api.' + 'key=' + V8, "hit"),       # LR19: a dot splits a key
    # LR5 (an escaped closing quote): a value written between escaped quotes inside a plain-quoted string,
    # found by tools/equiv_check.py (14 fuzz differences) and reduced by delta debugging
    ('r9-adopt-lr5-escaped-quotes-in-plain-string', 'tok' + 'en="\\"' + V9 + '\\"', "hit"),
    # the independent leak scan's mutation run left the Hangul-filler strip alive: no row held a filler
    # (a non-Cf invisible letter) inside a key word
    ('r9-adopt-scan-hangul-filler-in-key', 'pass\u3164' + 'word=' + V, "hit"),
    ('r9-adopt-scan-choseong-filler-in-key', 'tok\u115f' + 'en=' + V, "hit"),
    # the scan's normalisation steps, each held by a row the lint reports: a Greek letter with a tonos for
    # a Latin one (NFKD takes the tonos off, the fold then reads a Latin letter)
    ('r9-adopt-scan-omicron-tonos-in-token', 't\u03cc' + 'ken=' + V, "hit"),
    ('r9-adopt-scan-epsilon-tonos-for-a', 'p\u03ad' + 'ssword=' + V, "hit"),
    ('r9-adopt-lr5-backtick-escape-close', 'pw' + 'd: `\\q' + V9 + '\\`', "hit"),
]

FIXTURES = (
    [(lb, t, "hit" if w == "hit" else "miss", w) for lb, t, w in RV_POS]
    + [(lb, t, "miss", "negative") for lb, t in RV_NEG]
    + [(lb, t, "hit", None) for lb, t in RV_BS]
    + [(lb, t, "hit" if w == "hit" else "miss", w) for lb, t, w in OWN]
    + [(lb, t, "hit", None) for lb, t in R9_POS]
    + [(lb, t, "miss", "negative") for lb, t in R9_NEG]
    + [(lb, t, "hit" if w == "hit" else "miss", w) for lb, t, w in R9_ADOPT]
)

# the exact rule names the lint reports for each "hit" row (frozen in round 8, extended in round 9; a change
# is a reviewed edit)
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
    "rv-pos-ideographic-space-flag": ('password-flag-space',),
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
    "own-rl5-tab-flag": ('password-flag-space',),
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
    # round 9: the B9, B12 and B18 rows that came into the class, RV2, and the round-9 reviewer's 50 shapes
    'rv-pos-key-word': ('short-key-assign',),
    'rv-pos-pin-key': ('short-key-assign',),
    'rv-pos-cookie-session': ('short-key-assign',),
    'rv-pos-bearer-short': ('authorization-header',),
    'own-armenian-lookalike': ('password-assign-unquoted',),
    'own-rv2-escaped-fullwidth-key': ('password-assign',),
    'r9-pos-p01-key-suffix': ('password-assign-unquoted',),
    'r9-pos-p02-key-suffix-apikey-v2': ('password-assign-unquoted',),
    'r9-pos-p03-py-bytes': ('password-assign',),
    'r9-pos-p04-py-fstring': ('password-assign',),
    'r9-pos-p05-py-raw': ('password-assign',),
    'r9-pos-p06-split-concat-c': ('password-assign',),
    'r9-pos-p07-split-concat-plus': ('password-assign',),
    'r9-pos-p08-sql-identified-by': ('password-space-quoted',),
    'r9-pos-p09-sql-with-password': ('password-space-quoted',),
    'r9-pos-p10-openssl-pass': ('short-flag-value',),
    'r9-pos-p11-redis-cli-a': ('short-flag-value',),
    'r9-pos-p12-docker-login-p': ('short-flag-value',),
    'r9-pos-p13-azure-accountkey': ('password-assign-unquoted',),
    'r9-pos-p14-camel-userpass': ('short-key-assign',),
    'r9-pos-p15-camel-adminpwd': ('short-key-assign',),
    'r9-pos-p16-html-entity-json': ('password-assign',),
    'r9-pos-p17-html-numeric-key': ('password-assign-unquoted',),
    'r9-pos-p18-double-percent': ('password-assign-unquoted',),
    'r9-pos-p19-octal-escape-key': ('password-assign-unquoted',),
    'r9-pos-p20-combining-mark': ('password-assign-unquoted',),
    'r9-pos-p21-cgj-in-key': ('password-assign-unquoted',),
    'r9-pos-p22-variation-selector': ('password-assign-unquoted',),
    'r9-pos-p23-latin-alpha': ('password-assign-unquoted',),
    'r9-pos-p24-small-caps': ('password-assign-unquoted',),
    'r9-pos-p25-armenian-o': ('password-assign-unquoted',),
    'r9-pos-p26-cherokee-mixed': ('password-assign-unquoted',),
    'r9-pos-p27-german-key': ('password-assign-unquoted',),
    'r9-pos-p28-signing-key': ('password-assign-unquoted',),
    'r9-pos-p29-encryption-key': ('password-colon-unquoted',),
    'r9-pos-p30-master-key': ('password-assign-unquoted',),
    'r9-pos-p31-bearer-16': ('authorization-header',),
    'r9-pos-p32-authorization-apikey': ('password-space', 'authorization-header'),
    'r9-pos-p33-htpasswd-b': ('short-flag-value',),
    'r9-pos-p34-toml-inline-table': ('password-assign',),
    'r9-pos-p35-ini-colon-space-key': ('password-assign-unquoted',),
    'r9-pos-p36-k8s-stringdata-json': ('short-key-assign',),
    'r9-pos-p37-env-json-escaped-twice': ('password-assign',),
    'r9-pos-p38-uuencoded-url-at': ('url-userinfo-password',),
    'r9-pos-p39-line-continuation': ('password-assign-unquoted',),
    'r9-pos-p40-hex-escape-value': ('password-assign',),
    'r9-pos-p41-mongo-p': ('short-flag-value',),
    'r9-pos-p42-psql-conninfo': ('password-assign-unquoted',),
    'r9-pos-p43-unicode-escape-key-json': ('password-assign',),
    'r9-pos-p44-fullwidth-equals': ('password-assign-unquoted',),
    'r9-pos-p45-nbsp-around-sep': ('password-assign-unquoted',),
    'r9-pos-p46-tab-sep-tsv': ('password-space',),
    'r9-pos-p47-key-in-brackets': ('password-assign-unquoted',),
    'r9-pos-p48-js-object-noquote': ('password-assign',),
    'r9-pos-p49-go-struct-backtick': ('password-assign',),
    'r9-pos-p50-gpg-passphrase': ('password-flag-space',),
    'r9-adopt-rv2-escaped-fullwidth-key': ('password-assign',),
    'r9-adopt-rv13-percent-not-at-start': ('password-assign-unquoted',),
    'r9-adopt-rv4-short-key-length-8': ('short-key-assign',),
    'r9-adopt-ol1-two-letter-qualifier': ('password-colon-unquoted',),
    'r9-adopt-ol1-two-letter-qualifier-upper': ('password-colon-unquoted',),
    'r9-adopt-scan-hangul-filler-in-key': ('password-assign-unquoted',),
    'r9-adopt-scan-choseong-filler-in-key': ('password-assign-unquoted',),
    'r9-adopt-scan-omicron-tonos-in-token': ('password-assign-unquoted',),
    'r9-adopt-scan-epsilon-tonos-for-a': ('password-assign-unquoted',),
    'r9-adopt-rv10-omicron-short-key': ('short-key-assign',),
    'r9-adopt-r85-cyrillic-a-short-key': ('short-key-assign',),
    'r9-adopt-r830-underscore-key-space': ('password-space',),
    'r9-adopt-r834-second-view-of-a-layer': ('password-assign-unquoted',),
    'r9-adopt-lr1-prefix-joined-head': ('password-assign-unquoted',),
    'r9-adopt-lr18-credentials-key': ('password-assign-unquoted',),
    'r9-adopt-lr19-dot-joined-api-key': ('password-assign-unquoted',),
    'r9-adopt-lr5-escaped-quotes-in-plain-string': ('password-assign', 'password-assign-unquoted'),
    'r9-adopt-lr5-backtick-escape-close': ('short-key-assign',),
}

# control needles of the oracle itself: a known member and a prose line (section 11.4.273)
CONTROL_POSITIVE = "DB_" + PW.upper() + "=" + V8
CONTROL_NEGATIVE = "a plain line with no credential"


def selfcheck():
    """The rows' own invariants (round 9: the module is a full-suite entry, not an excluded helper): every
    label once, want in {hit, miss}, a hit row with a non-empty rule tuple in EXPECT_RULES, a miss row with
    a reason, no EXPECT_RULES entry for a label that is not a hit row, and the reviewer lists at their
    verbatim sizes.
    Returns a list of problems (labels only, never a row's text, section 11.4.10)."""
    probs = []
    labels = [r[0] for r in FIXTURES]
    seen = set()
    for lab in labels:
        if lab in seen:
            probs.append("label twice: %s" % lab)
        seen.add(lab)
    hits = {}
    for r in FIXTURES:
        if len(r) != 4 or not isinstance(r[1], str) or not r[1]:
            probs.append("row shape: %s" % r[0])
            continue
        lab, _text, want, detail = r
        if want == "hit":
            hits[lab] = detail
            rules = EXPECT_RULES.get(lab)
            if not isinstance(rules, tuple) or not rules or not all(isinstance(x, str) and x for x in rules):
                probs.append("hit row without a rule tuple in EXPECT_RULES: %s" % lab)
        elif want == "miss":
            if not isinstance(detail, str) or not detail:
                probs.append("miss row without a reason: %s" % lab)
        else:
            probs.append("want not hit/miss: %s" % lab)
    for lab in EXPECT_RULES:
        if lab not in hits:
            probs.append("EXPECT_RULES names a label that is not a hit row: %s" % lab)
    for name, lst, n in (("RV_POS", RV_POS, 51), ("RV_NEG", RV_NEG, 52), ("RV_BS", RV_BS, 6),
                         ("R9_POS", R9_POS, 50), ("R9_NEG", R9_NEG, 20)):
        if len(lst) != n:
            probs.append("%s holds %d rows, the reviewer's list holds %d" % (name, len(lst), n))
    if CONTROL_POSITIVE == CONTROL_NEGATIVE:
        probs.append("the control needles are equal")
    return probs


if __name__ == "__main__":
    import sys
    p = selfcheck()
    for x in p:
        print("FAIL " + x)
    print("RESULT rows=%d hit=%d problems=%d" % (len(FIXTURES), sum(1 for r in FIXTURES if r[2] == "hit"), len(p)))
    sys.exit(1 if p else 0)
