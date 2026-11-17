#!/usr/bin/env bash
# test_no_real_tools.sh (round 5, review R4-5): no Jev test may resolve a real llmctl or claude-providers by itself.
# The round-4 suite found a real llmctl through the user database (the home directory of the current uid) and a project
# path under it, and ran `require-validated` against the operator's own llmctl state. The only way a test may reach a
# real binary is an explicit variable the operator sets (REAL_LLMCTL_BIN); every other lookup must end at a stub.
#   N1 STATIC: no non-comment line of tests/jev/*.sh (this file excluded) contains a user-database home lookup, a path
#      under a Projects directory, or the path of a real llmctl / claude-providers binary.
#      CONTROLS: a planted file with such a line gives exactly one hit; a clean file gives none.
#   N2 DYNAMIC: test_review_fixes_r5.sh runs with a decoy user database (a getent stub that maps the current uid to a
#      decoy home) and tripwire binaries at every real-tool location of that home and on PATH. No tripwire may fire.
#      CONTROL: a passwd-derived call of the decoy path DOES fire the tripwire (the decoy is visible to the lookup).
# NRT_SUITE_DIR selects the suite under test (a RED run points it at the tests/jev directory of the pre-fix tree).
# Evidence class: gate-logic / unit (§11.4.289(C)(2)): stubs and tripwires only; no real tool is ever run.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq python3 grep; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
SUITE="${NRT_SUITE_DIR:-$HERE}"
PAT='getent[[:space:]]+passwd|/Projects/|submodules/llmctl/bin/llmctl|claude_toolkit/bin/claude-providers'

# scan <file...> -> the non-comment lines that match PAT (file:line:text)
scan() { grep -HnE "$PAT" "$@" 2>/dev/null | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true; }   # -H: file:line: even for one file

# ---- N1 static ----------------------------------------------------------------------------------------------------------
make_fixture_env n1
files=(); for f in "$SUITE"/*.sh; do [ "${f##*/}" = test_no_real_tools.sh ] || files+=("$f"); done
assert_ne "0" "${#files[@]}" "N1 the scan sees the suite files (${#files[@]})"
hits="$(scan "${files[@]}")"
if [ -z "$hits" ]; then ok "N1 no test resolves a real tool by itself"; else fail "N1 real-tool lookup in a test: $(printf '%s' "$hits" | cut -c1-300)"; fi
# shellcheck disable=SC2016  # the planted file holds a literal $(...) on purpose
printf '%s\n' '#!/bin/sh' '# a comment that names getent passwd is not a hit' 'x="$(getent passwd 0 | cut -d: -f6)/Projects/x"' > "$T/planted.sh"
printf '%s\n' '#!/bin/sh' 'echo clean' > "$T/clean.sh"
assert_eq "1" "$(scan "$T/planted.sh" | grep -c .)" "N1 CONTROL: a planted lookup line is found (comment lines are not)"
assert_eq "0" "$(scan "$T/clean.sh" | grep -c .)" "N1 CONTROL: a clean file gives no hit"

# ---- N2 dynamic ---------------------------------------------------------------------------------------------------------
DH="$T/decoy_home"; DB="$T/decoy_bin"; TRIP="$T/trip.log"; mkdir -p "$DB"; : > "$TRIP"
# shellcheck disable=SC2016  # $0 and $* belong to the generated tripwire script
trip() { mkdir -p "${1%/*}"; printf '#!/bin/sh\nprintf "TRIP %%s %%s\\n" "$0" "$*" >> %q\nexit 0\n' "$TRIP" > "$1"; chmod +x "$1"; }
for p in Projects/catalogizer/constitution/submodules/llmctl/bin/llmctl Projects/constitution/submodules/llmctl/bin/llmctl \
         Projects/claude_toolkit/bin/claude-providers Projects/catalogizer/constitution/submodules/claude_toolkit/bin/claude-providers \
         .local/bin/llmctl .local/bin/claude-providers; do trip "$DH/$p"; done
trip "$DB/llmctl"; trip "$DB/claude-providers"
# shellcheck disable=SC2016  # $1, $2 and $(id ...) belong to the generated getent stub
printf '#!/bin/sh\nif [ "$1" = passwd ] && [ "$2" = "$(id -u)" ]; then echo "decoy:x:$(id -u):$(id -g)::%s:/bin/sh"; exit 0; fi\nexit 2\n' "$DH" > "$DB/getent"
chmod +x "$DB/getent"
# CONTROL: the decoy is what a user-database lookup sees
# shellcheck disable=SC2030,SC2031  # the decoy PATH is meant for this subshell only
( PATH="$DB:$PATH"; "$(getent passwd "$(id -u)" | cut -d: -f6)/Projects/catalogizer/constitution/submodules/llmctl/bin/llmctl" control ) >/dev/null 2>&1
assert_contains "$TRIP" "TRIP $DH/Projects/catalogizer/constitution/submodules/llmctl/bin/llmctl control" "N2 CONTROL: a lookup through the user database reaches the decoy tripwire"
: > "$TRIP"
out="$T/r5.out"
# shellcheck disable=SC2031  # PATH here is the parent PATH plus the decoy dir, set for this one command
env -u REAL_LLMCTL_BIN PATH="$DB:$PATH" HOME="$DH" TMPDIR="$T" bash "$SUITE/test_review_fixes_r5.sh" > "$out" 2>&1; rc=$?
if [ -s "$TRIP" ]; then fail "N2 a real-tool location was executed by test_review_fixes_r5.sh: $(head -3 "$TRIP" | tr '\n' ' ')"
else ok "N2 test_review_fixes_r5.sh executed no real-tool location (decoy user database, tripwires on PATH and in the home)"; fi
assert_contains "$out" "skip - I5-1 real pinned llmctl not named" "N2 without REAL_LLMCTL_BIN the real-binary check is an honest SKIP"
assert_rc 0 "$rc" "N2 test_review_fixes_r5.sh passes under the decoy environment"

# ---- N3 dynamic (round 6, review R5-11) ----------------------------------------------------------------------------------
# test_gate_pairs.sh (and through it the four gate mutation tests) runs with the same decoy user database and tripwires
# first on PATH, with no JEV_LLMCTL_BIN from the caller: no tripwire may fire (the round-5 detection mutation test fell
# back to the PATH llmctl, `decide status --json`, once per run). CONTROL: the detection gate on an empty record with no
# named llmctl DOES reach the PATH tripwire, so the tripwire sees the fallback the fix removes.
GATES_UT="$(cd "$SUITE/../.." && pwd)/scripts/gates"
: > "$TRIP"
env -u REAL_LLMCTL_BIN -u JEV_LLMCTL_BIN PATH="$DB:$PATH" HOME="$DH" TMPDIR="$T" bash "$SUITE/test_gate_pairs.sh" > "$T/gp.out" 2>&1; rc=$?
if [ -s "$TRIP" ]; then fail "N3 test_gate_pairs.sh executed a real-tool location: $(head -3 "$TRIP" | tr '\n' ' ')"
else ok "N3 test_gate_pairs.sh (four gate pairs and their mutation tests) executed no real-tool location"; fi
assert_rc 0 "$rc" "N3 test_gate_pairs.sh passes under the decoy environment"
: > "$TRIP"
jq '.endpoints=[] | .reason="nothing running" | .capacity={"instances":0,"decision_instances":0,"parallel_total":0}' \
  "$GATES_UT/fixtures/jev/evidence/jev-detection.json" > "$T/empty.json"
env -u JEV_LLMCTL_BIN PATH="$DB:$PATH" HOME="$DH" TMPDIR="$T" HELIX_TEST_MODE=1 JEV_DETECTION_FILE="$T/empty.json" \
  JEV_EVIDENCE_WINDOW_START=1759999000 JEV_FIXTURE_ROOT="$GATES_UT/fixtures/jev" bash "$GATES_UT/cm_jev_detection.sh" >/dev/null 2>&1
assert_contains "$TRIP" "TRIP $DB/llmctl decide status" "N3 CONTROL: the detection gate's PATH fallback reaches the tripwire when no llmctl is named"
finish
