# Rollout

| Stage | Action | Go/no-go |
|---|---|---|
| 0 | Land the generated layer + validators (this delivery) | structure/behavior/submodule PASS, matrix 12/12 |
| 1 | Consumers keep `HELIX_CONSTITUTION_MODE=monolith` for one cycle | no consumer breakage reported |
| 2 | Flip new sessions to `progressive` (default) | the token measurement completes and passes |
| 3 | Remove the monolith preload from consumer agent configs | one full cycle with no rule-loading failure |

Rollback at any stage: `HELIX_CONSTITUTION_MODE=monolith`.
