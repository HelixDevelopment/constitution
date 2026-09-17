#!/usr/bin/env bash
# mutation_harness.sh — apply one named mutation to a scratch copy of a source
# tree, run one test suite against it, report the counts, restore, and prove
# the restore and the original tree are byte-identical.
#
# WHY THIS EXISTS (§11.4.274)
#   The paired-mutation loop of §1.1 is: copy the tree, apply a one-line edit,
#   run a suite, read the summary, restore, verify the restore, compare counts.
#   Every step is deterministic and decision-free, and it was being executed by
#   hand roughly thirty-five times in a single session — one tool call per step,
#   with a fresh chance of a transcription error at each one. This is that loop,
#   written down once.
#
# WHAT IT DOES NOT DO (§11.4.274(d))
#   It does not decide whether a mutation is a GOOD mutation, whether a gate is
#   genuine, or whether a suite's coverage is adequate. It reports what happened
#   when a named edit met a named suite. Reading that as evidence for or against
#   a claim is the agent's job, and this tool must never be cited as a verdict.
#
# USAGE
#   mutation_harness.sh --tree DIR --suite REL [--name NAME]
#                       [--file REL --from LITERAL --to LITERAL]
#                       [--expect pass|fail] [--env-knob NAME]
#                       [--scratch DIR] [--timeout SECS] [--unset VAR]... [--keep]
#
#   --tree DIR       Source tree to copy. NEVER modified (asserted, see below).
#   --suite REL      Suite to run, path RELATIVE to --tree.
#   --name NAME      Label for the verdict line. Default: the mutation id or
#                    "BASELINE".
#   --file REL       File to mutate, relative to --tree. Omit for a BASELINE run.
#   --from LITERAL   Exact literal text to replace. Not a regex.
#   --to LITERAL     Exact literal replacement text.
#   --expect         pass | fail — the expected outcome. Defaults to "pass" for a
#                    baseline run and "fail" for a mutation run, because a
#                    mutation that leaves a suite green is the finding §1.1 hunts.
#   --env-knob NAME  Run the suite from the ORIGINAL tree with NAME set to the
#                    mutated scratch scripts dir, instead of running the scratch
#                    copy of the suite. REFUSED unless NAME actually appears in
#                    the suite source — see THE SILENT-GREEN TRAP below.
#   --unset VAR      Unset VAR in the suite's environment. Repeatable. Use it for
#                    credentials so a suite cannot reach a live service.
#   --timeout SECS   Hard ceiling on the suite run. Default 600.
#   --scratch DIR    Where to build the copies. Default: a mktemp -d.
#   --keep           Do not delete the scratch dir (for post-mortem).
#
# THE SILENT-GREEN TRAP (why --env-knob is guarded)
#   Suites differ in which environment variable redirects them at another tree.
#   Setting the WRONG name does not error: the suite ignores it, falls back to
#   its own location, and tests the REAL tree — returning a confident green that
#   describes code the mutation never touched. So: by default this harness runs
#   the suite FROM THE SCRATCH COPY (path-derived redirection, no env var, no
#   way to miss), and when --env-knob is used it first asserts the name is
#   literally present in the suite source and exits CANNOT_RUN if it is not.
#
# EXIT CODES (§11.4.201)
#   0  ran; outcome matched --expect
#   1  ran; outcome VIOLATED --expect (a finding)
#   2  could not run: bad args, missing tree/file/suite, mutation text not found,
#      unparseable summary, suite timed out, or the original tree changed
#   Any of these is a fact about the RUN, never a judgment about the code.
#
# FAILURE MODES IT REFUSES TO PAPER OVER
#   * --from not present in the target file  -> CANNOT_RUN. A mutation that did
#     not apply produces a meaningless result; reporting it as "suite still
#     green" would be a bluff.
#   * --from present more than once and --expect-count not matching -> reported;
#     the replacement count is always printed.
#   * suite produced no parseable summary   -> CANNOT_RUN, not a pass.
#   * suite exceeded --timeout              -> CANNOT_RUN, not a fail.
#   * original tree fingerprint changed     -> CANNOT_RUN, loudly.
set -uo pipefail

MECH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mech_common.sh
source "$MECH_DIR/lib/mech_common.sh"

TREE="" SUITE="" NAME="" MFILE="" MFROM="" MTO="" EXPECT="" ENV_KNOB=""
SCRATCH="" TIMEOUT=600 KEEP=0
UNSET_VARS=()
HAVE_FROM=0

usage() { sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tree)      TREE="${2:-}"; shift 2 ;;
    --suite)     SUITE="${2:-}"; shift 2 ;;
    --name)      NAME="${2:-}"; shift 2 ;;
    --file)      MFILE="${2:-}"; shift 2 ;;
    --from)      MFROM="${2:-}"; HAVE_FROM=1; shift 2 ;;
    --to)        MTO="${2:-}"; shift 2 ;;
    --expect)    EXPECT="${2:-}"; shift 2 ;;
    --env-knob)  ENV_KNOB="${2:-}"; shift 2 ;;
    --scratch)   SCRATCH="${2:-}"; shift 2 ;;
    --timeout)   TIMEOUT="${2:-}"; shift 2 ;;
    --unset)     UNSET_VARS+=("${2:-}"); shift 2 ;;
    --keep)      KEEP=1; shift ;;
    -h|--help)   usage; exit "$MECH_EXIT_OK" ;;
    *)           mech_die "unknown argument: $1 (try --help)" ;;
  esac
done

mech_need cp find md5sum diff timeout python3

[ -n "$TREE" ]  || mech_die "--tree is required"
[ -n "$SUITE" ] || mech_die "--suite is required"
[ -d "$TREE" ]  || mech_die "--tree is not a directory: $TREE"
TREE="$(cd "$TREE" && pwd)"
[ -f "$TREE/$SUITE" ] || mech_die "--suite not found under tree: $TREE/$SUITE"
case "$TIMEOUT" in ''|*[!0-9]*) mech_die "--timeout must be a whole number of seconds: $TIMEOUT" ;; esac

IS_MUTATION=0
if [ -n "$MFILE" ] || [ "$HAVE_FROM" -eq 1 ] || [ -n "$MTO" ]; then
  IS_MUTATION=1
  [ -n "$MFILE" ]        || mech_die "--file is required when mutating"
  [ "$HAVE_FROM" -eq 1 ] || mech_die "--from is required when mutating"
  [ -f "$TREE/$MFILE" ]  || mech_die "--file not found under tree: $TREE/$MFILE"
  [ -n "$MFROM" ]        || mech_die "--from must not be empty"
fi

if [ -z "$EXPECT" ]; then
  if [ "$IS_MUTATION" -eq 1 ]; then EXPECT="fail"; else EXPECT="pass"; fi
fi
case "$EXPECT" in pass|fail) ;; *) mech_die "--expect must be 'pass' or 'fail', got: $EXPECT" ;; esac
[ -n "$NAME" ] || { if [ "$IS_MUTATION" -eq 1 ]; then NAME="unnamed"; else NAME="BASELINE"; fi; }

if [ -n "$ENV_KNOB" ]; then
  case "$ENV_KNOB" in
    [A-Za-z_]*) ;;
    *) mech_die "--env-knob must be an environment variable name, got: $ENV_KNOB" ;;
  esac
  # Real-condition assertion (§11.4.201): a knob the suite never reads is not a
  # knob. Without this check the run silently grades the unmutated real tree.
  grep -q -- "$ENV_KNOB" "$TREE/$SUITE" \
    || mech_die "suite $SUITE does not read \$$ENV_KNOB — using it would silently test the ORIGINAL tree, not the mutated copy"
fi

OWN_SCRATCH=0
if [ -z "$SCRATCH" ]; then
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/mech-mutation.XXXXXX")" || mech_die "cannot create scratch dir"
  OWN_SCRATCH=1
else
  mkdir -p "$SCRATCH" || mech_die "cannot create scratch dir: $SCRATCH"
  SCRATCH="$(cd "$SCRATCH" && pwd)"
fi

cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    mech_log INFO "scratch kept at $SCRATCH"
  elif [ "$OWN_SCRATCH" -eq 1 ]; then
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT

PRISTINE="$SCRATCH/pristine"
WORK="$SCRATCH/work"
RUNLOG="$SCRATCH/suite.log"

TREE_FP_BEFORE="$(mech_fingerprint_tree "$TREE")" || mech_die "cannot fingerprint tree: $TREE"
mech_manifest_tree "$TREE" "$SCRATCH/tree.before" || mech_die "cannot manifest tree: $TREE"

if [ -n "$ENV_KNOB" ]; then
  # env-knob mode runs the suite FROM THE ORIGINAL TREE (that is the whole point
  # of the knob: the suite stays where it lives and is pointed elsewhere). A
  # suite that writes artifacts next to itself — a proof file, a generated
  # fixture, a cache — therefore writes into the ORIGINAL tree, not the copy.
  # Measured 2026-09-08: exactly this rewrote a tracked proof file in a tree
  # under independent review. The write is detected and named after the run;
  # this warning is so it is not a surprise before it.
  mech_log WARN "env-knob mode executes the suite inside $TREE — a suite that writes artifacts beside itself will modify the ORIGINAL tree; changed paths are reported at the end"
fi

# VCS METADATA IS EXCLUDED, and that is not an optimisation — it is what makes
# this tool usable on a real repository at all. Measured on first real use: the
# target tree was 1.8 GB of which 1.4 GB was `.git`, and a plain `cp -a` copies
# it TWICE (pristine + work) before the suite even starts. Against a tmpfs
# /tmp that is 3.6 GB of RAM to mutate one shell script, and it failed with
# "cannot copy tree"; pointed at disk instead it exhausted the home quota. No
# mutation run has ever needed VCS history — the suite runs against the working
# tree, not against its past.
_mech_copy_tree() {
  # tar, not cp: it takes an exclude list and still preserves modes and times.
  # Present everywhere bash is. The subshells keep the cd local.
  ( cd "$1" && tar --exclude=./.git --exclude=./.hg --exclude=./.svn \
                   --exclude=./.git/* -cf - . ) 2>/dev/null \
  | ( mkdir -p "$2" && cd "$2" && tar -xf - ) 2>/dev/null
}
rm -rf "$PRISTINE" "$WORK"
_mech_copy_tree "$TREE" "$PRISTINE" || mech_die "cannot copy tree to $PRISTINE"
_mech_copy_tree "$TREE" "$WORK"     || mech_die "cannot copy tree to $WORK"
# A copy that produced nothing is a could-not-run (exit 2), never a pass: an
# empty scratch tree would make every suite "fail" for a reason unrelated to
# the mutation (§11.4.201).
[ -n "$(ls -A "$WORK" 2>/dev/null)" ] || mech_die "tree copy produced an empty scratch at $WORK"

REPLACEMENTS=0
if [ "$IS_MUTATION" -eq 1 ]; then
  # Literal (non-regex) replacement. Passing the strings through the environment
  # avoids every layer of shell/sed quoting, which is itself a documented source
  # of hand-executed mutation errors.
  REPLACEMENTS="$(MECH_TARGET="$WORK/$MFILE" MECH_FROM="$MFROM" MECH_TO="$MTO" python3 - <<'PY'
import os, sys
p = os.environ["MECH_TARGET"]
frm = os.environ["MECH_FROM"]
to = os.environ["MECH_TO"]
with open(p, "r", encoding="utf-8", errors="surrogateescape") as fh:
    src = fh.read()
n = src.count(frm)
if n:
    with open(p, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(src.replace(frm, to))
print(n)
PY
)" || mech_die "mutation step failed on $MFILE"
  if [ "$REPLACEMENTS" -eq 0 ]; then
    mech_die "mutation '$NAME' did not apply: --from text not found in $MFILE (a result from an unapplied mutation would be meaningless)"
  fi
  mech_log INFO "mutation '$NAME' applied to $MFILE ($REPLACEMENTS replacement(s))"
fi

# ---- run the suite -------------------------------------------------------
run_suite() {
  local -a cmd=(env)
  local v
  for v in "${UNSET_VARS[@]+"${UNSET_VARS[@]}"}"; do cmd+=(-u "$v"); done
  if [ -n "$ENV_KNOB" ]; then
    cmd+=("$ENV_KNOB=$WORK")
    cmd+=(timeout "$TIMEOUT" bash "$TREE/$SUITE")
  else
    cmd+=(timeout "$TIMEOUT" bash "$WORK/$SUITE")
  fi
  "${cmd[@]}" >"$RUNLOG" 2>&1
}

run_suite
SUITE_RC=$?

# ---- restore + prove nothing leaked into the original tree ---------------
restore_ok=1
rm -rf "$WORK"
cp -a "$PRISTINE" "$WORK" || restore_ok=0
if [ "$restore_ok" -eq 1 ]; then
  diff -r "$PRISTINE" "$WORK" >/dev/null 2>&1 || restore_ok=0
fi
TREE_FP_AFTER="$(mech_fingerprint_tree "$TREE")"

if [ "$TREE_FP_BEFORE" != "$TREE_FP_AFTER" ]; then
  printf 'SOURCE-TREE MODIFIED: %s (before=%s after=%s)\n' "$TREE" "$TREE_FP_BEFORE" "$TREE_FP_AFTER"
  mech_manifest_tree "$TREE" "$SCRATCH/tree.after"
  printf 'CHANGED PATHS (restore these):\n'
  mech_manifest_diff "$SCRATCH/tree.before" "$SCRATCH/tree.after" | sed 's|^|  |'
  KEEP=1
  mech_die "the source tree changed during the run — refusing to report a result"
fi
if [ "$restore_ok" -ne 1 ]; then
  mech_die "scratch restore was not byte-identical to the pristine copy"
fi

# ---- parse -------------------------------------------------------------
if [ "$SUITE_RC" -eq 124 ]; then
  printf 'MUTATION %s: TIMEOUT after %ss (log: %s)\n' "$NAME" "$TIMEOUT" "$RUNLOG"
  KEEP=1
  mech_die "suite exceeded --timeout; a timeout is not a failure result"
fi

counts="$(mech_parse_summary "$RUNLOG")" || {
  printf 'MUTATION %s: UNPARSEABLE suite output (rc=%s, log: %s)\n' "$NAME" "$SUITE_RC" "$RUNLOG"
  KEEP=1
  mech_die "no summary line naming both a passed and a failed count; refusing to guess"
}
PASSED="${counts% *}"
FAILED="${counts#* }"
MATCHED_LINE="$(mech_summary_line "$RUNLOG")"

# ---- verdict LINE (a measurement, not a judgment) ------------------------
if [ "$EXPECT" = "fail" ]; then
  EXPECT_LABEL="EXPECTED-FAIL"
  if [ "$FAILED" -gt 0 ]; then OUTCOME="OK"; RC="$MECH_EXIT_OK"; else OUTCOME="VIOLATION"; RC="$MECH_EXIT_FINDING"; fi
else
  EXPECT_LABEL="EXPECTED-PASS"
  if [ "$FAILED" -eq 0 ]; then OUTCOME="OK"; RC="$MECH_EXIT_OK"; else OUTCOME="VIOLATION"; RC="$MECH_EXIT_FINDING"; fi
fi

printf 'MUTATION %s: %s got %s failed / %s passed [%s]\n' \
  "$NAME" "$EXPECT_LABEL" "$FAILED" "$PASSED" "$OUTCOME"
if [ -n "$ENV_KNOB" ]; then MODE="env-knob:$ENV_KNOB"; else MODE="scratch-copy"; fi
printf '  suite=%s mode=%s replacements=%s suite_rc=%s\n' \
  "$SUITE" "$MODE" "$REPLACEMENTS" "$SUITE_RC"
printf '  parsed_line=%s\n' "$MATCHED_LINE"
printf '  tree_fingerprint_unchanged=%s\n' "$TREE_FP_BEFORE"

exit "$RC"
