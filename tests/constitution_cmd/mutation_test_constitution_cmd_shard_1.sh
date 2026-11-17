#!/usr/bin/env bash
# tests/constitution_cmd/mutation_test_constitution_cmd_shard_1.sh - full-suite unit: shard 1 of 4 of
# tests/constitution_cmd/mutation_test_constitution_cmd.sh (the baseline and the mutants i with (i - 1) mod 4 == 0).
# The 48 mutants are split into four units so that each stays under the suite runner's default per-unit limit of 900 s,
# which the pull-request CI uses; the shard checks that all four wrappers exist and are manifest entries.
set -uo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mutation_test_constitution_cmd.sh" --shard 1/4
