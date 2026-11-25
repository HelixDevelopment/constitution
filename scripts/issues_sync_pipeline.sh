#!/usr/bin/env bash
# scripts/issues_sync_pipeline.sh -- THE facade of the bidirectional workable-items <-> Issues pipeline (anchor §11.4.300; operator decision 2026-11-25),
# bound to the Docs Chain context `issues-sync` (templates/docs_chain/issues-sync.yaml).
# Usage: issues_sync_pipeline.sh <subcommand> [options]
#   plan        outbound dry-run: what each tracker leg would receive (no write)             [wraps scripts/issue_sync.sh plan]
#   apply       outbound write: needs --apply AND config mode: apply + apply_decision; refuses while a tracker edit is not yet preserved as a proposal
#   pull        inbound: tracker comments/new issues/conflicts -> reviewable proposal files in docs/issues_sync/inbound/ (dry-run; --write writes files)
#   reconcile   report DB-vs-tracker differences; a tracker edit of a synced issue is a CONFLICT (the database wins; never applied inbound)
#   verify      read-only 0 in sync / 1 drift / 2 cannot determine                                [wraps scripts/verify_issues_sync.sh semantics]
#   run         the whole chain through Docs Chain: doctor + verify (read-only); with --write: docs_chain sync + pull --write + verify
#   init-context --root DIR [--owner-repo H/O/R] [--write]   install the Docs Chain context template (never overwrites)
# Shared options (as issue_sync.sh): --config F --db F --owner-repo H/O/R [--db-repo H/O/R] --target H/O/R ... [--out-dir D] [--json] [--write] [--apply]
# Exit: 0 ok / disabled (default OFF), 1 drift, conflict or refusal, 2 cannot determine (no token, unreachable host, unverified capability, comments unreadable); 2 is never a pass.
# Tokens are read by variable NAME from the caller's environment (or the 0600 ~/api_keys.sh, parsed never sourced) and are never printed.
# Docs Chain calls it as an exec transform (`--docs-chain-exec stage <name> ...`); that internal form writes only the staged output file.
# Side-effects: pull --write and init-context --write create files; apply writes trackers only as stated. Dependencies: bash, python3, PyYAML (+ docs_chain for `run`).
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}"
if [ "${1:-}" = "--prove-failure" ]; then exec python3 -W ignore -m issue_sync.prove_pipeline; fi
exec python3 -W ignore -m issue_sync.pipeline "$@"
