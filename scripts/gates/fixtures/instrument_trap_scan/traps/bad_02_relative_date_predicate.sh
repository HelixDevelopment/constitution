#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# BAD: a relative date inside -newermt is read relative to the moment of the run.
find . -type f -newermt "yesterday" -print
