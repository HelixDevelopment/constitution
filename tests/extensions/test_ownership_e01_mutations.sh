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
# wave 2 review round 2 (operator decision Q1, review F6/F7)
kill_mutant E11_adopt_without_attestation 'if not att:  # RULE:Q1-adopt-needs-attest' 'if False:'
kill_mutant E12_adopt_without_record 'if rp:  # RULE:Q1-adopt-needs-record' 'if False:'
kill_mutant E13_adopt_without_digest 'if digest != entry.get("sha256"):  # RULE:Q1-adopt-digest' 'if False:'
kill_mutant E14_adopt_replaces_fact 'if os.path.lexists(fp):  # RULE:Q1-adopt-never-replaces' 'if False:'
kill_mutant E15_adopt_without_confirmation 'if os.environ.get("CONSTITUTION_EXT_NO_TTY") == "1":  # RULE:Q1-adopt-confirm' 'if True:
            return
        if False:'
kill_mutant E16_adopt_through_symlink 'if not os.path.lexists(final) or os.path.islink(final) or not os.path.isdir(final):  # RULE:Q1-adopt-real-tree' 'if not os.path.lexists(final):'
kill_mutant E17_adopt_not_in_lock 'if entry is None or entry.get("origin") != "installed":  # RULE:Q1-adopt-lock-entry' 'if entry is None:'
kill_mutant E18_no_per_id_upfront_check 'files += [os.path.join(sd, n) for n in sorted(os.listdir(sd)) if n.endswith(".json")]  # RULE:R18-per-id' 'pass'
kill_mutant E19_commit_recovery_keeps_fact '                    self.delete_added(i)  # RULE:F7-recover-commit-fact' '                    pass'
kill_mutant E20_remove_recovery_keeps_fact '                self.delete_added(eid)  # RULE:F7-recover-remove-fact' '                pass'
kill_mutant E21_adopt_message_drops_next_step 'operator can attest that and make it removable by running, at a terminal, adopt-install %s --waiver-id "' 'operator can attest that and make it removable %s "'
# review round 2 A1 and R2 (tty-only adoption, operator decision 2026-11-05 by the 11.4.101 safe default)
kill_mutant E22_adopt_accepts_yes '"adopt-install": (1, 1, {"waiver_id"}),  # RULE:A1-adopt-no-yes' '"adopt-install": (1, 1, {"yes", "waiver_id"}),'
kill_mutant E23_no_tty_message_names_bypass '"adopt-install %s needs an operator at a terminal (%s): an operator runs it interactively and "' '"adopt-install %s: confirmation required (%s): pass --yes or run interactively and "'
kill_mutant RMc_any_tty_answer_confirms 'if ans != eid:' 'if False:'
kill_mutant E24_tty_open_failure_confirms 'raise EngineError(EXIT_REFUSED, ADOPT_NEEDS_TTY % (eid, "this process has no controlling terminal"))' 'return'
# review round 3 N3: reviewer-authored mutants of the prompt comparison and the NO_TTY knob
kill_mutant RN1_substring_match 'if ans != eid:' 'if eid not in ans:'
kill_mutant RN2_case_insensitive 'if ans != eid:' 'if ans.lower() != eid.lower():'
kill_mutant RN3_no_tty_knob_ignored 'if os.environ.get("CONSTITUTION_EXT_NO_TTY") == "1":  # RULE:Q1-adopt-confirm' 'if False:  # RULE:Q1-adopt-confirm'
# Reviewer mutants R1 and R2 (review of wave 2, section "Reviewer mutants on E01") are EQUIVALENT in effect and are
# deliberately not listed. R1 drops the f["id"] != eid check: a fact copied under another id still fails, because the
# digest binding compares against the lock entry of THAT id and tree_digest hashes extension.yml, which holds the id.
# R2 drops the root check in the journal roll-forward: a fact for another root that is rolled forward is still
# refused at remove by the root binding (E3 kills that rule). Both checks stay as defense in depth.
finish
