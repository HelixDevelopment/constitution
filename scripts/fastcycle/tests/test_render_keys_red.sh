#!/bin/sh
# =============================================================================
# T062 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C12; SC-002, FR-022).
# =============================================================================
#
# Purpose: prove, BEFORE T-C12's `docs/render_keys.py` implementation
# exists, all 4 named cases from tasks.md's T062 line verbatim: "(an
# unchanged source re-renders today; a changed source re-renders all four
# formats; golden-bad: a twin whose source changed but whose key was not
# updated is caught by the freshness gate; touched-but-identical file
# fixture shows mtime vs content difference)". Concretely:
#
#   (1) control needle -- an UNCHANGED source (touched mtime, byte-identical
#       content, sha256-verified) genuinely re-renders TODAY via a REAL
#       invocation of the ALREADY-EXISTING `scripts/testing/
#       sync_all_markdown_exports.sh`, because its current freshness check
#       is mtime-only (`[ "$md" -nt "$html" ]`, no content hash anywhere --
#       proven in Section B by grepping the real script's own text). This
#       is the wasteful BEFORE state T-C12's own Expected-saving hypothesis
#       targets.
#   (2) golden -- a genuinely CHANGED source (real content edit) re-renders
#       ALL THREE sibling formats (.html/.pdf/.docx) via the SAME real
#       exporter -- the full §11.4.65 four-format set alongside the .md
#       source of truth. This correct behaviour must be PRESERVED, never
#       weakened, once T-C12 lands (FR-022).
#   (3) golden-bad -- a twin whose source genuinely changed but whose
#       recorded key sidecar was NOT updated (the exact defect T-C12's
#       freshness gate must catch) is checked via a real invocation of the
#       (today, absent) `docs/render_keys.py check` -- rc=127 today,
#       self-flips GREEN once T-C12 lands.
#   (4) the direct positive contrast to (1) -- a touched-but-content-
#       identical fixture (self-validated in Section B: real `touch` +
#       real `sha256sum` before/after prove mtime and content are
#       genuinely distinguishable on this host) is checked via a real
#       invocation of the (today, absent) `docs/render_keys.py check`
#       against a MATCHING recorded key -- rc=127 today, self-flips GREEN
#       (expected: FRESH, skip) once T-C12 lands.
#
# Contract: specs/004-fast-dev-cycles/plan.md T-C12 ("Content-addressed,
#   parallel, batched twin regeneration") + SC-002/FR-022 in spec.md. No
#   dedicated contracts/ file names render_keys.py explicitly (confirmed
#   absent by this file's own author, per the same "no contract exists"
#   pattern T057/T060/T061 already document). The assumed CLI contract for
#   render_keys.py (UNCONFIRMED by the plan itself, DEFINED here, binding-
#   if-adopted on the implementer) is documented in
#   fixtures/render_keys/README.md, following the house precedent set by
#   fixtures/verdict_cache/README.md and fixtures/dispatch_stamp/.
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# its fixtures under fixtures/render_keys/ + the standalone reference key
# builder at lib/render_keys_ref.py (never render_keys.py itself, T-C12's
# own separate later task). Every check below is either (a) a real
# invocation of the ALREADY-EXISTING, already-implemented
# scripts/testing/sync_all_markdown_exports.sh this file performs itself
# (Section C1/C2, proving today's BEFORE state), or (b) a real invocation
# of the (today, absent) docs/render_keys.py tool, reported RED because the
# tool cannot be found (Section C3/C4) -- never a synthetic "tool absent ->
# assume PASS" stub.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for C3/C4's tool-invocation checks -- C1/C2's real-exporter
#       checks and Section B's mechanism self-checks are expected to PASS
#       today, since they exercise only the already-landed real exporter
#       and real host tools, never the absent render_keys.py).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
TOOL="$FC/docs/render_keys.py"
FIXDIR="$HERE/fixtures/render_keys"
REFKEY="$HERE/lib/render_keys_ref.py"
EXPORTER="$REPO_ROOT/scripts/testing/sync_all_markdown_exports.sh"
STYLESHEET="constitution/styles/default-md.css"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T062 RED: content-addressed, parallel, batched twin regeneration (plan T-C12; SC-002, FR-022) =="

# =============================================================================
# Cleanup -- ALWAYS restore every fixture source.md to its ORIGINAL,
# checked-in bytes and remove every generated .html/.pdf/.docx this test
# itself renders, on EVERY exit path. Keeps the tracked fixture tree at
# exactly {source.md, key_*.json, expected.json} -- matching the
# established convention across every other fixtures/*/ directory -- and
# makes repeated invocations of this file idempotent (§11.4.50).
# =============================================================================
_BACKUP_DIR=$(mktemp -d 2>/dev/null || echo "/tmp/t062_backup_$$")
mkdir -p "$_BACKUP_DIR" 2>/dev/null
cp "$FIXDIR/rk_changed_all_four/source.md" "$_BACKUP_DIR/changed_all_four.orig.md" 2>/dev/null
cp "$FIXDIR/rk_stale_key_caught/source.md" "$_BACKUP_DIR/stale_key_caught.orig.md" 2>/dev/null

# I8(a) fix (T085 Round 1, 2026-09-30): the pre-remediation cleanup()
# unconditionally `rm -f`'d every source.{html,pdf,docx} twin under all 4
# fixture directories on every exit path -- but 9+ of those exact 12 files
# are TRACKED, committed fixture twins (the doc-twin exporter, constitution
# commit 310c065), not test-generated throwaway output. A real run of this
# test therefore left the working tree with tracked files genuinely
# DELETED from disk (confirmed live before this fix: `git status
# --porcelain` reported them ` D <path>` after a run, requiring a manual
# `git checkout --` to restore -- exactly the T085 Round 1 I8 finding's
# repro). This test's OWN rendering work (if any) into these same paths is
# still cleaned up.
#
# T085 Round 3 R3-I3 (IMPORTANT): the I8(a) fix above restored a TRACKED
# twin via `git checkout -- "$f"` -- but that restores the file to its
# COMMITTED-AT-HEAD bytes, discarding ANY uncommitted edit, including a
# DIFFERENT, concurrently-running track's own legitimate, not-yet-
# committed work on that exact tracked file. Confirmed live on this
# checkout (2026-10-02): 4 of these exact 12 twins --
# rk_stale_key_caught/source.{docx,pdf} and
# rk_touched_identical/source.{docx,pdf} -- were concurrently modified
# and uncommitted at the moment this fix was written; a run of the
# pre-R3-I3 cleanup() would have silently discarded that other track's
# work via `git checkout --`, even though THIS test's own render work
# (Section C/D below) never touches rk_stale_key_caught/ or
# rk_touched_identical/ at all -- `git checkout --` was applied
# UNCONDITIONALLY to every tracked twin in all 4 directories, regardless
# of whether this specific run ever wrote to that specific file.
#
# Fixed: a CAPTURED-CONTENT snapshot-and-restore, never `git checkout --`.
# Every twin file that EXISTS on disk right now (before this test does
# ANY work) has its CURRENT, real, de-facto bytes -- whatever they
# genuinely are at this exact moment, including any OTHER track's
# uncommitted edits -- copied into $_BACKUP_DIR. On cleanup, each such
# file is restored FROM THAT SNAPSHOT (a plain `cp`, never a `git`
# operation that could reach into history and discard concurrent work).
# A file that did NOT exist before this test started (this test's own
# fresh, first-time render of a twin that was absent) has no snapshot to
# restore from and is instead `rm -f`'d, exactly as the untracked case
# always was -- this test never leaves behind output it itself created
# from nothing, and never touches anything that already existed before
# it ran beyond putting it back exactly as found.
_RK_SNAPSHOT_FILES=""
for d in rk_unchanged_today rk_changed_all_four rk_stale_key_caught rk_touched_identical; do
    for ext in html pdf docx; do
        f="$FIXDIR/$d/source.$ext"
        if [ -f "$f" ]; then
            snap="$_BACKUP_DIR/twin__${d}__source.${ext}"
            cp "$f" "$snap" 2>/dev/null
            _RK_SNAPSHOT_FILES="$_RK_SNAPSHOT_FILES $f"
        fi
    done
done

cleanup() {
    [ -f "$_BACKUP_DIR/changed_all_four.orig.md" ] && cp "$_BACKUP_DIR/changed_all_four.orig.md" "$FIXDIR/rk_changed_all_four/source.md" 2>/dev/null
    [ -f "$_BACKUP_DIR/stale_key_caught.orig.md" ] && cp "$_BACKUP_DIR/stale_key_caught.orig.md" "$FIXDIR/rk_stale_key_caught/source.md" 2>/dev/null
    for d in rk_unchanged_today rk_changed_all_four rk_stale_key_caught rk_touched_identical; do
        for ext in html pdf docx; do
            f="$FIXDIR/$d/source.$ext"
            snap="$_BACKUP_DIR/twin__${d}__source.${ext}"
            case " $_RK_SNAPSHOT_FILES " in
                *" $f "*)
                    # A real, pre-existing snapshot of this EXACT file's
                    # own bytes as they stood immediately before this
                    # test ran -- restore from it directly, NEVER via
                    # `git checkout --` (R3-I3 fix: this can never
                    # discard a concurrent track's uncommitted edit,
                    # because it restores the file to the state it was
                    # ALREADY in, not to git HEAD).
                    [ -f "$snap" ] && cp "$snap" "$f" 2>/dev/null
                    ;;
                *)
                    # No snapshot was captured because the file did NOT
                    # exist before this test started -- this test's own
                    # fresh render of a file that was genuinely absent.
                    # Safe to remove; there is nothing pre-existing
                    # (from this test, a concurrent track, or git HEAD)
                    # that removing it could discard.
                    rm -f "$f" 2>/dev/null
                    ;;
            esac
        done
    done
    rm -rf "$_BACKUP_DIR" 2>/dev/null
}
trap cleanup EXIT

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-C12 has landed; Section C3/C4's real"
    echo "   invocation checks below are the functional tests to run"
else
    echo "RED: $TOOL is absent -- T-C12 (docs/render_keys.py) has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

if [ -d "$FC/docs" ]; then
    NON_GITKEEP=$(find "$FC/docs" -maxdepth 1 -type f ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$NON_GITKEEP" -eq 0 ]; then
        ok "control needle: $FC/docs/ genuinely holds nothing but .gitkeep --"
        echo "   confirms render_keys.py is absent by DIRECTORY CONTENT, not"
        echo "   merely by the single-path check above"
    else
        echo "NOTE: $FC/docs/ holds $NON_GITKEEP non-.gitkeep file(s) already --"
        echo "      re-check whether T-C12 (or a sibling task) has partially landed"
    fi
else
    bad "control needle FAILED: $FC/docs/ does not exist at all -- Setup"
    echo "   phase (T001-T006) has not created it"
fi

if [ ! -f "$EXPORTER" ]; then
    bad "control needle FAILED: $EXPORTER does not exist -- Section C1/C2's"
    echo "   entire premise (the CURRENT exporter's mtime-only wasteful"
    echo "   re-render behaviour) cannot be exercised without it"
else
    ok "control needle: the already-existing $EXPORTER genuinely exists --"
    echo "   Section C1/C2 below invoke it for real"
fi

HAVE_PANDOC=0
if command -v pandoc >/dev/null 2>&1; then
    HAVE_PANDOC=1
    ok "control needle: pandoc is available ($(pandoc --version 2>&1 | head -1))"
else
    bad "control needle FAILED: pandoc not found on this host -- Section"
    echo "   C1/C2's real-render proofs cannot run without it"
fi

HAVE_WEASYPRINT=0
if command -v weasyprint >/dev/null 2>&1; then
    HAVE_WEASYPRINT=1
    ok "control needle: weasyprint is available ($(weasyprint --version 2>&1 | head -1))"
else
    bad "control needle FAILED: weasyprint not found on this host -- the"
    echo "   PDF leg of Section C1/C2's real-render proofs cannot run"
    echo "   without it (HTML/DOCX legs still can)"
fi

if [ ! -f "$REFKEY" ]; then
    bad "control needle FAILED: $REFKEY (the standalone reference key"
    echo "   builder this test uses to ground its own key.json fixtures in"
    echo "   a real, self-validated computation) is missing"
fi

# =============================================================================
# Section B -- self-validation of the underlying MECHANISMS
# (§11.4.107(10)/§11.4.273: "the path is part of the instrument" -- proving
# these mechanisms sound, with REAL commands against REAL fixture files,
# BEFORE any claim is made about what the (absent) render_keys.py tool
# should do with them). Never a substitute for Section C's real tool
# invocations -- it only proves the mechanisms T-C12's implementer will
# build on are sound.
# =============================================================================

# --- B1: today's freshness mechanism IS mtime-only, measured from the
#     real exporter's own source text, not assumed from reading the plan.
if [ -f "$EXPORTER" ]; then
    if grep -q '\-nt "\$html"' "$EXPORTER" 2>/dev/null || grep -q '\-nt "\$pdf"' "$EXPORTER" 2>/dev/null; then
        ok "B1 mechanism self-check: the real exporter's own text genuinely"
        echo "   contains the mtime-only freshness comparison ([ \"\$md\" -nt"
        echo "   \"\$html\" ]) -- the 'BEFORE state' premise is a measured fact"
        echo "   about this script's real source, never an assumption"
        if grep -qE 'sha256|md5sum|content.hash|content_hash' "$EXPORTER" 2>/dev/null; then
            bad "B1b unexpected: the real exporter ALSO already contains a"
            echo "    content-hash reference -- re-check whether T-C12's key"
            echo "    mechanism has already been partially wired into it"
        else
            ok "B1b confirmed: the real exporter's classify loop contains NO"
            echo "    sha256/md5/content-hash reference anywhere -- today's"
            echo "    freshness decision is provably mtime-only, end to end"
        fi
    else
        bad "B1 mechanism self-check FAILED: the real exporter's text does"
        echo "   NOT contain the expected mtime-only comparison pattern --"
        echo "   either the exporter's freshness logic changed since this"
        echo "   test was authored, or the grep pattern needs re-deriving"
    fi
fi

# --- B2: capture REAL host tool versions -- used to compute the key
#     fixtures below, and re-derivable by anyone re-running this test.
PANDOC_VER=""
WEASY_VER=""
if [ "$HAVE_PANDOC" = "1" ]; then
    PANDOC_VER=$(pandoc --version 2>&1 | head -1)
fi
if [ "$HAVE_WEASYPRINT" = "1" ]; then
    WEASY_VER=$(weasyprint --version 2>&1 | head -1)
fi
if [ -f "$EXPORTER" ]; then
    EXPORTER_VERSION=$(command -v sha256sum >/dev/null 2>&1 && sha256sum "$EXPORTER" | awk '{print $1}')
    if [ -n "${EXPORTER_VERSION:-}" ]; then
        ok "B2 captured real host tool versions -- pandoc='$PANDOC_VER'"
        echo "   weasyprint='$WEASY_VER' exporter_version(sha256)=$EXPORTER_VERSION"
    else
        bad "B2 FAILED: could not compute a sha256 of $EXPORTER (sha256sum"
        echo "   missing?) -- the exporter_version key component cannot be"
        echo "   derived"
    fi
fi

# --- B3: the touch/sha256 distinguishability mechanism the future
#     content-addressed key relies on -- proven REAL, against the REAL
#     rk_touched_identical/ fixture, before any claim is made about it.
TI_SRC="$FIXDIR/rk_touched_identical/source.md"
if [ -f "$TI_SRC" ] && command -v sha256sum >/dev/null 2>&1; then
    TI_SHA_BEFORE=$(sha256sum "$TI_SRC" | awk '{print $1}')
    TI_MTIME_BEFORE=$(stat -c '%Y' "$TI_SRC" 2>/dev/null)
    touch -d '+2 seconds' "$TI_SRC" 2>/dev/null || touch "$TI_SRC"
    TI_SHA_AFTER=$(sha256sum "$TI_SRC" | awk '{print $1}')
    TI_MTIME_AFTER=$(stat -c '%Y' "$TI_SRC" 2>/dev/null)
    if [ "$TI_SHA_BEFORE" = "$TI_SHA_AFTER" ] && [ "$TI_MTIME_AFTER" != "$TI_MTIME_BEFORE" ]; then
        ok "B3 mechanism self-check: a real touch on rk_touched_identical/"
        echo "   source.md genuinely changed its mtime ($TI_MTIME_BEFORE ->"
        echo "   $TI_MTIME_AFTER) while its sha256 stayed BYTE-IDENTICAL"
        echo "   ($TI_SHA_BEFORE) -- mtime and content are genuinely"
        echo "   distinguishable on this host, the property a"
        echo "   content-addressed key depends on (§11.4.273 -- the"
        echo "   null-hypothesis needle: had the sha256 also changed, this"
        echo "   whole fixture's premise would be false, not merely"
        echo "   unproven)"
    else
        bad "B3 mechanism self-check FAILED: either the sha256 changed"
        echo "   ($TI_SHA_BEFORE -> $TI_SHA_AFTER, meaning touch corrupted"
        echo "   content) or the mtime did NOT change ($TI_MTIME_BEFORE ->"
        echo "   $TI_MTIME_AFTER, meaning touch had no effect) -- the"
        echo "   distinguishability mechanism T-C12 depends on could not be"
        echo "   proven sound on this host"
    fi
else
    bad "B3 mechanism self-check FAILED: rk_touched_identical/source.md or"
    echo "   sha256sum is missing -- cannot prove the touch mechanism"
fi

# =============================================================================
# Section C -- real invocations.
# =============================================================================

# --- C1: control needle (case 1) -- an unchanged source re-renders TODAY,
#     via a real invocation of the ALREADY-EXISTING exporter.
UT_SRC="$FIXDIR/rk_unchanged_today/source.md"
if [ "$HAVE_PANDOC" = "1" ] && [ "$HAVE_WEASYPRINT" = "1" ] && [ -f "$EXPORTER" ] && [ -f "$UT_SRC" ]; then
    UT_REL="constitution/scripts/fastcycle/tests/fixtures/render_keys/rk_unchanged_today/source.md"
    ( cd "$REPO_ROOT" && bash "$EXPORTER" --paths "$UT_REL" >/dev/null 2>&1 )
    C1_BASELINE_RC=$?
    UT_HTML="$FIXDIR/rk_unchanged_today/source.html"
    if [ "$C1_BASELINE_RC" -eq 0 ] && [ -f "$UT_HTML" ]; then
        C1_SHA_BEFORE=$(sha256sum "$UT_SRC" | awk '{print $1}')
        C1_HTML_MTIME_BEFORE=$(stat -c '%Y' "$UT_HTML" 2>/dev/null)
        touch -d '+2 seconds' "$UT_SRC" 2>/dev/null || touch "$UT_SRC"
        C1_SHA_AFTER=$(sha256sum "$UT_SRC" | awk '{print $1}')
        ( cd "$REPO_ROOT" && bash "$EXPORTER" --paths "$UT_REL" >/dev/null 2>&1 )
        C1_RERENDER_RC=$?
        C1_HTML_MTIME_AFTER=$(stat -c '%Y' "$UT_HTML" 2>/dev/null)
        if [ "$C1_SHA_BEFORE" = "$C1_SHA_AFTER" ] \
            && [ "$C1_RERENDER_RC" -eq 0 ] \
            && [ "$C1_HTML_MTIME_AFTER" -gt "$C1_HTML_MTIME_BEFORE" ] 2>/dev/null; then
            ok "C1 control needle: a REAL invocation of the CURRENT exporter"
            echo "   re-rendered rk_unchanged_today/source.md's .html sibling"
            echo "   (mtime $C1_HTML_MTIME_BEFORE -> $C1_HTML_MTIME_AFTER) despite"
            echo "   its content staying byte-identical (sha256 $C1_SHA_BEFORE"
            echo "   both before and after the touch) -- the BEFORE state"
            echo "   T-C12 fixes, genuinely reproduced today"
        else
            bad "C1 control needle FAILED: expected an unchanged-content,"
            echo "   touched-mtime re-render (sha_before=$C1_SHA_BEFORE"
            echo "   sha_after=$C1_SHA_AFTER rerender_rc=$C1_RERENDER_RC"
            echo "   mtime_before=$C1_HTML_MTIME_BEFORE"
            echo "   mtime_after=$C1_HTML_MTIME_AFTER)"
        fi
    else
        bad "C1 control needle FAILED: baseline render of"
        echo "   rk_unchanged_today/source.md did not succeed (rc=$C1_BASELINE_RC,"
        echo "   html_exists=$([ -f "$UT_HTML" ] && echo yes || echo no))"
    fi
else
    bad "C1 control needle SKIPPED-AS-FAIL: pandoc/weasyprint/exporter/fixture"
    echo "   prerequisite missing -- cannot exercise the real exporter"
fi

# --- C2: golden (case 2) -- a changed source re-renders ALL FOUR formats,
#     via a real invocation of the ALREADY-EXISTING exporter.
CA_SRC="$FIXDIR/rk_changed_all_four/source.md"
if [ "$HAVE_PANDOC" = "1" ] && [ "$HAVE_WEASYPRINT" = "1" ] && [ -f "$EXPORTER" ] && [ -f "$CA_SRC" ]; then
    CA_REL="constitution/scripts/fastcycle/tests/fixtures/render_keys/rk_changed_all_four/source.md"
    ( cd "$REPO_ROOT" && bash "$EXPORTER" --paths "$CA_REL" >/dev/null 2>&1 )
    C2_BASELINE_RC=$?
    CA_HTML="$FIXDIR/rk_changed_all_four/source.html"
    CA_PDF="$FIXDIR/rk_changed_all_four/source.pdf"
    CA_DOCX="$FIXDIR/rk_changed_all_four/source.docx"
    if [ "$C2_BASELINE_RC" -eq 0 ] && [ -f "$CA_HTML" ] && [ -f "$CA_PDF" ] && [ -f "$CA_DOCX" ] \
        && grep -q 'RK-CHANGED-V1' "$CA_HTML" 2>/dev/null; then
        C2_HTML_MTIME_BEFORE=$(stat -c '%Y' "$CA_HTML" 2>/dev/null)
        C2_PDF_MTIME_BEFORE=$(stat -c '%Y' "$CA_PDF" 2>/dev/null)
        C2_DOCX_MTIME_BEFORE=$(stat -c '%Y' "$CA_DOCX" 2>/dev/null)
        sed -i 's/RK-CHANGED-V1/RK-CHANGED-V2/' "$CA_SRC"
        touch -d '+2 seconds' "$CA_SRC" 2>/dev/null || touch "$CA_SRC"
        ( cd "$REPO_ROOT" && bash "$EXPORTER" --paths "$CA_REL" >/dev/null 2>&1 )
        C2_RERENDER_RC=$?
        C2_HTML_MTIME_AFTER=$(stat -c '%Y' "$CA_HTML" 2>/dev/null)
        C2_PDF_MTIME_AFTER=$(stat -c '%Y' "$CA_PDF" 2>/dev/null)
        C2_DOCX_MTIME_AFTER=$(stat -c '%Y' "$CA_DOCX" 2>/dev/null)
        if [ "$C2_RERENDER_RC" -eq 0 ] \
            && [ "$C2_HTML_MTIME_AFTER" -gt "$C2_HTML_MTIME_BEFORE" ] 2>/dev/null \
            && [ "$C2_PDF_MTIME_AFTER" -gt "$C2_PDF_MTIME_BEFORE" ] 2>/dev/null \
            && [ "$C2_DOCX_MTIME_AFTER" -gt "$C2_DOCX_MTIME_BEFORE" ] 2>/dev/null \
            && grep -q 'RK-CHANGED-V2' "$CA_HTML" 2>/dev/null \
            && ! grep -q 'RK-CHANGED-V1' "$CA_HTML" 2>/dev/null; then
            ok "C2 golden: a REAL content edit to rk_changed_all_four/source.md"
            echo "   (marker V1 -> V2) caused a REAL invocation of the CURRENT"
            echo "   exporter to regenerate ALL THREE sibling formats (html"
            echo "   $C2_HTML_MTIME_BEFORE->$C2_HTML_MTIME_AFTER, pdf"
            echo "   $C2_PDF_MTIME_BEFORE->$C2_PDF_MTIME_AFTER, docx"
            echo "   $C2_DOCX_MTIME_BEFORE->$C2_DOCX_MTIME_AFTER) with the new"
            echo "   marker present and the old marker gone from the rendered"
            echo "   html -- the correct behaviour T-C12 must preserve"
        else
            bad "C2 golden FAILED: expected all-three-siblings regeneration"
            echo "   with the updated marker (rerender_rc=$C2_RERENDER_RC"
            echo "   html $C2_HTML_MTIME_BEFORE->$C2_HTML_MTIME_AFTER pdf"
            echo "   $C2_PDF_MTIME_BEFORE->$C2_PDF_MTIME_AFTER docx"
            echo "   $C2_DOCX_MTIME_BEFORE->$C2_DOCX_MTIME_AFTER)"
        fi
    else
        bad "C2 golden FAILED: baseline render of rk_changed_all_four/source.md"
        echo "   did not succeed or did not contain the V1 marker"
        echo "   (rc=$C2_BASELINE_RC)"
    fi
else
    bad "C2 golden SKIPPED-AS-FAIL: pandoc/weasyprint/exporter/fixture"
    echo "   prerequisite missing -- cannot exercise the real exporter"
fi

# --- C3: golden-bad (case 3) -- a twin whose source changed but whose key
#     was not updated is caught by the (today, absent) freshness gate.
SK_SRC="$FIXDIR/rk_stale_key_caught/source.md"
SK_KEY="$FIXDIR/rk_stale_key_caught/key_v1.json"
if [ -f "$SK_SRC" ] && [ -f "$SK_KEY" ]; then
    sed -i 's/RK-STALE-V1/RK-STALE-V2/' "$SK_SRC"
    if [ -f "$TOOL" ]; then
        C3_OUT=$(python3 "$TOOL" check --source "$SK_SRC" --format html \
            --key-file "$SK_KEY" --stylesheet "$STYLESHEET" \
            --exporter-version "${EXPORTER_VERSION:-unknown}" \
            --pandoc-version "$PANDOC_VER" --weasyprint-version "$WEASY_VER" 2>&1)
        C3_RC=$?
    else
        C3_OUT="render_keys.py absent"
        C3_RC=127
    fi
    # T080 fix-forward (§11.4.6, documented not silent): originally read
    # `[ "$C3_RC" -eq 0 ] ...` here -- a copy/paste typo from C4's block
    # requiring a ZERO exit code on a STALE verdict, contradicting (a) this
    # file's own module docstring ("STALE + non-zero exit"), (b) this same
    # block's own `bad`-branch text three lines below ("STALE+nonzero"),
    # (c) fixtures/render_keys/README.md's CLI contract ("exits
    # non-zero"), and (d) C-001's exit-code table (a finding = exit 1).
    # Corrected to `-ne 0`, matching every one of those authorities and
    # C4's own correct, parallel `-eq 0`-on-FRESH pattern below -- this
    # STRENGTHENS the assertion (a gate that reports STALE but exits 0
    # would let a naive `if render_keys.py check; then skip; fi` caller
    # silently skip re-rendering a genuinely stale twin), it is never a
    # weakening.
    if [ "$C3_RC" -ne 0 ] && echo "$C3_OUT" | grep -qi 'STALE'; then
        ok "C3 golden-bad: render_keys.py check correctly caught the stale"
        echo "   key (source changed to V2, key_v1.json still recorded V1) --"
        echo "   reported STALE as expected"
    else
        bad "C3 golden-bad: render_keys.py check did not report STALE for the"
        echo "   changed-source/stale-key twin (rc=$C3_RC out=$C3_OUT) --"
        echo "   expected TODAY while the tool is absent (rc=127); once T-C12"
        echo "   lands this check must genuinely flip to STALE+nonzero"
    fi
else
    bad "C3 golden-bad SKIPPED-AS-FAIL: rk_stale_key_caught/ fixture files"
    echo "   are missing"
fi

# --- C4: the direct positive contrast (case 4) -- a touched-but-identical
#     twin (continuing from Section B3's real touch) is recognised FRESH by
#     the (today, absent) freshness gate, despite the mtime change.
TI_KEY="$FIXDIR/rk_touched_identical/key_matching.json"
if [ -f "$TI_SRC" ] && [ -f "$TI_KEY" ]; then
    if [ -f "$TOOL" ]; then
        C4_OUT=$(python3 "$TOOL" check --source "$TI_SRC" --format html \
            --key-file "$TI_KEY" --stylesheet "$STYLESHEET" \
            --exporter-version "${EXPORTER_VERSION:-unknown}" \
            --pandoc-version "$PANDOC_VER" --weasyprint-version "$WEASY_VER" 2>&1)
        C4_RC=$?
    else
        C4_OUT="render_keys.py absent"
        C4_RC=127
    fi
    if [ "$C4_RC" -eq 0 ] && echo "$C4_OUT" | grep -qi 'FRESH'; then
        ok "C4 positive contrast: render_keys.py check correctly recognised"
        echo "   rk_touched_identical/source.md as FRESH despite its mtime"
        echo "   having been touched in Section B3 -- direct, provable"
        echo "   contrast to C1's proof of today's mtime-only waste on the"
        echo "   exact same class of input"
    else
        bad "C4 positive contrast: render_keys.py check did not report FRESH"
        echo "   for the touched-but-identical twin (rc=$C4_RC out=$C4_OUT) --"
        echo "   expected TODAY while the tool is absent (rc=127); once T-C12"
        echo "   lands this check must genuinely flip to FRESH+exit-0"
    fi
else
    bad "C4 positive contrast SKIPPED-AS-FAIL: rk_touched_identical/ fixture"
    echo "   files are missing"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
