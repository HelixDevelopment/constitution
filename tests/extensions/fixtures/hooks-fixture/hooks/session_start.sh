#!/usr/bin/env bash
# TEST FIXTURE hook. The extension engine never executes this file; if it ever did,
# the marker below would appear in the sandbox and tests/extensions/test_security.sh fails.
touch "${CONSTITUTION_EXT_FIXTURE_MARKER:-/nonexistent/fixture-marker}" 2>/dev/null
exit 0
