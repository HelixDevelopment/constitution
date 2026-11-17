#!/usr/bin/env bash
# ============================================================================
# schedule_feature_research.sh — §11.4.213 FEATURE research-scheduling engine
# ============================================================================
#
# Purpose:
#   Turn a plain-language FEATURE DESCRIPTION (delivered by the §11.4.140
#   registered action `FEATURE`, or by any other caller) into a SCHEDULED —
#   never synchronously executed — deep, enterprise-grade research +
#   implementation-planning effort:
#
#       feature description
#          │
#          ├─(1) CREATE  → a Type=Task workable item in the SAME workable-items
#          │               SQLite SSoT §11.4.202 `report_item.sh` writes to
#          │               (§11.4.93 / §11.4.95), by DELEGATING to that engine
#          │               — never a duplicate implementation (§11.4.213
#          │               clause 4) — whose comprehensive description embeds
#          │               the full research-and-planning WORK PROGRAM as its
#          │               acceptance-defining content (§11.4.148 / §11.4.171)
#          │
#          ├─(2) SYNC + PUSH → delegated to report_item.sh exactly as §11.4.202
#          │               performs them: every derived document regenerated
#          │               FROM the DB, every configured external tracker
#          │               pushed, absent credentials/client ⇒ honest
#          │               SKIP-with-reason, NEVER a faked push
#          │
#          └─(3) QUEUE   → append a row to the durable, never-dropped
#                          `docs/requests/feature_queue.md` (mirrors the
#                          §11.4.140 `BACKGROUND` action's durable queue
#                          pattern) so a scheduled request can never be
#                          silently dropped or forgotten.
#
#   The multi-day research / planning / documentation work DESCRIBED INSIDE
#   the item is NOT performed by this engine — it is performed LATER by the
#   project's standing autonomous loop (§11.4.87 / §11.4.94 / §11.4.97 /
#   §11.4.103 / §11.4.126) when it claims the item, driven to a genuinely
#   COMPLETED-and-wired or explicitly evidence-backed CLOSED terminal state
#   under the §11.4.197 research-completion mandate.
#
# Decoupling (§11.4.28 / §11.4.177):
#   This engine carries ZERO project literals. Every project-specific value —
#   the DB path, the id prefix, the research-doc root, the sync command, the
#   tracker commands and their required env vars — comes from a
#   CONSUMER-OWNED config file (DATA, never an edit to this script). The
#   engine is inherited BY REFERENCE, never copied.
#
# Usage:
#   schedule_feature_research.sh (--description <TEXT> | --description-file <P> | stdin)
#                  [--title <T>] [--severity <S>] [--reported-by <who>]
#                  [--config <P>] [--db <P>]
#                  [--no-sync] [--no-tracker] [--dry-run] [--json]
#
# Inputs:
#   $HELIX_FEATURE_CONFIG   — path to the consumer config (else the searched
#                             defaults: .helix/feature.yaml,
#                             config/feature/feature.yaml)
#   The SAME config file is passed through to the delegated report_item.sh
#   engine via --config (schema-compatible superset — §11.4.213 clause 4);
#   this script itself reads only its own `research_doc_root` key.
#
# Outputs:
#   stdout                  — human summary (or a JSON object with --json)
#   docs/requests/feature_queue.md  — durable append-only queue row
#   <evidence_dir>/<id>_<ts>/result.json + report_item_result.json
#
# Side-effects:
#   Delegates to report_item.sh (creates one workable item, may regenerate
#   derived documents, may push to external trackers). Appends one row to
#   the project's docs/requests/feature_queue.md. Never commits, never
#   pushes git.
#
# Exit codes:
#   0  OK (item created + queued; sync + trackers reported honestly)
#   2  config not found / invalid (this engine's OR the delegated engine's)
#   3  the §11.4.202 report_item.sh engine is not resolvable
#   4  item creation failed (delegated engine's rc=4)
#   5  sync command failed (delegated engine's rc=5 — the item IS created)
#   64 usage error
#
# Dependencies:
#   bash, python3 (+PyYAML for the config read + JSON parse of the delegate's
#   result), the sibling constitution/scripts/reporting/report_item.sh engine.
#
# Cross-references:
#   §11.4.213 (this mandate) · §11.4.202 (the delegated engine + reporting
#   directive family) · §11.4.197 (a started research effort never
#   evaporates) · §11.4.140 (the directive grammar) · §11.4.93 / §11.4.95 (DB
#   SSoT) · §11.4.148 / §11.4.171 (comprehensive description) · §11.4.8 /
#   §11.4.99 / §11.4.150 (deep research) · §11.4.102 (systematic-debug of
#   every gap) · §11.4.28 / §11.4.74 / §11.4.177 (reuse-first, decoupled) ·
#   §11.4.27 / §11.4.169 (test-type + Challenges + HelixQA planning) ·
#   §11.4.162 / §11.4.190 (OpenDesign UI planning) · §11.4.78 / §11.4.79 /
#   §11.4.80 (CodeGraph integration) · §11.4.10 (credentials) · §11.4.6 (no
#   guessing) · §11.4.18 (companion doc: docs/scripts/schedule_feature_research.md)
#   · §11.4.67 (bash -n + sh -n parseable) · §11.4.87 / §11.4.94 / §11.4.97 /
#   §11.4.103 / §11.4.126 (the autonomous loop that performs the scheduled work).
#
# Classification: universal (§11.4.17).
# ============================================================================
set -eu

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
# This script lives at <constitution>/scripts/feature/ — the constitution
# root is TWO levels up (a one-level `..` resolves to scripts/ and breaks the
# report_item.sh lookup; caught by the real end-to-end run, not assumed).
CONST_DIR=$(cd "$SELF_DIR/../.." && pwd)
REPORT_ITEM="$CONST_DIR/scripts/reporting/report_item.sh"

# ---------------------------------------------------------------------------
# defaults + arg parse (POSIX-parseable: no arrays, no [[ ]])
# ---------------------------------------------------------------------------
DESCRIPTION=""
DESCRIPTION_FILE=""
TITLE=""
SEVERITY=""
REPORTED_BY=""
CONFIG="${HELIX_FEATURE_CONFIG:-}"
DB_OVERRIDE=""
DO_SYNC=1
DO_TRACKER=1
DRY_RUN=0
JSON_OUT=0

die()   { printf 'schedule_feature_research: %s\n' "$*" >&2; exit "${2:-64}"; }
log()   { [ "$JSON_OUT" = "1" ] || printf '[schedule_feature_research] %s\n' "$*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--description)      shift; [ $# -gt 0 ] || die "--description needs a value"; DESCRIPTION="$1" ;;
		--description-file) shift; [ $# -gt 0 ] || die "--description-file needs a value"; DESCRIPTION_FILE="$1" ;;
		--title)             shift; [ $# -gt 0 ] || die "--title needs a value"; TITLE="$1" ;;
		--severity)           shift; [ $# -gt 0 ] || die "--severity needs a value"; SEVERITY="$1" ;;
		--reported-by)        shift; [ $# -gt 0 ] || die "--reported-by needs a value"; REPORTED_BY="$1" ;;
		--config)             shift; [ $# -gt 0 ] || die "--config needs a value"; CONFIG="$1" ;;
		--db)                 shift; [ $# -gt 0 ] || die "--db needs a value"; DB_OVERRIDE="$1" ;;
		--no-sync)     DO_SYNC=0 ;;
		--no-tracker)  DO_TRACKER=0 ;;
		--dry-run)     DRY_RUN=1 ;;
		--json)        JSON_OUT=1 ;;
		-h|--help)     sed -n '2,99p' "$0"; exit 0 ;;
		*)             die "unknown argument: $1" ;;
	esac
	shift
done

# ---------------------------------------------------------------------------
# feature description: --description | --description-file | stdin
# ---------------------------------------------------------------------------
if [ -z "$DESCRIPTION" ] && [ -n "$DESCRIPTION_FILE" ]; then
	[ -f "$DESCRIPTION_FILE" ] || die "--description-file not found: $DESCRIPTION_FILE" 64
	DESCRIPTION=$(cat "$DESCRIPTION_FILE")
fi
if [ -z "$DESCRIPTION" ] && [ ! -t 0 ]; then
	DESCRIPTION=$(cat || true)
fi
[ -n "$DESCRIPTION" ] || die "no feature description (pass --description, --description-file, or pipe it on stdin)" 64

[ -f "$REPORT_ITEM" ] || die "the §11.4.202 report_item.sh engine is missing: $REPORT_ITEM (§11.4.213 clause 4 — FEATURE delegates to it, never reimplements it)" 3

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
		"$PROJECT_ROOT/.helix/feature.yaml" \
		"$PROJECT_ROOT/config/feature/feature.yaml"
	do
		if [ -f "$cand" ]; then CONFIG="$cand"; break; fi
	done
fi
if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then
	die "no feature config found.
  Searched: \$HELIX_FEATURE_CONFIG, $PROJECT_ROOT/.helix/feature.yaml,
            $PROJECT_ROOT/config/feature/feature.yaml
  Create one from the template (consumer-owned DATA, §11.4.28):
      $CONST_DIR/scripts/feature/feature.example.yaml
  The engine refuses to guess your DB path / research-doc root (§11.4.6)." 2
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required to read the feature config" 2

# This script reads only its OWN key (research_doc_root [+ evidence_dir
# default]); every other key (db / id_prefix / sync_command / trackers / …)
# is read independently by the DELEGATED report_item.sh from the SAME file.
CFG_ENV=$(python3 - "$CONFIG" <<'PYEOF'
import sys, yaml, shlex
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
except Exception as e:
    sys.stderr.write("schedule_feature_research: config parse error: %s\n" % e)
    sys.exit(3)
if not isinstance(doc, dict):
    sys.stderr.write("schedule_feature_research: config root is not a mapping\n")
    sys.exit(3)
def emit(k, v):
    print("%s=%s" % (k, shlex.quote("" if v is None else str(v))))
emit("CFG_RESEARCH_ROOT", doc.get("research_doc_root", "docs/research"))
emit("CFG_EVIDENCE_DIR", doc.get("evidence_dir", "qa-results/feature"))
PYEOF
) || die "feature config is invalid: $CONFIG" 2
eval "$CFG_ENV"

RESEARCH_ROOT="${CFG_RESEARCH_ROOT:-docs/research}"
case "$RESEARCH_ROOT" in /*) : ;; *) RESEARCH_ROOT="$PROJECT_ROOT/$RESEARCH_ROOT" ;; esac

EVIDENCE_DIR="${CFG_EVIDENCE_DIR:-qa-results/feature}"
case "$EVIDENCE_DIR" in /*) : ;; *) EVIDENCE_DIR="$PROJECT_ROOT/$EVIDENCE_DIR" ;; esac

# ---------------------------------------------------------------------------
# title + destination-slug derivation (title logic mirrors report_item.sh)
# ---------------------------------------------------------------------------
if [ -z "$TITLE" ]; then
	TITLE=$(printf '%s' "$DESCRIPTION" | tr '\n' ' ' | sed -E 's/^[[:space:]]+//; s/([.!?])[[:space:]].*$/\1/' | cut -c1-96)
	TITLE=$(printf '%s' "$TITLE" | sed -E 's/[[:space:]]+$//; s/[.!?]$//')
fi
[ -n "$TITLE" ] || die "could not derive a title from the description — pass --title" 64

SLUG=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//' | cut -c1-60)
[ -n "$SLUG" ] || SLUG="feature"

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RUN_TS=$(date -u +%Y%m%dT%H%M%SZ)

case "$RESEARCH_ROOT" in
	"$PROJECT_ROOT"/*) DEST_ROOT_REL="${RESEARCH_ROOT#"$PROJECT_ROOT"/}" ;;
	*)                 DEST_ROOT_REL="$RESEARCH_ROOT" ;;
esac
# Uniquifier (F3, §11.4.6): (slug, seconds-resolution UTC timestamp) alone
# collides when two identical-title requests are scheduled within the same
# second — both would record the SAME research-doc destination on two
# distinct items. Append this process's PID ($$) as a third key component;
# it costs nothing (already resolvable), keeps the path human-readable, and
# is unique-enough for a doc destination (two concurrent schedulers sharing
# both the same second AND the same PID is not a real system's condition).
DEST_PATH="$RESEARCH_ROOT/${SLUG}_${RUN_TS}_$$"
DEST_PATH_REL="${DEST_ROOT_REL}/${SLUG}_${RUN_TS}_$$"

# ---------------------------------------------------------------------------
# the full §11.4.213 research-and-planning WORK PROGRAM, embedded verbatim as
# the item's acceptance-defining content (never invented per-clause — this IS
# the mandate, §11.4.6).
# ---------------------------------------------------------------------------
RESEARCH_MANDATE=$(cat <<MANDEOF
§11.4.213 FEATURE research-and-planning WORK PROGRAM (scheduled, not yet executed):

(a) Deep web-research series (articles / guides / scientific papers / open-source projects+codebases / real-world examples) on the best way to incorporate this feature into the project (§11.4.8 / §11.4.99 / §11.4.150).
(b) Systematic-debug (§11.4.102) of ALL data obtained to enumerate EVERY weak spot / gap / danger-zone / inconsistency / imperfection, and design a risk-free, rock-solid solution for EACH one found.
(c) The design MUST ALWAYS be enterprise-grade, bleeding-edge, and innovative -- never less.
(d) MANDATORY exhaustive documentation: many technical documents, an implementation plan down to lines-of-code + micro-proof-of-concepts, diagrams / schemes / graphs, illustrations, SQL definitions, templates, and every other relevant material (§11.4.65 / §11.4.73).
(e) Investigate + plan REUSE of existing vasic-digital + HelixDevelopment submodules/components BEFORE proposing a rewrite; extend them freely where genuinely needed while keeping them fully decoupled / project-not-aware / reusable (§11.4.28 / §11.4.74 / §11.4.177).
(f) Plan from the TESTING point of view from day one: every supported test type, the Challenges submodule, and full HelixQA bank coverage (§11.4.27 / §11.4.169).
(g) Divide the work into phases / tasks / subtasks, fine-grained and nano-detailed enough to drive integration / implementation / wiring / testing / scaling directly.
(h) Plan explicitly for enterprise scalability and maximal performance.
(i) When the feature has a UI/UX surface, produce full wireframes / diagrams / design files (Figma / PSD / PDF, or whatever the project mandates) authored via OpenDesign (§11.4.162 / §11.4.190).
(j) Plan full CodeGraph integration with regular / real-time index synchronisation (§11.4.78 / §11.4.79 / §11.4.80).
(k) Create fully-detailed follow-on workable items (every detail + reference + attachment) synced in REAL TIME to the SQLite single-source-of-truth (§11.4.93 / §11.4.95) + every derived workable-items document + every related project doc/component + every connected external work-tracking system (§11.4.148 D5) -- honestly SKIPPING any absent tracker with a machine-readable reason (credentials_absent / tracker_client_absent, §11.4.10) rather than EVER faking a push.

Research-doc destination (to be populated when this item is worked): ${DEST_PATH_REL}/

Execution model (§11.4.213 clauses 1-2): this item is SCHEDULED, not yet executed. The multi-day research/planning/documentation work above is performed LATER by the project's standing autonomous loop (§11.4.87 / §11.4.94 / §11.4.97 / §11.4.103 / §11.4.126) when it claims this item, and MUST be driven to a genuinely COMPLETED-and-wired or explicitly evidence-backed CLOSED terminal state under §11.4.197 -- this item MUST NOT be left sitting un-wired in the backlog.
MANDEOF
)

FULL_REPORT="Feature description (verbatim):
${DESCRIPTION}

${RESEARCH_MANDATE}"

ACCEPTANCE="The full research-doc tree exists under ${DEST_PATH_REL}/, every enumerated weak-spot/gap/danger-zone carries a designed risk-free solution, an implementation plan down to lines-of-code exists, the planned follow-on workable items are created, and the whole effort is validated per §11.4.197 (never left un-wired)."
SCOPE="Feature research/planning -- destination: ${DEST_PATH_REL}/"

# ---------------------------------------------------------------------------
# DRY RUN — render + preview, write nothing, never invoke the delegate.
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
	log "DRY-RUN — nothing written, delegate NOT invoked."
	log "  title=$TITLE"
	log "  destination=$DEST_PATH_REL"
	printf '%s\n' "$FULL_REPORT"
	exit 0
fi

mkdir -p "$EVIDENCE_DIR"

# ---------------------------------------------------------------------------
# (1)+(2) DELEGATE item-creation + DB-sync + tracker-push to the SAME
# §11.4.202 report_item.sh engine — NEVER a duplicate/divergent
# implementation of that machinery (§11.4.213 clause 4).
# ---------------------------------------------------------------------------
set -- --kind task --title "$TITLE" --report "$FULL_REPORT" \
	--scope "$SCOPE" --acceptance "$ACCEPTANCE" --config "$CONFIG"
if [ -n "$SEVERITY" ]; then set -- "$@" --severity "$SEVERITY"; fi
if [ -n "$REPORTED_BY" ]; then set -- "$@" --reported-by "$REPORTED_BY"; fi
if [ -n "$DB_OVERRIDE" ]; then set -- "$@" --db "$DB_OVERRIDE"; fi
if [ "$DO_SYNC" != "1" ]; then set -- "$@" --no-sync; fi
if [ "$DO_TRACKER" != "1" ]; then set -- "$@" --no-tracker; fi
set -- "$@" --json

log "(1)+(2) delegating to report_item.sh --kind task ..."
set +e
RI_OUT=$(bash "$REPORT_ITEM" "$@" 2>&1)
RI_RC=$?
set -e

if [ "$RI_RC" != "0" ] && [ "$RI_RC" != "5" ]; then
	log "DELEGATE FAILED (rc=$RI_RC) -- the FEATURE item was NOT created:"
	printf '%s\n' "$RI_OUT" >&2
	exit "$RI_RC"
fi

ITEM_ID=$(printf '%s' "$RI_OUT" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    sys.stdout.write(d.get("item_id",""))
except Exception:
    pass' 2>/dev/null || true)
[ -n "$ITEM_ID" ] || ITEM_ID="UNKNOWN-ID"

log "(1) SCHEDULED $ITEM_ID  type=Task  destination=$DEST_PATH_REL"

# ---------------------------------------------------------------------------
# (3) QUEUE — durable, never-dropped feature-research queue (§11.4.213
# clause 4; mirrors the §11.4.140 BACKGROUND durable-queue pattern).
# ---------------------------------------------------------------------------
FEATURE_QUEUE="$PROJECT_ROOT/docs/requests/feature_queue.md"
mkdir -p "$(dirname "$FEATURE_QUEUE")"
if [ ! -f "$FEATURE_QUEUE" ]; then
	{
		printf '# Feature Research Queue (§11.4.213)\n\n'
		printf '**Revision:** 1\n'
		printf '**Last modified:** %s\n\n' "$NOW_ISO"
		printf 'Durable, append-only, NEVER-dropped queue of §11.4.213 FEATURE\n'
		printf 'research-scheduling requests. Each row records the assigned\n'
		printf 'workable-item id, title, research-doc destination, and the\n'
		printf 'timestamp the request was scheduled; the standing autonomous\n'
		printf 'loop (§11.4.87 / §11.4.94 / §11.4.97 / §11.4.103 / §11.4.126)\n'
		printf 'claims and works each item under the §11.4.197\n'
		printf 'research-completion mandate -- never left un-wired.\n\n'
		printf '| Item ID | Title | Destination | Scheduled (UTC) | Status |\n'
		printf '|---|---|---|---|---|\n'
	} > "$FEATURE_QUEUE"
fi
# F1 (§11.4.65): TITLE is the only user-influenced cell in this row — an
# unescaped literal `|` in the title corrupts the 5-column markdown table
# (Destination / Scheduled / Status all shift one column right). The
# ITEM_ID / DEST_PATH_REL / NOW_ISO / literal "Queued" cells are
# structurally safe by construction (generated, never free-text) and need
# no escaping.
QTITLE=$(printf '%s' "$TITLE" | sed 's/|/\\|/g')
printf '| %s | %s | `%s/` | %s | Queued |\n' "$ITEM_ID" "$QTITLE" "$DEST_PATH_REL" "$NOW_ISO" >> "$FEATURE_QUEUE"
log "(3) QUEUED -> ${FEATURE_QUEUE#"$PROJECT_ROOT"/}"

# ---------------------------------------------------------------------------
# captured evidence (§11.4.5 / §11.4.69) + summary
# ---------------------------------------------------------------------------
EVID="$EVIDENCE_DIR/${ITEM_ID}_${RUN_TS}"
mkdir -p "$EVID"
printf '%s\n' "$RI_OUT" > "$EVID/report_item_result.json"

RESULT_JSON="$EVID/result.json"
{
	printf '{\n'
	printf '  "anchor": "11.4.213",\n'
	printf '  "item_id": "%s",\n' "$ITEM_ID"
	printf '  "title": "%s",\n' "$(printf '%s' "$TITLE" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read().rstrip("\n"))[1:-1])')"
	printf '  "destination": "%s",\n' "$DEST_PATH_REL"
	printf '  "scheduled_at": "%s",\n' "$NOW_ISO"
	printf '  "feature_queue": "%s",\n' "${FEATURE_QUEUE#"$PROJECT_ROOT"/}"
	printf '  "delegated_report_item_rc": %s,\n' "$RI_RC"
	printf '  "delegated_report_item_result": %s,\n' "$RI_OUT"
	printf '  "evidence_dir": "%s"\n' "$EVID"
	printf '}\n'
} > "$RESULT_JSON"

if [ "$JSON_OUT" = "1" ]; then
	cat "$RESULT_JSON"
else
	log "DONE — $ITEM_ID scheduled (Task, Queued)"
	log "  destination: $DEST_PATH_REL"
	log "  delegate rc: $RI_RC"
	log "  evidence:    $RESULT_JSON"
fi

exit "$RI_RC"
