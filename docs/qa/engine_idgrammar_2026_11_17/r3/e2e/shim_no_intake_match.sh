#!/usr/bin/env bash
# Dispatch shim: makes intake-match unavailable, runs every other verb on the real engine.
if [ "${1:-}" = "intake-match" ]; then echo "shim: intake-match unavailable" >&2; exit 1; fi
exec "/mnt/DATA1TB/claude-work/scratch/fix456r3_3Kpt0z/repo/scripts/workable-items/bin/workable-items" "$@"
