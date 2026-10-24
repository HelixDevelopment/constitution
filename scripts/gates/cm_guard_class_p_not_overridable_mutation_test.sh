#!/usr/bin/env bash
# Paired §1.1 mutation test for CM-GUARD-CLASS-P-NOT-OVERRIDABLE.
# Behavioural mutations on an out-of-repo COPY of the guard (the tracked file is
# never edited; its checksum is asserted unchanged):
#   M1  honour the allow marker for class P   -> gate MUST FAIL
#   M2  never block anything                  -> gate MUST FAIL
#   M3  block class H even with the marker    -> gate MUST FAIL (kills a gate that only checks P)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/cm_guard_class_p_not_overridable.sh"
GUARD="$HERE/../hooks/guard-destructive-paths.py"
T="$(mktemp -d)"; trap 'rm -rf "${T:?}"' EXIT
sum0="$(sha256sum "$GUARD" | cut -d' ' -f1)"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "META OK:   $1"; }
bad() { fail=$((fail+1)); echo "META FAIL: $1"; }

GUARD="$GUARD" bash "$GATE" >/dev/null 2>&1 && ok "baseline gate PASSes on the real guard" || bad "baseline gate does not PASS on the real guard"

mut() { # id sed-expr
  sed "$2" "$GUARD" > "$T/$1.py"
  cmp -s "$GUARD" "$T/$1.py" && { bad "$1: mutation did not change the file"; return; }
  python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$T/$1.py" 2>/dev/null || { bad "$1: mutant does not parse"; return; }
  if GUARD="$T/$1.py" bash "$GATE" >/dev/null 2>&1; then bad "$1: gate still PASSes on the mutant"; else ok "$1: gate FAILs on the mutant"; fi
}
mut M1 's/blocking = \[f for f in findings if f\[0\] in hard or marker is None\]/blocking = [f for f in findings if marker is None]/'
mut M2 's/^    if blocking:$/    if False:/'
mut M3 's/blocking = \[f for f in findings if f\[0\] in hard or marker is None\]/blocking = list(findings)/'

sum1="$(sha256sum "$GUARD" | cut -d' ' -f1)"
[ "$sum0" = "$sum1" ] && ok "tracked guard byte-identical after the run" || bad "tracked guard changed"
echo "mutation test: ok=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "META PASS: CM-GUARD-CLASS-P-NOT-OVERRIDABLE is a genuine (non-bluff) gate"
[ "$fail" -eq 0 ]
