#!/usr/bin/env bash
# install_timer.sh - idempotent installer for the credscan systemd --user timer.
#
#   install_timer.sh [--dry-run] [--enable] [--seed-baseline FILE]
#
# Copies the engine + wrapper to ~/.local/lib/credscan and the units to ~/.config/systemd/user.
# It does NOT install the UserPromptSubmit hook and does NOT touch any settings.json.
# It does NOT enable the timer unless --enable is given, and never creates a baseline by
# scanning: a baseline only comes from --seed-baseline FILE (an existing counts-only file)
# or from an explicit `credscan.py baseline` run by the operator.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; ENABLE=0; SEED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --enable) ENABLE=1 ;;
    --seed-baseline) shift; SEED="${1:?--seed-baseline needs a file}" ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac; shift
done
if [ -n "$SEED" ]; then
  [ -f "$SEED" ] || { echo "seed baseline not found: $SEED" >&2; exit 2; }
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("schema")==1 and d.get("counts_only") is True and isinstance(d.get("files"),dict)' "$SEED" 2>/dev/null \
    || { echo "seed baseline is not a credscan counts-only baseline: $SEED" >&2; exit 2; }
fi
LIB="$HOME/.local/lib/credscan"; UNITS="$HOME/.config/systemd/user"; STATE="${CREDSCAN_STATE_DIR:-$HOME/.local/state/credscan}"
run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
echo "plan: engine+wrapper -> $LIB ; units credscan-check.service credscan-check.timer -> $UNITS ; state $STATE"
run mkdir -p -- "$LIB" "$UNITS" "$STATE"
run chmod 700 -- "$STATE"
for f in credscan.py credscan_check_timer.sh; do run install -m 0755 -- "$HERE/$f" "$LIB/$f"; done
for f in credscan-check.service credscan-check.timer; do run install -m 0644 -- "$HERE/systemd/$f" "$UNITS/$f"; done
if [ -n "$SEED" ]; then
  [ -e "$STATE/baseline.json" ] && echo "baseline already present, not overwritten" || run install -m 0600 -- "$SEED" "$STATE/baseline.json"
fi
[ -f "$STATE/baseline.json" ] || echo "note: no baseline at $STATE/baseline.json - the timer will report baseline_missing until the operator creates one"
if [ "$DRY" = 1 ]; then echo "[dry-run] systemctl --user daemon-reload"; else systemctl --user daemon-reload || echo "warning: daemon-reload failed" >&2; fi
if [ "$ENABLE" = 1 ]; then run systemctl --user enable --now credscan-check.timer; else echo "timer not enabled (pass --enable, or: systemctl --user enable --now credscan-check.timer)"; fi
