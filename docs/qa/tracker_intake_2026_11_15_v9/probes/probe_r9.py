"""Reviewer r9 probe: new secret shapes (values are obviously fake: they contain FAKE). Prints labels only."""
import importlib.util, sys, time

import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
spec = importlib.util.spec_from_file_location("lint", sys.argv[1])
L = importlib.util.module_from_spec(spec)
spec.loader.exec_module(L)

V = "FAKEva1ue9Zq"   # 12 chars, letters + digits, obviously fake
B64 = "RkFLRXZhMXVlOVpx"  # base64-looking fake
# (id, text, should_hit)
POS = [
    ("p01-key-suffix", "DB_PASSWORD_PROD=%s" % V),
    ("p02-key-suffix-apikey-v2", "API_KEY_V2=%s" % V),
    ("p03-py-bytes", 'password=b"%s"' % V),
    ("p04-py-fstring", "token = f'%s'" % V),
    ("p05-py-raw", 'api_key = r"%s"' % V),
    ("p06-split-concat-c", 'password = "FAKEva" "1ue9Zq"'),
    ("p07-split-concat-plus", 'password = "FAKEva" + "1ue9Zq"'),
    ("p08-sql-identified-by", "CREATE USER app IDENTIFIED BY '%s';" % V),
    ("p09-sql-with-password", "ALTER USER app WITH PASSWORD '%s';" % V),
    ("p10-openssl-pass", "openssl pkcs12 -export -passout pass:%s -out x.p12" % V),
    ("p11-redis-cli-a", "redis-cli -h db -a %s ping" % V),
    ("p12-docker-login-p", "docker login -u bot -p %s registry.example" % V),
    ("p13-azure-accountkey", "DefaultEndpointsProtocol=https;AccountName=x;AccountKey=%s==;" % B64),
    ("p14-camel-userpass", "userPass=%s" % V),
    ("p15-camel-adminpwd", "adminPwd=%s" % V),
    ("p16-html-entity-json", "{&quot;password&quot;: &quot;%s&quot;}" % V),
    ("p17-html-numeric-key", "pass&#119;ord=%s" % V),
    ("p18-double-percent", "pass%%2577ord=%s" % V),
    ("p19-octal-escape-key", "\\160assword=%s" % V),
    ("p20-combining-mark", "pa\u0301ssword=%s" % V),
    ("p21-cgj-in-key", "pass\u034fword=%s" % V),
    ("p22-variation-selector", "pass\ufe0fword=%s" % V),
    ("p23-latin-alpha", "p\u0251ssword=%s" % V),
    ("p24-small-caps", "\u1d18\u1d00\ua731\ua731\u1d21\u1d0f\u0280\u1d05=%s" % V),
    ("p25-armenian-o", "passw\u0585rd=%s" % V),
    ("p26-cherokee-mixed", "\u13e2assword=%s" % V),
    ("p27-german-key", "passwort=%s" % V),
    ("p28-signing-key", "SIGNING_KEY=%s" % V),
    ("p29-encryption-key", "encryption_key: %s" % V),
    ("p30-master-key", "MASTER_KEY=%s" % V),
    ("p31-bearer-16", "Authorization: Bearer FAKEva1ue9Zq123"),
    ("p32-authorization-apikey", "Authorization: ApiKey %s%s" % (V, V)),
    ("p33-htpasswd-b", "htpasswd -b /etc/nginx/.htpasswd admin %s" % V),
    ("p34-toml-inline-table", "db = { user = \"x\", password = \"%s\" }" % V),
    ("p35-ini-colon-space-key", "Password = %s" % V),
    ("p36-k8s-stringdata-json", '{"stringData":{"DB_PASS":"%s"}}' % V),
    ("p37-env-json-escaped-twice", '"{\\\\\\"password\\\\\\":\\\\\\"%s\\\\\\"}"' % V),
    ("p38-uuencoded-url-at", "https://bot:%s%%40x@git.example/r.git" % V),
    ("p39-line-continuation", "password=FAKEva1\\\nue9Zq"),
    ("p40-hex-escape-value", 'password="\\x46\\x41\\x4b\\x45va1ue9Zq"'),
    ("p41-mongo-p", "mongosh --username bot -p %s" % V),
    ("p42-psql-conninfo", "psql 'host=db user=bot password=%s dbname=x'" % V),
    ("p43-unicode-escape-key-json", '{"pass\\u0077ord": "%s"}' % V),
    ("p44-fullwidth-equals", "password\uff1d%s" % V),
    ("p45-nbsp-around-sep", "password\u00a0=\u00a0%s" % V),
    ("p46-tab-sep-tsv", "password\t%s" % V),
    ("p47-key-in-brackets", "config[password]=%s" % V),
    ("p48-js-object-noquote", "{password:'%s'}" % V),
    ("p49-go-struct-backtick", "Password: `%s`," % V),
    ("p50-gpg-passphrase", "gpg --batch --passphrase %s -d x.gpg" % V),
]
NEG = [
    ("n01-vault-ref", "password: vault:secret/data/db#password"),
    ("n02-sops-enc", "password: ENC[AES256_GCM,data:abc,iv:def,tag:ghi,type:str]"),
    ("n03-test-report", "result pass=lint_suite_2 fail=0"),
    ("n04-ref-plus", "password: ref+awsssm://prod/db/password"),
    ("n05-k8s-secretkeyref", "password: secretKeyRef.name"),
    ("n06-helm-tpl", 'password: "{{ .Values.db.password }}"'),
    ("n07-gha-secret", "token: ${{ secrets.GITHUB_TOKEN }}"),
    ("n08-erb", "password: <%= ENV['DB_PASSWORD'] %>"),
    ("n09-placeholder-angle", "password=<your-db-password>"),
    ("n10-masked", "password=****************"),
    ("n11-getenv", "password = os.getenv('DB_PASSWORD')"),
    ("n12-prose-rule-name", "the password-assign-unquoted rule fired"),
    ("n13-token-count", "token_count=1234567890"),
    ("n14-url-port", "http://localhost:8080/path@v2"),
    ("n15-file-flag", "--password-file /run/secrets/db"),
    ("n16-pass-ok", "PASS: test_password_rotation_2026"),
    ("n17-hash-field", "password_hash=$argon2id$v=19$m=65536"),
    ("n18-doc-example", "token=example"),
    ("n19-commit-sha-word", "the secret hits were 235 (secret_hits=235)"),
    ("n20-azure-keyvault-ref", "password: @Microsoft.KeyVault(SecretUri=https://kv/secrets/db)"),
]

def hits(t):
    return [n for n, _ in L.secret_hits(t)]

miss = []
for i, t in POS:
    h = hits(t)
    print("POS %s %s %s" % (i, "HIT" if h else "MISS", ",".join(h)))
    if not h:
        miss.append(i)
fp = []
for i, t in NEG:
    h = hits(t)
    print("NEG %s %s %s" % (i, "FP" if h else "ok", ",".join(h)))
    if h:
        fp.append(i)
print("SUMMARY pos=%d miss=%d neg=%d fp=%d" % (len(POS), len(miss), len(NEG), len(fp)))
print("MISSED", " ".join(miss))
print("FPS", " ".join(fp))
# control needle
assert hits("password=%s" % V), "control needle blind"
print("CONTROL positive ok; negative:", hits("hello world") == [])

# ReDoS / long-line timing
cases = {
    "password-eq-repeat": "password=" * 20000,
    "backslash-run": 'password="' + "\\" * 40000,
    "quote-backslash-mix": 'token="' + '\\"' * 20000,
    "dash-ident-run": "-" * 40000 + "password x",
    "word-run-no-key": "a" * 100000,
    "dot-run-space": "." * 40000 + "passwordx 9",
    "xml-open-run": "<password " * 8000,
    "xml-attr-run": '<a key="password" ' * 5000,
    "url-colon-run": "a://" + ":" * 40000,
    "pgpass-colon-run": "a:1:" + "b:" * 20000,
    "flag-run": "--" + "x" * 40000 + "token",
    "yaml-block-run": "password: |\n" + " " * 40000,
    "pct-run": "%41" * 30000,
    "uescape-run": "\\u0041" * 20000,
    "mysql-run": "mysql " + "a " * 20000,
    "space-key-run": "x_" * 30000 + "password",
    "colon-many": "token:" * 15000,
}
for k, t in cases.items():
    t0 = time.perf_counter(); L.secret_hits(t) and None; list(L.secret_hits(t)); dt = time.perf_counter() - t0
    print("TIME %-22s len=%7d %.3fs" % (k, len(t), dt))
