#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# BAD: a greedy group in a display transform eats everything up to the LAST separator.
sed -E 's/(.*):(.*)/\1/' names.txt
