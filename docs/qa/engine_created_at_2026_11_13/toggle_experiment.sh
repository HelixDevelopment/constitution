#!/bin/bash
# docs/qa/engine_created_at_2026_11_13/toggle_experiment.sh -- the decisive experiment for CON-339
# (section 11.4.102): the same reproduction (repro_con339.sh) run on fresh copies of one database
# with three engine builds that differ only in the two root-cause sites:
#   base        the engine at the base commit
#   close-only  base + the closeCmd change (created_at read before the delete and re-inserted)
#   full-fix    close-only + the md-to-db snapshot (replaceDocumentWithSnapshot)
# Expected if the root cause is right: base rewrites in C1 and S1; close-only preserves C1 and still
# rewrites S1; full-fix preserves both. Any other pattern refutes the root-cause claim.
#
# Usage: toggle_experiment.sh <db file> <open id> <control id> <evidence file> <label>=<engine> ...
#   Run from the repository root (the evidence path is resolved from $PWD, as the engine does).
# Exit: 0 the observed pattern matches the expectation above; 1 it does not; 2 usage; 3 a leg was BLIND.
set -u
[ $# -ge 5 ] || { echo 'usage: toggle_experiment.sh <db> <open id> <control id> <evidence> <label>=<engine> ...' >&2; exit 2; }
DB=${1:?}; OPEN=${2:?}; CTRL=${3:?}; EV=${4:?}; shift 4
HERE=$(cd "$(dirname "$0")" && pwd) || exit 2
[ -f "$DB" ] || { echo "precondition: db not found: $DB" >&2; exit 3; }
TMPD=$(mktemp -d) || exit 3
trap 'rm -rf "${TMPD:?}"' EXIT
echo "source db sha256: $(sha256sum "$DB" | cut -c1-64)"
declare -A C1 S1
for spec in "$@"; do
  label=${spec%%=*}; wi=${spec#*=}
  [ -n "$label" ] && [ "$label" != "$spec" ] || { echo "bad leg spec: $spec" >&2; exit 2; }
  cp "$DB" "$TMPD/$label.db" || exit 3
  echo "===== leg $label"
  bash "$HERE/repro_con339.sh" "$wi" "$TMPD/$label.db" "$OPEN" "$CTRL" "$EV" >"$TMPD/$label.out" 2>&1
  rc=$?
  sed 's/^/  /' "$TMPD/$label.out"
  echo "  repro exit=$rc"
  [ "$rc" -eq 3 ] && { echo "BLIND leg $label" >&2; exit 3; }
  C1[$label]=$(sed -n 's/^  C1 VERDICT //p' "$TMPD/$label.out")
  S1[$label]=$(sed -n 's/^  S1 VERDICT //p' "$TMPD/$label.out")
done
echo "===== summary"
echo '  leg         C1 = close, S1 = sync md-to-db'
for spec in "$@"; do l=${spec%%=*}; printf '  %-11s C1=%-10s S1=%s\n' "$l" "${C1[$l]}" "${S1[$l]}"; done
want="base:REWRITTEN/REWRITTEN close-only:preserved/REWRITTEN full-fix:preserved/preserved"
got=""
for l in base close-only full-fix; do got="$got $l:${C1[$l]:-?}/${S1[$l]:-?}"; done
got=${got# }
echo "  expected: $want"
echo "  observed: $got"
if [ "$got" = "$want" ]; then echo "TOGGLE RESULT: matches (each fix site toggles exactly its own leg)"; exit 0; fi
echo "TOGGLE RESULT: does NOT match"; exit 1
