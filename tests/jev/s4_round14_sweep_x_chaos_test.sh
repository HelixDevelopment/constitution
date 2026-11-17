#!/usr/bin/env bash
# s4_round14_sweep_x_chaos_test.sh - part x of the round-14 kill sweep of scripts/jev/jev-place.sh (section 11.4.291, review
# R13-B1); the sweep and its parts are described in tests/jev/fixtures/sweep_s4_round14.sh. Gate-logic evidence
# (section 11.4.289(C)(2)), stub llmctl; heavy tier (about 4 to 7 minutes on the reference host).
HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP14_PART=x bash "$HERE/fixtures/sweep_s4_round14.sh"
