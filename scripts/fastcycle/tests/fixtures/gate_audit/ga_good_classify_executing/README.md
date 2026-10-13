# ga_good_classify_executing

Golden-good classification case. `_shared/gates/gate_executing.sh` is a real,
content-driven check (exits 1 when `FORBIDDEN_MARKER` is present in its
target, 0 otherwise — verified live during authoring, see
`_shared/gates/` invocations in the RED test itself). `gate_audit.py classify`
MUST report `TOY-GATE-EXECUTING` as `executing` — never `vacuous` (it has a
real fail path) and never `named-only` (it has a real script body).
