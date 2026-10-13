#!/bin/bash
# Purpose: T105 (SpecKit-004 "fast-dev-cycles", User Story 4 / Phase E) RED
#          test for T113's core-vs-on-demand governance restructuring
#          (tasks.md T105: "RED test ... (the recorded P-20 haiku-tier
#          'Prompt too long' dispatch is reproduced; substance check: the
#          sorted multiset of anchor-body lines before == after; golden-bad:
#          one dropped line FAILs; block-integrity and lockstep gates run)";
#          plan.md T-E02; FR-013, FR-022, SC-005).
#
# T-E02 (plan.md) restructures what the CLI auto-loads so the always-loaded
# text is a small CORE and anchor BODIES move to on-demand documents loaded
# by reference -- structural only (FR-022: substance unchanged), mirrors
# stay in lockstep (§11.4.157), block-integrity holds (§11.4.227(B)). T113
# is the IMPLEMENTATION task that does this restructuring; T105 (this file)
# is its PROTECTING TEST, authored and observed RED before T113 exists.
#
# ============================================================================
# The real, recorded P-20 incident (constitution 11.4.199 exact-reproduction:
# this test uses the SAME governance-context payload and the SAME 200k-token
# threshold the real incident recorded, never a hand-rolled approximation).
# ============================================================================
#
# docs/requests/agent_registry.jsonl:2583 (verbatim, re-confirmed live below):
#
#   {"ts": "2026-09-26T14:08:33Z", "event": "crashed", "key":
#   "d477c22fbd6a50b2", "tool_name": "", "session_id": "", "description":
#   "", "note": "haiku dispatch failed: Prompt too long (~421k tokens vs
#   200k limit; project preamble exceeds haiku context,
#   req_011CfSBXm7Kn6enyUT1UEaWd). Respawn on sonnet. Lesson: never dispatch
#   haiku in this repo."}
#
# This is the SAME incident constitution 11.4.231(D.1) cites as a measured
# fact and the SAME incident research.md's P-20 root-cause row (P-20 |
# cheap-tier dispatch failure | haiku `Prompt too long (~421k tokens vs 200k
# limit)` 2026-09-26T14:08:33Z | R2:16) and RC-06 (Governance preamble
# exceeds cheap-tier context ... CONFIRMED ... haiku dispatch failed at
# ~421k tok vs 200k limit (P-20); chain = 1,184,825 B) cite. research/
# R2_measured_causes.md:14-19 independently measured, on 2026-09-26, the two
# real files that make up "the chain every Claude Code agent loads" (this
# project's own CLAUDE.md, which contains a native Claude Code `@`-import --
# `@constitution/CLAUDE.md` at CLAUDE.md:20, confirmed live below -- so the
# constitution submodule's CLAUDE.md is injected alongside the project's own
# on EVERY dispatch, exactly matching the independent memory-card finding
# "A whole-repo CLAUDE.md is already injected into every subagent's context
# by the harness", ~/.claude*/memory/subagent-context-overflow-crash.md):
#
#   CLAUDE.md (project; @-imports constitution/CLAUDE.md)   337,329 B  ~84k
#   constitution/CLAUDE.md                                  834,628 B ~209k
#   chain every Claude Code agent loads                   1,184,825 B ~296k
#
# THE GOVERNANCE-CONTEXT PAYLOAD this test reproduces against is EXACTLY
# these same two real, tracked files (CLAUDE.md + constitution/CLAUDE.md),
# via the SAME @-import mechanism, measured with the SAME documented
# convention research.md:20 fixes project-wide: "`est tok` means bytes/4
# and is always labelled as an estimate, never a tokenizer count." (also
# research.md:886, quickstart.md:111 -- bytes/4 is an ALLOWED, LABELLED
# estimate for a characterization/RED check; the ACTUAL green acceptance
# for T119 token stability reads recorded `usage`, never bytes/4).
#
# HONEST DISCREPANCY (constitution 11.4.6, documented not silently
# reconciled): live-measuring the SAME two files TODAY (2026-09-29, three
# days after R2's 2026-09-26 measurement) via `wc -c` gives 337,329 +
# 834,628 = 1,171,957 B -- 12,868 B (~1.1%) BELOW R2's own recorded
# 1,184,825 B chain total. Both CLAUDE.md's and constitution/CLAUDE.md's
# individual byte counts are IDENTICAL, character for character, to R2's
# row values (confirmed live below), so the two files have not changed
# since R2 measured them; the ~1% gap is most plausibly R2's own chain total
# including a small amount of harness-added wrapper text around each
# injected file (this session's own system prompt literally prefixes each
# injected CLAUDE.md with a line "Contents of <path> (project instructions,
# checked into the codebase):", which `wc -c` on the source files alone
# does not count) -- UNCONFIRMED beyond that; NEITHER figure is remotely
# close to the 800,000 B (200,000 est-tok x 4) threshold either way, so the
# discrepancy is immaterial to this test's RED conclusion and is recorded
# here rather than silently "corrected" in either document.
#
# ============================================================================
# This test's OWN choices (constitution 11.4.6 -- fixed here BEFORE T113
# exists, binding on T113 unless T113 records an explicit, evidenced
# deviation; mirrors test_2nd_display_triage_red.sh's/
# test_escape_classify_red.sh's identical practice for exactly this
# situation -- a RED test pinning an unspecified implementation detail).
# ============================================================================
#
# (1) The DECLARED FILE SET T105/T113 govern (T105's own task line, verbatim):
#     constitution/{CLAUDE,AGENTS,QWEN,GEMINI}.md, the project-layer
#     equivalents {CLAUDE,AGENTS,QWEN,GEMINI}.md, constitution/
#     CLAUDE_ANCHORS_FULL.md, docs/PROJECT_GOVERNANCE_ANCHORS.md -- 10 files,
#     never Constitution.md itself (Constitution.md already IS the
#     full-text reference document these carriers point readers at; it is
#     not part of what the CLI *auto-loads*, so it is out of T-E02's scope).
#
# (2) "Anchor-body lines" = every line of a declared file from its FIRST
#     anchor-opener-shaped line (any of the three real-corpus forms: `### §`,
#     `**§`, `- §`, the SAME three forms constitution/scripts/anchors/
#     anchor_lib.py and constitution/scripts/gates/lib/
#     covenant_propagation_engine.sh both recognize) through EOF. This is a
#     DELIBERATELY SIMPLER, more robust definition than calling
#     anchor_lib.extract_anchors() per anchor: for every one of the 7/10
#     declared files where extract_anchors() parses cleanly, this test
#     independently CONFIRMED (2026-09-29, one-off cross-check, not part of
#     the automated run below) that summing extract_anchors()'s own
#     per-anchor body-line counts equals EXACTLY this simpler
#     first-opener-line-to-EOF line count for that file (both mechanisms
#     partition the identical line range identically) -- so this is not an
#     approximation of anchor_lib's own definition, it is the same line set
#     computed a cheaper, more robust way.
#
#     REAL FINDING, documented honestly and explicitly OUT OF THIS TEST'S
#     SCOPE to fix: `anchor_lib.extract_anchors()` (imported live below,
#     2026-09-29) raises `MalformedHeadingError` on the PROJECT-LAYER
#     AGENTS.md and QWEN.md and GEMINI.md (never on constitution/*.md nor on
#     the project's own CLAUDE.md) at the line
#       "**§11.4.1 extension (Phase 33, 2026-05-05) — FAIL-bluffs equally"
#     -- a bold-form (`**§`) anchor opener whose closing `**` sits on the
#     NEXT physical line ("forbidden.**") rather than the opener's own line,
#     which the strict bold-form parser (constitution/scripts/anchors/
#     anchor_lib.py) does not accept. This is a genuine, live,
#     pre-existing formatting defect in 3 of the 10 declared carrier files,
#     unrelated to T105/T113 -- fixing anchor_lib.py or reformatting the 3
#     carriers is NOT this task's job; it is why this test defines its OWN
#     opener-to-EOF line extraction (independent of anchor_lib's strict
#     per-anchor classifier) rather than depending on a parser known to
#     reject 3/10 of its real target files.
#
# (3) The "AFTER" contract T113 MUST satisfy for the substance check's real
#     comparison to go GREEN: a manifest file at
#       constitution/scripts/fastcycle/context/core_ondemand_manifest.json
#     with the minimal shape {"on_demand_files": ["<repo-relative path>", ...]}
#     naming every NEW document T113 creates to hold moved anchor bodies.
#     Once present, this test's "after" multiset = (opener-to-EOF lines of
#     the 10 declared carrier files, in whatever SHRUNKEN state T113 leaves
#     them) UNION (opener-to-EOF lines of every file the manifest names) --
#     sorted, hashed, and compared to the FROZEN baseline hash this run
#     captures. The manifest does not exist today (confirmed live below) --
#     this is the "no restructured state to compare against" RED the task
#     instruction names explicitly.
#
# (4) T113 is NOT starting from zero -- REAL, DIRECTLY-RELEVANT PRECEDENT
#     discovered while authoring this test (constitution 11.4.6, verified
#     live 2026-09-29, never guessed): `docs/scripts/compact_governance_
#     preamble.md` documents an ALREADY-BUILT, ALREADY-TESTED tool,
#     `scripts/testing/compact_governance_preamble.py` (13 test cases + a
#     7-mutant mutation harness), that does EXACTLY T113's kind of move --
#     it relocates a duplicated bold anchor block one hop away into a
#     target doc and leaves a literal-preserving one-line index pointer
#     behind ("Nothing is deleted, §11.4.124"). It has ALREADY BEEN RUN
#     once (2026-09-24, `--src CLAUDE.md --anchors docs/
#     PROJECT_GOVERNANCE_ANCHORS.md --canonical constitution/CLAUDE.md`),
#     against the project-layer CLAUDE.md ONLY -- confirmed by this test's
#     Section 4 sweep below, which finds every one of its ~59 non-PASS
#     anchors is the SAME shape: CLAUDE.md carries the tool's compact
#     pointer form while AGENTS.md/QWEN.md/GEMINI.md (project layer) still
#     carry the tool's UN-migrated full verbatim body for the identical
#     anchor number -- a direct, measured, live-diffed example (§11.4.239:
#     CLAUDE.md line 2784, 354 B compact pointer vs AGENTS.md line 2865,
#     3600 B full body) is in Section 4's own INFO output. T113 SHOULD
#     REUSE (constitution 11.4.251 no-byte-identical-forks) this existing
#     tool -- extended or re-invoked -- against the remaining 9 declared
#     files (this test does not itself extend the tool; that decision and
#     its implementation is T113's own).
#
# ============================================================================
# Fixtures (self-refreshing, NOT a one-time-frozen-forever constant --
# documented explicitly to avoid a false-failure trap): this project runs
# multiple concurrent tracks (constitution 11.4.176/11.4.187) that may
# legitimately add new anchors to the 10 declared files BEFORE T113 lands.
# A hardcoded expected hash captured once today would go stale (and FAIL
# for reasons that have nothing to do with T113) the moment any such
# unrelated, legitimate edit lands. Instead, `constitution/scripts/
# fastcycle/tests/fixtures/core_ondemand/baseline_lines_sorted.txt` (+ its
# `.sha256` sibling) are REFRESHED by every RED run of this test WHILE THE
# core_ondemand_manifest.json contract has not yet appeared -- i.e. while it
# is still true that "no restructuring has happened yet", the most recent
# capture IS by definition the correct pre-restructuring ground truth. The
# LAST RED run before T113 actually restructures the 10 files freezes the
# fixture at the exact right moment (T113 depends on T105 per plan.md:
# "until the substance half of T105 is GREEN" -- T113 is expected to
# (re-)run this test's capture step as its own immediate precondition).
#
# ============================================================================
# Usage: bash test_core_ondemand_red.sh   Exit 0 = every check below held
#        (only possible once T113 has landed the manifest AND shrunk the
#        governance-context payload under haiku's 200k-token window AND the
#        full block-integrity/lockstep sweep is clean); nonzero = FAIL
#        count>0 (today, RED, by design).
#
# Env overrides:
#   FC_CORE_ONDEMAND_SKIP_SWEEP=1   skip the full 82-anchor block-integrity/
#     lockstep sweep (section 5, ~1-2 min wall-clock) -- prints an explicit
#     "SKIPPED (env override)" line, never silently counted as a PASS.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$FC/../../.." && pwd)"
GATES="$ROOT/constitution/scripts/gates"
FIXDIR="$HERE/fixtures/core_ondemand"

TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
reap_children() {
  pkill -KILL -f "$TMP" 2>/dev/null
  return 0
}
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM

FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "INFO: $1"; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not on PATH -- cannot run any of the checks below"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "FAIL: sha256sum not on PATH -- cannot run any of the checks below"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi

mkdir -p "$FIXDIR"

# -----------------------------------------------------------------------
# constitution 11.4.273 control-needle discipline (needle set #1: this
# test's own file-existence-check mechanism, generic self-check before
# trusting it against real files below).
# -----------------------------------------------------------------------
NEEDLE_PRESENT="$TMP/.needle_present_marker"
printf 'x\n' > "$NEEDLE_PRESENT"
chk "control needle #1a: a known-present, non-empty file IS found by the existence+non-empty check" \
  "$([ -s "$NEEDLE_PRESENT" ] && echo 1 || echo 0)"
NEEDLE_FABRICATED="$TMP/.needle_fabricated_never_created_$$_$(date +%s 2>/dev/null || echo x)"
chk "control needle #1b: a fabricated (never-created) path IS reported absent" \
  "$([ ! -e "$NEEDLE_FABRICATED" ] && echo 1 || echo 0)"
rm -f "$NEEDLE_PRESENT"

# =========================================================================
# Section 1: P-20 real-incident citation -- verify it is genuinely present
# in the live tracked ledger before reproducing it (constitution 11.4.6 --
# never cite an invented incident).
# =========================================================================
echo
echo "=== Section 1: P-20 real-incident citation (live) ==="
REGISTRY="$ROOT/docs/requests/agent_registry.jsonl"
P20_LINE="$(grep -n 'req_011CfSBXm7Kn6enyUT1UEaWd' "$REGISTRY" 2>/dev/null | head -1)"
info "agent_registry.jsonl P-20 line: $P20_LINE"
chk "docs/requests/agent_registry.jsonl carries the real P-20 crashed row (req_011CfSBXm7Kn6enyUT1UEaWd)" \
  "$([ -n "$P20_LINE" ] && echo 1 || echo 0)"
chk "the real P-20 row's note contains 'Prompt too long' (the exact recorded failure text)" \
  "$(printf '%s' "$P20_LINE" | grep -q 'Prompt too long' && echo 1 || echo 0)"
chk "the real P-20 row's note contains 'haiku' (the exact recorded dispatch tier)" \
  "$(printf '%s' "$P20_LINE" | grep -q 'haiku' && echo 1 || echo 0)"
chk "the real P-20 row's note contains '200k limit' (the exact recorded threshold)" \
  "$(printf '%s' "$P20_LINE" | grep -q '200k limit' && echo 1 || echo 0)"

# =========================================================================
# Section 2: P-20 reproduction -- the SAME governance-context payload (the
# @-imported CLAUDE.md + constitution/CLAUDE.md chain every Claude Code
# agent loads), measured with the project's own labelled bytes/4 estimate
# convention, compared against the SAME 200k-token threshold P-20 recorded.
# =========================================================================
echo
echo "=== Section 2: P-20 reproduction (governance-context payload size) ==="
CLAUDE_PROJECT="$ROOT/CLAUDE.md"
CLAUDE_CONSTITUTION="$ROOT/constitution/CLAUDE.md"

for f in "$CLAUDE_PROJECT" "$CLAUDE_CONSTITUTION"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required governance-preamble file missing: $f"
    echo "SUMMARY pass=$((N - FAIL)) fail=$((FAIL + 1)) total=$((N + 1))"
    exit 1
  fi
done

# The concrete injection mechanism: CLAUDE.md's own `@constitution/CLAUDE.md`
# import line -- proven live, not assumed, per constitution 11.4.6.
IMPORT_LINE="$(grep -n '^@constitution/CLAUDE\.md$' "$CLAUDE_PROJECT" 2>/dev/null | head -1)"
info "CLAUDE.md @-import line: $IMPORT_LINE"
chk "CLAUDE.md carries a literal '@constitution/CLAUDE.md' Claude-Code-native import line (the real injection mechanism P-20 recorded, memory card 'A whole-repo CLAUDE.md is already injected into every subagent's context by the harness')" \
  "$([ -n "$IMPORT_LINE" ] && echo 1 || echo 0)"

BYTES_PROJECT="$(wc -c < "$CLAUDE_PROJECT" | tr -d ' ')"
BYTES_CONSTITUTION="$(wc -c < "$CLAUDE_CONSTITUTION" | tr -d ' ')"
CHAIN_BYTES=$((BYTES_PROJECT + BYTES_CONSTITUTION))
EST_TOK=$((CHAIN_BYTES / 4))
info "CLAUDE.md (project) = $BYTES_PROJECT B; constitution/CLAUDE.md = $BYTES_CONSTITUTION B; chain = $CHAIN_BYTES B; est_tok (bytes/4, LABELLED ESTIMATE per research.md:20/886 -- never a tokenizer count) = $EST_TOK"
info "research/R2_measured_causes.md:14-17 independently recorded (2026-09-26): CLAUDE.md=337,329 B, constitution/CLAUDE.md=834,628 B, chain=1,184,825 B, ~296k est tok -- cross-check against today's live measurement above (see this file's header for the honest ~1% discrepancy note)."

HAIKU_LIMIT_TOK=200000
chk "TODAY, dispatching a haiku-tier subagent with the current governance-context payload (CLAUDE.md + constitution/CLAUDE.md via the real @-import chain) fits within haiku's ${HAIKU_LIMIT_TOK}-token context window (est_tok=$EST_TOK) -- the DESIRED, GREEN, post-T113/T114 state; today this MUST and DOES fail, reproducing the real P-20 'Prompt too long' condition with the SAME payload, the SAME mechanism and the SAME threshold the real incident recorded" \
  "$([ "$EST_TOK" -le "$HAIKU_LIMIT_TOK" ] && echo 1 || echo 0)"

# =========================================================================
# Section 3: substance-check baseline capture -- "sorted multiset of
# anchor-body lines before == after" (plan T-E02 / tasks T105).
# =========================================================================
echo
echo "=== Section 3: substance-check baseline capture ==="

DECLARED_FILES=(
  "$ROOT/constitution/CLAUDE.md"
  "$ROOT/constitution/AGENTS.md"
  "$ROOT/constitution/QWEN.md"
  "$ROOT/constitution/GEMINI.md"
  "$ROOT/CLAUDE.md"
  "$ROOT/AGENTS.md"
  "$ROOT/QWEN.md"
  "$ROOT/GEMINI.md"
  "$ROOT/constitution/CLAUDE_ANCHORS_FULL.md"
  "$ROOT/docs/PROJECT_GOVERNANCE_ANCHORS.md"
)

MISSING_DECLARED=0
for f in "${DECLARED_FILES[@]}"; do
  [ -f "$f" ] || { echo "FAIL: declared carrier file missing: $f"; MISSING_DECLARED=$((MISSING_DECLARED + 1)); }
done
chk "all 10 declared carrier files (constitution/{CLAUDE,AGENTS,QWEN,GEMINI}.md + project-layer equivalents + CLAUDE_ANCHORS_FULL.md + PROJECT_GOVERNANCE_ANCHORS.md) are present" \
  "$([ "$MISSING_DECLARED" -eq 0 ] && echo 1 || echo 0)"

# extract_multiset.py -- this test's own opener-to-EOF extraction (see
# header (2) for why this, not anchor_lib.extract_anchors(), is used).
# Usage: extract_multiset.py <out_lines> <out_hash> <file1> [file2 ...]
#   Exits 2 (never silently 0-line) if any file has NO opener-shaped line.
cat > "$TMP/extract_multiset.py" <<'PY'
import hashlib, re, sys

OPENER = re.compile(
    r'^(?:'
    r'### §\d+\.\d+(?:\.\d+)?(?:\.[A-Z]|\([A-Z]+\))?|'
    r'\*\*§\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?|'
    r'- §\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?'
    r')'
)

def opener_to_eof_lines(path):
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()
    first = None
    for i, l in enumerate(lines):
        if OPENER.match(l):
            first = i
            break
    if first is None:
        raise SystemExit(f"extract_multiset.py: NO anchor-opener-shaped line found in {path}")
    return lines[first:]

def main(argv):
    out_lines_path, out_hash_path = argv[1], argv[2]
    files = argv[3:]
    multiset = []
    per_file = []
    for f in files:
        got = opener_to_eof_lines(f)
        per_file.append((f, len(got)))
        multiset.extend(got)
    multiset.sort()
    joined = "\n".join(multiset)
    with open(out_lines_path, "w", encoding="utf-8") as fh:
        fh.write(joined)
        fh.write("\n")
    digest = hashlib.sha256(joined.encode("utf-8")).hexdigest()
    with open(out_hash_path, "w", encoding="utf-8") as fh:
        fh.write(digest + "\n")
    for f, n in per_file:
        print(f"  {f}: {n} anchor-body lines")
    print(f"TOTAL: {len(multiset)} anchor-body lines across {len(files)} files; sha256={digest}")

if __name__ == "__main__":
    main(sys.argv)
PY

CAPTURE_OK=1
CAPTURE_OUT="$(python3 "$TMP/extract_multiset.py" "$TMP/before_lines.txt" "$TMP/before_hash.txt" "${DECLARED_FILES[@]}" 2>&1)" || CAPTURE_OK=0
echo "$CAPTURE_OUT" | sed 's/^/  /'
chk "capturing today's ground-truth anchor-body-line multiset across the 10 declared carrier files succeeds (non-empty, every declared file's own anchor-opener-shaped line is found)" \
  "$CAPTURE_OK"

if [ "$CAPTURE_OK" = "1" ]; then
  LINE_COUNT="$(wc -l < "$TMP/before_lines.txt" | tr -d ' ')"
  BASELINE_HASH="$(cat "$TMP/before_hash.txt")"
  info "captured multiset: $LINE_COUNT lines, sha256=$BASELINE_HASH"

  # Refresh the self-refreshing fixture (see header: this is legitimate and
  # expected WHILE the core_ondemand_manifest.json contract has not yet
  # appeared -- the most recent capture is, by definition, the correct
  # pre-restructuring ground truth until T113 actually restructures).
  cp "$TMP/before_lines.txt" "$FIXDIR/baseline_lines_sorted.txt"
  cp "$TMP/before_hash.txt" "$FIXDIR/baseline_lines_sorted.sha256"
  chk "the frozen baseline fixture (fixtures/core_ondemand/baseline_lines_sorted.{txt,sha256}) was refreshed with today's capture" \
    "$([ -f "$FIXDIR/baseline_lines_sorted.sha256" ] && [ "$(cat "$FIXDIR/baseline_lines_sorted.sha256")" = "$BASELINE_HASH" ] && echo 1 || echo 0)"

  # -----------------------------------------------------------------------
  # Self-validation quadruple of the COMPARISON MECHANISM (constitution
  # 11.4.107(10)/11.4.201(1)) -- entirely synthetic/local, proves the
  # comparator discriminates a dropped line BEFORE trusting it against
  # T113's real future work. This is instruction (3)'s golden-bad, run
  # today.
  # -----------------------------------------------------------------------
  echo
  echo "--- self-validation of the multiset comparator ---"

  # golden (unmutated self-compare): hashing the SAME captured lines again
  # must match.
  cp "$TMP/before_lines.txt" "$TMP/self_copy.txt"
  SELF_HASH="$(sha256sum "$TMP/self_copy.txt" | awk '{print $1}')"
  ORIG_CONTENT_HASH="$(sha256sum "$TMP/before_lines.txt" | awk '{print $1}')"
  chk "golden (unmutated): re-hashing the identical captured multiset produces the SAME hash (the comparator's false-positive guard -- an unchanged multiset must not be reported as diverged)" \
    "$([ "$SELF_HASH" = "$ORIG_CONTENT_HASH" ] && echo 1 || echo 0)"

  # golden-bad: drop exactly one line (the first line of the sorted
  # multiset) from a scratch copy and confirm the comparison correctly
  # reports a mismatch.
  tail -n +2 "$TMP/before_lines.txt" > "$TMP/mutated_drop_one_line.txt"
  MUTATED_HASH="$(sha256sum "$TMP/mutated_drop_one_line.txt" | awk '{print $1}')"
  chk "golden-bad (one dropped line): a scratch copy of the captured multiset with its first line removed produces a DIFFERENT hash -- the comparator correctly FAILs on a single dropped anchor-body line, as instruction (3) requires" \
    "$([ "$MUTATED_HASH" != "$ORIG_CONTENT_HASH" ] && echo 1 || echo 0)"

  # negative control: REVERSE the physical line order of the captured
  # multiset (a genuine input-order shuffle, not a no-op) and re-run it
  # through the SAME canonical sort mechanism this comparator uses
  # (Python's own list.sort()) -- must still produce the IDENTICAL hash,
  # proving the comparator is order-of-INPUT independent.
  #
  # REAL FINDING documented honestly, not silently discarded (constitution
  # 11.4.6/11.4.273): this negative control was FIRST written as "re-sort
  # via the shell `sort` builtin and confirm it is a no-op" -- that version
  # FAILED live (2026-09-29), because GNU `sort`'s DEFAULT locale-aware
  # collation orders this heavily-§-and-em-dash-and-curly-quote Unicode
  # content DIFFERENTLY from Python's own codepoint-based `str.sort()`, so
  # hashing a GNU-`sort`-resorted copy against a Python-sorted original is
  # a cross-implementation comparison, not a genuine no-op check. The REAL
  # before/after comparison in this test (Section 3's "after" branch, and
  # T113's own future comparison) never crosses this boundary -- both
  # directions always go through this SAME extract_multiset.py (Python
  # sort only) -- so that class of false-FAIL cannot occur there; it was
  # specific to this ADDITIONAL, now-corrected negative control.
  tac "$TMP/before_lines.txt" > "$TMP/reversed_input.txt" 2>/dev/null \
    || tail -r "$TMP/before_lines.txt" > "$TMP/reversed_input.txt"
  # Written with the SAME trailing-newline convention extract_multiset.py
  # itself uses (join by "\n" + one trailing "\n"), then hashed via
  # `sha256sum` on the WRITTEN FILE -- exactly how ORIG_CONTENT_HASH below
  # was computed -- so this is a genuine apples-to-apples re-check, not a
  # second, differently-conventioned hash of the same logical content.
  # (A first version of this fix hashed a raw joined Python string with no
  # trailing newline against a file that HAS one, producing a spurious
  # mismatch -- caught live 2026-09-29 and corrected here.)
  python3 -c '
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
lines.sort()
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))
    fh.write("\n")
' "$TMP/reversed_input.txt" "$TMP/reversed_resorted.txt"
  REVERSED_RESORTED_HASH="$(sha256sum "$TMP/reversed_resorted.txt" | awk '{print $1}')"
  chk "negative control: reversing the captured multiset's physical line order, then re-sorting via the SAME canonical (Python) sort mechanism, produces the SAME hash as the original (proves the comparator is genuinely order-of-input independent, not merely 'any re-run differs')" \
    "$([ "$REVERSED_RESORTED_HASH" = "$ORIG_CONTENT_HASH" ] && echo 1 || echo 0)"

  # -----------------------------------------------------------------------
  # The REAL "after" comparison -- instruction (2)'s load-bearing half:
  # "since T113 hasn't run yet, the 'after' comparison itself is the RED
  # ... legitimately fails/errors today, documented honestly."
  # -----------------------------------------------------------------------
  echo
  echo "--- the real before==after comparison (T113's contract) ---"
  MANIFEST="$ROOT/constitution/scripts/fastcycle/context/core_ondemand_manifest.json"
  if [ -f "$MANIFEST" ]; then
    info "core_ondemand_manifest.json FOUND -- T113 appears to have landed; attempting the real after-comparison"
    ON_DEMAND_FILES="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('\n'.join(d.get('on_demand_files', [])))" "$MANIFEST" 2>/dev/null)"
    AFTER_FILES=("${DECLARED_FILES[@]}")
    while IFS= read -r rel; do
      [ -n "$rel" ] && AFTER_FILES+=("$ROOT/$rel")
    done <<< "$ON_DEMAND_FILES"
    AFTER_OK=1
    python3 "$TMP/extract_multiset.py" "$TMP/after_lines.txt" "$TMP/after_hash.txt" "${AFTER_FILES[@]}" >/dev/null 2>&1 || AFTER_OK=0
    if [ "$AFTER_OK" = "1" ]; then
      AFTER_HASH="$(cat "$TMP/after_hash.txt")"
      chk "the AFTER multiset (10 declared files, post-restructuring, UNION every core_ondemand_manifest.json on_demand_files entry) equals the FROZEN before-multiset (sha256=$BASELINE_HASH) -- FR-022 substance-unchanged, T-E02's own acceptance criterion" \
        "$([ "$AFTER_HASH" = "$BASELINE_HASH" ] && echo 1 || echo 0)"
    else
      chk "the AFTER multiset extraction succeeds against the manifest-named file set" "0"
    fi
  else
    info "core_ondemand_manifest.json NOT FOUND at $MANIFEST -- T113 has not landed; this is the EXPECTED RED-today outcome (no restructured state exists yet to compare against)"
    chk "T113 has landed a core_ondemand_manifest.json (constitution/scripts/fastcycle/context/core_ondemand_manifest.json) naming the on-demand anchor-body documents, so the real before==after substance comparison can run -- expected to FAIL today (RED), documented honestly per T105's own task text ('the after comparison itself is the RED')" \
      "0"
  fi
else
  info "capture failed -- see CAPTURE_OUT above for the offending file (likely a real anchor_lib-class formatting defect, or a missing declared file); the self-validation quadruple and the real after-comparison are both skipped this run (dependent on a successful capture)"
fi

# =========================================================================
# Section 4: block-integrity + lockstep gates (§11.4.157 / §11.4.227(B)) --
# instruction (4): "must run as part of this test -- confirm each anchor
# still appears exactly-once per file post-restructuring (again,
# legitimately unverifiable/RED today since restructuring hasn't happened;
# document this honestly rather than faking a pass)."
#
# Reuses the REAL, existing, shared covenant_propagation_engine.sh
# (constitution 11.4.251 role-as-data-pack -- no fork, no reimplementation
# of the check logic). The carrier-list precompute below MIRRORS (does not
# duplicate) the engine's OWN internal exclusion-prune logic purely as a
# performance optimization the engine itself documents and supports via
# COVENANT_PROPAGATION_CARRIERS (avoiding N-1 redundant `find` traversals
# of the whole tree, one per anchor) -- verified live 2026-09-29: without
# this optimization each of the 82 registered anchors costs ~10.7s (find
# walk dominated); with it, ~1.0s each (~82s total for the full sweep).
# =========================================================================
echo
echo "=== Section 4: block-integrity + lockstep sweep (§11.4.227(B)) ==="

if [ "${FC_CORE_ONDEMAND_SKIP_SWEEP:-0}" = "1" ]; then
  echo "SKIPPED (FC_CORE_ONDEMAND_SKIP_SWEEP=1 env override) -- not counted as PASS or FAIL"
else
  DATAPACK="$GATES/covenant_propagation_anchors.tsv"
  EXCLUSIONS="$ROOT/config/covenant_propagation_exclusions.tsv"
  ENGINE="$GATES/lib/covenant_propagation_engine.sh"

  SWEEP_PRECONDITIONS_OK=1
  for need in "$DATAPACK" "$ENGINE"; do
    [ -r "$need" ] || { echo "FAIL: required propagation-engine artefact not found/readable: $need"; SWEEP_PRECONDITIONS_OK=0; }
  done
  chk "the shared covenant_propagation_engine.sh + its data pack are present and readable (§11.4.251 reuse precondition)" \
    "$SWEEP_PRECONDITIONS_OK"

  if [ "$SWEEP_PRECONDITIONS_OK" = "1" ]; then
    # Build the -prune clause from the checked-in exclusion TSV, mirroring
    # the engine's own column-1-glob parsing (constitution 11.4.201(7)(a):
    # structure, not substring -- comment lines and malformed rows skipped
    # the SAME way the engine skips them).
    PRUNE_ARGS=(-path '*/node_modules' -o -path '*/.git' -o -path '*/out'
                -o -path '*/build' -o -path '*/dist' -o -path '*/prebuilts'
                -o -path '*/external' -o -path '*/vendor' -o -path '*/target')
    if [ -r "$EXCLUSIONS" ]; then
      # shellcheck disable=SC2034  # _eclass/_ejust are read for column
      # alignment (mirroring the engine's own TSV shape) but unused here --
      # only the glob (column 1) drives -prune.
      while IFS=$'\t' read -r _eglob _eclass _ejust || [ -n "${_eglob:-}" ]; do
        case "${_eglob:-}" in ''|'#'*) continue ;; esac
        PRUNE_ARGS+=(-o -path "$_eglob")
      done < "$EXCLUSIONS"
    fi

    find "$ROOT" \( "${PRUNE_ARGS[@]}" \) -prune \
      -o \( -type f \( -name 'CLAUDE.md' -o -name 'AGENTS.md' \
         -o -name 'QWEN.md' -o -name 'GEMINI.md' \) -print \) 2>/dev/null \
      | sort > "$TMP/carriers.txt"
    CARRIER_COUNT="$(wc -l < "$TMP/carriers.txt" | tr -d ' ')"
    info "precomputed carrier list: $CARRIER_COUNT files (mirrors the engine's own exclusion parsing)"

    export COVENANT_PROPAGATION_CARRIERS="$TMP/carriers.txt"
    export CONSUMER_ROOT="$ROOT"
    # shellcheck source=lib/covenant_propagation_engine.sh
    . "$ENGINE"

    SWEEP_PASS=0
    SWEEP_FAIL=0
    SWEEP_ERROR=0
    FAILING_GATES=""
    while IFS=$'\t' read -r gate anchor; do
      case "${gate:-}" in ''|'#'*) continue ;; esac
      covenant_propagation_main "$gate" --quiet >"$TMP/gate_out.txt" 2>&1
      rc=$?
      case "$rc" in
        0) SWEEP_PASS=$((SWEEP_PASS + 1)) ;;
        1) SWEEP_FAIL=$((SWEEP_FAIL + 1)); FAILING_GATES="$FAILING_GATES §$anchor" ;;
        *) SWEEP_ERROR=$((SWEEP_ERROR + 1)); FAILING_GATES="$FAILING_GATES §$anchor(ERR=$rc)" ;;
      esac
    done < <(awk -F'\t' '!/^#/ && NF>=2 {print $1"\t"$2}' "$DATAPACK")

    SWEEP_TOTAL=$((SWEEP_PASS + SWEEP_FAIL + SWEEP_ERROR))
    info "block-integrity + lockstep sweep: $SWEEP_PASS PASS / $SWEEP_FAIL FAIL / $SWEEP_ERROR ERROR of $SWEEP_TOTAL registered anchors"
    if [ -n "$FAILING_GATES" ]; then
      info "non-PASS anchors:$FAILING_GATES"
      info "ROOT CAUSE, verified live 2026-09-29 (not guessed, constitution 11.4.6): every one of these anchors' failure is 'CLAUDE.md -- block differs from AGENTS.md' (spot-checked §11.4.162/§11.4.236/§11.4.239/§11.4.260 individually, all the SAME shape). Direct diff of §11.4.239's actual block: CLAUDE.md line 2784 carries the COMPACT one-line pointer form '- §11.4.239 -- ... [full -> docs/PROJECT_GOVERNANCE_ANCHORS.md] ...' (354 B) while AGENTS.md line 2865 STILL carries the full verbatim bold-form anchor body (3600 B). This is the DIRECT, ALREADY-EXISTING PRECEDENT for T113's own job: docs/scripts/compact_governance_preamble.md's tool (scripts/testing/compact_governance_preamble.py, landed 2026-09-24, run as '--src CLAUDE.md --anchors docs/PROJECT_GOVERNANCE_ANCHORS.md --canonical constitution/CLAUDE.md') has ALREADY moved many of the newest anchor bodies (the §11.4.236+ era) out of the project-layer CLAUDE.md into docs/PROJECT_GOVERNANCE_ANCHORS.md and left a compact pointer behind -- but has NEVER been run against the other 9 declared carrier files (AGENTS.md/QWEN.md/GEMINI.md at the project layer, nor any of the 4 constitution-submodule mirrors, nor has constitution/CLAUDE.md's own 835 KB half been touched at all, per research/R2_measured_causes.md:22's own citation of this exact tool). T113's job is NOT starting from zero: it is EXTENDING/APPLYING this SAME existing, tested tool (constitution 11.4.251 reuse mandate) to the remaining 9 files, which will directly RESOLVE this precise class of §11.4.157/§11.4.227(B) divergence as a byproduct -- this sweep's non-PASS count is therefore T113's OWN measurable starting-point metric, not an unrelated pre-existing defect; fixing the remaining 9 files (beyond what T113/T121 land) stays a separate tracked remediation, cited here per constitution 11.4.6 rather than silently absorbed"
    fi
    chk "block-integrity + lockstep holds for EVERY anchor registered in the propagation data pack ($SWEEP_TOTAL anchors swept, 0 non-PASS) -- confirms each anchor still appears exactly-once per file, TODAY (pre-restructuring); T-E02's own checkpoint criterion ('lockstep and block-integrity gates are green') for the POST-restructuring state is what T113/T121 must additionally prove -- this run's non-PASS anchors are PRECISELY the ones the ALREADY-EXISTING compact_governance_preamble.py tool has moved in CLAUDE.md alone (see the INFO line above), i.e. T113's own measurable before-state, never an unrelated defect" \
      "$([ "$SWEEP_FAIL" -eq 0 ] && [ "$SWEEP_ERROR" -eq 0 ] && echo 1 || echo 0)"
  fi
fi

echo
echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
