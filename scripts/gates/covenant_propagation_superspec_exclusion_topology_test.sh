#!/usr/bin/env bash
# covenant_propagation_superspec_exclusion_topology_test.sh — guards the topology handling of
# covenant_propagation_superspec_exclusion_test.sh (review F7 of the manifest-triage vehicle):
# with a submodule checkout missing, the control needle cannot run, so the test MUST exit 77 with
# reason=topology_unsupported on its last line and MUST NOT exit 0 on a vacuous zero; with both
# carriers present it MUST run the needle and exit 0.
# Builds a scratch shared-object clone of this repository's HEAD (no submodules are checked out
# there), overlays the CURRENT test file, and runs that real test in two layouts:
#   (1) no submodule files                          -> rc 77, last line reason=topology_unsupported
#   (2) the two carrier files placed as plain files -> rc 0 and the control-needle line ran
# Usage: bash scripts/gates/covenant_propagation_superspec_exclusion_topology_test.sh
# Exit: 0 all pass, 1 any fail, 2 setup error.
# Safety: one mktemp -d root removed with safe_rm_rf restricted to it; $HOME is never reassigned;
# this repository is only read (git clone --shared).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/safe_rm.sh
. "$REPO/scripts/lib/safe_rm.sh"
UNDER="$HERE/covenant_propagation_superspec_exclusion_test.sh"
P=0; F=0
ok()  { P=$((P+1)); echo "ok - $*"; }
bad() { F=$((F+1)); echo "not ok - $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/cpse_topo.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
export SAFE_RM_ALLOWED_ROOTS="$W"
trap 'safe_rm_rf "${W:?}"' EXIT
C="$W/canon"
git clone -q --shared --no-recurse-submodules "$REPO" "$C" 2>/dev/null \
  && git -C "$C" checkout -q --detach "$(git -C "$REPO" rev-parse HEAD)" || { echo "scratch clone failed" >&2; exit 2; }
cp "$UNDER" "$C/scripts/gates/covenant_propagation_superspec_exclusion_test.sh" || exit 2
T="$C/scripts/gates/covenant_propagation_superspec_exclusion_test.sh"
last() { grep -v '^[[:space:]]*$' "$1" | tail -1; }

[ -e "$C/submodules/claude_toolkit/CLAUDE.md" ] && { echo "precondition broken: scratch clone has the toolkit carrier" >&2; exit 2; }
( cd "$W" && TMPDIR="$W" bash "$T" ) >"$W/o1" 2>&1; rc=$?
[ "$rc" = 77 ] && ok "(1) no submodule checkout: rc 77" || bad "(1) no submodule checkout: rc $rc, want 77 ($(last "$W/o1"))"
last "$W/o1" | grep -q 'reason=topology_unsupported$' && ok "(1) last line carries reason=topology_unsupported" \
  || bad "(1) last line [$(last "$W/o1")] lacks reason=topology_unsupported"
grep -Eq '^(not )?ok - control needle' "$W/o1" && bad "(1) the needle reported a result it could not have measured" || ok "(1) no needle result is reported"

mkdir -p "$C/submodules/claude_toolkit" "$C/submodules/superspec/examples/static-landing-page"
TK="$C/submodules/claude_toolkit/CLAUDE.md"; SS="$C/submodules/superspec/examples/static-landing-page/CLAUDE.md"
# (3) only the superspec fixture, (4) only the toolkit carrier: each half alone still cannot prove (a)
printf '# placeholder fixture for the topology test\n' >"$SS"
( cd "$W" && TMPDIR="$W" bash "$T" ) >"$W/o3" 2>&1; rc=$?
[ "$rc" = 77 ] && ok "(3) superspec only: rc 77" || bad "(3) superspec only: rc $rc, want 77 ($(last "$W/o3"))"
rm -f -- "$SS"; printf '# placeholder carrier for the topology test\n' >"$TK"
( cd "$W" && TMPDIR="$W" bash "$T" ) >"$W/o4" 2>&1; rc=$?
[ "$rc" = 77 ] && ok "(4) toolkit only: rc 77" || bad "(4) toolkit only: rc $rc, want 77 ($(last "$W/o4"))"
printf '# placeholder fixture for the topology test\n' >"$SS"
( cd "$W"&& TMPDIR="$W" bash "$T" ) >"$W/o2" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "(2) both carriers present: rc 0" || bad "(2) both carriers present: rc $rc, want 0 ($(last "$W/o2"))"
grep -q '^ok - control needle' "$W/o2" && ok "(2) the control needle ran and passed" || bad "(2) the control needle did not run: $(grep needle "$W/o2")"
echo "# pass=$P fail=$F"
[ "$F" -eq 0 ] && [ "$P" -gt 0 ]
