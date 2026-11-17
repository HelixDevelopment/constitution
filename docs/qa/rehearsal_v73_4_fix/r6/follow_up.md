# CON-423 round 6: follow-up items (proposed, not filed)

| Field | Value |
|---|---|
| Item | CON-423 |
| Round | 6 |
| Status | proposals for the conductor; no tracker write was made |

1. Snapshot retry has no deterministic test. `snapshot_db` retries when the
   database files change during the copy; forcing that race needs a hook in
   the copy loop. Proposal: a test seam (an injected callback between the
   copy and the second stat), with a paired mutant `if True: return dst`.
2. Stricter refusals kept (safe direction): a line after a link reference
   definition, a fence after a blank line inside a list item, NBSP and FF at
   the start of a line. Each is refused although markdown-it shows the line.
   Proposal: model link reference definitions only if a real tracker body
   needs it.
3. The real database gives the same 29 refused items as in r5 (same ids).
   Five of them (CON-144, CON-186, CON-189, CON-190, CON-191) now carry the
   near-rule reason instead of "no line": their bodies hold a labelled line
   that is not the counted line. They need their bodies rewritten, the same as
   the job-field refusals.
4. markdown-it-py is a reference reader, not ground truth. A body both
   readers misread is not detected.
5. The r5 probes (probe_e2e_r5.py.txt, probe_lm_r5.py.txt) are vendored but
   not run inside P11; their r6 outputs are in this directory. Proposal: add
   them to P11 with needles.
