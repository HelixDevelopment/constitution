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
#           (rows, prefix shape, column names, no write, id case, NULL ids, whitespace and other tables);
#           round 7 adds L11b (row count), L17b, L18..L23 (quoted path, view, empty ids, BLOB ids, stdout
#           and stderr contract) and measures L14 (read-only calls, side files); round 8 adds L26 (committed
#           content only in the -wal), L27 (a column named k), L28 (a path ending in a newline), L29 (locale)
#           and L22b (the whole SKIP line).
#           Part 4 (CR-2) runs the two REAL cycle_report suites from a scratch consumer layout whose
#           constitution/scripts/fastcycle links to this checkout, so the guard under test is the one the
#           suites really execute (never a text extract): the renamed-column, lost-item and query-error DBs
#           must not SKIP, another consumer's register must; s12 ends in a counted SUMMARY line naming the
#           skipped check 8 (review C2-2).
# Usage   : bash scripts/fastcycle/tests/test_consumer_required_helper.sh
# Exit    : 0 all pass; 1 any fail; 77 (reason=topology_unsupported) when no dash is installed, so the
#           dash leg could not run (the bash leg still ran and passed), or when a leg recorded a
#           SKIP-with-reason (today only L29, a host without a usable locale; CON-222): a skipped leg
#           is never folded into a green exit 0, and the SUMMARY line counts it ("N skip (skipped: L29)").
# Env     : FC_L29_CANDIDATES (test hook, CON-185) replaces the L29 locale list; when it is set at all,
#           a note line names its value (CON-223), and a SKIP it causes ends the run with 77 (CON-222).
# Safety  : one mktemp -d root, removed with safe_rm_rf restricted to it; $HOME is never reassigned.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CANON="$(cd "$HERE/../../.." && pwd)"
HELPER="${FC_HELPER_UNDER_TEST:-$HERE/lib/consumer_required.sh}"   # the mutation harness points this at a mutated copy
# shellcheck source=../../../scripts/lib/safe_rm.sh
. "$CANON/scripts/lib/safe_rm.sh"
P=0; F=0; S=0; SKIPPED=""
ok()  { P=$((P+1)); echo "ok   $*"; }
bad() { F=$((F+1)); echo "NOT ok $*"; }
skipped() { S=$((S+1)); SKIPPED="$SKIPPED $1"; }   # CON-222: a leg that did not run is counted, never a pass
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
  cat >"$t/rc_consumer.sh" <<'EOF'
#!/bin/sh
. "$(dirname "$0")/lib/consumer_required.sh" && { fc_require_consumer "$@"; echo "RC=$?"; }
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
    # round 7 sweep legs (S1..S4): a present directory counts as present; the SKIP is the last STDOUT line and
    # stderr stays empty; the function returns 0 when nothing is missing; an unresolvable root SKIPs 77 silently
    mkdir -p "$C/docs/present_dir"
    "$sh" "$T" docs/present_dir >"$o" 2>&1; rc=$?
    expect "$tag S1 present directory -> body runs" 0 "^BODY RAN$" "$o" "$rc"
    "$sh" "$T" docs/absent.db >"$o" 2>"$o.err"; rc=$?
    expect "$tag S2 SKIP on stdout alone" 77 "docs/absent\.db.*reason=topology_unsupported$" "$o" "$rc"
    [ ! -s "$o.err" ] && ok "$tag S2 SKIP writes nothing on stderr" || bad "$tag S2 SKIP wrote on stderr: $(head -c 200 "$o.err")"
    "$sh" "$(dirname "$T")/rc_consumer.sh" docs/present.db >"$o" 2>"$o.err"; rc=$?
    if [ "$rc" = 0 ] && [ "$(cat "$o")" = "RC=0" ] && [ ! -s "$o.err" ]; then ok "$tag S3 nothing missing -> fc_require_consumer returns 0, prints nothing"
    else bad "$tag S3 nothing missing: rc $rc, stdout [$(cat "$o")], stderr [$(head -c 200 "$o.err")]"; fi
    "$sh" -c '. "$1" && fc_require_consumer docs/present.db; echo BODY RAN' "$W/no/such/dir/x/y/t.sh" "$HELPER" >"$o" 2>"$o.err"; rc=$?
    expect "$tag S4 consumer root not resolvable (\$0 under an absent dir) -> SKIP 77" 77 "consumer root not resolvable.*reason=topology_unsupported$" "$o" "$rc"
    [ ! -s "$o.err" ] && ok "$tag S4 unresolvable root writes nothing on stderr" || bad "$tag S4 wrote on stderr: $(head -c 200 "$o.err")"
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
  #       pinned; the direction stays CON-178's decision, CR3-3). MG23 (reviewer R4-I: items counted as non-NULL keys).
  #   L17 whitespace and other tables: an id with a leading space is not the prefix (SKIP), a trailing space is (RUN);
  #       only the items table is read (another table holding ATM-953, or no id column, changes nothing).
  #       MG24 (trim(k) in C3), MG25 (the pragma reads the first table of the schema).
  #   Empty table: L5 (MG6).
  # Round 7 (review round 6 CR6-1..CR6-6, N6-1; the last round section 11.4.276(G) allows): every reviewer mutant
  # RV6-1..RV6-12 is a paired mutant in test_consumer_required_mutations.sh, and the remaining axes are legs:
  #   L11b row COUNT: 10 000 foreign rows with ATM-5 LAST (and 10 000 foreign rows only). RV6-1 (C3 over LIMIT 3),
  #       RV6-2 (C3 over LIMIT 1000). Bound: a C3 that reads a sample of more than 10 001 rows is out of scope; every
  #       fixture here is smaller, and the real registers hold far fewer rows (the consumer tracker is below 2 000
  #       items), so such a sample reads the whole register in every real case. Recorded, not tested.
  #   L17b whitespace in C2: ' ATM-953' (leading space, the named id) SKIPs: C3 = 0 and C2 = 0. RV6-7 (trim(k) IN in
  #       C2) RUNs it. The round-6 claim that trim(k) in C2 is equivalent was false (C2 and C3 read different values);
  #       the direction (SKIP, the non-conservative one) is pinned and registered with CON-178, like L16 and L17.
  #   L18 path quoting: a tracker path holding a space, a single and a double quote. RV6-4 (path unquoted).
  #   L19 items is a VIEW over foreign rows: SKIP (a view answers the pragma and the counts like a table); a view
  #       over a lost item: run. RV6-5 (pragma only for a table).
  #   L20 empty-string ids only: SKIP (they count as items, like NULL ids in L16; direction registered with CON-178).
  #       RV6-6 (items counted as non-empty keys).
  #   L21 BLOB-stored ids: CAST('ATM-5' AS BLOB) and CAST('ATM-953' AS BLOB) run the checks (LIKE reads a BLOB as
  #       text, so C3 >= 1). The real schema stores TEXT; the helper needs no change. RV6-10 (C3 over text keys only).
  #   L22 stdout contract: the SKIP line is the last line on STDOUT (captured alone) and nothing goes to stderr.
  #       RV6-3 (SKIP line to stderr); RV6-11 (exit 77 -> return 77) is killed by the m2 matrix.
  #   L23 stderr silence: a run (no SKIP) prints nothing on stderr, also when a query errors (viewfail, garbage,
  #       nocol, absent). RV6-8 (2>/dev/null dropped from the data query; round 6 called it harmless, it breaks the
  #       documented Output contract "otherwise nothing").
  #   L14 read-only, measured: a sqlite3 shim on PATH logs every call the helper makes; each starts with -readonly
  #       (RV6-12, MG20). The tracker file's bytes never change (sha256 before = after); a rollback-journal database
  #       gets no new file beside it; a WAL-mode database may get <db>-wal (empty) and <db>-shm beside it and nothing
  #       else (sqlite leaves them when the last connection is read-only; docs/workable_items.db-wal and -shm are
  #       gitignored). Round 6 said "the helper never writes": that holds only for the database's own bytes.
  #   Error / lock: RV6-9 (data-query error -> SKIP) is killed by viewfail (L4).
  # Round 8 (review round 7 CR7-1..CR7-4, N7-1..N7-4; the operator authorised round 8 for this item on 2026-11-11,
  # section 11.4.276(E)(3)/(G), scoped to those findings):
  #   L26 WAL content: a WAL-mode register whose ATM-5 row is committed only in the -wal file (not checkpointed; the
  #       state a live writer or a crash leaves) runs the checks: the read sees committed WAL content. RV7-4 (data
  #       query opened with immutable=1, -readonly kept: it reads the main file alone and SKIPs). RV7-11 (nolock=1)
  #       reads the WAL like the helper here and is killed by the L14 side-file leg.
  #   L27 a real column named k: items(atm_id, k) with the prefixed row's k = ''. CR7-2 (from-items-sample.2, a filter
  #       on k inside the column subquery, reads the column, not the alias: the registry row was not equivalent).
  #   L28 path quoting, newline: a tracker path ending in a newline is passed whole (control: the same name without
  #       the newline is a foreign register and SKIPs). RV7-7 (the path through a command substitution).
  #   L29 locale: an id whose prefix starts with A-umlaut is a usage error (exit 2) in every UTF-8 locale where bash
  #       classes A-umlaut as [:upper:] (needle). RV7-10 ([:upper:] classes instead of [A-Z]; bash only, dash has no
  #       multibyte classes and exits 2 either way).
  #   L22b the whole SKIP line is pinned (message mutants of the sweep's param class).
  #   Bound (CR7-4): the systematic sweep enumerates the operator classes sql, test, grep, redir, exit and (round 8)
  #   param (parameter expansions, the argument shift and count, the relative-path root, the SQL quoting of an id, the
  #   quoting of the db path, the unset statements). It does not enumerate command substitutions, word splitting of
  #   the path, locale classes or multi-edit mutants; those are pinned by hand mutants (RV7-7, RV7-10 and the rest of
  #   the table in test_consumer_required_mutations.sh), not claimed closed by the sweep.
  #   Bound (N7-4): the helper splits its prefix list and the three counts with the caller's IFS. With an IFS that
  #   lacks a space (IFS=, or empty) it never SKIPs (the checks run and FAIL on a foreign register: fail-closed).
  #   Measured by the reviewer, documented in the helper; not tested here (no caller sets such an IFS).
  # The systematic sweep (embedded in test_consumer_required_mutations.sh, run with --sweep) generates every
  # single-edit mutant of the helper for the operator classes above and checks each is killed or registered
  # equivalent with a proof (consumer_required_equivalents.tsv).
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
  # Round 7 fixtures (legs L11b, L17b, L19..L21)
  for _sq in \
    "l11b_count.db|CREATE TABLE items(atm_id TEXT, title TEXT); BEGIN; WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM c WHERE n<10000) INSERT INTO items SELECT 'CON-'||n,'t' FROM c; INSERT INTO items VALUES('ATM-5','t'); COMMIT;" \
    "l11b_foreign.db|CREATE TABLE items(atm_id TEXT, title TEXT); BEGIN; WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM c WHERE n<10000) INSERT INTO items SELECT 'CON-'||n,'t' FROM c; COMMIT;" \
    "l17b_lead953.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES(' ATM-953','t');" \
    "l19_view.db|CREATE TABLE t(atm_id TEXT, title TEXT); INSERT INTO t VALUES('CON-1','t'),('CON-2','t'); CREATE VIEW items AS SELECT atm_id, title FROM t;" \
    "l19_viewlost.db|CREATE TABLE t(atm_id TEXT, title TEXT); INSERT INTO t VALUES('CON-1','t'),('ATM-5','t'); CREATE VIEW items AS SELECT atm_id, title FROM t;" \
    "l20_emptystr.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('','t'),('','u');" \
    "l21_blob.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES(CAST('ATM-5' AS BLOB),'t');" \
    "l21_blob953.db|CREATE TABLE items(atm_id BLOB, title TEXT); INSERT INTO items VALUES(CAST('ATM-953' AS BLOB),'t');"; do
    _f=${_sq%%|*}; rm -f "$FX/$_f"
    sqlite3 "$FX/$_f" "${_sq#*|}" || bad "$_f fixture setup failed"
  done
  # needles: the count fixture holds 10 001 rows with ATM-5 last; the BLOB fixtures really store a BLOB; the view is a view
  [ "$(sqlite3 -readonly "$FX/l11b_count.db" "SELECT COUNT(*) || ' ' || (SELECT atm_id FROM items ORDER BY rowid DESC LIMIT 1) FROM items;")" = "10001 ATM-5" ] \
    && [ "$(sqlite3 -readonly "$FX/l11b_foreign.db" "SELECT COUNT(*) FROM items WHERE atm_id LIKE 'ATM-%';")" = 0 ] \
    && ok "L11b count fixtures built (needle: 10001 rows, ATM-5 last; foreign-only holds no ATM row)" || bad "L11b count fixtures broken"
  [ "$(sqlite3 -readonly "$FX/l21_blob.db" "SELECT typeof(atm_id) FROM items;")" = blob ] \
    && [ "$(sqlite3 -readonly "$FX/l21_blob953.db" "SELECT typeof(atm_id) FROM items;")" = blob ] \
    && [ "$(sqlite3 -readonly "$FX/l19_view.db" "SELECT type FROM sqlite_master WHERE name='items';")" = view ] \
    && ok "L19/L21 fixtures built (needle: items is a view; the ids are stored as blob)" || bad "L19/L21 fixtures broken"
  # L18: a path with a space, a single and a double quote
  QD="$FX/sp a'b \"q\""; mkdir -p "$QD" && cp "$FX/other_atm.db" "$QD/other.db" && cp "$FX/lost_atm.db" "$QD/lost.db" \
    && [ -s "$QD/other.db" ] && ok "L18 quoted-path fixtures built (needle: $QD/other.db exists)" || bad "L18 quoted-path fixtures broken"
  # L14: the sqlite3 shim (logs the arguments of every call, then runs the real sqlite3) and the side-file fixtures
  SQ_REAL=$(command -v sqlite3); SHIM="$W/shim"; mkdir -p "$SHIM"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$FC_SHIM_LOG"\nexec "%s" "$@"\n' "$SQ_REAL" >"$SHIM/sqlite3"; chmod +x "$SHIM/sqlite3"
  rm -f "$FX/wal_t.db" "$FX/rbk_t.db"
  sqlite3 "$FX/wal_t.db" "PRAGMA journal_mode=wal; CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('CON-1','t');" >/dev/null || bad "wal fixture setup failed"
  cp "$FX/other_atm.db" "$FX/rbk_t.db"
  [ "$(sqlite3 -readonly "$FX/rbk_t.db" 'PRAGMA journal_mode;')" = delete ] && [ ! -e "$FX/wal_t.db-wal" ] \
    && ok "L14 side-file fixtures built (needle: rbk_t is a rollback-journal db; wal_t has no -wal left after its writer closed)" || bad "L14 side-file fixtures broken"
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
  cat >"$C/canon/scripts/fastcycle/tests/items_rc.sh" <<'EOF'
#!/bin/sh
. "$(dirname "$0")/lib/consumer_required.sh" && { fc_require_items "$@"; echo "RC=$?"; }
EOF
  TR="$C/canon/scripts/fastcycle/tests/items_rc.sh"
  # S5 (round 7 sweep): a fake sqlite3 that answers the pragma with atm_id and prints $FC_FAKE_Q for the data query.
  # It is a unit-level double for the helper's own parsing of malformed counts (section 11.4.289(C)(1)): real sqlite3
  # never prints them, so only a double reaches those branches. It decides nothing about any real register.
  FAKE="$W/fakesq"; mkdir -p "$FAKE"
  printf '#!/bin/sh\ncase "$*" in *pragma_table_info*) echo atm_id ;; *) printf "%%s\\n" "$FC_FAKE_Q" ;; esac\n' >"$FAKE/sqlite3"; chmod +x "$FAKE/sqlite3"
  for _sq in \
    "l24_at.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('AT-5','t');" \
    "l25_dashonly.db|CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('ATM-','t');"; do
    _f=${_sq%%|*}; rm -f "$FX/$_f"
    sqlite3 "$FX/$_f" "${_sq#*|}" || bad "$_f fixture setup failed"
  done
  # Round 8 fixtures (review round 7 CR7-1, CR7-2, RV7-7, RV7-10; legs L26..L29).
  # L26 (CR7-1): a WAL-mode register whose ATM-5 row is COMMITTED but lives only in the -wal file (not checkpointed):
  # the state a live writer or a crash leaves. Built by copying db + -wal while the writing connection is still open
  # (the crash shape): the sqlite3 CLI runs the copy with .system before it exits, and wal_autocheckpoint=0 keeps the
  # row out of the main file. A reader that ignores the WAL (immutable=1, RV7-4) sees only CON-1 and would SKIP.
  rm -f "$FX/l26_src.db" "$FX/l26_src.db-wal" "$FX/l26_src.db-shm" "$FX/l26_walonly.db" "$FX/l26_walonly.db-wal" "$FX/l26_walonly.db-shm"
  ( cd "$FX" && sqlite3 l26_src.db "PRAGMA journal_mode=wal; PRAGMA wal_autocheckpoint=0; CREATE TABLE items(atm_id TEXT, title TEXT); INSERT INTO items VALUES('CON-1','t'); PRAGMA wal_checkpoint(TRUNCATE); INSERT INTO items VALUES('ATM-5','t');" \
      ".system cp l26_src.db l26_walonly.db && cp l26_src.db-wal l26_walonly.db-wal" >/dev/null ) || bad "l26 WAL fixture setup failed"
  rm -f "$FX/l26_src.db" "$FX/l26_src.db-wal" "$FX/l26_src.db-shm"
  # needle: the WAL copy holds a non-empty -wal; a normal read sees CON-1,ATM-5; a read of the main file alone
  # (immutable=1) sees CON-1 only, so ATM-5 really lives only in the WAL (read from a scratch copy, the fixture is kept)
  _nd="$W/l26_needle"; mkdir -p "$_nd"; cp "$FX/l26_walonly.db" "$FX/l26_walonly.db-wal" "$_nd/"
  if [ -s "$FX/l26_walonly.db-wal" ] \
     && [ "$(sqlite3 -readonly "$_nd/l26_walonly.db" "SELECT group_concat(atm_id) FROM (SELECT atm_id FROM items ORDER BY rowid);")" = "CON-1,ATM-5" ] \
     && [ "$(sqlite3 -readonly "file:$FX/l26_walonly.db?immutable=1" "SELECT group_concat(atm_id) FROM items;")" = "CON-1" ]; then
    ok "L26 WAL fixture built (needle: -wal non-empty; full read CON-1,ATM-5; main file alone CON-1)"
  else bad "L26 WAL fixture broken"; fi
  # L27 (CR7-2): items has a REAL column named k (the alias of the helper's subqueries). The prefixed row carries
  # k = '': a filter written on k inside the subquery reads the column, not the alias (from-items-sample.2).
  rm -f "$FX/l27_kcol.db"
  sqlite3 "$FX/l27_kcol.db" "CREATE TABLE items(atm_id TEXT, k TEXT); INSERT INTO items VALUES('ATM-5',''),('CON-1','x');" || bad "l27 fixture setup failed"
  # L28 (RV7-7): a tracker path that ENDS in a newline; beside it the same name without the newline holds a foreign
  # register. The path must be passed whole: a command substitution would strip the newline and read the other file.
  NLD="$FX/nl"; mkdir -p "$NLD"; NLP="$NLD/x.db
"
  cp "$FX/lost_atm.db" "$NLP" && cp "$FX/other_atm.db" "$NLD/x.db" \
    && [ "$(sqlite3 -readonly "$NLD/x.db" "SELECT COUNT(*) FROM items WHERE atm_id LIKE 'ATM-%';")" = 0 ] && [ -s "$NLP" ] && ! cmp -s "$NLP" "$NLD/x.db" \
    && ok "L28 newline-path fixtures built (needle: 'x.db<LF>' is the lost register, 'x.db' a foreign one)" || bad "L28 newline-path fixtures broken"
  # L29 (RV7-10): the locales the id check is run under. A locale counts only when bash classes A-umlaut as
  # [:upper:] in it (needle), so a [:upper:] class would accept the id there while [A-Z] does not.
  # CON-185: a host without such a locale lacks the topology for this leg: that is a section 11.4.3 SKIP-with-reason
  # (reason=topology_unsupported), never a FAIL. l29_locales prints the usable ones; l29_verdict maps a list to the line.
  l29_locales() {
    for _l in "$@"; do
      if LC_ALL=$_l bash -c 'case "$1" in [[:upper:]]) exit 0 ;; esac; exit 1' _ "$(printf '\303\204')" 2>/dev/null; then printf ' %s' "$_l"; fi
    done
  }
  l29_verdict() { # $1 = the usable-locale list
    if [ -n "$1" ]; then echo "ok   L29 locales where bash classes A-umlaut as upper:$1"
    else echo "SKIP: L29 no listed UTF-8 locale classes A-umlaut as [:upper:], so the [:upper:] mutant is not observable on this host; the leg did not run reason=topology_unsupported"; fi
  }
  # both branches proven on every run: a name no host has -> SKIP line; the host's own list is probed below
  _l29_none=$(l29_locales zz_ZZ.nosuchlocale); _l29_line=$(l29_verdict "$_l29_none")
  case $_l29_line in "SKIP: L29 "*"reason=topology_unsupported") ok "L29 branch: no usable locale -> SKIP-with-reason, not a FAIL (needle: zz_ZZ.nosuchlocale yields an empty list)" ;; *) bad "L29 branch: no usable locale gave [$_l29_line]" ;; esac
  # CON-222: the dispatch of the verdict line is a function, so its SKIP branch is proven on every run (below):
  # the SKIP line is printed AND counted by skipped(); it never goes through ok() (reviewer mutant RV-E) and is
  # never dropped (RV-F). The final exit turns a counted skip into 77.
  l29_dispatch() { # $1 = the verdict line
    case $1 in ok*) ok "${1#ok   }" ;; SKIP*) echo "$1"; skipped L29 ;; *) bad "L29 verdict line unreadable: $1" ;; esac
  }
  _l29_probe=$(P=0; F=0; S=0; SKIPPED=""; l29_dispatch "SKIP: L29 probe line reason=topology_unsupported"; echo "P=$P F=$F S=$S SKIPPED=$SKIPPED")
  _l29_want="SKIP: L29 probe line reason=topology_unsupported
P=0 F=0 S=1 SKIPPED= L29"
  if [ "$_l29_probe" = "$_l29_want" ]; then ok "L29 dispatch: a SKIP line is printed and counted as a skip, not a pass (CON-222)"
  else bad "L29 dispatch: a SKIP line gave [$(printf '%s' "$_l29_probe" | tr '\n' '|')]"; fi
  _l29_probe=$(P=0; F=0; S=0; SKIPPED=""; l29_dispatch "ok   L29 probe"; echo "P=$P F=$F S=$S")
  if [ "$_l29_probe" = "ok   L29 probe
P=1 F=0 S=0" ]; then ok "L29 dispatch: an ok line is a pass and no skip (control)"
  else bad "L29 dispatch: an ok line gave [$(printf '%s' "$_l29_probe" | tr '\n' '|')]"; fi
  # CON-223: the override is a test hook; when it is set (even to an empty or blank value) the run says so.
  if [ "${FC_L29_CANDIDATES+set}" = set ]; then echo "note: FC_L29_CANDIDATES override in effect: [$FC_L29_CANDIDATES] (CON-223; a SKIP it causes ends the run with 77)"; fi
  L29LOC=$(l29_locales ${FC_L29_CANDIDATES:-C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8 de_DE.UTF-8 de_DE.utf8})   # FC_L29_CANDIDATES: a test hook for a host without locales
  _l29_line=$(l29_verdict "$L29LOC")
  l29_dispatch "$_l29_line"
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
l11b_count.db            run  ATM-953
l11b_foreign.db          skip ATM-953
l17b_lead953.db          skip ATM-953
l19_view.db              skip ATM-953
l19_viewlost.db          run  ATM-953
l20_emptystr.db          skip ATM-953
l21_blob.db              run  ATM-953
l21_blob953.db           run  ATM-953
l24_at.db                run  ATM-953 AT-1
l25_dashonly.db          run  ATM-953
l27_kcol.db              run  ATM-953
CASES
    # S6 (round 7 sweep): the function's own return code is 0 on every run path (sqlite3 missing, pragma error, no id
    # column, data-query error, found, absent path)
    for _q in garbage.db nocol.db viewfail.db real_atm.db absent.db; do
      rm -f "$FX/absent.db"
      "$sh" "$TR" "$FX/$_q" ATM-953 >"$o" 2>"$o.err"; rc=$?
      if [ "$rc" = 0 ] && [ "$(cat "$o")" = "RC=0" ] && [ ! -s "$o.err" ]; then ok "[$sh] S6 $_q: fc_require_items returns 0, prints nothing"
      else bad "[$sh] S6 $_q: rc $rc, stdout [$(cat "$o")], stderr [$(head -c 200 "$o.err")]"; fi
    done
    if [ -x "$NB/$sh" ]; then
      PATH="$NB" "$(command -v "$sh")" "$TR" "$FX/other_atm.db" ATM-953 >"$o" 2>"$o.err"; rc=$?
      [ "$rc" = 0 ] && [ "$(cat "$o")" = "RC=0" ] && [ ! -s "$o.err" ] && ok "[$sh] S6 no sqlite3: returns 0, prints nothing" \
        || bad "[$sh] S6 no sqlite3: rc $rc, stdout [$(cat "$o")], stderr [$(head -c 200 "$o.err")]"
    fi
    # S5: malformed counts from the (fake) data query never SKIP, return 0 and print nothing; the needle row "0 0 0"
    # with C1 = 0 proves the fake is consulted (an empty register runs), and "1 0 0" proves it can SKIP
    for _fq in "1 2" "1 0 0 9" "a 0 0" "1 0 x" "" "1 0"; do
      FC_FAKE_Q="$_fq" PATH="$FAKE:$PATH" "$sh" "$TR" "$FX/real_atm.db" ATM-953 >"$o" 2>"$o.err"; rc=$?
      if [ "$rc" = 0 ] && [ "$(cat "$o")" = "RC=0" ] && [ ! -s "$o.err" ]; then ok "[$sh] S5 malformed counts [$_fq] -> run, returns 0, silent"
      else bad "[$sh] S5 malformed counts [$_fq]: rc $rc, stdout [$(cat "$o")], stderr [$(head -c 200 "$o.err")]"; fi
    done
    FC_FAKE_Q="1 0 0" PATH="$FAKE:$PATH" "$sh" "$T" "$FX/real_atm.db" ATM-953 >"$o" 2>&1; rc=$?
    expect "[$sh] S5 needle: the fake answering [1 0 0] SKIPs (the fake is the sqlite3 the helper runs)" 77 "reason=topology_unsupported$" "$o" "$rc"
    # S7: usage errors go to stderr only, exit 2, the body does not run; no id at all is a usage error too
    for _ids in "" "9X-1" "ATM953" "ATM-1'; DROP TABLE items; --"; do
      # shellcheck disable=SC2086
      if [ -z "$_ids" ]; then "$sh" "$T" "$FX/real_atm.db" >"$o" 2>"$o.err"; rc=$?; else "$sh" "$T" "$FX/real_atm.db" "$_ids" >"$o" 2>"$o.err"; rc=$?; fi
      if [ "$rc" = 2 ] && [ ! -s "$o" ] && grep -q '^fc_require_items: ' "$o.err"; then ok "[$sh] S7 usage error [$_ids]: exit 2, message on stderr only"
      else bad "[$sh] S7 usage error [$_ids]: rc $rc, stdout [$(head -c 120 "$o")], stderr [$(head -c 120 "$o.err")]"; fi
    done
    # S7b (round 8 CR7-4): the usage message names the id in single quotes, for each of the three id checks
    for _bi in "ATM953" "9X-1" "ATM-9x" "AtM-5" "A_B-1"; do   # CON-184: a lowercase letter or an underscore inside the prefix
      "$sh" "$T" "$FX/real_atm.db" "$_bi" >"$o" 2>"$o.err"; rc=$?
      [ "$rc" = 2 ] && [ "$(cat "$o.err")" = "fc_require_items: bad item id '$_bi'" ] && ok "[$sh] S7b usage message for [$_bi] is exact" \
        || bad "[$sh] S7b usage message for [$_bi]: rc $rc, stderr [$(head -c 120 "$o.err")]"
    done
    "$sh" "$T" "$FX/other_atm.db" A1B-7 >"$o" 2>&1; rc=$?
    expect "[$sh] S7 a digit inside the prefix (A1B-7) is a valid id (SKIP on a foreign register, not exit 2)" 77 "reason=topology_unsupported$" "$o" "$rc"
    "$sh" "$T" "$FX/both_other.db" ATM-953 >"$o" 2>&1
    grep -q 'column atm_id,ticket_id)' "$o" && ok "[$sh] S8 the SKIP line names the id columns in candidate order (atm_id,ticket_id)" \
      || bad "[$sh] S8 the SKIP line does not name atm_id,ticket_id: $(cat "$o")"
    # L18 (round 7 CR6-5): a tracker path with a space and quotes is passed whole
    "$sh" "$T" "$QD/other.db" ATM-953 >"$o" 2>&1; rc=$?
    expect "[$sh] quoted path, foreign register -> SKIP 77" 77 "reason=topology_unsupported$" "$o" "$rc"
    "$sh" "$T" "$QD/lost.db" ATM-953 >"$o" 2>&1; rc=$?
    expect "[$sh] quoted path, lost item -> no SKIP" 0 "^BODY RAN$" "$o" "$rc"
    # L22 (round 7 CR6-4): the SKIP line is the last STDOUT line, captured alone; stderr is empty
    "$sh" "$T" "$FX/other_atm.db" ATM-953 >"$o" 2>"$o.err"; rc=$?
    expect "[$sh] SKIP on stdout alone: last stdout line ends reason=topology_unsupported" 77 "reason=topology_unsupported$" "$o" "$rc"
    [ ! -s "$o.err" ] && ok "[$sh] SKIP writes nothing on stderr" || bad "[$sh] SKIP wrote on stderr: $(head -c 200 "$o.err")"
    # L23 (round 7 N6-1): a run prints only the body on stdout and nothing on stderr, query errors included
    for _q in viewfail.db garbage.db nocol.db absent.db real_atm.db; do
      rm -f "$FX/absent.db"
      "$sh" "$T" "$FX/$_q" ATM-953 >"$o" 2>"$o.err"; rc=$?
      if [ "$rc" = 0 ] && [ "$(cat "$o")" = "BODY RAN" ] && [ ! -s "$o.err" ]; then ok "[$sh] $_q: run, stdout is only the body, stderr empty"
      else bad "[$sh] $_q: rc $rc, stdout [$(head -c 120 "$o")], stderr [$(head -c 200 "$o.err")]"; fi
    done
    # L26 (round 8 CR7-1, RV7-4): the read sees committed WAL content; per shell a fresh copy of db + -wal
    _d="$W/l26_${sh##*/}"; mkdir -p "$_d"; rm -f "$_d"/t.db*; cp "$FX/l26_walonly.db" "$_d/t.db"; cp "$FX/l26_walonly.db-wal" "$_d/t.db-wal"
    _h0=$(cat "$_d/t.db" "$_d/t.db-wal" | sha256sum)
    "$sh" "$T" "$_d/t.db" ATM-953 >"$o" 2>&1; rc=$?
    expect "[$sh] L26 WAL register, ATM-5 committed only in the -wal -> no SKIP (the lost item is seen)" 0 "^BODY RAN$" "$o" "$rc"
    [ "$(cat "$_d/t.db" "$_d/t.db-wal" | sha256sum)" = "$_h0" ] && ok "[$sh] L26 db and -wal bytes unchanged by the read" || bad "[$sh] L26 db or -wal bytes changed"
    # L28 (round 8 RV7-7): the path with a trailing newline is passed whole
    "$sh" "$T" "$NLP" ATM-953 >"$o" 2>&1; rc=$?
    expect "[$sh] L28 path ending in a newline (lost register) -> no SKIP" 0 "^BODY RAN$" "$o" "$rc"
    "$sh" "$T" "$NLD/x.db" ATM-953 >"$o" 2>&1; rc=$?
    expect "[$sh] L28 control: the same name without the newline (foreign) -> SKIP 77" 77 "reason=topology_unsupported$" "$o" "$rc"
    # L29 (round 8 RV7-10): an id whose prefix starts with A-umlaut is a usage error in every UTF-8 locale listed
    for _l in $L29LOC; do
      LC_ALL=$_l "$sh" "$T" "$FX/other_atm.db" "$(printf '\303\204')TM-5" >"$o" 2>"$o.err"; rc=$?
      if [ "$rc" = 2 ] && [ ! -s "$o" ] && grep -q '^fc_require_items: bad item id' "$o.err"; then ok "[$sh] L29 LC_ALL=$_l: A-umlaut prefix is a usage error (exit 2)"
      else bad "[$sh] L29 LC_ALL=$_l: A-umlaut prefix: rc $rc, stdout [$(head -c 120 "$o")]"; fi
    done
    # L22b (round 8 CR7-4): the whole SKIP line is pinned, not only its tail
    "$sh" "$T" "$FX/other_atm.db" ATM-953 >"$o" 2>&1; rc=$?
    _want="SKIP: tracker DB $FX/other_atm.db (2 items, column atm_id) is another consumer's register: it holds no ATM-* item, so not the real items this suite reads (ATM-953; found 0 of 1) reason=topology_unsupported"
    [ "$rc" = 77 ] && [ "$(cat "$o")" = "$_want" ] && ok "[$sh] L22b the SKIP line is exactly the documented text" || bad "[$sh] L22b SKIP line [$(cat "$o")], want [$_want]"
    # L14 (round 7 CR6-3, RV6-12): every sqlite3 call carries -readonly (shim log); bytes and side files
    for _q in other_atm.db real_atm.db viewfail.db; do
      : >"$W/shim.log"
      FC_SHIM_LOG="$W/shim.log" PATH="$SHIM:$PATH" "$sh" "$T" "$FX/$_q" ATM-953 >"$o" 2>&1; rc=$?
      _n=$(grep -c . "$W/shim.log"); _ro=$(grep -c '^-readonly ' "$W/shim.log")
      if [ "$_n" -ge 2 ] && [ "$_n" = "$_ro" ]; then ok "[$sh] $_q: all $_n sqlite3 calls are -readonly (shim log; needle: >= 2 calls logged)"
      else bad "[$sh] $_q: $_ro of $_n sqlite3 calls are -readonly: $(grep -v '^-readonly ' "$W/shim.log" | head -2 | cut -c1-80)"; fi
    done
    for _k in wal rbk; do
      _d="$W/side_${sh}_$_k"; mkdir -p "$_d"; cp "$FX/${_k}_t.db" "$_d/t.db"
      _h0=$(sha256sum <"$_d/t.db"); "$sh" "$T" "$_d/t.db" ATM-953 >"$o" 2>&1; rc=$?
      _h1=$(sha256sum <"$_d/t.db"); _extra=$(cd "$_d" && ls -A | grep -vx 't.db' | tr '\n' ' ')
      case $_k in
        wal) _okx=1; for _e in $_extra; do case $_e in t.db-wal|t.db-shm) ;; *) _okx=0 ;; esac; done
             [ -e "$_d/t.db-wal" ] && [ -s "$_d/t.db-wal" ] && _okx=0 ;;
        rbk) [ -z "$_extra" ] && _okx=1 || _okx=0 ;;
      esac
      if [ "$rc" = 77 ] && [ "$_h0" = "$_h1" ] && [ "$_okx" = 1 ]; then ok "[$sh] $_k db: SKIP, bytes unchanged, side files [${_extra:-none}] allowed"
      else bad "[$sh] $_k db: rc $rc, bytes changed: $([ "$_h0" = "$_h1" ] && echo no || echo yes), side files [$_extra]"; fi
    done
    # L14 (review round 5 CR5-2): the helper creates no database; an absent tracker path is still absent afterwards
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

echo "=== Part 3b: the helper under test in a SYMLINKED canon layout (CON-183; runs for a mutated copy too)"
# Part 4 (below) is skipped for a mutated copy, because it runs the checkout's real helper. Its only layout-specific
# property the mutation harness can lose is the symlinked canon (<consumer>/constitution/scripts/fastcycle -> a checkout):
# there $0 is the logical path, so the root must be resolved LOGICALLY (cd without -P), not through the link target.
# This leg builds that layout around the helper UNDER TEST ($HELPER), so a mutant such as cd -P is judged here.
SYM="$W/symcanon"; SYMREAL="$SYM/realcanon/scripts/fastcycle/tests"; SYMC="$SYM/consumer"
mkdir -p "$SYMREAL/lib" "$SYMC/constitution/scripts" "$SYMC/docs" && : >"$SYMC/docs/present.txt" && : >"$SYMC/docs/my data.txt" \
  && ln -s "$HELPER" "$SYMREAL/lib/consumer_required.sh" \
  && ln -s "$SYM/realcanon/scripts/fastcycle" "$SYMC/constitution/scripts/fastcycle" \
  && printf '%s\n' '#!/bin/sh' '. "$(dirname "$0")/lib/consumer_required.sh" && fc_require_consumer "$@"' 'echo "BODY RAN"' >"$SYMREAL/fake_test.sh" \
  && [ -e "$SYMC/constitution/scripts/fastcycle/tests/fake_test.sh" ] \
  && ok "symlinked canon layout built (needle: the consumer data docs/present.txt sits only under the logical root)" \
  || bad "symlinked canon layout setup failed"
# CON-224 (reviewer mutant RV-C, `&& pwd)` -> `&& pwd -P)`): the consumer root reached through a symlinked PARENT
# directory. The root is resolved logically, so the SKIP message names the path as given ($SYM/lp/consumer), not the
# physical one ($SYM/consumer). Needle: both names reach the same fake test.
ln -s "$SYM" "$SYM/lp" && [ -e "$SYM/lp/consumer/constitution/scripts/fastcycle/tests/fake_test.sh" ] \
  && [ "$(cd "$SYM/lp/consumer" && pwd)" != "$(cd "$SYM/lp/consumer" && pwd -P)" ] \
  && ok "symlinked-parent consumer root built (needle: logical and physical root differ)" \
  || bad "symlinked-parent consumer root setup failed"
for sh in $SHELLS; do
  o="$W/out3b"
  "$sh" "$SYM/lp/consumer/constitution/scripts/fastcycle/tests/fake_test.sh" docs/absent.txt >"$o" 2>&1; rc=$?
  _l="$(grep -v '^[[:space:]]*$' "$o" | tail -1)"
  case $_l in "SKIP: consumer-project files absent under $SYM/lp/consumer: docs/absent.txt "*"reason=topology_unsupported")
      [ "$rc" = 77 ] && ok "[$sh] symlinked parent: the SKIP names the logical consumer root (CON-224)" || bad "[$sh] symlinked parent: rc $rc, want 77" ;;
    *) bad "[$sh] symlinked parent: SKIP line [$_l] does not name the logical root $SYM/lp/consumer (rc $rc)" ;;
  esac
done
for sh in $SHELLS; do
  ST="$SYMC/constitution/scripts/fastcycle/tests/fake_test.sh"; o="$W/out3b"
  "$sh" "$ST" docs/present.txt >"$o" 2>&1; rc=$?
  expect "[$sh] symlinked canon: the consumer data under the logical root is found (no false SKIP)" 0 "^BODY RAN$" "$o" "$rc"
  # CON-102 (mutant M1G / reviewer M6, for _fcr_p in "$@" -> $*): a path argument that contains a space is one path
  "$sh" "$ST" "docs/my data.txt" >"$o" 2>&1; rc=$?
  expect "[$sh] a path argument with a space is passed whole (docs/my data.txt present -> no false SKIP)" 0 "^BODY RAN$" "$o" "$rc"
  "$sh" "$ST" "docs/my data.txt" docs/absent.txt >"$o" 2>&1; rc=$?
  expect "[$sh] a spaced path beside an absent one: only the absent one is named" 77 "absent under .*: docs/absent.txt \\(test targets" "$o" "$rc"
  "$sh" "$ST" docs/absent.txt >"$o" 2>&1; rc=$?
  expect "[$sh] symlinked canon: an absent consumer path still SKIPs" 77 "reason=topology_unsupported$" "$o" "$rc"
done

echo "=== Part 4: the REAL cycle_report suites decide SKIP through fc_require_items (CR-2)"
if [ "${FC_HELPER_UNDER_TEST:-}" != "" ]; then
  echo "note: FC_HELPER_UNDER_TEST is set; Part 4 runs the checkout's real helper, so it is skipped for a mutated copy."
  echo "note: BOUND (CON-183): of Part 4 only the symlinked-canon layout is replayed against the copy (Part 3b); a mutant that only"
  echo "note: the real cycle_report suites kill is reported survived here and must be probed on the real helper (Part 4 on the checkout)."
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

echo "SUMMARY: $P pass / $F fail / $S skip${SKIPPED:+ (skipped:$SKIPPED)}"
[ "$F" -eq 0 ] || exit 1
[ "$P" -gt 0 ] || exit 1
if [ -z "$DASH" ]; then
  echo "SKIP: dash is not installed, so the dash leg did not run reason=topology_unsupported"
  exit 77
fi
if [ "$S" -gt 0 ]; then   # CON-222: a skipped leg is never a green exit 0
  echo "SKIP: $S leg(s) did not run:$SKIPPED reason=topology_unsupported"
  exit 77
fi
exit 0
