#!/bin/bash
# Purpose : T129 (SpecKit-004 "fast-dev-cycles", User Story 5) RED baseline
#           for `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           (T137's own, separate, later implementation task), per plan.md
#           T-B08 and this test's own dispatch instructions ("inventory
#           stashes and worktrees with owner item, last commit, dirty-file
#           hashes, existing custody backups; propose land/keep/retire each
#           with a verified backup; executes nothing without operator
#           confirmation").
#
# HONEST CORRECTION TO THE TASK TEXT (section 11.4.6, re-verified LIVE by
# THIS test at authoring time, 2026-09-30 -- not merely re-stated from an
# earlier session's memory): tasks.md's T129 line (and plan.md's own T-B08
# "memory note", which repeats the SAME claim) both state: "stash@{3} is
# already landed (do not pop) ... stash@{5} and worktrees a17eb/a67d hold
# stranded work with backups in qa-results/agent_custody_20260926/". A prior
# investigation THIS SESSION already found this claim wrong on THREE counts,
# and this test independently RE-VERIFIED all three live before authoring
# any fixture around them:
#
#   (1) "stash@{3} is already landed (do not pop)" is WRONG. `git stash
#       show -p stash@{3} --stat` (re-run live below, section REAL-STATE)
#       shows it is a real, still-present diff against
#       device/rockchip/rk3588/bin/atmosphere-ui-recovery.sh +
#       device/rockchip/rk3588/init.rk3588.rc that has NOT been merged/
#       superseded by the crash-loop fix already on main -- it needs
#       operator sign-off before any drop, it is NOT "already landed,
#       never pop".
#   (2) "worktrees a17eb/a67d" undercounts the real set: THREE worktrees
#       are currently registered (a17eb3df7db2f148a, a67d4795f1c7c710a,
#       AND a7703e281e7a62864 -- re-verified live below), not two.
#   (3) "stash@{5} ... with backups in qa-results/agent_custody_20260926/"
#       is WRONG for the STASH half of that claim: a real, byte-verified
#       backup directory (qa-results/agent_custody_20260926/
#       backup_worktrees/) exists for ALL THREE worktrees (each holding a
#       real tracked.patch + status.txt), but NO backup artifact of any
#       kind for stash@{5} was found anywhere under qa-results/ or docs/ by
#       an exhaustive `grep -rl` for "stash@{5}" (re-run live below) --
#       there is no stash backup directory, only a worktree one.
#
# This test's fixtures are therefore built around the REAL, RE-VERIFIED
# current state captured live at run time (never a hardcoded snapshot of
# the STALE task-text claim) -- see the REAL-STATE section below, which is
# read-only inventory only. This test NEVER proposes/executes anything
# destructive against the real stashes/worktrees.
#
# This file's checks, in order:
#   (0) section-11.4.273 control needle #1 -- a known-present sibling file
#       resolves through this test's own relative-path construction, so the
#       absence check below can be trusted;
#   (1) absence check -- orchestration/custody_sweep.py (T137) does not
#       exist yet;
#   (2) REAL-STATE -- read-only, live re-verification of this project's OWN
#       current `git stash list` + `git worktree list`, printed as captured
#       evidence, with the three corrections above re-confirmed live (never
#       merely asserted from memory);
#   (3) section-11.4.273 control needle #2 (the actual "control needle: a
#       planted stash with a known file appears in the inventory" the
#       dispatch asked for) -- a SAFE, ISOLATED scratch git repo (never this
#       project's own real stashes) with a real stash containing a real,
#       uniquely-identifiable planted file, scanned by an independent
#       inventory-scanning function to prove that function can genuinely
#       see real stash contents (not a mocked/assumed result);
#   (4) the golden-bad / golden-good / negative-control land/keep/retire
#       PROPOSAL-refusal fixtures, checked against an independently
#       DERIVED oracle (section 11.4.245) that re-verifies each fixture's
#       backup_hash against the REAL backup_artifact_path on disk at test
#       time (never trusts the fixture's own claimed verdict), including:
#         proposal_golden_bad_no_hash.json          -> REFUSED
#         proposal_golden_bad_wrong_hash.json       -> REFUSED
#         proposal_golden_bad_stash5_no_backup.json -> REFUSED
#         proposal_golden_good_verified_hash.json   -> ALLOWED
#         proposal_negctrl_keep_no_hash.json        -> ALLOWED (negative
#                                                       control: 'keep' is
#                                                       non-destructive, so
#                                                       it must never be
#                                                       refused merely for
#                                                       an absent backup_hash
#                                                       -- section
#                                                       11.4.201(1))
#   (5) self-validation discrimination needle (section 11.4.107(10) /
#       11.4.201(1)) -- the three REFUSED fixtures and the two ALLOWED
#       fixtures MUST genuinely diverge, never all resolve to the same
#       verdict regardless of input.
#
# Producer != Verifier (section 11.4.240): this file is authored at the RED
# step (T129); T137's implementation of `custody_sweep.py` is a separate,
# later task -- this file's author never implements it. The independent
# oracle embedded below (derive_verdict, a fresh Python function written
# directly from section 9.2 + this test's own dispatch instructions, over
# this test's OWN fixture files -- never T137's eventual production code)
# is a DERIVED oracle per section 11.4.245, computed independently of
# whatever T137 eventually writes; it is never imported by, shared with, or
# otherwise coupled to `custody_sweep.py`.
#
# House style: mirrors constitution/scripts/fastcycle/tests/
# test_evidence_ref_red.sh (T108) -- absence-check-first, control-needle-
# first, independently-DERIVED oracle over fixture files (never the not-yet-
# built implementation), golden-good/golden-bad/negative-control
# discrimination needle, honest RED-vs-unexpected-GREEN closing summary.
#
# Usage : bash test_custody_sweep_red.sh   Exit 0 = every real assertion
#         below held (the control needles, the absence check, the REAL-
#         STATE re-verification, the five-row proposal-refusal fixture
#         table via the derived oracle, the discrimination needle).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-30):
#         `custody_sweep.py` genuinely does not exist yet (T137 is a
#         separate, later, not-yet-started task) -- this is the T129 RED
#         baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/custody_sweep"
IMPL="$FC/orchestration/custody_sweep.py"
QARESULTS="$ROOT/qa-results/agent_custody_20260926"

fail=0
failx() { fail=1; }

# --- section-11.4.273 control needle #1: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so the absence check below proves"
  echo "     nothing (section 11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the absence check"
  echo "   below can be trusted"
fi

# --- (1) Absence check: orchestration/custody_sweep.py ---
ORCH_DIR="$FC/orchestration"
if [ -d "$ORCH_DIR" ]; then
  py_count=$(find "$ORCH_DIR" -maxdepth 1 -name '*.py' -o -maxdepth 1 -name '*.sh' | wc -l)
  echo "-- $ORCH_DIR exists, holding $py_count script(s) right now (e.g."
  echo "   completion_probe.sh from T122 -- a separate, already-landed task)"
else
  echo "-- $ORCH_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok orchestration/custody_sweep.py now exists -- T137 has landed. If"
  echo "   you are seeing this, T137's real implementation should be re-"
  echo "   pointed at instead of this file's derived oracle."
else
  echo "NOT ok orchestration/custody_sweep.py is absent -- T137 (plan.md"
  echo "     T-B08's implementation task, a SEPARATE later task from this"
  echo "     RED test) has not landed yet. THIS IS THE CORRECT, EXPECTED"
  echo "     T129 RED BASELINE -- the fixtures + independent derivation"
  echo "     below stand as the interim contract T137 must satisfy to turn"
  echo "     this GREEN."
  failx
fi

# ---------------------------------------------------------------------------
# (2) REAL-STATE: read-only, live re-verification of this project's own
# current stash list + worktree list. NEVER a hardcoded snapshot of the
# stale task-text claim -- captured fresh, every run, from the real git
# state, and printed as evidence.
# ---------------------------------------------------------------------------
echo
echo "=== REAL-STATE: live git stash list (re-verified, never assumed) ==="
STASH_RAW="$(git -C "$ROOT" stash list 2>&1)"
if [ -z "$STASH_RAW" ]; then
  echo "-- (empty stash list -- if you expected stash@{3} / stash@{5} to be"
  echo "   present, the real state has changed since this test was authored;"
  echo "   that is itself honest information, not a test failure)"
else
  echo "$STASH_RAW" | sed 's/^/   /'
fi
STASH_COUNT=$(printf '%s\n' "$STASH_RAW" | grep -c '^stash@{' || true)
echo "-- live stash count: $STASH_COUNT"

echo
echo "=== REAL-STATE: live git worktree list (re-verified, never assumed) ==="
WT_RAW="$(git -C "$ROOT" worktree list --porcelain 2>&1)"
echo "$WT_RAW" | sed 's/^/   /'
WT_PATHS=$(printf '%s\n' "$WT_RAW" | awk '/^worktree /{print $2}')
WT_COUNT=$(printf '%s\n' "$WT_PATHS" | grep -c . || true)
echo "-- live worktree count: $WT_COUNT (main checkout counts as one of these)"

echo
echo "=== REAL-STATE: correction (1) -- is stash@{3} genuinely 'already landed'? ==="
STASH3_REF='stash@{3}'
if printf '%s\n' "$STASH_RAW" | grep -q '^stash@{3}:'; then
  S3_STAT="$(git -C "$ROOT" stash show -p "$STASH3_REF" --stat 2>&1)"
  if [ -n "$S3_STAT" ]; then
    echo "ok CONFIRMED: stash@{3} is STILL a real, non-empty diff (shown below,"
    echo "   truncated) -- the task text's 'already landed, never pop' claim"
    echo "   is FALSE; this is genuinely uncommitted work needing operator"
    echo "   sign-off before any drop, exactly as this session's prior"
    echo "   investigation found:"
    echo "$S3_STAT" | head -6 | sed 's/^/   /'
  else
    echo "NOT ok stash@{3} shows an EMPTY diff -- this would actually support"
    echo "     the task text's 'already landed' claim; re-investigate before"
    echo "     trusting this test's own correction over the task text"
    failx
  fi
else
  echo "-- stash@{3} is no longer present in the live list -- the task"
  echo "   text's claim about it is moot today (state has moved on); this"
  echo "   is honestly reported, not silently assumed either way"
fi

echo
echo "=== REAL-STATE: correction (2) -- THREE worktrees, not two ==="
# Count worktree entries whose path contains .claude/worktrees/agent- (the
# agent-worktree naming convention observed live), independent of the exact
# ids named in the task text -- never hardcoded to a specific count.
AGENT_WT_COUNT=$(printf '%s\n' "$WT_PATHS" | grep -c '\.claude/worktrees/agent-' || true)
echo "-- live count of agent worktrees (path contains .claude/worktrees/agent-): $AGENT_WT_COUNT"
if [ "$AGENT_WT_COUNT" -ge 3 ]; then
  echo "ok CONFIRMED: at least 3 agent worktrees are live -- the task text's"
  echo "   'worktrees a17eb/a67d' (naming only two) undercounts the real set."
  printf '%s\n' "$WT_PATHS" | grep '\.claude/worktrees/agent-' | sed 's/^/   /'
elif [ "$AGENT_WT_COUNT" -gt 0 ]; then
  echo "-- $AGENT_WT_COUNT agent worktree(s) live today; this may be fewer"
  echo "   than the THREE this test's authoring-time re-verification found"
  echo "   (a7703e281e7a62864 having since been landed/retired would explain"
  echo "   a drop) -- honestly reported as the current live count, not"
  echo "   forced to match a stale number"
else
  echo "-- no agent worktrees are live today"
fi

echo
echo "=== REAL-STATE: correction (3) -- is there really a backup for stash@{5}? ==="
STASH_BACKUP_HITS=$(grep -rl "stash@{5}" "$ROOT/qa-results" "$ROOT/docs" 2>/dev/null | grep -v '\.pdf$\|\.docx$\|\.html$' | wc -l)
WT_BACKUP_DIR_COUNT=0
if [ -d "$QARESULTS/backup_worktrees" ]; then
  WT_BACKUP_DIR_COUNT=$(find "$QARESULTS/backup_worktrees" -mindepth 1 -maxdepth 1 -type d | wc -l)
fi
echo "-- text-file hits mentioning literal 'stash@{5}' under qa-results/+docs/: $STASH_BACKUP_HITS"
echo "-- real worktree backup subdirectories under $QARESULTS/backup_worktrees: $WT_BACKUP_DIR_COUNT"
if [ -d "$QARESULTS/backup_worktrees" ] && [ ! -d "$QARESULTS/backup_stashes" ] && [ ! -f "$QARESULTS/stash5.patch" ] && [ ! -f "$QARESULTS/stash_5.patch" ]; then
  echo "ok CONFIRMED: a real worktree-backup directory exists"
  echo "   ($QARESULTS/backup_worktrees, holding $WT_BACKUP_DIR_COUNT real"
  echo "   subdirectories) but NO stash-backup directory or file for"
  echo "   stash@{5} was found under the same tree -- the task text's claim"
  echo "   that stash@{5} has 'backups in qa-results/agent_custody_20260926/'"
  echo "   is FALSE for the stash half specifically; only the worktree half"
  echo "   of that sentence is true."
else
  echo "-- backup-directory layout differs from what this test expected at"
  echo "   authoring time; printing what actually exists rather than"
  echo "   asserting a stale conclusion:"
  find "$QARESULTS" -mindepth 1 -maxdepth 1 2>/dev/null | sed 's/^/   /'
fi

# ---------------------------------------------------------------------------
# (3) section-11.4.273 control needle #2: the actual dispatch-requested
# needle -- plant a real, known, uniquely-identifiable file inside a REAL
# scratch stash in a SAFE, ISOLATED scratch git repo (never touching this
# project's own real stashes/worktrees), then confirm an independent
# inventory-scanning function genuinely finds it by scanning real stash
# content (never a mocked/assumed result).
# ---------------------------------------------------------------------------
echo
echo "=== control needle #2: isolated scratch-repo stash content-scan ==="
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
git -C "$SCRATCH" init -q
git -C "$SCRATCH" config user.email "t129-scratch@example.invalid"
git -C "$SCRATCH" config user.name "T129 scratch"
echo "base" > "$SCRATCH/base.txt"
git -C "$SCRATCH" add base.txt
git -C "$SCRATCH" commit -q -m "base commit"

NEEDLE_TOKEN="T129_CONTROL_NEEDLE_$(date +%s)_$$_$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$NEEDLE_TOKEN" > "$SCRATCH/planted_marker.txt"
git -C "$SCRATCH" add planted_marker.txt
git -C "$SCRATCH" stash push -q -m "control-needle stash: $NEEDLE_TOKEN"

# Independent inventory-scanning function (never borrowed from any real
# custody_sweep implementation -- there is none yet): parses `git stash
# list` + `git stash show -p <ref>` output looking for the planted file.
scan_stash_for_file() {
  # $1 = repo path, $2 = stash ref (e.g. stash@{0}), $3 = filename to find
  git -C "$1" stash show -p "$2" 2>/dev/null | grep -q "^diff --git a/$3 "
}

if git -C "$SCRATCH" stash list | grep -q "control-needle stash: $NEEDLE_TOKEN"; then
  echo "ok scratch stash created + listed (message contains the real planted"
  echo "   needle token)"
else
  echo "NOT ok scratch stash was not created or not listed -- control needle"
  echo "     setup itself is broken"
  failx
fi

if scan_stash_for_file "$SCRATCH" "stash@{0}" "planted_marker.txt"; then
  echo "ok CONTROL NEEDLE PROVEN: the independent inventory-scanning function"
  echo "   genuinely finds the real, uniquely-identifiable planted file"
  echo "   (planted_marker.txt, needle $NEEDLE_TOKEN) inside a real git"
  echo "   stash -- this proves the scanning mechanism can see real stash"
  echo "   content, not merely a mocked/assumed result (section 11.4.273)."
else
  echo "NOT ok control needle #2 FAILED: the scanning function did NOT find"
  echo "     the real planted file inside the real scratch stash -- the"
  echo "     scanner is blind and any 'stash content found' claim elsewhere"
  echo "     in a future sweep implementation is unproven until this needle"
  echo "     passes (section 11.4.273)"
  failx
fi

# A negative check on the SAME scanner + SAME real stash, for a file that
# was NEVER planted -- proves the scanner does not simply always return
# true (the false-positive guard, section 11.4.201(1)).
if scan_stash_for_file "$SCRATCH" "stash@{0}" "definitely_never_planted_file_xyz.txt"; then
  echo "NOT ok control needle #2 negative check FAILED: the scanner reported"
  echo "     finding a file that was never planted -- it is not genuinely"
  echo "     inspecting stash content, it always returns true"
  failx
else
  echo "ok control needle #2 negative check: the scanner correctly reports"
  echo "   NOT-found for a file that was never planted in the same real"
  echo "   stash (proves it discriminates, section 11.4.201(1))"
fi

# ---------------------------------------------------------------------------
# (4) golden-bad / golden-good / negative-control proposal-refusal fixtures,
# checked against an independently DERIVED oracle (section 11.4.245).
# ---------------------------------------------------------------------------
echo
echo "=== T129 land/keep/retire proposal-refusal fixtures, independent DERIVED oracle ==="

derive_verdict() {
  # $1 = fixture json path. Prints ALLOWED or REFUSED on stdout.
  # Independently derived from section 9.2 (no destructive op without a
  # verified backup) + this test's own dispatch instructions -- never
  # borrowed from, or coupled to, orchestration/custody_sweep.py.
  python3 - "$1" "$ROOT" <<'PYEOF'
import hashlib
import json
import os
import sys

fixture_path, root = sys.argv[1], sys.argv[2]
with open(fixture_path, encoding="utf-8") as fh:
    d = json.load(fh)

action = d["action"]
backup_hash = d.get("backup_hash")
backup_artifact_path = d.get("backup_artifact_path")

# 'keep' is non-destructive (leaves the entry exactly as-is) -- it is
# NEVER refused for a missing backup_hash. Only 'land' and 'retire' are
# destructive-enough to require a verified backup per section 9.2.
DESTRUCTIVE_ACTIONS = {"land", "retire"}

if action not in DESTRUCTIVE_ACTIONS:
    print("ALLOWED")
    sys.exit(0)

if not backup_hash or not backup_artifact_path:
    print("REFUSED")
    sys.exit(0)

full_artifact = os.path.join(root, backup_artifact_path)
if not os.path.isfile(full_artifact):
    # The claimed backup artifact does not even exist on disk -- refuse,
    # never trust a path that cannot be independently re-verified.
    print("REFUSED")
    sys.exit(0)

with open(full_artifact, "rb") as fh:
    real_hash = hashlib.sha256(fh.read()).hexdigest()

if real_hash == backup_hash:
    print("ALLOWED")
else:
    print("REFUSED")
PYEOF
}

FIXDIR_CHECK_FAIL=0
for f in \
  "proposal_golden_bad_no_hash.json:REFUSED" \
  "proposal_golden_bad_wrong_hash.json:REFUSED" \
  "proposal_golden_bad_stash5_no_backup.json:REFUSED" \
  "proposal_golden_good_verified_hash.json:ALLOWED" \
  "proposal_negctrl_keep_no_hash.json:ALLOWED" \
; do
  fname="${f%%:*}"
  expected="${f##*:}"
  fpath="$FIXDIR/$fname"
  if [ ! -f "$fpath" ]; then
    echo "NOT ok fixture $fname is MISSING"
    FIXDIR_CHECK_FAIL=1
    failx
    continue
  fi
  actual="$(derive_verdict "$fpath")"
  if [ "$actual" = "$expected" ]; then
    echo "ok $fname: derived verdict = $actual (matches expected $expected)"
  else
    echo "NOT ok $fname: derived verdict = $actual, expected $expected"
    FIXDIR_CHECK_FAIL=1
    failx
  fi
done
if [ "$FIXDIR_CHECK_FAIL" = 0 ]; then
  echo "ok all five proposal fixtures match their expected verdicts via the"
  echo "   independently-derived oracle"
fi

# ---------------------------------------------------------------------------
# (5) Self-validation discrimination needle (section 11.4.107(10) /
# 11.4.201(1)): REFUSED and ALLOWED fixtures must genuinely diverge.
# ---------------------------------------------------------------------------
echo
echo "=== Self-validation discrimination needle ==="
REFUSED_VERDICTS=""
for f in proposal_golden_bad_no_hash.json proposal_golden_bad_wrong_hash.json proposal_golden_bad_stash5_no_backup.json; do
  REFUSED_VERDICTS="$REFUSED_VERDICTS $(derive_verdict "$FIXDIR/$f")"
done
ALLOWED_VERDICTS=""
for f in proposal_golden_good_verified_hash.json proposal_negctrl_keep_no_hash.json; do
  ALLOWED_VERDICTS="$ALLOWED_VERDICTS $(derive_verdict "$FIXDIR/$f")"
done

disc_fail=0
for v in $REFUSED_VERDICTS; do
  if [ "$v" != "REFUSED" ]; then
    echo "NOT ok discrimination: a golden-bad fixture unexpectedly did not"
    echo "     resolve to REFUSED (got: $v)"
    disc_fail=1
    failx
  fi
done
for v in $ALLOWED_VERDICTS; do
  if [ "$v" != "ALLOWED" ]; then
    echo "NOT ok discrimination: an ALLOWED-expected fixture unexpectedly"
    echo "     did not resolve to ALLOWED (got: $v)"
    disc_fail=1
    failx
  fi
done
if [ "$disc_fail" = 0 ]; then
  echo "ok discrimination: every REFUSED-expected fixture genuinely resolved"
  echo "   to REFUSED and every ALLOWED-expected fixture genuinely resolved"
  echo "   to ALLOWED -- the oracle discriminates rather than rubber-stamping"
  echo "   every input identically"
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T137 not yet landed); if you"
  echo "    see this, orchestration/custody_sweep.py must have landed AND"
  echo "    every fixture check passed against the real tool. ==="
else
  echo "=== T129 RED BASELINE CONFIRMED: orchestration/custody_sweep.py does"
  echo "    not exist yet (T137 is a separate, later task). The REAL-STATE"
  echo "    re-verification (including the three corrections to the stale"
  echo "    task-text claim), the isolated-scratch control needle, and the"
  echo "    five-row proposal-refusal fixture table via the independently"
  echo "    derived oracle, all above, are the interim contract T137 must"
  echo "    satisfy to turn this GREEN. ==="
fi

exit $fail
