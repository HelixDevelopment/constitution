#!/bin/sh
# Toy gate for T056's batch_bisect corpus. Genuinely EXECUTES every
# widget_*.sh in the tree directory passed as $1 and inspects REAL runtime
# output -- never greps patch/source TEXT (T050's own authoring lesson,
# §11.4.201(7)(a): grepping source text false-matches a patch's own
# removal/description comment; this gate runs each file and checks what it
# PRINTS).
#
# FAIL if ANY widget_*.sh's real stdout contains "BROKEN". PASS otherwise.
# Prints one line per component so a caller (or a human) can see which
# component(s) actually failed -- the toy corpus's per-change model is:
# one "change" = one widget_<id>.sh file swapped for a variant.
set -u
TREE="${1:?usage: gate.sh <tree-dir>}"
RC=0
for f in "$TREE"/widget_*.sh; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .sh)
    OUT=$(sh "$f" 2>&1)
    if printf '%s\n' "$OUT" | grep -q BROKEN; then
        echo "GATE-FAIL($name): $OUT"
        RC=1
    else
        echo "GATE-PASS($name): $OUT"
    fi
done
exit $RC
