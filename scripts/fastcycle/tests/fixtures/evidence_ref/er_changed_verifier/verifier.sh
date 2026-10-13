#!/bin/sh
# CHANGED verifier -- an extra check line added after the reference was created.
echo "VERIFIER_RAN" >> "${EVREF_VERIFIER_MARKER:-/dev/null}"
echo "extra-check-not-present-at-create-time"
exit 0
