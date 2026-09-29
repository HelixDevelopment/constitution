#!/bin/sh
# T021 RED test (plan T-A07; FR-013, SC-005): constitution/scripts/fastcycle/context/anchor_citations.py
# (T039) must record, per work item, the real section-anchor ids cited in its commits/diaries/
# review-records/closure-evidence as {item_id, anchor_id, source}, checked against the LIVE anchor-
# opener list read from constitution/constitution_index.yaml -- NEVER a literal (contracts/
# common-conventions.md C-004; plan T-A07: "distribution of anchors bound per item against the live
# anchor-opener count ... never a literal").
#
# Contract for the T039 implementer -- BINDING HERE (UNCONFIRMED: no contract file under contracts/
# covers this tool; contracts/common-conventions.md's "Plan tools that no contract in this directory
# covers" list names `$FC/context/anchor_citations.py (T-A07)` explicitly and states "Their interface,
# output and RED fixtures are fixed by the plan task text until a contract is written" -- this file IS
# that fixing, mirroring the test_host_guard_red.sh precedent used for T012):
#
#   Invocation : python3 context/anchor_citations.py --item-id <ID> --repo <PATH>
#                  --anchor-index <PATH to constitution_index.yaml> --out <PATH>
#                  [--sources commit,diary,review,closure] [--as-of YYYY-MM-DD] [--determinism-check]
#   --repo     : the CONSUMING project's working tree (the repo whose commit/diary/review/closure
#                artefacts are scanned for <ID>) -- ALWAYS supplied explicitly by the caller, NEVER
#                guessed (this constitution submodule's own git history is a DIFFERENT repository and
#                does not contain the consuming project's ATM-NNN commits; §11.4.6/§11.4.28).
#   Output     : canonical JSON per C-002 (schema "anchor_citations/v1"), body containing at least:
#                {"item_id": "<ID>",
#                 "citations": [{"anchor_id": "<id>", "source": "commit"|"diary"|"review"|"closure",
#                                "evidence": "<commit sha | file path>"}, ...],
#                 "anchor_opener_count": <int -- MUST equal the live count of `- id:` entries read
#                                         from --anchor-index at run time; NEVER a hardcoded literal>}
#   anchor_id set : exactly the ids enumerated under `anchors:` in --anchor-index; a numeric-looking
#                   token that is not one of those live ids (e.g. a release-version string such as
#                   "1.2.1") is NOT a citation -- see the false_positive_guard fixture below.
#   Exit codes : per C-001 (0 success; 2 usage/config error; 3 self-test failed; 4 BLIND -- --repo or
#                --anchor-index unreadable/unparseable).
#   Determinism: two runs over the same --as-of and repo state MUST produce byte-identical citations
#                (C-003; the citations array sorted by anchor_id then source per C-002).
#
# Control needle / negative control (this task's own mandate; VERIFIED against REAL repository
# history, never fabricated data -- 11.4.6/11.4.273). Human-auditable provenance record:
# fixtures/anchor_citations/atm277_control_needle.json -- this test does NOT trust that file blindly:
# every fact below is RE-DERIVED live, at run time, straight from `git log` and the real diary file;
# the fixture exists only so a reviewer can check the claims without re-running the git commands.
#
#   G1 PRESENT (task's literal control needle -- "an item whose commit message cites section 11.4.108
#     lists it"): item ATM-277, anchor 11.4.108, cited in the real commit 708245e4684cf54177abe43986
#     fea7a8c3680a76 (subject: "fix(ATM-277 section-11.4.108 ARTIFACT): bump presenter pointer 6a1c2da
#     -> c73d44b so the G1 stale-frame fix ACTUALLY SHIPS from a clean checkout").
#   G2 NEGATIVE CONTROL (task's literal ask -- "an anchor cited in no artefact of the item does not
#     appear"): item ATM-277, anchor 11.4.143 -- a genuine anchor id (constitution_index.yaml), proven
#     absent from ATM-277's ENTIRE commit corpus (899 lines, subject+body, every commit matched by
#     `git log --all --grep='ATM-277\b' -i`) AND from its diary docs/issues/ATM-277/Reopens.md.
#   G3 COMMIT-EXCLUSIVE PROBE (T027 discriminator -- see the T027 note below): item ATM-277, anchor
#     11.4.1, cited ONLY via commit d308642834cad69a2e4d34eec31265b062da177b's subject line. Anchor
#     11.4.108 (G1) is reachable via BOTH the commit AND the diary source for this item, so G1 alone
#     would NOT catch an implementation that silently skips commit-message scanning; 11.4.1 has no
#     other artefact for ATM-277, so it is the case that DOES discriminate that specific bug.
#   FALSE-POSITIVE GUARD: "1.2.1" appears verbatim inside real ATM-277 commit subjects (release strings
#     such as "1.2.1-dev-0.0.2") but is NOT a member of constitution_index.yaml's anchor id set --
#     proves an implementation that treats every N.N(.N) shaped token as a citation, without filtering
#     against the LIVE anchor index, would over-report.
#
# T027 mutation for this area ("anchor_citations ignores commit-message sources"): once GREEN, a
# mutation that makes the implementation skip the "source: commit" scan entirely is caught by G3:
# 11.4.1 has NO artefact for ATM-277 other than commit d308642834's subject line, so a commit-scan-
# skipping implementation reports it MISSING where the correct implementation reports it PRESENT --
# G3 flips PASS -> FAIL under exactly that mutation. (G1/G2 alone would NOT catch this specific
# mutation, since 11.4.108's diary citation would still surface it; G1/G2 instead guard against a
# "citations are fabricated" or "a negative-control anchor leaks in" class of bug.)
#
# Usage: sh test_anchor_citations_red.sh   (exit 0 = all assertions pass; nonzero = FAIL count > 0)
# During RED (anchor_citations.py absent) this correctly exits 1: the self-validation of the control-
# needle DESIGN (G1/G2/G3/false-positive guard, independent of the tool) passes now, but the tool-
# existence + tool-output assertions correctly FAIL because the implementation does not exist yet.

HERE=$(cd "$(dirname "$0")" && pwd)
FC="$HERE/../lib/fc_common.py"
IMPL="$HERE/../context/anchor_citations.py"
FIXTURE="$HERE/fixtures/anchor_citations/atm277_control_needle.json"
ANCHOR_INDEX_REL="constitution/constitution_index.yaml"
ITEM_ID="ATM-277"
G1_ANCHOR="11.4.108"; G1_COMMIT="708245e4684cf54177abe43986fea7a8c3680a76"
G3_ANCHOR="11.4.1";   G3_COMMIT="d308642834cad69a2e4d34eec31265b062da177b"
NEG_ANCHOR="11.4.143"
FP_DECOY="1.2.1"
DIARY_REL="docs/issues/ATM-277/Reopens.md"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

for dep in git python3 grep sort comm; do
  command -v "$dep" >/dev/null 2>&1 || { echo "BLIND: required dependency '$dep' not usable" >&2; exit 4; }
done

[ -f "$FIXTURE" ] || { echo "BLIND: control-needle provenance fixture absent: $FIXTURE" >&2; exit 4; }

# The consuming project's working tree -- NEVER this constitution submodule's own history (a
# different repository that does not contain the consuming project's ATM-NNN commits, 11.4.6/11.4.28).
# `--show-superproject-working-tree` is the non-guessing mechanism: it resolves the real parent
# checkout when this constitution tree is embedded as a submodule, and prints nothing otherwise.
REPO_ROOT=$(git -C "$HERE" rev-parse --show-superproject-working-tree 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  # Not currently consumed as a submodule of anything (e.g. constitution tested fully standalone):
  # honestly fall back to its own working tree. The ATM-277 control-needle commits below will then
  # not resolve there, which the resolvability checks immediately after report as BLIND, never a
  # silent pass (11.4.201(6): an absent/unreachable target is never read as "0 findings").
  REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)
fi
[ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ] || { echo "BLIND: could not resolve the consuming project's working tree" >&2; exit 4; }
ANCHOR_INDEX="$REPO_ROOT/$ANCHOR_INDEX_REL"
[ -f "$ANCHOR_INDEX" ] || { echo "BLIND: anchor index absent at $ANCHOR_INDEX" >&2; exit 4; }

if git -C "$REPO_ROOT" cat-file -e "$G1_COMMIT" 2>/dev/null && git -C "$REPO_ROOT" cat-file -e "$G3_COMMIT" 2>/dev/null; then
  ok "control-needle commits resolve in $REPO_ROOT ($G1_COMMIT, $G3_COMMIT)"
else
  bad "control-needle commits do not resolve in $REPO_ROOT: this test targets the atmosphere-t1 history; run it against that checkout"
  echo "SUMMARY pass=$PASS fail=$FAIL"
  exit 1
fi

TMP=$(mktemp -d) || { echo "BLIND: mktemp failed" >&2; exit 4; }
trap 'rm -rf "$TMP"' EXIT

# --- Step A: self-validate the control-needle DESIGN, live, independent of anchor_citations.py ---
# Live anchor ids from --anchor-index (never a frozen copy: a future anchor addition/removal is
# picked up automatically, matching T-A07's "never a literal" mandate).
grep -E '^- id:' "$ANCHOR_INDEX" | sed -E "s/^- id: *'?([^']+)'?\$/\1/" | LC_ALL=C sort -u > "$TMP/live_anchor_ids.txt"
LIVE_ANCHOR_COUNT=$(wc -l < "$TMP/live_anchor_ids.txt" | tr -d ' [:space:]')
case $LIVE_ANCHOR_COUNT in
  ''|*[!0-9]*) bad "live anchor-opener count unreadable from $ANCHOR_INDEX" ;;
  *)
    if [ "$LIVE_ANCHOR_COUNT" -ge 1 ]; then ok "live anchor-opener count read from $ANCHOR_INDEX = $LIVE_ANCHOR_COUNT (never a literal)"
    else bad "live anchor-opener count is zero"; fi ;;
esac

# Raw item-history corpus: the FULL commit corpus (subject+body of every commit whose message
# mentions the item id, word-bounded) plus the diary, if it exists. Read LIVE from git -- never a
# frozen snapshot -- so this test automatically incorporates any future ATM-277 commit too.
git -C "$REPO_ROOT" log --all --grep="${ITEM_ID}\\b" -i --format='%B' > "$TMP/item_commits.txt"
COMMIT_LINES=$(wc -l < "$TMP/item_commits.txt" | tr -d ' [:space:]')
if [ "$COMMIT_LINES" -ge 1 ]; then ok "live commit-message corpus for $ITEM_ID non-empty ($COMMIT_LINES lines)"
else bad "live commit-message corpus for $ITEM_ID is empty (git log --grep matched nothing)"; fi

DIARY_PATH="$REPO_ROOT/$DIARY_REL"
if [ -f "$DIARY_PATH" ]; then cp "$DIARY_PATH" "$TMP/item_diary.txt"; else : > "$TMP/item_diary.txt"; fi

# Tokenise: candidate anchor-shaped substrings, then filter to the LIVE anchor id set (the
# false-positive-guard step -- never trust a numeric-looking token on its own; §11.4.6).
grep -oE '[0-9]{1,2}(\.[0-9]{1,3}){1,3}(\.[A-Za-z])?' "$TMP/item_commits.txt" | LC_ALL=C sort -u > "$TMP/commit_tokens.txt"
grep -oE '[0-9]{1,2}(\.[0-9]{1,3}){1,3}(\.[A-Za-z])?' "$TMP/item_diary.txt"   | LC_ALL=C sort -u > "$TMP/diary_tokens.txt"
# comm's collation MUST match the LC_ALL=C sort that produced both inputs, else it reports
# "not in sorted order" and silently drops the comparison (a real instrument trap caught while
# authoring this test: an un-pinned `comm` disagreed with its own LC_ALL=C-sorted inputs -- see
# 11.4.201(7)(c)/11.4.273, "the path is part of the instrument").
LC_ALL=C comm -12 "$TMP/live_anchor_ids.txt" "$TMP/commit_tokens.txt" > "$TMP/commit_anchors.txt"
LC_ALL=C comm -12 "$TMP/live_anchor_ids.txt" "$TMP/diary_tokens.txt"  > "$TMP/diary_anchors.txt"
LC_ALL=C sort -u "$TMP/commit_anchors.txt" "$TMP/diary_anchors.txt" > "$TMP/all_anchors.txt"

# G1: the literal control needle -- item's commit message cites 11.4.108 -> must be listed.
if grep -qx -- "$G1_ANCHOR" "$TMP/all_anchors.txt"; then ok "G1 control needle: $ITEM_ID's real artefacts cite $G1_ANCHOR (commit $G1_COMMIT)"
else bad "G1 control needle MISSING: $G1_ANCHOR not found for $ITEM_ID (expected via commit $G1_COMMIT)"; fi
if grep -qx -- "$G1_ANCHOR" "$TMP/commit_anchors.txt"; then ok "G1 detail: $G1_ANCHOR specifically reachable via the commit source class"
else bad "G1 detail FAILED: $G1_ANCHOR not reachable via the commit source class"; fi

# G2: the literal negative control -- an anchor cited in NO artefact of the item -> must NOT appear.
if grep -qx -- "$NEG_ANCHOR" "$TMP/all_anchors.txt"; then bad "G2 negative control FAILED: $NEG_ANCHOR unexpectedly present for $ITEM_ID"
else ok "G2 negative control: $NEG_ANCHOR (a genuine anchor id) correctly absent from every artefact of $ITEM_ID"; fi

# G3: the T027 discriminator -- 11.4.1 reachable ONLY via the commit source (never the diary).
if grep -qx -- "$G3_ANCHOR" "$TMP/commit_anchors.txt"; then ok "G3 commit-exclusive probe: $ITEM_ID's commit source cites $G3_ANCHOR (commit $G3_COMMIT)"
else bad "G3 commit-exclusive probe MISSING: $G3_ANCHOR not found via the commit source (expected via $G3_COMMIT)"; fi
if grep -qx -- "$G3_ANCHOR" "$TMP/diary_anchors.txt"; then bad "G3 premise FAILED: $G3_ANCHOR unexpectedly ALSO present in the diary -- no longer commit-exclusive, the T027 claim above needs a different anchor"
else ok "G3 premise holds: $G3_ANCHOR is absent from the diary, so it is genuinely commit-exclusive for $ITEM_ID"; fi

# False-positive guard: a real release-version substring must NOT be treated as a citation.
if grep -qx -- "$FP_DECOY" "$TMP/commit_tokens.txt"; then ok "false-positive-guard premise holds: decoy token '$FP_DECOY' genuinely appears as a raw substring in $ITEM_ID's commits"
else bad "false-positive-guard premise FAILED: decoy token '$FP_DECOY' not found raw -- pick a different decoy"; fi
if grep -qx -- "$FP_DECOY" "$TMP/live_anchor_ids.txt"; then bad "false-positive-guard FAILED: '$FP_DECOY' is unexpectedly a real anchor id"
elif grep -qx -- "$FP_DECOY" "$TMP/commit_anchors.txt"; then bad "false-positive-guard FAILED: '$FP_DECOY' leaked into the live-index-filtered anchor set"
else ok "false-positive guard: decoy token '$FP_DECOY' correctly filtered out by the live-anchor-index intersection"; fi

# Re-run the SAME three properties through fc_common.py's own shared needle mechanism (C-004),
# as an independent second instrument -- if fc_common.py's needle logic itself regressed, this
# would disagree with the plain-grep checks above rather than silently agreeing with a broken one.
HAYSTACK_JSON=$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    print(json.dumps(sorted(l.strip() for l in fh if l.strip())))
" "$TMP/all_anchors.txt")
if python3 "$FC" needle --present "[\"$G1_ANCHOR\"]" --fabricated "[\"$NEG_ANCHOR\"]" --haystack "$HAYSTACK_JSON" >/dev/null 2>"$TMP/needle_g1g2.err"; then
  ok "fc_common.py needle (independent instrument): G1 present + G2 fabricated-absent both confirmed"
else
  bad "fc_common.py needle disagreed with the plain-grep G1/G2 checks: $(cat "$TMP/needle_g1g2.err")"
fi
COMMIT_HAYSTACK_JSON=$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    print(json.dumps(sorted(l.strip() for l in fh if l.strip())))
" "$TMP/commit_anchors.txt")
if python3 "$FC" needle --present "[\"$G3_ANCHOR\"]" --fabricated "[\"$NEG_ANCHOR\"]" --haystack "$COMMIT_HAYSTACK_JSON" >/dev/null 2>"$TMP/needle_g3.err"; then
  ok "fc_common.py needle (independent instrument): G3 commit-exclusive probe confirmed present via the commit source"
else
  bad "fc_common.py needle disagreed with the plain-grep G3 check: $(cat "$TMP/needle_g3.err")"
fi
# Needle self-test: feeding a haystack that DROPS the diary-independent G3 anchor (simulating the
# T027 mutation itself -- "ignores commit-message sources", so the commit-derived haystack becomes
# empty of it) must make the SAME needle call FAIL (exit 3), proving the needle genuinely
# discriminates rather than passing unconditionally.
MUTATED_HAYSTACK_JSON=$(python3 -c "
import json
print(json.dumps([]))
")
if python3 "$FC" needle --present "[\"$G3_ANCHOR\"]" --fabricated "[\"$NEG_ANCHOR\"]" --haystack "$MUTATED_HAYSTACK_JSON" >/dev/null 2>/dev/null; then
  bad "G3 mutation-simulation FAILED to fail: an empty (commit-scan-skipped) haystack was accepted -- the needle would not catch T027's mutation"
else
  ok "G3 mutation-simulation: an empty (commit-scan-skipped) haystack correctly FAILS the needle -- proves G3 would catch the T027 mutation once GREEN"
fi

# --- Step B: the actual RED gate -- the implementation does not exist yet ---
if [ ! -f "$IMPL" ]; then
  echo "RED: anchor_citations.py absent at $IMPL (T039 not yet landed)"
  bad "anchor_citations.py exists"
  echo "SUMMARY pass=$PASS fail=$FAIL"
  exit 1
fi

# --- Step C: once T039 lands, exercise the real tool end-to-end against the SAME control needle ---
OUT="$TMP/anchor_citations.out.json"
if ! python3 "$IMPL" --item-id "$ITEM_ID" --repo "$REPO_ROOT" --anchor-index "$ANCHOR_INDEX" --out "$OUT" 2>"$TMP/impl.err"; then
  bad "anchor_citations.py exited nonzero for --item-id $ITEM_ID: $(cat "$TMP/impl.err")"
else
  ok "anchor_citations.py ran to completion for --item-id $ITEM_ID"
fi
if [ -f "$OUT" ]; then
  python3 -c "
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc.get('schema', '').startswith('anchor_citations/v'), 'bad schema: %r' % doc.get('schema')
assert doc.get('item_id') == sys.argv[2], 'item_id mismatch: %r' % doc.get('item_id')
cites = doc.get('citations')
assert isinstance(cites, list), 'citations must be a list'
ids_all = {c.get('anchor_id') for c in cites}
ids_commit = {c.get('anchor_id') for c in cites if c.get('source') == 'commit'}
assert sys.argv[3] in ids_all, 'G1: %r missing from reported citations' % sys.argv[3]
assert sys.argv[4] not in ids_all, 'G2: negative-control %r leaked into reported citations' % sys.argv[4]
assert sys.argv[5] in ids_commit, 'G3: commit-exclusive %r not reported with source=commit' % sys.argv[5]
assert sys.argv[6] not in ids_all, 'false-positive-guard: decoy %r leaked into reported citations' % sys.argv[6]
opener = doc.get('anchor_opener_count')
assert isinstance(opener, int) and opener == int(sys.argv[7]), 'anchor_opener_count %r != live count %s (must never be a literal)' % (opener, sys.argv[7])
print('OK')
" "$OUT" "$ITEM_ID" "$G1_ANCHOR" "$NEG_ANCHOR" "$G3_ANCHOR" "$FP_DECOY" "$LIVE_ANCHOR_COUNT" > "$TMP/assert.out" 2> "$TMP/assert.err"
  if [ "$(cat "$TMP/assert.out")" = "OK" ]; then
    ok "anchor_citations.py output satisfies G1+G2+G3+false-positive-guard+live anchor_opener_count for $ITEM_ID"
  else
    bad "anchor_citations.py output failed assertions: $(cat "$TMP/assert.err")"
  fi
else
  bad "anchor_citations.py did not write --out $OUT"
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
