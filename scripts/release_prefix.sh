#!/usr/bin/env bash
# scripts/release_prefix.sh — resolve the project release/tag prefix (§11.4.151).
#
# Single source of truth for "<PREFIX>-<version>" tag/version naming. EVERY
# release-tag-creating or version-naming script — main repo AND every owned
# submodule (§11.4.28 / §11.4.151) — MUST obtain its prefix from here so the
# SAME prefix spans the whole release and a release is greppable across every
# repo:  git tag -l "$(scripts/release_prefix.sh)-*"
#
# Resolution order (closed-set, deterministic — §11.4.6 no-guessing, §11.4.151):
#   1. HELIX_RELEASE_PREFIX from the environment (authoritative when set).
#   2. HELIX_RELEASE_PREFIX from the git-ignored project-root .env (§11.4.30),
#      PARSED (never sourced) so a hostile .env cannot execute code (§11.4.10).
#   3. Fallback: lowercased snake_case of the project-root directory name
#      (§11.4.29) — always resolvable from the checkout, no operator input.
#
# Usage:
#   prefix="$(bash scripts/release_prefix.sh)"                      # as a command
#   . scripts/release_prefix.sh; prefix="$(helix_release_prefix)"   # sourced
#
# Exit 0 + prints the prefix on stdout (never empty). Non-zero only on a
# genuinely unresolvable root — a directed error, never a guess (§11.4.6).
# Classification: universal (§11.4.17). No hardcoded prefix anywhere.

set -euo pipefail

# Project root: resolved ANCHORED TO THIS FILE'S OWN LOCATION, never to the
# caller's current working directory (§11.4.6 no-guessing + the exact-
# reproduction-sequence precedent already established elsewhere in this
# codebase by constitution/scripts/fastcycle/timing/fc_timer.sh, whose
# CANDIDATE FINGERPRINT RESOLUTION header states: "deliberately ANCHORED TO
# THIS FILE'S OWN PATH, not the caller's current working directory, so the
# fingerprint is stable regardless of what directory the sourcing script
# happens to be running from").
#
# BUG FIXED (found by independent Opus-xhigh review of SpecKit-004 T048/US1
# slice S8, 2026-10-03): the PREVIOUS primary mechanism ran
# `git rev-parse --show-toplevel` in the CALLING PROCESS's ambient cwd. This
# genuinely depends on the current directory in TWO distinct, reproducible
# ways: (1) `constitution/` in THIS deployment is itself a nested git
# submodule with its OWN `.git` -- invoking `git rev-parse --show-toplevel`
# from ANYWHERE inside `constitution/` (including the real caller,
# `dispatch_stamp.sh`, whenever the PROCESS invoking it happens to have cwd
# inside `constitution/`) returns the SUBMODULE's own toplevel
# (".../constitution") rather than the consuming project's real root, so
# `.env`'s HELIX_RELEASE_PREFIX is never found there and the prefix silently
# degrades to snake_case("constitution") instead of the real "atmosphere";
# (2) from a directory with no git repository at all (e.g. /tmp), the OLD
# fallback computed only ONE level up from this file's own directory
# ("$self_dir/.."), which for this file's REAL deployed location
# (constitution/scripts/release_prefix.sh) resolves to "constitution/" --
# again one level short of the real project root. Both paths independently
# produced the WRONG prefix depending purely on the caller's cwd, which a
# downstream consumer (dispatch_stamp.sh's item=<ATM-nnnn> dispatch-tag
# enforcement) read through to a correctly-tagged dispatch being WRONGLY
# REFUSED, or its item attribution silently lost, purely because of where
# the invoking process happened to be running from.
#
# FIX (round 2, S8 remediation, independent Opus-xhigh NO-GO on the round-1
# fix above -- this comment documents the SURVIVING history, §11.4.113
# forward-only, never rewritten): a FIXED "two levels up from this file's
# own directory" is WRONG for this constitution's OTHER documented,
# supported layout -- STANDALONE use, where `constitution/` is cloned as
# its OWN top-level repo (see `constitution/.env.example`'s own header:
# "the HelixConstitution repo itself" / "helix_constitution" fallback, and
# this file's own `Usage:` block above, both of which predate and describe
# that layout). In a standalone clone
# (<clone>/scripts/release_prefix.sh), "two levels up from this file's own
# directory" lands ONE level ABOVE the clone itself -- the wrong directory
# entirely, silently ignoring that repo's OWN `.env` and resolving to
# whatever directory name happens to CONTAIN the clone instead of the
# clone's own basename. Verified live: in a standalone clone named
# "HelixConstitution" the OLD (pre-round-1) code correctly printed
# "helix_constitution"; the round-1 "$self_dir/../.." fix printed the
# CONTAINING directory's name instead -- silently wrong in the opposite
# direction from the bug round-1 was fixing.
#
# FIX (round 2): resolve root via `git`, ANCHORED to this file's own
# location (`-C "$self_dir"`, never the caller's ambient cwd -- this is
# what actually fixes the round-1 bug; the caller-cwd-dependence was NEVER
# about using git vs. a fixed directory count, it was about git being
# invoked in the WRONG directory), in priority order:
#   1. `git -C "$self_dir" rev-parse --show-superproject-working-tree` --
#      when `constitution/` is a NESTED git submodule of a consuming
#      project (the EMBEDDED layout), this returns that consuming
#      project's own top-level root regardless of which directory inside
#      `constitution/` the caller's process cwd happens to be -- verified
#      live from constitution/scripts, constitution/scripts/fastcycle/
#      tests, and from /tmp via `-C`, all four returning the SAME
#      consuming-project root. Empty when NOT a submodule (the STANDALONE
#      case), never when it IS one -- so this never shadows case 2.
#   2. `git -C "$self_dir" rev-parse --show-toplevel` -- when `constitution/`
#      is NOT a nested submodule (the STANDALONE layout: it IS its own
#      top-level git repo), this correctly returns that repo's own root --
#      exactly the "helix_constitution" example `constitution/.env.example`
#      documents.
#   3. `$self_dir/..` (one level above this file's own containing
#      directory, i.e. `self_dir`'s parent -- NOT the round-1 fix's
#      `../..`) -- only when THIS file's own directory is not inside any
#      git repository at all (an unpacked tarball, a bare file copy); the
#      ORIGINAL, pre-round-1 no-git fallback, restored unchanged.
#   4. (optional override) HELIX_PROJECT_ROOT from the environment, when
#      set to a directory that genuinely exists, takes priority over all
#      of the above -- an explicit operator/CI escape hatch for a layout
#      none of (1)-(3) can resolve correctly (§11.4.6: an EXPLICIT override
#      the caller opted into, never a silent guess).
#
# FIX (round 3, independent Opus-xhigh review of SpecKit-004 T048/US1
# slice S8, 2026-10-03 -- two MINOR findings, follow-up polish round,
# N1/N2; neither has a measured real-world instance, both are tracked
# edge-case hardening):
#   N1 -- an UNREGISTERED nested `constitution/` repo (has its own
#     `.git` but is NOT a registered gitlink/submodule in any parent
#     project) previously fell straight through case 2 above
#     (`--show-toplevel`), silently treating it as genuinely STANDALONE
#     and returning constitution's OWN root even when it is really
#     nested two levels under an intended parent project (the exact
#     embedded-layout shape case 1/round-2 was built for, just without
#     a formal `git submodule add` registration). Fixed: when case 2
#     resolves to this file's OWN repo root (not a real submodule, since
#     case 1 already failed), check whether the directory TWO levels
#     above this file's own location (`$self_dir/../..`, the real
#     embedded-layout parent-project root) carries REAL evidence of
#     being that intended parent -- its own `.env` file, or a
#     `.gitmodules` entry naming "constitution" as a submodule path --
#     and PREFER that directory over the narrower `--show-toplevel`
#     result when it does. `HELIX_PROJECT_ROOT` (case 4) remains the
#     manual escape hatch for any layout this heuristic still misses.
#   N2 -- an explicit-but-INVALID `HELIX_PROJECT_ROOT` override (set to a
#     path that is not an existing, readable directory) was previously
#     silently skipped, falling through to the next tier with NO
#     indication the caller's own explicit override was ignored (§11.4.6:
#     "a directed error, never a guess" -- silently ignoring an explicit
#     override is neither). Fixed: an invalid override now prints a
#     clear stderr warning naming the invalid path before falling
#     through -- a WARNING, not a hard failure, since graceful
#     degradation to the next resolution tier remains the correct
#     behaviour for this non-critical path-resolution tool.
#
# FIX (round 4, independent Opus-xhigh review of SpecKit-004 T048/US1
# slice S8, 2026-10-03 -- one BLOCKING finding B1 + one MINOR finding M1):
#   B1 -- N1's widen-to-parent evidence check was too permissive: it
#     treated ANY readable `.env` file in the parent (even one with NO
#     `HELIX_RELEASE_PREFIX` assignment at all, e.g. one holding only
#     `API_KEY=x`) as sufficient evidence to widen, and treated ANY
#     `.gitmodules` entry naming `path = constitution` as sufficient even
#     when `root` (the directory N1's own heuristic is deciding whether
#     to widen AWAY FROM -- see the `root=...--show-toplevel` call
#     immediately below) is NOT itself named "constitution" at all (e.g.
#     a clone named "HelixConstitution" sitting under an unrelated parent
#     "workspace/" that merely happens to carry SOME `.env`). Concretely
#     reproduced and now fixed: (a) a clone named "HelixConstitution"
#     under "workspace/", with "workspace/.env" holding unrelated
#     content, no longer widens -- stays "helix_constitution"; (b) a
#     readable-but-content-irrelevant parent `.env` (no
#     `HELIX_RELEASE_PREFIX=` line) no longer widens; (c) an unreadable
#     (chmod 000) parent `.env` no longer widens. Fixed by: (1) requiring
#     `basename "$root"` to be LITERALLY "constitution" before EITHER
#     evidence branch is even consulted -- the widen heuristic exists
#     ONLY for "is this genuinely the constitution/ submodule, just
#     nested-but-unregistered", so a directory not even named
#     "constitution" is never a candidate for it, regardless of what its
#     parent contains; (2) the `.env` branch now calls the SAME
#     `_hrp_from_env_file()` this file's own tier-2 resolution already
#     uses (never re-implemented, never sourced -- §11.4.10) to verify
#     the parent's `.env` genuinely CONTAINS a `HELIX_RELEASE_PREFIX=`
#     assignment, not merely that the file exists and is readable. The
#     `.gitmodules` branch's `path = constitution` anchoring is unchanged
#     (already exact-value-anchored, confirmed by re-reading it before
#     this fix) and is now gated behind the SAME basename check.
#   M1 -- `HELIX_PROJECT_ROOT` validation checked `-d` (is a directory)
#     and `-r` (is readable) but not `-x` (is searchable/enterable). A
#     directory that is readable-but-not-searchable (`chmod 444`)
#     previously passed validation, then the subsequent `cd` into it
#     failed, producing an exit-1 with EMPTY stdout instead of the
#     documented warn-and-fall-through contract every OTHER invalid-
#     override shape already gets. Fixed: `-x` is now checked alongside
#     `-d`/`-r`; on failure, the SAME warn-and-fall-through behaviour as
#     every other invalid-HELIX_PROJECT_ROOT shape.
_hrp_project_root() {
  local self_dir root root_base parent_root evidence
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [ -n "${HELIX_PROJECT_ROOT:-}" ]; then
    if [ -d "${HELIX_PROJECT_ROOT}" ] && [ -r "${HELIX_PROJECT_ROOT}" ] && [ -x "${HELIX_PROJECT_ROOT}" ]; then
      (cd "$HELIX_PROJECT_ROOT" && pwd); return 0
    else
      echo "release_prefix.sh: WARNING: HELIX_PROJECT_ROOT='${HELIX_PROJECT_ROOT}' is set but is not an existing, readable, and searchable (executable-bit) directory -- ignoring this explicit override and falling through to the next resolution tier (§11.4.6: a directed error, never a silent guess)" >&2
    fi
  fi
  if root="$(git -C "$self_dir" rev-parse --show-superproject-working-tree 2>/dev/null)" \
     && [ -n "$root" ]; then
    printf '%s' "$root"; return 0
  fi
  if root="$(git -C "$self_dir" rev-parse --show-toplevel 2>/dev/null)" \
     && [ -n "$root" ]; then
    # N1 (round 3) + B1 (round 4): `root` here is constitution's OWN git
    # toplevel (case 1 above already failed, so this is NOT a registered
    # submodule). Widening is considered ONLY when `root` ITSELF is
    # literally named "constitution" -- B1's first gate, consulted BEFORE
    # either evidence branch below.
    root_base="$(basename "$root")"
    if [ "$root_base" = "constitution" ]; then
      # If the real embedded-layout parent two levels up carries evidence
      # of being the intended project root, prefer it.
      parent_root="$(cd "$self_dir/../.." 2>/dev/null && pwd)"
      if [ -n "$parent_root" ] && [ "$parent_root" != "$root" ]; then
        evidence=0
        # B1: content-verified -- the parent's `.env` must genuinely
        # contain a `HELIX_RELEASE_PREFIX=` assignment, parsed via the
        # SAME `_hrp_from_env_file()` tier-2 already uses below --
        # file-existence alone is no longer sufficient.
        if [ -n "$(_hrp_from_env_file "$parent_root/.env")" ]; then
          evidence=1
        elif [ -f "$parent_root/.gitmodules" ] \
             && grep -Eq '^[[:space:]]*path[[:space:]]*=[[:space:]]*constitution[[:space:]]*$' \
                  "$parent_root/.gitmodules" 2>/dev/null; then
          evidence=1
        fi
        if [ "$evidence" -eq 1 ]; then
          printf '%s' "$parent_root"; return 0
        fi
      fi
    fi
    printf '%s' "$root"; return 0
  fi
  (cd "$self_dir/.." && pwd)
}

# Parse HELIX_RELEASE_PREFIX=<value> from a .env WITHOUT sourcing it.
_hrp_from_env_file() {
  local envfile="$1" line val
  [ -f "$envfile" ] || return 0
  line="$(grep -E '^[[:space:]]*HELIX_RELEASE_PREFIX[[:space:]]*=' "$envfile" 2>/dev/null \
          | grep -vE '^[[:space:]]*#' | tail -n1 || true)"
  [ -n "$line" ] || return 0
  val="${line#*=}"
  val="${val#"${val%%[![:space:]]*}"}"   # ltrim
  val="${val%"${val##*[![:space:]]}"}"   # rtrim
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  printf '%s' "$val"
}

# Lowercase snake_case of the project-root dir name (§11.4.29 fallback):
# camelCase/PascalCase -> snake, non-alnum -> _, lowercase, squeeze/trim _.
# e.g. "HelixConstitution" -> "helix_constitution"; "My App" -> "my_app".
_hrp_snake_case() {
  printf '%s' "$1" \
    | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/[^A-Za-z0-9]+/_/g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/_+/_/g; s/^_//; s/_$//'
}

helix_release_prefix() {
  local root prefix
  if [ -n "${HELIX_RELEASE_PREFIX:-}" ]; then           # (1) env — authoritative
    printf '%s\n' "$HELIX_RELEASE_PREFIX"; return 0
  fi
  root="$(_hrp_project_root)"
  prefix="$(_hrp_from_env_file "$root/.env")"           # (2) .env (parsed, §11.4.10)
  if [ -n "$prefix" ]; then printf '%s\n' "$prefix"; return 0; fi
  prefix="$(_hrp_snake_case "$(basename "$root")")"     # (3) snake_case fallback
  if [ -z "$prefix" ]; then
    echo "release_prefix: cannot resolve a prefix (no HELIX_RELEASE_PREFIX, no .env value, empty root name)" >&2
    return 1
  fi
  printf '%s\n' "$prefix"
}

# Run directly (not sourced) -> print the resolved prefix.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then helix_release_prefix; fi
