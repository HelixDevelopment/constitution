"""Independent reviewer probe, round 10. Fake values built from fragments. Prints labels and verdicts
only, never a value. usage: probe_r10_reviewer.py LINT SCAN FIXTURES"""
import importlib.util, sys, base64, binascii, os
for v in ("GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY "
          "GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE").split():
    os.environ.pop(v, None)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


L = load("lint", sys.argv[1])
S = load("scan", sys.argv[2])
F = load("fix", sys.argv[3])
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


def lint_hit(t):
    return [n for n, _ in L.secret_hits(t)]


def scan_hit(t):
    return [k for k, _ in S.scan_line(t)]


fixtexts = {t for _, t, *_ in F.FIXTURES}
ok_pos = bool(lint_hit(PW + "=" + V)) and bool(scan_hit(PW + "=" + V))
ok_neg = not lint_hit("plain text line with no key 2026") and not scan_hit("plain text line with no key 2026")
print("control_pos=%s control_neg=%s" % (ok_pos, ok_neg))
dup = [lb for lb, t in POS + NEG if t in fixtexts]
print("in_fixtures=%d %s" % (len(dup), ",".join(dup)))
lm = sm = lf = sf = 0
for lb, t in POS:
    a, b = lint_hit(t), scan_hit(t)
    lm += not a; sm += not b
    print("POS %-34s lint=%s scan=%s" % (lb, "HIT" if a else "MISS", "HIT" if b else "MISS"))
for lb, t in NEG:
    a, b = lint_hit(t), scan_hit(t)
    lf += bool(a); sf += bool(b)
    print("NEG %-34s lint=%s scan=%s %s" % (lb, "FP" if a else "ok", "FP" if b else "ok", ",".join(a)))
print("SUMMARY pos=%d lint_miss=%d scan_miss=%d neg=%d lint_fp=%d scan_fp=%d"
      % (len(POS), lm, sm, len(NEG), lf, sf))
