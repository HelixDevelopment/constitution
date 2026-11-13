#!/usr/bin/env bash
# tests/workable_items/test_remint_ids.sh -- hermetic test of scripts/workable-items/remint_ids.py.
#
# Documentation (section 11.4.18): docs/guides/remint_ids_guide.md.
#
# WHAT  (1) rewrite: tokens, ranges, no chaining, id boundaries, Foreign lines, the refusals (a
#       partly mapped range, a range whose new ids are not contiguous, a .db file, a binary file),
#       dry run writes nothing, a refusal writes no file at all; (2) plan: order, width, the next
#       free number, the collision refusal, the BLIND exits; (3) replay and verify against the REAL
#       engine: a vehicle and a colliding target built from a scratch copy of docs/workable_items.db
#       with the engine (Queued, states, Obsolete duplicate-of, Reopened items), replay onto the
#       target copy, verify PASS, validate adds no finding; a second replay is refused before any write; a
#       changed description and a missing item make verify FAIL.
# ENV   WORKABLE_ITEMS  path of the workable-items engine binary (default: the tracked
#                       scripts/workable-items/bin/workable-items; exit 2 when not executable)
#       REMINT_IDS      path of the tool to test (default: the repository copy)
# EXIT  0 all cases pass; 1 a case failed; 2 setup error, or the cleanup of the temp dir was refused.
# EVIDENCE CLASS  gate-logic (section 11.4.289): real engine, scratch copies, no tracker database written.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
tool=${REMINT_IDS:-$root/scripts/workable-items/remint_ids.py}
wi=${WORKABLE_ITEMS:-$root/scripts/workable-items/bin/workable-items}
realdb=$root/docs/workable_items.db
[ -f "$tool" ] || { echo "setup: tool not found: $tool" >&2; exit 2; }
[ -x "$wi" ] || { echo "setup: engine binary not executable: $wi (set WORKABLE_ITEMS)" >&2; exit 2; }
[ -f "$realdb" ] || { echo "setup: $realdb missing" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2; exit 2; fi
  exit "$st"
}
trap cleanup EXIT

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1: $2"; }
t() { python3 -I "$tool" "$@" >"$tmp/out" 2>&1; rc=$?; }
expect() { # expect <name> <want-rc> <pattern-or-empty> <args...>
  local name=$1 want=$2 pat=$3; shift 3
  t "$@"
  if [ "$rc" != "$want" ]; then bad "$name" "rc=$rc want=$want: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; return; fi
  if [ -n "$pat" ] && ! grep -Eq -- "$pat" "$tmp/out"; then bad "$name" "/$pat/ not in: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; return; fi
  ok "$name"
}
same() { # same <name> <file> <expected text>
  if [ "$(cat "$2")" = "$3" ]; then ok "$1"; else bad "$1" "got: $(tr '\n' '|' <"$2")"; fi
}

# ---- (1) rewrite ----
printf 'old\tnew\nCON-1\tCON-2\nCON-2\tCON-3\nCON-5\tCON-20\nCON-6\tCON-21\nCON-7\tCON-22\nCON-8\tCON-30\n' >"$tmp/m.tsv"
printf 'see CON-1 and CON-2; CON-12 CON-1-x xCON-1 stays\nrange CON-5..CON-7 here\nFX-1 too\n' >"$tmp/a.txt"
expect "rewrite dry run counts" 0 '^RESULT: DRY-RUN files=1 replaced=3$' rewrite --map "$tmp/m.tsv" "$tmp/a.txt"
same "rewrite dry run writes nothing" "$tmp/a.txt" "$(printf 'see CON-1 and CON-2; CON-12 CON-1-x xCON-1 stays\nrange CON-5..CON-7 here\nFX-1 too')"
expect "rewrite --write" 0 '^RESULT: WRITTEN files=1 replaced=3$' rewrite --map "$tmp/m.tsv" --write "$tmp/a.txt"
same "tokens, no chaining, boundaries, range" "$tmp/a.txt" "$(printf 'see CON-2 and CON-3; CON-12 CON-1-x xCON-1 stays\nrange CON-20..CON-22 here\nFX-1 too')"
printf 'Foreign ids (another tracker): CON-1, CON-5..CON-7\nhere CON-1 is foreign, CON-2 is ours\n' >"$tmp/f.txt"
expect "Foreign line and its ids left alone" 0 'replaced=1$' rewrite --map "$tmp/m.tsv" --write "$tmp/f.txt"
same "Foreign line text" "$tmp/f.txt" "$(printf 'Foreign ids (another tracker): CON-1, CON-5..CON-7\nhere CON-1 is foreign, CON-3 is ours')"
printf 'Foreign ids (copied from the CON-8 notes): CON-1\nours CON-8\n' >"$tmp/f2.txt"
expect "Foreign line left alone before its colon too" 0 'replaced=1$' rewrite --map "$tmp/m.tsv" --write "$tmp/f2.txt"
same "Foreign line text before its colon" "$tmp/f2.txt" "$(printf 'Foreign ids (copied from the CON-8 notes): CON-1\nours CON-30')"
printf 'see CON-2\n' >"$tmp/x.txt"
expect "--foreign excludes an id" 0 'replaced=0$' rewrite --map "$tmp/m.tsv" --foreign CON-2 "$tmp/x.txt"
printf 'see CON-2\n' >"$tmp/ok.txt"; printf 'partial CON-4..CON-6\n' >"$tmp/p.txt"
expect "partly mapped range refused" 1 'partly mapped' rewrite --map "$tmp/m.tsv" --write "$tmp/ok.txt" "$tmp/p.txt"
same "a refusal writes no file at all" "$tmp/ok.txt" "see CON-2"
printf 'gap CON-7..CON-8\n' >"$tmp/g.txt"
expect "range with non-contiguous new ids refused" 1 'not contiguous' rewrite --map "$tmp/m.tsv" "$tmp/g.txt"
: >"$tmp/z.db"
expect "a .db file refused" 1 'database or bundle' rewrite --map "$tmp/m.tsv" "$tmp/z.db"
printf 'CON-1\0bin' >"$tmp/b.bin"
expect "a binary file refused" 1 'binary' rewrite --map "$tmp/m.tsv" "$tmp/b.bin"
printf 'old\tnew\nCON-1\tCON-2\nCON-1\tCON-3\n' >"$tmp/dup.tsv"
expect "map naming an id twice is BLIND" 3 'twice' rewrite --map "$tmp/dup.tsv" "$tmp/x.txt"
printf 'CON-1\tCON-2\n' >"$tmp/nohdr.tsv"
expect "map without header is BLIND" 3 'header' rewrite --map "$tmp/nohdr.tsv" "$tmp/x.txt"
expect "usage: no subcommand" 2 ''

# ---- (2) plan on minimal fixture databases ----
mkdb() { # mkdb <db> <id>...
  local db=$1; shift
  python3 -I - "$db" "$@" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("create table items (atm_id text)")
c.executemany("insert into items values (?)", [(i,) for i in sys.argv[2:]]); c.commit()
PY
}
mkdb "$tmp/base.db" CON-001 CON-002 CON-003
mkdb "$tmp/veh.db" CON-001 CON-002 CON-003 CON-004 CON-005 AA-001
mkdb "$tmp/tgt.db" CON-001 CON-002 CON-003 CON-004 CON-005 CON-006
expect "plan maps own ids in order to max(target)+1" 0 '^RESULT: PLAN own=2 first=CON-007 last=CON-008$' plan --vehicle-db "$tmp/veh.db" --base-db "$tmp/base.db" --target-db "$tmp/tgt.db" --out "$tmp/p.tsv"
same "plan map file" "$tmp/p.tsv" "$(printf 'old\tnew\nCON-004\tCON-007\nCON-005\tCON-008')"
mkdb "$tmp/base2.db" CON-001 CON-009
mkdb "$tmp/veh2.db" CON-001 CON-009 CON-006 CON-007 CON-008 CON-010
mkdb "$tmp/tgt2.db" CON-001 CON-005
expect "plan refuses a new id held by an item that stays" 1 'CON-009 is an item of the vehicle that is not moved' plan --vehicle-db "$tmp/veh2.db" --base-db "$tmp/base2.db" --target-db "$tmp/tgt2.db"
expect "plan BLIND when nothing is own" 3 'no own id' plan --vehicle-db "$tmp/base.db" --base-db "$tmp/base.db" --target-db "$tmp/tgt.db"
expect "plan BLIND when a database is missing" 3 'database not found' plan --vehicle-db "$tmp/none.db" --base-db "$tmp/base.db" --target-db "$tmp/tgt.db"
mkdb "$tmp/aa.db" AA-001
expect "plan BLIND when the target holds no id of the prefix" 3 'holds no CON id' plan --vehicle-db "$tmp/veh.db" --base-db "$tmp/base.db" --target-db "$tmp/aa.db"

# ---- (3) replay and verify with the real engine ----
repo=$tmp/repo; mkdir -p "$repo/docs/qa" && printf 'evidence\n' >"$repo/docs/qa/x.txt" || exit 2
cp "$realdb" "$tmp/b.db" && cp "$realdb" "$repo/docs/v.db" && cp "$realdb" "$repo/docs/t.db" || exit 2
n=$(python3 -I -c 'import sqlite3,sys;c=sqlite3.connect("file:%s?mode=ro"%sys.argv[1],uri=True);print(max(int(r[0][4:]) for r in c.execute("select atm_id from items where atm_id like '"'CON-%'"'")))' "$tmp/b.db") || exit 2
id() { printf 'CON-%03d' "$(( n + $1 ))"; }
W() { (cd "$repo" && "$wi" "$@") >>"$tmp/engine.log" 2>&1 || { echo "setup: engine step failed: $*" >&2; tail -3 "$tmp/engine.log" >&2; exit 2; }; }
D="**What:** remint fixture item for the remint_ids test, never landed in a tracker."
W add Task Low --db docs/v.db --id "$(id 1)" --title "Remint fixture alpha item" --description "$D Parent / links: see $(id 3) (remint fixture gamma) and the range $(id 1)..$(id 2)." --created-by Claude
W add Bug Medium --db docs/v.db --id "$(id 2)" --title "Remint fixture beta item" --description "$D Links to $(id 1)." --created-by Claude \
  --reproduction-state UNREPRODUCED --investigation-state not-started --states-updated-by "remint test" --states-updated-at 2026-11-13T10:00:00Z
W add Task Low --db docs/v.db --id "$(id 3)" --title "Remint fixture gamma item" --description "$D Duplicate of $(id 1)." --created-by Claude
W close "$(id 3)" --db docs/v.db --status obsolete --evidence docs/qa/x.txt
W obsolete-details "$(id 3)" --db docs/v.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 1)" --evidence docs/qa/x.txt
W add Task Low --db docs/v.db --id "$(id 4)" --title "Remint fixture delta item" --description "$D Was closed onto $(id 2), then reopened." --created-by Claude
W close "$(id 4)" --db docs/v.db --status obsolete --evidence docs/qa/x.txt
W obsolete-details "$(id 4)" --db docs/v.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 2)" --evidence docs/qa/x.txt
W reopen --id "$(id 4)" --db docs/v.db --why design-reconsidered --who AI --when 2026-11-13 --incident docs/qa/x.txt
W add Task Low --db docs/t.db --id "$(id 1)" --title "Colliding target item one" --description "$D A target item that holds the same number." --created-by Claude
W add Task Low --db docs/t.db --id "$(id 2)" --title "Colliding target item two" --description "$D A target item that holds the same number." --created-by Claude
(cd "$repo" && python3 -I "$tool" plan --vehicle-db docs/v.db --base-db "$tmp/b.db" --target-db docs/t.db --out "$tmp/r.tsv") >"$tmp/out" 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q "^RESULT: PLAN own=4 first=$(id 3) last=$(id 6)\$" "$tmp/out"; then ok "plan on engine-built databases"
else bad "plan on engine-built databases" "rc=$rc $(tr '\n' '|' <"$tmp/out")"; fi
(cd "$repo" && python3 -I "$tool" replay --map "$tmp/r.tsv" --vehicle-db docs/v.db) >"$tmp/plan.jsonl" 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q '^RESULT: DRY-RUN steps=9 items=4$' "$tmp/plan.jsonl"; then
  if grep -qF "see $(id 5) (remint fixture gamma) and the range $(id 3)..$(id 4)." "$tmp/plan.jsonl"; then ok "replay dry run rewrites text without chaining"
  else bad "replay dry run rewrites text without chaining" "$(grep -m1 alpha "$tmp/plan.jsonl" | cut -c1-300)"; fi
else bad "replay dry run" "rc=$rc $(tail -2 "$tmp/plan.jsonl" | tr '\n' '|')"; fi
cp "$repo/docs/t.db" "$tmp/t.before" || exit 2
# validate reads every item of the copied real database, and the evidence of the real items is not
# in this scratch repo; so the check is that the replay adds no finding validate did not already
# report before it (the findings of the real items are the same lines before and after).
(cd "$repo" && "$wi" validate --db docs/t.db) >"$tmp/val.before" 2>&1
(cd "$repo" && python3 -I "$tool" replay --map "$tmp/r.tsv" --vehicle-db docs/v.db --apply --engine "$wi" --db docs/t.db) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q '^RESULT: APPLIED steps=9 items=4$' "$tmp/out"; then ok "replay --apply through the engine"
else bad "replay --apply through the engine" "rc=$rc $(tail -4 "$tmp/out" | tr '\n' '|')"; fi
(cd "$repo" && "$wi" validate --db docs/t.db) >"$tmp/val.after" 2>&1
grep '^  - ' "$tmp/val.before" | sort >"$tmp/val.b"; grep '^  - ' "$tmp/val.after" | sort >"$tmp/val.a"
newf=$(comm -13 "$tmp/val.b" "$tmp/val.a")
# control needle (§11.4.273): the same comm path must see one added finding line
{ cat "$tmp/val.a"; echo "  - $(id 3) [needle]: x"; } | sort >"$tmp/val.n"
needle=$(comm -13 "$tmp/val.b" "$tmp/val.n")
if [ -s "$tmp/val.after" ] && [ -n "$needle" ] && [ -z "$newf" ] && ! grep -qE "$(id 3)|$(id 4)|$(id 5)|$(id 6)" "$tmp/val.a"; then ok "validate reports no new finding on the replayed target"
else bad "validate reports no new finding on the replayed target" "$(printf '%s' "$newf" | head -3 | tr '\n' '|' | cut -c1-400)"; fi
(cd "$repo" && python3 -I "$tool" verify --map "$tmp/r.tsv" --vehicle-db docs/v.db --db docs/t.db) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q '^RESULT: PASS items=4 mismatches=0$' "$tmp/out"; then ok "verify PASS after replay"
else bad "verify PASS after replay" "rc=$rc $(tr '\n' '|' <"$tmp/out" | cut -c1-400)"; fi
python3 -I - "$repo/docs/t.db" "$(id 5)" "$(id 6)" "$(id 3)" "$(id 4)" >"$tmp/out" 2>&1 <<'PY'
import sqlite3, sys
c = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
g, d, a, b = sys.argv[2:6]
print(c.execute("select status, current_location from items where atm_id=?", (g,)).fetchone())
print(c.execute("select reason, superseding_item from obsolete_details where atm_id=?", (g,)).fetchone())
print(c.execute("select status from items where atm_id=?", (d,)).fetchone())
print(c.execute("select superseding_item from obsolete_details where atm_id=?", (d,)).fetchone())
PY
if grep -q "('Obsolete" "$tmp/out" && grep -q "('duplicate-of', '$(id 3)')" "$tmp/out" && grep -q "('Reopened',)" "$tmp/out" && grep -q "('$(id 4)',)" "$tmp/out"; then
  ok "statuses and superseding ids replayed (gamma Obsolete onto alpha, delta Reopened)"
else bad "statuses and superseding ids replayed" "$(tr '\n' '|' <"$tmp/out")"; fi
cp "$repo/docs/t.db" "$tmp/t.after" || exit 2
(cd "$repo" && python3 -I "$tool" replay --map "$tmp/r.tsv" --vehicle-db docs/v.db --apply --engine "$wi" --db docs/t.db) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" = 1 ] && grep -q 'already holds new id' "$tmp/out" && cmp -s "$repo/docs/t.db" "$tmp/t.after"; then ok "second replay refused before any write"
else bad "second replay refused before any write" "rc=$rc $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; fi
cp "$repo/docs/t.db" "$repo/docs/t2.db" || exit 2
W update --id "$(id 3)" --db docs/t2.db --description "$D A description changed after the replay."
(cd "$repo" && python3 -I "$tool" verify --map "$tmp/r.tsv" --vehicle-db docs/v.db --db docs/t2.db) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" = 1 ] && grep -q "^MISMATCH $(id 3): description differs" "$tmp/out"; then ok "verify FAILs on a changed description"
else bad "verify FAILs on a changed description" "rc=$rc $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; fi
(cd "$repo" && python3 -I "$tool" verify --map "$tmp/r.tsv" --vehicle-db docs/v.db --db "$tmp/t.before") >"$tmp/out" 2>&1; rc=$?
if [ "$rc" = 1 ] && grep -q "^MISMATCH $(id 3): 0 rows in the result" "$tmp/out"; then ok "verify FAILs when the items are missing"
else bad "verify FAILs when the items are missing" "rc=$rc $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; fi
if cmp -s "$realdb" "$tmp/b.db"; then ok "the real database is untouched"; else bad "the real database is untouched" "changed"; fi

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
