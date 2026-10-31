#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# GOOD: the predicate takes a fixed stamp computed once by the caller.
STAMP="2026-01-01 00:00:00"
find . -type f -newermt "$STAMP" -print
