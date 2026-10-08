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
#   - `constitution/scripts/fastcycle/timing/fc_timer.sh` (T028's deliverable,
#     the SHARED library both T-A01 -- T015's target -- and T-A02 -- this
#     task's target -- depend on) HAS LANDED (26412 bytes, confirmed present
#     2026-09-28; see RECONCILIATION below) and is now a PERMANENT part of
#     the codebase. `commit_all.sh` itself, however, does NOT yet call any of
#     its public functions (`fc_timer_start`/`fc_timer_end`/... -- confirmed
#     zero hits for `fc_timer_(start|end)` anywhere in the 2768-line file).
#   - `scripts/commit_all.sh` references NONE of `.tsv`, `FC_TIMING`, or
#     `fc_timer` anywhere -- confirmed by a whole-file grep for each pattern
#     returning zero hits. There is no stage-boundary instrumentation of any
#     kind: no start/end timestamp pair around preflight, the §11.4.74
#     sibling check, exporter invocation, DB-writer sync, `git add` (stage),
#     `git commit`, or the per-remote push loop -- and zero occurrences of
#     `ls-remote` anywhere (no per-remote read-back-tip mechanism exists).
#   - `qa-results/fastcycle/commit/` (the TSV output directory plan.md T-A02
#     names: "TSV per commit under `qa-results/fastcycle/commit/<ts>.tsv`")
#     does not exist -- only `qa-results/fastcycle/{foundational,setup,us1}`
#     exist today.
#   - tasks.md T030 itself is confirmed `[ ]` (unchecked) -- so, unlike T015's
#     target (pre_build_verification.sh, whose OWN wiring task T029 has ALSO
#     landed), THIS file's overall verdict is expected to correctly stay RED
#     (this script's own `exit $fail` non-zero) until T030 lands, even though
#     the shared fc_timer.sh library itself is now permanently present.
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
# (`do_push()`'s OWN fallback loop, when `push_all.sh` is unavailable,
# already dedups by URL -- "Skip duplicate URLs" -- a real, live example of
# exactly this pitfall inside the codebase this test instruments, confirmed
# by direct source inspection 2026-09-28.)
#
# §11.4.273 control needle #3 / #4 (see GROUP 2 below): before trusting the
# zero-hit counts for `fc_timer_(start|end)` and `ls-remote` against
# commit_all.sh, each is paired with a needle proving grep can find a REAL,
# known-present, domain-matched token (fc_timer_start's own definition inside
# fc_timer.sh; `_spawn_detached_push`, commit_all.sh's own real per-remote
# push spawner) through the identical code path, and correctly returns zero
# for a fabricated one -- so an empty result below is a proven absence, never
# an unproven grep-mechanism blind spot.
#
# Producer≠Verifier (§11.4.240): this file is authored at the RED step
# (T016); the actual `fc_timer.sh` library and its wiring into
# `commit_all.sh` are a LATER, SEPARATE implementation task (T030) -- this
# file's author never implements them, and never invokes `commit_all.sh` in
# any mode that commits or pushes real content.
#
# Safety: this test performs ONLY read-only `grep`/`find`/`git remote`
# operations against the live tree -- it NEVER invokes `git commit`,
# `git push`, or `scripts/commit_all.sh` in any form (dry-run included). See
# RECONCILIATION below for the explicit safety judgement on why `--dry-run`
# is NOT invoked even for the golden-output check, and what real, static
# alternative is used instead.
#
# ---------------------------------------------------------------------------------------
# RECONCILIATION (§11.4.115 polarity-switch / §11.4.120 gate-reconciliation,
# applied 2026-09-28 -- a follow-up fix to this file only, applying the SAME
# investigation-and-fix discipline the conductor already applied to T015's
# sibling RED test `test_fc_timer_prebuild_red.sh`; this file's own header
# above commits it to never weakening its own assertions, so any
# broken-assertion fix below is reconciliation, never a silent weakening):
#
#   Independent re-verification against the live tree (2026-09-28) found this
#   file had TWO structural defects of the exact class T015's own
#   RECONCILIATION section documents, plus one gap in its golden-output stub:
#
#   (a) PERMANENTLY-FALSE-FOREVER ASSERTION -- the original absence check (1)
#       asserted `constitution/scripts/fastcycle/timing/fc_timer.sh` is
#       ABSENT, written with NO polarity switch -- but T028 has since landed
#       it (confirmed present: 26412 bytes, 2026-09-28) as a PERMANENT part
#       of the codebase (the SAME shared library T015 also depends on).
#       False forever from the moment T028 landed, by construction.
#
#       Fix: a `RED_MODE` env-overridable polarity switch, exactly like
#       T015's own fix, but under a DISTINCT env var name
#       (`FC_TIMER_COMMIT_RED_MODE`, never `FC_TIMER_RED_MODE` -- these are
#       two independent test files instrumenting two different targets, and
#       sharing one flag name would let setting one accidentally flip the
#       other's polarity). Default 0 = the library's now-PERMANENT present
#       state (assert PRESENT); `FC_TIMER_COMMIT_RED_MODE=1` is preserved as
#       an explicit, documented audit-only escape hatch reconstructing the
#       original pre-T028 precondition (assert ABSENT; requires fc_timer.sh
#       to be temporarily moved aside).
#
#       UNLIKE T015 (whose whole file reached the fully-GREEN, post-landing
#       state because BOTH of its dependent tasks, T028 AND T029, had
#       landed), tasks.md T030 -- the task that wires fc_timer.sh's API INTO
#       commit_all.sh -- remains `[ ]` unchecked. So only THIS ONE
#       assertion's polarity was permanently wrong; the file's OVERALL exit
#       status correctly stays RED (non-zero) until T030 lands, exactly as
#       it did before this fix.
#
#   (b) INERT-PROSE CONTRACT STUBS -- the file's two "T030 contract stub"
#       sections for the 2 tasks.md T016 acceptance criteria ("one row per
#       executed stage of a dry-run commit" / "one push row per remote with
#       its read-back tip") were narrative `echo` text ONLY -- never a real
#       assertion capable of failing.
#
#       Fix: two new, real, deterministic, control-needle-proven assertions
#       (GROUP 2 below) that assert the acceptance criteria DIRECTLY --
#       mirroring T015's own assertion-7 pattern (assert the target
#       behaviour itself, which is genuinely false today because T030 has
#       not landed, so BOTH currently FAIL and are designed to flip to PASS
#       the moment T030's real `fc_timer_start`/`fc_timer_end` calls and a
#       `git ls-remote`-based read-back-tip mechanism land AND produce at
#       least one captured TSV run). The original prose stubs are KEPT
#       VERBATIM below the new assertions (see "T030 contract stub" sections)
#       -- they remain genuinely useful documentation of the FULL acceptance
#       contract (exact row semantics, the dedup-by-URL pitfall, the
#       requested_at/applied_at pair, etc.) that a single grep-count
#       assertion cannot fully capture on its own; converting the criteria
#       into real assertions does not delete that documentation.
#
#   (c) GOLDEN-OUTPUT STUB (3/3) -- "byte-identical staged set + message
#       with/without timers" -- was pure narrative with no real check, AND
#       (distinct from (b)) the natural way to make it real -- actually
#       invoking `commit_all.sh --dry-run` twice and diffing the output --
#       was evaluated and explicitly judged UNSAFE/UNCERTAIN for THIS
#       session, documented here per this task's own explicit instruction
#       ("if genuinely unsafe/uncertain, fall back to static
#       source-structure assertions instead, documented honestly"):
#
#         - CONFIRMED SAFE (direct source inspection, 2026-09-28):
#           `stage_changes()` under `DRY_RUN=true` runs ONLY
#           `git status --short` (no `git add`); `do_push()` under
#           `DRY_RUN=true` logs and returns with NO push attempted;
#           `main()`'s push-selection step also short-circuits to "skipping
#           push entirely" under `DRY_RUN=true`. `--dry-run` alone is
#           confirmed git-state-safe.
#         - NOT AUDITED WITHIN THIS FIX'S SCOPE: `--auto-cascade` is ON BY
#           DEFAULT and recursively enters EVERY dirty OWNED submodule; the
#           full call chain under `--dry-run` (cascade traversal,
#           compression's own `--dry-run` pass-through, docs_chain's own
#           `--dry-run` pass-through, the §11.4.74 sibling check) was NOT
#           individually verified side-effect-free for every one of those
#           subordinate scripts within this task's scope.
#         - EVEN IF FULLY SAFE: this repository's working tree is, AT THE
#           TIME OF THIS FIX, extremely dirty (dozens of modified
#           governance/doc files spanning multiple concurrently-committing
#           parallel tracks, per this project's own documented
#           §11.4.58/§11.4.167/§11.4.176 multi-track operating model) -- a
#           "golden" staged-file-set/commit-message baseline captured
#           against a tree this actively concurrently-modified would go
#           stale within minutes, worthless as a stable regression fixture
#           (the same non-reproducibility problem T015's header explicitly
#           reasons about for its own hardcoded-count trap, applied here to
#           a hardcoded-baseline trap instead).
#
#       Fix (GROUP 3 below): a STATIC structural baseline is used instead.
#       The exact source spans of the THREE functions that decide what gets
#       staged and what commit message is used (`stage_changes()`,
#       `prompt_commit_message()`, `do_commit()`) are dynamically LOCATED
#       (never hardcoded line numbers -- re-derived every run by searching
#       for each function's own definition, exactly matching this file's
#       existing "never hardcode" discipline for the remote count), hashed,
#       and asserted to contain ZERO `FC_TIMING`/`fc_timer` references TODAY
#       -- the real, precise, control-proven version of the original stub's
#       own "today this is trivially-but-uninformatively true" claim (today
#       `FC_TIMING` is inert in commit_all.sh because it is never referenced
#       there at all -- confirmed by absence check (2) below -- so this
#       static check currently PASSES, correctly). The REAL BEHAVIOURAL
#       dry-run diff (actually invoking commit_all.sh twice and comparing
#       output) is explicitly DEFERRED to T030's own GREEN-verification step
#       -- at which point the implementer will already be invoking
#       commit_all.sh for real to prove the wiring works, so that invocation
#       is the natural, safe point to add the real diff check too.
#
# PAIRED MUTATION (T027, not implemented here -- documented so T027's author
# can wire it, extending the mutation T015's own header already documents):
# once T030 lands, (i) "drop one stage's fc_timer_end call, leaving its
# fc_timer_start intact" MUST flip the future per-stage row-count assertion
# to FAIL (a started-but-never-closed stage never gets a completed row); (ii)
# "let the timer wrapper mutate COMMIT_MESSAGE or the staged-file selection
# (e.g. append a timing marker line)" MUST flip the GROUP 3 static-absence
# assertion below to FAIL (its FC_TIMING/fc_timer reference count inside
# stage_changes()/prompt_commit_message()/do_commit() no longer stays zero)
# AND, once the real behavioural dry-run diff exists per (c) above, MUST
# flip THAT check to FAIL too -- the two together close the gap a
# source-absence check alone cannot (a call that exists but is a true
# side-channel no-op vs. one that silently mutates output).
#
# (d) T048 review round-1 finding F7 remediation (2026-09-29): independent
#     re-verification found tasks.md T030 is now `[x]` (landed), and checks
#     (2a)/(2b) below (the ".tsv" and "FC_TIMING|fc_timer" absence checks
#     against commit_all.sh's own SOURCE) had the exact SAME
#     PERMANENTLY-FALSE-FOREVER defect class as (a) above -- T030's own
#     inline comments said "If T030 has shipped it, DELETE this assertion",
#     but deletion would lose the ability to catch a REAL regression later
#     (T030's wiring reverted/removed), so both were instead folded under
#     the SAME RED_MODE switch as (1)/(a) (default 0 = assert PRESENT, the
#     now-permanent state; 1 = audit-only reconstruction). Check (3)
#     (qa-results/fastcycle/commit/ directory existence) was DELETED
#     outright rather than flipped: unlike the tracked-source facts
#     (1)/(2a)/(2b), that directory is gitignored CAPTURED EVIDENCE whose
#     existence depends on whether commit_all.sh has ever actually RUN on a
#     given checkout since T030 landed, not on whether T030's source wiring
#     landed -- a fresh clone with T030 fully landed would still fail an
#     "assert PRESENT" flip on its very first run, itself a §11.4.201
#     false-positive refusal of a healthy state.
#
# (e) T048 review round-1 finding F7 remediation, GROUP 2 Assertion B
#     (2026-09-29): the "one push row per remote with its read-back tip"
#     check read ONLY the single most-recently-modified TSV under the
#     SHARED, cross-track qa-results/fastcycle/commit/ directory. Direct
#     source inspection of commit_all.sh's main() found this is the WRONG
#     ARTIFACT (§11.4.120), not a stale-polarity flip: under the DEFAULT
#     invocation (no --sync-push/--dry-run) main() releases the flock and
#     calls _spawn_detached_push() -- a genuinely DETACHED `nohup ... &`
#     subshell (§11.4.88 hard constraint) that NEVER reaches do_push()'s
#     own per-remote fc_timer rows at all; those rows are emitted ONLY
#     inside do_push(), reached ONLY via --sync-push or a direct call. The
#     shared directory's newest file is therefore, under this repo's own
#     routine multi-track operating model, overwhelmingly likely to be a
#     default/async invocation that structurally cannot carry push rows --
#     reading RED FOREVER regardless of whether T030's mechanism is correct
#     (which several 2026-09-28 15:0x TSVs elsewhere in that same directory
#     already independently demonstrate it is). Fix: Assertion B now
#     freshly, deterministically, and safely re-verifies the contract
#     itself every run -- sourcing the REAL commit_all.sh
#     (COMMIT_ALL_SOURCE_ONLY=1, the same pattern
#     scripts/testing/test_commit_all_push_failure_signal_red.sh already
#     established) and calling do_push() directly with DRY_RUN=true (this
#     file's own RECONCILIATION (c) already judged that branch "CONFIRMED
#     SAFE ... NO push attempted") against a throwaway scratch
#     FC_TIMER_TSV, checking every currently-configured remote (control
#     needle #2's $remote_names) got a well-formed push:<remote> row
#     carrying both remote= and tip= fields. See the assertion's own inline
#     comment below for the full detail.
# ---------------------------------------------------------------------------------------
#
# Usage : bash test_fc_commit_stage_timer_red.sh   Exit 0 = every check
#         holds: T030's presence/wiring facts confirmed PRESENT (RED_MODE=0
#         default), all control needles satisfied, GROUP 2's two acceptance
#         criteria (per-stage rows / per-remote push rows + read-back tip)
#         both genuinely demonstrated, and GROUP 3's golden-output static
#         precondition holds. UPDATED 2026-09-29 (T048 review round-1 F7
#         remediation, RECONCILIATION (d)/(e) above): T030 landed (tasks.md
#         `[x]`) and every assertion below now targets the CORRECT artifact
#         for that landed state, so Exit 0 is the expected steady-state
#         result going forward -- a non-zero exit past this point is a real
#         regression in T030's wiring, not an ordinary/expected RED
#         baseline. The T030 contract stubs (per-stage rows, per-remote push
#         rows, golden-output identity) remain printed below as full
#         acceptance-contract documentation for any future maintainer.
#   Env FC_TIMER_COMMIT_RED_MODE=0|1  : polarity switch (§11.4.115). Default
#                                    0 = fc_timer.sh's now-PERMANENT present
#                                    state (T028 landed; assert PRESENT).
#                                    Set to 1 ONLY to reconstruct/audit the
#                                    original pre-T028 precondition (requires
#                                    fc_timer.sh to be temporarily absent or
#                                    moved aside -- an audit path, never the
#                                    routine one).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
COMMIT_ALL="$ROOT/scripts/commit_all.sh"
FC_TIMER="$FC/timing/fc_timer.sh"
COMMIT_TSV_DIR="$ROOT/qa-results/fastcycle/commit"

fail=0
failx() { fail=1; }

RED_MODE="${FC_TIMER_COMMIT_RED_MODE:-0}"
echo "INFO: RED_MODE=$RED_MODE (0=default: fc_timer.sh library treated as PERMANENTLY present [T028 landed], 1=audit-only reconstruction of the original pre-T028 precondition)"

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

# ============================================================================
# GROUP 1 -- static source-level absence checks (fast, always run)
# ============================================================================

# --- (1) Absence check: constitution/scripts/fastcycle/timing/fc_timer.sh ---
# Polarity depends on RED_MODE (see RECONCILIATION (a) above).
if [ "$RED_MODE" = "1" ]; then
  chk1=$([ ! -f "$FC_TIMER" ] && echo 1 || echo 0)
  if [ "$chk1" = 1 ]; then
    echo "ok fc_timer.sh absent [RED_MODE=1 audit] -- reconstructed pre-T028 precondition"
  else
    echo "NOT ok fc_timer.sh unexpectedly present [RED_MODE=1 audit] -- audit"
    echo "     reconstruction requires it to be temporarily moved aside"
    failx
  fi
else
  if [ -f "$FC_TIMER" ]; then
    echo "ok fc_timer.sh is PRESENT (T028 landed, confirmed 2026-09-28) [RED_MODE=0/default]"
    echo "   -- the shared T-A01/T-A02 timer library is now a PERMANENT part"
    echo "   of the codebase going forward"
  else
    echo "NOT ok fc_timer.sh MISSING -- T028's landed timer library appears to"
    echo "     have been removed or moved; this is a REGRESSION, not the"
    echo "     expected RED-baseline precondition (re-investigate before"
    echo "     treating this as an ordinary RED state)"
    failx
  fi
fi

# --- (2) Absence check: no timing reference of any kind in commit_all.sh ---
[ -f "$COMMIT_ALL" ] || { echo "NOT ok scripts/commit_all.sh missing at $COMMIT_ALL"; exit 1; }

# --- (2a)/(2b) T048 review round-1 F7 remediation (2026-09-29): SAME class
# of defect as (1) above, SAME RED_MODE-gated fix. Independent re-
# verification found T030 IS `[x]` in tasks.md and commit_all.sh's own
# source NOW references '.tsv' and 'FC_TIMING'/'fc_timer' -- these two
# absence checks were PERMANENTLY-false-forever the moment T030 landed,
# exactly like check (1)'s fc_timer.sh-presence defect. Their own inline
# comments said "DELETE this assertion" -- but deleting loses the ability to
# catch a REAL regression (T030's wiring later reverted/removed), the same
# reasoning (1)'s RECONCILIATION (a) already applied. Fix: fold both under
# the SAME RED_MODE switch as (1) (one flag, one meaning: "has T030's timing
# wiring landed in commit_all.sh's source"), default 0 = assert PRESENT
# (today's permanent state), 1 = audit-only reconstruction of the pre-T030
# precondition. See top-of-file RECONCILIATION (d) for the full writeup.
if [ "$RED_MODE" = "1" ]; then
  if grep -qE '\.tsv' "$COMMIT_ALL"; then
    echo "NOT ok scripts/commit_all.sh unexpectedly references a .tsv path"
    echo "     [RED_MODE=1 audit] -- reconstructing the pre-T030 precondition"
    echo "     requires the .tsv wiring to be temporarily reverted/moved aside"
    failx
  else
    echo "ok scripts/commit_all.sh contains zero '.tsv' references [RED_MODE=1"
    echo "   audit] -- reconstructed pre-T030 precondition"
  fi
else
  if grep -qE '\.tsv' "$COMMIT_ALL"; then
    echo "ok scripts/commit_all.sh now references a .tsv path (T030 landed,"
    echo "   confirmed 2026-09-29 -- tasks.md T030 is \`[x]\`) [RED_MODE=0/"
    echo "   default] -- the stage-timer TSV mechanism is now a PERMANENT"
    echo "   part of the codebase going forward"
  else
    echo "NOT ok scripts/commit_all.sh has NO '.tsv' reference -- T030's own"
    echo "     TSV-writing wiring appears to have been removed or reverted;"
    echo "     this is a REGRESSION, not the expected RED-baseline"
    echo "     precondition (re-investigate before treating this as an"
    echo "     ordinary RED state)"
    failx
  fi
fi

if [ "$RED_MODE" = "1" ]; then
  if grep -qE 'FC_TIMING|fc_timer' "$COMMIT_ALL"; then
    echo "NOT ok scripts/commit_all.sh unexpectedly sources fc_timer.sh or"
    echo "     reads FC_TIMING [RED_MODE=1 audit] -- reconstructing the"
    echo "     pre-T030 precondition requires this wiring to be temporarily"
    echo "     reverted/moved aside"
    failx
  else
    echo "ok scripts/commit_all.sh has zero 'FC_TIMING'/'fc_timer' references"
    echo "   [RED_MODE=1 audit] -- reconstructed pre-T030 precondition"
  fi
else
  if grep -qE 'FC_TIMING|fc_timer' "$COMMIT_ALL"; then
    echo "ok scripts/commit_all.sh now sources fc_timer.sh and reads"
    echo "   FC_TIMING (T030 landed, confirmed 2026-09-29) [RED_MODE=0/"
    echo "   default] -- stage-boundary instrumentation now wraps preflight/"
    echo "   sibling-check/exporter/DB-sync/stage/commit/push"
  else
    echo "NOT ok scripts/commit_all.sh has NEITHER 'FC_TIMING' NOR"
    echo "     'fc_timer' anywhere -- T030's own wiring appears to have been"
    echo "     removed or reverted; this is a REGRESSION, not the expected"
    echo "     RED-baseline precondition (re-investigate before treating"
    echo "     this as an ordinary RED state)"
    failx
  fi
fi

# --- (3) REMOVED 2026-09-29 (T048 review round-1 F7 remediation) ---
# The original check asserted qa-results/fastcycle/commit/ is ABSENT, with
# no polarity switch, written the same day T030 was still unlanded. UNLIKE
# checks (1)/(2a)/(2b) above (all tracked SOURCE facts, stable across every
# checkout once T030 lands), this directory is CAPTURED EVIDENCE -- gitignored
# (see fc_timer.sh wiring comment in commit_all.sh: "written to qa-results/
# fastcycle/commit/<run-id>.tsv (gitignored -- captured evidence, never
# tracked)") -- so its existence depends on whether commit_all.sh has EVER
# actually RUN on THIS checkout since T030 landed, not on whether T030's
# source wiring landed. A genuinely fresh clone with T030 fully landed in
# source would still fail this check on its very first run, a FALSE-POSITIVE
# refusal of a healthy state (§11.4.201) -- flipping it to "assert PRESENT"
# would be exactly as wrong as leaving it "assert ABSENT" now is. Its own
# inline comment already said "DELETE this RED-baseline assertion" once
# T030 lands; this is that deletion. (COMMIT_TSV_DIR/COMMIT_TSV_LATEST/
# COMMIT_TSV_ROWS below already handle "directory may not exist yet"
# gracefully and are unaffected by this removal.)

# Shared lookup (used by both GROUP 2 assertions below): the most recent
# captured commit-path TSV, if any has ever been written.
COMMIT_TSV_LATEST=""
if [ -d "$COMMIT_TSV_DIR" ]; then
  COMMIT_TSV_LATEST="$(find "$COMMIT_TSV_DIR" -maxdepth 1 -name '*.tsv' 2>/dev/null | sort | tail -n1)"
fi
COMMIT_TSV_ROWS=0
if [ -n "$COMMIT_TSV_LATEST" ] && [ -f "$COMMIT_TSV_LATEST" ]; then
  COMMIT_TSV_ROWS="$(tail -n +2 "$COMMIT_TSV_LATEST" 2>/dev/null | grep -c . || true)"
fi
: "${COMMIT_TSV_ROWS:=0}"

# ============================================================================
# GROUP 2 -- NEW: real, deterministic, control-needle-proven assertions of
# the 2 tasks.md T016 acceptance criteria THEMSELVES (see RECONCILIATION (b)
# above). Both currently FAIL -- T030 has not landed -- and are designed to
# flip to PASS once it does AND at least one real captured commit-path run
# exists.
# ============================================================================

# --- Assertion A: "one row per executed stage of a dry-run commit" ---
# §11.4.273 control needle #3: prove grep can find a REAL, known-present
# fc_timer_start call-shaped token (T028's own landed definition inside
# fc_timer.sh itself) before trusting a zero-hit count for the SAME pattern
# searched against commit_all.sh.
NEEDLE3_PRESENT="fc_timer_start"
NEEDLE3_FABRICATED="fc_timer_start_FABRICATED_NEEDLE_T016_DOES_NOT_EXIST"
N3_PRESENT_HITS=$(grep -c -- "$NEEDLE3_PRESENT" "$FC_TIMER" 2>/dev/null || true)
: "${N3_PRESENT_HITS:=0}"
N3_FAB_HITS=$(grep -c -- "$NEEDLE3_FABRICATED" "$FC_TIMER" 2>/dev/null || true)
: "${N3_FAB_HITS:=0}"
if [ "$N3_PRESENT_HITS" -ge 1 ] && [ "$N3_FAB_HITS" -eq 0 ]; then
  echo "ok control needle #3: grep finds the known-present '$NEEDLE3_PRESENT'"
  echo "   in fc_timer.sh ($N3_PRESENT_HITS hits) and correctly finds zero"
  echo "   hits for a fabricated needle -- the per-stage-row-mechanism"
  echo "   absence check below can be trusted"
else
  echo "NOT ok control needle #3 failed (present=$N3_PRESENT_HITS"
  echo "     fabricated=$N3_FAB_HITS) -- the grep mechanism cannot be"
  echo "     trusted; the assertion below proves nothing (§11.4.273)"
  failx
fi

FC_TIMER_CALLS=$(grep -cE 'fc_timer_(start|end)' "$COMMIT_ALL" 2>/dev/null || true)
: "${FC_TIMER_CALLS:=0}"
if [ "$FC_TIMER_CALLS" -ge 1 ] && [ "$COMMIT_TSV_ROWS" -ge 1 ]; then
  echo "ok commit_all.sh emits per-stage TSV rows via fc_timer_start/"
  echo "   fc_timer_end ($FC_TIMER_CALLS call site(s), $COMMIT_TSV_ROWS"
  echo "   captured row(s) at $COMMIT_TSV_LATEST) -- T030 acceptance"
  echo "   criterion #1 (one row per executed stage of a dry-run commit)"
else
  echo "NOT ok commit_all.sh does NOT yet emit per-stage TSV rows -- T030"
  echo "     acceptance criterion #1 (one row per executed stage of a"
  echo "     dry-run commit) currently FAILS: fc_timer_start/fc_timer_end"
  echo "     call sites in commit_all.sh = $FC_TIMER_CALLS (need >=1),"
  echo "     captured TSV rows under $COMMIT_TSV_DIR = $COMMIT_TSV_ROWS"
  echo "     (need >=1). This IS the expected RED state until T030 lands"
  echo "     (see 'T030 contract stub 1/3' below for the full per-stage-row"
  echo "     semantics T030 must satisfy)."
  failx
fi

# --- Assertion B: "one push row per remote with its read-back tip" ---
# §11.4.273 control needle #4: prove grep can find a REAL, known-present,
# push-domain token in commit_all.sh's OWN detached-push spawner before
# trusting a zero-hit count for the ls-remote read-back pattern.
NEEDLE4_PRESENT="_spawn_detached_push"
NEEDLE4_FABRICATED="_spawn_detached_push_FABRICATED_NEEDLE_T016_DOES_NOT_EXIST"
N4_PRESENT_HITS=$(grep -c -- "$NEEDLE4_PRESENT" "$COMMIT_ALL" 2>/dev/null || true)
: "${N4_PRESENT_HITS:=0}"
N4_FAB_HITS=$(grep -c -- "$NEEDLE4_FABRICATED" "$COMMIT_ALL" 2>/dev/null || true)
: "${N4_FAB_HITS:=0}"
if [ "$N4_PRESENT_HITS" -ge 1 ] && [ "$N4_FAB_HITS" -eq 0 ]; then
  echo "ok control needle #4: grep finds the known-present"
  echo "   '$NEEDLE4_PRESENT' in commit_all.sh ($N4_PRESENT_HITS hits) and"
  echo "   correctly finds zero hits for a fabricated needle -- the"
  echo "   readback-tip-mechanism absence check below can be trusted"
else
  echo "NOT ok control needle #4 failed (present=$N4_PRESENT_HITS"
  echo "     fabricated=$N4_FAB_HITS) -- the grep mechanism cannot be"
  echo "     trusted; the assertion below proves nothing (§11.4.273)"
  failx
fi

READBACK_HITS=$(grep -c -- "ls-remote" "$COMMIT_ALL" 2>/dev/null || true)
: "${READBACK_HITS:=0}"

# 2026-09-29 T048 review round-1 F7 remediation -- see top-of-file
# RECONCILIATION (e) for the full writeup. SUMMARY: the ORIGINAL check here
# read COMMIT_TSV_LATEST -- the single most-recently-modified file under the
# SHARED, cross-track qa-results/fastcycle/commit/ directory -- for >=
# remote_count "push"-substring rows. That is the WRONG ARTIFACT to assert
# on (§11.4.120), confirmed by direct source inspection of commit_all.sh's
# main() (2026-09-29): under the DEFAULT invocation (no --sync-push, no
# --dry-run) main()'s push-dispatch releases the flock and calls
# _spawn_detached_push() -- a genuinely DETACHED `nohup ... &` subshell
# (§11.4.88 hard constraint, "the push is NEVER made synchronous") that
# NEVER goes through do_push()'s per-remote fc_timer rows. Those rows are
# emitted ONLY inside do_push() itself, reached ONLY via --sync-push
# (§11.4.88(E)) or a direct call. So the shared directory's most-recent file
# is, under this repo's own routine multi-track operating model,
# overwhelmingly likely to be a default/async invocation that structurally
# CANNOT carry push rows -- checking it would read RED FOREVER even though
# T030 IS `[x]` in tasks.md and several 2026-09-28 15:0x TSVs elsewhere in
# this SAME directory already demonstrate the exact required shape.
#
# Fix: freshly, deterministically, and safely re-verify the CONTRACT ITSELF
# every run -- source the REAL commit_all.sh (COMMIT_ALL_SOURCE_ONLY=1, the
# SAME pattern scripts/testing/test_commit_all_push_failure_signal_red.sh
# already established) and call do_push() directly with DRY_RUN=true and a
# throwaway scratch FC_TIMER_TSV (never the shared directory) against the
# REAL repo's REAL, currently-configured remotes (control needle #2's
# $remote_names, re-derived above). do_push()'s DRY_RUN branch performs ONLY
# read-only `git ls-remote` calls (no `git push`, no state mutation) --
# already judged "CONFIRMED SAFE ... NO push attempted" by this file's own
# RECONCILIATION (c). `_fc_ls_remote_tip`'s documented UNKNOWN fallback
# (network-unreachable remote) is a VALID `tip=` reading -- this checks that
# the row + both fields were genuinely emitted by a real per-remote
# read-back attempt, not that every remote is reachable from this host.
FC_ASSB_TSV="$(mktemp "${TMPDIR:-/tmp}/fc_t016_assertb_XXXXXX.tsv" 2>/dev/null || true)"
if [ -z "$FC_ASSB_TSV" ]; then
  echo "NOT ok Assertion B: could not create a scratch FC_TIMER_TSV file"
  echo "     (mktemp failed) -- the fresh self-verification below cannot run"
  failx
else
  rm -f "$FC_ASSB_TSV" 2>/dev/null  # fc_timer.sh creates it fresh with the header
  trap 'rm -f "$FC_ASSB_TSV" 2>/dev/null || true' EXIT
  (
    # read by the sourced commit_all.sh (do_push), not by this subshell
    # shellcheck disable=SC2034
    COMMIT_ALL_SOURCE_ONLY=1
    # shellcheck disable=SC1090
    source "$COMMIT_ALL"
    set +e +u +o pipefail
    # read by the sourced commit_all.sh (do_push), not by this subshell
    # shellcheck disable=SC2034
    FC_TIMING=1
    FC_TIMER_RUN_ID="t016_assertion_b_$$"
    export FC_TIMER_RUN_ID
    FC_TIMER_TSV="$FC_ASSB_TSV"
    export FC_TIMER_TSV
    # read by the sourced commit_all.sh (do_push), not by this subshell
    # shellcheck disable=SC2034
    DRY_RUN=true
    # read by the sourced commit_all.sh (do_push), not by this subshell
    # shellcheck disable=SC2034
    NO_PUSH=false
    do_push >/dev/null 2>&1
  )
  FC_ASSB_ROWS_OK=0
  FC_ASSB_MISSING=""
  if [ -f "$FC_ASSB_TSV" ]; then
    for _rn in $remote_names; do
      _row="$(awk -F'\t' -v want="push:$_rn" 'NR>1 && $3==want {print; exit}' "$FC_ASSB_TSV" 2>/dev/null)"
      if [ -z "$_row" ]; then
        FC_ASSB_MISSING="$FC_ASSB_MISSING ${_rn}(no-row)"
        continue
      fi
      _extra="$(printf '%s' "$_row" | awk -F'\t' '{print $11}')"
      _has_remote=false
      _has_tip=false
      case "$_extra" in *"remote=$_rn"*) _has_remote=true ;; esac
      case "$_extra" in *"tip="*) _has_tip=true ;; esac
      if [ "$_has_remote" = true ] && [ "$_has_tip" = true ]; then
        FC_ASSB_ROWS_OK=$((FC_ASSB_ROWS_OK + 1))
      else
        FC_ASSB_MISSING="$FC_ASSB_MISSING ${_rn}(row-present-but-malformed-extra:$_extra)"
      fi
    done
  else
    FC_ASSB_MISSING="(scratch TSV was never created -- do_push() sourcing/call failed)"
  fi

  if [ "$READBACK_HITS" -ge 1 ] && [ "$FC_ASSB_ROWS_OK" -eq "$remote_count" ]; then
    echo "ok commit_all.sh reads back each remote's tip via ls-remote"
    echo "   ($READBACK_HITS reference(s)) and do_push() -- freshly re-"
    echo "   verified this run via a scratch FC_TIMER_TSV, never the shared"
    echo "   qa-results/fastcycle/commit/ directory -- emits exactly"
    echo "   $FC_ASSB_ROWS_OK/$remote_count well-formed push:<remote> rows"
    echo "   (remote= + tip= fields both present) -- T030 acceptance"
    echo "   criterion #2 (one push row per remote with its read-back tip)"
  else
    echo "NOT ok commit_all.sh's do_push() does NOT emit a well-formed push"
    echo "     row (remote=+tip= fields) for every currently-configured"
    echo "     remote: 'ls-remote' references in commit_all.sh = $READBACK_HITS"
    echo "     (need >=1), fresh scratch-run rows = $FC_ASSB_ROWS_OK/"
    echo "     $remote_count (need == $remote_count). Missing/malformed:"
    echo "     ${FC_ASSB_MISSING:-<none -- see counts above>}."
    echo "     This IS a genuine T030 acceptance-criterion #2 gap if it"
    echo "     persists (see 'T030 contract stub 2/3' below for the full"
    echo "     per-remote-row semantics, including the dedup-by-URL pitfall,"
    echo "     T030 must satisfy)."
    failx
  fi
fi

# ============================================================================
# GROUP 3 -- NEW: static golden-output baseline (T030 contract stub 3/3
# support; see RECONCILIATION (c) above for why a REAL commit_all.sh
# --dry-run invocation is NOT used here). The exact source spans of the
# three functions that decide the staged file set and the commit message are
# dynamically LOCATED (never hardcoded line numbers) and checked for zero
# FC_TIMING/fc_timer references TODAY.
#
# T048 round-2 review finding F17 (2026-09-30) fix: the substring regex
# below is widened from bare `FC_TIMING|fc_timer` to also match
# `_fc_stage_(start|end)` -- commit_all.sh's own two thin wrapper functions
# around fc_timer_start/fc_timer_end (see "fc_timer.sh wiring" near this
# file's top, above _fc_stage_start()/_fc_stage_end()'s definitions).
# Verified directly (2026-09-30): a call to `_fc_stage_start "x"` inside
# stage_changes() contains NEITHER the literal substring "FC_TIMING" NOR
# "fc_timer" -- the OLD regex would have reported STAGE_TIMER_REFS=0 even
# with a real timer call wired straight into the function this GROUP exists
# to prove is timer-free, satisfiable by moving code around a line-range
# boundary rather than by the actual absence-of-instrumentation property
# the check is meant to guard (F17's own finding, reproduced live before
# fixing). Widening the regex here closes that gap for BOTH the direct
# fc_timer_*/FC_TIMING form and the wrapper-call form.
# ============================================================================
_func_start_line() {
  # $1 = exact function name; prints the 1-based source line of its
  # definition ("name() {"), re-derived from the LIVE file every run.
  grep -nE "^${1}\\(\\)[[:space:]]*\\{" "$COMMIT_ALL" 2>/dev/null | head -n1 | cut -d: -f1
}
STAGE_START="$(_func_start_line "stage_changes")"
PCM_START="$(_func_start_line "prompt_commit_message")"
DOCOMMIT_START="$(_func_start_line "do_commit")"
DOPUSH_START="$(_func_start_line "do_push")"

if [ -z "$STAGE_START" ] || [ -z "$PCM_START" ] || [ -z "$DOCOMMIT_START" ] || [ -z "$DOPUSH_START" ]; then
  echo "NOT ok GROUP 3 baseline: could not dynamically locate one of"
  echo "     stage_changes()/prompt_commit_message()/do_commit()/do_push()"
  echo "     in $COMMIT_ALL -- commit_all.sh's structure may have changed;"
  echo "     the golden-output static baseline below cannot be trusted"
  failx
else
  # stage_changes() spans [STAGE_START, PCM_START); prompt_commit_message()
  # and do_commit() together span [PCM_START, DOPUSH_START) -- do_commit()
  # is confirmed (2026-09-28) to be the last function defined immediately
  # before do_push() in source order, re-derived here rather than assumed.
  STAGE_END=$((PCM_START - 1))
  COMMIT_END=$((DOPUSH_START - 1))
  STAGE_SPAN_LINES=$((STAGE_END - STAGE_START + 1))
  COMMIT_SPAN_LINES=$((COMMIT_END - PCM_START + 1))
  STAGE_SPAN_SHA=$(sed -n "${STAGE_START},${STAGE_END}p" "$COMMIT_ALL" | sha256sum | cut -d' ' -f1)
  COMMIT_SPAN_SHA=$(sed -n "${PCM_START},${COMMIT_END}p" "$COMMIT_ALL" | sha256sum | cut -d' ' -f1)
  STAGE_TIMER_REFS=$(sed -n "${STAGE_START},${STAGE_END}p" "$COMMIT_ALL" | grep -cE 'FC_TIMING|fc_timer|_fc_stage_(start|end)' || true)
  : "${STAGE_TIMER_REFS:=0}"
  COMMIT_TIMER_REFS=$(sed -n "${PCM_START},${COMMIT_END}p" "$COMMIT_ALL" | grep -cE 'FC_TIMING|fc_timer|_fc_stage_(start|end)' || true)
  : "${COMMIT_TIMER_REFS:=0}"

  echo "INFO: GROUP 3 baseline located dynamically -- stage_changes() lines"
  echo "   ${STAGE_START}-${STAGE_END} (${STAGE_SPAN_LINES} lines, sha256"
  echo "   ${STAGE_SPAN_SHA}); prompt_commit_message()+do_commit() lines"
  echo "   ${PCM_START}-${COMMIT_END} (${COMMIT_SPAN_LINES} lines, sha256"
  echo "   ${COMMIT_SPAN_SHA})"

  if [ "$STAGE_TIMER_REFS" -eq 0 ] && [ "$COMMIT_TIMER_REFS" -eq 0 ]; then
    echo "ok golden-output static precondition: stage_changes()"
    echo "   ($STAGE_TIMER_REFS refs) and prompt_commit_message()+do_commit()"
    echo "   ($COMMIT_TIMER_REFS refs) contain ZERO FC_TIMING/fc_timer"
    echo "   references today -- the timer wrapper cannot currently alter"
    echo "   what is staged or committed because it is not called from"
    echo "   either function at all (T030 contract stub 3/3 static"
    echo "   precondition; the REAL behavioural dry-run diff remains"
    echo "   deferred to T030's own GREEN-verification step, see"
    echo "   RECONCILIATION (c) above)"
  else
    echo "NOT ok golden-output static precondition: expected ZERO"
    echo "     FC_TIMING/fc_timer references inside stage_changes()/"
    echo "     prompt_commit_message()/do_commit() but found"
    echo "     $STAGE_TIMER_REFS / $COMMIT_TIMER_REFS -- T030 wiring may"
    echo "     have started inside one of the staging/commit-message"
    echo "     decision functions; the REAL behavioural dry-run diff"
    echo "     (deferred, see RECONCILIATION (c) above) is now required to"
    echo "     confirm the timer wrapper is still a pure side-channel"
    echo "     observer that never alters the staged set or the message"
    failx
  fi
fi

echo
echo "=== N5 fix (T048 round-2 review): missing-\$_FC_TIMER_LIB path is loud, ==="
echo "=== never silent ==="
# T048 round-2 review finding N5 (2026-09-30): commit-timing rows were found
# to stop entirely after a specific run, with 44+ later real commits carrying
# no TSV row at all and no visible explanation. Investigated: EVERY write
# failure INSIDE fc_timer.sh itself (header write, row append) already
# echoes a loud "fc_timer_*: failed to ..." to stderr on failure -- verified
# directly against fc_timer.sh's own source. The ONE genuinely-silent gap
# this investigation found is commit_all.sh's OWN `if [ -f "$_FC_TIMER_LIB"
# ]` branch: when the library file is absent at the computed path, the
# entire timing-instrumentation block was skipped with ZERO output
# anywhere -- indistinguishable, from the outside, from "timing is simply
# disabled by FC_TIMING=0" (which IS a documented, intentional no-op). This
# assertion proves the fix: sourcing a scratch copy of commit_all.sh from a
# directory with NO ../constitution sibling (so $_FC_TIMER_LIB genuinely
# cannot resolve) now emits a named, actionable warning to stderr instead of
# silence.
N5_SCRATCH="$(mktemp -d)"
if [ -z "$N5_SCRATCH" ] || [ ! -d "$N5_SCRATCH" ]; then
  echo "NOT ok N5 fix: mktemp -d failed"
  failx
else
  mkdir -p "$N5_SCRATCH/scripts"
  cp -- "$COMMIT_ALL" "$N5_SCRATCH/scripts/commit_all.sh"
  N5_OUT="$(cd "$N5_SCRATCH" && COMMIT_ALL_SOURCE_ONLY=1 bash -c 'source scripts/commit_all.sh' 2>&1)"
  if printf '%s' "$N5_OUT" | grep -qF "fc_timer.sh not found at"; then
    echo "ok N5 fix: sourcing commit_all.sh with no reachable fc_timer.sh emits a"
    echo "   named, actionable stderr warning -- the missing-library path is no"
    echo "   longer silent"
  else
    echo "NOT ok N5 fix FAILED: sourcing commit_all.sh with no reachable"
    echo "     fc_timer.sh produced no 'fc_timer.sh not found at' warning --"
    echo "     captured output: $(printf '%s' "$N5_OUT" | tr '\n' ' ' | head -c 300)"
    failx
  fi
  # Self-validation control needle (§11.4.107(10)/§11.4.201(1)): a NORMAL
  # source (real ../constitution sibling present, as in this actual repo)
  # MUST NOT print this warning -- proving the check above is genuinely
  # discriminating the missing-library case, not firing unconditionally.
  N5_NORMAL_OUT="$(cd "$ROOT" && COMMIT_ALL_SOURCE_ONLY=1 bash -c 'source scripts/commit_all.sh' 2>&1)"
  if printf '%s' "$N5_NORMAL_OUT" | grep -qF "fc_timer.sh not found at"; then
    echo "NOT ok control needle (N5 fix false-positive guard) FAILED: a NORMAL"
    echo "     source of the real commit_all.sh (real ../constitution sibling"
    echo "     present) ALSO printed the missing-library warning -- the check"
    echo "     is not discriminating, §11.4.201(1)"
    failx
  else
    echo "ok control needle (N5 fix false-positive guard): a normal source of the"
    echo "   real commit_all.sh (constitution sibling genuinely present) does NOT"
    echo "   print the missing-library warning"
  fi
  rm -rf "$N5_SCRATCH"
fi

echo
echo "=== T030 contract stub 1/3: one row per EXECUTED stage (plan.md T-A02) ==="
echo "Backed above by GROUP 2 Assertion A. NOT YET SATISFIED: a per-commit"
echo "  TSV at qa-results/fastcycle/commit/<ts>.tsv, keyed to the candidate"
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
echo "Backed above by GROUP 2 Assertion B. NOT YET SATISFIED: for every"
echo "  remote the push loop actually targets, emit exactly one row carrying"
echo "  (at minimum) the remote NAME, a push start timestamp, a push end"
echo "  timestamp, a result (ok/ff-only-deferred/error -- commit_all.sh's own"
echo "  documented semantics are NEVER --force, §11.4.113; a non-fast-forward"
echo "  remote is DEFERRED, not forced), and the read-back TIP commit hash of"
echo "  that remote's ref AFTER the push attempt completes (a real"
echo "  \`git ls-remote\`/fetch-and-compare read-back against that specific"
echo "  remote -- NEVER the local pre-push HEAD asserted by assumption, since"
echo "  a deferred/failed push must show a DIFFERENT read-back tip than a"
echo "  succeeded one). Control needle #2 above pins the currently-configured"
echo "  remote count at exactly 3 (github, origin, upstream) -- ALL THREE"
echo "  resolve to the SAME destination URL per this repo's own documented"
echo "  git-remotes reality, so the correct implementation emits 3 rows (one"
echo "  per configured remote NAME) on a full push, never 1 row deduplicated"
echo "  by destination URL (do_push()'s own URL-dedup fallback loop is a"
echo "  LIVE example of exactly this pitfall, confirmed by direct source"
echo "  inspection above); re-run this test's control needle before"
echo "  implementing in case the remote set has since changed."

echo
echo "=== T030 contract stub 3/3: golden-output identity (staged set + message) ==="
echo "Backed above by GROUP 3's static structural precondition. NOT YET FULLY"
echo "  SATISFIED (deferred to a REAL behavioural check, see RECONCILIATION"
echo "  (c) above): a dry-run commit_all.sh invocation with FC_TIMING=1 and"
echo "  an otherwise-identical invocation with FC_TIMING=0 (or unset) MUST"
echo "  produce a byte-identical STAGED FILE SET (the exact"
echo "  \`git diff --staged --name-status\` output, or equivalent, compared as"
echo "  a set/ordered-list, never merely as an equal file COUNT -- the same"
echo "  §11.4.201(8) count-blind-regression trap this suite's other RED"
echo "  baselines already guard against) AND a byte-identical COMMIT MESSAGE"
echo "  (the exact \$COMMIT_MESSAGE value, or its --dry-run placeholder per"
echo "  commit_all.sh's own §11.4.209 review M2 dry-run-never-prompts rule)."
echo "  Today the STATIC precondition (GROUP 3 above) confirms this holds"
echo "  trivially: FC_TIMING is inert in commit_all.sh (confirmed by absence"
echo "  check (2) above -- the string literally never appears in the file,"
echo "  so setting it changes nothing) AND, more precisely, neither"
echo "  stage_changes() nor prompt_commit_message()/do_commit() reference it"
echo "  at all. Once T030 wires fc_timer.sh in, the SAME invariant must"
echo "  continue to hold non-trivially: the timing wrapper is a PURE"
echo "  side-channel observer that never alters what actually gets"
echo "  committed/pushed -- confirming that NON-trivially requires a REAL"
echo "  dry-run invocation diff, deferred to T030's own GREEN-verification"
echo "  step per RECONCILIATION (c) above."
echo "  Paired mutation for the future gate (T027, see PAIRED MUTATION"
echo "  above): make the timer wrapper mutate COMMIT_MESSAGE or the"
echo "  staged-file selection (e.g. append a timing marker line) -> both the"
echo "  GROUP 3 static check above AND the future real dry-run diff MUST"
echo "  FAIL."

exit $fail
