# Fixture: plan_struct_causes / golden-bad-count-mismatch

Identical to the golden-good fixture (every Class cell and every last-column
cell populated, no per-row defect) except the §2.2 "Register counts" table
states CONFIRMED = 3 while §2.1 actually contains exactly 2 CONFIRMED rows
(RC-01, RC-02). Per contract plan-research-structural-check.md SC-C-001:
"the class counts equal research.md §2.2" -- this fixture makes them
disagree. Expected `causes` verdict: exit 1, naming the CONFIRMED class
(stated 3, actual 2).

## 2. Root-cause register

### 2.1 Register table

| RC | Cause | Origin | Class | Measured magnitude (named denominator) | Share of total cycle | Evidence | Settling evidence / what remains | Removed / measured by |
|---|---|---|---|---|---|---|---|---|
| RC-01 | Fixture cause one | O1 | **CONFIRMED** | 1 of 1 fixture measurement | UNMEASURED | fixture evidence line one | settling note (T-X01) | T-X01 |
| RC-02 | Fixture cause two | O2 | **CONFIRMED** | 1 of 1 fixture measurement | UNMEASURED | fixture evidence line two | settling note (T-X02) | T-X02 |
| RC-03 | Fixture cause three | O3 | **REFUTED** | fixture refutation note | n/a | fixture evidence line three | n/a | T-X03 (verification only, no removal task needed) |
| RC-04 | Fixture cause four | O4 | **UNDETERMINED** | fixture magnitude unmeasured | UNMEASURED | fixture evidence line four | settling evidence needed (T-X04) | T-X04 |

### 2.2 Register counts (machine count over the Class column of §2.1)

| Class | Rows | Row ids |
|---|---|---|
| CONFIRMED | 3 | RC-01, RC-02 |
| REFUTED | 1 | RC-03 |
| UNDETERMINED | 1 | RC-04 |
| **Total** | **4** | |
