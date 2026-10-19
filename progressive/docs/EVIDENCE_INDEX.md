# Evidence index

`EVIDENCE/INDEX.json` is the machine-parseable index (sha256 per artifact);
this table is its human companion. `validate_evidence.py` fails if an artifact is
missing, unindexed, stale, or differs from its recorded sha256.

| Artifact | Producer | Content |
|---|---|---|
| `EVIDENCE/INDEX.json` | `gen_evidence.py` | every artifact below with sha256, bytes, producer |
| `EVIDENCE/PREFLIGHT_MANIFEST.json` | `gen_evidence.py` | sha256 of every file in the constitution submodule tree (excl. `.git`, `__pycache__`, `EVIDENCE/`) |
| `EVIDENCE/ANCHORS.json` | `gen_evidence.py` | independent anchor inventory of `Constitution.md` + twins, cross-checked against `catalog.json` |
| `EVIDENCE/CONSUMERS.json` | `gen_evidence.py` | read-only scan of the parent repo for every reference to the constitution |
| `EVIDENCE/KNOWN_ISSUES.md` | `gen_evidence.py` | non-PASS output of the four existing validators |
| `EVIDENCE/RISK_REGISTER.md` | hand-authored | risk register (moved from `docs/RISK_REGISTER.md`) |
| `EVIDENCE/STRUCTURE.json` | `validate_structure.py --evidence` | 5 checks, ok flag |
| `EVIDENCE/BEHAVIOR.json` | `validate_behavior.py --evidence` | search/load/list/verify results |
| `EVIDENCE/TOKENS.json` | `validate_tokens.py --evidence` | token counts + UNCONFIRMED live item |
| `EVIDENCE/SUBMODULE.json` | `validate_submodule.py --evidence` | pin, recursion, clean tree |
| `EVIDENCE/MUTATIONS.json` | `mutation_matrix.py --evidence` | 20 mutation outcomes |
| `EVIDENCE/MCP_SELFTEST.txt` | `mcp_server.py --selftest` | tool round-trip, stdout |
| `EVIDENCE/DISCREPANCIES.md` | hand-authored from measured output | twin/undefined-anchor, catalog-budget, catalog-omission findings |
| `EVIDENCE/mcp_accounting.jsonl` | `mcp_server.py --accounting` | one JSON line per tool call (append-only; not indexed) |

Regenerate and verify, in this order (the matrix needs a fresh index, and
rewriting `MUTATIONS.json` makes the index stale again):

```bash
python3 progressive/gen_evidence.py
python3 progressive/mutation_matrix.py --evidence progressive/EVIDENCE/MUTATIONS.json
python3 progressive/gen_evidence.py
python3 progressive/validate_evidence.py
python3 progressive/gen_evidence.py --check
```

Every artifact is machine-produced except the two named hand-authored ones, whose
numbers come from captured command output. No screenshot is used as evidence.
