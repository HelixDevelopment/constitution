# Validation matrix

Every gate, its mutation, the command that proves the mutation fails, and the
evidence path. Executed by `progressive/mutation_matrix.py` (12/12 PASS).

| ID | Gate | Injected defect | Observed |
|---|---|---|---|
| M-01 | `test_core_budget` | append ~5k tokens to `core.md` | mutated FAIL → restored PASS |
| M-02 | `test_anchor_integrity` | delete §11.4.141 from `catalog.json` | mutated FAIL → restored PASS |
| M-03 | `test_twin_consistency` | remove §11.4.141 from every twin | mutated FAIL → restored PASS |
| M-04 | `test_split_reproducible` | hand-edit one byte of a rule file | mutated FAIL → restored PASS |
| M-05 | `test_core_budget` | replace `core.md` with the monolith | mutated FAIL → restored PASS |
| M-06 | `test_cache_warm` | inject a volatile marker into the prefix | mutated FAIL → restored PASS |
| M-07 | `test_catalog_description` | empty the §11.4.141 description | mutated FAIL → restored PASS |
| M-08 | `test_load_rule_body` | point the catalog at another rule | mutated FAIL → restored PASS |
| M-09 | `test_pinned_revision` | advance the consumer pin without HEAD | mutated FAIL → restored PASS |
| M-10 | `test_recursive_fetch` | uninitialised nested submodule in the status | mutated FAIL → restored PASS |
| M-11 | `test_evidence_presence` | PASS without writing evidence | mutated FAIL → restored PASS |
| M-12 | `test_no_placeholders` | plant a placeholder marker | mutated FAIL → restored PASS |

Mutations run against a hardlink sandbox of the real tree; the live repository is
never modified (`progressive/EVIDENCE/MUTATIONS.json`).

```bash
python3 progressive/validate_structure.py
python3 progressive/validate_behavior.py
python3 progressive/validate_tokens.py          # exit 3 = live measurement absent
python3 progressive/validate_submodule.py
python3 progressive/mutation_matrix.py
```
