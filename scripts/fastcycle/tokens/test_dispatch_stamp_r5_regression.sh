#!/usr/bin/env bash
# test_dispatch_stamp_r5_regression.sh -- T048/US1 slice S8 (independent
# Opus-xhigh review, 2026-10-03) regression guard for a LIVE PRODUCTION BUG
# in `constitution/scripts/release_prefix.sh`'s `_hrp_project_root()`.
#
# THE BUG (confirmed live before fixing, §11.4.199 exact-reproduction-
# sequence): `_hrp_project_root()`'s PRIMARY mechanism ran
# `git rev-parse --show-toplevel` in the CALLING PROCESS's ambient cwd --
# genuinely CWD-dependent in two distinct, reproducible ways:
#   (1) `constitution/` in this real deployment is itself a nested git
#       submodule with its OWN `.git`. Running `git rev-parse
#       --show-toplevel` from ANYWHERE inside `constitution/` (which is
#       exactly where `dispatch_stamp.sh` -- the real caller -- lives, and
#       therefore exactly where an invoking hook/caller's cwd may happen to
#       be) returns the SUBMODULE's own toplevel (".../constitution")
#       rather than the consuming project's real root, so `.env`'s
#       HELIX_RELEASE_PREFIX (="atmosphere") is never found there and the
#       prefix silently degrades to snake_case("constitution") = "constitution"
#       -> a 3-letter derived ticket prefix of "CON", never "ATM".
#   (2) From a directory with NO git repository at all (e.g. /tmp), the OLD
#       fallback computed only ONE level up from release_prefix.sh's own
#       directory ("$self_dir/.."), which for this file's real deployed
#       location (constitution/scripts/release_prefix.sh) resolves to
#       "constitution/" -- one level short of the real project root, same
#       wrong "CON" result.
# Consequence (live, reproduced below): a correctly-tagged dispatch whose
# description carries a genuine `item=ATM-NNNN` token is WRONGLY REFUSED by
# dispatch_stamp.sh's GUARD mode (exit 2 instead of exit 0), and its
# --extract-item-id EXTRACTION mode silently loses the attribution (prints
# empty instead of the real id) -- purely because of the invoking PROCESS's
# current working directory at the moment dispatch_stamp.sh happens to run,
# which is never something a caller/hook controls. This is exactly the
# §11.4.199 "deviating repro proves nothing, use the EXACT reported
# sequence" class: the defect is invisible from the repo root (the most
# common invocation cwd), which is why it shipped unnoticed.
#
# THE FIX (round 1): `_hrp_project_root()` was rewritten to resolve root
# ANCHORED TO THE SCRIPT'S OWN FILE LOCATION via `${BASH_SOURCE[0]}`,
# mirroring the ALREADY-ESTABLISHED precedent in this exact codebase,
# `constitution/scripts/fastcycle/timing/fc_timer.sh`'s own CANDIDATE
# FINGERPRINT RESOLUTION header ("deliberately ANCHORED TO THIS FILE'S OWN
# PATH, not the caller's current working directory") -- a FIXED
# two-levels-up computation (release_prefix.sh lives at
# <project-root>/constitution/scripts/release_prefix.sh) instead of an
# ambient-cwd `git rev-parse --show-toplevel` call.
#
# THE FIX (round 2, supersedes round 1, same batch's S8 remediation): an
# independent Opus-xhigh review found round 1's FIXED two-levels-up
# computation itself CWD-of-a-different-kind-dependent -- it is correct
# ONLY for the EMBEDDED layout (constitution/ nested two levels under a
# consuming project's root) and silently WRONG for the equally-documented
# STANDALONE layout (constitution/ cloned as its own top-level repo, see
# case (5) below). Round 2 keeps the §11.4.6 "anchor to this file's own
# location, never the caller's ambient cwd" PRINCIPLE round 1 established
# (that part of round 1 was correct and is NOT reverted) but replaces the
# fixed directory-count arithmetic with `git -C "$self_dir"
# --show-superproject-working-tree` (embedded) falling back to
# `--show-toplevel` (standalone) falling back to the ORIGINAL pre-round-1
# one-level-up no-git fallback -- see release_prefix.sh's own
# `_hrp_project_root()` header for the full account.
#
# THIS FILE proves, end-to-end, through the REAL dispatch_stamp.sh GUARD +
# --extract-item-id pipeline (never a reimplementation/mock of either
# release_prefix.sh's or dispatch_stamp.sh's own logic -- §11.4.240
# producer != verifier, §11.4.245 oracle independence: the oracle here is
# simply "does the SAME real payload, run from 4 different real
# directories, produce the SAME real extracted id and the SAME real GUARD
# verdict" -- a structural invariant, not a re-derivation of either tool's
# internals) that a well-formed `item=ATM-NNNN` dispatch is extracted and
# allowed IDENTICALLY regardless of the invoking process's cwd, across:
#   (1) the repository root (the baseline that always worked, even
#       pre-fix -- this is the scenario the bug was invisible from);
#   (2) inside the `constitution/` git submodule itself (the git-
#       submodule-toplevel-boundary defect, class (1) above);
#   (3) a directory nested further inside the submodule
#       (constitution/scripts/fastcycle/tests/ -- the exact directory
#       T020's own test, test_token_attribution_red.sh, lives in). T020
#       was NOT modified with any companion directory-dependence
#       assertion in this batch (its only diff right now is an UNRELATED
#       concurrent fix, S9's "PART F" item=<prefix> decoupling work) --
#       the honest basis for citing it here is a ONE-TIME empirical
#       observation, confirmed by this file's own author before writing
#       this comment: running T020 from the repo root vs. from
#       constitution/ produces the SAME pass=78 fail=0 SUMMARY (the
#       per-line PASS messages differ only in an incidental randomized
#       tmp-dir path embedded by mktemp, never in pass/fail outcome).
#       That is reassuring context, NOT a standing guard -- it is a
#       single observation taken once, not a regression test T020 itself
#       carries, and it is NOT evidence that T020 ever exercised the
#       release_prefix.sh bug this file's own cases A/B/C below prove;
#   (4) a directory with NO git repository at all (/tmp -- the
#       no-git-at-all fallback defect, class (2) above);
#   (5) (round 2, S8 remediation, independent Opus-xhigh NO-GO F1) a
#       freshly-created, genuinely STANDALONE scratch git repo mimicking
#       `constitution/`'s own on-disk shape (<repo>/scripts/
#       release_prefix.sh, its OWN `.env`, no parent/superproject at
#       all) -- the DOCUMENTED but previously untested "constitution/
#       used as its own top-level repo" layout (see `constitution/
#       .env.example`'s own header example, "HelixConstitution" ->
#       "helix_constitution", and this file's own `Usage:` block), which
#       the round-1 fix (a fixed "two levels up from this file's own
#       directory") silently broke: it resolved ONE level ABOVE a
#       standalone clone instead of the clone's own root, reading that
#       clone's `.env` never and printing the CONTAINING directory's
#       name instead of the clone's own -- verified live (§11.4.199)
#       before writing the round-2 fix in release_prefix.sh (this same
#       batch): the round-1 code printed the scratch harness's own
#       enclosing directory name from inside a repo named
#       "HelixConstitution" with its own `.env`, never
#       "helix_constitution".
#
# Producer != Verifier (§11.4.240): this file is a fix-pass deliverable,
# itself subject to a SEPARATE, later, independent §11.4.209 Opus-xhigh
# review before being trusted -- its author never self-certifies it as
# that review.
#
# Usage:  bash constitution/scripts/fastcycle/tokens/test_dispatch_stamp_r5_regression.sh
# Exit 0 = all cases pass (CWD-independence genuinely holds, in BOTH the
# embedded and standalone layouts); exit 1 = one or more cases diverged.
set -u

# F2 remediation (independent Opus-xhigh review, 2026-10-03): every case
# below exercises root-resolution logic that `HELIX_RELEASE_PREFIX` (tier 1,
# env-authoritative) SHORT-CIRCUITS entirely -- if that var happened to be
# set in the ambient shell BEFORE this script ran (a leaked export from the
# harness, CI, or an interactive shell), every case would silently pass
# unconditionally on that leaked value WITHOUT ever reaching
# `_hrp_project_root()`, the directory-dependent code this whole file exists
# to exercise -- a test that would pass identically against the OLD BUGGY
# release_prefix.sh. Verified live before relying on the unset below: with
# `HELIX_RELEASE_PREFIX=atmosphere` exported and the PRE-F1 round-1-broken
# release_prefix.sh restored, running it from /tmp printed "atmosphere" (the
# correct value) -- i.e. the leaked env var alone made broken code LOOK
# correct. The two lines immediately below close that hole, and the
# control-needle assertion immediately after PROVES the closure is real
# (removing the `unset` line would make the needle itself report FAIL,
# confirmed live before trusting it, per §11.4.201(7)(b)).
unset HELIX_RELEASE_PREFIX HELIX_PROJECT_ROOT 2>/dev/null || true

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

echo "-- control needle: HELIX_RELEASE_PREFIX / HELIX_PROJECT_ROOT genuinely unset before exercising directory-dependent resolution --"
if [ -n "${HELIX_RELEASE_PREFIX+x}" ]; then
  bad "HELIX_RELEASE_PREFIX is still SET ('${HELIX_RELEASE_PREFIX:-}') -- tier-1 env short-circuit would mask every case below, proving nothing"
else
  ok "HELIX_RELEASE_PREFIX is genuinely unset (checked via \${VAR+x} presence-test, not merely empty-string)"
fi
if [ -n "${HELIX_PROJECT_ROOT+x}" ]; then
  bad "HELIX_PROJECT_ROOT is still SET ('${HELIX_PROJECT_ROOT:-}') -- the F1 override tier would mask the git-resolution logic below"
else
  ok "HELIX_PROJECT_ROOT is genuinely unset (checked via \${VAR+x} presence-test, not merely empty-string)"
fi
if [ "$FAIL" -gt 0 ]; then
  echo "  ABORT: the unset above did not take effect (or this needle was removed/bypassed) -- every result below would be meaningless; refusing to proceed rather than report a false PASS (§11.4.201 conservative-safe default)"
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/dispatch_stamp.sh"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"
RELEASE_PREFIX="$REPO_ROOT/constitution/scripts/release_prefix.sh"

echo "T048/US1 S8 regression guard: release_prefix.sh / dispatch_stamp.sh CWD-independence"
echo "tool:            $TOOL"
echo "release_prefix:  $RELEASE_PREFIX"
echo

if [ ! -f "$TOOL" ] || [ ! -f "$RELEASE_PREFIX" ]; then
  echo "  FAIL  precondition: $TOOL or $RELEASE_PREFIX missing"
  exit 1
fi

# A well-formed, real-shaped dispatch payload carrying a genuine
# item=ATM-9042 token immediately after the §11.4.182 label (the exact
# reproduction the reviewer captured).
PAYLOAD='{"tool_name":"Agent","tool_input":{"description":"(T1/main - claude5 - sonnet - high) item=ATM-9042 test"}}'

# The 4-directory table the reviewer's own reproduction used, verified live
# as real, existing, reachable directories on this checkout before relying
# on any of them (§11.4.273 control needle: no case silently no-ops because
# its directory does not exist).
DIR_ROOT="$REPO_ROOT"
DIR_SUBMODULE="$REPO_ROOT/constitution"
DIR_NESTED="$REPO_ROOT/constitution/scripts/fastcycle/tests"
DIR_NOGIT="/tmp"

echo "-- control needle: all 4 target directories genuinely exist --"
for d in "$DIR_ROOT" "$DIR_SUBMODULE" "$DIR_NESTED" "$DIR_NOGIT"; do
  if [ -d "$d" ]; then
    ok "directory exists: $d"
  else
    bad "directory MISSING: $d -- cannot run the case for it, fixture is broken"
  fi
done

# control needle: /tmp is genuinely outside any git repository (the
# no-git-at-all case this table is supposed to exercise) -- never assumed.
echo
echo "-- control needle: /tmp is genuinely not inside a git repository --"
if (cd "$DIR_NOGIT" && git rev-parse --show-toplevel >/dev/null 2>&1); then
  bad "/tmp unexpectedly resolves as a git repository on this host -- the no-git case this table relies on is not actually exercised; re-pick a genuinely non-git scratch directory"
else
  ok "/tmp genuinely has no git repository (git rev-parse --show-toplevel fails there, confirmed live)"
fi

# control needle: constitution/ is genuinely its OWN, nested git boundary
# distinct from the superproject root -- the exact class-(1) defect
# scenario -- never assumed.
echo
echo "-- control needle: constitution/ is genuinely its own, nested git toplevel, distinct from the superproject root --"
SUBMODULE_TOPLEVEL="$(cd "$DIR_SUBMODULE" && git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$SUBMODULE_TOPLEVEL" ] && [ "$SUBMODULE_TOPLEVEL" != "$DIR_ROOT" ]; then
  ok "constitution/'s own 'git rev-parse --show-toplevel' ('$SUBMODULE_TOPLEVEL') genuinely differs from the superproject root ('$DIR_ROOT') -- the submodule-boundary scenario is real on this checkout, not assumed"
else
  bad "constitution/'s own git-toplevel ('$SUBMODULE_TOPLEVEL') did not diverge from the superproject root ('$DIR_ROOT') -- this fixture's premise does not hold on this checkout; re-investigate before trusting the result below"
fi

# run_case <label> <dir> -- runs BOTH dispatch_stamp.sh --extract-item-id
# AND plain dispatch_stamp.sh (GUARD mode) against the SAME real payload
# from the given real cwd, returning "extracted|guard_exit".
run_case() {
  local dir="$2" id rc
  id="$(cd "$dir" && printf '%s' "$PAYLOAD" | bash "$TOOL" --extract-item-id)"
  (cd "$dir" && printf '%s' "$PAYLOAD" | bash "$TOOL" >/dev/null 2>&1)
  rc=$?
  printf '%s|%s' "$id" "$rc"
}

echo
echo "-- A. identical extraction + GUARD verdict across all 4 real invocation directories --"
RESULT_ROOT="$(run_case "root" "$DIR_ROOT")"
RESULT_SUBMODULE="$(run_case "constitution" "$DIR_SUBMODULE")"
RESULT_NESTED="$(run_case "nested-under-submodule" "$DIR_NESTED")"
RESULT_NOGIT="$(run_case "no-git (/tmp)" "$DIR_NOGIT")"

printf '  repo root:                result=%s\n' "$RESULT_ROOT"
printf '  constitution/:            result=%s\n' "$RESULT_SUBMODULE"
printf '  constitution/.../tests/:  result=%s\n' "$RESULT_NESTED"
printf '  /tmp:                     result=%s\n' "$RESULT_NOGIT"

WANT="ATM-9042|0"
if [ "$RESULT_ROOT" = "$WANT" ]; then
  ok "repo root: extracted+guard = '$WANT' (the always-worked baseline)"
else
  bad "repo root: got '$RESULT_ROOT', want '$WANT'"
fi
if [ "$RESULT_SUBMODULE" = "$WANT" ]; then
  ok "constitution/ (nested git-submodule toplevel): extracted+guard = '$WANT' (R5 fix: previously degraded to the submodule's own basename-derived prefix, BLOCKING a correctly-tagged dispatch)"
else
  bad "constitution/ (nested git-submodule toplevel): got '$RESULT_SUBMODULE', want '$WANT' -- the CWD-dependent submodule-boundary defect has returned"
fi
if [ "$RESULT_NESTED" = "$WANT" ]; then
  ok "constitution/scripts/fastcycle/tests/ (nested further, same submodule): extracted+guard = '$WANT' (the exact directory T020's own test lives in)"
else
  bad "constitution/scripts/fastcycle/tests/: got '$RESULT_NESTED', want '$WANT' -- the CWD-dependent submodule-boundary defect has returned"
fi
if [ "$RESULT_NOGIT" = "$WANT" ]; then
  ok "/tmp (no git repository at all): extracted+guard = '$WANT' (R5 fix: previously the one-level-short self-dir fallback also mis-resolved to 'constitution/')"
else
  bad "/tmp (no git repository at all): got '$RESULT_NOGIT', want '$WANT' -- the CWD-dependent no-git fallback defect has returned"
fi

# B. release_prefix.sh itself, called directly (not through dispatch_stamp.sh
# at all), resolves IDENTICALLY from all 4 directories -- isolates the fix
# to its actual owning file, independent of dispatch_stamp.sh's own
# (already-correct, BASH_SOURCE-anchored) path-to-release_prefix.sh
# resolution.
echo
echo "-- B. release_prefix.sh resolves the IDENTICAL prefix directly, from all 4 directories --"
RP_ROOT="$(cd "$DIR_ROOT" && bash "$RELEASE_PREFIX")"
RP_SUBMODULE="$(cd "$DIR_SUBMODULE" && bash "$RELEASE_PREFIX")"
RP_NESTED="$(cd "$DIR_NESTED" && bash "$RELEASE_PREFIX")"
RP_NOGIT="$(cd "$DIR_NOGIT" && bash "$RELEASE_PREFIX")"
printf '  repo root:               %s\n' "$RP_ROOT"
printf '  constitution/:           %s\n' "$RP_SUBMODULE"
printf '  constitution/.../tests/: %s\n' "$RP_NESTED"
printf '  /tmp:                    %s\n' "$RP_NOGIT"
if [ -n "$RP_ROOT" ] && [ "$RP_ROOT" = "$RP_SUBMODULE" ] && [ "$RP_SUBMODULE" = "$RP_NESTED" ] && [ "$RP_NESTED" = "$RP_NOGIT" ]; then
  ok "release_prefix.sh prints the SAME non-empty prefix ('$RP_ROOT') from every one of the 4 real directories"
else
  bad "release_prefix.sh prefix diverged by invocation directory: root='$RP_ROOT' constitution='$RP_SUBMODULE' nested='$RP_NESTED' nogit='$RP_NOGIT'"
fi

# C. STANDALONE layout (F1, S8 remediation round-2, independent Opus-xhigh
# review 2026-10-03): `constitution/` is NOT only ever embedded two levels
# under a consuming project -- `constitution/.env.example`'s own header
# ("the HelixConstitution repo itself" -> "helix_constitution") and this
# very file's `release_prefix.sh`'s own `Usage:` block both document a
# SECOND, STANDALONE layout: constitution/ cloned and used AS its own
# top-level repo. The round-1 fix (a fixed "two levels up from this file's
# own directory") was correct for the embedded case covered by sections
# A/B above but SILENTLY WRONG for this one -- it resolves ONE level ABOVE
# a standalone clone (the clone's own CONTAINING directory) instead of the
# clone's own root, so that clone's own `.env` is never read and the
# resolved prefix is the basename of whatever directory happens to CONTAIN
# the clone, not the clone's own name.
#
# A fresh, genuinely standalone scratch git repo is built here (its own
# `scripts/release_prefix.sh` -- a real COPY of the file under test, never
# a reimplementation, §11.4.240 producer != verifier -- its own `.env`, and
# deliberately NO parent/superproject of any kind) and CONTROL-NEEDLED
# (§11.4.201(7)(b)) to confirm it is genuinely standalone before trusting
# any result from it, then release_prefix.sh is invoked from INSIDE it.
echo
echo "-- C. STANDALONE layout: constitution/'s OWN top-level-repo use case --"
STANDALONE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_standalone_fixture.XXXXXX")"
STANDALONE_DIR="$STANDALONE_ROOT/HelixConstitutionStandaloneFixture"
mkdir -p "$STANDALONE_DIR/scripts"
cp "$RELEASE_PREFIX" "$STANDALONE_DIR/scripts/release_prefix.sh"
(
  cd "$STANDALONE_DIR" \
    && git init -q \
    && git config user.email "r5-fixture@example.invalid" \
    && git config user.name "r5-fixture"
) >/dev/null 2>&1
printf 'HELIX_RELEASE_PREFIX=helix_standalone_fixture_r5_expected\n' > "$STANDALONE_DIR/.env"

cleanup_standalone_fixture() { rm -rf "$STANDALONE_ROOT"; }
trap cleanup_standalone_fixture EXIT

if [ ! -d "$STANDALONE_DIR/.git" ] || [ ! -f "$STANDALONE_DIR/.env" ] || [ ! -f "$STANDALONE_DIR/scripts/release_prefix.sh" ]; then
  bad "standalone fixture setup failed -- $STANDALONE_DIR missing .git/.env/scripts/release_prefix.sh, cannot run case C"
else
  # control needle: the fixture is genuinely standalone -- NOT nested
  # inside any superproject, and genuinely its OWN git toplevel -- never
  # assumed (§11.4.201(7)(b); mirrors the control needles above for the
  # embedded-layout directories).
  FIXTURE_SUPERPROJECT="$(cd "$STANDALONE_DIR" && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  FIXTURE_TOPLEVEL="$(cd "$STANDALONE_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"
  FIXTURE_TOPLEVEL_REAL="$(cd "$FIXTURE_TOPLEVEL" 2>/dev/null && pwd || true)"
  STANDALONE_DIR_REAL="$(cd "$STANDALONE_DIR" && pwd)"
  if [ -z "$FIXTURE_SUPERPROJECT" ] && [ -n "$FIXTURE_TOPLEVEL_REAL" ] && [ "$FIXTURE_TOPLEVEL_REAL" = "$STANDALONE_DIR_REAL" ]; then
    ok "fixture is genuinely standalone: no superproject ('$FIXTURE_SUPERPROJECT'), own git toplevel == its own directory ('$FIXTURE_TOPLEVEL_REAL')"
  else
    bad "fixture is NOT genuinely standalone (superproject='$FIXTURE_SUPERPROJECT' toplevel='$FIXTURE_TOPLEVEL_REAL' vs dir='$STANDALONE_DIR_REAL') -- this case's premise does not hold on this host, re-investigate before trusting case C's result below"
  fi

  STANDALONE_RESULT="$(cd "$STANDALONE_DIR" && bash scripts/release_prefix.sh)"
  printf '  standalone fixture result: %s\n' "$STANDALONE_RESULT"
  if [ "$STANDALONE_RESULT" = "helix_standalone_fixture_r5_expected" ]; then
    ok "standalone layout: release_prefix.sh resolves ITS OWN repo's .env prefix ('helix_standalone_fixture_r5_expected') -- F1's superproject-vs-toplevel split correctly falls through to case 2 (own git toplevel) here, never case 1 (no superproject exists to resolve)"
  else
    bad "standalone layout: got '$STANDALONE_RESULT', want 'helix_standalone_fixture_r5_expected' -- the F1 standalone-layout regression has returned (round-1's fixed-two-levels-up code printed the fixture's CONTAINING directory's name instead, confirmed live before this fix: '$(basename "$STANDALONE_ROOT")')"
  fi
fi

# D. UNREGISTERED-NESTED-CONSTITUTION layout (N1, independent Opus-xhigh
# review of S8's own round-2 fix, follow-up polish round, 2026-10-03):
# `constitution/` may have its OWN `.git` (so neither case 1's
# `--show-superproject-working-tree` NOR a registered-gitlink check ever
# fires) while still being genuinely NESTED two levels under an intended
# parent project -- the parent just never ran a formal `git submodule
# add`. Before this fix, `_hrp_project_root()`'s case 2
# (`--show-toplevel`) returned constitution's OWN root unconditionally
# in this shape, silently degrading the resolved prefix to
# snake_case("constitution") exactly like the pre-S8 defect this file's
# cases A/B/C already guard -- just via a DIFFERENT precondition (no
# superproject relationship at all, vs. a wrong-toplevel git boundary).
#
# A fresh scratch fixture is built here: a PARENT directory carrying its
# OWN `.env` (the real evidence the fix looks for) containing a NESTED
# `constitution/` directory that is its OWN, independently-`git init`'d
# repository (never a registered submodule of the parent -- confirmed by
# a control needle below, mirroring case C's own standalone-fixture
# control-needle discipline) with a real COPY of release_prefix.sh under
# test (never a reimplementation, §11.4.240 producer != verifier).
echo
echo "-- D. UNREGISTERED-NESTED-CONSTITUTION layout: a parent project's own .env / .gitmodules evidence is preferred over the narrower nested-repo toplevel --"
D_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_unregistered_nested_fixture.XXXXXX")"
D_PARENT="$D_ROOT/parent_project"
D_CONSTITUTION="$D_PARENT/constitution"
mkdir -p "$D_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d-fixture@example.invalid" \
    && git config user.name "r5-d-fixture"
) >/dev/null 2>&1
printf 'HELIX_RELEASE_PREFIX=parent_project_r5_expected\n' > "$D_PARENT/.env"
cleanup_d_fixture() { rm -rf "$D_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture' EXIT

if [ ! -d "$D_CONSTITUTION/.git" ] || [ ! -f "$D_PARENT/.env" ] || [ ! -f "$D_CONSTITUTION/scripts/release_prefix.sh" ]; then
  bad "D fixture setup failed -- $D_CONSTITUTION missing .git, or $D_PARENT missing .env, or scripts/release_prefix.sh missing, cannot run case D"
else
  # control needle: this nested constitution/ is genuinely UNREGISTERED
  # -- it is its own git toplevel (same class as case C's standalone
  # check) AND, unlike case C, it is genuinely nested two levels under a
  # real parent directory that is NOT itself a git repository at all
  # (the parent was never `git init`'d) -- never assumed.
  D_TOPLEVEL="$(cd "$D_CONSTITUTION" && git rev-parse --show-toplevel 2>/dev/null || true)"
  D_SUPERPROJECT="$(cd "$D_CONSTITUTION" && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  D_TOPLEVEL_REAL="$(cd "$D_TOPLEVEL" 2>/dev/null && pwd || true)"
  D_CONSTITUTION_REAL="$(cd "$D_CONSTITUTION" && pwd)"
  D_PARENT_REAL="$(cd "$D_PARENT" && pwd)"
  if [ -z "$D_SUPERPROJECT" ] && [ -n "$D_TOPLEVEL_REAL" ] && [ "$D_TOPLEVEL_REAL" = "$D_CONSTITUTION_REAL" ] && [ "$D_TOPLEVEL_REAL" != "$D_PARENT_REAL" ]; then
    ok "D fixture precondition is genuinely real: constitution/ has no superproject ('$D_SUPERPROJECT'), its own git toplevel is itself ('$D_TOPLEVEL_REAL'), and that differs from the real parent directory ('$D_PARENT_REAL') that carries the .env evidence -- the unregistered-nested scenario is real on this fixture, not assumed"
  else
    bad "D fixture is NOT genuinely unregistered-nested (superproject='$D_SUPERPROJECT' toplevel='$D_TOPLEVEL_REAL' constitution='$D_CONSTITUTION_REAL' parent='$D_PARENT_REAL') -- this case's premise does not hold, re-investigate before trusting case D's result below"
  fi

  D_RESULT="$(cd "$D_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  unregistered-nested fixture result: %s\n' "$D_RESULT"
  if [ "$D_RESULT" = "parent_project_r5_expected" ]; then
    ok "N1: an unregistered nested constitution/ repo resolves the REAL parent project's .env prefix ('parent_project_r5_expected') via the new .env-evidence heuristic, rather than silently degrading to its own basename-derived prefix ('constitution')"
  else
    bad "N1 regression: got '$D_RESULT', want 'parent_project_r5_expected' -- the unregistered-nested-constitution heuristic has regressed (pre-fix behaviour returns the nested repo's own snake_case basename, 'constitution', confirmed live before landing this fix)"
  fi

  # D-negative-control (§11.4.201(1) false-positive guard): remove the
  # .env evidence and confirm a GENUINELY standalone nested repo (no
  # evidence of an intended parent at all) is NOT falsely widened --
  # it must still resolve to its own root, exactly as case C's
  # standalone layout does.
  rm -f "$D_PARENT/.env"
  D_NEGCTRL_RESULT="$(cd "$D_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  negative-control (no parent evidence) result: %s\n' "$D_NEGCTRL_RESULT"
  if [ "$D_NEGCTRL_RESULT" = "constitution" ]; then
    ok "negative control: with NO parent-project evidence at all, the heuristic correctly does NOT widen -- still resolves to the nested repo's own standalone prefix ('constitution'), proving N1's fix is not a false-positive-prone over-widening"
  else
    bad "negative-control regression: got '$D_NEGCTRL_RESULT', want 'constitution' -- N1's heuristic is now falsely widening even without real parent-project evidence, a new false-positive this fix must not introduce"
  fi

  # D-gitmodules-variant: the SAME scenario but with a `.gitmodules`
  # entry naming "constitution" as a submodule path instead of a `.env`
  # file -- the task's OTHER named evidence source -- and no `.env` at
  # all, so a successful resolve here proves the `.gitmodules` branch
  # is independently load-bearing, not merely redundant with the `.env`
  # branch already proven above.
  cat > "$D_PARENT/.gitmodules" <<'GITMODULES_EOF'
[submodule "constitution"]
	path = constitution
	url = git@example.invalid:org/constitution.git
GITMODULES_EOF
  D_GITMODULES_RESULT="$(cd "$D_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  .gitmodules-only evidence result: %s\n' "$D_GITMODULES_RESULT"
  if [ "$D_GITMODULES_RESULT" = "parent_project" ]; then
    ok "N1 .gitmodules branch: with ONLY a .gitmodules entry naming 'constitution' as a submodule path (no .env), the heuristic still prefers the real parent directory, deriving its snake_case basename ('parent_project') -- the .gitmodules evidence path is independently load-bearing"
  else
    bad "N1 .gitmodules branch regression: got '$D_GITMODULES_RESULT', want 'parent_project' -- the .gitmodules-entry evidence path is not taking effect"
  fi
fi

# D2-D5 -- B1 remediation (round-4 independent Opus-xhigh review, 2026-10-03,
# finding B1 + I3): the N1 widen heuristic above was found too permissive on
# BOTH its evidence branches -- it treated ANY readable `.env` (even one
# carrying NO `HELIX_RELEASE_PREFIX=` assignment at all) as sufficient
# evidence, and treated ANY `.gitmodules` entry naming "constitution" as
# sufficient even when the directory being examined is NOT itself named
# "constitution". Each scenario below is one of the reviewer's OWN named
# adversarial reproductions (§11.4.199 exact-reproduction-sequence),
# proven to NOT widen against the FIXED release_prefix.sh, each paired
# (D2/D3) with a mutation-discrimination proof (§11.4.194(6)(d)) that the
# SAME fixture WOULD incorrectly widen if the corresponding fix were
# reverted to its pre-B1 permissive shape -- demonstrating these negative
# controls are genuinely load-bearing, not vacuously true (the exact I3
# finding: a reviewer-loosened `.gitmodules` grep stayed undetected by the
# pre-existing suite because nothing exercised the substring-collision or
# irrelevant-content shapes).
#
# mutate_release_prefix.py <src> <dst> <kind> -- generates an exact-text-
# substitution mutated COPY of release_prefix.sh (never a hand-written
# reimplementation, §11.4.240 producer != verifier), reverting ONE of the
# two B1 evidence-tightenings back to its pre-fix permissive shape:
#   env                -- the `.env` content-verification
#                         (_hrp_from_env_file) reverted to a bare
#                         file-existence check.
#   gitmodules         -- the anchored `path = constitution` exact-value
#                         grep reverted to a bare unanchored substring
#                         grep.
#
# I-A (round-3 independent Opus-xhigh review, 2026-10-03, verbatim):
# "4 reviewer-authored (S11.4.194(6)(d)) mutations of the B1 guard
# survive the r5 suite's existing fixtures: dropping the .gitmodules
# regex's trailing $, dropping its leading anchor, and two ways of
# loosening the HELIX_RELEASE_PREFIX evidence check (bare
# grep-for-the-var-name; grep-for-key-only). The SOURCE fix itself
# resists all four when tested directly -- only the regression suite's
# OWN negative-control coverage has gaps." The four additional kinds
# below close exactly those four coverage gaps -- release_prefix.sh
# ITSELF is unchanged by this round (the review confirms it already
# resists all four):
#   gitmodules_trailing -- the SAME anchored `path = constitution` grep
#                         with ONLY its trailing `$` end-of-line anchor
#                         dropped (kept `^` + the literal prefix), so a
#                         value that STARTS with "constitution" but has
#                         a non-whitespace suffix (e.g.
#                         "constitution-extra") incorrectly matches.
#   gitmodules_leading  -- the SAME anchored grep with ONLY its leading
#                         `^` start-of-line anchor dropped (kept the
#                         trailing `$`), so "path = constitution" found
#                         as a MID-LINE substring (e.g. a key literally
#                         named "notpath") incorrectly matches.
#   env_bare_varname    -- the `_hrp_from_env_file()` call replaced with
#                         a bare, unanchored `grep -q
#                         'HELIX_RELEASE_PREFIX'` -- matches the var
#                         NAME appearing ANYWHERE in the file (e.g.
#                         inside a comment that never assigns it).
#   env_key_only        -- the `_hrp_from_env_file()` call replaced with
#                         a bare, unanchored `grep -q
#                         'HELIX_RELEASE_PREFIX='` -- matches the
#                         literal "KEY=" substring ANYWHERE in the file
#                         (e.g. inside a comment documenting a disabled
#                         assignment), never verifying it is a real,
#                         non-commented, line-start assignment.
MUT_GEN="$(mktemp "${TMPDIR:-/tmp}/mutate_release_prefix.XXXXXX.py")"
cat > "$MUT_GEN" <<'PYEOF'
import sys
src_path, dst_path, kind = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(src_path, encoding="utf-8").read()
ENV_OLD = '        if [ -n "$(_hrp_from_env_file "$parent_root/.env")" ]; then\n'
GITMODULES_OLD = (
    '        elif [ -f "$parent_root/.gitmodules" ] \\\n'
    "             && grep -Eq '^[[:space:]]*path[[:space:]]*=[[:space:]]*constitution[[:space:]]*$' \\\n"
    '                  "$parent_root/.gitmodules" 2>/dev/null; then\n'
)
BASENAME_OLD = '    if [ "$root_base" = "constitution" ]; then\n'
if kind == "env":
    OLD = ENV_OLD
    NEW = '        if [ -f "$parent_root/.env" ]; then\n'
elif kind == "gitmodules":
    OLD = GITMODULES_OLD
    NEW = (
        '        elif [ -f "$parent_root/.gitmodules" ] \\\n'
        "             && grep -q 'constitution' \\\n"
        '                  "$parent_root/.gitmodules" 2>/dev/null; then\n'
    )
elif kind == "gitmodules_trailing":
    OLD = GITMODULES_OLD
    NEW = (
        '        elif [ -f "$parent_root/.gitmodules" ] \\\n'
        "             && grep -Eq '^[[:space:]]*path[[:space:]]*=[[:space:]]*constitution[[:space:]]*' \\\n"
        '                  "$parent_root/.gitmodules" 2>/dev/null; then\n'
    )
elif kind == "gitmodules_leading":
    OLD = GITMODULES_OLD
    NEW = (
        '        elif [ -f "$parent_root/.gitmodules" ] \\\n'
        "             && grep -Eq '[[:space:]]*path[[:space:]]*=[[:space:]]*constitution[[:space:]]*$' \\\n"
        '                  "$parent_root/.gitmodules" 2>/dev/null; then\n'
    )
elif kind == "env_bare_varname":
    OLD = ENV_OLD
    NEW = '        if grep -q \'HELIX_RELEASE_PREFIX\' "$parent_root/.env" 2>/dev/null; then\n'
elif kind == "env_key_only":
    OLD = ENV_OLD
    NEW = '        if grep -q \'HELIX_RELEASE_PREFIX=\' "$parent_root/.env" 2>/dev/null; then\n'
elif kind == "basename_insert_before":
    # I-1 residual gap (round-6 independent Opus-xhigh review,
    # 2026-10-03, verbatim finding), SUPERSEDED round-7 (independent
    # Opus-xhigh review, 2026-10-03): round-6's companion
    # "basename_substring" kind (a case-insensitive SUBSTRING loosening,
    # implemented by LINE-EDITING the gate line itself via a replaced
    # `grep -qi` test) was REMOVED this round -- its D10 caller is gone,
    # replaced by the table-driven near-miss sweep below, whose
    # "basename_insert_casefold" kind (same elif-chain, further down)
    # covers the SAME case-insensitive-substring class via a STRICTLY
    # MORE GENERAL mechanism (nocasematch) that also closes the
    # case-fold-EXACT gap ("Constitution"/"CONSTITUTION") the old
    # line-editing kind could never represent. Keeping the old kind
    # defined with no caller would itself be exactly the round-6-
    # reviewer-flagged "dead code" class this same round's M2 finding
    # fixes elsewhere in this file -- so it is deleted, not merely
    # orphaned.
    #
    # This kind (basename_insert_before) remains as the table-driven
    # sweep's SUBSTRING-class representative (the LINE-PRESERVING
    # attack shape: a NEW case-SENSITIVE normalization statement
    # INSERTED immediately before the existing, UNTOUCHED exact-match
    # gate line, rather than editing that line's own text -- the gate
    # line itself is never edited, only a prior statement silently
    # rewrites $root_base to the literal "constitution" before the
    # still-textually-unchanged exact-match test ever runs, for ANY
    # basename that is a case-SENSITIVE substring/prefix/suffix match).
    #
    # This kind's own setup self-check is NOT brittle by the SAME text-
    # pin mechanism the round-5 reviewer flagged in the general
    # critique: `OLD` (the untouched gate line) is PRESERVED VERBATIM
    # inside `NEW` (as its trailing line), so the generic
    # `src.count(OLD) != 1` guard above still correctly validates the
    # PRE-mutation source (where OLD is genuinely unique) before this
    # kind's insertion-shaped NEW value is ever written -- it does not
    # rely on OLD's absence afterwards. The same self-check property
    # holds for every "basename_insert_*" kind below, by the identical
    # construction (OLD preserved verbatim as NEW's trailing line).
    OLD = BASENAME_OLD
    NEW = (
        '    case "$root_base" in *constitution*) root_base=constitution ;; esac\n'
        + BASENAME_OLD
    )
elif kind == "basename_insert_prefix":
    # I-1 residual gap (round-7 independent Opus-xhigh review,
    # 2026-10-03, verbatim finding): neither the substring-class kind
    # above nor the case-fold-class kind below discriminates a PREFIX
    # loosening -- a basename that merely STARTS WITH "constitution"
    # followed by one-or-more further characters (e.g.
    # "constitution-fork", "constitution.bak"), case-SENSITIVE, never
    # case-folded. This is the table-driven sweep's PREFIX-class
    # representative.
    OLD = BASENAME_OLD
    NEW = (
        '    case "$root_base" in constitution?*) root_base=constitution ;; esac\n'
        + BASENAME_OLD
    )
elif kind == "basename_insert_suffix":
    # I-1 residual gap (round-7 independent Opus-xhigh review,
    # 2026-10-03, verbatim finding): a basename that merely ENDS WITH
    # "constitution" (e.g. "my-constitution"), case-SENSITIVE, is a
    # genuinely distinct attack shape from both the substring kind above
    # (which also matches it, but does not ISOLATE the suffix-only
    # shape) and the prefix kind above (which does NOT match it, since
    # the string does not START with "constitution"). This is the
    # table-driven sweep's SUFFIX-class representative, via a case-
    # sensitive extended-regex end-anchor.
    OLD = BASENAME_OLD
    NEW = (
        '    if [[ "$root_base" =~ constitution$ ]]; then root_base=constitution; fi\n'
        + BASENAME_OLD
    )
elif kind == "basename_insert_casefold":
    # I-1 residual gap (round-7 independent Opus-xhigh review,
    # 2026-10-03, verbatim finding): a case-INSENSITIVE loosening via
    # `shopt -s nocasematch` rather than a line-edited `grep -qi` call
    # (the round-5/D10 mechanism this kind supersedes, see the removal
    # note on "basename_insert_before" above) -- this is STRICTLY MORE
    # GENERAL than a mere case-insensitive-substring loosening: it also
    # fires on a basename that is an EXACT case-fold match for
    # "constitution" (e.g. "Constitution", "CONSTITUTION"), since an
    # exact match is trivially also a substring match of itself. This
    # single kind is therefore the table-driven sweep's CASE-FOLD-class
    # representative, covering BOTH the case-insensitive-substring shape
    # (round-5/D10's original fixture, "HelixConstitution") AND the
    # case-fold-exact shape (round-6-reviewer-named mD gap,
    # "Constitution" / "CONSTITUTION") with one mechanism.
    OLD = BASENAME_OLD
    NEW = (
        '    shopt -s nocasematch; [[ $root_base == *constitution* ]] && root_base=constitution; shopt -u nocasematch\n'
        + BASENAME_OLD
    )
else:
    sys.stderr.write("mutate_release_prefix.py: unknown kind %r\n" % kind)
    sys.exit(2)
if src.count(OLD) != 1:
    sys.stderr.write("MUTATION_SETUP_FAILED matches=%d\n" % src.count(OLD))
    sys.exit(2)
open(dst_path, "w", encoding="utf-8").write(src.replace(OLD, NEW, 1))
PYEOF

# D2 (B1): a readable parent `.env` with CONTENT IRRELEVANT to
# HELIX_RELEASE_PREFIX (e.g. an unrelated API_KEY=... line, exactly the
# reviewer's reported shape) must NOT be treated as widening evidence.
echo
echo "-- D2 (B1): content-irrelevant parent .env does NOT widen --"
D2_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_b1_irrelevant_env_fixture.XXXXXX")"
D2_PARENT="$D2_ROOT/parent_irrelevant_env"
D2_CONSTITUTION="$D2_PARENT/constitution"
mkdir -p "$D2_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D2_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D2_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d2-fixture@example.invalid" \
    && git config user.name "r5-d2-fixture"
) >/dev/null 2>&1
printf 'API_KEY=unrelated_content_no_release_prefix_here\n' > "$D2_PARENT/.env"
cleanup_d2_fixture() { rm -rf "$D2_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture' EXIT

if [ ! -d "$D2_CONSTITUTION/.git" ] || [ ! -f "$D2_PARENT/.env" ]; then
  bad "D2 fixture setup failed -- cannot run the content-irrelevant-.env case"
else
  D2_RESULT="$(cd "$D2_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  content-irrelevant-.env fixture result: %s\n' "$D2_RESULT"
  if [ "$D2_RESULT" = "constitution" ]; then
    ok "B1: a parent .env with NO HELIX_RELEASE_PREFIX= assignment (file exists, content irrelevant) correctly does NOT widen -- stays 'constitution' (the pre-B1-fix bug treated ANY readable .env, regardless of content, as sufficient evidence)"
  else
    bad "B1 regression: got '$D2_RESULT', want 'constitution' -- the content-irrelevant-.env false-widen bug has returned"
  fi

  D2_MUT="$D2_ROOT/release_prefix_mut_env.sh"
  D2_MUT_SETUP_ERR="$(python3 "$MUT_GEN" "$RELEASE_PREFIX" "$D2_MUT" env 2>&1)"
  D2_MUT_SETUP_RC=$?
  if [ "$D2_MUT_SETUP_RC" -ne 0 ] || [ ! -f "$D2_MUT" ]; then
    bad "D2 mutation-discrimination setup failed (rc=$D2_MUT_SETUP_RC err=$D2_MUT_SETUP_ERR) -- cannot prove D2's negative control is discriminating; investigate before trusting the D2 result above as a genuine regression guard"
  else
    cp "$D2_MUT" "$D2_CONSTITUTION/scripts/release_prefix.sh"
    D2_MUT_RESULT="$(cd "$D2_CONSTITUTION" && bash scripts/release_prefix.sh)"
    cp "$RELEASE_PREFIX" "$D2_CONSTITUTION/scripts/release_prefix.sh"   # restore the real, unmutated file
    printf '  mutated (content-check reverted to bare existence) result: %s\n' "$D2_MUT_RESULT"
    if [ "$D2_MUT_RESULT" != "constitution" ]; then
      ok "D2 mutation-discrimination: the SAME content-irrelevant-.env fixture, run against a copy with the .env evidence check reverted to a bare file-existence test (the exact pre-B1-fix shape), DOES incorrectly widen ('$D2_MUT_RESULT') -- proving D2's negative control above is genuinely load-bearing, not vacuously true"
    else
      bad "D2 mutation-discrimination FAILED: the mutated (pre-B1-fix-shaped) copy did NOT widen against the SAME content-irrelevant-.env fixture ('$D2_MUT_RESULT') -- D2's negative control above cannot be trusted as a real regression guard against this specific loosening"
    fi
  fi
fi

# D3 (B1/I3): a `.gitmodules` entry naming "constitution" only as a
# SUBSTRING of a DIFFERENT path (e.g. `path = other/constitution-utils`,
# never the complete value "constitution") must NOT be treated as
# widening evidence -- the exact I3 reviewer-loosened-grep collision.
echo
echo "-- D3 (B1/I3): .gitmodules entry mentioning 'constitution' only as a substring of a different path does NOT widen --"
D3_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_b1_gitmodules_substring_fixture.XXXXXX")"
D3_PARENT="$D3_ROOT/parent_substring_gitmodules"
D3_CONSTITUTION="$D3_PARENT/constitution"
mkdir -p "$D3_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D3_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D3_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d3-fixture@example.invalid" \
    && git config user.name "r5-d3-fixture"
) >/dev/null 2>&1
cat > "$D3_PARENT/.gitmodules" <<'GITMODULES_D3_EOF'
[submodule "other"]
	path = other/constitution-utils
	url = git@example.invalid:org/constitution-utils.git
GITMODULES_D3_EOF
cleanup_d3_fixture() { rm -rf "$D3_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture' EXIT

if [ ! -d "$D3_CONSTITUTION/.git" ] || [ ! -f "$D3_PARENT/.gitmodules" ]; then
  bad "D3 fixture setup failed -- cannot run the .gitmodules-substring case"
else
  D3_RESULT="$(cd "$D3_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  .gitmodules-substring-only fixture result: %s\n' "$D3_RESULT"
  if [ "$D3_RESULT" = "constitution" ]; then
    ok "B1/I3: a .gitmodules entry naming 'constitution' only as a substring of a different path ('other/constitution-utils', never the exact value 'constitution') correctly does NOT widen -- stays 'constitution' (proves the real grep is value-anchored, not a substring match)"
  else
    bad "B1/I3 regression: got '$D3_RESULT', want 'constitution' -- the .gitmodules substring-collision false-widen bug has returned"
  fi

  D3_MUT="$D3_ROOT/release_prefix_mut_gitmodules.sh"
  D3_MUT_SETUP_ERR="$(python3 "$MUT_GEN" "$RELEASE_PREFIX" "$D3_MUT" gitmodules 2>&1)"
  D3_MUT_SETUP_RC=$?
  if [ "$D3_MUT_SETUP_RC" -ne 0 ] || [ ! -f "$D3_MUT" ]; then
    bad "D3 mutation-discrimination setup failed (rc=$D3_MUT_SETUP_RC err=$D3_MUT_SETUP_ERR) -- cannot prove D3's negative control is discriminating; investigate before trusting the D3 result above as a genuine regression guard"
  else
    cp "$D3_MUT" "$D3_CONSTITUTION/scripts/release_prefix.sh"
    D3_MUT_RESULT="$(cd "$D3_CONSTITUTION" && bash scripts/release_prefix.sh)"
    cp "$RELEASE_PREFIX" "$D3_CONSTITUTION/scripts/release_prefix.sh"   # restore the real, unmutated file
    printf '  mutated (anchored grep reverted to bare substring match) result: %s\n' "$D3_MUT_RESULT"
    if [ "$D3_MUT_RESULT" != "constitution" ]; then
      ok "D3 mutation-discrimination: the SAME .gitmodules-substring fixture, run against a copy with the anchored exact-value grep reverted to a bare unanchored 'grep -q constitution' (the exact I3 reviewer-mutation shape), DOES incorrectly widen ('$D3_MUT_RESULT') -- proving D3's negative control above is genuinely load-bearing, not vacuously true"
    else
      bad "D3 mutation-discrimination FAILED: the mutated (I3-reviewer-loosened-shaped) copy did NOT widen against the SAME .gitmodules-substring fixture ('$D3_MUT_RESULT') -- D3's negative control above cannot be trusted as a real regression guard against this specific loosening"
    fi
  fi
fi

# D6 (I-A, round-3 independent Opus-xhigh review, 2026-10-03): the
# .gitmodules anchored grep's TRAILING `$` anchor, dropped in isolation
# (keeping the leading `^` + literal-prefix portion intact) -- a value
# that STARTS with the literal word "constitution" but carries a
# non-whitespace SUFFIX (e.g. "constitution-extra", never the complete
# exact value "constitution") must NOT be treated as widening evidence.
# D3 above already proves the FULLY-unanchored substring-grep mutation
# is caught; this is the narrower, specifically-trailing-anchor-only
# loosening the reviewer separately named, which D3's own fixture
# ("other/constitution-utils", failing even the LEADING anchor) cannot
# discriminate -- a genuinely different, previously-uncovered mutation
# shape.
echo
echo "-- D6 (I-A): .gitmodules entry value starting with 'constitution' but carrying a non-whitespace suffix does NOT widen (trailing-anchor-drop mutation) --"
D6_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_ia_gitmodules_trailing_fixture.XXXXXX")"
D6_PARENT="$D6_ROOT/parent_trailing_gitmodules"
D6_CONSTITUTION="$D6_PARENT/constitution"
mkdir -p "$D6_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D6_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D6_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d6-fixture@example.invalid" \
    && git config user.name "r5-d6-fixture"
) >/dev/null 2>&1
cat > "$D6_PARENT/.gitmodules" <<'GITMODULES_D6_EOF'
[submodule "other"]
	path = constitution-extra
	url = git@example.invalid:org/constitution-extra.git
GITMODULES_D6_EOF
cleanup_d6_fixture() { rm -rf "$D6_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture' EXIT

if [ ! -d "$D6_CONSTITUTION/.git" ] || [ ! -f "$D6_PARENT/.gitmodules" ]; then
  bad "D6 fixture setup failed -- cannot run the .gitmodules-trailing-suffix case"
else
  D6_RESULT="$(cd "$D6_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  .gitmodules-trailing-suffix fixture result: %s\n' "$D6_RESULT"
  if [ "$D6_RESULT" = "constitution" ]; then
    ok "I-A: a .gitmodules entry whose value STARTS with 'constitution' but carries a non-whitespace suffix ('constitution-extra', never the complete exact value 'constitution') correctly does NOT widen -- stays 'constitution' (proves the real grep's trailing \$ end-anchor is genuinely load-bearing, not merely the leading ^ one D3 already covers)"
  else
    bad "I-A regression: got '$D6_RESULT', want 'constitution' -- the .gitmodules trailing-suffix false-widen bug has returned"
  fi

  D6_MUT="$D6_ROOT/release_prefix_mut_gitmodules_trailing.sh"
  D6_MUT_SETUP_ERR="$(python3 "$MUT_GEN" "$RELEASE_PREFIX" "$D6_MUT" gitmodules_trailing 2>&1)"
  D6_MUT_SETUP_RC=$?
  if [ "$D6_MUT_SETUP_RC" -ne 0 ] || [ ! -f "$D6_MUT" ]; then
    bad "D6 mutation-discrimination setup failed (rc=$D6_MUT_SETUP_RC err=$D6_MUT_SETUP_ERR) -- cannot prove D6's negative control is discriminating; investigate before trusting the D6 result above as a genuine regression guard"
  else
    cp "$D6_MUT" "$D6_CONSTITUTION/scripts/release_prefix.sh"
    D6_MUT_RESULT="$(cd "$D6_CONSTITUTION" && bash scripts/release_prefix.sh)"
    cp "$RELEASE_PREFIX" "$D6_CONSTITUTION/scripts/release_prefix.sh"   # restore the real, unmutated file
    printf '  mutated (trailing \$ anchor dropped) result: %s\n' "$D6_MUT_RESULT"
    if [ "$D6_MUT_RESULT" != "constitution" ]; then
      ok "D6 mutation-discrimination: the SAME .gitmodules-trailing-suffix fixture, run against a copy with ONLY the anchored grep's trailing \$ end-anchor dropped (the exact I-A reviewer-named mutation shape), DOES incorrectly widen ('$D6_MUT_RESULT') -- proving D6's negative control above is genuinely load-bearing, not vacuously true"
    else
      bad "D6 mutation-discrimination FAILED: the mutated (trailing-\$-dropped) copy did NOT widen against the SAME .gitmodules-trailing-suffix fixture ('$D6_MUT_RESULT') -- D6's negative control above cannot be trusted as a real regression guard against this specific loosening"
    fi
  fi
fi

# D7 (I-A, round-3 independent Opus-xhigh review, 2026-10-03): the
# .gitmodules anchored grep's LEADING `^` anchor, dropped in isolation
# (keeping the trailing `$` portion intact) -- "path = constitution"
# appearing as a MID-LINE substring of a DIFFERENT key (e.g. a line
# whose real key is "notpath", not "path") must NOT be treated as
# widening evidence. A genuinely different mutation shape than D3/D6
# above: without the `^` anchor, grep -E searches for the pattern
# ANYWHERE on the line, so "notpath = constitution" (the literal
# substring "path = constitution" embedded starting at offset 3) would
# incorrectly match.
echo
echo "-- D7 (I-A): .gitmodules entry whose real key merely ENDS WITH 'path' (not literally 'path') does NOT widen (leading-anchor-drop mutation) --"
D7_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_ia_gitmodules_leading_fixture.XXXXXX")"
D7_PARENT="$D7_ROOT/parent_leading_gitmodules"
D7_CONSTITUTION="$D7_PARENT/constitution"
mkdir -p "$D7_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D7_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D7_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d7-fixture@example.invalid" \
    && git config user.name "r5-d7-fixture"
) >/dev/null 2>&1
cat > "$D7_PARENT/.gitmodules" <<'GITMODULES_D7_EOF'
[submodule "weird"]
	notpath = constitution
GITMODULES_D7_EOF
cleanup_d7_fixture() { rm -rf "$D7_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture; cleanup_d7_fixture' EXIT

if [ ! -d "$D7_CONSTITUTION/.git" ] || [ ! -f "$D7_PARENT/.gitmodules" ]; then
  bad "D7 fixture setup failed -- cannot run the .gitmodules-mid-line-substring case"
else
  D7_RESULT="$(cd "$D7_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  .gitmodules-mid-line-substring fixture result: %s\n' "$D7_RESULT"
  if [ "$D7_RESULT" = "constitution" ]; then
    ok "I-A: a .gitmodules line whose real key is 'notpath' (NOT the literal key 'path') correctly does NOT widen even though 'path = constitution' appears as a mid-line substring -- stays 'constitution' (proves the real grep's leading ^ start-anchor is genuinely load-bearing)"
  else
    bad "I-A regression: got '$D7_RESULT', want 'constitution' -- the .gitmodules mid-line-substring false-widen bug has returned"
  fi

  D7_MUT="$D7_ROOT/release_prefix_mut_gitmodules_leading.sh"
  D7_MUT_SETUP_ERR="$(python3 "$MUT_GEN" "$RELEASE_PREFIX" "$D7_MUT" gitmodules_leading 2>&1)"
  D7_MUT_SETUP_RC=$?
  if [ "$D7_MUT_SETUP_RC" -ne 0 ] || [ ! -f "$D7_MUT" ]; then
    bad "D7 mutation-discrimination setup failed (rc=$D7_MUT_SETUP_RC err=$D7_MUT_SETUP_ERR) -- cannot prove D7's negative control is discriminating; investigate before trusting the D7 result above as a genuine regression guard"
  else
    cp "$D7_MUT" "$D7_CONSTITUTION/scripts/release_prefix.sh"
    D7_MUT_RESULT="$(cd "$D7_CONSTITUTION" && bash scripts/release_prefix.sh)"
    cp "$RELEASE_PREFIX" "$D7_CONSTITUTION/scripts/release_prefix.sh"   # restore the real, unmutated file
    printf '  mutated (leading ^ anchor dropped) result: %s\n' "$D7_MUT_RESULT"
    if [ "$D7_MUT_RESULT" != "constitution" ]; then
      ok "D7 mutation-discrimination: the SAME .gitmodules-mid-line-substring fixture, run against a copy with ONLY the anchored grep's leading ^ start-anchor dropped (the exact I-A reviewer-named mutation shape), DOES incorrectly widen ('$D7_MUT_RESULT') -- proving D7's negative control above is genuinely load-bearing, not vacuously true"
    else
      bad "D7 mutation-discrimination FAILED: the mutated (leading-^-dropped) copy did NOT widen against the SAME .gitmodules-mid-line-substring fixture ('$D7_MUT_RESULT') -- D7's negative control above cannot be trusted as a real regression guard against this specific loosening"
    fi
  fi
fi

# D8 (I-A, round-3 independent Opus-xhigh review, 2026-10-03): the `.env`
# evidence check's call to the real `_hrp_from_env_file()` parser,
# replaced with a BARE, UNANCHORED `grep -q 'HELIX_RELEASE_PREFIX'` --
# matching the var NAME appearing anywhere in the file, including inside
# a comment that documents the variable without ever assigning it (no
# `=` adjacent at all) -- must NOT be treated as widening evidence.
echo
echo "-- D8 (I-A): .env mentioning the variable NAME in prose (no '=' at all) does NOT widen (bare-grep-for-var-name mutation) --"
D8_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_ia_env_bare_varname_fixture.XXXXXX")"
D8_PARENT="$D8_ROOT/parent_bare_varname_env"
D8_CONSTITUTION="$D8_PARENT/constitution"
mkdir -p "$D8_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D8_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D8_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d8-fixture@example.invalid" \
    && git config user.name "r5-d8-fixture"
) >/dev/null 2>&1
printf '# This project does not set HELIX_RELEASE_PREFIX, see docs\nOTHER_VAR=value\n' > "$D8_PARENT/.env"
cleanup_d8_fixture() { rm -rf "$D8_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture; cleanup_d7_fixture; cleanup_d8_fixture' EXIT

if [ ! -d "$D8_CONSTITUTION/.git" ] || [ ! -f "$D8_PARENT/.env" ]; then
  bad "D8 fixture setup failed -- cannot run the bare-grep-for-var-name case"
else
  D8_RESULT="$(cd "$D8_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  bare-grep-for-var-name fixture result: %s\n' "$D8_RESULT"
  if [ "$D8_RESULT" = "constitution" ]; then
    ok "I-A: a parent .env that merely MENTIONS 'HELIX_RELEASE_PREFIX' in prose (a comment, never a real assignment, no '=' adjacent at all) correctly does NOT widen -- stays 'constitution' (proves the real check calls the full _hrp_from_env_file() parser, never a bare var-name grep)"
  else
    bad "I-A regression: got '$D8_RESULT', want 'constitution' -- the .env bare-var-name-mention false-widen bug has returned"
  fi

  D8_MUT="$D8_ROOT/release_prefix_mut_env_bare_varname.sh"
  D8_MUT_SETUP_ERR="$(python3 "$MUT_GEN" "$RELEASE_PREFIX" "$D8_MUT" env_bare_varname 2>&1)"
  D8_MUT_SETUP_RC=$?
  if [ "$D8_MUT_SETUP_RC" -ne 0 ] || [ ! -f "$D8_MUT" ]; then
    bad "D8 mutation-discrimination setup failed (rc=$D8_MUT_SETUP_RC err=$D8_MUT_SETUP_ERR) -- cannot prove D8's negative control is discriminating; investigate before trusting the D8 result above as a genuine regression guard"
  else
    cp "$D8_MUT" "$D8_CONSTITUTION/scripts/release_prefix.sh"
    D8_MUT_RESULT="$(cd "$D8_CONSTITUTION" && bash scripts/release_prefix.sh)"
    cp "$RELEASE_PREFIX" "$D8_CONSTITUTION/scripts/release_prefix.sh"   # restore the real, unmutated file
    printf '  mutated (bare grep-for-var-name) result: %s\n' "$D8_MUT_RESULT"
    if [ "$D8_MUT_RESULT" != "constitution" ]; then
      ok "D8 mutation-discrimination: the SAME bare-grep-for-var-name fixture, run against a copy with the _hrp_from_env_file() call reverted to a bare, unanchored 'grep -q HELIX_RELEASE_PREFIX' (the exact I-A reviewer-named mutation shape), DOES incorrectly widen ('$D8_MUT_RESULT') -- proving D8's negative control above is genuinely load-bearing, not vacuously true"
    else
      bad "D8 mutation-discrimination FAILED: the mutated (bare-var-name-grep-shaped) copy did NOT widen against the SAME fixture ('$D8_MUT_RESULT') -- D8's negative control above cannot be trusted as a real regression guard against this specific loosening"
    fi
  fi
fi

# D9 (I-A, round-3 independent Opus-xhigh review, 2026-10-03): the `.env`
# evidence check's call to the real `_hrp_from_env_file()` parser,
# replaced with a BARE, UNANCHORED `grep -q 'HELIX_RELEASE_PREFIX='` --
# matching the literal "KEY=" substring appearing anywhere in the file,
# including inside a comment documenting a DISABLED assignment (never a
# real, non-commented, line-start assignment) -- must NOT be treated as
# widening evidence. A genuinely different mutation shape than D8 above
# (D8's fixture carries no '=' at all, so it cannot discriminate this
# "grep-for-key-only" shape, which specifically requires a '=' to be
# present to even have a chance of matching).
echo
echo "-- D9 (I-A): .env with a commented-out 'KEY=value' assignment does NOT widen (grep-for-key-only mutation) --"
D9_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_ia_env_key_only_fixture.XXXXXX")"
D9_PARENT="$D9_ROOT/parent_key_only_env"
D9_CONSTITUTION="$D9_PARENT/constitution"
mkdir -p "$D9_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D9_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D9_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d9-fixture@example.invalid" \
    && git config user.name "r5-d9-fixture"
) >/dev/null 2>&1
printf '# old config: HELIX_RELEASE_PREFIX=disabled_value\nOTHER_VAR=value\n' > "$D9_PARENT/.env"
cleanup_d9_fixture() { rm -rf "$D9_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture; cleanup_d7_fixture; cleanup_d8_fixture; cleanup_d9_fixture' EXIT

if [ ! -d "$D9_CONSTITUTION/.git" ] || [ ! -f "$D9_PARENT/.env" ]; then
  bad "D9 fixture setup failed -- cannot run the grep-for-key-only case"
else
  D9_RESULT="$(cd "$D9_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  grep-for-key-only fixture result: %s\n' "$D9_RESULT"
  if [ "$D9_RESULT" = "constitution" ]; then
    ok "I-A: a parent .env whose ONLY 'HELIX_RELEASE_PREFIX=' occurrence is inside a comment documenting a DISABLED assignment ('# old config: HELIX_RELEASE_PREFIX=disabled_value', never a real line-start assignment) correctly does NOT widen -- stays 'constitution' (proves the real check calls the full _hrp_from_env_file() parser, never a bare key-only grep)"
  else
    bad "I-A regression: got '$D9_RESULT', want 'constitution' -- the .env commented-out-key-only false-widen bug has returned"
  fi

  D9_MUT="$D9_ROOT/release_prefix_mut_env_key_only.sh"
  D9_MUT_SETUP_ERR="$(python3 "$MUT_GEN" "$RELEASE_PREFIX" "$D9_MUT" env_key_only 2>&1)"
  D9_MUT_SETUP_RC=$?
  if [ "$D9_MUT_SETUP_RC" -ne 0 ] || [ ! -f "$D9_MUT" ]; then
    bad "D9 mutation-discrimination setup failed (rc=$D9_MUT_SETUP_RC err=$D9_MUT_SETUP_ERR) -- cannot prove D9's negative control is discriminating; investigate before trusting the D9 result above as a genuine regression guard"
  else
    cp "$D9_MUT" "$D9_CONSTITUTION/scripts/release_prefix.sh"
    D9_MUT_RESULT="$(cd "$D9_CONSTITUTION" && bash scripts/release_prefix.sh)"
    cp "$RELEASE_PREFIX" "$D9_CONSTITUTION/scripts/release_prefix.sh"   # restore the real, unmutated file
    printf '  mutated (grep-for-key-only) result: %s\n' "$D9_MUT_RESULT"
    if [ "$D9_MUT_RESULT" != "constitution" ]; then
      ok "D9 mutation-discrimination: the SAME grep-for-key-only fixture, run against a copy with the _hrp_from_env_file() call reverted to a bare, unanchored 'grep -q HELIX_RELEASE_PREFIX=' (the exact I-A reviewer-named mutation shape), DOES incorrectly widen ('$D9_MUT_RESULT') -- proving D9's negative control above is genuinely load-bearing, not vacuously true"
    else
      bad "D9 mutation-discrimination FAILED: the mutated (key-only-grep-shaped) copy did NOT widen against the SAME fixture ('$D9_MUT_RESULT') -- D9's negative control above cannot be trusted as a real regression guard against this specific loosening"
    fi
  fi
fi
# SWEEP (I-1 full remediation, round-7 independent Opus-xhigh review,
# 2026-10-03): D10 + D11 above (now REMOVED, replaced entirely by this one
# table-driven sweep) each closed exactly ONE near-miss basename shape the
# round-5/round-6 reviewers anticipated, with ONE matching mutant apiece.
# The SAME round-7 review additionally reproduced TWO further line-
# preserving mutants that survive ALL of D10+D11 combined, UNDETECTED
# (47/0, confirmed live before writing this sweep, §11.4.199):
#   mC (PREFIX):    `case "$root_base" in constitution?*) ...` widens on
#                    any basename STARTING WITH "constitution" plus 1+
#                    further characters (e.g. "constitution-fork",
#                    "constitution.bak").
#   mD (CASE-FOLD): `root_base="$(... tr upper lower ...)"` applied
#                    BEFORE the still-exact-match gate widens on any
#                    basename that is an EXACT case-fold match for
#                    "constitution" (e.g. "Constitution", "CONSTITUTION").
# Per §11.4.194(6)(d) (reviewer-authored mutations are necessary, never
# sufficient, on their own) and §11.4.201(1) (a guard is proven only
# against BOTH a golden-TRUE AND a golden-FALSE-with-carrier fixture),
# this sweep replaces the two standalone, single-shape D10/D11 cases with
# ONE TABLE-DRIVEN near-miss matrix spanning all FOUR attack classes the
# B1 basename gate's exact '=' comparison must resist -- SUBSTRING,
# PREFIX, SUFFIX, and CASE-FOLD -- plus two pure real-code safety rows
# (TRUNCATION, trailing WHITESPACE) that NO representative mutant below
# is expected to widen on, proving the mutants themselves are not
# over-broad (a mutant that widened on "constitutio" or "constitution "
# too would itself be a defective, overly-permissive negative control).
#
# Each row pins exactly ONE basename to, at most, ONE class-
# representative mutation kind (defined in the SAME shared $MUT_GEN
# generator used by every other case above -- never re-implemented,
# §11.4.240 producer != verifier) that MUST widen against it, while the
# REAL, unmutated code MUST NOT widen against ANY row. The table's
# "expect" column is the real basename-derived snake_case fallback each
# name genuinely resolves to -- VERIFIED LIVE (§11.4.6, never guessed)
# before writing these expectations, including the two rows where a
# capitalized or whitespace-padded name HAPPENS to snake-case to the
# literal string "constitution" too (never confused with an actual
# widen below, since a widen is distinguished by the DIFFERENT sentinel
# value "wrong_widen", not by this coincidental string collision):
#
#   row (basename)       expect               representative kind       attack class (what it closes)
#   my-constitution       my_constitution      basename_insert_suffix    SUFFIX (subsumes former D11)
#   xconstitutionx         xconstitutionx       basename_insert_before    SUBSTRING (isolates it uniquely --
#                                                                          not a prefix, not a suffix match)
#   HelixConstitution      helix_constitution   basename_insert_casefold  CASE-FOLD (subsumes former D10)
#   constitution-fork      constitution_fork    basename_insert_prefix    PREFIX (closes mC)
#   constitution.bak       constitution_bak     basename_insert_prefix    PREFIX (different separator)
#   Constitution           constitution         basename_insert_casefold  CASE-FOLD (closes mD)
#   CONSTITUTION           constitution         basename_insert_casefold  CASE-FOLD (closes mD, all-caps)
#   constitutio            constitutio          (none)                    TRUNCATION safety only
#   "constitution "        constitution         (none)                    trailing-WHITESPACE safety only
echo
echo "-- SWEEP (I-1 full remediation): table-driven near-miss basename matrix -- SUBSTRING / PREFIX / SUFFIX / CASE-FOLD attack classes, plus truncation + trailing-whitespace safety rows -- none widen on the real code, each class's representative mutant DOES widen on at least one row of that class --"
SWEEP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_i1_sweep_fixture.XXXXXX")"
cleanup_sweep_fixture() { rm -rf "$SWEEP_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture; cleanup_d7_fixture; cleanup_d8_fixture; cleanup_d9_fixture; cleanup_sweep_fixture' EXIT

SWEEP_NAME=(
  "my-constitution"
  "xconstitutionx"
  "HelixConstitution"
  "constitution-fork"
  "constitution.bak"
  "Constitution"
  "CONSTITUTION"
  "constitutio"
  "constitution "
)
SWEEP_EXPECT=(
  "my_constitution"
  "xconstitutionx"
  "helix_constitution"
  "constitution_fork"
  "constitution_bak"
  "constitution"
  "constitution"
  "constitutio"
  "constitution"
)
SWEEP_KIND=(
  "basename_insert_suffix"
  "basename_insert_before"
  "basename_insert_casefold"
  "basename_insert_prefix"
  "basename_insert_prefix"
  "basename_insert_casefold"
  "basename_insert_casefold"
  ""
  ""
)
SWEEP_CLASS=(
  "SUFFIX (subsumes the former D11 case)"
  "SUBSTRING (isolates it uniquely -- not a prefix, not a suffix match)"
  "CASE-FOLD (subsumes the former D10 case)"
  "PREFIX (closes mC)"
  "PREFIX (belt-and-suspenders, a different separator)"
  "CASE-FOLD (closes mD)"
  "CASE-FOLD (closes mD's class more thoroughly -- all-caps)"
  "none -- TRUNCATION real-code safety row only"
  "none -- trailing-WHITESPACE real-code safety row only"
)

SWEEP_ROW_COUNT=${#SWEEP_NAME[@]}
SWEEP_I=0
while [ "$SWEEP_I" -lt "$SWEEP_ROW_COUNT" ]; do
  SWEEP_ROW_NAME="${SWEEP_NAME[$SWEEP_I]}"
  SWEEP_ROW_EXPECT="${SWEEP_EXPECT[$SWEEP_I]}"
  SWEEP_ROW_KIND="${SWEEP_KIND[$SWEEP_I]}"
  SWEEP_ROW_CLASS="${SWEEP_CLASS[$SWEEP_I]}"

  SWEEP_ROW_PARENT="$SWEEP_ROOT/row_${SWEEP_I}_parent"
  SWEEP_ROW_DIR="$SWEEP_ROW_PARENT/$SWEEP_ROW_NAME"
  mkdir -p "$SWEEP_ROW_DIR/scripts"
  cp "$RELEASE_PREFIX" "$SWEEP_ROW_DIR/scripts/release_prefix.sh"
  (
    cd "$SWEEP_ROW_DIR" \
      && git init -q \
      && git config user.email "r7-sweep-fixture@example.invalid" \
      && git config user.name "r7-sweep-fixture"
  ) >/dev/null 2>&1
  printf 'HELIX_RELEASE_PREFIX=wrong_widen\n' > "$SWEEP_ROW_PARENT/.env"

  echo
  echo "-- SWEEP row $((SWEEP_I + 1))/$SWEEP_ROW_COUNT: '$SWEEP_ROW_NAME' -- $SWEEP_ROW_CLASS --"

  if [ ! -d "$SWEEP_ROW_DIR/.git" ] || [ ! -f "$SWEEP_ROW_PARENT/.env" ]; then
    bad "SWEEP row '$SWEEP_ROW_NAME' fixture setup failed -- cannot run this case"
    SWEEP_I=$((SWEEP_I + 1))
    continue
  fi

  SWEEP_ROW_TOPLEVEL="$(cd "$SWEEP_ROW_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"
  SWEEP_ROW_TOPLEVEL_BASE="$(basename "$SWEEP_ROW_TOPLEVEL" 2>/dev/null || true)"
  if [ "$SWEEP_ROW_TOPLEVEL_BASE" = "$SWEEP_ROW_NAME" ]; then
    ok "SWEEP row '$SWEEP_ROW_NAME' fixture precondition is genuinely real: the examined directory's own git toplevel basename is literally '$SWEEP_ROW_TOPLEVEL_BASE' -- not assumed"
  else
    bad "SWEEP row '$SWEEP_ROW_NAME' fixture is NOT genuinely named as intended (toplevel basename='$SWEEP_ROW_TOPLEVEL_BASE') -- re-investigate before trusting this row's result below"
  fi

  SWEEP_ROW_RESULT="$(cd "$SWEEP_ROW_DIR" && bash scripts/release_prefix.sh)"
  printf '  real-code result: %s (want %s)\n' "$SWEEP_ROW_RESULT" "$SWEEP_ROW_EXPECT"
  if [ "$SWEEP_ROW_RESULT" = "$SWEEP_ROW_EXPECT" ]; then
    ok "SWEEP row '$SWEEP_ROW_NAME' ($SWEEP_ROW_CLASS): the real, unmutated basename gate correctly does NOT widen -- stays basename-derived '$SWEEP_ROW_RESULT', even though the parent carries a valid, non-empty HELIX_RELEASE_PREFIX= .env"
  else
    bad "SWEEP row '$SWEEP_ROW_NAME' regression: got '$SWEEP_ROW_RESULT', want '$SWEEP_ROW_EXPECT' -- this near-miss basename false-widen bug has returned"
  fi

  if [ -z "$SWEEP_ROW_KIND" ]; then
    ok "SWEEP row '$SWEEP_ROW_NAME': no attack-class mutant applies to this row by design (a pure real-code safety check -- $SWEEP_ROW_CLASS) -- mutation-discrimination intentionally skipped for this row"
  else
    SWEEP_ROW_MUT="$SWEEP_ROW_PARENT/release_prefix_mut_${SWEEP_I}.sh"
    SWEEP_ROW_MUT_ERR="$(python3 "$MUT_GEN" "$RELEASE_PREFIX" "$SWEEP_ROW_MUT" "$SWEEP_ROW_KIND" 2>&1)"
    SWEEP_ROW_MUT_RC=$?
    if [ "$SWEEP_ROW_MUT_RC" -ne 0 ] || [ ! -f "$SWEEP_ROW_MUT" ]; then
      bad "SWEEP row '$SWEEP_ROW_NAME' mutation-discrimination setup failed (kind=$SWEEP_ROW_KIND rc=$SWEEP_ROW_MUT_RC err=$SWEEP_ROW_MUT_ERR) -- cannot prove this row's negative control is discriminating; investigate before trusting this row's real-code result above as a genuine regression guard"
    else
      cp "$SWEEP_ROW_MUT" "$SWEEP_ROW_DIR/scripts/release_prefix.sh"
      SWEEP_ROW_MUT_RESULT="$(cd "$SWEEP_ROW_DIR" && bash scripts/release_prefix.sh)"
      cp "$RELEASE_PREFIX" "$SWEEP_ROW_DIR/scripts/release_prefix.sh"   # restore the real, unmutated file
      printf '  mutated (%s, kind=%s) result: %s (want wrong_widen)\n' "$SWEEP_ROW_CLASS" "$SWEEP_ROW_KIND" "$SWEEP_ROW_MUT_RESULT"
      if [ "$SWEEP_ROW_MUT_RESULT" = "wrong_widen" ]; then
        ok "SWEEP row '$SWEEP_ROW_NAME' mutation-discrimination: the SAME fixture, run against a copy with ONLY the $SWEEP_ROW_CLASS attack applied (kind=$SWEEP_ROW_KIND), DOES incorrectly widen to the parent's unrelated prefix ('$SWEEP_ROW_MUT_RESULT') -- proving this row's negative control is genuinely load-bearing for the $SWEEP_ROW_CLASS attack class, not vacuously true"
      else
        bad "SWEEP row '$SWEEP_ROW_NAME' mutation-discrimination FAILED: the $SWEEP_ROW_CLASS-mutated copy (kind=$SWEEP_ROW_KIND) did NOT widen against the SAME fixture ('$SWEEP_ROW_MUT_RESULT') -- this row's negative control cannot be trusted as a real regression guard against this attack class"
      fi
    fi
  fi

  SWEEP_I=$((SWEEP_I + 1))
done
rm -f "$MUT_GEN"

# D4 (B1): the "mismatched-sibling-name-with-matching-.gitmodules-path"
# case -- the directory being examined is NOT itself named "constitution"
# at all (basename "other_dir"), even though the parent's .gitmodules
# carries a LEGITIMATE, exact-value-matching `path = constitution` entry
# (the kind of entry that WOULD correctly widen a genuine constitution/
# checkout per case D above). B1's basename gate must refuse to widen
# here regardless of how valid that evidence looks in isolation, because
# the entry describes a DIFFERENT, sibling directory -- not this one.
echo
echo "-- D4 (B1): mismatched sibling name ('other_dir', not 'constitution') with an otherwise-valid parent .gitmodules entry does NOT widen --"
D4_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_b1_mismatched_name_fixture.XXXXXX")"
D4_PARENT="$D4_ROOT/parent_mismatched_name"
D4_OTHER_DIR="$D4_PARENT/other_dir"
mkdir -p "$D4_OTHER_DIR/scripts"
cp "$RELEASE_PREFIX" "$D4_OTHER_DIR/scripts/release_prefix.sh"
(
  cd "$D4_OTHER_DIR" \
    && git init -q \
    && git config user.email "r5-d4-fixture@example.invalid" \
    && git config user.name "r5-d4-fixture"
) >/dev/null 2>&1
cat > "$D4_PARENT/.gitmodules" <<'GITMODULES_D4_EOF'
[submodule "constitution"]
	path = constitution
	url = git@example.invalid:org/constitution.git
GITMODULES_D4_EOF
printf 'HELIX_RELEASE_PREFIX=should_not_widen_wrong_sibling\n' > "$D4_PARENT/.env"
cleanup_d4_fixture() { rm -rf "$D4_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture; cleanup_d7_fixture; cleanup_d8_fixture; cleanup_d9_fixture; cleanup_sweep_fixture; cleanup_d4_fixture' EXIT

if [ ! -d "$D4_OTHER_DIR/.git" ] || [ ! -f "$D4_PARENT/.gitmodules" ] || [ ! -f "$D4_PARENT/.env" ]; then
  bad "D4 fixture setup failed -- cannot run the mismatched-sibling-name case"
else
  D4_TOPLEVEL="$(cd "$D4_OTHER_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"
  D4_TOPLEVEL_BASE="$(basename "$D4_TOPLEVEL" 2>/dev/null || true)"
  if [ "$D4_TOPLEVEL_BASE" = "other_dir" ]; then
    ok "D4 fixture precondition is genuinely real: the examined directory's own git toplevel basename is 'other_dir', NOT 'constitution' -- the mismatched-name scenario is real on this fixture, not assumed"
  else
    bad "D4 fixture is NOT genuinely mismatched-named (toplevel basename='$D4_TOPLEVEL_BASE') -- re-investigate before trusting case D4's result below"
  fi
  D4_RESULT="$(cd "$D4_OTHER_DIR" && bash scripts/release_prefix.sh)"
  printf '  mismatched-sibling-name fixture result: %s\n' "$D4_RESULT"
  if [ "$D4_RESULT" = "other_dir" ]; then
    ok "B1: a directory NOT named 'constitution' (basename 'other_dir') correctly does NOT widen even though its parent carries an otherwise-valid, exact-matching .gitmodules 'path = constitution' entry AND a valid HELIX_RELEASE_PREFIX .env -- stays 'other_dir' (the basename gate refuses to treat this sibling's own evidence as applying to a DIFFERENT directory)"
  else
    bad "B1 regression: got '$D4_RESULT', want 'other_dir' -- the mismatched-sibling-name false-widen bug has returned"
  fi
fi

# D5 (B1): the "unreadable-parent-.env" case -- a parent .env that DOES
# carry a genuine HELIX_RELEASE_PREFIX= assignment but is UNREADABLE
# (chmod 000) must NOT be treated as widening evidence (an unreadable
# file can never be verified to contain anything, so it must be treated
# identically to no evidence at all -- never silently trusted).
echo
echo "-- D5 (B1): unreadable parent .env (chmod 000, dir genuinely named 'constitution') does NOT widen --"
D5_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_b1_unreadable_env_fixture.XXXXXX")"
D5_PARENT="$D5_ROOT/parent_unreadable_env"
D5_CONSTITUTION="$D5_PARENT/constitution"
mkdir -p "$D5_CONSTITUTION/scripts"
cp "$RELEASE_PREFIX" "$D5_CONSTITUTION/scripts/release_prefix.sh"
(
  cd "$D5_CONSTITUTION" \
    && git init -q \
    && git config user.email "r5-d5-fixture@example.invalid" \
    && git config user.name "r5-d5-fixture"
) >/dev/null 2>&1
printf 'HELIX_RELEASE_PREFIX=should_not_widen_unreadable\n' > "$D5_PARENT/.env"
chmod 000 "$D5_PARENT/.env"
cleanup_d5_fixture() { chmod 644 "$D5_PARENT/.env" 2>/dev/null || true; rm -rf "$D5_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture; cleanup_d7_fixture; cleanup_d8_fixture; cleanup_d9_fixture; cleanup_sweep_fixture; cleanup_d4_fixture; cleanup_d5_fixture' EXIT

if [ ! -d "$D5_CONSTITUTION/.git" ] || [ ! -e "$D5_PARENT/.env" ]; then
  bad "D5 fixture setup failed -- cannot run the unreadable-parent-.env case"
else
  if [ -r "$D5_PARENT/.env" ]; then
    bad "D5 fixture precondition failed: '$D5_PARENT/.env' is unexpectedly READABLE despite chmod 000 (running as root?) -- cannot genuinely exercise the unreadable-file case on this host"
  else
    ok "D5 fixture precondition: '$D5_PARENT/.env' is genuinely unreadable (chmod 000, confirmed via [ -r ])"
  fi
  D5_RESULT="$(cd "$D5_CONSTITUTION" && bash scripts/release_prefix.sh)"
  printf '  unreadable-parent-.env fixture result: %s\n' "$D5_RESULT"
  if [ "$D5_RESULT" = "constitution" ]; then
    ok "B1: an unreadable parent .env (chmod 000) -- even one that genuinely contains a HELIX_RELEASE_PREFIX= assignment -- correctly does NOT widen, since it cannot be verified to contain anything -- stays 'constitution'"
  else
    bad "B1 regression: got '$D5_RESULT', want 'constitution' -- the unreadable-.env false-widen bug has returned"
  fi
fi

# E. invalid HELIX_PROJECT_ROOT override (N2, same independent review,
# 2026-10-03): an explicit-but-INVALID HELIX_PROJECT_ROOT (a path that
# does not exist / is not readable) MUST print a clear stderr warning
# naming the invalid path, and MUST still correctly fall through to the
# next resolution tier on stdout (a WARNING, never a hard failure, per
# §11.4.6 -- an explicit override silently ignored is as much a guess
# as inventing one).
echo
echo "-- E. invalid HELIX_PROJECT_ROOT override: warns on stderr, falls through correctly on stdout --"
E_INVALID_ROOT="/nonexistent/path/hrp_r5_e_fixture_$$"
if [ -e "$E_INVALID_ROOT" ]; then
  bad "E fixture precondition failed: '$E_INVALID_ROOT' unexpectedly exists on this host -- cannot exercise the invalid-override case"
else
  ok "E fixture precondition: '$E_INVALID_ROOT' genuinely does not exist"
  E_STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/hrp_r5_e_stderr.XXXXXX")"
  E_STDOUT="$(HELIX_PROJECT_ROOT="$E_INVALID_ROOT" bash "$RELEASE_PREFIX" 2>"$E_STDERR_FILE")"
  E_RC=$?
  E_STDERR="$(cat "$E_STDERR_FILE" 2>/dev/null)"
  rm -f "$E_STDERR_FILE"
  printf '  stdout: %s\n' "$E_STDOUT"
  printf '  stderr: %s\n' "$E_STDERR"
  printf '  exit:   %s\n' "$E_RC"
  if printf '%s' "$E_STDERR" | grep -Fq "$E_INVALID_ROOT"; then
    ok "N2: an invalid HELIX_PROJECT_ROOT override prints a stderr WARNING naming the specific invalid path ('$E_INVALID_ROOT'), rather than silently falling through with no indication the caller's explicit override was ignored"
  else
    bad "N2 regression: no stderr warning naming the invalid path ('$E_INVALID_ROOT') was printed (captured stderr: '$E_STDERR') -- the invalid-override warning has regressed"
  fi
  if [ "$E_RC" -eq 0 ] && [ -n "$E_STDOUT" ] && [ "$E_STDOUT" != "$E_INVALID_ROOT" ]; then
    ok "N2: resolution still correctly falls through to the next tier on stdout (got '$E_STDOUT', exit $E_RC) despite the invalid override -- a WARNING, never a hard failure, for this non-critical path-resolution tool"
  else
    bad "N2 regression: resolution did not correctly fall through after the invalid override (stdout='$E_STDOUT' exit=$E_RC)"
  fi
fi

# E2. readable-but-not-searchable HELIX_PROJECT_ROOT (M1, round-4
# independent Opus-xhigh review, 2026-10-03): a directory that IS a
# directory and IS readable (`-d`/`-r` both true) but is NOT searchable
# (chmod 444, no executable bit) previously passed the pre-M1-fix
# validation, then the subsequent `cd` into it failed -- producing an
# exit-1 with EMPTY stdout instead of the SAME documented
# warn-and-fall-through contract every other invalid-override shape
# (case E above) already gets. M1 added an `-x` check alongside `-d`/
# `-r`; this case proves it fires and the resolution still falls through
# correctly on stdout.
echo
echo "-- E2 (M1): readable-but-not-searchable HELIX_PROJECT_ROOT (chmod 444) warns on stderr, falls through correctly on stdout --"
E2_NOSEARCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hrp_r5_m1_nosearch_fixture.XXXXXX")"
chmod 444 "$E2_NOSEARCH_ROOT"
cleanup_e2_fixture() { chmod 755 "$E2_NOSEARCH_ROOT" 2>/dev/null || true; rm -rf "$E2_NOSEARCH_ROOT"; }
trap 'cleanup_standalone_fixture; cleanup_d_fixture; cleanup_d2_fixture; cleanup_d3_fixture; cleanup_d6_fixture; cleanup_d7_fixture; cleanup_d8_fixture; cleanup_d9_fixture; cleanup_sweep_fixture; cleanup_d4_fixture; cleanup_d5_fixture; cleanup_e2_fixture' EXIT
if [ ! -d "$E2_NOSEARCH_ROOT" ]; then
  bad "E2 fixture setup failed -- '$E2_NOSEARCH_ROOT' missing, cannot run the M1 readable-but-not-searchable case"
else
  if [ -x "$E2_NOSEARCH_ROOT" ]; then
    bad "E2 fixture precondition failed: '$E2_NOSEARCH_ROOT' is unexpectedly SEARCHABLE despite chmod 444 (running as root?) -- cannot genuinely exercise the not-searchable case on this host"
  else
    ok "E2 fixture precondition: '$E2_NOSEARCH_ROOT' is genuinely a directory ([ -d ]), readable ([ -r ]), but NOT searchable ([ -x ] fails, confirmed live)"
  fi
  E2_STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/hrp_r5_e2_stderr.XXXXXX")"
  E2_STDOUT="$(HELIX_PROJECT_ROOT="$E2_NOSEARCH_ROOT" bash "$RELEASE_PREFIX" 2>"$E2_STDERR_FILE")"
  E2_RC=$?
  E2_STDERR="$(cat "$E2_STDERR_FILE" 2>/dev/null)"
  rm -f "$E2_STDERR_FILE"
  printf '  stdout: %s\n' "$E2_STDOUT"
  printf '  stderr: %s\n' "$E2_STDERR"
  printf '  exit:   %s\n' "$E2_RC"
  if printf '%s' "$E2_STDERR" | grep -Fq "$E2_NOSEARCH_ROOT"; then
    ok "M1: a readable-but-not-searchable HELIX_PROJECT_ROOT override prints a stderr WARNING naming the specific path ('$E2_NOSEARCH_ROOT'), rather than silently crashing or producing empty output with no indication of why"
  else
    bad "M1 regression: no stderr warning naming the not-searchable path ('$E2_NOSEARCH_ROOT') was printed (captured stderr: '$E2_STDERR') -- the not-searchable-override warning has regressed"
  fi
  if [ "$E2_RC" -eq 0 ] && [ -n "$E2_STDOUT" ] && [ "$E2_STDOUT" != "$E2_NOSEARCH_ROOT" ]; then
    ok "M1: resolution still correctly falls through to the next tier on stdout (got '$E2_STDOUT', exit $E2_RC) despite the readable-but-not-searchable override -- the SAME warn-and-fall-through contract as every other invalid-override shape, never the pre-M1-fix empty-stdout/exit-1 crash"
  else
    bad "M1 regression: resolution did not correctly fall through after the readable-but-not-searchable override (stdout='$E2_STDOUT' exit=$E2_RC) -- the pre-M1-fix empty-output bug has returned"
  fi
fi

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases) -- release_prefix.sh / dispatch_stamp.sh resolution is genuinely CWD-independent"
exit 0
