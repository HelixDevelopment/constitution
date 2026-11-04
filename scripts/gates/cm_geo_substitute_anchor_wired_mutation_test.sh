#!/usr/bin/env bash
# cm_geo_substitute_anchor_wired_mutation_test.sh — paired §1.1 mutation test for CM-GEO-SUBSTITUTE-ANCHOR-WIRED
#
# Purpose
#   Proves cm_geo_substitute_anchor_wired.sh genuinely discriminates, instead of
#   passing whatever it is shown. It copies the files the gate reads into a scratch
#   tree and runs the gate:
#     * GREEN control    the unmodified copy MUST pass (exit 0);
#     * golden-FALSE     changes that must NOT trip the gate (a mid-body citation of
#                        §11.4.295 elsewhere, an unrelated project section after a
#                        mirror block, a prefix-colliding decoy heading §11.4.2950,
#                        a whitespace-only edit inside the block) MUST still pass — a
#                        gate that refuses them is a false-positive refusal
#                        (§11.4.201(1));
#     * RED mutations    every required marker phrase, every clause heading (A)..(G),
#                        every escape-hatch flag, every cross-reference, every
#                        back-pointer in the five composed anchors, every mirror, the
#                        index entry, the group file, the progressive rule file and
#                        catalog, the data-pack row, the generated wrappers, the seam
#                        binding, the deferral row, the hook binding, a duplicated
#                        canon block, a stray second block-start form and a demoted
#                        heading is removed or broken ONE AT A TIME, and the gate MUST
#                        exit 1 and name that exact failed check;
#     * BLIND            a broken block extractor, a missing Constitution.md and a lost
#                        real-file control needle MUST exit 2 (never a silent PASS).
#   Each mutation operator asserts it really changed the file; a no-op mutation is a
#   test bug (exit 2), never a green.
#
# Usage
#   cm_geo_substitute_anchor_wired_mutation_test.sh [--quiet]
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
GATE="$HERE/cm_geo_substitute_anchor_wired.sh"
N=295
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
for _t in python3 awk grep cp mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[mutation:geo] cannot determine: required tool '$_t' missing" >&2; exit 2; }
done
[ -f "$GATE" ] || { echo "[mutation:geo] SETUP FAILURE: gate missing: $GATE" >&2; exit 2; }

TMPD="$(mktemp -d)" || exit 2
trap 'rm -rf "${TMPD:?}"' EXIT
BASE="$TMPD/base"; W="$TMPD/work"; PY="$TMPD/mut.py"
RESULT=0; NRED=0; NGF=0
say() { printf '[mutation:geo] %s\n' "$*"; }
quiet_say() { [ "$QUIET" = 1 ] || say "$@"; }

FILES=(
    Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md
    constitution_index.yaml
    groups/testing-and-tdd.md
    "progressive/rules/11.4.$N.md" progressive/catalog.json
    scripts/gates/covenant_propagation_anchors.tsv
    "scripts/gates/cm_covenant_114_${N}_propagation.sh"
    "scripts/gates/cm_covenant_114_${N}_propagation_mutation_test.sh"
    scripts/gates/rule_seam_bindings.tsv
    scripts/gates/gate_ledger_deferrals.tsv
    scripts/gates/cm_geo_substitute_anchor_wired.sh
    scripts/gates/cm_geo_substitute_anchor_wired_mutation_test.sh
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
XREFS="3 6 17 35 50 69 107 117 118 136 143 201 202 227 273 289 293"
REFINED="69 107 117 143 293"
CLAUSE_IDS=(A B C D E F G)
FLAGS=(--geo-restricted-is-failure --geo-restricted-is-pass --skip-instead-of-substitute --weaker-criteria-for-substitute --substitute-chosen-after-result --geo-label-without-probe-record --geo-label-without-control-probe --substitute-proves-original-app)
grep -F -q -- "for n in $XREFS; do" "$GATE" || { say "SETUP FAILURE: gate cross-reference list differs from this test's list"; exit 2; }
grep -F -q -- "for n in $REFINED; do" "$GATE" || { say "SETUP FAILURE: gate refined-anchor list differs from this test's list"; exit 2; }
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
[ "${#MARKERS[@]}" -ge 25 ] || { say "SETUP FAILURE: could not parse MARKERS from the gate (${#MARKERS[@]})"; exit 2; }
mapfile -t CLAUSES < <(python3 - "$GATE" <<'PYEOF'
import re, shlex, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^CLAUSES=\(\n(.*?)^\)', src, re.S | re.M)
for tok in shlex.split(m.group(1)):
    print(tok)
PYEOF
)
[ "${#CLAUSES[@]}" -eq 7 ] || { say "SETUP FAILURE: could not parse CLAUSES from the gate (${#CLAUSES[@]})"; exit 2; }

# ── GREEN control ────────────────────────────────────────────────────────────
fresh
expect_green "GREEN control: genuine tree"

# ── golden-FALSE: changes that must not trip the gate (§11.4.201(1)) ─────────
fresh; mut block-append Constitution.md 286 'See §11.4.295(C) for the substitute verdict; this mid-body citation is not a block.'
expect_green "mid-body citation of §11.4.295 inside another anchor's block is not a second block"
fresh; mut append CLAUDE.md '## Project-specific section'; mut append CLAUDE.md 'Project text after the mirror block.'
expect_green "an unrelated project H2 section after the CLAUDE.md block does not break the mirror check"
fresh; mut append Constitution.md '### §11.4.2950 — prefix-collision decoy heading'
expect_green "prefix-colliding heading §11.4.2950 is not counted as §11.4.295"
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
fresh; mut block-resub Constitution.md "$N" '§1\.1(?![0-9])' '§X1.1'
expect_red "cross-reference removed: §1.1" "FAIL  canon: block cites §1.1"
fresh; mut block-resub Constitution.md "$N" '^Classification: universal' 'Classification (universal)'
expect_red "line-start Classification line removed" "FAIL  canon: block carries a line-start 'Classification: universal'"
fresh; mut block-sub Constitution.md "$N" '**Canonical authority:**' 'Canonical authority:'
expect_red "Canonical authority line removed" "FAIL  canon: block carries a Canonical authority line"
fresh; mut block-sub Constitution.md "$N" 'Non-compliance is a release blocker' 'Non-compliance is tolerated'
expect_red "non-compliance line weakened" "FAIL  canon: block carries the non-compliance release-blocker line"

# ── RED: heading integrity, decoys and duplicates ────────────────────────────
fresh; mut file-sub Constitution.md "### §11.4.$N — Substitute app, same verdict" "#### §11.4.$N — Substitute app, same verdict"
expect_red "decoy: heading demoted, mid-body citations remain" "FAIL  canon: exactly one '### §11.4.$N' heading in Constitution.md"
fresh; mut append Constitution.md "### §11.4.$N — duplicate block"
expect_red "duplicate canon heading" "FAIL  canon: exactly one '### §11.4.$N' heading in Constitution.md"
fresh; mut append Constitution.md "**§11.4.$N — stray second block-start form.** text"
expect_red "second block-start form in canon" "FAIL  canon: exactly one §11.4.$N block-start of any form in Constitution.md (no duplicate form)"
fresh; mut file-sub Constitution.md "### §11.4.$N — Substitute app, same verdict" "### §11.4.$N — Region rules"
expect_red "heading no longer names 'Substitute app, same verdict'" "FAIL  canon: heading names 'Substitute app, same verdict'"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)recorded as GEO_RESTRICTED" '\1recorded as a region refusal'
expect_red "heading no longer names GEO_RESTRICTED" "FAIL  canon: heading names GEO_RESTRICTED"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)under the SAME pass/fail criteria" '\1under looser criteria'
expect_red "heading no longer names 'SAME pass/fail criteria'" "FAIL  canon: heading names 'SAME pass/fail criteria'"
fresh; mut block-sub Constitution.md "$N" '(User mandate, 2026-11-03)' '(User mandate)'
expect_red "heading loses the mandate date" "FAIL  canon: heading carries the mandate date 2026-11-03"

# ── RED: back-pointers in the five composed anchors ──────────────────────────
for n in $REFINED; do
    fresh; mut block-sub Constitution.md "$n" 'Refinement note (2026-11-03)' 'Note'
    expect_red "refinement note removed from §11.4.$n" "FAIL  refined §11.4.$n: carries 'Refinement note (2026-11-03)'"
    fresh; mut block-resub Constitution.md "$n" '§11\.4\.295(?![0-9])' '§11.4.X95'
    expect_red "refinement note in §11.4.$n no longer cites §11.4.295" "FAIL  refined §11.4.$n: refinement note cites §11.4.295"
done

# ── RED: the four mirrors ────────────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; mut del-carrier "$f" "$N"
    expect_red "mirror block deleted: $f" "FAIL  mirror $f: exactly one §11.4.$N block-start"
    fresh; mut dup-carrier "$f" "$N"
    expect_red "mirror block duplicated: $f" "FAIL  mirror $f: exactly one §11.4.$N block-start"
    fresh; mut carrier-sub "$f" "$N" '`GEO_RESTRICTED`' '@@'
    expect_red "mirror loses the record label: $f" "FAIL  mirror $f: block names the record label GEO_RESTRICTED"
    fresh; mut carrier-sub "$f" "$N" '`geo_restricted`' '@@'
    expect_red "mirror loses the reason code: $f" "FAIL  mirror $f: block keeps the reason code geo_restricted"
    fresh; mut carrier-sub "$f" "$N" 'GEO_RESTRICTED(<original app>) -> <substitute app>: <verdict>' '@@'
    expect_red "mirror loses the report line: $f" "FAIL  mirror $f: block names the report line"
    fresh; mut carrier-sub "$f" "$N" 'substitute chain' '@@'
    expect_red "mirror loses the substitute chain: $f" "FAIL  mirror $f: block names the substitute chain"
    fresh; mut carrier-sub "$f" "$N" "sha256 of the test's criteria set" '@@'
    expect_red "mirror loses the criteria hash: $f" "FAIL  mirror $f: block names the criteria hash"
    fresh; mut carrier-sub "$f" "$N" 'CM-GEO-SUBSTITUTE-ANCHOR-WIRED' '@@'
    expect_red "mirror loses the gate token: $f" "FAIL  mirror $f: block names gate CM-GEO-SUBSTITUTE-ANCHOR-WIRED"
    fresh; rm -f "${W:?}/${f:?}"
    expect_red "mirror file missing: $f" "FAIL  mirror $f: file missing"
done

# ── RED: generated artefacts ─────────────────────────────────────────────────
fresh; mut file-resub constitution_index.yaml "^- id: 11\\.4\\.$N\$" "- id: 11.4.$N-removed"
expect_red "index entry for 11.4.$N gone" "FAIL  index: constitution_index.yaml has an entry for 11.4.$N"
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  propagation_gate: )CM-COVENANT-114-$N-PROPAGATION" '\1none'
expect_red "index propagation_gate wrong" "FAIL  index: 11.4.$N propagation_gate is CM-COVENANT-114-$N-PROPAGATION"
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  group: )testing-and-tdd" '\1workable-items-and-tracking'
expect_red "index group wrong" "FAIL  index: 11.4.$N group is testing-and-tdd"
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  classification: )universal" '\1project'
expect_red "index classification wrong" "FAIL  index: 11.4.$N classification is universal"
fresh; mut file-sub groups/testing-and-tdd.md "### §11.4.$N " "#### §11.4.$N "
expect_red "group file loses the block" "FAIL  group: testing-and-tdd.md carries exactly one §11.4.$N block"
fresh; rm -f "${W:?}/groups/testing-and-tdd.md"
expect_red "group file missing" "FAIL  group: groups/testing-and-tdd.md missing"
fresh; rm -f "${W:?}/progressive/rules/11.4.$N.md"
expect_red "progressive rule file missing" "FAIL  progressive: rules/11.4.$N.md exists"
fresh; mut del-lines progressive/catalog.json "\"id\":\"§11\\.4\\.$N\""
expect_red "catalog entry gone" "FAIL  progressive: catalog.json lists §11.4.$N"
fresh; mut file-sub progressive/catalog.json "\"file\":\"progressive/rules/11.4.$N.md\"" '"file":"progressive/rules/missing.md"'
expect_red "catalog file pointer wrong" "FAIL  progressive: catalog.json points at rules/11.4.$N.md"

# ── RED: seams ───────────────────────────────────────────────────────────────
fresh; mut del-lines scripts/gates/covenant_propagation_anchors.tsv "^CM-COVENANT-114-$N-PROPAGATION"
expect_red "data-pack row removed" "FAIL  seam: propagation data pack has the CM-COVENANT-114-$N-PROPAGATION<TAB>11.4.$N row"
fresh; mut file-sub scripts/gates/covenant_propagation_anchors.tsv $'CM-COVENANT-114-295-PROPAGATION\t11.4.295' $'CM-COVENANT-114-295-PROPAGATION\t11.4.292'
expect_red "data-pack row points at the wrong anchor" "FAIL  seam: propagation data pack has the CM-COVENANT-114-$N-PROPAGATION<TAB>11.4.$N row"
fresh; rm -f "${W:?}/scripts/gates/cm_covenant_114_${N}_propagation.sh"
expect_red "generated propagation gate missing" "FAIL  seam: generated propagation gate cm_covenant_114_${N}_propagation.sh exists"
fresh; rm -f "${W:?}/scripts/gates/cm_covenant_114_${N}_propagation_mutation_test.sh"
expect_red "generated propagation mutation test missing" "FAIL  seam: generated propagation mutation test exists"
fresh; mut del-lines scripts/gates/rule_seam_bindings.tsv "^11\\.4\\.$N"$'\t'
expect_red "seam binding row removed" "FAIL  seam: rule_seam_bindings.tsv binds 11.4.$N to a seam"
for pair in CM-GEO-SUBSTITUTE-SAME-VERDICT:OWED-GATE-180; do
    dg="${pair%%:*}"; ow="${pair##*:}"
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
fresh; rm -f "${W:?}/scripts/gates/cm_geo_substitute_anchor_wired_mutation_test.sh"
expect_red "this gate's own mutation test missing" "FAIL  seam: this gate's paired mutation test exists"
fresh; mut file-sub scripts/post_update_hook.sh 'cm_geo_substitute_anchor_wired.sh' 'cm_removed_gate.sh'
expect_red "hook no longer runs the gate" "FAIL  seam: post_update_hook.sh runs this gate on every pull"
fresh; mut file-sub scripts/post_update_hook.sh 'CM-GEO-SUBSTITUTE-ANCHOR-WIRED' 'CM-REMOVED'
expect_red "hook no longer names the token" "FAIL  seam: post_update_hook.sh names the token CM-GEO-SUBSTITUTE-ANCHOR-WIRED"
fresh; rm -f "${W:?}/scripts/post_update_hook.sh"
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
fresh; rm -f "${W:?}/Constitution.md"
expect_blind "Constitution.md missing"
fresh; mut file-sub Constitution.md '### §11.4.286 ' '#### §11.4.286 '
expect_blind "real-file control needle (§11.4.286 heading) lost"

if [ "$RESULT" -eq 0 ]; then
    say "PASS: $NRED RED/BLIND cases and $NGF GREEN cases (1 control + $((NGF - 1)) golden-FALSE) behaved as required — cm_geo_substitute_anchor_wired.sh genuinely discriminates"
else
    say "FAIL: at least one mutation survived or a golden-FALSE case tripped the gate"
fi
exit "$RESULT"
