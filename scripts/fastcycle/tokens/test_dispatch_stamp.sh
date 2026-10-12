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
run_extract "jq: duplicate key refused by the shared reader, EXTRACT empty" '' "$DUP_KEY"
run_guard "jq: duplicate key refused by the shared reader, BLOCKED" 2 "$DUP_KEY"
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
  run_extract_nojq "awk: duplicate key refused, EXTRACT empty" '' "$DUP_KEY"
  # T048 restart round 3, R3V1-M1: a repeated key whose LATER value removes,
  # nulls or retypes the path used to keep the earlier TAGGED string without
  # jq (fail open). Both readers now refuse any repeated key.
  for dup in \
    '{"tool_name":"Agent","tool_input":{"description":"(T1) item=ATM-1 x"},"tool_input":{"subagent":"y"}}' \
    '{"tool_name":"Agent","tool_input":{"description":"(T1) item=ATM-1 x","description":null}}' \
    '{"tool_name":"Agent","tool_input":{"description":"(T1) item=ATM-1 x","description":7}}' \
    '{"tool_name":"Agent","tool_input":{"description":"(T1) item=ATM-1 x"},"tool_input":5}'; do
    run_guard_nojq "awk: R3V1-M1 repeated key BLOCKED: $dup" 2 "$dup"
    run_extract_nojq "awk: R3V1-M1 repeated key EXTRACT empty: $dup" '' "$dup"
  done
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

# ===========================================================================
# J. T048 restart round 9 (V1 re-review follow-ups T1, T2, S2, P2).
#    T1  `item=??` is the honest unknown `?` (one mark), never the id `??`.
#    T2  a short release prefix pads with X (ab -> ABX), the ingest tool
#        pads the same way (its half: test_token_attribution_red.sh K17b).
#    S2  the documented guard contract for input that names no tool.
#    P2  an awk that is not gawk-compatible is refused, not mis-read.
# ===========================================================================
echo
echo "-- J. item=??, short-prefix padding, tool_name contract, non-gawk awk --"
QQ='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=?? two marks"}}'
run_extract "T1: 'item=??' EXTRACT prints the one-mark '?' (the contract is empty | ? | <prefix>-nnnn)" '?' "$QQ"
run_guard "T1: 'item=??' GUARD allowed (it is the honest unknown)" 0 "$QQ"
[ "$NOJQ_AVAILABLE" -eq 1 ] && run_extract_nojq "T1: awk path, 'item=??' EXTRACT prints '?'" '?' "$QQ"

for pair in ab:ABX a:AXX a1b:ABX 12:WIT; do
  base="${pair%%:*}"; want="${pair##*:}"
  other="${want%?}Z"
  [ "$want" = WIT ] && other=WIZ
  P_OK="{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - x) item=${want}-5 padded\"}}"
  P_Z="{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - x) item=${other}-5 padded with Z\"}}"
  OLD_HRP="$HELIX_RELEASE_PREFIX"
  export HELIX_RELEASE_PREFIX="$base"
  run_guard "T2: release prefix '$base' derives the key $want (item=$want-5 allowed)" 0 "$P_OK"
  run_extract "T2: release prefix '$base': EXTRACT $want-5" "$want-5" "$P_OK"
  run_guard "T2: release prefix '$base': the key padded with Z ($other) is NOT accepted" 2 "$P_Z"
  export HELIX_RELEASE_PREFIX="$OLD_HRP"
done

# S2: what the guard does with input that does not name a tool (header: WHAT THE
# GUARD CANNOT CLASSIFY). Allowed: empty / whitespace stdin, an object with no
# tool_name. Refused: a tool_name that is present but not a string.
J_TAGGED='"tool_input":{"description":"(T1/main - x) item=ATM-12 ok"}'
J_BARE='"tool_input":{"description":"(T1/main - x) no tag at all"}'
for badname in 'null' '5' 'true' '["Agent"]' '{"a":1}' '1.5e2'; do
  run_guard "S2: tool_name=$badname (present, not a string) BLOCKED (fail closed)" 2 "{\"tool_name\":$badname,$J_BARE}"
  run_guard "S2: tool_name=$badname BLOCKED even when the description is tagged" 2 "{$J_TAGGED,\"tool_name\":$badname}"
  run_extract "S2: tool_name=$badname EXTRACT still reads the tag (extraction never gates on tool_name)" 'ATM-12' "{\"tool_name\":$badname,$J_TAGGED}"
  [ "$NOJQ_AVAILABLE" -eq 1 ] && run_guard_nojq "S2: awk path, tool_name=$badname BLOCKED (same as jq)" 2 "{\"tool_name\":$badname,$J_BARE}"
done
for okpay in '{}' '{"session_id":"s"}' "{$J_BARE}" '{"tool_name":"Read"}' '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 ok"}}'; do
  run_guard "S2: allowed: $okpay" 0 "$okpay"
  [ "$NOJQ_AVAILABLE" -eq 1 ] && run_guard_nojq "S2: awk path, allowed: $okpay" 0 "$okpay"
done
run_guard "S2: whitespace-only stdin allowed (not a dispatch)" 0 "$(printf '  \n\t ')"
[ "$NOJQ_AVAILABLE" -eq 1 ] && run_guard_nojq "S2: awk path, whitespace-only stdin allowed" 0 "$(printf '  \n\t ')"
# The refusal text names the cause, so an operator can fix the payload.
ERR_TN="$(printf '%s' "{\"tool_name\":null,$J_BARE}" | bash "$TOOL" 2>&1 >/dev/null)"
check "S2: the refusal of a non-string tool_name says so (not the generic JSON text)" \
  "$(printf '%s' "$ERR_TN" | grep -Fq 'tool_name is present but is not a string'; echo $?)" "stderr: $ERR_TN"
# Real Claude Code payload shapes (PreToolUse and PostToolUse for Agent / Task /
# TaskCreate), as the hook receives them: every one has a STRING tool_name and
# carries keys of every JSON type elsewhere. None may be refused.
REAL_PRE='{"session_id":"abc123","transcript_path":"/home/u/.claude/projects/p/abc123.jsonl","cwd":"/work","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"description":"(T1/main - claude1 - sonnet - medium) item=ATM-12 do it","prompt":"long prompt with \"quotes\" and \\ backslashes","subagent_type":"general-purpose","model":"sonnet","run_in_background":true},"tool_use_id":"toolu_01"}'
REAL_POST='{"session_id":"abc123","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 d","prompt":"p"},"tool_response":{"agentId":"a1","status":"async_launched","totalTokens":null,"usage":{"input_tokens":1,"output_tokens":2},"content":[{"type":"text","text":"ok"}]},"tool_use_id":"toolu_01"}'
REAL_TC='{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"TaskCreate","tool_input":{"subject":"s","description":"(T2/x - y) item=? unknown","activeForm":"doing","metadata":{"k":[1,2,{"z":null}]}},"tool_use_id":"toolu_02"}'
run_guard "S2: a real PreToolUse Agent payload is allowed" 0 "$REAL_PRE"
run_guard "S2: a real PostToolUse Agent payload (tool_response with nulls, arrays, numbers) is allowed" 0 "$REAL_POST"
run_guard "S2: a real TaskCreate payload is allowed" 0 "$REAL_TC"
run_extract "S2: a real PreToolUse Agent payload EXTRACT" 'ATM-12' "$REAL_PRE"
if [ "$NOJQ_AVAILABLE" -eq 1 ]; then
  run_guard_nojq "S2: awk path, a real PreToolUse Agent payload is allowed" 0 "$REAL_PRE"
  run_guard_nojq "S2: awk path, a real PostToolUse payload is allowed" 0 "$REAL_POST"
  run_guard_nojq "S2: awk path, a real TaskCreate payload is allowed" 0 "$REAL_TC"
fi

# P2: the jq-less reader is verified on gawk only. An awk without gawk's RT, a
# NUL record separator or a one-byte %c is refused with a clear message (a
# shim stands in for mawk / busybox awk: real gawk in --traditional mode has
# no RT), and extraction stays silent with exit 0.
GAWK_ABS="$(command -v gawk 2>/dev/null || true)"
if [ -n "$GAWK_ABS" ] && [ "$NOJQ_AVAILABLE" -eq 1 ]; then
  SHIM_BIN="$(mktemp -d)"
  printf '#!/bin/sh\nexec %s --traditional "$@"\n' "$GAWK_ABS" > "$SHIM_BIN/awk"
  chmod +x "$SHIM_BIN/awk"
  ln -s "$(command -v cat)" "$SHIM_BIN/cat"
  # control needle: the shim really lacks RT (otherwise the test proves nothing)
  SHIM_RT="$(printf 'a\0' | PATH="$SHIM_BIN" awk 'BEGIN { RS = "\0" } { n++ } END { print (RT == "\0") ? "has-RT" : "no-RT" }')"
  check "P2 control needle: the stand-in awk lacks RT (gawk --traditional)" "$([ "$SHIM_RT" = no-RT ] && echo 0 || echo 1)" "got $SHIM_RT"
  P2_TAGGED='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 tagged"}}'
  P2_ERR="$(printf '%s' "$P2_TAGGED" | PATH="$SHIM_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" 2>&1 >/dev/null)"; P2_RC=$?
  check "P2: a non-gawk awk makes the guard refuse (exit 2) even for a tagged dispatch" "$([ "$P2_RC" = 2 ] && echo 0 || echo 1)" "rc=$P2_RC"
  check "P2: the refusal says the awk is not gawk-compatible and only gawk is verified" \
    "$(printf '%s' "$P2_ERR" | grep -Fq 'not gawk-compatible'; echo $?)" "stderr: $P2_ERR"
  P2_OUT="$(printf '%s' "$P2_TAGGED" | PATH="$SHIM_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" --extract-item-id 2>"$SHIM_BIN/err")"; P2_RC=$?
  check "P2: extraction with a non-gawk awk prints nothing, exits 0 and writes nothing to stderr" \
    "$([ -z "$P2_OUT" ] && [ "$P2_RC" = 0 ] && [ ! -s "$SHIM_BIN/err" ] && echo 0 || echo 1)" "out='$P2_OUT' rc=$P2_RC err='$(head -c 120 "$SHIM_BIN/err")'"
  # A second stand-in: an awk whose %c yields a multi-byte character (it
  # follows a UTF-8 locale even though the tool exports LC_ALL=C).
  ENV_ABS="$(command -v env)"
  printf '#!/bin/sh\nexec %s LC_ALL=C.UTF-8 %s "$@"\n' "$ENV_ABS" "$GAWK_ABS" > "$SHIM_BIN/awk"
  SHIM_BYTE="$(printf 'a' | PATH="$SHIM_BIN" awk '{ x = sprintf("%c", 233); print (x == "\351") ? "one-byte" : "multi-byte" }')"
  check "P2 control needle: the second stand-in awk yields a multi-byte %c" "$([ "$SHIM_BYTE" = multi-byte ] && echo 0 || echo 1)" "got $SHIM_BYTE (needs a C.UTF-8 locale on this host)"
  printf '%s' "$P2_TAGGED" | PATH="$SHIM_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" >/dev/null 2>&1; P2_RC=$?
  check "P2: an awk whose %c is not a single byte makes the guard refuse (exit 2)" "$([ "$P2_RC" = 2 ] && echo 0 || echo 1)" "rc=$P2_RC"
  rm -rf "$SHIM_BIN"
else
  echo "SKIP: gawk or the jq-less PATH is unavailable; the non-gawk awk cases cannot run."
fi

# ===========================================================================
# K. T048 restart round 10 (V1 re-review: MA, F9, F3/F4).
#    MA  the jq-less reader's UTF-8 encoder is exact for 2-, 3- and 4-byte
#        characters: a key written raw and the same key written as \u
#        escapes are ONE key (a duplicate, refused), two different
#        characters are two keys (allowed). The reviewer's mutant (4-byte
#        lead byte 241 instead of 240) makes "😀" a different key
#        from the raw emoji, and the duplicate slips through.
#    F9  FC_DISPATCH_EXTRA_ITEM_PREFIXES is split into words but never
#        glob-expanded (a `Q*` token used to expand to file names in the
#        caller's cwd). Round 11 (RV11-1): a token that is not ASCII letters
#        and digits -- `Q*`, `*`, `Q?S` -- is IGNORED with a GUARD-mode notice,
#        as transcript_ingest.py does (its half: test_token_attribution_red.sh
#        PART K, K19); the class guard is section L below.
#    F3  bounded time on a large escape-heavy payload (the hook's timeout is
#        a fail-open path), with a linearity check that a quadratic decoder
#        fails whatever the host's speed.
# ===========================================================================
echo
echo "-- K. exact UTF-8 keys, unexpanded extra prefixes, bounded time --"
K_TAG='"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 ok"}'
EMOJI="$(printf '\360\237\230\200')"   # U+1F600, 4 bytes
EACUTE="$(printf '\303\251')"           # U+00E9, 2 bytes
EURO="$(printf '\342\202\254')"         # U+20AC, 3 bytes
for spec in "4-byte:$EMOJI:\\ud83d\\ude00:\\ud83d\\ude01" "2-byte:$EACUTE:\\u00e9:\\u00ea" "3-byte:$EURO:\\u20ac:\\u20ad"; do
  IFS=: read -r klabel kraw kesc kother <<EOF_K
$spec
EOF_K
  run_guard "MA: a $klabel key written raw and as \\u escapes is a duplicate, BLOCKED" 2 "{$K_TAG,\"$kraw\":1,\"$kesc\":2}"
  run_guard "MA: a $klabel key and a DIFFERENT escaped character are two keys, allowed" 0 "{$K_TAG,\"$kraw\":1,\"$kother\":2}"
  if [ "$NOJQ_AVAILABLE" -eq 1 ]; then
    run_guard_nojq "MA: awk path, $klabel raw/escaped duplicate BLOCKED" 2 "{$K_TAG,\"$kraw\":1,\"$kesc\":2}"
    run_guard_nojq "MA: awk path, $klabel raw/different escaped character allowed" 0 "{$K_TAG,\"$kraw\":1,\"$kother\":2}"
  fi
done

# F9: run from a directory whose file names a glob would match.
K_CWD="$(mktemp -d)"
touch "$K_CWD/QRS" "$K_CWD/ABC"
k_guard() { # <name> <want-exit> <extra-prefixes> <id>
  local got
  printf '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=%s ok"}}' "$4" \
    | (cd "$K_CWD" && FC_DISPATCH_EXTRA_ITEM_PREFIXES="$3" bash "$TOOL") >/dev/null 2>&1
  got=$?
  check "$1" "$([ "$got" -eq "$2" ] && echo 0 || echo 1)" "got exit $got, want $2"
}
k_extract() { # <name> <want-stdout> <extra-prefixes> <id>
  local got rc err
  err="$(mktemp)"
  got="$(printf '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=%s ok"}}' "$4" \
    | (cd "$K_CWD" && FC_DISPATCH_EXTRA_ITEM_PREFIXES="$3" bash "$TOOL" --extract-item-id) 2>"$err")"
  rc=$?
  check "$1" "$([ "$got" = "$2" ] && [ "$rc" -eq 0 ] && [ ! -s "$err" ] && echo 0 || echo 1)" "got '$got' rc=$rc stderr='$(head -c 160 "$err")', want '$2' rc=0 empty stderr"
  rm -f "$err"
}
# control needle: in that directory an unquoted glob really does expand.
K_NEEDLE="$(cd "$K_CWD" && echo Q*)"
check "F9 control needle: in the test directory the glob Q* expands to QRS" "$([ "$K_NEEDLE" = QRS ] && echo 0 || echo 1)" "got '$K_NEEDLE'"
k_guard "F9: token 'Q*' is not glob-expanded: item=QRS-1 BLOCKED" 2 'Q*' QRS-1
k_extract "F9: token 'Q*': item=QRS-1 EXTRACT empty" '' 'Q*' QRS-1
k_guard "F9/RV11-1: token 'Q*' is not a prefix (ignored, never a regex): item=Q-1 BLOCKED" 2 'Q*' Q-1
k_extract "F9/RV11-1: token 'Q*': item=Q-1 EXTRACT empty" '' 'Q*' Q-1
k_guard "F9: token 'Q?S' is not glob-expanded: item=QRS-1 BLOCKED" 2 'Q?S' QRS-1
k_guard "F9: token '*' is not glob-expanded: item=ABC-1 BLOCKED" 2 '*' ABC-1
k_guard "F9: token '*' is ignored: the derived prefix still works (item=ATM-12 allowed)" 0 '*' ATM-12
k_extract "F9: token '*': EXTRACT ATM-12, silently" 'ATM-12' '*' ATM-12
k_guard "F9: tokens 'QRS,Q*': the valid one is kept (item=QRS-1 allowed)" 0 'QRS,Q*' QRS-1
K_ERR="$(printf '%s' "{$K_TAG}" | (cd "$K_CWD" && FC_DISPATCH_EXTRA_ITEM_PREFIXES='*' bash "$TOOL") 2>&1 >/dev/null)"
check "F9/RV11-1: GUARD mode says the token is ignored" \
  "$(printf '%s' "$K_ERR" | grep -Fq "'*' ignored: a prefix is ASCII letters and digits only"; echo $?)" "stderr: $K_ERR"
rm -rf "$K_CWD"

# F3/F4: bounded time. A 4.2 MB description made of é escapes (the
# shape the reviewer timed) must be decided within K_BOUND_S seconds with jq
# and without it, and the jq-less run on 4x the input must take less than 8x
# the time (a quadratic decoder takes about 16x). Measured on the reference
# host (64 cores, gawk 5.1.0, jq 1.8.1, round 10): 4.2 MB 1.4 s with jq,
# 3.6 s without; 16.8 MB 5.0 s / 14.1 s.
K_BOUND_S=30
K_BIG="$(mktemp)"; K_SMALL="$(mktemp)"
python3 -c '
import sys
for path, n in ((sys.argv[1], 700000), (sys.argv[2], 175000)):
    open(path, "w").write("{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - x) item=ATM-12 " + "\\u00e9" * n + "\"}}")
' "$K_BIG" "$K_SMALL"
k_time() { # <file> <nojq 0|1> -> prints "<exit> <milliseconds>"
  local t0 t1 rc
  t0=$(date +%s%N)
  if [ "$2" -eq 1 ]; then
    PATH="$NOJQ_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" < "$1" >/dev/null 2>&1
  else
    bash "$TOOL" < "$1" >/dev/null 2>&1
  fi
  rc=$?
  t1=$(date +%s%N)
  echo "$rc $(( (t1 - t0) / 1000000 ))"
}
read -r K_RC K_MS <<<"$(k_time "$K_BIG" 0)"
check "F3: 4.2 MB of \\u escapes, jq on PATH: allowed (exit 0) within ${K_BOUND_S}s (took ${K_MS} ms)" \
  "$([ "$K_RC" -eq 0 ] && [ "$K_MS" -lt $((K_BOUND_S * 1000)) ] && echo 0 || echo 1)" "exit=$K_RC ms=$K_MS"
if [ "$NOJQ_AVAILABLE" -eq 1 ]; then
  read -r K_RC K_MS <<<"$(k_time "$K_BIG" 1)"
  read -r K_RC1 K_MS1 <<<"$(k_time "$K_SMALL" 1)"
  check "F3: 4.2 MB of \\u escapes, no jq: allowed (exit 0) within ${K_BOUND_S}s (took ${K_MS} ms)" \
    "$([ "$K_RC" -eq 0 ] && [ "$K_MS" -lt $((K_BOUND_S * 1000)) ] && echo 0 || echo 1)" "exit=$K_RC ms=$K_MS"
  check "F3: no jq, 4x the input takes < 8x the time (1.05 MB ${K_MS1} ms, 4.2 MB ${K_MS} ms; quadratic would be ~16x)" \
    "$([ "$K_RC1" -eq 0 ] && [ "$K_MS1" -gt 0 ] && [ "$K_MS" -lt $((K_MS1 * 8)) ] && echo 0 || echo 1)" "small=${K_MS1}ms big=${K_MS}ms"
fi
rm -f "$K_BIG" "$K_SMALL"

# ===========================================================================
# L. T048 restart round 11, RV11-1: an extra prefix is DATA, never a regex
#    fragment. Round 10 handled only tokens that make the pattern invalid;
#    tokens that compile but are malformed made bash and Python DISAGREE
#    (measured on the round-10 tree: `)` -> bash extracted "ATM" from
#    item=ATM-1 and refused an honest item=?; `{` -> Python matched
#    item={-9; `\D` -> Python accepted item=X-4; `ATM-1` -> bash extracted
#    ATM-1-2, Python ATM-1). Both tools now keep a token only when its ASCII
#    upper-case form is [A-Z0-9]+ and ignore any other one (GUARD-mode
#    notice, silent extraction). The CLASS guard: a generated corpus of
#    tokens -- every printable ASCII punctuation character, empty and blank
#    tokens, separators, lower-case, digits, a long token, non-ASCII letters
#    (some of which Python's str.upper would widen), CR, the reviewer's four
#    -- is fed to BOTH tools, and the extraction must be identical for every
#    token x description pair. The Python side is the REAL
#    transcript_ingest.py (its _build_item_tag_re(), imported, never re-typed).
# ===========================================================================
echo
echo "-- L. extra prefixes are data: bash and Python extract the same id for a generated token corpus --"
L_DIR="$(mktemp -d)"
TI_PY="$HERE/transcript_ingest.py"
if ! python3 - "$L_DIR" "$TI_PY" <<'PYEOF'
import importlib.util, io, os, string, sys, contextlib
d, ti_path = sys.argv[1], sys.argv[2]
toks = list(string.punctuation)                               # all 32, one by one
toks += [")", "{", "\\D", "ATM-1",                            # the reviewer's four
         "", " ", "\t", ",|", "SPK", "spk", "Spk2", "123", "a1b2", "ZZZ9",
         "SPK,QRS", " SPK ", "\tSPK\nQRS", "SP|K", "A.B", "A+", "^A", "A$", "(SPK)", "S{2}",
         "[A-Z]", "Q*", "x-y", "SPK\r", "A" * 300,
         "ÄBC", "é", "ß", "ı", "ﬁ", "ſ", "KK"]
spec = importlib.util.spec_from_file_location("ti_l", ti_path)
ti = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ti)
n = 0
with open(os.path.join(d, "expected.tsv"), "w") as exp:
    for t in toks:
        up = ti._ascii_upper(t).strip() or "ATM"
        ids = [up + "-1", "ATM-1", "?", "X-4", "{-9", "ATM-1-2", "SPK-5", "Q-1", "FI-2", "SS-3"]
        os.environ["FC_DISPATCH_EXTRA_ITEM_PREFIXES"] = t
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rx = ti._build_item_tag_re()
        ignored = "ignored" in err.getvalue()
        with open(os.path.join(d, "tok_%03d" % n), "w", encoding="utf-8") as fh:
            fh.write(t)
        for j, iid in enumerate(ids):
            desc = "(T1/main - x) item=%s ok" % iid
            m = rx.search(desc)
            with open(os.path.join(d, "pay_%03d_%02d.json" % (n, j)), "w", encoding="utf-8") as fh:
                import json
                fh.write(json.dumps({"tool_name": "Agent", "tool_input": {"description": desc}}))
            exp.write("%03d_%02d|%s|%d\n" % (n, j, m.group(1) if m else "", 1 if ignored else 0))
        n += 1
print(n)
PYEOF
then
  check "L setup: the corpus generator (the real transcript_ingest.py) ran" 1 "python3 failed"
fi
L_TOTAL=0; L_DIFF=0; L_DIFFS=""; L_GUARD_BAD=0; L_NOTICE_BAD=0
# '|' separates the fields (an empty id must stay an empty field; a TAB is
# IFS whitespace and would collapse); no extracted id contains '|'.
while IFS='|' read -r l_key l_py l_ign; do
  l_n="${l_key%_*}"
  IFS= read -r -d '' l_tok < "$L_DIR/tok_$l_n" || true
  l_sh="$(FC_DISPATCH_EXTRA_ITEM_PREFIXES="$l_tok" bash "$TOOL" --extract-item-id < "$L_DIR/pay_$l_key.json" 2>"$L_DIR/err")"
  L_TOTAL=$((L_TOTAL + 1))
  if [ "$l_sh" != "$l_py" ] || [ -s "$L_DIR/err" ]; then
    L_DIFF=$((L_DIFF + 1))
    [ "$L_DIFF" -le 5 ] && L_DIFFS="$L_DIFFS [case $l_key token=$(printf '%q' "$l_tok") bash='$l_sh' python='$l_py' stderr='$(head -c 80 "$L_DIR/err")']"
  fi
  # GUARD: allowed exactly when an id was extracted; the notice appears exactly
  # when the ingest tool also warned that a token was ignored (checked on the
  # first description of each token).
  case "$l_key" in
    *_00|*_02)
      FC_DISPATCH_EXTRA_ITEM_PREFIXES="$l_tok" bash "$TOOL" < "$L_DIR/pay_$l_key.json" >/dev/null 2>"$L_DIR/gerr"; l_rc=$?
      if { [ -n "$l_py" ] && [ "$l_rc" -ne 0 ]; } || { [ -z "$l_py" ] && [ "$l_rc" -ne 2 ]; }; then
        L_GUARD_BAD=$((L_GUARD_BAD + 1)); L_DIFFS="$L_DIFFS [guard $l_key rc=$l_rc py='$l_py']"
      fi
      if [ "$l_key" = "${l_n}_00" ]; then
        if grep -q 'ignored: a prefix is ASCII letters and digits only' "$L_DIR/gerr"; then l_gn=1; else l_gn=0; fi
        [ "$l_gn" = "$l_ign" ] || { L_NOTICE_BAD=$((L_NOTICE_BAD + 1)); L_DIFFS="$L_DIFFS [notice $l_key stamp=$l_gn ingest=$l_ign token=$(printf '%q' "$l_tok")]"; }
      fi ;;
  esac
done < "$L_DIR/expected.tsv"
check "L control needle: the corpus produced cases (got $L_TOTAL, want >= 600)" "$([ "$L_TOTAL" -ge 600 ] && echo 0 || echo 1)" "total=$L_TOTAL"
check "L RV11-1: bash --extract-item-id == transcript_ingest.py for every token x description ($L_TOTAL pairs, $L_DIFF differ), extraction silent" \
  "$([ "$L_TOTAL" -gt 0 ] && [ "$L_DIFF" -eq 0 ] && echo 0 || echo 1)" "$L_DIFFS"
check "L RV11-1: GUARD allows exactly the dispatches the extraction names, for every token ($L_GUARD_BAD wrong)" \
  "$([ "$L_GUARD_BAD" -eq 0 ] && echo 0 || echo 1)" "$L_DIFFS"
check "L RV11-1: the GUARD notice 'ignored' appears exactly when the ingest tool also ignores a token ($L_NOTICE_BAD differ)" \
  "$([ "$L_NOTICE_BAD" -eq 0 ] && echo 0 || echo 1)" "$L_DIFFS"
# Absolute rows for the reviewer's four tokens (a parity check alone would
# pass if both tools went wrong the same way).
l_abs() { # <token> <id> <want-extract> <want-guard>
  local p got rc
  p="{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - x) item=$2 ok\"}}"
  got="$(printf '%s' "$p" | FC_DISPATCH_EXTRA_ITEM_PREFIXES="$1" bash "$TOOL" --extract-item-id 2>/dev/null)"
  printf '%s' "$p" | FC_DISPATCH_EXTRA_ITEM_PREFIXES="$1" bash "$TOOL" >/dev/null 2>&1; rc=$?
  check "L RV11-1 absolute: token '$1', item=$2 -> extract '$3', guard exit $4" \
    "$([ "$got" = "$3" ] && [ "$rc" -eq "$4" ] && echo 0 || echo 1)" "got extract='$got' guard=$rc"
}
l_abs ')' ATM-1 ATM-1 0
l_abs ')' '?' '?' 0
l_abs '{' '{-9' '' 2
l_abs '\D' X-4 '' 2
l_abs 'ATM-1' ATM-1-2 ATM-1 0
l_abs 'spk' SPK-5 SPK-5 0
rm -rf "$L_DIR"

# ===========================================================================
# L2. The full-pattern override FC_DISPATCH_ITEM_ID_RE stays a regex (OWED-TI-2):
#     one that does not compile falls back to the derived prefix with a GUARD
#     notice and a silent extraction, as transcript_ingest.py does (its half:
#     test_token_attribution_red.sh PART G1). Since round 11 an extra-prefix
#     token can no longer produce an invalid pattern, so these rows are what
#     exercises the fallback.
# ===========================================================================
echo
echo "-- L2. an invalid FC_DISPATCH_ITEM_ID_RE falls back to the derived prefix --"
L2_P='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 ok"}}'
printf '%s' "$L2_P" | FC_DISPATCH_ITEM_ID_RE='ATM-(' bash "$TOOL" >/dev/null 2>"$HERE/.l2_err.$$"; L2_RC=$?
L2_ERR="$(cat "$HERE/.l2_err.$$")"; rm -f "$HERE/.l2_err.$$"
check "L2: FC_DISPATCH_ITEM_ID_RE='ATM-(' does not compile: item=ATM-12 is still allowed (derived prefix)" "$([ "$L2_RC" -eq 0 ] && echo 0 || echo 1)" "rc=$L2_RC"
check "L2: ...and GUARD mode says the configured pattern is not a valid regex" \
  "$(printf '%s' "$L2_ERR" | grep -Fq 'is not a valid regex'; echo $?)" "stderr: $L2_ERR"
L2_OUT="$(printf '%s' "$L2_P" | FC_DISPATCH_ITEM_ID_RE='ATM-(' bash "$TOOL" --extract-item-id 2>"$HERE/.l2_err.$$")"
check "L2: ...and the extraction prints ATM-12 with nothing on stderr" \
  "$([ "$L2_OUT" = ATM-12 ] && [ ! -s "$HERE/.l2_err.$$" ] && echo 0 || echo 1)" "out='$L2_OUT' err='$(head -c 120 "$HERE/.l2_err.$$")'"
rm -f "$HERE/.l2_err.$$"
printf '%s' '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=QZT-1 ok"}}' | FC_DISPATCH_ITEM_ID_RE='ATM-(' bash "$TOOL" >/dev/null 2>&1; L2_RC=$?
check "L2: ...and an id the derived prefix does not name is refused (exit 2)" "$([ "$L2_RC" -eq 2 ] && echo 0 || echo 1)" "rc=$L2_RC"

# ===========================================================================
# M. T048 restart round 11, RV11-3: the reader's time is near-linear in the
#    payload for EVERY shape, not only for one long string. Round 10 rebuilt
#    the path of every value from all open containers (cur_path()), so arrays
#    nested k deep around k strings cost k*k: measured on the round-10 tree
#    (reference host, 64 cores, gawk 5.1.0, jq 1.8.1): 12 KB 1.9 s / 48 KB
#    30.8 s without jq, 0.4 s / 5.6 s with jq -- a hook timeout would let the
#    dispatch through. Each shape is generated at a small size and at 4x that
#    size; each run is timed twice and the faster run counts. Asserted per
#    shape and per mode (jq / no jq): both sizes allowed (exit 0); the big one
#    within M_BOUND_S; and big < 8 x small + M_SLACK_MS (near-linear: 4x the
#    input may take less than 8x the time; a quadratic reader takes about
#    16x; the slack absorbs the ~40 ms process start that dominates a small
#    run). The shapes: arrays nested deep around many strings, objects nested
#    deep each holding strings, one very long key over many values, many
#    strings full of escapes, many small values one per line, a description
#    full of near-tags.
# ===========================================================================
echo
echo "-- M. near-linear reader time across payload shapes (jq and no jq) --"
M_BOUND_S=10
M_SLACK_MS=300
M_DIR="$(mktemp -d)"
M_SHAPES="$(python3 - "$M_DIR" <<'PYEOF'
import sys, json
out = sys.argv[1]
HEAD = '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 shape"},"z":'
def deep_arrays(k):
    return HEAD + "[" * k + '"a",' * k + '"a"' + "]" * k + "}"
def deep_objects(k):
    return HEAD + '{"s":"v","t":"w","a":' * k + "1" + "}" * k + "}"
def long_keys(k):
    return HEAD + '{"' + "K" * k + '":[' + ",".join(['"v"'] * k) + "]}}"
def escapes(k):
    return HEAD + "[" + ",".join(['"\\n\\t\\"\\\\\\u00e9\\ud83d\\ude00x"'] * k) + "]}"
def many_small(k):
    vals = ['1', '"a"', 'true', 'null', '-2.5e3', '{}', '[]']
    return HEAD + "[\n" + ",\n".join(vals[i % len(vals)] for i in range(k)) + "\n]}"
def tag_noise(k):
    return '{"tool_name":"Agent","tool_input":{"description":"' + "item= item=ATM- xitem=ATM-1 " * k + 'item=ATM-12"}}'
SHAPES = {"deep_arrays": (deep_arrays, 2000), "deep_objects": (deep_objects, 1200),
          "long_keys": (long_keys, 3000), "escapes": (escapes, 20000),
          "many_small": (many_small, 50000), "tag_noise": (tag_noise, 20000)}
for name, (fn, k) in SHAPES.items():
    for size, kk in (("small", k), ("big", 4 * k)):
        doc = fn(kk)
        json.loads(doc)
        open("%s/%s_%s.json" % (out, name, size), "w").write(doc)
print(" ".join(SHAPES))
PYEOF
)"
m_time() { # <file> <nojq 0|1> -> "<exit> <ms>" (the faster of two runs)
  local best="" rc t0 t1 ms i
  for i in 1 2; do
    t0=$(date +%s%N)
    if [ "$2" -eq 1 ]; then
      PATH="$NOJQ_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" < "$1" >/dev/null 2>&1
    else
      bash "$TOOL" < "$1" >/dev/null 2>&1
    fi
    rc=$?
    t1=$(date +%s%N)
    ms=$(( (t1 - t0) / 1000000 ))
    if [ -z "$best" ] || [ "$ms" -lt "$best" ]; then best=$ms; fi
  done
  echo "$rc $best"
}
check "M control needle: the shape generator wrote 12 payloads" "$([ "$(ls "$M_DIR" | wc -l)" -eq 12 ] && echo 0 || echo 1)" "shapes='$M_SHAPES' files=$(ls "$M_DIR" | wc -l)"
for m_shape in $M_SHAPES; do
  for m_nojq in 0 1; do
    if [ "$m_nojq" -eq 1 ] && [ "$NOJQ_AVAILABLE" -ne 1 ]; then continue; fi
    m_mode=$([ "$m_nojq" -eq 1 ] && echo "no jq" || echo "jq")
    read -r M_RC1 M_MS1 <<<"$(m_time "$M_DIR/${m_shape}_small.json" "$m_nojq")"
    read -r M_RC2 M_MS2 <<<"$(m_time "$M_DIR/${m_shape}_big.json" "$m_nojq")"
    check "M RV11-3: $m_shape ($m_mode): small ${M_MS1} ms, 4x ${M_MS2} ms -- both allowed, 4x within ${M_BOUND_S}s and < 8 x small + ${M_SLACK_MS} ms" \
      "$([ "$M_RC1" -eq 0 ] && [ "$M_RC2" -eq 0 ] && [ "$M_MS2" -lt $((M_BOUND_S * 1000)) ] && [ "$M_MS2" -lt $((M_MS1 * 8 + M_SLACK_MS)) ] && echo 0 || echo 1)" \
      "rc=$M_RC1/$M_RC2 small=${M_MS1}ms big=${M_MS2}ms"
  done
done
rm -rf "$M_DIR"

# ===========================================================================
# N. T048 restart round 11, RV11-2 / RV11-5: the caller's environment does
#    not change any verdict. Measured on the round-10 tree: a ~/.jq
#    redefining `objects` made the guard ALLOW an untagged dispatch (fail
#    open), a ~/.jq with a syntax error refused every dispatch, and
#    POSIXLY_CORRECT put gawk in POSIX mode so the awk probe failed and every
#    dispatch was refused. The CLASS guard: a matrix of hostile environments
#    (each applied on top of this suite's own) x six payloads x GUARD and
#    EXTRACTION x jq and no jq; every (exit, stdout) must equal the clean
#    run's, and EXTRACTION must stay silent on stderr. BASH_ENV and ENV files
#    here only SET state (functions, shell options, variables); code a
#    BASH_ENV file RUNS before the tool's first line is out of the tool's
#    reach (see the tool's header, THE ENVIRONMENT). Every run starts with
#    BASH_ENV and ENV removed unless the row sets them: the agent environment
#    on the reference host exports BASH_ENV=~/.bashrc, and under the SHELLOPTS
#    row bash traces that file's first lines on stderr BEFORE the tool's first
#    line -- the boundary above, measured, not something the tool can undo.
# ===========================================================================
echo
echo "-- N. hostile caller environments do not change any verdict --"
N_DIR="$(mktemp -d)"
mkdir -p "$N_DIR/home_objects" "$N_DIR/home_syntax" "$N_DIR/lib"
printf 'def objects: {tool_input: {description: "item=ATM-1 forged"}, description: "item=ATM-1 forged"};\n' > "$N_DIR/home_objects/.jq"
printf 'def broken(: ;\n' > "$N_DIR/home_syntax/.jq"
printf 'def objects: {tool_input: {description: "item=ATM-1 forged"}};\n' > "$N_DIR/lib/jq.jq"
cp "$N_DIR/home_objects/.jq" "$N_DIR/lib/.jq"
cat > "$N_DIR/bash_env.sh" <<'EOF_BE'
shopt -s nocasematch extglob nullglob failglob
set -f
jq() { printf '%s\n' 'item=ATM-1 forged'; }
awk() { command awk -v forged=1 "$@"; }
tr() { command tr "$@" | command tr 'A-Z' 'a-z'; }
cat() { printf '{"tool_name":"Agent","tool_input":{"description":"item=ATM-1 forged"}}'; }
printf() { builtin printf "$@"; }
export FC_FORGED=1
EOF_BE
N_TAG='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 ok"}}'
N_UNTAG='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) no tag"}}'
N_LOWER='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=atm-12 lower case"}}'
N_BASH='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
N_BADJSON='{"tool_name":"Agent","tool_input":{"description":"item=ATM-12"}} trailing'
N_TNNULL='{"tool_name":null,"tool_input":{"description":"item=ATM-12"}}'
n_run() { # <nojq> <mode guard|extract> <payload> [env assignments...] -> "rc|stdout|stderr-empty"
  local nojq="$1" mode="$2" payload="$3" out rc arg=""
  shift 3
  [ "$mode" = extract ] && arg="--extract-item-id"
  if [ "$nojq" -eq 1 ]; then
    out="$(printf '%s' "$payload" | env -u BASH_ENV -u ENV "$@" PATH="$NOJQ_BIN" FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' "$BASH_ABS" "$TOOL" $arg 2>"$N_DIR/err")"
  else
    out="$(printf '%s' "$payload" | env -u BASH_ENV -u ENV "$@" "$BASH_ABS" "$TOOL" $arg 2>"$N_DIR/err")"
  fi
  rc=$?
  if [ "$mode" = extract ]; then
    printf '%s|%s|%s' "$rc" "$out" "$([ -s "$N_DIR/err" ] && echo noisy || echo silent)"
  else
    printf '%s' "$rc"
  fi
}
N_ENVS=(
  "a ~/.jq redefining objects|HOME=$N_DIR/home_objects"
  "a ~/.jq with a syntax error|HOME=$N_DIR/home_syntax"
  "POSIXLY_CORRECT|POSIXLY_CORRECT=1"
  "AWKPATH and AWKLIBPATH|AWKPATH=$N_DIR/lib AWKLIBPATH=$N_DIR/lib"
  "GAWK_READ_TIMEOUT=1|GAWK_READ_TIMEOUT=1"
  "BASH_ENV setting functions and options|BASH_ENV=$N_DIR/bash_env.sh"
  "ENV|ENV=$N_DIR/bash_env.sh"
  "IFS|IFS=x"
  "SHELLOPTS|SHELLOPTS=xtrace:noglob:errexit:nounset"
  "BASHOPTS|BASHOPTS=nocasematch:extglob:failglob:nullglob"
  "exported functions|BASH_FUNC_jq%%=() { echo forged; } BASH_FUNC_awk%%=() { :; } BASH_FUNC_tr%%=() { :; } BASH_FUNC_cat%%=() { :; }"
  "LC_ALL=C.UTF-8|LC_ALL=C.UTF-8"
  "LANG=tr_TR.UTF-8, LC_CTYPE=en_US.UTF-8|LANG=tr_TR.UTF-8 LC_CTYPE=en_US.UTF-8 LC_ALL="
  "JQ_COLORS and JQ_LIBRARY_PATH|JQ_COLORS=0;31:0;32 JQ_LIBRARY_PATH=$N_DIR/lib"
  "TMPDIR, CDPATH, GLOBIGNORE, GIT_DIR|TMPDIR=/nonexistent CDPATH=/ GLOBIGNORE=* GIT_DIR=/nonexistent"
)
N_PAYLOADS=("$N_TAG" "$N_UNTAG" "$N_LOWER" "$N_BASH" "$N_BADJSON" "$N_TNNULL")
declare -A N_BASE=()
for n_nojq in 0 1; do
  [ "$n_nojq" -eq 1 ] && [ "$NOJQ_AVAILABLE" -ne 1 ] && continue
  for n_i in "${!N_PAYLOADS[@]}"; do
    for n_mode in guard extract; do
      N_BASE["$n_nojq/$n_i/$n_mode"]="$(n_run "$n_nojq" "$n_mode" "${N_PAYLOADS[$n_i]}" N_CLEAN=1)"
    done
  done
done
check "N control: the clean verdicts are the expected ones (tagged allowed, untagged / lower-case refused, other tool allowed, bad JSON and null tool_name refused; extraction ATM-12, silent)" \
  "$([ "${N_BASE[0/0/guard]}" = 0 ] && [ "${N_BASE[0/1/guard]}" = 2 ] && [ "${N_BASE[0/2/guard]}" = 2 ] && [ "${N_BASE[0/3/guard]}" = 0 ] && [ "${N_BASE[0/4/guard]}" = 2 ] && [ "${N_BASE[0/5/guard]}" = 2 ] && [ "${N_BASE[0/0/extract]}" = '0|ATM-12|silent' ] && echo 0 || echo 1)" \
  "base: $(for k in "${!N_BASE[@]}"; do printf '%s=%s ' "$k" "${N_BASE[$k]}"; done)"
N_HAS_TR=0; locale -a 2>/dev/null | grep -qi '^tr_TR' && N_HAS_TR=1
for n_spec in "${N_ENVS[@]}"; do
  n_label="${n_spec%%|*}"
  n_assign="${n_spec#*|}"
  n_args=()
  # Split the assignments on the spaces that start a new NAME=; a function
  # value contains spaces of its own.
  while IFS= read -r n_a || [ -n "$n_a" ]; do [ -n "$n_a" ] && n_args+=("$n_a"); done < <(printf '%s\n' "$n_assign" | sed -E 's/ ([A-Za-z_][A-Za-z0-9_%]*=)/\n\1/g')
  # control needle: the row really applies its assignments (round 11: an
  # earlier draft of this loop dropped a single assignment without a newline,
  # and the whole matrix passed on the round-10 tool, blind).
  n_want="$(printf '%s' "$n_assign" | grep -oE '(^| )[A-Za-z_][A-Za-z0-9_%]*=' | wc -l)"
  check "N control: '$n_label' parsed into its $n_want assignment(s)" "$([ "${#n_args[@]}" -eq "$n_want" ] && [ "$n_want" -ge 1 ] && echo 0 || echo 1)" "got ${#n_args[@]}: ${n_args[*]}"
  n_diff=""
  for n_nojq in 0 1; do
    [ "$n_nojq" -eq 1 ] && [ "$NOJQ_AVAILABLE" -ne 1 ] && continue
    for n_i in "${!N_PAYLOADS[@]}"; do
      for n_mode in guard extract; do
        n_got="$(n_run "$n_nojq" "$n_mode" "${N_PAYLOADS[$n_i]}" "${n_args[@]}")"
        [ "$n_got" = "${N_BASE[$n_nojq/$n_i/$n_mode]}" ] || n_diff="$n_diff [nojq=$n_nojq payload=$n_i $n_mode: got '$n_got' clean '${N_BASE[$n_nojq/$n_i/$n_mode]}']"
      done
    done
  done
  check "N RV11-2/RV11-5: $n_label: every verdict equals the clean run (6 payloads x guard/extract x jq/no jq)" \
    "$([ -z "$n_diff" ] && echo 0 || echo 1)" "$n_diff"
done
[ "$N_HAS_TR" -eq 1 ] || echo "  NOTE  no tr_TR locale on this host: the LANG=tr_TR row ran with an unknown locale (still a hostile value)"
rm -rf "$N_DIR"

# ===========================================================================
# O. T048 restart round 11, reviewer mutant V1: CR (\r) is JSON whitespace.
#    The reader is the shared gate of both paths, so a gate that stopped
#    skipping CR would refuse the payload with AND without jq -- the parity
#    matrix cannot see that. Absolute verdicts: CR, LF and TAB between tokens
#    are allowed and extract the id in both paths.
# ===========================================================================
echo
echo "-- O. CR, LF and TAB between tokens are whitespace (absolute verdicts, both paths) --"
for o_ws in CR LF TAB; do
  case "$o_ws" in CR) o_c=$'\r' ;; LF) o_c=$'\n' ;; TAB) o_c=$'\t' ;; esac
  o_p="{${o_c}\"tool_name\"${o_c}:${o_c}\"Agent\"${o_c},${o_c}\"tool_input\":{\"description\":\"(T1/main - x) item=ATM-12 ok\"${o_c}}${o_c}}${o_c}"
  run_guard "V1: $o_ws between every token: allowed" 0 "$o_p"
  run_extract "V1: $o_ws between every token: EXTRACT ATM-12" 'ATM-12' "$o_p"
  if [ "$NOJQ_AVAILABLE" -eq 1 ]; then
    run_guard_nojq "V1: awk path, $o_ws between every token: allowed" 0 "$o_p"
    run_extract_nojq "V1: awk path, $o_ws between every token: EXTRACT ATM-12" 'ATM-12' "$o_p"
  fi
done

# ===========================================================================
# P. T048 restart round 11: the clean-environment re-execution fails CLOSED.
#    The tool re-executes "$BASH" (the path bash derived from its own argv[0]).
#    When that names no executable the re-execution fails: GUARD refuses with
#    a message (exit 2), EXTRACTION prints nothing and exits 0. Reached by
#    starting the tool with an argv[0] that names no file.
# ===========================================================================
echo
echo "-- P. a failed clean-environment re-execution refuses (GUARD) / stays silent (EXTRACTION) --"
P_TAGGED='{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) item=ATM-12 ok"}}'
P_BASH="$(exec -a /nonexistent/fc-no-bash/bash "$BASH_ABS" -c 'printf %s "$BASH"')"
check "P control needle: bash started as /nonexistent/fc-no-bash/bash reports that path as \$BASH" "$([ "$P_BASH" = /nonexistent/fc-no-bash/bash ] && echo 0 || echo 1)" "BASH='$P_BASH'"
P_ERR="$(printf '%s' "$P_TAGGED" | (exec -a /nonexistent/fc-no-bash/bash "$BASH_ABS" "$TOOL") 2>&1 >/dev/null)"; P_RC=$?
check "P: GUARD refuses a tagged dispatch when it cannot re-execute itself cleanly (exit 2, says so)" \
  "$([ "$P_RC" -eq 2 ] && printf '%s' "$P_ERR" | grep -Fq 'could not re-execute itself in a clean environment' && echo 0 || echo 1)" "rc=$P_RC stderr=$P_ERR"
P_OUT="$(printf '%s' "$P_TAGGED" | (exec -a /nonexistent/fc-no-bash/bash "$BASH_ABS" "$TOOL" --extract-item-id) 2>"$HERE/.p_err.$$")"; P_RC=$?
check "P: EXTRACTION prints nothing, exits 0 and writes nothing to stderr" \
  "$([ -z "$P_OUT" ] && [ "$P_RC" -eq 0 ] && [ ! -s "$HERE/.p_err.$$" ] && echo 0 || echo 1)" "out='$P_OUT' rc=$P_RC err='$(head -c 160 "$HERE/.p_err.$$")'"
rm -f "$HERE/.p_err.$$"

# ===========================================================================
# Q. T048 restart round 11, RV11-3: the incremental path match reads the
#    value at EXACTLY tool_input -> description (or -> subagent), whatever
#    surrounds it. Absolute verdicts in both paths: an array in place of
#    tool_input, a description one level too deep or under another parent, a
#    key that is a prefix of the wanted one, and a raw line feed inside the
#    description (refused: a raw control character in a string).
# ===========================================================================
echo
echo "-- Q. the value is read at exactly the wanted path (both paths) --"
Q_LF="$(printf '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x)\nitem=ATM-12"}}')"
for q_spec in \
  "tool_input is an array holding the tag|2||{\"tool_name\":\"Agent\",\"tool_input\":[\"(T1/main - x) item=ATM-12\"]}" \
  "description under another top-level key|2||{\"tool_name\":\"Agent\",\"x\":{\"description\":\"(T1/main - x) item=ATM-12\"}}" \
  "description one level too deep|2||{\"tool_name\":\"Agent\",\"tool_input\":{\"x\":{\"description\":\"(T1/main - x) item=ATM-12\"}}}" \
  "key tool_inpu (a prefix of tool_input)|2||{\"tool_name\":\"Agent\",\"tool_inpu\":{\"description\":\"(T1/main - x) item=ATM-12\"}}" \
  "key description2 next to an untagged description|2||{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - x) none\",\"description2\":\"item=ATM-12\"}}" \
  "the right value next to arrays of look-alikes|0|ATM-12|{\"tool_name\":\"Agent\",\"x\":[{\"description\":\"no\"},[\"item=ATM-9\"]],\"tool_input\":{\"y\":[{\"description\":\"item=ATM-8\"}],\"description\":\"(T1/main - x) item=ATM-12\"}}" \
  "a raw line feed inside the description is refused|2||$Q_LF"; do
  q_label="${q_spec%%|*}"; q_rest="${q_spec#*|}"
  q_rc="${q_rest%%|*}"; q_rest="${q_rest#*|}"
  q_id="${q_rest%%|*}"; q_pay="${q_rest#*|}"
  run_guard "RV11-3 path: $q_label (exit $q_rc)" "$q_rc" "$q_pay"
  run_extract "RV11-3 path: $q_label: EXTRACT '$q_id'" "$q_id" "$q_pay"
  if [ "$NOJQ_AVAILABLE" -eq 1 ]; then
    run_guard_nojq "RV11-3 path, awk path: $q_label (exit $q_rc)" "$q_rc" "$q_pay"
    run_extract_nojq "RV11-3 path, awk path: $q_label: EXTRACT '$q_id'" "$q_id" "$q_pay"
  fi
done

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
