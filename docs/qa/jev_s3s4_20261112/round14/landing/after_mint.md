# For the lander: after the six vehicle items are re-minted

This round does not mint ids: `main` holds other items under CON-423 to CON-428, and ids are minted only through the
workable-items engine, by whoever lands the vehicle. The steps below are what this round would have done with ids; they
are NOT run here and nothing below claims they were.

1. Re-mint the six items from `vehicle_items_before_merge.md` through the engine (`workable-items add`, then `update`
   for the reproduction and investigation states as recorded there), in the order of the table, never by editing the
   database by hand. Record the new ids next to the placeholders.
2. For the item CON-PENDINGjev6 (R12-F1, with R12-B1 and R13-B1), point its investigation evidence at the final round-14
   run, through the engine:
   `scripts/workable-items/bin/workable-items update --id <new id> --db docs/workable_items.db --investigation-evidence docs/qa/jev_s3s4_20261112/round14/runs/final1_r14.txt --states-updated-by <lander>`
   The reproduction state stays as recorded in `vehicle_items_before_merge.md` (gate-logic, host-fixture class); this
   round adds no live run.
3. Replace each placeholder with its new id in the vehicle's prose and nowhere else:
   `CHANGELOG.md` (the Jev round entries only), `docs/jev/governance-guide.md`, `docs/qa/jev_s3s4_20261112/README.md`,
   `docs/qa/jev_s3s4_20261112/round12/README.md`, `docs/qa/jev_s3s4_20261112/round13/README.md`,
   `docs/qa/jev_s3s4_20261112/round14/README.md`, and this directory's `vehicle_items_before_merge.md` table (add a
   column). The machine-produced landing files of rounds 12 and 13 keep the ids they were written with. Refresh each
   touched evidence directory's `SHA256SUMS`.
4. Run `workable-items export --no-formats` and `diff` (in sync), `validate`, `--sync-guide`, `--verify-manifest`.
5. The commits of this round carry `Roadmap-Item: CON-PENDINGjev1` (and CON-PENDINGjev6 where the change is the R13-B1
   fix); the landing commit names the new ids.
