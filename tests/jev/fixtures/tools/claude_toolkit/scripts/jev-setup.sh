#!/usr/bin/env bash
# Fixture jev-setup.sh. Contract used by bootstrap:
#   --check --agents <csv>   : rc 0 when every present agent home is wired, else rc 1
#   --agents <csv> --yes     : wires (marker file); WITHOUT --yes it refuses (rc 2)
set -euo pipefail
check=0; yes=0; agents="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=1; shift ;;
    --yes) yes=1; shift ;;
    --agents) agents="$2"; shift 2 ;;
    *) echo "jev-setup fixture: unknown arg $1" >&2; exit 2 ;;
  esac
done
printf '%s\n' "jev-setup check=$check yes=$yes agents=$agents" >> "${STUB_LOG:-/tmp}/jev-setup.log" 2>/dev/null || true
homes=()
want() { [ "$agents" = all ] || printf '%s' "$agents" | tr ',' '\n' | grep -qx "$1"; }
want claude   && [ -d "$HOME/.claude" ]          && homes+=("$HOME/.claude")
want kimi     && [ -d "$HOME/.kimi-code" ]       && homes+=("$HOME/.kimi-code")
want pi       && [ -d "$HOME/.pi" ]              && homes+=("$HOME/.pi")
want opencode && [ -d "$HOME/.config/opencode" ] && homes+=("$HOME/.config/opencode")
if [ "$check" = 1 ]; then
  rc=0
  for h in "${homes[@]:-}"; do [ -n "$h" ] || continue; [ -f "$h/jev-wiring.marker" ] || { echo "unwired: $h"; rc=1; }; done
  exit $rc
fi
[ "$yes" = 1 ] || { echo "refusing to edit agent homes without --yes" >&2; exit 2; }
for h in "${homes[@]:-}"; do [ -n "$h" ] || continue; [ -f "$h/jev-wiring.marker" ] || printf 'jev-gate-wired\n' > "$h/jev-wiring.marker"; done
echo "fixture jev-setup: wired $agents"
