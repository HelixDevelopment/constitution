#!/bin/sh
# Toy change "chg-C" (the seeded batch culprit): targets widget_c.sh; its
# real runtime output contains the literal token BROKEN. This is the ONLY
# bad change in the T056 batch fixtures -- bisection must name exactly this
# one, never chg-A or chg-B, and applying it alone must FAIL the gate
# identically to applying it inside any batch that also contains chg-A
# and/or chg-B (each targets a distinct file, so they never collide).
echo "COMPONENT-C: BROKEN (chg-C applied)"
