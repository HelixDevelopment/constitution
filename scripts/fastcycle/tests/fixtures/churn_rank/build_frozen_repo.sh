#!/bin/sh
# =============================================================================
# T090 fixture builder (SpecKit-004 "fast-dev-cycles", User Story 3; plan.md
# T-D05; see fixtures/churn_rank/README.md).
# =============================================================================
#
# Purpose: deterministically construct, from scratch, a small git repository
# with a FIXED, reproducible commit history -- fixed author/committer
# identity, fixed GIT_AUTHOR_DATE/GIT_COMMITTER_DATE per commit (never "now"),
# fixed content, fixed commit messages -- so that two independent invocations
# of this script, into two separate empty target directories, produce
# COMMIT-SHA-IDENTICAL repositories. This is the "frozen history" the
# test_churn_rank_red.sh determinism scenario (plan T-D05's "Protecting
# tests: determinism of the ranking on a frozen history") is built against.
#
# The repo has 5 files, each with a distinct, exact, hand-chosen commit
# count: file_a.txt=1, file_b.txt=2, file_c.txt=3, file_d.txt=5, file_e.txt=8.
#
# Usage: sh build_frozen_repo.sh <empty-or-nonexistent-target-dir>
# Exit 0 on success; nonzero and a message on stderr on failure (e.g. target
# dir already exists and is non-empty).
#
# This script is itself a fixture, not the tool under test (churn_rank.py,
# T099, a separate later task) -- it never invokes churn_rank.py.
# =============================================================================

set -eu

TARGET="${1:?usage: build_frozen_repo.sh <empty-or-nonexistent-target-dir>}"

if [ -e "$TARGET" ]; then
    if [ -d "$TARGET" ] && [ -z "$(ls -A "$TARGET" 2>/dev/null)" ]; then
        : # empty dir, fine
    else
        echo "build_frozen_repo.sh: $TARGET already exists and is not an empty directory -- refusing to overwrite" >&2
        exit 1
    fi
else
    mkdir -p "$TARGET"
fi

cd "$TARGET"
git init -q .
git config user.name "Fastcycle Fixture"
git config user.email "fixture@fastcycle.invalid"
git config commit.gpgsign false
git config core.autocrlf false

# fixed_commit <file> <content> <message> <iso-date-no-tz>
# Date is always rendered with an explicit +0000 offset so the resulting
# commit is byte-identical regardless of the host's local timezone or
# locale (§11.4.6 -- never let an unstated environmental default leak into
# a claimed-frozen artefact).
fixed_commit() {
    file="$1"
    content="$2"
    message="$3"
    date_no_tz="$4"
    printf '%s\n' "$content" > "$file"
    git add "$file"
    GIT_AUTHOR_NAME="Fastcycle Fixture" \
    GIT_AUTHOR_EMAIL="fixture@fastcycle.invalid" \
    GIT_AUTHOR_DATE="${date_no_tz} +0000" \
    GIT_COMMITTER_NAME="Fastcycle Fixture" \
    GIT_COMMITTER_EMAIL="fixture@fastcycle.invalid" \
    GIT_COMMITTER_DATE="${date_no_tz} +0000" \
        git commit -q -m "$message"
}

# file_a.txt -- exactly 1 commit
fixed_commit file_a.txt "a1" "file_a: initial (fixture)" "2020-01-01 12:00:00"

# file_b.txt -- exactly 2 commits
fixed_commit file_b.txt "b1" "file_b: initial (fixture)" "2020-01-02 12:00:00"
fixed_commit file_b.txt "b2" "file_b: update 1 (fixture)" "2020-01-03 12:00:00"

# file_c.txt -- exactly 3 commits
fixed_commit file_c.txt "c1" "file_c: initial (fixture)" "2020-01-04 12:00:00"
fixed_commit file_c.txt "c2" "file_c: update 1 (fixture)" "2020-01-05 12:00:00"
fixed_commit file_c.txt "c3" "file_c: update 2 (fixture)" "2020-01-06 12:00:00"

# file_d.txt -- exactly 5 commits
fixed_commit file_d.txt "d1" "file_d: initial (fixture)" "2020-01-07 12:00:00"
fixed_commit file_d.txt "d2" "file_d: update 1 (fixture)" "2020-01-08 12:00:00"
fixed_commit file_d.txt "d3" "file_d: update 2 (fixture)" "2020-01-09 12:00:00"
fixed_commit file_d.txt "d4" "file_d: update 3 (fixture)" "2020-01-10 12:00:00"
fixed_commit file_d.txt "d5" "file_d: update 4 (fixture)" "2020-01-11 12:00:00"

# file_e.txt -- exactly 8 commits (the frozen repo's "high-churn" file --
# used only for the mechanism self-check / determinism scenario, NOT the
# real ATM-277 top-decile needle, which is measured against the live
# project repositories, not this synthetic one).
fixed_commit file_e.txt "e1" "file_e: initial (fixture)" "2020-01-12 12:00:00"
fixed_commit file_e.txt "e2" "file_e: update 1 (fixture)" "2020-01-13 12:00:00"
fixed_commit file_e.txt "e3" "file_e: update 2 (fixture)" "2020-01-14 12:00:00"
fixed_commit file_e.txt "e4" "file_e: update 3 (fixture)" "2020-01-15 12:00:00"
fixed_commit file_e.txt "e5" "file_e: update 4 (fixture)" "2020-01-16 12:00:00"
fixed_commit file_e.txt "e6" "file_e: update 5 (fixture)" "2020-01-17 12:00:00"
fixed_commit file_e.txt "e7" "file_e: update 6 (fixture)" "2020-01-18 12:00:00"
fixed_commit file_e.txt "e8" "file_e: update 7 (fixture)" "2020-01-19 12:00:00"

exit 0
