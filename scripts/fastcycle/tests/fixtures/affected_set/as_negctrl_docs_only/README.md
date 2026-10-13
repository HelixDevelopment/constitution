# as_negctrl_docs_only (negative-control, AS-012)

Both changed paths map ONLY to doc gates (`gate_docsync`, `gate_integrity`).
Per AS-012, `change_class=docs-only` must be DERIVED from this fact (never
asserted/hardcoded), and the 3 executable-layer gates (alpha/beta/gamma)
appear in `skipped` with `reason_code=LAYER_NOT_APPLICABLE` -- a DIFFERENT
reason code from `NO_OBSERVED_INPUT_CHANGED` (as_good_single_component uses
that one), proving the tool distinguishes "not applicable to this layer"
from "applicable but untouched". Negative control per the contract's own
table: proves the selector is not vacuously "always full suite" by exercising
its narrowest legitimate selection.
