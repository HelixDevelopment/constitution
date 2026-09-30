#!/bin/sh
# enumerate.sh - consumer enumeration (T-G03; contract
# contracts/consumer-audit-and-migration.md CA-001..CA-005; guarded by
# tests/test_consumer_enumerate_red.sh, T166; FR-024, SC-010).
# Purpose: thin POSIX-sh entrypoint; the real logic (multi-source probing,
#   JSON construction, needle checks) lives in the co-located
#   _enumerate_impl.py (Python stdlib + PyYAML for --config parsing).
# Usage: enumerate.sh --config <fastcycle.yaml> --out <consumers.json>
#        [--determinism-check]
# Exit: 0 ok, 1 determinism mismatch (--determinism-check only), 2 usage,
#       3 needle failure (CA-004), 4 all sources unreachable, 5 one or
#       more probes degraded (partial enumeration; see --out's
#       source_reachability block -- T177 Round 1 B1).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
exec python3 "$HERE/_enumerate_impl.py" "$@"
