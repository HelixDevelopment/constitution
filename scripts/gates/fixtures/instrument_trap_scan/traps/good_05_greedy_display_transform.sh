#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# GOOD: a negated class stops at the first separator.
sed -E 's/([^:]*):([^:]*)/\1/' names.txt
