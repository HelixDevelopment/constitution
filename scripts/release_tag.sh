#!/usr/bin/env bash
# scripts/release_tag.sh — create the §11.4.151 prefixed release tag.
#   usage: bash scripts/release_tag.sh <version>     # e.g. 1.0.0-dev-0.0.1
# Produces an annotated tag "<PREFIX>-<version>" where <PREFIX> comes ONLY from
# scripts/release_prefix.sh (no prefix literal lives here). The SAME invocation
# is run in the main repo and in EVERY owned submodule so one release shares one
# prefix (§11.4.151) and fans out to every upstream (§2.1, never force-push §11.4.113).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="${1:?usage: release_tag.sh <version>   e.g. 1.0.0-dev-0.0.1}"
prefix="$("$here/release_prefix.sh")"          # decoupled resolution
tag="${prefix}-${version}"

# Preconditions enforced by caller/CI BEFORE this runs: §11.4.40 full-suite GREEN
# + §11.4.113 merged onto latest main. This script only does naming + tag create.
git tag -a "$tag" -m "Release $tag"
printf 'created tag: %s\n' "$tag"
printf 'fan-out (§2.1): git push origin "%s"   # origin pushes to every upstream\n' "$tag"
