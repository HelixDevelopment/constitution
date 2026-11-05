#!/usr/bin/env bash
# shellcheck disable=SC2034
# test_ownership_e01_mutations.sh — paired §1.1 mutations for tests/extensions/test_ownership_e01.sh.
# Each mutant is a sandbox copy of the engine with ONE rule removed; the E01 suite runs against it through
# CONSTITUTION_EXT_ENGINE and MUST fail. The control run (unmutated copy) MUST pass. A mutation whose anchor
# is not found exactly once is BROKEN (reported as failure), never a silent no-op (§11.4.273).
# Usage: bash tests/extensions/test_ownership_e01_mutations.sh   (exit 0 iff control passes and every mutant dies)
T_NAME=ownership-e01-mutations
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
: "${SB:?}"
SUITE="$REPO/tests/extensions/test_ownership_e01.sh"
mk_copy() { mkdir -p "$1/scripts/constitution_ext" "$1/scripts/lib"
  cp "$REPO"/scripts/constitution_ext/*.sh "$REPO"/scripts/constitution_ext/*.py "$1/scripts/constitution_ext/"
  cp "$REPO/scripts/lib/safe_rm.sh" "$REPO/scripts/lib/protected_paths.list" "$1/scripts/lib/"; }
runsuite() { CONSTITUTION_EXT_ENGINE="$1/scripts/constitution_ext/constitution_ext.sh" bash "$SUITE" >"$SB/out.txt" 2>&1; }
mk_copy "$SB/control"
if runsuite "$SB/control"; then ok "control (unmutated copy) passes"; else nok "control fails: $(grep FAIL "$SB/out.txt" | head -3)"; fi
kill_mutant() { # name old new
  local d="$SB/$1"; mk_copy "$d"
  python3 -I - "$d/scripts/constitution_ext/ext_engine.py" "$2" "$3" <<'PY' || { nok "mutant $1: anchor not unique"; return; }
import sys
f, old, new = sys.argv[1:4]
s = open(f, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(f, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if runsuite "$d"; then nok "mutant $1 SURVIVED"; else ok "mutant $1 killed ($(grep -c '  FAIL' "$SB/out.txt") failures)"; fi
}
kill_mutant E1_remove_ignores_fact '        aprobs, tree_ours = self.added_problems(eid, lock[eid])  # RULE:E01-remove-needs-fact
        if aprobs:' '        aprobs, tree_ours = self.added_problems(eid, lock[eid])  # RULE:E01-remove-needs-fact
        if False:'
kill_mutant E2_no_fact_mac 'and hmac.compare_digest(f["mac"], self._amac(key, {k: v for k, v in f.items() if k != "mac"}))  # RULE:E01-fact-mac' 'and True'
kill_mutant E3_no_root_binding 'if f["root"] != os.path.realpath(self.root):  # RULE:E01-root-binding' 'if False:'
kill_mutant E4_no_digest_binding 'if f["sha256"] != entry.get("sha256"):  # RULE:E01-digest-binding' 'if False:'
kill_mutant E5_no_tree_identity 'return ([], idt is not None and [idt[0], idt[1]] == [f["dev"], f["ino"]])  # RULE:E01-tree-identity' 'return ([], True)'
kill_mutant E6_tree_deleted_when_not_ours 'if os.path.lexists(final) and not os.path.islink(final) and tree_ours:' 'if os.path.lexists(final) and not os.path.islink(final):'
kill_mutant E7_enable_mints_fact '        self.commit(lock, [eid], stage="enable:locked")' '        self.commit(lock, [eid], stage="enable:locked")
        if e.get("origin") == "installed" and not os.path.lexists(os.path.join(self._sd(), eid + ADDED_SUFFIX)):
            self.write_added(self.make_added(eid, e["sha256"], _ident_of(tree) or [0, 0, 0]))'
kill_mutant E8_add_never_writes_fact '        self.write_added(jadd["added"])  # the only place besides the journal roll-forward that mints the fact' '        pass'
kill_mutant E9_no_journal_roll_forward '                self._roll_added(j.get("added"), lock, j.get("sha256"))' '                pass'
kill_mutant E10_fact_not_deleted_with_entry '            self.delete_added(i)
' '            pass
'
finish
