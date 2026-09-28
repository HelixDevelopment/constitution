# Fixture: plan_struct_causes / golden-good

Minimal, well-formed register mirroring the real
`specs/004-fast-dev-cycles/research.md` §2.1/§2.2 structure exactly (same
heading text, same 9-column table shape) with FOUR rows, one of each real
class (CONFIRMED x2, REFUTED, UNDETERMINED), every row's Class cell populated
and every row's last ("Removed / measured by") cell populated, and a §2.2
table whose stated per-class counts agree exactly with §2.1's real tally.
Expected `causes` verdict (SC-C-001): exit 0 -- no structural problem.

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
| CONFIRMED | 2 | RC-01, RC-02 |
| REFUTED | 1 | RC-03 |
| UNDETERMINED | 1 | RC-04 |
| **Total** | **4** | |
