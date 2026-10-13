#!/bin/bash
# Purpose: T092 (SpecKit-004 "fast-dev-cycles", User Story 3) RED baseline for
#          T101's triage of the 13-item 2nd-display defect family
#          (tasks.md T101: "Triage the 13 2nd-display items against ATM-953's
#          reopen evidence (recurrence -> linked + reopened / distinct ->
#          candidate link kept / undetermined -> evidence named), applying
#          link edits through the single tracker writer after a §9.2 backup,
#          until T092 is GREEN"; plan.md T-D07; research.md RC-23/U-21).
#
# This file pins the EXPECTED POST-TRIAGE STATE T101 must produce -- "every
# one of the 13 items carries a verdict with an evidence path" (T092's own
# task line) -- and proves the R1:66 control needle: a title-only search
# misses a known body-text/evidence-file match, so a correct triage (and this
# test's own checker) reads bodies and evidence files, never titles alone.
#
# RED baseline (confirmed live against the real tracker, 2026-09-29): NONE of
# the 13 items carry any item_history row matching the closed-set verdict
# vocabulary defined below -- every one of the 13 chk() calls in the "Core
# RED assertion" section is therefore expected to FAIL today. This test does
# NOT perform the triage itself (that is T101's own, later, separate,
# [SERIAL] job, applied through the existing tracker writer
# constitution/scripts/workable-items/bin/workable-items after a §9.2
# backup) -- it is strictly READ-ONLY against docs/workable_items.db
# throughout (constitution 11.4.240 producer != verifier: the author of this
# RED test never performs the mutation it gates).
#
# The 13 items (research/R1_baseline_cycle_time.md line 68, "at least
# ATM-787, 792, 793, 801, 809, 814, 893, 920, 922, 925, 926, 933, 934 (13
# items, statuses Queued/Ready for testing) describe video not
# routed/mirrored to the 2nd display for different apps"), INDEPENDENTLY
# RE-CONFIRMED live against docs/workable_items.db (2026-09-29, needle set
# #3 below) -- exactly 13, all type=Bug, all status IN
# (Queued, Ready for testing), all in Issues (never closed). No discrepancy
# from R1's count was found (constitution 11.4.6: this is a checked FACT,
# not assumed from the frozen doc).
#
# ATM-953 ("Video ±subtitles on 2nd display does not work at all -- video
# apps enter endless mode-switch loop, end in ANR/crash (0.1.3 live QA)",
# status Reopened) is the "reopen evidence" the 13 items are triaged against
# (T101's own task line). Its real, on-disk, live-readable reopen-evidence
# file is qa-results/atm953_reopen_20260728/REOPEN_EVIDENCE.md
# (item_history rowid 869, Reopened 2026-07-28, By=User,
# reason=manual-testing-detected -- confirmed live below).
#
# R1:66 CITATION-DRIFT NOTE (constitution 11.4.6 -- documented honestly,
# never silently corrected): tasks.md T092's own task line cites "R1:66"
# and plan.md T-D07 repeats the same citation ("the control needle of
# R1:66 (title search misses body text)"); research.md itself independently
# cites the SAME needle at "R1:66" three times (lines 96, 97, 129 as
# "R1:65"/"R1:66"). Live-checked against the CURRENT
# research/R1_baseline_cycle_time.md (2026-09-29): the control-needle
# sentence itself is at line 69 (title-search-misses-body-text) and the
# 13-item enumeration it is paired with is at line 68 -- a 2-3 line
# downward drift from the "R1:66"/"R1:65" citations, evidently from edits to
# that file made after the citing documents were written. The CONTENT this
# test needs (the exact needle: a title-only LIKE search for "endless loop"
# returns 0 rows although ATM-953's own reopen-evidence file contains that
# phrase verbatim) is unambiguously present and is independently
# live-verified below against the real tracker + the real evidence file
# (never trusted from the frozen doc alone) -- the line-number drift is
# reported here as a fact, not silently "fixed" by re-editing the citing
# docs (out of this task's scope) and not treated as a discrepancy in the
# needle's SUBSTANCE, which matches exactly.
#
# UNCONFIRMED (constitution 11.4.6 -- this test's OWN choice, fixed here
# BEFORE T101 exists, binding on T101 unless T101 records an explicit,
# evidenced deviation -- mirrors test_escape_classify_red.sh's identical
# practice for escape_classify.py's --out schema):
#
#   Storage mechanism: T101's task line describes an OUTCOME ("recurrence ->
#   linked + reopened / distinct -> candidate link kept / undetermined ->
#   evidence named"), not a schema. docs/workable_items.db has no "verdict"
#   column anywhere (schema-checked live below). Rather than invent a schema
#   migration (out of scope for a [P] RED test; T101 itself is [SERIAL] and
#   explicitly "applies link edits through the single tracker writer" --
#   i.e. the ALREADY-IMPLEMENTED constitution/scripts/workable-items binary,
#   never a new tool), this test reuses the EXISTING, already-implemented,
#   general-purpose §11.4.34 audit mechanism every mutating subcommand of
#   that binary already writes to: an item_history row
#   (atm_id, event_type, reason, evidence_path). In particular the already-
#   landed `move` subcommand
#   (constitution/scripts/workable-items/cmd/workable-items/mutate.go,
#   "move -- the general REVERSE-OF-CLOSE relocation ... WITHOUT the
#   §11.4.34 reopen semantics") already writes exactly
#   (event_type='Updated', reason=<free text>, evidence_path=<path>) triples
#   WITHOUT forcing a status transition -- the natural existing mechanism
#   for the candidate-link-kept / undetermined-evidence-named verdicts on
#   items that stay open (constitution 11.4.214's "Open-original case":
#   "a matched item still OPEN gets LINK-ONLY -- 'reopen an open item' is
#   undefined ... an open item is not telling [the closed-as-fixed-and-
#   it-is-not lie]" -- all 13 of these items are currently
#   Queued/Ready-for-testing, i.e. OPEN, never Fixed, so a literal status
#   flip to Reopened via the `reopen` subcommand is NOT required by this
#   test for ANY of the three verdicts; T101 MAY additionally invoke
#   `reopen` on a specific item if it independently judges that correct,
#   but this test's verdict check below is satisfied by the item_history
#   row alone, regardless of which subcommand wrote it or whether the
#   item's own `status` column ever changes).
#
#   Verdict token vocabulary (closed set, hyphenated directly from T101's
#   own task-line wording, never invented beyond that): a matching
#   item_history.reason value is EXACTLY one of
#     linked-reopened | candidate-link-kept | undetermined-evidence-named
#   OR begins with "<token>:" (colon), so T101 may append free-text detail
#   after the fixed token (e.g. "linked-reopened: recurrence of ATM-953,
#   shared root cause per REOPEN_EVIDENCE.md"). A reason value outside this
#   set (any event_type) never counts as a verdict, no matter how plausible
#   -- proven by this test's own negative-control self-validation fixture
#   below (an unrelated real reason, "operator-blocked", correctly does NOT
#   count).
#
#   Evidence-path requirement ("... with an evidence path", T092's own task
#   line): the matching row's evidence_path column must be non-empty AND,
#   interpreted relative to the repo root ($ROOT -- the SAME repo-relative
#   convention ATM-953's own item_history evidence_path already uses:
#   "qa-results/atm953_reopen_20260728/REOPEN_EVIDENCE.md"), resolve to a
#   real, existing, non-empty file. A non-empty path string alone is NOT
#   sufficient (proven by this test's own golden-bad self-validation
#   fixture below, whose evidence_path names a file that is never created).
#
#   Multiplicity: if an item somehow accumulates more than one matching row
#   (e.g. T101 revises its own verdict), this test reads the MOST RECENT one
#   (MAX(id), item_history's own insertion-order primary key) as
#   authoritative -- an explicit, documented choice, never an unstated
#   assumption.
#
# Fixtures: unlike test_escape_classify_red.sh (which gates a standalone
# --config/--out CLI tool and therefore pins that tool's exact invocation
# shape with committed input.yaml/expected.json fixture pairs), this test's
# assertions run directly against the LIVE tracker DB
# (docs/workable_items.db) and a LIVE, already-existing, on-disk evidence
# file (qa-results/atm953_reopen_20260728/REOPEN_EVIDENCE.md) -- there is no
# separate tool whose CLI contract needs fixture-driven pinning (T101 is a
# [SERIAL] triage TASK performed through the already-implemented tracker
# writer, not a new program this test's fixtures would drive). This test
# therefore constructs NO
# constitution/scripts/fastcycle/tests/fixtures/2nd_display_triage/
# directory. In its place, this test's own verdict-detection logic
# (verdict_ok(), below) is self-validated (constitution 11.4.107(10)/
# 11.4.201(1)) against a throwaway, in-$TMP, schema-minimal SQLite DB
# carrying a golden-good / golden-bad / negative-control / not-yet-triaged
# quadruple -- proving the checker discriminates all four cases correctly
# BEFORE it is trusted against the real 13 items.
#
# Usage: bash test_2nd_display_triage_red.sh   Exit 0 = every real assertion
#        below held (control needles, live 13-item + ATM-953-evidence
#        confirmation, self-validation quadruple, and all 13 real verdict
#        checks) -- only possible once T101 is GREEN; nonzero = FAIL
#        count>0 (today, RED).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$FC/../../.." && pwd)"
DB="$ROOT/docs/workable_items.db"
EVIDENCE_953="qa-results/atm953_reopen_20260728/REOPEN_EVIDENCE.md"

TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
reap_children() {
  # Process-leak guard (matches test_escape_classify_red.sh /
  # test_review_record_red.sh convention): kill anything this test spawned
  # whose command line names $TMP.
  pkill -KILL -f "$TMP" 2>/dev/null
  return 0
}
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM

FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "INFO: $1"; }

# The 13 items, in the exact order research/R1_baseline_cycle_time.md:68
# lists them.
ITEMS="ATM-787 ATM-792 ATM-793 ATM-801 ATM-809 ATM-814 ATM-893 ATM-920 ATM-922 ATM-925 ATM-926 ATM-933 ATM-934"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "FAIL: sqlite3 not on PATH -- cannot run any of the checks below;"
  echo "      this is an environment gap, not a finding about T101"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi
if [ ! -f "$DB" ]; then
  echo "FAIL: tracker DB not found at $DB -- cannot run any of the checks below"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi

# -----------------------------------------------------------------------
# constitution 11.4.273 control-needle discipline (needle set #1: this
# test's own file-existence-check mechanism, generic self-check before
# trusting it against real evidence files below).
# -----------------------------------------------------------------------
NEEDLE_PRESENT="$TMP/.needle_present_marker"
printf 'x\n' > "$NEEDLE_PRESENT"
chk "control needle #1a: a known-present, non-empty file IS found by the existence+non-empty check" \
  "$([ -s "$NEEDLE_PRESENT" ] && echo 1 || echo 0)"
NEEDLE_FABRICATED="$TMP/.needle_fabricated_never_created_$$_$(date +%s 2>/dev/null || echo x)"
chk "control needle #1b: a fabricated (never-created) path IS reported absent" \
  "$([ ! -e "$NEEDLE_FABRICATED" ] && echo 1 || echo 0)"
rm -f "$NEEDLE_PRESENT"

# -----------------------------------------------------------------------
# constitution 11.4.273 control-needle discipline (needle set #2: the R1:66
# control needle itself -- LIVE against the real tracker DB and the real
# on-disk evidence file, proving a title-only search misses a known
# body-text/evidence-file match, per T092's own task line).
# -----------------------------------------------------------------------
echo
echo "=== needle set #2: R1:66 control needle (live, 2026-09-29) ==="

# 2a (the load-bearing half): a title-only LIKE search for the CONTIGUOUS
# phrase "endless loop" returns ZERO rows. ATM-953's own title reads
# "...video apps enter endless mode-switch loop..." -- "endless" and "loop"
# are both present but NOT contiguous (the words "mode-switch" sit between
# them), so a naive title substring match genuinely misses it.
TITLE_HITS_ENDLESS_LOOP="$(sqlite3 -readonly "$DB" \
  "SELECT COUNT(*) FROM items WHERE title LIKE '%endless loop%';" 2>&1)"
chk "needle #2a: title-only search for 'endless loop' returns 0 rows (got '$TITLE_HITS_ENDLESS_LOOP') -- proves title-only search misses this match" \
  "$([ "$TITLE_HITS_ENDLESS_LOOP" = "0" ] && echo 1 || echo 0)"

# 2b: the SAME phrase IS present, verbatim, in ATM-953's own real,
# on-disk reopen-evidence file -- proving a title-only search is blind to
# exactly the evidence T101's triage (and this checker) must read.
if [ ! -f "$ROOT/$EVIDENCE_953" ]; then
  chk "needle #2b: ATM-953's real reopen-evidence file exists at $EVIDENCE_953" 0
  chk "needle #2b: 'endless loop' is present verbatim in ATM-953's evidence file body (SKIPPED: file absent)" 0
else
  chk "needle #2b: ATM-953's real reopen-evidence file exists at $EVIDENCE_953" 1
  EVIDENCE_HITS="$(grep -c "endless loop" "$ROOT/$EVIDENCE_953" 2>/dev/null || echo 0)"
  chk "needle #2b: 'endless loop' is present verbatim in ATM-953's evidence file body (got $EVIDENCE_HITS occurrence(s)) -- proves the phrase is genuinely in the body/evidence text, not merely claimed" \
    "$([ "$EVIDENCE_HITS" -ge 1 ] 2>/dev/null && echo 1 || echo 0)"
fi

# 2c (positive control): a title-only search for a phrase genuinely present
# IN a title ("Apple TV") DOES find rows, including ATM-239/792/793 among
# them (research.md line 96's own citation) -- proves the title-search
# MECHANISM itself works and 2a is not merely a broken query.
APPLETV_HITS="$(sqlite3 -readonly "$DB" \
  "SELECT COUNT(*) FROM items WHERE title LIKE '%Apple TV%';" 2>&1)"
chk "needle #2c (positive control): title-only search for 'Apple TV' finds >=1 row (got '$APPLETV_HITS')" \
  "$([ "$APPLETV_HITS" -ge 1 ] 2>/dev/null && echo 1 || echo 0)"
APPLETV_IDS="$(sqlite3 -readonly "$DB" \
  "SELECT atm_id FROM items WHERE title LIKE '%Apple TV%' ORDER BY atm_id;" 2>&1 | tr '\n' ',')"
case "$APPLETV_IDS" in
  *"ATM-239"*"ATM-792"*"ATM-793"*) APPLETV_TRIO_OK=1 ;;
  *) APPLETV_TRIO_OK=0 ;;
esac
chk "needle #2c: ATM-239/792/793 are among the 'Apple TV' title hits (research.md line 96's own citation; got '$APPLETV_IDS')" \
  "$APPLETV_TRIO_OK"

# -----------------------------------------------------------------------
# needle set #3: live, independent re-confirmation of the 13-item family
# (not trusted from the frozen R1 doc alone -- constitution 11.4.245
# independent-oracle-derivation).
# -----------------------------------------------------------------------
echo
echo "=== needle set #3: live re-confirmation of the 13-item 2nd-display family ==="
LIVE_COUNT_13="$(sqlite3 -readonly "$DB" \
  "SELECT COUNT(*) FROM items WHERE atm_id IN ('ATM-787','ATM-792','ATM-793','ATM-801','ATM-809','ATM-814','ATM-893','ATM-920','ATM-922','ATM-925','ATM-926','ATM-933','ATM-934');" 2>&1)"
chk "live DB: all 13 R1-cited ids resolve to exactly 13 rows (got '$LIVE_COUNT_13', no missing/duplicated id)" \
  "$([ "$LIVE_COUNT_13" = "13" ] && echo 1 || echo 0)"

BAD_TYPE_OR_STATUS="$(sqlite3 -readonly "$DB" \
  "SELECT COUNT(*) FROM items WHERE atm_id IN ('ATM-787','ATM-792','ATM-793','ATM-801','ATM-809','ATM-814','ATM-893','ATM-920','ATM-922','ATM-925','ATM-926','ATM-933','ATM-934') AND (type != 'Bug' OR status NOT IN ('Queued','Ready for testing') OR current_location != 'Issues');" 2>&1)"
chk "live DB: every one of the 13 is type=Bug, status IN (Queued, Ready for testing), current_location=Issues -- matches R1's own characterization exactly (got $BAD_TYPE_OR_STATUS mismatches)" \
  "$([ "$BAD_TYPE_OR_STATUS" = "0" ] && echo 1 || echo 0)"

ROW_953="$(sqlite3 -readonly "$DB" \
  "SELECT id||'|'||event_type||'|'||by||'|'||on_date||'|'||reason||'|'||evidence_path FROM item_history WHERE atm_id='ATM-953' AND event_type='Reopened';" 2>&1)"
chk "live DB: ATM-953's real Reopened row is rowid 869 (By=User, On=2026-07-28, evidence=$EVIDENCE_953) (got '$ROW_953')" \
  "$([ "$ROW_953" = "869|Reopened|User|2026-07-28|manual-testing-detected|$EVIDENCE_953" ] && echo 1 || echo 0)"

FABRICATED_ID="$(sqlite3 -readonly "$DB" \
  "SELECT atm_id FROM items WHERE atm_id='ATM-99999-NEGATIVE-CONTROL';" 2>&1)"
chk "needle (known-absent): a fabricated id (ATM-99999-NEGATIVE-CONTROL) matches zero items rows (got '$FABRICATED_ID')" \
  "$([ -z "$FABRICATED_ID" ] && echo 1 || echo 0)"

# -----------------------------------------------------------------------
# Self-validation quadruple (constitution 11.4.107(10)/11.4.201(1)): proves
# verdict_ok()'s own discrimination logic -- golden-good / golden-bad /
# negative-control / not-yet-triaged -- against a throwaway, in-$TMP,
# schema-minimal SQLite DB BEFORE it is trusted against the real 13 items.
# Never touches docs/workable_items.db.
# -----------------------------------------------------------------------
echo
echo "=== self-validation quadruple: verdict_ok() discrimination logic ==="

SVDB="$TMP/selfcheck.db"
sqlite3 "$SVDB" <<'SQL'
CREATE TABLE item_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  atm_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  reason TEXT,
  evidence_path TEXT
);
SQL

# golden-good: SV-GOOD's most-recent row carries a valid verdict token AND
# a real, existing, non-empty evidence file (under $TMP -- verdict_ok's
# base-dir parameter, never $ROOT, for this synthetic fixture).
mkdir -p "$TMP/sv_good"
printf 'synthetic evidence body for self-validation\n' > "$TMP/sv_good/evidence.md"
sqlite3 "$SVDB" "INSERT INTO item_history (atm_id, event_type, reason, evidence_path) VALUES
  ('SV-GOOD', 'Updated', 'linked-reopened: recurrence of SV-ROOT per body read', 'sv_good/evidence.md');"

# golden-bad: SV-BAD's row carries a valid verdict token but its
# evidence_path names a file that is NEVER created -- verdict_ok must
# refuse this, proving it checks file existence, not just a non-empty
# path string.
sqlite3 "$SVDB" "INSERT INTO item_history (atm_id, event_type, reason, evidence_path) VALUES
  ('SV-BAD', 'Updated', 'candidate-link-kept: distinct symptom, kept as candidate', 'sv_bad/MISSING_evidence.md');"

# negative-control: SV-NEGCTRL's row carries a REAL, valid item_history
# reason (operator-blocked -- a genuine, unrelated §11.4.21 use of the
# reason column) with a real, existing evidence file, but the reason is
# outside the triage closed-set vocabulary -- verdict_ok must NOT count
# this as a triage verdict merely because it has some evidence path.
mkdir -p "$TMP/sv_negctrl"
printf 'unrelated operator-block evidence\n' > "$TMP/sv_negctrl/evidence.md"
sqlite3 "$SVDB" "INSERT INTO item_history (atm_id, event_type, reason, evidence_path) VALUES
  ('SV-NEGCTRL', 'Updated', 'operator-blocked', 'sv_negctrl/evidence.md');"

# not-yet-triaged: SV-UNTOUCHED has zero item_history rows at all -- the
# exact state every one of the real 13 items is in today (RED baseline).
# (no INSERT for SV-UNTOUCHED -- absence of rows IS the fixture)

# latest_reason <db> <atm_id> / latest_evidence_path <db> <atm_id>: print the
# `reason` / `evidence_path` column of item_history's MOST-RECENT row
# (MAX(id)) for <atm_id>, or "" if no row exists. TWO SEPARATE single-column
# queries (never one query concatenating both fields with an in-band
# separator) -- a real bug caught while first running this test
# (constitution 11.4.1: fixed at the harness, never worked around at the
# call site): sqlite3's CLI (list mode, this host's 3.50.6) silently
# renders NON-TAB C0 control bytes (0x01-0x1F except 0x09) in caret
# notation on output -- e.g. a literal U+001F (0x1F) unit-separator byte
# concatenated into a query's result column comes back as the TWO printable
# characters "^_", not the single 0x1F byte -- so a first version of this
# function that joined reason and evidence_path with a $'\x1f' separator
# and then split on it via bash parameter expansion NEVER found the
# separator in the sqlite3 output (it had already been mangled into "^_"
# by the CLI itself, invisible to a byte-for-byte xxd dump only once
# actually inspected) and therefore always treated the WHOLE concatenated
# string as one field -- SV-GOOD's own golden-good self-validation fixture
# below caught this immediately (verdict_ok fell through to "0" instead of
# "1" on a fixture whose row was, byte-for-byte, exactly correct). Verified
# empirically before writing this comment (constitution 11.4.6): `sqlite3
# ":memory:" "SELECT 'a'||X'1F'||'b';"` prints `a^_b`, confirmed via xxd
# against multiple C0 control bytes (0x01->^A, 0x1E->^^, 0x1F->^_; 0x09
# tab passes through unescaped) -- a real instrument trap of exactly the
# class constitution 11.4.201(7)(c) ("the path is part of the instrument")
# warns about. Two single-column queries have no separator to mangle.
latest_reason() {
  sqlite3 -readonly "$1" \
    "SELECT reason FROM item_history WHERE atm_id='$2' AND id = (SELECT MAX(id) FROM item_history WHERE atm_id='$2');" 2>/dev/null
}
latest_evidence_path() {
  sqlite3 -readonly "$1" \
    "SELECT evidence_path FROM item_history WHERE atm_id='$2' AND id = (SELECT MAX(id) FROM item_history WHERE atm_id='$2');" 2>/dev/null
}

# verdict_token <db> <atm_id>: prints the resolved verdict token
# (linked-reopened / candidate-link-kept / undetermined-evidence-named) for
# diagnostic purposes, or "<NONE>" if the latest row's reason matches
# nothing in the vocabulary (including "no row at all", since
# latest_reason then returns "", which also matches no case below) --
# independent of whether the evidence file exists; used only for info()
# lines below, never for a chk() truth value on its own.
verdict_token() {
  local reason
  reason="$(latest_reason "$1" "$2")"
  case "$reason" in
    linked-reopened|linked-reopened:*) echo linked-reopened ;;
    candidate-link-kept|candidate-link-kept:*) echo candidate-link-kept ;;
    undetermined-evidence-named|undetermined-evidence-named:*) echo undetermined-evidence-named ;;
    *) echo "<NONE>" ;;
  esac
}

# verdict_ok <db> <atm_id> <base_dir>: prints "1" iff item_history's
# MOST-RECENT row (MAX(id)) for <atm_id> has a reason matching the closed
# triage-verdict vocabulary (exact token, or "<token>:" prefix, via
# verdict_token) AND a non-empty evidence_path that resolves, under
# <base_dir>, to a real, existing, non-empty file. Prints "0" otherwise (no
# matching row, reason outside the vocabulary, empty evidence_path, or the
# evidence file is missing/empty). Never raises; a query error is honestly
# "0" (constitution 11.4.6 -- no invented pass).
verdict_ok() {
  local db="$1" atm_id="$2" base_dir="$3"
  local token evpath
  token="$(verdict_token "$db" "$atm_id")"
  [ "$token" = "<NONE>" ] && { echo 0; return; }
  evpath="$(latest_evidence_path "$db" "$atm_id")"
  [ -n "$evpath" ] || { echo 0; return; }
  [ -s "$base_dir/$evpath" ] && echo 1 || echo 0
}

chk "self-validation: golden-good (valid token + real evidence file) -> verdict_ok == 1" \
  "$([ "$(verdict_ok "$SVDB" SV-GOOD "$TMP")" = "1" ] && echo 1 || echo 0)"
chk "self-validation: golden-bad (valid token + MISSING evidence file) -> verdict_ok == 0" \
  "$([ "$(verdict_ok "$SVDB" SV-BAD "$TMP")" = "0" ] && echo 1 || echo 0)"
chk "self-validation: negative-control (real evidence file, but reason outside the closed vocabulary) -> verdict_ok == 0" \
  "$([ "$(verdict_ok "$SVDB" SV-NEGCTRL "$TMP")" = "0" ] && echo 1 || echo 0)"
chk "self-validation: not-yet-triaged (zero item_history rows) -> verdict_ok == 0" \
  "$([ "$(verdict_ok "$SVDB" SV-UNTOUCHED "$TMP")" = "0" ] && echo 1 || echo 0)"
chk "self-validation: a fabricated id with zero item_history rows -> verdict_ok == 0 (same code path as not-yet-triaged)" \
  "$([ "$(verdict_ok "$SVDB" SV-DOES-NOT-EXIST "$TMP")" = "0" ] && echo 1 || echo 0)"

# -----------------------------------------------------------------------
# Core RED assertion (T092's own task line): "every one of the 13 items
# carries a verdict with an evidence path". Checked LIVE against the real
# docs/workable_items.db, base_dir=$ROOT (the repo-relative evidence-path
# convention ATM-953's own evidence_path already uses). Every one of these
# 13 checks is expected to FAIL today (RED) -- confirmed by the live
# needle immediately below the header block's own live spot-check (0
# existing verdict rows for all 13, run manually before authoring this
# file, 2026-09-29).
# -----------------------------------------------------------------------
echo
echo "=== Core RED assertion: every one of the 13 items carries a verdict + evidence path ==="
TRIAGED_COUNT=0
for id in $ITEMS; do
  tok="$(verdict_token "$DB" "$id")"
  ok="$(verdict_ok "$DB" "$id" "$ROOT")"
  info "$id: verdict_token='$tok' verdict_ok='$ok'"
  chk "$id carries a valid triage verdict (linked-reopened | candidate-link-kept | undetermined-evidence-named) with a real, existing, non-empty evidence file" \
    "$ok"
  [ "$ok" = "1" ] && TRIAGED_COUNT=$((TRIAGED_COUNT + 1))
done
info "triaged so far: $TRIAGED_COUNT of 13"
chk "all 13 of the 13 items are triaged (T101 GREEN condition; currently $TRIAGED_COUNT/13)" \
  "$([ "$TRIAGED_COUNT" -eq 13 ] && echo 1 || echo 0)"

echo
echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
