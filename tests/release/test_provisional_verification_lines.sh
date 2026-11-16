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
# Review r2 of CON-423 (B2, r3 fixer, structural round): the grid adds the reviewer's 74 probe cases and the fixer's
# own cases per axis of docs/qa/rehearsal_v73_4_fix/r3/class_inventory.md; P5 also runs with --root (a job path must
# exist); P8 holds one paired mutant per rule of the rebuilt checker; P10 tests --root; P11 runs the reviewer's
# mutants X1 to X7 (X1, X2, X3, X7 verbatim; X4, X5, X6 ported to the rebuilt code, see the comment there).
# Review r3 of CON-423 (B1 to B3, F1 to F4, r4 fixer, structural round: one scan feeds every word rule): the grid adds
# the r4 cases and a sample of the character-class inventory; P8 holds the paired mutants of the rebuilt checker (own,
# O01 to O42 without O04, see there); P11 the reviewer's mutants R1 to R22 of review r3 (checker ones; R17, R18 are
# the render's) and X1 to X7 of review r2, printed with the P8 label by the same helper; P12 runs the full inventory tests/release/pvl_inventory.py and compares its
# class list with docs/qa/rehearsal_v73_4_fix/r4/class_inventory.md; P13 the work bound (tests/release/pvl_timing.py).
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
  has "P5 without --root the paths are checked for their shape only (said on the PATHS line)" '^PATHS: shape-only$'
  [ "$n" -gt 0 ] && ok "P5 the real database holds provisional items (control: $n > 0)" || bad "P5 the real database holds provisional items ($n)"
  run --root "$ROOT" "$DB"
  [ "$RC" = 0 ] && ok "P5 real database with --root: every job path that counts exists in this checkout" || bad "P5 real database with --root ($RC): $(printf '%s\n' "$OUT" | grep '^FAIL' | tr '\n' '|')"
  has "P5 --root is reported" "^PATHS: exist-under $ROOT\$"
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
has "P7 grid size (needle: the grid really ran its cases)" '^GRID cases=7[0-9][0-9] refused=6[0-9][0-9] accepted=1[0-9][0-9] mismatches=0 checker_rc=1$'
for c in r3:cyr_TBD_job r3:pending_sched_job r3:none_assigned_target r3:not_applicable_checks r3:T.B.D_job r3:TBD_underscore_target r3:qqq_checks r3:body:html_comment_only r3:body:prefix_glued; do
  printf '%s\n' "$OUT" | grep -q "^GRID-PASS CON-[0-9]* $c\$" && ok "P7 B2: the reviewer case $c is in the grid and as expected" || bad "P7 B2: the reviewer case $c"
done
n_r3="$(printf '%s\n' "$OUT" | grep -c '^GRID-PASS CON-[0-9]* r3:')"
[ "$n_r3" -ge 150 ] && ok "P7 B2: at least 150 r3 cases pass ($n_r3; 74 the reviewer's, the rest the fixer's)" || bad "P7 B2: r3 cases ($n_r3)"
n_r4="$(printf '%s\n' "$OUT" | grep -c '^GRID-PASS CON-[0-9]* r4:')"
[ "$n_r4" -ge 55 ] && ok "P7 r4: at least 55 r4 cases pass ($n_r4)" || bad "P7 r4: r4 cases ($n_r4)"
n_inv="$(printf '%s\n' "$OUT" | grep -c '^GRID-PASS CON-[0-9]* inv:U[0-9][0-9]:')"
[ "$n_inv" -ge 200 ] && ok "P7 r4: at least 200 inventory sample cases pass ($n_inv)" || bad "P7 r4: inventory sample cases ($n_inv)"
for c in r4:B1_slash r4:B1_middot r4:B2_none_yet r4:B2_pending_sh r4:B3_hangul_filler r4:F4_foo r4:root:F2_etc_passwd r4:R10_one_letter_key r4:R12_hex6 r4:body:line_too_long; do
  printf '%s\n' "$OUT" | grep -q "^GRID-PASS CON-[0-9]* $c\$" && ok "P7 r4: the case $c is in the grid and as expected" || bad "P7 r4: the case $c"
done
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
# The r3 mutants targeted code the structural round of r4 replaced (normalise, fold, tokens); the own mutants below
# remove one rule each of the rebuilt checker. O04 (the removal repeated after NFKC) was removed with the code: no
# character's fold holds an invisible character (pvl_inventory.py FOLD-CLOSURE, every code point), so it was dead.
gmut O01-default-ignorable $'        return True\n    return ch != "\\t"' $'        return False\n    return ch != "\\t"'
gmut O02-tab-not-invisible 'return ch != "\t" and unicodedata.category' 'return unicodedata.category'
gmut O03-compat-fold 'v = "".join(compat_char(ch) for ch in raw if not is_invisible(ch))' 'v = "".join(ch for ch in raw if not is_invisible(ch))'
gmut O05-skeleton-decimal 'if unicodedata.decimal(ch, None) is not None:' 'if False:'
gmut O06-skeleton-confusables 'if ch in CONFUSABLES:' 'if False:'
gmut O07-skeleton-latin-name 'if words[:1] == ["LATIN"] and key:' 'if False and key:'
gmut O08-single-runs 'if len(cur) >= 2:' 'if len(cur) >= 99:'
gmut O09-lead-letters 'return n, "".join(t[3] for t in toks[:n])' 'return 0, ""'
gmut O10-weak-path 'return path_ok(t, root) if root is not None else not weak_path(t)' 'return path_ok(t, root) if root is not None else True'
gmut O11-path-dotdot 'if ".." in t.split("/"):' 'if False:'
gmut O12-path-commonpath ' and os.path.commonpath([real_root, p]) == real_root' ''
gmut O13-path-root-itself 'return os.path.exists(p) and p != real_root and' 'return os.path.exists(p) and'
gmut O14-trailing $'    if last:\n' $'    if False:\n'
gmut O15-note $'            if hit:\n                return "holds a placeholder note' $'            if False:\n                return "holds a placeholder note'
gmut O16-mixed-script 'if len(scripts) > 1:' 'if False:'
gmut O17-declared-script 'if sc != "COMMON" and sc not in DECLARED_SCRIPTS:' 'if False:'
gmut O18-outcome-shape 'if key == "checks" and not (re.search' 'if False and not (re.search'
gmut O19-max-line 'if len(lines[0]) > MAX_LINE:' 'if False:'
gmut O20-lead-only 'lead_only = sorted(heads & LEAD_ONLY_WORDS)' 'lead_only = []'
gmut O21-checks-trail-none 'trail = TRAIL_WORDS if key == "checks" else' 'trail = TRAIL_WORDS | TRAIL_WORDS_NOT_CHECKS if key == "checks" else'
gmut O22-invisible-refused $'    if gone:\n' $'    if False:\n'
gmut O23-strong-lead '    strong = sorted(cands & STRONG_WORDS)' '    strong = []'
gmut O24-weak-lead '    weak = sorted(heads & WEAK_WORDS)' '    weak = []'
gmut O25-inside '        if readings(s) & INSIDE_ANY_CASE or s in INSIDE_CAPITALS' '        if False and readings(s) & INSIDE_ANY_CASE or s in INSIDE_CAPITALS'
gmut O26-inside-run '        if any(w in run.lower() for w in INSIDE_ANY_CASE)' '        if False and any(w in run.lower() for w in INSIDE_ANY_CASE)'
gmut O27-template '    m = TEMPLATE.search(core)' '    m = None'
gmut O28-punct-led '        return "starts with no word' '        pass  # "starts with no word'
gmut O29-run-prefixes '        cands |= prefixes(run)' '        pass'
gmut O30-not-no-lead '        if head in ("not", "no") and len(toks) > 1:' '        if False:'
gmut O31-checks-not '        if head == "not" and (nxt in CHECKS_NOT_WORDS' '        if False and (nxt in CHECKS_NOT_WORDS'
gmut O32-target-words 'if key == "target" and not TARGET_WORDS.intersection(ascii_words):' 'if False:'
gmut O33-compat-char-single 'return al[0] if n != ch and len(al) == 1 else ch' 'return ch'
gmut O34-fence-ignored 'lines = [ln for ln in unfenced_lines(body) if PREFIX_RE.match(ln)]' 'lines = [ln for ln in (body or "").splitlines() if PREFIX_RE.match(ln)]'
gmut O35-colonless-form 'FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due)(?=[\s:]|\Z):?(.*)\Z", re.S)' 'FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due):(.*)\Z", re.S)'
gmut O36-due-calendar 'datetime.date(y, mo, da)' 'datetime.date(2026, 1, 1)'
gmut O37-due-time 'datetime.datetime.fromisoformat(d.group(0).replace("Z", "+00:00"))' 'pass'
gmut O38-layer-shape 'if lw not in LAYER_VOCAB:' 'if False:'
gmut O39-artifact-shape 'if not (HEX.search(core.lower()) or ARTIFACT_WORDS.search(core)):' 'if False:'
gmut O40-job-shape 'if not job_anchor(v, root):' 'if False:'
gmut O41-job-command 'if t in COMMANDS:' 'if False:'
gmut O42-comment-skipped 'elif COMMENT_OPEN.match(ln):' 'elif False:'

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

# P10 (B2) --root: a job path counts only when it exists under the root; without --root the shape is enough
mkdir -p "$W/root/tests"; : >"$W/root/tests/there.sh"
JP='**Verification:** provisional -- job: re-run tests/there.sh -- checks: 3 passed -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23'
JA='**Verification:** provisional -- job: re-run tests/absent.sh -- checks: 3 passed -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23'
JC='**Verification:** provisional -- job: go test ./... -- checks: 3 passed -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-23'
mkdb "$W/root.db" "CON-050|Ready for testing|x\\n$JP" "CON-051|Ready for testing|x\\n$JA" "CON-052|In testing|x\\n$JC"
run --root "$W/root" "$W/root.db"
[ "$RC" = 1 ] && ok "P10 --root: exit 1 (one job path is absent)" || bad "P10 --root: exit 1 ($RC: $OUT)"
has "P10 --root: the absent path is refused" "^FAIL CON-051 Ready for testing: field 'job' does not name a job"
printf '%s\n' "$OUT" | grep -q '^FAIL CON-050' && bad "P10 --root: an existing path is accepted" || ok "P10 --root: an existing path is accepted"
printf '%s\n' "$OUT" | grep -q '^FAIL CON-052' && bad "P10 --root: a command with ./... needs no path" || ok "P10 --root: a command with ./... needs no path"
has "P10 --root is reported" "^PATHS: exist-under $W/root\$"
run "$W/root.db"; [ "$RC" = 0 ] && has "P10 without --root the shape is enough (control)" '^PATHS: shape-only$' || bad "P10 without --root ($RC: $OUT)"
run --root "$W/no_such_dir" "$W/root.db"; [ "$RC" = 64 ] && ok "P10 --root that is not a directory: usage exit 64" || bad "P10 --root not a directory ($RC)"
run --root; [ "$RC" = 64 ] && ok "P10 --root without a value: usage exit 64" || bad "P10 --root without a value ($RC)"
sed 's|return path_ok(t, root) if root is not None|return True if root is not None|' "$C" >"$W/m.py"; cmp -s "$C" "$W/m.py" && bad "P10 mutant root-ignored did not apply" || {
  OUT="$(python3 -I "$W/m.py" --root "$W/root" "$W/root.db" 2>&1)"; RC=$?
  [ "$RC" = 0 ] && ok "P10 mutant root-ignored is caught (rc 0, the correct checker gives 1)" || bad "P10 mutant root-ignored survived ($RC)"; }

# P11 the reviewer's mutants. Review r3 (bin/mutants_r3.py of the reviewer, R1 to R22; R17, R18 mutate the render and
# run in its own suite): R9, R10, R12 to R16, R19 to R22 apply VERBATIM; R1 to R8 and R11 targeted code the structural
# round of r4 replaced, and their PORT removes the same behaviour from the rebuilt code (R1 format characters are text,
# R2 combining marks stay, R3 no 1->i reading, R4 white space no separator, R5 underscore no separator, R6 any
# "none ..." in checks a statement, R7 "will be" not a lead phrase, R8 a --root path need not exist, R11 the target
# words read the look-alike map). Review r2 (X1 to X7): X1, X2, X3, X7 verbatim; X4, X5, X6 ported in r3, kept.
gmut R1-port 'NONTEXT_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))' 'NONTEXT_CATEGORIES = frozenset(("Cc", "Cs", "Co", "Cn", "Zl", "Zp"))'
gmut R2-port 'if unicodedata.category(ch) not in MARK_CATEGORIES)' 'if True)'
gmut R3-port 'low.replace("0", "o").replace("1", "i")}' 'low.replace("0", "o")}'
gmut R4-port 'if ch.isalnum() and i < len(v):' 'if (ch.isalnum() or ch.isspace()) and i < len(v):'
gmut R5-port 'if ch.isalnum() and i < len(v):' 'if (ch.isalnum() or ch == "_") and i < len(v):'
gmut R6-port 'not (head == "none" and nxt == "of")' 'not (head == "none")'
gmut R7-port 'BE_LEADS = frozenset(("to", "will", "shall", "should", "would"))' 'BE_LEADS = frozenset(("to", "shall", "should", "would"))'
gmut R8-port 'return os.path.exists(p) and p != real_root' 'return p != real_root'
gmut R9-verbatim '[i + 1:i + 3]' '[i + 1:i + 2]'
gmut R10-verbatim 'JOB_ID = re.compile(r"[A-Z][A-Z0-9]{1,15}' 'JOB_ID = re.compile(r"[A-Z][A-Z0-9]{0,15}'
gmut R11-port 're.findall(r"[A-Za-z0-9]+", core) if w.isascii()]' 're.findall(r"[A-Za-z0-9]+", "".join(skeleton_char(c) for c in core))]'
gmut R12-verbatim '[0-9a-f]{7,64}' '[0-9a-f]{6,64}'
gmut R13-verbatim 'if not 2000 <= y <= 2099:' 'if not 2000 <= y <= 2199:'
gmut R14-verbatim 'comment = "-->" not in ln[ln.index("<!--") + 4:]' 'comment = True'
gmut R15-verbatim '"live-target", "gate-logic")' '"live-target")'
gmut R16-verbatim '"unconfirmed", "lorem"))' '"unconfirmed"))'
gmut R19-verbatim '"ρ": "p", "υ": "u"' '"υ": "u"'
gmut R20-verbatim 'provisional(?=[\s(]|\Z)' 'provisional'
gmut R21-verbatim 'if len(lines) > 1:' 'if len(lines) > 99:'
gmut R22-verbatim 'if tuple(found) != FIELDS:' 'if False:'
gmut X1-verbatim 'elif m and m.group(1)[0] == fence[0] and len' 'elif m and len'
gmut X2-verbatim 'len(m.group(1)) >= len(fence) and not ln[m.end():].strip():' 'len(m.group(1)) >= len(fence):'
gmut X3-verbatim 'FENCE = re.compile(r" {0,3}(' 'FENCE = re.compile(r" *('
gmut X4-port 'INSIDE_CAPITALS = frozenset(("XXX",))' 'INSIDE_CAPITALS = frozenset()'
gmut X5-port 'INSIDE_ANY_CASE = frozenset(("tbd", "tba", "tbc", "todo", "fixme"))' 'INSIDE_ANY_CASE = frozenset(("tbd", "tbc", "todo", "fixme"))'
gmut X6-port 'if path_anchor(t, root):' 'if path_anchor(t, root) or len(toks) == 1:'
gmut X7-verbatim '|\{\{.*?\}\}|\$\{[^}]*\}")' '|\{\{.*?\}\}")'

# P12 (r4) the full character-class inventory: every member of every class of the generator, from the Unicode database
# of this Python, against the checker; and the generator's class list equals the table of the class inventory document
INV="$HERE/pvl_inventory.py"
OUT="$(python3 -I "$INV" "$C" 2>&1)"; RC=$?
printf '%s\n' "$OUT" | grep '^INV-FAIL' | head -10
[ "$RC" = 0 ] && ok "P12 inventory: no mismatch, every class at its floor" || bad "P12 inventory (rc $RC): $(printf '%s\n' "$OUT" | grep -E 'BELOW|^INVENTORY' | tr '\n' '|')"
has "P12 inventory size (needle: the sweep really ran)" '^INVENTORY classes=23 members=1[0-9]{6} cases=[0-9]{5,} mismatches=0 below_floor=0 unicode=[0-9.]+$'
has "P12 fold closure: no character's fold holds an invisible character" '^FOLD-CLOSURE code_points=1114112 folds_to_invisible=0$'
DOC="$ROOT/docs/qa/rehearsal_v73_4_fix/r4/class_inventory.md"
gen="$(python3 -I "$INV" "$C" --classes | tr '\n' ' ')"
doc="$(grep -oE '^\| U[0-9]{2} \|' "$DOC" | tr -d '| ' | tr '\n' ' ')"
[ -n "$gen" ] && [ "$gen" = "$doc" ] && ok "P12 the document lists the generator's classes, in order ($gen)" || bad "P12 class lists differ: generator [$gen] document [$doc]"
sed 's|("U23", |("U99", |' "$INV" >"$W/inv_m.py"
gen_m="$(python3 -I "$W/inv_m.py" "$C" --classes | tr '\n' ' ')"
[ "$gen_m" != "$doc" ] && ok "P12 mutant: a renamed class makes the lists differ (the comparison can fail)" || bad "P12 the list comparison cannot fail"
sed 's|1123),$|99999),|' "$INV" >"$W/inv_f.py"
OUT="$(python3 -I "$W/inv_f.py" "$C" 2>&1)"; RC=$?
[ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q '^CLASS U14 .*BELOW-FLOOR$' && ok "P12 mutant: a floor above the members is reported BELOW-FLOOR (rc 1)" || bad "P12 the floor check cannot fail (rc $RC)"

# P13 (r4, F1) the work bound: no pathological value takes longer than the limit, and a quadratic split is caught
TIM="$HERE/pvl_timing.py"
OUT="$(python3 -I "$TIM" "$C" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "P13 timing within the limit ($(printf '%s\n' "$OUT" | tail -1))" || bad "P13 timing (rc $RC): $(printf '%s\n' "$OUT" | grep -E '^(SLOW|TIMING)' | tr '\n' '|')"
has "P13 timing size (needle)" '^TIMING cases=98 worst=[0-9.]+s limit=1.00s OK$'
python3 -I -c 'import sys; s=open(sys.argv[1],encoding="utf-8").read(); o,n=sys.argv[3],sys.argv[4]
if s.count(o)!=1: sys.exit(9)
open(sys.argv[2],"w",encoding="utf-8").write(s.replace(o,n))' "$C" "$W/sep_m.py" 'SEP = re.compile(r"(?<!\s)\s+' 'SEP = re.compile(r"\s+' || bad "P13 mutant quadratic-split did not apply"
OUT="$(python3 -I "$TIM" "$W/sep_m.py" 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "P13 mutant quadratic-split is caught ($(printf '%s\n' "$OUT" | grep '^split40k'))" || bad "P13 mutant quadratic-split survived (rc $RC)"

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
