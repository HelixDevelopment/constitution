# Separate note (review R7-G, outside this vehicle; nothing changed here)

`helix-deps.yaml` line 92 records llmctl `ref: 3877467  # pinned sha = the recorded gitlink`, but the recorded gitlink
is `391d8177`. The round-7 reviewer measured (read-only) that 3877467 is an ancestor of 391d8177, 10 commits apart,
with `lib/` and `bin/` identical. The comment is therefore false and the ref is stale; the README sentence
"UNCONFIRMED whether the same commit" can say "not the same commit; same lib/bin". Not re-measured in round 8. It is a
manifest fix of its own (one line plus the README sentence), to be filed as `CON-PENDING-DEPS-LLMCTL-REF`.
