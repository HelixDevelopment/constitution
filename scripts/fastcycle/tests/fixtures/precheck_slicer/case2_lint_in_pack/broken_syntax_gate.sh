#!/bin/sh
# T061 case-2 fixture: a genuine, planted PARSE error (unclosed `if`).
# This is deliberately real, not a description of one -- `sh -n` / `bash -n`
# against this exact file must fail for real (confirmed by this RED test's
# own Section B before any claim is made about the absent precheck_pack.sh).
echo "before the broken block"
if [ -f "/tmp/does-not-matter" ]; then
    echo "unreachable branch, syntax is broken before we get here"
# NOTE: deliberately no `fi` -- this is the planted defect.
echo "trailing statement, never parses"
