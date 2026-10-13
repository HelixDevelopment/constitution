# Fixture: plan_struct_causes / golden-bad-no-class

Identical to the golden-good fixture except RC-02's Class cell is EMPTY
(blank -- no bolded token, no value at all). Per contract
plan-research-structural-check.md SC-C-001: "class ∈ {CONFIRMED, REFUTED,
UNDETERMINED}" -- a row whose Class cell is blank fails this membership
check. Expected `causes` verdict: exit 1, naming RC-02.

## 2. Root-cause register

### 2.1 Register table

| RC | Cause | Origin | Class | Measured magnitude (named denominator) | Share of total cycle | Evidence | Settling evidence / what remains | Removed / measured by |
|---|---|---|---|---|---|---|---|---|
| RC-01 | Fixture cause one | O1 | **CONFIRMED** | 1 of 1 fixture measurement | UNMEASURED | fixture evidence line one | settling note (T-X01) | T-X01 |
| RC-02 | Fixture cause two | O2 |  | 1 of 1 fixture measurement | UNMEASURED | fixture evidence line two | settling note (T-X02) | T-X02 |
| RC-03 | Fixture cause three | O3 | **REFUTED** | fixture refutation note | n/a | fixture evidence line three | n/a | T-X03 (verification only, no removal task needed) |
| RC-04 | Fixture cause four | O4 | **UNDETERMINED** | fixture magnitude unmeasured | UNMEASURED | fixture evidence line four | settling evidence needed (T-X04) | T-X04 |

### 2.2 Register counts (machine count over the Class column of §2.1)

| Class | Rows | Row ids |
|---|---|---|
| CONFIRMED | 2 | RC-01, RC-02 |
| REFUTED | 1 | RC-03 |
| UNDETERMINED | 1 | RC-04 |
| **Total** | **4** | |
