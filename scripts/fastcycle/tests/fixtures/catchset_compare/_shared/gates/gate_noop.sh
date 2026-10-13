#!/bin/sh
# id: g_noop
# Purpose: toy Gate for the T050 catch-set-comparison-harness RED fixtures.
#          Always PASSes (exit 0), regardless of $1's content. Present in
#          every fixture's config so baseline-sanity (CS-003: unmutated
#          tree -> ALL gates PASS) has a second, independently-verifiable
#          "definitely passes" data point beyond the marker gates.
# Usage: gate_noop.sh <target_file>   (ignored)
# Exit: always 0.
exit 0
