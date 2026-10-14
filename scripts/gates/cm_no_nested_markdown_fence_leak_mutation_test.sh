#!/usr/bin/env bash
# cm_no_nested_markdown_fence_leak_mutation_test.sh — paired §1.1 / §11.4.107(10)
# self-validation test for the CM-NO-NESTED-MARKDOWN-FENCE-LEAK gate
# (HXC-159 T-P9.03 F-19).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# A gate that cannot FAIL is a bluff gate (§11.4 / §1.1 / §11.4.107(10)). This
# test PROVES cm_no_nested_markdown_fence_leak.sh genuinely detects the
# defect class it claims to guard against, by pointing it at SANDBOXED
# (mktemp -d, never the real tree — §11.4.84) fixture files:
#
#   GOLDEN-GOOD   a correctly-nested Markdown document (outer fence run-length
#                 strictly longer than every fence nested inside it, per
#                 CommonMark) with a real mermaid diagram, a code sample
#                 inside a longer-fenced example block, and a second,
#                 top-level mermaid diagram             -> gate MUST PASS (rc=0)
#   GOLDEN-BAD-1  the exact historical defect: an inner ```mermaid block
#                 opened inside an outer fence of the SAME run-length
#                 (reproducing the class fixed 4x across B3/T-P8.01/T-P8.04/
#                 F-10)                                  -> gate MUST FAIL (rc=1),
#                                                             reporting S1 + S3
#   GOLDEN-BAD-2  a raw diagram directive with no fence at all (the
#                 artifact-layer leaked-directive symptom)
#                                                         -> gate MUST FAIL (rc=1),
#                                                             reporting S2
#   GOLDEN-BAD-3  a mermaid fence opened with `~~~` but closed with a bare
#                 ``` `-shaped line that never matches (mermaid imbalance,
#                 the class S1 alone cannot see because the fence
#                 CHARACTERS differ)                     -> gate MUST FAIL (rc=1),
#                                                             reporting S4
#   NEGATIVE      a document with ONLY a normal, correctly-fenced non-mermaid
#   CONTROL       code block and ordinary prose containing the word "graph"
#                 mid-sentence (never at line start) — proves the gate does
#                 NOT false-positive on innocuous content
#                                                         -> gate MUST PASS (rc=0)
#
# Each FAIL case additionally asserts the gate's output names the specific
# signature (S1/S2/S3/S4) expected, so a gate failing for an unrelated reason
# cannot pass this test.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/gates/cm_no_nested_markdown_fence_leak_mutation_test.sh [--quiet]
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   NONE from the real tree — every fixture is authored fresh inside a
#   `mktemp -d` sandbox.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per case + a verdict. Exit 0 — the gate is proven
#   non-bluff (catches every golden-bad case, passes golden-good AND the
#   negative control). Exit 1 — the gate failed to discriminate correctly.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE on the repo. Every fixture lives inside a `mktemp -d` sandbox removed
#   by the EXIT trap (§11.4.14 / §11.4.84).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3, mktemp. Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 · §11.4.84 (sandbox-only mutation) · §11.4.107(10) (golden-good /
#   golden-bad self-validation) · gate: cm_no_nested_markdown_fence_leak.sh ·
#   detector: lib/nested_fence_detector.py
#
# Classification: universal (§11.4.17).
# Last verified: 2026-09-23
set -u

NAME="CM-NO-NESTED-MARKDOWN-FENCE-LEAK mutation"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
GATE="$SELF_DIR/cm_no_nested_markdown_fence_leak.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

FAILS=0
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { say "  PASS  [$NAME] $*"; }
bad()  { printf '  FAIL  [%s] %s\n' "$NAME" "$*" >&2; FAILS=$((FAILS + 1)); }

if [ ! -f "$GATE" ]; then
	bad "gate script missing: $GATE"
	echo "== $NAME: FAIL ==" >&2
	exit 1
fi

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT INT TERM
TMP=$(mktemp -d) || { bad "mktemp -d failed"; echo "== $NAME: FAIL ==" >&2; exit 1; }

run_gate() {
	# runs the gate against exactly the file(s) given, quiet, returns its rc
	bash "$GATE" --quiet "$@" >"$TMP/last_gate.out" 2>&1
	echo $?
}

# ── GOLDEN-GOOD — correctly-nested Markdown ──────────────────────────────────
cat > "$TMP/golden_good.md" <<'FIXTURE'
# Correctly-Nested Example Document

Here is a worked example of embedding a diagram sample inside a longer
outer fence, per CommonMark's own recommended nesting convention (outer
fence run-length strictly greater than any fence nested inside it):

````markdown
```mermaid
graph TD
  A --> B
```
````

And here is a real, standalone, correctly top-level-fenced mermaid diagram:

```mermaid
graph TD
  C --> D
```

Some prose that simply mentions the word graph in passing, never at the
start of a line, never intended as a diagram directive.
FIXTURE
rc=$(run_gate "$TMP/golden_good.md")
if [ "$rc" -eq 0 ]; then
	ok "golden-good: correctly-nested document → gate PASSes (rc=0)"
else
	bad "golden-good: correctly-nested document → gate FAILed (rc=$rc) — the detector itself is broken; output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi

# ── GOLDEN-BAD-1 — the exact historical defect (S1 + S3) ────────────────────
cat > "$TMP/golden_bad_1.md" <<'FIXTURE'
# Historical Defect Reproduction

```
outer fence content before the nested block

```mermaid
graph TD
  A --> B
```

outer fence content after — this text (and the diagram source above it)
leaks into the exported document as literal body text once the outer
fence's own closer fires early.
```
FIXTURE
rc=$(run_gate "$TMP/golden_bad_1.md")
if [ "$rc" -ne 0 ] && grep -q ' S1 ' "$TMP/last_gate.out" && grep -q ' S3 ' "$TMP/last_gate.out"; then
	ok "golden-bad-1: same-run-length nested mermaid block → gate FAILs (rc=$rc), reporting S1 + S3"
else
	bad "golden-bad-1: same-run-length nested mermaid block did NOT make the gate fail correctly (rc=$rc); output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi

# ── GOLDEN-BAD-2 — leaked directive with no fence at all (S2) ────────────────
cat > "$TMP/golden_bad_2.md" <<'FIXTURE'
# Unfenced Directive

graph TD
  A --> B
FIXTURE
rc=$(run_gate "$TMP/golden_bad_2.md")
if [ "$rc" -ne 0 ] && grep -q ' S2 ' "$TMP/last_gate.out"; then
	ok "golden-bad-2: unfenced diagram directive → gate FAILs (rc=$rc), reporting S2"
else
	bad "golden-bad-2: unfenced diagram directive did NOT make the gate fail correctly (rc=$rc); output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi

# ── GOLDEN-BAD-3 — mermaid fence-character mismatch (S4, S1 alone blind) ─────
cat > "$TMP/golden_bad_3.md" <<'FIXTURE'
# Fence-Character-Mismatch Imbalance

```mermaid
graph TD
~~~
A --> B
~~~
FIXTURE
rc=$(run_gate "$TMP/golden_bad_3.md")
if [ "$rc" -ne 0 ] && grep -q ' S4 ' "$TMP/last_gate.out"; then
	ok "golden-bad-3: mermaid opener never closed by a matching-char fence → gate FAILs (rc=$rc), reporting S4"
else
	bad "golden-bad-3: mermaid fence-character mismatch did NOT make the gate fail correctly (rc=$rc); output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi

# ── NEGATIVE CONTROL — innocuous content must still PASS ────────────────────
cat > "$TMP/negative_control.md" <<'FIXTURE'
# Negative Control

This document has a normal, correctly-fenced code block and mentions the
word graph mid-sentence, never at the start of a line.

```bash
echo "no diagrams here, just a normal shell snippet"
```

A directed graph is a common data structure, but this sentence is prose,
not a diagram directive, because "graph" here is not followed by a
direction keyword at the start of a line.
FIXTURE
rc=$(run_gate "$TMP/negative_control.md")
if [ "$rc" -eq 0 ]; then
	ok "negative control: innocuous prose + normal fenced block → gate still PASSes (rc=$rc), proving no false-positive"
else
	bad "negative control: innocuous content → gate FAILed (rc=$rc) — a false-positive refusal (§11.4.201(1)); output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILS" -eq 0 ]; then
	say "== $NAME: PASS (5/5 cases) =="
	exit 0
fi
printf '== %s: FAIL (%s failing case(s)) ==\n' "$NAME" "$FAILS" >&2
exit 1
