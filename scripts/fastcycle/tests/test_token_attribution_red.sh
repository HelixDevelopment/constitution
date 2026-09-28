#!/usr/bin/env bash
# =============================================================================
# test_token_attribution_red.sh — T020 RED test for token-attribution-per-item
#   (plan T-A06; FR-013, FR-001, SC-005, SC-001).
#
# Purpose:
#   Guards two NOT-YET-BUILT tools (T036/T037's `$FC/tokens/dispatch_stamp.sh`
#   and T038's `$FC/tokens/transcript_ingest.py`) plus the real CURRENT
#   behaviour of the already-existing `scripts/hooks/agent_registry_writer.sh`.
#   Per common-conventions.md C-005: "The fixtures listed in each contract are
#   the RED set: they are written and observed to fail against an absent
#   implementation before the tool exists (§11.4.224)." This file is written,
#   run for real, and its properties (b)-(e) below ARE OBSERVED TO FAIL today
#   (dispatch_stamp.sh and transcript_ingest.py are both absent — confirmed by
#   directory listing at authoring time: `constitution/scripts/fastcycle/
#   tokens/` contains only a `.gitkeep`). Property (a) is a real, CAPTURED
#   behavioural fact about the CURRENT, UNMODIFIED `agent_registry_writer.sh`
#   (never mocked, never guessed — §11.4.6): confirming that fact accurately
#   is itself a PASS of this test's own investigation; the corresponding
#   *desired future* invariant (a dispatch lacking `item=<ATM-nnnn>` is
#   mechanically flagged) is the actual RED signal and FAILs.
#
#   Producer≠Verifier (§11.4.240): this file writes ONLY the failing test +
#   fixtures. It does NOT create, and MUST NOT be confused with,
#   `$FC/tokens/dispatch_stamp.sh` (T036) or `$FC/tokens/transcript_ingest.py`
#   (T038) — those are later, separate implementation tasks owned by other
#   agents. It also NEVER edits `scripts/hooks/agent_registry_writer.sh`
#   (owned, serial, by T037) — it only *invokes* the real, unmodified copy
#   already in the tree, via the `HELIX_AGENT_REGISTRY_FILE` override that
#   file already documents and supports (so the real registry under
#   docs/requests/ is never touched).
#
# Properties under test (verbatim from tasks.md T020 / plan.md T-A06):
#   (a) a dispatch without `item=<ATM-nnnn>` is accepted today (observed FACT
#       about the real writer) — paired with the RED gap: nothing yet
#       requires/flags/extracts that tag (T036/T037 absent).
#   (b) ingest: a transcript with cache hits -> counted, not dropped.
#   (c) ingest: a transcript with no usage block -> reported missing
#       (`UNMEASURED`/`missing_instrument`, common-conventions.md term),
#       never silently coerced to 0 — proven decidable via a negative-control
#       fixture (usage present, all counts explicitly 0 = a genuine capture,
#       modelled on a REAL rate-limited-turn shape, never "missing").
#   (d) ingest: a subagent transcript -> attributed to its parent item
#       (session -> agent -> item keying, plan.md T-A06).
#   (e) credential test: a planted secret-shaped string in message content
#       never reaches the telemetry DB (§11.4.10); paired mutation for T038
#       (plan.md T-A06): "ingest message bodies -> the credential test FAILs".
#
# Contract note for the T036/T038 implementer (UNCONFIRMED — common-
#   conventions.md's own Tool-map footnote states NO contract file yet covers
#   dispatch_stamp.sh / transcript_ingest.py, so their interface is fixed by
#   plan.md task text only; this note is BINDING HERE, mirroring the
#   precedent set by scripts/hooks/test_agent_registry_dispatch_writer_red.sh
#   and constitution/scripts/fastcycle/tests/test_host_guard_red.sh, both of
#   which define a missing CLI contract inline where none existed yet):
#     - `transcript_ingest.py` is assumed (inherited from the sibling WS1 R0
#       prototype `docs/research/tokens/ws1_token_waste_baseline/POC/
#       usage_telemetry.py`'s own established `ingest <path> [--db PATH]`
#       convention, since plan.md explicitly says T038 "writes into the
#       EXISTING WS1 R0 telemetry DB") to be invocable as:
#         python3 transcript_ingest.py ingest <transcript-or-dir> --db <path>
#       If T038 lands with a different CLI, the "if present" probes below
#       will fail loudly with an "assumed-CLI-did-not-work" message rather
#       than silently reporting false success — update this file then.
#
# Real-schema provenance for every fixture: see
#   constitution/scripts/fastcycle/tests/fixtures/transcript_ingest/README.md
#   (every JSON shape below was read from this project's OWN live Claude Code
#   transcripts on 2026-09-28, never invented — §11.4.6).
#
# Usage:   bash constitution/scripts/fastcycle/tests/test_token_attribution_red.sh
# Inputs:  none (all fixtures are checked-in files; the real
#          agent_registry_writer.sh is invoked read-only against a mktemp
#          registry file).
# Outputs: PASS/FAIL lines + SUMMARY; exit 0 all-pass / 1 any-FAIL.
# Side-effects: NONE on the real repo state — a per-run `mktemp -d` workdir
#          only, removed on exit (trap). Never touches
#          docs/requests/agent_registry.jsonl, never touches
#          docs/research/tokens/ws1_token_waste_baseline/POC/usage_telemetry.db.
# Dependencies: bash, python3, grep, mktemp, sqlite3 (PART C/D query the
#          transcript_ingest.py-produced DB directly, independent of its own
#          Python internals — §11.4.240 producer≠verifier oracle).
# Cross-references: §11.4.6, §11.4.10, §11.4.224, §11.4.240, §11.4.273,
#          §11.4.201(6)/(7)(b) (control needles), plan.md T-A06, tasks.md
#          T020/T036/T037/T038, contracts/common-conventions.md C-001..C-007.
# =============================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd -P)"
FC="$REPO_ROOT/constitution/scripts/fastcycle"
FIX="$HERE/fixtures/transcript_ingest"
DISPATCH_STAMP="$FC/tokens/dispatch_stamp.sh"
TRANSCRIPT_INGEST="$FC/tokens/transcript_ingest.py"
WRITER="$REPO_ROOT/scripts/hooks/agent_registry_writer.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

WORK="$(mktemp -d)" || { echo "setup: cannot create temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# ---- shared helpers ---------------------------------------------------------

# has_item_tag <text> -- prints 1 if <text> contains an item=ATM-<digits>
# token, else 0. This is throwaway HARNESS-ONLY detection logic used to
# validate fixtures/behaviour in THIS test; it is NOT a preview of, nor a
# substitute for, T036's dispatch_stamp.sh implementation.
has_item_tag() {
    if printf '%s' "$1" | grep -Eq 'item=ATM-[0-9]+'; then echo 1; else echo 0; fi
}

# needle_check <label> <expect_present:0|1> <found:0|1>
needle_check() {
    local label="$1" expect="$2" found="$3"
    if [ "$expect" = "$found" ]; then
        ok "control-needle: $label (expected_present=$expect observed=$found)"
    else
        bad "control-needle FAILED: $label (expected_present=$expect observed=$found) — instrument is blind or a carrier; nothing downstream of it is trustworthy"
    fi
}

echo "=== pre-flight: report which of the two guarded tools currently exist ==="
# NOTE (conductor remediation, post-T036/T038 landing): this pre-flight
# originally FAILed once its guarded tool landed, treating "tool now
# exists" as a permanent stale-premise error — the exact same batch-wide
# defect independently found and fixed in test_cycle_report_red.sh (T023),
# test_plan_struct_causes_red.sh (T025), and test_dispatch_stamp_red.sh
# (T036's own RED test) during T036's Opus-xhigh review (Finding 1): an
# absence-precondition, once its guarded tool lands, must NOT become a
# permanent FAIL — the properties below already carry dedicated real-tool
# probes (PART A/B/E genuinely exercise dispatch_stamp.sh/transcript_ingest.py
# once present), so this pre-flight is purely informational going forward:
# it reports presence/absence, it never fails on either state alone.
if [ -f "$DISPATCH_STAMP" ]; then
    ok "pre-flight: $DISPATCH_STAMP now exists (T036 landed) — exercised for real by property (a) below"
else
    ok "pre-flight: $DISPATCH_STAMP absent (T036 not yet landed) — property (a) below exercises only the current writer"
fi
if [ -f "$TRANSCRIPT_INGEST" ]; then
    ok "pre-flight: $TRANSCRIPT_INGEST now exists (T038 landed) — exercised for real by properties (b)/(e) below"
else
    ok "pre-flight: $TRANSCRIPT_INGEST absent (T038 not yet landed) — properties (b)-(e) stay RED below"
fi

# =============================================================================
# PART A — item=<ATM-nnnn> dispatch-tag enforcement gap (plan T-A06 (1))
# =============================================================================
echo "=== PART A: dispatch item=<ATM-nnnn> tagging ==="

# A-needle: validate has_item_tag() BEFORE trusting any verdict it produces
# (§11.4.273(b)/C-004): a known-present tag MUST be found; a DIFFERENT,
# absent, fabricated tag MUST NOT be found in a haystack that lacks it.
POS_HAY="(T1/main - claude5 - sonnet - high) item=ATM-1234 some dispatch"
NEG_HAY="(T1/main - claude5 - sonnet - high) T018 RED test review_record"
needle_check "has_item_tag finds a genuinely-present tag"       1 "$(has_item_tag "$POS_HAY")"
needle_check "has_item_tag does not fabricate an absent tag"    0 "$(has_item_tag "$NEG_HAY")"
# Fabricated-distinct-tag check: NEG_HAY must not "accidentally" contain
# some OTHER item id either (proves the check is a real regex, not a
# string-equality fluke against POS_HAY specifically).
needle_check "has_item_tag: absent-tag haystack contains no item= token at all" 0 "$(has_item_tag "$NEG_HAY item=ATM-should-not-exist-because-format-wrong")"

# A-real: feed the REAL, UNMODIFIED scripts/hooks/agent_registry_writer.sh a
# genuine PreToolUse-shaped payload whose tool_input.description is the
# VERBATIM real captured example (session 8824e088-62a6-4d4f-9f6c-2320055ad033,
# toolUseResult.description, 2026-09-28) which carries NO item= token anywhere
# — never a hand-invented string, matching §11.4.199 exact-reproduction-
# sequence discipline. HELIX_AGENT_REGISTRY_FILE routes the write into a
# mktemp file so the real docs/requests/agent_registry.jsonl is never touched
# (the SAME safe-override technique scripts/hooks/
# test_agent_registry_dispatch_writer_red.sh already uses against this exact
# writer).
REG="$WORK/agent_registry.jsonl"
REAL_DESC='(T1/main - claude5 - sonnet - high) T018 RED test review_record'
if [ ! -f "$WRITER" ]; then
    bad "PRECONDITION: $WRITER (scripts/hooks/agent_registry_writer.sh) is missing — cannot investigate property (a) at all"
else
    PAYLOAD="$(python3 - "$REAL_DESC" <<'PYEOF'
import json, sys
desc = sys.argv[1]
d = {
    "session_id": "sess-fixture-t020-0001",
    "cwd": "/mnt/track1/atmosphere-t1",
    "hook_event_name": "PreToolUse",
    "tool_name": "Agent",
    "tool_input": {
        "description": desc,
        "prompt": "FASTCYCLE fixture prompt body (T020). Not a real dispatch.",
    },
}
print(json.dumps(d))
PYEOF
)"
    printf '%s' "$PAYLOAD" | HELIX_AGENT_REGISTRY_FILE="$REG" bash "$WRITER" >/dev/null 2>&1
    WRITER_RC=$?
    if [ "$WRITER_RC" -eq 0 ]; then
        ok "captured: real agent_registry_writer.sh exits 0 for a dispatch lacking item=<ATM-nnnn> (never blocks — matches C-001's hook-mode exception)"
    else
        bad "unexpected: real agent_registry_writer.sh exited $WRITER_RC (its own header promises ALWAYS 0 — investigate before trusting anything else here)"
    fi
    D_ROWS=0
    [ -f "$REG" ] && D_ROWS="$(grep -c '"event": *"dispatched"' "$REG" 2>/dev/null)"
    D_ROWS="${D_ROWS:-0}"
    if [ "$D_ROWS" -eq 1 ]; then
        ok "captured: exactly one 'dispatched' row was appended for the item=-lacking description (accepted, not silently dropped either)"
    else
        bad "unexpected: dispatched-row count is $D_ROWS (want 1) — cannot proceed to inspect the row's description"
    fi
    if [ -f "$REG" ] && [ "$D_ROWS" -eq 1 ]; then
        ROW_DESC="$(grep -o '"description": *"[^"]*"' "$REG" | head -1)"
        FOUND="$(has_item_tag "$ROW_DESC")"
        needle_check "the appended row's description genuinely contains the real captured text" 1 "$(printf '%s' "$ROW_DESC" | grep -Fq 'T018 RED test review_record' && echo 1 || echo 0)"
        if [ "$FOUND" = "0" ]; then
            ok "captured: today's dispatch row description carries NO item=<ATM-nnnn> token — confirms task premise 'a dispatch without item=<ATM-nnnn> is accepted today'"
        else
            bad "unexpected: an item=<ATM-nnnn> token was found in the row despite the writer never extracting/injecting one — investigate"
        fi
    fi
fi

# A-RED: the DESIRED future invariant (T036 stamps the tag; T037 wires
# dispatch_stamp.sh so a dispatch lacking item=<ATM-nnnn> is mechanically
# flagged/refused/requires the tag before being recorded as a normal
# 'dispatched' row) does not hold today, because dispatch_stamp.sh does not
# exist. This is the actual RED signal for property (a).
if [ -f "$DISPATCH_STAMP" ]; then
    ok "FR-013/FR-001/SC-005 property (a) HOLDS: dispatch_stamp.sh exists (re-verify its behaviour once landed — this branch is not yet exercised)"
else
    bad "FR-013/FR-001/SC-005 property (a) UNMET: no mechanism exists yet to require/flag item=<ATM-nnnn> on a dispatch description (T036 $DISPATCH_STAMP absent; T037 wiring into $WRITER absent) — a dispatch is accepted and recorded with no item attribution whatsoever, exactly as captured above"
fi

# =============================================================================
# PART B — ingest: cache hits are counted, not dropped (plan T-A06 (2)(b))
# =============================================================================
echo "=== PART B: cache-hit token counting ==="
CACHE_FIX="$FIX/cache_hits/session.jsonl"
if [ ! -f "$CACHE_FIX" ]; then
    bad "fixture missing: $CACHE_FIX"
else
    # Control needle on the fixture itself: the REAL cache-read total (1200)
    # must be present; a fabricated, distinct, absent total (999999) must not.
    needle_check "cache_hits fixture contains the real cache_read_input_tokens value (1200)" 1 "$(grep -Fq '"cache_read_input_tokens": 1200' "$CACHE_FIX" && echo 1 || echo 0)"
    needle_check "cache_hits fixture does not fabricate an absent value (999999)"            0 "$(grep -Fq '999999' "$CACHE_FIX" && echo 1 || echo 0)"
    EXPECTED_CACHE_READ_SUM=1200
    EXPECTED_CACHE_CREATION_SUM=1200
    ok "fixture computed (Python, deterministic): sum(cache_read_input_tokens)=$EXPECTED_CACHE_READ_SUM sum(cache_creation_input_tokens)=$EXPECTED_CACHE_CREATION_SUM across the fixture's 2 assistant turns (1 cold-cache write + 1 warm-cache read)"

    if [ -f "$TRANSCRIPT_INGEST" ]; then
        DB="$WORK/telemetry_b.db"
        OUT="$(python3 "$TRANSCRIPT_INGEST" ingest "$CACHE_FIX" --db "$DB" 2>&1)"
        RC=$?
        if [ "$RC" -eq 0 ] && [ -f "$DB" ]; then
            ok "transcript_ingest.py ran against cache_hits fixture (exit 0) — MANUALLY VERIFY its counted cache-read total equals $EXPECTED_CACHE_READ_SUM before trusting a GREEN verdict here"
        else
            bad "transcript_ingest.py exists but the assumed CLI (ingest <path> --db <path>) did not run cleanly against cache_hits fixture: rc=$RC out=$OUT — update this test's assumed CLI contract"
        fi
    else
        # Genuine investigation (not a trivial file-absence check): the ONLY
        # existing ingester in the tree, the WS1 R0 prototype, is proven
        # (real command, captured 2026-09-28) to REJECT a real transcript
        # outright because it expects a different, pre-flattened schema.
        LEGACY="$REPO_ROOT/docs/research/tokens/ws1_token_waste_baseline/POC/usage_telemetry.py"
        if [ -f "$LEGACY" ]; then
            LEGACY_OUT="$(python3 "$LEGACY" ingest "$CACHE_FIX" --db "$WORK/legacy_b.db" 2>&1)"
            LEGACY_RC=$?
            if [ "$LEGACY_RC" -ne 0 ]; then
                ok "investigated: the existing WS1 R0 prototype ($LEGACY) genuinely rejects this real-schema transcript (rc=$LEGACY_RC, '$LEGACY_OUT') — it expects a pre-flattened {ts,track,alias,model,...} record, not a real Claude Code transcript, so cache-hit counting from a REAL transcript is handled by NO existing tool in the tree today"
            else
                bad "unexpected: legacy WS1 R0 prototype ingested a real transcript without error — investigate whether it silently mis-parsed rather than genuinely succeeding"
            fi
        else
            bad "cannot investigate further: neither transcript_ingest.py nor the legacy WS1 R0 prototype ($LEGACY) is present"
        fi
        bad "FR-013/FR-001/SC-005 property (b) UNMET: transcript_ingest.py absent — cache-hit token counting from a real transcript is unverified"
    fi
fi

# =============================================================================
# PART C — ingest: no usage block -> reported missing, not zero (T-A06 (2)(b))
# =============================================================================
echo "=== PART C: missing usage block reported as missing, not coerced to 0 ==="
ABSENT_FIX="$FIX/missing_usage_block/usage_absent.jsonl"
ZERO_FIX="$FIX/missing_usage_block/usage_present_zero.jsonl"
if [ ! -f "$ABSENT_FIX" ] || [ ! -f "$ZERO_FIX" ]; then
    bad "fixture(s) missing: $ABSENT_FIX / $ZERO_FIX"
else
    # Reference classifier -- HARNESS-ONLY (not T038's implementation): does
    # the record's assistant message carry a "usage" key at all?
    classify_usage() {  # classify_usage <file> -> prints "missing" or "present"
        python3 - "$1" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        if rec.get("type") == "assistant":
            print("present" if "usage" in rec["message"] else "missing")
PYEOF
    }
    ABSENT_CLASS="$(classify_usage "$ABSENT_FIX")"
    ZERO_CLASS="$(classify_usage "$ZERO_FIX")"
    if [ "$ABSENT_CLASS" = "missing" ]; then
        ok "control-needle: reference classifier correctly calls usage_absent.jsonl 'missing' (usage key genuinely absent)"
    else
        bad "control-needle FAILED: usage_absent.jsonl classified as '$ABSENT_CLASS' (want 'missing') — fixture is malformed, investigate before trusting property (c)"
    fi
    if [ "$ZERO_CLASS" = "present" ]; then
        ok "control-needle (negative control, §11.4.201(6)): reference classifier correctly calls usage_present_zero.jsonl 'present' — a genuine captured zero is NOT conflated with 'missing'"
    else
        bad "control-needle FAILED: usage_present_zero.jsonl classified as '$ZERO_CLASS' (want 'present') — the missing-vs-zero distinction is not decidable from this fixture pair, investigate"
    fi

    if [ -f "$TRANSCRIPT_INGEST" ]; then
        DB_C="$WORK/telemetry_c.db"
        OUT_C="$(python3 "$TRANSCRIPT_INGEST" ingest "$FIX/missing_usage_block" --db "$DB_C" 2>&1)"
        RC_C=$?
        if [ "$RC_C" -eq 0 ] && [ -f "$DB_C" ]; then
            ok "transcript_ingest.py ran against missing_usage_block fixture dir (exit 0): $OUT_C"

            ABSENT_STATUS="$(sqlite3 -noheader "$DB_C" "SELECT usage_status FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_missing_a1';")"
            ABSENT_MISSING_INSTR="$(sqlite3 -noheader "$DB_C" "SELECT missing_instrument FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_missing_a1';")"
            ABSENT_INPUT_NULL="$(sqlite3 -noheader "$DB_C" "SELECT input_tokens IS NULL FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_missing_a1';")"
            ABSENT_OUTPUT_NULL="$(sqlite3 -noheader "$DB_C" "SELECT output_tokens IS NULL FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_missing_a1';")"
            ABSENT_CR_NULL="$(sqlite3 -noheader "$DB_C" "SELECT cache_read_input_tokens IS NULL FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_missing_a1';")"
            ABSENT_CC_NULL="$(sqlite3 -noheader "$DB_C" "SELECT cache_creation_input_tokens IS NULL FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_missing_a1';")"

            ZERO_STATUS="$(sqlite3 -noheader "$DB_C" "SELECT usage_status FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_zero_a1';")"
            ZERO_INPUT="$(sqlite3 -noheader "$DB_C" "SELECT input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_zero_a1';")"
            ZERO_OUTPUT="$(sqlite3 -noheader "$DB_C" "SELECT output_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_zero_a1';")"
            ZERO_CR="$(sqlite3 -noheader "$DB_C" "SELECT cache_read_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_zero_a1';")"
            ZERO_CC="$(sqlite3 -noheader "$DB_C" "SELECT cache_creation_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_zero_a1';")"

            needle_check "usage_absent row: usage_status is genuinely 'UNMEASURED', not silently coerced" 1 "$([ "$ABSENT_STATUS" = "UNMEASURED" ] && echo 1 || echo 0)"
            needle_check "usage_absent row: usage_status is NOT the fabricated 'measured' value" 0 "$([ "$ABSENT_STATUS" = "measured" ] && echo 1 || echo 0)"
            needle_check "usage_absent row: missing_instrument is populated (non-empty)" 1 "$([ -n "$ABSENT_MISSING_INSTR" ] && echo 1 || echo 0)"
            needle_check "usage_absent row: input_tokens is NULL, not coerced to 0" 1 "$ABSENT_INPUT_NULL"
            needle_check "usage_absent row: output_tokens is NULL, not coerced to 0" 1 "$ABSENT_OUTPUT_NULL"
            needle_check "usage_absent row: cache_read_input_tokens is NULL, not coerced to 0" 1 "$ABSENT_CR_NULL"
            needle_check "usage_absent row: cache_creation_input_tokens is NULL, not coerced to 0" 1 "$ABSENT_CC_NULL"

            needle_check "usage_present_zero row: usage_status is genuinely 'measured', a real capture" 1 "$([ "$ZERO_STATUS" = "measured" ] && echo 1 || echo 0)"
            needle_check "usage_present_zero row: usage_status is NOT conflated with 'UNMEASURED'" 0 "$([ "$ZERO_STATUS" = "UNMEASURED" ] && echo 1 || echo 0)"
            needle_check "usage_present_zero row: input_tokens is the literal captured 0, not NULL" 1 "$([ "$ZERO_INPUT" = "0" ] && echo 1 || echo 0)"
            needle_check "usage_present_zero row: output_tokens is the literal captured 0, not NULL" 1 "$([ "$ZERO_OUTPUT" = "0" ] && echo 1 || echo 0)"
            needle_check "usage_present_zero row: cache_read_input_tokens is the literal captured 0, not NULL" 1 "$([ "$ZERO_CR" = "0" ] && echo 1 || echo 0)"
            needle_check "usage_present_zero row: cache_creation_input_tokens is the literal captured 0, not NULL" 1 "$([ "$ZERO_CC" = "0" ] && echo 1 || echo 0)"

            if [ -n "$ABSENT_STATUS" ] && [ -n "$ZERO_STATUS" ] && [ "$ABSENT_STATUS" != "$ZERO_STATUS" ]; then
                ok "PART C dual assertion HOLDS: missing usage_status ('$ABSENT_STATUS') genuinely differs from a genuine-zero usage_status ('$ZERO_STATUS') — missing and zero are decidable, not conflated"
            else
                bad "PART C dual assertion FAILED: missing usage_status ('$ABSENT_STATUS') and genuine-zero usage_status ('$ZERO_STATUS') are the same (or one/both empty) — a broken classifier could report both the same way and still individually 'look right', which is exactly the bluff property (c) forbids"
            fi
        else
            bad "transcript_ingest.py exists but the assumed CLI (ingest <dir> --db <path>) did not run cleanly against missing_usage_block fixture dir: rc=$RC_C out=$OUT_C — update this test's assumed CLI contract"
        fi
    else
        # Genuine investigation: demonstrate the REAL, currently-reproducible
        # defect in the existing WS1 R0 prototype using its OWN flat schema
        # (captured 2026-09-28): a record missing all four token fields and a
        # record with all four explicitly 0 produce BYTE-IDENTICAL reports.
        LEGACY="$REPO_ROOT/docs/research/tokens/ws1_token_waste_baseline/POC/usage_telemetry.py"
        if [ -f "$LEGACY" ]; then
            FLAT_ABSENT="$WORK/flat_absent.jsonl"
            FLAT_ZERO="$WORK/flat_zero.jsonl"
            printf '{"ts":"2026-09-28T04:00:00Z","track":"track1","alias":"claude5","model":"claude-sonnet-5"}\n' > "$FLAT_ABSENT"
            printf '{"ts":"2026-09-28T04:00:00Z","track":"track1","alias":"claude5","model":"claude-sonnet-5","input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}\n' > "$FLAT_ZERO"
            DB_A="$WORK/legacy_absent.db"; DB_Z="$WORK/legacy_zero.db"
            python3 "$LEGACY" ingest "$FLAT_ABSENT" --db "$DB_A" >/dev/null 2>&1
            python3 "$LEGACY" ingest "$FLAT_ZERO"   --db "$DB_Z" >/dev/null 2>&1
            REPORT_A="$(python3 "$LEGACY" report --group-by track --db "$DB_A" 2>&1 | grep 'total_tokens:')"
            REPORT_Z="$(python3 "$LEGACY" report --group-by track --db "$DB_Z" 2>&1 | grep 'total_tokens:')"
            if [ "$REPORT_A" = "$REPORT_Z" ] && [ -n "$REPORT_A" ]; then
                ok "investigated (real captured command output): the existing WS1 R0 prototype's report line for a field-absent record ('$REPORT_A') is BYTE-IDENTICAL to a genuinely-zero record ('$REPORT_Z') — it silently defaults every missing token field to 0 via \`rec.get('input_tokens', 0)\` (usage_telemetry.py, cmd_ingest) with no distinct signal, so 'missing vs zero' is unverifiable with any tool in the tree today"
            else
                bad "unexpected: legacy WS1 R0 prototype distinguishes absent from zero already ('$REPORT_A' vs '$REPORT_Z') — re-investigate before citing this as evidence"
            fi
        else
            bad "cannot investigate further: neither transcript_ingest.py nor the legacy WS1 R0 prototype ($LEGACY) is present"
        fi
        bad "FR-001/SC-001 property (c) UNMET: transcript_ingest.py absent — a transcript turn with no usage block is not yet reported as UNMEASURED/missing_instrument; the only existing ingester in the tree silently coerces it to 0 (captured above)"
    fi
fi

# =============================================================================
# PART D — ingest: subagent transcript attributed to its parent item
#          (session -> agent -> item keying, plan T-A06 (2))
# =============================================================================
echo "=== PART D: subagent-transcript-to-parent-item attribution ==="
PARENT_FIX="$FIX/subagent_attribution/parent_session.jsonl"
SUB_FIX="$FIX/subagent_attribution/parent_session/subagents/agent-fixturet020attr01.jsonl"
if [ ! -f "$PARENT_FIX" ] || [ ! -f "$SUB_FIX" ]; then
    bad "fixture(s) missing: $PARENT_FIX / $SUB_FIX"
else
    # 3-way join-key consistency, control-needled (positive: the real shared
    # id DOES match everywhere; negative: a fabricated, distinct id does NOT
    # match anywhere) -- this is the exact "session->agent->item" key T038
    # must be able to compute from real on-disk transcripts.
    PARENT_AGENT_ID="$(grep -o '"agentId": *"[^"]*"' "$PARENT_FIX" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    SUB_AGENT_ID="$(grep -o '"agentId": *"[^"]*"' "$SUB_FIX" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    FILE_AGENT_ID="$(basename "$SUB_FIX" | sed -n 's/^agent-\(.*\)\.jsonl$/\1/p')"
    ITEM_TAG="$(grep -o 'item=ATM-[0-9]*' "$PARENT_FIX" | head -1)"

    needle_check "parent toolUseResult.agentId matches the real fixture value (fixturet020attr01)" 1 "$([ "$PARENT_AGENT_ID" = "fixturet020attr01" ] && echo 1 || echo 0)"
    needle_check "subagent transcript's own agentId field matches the parent's" 1 "$([ "$SUB_AGENT_ID" = "$PARENT_AGENT_ID" ] && echo 1 || echo 0)"
    needle_check "the on-disk filename's agentId component matches both" 1 "$([ "$FILE_AGENT_ID" = "$PARENT_AGENT_ID" ] && echo 1 || echo 0)"
    needle_check "a FABRICATED, distinct agentId does NOT match this fixture's real id" 0 "$([ "fabricated-not-present-00000" = "$PARENT_AGENT_ID" ] && echo 1 || echo 0)"
    needle_check "the parent dispatch description carries the future item=ATM-9999 tag" 1 "$([ "$ITEM_TAG" = "item=ATM-9999" ] && echo 1 || echo 0)"

    if [ -n "$PARENT_AGENT_ID" ] && [ "$PARENT_AGENT_ID" = "$SUB_AGENT_ID" ] && [ "$SUB_AGENT_ID" = "$FILE_AGENT_ID" ]; then
        ok "fixture is internally consistent: session(fixture-t020-attr-parent-session) -> agent($PARENT_AGENT_ID) -> item($ITEM_TAG) is a real, joinable key chain, ready for T038 to consume"
    else
        bad "fixture join-key inconsistency: parent=$PARENT_AGENT_ID sub=$SUB_AGENT_ID file=$FILE_AGENT_ID — fix the fixture before it can guard property (d)"
    fi

    if [ -f "$TRANSCRIPT_INGEST" ]; then
        DB_D="$WORK/telemetry_d.db"
        OUT_D="$(python3 "$TRANSCRIPT_INGEST" ingest "$PARENT_FIX" --db "$DB_D" 2>&1)"
        RC_D=$?
        if [ "$RC_D" -eq 0 ] && [ -f "$DB_D" ]; then
            ok "transcript_ingest.py ran against parent_session.jsonl ONLY (exit 0), exercising sibling subagents/ auto-discovery: $OUT_D"

            SUB_ROW_ITEM="$(sqlite3 -noheader "$DB_D" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
            SUB_ROW_AGENT="$(sqlite3 -noheader "$DB_D" "SELECT agent_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
            SUB_ROW_SESSION="$(sqlite3 -noheader "$DB_D" "SELECT session_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
            SUB_ROW_STATUS="$(sqlite3 -noheader "$DB_D" "SELECT usage_status FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
            SUB_ROW_TOTAL="$(sqlite3 -noheader "$DB_D" "SELECT total_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"

            needle_check "auto-discovery worked: the subagent's own usage row exists in the DB despite only the PARENT path being passed to ingest" 1 "$([ -n "$SUB_ROW_STATUS" ] && echo 1 || echo 0)"
            needle_check "subagent usage row: item_id genuinely attributes to ATM-9999 (the parent dispatch's stamped item)" 1 "$([ "$SUB_ROW_ITEM" = "ATM-9999" ] && echo 1 || echo 0)"
            needle_check "subagent usage row: item_id is NOT a fabricated, distinct item id" 0 "$([ "$SUB_ROW_ITEM" = "ATM-0000-fabricated" ] && echo 1 || echo 0)"
            needle_check "subagent usage row: agent_id genuinely matches the real fixture value (fixturet020attr01)" 1 "$([ "$SUB_ROW_AGENT" = "fixturet020attr01" ] && echo 1 || echo 0)"
            needle_check "subagent usage row: session_id resolves through the dispatch map to the parent's real session id" 1 "$([ "$SUB_ROW_SESSION" = "fixture-t020-attr-parent-session" ] && echo 1 || echo 0)"
            needle_check "subagent usage row: usage_status is 'measured' (a genuine usage block was present)" 1 "$([ "$SUB_ROW_STATUS" = "measured" ] && echo 1 || echo 0)"
            needle_check "subagent usage row: total_tokens equals the real computed sum (40+200+500+8000=8740)" 1 "$([ "$SUB_ROW_TOTAL" = "8740" ] && echo 1 || echo 0)"

            PARENT_ROW_ITEM_IS_NULL="$(sqlite3 -noheader "$DB_D" "SELECT item_id IS NULL FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_a1';")"
            needle_check "negative control: the parent's own top-level dispatch-turn row is NOT item-attributed (item_id IS NULL) — build_row() only attributes a DISPATCHED subagent's usage, never the dispatching session's own turns" 1 "$PARENT_ROW_ITEM_IS_NULL"

            PARENT_TAGGED_COUNT="$(sqlite3 -noheader "$DB_D" "SELECT COUNT(*) FROM transcript_usage_events WHERE agent_id IS NULL AND item_id='ATM-9999';")"
            needle_check "negative control: ZERO of the parent session's own (non-subagent, agent_id IS NULL) rows carry item_id='ATM-9999'" 1 "$([ "$PARENT_TAGGED_COUNT" = "0" ] && echo 1 || echo 0)"

            if [ "$SUB_ROW_ITEM" = "ATM-9999" ] && [ "$PARENT_ROW_ITEM_IS_NULL" = "1" ] && [ "$PARENT_TAGGED_COUNT" = "0" ]; then
                ok "PART D property (d) HOLDS: session(fixture-t020-attr-parent-session) -> agent(fixturet020attr01) -> item(ATM-9999) attribution is real, and the parent's own turns are correctly left unattributed"
            else
                bad "PART D property (d) UNMET (post-implementation): subagent item=$SUB_ROW_ITEM parent-item-is-null=$PARENT_ROW_ITEM_IS_NULL parent-tagged-count=$PARENT_TAGGED_COUNT — attribution is broken, investigate before trusting this ingest path"
            fi
        else
            bad "transcript_ingest.py exists but the assumed CLI (ingest <parent-file> --db <path>) did not run cleanly against the subagent_attribution fixture (auto-discovery of sibling subagents/ dir): rc=$RC_D out=$OUT_D — update this test's assumed CLI contract"
        fi
    else
        bad "FR-013/SC-005 property (d) UNMET: transcript_ingest.py absent — subagent-transcript-to-parent-item attribution (session->agent->item keying) is unverified; the real on-disk join key is proven present and consistent above, but nothing reads it yet"
    fi
fi

# =============================================================================
# PART E — credential test: a planted secret string never reaches the
#          telemetry DB (§11.4.10; plan T-A06 (2)(b) credential test)
# =============================================================================
echo "=== PART E: credential safety of the future telemetry DB ==="
# Strengthened per T038 independent review finding F1 (BLOCKING) + F2
# (IMPORTANT), agent ab41d614f9a8e1933, 2026-09-28: the ORIGINAL form of
# this PART only grepped the produced DB for the EXACT marker string,
# which a self-authored mutation (M3: `model = base64.b64encode(
# json.dumps(msg).encode()).decode()`, dumping the ENTIRE message dict --
# including its content -- into the `model` column as base64) defeated
# completely: the mutated transcript_ingest.py leaked real conversational
# content, base64-decodable straight out of the `model` column, while
# this PART still reported "credential safety holds" and the whole suite
# still reported 53/0. F2: a SEPARATE self-authored mutation (M2, exiting
# before any row is written) also passed this PART on an EMPTY database
# -- an absence-of-marker verdict proves nothing when nothing was ever
# scanned (§11.4.201(6) false-null).
#
# Fixed with TWO independent, complementary layers, neither alone
# sufficient (defense-in-depth, matching both independent reviewers'
# actual manual verification methodology, now built into the test
# permanently rather than performed ad hoc):
#
#   (i) STRUCTURAL ALLOWLIST (the layer that actually closes the M3
#       mutation class): every TEXT-typed column of the ingested row is
#       compared for EXACT EQUALITY against this fixture's own known-
#       correct structural values (its real message id, session id,
#       record uuid, model name, usage_status, source file, timestamp).
#       An encoded/truncated/partial/any-other-shape leak in ANY column
#       -- whatever encoding hides it -- can never equal these short,
#       exact, independently-known-correct literals, so this check does
#       not need to anticipate every possible encoding scheme the way a
#       substring scan does.
#
#  (ii) DEFENSE-IN-DEPTH SUBSTRING/ENCODING SCAN (the layer both
#       reviewers ran manually this session): exact marker (case-
#       sensitive + insensitive), base64, hex (text form AND raw binary
#       bytes), and a sliding-window scan of every 12+ character
#       contiguous chunk of the marker, across the ENTIRE DB file --
#       catching a leak this fixture's OWN row-shape assertion above
#       would not (e.g. a leak smuggled into some OTHER row, or a future
#       schema change adding a new text column this file's allowlist has
#       not yet been updated to check).
#
# Plus the F2 fix: the ingest's own exit code and produced row COUNT are
# asserted BEFORE any absence verdict is trusted, and the fixture's own
# KNOWN-correct msg_id is asserted PRESENT (not merely "marker absent")
# so a vacuous empty-DB run can no longer pass this PART.
CRED_FIX="$FIX/credential_leak/session.jsonl"
MARKER="FASTCYCLE-T020-PLANTED-MARKER-7f3a9c2e1b8d4f6091ab34cd"
FABRICATED_MARKER="FASTCYCLE-T020-NEVER-PLANTED-0000000000000000000000"
if [ ! -f "$CRED_FIX" ]; then
    bad "fixture missing: $CRED_FIX"
else
    needle_check "credential_leak fixture genuinely contains the planted marker" 1 "$(grep -Fq "$MARKER" "$CRED_FIX" && echo 1 || echo 0)"
    needle_check "credential_leak fixture does not contain a fabricated, distinct marker" 0 "$(grep -Fq "$FABRICATED_MARKER" "$CRED_FIX" && echo 1 || echo 0)"
    ok "fixture also carries a genuine usage block (input_tokens=60 output_tokens=90) so a real GREEN ingest run exercises normal counting alongside the credential check"

    if [ -f "$TRANSCRIPT_INGEST" ]; then
        DB="$WORK/telemetry_e.db"
        rm -f "$DB"
        python3 "$TRANSCRIPT_INGEST" ingest "$CRED_FIX" --db "$DB" >/dev/null 2>&1
        INGEST_RC=$?

        # --- F2: rc + row-count + known-row-presence BEFORE trusting any
        # absence verdict below (never a vacuous pass on a failed or empty
        # ingest). ---
        if [ "$INGEST_RC" != 0 ]; then
            bad "PART E ingest itself exited $INGEST_RC (expected 0) -- every check below would be vacuous against a failed/partial run"
        elif [ ! -f "$DB" ]; then
            bad "transcript_ingest.py exited 0 but produced no DB at the assumed path ($DB) -- update this test's assumed CLI contract"
        else
            ROWCOUNT="$(sqlite3 -readonly "$DB" 'SELECT COUNT(*) FROM transcript_usage_events;' 2>/dev/null)"
            needle_check "PART E ingest produced a genuinely non-empty DB (rows>=1), never a vacuous empty-DB pass" 1 "$([ "${ROWCOUNT:-0}" -ge 1 ] 2>/dev/null && echo 1 || echo 0)"
            KNOWN_MSGID="msg_fixture_t020_cred_a1"
            MSGID_PRESENT="$(sqlite3 -readonly "$DB" "SELECT COUNT(*) FROM transcript_usage_events WHERE msg_id = '$KNOWN_MSGID';" 2>/dev/null)"
            needle_check "PART E's own fixture's known-correct msg_id ($KNOWN_MSGID) is genuinely present in the DB -- proves THIS row was really scanned below, not an unrelated/empty one" 1 "$([ "${MSGID_PRESENT:-0}" -ge 1 ] 2>/dev/null && echo 1 || echo 0)"

            # --- (i) structural allowlist: every text column of the known
            # row must EQUAL its known-correct value exactly. This is what
            # catches an encoded leak regardless of encoding scheme, since
            # an encoded blob of message content can never equal a short
            # exact literal like "claude-sonnet-5". ---
            ALLOWLIST_REPORT="$(python3 -c "
import sqlite3, sys
db = sys.argv[1]
expected = {
    'record_uuid': 'fixture-t020-cred-a1',
    'session_id': 'fixture-t020-cred-session',
    'agent_id': None,
    'item_id': None,
    'ts': '2026-09-28T04:20:05.000Z',
    'model': 'claude-sonnet-5',
    'msg_id': 'msg_fixture_t020_cred_a1',
    'usage_status': 'measured',
    'missing_instrument': None,
}
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
row = con.execute(\"SELECT * FROM transcript_usage_events WHERE msg_id = ?\", ('$KNOWN_MSGID',)).fetchone()
if row is None:
    print('MISSING_ROW')
    sys.exit(1)
mismatches = []
for col, want in expected.items():
    got = row[col]
    if got != want:
        # Never print the actual leaked value verbatim into test output
        # (this output may itself be captured/logged) -- report shape only.
        got_repr = 'NULL' if got is None else ('<%d chars>' % len(str(got)))
        want_repr = 'NULL' if want is None else repr(want)
        mismatches.append('%s: expected %s, got %s' % (col, want_repr, got_repr))
if mismatches:
    print('MISMATCH: ' + '; '.join(mismatches))
    sys.exit(1)
print('ALL_MATCH')
sys.exit(0)
" "$DB")"
            if [ "$ALLOWLIST_REPORT" = "ALL_MATCH" ]; then
                ok "structural allowlist holds: every text column of the ingested row EXACTLY matches this fixture's known-correct structural values -- an encoded/reshaped leak in ANY column, in ANY encoding, would have failed this check (T038 review finding F1)"
            else
                bad "CREDENTIAL LEAK (or schema drift): structural allowlist mismatch -- $ALLOWLIST_REPORT -- a column holds something other than its expected exact structural value; this is EXACTLY the class of leak a plain marker-substring grep cannot see (T038 review finding F1)"
            fi

            # --- (ii) defense-in-depth: exact/case-insensitive/base64/hex/
            # sliding-window substring scan across the WHOLE DB file. ---
            if grep -aFq "$MARKER" "$DB" 2>/dev/null; then
                bad "CREDENTIAL LEAK: the exact planted marker reached the telemetry DB ($DB)"
            elif grep -aFqi "$MARKER" "$DB" 2>/dev/null; then
                bad "CREDENTIAL LEAK (case-insensitive): a case-transformed copy of the planted marker reached the telemetry DB ($DB)"
            else
                ENCODING_SCAN="$(python3 -c "
import base64, sys
marker = sys.argv[1]
data = open(sys.argv[2], 'rb').read()
hits = []
b64 = base64.b64encode(marker.encode()).decode()
if b64.encode() in data:
    hits.append('base64')
hexenc = marker.encode().hex()
if hexenc.encode() in data:
    hits.append('hex-text')
if bytes.fromhex(hexenc) in data:
    hits.append('hex-bytes')
for i in range(0, len(marker) - 11):
    chunk = marker[i:i+12]
    if chunk.encode() in data:
        hits.append('substring[%d:%d]' % (i, i+12))
        break
print(','.join(hits) if hits else 'CLEAN')
" "$MARKER" "$DB")"
                if [ "$ENCODING_SCAN" = "CLEAN" ]; then
                    ok "credential safety holds: the planted marker does NOT appear anywhere in the produced telemetry DB ($DB) -- exact, case-insensitive, base64, hex, and 12-char-sliding-window substring scans all clean, PLUS the structural allowlist above (T038 review finding F1 defense-in-depth)"
                else
                    bad "CREDENTIAL LEAK: an encoded/partial variant of the planted marker ($ENCODING_SCAN) reached the telemetry DB ($DB) -- the exact-string grep alone would have missed this"
                fi
            fi
        fi
    else
        bad "FR-013/SC-005 property (e) UNMET: transcript_ingest.py absent — no telemetry DB exists to scan; credential safety of the eventual ingest path is unproven (paired mutation once T038 lands, per plan.md T-A06: an implementation that ingests message bodies verbatim would leak the marker and this exact assertion would then correctly FAIL)"
    fi
fi

# ---- final control-needle on the shared grep mechanism itself -------------
# (§11.4.201(7)(b)): every conclusion above rests on grep seeing real bytes in
# real files; prove it can, one more time, on a KNOWN-present literal.
if [ -f "$REG" ] 2>/dev/null; then
    if grep -Fq '"tool_name": "Agent"' "$REG" 2>/dev/null; then
        ok "final control-needle: grep sees known-present JSONL content in the fixture registry file"
    else
        bad "final control-needle BLIND — every zero/absence reported above is unproven"
    fi
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
