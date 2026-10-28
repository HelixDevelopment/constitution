#!/usr/bin/env bash
# covenant_propagation_third_party_hub_exclusion_test.sh — v72.1: the third-party open_design reference
# checkout (nexu-io/open-design, §11.4.162) and the third-party submodules/verification checkout
# (ArcBlock/agent-skills) carry upstream-authored AGENTS.md/CLAUDE.md files that are NOT governance
# carriers and MUST be excluded (listed, justified) from the propagation family.
# Requires, with all submodules checked out (non-recursive): (a) no carrier under those two paths is
# reported MISSING, (b) both exclusions are reported applied, (c) control needle: the gate still audits the hub's own CLAUDE.md.
# SKIP (exit 0, stated) when the submodules are not checked out. Exit 0 all pass, 1 any fail.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = "$3" ]; then echo "ok - $1"; P=$((P+1)); else echo "not ok - $1 (got [$2] want [$3])"; F=$((F+1)); fi; }
if [ ! -f "$REPO/submodules/open_design/AGENTS.md" ] || [ ! -d "$REPO/submodules/verification" ]; then
  echo "SKIP - open_design/verification submodules not checked out (nothing to exclude)"; exit 0; fi
W="$(mktemp -d "${TMPDIR:-$HOME/.cache/claude-tmp}/cptp.XXXXXX")"; trap 'rm -rf "$W"' EXIT
cd "$W" || exit 2
bash "$HERE/cm_covenant_114_270_propagation.sh" --root "$REPO" >"$W/out" 2>&1
ok "no open_design carrier reported MISSING" "$(grep -c 'MISSING.*submodules/open_design/' "$W/out")" 0
ok "no verification carrier reported MISSING" "$(grep -c 'MISSING.*submodules/verification/' "$W/out")" 0
ok "open_design exclusion applied" "$(grep -c 'EXCLUDED  \*/submodules/open_design/\*' "$W/out" | awk '{print ($1>0)?"yes":"no"}')" yes
ok "verification exclusion applied" "$(grep -c 'EXCLUDED  \*/submodules/verification/\*' "$W/out" | awk '{print ($1>0)?"yes":"no"}')" yes
ok "control needle: hub CLAUDE.md still audited (PRESENT)" "$(grep -c 'PRESENT     CLAUDE.md' "$W/out" | awk '{print ($1>0)?"yes":"no"}')" yes
echo "# pass=$P fail=$F"; [ "$F" -eq 0 ]
