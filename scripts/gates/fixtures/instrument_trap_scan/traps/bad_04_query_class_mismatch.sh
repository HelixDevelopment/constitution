#!/bin/sh
# Fixture for CM-INSTRUMENT-TRAP-SCAN (shipped with the canon so the gate can prove it sees; never executed).
# BAD: the certified query uses alternation (-E) but the needle that vouches for it is a fixed-string count.
grep -E 'alpha|beta' data.txt
hits=$(grep -c 'needle' data.txt)
echo "$hits"
