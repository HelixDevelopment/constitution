# Tracked item draft: CON-PENDING-CLOCK-BOOTSTRAP (no id minted)

- Type: Bug (low). Status: Queued. Reproduction: none — UNREPRODUCED. Investigation: root-cause-unconfirmed.
- `scripts/jev/bootstrap.sh:134` and `scripts/jev/jev-calibrate.sh:56` read the clock once at process start and
  stamp `generated_at`, `probed_at`, `pending_at`, `first_created` and `calibrated_at` with it after long work
  (probes). The error makes records look older (fail-closed for freshness checks), so no unsafe effect is known;
  stamping each field at write time would make the records exact. Found by the round-8 census
  (`census_stale_clock.md`). Roadmap-Item: CON-PENDING-JEV.
