# Evidence index

| Artifact | Producer | Content |
|---|---|---|
| `EVIDENCE/STRUCTURE.json` | `validate_structure.py --evidence` | 5 checks, ok flag |
| `EVIDENCE/BEHAVIOR.json` | `validate_behavior.py --evidence` | search/load/list/verify results |
| `EVIDENCE/TOKENS.json` | `validate_tokens.py --evidence` | token counts + UNCONFIRMED live item |
| `EVIDENCE/SUBMODULE.json` | `validate_submodule.py --evidence` | pin, recursion, clean tree |
| `EVIDENCE/MUTATIONS.json` | `mutation_matrix.py --evidence` | 12 mutation outcomes |
| `EVIDENCE/DISCREPANCIES.md` | manual (measured) | twin/undefined-anchor findings |
| `EVIDENCE/mcp_accounting.jsonl` | `mcp_server.py --accounting` | one JSON line per tool call |

Every artifact is machine-produced. No screenshot and no prose is used as
evidence anywhere in this layer.
