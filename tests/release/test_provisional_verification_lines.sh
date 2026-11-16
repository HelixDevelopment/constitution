#!/usr/bin/env bash
# tests/release/test_provisional_verification_lines.sh — test of scripts/validation/check_provisional_verification_lines.py
# (CON-423, rehearsal of the v73.4 cut, D2: every item in Status "Ready for testing" or "In testing" carries one
# "**Verification:** provisional" line that is a sentence of a closed grammar, section 11.4.290).
#
# Round 5 (structural, section 11.4.276(E)(3) and 11.4.250): the checker accepts a line only when it is a sentence of
# the closed grammar of docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md whose references resolve. This suite:
#   P0        the self-checks of the fixture (tests/release/pvl_fixture.py) and of the independent oracle
#             (tests/release/pvl_oracle.py: golden line accepted, every golden-bad line refused) before any harness
#             trusts them
#   P1 to P4  the command line on fixture databases (created_at set, --root a fixture tree, --today fixed): golden good,
#             golden bad, blind and usage cases, the database never written (no -wal or -shm sidecar appears)
#   P5        the real tracker database of this checkout with --root of this checkout: counts needled against an
#             independent count; every refused item is listed (PVL_EVIDENCE=<dir> writes the list); exit 0 or 1 both
#             honest, the per-item verdicts are the evidence
#   P6        the case grid (tests/release/pvl_grid.py): API, command line and the independent oracle agree
#   P7        the closed-world property test (tests/release/pvl_property.py)
#   P8        the line model against CommonMark cases, pandoc and markdown-it (tests/release/pvl_linemodel.py)
#   P8b       the reference readers' self-test (tests/release/pvl_refreader.py) and the class-exhaustive line-ending
#             and start-of-line enumeration (tests/release/pvl_lineend.py, round 6)
#   P9        the member inventory of the complement (tests/release/pvl_inventory.py), class list equal to the document
#   P10       the work bound, 1 s per case (tests/release/pvl_timing.py)
#   P11       the reviewers' probes r3, r3b, r4 run verbatim (tests/release/pvl_reviewer.py probes)
#   P12       the reviewers' mutants listed: applies, not applicable with covering cases, or run by another suite
#   P13       the paired mutants (own, tests/release/pvl_mutants.tsv, and the reviewers' that apply) each killed
#             (tests/release/pvl_mutate.py)
# Class (section 11.4.289(C)(2)): gate-logic fixtures; P5 reads the real database of this checkout.
#
# Usage: bash tests/release/test_provisional_verification_lines.sh   (PVL_SCRIPT=<path> tests another copy of the
#        checker for P1 to P10; PVL_EVIDENCE=<dir> keeps the P5 output)
# Exit 0 when every case passes, 1 otherwise. Last line "RESULT: pass=N fail=M".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
C="${PVL_SCRIPT:-$ROOT/scripts/validation/check_provisional_verification_lines.py}"
W="$(mktemp -d "${TMPDIR:-/tmp}/pvl.XXXXXX")" || exit 1
: "${W:?}"; trap 'rm -rf -- "${W:?}"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }
run() { OUT="$(python3 -I "$C" "$@" 2>&1)"; RC=$?; }
has() { printf '%s\n' "$OUT" | grep -qE -- "$2" && ok "$1" || bad "$1 (no line /$2/: $(printf '%s' "$OUT" | tr '\n' '|' | cut -c1-300))"; }
# the fixture root and the fixture lines come from tests/release/pvl_fixture.py (one definition for every harness)
FX="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import pvl_fixture as F; print(F.make_root(sys.argv[2])["root"])' "$HERE" "$W/fx")"
fxline() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import pvl_fixture as F
kw = dict(a.split("=", 1) for a in sys.argv[2:]); print(F.line(**kw))' "$HERE" "$@"; }
# mkdb FILE ROW...: a database with an items table; each ROW is "id|status|created|body" (body: \n written as \\n)
mkdb() {
  local f="$1"; shift
  python3 -I - "$f" "$@" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
for row in sys.argv[2:]:
    i, s, c, b = row.split("|", 3)
    con.execute("insert into items values (?, ?, ?, ?)", (i, s, b.replace("\\n", "\n"), c or None))
con.commit()
PY
}
CK() { run --root "$FX" --today 2026-11-16 "$@"; }
GOOD="$(fxline)"
EMD="$(printf '%s' "$GOOD" | sed 's/ -- / — /g')"
OPEN="CON-777|In progress|2026-11-01|x"

# P0 the fixture and the oracle are checked before anything relies on them
OUT="$(python3 -I "$HERE/pvl_fixture.py" --selftest "$W/st_fx" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "P0 fixture self-check" '^FIXTURE-SELFTEST checks=13 wrong=0$' || bad "P0 fixture self-check (rc $RC: $(printf '%s' "$OUT" | tr '\n' '|' | cut -c1-300))"
OUT="$(python3 -I "$HERE/pvl_oracle.py" --selftest "$W/st_or" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "P0 oracle self-check" '^ORACLE-SELFTEST good=1 bad=13 wrong=0$' || bad "P0 oracle self-check (rc $RC: $(printf '%s' "$OUT" | tr '\n' '|' | cut -c1-300))"

# P1 golden good: both separators, both statuses, the colon-less form; other statuses are not checked
COLONLESS="$(printf '%s' "$GOOD" | sed 's/: / /g')"
mkdb "$W/good.db" "$OPEN" "CON-001|Ready for testing|2026-11-01|## [CON-001] x\\n\\n$GOOD" \
  "CON-002|In testing|2026-11-01T09:00:00Z|## [CON-002] y\\n\\ntext\\n\\n$EMD" \
  "CON-005|Ready for testing|2026-11-01|## x\\n\\n$COLONLESS" \
  "CON-003|Queued|2026-11-01|## [CON-003] no line, not provisional" "CON-004|Fixed||## [CON-004] fixed, no line"
CK "$W/good.db"
[ "$RC" = 0 ] && ok "P1 golden good: exit 0" || bad "P1 golden good: exit 0 ($RC: $OUT)"
has "P1 VERDICT PASS" '^VERDICT: PASS$'
has "P1 counts: 6 items, 3 provisional, 3 ok" '^CHECKED items=6 provisional_status=3 ok=3 fail=0$'
has "P1 the root is reported" "^ROOT: $FX\$"
has "P1 --today and the window are reported" '^TODAY: 2026-11-16 window=60d$'
printf '%s\n' "$OUT" | grep -q 'CON-003\|CON-004' && bad "P1 negative control: Queued and Fixed items are not checked" || ok "P1 negative control: Queued and Fixed items are not checked"

# P2 golden bad: each defect named with the item id and the reason
NOCHK="$(printf '%s' "$GOOD" | sed 's/ -- checks: [^-]*-- / -- /')"
ORDERED="$(fxline job='bash tests/t.sh' checks='tests/t.sh pass=1' | sed 's/ -- job: \(bash tests\/t.sh\) -- checks: \(tests\/t.sh pass=1\)/ -- checks: \2 -- job: \1/')"
PROSE='**Verification:** provisional (section 11.4.290) -- job: re-run t.sh -- checks: 3 passed -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23.'
mkdb "$W/bad.db" "$OPEN" "CON-010|Ready for testing|2026-11-01|## [CON-010] the D2 shape: no line" \
  "CON-011|Ready for testing|2026-11-01|x\\n\\n$NOCHK" "CON-013|Ready for testing|2026-11-01|x\\n\\n$ORDERED" \
  "CON-014|Ready for testing|2026-11-01|x\\n\\n$GOOD\\n\\n$GOOD" "CON-015|In testing|2026-11-01|x\\n\\nVerification: provisional -- job: a" \
  "CON-016|Ready for testing|2026-11-01|x\\n\\n$GOOD" "CON-017|Ready for testing|2026-11-01|x\\n\\n$PROSE" \
  "CON-018|Ready for testing||x\\n\\n$GOOD" "CON-019|In testing|2026-11-25|x\\n\\n$GOOD" \
  "CON-020|Ready for testing|2026-11-01|x\\ncontinues\\n$GOOD" "CON-021|Ready for testing|2026-11-01|x\\n\\n<!-->\\n\\n$GOOD"
CK "$W/bad.db"
[ "$RC" = 1 ] && ok "P2 golden bad: exit 1" || bad "P2 golden bad: exit 1 ($RC)"
has "P2 VERDICT FAIL" '^VERDICT: FAIL$'
has "P2 no line" "^FAIL CON-010 Ready for testing: no '\*\*Verification:\*\* provisional' line$"
has "P2 missing checks (the CON-190/CON-191 shape)" '^FAIL CON-011 Ready for testing: the fields are not job, checks, layer, target, artifact, due in that order: job, layer'
has "P2 fields out of order" '^FAIL CON-013 Ready for testing: the fields are not job, checks'
has "P2 two lines" '^FAIL CON-014 Ready for testing: 2 verification lines'
has "P2 a line without the bold marker does not count (r6: and its label refuses the body)" "^FAIL CON-015 In testing: a line a reader shows carries the Verification label but is not the one counted line"
has "P2 prose is not a sentence of the grammar (the r4 golden-good line)" "^FAIL CON-017 Ready for testing: field 'job' does not start an invocation with a runner"
has "P2 no created date: the window cannot be checked" "^FAIL CON-018 Ready for testing: field 'due' cannot be checked: the item has no created date$"
has "P2 due before the item was created" "^FAIL CON-019 In testing: field 'due' is 2026-11-20, before the item was created \(2026-11-25\)$"
has "P2 a line that continues a paragraph does not count (r6: and its label refuses the body)" "^FAIL CON-020 Ready for testing: a line a reader shows carries the Verification label but is not the one counted line"
has "P2 a body the two readers read differently is refused" '^FAIL CON-021 Ready for testing: the body reads differently'
printf '%s\n' "$OUT" | grep -q '^FAIL CON-016' && bad "P2 a complete item among bad ones is not flagged" || ok "P2 a complete item among bad ones is not flagged"
has "P2 counts" '^CHECKED items=12 provisional_status=11 ok=1 fail=10$'

# P3 blind and usage: a zero proves nothing when the instrument cannot see
CK "$W/no_such.db"; [ "$RC" = 2 ] && printf '%s\n' "$OUT" | grep -qx 'VERDICT: BLIND' && ok "P3 missing database: BLIND, exit 2" || bad "P3 missing database ($RC: $OUT)"
mkdb "$W/empty.db"; CK "$W/empty.db"; [ "$RC" = 2 ] && printf '%s\n' "$OUT" | grep -qx 'VERDICT: BLIND' && ok "P3 empty items table: BLIND, exit 2" || bad "P3 empty items table ($RC: $OUT)"
python3 -I -c 'import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute("create table other (a)")' "$W/notab.db"
CK "$W/notab.db"; [ "$RC" = 2 ] && ok "P3 no items table: BLIND, exit 2" || bad "P3 no items table ($RC)"
run --bogus; [ "$RC" = 64 ] && ok "P3 an unknown option: usage exit 64" || bad "P3 an unknown option ($RC)"
run --root "$W/no_dir" "$W/good.db"; [ "$RC" = 64 ] && ok "P3 a root that is not a directory: exit 64" || bad "P3 root not a directory ($RC)"
run --today 2026-13-01 "$W/good.db"; [ "$RC" = 64 ] && ok "P3 a --today that is not a date: exit 64" || bad "P3 --today not a date ($RC)"
run --due-window-days 3651 "$W/good.db"; [ "$RC" = 64 ] && ok "P3 a window above 3650: exit 64" || bad "P3 window above 3650 ($RC)"
mkdb "$W/none.db" "CON-020|Queued|2026-11-01|x"; CK "$W/none.db"
[ "$RC" = 0 ] && has "P3 no provisional item at all: PASS with the count 0 (items readable: 1)" '^CHECKED items=1 provisional_status=0 ok=0 fail=0$' || bad "P3 no provisional item ($RC)"
mkdb "$W/sp ace.db" "$OPEN" "CON-001|Ready for testing|2026-11-01|x\\n\\n$GOOD"; CK "$W/sp ace.db"
[ "$RC" = 0 ] && ok "P3 a database path with a space opens (pathlib URI)" || bad "P3 a database path with a space ($RC: $OUT)"

# P4 the checker never writes the database and leaves no sidecar
s0="$(sha256sum "$W/bad.db" | cut -d' ' -f1)"; CK "$W/bad.db"
[ "$(sha256sum "$W/bad.db" | cut -d' ' -f1)" = "$s0" ] && ok "P4 the database is unchanged" || bad "P4 the database is unchanged"
[ ! -e "$W/bad.db-wal" ] && [ ! -e "$W/bad.db-shm" ] && [ ! -e "$W/bad.db-journal" ] && ok "P4 no -wal, -shm or -journal sidecar" || bad "P4 a sidecar appeared"

# P4b review r5 (round 6): typed values, a status with a trailing space, hour 24, a lone CR, a registry that is not
# UTF-8, and a WAL-mode database (closed, and with a live writer): a VERDICT line every time, never a traceback, and
# the database directory unchanged byte for byte (no -wal or -shm created)
# rdb FILE WAL|ROLLBACK ROW...: ROW is a Python literal tuple (id, status, body, created): types kept as written
rdb() {
  python3 -I - "$@" <<'PY'
import sqlite3, sys
f, mode = sys.argv[1], sys.argv[2]
con = sqlite3.connect(f)
if mode == "WAL":
    con.execute("pragma journal_mode=wal")
con.execute("create table items (atm_id text primary key, status text, body_md, created_at)")
for r in sys.argv[3:]:
    con.execute("insert into items values (?, ?, ?, ?)", eval(r, {"__builtins__": {}}))  # test rows: suite-written literals
con.commit()
con.close()
PY
}
GOODPY="$(python3 -I -c 'import sys; print(repr(sys.argv[1]))' "$GOOD")"
OPENPY="('CON-777', 'In progress', 'x', '2026-11-01')"
notrace() { printf '%s\n' "$OUT" | grep -q 'Traceback' && bad "$1 (a traceback: $(printf '%s' "$OUT" | tr '\n' '|' | cut -c1-200))" || ok "$1"; }
rdb "$W/typed.db" ROLLBACK "$OPENPY" "('CON-901', 'Ready for testing', 'x\n\n' + $GOODPY, 20261101)" \
  "('CON-902', 'Ready for testing', ('x\n\n' + $GOODPY).encode(), '2026-11-01')" \
  "('CON-903', 'Ready for testing ', 'x', '2026-11-01')" "('CON-904', 'in testing', 'x', '2026-11-01')" \
  "('CON-905', 'Ready for testing', 'x\n\n' + $GOODPY.replace('due: 2026-11-20', 'due: 2026-11-20T24:00'), '2026-11-01')" \
  "('CON-906', 'Ready for testing', 'x\r\`\`\`\n\n' + $GOODPY + '\n\`\`\`\n', '2026-11-01')" \
  "('CON-907', 'Ready for testing', 'x\r<!--\n\n' + $GOODPY + '\n-->\n', '2026-11-01')" \
  "('CON-908', 'Ready for testing', 'x\n\n' + $GOODPY, '2026-11-01')"
CK "$W/typed.db"
[ "$RC" = 1 ] && ok "P4b typed values: exit 1" || bad "P4b typed values: exit 1 ($RC: $(printf '%s' "$OUT" | tr '\n' '|' | cut -c1-300))"
notrace "P4b typed values: no traceback"
has "P4b an integer created_at is refused, named" "^FAIL CON-901 Ready for testing: the created date is not text \(int\)"
has "P4b a blob body is refused, named" "^FAIL CON-902 Ready for testing: the body is not text \(bytes\)"
has "P4b a status with a trailing space is refused, not skipped" "^FAIL CON-903 Ready for testing : the Status 'Ready for testing ' is not written exactly as 'Ready for testing'"
has "P4b a status in another case is refused, not skipped" "^FAIL CON-904 in testing: the Status 'in testing' is not written exactly as 'In testing'"
has "P4b hour 24 is refused" "^FAIL CON-905 Ready for testing: field 'due' is not a real date and time: 2026-11-20T24:00"
has "P4b a lone CR before a fence hides the line (review r5 I-1)" "^FAIL CON-906 Ready for testing: no '\*\*Verification:\*\* provisional' line"
has "P4b a lone CR before a comment hides the line (review r5 I-1)" "^FAIL CON-907 Ready for testing: no '\*\*Verification:\*\* provisional' line"
printf '%s\n' "$OUT" | grep -q '^FAIL CON-908' && bad "P4b the clean item among them is accepted (control)" || ok "P4b the clean item among them is accepted (control)"
has "P4b counts: the trailing-space and other-case statuses are checked" '^CHECKED items=9 provisional_status=8 ok=1 fail=7$'
printf 'board\tT1\n\377\376\n' >"$W/bad_reg.tsv"
rdb "$W/reg.db" ROLLBACK "$OPENPY" "('CON-901', 'Ready for testing', 'x\n\n' + $GOODPY, '2026-11-01')"
CK --targets "$W/bad_reg.tsv" "$W/reg.db"
[ "$RC" = 2 ] && has "P4b a target registry that is not UTF-8: BLIND" '^VERDICT: BLIND$' || bad "P4b registry not UTF-8 ($RC: $(printf '%s' "$OUT" | tr '\n' '|' | cut -c1-300))"
notrace "P4b registry not UTF-8: no traceback"
mkdir -p "$W/wal1" "$W/wal2"
rdb "$W/wal1/w.db" WAL "$OPENPY" "('CON-901', 'Ready for testing', 'x\n\n' + $GOODPY, '2026-11-01')"
before="$(cd "$W/wal1" && ls -A | tr '\n' ' '; sha256sum ./* | tr '\n' ' ')"
CK "$W/wal1/w.db"
after="$(cd "$W/wal1" && ls -A | tr '\n' ' '; sha256sum ./* | tr '\n' ' ')"
[ "$RC" = 0 ] && has "P4b a closed WAL-mode database is read" '^CHECKED items=2 provisional_status=1 ok=1 fail=0$' || bad "P4b closed WAL db ($RC: $OUT)"
[ "$before" = "$after" ] && ok "P4b a closed WAL-mode database: no -wal or -shm created, bytes unchanged" || bad "P4b closed WAL db changed: before '$before' after '$after'"
chmod 0555 "$W/wal1"; CK "$W/wal1/w.db"; chmod 0755 "$W/wal1"
[ "$RC" = 0 ] && has "P4b a closed WAL-mode database in a directory that cannot be written is read (the copy)" '^CHECKED items=2 provisional_status=1 ok=1 fail=0$' || bad "P4b read-only directory WAL db ($RC: $OUT)"
rdb "$W/wal2/w.db" WAL "$OPENPY" "('CON-901', 'Ready for testing', 'x\n\n' + $GOODPY, '2026-11-01')"
# a live writer: it commits one row and keeps its connection (the row is only in -wal), then waits for a stop file
python3 -I -c 'import sqlite3, sys, time, os
c = sqlite3.connect(sys.argv[1]); c.execute("pragma wal_autocheckpoint=0")
c.execute("insert into items values (?, ?, ?, ?)", ("CON-909", "Ready for testing", "x", "2026-11-01")); c.commit()
open(sys.argv[2], "w").close()
t = time.time()
while not os.path.exists(sys.argv[3]) and time.time() - t < 120: time.sleep(0.05)
c.close()' "$W/wal2/w.db" "$W/wal2.ready" "$W/wal2.stop" &
wpid=$!
t=0; while [ ! -e "$W/wal2.ready" ] && [ "$t" -lt 600 ]; do sleep 0.1; t=$((t + 1)); done
before="$(cd "$W/wal2" && ls -A | tr '\n' ' '; sha256sum ./* | tr '\n' ' ')"
CK "$W/wal2/w.db"
after="$(cd "$W/wal2" && ls -A | tr '\n' ' '; sha256sum ./* | tr '\n' ' ')"
: >"$W/wal2.stop"; wait "$wpid"
[ -e "$W/wal2.ready" ] && ok "P4b the live writer committed its row (control)" || bad "P4b the live writer did not start"
has "P4b a WAL database with a live writer: the row only in -wal is read (needle CON-909)" "^FAIL CON-909 Ready for testing: no '\*\*Verification:\*\* provisional' line"
has "P4b a WAL database with a live writer: counts include the -wal row" '^CHECKED items=3 provisional_status=2 ok=1 fail=1$'
[ "$before" = "$after" ] && ok "P4b a WAL database with a live writer: its files unchanged byte for byte" || bad "P4b live WAL db changed: before '$before' after '$after'"

# P5 the real tracker database of this checkout, --root this checkout
DB="$ROOT/docs/workable_items.db"
if [ -f "$DB" ]; then
  run --root "$ROOT" "$DB"
  { [ "$RC" = 0 ] || [ "$RC" = 1 ]; } && ok "P5 real database read (exit $RC: 0 every line a sentence, 1 refusals listed)" || bad "P5 real database ($RC): $OUT"
  n="$(python3 -I -c 'import pathlib,sqlite3,sys; print(sqlite3.connect(pathlib.Path(sys.argv[1]).as_uri()+"?mode=ro", uri=True).execute("select count(*) from items where status in (\"Ready for testing\",\"In testing\")").fetchone()[0])' "$DB")"
  has "P5 the checker counted the same $n rows (needle: an independent count)" "^CHECKED items=[0-9]+ provisional_status=$n "
  [ "$n" -gt 0 ] && ok "P5 the real database holds provisional items (control: $n > 0)" || bad "P5 the real database holds provisional items ($n)"
  nf="$(printf '%s\n' "$OUT" | grep -c '^FAIL ')"
  has "P5 the fail count equals the FAIL lines ($nf)" "^CHECKED items=[0-9]+ provisional_status=$n ok=$((n - nf)) fail=$nf\$"
  has "P5 the root is reported" "^ROOT: $ROOT\$"
  if [ -n "${PVL_EVIDENCE:-}" ]; then
    mkdir -p "$PVL_EVIDENCE" && printf '%s\n' "$OUT" >"$PVL_EVIDENCE/real_db_verdicts.txt" && ok "P5 the verdicts are written to $PVL_EVIDENCE/real_db_verdicts.txt" || bad "P5 the verdicts could not be written"
  fi
  printf '%s\n' "$OUT" | grep '^FAIL ' | cut -c1-200 | sed 's/^/P5-REFUSED /'
else
  bad "P5 real database missing: $DB"
fi

# P6 the case grid
OUT="$(python3 -I "$HERE/pvl_grid.py" "$C" "$W/grid" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P6 grid: API, command line and oracle agree" || bad "P6 grid ($RC): $(printf '%s\n' "$OUT" | grep 'GRID-FAIL' | head -5 | tr '\n' '|')"
has "P6 grid size needle (227 cases, 166 refused, 61 accepted)" '^GRID cases=227 refused=166 accepted=61 mismatches=0 cli_mismatches=0 oracle_mismatches=0$'

# P7 the closed-world property
OUT="$(python3 -I "$HERE/pvl_property.py" "$C" "$W/prop" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P7 property: no line the checker accepts is refused by the grammar's oracle" || bad "P7 property ($RC): $(printf '%s\n' "$OUT" | head -5 | tr '\n' '|')"
has "P7 property size needle (3000 sentences, 18000 perturbations, both verdicts reached)" '^PROPERTY seed=290423 sentences=3000 perturbed=18000 agree=18000 agree_accepted=[1-9][0-9]* checker_only=0 oracle_only=0 sentences_refused=0$'

# P8 the line model, against pandoc where installed
OUT="$(python3 -I "$HERE/pvl_linemodel.py" "$C" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P8 line model: every case counted as CommonMark counts it" || bad "P8 line model ($RC): $(printf '%s\n' "$OUT" | grep FAIL | head -5 | tr '\n' '|')"
if command -v pandoc >/dev/null 2>&1; then
  has "P8 pandoc and markdown-it cross-checks ran with no mismatch" '^LINEMODEL cases=65 mismatches=0 pandoc=checked pandoc_mismatches=0 mdit=checked mdit_mismatches=0$'
else
  has "P8 pandoc absent: SKIP stated, the 65 cases still checked against markdown-it" '^LINEMODEL cases=65 mismatches=0 pandoc=SKIP .*mdit=checked mdit_mismatches=0$'
fi

# P8b the line-ending and start-of-line class, enumerated against markdown-it (round 6)
OUT="$(python3 -I "$HERE/pvl_refreader.py" --selftest 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P8b the reference readers pass their control needles" || bad "P8b reference readers ($RC): $OUT"
has "P8b markdown-it is present and sees the needles" '^REFREADER-SELFTEST mdit=ok '
OUT="$(python3 -I "$HERE/pvl_lineend.py" "$C" "$W/le" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P8b no line-ending or start-of-line variant is accepted while markdown-it shows other lines" || bad "P8b line endings ($RC): $(printf '%s\n' "$OUT" | grep -E 'LE-DANGER|BLIND' | head -5 | tr '\n' '|')"
if command -v pandoc >/dev/null 2>&1; then
  has "P8b class needle (30 members, danger 0, pandoc blind to a lone CR, no reader disagreement accepted)" '^LINEEND variants=19350 agree=[0-9]+ refused=[0-9]+ danger=0 members=30 mdit=3\.0\.0 pandoc=checked pandoc_cr_blind=yes pandoc_danger=0$'
else
  has "P8b class needle (30 members, danger 0, pandoc absent)" '^LINEEND variants=19350 agree=[0-9]+ refused=[0-9]+ danger=0 members=30 mdit=3\.0\.0 pandoc=SKIP pandoc_cr_blind=SKIP pandoc_danger=SKIP$'
fi

# P9 the inventory of the complement; its class list equals the document's table
OUT="$(python3 -I "$HERE/pvl_inventory.py" "$C" "$W/inv" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P9 inventory: every member refused or accepted as the grammar says" || bad "P9 inventory ($RC): $(printf '%s\n' "$OUT" | grep INV-FAIL | head -5 | tr '\n' '|')"
has "P9 inventory needle (12 classes, the whole code space)" '^INVENTORY classes=12 members=[0-9]+ mismatches=0 code_points=1114112$'
has "P9 the one G01 member the grammar accepts is the root path argument" "^G01-ACCEPTED 1 job='bash tests/t.sh -k case12; python3 -I tests/p.py \.'\$"
gen="$(python3 -I "$HERE/pvl_inventory.py" --classes | tr '\n' ' ')"
doc="$(grep -oE '^\| G[0-9]{2} ' "$ROOT/docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md" | tr -d '| ' | tr '\n' ' ')"
[ -n "$gen" ] && [ "$gen" = "$doc" ] && ok "P9 the generator's classes equal the document's ($gen)" || bad "P9 classes differ: generator '$gen', document '$doc'"

# P10 the work bound
OUT="$(python3 -I "$HERE/pvl_timing.py" "$C" "$W/tim" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P10 every pathological case within the limit" || bad "P10 timing ($RC): $(printf '%s\n' "$OUT" | grep SLOW | head -5 | tr '\n' '|')"
has "P10 the limit is 1 s and every case ran" '^TIMING cases=129 worst=[0-9.]+s limit=1.00s OK$'

# P11 the reviewers' probes, verbatim
OUT="$(python3 -I "$HERE/pvl_reviewer.py" probes "$ROOT" "$W/rev" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P11 reviewer probes: no REJ case accepted, every narrowed OK case listed with its reason" || bad "P11 reviewer probes ($RC): $(printf '%s\n' "$OUT" | grep -E 'UNEXPLAINED|STALE|REVERSED|BLIND' | head -5 | tr '\n' '|')"
has "P11 probe needle (322 cases, 33 narrowed by the grammar)" '^REVIEWER probes cases=322 kept=289 narrowed=33 unexplained=0 stale=0 reversed=0 dos_worst=0\.[0-9]{3}$'
has "P11 separator classes: none accepted; shape-only jobs refused" '^REV-R3B PASS separator-class cases 700 accepted 0$'

# P12 the reviewers' mutants listed
OUT="$(python3 -I "$HERE/pvl_reviewer.py" mutants "$ROOT" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P12 every reviewer mutant applies, is run by its suite, or is not applicable with covering cases" || bad "P12 reviewer mutants ($RC): $(printf '%s\n' "$OUT" | grep FAIL | head -5 | tr '\n' '|')"
has "P12 mutant needle (68: R1-R22, X1-X12, N01-N22, RV01-RV12)" '^REVIEWER mutants total=68 applies=23 not_applicable=45 fail=0$'

# P13 the paired mutants: each must be killed by a harness the unmutated copy passes
OUT="$(python3 -I "$HERE/pvl_mutate.py" "$ROOT" "$W/mut" 2>&1)"; RC=$?
printf '%s\n' "$OUT" | grep '^MUT '
[ "$RC" = 0 ] && ok "P13 every mutant killed" || bad "P13 mutants ($RC): $(printf '%s\n' "$OUT" | grep -E 'SURVIVED|NOT-APPLIED|BLIND' | tr '\n' '|')"
has "P13 the unmutated copy passes every kill harness (control)" '^MUT-CONTROL unmutated copy passes'
nown="$(grep -vc '^#' "$HERE/pvl_mutants.tsv")"
[ "$nown" -ge 15 ] && ok "P13 own mutants: $nown (at least 15)" || bad "P13 own mutants: $nown (at least 15)"
has "P13 mutant needle (own plus the 16 reviewer mutants of this suite that apply: 5 of r2-r4 and RV01-RV12 except RV04)" "^MUTATE total=$((nown + 16)) killed=$((nown + 16)) survived=0 not_applied=0\$"

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
