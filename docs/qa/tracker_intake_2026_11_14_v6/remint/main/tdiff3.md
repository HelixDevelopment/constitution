## Table counts

| table | B rows | V rows | T rows | L rows | V-B added | V-B removed | V-B changed | L-T added | L-T removed | L-T changed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| doc_segments | 263 | 309 | 263 | 309 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| firebase_metadata | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| item_history | 509 | 637 | 509 | 637 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| items | 263 | 309 | 263 | 309 | 46 | 0 | 3 | 46 | 0 | 3 |
| logic_groups | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| meta | 4 | 4 | 4 | 4 | 0 | 0 | 0 | 0 | 0 | 0 |
| obsolete_details | 1 | 3 | 1 | 3 | 2 | 0 | 0 | 2 | 0 | 0 |
| operator_block_details | 2 | 2 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| repro_gate_exemptions | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| sqlite_sequence | 2 | 2 | 2 | 2 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| test_diary | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

## Items the vehicle changed or added, and where they landed

| vehicle id | landed id | kind | content columns changed in V (against B) | content columns of L that differ from V |
|---|---|---|---|---|
| CON-046 | CON-046 | base item changed | body_md, description, reproduction_state, reproduction_updated_at, reproduction_updated_by | none |
| CON-243 | CON-243 | base item changed | body_md, current_location, description, status | none |
| CON-262 | CON-262 | base item changed | body_md, description | none |
| CON-299 | CON-299 | minted by V | (new) | none |
| CON-300 | CON-300 | minted by V | (new) | none |
| CON-301 | CON-301 | minted by V | (new) | none |
| CON-302 | CON-302 | minted by V | (new) | none |
| CON-303 | CON-303 | minted by V | (new) | none |
| CON-304 | CON-304 | minted by V | (new) | none |
| CON-305 | CON-305 | minted by V | (new) | none |
| CON-306 | CON-306 | minted by V | (new) | none |
| CON-307 | CON-307 | minted by V | (new) | none |
| CON-308 | CON-308 | minted by V | (new) | none |
| CON-309 | CON-309 | minted by V | (new) | none |
| CON-310 | CON-310 | minted by V | (new) | none |
| CON-311 | CON-311 | minted by V | (new) | none |
| CON-312 | CON-312 | minted by V | (new) | none |
| CON-313 | CON-313 | minted by V | (new) | none |
| CON-314 | CON-314 | minted by V | (new) | none |
| CON-315 | CON-315 | minted by V | (new) | none |
| CON-316 | CON-316 | minted by V | (new) | none |
| CON-317 | CON-317 | minted by V | (new) | none |
| CON-318 | CON-318 | minted by V | (new) | none |
| CON-319 | CON-319 | minted by V | (new) | none |
| CON-320 | CON-320 | minted by V | (new) | none |
| CON-321 | CON-321 | minted by V | (new) | none |
| CON-322 | CON-322 | minted by V | (new) | none |
| CON-323 | CON-323 | minted by V | (new) | none |
| CON-324 | CON-324 | minted by V | (new) | none |
| CON-325 | CON-325 | minted by V | (new) | none |
| CON-326 | CON-326 | minted by V | (new) | none |
| CON-327 | CON-327 | minted by V | (new) | none |
| CON-328 | CON-328 | minted by V | (new) | none |
| CON-329 | CON-329 | minted by V | (new) | none |
| CON-330 | CON-330 | minted by V | (new) | none |
| CON-331 | CON-331 | minted by V | (new) | none |
| CON-332 | CON-332 | minted by V | (new) | none |
| CON-333 | CON-333 | minted by V | (new) | none |
| CON-334 | CON-334 | minted by V | (new) | none |
| CON-335 | CON-335 | minted by V | (new) | none |
| CON-336 | CON-336 | minted by V | (new) | none |
| CON-337 | CON-337 | minted by V | (new) | none |
| CON-338 | CON-338 | minted by V | (new) | none |
| CON-339 | CON-339 | minted by V | (new) | none |
| CON-340 | CON-340 | minted by V | (new) | none |
| CON-341 | CON-341 | minted by V | (new) | none |
| CON-342 | CON-342 | minted by V | (new) | none |
| CON-343 | CON-343 | minted by V | (new) | none |
| CON-344 | CON-344 | minted by V | (new) | none |

## Target items the landing changed

| id | content columns changed (L against T) | changed in V too |
|---|---|---|
| CON-046 | body_md, description, reproduction_state, reproduction_updated_at, reproduction_updated_by | yes |
| CON-243 | body_md, current_location, description, status | yes |
| CON-262 | body_md, description | yes |

Target items removed by the landing: none
