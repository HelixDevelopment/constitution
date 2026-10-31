#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# BAD: -q combined with -v answers 'is there ANY non-matching line', not 'is the pattern absent'.
if grep -qv 'forbidden' input.txt; then echo clean; fi
