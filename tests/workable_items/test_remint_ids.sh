#!/usr/bin/env bash
# tests/workable_items/test_remint_ids.sh -- hermetic test of scripts/workable-items/remint_ids.py.
#
# Documentation (section 11.4.18): docs/guides/remint_ids_guide.md.
#
# WHAT  (1) rewrite: tokens, ranges, no chaining, id boundaries, Foreign lines, every refusal of the
#       rewriter (partly moved, not contiguous, short form, reverse, mixed foreign, zero padding, path,
#       an id the target also holds), every map guard (header, a line that does not parse, an id
#       named twice, two old ids onto one new id, mixed prefixes, an empty map), a .db, binary or
#       non-UTF-8 file, and that a refusal writes no file at all; (2) refs: the LIVE, EVIDENCE and
#       DATABASE classes in a scratch git repository; (3) plan, replay and verify against the REAL
#       engine: base, vehicle and target trackers built from a scratch copy of docs/workable_items.db
#       by engine commands only. The vehicle adds five own items (an assignee, both state blocks with
#       their stamps, an Obsolete duplicate, a reopened Obsolete duplicate, a status change, a Foreign
#       ids line that keeps a fix227 id) and changes five base items (a description, a state block, a
#       close with its obsolete_details row, a rewritten obsolete_details row, a reopen); the target
#       adds two colliding items and changes two base items (one disjoint merge, one target-only
#       title). The landing must carry every base-item change (round-3 finding R3-1), keep the item's
#       foreign ids on every column (R3-2), carry the obsolete_details row on every lifecycle path
#       (round 4), and verify must PASS. Then: FAST-FORWARD and --no-fast-forward, the conflicts
#       (both sides, lifecycle against a change, a deleted target item) and --resolve both ways,
#       every plan refusal and BLIND exit, the replay guards (a plan with conflicts, a FAST-FORWARD
#       plan, a target copy with another sha256, a non-empty -wal sidecar, a second replay), and
#       verify FAIL needles (a changed description, a re-pointed foreign id, a status, an untouched
#       target item, a lost base change, an obsolete_details field, a missing Opened row, a closure
#       row citing other evidence, a changed Reopened row, a target history row, another table,
#       missing and extra items, a map that is not the own set, doc_segments). A few states have no
#       engine path (a deleted base row, a raw body_md edit, a missing history row): those fixtures
#       are raw edits of SCRATCH copies (fx_sql, which refuses the real database).
# ENV   WORKABLE_ITEMS  path of the workable-items engine binary (default: the tracked
#                       scripts/workable-items/bin/workable-items; exit 2 when not executable)
#       REMINT_IDS      path of the tool to test (default: the repository copy)
#       REMINT_IDS_ROOT repository root (default: two levels above this file; set when running a copy)
#       REMINT_IDS_FAILFAST=1  stop at the first failing case (the mutation suite: a kill is a kill)
# EXIT  0 all cases pass; 1 a case failed; 2 setup error, or the cleanup of the temp dir was refused.
# EVIDENCE CLASS  gate-logic (section 11.4.289): real engine, scratch copies, no tracker database written.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=${REMINT_IDS_ROOT:-$(cd "$here/../.." && pwd)} || exit 2
tool=${REMINT_IDS:-$root/scripts/workable-items/remint_ids.py}
wi=${WORKABLE_ITEMS:-$root/scripts/workable-items/bin/workable-items}
realdb=$root/docs/workable_items.db
[ -f "$tool" ] || { echo "setup: tool not found: $tool" >&2; exit 2; }
[ -x "$wi" ] || { echo "setup: engine binary not executable: $wi (set WORKABLE_ITEMS)" >&2; exit 2; }
[ -f "$realdb" ] || { echo "setup: $realdb missing" >&2; exit 2; }
command -v git >/dev/null || { echo "setup: git not found" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2; exit 2; fi
  exit "$st"
}
trap cleanup EXIT
real_sha=$(sha256sum "$realdb" | cut -d' ' -f1) || exit 2

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() {
  fail=$((fail + 1)); echo "FAIL $1: $2"
  if [ "${REMINT_IDS_FAILFAST:-}" = 1 ]; then echo "RESULT: pass=$pass fail=$fail (stopped at the first failure)"; exit 1; fi
}
check() { # check <name> <want-rc> <pattern-or-empty>  (reads $rc and $tmp/out)
  if [ "$rc" != "$2" ]; then bad "$1" "rc=$rc want=$2: $(tr '\n' '|' <"$tmp/out" | cut -c1-400)"; return; fi
  if [ -n "$3" ] && ! grep -Eq -- "$3" "$tmp/out"; then bad "$1" "/$3/ not in: $(tr '\n' '|' <"$tmp/out" | cut -c1-400)"; return; fi
  ok "$1"
}
expect() { # expect <name> <want-rc> <pattern-or-empty> <args...>  (run in the current directory)
  local name=$1 want=$2 pat=$3; shift 3
  python3 -I "$tool" "$@" >"$tmp/out" 2>&1; rc=$?
  check "$name" "$want" "$pat"
}
xp() { # xp <name> <want-rc> <pattern-or-empty> <args...>  (run in the fixture repository)
  local name=$1 want=$2 pat=$3; shift 3
  (cd "$repo" && python3 -I "$tool" "$@") >"$tmp/out" 2>&1; rc=$?
  check "$name" "$want" "$pat"
}
same() { # same <name> <got> <expected>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-300) want: $(printf '%s' "$3" | tr '\n' '|' | cut -c1-300)"; fi
}
q() { # q <db> <sql> [params...]: read-only query, one line per row, fields joined by |
  python3 -I - "$@" <<'PY'
import sqlite3, sys
c = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
for r in c.execute(sys.argv[2], sys.argv[3:]):
    print("|".join("" if x is None else str(x) for x in r))
PY
}
fx_sql() { # fx_sql <db> <sql> [params...]: a raw edit of a SCRATCH copy, only for a state no engine command produces
  local a b
  a=$(readlink -f "$1") && b=$(readlink -f "$realdb") || return 2
  [ "$a" != "$b" ] || { echo "setup: fx_sql refuses the real database" >&2; exit 2; }
  case "$a" in "$tmp"/*) ;; *) echo "setup: fx_sql edits only scratch copies under the temp dir" >&2; exit 2 ;; esac
  # a fixture edit that fails (a CHECK constraint, a typo) is a setup error, never a silently unchanged copy
  python3 -I - "$@" <<'PY' || { echo "setup: fx_sql failed: $2" >&2; exit 2; }
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
n = c.execute(sys.argv[2], sys.argv[3:]).rowcount
c.commit()
c.close()
if n == 0:  # DML that matched no row; DDL reports -1
    sys.exit("fx_sql changed no row")
PY
}

# ---- (1) rewrite ----
cd "$tmp" || exit 2
printf 'old\tnew\nCON-1\tCON-2\nCON-2\tCON-3\nCON-5\tCON-20\nCON-6\tCON-21\nCON-7\tCON-22\nCON-8\tCON-30\n' >"$tmp/m.tsv"
printf 'see CON-1 and CON-2; CON-12 CON-1-x xCON-1 stays\nrange CON-5..CON-7 here, end CON-8.\nFX-1 too\n' >"$tmp/a.txt"
expect "rewrite dry run counts" 0 '^RESULT: DRY-RUN files=1 replaced=4$' rewrite --map "$tmp/m.tsv" "$tmp/a.txt"
same "rewrite dry run writes nothing" "$(cat "$tmp/a.txt")" "$(printf 'see CON-1 and CON-2; CON-12 CON-1-x xCON-1 stays\nrange CON-5..CON-7 here, end CON-8.\nFX-1 too')"
expect "rewrite --write without --target-db is a usage error" 2 'needs --target-db' rewrite --map "$tmp/m.tsv" --write "$tmp/a.txt"
printf 'old\tnew\nCON-90\tCON-91\n' >"$tmp/m90.tsv"
q0() { python3 -I -c 'import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute("create table items (atm_id text)");c.executemany("insert into items values (?)",[(i,) for i in sys.argv[2:]]);c.commit()' "$@"; }
q0 "$tmp/tg.db" CON-1 CON-90 || exit 2
expect "rewrite --write" 0 '^RESULT: WRITTEN files=1 replaced=4$' rewrite --map "$tmp/m.tsv" --write --target-db "$tmp/tg.db" --own CON-1 "$tmp/a.txt"
same "tokens, no chaining, boundaries, range, sentence dot" "$(cat "$tmp/a.txt")" "$(printf 'see CON-2 and CON-3; CON-12 CON-1-x xCON-1 stays\nrange CON-20..CON-22 here, end CON-30.\nFX-1 too')"
printf 'see CON-90\n' >"$tmp/amb.txt"
expect "an id the target also holds is refused as ambiguous" 1 'target also holds CON-90; declare it' rewrite --map "$tmp/m90.tsv" --target-db "$tmp/tg.db" "$tmp/amb.txt"
expect "--own declares the ambiguous id" 0 'replaced=1$' rewrite --map "$tmp/m90.tsv" --target-db "$tmp/tg.db" --own CON-90 "$tmp/amb.txt"
expect "--foreign declares the ambiguous id" 0 'replaced=0$' rewrite --map "$tmp/m90.tsv" --target-db "$tmp/tg.db" --foreign CON-90 "$tmp/amb.txt"
printf 'Foreign ids (another tracker): CON-1, CON-5..CON-7\nhere CON-1 is foreign, CON-2 is ours\n' >"$tmp/f.txt"
expect "Foreign line and its ids left alone in the whole file" 0 'replaced=1$' rewrite --map "$tmp/m.tsv" --write --target-db "$tmp/tg.db" "$tmp/f.txt"
same "Foreign line text" "$(cat "$tmp/f.txt")" "$(printf 'Foreign ids (another tracker): CON-1, CON-5..CON-7\nhere CON-1 is foreign, CON-3 is ours')"
printf 'Foreign ids (copied from the CON-8 notes): CON-1\nours CON-8\n' >"$tmp/f2.txt"
expect "Foreign line left alone before its colon too" 0 'replaced=1$' rewrite --map "$tmp/m.tsv" --write --target-db "$tmp/tg.db" "$tmp/f2.txt"
same "Foreign line text before its colon" "$(cat "$tmp/f2.txt")" "$(printf 'Foreign ids (copied from the CON-8 notes): CON-1\nours CON-30')"
printf 'see CON-2\n' >"$tmp/x.txt"
expect "--foreign excludes an id" 0 'replaced=0$' rewrite --map "$tmp/m.tsv" --foreign CON-2 "$tmp/x.txt"
expect "--foreign that does not parse is BLIND" 3 'cannot read id list item' rewrite --map "$tmp/m.tsv" --foreign 'two' "$tmp/x.txt"
printf 'see CON-2\n' >"$tmp/ok.txt"; printf 'partial CON-4..CON-6\n' >"$tmp/p.txt"
expect "partly moved range refused" 1 'is partly moved \(2 of 3 ids\)' rewrite --map "$tmp/m.tsv" --write --target-db "$tmp/tg.db" "$tmp/ok.txt" "$tmp/p.txt"
same "a refusal writes no file at all (the first file is checked before any write)" "$(cat "$tmp/ok.txt")" "see CON-2"
printf 'gap CON-7..CON-8\n' >"$tmp/g.txt"
expect "range with non-contiguous new ids refused" 1 'not contiguous' rewrite --map "$tmp/m.tsv" "$tmp/g.txt"
printf 'short CON-5..7\n' >"$tmp/s.txt"
expect "short-form range refused" 1 'short-form range CON-5\.\.7' rewrite --map "$tmp/m.tsv" "$tmp/s.txt"
printf 'back CON-7..CON-5\n' >"$tmp/r.txt"
expect "reverse range refused" 1 'reverse range CON-7\.\.CON-5' rewrite --map "$tmp/m.tsv" "$tmp/r.txt"
printf 'Foreign ids (other): CON-6\nrange CON-5..CON-7\n' >"$tmp/mx.txt"
expect "range mixing foreign and moved ids refused" 1 'mixes foreign and moved ids' rewrite --map "$tmp/m.tsv" "$tmp/mx.txt"
printf 'padded CON-001\n' >"$tmp/z.txt"
expect "a zero-padded token of a moved id refused" 1 'CON-001 names moved CON-1 with a different zero padding' rewrite --map "$tmp/m.tsv" "$tmp/z.txt"
printf 'evidence docs/qa/CON-1/x.txt\n' >"$tmp/pa.txt"
expect "an id inside a path refused (slash)" 1 'part of a path' rewrite --map "$tmp/m.tsv" "$tmp/pa.txt"
printf 'see CON-1.md\n' >"$tmp/pb.txt"
expect "an id inside a path refused (extension)" 1 'part of a path' rewrite --map "$tmp/m.tsv" "$tmp/pb.txt"
: >"$tmp/z.db"
expect "a .db file refused" 1 'database or bundle' rewrite --map "$tmp/m.tsv" "$tmp/z.db"
printf 'CON-1\0bin' >"$tmp/b.bin"
expect "a binary file refused" 1 'binary' rewrite --map "$tmp/m.tsv" "$tmp/b.bin"
printf 'see CON-1 \xff\xfe\n' >"$tmp/u.txt"
expect "a non-UTF-8 file is BLIND" 3 'not UTF-8' rewrite --map "$tmp/m.tsv" "$tmp/u.txt"
printf 'old\tnew\nCON-1\tCON-2\nCON-1\tCON-3\n' >"$tmp/dup.tsv"
expect "map naming an id twice is BLIND" 3 'map names CON-1 twice' rewrite --map "$tmp/dup.tsv" "$tmp/x.txt"
printf 'old\tnew\nCON-1\tCON-9\nCON-2\tCON-9\n' >"$tmp/two.tsv"
expect "map giving two old ids one new id is BLIND" 3 'two old ids one new id' rewrite --map "$tmp/two.tsv" "$tmp/x.txt"
printf 'old\tnew\nCON-1\tCON-9\nAA-2\tAA-3\n' >"$tmp/mix.tsv"
expect "map mixing prefixes is BLIND" 3 'mixes prefixes: AA,CON' rewrite --map "$tmp/mix.tsv" "$tmp/x.txt"
printf 'old\tnew\n' >"$tmp/empty.tsv"
expect "empty map is BLIND" 3 'map is empty' rewrite --map "$tmp/empty.tsv" "$tmp/x.txt"
printf 'old\tnew\nCON-1 CON-2\n' >"$tmp/bad.tsv"
expect "map line that does not parse is BLIND" 3 'map line 2 does not parse' rewrite --map "$tmp/bad.tsv" "$tmp/x.txt"
printf 'CON-1\tCON-2\n' >"$tmp/nohdr.tsv"
expect "map without header is BLIND" 3 'header' rewrite --map "$tmp/nohdr.tsv" "$tmp/x.txt"
expect "usage: no subcommand" 2 ''
expect "usage: unknown option" 2 '' plan --nonsense

# ---- (2) refs ----
rr=$tmp/refrepo; mkdir -p "$rr/docs/qa" "$rr/docs/guides" || exit 2
printf 'captured CON-1 output\n' >"$rr/docs/qa/run.txt"
printf 'the guide names CON-2 and CON-12\n' >"$rr/docs/guides/g.md"
printf 'Foreign ids (other tracker): CON-1\nonly a foreign CON-1 here\n' >"$rr/docs/guides/f.md"
: >"$rr/docs/workable_items.db"; : >"$rr/docs/other.db"
printf 'bin CON-1\0x' >"$rr/blob.bin"
git -C "$rr" -c init.defaultBranch=main init -q && git -C "$rr" add -A || exit 2
expect "refs lists LIVE, EVIDENCE and DATABASE" 0 '^RESULT: REFS live=1 evidence=1 database=1$' refs --map "$tmp/m.tsv" --repo-root "$rr"
grep -q "^LIVE	docs/guides/g.md	CON-2$" "$tmp/out" && grep -q "^EVIDENCE	docs/qa/run.txt	CON-1$" "$tmp/out" && grep -q "^DATABASE	docs/workable_items.db	-$" "$tmp/out" \
  && ! grep -q 'f.md\|other.db\|blob.bin' "$tmp/out" && ok "refs lines (a Foreign-only file, another .db and a binary are not listed)" \
  || bad "refs lines" "$(tr '\n' '|' <"$tmp/out")"
mkdir -p "$tmp/emptyrepo" && git -C "$tmp/emptyrepo" -c init.defaultBranch=main init -q || exit 2
expect "refs on a repository with no tracked file is BLIND" 3 'no tracked file' refs --map "$tmp/m.tsv" --repo-root "$tmp/emptyrepo"

# ---- (3) plan, replay and verify with the real engine ----
repo=$tmp/repo; mkdir -p "$repo/docs/qa" "$repo/scripts" || exit 2
printf 'evidence\n' >"$repo/docs/qa/x.txt" || exit 2
cp "$realdb" "$repo/docs/b.db" || exit 2
n=$(python3 -I -c 'import re,sqlite3,sys;c=sqlite3.connect("file:%s?mode=ro"%sys.argv[1],uri=True);print(max(int(r[0][4:]) for r in c.execute("select atm_id from items") if re.fullmatch(r"CON-\d+",r[0])))' "$repo/docs/b.db") || exit 2
id() { printf 'CON-%03d' "$(( n + $1 ))"; }
W() { (cd "$repo" && "$wi" "$@") >>"$tmp/engine.log" 2>&1 || { echo "setup: engine step failed: $*" >&2; tail -3 "$tmp/engine.log" >&2; exit 2; }; }
cpdb() { cp "$repo/docs/$1.db" "$repo/docs/$2.db" || exit 2; }
D="**What:** remint fixture item for the remint_ids test, never landed in a tracker."
NL=$'\n'
EV=docs/qa/x.txt
# base: eight items; 5 and 6 are closed Obsolete duplicates; 7 names an id the vehicle mints later
for k in 1 3 4 5 6 8; do W add Task Low --db docs/b.db --id "$(id $k)" --title "Remint base item $k" --description "$D Base item $k." --created-by Claude; done
W add Bug Medium --db docs/b.db --id "$(id 2)" --title "Remint base item 2" --description "$D Base item 2." --created-by Claude
W add Task Low --db docs/b.db --id "$(id 7)" --title "Remint base item 7" --description "$D Base item 7 names $(id 11) before it exists." --created-by Claude
W close "$(id 5)" --db docs/b.db --status obsolete --evidence "$EV"
W obsolete-details "$(id 5)" --db docs/b.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 1)" --evidence "$EV"
W close "$(id 6)" --db docs/b.db --status obsolete --evidence "$EV"
W obsolete-details "$(id 6)" --db docs/b.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 2)" --evidence "$EV"
cpdb b v; cpdb b t
# the fixture instrument checks itself: an edit that matches no row, and the real database, are setup errors
( fx_sql "$repo/docs/b.db" "update items set title='x' where atm_id='NO-SUCH-ID'" ) >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "fx_sql refuses an edit that changes no row" || bad "fx_sql refuses an edit that changes no row" "rc=$rc"
# a read-only statement: if the guard were missing, nothing is written and the probe exits 0 (caught)
( fx_sql "$realdb" "select 1 from items limit 1" ) >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "fx_sql refuses the real database" || bad "fx_sql refuses the real database" "rc=$rc"
# vehicle: own items 9..13
W add Task Low --db docs/v.db --id "$(id 9)" --title "Remint fixture alpha item" --description "$D Parent / links: see $(id 11) (remint fixture gamma) and the range $(id 9)..$(id 10)." --created-by Claude --assigned-to Conductor
W add Bug Medium --db docs/v.db --id "$(id 10)" --title "Remint fixture beta item, seen in fix227 $(id 11)" --description "$D Links to $(id 9).${NL}Foreign ids (fix227 tracker): $(id 11)" --created-by Claude \
  --reproduction-state UNREPRODUCED --investigation-state not-started --states-updated-by "remint test" --states-updated-at 2026-11-13T10:00:00Z
W add Task Low --db docs/v.db --id "$(id 11)" --title "Remint fixture gamma item" --description "$D Duplicate of $(id 9)." --created-by Claude
W close "$(id 11)" --db docs/v.db --status obsolete --evidence "$EV"
W obsolete-details "$(id 11)" --db docs/v.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 9)" --evidence "$EV"
W add Task Low --db docs/v.db --id "$(id 12)" --title "Remint fixture delta item" --description "$D Was closed onto $(id 10), then reopened." --created-by Claude
W close "$(id 12)" --db docs/v.db --status obsolete --evidence "$EV"
W obsolete-details "$(id 12)" --db docs/v.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 10)" --evidence "$EV"
W reopen --id "$(id 12)" --db docs/v.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
W add Task Low --db docs/v.db --id "$(id 13)" --title "Remint fixture epsilon item" --description "$D Plain own item, now in progress." --created-by Claude
W update --id "$(id 13)" --db docs/v.db --location Issues --status "In progress"
# vehicle: base item changes (R3-1: every one must land)
W update --id "$(id 1)" --db docs/v.db --location Issues --description "$D Base item one, changed by the vehicle; see $(id 11)."
W update --id "$(id 2)" --db docs/v.db --location Issues --reproduction-state UNREPRODUCED --states-updated-by "remint test" --states-updated-at 2026-11-13T11:00:00Z
W close "$(id 3)" --db docs/v.db --status obsolete --evidence "$EV"
W obsolete-details "$(id 3)" --db docs/v.db --since 2026-11-13 --reason superseded-by-design-change --superseding "$(id 9)" --evidence "$EV"
W obsolete-details "$(id 5)" --db docs/v.db --since 2026-11-12 --reason not-reproducible --superseding none --evidence "$EV"
W obsolete-details "$(id 6)" --db docs/v.db --since 2026-11-12 --reason superseded-by-later-mandate --superseding none --evidence "$EV"
W reopen --id "$(id 6)" --db docs/v.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
# target: two colliding items, a disjoint change and a target-only change
W add Task Low --db docs/t.db --id "$(id 9)" --title "Colliding target item one" --description "$D A target item that holds the same number." --created-by Claude
W add Task Low --db docs/t.db --id "$(id 10)" --title "Colliding target item two" --description "$D A target item that holds the same number." --created-by Claude
W update --id "$(id 4)" --db docs/t.db --location Issues --title "Remint base item 4, renamed by the target"
W update --id "$(id 1)" --db docs/t.db --location Issues --severity Medium
sha3() { sha256sum "$repo/docs/v.db" "$repo/docs/b.db" "$repo/docs/t.db" | cut -d' ' -f1 | tr '\n' ' '; }
before=$(sha3)
PLAN=(--vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t.db)
xp "plan: REPLAY, five own ids from max(target)+1, five base changes, 20 steps" 0 "^RESULT: PLAN mode=REPLAY own=5 base_changes=5 steps=20 conflicts=0 refusals=0 first=$(id 11) last=$(id 15)\$" \
  plan "${PLAN[@]}" --out "$tmp/plan.json" --map-out "$tmp/map.tsv" --repo-root .
grep -q "^MERGE $(id 1): vehicle description, target severity (disjoint columns)\$" "$tmp/out" && ok "plan: disjoint base change merged" || bad "plan: disjoint base change merged" "$(tr '\n' '|' <"$tmp/out")"
for k in 1 2 3 5 6; do grep -q "^BASE-CHANGE $(id $k) " "$tmp/out" || bad "plan: base change $(id $k) listed" "missing"; done
same "plan: the three databases are not written" "$(sha3)" "$before"
same "plan: map file" "$(cat "$tmp/map.tsv")" "$(printf 'old\tnew\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s' "$(id 9)" "$(id 11)" "$(id 10)" "$(id 12)" "$(id 11)" "$(id 13)" "$(id 12)" "$(id 14)" "$(id 13)" "$(id 15)")"
xp "replay dry run" 0 '^RESULT: DRY-RUN steps=20$' replay --plan "$tmp/plan.json"
cp "$tmp/out" "$tmp/steps.txt"
grep -qF "see $(id 13) (remint fixture gamma) and the range $(id 11)..$(id 12)." "$tmp/steps.txt" && ok "dry run: own text rewritten without chaining" || bad "dry run: own text rewritten without chaining" "$(grep -m1 alpha "$tmp/steps.txt" | cut -c1-300)"
grep -qF "\"obsolete-details\", \"$(id 14)\"" "$tmp/steps.txt" && grep -qF "\"obsolete-details\", \"$(id 5)\"" "$tmp/steps.txt" && ok "dry run: obsolete_details replayed on the reopened own item and on the rewritten base row" || bad "dry run: obsolete_details steps" "$(grep obsolete-details "$tmp/steps.txt" | tr '\n' '|' | cut -c1-300)"
cpdb t r
(cd "$repo" && "$wi" validate --db docs/r.db) >"$tmp/val.before" 2>&1
xp "replay --apply through the engine" 0 '^RESULT: APPLIED steps=20 items=5$' replay --plan "$tmp/plan.json" --apply --engine "$wi" --db docs/r.db
xp "verify PASS after the replay" 0 '^RESULT: PASS mode=REPLAY items=10 mismatches=0 known=[0-9]+$' verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/r.db
grep -q "^KNOWN $(id 3) created_at: .*CON-339" "$tmp/out" && ok "verify: the close rewriting created_at is KNOWN (CON-339), never a pass" || bad "verify: CON-339 KNOWN line" "$(tr '\n' '|' <"$tmp/out" | cut -c1-300)"
# the landed values, read directly (a third angle beside the planner and verify)
R=$repo/docs/r.db
same "landed: base description change carried and rewritten; target severity kept" "$(q "$R" 'select description, severity from items where atm_id=?' "$(id 1)")" "$D Base item one, changed by the vehicle; see $(id 13).|Medium"
same "landed: base state block with the vehicle's stamps" "$(q "$R" 'select reproduction_state, reproduction_updated_by, reproduction_updated_at from items where atm_id=?' "$(id 2)")" "UNREPRODUCED|remint test|2026-11-13T11:00:00Z"
same "landed: base close with its obsolete_details row, superseding rewritten" "$(q "$R" 'select i.status, o.reason, o.superseding_item from items i join obsolete_details o using (atm_id) where atm_id=?' "$(id 3)")" "Obsolete (→ Fixed.md)|superseded-by-design-change|$(id 11)"
same "landed: target-only title kept" "$(q "$R" 'select title from items where atm_id=?' "$(id 4)")" "Remint base item 4, renamed by the target"
same "landed: rewritten obsolete_details row of a closed base item" "$(q "$R" 'select since, reason, superseding_item from obsolete_details where atm_id=?' "$(id 5)")" "2026-11-12|not-reproducible|none"
same "landed: base reopen with the obsolete_details row the vehicle rewrote before it" "$(q "$R" 'select i.status, i.current_location, o.reason, o.superseding_item from items i join obsolete_details o using (atm_id) where atm_id=?' "$(id 6)")" "Reopened|Issues|superseded-by-later-mandate|none"
same "landed: own alpha text and assignee" "$(q "$R" 'select description, assigned_to from items where atm_id=?' "$(id 11)")" "$D Parent / links: see $(id 13) (remint fixture gamma) and the range $(id 11)..$(id 12).|Conductor"
same "landed: own beta keeps its fix227 id on every column (R3-2)" "$(q "$R" 'select title, description from items where atm_id=?' "$(id 12)")" "Remint fixture beta item, seen in fix227 $(id 11)|$D Links to $(id 11).${NL}Foreign ids (fix227 tracker): $(id 11)"
same "landed: own beta state stamps" "$(q "$R" 'select reproduction_updated_at, investigation_updated_at, investigation_state from items where atm_id=?' "$(id 12)")" "2026-11-13T10:00:00Z|2026-11-13T10:00:00Z|not-started"
same "landed: own gamma Obsolete onto alpha" "$(q "$R" 'select i.status, o.superseding_item from items i join obsolete_details o using (atm_id) where atm_id=?' "$(id 13)")" "Obsolete (→ Fixed.md)|$(id 11)"
same "landed: own delta Reopened with its obsolete_details row" "$(q "$R" 'select i.status, o.superseding_item from items i join obsolete_details o using (atm_id) where atm_id=?' "$(id 14)")" "Reopened|$(id 12)"
same "landed: own epsilon status" "$(q "$R" 'select status from items where atm_id=?' "$(id 15)")" "In progress"
same "landed: the colliding target items are untouched" "$(q "$R" 'select title from items where atm_id in (?, ?) order by atm_id' "$(id 9)" "$(id 10)")" "$(printf 'Colliding target item one\nColliding target item two')"
(cd "$repo" && "$wi" validate --db docs/r.db) >"$tmp/val.after" 2>&1
grep '^  - ' "$tmp/val.before" | sort >"$tmp/val.b"; grep '^  - ' "$tmp/val.after" | sort >"$tmp/val.a"
newf=$(comm -13 "$tmp/val.b" "$tmp/val.a")
{ cat "$tmp/val.a"; echo "  - $(id 11) [needle]: x"; } | sort >"$tmp/val.n"
needle=$(comm -13 "$tmp/val.b" "$tmp/val.n")
if [ -s "$tmp/val.after" ] && [ -n "$needle" ] && [ -z "$newf" ]; then ok "validate reports no new finding on the landed copy (control needle seen)"
else bad "validate reports no new finding on the landed copy" "$(printf '%s' "$newf" | head -3 | tr '\n' '|' | cut -c1-400)"; fi
cpdb r r_after
xp "a second replay is refused before any write" 1 're-plan against this target' replay --plan "$tmp/plan.json" --apply --engine "$wi" --db docs/r.db
cmp -s "$repo/docs/r.db" "$repo/docs/r_after.db" && ok "the refused second replay wrote nothing" || bad "the refused second replay wrote nothing" "changed"

# ---- (4) verify FAIL needles on copies of the landed database ----
vn() { # vn <name> <pattern> <db>: verify must FAIL with the pattern
  xp "verify FAIL: $1" 1 "$2" verify --plan "$tmp/plan.json" "${PLAN[@]}" --db "docs/$3.db"
}
cpdb r_after n1; W update --id "$(id 11)" --db docs/n1.db --location Issues --description "$D A description changed after the replay."
vn "a changed own description" "^MISMATCH $(id 11) description: text differs outside the ids" n1
cpdb r_after n2; W update --id "$(id 12)" --db docs/n2.db --location Issues --title "Remint fixture beta item, seen in fix227 $(id 13)"
vn "a foreign id re-pointed to the map (R3-2)" "^MISMATCH $(id 12) title: id $(id 11) landed as $(id 13), expected $(id 11)" n2
cpdb r_after n3; W update --id "$(id 15)" --db docs/n3.db --location Issues --status Queued
vn "an own status" "^MISMATCH $(id 15) status: landed 'Queued', expected 'In progress'" n3
cpdb r_after n4; W update --id "$(id 4)" --db docs/n4.db --location Issues --severity High
vn "an untouched target item" "^MISMATCH $(id 4): an item the landing must not touch differs from the target" n4
cpdb r_after n5; W update --id "$(id 1)" --db docs/n5.db --location Issues --description "$D Base item 1."
vn "a lost base-item change (R3-1)" "^MISMATCH $(id 1) description: " n5
cpdb r_after n6; W obsolete-details "$(id 13)" --db docs/n6.db --since 2026-11-01 --reason duplicate-of --superseding "$(id 11)" --evidence "$EV"
vn "an obsolete_details field" "^MISMATCH $(id 13) obsolete_details.since: landed '2026-11-01', vehicle '2026-11-13'" n6
cpdb r_after n7; W obsolete-details "$(id 13)" --db docs/n7.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 9)" --evidence "$EV"
vn "an obsolete_details superseding id" "^MISMATCH $(id 13) obsolete_details.superseding_item: id $(id 9) landed as $(id 9), expected $(id 11)" n7
cpdb r_after n8; fx_sql "$repo/docs/n8.db" "delete from item_history where atm_id=? and event_type='Opened'" "$(id 15)"
vn "a missing Opened history row" "^MISMATCH $(id 15): no Opened history row" n8
cpdb r_after n9; fx_sql "$repo/docs/n9.db" "update item_history set evidence_path='docs/qa/other.txt' where atm_id=? and event_type='Obsolete'" "$(id 13)"
vn "a closure row citing other evidence" "^MISMATCH $(id 13): landed closure row cites 'docs/qa/other.txt'" n9
cpdb r_after n10; fx_sql "$repo/docs/n10.db" "update item_history set reason='other-reason' where atm_id=? and event_type='Reopened'" "$(id 14)"
vn "a changed Reopened row" "^MISMATCH $(id 14): the last Reopened row does not match the vehicle's" n10
cpdb r_after n11; fx_sql "$repo/docs/n11.db" "update item_history set reason='changed' where id=(select min(id) from item_history)"
vn "a target history row" "^MISMATCH item_history row [0-9]+ of the target changed or vanished" n11
cpdb r_after n12; W diary add --id "$(id 9)" --db docs/n12.db --tested-by AI-agent --result SKIP --detail needle --observations needle
vn "another table" "^MISMATCH table test_diary differs from the target" n12
vn "missing landed items" "^MISMATCH landed ids: missing" t
cpdb r_after n15; fx_sql "$repo/docs/n15.db" "update items set reproduction_updated_at='2026-11-14T00:00:00Z' where atm_id=?" "$(id 2)"
vn "a base-change state stamp" "^MISMATCH $(id 2) reproduction_updated_at: landed '2026-11-14T00:00:00Z', vehicle '2026-11-13T11:00:00Z'" n15
cpdb r_after n13; W add Task Low --db docs/n13.db --id "$(id 30)" --title "An extra item" --description "$D An item no plan lands." --created-by Claude
vn "an extra landed item" "^MISMATCH landed ids: .*extra \['$(id 30)'\]" n13
xp "verify --require-segments PASS (the engine's add writes the item segment)" 0 '^RESULT: PASS mode=REPLAY items=10 mismatches=0' verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/r_after.db --require-segments
cpdb r_after n14; fx_sql "$repo/docs/n14.db" "delete from doc_segments where atm_id=?" "$(id 11)"
xp "verify --require-segments FAILs on an item with no segment" 1 "^MISMATCH $(id 11): not in doc_segments" verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/n14.db --require-segments
python3 -I - "$tmp/plan.json" "$tmp/plan_short.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p["map"] = p["map"][:-1]
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"))
PY
xp "verify FAIL: a plan map that is not the own set" 1 "^MISMATCH the plan's map keys are not the own set" verify --plan "$tmp/plan_short.json" "${PLAN[@]}" --db docs/r_after.db
python3 -I - "$tmp/plan.json" "$tmp/plan_pfx.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p["prefix"] = "ZZ"
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"))
PY
xp "verify: a plan whose map prefix is not its prefix is BLIND" 3 'plan map prefix CON is not the plan prefix ZZ' verify --plan "$tmp/plan_pfx.json" "${PLAN[@]}" --db docs/r_after.db
xp "verify refuses databases the plan was not made from" 1 'the vehicle database is not the one the plan was made from' verify --plan "$tmp/plan.json" --vehicle-db docs/b.db --base-db docs/b.db --target-db docs/t.db --db docs/r_after.db

# ---- (5) FAST-FORWARD and --no-fast-forward ----
cpdb b tff
xp "plan: FAST-FORWARD when the target is the base" 0 "^RESULT: PLAN mode=FAST-FORWARD own=5 base_changes=5 steps=0 conflicts=0 refusals=0 first=$(id 9) last=$(id 13)\$" \
  plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/tff.db --out "$tmp/ff.json"
xp "replay refuses a FAST-FORWARD plan" 1 'the plan is FAST-FORWARD: copy the vehicle database' replay --plan "$tmp/ff.json" --apply --engine "$wi" --db docs/tff.db
xp "verify FAST-FORWARD PASS on the vehicle database" 0 '^RESULT: PASS mode=FAST-FORWARD items=[0-9]+ mismatches=0' verify --plan "$tmp/ff.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/tff.db --db docs/v.db
cpdb v vff; W update --id "$(id 9)" --db docs/vff.db --location Issues --severity High
xp "verify FAST-FORWARD FAILs on a changed copy" 1 "^MISMATCH FAST-FORWARD: $(id 9) differs from the vehicle" verify --plan "$tmp/ff.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/tff.db --db docs/vff.db
xp "plan --no-fast-forward replays with the own ids kept" 0 "^RESULT: PLAN mode=REPLAY own=5 base_changes=5 steps=20 conflicts=0 refusals=0 first=$(id 9) last=$(id 13)\$" \
  plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/tff.db --out "$tmp/nff.json" --no-fast-forward
cpdb tff rnff
xp "replay of the --no-fast-forward plan" 0 '^RESULT: APPLIED steps=20 items=5$' replay --plan "$tmp/nff.json" --apply --engine "$wi" --db docs/rnff.db
xp "verify PASS of the --no-fast-forward landing" 0 '^RESULT: PASS mode=REPLAY items=10 mismatches=0' verify --plan "$tmp/nff.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/tff.db --db docs/rnff.db

# ---- (6) conflicts and --resolve ----
cpdb t t2; W update --id "$(id 1)" --db docs/t2.db --location Issues --description "$D Base item one, changed by the target."
xp "conflict: both sides changed one column" 1 "^CONFLICT $(id 1): both changed description .*--resolve $(id 1)=target or =vehicle decides" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --out "$tmp/c.json"
grep -q '^RESULT: NOT-LANDABLE mode=REPLAY .* conflicts=1 refusals=0' "$tmp/out" && ok "conflict: the plan is NOT-LANDABLE" || bad "conflict: the plan is NOT-LANDABLE" "$(tail -1 "$tmp/out")"
xp "replay refuses a plan with a conflict" 1 'cannot be replayed' replay --plan "$tmp/c.json"
xp "--resolve vehicle" 0 '^RESULT: PLAN mode=REPLAY' plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --out "$tmp/cv.json" --resolve "$(id 1)=vehicle"
cpdb t2 rcv
xp "replay of --resolve vehicle" 0 '^RESULT: APPLIED' replay --plan "$tmp/cv.json" --apply --engine "$wi" --db docs/rcv.db
xp "verify of --resolve vehicle" 0 '^RESULT: PASS' verify --plan "$tmp/cv.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --db docs/rcv.db
same "--resolve vehicle lands the vehicle's description" "$(q "$repo/docs/rcv.db" 'select description from items where atm_id=?' "$(id 1)")" "$D Base item one, changed by the vehicle; see $(id 13)."
xp "--resolve target" 0 '^RESULT: PLAN mode=REPLAY' plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --out "$tmp/ct.json" --resolve "$(id 1)=target"
cpdb t2 rct
xp "replay of --resolve target" 0 '^RESULT: APPLIED' replay --plan "$tmp/ct.json" --apply --engine "$wi" --db docs/rct.db
xp "verify of --resolve target" 0 '^RESULT: PASS' verify --plan "$tmp/ct.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --db docs/rct.db
same "--resolve target keeps the target's description" "$(q "$repo/docs/rct.db" 'select description from items where atm_id=?' "$(id 1)")" "$D Base item one, changed by the target."
xp "--resolve that does not parse is BLIND" 3 'want ID=target or ID=vehicle' plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --out "$tmp/cx.json" --resolve "$(id 1)=both"
cpdb t t3; W close "$(id 1)" --db docs/t3.db --status obsolete --evidence "$EV"
xp "conflict: a lifecycle change on one side and a change on the other" 1 "^CONFLICT $(id 1): a lifecycle change on one side and a change on the other" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t3.db --out "$tmp/c3.json"
cpdb t t4; fx_sql "$repo/docs/t4.db" "delete from items where atm_id=?" "$(id 2)"
xp "conflict: the target deleted an item the vehicle changed" 1 "^CONFLICT $(id 2): the target deleted the item; the vehicle changed reproduction_state" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t4.db --out "$tmp/c4.json"

# ---- (7) plan refusals (each on a copy of the vehicle with one more change) ----
pr() { # pr <name> <pattern> <vehicle copy>
  xp "plan refusal: $1" 1 "$2" plan --vehicle-db "docs/$3.db" --base-db docs/b.db --target-db docs/t.db --out "$tmp/$3.json" --repo-root .
}
cpdb v x1; fx_sql "$repo/docs/x1.db" "delete from items where atm_id=?" "$(id 8)"
pr "the vehicle deleted a base item" "^REFUSED $(id 8): the vehicle deleted a base item" x1
cpdb v x2; W add Task Low --db docs/x2.db --id AA-001 --title "Foreign prefix item" --description "$D An item outside the prefix." --created-by Claude
pr "a new id outside the prefix" '^REFUSED AA-001: a new vehicle id outside the CON prefix' x2
cpdb v x3; fx_sql "$repo/docs/x3.db" "update items set reproduction_updated_at='2026-11-13T12:00:00Z', reproduction_updated_by='x' where atm_id=?" "$(id 8)"
pr "only a state stamp changed" "^REFUSED $(id 8): only the reproduction stamp changed" x3
cpdb v x4; fx_sql "$repo/docs/x4.db" "update items set body_md = body_md || ' x' where atm_id=?" "$(id 8)"
pr "body_md changed with no column change" "^REFUSED $(id 8): body_md changed with no column change" x4
cpdb v x5; fx_sql "$repo/docs/x5.db" "update items set logic_group='needle' where atm_id=?" "$(id 8)"
pr "a column with no replay rule" "^REFUSED $(id 8): the vehicle changed logic_group, which has no replay rule" x5
cpdb v x6; W block --id "$(id 8)" --db docs/x6.db --details "wait for the needle" --why w --unblock u --who operator
pr "another table changed" '^REFUSED table operator_block_details: the vehicle changed it' x6
cpdb v x7; fx_sql "$repo/docs/x7.db" "update item_history set reason='rewritten' where atm_id=? and event_type='Opened'" "$(id 8)"
pr "a base history row rewritten" "^REFUSED item_history row [0-9]+ \($(id 8)\): the vehicle rewrote or deleted a base history row" x7
cpdb v x8; fx_sql "$repo/docs/x8.db" "insert into doc_segments (document, seq, kind, atm_id, raw) values ('Issues', 99999, 'raw', null, 'needle')"
pr "a non-item doc segment" '^REFUSED doc_segments: the vehicle changed a segment that is not an item segment' x8
cpdb v x9; fx_sql "$repo/docs/x9.db" "update items set logic_group='needle' where atm_id=?" "$(id 13)"
pr "an own item with a column add cannot carry" "^REFUSED $(id 13): logic_group is set \('needle'\), which add cannot carry" x9
cpdb v x10; fx_sql "$repo/docs/x10.db" "update items set representation='table' where atm_id=?" "$(id 13)"
pr "an own item with another representation" "^REFUSED $(id 13): representation 'table' cannot be replayed" x10
cpdb v x11; W update --id "$(id 7)" --db docs/x11.db --location Issues --title "Remint base item 7, renamed by the vehicle"
pr "a base text that already names an id the vehicle minted later" "^REFUSED $(id 7): the base text of description already names $(id 11), an id the vehicle minted later \(ambiguous\)" x11
cpdb v x12; W close "$(id 8)" --db docs/x12.db --status obsolete --evidence "$EV"
W obsolete-details "$(id 8)" --db docs/x12.db --since 2026-11-13 --reason duplicate-of --superseding "$(id 1)" --evidence "$EV"
W reopen --id "$(id 8)" --db docs/x12.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
W update --id "$(id 8)" --db docs/x12.db --location Issues --status "In progress"
pr "an obsolete_details row on an item left open" "^REFUSED base $(id 8): the vehicle's obsolete_details row cannot be replayed on a 'In progress' item" x12
cpdb v x13; W update --id "$(id 10)" --db docs/x13.db --location Issues --reproduction-state UNREPRODUCED --reproduction-red-cmd "bash scripts/remint_probe.sh" --states-updated-by "remint test" --states-updated-at 2026-11-13T10:00:00Z
printf '#!/bin/sh\n# probes %s\n' "$(id 9)" >"$repo/scripts/remint_probe.sh"
pr "a red command whose script names a moved id" "^REFUSED $(id 10) reproduction_red_cmd runs scripts/remint_probe.sh names $(id 9)" x13
printf '#!/bin/sh\n# probes %s\n' "$(id 13)" >"$repo/scripts/remint_probe.sh"
pr "a red command whose script names another moved id" "^REFUSED $(id 10) reproduction_red_cmd runs scripts/remint_probe.sh names $(id 13)" x13
xp "plan: --foreign covers the script scan too" 0 '^RESULT: PLAN mode=REPLAY' plan --vehicle-db docs/x13.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x13a.json" --repo-root . --foreign "$(id 13)"
printf '#!/bin/sh\n# Foreign ids (fix227): %s\n# probes %s\n' "$(id 9)" "$(id 9)" >"$repo/scripts/remint_probe.sh"
xp "plan: a script that declares its id foreign in a comment is not refused" 0 '^RESULT: PLAN mode=REPLAY' plan --vehicle-db docs/x13.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x13b.json" --repo-root .
printf '#!/bin/sh\n# probes %s\n' "$(id 11)" >"$repo/scripts/remint_probe.sh"
xp "plan: a script naming an id the item itself declares foreign is not refused" 0 '^RESULT: PLAN mode=REPLAY' plan --vehicle-db docs/x13.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x13c.json" --repo-root .
printf '#!/bin/sh\necho "Foreign ids (fix227): %s"\n# probes %s\n' "$(id 9)" "$(id 9)" >"$repo/scripts/remint_probe.sh"
pr "a Foreign text that is not a comment line declares nothing" "^REFUSED $(id 10) reproduction_red_cmd runs scripts/remint_probe.sh names $(id 9)" x13

# ---- (8) BLIND and usage exits ----
xp "plan: a missing database is BLIND" 3 'database not found' plan --vehicle-db docs/none.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/b1.json"
cpdb v y1; fx_sql "$repo/docs/y1.db" "create table extra_needle (x text)"
xp "plan: an unknown table is BLIND" 3 "tables differ from the known set .*extra \['extra_needle'\]" plan --vehicle-db docs/y1.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/b2.json"
cpdb v y2; fx_sql "$repo/docs/y2.db" "alter table items add column needle text"
xp "plan: an unknown items column is BLIND" 3 "items columns differ from the known set: \['needle'\]" plan --vehicle-db docs/y2.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/b3.json"
cpdb t y3; fx_sql "$repo/docs/y3.db" "update meta set value='0' where key='schema_version'"
xp "plan: a schema_version that differs is BLIND" 3 'schema_version differs or is missing' plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/y3.db --out "$tmp/b4.json"
cpdb v y4; W add Task Low --db docs/y4.db --id ZZ-001 --title "Other prefix item" --description "$D An item of another prefix." --created-by Claude
xp "plan: a target without an id of the prefix is BLIND" 3 'the target holds no ZZ id' plan --vehicle-db docs/y4.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/b5.json" --prefix ZZ
printf '{"schema": "other"}\n' >"$tmp/badplan.json"
xp "replay: a plan of another schema is BLIND" 3 'plan has no remint_ids.plan/4 schema' replay --plan "$tmp/badplan.json"
printf 'not json\n' >"$tmp/notjson.json"
xp "replay: an unreadable plan is BLIND" 3 'plan unreadable' replay --plan "$tmp/notjson.json"
python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));del p["steps"];json.dump(p,open(sys.argv[2],"w"))' "$tmp/plan.json" "$tmp/nosteps.json" || exit 2
xp "replay: a plan without steps is BLIND" 3 "plan lacks 'steps'" replay --plan "$tmp/nosteps.json"
xp "replay --apply without --engine is a usage error" 2 'needs --engine and --db' replay --plan "$tmp/plan.json" --apply
xp "replay: a missing target copy is BLIND" 3 'target copy not found' replay --plan "$tmp/plan.json" --apply --engine "$wi" --db docs/none.db
cpdb t w1; printf 'not empty' >"$repo/docs/w1.db-wal"
xp "replay refuses a target copy with a non-empty -wal sidecar" 1 'non-empty -wal sidecar' replay --plan "$tmp/plan.json" --apply --engine "$wi" --db docs/w1.db
cpdb b w2
xp "replay refuses a target copy whose sha256 is not the plan's" 1 're-plan against this target' replay --plan "$tmp/plan.json" --apply --engine "$wi" --db docs/w2.db
cmp -s "$repo/docs/w2.db" "$repo/docs/b.db" && ok "the refused replay wrote nothing" || bad "the refused replay wrote nothing" "changed"

same "the real database is untouched" "$(sha256sum "$realdb" | cut -d' ' -f1)" "$real_sha"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
