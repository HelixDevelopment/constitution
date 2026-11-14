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
# round 5 (R4-4, R4-5, RV3): a range is a range whatever its connector; non-ASCII digits are refused
rwcase() { # rwcase <name> <want-rc> <pattern> <text>: a dry run on one file holding <text>
  printf '%s\n' "$4" >"$tmp/w5.txt"
  expect "$1" "$2" "$3" rewrite --map "$tmp/m.tsv" "$tmp/w5.txt"
}
rwgot() { # rwgot <name> <text> <want-text>: --write, then exit status and file text
  printf '%s\n' "$2" >"$tmp/w5.txt"
  python3 -I "$tool" rewrite --map "$tmp/m.tsv" --write --target-db "$tmp/tg.db" --own CON-1 "$tmp/w5.txt" >"$tmp/out" 2>&1; rc=$?
  same "$1" "$rc|$(cat "$tmp/w5.txt")" "0|$3"
}
rwcase "R4-4: a spaced en dash partly-moved range is refused" 1 'range CON-4 – CON-6 is partly moved \(2 of 3 ids\)' 'span CON-4 – CON-6 here'
rwcase "R4-4: a worded 'to' partly-moved range is refused" 1 'range CON-4 to CON-6 is partly moved' 'span CON-4 to CON-6'
rwcase "R4-4: a worded 'through' partly-moved range is refused" 1 'range CON-4 through CON-6 is partly moved' 'span CON-4 through CON-6'
rwcase "R4-4: a tight three-dot partly-moved range is refused" 1 'range CON-4\.\.\.CON-6 is partly moved' 'span CON-4...CON-6'
rwcase "R4-4: a spaced three-dot partly-moved range is refused" 1 'is partly moved' 'span CON-4 ... CON-6'
rwcase "R4-4: an ellipsis partly-moved range is refused" 1 'is partly moved' 'span CON-4…CON-6'
rwcase "R4-4: a spaced hyphen partly-moved range is refused" 1 'is partly moved' 'span CON-4 - CON-6'
rwcase "R4-4: a spaced em dash partly-moved range is refused" 1 'is partly moved' 'span CON-4 — CON-6'
rwcase "R4-4: a tight em dash partly-moved range is refused" 1 'is partly moved' 'span CON-4—CON-6'
rwcase "R4-4: a 'between ... and' partly-moved range is refused" 1 'range between CON-4 and CON-6 is partly moved' 'see between CON-4 and CON-6'
rwcase "R4-4: ids joined by a tight hyphen are refused (the tokens are never rewritten)" 1 'range CON-5-CON-6 joins its ids with a hyphen' 'see CON-5-CON-6'
rwcase "R4-4: a chained range is checked link by link" 1 'range CON-2 to CON-6 is partly moved' 'see CON-1 to CON-2 to CON-6'
rwgot "R4-4: a list joined with 'and' is not a range" 'see CON-4 and CON-6' 'see CON-4 and CON-21'
rwcase "RV3: a tight en dash partly-moved range is refused" 1 'range CON-4–CON-6 is partly moved' 'span CON-4–CON-6'
rwgot "RV3: a tight en dash range of moved ids is rewritten" 'span CON-5–CON-7' 'span CON-20–CON-22'
rwgot "R4-4: a spaced en dash range of moved ids is rewritten" 'span CON-5 – CON-7' 'span CON-20 – CON-22'
rwgot "R4-4: a worded range of moved contiguous ids is rewritten id by id" 'moved CON-1 to CON-2' 'moved CON-2 to CON-3'
rwgot "R4-4: a worded range with no moved id is left alone" 'see CON-40 to CON-50' 'see CON-40 to CON-50'
rwcase "R4-4: a worded range mixing foreign and moved ids is refused" 1 'range CON-5 to CON-7 mixes foreign and moved ids' "$(printf 'Foreign ids (other): CON-6\nrange CON-5 to CON-7')"
rwcase "R4-4: a worded reverse range is refused" 1 'reverse range CON-7 to CON-5' 'back CON-7 to CON-5'
rwcase "R4-4: a worded range mapped to non-contiguous ids is refused" 1 'range CON-7 to CON-8 maps to ids that are not contiguous' 'gap CON-7 to CON-8'
rwcase "R4-4: a worded short-form range is refused" 1 'short-form range CON-5 to 7' 'short CON-5 to 7'
rwcase "R4-5: fullwidth digits of a moved id are refused" 1 'CON-５ writes moved CON-5 with non-ASCII digits' 'see CON-５'
rwcase "R4-5: Arabic-Indic digits of a moved id are refused" 1 'CON-٥ writes moved CON-5 with non-ASCII digits' 'see CON-٥'
rwgot "R4-5: non-ASCII digits of an id the map does not move are left alone" 'see CON-４４' 'see CON-４４'
# round 5, branch sweep (R4-2): cases for the Rewriter branches the sweep found untested
rwgot "sweep: a tight range of foreign-declared ids is left as written" "$(printf 'Foreign ids (other): CON-5..CON-7\nsee CON-5..CON-7')" "$(printf 'Foreign ids (other): CON-5..CON-7\nsee CON-5..CON-7')"
rwgot "sweep: ids joined by a tight hyphen that hold no moved id are left as written" 'see CON-40-CON-50' 'see CON-40-CON-50'
rwgot "sweep: a tight range of ids that do not move is left as written" 'see CON-40..CON-50' 'see CON-40..CON-50'
printf 'see CON-1..CON-2\n' >"$tmp/w5.txt"
expect "sweep: a range holding a moved id the target also holds is refused" 1 'CON-1 in range CON-1\.\.CON-2 is also a target id; declare it' rewrite --map "$tmp/m.tsv" --target-db "$tmp/tg.db" "$tmp/w5.txt"
rwcase "sweep: a range whose first id is written with another zero padding is refused" 1 'range CON-001\.\.CON-002 is written with a different zero padding' 'see CON-001..CON-002'
rwcase "sweep: a range whose second id is written with another zero padding is refused" 1 'range CON-1\.\.CON-002 is written with a different zero padding' 'see CON-1..CON-002'
rwgot "sweep: a line that starts with a moved id and ends with a slash is rewritten" 'CON-1 see docs/' 'CON-2 see docs/'
rwcase "sweep: a moved id after a slash is refused as part of a path" 1 'moved id CON-1 is part of a path' 'see dir/CON-1 here'
rwcase "sweep: a moved tight range after a slash is refused as part of a path" 1 'moved range CON-5\.\.CON-7 is part of a path' 'see docs/qa/CON-5..CON-7/x.txt'
rwcase "sweep: a moved en dash range with an extension is refused as part of a path" 1 'moved range CON-5–CON-7 is part of a path' 'see CON-5–CON-7.md'
rwgot "sweep: a range of ids that do not move inside a path is left as written" 'see docs/qa/CON-40..CON-50.txt' 'see docs/qa/CON-40..CON-50.txt'
# round 5, branch sweep: a chain of tight ranges is checked pair by pair with overlap (the sweep found the
# skip of tight pairs in Rewriter._checks; rng.finditer never sees the second pair of a chain)
rwcase "sweep: a tight chain whose second pair is partly moved is refused" 1 'range CON-2\.\.CON-3 is partly moved \(1 of 2 ids\)' 'see CON-1..CON-2..CON-3'
rwcase "sweep: an en dash chain whose second pair is partly moved is refused" 1 'range CON-2–CON-3 is partly moved \(1 of 2 ids\)' 'see CON-1–CON-2–CON-3'
rwgot "sweep: a tight chain of moved ids is rewritten" 'see CON-5..CON-6..CON-7' 'see CON-20..CON-21..CON-22'
rwcase "sweep: a line with a bad tight range and a bad worded range is refused for the first one" 1 'range CON-001\.\.CON-002 is written with a different zero padding' 'see CON-001..CON-002 and CON-5 to 7'

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
grep -qE "^NOTE ($(id 4)|$(id 7)|$(id 8)):" "$tmp/out" && bad "plan: no note for an item the vehicle left unchanged" "$(grep '^NOTE ' "$tmp/out" | tr '\n' '|' | cut -c1-300)" || ok "plan: no note for an item the vehicle left unchanged"
same "plan: a merge line only for the item both sides changed" "$(grep -c '^MERGE ' "$tmp/out")" "1"
same "plan: a created_at note only for the item the vehicle's close rewrote (CON-339)" "$(grep -o '^NOTE [^:]*: created_at changed in the vehicle' "$tmp/out" | tr '\n' '|')" "NOTE $(id 3): created_at changed in the vehicle|"
same "plan: the three databases are not written" "$(sha3)" "$before"
same "plan: an update step passes --description once" "$(python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));print(sum(a.startswith("--description=") for s in p["steps"] if s["item"]==sys.argv[2] and s["kind"]=="update" for a in s["argv"]))' "$tmp/plan.json" "$(id 1)")" "1"
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
vn "a changed own description" "^MISMATCH $(id 11) description: text differs outside the ids near '" n1
cpdb r_after n1b; W update --id "$(id 11)" --db docs/n1b.db --location Issues --description "$D Parent / links: see $(id 13) (remint fixture gamma) and the range $(id 11)..$(id 12). Extra."
vn "a description changed after its last id names the piece that differs" "^MISMATCH $(id 11) description: text differs outside the ids near '\.'\$" n1b
cpdb r_after n1c; W update --id "$(id 11)" --db docs/n1c.db --location Issues --description "$D Parent / links: see $(id 13) (remint fixture gamma) and the range $(id 11)..$(id 12).$(id 1)"
vn "a description with an id appended gives the piece count" "^MISMATCH $(id 11) description: text differs outside the ids \(piece count 3 vs 4\)" n1c
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
xp "verify without --require-segments leaves doc_segments unchecked" 0 '^RESULT: PASS mode=REPLAY items=10 mismatches=0' verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/n14.db
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
# A FAST-FORWARD landing must hold the vehicle's ids, no more and no fewer (an extra item made by the engine;
# a vehicle item missing, a state no engine command produces), and every other table equal to the vehicle's.
FFV=(verify --plan "$tmp/ff.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/tff.db)
cpdb v vffx; W add Task Low --db docs/vffx.db --id "$(id 40)" --title "Remint fast-forward extra item" --description "$D An item the vehicle does not hold." --created-by Claude
xp "verify FAST-FORWARD FAILs on a copy with an item the vehicle does not hold" 1 '^MISMATCH FAST-FORWARD: the landed ids are not the vehicle ids$' "${FFV[@]}" --db docs/vffx.db
cpdb v vffm; fx_sql "$repo/docs/vffm.db" "delete from items where atm_id=?" "$(id 9)"
xp "verify FAST-FORWARD FAILs on a copy missing a vehicle item" 1 '^MISMATCH FAST-FORWARD: the landed ids are not the vehicle ids$' "${FFV[@]}" --db docs/vffm.db
# one table at a time, items untouched: the table's line and nothing else (mismatches=1)
fft_sql() { # fft_sql <table>: one changed or added row, a state no engine command produces
  case $1 in
    item_history) echo "update item_history set reason='changed in the copy' where id=(select min(id) from item_history)" ;;
    obsolete_details) echo "insert into obsolete_details (atm_id, since, reason, superseding_item, triple_check_evidence) values ('$(id 9)', '2026-01-01', 'feature-removed', 'none', 'e')" ;;
    operator_block_details) echo "insert into operator_block_details (atm_id, what, why_exhausted_alternatives, unblock_condition) values ('$(id 9)', 'w', 'x', 'y')" ;;
    firebase_metadata) echo "insert into firebase_metadata (atm_id, kpi) values ('$(id 9)', 'k')" ;;
    logic_groups) echo "insert into logic_groups (group_id, title, destination, priority) values ('remint-ff-case', 'a group for the fast forward case', 'main', 'P2')" ;;
    test_diary) echo "insert into test_diary (atm_id, date_time, tested_by, result, observations, action_taken) values ('$(id 9)', '2026-01-01T00:00:00Z', 'AI-agent', 'SKIP', 'o', 'a')" ;;
    repro_gate_exemptions) echo "insert into repro_gate_exemptions (atm_id, status, frozen_at) values ('$(id 9)', 's', '2026-01-01')" ;;
    *) echo "setup: no fixture for table $1" >&2; exit 2 ;;
  esac
}
for t in item_history obsolete_details operator_block_details firebase_metadata logic_groups test_diary repro_gate_exemptions; do
  cpdb v "fft_$t"; fx_sql "$repo/docs/fft_$t.db" "$(fft_sql "$t")"
  xp "verify FAST-FORWARD FAILs on a copy whose $t differs" 1 "^MISMATCH FAST-FORWARD: table $t differs from the vehicle\$" "${FFV[@]}" --db "docs/fft_$t.db"
  if grep -Eq '^RESULT: FAIL mode=FAST-FORWARD items=[0-9]+ mismatches=1 known=0$' "$tmp/out"; then ok "verify FAST-FORWARD: the $t copy gives that one mismatch"
  else bad "verify FAST-FORWARD: the $t copy gives that one mismatch" "$(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; fi
done
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
grep -q '^RESULT: NOT-LANDABLE mode=REPLAY own=5 ' "$tmp/out" && ok "a new id outside the prefix is not an own id" || bad "a new id outside the prefix is not an own id" "$(grep '^RESULT' "$tmp/out")"
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
xp "replay: a plan of another schema is BLIND" 3 'plan has no remint_ids.plan/5 schema' replay --plan "$tmp/badplan.json"
python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));p["schema"]="remint_ids.plan/4";json.dump(p,open(sys.argv[2],"w"))' "$tmp/plan.json" "$tmp/plan4.json" || exit 2
xp "replay: a round-4 plan (re-pointed target text, R4-1) is refused as another schema" 3 'plan has no remint_ids.plan/5 schema' replay --plan "$tmp/plan4.json"
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

# ---- (9) round 5: per-unit three-way merge (R4-1), the reviewer's survivors (R4-2), sidecars and URIs (R4-9) ----
# R4-1a: a MERGE never runs target text through the vehicle map, and passes a column only when the vehicle changed it
cpdb v v5; W update --id "$(id 8)" --db docs/v5.db --location Issues --severity High --title "Remint base item 8, see $(id 13)"
cpdb t t5; W update --id "$(id 8)" --db docs/t5.db --location Issues --description "$D Base item 8; see $(id 9) for the related target item."
P5=(--vehicle-db docs/v5.db --base-db docs/b.db --target-db docs/t5.db)
xp "R4-1a: plan of a disjoint merge whose target text names a target id the map moves" 0 '^RESULT: PLAN mode=REPLAY own=5 base_changes=6 ' plan "${P5[@]}" --out "$tmp/p5.json"
grep -q "^MERGE $(id 8): vehicle severity,title, target description (disjoint columns)\$" "$tmp/out" && ok "R4-1a: the merge line" || bad "R4-1a: the merge line" "$(grep MERGE "$tmp/out" | tr '\n' '|')"
xp "R4-1a: dry run" 0 '^RESULT: DRY-RUN ' replay --plan "$tmp/p5.json"
grep -F "\"--id=$(id 8)\"" "$tmp/out" >"$tmp/p5step.txt"
grep -qF "\"--description=$D Base item 8; see $(id 9) for the related target item.\"" "$tmp/p5step.txt" && ok "R4-1a: the target's description is passed verbatim" || bad "R4-1a: the target's description is passed verbatim" "$(cut -c1-400 "$tmp/p5step.txt")"
grep -qF "\"--title=Remint base item 8, see $(id 15)\"" "$tmp/p5step.txt" && grep -qF '"--severity=High"' "$tmp/p5step.txt" && ok "R4-1a: the vehicle's title (rewritten) and severity are passed" || bad "R4-1a: the vehicle's columns" "$(cut -c1-400 "$tmp/p5step.txt")"
cpdb t5 r5
xp "R4-1a: replay" 0 '^RESULT: APPLIED ' replay --plan "$tmp/p5.json" --apply --engine "$wi" --db docs/r5.db
xp "R4-1a: verify PASS" 0 '^RESULT: PASS mode=REPLAY' verify --plan "$tmp/p5.json" "${P5[@]}" --db docs/r5.db
same "R4-1a: landed values" "$(q "$repo/docs/r5.db" 'select severity, title, description from items where atm_id=?' "$(id 8)")" "High|Remint base item 8, see $(id 15)|$D Base item 8; see $(id 9) for the related target item."
cpdb r5 n19; W update --id "$(id 8)" --db docs/n19.db --location Issues --description "$D Base item 8; see $(id 11) for the related target item."
xp "R4-1a: verify FAIL when the target's text is re-pointed through the map" 1 "^MISMATCH $(id 8) description: landed .*target .*\(a column the vehicle did not change\)" verify --plan "$tmp/p5.json" "${P5[@]}" --db docs/n19.db
# R4-1b: one state block changed on both sides is a CONFLICT unless both made the same change
cpdb b b7; W update --id "$(id 8)" --db docs/b7.db --location Issues --reproduction-state UNREPRODUCED --reproduction-env "env one" --reproduction-signature "sig one" --states-updated-by "remint test" --states-updated-at 2026-11-13T09:00:00Z
cpdb b7 v7; W update --id "$(id 8)" --db docs/v7.db --location Issues --reproduction-env "env two" --states-updated-by "remint test" --states-updated-at 2026-11-13T12:00:00Z
cpdb b7 t7; W update --id "$(id 8)" --db docs/t7.db --location Issues --reproduction-signature "sig two" --states-updated-by "target" --states-updated-at 2026-11-13T12:30:00Z
P7=(--vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t7.db)
xp "R4-1b: both sides changed one state block (other columns) is a CONFLICT" 1 "^CONFLICT $(id 8): both changed the reproduction block" plan "${P7[@]}" --out "$tmp/p7.json"
xp "R4-1b: --resolve vehicle" 0 '^RESULT: PLAN mode=REPLAY own=0 ' plan "${P7[@]}" --out "$tmp/p7v.json" --resolve "$(id 8)=vehicle"
cpdb t7 r7v
xp "R4-1b: replay of --resolve vehicle" 0 '^RESULT: APPLIED ' replay --plan "$tmp/p7v.json" --apply --engine "$wi" --db docs/r7v.db
xp "R4-1b: verify of --resolve vehicle" 0 '^RESULT: PASS ' verify --plan "$tmp/p7v.json" "${P7[@]}" --db docs/r7v.db
same "R4-1b: --resolve vehicle lands the vehicle's whole block and stamps" "$(q "$repo/docs/r7v.db" 'select reproduction_env, reproduction_signature, reproduction_updated_by, reproduction_updated_at from items where atm_id=?' "$(id 8)")" "env two|sig one|remint test|2026-11-13T12:00:00Z"
xp "R4-1b: --resolve target" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=1 steps=0 ' plan "${P7[@]}" --out "$tmp/p7t.json" --resolve "$(id 8)=target"
cpdb t7 r7t
xp "R4-1b: replay of --resolve target" 0 '^RESULT: APPLIED steps=0' replay --plan "$tmp/p7t.json" --apply --engine "$wi" --db docs/r7t.db
xp "R4-1b: verify of --resolve target" 0 '^RESULT: PASS ' verify --plan "$tmp/p7t.json" "${P7[@]}" --db docs/r7t.db
cpdb b7 t8; W update --id "$(id 8)" --db docs/t8.db --location Issues --reproduction-env "env two" --states-updated-by "remint test" --states-updated-at 2026-11-13T12:00:00Z
xp "R4-1b: the same block change on both sides converges (nothing to write)" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=1 steps=0 conflicts=0 ' plan --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t8.db --out "$tmp/p8.json"
cpdb t8 r8
xp "R4-1b: replay of the converged plan" 0 '^RESULT: APPLIED steps=0' replay --plan "$tmp/p8.json" --apply --engine "$wi" --db docs/r8.db
xp "R4-1b: verify of the converged plan" 0 '^RESULT: PASS ' verify --plan "$tmp/p8.json" --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t8.db --db docs/r8.db
cpdb b7 t10; fx_sql "$repo/docs/t10.db" "update items set reproduction_updated_by='other' where atm_id=?" "$(id 8)"
xp "R4-1b: a target stamp change on a block the vehicle changed is a CONFLICT" 1 "^CONFLICT $(id 8): both changed the reproduction block" plan --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t10.db --out "$tmp/p10.json"
# RV7a: a vehicle lifecycle change against a target column change
cpdb t t9; W update --id "$(id 3)" --db docs/t9.db --location Issues --severity Medium
xp "RV7a: a vehicle lifecycle change and a target change is a CONFLICT" 1 "^CONFLICT $(id 3): a lifecycle change on one side and a change on the other" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t9.db --out "$tmp/p9.json"
# RV1, RV5, RV6: verify needles on copies of the landed database
cpdb r_after n16; W update --id "$(id 1)" --db docs/n16.db --location Issues --severity Low
vn "a target-side column the vehicle did not change (RV1)" "^MISMATCH $(id 1) severity: landed 'Low', target 'Medium' \(a column the vehicle did not change\)" n16
cpdb r_after n17; fx_sql "$repo/docs/n17.db" "update items set created_at='2026-01-01 00:00:00' where atm_id=?" "$(id 1)"
vn "a base created_at drift with no closure (RV5)" "^MISMATCH $(id 1) created_at: landed 2026-01-01 00:00:00" n17
vn "a base created_at drift with no closure carries no CON-339 note" "^MISMATCH $(id 1) created_at: landed 2026-01-01 00:00:00, target [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\$" n17
cpdb r_after n18; fx_sql "$repo/docs/n18.db" "update items set body_md = body_md || ' x' where atm_id=?" "$(id 2)"
vn "a base body_md the target did not change (RV6)" "^MISMATCH $(id 2) body_md: " n18
# RV4: an own item's created_at is never carried, and verify says so
cpdb v v10; fx_sql "$repo/docs/v10.db" "update items set created_at='2026-01-01 00:00:00' where atm_id=?" "$(id 13)"
xp "RV4: plan with an old own created_at" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/v10.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/p10v.json"
cpdb t r10
xp "RV4: replay" 0 '^RESULT: APPLIED ' replay --plan "$tmp/p10v.json" --apply --engine "$wi" --db docs/r10.db
xp "RV4: verify reports the own created_at as KNOWN" 0 "^KNOWN $(id 15) created_at: replay time .*\(vehicle 2026-01-01 00:00:00\), not carried" verify --plan "$tmp/p10v.json" --vehicle-db docs/v10.db --base-db docs/b.db --target-db docs/t.db --db docs/r10.db
# R4-2: verify recomputes the conflicts itself; a plan whose resolution is stripped fails on the landing it made
strip() { python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));p["resolutions"]={};json.dump(p,open(sys.argv[2],"w"))' "$1" "$2" || exit 2; }
strip "$tmp/cv.json" "$tmp/cv_s.json"
xp "verify FAIL: a column conflict whose --resolve vehicle is stripped" 1 "^MISMATCH $(id 1): both changed description, and the plan has no --resolve for it" verify --plan "$tmp/cv_s.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --db docs/rcv.db
strip "$tmp/ct.json" "$tmp/ct_s.json"
xp "verify FAIL: a column conflict whose --resolve target is stripped" 1 "^MISMATCH $(id 1): both changed description, and the plan has no --resolve for it" verify --plan "$tmp/ct_s.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --db docs/rct.db
strip "$tmp/p7v.json" "$tmp/p7v_s.json"
xp "verify FAIL: a block conflict whose --resolve is stripped" 1 "^MISMATCH $(id 8): both changed the reproduction block, and the plan has no --resolve for it" verify --plan "$tmp/p7v_s.json" "${P7[@]}" --db docs/r7v.db
xp "--resolve vehicle of a lifecycle conflict" 0 '^RESULT: PLAN mode=REPLAY' plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t3.db --out "$tmp/c3v.json" --resolve "$(id 1)=vehicle"
cpdb t3 rc3v
xp "replay of --resolve vehicle on a lifecycle conflict" 0 '^RESULT: APPLIED' replay --plan "$tmp/c3v.json" --apply --engine "$wi" --db docs/rc3v.db
xp "verify of --resolve vehicle on a lifecycle conflict" 0 '^RESULT: PASS' verify --plan "$tmp/c3v.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t3.db --db docs/rc3v.db
strip "$tmp/c3v.json" "$tmp/c3v_s.json"
xp "verify FAIL: a lifecycle conflict whose --resolve is stripped" 1 "^MISMATCH $(id 1): a lifecycle change on one side and a change on the other, and the plan has no --resolve for it" verify --plan "$tmp/c3v_s.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t3.db --db docs/rc3v.db
# R4-5: a new own id with non-ASCII digits is refused at plan time
cpdb v x14; W add Task Low --db docs/x14.db --id "CON-９０１" --title "Fullwidth id item" --description "$D An item whose id has fullwidth digits." --created-by Claude
pr "a new id with non-ASCII digits" '^REFUSED CON-９０１: a new vehicle id with non-ASCII digits' x14
# round 5, branch sweep (R4-2): a close the vehicle made with no evidence on its closure row is refused
cpdb v x15; W close "$(id 8)" --db docs/x15.db --status completed --evidence "$EV"
fx_sql "$repo/docs/x15.db" "update item_history set evidence_path='' where atm_id=? and event_type in ('Fixed', 'Implemented', 'Completed', 'Obsolete')" "$(id 8)"
pr "a vehicle close whose closure row has no evidence" "^REFUSED base $(id 8): the vehicle closed it but has no new closure history row with evidence to replay" x15
# R4-9: a database path is a path, never URI syntax; a non-empty -wal sidecar is refused on every database
cp "$repo/docs/b.db" "$repo/docs/b?x#y.db" || exit 2
xp "R4-9: a database path holding ? and # is opened as that file" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/v.db --base-db 'docs/b?x#y.db' --target-db docs/t.db --out "$tmp/uq.json"
[ ! -e "$repo/docs/b" ] && ok "R4-9: no stray database file is created" || bad "R4-9: no stray database file is created" "docs/b exists"
for k in v b t; do cpdb "$k" "wal$k"; printf 'not empty' >"$repo/docs/wal$k.db-wal"; done
xp "R4-9: plan refuses a vehicle with a non-empty -wal" 1 'non-empty -wal sidecar' plan --vehicle-db docs/walv.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/wl.json"
xp "R4-9: plan refuses a base with a non-empty -wal" 1 'non-empty -wal sidecar' plan --vehicle-db docs/v.db --base-db docs/walb.db --target-db docs/t.db --out "$tmp/wl.json"
xp "R4-9: plan refuses a target with a non-empty -wal" 1 'non-empty -wal sidecar' plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/walt.db --out "$tmp/wl.json"
cpdb r_after walr; printf 'not empty' >"$repo/docs/walr.db-wal"
xp "R4-9: verify refuses a landed copy with a non-empty -wal" 1 'non-empty -wal sidecar' verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/walr.db
: >"$repo/docs/walr.db-wal"
xp "R4-9: an empty -wal sidecar is not refused (control)" 0 '^RESULT: PASS ' verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/walr.db

# round 5, own mutants: one block changed to the same content with other stamps is a CONFLICT (N2), and
# a --resolve vehicle lands the vehicle's stamps (N20)
cpdb b7 t11; W update --id "$(id 8)" --db docs/t11.db --location Issues --reproduction-env "env two" --states-updated-by "target" --states-updated-at 2026-11-13T12:30:00Z
xp "a block both changed to the same content with other stamps is a CONFLICT" 1 "^CONFLICT $(id 8): both changed the reproduction block" plan --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t11.db --out "$tmp/p11.json"
# --resolve vehicle cannot land the vehicle's stamps there: replaying the same content changes nothing and
# the engine stamps a block only on a content change (verify caught the first version of this case)
xp "--resolve vehicle of a same-content block with other stamps is refused" 1 "^REFUSED $(id 8): --resolve vehicle cannot land the reproduction block: its content is already the target's" plan --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t11.db --out "$tmp/p11v.json" --resolve "$(id 8)=vehicle"
grep -q '^RESULT: NOT-LANDABLE mode=REPLAY own=0 base_changes=1 steps=0 ' "$tmp/out" && ok "the refused item gets no steps" || bad "the refused item gets no steps" "$(grep '^RESULT' "$tmp/out")"
xp "--resolve target of the same-content block conflict" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=1 steps=0 ' plan --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t11.db --out "$tmp/p11t.json" --resolve "$(id 8)=target"
cpdb t11 r11
xp "replay of the same-content block conflict resolved for the target" 0 '^RESULT: APPLIED steps=0' replay --plan "$tmp/p11t.json" --apply --engine "$wi" --db docs/r11.db
xp "verify: the target's block and stamps stay" 0 '^RESULT: PASS ' verify --plan "$tmp/p11t.json" --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t11.db --db docs/r11.db
strip "$tmp/p11t.json" "$tmp/p11t_s.json"
xp "verify FAIL: a same-content block with other stamps whose --resolve is stripped" 1 "^MISMATCH $(id 8): both changed the reproduction block, and the plan has no --resolve for it" verify --plan "$tmp/p11t_s.json" --vehicle-db docs/v7.db --base-db docs/b7.db --target-db docs/t11.db --db docs/r11.db
# a column both sides changed to the same text after the map converges: nothing is written for it (N5, N19)
cpdb t t12; W update --id "$(id 8)" --db docs/t12.db --location Issues --title "Remint base item 8, see $(id 15)"
xp "a title both sides changed the same way (after the map) converges" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/v5.db --base-db docs/b.db --target-db docs/t12.db --out "$tmp/p12.json"
grep -q "^MERGE $(id 8): vehicle severity,title, target title (the same change on both sides: title)\$" "$tmp/out" && ok "the converged merge line" || bad "the converged merge line" "$(grep MERGE "$tmp/out" | tr '\n' '|')"
xp "dry run of the converged plan" 0 '^RESULT: DRY-RUN ' replay --plan "$tmp/p12.json"
grep -F "\"--id=$(id 8)\"" "$tmp/out" | grep -qF -- '"--severity=High"' && ! grep -F "\"--id=$(id 8)\"" "$tmp/out" | grep -qF -- '--title=' && ok "the converged title is not written, the severity is" || bad "the converged title is not written, the severity is" "$(grep -F "\"--id=$(id 8)\"" "$tmp/out" | cut -c1-300)"
cpdb t12 r12
xp "replay of the converged plan" 0 '^RESULT: APPLIED ' replay --plan "$tmp/p12.json" --apply --engine "$wi" --db docs/r12.db
xp "verify of the converged plan" 0 '^RESULT: PASS ' verify --plan "$tmp/p12.json" --vehicle-db docs/v5.db --base-db docs/b.db --target-db docs/t12.db --db docs/r12.db
# verify needles on the R4-1a landing: a vehicle-side column (N17) and an obsolete_details row the vehicle never wrote (N15)
cpdb r5 n21; W update --id "$(id 8)" --db docs/n21.db --location Issues --severity Low
xp "verify FAIL: a vehicle-side column landed wrong" 1 "^MISMATCH $(id 8) severity: landed 'Low', vehicle 'High'" verify --plan "$tmp/p5.json" "${P5[@]}" --db docs/n21.db
cpdb r5 n20; fx_sql "$repo/docs/n20.db" "insert into obsolete_details(atm_id, since, reason, superseding_item, triple_check_evidence) values(?, '2026-11-13', 'feature-removed', 'none', 'needle')" "$(id 8)"
xp "verify FAIL: an obsolete_details row the vehicle did not write" 1 "^MISMATCH $(id 8) obsolete_details: differs from the target, and the vehicle did not change it" verify --plan "$tmp/p5.json" "${P5[@]}" --db docs/n20.db
# a target stamp change alone, on a block the vehicle did not change, is still a target change of that block (N1)
cpdb t t13; fx_sql "$repo/docs/t13.db" "update items set reproduction_updated_by='other' where atm_id=?" "$(id 8)"
xp "a target stamp-only change on another block merges" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/v5.db --base-db docs/b.db --target-db docs/t13.db --out "$tmp/p13.json"
grep -q "^MERGE $(id 8): vehicle severity,title, target reproduction_updated_by (disjoint columns)\$" "$tmp/out" && ok "the merge line names the target's stamp" || bad "the merge line names the target's stamp" "$(grep MERGE "$tmp/out" | tr '\n' '|')"
cpdb t13 r13
xp "replay of the stamp-only merge" 0 '^RESULT: APPLIED ' replay --plan "$tmp/p13.json" --apply --engine "$wi" --db docs/r13.db
xp "verify of the stamp-only merge keeps the target's stamp" 0 '^RESULT: PASS ' verify --plan "$tmp/p13.json" --vehicle-db docs/v5.db --base-db docs/b.db --target-db docs/t13.db --db docs/r13.db

# ---- (9) round 5: cases for the branch sweep's survivors (R4-2), each named for the branch it pins ----
# lifecycle_steps: the close kind is the vehicle's status; a closure row of another kind (a state no engine
# command makes) does not change it
cpdb v x16; W close "$(id 8)" --db docs/x16.db --status completed --evidence "$EV"
fx_sql "$repo/docs/x16.db" "update item_history set event_type='Fixed' where atm_id=? and event_type='Completed'" "$(id 8)"
xp "plan of a vehicle close whose closure row names another kind" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x16.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x16.json" --repo-root .
xp "dry run of that plan" 0 '^RESULT: DRY-RUN ' replay --plan "$tmp/x16.json"
grep -F "\"close\", \"$(id 8)\"" "$tmp/out" | grep -qF -- '"--status=completed"' && ok "the close kind is the vehicle's status, not the kind of its closure row" || bad "the close kind is the vehicle's status, not the kind of its closure row" "$(grep -F "\"close\", \"$(id 8)\"" "$tmp/out" | cut -c1-300)"
# lifecycle_steps: a reopen replays the last Reopened row, even when another history row follows it
cpdb v x17; W close "$(id 8)" --db docs/x17.db --status completed --evidence "$EV"
W reopen --id "$(id 8)" --db docs/x17.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
W update --id "$(id 8)" --db docs/x17.db --location Issues --title "Remint base item 8, retitled after its reopen"
xp "plan of a reopen followed by an update" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x17.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x17.json" --repo-root .
xp "dry run of the reopen followed by an update" 0 '^RESULT: DRY-RUN ' replay --plan "$tmp/x17.json"
grep -F "\"reopen\", \"--id=$(id 8)\"" "$tmp/out" | grep -qF -- '"--why=design-reconsidered"' && ok "the reopen replays the last Reopened row, not the last history row" || bad "the reopen replays the last Reopened row, not the last history row" "$(grep -F "\"reopen\", \"--id=$(id 8)\"" "$tmp/out" | cut -c1-300)"
cpdb t r17
xp "replay of the reopen followed by an update" 0 '^RESULT: APPLIED ' replay --plan "$tmp/x17.json" --apply --engine "$wi" --db docs/r17.db
xp "verify of the reopen followed by an update" 0 '^RESULT: PASS ' verify --plan "$tmp/x17.json" --vehicle-db docs/x17.db --base-db docs/b.db --target-db docs/t.db --db docs/r17.db
# fail closed (characterization of an engine defect, round 5, owed to the conductor): after a reopen,
# `update --severity` changes the column but leaves the body's Severity line; the replay updates before it
# closes, so the landed body differs, and verify refuses to certify it (never a PASS on a body that differs)
cpdb x17 x17s; W update --id "$(id 8)" --db docs/x17s.db --location Issues --severity High
xp "plan of a reopen followed by a severity update" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x17s.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x17s.json" --repo-root .
cpdb t r17s
xp "replay of the reopen followed by a severity update" 0 '^RESULT: APPLIED ' replay --plan "$tmp/x17s.json" --apply --engine "$wi" --db docs/r17s.db
xp "verify FAIL: the engine's stale Severity line in the vehicle body is not certified" 1 "^MISMATCH $(id 8) body_md: text differs outside the ids" verify --plan "$tmp/x17s.json" --vehicle-db docs/x17s.db --base-db docs/b.db --target-db docs/t.db --db docs/r17s.db
# lifecycle_steps: a vehicle item that is Reopened with no new Reopened history row (a state no engine command
# makes) is refused
cpdb x17 x18; fx_sql "$repo/docs/x18.db" "delete from item_history where atm_id=? and event_type='Reopened'" "$(id 8)"
pr "a vehicle reopen with no new Reopened history row" "^REFUSED base $(id 8): the vehicle reopened it but has no new Reopened history row" x18
# lifecycle_steps: a reopen the vehicle kept in Fixed.md is replayed with --location=Fixed
cpdb v x19; W close "$(id 8)" --db docs/x19.db --status completed --evidence "$EV"
W reopen --id "$(id 8)" --db docs/x19.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV" --location Fixed
xp "plan of a reopen kept in Fixed" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x19.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x19.json" --repo-root .
xp "dry run of the reopen kept in Fixed" 0 '^RESULT: DRY-RUN ' replay --plan "$tmp/x19.json"
grep -F "\"reopen\", \"--id=$(id 8)\"" "$tmp/out" | grep -qF -- '"--location=Fixed"' && ok "a reopen kept in Fixed is replayed with --location=Fixed" || bad "a reopen kept in Fixed is replayed with --location=Fixed" "$(grep -F "\"reopen\", \"--id=$(id 8)\"" "$tmp/out" | cut -c1-300)"
cpdb t r19
xp "replay of the reopen kept in Fixed" 0 '^RESULT: APPLIED ' replay --plan "$tmp/x19.json" --apply --engine "$wi" --db docs/r19.db
same "landed: the reopen kept in Fixed" "$(q "$repo/docs/r19.db" 'select status, current_location from items where atm_id=?' "$(id 8)")" "Reopened|Fixed"
xp "verify of the reopen kept in Fixed" 0 '^RESULT: PASS ' verify --plan "$tmp/x19.json" --vehicle-db docs/x19.db --base-db docs/b.db --target-db docs/t.db --db docs/r19.db
# lifecycle_steps: a closed base item the vehicle reopened and then closed with another kind has no engine path
# from the target's closed state (the refusal, never a status update the engine would refuse)
cpdb v x20; W reopen --id "$(id 5)" --db docs/x20.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
W close "$(id 5)" --db docs/x20.db --status completed --evidence "$EV"
pr "a closed base item closed again with another kind" "^REFUSED base $(id 5): no engine path from 'Obsolete" x20
# block_steps: a block the vehicle reset to UNSET is replayed as the state alone
cpdb b7 v20; W update --id "$(id 8)" --db docs/v20.db --location Issues --reproduction-state UNSET --states-updated-by "remint test"
cpdb b7 t20
P20=(--vehicle-db docs/v20.db --base-db docs/b7.db --target-db docs/t20.db)
xp "plan of a block reset to UNSET" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=1 steps=1 ' plan "${P20[@]}" --out "$tmp/p20.json" --no-fast-forward
xp "dry run of the block reset" 0 '^RESULT: DRY-RUN steps=1$' replay --plan "$tmp/p20.json"
grep -F "\"--id=$(id 8)\"" "$tmp/out" | grep -qF -- '"--reproduction-state=UNSET"' && ! grep -F "\"--id=$(id 8)\"" "$tmp/out" | grep -qF -- '--reproduction-env' && ok "a block reset passes the state alone" || bad "a block reset passes the state alone" "$(grep -F "\"--id=$(id 8)\"" "$tmp/out" | cut -c1-300)"
cpdb t20 r20
xp "replay of the block reset" 0 '^RESULT: APPLIED steps=1' replay --plan "$tmp/p20.json" --apply --engine "$wi" --db docs/r20.db
same "landed: the block reset" "$(q "$repo/docs/r20.db" 'select reproduction_state, reproduction_env, reproduction_signature from items where atm_id=?' "$(id 8)")" "UNSET||"
xp "verify of the block reset" 0 '^RESULT: PASS ' verify --plan "$tmp/p20.json" "${P20[@]}" --db docs/r20.db
# block_steps: the block's text columns are rewritten through the map
cpdb v x21; W update --id "$(id 10)" --db docs/x21.db --location Issues --reproduction-state UNREPRODUCED --reproduction-signature "fails like $(id 9)" --states-updated-by "remint test" --states-updated-at 2026-11-13T10:00:00Z
xp "plan of an own block naming a moved id" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x21.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x21.json" --repo-root .
xp "dry run of the own block" 0 '^RESULT: DRY-RUN ' replay --plan "$tmp/x21.json"
grep -F "\"--id=$(id 12)\"" "$tmp/out" | grep -qF -- "\"--reproduction-signature=fails like $(id 11)\"" && ok "a block text column is rewritten through the map" || bad "a block text column is rewritten through the map" "$(grep -F "\"--id=$(id 12)\"" "$tmp/out" | grep -F -- --reproduction-state | cut -c1-400)"
cpdb t r21
xp "replay of the own block" 0 '^RESULT: APPLIED ' replay --plan "$tmp/x21.json" --apply --engine "$wi" --db docs/r21.db
same "landed: the own block" "$(q "$repo/docs/r21.db" 'select reproduction_signature from items where atm_id=?' "$(id 12)")" "fails like $(id 11)"
xp "verify of the own block" 0 '^RESULT: PASS ' verify --plan "$tmp/x21.json" --vehicle-db docs/x21.db --base-db docs/b.db --target-db docs/t.db --db docs/r21.db
# keep(): a value passed as written (here an evidence column, the class of every non-rewritten vehicle value)
# that names a moved id is refused at plan time, in a path and as a bare id; a foreign declaration keeps it
printf 'evidence\n' >"$repo/docs/qa/$(id 9).txt" || exit 2
cpdb v x21p; W update --id "$(id 10)" --db docs/x21p.db --location Issues --reproduction-state UNREPRODUCED --reproduction-evidence "docs/qa/$(id 9).txt" --states-updated-by "remint test" --states-updated-at 2026-11-13T10:00:00Z
pr "an evidence path naming a moved id" "^REFUSED: own $(id 10) reproduction_evidence: moved id $(id 9) is part of a path; a path is never rewritten" x21p
cpdb v x21b; W update --id "$(id 10)" --db docs/x21b.db --location Issues --investigation-state root-cause-unconfirmed --investigation-evidence "$(id 9)" --states-updated-by "remint test" --states-updated-at 2026-11-13T10:00:00Z
pr "an evidence value that is a moved id" "^REFUSED: own $(id 10) investigation_evidence: '$(id 9)' names an id the map moves, in a value that is never rewritten" x21b
# (item 10's own Foreign line declares id 11 foreign for that item: its evidence path naming id 11 is kept)
printf 'evidence\n' >"$repo/docs/qa/$(id 11).txt" || exit 2
cpdb v x21f; W update --id "$(id 10)" --db docs/x21f.db --location Issues --reproduction-state UNREPRODUCED --reproduction-evidence "docs/qa/$(id 11).txt" --states-updated-by "remint test" --states-updated-at 2026-11-13T10:00:00Z
xp "plan of an evidence path naming an id the item declares foreign" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x21f.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x21f.json" --repo-root .
cpdb t r21f
xp "replay of the foreign evidence path" 0 '^RESULT: APPLIED ' replay --plan "$tmp/x21f.json" --apply --engine "$wi" --db docs/r21f.db
same "landed: the foreign evidence path as written" "$(q "$repo/docs/r21f.db" 'select reproduction_evidence from items where atm_id=?' "$(id 12)")" "docs/qa/$(id 11).txt"
xp "verify of the foreign evidence path" 0 '^RESULT: PASS ' verify --plan "$tmp/x21f.json" --vehicle-db docs/x21f.db --base-db docs/b.db --target-db docs/t.db --db docs/r21f.db
cpdb v x21c; W close "$(id 8)" --db docs/x21c.db --status completed --evidence "docs/qa/$(id 9).txt"
pr "a closure evidence path naming a moved id" "^REFUSED: base $(id 8) closure evidence: moved id $(id 9) is part of a path" x21c
cpdb v x21r; W close "$(id 8)" --db docs/x21r.db --status completed --evidence "$EV"
W reopen --id "$(id 8)" --db docs/x21r.db --why design-reconsidered --who AI --when 2026-11-13 --incident "docs/qa/$(id 9).txt"
pr "a reopen incident path naming a moved id" "^REFUSED: base $(id 8) Reopened row evidence_path: moved id $(id 9) is part of a path" x21r
cpdb v x21o; W obsolete-details "$(id 5)" --db docs/x21o.db --since 2026-11-12 --reason not-reproducible --superseding none --evidence "docs/qa/$(id 9).txt"
pr "an obsolete_details evidence path naming a moved id" "^REFUSED: base $(id 5) obsolete_details.triple_check_evidence: moved id $(id 9) is part of a path" x21o
cpdb v x21a; W update --id "$(id 9)" --db docs/x21a.db --location Issues --assigned-to "owner of $(id 10)"
pr "an own assignee naming a moved id" "^REFUSED: own $(id 9) assigned_to: 'owner of $(id 10)' names an id the map moves" x21a
# block_steps: a block whose time stamp the vehicle left empty (the engine stores an empty --states-updated-at
# as NULL, and an omitted one as the time of the replay) lands with the empty stamp
cpdb v x22; W update --id "$(id 8)" --db docs/x22.db --location Issues --reproduction-state UNREPRODUCED --states-updated-by "remint test" --states-updated-at=
same "fixture: an empty --states-updated-at is stored as NULL" "$(q "$repo/docs/x22.db" 'select reproduction_state, coalesce(reproduction_updated_at, "NULL"), reproduction_updated_by from items where atm_id=?' "$(id 8)")" "UNREPRODUCED|NULL|remint test"
xp "plan of a block with an empty stamp" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x22.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x22.json" --repo-root .
cpdb t r22
xp "replay of the empty-stamp block" 0 '^RESULT: APPLIED ' replay --plan "$tmp/x22.json" --apply --engine "$wi" --db docs/r22.db
same "landed: the empty stamp" "$(q "$repo/docs/r22.db" 'select reproduction_state, coalesce(reproduction_updated_at, "NULL"), reproduction_updated_by from items where atm_id=?' "$(id 8)")" "UNREPRODUCED|NULL|remint test"
xp "verify of the empty-stamp block" 0 '^RESULT: PASS ' verify --plan "$tmp/x22.json" --vehicle-db docs/x22.db --base-db docs/b.db --target-db docs/t.db --db docs/r22.db
# make_plan: an item with two rows (a state the schema allows, one row per location and representation) is
# refused, never planned from its first row
cpdb v x23; fx_sql "$repo/docs/x23.db" "insert into items (atm_id, type, status, severity, title, description, current_location, representation) select atm_id, type, status, severity, title, description, current_location, 'table' from items where atm_id=?" "$(id 8)"
pr "a base item with two rows" "^REFUSED $(id 8): 2 rows \\(one expected\\)" x23
# make_plan: an item whose only change is last_modified is noted, never refused
cpdb v x24; fx_sql "$repo/docs/x24.db" "update items set last_modified='2026-11-13 12:00:00' where atm_id=?" "$(id 8)"
xp "plan of a vehicle whose only change is a last_modified" 0 "^NOTE $(id 8): only last_modified differs from the base; nothing to replay" plan --vehicle-db docs/x24.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x24.json" --repo-root .
grep -q "^NOTE $(id 8): created_at" "$tmp/out" && bad "no created_at note when only last_modified changed" "$(grep '^NOTE ' "$tmp/out" | tr '\n' '|' | cut -c1-300)" || ok "no created_at note when only last_modified changed"
# make_plan: an item whose only change is created_at is noted (not carried: no engine command sets it)
cpdb v x24c; fx_sql "$repo/docs/x24c.db" "update items set created_at='2026-01-01 00:00:00' where atm_id=?" "$(id 8)"
xp "plan of a vehicle whose only change is a created_at" 0 "^NOTE $(id 8): created_at differs from the base with no other change; not carried" plan --vehicle-db docs/x24c.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x24c.json" --repo-root .
grep -q "^NOTE $(id 8): only last_modified" "$tmp/out" && bad "no last_modified note when created_at changed" "$(grep '^NOTE ' "$tmp/out" | tr '\n' '|' | cut -c1-300)" || ok "no last_modified note when created_at changed"
# make_plan: the next free number counts only the ids of the prefix (a target item of another prefix with a
# higher number does not move the re-mint)
cpdb t t25; W add Task Low --db docs/t25.db --id AA-900 --title "Foreign prefix target item" --description "$D A target item outside the prefix." --created-by Claude
xp "plan against a target holding a higher id of another prefix" 0 "^RESULT: PLAN mode=REPLAY own=5 .* first=$(id 11) last=$(id 15)\$" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t25.db --out "$tmp/x25.json" --repo-root .
# make_plan: a new id that equals a base item the target deleted (a state no engine command makes) is refused
cpdb b t26; fx_sql "$repo/docs/t26.db" "delete from items where atm_id=?" "$(id 8)"
xp "plan refusal: a new id equal to a base item the target lacks" 1 "^REFUSED new id $(id 8) is an item of the vehicle that is not moved" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t26.db --out "$tmp/x26.json" --repo-root .
# make_plan: base items are planned by prefix, then by number (a narrow id before a wide one), and an id with
# no number sorts by its text instead of failing
cpdb b b27; W add Task Low --db docs/b27.db --id CON-99 --title "A base item with a narrow id" --description "$D A base item numbered below the others." --created-by Claude
W add Task Low --db docs/b27.db --id AA-x1 --title "A base item of another prefix" --description "$D A base item whose id carries no number." --created-by Claude
cpdb b27 v27; for k in "$(id 1)" CON-99 AA-x1; do W update --id "$k" --db docs/v27.db --location Issues --title "A retitled base item"; done
cpdb b27 t27
xp "plan of base changes on ids of mixed width and prefix" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=3 ' plan --vehicle-db docs/v27.db --base-db docs/b27.db --target-db docs/t27.db --out "$tmp/x27.json" --no-fast-forward
same "base changes are listed by prefix, then number" "$(grep '^BASE-CHANGE ' "$tmp/out" | cut -d' ' -f2 | tr '\n' ' ')" "AA-x1 CON-99 $(id 1) "
# make_plan: a base text naming an id the map does not move is not ambiguous
cpdb b b28; W update --id "$(id 4)" --db docs/b28.db --location Issues --description "$D Base item 4, see $(id 1)."
cpdb b28 v28; W update --id "$(id 4)" --db docs/v28.db --location Issues --title "Remint base item 4, retitled"
cpdb b28 t28
xp "plan of a base item whose base text names an id the map leaves" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=1 ' plan --vehicle-db docs/v28.db --base-db docs/b28.db --target-db docs/t28.db --out "$tmp/x28.json" --no-fast-forward
# make_plan: a target item with two rows is refused, never merged from its first row
cpdb t t29; fx_sql "$repo/docs/t29.db" "insert into items (atm_id, type, status, severity, title, description, current_location, representation) select atm_id, type, status, severity, title, description, current_location, 'table' from items where atm_id=?" "$(id 1)"
xp "plan refusal: a target item with two rows" 1 "^REFUSED $(id 1): 2 rows \\(one expected\\)" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t29.db --out "$tmp/x29.json" --repo-root .
# make_plan: a block whose content the target changed counts as its columns, not also as its stamps
cpdb t t30; W update --id "$(id 1)" --db docs/t30.db --location Issues --reproduction-state UNREPRODUCED --states-updated-by "target test" --states-updated-at 2026-11-13T09:00:00Z
xp "plan against a target that changed a block of a merged item" 0 "^MERGE $(id 1): vehicle description, target severity,reproduction_state \\(disjoint columns\\)\$" plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t30.db --out "$tmp/x30.json" --repo-root .
# make_plan: a target change of obsolete_details counts as a target change (here a conflict with the vehicle's)
cpdb t t31; W obsolete-details "$(id 5)" --db docs/t31.db --since 2026-11-11 --reason superseded-by-later-mandate --superseding none --evidence "$EV"
xp "plan against a target that changed the same obsolete_details row" 1 "^CONFLICT $(id 5): both changed obsolete_details " plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t31.db --out "$tmp/x31.json" --repo-root .
# keep() on a base item's update: a non-text column the vehicle changed is passed as written, so a moved id in
# it is refused (never rewritten)
cpdb v x32; W update --id "$(id 4)" --db docs/x32.db --location Issues --assigned-to "owner of $(id 10)"
pr "a base assignee naming a moved id" "^REFUSED: base $(id 4) assigned_to: 'owner of $(id 10)' names an id the map moves" x32
# make_plan: the same obsolete_details change on both sides is still a conflict (a lifecycle unit changed on
# one side and anything changed on the other is a conflict, M10), named as such and not as two rows differing
cpdb t t33; W obsolete-details "$(id 5)" --db docs/t33.db --since 2026-11-12 --reason not-reproducible --superseding none --evidence "$EV"
xp "plan against a target that made the vehicle's obsolete_details change" 1 "^CONFLICT $(id 5): a lifecycle change on one side and a change on the other " plan --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t33.db --out "$tmp/x33.json" --repo-root .
# M13: under --resolve ID=vehicle a unit only the target changed lands from the target (here the severity of
# the description conflict's item), and verify checks that unit against the target
same "--resolve vehicle keeps the unit only the target changed (M13)" "$(q "$repo/docs/rcv.db" 'select severity from items where atm_id=?' "$(id 1)")" "Medium"
cpdb rcv n34; W update --id "$(id 1)" --db docs/n34.db --location Issues --severity High
xp "verify FAIL: a unit only the target changed, landed wrong under --resolve vehicle (M13)" 1 "^MISMATCH $(id 1) severity: landed 'High', target 'Medium'" verify --plan "$tmp/cv.json" --vehicle-db docs/v.db --base-db docs/b.db --target-db docs/t2.db --db docs/n34.db
# keep() on a block's stamps: the author and the time of a block are passed as written, so a moved id in them is
# refused
# (the signature changes the block's content: the engine stamps a block only when its content changes)
cpdb v x35; W update --id "$(id 10)" --db docs/x35.db --location Issues --reproduction-state UNREPRODUCED --reproduction-signature "fails in x35" --states-updated-by "agent of $(id 9)" --states-updated-at 2026-11-13T10:00:00Z
same "fixture: the block author names a moved id" "$(q "$repo/docs/x35.db" 'select reproduction_updated_by from items where atm_id=?' "$(id 10)")" "agent of $(id 9)"
pr "a block author naming a moved id" "^REFUSED: own $(id 10) reproduction_updated_by: 'agent of $(id 9)' names an id the map moves" x35
# make_plan (branch sweep): an Obsolete base item the vehicle reopened without touching its obsolete_details
# row gets the reopen step only; the row is the base's, the target left it alone, so it is not a vehicle unit
cpdb b x37; W reopen --id "$(id 5)" --db docs/x37.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
same "fixture: the reopen kept the base's obsolete_details row" "$(q "$repo/docs/x37.db" 'select since, reason, superseding_item from obsolete_details where atm_id=?' "$(id 5)")" "$(q "$repo/docs/b.db" 'select since, reason, superseding_item from obsolete_details where atm_id=?' "$(id 5)")"
xp "plan of a reopen of an Obsolete item whose row the vehicle left alone" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=1 steps=1 conflicts=0 refusals=0 ' plan --vehicle-db docs/x37.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x37.json" --repo-root .
same "plan: the reopen only, no obsolete_details step" "$(python3 -I -c 'import json,sys;print(",".join(s["kind"] for s in json.load(open(sys.argv[1]))["steps"]))' "$tmp/x37.json")" "reopen"
# make_plan (branch sweep): in FAST-FORWARD the vehicle database is the landed database, so an own item is not
# replayed and a column add cannot carry is no reason to refuse (the copy carries it; x9 is refused in REPLAY)
xp "plan: FAST-FORWARD of a vehicle whose own item holds a column add cannot carry" 0 "^RESULT: PLAN mode=FAST-FORWARD own=5 base_changes=5 steps=0 conflicts=0 refusals=0 " plan --vehicle-db docs/x9.db --base-db docs/b.db --target-db docs/tff.db --out "$tmp/x9ff.json"
# make_plan (branch sweep): an own item with two rows is refused, never planned from its first row
cpdb v x38; fx_sql "$repo/docs/x38.db" "insert into items (atm_id, type, status, severity, title, description, current_location, representation) select atm_id, type, status, severity, title, description, current_location, 'table' from items where atm_id=?" "$(id 13)"
pr "an own item with two rows" "^REFUSED $(id 13): 2 rows \\(one expected\\)" x38
# engine fact the branch-sweep register rests on (make_plan|if|kv["created_by"] and kv["assigned_to"] forced
# True are equivalent): add with an empty --created-by= and --assigned-to= stores the same item, history row
# and segment as add without them, because both flags default to ''. The wall-clock columns are left out
# (items created_at and last_modified, history occurred_at, created_at and on_date): two adds a second apart
# differ there, and the case once compared history created_at and failed at random (red/engine_fact_flake.txt)
cpdb b e1; W add Task Low --db docs/e1.db --id "$(id 20)" --title "Engine fact item" --description "$D Engine fact item." --created-by= --assigned-to=
cpdb b e2; W add Task Low --db docs/e2.db --id "$(id 20)" --title "Engine fact item" --description "$D Engine fact item."
fact=$(python3 -I - "$repo/docs/e1.db" "$repo/docs/e2.db" "$(id 20)" <<'PY'
import sqlite3, sys, urllib.parse
def dump(p, k):
    c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(p), uri=True)
    c.row_factory = sqlite3.Row
    def rows(sql, skip):
        return [{x: r[x] for x in r.keys() if x not in skip} for r in c.execute(sql, (k,))]
    return (rows("select * from items where atm_id=?", ("id", "created_at", "last_modified")),
            rows("select * from item_history where atm_id=? order by id", ("id", "occurred_at", "created_at", "on_date")),
            rows("select * from doc_segments where atm_id=? order by id", ("id", "seq")))
a, b = dump(sys.argv[1], sys.argv[3]), dump(sys.argv[2], sys.argv[3])
print("same" if a == b and all(len(x) == 1 for x in a) else "differ in part %s" % [n for n in range(3) if a[n] != b[n]])
PY
)
same "engine fact: an empty --created-by= and --assigned-to= equal omitting them" "$fact" "same"
# make_plan (branch sweep): an own item's lifecycle replays from its own history rows only; with two own items
# closed with different evidence, each close step carries its own item's evidence (and the base close its own)
printf 'evidence y\n' >"$repo/docs/qa/y.txt" || exit 2
cpdb v x39; W close "$(id 13)" --db docs/x39.db --status completed --evidence docs/qa/y.txt
xp "plan of own items closed with different evidence" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/x39.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/x39.json" --repo-root .
same "plan: each close step carries its own item's evidence" "$(python3 -I -c 'import json,sys;print("|".join(s["from"] + "=" + [a for a in s["argv"] if a.startswith("--evidence=")][0] for s in json.load(open(sys.argv[1]))["steps"] if s["kind"] == "close"))' "$tmp/x39.json")" "$(id 3)=--evidence=$EV|$(id 11)=--evidence=$EV|$(id 12)=--evidence=$EV|$(id 13)=--evidence=docs/qa/y.txt"
# round 5, final branch sweep: an engine step that fails stops the replay at that step (here a real
# engine failure: the target copy is read-only), and no later step runs
cpdb t ro1; chmod 444 "$repo/docs/ro1.db" || exit 2
xp "replay stops at the first engine step that fails" 1 '^RESULT: STOPPED at step 1 of [0-9]+ ' replay --plan "$tmp/plan.json" --apply --engine "$wi" --db docs/ro1.db
grep -q '^step 2 ' "$tmp/out" && bad "the stopped replay runs no further step" "$(grep -m1 '^step 2 ' "$tmp/out")" || ok "the stopped replay runs no further step"
# round 5, final branch sweep: verify passes a landed text that holds a range of ids that do not move
cpdb v xum; W update --id "$(id 13)" --db docs/xum.db --location Issues --description "$D Plain own item; see the base range $(id 1)..$(id 2)."
xp "plan of an own text holding a range of ids that do not move" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan --vehicle-db docs/xum.db --base-db docs/b.db --target-db docs/t.db --out "$tmp/xum.json" --repo-root .
cpdb t rum
xp "replay of the range of ids that do not move" 0 '^RESULT: APPLIED ' replay --plan "$tmp/xum.json" --apply --engine "$wi" --db docs/rum.db
same "landed: the range of ids that do not move, as written" "$(q "$repo/docs/rum.db" 'select description from items where atm_id=?' "$(id 15)")" "$D Plain own item; see the base range $(id 1)..$(id 2)."
xp "verify of a text holding a range of ids that do not move" 0 '^RESULT: PASS ' verify --plan "$tmp/xum.json" --vehicle-db docs/xum.db --base-db docs/b.db --target-db docs/t.db --db docs/rum.db
# round 5, final branch sweep: verify refuses a plan the planner did not call landable (T2), and its own
# reading of the own set flags a new id outside the prefix on a plan whose refusals were removed (T3)
xp "plan: FAST-FORWARD of a vehicle with an id outside the prefix is not landable" 1 '^RESULT: NOT-LANDABLE mode=FAST-FORWARD ' plan --vehicle-db docs/x2.db --base-db docs/b.db --target-db docs/tff.db --out "$tmp/x2ff.json"
xp "verify refuses a plan the planner did not call landable" 1 'it was never landable, so there is no landing to verify' verify --plan "$tmp/x2ff.json" --vehicle-db docs/x2.db --base-db docs/b.db --target-db docs/tff.db --db docs/x2.db
python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));p["refusals"]=[];json.dump(p,open(sys.argv[2],"w"))' "$tmp/x2ff.json" "$tmp/x2ffs.json" || exit 2
xp "verify FAIL: a new id outside the prefix, on a plan whose refusals were removed" 1 '^MISMATCH AA-001: a new vehicle id that is not CON-<ASCII digits>; the planner refuses it$' verify --plan "$tmp/x2ffs.json" --vehicle-db docs/x2.db --base-db docs/b.db --target-db docs/tff.db --db docs/x2.db
grep -q '^RESULT: FAIL mode=FAST-FORWARD items=[0-9]* mismatches=1 ' "$tmp/out" && ok "verify: the id outside the prefix is the only mismatch" || bad "verify: the id outside the prefix is the only mismatch" "$(grep -E '^(MISMATCH|RESULT)' "$tmp/out" | tr '\n' '|' | cut -c1-300)"
# round 5, final branch sweep: verify's referent check, asserted (the item an id names after the landing must be
# the item it named in the vehicle; here the landed gamma item gets another created_by, so the alpha text that
# names it is reported, beside gamma's own created_by)
cpdb r_after nref; W update --id "$(id 13)" --db docs/nref.db --location Fixed --created-by Conductor
vn "an id whose landed item is not the item it named in the vehicle" "^MISMATCH $(id 11) description: $(id 11) now names $(id 13), which is not the item $(id 11) named in the vehicle$" nref
# round 5, final branch sweep: a plan map entry that is not a pair is BLIND, never read as its first two parts
python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));p["map"][0]=p["map"][0]+["extra"];json.dump(p,open(sys.argv[2],"w"))' "$tmp/plan.json" "$tmp/plan_trip.json" || exit 2
xp "verify: a plan map entry that is not a pair is BLIND" 3 'plan map entry does not parse' verify --plan "$tmp/plan_trip.json" "${PLAN[@]}" --db docs/r_after.db
# round 5, final branch sweep: verify's two self-checks and two of its text rules, probed on a loaded copy of
# the tool. gp breaks one function or table and runs verify on a plan path that does not exist, so a missing
# self-check shows as the plan's own BLIND message instead of the self-check's. gp and tf exec or eval only
# statements written in this suite (their second argument), never input read from outside it.
gp() { # gp <name> <python statement that breaks the loaded tool m> <pattern>
  python3 -I -B - "$tool" "$2" >"$tmp/out" 2>&1 <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("remint_ids_under_test", sys.argv[1])
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
exec(sys.argv[2])
sys.exit(m.main(["verify", "--plan", "/nonexistent/plan.json", "--vehicle-db", "x", "--base-db", "x", "--target-db", "x", "--db", "x"]))
PY
  rc=$?; check "$1" 3 "$3"
}
gp "verify is BLIND when its comparator misses a needle" 'm.v_compare = lambda *a: None' 'verify control needle failed'
gp "verify is BLIND when its landing units miss a column" 'm.V_UNITS = m.V_UNITS[1:]' "landing units do not partition the item columns: \['atm_id'\]"
tf() { # tf <name> <python expression on the loaded tool m> <expected printed value>
  local got
  got=$(python3 -I -B - "$tool" "$2" 2>&1 <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("remint_ids_under_test", sys.argv[1])
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
print(eval(sys.argv[2]))
PY
)
  same "$1" "$got" "$3"
}
# the register's v_compare id-count entry rests on this: a skeleton has one piece more than its id tokens,
# so equal skeletons carry equally many tokens (the control: v_split does find the two ids of a list)
tf "v_split fact: a skeleton has one piece more than its id tokens" 'all(len(m.v_split(t, "CON")[0]) == len(m.v_split(t, "CON")[1]) + 1 for t in ["", "no ids", "CON-1", "see CON-1 and CON-2", "CON-1..CON-3 x", "a CON-5–CON-7 b CON-9", "CON-1CON-2", "x CON-1-y CON-2", "CON-001..002 CON-3", "b.CON-2"]) and m.v_split("see CON-1 and CON-2", "CON")[1] == ["CON-1", "CON-2"]' "True"
# the register's entry for verify's own-item check_od guard rests on this: check_od appends nothing when
# neither side has a row (the control: a row on one side only is reported, so the instrument sees an append)
tf "check_od fact: no row on either side appends nothing" '(lambda b: (m.check_od("CON-1", None, None, {}, set(), "CON", b), b)[1])([])' "[]"
tf "check_od fact control: a row on one side only is reported" '(lambda b: (m.check_od("CON-1", None, {"since": "x"}, {}, set(), "CON", b), b)[1])([])' "['CON-1 obsolete_details: present in the landed database only']"
tf "verify text rules: a range of moved ids around a foreign id mixes them" 'm.v_text_rules("see CON-5..CON-7", {"CON-5": "CON-20", "CON-6": "CON-21", "CON-7": "CON-22"}, m.v_foreign_numbers(["Foreign ids (other): CON-6"], "CON", []), "CON")' "range 'CON-5..CON-7' mixes foreign and moved ids"
# round 5, final branch sweep: the shared-item loop of verify, one case per branch. dupsql copies an item's row
# as a second row of another representation (created_at and last_modified copied, so two copies are identical)
dupsql="insert into items (atm_id, type, status, severity, title, description, current_location, representation, created_at, last_modified) select atm_id, type, status, severity, title, description, current_location, 'table', created_at, last_modified from items where atm_id=?"
# (a) an item nobody changed is skipped as the planner skips it, even when it has two rows on every side
cpdb b bdup; fx_sql "$repo/docs/bdup.db" "$dupsql" "$(id 8)"
cpdb v vdup; fx_sql "$repo/docs/vdup.db" "$dupsql" "$(id 8)"
cpdb t tdup; fx_sql "$repo/docs/tdup.db" "$dupsql" "$(id 8)"
PD=(--vehicle-db docs/vdup.db --base-db docs/bdup.db --target-db docs/tdup.db)
xp "plan of an unchanged item with two rows on every side" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan "${PD[@]}" --out "$tmp/pdup.json" --repo-root .
cpdb tdup rdup
xp "replay with an unchanged two-row item" 0 '^RESULT: APPLIED ' replay --plan "$tmp/pdup.json" --apply --engine "$wi" --db docs/rdup.db
xp "verify PASS: an unchanged two-row item is skipped, as the planner skips it" 0 '^RESULT: PASS mode=REPLAY' verify --plan "$tmp/pdup.json" "${PD[@]}" --db docs/rdup.db
# (b) a changed vehicle item with two rows is a mismatch of its own, on a plan whose refusals were removed
python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));p["refusals"]=[];json.dump(p,open(sys.argv[2],"w"))' "$tmp/x23.json" "$tmp/x23s.json" || exit 2
xp "verify FAIL: a vehicle item with two rows, on a plan whose refusals were removed" 1 "^MISMATCH $(id 8): not one row in vehicle or base\$" verify --plan "$tmp/x23s.json" --vehicle-db docs/x23.db --base-db docs/b.db --target-db docs/t.db --db docs/r_after.db
grep -q '^RESULT: FAIL mode=REPLAY items=[0-9]* mismatches=1 ' "$tmp/out" && ok "verify: the two-row item is the only mismatch" || bad "verify: the two-row item is the only mismatch" "$(grep -E '^(MISMATCH|RESULT)' "$tmp/out" | tr '\n' '|' | cut -c1-300)"
# (c) an item whose only vehicle change is last_modified is not replayed, so it must land as the target has it
cpdb t r24
xp "replay of a vehicle whose only change is a last_modified" 0 '^RESULT: APPLIED ' replay --plan "$tmp/x24.json" --apply --engine "$wi" --db docs/r24.db
xp "verify of a vehicle whose only change is a last_modified" 0 '^RESULT: PASS mode=REPLAY' verify --plan "$tmp/x24.json" --vehicle-db docs/x24.db --base-db docs/b.db --target-db docs/t.db --db docs/r24.db
cpdb r24 n24; fx_sql "$repo/docs/n24.db" "update items set last_modified='2026-11-13 13:00:00' where atm_id=?" "$(id 8)"
xp "verify FAIL: the landing wrote to an item it was not to touch" 1 "^MISMATCH $(id 8): an item the landing must not touch differs from the target\$" verify --plan "$tmp/x24.json" --vehicle-db docs/x24.db --base-db docs/b.db --target-db docs/t.db --db docs/n24.db
# (d) a replayed item must land as one row
cpdb r_after nrow; fx_sql "$repo/docs/nrow.db" "$dupsql" "$(id 1)"
vn "a replayed item that landed as two rows" "^MISMATCH $(id 1): not one landed row\$" nrow
# (e) a column outside the rewrite set is compared as written, never under the map: both sides changed the
# assignee to texts that are equal only under the map. The planner refuses the vehicle's text (as in x32) and
# writes no plan, so the case forges one: the main plan with the sha256 of these three databases. Its landing
# keeps the target's assignee, and verify must still report two changes of that column with no --resolve
cpdb v vas; W update --id "$(id 8)" --db docs/vas.db --location Issues --assigned-to "Owner of $(id 13)"
cpdb t tas; W update --id "$(id 8)" --db docs/tas.db --location Issues --assigned-to "Owner of $(id 15)"
PA=(--vehicle-db docs/vas.db --base-db docs/b.db --target-db docs/tas.db)
xp "plan: both sides changed the assignee to texts equal only under the map" 1 "^REFUSED: base $(id 8) assigned_to: 'Owner of $(id 13)' names an id the map moves" plan "${PA[@]}" --out "$tmp/pas.json"
[ ! -e "$tmp/pas.json" ] && ok "plan: a refused plan writes no plan file" || bad "plan: a refused plan writes no plan file" "$tmp/pas.json exists"
python3 -I -c 'import hashlib,json,sys
p = json.load(open(sys.argv[1]))
p["sha256"] = {k: hashlib.sha256(open(f, "rb").read()).hexdigest() for k, f in zip(("vehicle", "base", "target"), sys.argv[3:6])}
json.dump(p, open(sys.argv[2], "w"))' "$tmp/plan.json" "$tmp/pas_f.json" "$repo/docs/vas.db" "$repo/docs/b.db" "$repo/docs/tas.db" || exit 2
cpdb tas ras
xp "replay of the forged assignee plan" 0 '^RESULT: APPLIED ' replay --plan "$tmp/pas_f.json" --apply --engine "$wi" --db docs/ras.db
xp "verify FAIL: a column outside the rewrite set equal only under the map is two changes" 1 "^MISMATCH $(id 8): both changed assigned_to, and the plan has no --resolve for it\$" verify --plan "$tmp/pas_f.json" "${PA[@]}" --db docs/ras.db
# (f) a target change of obsolete_details is named when verify leaves body_md uncompared: the vehicle changed
# the severity of an obsolete item and the target its obsolete_details, decided by --resolve vehicle
cpdb b vod; W update --id "$(id 6)" --db docs/vod.db --location Fixed --severity High
cpdb t tod; W obsolete-details "$(id 6)" --db docs/tod.db --since 2026-11-12 --reason superseded-by-later-mandate --superseding none --evidence "$EV"
POD=(--vehicle-db docs/vod.db --base-db docs/b.db --target-db docs/tod.db)
xp "plan: a vehicle change and a target obsolete_details change of one item is a conflict" 1 "^CONFLICT $(id 6): a lifecycle change on one side and a change on the other " plan "${POD[@]}" --out "$tmp/pod.json"
xp "plan: --resolve vehicle of the obsolete_details conflict" 0 '^RESULT: PLAN mode=REPLAY own=0 ' plan "${POD[@]}" --out "$tmp/podv.json" --resolve "$(id 6)=vehicle"
cpdb tod rod
xp "replay of the obsolete_details --resolve vehicle" 0 '^RESULT: APPLIED ' replay --plan "$tmp/podv.json" --apply --engine "$wi" --db docs/rod.db
xp "verify of the obsolete_details --resolve vehicle" 0 '^RESULT: PASS mode=REPLAY' verify --plan "$tmp/podv.json" "${POD[@]}" --db docs/rod.db
grep -qF "KNOWN $(id 6): body_md not compared (the target also changed the item: obsolete_details)" "$tmp/out" && ok "verify names the target's obsolete_details change" || bad "verify names the target's obsolete_details change" "$(grep -E '^(KNOWN|MISMATCH)' "$tmp/out" | tr '\n' '|' | cut -c1-300)"
# (g) a base item's obsolete_details the vehicle changed must land as the vehicle wrote it
cpdb r_after nod5; W obsolete-details "$(id 5)" --db docs/nod5.db --since 2026-11-01 --reason not-reproducible --superseding none --evidence "$EV"
vn "a base item's obsolete_details field" "^MISMATCH $(id 5) obsolete_details.since: landed '2026-11-01', vehicle '2026-11-12'" nod5
# (h) an item the landing does not replay keeps the target's obsolete_details row (here a row added to an
# item that has none, with the item row itself unchanged)
cpdb r_after nodu; fx_sql "$repo/docs/nodu.db" "insert into obsolete_details (atm_id, since, reason, superseding_item, triple_check_evidence) values (?, '2026-11-13', 'duplicate-of', 'none', 'docs/qa/x.txt')" "$(id 4)"
vn "an obsolete_details row added to an untouched item" "^MISMATCH $(id 4): obsolete_details differs from the target on an untouched item\$" nodu
# (i) an own item's created_at is reported only when it differs from the vehicle's (here the landed value is
# set to the vehicle's, so verify passes without that KNOWN line)
ca=$(q "$repo/docs/v.db" 'select created_at from items where atm_id=?' "$(id 11)")
cpdb r_after nca; fx_sql "$repo/docs/nca.db" "update items set created_at=? where atm_id=?" "$ca" "$(id 13)"
xp "verify of an own item whose created_at equals the vehicle's" 0 '^RESULT: PASS mode=REPLAY' verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/nca.db
grep -q "^KNOWN $(id 13) created_at:" "$tmp/out" && bad "no created_at KNOWN line for an own item whose created_at was carried" "$(grep "^KNOWN $(id 13)" "$tmp/out" | tr '\n' '|')" || ok "no created_at KNOWN line for an own item whose created_at was carried"
grep -q "^KNOWN $(id 14) created_at: replay time " "$tmp/out" && ok "the created_at KNOWN line of another own item stays" || bad "the created_at KNOWN line of another own item stays" "$(grep '^KNOWN ' "$tmp/out" | tr '\n' '|' | cut -c1-300)"
# (j) an own item's obsolete_details row present on one side only names the side that has it
odsql="insert into obsolete_details (atm_id, since, reason, superseding_item, triple_check_evidence) values (?, '2026-11-13', 'duplicate-of', 'none', 'docs/qa/x.txt')"
cpdb r_after nodl; fx_sql "$repo/docs/nodl.db" "$odsql" "$(id 11)"
vn "an obsolete_details row on a landed own item that has none in the vehicle" "^MISMATCH $(id 11) obsolete_details: present in the landed database only\$" nodl
cpdb r_after nodv; fx_sql "$repo/docs/nodv.db" "delete from obsolete_details where atm_id=?" "$(id 13)"
vn "an own item's obsolete_details row missing from the landing" "^MISMATCH $(id 13) obsolete_details: present in the vehicle only\$" nodv
# (k) verify is BLIND when the landing touched every target item, because its control comparison of the untouched
# items would see nothing: a one-item tracker, built by engine commands from empty Markdown
: >"$repo/docs/emptyI.md"; : >"$repo/docs/emptyF.md"
W sync md-to-db --db docs/b1.db --issues docs/emptyI.md --fixed docs/emptyF.md
W add Task Low --db docs/b1.db --id "$(id 1)" --title "Remint one-item tracker item" --description "$D The only item of a one-item tracker." --created-by Claude
cpdb b1 v1; cpdb b1 t1
W update --id "$(id 1)" --db docs/v1.db --location Issues --description "$D The only item of a one-item tracker, changed by the vehicle."
P1=(--vehicle-db docs/v1.db --base-db docs/b1.db --target-db docs/t1.db)
xp "plan of a one-item tracker, --no-fast-forward" 0 '^RESULT: PLAN mode=REPLAY own=0 base_changes=1 steps=1 ' plan "${P1[@]}" --out "$tmp/p1.json" --no-fast-forward
cpdb t1 r1
xp "replay of the one-item tracker" 0 '^RESULT: APPLIED ' replay --plan "$tmp/p1.json" --apply --engine "$wi" --db docs/r1.db
xp "verify is BLIND when the landing touched every target item" 3 '^BLIND: no untouched target item to compare' verify --plan "$tmp/p1.json" "${P1[@]}" --db docs/r1.db
# (l) a vehicle that removed a base item's obsolete_details row (no engine command removes one; a raw edit of a
# scratch copy) is refused: the planner used to write no step for it, so the landing kept the row the vehicle had
# removed, and only verify noticed (round 5, found while killing the final sweep's check_od survivors)
cpdb v vrm; fx_sql "$repo/docs/vrm.db" "delete from obsolete_details where atm_id=?" "$(id 5)"
pr "the vehicle removed a base item's obsolete_details row" "^REFUSED $(id 5): the vehicle removed the obsolete_details row; no engine command removes one\$" vrm
# (m) both sides removed the row, decided by --resolve vehicle: on the plan with its refusals removed, verify has
# no row on either side to compare, so it reports no obsolete_details mismatch for the item; its one mismatch is
# the vehicle's closure row of the item, which the stripped plan has no step for
cpdb t trm; fx_sql "$repo/docs/trm.db" "delete from obsolete_details where atm_id=?" "$(id 5)"
PRM=(--vehicle-db docs/vrm.db --base-db docs/b.db --target-db docs/trm.db)
xp "plan: both sides removed the obsolete_details row (refused)" 1 "^REFUSED $(id 5): the vehicle removed the obsolete_details row" plan "${PRM[@]}" --out "$tmp/prm.json" --resolve "$(id 5)=vehicle"
python3 -I -c 'import json,sys;p=json.load(open(sys.argv[1]));p["refusals"]=[];json.dump(p,open(sys.argv[2],"w"))' "$tmp/prm.json" "$tmp/prm_s.json" || exit 2
cpdb trm rrm
xp "replay of the removed-row plan whose refusals were removed" 0 '^RESULT: APPLIED ' replay --plan "$tmp/prm_s.json" --apply --engine "$wi" --db docs/rrm.db
xp "verify of the stripped removed-row plan: the closure row has no step" 1 "^MISMATCH $(id 5): the vehicle closed $(id 5) but the landed history has no closure row\$" verify --plan "$tmp/prm_s.json" "${PRM[@]}" --db docs/rrm.db
grep -qE '^RESULT: FAIL mode=REPLAY items=10 mismatches=1 ' "$tmp/out" && ok "verify: the closure row is the only mismatch of the stripped plan" || bad "verify: the closure row is the only mismatch of the stripped plan" "$(grep -E '^(MISMATCH|RESULT)' "$tmp/out" | tr '\n' '|' | cut -c1-300)"
grep -q "^MISMATCH $(id 5) obsolete_details" "$tmp/out" && bad "verify: no obsolete_details row on either side is nothing to compare" "$(grep "^MISMATCH $(id 5)" "$tmp/out" | tr '\n' '|')" || ok "verify: no obsolete_details row on either side is nothing to compare"
# (n) only the last Reopened row of the landed history is compared with the vehicle's, never the last row of any
# kind: a reopened own item changed after the landing (one more history row) fails on the change alone
cpdb r_after nro; W update --id "$(id 14)" --db docs/nro.db --location Issues --assigned-to Reviewer
xp "verify FAIL: a reopened own item changed after the landing" 1 "^MISMATCH $(id 14) assigned_to: landed 'Reviewer', expected ''\$" verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/nro.db
grep -q "^MISMATCH $(id 14): the last Reopened row does not match the vehicle's" "$tmp/out" && bad "verify: a later history row is not the Reopened row" "$(grep "^MISMATCH $(id 14)" "$tmp/out" | tr '\n' '|')" || ok "verify: a later history row is not the Reopened row"
# (o) the closed own item lost its closure row in the landing: verify names the missing closure
cpdb r_after ncl; fx_sql "$repo/docs/ncl.db" "delete from item_history where atm_id=? and event_type='Obsolete'" "$(id 13)"
vn "a closed own item with no landed closure row" "^MISMATCH $(id 13): the vehicle closed $(id 11) but the landed history has no closure row\$" ncl
# (p) a landed closure row with no evidence is not cited by any vehicle closure row (the vehicle's Opened row,
# which cites no evidence either, is not a closure row)
cpdb r_after nce; fx_sql "$repo/docs/nce.db" "update item_history set evidence_path='' where atm_id=? and event_type='Obsolete'" "$(id 13)"
vn "a landed closure row with no evidence" "^MISMATCH $(id 13): landed closure row cites '', which no vehicle closure row of $(id 11) cites\$" nce
# (q) the lifecycle row count compares closure and Reopened rows only: the landing has as many as the vehicle, so
# verify writes no M-14 line for it (every other history row of the item is left out of the count)
xp "verify of the landing, for its KNOWN lines" 0 '^RESULT: PASS mode=REPLAY items=10 mismatches=0 ' verify --plan "$tmp/plan.json" "${PLAN[@]}" --db docs/r_after.db
same "verify: no lifecycle-count KNOWN line when the counts agree" "$(grep -c 'lifecycle history rows' "$tmp/out")" "0"
# (r) an own item the vehicle closed, reopened and closed again lands with fewer lifecycle rows than the
# vehicle wrote (history is not carried, M-14): verify passes and says so in a KNOWN line
cpdb v vkn; W close "$(id 13)" --db docs/vkn.db --status completed --evidence "$EV"
W reopen --id "$(id 13)" --db docs/vkn.db --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
W close "$(id 13)" --db docs/vkn.db --status completed --evidence "$EV"
PKN=(--vehicle-db docs/vkn.db --base-db docs/b.db --target-db docs/t.db)
xp "plan of an own item closed, reopened and closed again" 0 '^RESULT: PLAN mode=REPLAY own=5 ' plan "${PKN[@]}" --out "$tmp/pkn.json" --repo-root .
cpdb t rkn
xp "replay of the twice-closed own item" 0 '^RESULT: APPLIED ' replay --plan "$tmp/pkn.json" --apply --engine "$wi" --db docs/rkn.db
xp "verify of the twice-closed own item" 0 '^RESULT: PASS mode=REPLAY' verify --plan "$tmp/pkn.json" "${PKN[@]}" --db docs/rkn.db
grep -qE "^KNOWN $(id 15): lifecycle history rows vehicle 3, landed [0-9]+ \(history is not carried; M-14\)\$" "$tmp/out" && ok "verify: a lifecycle-count KNOWN line when the counts differ" || bad "verify: a lifecycle-count KNOWN line when the counts differ" "$(grep -E "^(KNOWN|MISMATCH) $(id 15)" "$tmp/out" | tr '\n' '|' | cut -c1-300)"
same "the real database is untouched" "$(sha256sum "$realdb" | cut -d' ' -f1)" "$real_sha"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
