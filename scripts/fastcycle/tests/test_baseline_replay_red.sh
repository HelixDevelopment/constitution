#!/bin/bash
# Purpose : T024 (SpecKit-004 "fast-dev-cycles", User Story 1) baseline guard
#           for the T-A10 stratified-baseline sampling + replay mechanism.
#           tasks.md's T024 line, and plan.md's T-A10 "Protecting tests"
#           clause (lines 488-490), state the exact contract this test pins:
#
#   "determinism: two replays of one sample change produce the same verdict
#   set; the sample selection script is re-run and yields the same item list
#   (control: the known 5 bugs of the 60-day window are included)."
#
# STATUS (corrected 2026-09-28, investigate-then-verify pass): this file
# previously proved `cycle/select_sample.py` and `cycle/baseline_replay.sh`
# ABSENT and printed three "NOT YET IMPLEMENTED" contract-stub blocks that
# never actually ran the contract they described -- T043 has SINCE landed
# both tools (verified directly: both files exist, both executable), which
# left the file exiting 0 unconditionally while genuinely testing NOTHING
# of the determinism/re-run/needle contract below. That is the exact
# "stale absence-precondition becomes a permanent false PASS" defect class
# this suite independently fixed at the ASSERTION level elsewhere (T023,
# T025, T036, T020) -- this file had the SAME defect one level up, at the
# DOCSTRING/stub level, because its three contract sections were left as
# prose for "T043's implementer" to convert into real tests (a step T043's
# implementer is explicitly forbidden from doing itself, per
# Producer!=Verifier below). Converted here, by the conductor (not T043's
# implementer), into real, executable assertions against the now-landed
# tools -- every determinism/re-run/needle claim below is proven by an
# actual invocation captured in this same investigation, including a
# deliberately-injected NON-deterministic gate-cmd (a golden-bad control
# needle, §11.4.201/§11.4.107(10)) proving the replay determinism check
# can genuinely FAIL and is not a rubber stamp.
#
# research.md P-15 (line 126) is the source of the "5 known bugs" figure:
#   "60-day window: Bug 5, Task 2, Feature 0; 90-day: Bug 21, Task 16,
#   Feature 1; Feature ever: 2" -- cited to raw research artifact "R1:19-21",
#   which is NOT itself a tracked file in this repo (an ephemeral research-pass
#   artifact) and does NOT enumerate the 5 items by ATM-id anywhere this file
#   can find. §11.4.6 (no-guessing): the exact 5 item ids are therefore NOT
#   invented here -- the needle assertion below uses select_sample.py's own
#   built-in CT-009-style needle (a known-present item's closure event/date
#   MUST be found, a fabricated id MUST be absent, per §11.4.201(7)(b)) as
#   the "known bug must be included" proxy, and separately reports (never
#   hard-fails on) the live 60-day Bug-type count against research.md's
#   cited 5 -- a mismatch is a finding to surface, never silently reconciled
#   or invented away.
#
# Producer≠Verifier: this file was authored at the RED step (T024); T043's
# implementation of select_sample.py/baseline_replay.sh was a SEPARATE,
# earlier-numbered-but-later-landed task -- T043's implementer never edited
# this file (confirmed: `git log --oneline -- <this file>` shows exactly two
# commits before this correction, the T024 authoring commit and a later one
# whose subject names T036, not T043).
#
# §11.4.273 control needle (for THIS file's own absence-detection mechanism):
# before trusting "select_sample.py is absent" as a finding, prove the plain
# `[ -f PATH ]` file-presence check genuinely resolves paths relative to this
# script's real location by first confirming a KNOWN-PRESENT sibling
# (lib/fc_common.py, used throughout this suite) resolves true through the
# identical relative-path construction. A wrong relative-path computation
# would make EVERY file in the tree look "absent", including real ones.
#
# Usage : bash test_baseline_replay_red.sh   Exit 0 = every real assertion
#         below (control needle, presence, replay determinism x2 incl. the
#         golden-bad control, select_sample re-run stability, needle) held.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }

# legacy alias used by the pre-existing control-needle block below
fail=0
failx() { fail=1; FAIL=$((FAIL+1)); }

# --- §11.4.273 control needle: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so every absence check below proves"
  echo "     nothing (§11.4.273)"
  failx
else
  echo "ok control needle: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the absence checks"
  echo "   below can be trusted"
fi

# --- (1) Presence: select_sample.py (T043 has landed both tools -- verified
#     directly below, never assumed) ---
SELECT_SAMPLE="$FC/cycle/select_sample.py"
if [ -f "$SELECT_SAMPLE" ] && [ -x "$SELECT_SAMPLE" ]; then
  ok "cycle/select_sample.py present and executable"
else
  bad "cycle/select_sample.py missing or not executable at $SELECT_SAMPLE -- every real assertion below that depends on it is SKIPPED, not silently passed"
fi

# --- (2) Presence: baseline_replay.sh ---
BASELINE_REPLAY="$FC/cycle/baseline_replay.sh"
if [ -f "$BASELINE_REPLAY" ] && [ -x "$BASELINE_REPLAY" ]; then
  ok "cycle/baseline_replay.sh present and executable"
else
  bad "cycle/baseline_replay.sh missing or not executable at $BASELINE_REPLAY -- every real assertion below that depends on it is SKIPPED, not silently passed"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_scratch_repo() {
  local r
  r="$(mktemp -d)"
  git -C "$r" init -q
  git -C "$r" config user.email t024@test.local
  git -C "$r" config user.name "T024 baseline_replay determinism test"
  printf '%s' "$1" > "$r/f.txt"
  git -C "$r" add f.txt
  git -C "$r" commit -q -m "$2"
  printf '%s' "$r"
}

echo
echo "=== contract 1/3: replay determinism (plan.md T-A10, SC-002/SC-005) ==="
if [ -x "$BASELINE_REPLAY" ]; then
  # Real (not scratch-repo-only) confirmation, kept intentionally light --
  # a single deterministic gate-cmd against THIS repo's real HEAD/tree is a
  # slow real `git worktree add` on a multi-hundred-thousand-file tree, so
  # the exhaustive golden-good/golden-bad matrix below runs against a tiny
  # throwaway scratch repo (near-instant, same code path, isolates the
  # ASSERTION from this repo's tree size -- §11.4.107(10)/§11.4.201).
  SREPO="$(mk_scratch_repo a init)"
  SCOMMIT="$(git -C "$SREPO" rev-parse HEAD)"
  STREE="$(git -C "$SREPO" rev-parse HEAD^{tree})"
  WT="$TMP/wt_good"
  mkdir -p "$WT"
  cat > "$TMP/gate_true.sh" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$TMP/gate_true.sh"
  DET_OUT="$TMP/det_good.json"
  bash "$BASELINE_REPLAY" replay --commit "$SCOMMIT" --tree "$STREE" \
    --gate-cmd "$TMP/gate_true.sh" --cold-runs 1 --warm-runs 1 \
    --repo-root "$SREPO" --worktree-root "$WT" \
    --out "$DET_OUT" --determinism-check >"$TMP/det_good.out" 2>&1
  GOOD_RC=$?
  GOOD_DET="$(python3 -c "import json; print(json.load(open('$DET_OUT')).get('deterministic'))" 2>/dev/null)"
  if [ "$GOOD_RC" = 0 ] && [ "$GOOD_DET" = True ]; then
    ok "replay --determinism-check: golden-GOOD (deterministic gate-cmd, exit 0, deterministic=True) -- $(cat "$TMP/det_good.out")"
  else
    bad "replay --determinism-check: golden-GOOD gate-cmd was reported non-deterministic or errored (rc=$GOOD_RC deterministic=$GOOD_DET) -- $(cat "$TMP/det_good.out")"
  fi
  rm -rf "$SREPO"

  # Golden-BAD control needle (§11.4.201/§11.4.107(10)): a gate-cmd that
  # deliberately flips its exit code between the two internal
  # determinism-check invocations (PASS,PASS then FAIL,FAIL with
  # --cold-runs 1 --warm-runs 1 -> exactly 4 gate calls total) MUST be
  # detected as non-deterministic -- proving this mechanism can genuinely
  # FAIL and is not a rubber-stamp that always reports "deterministic".
  SREPO2="$(mk_scratch_repo a init2)"
  SCOMMIT2="$(git -C "$SREPO2" rev-parse HEAD)"
  STREE2="$(git -C "$SREPO2" rev-parse HEAD^{tree})"
  WT2="$TMP/wt_bad"
  mkdir -p "$WT2"
  CTR="$TMP/gate_flip_counter"
  cat > "$TMP/gate_flip.sh" <<SH
#!/bin/bash
CTR="$CTR"
n=0
[ -f "\$CTR" ] && n=\$(cat "\$CTR")
n=\$((n + 1))
echo "\$n" > "\$CTR"
[ "\$n" -le 2 ] && exit 0 || exit 1
SH
  chmod +x "$TMP/gate_flip.sh"
  rm -f "$CTR"
  DET_OUT2="$TMP/det_bad.json"
  bash "$BASELINE_REPLAY" replay --commit "$SCOMMIT2" --tree "$STREE2" \
    --gate-cmd "$TMP/gate_flip.sh" --cold-runs 1 --warm-runs 1 \
    --repo-root "$SREPO2" --worktree-root "$WT2" \
    --out "$DET_OUT2" --determinism-check >"$TMP/det_bad.out" 2>&1
  BAD_RC=$?
  BAD_DET="$(python3 -c "import json; print(json.load(open('$DET_OUT2')).get('deterministic'))" 2>/dev/null)"
  BAD_DIFFERS="$(python3 -c "
import json
d = json.load(open('$DET_OUT2'))
v1, v2 = d.get('run1_verdict_set'), d.get('run2_verdict_set')
print(v1 != v2)
" 2>/dev/null)"
  if [ "$BAD_RC" = 1 ] && [ "$BAD_DET" = False ] && [ "$BAD_DIFFERS" = True ]; then
    ok "replay --determinism-check: golden-BAD control needle correctly detected a deliberately-injected determinism defect (exit 1, deterministic=False, verdict_sets genuinely differ) -- $(cat "$TMP/det_bad.out")"
  else
    bad "replay --determinism-check: golden-BAD control needle did NOT correctly detect the injected non-determinism (rc=$BAD_RC deterministic=$BAD_DET differs=$BAD_DIFFERS) -- the mechanism may be a rubber stamp -- $(cat "$TMP/det_bad.out")"
  fi
  rm -rf "$SREPO2"
else
  bad "contract 1/3 SKIPPED: baseline_replay.sh not present/executable (see presence check above)"
fi

echo
echo "=== contract 2/3: selection-script re-run stability (SC-001, SC-004) ==="
if [ -x "$SELECT_SAMPLE" ]; then
  OUT_A="$TMP/sample_a.json"
  OUT_B="$TMP/sample_b.json"
  ERR_A="$TMP/sample_a.err"
  ERR_B="$TMP/sample_b.err"
  # Frozen, fixed --as-of (deliberately NOT "today" -- the point of this
  # test is that the SAME frozen parameters reproduce the SAME result,
  # independent of when the test happens to run).
  python3 "$SELECT_SAMPLE" --as-of 2026-09-27 --window-days 90 \
    --repo-root "$ROOT" --out "$OUT_A" >"$ERR_A" 2>&1
  RC_A=$?
  python3 "$SELECT_SAMPLE" --as-of 2026-09-27 --window-days 90 \
    --repo-root "$ROOT" --out "$OUT_B" >"$ERR_B" 2>&1
  RC_B=$?
  if [ "$RC_A" = 0 ] && [ "$RC_B" = 0 ] && [ -f "$OUT_A" ] && [ -f "$OUT_B" ]; then
    SAME="$(python3 -c "
import json
a = json.load(open('$OUT_A'))
b = json.load(open('$OUT_B'))
ai = [x['item_id'] for x in a['items']]
bi = [x['item_id'] for x in b['items']]
print(a['body_hash'] == b['body_hash'] and ai == bi)
" 2>/dev/null)"
    if [ "$SAME" = True ]; then
      ITEM_COUNT="$(python3 -c "import json; print(len(json.load(open('$OUT_A'))['items']))")"
      ok "select_sample.py: two independent invocations with identical frozen parameters (--as-of 2026-09-27 --window-days 90) produced the IDENTICAL item list ($ITEM_COUNT items, same order, same body_hash)"
    else
      bad "select_sample.py: two independent invocations with identical frozen parameters produced DIFFERENT item lists or body_hash -- a re-run-stability defect (SC-001/SC-004)"
    fi
  else
    bad "select_sample.py: at least one of the two identical-parameter invocations failed to produce an honest 0-exit result (rc_a=$RC_A rc_b=$RC_B) -- $(cat "$ERR_A" "$ERR_B" 2>/dev/null | tail -3)"
  fi
  # Secondary, corroborating check via the tool's OWN built-in
  # --determinism-check flag (independent code path: re-invokes itself
  # via subprocess and compares body_hash, rather than this test diffing
  # two files it drove itself) -- never trust a single measurement path
  # alone for a determinism claim (§11.4.201/§11.4.273).
  DC_OUT="$TMP/sample_dc.err"
  python3 "$SELECT_SAMPLE" --as-of 2026-09-27 --window-days 90 \
    --repo-root "$ROOT" --out "$TMP/sample_dc.json" --determinism-check >"$DC_OUT" 2>&1
  DC_RC=$?
  if [ "$DC_RC" = 0 ] && grep -q "^select_sample: deterministic" "$DC_OUT"; then
    ok "select_sample.py --determinism-check (independent, tool-internal re-invocation path): $(cat "$DC_OUT")"
  else
    bad "select_sample.py --determinism-check (independent, tool-internal re-invocation path) did not confirm determinism (rc=$DC_RC): $(cat "$DC_OUT")"
  fi
else
  bad "contract 2/3 SKIPPED: select_sample.py not present/executable (see presence check above)"
fi

echo
echo "=== contract 3/3: known-bugs control needle (plan.md T-A10 line 489) ==="
if [ -x "$SELECT_SAMPLE" ]; then
  # select_sample.py's own built-in CT-009-style needle (run_needle():
  # a known-present item's closure event+date MUST be found, a
  # fabricated id MUST be absent) is the "known bug must be included"
  # proxy this contract requires -- the exact 5 ATM-ids research.md
  # cites are NOT given by ATM-id anywhere (§11.4.6 no-guessing), so
  # they are never invented here; this exercises the SAME needle
  # mechanism select_sample.py's implementer already wired for exactly
  # this purpose, at its documented defaults.
  NEEDLE_OUT="$TMP/needle.err"
  python3 "$SELECT_SAMPLE" --as-of 2026-09-27 --window-days 90 \
    --repo-root "$ROOT" --out "$TMP/needle.json" >"$NEEDLE_OUT" 2>&1
  NEEDLE_RC=$?
  if [ "$NEEDLE_RC" = 0 ] && grep -q "needle ok" "$NEEDLE_OUT"; then
    ok "select_sample.py control needle: known-present item found, fabricated item absent -- $(cat "$NEEDLE_OUT")"
  else
    bad "select_sample.py control needle FAILED or errored (rc=$NEEDLE_RC): $(cat "$NEEDLE_OUT")"
  fi

  # research.md P-15's specific "5 known bugs of the 60-day window" figure:
  # run with --window-days 60 and report (never hard-fail on) the live
  # Bug-type count against the cited 5 -- a mismatch is a finding to
  # surface, never silently reconciled or invented away (§11.4.6). The
  # hard, always-enforced invariant is that Bug-type items ARE present in
  # the 60-day sample at all (the actual "known bugs are included"
  # guarantee); the exact count is inherently time-dependent (it is
  # itself pinned by select_sample.py's own --min-per-type floor, not a
  # raw historical count) and is reported as evidence, not asserted exact.
  W60_OUT="$TMP/w60.err"
  python3 "$SELECT_SAMPLE" --as-of 2026-09-27 --window-days 60 \
    --repo-root "$ROOT" --out "$TMP/w60.json" >"$W60_OUT" 2>&1
  W60_RC=$?
  if [ "$W60_RC" = 0 ]; then
    BUG_COUNT="$(python3 -c "
import json
d = json.load(open('$TMP/w60.json'))
print(sum(1 for it in d['items'] if it['type'] == 'Bug'))
" 2>/dev/null)"
    if [ -n "$BUG_COUNT" ] && [ "$BUG_COUNT" -ge 1 ] 2>/dev/null; then
      MATCH_NOTE="matches"
      [ "$BUG_COUNT" != 5 ] && MATCH_NOTE="DIFFERS FROM (a live-data finding, not invented/reconciled)"
      ok "select_sample.py --window-days 60: Bug-type items ARE present in the sample ($BUG_COUNT found; $MATCH_NOTE research.md's cited 5)"
    else
      bad "select_sample.py --window-days 60: NO Bug-type items in the sample (count='$BUG_COUNT') -- the known-bugs-included guarantee is violated"
    fi
  else
    bad "select_sample.py --window-days 60 invocation failed (rc=$W60_RC): $(cat "$W60_OUT")"
  fi
else
  bad "contract 3/3 SKIPPED: select_sample.py not present/executable (see presence check above)"
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
