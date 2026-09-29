# ga_negctrl_clean_state — the false-positive guard

No removal is proposed in this fixture at all — `gate_audit.py audit` run
against the whole `_shared/` toy corpus (registry + deferrals + gates, no
`removal_request.json`) with every gate in its ORIGINAL, un-removed state
MUST report zero REFUSED entries and zero misclassifications. A checker
that refuses even a genuinely clean, no-removal-pending state (§11.4.201(1)
the false-positive guard) is as broken as one that accepts a bad removal.
