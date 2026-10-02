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

D1_OUT=$(python3 "$TOOL" wip-caps --thresholds "$THRESH" --metrics "$METRICS" --apply 2>&1)
D1_RC=$?
BACKUP_PATH="$THRESH.pre-wip-caps.bak"

if [ "$D1_RC" -eq 0 ] && [ -f "$BACKUP_PATH" ]; then
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
