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
    PAYLOAD="$(python3 - "$REAL_DESC" "$REPO_ROOT" <<'PYEOF'
import json, sys
desc = sys.argv[1]
cwd = sys.argv[2]
d = {
    "session_id": "sess-fixture-t020-0001",
    "cwd": cwd,
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

# T048 review round-1 finding F8 remediation (2026-09-29): property (a)'s
# HOLDS/UNMET verdict below (see the "A-RED" block) was originally driven
# entirely by $FOUND -- i.e. by whether the row's DESCRIPTION field
# contains an item=<ATM-nnnn> token. That premise is WRONG for T037's real,
# deliberately-specified design: T037's own tasks.md line reads "item id
# COLUMN" (not "inject the tag into the description"), and direct
# inspection of the REAL, live scripts/hooks/agent_registry_writer.sh
# confirms it writes `"item": item_id` as its OWN dedicated JSONL key,
# NEVER touching `description` at all -- so $FOUND (description-based)
# will structurally read 0 FOREVER, whether or not T037 has landed and is
# genuinely taking effect. That is a §11.4.120 wrong-artifact assertion,
# not a real gap: T037's implementation is the deliberate, already-shipped,
# spec-matching choice (its own task line names a separate column), so the
# fix is to correct the TEST to read the field T037 actually writes, per
# §11.4.120, never to weaken T037's already-correct design.
#
# item_field_state <registry-jsonl-file> -- parses the REAL row's JSON
# structure (never a brittle string grep across the raw text, which risks
# a false match against unrelated content) and prints "PRESENT:<value>" if
# the writer's own "item" key exists in the row (any value, including an
# honest empty string for an untagged dispatch), "ABSENT" if the key is
# missing from the row's schema entirely (the pre-T037 shape), or "NOFILE"
# if the registry file is missing/unparseable/empty.
item_field_state() {
    python3 - "$1" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        lines = [l for l in f if l.strip()]
    if not lines:
        print("NOFILE")
        sys.exit(0)
    row = json.loads(lines[-1])
    if "item" in row:
        print("PRESENT:" + str(row["item"]))
    else:
        print("ABSENT")
except Exception:
    print("NOFILE")
PYEOF
}

ITEM_FIELD_UNTAGGED="ABSENT"
ITEM_FIELD_TAGGED="ABSENT"
ITEM_FIELD_TAKING_EFFECT=0
if [ -f "$WRITER" ]; then
    ITEM_FIELD_UNTAGGED="$(item_field_state "$REG")"

    # A-tagged-real: a SECOND real writer invocation, this time with a
    # description that DOES carry a well-formed item=ATM-nnnn tag -- the
    # §11.4.273(b) control needle for the check above. An empty "item"
    # field on the untagged case alone proves little on its own (a field
    # that is ALWAYS empty, even when broken, would look identical); pairing
    # it with a REAL tag that genuinely round-trips through the extraction
    # + write path is what proves the mechanism is truly connected, not
    # merely present-but-inert.
    REG2="$WORK/agent_registry_tagged.jsonl"
    TAGGED_DESC="(T1/main - claude5 - sonnet - high) item=ATM-9042 T020 fixture control-needle dispatch"
    PAYLOAD2="$(python3 - "$TAGGED_DESC" "$REPO_ROOT" <<'PYEOF'
import json, sys
desc = sys.argv[1]
cwd = sys.argv[2]
d = {
    "session_id": "sess-fixture-t020-0002",
    "cwd": cwd,
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
    printf '%s' "$PAYLOAD2" | HELIX_AGENT_REGISTRY_FILE="$REG2" bash "$WRITER" >/dev/null 2>&1
    ITEM_FIELD_TAGGED="$(item_field_state "$REG2")"
    needle_check "the REAL writer's 'item' JSON field genuinely round-trips a real item=ATM-nnnn tag (proves the untagged case's field state above is a real extraction result, not an always-inert field)" 1 "$([ "$ITEM_FIELD_TAGGED" = "PRESENT:ATM-9042" ] && echo 1 || echo 0)"

    if [ "$ITEM_FIELD_UNTAGGED" = "PRESENT:" ] && [ "$ITEM_FIELD_TAGGED" = "PRESENT:ATM-9042" ]; then
        ITEM_FIELD_TAKING_EFFECT=1
    fi
fi

# A-RED: the DESIRED future invariant (T036 stamps the tag; T037 wires
# dispatch_stamp.sh so a dispatch lacking item=<ATM-nnnn> is mechanically
# flagged/refused/requires the tag before being recorded as a normal
# 'dispatched' row) does not hold today. The task text itself pairs BOTH
# T036 AND T037 as the joint gap-closer ("T036/T037 absent"), and
# dispatch_stamp.sh's OWN header confirms this in-source: "NOT YET WIRED
# (deliberately, by design — T037's job, NOT this task's) ... this file is
# NOT registered in .claude/settings.json's PreToolUse hook chain ...
# Invoke it directly/manually until T037 lands." tasks.md:121 independently
# confirms T037 ([SERIAL], conductor-only wiring into $WRITER's item-id
# column AND .claude/settings.json's PreToolUse hook list) is still `[ ]`
# unchecked as of this run.
#
# (§11.4.108/§11.4.226/§11.4.240 remediation, T020 self-review, 2026-09-28):
# the ORIGINAL form of this check treated `[ -f "$DISPATCH_STAMP" ]` alone
# as sufficient to declare property (a) HOLDS — an ARTIFACT-layer
# (T036-file-exists) verdict standing in for the RUNTIME-layer invariant
# the task actually requires (a REAL dispatch through the REAL pipeline is
# flagged/refused/attributed). That is exactly the source-present-runtime-
# absent bluff this project's own T020/T036/T038 batch review found and
# fixed repeatedly elsewhere this same session: a standalone, deliberately-
# unwired script existing on disk proves NOTHING about what a live dispatch
# actually does, and the A-real block immediately above THIS one already
# empirically demonstrated (via a REAL invocation of the REAL, unmodified
# $WRITER) that a description lacking item=<ATM-nnnn> is STILL accepted
# today with NO item token in the resulting row (FOUND=0, captured above) —
# directly contradicting a bare "property (a) HOLDS" verdict drawn from
# file-existence alone.
#
# Fixed: property (a)'s verdict is now driven by (i) a structural check for
# a genuine wiring REFERENCE to dispatch_stamp.sh inside the REAL pipeline
# files T037 is scoped to touch ($WRITER and .claude/settings.json), AND
# (ii) cross-validated against the REAL A-real invocation's own FOUND
# result computed above — never file-existence of T036 in isolation. This
# does not presuppose T037's not-yet-written implementation details; it
# only asserts that BOTH a source-level wiring reference AND a real,
# observed behavioural effect must be present before the invariant is
# declared to hold, and explicitly flags the "reference exists but has no
# observed effect" case as its own distinct FAIL rather than silently
# treating it as either PASS or the pre-T037 FAIL.
WIRED_INTO_WRITER=0
if [ -f "$WRITER" ] && grep -Fq "dispatch_stamp" "$WRITER" 2>/dev/null; then
    WIRED_INTO_WRITER=1
fi
SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"
WIRED_INTO_SETTINGS=0
if [ -f "$SETTINGS_JSON" ] && grep -Fq "dispatch_stamp" "$SETTINGS_JSON" 2>/dev/null; then
    WIRED_INTO_SETTINGS=1
fi

# F8 remediation (2026-09-29): verdict now driven by $ITEM_FIELD_TAKING_EFFECT
# (the REAL writer row's "item" JSON field -- what T037 actually writes),
# never $FOUND (the description field -- what T037 was NEVER designed to
# touch; see the item_field_state() block above for the full derivation).
if [ -f "$DISPATCH_STAMP" ] && { [ "$WIRED_INTO_WRITER" -eq 1 ] || [ "$WIRED_INTO_SETTINGS" -eq 1 ]; }; then
    if [ "$ITEM_FIELD_TAKING_EFFECT" = "1" ]; then
        ok "FR-013/FR-001/SC-005 property (a) HOLDS: dispatch_stamp.sh exists AND a wiring reference was found (writer_wired=$WIRED_INTO_WRITER settings_wired=$WIRED_INTO_SETTINGS), AND the REAL $WRITER invocation genuinely writes its own dedicated 'item' JSON field for every dispatch -- untagged=$ITEM_FIELD_UNTAGGED, tagged=$ITEM_FIELD_TAGGED (T037's own 'item id column' design, confirmed via two real writer invocations, round-trips correctly: honest-empty for an untagged description, the real ATM-nnnn id for a tagged one) -- T037 has landed and is taking real effect"
    else
        bad "FR-013/FR-001/SC-005 property (a) UNMET (wiring reference present but NOT taking effect): a reference to dispatch_stamp.sh was found in the real pipeline (writer_wired=$WIRED_INTO_WRITER settings_wired=$WIRED_INTO_SETTINGS), BUT the REAL $WRITER invocation(s) did NOT produce the expected 'item' field round-trip (untagged=$ITEM_FIELD_UNTAGGED want PRESENT:, tagged=$ITEM_FIELD_TAGGED want PRESENT:ATM-9042) — a source-level wiring reference existing is not the same as it genuinely taking effect on a real dispatch; investigate before declaring T037 done"
    fi
else
    bad "FR-013/FR-001/SC-005 property (a) UNMET: dispatch_stamp.sh $([ -f "$DISPATCH_STAMP" ] && echo 'exists as a standalone, deliberately-unwired T036 artifact' || echo 'is absent (T036 not yet landed)') — T037 (wiring $DISPATCH_STAMP into \$WRITER's item-id column AND .claude/settings.json's PreToolUse hook list, tasks.md:121, still \`[ ]\` unchecked) has NOT landed (writer_wired=$WIRED_INTO_WRITER settings_wired=$WIRED_INTO_SETTINGS) — a dispatch is accepted and recorded with no item attribution whatsoever on the REAL pipeline (item field state=$ITEM_FIELD_UNTAGGED)"
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
            ok "transcript_ingest.py ran against cache_hits fixture (exit 0): $OUT"

            # Real DB-level control needles (§11.4.273/§11.4.201(6)/(7)(b)) —
            # this replaces an earlier 'MANUALLY VERIFY ... before trusting a
            # GREEN verdict here' placeholder found during this task's own
            # investigation (2026-09-28, T020 RED-test re-verification): a
            # bare exit-0 + DB-file-exists check proves nothing about whether
            # cache-hit tokens were actually counted or summed correctly —
            # PART C/D already query the DB directly for their properties;
            # PART B is brought to the same rigor here, never left to a human
            # to eyeball. The oracle is sqlite3 (producer-independent of
            # transcript_ingest.py's own Python internals — §11.4.240).
            SUM_CACHE_READ="$(sqlite3 -noheader "$DB" "SELECT SUM(cache_read_input_tokens) FROM transcript_usage_events WHERE msg_id IN ('msg_fixture_t020_cachehit_a1','msg_fixture_t020_cachehit_a2');")"
            SUM_CACHE_CREATION="$(sqlite3 -noheader "$DB" "SELECT SUM(cache_creation_input_tokens) FROM transcript_usage_events WHERE msg_id IN ('msg_fixture_t020_cachehit_a1','msg_fixture_t020_cachehit_a2');")"
            TURN1_CR="$(sqlite3 -noheader "$DB" "SELECT cache_read_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_cachehit_a1';")"
            TURN1_CC="$(sqlite3 -noheader "$DB" "SELECT cache_creation_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_cachehit_a1';")"
            TURN2_CR="$(sqlite3 -noheader "$DB" "SELECT cache_read_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_cachehit_a2';")"
            TURN2_CC="$(sqlite3 -noheader "$DB" "SELECT cache_creation_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_cachehit_a2';")"
            ROW_COUNT="$(sqlite3 -noheader "$DB" "SELECT COUNT(*) FROM transcript_usage_events WHERE msg_id IN ('msg_fixture_t020_cachehit_a1','msg_fixture_t020_cachehit_a2');")"

            needle_check "cache_hits ingest: exactly 2 rows landed for this fixture's 2 assistant turns (not dropped, not duplicated)" 1 "$([ "$ROW_COUNT" = "2" ] && echo 1 || echo 0)"
            needle_check "cache_hits ingest: SUM(cache_read_input_tokens) across both turns equals the real captured total ($EXPECTED_CACHE_READ_SUM)" 1 "$([ "$SUM_CACHE_READ" = "$EXPECTED_CACHE_READ_SUM" ] && echo 1 || echo 0)"
            needle_check "cache_hits ingest: SUM(cache_read_input_tokens) is NOT a fabricated, distinct total (999999)" 0 "$([ "$SUM_CACHE_READ" = "999999" ] && echo 1 || echo 0)"
            needle_check "cache_hits ingest: SUM(cache_creation_input_tokens) across both turns equals the real captured total ($EXPECTED_CACHE_CREATION_SUM)" 1 "$([ "$SUM_CACHE_CREATION" = "$EXPECTED_CACHE_CREATION_SUM" ] && echo 1 || echo 0)"
            needle_check "cache_hits ingest: turn 1 (cold-cache write) is genuinely cache_read=0" 1 "$([ "$TURN1_CR" = "0" ] && echo 1 || echo 0)"
            needle_check "cache_hits ingest: turn 1 (cold-cache write) is genuinely cache_creation=1200" 1 "$([ "$TURN1_CC" = "1200" ] && echo 1 || echo 0)"
            needle_check "cache_hits ingest: turn 2 (warm-cache read) is genuinely cache_read=1200" 1 "$([ "$TURN2_CR" = "1200" ] && echo 1 || echo 0)"
            needle_check "cache_hits ingest: turn 2 (warm-cache read) is genuinely cache_creation=0" 1 "$([ "$TURN2_CC" = "0" ] && echo 1 || echo 0)"

            if [ "$SUM_CACHE_READ" = "$EXPECTED_CACHE_READ_SUM" ] && [ "$SUM_CACHE_CREATION" = "$EXPECTED_CACHE_CREATION_SUM" ] && [ "$TURN1_CR" = "0" ] && [ "$TURN2_CR" = "$EXPECTED_CACHE_READ_SUM" ]; then
                ok "PART B property (b) HOLDS: cache-hit tokens are counted per-turn AND summed correctly — not dropped, not coerced, and not merely coincidentally summing right while individually wrong (turn 1 cold-write vs turn 2 warm-read are distinguishable in the DB)"
            else
                bad "PART B property (b) UNMET: cache-hit token counting does not match the real captured shape (sum_cache_read=$SUM_CACHE_READ sum_cache_creation=$SUM_CACHE_CREATION turn1_cr=$TURN1_CR turn2_cr=$TURN2_CR, want sum_cache_read=$EXPECTED_CACHE_READ_SUM sum_cache_creation=$EXPECTED_CACHE_CREATION_SUM turn1_cr=0 turn2_cr=$EXPECTED_CACHE_READ_SUM)"
            fi
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
#       contiguous chunk of the marker, across the ENTIRE DB file. HONEST
#       BOUNDARY (T038 round-3 review, agent a3e3aec6be73b24e3,
#       2026-09-28): this layer is NOT, by itself, a complete oracle --
#       it is base64-ALIGNMENT-dependent (a leak shifted by 1 or 2 bytes
#       before encoding evades the base64 check entirely, independently
#       reproduced) and catches only FORWARD, PLAINTEXT-adjacent
#       substrings (a reversed, rot13'd, compressed, or otherwise
#       transformed copy of the marker is NOT caught by this scan at
#       all). It remains useful defense-in-depth for the SPECIFIC forms
#       it does cover, but layer (i) below -- never this layer alone --
#       is what this PART actually relies on to catch an arbitrary-shape
#       leak.
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
        # T038 round-4 independent review (agent a29d6aaf96f5f6440,
        # 2026-09-28) found 3 side-channel leak classes this PART
        # previously could not see at all because the ingest's own I/O
        # was discarded (>/dev/null 2>&1, never inspected: R4-7) and it
        # ran directly into $WORK, a directory shared with other test
        # fixtures rather than one whose file listing is directly
        # enumerable (R4-6). Fixed: run in a freshly-created, otherwise-
        # empty isolated directory, and capture both streams to files
        # instead of discarding them.
        CRED_ISOLATED_DIR="$WORK/cred_isolated_run"
        rm -rf "$CRED_ISOLATED_DIR"
        mkdir -p "$CRED_ISOLATED_DIR"
        DB="$CRED_ISOLATED_DIR/telemetry_e.db"
        STDOUT_CAP="$CRED_ISOLATED_DIR/.ingest_stdout.log"
        STDERR_CAP="$CRED_ISOLATED_DIR/.ingest_stderr.log"
        python3 "$TRANSCRIPT_INGEST" ingest "$CRED_FIX" --db "$DB" >"$STDOUT_CAP" 2>"$STDERR_CAP"
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

            # --- (i) COMPLETE, DYNAMICALLY-DERIVED structural allowlist
            # (T038 round-3 review finding, BLOCKING, fixed 2026-09-28):
            # the FIRST version of this check hand-maintained a 9-column
            # expected dict that OMITTED source_file, row_hash, lineno,
            # and all 4 numeric token columns -- 7 independently-authored
            # adversarial mutations smuggled a real, recoverable content
            # leak through exactly those UNCHECKED columns (including
            # source_file, which an earlier version of THIS COMMENT
            # falsely claimed was checked -- a real self-inflicted
            # inaccuracy, corrected here rather than repeated) and still
            # scored a full 56/0 PASS. Fixed properly this time: every
            # column this table's OWN schema reports via
            # `PRAGMA table_info` is checked -- never a hand-maintained
            # subset that can silently miss a column, today or after any
            # future schema change -- AND the table's TOTAL row count is
            # asserted to be EXACTLY 1 (never merely >=1), closing the
            # "smuggle a leak into an extra, unscanned row" mutation
            # class the round-3 review also found. row_hash is verified
            # against the SAME sha256("msgid:"+msg_id) formula this
            # module's own build_row() documents (never a hardcoded
            # magic hex string, which would silently stop verifying
            # anything the moment the fixture's msg_id ever changed). A
            # schema column this check does not yet know how to derive
            # an expected value for FAILS LOUD naming the column, rather
            # than being silently skipped -- the uncovered-column class
            # that broke the first version cannot recur unnoticed. ---
            ALLOWLIST_REPORT="$(python3 -c "
import hashlib, sqlite3, sys
db = sys.argv[1]
cred_fix_path = sys.argv[2]
known_msgid = sys.argv[3]
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row

total_rows = con.execute('SELECT COUNT(*) FROM transcript_usage_events').fetchone()[0]
if total_rows != 1:
    print('ROW_COUNT: expected exactly 1 row in the whole table, got %d -- a leak could be smuggled into an extra, otherwise-unscanned row' % total_rows)
    sys.exit(1)

row = con.execute('SELECT * FROM transcript_usage_events WHERE msg_id = ?', (known_msgid,)).fetchone()
if row is None:
    print('MISSING_ROW')
    sys.exit(1)

expected = {
    'row_hash': hashlib.sha256(('msgid:' + known_msgid).encode('utf-8')).hexdigest(),
    'source_file': cred_fix_path,
    'lineno': 2,
    'record_uuid': 'fixture-t020-cred-a1',
    'session_id': 'fixture-t020-cred-session',
    'agent_id': None,
    'item_id': None,
    'ts': '2026-09-28T04:20:05.000Z',
    'model': 'claude-sonnet-5',
    'msg_id': known_msgid,
    'usage_status': 'measured',
    'missing_instrument': None,
    'input_tokens': 60,
    'output_tokens': 90,
    'cache_read_input_tokens': 0,
    'cache_creation_input_tokens': 0,
    'total_tokens': 150,
}

schema_cols = [r[1] for r in con.execute('PRAGMA table_info(transcript_usage_events)').fetchall()]
mismatches = []
uncovered = [c for c in schema_cols if c not in expected]
if uncovered:
    print('UNCOVERED_COLUMNS: %s -- this check does not yet know an expected value for these schema columns; add them rather than silently trusting them' % ','.join(uncovered))
    sys.exit(1)

for col in schema_cols:
    want = expected[col]
    got = row[col]
    if got != want:
        # Never print the actual leaked value verbatim into test output
        # (this output may itself be captured/logged) -- report shape only.
        got_repr = 'NULL' if got is None else ('<%d chars/bytes: %r>' % (len(str(got)), type(got).__name__))
        want_repr = 'NULL' if want is None else repr(want)
        mismatches.append('%s: expected %s, got %s' % (col, want_repr, got_repr))
if mismatches:
    print('MISMATCH: ' + '; '.join(mismatches))
    sys.exit(1)
print('ALL_MATCH(%d columns, %d rows)' % (len(schema_cols), total_rows))
sys.exit(0)
" "$DB" "$CRED_FIX" "$KNOWN_MSGID")"
            if [ "${ALLOWLIST_REPORT#ALL_MATCH}" != "$ALLOWLIST_REPORT" ]; then
                ok "structural allowlist holds: $ALLOWLIST_REPORT, dynamically derived from PRAGMA table_info (never a hand-maintained subset), the table holds EXACTLY one row -- an encoded/reshaped/smuggled-into-an-extra-row leak in ANY column, in ANY encoding, would have failed this check (T038 review finding F1, fixed properly after round-3 found the first attempt incomplete)"
            else
                bad "CREDENTIAL LEAK (or schema drift): structural allowlist mismatch -- $ALLOWLIST_REPORT -- a column holds something other than its expected exact structural value, or an uncovered schema column was found, or the row count is wrong; this is EXACTLY the class of leak a plain marker-substring grep cannot see (T038 review finding F1)"
            fi

            # --- (ii) WHOLE-DATABASE-FILE deterministic census (T038
            # round-4 independent review, agent a29d6aaf96f5f6440,
            # 2026-09-28, 3 BLOCKING root causes demonstrated with 7
            # concrete mutations R4-1..R4-5): layer (i) above proves the
            # ONE CHECKED ROW is clean but says NOTHING about the REST of
            # the database file -- an extra table, a view, an index whose
            # NAME itself carries the leak (all invisible to a per-row
            # column check), or bytes left in a freed page after a
            # delete (R4-5: insert-then-delete a leak row, the checked
            # table's row count returns to 1, but the freed page's old
            # content survives on disk with secure_delete=0). This is
            # DELIBERATELY the fully deterministic replacement for
            # "think of one more creative attack" -- it does not
            # enumerate attack SHAPES at all, it asserts the database's
            # ENTIRE logical content equals the ONE expected state, so
            # there is no shape of leak left un-covered by construction.
            # Built from this module's OWN `SCHEMA` string (never a
            # hand-duplicated copy that could silently drift from the
            # real schema) so this check cannot go stale the way the
            # original hand-maintained 9-column allowlist did. ---
            DUMP_REPORT="$(python3 -c "
import hashlib, importlib.util, sqlite3, sys

real_db, cred_fix_path, known_msgid, ingest_path = sys.argv[1:5]

spec = importlib.util.spec_from_file_location('transcript_ingest', ingest_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

ref = sqlite3.connect(':memory:')
ref.executescript(mod.SCHEMA)
row_hash = hashlib.sha256(('msgid:' + known_msgid).encode('utf-8')).hexdigest()
ref.execute(
    'INSERT INTO transcript_usage_events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
    (row_hash, cred_fix_path, 2, 'fixture-t020-cred-a1', 'fixture-t020-cred-session',
     None, None, '2026-09-28T04:20:05.000Z', 'claude-sonnet-5', known_msgid, 'measured',
     None, 60, 90, 0, 0, 150),
)
ref.commit()

real = sqlite3.connect(real_db)
real_freelist = real.execute('PRAGMA freelist_count').fetchone()[0]

# iterdump() order is stable (schema-creation order, then rowid order) for
# a single-writer, single-transaction DB -- no sort needed, and sorting
# would hide a genuine ordering-dependent difference.
ref_dump = list(ref.iterdump())
real_dump = list(real.iterdump())

if real_freelist != 0:
    print('FREELIST_NONZERO: %d freed page(s) remain in the real DB -- possible insert-then-delete residue (R4-5)' % real_freelist)
    sys.exit(1)

if real_dump != ref_dump:
    # Never print the actual dump content (it may itself carry the leak)
    # -- report only the shape of the divergence.
    extra = [l for l in real_dump if l not in ref_dump]
    missing = [l for l in ref_dump if l not in real_dump]
    print('DUMP_MISMATCH: %d line(s) in the real DB not in the reference, %d line(s) in the reference not in the real DB -- extra/missing table, view, index, trigger, row, or row-content divergence' % (len(extra), len(missing)))
    sys.exit(1)

print('DUMP_MATCH(%d lines, freelist=0)' % len(real_dump))
sys.exit(0)
" "$DB" "$CRED_FIX" "$KNOWN_MSGID" "$TRANSCRIPT_INGEST")"
            if [ "${DUMP_REPORT#DUMP_MATCH}" != "$DUMP_REPORT" ]; then
                ok "whole-database deterministic census holds: $DUMP_REPORT -- an extra table/view/index/trigger/row or freed-page residue would have failed this (T038 round-4 review, R4-1..R4-5)"
            else
                bad "CREDENTIAL LEAK (whole-database census): $DUMP_REPORT -- this is EXACTLY the class of leak a single-row/single-column check cannot see (T038 round-4 review, R4-1..R4-5)"
            fi

            # --- (iii) stdout/stderr + run-directory census (T038 round-4
            # review, R4-6/R4-7): the ingest's own process I/O was
            # previously discarded (>/dev/null 2>&1) and never inspected,
            # and it ran into a shared directory whose file listing was
            # never enumerated -- a debug print or a sidecar cache file
            # could carry a leak invisible to every DB-only check above. ---
            IO_LEAK_FOUND=0
            for f in "$STDOUT_CAP" "$STDERR_CAP"; do
                if [ -f "$f" ] && grep -aFq "$MARKER" "$f" 2>/dev/null; then
                    bad "CREDENTIAL LEAK: the planted marker reached $(basename "$f") -- ingest I/O was previously discarded via >/dev/null and never checked (T038 review R4-7)"
                    IO_LEAK_FOUND=1
                fi
            done
            [ "$IO_LEAK_FOUND" = 0 ] && ok "ingest stdout+stderr captured and scanned clean (T038 review R4-7 -- previously discarded, never inspected)"

            UNEXPECTED_FILES="$(find "$CRED_ISOLATED_DIR" -maxdepth 1 -type f \
                ! -name "$(basename "$DB")" \
                ! -name "$(basename "$DB")-journal" ! -name "$(basename "$DB")-wal" ! -name "$(basename "$DB")-shm" \
                ! -name "$(basename "$STDOUT_CAP")" ! -name "$(basename "$STDERR_CAP")" 2>/dev/null)"
            if [ -n "$UNEXPECTED_FILES" ]; then
                bad "CREDENTIAL LEAK (or unaccounted artifact): the isolated ingest run directory contains unexpected file(s): $UNEXPECTED_FILES (T038 review R4-6 -- a sidecar cache file previously went uncensused)"
            else
                ok "isolated ingest run directory contains only the expected DB + normal SQLite sidecars -- no unaccounted sidecar file was created (T038 review R4-6)"
            fi

            # --- (iv) defense-in-depth: exact/case-insensitive/base64/hex/
            # sliding-window substring scan across the WHOLE DB file (see
            # the HONEST BOUNDARY note above this PART -- this layer has
            # known blind spots and is never the load-bearing check). ---
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
# alignment-shifted base64 (round-3 finding: byte-alignment matters for
# base64 -- a leak encoded with 1 or 2 bytes of padding before it shifts
# every subsequent triplet, producing a DIFFERENT base64 string entirely)
for pad in (1, 2):
    b64_shifted = base64.b64encode(b'\\\\x00' * pad + marker.encode()).decode()
    if b64_shifted.encode() in data:
        hits.append('base64-shifted-%d' % pad)
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
                    ok "defense-in-depth encoding scan clean (exact, case-insensitive, base64 incl. 2 alignment shifts, hex, 12-char sliding window) -- PLUS the load-bearing structural allowlist above (T038 review finding F1 defense-in-depth; see this PART's HONEST BOUNDARY note for this layer's known remaining blind spots, e.g. reversal/rot13/compression, which the structural allowlist -- not this layer -- is what actually covers)"
                else
                    bad "CREDENTIAL LEAK: an encoded/partial variant of the planted marker ($ENCODING_SCAN) reached the telemetry DB ($DB) -- the exact-string grep alone would have missed this"
                fi
            fi
        fi
    else
        bad "FR-013/SC-005 property (e) UNMET: transcript_ingest.py absent — no telemetry DB exists to scan; credential safety of the eventual ingest path is unproven (paired mutation once T038 lands, per plan.md T-A06: an implementation that ingests message bodies verbatim would leak the marker and this exact assertion would then correctly FAIL)"
    fi
fi

# =============================================================================
# PART F — decoupling: transcript_ingest.py's item=<prefix>-<digits> tagging
#          is CONFIGURABLE, not hardcoded to the literal "ATM-" prefix
#          (§11.4.28/§11.4.177; T048 S9 independent-review remediation,
#          2026-10-03). The reviewer found this file's own ITEM_TAG_RE
#          hard-coded "ATM-" verbatim -- a project-literal leak inside this
#          project-agnostic constitution-submodule engine (a DIFFERENT
#          consuming project whose item-id prefix is not "ATM" would get
#          ZERO item/token attribution, silently). The fix reuses the SAME
#          configurable mechanism `tokens/dispatch_stamp.sh` (T036) already
#          established on this SAME field: `FC_DISPATCH_ITEM_ID_RE` (full
#          override) and `FC_DISPATCH_EXTRA_ITEM_PREFIXES` (additive) env
#          vars, with the DEFAULT prefix derived (never hardcoded) via
#          `scripts/release_prefix.sh` -- for THIS checkout the derived
#          default is "ATM" (release prefix "atmosphere"), so the default
#          (unconfigured) behaviour matches the old hardcode's set of
#          accepted ids for every existing caller (the built regex itself
#          is NOT byte-identical -- it wraps the derived prefix in a
#          non-capturing group, `(?:ATM)-[0-9]+`, vs the old bare literal
#          `ATM-[0-9]+`; corrected per T048 S9 independent review finding
#          M2, 2026-10-03 -- this comment previously overstated it).
# =============================================================================
echo "=== PART F: item= tag prefix is configurable (not hardcoded 'ATM-') ==="

# F-needle (§11.4.273(b)/C-004): prove this test's own detection of "which
# mechanism name" transcript_ingest.py and dispatch_stamp.sh agree on is not
# a fabrication -- both files MUST literally mention the SAME env var names.
DISPATCH_STAMP_MENTIONS_EXTRA="$(grep -c 'FC_DISPATCH_EXTRA_ITEM_PREFIXES' "$DISPATCH_STAMP" 2>/dev/null || echo 0)"
INGEST_MENTIONS_EXTRA="$(grep -c 'FC_DISPATCH_EXTRA_ITEM_PREFIXES' "$TRANSCRIPT_INGEST" 2>/dev/null || echo 0)"
needle_check "dispatch_stamp.sh (T036) genuinely defines the FC_DISPATCH_EXTRA_ITEM_PREFIXES mechanism (control needle: the real file, not an invented name)" 1 "$([ "${DISPATCH_STAMP_MENTIONS_EXTRA:-0}" -gt 0 ] && echo 1 || echo 0)"
needle_check "a FABRICATED, distinct env-var name is NOT present in dispatch_stamp.sh" 0 "$(grep -c 'FC_DISPATCH_SOME_NAME_THAT_DOES_NOT_EXIST' "$DISPATCH_STAMP" 2>/dev/null | grep -qv '^0$' && echo 1 || echo 0)"

EXTRAPFX_FIX="$FIX/extra_prefix_attribution/parent_session.jsonl"
EXTRAPFX_SUB="$FIX/extra_prefix_attribution/parent_session/subagents/agent-fixturet020extrapfx01.jsonl"
if [ ! -f "$EXTRAPFX_FIX" ] || [ ! -f "$EXTRAPFX_SUB" ]; then
    bad "fixture(s) missing: $EXTRAPFX_FIX / $EXTRAPFX_SUB"
else
    needle_check "the extra_prefix_attribution fixture's dispatch carries the real item=SPK-4321 tag" 1 "$(grep -Fq 'item=SPK-4321' "$EXTRAPFX_FIX" && echo 1 || echo 0)"
    needle_check "the fixture does NOT fabricate an item=ATM-4321 tag instead" 0 "$(grep -Fq 'item=ATM-4321' "$EXTRAPFX_FIX" && echo 1 || echo 0)"

    if [ -f "$TRANSCRIPT_INGEST" ]; then
        # --- F1: NEGATIVE CONTROL (T048 S9 independent review finding M2,
        # 2026-10-03 -- relabelled; this case was mislabeled "RED" below,
        # but it is a negative control, not a RED fixture: it passes BOTH
        # before T048's decoupling fix (the old hardcode never matched a
        # non-ATM prefix either) AND after it (the new, configurable
        # default stays ATM-only when unconfigured) -- it never transitions
        # from FAIL to PASS across the fix, which is what "RED" would mean
        # here. Its genuine job is proving the default prefix alternation
        # does NOT silently widen on its own (the §11.4.6 "never silently
        # widen the default" guarantee) -- today's (post-fix) code MUST
        # still refuse the unconfigured SPK- tag by default. Run WITHOUT
        # FC_DISPATCH_EXTRA_ITEM_PREFIXES set at all (unset, not merely
        # empty) so no ambient value from the invoking shell leaks in.
        DB_F1="$WORK/telemetry_f1.db"
        OUT_F1="$(env -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u FC_DISPATCH_ITEM_ID_RE python3 "$TRANSCRIPT_INGEST" ingest "$EXTRAPFX_FIX" --db "$DB_F1" 2>&1)"
        RC_F1=$?
        if [ "$RC_F1" -eq 0 ] && [ -f "$DB_F1" ]; then
            UNCONFIGURED_ITEM="$(sqlite3 -noheader "$DB_F1" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_extrapfx_sub_a1';")"
            needle_check "DEFAULT (unconfigured) behaviour: the SPK-4321 subagent row is NOT item-attributed (item_id empty/NULL) — the default prefix alternation never silently widens, and this MATCHES this project's pre-fix behaviour for every existing ATM-only caller in the SET OF IDS IT ACCEPTS (though the built regex itself is not byte-identical -- see transcript_ingest.py's own ITEM_TAG_RE DECOUPLING FIX comment)" 1 "$([ -z "$UNCONFIGURED_ITEM" ] && echo 1 || echo 0)"
        else
            bad "PART F1 setup failed: transcript_ingest.py did not run cleanly unconfigured against the extra_prefix_attribution fixture: rc=$RC_F1 out=$OUT_F1"
        fi

        # --- F2: GREEN — with FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK configured
        # (the SAME mechanism dispatch_stamp.sh already exposes, never an
        # invented one), the SAME fixture's SPK-4321 tag IS extracted.
        DB_F2="$WORK/telemetry_f2.db"
        OUT_F2="$(FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK python3 "$TRANSCRIPT_INGEST" ingest "$EXTRAPFX_FIX" --db "$DB_F2" 2>&1)"
        RC_F2=$?
        if [ "$RC_F2" -eq 0 ] && [ -f "$DB_F2" ]; then
            CONFIGURED_ITEM="$(sqlite3 -noheader "$DB_F2" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_extrapfx_sub_a1';")"
            needle_check "CONFIGURED (FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK) behaviour: the SPK-4321 subagent row IS item-attributed to 'SPK-4321' (the real tagged value, not a fabricated one)" 1 "$([ "$CONFIGURED_ITEM" = "SPK-4321" ] && echo 1 || echo 0)"
            needle_check "CONFIGURED behaviour: item_id is NOT a fabricated, distinct value" 0 "$([ "$CONFIGURED_ITEM" = "ATM-0000-fabricated" ] && echo 1 || echo 0)"
        else
            bad "PART F2 setup failed: transcript_ingest.py did not run cleanly with FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK against the extra_prefix_attribution fixture: rc=$RC_F2 out=$OUT_F2"
        fi

        # --- F3: backward-compatibility — the pre-existing PART D fixture
        # (a genuine item=ATM-9999 tag) MUST STILL attribute correctly even
        # with FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK configured (additive,
        # never replacing the derived default) -- this is the "default
        # ATM- ids still correctly extracted" half of the task's required
        # backward-compatibility proof, exercised under the SAME configured
        # environment as F2 above (not merely the already-passing PART D's
        # own unconfigured run).
        if [ -f "$PARENT_FIX" ]; then
            DB_F3="$WORK/telemetry_f3.db"
            OUT_F3="$(FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK python3 "$TRANSCRIPT_INGEST" ingest "$PARENT_FIX" --db "$DB_F3" 2>&1)"
            RC_F3=$?
            if [ "$RC_F3" -eq 0 ] && [ -f "$DB_F3" ]; then
                ATM_STILL_WORKS="$(sqlite3 -noheader "$DB_F3" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
                needle_check "backward-compat: with FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK configured, a genuine item=ATM-9999 tag STILL attributes correctly to 'ATM-9999' (additive, never replacing the derived default)" 1 "$([ "$ATM_STILL_WORKS" = "ATM-9999" ] && echo 1 || echo 0)"
            else
                bad "PART F3 setup failed: transcript_ingest.py did not run cleanly with FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK against the PART D ATM-9999 fixture: rc=$RC_F3 out=$OUT_F3"
            fi
        else
            bad "PART F3 precondition missing: $PARENT_FIX (the PART D fixture) not found — cannot verify backward-compatible ATM- attribution under a configured environment"
        fi

        # NOTE: the `${VAR-x}` single-dash form (never `${VAR:-x}`) is
        # deliberate here -- `:-` substitutes on EITHER unset OR a
        # legitimately-empty value, which would misreport
        # $UNCONFIGURED_ITEM's correct, intentional empty-string result
        # (NULL item_id, cast to "" by sqlite3) as "F1 never ran". The
        # single-dash form substitutes ONLY when truly unset (the F1
        # block was skipped), which is the real failure case this
        # aggregate check must distinguish from a genuine empty result.
        if [ "$RC_F1" -eq 0 ] && [ -z "${UNCONFIGURED_ITEM-UNSET}" ] && [ "${CONFIGURED_ITEM-}" = "SPK-4321" ] && [ "${ATM_STILL_WORKS-}" = "ATM-9999" ]; then
            ok "PART F HOLDS: transcript_ingest.py's item= tag prefix is genuinely CONFIGURABLE via the SAME FC_DISPATCH_EXTRA_ITEM_PREFIXES/FC_DISPATCH_ITEM_ID_RE mechanism dispatch_stamp.sh already exposes -- unconfigured default stays ATM-only (matching, not byte-identical to, the pre-fix hardcode's accepted-id set), a configured extra prefix (SPK) is genuinely extracted, and the default ATM- extraction is preserved additively under that same configured environment"
        else
            bad "PART F UNMET: decoupling fix did not take full effect — unconfigured_item='${UNCONFIGURED_ITEM-<F1-never-ran>}' (want empty) configured_item='${CONFIGURED_ITEM-<F2-never-ran>}' (want SPK-4321) atm_still_works='${ATM_STILL_WORKS-<F3-never-ran>}' (want ATM-9999)"
        fi
    else
        bad "PART F UNMET: transcript_ingest.py absent — the item= tag prefix decoupling fix is unverified"
    fi
fi

# =============================================================================
# PART F4-F7 — T048 S9 remediation round (independent Opus-xhigh review
#          finding I2, 2026-10-03): the PART F block above only ever
#          exercised the ADDITIVE FC_DISPATCH_EXTRA_ITEM_PREFIXES tier with
#          the DEFAULT prefix fixed at "ATM" (this checkout's own real
#          value). It never exercised: (1) a DIFFERENT project deriving its
#          OWN default prefix from a DIFFERENT HELIX_RELEASE_PREFIX; (2) the
#          FC_DISPATCH_ITEM_ID_RE FULL-OVERRIDE tier taking genuine priority
#          over everything else; (3) the neutral "WIT" fallback; and (4,
#          "most important" per the reviewer) an ingest run whose PROCESS
#          cwd is itself INSIDE constitution/ — the exact precondition the
#          sibling S8 fix (release_prefix.sh's own cwd-anchoring, see that
#          file's header) exists to close, and the one scenario that would
#          have caught I1 (this file's own dependence on S8 having already
#          landed) before it ever reached review.
# =============================================================================
echo "=== PART F4-F7: prefix derivation under a different project, full-override priority, WIT fallback, and cwd-independence ==="

# probe_item_tag_match <test-string> -- genuinely imports and calls the
# REAL _build_item_tag_re() (never a harness reimplementation of the
# 3-tier priority logic -- the function's OWN docstring explicitly invites
# exactly this: "so a test can call it directly after monkeypatching
# os.environ"), rebuilding it FRESH against WHATEVER env vars are
# currently exported in the invoking shell (real subprocess call through
# to the real release_prefix.sh when relevant -- nothing here is mocked),
# and prints 1 if the freshly-built regex matches <test-string>, else 0.
probe_item_tag_match() {
    python3 - "$(dirname "$TRANSCRIPT_INGEST")" "$1" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import transcript_ingest as ti
re_obj = ti._build_item_tag_re()
print(1 if re_obj.search(sys.argv[2]) else 0)
PYEOF
}

if [ -f "$TRANSCRIPT_INGEST" ]; then
    # =========================================================================
    # F4 — a DIFFERENT project (HELIX_RELEASE_PREFIX != "atmosphere") derives
    #      ITS OWN 3-letter default prefix, never the hardcoded "ATM".
    # =========================================================================
    echo "--- F4: a different project's HELIX_RELEASE_PREFIX derives its OWN default prefix ---"
    # F4-positive: under HELIX_RELEASE_PREFIX=octopusteam (a fabricated,
    # non-"atmosphere" project name, never resembling this project's real
    # prefix by coincidence), the REAL _build_item_tag_re() -- which calls
    # the REAL _fc_default_item_prefix() -> a REAL subprocess invocation of
    # the REAL, unmodified release_prefix.sh with that env var set (case 1
    # of release_prefix.sh's own resolution order: env is authoritative) --
    # must derive "OCT" (first 3 ASCII letters of "octopusteam", uppercased)
    # and match an item=OCT-5555 tag.
    F4_OCT_MATCH="$(HELIX_RELEASE_PREFIX=octopusteam probe_item_tag_match "item=OCT-5555 some dispatch")"
    needle_check "a DIFFERENT project (HELIX_RELEASE_PREFIX=octopusteam) derives its OWN 'OCT' default prefix and matches item=OCT-5555 — never hardcoded 'ATM'" 1 "$F4_OCT_MATCH"
    # F4-negative (same configured environment, the real distinguishing
    # proof -- a prefix match here would mean "OCT" silently ALSO still
    # accepted "ATM", i.e. the derivation did not genuinely change):
    F4_ATM_MATCH="$(HELIX_RELEASE_PREFIX=octopusteam probe_item_tag_match "item=ATM-5555 some dispatch")"
    needle_check "...and that SAME configured environment does NOT also match item=ATM-5555 — the derived prefix genuinely changed, it did not widen" 0 "$F4_ATM_MATCH"

    # F4-integration: the SAME fact demonstrated end-to-end through the
    # REAL ingest CLI + a REAL sqlite3 query against the produced DB,
    # reusing the pre-existing PART D fixture ($PARENT_FIX, a real
    # item=ATM-9999 dispatch) rather than a new fixture: under a different
    # project's HELIX_RELEASE_PREFIX, that SAME ATM-9999-tagged dispatch
    # must NOT be item-attributed (the derived default is "OCT" for this
    # run, not "ATM").
    if [ -f "$PARENT_FIX" ]; then
        DB_F4="$WORK/telemetry_f4.db"
        OUT_F4="$(HELIX_RELEASE_PREFIX=octopusteam env -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u FC_DISPATCH_ITEM_ID_RE python3 "$TRANSCRIPT_INGEST" ingest "$PARENT_FIX" --db "$DB_F4" 2>&1)"
        RC_F4=$?
        if [ "$RC_F4" -eq 0 ] && [ -f "$DB_F4" ]; then
            F4_DB_ITEM="$(sqlite3 -noheader "$DB_F4" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
            needle_check "end-to-end (real ingest CLI + real DB query): under HELIX_RELEASE_PREFIX=octopusteam, the PART D fixture's real item=ATM-9999 tag is NOT attributed (item_id empty/NULL) — confirms F4's regex-level finding at the full-pipeline level, not merely in isolation" 1 "$([ -z "$F4_DB_ITEM" ] && echo 1 || echo 0)"
            if [ "$F4_OCT_MATCH" = "1" ] && [ "$F4_ATM_MATCH" = "0" ] && [ -z "$F4_DB_ITEM" ]; then
                ok "PART F4 HOLDS: transcript_ingest.py's default item-tag prefix is genuinely RE-DERIVED per the configured project's own HELIX_RELEASE_PREFIX (here: 'OCT' for a fabricated 'octopusteam' project), both at the regex-construction level AND end-to-end through the real ingest CLI — never a hardcoded 'ATM' silently surviving under a different project's configuration"
            else
                bad "PART F4 UNMET: oct_match=$F4_OCT_MATCH (want 1) atm_match=$F4_ATM_MATCH (want 0) db_item='$F4_DB_ITEM' (want empty) — the default prefix is not genuinely re-derived per project"
            fi
        else
            bad "PART F4 integration setup failed: transcript_ingest.py did not run cleanly with HELIX_RELEASE_PREFIX=octopusteam against the PART D fixture: rc=$RC_F4 out=$OUT_F4"
        fi
    else
        bad "PART F4 integration precondition missing: $PARENT_FIX (the PART D fixture) not found"
    fi

    # =========================================================================
    # F5 — FC_DISPATCH_ITEM_ID_RE (the FULL-OVERRIDE tier) takes genuine
    #      PRIORITY over BOTH the additive FC_DISPATCH_EXTRA_ITEM_PREFIXES
    #      tier AND the derived-default tier, even when ALL THREE are
    #      configured simultaneously (the hardest, most realistic
    #      competing-configuration case).
    # =========================================================================
    echo "--- F5: FC_DISPATCH_ITEM_ID_RE full override takes priority over the additive AND default tiers ---"
    # All three tiers configured AT ONCE: HELIX_RELEASE_PREFIX (would derive
    # a default), FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK (additive), AND
    # FC_DISPATCH_ITEM_ID_RE=XYZ-[0-9]+ (the override under test). If the
    # override genuinely wins, ONLY "XYZ-" ids are ever extracted.
    F5_XYZ_MATCH="$(HELIX_RELEASE_PREFIX=zzzproject FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+' probe_item_tag_match "item=XYZ-9876 some dispatch")"
    F5_SPK_MATCH="$(HELIX_RELEASE_PREFIX=zzzproject FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+' probe_item_tag_match "item=SPK-9876 some dispatch")"
    F5_ATM_MATCH="$(HELIX_RELEASE_PREFIX=zzzproject FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+' probe_item_tag_match "item=ATM-9876 some dispatch")"
    needle_check "override (XYZ-[0-9]+) matches its OWN pattern (item=XYZ-9876) even with the additive AND default tiers simultaneously configured" 1 "$F5_XYZ_MATCH"
    needle_check "...and does NOT match the ADDITIVE tier's own SPK- prefix (the override REPLACES the whole alternation, never merges with it)" 0 "$F5_SPK_MATCH"
    needle_check "...and does NOT match the DERIVED-DEFAULT tier's ATM- prefix either (the override wins over the default too)" 0 "$F5_ATM_MATCH"

    # F5-integration: the SAME three-way-competing configuration run
    # through the REAL ingest CLI against the pre-existing extra_prefix
    # fixture ($EXTRAPFX_FIX, a real item=SPK-4321 dispatch) — if the
    # override genuinely takes full precedence end-to-end, that real
    # SPK-4321 tag must NOT be attributed despite FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK
    # being simultaneously configured.
    if [ -f "$EXTRAPFX_FIX" ]; then
        DB_F5="$WORK/telemetry_f5.db"
        OUT_F5="$(HELIX_RELEASE_PREFIX=zzzproject FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+' python3 "$TRANSCRIPT_INGEST" ingest "$EXTRAPFX_FIX" --db "$DB_F5" 2>&1)"
        RC_F5=$?
        if [ "$RC_F5" -eq 0 ] && [ -f "$DB_F5" ]; then
            F5_DB_ITEM="$(sqlite3 -noheader "$DB_F5" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_extrapfx_sub_a1';")"
            needle_check "end-to-end (real ingest CLI + real DB query): with the override AND the additive tier BOTH configured, the real item=SPK-4321 dispatch is NOT attributed — the override's precedence holds through the full pipeline, not merely at the regex-construction level" 1 "$([ -z "$F5_DB_ITEM" ] && echo 1 || echo 0)"
            if [ "$F5_XYZ_MATCH" = "1" ] && [ "$F5_SPK_MATCH" = "0" ] && [ "$F5_ATM_MATCH" = "0" ] && [ -z "$F5_DB_ITEM" ]; then
                ok "PART F5 HOLDS: FC_DISPATCH_ITEM_ID_RE genuinely takes FULL PRIORITY over both FC_DISPATCH_EXTRA_ITEM_PREFIXES and the derived default, even when all three are configured at once, both at the regex-construction level AND end-to-end through the real ingest CLI"
            else
                bad "PART F5 UNMET: xyz_match=$F5_XYZ_MATCH (want 1) spk_match=$F5_SPK_MATCH (want 0) atm_match=$F5_ATM_MATCH (want 0) db_item='$F5_DB_ITEM' (want empty) — the override tier does not genuinely take full priority"
            fi
        else
            bad "PART F5 integration setup failed: transcript_ingest.py did not run cleanly with all three tiers configured against the extra_prefix_attribution fixture: rc=$RC_F5 out=$OUT_F5"
        fi
    else
        bad "PART F5 integration precondition missing: $EXTRAPFX_FIX not found"
    fi

    # =========================================================================
    # F6 — the neutral "WIT" fallback: when the resolved HELIX_RELEASE_PREFIX
    #      value genuinely has NO ASCII letters at all (a project configured
    #      with a digits-only release prefix), _fc_derive_key_prefix()'s own
    #      documented no-letters branch returns "WIT", never a crash and
    #      never a silent re-use of "ATM".
    # =========================================================================
    echo "--- F6: the neutral 'WIT' fallback when no prefix letters can be resolved at all ---"
    # NOTE: `env -u` cannot invoke a bash FUNCTION (it is an external
    # command, not a shell builtin, so `env ... probe_item_tag_match` would
    # try -- and fail -- to exec a binary of that name on $PATH; the
    # `env: 'probe_item_tag_match': No such file or directory` failure
    # mode is exactly this). The plain `VAR=value funcname` prefix-
    # assignment form (used throughout F4/F5 above) is used here instead --
    # it still ONLY affects the single command it prefixes, never leaking
    # into this shell's own environment, and no FC_DISPATCH_* var is set
    # anywhere earlier in this script's own process (every prior use was
    # itself this SAME non-persistent prefix-assignment form), so an
    # explicit `-u` unset is unnecessary here.
    F6_WIT_MATCH="$(HELIX_RELEASE_PREFIX=7042 probe_item_tag_match "item=WIT-6666 some dispatch")"
    F6_ATM_MATCH="$(HELIX_RELEASE_PREFIX=7042 probe_item_tag_match "item=ATM-6666 some dispatch")"
    needle_check "HELIX_RELEASE_PREFIX=7042 (digits-only, no ASCII letters) derives the neutral 'WIT' fallback and matches item=WIT-6666" 1 "$F6_WIT_MATCH"
    needle_check "...and that SAME environment does NOT match item=ATM-6666 (the fallback is genuinely 'WIT', not a disguised 'ATM')" 0 "$F6_ATM_MATCH"

    # F6-integration: the SAME digits-only-prefix environment run through
    # the REAL ingest CLI against the pre-existing PART D fixture
    # (item=ATM-9999) — confirms end-to-end that the WIT-fallback
    # environment does NOT accidentally still attribute the ATM-9999 tag.
    if [ -f "$PARENT_FIX" ]; then
        DB_F6="$WORK/telemetry_f6.db"
        OUT_F6="$(HELIX_RELEASE_PREFIX=7042 env -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u FC_DISPATCH_ITEM_ID_RE python3 "$TRANSCRIPT_INGEST" ingest "$PARENT_FIX" --db "$DB_F6" 2>&1)"
        RC_F6=$?
        if [ "$RC_F6" -eq 0 ] && [ -f "$DB_F6" ]; then
            F6_DB_ITEM="$(sqlite3 -noheader "$DB_F6" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
            needle_check "end-to-end (real ingest CLI + real DB query): under the digits-only HELIX_RELEASE_PREFIX=7042, the PART D fixture's real item=ATM-9999 tag is NOT attributed (item_id empty/NULL)" 1 "$([ -z "$F6_DB_ITEM" ] && echo 1 || echo 0)"
            if [ "$F6_WIT_MATCH" = "1" ] && [ "$F6_ATM_MATCH" = "0" ] && [ -z "$F6_DB_ITEM" ]; then
                ok "PART F6 HOLDS: a digits-only HELIX_RELEASE_PREFIX genuinely derives the neutral 'WIT' fallback (never 'ATM', never a crash), both at the regex-construction level AND end-to-end through the real ingest CLI"
            else
                bad "PART F6 UNMET: wit_match=$F6_WIT_MATCH (want 1) atm_match=$F6_ATM_MATCH (want 0) db_item='$F6_DB_ITEM' (want empty) — the WIT fallback does not genuinely take effect"
            fi
        else
            bad "PART F6 integration setup failed: transcript_ingest.py did not run cleanly with HELIX_RELEASE_PREFIX=7042 against the PART D fixture: rc=$RC_F6 out=$OUT_F6"
        fi
    else
        bad "PART F6 integration precondition missing: $PARENT_FIX (the PART D fixture) not found"
    fi

    # =========================================================================
    # F7 — "MOST IMPORTANT" (reviewer's own wording): an ingest run whose
    #      PROCESS cwd is itself INSIDE constitution/ — the EXACT scenario
    #      this file's own sibling S8 fix (release_prefix.sh's cwd-
    #      anchoring, see that file's header for the full forensic history)
    #      exists to close, and the one scenario that would have caught
    #      this file's I1 cross-dependency on S8 BEFORE it ever reached
    #      review, had it existed then.
    # =========================================================================
    echo "--- F7: ingest run with process cwd INSIDE constitution/ still resolves the real 'ATM' prefix (the I1 cross-dependency scenario) ---"

    # F7-proof (§11.4.199/§11.4.6 — concrete, never merely asserted): before
    # trusting the real assertion below as a genuine regression guard for
    # the I1 defect class, demonstrate -- with REAL git commands run from
    # the SAME cwd this PART's real assertion uses, right now, on the real
    # repository -- that the PRECONDITION the original bug depended on is
    # REAL and reproducible at this exact location TODAY. This replicates
    # ONLY the OLD (pre-S8), now-replaced PRIMARY mechanism release_prefix.sh's
    # own header documents in full ("git rev-parse --show-toplevel" with NO
    # `-C` anchor, operated on the CALLER's ambient cwd) -- HARNESS-ONLY, a
    # faithful historical replica for proof purposes, never a preview of
    # production code and never used to compute anything this test trusts
    # downstream (exactly like has_item_tag()'s own documented role above).
    OLD_BUGGY_ROOT="$(cd "$HERE" && git rev-parse --show-toplevel 2>/dev/null)"
    OLD_BUGGY_PREFIX=""
    if [ -n "$OLD_BUGGY_ROOT" ]; then
        OLD_BUGGY_PREFIX="$(basename "$OLD_BUGGY_ROOT" \
            | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/[^A-Za-z0-9]+/_/g' \
            | tr '[:upper:]' '[:lower:]' \
            | sed -E 's/_+/_/g; s/^_//; s/_$//')"
    fi
    needle_check "PROOF the I1 precondition is still real at this exact cwd: the OLD, pre-S8, un-anchored 'git rev-parse --show-toplevel' genuinely returns the WRONG (constitution-submodule-own) root from inside \$HERE, not the real atmosphere project root" 1 "$([ "$OLD_BUGGY_ROOT" = "$REPO_ROOT/constitution" ] && echo 1 || echo 0)"
    needle_check "PROOF continued: that wrong root's own snake_case name ('${OLD_BUGGY_PREFIX:-<empty>}') is genuinely 'constitution', a real, non-coincidental divergence from the real project's 'atmosphere' prefix (never a false alarm)" 1 "$([ "$OLD_BUGGY_PREFIX" = "constitution" ] && echo 1 || echo 0)"
    I1_PRECONDITION_REAL=0
    if [ "$OLD_BUGGY_ROOT" = "$REPO_ROOT/constitution" ] && [ "$OLD_BUGGY_PREFIX" = "constitution" ]; then
        I1_PRECONDITION_REAL=1
        ok "control fact established: a release_prefix.sh built on the OLD, un-anchored primary mechanism would derive 'constitution' (hence the WRONG item-tag prefix 'CON') from exactly the cwd (\$HERE) the real assertion below uses — proving that assertion is a genuine, non-vacuous regression guard for the I1 defect class, not a test of an already-impossible precondition"
    else
        bad "cannot establish the I1 precondition fact at this cwd (old_root='$OLD_BUGGY_ROOT' old_prefix='$OLD_BUGGY_PREFIX') — investigate before trusting the real assertion below as a genuine regression guard"
    fi

    # F7-real: the REAL, UNMODIFIED transcript_ingest.py, invoked with its
    # OWN PROCESS cwd actually set to $HERE (inside constitution/scripts/
    # fastcycle/tests/ — the exact I1 scenario), against the pre-existing
    # PART D fixture (item=ATM-9999), with NO env override of any kind
    # (the unconfigured default path only, §11.4.6: never silently widen).
    # $PARENT_FIX is passed as an ABSOLUTE path, so the cwd change cannot
    # affect fixture resolution — only the internal prefix-derivation
    # subprocess chain is under test here.
    if [ -f "$PARENT_FIX" ]; then
        DB_F7="$WORK/telemetry_f7.db"
        OUT_F7="$(cd "$HERE" && env -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u FC_DISPATCH_ITEM_ID_RE -u HELIX_RELEASE_PREFIX python3 "$TRANSCRIPT_INGEST" ingest "$PARENT_FIX" --db "$DB_F7" 2>&1)"
        RC_F7=$?
        if [ "$RC_F7" -eq 0 ] && [ -f "$DB_F7" ]; then
            DIR_DEP_ITEM="$(sqlite3 -noheader "$DB_F7" "SELECT item_id FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_attr_sub_a1';")"
            needle_check "ingest run with process cwd=\$HERE (inside constitution/) STILL correctly attributes item=ATM-9999 — the real atmosphere project prefix" 1 "$([ "$DIR_DEP_ITEM" = "ATM-9999" ] && echo 1 || echo 0)"
            needle_check "...and is NOT the OLD-buggy-mechanism's would-be WRONG prefix ('CON-9999')" 0 "$([ "$DIR_DEP_ITEM" = "CON-9999" ] && echo 1 || echo 0)"
            if [ "$I1_PRECONDITION_REAL" = "1" ] && [ "$DIR_DEP_ITEM" = "ATM-9999" ]; then
                ok "PART F7 HOLDS (the reviewer's 'most important' case): running transcript_ingest.py with its process cwd set INSIDE constitution/ (\$HERE) still correctly derives the real project's 'ATM' prefix and attributes item=ATM-9999, end-to-end through the real ingest CLI — the directory-dependence defect class I1 flagged (now closed by S8's release_prefix.sh fix) is proven closed for THIS tool, not merely assumed from S8 landing elsewhere"
            else
                bad "PART F7 UNMET: i1_precondition_real=$I1_PRECONDITION_REAL (want 1) dir_dep_item='$DIR_DEP_ITEM' (want ATM-9999) — the directory-dependence defect is NOT proven closed end-to-end for this tool; investigate release_prefix.sh's cwd-anchoring (or its invocation here) before trusting any other property in this file that depends on the derived default prefix"
            fi
        else
            bad "PART F7 setup failed: transcript_ingest.py did not run cleanly with cwd=\$HERE against the PART D fixture: rc=$RC_F7 out=$OUT_F7"
        fi
    else
        bad "PART F7 precondition missing: $PARENT_FIX (the PART D fixture) not found"
    fi
else
    bad "PART F4-F7 UNMET: transcript_ingest.py absent — the configurable-prefix mechanism's different-project/full-override/WIT-fallback/cwd-independence properties are unverified"
fi

# =============================================================================
# PART G1-G2 -- T048 S9 THIRD remediation round (second independent Opus-
#          xhigh review, 2026-10-03, finding N1): the first remediation
#          round added FAIL-SAFE handling (warn + fall back, never crash)
#          to `_build_item_tag_re()` and `_fc_default_item_prefix()`, but
#          NOTHING in this suite actually exercised those two new fail-
#          safe code paths -- they were reviewer-confirmed by hand only.
#          G1 covers the invalid-FC_DISPATCH_ITEM_ID_RE path;
#          G2 covers the missing/unreachable-release_prefix.sh path.
# =============================================================================
echo "=== PART G1-G2: T048 S9 THIRD review remediation -- fail-safe path tests (N1) ==="

if [ -f "$TRANSCRIPT_INGEST" ]; then
    # =========================================================================
    # G1 -- FC_DISPATCH_ITEM_ID_RE is an INVALID regex (an unclosed bracket
    #      expression, "ATM-[0-9"): _build_item_tag_re()'s own documented
    #      FAIL-SAFE (its re.compile(...) try/except) must (a) emit a named
    #      stderr warning naming the invalid value and (b) fall back to the
    #      derived-default-prefix regex ONLY, never crash the whole module.
    # =========================================================================
    echo "--- G1: invalid FC_DISPATCH_ITEM_ID_RE triggers the named warning + derived-default fallback ---"

    # G1-precondition proof (§11.4.199/§11.4.6, the same discipline PART F7
    # uses for its OLD_BUGGY replica): confirm, with the REAL stdlib `re`
    # module, OUTSIDE any try/except, that this EXACT invalid value
    # genuinely raises re.error when substituted into the EXACT construction
    # transcript_ingest.py itself uses (`"(?:^|\s)item=(%s|\?)" % value_re`)
    # -- never an assumed-broken fixture; HARNESS-ONLY proof the value is a
    # genuine defect trigger, never trusted downstream by itself (exactly
    # like has_item_tag()'s documented role).
    BAD_RE='ATM-[0-9'
    G1_RAISES="$(python3 -c "
import re
try:
    re.compile(r'(?:^|\s)item=(%s|\?)' % '$BAD_RE')
    print(0)
except re.error:
    print(1)
" 2>/dev/null)"
    needle_check "PROOF the configured value genuinely raises re.error when compiled directly (never an assumed-broken fixture)" 1 "$G1_RAISES"

    G1_STDERR_FILE="$WORK/stderr_g1.txt"
    G1_MATCH="$(FC_DISPATCH_ITEM_ID_RE="$BAD_RE" probe_item_tag_match "item=ATM-4242 some dispatch" 2>"$G1_STDERR_FILE")"
    G1_STDERR="$(cat "$G1_STDERR_FILE" 2>/dev/null)"
    needle_check "despite the invalid regex, _build_item_tag_re() does NOT crash and still matches a genuine ATM-<digits> tag via the derived-default fallback" 1 "$G1_MATCH"
    needle_check "the fail-safe emits a NAMED stderr warning mentioning the invalid FC_DISPATCH_ITEM_ID_RE value" 1 "$(printf '%s' "$G1_STDERR" | grep -Fq 'FC_DISPATCH_ITEM_ID_RE' && printf '%s' "$G1_STDERR" | grep -Fq "$BAD_RE" && echo 1 || echo 0)"
    needle_check "...and the warning is genuinely a WARNING (not swallowed, not a generic/unlabelled message)" 1 "$(printf '%s' "$G1_STDERR" | grep -Fq 'WARNING' && echo 1 || echo 0)"

    # G1-discrimination (control-needle rigor, §11.4.194(6)(d) reviewer-
    # authored-mutation discipline): prove the needle_checks above are NOT
    # vacuously true by demonstrating what happens WITHOUT the try/except
    # fail-safe -- a scratch COPY of the real module with ONLY the exact
    # try/except text (never a hand-written reimplementation) removed, run
    # as a REAL subprocess against the SAME invalid value: it MUST crash
    # with an unhandled re.error (never silently "still work"). This proves
    # the fail-safe the needle_checks above exercise is genuinely load-
    # bearing, not decoration -- a future edit that deletes the real
    # try/except would make a REAL rerun of the needle_checks above fail,
    # because they would then observe the SAME crash this control-needle
    # deliberately reproduces on a throwaway copy.
    G1_MUT_GEN="$WORK/g1_mutate.py"
    cat > "$G1_MUT_GEN" <<'PYEOF'
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding="utf-8").read()
OLD = (
    '    try:\n'
    '        return re.compile(r"(?:^|\\s)item=(%s|\\?)" % value_re)\n'
    '    except re.error as exc:\n'
    '        print(\n'
    '            "transcript_ingest: WARNING: the configured item-tag pattern "\n'
    '            "(FC_DISPATCH_ITEM_ID_RE=%r FC_DISPATCH_EXTRA_ITEM_PREFIXES=%r) "\n'
    '            "is not a valid regex (%s) -- falling back to the derived "\n'
    '            "default prefix only for this run; item attribution via the "\n'
    '            "misconfigured value is LOST until the env var is fixed"\n'
    '            % (override, os.environ.get("FC_DISPATCH_EXTRA_ITEM_PREFIXES", ""), exc),\n'
    '            file=sys.stderr,\n'
    '        )\n'
    '        fallback_prefix = _fc_default_item_prefix()\n'
    '        return re.compile(r"(?:^|\\s)item=((?:%s)-[0-9]+|\\?)" % fallback_prefix)\n'
)
NEW = '    return re.compile(r"(?:^|\\s)item=(%s|\\?)" % value_re)\n'
if src.count(OLD) != 1:
    sys.stderr.write("MUTATION_SETUP_FAILED matches=%d\n" % src.count(OLD))
    sys.exit(2)
open(dst_path, "w", encoding="utf-8").write(src.replace(OLD, NEW, 1))
PYEOF
    MUT_G1="$WORK/transcript_ingest_mut_g1.py"
    MUT_G1_SETUP_ERR="$(python3 "$G1_MUT_GEN" "$TRANSCRIPT_INGEST" "$MUT_G1" 2>&1)"
    MUT_G1_SETUP_RC=$?
    if [ "$MUT_G1_SETUP_RC" -eq 0 ] && [ -f "$MUT_G1" ]; then
        # NOTE: the exception's printed CLASS NAME is Python-version-
        # dependent (e.g. CPython 3.13 renamed the concrete class backing
        # `re.error` to `re.PatternError`, with `re.error` kept as an
        # alias) -- so this classifies the caught exception via `isinstance
        # (..., re.error)` (the alias, stable across versions) rather than
        # grepping a traceback for a literal class-name string, which would
        # itself be a §11.4.201(7) wrong-layer/version-fragile instrument.
        # NOTE: the mutated module's own module-level statement
        # `ITEM_TAG_RE = _build_item_tag_re()` runs DURING
        # `spec.loader.exec_module(mod)` (import time), BEFORE this
        # driver's own explicit `mod._build_item_tag_re()` call ever
        # executes -- so the try/except below wraps `exec_module` itself,
        # not merely the later explicit call, to actually observe the
        # real crash point rather than one that (with the fail-safe
        # genuinely removed) never gets reached a second time.
        G1_MUT_OUT="$(cd "$(dirname "$MUT_G1")" && FC_DISPATCH_ITEM_ID_RE="$BAD_RE" python3 -c "
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location('transcript_ingest_mut_g1', '$MUT_G1')
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
    mod._build_item_tag_re()
    print('NO_CRASH')
except re.error as exc:
    print('CRASHED_WITH_RE_ERROR: %r' % exc)
    sys.exit(1)
except Exception as exc:
    print('CRASHED_WITH_OTHER: %r' % exc)
    sys.exit(1)
" 2>&1)"
        MUT_G1_RC=$?
        needle_check "control-needle: the SAME invalid value against a mutated copy with the fail-safe try/except REMOVED genuinely CRASHES (non-zero exit) -- proving the real file's try/except is load-bearing, not decoration" 1 "$([ "$MUT_G1_RC" -ne 0 ] && echo 1 || echo 0)"
        needle_check "...and the crash is specifically the unhandled re.error this fail-safe exists to catch (never a different, coincidental failure)" 1 "$(printf '%s' "$G1_MUT_OUT" | grep -Fq 'CRASHED_WITH_RE_ERROR' && echo 1 || echo 0)"
    else
        bad "G1 mutation-discrimination setup failed (rc=$MUT_G1_SETUP_RC err=$MUT_G1_SETUP_ERR) -- cannot prove the fail-safe is load-bearing; investigate before trusting the G1 needle_checks above as a genuine regression guard"
    fi

    # =========================================================================
    # G2 -- release_prefix.sh is MISSING/UNREACHABLE: the reviewer's own
    #      "scratch copy of the tree" technique -- a byte-identical copy of
    #      transcript_ingest.py relocated so its self-relative resolution of
    #      release_prefix.sh (self_dir/../../release_prefix.sh) genuinely
    #      finds nothing. _fc_default_item_prefix()'s own documented
    #      FAIL-SAFE must (a) emit a named stderr warning naming the
    #      unreachable path and (b) fall back to the neutral "WIT" prefix.
    # =========================================================================
    echo "--- G2: missing/unreachable release_prefix.sh triggers the named warning + 'WIT' fallback ---"

    SCRATCH_G2="$WORK/scratch_g2/constitution/scripts/fastcycle/tokens"
    mkdir -p "$SCRATCH_G2"
    cp "$TRANSCRIPT_INGEST" "$SCRATCH_G2/transcript_ingest.py"
    needle_check "G2 precondition: the scratch copy is byte-identical to the real, unmodified transcript_ingest.py (never a harness reimplementation -- only the FILESYSTEM location is manipulated)" 1 "$(cmp -s "$TRANSCRIPT_INGEST" "$SCRATCH_G2/transcript_ingest.py" && echo 1 || echo 0)"
    needle_check "G2 precondition: the scratch tree genuinely lacks release_prefix.sh at the exact relative path _fc_default_item_prefix() resolves (self_dir/../../release_prefix.sh)" 1 "$([ ! -f "$WORK/scratch_g2/constitution/scripts/release_prefix.sh" ] && echo 1 || echo 0)"

    G2_STDERR_FILE="$WORK/stderr_g2.txt"
    G2_WIT_MATCH="$(cd "$WORK" && env -u FC_DISPATCH_ITEM_ID_RE -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u HELIX_RELEASE_PREFIX python3 -c "
import sys
sys.path.insert(0, '$SCRATCH_G2')
import transcript_ingest as ti
re_obj = ti._build_item_tag_re()
print(1 if re_obj.search('item=WIT-7777 some dispatch') else 0)
" 2>"$G2_STDERR_FILE")"
    G2_ATM_MATCH="$(cd "$WORK" && env -u FC_DISPATCH_ITEM_ID_RE -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u HELIX_RELEASE_PREFIX python3 -c "
import sys
sys.path.insert(0, '$SCRATCH_G2')
import transcript_ingest as ti
re_obj = ti._build_item_tag_re()
print(1 if re_obj.search('item=ATM-7777 some dispatch') else 0)
" 2>/dev/null)"
    G2_STDERR="$(cat "$G2_STDERR_FILE" 2>/dev/null)"
    needle_check "the fail-safe emits a NAMED stderr warning naming the missing script's resolved path" 1 "$(printf '%s' "$G2_STDERR" | grep -Fq 'WARNING' && printf '%s' "$G2_STDERR" | grep -Fq 'scratch_g2' && printf '%s' "$G2_STDERR" | grep -Fq 'release_prefix.sh' && echo 1 || echo 0)"
    needle_check "...and explicitly says the script was not found" 1 "$(printf '%s' "$G2_STDERR" | grep -Fq 'not found' && echo 1 || echo 0)"
    needle_check "missing release_prefix.sh falls back to the neutral item=WIT-<digits> tag" 1 "$G2_WIT_MATCH"
    needle_check "...and does NOT match item=ATM-<digits> either (this real project's own prefix is NOT silently reused when release_prefix.sh is unreachable)" 0 "$G2_ATM_MATCH"

    # G2-discrimination (control-needle rigor): a SECOND scratch copy with
    # ONLY the warning's print(...) call removed (the fallback-to-WIT
    # BEHAVIOUR is deliberately left intact, isolating the diagnostic from
    # the functional fallback) proves the needle_checks above genuinely
    # depend on that print existing -- behaviour unchanged, diagnostic gone,
    # and the SAME stderr-content needle_checks correctly flip to FAIL
    # against it, proving they are not vacuously true.
    G2_MUT_GEN="$WORK/g2_mutate.py"
    cat > "$G2_MUT_GEN" <<'PYEOF'
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding="utf-8").read()
OLD = (
    '    else:\n'
    '        print(\n'
    '            "transcript_ingest: WARNING: %s not found -- falling back to "\n'
    '            "the neutral \'WIT\' item-tag prefix for this run" % rp_script,\n'
    '            file=sys.stderr,\n'
    '        )\n'
)
NEW = '    else:\n        pass\n'
if src.count(OLD) != 1:
    sys.stderr.write("MUTATION_SETUP_FAILED matches=%d\n" % src.count(OLD))
    sys.exit(2)
open(dst_path, "w", encoding="utf-8").write(src.replace(OLD, NEW, 1))
PYEOF
    SCRATCH_G2B="$WORK/scratch_g2b/constitution/scripts/fastcycle/tokens"
    mkdir -p "$SCRATCH_G2B"
    MUT_G2_SETUP_ERR="$(python3 "$G2_MUT_GEN" "$TRANSCRIPT_INGEST" "$SCRATCH_G2B/transcript_ingest.py" 2>&1)"
    MUT_G2_SETUP_RC=$?
    if [ "$MUT_G2_SETUP_RC" -eq 0 ] && [ -f "$SCRATCH_G2B/transcript_ingest.py" ]; then
        G2_MUT_STDERR_FILE="$WORK/stderr_g2_mut.txt"
        G2_MUT_WIT_MATCH="$(cd "$WORK" && env -u FC_DISPATCH_ITEM_ID_RE -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u HELIX_RELEASE_PREFIX python3 -c "
import sys
sys.path.insert(0, '$SCRATCH_G2B')
import transcript_ingest as ti
re_obj = ti._build_item_tag_re()
print(1 if re_obj.search('item=WIT-8888 some dispatch') else 0)
" 2>"$G2_MUT_STDERR_FILE")"
        G2_MUT_STDERR="$(cat "$G2_MUT_STDERR_FILE" 2>/dev/null)"
        needle_check "control-needle: with the diagnostic print REMOVED but the fallback BEHAVIOUR intact, the functional fallback to WIT still holds (proves this mutation isolates the diagnostic, not the behaviour)" 1 "$G2_MUT_WIT_MATCH"
        needle_check "control-needle: ...but the SAME stderr-content check this PART's needle_checks use now correctly reports the warning ABSENT -- proving those needle_checks are not vacuously true" 0 "$(printf '%s' "$G2_MUT_STDERR" | grep -Fq 'not found' && echo 1 || echo 0)"
    else
        bad "G2 mutation-discrimination setup failed (rc=$MUT_G2_SETUP_RC err=$MUT_G2_SETUP_ERR) -- cannot prove the warning-presence needle_checks are discriminating; investigate before trusting the G2 needle_checks above as a genuine regression guard"
    fi
else
    bad "PART G1-G2 UNMET: transcript_ingest.py absent -- the two fail-safe code paths (invalid FC_DISPATCH_ITEM_ID_RE, missing release_prefix.sh) are unverified"
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
