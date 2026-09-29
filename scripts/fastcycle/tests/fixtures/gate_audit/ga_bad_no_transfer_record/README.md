# ga_bad_no_transfer_record (golden-bad #2: the task's literal case)

Removing `TOY-GATE-REMOVED` with NO `transfer_run_log` field at all (the
`removal_request.json` here omits it entirely, distinct from
`ga_bad_no_transfer_proof`'s case where a log IS cited but proves the
opposite of the claim). This is the task text's literal scenario: "a
removal without a transferred-mutation record is refused."

`gate_audit.py check-removal` MUST REFUSE this removal, naming the missing
record as the reason (never silently defaulting to ACCEPTED on an absent
field, per §11.4.201(1)).
