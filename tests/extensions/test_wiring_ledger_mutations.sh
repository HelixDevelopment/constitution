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
# M9 (unlink on fingerprint match alone) is superseded by M15 (unlink without classify_row == ours)
kill_mutant M10_launder_signatures 'and self.local_rows().get(r["id"]) == self.row_digest(r)}' '}'
kill_mutant M11_inventory_all_links 'def _points_into_constitution(self, link):' 'def _points_into_constitution(self, link):
        return True'
kill_mutant M12_hostile_row_path_ok 'if r["path"].startswith("/") or any(p in ("", ".", "..") for p in parts) or "\0" in r["path"]:' 'if False:'
kill_mutant M13_rebind_no_old_fp   'if row["fingerprint"] != old_fp:' 'if False:'
kill_mutant M14_refs_no_unlink_at_zero 'if os.path.lexists(p):
                os.unlink(p)
            return' 'return'
kill_mutant M15_rollback_unlink_unsigned 'if self.classify_row(r, local) != "ours":' 'if False:'
kill_mutant M16_rollback_no_symlink_leaf_preflight 'if e["type"] == "file" and os.path.lexists(full) and stat.S_ISLNK(os.lstat(full).st_mode):' 'if False:'
kill_mutant M17_rollback_row_error_aborts 'report["left_alone"].append({"path": r["path"], "reason": "cannot be checked: %s" % clean(ex)})' 'raise'
kill_mutant M18_no_backup_gitignore 'atomic_write(bgi, b"*\n")' 'pass'
kill_mutant M19_record_without_path_crashes 'if cmd in ("record", "classify") and not o["path"]:' 'if False:'
kill_mutant M20_no_key_mode_check 'if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077:' 'if not stat.S_ISREG(st.st_mode):'
kill_mutant M21_no_git_reserved 'if parts[0] == ".git" or rel == STATE_REL' 'if rel == STATE_REL'
kill_mutant M22_no_nofollow_read 'os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK' 'os.O_RDONLY | os.O_NONBLOCK'
kill_mutant M23_same_mac_domain 'b"wiring-backup\0"' 'b"wiring-local\0"'
kill_mutant M24_refs_strict_utf8 '.decode("utf-8", "surrogateescape").split' '.decode("utf-8").split'
kill_mutant M25_refs_write_strict_utf8 'sorted(refs.items())).encode("utf-8", "surrogateescape"))' 'sorted(refs.items())).encode())'
kill_mutant M26_ledger_dir_not_checked '                self._need_writable_dir(os.path.dirname(dst), name)  # RULE:W-ledger-dir-writable
                ledger_plan.append((name, dst, data))' '                ledger_plan.append((name, dst, data))'
kill_mutant M27_ledger_unlink_dir_not_checked '                    self._need_writable_dir(os.path.dirname(dst), name)  # RULE:W-ledger-dir-writable
                ledger_plan.append((name, dst, None))' '                    pass
                ledger_plan.append((name, dst, None))'
kill_mutant M28_ledger_leaf_dir_ok 'if os.path.lexists(dst) and stat.S_ISDIR(os.lstat(dst).st_mode):  # RULE:W-ledger-leaf-dir' 'if False:'
kill_mutant M29_json_entry_unlinked 'if r["kind"] not in ("symlink", "file"):' 'if False:'
kill_mutant M30_restore_probe_not_dir 'if not stat.S_ISDIR(os.stat(probe).st_mode) or not os.access(probe, os.W_OK | os.X_OK):
                raise Refused("cannot restore %s' 'if False:
                raise Refused("cannot restore %s'
kill_mutant M31_unlink_dir_not_checked 'if not os.access(os.path.dirname(full), os.W_OK | os.X_OK):
                    report["left_alone"]' 'if False:
                    report["left_alone"]'
kill_mutant M32_in_backup_not_skipped 'if r["path"] in in_backup:
                continue' 'if False:
                continue'
kill_mutant M33_ledger_symlink_ok 'if os.path.lexists(dst) and stat.S_ISLNK(os.lstat(dst).st_mode) and m["ledger"][name] is not None:' 'if False:'
# M34 (ValueError not caught in main) and M35 (preflight creates the ledger dir) are EQUIVALENT and deliberately not listed:
# every ledger row path is validated on load (a NUL path is refused as hostile), so no ValueError can reach main(); and
# the backup manifest is MAC-verified with the key that lives in .constitution/extensions.state, so any rollback that
# reaches the ledger preflight already has both ledger directories on disk. Both guards remain as defense in depth.
finish
