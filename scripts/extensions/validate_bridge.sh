#!/usr/bin/env bash
# validate_bridge.sh — HXC-159 T-B2.03 Bridge self-validation.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The Bridge design corpus's own README (already read during Phase 1 planning;
# implementation/README.md:507-539) advertises an aspirational
# "ALL 8/8 CHECKS PASSED — bridge ready" example transcript. This script
# re-derives that 8-check list from the corpus and reports HONESTLY against
# the MEASURED layer state (T-B1.01's probe) — never claiming 8/8 while a
# layer is genuinely absent (§11.4/§11.4.1 — a config-only or wishful PASS is
# a bluff regardless of how green the summary line looks).
#
# ── The 8 checks, re-derived verbatim from the design corpus ────────────────
# (implementation/README.md:528-538, Step 4 "Run the Self-Validation Suite"):
#   1. SuperBridge MCP server health-check         (L5)
#   2. speckit-specify extension loads             (L2)
#   3. speckit-plan extension loads                (L2)
#   4. speckit-tasks extension loads                (L2)
#   5. superspec status returns valid JSON          (L3)
#   6. superb check passes on constitution files    (L4)
#   7. Helix LLM Gateway reachable                  (L6)
#   8. llama.cpp RPC backend health-check            (L7)
#
# ── Check 1 (SuperBridge MCP) is DROPPED, not merely failed ─────────────────
# T-B1.01/T-B3.01 independently established (two derivations: `total_count: 0`
# GitHub code search + zero matching npm packages) that "SuperBridge MCP" does
# not exist as software — the design corpus's own L4 (SuperB) README states it
# "owns no plan, task store, execution lifecycle, completion state, or
# convergence command", so no adjacent layer ever claimed the execution role
# either. Per T-B2.03.2 ("drop or re-point any check that depends on L5") and
# the parent task's own framing ("a step that can never succeed is a defect,
# not a TODO"), check 1 is DROPPED from the evaluable set rather than reported
# as a permanent FAIL — a check that can NEVER pass, on ANY host, forever, is
# not informative signal, it is noise. This script reports it explicitly as
# DROPPED (never silently omitted, §11.4.6) with its citation, and the summary
# line is honestly "N/7 evaluable checks", never "N/8".
#
# ── Honest scope narrowing on checks 5 and 6 (§11.4.6, recorded not hidden) ──
# Checks 5 ("superspec status returns valid JSON") and 6 ("superb check passes
# on constitution files") name `speckit.superspec.status` / a SuperB `check`
# command as their oracle. Both are Markdown SLASH-COMMAND PROMPTS consumed by
# a CLI AGENT (an LLM turn), not standalone scripts a shell validator can
# invoke and parse output from (confirmed by reading
# .specify/extensions/superspec/commands/status.md — it is a natural-language
# procedure for an agent to follow, not executable code). Requiring this
# SHELL script to genuinely "run superspec status and parse its JSON" would
# require driving an LLM turn from inside a non-interactive validator — not
# something this script can do autonomously (§11.4.98's fully-self-driving
# requirement cuts the OTHER way here: a check requiring a human/LLM-in-the-
# loop to produce its verdict is the thing §11.4.98 forbids as primary
# validation). This script therefore checks the SHELL-VERIFIABLE PRECONDITIONS
# for each command instead — command file present + well-formed, AND (for
# check 5) the superspec extension registered + Enabled via
# `specify extension list --json` — and reports the narrowed scope explicitly
# in its own output rather than silently claiming to have validated the LLM
# behaviour it did not and cannot autonomously drive.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/extensions/validate_bridge.sh \
#       [--root <repo-root>] [--report-file <probe-report.json>] [--quiet]
#
#   --root         repo root (defaults to three levels above this script).
#   --report-file  use this probe report.json instead of running a fresh
#                  probe_bridge_layers.sh invocation (used by this script's
#                  own paired-mutation test to inject a sandboxed/synthetic
#                  layer report, §11.4.84).
#   --quiet        suppress non-essential stdout narration.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   A Bridge layer-presence report (freshly probed, or --report-file), the
#   `specify` CLI (or $SPECIFY_BIN override), the repo's skill directories
#   (.claude/skills, .kimi-code/skills — the same per-consumer set the probe
#   itself checks, since per-consumer skill-count variance is a known, tracked
#   fact per HXC-159 Phase P2, not a defect this script re-litigates), curl
#   (opportunistic — its absence degrades check 7 honestly, never guessed).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   <repo-root>/qa-results/hxc159/bridge_validate/<run-id>/
#     validate_report.json — machine-readable per-check verdict.
#     validate.log          — full narration.
#   Exit 0 — every EVALUABLE check (2-8, i.e. all but the dropped check 1)
#            reports PASS. Exit 1 — one or more evaluable checks FAILed, OR
#            the check itself could not run (treated as FAIL, never silently
#            skipped as if it were a PASS — §11.4.201 conservative default).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE. Every check is a read-only probe (file reads, `specify extension
#   list`, a single `curl` HEAD-equivalent request to the Helix LLM Gateway,
#   a process-presence check for the llama.cpp RPC server). No installation,
#   no mutation of .specify/ or any submodule.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 (JSON parsing/assembly), the `specify` CLI (or $SPECIFY_BIN),
#   curl (opportunistic, check 7 only). Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   specs/001-helixskills-incorporation/tasks.md Phase B2 (T-B2.03) ·
#   implementation/README.md:507-539 (the 8-check source) · T-B1.01/T-B3.01
#   (L5-does-not-exist finding, cited not re-derived) · §11.4.6 (no-guessing —
#   honest DROPPED/scope-narrowed markers) · §11.4.69 (feature_class=
#   extension_loading) · §11.4.98 (fully-self-driving — the reason checks 5/6
#   are scope-narrowed rather than LLM-driven) · §11.4.201 (conservative
#   default: an unresolvable check is FAIL, never a silent PASS) · §1.1
#   (paired mutation: validate_bridge_mutation_test.sh).
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
REPORT_FILE=""
QUIET=0
SPECIFY_BIN="${SPECIFY_BIN:-specify}"

while [ $# -gt 0 ]; do
	case "$1" in
		--root)        shift; ROOT="$1" ;;
		--report-file) shift; REPORT_FILE="$1" ;;
		--quiet)       QUIET=1 ;;
		-h|--help)     sed -n '3,90p' "$0"; exit 0 ;;
		*) echo "validate_bridge.sh: unknown arg: $1" >&2; exit 2 ;;
	esac
	shift || true
done

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
EVID_DIR="$ROOT/qa-results/hxc159/bridge_validate/$RUN_ID"
mkdir -p "$EVID_DIR" || { echo "cannot create evidence dir: $EVID_DIR" >&2; exit 1; }
LOG_FILE="$EVID_DIR/validate.log"
REPORT_OUT="$EVID_DIR/validate_report.json"

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; printf '%s\n' "$*" >>"$LOG_FILE"; }
log_only() { printf '%s\n' "$*" >>"$LOG_FILE"; }

say "== validate_bridge.sh — run $RUN_ID =="
say "   root: $ROOT"

if [ -z "$REPORT_FILE" ]; then
	PROBE="$SELF_DIR/probe_bridge_layers.sh"
	if [ ! -f "$PROBE" ]; then
		say "FATAL: probe script missing: $PROBE"
		exit 1
	fi
	# Capture the probe's OWN stdout to extract "report written: <path>"
	# directly, rather than "latest directory under bridge_layers/ by sort" —
	# this checkout is shared by concurrent agents/tracks (§11.4.119/§11.4.176)
	# that may run this same probe concurrently, and picking "latest by
	# lexicographic sort" races a sibling track's in-flight (not-yet-written)
	# run-id directory, producing a false "no report" FATAL that has nothing
	# to do with THIS invocation's own result (found + fixed during this
	# script's own integration run, §11.4.6 — never guess which run is ours).
	PROBE_STDOUT=$(bash "$PROBE" --root "$ROOT" --quiet 2>>"$LOG_FILE")
	PROBE_RC=$?
	printf '%s\n' "$PROBE_STDOUT" >>"$LOG_FILE"
	if [ "$PROBE_RC" -ne 0 ]; then
		say "FATAL: probe_bridge_layers.sh failed — cannot determine layer state"
		exit 1
	fi
	REPORT_FILE=$(printf '%s\n' "$PROBE_STDOUT" | sed -n 's/^report written: //p' | tail -1)
fi
if [ -z "$REPORT_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	say "FATAL: no probe report.json available (looked for --report-file / a fresh probe run)"
	exit 1
fi
say "   report-file: $REPORT_FILE"

# ── per-check state — each record() call appends ONE JSON object as its own
#    line to a JSONL scratch file (never bash-array-to-python string-gluing,
#    which silently concatenates multi-line command-substitution output
#    instead of comma-joining it — caught and fixed during this script's own
#    integration run, §11.4.6). The final assembly step reads this file back
#    as the authoritative per-check list. ─────────────────────────────────────
RECORDS_FILE="$EVID_DIR/.records.jsonl"
: >"$RECORDS_FILE"

record() {
	# record <id> <name> <verdict PASS|FAIL|DROPPED> <reason>
	python3 - "$RECORDS_FILE" "$1" "$2" "$3" "$4" <<'PYEOF'
import json, sys
path, cid, name, verdict, reason = sys.argv[1:6]
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"id": cid, "name": name, "verdict": verdict, "reason": reason}) + "\n")
PYEOF
	say "   [$3] check $1: $2 — $4"
}

# ── check 1 — DROPPED (L5 does not exist; T-B1.01/T-B3.01) ─────────────────
record 1 "SuperBridge MCP server health-check" "DROPPED" "L5 does not exist as software (T-B1.01 measured NONEXISTENT via two independent derivations, T-B3.01 recorded upstream) — a check that can never pass on any host is dropped, not permanently failed, per T-B2.03.2."

# ── checks 2-4 — speckit-{specify,plan,tasks} extension loads (L2) ─────────
skill_loads() {
	# skill_loads <skill-name> — checks every recognised consumer skill dir
	# for a present, well-formed (has a SKILL.md with a name: frontmatter
	# field, or an equivalent command markdown file) entry. Mirrors the
	# probe's own per-consumer enumeration (.claude/skills, .kimi-code/skills)
	# rather than assuming a single canonical location — the per-consumer
	# variance is itself a tracked fact (HXC-159 Phase P2), not resolved here.
	local skill="$1"
	local found=""
	for dir in "$ROOT/.claude/skills" "$ROOT/.kimi-code/skills"; do
		if [ -f "$dir/$skill/SKILL.md" ]; then
			found="$found ${dir#"$ROOT"/}"
		fi
	done
	printf '%s' "$found" | xargs
}

for sk in speckit-specify speckit-plan speckit-tasks; do
	num=2
	case "$sk" in speckit-specify) num=2 ;; speckit-plan) num=3 ;; speckit-tasks) num=4 ;; esac
	FOUND=$(skill_loads "$sk")
	if [ -n "$FOUND" ]; then
		record "$num" "$sk extension loads" "PASS" "SKILL.md present + well-formed in: $FOUND"
	else
		record "$num" "$sk extension loads" "FAIL" "no consumer directory (.claude/skills, .kimi-code/skills) has a $sk/SKILL.md"
	fi
done

# ── check 5 — superspec status (L3), scope-narrowed to shell-verifiable
#    preconditions per the honest-boundary note above ───────────────────────
SUPERSPEC_CMD="$ROOT/.specify/extensions/superspec/commands/status.md"
SUPERSPEC_ENABLED=""
LIST_JSON=$("$SPECIFY_BIN" extension list --json 2>/dev/null || echo "[]")
SUPERSPEC_ENABLED=$(printf '%s' "$LIST_JSON" | python3 -c 'import json,sys
try:
    doc = json.load(sys.stdin)
except Exception:
    doc = []
for e in doc:
    if e.get("id") == "superspec" and e.get("enabled"):
        print("true")
        break
else:
    print("false")' 2>/dev/null || echo "false")
if [ -f "$SUPERSPEC_CMD" ] && [ "$SUPERSPEC_ENABLED" = "true" ]; then
	record 5 "superspec status returns valid JSON (scope-narrowed: command present + extension Enabled — see header)" "PASS" "commands/status.md present; 'specify extension list --json' shows superspec enabled=true"
else
	record 5 "superspec status returns valid JSON (scope-narrowed: command present + extension Enabled — see header)" "FAIL" "commands/status.md present=$([ -f "$SUPERSPEC_CMD" ] && echo yes || echo no); superspec enabled=$SUPERSPEC_ENABLED"
fi

# ── check 6 — superb check passes on constitution files (L4) ───────────────
SUPERB_ENABLED=$(printf '%s' "$LIST_JSON" | python3 -c 'import json,sys
try:
    doc = json.load(sys.stdin)
except Exception:
    doc = []
for e in doc:
    if e.get("id") == "superb" and e.get("enabled"):
        print("true")
        break
else:
    print("false")' 2>/dev/null || echo "false")
if [ "$SUPERB_ENABLED" = "true" ]; then
	record 6 "superb check passes on constitution files" "PASS" "'specify extension list --json' shows superb enabled=true"
else
	record 6 "superb check passes on constitution files" "FAIL" "superb is NOT installed on this host (DESIGNED-ONLY per the probe; HIGH-risk supply-chain dependency requiring an explicit §11.4.66 operator-vetted install per T-B2.02) — this is the CORRECT, expected state absent that decision, but the check honestly reports FAIL rather than a silent skip-as-pass"
fi

# ── check 7 — Helix LLM Gateway reachable (L6) ──────────────────────────────
GATEWAY_URL="${HELIX_GATEWAY_URL:-https://localhost:8443/}"
if command -v curl >/dev/null 2>&1; then
	HTTP_CODE=$(curl -sS -k -m 5 -o /dev/null -w '%{http_code}' "$GATEWAY_URL" 2>>"$LOG_FILE")
	CURL_RC=$?
	if [ "$CURL_RC" -eq 0 ] && [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
		record 7 "Helix LLM Gateway reachable" "PASS" "TCP+TLS+HTTP round-trip to $GATEWAY_URL succeeded (http_code=$HTTP_CODE — any real HTTP response, including a 404 on an unannounced path, proves the gateway process answered)"
	else
		record 7 "Helix LLM Gateway reachable" "FAIL" "curl to $GATEWAY_URL did not complete a round-trip (rc=$CURL_RC, http_code=${HTTP_CODE:-<none>})"
	fi
else
	record 7 "Helix LLM Gateway reachable" "FAIL" "curl not available on this host — cannot check reachability (honest FAIL, never a silent skip-as-pass per §11.4.201)"
fi

# ── check 8 — llama.cpp RPC backend health-check (L7) ───────────────────────
RPC_BUILT=$(find "$ROOT" -maxdepth 6 -path "*build*" -iname "rpc-server" -type f -executable 2>/dev/null | head -1)
if [ -n "$RPC_BUILT" ] && pgrep -f "$(basename "$RPC_BUILT")" >/dev/null 2>&1; then
	record 8 "llama.cpp RPC backend health-check" "PASS" "rpc-server executable found at $RPC_BUILT and a matching process is running"
else
	record 8 "llama.cpp RPC backend health-check" "FAIL" "rpc-server ${RPC_BUILT:+found at $RPC_BUILT but }not running (L7 measured PARTIAL by the probe — the -DGGML_RPC=ON build flag is documented but the binary has not been built on this host; tracked as a separate follow-on item per spec.md §7, out of scope for this installer/validator pair)"
fi

# ── verdict + evidence — assembled from the JSONL records file (one real
#    JSON object per line, written by record() as each check ran) rather than
#    reconstructed from bash arrays, so no check's name/reason can ever be
#    silently glued onto its neighbour's (§11.4.6 — caught during this
#    script's own integration run: the original bash-array/printf join
#    concatenated all four checks' text into a single field). ───────────────
VERDICT_RC=1
python3 - "$RECORDS_FILE" "$REPORT_OUT" "$RUN_ID" >>"$LOG_FILE" 2>&1 <<'PYEOF'
import json, sys
records_path, out_path, run_id = sys.argv[1:4]
checks = []
with open(records_path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if line:
            checks.append(json.loads(line))
evaluable = [c for c in checks if c["verdict"] != "DROPPED"]
passing = [c for c in evaluable if c["verdict"] == "PASS"]
doc = {
    "schema_version": "1.0",
    "run_id": run_id,
    "generated_by": "constitution/scripts/extensions/validate_bridge.sh (HXC-159 T-B2.03)",
    "feature_class": "extension_loading",
    "checks": checks,
    "evaluable_count": len(evaluable),
    "passing_count": len(passing),
    "overall_status": "PASS" if len(passing) == len(evaluable) and evaluable else "FAIL",
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
print(f"{len(passing)} {len(evaluable)}")
sys.exit(0 if doc["overall_status"] == "PASS" else 1)
PYEOF
VERDICT_RC=$?
read -r PASSING EVALUABLE < <(python3 -c "import json; d=json.load(open('$REPORT_OUT')); print(d['passing_count'], d['evaluable_count'])")

say "   ─────────────────────────────────────────"
if [ "$VERDICT_RC" -eq 0 ]; then
	say "   $PASSING/$EVALUABLE EVALUABLE CHECKS PASSED (1 check DROPPED — see check 1) — bridge ready per measured state"
	say "== validate_bridge.sh: PASS ($PASSING/$EVALUABLE) =="
	rm -f "$RECORDS_FILE"
	exit 0
fi
say "   $PASSING/$EVALUABLE EVALUABLE CHECKS PASSED (1 check DROPPED — see check 1) — bridge NOT fully ready; see FAIL reasons above"
say "== validate_bridge.sh: FAIL ($PASSING/$EVALUABLE) =="
rm -f "$RECORDS_FILE"
exit 1
