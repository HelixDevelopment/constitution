#!/usr/bin/env bash
# cm_multitrack_engine_in_constitution_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-MULTITRACK-ENGINE-IN-CONSTITUTION (§11.4.187).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-MULTITRACK-ENGINE-IN-CONSTITUTION is NOT a bluff gate across all
# three of its invariants (presence / decoupling / parseability), AND proves
# its narrow self-referential-comment exemption (documented in the gate's own
# header) does NOT mask a real violation:
#
#   1a. CLEAN fixture (generic scripts, incl. a comment that self-documents
#       "no atmosphere literal here" — exercising the exemption) → PASS.
#   1b. Too-few-scripts fixture (below --min-scripts) → PRESENCE FAILs.
#   2a. Real-literal-in-code fixture (a NON-comment line embeds a
#       track-mount+basename coupling literal in actual code) → DECOUPLING FAILs.
#   2b. Comment-only "atmosphere" mention (mirroring the real
#       multitrack_bootstrap.sh:107 case) → still PASSes (proves the
#       exemption fires correctly and is not itself a bluff-through).
#   3.  Parse-broken fixture (unbalanced quote) → PARSEABILITY FAILs.
#   4a. A python-declaring script whose content is valid python but INVALID
#       shell (the exact shape of the real agent_label_frontmatter_check.py:
#       `MODELS = ("sonnet", "opus")`) → PASSes (RED before the gate learned
#       python: `sh -n` was demanded of a declared-python script).
#   4b. A python-declaring script with a python syntax error → FAILs (the
#       python parse is a real parse, not a skip).
#   4c. Negative control: a bash-declaring script carrying that same
#       python-only content → still FAILs (the python rule did not relax the
#       bash/sh rule), and a `#!/bin/sh` one likewise.
#   4d. `#!/usr/bin/env -S python3 -I` (env options) is read as python; a
#       python-declaring script on a host with NO python3 FAILs (fail closed,
#       never a silent skip).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_multitrack_engine_in_constitution_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real engine tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, the sibling cm_multitrack_engine_in_constitution.sh gate script.
#   Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.187, §11.4.28(B)/§11.4.177 (decoupling),
#   §11.4.67 (target-shell-parseability).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected PASS/FAIL verdict.
#   1 — at least one sub-case produced the wrong verdict (bluff or false alarm).
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_multitrack_engine_in_constitution.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_mtec_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
expect_fail() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        note "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "✅ META OK:   ${desc} — gate correctly PASSed"
    else
        note "❌ META FAIL: ${desc} — gate FAILed unexpectedly (false alarm!)"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-MULTITRACK-ENGINE-IN-CONSTITUTION"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- 1a/2b. CLEAN fixture: generic scripts + a self-referential exemption
#            comment (mirrors the real multitrack_bootstrap.sh:107 case) ---
CLEAN="$TMP/engine_clean"
mkdir -p "$CLEAN"
cat > "$CLEAN/multitrack_config.sh" <<'SH'
#!/usr/bin/env bash
# Generic config loader — project-agnostic (no project literal here;
# consuming projects supply config/multitrack/<hostname>.yaml as DATA).
set -euo pipefail
echo "load config"
SH
cat > "$CLEAN/multitrack_resolve_worktree.sh" <<'SH'
#!/usr/bin/env bash
# §11.4.28(B) / §11.4.177 (project-agnostic — no `atmosphere` literal here;
# this comment exists purely to exercise the gate's exemption clause).
set -euo pipefail
echo "resolve"
SH
cat > "$CLEAN/multitrack-up" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "up"
SH
chmod +x "$CLEAN"/multitrack_config.sh "$CLEAN"/multitrack_resolve_worktree.sh "$CLEAN"/multitrack-up
expect_pass "clean fixture (3 scripts, exemption comment present)" \
    bash "$GATE" --engine-dir "$CLEAN" --quiet

# --- 1b. Too-few-scripts fixture ---
FEW="$TMP/engine_few"
mkdir -p "$FEW"
cat > "$FEW/multitrack_config.sh" <<'SH'
#!/usr/bin/env bash
echo "only one script here"
SH
chmod +x "$FEW/multitrack_config.sh"
expect_fail "too-few-scripts fixture (1 < min-scripts 3)" \
    bash "$GATE" --engine-dir "$FEW" --min-scripts 3 --quiet

# --- 2a. Real-literal-in-code fixture: a NON-comment line embeds the
#         project-coupled mount+basename combination ---
MUT_LIT="$TMP/engine_literal_mut"
mkdir -p "$MUT_LIT"
cp -r "$CLEAN"/. "$MUT_LIT"/
# Build the 2a payload from split tokens so THIS test script does not itself
# statically embed the coupling literal (the §11.4.28(B) audit would flag it) —
# the assembled literal lands in the FIXTURE, which the gate under test must
# still catch on a non-comment code line.
_mut_lit="/mnt/track1/atmo""sphere-t1"
{
    printf '%s\n' '# MUTATION: a real (non-comment) project path'
    printf 'ROOT_OVERRIDE="%s"\n' "$_mut_lit"
    printf '%s\n' 'echo "$ROOT_OVERRIDE"'
} >> "$MUT_LIT/multitrack_config.sh"
expect_fail "real-literal-in-code fixture (/mnt/track1/atmosphere-t1 hardcoded)" \
    bash "$GATE" --engine-dir "$MUT_LIT" --quiet

# --- 3. Parse-broken fixture (unbalanced quote) ---
MUT_PARSE="$TMP/engine_parse_mut"
mkdir -p "$MUT_PARSE"
cp -r "$CLEAN"/. "$MUT_PARSE"/
cat >> "$MUT_PARSE/multitrack-up" <<'SH'
echo "unbalanced quote
SH
expect_fail "parse-broken fixture (unbalanced quote)" \
    bash "$GATE" --engine-dir "$MUT_PARSE" --quiet

# --- 4a. python-declaring script: valid python, INVALID shell ---
PY_OK="$TMP/engine_py_ok"
mkdir -p "$PY_OK"
cp -r "$CLEAN"/. "$PY_OK"/
cat > "$PY_OK/agent_label_check.py" <<'PYSRC'
#!/usr/bin/env python3
"""generic python helper shipped in the engine directory."""
MODELS = ("sonnet", "opus")
print(MODELS)
PYSRC
chmod +x "$PY_OK/agent_label_check.py"
# the control needle for 4a: the SAME content under `sh -n` really fails, so the PASS below is the interpreter choice, not a blind check
if sh -n "$PY_OK/agent_label_check.py" >/dev/null 2>&1; then
    note "❌ META FAIL: 4a control needle — sh -n accepted the python content (the fixture cannot discriminate)"
    rc=1
else
    note "✅ META OK:   4a control needle — sh -n rejects the python-only content (the fixture discriminates)"
fi
expect_pass "python-declaring script (valid python, invalid shell) is parsed as python" \
    bash "$GATE" --engine-dir "$PY_OK" --quiet

# --- 4b. python-declaring script with a python syntax error ---
PY_BAD="$TMP/engine_py_bad"
mkdir -p "$PY_BAD"
cp -r "$PY_OK"/. "$PY_BAD"/
printf '%s\n' 'def broken(:' >> "$PY_BAD/agent_label_check.py"
expect_fail "python-declaring script with a python syntax error" \
    bash "$GATE" --engine-dir "$PY_BAD" --quiet

# a file that FAILED to parse never gets a "clean" line (non-quiet run; control needle: the python-ok fixture prints one)
pybad_out="$(bash "$GATE" --engine-dir "$PY_BAD" 2>&1 || true)"
pyok_out="$(bash "$GATE" --engine-dir "$PY_OK" 2>&1 || true)"
if grep -qF '✅ PARSEABILITY: agent_label_check.py clean' <<<"$pyok_out" \
   && ! grep -qF '✅ PARSEABILITY: agent_label_check.py clean' <<<"$pybad_out"; then
    note "✅ META OK:   a file that failed to parse gets no 'clean' line (and a clean one does)"
else
    note "❌ META FAIL: 'clean' line missing for a clean file, or printed for a file that failed to parse"
    rc=1
fi

# --- 4c. negative controls: the python rule does not relax bash / sh ---
for decl in '#!/usr/bin/env bash' '#!/bin/sh'; do
    NEG="$TMP/engine_neg_$(printf '%s' "$decl" | tr -c 'a-z' '_')"
    mkdir -p "$NEG"
    cp -r "$CLEAN"/. "$NEG"/
    { printf '%s\n' "$decl"; printf '%s\n' 'MODELS = ("sonnet", "opus")'; } > "$NEG/not_really_python.sh"
    chmod +x "$NEG/not_really_python.sh"
    expect_fail "negative control: '${decl}' script carrying python-only content still FAILs" \
        bash "$GATE" --engine-dir "$NEG" --quiet
done

# --- 4d. env options before the interpreter word; fail closed when python3 is absent ---
PY_ENV="$TMP/engine_py_env"
mkdir -p "$PY_ENV"
cp -r "$CLEAN"/. "$PY_ENV"/
{ printf '%s\n' '#!/usr/bin/env -S python3 -I'; printf '%s\n' 'MODELS = ("sonnet", "opus")'; } > "$PY_ENV/env_option_check.py"
chmod +x "$PY_ENV/env_option_check.py"
expect_pass "'#!/usr/bin/env -S python3 -I' is read as python" \
    bash "$GATE" --engine-dir "$PY_ENV" --quiet
NOPY="$TMP/nopy_path"
mkdir -p "$NOPY"
for t in bash sh head find grep sort tr sed cat rm mktemp dirname basename readlink; do
    p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$NOPY/$t"
done
# control needle for the next case: the SAME minimal PATH runs the gate green on the python-free CLEAN fixture, so the
# FAIL below is the missing python3 and nothing else
expect_pass "minimal no-python3 PATH still runs the gate green on a python-free engine (control needle)" \
    env PATH="$NOPY" "$NOPY/bash" "$GATE" --engine-dir "$CLEAN" --quiet
expect_fail "python-declaring script on a host with no python3 fails closed" \
    env PATH="$NOPY" "$NOPY/bash" "$GATE" --engine-dir "$PY_OK" --quiet
# ... and it fails FOR THAT REASON (the verdict line names the missing interpreter), not by chance
# (output captured first and matched with a here-string: `cmd | grep -q` under pipefail is the SIGPIPE class, 11.4.276(C))
nopy_out="$(env PATH="$NOPY" "$NOPY/bash" "$GATE" --engine-dir "$PY_OK" --quiet 2>&1 || true)"
if grep -qF 'cannot verify a python-declaring script' <<<"$nopy_out"; then
    note "✅ META OK:   no-python3 failure names the missing interpreter (cannot verify a python-declaring script)"
else
    note "❌ META FAIL: no-python3 failure does not name the missing interpreter (failed for another reason, or silently)"
    rc=1
fi

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-MULTITRACK-ENGINE-IN-CONSTITUTION is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-MULTITRACK-ENGINE-IN-CONSTITUTION failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
