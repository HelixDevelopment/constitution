#!/usr/bin/env bash
# tests/release/test_derive_release_facts_provisional_mutants.sh — paired mutations (§1.1) of the rel1 and
# rel2 derivations of scripts/release/derive_release_facts.sh: each mutant is a copy of scripts/release and
# scripts/lib with one line changed back to the broken behaviour; test_derive_release_facts_provisional.sh must
# FAIL on it (and pass on the unmutated copy, the control). Evidence class: gate-logic (PROVISIONAL).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/drf_mut.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
mk(){ local d="$W/$1"; mkdir -p "$d/scripts"; cp -r "$ROOT/scripts/release" "$ROOT/scripts/lib" "$d/scripts/"; echo "$d/scripts/release/derive_release_facts.sh"; }
run(){ DRF_SCRIPT="$1" bash "$HERE/test_derive_release_facts_provisional.sh" >"$W/out" 2>&1; }
S0="$(mk control)"; run "$S0" && ok "control: the unmutated copy passes" || bad "control: the unmutated copy passes"
# M1 (rel1): the marker may be anywhere in the body again (the pre-fix whole-body match)
S1="$(mk m1)"; python3 -I - "$S1" <<'PY' || { bad "M1 could not be applied"; }
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
a="index($0,\"**Verification:** provisional\")==1{print; exit}"
b="index($0,\"**Verification:** provisional\")>0{print; exit}"
assert s.count(a)==1; open(p,'w',encoding='utf-8').write(s.replace(a,b))
PY
run "$S1" && bad "M1 (marker anywhere in a line) is caught" || ok "M1 (marker anywhere in a line) is caught"
# M2 (rel1): fences are not honoured
S2="$(mk m2)"; python3 -I - "$S2" <<'PY' || { bad "M2 could not be applied"; }
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
a="/^```/{f=!f; next} !f && "
assert s.count(a)==1; open(p,'w',encoding='utf-8').write(s.replace(a,""))
PY
run "$S2" && bad "M2 (fences ignored) is caught" || ok "M2 (fences ignored) is caught"
# M3 (rel2): every retest item counts as evidence
S3="$(mk m3)"; python3 -I - "$S3" <<'PY' || { bad "M3 could not be applied"; }
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
a='if [ "$rloc" = Fixed ]; then'
assert s.count(a)==1; open(p,'w',encoding='utf-8').write(s.replace(a,'if [ -n "$rloc" ]; then'))
PY
run "$S3" && bad "M3 (any item is evidence) is caught" || ok "M3 (any item is evidence) is caught"
# M4 (rel2): --require-retest-evidence does not refuse
S4="$(mk m4)"; python3 -I - "$S4" <<'PY' || { bad "M4 could not be applied"; }
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
a='if [ "$REQ_RETEST" -eq 1 ]; then'
assert s.count(a)==1; open(p,'w',encoding='utf-8').write(s.replace(a,'if false; then'))
PY
run "$S4" && bad "M4 (no refusal under --require-retest-evidence) is caught" || ok "M4 (no refusal under --require-retest-evidence) is caught"
# M5 (rel2): an unknown id is cited without a refusal
S5="$(mk m5)"; python3 -I - "$S5" <<'PY' || { bad "M5 could not be applied"; }
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
a='  if [ -z "$rrow" ]; then'
assert s.count(a)==1; open(p,'w',encoding='utf-8').write(s.replace(a,'  if [ -z "$rrow" ] && false; then'))
PY
run "$S5" && bad "M5 (unknown id not refused) is caught" || ok "M5 (unknown id not refused) is caught"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
