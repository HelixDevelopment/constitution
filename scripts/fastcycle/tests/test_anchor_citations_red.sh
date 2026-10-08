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
#   Output     : canonical JSON per C-002 (schema "anchor_citations/v2" since R8; v2 adds
#                source_status / source_errors / commit_stats / review_stats, and a failed source
#                makes the run exit 4 with "BLIND": true), body containing at least:
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

# Real-data invariant (R8 F1): on the REAL ATM-277 history, every two-segment anchor id the tool
# reports from the commit source (e.g. "7.1", "9.2", "11.4") must be backed by a `§<id>` spelling
# in that commit's own message. A bare "7.1" is overwhelmingly an audio channel layout ("5.1/7.1")
# or a document section number, never a constitution citation. Independent instrument: reads the
# commit message straight from git, not from the tool.
if [ -f "$OUT" ]; then
  python3 - "$OUT" "$REPO_ROOT" > "$TMP/twoseg.out" 2> "$TMP/twoseg.err" <<'PY'
import json, re, subprocess, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
bad = []
checked = 0
for c in doc.get("citations", []):
    a = c.get("anchor_id", "")
    if c.get("source") != "commit" or a.count(".") != 1:
        continue
    checked += 1
    msg = subprocess.run(["git", "-C", sys.argv[2], "log", "-1", "--format=%B", c["evidence"]],
                         capture_output=True, text=True, check=True).stdout
    if not re.search(r"§ ?%s(?![0-9])" % re.escape(a), msg):
        bad.append("%s via %s" % (a, c["evidence"][:12]))
print("checked=%d bad=%s" % (checked, ",".join(bad)))
sys.exit(1 if bad else 0)
PY
  TWOSEG_RC=$?
  if [ "$TWOSEG_RC" -eq 0 ]; then ok "R8-F1 real data: every two-segment commit citation for $ITEM_ID is spelled with a section sign in its commit ($(cat "$TMP/twoseg.out"))"
  else bad "R8-F1 real data: two-segment citation(s) with no section sign in the commit: $(cat "$TMP/twoseg.out") $(cat "$TMP/twoseg.err")"; fi
fi

# --- Step D: behaviour regression checks on a SYNTHETIC repository (R8 F1-F4, F10-F14, F17) ---
# Each check drives the REAL tool through its real CLI against a small git repository built here,
# with exact expected citation sets per source. The same harness is re-run in Step E against
# mutated copies of the tool; a mutation that leaves every check green is an unguarded behaviour.
FX_ROOT="$TMP/fx"
mkdir -p "$FX_ROOT"
python3 - "$FX_ROOT" > "$TMP/fx_build.out" 2>&1 <<'PY'
import os, sqlite3, subprocess, sys, json
root = sys.argv[1]
repo = os.path.join(root, "repo")
os.makedirs(repo)
env = dict(os.environ, GIT_AUTHOR_NAME="fx", GIT_AUTHOR_EMAIL="fx@example.invalid",
           GIT_COMMITTER_NAME="fx", GIT_COMMITTER_EMAIL="fx@example.invalid",
           GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
def git(*a, date="2026-01-01T00:00:00"):
    e = dict(env, GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
    return subprocess.run(["git", "-C", repo] + list(a), env=e, check=True, capture_output=True, text=True).stdout
git("init", "-q", "-b", "main")
def commit(msg, date="2026-01-01T00:00:00"):
    git("commit", "-q", "--allow-empty", "-m", msg, date=date)
    return git("rev-parse", "HEAD").strip()
# Root commit: no item id at all (so deleting its object breaks `git log` part-way, F3).
root_sha = commit("init: fixture root")
commit("fix(ATM-1): repair widget per §11.4.108\n\nAlso a 5.1/7.1 channel layout, the §9.1 rule, and release 1.2.1.")
commit("close ATM-2 widget, reopen ATM-1 (ATM-2 root cause per 11.4.13)\n\nATM-1: residual per 11.4.6\nATM-2 detail 11.4.1")
commit("docs: digest\n\ntally ATM-1 x3 per 11.4.143")
commit("fix(ATM-1): boundary decoys 111.4.200 and 11.4.2000")
commit("fix(ATM-10): unrelated per §11.4.77")
commit("chore: misc per 11.4.5\n\nRefs: ATM-1")
commit("fix(ATM-1): late per §11.4.99", date="2030-01-01T00:00:00")
os.makedirs(os.path.join(repo, "docs", "issues", "ATM-1"))
with open(os.path.join(repo, "docs", "issues", "ATM-1", "Reopens.md"), "w", encoding="utf-8") as fh:
    fh.write("reopened per §11.4.30\n")
with open(os.path.join(repo, "docs", "Fixed.md"), "w", encoding="utf-8") as fh:
    fh.write("# Fixed\n\n## [ATM-1] first fix\ncites 11.4.20, release 1.2.1\n### Root cause\ncites 11.4.21\n"
             "## [ATM-3] other\nmentions ATM-1 and 11.4.22\n# Later part\n## [ATM-1] reopened and re-fixed\n"
             "cites 11.4.23\n# Appendix\nstray 11.4.24\n")
db = sqlite3.connect(os.path.join(repo, "docs", "workable_items.db"))
db.execute("CREATE TABLE items (atm_id TEXT, current_location TEXT, description TEXT, closure_criteria TEXT, body_md TEXT, forensic_anchor TEXT)")
db.executemany("INSERT INTO items VALUES (?,?,?,?,?,?)", [
    ("ATM-1", "Fixed", "closed per 11.4.40", None, None, None),
    ("ATM-5", "Issues", "open per 11.4.41", None, None, None),
    ("ATM-6", None, "unknown location per 11.4.42", None, None, None),
])
db.commit(); db.close()
rev = os.path.join(root, "reviews"); os.makedirs(rev)
json.dump({"schema": "review-record/v1", "item_id": "ATM-1", "substrate_evidence": "per 11.4.50",
           "reviewer_mutations": [{"note": "mutation per 11.4.51"}], "findings": []},
          open(os.path.join(rev, "rec1.json"), "w"))
json.dump({"schema": "other/v1", "item_id": "ATM-1", "substrate_evidence": "foreign 11.4.52"},
          open(os.path.join(rev, "foreign.json"), "w"))
badrev = os.path.join(root, "reviews_corrupt"); os.makedirs(badrev)
open(os.path.join(badrev, "trunc.json"), "w").write('{"schema": "review-record/v1", "item_id": "ATM-1", "substr')
ids = ["7.1", "9.1", "11.4", "11.4.1", "11.4.5", "11.4.6", "11.4.13", "11.4.20", "11.4.21", "11.4.22",
       "11.4.23", "11.4.24", "11.4.30", "11.4.40", "11.4.41", "11.4.42", "11.4.50", "11.4.51", "11.4.52",
       "11.4.77", "11.4.99", "11.4.108", "11.4.143", "11.4.200"]
with open(os.path.join(root, "index.yaml"), "w") as fh:
    fh.write("anchors:\n" + "".join("- id: '%s'\n  title: t\n" % i for i in ids))
# A copy of the repository whose ROOT commit object is deleted: `git log` fails part-way (F3).
import shutil
broken = os.path.join(root, "repo_broken")
shutil.copytree(repo, broken)
obj = os.path.join(broken, ".git", "objects", root_sha[:2], root_sha[2:])
os.unlink(obj)
# A copy whose diary is not valid UTF-8 (F10) and one whose DB has no items table (F3).
undec = os.path.join(root, "repo_undecodable"); shutil.copytree(repo, undec)
open(os.path.join(undec, "docs", "issues", "ATM-1", "Reopens.md"), "wb").write(b"per \xff\xfe 11.4.30\n")
baddb = os.path.join(root, "repo_baddb"); shutil.copytree(repo, baddb)
os.unlink(os.path.join(baddb, "docs", "workable_items.db"))
c = sqlite3.connect(os.path.join(baddb, "docs", "workable_items.db")); c.execute("CREATE TABLE other (x)"); c.commit(); c.close()
print("built")
PY
if [ "$(tail -n 1 "$TMP/fx_build.out")" = "built" ]; then ok "Step D fixture repository built"
else bad "Step D fixture repository could not be built: $(cat "$TMP/fx_build.out")"; fi

cat > "$TMP/harness.py" <<'PY'
# Behaviour harness: argv = <impl> <fixture root>. Prints PASS:/FAIL: lines; exit = FAIL count (capped).
import json, os, subprocess, sys
impl, fx = sys.argv[1], sys.argv[2]
repo, index, rev = os.path.join(fx, "repo"), os.path.join(fx, "index.yaml"), os.path.join(fx, "reviews")
out = os.path.join(fx, "h_out.json")
fails = 0
def check(cond, label):
    global fails
    print(("PASS: " if cond else "FAIL: ") + label)
    if not cond:
        fails += 1
def run(*extra, item="ATM-1", r=repo, review=rev):
    if os.path.exists(out):
        os.unlink(out)
    argv = ["python3", impl, "--item-id", item, "--repo", r, "--anchor-index", index, "--out", out]
    if review is not None:
        argv += ["--review-records", review]
    p = subprocess.run(argv + list(extra), capture_output=True, text=True)
    doc = None
    if os.path.exists(out):
        try:
            doc = json.load(open(out, encoding="utf-8"))
        except ValueError:
            doc = None
    return p.returncode, doc, p.stderr
def by_source(doc, src):
    return sorted({c["anchor_id"] for c in (doc or {}).get("citations", []) if c.get("source") == src})

rc, doc, err = run()
check(rc == 0 and doc is not None, "D0 clean run exits 0 and writes --out (rc=%s err=%s)" % (rc, err.strip()[-200:]))
commit = by_source(doc, "commit")
check(commit == sorted(["11.4.108", "9.1", "11.4.6", "11.4.5", "11.4.99"]),
      "D1 commit citations exact (F1/F2/A1/A2): %s" % commit)
check("7.1" not in commit, "D1a F1: bare two-segment '7.1' (channel layout) is not a citation")
check("9.1" in commit, "D1b F1: '§9.1' (section-sign spelling) IS a citation")
check("11.4.13" not in commit and "11.4.1" not in commit, "D1c F2: anchors on a multi-item subject line / another item's line are not credited")
check("11.4.6" in commit, "D1d F2: a line naming only this item inside a multi-item commit is credited")
check("11.4.143" not in commit, "D1e A1: a body-only mention never attributes the commit")
check("11.4.200" not in commit, "D1f A2: digit-boundary decoys 111.4.200 / 11.4.2000 never yield 11.4.200")
check("11.4.77" not in commit, "D1g: ATM-10 is not ATM-1")
check(by_source(doc, "diary") == ["11.4.30"], "D2 diary citations exact: %s" % by_source(doc, "diary"))
check(by_source(doc, "review") == ["11.4.50", "11.4.51"], "D3 review citations exact (F10 schema check, F14 dict mutations): %s" % by_source(doc, "review"))
check(by_source(doc, "closure") == sorted(["11.4.20", "11.4.21", "11.4.23", "11.4.40"]),
      "D4 closure citations exact (F11 every owning section, level-1 boundary; A5 filter): %s" % by_source(doc, "closure"))
st = (doc or {}).get("source_status", {})
check(st == {"commit": "ok", "diary": "ok", "review": "ok", "closure": "ok"}, "D5 source_status all ok: %s" % st)
check(doc is not None and not doc.get("BLIND"), "D5a clean run is not BLIND")

rc, doc, err = run("--as-of", "2029-12-31")
check(rc == 0 and "11.4.99" not in by_source(doc, "commit") and "11.4.108" in by_source(doc, "commit"),
      "D6 A4: --as-of excludes the 2030 commit only (rc=%s commit=%s)" % (rc, by_source(doc, "commit")))

rc, doc, _ = run(item="ATM-5", review=None)
check(rc == 0 and by_source(doc, "closure") == [], "D7 A3: an open (Issues) DB row is not closure evidence: %s" % by_source(doc, "closure"))
rc, doc, _ = run(item="ATM-6", review=None)
check(rc == 0 and by_source(doc, "closure") == [], "D8 F12: a NULL-location DB row is not closure evidence: %s" % by_source(doc, "closure"))

rc, doc, _ = run(review=None)
check(rc == 0 and (doc or {}).get("source_status", {}).get("review") == "not_supplied",
      "D9 no --review-records: rc 0 and review status explicitly 'not_supplied' (rc=%s status=%s)" % (rc, (doc or {}).get("source_status")))

for label, kw in (("F3 git log fails part-way (root object deleted)", {"r": os.path.join(fx, "repo_broken")}),
                  ("F3 DB query fails (no items table)", {"r": os.path.join(fx, "repo_baddb")}),
                  ("F10 diary not valid UTF-8", {"r": os.path.join(fx, "repo_undecodable")}),
                  ("F3/F10 corrupt review record", {"review": os.path.join(fx, "reviews_corrupt")}),
                  ("F3 --review-records path does not exist", {"review": os.path.join(fx, "no_such_dir")})):
    rc, doc, err = run(**kw)
    errs = (doc or {}).get("source_errors") or []
    check(rc == 4 and doc is not None and doc.get("BLIND") is True and len(errs) >= 1,
          "D10 %s: exit 4, --out marked BLIND with source_errors (rc=%s doc=%s errors=%s)" % (label, rc, doc is not None, errs))

for bad_id in ("", "  "):
    rc, doc, _ = run(item=bad_id)
    check(rc == 2 and doc is None, "D11 F13: --item-id %r is a usage error, exit 2, nothing written (rc=%s)" % (bad_id, rc))

rc, doc, err = run("--determinism-check")
rc2, doc2, _ = run()
check(rc == 0 and doc is not None and doc2 is not None and doc.get("body_hash") == doc2.get("body_hash"),
      "D12 --determinism-check exits 0 and its body equals a plain run's body")
sys.exit(min(fails, 100))
PY

python3 "$TMP/harness.py" "$IMPL" "$FX_ROOT" > "$TMP/harness_real.out" 2>&1
HRC=$?
sed 's/^/  /' "$TMP/harness_real.out"
if [ "$HRC" -eq 0 ]; then ok "Step D behaviour checks: all pass against the real tool"
else bad "Step D behaviour checks: $HRC check(s) failed against the real tool (see lines above)"; fi

# --- Step E: paired mutations (R8 F4: A1-A5 adopted verbatim, plus this round's own) ---
# Each mutation is a one-place source substitution applied to a COPY of the tool under $TMP (never
# next to the real file). The substitution target must occur exactly once, so a mutation can never
# silently become a no-op when the source moves. The Step D harness must then FAIL at least one check.
MUT_DIR="$TMP/mut"
mkdir -p "$MUT_DIR/context"
ln -s "$HERE/../lib" "$MUT_DIR/lib"
cat > "$TMP/mutate.py" <<'PY'
import sys
src, dst, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(src, encoding="utf-8").read()
n = text.count(old)
if n != 1:
    print("target occurs %d times (must be exactly 1): %r" % (n, old)); sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
PY
mutate() { # mutate <name> <old> <new>
  name=$1
  if ! python3 "$TMP/mutate.py" "$IMPL" "$MUT_DIR/context/anchor_citations.py" "$2" "$3" > "$TMP/mut_apply.out" 2>&1; then
    bad "mutation $name could not be applied: $(cat "$TMP/mut_apply.out")"
    return
  fi
  python3 "$TMP/harness.py" "$MUT_DIR/context/anchor_citations.py" "$FX_ROOT" > "$TMP/mut_$name.out" 2>&1
  n=$?
  if [ "$n" -gt 0 ]; then ok "mutation $name caught ($n check(s) failed, first: $(grep -m1 '^FAIL' "$TMP/mut_$name.out" | cut -c1-120))"
  else bad "mutation $name SURVIVED: every Step D check still passes"; fi
}
NL='
'
mutate A1_no_ownership_gate "        if not owners:${NL}            stats[\"body_only_skipped\"] += 1${NL}            continue" "        if not owners:${NL}            owners = {item_key}"
mutate A2_truncating_tokenizer '_NUMERIC_RUN_RE = re.compile(r"(?<![0-9])[0-9]+(?:\.[0-9]+)*(?![0-9])")' '_NUMERIC_RUN_RE = re.compile(r"[0-9]{1,2}(?:\.[0-9]{1,3}){1,3}")'
mutate A3_open_rows_are_closure "        if loc not in _CLOSED_LOCATIONS:${NL}            continue" "        if False:${NL}            continue"
mutate A4_ignore_as_of '    if as_of:' '    if False:'
mutate A5_fixed_md_unfiltered 'for a in _filter_live(_extract_tokens(text), live_ids)]  # closure/Fixed.md' 'for a in _extract_tokens(text)]  # closure/Fixed.md'
mutate M6_two_segment_without_section_sign '    return _SECTION_SIGN_RE.search(text[max(0, start - 2):start]) is not None' '    return True'
mutate M7_multi_owner_scans_whole_message '        if len(owners) > 1:' '        if False:'
mutate M8_source_error_exits_zero '    rc = _emit(body, run_meta, a.out, code=4 if source_errors else 0)' '    rc = _emit(body, run_meta, a.out, code=0)'
mutate M9_fixed_md_first_section_only "                sections.append(section)${NL}                section = None" "                sections.append(section)${NL}                break"
mutate M10_null_location_closed '_CLOSED_LOCATIONS = ("fixed",)' '_CLOSED_LOCATIONS = ("fixed", "")'
mutate M11_empty_item_id_accepted '    if not item_id or item_id != item_id.strip() or any(ch.isspace() for ch in item_id):' '    if False:'
mutate M12_review_schema_unchecked '        if doc.get("schema") != _REVIEW_SCHEMA:' '        if False:'
mutate M13_diary_lossy_decode '    text, err = _read_text_strict(path)  # diary' '    text, err = open(path, encoding="utf-8", errors="replace").read(), None  # diary'

# R8 F17: the self-check must be able to fail. The A2 truncating tokenizer, on its own, must make the
# tool refuse with exit 3 (self-check) on the fixture -- and the SAME mutant with the self-check
# call removed must not, proving the exit 3 comes from the self-check and not from something else.
if python3 "$TMP/mutate.py" "$IMPL" "$TMP/a2.py" '_NUMERIC_RUN_RE = re.compile(r"(?<![0-9])[0-9]+(?:\.[0-9]+)*(?![0-9])")' '_NUMERIC_RUN_RE = re.compile(r"[0-9]{1,2}(?:\.[0-9]{1,3}){1,3}")' >/dev/null 2>&1 \
   && cp "$TMP/a2.py" "$MUT_DIR/context/anchor_citations.py"; then
  python3 "$MUT_DIR/context/anchor_citations.py" --item-id ATM-1 --repo "$FX_ROOT/repo" --anchor-index "$FX_ROOT/index.yaml" --out "$TMP/a2.json" 2>"$TMP/a2.err"
  A2RC=$?
  if python3 "$TMP/mutate.py" "$TMP/a2.py" "$MUT_DIR/context/anchor_citations.py" '    self_check_err = _self_check(live_ids)' '    self_check_err = None' >/dev/null 2>&1; then
    python3 "$MUT_DIR/context/anchor_citations.py" --item-id ATM-1 --repo "$FX_ROOT/repo" --anchor-index "$FX_ROOT/index.yaml" --out "$TMP/a2b.json" 2>/dev/null
    A2NRC=$?
  else A2NRC=x; fi
  if [ "$A2RC" -eq 3 ] && [ "$A2NRC" != 3 ]; then ok "F17: self-check refuses the truncating tokenizer with exit 3 (and only the self-check does: rc without it=$A2NRC)"
  else bad "F17: self-check did not catch the truncating tokenizer (rc=$A2RC, rc without self-check=$A2NRC): $(cat "$TMP/a2.err")"; fi
else
  bad "F17: could not build the A2 / self-check mutants"
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
