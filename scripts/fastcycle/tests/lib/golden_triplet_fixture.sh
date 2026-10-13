#!/bin/bash
# golden_triplet_fixture.sh -- shared fixture helpers for the T048 regression
# guards of test_fc_timer_golden_output.sh and capture_fc_timer_triplet.sh.
# Sourced, never executed. (T048 round 6.)
#
# The point of this library is that fixtures are produced BY THE REAL HARNESS
# (capture_fc_timer_triplet.sh) driving a stand-in pre-build script, and are
# consumed BY THE REAL GOLDEN TEST run end-to-end. Nothing here re-implements
# either file's logic or extracts code fragments out of them, so a regression
# test built on it exercises the shipped code path. Callers may point
# GT_HARNESS / GT_GOLDEN at a MUTATED COPY to prove a check is load-bearing.
#
# Stand-in pre-build contract: the member name is the suffix of
# FC_TIMER_RUN_ID (the harness sets it to <run-id>_<prefix>_<member>). The
# stand-in prints $GT_FIX/<member>.txt as its "pre_build output". It writes a
# section TSV with $GT_FIX/<member>.rows data rows (file absent -> 2 rows when
# FC_TIMING != 0, none when FC_TIMING = 0), so a test can make a member LIE
# about its timer setting. It also echoes the FC_TIMING it saw, so a test can
# confirm the harness passed the right value.
#
# T048 round 19 (R18-I1) -- realistic summary block. The real
# pre_build_verification.sh prints "  Failed:       N" (:51115) on straight-
# line top-level code BEFORE its only two exits (`exit 0` iff N==0, else
# `exit 1`), so every real member log carries exactly one such line. Since
# round 19 the golden test hard-FAILs a member whose exit is nonzero while
# its Failed: count is unreadable (that is exactly what a crash-before-
# summary looks like), so the stand-in now mirrors the real script:
#   * it exits with the code in $GT_FIX/<member>.exit when that file exists,
#     1 otherwise (the pre-round-19 constant), so a fixture states a member's
#     exit code BEFORE capture and the harness records it for real, instead
#     of a post-hoc manifest edit that the member's own log contradicts;
#   * when the fixture text has NO full-line "Failed: N" line of its own, it
#     appends one consistent with that exit code (0 for exit 0, else 1).
#     A fixture that carries its own Failed: line(s) is printed verbatim --
#     including deliberately missing/duplicated/inconsistent ones -- and
#     $GT_FIX/<member>.nosummary suppresses the auto line entirely (used to
#     model a crash before the summary block, e.g. the round-18 ADVA/ADVG
#     fixtures).
#
# Provides: gt_init, gt_member_text, gt_capture, gt_promote, gt_golden
# Env read by the stand-in: GT_FIX, GT_FIX_SLEEP, GT_FIX_COLLIDE, GT_FIX_TOUCH(_MEMBER).

GT_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GT_HARNESS="${GT_HARNESS:-$GT_TESTS_DIR/capture_fc_timer_triplet.sh}"
GT_GOLDEN="${GT_GOLDEN:-$GT_TESTS_DIR/test_fc_timer_golden_output.sh}"

# gt_init WORKDIR -- creates the stand-in pre-build at WORKDIR/fake_prebuild.sh
gt_init() {
  GT_WORK="$1"
  mkdir -p "$GT_WORK"
  cat > "$GT_WORK/fake_prebuild.sh" <<'EOF'
#!/bin/bash
m="${FC_TIMER_RUN_ID##*_}"
[ -n "${GT_FIX_SLEEP:-}" ] && sleep "$GT_FIX_SLEEP"
# T048 restart round-1 (R1-I6): drive REAL tree drift during a capture -- the named member
# (default FC1) appends a line to $GT_FIX_TOUCH (a file inside a scratch git work tree the
# harness fingerprints via CAPTURE_TRIPLET_TREE_ROOT).
if [ -n "${GT_FIX_TOUCH:-}" ] && [ "$m" = "${GT_FIX_TOUCH_MEMBER:-FC1}" ]; then echo "drift by $m" >> "$GT_FIX_TOUCH"; fi
cat "$GT_FIX/$m.txt"
gt_exit=1
[ -f "$GT_FIX/$m.exit" ] && gt_exit="$(cat "$GT_FIX/$m.exit")"
if [ ! -f "$GT_FIX/$m.nosummary" ] && ! grep -qE '^[[:space:]]*Failed:[[:space:]]+[0-9]+[[:space:]]*$' "$GT_FIX/$m.txt"; then
  if [ "$gt_exit" = 0 ]; then echo "  Failed:       0"; else echo "  Failed:       1"; fi
fi
echo "stand-in member=$m FC_TIMING=${FC_TIMING-unset}"
echo "stand-in member=$m TMPDIR=${TMPDIR-unset}"
# GT_FIX_COLLIDE=<seconds> reproduces the round-7 R6-B1 mechanism: a sub-test
# that keeps its evidence in a FIXED ${TMPDIR}/<name> dir and rm -rf's it at
# start (as test_stress_chaos_oracles_selfcheck.sh does). Two members sharing
# one TMPDIR clobber each other; isolated members do not.
if [ -n "${GT_FIX_COLLIDE:-}" ]; then
  d="${TMPDIR:-/nonexistent}/gt_shared_evid"; rm -rf "$d"; mkdir -p "$d"
  echo "$m" > "$d/owner"; sleep "$GT_FIX_COLLIDE"
  if [ "$(cat "$d/owner" 2>/dev/null)" = "$m" ]; then echo "  ✓ CM-SHARED-EVID: own evidence intact"
  else echo "  ✗ ERROR: CM-SHARED-EVID: evidence dir clobbered by a concurrent member"; fi
fi
if [ -f "$GT_FIX/$m.rows" ]; then rows="$(cat "$GT_FIX/$m.rows")"
elif [ "${FC_TIMING:-1}" != 0 ]; then rows=2
else rows=0; fi
if [ "$rows" -gt 0 ]; then
  d="$CAPTURE_TRIPLET_TSV_ROOT/$FC_TIMER_RUN_ID"; mkdir -p "$d"
  printf 'section\tms\n' > "$d/prebuild_sections.tsv"
  i=0; while [ "$i" -lt "$rows" ]; do printf 'S%s\t1\n' "$i" >> "$d/prebuild_sections.tsv"; i=$((i + 1)); done
fi
exit "$gt_exit"
EOF
}

# gt_member_text FIXDIR MEMBER < text -- the verdict output MEMBER will print.
gt_member_text() { mkdir -p "$1"; cat > "$1/$2.txt"; }

# gt_member_exit FIXDIR MEMBER CODE -- the exit code MEMBER's stand-in run
# will really return (default 1). See the round-19 note at the top.
gt_member_exit() { mkdir -p "$1"; printf '%s\n' "$3" > "$1/$2.exit"; }

# gt_member_nosummary FIXDIR MEMBER -- suppress the stand-in's automatic
# "Failed: N" line for MEMBER (models a crash before the summary block).
gt_member_nosummary() { mkdir -p "$1"; : > "$1/$2.nosummary"; }

# gt_capture FIXDIR OUTDIR PREFIX RUNID [harness-args...] -- runs the harness;
# its stdout+stderr go to OUTDIR/.capture.log; returns its exit code.
gt_capture() {
  local fix="$1" out="$2" prefix="$3" runid="$4"; shift 4
  mkdir -p "$out"
  mkdir -p "$GT_WORK/inherited_tmp"
  # TMPDIR is pinned to ONE shared, test-private directory: a harness that
  # did NOT isolate members would hand all three this same TMPDIR.
  TMPDIR="$GT_WORK/inherited_tmp" GT_FIX="$fix" CAPTURE_TRIPLET_PREBUILD="$GT_WORK/fake_prebuild.sh" \
    CAPTURE_TRIPLET_OUT_DIR="$out" CAPTURE_TRIPLET_TSV_ROOT="$out/tsv" \
    CAPTURE_TRIPLET_RUN_ID="$runid" \
    bash "$GT_HARNESS" --prefix "$prefix" "$@" > "$out/.capture.log" 2>&1
}

# gt_promote MANIFEST -- fixture promotion: the stand-in manifest is relabelled
# mode=real so the golden test's auto-discovery will consume it. This is a
# TEST FIXTURE step, stated as such; the real harness never writes mode=real
# for a stand-in run.
gt_promote() { sed -i 's/^mode=stand-in$/mode=real/' "$1"; }

# gt_golden OUTFILE [VAR=VALUE...] -- runs the golden test with the given env
# assignments; output to OUTFILE; returns its exit code.
gt_golden() {
  local out="$1"; shift
  env "$@" bash "$GT_GOLDEN" > "$out" 2>&1
}
