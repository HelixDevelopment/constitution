#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (B-R2-5 + B-R2-5(a) + the
# gate-timeout Minor, 2026-09-30).
# =============================================================================
#
# Proves, against scratch corpora this file constructs itself (never the
# real batch_bisect fixture tree's on-disk config), the three fixes to
# constitution/scripts/fastcycle/gates/batch_bisect.py:
#
#   B-R2-5   `wip-caps --apply`'s ".bak" hardlink backup is no longer
#            silently overwritten by the new content (the pre-fix
#            `os.link()` + `open(path, "w")` pair shared ONE inode).
#   B-R2-5(a) `target_file` in a batch.json change can no longer escape
#            the disposable tree via an absolute path or a `..`-escaping
#            relative one.
#   MINOR    a hung `--gate` invocation no longer blocks `run` forever.
#
# §11.4.199: every scenario below is a REAL invocation of the real tool,
# never a synthetic stand-in.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/batch_bisect.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 B-R2-5/B-R2-5(a) regression: batch_bisect.py backup + path-containment + gate-timeout =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

# =============================================================================
# Section D -- B-R2-5: hardlink-backup content preservation.
# =============================================================================
echo "-- Section D: wip-caps --apply backup is a genuine, distinct copy --"

THRESH="$SCRATCH/thresholds.yaml"
cat > "$THRESH" <<'EOF'
# scratch thresholds fixture (T085 Round 2 regression)
wip_caps:
  per_track: UNMEASURED             # T-A09
  review_queue: UNMEASURED          # T-A09
  device_flash_queue: UNMEASURED    # T-A09
EOF
ORIGINAL_CONTENT=$(cat "$THRESH")

METRICS="$SCRATCH/metrics.json"
cat > "$METRICS" <<'EOF'
{"queues": {"per_track": {"median_wip": 4}, "review_queue": {"median_wip": 2}, "device_flash_queue": {"median_wip": 1}}}
EOF

D1_OUT=$(python3 "$TOOL" wip-caps --thresholds "$THRESH" --metrics "$METRICS" --apply 2>"$SCRATCH/d1.stderr")
D1_RC=$?
# T085 Round 3 R3-B3 (via the shared fc_common.atomic_backup_and_replace()
# helper, m2 fix): backup_path is no longer a FIXED filename
# ("$THRESH.pre-wip-caps.bak") -- it is unique per call (timestamp+pid+
# counter), specifically so a SECOND --apply run never collides with /
# silently skips a prior run's backup (see Section D2 below). Read the
# REAL backup_path back from the tool's own JSON report, never assume a
# literal filename.
BACKUP_PATH=$(printf '%s\n' "$D1_OUT" | python3 -c '
import json, sys
text = sys.stdin.read()
try:
    start = text.index("{")
    doc = json.loads(text[start:])
    print(doc.get("backup_path", ""))
except (ValueError, json.JSONDecodeError):
    pass
')

if [ "$D1_RC" -eq 0 ] && [ -n "$BACKUP_PATH" ] && [ -f "$BACKUP_PATH" ]; then
    ok "D1: wip-caps --apply exited 0 and wrote a backup file"
else
    bad "D1: wip-caps --apply exited $D1_RC or backup missing: $D1_OUT"
fi

BACKUP_CONTENT=$(cat "$BACKUP_PATH" 2>/dev/null)
if [ "$BACKUP_CONTENT" = "$ORIGINAL_CONTENT" ]; then
    ok "D2: backup file content == the ORIGINAL pre-write bytes (not silently overwritten)"
else
    bad "D2: backup file content does NOT match the original pre-write bytes -- the backup was overwritten (the B-R2-5 bug)"
    echo "   --- original ---"; echo "$ORIGINAL_CONTENT"
    echo "   --- backup now ---"; echo "$BACKUP_CONTENT"
fi

BACKUP_INODE=$(stat -c '%i' "$BACKUP_PATH" 2>/dev/null || stat -f '%i' "$BACKUP_PATH")
NEW_INODE=$(stat -c '%i' "$THRESH" 2>/dev/null || stat -f '%i' "$THRESH")
if [ "$BACKUP_INODE" != "$NEW_INODE" ]; then
    ok "D3: backup inode ($BACKUP_INODE) != rewritten thresholds.yaml's new inode ($NEW_INODE) -- genuinely separate content, not the same inode"
else
    bad "D3: backup and the rewritten file share the SAME inode ($BACKUP_INODE) -- they are the same file on disk"
fi

NEW_CONTENT=$(cat "$THRESH")
if echo "$NEW_CONTENT" | grep -q "per_track: 4" && echo "$NEW_CONTENT" | grep -q "review_queue: 2" && echo "$NEW_CONTENT" | grep -q "device_flash_queue: 1"; then
    ok "D4: thresholds.yaml genuinely updated with the new per-queue WIP caps from --metrics"
else
    bad "D4: thresholds.yaml was not correctly updated with the new caps: $NEW_CONTENT"
fi

# T085 Round 3 m2 (MINOR, shared with R3-B3's fix): a SECOND --apply run
# must get its OWN genuine backup of the state immediately before THAT
# run -- never silently reuse/skip because a fixed backup filename from
# the first run already exists (the pre-fix `FileExistsError: pass`
# bug). Update the metrics so the second apply writes genuinely
# different content, then apply a second time.
AFTER_FIRST_APPLY_CONTENT=$(cat "$THRESH")
cat > "$METRICS" <<'EOF'
{"queues": {"per_track": {"median_wip": 9}, "review_queue": {"median_wip": 8}, "device_flash_queue": {"median_wip": 7}}}
EOF
D5_OUT=$(python3 "$TOOL" wip-caps --thresholds "$THRESH" --metrics "$METRICS" --apply 2>"$SCRATCH/d5.stderr")
D5_RC=$?
BACKUP_PATH_2=$(printf '%s\n' "$D5_OUT" | python3 -c '
import json, sys
text = sys.stdin.read()
try:
    start = text.index("{")
    doc = json.loads(text[start:])
    print(doc.get("backup_path", ""))
except (ValueError, json.JSONDecodeError):
    pass
')

if [ "$D5_RC" -eq 0 ] && [ -n "$BACKUP_PATH_2" ] && [ -f "$BACKUP_PATH_2" ] && [ "$BACKUP_PATH_2" != "$BACKUP_PATH" ]; then
    ok "D5: a SECOND wip-caps --apply produces a genuinely DISTINCT backup_path ($BACKUP_PATH_2 != $BACKUP_PATH) -- never collides with / silently skips the first run's backup"
else
    bad "D5: second --apply's backup_path ($BACKUP_PATH_2) is missing, unwritten, or identical to the first run's ($BACKUP_PATH) -- the m2 bug"
fi

BACKUP_2_CONTENT=$(cat "$BACKUP_PATH_2" 2>/dev/null)
if [ "$BACKUP_2_CONTENT" = "$AFTER_FIRST_APPLY_CONTENT" ]; then
    ok "D6: the SECOND backup's bytes equal the state immediately BEFORE the second apply (the first apply's own result) -- genuinely captured, not a stale/empty/overwritten copy"
else
    bad "D6: the second backup's content does not match the pre-second-apply state -- the m2 bug (second run's pre-op bytes never genuinely backed up)"
fi

# T085 Round 3 m3 (MINOR): --apply must preserve thresholds.yaml's
# ORIGINAL mode bits across the rewrite -- tempfile.mkstemp() defaults
# to 0600, so a bare os.replace(tmp_path, args.thresholds) would
# silently tighten a pre-existing 0644 file to 0600 on every apply.
chmod 644 "$THRESH"
D7_MODE_BEFORE=$(stat -c '%a' "$THRESH" 2>/dev/null || stat -f '%OLp' "$THRESH")
python3 "$TOOL" wip-caps --thresholds "$THRESH" --metrics "$METRICS" --apply >/dev/null 2>"$SCRATCH/d7.stderr"
D7_MODE_AFTER=$(stat -c '%a' "$THRESH" 2>/dev/null || stat -f '%OLp' "$THRESH")
if [ "$D7_MODE_BEFORE" = "$D7_MODE_AFTER" ]; then
    ok "D7: thresholds.yaml's mode bits ($D7_MODE_BEFORE) are preserved across --apply, never silently tightened to mkstemp's default 0600"
else
    bad "D7: thresholds.yaml's mode changed from $D7_MODE_BEFORE to $D7_MODE_AFTER across --apply -- the m3 bug"
fi

# T085 Round 3 m3 (MINOR, continued): if thresholds.yaml is itself a
# SYMLINK, --apply must write through it (the symlink stays a symlink
# pointing at the now-updated real file), never replace the symlink
# itself with a plain regular file.
REAL_THRESH="$SCRATCH/real_thresholds.yaml"
cp "$THRESH" "$REAL_THRESH"
SYMLINK_THRESH="$SCRATCH/symlink_thresholds.yaml"
ln -s "$REAL_THRESH" "$SYMLINK_THRESH"
python3 "$TOOL" wip-caps --thresholds "$SYMLINK_THRESH" --metrics "$METRICS" --apply >/dev/null 2>"$SCRATCH/d8.stderr"
D8_RC=$?
if [ "$D8_RC" -eq 0 ] && [ -L "$SYMLINK_THRESH" ] && [ "$(readlink "$SYMLINK_THRESH")" = "$REAL_THRESH" ]; then
    ok "D8: --apply against a SYMLINK --thresholds path leaves the symlink intact, still pointing at the real file (never replaced by a regular file)"
else
    bad "D8: --apply against a symlink --thresholds path broke the symlink (rc=$D8_RC, is_symlink=$([ -L "$SYMLINK_THRESH" ] && echo yes || echo no)) -- the m3 symlink bug"
fi
if [ -f "$REAL_THRESH" ] && grep -q "per_track: 9" "$REAL_THRESH" 2>/dev/null; then
    ok "D9: the symlink's REAL target file was genuinely updated with the new caps (write-through-symlink worked, not a no-op)"
else
    bad "D9: the symlink's real target file was not updated with the new caps"
fi

# =============================================================================
# Section E -- B-R2-5(a): target_file path-escape refusal.
# =============================================================================
echo "-- Section E: batch.json target_file cannot escape the disposable tree --"

BASE_TREE="$SCRATCH/base_tree"
PATCHES="$SCRATCH/patches"
mkdir -p "$BASE_TREE" "$PATCHES"
echo "base content" > "$BASE_TREE/widget.txt"

GATE="$SCRATCH/gate.sh"
cat > "$GATE" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$GATE"

echo "patched content" > "$PATCHES/patch1.txt"

VICTIM="$SCRATCH/victim_outside_tree.txt"
echo "PRISTINE -- must never be overwritten" > "$VICTIM"
VICTIM_BEFORE=$(cat "$VICTIM")

# --- E1: absolute target_file ---
BATCH_ABS="$SCRATCH/batch_abs.json"
cat > "$BATCH_ABS" <<EOF
{"batch_id": "b-abs", "changes": [{"change_id": "c1", "target_file": "$VICTIM", "patch": "patch1.txt"}]}
EOF
OUT_ABS="$SCRATCH/out_abs.json"
E1_OUT=$(python3 "$TOOL" run --batch "$BATCH_ABS" --base-tree "$BASE_TREE" --patches "$PATCHES" --gate "$GATE" --out "$OUT_ABS" 2>&1)
E1_RC=$?
VICTIM_AFTER_E1=$(cat "$VICTIM")

if [ "$E1_RC" -eq 2 ]; then
    ok "E1: an ABSOLUTE target_file (\$VICTIM) is refused with exit 2 (usage error)"
else
    bad "E1: an absolute target_file was NOT refused with exit 2 (got rc=$E1_RC): $E1_OUT"
fi
if [ "$VICTIM_AFTER_E1" = "$VICTIM_BEFORE" ]; then
    ok "E2: the victim file OUTSIDE the disposable tree was never touched"
else
    bad "E2: the victim file OUTSIDE the disposable tree WAS overwritten -- content now: $VICTIM_AFTER_E1"
fi
if [ -f "$OUT_ABS" ]; then
    bad "E3: result.json was written despite the usage-error refusal (should not exist): $OUT_ABS"
else
    ok "E3: no result.json written for the refused batch (matches C-001 row 2 semantics)"
fi

# --- E4: '..'-escaping relative target_file ---
BATCH_DOTDOT="$SCRATCH/batch_dotdot.json"
cat > "$BATCH_DOTDOT" <<'EOF'
{"batch_id": "b-dotdot", "changes": [{"change_id": "c1", "target_file": "../../../victim_outside_tree.txt", "patch": "patch1.txt"}]}
EOF
OUT_DOTDOT="$SCRATCH/out_dotdot.json"
E4_OUT=$(python3 "$TOOL" run --batch "$BATCH_DOTDOT" --base-tree "$BASE_TREE" --patches "$PATCHES" --gate "$GATE" --out "$OUT_DOTDOT" 2>&1)
E4_RC=$?
VICTIM_AFTER_E4=$(cat "$VICTIM")

if [ "$E4_RC" -eq 2 ]; then
    ok "E4: a '..'-escaping relative target_file is refused with exit 2 (usage error)"
else
    bad "E4: a '..'-escaping relative target_file was NOT refused with exit 2 (got rc=$E4_RC): $E4_OUT"
fi
if [ "$VICTIM_AFTER_E4" = "$VICTIM_BEFORE" ]; then
    ok "E5: the victim file is still untouched after the '..'-escape attempt"
else
    bad "E5: the victim file WAS overwritten by the '..'-escape attempt -- content now: $VICTIM_AFTER_E4"
fi

# --- E6: a genuinely safe relative target_file still works (no regression) ---
BATCH_SAFE="$SCRATCH/batch_safe.json"
cat > "$BATCH_SAFE" <<'EOF'
{"batch_id": "b-safe", "changes": [{"change_id": "c1", "target_file": "widget.txt", "patch": "patch1.txt"}]}
EOF
OUT_SAFE="$SCRATCH/out_safe.json"
E6_OUT=$(python3 "$TOOL" run --batch "$BATCH_SAFE" --base-tree "$BASE_TREE" --patches "$PATCHES" --gate "$GATE" --out "$OUT_SAFE" 2>&1)
E6_RC=$?
if [ "$E6_RC" -eq 0 ] && [ -f "$OUT_SAFE" ]; then
    ok "E6: a genuinely safe relative target_file ('widget.txt') is NOT refused -- the fix does not over-reject legitimate batches"
else
    bad "E6: a safe relative target_file was wrongly refused (rc=$E6_RC): $E6_OUT"
fi

# =============================================================================
# Section G -- MINOR: a hung --gate no longer blocks run() forever.
# Unit-level, monkeypatched GATE_TIMEOUT_SECONDS so the test itself stays
# fast and deterministic (never a real 120s wait).
# =============================================================================
echo "-- Section G: a hung gate is bounded by a timeout, never hangs run() forever --"

G_OUT=$(python3 - "$TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile
import time

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Monkeypatch the timeout down to something this unit test can afford.
mod.GATE_TIMEOUT_SECONDS = 1

hang_gate = os.path.join(scratch, "hang_forever_gate.sh")
with open(hang_gate, "w") as fh:
    fh.write("#!/bin/sh\nsleep 60\n")
os.chmod(hang_gate, 0o755)

tree = tempfile.mkdtemp(dir=scratch)
t0 = time.time()
verdict, rc = mod.run_gate_on_tree(hang_gate, tree)
elapsed = time.time() - t0

if verdict == "FAIL" and rc == -1 and elapsed < 10:
    print("OK: hung gate bounded -- verdict=%s rc=%s elapsed=%.1fs" % (verdict, rc, elapsed))
else:
    print("FAIL: hung gate NOT bounded -- verdict=%s rc=%s elapsed=%.1fs" % (verdict, rc, elapsed))
    sys.exit(1)
PYEOF
)
G_RC=$?
echo "$G_OUT"
if [ "$G_RC" -eq 0 ] && echo "$G_OUT" | grep -q "^OK: hung gate bounded"; then
    ok "G1: a hung --gate is bounded by GATE_TIMEOUT_SECONDS, verdict=FAIL rc=-1, never hangs forever"
else
    bad "G1: hung-gate timeout check failed: $G_OUT"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
