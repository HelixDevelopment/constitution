# Optimization plan (progressive disclosure)

Source: `docs/requests/optimizations/02_quality_optimization.md`.
Canonical text is **never modified**: `Constitution.md` stays byte-identical to
its baseline; the split artifacts are generated from it.

## Phases and acceptance criteria

| Phase | Deliverable | Acceptance (deterministic) | Status |
|---|---|---|---|
| 0 — Baseline | anchor + consumer inventory, hashes | `validate_structure.py` PASS | DONE |
| 1 — Generator | `generate_split.py` → `catalog.json` + `rules_manifest.json` + `rules/` | `--check` byte-identical on re-run | DONE (289 anchors) |
| 1 — Lean core | `core.md` | ≤3000 tokens, byte-stable prefix | DONE (999 tokens) |
| 2 — Meta-tools | `mcp_server.py` (4 tools, stdio) | `--selftest` PASS, accounting per call | DONE |
| 2 — Surfaces | skill, plugin, LSP, codegraph, mcp template | files present, plugin/skill defer rule stated | DONE |
| 2 — Validation | 5 validators (incl. `validate_evidence.py`) + 20-mutation matrix | matrix 20/20 flips | DONE |
| 2 — Evidence | `gen_evidence.py` → manifest, anchors, consumers, known issues, index | `gen_evidence.py --check` byte-identical; `validate_evidence.py` PASS | DONE |
| 3 — Token measurement | real provider BEFORE/AFTER | usage objects present, AFTER ≤40% | **UNCONFIRMED** (no provider object on this host) |
| 3 — Rollout | consumer adoption | consumer runs the gates green | PARTIAL (this consumer wired) |

## Rollback

`HELIX_CONSTITUTION_MODE=monolith` restores the pre-optimization behaviour
exactly: only `Constitution.md` is used; the generated layer is ignored.

## Owners

| Area | Owner |
|---|---|
| generator + catalog | constitution maintainer |
| validators + mutations | QA / anti-bluff reviewer |
| consumer integration | consuming project |
