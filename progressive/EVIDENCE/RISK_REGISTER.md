# Risk register

| Risk | Likelihood | Mitigation | Residual |
|---|---|---|---|
| Generated layer drifts from source | medium | `--check` reproducibility gate + `rules_manifest.json` hashes | none (gate catches it) |
| A consumer reads a stale rule | low | `verify_anchor` recomputes the hash against `rules_manifest.json` | none |
| Evidence artifacts go stale after an edit | medium | `validate_evidence.py` fails on a stale manifest/anchors/index; `gen_evidence.py --check` diffs a regeneration; matrix mutations M-13..M-19 | none (gate catches it) |
| Agent loads the monolith anyway | medium | core explicitly forbids full reads when an id is known; M4 documents it | behavioural, not mechanical — recorded |
| Token reduction not proven | **present** | harness refuses to PASS without live usage objects | **UNCONFIRMED until a provider run exists** |
| Twin files reference undefined anchors | present in source | `twin_exceptions.txt` records the measured set; `EVIDENCE/DISCREPANCIES.md` lists it | source-side debt, not introduced here |
| Namespace collision with another MCP | low | all names prefixed `helix-constitution` | none |

Residual risks requiring a second independent reviewer: the token-reduction item
(UNCONFIRMED) and the twin/undefined-anchor debt. Both are stated, not signed off.
