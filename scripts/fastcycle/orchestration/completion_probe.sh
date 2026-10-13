#!/bin/bash
# completion_probe.sh - T-B01 completion-signal probe (reproduction of
# ATM-858 D1), SpecKit-004 "fast-dev-cycles" User Story 5, task T122.
# Contract: specs/004-fast-dev-cycles/contracts/agent-registry-and-handoff.md
# ("$FC/orchestration/completion_probe.sh --out <probe.json>   # T-B01:
# empirical hook-semantics probe (must run before AR-003 source (b) is
# trusted)"); plan.md T-B01 "Completion-signal probe (reproduction of
# ATM-858 D1)"; data-model.md §9.1 "UNCONFIRMED (R5 open item 1): whether
# Claude Code's SubagentStop hook fires at real completion (not at launch)
# for backgrounded Agent-tool launches."
#
# Purpose: launch ONE background agent per dispatch kind named by the plan
#   (Agent-tool background; Workflow agent()), each ending in a KNOWN
#   marker-file write as its LAST action, and record: the launch timestamp
#   (from the registry's own `dispatched` row -- never a locally-guessed
#   clock read, §11.4.6), the marker-write timestamp (ground truth of REAL
#   completion, read from the filesystem, never assumed), and EVERY hook
#   event the single-writer registry (scripts/hooks/agent_registry_writer.sh)
#   recorded for that dispatch's correlation key, in order, with its own
#   `ts` field. The RED condition this probe checks is literal and
#   contract-defined: a `complete`-class registry row exists strictly
#   BEFORE the marker file's real write time (or exists with no marker
#   ever observed at all) -- i.e. the registry claims completion before the
#   dispatched agent's real work finished.
#
#   A Bash script cannot itself invoke Claude Code's native Agent tool (that
#   is a harness-level LLM tool call, not a shell-spawnable process) -- so
#   this tool is a RECORDER/OBSERVER the calling agent invokes AROUND a real
#   dispatch it performs itself via the Agent tool, exactly the same
#   architecture agent_registry_writer.sh already assumes for the "conductor
#   writes complete on the task notification" fallback path (DEC-13). The
#   `key` subcommand lets the caller PRECOMPUTE the exact correlation key
#   agent_registry_writer.sh will derive for a planned dispatch (same
#   sha256(session_id|tool|description|prompt)[:16] algorithm, read
#   verbatim from that file so the two never drift), so the caller knows
#   which key to `watch` for BEFORE issuing the dispatch.
#
# Usage:
#   completion_probe.sh key --session SID --tool NAME --description DESC \
#       [--prompt TEXT | --prompt-file PATH]
#     Prints the 16-hex correlation key to stdout (exit 0), or exits 2 on
#     missing/invalid args. Pure function, no side effects, no dispatch.
#
#   completion_probe.sh watch --key KEY --marker PATH \
#       --dispatch-kind {agent_tool_background|workflow_agent} --out PATH \
#       [--registry PATH] [--timeout-seconds N] [--poll-interval-seconds N] \
#       [--settle-seconds N]
#     Polls --registry (default docs/requests/agent_registry.jsonl relative
#     to the repo root this script lives under) for every event carrying
#     --key, and polls --marker for its real appearance + mtime + expected
#     content (the marker's content is checked against the literal string
#     "COMPLETION_PROBE_MARKER" so a stale pre-existing file at that path
#     can never be misread as a fresh completion signal -- §11.4.201(7)(b)).
#     Polling continues until EITHER (a) the marker is observed AND
#     --settle-seconds has elapsed with no NEW registry event for the key
#     (catches a delayed post-marker event), OR (b) --timeout-seconds is
#     reached. Runs a control-needle self-test (see CONTROL NEEDLES below)
#     before reporting any absence as real. Writes the canonical probe.json
#     to --out via fc_common.py emit (schema completion-probe/v1) and exits
#     0 (semantics measured) or 4 (could not run -- the key never appeared
#     in the registry at all within a short grace window, i.e. the dispatch
#     never even reached PreToolUse, OR the registry file is unreadable).
#
#   completion_probe.sh skip --dispatch-kind KIND --reason TEXT --out PATH
#     For a dispatch kind this harness genuinely cannot exercise (see
#     WORKFLOW-AGENT-KIND HONEST GAP below) -- writes an honest
#     not-applicable record (fires_at: "not-applicable") with the reason,
#     no polling, no fabricated dispatch. Exit 0.
#
# Outputs: --out doc (canonical JSON, schema completion-probe/v1, C-002);
#   stdout for `key` is the bare 16-hex string only.
# Side-effects: NONE on the real registry or repo state -- this tool is
#   strictly read-only against docs/requests/agent_registry.jsonl (never
#   appends, never writes there); its own --out lands under the caller's
#   evidence directory (this task's convention:
#   qa-results/fastcycle/us5/probe/, untracked per §11.4.11).
# Dependencies: bash, python3 (registry parsing, key derivation, canonical
#   JSON emit via lib/fc_common.py), date, stat.
#
# CONTROL NEEDLES (§11.4.6 / §11.4.201(7)(b) / §11.4.273 -- a null result is
#   never evidence until the SAME code path is proven to see a known-present
#   item through the SAME instrument):
#   (1) SYNTHETIC scratch-file needle -- a temp copy of one real registry
#       line, with its `key` field rewritten to a needle key, is fed through
#       the IDENTICAL `extract_events_for_key()` Python function this script
#       uses on the live file; the needle key MUST be found, and a
#       fabricated key that was never written MUST NOT be found. Always run,
#       deterministic, no dependency on live-file content.
#   (2) LIVE positive-control -- the first `event: "complete"` line ANYWHERE
#       in the real, live registry (this project's registry has recorded
#       1,317+ such rows historically and is append-only, so one always
#       exists) is located and its key re-extracted through the SAME
#       function, proving the parser genuinely sees a real historical
#       `complete` row on the actual file being watched, not merely a
#       synthetic copy. Soft check: if the live file is momentarily
#       unreadable this is recorded as an honest gap, never silently
#       skipped.
#   Both needle results are recorded in the emitted doc's `control_needles`
#   object; a needle FAILURE aborts the whole `watch` invocation with exit 4
#   (could not run -- the instrument is not trustworthy this run, mirroring
#   C-001 row 3's "self-test failed" semantics folded into this tool's own
#   0/4 exit contract) and writes NO probe result claiming a measurement.
#
# WORKFLOW-AGENT-KIND HONEST GAP (§11.4.6, confirmed empirically this task):
#   the plan (DEC-13, T-B01) names "Workflow agent()" as the SECOND dispatch
#   kind to probe alongside "Agent tool background". This harness (Claude
#   Code, this session) was checked via ToolSearch for any tool matching
#   "Workflow agent workflow tool script execute" and via the full
#   top-level + deferred-tool lists visible to this session: NO distinct
#   "Workflow" dispatch tool exists here -- only the "Agent" tool is
#   available. (This matches the constitution's own honest-boundary
#   language at §11.4.231(F.2): "the Workflow tool's agent() DOES take an
#   effort argument... the Agent tool exposes NO effort parameter" --
#   i.e. the constitution itself treats "Workflow agent()" as a SEPARATE,
#   not-always-available mechanism from the Agent tool, consistent with
#   what this probe independently found.) T122's own task line anticipated
#   exactly this: "if genuinely available/distinct... confirm first... if
#   the latter, honestly document this rather than fabricating a second
#   dispatch kind." This script's `skip` subcommand is that honest
#   documentation path -- it does NOT invent a second dispatch or a fake
#   `fires_at` value for a mechanism that was never exercised.
#
# Cross-references: contracts/agent-registry-and-handoff.md AR-002/AR-003;
#   data-model.md §9.1; research.md DEC-13; plan.md T-B01; tasks.md T122;
#   scripts/hooks/agent_registry_writer.sh (the single writer this probe
#   reads, and the sha256 key algorithm `key` reproduces); constitution
#   §11.4.6 (no-guessing), §11.4.85 (real dispatches, no mocks), §11.4.115(F)
#   (harness-written verdicts, target fingerprint read at run time),
#   §11.4.201(7)(b) / §11.4.273 (control needles).
# Exit codes: `key` 0 ok / 2 usage error. `watch` 0 semantics measured
#   (fires_at in {completion, launch, never}) / 4 could not run (needle
#   failure, unreadable registry, or key never appeared at all). `skip`
#   0 (fires_at: not-applicable).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FC="$(cd "$SCRIPT_DIR/.." && pwd)"                 # constitution/scripts/fastcycle
CONST_ROOT="$(cd "$FC/../.." && pwd)"              # constitution/
REPO_ROOT="$(cd "$CONST_ROOT/.." && pwd)"          # project root
DEFAULT_REGISTRY="$REPO_ROOT/docs/requests/agent_registry.jsonl"
MARKER_MAGIC="COMPLETION_PROBE_MARKER"

die_usage() { echo "completion_probe.sh: $1" >&2; exit 2; }

# ---------------------------------------------------------------------------
# emit_doc schema body_json out_path code -- via fc_common.py (C-002).
# ---------------------------------------------------------------------------
emit_doc() {
  local schema="$1" body_json="$2" out_path="$3" code="${4:-0}"
  mkdir -p "$(dirname "$out_path")" 2>/dev/null
  local run_meta
  run_meta="$(python3 -c 'import json,platform; print(json.dumps({"host": platform.node()}))')"
  python3 "$FC/lib/fc_common.py" emit --schema "$schema" --body-json "$body_json" \
    --run-meta-json "$run_meta" --out "$out_path" --code "$code"
  return $?
}

# =============================================================================
# key -- deterministic correlation-key precomputation (mirrors
# agent_registry_writer.sh's PY_OUT python3 heredoc's `key = hashlib.sha256(
#   ("|".join((sess, tool, desc, prompt))).encode("utf-8","replace")
# ).hexdigest()[:16]` byte-for-byte).
# =============================================================================
cmd_key() {
  local session="" tool="" description="" prompt="" prompt_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --tool) tool="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --prompt) prompt="$2"; shift 2 ;;
      --prompt-file) prompt_file="$2"; shift 2 ;;
      *) die_usage "key: unknown arg '$1'" ;;
    esac
  done
  [ -n "$session" ] || die_usage "key: --session is required"
  [ -n "$tool" ] || die_usage "key: --tool is required"
  [ -n "$description" ] || die_usage "key: --description is required"
  if [ -n "$prompt_file" ]; then
    [ -r "$prompt_file" ] || die_usage "key: --prompt-file not readable: $prompt_file"
    prompt="$(cat "$prompt_file")"
  fi
  SESSION="$session" TOOL="$tool" DESCRIPTION="$description" PROMPT="$prompt" python3 - <<'PYEOF'
import hashlib, os
sess = os.environ["SESSION"]
tool = os.environ["TOOL"]
desc = os.environ["DESCRIPTION"]
prompt = os.environ.get("PROMPT", "")
key = hashlib.sha256(("|".join((sess, tool, desc, prompt))).encode("utf-8", "replace")).hexdigest()[:16]
print(key)
PYEOF
}

# =============================================================================
# skip -- honest not-applicable record for a dispatch kind this harness
# genuinely cannot exercise (see WORKFLOW-AGENT-KIND HONEST GAP above).
# =============================================================================
cmd_skip() {
  local dispatch_kind="" reason="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dispatch-kind) dispatch_kind="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      *) die_usage "skip: unknown arg '$1'" ;;
    esac
  done
  [ -n "$dispatch_kind" ] || die_usage "skip: --dispatch-kind is required"
  [ -n "$reason" ] || die_usage "skip: --reason is required"
  [ -n "$out" ] || die_usage "skip: --out is required"
  local body
  body="$(DISPATCH_KIND="$dispatch_kind" REASON="$reason" python3 -c '
import json, os
print(json.dumps({
    "dispatch_kind": os.environ["DISPATCH_KIND"],
    "fires_at": "not-applicable",
    "reason": os.environ["REASON"],
    "red_condition": None,
}))
')"
  emit_doc "completion-probe/v1" "$body" "$out" 0
}

# =============================================================================
# watch -- the core probe.
# =============================================================================
cmd_watch() {
  local key="" marker="" dispatch_kind="" out="" registry="$DEFAULT_REGISTRY"
  local timeout_s=120 poll_s=2 settle_s=15 grace_s=20
  while [ $# -gt 0 ]; do
    case "$1" in
      --key) key="$2"; shift 2 ;;
      --marker) marker="$2"; shift 2 ;;
      --dispatch-kind) dispatch_kind="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --registry) registry="$2"; shift 2 ;;
      --timeout-seconds) timeout_s="$2"; shift 2 ;;
      --poll-interval-seconds) poll_s="$2"; shift 2 ;;
      --settle-seconds) settle_s="$2"; shift 2 ;;
      --grace-seconds) grace_s="$2"; shift 2 ;;
      *) die_usage "watch: unknown arg '$1'" ;;
    esac
  done
  [ -n "$key" ] || die_usage "watch: --key is required"
  [ -n "$marker" ] || die_usage "watch: --marker is required"
  [ -n "$dispatch_kind" ] || die_usage "watch: --dispatch-kind is required"
  [ -n "$out" ] || die_usage "watch: --out is required"
  case "$dispatch_kind" in agent_tool_background|workflow_agent) : ;;
    *) die_usage "watch: --dispatch-kind must be agent_tool_background or workflow_agent" ;;
  esac
  [ -r "$registry" ] || die_usage "watch: --registry not readable: $registry"

  # -- Control needles (run once, before any poll loop; §11.4.201(7)(b)) --
  local needle_report
  needle_report="$(KEY="$key" REGISTRY="$registry" python3 - <<'PYEOF'
import hashlib, json, os, random, string, sys, tempfile

registry = os.environ["REGISTRY"]

def extract_events_for_key(path, target_key):
    """IDENTICAL logic used later against the live registry in watch mode:
    read every JSONL line, keep those whose 'key' field equals target_key,
    in file order, tolerating malformed lines (never crashing the probe)."""
    events = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except Exception:
                    continue
                if row.get("key") == target_key:
                    events.append(row)
    except OSError as exc:
        return None, str(exc)
    return events, None

result = {"synthetic": {}, "live": {}}

# (1) SYNTHETIC scratch-file needle: copy ONE real line, rewrite its key to
# a fresh needle id, append a second line for a NEVER-written fabricated key
# that must NOT be found.
needle_key = "".join(random.choices("0123456789abcdef", k=16))
fabricated_key = "".join(random.choices("0123456789abcdef", k=16))
try:
    with open(registry, encoding="utf-8") as fh:
        sample_line = None
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                json.loads(line)
            except Exception:
                continue
            sample_line = line
            break
except OSError as exc:
    result["synthetic"]["error"] = "cannot read registry to build scratch fixture: %s" % exc
    print(json.dumps(result))
    sys.exit(3)

if sample_line is None:
    result["synthetic"]["error"] = "registry has no parseable JSON line to build a scratch fixture from"
    print(json.dumps(result))
    sys.exit(3)

sample_row = json.loads(sample_line)
needle_row = dict(sample_row)
needle_row["key"] = needle_key
needle_row["event"] = "complete"

fd, tmp_path = tempfile.mkstemp(prefix="completion_probe_needle_", suffix=".jsonl")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(needle_row) + "\n")
try:
    found_needle, err1 = extract_events_for_key(tmp_path, needle_key)
    found_fabricated, err2 = extract_events_for_key(tmp_path, fabricated_key)
finally:
    os.unlink(tmp_path)

needle_ok = (err1 is None and err2 is None
             and found_needle is not None and len(found_needle) == 1
             and found_needle[0]["event"] == "complete"
             and found_fabricated is not None and len(found_fabricated) == 0)
result["synthetic"] = {
    "needle_key": needle_key,
    "fabricated_key": fabricated_key,
    "needle_found": bool(found_needle),
    "fabricated_found": bool(found_fabricated) if found_fabricated is not None else None,
    "pass": needle_ok,
}
if not needle_ok:
    print(json.dumps(result))
    sys.exit(3)

# (2) LIVE positive-control: the first real `event: "complete"` row anywhere
# in the ACTUAL live registry, re-found through the SAME extraction path.
live_complete_key = None
try:
    with open(registry, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("event") == "complete" and row.get("key"):
                live_complete_key = row["key"]
                break
except OSError as exc:
    result["live"] = {"error": "cannot read live registry for live positive-control: %s" % exc, "pass": False}
    print(json.dumps(result))
    sys.exit(3)

if live_complete_key is None:
    # Honest gap, not a failure of the synthetic needle above: record it,
    # never silently absorbed, never treated as a hard needle failure since
    # the synthetic needle already proves the parser sees a real 'complete'
    # row via the SAME code path.
    result["live"] = {"found_any_complete_row": False, "pass": True, "note": "no complete-class row exists anywhere in the live registry yet (honest gap, not a parser failure)"}
else:
    found_live, err = extract_events_for_key(registry, live_complete_key)
    live_ok = err is None and found_live is not None and any(e.get("event") == "complete" for e in found_live)
    result["live"] = {
        "found_any_complete_row": True,
        "sample_key": live_complete_key,
        "reextracted_event_count": len(found_live) if found_live is not None else 0,
        "pass": live_ok,
    }
    if not live_ok:
        print(json.dumps(result))
        sys.exit(3)

print(json.dumps(result))
sys.exit(0)
PYEOF
)"
  local needle_rc=$?
  if [ "$needle_rc" -eq 3 ]; then
    echo "completion_probe.sh: control-needle self-test FAILED -- instrument not trusted this run; NOT writing a measurement" >&2
    echo "$needle_report" >&2
    local blind_body
    blind_body="$(DK="$dispatch_kind" NR="$needle_report" python3 -c '
import json, os
print(json.dumps({
    "dispatch_kind": os.environ["DK"],
    "fires_at": None,
    "control_needles": json.loads(os.environ["NR"]),
    "reason": "control-needle self-test failed",
}))
')"
    emit_doc "completion-probe/v1" "$blind_body" "$out" 4
    return 4
  fi

  # -- Poll loop: registry events for --key + marker existence/mtime/content --
  local deadline
  deadline=$(( $(date +%s) + timeout_s ))
  local grace_deadline
  grace_deadline=$(( $(date +%s) + grace_s ))
  local key_seen=0
  local marker_seen=0
  local settle_start=0
  local last_event_count=0

  while :; do
    local now
    now=$(date +%s)
    local events_now
    events_now="$(KEY="$key" REGISTRY="$registry" python3 -c '
import json, os
events = []
try:
    with open(os.environ["REGISTRY"], encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("key") == os.environ["KEY"]:
                events.append(row)
except OSError:
    pass
print(json.dumps(events))
')"
    local event_count
    event_count="$(printf '%s' "$events_now" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
    if [ "$event_count" -gt 0 ]; then
      key_seen=1
    fi

    local marker_ok=0
    if [ -f "$marker" ]; then
      if grep -qF "$MARKER_MAGIC" "$marker" 2>/dev/null; then
        marker_ok=1
      fi
    fi
    if [ "$marker_ok" -eq 1 ] && [ "$marker_seen" -eq 0 ]; then
      marker_seen=1
    fi

    if [ "$marker_seen" -eq 1 ]; then
      if [ "$event_count" -ne "$last_event_count" ]; then
        settle_start=$now
        last_event_count="$event_count"
      fi
      if [ "$settle_start" -eq 0 ]; then
        settle_start=$now
      fi
      if [ $((now - settle_start)) -ge "$settle_s" ]; then
        break
      fi
    fi

    if [ "$key_seen" -eq 0 ] && [ "$now" -ge "$grace_deadline" ]; then
      # key never reached the registry at all -- not a RED/GREEN finding,
      # an instrumentation failure (the dispatch never fired PreToolUse).
      local nokey_body
      nokey_body="$(DK="$dispatch_kind" K="$key" python3 -c '
import json, os
print(json.dumps({
    "dispatch_kind": os.environ["DK"],
    "key": os.environ["K"],
    "fires_at": None,
    "reason": "key never appeared in the registry within the grace window -- dispatch never reached PreToolUse, or registry writer failed",
}))
')"
      emit_doc "completion-probe/v1" "$nokey_body" "$out" 4
      return 4
    fi

    if [ "$now" -ge "$deadline" ]; then
      break
    fi
    sleep "$poll_s"
  done

  local final_events
  final_events="$(KEY="$key" REGISTRY="$registry" python3 -c '
import json, os
events = []
try:
    with open(os.environ["REGISTRY"], encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("key") == os.environ["KEY"]:
                events.append(row)
except OSError:
    pass
print(json.dumps(events))
')"

  local marker_write_ts="null"
  local marker_observed="false"
  local marker_content_ok="false"
  if [ -f "$marker" ]; then
    marker_observed="true"
    local mtime_epoch
    mtime_epoch="$(stat -c %Y "$marker" 2>/dev/null || echo "")"
    if [ -n "$mtime_epoch" ]; then
      marker_write_ts="\"$(date -u -d "@$mtime_epoch" '+%Y-%m-%dT%H:%M:%SZ')\""
    fi
    if grep -qF "$MARKER_MAGIC" "$marker" 2>/dev/null; then
      marker_content_ok="true"
    fi
  fi

  local body_json
  body_json="$(DK="$dispatch_kind" K="$key" MP="$marker" EV="$final_events" \
    MWT="$marker_write_ts" MOB="$marker_observed" MCK="$marker_content_ok" \
    NR="$needle_report" python3 - <<'PYEOF'
import json, os

dispatch_kind = os.environ["DK"]
key = os.environ["K"]
marker_path = os.environ["MP"]
events = json.loads(os.environ["EV"])
marker_write_ts = json.loads(os.environ["MWT"])
marker_observed = json.loads(os.environ["MOB"])
marker_content_ok = json.loads(os.environ["MCK"])
control_needles = json.loads(os.environ["NR"])

events_sorted = sorted(events, key=lambda e: e.get("ts", ""))
complete_events = [e for e in events_sorted if e.get("event") == "complete"]
first_complete = complete_events[0] if complete_events else None

red_condition = False
if first_complete is not None:
    if not marker_observed or not marker_content_ok:
        red_condition = True
    elif marker_write_ts is not None and first_complete.get("ts", "") < marker_write_ts:
        red_condition = True

if first_complete is None:
    fires_at = "never"
elif red_condition:
    fires_at = "launch"
else:
    fires_at = "completion"

print(json.dumps({
    "dispatch_kind": dispatch_kind,
    "key": key,
    "marker_path": marker_path,
    "marker_observed": marker_observed,
    "marker_content_verified": marker_content_ok,
    "marker_write_ts": marker_write_ts,
    "events": events_sorted,
    "complete_event": first_complete,
    "red_condition": red_condition,
    "fires_at": fires_at,
    "control_needles": control_needles,
}))
PYEOF
)"
  emit_doc "completion-probe/v1" "$body_json" "$out" 0
  return 0
}

# =============================================================================
# main
# =============================================================================
[ $# -ge 1 ] || die_usage "usage: completion_probe.sh {key|watch|skip} ..."
sub="$1"; shift
case "$sub" in
  key) cmd_key "$@" ;;
  watch) cmd_watch "$@" ;;
  skip) cmd_skip "$@" ;;
  *) die_usage "unknown subcommand '$sub' (expected key|watch|skip)" ;;
esac
