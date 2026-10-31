# constitution/scripts/anchors/tests/_paths.py
# Location-independent paths for the anchors tests (known_failures_v73 rank 1).
# The tests used to open the cwd-relative path "constitution/Constitution.md",
# which only exists when the cwd is a CONSUMER root that vendors the canon as
# a `constitution/` submodule. The canon file is resolved from this file's own
# location instead, so the tests run identically from the canon root, from a
# consumer root, or from any other cwd. Note: the logical prefix
# "constitution/groups/..." that the generator writes into index `location`
# fields is a fixed OUTPUT contract, not a cwd lookup, and is unchanged.
import os

CANON = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC = os.path.join(CANON, "Constitution.md")
