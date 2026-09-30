#!/bin/bash
# Purpose : T178 (SpecKit-004 "fast-dev-cycles", Phase H / plan T-H08) RED
#           baseline for the `research` and `plan` subcommands of
#           `constitution/scripts/fastcycle/verify/plan_struct_check.py`,
#           per contract `contracts/plan-research-structural-check.md`
#           (SC-C-002/FR-003, SC-C-003/FR-004) and tasks.md's own T178 line:
#           "golden-bad fixtures each FAIL: a task with no rollback; an
#           orphan RC; an FR with no task; a recommendation with no source
#           and no 'original work' statement; research pass log with <3
#           passes; documentation below 30 pages-equivalent; a CONFIRMED row
#           still UNMEASURED after the T-A11 checkpoint without a named
#           permanent gap; negative control: the current documents PASS."
#
# THE GAP (verified directly, 2026-09-30, before writing a single fixture
# below -- constitution 11.4.6): `plan_struct_check.py` (T046's file) exists
# and its `causes` subcommand is implemented + GO-reviewed + committed (see
# sibling test_plan_struct_causes_red.sh), but `main()`'s subparser table
# registers ONLY `causes`:
#
#   $ python3 verify/plan_struct_check.py research --log r.md --plan p.md --out /tmp/r.json
#   usage: plan_struct_check.py [-h] {causes} ...
#   plan_struct_check.py: error: argument cmd_name: invalid choice: 'research'
#     (choose from causes)
#   rc=2
#   $ python3 verify/plan_struct_check.py plan --plan p.md --causes c.json --out /tmp/p.json
#   usage: plan_struct_check.py [-h] {causes} ...
#   plan_struct_check.py: error: argument cmd_name: invalid choice: 'plan'
#     (choose from causes)
#   rc=2
#
# (reproduced live below via a real invocation of every fixture, never
# assumed from this header's prose). Both `research` and `plan` are named,
# in the tool's own module docstring, as landing in "T159 and T179" -- a
# LATER, SEPARATE implementation task (T179's own tasks.md line: "Implement
# `plan_struct_check.py research` and `plan` ... until T178 is GREEN") --
# this file's author never implements either. Because the whole subcommand
# is absent, EVERY invocation below -- all seven golden-bad fixtures AND the
# negative control against the real, current documents -- returns the SAME
# rc=2 "invalid choice" signature today: the honest current RED state is
# uniform tool-absence, not a selective per-fixture structural finding (the
# tool cannot yet distinguish "this document is clean" from "this
# subcommand does not exist"; see section (9) below for why that matters).
#
# WHICH SUBCOMMAND EACH FIXTURE TARGETS (contract clause -> subcommand,
# read directly off the contract's own Invocation line comments and
# tasks.md T179's own wording, never guessed):
#   1. task with no rollback              -> `plan`     (SC-C-003/FR-004)
#   2. orphan RC (no task removes/measures it) -> `plan` (SC-C-003 bipartite)
#   3. FR with no task covering it        -> `plan`     (SC-C-003 bipartite)
#   4. recommendation, no source/"original work" -> `research` (SC-C-002/FR-003)
#   5. research-pass log with <3 passes   -> `research` (SC-C-002/FR-003)
#   6. documentation below 30 pages-equivalent -> `plan` (SC-C-003 size check)
#   7. CONFIRMED row still UNMEASURED post-T-A11, no permanent gap -> `plan`
#      (the contract's Invocation line comments `plan` itself with
#      "# T-H08, T-A11" -- the T-A11 re-plan checkpoint's own re-run target
#      -- and `plan` alone takes `--causes <causes.json>` as input, the
#      artefact this clause reads `measured_share` from; `causes`'s own
#      SC-C-001 text states the SAME clause, but `causes`'s already-landed
#      `--post-a11` flag is a DIFFERENT, narrower, opt-in implementation of
#      it that this file does not exercise or assume superseded --
#      tasks.md T179's own line assigns "checks every CONFIRMED share" to
#      the research/plan implementation task, so `plan` is this fixture's
#      target here, honestly disclosed as an inference from that task line
#      plus the Invocation comment, not a verbatim contract quote).
#
# Fixtures are built INLINE, per-check, into a throwaway `mktemp -d`
# directory at runtime (this task's hard scope limit permits creating and
# editing ONLY this one test file -- no checked-in fixtures/ directory is
# added), matching the inline-heredoc-fixture convention already used by
# several siblings in this exact suite (test_disk_floor_red.sh's
# `cat > "$CFG" <<'YAML'` pattern; test_reopen_rate_red.sh's inline
# `$TMP/derive.py`), as opposed to test_plan_struct_causes_red.sh's own
# on-disk fixtures/plan_struct_causes/ directory convention (not usable
# here under this task's hard scope limit).
#
# Producer != Verifier (constitution 11.4.240): each golden-bad fixture
# below is independently self-checked -- via a small, standalone grep/awk/
# python assertion written by THIS file's author, never sharing code with
# `plan_struct_check.py` -- to prove it genuinely encodes the ONE defect it
# claims to, BEFORE that fixture is used as a RED-baseline input. This
# mirrors test_plan_struct_causes_red.sh's own `register_audit` instrument
# and test_reopen_rate_red.sh's own `derive.py` oracle: a fixture
# self-validation check, not the tool under test, and never later reused
# by, nor shared with, T179's own implementation.
#
# §11.4.273 control needle: before trusting any "subcommand absent" /
# "fixture field absent" finding below, this file first proves its own
# relative-path resolution and its own field-presence-testing mechanism
# genuinely work, by confirming a KNOWN-PRESENT sibling (lib/fc_common.py)
# resolves, and by confirming a KNOWN-PRESENT field (this file's own
# fixture's `**Serves:**` line) is found by the exact same grep this file
# later uses to claim a field is ABSENT elsewhere -- the same "prove the
# instrument can see before trusting its silence" discipline used
# throughout this suite (constitution 11.4.201(6)-(7)).
#
# HONEST BOUNDARY (constitution 11.4.6): this file does NOT know, and does
# not guess, exactly how T179's eventual `research`/`plan` implementation
# will discover "the full universe of FR-001..FR-025 / SC-001..SC-010 ids"
# for the orphan-FR bipartite check (the contract's Invocation line for
# `plan` takes no `--spec` argument) -- fixture 3 below is therefore built
# so its "orphan-FR" claim is checkable on STRUCTURE ALONE, independent of
# that open question: it declares an FR id in a scope preamble and proves,
# via its own grep, that the SAME id appears in NO task's `**Serves:**`
# field anywhere in the document -- true regardless of how the real
# universe is eventually sourced. Likewise for fixture 7's forward-
# compatible `--post-a11`-shaped flag name (T179 has not yet chosen one);
# this file passes no such flag (the subcommand is absent regardless, so it
# would not matter to the assertion below) and names the open question
# rather than inventing an answer for it.
#
# Usage : bash test_plan_struct_full_red.sh   Exit 0 = RED baseline holds
#         (both control needles pass, all seven golden-bad fixtures are
#         independently confirmed to encode their designed defect, EVERY
#         fixture's real `research`/`plan` invocation returns rc=2 with the
#         "invalid choice" signature naming the right subcommand, the
#         negative control's `causes` invocation against the real, live
#         register genuinely exits 0, and the negative control's
#         `research`/`plan` invocations against the real, live documents
#         are reported honestly -- currently ALSO rc=2, for tool-absence,
#         not for any document defect). Matches the T017/T024/T026/T025
#         sibling files' "exit 0 = RED baseline PASS" convention.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
TOOL="$FC/verify/plan_struct_check.py"
RESEARCH_LIVE="$ROOT/specs/004-fast-dev-cycles/research.md"
PLAN_LIVE="$ROOT/specs/004-fast-dev-cycles/plan.md"

fail=0
failx() { fail=1; }

WORK=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# --- §11.4.273 control needle #1: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so every finding below proves nothing"
  echo "     (§11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the checks below can be"
  echo "   trusted"
fi

# --- §11.4.273 control needle #2: this file's own field-presence grep can SEE
#     a field it should see, before it is trusted to report one ABSENT ---
NEEDLE_DOC="$WORK/_needle_doc.md"
cat > "$NEEDLE_DOC" <<'EOF'
#### T-NEEDLE -- control-needle task

- **Serves:** FR-NEEDLE-PRESENT
EOF
if grep -q '\*\*Serves:\*\*.*FR-NEEDLE-PRESENT' "$NEEDLE_DOC"; then
  echo "ok control needle #2: this file's own field-presence grep correctly"
  echo "   FINDS a field genuinely present in a synthetic control document --"
  echo "   an ABSENT-field finding elsewhere in this run can be trusted"
else
  echo "NOT ok control needle #2 FAILED: this file's own grep could not find a"
  echo "     field it planted itself -- every 'field is absent' claim below is"
  echo "     meaningless until this is fixed (§11.4.201(6)-(7))"
  failx
fi

# --- (0) The tool itself exists (T046 landed) but the specific subcommands
#         this file targets do not -- both facts proven by REAL invocation,
#         never by parsing the tool's own source as a proxy for its runtime
#         behaviour (§11.4.201(11)) ---
if [ ! -f "$TOOL" ]; then
  echo "NOT ok $TOOL is absent entirely -- even T046's already-landed \`causes\`"
  echo "     subcommand is missing; this is a bigger regression than this"
  echo "     file's own scope (research/plan) can characterise"
  failx
else
  echo "ok $TOOL exists (T046 has landed) -- the subcommand-absence checks"
  echo "   below are exercised against the REAL, current subparser table"
fi

assert_subcommand_absent() {
  # assert_subcommand_absent <label> <subcommand> -- <full invocation...>
  # Runs the real tool; asserts rc=2 and that stderr names exactly the
  # given subcommand as an invalid choice. This is the CORRECT, EXPECTED
  # RED-baseline outcome for every fixture below today (2026-09-30):
  # `research` and `plan` are both wholly absent, so no fixture's CONTENT
  # can yet be distinguished from any other's by this tool -- the finding
  # this assertion proves is tool-absence, never a structural verdict on
  # the fixture's document content (that verdict does not exist until
  # T179 lands).
  label=$1; shift
  subcmd=$1; shift
  # remaining args: the real invocation (python3 "$TOOL" <subcmd> ...)
  out_file="$WORK/_inv_out_$$_${RANDOM}"
  err_file="$WORK/_inv_err_$$_${RANDOM}"
  "$@" >"$out_file" 2>"$err_file"
  rc=$?
  if [ "$rc" -ne 2 ]; then
    echo "NOT ok $label: expected rc=2 (subcommand '$subcmd' absent), got rc=$rc"
    echo "     stdout: $(cat "$out_file" 2>/dev/null)"
    echo "     stderr: $(cat "$err_file" 2>/dev/null)"
    failx
    return
  fi
  if ! grep -q "invalid choice: '$subcmd'" "$err_file"; then
    echo "NOT ok $label: rc=2 as expected, but stderr does not name '$subcmd' as"
    echo "     the invalid choice -- stderr: $(cat "$err_file" 2>/dev/null)"
    failx
    return
  fi
  if ! grep -q 'choose from' "$err_file"; then
    echo "NOT ok $label: rc=2 and '$subcmd' named, but stderr is missing"
    echo "     argparse's usual 'choose from ...' guidance -- unexpected error"
    echo "     shape, worth re-checking by hand: $(cat "$err_file" 2>/dev/null)"
    failx
    return
  fi
  echo "ok $label: real invocation of subcommand '$subcmd' exits rc=2, stderr"
  echo "   names it an invalid choice (argparse's own 'choose from' guidance"
  echo "   present) -- the correct, current RED baseline (T179 not yet landed)"
}

# =============================================================================
# Fixture 1 -- plan: a task with no rollback plan (SC-C-003/FR-004)
# =============================================================================
F1="$WORK/f1_no_rollback"
mkdir -p "$F1"
cat > "$F1/plan.md" <<'EOF'
## Phased Implementation Plan

#### T-X01 -- fixture task with no rollback field at all

- **Removes / measures:** measures U-901.
- **Serves:** FR-901.
- **Expected saving -> measurement:** none directly (instrument).
- **Protecting tests:** RED fixture_self_check.sh; golden triple present.
- **Origin:** DEC-901; original work (no external solution found).
EOF
cat > "$F1/causes.json" <<'EOF'
{"doc": "fixture", "causes": [], "class_counts": {"stated": {}, "actual": {}}, "violations": []}
EOF
# --- independent self-check: T-X01's block genuinely has NO Rollback field ---
if grep -A20 '^#### T-X01' "$F1/plan.md" | grep -q '\*\*Rollback:\*\*'; then
  echo "NOT ok fixture 1 self-check FAILED: T-X01's block unexpectedly DOES carry"
  echo "     a Rollback field -- this fixture does not encode the intended defect"
  failx
else
  echo "ok fixture 1 self-check: T-X01's task block genuinely has no"
  echo "   **Rollback:** field anywhere in its own text (independently confirmed"
  echo "   via grep, never assumed from having typed the fixture) -- this"
  echo "   fixture genuinely encodes the 'task with no rollback plan' defect"
fi
assert_subcommand_absent "fixture 1 (no-rollback task)" plan \
  python3 "$TOOL" plan --plan "$F1/plan.md" --causes "$F1/causes.json" --out "$WORK/f1.out.json"

# =============================================================================
# Fixture 2 -- plan: an orphan RC (a cause with no task removing/measuring it)
# =============================================================================
F2="$WORK/f2_orphan_rc"
mkdir -p "$F2"
cat > "$F2/causes.json" <<'EOF'
{
  "doc": "fixture",
  "causes": [
    {"id": "RC-X01", "class": "CONFIRMED", "evidence_paths": ["fixture/evidence"],
     "measured_share": "12%", "settling_evidence": null, "removed_or_measured_by": "T-X02"}
  ],
  "class_counts": {"stated": {"CONFIRMED": 1}, "actual": {"CONFIRMED": 1}},
  "violations": []
}
EOF
cat > "$F2/plan.md" <<'EOF'
## Phased Implementation Plan

#### T-X02 -- fixture task that names a different cause entirely

- **Removes / measures:** measures U-902; RC-X99 only.
- **Serves:** FR-902.
- **Expected saving -> measurement:** none directly (instrument).
- **Rollback:** additive change, remove the added line.
- **Protecting tests:** RED fixture_self_check.sh; golden triple present.
- **Origin:** DEC-902; original work (no external solution found).
EOF
# --- independent self-check: RC-X01 is declared CONFIRMED in causes.json but
#     appears in NO task's "Removes / measures" field in plan.md (the
#     register-level "orphan cause" condition, bipartite half checked
#     against a real document per SC-C-003, distinct from `causes`'s own
#     shallower register-level-only clause (b)) ---
if grep -q 'RC-X01' "$F2/plan.md"; then
  echo "NOT ok fixture 2 self-check FAILED: RC-X01 unexpectedly DOES appear"
  echo "     somewhere in plan.md -- this fixture does not encode a genuine"
  echo "     orphan cause"
  failx
else
  if ! grep -q '"id": "RC-X01"' "$F2/causes.json" || ! grep -q '"class": "CONFIRMED"' "$F2/causes.json"; then
    echo "NOT ok fixture 2 self-check FAILED: causes.json does not declare"
    echo "     RC-X01 as CONFIRMED -- the fixture's own input is malformed"
    failx
  else
    echo "ok fixture 2 self-check: RC-X01 is declared CONFIRMED in causes.json"
    echo "   and independently confirmed absent from every task block in"
    echo "   plan.md (grep found zero occurrences) -- this fixture genuinely"
    echo "   encodes the 'orphan RC with no implementing task' defect"
  fi
fi
assert_subcommand_absent "fixture 2 (orphan RC)" plan \
  python3 "$TOOL" plan --plan "$F2/plan.md" --causes "$F2/causes.json" --out "$WORK/f2.out.json"

# =============================================================================
# Fixture 3 -- plan: an FR with no task covering it (SC-C-003 bipartite,
# the OTHER direction from fixture 2: "every FR-001..FR-025 and SC-001..
# SC-010 has >=1 task"). See this file's own header "HONEST BOUNDARY" note
# for why the universe-discovery mechanism is deliberately left open here.
# =============================================================================
F3="$WORK/f3_orphan_fr"
mkdir -p "$F3"
cat > "$F3/plan.md" <<'EOF'
## Phased Implementation Plan

**Scope of this fixture plan**: implements FR-X03, FR-X04.

#### T-X03 -- fixture task that only serves FR-X04, never FR-X03

- **Removes / measures:** measures U-903.
- **Serves:** FR-X04.
- **Expected saving -> measurement:** none directly (instrument).
- **Rollback:** additive change, remove the added line.
- **Protecting tests:** RED fixture_self_check.sh; golden triple present.
- **Origin:** DEC-903; original work (no external solution found).
EOF
cat > "$F3/causes.json" <<'EOF'
{"doc": "fixture", "causes": [], "class_counts": {"stated": {}, "actual": {}}, "violations": []}
EOF
# --- independent self-check: FR-X03 is declared in the fixture's own scope
#     preamble but never appears in any task's "**Serves:**" field, while
#     FR-X04 (the negative instance inside the SAME fixture) genuinely does
#     -- proving this check discriminates rather than always firing ---
SERVES_LINES=$(grep '\*\*Serves:\*\*' "$F3/plan.md")
if printf '%s\n' "$SERVES_LINES" | grep -q 'FR-X03'; then
  echo "NOT ok fixture 3 self-check FAILED: FR-X03 unexpectedly DOES appear in"
  echo "     a Serves field -- this fixture does not encode an orphan FR"
  failx
elif ! printf '%s\n' "$SERVES_LINES" | grep -q 'FR-X04'; then
  echo "NOT ok fixture 3 self-check FAILED: FR-X04 (the intended non-orphan"
  echo "     control inside this SAME fixture) is ALSO missing from every"
  echo "     Serves field -- this fixture's own discrimination is broken"
  failx
else
  echo "ok fixture 3 self-check: FR-X03 is declared in the fixture's scope"
  echo "   preamble but appears in NO task's **Serves:** field anywhere in the"
  echo "   document, while FR-X04 -- declared in the very same preamble --"
  echo "   genuinely IS served by T-X03; this fixture genuinely encodes an"
  echo "   orphan FR and demonstrably discriminates it from a covered one"
fi
assert_subcommand_absent "fixture 3 (orphan FR)" plan \
  python3 "$TOOL" plan --plan "$F3/plan.md" --causes "$F3/causes.json" --out "$WORK/f3.out.json"

# =============================================================================
# Fixture 4 -- research: a recommendation (DEC-nn) with no cited source and
# no "no external solution found -- original work" statement (SC-C-002/
# FR-003). Field format per the REAL research.md §3 decision-log preamble:
# "Source" is an R3-R5 URL, an internal artefact path, or the literal
# "no external solution found -- original work" (verified live against
# specs/004-fast-dev-cycles/research.md's own §3 preamble before writing
# this fixture, never invented).
# =============================================================================
F4="$WORK/f4_uncited_recommendation"
mkdir -p "$F4"
cat > "$F4/research.md" <<'EOF'
## 3. Decision log

Each decision resolves one plan-level unknown. Form: **Decision / Rationale / Alternatives
considered / Source**. "Source" is an R3-R5 URL (retrieved date, untrusted data), an internal
artefact path, or the literal "no external solution found -- original work".

### DEC-X01 -- fixture recommendation with an uncited Source field

- **Decision:** do the fixture thing.
- **Rationale:** because.
- **Alternatives considered:** (a) do nothing -- rejected.
- **Source:** TBD
EOF
cat > "$F4/plan.md" <<'EOF'
## Phased Implementation Plan

#### T-X05 -- fixture task

- **Removes / measures:** measures U-905.
- **Serves:** FR-905.
- **Expected saving -> measurement:** none directly.
- **Rollback:** additive.
- **Protecting tests:** RED fixture_self_check.sh.
- **Origin:** DEC-X01; TBD.
EOF
# --- independent self-check: DEC-X01's Source line is neither a real
#     citation (no URL, no internal artefact path) nor the literal marker
#     phrase ---
SOURCE_LINE=$(grep '^- \*\*Source:\*\*' "$F4/research.md")
if printf '%s' "$SOURCE_LINE" | grep -qi 'no external solution found'; then
  echo "NOT ok fixture 4 self-check FAILED: the Source line unexpectedly DOES"
  echo "     carry the literal permanent-marker phrase"
  failx
elif printf '%s' "$SOURCE_LINE" | grep -qE 'https?://|`[^`]+`'; then
  echo "NOT ok fixture 4 self-check FAILED: the Source line unexpectedly DOES"
  echo "     look like a real citation (URL or backtick path) -- got:"
  echo "     '$SOURCE_LINE'"
  failx
else
  echo "ok fixture 4 self-check: DEC-X01's Source line ('$SOURCE_LINE') is"
  echo "   independently confirmed to be neither a URL/artefact-path citation"
  echo "   nor the literal 'no external solution found -- original work'"
  echo "   marker -- this fixture genuinely encodes an uncited recommendation"
fi
assert_subcommand_absent "fixture 4 (uncited recommendation)" research \
  python3 "$TOOL" research --log "$F4/research.md" --plan "$F4/plan.md" --out "$WORK/f4.out.json"

# =============================================================================
# Fixture 5 -- research: a research-pass log with fewer than 3 recorded
# passes (SC-C-002/FR-003: ">=3 passes"). Table shape per the REAL
# research.md §6 header row, verified live before writing this fixture.
# =============================================================================
F5="$WORK/f5_two_passes"
mkdir -p "$F5"
cat > "$F5/research.md" <<'EOF'
## 6. Research pass log (FR-003)

| Pass | Stream | Topic | What the pass changed in the plan (from the stream's own "what this pass changed") |
|---|---|---|---|
| 1 | R1 | fixture topic one | changed nothing real -> DEC-X01 |
| 2 | R1 | fixture topic two | changed nothing real -> DEC-X02 |
EOF
cat > "$F5/plan.md" <<'EOF'
## Phased Implementation Plan

#### T-X06 -- fixture task

- **Removes / measures:** measures U-906.
- **Serves:** FR-906.
- **Expected saving -> measurement:** none directly.
- **Rollback:** additive.
- **Protecting tests:** RED fixture_self_check.sh.
- **Origin:** DEC-X01; original work (no external solution found).
EOF
# --- independent self-check: exactly 2 numbered pass rows, independently
#     re-counted (never assumed from having typed "two" in the file name) ---
PASS_ROW_COUNT=$(grep -cE '^\| [0-9]+ \|' "$F5/research.md")
if [ "$PASS_ROW_COUNT" -lt 3 ] && [ "$PASS_ROW_COUNT" -ge 1 ]; then
  echo "ok fixture 5 self-check: an independent re-count over §6's own numbered"
  echo "   Pass column finds $PASS_ROW_COUNT row(s) (< 3) -- this fixture"
  echo "   genuinely encodes 'a research-pass log with fewer than 3 passes'"
else
  echo "NOT ok fixture 5 self-check FAILED: re-counted $PASS_ROW_COUNT numbered"
  echo "     pass row(s), expected a number in [1,2] (below the >=3 floor)"
  failx
fi
assert_subcommand_absent "fixture 5 (two research passes)" research \
  python3 "$TOOL" research --log "$F5/research.md" --plan "$F5/plan.md" --out "$WORK/f5.out.json"

# =============================================================================
# Fixture 6 -- plan: documentation below a 30-pages-equivalent size threshold
# (SC-C-003: "plan + supporting documents >= 30 pages-equivalent, measured
# as words / 500"). 30 pages-equivalent = 15000 words; this fixture's own
# plan.md file, alone, is drastically below that regardless of what other
# "supporting documents" a future implementation additionally sums in.
# =============================================================================
F6="$WORK/f6_below_size"
mkdir -p "$F6"
cat > "$F6/plan.md" <<'EOF'
## Phased Implementation Plan

#### T-X07 -- the only task in this deliberately tiny fixture plan

- **Removes / measures:** measures U-907.
- **Serves:** FR-907.
- **Expected saving -> measurement:** none directly.
- **Rollback:** additive.
- **Protecting tests:** RED fixture_self_check.sh.
- **Origin:** DEC-X03; original work (no external solution found).
EOF
cat > "$F6/causes.json" <<'EOF'
{"doc": "fixture", "causes": [], "class_counts": {"stated": {}, "actual": {}}, "violations": []}
EOF
# --- independent self-check: re-count words via wc -w, independent of the
#     tool's own future word-counting code, and assert < 15000 (30 * 500) ---
WORDS=$(wc -w < "$F6/plan.md")
PAGES_EQUIV=$(python3 -c "print($WORDS / 500)")
if [ "$WORDS" -lt 15000 ]; then
  echo "ok fixture 6 self-check: an independent \`wc -w\` count finds $WORDS"
  echo "   word(s) ($PAGES_EQUIV pages-equivalent at 500 words/page, well below"
  echo "   the 30-page floor) -- this fixture genuinely encodes the"
  echo "   'below-size-threshold' defect"
else
  echo "NOT ok fixture 6 self-check FAILED: word count $WORDS is NOT below the"
  echo "     15000-word (30-page-equivalent) floor -- fixture too large"
  failx
fi
assert_subcommand_absent "fixture 6 (below-size-threshold)" plan \
  python3 "$TOOL" plan --plan "$F6/plan.md" --causes "$F6/causes.json" --out "$WORK/f6.out.json"

# =============================================================================
# Fixture 7 -- plan: a row marked CONFIRMED but still UNMEASURED after the
# T-A11 checkpoint, with no named permanent gap recorded anywhere for it
# (SC-C-001's own text, exercised here via `plan --causes` per this file's
# header note on why `plan` -- not `causes`'s own separate `--post-a11`
# flag -- is this fixture's target).
# =============================================================================
F7="$WORK/f7_confirmed_unmeasured_no_gap"
mkdir -p "$F7"
cat > "$F7/causes.json" <<'EOF'
{
  "doc": "fixture",
  "causes": [
    {"id": "RC-X08", "class": "CONFIRMED", "evidence_paths": ["fixture/evidence"],
     "measured_share": "UNMEASURED", "settling_evidence": null,
     "removed_or_measured_by": "T-X08"}
  ],
  "class_counts": {"stated": {"CONFIRMED": 1}, "actual": {"CONFIRMED": 1}},
  "violations": []
}
EOF
cat > "$F7/plan.md" <<'EOF'
## Phased Implementation Plan

#### T-X08 -- fixture task that removes/measures RC-X08, records no gap marker

- **Removes / measures:** measures U-908; RC-X08.
- **Serves:** FR-908.
- **Expected saving -> measurement:** none directly (instrument).
- **Rollback:** additive change, remove the added line.
- **Protecting tests:** RED fixture_self_check.sh; golden triple present.
- **Origin:** DEC-X04; original work (no external solution found).
EOF
# --- independent self-check: causes.json genuinely declares RC-X08
#     CONFIRMED + measured_share exactly "UNMEASURED"; plan.md genuinely
#     names no permanent-gap marker anywhere for it ---
python3 - "$F7/causes.json" <<'PYEOF'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
row = next((c for c in doc["causes"] if c["id"] == "RC-X08"), None)
ok = row is not None and row["class"] == "CONFIRMED" and row["measured_share"] == "UNMEASURED"
sys.exit(0 if ok else 1)
PYEOF
CAUSES_JSON_OK=$?
if grep -qi 'permanent gap' "$F7/plan.md"; then
  echo "NOT ok fixture 7 self-check FAILED: plan.md unexpectedly DOES name a"
  echo "     permanent gap for RC-X08 -- this fixture does not encode the"
  echo "     intended defect"
  failx
elif [ "$CAUSES_JSON_OK" -ne 0 ]; then
  echo "NOT ok fixture 7 self-check FAILED: causes.json does not declare"
  echo "     RC-X08 as CONFIRMED with measured_share exactly 'UNMEASURED' --"
  echo "     the fixture's own input is malformed"
  failx
else
  echo "ok fixture 7 self-check: causes.json independently confirmed (via a"
  echo "   real json.load, not a text grep) to declare RC-X08 CONFIRMED with"
  echo "   measured_share == 'UNMEASURED', and plan.md independently confirmed"
  echo "   to name no permanent-gap marker anywhere for it -- this fixture"
  echo "   genuinely encodes the 'CONFIRMED-but-still-UNMEASURED, no named"
  echo "   permanent gap' defect"
fi
assert_subcommand_absent "fixture 7 (CONFIRMED/UNMEASURED, no permanent gap)" plan \
  python3 "$TOOL" plan --plan "$F7/plan.md" --causes "$F7/causes.json" --out "$WORK/f7.out.json"

# =============================================================================
# (9) Negative control: the project's OWN current, real research.md and
#     plan.md documents. Per this file's own header, `causes` is the ONLY
#     already-implemented subcommand, so this section first re-verifies
#     (real invocation, not assumed from the sibling test's own prose) that
#     `causes` genuinely exits 0 against the live register TODAY -- giving
#     this file a real `causes.json` to feed `plan` -- and THEN honestly
#     reports what `research`/`plan` do against the real documents: the
#     SAME rc=2 "invalid choice" every golden-bad fixture above got, for
#     the SAME reason (the subcommand is wholly absent). This is reported
#     as-is, never dressed up as "the documents cleanly PASS" -- a
#     tool that does not exist has not evaluated these documents at all,
#     and claiming otherwise would itself be a §11.4/§11.4.1 bluff at the
#     investigation layer (§11.4.199/§11.4.6).
# =============================================================================
if [ ! -f "$RESEARCH_LIVE" ] || [ ! -f "$PLAN_LIVE" ]; then
  echo "NOT ok negative control SKIPPED: live research.md/plan.md missing at"
  echo "     $RESEARCH_LIVE / $PLAN_LIVE"
  failx
else
  LIVE_CAUSES_JSON="$WORK/live_causes.json"
  python3 "$TOOL" causes --doc "$RESEARCH_LIVE" --out "$LIVE_CAUSES_JSON" \
    >"$WORK/live_causes.out" 2>"$WORK/live_causes.err"
  CAUSES_RC=$?
  if [ "$CAUSES_RC" -eq 0 ] && [ -s "$LIVE_CAUSES_JSON" ]; then
    echo "ok negative control precondition: the ALREADY-implemented \`causes\`"
    echo "   subcommand real-invoked against the live, current research.md"
    echo "   genuinely exits 0 and writes a real causes.json TODAY (re-verified"
    echo "   live here, not assumed from test_plan_struct_causes_red.sh's own"
    echo "   prose) -- this file now has a real --causes input for \`plan\`"
  else
    echo "NOT ok negative control precondition FAILED: \`causes\` against the"
    echo "     live register did not exit 0 (rc=$CAUSES_RC) or wrote no output"
    echo "     -- stderr: $(cat "$WORK/live_causes.err" 2>/dev/null)"
    failx
  fi

  # `research` against the live documents
  python3 "$TOOL" research --log "$RESEARCH_LIVE" --plan "$PLAN_LIVE" \
    --out "$WORK/live_research.out.json" \
    >"$WORK/live_research.out" 2>"$WORK/live_research.err"
  RESEARCH_RC=$?
  if [ "$RESEARCH_RC" -eq 2 ] && grep -q "invalid choice: 'research'" "$WORK/live_research.err"; then
    echo "info negative control, \`research\` subcommand against the REAL, live"
    echo "   research.md/plan.md: rc=$RESEARCH_RC (subcommand absent -- the SAME"
    echo "   reason every golden-bad fixture above got, not a finding about"
    echo "   the live documents' own content, which this tool has not yet"
    echo "   evaluated at all). Honestly reported, not claimed as a clean PASS."
  else
    echo "NOT ok negative control, \`research\` against the real documents:"
    echo "     expected the same tool-absence signature (rc=2, 'invalid"
    echo "     choice'), got rc=$RESEARCH_RC -- stderr:"
    echo "     $(cat "$WORK/live_research.err" 2>/dev/null)"
    failx
  fi

  # `plan` against the live documents + the just-produced live causes.json
  python3 "$TOOL" plan --plan "$PLAN_LIVE" --tasks "$ROOT/specs/004-fast-dev-cycles/tasks.md" \
    --causes "$LIVE_CAUSES_JSON" --out "$WORK/live_plan.out.json" \
    >"$WORK/live_plan.out" 2>"$WORK/live_plan.err"
  PLAN_RC=$?
  if [ "$PLAN_RC" -eq 2 ] && grep -q "invalid choice: 'plan'" "$WORK/live_plan.err"; then
    echo "info negative control, \`plan\` subcommand against the REAL, live"
    echo "   plan.md/tasks.md/causes.json: rc=$PLAN_RC (subcommand absent -- the"
    echo "   SAME reason every golden-bad fixture above got). Honestly"
    echo "   reported, not claimed as a clean PASS: whether the real, live"
    echo "   plan.md genuinely satisfies SC-C-003 (rollback fields, the"
    echo "   bipartite FR/RC coverage, the 30-page-equivalent floor, the"
    echo "   post-T-A11 measured_share rule) is UNKNOWN until T179 lands and"
    echo "   this fixture-driven RED baseline is re-pointed at the real CLI's"
    echo "   output, exactly as test_plan_struct_causes_red.sh's own section"
    echo "   (1b)/(8) already did for \`causes\` once T046 landed."
  else
    echo "NOT ok negative control, \`plan\` against the real documents: expected"
    echo "     the same tool-absence signature (rc=2, 'invalid choice'), got"
    echo "     rc=$PLAN_RC -- stderr: $(cat "$WORK/live_plan.err" 2>/dev/null)"
    failx
  fi
fi

echo
echo "=== T178 contract stub 1/3: which subcommand each fixture targets ==="
echo "VERIFIED (real invocation, sections above): fixtures 1/2/3/6/7 target"
echo "  \`plan\` (SC-C-003/FR-004: rollback, bipartite RC/FR coverage, the"
echo "  30-page-equivalent size floor, and the post-T-A11 measured_share"
echo "  rule read from --causes); fixtures 4/5 target \`research\`"
echo "  (SC-C-002/FR-003: cited recommendations, >=3 research passes)."

echo
echo "=== T178 contract stub 2/3: today's uniform RED signature ==="
echo "VERIFIED (real invocation, all nine cases above -- 7 golden-bad plus 2"
echo "  negative-control subcommand calls): every single one exits rc=2 with"
echo "  argparse's own 'invalid choice' + 'choose from' text naming the"
echo "  absent subcommand. This tool CANNOT yet distinguish any of the seven"
echo "  deliberately-broken fixtures from the live, real, presumably-clean"
echo "  documents -- the only honest RED-baseline claim available today is"
echo "  'the subcommand does not exist', never 'the documents were checked"
echo "  and found clean/broken'. T179 replaces this uniform rc=2 with real,"
echo "  per-fixture verdicts; this file's fixtures + their independent"
echo "  self-checks above stand as T179's interim contract in the interim,"
echo "  per contracts/common-conventions.md's own convention for open-gap"
echo "  tools."

echo
echo "=== T178 contract stub 3/3: OUT OF SCOPE for this file (honest disclosure) ==="
echo "NOT covered by THIS file (separate contract clauses / a separate later"
echo "  task's test, per plan-research-structural-check.md's own RED-fixtures"
echo "  table): sc_bad_duplicate_block / sc_bad_substantive_edit (the"
echo "  \`landing\`/\`rule-diff\` subcommands, FR-019/FR-022, T-G01/T-G02);"
echo "  sc_negctrl_refuted_cause_no_task (a REFUTED-class negative control,"
echo "  belongs to \`causes\`'s own already-landed test suite); the CT-5"
echo "  self-validation-triple check named by T179's own task line (that is"
echo "  T179's own implementation's job to satisfy, not this RED test's)."

echo
echo "SUMMARY control_needles=2 subcommand_calls_asserted=9" \
     "(fixtures=7 negative_control_calls=2) fixture_self_checks=7 fail=$fail"
exit $fail
