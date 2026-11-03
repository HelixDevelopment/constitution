#!/usr/bin/env bash
# golden-bad demo gate: DEMO_ROOT read raw (not guarded, not allowlisted): a stray variable can redirect the scan.
root="${DEMO_ROOT:-.}"
cfg="${DEMO_CONFIG:-}"
echo "$root $cfg"
