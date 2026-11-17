## Table counts

| table | B rows | V rows | T rows | L rows | V-B added | V-B removed | V-B changed | L-T added | L-T removed | L-T changed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| doc_segments | 263 | 309 | 365 | 410 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| firebase_metadata | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| item_history | 509 | 637 | 641 | 711 | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) | (engine-written) |
| items | 263 | 309 | 365 | 410 | 46 | 0 | 3 | 45 | 0 | 4 |
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
| CON-299 | CON-401 | minted by V | (new) | body_md, description |
| CON-300 | CON-402 | minted by V | (new) | body_md, description |
| CON-301 | CON-403 | minted by V | (new) | body_md, description |
| CON-302 | CON-404 | minted by V | (new) | body_md, description |
| CON-303 | CON-405 | minted by V | (new) | body_md, description |
| CON-304 | CON-406 | minted by V | (new) | body_md, description |
| CON-305 | CON-407 | minted by V | (new) | body_md, description |
| CON-306 | CON-408 | minted by V | (new) | body_md, description |
| CON-307 | CON-409 | minted by V | (new) | body_md, description |
| CON-308 | CON-410 | minted by V | (new) | body_md, description |
| CON-309 | CON-411 | minted by V | (new) | body_md, description |
| CON-310 | CON-412 | minted by V | (new) | body_md, description |
| CON-311 | CON-413 | minted by V | (new) | body_md, description |
| CON-312 | CON-414 | minted by V | (new) | body_md, description |
| CON-313 | CON-415 | minted by V | (new) | body_md, description |
| CON-314 | CON-416 | minted by V | (new) | body_md, description |
| CON-315 | CON-417 | minted by V | (new) | body_md, description |
| CON-316 | CON-418 | minted by V | (new) | body_md, description |
| CON-317 | CON-419 | minted by V | (new) | body_md, description |
| CON-318 | CON-420 | minted by V | (new) | body_md, description |
| CON-319 | CON-421 | minted by V | (new) | body_md, description |
| CON-320 | CON-422 | minted by V | (new) | body_md, description |
| CON-321 | CON-423 | minted by V | (new) | body_md, description |
| CON-322 | CON-424 | minted by V | (new) | body_md, description |
| CON-323 | CON-425 | minted by V | (new) | body_md, description |
| CON-324 | CON-426 | minted by V | (new) | body_md, description |
| CON-325 | CON-427 | minted by V | (new) | body_md, description |
| CON-326 | CON-428 | minted by V | (new) | body_md, description |
| CON-327 | CON-429 | minted by V | (new) | body_md, description |
| CON-328 | CON-430 | minted by V | (new) | body_md, description |
| CON-329 | CON-431 | minted by V | (new) | body_md, description |
| CON-330 | CON-432 | minted by V | (new) | body_md, description |
| CON-331 | CON-433 | minted by V | (new) | body_md, description |
| CON-332 | CON-434 | minted by V | (new) | body_md, description |
| CON-333 | CON-435 | minted by V | (new) | body_md, description |
| CON-334 | CON-436 | minted by V | (new) | body_md, description |
| CON-335 | CON-437 | minted by V | (new) | body_md, description |
| CON-336 | CON-438 | minted by V | (new) | body_md, description |
| CON-337 | CON-439 | minted by V | (new) | body_md, description |
| CON-338 | CON-440 | minted by V | (new) | body_md, description |
| CON-339 | CON-313 | minted by V | (new) | body_md, created_by, description, investigation_evidence, investigation_root_cause, investigation_state, investigation_updated_at, investigation_updated_by, reproduction_env, reproduction_evidence, reproduction_green_cmd, reproduction_red_cmd, reproduction_signature, reproduction_updated_at, reproduction_updated_by, severity, status, title |
| CON-340 | CON-441 | minted by V | (new) | body_md, description |
| CON-341 | CON-442 | minted by V | (new) | body_md, description |
| CON-342 | CON-443 | minted by V | (new) | body_md, description |
| CON-343 | CON-444 | minted by V | (new) | body_md, description |
| CON-344 | CON-445 | minted by V | (new) | body_md, description |

## Target items the landing changed

| id | content columns changed (L against T) | changed in V too |
|---|---|---|
| CON-046 | body_md, description, reproduction_state, reproduction_updated_at, reproduction_updated_by | yes |
| CON-243 | body_md, current_location, description, status | yes |
| CON-262 | body_md, description | yes |
| CON-313 | body_md, description | NO |

Target items removed by the landing: none
