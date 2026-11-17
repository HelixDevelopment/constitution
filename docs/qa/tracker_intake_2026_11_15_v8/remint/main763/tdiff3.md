## Table counts

| table | B rows | V rows | T rows | L rows | V-B added | V-B removed | V-B changed | L-T added | L-T removed | L-T changed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| doc_segments | 263 | 309 | 276 | 322 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| firebase_metadata | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| item_history | 509 | 637 | 538 | 610 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| items | 263 | 309 | 276 | 322 | 46 | 0 | 3 | 46 | 0 | 3 |
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
| CON-046 | CON-046 | base item changed | body_md, description, reproduction_state, reproduction_updated_at, reproduction_updated_by | body_md, description |
| CON-243 | CON-243 | base item changed | body_md, current_location, description, status | body_md, description |
| CON-262 | CON-262 | base item changed | body_md, description | body_md, description |
| CON-299 | CON-312 | minted by V | (new) | body_md, description |
| CON-300 | CON-313 | minted by V | (new) | body_md, description |
| CON-301 | CON-314 | minted by V | (new) | body_md, description |
| CON-302 | CON-315 | minted by V | (new) | body_md, description |
| CON-303 | CON-316 | minted by V | (new) | body_md, description |
| CON-304 | CON-317 | minted by V | (new) | body_md, description |
| CON-305 | CON-318 | minted by V | (new) | body_md, description |
| CON-306 | CON-319 | minted by V | (new) | body_md, description |
| CON-307 | CON-320 | minted by V | (new) | body_md, description |
| CON-308 | CON-321 | minted by V | (new) | body_md, description |
| CON-309 | CON-322 | minted by V | (new) | body_md, description |
| CON-310 | CON-323 | minted by V | (new) | body_md, description |
| CON-311 | CON-324 | minted by V | (new) | body_md, description |
| CON-312 | CON-325 | minted by V | (new) | body_md, description |
| CON-313 | CON-326 | minted by V | (new) | body_md, description |
| CON-314 | CON-327 | minted by V | (new) | body_md, description |
| CON-315 | CON-328 | minted by V | (new) | body_md, description |
| CON-316 | CON-329 | minted by V | (new) | body_md, description |
| CON-317 | CON-330 | minted by V | (new) | body_md, description |
| CON-318 | CON-331 | minted by V | (new) | body_md, description |
| CON-319 | CON-332 | minted by V | (new) | body_md, description |
| CON-320 | CON-333 | minted by V | (new) | body_md, description |
| CON-321 | CON-334 | minted by V | (new) | body_md, description |
| CON-322 | CON-335 | minted by V | (new) | body_md, description |
| CON-323 | CON-336 | minted by V | (new) | body_md, description |
| CON-324 | CON-337 | minted by V | (new) | body_md, description |
| CON-325 | CON-338 | minted by V | (new) | body_md, description |
| CON-326 | CON-339 | minted by V | (new) | body_md, description |
| CON-327 | CON-340 | minted by V | (new) | body_md, description |
| CON-328 | CON-341 | minted by V | (new) | body_md, description |
| CON-329 | CON-342 | minted by V | (new) | body_md, description |
| CON-330 | CON-343 | minted by V | (new) | body_md, description |
| CON-331 | CON-344 | minted by V | (new) | body_md, description |
| CON-332 | CON-345 | minted by V | (new) | body_md, description |
| CON-333 | CON-346 | minted by V | (new) | body_md, description |
| CON-334 | CON-347 | minted by V | (new) | body_md, description |
| CON-335 | CON-348 | minted by V | (new) | body_md, description |
| CON-336 | CON-349 | minted by V | (new) | body_md, description |
| CON-337 | CON-350 | minted by V | (new) | body_md, description |
| CON-338 | CON-351 | minted by V | (new) | body_md, description |
| CON-339 | CON-352 | minted by V | (new) | body_md, description |
| CON-340 | CON-353 | minted by V | (new) | body_md, description |
| CON-341 | CON-354 | minted by V | (new) | body_md, description |
| CON-342 | CON-355 | minted by V | (new) | body_md, description |
| CON-343 | CON-356 | minted by V | (new) | body_md, description |
| CON-344 | CON-357 | minted by V | (new) | body_md, description |

## Target items the landing changed

| id | content columns changed (L against T) | changed in V too |
|---|---|---|
| CON-046 | body_md, description, reproduction_state, reproduction_updated_at, reproduction_updated_by | yes |
| CON-243 | body_md, current_location, description, status | yes |
| CON-262 | body_md, description | yes |

Target items removed by the landing: none
