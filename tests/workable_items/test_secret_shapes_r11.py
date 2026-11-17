#!/usr/bin/env python3
"""tests/workable_items/test_secret_shapes_r11.py -- the lint's oracle for the round-10 reviewer's probe rows
(review r10 item 1; the rows are adopted verbatim in secret_shape_fixtures_r11.py).

Documentation (section 11.4.18): docs/guides/intake_lint_guide.md, section "Credential shapes".

WHAT  Loads the lint named on the command line (a path; the mutation suites pass a mutated copy) and runs
      its secret_hits() over every row: each positive (POS, EXTRA_POS) must be reported, with EXACTLY the
      rule names in EXPECT_RULES_R11; each negative (NEG) must be reported by no rule. The reviewer gave
      hit or miss; the rule names are PINNED from the round-11 run (they catch a mutant that only moves a
      shape from one rule to another; they are not reviewer evidence).
      Control needles first (section 11.4.273): a known member must be reported, a prose line must not.
OUTPUT  One line per row with its LABEL only, then "RESULT: pass=N fail=M rows=R".
USAGE   test_secret_shapes_r11.py [<path-of-intake_lint.py>]
EXIT    0 every row as expected; 1 a row failed; 2 usage or load error; 3 BLIND (a control needle failed).
EVIDENCE CLASS  gate-logic only (section 11.4.289).
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import secret_shape_fixtures_r11 as F  # noqa: E402

EXPECT_RULES_R11 = {
    'a01-underscore-every-letter': ('canonical-key',),
    'a02-spaced-letters': ('canonical-key',),
    'a03-small-capitals': ('password-assign-unquoted',),
    'a04-pwd-odbc': ('short-key-assign',),
    'a05-pw-short': ('short-key-assign',),
    'a06-hungarian-accent': ('password-assign-unquoted',),
    'a07-vietnamese': ('canonical-key',),
    'a08-thai': ('canonical-key',),
    'a09-arabic': ('canonical-key',),
    'a10-persian-ramz': ('canonical-key',),
    'a11-lithuanian': ('canonical-key',),
    'a12-icelandic': ('canonical-key',),
    'a13-swahili': ('canonical-key',),
    'a14-estonian': ('canonical-key',),
    'a15-catalan': ('canonical-key',),
    'a16-portuguese-pt': ('canonical-key',),
    'a17-spanish-clave': ('canonical-key',),
    'a18-greek-rho-alpha': ('password-assign-unquoted',),
    'a19-cyrillic-upper': ('password-assign-unquoted',),
    'b01-hex-whole-line': ('canonical-key',),
    'b02-base32-whole-line': ('canonical-key',),
    'b03-python-named-escape': ('canonical-key',),
    'b04-iis-percent-u': ('canonical-key',),
    'b05-css-escape': ('canonical-key',),
    'b06-utf16-nul': ('canonical-key',),
    'b07-qp-soft-break': ('short-key-assign',),
    'b08-base64-key-only': ('canonical-key',),
    'c01-properties-space-sep': ('password-space',),
    'c02-makefile-colon-eq': ('password-assign-unquoted',),
    'c03-makefile-q-eq': ('canonical-key',),
    'c04-dockerfile-env-space': ('password-space',),
    'c05-curl-user': ('short-flag-value',),
    'c06-mysql-attached-p': ('short-flag-value',),
    'c07-sshpass': ('short-flag-value',),
    'c08-netrc': ('password-netrc',),
    'c09-ldap-bindpw': ('canonical-key',),
    'c10-sql-identified-by': ('password-space-quoted',),
    'c11-yaml-block-scalar': ('yaml-block-scalar',),
    'c12-k8s-name-value': ('canonical-record',),
    'c13-json-key-value-pair': ('canonical-record',),
    'c14-os-environ-assign': ('password-assign',),
    'c15-setenv-call': ('argument-pair',),
    'c16-java-setproperty': ('argument-pair',),
    'c17-lisp-setq': ('password-space-quoted',),
    'c18-clojure-keyword': ('password-space-quoted',),
    'c19-powershell-securestring': ('canonical-key',),
    'c20-php-dot-concat': ('password-assign',),
    'c21-python-kwarg-passwd': ('password-assign',),
    'c22-systemd-environment': ('password-assign-unquoted',),
    'c23-docker-run-e': ('password-assign-unquoted',),
    'c24-json-multiline': ('password-assign',),
    'e01-ecs-name-value-one-line': ('canonical-record',),
    'e02-k8s-flow': ('canonical-record',),
    'e03-k8s-one-line-list': ('canonical-record',),
    'e04-ssm-param': ('canonical-record',),
    'e05-key-value-swapped-order': ('canonical-record',),
    'e06-makefile-plus-eq': ('canonical-key',),
    'e07-makefile-bang-eq': ('canonical-key',),
    'e08-makefile-colon-colon-eq': ('canonical-key',),
    'e09-dot-separated-letters': ('canonical-key',),
    'e10-dash-separated-letters': ('canonical-key',),
    'e11-bindpw-ldaprc': ('canonical-key',),
    'e12-rootpw': ('canonical-key',),
    'e13-catalan-upper': ('canonical-key',),
    'e14-hex-upper': ('canonical-key',),
    'e15-named-escape-upper': ('canonical-key',),
}


def load(path):
    spec = importlib.util.spec_from_file_location("intake_lint_under_test_r11", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(HERE, "..", "..", "scripts", "workable-items", "intake_lint.py")
    try:
        lint = load(path)
    except Exception as e:  # noqa: BLE001 - any load failure is a usage error of this oracle
        print("LOAD ERROR: %s" % type(e).__name__)
        return 2

    def rules(t):
        return tuple(sorted({n for n, _ in lint.secret_hits(t)}))
    if not rules(F.PW + "=" + F.V) or rules("plain text line with no key 2026"):
        print("BLIND: a control needle failed")
        return 3
    ok = bad = 0
    for lb, t in F.POS + F.EXTRA_POS:
        got = rules(t)
        if got and got == EXPECT_RULES_R11.get(lb):
            ok += 1
            print("PASS r11 positive %s" % lb)
        else:
            bad += 1
            print("FAIL r11 positive %s (got %s, want %s)" % (lb, ",".join(got) or "none",
                                                            ",".join(EXPECT_RULES_R11.get(lb, ())) or "none"))
    for lb, t in F.NEG:
        got = rules(t)
        if got:
            bad += 1
            print("FAIL r11 negative %s (got %s)" % (lb, ",".join(got)))
        else:
            ok += 1
            print("PASS r11 negative %s" % lb)
    print("RESULT: pass=%d fail=%d rows=%d" % (ok, bad, ok + bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
