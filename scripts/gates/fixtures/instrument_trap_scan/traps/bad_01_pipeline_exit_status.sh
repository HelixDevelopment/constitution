#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# BAD: the exit status read after a pipeline is the pager's, not the checker's.
check_thing /etc/hosts | head -5
rc=$?
echo "checked rc=$rc"
