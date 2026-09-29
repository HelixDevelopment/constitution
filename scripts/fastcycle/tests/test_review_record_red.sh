#!/bin/bash
# T018 RED test for review/review_record.py (spec 004-fast-dev-cycles;
# contracts/review-batch-and-precheck.md RB-001..RB-007; data-model.md #10.1
# ReviewVerdictRecord; plan T-A04; FR-023, SC-009, SC-001).
#
# Purpose: pin review_record.py's finding classifier (mechanical | judgment |
#          false-positive, the T-A04 class set) BEFORE T034 implements it.
#          RED = review_record.py is absent today, so EVERY fixture review
#          produces NO record right now -- the classification this test
#          demands is therefore, today, entirely unmet (every chk below is
#          expected to FAIL until T034 lands).
#
# Producer != Verifier (constitution 11.4.240): this test + its fixtures are
# authored by a DIFFERENT task than the one that implements
# review/review_record.py (T034, a later, separate task). It is written to
# fail loudly against today's absent tool and to flip, unedited, to a real
# classification check the moment T034 lands the file: every assertion below
# reads its expected/observed values from files (the `expected` fixture file,
# the tool's own `--out` JSON), never from an if/else branch on "does the
# tool exist yet" -- so there is exactly one code path for RED and GREEN
# (constitution 11.4.115: one source, two roles).
#
# UNCONFIRMED (the contract fixes semantics -- findings classify mechanical |
# judgment | false-positive -- NOT the exact CLI flag spellings or the
# classifier's internal signal source; the choices below are what THIS test
# invokes/asserts and are therefore binding on T034 unless T034 records an
# explicit, evidenced deviation, constitution 11.4.6):
#   Invocation : python3 $FC/review/review_record.py record --batch <batch.json>
#                  --round <n> --verdict-file <verdict.json> --tier opus
#                  --effort xhigh --out <rev.json>
#                (contract review-batch-and-precheck.md "Invocations": the flag
#                 NAMES --batch/--round/--verdict-file/--tier/--effort/--out are
#                 given verbatim there; the VALUES "opus" and "xhigh" are this
#                 test's choice, matching the designated/pinned review tier,
#                 contracts/common-conventions.md "Terms" and constitution
#                 11.4.209 as amended 2026-09-26: Opus xhigh, no Fable, no
#                 fallback model)
#   Output     : a JSON document (ReviewVerdictRecord, data-model.md #10.1)
#                written to <rev.json>, carrying at minimum
#                {effort, findings:[{id, class, ...}]}.
#   Classifier signal source (fixture design choice below, not asserted as the
#   ONLY valid implementation -- any classifier that reaches the same per-
#   fixture verdict satisfies this test):
#     mechanical     -- the finding names a known lint/style rule
#                        (verdict.json "rule": "SC2086", a shellcheck code)
#     judgment       -- the finding is a substantive design/architecture
#                        concern: no lint rule, no already-fixed-markers match
#     false-positive -- the finding's file+line matches an entry in
#                        precheck.json's "already-fixed-markers" check
#                        evidence (DEC-33 "state-temporal misalignment": the
#                        code was already fixed by the time the reviewer
#                        filed the comment)
#   Exit codes (contract "Exit codes" table): record 0 success (written) / 1
#     refused (tier/effort mismatch). None of these three fixtures exercises
#     the tier/effort-refusal path (that is review-batch-and-precheck's own
#     rb_bad_wrong_tier / rb_bad_low_effort fixtures, a different task) --
#     all three here pass the DESIGNATED tier/effort, so a correct
#     implementation returns 0 for all three. Today (tool absent) python3
#     cannot even start it; the observed rc is whatever python3 itself
#     reports for a missing script (verified empirically before writing this
#     test: `python3 <absent-path> ...` -> rc=2,
#     "python3: can't open file '<path>': [Errno 2] No such file or
#     directory" -- never assumed, constitution 11.4.6) -- in any case never
#     0, and <rev.json> is never created.
#
# Fixtures (C-005 self-validation triple; constitution/scripts/fastcycle/
# tests/lib/triple_harness.sh and fixtures/triple_harness/*/{golden-good,
# golden-bad,negative-control}/{input,expected} set the directory/file-naming
# convention this test follows. review_record.py's CLI takes several named
# flags rather than one positional "input" file, so this test drives it
# directly instead of through the generic triple_harness.sh runner -- the
# NAMING convention carries over, not the runner code):
#   fixtures/review_record/golden-good/      -- lint-class finding
#                                                -> expected "mechanical"
#   fixtures/review_record/golden-bad/       -- design-level finding
#                                                -> expected "judgment"
#   fixtures/review_record/negative-control/ -- already-fixed-line finding
#                                                -> expected "false-positive"
# Each holds: batch.json (ReviewBatch, data-model.md #10.2), precheck.json
# (PreCheckReport, #10.3), verdict.json (the raw --verdict-file a reviewer
# produced, one finding with id "F1"), and a one-line `expected` file naming
# the classification F1 MUST resolve to once T034 lands (matching the
# triple_harness.sh "golden-bad/expected" convention: one non-blank line the
# tool's output must eventually name).
#
# I2 fixtures (contract review-batch-and-precheck.md "RED fixtures" table --
# added as a T034 fix-pass so the tier/effort refusal path this file's own
# assertions previously exercised only by hand becomes a PERMANENT regression
# guard, not a one-off manual check): these three carry no `expected` file --
# they assert on the record call's exit code and, for the negative control,
# on specific output fields, not on classification.
#   fixtures/review_record/rb_bad_wrong_tier/        -- record --tier sonnet
#                                                        (wrong model tier)
#                                                        -> exit 1, no file written
#   fixtures/review_record/rb_bad_low_effort/         -- record --effort high
#                                                        (below the xhigh floor)
#                                                        -> exit 1, no file written
#   fixtures/review_record/rb_negctrl_unknown_effort/ -- record --effort '?'
#                                                        (the honest capability-
#                                                        gap token, constitution
#                                                        11.4.231(F.2)) -> exit 0,
#                                                        file written, effort=="?",
#                                                        effort_capability_gap==true
#                                                        (the false-positive guard:
#                                                        this MUST NOT be refused
#                                                        like the two golden-bad
#                                                        cases above it)
#
# T027 tie-in: the GREEN-mode assertion `doc.get("effort") == "xhigh"` below
# is exactly the check T027's paired mutation "review_record drops `effort`"
# (T-A04) must flip to FAIL: once T034 exists and this test is GREEN,
# deleting the `effort` key (or writing a wrong value) from
# review_record.py's emitted record makes that specific chk() fail, proving
# the mutation is caught (constitution 1.1 / 11.4.224).
#
# Usage: bash test_review_record_red.sh   (exit 0 = all assertions pass
#        [only possible once T034 is GREEN]; nonzero = FAIL count>0 [today])
HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
TOOL="$FC/review/review_record.py"
FX="$HERE/fixtures/review_record"
TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
RECORD_TIMEOUT_S=30  # operator-tunable default, no measured basis; bounds a hung future implementation.

reap_children() {
  # Process-leak guard (matches test_fc_common_red.sh convention): kill anything
  # this test spawned whose command line names $TMP, in case a future
  # review_record.py leaves a descendant running past `timeout`'s own reap.
  pkill -KILL -f "$TMP" 2>/dev/null
  return 0
}
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM

FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "INFO: $1"; }

# ---------------------------------------------------------------------------
# constitution 11.4.273 control-needle discipline: prove the absence-check
# mechanism itself can see (find a known-present item, and correctly report a
# fabricated item as absent) BEFORE relying on it below to conclude "no
# record was written" for the real fixtures. A blind check and a genuinely
# clean state return the identical quiet "not found" -- the needle is what
# tells them apart (constitution 11.4.201(6)).
# ---------------------------------------------------------------------------
NEEDLE_PRESENT="$TMP/.needle_present_marker"
: > "$NEEDLE_PRESENT"
chk "control needle: known-present file IS found by the file-existence check" \
  "$([ -f "$NEEDLE_PRESENT" ] && echo 1 || echo 0)"
NEEDLE_FABRICATED="$TMP/.needle_fabricated_never_created_$$_$(date +%s 2>/dev/null || echo x)"
chk "control needle: fabricated (never-created) path IS reported absent" \
  "$([ ! -e "$NEEDLE_FABRICATED" ] && echo 1 || echo 0)"
rm -f "$NEEDLE_PRESENT"

# ---------------------------------------------------------------------------
# Fixture self-check: all three fixture reviews exist, are well-formed JSON,
# and each `expected` file names a value from the T-A04 closed class set.
# ---------------------------------------------------------------------------
for fx in golden-good golden-bad negative-control; do
  for f in batch.json precheck.json verdict.json expected; do
    chk "fixture $fx/$f exists" "$([ -f "$FX/$fx/$f" ] && echo 1 || echo 0)"
  done
done
for fx in golden-good golden-bad negative-control; do
  for j in batch.json precheck.json verdict.json; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$FX/$fx/$j" >/dev/null 2>"$TMP/jerr"
    rc=$?
    chk "fixture $fx/$j parses as JSON" "$([ "$rc" -eq 0 ] && echo 1 || echo 0)"
  done
  exp="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$FX/$fx/expected" 2>/dev/null | sed '/^$/d' | head -n1)"
  case "$exp" in
    mechanical|judgment|false-positive) chk "fixture $fx/expected names a T-A04 class ('$exp')" 1 ;;
    *) chk "fixture $fx/expected names a T-A04 class ('$exp')" 0 ;;
  esac
done

# ---------------------------------------------------------------------------
# Core RED assertion: is review_record.py implemented yet?
# ---------------------------------------------------------------------------
if [ -e "$TOOL" ]; then
  info "review_record.py EXISTS at $TOOL -- assertions below run for real (GREEN mode)."
else
  info "review_record.py ABSENT at $TOOL -- this is the RED baseline; every fixture below produces no record."
fi
chk "review_record.py implemented ($TOOL)" "$([ -e "$TOOL" ] && echo 1 || echo 0)"

# record_call <fixture-dir> <out-file>: invokes the real CLI shape (see header
# UNCONFIRMED block); sets $RC to its exit status. Identical call whether the
# tool exists or not -- the natural absence of $TOOL is what makes this RED
# today, not a branch in this function.
record_call() {
  timeout -k 2 "$RECORD_TIMEOUT_S" python3 "$TOOL" record \
    --batch "$1/batch.json" \
    --round 1 \
    --verdict-file "$1/verdict.json" \
    --tier opus --effort xhigh \
    --out "$2" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}

# class_of <record-file>: prints the "class" of finding "F1" in <record-file>,
# or the empty string if the file is absent/unreadable/malformed/has no such
# finding. Never raises -- an unreadable file is honestly "" (no invented
# value, constitution 11.4.6), which naturally fails the equality check below
# against a non-empty expected class.
class_of() {
  python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    doc = {}
findings = doc.get("findings") if isinstance(doc, dict) else None
f1 = next((f for f in (findings or []) if isinstance(f, dict) and f.get("id") == "F1"), None)
print((f1 or {}).get("class", ""))
PY
}

# effort_of <record-file>: prints the top-level "effort" field, or "" if the
# file is absent/unreadable/malformed. See T027 tie-in in the header comment:
# this is the field a "review_record drops `effort`" mutation removes.
effort_of() {
  python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    doc = {}
print(doc.get("effort", "") if isinstance(doc, dict) else "")
PY
}

for fx in golden-good golden-bad negative-control; do
  EXPECTED="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$FX/$fx/expected" | sed '/^$/d' | head -n1)"
  OUT="$TMP/$fx.record.json"
  rm -f "$OUT"

  record_call "$FX/$fx" "$OUT"
  info "$fx: ran: python3 $TOOL record --batch $FX/$fx/batch.json --round 1 --verdict-file $FX/$fx/verdict.json --tier opus --effort xhigh --out $OUT"
  info "$fx: rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"

  chk "$fx: record call exits 0 (accepted at the designated tier/effort)" \
    "$([ "$RC" -eq 0 ] && echo 1 || echo 0)"
  chk "$fx: record file was written ($OUT)" \
    "$([ -f "$OUT" ] && echo 1 || echo 0)"

  GOT_CLASS="$(class_of "$OUT")"
  chk "$fx: finding F1 classified '$EXPECTED' (got '$GOT_CLASS')" \
    "$([ -n "$EXPECTED" ] && [ "$GOT_CLASS" = "$EXPECTED" ] && echo 1 || echo 0)"

  GOT_EFFORT="$(effort_of "$OUT")"
  chk "$fx: record.effort == xhigh (T027 mutation target; got '$GOT_EFFORT')" \
    "$([ "$GOT_EFFORT" = "xhigh" ] && echo 1 || echo 0)"
done

# ---------------------------------------------------------------------------
# I2: permanent regression guard for the tier/effort refusal path (RB-004 /
# review-batch-and-precheck.md RED fixtures rb_bad_wrong_tier, rb_bad_low_effort,
# rb_negctrl_unknown_effort) -- previously exercised only by hand, never pinned
# in this file.
# ---------------------------------------------------------------------------

# record_call_te <fixture-dir> <out-file> <tier> <effort>: identical to
# record_call() above but with the tier/effort under test, not the fixed
# opus/xhigh pair. Sets $RC to the exit status.
record_call_te() {
  timeout -k 2 "$RECORD_TIMEOUT_S" python3 "$TOOL" record \
    --batch "$1/batch.json" \
    --round 1 \
    --verdict-file "$1/verdict.json" \
    --tier "$3" --effort "$4" \
    --out "$2" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}

# field_of <record-file> <field-name>: prints json.dumps(value) for a top-level
# field (so a bool prints "true"/"false"), or "" if the file is
# absent/unreadable/malformed/lacks the field -- never raises, never invents a
# value (constitution 11.4.6), matching class_of()/effort_of()'s convention.
field_of() {
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    doc = {}
if isinstance(doc, dict) and sys.argv[2] in doc:
    print(json.dumps(doc[sys.argv[2]]))
else:
    print("")
PY
}

# rb_bad_wrong_tier: sonnet where opus is designated -- record MUST refuse (1)
# and MUST NOT write --out.
OUT="$TMP/rb_bad_wrong_tier.record.json"
rm -f "$OUT"
record_call_te "$FX/rb_bad_wrong_tier" "$OUT" sonnet xhigh
info "rb_bad_wrong_tier: ran: python3 $TOOL record --tier sonnet --effort xhigh ... ; rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"
chk "rb_bad_wrong_tier: record refused (exit 1) for a non-designated model tier" \
  "$([ "$RC" -eq 1 ] && echo 1 || echo 0)"
chk "rb_bad_wrong_tier: no record file written on refusal" \
  "$([ ! -f "$OUT" ] && echo 1 || echo 0)"

# rb_bad_low_effort: "high" where "xhigh" is designated -- record MUST refuse
# (1) and MUST NOT write --out.
OUT="$TMP/rb_bad_low_effort.record.json"
rm -f "$OUT"
record_call_te "$FX/rb_bad_low_effort" "$OUT" opus high
info "rb_bad_low_effort: ran: python3 $TOOL record --tier opus --effort high ... ; rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"
chk "rb_bad_low_effort: record refused (exit 1) for a below-xhigh effort" \
  "$([ "$RC" -eq 1 ] && echo 1 || echo 0)"
chk "rb_bad_low_effort: no record file written on refusal" \
  "$([ ! -f "$OUT" ] && echo 1 || echo 0)"

# rb_negctrl_unknown_effort (negative control, constitution 11.4.231(F.2) /
# 11.4.201(1) false-positive guard): effort "?" is the HONEST capability-gap
# token, not a wrong-effort refusal case -- it MUST be ACCEPTED (0), stored
# verbatim, and flagged as a capability gap, never silently treated like
# rb_bad_low_effort above it.
OUT="$TMP/rb_negctrl_unknown_effort.record.json"
rm -f "$OUT"
record_call_te "$FX/rb_negctrl_unknown_effort" "$OUT" opus '?'
info "rb_negctrl_unknown_effort: ran: python3 $TOOL record --tier opus --effort '?' ... ; rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"
chk "rb_negctrl_unknown_effort: record ACCEPTED (exit 0) for the honest '?' effort token" \
  "$([ "$RC" -eq 0 ] && echo 1 || echo 0)"
chk "rb_negctrl_unknown_effort: record file was written ($OUT)" \
  "$([ -f "$OUT" ] && echo 1 || echo 0)"
GOT_EFFORT="$(field_of "$OUT" effort)"
chk "rb_negctrl_unknown_effort: record.effort == \"?\" verbatim (got $GOT_EFFORT)" \
  "$([ "$GOT_EFFORT" = '"?"' ] && echo 1 || echo 0)"
GOT_GAP="$(field_of "$OUT" effort_capability_gap)"
chk "rb_negctrl_unknown_effort: record.effort_capability_gap == true (got '$GOT_GAP')" \
  "$([ "$GOT_GAP" = "true" ] && echo 1 || echo 0)"

echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
