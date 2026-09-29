#!/bin/bash
# T086 RED test for closure/escape_classify.py (spec 004-fast-dev-cycles, User
# Story 3; contracts/closure-refusal.md EC-001..EC-003; data-model.md §6.1-6.2
# Escape Mechanism / EscapeClassification; plan T-D01; FR-009, SC-004).
#
# Purpose: pin escape_classify.py's DEC-19 closed-list classifier (E1..E9,
#          exactly one primary per reopened item, ≥1 hash-matched EvidencePath
#          per non-E9 entry, row count == distinct reopened items in the
#          window) BEFORE T094 implements it. RED = escape_classify.py is
#          absent today (confirmed 2026-09-29: constitution/scripts/fastcycle/
#          closure/ holds only a .gitkeep placeholder) -- every fixture below
#          is therefore expected to FAIL every real check until T094 lands.
#
# Producer != Verifier (constitution 11.4.240): this file + its fixtures are
# authored at the RED step (T086); T094 (a later, separate task) implements
# closure/escape_classify.py. This file is written to fail loudly against
# today's absent tool and to flip, unedited, to a real classification check
# the moment T094 lands the file -- every assertion below reads its expected/
# observed values from files (each fixture's own expected.json, the tool's own
# --out JSON / stderr), never from an if/else branch on "does the tool exist
# yet" -- one code path for RED and GREEN (constitution 11.4.115: one source,
# two roles).
#
# UNCONFIRMED (constitution 11.4.6 -- the contract's "Invocations" section
# FIXES the flag names verbatim; this test's OWN choices below -- the real
# --config file used, the window semantics, the EscapeClassification /
# EvidencePath field names inside --classifications, and this checker's
# robust-nested-lookup strategy against --out -- are binding on T094 unless
# T094 records an explicit, evidenced deviation):
#   Invocation : python3 $FC/closure/escape_classify.py --config <cfg>
#                  --as-of <date> --window-days <N>
#                  --classifications <input.yaml> --out <escape.json>
#                (contract closure-refusal.md "Invocations" line 19: the flag
#                 NAMES --config/--as-of/--window-days/--classifications/--out
#                 are given verbatim there.)
#   --config   : the REAL, already-tracked project config
#                config/fastcycle/fastcycle.yaml (contracts/common-conventions.md
#                Placement: "default config file config/fastcycle/fastcycle.yaml"),
#                which already declares paths.workable_items_db:
#                docs/workable_items.db -- never a fixture-invented config.
#                Invoked with cwd=$ROOT so relative paths inside it resolve
#                against the repo root regardless of the tool's own root-
#                detection default (mirrors the already-landed sibling tool
#                cycle/cycle_report.py's `db_path = args.db_path or
#                os.path.join(repo_root, "docs", "workable_items.db")`
#                pattern; this test supplies --config instead of that tool's
#                --db-path/--repo-root override flags because closure-refusal.md's
#                Invocations line does not list those two -- --config is what
#                is fixed here).
#   Window     : --as-of <D> --window-days 0 => [D, D] inclusive (same
#                window.from = as_of - window_days, BETWEEN window.from AND
#                window.to convention already implemented in cycle_report.py,
#                cited rather than re-guessed).
#   --classifications (input.yaml) EscapeClassification fields: EXACTLY
#     data-model.md line 184's `{item_id, reopen_events: [item_history rowid
#     >=1], primary: EscapeCode, contributing: [EscapeCode] (optional),
#     detection_channel (11.4.34 vocabulary), evidence: [EvidencePath >=1]}`.
#     EvidencePath's own shape (`path` + `content_address`) is data-model.md
#     line 27 verbatim ("Repo-relative path ... plus its ContentAddress at
#     capture time"). `classified_by`/`reviewed_by` (also named in line 184)
#     are the TOOL's own output provenance, not supplied as fixture input --
#     EC-002 lists no such input requirement.
#   --out (escape.json): this test does NOT assume a specific top-level
#     container key (rows/classifications/items/...) -- its checker recursively
#     searches the parsed JSON document for any dict carrying
#     `"item_id" == <expected>` and reads that dict's fields directly, so it is
#     robust to T094's eventual envelope choice while still performing a REAL,
#     per-field, non-vacuous comparison (constitution 11.4.107(10)/11.4.201).
#   Exit codes (contract "Exit codes" line 51): "escape_classify.py: 0 valid +
#     complete, 1 missing/extra/invalid entries, 3 needle failure (a known
#     reopened item -- default ATM-953, reopen event 2026-07-28 -- not
#     enumerated), 4 DB unreadable." Today (tool absent) python3 cannot even
#     start it; the observed rc is whatever python3 itself reports for a
#     missing script (verified empirically before writing this test:
#     `python3 <absent-path> ...` -> rc=2, "python3: can't open file
#     '<path>': [Errno 2] No such file or directory" -- never assumed,
#     constitution 11.4.6) -- in any case never one of the contract's own
#     codes above, and no --out file is ever created.
#
# Fixtures (constitution/scripts/fastcycle/tests/fixtures/escape_classify/,
# C-005 self-validation triple naming convention -- golden-good / golden-bad /
# negative-control, per contracts/common-conventions.md):
#   ec_good_atm953_e1/               -- golden: ATM-953 -> E1 wrong-layer-evidence
#                                        (task line; data-model.md §6.1 E1 cites
#                                        ATM-953 by name; RC-22/P-39/the item's
#                                        own real §11.4.226 bluff-audit doc)
#   ec_good_e7_design_reconsidered/  -- golden: SPK-609/ATM-610/ATM-611 -> E7
#                                        design-reconsidered (task line;
#                                        data-model.md §6.1 E7 cites these three
#                                        ids by name; ALSO the count-check
#                                        fixture -- a real, natural 3-item window)
#   ec_bad_no_evidence_path/         -- golden-bad: a row with no evidence path
#                                        fails (task line; EC-002)
#   ec_negctrl_atm799_e4_no_e9/      -- negative control: an item with complete
#                                        evidence classifies without E9 (task
#                                        line; the "primary != E9" assertion is
#                                        load-bearing, "primary == E4" is this
#                                        fixture's own grounded, evidenced claim)
# Each fixture directory holds input.yaml (the analyst-authored classification,
# real item_history rowids + real, existing, sha256-hashed evidence files --
# see each input.yaml's own header for full provenance) and expected.json (the
# subset of fields this test asserts on, plus its own provenance/robustness
# notes).
#
# Count check (task line "count check: rows == distinct reopened items"): run
# as its own labelled section below against ec_good_e7_design_reconsidered/'s
# real 3-item window, cross-checked live (not from a frozen claim) against
# docs/workable_items.db's own COUNT(DISTINCT atm_id) for that exact window
# (mirrors test_cycle_report_red.sh's live-DB control-needle technique). This
# test does NOT attempt to classify the tracker's full real 24-distinct-item /
# 28-event population (research.md R1:62) -- that full corpus classification is
# T094's own production run over "every reopened item after T044" (tasks.md
# T094 line), a separate, later, much larger undertaking; this RED test proves
# the row-count INVARIANT on a small, fully-real, fully-verifiable window.
#
# §11.4.273 control-needle discipline: prove the absence-check mechanism itself
# can see (find a known-present item, correctly report a fabricated item as
# absent) BEFORE relying on it below to conclude "escape_classify.py is
# absent" / "no --out document was written" for the real fixtures -- a blind
# check and a genuinely clean state return the identical quiet "not found"
# (constitution 11.4.201(6)); a second, independent needle proves the LIVE
# tracker DB genuinely contains the real reopen rows this test's fixtures cite
# (mirrors test_cycle_report_red.sh's needle #2a/#2b technique) rather than
# trusting the frozen claims in each input.yaml's header comments.
#
# Usage: bash test_escape_classify_red.sh   Exit 0 = every real assertion below
#        (control needles, fixture presence/parse, the four fixture checks
#        against escape_classify.py's real output, and the count check) held
#        (only possible once T094 is GREEN); nonzero = FAIL count>0 (today).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$FC/../../.." && pwd)"
TOOL="$FC/closure/escape_classify.py"
FX="$HERE/fixtures/escape_classify"
CONFIG="$ROOT/config/fastcycle/fastcycle.yaml"
DB="$ROOT/docs/workable_items.db"

TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
CLASSIFY_TIMEOUT_S=60  # operator-tunable default, no measured basis; bounds a hung future implementation.

reap_children() {
  # Process-leak guard (matches test_review_record_red.sh / test_fc_common_red.sh
  # convention): kill anything this test spawned whose command line names $TMP.
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
# constitution 11.4.273 control-needle discipline (needle set #1: the
# absence-check mechanism itself).
# ---------------------------------------------------------------------------
NEEDLE_PRESENT="$TMP/.needle_present_marker"
: > "$NEEDLE_PRESENT"
chk "control needle #1a: known-present file IS found by the file-existence check" \
  "$([ -f "$NEEDLE_PRESENT" ] && echo 1 || echo 0)"
NEEDLE_FABRICATED="$TMP/.needle_fabricated_never_created_$$_$(date +%s 2>/dev/null || echo x)"
chk "control needle #1b: fabricated (never-created) path IS reported absent" \
  "$([ ! -e "$NEEDLE_FABRICATED" ] && echo 1 || echo 0)"
rm -f "$NEEDLE_PRESENT"

# ---------------------------------------------------------------------------
# constitution 11.4.273 control-needle discipline (needle set #2: the LIVE
# tracker DB genuinely contains what every fixture header claims -- proves the
# fixtures' own provenance rather than trusting the frozen comments).
# ---------------------------------------------------------------------------
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "FAIL: sqlite3 not on PATH -- cannot run the live needle #2 proofs;"
  echo "      this is an environment gap, not a finding about escape_classify.py"
  FAIL=$((FAIL+1)); N=$((N+1))
elif [ ! -f "$DB" ]; then
  echo "FAIL: tracker DB not found at $DB -- cannot run the live needle #2 proofs"
  FAIL=$((FAIL+1)); N=$((N+1))
else
  # 2a: ATM-953's real Reopened row (rowid=869, on_date=2026-07-28) -- the
  # exact item the contract itself names as escape_classify.py's OWN default
  # self-test needle (closure-refusal.md "Exit codes": "3 needle failure (a
  # known reopened item -- default ATM-953, reopen event 2026-07-28 -- not
  # enumerated)").
  ROW_953="$(sqlite3 -readonly "$DB" \
    "SELECT id || '|' || event_type || '|' || on_date FROM item_history WHERE atm_id='ATM-953' AND event_type='Reopened' AND on_date='2026-07-28';" 2>&1)"
  chk "needle #2a (known-present): ATM-953's real Reopened/2026-07-28 row is rowid 869 (got '$ROW_953')" \
    "$([ "$ROW_953" = "869|Reopened|2026-07-28" ] && echo 1 || echo 0)"

  # 2a (cont.): SPK-609/ATM-610/ATM-611 Reopened/2026-07-07 rows -- the E7
  # trio's real rowids this test's ec_good_e7 fixture cites.
  ROWS_E7="$(sqlite3 -readonly "$DB" \
    "SELECT atm_id || '=' || id FROM item_history WHERE event_type='Reopened' AND on_date='2026-07-07' ORDER BY atm_id;" 2>&1 | tr '\n' ',')"
  chk "needle #2a (known-present): the real E7 trio rowids are SPK-609=238,ATM-610=239,ATM-611=240 (got '$ROWS_E7')" \
    "$([ "$ROWS_E7" = "ATM-610=239,ATM-611=240,SPK-609=238," ] && echo 1 || echo 0)"

  # 2a (cont.): ATM-799's real Reopened row (rowid=684, on_date=2026-07-23).
  ROW_799="$(sqlite3 -readonly "$DB" \
    "SELECT id || '|' || event_type || '|' || on_date || '|' || reason FROM item_history WHERE atm_id='ATM-799' AND event_type='Reopened' AND on_date='2026-07-23';" 2>&1)"
  chk "needle #2a (known-present): ATM-799's real Reopened/2026-07-23 row is rowid 684 (got '$ROW_799')" \
    "$([ "$ROW_799" = "684|Reopened|2026-07-23|captured-evidence-contradicts" ] && echo 1 || echo 0)"

  # 2b: a fabricated id genuinely returns zero rows -- proves the DB-lookup
  # mechanism does not false-match on an id that was never registered.
  FABRICATED_ROW="$(sqlite3 -readonly "$DB" \
    "SELECT atm_id FROM item_history WHERE atm_id='ATM-99999-NEGATIVE-CONTROL';" 2>&1)"
  chk "needle #2b (known-absent): a fabricated id (ATM-99999-NEGATIVE-CONTROL) returns zero item_history rows (got '$FABRICATED_ROW')" \
    "$([ -z "$FABRICATED_ROW" ] && echo 1 || echo 0)"
fi

# ---------------------------------------------------------------------------
# Fixture self-check: all four fixture dirs exist, each has a valid input.yaml
# and expected.json.
# ---------------------------------------------------------------------------
for fx in ec_good_atm953_e1 ec_good_e7_design_reconsidered ec_bad_no_evidence_path ec_negctrl_atm799_e4_no_e9; do
  for f in input.yaml expected.json; do
    chk "fixture $fx/$f exists" "$([ -f "$FX/$fx/$f" ] && echo 1 || echo 0)"
  done
  python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$FX/$fx/input.yaml" >/dev/null 2>"$TMP/yerr"
  chk "fixture $fx/input.yaml parses as YAML" "$([ $? -eq 0 ] && echo 1 || echo 0)"
  python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$FX/$fx/expected.json" >/dev/null 2>"$TMP/jerr"
  chk "fixture $fx/expected.json parses as JSON" "$([ $? -eq 0 ] && echo 1 || echo 0)"
done

# ---------------------------------------------------------------------------
# Core RED assertion: is escape_classify.py implemented yet?
# ---------------------------------------------------------------------------
if [ -e "$TOOL" ]; then
  info "escape_classify.py EXISTS at $TOOL -- assertions below run for real (GREEN mode)."
else
  info "escape_classify.py ABSENT at $TOOL -- this is the RED baseline; every fixture below is expected to fail."
fi
chk "escape_classify.py implemented ($TOOL)" "$([ -e "$TOOL" ] && echo 1 || echo 0)"

chk "config/fastcycle/fastcycle.yaml exists (the real --config this test uses)" \
  "$([ -f "$CONFIG" ] && echo 1 || echo 0)"

# classify_call <fixture-dir> <out-file>: invokes the real CLI shape (see
# header UNCONFIRMED block); sets $RC to its exit status, $ERR_FILE content
# captured for message-substring checks. Identical call whether the tool
# exists or not -- the natural absence of $TOOL is what makes this RED today,
# not a branch in this function. Invoked with cwd=$ROOT so config-relative
# paths (workable_items_db: docs/workable_items.db) resolve correctly.
classify_call() {
  local fxdir="$1" outfile="$2" as_of window_days
  as_of="$(python3 -c "import yaml; print(yaml.safe_load(open('$fxdir/input.yaml'))['as_of'])")"
  window_days="$(python3 -c "import yaml; print(yaml.safe_load(open('$fxdir/input.yaml'))['window_days'])")"
  ( cd "$ROOT" && timeout -k 2 "$CLASSIFY_TIMEOUT_S" python3 "$TOOL" \
      --config "$CONFIG" --as-of "$as_of" --window-days "$window_days" \
      --classifications "$fxdir/input.yaml" --out "$outfile" \
      >"$TMP/out" 2>"$TMP/err" )
  RC=$?
}

# find_item_in_json <json-file> <item_id>: prints, as a one-line JSON object,
# the FIRST dict found anywhere in <json-file> (recursively, through dicts and
# lists) whose "item_id" field equals <item_id> -- or "{}" if the file is
# absent/unreadable/malformed/has no such entry. Never raises -- an unreadable
# file or missing entry is honestly "{}" (no invented value, constitution
# 11.4.6), which naturally fails every field-equality check below against a
# non-empty expected value. This is what makes the checker robust to T094's
# eventual top-level container key name (rows/classifications/items/...)
# while still performing a real, per-field comparison.
find_item_in_json() {
  python3 - "$1" "$2" <<'PY'
import json, sys

def walk(node, target):
    if isinstance(node, dict):
        if node.get("item_id") == target:
            return node
        for v in node.values():
            found = walk(v, target)
            if found is not None:
                return found
    elif isinstance(node, list):
        for v in node:
            found = walk(v, target)
            if found is not None:
                return found
    return None

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    doc = None

result = walk(doc, sys.argv[2]) if doc is not None else None
print(json.dumps(result if result is not None else {}))
PY
}

# field_eq <found-json-line> <field> <expected-json-value>: prints "1"/"0"
# (chk()'s own truthy convention, matching every other check in this file --
# see the FIXED note below), comparing found[<field>] to the parsed
# <expected-json-value> by deep equality (so a list like [869] or []
# compares correctly). Never raises.
#
# FIXED (real bug in this test's own harness, caught while driving T094's
# implementation to GREEN, 2026-09-29 -- constitution 11.4.1: "a test must
# fail only for genuine product defects, never a script-internal bug"):
# this function's `print(found.get(...) == expected)` emitted Python's
# capitalized boolean literals "True"/"False", but chk() (line 154 of this
# file) compares its second argument against the literal string "1" --
# `[ "$2" = "1" ]`. "True" != "1" and "False" != "1" unconditionally, so
# EVERY assertion routed through field_eq()/evidence_paths_superset() was
# STRUCTURALLY INCAPABLE of ever reporting PASS, regardless of whether the
# tool under test was correct -- confirmed directly: a byte-for-byte
# manually-invoked escape_classify.py run against ec_good_atm953_e1 produced
# an --out document whose every field exactly matched expected.json (primary
# E1, contributing [], detection_channel manual-testing-detected,
# reopen_events [869], both evidence paths present with matching hashes),
# yet the pre-fix version of this function still reported FAIL for every one
# of those fields. This is the exact class of bug 11.4.1 requires be fixed
# at the harness, not worked around at the call site (a "print 1 if X else
# 0" fix here, matching this file's own established chk()-compatible
# convention everywhere else, is the minimal correction -- no other
# function, expectation, or fixture value in this file changes).
field_eq() {
  python3 -c "
import json, sys
found = json.loads(sys.argv[1])
expected = json.loads(sys.argv[3])
print('1' if found.get(sys.argv[2]) == expected else '0')
" "$1" "$2" "$3" 2>/dev/null
}

# evidence_paths_superset <found-json-line> <expected-paths-json-list>:
# prints "1"/"0" (see field_eq's FIXED note immediately above -- the
# identical bug affected this function too) if every path in
# <expected-paths-json-list> appears as the "path" of some entry in
# found["evidence"] (a list of {path, content_address} dicts, per this
# test's own EvidencePath shape choice). Never raises.
evidence_paths_superset() {
  python3 -c "
import json, sys
found = json.loads(sys.argv[1])
expected_paths = json.loads(sys.argv[2])
got_paths = {e.get('path') for e in (found.get('evidence') or []) if isinstance(e, dict)}
print('1' if all(p in got_paths for p in expected_paths) else '0')
" "$1" "$2" 2>/dev/null
}

run_golden_fixture() {
  local fx="$1"
  local item_id primary contributing detection_channel reopen_events evidence_paths
  local exp="$FX/$fx/expected.json"
  item_id="$(python3 -c "import json; print(json.load(open('$exp'))['item_id'])")"
  primary="$(python3 -c "import json; print(json.load(open('$exp'))['primary'])")"
  contributing="$(python3 -c "import json; print(json.dumps(json.load(open('$exp'))['contributing']))")"
  detection_channel="$(python3 -c "import json; print(json.load(open('$exp'))['detection_channel'])")"
  reopen_events="$(python3 -c "import json; print(json.dumps(json.load(open('$exp'))['reopen_events']))")"
  evidence_paths="$(python3 -c "import json; print(json.dumps(json.load(open('$exp'))['evidence_paths_at_least']))")"

  local outfile="$TMP/$fx.escape.json"
  rm -f "$outfile"
  classify_call "$FX/$fx" "$outfile"
  info "$fx: ran (cwd=$ROOT): python3 $TOOL --config $CONFIG --as-of <fixture as_of> --window-days <fixture window_days> --classifications $FX/$fx/input.yaml --out $outfile"
  info "$fx: rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"

  chk "$fx: classify call exits 0 (valid + complete classification)" \
    "$([ "$RC" -eq 0 ] && echo 1 || echo 0)"
  chk "$fx: --out document was written ($outfile)" \
    "$([ -f "$outfile" ] && echo 1 || echo 0)"

  local found
  found="$(find_item_in_json "$outfile" "$item_id")"
  chk "$fx: item_id '$item_id' found somewhere in the --out document" \
    "$([ "$found" != "{}" ] && echo 1 || echo 0)"
  chk "$fx: $item_id.primary == '$primary' (found: $(echo "$found" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("primary"))' 2>/dev/null))" \
    "$(field_eq "$found" primary "\"$primary\"")"
  chk "$fx: $item_id.contributing == $contributing" \
    "$(field_eq "$found" contributing "$contributing")"
  chk "$fx: $item_id.detection_channel == '$detection_channel'" \
    "$(field_eq "$found" detection_channel "\"$detection_channel\"")"
  chk "$fx: $item_id.reopen_events == $reopen_events" \
    "$(field_eq "$found" reopen_events "$reopen_events")"
  chk "$fx: $item_id.evidence includes every expected path" \
    "$(evidence_paths_superset "$found" "$evidence_paths")"

  echo "$outfile"
}

echo
echo "=== T094 contract check 1/4: golden ATM-953 -> E1 wrong-layer-evidence (task line; data-model.md §6.1) ==="
# NOTE: run_golden_fixture's own trailing `echo "$outfile"` (a command-
# substitution-style "return value", unused here -- this fixture's --out file
# is not consulted again after this call, unlike ec_good_e7's $E7_OUT which
# feeds the count check below) is intentionally left UNCAPTURED (no
# `x=$(...)`, no output redirection at all) so every chk()/info() line this
# call produces prints directly to this script's own stdout as intended. A
# previous version of this line piped the whole call to `>/dev/null` meaning
# to discard only that trailing echo, which instead silently swallowed every
# diagnostic/PASS/FAIL line for this fixture (a real bug in this test's own
# harness, caught and fixed on first run, 2026-09-29; the swallowed checks
# still counted toward N/FAIL via chk()'s global variables, so no assertion
# was skipped -- only its VISIBLE evidence was). The harmless extra line this
# now prints (the bare $outfile path from that trailing echo) is left as-is,
# matching this file's existing info()-heavy verbosity elsewhere.
run_golden_fixture ec_good_atm953_e1

echo
echo "=== T094 contract check 2/4: golden SPK-609/ATM-610/ATM-611 -> E7 design-reconsidered (task line) ==="
# ec_good_e7_design_reconsidered has 3 expected items -- run_golden_fixture's
# single-item helper only reads expected.json's top-level item_id/primary/...
# keys, which that fixture's expected.json does not carry at the top level
# (it carries items: [...] instead, per that fixture's own expected.json
# design). Handle the 3-item case explicitly here, reusing classify_call() +
# find_item_in_json()/field_eq()/evidence_paths_superset() directly.
E7_OUT="$TMP/ec_good_e7_design_reconsidered.escape.json"
rm -f "$E7_OUT"
classify_call "$FX/ec_good_e7_design_reconsidered" "$E7_OUT"
info "ec_good_e7_design_reconsidered: rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"
chk "ec_good_e7_design_reconsidered: classify call exits 0" "$([ "$RC" -eq 0 ] && echo 1 || echo 0)"
chk "ec_good_e7_design_reconsidered: --out document was written ($E7_OUT)" "$([ -f "$E7_OUT" ] && echo 1 || echo 0)"
E7_ITEM_COUNT="$(python3 -c "import json; d=json.load(open('$FX/ec_good_e7_design_reconsidered/expected.json')); print(len(d['items']))")"
for i in $(seq 0 $((E7_ITEM_COUNT - 1))); do
  item_id="$(python3 -c "import json; print(json.load(open('$FX/ec_good_e7_design_reconsidered/expected.json'))['items'][$i]['item_id'])")"
  primary="$(python3 -c "import json; print(json.load(open('$FX/ec_good_e7_design_reconsidered/expected.json'))['items'][$i]['primary'])")"
  detection_channel="$(python3 -c "import json; print(json.load(open('$FX/ec_good_e7_design_reconsidered/expected.json'))['items'][$i]['detection_channel'])")"
  reopen_events="$(python3 -c "import json; print(json.dumps(json.load(open('$FX/ec_good_e7_design_reconsidered/expected.json'))['items'][$i]['reopen_events']))")"
  evidence_paths="$(python3 -c "import json; print(json.dumps(json.load(open('$FX/ec_good_e7_design_reconsidered/expected.json'))['items'][$i]['evidence_paths_at_least']))")"
  found="$(find_item_in_json "$E7_OUT" "$item_id")"
  chk "ec_good_e7: item_id '$item_id' found in --out document" "$([ "$found" != "{}" ] && echo 1 || echo 0)"
  chk "ec_good_e7: $item_id.primary == '$primary'" "$(field_eq "$found" primary "\"$primary\"")"
  chk "ec_good_e7: $item_id.detection_channel == '$detection_channel'" "$(field_eq "$found" detection_channel "\"$detection_channel\"")"
  chk "ec_good_e7: $item_id.reopen_events == $reopen_events" "$(field_eq "$found" reopen_events "$reopen_events")"
  chk "ec_good_e7: $item_id.evidence includes the expected path" "$(evidence_paths_superset "$found" "$evidence_paths")"
done

echo
echo "=== count check (task line: 'count check: rows == distinct reopened items') ==="
# Live cross-check against the REAL DB (not a frozen claim in this file's own
# comments): the 2026-07-07 window genuinely holds exactly 3 distinct
# reopened items right now.
LIVE_COUNT_707="$(sqlite3 -readonly "$DB" "SELECT COUNT(DISTINCT atm_id) FROM item_history WHERE event_type='Reopened' AND on_date='2026-07-07';" 2>&1)"
chk "live DB: window 2026-07-07 has exactly 3 distinct reopened items right now (got '$LIVE_COUNT_707')" \
  "$([ "$LIVE_COUNT_707" = "3" ] && echo 1 || echo 0)"
EXPECTED_ROW_COUNT="$(python3 -c "import json; print(json.load(open('$FX/ec_good_e7_design_reconsidered/expected.json'))['expected_row_count_for_window'])")"
chk "ec_good_e7_design_reconsidered/expected.json's own expected_row_count_for_window (3) matches the live DB count" \
  "$([ "$EXPECTED_ROW_COUNT" = "$LIVE_COUNT_707" ] && echo 1 || echo 0)"
if [ -f "$E7_OUT" ]; then
  GOT_ROW_COUNT="$(python3 - "$E7_OUT" <<'PY'
import json, sys

def count_leaf_items(node):
    n = 0
    if isinstance(node, dict):
        if "item_id" in node and "primary" in node:
            n += 1
        else:
            for v in node.values():
                n += count_leaf_items(v)
    elif isinstance(node, list):
        for v in node:
            n += count_leaf_items(v)
    return n

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    doc = None
print(count_leaf_items(doc) if doc is not None else -1)
PY
)"
  chk "escape_classify.py's real --out row count for the 2026-07-07 window == 3 (got '$GOT_ROW_COUNT')" \
    "$([ "$GOT_ROW_COUNT" = "3" ] && echo 1 || echo 0)"
else
  chk "escape_classify.py's real --out row count for the 2026-07-07 window == 3 (SKIPPED: no --out file, tool absent or refused)" 0
fi

echo
echo "=== T094 contract check 3/4: golden-bad -- a row with no evidence path fails (task line; EC-002) ==="
BAD_OUT="$TMP/ec_bad_no_evidence_path.escape.json"
rm -f "$BAD_OUT"
classify_call "$FX/ec_bad_no_evidence_path" "$BAD_OUT"
info "ec_bad_no_evidence_path: rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"
EXP_BAD_RC="$(python3 -c "import json; print(json.load(open('$FX/ec_bad_no_evidence_path/expected.json'))['expected_exit_code'])")"
chk "ec_bad_no_evidence_path: refused (exit $EXP_BAD_RC) for an entry with zero EvidencePath entries" \
  "$([ "$RC" = "$EXP_BAD_RC" ] && echo 1 || echo 0)"
chk "ec_bad_no_evidence_path: no --out document written on refusal" \
  "$([ ! -f "$BAD_OUT" ] && echo 1 || echo 0)"
BAD_MSG="$(cat "$TMP/out" "$TMP/err" 2>/dev/null)"
BAD_MUST_MENTION="$(python3 -c "import json; print(' '.join(json.load(open('$FX/ec_bad_no_evidence_path/expected.json'))['expected_message_must_mention']))")"
BAD_MENTIONS_OK=1
for token in $BAD_MUST_MENTION; do
  case "$BAD_MSG" in
    *"$token"*) : ;;
    *) BAD_MENTIONS_OK=0 ;;
  esac
done
chk "ec_bad_no_evidence_path: refusal message mentions each of: $BAD_MUST_MENTION" "$BAD_MENTIONS_OK"

echo
echo "=== T094 contract check 4/4: negative control -- complete evidence classifies without E9 (task line; §11.4.201(1)) ==="
NC_OUT="$TMP/ec_negctrl_atm799_e4_no_e9.escape.json"
rm -f "$NC_OUT"
classify_call "$FX/ec_negctrl_atm799_e4_no_e9" "$NC_OUT"
info "ec_negctrl_atm799_e4_no_e9: rc=$RC stderr='$(cat "$TMP/err" 2>/dev/null)'"
chk "ec_negctrl_atm799_e4_no_e9: classify call exits 0 (accepted -- complete evidence, not a refusal)" \
  "$([ "$RC" -eq 0 ] && echo 1 || echo 0)"
chk "ec_negctrl_atm799_e4_no_e9: --out document was written ($NC_OUT)" \
  "$([ -f "$NC_OUT" ] && echo 1 || echo 0)"
NC_FOUND="$(find_item_in_json "$NC_OUT" "ATM-799")"
chk "ec_negctrl_atm799_e4_no_e9: item_id 'ATM-799' found in --out document" \
  "$([ "$NC_FOUND" != "{}" ] && echo 1 || echo 0)"
# NC_GOT_PRIMARY: the raw "primary" value if present, else the literal string
# "<NOT-FOUND>" -- deliberately NOT Python's None-as-string ("None"), so the
# not-E9 check below cannot vacuously pass just because the item was never
# found (a real bug caught while first running this test: `"None" != "E9"` is
# true, so an absent item silently "passed" the not-E9 assertion -- exactly
# the §11.4.201(1) false-positive class this file exists to prevent).
if [ "$NC_FOUND" = "{}" ]; then
  NC_GOT_PRIMARY="<NOT-FOUND>"
else
  NC_GOT_PRIMARY="$(echo "$NC_FOUND" | python3 -c 'import json,sys; v=json.load(sys.stdin).get("primary"); print(v if isinstance(v, str) and v else "<NOT-FOUND>")' 2>/dev/null)"
fi
chk "ec_negctrl_atm799_e4_no_e9: ATM-799.primary != 'E9' (load-bearing assertion; requires the item to be FOUND with a real primary value, not merely absent; got '$NC_GOT_PRIMARY')" \
  "$([ "$NC_GOT_PRIMARY" != "E9" ] && [ "$NC_GOT_PRIMARY" != "<NOT-FOUND>" ] && echo 1 || echo 0)"

# Self-validation control needle (§11.4.107(10)/§11.4.201(1)) for the not-E9
# check immediately above: proves the "!=E9 AND !=<NOT-FOUND>" discrimination
# logic genuinely tells apart three cases -- (a) found with a real non-E9
# primary [MUST pass], (b) found with primary E9 [MUST fail], (c) not found at
# all [MUST fail, the exact bug this section was fixed to catch, confirmed
# live 2026-09-29: the pre-fix version of this check used `[ "$X" != "E9" ]`
# alone and PASSED on Python's `None`-as-string for an absent item]. Three
# synthetic JSON documents, written only under $TMP -- nothing on disk outside
# the temp dir is touched, nothing needs restoring.
SELFTEST_A="$TMP/.selftest_found_nonE9.json"; printf '{"item_id":"ATM-799","primary":"E4"}\n' > "$SELFTEST_A"
SELFTEST_B="$TMP/.selftest_found_E9.json";    printf '{"item_id":"ATM-799","primary":"E9"}\n' > "$SELFTEST_B"
SELFTEST_C="$TMP/.selftest_not_found.json";   printf '{"item_id":"ATM-SOMETHING-ELSE","primary":"E4"}\n' > "$SELFTEST_C"
selftest_not_e9() {
  local doc="$1" found got
  found="$(find_item_in_json "$doc" "ATM-799")"
  if [ "$found" = "{}" ]; then got="<NOT-FOUND>"; else
    got="$(echo "$found" | python3 -c 'import json,sys; v=json.load(sys.stdin).get("primary"); print(v if isinstance(v, str) and v else "<NOT-FOUND>")' 2>/dev/null)"
  fi
  [ "$got" != "E9" ] && [ "$got" != "<NOT-FOUND>" ] && echo 1 || echo 0
}
chk "self-validation needle: not-E9 check PASSES on a genuinely-found non-E9 primary" "$(selftest_not_e9 "$SELFTEST_A")"
chk "self-validation needle: not-E9 check FAILS on a genuinely-found E9 primary" \
  "$([ "$(selftest_not_e9 "$SELFTEST_B")" = "0" ] && echo 1 || echo 0)"
chk "self-validation needle: not-E9 check FAILS on an item that was NOT found at all (the pre-fix bug this file was caught and corrected against)" \
  "$([ "$(selftest_not_e9 "$SELFTEST_C")" = "0" ] && echo 1 || echo 0)"

chk "ec_negctrl_atm799_e4_no_e9: ATM-799.primary == 'E4' (this fixture's own grounded claim, non-load-bearing per §11.4.201(1); got '$NC_GOT_PRIMARY')" \
  "$(field_eq "$NC_FOUND" primary '"E4"')"
NC_EVIDENCE_PATHS="$(python3 -c "import json; print(json.dumps(json.load(open('$FX/ec_negctrl_atm799_e4_no_e9/expected.json'))['evidence_paths_at_least']))")"
chk "ec_negctrl_atm799_e4_no_e9: ATM-799.evidence includes every expected path" \
  "$(evidence_paths_superset "$NC_FOUND" "$NC_EVIDENCE_PATHS")"

echo
echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
