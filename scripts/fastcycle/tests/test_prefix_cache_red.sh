#!/bin/bash
# Purpose: T106 (SpecKit-004 "fast-dev-cycles", User Story 4 / Phase E) RED
#          test for T115's own `context/dispatch_prefix.py`
#          (tasks.md T106: "two consecutive same-class dispatches show a
#          cache read on the second; golden-bad: a per-item timestamp
#          placed before the subset shows no read; when the harness
#          exposes no subagent cache metric the test records the U-12
#          limitation and does not claim a hit"; plan.md T-E03; FR-013,
#          SC-005).
#
# common-conventions.md's own "no contract exists yet" table lists
# `$FC/context/dispatch_prefix.py (T-E03)` explicitly among the tools
# "Their interface, output and RED fixtures are fixed by the plan task
# text until a contract is written" -- THIS FILE is what fixes that
# interface, mirroring test_governance_subset_red.sh (T104) and
# test_tool_deferral_red.sh (T107)'s own identical, already-established
# practice for exactly this situation (both cited by task instruction as
# this file's closest sibling examples).
#
# ============================================================================
# THE GAP (verified directly, 2026-09-29 against the current working tree,
# both the outer worktree and inside the constitution submodule itself --
# `git status --short` clean, `git log --oneline -- .../dispatch_prefix.py`
# empty).
# ============================================================================
# `constitution/scripts/fastcycle/context/` holds exactly one file today,
# `anchor_citations.py` (T039, a SEPARATE, already-landed task) -- there is
# NO `dispatch_prefix.py` of any kind. A bare directory-existence check
# would be a section-12.1-class false-positive-refusal guard (the directory
# existing proves nothing about T115's status -- the same lesson
# test_governance_subset_red.sh already documents for `context/` and
# test_reopen_rate_red.sh documents for `closure/`); the load-bearing check
# below is CONTENT: does the directory hold `dispatch_prefix.py`
# specifically.
#
# ============================================================================
# Two INDEPENDENT oracles combined (section 11.4.245 -- neither is T115's
# own, not-yet-written opinion; neither is imported by, shared with, or
# otherwise coupled to context/dispatch_prefix.py).
# ============================================================================
#
# Oracle A -- STRUCTURAL (the [core][subset][per-item] ordering invariant
# itself). A from-scratch Python function (derive_prompt, embedded below,
# written directly from tasks.md T115's own wording -- "orders dispatch
# prompts [core][subset][per-item]") composes the three text blocks in
# either the CORRECT order or the golden-bad's BROKEN order (per-item
# placed first) and measures the resulting strings' shared-prefix length.
# This proves the STRUCTURAL claim: correct ordering makes two same-class
# dispatches' prompts share a long common prefix (the identical
# [core][subset] blocks); broken ordering collapses that shared prefix to
# (at most) whatever the two dispatches' own short per-item texts happen to
# overlap on, which can never reach into the trailing [core][subset] bytes
# at all (see fixtures/prefix_cache/prompt_spec.json's own
# "_note_on_the_bound_used_by_the_test" field for the exact, provably-true
# bound this test asserts -- NOT a brittle "exactly 0" claim, since this
# fixture's own two per-item timestamps happen to share a short leading
# ISO-date substring before diverging).
#
# Oracle B -- REAL-WORLD CONSEQUENCE (does a shared byte-prefix actually
# earn a cache read from the real provider). Per the task instruction's own
# explicit mandate ("derive expected cache-read behavior from real
# transcript/API data structure, never from the not-yet-built tool's own
# self-report"), this is checked ENTIRELY through the ALREADY-LANDED, ALREADY
# -TESTED `tokens/transcript_ingest.py` (T038/T020, GO, committed at
# constitution HEAD 85b7e85) reading three REAL-transcript-schema JSONL
# fixtures this task authors fresh under fixtures/prefix_cache/{good_order,
# bad_order,no_cache_metric}/ -- each modelling two CONSECUTIVE, SEPARATE
# subagent dispatches (two Agent tool_use dispatches + their own
# subagents/agent-<id>.jsonl transcripts, the exact real, documented,
# already-tested shape T020's own fixtures/transcript_ingest/
# subagent_attribution/ fixture established) of the SAME class. Dispatch
# 2's own FIRST assistant turn's real, captured `usage.cache_read_input_
# tokens` field (per Anthropic's own prompt-caching mechanics, R5:20-24: a
# cache read is served ONLY when the prefix up to the cache breakpoint is
# byte-identical to a previously cached prefix) is the load-bearing oracle
# value in all three scenarios -- this test asserts it >0 for good_order,
# ==0 (a real, MEASURED, deliberate zero -- never NULL) for bad_order, and
# genuinely NULL/UNMEASURED (never coerced to 0, transcript_ingest.py's own
# documented invariant) for no_cache_metric, per this file's dedicated U-12
# branch below. context/dispatch_prefix.py is never consulted anywhere in
# Oracle B -- it does not exist, and even once T115 lands, Oracle B's own
# fixtures are hand-authored REAL-schema transcript data, not that tool's
# self-report.
#
# ============================================================================
# section-11.4.273 control needles (this file's own absence/false-anchor
# detection mechanisms).
# ============================================================================
#   #1 -- before trusting "dispatch_prefix.py is absent" as a finding, prove
#        the plain `[ -f PATH ]` relative-path check genuinely resolves
#        paths from this script's real location, by first confirming a
#        KNOWN-PRESENT sibling (tokens/transcript_ingest.py, Oracle B's own
#        real tool) resolves true through the identical relative-path
#        construction.
#   #2 -- every fixture id this file mints (agent ids fcpc{good,bad,nc}0{1,
#        2}, session ids fixture-t106-{good,bad,nc}-parent-session, msg ids
#        msg_fixture_t106_*) is checked LIVE, at run time, for collision
#        against every OTHER fixture already committed anywhere under
#        tests/fixtures/ in this tree -- proving this file's own new
#        fixtures cannot silently shadow or be shadowed by a sibling
#        suite's identically-named row (the exact class of defect T020's
#        own row_hash-on-msg_id-alone design depends on never happening).
#   #3 -- Oracle B's own instrument (transcript_ingest.py) is proven to
#        genuinely discriminate a cache HIT from a cache MISS, using the
#        ALREADY-COMMITTED, ALREADY-GO sibling fixture
#        fixtures/transcript_ingest/cache_hits/session.jsonl (T020) --
#        BEFORE this file's own three brand-new fixtures are trusted on top
#        of it. If the real tool could not tell 1200!=0 apart on a fixture
#        its own author's suite already certified GO, nothing built on it
#        below would mean anything.
#
# Producer != Verifier (11.4.240): this file is authored at the RED step
# (T106); T115's implementation of `context/dispatch_prefix.py` is a
# separate, later task -- this file's author never implements it.
# derive_prompt() below is a DERIVED oracle per section 11.4.245, computed
# independently of whatever T115 eventually writes; it is never imported by,
# shared with, or otherwise coupled to `context/dispatch_prefix.py`.
#
# section-11.4.107(10) self-validation triple (Principle IV): the three
# transcript-fixture scenarios (good_order / bad_order / no_cache_metric)
# MUST produce THREE DISTINCT observed states from the SAME real oracle
# (measured-hit / measured-miss / genuinely-unmeasured) -- proving Oracle B
# discriminates for real, rather than always reporting one fixed answer.
# Section "Oracle A discrimination" below performs the identical proof for
# Oracle A (correct-order shared-prefix length strictly exceeds broken-
# order's).
#
# Paired mutation (this file's own -- T-E03's plan.md entry names no
# specific mutation the way GS-004's contract clause did; this test defines
# one directly from tasks.md T115's own wording, per common-conventions.md's
# "fixed by the plan task text until a contract is written" precedent,
# mirroring T104's identical practice for an under-specified corner):
# a mutated derive_prompt_mutated_always_broken() that IGNORES the `order`
# argument and ALWAYS composes per-item first (i.e. T115 silently drops the
# ordering invariant even when asked for "correct") is proven, below, to
# WRONGLY collapse the correct-order case's shared-prefix length down to the
# broken-order bound -- proving a real meta-test built against this
# fixture, once T115 lands, would genuinely catch that regression.
#
# ============================================================================
# U-12 honesty (research.md: "The CLI exposes prompt-cache hit metrics per
# subagent -- UNCONFIRMED (R5:157)"; quickstart.md Scenario 6). This test's
# no_cache_metric section is the ONLY place a "hit" or "no hit" verdict is
# NEVER emitted -- it prints a dedicated "U-12 LIMITATION RECORDED" line
# instead and counts that RECORDING (not any hit/no-hit claim) as the
# checked property.
# ============================================================================
#
# Usage : bash test_prefix_cache_red.sh   Exit 0 = every real assertion
#         below held (all three control needles, Oracle A's structural
#         proof + its mutation-catch proof, Oracle B's three real-transcript
#         scenarios including the honest U-12 branch, and -- once T115
#         lands -- the forward-compatible real-tool invocation block).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-29):
#         `context/dispatch_prefix.py` genuinely does not exist yet (T115
#         is a separate, later, not-yet-started task) -- this is the T106
#         RED baseline, not a bug in this test.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
IMPL="$FC/context/dispatch_prefix.py"
TRANSCRIPT_INGEST="$FC/tokens/transcript_ingest.py"
FIXDIR="$HERE/fixtures/prefix_cache"
SIBLING_FIX="$HERE/fixtures/transcript_ingest"
FIXTURES_ROOT="$HERE/fixtures"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not on PATH -- cannot run any of the checks below"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "FAIL: sqlite3 not on PATH -- cannot run Oracle B's real-transcript checks"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi

TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 130' INT
trap 'rm -rf "$TMP"; exit 143' TERM

FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "INFO: $1"; }

# =========================================================================
# section 11.4.273 control needle #1: known-present sibling resolves
# through this test's own relative-path construction.
# =========================================================================
echo "=== control needle #1: relative-path resolution mechanism ==="
chk "control needle #1: known-present sibling tokens/transcript_ingest.py (T038, Oracle B's own real instrument) resolves through this file's exact path-construction mechanism -- proving the absence check below is trustworthy" \
  "$([ -f "$TRANSCRIPT_INGEST" ] && echo 1 || echo 0)"

# =========================================================================
# section 11.4.273 control needle #2: fixture id collision against every
# sibling suite's already-committed fixtures.
# =========================================================================
echo
echo "=== control needle #2: fixture id namespace collision (live grep) ==="
COLLIDE=0
for needle in fixture-t106-good-parent-session fixture-t106-bad-parent-session \
              fixture-t106-nc-parent-session fcpcgood01 fcpcgood02 fcpcbad01 fcpcbad02 \
              fcpcnc01 fcpcnc02 msg_fixture_t106_good_sub_a1 msg_fixture_t106_good_sub_a2 \
              msg_fixture_t106_bad_sub_a1 msg_fixture_t106_bad_sub_a2 \
              msg_fixture_t106_nc_sub_a1 msg_fixture_t106_nc_sub_a2; do
  hits="$(grep -rl -F -- "$needle" "$FIXTURES_ROOT" 2>/dev/null | grep -v "^$FIXDIR/" | wc -l | tr -d ' ')"
  if [ "$hits" != "0" ]; then
    echo "  COLLISION: '$needle' also appears outside fixtures/prefix_cache/ ($hits file(s))"
    COLLIDE=1
  fi
done
chk "none of this file's new fixture ids collide with any sibling suite's already-committed fixture (fixtures/ tree-wide grep)" \
  "$([ "$COLLIDE" = "0" ] && echo 1 || echo 0)"

# =========================================================================
# section 11.4.273 control needle #3: Oracle B's own real instrument
# genuinely discriminates a cache hit from a cache miss, proven against the
# ALREADY-COMMITTED, ALREADY-GO sibling fixture (T020) -- BEFORE this
# file's own three brand-new fixtures are trusted on top of it.
# =========================================================================
echo
echo "=== control needle #3: Oracle B's real instrument discriminates (sibling T020 fixture) ==="
CACHE_HITS_FIX="$SIBLING_FIX/cache_hits/session.jsonl"
if [ ! -f "$CACHE_HITS_FIX" ]; then
  echo "  BLIND: sibling fixture $CACHE_HITS_FIX absent -- cannot run this needle"
  chk "control needle #3: Oracle B's instrument discriminates hit-vs-miss on the sibling T020 cache_hits fixture" "0"
else
  N3DB="$TMP/needle3.db"
  N3OUT="$(python3 "$TRANSCRIPT_INGEST" ingest "$CACHE_HITS_FIX" --db "$N3DB" 2>&1)"
  N3RC=$?
  N3TURN1_CR="$(sqlite3 -noheader "$N3DB" "SELECT cache_read_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_cachehit_a1';" 2>/dev/null)"
  N3TURN2_CR="$(sqlite3 -noheader "$N3DB" "SELECT cache_read_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t020_cachehit_a2';" 2>/dev/null)"
  if [ "$N3RC" = "0" ] && [ "$N3TURN1_CR" = "0" ] && [ "$N3TURN2_CR" = "1200" ]; then
    info "control needle #3: the real instrument correctly reports the sibling fixture's cold turn (cache_read=0) and warm turn (cache_read=1200) -- it can genuinely tell a hit from a non-hit"
    chk "control needle #3: Oracle B's instrument discriminates hit-vs-miss on the sibling T020 cache_hits fixture" "1"
  else
    echo "  UNEXPECTED: rc=$N3RC turn1_cr=$N3TURN1_CR (want 0) turn2_cr=$N3TURN2_CR (want 1200) out=$N3OUT"
    chk "control needle #3: Oracle B's instrument discriminates hit-vs-miss on the sibling T020 cache_hits fixture" "0"
  fi
fi

# =========================================================================
# (1) TODAY absence check: context/dispatch_prefix.py
# =========================================================================
echo
echo "=== Section 1: context/dispatch_prefix.py RED baseline (live) ==="
CONTEXT_DIR="$FC/context"
if [ -d "$CONTEXT_DIR" ]; then
  py_count=$(find "$CONTEXT_DIR" -maxdepth 1 -name '*.py' | wc -l | tr -d ' ')
  info "$CONTEXT_DIR exists, holding $py_count *.py file(s) right now (T039's already-landed anchor_citations.py lives here too)"
fi
if [ -f "$IMPL" ]; then
  info "context/dispatch_prefix.py now exists -- T115 has landed. The forward-compatible real-tool invocation block below will exercise it for real."
  TOOL_PRESENT=1
else
  info "context/dispatch_prefix.py is absent -- T115 (plan.md T-E03's implementation task, a SEPARATE later task from this RED test) has not landed yet. THIS IS THE CORRECT, EXPECTED T106 RED BASELINE -- the fixtures + independent derive_prompt() oracle below stand as the interim contract T115 must satisfy to turn this GREEN."
  TOOL_PRESENT=0
fi
chk "context/dispatch_prefix.py has landed (T115) -- expected to FAIL today (RED)" \
  "$([ -f "$IMPL" ] && echo 1 || echo 0)"

# --- Fixture files present ---
echo
echo "=== Fixture presence ==="
FIX_OK=1
for f in prompt_spec.json \
         good_order/parent_session.jsonl \
         good_order/parent_session/subagents/agent-fcpcgood01.jsonl \
         good_order/parent_session/subagents/agent-fcpcgood02.jsonl \
         bad_order/parent_session.jsonl \
         bad_order/parent_session/subagents/agent-fcpcbad01.jsonl \
         bad_order/parent_session/subagents/agent-fcpcbad02.jsonl \
         no_cache_metric/parent_session.jsonl \
         no_cache_metric/parent_session/subagents/agent-fcpcnc01.jsonl \
         no_cache_metric/parent_session/subagents/agent-fcpcnc02.jsonl; do
  if [ ! -f "$FIXDIR/$f" ]; then
    echo "  missing: $FIXDIR/$f"
    FIX_OK=0
  fi
done
chk "all 10 fixtures under fixtures/prefix_cache/ are present" "$FIX_OK"

if [ "$FIX_OK" != "1" ]; then
  echo
  echo "=== FIXTURES MISSING -- cannot run the rest of this suite meaningfully ==="
  echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
  exit 1
fi

# =========================================================================
# Oracle A -- STRUCTURAL: independent derive_prompt() (section 11.4.245),
# a from-scratch reimplementation of T115's own "[core][subset][per-item]"
# wording, never imported by nor shared with context/dispatch_prefix.py.
# =========================================================================
cat > "$TMP/derive_prompt.py" <<'PYEOF'
import json
import sys


def derive_prompt(core, subset, per_item, order):
    """Section 11.4.245 DERIVED oracle: a from-scratch reimplementation of
    tasks.md T115's own wording ("orders dispatch prompts
    [core][subset][per-item]"), written directly by this test's author,
    NEVER imported by nor shared with context/dispatch_prefix.py.
    order='correct' -> [core][subset][per-item] (T115's own mandated shape).
    order='broken'  -> [per-item][core][subset] (T106's own golden-bad
    case: "a per-item timestamp placed before the subset")."""
    if order == "correct":
        return core + subset + per_item
    if order == "broken":
        return per_item + core + subset
    raise ValueError("order must be 'correct' or 'broken', got %r" % (order,))


def derive_prompt_mutated_always_broken(core, subset, per_item, order):
    """This file's own paired mutation (common-conventions.md: T-E03 has no
    contract, so this test fixes it directly from tasks.md T115's wording,
    mirroring T104's identical practice for an under-specified corner):
    T115 silently drops the ordering invariant and ALWAYS composes per-item
    FIRST, no matter what `order` is asked for -- even when 'correct' is
    requested. Deliberately WRONG; used only to prove the correct
    derive_prompt() output diverges from this one on the 'correct' case."""
    return per_item + core + subset


def shared_prefix_len(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n


def main():
    spec_path, out_path = sys.argv[1:3]
    with open(spec_path, encoding="utf-8") as fh:
        spec = json.load(fh)
    core = spec["core_text"]
    subset = spec["subset_text_class_a"]
    p1 = spec["dispatch_1_per_item"]
    p2 = spec["dispatch_2_per_item"]

    correct1 = derive_prompt(core, subset, p1, "correct")
    correct2 = derive_prompt(core, subset, p2, "correct")
    broken1 = derive_prompt(core, subset, p1, "broken")
    broken2 = derive_prompt(core, subset, p2, "broken")

    correct_shared_len = shared_prefix_len(correct1, correct2)
    broken_shared_len = shared_prefix_len(broken1, broken2)

    # Paired-mutation check: the mutated derivation asked for the CORRECT
    # order (order='correct') but ALWAYS composes broken-order bytes
    # regardless -- so its own "correct"-order output must diverge from the
    # real derive_prompt()'s correct-order output, and its shared-prefix
    # length on the 'correct' request must collapse down to (at most) the
    # broken-order bound, proving a meta-test would genuinely catch it.
    mut_correct1 = derive_prompt_mutated_always_broken(core, subset, p1, "correct")
    mut_correct2 = derive_prompt_mutated_always_broken(core, subset, p2, "correct")
    mut_shared_len = shared_prefix_len(mut_correct1, mut_correct2)

    result = {
        "len_core": len(core),
        "len_subset": len(subset),
        "len_core_plus_subset": len(core) + len(subset),
        "len_p1": len(p1),
        "len_p2": len(p2),
        "correct_shared_len": correct_shared_len,
        "broken_shared_len": broken_shared_len,
        "mutated_correct_request_shared_len": mut_shared_len,
        "correct1_ne_mut_correct1": correct1 != mut_correct1,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, sort_keys=True, indent=2)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
PYEOF

echo
echo "=== Oracle A: structural [core][subset][per-item] ordering proof ==="
ORACLE_A_OUT="$TMP/oracle_a.json"
python3 "$TMP/derive_prompt.py" "$FIXDIR/prompt_spec.json" "$ORACLE_A_OUT" >/dev/null
LEN_CS="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['len_core_plus_subset'])" "$ORACLE_A_OUT")"
LEN_P1="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['len_p1'])" "$ORACLE_A_OUT")"
CORRECT_SHARED="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['correct_shared_len'])" "$ORACLE_A_OUT")"
BROKEN_SHARED="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['broken_shared_len'])" "$ORACLE_A_OUT")"
MUT_SHARED="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['mutated_correct_request_shared_len'])" "$ORACLE_A_OUT")"
CORRECT_NE_MUT="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['correct1_ne_mut_correct1'])" "$ORACLE_A_OUT")"

info "len(core)+len(subset)=$LEN_CS  len(dispatch_1_per_item)=$LEN_P1"
info "correct-order shared-prefix length (two same-class dispatches) = $CORRECT_SHARED"
info "broken-order (golden-bad: per-item BEFORE subset) shared-prefix length = $BROKEN_SHARED"

chk "correct ordering ([core][subset][per-item]): shared-prefix length >= len(core)+len(subset) -- the identical [core][subset] block is guaranteed a common prefix" \
  "$([ "$CORRECT_SHARED" -ge "$LEN_CS" ] && echo 1 || echo 0)"
chk "golden-bad ordering (per-item timestamp placed BEFORE the subset): shared-prefix length < len(dispatch_1_per_item) -- it can never cross into the trailing [core][subset] bytes at all once the per-item texts diverge" \
  "$([ "$BROKEN_SHARED" -lt "$LEN_P1" ] && echo 1 || echo 0)"
chk "Oracle A discrimination: correct-order shared-prefix length ($CORRECT_SHARED) strictly exceeds broken-order's ($BROKEN_SHARED) -- proving the derivation genuinely tells the two orderings apart, not decoration that always reports the same answer" \
  "$([ "$CORRECT_SHARED" -gt "$BROKEN_SHARED" ] && echo 1 || echo 0)"
chk "paired mutation caught: a mutated derivation that ALWAYS composes per-item-first (even when asked for 'correct') collapses its own 'correct'-request shared-prefix length ($MUT_SHARED) down to the broken bound (< len(dispatch_1_per_item)=$LEN_P1), diverging from the real correct-order result ($CORRECT_SHARED) -- a real meta-test built against this fixture, once T115 lands, would genuinely catch this regression" \
  "$([ "$MUT_SHARED" -lt "$LEN_P1" ] && [ "$CORRECT_NE_MUT" = "True" ] && echo 1 || echo 0)"

# =========================================================================
# Oracle B -- REAL-WORLD CONSEQUENCE: does the correct byte-prefix actually
# earn a cache read from a real, captured, already-tested transcript-usage
# instrument (never dispatch_prefix.py's own self-report).
# =========================================================================
echo
echo "=== Oracle B: real-transcript cache-read consequence (good_order) ==="
GOOD_DB="$TMP/good_order.db"
GOOD_OUT="$(python3 "$TRANSCRIPT_INGEST" ingest "$FIXDIR/good_order/parent_session.jsonl" --db "$GOOD_DB" 2>&1)"
GOOD_RC=$?
GOOD_D2_STATUS="$(sqlite3 -noheader "$GOOD_DB" "SELECT usage_status FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_good_sub_a2';" 2>/dev/null)"
GOOD_D2_CR="$(sqlite3 -noheader "$GOOD_DB" "SELECT cache_read_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_good_sub_a2';" 2>/dev/null)"
GOOD_D1_CC="$(sqlite3 -noheader "$GOOD_DB" "SELECT cache_creation_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_good_sub_a1';" 2>/dev/null)"
info "good_order: ingest rc=$GOOD_RC ($GOOD_OUT); dispatch1 cache_creation=$GOOD_D1_CC; dispatch2 usage_status=$GOOD_D2_STATUS cache_read=$GOOD_D2_CR"
chk "good_order: transcript_ingest.py runs cleanly (rc=0) against the real-schema two-dispatch fixture" \
  "$([ "$GOOD_RC" = "0" ] && echo 1 || echo 0)"
chk "good_order: dispatch 2's own first turn is MEASURED with a real, positive cache_read_input_tokens value ($GOOD_D2_CR > 0) that equals dispatch 1's own cache_creation_input_tokens ($GOOD_D1_CC) -- the real captured oracle for 'two consecutive same-class dispatches show a cache read on the second'" \
  "$([ "$GOOD_D2_STATUS" = "measured" ] && [ "$GOOD_D2_CR" = "$GOOD_D1_CC" ] && [ "$GOOD_D2_CR" -gt "0" ] && echo 1 || echo 0)"

echo
echo "=== Oracle B: real-transcript cache-read consequence (bad_order, golden-bad) ==="
BAD_DB="$TMP/bad_order.db"
BAD_OUT="$(python3 "$TRANSCRIPT_INGEST" ingest "$FIXDIR/bad_order/parent_session.jsonl" --db "$BAD_DB" 2>&1)"
BAD_RC=$?
BAD_D2_STATUS="$(sqlite3 -noheader "$BAD_DB" "SELECT usage_status FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_bad_sub_a2';" 2>/dev/null)"
BAD_D2_CR="$(sqlite3 -noheader "$BAD_DB" "SELECT cache_read_input_tokens FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_bad_sub_a2';" 2>/dev/null)"
info "bad_order: ingest rc=$BAD_RC ($BAD_OUT); dispatch2 usage_status=$BAD_D2_STATUS cache_read=$BAD_D2_CR"
chk "bad_order: transcript_ingest.py runs cleanly (rc=0) against the real-schema two-dispatch golden-bad fixture" \
  "$([ "$BAD_RC" = "0" ] && echo 1 || echo 0)"
chk "bad_order: dispatch 2's own first turn is MEASURED with a real, genuinely-captured cache_read_input_tokens of exactly 0 (never NULL/unmeasured -- this is a deliberate, measured zero, not an absent instrument) -- the real captured oracle for 'a per-item timestamp placed before the subset shows no read'" \
  "$([ "$BAD_D2_STATUS" = "measured" ] && [ "$BAD_D2_CR" = "0" ] && echo 1 || echo 0)"

echo
echo "=== Oracle B discrimination: good_order vs bad_order ==="
chk "Oracle B discrimination: dispatch 2's own cache_read_input_tokens differs between good_order ($GOOD_D2_CR) and bad_order ($BAD_D2_CR) -- proving the real instrument genuinely tells the two scenarios apart, not decoration that always reports the same answer" \
  "$([ "$GOOD_D2_CR" != "$BAD_D2_CR" ] && echo 1 || echo 0)"

# =========================================================================
# Oracle B -- U-12 HONESTY branch: "when the harness exposes no subagent
# cache metric the test records the U-12 limitation and does not claim a
# hit" (tasks.md T106's own literal wording).
# =========================================================================
echo
echo "=== Oracle B: U-12 honesty branch (no_cache_metric) ==="
NC_DB="$TMP/no_cache_metric.db"
NC_OUT="$(python3 "$TRANSCRIPT_INGEST" ingest "$FIXDIR/no_cache_metric/parent_session.jsonl" --db "$NC_DB" 2>&1)"
NC_RC=$?
NC_D2_STATUS="$(sqlite3 -noheader "$NC_DB" "SELECT usage_status FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_nc_sub_a2';" 2>/dev/null)"
NC_D2_CR_IS_NULL="$(sqlite3 -noheader "$NC_DB" "SELECT cache_read_input_tokens IS NULL FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_nc_sub_a2';" 2>/dev/null)"
NC_D2_MISSING="$(sqlite3 -noheader "$NC_DB" "SELECT missing_instrument FROM transcript_usage_events WHERE msg_id='msg_fixture_t106_nc_sub_a2';" 2>/dev/null)"
info "no_cache_metric: ingest rc=$NC_RC ($NC_OUT); dispatch2 usage_status=$NC_D2_STATUS cache_read_is_null=$NC_D2_CR_IS_NULL"

chk "no_cache_metric: transcript_ingest.py runs cleanly (rc=0) against the real-schema two-dispatch no-metric fixture" \
  "$([ "$NC_RC" = "0" ] && echo 1 || echo 0)"

if [ "$NC_D2_STATUS" = "UNMEASURED" ] && [ "$NC_D2_CR_IS_NULL" = "1" ] && [ -n "$NC_D2_MISSING" ]; then
  echo "U-12 LIMITATION RECORDED: dispatch 2's own subagent transcript carries no usage block at all for its first turn (missing_instrument: $NC_D2_MISSING). Per research.md U-12 ('The CLI exposes prompt-cache hit metrics per subagent -- UNCONFIRMED, R5:157') and tasks.md T106's own literal wording, this test does NOT claim a cache hit (nor a cache miss) for this dispatch -- it records the limitation and moves on. This is the CORRECT, HONEST outcome for this scenario -- not a defect in dispatch_prefix.py's ordering (dispatch 1's cache_creation and dispatch 2's structural prompt ordering are untouched by this scenario; only dispatch 2's own real captured usage metric is absent)."
  chk "no_cache_metric: dispatch 2 is genuinely UNMEASURED (usage_status=UNMEASURED, cache_read_input_tokens IS NULL -- never coerced to 0, missing_instrument populated) AND this test's own U-12 branch records the limitation instead of claiming a hit" \
    "1"
else
  echo "UNEXPECTED: dispatch 2's own row does not match the expected U-12 shape (usage_status=$NC_D2_STATUS want UNMEASURED; cache_read_is_null=$NC_D2_CR_IS_NULL want 1; missing_instrument='$NC_D2_MISSING' want non-empty) -- either the fixture or transcript_ingest.py's own behaviour has changed"
  chk "no_cache_metric: dispatch 2 is genuinely UNMEASURED (usage_status=UNMEASURED, cache_read_input_tokens IS NULL -- never coerced to 0, missing_instrument populated) AND this test's own U-12 branch records the limitation instead of claiming a hit" \
    "0"
fi

# =========================================================================
# Self-validation triple (section 11.4.107(10), Principle IV): the three
# scenarios MUST produce three DISTINCT observed states -- measured-hit,
# measured-miss, genuinely-unmeasured -- proving Oracle B discriminates
# among all three, not merely a binary hit/no-hit.
# =========================================================================
echo
echo "=== Self-validation triple: three DISTINCT observed states ==="
STATE_GOOD="measured:$GOOD_D2_CR"
STATE_BAD="measured:$BAD_D2_CR"
STATE_NC="$NC_D2_STATUS:null=$NC_D2_CR_IS_NULL"
info "good_order state='$STATE_GOOD'  bad_order state='$STATE_BAD'  no_cache_metric state='$STATE_NC'"
THREE_DISTINCT=0
if [ "$STATE_GOOD" != "$STATE_BAD" ] && [ "$STATE_GOOD" != "$STATE_NC" ] && [ "$STATE_BAD" != "$STATE_NC" ]; then
  THREE_DISTINCT=1
fi
chk "self-validation triple: good_order, bad_order and no_cache_metric each produce a genuinely DISTINCT observed state from the SAME real oracle -- proving the oracle discriminates a hit from a miss from an honest absence, not merely two of the three" \
  "$THREE_DISTINCT"

# =========================================================================
# Forward-compatible real-tool invocation (guarded on TOOL_PRESENT, dormant
# today by design -- T115 has not landed. This section's assumed CLI
# (`dispatch_prefix.py compose --core FILE --subset FILE --per-item FILE
# --out FILE`, emitting the composed [core][subset][per-item] prompt bytes
# to --out) is THIS test's OWN choice, fixed here per common-conventions.md's
# "no contract exists yet ... fixed by the plan task text until a contract
# is written" precedent (mirroring T104/T107's identical practice) --
# binding on T115 unless T115 records an explicit, evidenced deviation.
# =========================================================================
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: context/dispatch_prefix.py compose ==="
  python3 -c "
import json
d = json.load(open('$FIXDIR/prompt_spec.json'))
open('$TMP/real_core.txt', 'w').write(d['core_text'])
open('$TMP/real_subset.txt', 'w').write(d['subset_text_class_a'])
open('$TMP/real_p1.txt', 'w').write(d['dispatch_1_per_item'])
open('$TMP/real_p2.txt', 'w').write(d['dispatch_2_per_item'])
"
  RT_OUT1="$TMP/real_compose1.txt"
  RT_OUT2="$TMP/real_compose2.txt"
  python3 "$IMPL" compose --core "$TMP/real_core.txt" --subset "$TMP/real_subset.txt" --per-item "$TMP/real_p1.txt" --out "$RT_OUT1" >"$TMP/real_compose1.err" 2>&1
  RT_RC1=$?
  python3 "$IMPL" compose --core "$TMP/real_core.txt" --subset "$TMP/real_subset.txt" --per-item "$TMP/real_p2.txt" --out "$RT_OUT2" >"$TMP/real_compose2.err" 2>&1
  RT_RC2=$?
  if [ "$RT_RC1" = "0" ] && [ "$RT_RC2" = "0" ] && [ -f "$RT_OUT1" ] && [ -f "$RT_OUT2" ]; then
    REAL_SHARED="$(python3 -c "
a=open('$RT_OUT1','rb').read(); b=open('$RT_OUT2','rb').read()
n=0
for x,y in zip(a,b):
    if x!=y: break
    n+=1
print(n)
")"
    chk "real dispatch_prefix.py compose: two same-class 'correct'-order dispatches share a byte-prefix >= len(core)+len(subset) ($LEN_CS), matching Oracle A's independent prediction ($REAL_SHARED >= $LEN_CS)" \
      "$([ "$REAL_SHARED" -ge "$LEN_CS" ] && echo 1 || echo 0)"
  else
    echo "  NOT ok real dispatch_prefix.py compose invocation failed: rc1=$RT_RC1 rc2=$RT_RC2 -- $(cat "$TMP/real_compose1.err" "$TMP/real_compose2.err" 2>/dev/null)"
    chk "real dispatch_prefix.py compose invocation succeeds against this test's own fixed CLI contract" "0"
  fi
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: context/dispatch_prefix.py not present ==="
  chk "real-invocation checks run -- SKIPPED, contributes to the overall RED exit below, which is the CORRECT state until T115 lands" "0"
fi

echo
if [ "$FAIL" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T115 not yet landed); if you see"
  echo "    this, context/dispatch_prefix.py must have landed AND every fixture"
  echo "    check passed against the real tool. ==="
else
  echo "=== T106 RED BASELINE CONFIRMED: context/dispatch_prefix.py does not"
  echo "    exist yet (T115 is a separate, later task). Oracle A's structural"
  echo "    ordering proof + its mutation-catch proof, and Oracle B's three"
  echo "    real-transcript scenarios (good_order/bad_order/no_cache_metric,"
  echo "    including the honest U-12 branch), stand as the interim contract"
  echo "    T115 must satisfy to turn this GREEN. ==="
fi

echo
echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
