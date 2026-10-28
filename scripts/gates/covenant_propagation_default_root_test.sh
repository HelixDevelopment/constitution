#!/usr/bin/env bash
# covenant_propagation_default_root_test.sh — F5 (v72.1 review follow-up): the engine
# default root must be the repository root (or the consumer root when the hub is a
# vendored "constitution" submodule), NEVER the caller cwd-relative ".."
# Usage: bash covenant_propagation_default_root_test.sh   Exit: 0 all pass, 1 any fail
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENG="$HERE/lib/covenant_propagation_engine.sh"
P=0; F=0
ok(){ if [ "$2" = "$3" ]; then echo "ok - $1"; P=$((P+1)); else echo "not ok - $1 (got [$2] want [$3])"; F=$((F+1)); fi; }
W="$(mktemp -d "${TMPDIR:-$HOME/.cache/claude-tmp}/cpdr.XXXXXX")"; trap 'rm -rf "$W"' EXIT
# unit: helper, hub-as-itself
mkdir -p "$W/hub/.git" "$W/cons/.git" "$W/cons/constitution" "$W/cons2/constitution" "$W/elsewhere"
# shellcheck disable=SC1090
. "$ENG"
type covenant_propagation_default_root >/dev/null 2>&1 && H=yes || H=no
ok "helper covenant_propagation_default_root exists" "$H" yes
ok "plain repo resolves to itself" "$(covenant_propagation_default_root "$W/hub" 2>/dev/null)" "$W/hub"
ok "vendored constitution inside a git consumer resolves to the consumer" "$(covenant_propagation_default_root "$W/cons/constitution" 2>/dev/null)" "$W/cons"
ok "constitution dir whose parent is not a git repo resolves to itself" "$(covenant_propagation_default_root "$W/cons2/constitution" 2>/dev/null)" "$W/cons2/constitution"
# integration: real wrapper, no --root, unrelated cwd, must equal run with explicit --root
WR="$HERE/cm_covenant_114_287_propagation.sh"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$W/elsewhere" || exit 2
bash "$WR" >"$W/a.out" 2>&1; A=$?
bash "$WR" --root "$REPO" >"$W/b.out" 2>&1; B=$?
ok "no --root from unrelated cwd equals explicit --root (rc)" "$A" "$B"
ok "no --root names the repo root, not the cwd-relative parent" "$(grep -c "consumer root not found" "$W/a.out")" 0
echo "# pass=$P fail=$F"; [ "$F" -eq 0 ]
