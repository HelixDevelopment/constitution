#!/bin/bash
# mint.sh <repo>: round 11 (re-mint at the landing on main bcac0882). Files the Jev S3/S4 item and its four drafts through
# the workable-items engine (never a hand-edited DB),
# PWD = the repo root, --prefix CON. Prints "<key> <id>" per item to stdout; the ids are read back from the DB.
set -euo pipefail
REPO="${1:?repo}"
cd "$REPO"
HERE=docs/qa/jev_s3s4_20261112/round11/landing
W=scripts/workable-items/bin/workable-items; DB=docs/workable_items.db; BY=jev-r11-fixer
add() { # add <key> <type> <sev> <title> <desc> [state flags...]
  local k="$1" ty="$2" sv="$3" ti="$4" de="$5"; shift 5
  local out; out="$("$W" add "$ty" "$sv" --db "$DB" --prefix CON --title "$ti" --description "$de" "$@" 2>&1)"
  local id; id="$(printf '%s\n' "$out" | sed -n 's/^add: created \(CON-[0-9]*\) .*/\1/p')"
  [ -n "$id" ] || { echo "mint $k failed: $out" >&2; exit 1; }
  printf '%s %s\n' "$k" "$id"
}
JD="$(cat "$HERE/jev_desc.txt")
Ids: this item was carried on the vehicle as CON-299 (rounds 1 to 7), CON-PENDING-JEV (rounds 8 to 10) and, in the trailer of dc654757, CON-PENDING-JEV-CONSTITUTION. main minted CON-299 for another item (land_vehicle lander), so this item is minted anew at landing (§11.4.54, §11.4.214). The round-10 landing pack (never landed) minted it as CON-388 on the vehicle database; main then minted CON-388 to CON-400 for other items, so it was minted again at the round-11 landing. Commit trailers are not rewritten; the mapping note is in CHANGELOG.md and docs/qa/jev_s3s4_20261112/round10/README.md.
Status: rounds 1 to 11 of independent review; the round-11 head is gate-logic evidence only (§11.4.289(C)(2)), PROVISIONAL (§11.4.290); live acceptance (T5 local placement) is open."
JL="$(add JEV Task High "Jev S3/S4: honest bootstrap exit codes, default-on wiring, capacity-gated local placement, per-endpoint calibration, status control view" "$JD")"
printf '%s\n' "$JL"
# the Jev item is the item being worked: In progress (run once, after the add; recorded here so the mint is replayable)
"$W" update --id "${JL#JEV }" --db "$DB" --status "In progress" >&2
add O6-1 Bug Medium "Intermittent failure of tests/jev/test_review_fixes_r2.sh P2 (bootstrap row), root cause UNKNOWN" \
"What: P2 of tests/jev/test_review_fixes_r2.sh failed once in a full run during Jev round 6 and has not been seen again; round 7 added an instrument (keep_bs_evidence keeps bs.out/err, gate.out, status.json, cap.json and the rc). Reproduction: 12 of 12 standalone repetitions and every run_all run passed (round 7); not reproduced in rounds 8 to 10. Next: run P2 in a loop under normal host load (at least 50 runs) and keep every instrument dump of a failure. Acceptance: a captured failing run with the instrument output, a root cause shown by a decisive experiment (§11.4.292(G)) and a RED-to-GREEN row, or closure as not-reproducible with the attempts and a control needle. Draft: docs/qa/jev_s3s4_20261112/round8/item_draft_O6-1.md (was CON-PENDING-O6-1)." \
  --reproduction-state UNREPRODUCED --investigation-state not-started --states-updated-by "$BY"
add CLOCK-BOOTSTRAP Bug Low "Jev bootstrap.sh and jev-calibrate.sh stamp record times with the process-start clock after long work" \
"What: scripts/jev/bootstrap.sh and scripts/jev/jev-calibrate.sh read the clock once at process start and stamp generated_at, probed_at, pending_at, first_created and calibrated_at with it after long work (probes). The error makes records look older (fail-closed for freshness checks); no unsafe effect is known. Fix: stamp each field at write time. Found by the Jev round-8 census (census_stale_clock.md). Draft: docs/qa/jev_s3s4_20261112/round8/item_draft_clock_bootstrap.md (was CON-PENDING-CLOCK-BOOTSTRAP)." \
  --reproduction-state UNREPRODUCED --investigation-state root-cause-unconfirmed --states-updated-by "$BY"
add MONO-FALLBACK Task Low "Jev placement: ages on wall time where no monotonic source exists (decide fail-closed or a visible warning)" \
"What: scripts/jev/jev-place.sh judges mark and lease ages on a monotonic clock (boot id and uptime) where /proc provides one; a host without readable /proc, and records written by an older producer without mono, are judged on wall time, so a wall-clock step can expire a live mark or lease early or keep a dead one late. Acceptance: an operator decision (§11.4.66) between refusing local placement on such a host (fail closed to the fallback route) and keeping the wall-time rule with a visible warning in status; either way status --json names the clock source in use (monotonic or wall) and a test pins it. Draft: docs/qa/jev_s3s4_20261112/round9/item_draft_mono_fallback.md (was CON-PENDING-MONO-FALLBACK)."
add DEPS-LLMCTL-REF Task Low "helix-deps.yaml llmctl ref is stale: records 3877467 while the recorded gitlink is 391d8177" \
"What: helix-deps.yaml records llmctl ref 3877467 with the comment 'pinned sha = the recorded gitlink', but the recorded gitlink is 391d8177. The Jev round-7 reviewer measured (read-only) that 3877467 is an ancestor of 391d8177, 10 commits apart, with lib/ and bin/ identical, so the comment is false and the ref is stale. Fix: one manifest line plus the README sentence (not the same commit; same lib/bin), re-measured before the change. Note: docs/qa/jev_s3s4_20261112/round8/note_R7-G.md (was CON-PENDING-DEPS-LLMCTL-REF)."
