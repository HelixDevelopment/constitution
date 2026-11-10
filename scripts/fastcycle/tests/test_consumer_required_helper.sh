#!/bin/bash
# Purpose : tests the sourced consumer-data guard scripts/fastcycle/tests/lib/consumer_required.sh
#           (review F1, F2, F9 of the manifest-triage vehicle, round 2).
#           Part 1 drives the REAL helper (linked, not copied) from a fake test placed in a scratch
#           consumer layout <consumer>/<canon>/scripts/fastcycle/tests/, under bash AND under dash:
#             - data absent  -> rc 77, last line names the missing path and ends reason=topology_unsupported
#             - data present -> rc 0 and the test body runs (a false SKIP here was F1: BASH_SOURCE is empty
#                               under dash, so the root resolved to /)
#             - an absolute (effective) path is checked as given, present and absent
#             - several paths: only the missing ones are named
#             - relative $0 (run from another cwd) and a consumer root with a space
#           Part 2 drives two REAL callers in this checkout, only where the consumer data they default to is
#           genuinely absent (canon alone): the env override is honoured (no SKIP when the override points at a
#           present file), and monday_dryrun needs the RB-05 mock only for RED_MODE=0 (F2).
#           Part 3 (review round 2 CR-1/CR-3 of the full-suite fix vehicle) drives fc_require_items, from the
#           same fake-test layout, against fixture tracker DBs: SKIP 77 only for another consumer's register
#           (items present, none with the named ids' prefix), under atm_id AND ticket_id; no SKIP for the
#           real register, a register that LOST a named item, a query error (no id column, not a database),
#           an empty table, no database at all, a data query that errors after the pragma answered (view
#           failing at step time), no sqlite3 on PATH (CR3-1), and a register with BOTH id columns whose named
#           items sit only in ticket_id (CR3-2); both columns are examined. Round 6 adds the legs L11..L17
#           (rows, prefix shape, column names, no write, id case, NULL ids, whitespace and other tables).
#           Part 4 (CR-2) runs the two REAL cycle_report suites from a scratch consumer layout whose
#           constitution/scripts/fastcycle links to this checkout, so the guard under test is the one the
#           suites really execute (never a text extract): the renamed-column, lost-item and query-error DBs
#           must not SKIP, another consumer's register must; s12 ends in a counted SUMMARY line naming the
#           skipped check 8 (review C2-2).
# Usage   : bash scripts/fastcycle/tests/test_consumer_required_helper.sh
# Exit    : 0 all pass; 1 any fail; 77 (reason=topology_unsupported) when no dash is installed, so the
#           dash leg could not run (the bash leg still ran and passed).
# Safety  : one mktemp -d root, removed with safe_rm_rf restricted to it; $HOME is never reassigned.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CANON="$(cd "$HERE/../../.." && pwd)"
HELPER="${FC_HELPER_UNDER_TEST:-$HERE/lib/consumer_required.sh}"   # the mutation harness points this at a mutated copy
# shellcheck source=../../../scripts/lib/safe_rm.sh
. "$CANON/scripts/lib/safe_rm.sh"
P=0; F=0
ok()  { P=$((P+1)); echo "ok   $*"; }
bad() { F=$((F+1)); echo "NOT ok $*"; }
expect() { # expect DESC WANT_RC WANT_LASTLINE_REGEX(or -) OUTFILE RC
  local d="$1" wrc="$2" wre="$3" out="$4" rc="$5" last
  last="$(grep -v '^[[:space:]]*$' "$out" | tail -1)"
  if [ "$rc" != "$wrc" ]; then bad "$d (rc $rc, want $wrc; last line: $last)"; return; fi
  if [ "$wre" != "-" ] && ! printf '%s\n' "$last" | grep -Eq -- "$wre"; then bad "$d (last line [$last] does not match /$wre/)"; return; fi
  ok "$d"
}

W="$(mktemp -d "${TMPDIR:-/tmp}/consumer_required_test.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
export SAFE_RM_ALLOWED_ROOTS="$W"
trap 'safe_rm_rf "${W:?}"' EXIT

mk_layout() { # mk_layout CONSUMER_DIR -> fake test path on stdout
  local c="$1" t="$1/canon/scripts/fastcycle/tests"
  mkdir -p "$t/lib" "$c/docs" || return 1
  ln -s "$HELPER" "$t/lib/consumer_required.sh" || return 1
  cat >"$t/fake_test.sh" <<'EOF'
#!/bin/sh
. "$(dirname "$0")/lib/consumer_required.sh" && fc_require_consumer "$@"
echo "BODY RAN"
EOF
  printf '%s\n' "$t/fake_test.sh"
}

SHELLS="bash"
DASH="$(command -v dash 2>/dev/null || true)"
[ -n "$DASH" ] && SHELLS="bash dash"

echo "=== Part 1: the helper under $SHELLS"
for layout in "plain" "with space"; do
  C="$W/$layout/consumer"
  T="$(mk_layout "$C")" || { bad "layout '$layout': setup failed"; continue; }
  : >"$C/docs/present.db"
  : >"$W/outside_present.sh"
  for sh in $SHELLS; do
    tag="[$sh, $layout]"
    o="$W/out"
    "$sh" "$T" docs/absent.db >"$o" 2>&1; rc=$?
    expect "$tag data absent -> SKIP 77 naming the path, reason=topology_unsupported" 77 \
      "docs/absent\.db.*reason=topology_unsupported$" "$o" "$rc"
    grep -qF "absent under $C:" "$o" && ok "$tag SKIP names the consumer root $C" || bad "$tag SKIP does not name the root $C: $(cat "$o")"
    "$sh" "$T" docs/present.db >"$o" 2>&1; rc=$?
    expect "$tag data present -> body runs, no SKIP" 0 "^BODY RAN$" "$o" "$rc"
    "$sh" "$T" "$W/outside_present.sh" >"$o" 2>&1; rc=$?
    expect "$tag absolute effective path present -> body runs" 0 "^BODY RAN$" "$o" "$rc"
    "$sh" "$T" "$W/outside_absent.sh" >"$o" 2>&1; rc=$?
    expect "$tag absolute effective path absent -> SKIP 77" 77 "outside_absent\.sh.*reason=topology_unsupported$" "$o" "$rc"
    "$sh" "$T" docs/present.db docs/gone1 docs/gone2 >"$o" 2>&1; rc=$?
    expect "$tag several paths -> SKIP naming only the missing ones" 77 "docs/gone1 docs/gone2 \(" "$o" "$rc"
    grep -q 'present\.db' "$o" && bad "$tag the present path was named as missing" || ok "$tag the present path is not named"
    ( cd "$C/canon" && "$sh" scripts/fastcycle/tests/fake_test.sh docs/present.db ) >"$o" 2>&1; rc=$?
    expect "$tag relative \$0 from another cwd -> root still resolved, body runs" 0 "^BODY RAN$" "$o" "$rc"
  done
done

echo "=== Part 2: real callers in this checkout (effective-path guard, F2)"
CONSUMER="$(cd "$CANON/.." && pwd)"
TPB="$HERE/test_fc_timer_prebuild_red.sh"
if [ -e "$CONSUMER/device/rockchip/rk3588/tests/pre_build_verification.sh" ]; then
  echo "note: consumer pre_build_verification.sh is present here; the canon-alone legs of Part 2 do not apply"
else
  o="$W/tpb"
  FC_TIMER_RED_EVIDENCE_DIR="$W/tpb_ev" bash "$TPB" >"$o" 2>&1; rc=$?
  expect "timer_prebuild, no override, default input absent -> SKIP 77" 77 "reason=topology_unsupported$" "$o" "$rc"
  printf '#!/bin/sh\nexit 0\n' >"$W/stub_prebuild.sh"
  FC_TIMER_RED_PREBUILD="$W/stub_prebuild.sh" FC_TIMER_RED_EVIDENCE_DIR="$W/tpb_ev" bash "$TPB" >"$o" 2>&1; rc=$?
  if [ "$rc" != 77 ] && ! grep -q 'reason=topology_unsupported' "$o"; then
    ok "timer_prebuild, FC_TIMER_RED_PREBUILD -> present stub: the guard honours the override (rc $rc, the run went on)"
  else
    bad "timer_prebuild ignored FC_TIMER_RED_PREBUILD (rc $rc): $(tail -1 "$o")"
  fi
fi
MON="$CANON/scripts/multitrack/test_multitrack_monday_dryrun.sh"
if [ -e "$CONSUMER/scripts/multitrack/rb05_fixtures/mock_claude.sh" ]; then
  echo "note: the RB-05 mock is present here; the canon-alone legs of Part 2 do not apply"
else
  o="$W/mon"
  RED_MODE=1 MT_RB13_TEST_EVIDENCE_DIR="$W/mon1_ev" sh "$MON" >"$o" 2>&1; rc=$?
  if [ "$rc" != 77 ]; then ok "monday_dryrun RED_MODE=1 without the mock runs (rc $rc): the RED battery never reads the mock"
  else bad "monday_dryrun RED_MODE=1 SKIPped on the absent mock it does not use: $(tail -1 "$o")"; fi
  RED_MODE=0 MT_RB13_TEST_EVIDENCE_DIR="$W/mon0_ev" sh "$MON" >"$o" 2>&1; rc=$?
  expect "monday_dryrun RED_MODE=0 without the mock -> SKIP 77" 77 "mock_claude\.sh reason=topology_unsupported$" "$o" "$rc"
  [ -e "$W/mon0_ev" ] && bad "monday_dryrun RED_MODE=0 created its evidence dir before the SKIP" || ok "monday_dryrun RED_MODE=0 SKIP is decided before any evidence dir is created"
fi

echo "=== Part 3: fc_require_items against fixture tracker DBs (CR-1, CR-3) under $SHELLS"
mkdb() { # mkdb FILE COLUMN ID... ; COLUMN "-" = items table with no id column; FILE gets the ids as rows
  local f="$1" col="$2"; shift 2
  rm -f "$f"
  if [ "$col" = "-" ]; then sqlite3 "$f" "CREATE TABLE items(id TEXT, title TEXT); INSERT INTO items VALUES('ATM-953','t');" || return 1; return 0; fi
  sqlite3 "$f" "CREATE TABLE items($col TEXT, title TEXT);" || return 1
  local i; for i in "$@"; do sqlite3 "$f" "INSERT INTO items VALUES('$i','t');" || return 1; done
}
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "note: sqlite3 is not installed; Part 3 and Part 4 cannot build fixture DBs"
  NOSQL=1
else
  NOSQL=0
  FX="$W/fix"; mkdir -p "$FX"
  mkdb "$FX/real_atm.db"     atm_id    ATM-953 ATM-1025 ATM-343 ATM-1
  mkdb "$FX/real_ticket.db"  ticket_id ATM-953 ATM-1025 ATM-343 ATM-1
  mkdb "$FX/other_atm.db"    atm_id    CON-001 CON-002
  mkdb "$FX/other_ticket.db" ticket_id CON-001 CON-002
  mkdb "$FX/lost_atm.db"     atm_id    ATM-1 ATM-1025
  mkdb "$FX/lost_ticket.db"  ticket_id ATM-1 ATM-1025
  mkdb "$FX/nocol.db"        -
  mkdb "$FX/empty.db"        atm_id
  printf 'this is not a sqlite database\n' >"$FX/garbage.db"
  # CR3-1: the pragma answers (atm_id, title) but the COUNT query errors at step time (integer overflow in
  # the view); the guard cannot prove absence, so it must not SKIP (the literal CR-1 shape).
  rm -f "$FX/viewfail.db"
  sqlite3 "$FX/viewfail.db" "CREATE TABLE t(atm_id TEXT, title TEXT); INSERT INTO t VALUES('CON-1','t'); CREATE VIEW items AS SELECT atm_id, title FROM t WHERE abs(-9223372036854775808) > 0;" || bad "viewfail fixture setup failed"
  # CR3-2: both id columns exist; the named items live only in ticket_id (atm_id holds another prefix)
  rm -f "$FX/both_ticket.db" "$FX/both_other.db"
  sqlite3 "$FX/both_ticket.db" "CREATE TABLE items(atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('CON-1','ATM-953');" || bad "both_ticket fixture setup failed"
  sqlite3 "$FX/both_other.db" "CREATE TABLE items(atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('CON-1','CON-2');" || bad "both_other fixture setup failed"
  # Round 5 (structural, section 11.4.276(E), review round 4 CR4-1): the decision-leg matrix. fc_require_items SKIPs
  # only when C1 (items) > 0, C2 (named ids found) < need and C3 (rows with a named prefix) = 0, C2 and C3 read over
  # every id column found. Each input leg gets a fixture and a paired mutant in test_consumer_required_mutations.sh:
  #   L1 no sqlite3 (MG8)  L2 pragma fails: garbage, absent (MG1b)  L3 no known id column (MG1)  L4 count errors (MG7)
  #   L5 C1 = 0: empty (MG6)  L6 C3 dropped: lost_* (MG2)  L7 candidate column dropped: atm_id (MG12), ticket_id (MG3)
  #   L8 two columns, examined: first only (MG9), last only (MG11); C3 over first only (MG10), last only (MG13)
  #   L9 several prefixes in the ids: C3 over the first prefix only (MG14), the last only (MG15)
  #   L10 C2 legs: reasoned equivalents (R4-D first-column C2, R4-J clause dropped; named ids carry a named prefix,
  #       so C3 = 0 implies C2 = 0); R4-E UNION vs UNION ALL and R4-F src vs key test: equivalents (see the mutation
  #       file).
  # Round 6 (review round 5 CR5-1, section 11.4.276(G) operator-authorised round): every remaining input axis of the
  # decision, each with a fixture (the L11..L17 fixtures below) and a paired mutant:
  #   L11 rows: multiplicity and position. A foreign row first and the prefixed row later (lost or named), per id
  #       column; three rows with the prefixed one last; several foreign rows only. MG16 (reviewer RV5-1 verbatim:
  #       each column read from its first row only), MG17 (RV5-1b: C3 over a two-row sample).
  #   L12 prefix shape: the dash is part of the prefix test (ATMX-1 is not ATM-*). MG18 (RV5-3).
  #   L13 column names: exact match (parent_atm_id is not atm_id) and case (a column spelled ATM_ID is not found, so
  #       the checks run). MG19 (RV5-4: substring match), MG22 (case-insensitive match).
  #   L14 no write: the helper opens the database read-only; an absent tracker path stays absent. MG20 (RV5-5).
  #   L15 case of ids: LIKE is case-insensitive, so atm-5 counts as the prefix and the checks run (the fail-closed
  #       direction). MG21 (reviewer R4-G: LIKE to GLOB, case-sensitive).
  #   L16 NULL ids: rows whose id is NULL count as items, so a table of NULL ids only SKIPs (current behaviour,
  #       pinned; the direction stays CON-131's decision, CR3-3). MG23 (reviewer R4-I: items counted as non-NULL keys).
  #   L17 whitespace and other tables: an id with a leading space is not the prefix (SKIP), a trailing space is (RUN);
  #       only the items table is read (another table holding ATM-953, or no id column, changes nothing).
  #       MG24 (trim(k) in C3), MG25 (the pragma reads the first table of the schema).
  #   Empty table: L5 (MG6). C2 under whitespace (trim(k) IN): equivalent for the reason of R4-D.
  # m2_<order>_<datacol>_<data>_<other>: both columns, declared in <order> (at = atm_id,ticket_id; ta = reversed);
  # <datacol> holds <data> (named ATM-953 | lost ATM-5, the prefix with the named id lost | foreign CON-7) and the
  # other column holds <other> (foreign CON-1 | NULL). Want: named, lost -> run; foreign -> skip (no ATM row at all).
  : >"$FX/m2cases.txt"
  for _o in at ta; do
    if [ $_o = at ]; then _decl="atm_id TEXT, ticket_id TEXT"; else _decl="ticket_id TEXT, atm_id TEXT"; fi
    for _dc in atm_id ticket_id; do
      if [ $_dc = atm_id ]; then _oc=ticket_id; else _oc=atm_id; fi
      for _d in named lost foreign; do
        case $_d in named) _dv="'ATM-953'"; _w=run ;; lost) _dv="'ATM-5'"; _w=run ;; foreign) _dv="'CON-7'"; _w=skip ;; esac
        for _ot in foreign null; do
          if [ $_ot = foreign ]; then _ov="'CON-1'"; else _ov=NULL; fi
          _f="m2_${_o}_${_dc}_${_d}_${_ot}.db"; rm -f "$FX/$_f"
          sqlite3 "$FX/$_f" "CREATE TABLE items($_decl); INSERT INTO items($_dc, $_oc) VALUES($_dv, $_ov);" || bad "$_f fixture setup failed"
          printf '%s %s ATM-953\n' "$_f" "$_w" >>"$FX/m2cases.txt"
        done
      done
    done
  done
  # C2 split across the columns: ATM-1025 in atm_id, ATM-343 in ticket_id (found 2 of 2), and one named id present in
  # ticket_id only with the other lost (found 1 of 2, prefix present): both run.
  rm -f "$FX/m2_split.db" "$FX/m2_half.db"
  sqlite3 "$FX/m2_split.db" "CREATE TABLE items(atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('ATM-1025',NULL),('CON-1','ATM-343');" || bad "m2_split fixture setup failed"
  sqlite3 "$FX/m2_half.db" "CREATE TABLE items(atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('CON-1','ATM-1025'),('CON-2',NULL);" || bad "m2_half fixture setup failed"
  printf '%s\n' "m2_split.db run ATM-1025 ATM-343" "m2_half.db run ATM-1025 ATM-343" >>"$FX/m2cases.txt"
  # the reviewer's round-4 fixture names (CR4-1), the same data as two matrix cells: both_lost = atm_id CON-1,
  # ticket_id ATM-5 (named item lost, prefix only in the second column); ticket_null = atm_id ATM-953, ticket_id NULL
  rm -f "$FX/both_lost.db" "$FX/ticket_null.db"
  sqlite3 "$FX/both_lost.db" "CREATE TABLE items(atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('CON-1','ATM-5');" || bad "both_lost fixture setup failed"
  sqlite3 "$FX/ticket_null.db" "CREATE TABLE items(atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('ATM-953',NULL);" || bad "ticket_null fixture setup failed"
  # Round 6 legs L11..L17 (see the leg table above): one fixture per cell, built with literal SQL.
  for _sq in \
    "l11_lostlater_atm.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('CON-9','t'),('ATM-5','t');" \
    "l11_lostlater_ticket.db|CREATE TABLE items(ticket_id TEXT, title TEXT); INSERT INTO items VALUES('CON-9','t'),('ATM-5','t');" \
    "l11_namedlater_atm.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('CON-9','t'),('ATM-953','t');" \
    "l11_namedlater_ticket.db|CREATE TABLE items(ticket_id TEXT, title TEXT); INSERT INTO items VALUES('CON-9','t'),('ATM-953','t');" \
    "l11_lost3_atm.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('CON-1','t'),('CON-2','t'),('ATM-5','t');" \
    "l11_lostlater_both.db|CREATE TABLE items(atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('CON-1','CON-2'),('CON-3','ATM-5');" \
    "l11_foreign3_atm.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('CON-1','t'),('CON-2','t'),('CON-3','t');" \
    "l12_atmx.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('ATMX-1','t');" \
    "l13_parentcol.db|CREATE TABLE items(parent_atm_id TEXT, ticket_id TEXT); INSERT INTO items VALUES('ATM-953','CON-1');" \
    "l13_colcase.db|CREATE TABLE items(ATM_ID TEXT, title TEXT); INSERT INTO items VALUES('CON-1','t');" \
    "l15_lower.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('atm-5','t');" \
    "l16_nullonly.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES(NULL,'t'),(NULL,'u');" \
    "l16_nullthen.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES(NULL,'t'),('ATM-5','u');" \
    "l17_lead.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES(' ATM-5','t');" \
    "l17_trail.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('ATM-5 ','t');" \
    "l17_tables.db|CREATE TABLE aaa(x TEXT); INSERT INTO aaa VALUES('ATM-953'); CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('CON-1','t');" \
    "l17_tables2.db|CREATE TABLE aaa(atm_id TEXT); INSERT INTO aaa VALUES('CON-1'); CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('ATM-5','t');"; do
    _f=${_sq%%|*}; rm -f "$FX/$_f"
    sqlite3 "$FX/$_f" "${_sq#*|}" || bad "$_f fixture setup failed"
  done
  # needle: each L11 fixture holds its foreign row FIRST (rowid order), so the later rows are what the leg tests
  [ "$(sqlite3 -readonly "$FX/l11_lostlater_atm.db" "SELECT group_concat(atm_id) FROM (SELECT atm_id FROM items ORDER BY rowid);")" = "CON-9,ATM-5" ] \
    && [ "$(sqlite3 -readonly "$FX/l11_lost3_atm.db" "SELECT atm_id FROM items ORDER BY rowid LIMIT 1;")" = "CON-1" ] \
    && ok "L11 row fixtures built (needle: l11_lostlater_atm rows in order CON-9,ATM-5)" || bad "L11 row fixtures broken"
  # needle: the matrix produced 24 + 2 cases and each fixture answers the pragma with both columns
  [ "$(wc -l <"$FX/m2cases.txt")" -eq 26 ] && [ "$(sqlite3 -readonly "$FX/m2_ta_atm_id_named_null.db" "SELECT group_concat(name) FROM pragma_table_info('items');")" = "ticket_id,atm_id" ] \
    && ok "decision-leg matrix built: 26 two-column cases (needle: m2_ta_* declares ticket_id,atm_id)" || bad "decision-leg matrix fixture broken"
  # CR3-1: a PATH holding the shells and the tools the helper uses, but no sqlite3 (needle: the shell is found,
  # `command -v sqlite3` is not)
  NB="$W/nosql_bin"; mkdir -p "$NB"
  for _t in bash dash sh cat dirname grep tr; do
    _p=$(command -v "$_t" 2>/dev/null) && [ -n "$_p" ] && ln -sf "$_p" "$NB/$_t"
  done
  C="$W/items/consumer"; mk_layout "$C" >/dev/null || bad "Part 3 layout setup failed"
  T="$C/canon/scripts/fastcycle/tests/items_test.sh"
  cat >"$T" <<'EOF'
#!/bin/sh
. "$(dirname "$0")/lib/consumer_required.sh" && fc_require_items "$@"
echo "BODY RAN"
EOF
  for sh in $SHELLS; do
    o="$W/out3"
    # case: db ids... -> want
    while read -r db want ids; do
      [ -n "$db" ] || continue
      # shellcheck disable=SC2086
      "$sh" "$T" "$FX/$db" $ids >"$o" 2>&1; rc=$?
      if [ "$want" = skip ]; then
        expect "[$sh] $db, $ids -> SKIP 77 (another consumer's register)" 77 "reason=topology_unsupported$" "$o" "$rc"
      else
        expect "[$sh] $db, $ids -> no SKIP, the suite's checks run" 0 "^BODY RAN$" "$o" "$rc"
      fi
    done <<CASES
$(cat "$FX/m2cases.txt")
both_lost.db    run  ATM-953
ticket_null.db  run  ATM-953
other_atm.db    run  ATM-953 CON-001
other_atm.db    run  CON-001 ATM-953
real_atm.db     run  ATM-953
real_atm.db     run  ATM-1025 ATM-343
real_ticket.db  run  ATM-953
real_ticket.db  run  ATM-1025 ATM-343
other_atm.db    skip ATM-953
other_atm.db    skip ATM-1025 ATM-343
other_ticket.db skip ATM-953
other_ticket.db skip ATM-1025 ATM-343
lost_atm.db     run  ATM-953
lost_atm.db     run  ATM-1025 ATM-343
lost_ticket.db  run  ATM-953
lost_ticket.db  run  ATM-1025 ATM-343
nocol.db        run  ATM-953
empty.db        run  ATM-953
garbage.db      run  ATM-953
absent.db       run  ATM-953
viewfail.db     run  ATM-953
both_ticket.db  run  ATM-953
both_other.db   skip ATM-953
l11_lostlater_atm.db     run  ATM-953
l11_lostlater_ticket.db  run  ATM-953
l11_namedlater_atm.db    run  ATM-953
l11_namedlater_ticket.db run  ATM-953
l11_lost3_atm.db         run  ATM-953
l11_lostlater_both.db    run  ATM-953
l11_foreign3_atm.db      skip ATM-953
l12_atmx.db              skip ATM-953
l13_parentcol.db         skip ATM-953
l13_colcase.db           run  ATM-953
l15_lower.db             run  ATM-953
l16_nullonly.db          skip ATM-953
l16_nullthen.db          run  ATM-953
l17_lead.db              skip ATM-953
l17_trail.db             run  ATM-953
l17_tables.db            skip ATM-953
l17_tables2.db           run  ATM-953
CASES
    # L14 (review round 5 CR5-2): the helper never writes; an absent tracker path is still absent afterwards
    rm -f "$FX/absent.db"
    "$sh" "$T" "$FX/absent.db" ATM-953 >"$o" 2>&1; rc=$?
    if [ "$rc" = 0 ] && [ ! -e "$FX/absent.db" ]; then ok "[$sh] absent tracker path -> checks run and the path is still absent (no file created)"
    else bad "[$sh] absent tracker path: rc $rc, exists after the call: $([ -e "$FX/absent.db" ] && echo yes || echo no)"; fi
    # CR3-1: no sqlite3 on PATH -> the guard cannot prove absence -> never SKIPs
    shp=$(command -v "$sh"); nbneedle=$(PATH="$NB" command -v "$sh" 2>/dev/null; PATH="$NB" command -v sqlite3 >/dev/null 2>&1 && echo HAS_SQLITE3)
    if [ -x "$NB/$sh" ] && ! PATH="$NB" command -v sqlite3 >/dev/null 2>&1; then
      PATH="$NB" "$shp" "$T" "$FX/other_atm.db" ATM-953 >"$o" 2>&1; rc=$?
      expect "[$sh] no sqlite3 on PATH (needle: shell found, sqlite3 not) -> no SKIP, the suite's checks run" 0 "^BODY RAN$" "$o" "$rc"
    else bad "[$sh] the no-sqlite3 PATH fixture is broken (needle: $nbneedle)"; fi
    for badid in "ATM-1'; DROP TABLE items; --" "A'X-1" "atm-953" "ATM953" "ATM-" "-953" "ATM--1" "ATM-9x"; do
      "$sh" "$T" "$FX/real_atm.db" "$badid" >"$o" 2>&1; rc=$?
      expect "[$sh] id [$badid] outside [A-Z][A-Z0-9]*-[0-9]+ is a usage error (exit 2), never SQL" 2 "-" "$o" "$rc"
    done
    [ "$(sqlite3 -readonly "$FX/real_atm.db" 'SELECT COUNT(*) FROM items;')" = 4 ] \
      && ok "[$sh] the fixture DB is unchanged after the usage error" || bad "[$sh] the fixture DB changed"
    "$sh" "$T" "$FX/other_atm.db" ATM-953 >"$o" 2>&1
    grep -q 'found 0 of 1' "$o" && ok "[$sh] the SKIP line states the measured count (found 0 of 1)" \
      || bad "[$sh] the SKIP line does not state the measured count: $(cat "$o")"
  done
fi

echo "=== Part 4: the REAL cycle_report suites decide SKIP through fc_require_items (CR-2)"
if [ "${FC_HELPER_UNDER_TEST:-}" != "" ]; then
  echo "note: FC_HELPER_UNDER_TEST is set; Part 4 runs the checkout's real helper, so it is skipped for a mutated copy"
elif [ "$NOSQL" = 1 ]; then
  echo "note: no sqlite3; Part 4 not run"
else
  RC="$W/real/consumer"
  mkdir -p "$RC/constitution/scripts" "$RC/docs"
  ln -s "$(cd "$HERE/.." && pwd)" "$RC/constitution/scripts/fastcycle"
  for suite in test_cycle_report_red.sh test_cycle_report_s12_fix_red.sh; do
    for db in real_ticket lost_atm nocol other_atm other_ticket; do
      cp "$FX/$db.db" "$RC/docs/workable_items.db"
      o="$W/out4"
      timeout 600 bash "$RC/constitution/scripts/fastcycle/tests/$suite" >"$o" 2>&1; rc=$?
      case $db in
        other_*) expect "$suite on $db -> SKIP 77" 77 "reason=topology_unsupported$" "$o" "$rc" ;;
        *) if [ "$rc" != 77 ] && ! grep -q 'reason=topology_unsupported' "$o"; then
             ok "$suite on $db -> not SKIPped; the suite's own checks ran (rc $rc)"
           else bad "$suite on $db SKIPped: $(grep -m1 SKIP "$o")"; fi
           if [ "$suite" = test_cycle_report_s12_fix_red.sh ]; then
             # review C2-2: the counted summary line names the skipped check 8 and matches the ok / NOT ok lines
             last="$(grep -v '^[[:space:]]*$' "$o" | tail -1)"
             wantl="SUMMARY pass=$(grep -c '^ok ' "$o") fail=$(grep -c '^NOT ok ' "$o") skip=1 (skipped: check8)"
             if [ "$last" = "$wantl" ]; then ok "s12 on $db ends in the counted summary line [$last]"
             else bad "s12 on $db summary line [$last], want [$wantl]"; fi
           fi ;;
      esac
    done
  done
fi

echo "SUMMARY: $P pass / $F fail"
[ "$F" -eq 0 ] || exit 1
[ "$P" -gt 0 ] || exit 1
if [ -z "$DASH" ]; then
  echo "SKIP: dash is not installed, so the dash leg did not run reason=topology_unsupported"
  exit 77
fi
exit 0
