# Relayed operator decision, 2026-11-16 night: landing mode of the release queue

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Last modified | 2026-11-17 |
| Status | PROVISIONAL |
| Source | relayed operator answer of 2026-11-16, about 23:50: the operator answered an interactive question of the conductor; the conductor relayed the answer to the fixer agent (CON-PENDINGrel2 vehicle) in the operator's words of intent. Not verbatim. |
| Recorded by | fixer subagent (Opus 5.5), scratch clone, from the conductor's relay of 2026-11-17 |
| Exact wording | UNCONFIRMED: the operator's own words are not in this repository; the text below is the relayed meaning |

This record is the §11.4.66 / §11.4.215 tracked record of one relayed answer. It was written after the review of
`e5efbf77` (finding F7) found that the release entry template cited decision 8 of
`docs/operator_decisions/2026-11-11_relayed_decisions.md` for the release landing, a decision that predates and is
superseded by the pull-request delivery declaration `config/delivery.conf` (decision ids
`OPD-2026-11-16-PR-DELIVERY` and `OPD-2026-11-16-PR-DELIVERY-R2`), and called the landing question open although
the operator had answered it.

## Decision (relayed, not verbatim)

Landing mode for the rest of the current release queue: fast-forward push to every upstream, no pull requests.
Pull-request mode (`config/delivery.conf`, `mode=pr`) applies after the release.

## What it does not say

- It does not make `config/delivery.conf` ENFORCED: that file stays a PROVISIONAL declaration (§11.4.297(G)).
- It does not change any review or GO requirement: every change still needs its independent review GO before it
  lands (§11.4.142, §11.4.288(B)(1)).
- It names no end of "the release queue" other than the release itself; when the release is cut is not stated
  here.

The operator may correct the wording; until then this record is PROVISIONAL and its wording UNCONFIRMED.
