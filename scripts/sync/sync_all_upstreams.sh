#!/usr/bin/env bash
# scripts/sync/sync_all_upstreams.sh -- fetch every remote of a project and of every submodule at every
# depth, report ahead/behind/diverged/unreachable and pin state, and integrate by FAST-FORWARD only.
# Engine: scripts/sync/sync_all_upstreams.py (one file, python3 -I, standard library only).
# Documentation: docs/guides/sync_upstreams_user_guide.md, docs/manuals/sync_upstreams_manual.md,
# docs/faq/sync_upstreams_faq.md; design: docs/design/sync_all_upstreams_design.md.
#
# USAGE  sync_all_upstreams.sh (--check | --dry-run | --apply) [--root DIR] [--no-fetch] [--tags]
#          [--advance-pins [--advance-third-party]] [--strict-pins] [--own-org ORG]... [--branch main]
#          [--jobs N] [--timeout SEC] [--deadline SEC] [--max-depth N] [--out DIR] [--run-id ID]
#          [--interactive | --non-interactive] [--quiet]
#   --check    fetch every remote, report, change nothing else
#   --dry-run  no fetch, no change: report from the refs already present
#   --apply    fetch, then fast-forward repositories checked out on main; clean submodules follow
#              their new recorded gitlink; with --advance-pins own-org pins move to upstream main and
#              are STAGED in the parent (git add), never committed
# SAFETY  never pushes, commits, forces, resets, rebases or deletes; every git call is allow-listed
#   (gate scripts/gates/cm_sync_upstreams_ff_only.sh); a dirty tree, an in-progress operation or an
#   index.lock blocks that repository only; one run per project (kernel lock, no stale lock);
#   URLs without userinfo in every log; git never prompts; fetched code is never run.
# EVIDENCE  <out>/sync_report.json (schema helix.sync_upstreams/1) and <out>/sync_report.tsv; stdout
#   ends with REPORT_JSON=, CANONICAL_SHA256= (identical for identical repository states) and RESULT:.
# EXIT  0 current / applied · 1 an integration step failed · 2 usage error · 3 updates available
#   (--check, --dry-run; after --apply: something is still behind, e.g. a pin without --advance-pins or
#   a declined prompt) · 4 attention needed (diverged, unreachable, dirty, in progress, pin not on main /
#   unfetchable, root not on main, an ignored file in the way, a parent gitlink modified, upstream branch
#   gone) · 5 INCONCLUSIVE (a git call gave no answer in time: nothing about that repository is concluded)
#   · 6 BLIND (the control needle failed: the tree could not be inspected) · 7 LOCKED (another run holds
#   the lock; nothing was done)
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
exec python3 -I -B "$HERE/sync_all_upstreams.py" "$@"
