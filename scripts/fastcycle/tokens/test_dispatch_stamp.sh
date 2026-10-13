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
# HERMETICITY / DETERMINISM (§11.4.50): no session-scoped ENV state
# (CLAUDE_*, CLAUDE_CONFIG_DIR, etc.) affects this tool. It DOES read three
# configuration vars (FC_DISPATCH_ITEM_ID_RE, FC_DISPATCH_EXTRA_ITEM_PREFIXES
# and, through release_prefix.sh, HELIX_RELEASE_PREFIX). T048 restart
# round-1 (R4-I2 class: a constitution test must not depend on the checkout
# it happens to run in): this suite now unsets the two FC_* vars and pins
# HELIX_RELEASE_PREFIX to a fixture value whose derived ticket prefix is
# "ATM", the prefix the static fixtures under tests/fixtures/dispatch_stamp/
# use. Before this, the suite passed only on a checkout whose own .env
# happened to derive "ATM", and false-FAILed on any other consumer. The
# pinned value is a test fixture, not a claim about any real project.
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

unset FC_DISPATCH_ITEM_ID_RE FC_DISPATCH_EXTRA_ITEM_PREFIXES HELIX_PROJECT_ROOT 2>/dev/null || true
export HELIX_RELEASE_PREFIX=atm_fixture_prefix

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
#   The tool's contract is "stdout is the id, NO other output", so stderr
#   must be empty too (T048 restart round-1, R3 minor note).
run_extract() {
  local name="$1" want="$2" payload="$3" got rc err
  err="$(mktemp)"
  got="$(printf '%s' "$payload" | bash "$TOOL" --extract-item-id 2>"$err")"
  rc=$?
  if [ "$got" = "$want" ] && [ "$rc" -eq 0 ] && [ ! -s "$err" ]; then
    printf '  PASS  %-64s (stdout="%s" exit=%s)\n' "$name" "$got" "$rc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-64s (got stdout="%s" exit=%s stderr="%s", want stdout="%s" exit=0 stderr empty)\n' "$name" "$got" "$rc" "$(head -c 200 "$err")" "$want"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$err"
}

# run_guard_nojq / run_extract_nojq <name> <expected> <json-payload>
#   Identical to run_guard / run_extract, but invoked with PATH restricted
#   to a minimal directory holding ONLY awk + cat (no jq) — forces
#   dispatch_stamp.sh's json_field() into its pure-AWK fallback branch
#   (`command -v jq` fails under this PATH). bash itself is invoked by its
#   OWN absolute path ($BASH_ABS), never looked up on the restricted PATH,
#   so only the TOOL's internal `command -v jq` check is affected.
#
# T048 round-3 review finding R3-M1 companion fix (2026-09-30): the claim
# immediately above ("only the TOOL's internal `command -v jq` check is
# affected") is INCOMPLETE, discovered live while fixing R3-M1 in
# dispatch_stamp.sh itself. `_fc_default_item_prefix()` ALSO shells out to
# a BARE `bash "$rp_script"` (release_prefix.sh) to derive the default
# ticket-id prefix, and release_prefix.sh in turn needs `git`/`grep`/`sed`
# — every one of which is ALSO unresolvable under `PATH="$NOJQ_BIN"`, so
# this section's PATH restriction was ALWAYS breaking prefix resolution
# too, silently masked before R3-M1 because the OLD hardcoded "ATM"
# fallback happened to coincide with this checkout's real derived prefix.
# R3-M1 replaced that literal "ATM" guess with the honest neutral "WIT"
# fallback (§11.4.28/§11.4.177 decoupling), which genuinely changes what
# this section's tool invocation resolves as its default prefix. A first
# attempt at this companion fix tried `FC_DISPATCH_EXTRA_ITEM_PREFIXES=ATM`
# (the tool's OTHER override mechanism) but that path ALSO needs `tr` to
# parse the comma/pipe-separated list (dispatch_stamp.sh's own extra-
# prefix loop), which is likewise unresolvable under this minimal PATH —
# reproduced live (`tr: command not found`) before switching approach.
# `FC_DISPATCH_ITEM_ID_RE` (a full regex override) is used instead: it
# is read BEFORE `_fc_default_item_prefix()` is ever called (see
# dispatch_stamp.sh's own `if [ -n "${FC_DISPATCH_ITEM_ID_RE:-}" ]`
# branch), so it bypasses the whole prefix/tr/bash/git/grep/sed
# dependency chain entirely — keeping this section testing exactly what
# it always meant to test (the jq-absent AWK JSON-extraction path,
# against the SAME shared "ATM-nnnn"-shaped fixtures section A already
# uses) independently of, rather than accidentally coupled to, the
# separate prefix-fallback mechanism R3-M1 fixed.
run_guard_nojq() {
  local name="$1" want="$2" payload="$3" got
  printf '%s' "$payload" | PATH="$NOJQ_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" >/dev/null 2>&1
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
  got="$(printf '%s' "$payload" | PATH="$NOJQ_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" --extract-item-id)"
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

# ===========================================================================
# H. Prefix configuration and tag right boundary (T048 restart round-1,
#    R3-F3: the FC_DISPATCH_EXTRA_ITEM_PREFIXES path had no behavioural
#    coverage; R3 boundary note: 'item=ATM-12x' used to count as ATM-12).
# ===========================================================================
echo
echo "-- H. extra prefixes, full override, right boundary --"
SPK_PAYLOAD='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=SPK-609 extra-prefix id"}}'
run_guard "unconfigured: item=SPK-609 BLOCKED (default stays the derived prefix)" 2 "$SPK_PAYLOAD"
run_extract "unconfigured: item=SPK-609 EXTRACT empty" '' "$SPK_PAYLOAD"
# The extra prefixes are passed per case through env(1); the helpers above
# inherit the environment, so each case exports and then unsets it.
export FC_DISPATCH_EXTRA_ITEM_PREFIXES=spk
run_guard "FC_DISPATCH_EXTRA_ITEM_PREFIXES=spk (lowercase): item=SPK-609 allowed" 0 "$SPK_PAYLOAD"
run_extract "FC_DISPATCH_EXTRA_ITEM_PREFIXES=spk: EXTRACT SPK-609" 'SPK-609' "$SPK_PAYLOAD"
run_extract "FC_DISPATCH_EXTRA_ITEM_PREFIXES=spk: the derived ATM prefix still works" 'ATM-2000' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-2000 still default"}}'
export FC_DISPATCH_EXTRA_ITEM_PREFIXES='foo|bar, spk'
run_extract "FC_DISPATCH_EXTRA_ITEM_PREFIXES='foo|bar, spk' (mixed separators): EXTRACT SPK-609" 'SPK-609' "$SPK_PAYLOAD"
run_extract "FC_DISPATCH_EXTRA_ITEM_PREFIXES='foo|bar, spk': EXTRACT BAR-7" 'BAR-7' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=BAR-7 second token"}}'
unset FC_DISPATCH_EXTRA_ITEM_PREFIXES
export FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+'
FC_DISPATCH_EXTRA_ITEM_PREFIXES=spk run_extract "FC_DISPATCH_ITEM_ID_RE wins over extra prefixes (SPK-609 not extracted)" '' "$SPK_PAYLOAD"
run_extract "FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+': EXTRACT XYZ-5" 'XYZ-5' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=XYZ-5 override"}}'
unset FC_DISPATCH_ITEM_ID_RE
run_guard "right boundary: 'item=ATM-12x' BLOCKED (not a whole token)" 2 \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12x trailing"}}'
run_extract "right boundary: 'item=ATM-12x' EXTRACT empty" '' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12x trailing"}}'
run_guard "right boundary: 'item=?foo' BLOCKED (not the honest '?' token)" 2 \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=?foo"}}'
run_extract "right boundary: 'item=ATM-12,' EXTRACT ATM-12 (punctuation ends a token)" 'ATM-12' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12, next"}}'
run_extract "right boundary: 'item=ATM-12' at end of string EXTRACT ATM-12" 'ATM-12' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12"}}'

# ===========================================================================
# I. T048 restart round 2 (V1-I3 N8, V1-M3, V1-M4(a)): '_' ends no tag;
#    the refusal names the RESOLVED prefix; the jq-less reader takes the
#    value at the exact path and fails closed on a payload it cannot parse.
# ===========================================================================
echo
echo "-- I. underscore boundary, refusal text, exact-path parsing, fail-closed --"
run_guard "right boundary: 'item=ATM-12_x' BLOCKED ('_' continues the token)" 2 \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12_x trailing"}}'
run_extract "right boundary: 'item=ATM-12_x' EXTRACT empty" '' \
  '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12_x trailing"}}'

# check <name> <condition-exit-status>
check() {
  if [ "$2" -eq 0 ]; then printf '  PASS  %-64s\n' "$1"; PASS=$((PASS + 1));
  else printf '  FAIL  %-64s %s\n' "$1" "${3:-}"; FAIL=$((FAIL + 1)); fi
}
UNTAGGED='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 no zeta tag"}}'
ERR_Z="$(printf '%s' "$UNTAGGED" | HELIX_RELEASE_PREFIX=zeta bash "$TOOL" 2>&1 >/dev/null)"; RC_Z=$?
check "V1-M3: zeta consumer blocks item=ATM-12 (exit 2)" "$([ "$RC_Z" = 2 ] && echo 0 || echo 1)" "rc=$RC_Z"
check "V1-M3: refusal names the resolved form item=<ZET-nnnn>" "$(printf '%s' "$ERR_Z" | grep -Fq 'item=<ZET-nnnn>'; echo $?)" "stderr: $ERR_Z"
check "V1-M3: refusal example uses the resolved prefix (item=ZET-1041)" "$(printf '%s' "$ERR_Z" | grep -Fq 'item=ZET-1041'; echo $?)" "stderr: $ERR_Z"
check "V1-M3: refusal text carries no ATM-nnnn / ATM-1041 literal" "$(printf '%s' "$ERR_Z" | grep -Eq 'ATM-(nnnn|1041)' && echo 1 || echo 0)" "stderr: $ERR_Z"
ERR_X="$(printf '%s' "$UNTAGGED" | HELIX_RELEASE_PREFIX=zeta FC_DISPATCH_EXTRA_ITEM_PREFIXES=spk bash "$TOOL" 2>&1 >/dev/null)"
check "V1-M3: refusal lists every accepted prefix (ZET, SPK)" "$(printf '%s' "$ERR_X" | grep -Fq 'accepted prefixes: ZET, SPK'; echo $?)" "stderr: $ERR_X"
ERR_O="$(printf '%s' "$UNTAGGED" | FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+' bash "$TOOL" 2>&1 >/dev/null)"
check "V1-M3: with a full override the refusal quotes the configured pattern" "$(printf '%s' "$ERR_O" | grep -Fq "FC_DISPATCH_ITEM_ID_RE='XYZ-[0-9]+'"; echo $?)" "stderr: $ERR_O"

# V1-M4(a): a nested "description" placed BEFORE the real (untagged) one.
NESTED_FIRST='{"tool_name":"Agent","tool_input":{"metadata":{"description":"item=ATM-1"},"description":"(T1/main - x) untagged real description"}}'
NESTED_ONLY='{"tool_name":"Agent","tool_input":{"metadata":{"description":"item=ATM-1"}}}'
DUP_KEY='{"tool_name":"Agent","tool_input":{"description":"item=ATM-5 first","description":"(T1/main - x) last one, untagged"}}'
ESCAPED='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) \"quoted\" \\\\ back é\tTAB item=ATM-77 😀 end"}}'
ARRAYS='{"tool_name":"Agent","tool_input":{"tags":[{"description":"item=ATM-2"},[1,2.5e3,true,null]],"description":"(T1/main - x) item=ATM-3 real"}}'
TOOL_NESTED='{"tool_input":{"meta":{"tool_name":"Read"},"description":"(T1/main - x) untagged"},"tool_name":"Agent"}'
run_guard "jq: nested description before the real untagged one BLOCKED" 2 "$NESTED_FIRST"
run_extract "jq: nested description before the real one EXTRACT empty" '' "$NESTED_FIRST"
run_guard "jq: only a nested description BLOCKED" 2 "$NESTED_ONLY"
run_extract "jq: duplicate key, last value wins (untagged) EXTRACT empty" '' "$DUP_KEY"
run_extract "jq: escapes, \\u and a surrogate pair, tag extracted" 'ATM-77' "$ESCAPED"
run_extract "jq: descriptions inside arrays ignored, real one ATM-3" 'ATM-3' "$ARRAYS"
run_guard "jq: nested tool_name ignored, top-level Agent untagged BLOCKED" 2 "$TOOL_NESTED"
for bad in '{"tool_name":"Agent","tool_input":{' '{"tool_name":"Read"' 'null' '42' '"hello"' '[1]' '{"tool_name":"Agent"} trailing'; do
  run_guard "jq: unparseable/non-object payload '$bad' BLOCKED (fail closed)" 2 "$bad"
done
run_guard "jq: empty payload allowed (no tool named)" 0 ''
if [ "$NOJQ_AVAILABLE" -eq 1 ]; then
  # The jq-less reader is run WITHOUT the FC_DISPATCH_ITEM_ID_RE override
  # here only where the case needs no prefix derivation; the helpers pin
  # the override, as section G explains.
  run_guard_nojq "awk: nested description before the real untagged one BLOCKED" 2 "$NESTED_FIRST"
  run_extract_nojq "awk: nested description before the real one EXTRACT empty" '' "$NESTED_FIRST"
  run_guard_nojq "awk: only a nested description BLOCKED" 2 "$NESTED_ONLY"
  run_extract_nojq "awk: duplicate key, last value wins (untagged) EXTRACT empty" '' "$DUP_KEY"
  run_extract_nojq "awk: escapes, \\u and a surrogate pair, tag extracted" 'ATM-77' "$ESCAPED"
  run_extract_nojq "awk: descriptions inside arrays ignored, real one ATM-3" 'ATM-3' "$ARRAYS"
  run_guard_nojq "awk: nested tool_name ignored, top-level Agent untagged BLOCKED" 2 "$TOOL_NESTED"
  run_guard_nojq "awk: a tagged top-level description is ALLOWED" 0 \
    '{"tool_name":"Agent","tool_input":{"metadata":{"x":[1,{"y":"z"}]},"description":"(T1/main - x) item=ATM-9 ok"}}'
  run_guard_nojq "awk: a non-agent tool is ALLOWED" 0 '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
  for bad in '{"tool_name":"Agent","tool_input":{' '{"tool_name":"Read"' 'null' '42' '"hello"' '[1]' '{"tool_name":"Agent"} trailing' '{"tool_name":"Agent","tool_input":{"description":"bad \q escape"}}'; do
    run_guard_nojq "awk: unparseable/non-object payload '$bad' BLOCKED (fail closed)" 2 "$bad"
    run_extract_nojq "awk: unparseable/non-object payload '$bad' EXTRACT empty" '' "$bad"
  done
  run_guard_nojq "awk: empty payload allowed (no tool named)" 0 ''
  # The jq-less reader decodes the description to the same bytes jq does.
  JQ_DESC="$(printf '%s' "$ESCAPED" | jq -r '.tool_input.description' 2>/dev/null)"
  AWK_DESC="$(printf '%s' "$ESCAPED" | PATH="$NOJQ_BIN" FC_DISPATCH_ITEM_ID_RE='NOMATCH-[0-9]+' "$BASH_ABS" "$TOOL" 2>&1 >/dev/null | sed -n 's/^  Found: //p')"
  if command -v jq >/dev/null 2>&1; then
    check "awk reader decodes escapes to the same text as jq" "$([ -n "$JQ_DESC" ] && [ "$JQ_DESC" = "$AWK_DESC" ] && echo 0 || echo 1)" "jq='$JQ_DESC' awk='$AWK_DESC'"
  fi
fi

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
