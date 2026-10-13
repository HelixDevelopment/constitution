#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (I-R2-1, IMPORTANT, 2026-09-30).
# =============================================================================
#
# Proves catchset_compare.py's `combined_content_hash()` genuinely covers a
# gate script's `.`/`source`d sibling engine file, not only the gate
# script's own bytes -- the Round 2 reproduction: gutting a sourced
# lib/*.sh engine, leaving the gate script itself byte-identical, gave
# old_sha256==new_sha256 and rc=0/superset=true/changed=[] pre-fix.
#
# Unit-level (imports catchset_compare.py directly) rather than a full
# `compare` subcommand invocation -- deterministic, fast, and focused
# exactly on the fixed mechanism; the existing test_catchset_compare_red.sh
# (71/71, re-run unmodified above) already proves the surrounding
# `compare` pipeline end-to-end.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/catchset_compare.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 I-R2-1 regression: catchset_compare.py content-hash covers sourced engine files =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

mkdir -p "$SCRATCH/lib"
cat > "$SCRATCH/lib/engine.sh" <<'EOF'
#!/bin/sh
run_check() { return 0; }
EOF

cat > "$SCRATCH/gate_sourcing.sh" <<EOF
#!/bin/sh
HERE=\$(cd "\$(dirname "\$0")" && pwd)
. "\$HERE/lib/engine.sh"
run_check
exit \$?
EOF
chmod +x "$SCRATCH/gate_sourcing.sh" "$SCRATCH/lib/engine.sh"

OUT=$(python3 - "$TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("catchset_compare", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

gate = os.path.join(scratch, "gate_sourcing.sh")
lib = os.path.join(scratch, "lib", "engine.sh")

sourced = mod.resolve_sourced_files(gate)
print("SOURCED=%r" % (sourced,))
if os.path.realpath(lib) not in [os.path.realpath(p) for p in sourced]:
    print("FAIL: resolve_sourced_files did not find the sourced lib/engine.sh")
    sys.exit(1)

plain_hash_before = mod.sha256_file(gate)
combined_before = mod.combined_content_hash(gate)

# Gut the SOURCED engine file -- the gate script itself stays BYTE-IDENTICAL.
with open(lib, "w") as fh:
    fh.write("#!/bin/sh\nrun_check() { return 1; }  # GUTTED\n")

plain_hash_after = mod.sha256_file(gate)
combined_after = mod.combined_content_hash(gate)

print("plain_hash_before=%s plain_hash_after=%s (expect EQUAL -- gate script bytes unchanged)" % (plain_hash_before, plain_hash_after))
print("combined_before=%s combined_after=%s (expect DIFFERENT -- I-R2-1 fix)" % (combined_before, combined_after))

if plain_hash_before != plain_hash_after:
    print("FAIL: the gate script's own bytes changed -- test setup is broken")
    sys.exit(1)
if combined_before == combined_after:
    print("FAIL: combined_content_hash did NOT change when the sourced engine file was gutted -- I-R2-1 NOT fixed")
    sys.exit(1)
print("OK: plain sha256_file is blind to the gutted engine file (reproduces the pre-fix gap), combined_content_hash correctly detects it")
PYEOF
)
RC=$?
echo "$OUT"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^OK: plain sha256_file is blind"; then
    ok "R1: combined_content_hash() detects a gutted SOURCED engine file even though the gate script's own bytes are unchanged"
else
    bad "R1: sourced-engine-file hash coverage check failed (rc=$RC)"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
