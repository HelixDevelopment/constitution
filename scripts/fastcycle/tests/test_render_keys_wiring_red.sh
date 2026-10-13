#!/bin/sh
# =============================================================================
# T081 RED test (SpecKit-004 "fast-dev-cycles", Phase 4 / User Story 2;
# plan.md T-C12 "the wiring half"; tasks.md T081; SC-002, FR-022).
# =============================================================================
#
# Purpose: prove the WIRING of `constitution/scripts/fastcycle/docs/
# render_keys.py` (T080, "the key half" of T062, already landed) into
# `scripts/testing/sync_all_markdown_exports.sh`'s own freshness decision
# (T081, "until T062 is fully GREEN"). test_render_keys_red.sh (T062) tests
# render_keys.py's own compute/check/store subcommands DIRECTLY and is
# explicit in its own module docstring that it does NOT wire the tool into
# sync_all_markdown_exports.sh -- this file is that missing, separate test
# (the exact gap tasks.md's own HONEST DEFER note on T081 names: "no
# dedicated RED test gating the wiring itself").
#
# EVERY scenario below drives the REAL, tracked
# scripts/testing/sync_all_markdown_exports.sh end to end (real pandoc /
# weasyprint invocations, real file mtimes, real sha256 content hashes --
# never mocked, §11.4.27) inside an ISOLATED sandbox directory (mktemp -d)
# that mirrors just enough of the real repo layout (scripts/testing/ +
# constitution/scripts/fastcycle/docs/ + docs/) for the script's own
# REPO_ROOT auto-detection (`cd "$(dirname "${BASH_SOURCE[0]}")/../.."`) to
# resolve correctly -- the real tracked tree is NEVER touched, written to,
# or mtime-bumped by this test (§11.4.84).
#
# (A) control needle -- a `touch`ed-but-byte-identical source (sha256
#     verified unchanged before/after) is SKIPPED on the second run (the
#     html/pdf/docx siblings' own mtimes do NOT advance) even though mtime
#     alone says the .md looks newer than its siblings -- this is T-C12's
#     whole point ("a skipped render is still proven current") and is the
#     DIRECT CONTRAST to the already-landed test_render_keys_red.sh's own
#     `rk_unchanged_today/` fixture, which proves this is wasteful WITHOUT
#     the wiring. Here it must NOT be wasteful WITH the wiring.
# (B) golden -- a REAL content edit (V1 -> V2, sha256 provably different)
#     still forces a genuine re-render of every enabled format (mtime
#     advances, new content present in the regenerated .html) -- the
#     wiring must never let a real change through uncaught (FR-022: lose
#     nothing).
# (C) fail-safe -- with `render_keys.py` temporarily made unreachable,
#     the SAME touched-but-identical scenario from (A) now DOES re-render
#     (mtime advances) -- proving the gate degrades to TODAY's mtime-only
#     behaviour, never to a missed render, the instant any precondition
#     (python3 / render_keys.py / pandoc) is absent (§11.4.6).
# (D) mutation-sensitivity (§1.1 paired-mutation discipline) -- a MUTATED
#     copy of the script, with `render_key_is_fresh()` patched to
#     unconditionally `return 0` (always "fresh", never consulting
#     render_keys.py at all), is run against scenario (B)'s real content
#     change. The mutated copy WRONGLY skips the re-render (mtime does
#     NOT advance despite the real content edit) -- proving scenario (B)'s
#     own assertion is genuinely load-bearing: a broken wiring that always
#     claims "fresh" is caught by this test, not merely tolerated by it.
#
# Usage: sh test_render_keys_wiring_red.sh
# Exit: 0 all sections held; 1 any FAIL.
# =============================================================================
set -u

REPO_ROOT_REAL=$(cd "$(dirname "$0")/../../../.." && pwd)
REAL_EXPORTER="$REPO_ROOT_REAL/scripts/testing/sync_all_markdown_exports.sh"
REAL_RENDER_KEYS="$REPO_ROOT_REAL/constitution/scripts/fastcycle/docs/render_keys.py"

FAIL=0
PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T081 RED test: render_keys.py wiring into sync_all_markdown_exports.sh =="

if [ ! -f "$REAL_EXPORTER" ]; then
    bad "control needle: $REAL_EXPORTER does not exist"
    exit 1
fi
if [ ! -f "$REAL_RENDER_KEYS" ]; then
    bad "control needle: $REAL_RENDER_KEYS does not exist (T080 not landed?)"
    exit 1
fi
command -v pandoc >/dev/null 2>&1 || { echo "SKIP: pandoc not available on this host -- cannot drive the real exporter"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available on this host"; exit 0; }
ok "control needle: real exporter and real render_keys.py both exist and are readable"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/t081_wiring_red.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT INT TERM

build_sandbox() {
    # $1 = sandbox root. Fresh every call -- one per scenario, never shared,
    # so a scenario's own mtimes/content can never leak into another's.
    rm -rf "$1"
    mkdir -p "$1/scripts/testing" "$1/constitution/scripts/fastcycle/docs" "$1/docs"
    cp "$REAL_EXPORTER" "$1/scripts/testing/sync_all_markdown_exports.sh"
    cp "$REAL_RENDER_KEYS" "$1/constitution/scripts/fastcycle/docs/render_keys.py"
    printf '%s\n\n%s\n' '# Test Doc' 'Original content V1.' > "$1/docs/test.md"
}

run_exporter() {
    # $1 = sandbox root
    ( cd "$1" && sh scripts/testing/sync_all_markdown_exports.sh ) >"$1/.run.log" 2>&1
}

html_mtime() { stat -c '%Y' "$1/docs/test.html" 2>/dev/null || echo "MISSING"; }

# ── Section A: control needle -- touched-but-identical must be SKIPPED ──────
build_sandbox "$SANDBOX"
run_exporter "$SANDBOX"
if [ ! -f "$SANDBOX/docs/test.html" ]; then
    bad "Section A: first run did not produce docs/test.html at all -- cannot proceed (log follows)"
    cat "$SANDBOX/.run.log" 2>/dev/null
    exit 1
fi
SHA_BEFORE=$(sha256sum "$SANDBOX/docs/test.md" | cut -d' ' -f1)
sleep 1.1
touch "$SANDBOX/docs/test.md"
SHA_AFTER_TOUCH=$(sha256sum "$SANDBOX/docs/test.md" | cut -d' ' -f1)
if [ "$SHA_BEFORE" != "$SHA_AFTER_TOUCH" ]; then
    bad "Section A: control-needle precondition violated -- touch changed the source's bytes"
else
    HTML_BEFORE=$(html_mtime "$SANDBOX")
    run_exporter "$SANDBOX"
    HTML_AFTER=$(html_mtime "$SANDBOX")
    if [ "$HTML_BEFORE" = "$HTML_AFTER" ]; then
        ok "Section A: touched-but-content-identical source was SKIPPED (html mtime unchanged: $HTML_AFTER)"
    else
        bad "Section A: touched-but-content-identical source was WASTEFULLY re-rendered (html mtime $HTML_BEFORE -> $HTML_AFTER) -- the T-C12 wiring is not working"
    fi
fi

# ── Section B: golden -- a REAL content edit must still re-render ──────────
build_sandbox "$SANDBOX"
run_exporter "$SANDBOX"
sleep 1.1
printf '%s\n\n%s\n' '# Test Doc' 'CHANGED content V2 -- must force a real re-render.' > "$SANDBOX/docs/test.md"
HTML_BEFORE=$(html_mtime "$SANDBOX")
run_exporter "$SANDBOX"
HTML_AFTER=$(html_mtime "$SANDBOX")
if [ "$HTML_BEFORE" != "$HTML_AFTER" ] && grep -q 'CHANGED content V2' "$SANDBOX/docs/test.html" 2>/dev/null; then
    ok "Section B: a real content change still forces a genuine re-render (html mtime $HTML_BEFORE -> $HTML_AFTER, new content present)"
else
    bad "Section B: a real content change was NOT correctly re-rendered -- the wiring would silently lose a real edit (FR-022 violation)"
fi

# ── Section C: fail-safe -- render_keys.py absent degrades to old behaviour ──
build_sandbox "$SANDBOX"
run_exporter "$SANDBOX"
mv "$SANDBOX/constitution/scripts/fastcycle/docs/render_keys.py" "$SANDBOX/constitution/scripts/fastcycle/docs/render_keys.py.hidden"
sleep 1.1
touch "$SANDBOX/docs/test.md"
HTML_BEFORE=$(html_mtime "$SANDBOX")
run_exporter "$SANDBOX"
HTML_AFTER=$(html_mtime "$SANDBOX")
if [ "$HTML_BEFORE" != "$HTML_AFTER" ]; then
    ok "Section C: with render_keys.py unreachable, the gate fails SAFE to today's mtime-only behaviour (re-rendered, never crashed)"
else
    bad "Section C: with render_keys.py unreachable, a touched doc was WRONGLY skipped (fail-safe direction is backwards -- this could hide a real missed render)"
fi
if grep -qi 'traceback\|unbound variable\|command not found' "$SANDBOX/.run.log" 2>/dev/null; then
    bad "Section C: the run log shows a crash/error signature with render_keys.py absent -- the gate is not failing safely"
else
    ok "Section C: no crash/error signature in the run log with render_keys.py absent"
fi

# ── Section D: mutation-sensitivity (§1.1) -- a broken "always fresh" gate
#    must be CAUGHT by Section B's own assertion, proving it is load-bearing.
MUTANT_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/t081_wiring_red_mutant.XXXXXX")
build_sandbox "$MUTANT_SANDBOX"
MUTANT_SCRIPT="$MUTANT_SANDBOX/scripts/testing/sync_all_markdown_exports.sh"
# Patch render_key_is_fresh() to unconditionally report FRESH without ever
# consulting render_keys.py -- the exact defect class this whole test exists
# to catch ("key on mtime only" / "a review without checking the content" --
# tasks.md T063's own paired-mutation vocabulary for this US2 suite).
if ! python3 - "$MUTANT_SCRIPT" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    src = fh.read()
marker = "render_key_is_fresh() {"
idx = src.find(marker)
if idx == -1:
    sys.stderr.write("MUTATION-FAILED: render_key_is_fresh() not found\n")
    sys.exit(1)
insert_at = idx + len(marker)
mutated = src[:insert_at] + "\n    return 0  # MUTATION: always report fresh (T081 paired mutation)\n" + src[insert_at:]
with open(path, "w", encoding="utf-8") as fh:
    fh.write(mutated)
PYEOF
then
    bad "Section D: could not apply the paired mutation (patch point not found -- the function may have been renamed)"
else
    run_exporter "$MUTANT_SANDBOX"
    sleep 1.1
    printf '%s\n\n%s\n' '# Test Doc' 'CHANGED content V2 -- must force a real re-render.' > "$MUTANT_SANDBOX/docs/test.md"
    HTML_BEFORE=$(html_mtime "$MUTANT_SANDBOX")
    run_exporter "$MUTANT_SANDBOX"
    HTML_AFTER=$(html_mtime "$MUTANT_SANDBOX")
    if [ "$HTML_BEFORE" = "$HTML_AFTER" ]; then
        ok "Section D: the paired mutation (always-fresh gate) WRONGLY skips a real content change, as expected -- Section B's assertion is genuinely load-bearing (it would have caught this)"
    else
        bad "Section D: the paired mutation did not change scenario (B)'s outcome -- Section B's assertion may not actually be exercising the wiring (mutation did not survive to flip the test, §1.1)"
    fi
fi
rm -rf "$MUTANT_SANDBOX"

echo ""
echo "== Summary: $PASS ok / $FAIL bad =="
[ "$FAIL" = "0" ] && exit 0
exit 1
