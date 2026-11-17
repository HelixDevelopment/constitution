#!/usr/bin/env python3
"""tests/workable_items/secret_shape_fixtures_r11.py -- the round-10 reviewer's probe rows, adopted VERBATIM
(review r10 item 1): 51 positives, 25 negatives (two of them, bypass=... and secretary=..., were reported by
the round-10 scan), and the reviewer's 15 extra positives. The list code below is copied unchanged from the
review's tools/probe_r10_reviewer.py (lines 19 to 106) and tools/probe_r10_extra.py (lines 14 to 32);
every value is FAKE and built from fragments.

Read by tests/workable_items/test_secret_shapes_r11.py (the lint) and by
docs/qa/tracker_intake_2026_11_16_v11/tools/leak_scan_test.py (the scan). Both must report every positive
and no negative. Kept apart from secret_shape_fixtures.py so the round-6 to round-10 pack tools, which read
that file, keep their recorded results (operator decision: the old pack tools stay as they are).
Evidence class: gate-logic only (section 11.4.289).
"""
import base64
import binascii

V = "FA" + "KE" + "r10" + "Zq9xW"   # 12 chars, fake
PW = "pass" + "word"
SC = "".join({"p": "ᴘ", "a": "ᴀ", "s": "s", "w": "ᴡ", "o": "ᴏ", "r": "ʀ",
              "d": "ᴅ"}[c] for c in PW)  # small capitals

POS = [
    # (a) spelling
    ("a01-underscore-every-letter", "p_a_s_s_w_o_r_d=" + V),
    ("a02-spaced-letters", "p a s s w o r d = " + V),
    ("a03-small-capitals", SC + "=" + V),
    ("a04-pwd-odbc", "Server=h;Uid=u;Pwd=" + V + ";"),
    ("a05-pw-short", "db_pw=" + V),
    ("a06-hungarian-accent", "jelszó=" + V),
    ("a07-vietnamese", "mật_khẩu=" + V),
    ("a08-thai", "รหัสผ่าน=" + V),
    ("a09-arabic", "كلمة_المرور=" + V),
    ("a10-persian-ramz", "رمز_عبور=" + V),
    ("a11-lithuanian", "slaptažodis=" + V),
    ("a12-icelandic", "lykilorð=" + V),
    ("a13-swahili", "nenosiri=" + V),
    ("a14-estonian", "salasõna=" + V),
    ("a15-catalan", "contrasenya=" + V),
    ("a16-portuguese-pt", "palavra-passe=" + V),
    ("a17-spanish-clave", "clave=" + V),
    ("a18-greek-rho-alpha", "ραssword=" + V),
    ("a19-cyrillic-upper", "РАSSWОRD=" + V),
    # (b) encoding
    ("b01-hex-whole-line", binascii.hexlify((PW + "=" + V).encode()).decode()),
    ("b02-base32-whole-line", base64.b32encode((PW + "=" + V).encode()).decode()),
    ("b03-python-named-escape", "\\N{LATIN SMALL LETTER P}assword=" + V),
    ("b04-iis-percent-u", "%u0070assword=" + V),
    ("b05-css-escape", "\\70 assword=" + V),
    ("b06-utf16-nul", "\x00".join(PW) + "=" + V),
    ("b07-qp-soft-break", "pass=\nword=" + V),
    ("b08-base64-key-only", base64.b64encode(PW.encode()).decode() + ": " + V),
    # (c) layout
    ("c01-properties-space-sep", "db.password " + V),
    ("c02-makefile-colon-eq", "DB_PASSWORD := " + V),
    ("c03-makefile-q-eq", "DB_PASSWORD ?= " + V),
    ("c04-dockerfile-env-space", "ENV DB_PASSWORD " + V),
    ("c05-curl-user", "curl -u admin:" + V + " https://h.example/"),
    ("c06-mysql-attached-p", "mysql -u root -p" + V + " db"),
    ("c07-sshpass", "sshpass -p " + V + " ssh h"),
    ("c08-netrc", "machine h.example login u " + PW + " " + V),
    ("c09-ldap-bindpw", "bindpw " + V),
    ("c10-sql-identified-by", "CREATE USER u IDENTIFIED BY '" + V + "';"),
    ("c11-yaml-block-scalar", PW + ": |\n  " + V),
    ("c12-k8s-name-value", "- name: DB_PASSWORD\n  value: " + V),
    ("c13-json-key-value-pair", '{"key": "' + PW + '", "value": "' + V + '"}'),
    ("c14-os-environ-assign", 'os.environ["DB_PASSWORD"] = "' + V + '"'),
    ("c15-setenv-call", 'setenv("DB_PASSWORD", "' + V + '", 1);'),
    ("c16-java-setproperty", 'System.setProperty("db.password", "' + V + '");'),
    ("c17-lisp-setq", '(setq ' + PW + ' "' + V + '")'),
    ("c18-clojure-keyword", '{:' + PW + ' "' + V + '"}'),
    ("c19-powershell-securestring", 'ConvertTo-SecureString "' + V + '" -AsPlainText -Force'),
    ("c20-php-dot-concat", "$" + PW + ' = "FAKEr1" . "0Zq9xW";'),
    ("c21-python-kwarg-passwd", 'connect(host="h", passwd="' + V + '")'),
    ("c22-systemd-environment", 'Environment="DB_PASSWORD=' + V + '"'),
    ("c23-docker-run-e", "docker run -e DB_PASSWORD=" + V + " img"),
    ("c24-json-multiline", '"' + PW + '":\n    "' + V + '"'),
]
NEG = [
    ("m01-prose-reset", "the " + PW + " reset link is sent to the user"),
    ("m02-policy", PW + "_policy=strong"),
    ("m03-passwordless", PW + "less=true"),
    ("m04-token-expiry", "token_expiry=3600"),
    ("m05-rotation-days", "api_key_rotation_days=90"),
    ("m06-secret-scanning", "secret_scanning: enabled"),
    ("m07-empty", PW + "="),
    ("m08-redacted", PW + "=<REDACTED>"),
    ("m09-masked", PW + "=********"),
    ("m10-env-ref", PW + "=${DB_PASSWORD}"),
    ("m11-passport", "passport=AB1234567"),
    ("m12-bypass", "bypass=word2vec_model"),
    ("m13-compass", "compass=North7"),
    ("m14-length", PW + "_length: 16"),
    ("m15-secretary", "secretary=Jane_Doe2"),
    ("m16-tokenizer", "tokenizer=bpe_v2"),
    ("m17-token-count", "author_token_count=37421"),
    ("m18-authorization-required", "authorization: required"),
    ("m19-pass-through", "pass-through=enabled"),
    ("m20-session-timeout", "session_timeout=30m"),
    ("m21-cookie-policy", "cookie_policy=strict"),
    ("m22-pinned", "pinned=true"),
    ("m23-keyfile-path", "ssh_key_path=/home/u/.ssh/id_ed25519.pub"),
    ("m24-password-field-label", 'label="' + PW + '"'),
    ("m25-clave-prose", "la clave del problema es simple"),
]


# the reviewer's extra probe
V = "FA" + "KE" + "r10" + "Zq9xW"
PW = "pass" + "word"
EXTRA_POS = [
    ("e01-ecs-name-value-one-line", '{"name": "DB_PASSWORD", "value": "' + V + '"}'),
    ("e02-k8s-flow", "env: [{name: DB_PASSWORD, value: " + V + "}]"),
    ("e03-k8s-one-line-list", "- {name: DB_PASSWORD, value: '" + V + "'}"),
    ("e04-ssm-param", '{"Name": "/prod/db/' + PW + '", "Value": "' + V + '"}'),
    ("e05-key-value-swapped-order", '{"value": "' + V + '", "key": "' + PW + '"}'),
    ("e06-makefile-plus-eq", "DB_PASSWORD += " + V),
    ("e07-makefile-bang-eq", "DB_PASSWORD != echo " + V),
    ("e08-makefile-colon-colon-eq", "DB_PASSWORD ::= " + V),
    ("e09-dot-separated-letters", "p.a.s.s.w.o.r.d=" + V),
    ("e10-dash-separated-letters", "p-a-s-s-w-o-r-d=" + V),
    ("e11-bindpw-ldaprc", "BINDPW " + V),
    ("e12-rootpw", "rootpw " + V),
    ("e13-catalan-upper", "CONTRASENYA=" + V),
    ("e14-hex-upper", ("".join("%02X" % ord(c) for c in PW + "=" + V))),
    ("e15-named-escape-upper", "\\N{LATIN CAPITAL LETTER P}ASSWORD=" + V),
]

