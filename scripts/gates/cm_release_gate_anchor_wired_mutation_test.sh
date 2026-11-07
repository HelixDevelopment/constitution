#!/usr/bin/env bash
# cm_release_gate_anchor_wired_mutation_test.sh — paired §1.1 mutation test for CM-RELEASE-GATE-ANCHOR-WIRED
#
# Purpose
#   Proves cm_release_gate_anchor_wired.sh genuinely discriminates, instead of passing whatever it
#   is shown. It copies the files the gate reads into a scratch tree and runs the gate:
#     * GREEN control    the unmodified copy MUST pass (exit 0);
#     * golden-FALSE     changes that must NOT trip the gate (a mid-body citation of §11.4.298
#                        elsewhere, an unrelated project section after a mirror block, a
#                        prefix-colliding decoy heading §11.4.2980, a whitespace-only edit inside
#                        the block, inside a pinned mirror block and inside the pinned release-gate
#                        note, the release-gate note re-wrapped across two lines) MUST still pass
#                        (§11.4.201(1)); --print-digests on the genuine tree MUST
#                        print exactly the pinned values, and a gate copy re-pinned from it after a text
#                        change MUST pass that change;
#     * RED mutations    every required marker phrase, every clause heading (A)..(G), every row of
#                        the closed gate-state table and a fifth row, every escape-hatch flag, every
#                        cross-reference, the back-pointer in §11.4.293, every mirror and its
#                        phrases, the index entry, the group file, the progressive rule file and
#                        catalog, the data-pack row, the generated wrappers, the seam binding, the
#                        deferral row, the hook bindings, a duplicated canon block, a stray second
#                        block-start form and a demoted heading are removed or broken ONE AT A TIME,
#                        and the gate MUST exit 1 and name that exact failed check; each of the 10
#                        marker-preserving weakenings of audit 2 (R1..R10: canon, the §11.4.293
#                        release-gate note, each mirror) MUST exit 1 and name the pin of the text it
#                        edits, and with the pin check disabled in a gate copy R5 MUST pass (the pin is
#                        what names it); a sentence added on the line after the release-gate note, and
#                        on the line before it, with no blank line between (audit 3, B1), MUST exit 1
#                        and name the pin of the note;
#     * BLIND            a broken block extractor, a missing Constitution.md, a lost real-file
#                        control needle, a pin digest that keeps whitespace and a note extractor that
#                        reads only the marker line MUST exit 2 (never a silent PASS).
#   Each mutation operator asserts it really changed the file; a no-op mutation is a test bug
#   (exit 2), never a green. No product or device name is stored in this file.
#
# Usage
#   cm_release_gate_anchor_wired_mutation_test.sh [--quiet]
#   Reads the real files from the constitution directory that holds this script;
#   writes only inside a trap-cleaned temp dir.
#
# Exit codes
#   0  every control and every mutation behaved as required
#   1  at least one mutation survived, or a golden-FALSE case tripped the gate
#   2  setup failure (gate not GREEN on the genuine tree, missing input, no-op mutation)
#
# Dependencies: bash, python3, awk, grep, cp, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GATE="$HERE/cm_release_gate_anchor_wired.sh"
N=298
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
for _t in python3 awk grep cp mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[mutation:release-gate] cannot determine: required tool '$_t' missing" >&2; exit 2; }
done
[ -f "$GATE" ] || { echo "[mutation:release-gate] SETUP FAILURE: gate missing: $GATE" >&2; exit 2; }

TMPD="$(mktemp -d)" || exit 2
trap 'rm -rf "${TMPD:?}"' EXIT
BASE="$TMPD/base"; W="$TMPD/work"; PY="$TMPD/mut.py"
RESULT=0; NRED=0; NGF=0
say() { printf '[mutation:release-gate] %s\n' "$*"; }
quiet_say() { [ "$QUIET" = 1 ] || say "$@"; }

FILES=(
    Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md
    constitution_index.yaml
    groups/project-lifecycle-and-release.md
    "progressive/rules/11.4.$N.md" progressive/catalog.json
    scripts/gates/covenant_propagation_anchors.tsv
    "scripts/gates/cm_covenant_114_${N}_propagation.sh"
    "scripts/gates/cm_covenant_114_${N}_propagation_mutation_test.sh"
    scripts/gates/rule_seam_bindings.tsv
    scripts/gates/gate_ledger_deferrals.tsv
    scripts/gates/cm_release_gate_anchor_wired.sh
    scripts/gates/cm_release_gate_anchor_wired_mutation_test.sh
    scripts/post_update_hook.sh
)
mkdir -p "$BASE"
for f in "${FILES[@]}"; do
    [ -f "$ROOT/$f" ] || { say "SETUP FAILURE: input missing: $f"; exit 2; }
    (cd "$ROOT" && cp --parents "$f" "$BASE/") || { say "SETUP FAILURE: copy failed: $f"; exit 2; }
done

# ── mutation operators (python; every operator fails loudly on a no-op) ──────
cat >"$PY" <<'PYEOF'
import re, sys
cmd, path = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
raw = open(path, encoding='utf-8').read()
lines = raw.split('\n')

def canon_range(n):
    pat = re.compile(r'^### §11\.4\.%s( |$)' % re.escape(str(n)))
    start = None
    for i, l in enumerate(lines):
        if start is None:
            if pat.match(l):
                start = i
        elif l.startswith('### §') or l.startswith('## '):
            return start, i
    return (start, len(lines)) if start is not None else None

def carrier_range(n):
    st = re.compile(r'^(\*\*|### |- )§11\.4\.%s([^0-9]|$)' % re.escape(str(n)))
    gen = re.compile(r'^(\*\*|### |- )§11\.4\.[0-9]|^## ')
    start = None
    for i, l in enumerate(lines):
        if start is None:
            if st.match(l):
                start = i
        elif gen.match(l):
            return start, i
    return (start, len(lines)) if start is not None else None

def need(rng, what):
    if rng is None:
        sys.stderr.write('NOOP: range not found: %s\n' % what); sys.exit(3)
    return rng

def finish(new):
    if new == raw:
        sys.stderr.write('NOOP: mutation did not change the file\n'); sys.exit(3)
    open(path, 'w', encoding='utf-8').write(new)

if cmd == 'block-sub':
    n, old, new = args
    a, b = need(canon_range(n), 'canon ' + n)
    text = '\n'.join(lines[a:b])
    if old not in text:
        sys.stderr.write('NOOP: %r not in block %s\n' % (old, n)); sys.exit(3)
    lines[a:b] = text.replace(old, new).split('\n')
    finish('\n'.join(lines))
elif cmd == 'block-resub':
    n, rx, new = args
    a, b = need(canon_range(n), 'canon ' + n)
    text = '\n'.join(lines[a:b])
    out, k = re.subn(rx, new, text, flags=re.M)
    if k == 0:
        sys.stderr.write('NOOP: /%s/ not in block %s\n' % (rx, n)); sys.exit(3)
    lines[a:b] = out.split('\n')
    finish('\n'.join(lines))
elif cmd == 'block-append':
    n, text = args
    a, b = need(canon_range(n), 'canon ' + n)
    lines[b:b] = ['', text]
    finish('\n'.join(lines))
elif cmd == 'carrier-sub':
    n, old, new = args
    a, b = need(carrier_range(n), 'carrier ' + n)
    text = '\n'.join(lines[a:b])
    if old not in text:
        sys.stderr.write('NOOP: %r not in carrier block %s\n' % (old, n)); sys.exit(3)
    lines[a:b] = text.replace(old, new).split('\n')
    finish('\n'.join(lines))
elif cmd == 'del-carrier':
    a, b = need(carrier_range(args[0]), 'carrier ' + args[0])
    del lines[a:b]
    finish('\n'.join(lines))
elif cmd == 'dup-carrier':
    a, b = need(carrier_range(args[0]), 'carrier ' + args[0])
    blk = lines[a:b]
    while blk and blk[-1] == '':
        blk.pop()
    base = raw.rstrip('\n')
    finish(base + '\n\n' + '\n'.join(blk) + '\n')
elif cmd == 'file-sub':
    old, new = args
    if old not in raw:
        sys.stderr.write('NOOP: %r not in file\n' % old); sys.exit(3)
    finish(raw.replace(old, new))
elif cmd == 'file-resub':
    rx, new = args
    out, k = re.subn(rx, new, raw, flags=re.M)
    if k == 0:
        sys.stderr.write('NOOP: /%s/ not in file\n' % rx); sys.exit(3)
    finish(out)
elif cmd == 'del-lines':
    rx = re.compile(args[0])
    kept = [l for l in lines if not rx.search(l)]
    if len(kept) == len(lines):
        sys.stderr.write('NOOP: no line matched /%s/\n' % args[0]); sys.exit(3)
    finish('\n'.join(kept))
elif cmd == 'append':
    finish(raw.rstrip('\n') + '\n' + args[0] + '\n')
else:
    sys.stderr.write('unknown operator %s\n' % cmd); sys.exit(2)
PYEOF

mut() { # mut <operator> <relative file> <args...>  (operates on the scratch tree)
    local op="$1" rel="$2"; shift 2
    python3 "$PY" "$op" "$W/$rel" "$@" || { say "SETUP FAILURE: operator '$op $rel' failed (a no-op mutation is a test bug)"; exit 2; }
}
fresh() { rm -rf "${W:?}"; cp -a "$BASE" "$W" || { say "SETUP FAILURE: scratch copy failed"; exit 2; }; }
run_gate() { bash "$GATE" --root "$W" 2>&1; }

# expect_red <label> <exact failing line>
expect_red() {
    local label="$1" line="$2" out rc
    out="$(run_gate)"; rc=$?
    if [ "$rc" -ne 1 ]; then say "MUTATION SURVIVED [$label]: gate exit $rc, expected 1"; RESULT=1; return; fi
    if ! grep -F -x -q -- "$line" <<<"$out"; then
        say "[$label]: gate failed (exit 1) but did NOT name the check: $line"; RESULT=1; return
    fi
    NRED=$((NRED + 1)); quiet_say "RED flip: $label"
}
# expect_green <label>   (golden-FALSE / control: must still PASS)
expect_green() {
    local label="$1" out rc
    out="$(run_gate)"; rc=$?
    if [ "$rc" -ne 0 ]; then say "GOLDEN-FALSE TRIPPED [$label]: gate exit $rc on a change that must not matter"; printf '%s\n' "$out" | tail -n 8; RESULT=1; return; fi
    NGF=$((NGF + 1)); quiet_say "GREEN kept: $label"
}
# expect_blind <label> [gate-path]
expect_blind() {
    local label="$1" g="${2:-$GATE}" out rc
    out="$(bash "$g" --root "$W" 2>&1)"; rc=$?
    if [ "$rc" -ne 2 ]; then say "BLIND CASE SURVIVED [$label]: exit $rc, expected 2"; RESULT=1; return; fi
    if ! grep -F -q -- "BLIND" <<<"$out"; then say "[$label]: exit 2 but no BLIND message"; RESULT=1; return; fi
    NRED=$((NRED + 1)); quiet_say "BLIND asserted: $label"
}

# ── lists kept in lock-step with the gate source ─────────────────────────────
XREFS="6 17 35 40 50 66 108 114 115 118 135 151 185 200 227 236 248 251 262 264 289 290 292 293"
REFINED="293"
FLAGS=(--deploy-without-live-run --tag-without-live-run --emulator-counts-as-target --partial-suite-release --reuse-other-product-verdict --no-hardware-is-skip --deploy-blocked-product --release-covers-blocked-product)
STATES="RELEASABLE BLOCKED-NO-HARDWARE BLOCKED-NO-BASELINE REFUSED-REGRESSED"
grep -F -q -- "for n in $XREFS; do" "$GATE" || { say "SETUP FAILURE: gate cross-reference list differs from this test's list"; exit 2; }
grep -F -q -- "REFINED_IDS=\"$REFINED\"" "$GATE" || { say "SETUP FAILURE: gate refined-anchor list differs from this test's list"; exit 2; }
grep -F -q -- "for st in $STATES; do" "$GATE" || { say "SETUP FAILURE: gate gate-state list differs from this test's list"; exit 2; }
for fl in "${FLAGS[@]}"; do
    grep -F -q -- "$fl" "$GATE" || { say "SETUP FAILURE: gate does not list escape-hatch flag $fl"; exit 2; }
done
mapfile -t MARKERS < <(python3 - "$GATE" <<'PYEOF'
import re, shlex, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^MARKERS=\(\n(.*?)^\)', src, re.S | re.M)
for tok in shlex.split(m.group(1)):
    print(tok)
PYEOF
)
[ "${#MARKERS[@]}" -ge 40 ] || { say "SETUP FAILURE: could not parse MARKERS from the gate (${#MARKERS[@]})"; exit 2; }
mapfile -t CLAUSES < <(python3 - "$GATE" <<'PYEOF'
import re, shlex, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^CLAUSES=\(\n(.*?)^\)', src, re.S | re.M)
for tok in shlex.split(m.group(1)):
    print(tok)
PYEOF
)
[ "${#CLAUSES[@]}" -eq 7 ] || { say "SETUP FAILURE: could not parse CLAUSES from the gate (${#CLAUSES[@]})"; exit 2; }

# mk PREFIX -> the full gate marker that starts with PREFIX (the long load-bearing spans are not repeated here)
mk() { local m; for m in "${MARKERS[@]}"; do case "$m" in "$1"*) printf '%s' "$m"; return 0 ;; esac; done; printf 'NO-MARKER-STARTS-WITH:%s' "$1"; }

# ── GREEN control ────────────────────────────────────────────────────────────
fresh
expect_green "GREEN control: genuine tree"

# ── golden-FALSE: changes that must not trip the gate (§11.4.201(1)) ─────────
fresh; mut block-append Constitution.md 286 'See §11.4.298(D) for the gate state; this mid-body citation is not a block.'
expect_green "mid-body citation of §11.4.298 inside another anchor's block is not a second block"
fresh; mut append CLAUDE.md '## Project-specific section'; mut append CLAUDE.md 'Project text after the mirror block.'
expect_green "an unrelated project H2 section after the CLAUDE.md block does not break the mirror check"
fresh; mut append Constitution.md '### §11.4.2980 — prefix-collision decoy heading'
expect_green "prefix-colliding heading §11.4.2980 is not counted as §11.4.298"
fresh; mut block-sub Constitution.md "$N" 'Honest boundary (§11.4.6).' 'Honest boundary (§11.4.6).  '
expect_green "whitespace-only change inside the block keeps the gate green"

# ── RED: canon block markers, clause headings, flags, cross-references ───────
for m in "${MARKERS[@]}"; do
    fresh; mut block-sub Constitution.md "$N" "$m" '@@'
    expect_red "marker removed: $m" "FAIL  canon: block carries marker '$m'"
done
for c in "${CLAUSES[@]}"; do
    fresh; mut block-sub Constitution.md "$N" "$c" '(clause heading removed)'
    expect_red "clause heading removed: $c" "FAIL  canon: block carries clause heading $c"
done
for fl in "${FLAGS[@]}"; do
    fresh; mut block-sub Constitution.md "$N" "$fl" '--removed-flag'
    expect_red "escape-hatch flag removed: $fl" "FAIL  canon: block names escape-hatch flag $fl as forbidden"
done
for n in $XREFS; do
    fresh; mut block-resub Constitution.md "$N" "§11\\.4\\.$n(?![0-9])" '§11.4.X'
    expect_red "cross-reference removed: §11.4.$n" "FAIL  canon: block cites §11.4.$n"
done
SECTS="1.1"
for s in $SECTS; do
    fresh; mut block-resub Constitution.md "$N" "§${s/./\\.}(?![0-9])" "§X$s"
    expect_red "cross-reference removed: §$s" "FAIL  canon: block cites §$s"
done
for st in $STATES; do
    fresh; mut block-resub Constitution.md "$N" "^\\| \`$st\` \\|" '| (state removed) |'
    expect_red "gate-state row removed: $st" "FAIL  canon: gate-state table has a row for \`$st\`"
done
fresh; mut block-resub Constitution.md "$N" '^(\| `RELEASABLE` \|.*)$' '\1\n| `REFUSED-REGRESSED` | a fifth row | refused | refused | refused |'
expect_red "a fifth gate-state row added" "FAIL  canon: gate-state table has exactly four state rows"
fresh; mut block-resub Constitution.md "$N" '^Classification: universal' 'Classification (universal)'
expect_red "line-start Classification line removed" "FAIL  canon: block carries a line-start 'Classification: universal'"
fresh; mut block-sub Constitution.md "$N" '**Canonical authority:**' 'Canonical authority:'
expect_red "Canonical authority line removed" "FAIL  canon: block carries a Canonical authority line"
fresh; mut block-sub Constitution.md "$N" 'Non-compliance is a release blocker' 'Non-compliance is tolerated'
expect_red "non-compliance line weakened" "FAIL  canon: block carries the non-compliance release-blocker line"

# ── RED: semantic weakenings found by the independent audit of 2026-11-07 ────
fresh; mut block-sub Constitution.md "$N" '| refused | refused | refused |' '| refused | refused | allowed |'
expect_red "W6 a dev-class tag without hardware" "FAIL  canon: block carries marker '$(mk '| `BLOCKED-NO-HARDWARE` |')'"
fresh; mut block-sub Constitution.md "$N" 'verdict is `INCOMPARABLE-BASELINE-MISSING` | refused |' 'verdict is `INCOMPARABLE-BASELINE-MISSING` | allowed |'
expect_red "W6b deployment without a baseline" "FAIL  canon: block carries marker '$(mk '| `BLOCKED-NO-BASELINE` |')'"
fresh; mut block-sub Constitution.md "$N" 'verdict is `REGRESSED` | refused | refused |' 'verdict is `REGRESSED` | refused | allowed |'
expect_red "W6c release tag of a regressed build" "FAIL  canon: block carries marker '$(mk '| `REFUSED-REGRESSED` |')'"
fresh; mut block-sub Constitution.md "$N" 'An emulator, a simulator, a host-only run, a replayed or copied record, or a run on hardware of another product is never this run.' 'A host-only run or a run on hardware of another product is never this run; an emulator is acceptable when no hardware is connected.'
expect_red "W7 emulator accepted" "FAIL  canon: block carries marker 'An emulator, a simulator, a host-only run, a replayed or copied record, or a run on hardware of another product is never this run'"
fresh; mut block-sub Constitution.md "$N" '(the complete retest of §11.4.40; a subset, a spot check or the tests touched by the change is not this run)' '(the complete retest of §11.4.40, or the tests touched by the change when the full run exceeds the window)'
expect_red "W8 a subset run" "FAIL  canon: block carries marker 'a subset, a spot check or the tests touched by the change is not this run'"
fresh; mut block-sub Constitution.md "$N" 'never stand for another, even when the products share code or a build.' 'never stand for another, unless the products share a build.'
expect_red "W10 one product's verdict reused for another" "FAIL  canon: block carries marker 'never stand for another, even when the products share code or a build'"
fresh; mut block-sub Constitution.md "$N" 'it stays `BLOCKED-NO-BASELINE` (no deployment, no release tag) until the operator records' 'it may be deployed once its own live run passes, until the operator records'
expect_red "M3 a first build deployed without a baseline" "FAIL  canon: block carries marker '$(mk 'A product'"'"'s first deployable build')'"
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; mut carrier-sub "$f" "$N" 'a first build has no baseline and stays `BLOCKED-NO-BASELINE`' '@@'
    expect_red "mirror loses the first-build rule: $f" "FAIL  mirror $f: block names the first-build rule"
done

# ── RED: heading integrity, decoys and duplicates ────────────────────────────
fresh; mut file-sub Constitution.md "### §11.4.$N — Release gate per product" "#### §11.4.$N — Release gate per product"
expect_red "decoy: heading demoted, mid-body citations remain" "FAIL  canon: exactly one '### §11.4.$N' heading in Constitution.md"
fresh; mut append Constitution.md "### §11.4.$N — duplicate block"
expect_red "duplicate canon heading" "FAIL  canon: exactly one '### §11.4.$N' heading in Constitution.md"
fresh; mut append Constitution.md "**§11.4.$N — stray second block-start form.** text"
expect_red "second block-start form in canon" "FAIL  canon: exactly one §11.4.$N block-start of any form in Constitution.md (no duplicate form)"
fresh; mut file-sub Constitution.md "### §11.4.$N — Release gate per product:" "### §11.4.$N — Release notes:"
expect_red "heading no longer names 'Release gate per product'" "FAIL  canon: heading names 'Release gate per product'"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)connected target hardware" '\1any machine'
expect_red "heading no longer names 'connected target hardware'" "FAIL  canon: heading names 'connected target hardware'"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)is BLOCKED, never green" '\1is skipped'
expect_red "heading no longer names 'is BLOCKED, never green'" "FAIL  canon: heading names 'is BLOCKED, never green'"
fresh; mut block-sub Constitution.md "$N" '(User mandate, 2026-11-07)' '(User mandate)'
expect_red "heading loses the mandate date" "FAIL  canon: heading carries the mandate date 2026-11-07"

# ── RED: back-pointer in the composed anchor ─────────────────────────────────
for n in $REFINED; do
    fresh; mut block-sub Constitution.md "$n" 'Refinement note (2026-11-07, release gate)' 'Note'
    expect_red "refinement note removed from §11.4.$n" "FAIL  refined §11.4.$n: carries 'Refinement note (2026-11-07, release gate)'"
    fresh; mut block-resub Constitution.md "$n" '§11\.4\.298(?![0-9])' '§11.4.X98'
    expect_red "refinement note in §11.4.$n no longer cites §11.4.298" "FAIL  refined §11.4.$n: refinement note cites §11.4.298"
done
fresh; mut block-sub Constitution.md 293 'amends clause (F) at exactly one point' 'amends clause (F)'
expect_red "the §11.4.293 note no longer bounds the amendment to one point" "FAIL  refined §11.4.293: the note states the one amended point"
fresh; mut block-resub Constitution.md 293 '(release gate\)\.\*\*.*?)gets no tag of any class' '\1may be tagged'
expect_red "the §11.4.293 note no longer refuses every tag without the live run" "FAIL  refined §11.4.293: the note names 'no tag of any class'"
fresh; mut block-sub Constitution.md 293 'clauses (A) to (E) and (G) are unchanged' 'other clauses may change'
expect_red "the §11.4.293 note no longer keeps the other clauses" "FAIL  refined §11.4.293: the note keeps the other clauses"

# ── RED: the four mirrors ────────────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; mut del-carrier "$f" "$N"
    expect_red "mirror block deleted: $f" "FAIL  mirror $f: exactly one §11.4.$N block-start"
    fresh; mut dup-carrier "$f" "$N"
    expect_red "mirror block duplicated: $f" "FAIL  mirror $f: exactly one §11.4.$N block-start"
    fresh; mut carrier-sub "$f" "$N" '`BLOCKED-NO-BASELINE`, `REFUSED-REGRESSED`' '@@'
    expect_red "mirror loses the four gate states: $f" "FAIL  mirror $f: block names the four gate states"
    fresh; mut carrier-sub "$f" "$N" 'connected while the run executes and identified from the target' '@@'
    expect_red "mirror loses the connected-hardware rule: $f" "FAIL  mirror $f: block names the connected-hardware rule"
    fresh; mut carrier-sub "$f" "$N" "one product's verdict never stands for another" '@@'
    expect_red "mirror loses the per-product rule: $f" "FAIL  mirror $f: block names the per-product rule"
    fresh; mut carrier-sub "$f" "$N" 'no tag of any class without the live run' '@@'
    expect_red "mirror loses the one-point amendment: $f" "FAIL  mirror $f: block names the one-point amendment of §11.4.293(F)"
    fresh; mut carrier-sub "$f" "$N" 'CM-RELEASE-GATE-ANCHOR-WIRED' '@@'
    expect_red "mirror loses the gate token: $f" "FAIL  mirror $f: block names gate CM-RELEASE-GATE-ANCHOR-WIRED"
    fresh; mut carrier-sub "$f" "$N" "[\`Constitution.md\`](Constitution.md) §11.4.$N" '@@'
    expect_red "mirror loses the canonical pointer: $f" "FAIL  mirror $f: block points at Constitution.md §11.4.$N"
    fresh; rm -f "${W:?}/${f:?}"
    expect_red "mirror file missing: $f" "FAIL  mirror $f: file missing"
done

# ── RED: generated artefacts ─────────────────────────────────────────────────
fresh; mut file-resub constitution_index.yaml "^- id: 11\\.4\\.$N\$" "- id: 11.4.$N-removed"
expect_red "index entry for 11.4.$N gone" "FAIL  index: constitution_index.yaml has an entry for 11.4.$N"
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  propagation_gate: )CM-COVENANT-114-$N-PROPAGATION" '\1none'
expect_red "index propagation_gate wrong" "FAIL  index: 11.4.$N propagation_gate is CM-COVENANT-114-$N-PROPAGATION"
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  group: )project-lifecycle-and-release" '\1testing-and-tdd'
expect_red "index group wrong" "FAIL  index: 11.4.$N group is project-lifecycle-and-release"
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  classification: )universal" '\1project'
expect_red "index classification wrong" "FAIL  index: 11.4.$N classification is universal"
fresh; mut file-sub groups/project-lifecycle-and-release.md "### §11.4.$N " "#### §11.4.$N "
expect_red "group file loses the block" "FAIL  group: project-lifecycle-and-release.md carries exactly one §11.4.$N block"
fresh; rm -f "${W:?}/groups/project-lifecycle-and-release.md"
expect_red "group file missing" "FAIL  group: groups/project-lifecycle-and-release.md missing"
fresh; rm -f "${W:?}/progressive/rules/11.4.$N.md"
expect_red "progressive rule file missing" "FAIL  progressive: rules/11.4.$N.md exists"
fresh; mut del-lines progressive/catalog.json "\"id\":\"§11\\.4\\.$N\""
expect_red "catalog entry gone" "FAIL  progressive: catalog.json lists §11.4.$N"
fresh; mut file-sub progressive/catalog.json "\"file\":\"progressive/rules/11.4.$N.md\"" '"file":"progressive/rules/missing.md"'
expect_red "catalog file pointer wrong" "FAIL  progressive: catalog.json points at rules/11.4.$N.md"

# ── RED: seams ───────────────────────────────────────────────────────────────
fresh; mut del-lines scripts/gates/covenant_propagation_anchors.tsv "^CM-COVENANT-114-$N-PROPAGATION"
expect_red "data-pack row removed" "FAIL  seam: propagation data pack has the CM-COVENANT-114-$N-PROPAGATION<TAB>11.4.$N row"
fresh; mut file-sub scripts/gates/covenant_propagation_anchors.tsv $'CM-COVENANT-114-298-PROPAGATION\t11.4.298' $'CM-COVENANT-114-298-PROPAGATION\t11.4.293'
expect_red "data-pack row points at the wrong anchor" "FAIL  seam: propagation data pack has the CM-COVENANT-114-$N-PROPAGATION<TAB>11.4.$N row"
fresh; rm -f "${W:?}/scripts/gates/cm_covenant_114_${N}_propagation.sh"
expect_red "generated propagation gate missing" "FAIL  seam: generated propagation gate cm_covenant_114_${N}_propagation.sh exists"
fresh; rm -f "${W:?}/scripts/gates/cm_covenant_114_${N}_propagation_mutation_test.sh"
expect_red "generated propagation mutation test missing" "FAIL  seam: generated propagation mutation test exists"
fresh; mut del-lines scripts/gates/rule_seam_bindings.tsv "^11\\.4\\.$N"$'\t'
expect_red "seam binding row removed" "FAIL  seam: rule_seam_bindings.tsv binds 11.4.$N to a seam"
# The deferred gate names are read from the registry at run time (never written here as literals).
OWED_IDS="OWED-GATE-185"
for ow in $OWED_IDS; do
    dg="$(awk -F '\t' -v o="$ow" '$2 == o { print $1; exit }' "$BASE/scripts/gates/gate_ledger_deferrals.tsv")"
    case "$dg" in CM-?*) ;; *) say "SETUP FAILURE: no deferral row for $ow in the genuine registry"; exit 2 ;; esac
    fresh; mut del-lines scripts/gates/gate_ledger_deferrals.tsv "^$dg"$'\t'
    expect_red "deferral row $ow removed" "FAIL  seam: gate_ledger_deferrals.tsv has exactly one $ow row"
    fresh; mut file-sub scripts/gates/gate_ledger_deferrals.tsv "$dg"$'\t'"$ow" "$dg"$'\t'"OWED-GATE-001"
    expect_red "deferral row $ow carries the wrong id" "FAIL  seam: gate_ledger_deferrals.tsv has exactly one $ow row"
    fresh; mut append scripts/gates/gate_ledger_deferrals.tsv "CM-DUPLICATE-ROW"$'\t'"$ow"$'\t'"duplicate"
    expect_red "deferral id $ow registered twice" "FAIL  seam: gate_ledger_deferrals.tsv has exactly one $ow row"
    fresh; mut file-sub scripts/gates/gate_ledger_deferrals.tsv "$dg"$'\t'"$ow" "$dg-RENAMED"$'\t'"$ow"
    expect_red "deferral row $ow names a gate the canon does not name" "FAIL  seam: the $ow deferral names a CM-* gate that the §11.4.$N block names"
    fresh; mut block-sub Constitution.md "$N" "$dg" 'CM-SOMETHING-ELSE'
    expect_red "canon block no longer names the $ow gate" "FAIL  seam: the $ow deferral names a CM-* gate that the §11.4.$N block names"
    fresh; mut file-sub scripts/gates/gate_ledger_deferrals.tsv "$dg"$'\t'"$ow" "not-a-gate"$'\t'"$ow"
    expect_red "deferral row $ow names no CM-* gate" "FAIL  seam: the $ow deferral names a CM-* gate that the §11.4.$N block names"
done
fresh; rm -f "${W:?}/scripts/gates/cm_release_gate_anchor_wired_mutation_test.sh"
expect_red "this gate's own mutation test missing" "FAIL  seam: this gate's paired mutation test exists"
fresh; mut file-sub scripts/post_update_hook.sh 'cm_release_gate_anchor_wired.sh' 'cm_removed_gate.sh'
expect_red "hook no longer runs the gate" "FAIL  seam: post_update_hook.sh runs this gate on every pull"
fresh; mut file-sub scripts/post_update_hook.sh 'CM-RELEASE-GATE-ANCHOR-WIRED' 'CM-REMOVED'
expect_red "hook no longer names the token" "FAIL  seam: post_update_hook.sh names the token CM-RELEASE-GATE-ANCHOR-WIRED"
fresh; rm -f "${W:?}/scripts/post_update_hook.sh"
expect_red "hook file missing" "FAIL  seam: scripts/post_update_hook.sh missing"

# ── text pins (audit 2, F1): each marker-preserving weakening of audit 2 is named by its pin ─
fresh; mut block-sub Constitution.md 298 '; for a product in any other state it is refused, and no text describes it as covering that product.' '; a product in another state may ride along when the release note marks it partial.'
expect_red 'audit-2 R1-multiproduct-ride-along keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 298 'the target identity read from the hardware, ' ''
expect_red 'audit-2 R2-record-no-target-identity keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 298 'deterministically (§11.4.50) and LIVE (§11.4.289),' 'LIVE (§11.4.289),'
expect_red 'audit-2 R3-not-deterministic keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 298 'A missing baseline is cured only as §11.4.293(C) states;' 'A missing baseline is cured by the operator'"'"'s acceptance of the current build;'
expect_red 'audit-2 R4-baseline-by-acceptance keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 298 'There is no fifth state and no default state.' 'There is no fifth state and no default state. A product whose hardware is temporarily unavailable may reuse its last `RELEASABLE` state.'
expect_red 'audit-2 R5-additive-reuse-last-state keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 298 'A consumer rule that lets a dev tag be cut at any time yields to this point:' 'A consumer rule that lets a dev tag be cut at any time prevails over this point:'
expect_red 'audit-2 R6-consumer-devtag-prevails keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 298 'or handing it to manual QA (§11.4.185, §11.4.236) or to a user' 'or handing it to a user'
expect_red 'audit-2 R7-manual-QA-not-deployment keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 298 'no existing test is dropped, skipped or quarantined out of the comparison to let a build pass' 'no existing test is dropped, skipped or quarantined out of the comparison, unless it is marked flaky, to let a build pass'
expect_red 'audit-2 R8-flaky-may-be-dropped keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.298 block of Constitution.md matches PIN_CANON'
fresh; mut block-sub Constitution.md 293 'a build without a completed live run on connected hardware of its product gets no tag of any class.' 'a build without a completed live run on connected hardware of its product gets no release tag.'
expect_red 'audit-2 R9-CONTROL-293note-release-tag-only keeps every marker, caught by its pin' 'FAIL  pinned: the §11.4.293 refinement note (2026-11-07, release gate) matches PIN_NOTE_293'
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; mut carrier-sub "$f" 298 'an emulator, a host run, a replayed record or another product'"'"'s hardware is never this run' 'a host run, a replayed record or another product'"'"'s hardware is never this run (an emulator may stand in when no board is attached)'
    expect_red "audit-2 R10-carriers-emulator-ok keeps every marker, caught by its pin: $f" "FAIL  pinned: mirror $f §11.4.298 block matches PIN_CARRIER"
done
# golden-FALSE: whitespace-only edits inside a pinned mirror block and a pinned note keep the gate green
fresh; mut carrier-sub CLAUDE.md "$N" 'Classification: universal (§11.4.17).' 'Classification:   universal (§11.4.17).'
expect_green "whitespace-only change inside a pinned mirror block keeps the gate green"
fresh; mut block-sub Constitution.md 293 'makes the verdict of this anchor the condition' 'makes the verdict  of this anchor  the condition'
expect_green "whitespace-only change inside a pinned refinement note keeps the gate green"
# audit 3 (B1): the release-gate note is pinned as its whole paragraph, so a sentence on the line after it (or on the
# line before it) with no blank line between is caught by its pin; the note re-wrapped across lines is not
fresh; mut block-sub Constitution.md 293 'and clauses (A) to (E) and (G) are unchanged.' 'and clauses (A) to (E) and (G) are unchanged.
A consumer dev tag may skip this gate.'
expect_red "audit-3 B1 continuation line after the release-gate note, caught by its pin" "FAIL  pinned: the §11.4.293 refinement note (2026-11-07, release gate) matches PIN_NOTE_293"
fresh; mut block-sub Constitution.md 293 '
**Refinement note (2026-11-07, release gate).**' '
A consumer dev tag may skip this gate.
**Refinement note (2026-11-07, release gate).**'
expect_red "audit-3 B1 lead-in line directly before the release-gate note, caught by its pin" "FAIL  pinned: the §11.4.293 refinement note (2026-11-07, release gate) matches PIN_NOTE_293"
fresh; mut block-sub Constitution.md 293 'makes the verdict of this anchor the condition' 'makes the verdict
of this anchor the condition'
expect_green "the release-gate note re-wrapped across two lines (a whitespace-only change) keeps the gate green"
# --print-digests reads the texts the pins check: on the genuine tree it prints exactly the pinned values
fresh; PD="$(bash "$GATE" --root "$W" --print-digests 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && python3 - "$GATE" "$PD" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
pins = dict(re.findall(r"^(PIN_[A-Z0-9_]+)='([0-9a-f]{64})'", src, re.M))
out = re.findall(r"^(PIN_[A-Z0-9_]+)='([0-9a-f]{64})'", sys.argv[2], re.M)
sys.exit(0 if pins and out and all(pins.get(k) == v for k, v in out) and {k for k, _ in out} == set(pins) else 1)
PYEOF
then NGF=$((NGF + 1)); quiet_say "GREEN kept: --print-digests on the genuine tree prints the pinned values"
else say "PRINT-DIGESTS MISMATCH: exit $rc"; printf '%s\n' "$PD" | head -n 4; RESULT=1; fi
# re-pinned: after a reviewed text change, a gate copy re-pinned from --print-digests passes again
fresh; mut block-sub Constitution.md "$N" 'There is no fifth state and no default state.' 'There is no fifth state and no default state. A product whose hardware is temporarily unavailable may reuse its last `RELEASABLE` state.'
G2="$W/scripts/gates/${GATE##*/}"
NEWPIN="$(bash "$G2" --root "$W" --print-digests | sed -n "s/^PIN_CANON='\([0-9a-f]*\)'.*/\1/p")"
python3 - "$G2" "$NEWPIN" <<'PYEOF' || { say "SETUP FAILURE: could not re-pin the gate copy"; exit 2; }
import re, sys
p, v = sys.argv[1], sys.argv[2]
t = open(p, encoding='utf-8').read()
t2, k = re.subn(r"^PIN_CANON='[0-9a-f]{64}'", "PIN_CANON='%s'" % v, t, count=1, flags=re.M)
if k != 1 or t2 == t or len(v) != 64:
    sys.exit(3)
open(p, 'w', encoding='utf-8').write(t2)
PYEOF
out="$(bash "$G2" --root "$W" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then NGF=$((NGF + 1)); quiet_say "GREEN kept: a gate copy re-pinned from --print-digests passes the reviewed text change"
else say "RE-PIN CASE FAILED: exit $rc"; printf '%s\n' "$out" | grep FAIL | head -n 4; RESULT=1; fi
# gate mutant: with the pin check disabled in a copy, the same change passes; so the pin check is what names it
fresh; mut block-sub Constitution.md "$N" 'There is no fifth state and no default state.' 'There is no fifth state and no default state. A product whose hardware is temporarily unavailable may reuse its last `RELEASABLE` state.'
G3="$W/scripts/gates/pins_off_gate.sh"; cp "$GATE" "$G3"
python3 - "$G3" <<'PYEOF' || { say "SETUP FAILURE: could not disable the pin check in the copy"; exit 2; }
import sys
p = sys.argv[1]; t = open(p, encoding='utf-8').read()
old = 'if [ -n "$cur" ] && [ "$cur" = "$2" ]; then pass "$1"'
if t.count(old) != 1:
    sys.exit(3)
open(p, 'w', encoding='utf-8').write(t.replace(old, 'if true; then pass "$1"'))
PYEOF
bash "$G3" --root "$W" >/dev/null 2>&1; rc3=$?; bash "$GATE" --root "$W" >/dev/null 2>&1; rc1=$?
if [ "$rc3" -eq 0 ] && [ "$rc1" -eq 1 ]; then NRED=$((NRED + 1)); quiet_say "RED flip: the pin check alone names audit-2 R5 (pins off: exit 0; gate: exit 1)"
else say "PIN MUTANT SURVIVED OR MISWIRED: pins-off copy exit $rc3, gate exit $rc1 (expected 0 and 1)"; RESULT=1; fi
# BLIND: a digest that no longer normalises whitespace fails its control needle
fresh; cp "$GATE" "$W/scripts/gates/broken_digest.sh"
python3 - "$W/scripts/gates/broken_digest.sh" <<'PYEOF' || { say "SETUP FAILURE: could not break the digest copy"; exit 2; }
import sys
p = sys.argv[1]; t = open(p, encoding='utf-8').read()
old = """digest() { awk '{ for (i = 1; i <= NF; i++) printf "%s", $i }' | "${SHA[@]}" | awk '{ print $1 }'; }"""
if t.count(old) != 1:
    sys.exit(3)
open(p, 'w', encoding='utf-8').write(t.replace(old, """digest() { "${SHA[@]}" | awk '{ print $1 }'; }"""))
PYEOF
expect_blind "pin digest that keeps whitespace -> the digest control needle refuses (BLIND)" "$W/scripts/gates/broken_digest.sh"
# BLIND: a note extractor that reads only the marker line (the audit-3 B1 defect) fails its control needle
fresh; cp "$GATE" "$W/scripts/gates/broken_note.sh"
python3 - "$W/scripts/gates/broken_note.sh" <<'PYEOF' || { say "SETUP FAILURE: could not break the note extractor copy"; exit 2; }
import sys
p = sys.argv[1]; t = open(p, encoding='utf-8').read()
old = r'{ buf = buf $0 "\n"; if (index($0, m)) hit = 1 }'
if t.count(old) != 1:
    sys.exit(3)
open(p, 'w', encoding='utf-8').write(t.replace(old, r'{ if (index($0, m)) { buf = buf $0 "\n"; hit = 1 } }'))
PYEOF
expect_blind "note extractor that reads only the marker line -> the note paragraph control needle refuses (BLIND)" "$W/scripts/gates/broken_note.sh"

# ── BLIND: an untrustworthy instrument never reports PASS ────────────────────
fresh; cp "$GATE" "$W/scripts/gates/broken_gate.sh"
python3 - "$W/scripts/gates/broken_gate.sh" <<'PYEOF' || { say "SETUP FAILURE: could not break the extractor copy"; exit 2; }
import sys
p = sys.argv[1]
out, hit = [], 0
for l in open(p, encoding='utf-8').read().split('\n'):
    if l.startswith("HEAD_PREFIX='### §11"):
        l = l.replace('§11', '§99'); hit += 1
    out.append(l)
if hit != 1:
    sys.exit(3)
open(p, 'w', encoding='utf-8').write('\n'.join(out))
PYEOF
expect_blind "heading extractor broken -> the control needle refuses (BLIND)" "$W/scripts/gates/broken_gate.sh"
fresh; rm -f "${W:?}/Constitution.md"
expect_blind "Constitution.md missing"
fresh; mut file-sub Constitution.md '### §11.4.286 ' '#### §11.4.286 '
expect_blind "real-file control needle (§11.4.286 heading) lost"

if [ "$RESULT" -eq 0 ]; then
    say "PASS: $NRED RED/BLIND cases and $NGF GREEN cases (1 control + $((NGF - 1)) golden-FALSE) behaved as required — cm_release_gate_anchor_wired.sh genuinely discriminates"
else
    say "FAIL: at least one mutation survived or a golden-FALSE case tripped the gate"
fi
exit "$RESULT"
