#!/usr/bin/env bash
# tests/sync/test_robustness.sh -- ROBUSTNESS suite (review round 4 findings RV4-1 .. RV4-15 and the mutants
# V01 V02 V04 V08 V09 V13 V16 V17 V18 V22 that survived round 4): races between inspection and write, a staged
# gitlink, long and huge remote stderr, signals, the environment and repository config that could re-enable
# prompts or helpers, unwritable evidence directories, overlapping roots, odd gitlink paths. The body is
# scripts/sync/robustness_checks.py; it drives the real engine (SX_ENGINE, default the wrapper) against real
# git in a mktemp sandbox; no network (file:// and 127.0.0.1 only), $HOME untouched.
# Usage: bash tests/sync/test_robustness.sh [--only NAME,NAME]   Exit: 0 pass, 1 a check failed, 2 no sandbox.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$here/../../scripts/sync/robustness_checks.py" "$@"
