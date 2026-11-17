#!/usr/bin/env bash
# probe_legacy_bug_on_main.sh MAIN_BIN R3_BIN OUT - CON-456 round 3 scratch probe.
# A tracker that holds a Bug minted by the MAIN engine with the old
# report_item.sh template (the two record lines as description text): what
# does the round-3 engine do with it? Measures validate, md-to-db of the
# unchanged export, and the effect of the one operator edit that fixes it.
set -u
MAIN="${1:?main bin}"; R3="${2:?r3 bin}"; OUT="${3:?out}"
case "$OUT" in /mnt/DATA1TB/claude-work/scratch/*) : ;; *) echo "refusing: OUT outside scratch" >&2; exit 64 ;; esac
mkdir -p "$OUT"; SUM="$OUT/summary.txt"; : >"$SUM"
log() { printf '%s\n' "$*" | tee -a "$SUM"; }
DB="$OUT/db.sqlite"; : >/dev/null
DESC=$(printf '%s\n\n%s\n%s' "A legacy-template Bug minted by the main engine, long enough for the floor." \
	"**Reproduction:** none — UNREPRODUCED (§11.4.292)" "**Investigation:** not-started (§11.4.294)")
HELIX_RELEASE_PREFIX=con "$MAIN" add Bug Medium --db "$DB" --id CON-930 --title "legacy template bug" --description "$DESC" >"$OUT/add_main.out" 2>&1
log "main add rc=$?"
log "stored states: $(sqlite3 "$DB" "select reproduction_state||'|'||investigation_state from items where atm_id='CON-930'")"
"$R3" validate --db "$DB" >"$OUT/validate_r3.out" 2>&1; log "r3 validate rc=$? ($(tail -1 "$OUT/validate_r3.out"))"
"$R3" sync db-to-md --db "$DB" --out-issues "$OUT/I.md" --out-fixed "$OUT/F.md" >"$OUT/x.out" 2>&1; log "r3 export rc=$?"
cp "$DB" "$OUT/rt.sqlite"
"$R3" sync md-to-db --db "$OUT/rt.sqlite" --issues "$OUT/I.md" --fixed "$OUT/F.md" >"$OUT/m.out" 2>&1; log "r3 md-to-db of the unchanged export rc=$?"
sed 's/^/   /' "$OUT/m.out" | head -8 | tee -a "$SUM"
log "db unchanged by the refused md-to-db: $(cmp -s "$DB" "$OUT/rt.sqlite" && echo yes || echo no)"
cp "$DB" "$OUT/main_rt.sqlite"
"$MAIN" sync md-to-db --db "$OUT/main_rt.sqlite" --issues "$OUT/I.md" --fixed "$OUT/F.md" >"$OUT/m_main.out" 2>&1; log "main md-to-db of the same export rc=$?"
log "main md-to-db stored states: $(sqlite3 "$OUT/main_rt.sqlite" "select reproduction_state||'|'||investigation_state from items where atm_id='CON-930'")"
# The operator edit: drop the ` (§11.4.292)` tail so the line is a canonical record.
sed 's/^\*\*Reproduction:\*\* none — UNREPRODUCED (§11.4.292)$/**Reproduction:** none — UNREPRODUCED/' "$OUT/I.md" >"$OUT/I_edit.md"
log "edited lines: $(diff "$OUT/I.md" "$OUT/I_edit.md" | grep -c '^>')"
cp "$DB" "$OUT/rt_edit.sqlite"
"$R3" sync md-to-db --db "$OUT/rt_edit.sqlite" --issues "$OUT/I_edit.md" --fixed "$OUT/F.md" >"$OUT/m_edit.out" 2>&1; log "r3 md-to-db of the edited export rc=$?"
sed 's/^/   /' "$OUT/m_edit.out" | head -4 | tee -a "$SUM"
log "after the edit, stored states: $(sqlite3 "$OUT/rt_edit.sqlite" "select reproduction_state||'|'||investigation_state from items where atm_id='CON-930'")"
"$R3" validate --db "$OUT/rt_edit.sqlite" >"$OUT/validate_edit.out" 2>&1; log "r3 validate after the edit rc=$?"
