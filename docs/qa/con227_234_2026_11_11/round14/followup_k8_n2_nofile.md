# Follow-up draft: K8 N2 accepts the loop-guard mutant B2 under a soft descriptor limit of 1024

| Field | Value |
|---|---|
| Status | DRAFT follow-up (Type Task, test-instrumentation; §11.4.276(G.2), §11.4.261). Not yet minted in the tracker database: this vehicle is a scratch clone; the item is minted at the landing on `main` (§11.4.214: link it to CON-234, never a second id for the same weakness) |
| Parent | CON-234 (round-13 review F3, `review_fix227_r13.md`) |
| Layer | test-instrumentation (`tests/release/test_redact_cut.sh`, case K8 N2); no release script is wrong |
| Reproduction | `reproduced-live` by the round-13 review: `--only B2`, soft NOFILE 1024 2/2 "killed, but not by its property", soft NOFILE 524288 2/2 "killed by its property"; round 13 `b2_investigation/` |
| Investigation | `root-cause-found-with-evidence` for the toggle (the soft limit flips the verdict, two-way, 2/2 each); the mechanism line ("Too many open files" at the exec redirection) is stated by the round-13 producer probes and UNCONFIRMED by the reviewer |

## What is weak

B2 removes the loop guard of `rc_env_clean` (`scripts/release/redact_cut.sh`). K8 N2 checks only that the probe
`p5.sh` ends with `rc=4` and `a0=rc-clean-env` within `timeout 30`. Without the guard the probe re-executes itself
and leaks one descriptor per pass; at a soft `RLIMIT_NOFILE` of 1024 the `exec` fails after about 8 s with "too
many open files", `shopt -s execfail` keeps the shell, and `rc_env_clean` returns 4: the probe prints exactly what
K8 N2 wants. So the property K8 N2 names ("a marked process that is not clean refuses instead of re-executing
again") is not what it measures at that limit. B2 is still killed (by K6), so no defect ships; the weakness is that
the property check can pass while the property is false.

## Proposed fix (to be done test-first, §11.4.224)

1. RED: run the redact suite with the B2 mutant under `ulimit -Sn 1024`; K8 N2 passes (today's behaviour).
2. Make K8 N2 count the passes: the probe writes one line per entry into `rc_env_clean` (a builtin `printf` to a
   file named on fd 8 or by a variable the probe sets), and K8 N2 requires exactly 2 entries (the caller pass and
   the one re-executed pass) besides `rc=4` and `a0=rc-clean-env`.
3. GREEN: the unmutated library gives 2 entries at 1024 and at 524288; B2 gives more than 2 at both limits, so
   `--only B2` is "killed by its property" at both limits (N >= 3 each).
4. Record the soft and hard NOFILE of the standing run in its evidence (the round-13 run did not).

## Related nit (round-13 review F4, second half)

The pin `tests/release/netgate_pin.tsv` gives each F row a line count of newline count plus one: the L rows include
one row for the empty string after the final newline (for example `derive_release_facts.sh 167`, last L row key
`e3b0c442`, the sha256 prefix of the empty string). Harmless (the F row's sha256 binds the bytes). The header sentence
belongs in `channel_census.py pin-regen` (the pin is never edited by hand); deferred to this follow-up so the gate
code is not changed in round 14 without its own mutants.
