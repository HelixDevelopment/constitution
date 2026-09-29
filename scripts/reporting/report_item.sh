#!/usr/bin/env bash
# ============================================================================
# report_item.sh — §11.4.202 reporting-directive item-creation + full-sync engine
# ============================================================================
#
# Purpose:
#   Turn a plain-language REPORT (delivered by the §11.4.140 reporting directives
#   ISSUE / BUG / TASK, or by any other caller) into a REAL, fully-populated
#   workable item, and then drive the FULL sync so nothing anywhere is stale:
#
#       report text
#          │
#          ├─(1) CREATE  → workable-items SQLite SSoT (§11.4.93 / §11.4.95)
#          │               Type (§11.4.16) + Status=Queued (§11.4.15)
#          │               + stable auto-incremented id (§11.4.54)
#          │               + comprehensive structured description (§11.4.148 / §11.4.171)
#          │
#          ├─(2) SYNC    → every derived document, regenerated FROM the DB
#          │               (Issues / Fixed / summaries + HTML/PDF/DOCX siblings)
#          │               via the consuming project's configured sync command
#          │               (§11.4.12 / §11.4.53 / §11.4.65 / §11.4.106)
#          │
#          └─(3) PUSH    → every configured external tracker (§11.4.148 D5).
#                          Absent credentials / absent client ⇒ honest
#                          SKIP-with-reason (§11.4.3 / §11.4.6 / §11.4.10).
#                          A push is NEVER faked.
#
# Decoupling (§11.4.28 / §11.4.177):
#   This engine carries ZERO project literals. Every project-specific value —
#   the DB path, the id prefix, the sync command, the tracker commands and their
#   required env vars — comes from a CONSUMER-OWNED config file (DATA, never an
#   edit to this script). The engine is inherited BY REFERENCE, never copied.
#
# Usage:
#   report_item.sh --kind <bug|task|issue> [--type <Bug|Feature|Task>]
#                  [--title <T>] (--report <TEXT> | --report-file <P> | stdin)
#                  [--severity <S>] [--scope <S>] [--repro <R>] [--acceptance <A>]
#                  [--reported-by <who>] [--config <P>] [--db <P>]
#                  [--no-sync] [--no-tracker] [--autonomous] [--dry-run] [--json]
#
#   --kind bug    ⇒ Type=Bug   (fixed)
#   --kind task   ⇒ Type=Task  (fixed)
#   --kind issue  ⇒ Type from --type (§11.4.16 closed set {Bug|Feature|Task}).
#                   Omitting --type is an ERROR unless --autonomous is given, in
#                   which case the §11.4.16 lowest-stakes ambiguity default `Task`
#                   is used AND recorded verbatim in the description as a
#                   defaulted classification (never a silent assertion — §11.4.6).
#
# Inputs:
#   $HELIX_REPORTING_CONFIG  — path to the consumer config (else the searched
#                              defaults: .helix/reporting.yaml,
#                              config/reporting/reporting.yaml)
#   $WORKABLE_ITEMS_BIN      — pre-built workable-items binary override
#   Tracker credentials      — read from the environment ONLY, never printed
#                              (§11.4.10); the engine checks PRESENCE, never value.
#
# Outputs:
#   stdout                   — human summary (or a JSON object with --json)
#   <evidence_dir>/<id>_<ts>/result.json  — captured evidence (§11.4.5 / §11.4.69)
#   <evidence_dir>/<id>_<ts>/{create,sync,tracker_<name>}.log
#
# Side-effects:
#   MUTATES the workable-items DB (creates one item) and regenerates the derived
#   documents via the configured sync command. Never commits, never pushes git.
#
# Exit codes:
#   0 OK (item created; sync + trackers reported honestly)
#   2 config not found / invalid
#   3 workable-items binary not resolvable
#   4 item creation failed
#   5 sync command failed (the item IS created — the DB is the SSoT; re-run sync)
#   64 usage error
#
# Dependencies:
#   bash, python3 (+PyYAML for the config read), the workable-items Go binary
#   (built or committed), and whatever the consumer's sync/tracker commands need.
#
# Cross-references:
#   §11.4.202 (this mandate) · §11.4.140 (the directive grammar) · §11.4.93 /
#   §11.4.95 (DB SSoT) · §11.4.15 / §11.4.16 / §11.4.54 (status/type/id) ·
#   §11.4.148 / §11.4.171 (comprehensive description) · §11.4.106 / §11.4.12 /
#   §11.4.53 / §11.4.65 (doc sync) · §11.4.10 (credentials) · §11.4.6 (no
#   guessing) · §11.4.3 (SKIP-with-reason) · §11.4.18 (companion doc:
#   docs/scripts/report_item.md) · §11.4.67 (bash -n + sh -n parseable).
#
# Classification: universal (§11.4.17).
# ============================================================================
set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
# This script lives at <constitution>/scripts/reporting/ — the constitution root
# is therefore TWO levels up (a one-level `..` resolves to scripts/ and breaks the
# workable-items binary lookup; caught by the real end-to-end run, not assumed).
CONST_DIR=$(cd "$SELF_DIR/../.." && pwd)

# ---------------------------------------------------------------------------
# defaults + arg parse (POSIX-parseable: no arrays, no [[ ]])
# ---------------------------------------------------------------------------
KIND=""
TYPE=""
TITLE=""
REPORT=""
REPORT_FILE=""
SEVERITY=""
SCOPE=""
REPRO=""
ACCEPTANCE=""
REPORTED_BY=""
CONFIG="${HELIX_REPORTING_CONFIG:-}"
DB_OVERRIDE=""
DO_SYNC=1
DO_TRACKER=1
AUTONOMOUS=0
DRY_RUN=0
JSON_OUT=0

die()   { printf 'report_item: %s\n' "$*" >&2; exit "${2:-64}"; }
log()   { [ "$JSON_OUT" = "1" ] || printf '[report_item] %s\n' "$*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--kind)        shift; [ $# -gt 0 ] || die "--kind needs a value"; KIND="$1" ;;
		--type)        shift; [ $# -gt 0 ] || die "--type needs a value"; TYPE="$1" ;;
		--title)       shift; [ $# -gt 0 ] || die "--title needs a value"; TITLE="$1" ;;
		--report)      shift; [ $# -gt 0 ] || die "--report needs a value"; REPORT="$1" ;;
		--report-file) shift; [ $# -gt 0 ] || die "--report-file needs a value"; REPORT_FILE="$1" ;;
		--severity)    shift; [ $# -gt 0 ] || die "--severity needs a value"; SEVERITY="$1" ;;
		--scope)       shift; [ $# -gt 0 ] || die "--scope needs a value"; SCOPE="$1" ;;
		--repro)       shift; [ $# -gt 0 ] || die "--repro needs a value"; REPRO="$1" ;;
		--acceptance)  shift; [ $# -gt 0 ] || die "--acceptance needs a value"; ACCEPTANCE="$1" ;;
		--reported-by) shift; [ $# -gt 0 ] || die "--reported-by needs a value"; REPORTED_BY="$1" ;;
		--config)      shift; [ $# -gt 0 ] || die "--config needs a value"; CONFIG="$1" ;;
		--db)          shift; [ $# -gt 0 ] || die "--db needs a value"; DB_OVERRIDE="$1" ;;
		--no-sync)     DO_SYNC=0 ;;
		--no-tracker)  DO_TRACKER=0 ;;
		--autonomous)  AUTONOMOUS=1 ;;
		--dry-run)     DRY_RUN=1 ;;
		--json)        JSON_OUT=1 ;;
		-h|--help)     sed -n '2,70p' "$0"; exit 0 ;;
		*)             die "unknown argument: $1" ;;
	esac
	shift
done

# ---------------------------------------------------------------------------
# kind → type (§11.4.16 CLOSED set {Bug | Feature | Task}; no 4th type exists)
# ---------------------------------------------------------------------------
CLASSIFICATION_NOTE=""
case "$KIND" in
	bug)  TYPE="Bug" ;;
	task) TYPE="Task" ;;
	issue)
		if [ -z "$TYPE" ]; then
			if [ "$AUTONOMOUS" = "1" ]; then
				# §11.4.16 lowest-stakes ambiguity default, recorded EXPLICITLY in
				# the description (§11.4.6 — never a silent type assertion).
				TYPE="Task"
				CLASSIFICATION_NOTE="defaulted-to-Task (§11.4.16 ambiguity default — RECLASSIFY once the type is determined)"
			else
				die "--kind issue requires --type <Bug|Feature|Task> (§11.4.16 closed set). Determine it from the report, ASK the operator (§11.4.66), or pass --autonomous to accept the documented Task default." 64
			fi
		fi
		;;
	"") die "--kind is required (bug | task | issue)" 64 ;;
	*)  die "unknown --kind: $KIND (expected bug | task | issue)" 64 ;;
esac
case "$TYPE" in
	Bug|Feature|Task) : ;;
	*) die "--type must be one of Bug | Feature | Task (§11.4.16 closed set) — got: $TYPE" 64 ;;
esac

# ---------------------------------------------------------------------------
# report text: --report | --report-file | stdin (in that precedence)
# ---------------------------------------------------------------------------
if [ -z "$REPORT" ] && [ -n "$REPORT_FILE" ]; then
	[ -f "$REPORT_FILE" ] || die "--report-file not found: $REPORT_FILE" 64
	REPORT=$(cat "$REPORT_FILE")
fi
if [ -z "$REPORT" ] && [ ! -t 0 ]; then
	REPORT=$(cat || true)
fi
[ -n "$REPORT" ] || die "no report text (pass --report, --report-file, or pipe it on stdin)" 64

# ---------------------------------------------------------------------------
# config resolution — consumer-owned DATA (§11.4.28). Fail CLOSED + actionable.
# ---------------------------------------------------------------------------
find_project_root() {
	d=$(pwd)
	while [ "$d" != "/" ]; do
		if [ -d "$d/.git" ] || [ -f "$d/.git" ]; then printf '%s' "$d"; return 0; fi
		d=$(dirname "$d")
	done
	printf '%s' "$(pwd)"
}
PROJECT_ROOT=$(find_project_root)

if [ -z "$CONFIG" ]; then
	for cand in \
		"$PROJECT_ROOT/.helix/reporting.yaml" \
		"$PROJECT_ROOT/config/reporting/reporting.yaml"
	do
		if [ -f "$cand" ]; then CONFIG="$cand"; break; fi
	done
fi
if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then
	die "no reporting config found.
  Searched: \$HELIX_REPORTING_CONFIG, $PROJECT_ROOT/.helix/reporting.yaml,
            $PROJECT_ROOT/config/reporting/reporting.yaml
  Create one from the template (consumer-owned DATA, §11.4.28):
      $CONST_DIR/scripts/reporting/reporting.example.yaml
  The engine refuses to guess your DB path / sync command (§11.4.6)." 2
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required to read the reporting config" 2

# Emit shell-safe KEY=VALUE lines from the YAML (values single-quote-escaped).
CFG_ENV=$(python3 - "$CONFIG" <<'PYEOF'
import sys, yaml, shlex
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
except Exception as e:
    sys.stderr.write("report_item: config parse error: %s\n" % e)
    sys.exit(3)
if not isinstance(doc, dict):
    sys.stderr.write("report_item: config root is not a mapping\n")
    sys.exit(3)

def emit(k, v):
    print("%s=%s" % (k, shlex.quote("" if v is None else str(v))))

emit("CFG_DB", doc.get("db", ""))
emit("CFG_ID_PREFIX", doc.get("id_prefix", ""))
emit("CFG_DEFAULT_SEVERITY", doc.get("default_severity", "Medium"))
emit("CFG_SYNC_COMMAND", doc.get("sync_command", ""))
emit("CFG_EVIDENCE_DIR", doc.get("evidence_dir", "qa-results/reporting"))
emit("CFG_WI_BIN", doc.get("workable_items_bin", ""))
emit("CFG_REPORTED_BY", doc.get("default_reported_by", ""))

trackers = doc.get("trackers") or []
if not isinstance(trackers, list):
    sys.stderr.write("report_item: config `trackers` must be a list\n")
    sys.exit(3)
emit("CFG_TRACKER_COUNT", len(trackers))
for i, t in enumerate(trackers):
    if not isinstance(t, dict):
        sys.stderr.write("report_item: config trackers[%d] is not a mapping\n" % i)
        sys.exit(3)
    emit("CFG_TRACKER_%d_NAME" % i, t.get("name", "tracker%d" % i))
    emit("CFG_TRACKER_%d_COMMAND" % i, t.get("command", ""))
    req = t.get("required_env") or []
    emit("CFG_TRACKER_%d_REQUIRED_ENV" % i, " ".join(str(x) for x in req))
    env_pass = t.get("env_passthrough") or {}
    # rendered as "K=V K=V" (values may contain the {db} placeholder)
    emit("CFG_TRACKER_%d_ENV_PASSTHROUGH" % i,
         " ".join("%s=%s" % (k, v) for k, v in env_pass.items()))
PYEOF
) || die "reporting config is invalid: $CONFIG" 2
# shlex.quote() in the Python above wraps each value in single quotes,
# which prevent all shell expansion. eval is safe here because every value
# is shell-quoted by the Python emitter (§11.4.201 — the emitter, not eval,
# is the guard; the control needle proves it).
eval "$CFG_ENV"

[ -n "${CFG_DB:-}" ] || die "config is missing the required key: db" 2
DB="${DB_OVERRIDE:-$CFG_DB}"
case "$DB" in /*) : ;; *) DB="$PROJECT_ROOT/$DB" ;; esac
[ -f "$DB" ] || die "workable-items DB not found: $DB (config key: db)" 2

[ -n "$SEVERITY" ] || SEVERITY="${CFG_DEFAULT_SEVERITY:-Medium}"
[ -n "$REPORTED_BY" ] || REPORTED_BY="${CFG_REPORTED_BY:-Operator}"

EVIDENCE_DIR="${CFG_EVIDENCE_DIR:-qa-results/reporting}"
case "$EVIDENCE_DIR" in /*) : ;; *) EVIDENCE_DIR="$PROJECT_ROOT/$EVIDENCE_DIR" ;; esac

# ---------------------------------------------------------------------------
# workable-items binary resolution (env → config → committed → built)
# ---------------------------------------------------------------------------
WI="${WORKABLE_ITEMS_BIN:-${CFG_WI_BIN:-}}"
if [ -n "$WI" ]; then
	case "$WI" in /*) : ;; *) WI="$PROJECT_ROOT/$WI" ;; esac
fi
if [ -z "$WI" ] || [ ! -x "$WI" ]; then
	WI_SRC="$CONST_DIR/scripts/workable-items"
	for cand in "$WI_SRC/bin/workable-items" "$WI_SRC/workable-items"; do
		if [ -x "$cand" ]; then WI="$cand"; break; fi
	done
fi
if [ -z "$WI" ] || [ ! -x "$WI" ]; then
	if command -v go >/dev/null 2>&1; then
		WI_BUILD="$(mktemp -d)/workable-items"
		if ( cd "$CONST_DIR/scripts/workable-items" && go build -o "$WI_BUILD" ./cmd/workable-items ) >/dev/null 2>&1; then
			WI="$WI_BUILD"
		fi
	fi
fi
[ -n "$WI" ] && [ -x "$WI" ] || die "cannot resolve the workable-items binary (set WORKABLE_ITEMS_BIN, or config workable_items_bin, or install go)" 3

# ---------------------------------------------------------------------------
# title + comprehensive structured description (§11.4.148 D2 / §11.4.171)
#
# Missing sections are marked UNKNOWN: — NEVER invented (§11.4.6). An UNKNOWN
# section is an honest gap the investigation closes; a fabricated one is a bluff.
# ---------------------------------------------------------------------------
if [ -z "$TITLE" ]; then
	# First sentence / first line of the report, trimmed to a heading-sized span.
	TITLE=$(printf '%s' "$REPORT" | tr '\n' ' ' | sed -E 's/^[[:space:]]+//; s/([.!?])[[:space:]].*$/\1/' | cut -c1-96)
	TITLE=$(printf '%s' "$TITLE" | sed -E 's/[[:space:]]+$//; s/[.!?]$//')
fi
[ -n "$TITLE" ] || die "could not derive a title from the report — pass --title" 64

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -n "$SCOPE" ]      || SCOPE="UNKNOWN: not stated in the report — to be determined during investigation (§11.4.6)"
[ -n "$REPRO" ]      || REPRO="UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199)"
[ -n "$ACCEPTANCE" ] || ACCEPTANCE="The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135)."

DESCRIPTION="**Reported-Via:** §11.4.202 reporting directive \`${KIND}\` on ${NOW_ISO}
**Reported-By:** ${REPORTED_BY}"
if [ -n "$CLASSIFICATION_NOTE" ]; then
	DESCRIPTION="${DESCRIPTION}
**Classification:** ${CLASSIFICATION_NOTE}"
fi
DESCRIPTION="${DESCRIPTION}

**What (the report, verbatim):**
${REPORT}

**Affected scope / file-scope manifest:**
${SCOPE}

**Reproduction / context:**
${REPRO}

**Acceptance criteria:**
${ACCEPTANCE}"

# ---------------------------------------------------------------------------
# DRY RUN — classify + render, write nothing.
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
	log "DRY-RUN — nothing written."
	log "  type=$TYPE severity=$SEVERITY db=$DB"
	log "  title=$TITLE"
	printf '%s\n' "$DESCRIPTION"
	exit 0
fi

# ---------------------------------------------------------------------------
# (1) CREATE the item in the SQLite SSoT (§11.4.93 / §11.4.95)
#
# T098/SOL-07 (§11.4.214, T-D04): for Bug-typed reports, resolve against the
# intake-dedup matcher FIRST, through the workable-items `intake-match`
# subcommand — a closed match REOPENS the original with §11.4.34 attribution
# (no new id minted); a distinct/ambiguous report is minted THROUGH the
# matcher's own --apply write (the SAME single-writer `add` path this
# section used to call directly). Feature/Task reports are UNCHANGED — a
# direct `add` call, byte-identical to this section's pre-T098 behaviour —
# because recurrence-detection is scoped to DEFECTS (SOL-07's own measured
# problem is Bug recurrence: "15 first-touch tickets ≈ 9 root causes"), and a
# Task/Feature directive (e.g. the §11.4.213 FEATURE scheduler,
# scripts/feature/schedule_feature_research.sh) legitimately mints a NEW
# tracked item on every call — it must never be silently reopened into a
# prior, unrelated research item.
#
# intake-match unavailable/failed/inapplicable (non-Bug type, or a
# report/config/binary issue) honestly FALLS BACK to the direct,
# unconditional mint this section always performed before this migration —
# a report is NEVER silently dropped (§11.4.202/§11.4.197).
# ---------------------------------------------------------------------------
RUN_TS=$(date -u +%Y%m%dT%H%M%SZ)
TMP_EVID=$(mktemp -d)
CREATE_LOG="$TMP_EVID/create.log"
IM_VERDICT=""
ITEM_STATUS_LABEL="Queued"

if [ "$TYPE" = "Bug" ]; then
	IM_CFG="$TMP_EVID/intake_config.yaml"
	# T103 review R1-I9: the report + decision (and the reopen-evidence file
	# intake-match writes NEXT TO --out) go under the PERSISTENT evidence dir,
	# never $TMP_EVID — a SAME_DEFECT reopen records that evidence file's path
	# in its Reopened item_history row, and $TMP_EVID is deleted when this
	# script exits (§11.4.7: a reopen whose evidence vanishes is a
	# demotion-without-evidence).
	IM_DIR="$EVIDENCE_DIR/intake_match_${RUN_TS}_$$"
	IM_REPORT="$IM_DIR/intake_report.json"
	IM_LINK="$IM_DIR/intake_link.json"
	printf 'db: %s\n' "$DB" > "$IM_CFG"
	# Thread the SAME configured id_prefix a direct `add --prefix` call below
	# would use, so an item minted THROUGH intake-match never silently
	# diverges from the consumer's configured id-prefix convention (§11.4.6).
	if [ -n "${CFG_ID_PREFIX:-}" ]; then
		printf 'id_prefix: %s\n' "$CFG_ID_PREFIX" >> "$IM_CFG"
	fi
	# An unwritable evidence dir skips the matcher (never aborts the report —
	# `set -e` would otherwise kill it here); the INTAKE-MATCH UNAVAILABLE
	# notice below then records that dedup was skipped.
	if mkdir -p "$IM_DIR" 2>/dev/null && python3 - "$TITLE" "$SCOPE" "$REPORT" > "$IM_REPORT" <<'PYEOF'
import json, sys
title, scope, report = sys.argv[1:4]
print(json.dumps({"title": title, "scope": scope, "description": report,
                   "intake_path": "reporting-directive"}))
PYEOF
	then
		set +e
		"$WI" intake-match --config "$IM_CFG" --report "$IM_REPORT" --out "$IM_LINK" --apply >"$CREATE_LOG" 2>&1
		IM_RC=$?
		set -e
		if [ "$IM_RC" = "0" ] && [ -f "$IM_LINK" ]; then
			IM_VERDICT=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('verdict',''))" "$IM_LINK" 2>/dev/null || true)
		fi
	fi
fi

case "$IM_VERDICT" in
	SAME_DEFECT)
		ITEM_ID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('original_item_id',''))" "$IM_LINK")
		if [ -n "$ITEM_ID" ]; then
			ITEM_STATUS_LABEL="Reopened"
			log "(1) §11.4.214 RECURRENCE: matched + reopened $ITEM_ID (no new id minted, intake-match)"
		else
			IM_VERDICT=""
		fi
		;;
	DISTINCT|UNDECIDED)
		ITEM_ID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('minted_item_id',''))" "$IM_LINK")
		[ -n "$ITEM_ID" ] || IM_VERDICT=""
		;;
esac

if [ "$TYPE" = "Bug" ] && { [ -z "$IM_VERDICT" ] || [ -z "${ITEM_ID:-}" ]; }; then
	# T103 review R1-I8: the fallback below is honest (a report is never
	# dropped) but it must never be SILENT — a Bug minted here skipped
	# §11.4.214 recurrence detection, so say so, with the matcher's own output,
	# before CREATE_LOG is overwritten by the fallback `add`.
	# stderr, not log(): must stay visible even in --json mode (stdout = pure JSON).
	printf '[report_item] INTAKE-MATCH UNAVAILABLE: §11.4.214 recurrence dedup was SKIPPED for this Bug report — falling back to a direct mint (binary: %s). Matcher output:\n' "$WI" >&2
	sed 's/^/    /' "$CREATE_LOG" >&2 2>/dev/null || true
fi

if [ -z "$IM_VERDICT" ] || [ -z "${ITEM_ID:-}" ]; then
	set +e
	if [ -n "${CFG_ID_PREFIX:-}" ]; then
		"$WI" add "$TYPE" "$SEVERITY" --db "$DB" --title "$TITLE" --description "$DESCRIPTION" \
			--prefix "$CFG_ID_PREFIX" --created-by "$REPORTED_BY" >"$CREATE_LOG" 2>&1
	else
		"$WI" add "$TYPE" "$SEVERITY" --db "$DB" --title "$TITLE" --description "$DESCRIPTION" \
			--created-by "$REPORTED_BY" >"$CREATE_LOG" 2>&1
	fi
	CREATE_RC=$?
	set -e

	if [ "$CREATE_RC" != "0" ]; then
		log "ITEM CREATION FAILED (rc=$CREATE_RC):"
		cat "$CREATE_LOG" >&2
		exit 4
	fi

	# The binary prints the assigned id; extract the FIRST <PREFIX>-NNN token.
	ITEM_ID=$(grep -oE '[A-Z][A-Z0-9_]*-[0-9]{3,}' "$CREATE_LOG" | head -1 || true)
	[ -n "$ITEM_ID" ] || ITEM_ID="UNKNOWN-ID"
	ITEM_STATUS_LABEL="Queued"
fi

EVID="$EVIDENCE_DIR/${ITEM_ID}_${RUN_TS}"
mkdir -p "$EVID"
cp "$CREATE_LOG" "$EVID/create.log"
rm -rf "$TMP_EVID"
log "(1) CREATED $ITEM_ID  type=$TYPE  severity=$SEVERITY  status=$ITEM_STATUS_LABEL"

# ---------------------------------------------------------------------------
# (2) SYNC every derived document FROM the DB (§11.4.106 / §11.4.12 / §11.4.65)
# ---------------------------------------------------------------------------
SYNC_VERDICT="SKIPPED"
SYNC_REASON="disabled by --no-sync"
if [ "$DO_SYNC" = "1" ]; then
	if [ -z "${CFG_SYNC_COMMAND:-}" ]; then
		SYNC_VERDICT="SKIPPED"
		SYNC_REASON="no sync_command configured (§11.4.6: the engine refuses to guess one)"
		log "(2) SYNC SKIPPED — $SYNC_REASON"
	else
		SYNC_CMD=$(printf '%s' "$CFG_SYNC_COMMAND" | sed "s|{db}|$DB|g")
		log "(2) SYNC: $SYNC_CMD"
		set +e
		( cd "$PROJECT_ROOT" && bash -c "$SYNC_CMD" ) >"$EVID/sync.log" 2>&1
		SYNC_RC=$?
		set -e
		if [ "$SYNC_RC" = "0" ]; then
			SYNC_VERDICT="PASS"; SYNC_REASON=""
			log "    sync OK → $EVID/sync.log"
		else
			SYNC_VERDICT="FAIL"; SYNC_REASON="sync command exited $SYNC_RC"
			log "    SYNC FAILED (rc=$SYNC_RC) — the item IS created (the DB is the SSoT); re-run the sync."
		fi
	fi
fi

# ---------------------------------------------------------------------------
# (3) PUSH to every configured external tracker (§11.4.148 D5).
#     Absent credentials / absent client ⇒ honest SKIP-with-reason. NEVER faked.
#     Credential VALUES are never read, printed, or logged (§11.4.10) — only
#     their PRESENCE is tested.
# ---------------------------------------------------------------------------
TRACKER_JSON=""
TRACKER_COUNT="${CFG_TRACKER_COUNT:-0}"
if [ "$DO_TRACKER" = "1" ] && [ "$TRACKER_COUNT" != "0" ]; then
	i=0
	while [ "$i" -lt "$TRACKER_COUNT" ]; do
		eval "T_NAME=\${CFG_TRACKER_${i}_NAME:-}"
		eval "T_CMD=\${CFG_TRACKER_${i}_COMMAND:-}"
		eval "T_REQ=\${CFG_TRACKER_${i}_REQUIRED_ENV:-}"
		eval "T_PASS=\${CFG_TRACKER_${i}_ENV_PASSTHROUGH:-}"

		T_VERDICT=""
		T_REASON=""

		if [ -z "$T_CMD" ]; then
			T_VERDICT="SKIP"
			T_REASON="tracker_client_absent: no command configured for '$T_NAME' (PENDING-OPERATOR-INPUT — never faked, §11.4.6)"
		else
			MISSING=""
			for v in $T_REQ; do
				have="${!v:-}"  # indirect expansion (§11.4.201 — no eval)
				if [ -z "$have" ]; then MISSING="$MISSING $v"; fi
			done
			if [ -n "$MISSING" ]; then
				T_VERDICT="SKIP"
				# Names only — never values (§11.4.10).
				T_REASON="credentials_absent: unset env:$MISSING"
			else
				T_RENDERED=$(printf '%s' "$T_CMD" | sed "s|{db}|$DB|g; s|{id}|$ITEM_ID|g")
				T_ENV=""
				for kv in $T_PASS; do
					k=${kv%%=*}; v=${kv#*=}
					v=$(printf '%s' "$v" | sed "s|{db}|$DB|g; s|{id}|$ITEM_ID|g")
					T_ENV="$T_ENV $k=$v"
				done
				log "(3) TRACKER $T_NAME: pushing $ITEM_ID"
				set +e
				( cd "$PROJECT_ROOT" && bash -c "env $T_ENV $T_RENDERED" ) >"$EVID/tracker_$T_NAME.log" 2>&1
				T_RC=$?
				set -e
				if [ "$T_RC" = "0" ]; then
					T_VERDICT="PASS"
					T_REASON=""
					log "    $T_NAME OK → $EVID/tracker_$T_NAME.log"
				else
					T_VERDICT="FAIL"
					T_REASON="tracker command exited $T_RC (see tracker_$T_NAME.log)"
					log "    $T_NAME FAILED (rc=$T_RC) — reported honestly, never faked."
				fi
			fi
		fi
		# NOTE (§11.4.1): an `[ test ] && cmd` AND-list as the last command of the
		# loop body would abort the whole script under `set -e` whenever the test
		# is false. Use an explicit `if` — a script-internal crash that reports a
		# false failure is a FAIL-bluff.
		if [ "$T_VERDICT" = "SKIP" ]; then
			log "(3) TRACKER $T_NAME: SKIP — $T_REASON"
		fi

		if [ -n "$TRACKER_JSON" ]; then TRACKER_JSON="$TRACKER_JSON,"; fi
		TRACKER_JSON="$TRACKER_JSON{\"name\":\"$T_NAME\",\"verdict\":\"$T_VERDICT\",\"reason\":\"$T_REASON\"}"
		i=$((i + 1))
	done
fi

# ---------------------------------------------------------------------------
# captured evidence (§11.4.5 / §11.4.69) + summary
# ---------------------------------------------------------------------------
RESULT_JSON="$EVID/result.json"
{
	printf '{\n'
	printf '  "anchor": "11.4.202",\n'
	printf '  "item_id": "%s",\n' "$ITEM_ID"
	printf '  "kind": "%s",\n' "$KIND"
	printf '  "type": "%s",\n' "$TYPE"
	printf '  "status": "%s",\n' "$ITEM_STATUS_LABEL"
	printf '  "severity": "%s",\n' "$SEVERITY"
	printf '  "classification_note": "%s",\n' "$CLASSIFICATION_NOTE"
	printf '  "created_at": "%s",\n' "$NOW_ISO"
	printf '  "db": "%s",\n' "$DB"
	printf '  "sync": {"verdict": "%s", "reason": "%s"},\n' "$SYNC_VERDICT" "$SYNC_REASON"
	printf '  "trackers": [%s],\n' "$TRACKER_JSON"
	printf '  "evidence_dir": "%s"\n' "$EVID"
	printf '}\n'
} > "$RESULT_JSON"

if [ "$JSON_OUT" = "1" ]; then
	cat "$RESULT_JSON"
else
	log "DONE — $ITEM_ID ($TYPE, $ITEM_STATUS_LABEL)"
	log "  sync:     $SYNC_VERDICT ${SYNC_REASON:+($SYNC_REASON)}"
	log "  trackers: ${TRACKER_JSON:-none configured}"
	log "  evidence: $RESULT_JSON"
fi

if [ "$SYNC_VERDICT" = "FAIL" ]; then exit 5; fi
exit 0
