#!/usr/bin/env bash
# test_helix_deps_field.sh — scripts/deps_manifest/helix_deps_field.py: structural field reader + refusal codes.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$HERE/../../scripts/deps_manifest/helix_deps_field.py"
T="$(mktemp -d)"; trap 'rm -rf "${T:?}"' EXIT
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: want [$2] got [$3]"; fi; }
run() { # run <text> <name> <fields...> -> OUT, RC
  printf '%s' "$1" > "$T/m.yaml"; shift
  OUT="$(python3 -I "$PY" "$T/m.yaml" "$@" 2>/dev/null)"; RC=$?; }
US=$'\x1f'
run $'deps:\n  - name: a\n    ref: r1\n    recursive_init: false\n' a ref recursive_init missing; chk plain "r1${US}false${US}" "$OUT"; chk plain-rc 0 "$RC"
run $'deps:\n  -\n    name: a\n    ref: r1\n' a ref; chk bare "r1" "$OUT"
run $'deps:\n  - "name": a\n    "ref": r1\n' a ref; chk quoted "r1" "$OUT"
run $'deps:\n  - name : a\n    ref : r1\n' a ref; chk spc "r1" "$OUT"
run $'deps:\n  - name: a\n    ref: "r1"  # c\n' a ref; chk comment "r1" "$OUT"
run $'deps:\n  - name: b\n    ref: r2\n' a ref; chk notfound-rc 9 "$RC"; chk notfound-out "" "$OUT"
run $'deps:\n  - name: a\n    ref: r1\n    ref: r2\n' a ref; chk dup-rc 4 "$RC"; chk dup-out "" "$OUT"
run $'deps:\n  - name: a\n  - name: a\n' a ref; chk ambiguous-rc 6 "$RC"
run $'deps: [x\n' a ref; chk unparseable-rc 4 "$RC"
run $'- a\n' a ref; chk toplevel-rc 6 "$RC"
run $'deps:\n  - name: a\n    ref: [x]\n' a ref; chk nonstring-rc 6 "$RC"
run $'deps:\n' a ref; chk empty-rc 9 "$RC"
printf 'deps:\n  - name: a\n    ref: r\n' > "$T/m.yaml"
OUT="$(HELIX_TEST_MODE=1 HELIX_DEPS_FIELD_FORCE_NO_YAML=1 python3 -I "$PY" "$T/m.yaml" a ref 2>/dev/null)"; RC=$?; chk noyaml-rc 3 "$RC"; chk noyaml-out "" "$OUT"
python3 -I "$PY" "$T/absent.yaml" a ref >/dev/null 2>&1; chk unreadable-rc 4 "$?"
python3 -I "$PY" "$T/m.yaml" a >/dev/null 2>&1; chk usage-rc 7 "$?"
echo "# test_helix_deps_field.sh: pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
