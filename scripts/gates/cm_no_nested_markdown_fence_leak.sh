#!/usr/bin/env bash
# cm_no_nested_markdown_fence_leak.sh — CM-NO-NESTED-MARKDOWN-FENCE-LEAK gate
# (HXC-159 T-P9.03 F-19: promote the round-1/round-3 fence auditor into a
# permanent §11.4.135 regression guard).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.168 requires every exported document (HTML/PDF) to be independently
# validated for CONTENT + TEXTUAL + FULL-VISUAL fidelity — no raw diagram
# source leaking into the exported body as plain text. A nested-Markdown-fence
# defect (an inner fenced block, e.g. ```mermaid, opened inside an outer fence
# of the same character whose run-length is <= the inner one) causes the
# outer fence's own closer to fire prematurely, and everything between the
# inner opener and that closer renders as literal prose in the exported
# artifact. This exact class was "finally fixed" FOUR separate times across
# Phase B3 / T-P8.01 / T-P8.04 / the F-10 regeneration pass
# (specs/001-helixskills-incorporation/tasks.md F-19) with NO standing
# regression guard between fixes — the detector lived only as one-off scripts
# under docs/qa/.../captures/, in no scripts/gates/ location, and in no
# pre-build sweep. This gate closes that gap: it is the auditor, wired in,
# permanent, and self-validated (§11.4.107(10)).
#
# The detection logic itself is NOT reinvented here — it is the promoted,
# merged form of two independently-authored, control-needle-validated
# review instruments (round-1 fence_audit.py + round-3 fence_scan2.py, both
# agreeing 0/0 across the same 18-file corpus per §11.4.273). See
# lib/nested_fence_detector.py's own header for the full provenance + the
# CommonMark state-machine this gate asserts.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/gates/cm_no_nested_markdown_fence_leak.sh \
#       [--root <repo-root>] [--quiet] [<file.md> ...]
#
#   --root    repo root to resolve the default corpus's relative paths
#             against (defaults to three levels above this script, i.e. the
#             outer meta-repo root — the default corpus lives partly under
#             constitution/, partly under the outer repo, per the round-3
#             validated file list).
#   --quiet   suppress PASS-line chatter; FAIL detail still prints.
#   <file.md> one or more explicit files to scan INSTEAD of the default
#             corpus. Used by the paired §1.1 mutation test to point the
#             gate at sandboxed fixtures (§11.4.84 — the real tree is never
#             mutated).
#
# ── Default corpus ───────────────────────────────────────────────────────────
# The same 18 files round-3's two-instrument agreement run validated clean
# (docs/qa/hxc159_t_p9_01_review3_20260923/captures/
# 15_fence_two_instruments.txt): the 8 Bridge design documents under
# constitution/docs/research/extensions/speckit_superpowers/implementation/,
# plus the other HXC-159-relevant docs (skills architecture/capabilities/
# guides, the extensions catalogue, the HelixAgent skills doc, the top-level
# README, and the 3 HXC-159 spec files). A file that no longer exists at its
# recorded path is reported as an honest gap (§11.4.3 SKIP-with-reason per
# file), never silently dropped from the count.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   The corpus files themselves (read-only).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One line per finding (from lib/nested_fence_detector.py) + a per-file
#   PASS/FAIL summary + a verdict line. Exit 0 — every scanned file has zero
#   findings. Exit 1 — one or more findings were reported. Exit 2 — python3
#   is unavailable or the detector library is missing (a setup error, never
#   silently treated as a clean pass — §11.4.201 conservative default).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE. Read-only against every scanned file.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 (stdlib only — json, re, sys). Parses clean under
#   `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   specs/001-helixskills-incorporation/tasks.md F-19 (this gate's origin) ·
#   §11.4.135 (standing regression-guard suite) · §11.4.168 (exported-document
#   independent validation — the defect class this guards) · §11.4.107(10)
#   (self-validated analyzer, golden-good/golden-bad) · §11.4.273 (two
#   independent instruments must agree — the provenance this gate's
#   detection logic carries forward) · §1.1 (paired mutation:
#   cm_no_nested_markdown_fence_leak_mutation_test.sh) ·
#   lib/nested_fence_detector.py (the merged detector this gate invokes)
#
# Classification: universal (§11.4.17) — the CommonMark nested-fence defect
# class + the exported-document validation obligation it guards are
# platform-neutral; the DEFAULT CORPUS list is this project's own concrete
# instantiation (§11.4.35) and any consuming project supplies its own.
# Last verified: 2026-09-23
set -u

GATE_ID="CM-NO-NESTED-MARKDOWN-FENCE-LEAK"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
# SELF_DIR = <repo-root>/constitution/scripts/gates — two levels up is the
# constitution submodule root, three levels up is the OUTER meta-repo root.
# The default corpus mixes paths rooted at BOTH (constitution/docs/... and
# helix_code/docs/..., docs/..., submodules/..., specs/..., README.md), so
# ROOT here means the OUTER repo root, matching how every path in the
# corpus list below is written.
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
DETECTOR="$SELF_DIR/lib/nested_fence_detector.py"
QUIET=0

# Parse leading options only; the first non-option argument (or a bare `--`)
# ends option parsing and everything remaining is the explicit file list.
while [ $# -gt 0 ]; do
	case "$1" in
		--root) ROOT="$2"; shift 2 ;;
		--quiet) QUIET=1; shift ;;
		-h|--help) sed -n '2,90p' "$0"; exit 0 ;;
		--) shift; break ;;
		-*) echo "$GATE_ID: unknown arg: $1" >&2; exit 2 ;;
		*) break ;;
	esac
done
FILES=("$@")

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
pass() { say "  PASS  [$GATE_ID] $*"; }
fail() { printf '  FAIL  [%s] %s\n' "$GATE_ID" "$*" >&2; }

say "== $GATE_ID =="

if ! command -v python3 >/dev/null 2>&1; then
	fail "python3 not found on PATH — cannot run the detector (conservative refusal, §11.4.201)"
	exit 2
fi
if [ ! -f "$DETECTOR" ]; then
	fail "detector library missing: $DETECTOR"
	exit 2
fi

# ── Default corpus (round-3 two-instrument-validated 18-file list) ──────────
if [ "${#FILES[@]}" -eq 0 ]; then
	FILES=(
		"constitution/docs/research/extensions/speckit_superpowers/implementation/README.md"
		"constitution/docs/research/extensions/speckit_superpowers/implementation/IMPLEMENTATION_PLAN.md"
		"constitution/docs/research/extensions/speckit_superpowers/implementation/NANO_TASK_ENGINE.md"
		"constitution/docs/research/extensions/speckit_superpowers/implementation/EXTENSION_DEVELOPMENT.md"
		"constitution/docs/research/extensions/speckit_superpowers/implementation/TDD_INTEGRATION.md"
		"constitution/docs/research/extensions/speckit_superpowers/implementation/CONSTITUTION_INTEGRATION.md"
		"constitution/docs/research/extensions/speckit_superpowers/implementation/SECURITY.md"
		"constitution/docs/research/extensions/speckit_superpowers/implementation/APPENDIX.md"
		"helix_code/docs/architecture/skills_architecture.md"
		"helix_code/docs/CAPABILITIES.md"
		"helix_code/docs/guides/skills_user_manual.md"
		"helix_code/docs/guides/skills_faq.md"
		"docs/extensions/EXTENSIONS_CATALOG.md"
		"submodules/helix_agent/docs/skills/SKILLS_SYSTEM.md"
		"README.md"
		"specs/001-helixskills-incorporation/tasks.md"
		"specs/001-helixskills-incorporation/plan.md"
		"specs/001-helixskills-incorporation/spec.md"
	)
	RESOLVE_AGAINST_ROOT=1
else
	# Explicit files were passed (e.g. by the paired mutation test against a
	# sandbox) — use them exactly as given, never re-rooted.
	RESOLVE_AGAINST_ROOT=0
fi

TO_SCAN=()
MISSING=()
for f in "${FILES[@]}"; do
	if [ "$RESOLVE_AGAINST_ROOT" -eq 1 ]; then
		p="$ROOT/$f"
	else
		p="$f"
	fi
	if [ -f "$p" ]; then
		TO_SCAN+=("$p")
	else
		MISSING+=("$f")
	fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
	for m in "${MISSING[@]}"; do
		say "  SKIP  [$GATE_ID] $m — file not found at its recorded corpus path (§11.4.3 honest gap, not silently dropped)"
	done
fi

if [ "${#TO_SCAN[@]}" -eq 0 ]; then
	fail "no scannable files resolved (corpus fully missing) — cannot certify anything, refusing per §11.4.201 conservative default"
	exit 2
fi

OUT=$(python3 "$DETECTOR" "${TO_SCAN[@]}" 2>&1)
RC=$?

if [ "$RC" -eq 0 ]; then
	pass "0 findings across ${#TO_SCAN[@]} file(s) (${#MISSING[@]} honest gap(s) skipped)"
	say "$OUT" | sed 's/^/    /'
	echo "== $GATE_ID: PASS (${#TO_SCAN[@]} file(s), 0 findings) =="
	exit 0
else
	fail "nested-fence / leaked-directive / unclosed-fence / mermaid-imbalance finding(s) detected — see output below"
	printf '%s\n' "$OUT" | sed 's/^/    /' >&2
	echo "== $GATE_ID: FAIL (findings present, see above) ==" >&2
	exit 1
fi
