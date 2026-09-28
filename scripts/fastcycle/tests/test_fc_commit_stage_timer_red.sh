#!/bin/bash
# Purpose : T016 (SpecKit-004 "fast-dev-cycles", User Story 1) RED baseline for
#           the T-A02 commit-path/exporter/DB-writer/lock/push stage-timer
#           mechanism -- proves `scripts/commit_all.sh` (the ONLY sanctioned
#           commit/push wrapper, §2.1/§11.4.113) has NO per-stage timing/row
#           emission mechanism today, and documents the exact contract the
#           later, separate implementation task (T030, which wires
#           `constitution/scripts/fastcycle/timing/fc_timer.sh` into
#           `commit_all.sh` and `sync_all_markdown_exports.sh`) must satisfy.
#
# THE GAP (verified directly against the real source, 2026-09-28):
#   - `constitution/scripts/fastcycle/timing/` exists as a directory but is
#     EMPTY -- `fc_timer.sh` (plan.md Project Structure, line 171: "section/
#     stage timer library (T-A01, T-A02)") does not exist anywhere in this
#     tree. It is a SHARED library both T-A01 (pre-build section timers,
#     T015's RED test) and T-A02 (this task's commit-path timers) depend on;
#     neither has landed it.
#   - `scripts/commit_all.sh` (2768 lines) references NONE of `.tsv`,
#     `FC_TIMING`, or `fc_timer` anywhere -- confirmed by a whole-file grep for
#     each pattern returning zero hits. There is no stage-boundary
#     instrumentation of any kind: no start/end timestamp pair around
#     preflight, the §11.4.74 sibling check, exporter invocation, DB-writer
#     sync, `git add` (stage), `git commit`, or the per-remote push loop.
#   - `qa-results/fastcycle/commit/` (the TSV output directory plan.md T-A02
#     names: "TSV per commit under `qa-results/fastcycle/commit/<ts>.tsv`")
#     does not exist -- only `qa-results/fastcycle/{foundational,setup,us1}`
#     exist today.
#   - Nuance (§11.4.6, stated precisely rather than over-claimed): a lock-WAIT
#     mechanism already exists in `commit_all.sh` -- the index-lock retry loop
#     keyed off `INDEX_LOCK_WAIT_SECS` (around line 1671) genuinely measures a
#     wait via `date +%s` (line 173) and decides live-held vs stale via §11.4.180
#     staleness rules -- but it is an internal control-flow decision only; it
#     writes its wait duration and reaped/not-reaped verdict to NOWHERE
#     durable (no row, no TSV, no log line keyed to a fingerprint). The
#     UNDERLYING timeable fact (how long a lock wait took, whether it reaped)
#     is therefore real and already computed transiently, but not yet
#     recorded -- the identical shape of gap T017's header describes for
#     `meta_test_false_positive_proof.sh`'s scratch-dir `.rc` files.
#
# §11.4.273 control needle #1 (relative-path mechanism): before trusting any
# "absent" finding below, prove this test's own `$FC/...` path construction
# genuinely resolves paths relative to this script's real location, by first
# confirming a KNOWN-PRESENT sibling (`lib/fc_common.sh`, the shell twin of
# the C-001..C-007 machinery every other file in this suite sources)
# resolves true. A wrong relative-path computation would make every file in
# the tree -- present or absent -- look identical.
#
# §11.4.273 control needle #2 (remote-count fact): the T-A02 contract requires
# "one push row per remote with its read-back tip" (tasks.md T016). Rather
# than GUESS how many remotes a future implementation must emit rows for
# (§11.4.6), this test queries the REAL, currently-configured `git remote`
# list of the live checkout and asserts it matches the count this repo's own
# CLAUDE.md documents as fact ("Configured reality ... three remote NAMES,
# ONE destination URL"): exactly 3 named remotes (github, origin, upstream),
# all resolving to the SAME destination. This is pinned as a concrete,
# re-checkable fact for T030's implementer: the per-remote-row mechanism MUST
# emit one row per configured remote NAME (3 today on this checkout), never
# deduplicated down to one row per distinct destination URL -- three remote
# names sharing one URL is a documented, intentional configuration here
# (§2.1's "multi-upstream push is the norm"), and a naive URL-keyed
# implementation would silently under-report by 2/3 of the required rows.
#
# Producer≠Verifier (§11.4.240): this file is authored at the RED step
# (T016); the actual `fc_timer.sh` library and its wiring into
# `commit_all.sh` are a LATER, SEPARATE implementation task (T030) -- this
# file's author never implements them, and never invokes `commit_all.sh` in
# any mode that commits or pushes real content.
#
# Safety: this test performs ONLY read-only `grep`/`find`/`git remote`
# operations against the live tree -- it NEVER invokes `git commit`,
# `git push`, or `scripts/commit_all.sh` in any form (dry-run included), per
# the task's explicit instruction that a RED test proving absence need not,
# and here does not, exercise the wrapper it is instrumenting.
#
# Usage : bash test_fc_commit_stage_timer_red.sh   Exit 0 = RED baseline
#         holds (absence proven + both control needles satisfied) and the
#         T030 contract stubs (per-stage rows, per-remote push rows, golden-
#         output identity) are printed for the future implementer.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
COMMIT_ALL="$ROOT/scripts/commit_all.sh"

fail=0
failx() { fail=1; }

# --- §11.4.273 control needle #1: prove the relative-path mechanism works ---
KNOWN_PRESENT="$FC/lib/fc_common.sh"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so every absence check below proves"
  echo "     nothing (§11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.sh) resolves"
  echo "   through this test's own path construction -- the absence checks"
  echo "   below can be trusted"
fi

# --- §11.4.273 control needle #2: prove the real, current remote count/set ---
remote_names=$(git -C "$ROOT" remote 2>/dev/null | sort)
remote_count=$(printf '%s\n' "$remote_names" | grep -c . || true)
if [ "$remote_count" -ne 3 ]; then
  echo "NOT ok control needle #2: expected exactly 3 configured git remotes"
  echo "     (github, origin, upstream per this repo's own documented"
  echo "     git-remotes reality) but found $remote_count: $(printf '%s' "$remote_names" | tr '\n' ' ')"
  echo "     -- the 'one row per remote' contract stub below cites a stale"
  echo "     count; re-verify against \`git remote -v\` before implementing."
  failx
else
  echo "ok control needle #2: exactly 3 git remotes configured today"
  echo "   ($(printf '%s' "$remote_names" | tr '\n' ',' | sed 's/,$//')) --"
  echo "   the per-remote push-row contract stub below is pinned to this"
  echo "   real, re-checked count, never a guessed one (§11.4.6)"
fi

# --- (1) Absence check: constitution/scripts/fastcycle/timing/fc_timer.sh ---
FC_TIMER="$FC/timing/fc_timer.sh"
if [ -f "$FC_TIMER" ]; then
  echo "NOT ok timing/fc_timer.sh now exists -- the shared T-A01/T-A02 timer"
  echo "     library has landed. DELETE this RED-baseline assertion; check"
  echo "     whether test_fc_commit_stage_timer_red.sh's absence checks below"
  echo "     (the actual commit_all.sh wiring) still hold."
  failx
else
  echo "ok timing/fc_timer.sh absent today (confirmed 2026-09-28) -- the"
  echo "   shared section/stage timer library plan.md names for T-A01+T-A02"
  echo "   has not yet landed"
fi

# --- (2) Absence check: no timing reference of any kind in commit_all.sh ---
[ -f "$COMMIT_ALL" ] || { echo "NOT ok scripts/commit_all.sh missing at $COMMIT_ALL"; exit 1; }

if grep -qE '\.tsv' "$COMMIT_ALL"; then
  echo "NOT ok scripts/commit_all.sh now references a .tsv path -- the stage-"
  echo "     timer TSV mechanism this RED baseline pins as absent may have"
  echo "     landed. If T030 has shipped it, DELETE this assertion."
  failx
else
  echo "ok scripts/commit_all.sh (2768 lines) contains zero '.tsv' references"
  echo "   -- confirmed absent today (2026-09-28)"
fi

if grep -qE 'FC_TIMING|fc_timer' "$COMMIT_ALL"; then
  echo "NOT ok scripts/commit_all.sh now sources fc_timer.sh or reads"
  echo "     FC_TIMING -- re-check whether the absence this RED baseline"
  echo "     pins still holds"
  failx
else
  echo "ok scripts/commit_all.sh has zero 'FC_TIMING' or 'fc_timer'"
  echo "   references anywhere -- no stage-boundary instrumentation of any"
  echo "   kind wraps preflight/sibling-check/exporter/DB-sync/stage/commit/"
  echo "   push today"
fi

# --- (3) Absence check: qa-results/fastcycle/commit/ output directory ---
COMMIT_TSV_DIR="$ROOT/qa-results/fastcycle/commit"
if [ -d "$COMMIT_TSV_DIR" ]; then
  echo "NOT ok qa-results/fastcycle/commit/ now exists -- the TSV output"
  echo "     directory plan.md T-A02 names may already be in use. If T030"
  echo "     has landed, DELETE this RED-baseline assertion."
  failx
else
  echo "ok qa-results/fastcycle/commit/ absent today (confirmed 2026-09-28) --"
  echo "   only qa-results/fastcycle/{foundational,setup,us1} exist; no"
  echo "   per-commit TSV has ever been written"
fi

echo
echo "=== T030 contract stub 1/3: one row per EXECUTED stage (plan.md T-A02) ==="
echo "NOT YET IMPLEMENTED: a per-commit TSV at"
echo "  qa-results/fastcycle/commit/<ts>.tsv, keyed to the candidate"
echo "  fingerprint (git HEAD) and a run id, MUST carry exactly one row per"
echo "  stage of \`commit_all.sh\` that ACTUALLY RAN for that invocation --"
echo "  never a fixed row count, since a dry-run/aborted/--no-push invocation"
echo "  executes a strict SUBSET of the full stage list. The full stage set"
echo "  (plan.md T-A02 work item + T030's implementation task, both verified"
echo "  directly against this contract): preflight, §11.4.74 sibling check,"
echo "  each exporter render (one row PER DOCUMENT, PER FORMAT -- not one row"
echo "  per exporter invocation), each tracker-writer request (with BOTH a"
echo "  requested_at and a separate applied_at field), stage (git add), each"
echo "  lock acquisition (wait duration in ms/s + a reaped yes/no boolean,"
echo "  covering the ALREADY-EXISTING INDEX_LOCK_WAIT_SECS retry loop this"
echo "  file's header documents as currently transient/unrecorded), commit"
echo "  (git commit), each docs_chain rebaseline, and the per-remote push"
echo "  loop (contract stub 2/3 below). A stage that did not execute this run"
echo "  MUST NOT appear as a row -- appearing-but-zero-duration is NOT the"
echo "  same as absent, and a future gate must be able to tell the two apart."

echo
echo "=== T030 contract stub 2/3: one push row PER REMOTE + read-back tip ==="
echo "NOT YET IMPLEMENTED: for every remote the push loop actually targets,"
echo "  emit exactly one row carrying (at minimum) the remote NAME, a push"
echo "  start timestamp, a push end timestamp, a result (ok/ff-only-deferred/"
echo "  error -- commit_all.sh's own documented semantics are NEVER --force,"
echo "  §11.4.113; a non-fast-forward remote is DEFERRED, not forced), and the"
echo "  read-back TIP commit hash of that remote's ref AFTER the push attempt"
echo "  completes (a real \`git ls-remote\`/fetch-and-compare read-back against"
echo "  that specific remote -- NEVER the local pre-push HEAD asserted by"
echo "  assumption, since a deferred/failed push must show a DIFFERENT"
echo "  read-back tip than a succeeded one). Control needle #2 above pins the"
echo "  currently-configured remote count at exactly 3 (github, origin,"
echo "  upstream) -- ALL THREE resolve to the SAME destination URL per this"
echo "  repo's own documented git-remotes reality, so the correct"
echo "  implementation emits 3 rows (one per configured remote NAME) on a"
echo "  full push, never 1 row deduplicated by destination URL; re-run this"
echo "  test's control needle before implementing in case the remote set has"
echo "  since changed."

echo
echo "=== T030 contract stub 3/3: golden-output identity (staged set + message) ==="
echo "NOT YET IMPLEMENTED: a dry-run commit_all.sh invocation with"
echo "  FC_TIMING=1 and an otherwise-identical invocation with FC_TIMING=0"
echo "  (or unset) MUST produce a byte-identical STAGED FILE SET (the exact"
echo "  \`git diff --staged --name-status\` output, or equivalent, compared as"
echo "  a set/ordered-list, never merely as an equal file COUNT -- the same"
echo "  §11.4.201(8) count-blind-regression trap this suite's other RED"
echo "  baselines already guard against) AND a byte-identical COMMIT MESSAGE"
echo "  (the exact \$COMMIT_MESSAGE value, or its --dry-run placeholder per"
echo "  commit_all.sh's own §11.4.209 review M2 dry-run-never-prompts rule)."
echo "  Today this is trivially-but-uninformatively true: FC_TIMING is inert"
echo "  in commit_all.sh (confirmed by absence check (2) above -- the string"
echo "  literally never appears in the file, so setting it changes nothing)."
echo "  Once T030 wires fc_timer.sh in, the SAME invariant must continue to"
echo "  hold non-trivially: the timing wrapper is a PURE side-channel"
echo "  observer that never alters what actually gets committed/pushed."
echo "  Paired mutation for the future gate: make the timer wrapper mutate"
echo "  COMMIT_MESSAGE or the staged-file selection (e.g. append a timing"
echo "  marker line) -> this golden-output check MUST FAIL."

exit $fail
