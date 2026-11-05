#!/usr/bin/env bash
# covenant_propagation_superspec_exclusion_test.sh — v72.1 follow-up: the hub's own third-party
# submodules/superspec sample-project fixture (examples/static-landing-page/CLAUDE.md) is not an
# authored governance carrier and MUST be excluded (listed, justified) from the propagation family.
# Runs the real 287 wrapper against the real repo and requires (a) the fixture not reported as
# MISSING, (b) the exclusion reported as applied, (c) a control needle: a genuine own-org carrier gap
# is still reported (the exclusion must not blind the gate).
# Usage: bash covenant_propagation_superspec_exclusion_test.sh   Exit: 0 all pass, 1 any fail
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = "$3" ]; then echo "ok - $1"; P=$((P+1)); else echo "not ok - $1 (got [$2] want [$3])"; F=$((F+1)); fi; }
W="$(mktemp -d "${TMPDIR:-$HOME/.cache/claude-tmp}/cpse.XXXXXX")"; trap 'rm -rf "$W"' EXIT
cd "$W" || exit 2
bash "$HERE/cm_covenant_114_287_propagation.sh" --root "$REPO" >"$W/out" 2>&1
ok "fixture CLAUDE.md not reported MISSING" "$(grep -c 'submodules/superspec/examples/static-landing-page/CLAUDE.md' "$W/out")" 0
ok "superspec exclusion reported as applied" "$(grep -c 'EXCLUDED  \*/submodules/superspec/examples/\*' "$W/out" | awk '{print ($1>0)?"yes":"no"}')" yes
# The zero in (a) is evidence only when the fixture exists and the control needle proves the gate
# enumerates submodule carriers (section 11.4.201(7)(b), 11.4.273). Without either submodule checkout
# the result is an honest SKIP (exit 77), never a PASS on a vacuous zero (review F7).
MISSING=""
[ -f "$REPO/submodules/superspec/examples/static-landing-page/CLAUDE.md" ] || MISSING="$MISSING submodules/superspec"
[ -f "$REPO/submodules/claude_toolkit/CLAUDE.md" ] || MISSING="$MISSING submodules/claude_toolkit"
if [ -z "$MISSING" ]; then
ok "control needle: the toolkit carrier is still enumerated by the gate" "$(grep -c 'submodules/claude_toolkit/CLAUDE.md' "$W/out" | awk '{print ($1>0)?"yes":"no"}')" yes
fi
echo "# pass=$P fail=$F"
[ "$F" -eq 0 ] || exit 1
if [ -n "$MISSING" ]; then
  echo "SKIP: submodule checkout absent:$MISSING; assertion (a) cannot be proven without the fixture and the control needle reason=topology_unsupported"
  exit 77
fi
exit 0
