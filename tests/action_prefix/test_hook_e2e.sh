#!/usr/bin/env bash
# tests/action_prefix/test_hook_e2e.sh
#
# §11.4.140 LAYER-2 end-to-end proof: the Claude Code UserPromptSubmit hook
# scripts/hooks/action_prefix_expand.sh works OUT OF THE BOX. This test feeds
# the hook REAL stdin JSON (the Claude Code UserPromptSubmit contract,
# `{"prompt":"..."}`) for each case, captures the hook's ACTUAL emitted stdout,
# and asserts the documented behaviour with that captured stdout as the evidence
# artefact (§11.4.5 / §11.4.69 — every PASS cites a real captured file).
#
# ── What is proven (per-case) ────────────────────────────────────────────────
#   4 valid grammar forms — `BACKGROUND :: do X`, `DEFAULT::BACKGROUND :: do X`,
#     `/BACKGROUND do X`, `/DEFAULT::BACKGROUND do X` — MUST emit an
#     additionalContext payload carrying BOTH the BACKGROUND expansion text AND
#     the residual task `do X`.
#   escape `\BACKGROUND :: x` — MUST pass through unchanged (empty stdout,
#     NO expansion).
#   unknown `FOOBAR :: x` — MUST NOT expand (no BACKGROUND expansion text).
#     NOTE (no bluff): the hook does NOT emit silence here — per its documented
#     §11.4.66 / §11.4.105 contract it emits a clarify-ASK additionalContext
#     note ("do NOT silently expand ... Ask the user which registered action was
#     meant"). That is NOT an expansion. This test asserts the precise invariant
#     "the unknown token is NOT expanded" (the BACKGROUND expansion text is
#     absent), which is the behaviour the task names.
#   non-action `just a normal prompt` — MUST pass through (empty stdout).
#
# ── additionalContext semantics (precise, no bluff) ──────────────────────────
#   The Claude Code UserPromptSubmit hook contract is ADDITIVE: emitting
#   `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit",
#   "additionalContext":"<text>"}}` ADDS <text> to the conversation context that
#   Claude then obeys — it does NOT string-REPLACE the user's prompt in place.
#   So "the form expanded" means "the hook injected the expansion as obeyed
#   context", NOT "the literal prompt bytes were rewritten". This is the
#   documented behaviour (see the hook header lines 12-18). The test asserts the
#   injected-context contract exactly.
#
# ── Determinism (§11.4.50) ───────────────────────────────────────────────────
#   Every per-case hook invocation is run N=3 times against the same hook + same
#   registry; all 3 stdout captures MUST be byte-identical. Divergence is FAIL.
#
# ── Installer wiring sub-test (§11.4.75 out-of-the-box) ───────────────────────
#   scripts/install_action_prefix.sh is run against a SANDBOX .claude/settings.json
#   in a temp dir (NOT the real project). The wired hook command is asserted to be
#   the by-reference constitution path (never a copy) and to RESOLVE to an
#   existing, executable file.
#
# ── Inputs / Outputs ─────────────────────────────────────────────────────────
#   stdin  : none (self-driving per §11.4.98).
#   stdout : per-case verdict lines + final summary.
#   evidence: qa-results/action_prefix/hook_e2e/<run-ts>/<case>_iter<N>.json
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Writes evidence under qa-results/action_prefix/hook_e2e/ (gitignored runtime
#   capture per §11.4.11). The installer sub-test writes ONLY into a mktemp -d
#   sandbox, removed on exit. It does NOT touch the real project's .claude.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, jq, mktemp. The hook itself + the installer.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (mandate), §11.4.5/§11.4.69 (captured evidence), §11.4.50
#   (determinism N=3), §11.4.67 (sh -n + bash -n clean), §11.4.75 (installer
#   out-of-the-box seam), §11.4.98 (fully self-driving, no manual intervention).
#
# Classification: universal (§11.4.17)

set -euo pipefail

# ── Locate ourselves + the artefacts under test ──────────────────────────────
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
CONST_ROOT="$(cd "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)"
HOOK="$CONST_ROOT/scripts/hooks/action_prefix_expand.sh"
INSTALLER="$CONST_ROOT/scripts/install_action_prefix.sh"

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
EVID_DIR="$CONST_ROOT/qa-results/action_prefix/hook_e2e/$RUN_TS"
mkdir -p "$EVID_DIR"

N_ITER="${AB_N_ITER:-3}"

# The literal expansion text the BACKGROUND action MUST inject (the load-bearing
# substring — registry.yaml actions[].expansion, newline-collapsed).
EXPANSION_NEEDLE='The following prompt that we will provide MUST BE executed in background in parallel with all main work streams using the subagents-driven development approach!'

PASS_COUNT=0
FAIL_COUNT=0
declare -a VERDICT_ROWS=()

emit() { printf '%s\n' "$*"; }

# Build a UserPromptSubmit event JSON for an arbitrary prompt string via jq so
# the prompt is correctly JSON-encoded (the real Claude Code contract shape).
make_event_json() {
  jq -cn --arg p "$1" '{prompt:$p}'
}

# Run the hook once for a prompt, capture stdout to a file; echo the file path.
run_hook_capture() {
  local prompt="$1" out_file="$2"
  make_event_json "$prompt" | bash "$HOOK" >"$out_file" 2>/dev/null || true
  printf '%s' "$out_file"
}

# §11.4.50 N-iteration determinism: run the hook N times, assert byte-identical
# stdout across all iterations. Leaves <case>_iter1.json as the canonical
# evidence file (path echoed). Exits non-zero on divergence.
run_hook_deterministic() {
  local case_id="$1" prompt="$2"
  local first="" i f
  for i in $(seq 1 "$N_ITER"); do
    f="$EVID_DIR/${case_id}_iter${i}.json"
    make_event_json "$prompt" | bash "$HOOK" >"$f" 2>/dev/null || true
    if [ "$i" -eq 1 ]; then
      first="$f"
    else
      if ! cmp -s "$first" "$f"; then
        emit "  DETERMINISM FAIL: ${case_id} iter${i} differs from iter1"
        return 1
      fi
    fi
  done
  printf '%s' "$first"
}

# Assert: the captured stdout contains the BACKGROUND expansion needle AND the
# residual task. EVIDENCE = the captured file.
assert_expanded() {
  local case_id="$1" form_label="$2" prompt="$3"
  local cap
  if ! cap="$(run_hook_deterministic "$case_id" "$prompt")"; then
    FAIL_COUNT=$((FAIL_COUNT+1))
    VERDICT_ROWS+=("$form_label|EXPANDED?|FAIL (non-deterministic)|n/a")
    emit "FAIL [$case_id] $form_label — non-deterministic across $N_ITER iters"
    return 0
  fi
  local has_ac has_exp has_residual
  # additionalContext key present?
  if jq -e '.hookSpecificOutput.additionalContext' "$cap" >/dev/null 2>&1; then
    has_ac=yes
  else
    has_ac=no
  fi
  # expansion needle present in the additionalContext text?
  if [ "$has_ac" = yes ] && \
     jq -r '.hookSpecificOutput.additionalContext' "$cap" | grep -qF -- "$EXPANSION_NEEDLE"; then
    has_exp=yes
  else
    has_exp=no
  fi
  # residual task `do X` present in the additionalContext text?
  if [ "$has_ac" = yes ] && \
     jq -r '.hookSpecificOutput.additionalContext' "$cap" | grep -qF -- 'do X'; then
    has_residual=yes
  else
    has_residual=no
  fi
  if [ "$has_ac" = yes ] && [ "$has_exp" = yes ] && [ "$has_residual" = yes ]; then
    PASS_COUNT=$((PASS_COUNT+1))
    VERDICT_ROWS+=("$form_label|Y (expansion+residual)|PASS|$cap")
    emit "PASS [$case_id] $form_label — additionalContext carries BACKGROUND expansion + residual 'do X'  [evidence: $cap]"
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    VERDICT_ROWS+=("$form_label|ac=$has_ac exp=$has_exp residual=$has_residual|FAIL|$cap")
    emit "FAIL [$case_id] $form_label — ac=$has_ac expansion=$has_exp residual=$has_residual  [evidence: $cap]"
  fi
}

# Assert: the captured stdout is EMPTY (pure pass-through). EVIDENCE = the file.
assert_passthrough_empty() {
  local case_id="$1" form_label="$2" prompt="$3"
  local cap
  if ! cap="$(run_hook_deterministic "$case_id" "$prompt")"; then
    FAIL_COUNT=$((FAIL_COUNT+1))
    VERDICT_ROWS+=("$form_label|N|FAIL (non-deterministic)|n/a")
    emit "FAIL [$case_id] $form_label — non-deterministic across $N_ITER iters"
    return 0
  fi
  if [ ! -s "$cap" ]; then
    PASS_COUNT=$((PASS_COUNT+1))
    VERDICT_ROWS+=("$form_label|N (empty stdout, pass-through)|PASS|$cap")
    emit "PASS [$case_id] $form_label — empty stdout, prompt passes through unchanged  [evidence: $cap]"
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    VERDICT_ROWS+=("$form_label|N|FAIL (non-empty stdout)|$cap")
    emit "FAIL [$case_id] $form_label — expected EMPTY stdout, got non-empty  [evidence: $cap]"
  fi
}

# Assert: NOT expanded — the BACKGROUND expansion needle is ABSENT from stdout.
# (The hook may legitimately emit a clarify-ASK additionalContext per
# §11.4.66/§11.4.105; that is NOT an expansion. We assert the precise invariant
# the task names: the unknown token is NOT expanded.) EVIDENCE = the file.
assert_not_expanded() {
  local case_id="$1" form_label="$2" prompt="$3"
  local cap
  if ! cap="$(run_hook_deterministic "$case_id" "$prompt")"; then
    FAIL_COUNT=$((FAIL_COUNT+1))
    VERDICT_ROWS+=("$form_label|N|FAIL (non-deterministic)|n/a")
    emit "FAIL [$case_id] $form_label — non-deterministic across $N_ITER iters"
    return 0
  fi
  if grep -qF -- "$EXPANSION_NEEDLE" "$cap"; then
    FAIL_COUNT=$((FAIL_COUNT+1))
    VERDICT_ROWS+=("$form_label|Y (UNEXPECTED expansion)|FAIL|$cap")
    emit "FAIL [$case_id] $form_label — UNKNOWN token was expanded (expansion needle present)  [evidence: $cap]"
    return 0
  fi
  # Distinguish the two legitimate no-expansion shapes for the report.
  local shape
  if [ ! -s "$cap" ]; then
    shape="empty stdout"
  elif grep -qF -- 'NOT a registered action' "$cap"; then
    shape="clarify-ASK note (§11.4.66/§11.4.105)"
  else
    shape="no expansion"
  fi
  PASS_COUNT=$((PASS_COUNT+1))
  VERDICT_ROWS+=("$form_label|N (not expanded: $shape)|PASS|$cap")
  emit "PASS [$case_id] $form_label — unknown token NOT expanded ($shape)  [evidence: $cap]"
}

emit "=== §11.4.140 LAYER-2 hook e2e — run $RUN_TS (N=$N_ITER) ==="
emit "hook:      $HOOK"
emit "evidence:  $EVID_DIR"
emit ""

# ── Parse-clean precondition (§11.4.67) ──────────────────────────────────────
emit "--- parse-clean (§11.4.67) ---"
PARSE_OK=yes
for f in "$HOOK" "$CONST_ROOT/scripts/action_prefix_lib.sh" "$INSTALLER" "${BASH_SOURCE[0]:-$0}"; do
  # bash scripts (arrays, [[ ]], declare -a) are parse-checked with bash -n; only files
  # whose shebang is POSIX sh are also held to sh -n (dash rejects bash syntax by design).
  _shebang="$(head -n1 "$f" 2>/dev/null)"
  case "$_shebang" in
    '#!/bin/sh'*|'#!/usr/bin/env sh'*) _parse_ok=0; sh -n "$f" 2>/dev/null && bash -n "$f" 2>/dev/null && _parse_ok=1 ;;
    *) _parse_ok=0; bash -n "$f" 2>/dev/null && _parse_ok=1 ;;
  esac
  if [ "$_parse_ok" -eq 1 ]; then
    emit "  parse OK (${_shebang%% *}): ${f#"$CONST_ROOT"/}"
  else
    PARSE_OK=no
    emit "  PARSE FAIL: ${f#"$CONST_ROOT"/}"
  fi
done
if [ "$PARSE_OK" = yes ]; then
  PASS_COUNT=$((PASS_COUNT+1))
  emit "PASS [parse-clean] all in-scope scripts parse under sh -n AND bash -n"
else
  FAIL_COUNT=$((FAIL_COUNT+1))
  emit "FAIL [parse-clean] at least one script failed sh -n / bash -n"
fi
emit ""

# ── The 4 valid forms ────────────────────────────────────────────────────────
emit "--- 4 valid grammar forms (MUST expand) ---"
assert_expanded form1_colon_bare      'BACKGROUND :: do X'            'BACKGROUND :: do X'
assert_expanded form2_colon_namespace 'DEFAULT::BACKGROUND :: do X'   'DEFAULT::BACKGROUND :: do X'
assert_expanded form3_slash_bare      '/BACKGROUND do X'              '/BACKGROUND do X'
assert_expanded form4_slash_namespace '/DEFAULT::BACKGROUND do X'     '/DEFAULT::BACKGROUND do X'
emit ""

# ── Escape (MUST pass through unchanged) ─────────────────────────────────────
emit "--- escape (MUST pass through, no expansion) ---"
assert_passthrough_empty escape_backslash '\BACKGROUND :: x' '\BACKGROUND :: x'
emit ""

# ── Unknown (MUST NOT expand) ────────────────────────────────────────────────
emit "--- unknown action (MUST NOT expand) ---"
assert_not_expanded unknown_foobar 'FOOBAR :: x' 'FOOBAR :: x'
emit ""

# ── Non-action (MUST pass through) ───────────────────────────────────────────
emit "--- non-action prompt (MUST pass through) ---"
assert_passthrough_empty nonaction_plain 'just a normal prompt' 'just a normal prompt'
emit ""

# ── Installer wiring sub-test (sandbox, NOT the real project) ────────────────
emit "--- installer wiring into a SANDBOX .claude/settings.json (§11.4.75) ---"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/apx_install_sandbox.XXXXXX")"
cleanup_sandbox() { rm -rf "$SANDBOX"; }
trap cleanup_sandbox EXIT
INSTALL_LOG="$EVID_DIR/installer_run.log"
if bash "$INSTALLER" "$SANDBOX" >"$INSTALL_LOG" 2>&1; then
  SETTINGS="$SANDBOX/.claude/settings.json"
  cp -f "$SETTINGS" "$EVID_DIR/sandbox_settings.json" 2>/dev/null || true
  WIRED_CMD="$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command // empty' "$SETTINGS" 2>/dev/null || true)"
  case "$WIRED_CMD" in
    /*) RESOLVED="$WIRED_CMD" ;;
    *)  RESOLVED="$SANDBOX/$WIRED_CMD" ;;
  esac
  # Anti-bluff: the wired hook MUST point at the constitution-tree hook (by
  # reference, never a copy inside the sandbox project) AND resolve+executable.
  IS_BY_REFERENCE=no
  case "$RESOLVED" in
    "$SANDBOX"/*) IS_BY_REFERENCE=no ;;  # a copy inside the project = WRONG
    *) IS_BY_REFERENCE=yes ;;
  esac
  if [ -n "$WIRED_CMD" ] && [ "$RESOLVED" = "$HOOK" ] && [ -f "$RESOLVED" ] && [ -x "$RESOLVED" ] && [ "$IS_BY_REFERENCE" = yes ]; then
    PASS_COUNT=$((PASS_COUNT+1))
    emit "PASS [installer-wiring] UserPromptSubmit hook wired by-reference -> $WIRED_CMD (resolves, executable)  [evidence: $EVID_DIR/sandbox_settings.json]"
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    emit "FAIL [installer-wiring] wired='$WIRED_CMD' resolved='$RESOLVED' by-ref=$IS_BY_REFERENCE exists=$([ -f "$RESOLVED" ] && echo y || echo n) exec=$([ -x "$RESOLVED" ] && echo y || echo n)  [evidence: $EVID_DIR/sandbox_settings.json]"
  fi
  # Belt-and-suspenders: the wired hook MUST actually fire from the sandbox
  # settings' command (drive it via the wired path, not the local var).
  E2E_VIA_WIRED="$EVID_DIR/installer_wired_invoke.json"
  make_event_json 'BACKGROUND :: do X' | bash "$RESOLVED" >"$E2E_VIA_WIRED" 2>/dev/null || true
  if jq -r '.hookSpecificOutput.additionalContext' "$E2E_VIA_WIRED" 2>/dev/null | grep -qF -- "$EXPANSION_NEEDLE"; then
    PASS_COUNT=$((PASS_COUNT+1))
    emit "PASS [installer-wiring-fires] driving the WIRED hook path expands BACKGROUND  [evidence: $E2E_VIA_WIRED]"
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    emit "FAIL [installer-wiring-fires] WIRED hook path did not expand BACKGROUND  [evidence: $E2E_VIA_WIRED]"
  fi
else
  FAIL_COUNT=$((FAIL_COUNT+1))
  emit "FAIL [installer-wiring] installer exited non-zero  [evidence: $INSTALL_LOG]"
fi
emit ""

# ── Verdict table ────────────────────────────────────────────────────────────
emit "=== PER-CASE VERDICT TABLE (form -> emitted-expansion Y/N) ==="
printf '  %-32s | %-44s | %-6s\n' "FORM / CASE" "EMITTED EXPANSION?" "VERDICT"
printf '  %-32s-+-%-44s-+-%-6s\n' "--------------------------------" "--------------------------------------------" "------"
for row in "${VERDICT_ROWS[@]}"; do
  IFS='|' read -r f ans verdict _evid <<<"$row"
  printf '  %-32s | %-44s | %-6s\n' "$f" "$ans" "$verdict"
done
emit ""

emit "=== SUMMARY ==="
emit "PASS: $PASS_COUNT   FAIL: $FAIL_COUNT   (N_ITER=$N_ITER determinism)"
emit "evidence dir: $EVID_DIR"

if [ "$FAIL_COUNT" -eq 0 ]; then
  emit "RESULT: GREEN"
  exit 0
fi
emit "RESULT: RED"
exit 1
