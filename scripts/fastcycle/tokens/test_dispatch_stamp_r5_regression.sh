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

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases) -- release_prefix.sh / dispatch_stamp.sh resolution is genuinely CWD-independent"
exit 0
