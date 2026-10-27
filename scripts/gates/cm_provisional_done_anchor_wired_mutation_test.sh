#!/usr/bin/env bash
# cm_provisional_done_anchor_wired_mutation_test.sh — paired §1.1 mutation test for CM-PROVISIONAL-DONE-ANCHOR-WIRED
#
# Purpose
#   Proves cm_provisional_done_anchor_wired.sh genuinely discriminates, instead of
#   passing whatever it is shown. It copies the files the gate reads into a scratch
#   tree and runs the gate:
#     * GREEN control    the unmodified copy MUST pass (exit 0);
#     * golden-FALSE     changes that must NOT trip the gate (a mid-body citation of
#                        §11.4.290 elsewhere, an unrelated project section after a
#                        mirror block, a prefix-colliding decoy heading §11.4.2900)
#                        MUST still pass — a gate that refuses them is a false-positive
#                        refusal (§11.4.201(1));
#     * RED mutations    every required marker phrase, every escape-hatch flag, every
#                        cross-reference, every back-pointer in the five refined
#                        anchors, every mirror, the skill, the index entry, the group
#                        file, the progressive rule file and catalog, the data-pack
#                        row, the generated wrapper, the hook binding, a duplicated
#                        canon block, a stray second block-start form and a
#                        decoy-heading swap is removed or broken ONE AT A TIME, and the
#                        gate MUST exit 1 and name that exact failed check;
#     * BLIND            a broken block extractor and a missing Constitution.md MUST
#                        exit 2 (never a silent PASS).
#   Each mutation operator asserts it really changed the file; a no-op mutation is a
#   test bug (exit 2), never a green.
#
# Usage
#   cm_provisional_done_anchor_wired_mutation_test.sh [--quiet]
#   Reads the real files from the constitution directory that holds this script;
#   writes only inside a trap-cleaned temp dir.
#
# Exit codes
#   0  every control and every mutation behaved as required
#   1  at least one mutation survived, or a golden-FALSE case tripped the gate
#   2  setup failure (gate not GREEN on the genuine tree, missing input, no-op mutation)
#
# Dependencies: bash, python3, awk, grep, cp, mktemp.
set -u -o pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GATE="$HERE/cm_provisional_done_anchor_wired.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
for _t in python3 awk grep cp mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[mutation:pdone] cannot determine: required tool '$_t' missing" >&2; exit 2; }
done
[ -f "$GATE" ] || { echo "[mutation:pdone] SETUP FAILURE: gate missing: $GATE" >&2; exit 2; }

TMPD="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMPD"' EXIT
BASE="$TMPD/base"; W="$TMPD/work"; PY="$TMPD/mut.py"
RESULT=0; NRED=0; NGF=0
say() { printf '[mutation:pdone] %s\n' "$*"; }
quiet_say() { [ "$QUIET" = 1 ] || say "$@"; }

FILES=(
    Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md
    skills/workable-item-lifecycle/SKILL.md
    constitution_index.yaml
    groups/workable-items-and-tracking.md
    progressive/rules/11.4.290.md progressive/catalog.json
    scripts/gates/covenant_propagation_anchors.tsv
    scripts/gates/cm_covenant_114_290_propagation.sh
    scripts/gates/cm_covenant_114_290_propagation_mutation_test.sh
    scripts/gates/cm_provisional_done_anchor_wired.sh
    scripts/gates/cm_provisional_done_anchor_wired_mutation_test.sh
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
fresh() { rm -rf "$W"; cp -a "$BASE" "$W" || { say "SETUP FAILURE: scratch copy failed"; exit 2; }; }
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
XREFS="1 5 6 7 15 33 34 55 108 115 123 135 189 197 201 226 227 236 262 271"
REFINED="15 33 108 123 226"
grep -F -q -- "for n in $XREFS; do" "$GATE" || { say "SETUP FAILURE: gate cross-reference list differs from this test's list"; exit 2; }
grep -F -q -- "for n in $REFINED; do" "$GATE" || { say "SETUP FAILURE: gate refined-anchor list differs from this test's list"; exit 2; }
mapfile -t MARKERS < <(python3 - "$GATE" <<'PYEOF'
import re, shlex, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^MARKERS=\(\n(.*?)^\)', src, re.S | re.M)
for tok in shlex.split(m.group(1)):
    print(tok)
PYEOF
)
[ "${#MARKERS[@]}" -ge 20 ] || { say "SETUP FAILURE: could not parse MARKERS from the gate (${#MARKERS[@]})"; exit 2; }
FLAGS=(--provisional-counts-as-verified --skip-verification-job --silent-reopen --hide-provisional-in-changelog --promote-on-timeout --unlabelled-done-count)

# ── GREEN control ────────────────────────────────────────────────────────────
fresh
expect_green "GREEN control: genuine tree"

# ── golden-FALSE: changes that must not trip the gate (§11.4.201(1)) ─────────
fresh; mut block-append Constitution.md 286 'See §11.4.290(A) for provisional done; this mid-body citation is not a block.'
expect_green "mid-body citation of §11.4.290 inside another anchor's block is not a second block"
fresh; mut append CLAUDE.md '## Project-specific section'; mut append CLAUDE.md 'Project text after the mirror block.'
expect_green "an unrelated project H2 section after the CLAUDE.md block does not break the mirror check"
fresh; mut append Constitution.md '### §11.4.2900 — prefix-collision decoy heading'
expect_green "prefix-colliding heading §11.4.2900 is not counted as §11.4.290"
fresh; mut block-sub Constitution.md 290 'Honest boundary (§11.4.6).' 'Honest boundary (§11.4.6).  '
expect_green "whitespace-only change inside the block keeps the gate green"

# ── RED: canon block markers, flags, cross-references ────────────────────────
for m in "${MARKERS[@]}"; do
    fresh; mut block-sub Constitution.md 290 "$m" '@@'
    expect_red "marker removed: $m" "FAIL  canon: block carries marker '$m'"
done
for fl in "${FLAGS[@]}"; do
    fresh; mut block-sub Constitution.md 290 "$fl" '--removed-flag'
    expect_red "escape-hatch flag removed: $fl" "FAIL  canon: block names escape-hatch flag $fl as forbidden"
done
for n in $XREFS; do
    fresh; mut block-resub Constitution.md 290 "§11\\.4\\.$n(?![0-9])" '§11.4.X'
    expect_red "cross-reference removed: §11.4.$n" "FAIL  canon: block cites §11.4.$n"
done
fresh; mut block-resub Constitution.md 290 '§7\.1(?![0-9])' '§X7.1'
expect_red "cross-reference removed: §7.1" "FAIL  canon: block cites §7.1"
fresh; mut block-resub Constitution.md 290 '§9(?![0-9.])' '§X9'
expect_red "cross-reference removed: §9" "FAIL  canon: block cites §9"
fresh; mut block-resub Constitution.md 290 '§12(?![0-9.])' '§X12'
expect_red "cross-reference removed: §12" "FAIL  canon: block cites §12"
fresh; mut block-resub Constitution.md 290 '^Classification: universal' 'Classification (universal)'
expect_red "line-start Classification line removed" "FAIL  canon: block carries a line-start 'Classification: universal'"
fresh; mut block-sub Constitution.md 290 '**Canonical authority:**' 'Canonical authority:'
expect_red "Canonical authority line removed" "FAIL  canon: block carries a Canonical authority line"
fresh; mut block-sub Constitution.md 290 'Non-compliance is a release blocker' 'Non-compliance is tolerated'
expect_red "non-compliance line weakened" "FAIL  canon: block carries the non-compliance release-blocker line"

# ── RED: heading integrity, decoys and duplicates ────────────────────────────
fresh; mut file-sub Constitution.md '### §11.4.290 — Optimistic' '#### §11.4.290 — Optimistic'
expect_red "decoy: heading demoted, mid-body citations remain" "FAIL  canon: exactly one '### §11.4.290' heading in Constitution.md"
fresh; mut append Constitution.md '### §11.4.290 — duplicate block'
expect_red "duplicate canon heading" "FAIL  canon: exactly one '### §11.4.290' heading in Constitution.md"
fresh; mut append Constitution.md '**§11.4.290 — stray second block-start form.** text'
expect_red "second block-start form in canon" "FAIL  canon: exactly one §11.4.290 block-start of any form in Constitution.md (no duplicate form)"
fresh; mut file-sub Constitution.md '### §11.4.290 — Optimistic done with parallel background verification: PROVISIONAL-DONE vs VERIFIED-DONE' '### §11.4.290 — Optimistic done with parallel background verification: provisional vs verified'
expect_red "heading no longer names PROVISIONAL-DONE" "FAIL  canon: heading names PROVISIONAL-DONE"
fresh; mut block-sub Constitution.md 290 '(User mandate, 2026-10-27)' '(User mandate)'
expect_red "heading loses the mandate date" "FAIL  canon: heading carries the mandate date 2026-10-27"

# ── RED: back-pointers in the five refined anchors ───────────────────────────
for n in $REFINED; do
    fresh; mut block-sub Constitution.md "$n" 'Refinement note (2026-10-27)' 'Note'
    expect_red "refinement note removed from §11.4.$n" "FAIL  refined §11.4.$n: carries 'Refinement note (2026-10-27)'"
    fresh; mut block-resub Constitution.md "$n" '§11\.4\.290(?![0-9])' '§11.4.X87'
    expect_red "refinement note in §11.4.$n no longer cites §11.4.290" "FAIL  refined §11.4.$n: refinement note cites §11.4.290"
done

# ── RED: the four mirrors ────────────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; mut del-carrier "$f" 290
    expect_red "mirror block deleted: $f" "FAIL  mirror $f: exactly one §11.4.290 block-start"
    fresh; mut dup-carrier "$f" 290
    expect_red "mirror block duplicated: $f" "FAIL  mirror $f: exactly one §11.4.290 block-start"
    fresh; mut carrier-sub "$f" 290 'PROVISIONAL-DONE' '@@'
    expect_red "mirror loses PROVISIONAL-DONE: $f" "FAIL  mirror $f: block names PROVISIONAL-DONE"
    fresh; mut carrier-sub "$f" 290 'VERIFIED-DONE' '@@'
    expect_red "mirror loses VERIFIED-DONE: $f" "FAIL  mirror $f: block names VERIFIED-DONE"
    fresh; mut carrier-sub "$f" 290 '**Verification:**' '@@'
    expect_red "mirror loses the Verification: carrier: $f" "FAIL  mirror $f: block names the Verification: carrier"
    fresh; mut carrier-sub "$f" 290 'CM-PROVISIONAL-DONE-ANCHOR-WIRED' '@@'
    expect_red "mirror loses the gate token: $f" "FAIL  mirror $f: block names gate CM-PROVISIONAL-DONE-ANCHOR-WIRED"
    fresh; rm -f "$W/$f"
    expect_red "mirror file missing: $f" "FAIL  mirror $f: file missing"
done

# ── RED: lifecycle skill ─────────────────────────────────────────────────────
SK=skills/workable-item-lifecycle/SKILL.md
fresh; mut file-sub "$SK" '§11.4.290' '§11.4.X87'
expect_red "skill no longer cites §11.4.290" "FAIL  skill: workable-item-lifecycle cites §11.4.290"
fresh; mut file-sub "$SK" 'PROVISIONAL-DONE' '@@'
expect_red "skill loses PROVISIONAL-DONE" "FAIL  skill: workable-item-lifecycle names PROVISIONAL-DONE"
fresh; mut file-sub "$SK" 'VERIFIED-DONE' '@@'
expect_red "skill loses VERIFIED-DONE" "FAIL  skill: workable-item-lifecycle names VERIFIED-DONE"
fresh; mut file-sub "$SK" '**Verification:**' '@@'
expect_red "skill loses the Verification: line" "FAIL  skill: workable-item-lifecycle documents the Verification: line"
fresh; rm -f "$W/$SK"
expect_red "skill file missing" "FAIL  skill: skills/workable-item-lifecycle/SKILL.md missing"

# ── RED: generated artefacts ─────────────────────────────────────────────────
fresh; mut file-resub constitution_index.yaml '^- id: 11\.4\.290$' '- id: 11.4.290-removed'
expect_red "index entry for 11.4.290 gone" "FAIL  index: constitution_index.yaml has an entry for 11.4.290"
fresh; mut file-resub constitution_index.yaml '(- id: 11\.4\.290\n(?:.*\n)*?  propagation_gate: )CM-COVENANT-114-290-PROPAGATION' '\1none'
expect_red "index propagation_gate wrong" "FAIL  index: 11.4.290 propagation_gate is CM-COVENANT-114-290-PROPAGATION"
fresh; mut file-resub constitution_index.yaml '(- id: 11\.4\.290\n(?:.*\n)*?  group: )workable-items-and-tracking' '\1testing-and-tdd'
expect_red "index group wrong" "FAIL  index: 11.4.290 group is workable-items-and-tracking"
fresh; mut file-resub constitution_index.yaml '(- id: 11\.4\.290\n(?:.*\n)*?  classification: )universal' '\1project'
expect_red "index classification wrong" "FAIL  index: 11.4.290 classification is universal"
fresh; mut file-sub groups/workable-items-and-tracking.md '### §11.4.290 ' '#### §11.4.290 '
expect_red "group file loses the block" "FAIL  group: workable-items-and-tracking.md carries exactly one §11.4.290 block"
fresh; rm -f "$W/progressive/rules/11.4.290.md"
expect_red "progressive rule file missing" "FAIL  progressive: rules/11.4.290.md exists"
fresh; mut del-lines progressive/catalog.json '"id":"§11\.4\.290"'
expect_red "catalog entry gone" "FAIL  progressive: catalog.json lists §11.4.290"

# ── RED: seams ───────────────────────────────────────────────────────────────
fresh; mut del-lines scripts/gates/covenant_propagation_anchors.tsv '^CM-COVENANT-114-290-PROPAGATION'
expect_red "data-pack row removed" "FAIL  seam: propagation data pack has the CM-COVENANT-114-290-PROPAGATION<TAB>11.4.290 row"
fresh; mut file-sub scripts/gates/covenant_propagation_anchors.tsv $'CM-COVENANT-114-290-PROPAGATION\t11.4.290' $'CM-COVENANT-114-290-PROPAGATION\t11.4.288'
expect_red "data-pack row points at the wrong anchor" "FAIL  seam: propagation data pack has the CM-COVENANT-114-290-PROPAGATION<TAB>11.4.290 row"
fresh; rm -f "$W/scripts/gates/cm_covenant_114_290_propagation.sh"
expect_red "generated propagation gate missing" "FAIL  seam: generated propagation gate cm_covenant_114_290_propagation.sh exists"
fresh; rm -f "$W/scripts/gates/cm_covenant_114_290_propagation_mutation_test.sh"
expect_red "generated propagation mutation test missing" "FAIL  seam: generated propagation mutation test exists"
fresh; rm -f "$W/scripts/gates/cm_provisional_done_anchor_wired_mutation_test.sh"
expect_red "this gate's own mutation test missing" "FAIL  seam: this gate's paired mutation test exists"
fresh; mut file-sub scripts/post_update_hook.sh 'cm_provisional_done_anchor_wired.sh' 'cm_removed_gate.sh'
expect_red "hook no longer runs the gate" "FAIL  seam: post_update_hook.sh runs this gate on every pull"
fresh; mut file-sub scripts/post_update_hook.sh 'CM-PROVISIONAL-DONE-ANCHOR-WIRED' 'CM-REMOVED'
expect_red "hook no longer names the token" "FAIL  seam: post_update_hook.sh names the token CM-PROVISIONAL-DONE-ANCHOR-WIRED"
fresh; rm -f "$W/scripts/post_update_hook.sh"
expect_red "hook file missing" "FAIL  seam: scripts/post_update_hook.sh missing"

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
expect_blind "heading extractor broken -> control needle fails" "$W/scripts/gates/broken_gate.sh"
fresh; rm -f "$W/Constitution.md"
expect_blind "Constitution.md missing"
fresh; mut file-sub Constitution.md '### §11.4.286 ' '#### §11.4.286 '
expect_blind "real-file control needle (§11.4.286 heading) lost"

if [ "$RESULT" -eq 0 ]; then
    say "PASS: $NRED RED/BLIND cases and $NGF GREEN cases (1 control + $((NGF - 1)) golden-FALSE) behaved as required — cm_provisional_done_anchor_wired.sh genuinely discriminates"
else
    say "FAIL: at least one mutation survived or a golden-FALSE case tripped the gate"
fi
exit "$RESULT"
