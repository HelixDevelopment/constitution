#!/usr/bin/env bash
# tests/release/test_provisional_verification_lines.sh — test of scripts/validation/check_provisional_verification_lines.py
# (CON-423, rehearsal of the v73.4 cut, D2: every item in Status "Ready for testing" or "In testing" carries one
# complete "**Verification:** provisional" line, section 11.4.290).
#
# Class (§11.4.289(C)): fixture databases built here (golden good, golden bad, negative control, blind cases) prove the
# checker's own logic; the real-tree case runs the checker on docs/workable_items.db of this checkout and needles its
# count against an independent count of the same rows. Two paired mutants of a copy of the checker must be caught.
# Review r1 of CON-423 (B1, r2 fixer): P7 runs the case grid tests/release/pvl_grid.py (placeholder shapes x six
# fields, per-field shapes, due dates, fenced lines, golden-FALSE accepts incl. the colon-less form) with a grid-size
# needle; P8 runs one paired mutant per completeness check and per field (each must make the grid fail); P9 replays
# the reviewer's probe shapes (a "due: ." value and the other placeholders), each refused.
#
# Usage: bash tests/release/test_provisional_verification_lines.sh   (PVL_SCRIPT=<path> tests another copy)
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
# mkdb FILE ROW...: a database with an items table; each ROW is "id|status|body" (body: \n written as \\n)
mkdb() {
  local f="$1"; shift
  python3 -I - "$f" "$@" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table items (atm_id text primary key, status text, body_md text)")
for row in sys.argv[2:]:
    i, s, b = row.split("|", 2)
    con.execute("insert into items values (?, ?, ?)", (i, s, b.replace("\\n", "\n")))
con.commit()
PY
}
GOOD='**Verification:** provisional (section 11.4.290) -- job: re-run t.sh -- checks: 3 passed -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23.'
EMD='**Verification:** provisional (section 11.4.290) — job: re-run t.sh — checks: 3 passed — layer: host-only — target: host — artifact: main — due: 2026-11-23.'
NOCHK='**Verification:** provisional (section 11.4.290) -- job: re-run t.sh -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23.'
EMPTY='**Verification:** provisional (section 11.4.290) -- job: re-run t.sh -- checks:  -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23.'
ORDER='**Verification:** provisional (section 11.4.290) -- checks: 3 passed -- job: re-run t.sh -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23.'

# P1 golden good: complete lines (both separators) on both statuses; other statuses are not checked (negative control)
mkdb "$W/good.db" "CON-001|Ready for testing|## [CON-001] x\\n\\n$GOOD" "CON-002|In testing|## [CON-002] y\\n\\ntext\\n$EMD" \
  "CON-003|Queued|## [CON-003] no line, not provisional" "CON-004|Fixed|## [CON-004] fixed, no line"
run "$W/good.db"
[ "$RC" = 0 ] && ok "P1 golden good: exit 0" || bad "P1 golden good: exit 0 ($RC: $OUT)"
has "P1 VERDICT PASS" '^VERDICT: PASS$'
has "P1 counts: 4 items, 2 provisional, 2 ok" '^CHECKED items=4 provisional_status=2 ok=2 fail=0$'
printf '%s\n' "$OUT" | grep -q 'CON-003\|CON-004' && bad "P1 negative control: Queued and Fixed items are not checked" || ok "P1 negative control: Queued and Fixed items are not checked"

# P2 golden bad: each defect shape named with the item id
mkdb "$W/bad.db" "CON-010|Ready for testing|## [CON-010] the D2 shape: no line" "CON-011|Ready for testing|x\\n$NOCHK" \
  "CON-012|In testing|x\\n$EMPTY" "CON-013|Ready for testing|x\\n$ORDER" "CON-014|Ready for testing|x\\n$GOOD\\n$GOOD" \
  "CON-015|In testing|x\\nVerification: provisional -- job: a -- checks: b -- layer: c -- target: d -- artifact: e -- due: f" \
  "CON-016|Ready for testing|x\\n$GOOD"
run "$W/bad.db"
[ "$RC" = 1 ] && ok "P2 golden bad: exit 1" || bad "P2 golden bad: exit 1 ($RC)"
has "P2 VERDICT FAIL" '^VERDICT: FAIL$'
has "P2 no line" "^FAIL CON-010 Ready for testing: no '\*\*Verification:\*\* provisional' line$"
has "P2 missing checks (the CON-190/CON-191 shape)" '^FAIL CON-011 Ready for testing: missing field\(s\): checks$'
has "P2 empty field value" "^FAIL CON-012 In testing: field 'checks' is empty$"
has "P2 fields out of order" '^FAIL CON-013 Ready for testing: fields out of order'
has "P2 two lines" '^FAIL CON-014 Ready for testing: 2 verification lines'
has "P2 a line without the bold marker does not count" "^FAIL CON-015 In testing: no '\*\*Verification:\*\* provisional' line$"
printf '%s\n' "$OUT" | grep -q '^FAIL CON-016' && bad "P2 a complete item among bad ones is not flagged" || ok "P2 a complete item among bad ones is not flagged"
has "P2 counts" '^CHECKED items=7 provisional_status=7 ok=1 fail=6$'

# P3 blind: a zero proves nothing when the instrument cannot see
run "$W/no_such.db"; [ "$RC" = 2 ] && printf '%s\n' "$OUT" | grep -qx 'VERDICT: BLIND' && ok "P3 missing database: BLIND, exit 2" || bad "P3 missing database ($RC: $OUT)"
mkdb "$W/empty.db"; run "$W/empty.db"; [ "$RC" = 2 ] && printf '%s\n' "$OUT" | grep -qx 'VERDICT: BLIND' && ok "P3 empty items table: BLIND, exit 2" || bad "P3 empty items table ($RC: $OUT)"
python3 -I -c 'import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute("create table other (a)")' "$W/notab.db"
run "$W/notab.db"; [ "$RC" = 2 ] && ok "P3 no items table: BLIND, exit 2" || bad "P3 no items table ($RC)"
run --bogus; [ "$RC" = 64 ] && ok "P3 an option: usage exit 64" || bad "P3 an option: usage exit 64 ($RC)"
mkdb "$W/none.db" "CON-020|Queued|x"; run "$W/none.db"
[ "$RC" = 0 ] && has "P3 no provisional item at all: PASS with the count 0 (items readable: 1)" '^CHECKED items=1 provisional_status=0 ok=0 fail=0$' || bad "P3 no provisional item ($RC)"

# P4 the checker never writes the database
s0="$(sha256sum "$W/bad.db" | cut -d' ' -f1)"; run "$W/bad.db"; [ "$(sha256sum "$W/bad.db" | cut -d' ' -f1)" = "$s0" ] && ok "P4 the database is unchanged" || bad "P4 the database is unchanged"

# P5 the real tracker database of this checkout: PASS, and the count matches an independent count (control needle)
DB="$ROOT/docs/workable_items.db"
if [ -f "$DB" ]; then
  run "$DB"
  [ "$RC" = 0 ] && ok "P5 real database: every Ready-for-testing and In-testing item has a complete line" || bad "P5 real database ($RC): $(printf '%s\n' "$OUT" | grep '^FAIL' | tr '\n' '|')"
  n="$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True).execute("select count(*) from items where status in (\"Ready for testing\",\"In testing\")").fetchone()[0])' "$DB")"
  has "P5 the checker counted the same $n rows (needle: an independent count)" "^CHECKED items=[0-9]+ provisional_status=$n "
  [ "$n" -gt 0 ] && ok "P5 the real database holds provisional items (control: $n > 0)" || bad "P5 the real database holds provisional items ($n)"
else
  bad "P5 real database missing: $DB"
fi

# P6 paired mutants of a copy: each must make a case above fail
mut() { # NAME OLD NEW CASE-DB WANT-RC
  sed "s|$2|$3|" "$C" >"$W/m.py"; cmp -s "$C" "$W/m.py" && { bad "P6 mutant $1 did not apply"; return; }
  OUT="$(python3 -I "$W/m.py" "$4" 2>&1)"; RC=$?
  [ "$RC" != "$5" ] && ok "P6 mutant $1 is caught (rc $RC, the correct checker gives $5)" || bad "P6 mutant $1 survived"
}
mkdb "$W/m1.db" "CON-030|Ready for testing|x\\n$NOCHK"; mkdb "$W/m2.db" "CON-031|In testing|## [CON-031] no line"
run "$W/m1.db"; [ "$RC" = 1 ] && ok "P6 control: the correct checker refuses the single missing-checks item" || bad "P6 control m1 ($RC)"
run "$W/m2.db"; [ "$RC" = 1 ] && ok "P6 control: the correct checker refuses the single In-testing item" || bad "P6 control m2 ($RC)"
mut "checks-not-required" '"job", "checks", "layer"' '"job", "layer"' "$W/m1.db" 1
mut "status-in-testing-dropped" 'STATUSES = ("Ready for testing", "In testing")' 'STATUSES = ("Ready for testing", "Ready for testing")' "$W/m2.db" 1
sed 's|if total == 0:|if False:|' "$C" >"$W/m.py"; OUT="$(python3 -I "$W/m.py" "$W/empty.db" 2>&1)"; RC=$?
[ "$RC" != 2 ] && ok "P6 mutant blind-check-dropped is caught (rc $RC)" || bad "P6 mutant blind-check-dropped survived"

# P7 (CON-423 review r1, B1, M1, M2, M7) the case grid of tests/release/pvl_grid.py: every placeholder shape in each of
# the six fields, the per-field shape refusals, due dates that are not real dates, fenced lines, and the golden-FALSE
# cases (UNCONFIRMED qualifiers after a complete value, the canon's colon-less form) that must stay accepted
GRID="$HERE/pvl_grid.py"
OUT="$(python3 -I "$GRID" "$C" "$W" 2>&1)"; RC=$?
printf '%s\n' "$OUT" | grep '^GRID-FAIL' | head -20
[ "$RC" = 0 ] && ok "P7 grid: no mismatch" || bad "P7 grid: mismatches (rc $RC): $(printf '%s\n' "$OUT" | tail -1)"
has "P7 grid size (needle: the grid really ran its cases)" '^GRID cases=2[0-9][0-9] refused=2[0-9][0-9] accepted=2[0-9] mismatches=0 checker_rc=1$'
printf '%s\n' "$OUT" | grep -q '^GRID-PASS CON-[0-9]* due:dot$' && ok "P7 M1: the case 'due: .' is in the grid and refused" || bad "P7 M1: the case 'due: .'"

# P8 paired mutants of the B1 checks: each must make the grid report a mismatch (rc 1; rc 2 is a blind grid)
gmut() { # NAME OLD NEW
  local m="$W/gm_$1.py"
  python3 -I -c 'import sys; s=open(sys.argv[1],encoding="utf-8").read(); o,n=sys.argv[3],sys.argv[4]
if s.count(o)!=1: sys.exit(9)
open(sys.argv[2],"w",encoding="utf-8").write(s.replace(o,n))' "$C" "$m" "$2" "$3" || { bad "P8 mutant $1 did not apply exactly once"; return; }
  OUT="$(python3 -I "$GRID" "$m" "$W" 2>&1)"; RC=$?
  [ "$RC" = 1 ] && ok "P8 mutant $1 is caught ($(printf '%s\n' "$OUT" | grep -c '^GRID-FAIL') grid cases)" || bad "P8 mutant $1 survived (rc $RC)"
}
gmut empty-check 'if not core:' 'if False:'
gmut pv2-strip 'core = v.strip(" \t.,;:")' 'core = v.strip(" \t")'   # the reviewer's PV2 of review r1, on the new code
gmut punctuation-check 'if not any(ch.isalnum() for ch in core):' 'if False:'
gmut strong-placeholder 'if first in STRONG_PLACEHOLDERS' 'if False'
gmut unconfirmed-word '"unconfirmed", ' ''
gmut weak-placeholder 'if WEAK_PLACEHOLDER.fullmatch(s):' 'if False:'
gmut placeholder-phrase 'or PLACEHOLDER_PHRASE.match(s):' 'or False:'
gmut placeholder-inside 'm = PLACEHOLDER_INSIDE.search(v)' 'm = None'
gmut template 'm = TEMPLATE.search(v)' 'm = None'
gmut nfkc 'v = unicodedata.normalize("NFKC", v)' 'pass'
gmut format-chars 'if unicodedata.category(ch) != "Cf"' 'if True'
gmut job-shape 'if not (len(words) >= 2 or ID_TOKEN.match(core)):' 'if False:'
gmut checks-shape 'elif key in ("checks", "target"):' 'elif key in ("target",):'
gmut target-shape 'elif key in ("checks", "target"):' 'elif key in ("checks",):'
gmut layer-shape 'if lw not in LAYER_VOCAB:' 'if False:'
gmut artifact-shape 'if not (HEX.search(core.lower()) or ARTIFACT_WORDS.search(core)):' 'if False:'
gmut due-not-date 'd = DUE.match(raw.strip())' 'd = DUE.match(raw.strip()) or DUE.match("2026-01-01")'
gmut due-calendar 'datetime.date(y, mo, da)' 'datetime.date(2026, 1, 1)'
gmut due-year-range 'if not 2000 <= y <= 2099:' 'if False:'
gmut due-time 'datetime.datetime.fromisoformat(d.group(0).replace("Z", "+00:00"))' 'pass'
gmut fence-ignored 'lines = [ln for ln in unfenced_lines(body) if ln.startswith(PREFIX)]' 'lines = [ln for ln in (body or "").splitlines() if ln.startswith(PREFIX)]'
gmut fence-close-length 'and len(m.group(1)) >= len(fence)' ''
gmut colonless-form 'FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due)(?=[\s:]|\Z):?(.*)\Z", re.S)' 'FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due):(.*)\Z", re.S)'

# P9 the reviewer's probe shapes of review r1 (B1): each refused, by the field named
mkdb "$W/probe.db" \
  "CON-040|Ready for testing|x\\n**Verification:** provisional (x) -- job: UNCONFIRMED: -- checks: v1 passed -- layer: runtime -- target: host -- artifact: main -- due: 2026-11-23" \
  "CON-041|Ready for testing|x\\n**Verification:** provisional (x) -- job: re-run t.sh -- checks: v1 passed -- layer: runtime -- target: host -- artifact: main -- due: TODO" \
  "CON-042|Ready for testing|x\\n**Verification:** provisional (x) -- job: TBD -- checks: TBD -- layer: TBD -- target: TBD -- artifact: TBD -- due: TBD" \
  "CON-043|Ready for testing|x\\n**Verification:** provisional (x) -- job: - -- checks: v1 passed -- layer: runtime -- target: host -- artifact: main -- due: 2026-11-23" \
  "CON-044|Ready for testing|x\\n**Verification:** provisional (x) -- job: re-run t.sh -- checks: v1 passed -- layer: runtime -- target: host -- artifact: main -- due: ." \
  "CON-045|Ready for testing|x\\n\`\`\`\\n$GOOD\\n\`\`\`"
run "$W/probe.db"
has "P9 job: UNCONFIRMED: refused" "^FAIL CON-040 Ready for testing: field 'job' is a placeholder"
has "P9 due: TODO refused" "^FAIL CON-041 Ready for testing: field 'due' is a placeholder"
has "P9 every field TBD refused (the first field is named)" "^FAIL CON-042 Ready for testing: field 'job' is a placeholder"
has "P9 job: - refused" "^FAIL CON-043 Ready for testing: field 'job' is punctuation only"
has "P9 due: . refused (reviewer mutant PV2 shape)" "^FAIL CON-044 Ready for testing: field 'due' is empty"
has "P9 a line inside a code fence does not count" "^FAIL CON-045 Ready for testing: no '\*\*Verification:\*\* provisional' line$"

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
