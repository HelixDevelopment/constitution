#!/bin/sh
# sibling_search_check.sh - SiblingSearchArtefact validator (spec-004
# "fast-dev-cycles", plan.md T-D03; tasks.md T096; contract
# closure-refusal.md CR-004; data-model.md §6.4; FR-011, SC-004).
#
# Guarded by the shell half of
# constitution/scripts/fastcycle/tests/test_sibling_search_check_red.sh
# (T088), driven through the shared triple_harness.sh runner (C-005) over
# the 5 fixtures under tests/fixtures/sibling_search_check/.
#
# CLI contract (per tests/fixtures/sibling_search_check/README.md, the RED
# test's own binding definition -- no contracts/*.md file names an exact
# argv shape for this tool; that README's "Assumed CLI contract" section
# is the source of truth alongside this file's own header):
#
#   sibling_search_check.sh <artefact.json>
#
# Reads the single positional <artefact.json> path and validates it as an
# already-produced SiblingSearchArtefact record (data-model.md §6.4)
# against the schema documented in the README above -- this tool does NOT
# itself re-run search_method; it validates the artefact's OWN
# self-reported fields:
#   - class_statement is present and non-empty;
#   - search_method is present and non-empty;
#   - control_needle is present and non-empty, AND control_needle_found is
#     true -- a null/empty instances_found without a PROVEN control_needle
#     is never evidence (plan.md T-D03's own wording; §11.4.201(7)(b) /
#     §11.4.273(f): "a null without a needle is not evidence");
#   - every instances_found[] entry carries a location and a disposition
#     from the DEC-20 closed set: fixed-here / tracked-as <ItemId>
#     (matching this project's canonicalIDRe,
#     constitution/scripts/workable-items/cmd/workable-items/crud.go:25,
#     ^[A-Z]{3,}-[0-9A-Za-z]+$) / proven-not-an-instance.
#
# Exit codes (C-001 as this tool's own fixtures/sibling_search_check/README.md
# section concretises them):
#   0  the artefact is VALID (ACCEPTED)
#   1  a FINDING -- the artefact is present but INVALID; every offending
#      field/record is named on stdout, one "FINDING: ..." line each (the
#      triple_harness.sh C-005 whole-token name-matching rule governs
#      which literal word each golden-bad*/expected fixture requires)
#   2  usage error -- no <artefact.json> argument was given at all (a bare
#      CLI-shape problem; see the exit-4 note below for why "file does not
#      exist" is NOT classified here)
#   3  (unused by this tool -- it validates an already-produced artefact's
#      self-reported fields; it performs no control-needle proof-of-life
#      check of its OWN at runtime, so it has no self-test to fail)
#   4  BLIND -- the artefact file could not be read at all: missing,
#      unreadable, a directory, or not valid JSON.
#
# §11.4.6 design note on the exit-2-vs-exit-4 split (UNCONFIRMED by any
# RED-test assertion -- none of T088's 5 fixtures exercises exit 2/3/4,
# only golden-good/negative-control [exit 0] and the 3 golden-bad classes
# [exit 1] are driven through triple_harness.sh; documented transparently
# here rather than left an unstated guess, open to correction by a future
# contract): common-conventions.md's own C-001 table lists "evidence file
# missing" as an explicit EXIT-4 example ("4 | BLIND: a required input
# could not be read (remote unreachable, DB locked, evidence file
# missing)"), so a <artefact.json> path that does not resolve to a
# readable file is classified as BLIND -- a property of the ARTEFACT under
# validation -- never as exit-2 usage error, which is reserved here for
# the CLI-argument-shape failure (no path given at all / wrong argument
# count).
#
# Producer != Verifier (§11.4.240): this tool only validates a
# SiblingSearchArtefact that some other producer (a Bug-closure caller,
# per CR-004) already wrote; it never fabricates, searches for, or
# completes one on the caller's behalf.

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

if [ $# -ne 1 ]; then
    echo "sibling_search_check.sh: usage: sibling_search_check.sh <artefact.json>" >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "sibling_search_check.sh: python3 not found on PATH -- cannot validate the artefact" >&2
    exit 2
fi

exec python3 "$HERE/lib/sibling_search_validate.py" "$1"
