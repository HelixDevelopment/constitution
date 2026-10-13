# Fixture: cs_real_tree_untouched (safety)

Contract row 9: "real-tree status hash equal before/after".

This is a PROCEDURAL property, not a defect/gate scenario -- there is no
`config_old.json`/`config_new.json` here. It is enforced directly by the
main RED test (`../../test_catchset_compare_red.sh`): a canary path inside
the REAL project tree (`$FC/lib/fc_common.sh`, a file this whole fixture
suite reads but never writes) is sha256-hashed before ANY fixture work
begins and again after every fixture's disposable-copy work (all under
`mktemp -d`, never under `$FC/tests/fixtures/`) completes; the two hashes
MUST be identical.

This directly exercises CS-001 ("the harness verifies the real tree's
status is byte-identical before and after (§11.4.84 quiescence)") for the
RED test's OWN disposable-copy mechanism -- proving the isolation
discipline the future `catchset_compare.py` implementation must also
follow is genuinely followed here, not merely asserted in prose.
