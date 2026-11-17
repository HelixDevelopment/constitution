#!/usr/bin/env bash
# report_item_e2e.sh BIN TREE OUT - CON-456 round 3 end-to-end run of
# scripts/reporting/report_item.sh (review F-A). Scratch instrument.
#
# TREE is a repository tree holding scripts/reporting/report_item.sh and
# docs/workable_items.db. Every run works on its OWN copy of that database
# under OUT; TREE is never written. Paths covered:
#   bug_fallback   Bug, intake-match unavailable (a dispatch shim makes the
#                  `intake-match` verb exit 1; every other verb is the real BIN)
#   bug_matcher    Bug through the real intake-match --apply
#   task           Task (direct add, no states)
#   issue_auto     --kind issue --autonomous (Task default)
#   dry_run        Bug --dry-run (nothing written: database bytes unchanged)
# For each run: exit code, the minted id, its state columns, the body record
# lines, validate, and two db-to-md -> md-to-db cycles on a further copy.
set -u
BIN="${1:?bin}"; TREE="${2:?tree}"; OUT="${3:?out}"
case "$OUT" in /mnt/DATA1TB/claude-work/scratch/*) : ;; *) echo "refusing: OUT outside scratch" >&2; exit 64 ;; esac
mkdir -p "$OUT"
SUM="$OUT/summary.txt"; : >"$SUM"
log() { printf '%s\n' "$*" | tee -a "$SUM"; }
log "engine sha256: $(sha256sum "$BIN" | cut -c1-64)"
log "report_item.sh sha256: $(sha256sum "$TREE/scripts/reporting/report_item.sh" | cut -c1-64)"
log "source db sha256: $(sha256sum "$TREE/docs/workable_items.db" | cut -c1-64)"

SHIM="$OUT/shim_no_intake_match.sh"
cat >"$SHIM" <<EOF
#!/usr/bin/env bash
# Dispatch shim: makes intake-match unavailable, runs every other verb on the real engine.
if [ "\${1:-}" = "intake-match" ]; then echo "shim: intake-match unavailable" >&2; exit 1; fi
exec "$BIN" "\$@"
EOF
chmod 0755 "$SHIM"

run_case() { # name engine kind extra...
	local name="$1" eng="$2" kind="$3"; shift 3
	local d="$OUT/$name"; mkdir -p "$d/ev"
	cp "$TREE/docs/workable_items.db" "$d/db.sqlite"
	local before; before=$(sha256sum "$d/db.sqlite" | cut -c1-64)
	local n0; n0=$(sqlite3 "$d/db.sqlite" 'select count(*) from items;')
	cat >"$d/reporting.yaml" <<EOF
schema_version: 1
db: $d/db.sqlite
id_prefix: CON
default_severity: Medium
default_reported_by: Operator
sync_command: ""
evidence_dir: $d/ev
trackers: []
EOF
	( cd "$TREE" && HELIX_REPORTING_CONFIG="$d/reporting.yaml" WORKABLE_ITEMS_BIN="$eng" \
		bash scripts/reporting/report_item.sh --kind "$kind" --no-sync --no-tracker "$@" ) >"$d/run.out" 2>"$d/run.err"
	local rc=$?
	local after; after=$(sha256sum "$d/db.sqlite" | cut -c1-64)
	local n1; n1=$(sqlite3 "$d/db.sqlite" 'select count(*) from items;')
	local id; id=$(sqlite3 "$d/db.sqlite" "select atm_id from items where atm_id not in (select atm_id from items limit 0) order by rowid desc limit 1;")
	log "== $name: rc=$rc items $n0 -> $n1 db_changed=$([ "$before" = "$after" ] && echo no || echo yes) last_id=$id"
	grep -h 'INTAKE-MATCH UNAVAILABLE\|CREATED\|RECURRENCE\|DRY-RUN' "$d/run.out" "$d/run.err" | sed 's/^/   /' | tee -a "$SUM" >/dev/null
	if [ "$n1" != "$n0" ]; then
		sqlite3 "$d/db.sqlite" "select atm_id||' type='||type||' repro='||reproduction_state||' inv='||investigation_state||' repro_by='||coalesce(reproduction_updated_by,'')||' inv_by='||coalesce(investigation_updated_by,'') from items order by rowid desc limit 1;" | sed 's/^/   /' | tee -a "$SUM"
		sqlite3 "$d/db.sqlite" "select body_md from items order by rowid desc limit 1;" >"$d/new_body.md"
		grep -n '^\*\*Reproduction:\*\*\|^\*\*Investigation:\*\*' "$d/new_body.md" | sed 's/^/   body: /' | tee -a "$SUM"
		sqlite3 "$d/db.sqlite" "select description from items order by rowid desc limit 1;" >"$d/new_desc.md"
		log "   description carries a record line: $(grep -c '^\*\*Reproduction:\*\*\|^\*\*Investigation:\*\*' "$d/new_desc.md")"
		( cd "$TREE" && "$BIN" validate --db "$d/db.sqlite" ) >"$d/validate.out" 2>&1; log "   validate rc=$?"
		cp "$d/db.sqlite" "$d/c1.sqlite"
		( cd "$TREE" && "$BIN" sync db-to-md --db "$d/c1.sqlite" --out-issues "$d/I1.md" --out-fixed "$d/F1.md" ) >"$d/x1.out" 2>&1; log "   export 1 rc=$?"
		( cd "$TREE" && "$BIN" sync md-to-db --db "$d/c1.sqlite" --issues "$d/I1.md" --fixed "$d/F1.md" ) >"$d/m1.out" 2>&1; log "   md-to-db 1 rc=$?"
		cp "$d/c1.sqlite" "$d/c2.sqlite"
		( cd "$TREE" && "$BIN" sync db-to-md --db "$d/c2.sqlite" --out-issues "$d/I2.md" --out-fixed "$d/F2.md" ) >"$d/x2.out" 2>&1; log "   export 2 rc=$?"
		( cd "$TREE" && "$BIN" sync md-to-db --db "$d/c2.sqlite" --issues "$d/I2.md" --fixed "$d/F2.md" ) >"$d/m2.out" 2>&1; log "   md-to-db 2 rc=$?"
		local q="select reproduction_state||'|'||investigation_state||'|'||coalesce(reproduction_updated_at,'')||'|'||coalesce(reproduction_updated_by,'')||'|'||coalesce(investigation_updated_at,'')||'|'||coalesce(investigation_updated_by,'')||'|'||body_md from items where atm_id='$id';"
		local s0 s1 s2
		s0=$(sqlite3 "$d/db.sqlite" "$q" | sha256sum | cut -c1-16); s1=$(sqlite3 "$d/c1.sqlite" "$q" | sha256sum | cut -c1-16); s2=$(sqlite3 "$d/c2.sqlite" "$q" | sha256sum | cut -c1-16)
		log "   new item states+body sha16: minted=$s0 cycle1=$s1 cycle2=$s2 same=$([ "$s0" = "$s1" ] && [ "$s1" = "$s2" ] && echo yes || echo NO)"
		( cd "$TREE" && "$BIN" validate --db "$d/c2.sqlite" ) >"$d/validate2.out" 2>&1; log "   validate after two cycles rc=$?"
	fi
}

REPORT_BUG="CON-456 r3 e2e: the reporting directive minted a Bug and the export then failed when the operator pressed the sync button."
run_case bug_fallback "$SHIM" bug --title "r3 e2e fallback bug" --report "$REPORT_BUG"
run_case bug_matcher "$BIN" bug --title "r3 e2e matcher bug" --report "$REPORT_BUG"
run_case task "$BIN" task --title "r3 e2e task" --report "CON-456 r3 e2e: a task report for the round-3 end-to-end run of report_item.sh."
run_case issue_auto "$BIN" issue --autonomous --title "r3 e2e issue" --report "CON-456 r3 e2e: an issue report classified with the documented Task default."
run_case dry_run "$BIN" bug --dry-run --title "r3 e2e dry run" --report "$REPORT_BUG"
log "dry run output carries the preview records: $(grep -c '^\*\*Reproduction:\*\* none — UNREPRODUCED — updated\|^\*\*Investigation:\*\* not-started — updated' "$OUT/dry_run/run.out")"
