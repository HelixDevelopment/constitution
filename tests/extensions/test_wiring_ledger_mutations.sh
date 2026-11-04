#!/usr/bin/env bash
# shellcheck disable=SC2034
# test_wiring_ledger_mutations.sh — paired §1.1 mutations for tests/extensions/test_wiring_ledger.sh.
# Each mutant is a copy of scripts/constitution_ext/wiring_ledger.py with ONE rule removed; the real suite is
# run against it through WIRING_LEDGER_IMPL and MUST fail. The control run (unmutated copy) MUST pass, so a
# mutant that "survives" cannot be a harness problem. Everything lives in a mktemp sandbox.
# Usage: bash tests/extensions/test_wiring_ledger_mutations.sh   (exit 0 iff control passes and all mutants die)
T_NAME=wiring-ledger-mutations
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
: "${SB:?}"
SRC="$REPO/scripts/constitution_ext/wiring_ledger.py"
SUITE="$REPO/tests/extensions/test_wiring_ledger.sh"
mutate() { # name old new  -> $SB/<name>.py (fails the harness if the anchor is not unique)
  python3 -I - "$SRC" "$SB/$1.py" "$2" "$3" <<'PY' || { nok "mutant $1: anchor not unique"; return 1; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
runsuite() { WIRING_LEDGER_IMPL="$1" bash "$SUITE" >"$SB/out.txt" 2>&1; }
cp "$SRC" "$SB/control.py"
if runsuite "$SB/control.py"; then ok "control (unmutated copy) passes"; else nok "control fails: $(tail -3 "$SB/out.txt")"; fi
kill_mutant() { # name old new
  mutate "$1" "$2" "$3" || return
  if runsuite "$SB/$1.py"; then nok "mutant $1 SURVIVED"; else ok "mutant $1 killed ($(grep -c '  FAIL' "$SB/out.txt") failures)"; fi
}
kill_mutant M1_no_local_mac        'if not hmac.compare_digest(doc["mac"], self._mac(key, rows)):  # RULE:W-local-mac' 'if False:'
kill_mutant M2_no_root_binding     ' or row["constitution_root"] != self.root:  # RULE:W-root-binding' ':'
kill_mutant M3_no_fingerprint      'if fingerprint(full, row["kind"], row.get("json_path")) != row["fingerprint"]:  # RULE:W-fingerprint' 'if False:'
kill_mutant M4_refs_no_lock        'fcntl.flock(fd, fcntl.LOCK_EX)  # RULE:W-refs-lock' 'pass'
kill_mutant M5_no_backup_blob_check 'if hashlib.sha256(read_nofollow(blob, MAX_FILE, "backup blob")).hexdigest() != e["sha256"]:  # RULE:W-backup-blob' 'if False:'
kill_mutant M6_no_backup_mac       'or not hmac.compare_digest(m["mac"], self._bmac(key, m)):  # RULE:W-backup-mac' 'or False:'
kill_mutant M7_no_parent_containment 'if parent_real != project_real and not parent_real.startswith(project_real + os.sep):' 'if False:'
kill_mutant M8_adopt_default_all   'led.adopt(o.get("adopt", "none"), o["only"])' 'led.adopt(o.get("adopt", "all-matching"), o["only"])'
kill_mutant M9_rollback_unlink_any 'and fingerprint(full, r["kind"]) == r["fingerprint"]:       # still matches its row' ':'
kill_mutant M10_launder_signatures 'and self.local_rows().get(r["id"]) == self.row_digest(r)}' '}'
kill_mutant M11_inventory_all_links 'def _points_into_constitution(self, link):' 'def _points_into_constitution(self, link):
        return True'
kill_mutant M12_hostile_row_path_ok 'if r["path"].startswith("/") or any(p in ("", ".", "..") for p in parts) or "\0" in r["path"]:' 'if False:'
kill_mutant M13_rebind_no_old_fp   'if row["fingerprint"] != old_fp:' 'if False:'
kill_mutant M14_refs_no_unlink_at_zero 'if os.path.lexists(p):
                os.unlink(p)
            return' 'return'
finish
