#!/usr/bin/env bash
# covenant_propagation_suite_default_root_test.sh — v72.1 review IMPORTANT-1: the SUITE (not only the
# engine) must default to the repository root when run with no --root from an unrelated cwd.
# Uses a one-row anchors pack so it runs in seconds. Exit 0 all pass, 1 any fail.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = "$3" ]; then echo "ok - $1"; P=$((P+1)); else echo "not ok - $1 (got [$2] want [$3])"; F=$((F+1)); fi; }
W="$(mktemp -d "${TMPDIR:-$HOME/.cache/claude-tmp}/cpsdr.XXXXXX")"; trap 'rm -rf "$W"' EXIT
printf 'CM-COVENANT-114-27-PROPAGATION\t11.4.27\n' > "$W/pack.tsv"
mkdir -p "$W/elsewhere"; cd "$W/elsewhere" || exit 2
# The suite prints the carrier-set size right after resolving its root, before running any gate; read only
# that first line (the run is then cut off by timeout, which is irrelevant to this assertion).
first(){ COVENANT_PROPAGATION_ANCHORS="$W/pack.tsv" timeout 20 bash "$HERE/covenant_propagation_suite.sh" gates "$@" 2>&1 | head -n 1; }
D="$(first)"; E="$(first --root "$REPO")"
ok "no-root run printed a carrier-set line" "$(printf '%s' "$D" | grep -c 'carrier set computed once')" 1
ok "no-root carrier set equals explicit --root repo carrier set" "$D" "$E"
echo "# pass=$P fail=$F"; [ "$F" -eq 0 ]
