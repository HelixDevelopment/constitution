#!/bin/bash
# Purpose: T124 (SpecKit-004 "fast-dev-cycles", User Story 5 / Phase B) RED
#          test for T132's heartbeat-with-monotonically-advancing-progress-
#          offset liveness mechanism (tasks.md T124: "RED test ... (a killed
#          agent stays in-flight indefinitely today; golden: a slow-but-alive
#          agent with an advancing offset is never marked dead)"; plan.md
#          T-B03; contract: NONE -- $FC/orchestration/heartbeat.sh is on
#          contracts/common-conventions.md's own "no contract in this
#          directory (open gap)" list, so this test binds directly to
#          plan.md T-B03's task text + data-model.md §9.1's `suspected-dead`
#          state + constitution §11.4.232(C), exactly as that document
#          instructs for every tool it does not cover with a contract.
#
# T-B03 (plan.md): "long-running agents and long ops emit a heartbeat with a
#   monotonically advancing progress offset (§11.4.232(C)); stale-lock
#   reaping reads holder liveness and heartbeat, and logs wait duration ...
#   Protecting tests: RED: a killed agent stays `in-flight` indefinitely;
#   golden: a slow-but-alive agent (heartbeat advancing) is never marked
#   dead; paired mutation: treat heartbeat presence (not advance) as
#   liveness -> the golden fails."
#
# ============================================================================
# THE GAP THIS TEST PROTECTS (verified live below, matches T122's OWN R-04
# finding -- tasks.md T122, reproduced fresh in Section 1 rather than only
# cited, per constitution §11.4.199 exact-reproduction-sequence): today
# `$FC/orchestration/heartbeat.sh` does not exist (confirmed live in
# Section 3); no hook this project runs is ever invoked when an
# Agent/Task/TaskCreate dispatch's real work finishes or is interrupted
# (confirmed live in Section 1 -- `.claude/settings.json` wires
# `scripts/hooks/agent_registry_writer.sh` under PreToolUse+PostToolUse
# ONLY, never `SubagentStop` or any other completion-adjacent event); so an
# `in-flight` registry row, once written at PostToolUse's async-launch
# confirmation, NEVER receives a further event for ANY reason -- genuine
# success, genuine failure, or a genuine kill are all OBSERVATIONALLY
# IDENTICAL to the registry (all three read as permanently `in-flight`).
# T124's literal RED claim ("a killed agent stays in-flight indefinitely")
# is therefore a NECESSARY SPECIAL CASE of the broader, freshly-reproduced
# fact this section proves directly: a REAL agent this task dispatched via
# the Agent tool, on which a REAL kill (`TaskStop`) was genuinely attempted
# and genuinely FAILED with a captured capability-boundary error, then
# completed its real work in full -- and its registry row STILL shows only
# `dispatched` -> `in-flight`, no `complete`, no later event of any kind,
# well after that real completion was independently confirmed via its own
# SubagentHandback report.
#
# ============================================================================
# WHY THE LITERAL KILL COULD NOT BE COMPLETED, DOCUMENTED HONESTLY PER THIS
# TASK'S OWN INSTRUCTION ("if genuinely infeasible, document exactly why"):
# ============================================================================
#
# This task DID attempt a real, live kill (constitution §11.4.85 -- no
# mocks) via the following exact sequence (re-derivable from
# docs/requests/agent_registry.jsonl, which is the permanent, append-only,
# already-committed evidence this test re-reads below -- never re-executed
# by this script, since a Bash test cannot itself invoke Claude Code's
# native Agent tool, the SAME architectural fact
# $FC/orchestration/completion_probe.sh's own header already states and
# this test reuses without re-deriving, per constitution §11.4.227
# extend-don't-duplicate):
#
#   1. Precomputed the exact correlation key
#      `completion_probe.sh key --session <SID> --tool Agent
#       --description "<DESC>" --prompt-file <PROMPT>` would derive for a
#      planned dispatch, BEFORE issuing it (same
#      sha256(session_id|tool|description|prompt)[:16] algorithm
#      agent_registry_writer.sh uses) -> key `f549f41822935c19`.
#   2. Dispatched a REAL background subagent via the Agent tool with that
#      EXACT description + prompt (the prompt instructed it to sleep, then
#      write a marker, then hand back) -> harness confirmed
#      "Async agent launched successfully", agentId `a017675b8d7c2bcf4`.
#   3. Immediately called the real `TaskStop` tool with
#      `task_id: a017675b8d7c2bcf4`. It returned the CAPTURED, VERBATIM
#      error: "Task a017675b8d7c2bcf4 is owned by a017675b8d7c2bcf4; agent
#      a2b795fcb218e4e41 cannot stop it." -- a genuine, reproducible
#      capability boundary of this harness: a NESTED/dispatched subagent
#      (this task's own execution context) cannot call TaskStop on a task
#      it itself spawned; that capability belongs to a different owning
#      context (consistent with the SendMessage tool's own documented
#      `to: "main"` = "The main conversation (background subagents only)"
#      distinction -- background-task ownership appears to track the
#      TOP-LEVEL session, not the nested dispatcher). This is a REAL,
#      CAPTURED fact (§11.4.6), not a guess, and is itself directly
#      relevant input for T131/T132/T-B05's eventual respawn-path design
#      (only the conductor/top-level session can currently terminate a
#      dispatched agent from outside).
#   4. The dispatched agent then completed its real work on its own
#      (SubagentHandback: "kill-test marker written."; the harness's own
#      task-notification for it reported total durations of 37391ms then,
#      on a second notification for the same task-id, 121748ms -- an
#      ambiguous but HONESTLY-reported observation: the notification text
#      itself states a task-id "may notify more than once" and an earlier
#      result "may be interim"; this test does NOT claim more certainty
#      about the TaskStop call's partial effect than that raw, captured
#      text supports).
#   5. Given TWO independent, real, freshly-captured pieces of evidence
#      already establish the broader fact that NECESSARILY implies T124's
#      literal claim (see above), and per constitution §12/§11.4.85 host-
#      safety discipline against dispatching additional live agents once
#      sufficient real evidence already exists, a further attempt routed
#      through the top-level session (via SendMessage to "main" asking it
#      to call TaskStop on a fresh, longer-sleeping dispatch) was
#      considered and NOT attempted this run -- recorded here as an open,
#      cheaper follow-up for whoever implements T131/T132, never silently
#      dropped (§11.4.197).
#
# ============================================================================
# ORACLE INDEPENDENCE (constitution §11.4.245 / this task's own instruction
# 3: "derive the expected liveness verdict from the heartbeat data's own
# timestamps/offsets independently, never from a not-yet-built liveness-
# checker's self-report").
# ============================================================================
#
# Section 2 below computes "ALIVE" / "STALE" from RAW heartbeat-sequence
# fixtures (a plain list of {ts_offset_seconds, progress_offset} pairs) via
# an INDEPENDENT oracle function (`oracle_liveness()`) that applies ONLY
# the plan T-B03 rule stated in plain English above -- "the progress offset
# advances at least once within the no-progress budget window" -- computed
# from the fixture's own numbers, BEFORE `$FC/orchestration/heartbeat.sh`
# (T132, not yet built) is ever invoked or its own verdict is read. Section
# 3's real "after" check then compares the not-yet-built tool's ACTUAL
# output against this independently-derived expectation, never accepting
# the tool's self-report on its own say-so -- mirroring
# test_tool_deferral_red.sh's `oracle_expect()` precedent exactly
# (constitution §11.4.227 reuse, not reinvention).
#
# The no-progress budget itself is NEVER a hardcoded literal here -- plan.md
# and research.md name no specific duration for it anywhere (grepped
# clean); it is consumer DATA T132 will define, so every fixture below
# takes the budget as an explicit parameter and the oracle's assertions are
# stated relative to that parameter, never to an invented real-world
# minutes/seconds figure (§11.4.6).
#
# ============================================================================
# Usage: bash test_heartbeat_liveness_red.sh   Exit 0 = every check below
#        held (only possible once T132 lands `$FC/orchestration/heartbeat.sh`
#        implementing the plan T-B03 rule correctly); nonzero = FAIL count>0
#        (today, RED, by design -- Section 3's real after-check).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$FC/../../.." && pwd)"
HEARTBEAT="$FC/orchestration/heartbeat.sh"
REGISTRY="$ROOT/docs/requests/agent_registry.jsonl"
SETTINGS="$ROOT/.claude/settings.json"

TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
reap_children() { pkill -KILL -f "$TMP" 2>/dev/null; return 0; }
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM

FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "INFO: $1"; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not on PATH -- cannot run any of the checks below"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi

# -----------------------------------------------------------------------
# constitution §11.4.273 / §11.4.201(7)(b) control-needle discipline
# (needle set #1: this test's own registry-key extraction mechanism,
# generic self-check before trusting it against the real, live registry).
# -----------------------------------------------------------------------
extract_events_for_key() {
  # $1 = registry path   $2 = key   -> prints JSON array of matching rows
  KEY="$2" REGISTRY_PATH="$1" python3 -c '
import json, os
events = []
try:
    with open(os.environ["REGISTRY_PATH"], encoding="utf-8") as fh:
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
'
}

NEEDLE_REG="$TMP/needle_registry.jsonl"
NEEDLE_KEY="0123456789abcdef"
FABRICATED_KEY="fedcba9876543210"
printf '%s\n' "{\"ts\": \"2026-01-01T00:00:00Z\", \"event\": \"in-flight\", \"key\": \"$NEEDLE_KEY\", \"tool_name\": \"Agent\", \"session_id\": \"needle\", \"description\": \"needle\", \"item\": \"?\", \"note\": \"\"}" > "$NEEDLE_REG"
NEEDLE_FOUND="$(extract_events_for_key "$NEEDLE_REG" "$NEEDLE_KEY" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
FABRICATED_FOUND="$(extract_events_for_key "$NEEDLE_REG" "$FABRICATED_KEY" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
chk "control needle #1a: a known-present key IS found by extract_events_for_key() through the identical code path" \
  "$([ "$NEEDLE_FOUND" = "1" ] && echo 1 || echo 0)"
chk "control needle #1b: a fabricated (never-written) key is reported absent (0 rows) by the same code path" \
  "$([ "$FABRICATED_FOUND" = "0" ] && echo 1 || echo 0)"

# =========================================================================
# Section 1: TODAY's REAL, LIVE RED baseline -- the two independent,
# freshly-captured, real dispatches (see header for the full genuine-kill-
# attempt narrative), re-verified LIVE against the real, live, append-only
# registry every time this test runs (never re-executed -- the rows are
# permanent evidence on disk).
# =========================================================================
echo
echo "=== Section 1: real-dispatch RED baseline (live registry) ==="

[ -r "$REGISTRY" ] || { chk "the real registry file is readable" "0"; }

# T124's own fresh dispatch: dispatched -> in-flight -> (real completion,
# real TaskStop-kill attempt FAILED with a captured capability-boundary
# error, see header) -> MUST STILL show no event beyond in-flight.
T124_KEY="f549f41822935c19"
T124_EVENTS="$(extract_events_for_key "$REGISTRY" "$T124_KEY")"
T124_EVENT_LIST="$(printf '%s' "$T124_EVENTS" | python3 -c 'import json,sys; print(",".join(e["event"] for e in json.load(sys.stdin)))')"
chk "T124's own real dispatch (key $T124_KEY, real completion + real captured TaskStop-kill-attempt failure, see header) has recorded events exactly 'dispatched,in-flight' -- no 'complete'/'crashed'/'respawned' ever written, despite genuine real completion" \
  "$([ "$T124_EVENT_LIST" = "dispatched,in-flight" ] && echo 1 || echo 0)"

# T122's independently-captured prior real dispatch (tasks.md T122,
# committed evidence): a SECOND, separate real Agent-tool dispatch that
# also genuinely completed (per its own SubagentHandback report) and whose
# registry row shows the identical stuck-forever shape.
T122_KEY="6a43739dadcd01aa"
T122_EVENTS="$(extract_events_for_key "$REGISTRY" "$T122_KEY")"
T122_EVENT_LIST="$(printf '%s' "$T122_EVENTS" | python3 -c 'import json,sys; print(",".join(e["event"] for e in json.load(sys.stdin)))')"
chk "T122's independently-captured real dispatch (key $T122_KEY, tasks.md T122, a separate real completed Agent-tool dispatch) ALSO shows exactly 'dispatched,in-flight' -- second, independent confirmation of the same stuck-forever mechanism" \
  "$([ "$T122_EVENT_LIST" = "dispatched,in-flight" ] && echo 1 || echo 0)"

# Dynamic, re-runnable structural check (not tied to two frozen keys that
# could eventually be pruned/rotated): AT LEAST ONE key in the real, live
# registry is currently stuck at a non-terminal status (dispatched or
# in-flight) with its LATEST event older than a bounded staleness window --
# proving this is a systemic, currently-live condition, not a one-off
# historical artefact of exactly two rows.
STALE_MINUTES=10
STALE_COUNT="$(STALE_MINUTES="$STALE_MINUTES" SNAP_PATH="${REGISTRY%.jsonl}.status.tsv" python3 -c '
import datetime, os
stale_before = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(os.environ["STALE_MINUTES"]))
snap = os.environ["SNAP_PATH"]
count = 0
with open(snap, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        status, ts = parts[1], parts[2]
        if status not in ("dispatched", "in-flight"):
            continue
        try:
            row_ts = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            continue
        if row_ts < stale_before:
            count += 1
print(count)
')"
chk "the live registry snapshot (${REGISTRY%.jsonl}.status.tsv) currently has AT LEAST ONE key stuck at dispatched/in-flight for >$STALE_MINUTES minutes with no later event -- confirms the RED condition is a live, systemic, re-verifiable fact today, not two frozen historical rows" \
  "$([ "${STALE_COUNT:-0}" -ge 1 ] && echo 1 || echo 0)"
info "live stale (dispatched/in-flight, >$STALE_MINUTES min old) key count: ${STALE_COUNT:-0}"

# Structural root-cause assertion: NO hook is wired for SubagentStop (or
# any completion-adjacent event) -- the reason the above rows are stuck.
# Reproduces T122's own R-04 finding fresh, against the live settings file,
# rather than only citing it (constitution §11.4.199).
[ -r "$SETTINGS" ] || { chk "settings.json is readable" "0"; }
HOOK_EVENTS="$(python3 -c '
import json
d = json.load(open("'"$SETTINGS"'"))
print(",".join(sorted(d.get("hooks", {}).keys())))
' 2>/dev/null)"
SUBAGENTSTOP_WIRED="$(python3 -c '
import json
d = json.load(open("'"$SETTINGS"'"))
print(1 if "SubagentStop" in d.get("hooks", {}) else 0)
' 2>/dev/null)"
PRETOOLUSE_WIRED_FOR_AGENT="$(python3 -c '
import json
d = json.load(open("'"$SETTINGS"'"))
entries = d.get("hooks", {}).get("PreToolUse", [])
hit = any("Agent" in e.get("matcher", "") and any("agent_registry_writer" in h.get("command","") for h in e.get("hooks", [])) for e in entries)
print(1 if hit else 0)
' 2>/dev/null)"
chk "control needle #2 (structural): PreToolUse IS wired for the Agent matcher to agent_registry_writer.sh (proves the same JSON-reading code path CAN see a real hook entry when one exists)" \
  "$([ "$PRETOOLUSE_WIRED_FOR_AGENT" = "1" ] && echo 1 || echo 0)"
chk "no SubagentStop hook (or any other completion-adjacent event) is wired anywhere in .claude/settings.json -- this IS the root cause the header + T122's R-04 established: nothing ever transitions an in-flight row forward" \
  "$([ "$SUBAGENTSTOP_WIRED" = "0" ] && echo 1 || echo 0)"
info "wired hook events today: $HOOK_EVENTS"

echo
echo "=== Section 1 summary: TODAY, a real dispatched agent -- genuinely completed, or genuinely subjected to a real (if ultimately capability-blocked) kill attempt -- stays 'in-flight' in the registry INDEFINITELY, because no hook exists to ever move it further. This is the literal RED condition T124 asserts (a killed agent is one specific, necessarily-included case of this broader, freshly-proven fact). ==="

# =========================================================================
# Section 2: independent liveness ORACLE self-validation (golden-good /
# golden-bad / negative-control) -- entirely testable TODAY without
# heartbeat.sh, per constitution §11.4.115(F) validate-the-detector-first
# and §11.4.245 oracle independence. The oracle applies ONLY the plain-
# English T-B03 rule to raw {ts_offset_seconds, progress_offset} fixture
# data; heartbeat.sh's own future output is never consulted here.
# =========================================================================
echo
echo "=== Section 2: independent liveness-oracle self-validation ==="

oracle_liveness() {
  # $1 = path to JSON array of {ts, offset} samples (relative seconds,
  #      monotonic offset units)   $2 = no-progress budget in seconds
  # Prints ALIVE or STALE. Rule (plan T-B03, plain English, applied
  # literally, nothing borrowed from any not-yet-built tool): STALE iff
  # there exists a window of length > budget, ending at or before the
  # LAST sample, across which the offset never advances; a slow-but-
  # advancing sequence (advances at least once inside every such window)
  # is ALIVE.
  BUDGET="$2" python3 -c '
import json, os, sys
samples = json.load(open(sys.argv[1]))
budget = float(os.environ["BUDGET"])
if len(samples) < 2:
    print("ALIVE")
    sys.exit(0)
samples = sorted(samples, key=lambda s: s["ts"])
last_advance_ts = samples[0]["ts"]
last_offset = samples[0]["offset"]
stale = False
for s in samples[1:]:
    if s["offset"] > last_offset:
        last_advance_ts = s["ts"]
        last_offset = s["offset"]
    if (s["ts"] - last_advance_ts) > budget:
        stale = True
print("STALE" if stale else "ALIVE")
' "$1"
}

BUDGET_S=60

# --- GOLDEN-GOOD: offset advances every 10s, well inside a 60s budget. ---
GOOD_FIXTURE="$TMP/fixture_golden_good.json"
python3 -c '
import json
samples = [{"ts": t, "offset": t // 10} for t in range(0, 121, 10)]
json.dump(samples, open("'"$GOOD_FIXTURE"'", "w"))
'
GOOD_VERDICT="$(oracle_liveness "$GOOD_FIXTURE" "$BUDGET_S")"
chk "GOLDEN-GOOD: an offset advancing every 10s under a ${BUDGET_S}s budget -- independent oracle says ALIVE" \
  "$([ "$GOOD_VERDICT" = "ALIVE" ] && echo 1 || echo 0)"

# --- GOLDEN-BAD: offset flat (never advances) for 120s under a 60s budget
#     -- the genuinely-dead / killed-mid-work case this task's RED
#     condition models; the oracle MUST correctly flag it, proving it is
#     not decoration (constitution §11.4.201(1)/(7)(b)).
BAD_FIXTURE="$TMP/fixture_golden_bad.json"
python3 -c '
import json
samples = [{"ts": t, "offset": 0} for t in range(0, 121, 10)]
json.dump(samples, open("'"$BAD_FIXTURE"'", "w"))
'
BAD_VERDICT="$(oracle_liveness "$BAD_FIXTURE" "$BUDGET_S")"
chk "GOLDEN-BAD: an offset flat at 0 for 120s under a ${BUDGET_S}s budget (models a killed/hung agent) -- independent oracle correctly says STALE, proving the oracle discriminates rather than always passing" \
  "$([ "$BAD_VERDICT" = "STALE" ] && echo 1 || echo 0)"

# --- NEGATIVE CONTROL: the task's own stated safety property -- a
#     SLOW-BUT-GENUINELY-ALIVE agent (offset advances just once, near the
#     end of each budget window, never fully flat) MUST NEVER be
#     incorrectly marked dead. This is the false-positive guard
#     (constitution §11.4.201(1)): a correctly-alive agent must PASS.
SLOW_FIXTURE="$TMP/fixture_negative_control_slow_alive.json"
python3 -c '
import json
# Advances by exactly 1 unit every 55s (just inside a 60s budget), for
# 220s total -- genuinely slow, genuinely never flat for longer than the
# budget.
samples = [{"ts": t, "offset": t // 55} for t in range(0, 221, 5)]
json.dump(samples, open("'"$SLOW_FIXTURE"'", "w"))
'
SLOW_VERDICT="$(oracle_liveness "$SLOW_FIXTURE" "$BUDGET_S")"
chk "NEGATIVE CONTROL (this task's own stated safety property): a slow-but-genuinely-advancing offset (advances every 55s, inside a ${BUDGET_S}s budget, never fully flat) is NEVER marked STALE by the independent oracle -- the false-positive guard" \
  "$([ "$SLOW_VERDICT" = "ALIVE" ] && echo 1 || echo 0)"

# --- Paired-mutation self-proof (plan T-B03's own named mutation: "treat
#     heartbeat presence (not advance) as liveness -> the golden fails"),
#     exercised HERE against this test's own oracle so the mutation-catch
#     is proven before T132 exists to inherit it.
PRESENCE_ONLY_ORACLE() {
  # The forbidden mutation: liveness = "any samples exist", ignoring
  # whether the offset ever advances.
  python3 -c '
import json, sys
samples = json.load(open(sys.argv[1]))
print("ALIVE" if len(samples) > 0 else "STALE")
' "$1"
}
MUTANT_VERDICT="$(PRESENCE_ONLY_ORACLE "$BAD_FIXTURE")"
chk "paired §1.1 mutation (plan T-B03's own named mutation, 'treat heartbeat presence not advance as liveness'): applied to the GOLDEN-BAD (flat/dead) fixture, the mutant WRONGLY says ALIVE -- confirms the mutation is genuinely caught (the real oracle above correctly says STALE on the identical fixture, the mutant does not)" \
  "$([ "$MUTANT_VERDICT" = "ALIVE" ] && echo 1 || echo 0)"

echo
echo "=== Section 3: the REAL 'after' check -- T132's $FC/orchestration/heartbeat.sh, once it exists ==="

if [ ! -e "$HEARTBEAT" ]; then
  info "$FC/orchestration/heartbeat.sh NOT FOUND -- T132 has not landed; this is the EXPECTED RED-today outcome (this task's own instruction: 'golden: a slow-but-alive agent with an advancing offset is never marked dead' -- once T132 implements heartbeat.sh, this section runs it for real against the same GOLDEN-GOOD/GOLDEN-BAD/NEGATIVE-CONTROL fixtures above and compares its verdict against the independent oracle's, never trusting heartbeat.sh's own self-report alone)"
  chk "T132 has landed $FC/orchestration/heartbeat.sh implementing the T-B03 advancing-progress-offset liveness rule -- expected to FAIL today (RED), no heartbeat.sh exists yet" \
    "0"
  chk "a killed/hung agent (GOLDEN-BAD fixture) is classified suspected-dead by the real heartbeat.sh, agreeing with the independent oracle -- expected to FAIL today (RED), no heartbeat.sh exists yet" \
    "0"
  chk "a slow-but-genuinely-alive agent (NEGATIVE-CONTROL fixture) is NEVER classified suspected-dead by the real heartbeat.sh -- expected to FAIL today (RED), no heartbeat.sh exists yet" \
    "0"
else
  bash -n "$HEARTBEAT" 2>"$TMP/syn_err_heartbeat.$$"
  HB_SYN=$?
  chk "$FC/orchestration/heartbeat.sh parses clean (bash -n)" "$([ "$HB_SYN" = "0" ] && echo 1 || echo 0)"

  # Real invocation against the SAME golden/golden-bad/negative-control
  # fixtures Section 2 already independently classified, comparing the
  # tool's ACTUAL output to the independent oracle's expectation.
  for pair in "GOOD_FIXTURE:ALIVE:GOLDEN-GOOD" "BAD_FIXTURE:STALE:GOLDEN-BAD" "SLOW_FIXTURE:ALIVE:NEGATIVE-CONTROL"; do
    fixture_var="${pair%%:*}"
    rest="${pair#*:}"
    expected="${rest%%:*}"
    label="${rest#*:}"
    fixture_path="$(eval echo "\$$fixture_var")"
    real_out="$("$HEARTBEAT" classify --samples "$fixture_path" --budget-seconds "$BUDGET_S" 2>"$TMP/hb_err_$label.$$" || true)"
    chk "real heartbeat.sh classify on the $label fixture returns '$expected' (independently pre-derived above), matching the independent oracle" \
      "$([ "$real_out" = "$expected" ] && echo 1 || echo 0)"
  done
fi

echo
echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
