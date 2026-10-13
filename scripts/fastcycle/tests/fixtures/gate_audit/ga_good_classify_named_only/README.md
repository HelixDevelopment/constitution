# ga_good_classify_named_only

`TOY-GATE-DEFERRED` appears in `_shared/ledger/registry.tsv` with script
column `NONE` and has a real entry in `_shared/ledger/deferrals.tsv`
(ATM-9001, per the §11.4.227(A) registered-deferral schema — the exact TSV
shape the real `constitution/scripts/gates/gate_ledger_deferrals.tsv`
uses). `gate_audit.py classify` MUST report it as `named-only` — it is
mentioned/tracked but has no executing body, the third leg of the task's
taxonomy (executing / named-only / vacuous).
