#!/usr/bin/env bash
# test_report_item_bug_states.sh — behavioural test of the state flags
# scripts/reporting/report_item.sh passes to `workable-items add` for a Bug
# (CON-456 round 4, review mutant RR6).
#
# What it proves: a Bug minted through the reporting directive's FALLBACK path
# (intake-match unavailable) is stored with reproduction_state UNREPRODUCED and
# investigation_state not-started, the body carries the two record lines the
# engine renders from those columns, and the description carries no record
# text. A Task is minted with both states UNSET (the flags are Bug-only).
#
# Control (section 11.4.273): the same run on a copy of report_item.sh with the
# operative `set -- --reproduction-state …` line deleted (mutant RR6) MUST mint
# the Bug UNSET. If it does not, the test cannot see the flags and reports BLIND.
#
# Usage: test_report_item_bug_states.sh [--bin <workable-items binary>]
#   default binary: scripts/workable-items/bin/workable-items of this checkout.
# Exit: 0 PASS, 1 FAIL, 2 BLIND (control did not separate), 77 SKIP (no sqlite3).
# Writes only under a mktemp -d directory, removed on exit.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$ROOT/scripts/workable-items/bin/workable-items"
while [ $# -gt 0 ]; do
	case "$1" in
	--bin) BIN="${2:?--bin needs a path}"; shift 2 ;;
	-h | --help) sed -n '2,20p' "$0"; exit 0 ;;
	*) echo "unknown argument: $1" >&2; exit 64 ;;
	esac
done
command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: sqlite3 not installed"; exit 77; }
[ -x "$BIN" ] || { echo "FAIL: engine binary not executable: $BIN"; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ri_states.XXXXXX") || exit 1
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && rm -rf -- "${WORK:?}"; }
trap cleanup EXIT

SHIM="$WORK/shim.sh"
cat >"$SHIM" <<EOF
#!/usr/bin/env bash
# intake-match unavailable; every other verb runs on the real engine.
if [ "\${1:-}" = "intake-match" ]; then echo "shim: intake-match unavailable" >&2; exit 1; fi
exec "$BIN" "\$@"
EOF
chmod 0755 "$SHIM"

NPASS=0; NFAIL=0
ok() { NPASS=$((NPASS + 1)); printf 'PASS  %s\n' "$*"; }
no() { NFAIL=$((NFAIL + 1)); printf 'FAIL  %s\n' "$*"; }

# mint <name> <report_item.sh> <kind> -> prints "repro|inv|desc_has_record|body_records" of the new item
mint() {
	local name="$1" script="$2" kind="$3" d="$WORK/$1"
	mkdir -p "$d/ev"
	"$BIN" add Task Low --db "$d/db.sqlite" --id SEED-001 --title "seed item for the states test" \
		--description "seed item so that the reporting directive finds an existing database" >/dev/null 2>&1 || return 1
	cat >"$d/reporting.yaml" <<EOF
schema_version: 1
db: $d/db.sqlite
id_prefix: RIS
default_severity: Medium
default_reported_by: Operator
sync_command: ""
evidence_dir: $d/ev
trackers: []
EOF
	(cd "$ROOT" && HELIX_REPORTING_CONFIG="$d/reporting.yaml" WORKABLE_ITEMS_BIN="$SHIM" \
		bash "$script" --kind "$kind" --no-sync --no-tracker --title "states test $name" \
		--report "The reporting directive states test: a report long enough for the description floor of the engine.") \
		>"$d/run.out" 2>&1 || return 1
	sqlite3 "$d/db.sqlite" "select coalesce(reproduction_state,'')||'|'||coalesce(investigation_state,'')||'|'||
		(instr(description,'**Reproduction:**')>0 or instr(description,'**Investigation:**')>0)||'|'||
		((instr(body_md,char(10)||'**Reproduction:** none — UNREPRODUCED')>0)+(instr(body_md,char(10)||'**Investigation:** not-started')>0))
		from items where atm_id<>'SEED-001' order by rowid desc limit 1;"
}

TPL="$ROOT/scripts/reporting/report_item.sh"
got=$(mint bug "$TPL" bug) || { no "fallback Bug mint ran (see run.out)"; got=""; }
[ "$got" = "UNREPRODUCED|not-started|0|2" ] && ok "fallback Bug: states UNREPRODUCED/not-started, records in the body, none in the description" \
	|| no "fallback Bug: got '$got', want 'UNREPRODUCED|not-started|0|2'"
got=$(mint task "$TPL" task) || { no "Task mint ran"; got=""; }
[ "$got" = "UNSET|UNSET|0|0" ] && ok "Task: both states UNSET, no record lines" || no "Task: got '$got', want 'UNSET|UNSET|0|0'"

# Control: mutant RR6 (the operative flag line deleted) must mint the Bug UNSET.
MUT="$WORK/report_item_rr6.sh"
grep -v -E '^[[:space:]]*set -- --reproduction-state UNREPRODUCED' "$TPL" | grep -v -E '^[[:space:]]*--states-updated-by "\$REPORTED_BY"' >"$MUT"
if cmp -s "$TPL" "$MUT"; then echo "BLIND: the RR6 control mutation changed nothing"; exit 2; fi
got=$(mint rr6 "$MUT" bug) || got="mint-failed"
case "$got" in
UNSET\|UNSET\|*) ok "control: mutant RR6 mints the Bug UNSET (the test sees the flags)" ;;
*) echo "BLIND: mutant RR6 minted '$got'; the test does not separate it"; exit 2 ;;
esac

echo "report_item bug states: $NPASS passed, $NFAIL failed"
[ "$NFAIL" = 0 ]
