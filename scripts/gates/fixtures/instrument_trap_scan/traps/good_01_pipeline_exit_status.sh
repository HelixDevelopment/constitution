#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# GOOD: the status is captured from the command itself, no pipeline in between.
out=$(check_thing /etc/hosts)
rc=$?
printf '%s\n' "$out" | head -5
echo "checked rc=$rc"
