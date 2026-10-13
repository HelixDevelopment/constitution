#!/bin/sh
# =============================================================================
# T085 US2 Round 3 remediation regression (R3-B3, BLOCKING,
# device-independent, host-filesystem-only, 2026-10-02).
# =============================================================================
#
# Proves, against scratch corpora this file constructs itself (never any
# real project file), that backstop_compare.py's `--apply --map` path
# (apply_force_full()) no longer silently destroys its own pre-op backup.
#
# T085 Round 3 R3-B3 (independent review, 2026-10-02): the Round 2
# remediation fixed the IDENTICAL hardlink-then-truncate-in-place bug in
# batch_bisect.py's `wip-caps --apply` (B-R2-5) but never searched the
# rest of the codebase for the SAME pattern -- backstop_compare.py's
# apply_force_full() (edited in that very remediation, in-pack scope)
# had the UN-FIXED sibling: `os.link(map_path, backup_path)` followed by
# `open(map_path, "w")` on the SAME inode, silently overwriting the
# "backup" with the post-write content. Reproduced live before this fix
# (per §11.4.199): the map and its `.bak-*` shared one inode, and the
# "backup" held `force_full:true` -- the pre-op bytes were already gone.
#
# Fix: both call sites (this file's apply_force_full() AND
# batch_bisect.py's cmd_wip_caps(), see
# test_batch_bisect_r2_regression.sh Sections D5-D9) now route through
# ONE shared primitive, fc_common.atomic_backup_and_replace() -- this
# file proves backstop_compare.py's CLI (`--apply --map`, the REAL tool
# invocation, never a synthetic stand-in) genuinely delegates to it and
# that doing so holds under a real mutation-flip.
#
# §11.4.199: every scenario below drives the REAL backstop_compare.py
# CLI as a subprocess, never calls apply_force_full() as a bare Python
# import shortcut for the assertion-bearing sections.
#
# Usage: sh test_backstop_compare_r3_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/lib/backstop_compare.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "ok $1"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $1"; }

if [ ! -f "$TOOL" ]; then
    bad "control needle: $TOOL does not exist -- cannot regression-test it"
    exit 1
fi

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

mk_fixture() {
    # $1 = out-dir -- writes fast_verdicts.json / full_verdicts.json /
    # map.json such that gate "g_drift" DRIFTS (fast=PASS, full=FAIL,
    # per DEC-17: a drift is a full-lane FAIL the fast lane did NOT also
    # report) and is present in map.json's gates dict (so --apply marks
    # it force_full=true).
    out="$1"
    cat > "$out/fast_verdicts.json" <<'EOF'
{"schema": "verdicts/v1", "change_id": "CHG-R3B3", "results": [
  {"gate_id": "g_drift", "verdict": "PASS"},
  {"gate_id": "g_stable", "verdict": "PASS"}
]}
EOF
    cat > "$out/full_verdicts.json" <<'EOF'
{"schema": "verdicts/v1", "change_id": "CHG-R3B3", "results": [
  {"gate_id": "g_drift", "verdict": "FAIL"},
  {"gate_id": "g_stable", "verdict": "PASS"}
]}
EOF
    cat > "$out/map.json" <<'EOF'
{"gates": {"g_drift": {"force_full": false}, "g_stable": {"force_full": false}}}
EOF
}

parse_backup_path() {
    # $1 = captured stdout of a `backstop_compare.py --apply` run.
    # Extracts the backup path from the "APPLY: force_full=true set for
    # ... (backup: <path>)" line -- the real tool's own printed contract,
    # never a guessed filename.
    printf '%s\n' "$1" | sed -n 's/.*(backup: \(.*\))$/\1/p' | head -1
}

# =============================================================================
# Section A -- REAL tool, unmutated: --apply --map genuinely preserves the
# pre-op bytes in a distinct, non-colliding backup.
# =============================================================================
echo "-- Section A: backstop_compare.py --apply --map, real tool, unmutated --"

CORPUS_A="$SCRATCH/a"
mkdir -p "$CORPUS_A"
mk_fixture "$CORPUS_A"
ORIGINAL_MAP_CONTENT=$(cat "$CORPUS_A/map.json")

A1_OUT=$(python3 "$TOOL" --fast "$CORPUS_A/fast_verdicts.json" --full "$CORPUS_A/full_verdicts.json" \
    --out "$CORPUS_A/result.json" --apply --map "$CORPUS_A/map.json" 2>"$CORPUS_A/a1.stderr")
A1_RC=$?

if [ "$A1_RC" -eq 1 ]; then
    ok "A1: the tool exits 1 (EXIT_FINDING, a genuine drift on g_drift) as expected"
else
    bad "A1: expected exit 1 (drift found), got $A1_RC: $A1_OUT"
fi

BACKUP_PATH=$(parse_backup_path "$A1_OUT")
if [ -n "$BACKUP_PATH" ] && [ -f "$BACKUP_PATH" ]; then
    ok "A2: --apply reported and wrote a backup file: $BACKUP_PATH"
else
    bad "A2: --apply did not report/write a backup file. stdout: $A1_OUT"
fi

BACKUP_CONTENT=$(cat "$BACKUP_PATH" 2>/dev/null)
if [ "$BACKUP_CONTENT" = "$ORIGINAL_MAP_CONTENT" ]; then
    ok "A3: backup file content == the ORIGINAL pre-write map.json bytes (not silently overwritten) -- THE R3-B3 FIX"
else
    bad "A3: backup file content does NOT match the original pre-write bytes -- the R3-B3 bug is back"
    echo "   --- original ---"; echo "$ORIGINAL_MAP_CONTENT"
    echo "   --- backup now ---"; echo "$BACKUP_CONTENT"
fi

BACKUP_INODE=$(stat -c '%i' "$BACKUP_PATH" 2>/dev/null || stat -f '%i' "$BACKUP_PATH" 2>/dev/null)
NEW_INODE=$(stat -c '%i' "$CORPUS_A/map.json" 2>/dev/null || stat -f '%i' "$CORPUS_A/map.json" 2>/dev/null)
if [ -n "$BACKUP_INODE" ] && [ "$BACKUP_INODE" != "$NEW_INODE" ]; then
    ok "A4: backup inode ($BACKUP_INODE) != rewritten map.json's new inode ($NEW_INODE) -- genuinely separate content"
else
    bad "A4: backup and the rewritten map.json share the SAME inode ($BACKUP_INODE / $NEW_INODE)"
fi

NEW_MAP=$(cat "$CORPUS_A/map.json")
if printf '%s' "$NEW_MAP" | python3 -c 'import json, sys; d = json.load(sys.stdin); sys.exit(0 if d["gates"]["g_drift"]["force_full"] is True else 1)'; then
    ok "A5: map.json genuinely updated -- g_drift.force_full == true"
else
    bad "A5: map.json was not correctly updated with force_full=true for g_drift: $NEW_MAP"
fi

# --- A6: a SECOND --apply (re-running the same drift) gets its OWN
# distinct backup, never collides with / silently skips the first run's
# backup (the m2-class bug the shared helper also closes).
A6_OUT=$(python3 "$TOOL" --fast "$CORPUS_A/fast_verdicts.json" --full "$CORPUS_A/full_verdicts.json" \
    --out "$CORPUS_A/result2.json" --apply --map "$CORPUS_A/map.json" 2>"$CORPUS_A/a6.stderr")
BACKUP_PATH_2=$(parse_backup_path "$A6_OUT")
if [ -n "$BACKUP_PATH_2" ] && [ "$BACKUP_PATH_2" != "$BACKUP_PATH" ] && [ -f "$BACKUP_PATH_2" ]; then
    ok "A6: a second --apply run produces a genuinely DISTINCT backup_path, never collides with the first"
else
    bad "A6: second --apply's backup_path ('$BACKUP_PATH_2') missing or identical to the first ('$BACKUP_PATH')"
fi
BACKUP_2_CONTENT=$(cat "$BACKUP_PATH_2" 2>/dev/null)
if [ "$BACKUP_2_CONTENT" = "$NEW_MAP" ]; then
    ok "A7: the second backup's bytes equal the state immediately BEFORE the second apply"
else
    bad "A7: the second backup's content does not match the pre-second-apply state"
fi

# =============================================================================
# Section B -- mutation-flip proof: on a SCRATCH COPY of the real source
# (never the tracked file), revert apply_force_full() to the pre-fix
# hardlink-then-truncate-in-place pattern, and confirm THIS test's own
# A3 assertion now FAILS to hold -- proving the regression guard is
# genuinely load-bearing (§11.4.115(F)), not tautological.
# =============================================================================
echo "-- Section B: mutation-flip proof (apply_force_full reverted to the R3-B3 bug) --"

# backstop_compare.py resolves fc_common.py via a relative "../../lib"
# hop from its OWN directory (dirname/../../lib), matching its real
# on-disk position at .../fastcycle/gates/lib/backstop_compare.py --
# the mutated copy is placed in the SAME two-levels-deep layout
# (<root>/gates/lib/backstop_compare.py + <root>/lib/fc_common.py) so
# that hop resolves correctly, never editing the tracked fc_common.py.
MUT_ROOT="$SCRATCH/mutfc"
mkdir -p "$MUT_ROOT/gates/lib" "$MUT_ROOT/lib"
cp "$TOOL" "$MUT_ROOT/gates/lib/backstop_compare.py"
cp "$FC/lib/fc_common.py" "$MUT_ROOT/lib/fc_common.py"
MUT_TOOL="$MUT_ROOT/gates/lib/backstop_compare.py"

python3 - "$MUT_TOOL" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
target = '''    new_text = canonical_json(gate_map) + "\\n"
    backup_path = fc_common.atomic_backup_and_replace(map_path, new_text, backup_tag="bak")

    return updated, unknown, backup_path'''
replacement = '''    backup_path = "%s.bak-%d-%d" % (map_path, int(__import__("time").time()), os.getpid())
    try:
        os.link(map_path, backup_path)
    except OSError:
        import shutil as _sh
        _sh.copy2(map_path, backup_path)
    # T085-R3-B3-MUTATION: reverted to the pre-fix in-place write.
    with open(map_path, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(gate_map))
        fh.write("\\n")

    return updated, unknown, backup_path'''
if text.count(target) != 1:
    sys.stderr.write("expected exactly 1 occurrence of the fixed apply_force_full tail, found %d\n" % text.count(target))
    sys.exit(1)
text = text.replace(target, replacement)
with open(path, "w") as f:
    f.write(text)
PYEOF
MUT_SETUP_RC=$?

if [ "$MUT_SETUP_RC" -ne 0 ]; then
    bad "B0: mutation setup could not uniquely locate the fixed apply_force_full() tail in a fresh copy"
else
    ok "B0: mutation setup uniquely located and reverted apply_force_full() to the pre-fix pattern in a scratch copy"

    CORPUS_B="$SCRATCH/b"
    mkdir -p "$CORPUS_B"
    mk_fixture "$CORPUS_B"
    ORIGINAL_B=$(cat "$CORPUS_B/map.json")

    B1_OUT=$(python3 "$MUT_TOOL" --fast "$CORPUS_B/fast_verdicts.json" --full "$CORPUS_B/full_verdicts.json" \
        --out "$CORPUS_B/result.json" --apply --map "$CORPUS_B/map.json" 2>"$CORPUS_B/b1.stderr")
    B1_BACKUP=$(parse_backup_path "$B1_OUT")

    if [ -n "$B1_BACKUP" ] && [ -f "$B1_BACKUP" ]; then
        B1_BACKUP_CONTENT=$(cat "$B1_BACKUP")
        if [ "$B1_BACKUP_CONTENT" != "$ORIGINAL_B" ]; then
            ok "B1: mutation-flip -- with the pre-fix pattern restored, the backup is genuinely corrupted (overwritten with post-write content), confirming this guard is load-bearing, not tautological"
        else
            bad "B1: mutation-flip FAILED -- the pre-fix pattern was restored but the backup still (somehow) matches the original; the test cannot distinguish fixed from broken"
        fi
    else
        bad "B1: mutated tool did not produce a backup at all (setup or tool-invocation problem, not the targeted bug): $B1_OUT / $(cat "$CORPUS_B/b1.stderr")"
    fi
fi

echo "---"
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
