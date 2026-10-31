#!/usr/bin/env bash
# test_is_locked_contract.sh — canon self-scan item 2 (docs/design/canon_self_scan_triage_2026_10_31.md):
# is_locked() returns False for a key spec_for refuses. Measured verdict: ACCEPTABLE, because no caller can
# reach a store with such a key. This suite pins that: (a) is_locked contract, (b) every writer path refuses an
# unknown/malformed key with a named error and writes nothing, (c) determinism x3, (d) paired §1.1 mutation:
# making is_locked fail OPEN in the other direction (True) or letting dump_file skip validation is DETECTED.
set -u
export CONSTITUTION_JEV_HOOK=off PYTHONDONTWRITEBYTECODE=1
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(cd "$here/../.." && pwd)"
ENG="$repo/scripts/decisions"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT
fail=0
chk() { if [ "$2" = 1 ]; then echo "ok $1"; else echo "NOT ok $1"; fail=1; fi; }
probe() { # $1 engine dir -> prints a verdict line
  python3 -I - "$1" <<'P'
import sys
sys.path.insert(0, sys.argv[1])
import decisions_engine as d
out = []
out.append("locked_known=%s" % d.is_locked("keys.var_names"))
for k in ("bogus.key", "question_types.X", "agents.nonesuch", ""):
    try: out.append("%s=%s" % (k or "empty", d.is_locked(k)))
    except Exception as e: out.append("%s=EXC:%s" % (k or "empty", type(e).__name__))
try:
    d.dump_file("constitution/x.yaml", {"bogus.key": 1}); out.append("dump=WROTE")
except d.Refused: out.append("dump=Refused")
try:
    d.validate_map({"bogus.key": 1}, "t"); out.append("validate=ACCEPTED")
except d.Refused: out.append("validate=Refused")
out.append("drop_known_kept=%s" % ("layer.mode" in d.drop_locked({"layer.mode": "shadow"})))
print(" ".join(out))
P
}
v1=$(probe "$ENG"); echo "$v1"
chk "contract: known lock True; unknown keys False (no raise)" "$(case "$v1" in *locked_known=True*bogus.key=False*question_types.X=False*agents.nonesuch=False*empty=False*) echo 1;; esac)"
chk "writers refuse unknown key (dump_file + validate_map)" "$(case "$v1" in *dump=Refused*validate=Refused*) echo 1;; esac)"
chk "known key still kept by drop_locked" "$(case "$v1" in *drop_known_kept=True*) echo 1;; esac)"
d=1; for i in 1 2 3; do [ "$(probe "$ENG")" = "$v1" ] || d=0; done; chk "determinism x3 / idempotent" "$d"
# paired mutation: dump_file's validation removed -> unknown key is WRITTEN (the test above would FAIL = detected)
mkdir -p "$TMP/m"; cp "$ENG"/decisions_engine.py "$TMP/m/"
python3 -I - "$TMP/m/decisions_engine.py" <<'P'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'if not KEY_SHAPE_RE.fullmatch(k) or looks_secret(k) or is_locked(k):'
assert s.count(a) == 1
s = s.replace(a, 'if False:')
b = '    if back != decisions or data.get("inherits") != inherits or text.count("\\n") != len(lines):'
assert s.count(b) == 1
s = s.replace(b, '    if False:')
c = '    back = parse_override_data(data, "dumped decisions")'
assert s.count(c) == 1
s = s.replace(c, '    back = decisions')
open(p, "w").write(s)
P
vm=$(probe "$TMP/m")
chk "mutation: guards removed -> dump WROTE an unknown key (mutant killed)" "$(case "$vm" in *dump=WROTE*) echo 1;; esac)"
[ $fail = 0 ] && echo "ALL OK" || echo "FAILED"; exit $fail
