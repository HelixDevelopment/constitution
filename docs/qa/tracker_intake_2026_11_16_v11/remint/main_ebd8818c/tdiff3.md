## Table counts

| table | B rows | V rows | T rows | L rows | V-B added | V-B removed | V-B changed | L-T added | L-T removed | L-T changed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| doc_segments | 263 | 309 | 491 | 536 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| firebase_metadata | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| item_history | 509 | 638 | 828 | 900 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| items | 263 | 309 | 491 | 536 | 46 | 0 | 3 | 45 | 0 | 6 |
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
| CON-262 | CON-262 | base item changed | body_md, description | body_md, description, status |
| CON-299 | CON-527 | minted by V | (new) | body_md, description |
| CON-300 | CON-528 | minted by V | (new) | body_md, description |
| CON-301 | CON-529 | minted by V | (new) | body_md, description |
| CON-302 | CON-530 | minted by V | (new) | body_md, description |
| CON-303 | CON-531 | minted by V | (new) | body_md, description |
| CON-304 | CON-532 | minted by V | (new) | body_md, description |
| CON-305 | CON-533 | minted by V | (new) | body_md, description |
| CON-306 | CON-534 | minted by V | (new) | body_md, description |
| CON-307 | CON-535 | minted by V | (new) | body_md, description |
| CON-308 | CON-536 | minted by V | (new) | body_md, description |
| CON-309 | CON-537 | minted by V | (new) | body_md, description |
| CON-310 | CON-538 | minted by V | (new) | body_md, description |
| CON-311 | CON-539 | minted by V | (new) | body_md, description |
| CON-312 | CON-540 | minted by V | (new) | body_md, description |
| CON-313 | CON-541 | minted by V | (new) | body_md, description |
| CON-314 | CON-542 | minted by V | (new) | body_md, description |
| CON-315 | CON-543 | minted by V | (new) | body_md, description |
| CON-316 | CON-544 | minted by V | (new) | body_md, description |
| CON-317 | CON-545 | minted by V | (new) | body_md, description |
| CON-318 | CON-546 | minted by V | (new) | body_md, description |
| CON-319 | CON-547 | minted by V | (new) | body_md, description |
| CON-320 | CON-548 | minted by V | (new) | body_md, description |
| CON-321 | CON-549 | minted by V | (new) | body_md, description |
| CON-322 | CON-550 | minted by V | (new) | body_md, description |
| CON-323 | CON-551 | minted by V | (new) | body_md, description |
| CON-324 | CON-552 | minted by V | (new) | body_md, description |
| CON-325 | CON-553 | minted by V | (new) | body_md, description |
| CON-326 | CON-554 | minted by V | (new) | body_md, description |
| CON-327 | CON-555 | minted by V | (new) | body_md, description |
| CON-328 | CON-556 | minted by V | (new) | body_md, description |
| CON-329 | CON-557 | minted by V | (new) | body_md, description |
| CON-330 | CON-558 | minted by V | (new) | body_md, description |
| CON-331 | CON-559 | minted by V | (new) | body_md, description |
| CON-332 | CON-560 | minted by V | (new) | body_md, description |
| CON-333 | CON-561 | minted by V | (new) | body_md, description |
| CON-334 | CON-562 | minted by V | (new) | body_md, description |
| CON-335 | CON-563 | minted by V | (new) | body_md, description |
| CON-336 | CON-564 | minted by V | (new) | body_md, description |
| CON-337 | CON-565 | minted by V | (new) | body_md, description |
| CON-338 | CON-566 | minted by V | (new) | body_md, description |
| CON-339 | CON-313 | minted by V | (new) | body_md, created_by, description, investigation_evidence, investigation_root_cause, investigation_state, investigation_updated_at, investigation_updated_by, reproduction_env, reproduction_evidence, reproduction_green_cmd, reproduction_red_cmd, reproduction_signature, reproduction_updated_at, reproduction_updated_by, severity, status, title |
| CON-340 | CON-567 | minted by V | (new) | body_md, description |
| CON-341 | CON-568 | minted by V | (new) | body_md, description |
| CON-342 | CON-569 | minted by V | (new) | body_md, description |
| CON-343 | CON-570 | minted by V | (new) | body_md, description |
| CON-344 | CON-571 | minted by V | (new) | body_md, description |

## Target items the landing changed

| id | content columns changed (L against T) | changed in V too |
|---|---|---|
| CON-046 | body_md, description, reproduction_state, reproduction_updated_at, reproduction_updated_by | yes |
| CON-243 | body_md, current_location, description, status | yes |
| CON-262 | body_md, description | yes |
| CON-313 | body_md, description | NO |
| CON-387 | body_md, description | NO |
| CON-388 | body_md, description | NO |

Target items removed by the landing: none
