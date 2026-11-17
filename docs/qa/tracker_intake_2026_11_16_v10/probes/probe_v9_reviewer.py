"""Independent reviewer probe, round 9 review of vehicle v9. Values are obviously fake (built from
fragments: 'FA'+'KE'+...). Prints labels and verdicts only, never a value."""
import importlib.util, sys, urllib.parse, base64, html

import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

L = load("lint", sys.argv[1])
S = load("scan", sys.argv[2])
V = "FA" + "KE" + "v4" + "lu3Zq9"          # 12 chars, fake
PW = "pass" + "word"

def pct(s, n):
    for _ in range(n):
        s = "".join("%%%02X" % ord(c) for c in s) if _ == 0 else s.replace("%", "%25")
    return s

def ent(s):
    return "".join("&#%d;" % ord(c) for c in s)

POS = [
 # decode layers
 ("q01-pct-1", pct(PW, 1) + "=" + V),
 ("q02-pct-3", pct(PW, 3) + "=" + V),
 ("q03-pct-4-beyond", pct(PW, 4) + "=" + V),
 ("q04-pct-6-beyond", pct(PW, 6) + "=" + V),
 ("q05-entity-in-pct", urllib.parse.quote(ent(PW)) + "=" + V),
 ("q06-entity-no-semicolon", "&#112" + "assword=" + V),
 ("q07-js-brace-escape", "\\u{70}assword=" + V),
 ("q08-py-long-escape", "\\U00000070assword=" + V),
 ("q09-perl-x-brace", "\\x{70}assword=" + V),
 ("q10-base64-whole-line", base64.b64encode((PW + "=" + V).encode()).decode()),
 ("q11-entity-hex-named", "&#x70;&#x61;ssword=" + V),
 ("q12-entity-named-amp-equals", PW + "&equals;" + V),
 ("q13-double-escape", "\\\\u0070assword=" + V),
 # homoglyphs
 ("q14-three-unfolded-homoglyphs", "pɑssŵօrd=" + V),
 ("q15-coptic-cherokee", "ⲣaꮪꮪword=" + V),
 ("q16-serbian-cyrillic-lozinka", "лозинка=" + V),
 ("q17-russian-parol", "пароль=" + V),
 ("q18-math-bold", "".join(chr(0x1D41A + ord(c) - 97) for c in PW) + "=" + V),
 ("q19-fullwidth-sep", PW + "＝" + V),
 # split fragments / syntax
 ("q20-triple-quoted-toml", PW + ' = """' + V + '"""'),
 ("q21-paren-concat-newline", PW + ' = ("FAKEv4"\n    "lu3Zq9")'),
 ("q22-shell-default-expansion", PW + "=${DB_PASSWORD:-" + V + "}"),
 ("q23-md-table-row", "| " + PW + " | " + V + " |"),
 ("q24-r-assign", PW + ' <- "' + V + '"'),
 ("q25-html-input-type", '<input type="' + PW + '" value="' + V + '">'),
 ("q26-powershell-env", '$env:DB_PASSWORD = "' + V + '"'),
 ("q27-passphrase-spaced", 'passphrase: "correct horse battery st4ple"'),
 ("q28-header-x-api-key", "X-Api-Key: " + V),
 ("q29-query-string", "https://h.example/login?user=a&" + PW + "=" + V),
 ("q30-split-across-assign-concat-plus-newline", PW + ' = "FAKEv4" +\n "lu3Zq9"'),
 ("q31-json-escaped-key", '{\\"' + PW + '\\": \\"' + V + '\\"}'),
 ("q32-key-with-space-dash", "pass-word=" + V),
 ("q33-yaml-flow", "{user: a, " + PW + ": " + V + "}"),
 ("q34-sops-yaml-hashicorp", "vault_" + PW + "=" + V),
 ("q35-env-file-export-quoted-single", "export DB_PASS='" + V + "'"),
 ("q36-tcl-set", "set " + PW + " " + V),
 ("q37-lozinka-latin", "lozinka=" + V),
 ("q38-zw-inside-value-only", PW + "=FAKEv4​lu3Zq9"),
 ("q39-key-repeat-4layers-ent-pct", urllib.parse.quote(urllib.parse.quote(ent(PW))) + "=" + V),
 ("q40-gcloud-secret-string", "--secret-string " + V),
]
NEG = [
 ("n01-token-sha256", "token_sha256=" + "9f8e7d6c5b4a" * 5 + "abcd"),
 ("n02-password-sha256", PW + "_sha256: " + "0a1b2c3d4e5f" * 5 + "0a1b"),
 ("n03-key-ticket-id", "key=CON-1234"),
 ("n04-credentials-profile", "credentials: aws-profile-prod2"),
 ("n05-password-env-ref", PW + ": env:DB_PASSWORD"),
 ("n06-pin-year", "pin=2026"),
 ("n07-session-hex", "session 3fa9c1d2"),
 ("n08-keyboard", "keyboard_layout=us-intl2"),
 ("n09-gh-expr", PW + ": ${{ secrets.DB_PASSWORD }}"),
 ("n10-password-min", PW + "_min_length=12345678"),
 ("n11-pass-count", "pass=372/372 fail=0"),
 ("n12-auth-flow", "auth: oauth2-client-credentials-flow"),
 ("n13-token-version", "token: v1.2.3-beta4"),
 ("n14-key-version", "key=6.4.0-rc1-build42"),
 ("n15-secret-name", "secret_name=db-creds-prod2"),
 ("n16-commit-sha-token-word", "token 4b825dc642cb6eb9a060e54bf8d69288fbee4904"),
 ("n17-password-prompt", PW + "_prompt=Enter1Pass"),
 ("n18-uuid-session", "session=3fa9c1d2-0b4e-4c1a-9d2e-7f6a5b4c3d2e"),
 ("n19-cookie-name", "cookie=_ga_GA1.2"),
 ("n20-pwd-path", "PWD=/srv/app/rel2"),
 ("n21-gitlab-var", PW + ": $CI_DB_PASSWORD"),
 ("n22-kubernetes-secretref", "secretKeyRef: db-pass-2"),
 ("n23-item-anchor", "the " + PW + " rule (section 11.4.10) R2"),
 ("n24-hash-of-key", "key_hash=ab12cd34ef56"),
 ("n25-api-key-env-name", "API_KEY_ENV=MY_API_KEY_2"),
]

def lint_hit(t):
    return [n for n, _ in L.secret_hits(t)]

def scan_hit(t):
    return [k for k, _ in S.scan_line(t)]

# control needles
ok_pos = bool(lint_hit(PW + "=" + V)) and bool(scan_hit(PW + "=" + V))
ok_neg = not lint_hit("plain text line with no key 2026") and not scan_hit("plain text line with no key 2026")
print("control_pos=%s control_neg=%s" % (ok_pos, ok_neg))
lg = sg = lf = sf = 0
for lab, t in POS:
    a, b = lint_hit(t), scan_hit(t)
    lg += not a; sg += not b
    print("POS %-45s lint=%s scan=%s" % (lab, "HIT" if a else "MISS", "HIT" if b else "MISS"))
for lab, t in NEG:
    a, b = lint_hit(t), scan_hit(t)
    lf += bool(a); sf += bool(b)
    print("NEG %-45s lint=%s scan=%s %s" % (lab, "FP" if a else "ok", "FP" if b else "ok", ",".join(a)))
print("SUMMARY pos=%d lint_miss=%d scan_miss=%d neg=%d lint_fp=%d scan_fp=%d" % (len(POS), lg, sg, len(NEG), lf, sf))
