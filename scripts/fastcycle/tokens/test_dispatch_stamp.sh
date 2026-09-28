#!/usr/bin/env bash
# test_dispatch_stamp.sh — hermetic, automated regression test for T036
# (SpecKit-004 "fast-dev-cycles", User Story 1) dispatch_stamp.sh
# (constitution/scripts/fastcycle/tokens/dispatch_stamp.sh).
#
# FIX 2/3 (independent Opus-xhigh review of the T036 implementation, this
# batch): the review found dispatch_stamp.sh completely correct in its own
# functional logic (every fixture, every adversarial edge case reviewed by
# hand, shellcheck, bash -n — all clean) but BLOCKING because no automated,
# fixture-driven regression test invoked it — unlike its two NAMED siblings
# on the same Agent|Task|TaskCreate PreToolUse matcher, both of which ship a
# dedicated test_guard_*.sh file living alongside the tool it tests:
#   constitution/scripts/hooks/guard-track-branch-label.sh
#     + constitution/scripts/hooks/test_guard_track_branch_label.sh
#   constitution/scripts/hooks/guard-work-track-binding.sh
#     + constitution/scripts/hooks/test_guard_work_track_binding.sh
# The three static fixtures under tests/fixtures/dispatch_stamp/ existed
# only as README-documented "run this by hand" data with no automated
# runner. This file is that missing runner, placed alongside the tool it
# tests (dispatch_stamp.sh, this same directory) to match the two named
# siblings' own placement convention exactly.
#
# `tests/lib/triple_harness.sh` (the generic fixture-runner some OTHER
# fastcycle tools in this batch use) was investigated and ruled out as a
# drop-in fit here: it invokes its tool via `"$tool" "$1"` (a fixture PATH
# as a CLI arg) and hardcodes golden-bad expecting exit 1 (triple_harness.sh
# lines 41-42, 151-167) — architecturally built for CLI-arg-invoked tools,
# not this tool's stdin-JSON / exit-0-allow / exit-2-block PreToolUse
# contract. The two named-sibling hooks' own dedicated test_guard_*.sh
# files are the correct, already-established precedent this file follows.
#
# CONTRACT UNDER TEST (both of dispatch_stamp.sh's two modes, read in full
# from its own header before writing this file):
#   MODE 1 (default, GUARD): stdin JSON in the Claude Code PreToolUse
#     invocation shape; exit 0 = allow, exit 2 = BLOCK (stderr explains the
#     fix); tool_name in {Agent, Task, TaskCreate} MUST carry an
#     `item=(ATM-[0-9]+|\?)` token at a token boundary SOMEWHERE in
#     .tool_input.description (falling back to .tool_input.subagent); every
#     OTHER tool_name passes through untouched (exit 0).
#   MODE 2 (--extract-item-id, EXTRACTION): reads the SAME stdin JSON;
#     tool_name-agnostic; prints the extracted `ATM-nnnn` / literal `?` /
#     nothing (absent) to stdout with NO other output; ALWAYS exits 0,
#     under every input including malformed/truncated/empty stdin.
#
# Anti-bluff (§11.4.107(10)/§11.4.273 analogue): this suite proves the tool
#   - ALLOWS (GUARD exit 0) a well-formed item=ATM-nnnn token, the honest
#     item=? form, a token reached only via the .tool_input.subagent
#     fallback, and every non-Agent/Task/TaskCreate tool_name regardless of
#     item= presence;
#   - BLOCKS (GUARD exit 2) a genuinely missing item= token, a FUSED
#     "prefixitem=ATM-99" (not a standalone token — proves the regex is
#     genuinely token-boundary-aware, not a naive substring match a
#     future "simplification" could silently regress to), and
#     "item=ATM-" with no digits following;
#   - EXTRACTS the correct value (ATM-nnnn / `?` / empty) in lockstep with
#     each GUARD verdict above, from BOTH the real jq path AND the pure-AWK
#     fallback path (forced via a minimal PATH containing no jq binary —
#     the tool's own json_field() falls back to an AWK extractor when
#     `command -v jq` fails; both code paths are permanent regression
#     guards here, not just the jq-present happy path);
#   - in EXTRACTION mode NEVER crashes and ALWAYS exits 0 on malformed /
#     truncated / empty / `null` / bare-number / bare-string stdin (the
#     tool's own documented robustness guarantee, load-bearing since a
#     future T037 may embed this mode inside another tool's own
#     always-exit-0 contract) —
# so the enforcement (and the extraction helper) provably cannot bluff.
#
# HERMETICITY / DETERMINISM (§11.4.50): no ambient ENV state (CLAUDE_*,
# CLAUDE_CONFIG_DIR, etc.) affects this tool at all — dispatch_stamp.sh
# reads only stdin — so every case here is fully self-contained and
# re-runnable regardless of which alias/track/session runs it.
#
# Reuse: the three base cases (golden-good / golden-bad / negative-control)
# read their JSON payload AND expected GUARD-exit / EXTRACT-stdout directly
# from the existing static fixtures under
# ../tests/fixtures/dispatch_stamp/{golden-good,golden-bad,negative-control}/
# — a single source of truth, never re-typed — per the README.md already
# documenting that fixture set. Every additional adversarial case below (not
# covered by those three fixtures) uses an inline payload, matching the two
# named siblings' own established inline-payload convention.
#
# Producer != Verifier (constitution §11.4.240): this file is a fix-pass
# deliverable, itself subject to a SEPARATE, later, independent §11.4.209
# Opus-xhigh review before being trusted — its author never self-certifies.
#
# Usage: bash constitution/scripts/fastcycle/tokens/test_dispatch_stamp.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/dispatch_stamp.sh"
FIXDIR="$HERE/../tests/fixtures/dispatch_stamp"
BASH_ABS="$(command -v bash)"

PASS=0
FAIL=0

# run_guard <name> <expected-exit> <json-payload>
#   Runs dispatch_stamp.sh in default GUARD mode; compares its exit code.
run_guard() {
  local name="$1" want="$2" payload="$3" got
  printf '%s' "$payload" | bash "$TOOL" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-64s (exit %s)\n' "$name" "$got"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-64s (got exit %s, want %s)\n' "$name" "$got" "$want"
    FAIL=$((FAIL + 1))
  fi
}

# run_extract <name> <expected-stdout> <json-payload>
#   Runs dispatch_stamp.sh --extract-item-id; compares BOTH stdout content
#   AND exit code (which MUST always be 0, per the tool's own contract).
run_extract() {
  local name="$1" want="$2" payload="$3" got rc
  got="$(printf '%s' "$payload" | bash "$TOOL" --extract-item-id)"
  rc=$?
  if [ "$got" = "$want" ] && [ "$rc" -eq 0 ]; then
    printf '  PASS  %-64s (stdout="%s" exit=%s)\n' "$name" "$got" "$rc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-64s (got stdout="%s" exit=%s, want stdout="%s" exit=0)\n' "$name" "$got" "$rc" "$want"
    FAIL=$((FAIL + 1))
  fi
}

# run_guard_nojq / run_extract_nojq <name> <expected> <json-payload>
#   Identical to run_guard / run_extract, but invoked with PATH restricted
#   to a minimal directory holding ONLY awk + cat (no jq) — forces
#   dispatch_stamp.sh's json_field() into its pure-AWK fallback branch
#   (`command -v jq` fails under this PATH). bash itself is invoked by its
#   OWN absolute path ($BASH_ABS), never looked up on the restricted PATH,
#   so only the TOOL's internal `command -v jq` check is affected.
run_guard_nojq() {
  local name="$1" want="$2" payload="$3" got
  printf '%s' "$payload" | PATH="$NOJQ_BIN" "$BASH_ABS" "$TOOL" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-64s (exit %s)\n' "$name" "$got"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-64s (got exit %s, want %s)\n' "$name" "$got" "$want"
    FAIL=$((FAIL + 1))
  fi
}
run_extract_nojq() {
  local name="$1" want="$2" payload="$3" got rc
  got="$(printf '%s' "$payload" | PATH="$NOJQ_BIN" "$BASH_ABS" "$TOOL" --extract-item-id)"
  rc=$?
  if [ "$got" = "$want" ] && [ "$rc" -eq 0 ]; then
    printf '  PASS  %-64s (stdout="%s" exit=%s)\n' "$name" "$got" "$rc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-64s (got stdout="%s" exit=%s, want stdout="%s" exit=0)\n' "$name" "$got" "$rc" "$want"
    FAIL=$((FAIL + 1))
  fi
}

echo "T036 dispatch_stamp.sh hermetic test suite"
echo "tool:     $TOOL"
echo "fixtures: $FIXDIR"
echo

# ===========================================================================
# 0. Minimal jq-absent PATH — real AWK fallback, forced.
# ===========================================================================
NOJQ_BIN=""
NOJQ_AVAILABLE=1
if command -v awk >/dev/null 2>&1 && command -v cat >/dev/null 2>&1; then
  NOJQ_BIN="$(mktemp -d)"
  ln -s "$(command -v awk)" "$NOJQ_BIN/awk"
  ln -s "$(command -v cat)" "$NOJQ_BIN/cat"
  trap 'rm -rf "$NOJQ_BIN"' EXIT
  # Control needle: confirm jq is genuinely unresolvable under this PATH
  # (never assume the restriction worked — §11.4.273).
  if PATH="$NOJQ_BIN" command -v jq >/dev/null 2>&1; then
    echo "  FAIL  no-jq PATH control needle: jq still resolvable under \$NOJQ_BIN (test setup broken)"
    FAIL=$((FAIL + 1))
    NOJQ_AVAILABLE=0
  else
    printf '  PASS  %-64s\n' "no-jq PATH control needle: jq genuinely unresolvable"
    PASS=$((PASS + 1))
  fi
else
  echo "SKIP: awk or cat unavailable — the jq-absent-fallback cases cannot run hermetically."
  NOJQ_AVAILABLE=0
fi

# ===========================================================================
# A. Fixture-driven base cases (golden-good / golden-bad / negative-control)
#    — payload AND expected GUARD-exit / EXTRACT-stdout read directly from
#    the existing static fixtures, never re-typed.
# ===========================================================================
echo
echo "-- A. fixture-driven base cases --"
for CASE in golden-good golden-bad negative-control; do
  CDIR="$FIXDIR/$CASE"
  if [ ! -f "$CDIR/input" ] || [ ! -f "$CDIR/expected" ] || [ ! -f "$CDIR/expected_extract" ]; then
    echo "  FAIL  fixture $CASE: missing input/expected/expected_extract under $CDIR"
    FAIL=$((FAIL + 1))
    continue
  fi
  PAYLOAD="$(cat "$CDIR/input")"
  WANT_EXIT="$(cat "$CDIR/expected")"
  WANT_EXTRACT="$(cat "$CDIR/expected_extract")"
  run_guard "fixture $CASE GUARD" "$WANT_EXIT" "$PAYLOAD"
  run_extract "fixture $CASE EXTRACT" "$WANT_EXTRACT" "$PAYLOAD"
done

# ===========================================================================
# B. item=? honest-unknown form — accepted unconditionally (no live-
#    derivable "correct" id exists to cross-check it against; see
#    dispatch_stamp.sh's own header).
# ===========================================================================
echo
echo "-- B. honest '?' item form --"
run_guard "item=? honest-unknown GUARD" 0 \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x - opus - high) item=? ATM unknown","prompt":"x"}}'
run_extract "item=? honest-unknown EXTRACT prints '?'" '?' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x - opus - high) item=? ATM unknown","prompt":"x"}}'

# ===========================================================================
# C. Token-boundary adversarial cases — prove the regex is genuinely
#    token/word-boundary-aware, NOT a naive substring match.
# ===========================================================================
echo
echo "-- C. token-boundary adversarial cases --"
# A FUSED "prefixitem=ATM-99" is NOT a standalone `item=` token (no
# whitespace/start-of-string immediately before "item="): the well-formed
# ATM-99 id inside it must NOT satisfy the requirement.
run_guard "fused 'prefixitem=ATM-99' BLOCKED (not a token)" 2 \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x - opus - high) prefixitem=ATM-99 nope","prompt":"x"}}'
run_extract "fused 'prefixitem=ATM-99' EXTRACT empty (not a token)" '' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x - opus - high) prefixitem=ATM-99 nope","prompt":"x"}}'
# "item=ATM-" with no digits following the dash does not satisfy
# ATM-[0-9]+ nor the literal '?' alternative.
run_guard "'item=ATM-' no digits BLOCKED" 2 \
  '{"tool_name":"Task","tool_input":{"description":"(T1/main - x) item=ATM- nope"}}'
run_extract "'item=ATM-' no digits EXTRACT empty" '' \
  '{"tool_name":"Task","tool_input":{"description":"(T1/main - x) item=ATM- nope"}}'

# ===========================================================================
# D. .tool_input.subagent fallback — used when .tool_input.description is
#    absent/empty, identical fallback order to guard-track-branch-label.sh.
# ===========================================================================
echo
echo "-- D. subagent-field fallback --"
run_guard "subagent-field item=ATM-2000 GUARD allowed" 0 \
  '{"tool_name":"Agent","tool_input":{"subagent":"(T1/main - x - opus - high) item=ATM-2000 subagent field test"}}'
run_extract "subagent-field item=ATM-2000 EXTRACT" 'ATM-2000' \
  '{"tool_name":"Agent","tool_input":{"subagent":"(T1/main - x - opus - high) item=ATM-2000 subagent field test"}}'

# ===========================================================================
# E. Additional tool_name coverage (Task / TaskCreate gated; non-agent tools
#    pass through untouched regardless of item= presence).
# ===========================================================================
echo
echo "-- E. additional tool_name coverage --"
run_guard "TaskCreate item=ATM-3000 GUARD allowed" 0 \
  '{"tool_name":"TaskCreate","tool_input":{"description":"(T2/feature/x - x) item=ATM-3000 create"}}'
run_guard "TaskCreate missing item= BLOCKED" 2 \
  '{"tool_name":"TaskCreate","tool_input":{"description":"(T2/feature/x - x) create, no item token"}}'
run_guard "non-agent Read tool always allowed (no item= anywhere)" 0 \
  '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'
run_guard "non-agent Edit tool always allowed (no item= anywhere)" 0 \
  '{"tool_name":"Edit","tool_input":{"file_path":"x","old_string":"a","new_string":"b"}}'

# ===========================================================================
# F. EXTRACTION mode always-exit-0 robustness — malformed / truncated /
#    empty / null / bare-number / bare-string stdin must NEVER crash and
#    must ALWAYS exit 0 (load-bearing: T037 may embed this mode inside
#    another tool's own always-exit-0 PreToolUse contract).
# ===========================================================================
echo
echo "-- F. EXTRACTION-mode always-exit-0 robustness --"
run_extract "malformed truncated JSON -> empty, exit 0" '' \
  '{"tool_name":"Agent","tool_input":{'
run_extract "empty stdin -> empty, exit 0" '' \
  ''
run_extract "bare 'null' -> empty, exit 0" '' \
  'null'
run_extract "bare number '42' -> empty, exit 0" '' \
  '42'
run_extract "bare string '\"hello\"' -> empty, exit 0" '' \
  '"hello"'

# ===========================================================================
# G. jq-absent fallback (pure AWK json_field() branch) — same case matrix
#    as sections A/D re-run with jq forced unresolvable, proving the
#    fallback extractor is behaviourally identical to the jq path.
# ===========================================================================
echo
echo "-- G. jq-absent AWK-fallback path --"
if [ "$NOJQ_AVAILABLE" -eq 1 ]; then
  GG_PAYLOAD="$(cat "$FIXDIR/golden-good/input")"
  GB_PAYLOAD="$(cat "$FIXDIR/golden-bad/input")"
  NC_PAYLOAD="$(cat "$FIXDIR/negative-control/input")"
  run_guard_nojq "AWK-fallback golden-good GUARD" "$(cat "$FIXDIR/golden-good/expected")" "$GG_PAYLOAD"
  run_extract_nojq "AWK-fallback golden-good EXTRACT" "$(cat "$FIXDIR/golden-good/expected_extract")" "$GG_PAYLOAD"
  run_guard_nojq "AWK-fallback golden-bad GUARD" "$(cat "$FIXDIR/golden-bad/expected")" "$GB_PAYLOAD"
  run_guard_nojq "AWK-fallback negative-control GUARD" "$(cat "$FIXDIR/negative-control/expected")" "$NC_PAYLOAD"
  run_guard_nojq "AWK-fallback subagent-field item=ATM-2000 GUARD" 0 \
    '{"tool_name":"Agent","tool_input":{"subagent":"(T1/main - x - opus - high) item=ATM-2000 subagent field test"}}'
  run_extract_nojq "AWK-fallback subagent-field item=ATM-2000 EXTRACT" 'ATM-2000' \
    '{"tool_name":"Agent","tool_input":{"subagent":"(T1/main - x - opus - high) item=ATM-2000 subagent field test"}}'
else
  echo "SKIP: jq-absent-fallback cases skipped (see section 0 above)."
fi

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
