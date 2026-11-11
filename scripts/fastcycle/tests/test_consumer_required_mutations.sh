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
#   MG7  the data query's error returns SKIP (CR3-1, reviewer mutant RMG-A: the pragma answered, the count errors)
#   MG8  no sqlite3 returns SKIP (CR3-1, reviewer mutant RMG-B)
#   MG9  only the first id column found is examined (CR3-2, a register with both columns)
#   Round 5, structural (section 11.4.276(E), review round 4 CR4-1): one mutant per decision leg of the helper; the
#   leg table is in Part 3 of test_consumer_required_helper.sh. RED first: MG10, MG11, MG13, MG14, MG15 SURVIVED the
#   round-4 suite (97/0); MG12 was already killed by other_atm.db (evidence of the round-5 fix vehicle).
#   MG10 (reviewer R4-C, verbatim) the prefix count C3 reads the first id column only (both_lost shape)
#   MG11 (reviewer R4-H, verbatim) only the last id column found is examined (ticket_null shape)
#   MG12 atm_id dropped from the id-column candidates
#   MG13 C3 reads the last id column only
#   MG14 C3 counts the first named prefix only (ids with two prefixes)
#   MG15 C3 counts the last named prefix only
#   Round 6 (review round 5 CR5-1..CR5-4; the operator authorised round 6 for CON-152/CON-157/CON-031 under section
#   11.4.276(G), 2026-11-10): one mutant per remaining input axis, legs L11..L17 in Part 3. RED first: every one
#   below except MG17 SURVIVED the round-5 suite (158/0); MG17 was killed there only through m2_half.
#   MG16 (reviewer RV5-1, verbatim) each id column is read from its first row only (L11 rows; the CR-3 false SKIP)
#   MG17 (reviewer RV5-1b, verbatim) C3 over a two-row sample (L11)
#   MG18 (reviewer RV5-3, verbatim; round-3 RMG-G) the dash dropped from the prefix test (L12)
#   MG19 (reviewer RV5-4, verbatim) id column matched by substring (L13)
#   MG20 (reviewer RV5-5, verbatim) -readonly dropped from the pragma call: an absent path gets a 0-byte file (L14)
#   MG21 (reviewer R4-G) LIKE to GLOB, case-sensitive prefix (L15)
#   MG22 id column matched case-insensitively (L13)
#   MG23 (reviewer R4-I) items counted as non-NULL keys (L16; pins current behaviour, the direction is CON-161's)
#   MG24 trim(k) in the prefix count C3 (L17 whitespace)
#   MG25 the pragma reads the first table of the schema instead of items (L17 other tables)
# Reasoned EQUIVALENT, not listed: `-lt need` -> `-ne need`: COUNT(DISTINCT key) over `key IN (need ids)`
#   cannot exceed need, so the two agree on every input. The numeric check on the three counts cannot be
#   reached with a non-number from sqlite3's COUNT, and `[ -gt ]` on a non-number is false (no SKIP) anyway.
# Reasoned EQUIVALENTS of review round 4 (reviewer mutants, each measured to survive; not listed):
#   R4-D the named-id count C2 over the first column only (or the last only): every named id carries a named
#        prefix, so with C3 correct a named id in ANY column makes C3 >= 1 and the SKIP is refused whatever C2 says.
#   R4-E `UNION ALL` -> `UNION`: C2 is COUNT(DISTINCT k) and C3 is only tested against 0; duplicates change neither.
#   R4-F `[ -n "$_fci_src" ]` -> `[ -n "$_fci_key" ]`: the two are appended in the same branch, so both are set or
#        both empty.
#   R4-J the `$2 -lt need` clause dropped: measured equivalent; C3 = 0 implies C2 = 0 < need (same reason as R4-D).
# Reasoned EQUIVALENTS of review round 5 / round 6 (not listed):
#   RV5-5b `-readonly` dropped from the data query only: it runs only after the read-only pragma answered, so the
#        file exists; a SELECT writes nothing.
#   trim(k) in C2 (`trim(k) IN (...)`): a named id carries a named prefix, so with C3 correct C2 cannot decide a
#        SKIP (the R4-D reason).
# Round 5 pinned R4-G and R4-I to CON-161; round 6 adopted them as MG21 and MG23 with fixtures (see above).
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
MG1	  [ -n "$_fci_src" ] || return 0	  [ -n "$_fci_src" ] || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG1b	"SELECT name FROM pragma_table_info('items');" 2>/dev/null) || return 0	"SELECT name FROM pragma_table_info('items');" 2>/dev/null) || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG2	[ "$2" -lt "$_fci_need" ] && [ "$3" -eq 0 ]; then	[ "$2" -lt "$_fci_need" ]; then
MG3	  for _fci_c in atm_id ticket_id; do	  for _fci_c in atm_id; do
MG5	    case $_fci_p in ''|[!A-Z]*|*[!A-Z0-9]*) echo	    case $_fci_p in ''|[!A-Z]*) echo
MG6	  if [ "$1" -gt 0 ] && [ "$2" -lt "$_fci_need" ]	  if [ "$2" -lt "$_fci_need" ]
MG7	FROM ($_fci_src) WHERE $_fci_like);" 2>/dev/null) || return 0	FROM ($_fci_src) WHERE $_fci_like);" 2>/dev/null) || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG8	  command -v sqlite3 >/dev/null 2>&1 || return 0	  command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG9	      _fci_key="$_fci_key${_fci_key:+,}$_fci_c"	      _fci_key="$_fci_key${_fci_key:+,}$_fci_c"; break
MG10	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (${_fci_src%% UNION ALL*}) WHERE $_fci_like)
MG11	_fci_src="$_fci_src${_fci_src:+ UNION ALL }SELECT $_fci_c AS k FROM items"	_fci_src="SELECT $_fci_c AS k FROM items"
MG12	  for _fci_c in atm_id ticket_id; do	  for _fci_c in ticket_id; do
MG13	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (${_fci_src##* UNION ALL }) WHERE $_fci_like)
MG14	for _fci_p in $_fci_pfx; do _fci_like="$_fci_like${_fci_like:+ OR }k LIKE '$_fci_p-%'"; done	for _fci_p in $_fci_pfx; do _fci_like="k LIKE '$_fci_p-%'"; break; done
MG15	for _fci_p in $_fci_pfx; do _fci_like="$_fci_like${_fci_like:+ OR }k LIKE '$_fci_p-%'"; done	for _fci_p in $_fci_pfx; do _fci_like="k LIKE '$_fci_p-%'"; done
MG16	SELECT $_fci_c AS k FROM items"	SELECT $_fci_c AS k FROM items WHERE rowid = (SELECT MIN(rowid) FROM items)"
MG17	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (SELECT * FROM ($_fci_src) LIMIT 2) WHERE $_fci_like)
MG18	k LIKE '$_fci_p-%'"	k LIKE '$_fci_p%'"
MG19	grep -qx "$_fci_c"	grep -q "$_fci_c"
MG20	_fci_cols=$(sqlite3 -readonly "$_fci_db"	_fci_cols=$(sqlite3 "$_fci_db"
MG21	k LIKE '$_fci_p-%'"	k GLOB '$_fci_p-*'"
MG22	grep -qx "$_fci_c"	grep -qix "$_fci_c"
MG23	SELECT (SELECT COUNT(*) FROM items), 	SELECT (SELECT COUNT(k) FROM ($_fci_src)), 
MG24	}k LIKE '$_fci_p-%'"	}trim(k) LIKE '$_fci_p-%'"
MG25	pragma_table_info('items')	pragma_table_info((SELECT name FROM sqlite_master WHERE type='table' ORDER BY rowid LIMIT 1))
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
