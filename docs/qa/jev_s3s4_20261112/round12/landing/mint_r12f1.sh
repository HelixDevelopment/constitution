#!/bin/bash
# mint_r12f1.sh <repo>: round 12, file finding R12-F1 (found by R12-10, tests/jev/test_s4_round12_mc.sh) through the
# workable-items engine (never a hand-edited DB), PWD = the repo root, --prefix CON. Prints "R12-F1 <id>".
set -euo pipefail
REPO="${1:?repo}"
cd "$REPO"
W=scripts/workable-items/bin/workable-items; DB=docs/workable_items.db; BY=jev-r12-fixer
D="What: in a three-process interleaving, a third acquire treats a constitution-started local decision model as operator-started. Sequence: acquire A's slow start returns (its starting mark already judged expired); acquire B's dispose-stop records its result and deletes the set before A records the start; acquire C sees a running unit with no set and joins it as operator-started ('joined the already-running unit'); A's later record makes the set constitution-started again. In that window C would never stop the unit. Found by R12-10 in orders starCA and straCA of 60 (docs/qa/jev_s3s4_20261112/round12/README.md, runs/r12mc_head_discovery_R12-F1.txt). Reproduction: gate-logic only (stub llmctl, hermetic runner), not on a live host, so the state is UNREPRODUCED under section 11.4.292. In every order a running unit stays held or owed a stop and the cleanup leaves nothing running. Fix (producer change, open): keep a record of an in-flight start that survives the set deletion, or refuse adoption while a recent dispose of the profile is unanswered. Acceptance: R12-10's pinned adoption list becomes empty and is asserted empty, RED on the current producer."
out="$("$W" add Bug Medium --db "$DB" --prefix CON --title "Jev placement: a third acquire adopts a constitution-started unit as operator-started after a dispose deleted its set before a slow start was recorded (R12-F1)" --description "$D" --reproduction-state UNREPRODUCED --investigation-state root-cause-unconfirmed --states-updated-by "$BY" 2>&1)"
id="$(printf '%s\n' "$out" | sed -n 's/^add: created \(CON-[0-9]*\) .*/\1/p')"
[ -n "$id" ] || { echo "mint R12-F1 failed: $out" >&2; exit 1; }
printf 'R12-F1 %s\n' "$id"
