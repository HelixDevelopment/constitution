#!/usr/bin/env bash
# realtracker_check.sh — CON-456 round 4: round trip of a COPY of the real
# tracker database through the engine (validate, export equal to the committed
# Markdown, two md-to-db cycles, side tables unchanged).
#
# Usage: realtracker_check.sh <engine-binary> <repo-root> <out-dir>
#   Copies <repo-root>/docs/workable_items.db into <out-dir>; never writes the
#   original. <out-dir> must not exist (created here).
# Output: <out-dir>/summary.txt; exit 0 when every check holds, 1 otherwise.
set -u
# validate resolves recorded evidence paths against the working directory
# (review finding 7, filed as a follow-up), so every engine call runs from the
# repository root.
BIN="${1:?engine binary}"; ROOT="${2:?repo root}"; OUT="${3:?out dir}"
[ -e "$OUT" ] && { echo "out dir exists: $OUT" >&2; exit 64; }
mkdir -p "$OUT" || exit 1
OUT=$(cd "$OUT" && pwd); BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
cd "$ROOT" || exit 1
S="$OUT/summary.txt"; : >"$S"
FAILS=0
say() { printf '%s\n' "$*" | tee -a "$S"; }
chk() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then say "OK   $name"; else say "FAIL $name"; FAILS=$((FAILS + 1)); fi; }

cp -- "$ROOT/docs/workable_items.db" "$OUT/db0.sqlite"
say "engine sha256: $(sha256sum "$BIN" | cut -d' ' -f1)"
say "db0 sha256: $(sha256sum "$OUT/db0.sqlite" | cut -d' ' -f1)"
say "db0 items: $(sqlite3 "$OUT/db0.sqlite" 'select count(*) from items')"
chk "validate db0" "$BIN" validate --db "$OUT/db0.sqlite"
chk "diff db0 vs committed Issues.md + Fixed.md" "$BIN" diff --db "$OUT/db0.sqlite" --issues "$ROOT/docs/Issues.md" --fixed "$ROOT/docs/Fixed.md"
chk "export 1" "$BIN" sync db-to-md --db "$OUT/db0.sqlite" --out-issues "$OUT/I1.md" --out-fixed "$OUT/F1.md"
chk "export 1 Issues == committed" cmp -s "$OUT/I1.md" "$ROOT/docs/Issues.md"
chk "export 1 Fixed == committed" cmp -s "$OUT/F1.md" "$ROOT/docs/Fixed.md"

side() { sqlite3 "$1" "select 'OBD|'||atm_id||'|'||what||'|'||why_exhausted_alternatives||'|'||unblock_condition||'|'||coalesce(who,'') from operator_block_details order by atm_id; select 'OD|'||atm_id||'|'||since||'|'||reason||'|'||superseding_item||'|'||triple_check_evidence from obsolete_details order by atm_id;" 2>&1; }
side "$OUT/db0.sqlite" >"$OUT/side0.txt"
prev="$OUT/db0.sqlite"; I="$OUT/I1.md"; F="$OUT/F1.md"
for n in 1 2; do
	cp -- "$prev" "$OUT/db$n.sqlite"
	chk "md-to-db cycle $n" "$BIN" sync md-to-db --db "$OUT/db$n.sqlite" --issues "$I" --fixed "$F"
	say "db$n items: $(sqlite3 "$OUT/db$n.sqlite" 'select count(*) from items')"
	chk "validate db$n" "$BIN" validate --db "$OUT/db$n.sqlite"
	side "$OUT/db$n.sqlite" >"$OUT/side$n.txt"
	chk "side tables db0 == db$n (operator_block_details, obsolete_details)" cmp -s "$OUT/side0.txt" "$OUT/side$n.txt"
	chk "export $((n + 1))" "$BIN" sync db-to-md --db "$OUT/db$n.sqlite" --out-issues "$OUT/I$((n + 1)).md" --out-fixed "$OUT/F$((n + 1)).md"
	chk "export $((n + 1)) Issues == export 1" cmp -s "$OUT/I$((n + 1)).md" "$OUT/I1.md"
	chk "export $((n + 1)) Fixed == export 1" cmp -s "$OUT/F$((n + 1)).md" "$OUT/F1.md"
	prev="$OUT/db$n.sqlite"; I="$OUT/I$((n + 1)).md"; F="$OUT/F$((n + 1)).md"
done
say "side rows: $(wc -l <"$OUT/side0.txt") (control needle: OBD rows $(grep -c '^OBD|' "$OUT/side0.txt"), OD rows $(grep -c '^OD|' "$OUT/side0.txt"))"
for n in 1 2; do
	say "body changed db$((n - 1))->db$n: $(sqlite3 "$OUT/db$n.sqlite" "attach '$OUT/db$((n - 1)).sqlite' as o; select count(*) from items i join o.items p using(atm_id) where i.body_md<>p.body_md")"
	say "description changed db$((n - 1))->db$n: $(sqlite3 "$OUT/db$n.sqlite" "attach '$OUT/db$((n - 1)).sqlite' as o; select count(*) from items i join o.items p using(atm_id) where i.description<>p.description")"
	say "states changed db$((n - 1))->db$n: $(sqlite3 "$OUT/db$n.sqlite" "attach '$OUT/db$((n - 1)).sqlite' as o; select count(*) from items i join o.items p using(atm_id) where i.reproduction_state<>p.reproduction_state or i.investigation_state<>p.investigation_state")"
done
say "FAILS=$FAILS"
[ "$FAILS" = 0 ]
