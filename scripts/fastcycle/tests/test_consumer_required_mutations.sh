#!/bin/bash
# Purpose : paired section 1.1 mutations for fc_require_items in lib/consumer_required.sh (review round 2
#           CR-1/CR-2/CR-3 of the full-suite fix vehicle). Copies the helper into a mktemp tree, applies ONE
#           mutant (an exact string replacement whose anchor must occur exactly once), and runs
#           test_consumer_required_helper.sh against the copy (FC_HELPER_UNDER_TEST; Part 4, which runs the
#           real suites, is skipped for a copy). The unmutated copy must pass first (baseline). A mutant is
#           KILLED only when the helper test exits 1 AND prints at least one "NOT ok" line.
# Mutants :
#   MG1  a register with no known id column SKIPs (the CR-1 shape: an unanswerable query read as "absent")
#   MG1b a database the pragma cannot read SKIPs (not a database, unreadable file)
#   MG2  the "no item with the named prefix" condition dropped (CR-3: a register that LOST an item SKIPs)
#   MG3  ticket_id dropped from the id-column candidates (the section 11.4.54 rename)
#   MG5  the prefix character check dropped (ids are interpolated into SQL: A'X-1 would reach the query)
#   MG6  the "table holds at least one item" condition dropped (an empty table SKIPs)
# Reasoned EQUIVALENT, not listed: `-lt need` -> `-ne need`: COUNT(DISTINCT key) over `key IN (need ids)`
#   cannot exceed need, so the two agree on every input. The numeric check on the three counts cannot be
#   reached with a non-number from sqlite3's COUNT, and `[ -gt ]` on a non-number is false (no SKIP) anyway.
# Usage   : bash scripts/fastcycle/tests/test_consumer_required_mutations.sh [MUTANT_ID...]
# Exit    : 0 baseline passes and every selected mutant is killed; 1 otherwise; 77 (reason=topology_unsupported)
#           when sqlite3 is absent (the fixtures cannot be built, so no mutant could be killed).
# Safety  : one mktemp -d root, removed with safe_rm_rf restricted to it; $HOME is never reassigned.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CANON="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../../../scripts/lib/safe_rm.sh
. "$CANON/scripts/lib/safe_rm.sh"
command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: sqlite3 is not installed, the fixture DBs cannot be built reason=topology_unsupported"; exit 77; }
W="$(mktemp -d "${TMPDIR:-/tmp}/consumer_required_mut.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
export SAFE_RM_ALLOWED_ROOTS="$W"
trap 'safe_rm_rf "${W:?}"' EXIT

MUTANTS=$(cat <<'EOF'
MG1	  [ -n "$_fci_key" ] || return 0	  [ -n "$_fci_key" ] || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG1b	"SELECT name FROM pragma_table_info('items');" 2>/dev/null) || return 0	"SELECT name FROM pragma_table_info('items');" 2>/dev/null) || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG2	[ "$2" -lt "$_fci_need" ] && [ "$3" -eq 0 ]; then	[ "$2" -lt "$_fci_need" ]; then
MG3	  for _fci_c in atm_id ticket_id; do	  for _fci_c in atm_id; do
MG5	    case $_fci_p in ''|[!A-Z]*|*[!A-Z0-9]*) echo	    case $_fci_p in ''|[!A-Z]*) echo
MG6	  if [ "$1" -gt 0 ] && [ "$2" -lt "$_fci_need" ]	  if [ "$2" -lt "$_fci_need" ]
EOF
)

run_helper() { # $1 helper copy -> rc of the helper test; log in $1.log
  FC_HELPER_UNDER_TEST="$1" bash "$HERE/test_consumer_required_helper.sh" >"$1.log" 2>&1
}
cp "$HERE/lib/consumer_required.sh" "$W/base.sh"
run_helper "$W/base.sh"; rc=$?
if [ "$rc" = 0 ] || [ "$rc" = 77 ] && ! grep -q '^NOT ok' "$W/base.sh.log"; then
  echo "ok   baseline: the unmutated helper copy passes ($(grep '^SUMMARY' "$W/base.sh.log"))"
else
  echo "FAIL baseline: the unmutated helper copy fails (rc $rc): $(grep -m3 '^NOT ok' "$W/base.sh.log" | tr '\n' ' '); nothing concluded"
  exit 1
fi
killed=0; survived=0; bad=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id=${line%%$'\t'*}; rest=${line#*$'\t'}; old=${rest%%$'\t'*}; new=${rest#*$'\t'}
  if [ $# -gt 0 ]; then case " $* " in *" $id "*) ;; *) continue;; esac; fi
  m="$W/$id.sh"
  if ! python3 -I - "$HERE/lib/consumer_required.sh" "$m" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit("anchor occurs %d times" % s.count(old))
open(dst, "w").write(s.replace(old, new))
PY
  then echo "BAD  $id: mutation not applicable"; bad=$((bad+1)); continue; fi
  sh -n "$m" || { echo "BAD  $id: the mutant does not parse"; bad=$((bad+1)); continue; }
  run_helper "$m"; rc=$?
  n=$(grep -c '^NOT ok' "$m.log")
  if [ "$rc" = 1 ] && [ "$n" -gt 0 ]; then
    echo "killed $id ($n failing check(s): $(grep -m2 '^NOT ok' "$m.log" | cut -c8-100 | tr '\n' ';'))"; killed=$((killed+1))
  else echo "SURVIVED $id (rc $rc, $n NOT ok lines)"; survived=$((survived+1)); fi
done <<< "$MUTANTS"
echo "SUMMARY mutants=$((killed+survived+bad)) killed=$killed survivors=$survived not_applicable=$bad"
[ "$survived" -eq 0 ] && [ "$bad" -eq 0 ]
