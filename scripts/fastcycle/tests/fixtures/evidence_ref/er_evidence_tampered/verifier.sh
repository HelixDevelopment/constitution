#!/bin/sh
# T108 fixture verifier stub -- writes a marker file so the forward-
# compatible invocation block (once T117 lands) can prove `consume`
# NEVER invokes this while `reverify` DOES. Deliberately trivial:
# always exits 0, PASS.
echo "VERIFIER_RAN" >> "${EVREF_VERIFIER_MARKER:-/dev/null}"
exit 0
