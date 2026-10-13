# ga_good_classify_vacuous — the control needle for the classifier's negative class

`_shared/gates/gate_vacuous.sh` unconditionally `exit 0`s regardless of its
argument — no input, no mutation, can ever make it fail (verified live:
running it with a target file containing every planted-defect marker still
PASSes). `gate_audit.py classify` MUST report `TOY-GATE-VACUOUS` as
`vacuous`. A classifier that reports EVERY gate it can successfully invoke
as `executing` — without ever detecting a genuinely vacuous one — would
silently pass `ga_good_classify_executing` too, so this fixture is load-
bearing: it is the one case that proves the classifier can see the negative
class, not merely assume the positive one (§11.4.201(7)(b) control-needle
discipline applied to the classifier itself).
