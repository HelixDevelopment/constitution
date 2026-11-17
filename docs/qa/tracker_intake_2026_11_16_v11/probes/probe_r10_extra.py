"""Reviewer probe, follow-up variants of the round-10 misses (fake values, labels only).
usage: probe_r10_extra.py LINT SCAN"""
import importlib.util, sys


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


L = load("lint", sys.argv[1]); S = load("scan", sys.argv[2])
V = "FA" + "KE" + "r10" + "Zq9xW"
PW = "pass" + "word"
POS = [
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
for lb, t in POS:
    a = [n for n, _ in L.secret_hits(t)]; b = [k for k, _ in S.scan_line(t)]
    print("POS %-32s lint=%s scan=%s" % (lb, "HIT" if a else "MISS", "HIT" if b else "MISS"))
