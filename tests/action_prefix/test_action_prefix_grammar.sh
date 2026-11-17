#!/usr/bin/env bash
# tests/action_prefix/test_action_prefix_grammar.sh
#
# §11.4.140 GRAMMAR_ADDENDUM (2026-06-09) + arrow form (2026-07-02) — full test
# suite for the FIVE equivalent action-prefix forms + the action NAMESPACE, plus
# the registered REMINDER action:
#   (1) `ACTION :: rest`           (2) `PREFIX::ACTION :: rest`
#   (3) `/ACTION rest`             (4) `/PREFIX::ACTION rest`
#   (5) `ACTION ---> rest`          (+ `PREFIX::ACTION ---> rest`)
#
# Test types (§11.4.27 — every type the surface warrants):
#   UNIT        — apx_parse_prefix returns the correct (ns,action,rest,form) for
#                 every form (with + without DEFAULT prefix); escape → literal;
#                 unknown action → ASK; lowercase / `key: value` / `Foo::Bar` /
#                 URL → NO match; python-path ≡ awk-path (byte-identical).
#   INTEGRATION — the real UserPromptSubmit hook rewrites a sample prompt for
#                 each of the 4 forms (additionalContext correct).
#   E2E         — apx_expand_prompt on each form yields the BACKGROUND expansion
#                 + residual.
#   DETERMINISM — §11.4.50: each assertion run N=3 with identical evidence-hash.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash tests/action_prefix/test_action_prefix_grammar.sh
#   AB_N_ITER=3 bash tests/action_prefix/test_action_prefix_grammar.sh
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   None required. Uses the in-tree registry (actions/registry.yaml) via the lib.
#   AB_N_ITER (optional, default 3) — determinism iteration count (§11.4.50).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Captured evidence under qa-results/action_prefix/<run-id>/ (input→output per
#   case). Exit 0 iff ALL cases PASS; non-zero on any FAIL.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Writes evidence files under qa-results/ (gitignored). No device, no network,
#   no governance-file edit. Self-cleans nothing destructive (read-only on src).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   scripts/action_prefix_lib.sh, scripts/hooks/action_prefix_expand.sh,
#   python3 (+ PyYAML) preferred / awk fallback, jq preferred / sed fallback.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (mandate + GRAMMAR_ADDENDUM), §11.4.27 (test-type coverage),
#   §11.4.50 (determinism), §11.4.67 (sh -n + bash -n clean), §11.4.69
#   (captured evidence), §11.4.6 (no-guessing — every PASS cites real output).
#
# Classification: universal (§11.4.17)

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)"
LIB="$ROOT/scripts/action_prefix_lib.sh"
HOOK="$ROOT/scripts/hooks/action_prefix_expand.sh"

# shellcheck source=/dev/null
. "$LIB"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"
EVID_DIR="$ROOT/qa-results/action_prefix/$RUN_ID"
mkdir -p "$EVID_DIR"

N_ITER="${AB_N_ITER:-3}"

PASS=0
FAIL=0
FAILED_CASES=""

# ── tiny assertion helpers (no external test framework) ──────────────────────
# assert_eq <case-id> <expected> <actual>  → PASS/FAIL + evidence file.
assert_eq() {
  local id="$1" exp="$2" act="$3"
  {
    printf 'CASE: %s\n' "$id"
    printf 'EXPECT: [%s]\n' "$exp"
    printf 'ACTUAL: [%s]\n' "$act"
  } > "$EVID_DIR/$id.txt"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS+1))
    printf 'PASS: %s [evidence: %s]\n' "$id" "$EVID_DIR/$id.txt"
  else
    FAIL=$((FAIL+1))
    FAILED_CASES="$FAILED_CASES $id"
    printf 'FAIL: %s\n  EXPECT [%s]\n  ACTUAL [%s]\n' "$id" "$exp" "$act"
  fi
}

# field <json> <key>
field() { apx__json_get "$1" "$2"; }

# parse4 <prompt> → "ns|action|rest|form" or "NOMATCH"
parse4() {
  local t
  if t="$(apx_parse_prefix "$1" 2>/dev/null)"; then
    printf '%s' "$t" | tr '\t' '|'
  else
    printf 'NOMATCH'
  fi
}

# parse4_python / parse4_awk — direct path parity probes.
parse4_python() {
  local r; r="$(apx__parse_via_python "$1" 2>/dev/null; printf 'rc=%s' "$?")"
  printf '%s' "$r" | tr '\t' '|'
}
parse4_awk() {
  local r; r="$(apx__parse_via_awk "$1" 2>/dev/null; printf 'rc=%s' "$?")"
  printf '%s' "$r" | tr '\t' '|'
}

# ──────────────────────────────────────────────────────────────────────────────
# UNIT — apx_parse_prefix 4-tuple across all forms (with + without DEFAULT)
# ──────────────────────────────────────────────────────────────────────────────
echo "=== UNIT: parse 4 forms ==="
assert_eq "U-form1-bare-colon"        "DEFAULT|BACKGROUND|do X|colon"  "$(parse4 'BACKGROUND :: do X')"
assert_eq "U-form2-ns-colon-DEFAULT"  "DEFAULT|BACKGROUND|do X|colon"  "$(parse4 'DEFAULT::BACKGROUND :: do X')"
assert_eq "U-form2-ns-colon-custom"   "MYNS|BACKGROUND|do X|colon"     "$(parse4 'MYNS::BACKGROUND :: do X')"
assert_eq "U-form3-bare-slash"        "DEFAULT|BACKGROUND|do X|slash"  "$(parse4 '/BACKGROUND do X')"
assert_eq "U-form4-ns-slash-DEFAULT"  "DEFAULT|BACKGROUND|do X|slash"  "$(parse4 '/DEFAULT::BACKGROUND do X')"
assert_eq "U-form4-ns-slash-custom"   "MYNS|BACKGROUND|do X|slash"     "$(parse4 '/MYNS::BACKGROUND do X')"
# multi-word + multi-space residual preserved
assert_eq "U-form3-multiword"         "DEFAULT|BACKGROUND|please do the thing|slash" "$(parse4 '/BACKGROUND please do the thing')"
assert_eq "U-form3-multispace"        "DEFAULT|BACKGROUND|do X|slash"  "$(parse4 '/BACKGROUND    do X')"

# ── Form 5 (arrow ` ---> `): bare + namespaced (DEFAULT + custom) + multiword ──
echo "=== UNIT: parse form 5 (arrow) ==="
assert_eq "U-form5-bare-arrow"        "DEFAULT|BACKGROUND|do X|arrow"  "$(parse4 'BACKGROUND ---> do X')"
assert_eq "U-form5-ns-arrow-DEFAULT"  "DEFAULT|BACKGROUND|do X|arrow"  "$(parse4 'DEFAULT::BACKGROUND ---> do X')"
assert_eq "U-form5-ns-arrow-custom"   "MYNS|BACKGROUND|do X|arrow"     "$(parse4 'MYNS::BACKGROUND ---> do X')"
assert_eq "U-form5-multiword"         "DEFAULT|BACKGROUND|please do the thing|arrow" "$(parse4 'BACKGROUND ---> please do the thing')"
# arrow token immediately after leading token; a colon token then a mid-prose
# arrow parses as the COLON form (arrow branch falls through), and vice versa.
assert_eq "U-form5-colon-then-arrow"  "DEFAULT|A|B ---> C|colon"       "$(parse4 'A :: B ---> C')"
assert_eq "U-form5-arrow-then-colon"  "DEFAULT|A|B :: C|arrow"         "$(parse4 'A ---> B :: C')"

# ──────────────────────────────────────────────────────────────────────────────
# UNIT — NEGATIVES: lowercase / key:value / Foo::Bar / URL / mid-prose / no-rest
# ──────────────────────────────────────────────────────────────────────────────
echo "=== UNIT: negatives (no match) ==="
assert_eq "U-neg-lowercase-colon"     "NOMATCH" "$(parse4 'background :: x')"
assert_eq "U-neg-lowercase-slash"     "NOMATCH" "$(parse4 '/background x')"
assert_eq "U-neg-keyvalue"            "NOMATCH" "$(parse4 'key: value')"
assert_eq "U-neg-cpp-FooBar"          "NOMATCH" "$(parse4 'Foo::Bar')"
assert_eq "U-neg-cpp-nospace"         "NOMATCH" "$(parse4 'BACKGROUND::do X')"
# Single-colon form: parser matches ALL uppercase TOKEN: rest (grammar level).
# REGISTERED-ACTION-ONLY enforcement is at the RESOLVER level (§11.4.202):
# unregistered tokens like TODO: produce NO-OP, never ASK/expansion.
assert_eq "U-single-colon-unregistered" "DEFAULT|TODO|do X|single_colon" "$(parse4 'TODO: do X')"
assert_eq "U-neg-url"                 "NOMATCH" "$(parse4 'https://example.com/x')"
assert_eq "U-neg-midprose"            "NOMATCH" "$(parse4 'please BACKGROUND :: x')"
assert_eq "U-neg-colon-norest"        "NOMATCH" "$(parse4 'BACKGROUND ::')"
assert_eq "U-neg-slash-norest"        "NOMATCH" "$(parse4 '/BACKGROUND')"
assert_eq "U-neg-slash-lower-tok"     "NOMATCH" "$(parse4 '/notUpper x')"
# arrow-form negatives: lowercase / no-trailing-space (no rest) / mid-prose /
# no-spaces-around-arrow / single-dash arrow-ish separators.
assert_eq "U-neg-arrow-lowercase"     "NOMATCH" "$(parse4 'background ---> x')"
assert_eq "U-neg-arrow-norest"        "NOMATCH" "$(parse4 'BACKGROUND --->')"
assert_eq "U-neg-arrow-midprose"      "NOMATCH" "$(parse4 'please BACKGROUND ---> x')"
assert_eq "U-neg-arrow-nospace"       "NOMATCH" "$(parse4 'BACKGROUND--->x')"
assert_eq "U-neg-arrow-onedash"       "NOMATCH" "$(parse4 'BACKGROUND -> x')"

# ──────────────────────────────────────────────────────────────────────────────
# UNIT — python-path ≡ awk-path (byte-identical) for every probe above
# ──────────────────────────────────────────────────────────────────────────────
echo "=== UNIT: python/awk parse-path parity ==="
PARITY_INPUTS=(
  'BACKGROUND :: do X'
  'DEFAULT::BACKGROUND :: do X'
  'MYNS::BACKGROUND :: do X'
  '/BACKGROUND do X'
  '/DEFAULT::BACKGROUND do X'
  '/MYNS::BACKGROUND do X'
  '/BACKGROUND please do the thing'
  '/BACKGROUND    do X'
  'background :: x'
  '/background x'
  'key: value'
  'Foo::Bar'
  'BACKGROUND::do X'
  'BACKGROUND: do X'
  'https://example.com/x'
  'please BACKGROUND :: x'
  'BACKGROUND ::'
  '/BACKGROUND'
  '/notUpper x'
  'BACKGROUND ---> do X'
  'DEFAULT::BACKGROUND ---> do X'
  'MYNS::BACKGROUND ---> do X'
  'BACKGROUND ---> please do the thing'
  'A :: B ---> C'
  'A ---> B :: C'
  'background ---> x'
  'BACKGROUND --->'
  'please BACKGROUND ---> x'
  'BACKGROUND--->x'
  'BACKGROUND -> x'
)
i=0
for inp in "${PARITY_INPUTS[@]}"; do
  i=$((i+1))
  py="$(parse4_python "$inp")"
  aw="$(parse4_awk "$inp")"
  assert_eq "U-parity-$(printf '%02d' "$i")" "$py" "$aw"
done

# ──────────────────────────────────────────────────────────────────────────────
# UNIT — escape (leading backslash) → literal, no expansion, BOTH form families
# ──────────────────────────────────────────────────────────────────────────────
echo "=== UNIT: escape ==="
ESC1="$(apx_expand_prompt '\BACKGROUND :: do X')"
assert_eq "U-escape-colon-verdict"  "escape"           "$(field "$ESC1" verdict)"
assert_eq "U-escape-colon-emitted"  "BACKGROUND :: do X" "$(field "$ESC1" emitted)"
ESC2="$(apx_expand_prompt '\DEFAULT::BACKGROUND :: do X')"
assert_eq "U-escape-nscolon-emit"   "DEFAULT::BACKGROUND :: do X" "$(field "$ESC2" emitted)"
ESC3="$(apx_expand_prompt '\/BACKGROUND do X')"
assert_eq "U-escape-slash-verdict"  "escape"           "$(field "$ESC3" verdict)"
assert_eq "U-escape-slash-emitted"  "/BACKGROUND do X" "$(field "$ESC3" emitted)"
ESC4="$(apx_expand_prompt '\/DEFAULT::BACKGROUND do X')"
assert_eq "U-escape-nsslash-emit"   "/DEFAULT::BACKGROUND do X" "$(field "$ESC4" emitted)"
ESC5="$(apx_expand_prompt '\BACKGROUND ---> do X')"
assert_eq "U-escape-arrow-verdict"  "escape"                  "$(field "$ESC5" verdict)"
assert_eq "U-escape-arrow-emitted"  "BACKGROUND ---> do X"    "$(field "$ESC5" emitted)"
ESC6="$(apx_expand_prompt '\DEFAULT::BACKGROUND ---> do X')"
assert_eq "U-escape-nsarrow-emit"   "DEFAULT::BACKGROUND ---> do X" "$(field "$ESC6" emitted)"

# ──────────────────────────────────────────────────────────────────────────────
# UNIT — unknown grammar-shaped token → ASK (names closest), no invented expansion
# ──────────────────────────────────────────────────────────────────────────────
echo "=== UNIT: unknown → ASK ==="
ASKC="$(apx_expand_prompt 'BACGROUND :: do X')"
assert_eq "U-unknown-colon-verdict" "ask"        "$(field "$ASKC" verdict)"
assert_eq "U-unknown-colon-closest" "BACKGROUND" "$(field "$ASKC" closest)"
assert_eq "U-unknown-colon-noexp"   ""           "$(field "$ASKC" expansion)"
ASKS="$(apx_expand_prompt '/BACGROUND do X')"
assert_eq "U-unknown-slash-verdict" "ask"        "$(field "$ASKS" verdict)"
assert_eq "U-unknown-slash-closest" "BACKGROUND" "$(field "$ASKS" closest)"
ASKA="$(apx_expand_prompt 'BACGROUND ---> do X')"
assert_eq "U-unknown-arrow-verdict" "ask"        "$(field "$ASKA" verdict)"
assert_eq "U-unknown-arrow-closest" "BACKGROUND" "$(field "$ASKA" closest)"
assert_eq "U-unknown-arrow-noexp"   ""           "$(field "$ASKA" expansion)"

# ──────────────────────────────────────────────────────────────────────────────
# E2E (expander) — every form expands to the SAME BACKGROUND expansion + residual
# ──────────────────────────────────────────────────────────────────────────────
echo "=== E2E: expander all 4 forms equivalent ==="
EXP_VERBATIM="$(apx_lookup_expansion BACKGROUND)"
for spec in \
  "form1|BACKGROUND :: do X" \
  "form2|DEFAULT::BACKGROUND :: do X" \
  "form3|/BACKGROUND do X" \
  "form4|/DEFAULT::BACKGROUND do X" \
  "form5|BACKGROUND ---> do X" \
  "form5ns|DEFAULT::BACKGROUND ---> do X" \
  ; do
  tag="${spec%%|*}"; prompt="${spec#*|}"
  J="$(apx_expand_prompt "$prompt")"
  assert_eq "E2E-$tag-verdict"   "expand"        "$(field "$J" verdict)"
  assert_eq "E2E-$tag-action"    "BACKGROUND"    "$(field "$J" action)"
  assert_eq "E2E-$tag-residual"  "do X"          "$(field "$J" residual)"
  assert_eq "E2E-$tag-expansion" "$EXP_VERBATIM" "$(field "$J" expansion)"
  # emitted = expansion + blank line + residual
  assert_eq "E2E-$tag-emitted"   "$EXP_VERBATIM"$'\n\n'"do X" "$(field "$J" emitted)"
done
# namespace + form fields are reported correctly per form
assert_eq "E2E-form1-ns"   "DEFAULT" "$(field "$(apx_expand_prompt 'BACKGROUND :: x')" namespace)"
assert_eq "E2E-form2-ns"   "DEFAULT" "$(field "$(apx_expand_prompt 'DEFAULT::BACKGROUND :: x')" namespace)"
assert_eq "E2E-form3-form" "slash"   "$(field "$(apx_expand_prompt '/BACKGROUND x')" form)"
assert_eq "E2E-form1-form" "colon"   "$(field "$(apx_expand_prompt 'BACKGROUND :: x')" form)"
assert_eq "E2E-form5-form" "arrow"   "$(field "$(apx_expand_prompt 'BACKGROUND ---> x')" form)"
assert_eq "E2E-form5ns-ns" "MYNS"    "$(field "$(apx_expand_prompt 'MYNS::BACKGROUND ---> x')" namespace)"

# ── REMINDER action — registered; all 5 forms resolve to the SAME expansion ──
echo "=== E2E: REMINDER action, all forms equivalent ==="
REM_VERBATIM="$(apx_lookup_expansion REMINDER)"
assert_eq "REM-registered-nonempty" "yes" "$([ -n "$REM_VERBATIM" ] && echo yes || echo no)"
for spec in \
  "colon|REMINDER :: check the D3 audio fix" \
  "nscolon|DEFAULT::REMINDER :: check the D3 audio fix" \
  "slash|/REMINDER check the D3 audio fix" \
  "nsslash|/DEFAULT::REMINDER check the D3 audio fix" \
  "arrow|REMINDER ---> check the D3 audio fix" \
  "nsarrow|DEFAULT::REMINDER ---> check the D3 audio fix" \
  ; do
  tag="${spec%%|*}"; prompt="${spec#*|}"
  J="$(apx_expand_prompt "$prompt")"
  assert_eq "REM-$tag-verdict"   "expand"        "$(field "$J" verdict)"
  assert_eq "REM-$tag-action"    "REMINDER"      "$(field "$J" action)"
  assert_eq "REM-$tag-residual"  "check the D3 audio fix" "$(field "$J" residual)"
  assert_eq "REM-$tag-expansion" "$REM_VERBATIM" "$(field "$J" expansion)"
done
# REMINDER expansion carries its verify-don't-assume core (no-guessing §11.4.6)
has_verify="no"; case "$REM_VERBATIM" in *'verify the ACTUAL current status from captured evidence'*) has_verify="yes" ;; esac
assert_eq "REM-expansion-verify-core" "yes" "$has_verify"
# REMINDER escape → literal (arrow form)
assert_eq "REM-escape-arrow" "REMINDER ---> x" "$(field "$(apx_expand_prompt '\REMINDER ---> x')" emitted)"

# ──────────────────────────────────────────────────────────────────────────────
# INTEGRATION — the real hook rewrites each of the 4 forms (additionalContext)
# ──────────────────────────────────────────────────────────────────────────────
echo "=== INTEGRATION: hook all 4 forms ==="
hook_ctx() {  # feed a prompt to the real hook, echo additionalContext
  printf '{"prompt":"%s"}' "$1" | bash "$HOOK" 2>/dev/null \
    | apx__json_get "$(cat 2>/dev/null)" >/dev/null 2>&1 || true
  printf '{"prompt":"%s"}' "$1" | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
for spec in \
  "form1|BACKGROUND :: build the parser" \
  "form2|DEFAULT::BACKGROUND :: build the parser" \
  "form3|/BACKGROUND build the parser" \
  "form4|/DEFAULT::BACKGROUND build the parser" \
  "form5|BACKGROUND ---> build the parser" \
  "form5ns|DEFAULT::BACKGROUND ---> build the parser" \
  ; do
  tag="${spec%%|*}"; prompt="${spec#*|}"
  CTX="$(hook_ctx "$prompt")"
  {
    printf 'CASE: HOOK-%s\nINPUT: %s\nADDITIONAL_CONTEXT:\n%s\n' "$tag" "$prompt" "$CTX"
  } > "$EVID_DIR/HOOK-$tag.txt"
  # must mention the system + carry the registry-verbatim expansion fragment + the residual
  has_sys="no"; case "$CTX" in *'Action-Prefix System §11.4.140'*) has_sys="yes" ;; esac
  has_exp="no"; case "$CTX" in *'subagents-driven development approach'*) has_exp="yes" ;; esac
  has_task="no"; case "$CTX" in *'build the parser'*) has_task="yes" ;; esac
  assert_eq "HOOK-$tag-has-system"   "yes" "$has_sys"
  assert_eq "HOOK-$tag-has-expansion" "yes" "$has_exp"
  assert_eq "HOOK-$tag-has-task"     "yes" "$has_task"
done
# hook no-op on escape (slash) + no-op on ordinary prompt
ESC_OUT="$(printf '{"prompt":"\\\\/BACKGROUND x"}' | bash "$HOOK" 2>/dev/null)"
assert_eq "HOOK-escape-slash-noop" "" "$ESC_OUT"
NOOP_OUT="$(printf '{"prompt":"just an ordinary prompt"}' | bash "$HOOK" 2>/dev/null)"
assert_eq "HOOK-ordinary-noop" "" "$NOOP_OUT"

# ──────────────────────────────────────────────────────────────────────────────
# DETERMINISM (§11.4.50) — N=3 identical sha256 of the full expand JSON per form
# ──────────────────────────────────────────────────────────────────────────────
echo "=== DETERMINISM: N=$N_ITER per form ==="
sha() { sha256sum 2>/dev/null | cut -d' ' -f1 || shasum -a 256 | cut -d' ' -f1; }
for spec in \
  "form1|BACKGROUND :: do X" \
  "form2|DEFAULT::BACKGROUND :: do X" \
  "form3|/BACKGROUND do X" \
  "form4|/DEFAULT::BACKGROUND do X" \
  "form5|BACKGROUND ---> do X" \
  "form5-reminder|REMINDER ---> do X" \
  ; do
  tag="${spec%%|*}"; prompt="${spec#*|}"
  first_hash=""
  consistent="yes"
  k=0
  while [ "$k" -lt "$N_ITER" ]; do
    k=$((k+1))
    h="$(apx_expand_prompt "$prompt" | sha)"
    if [ -z "$first_hash" ]; then first_hash="$h"
    elif [ "$h" != "$first_hash" ]; then consistent="no"; fi
  done
  printf 'CASE: DET-%s\nITERS: %s\nHASH: %s\nCONSISTENT: %s\n' \
    "$tag" "$N_ITER" "$first_hash" "$consistent" > "$EVID_DIR/DET-$tag.txt"
  assert_eq "DET-$tag-consistent" "yes" "$consistent"
done

# ──────────────────────────────────────────────────────────────────────────────
echo "===================================================================="
echo "RESULT: PASS=$PASS FAIL=$FAIL  (evidence: $EVID_DIR)"
if [ "$FAIL" -ne 0 ]; then
  echo "FAILED CASES:$FAILED_CASES"
  exit 1
fi
echo "ALL PASS"
exit 0
