#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# GOOD: count the matches and compare the count with zero.
n=$(grep -c 'forbidden' input.txt)
[ "$n" -eq 0 ] && echo clean
