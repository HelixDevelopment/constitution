# Fixture: plan_struct_causes / golden-bad-orphan

Identical to the golden-good fixture except RC-03's LAST column ("Removed /
measured by") cell is EMPTY -- the row names no task at all. Per
research.md's own §2 preamble (lines 164-166 of the real document): "Task
ids in the last column refer to the phased plan in plan.md ... Every row is
removed or measured by at least one task ... (no orphan cause, no orphan
task -- checked mechanically by T-H08)." A row whose last cell is blank is
an orphan cause at the register level -- detectable from research.md alone
(no cross-reference to plan.md's own task list is needed for THIS check;
that deeper bipartite cross-check against plan.md's actual tasks is SC-C-003,
the separate `plan` subcommand). Expected `causes` verdict: exit 1, naming
RC-03.

## 2. Root-cause register

### 2.1 Register table

| RC | Cause | Origin | Class | Measured magnitude (named denominator) | Share of total cycle | Evidence | Settling evidence / what remains | Removed / measured by |
|---|---|---|---|---|---|---|---|---|
| RC-01 | Fixture cause one | O1 | **CONFIRMED** | 1 of 1 fixture measurement | UNMEASURED | fixture evidence line one | settling note (T-X01) | T-X01 |
| RC-02 | Fixture cause two | O2 | **CONFIRMED** | 1 of 1 fixture measurement | UNMEASURED | fixture evidence line two | settling note (T-X02) | T-X02 |
| RC-03 | Fixture cause three | O3 | **REFUTED** | fixture refutation note | n/a | fixture evidence line three | n/a |  |
| RC-04 | Fixture cause four | O4 | **UNDETERMINED** | fixture magnitude unmeasured | UNMEASURED | fixture evidence line four | settling evidence needed (T-X04) | T-X04 |

### 2.2 Register counts (machine count over the Class column of §2.1)

| Class | Rows | Row ids |
|---|---|---|
| CONFIRMED | 2 | RC-01, RC-02 |
| REFUTED | 1 | RC-03 |
| UNDETERMINED | 1 | RC-04 |
| **Total** | **4** | |
