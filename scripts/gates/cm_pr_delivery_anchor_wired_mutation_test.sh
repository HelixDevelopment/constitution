#!/usr/bin/env bash
# cm_pr_delivery_anchor_wired_mutation_test.sh — paired §1.1 mutation test for CM-PR-DELIVERY-ANCHOR-WIRED
#
# Purpose
#   Proves cm_pr_delivery_anchor_wired.sh genuinely discriminates, instead of passing whatever it
#   is shown. It copies the files the gate reads into a scratch tree and runs the gate:
#     * GREEN control    the unmodified copy MUST pass (exit 0);
#     * golden-FALSE     changes that must NOT trip the gate (a mid-body citation of §11.4.297
#                        elsewhere, an unrelated project section after a mirror block, a
#                        prefix-colliding decoy heading §11.4.2970, a whitespace-only edit inside
#                        the block) MUST still pass (§11.4.201(1));
#     * RED mutations    every required marker phrase, every clause heading (A)..(I) and amendment
#                        point (A.1)..(A.3), every escape-hatch flag, every cross-reference, every
#                        back-pointer in the three composed anchors, every mirror and its phrases,
#                        the index entry, the group file, the progressive rule file and catalog,
#                        the data-pack row, the generated wrappers, the seam binding, the three
#                        deferral rows, the account-name gate and its test, the hook bindings, a
#                        duplicated canon block, a stray second block-start form and a demoted
#                        heading are removed or broken ONE AT A TIME, and the gate MUST exit 1 and
#                        name that exact failed check;
#     * BLIND            a broken block extractor, a missing Constitution.md and a lost real-file
#                        control needle MUST exit 2 (never a silent PASS).
#   Each mutation operator asserts it really changed the file; a no-op mutation is a test bug
#   (exit 2), never a green. No account name is stored in this file.
#
# Usage
#   cm_pr_delivery_anchor_wired_mutation_test.sh [--quiet]
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
GATE="$HERE/cm_pr_delivery_anchor_wired.sh"
N=297
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
for _t in python3 awk grep cp mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[mutation:pr-delivery] cannot determine: required tool '$_t' missing" >&2; exit 2; }
done
[ -f "$GATE" ] || { echo "[mutation:pr-delivery] SETUP FAILURE: gate missing: $GATE" >&2; exit 2; }

TMPD="$(mktemp -d)" || exit 2
trap 'rm -rf "${TMPD:?}"' EXIT
BASE="$TMPD/base"; W="$TMPD/work"; PY="$TMPD/mut.py"
RESULT=0; NRED=0; NGF=0
say() { printf '[mutation:pr-delivery] %s\n' "$*"; }
quiet_say() { [ "$QUIET" = 1 ] || say "$@"; }

FILES=(
    Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md
    constitution_index.yaml
    groups/git-and-data-safety.md
    "progressive/rules/11.4.$N.md" progressive/catalog.json
    scripts/gates/covenant_propagation_anchors.tsv
    "scripts/gates/cm_covenant_114_${N}_propagation.sh"
    "scripts/gates/cm_covenant_114_${N}_propagation_mutation_test.sh"
    scripts/gates/rule_seam_bindings.tsv
    scripts/gates/gate_ledger_deferrals.tsv
    scripts/gates/cm_pr_delivery_anchor_wired.sh
    scripts/gates/cm_pr_delivery_anchor_wired_mutation_test.sh
    scripts/gates/cm_pr_delivery_account_name_free.sh
    scripts/gates/cm_pr_delivery_account_name_free_mutation_test.sh
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
XREFS="6 17 35 66 92 113 142 181 188 202 209 227 233 235 240 273 288 289 290 292 293 296"
REFINED="288 292 293"
FLAGS=(--squash-merge-OK --rebase-merge-OK --merge-without-GO --merge-on-stale-base --merge-without-self-review --self-review-is-the-GO --agent-merges-under-human-gate --merge-moved-head --multi-task-branch --annotated-roadmap-item --skip-push-readback --skip-reviewer-readback --drop-refused-reviewer --reviewer-names-in-constitution --evidence-outside-repo-OK --delete-branch-before-parity --pin-before-submodule-merge --claim-mirror-parity-without-readback --claim-server-side-protection)
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
[ "${#MARKERS[@]}" -ge 70 ] || { say "SETUP FAILURE: could not parse MARKERS from the gate (${#MARKERS[@]})"; exit 2; }
mapfile -t CLAUSES < <(python3 - "$GATE" <<'PYEOF'
import re, shlex, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^CLAUSES=\(\n(.*?)^\)', src, re.S | re.M)
for tok in shlex.split(m.group(1)):
    print(tok)
PYEOF
)
[ "${#CLAUSES[@]}" -eq 12 ] || { say "SETUP FAILURE: could not parse CLAUSES from the gate (${#CLAUSES[@]})"; exit 2; }

# mk PREFIX -> the full gate marker that starts with PREFIX (the long load-bearing spans are not repeated here)
mk() { local m; for m in "${MARKERS[@]}"; do case "$m" in "$1"*) printf '%s' "$m"; return 0 ;; esac; done; printf 'NO-MARKER-STARTS-WITH:%s' "$1"; }

# ── GREEN control ────────────────────────────────────────────────────────────
fresh
expect_green "GREEN control: genuine tree"

# ── golden-FALSE: changes that must not trip the gate (§11.4.201(1)) ─────────
fresh; mut block-append Constitution.md 286 'See §11.4.297(C) for the landing read-back; this mid-body citation is not a block.'
expect_green "mid-body citation of §11.4.297 inside another anchor's block is not a second block"
fresh; mut append CLAUDE.md '## Project-specific section'; mut append CLAUDE.md 'Project text after the mirror block.'
expect_green "an unrelated project H2 section after the CLAUDE.md block does not break the mirror check"
fresh; mut append Constitution.md '### §11.4.2970 — prefix-collision decoy heading'
expect_green "prefix-colliding heading §11.4.2970 is not counted as §11.4.297"
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
for s in 1.1 2.1 9.2; do
    fresh; mut block-resub Constitution.md "$N" "§${s/./\\.}(?![0-9])" "§X$s"
    expect_red "cross-reference removed: §$s" "FAIL  canon: block cites §$s"
done
fresh; mut block-sub Constitution.md "$N" 'CM-PR-DELIVERY-ACCOUNT-NAME-FREE' 'CM-REMOVED-NAME-GATE'
expect_red "canon block no longer names the account-name gate" "FAIL  canon: block names gate CM-PR-DELIVERY-ACCOUNT-NAME-FREE"
fresh; mut file-sub scripts/gates/cm_pr_delivery_account_name_free.sh 'GATE="CM-PR-DELIVERY-ACCOUNT-NAME-FREE"' 'GATE="x"'
expect_red "the account-name gate no longer declares its token" "FAIL  seam: the account-name gate declares its token on a GATE= line"
fresh; mut block-resub Constitution.md "$N" '^Classification: universal' 'Classification (universal)'
expect_red "line-start Classification line removed" "FAIL  canon: block carries a line-start 'Classification: universal'"
fresh; mut block-sub Constitution.md "$N" '**Canonical authority:**' 'Canonical authority:'
expect_red "Canonical authority line removed" "FAIL  canon: block carries a Canonical authority line"
fresh; mut block-sub Constitution.md "$N" 'Non-compliance is a release blocker' 'Non-compliance is tolerated'
expect_red "non-compliance line weakened" "FAIL  canon: block carries the non-compliance release-blocker line"

# ── RED: semantic weakenings found by the independent audit of 2026-11-07 (insertions inside a rule) ─
fresh; mut block-sub Constitution.md "$N" 'It merges only when all of these are read back:' 'It merges when any of these is read back:'
expect_red "W1 any condition suffices" "FAIL  canon: block carries marker '$(mk 'It merges only when all of these are read back:')'"
fresh; mut block-resub Constitution.md "$N" '\(b\) its self-review of that head.*?\(f\) every approval the project configures as required is present;' '(b) the merge call pins the reviewed head where the platform offers it;'
expect_red "W2 conditions (b) to (f) dropped" "FAIL  canon: block carries marker '$(mk 'It merges only when all of these are read back:')'"
fresh; mut block-sub Constitution.md "$N" 'or no GO refuses the merge);' 'or no GO refuses the merge, except that where no independent reviewer is available within the merge window the self-review stands in for it);'
expect_red "W3 the self-review may stand in for the GO" "FAIL  canon: block carries marker '$(mk 'It merges only when all of these are read back:')'"
fresh; mut block-sub Constitution.md "$N" 'then no agent presses a merge button or calls a merge interface of the hosting platform:' 'then no agent presses a merge button or calls a merge interface of the hosting platform, except the author agent when the human merger has not answered within the merge window:'
expect_red "W4 an agent may merge under a human merge gate" "FAIL  canon: block carries marker '$(mk 'then no agent presses a merge button')'"
fresh; mut block-sub Constitution.md "$N" '(A.3) THE LANDING FORM. The landing is a fast-forward' '(A.3) THE LANDING FORM. The landing is a squash merge, a fast-forward'
expect_red "W5 squash allowed in (A.3)" "FAIL  canon: block carries marker '$(mk '(A.3) THE LANDING FORM.')'"
fresh; mut block-sub Constitution.md "$N" '(the §11.4.288(B)(4) count is zero).' '(the §11.4.288(B)(4) count is zero). The author agent may also delete it on every upstream right after the merge.'
expect_red "W9 retirement before parity" "FAIL  canon: block carries marker '$(mk 'the task branch is deleted locally')'"
fresh; mut block-sub Constitution.md "$N" '(g) the remote base tip, fetched right before the merge, is an ancestor of the reviewed head' '(g) the remote base tip was an ancestor of the reviewed head when it was pushed'
expect_red "H2 base ancestry read only at push time" "FAIL  canon: block carries marker '$(mk 'It merges only when all of these are read back:')'"
fresh; mut block-sub Constitution.md 288 'and the reviewed head contains the base tip as (B)(3) requires' '@@'
expect_red "the §11.4.288 note loses the base-tip condition" "FAIL  refined §11.4.288: the note requires the reviewed head to contain the base tip"
fresh; mut block-sub Constitution.md 288 'that step admits exactly two waits' 'that step admits waits'
expect_red "the §11.4.288 note no longer bounds the admitted waits to two" "FAIL  refined §11.4.288: the note names the two waits (B)(1) otherwise forbids"
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; mut carrier-sub "$f" "$N" 'once the GO for that exact head, the self-review, the reviewer read-back, an unmoved head that contains the base tip' '@@'
    expect_red "mirror loses the GO and base-tip conditions: $f" "FAIL  mirror $f: block names the GO and base-tip merge conditions"
done

# ── RED: heading integrity, decoys and duplicates ────────────────────────────
fresh; mut file-sub Constitution.md "### §11.4.$N — Pull-request delivery" "#### §11.4.$N — Pull-request delivery"
expect_red "decoy: heading demoted, mid-body citations remain" "FAIL  canon: exactly one '### §11.4.$N' heading in Constitution.md"
fresh; mut append Constitution.md "### §11.4.$N — duplicate block"
expect_red "duplicate canon heading" "FAIL  canon: exactly one '### §11.4.$N' heading in Constitution.md"
fresh; mut append Constitution.md "**§11.4.$N — stray second block-start form.** text"
expect_red "second block-start form in canon" "FAIL  canon: exactly one §11.4.$N block-start of any form in Constitution.md (no duplicate form)"
fresh; mut file-sub Constitution.md "### §11.4.$N — Pull-request delivery:" "### §11.4.$N — Review rules:"
expect_red "heading no longer names 'Pull-request delivery'" "FAIL  canon: heading names 'Pull-request delivery'"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)one pull request per task id" '\1one review per change'
expect_red "heading no longer names 'one pull request per task id'" "FAIL  canon: heading names 'one pull request per task id'"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)no account is named in this constitution" '\1accounts are listed here'
expect_red "heading no longer names 'no account is named in this constitution'" "FAIL  canon: heading names 'no account is named in this constitution'"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)self-reviewed on the platform by its author agent" '\1merged by a person'
expect_red "heading no longer names the author agent's self-review" "FAIL  canon: heading names 'self-reviewed on the platform by its author agent'"
fresh; mut file-resub Constitution.md "^(### §11\\.4\\.$N .*?)where the project configures a human merge gate" '\1always'
expect_red "heading no longer names the human merge gate" "FAIL  canon: heading names 'where the project configures a human merge gate'"
fresh; mut block-sub Constitution.md "$N" '(User mandate, 2026-11-07)' '(User mandate)'
expect_red "heading loses the mandate date" "FAIL  canon: heading carries the mandate date 2026-11-07"

# ── RED: back-pointers in the three composed anchors ─────────────────────────
for n in $REFINED; do
    fresh; mut block-sub Constitution.md "$n" 'Refinement note (2026-11-07)' 'Note'
    expect_red "refinement note removed from §11.4.$n" "FAIL  refined §11.4.$n: carries 'Refinement note (2026-11-07)'"
    fresh; mut block-resub Constitution.md "$n" '§11\.4\.297(?![0-9])' '§11.4.X97'
    expect_red "refinement note in §11.4.$n no longer cites §11.4.297" "FAIL  refined §11.4.$n: refinement note cites §11.4.297"
done
fresh; mut block-sub Constitution.md 288 'it amends this anchor at exactly three points' 'it amends this anchor'
expect_red "the §11.4.288 note no longer bounds the amendment to three points" "FAIL  refined §11.4.288: the note states 'it amends this anchor at exactly three points'"
fresh; mut block-sub Constitution.md 288 'never a squash or rebase merge' 'any merge form'
expect_red "the §11.4.288 note no longer forbids squash and rebase" "FAIL  refined §11.4.288: the note forbids squash and rebase landings"
fresh; mut block-sub Constitution.md 288 'binds such a project unchanged' 'may bind such a project'
expect_red "the §11.4.288 note no longer keeps the rest binding" "FAIL  refined §11.4.288: the note keeps every other sentence binding"
fresh; mut block-sub Constitution.md 288 'by its author agent after a read-back self-review' 'by a merger'
expect_red "the §11.4.288 note no longer names the read-back self-review" "FAIL  refined §11.4.288: the note names the author agent's read-back self-review"
fresh; mut block-sub Constitution.md 288 'where the project configures a human merge gate' 'where it likes'
expect_red "the §11.4.288 note no longer names the human merge gate" "FAIL  refined §11.4.288: the note names the human merge gate"
fresh; mut block-sub Constitution.md 293 'gains no fifth' 'gains a fifth'
expect_red "the §11.4.293 note adds a fifth reason" "FAIL  refined §11.4.293: the note adds no fifth reason"
fresh; mut block-sub Constitution.md 293 'is an interpretation of (A)(4), stated as one in §11.4.297(E)(3), not an amendment' 'is a fifth reason'
expect_red "the §11.4.293 note no longer calls the reading an interpretation" "FAIL  refined §11.4.293: the note states the generated-regeneration reading as an interpretation"

# ── RED: the four mirrors ────────────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; mut del-carrier "$f" "$N"
    expect_red "mirror block deleted: $f" "FAIL  mirror $f: exactly one §11.4.$N block-start"
    fresh; mut dup-carrier "$f" "$N"
    expect_red "mirror block duplicated: $f" "FAIL  mirror $f: exactly one §11.4.$N block-start"
    fresh; mut carrier-sub "$f" "$N" 'landing form (`ff-only` or `merge-commit`)' '@@'
    expect_red "mirror loses the landing forms: $f" "FAIL  mirror $f: block names the two landing forms"
    fresh; mut carrier-sub "$f" "$N" 'never a squash or rebase merge' '@@'
    expect_red "mirror loses the squash/rebase ban: $f" "FAIL  mirror $f: block forbids squash and rebase landings"
    fresh; mut carrier-sub "$f" "$N" 'The author agent self-reviews the pull request on the platform' '@@'
    expect_red "mirror loses the author agent's self-review: $f" "FAIL  mirror $f: block names the author agent's self-review and merge"
    fresh; mut carrier-sub "$f" "$N" 'under a human merge gate only the human merger merges' '@@'
    expect_red "mirror loses the human merge gate: $f" "FAIL  mirror $f: block names the human merge gate"
    fresh; mut carrier-sub "$f" "$N" 'default key `pr_reviewers`' '@@'
    expect_red "mirror loses the reviewer key: $f" "FAIL  mirror $f: block names the default reviewer key"
    fresh; mut carrier-sub "$f" "$N" 'never named here' '@@'
    expect_red "mirror loses 'never named here': $f" "FAIL  mirror $f: block says the reviewers are never named here"
    fresh; mut carrier-sub "$f" "$N" '(`PRESENT`, `MIRROR-LAG <tip>`, `UNREACHABLE`)' '@@'
    expect_red "mirror loses the parity words: $f" "FAIL  mirror $f: block names the parity words"
    fresh; mut carrier-sub "$f" "$N" '`ENFORCED`, `PROVISIONAL` or `UNCONFIRMED`' '@@'
    expect_red "mirror loses the enforcement words: $f" "FAIL  mirror $f: block names the enforcement words"
    fresh; mut carrier-sub "$f" "$N" 'CM-PR-DELIVERY-ANCHOR-WIRED' '@@'
    expect_red "mirror loses the gate token: $f" "FAIL  mirror $f: block names gate CM-PR-DELIVERY-ANCHOR-WIRED"
    fresh; mut carrier-sub "$f" "$N" 'CM-PR-DELIVERY-ACCOUNT-NAME-FREE' '@@'
    expect_red "mirror loses the account-name gate token: $f" "FAIL  mirror $f: block names gate CM-PR-DELIVERY-ACCOUNT-NAME-FREE"
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
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  group: )git-and-data-safety" '\1testing-and-tdd'
expect_red "index group wrong" "FAIL  index: 11.4.$N group is git-and-data-safety"
fresh; mut file-resub constitution_index.yaml "(- id: 11\\.4\\.$N\\n(?:.*\\n)*?  classification: )universal" '\1project'
expect_red "index classification wrong" "FAIL  index: 11.4.$N classification is universal"
fresh; mut file-sub groups/git-and-data-safety.md "### §11.4.$N " "#### §11.4.$N "
expect_red "group file loses the block" "FAIL  group: git-and-data-safety.md carries exactly one §11.4.$N block"
fresh; rm -f "${W:?}/groups/git-and-data-safety.md"
expect_red "group file missing" "FAIL  group: groups/git-and-data-safety.md missing"
fresh; rm -f "${W:?}/progressive/rules/11.4.$N.md"
expect_red "progressive rule file missing" "FAIL  progressive: rules/11.4.$N.md exists"
fresh; mut del-lines progressive/catalog.json "\"id\":\"§11\\.4\\.$N\""
expect_red "catalog entry gone" "FAIL  progressive: catalog.json lists §11.4.$N"
fresh; mut file-sub progressive/catalog.json "\"file\":\"progressive/rules/11.4.$N.md\"" '"file":"progressive/rules/missing.md"'
expect_red "catalog file pointer wrong" "FAIL  progressive: catalog.json points at rules/11.4.$N.md"

# ── RED: seams ───────────────────────────────────────────────────────────────
fresh; mut del-lines scripts/gates/covenant_propagation_anchors.tsv "^CM-COVENANT-114-$N-PROPAGATION"
expect_red "data-pack row removed" "FAIL  seam: propagation data pack has the CM-COVENANT-114-$N-PROPAGATION<TAB>11.4.$N row"
fresh; mut file-sub scripts/gates/covenant_propagation_anchors.tsv $'CM-COVENANT-114-297-PROPAGATION\t11.4.297' $'CM-COVENANT-114-297-PROPAGATION\t11.4.288'
expect_red "data-pack row points at the wrong anchor" "FAIL  seam: propagation data pack has the CM-COVENANT-114-$N-PROPAGATION<TAB>11.4.$N row"
fresh; rm -f "${W:?}/scripts/gates/cm_covenant_114_${N}_propagation.sh"
expect_red "generated propagation gate missing" "FAIL  seam: generated propagation gate cm_covenant_114_${N}_propagation.sh exists"
fresh; rm -f "${W:?}/scripts/gates/cm_covenant_114_${N}_propagation_mutation_test.sh"
expect_red "generated propagation mutation test missing" "FAIL  seam: generated propagation mutation test exists"
fresh; mut del-lines scripts/gates/rule_seam_bindings.tsv "^11\\.4\\.$N"$'\t'
expect_red "seam binding row removed" "FAIL  seam: rule_seam_bindings.tsv binds 11.4.$N to a seam"
# The deferred gate names are read from the registry at run time (never written here as literals).
for ow in OWED-GATE-182 OWED-GATE-183 OWED-GATE-184; do
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
fresh; rm -f "${W:?}/scripts/gates/cm_pr_delivery_anchor_wired_mutation_test.sh"
expect_red "this gate's own mutation test missing" "FAIL  seam: this gate's paired mutation test exists"
fresh; rm -f "${W:?}/scripts/gates/cm_pr_delivery_account_name_free.sh"
expect_red "the account-name gate missing" "FAIL  seam: the account-name gate exists"
fresh; rm -f "${W:?}/scripts/gates/cm_pr_delivery_account_name_free_mutation_test.sh"
expect_red "the account-name gate's mutation test missing" "FAIL  seam: the account-name gate's paired mutation test exists"
fresh; mut file-sub scripts/post_update_hook.sh 'cm_pr_delivery_anchor_wired.sh' 'cm_removed_gate.sh'
expect_red "hook no longer runs the gate" "FAIL  seam: post_update_hook.sh runs this gate on every pull"
fresh; mut file-sub scripts/post_update_hook.sh 'CM-PR-DELIVERY-ANCHOR-WIRED' 'CM-REMOVED'
expect_red "hook no longer names the token" "FAIL  seam: post_update_hook.sh names the token CM-PR-DELIVERY-ANCHOR-WIRED"
fresh; mut file-sub scripts/post_update_hook.sh 'cm_pr_delivery_account_name_free.sh' 'cm_removed_gate2.sh'
expect_red "hook no longer runs the account-name gate" "FAIL  seam: post_update_hook.sh runs the account-name gate on every pull"
fresh; mut file-sub scripts/post_update_hook.sh 'CM-PR-DELIVERY-ACCOUNT-NAME-FREE' 'CM-REMOVED2'
expect_red "hook no longer names the account-name token" "FAIL  seam: post_update_hook.sh names the token CM-PR-DELIVERY-ACCOUNT-NAME-FREE"
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
expect_blind "heading extractor broken -> the control needle refuses (BLIND)" "$W/scripts/gates/broken_gate.sh"
fresh; rm -f "${W:?}/Constitution.md"
expect_blind "Constitution.md missing"
fresh; mut file-sub Constitution.md '### §11.4.286 ' '#### §11.4.286 '
expect_blind "real-file control needle (§11.4.286 heading) lost"

if [ "$RESULT" -eq 0 ]; then
    say "PASS: $NRED RED/BLIND cases and $NGF GREEN cases (1 control + $((NGF - 1)) golden-FALSE) behaved as required — cm_pr_delivery_anchor_wired.sh genuinely discriminates"
else
    say "FAIL: at least one mutation survived or a golden-FALSE case tripped the gate"
fi
exit "$RESULT"
