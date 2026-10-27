#!/usr/bin/env bash
# test_status_summary_archive.sh -- behaviour + paired-mutation test of scripts/amendment_log/status_summary_archive.py
#
# Purpose
#   The tool moves the older entries of the `Status summary` metadata cell of a governance carrier into an on-demand
#   Markdown archive so the always-loaded preamble stays small. Its only value is that the move is LOSSLESS, ordered
#   and re-verifiable; this test proves that through the tool's real command line on a synthetic carrier, and proves
#   the checks can fail by running them against deliberately broken copies of the tool (paired mutants, Constitution 1.1).
# Usage
#   bash scripts/amendment_log/tests/test_status_summary_archive.sh
# Exit codes
#   0 every check and every mutant kill passed | 1 a check failed or a mutant survived | 2 environment error
#   Also (job 2, 2026-10-27): proves the standalone independent-rebuild helper tests/independent_lossless_rebuild.py (imports nothing from
#   the tool; golden-good + six negative fixtures + paired mutants of the helper) and exercises the REAL carriers QWEN.md and
#   GEMINI.md of this checkout (verify, independent figure re-computation, section 11.4.290 anchor kept outside the preamble,
#   idempotent re-run, five corruption mutants on copies). CARRIER_ROOT=<dir> points the real-carrier section at another tree
#   (used to show the section goes RED on a pre-move snapshot).
# Dependencies
#   bash, python3, sha256sum, diff.  Writes only under a mktemp directory removed on exit.
# Classification: universal (Constitution 11.4.17).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../status_summary_archive.py"
[ -f "$TOOL" ] || { echo "ENV: tool not found: $TOOL" >&2; exit 2; }
command -v python3 >/dev/null || { echo "ENV: python3 missing" >&2; exit 2; }
WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS  $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

# ---- synthetic carrier: 4 entries, unicode, an inner pipe, both entry markers, a body with a heading after the table
mkcarrier() { # mkcarrier <file> <cell-body>
  python3 - "$1" "$2" <<'PY'
import sys
path, body = sys.argv[1], sys.argv[2]
open(path, "w", encoding="utf-8").write(
    "# Title\n\n| Field | Value |\n|---|---|\n| Revision | 3 |\n| Created | 2026-01-01 |\n"
    "| Last modified | 2026-01-02T00:00:00Z |\n| Status | active |\n"
    "| Status summary | " + body + " |\n| Issues | none |\n\n## First heading\n\n"
    "Body text with a literal | Status summary | row-looking line below the first heading.\n"
    "| Status summary | one-line current-state hook |\n")
PY
}
BODY='NEWEST entry §11.4.1 — kept. Prior: second entry with a | pipe and (Prior: inside parentheses, no leading space, so not a boundary). Prior round: third entry. Prior: fourth entry — last.'

# ---- independent lossless proof: rebuild the original cell from (new cell, archive) WITHOUT importing the tool
independent_ok() { # independent_ok <original-body> <carrier> <archive>
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys
orig, carrier, archive = sys.argv[1:4]
lines = open(carrier, encoding="utf-8").read().split("\n")
head = lines[:next(i for i, l in enumerate(lines) if l.startswith("## "))]
row = [l for l in head if l.startswith("| Status summary | ")]
assert len(row) == 1
body = row[0][len("| Status summary | "):-2]
kept = body.split(" Older entries of this cell", 1)[0]
a = open(archive, encoding="utf-8").read()
blk = a.split("<!-- BEGIN ENTRIES -->", 1)[1].split("<!-- END ENTRIES -->", 1)[0]
ents = [e for e in blk.split("\n") if e.strip()]
rebuilt = kept + " " + " ".join(ents)
sys.exit(0 if rebuilt == orig else 1)
PY
}

# ---- the check set that must hold for a correct tool and break for each mutant
run_core() { # run_core <tool> <dir> -> echoes failures count
  local tool="$1" d="$2" f=0
  mkdir -p "$d"
  mkcarrier "$d/C.md" "$BODY"
  python3 "$tool" archive --carrier "$d/C.md" --archive "$d/A.md" --bump-revision >"$d/out1" 2>&1 || f=$((f + 1))
  python3 "$tool" verify --carrier "$d/C.md" --archive "$d/A.md" >/dev/null 2>&1 || f=$((f + 1))
  independent_ok "$BODY" "$d/C.md" "$d/A.md" 2>/dev/null || f=$((f + 1))
  # order: the archive lists the entries newest first, as they stood in the cell
  python3 - "$d/A.md" 2>/dev/null <<'PY' || f=$((f + 1))
import sys
a = open(sys.argv[1], encoding="utf-8").read()
blk = a.split("<!-- BEGIN ENTRIES -->", 1)[1].split("<!-- END ENTRIES -->", 1)[0]
ents = [e for e in blk.split("\n") if e.strip()]
sys.exit(0 if len(ents) == 3 and ents[0].startswith("Prior: second") and ents[1].startswith("Prior round: third")
         and ents[2].startswith("Prior: fourth") else 1)
PY
  # rotation: a new amendment is prepended to the cell, then archived again; new entry goes on TOP of the archive
  python3 - "$d/C.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("| Status summary | NEWEST entry", "| Status summary | FRESHEST entry. Prior: NEWEST entry", 1)
open(p, "w", encoding="utf-8").write(s)
PY
  local pre_a; pre_a=$(python3 - "$d/A.md" 2>/dev/null <<'PY'
import sys
a = open(sys.argv[1], encoding="utf-8").read()
blk = a.split("<!-- BEGIN ENTRIES -->", 1)[1].split("<!-- END ENTRIES -->", 1)[0]
print(" ".join(e for e in blk.split("\n") if e.strip()))
PY
)
  python3 "$tool" archive --carrier "$d/C.md" --archive "$d/A.md" >"$d/out2" 2>&1 || f=$((f + 1))
  python3 "$tool" verify --carrier "$d/C.md" --archive "$d/A.md" >/dev/null 2>&1 || f=$((f + 1))
  python3 - "$d/C.md" "$d/A.md" "$pre_a" 2>/dev/null <<'PY' || f=$((f + 1))
import sys
carrier, archive, pre = sys.argv[1:4]
lines = open(carrier, encoding="utf-8").read().split("\n")
head = lines[:next(i for i, l in enumerate(lines) if l.startswith("## "))]
row = [l for l in head if l.startswith("| Status summary | ")][0]
kept = row[len("| Status summary | "):-2].split(" Older entries of this cell", 1)[0]
a = open(archive, encoding="utf-8").read()
blk = a.split("<!-- BEGIN ENTRIES -->", 1)[1].split("<!-- END ENTRIES -->", 1)[0]
ents = [e for e in blk.split("\n") if e.strip()]
# rotated entry first, the three older ones unchanged and in order after it
ok = (kept == "FRESHEST entry." and ents[0].startswith("Prior: NEWEST entry") and " ".join(ents[1:]) == pre)
sys.exit(0 if ok else 1)
PY
  echo "$f"
}

echo "== real tool: behaviour =="
D="$WORK/real"; n=$(run_core "$TOOL" "$D")
[ "$n" = 0 ] && ok "archive + verify + independent lossless proof + newest-first order + rotation (0 failing sub-checks)" \
  || bad "core scenario has $n failing sub-check(s)"

# fresh carrier for the remaining single-purpose checks
D2="$WORK/b"; mkdir -p "$D2"; mkcarrier "$D2/C.md" "$BODY"; cp "$D2/C.md" "$D2/orig.md"
python3 "$TOOL" archive --carrier "$D2/C.md" --archive "$D2/A.md" --bump-revision >/dev/null 2>&1
changed=$(diff "$D2/orig.md" "$D2/C.md" | grep -c '^[<>]')
[ "$changed" = 6 ] && ok "only 3 carrier lines change (Revision, Last modified, Status summary): 6 diff lines" \
  || bad "carrier diff has $changed changed lines, expected 6"
grep -q '^| Revision | 4 |$' "$D2/C.md" && ok "--bump-revision incremented Revision 3 -> 4" || bad "Revision not bumped"
tail -n 2 "$D2/orig.md" | cmp -s - <(tail -n 2 "$D2/C.md") && ok "body below the first heading (incl. the look-alike row) is untouched" \
  || bad "body below the first heading changed"
before_sum=$(sha256sum "$D2/C.md" "$D2/A.md" | awk '{print $1}' | tr -d '\n')
python3 "$TOOL" archive --carrier "$D2/C.md" --archive "$D2/A.md" >"$D2/again" 2>&1; rc=$?
after_sum=$(sha256sum "$D2/C.md" "$D2/A.md" | awk '{print $1}' | tr -d '\n')
{ [ "$rc" = 0 ] && grep -q 'already compact' "$D2/again" && [ "$before_sum" = "$after_sum" ]; } \
  && ok "second run on a compact cell is a no-op (rc 0, 'already compact', carrier and archive byte-identical)" \
  || bad "second run is not an idempotent no-op (rc=$rc)"

echo "== real tool: refusals =="
refuse() { # refuse <description> <carrier-body-file>
  python3 "$TOOL" archive --carrier "$1" --archive "$WORK/never.md" >"$WORK/ref.out" 2>&1; local r=$?
  { [ "$r" = 2 ] && [ ! -e "$WORK/never.md" ]; } && ok "$2 -> rc 2, no archive written" || bad "$2 (rc=$r, archive exists: $([ -e "$WORK/never.md" ] && echo yes || echo no))"
  rm -f "$WORK/never.md"
}
printf '# T\n\n| Status summary | a. Prior: b. |\n| Status summary | c |\n\n## H\n' >"$WORK/two.md";  refuse "$WORK/two.md" "two Status summary rows in the preamble"
printf '# T\n\n| Status |x|\n\n## H\n\n| Status summary | a. Prior: b. |\n' >"$WORK/late.md";    refuse "$WORK/late.md" "the only Status summary row sits below the first heading"
printf '# T\n\n| Status summary | a. Prior: b.\n\n## H\n' >"$WORK/nosuffix.md";                           refuse "$WORK/nosuffix.md" "the row does not end with ' |'"
printf '# T\n\n| Status summary |  Prior: b. |\n\n## H\n' >"$WORK/empty.md";                          refuse "$WORK/empty.md" "the newest entry is empty"
printf '# T\n\n| Status summary | only one entry, nothing older |\n\n## H\n' >"$WORK/single.md";        refuse "$WORK/single.md" "no older entries to archive"
printf 'no markers here\n' >"$WORK/badarch.md"
mkcarrier "$WORK/ba.md" "$BODY"
python3 "$TOOL" archive --carrier "$WORK/ba.md" --archive "$WORK/badarch.md" >/dev/null 2>&1; r=$?
{ [ "$r" = 2 ] && [ "$(cat "$WORK/badarch.md")" = "no markers here" ]; } \
  && ok "an existing archive without the entry markers is refused (rc 2) and left untouched" || bad "marker-less archive handled wrongly (rc=$r)"

echo "== paired mutants: each broken copy of the tool must fail the core scenario =="
mutant() { # mutant <name> <python-old> <python-new>   (old must occur exactly once: no tautological mutant)
  local m="$WORK/mut_$1.py"; cp "$TOOL" "$m"
  python3 - "$m" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    print(f"MUTANT NOT APPLIED: pattern occurs {s.count(old)} time(s)")
    sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  local ap=$?
  if [ "$ap" != 0 ]; then bad "mutant $1 could not be applied (the test is stale)"; return; fi
  local k; k=$(run_core "$m" "$WORK/mutrun_$1")
  [ "$k" != 0 ] && ok "mutant $1 killed ($k failing sub-check(s))" || bad "mutant $1 SURVIVED the core scenario"
}
mutant drop_last_entry   'atomic_write(archive, render_archive(carrier.name, entries, revision, created, now))' \
                         'atomic_write(archive, render_archive(carrier.name, entries[:-1], revision, created, now))'
mutant append_not_prepend 'entries = new_entries + old_entries' 'entries = old_entries + new_entries'
mutant no_pointer        'new_body = kept + pointer_sentence(rel_pointer(carrier, archive))' 'new_body = kept'
mutant keep_everything   'return body[: m.start()], body[m.start() + 1 :], pointer' 'return body, "", pointer'
mutant lose_marker_space 'return body[: m.start()], body[m.start() + 1 :], pointer' 'return body[: m.start()], body[m.start() + 2 :], pointer'


echo "== independent rebuild helper (tests/independent_lossless_rebuild.py: no import of the tool) =="
HELPER="$HERE/independent_lossless_rebuild.py"
[ -f "$HELPER" ] || { bad "helper missing: $HELPER"; HELPER=/dev/null; }
helper_suite() { # helper_suite <helper> <dir> -> echoes the number of failing sub-checks (0 = the helper behaves)
  local h="$1" d="$2" f=0 r
  mkdir -p "$d"; mkcarrier "$d/C.md" "$BODY"; cp "$d/C.md" "$d/orig.md"
  python3 "$TOOL" archive --carrier "$d/C.md" --archive "$d/A.md" --bump-revision >/dev/null 2>&1 || f=$((f + 1))
  python3 -I "$h" "$d/orig.md" "$d/C.md" "$d/A.md" >"$d/good.out" 2>&1; r=$?
  { [ "$r" = 0 ] && grep -q 'LOSSLESS' "$d/good.out"; } || f=$((f + 1))
  python3 -I "$h" --figures-only "$d/C.md" "$d/A.md" >/dev/null 2>&1 || f=$((f + 1))
  # six negatives: each must make the helper exit 1 (never 0)
  neg() { python3 -I "$h" "$d/orig.md" "$1" "$2" >/dev/null 2>&1; [ "$?" = 1 ] || f=$((f + 1)); }
  python3 - "$d" <<'PY'
import re, sys
d = sys.argv[1]
a = open(d + "/A.md", encoding="utf-8").read()
c = open(d + "/C.md", encoding="utf-8").read()
blk = a.split("<!-- BEGIN ENTRIES -->", 1)[1].split("<!-- END ENTRIES -->", 1)[0]
ents = [e for e in blk.split("\n") if e.strip()]
def put(name, text): open(d + "/" + name, "w", encoding="utf-8").write(text)
put("A_corrupt.md", a.replace("second entry", "secund entry", 1))
swapped = blk.replace(ents[0], "@@0@@", 1).replace(ents[1], ents[0], 1).replace("@@0@@", ents[1], 1)
put("A_swapped.md", a.replace(blk, swapped, 1))
put("A_dropped.md", a.replace(ents[-1], "", 1))
put("A_header.md", re.sub(r"^- Bytes of moved text: \d+$", "- Bytes of moved text: 1", a, count=1, flags=re.M))
put("C_body.md", c.replace("Body text with a literal", "Body text WITH a literal", 1))
body = c.split("| Status summary | ", 1)[1].split(" |\n", 1)[0]
kept = body.split(" Older entries of this cell", 1)[0]
put("C_reinline.md", c.replace("| Status summary | " + body + " |", "| Status summary | " + kept + " " + " ".join(ents) + " |", 1))
PY
  neg "$d/C.md" "$d/A_corrupt.md"; neg "$d/C.md" "$d/A_swapped.md"; neg "$d/C.md" "$d/A_dropped.md"
  neg "$d/C.md" "$d/A_header.md"; neg "$d/C_body.md" "$d/A.md"
  python3 -I "$h" "$d/orig.md" "$d/C_reinline.md" "$d/A.md" >/dev/null 2>&1; [ "$?" = 1 ] || f=$((f + 1))
  # usage / format errors are rc 2, not a verdict
  python3 -I "$h" "$d/orig.md" >/dev/null 2>&1; [ "$?" = 2 ] || f=$((f + 1))
  printf '# T\n\n| Status summary | a. |\n| Status summary | b. |\n\n## H\n' >"$d/two.md"
  python3 -I "$h" "$d/two.md" "$d/C.md" "$d/A.md" >/dev/null 2>&1; [ "$?" = 2 ] || f=$((f + 1))
  echo "$f"
}
n=$(helper_suite "$HELPER" "$WORK/helper_real"); [ "$n" = 0 ] && ok "helper: golden-good LOSSLESS + figures-only + 6 negatives rc 1 + 2 usage/format errors rc 2 (0 failing sub-checks)" || bad "helper suite has $n failing sub-check(s)"
hmutant() { # hmutant <name> <old> <new>
  local m="$WORK/hmut_$1.py"; cp "$HELPER" "$m"
  python3 - "$m" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    print("MUTANT NOT APPLIED: %d occurrences" % s.count(old)); sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  [ "$?" = 0 ] || { bad "helper mutant $1 could not be applied (the test is stale)"; return; }
  local k; k=$(helper_suite "$m" "$WORK/hmutrun_$1")
  [ "$k" != 0 ] && ok "helper mutant $1 killed ($k failing sub-check(s))" || bad "helper mutant $1 SURVIVED"
}
hmutant always_lossless  'return row_of(kept, entries) == orig_row' 'return True'
hmutant join_without_space 'return CELL + kept + " " + " ".join(entries) + " |"' 'return CELL + kept + " " + "".join(entries) + " |"'
hmutant figures_unchecked 'return n == len(entries) and b == len(moved.encode("utf-8")) and h == sha(moved)' 'return True'
hmutant other_lines_ignored 'legal = set(differing) <= {"Revision", "Last modified"} and rev_ok' 'legal = True'

echo "== real carriers: QWEN.md and GEMINI.md of this checkout (job 2) =="
CR="${CARRIER_ROOT:-$(cd "$HERE/../../.." && pwd)}"
rc_mutate() { # rc_mutate <dir> <carrier-name> <archive-name> <kind>  (edits the COPIES only)
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
d, car, arc, kind = sys.argv[1:5]
cp, ap = d + "/" + car, d + "/docs/amendment-log/" + arc
L = open(cp, encoding="utf-8").read().split("\n")
i = next(k for k, l in enumerate(L) if l.startswith("| Status summary | "))
body = L[i][len("| Status summary | "):-2]
mark = " Older entries of this cell"
head, ptr = body.split(mark, 1); ptr = mark + ptr
A = open(ap, encoding="utf-8").read()
ents = [e for e in A.split("<!-- BEGIN ENTRIES -->")[1].split("<!-- END ENTRIES -->")[0].split("\n") if e.strip()]
if kind == "corrupt":
    assert "Amendment of" in A; open(ap, "w", encoding="utf-8").write(A.replace("Amendment of", "Amendmenx of", 1)); sys.exit(0)
if kind == "noarchive":
    import os; os.remove(ap); sys.exit(0)
if kind == "nopointer":
    L[i] = "| Status summary | " + head + " |"
elif kind == "reinline":
    L[i] = "| Status summary | " + head + " " + " ".join(ents) + " |"
elif kind == "inline":
    L[i] = "| Status summary | " + head + " Prior: an older entry left inline." + ptr + " |"
else:
    raise SystemExit("unknown kind " + kind)
open(cp, "w", encoding="utf-8").write("\n".join(L))
PY
}
for pair in "QWEN.md status-summary-qwen.md" "GEMINI.md status-summary-gemini.md"; do
  set -- $pair; car="$CR/$1"; arc="$CR/docs/amendment-log/$2"
  if [ ! -f "$car" ]; then echo "  SKIP  $1 not present under $CR: the real-carrier checks for it were NOT run"; continue; fi
  python3 "$TOOL" verify --carrier "$car" --archive "$arc" >"$WORK/rv_$1.out" 2>&1 \
    && ok "real $1: verify passes ($(tail -n 1 "$WORK/rv_$1.out" | cut -c1-100))" || bad "real $1: verify FAILS: $(head -n 2 "$WORK/rv_$1.out" | tr '\n' ' ' | cut -c1-160)"
  python3 -I "$HELPER" --figures-only "$car" "$arc" >"$WORK/rf_$1.out" 2>&1 \
    && ok "real $1: independent figure re-computation (no tool import) passes" || bad "real $1: independent figure re-computation FAILS: $(tail -n 3 "$WORK/rf_$1.out" | tr '\n' ' ' | cut -c1-160)"
  pre=$(LC_ALL=C awk '/^## /{exit} {print}' "$car" | grep -c '11\.4\.290'); blocks=$(grep -c '^\*\*§11\.4\.290 — ' "$car")
  { [ "$pre" = 0 ] && [ "$blocks" = 1 ]; } && ok "real $1: the §11.4.290 anchor block-start occurs exactly once and not in the preamble (preamble hits $pre, block-starts $blocks)" \
    || bad "real $1: §11.4.290 anchor not intact (preamble hits $pre, block-starts $blocks; expected 0 and 1)"
  rd="$WORK/rc_$1"; mkdir -p "$rd/docs/amendment-log"; cp "$car" "$rd/$1"; cp "$arc" "$rd/docs/amendment-log/$2"
  s0=$(sha256sum "$rd/$1" "$rd/docs/amendment-log/$2" | awk '{print $1}' | tr -d '\n')
  python3 "$TOOL" archive --carrier "$rd/$1" --archive "$rd/docs/amendment-log/$2" >"$rd/again.out" 2>&1; r=$?
  s1=$(sha256sum "$rd/$1" "$rd/docs/amendment-log/$2" | awk '{print $1}' | tr -d '\n')
  { [ "$r" = 0 ] && grep -q 'already compact' "$rd/again.out" && [ "$s0" = "$s1" ]; } && ok "real $1: re-running archive is a no-op (rc 0, 'already compact', byte-identical)" || bad "real $1: re-run not idempotent (rc=$r)"
  for kind in corrupt noarchive nopointer reinline inline; do
    md="$WORK/rcm_${kind}_$1"; mkdir -p "$md/docs/amendment-log"; cp "$car" "$md/$1"; cp "$arc" "$md/docs/amendment-log/$2"
    rc_mutate "$md" "$1" "$2" "$kind" >/dev/null 2>&1 || { bad "real $1: mutant $kind could not be applied"; continue; }
    python3 "$TOOL" verify --carrier "$md/$1" --archive "$md/docs/amendment-log/$2" >"$md/v.out" 2>&1; r=$?
    [ "$r" = 1 ] && ok "real $1: mutant $kind killed by verify (rc 1: $(head -n 1 "$md/v.out" | cut -c1-90))" || bad "real $1: mutant $kind SURVIVED verify (rc=$r)"
  done
done

echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" = 0 ]
