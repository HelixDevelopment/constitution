#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# GOOD: the needle runs through the same dialect as the certified query.
grep -E 'alpha|beta' data.txt
hits=$(grep -Ec 'needle|alpha' data.txt)
echo "$hits"
