#!/usr/bin/env bash
# tests/action_prefix/test_subsystem_shortcuts.sh
#
# §11.4.140 sub-system-shortcut extension (2026-07-14) — runtime functional test
# suite. Complements the pre-build gate (scripts/gates/cm_subsystem_shortcuts.sh)
# + its paired §1.1 mutation meta-test with a captured-evidence runtime layer
# (§11.4.4(b) / §11.4.5 / §11.4.69 / §11.4.107 — every PASS cites real output).
#
# Drives the REAL library apx_expand_prompt against a controlled temp fixture
# project root (deterministic §11.4.50 — HELIX_PROJECT_ROOT pins the discovery
# graph) + the REAL registry `subsystems:` catalogue, asserting:
#   UNIT   — a NAMED catalogue token (HELIXQA / HXOTA) resolves to a sub-system
#            across all 5 grammar forms (kind=subsystem); an auto-DISCOVERED
#            submodule token resolves; behavioral-action PRECEDENCE preserved;
#            unknown → ASK; lowercase → NOOP (grammar honoured at runtime);
#            escape → literal.
#   FAN-OUT — duplicate checkouts of the SAME submodule (same URL) collapse to
#            ONE sub-system (both paths listed in the expansion).
#   AMBIG  — two submodules yielding a COLLIDING abbreviation ⇒ that abbreviation
#            does NOT resolve (§11.4.6 no-guessing) → falls to ASK.
#   DET    — §11.4.50: each expand JSON hashed N=3, identical.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash tests/action_prefix/test_subsystem_shortcuts.sh
#   AB_N_ITER=3 bash tests/action_prefix/test_subsystem_shortcuts.sh
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   AB_N_ITER (optional, default 3) — determinism iteration count (§11.4.50).
#   Requires python3 (+ PyYAML) — the sub-system tier is python-dependent by
#   design; if absent the suite SKIPs-with-reason (§11.4.3) with a clear exit.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Captured evidence under qa-results/action_prefix/<run-id>/ (input→output per
#   case). Exit 0 iff ALL cases PASS; non-zero on any FAIL.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates a temp fixture project root (trap-cleaned) + evidence under
#   qa-results/ (gitignored). Read-only on the real lib/registry. No device, no
#   network, no governance-file edit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   scripts/action_prefix_lib.sh, python3 (+ PyYAML), jq preferred / sed fallback.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (mandate + sub-system extension), §11.4.27 (test-type coverage),
#   §11.4.50 (determinism), §11.4.67 (sh -n + bash -n clean), §11.4.69 (captured
#   evidence), §11.4.6 (no-guessing — ambiguous/action-collide/lowercase → no
#   expansion), §11.4.28/§11.4.177 (decoupled engine — fixture-driven discovery).
#
# Classification: universal (§11.4.17)

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)"
LIB="$ROOT/scripts/action_prefix_lib.sh"

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "SKIP: sub-system tier requires python3 + PyYAML (§11.4.3 topology SKIP-with-reason)."
  echo "SKIP-REASON: python3/PyYAML absent — the behavioral-action tier is unaffected."
  exit 0
fi

# shellcheck source=/dev/null
. "$LIB"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"
EVID_DIR="$ROOT/qa-results/action_prefix/$RUN_ID"
mkdir -p "$EVID_DIR"
N_ITER="${AB_N_ITER:-3}"

# ── Deterministic fixture project root (§11.4.50) ────────────────────────────
FIX="$(mktemp -d "${TMPDIR:-/tmp}/subsys_fixture.XXXXXX")"
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT INT TERM
cat > "$FIX/.gitmodules" <<'GM'
[submodule "foo_widget"]
	path = tools/foo_widget
	url = git@github.com:vasic-digital/foo-widget.git
[submodule "foo_widget_dup"]
	path = vendor/foo_widget
	url = git@github.com:vasic-digital/foo-widget.git
[submodule "alpha_beta"]
	path = a/alpha_beta
	url = git@github.com:vasic-digital/alpha-beta.git
[submodule "alpha_bravo"]
	path = b/alpha_bravo
	url = git@github.com:vasic-digital/alpha-bravo.git
GM
export HELIX_PROJECT_ROOT="$FIX"

PASS=0
FAIL=0
FAILED_CASES=""

assert_eq() {
  local id="$1" exp="$2" act="$3"
  { printf 'CASE: %s\nEXPECT: [%s]\nACTUAL: [%s]\n' "$id" "$exp" "$act"; } > "$EVID_DIR/$id.txt"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$id" "$EVID_DIR/$id.txt"
  else
    FAIL=$((FAIL+1)); FAILED_CASES="$FAILED_CASES $id"
    printf 'FAIL: %s\n  EXPECT [%s]\n  ACTUAL [%s]\n' "$id" "$exp" "$act"
  fi
}
jget() { apx__json_get "$1" "$2"; }
# vk <prompt> → "verdict|kind"
vk() { local j; j="$(apx_expand_prompt "$1")"; printf '%s|%s' "$(jget "$j" verdict)" "$(jget "$j" kind)"; }

# ── UNIT: named-catalogue token, all 5 forms ────────────────────────────────
echo "=== UNIT: named-catalogue sub-system (HELIXQA / HXOTA), all 5 forms ==="
assert_eq "S-cat-form1-colon"   "expand|subsystem" "$(vk 'HELIXQA :: run the bank')"
assert_eq "S-cat-form2-nscolon" "expand|subsystem" "$(vk 'DEFAULT::HELIXQA :: run the bank')"
assert_eq "S-cat-form3-slash"   "expand|subsystem" "$(vk '/HELIXQA run the bank')"
assert_eq "S-cat-form4-nsslash" "expand|subsystem" "$(vk '/DEFAULT::HELIXQA run the bank')"
assert_eq "S-cat-form5-arrow"   "expand|subsystem" "$(vk 'HELIXQA ---> run the bank')"
assert_eq "S-cat-alias-hxota"   "expand|subsystem" "$(vk 'HXOTA ---> add resume support')"
# action + residual reported correctly
J="$(apx_expand_prompt 'HELIXQA :: run the bank')"
assert_eq "S-cat-action-field"  "HELIXQA"       "$(jget "$J" action)"
assert_eq "S-cat-residual"      "run the bank"  "$(jget "$J" residual)"
# expansion is a real sub-system context (names the display + §11.4.28)
exp_has="no"; case "$(jget "$J" expansion)" in *'incorporated sub-system'*'§11.4.28'*) exp_has="yes" ;; esac
assert_eq "S-cat-expansion-shape" "yes" "$exp_has"

# ── UNIT: auto-discovered submodule token (from the fixture graph) ──────────
echo "=== UNIT: auto-discovered submodule token (FOO_WIDGET) ==="
assert_eq "S-disc-name"   "expand|subsystem" "$(vk 'FOO_WIDGET :: build it')"
assert_eq "S-disc-arrow"  "expand|subsystem" "$(vk 'FOO_WIDGET ---> build it')"
assert_eq "S-disc-slash"  "expand|subsystem" "$(vk '/FOO_WIDGET build it')"

# ── FAN-OUT: duplicate copies of the SAME submodule collapse to ONE ─────────
echo "=== FAN-OUT: duplicate checkouts collapse to one sub-system ==="
FE="$(jget "$(apx_expand_prompt 'FOO_WIDGET :: x')" expansion)"
has_p1="no"; case "$FE" in *'tools/foo_widget'*) has_p1="yes" ;; esac
has_p2="no"; case "$FE" in *'vendor/foo_widget'*) has_p2="yes" ;; esac
assert_eq "S-fanout-both-paths-listed" "yesyes" "${has_p1}${has_p2}"

# ── AMBIG: colliding abbreviation does NOT resolve (§11.4.6) ────────────────
echo "=== AMBIG: colliding abbreviation → ASK (no guess) ==="
# alpha_beta + alpha_bravo both derive abbreviation AB → dropped → ASK
assert_eq "S-ambig-AB-asks"        "ask|action"       "$(vk 'AB :: do something')"
# but each FULL name still resolves uniquely
assert_eq "S-ambig-alpha-beta"     "expand|subsystem" "$(vk 'ALPHA_BETA :: do X')"
assert_eq "S-ambig-alpha-bravo"    "expand|subsystem" "$(vk 'ALPHA_BRAVO :: do X')"

# ── PRECEDENCE + grammar honour + escape ────────────────────────────────────
echo "=== PRECEDENCE + grammar honour + escape ==="
assert_eq "S-prec-background-action" "expand|action" "$(vk 'BACKGROUND :: do X')"
assert_eq "S-prec-reminder-action"   "expand|action" "$(vk 'REMINDER ---> check the fix')"
assert_eq "S-unknown-asks"           "ask|action"    "$(vk 'ZZUNKNOWNZZ :: do X')"
assert_eq "S-lowercase-noop"         "noop|action"   "$(vk 'helixqa :: do X')"
assert_eq "S-lowercase-disc-noop"    "noop|action"   "$(vk 'foo_widget :: do X')"
assert_eq "S-escape-literal"         "HELIXQA :: do X" "$(jget "$(apx_expand_prompt '\HELIXQA :: do X')" emitted)"
# stacked outer sub-system + inner action nests
STK="$(jget "$(apx_expand_prompt 'FOO_WIDGET :: BACKGROUND :: fix the bug')" emitted)"
stk_ok="no"; case "$STK" in *'sub-system'*'subagents-driven development approach'*'fix the bug'*) stk_ok="yes" ;; esac
assert_eq "S-stacked-subsystem-then-action" "yes" "$stk_ok"

# ── DETERMINISM (§11.4.50) — N iterations identical sha256 ──────────────────
echo "=== DETERMINISM: N=$N_ITER per case ==="
sha() { sha256sum 2>/dev/null | cut -d' ' -f1 || shasum -a 256 | cut -d' ' -f1; }
for spec in "cat|HELIXQA :: run the bank" "disc|FOO_WIDGET ---> build it" "ambig|AB :: x"; do
  tag="${spec%%|*}"; prompt="${spec#*|}"; first=""; consistent="yes"; k=0
  while [ "$k" -lt "$N_ITER" ]; do
    k=$((k+1)); h="$(apx_expand_prompt "$prompt" | sha)"
    if [ -z "$first" ]; then first="$h"; elif [ "$h" != "$first" ]; then consistent="no"; fi
  done
  printf 'CASE: DET-%s\nITERS: %s\nHASH: %s\nCONSISTENT: %s\n' "$tag" "$N_ITER" "$first" "$consistent" > "$EVID_DIR/DET-$tag.txt"
  assert_eq "S-det-$tag-consistent" "yes" "$consistent"
done

echo "===================================================================="
echo "RESULT: PASS=$PASS FAIL=$FAIL  (evidence: $EVID_DIR)"
if [ "$FAIL" -ne 0 ]; then
  echo "FAILED CASES:$FAILED_CASES"; exit 1
fi
echo "ALL PASS"
exit 0
