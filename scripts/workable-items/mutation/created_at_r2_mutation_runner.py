#!/usr/bin/env python3
"""Round-2 mutation runner for the engine created_at vehicle (CON-339, restore-created-at, apply_restore_plan.sh).

usage: created_at_r2_mutation_runner.py [--worktree <git worktree root>] [--go <go binary>]
                                         [--mode targeted|full] [--only N,N] [--shard i/n] [--list]

Without --worktree (the full-suite entry point) the runner adds a detached git worktree of the COMMITTED HEAD of
this repository in a private temporary directory, runs there and removes it with `git worktree remove` (uncommitted
changes are not covered). Without --go it uses `go` from PATH.

Every mutant is an exact, UNIQUE old->new replacement made IN PLACE in <worktree> (a disposable git worktree of
the head under test, never the live checkout), followed by the test run and a byte-exact restore whose sha256 is
re-checked (a failed restore aborts the run, exit 4). A clean `git status` of the worktree is asserted at the end.
  go mutants: `go test -count=1 ./cmd/workable-items/` from <worktree>/scripts/workable-items
              (targeted: -run '^(TestCON339|TestRestoreCreatedAt)'; full: the whole package).
  sh mutants: docs/qa/engine_created_at_2026_11_13/round2/test_apply_restore_plan.sh with APPLY_TEST_ENGINE set
              to an engine built once from the UNMUTATED worktree.
Controls: the unmutated go selection and the unmutated shell suite must PASS first (else exit 3, BLIND).
Outcomes: KILLED, SURVIVED, STALE (anchor absent or not unique), BUILD-BROKEN (never counted as killed), CENSUS-ONLY
(round 4: failed only by a test that reads the source text, CENSUS_TESTS; counted like SURVIVED).
Mutants marked EQUIVALENT are expected to survive; the proof is named in their intent text.
The reviewer's mutants (REVIEWER_MUTANTS) are copied verbatim from the round-1 review's rev_mutants.py, and
REVIEWER_R2_MUTANTS verbatim from the round-2 review's probes/rev2_mutants.py (round 3: MT*, MU* are own).
"""
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
import hashlib
import os
import subprocess
import sys
import tempfile

P = "cmd/workable-items/"
REVIEWER_MUTANTS = [
    # ---- engine fix (close / md-to-db)
    ("RM01-prefix-no-separator", P + "db.go", 'prefix := id + "|"', 'prefix := id',
     "fallback matches any id that starts with this id (CON-24 takes CON-243's value)"),
    ("RM02-prior-overrides-inner", P + "db.go",
     "\t\tif _, ok := snap[k]; !ok {\n\t\t\tsnap[k] = v\n\t\t}",
     "\t\tsnap[k] = v",
     "the caller's earlier snapshot wins over the rows present at the start of the transaction"),
    ("RM03-new-item-epoch", P + "db.go", "COALESCE(?, datetime('now'))", "COALESCE(?, '1970-01-01 00:00:00')",
     "a genuinely new item re-inserted by md-to-db gets a fixed epoch instead of the write time"),
    ("RM04-sync-snapshot-after-issues", P + "sync.go",
     "\tsnap, err := takeCreatedAtSnapshot(db)\n\tif err != nil {\n\t\tfmt.Fprintf(os.Stderr, \"sync md-to-db: snapshot created_at: %v\\n\", err)\n\t\treturn exitUsage\n\t}\n",
     "\tvar snap createdAtSnapshot\n",
     "md-to-db passes an empty prior snapshot (moved item loses created_at)"),
    ("RM05-close-ignores-representation", P + "crud.go",
     "SELECT created_at FROM items WHERE atm_id=? AND current_location='Issues' AND representation=?`, id, src.repOrDefault())",
     "SELECT created_at FROM items WHERE atm_id=? AND current_location='Issues' ORDER BY representation DESC`, id)",
     "close reads created_at from whichever Issues row of the id sorts first (table before section)"),
    ("RM06-inner-snapshot-after-delete", P + "db.go",
     "\tsnap, err := takeCreatedAtSnapshot(tx)\n\tif err != nil {\n\t\treturn fmt.Errorf(\"snapshot created_at: %w\", err)\n\t}\n",
     "\tsnap := createdAtSnapshot{}\n",
     "replaceDocument takes no in-transaction snapshot (only the caller's prior; nil for replaceDocument callers)"),
    ("RM07-lookup-exact-ignores-rep", P + "db.go",
     "\tif v, ok := s[createdAtKey(id, loc, rep)]; ok {\n\t\treturn &v\n\t}",
     "\tif v, ok := s[createdAtKey(id, loc, \"section\")]; ok {\n\t\treturn &v\n\t}",
     "exact lookup always uses the section key (a table row takes the section row's value)"),
    # ---- restore guards
    ("RR01-first-event-tolerance-1s", P + "restore_created_at.go",
     "if newT.After(first) {", "if newT.After(first.Add(time.Second)) {",
     "a value one second after the first history row is accepted"),
    ("RR02-current-tolerance-1s", P + "restore_created_at.go",
     "if newT.After(curT) {", "if newT.After(curT.Add(time.Second)) {",
     "a value one second later than the current created_at is accepted"),
    ("RR03-already-before-evidence", P + "restore_created_at.go",
     "\tevRaw := strings.TrimSpace(*evidence)\n",
     "\tif ti, e := os.Stat(liveAbs); e == nil && ti != nil {\n\t\tif ldb, e2 := openDB(*dbPath); e2 == nil {\n\t\t\tvar cur string\n\t\t\tif ldb.QueryRow(`SELECT created_at FROM items WHERE atm_id=?`, *id).Scan(&cur) == nil && cur == *value {\n\t\t\t\tldb.Close()\n\t\t\t\tfmt.Printf(\"already\\n\")\n\t\t\t\treturn exitOK\n\t\t\t}\n\t\t\tldb.Close()\n\t\t}\n\t}\n\tevRaw := strings.TrimSpace(*evidence)\n",
     "'already' answered before any evidence check (bad evidence exits 0 when the value is already set)"),
    ("RR04-any-history-event-attests", P + "restore_created_at.go",
     "FROM item_history WHERE atm_id=? AND event_type='Opened' ORDER BY id`, evID)",
     "FROM item_history WHERE atm_id=? ORDER BY id`, evID)",
     "any history row of the evidence item (not only Opened) attests the value"),
    ("RR05-type-not-compared", P + "restore_created_at.go",
     "if r.typ != target.typ || r.title != target.title {", "if r.title != target.title {",
     "evidence identity check ignores the type"),
    ("RR06-journal-sidecar-not-checked", P + "restore_created_at.go",
     'for _, side := range []string{"-wal", "-journal"} {', 'for _, side := range []string{"-wal"} {',
     "a non-empty -journal next to the evidence is not refused"),
    ("RR07-no-compare-and-set", P + "restore_created_at.go",
     "WHERE atm_id=? AND current_location=? AND COALESCE(representation,'section')=? AND created_at=?`,\n\t\t*value, *id, target.loc, target.rep, target.created)",
     "WHERE atm_id=? AND current_location=? AND COALESCE(representation,'section')=?`,\n\t\t*value, *id, target.loc, target.rep)",
     "the UPDATE no longer checks the value it replaces (no compare-and-set)"),
    ("RR08-reason-newline-allowed", P + "restore_created_at.go",
     'if strings.ContainsAny(*reason, "\\r\\n") {', 'if strings.ContainsAny(*reason, "\\r") {',
     "a multi-line --reason with LF is accepted"),
    ("RR09-no-roundtrip-format-check", P + "restore_created_at.go",
     "if err != nil || t.Format(storedTimeLayout) != s {", "if err != nil {",
     "the round-trip format check is dropped (is it redundant with time.Parse?)"),
    ("RR10-any-evidence-row-matches", P + "restore_created_at.go",
     "\tfor _, r := range evRows {\n\t\tif r.typ != target.typ || r.title != target.title {\n\t\t\treturn rcaRefuse(",
     "\tfor _, r := range evRows[:1] {\n\t\tif r.typ != target.typ || r.title != target.title {\n\t\t\treturn rcaRefuse(",
     "only the first evidence row of the id is identity-checked"),
    ("RR11-bad-history-row-skipped", P + "restore_created_at.go",
     "\t\tif !ok {\n\t\t\thist.Close()\n\t\t\treturn rcaRefuse(\"HISTORY-UNREADABLE\"",
     "\t\tif !ok {\n\t\t\tcontinue\n\t\t\treturn rcaRefuse(\"HISTORY-UNREADABLE\"",
     "an unparseable history created_at is skipped instead of refused"),
    ("RR12-audit-omits-old", P + "restore_created_at.go",
     'audit := fmt.Sprintf("created-at-restored old=%q new=%q location=',
     'audit := fmt.Sprintf("created-at-restored old=%.0q new=%q location=',
     "the audit row no longer records the replaced value"),
    ("RR13-sha-of-other-file", P + "restore_created_at.go",
     "gotSHA, err := fileSHA256(evAbs)", "gotSHA, err := fileSHA256(evAbs + \"\")\n\t_ = os.Remove",
     "control mutant: syntactically different, semantically equivalent (expected SURVIVED, equivalence check of the runner)"),
    ("RR14-history-bound-uses-evidence-db", P + "restore_created_at.go",
     "hist, err := db.Query(`SELECT created_at FROM item_history WHERE atm_id=? ORDER BY id`, *id)",
     "hist, err := edb.Query(`SELECT created_at FROM item_history WHERE atm_id=? ORDER BY id`, evID)",
     "the first-event bound is read from the evidence db instead of the live db"),
    ("RR15-dry-run-skips-current-bound", P + "restore_created_at.go",
     "\tif newT.After(curT) {\n", "\tif newT.After(curT) && !*dryRun {\n",
     "dry run does not apply the later-than-current refusal (dry run reports a would-write the real run refuses)"),
]

# Tests that read the source text instead of running it (round 4). Their failure is not a behavioural kill.
CENSUS_TESTS = {"TestRestoreCreatedAtR4_ComparisonCensus"}

EQUIVALENT = {
    "RR13-sha-of-other-file": "reviewer's control: evAbs + \"\" is evAbs; os.Remove is never called",
    "RR09-no-roundtrip-format-check": "argument: the regexp fixes every field width, time.Parse rejects out-of-range "
                                      "fields instead of normalising them, Format re-emits the same widths; checked by the "
                                      "FACTORED (not exhaustive) tool round2/rr09_equivalence.txt (0 counterexamples)",
    "MS11-git-show-failure-ignored": "the next statement `mv -- \"$tmp\" \"$dest\" || exit 3` fails because $tmp "
                                     "was just removed, so the script still exits 3 with nothing written; only an "
                                     "extra mv error line on stderr differs",
    "MV12-earliest-row-not-after": "only a tie differs (a row whose time equals the current first replaces it); "
                                   "parseStoredTime accepts only the canonical form, so equal times have equal text "
                                   "and first and firstRaw end up identical",
    "MV17-current-not-before": "!Before(curT) differs from After(curT) only when the value equals the current one, "
                               "and that case returns 'already' two statements earlier (target.created == *value, "
                               "both canonical text), so the line is never reached with equal times",
    "MV19-sidecar-ge-1": "os.FileInfo.Size() is an int64: > 0 and >= 1 are the same predicate",
}

R = P + "restore_created_at.go"
APPLIER = "docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh"

REVIEWER_R2_MUTANTS = [
    # copied verbatim (old/new/intent) from the round-2 review's probes/rev2_mutants.py; only the path is
    # rewritten from repository-relative to this runner's form (module-relative for Go, repository-relative for sh)
    ('VM01-lower-bound-skipped-in-dry-run', P + 'restore_created_at.go',
     'if newT.Before(trackerT.Add(-rcaTrackerSlack)) {',
     'if newT.Before(trackerT.Add(-rcaTrackerSlack)) && !*dryRun {',
     'VALUE-BEFORE-TRACKER only in a real run (dry run reports a would-write the real run refuses)'),
    ('VM02-title-compare-case-insensitive', P + 'restore_created_at.go',
     'if r.typ != target.typ || r.title != target.title {\n\t\t\treturn rcaRefuse("EVIDENCE-ITEM-MISMATCH"',
     'if r.typ != target.typ || !strings.EqualFold(r.title, target.title) {\n\t\t\treturn rcaRefuse("EVIDENCE-ITEM-MISMATCH"',
     'evidence identity accepts a title that differs only in letter case'),
    ('VM03-tracker-min-becomes-max', P + 'restore_created_at.go',
     'SELECT MIN(created_at) FROM item_history WHERE created_at GLOB',
     'SELECT MAX(created_at) FROM item_history WHERE created_at GLOB',
     'the tracker bound uses the latest history row'),
    ('VM04-tracker-bound-from-evidence-db', P + 'restore_created_at.go',
     'if err := db.QueryRow(`SELECT MIN(created_at) FROM item_history WHERE created_at GLOB',
     'if err := edb.QueryRow(`SELECT MIN(created_at) FROM item_history WHERE created_at GLOB',
     'the tracker bound is read from the (caller-supplied) evidence database'),
    ('VM05-hook-before-dry-run', P + 'restore_created_at.go',
     '\tif *dryRun {\n\t\tfmt.Printf("restore-created-at: dry-run:',
     '\tif rcaBeforeWriteHook != nil {\n\t\trcaBeforeWriteHook()\n\t}\n\tif *dryRun {\n\t\tfmt.Printf("restore-created-at: dry-run:',
     'the test seam is reached by a dry run too'),
    ('VM06-lower-bound-only-for-items-row-attest', P + 'restore_created_at.go',
     'if newT.Before(trackerT.Add(-rcaTrackerSlack)) {',
     'if attest == "items-row" && newT.Before(trackerT.Add(-rcaTrackerSlack)) {',
     'the lower bound is applied only when the items row attests (an Opened-row forgery bypasses it)'),
    ('VM07-audit-names-live-id-not-evidence-id', P + 'restore_created_at.go',
     'target.created, *value, target.loc, target.rep, gotSHA, attest, evID, strings.TrimSpace(*reason))',
     'target.created, *value, target.loc, target.rep, gotSHA, attest, *id, strings.TrimSpace(*reason))',
     'the audit row names the live id instead of the evidence id (re-minted items)'),
    ('VE01-fallback-latest-not-earliest', P + 'db.go',
     'if best == nil || v < *best {',
     'if best == nil || v > *best {',
     "the lookup fallback carries the LATEST value of the item's other rows instead of the earliest"),
    ('VE02-fixed-transaction-nil-prior', P + 'sync.go',
     'replaceDocumentWithSnapshot(db, "Fixed", items, segs, snap)',
     'replaceDocumentWithSnapshot(db, "Fixed", items, segs, nil)',
     "md-to-db's Fixed transaction gets no outer snapshot"),
    ('VE03-close-scan-error-ignored', P + 'crud.go',
     "\tif err := tx.QueryRow(`SELECT created_at FROM items WHERE atm_id=? AND current_location='Issues' AND representation=?`, id, src.repOrDefault()).Scan(&createdAt); err != nil {",
     "\tif err := tx.QueryRow(`SELECT created_at FROM items WHERE atm_id=? AND current_location='Issues' AND representation=?`, id, src.repOrDefault()).Scan(&createdAt); err != nil && false {",
     'close continues with an empty created_at when the read fails'),
    ('VS01-root-logical-not-physical', APPLIER,
     'ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) ||',
     'ROOT=$(cd "$ROOT" 2>/dev/null && pwd) ||',
     '--root kept as the logical path (a root reached through a symlink then fails the realdir check: false BLIND)'),
    ('VS02-mkdir-before-walk', APPLIER,
     '  p=$ROOT\n  IFS=/ read -r -a parts',
     '  mkdir -p "$(dirname "$dest")" || exit 3\n  p=$ROOT\n  IFS=/ read -r -a parts',
     'directories are created (possibly through a symlink, outside --root) before the symlink walk refuses'),
    ('VS03-walk-checks-only-last-two', APPLIER,
     '    if [ -L "$p" ]; then echo',
     '    if [ -L "$p" ] && [ "$(dirname "$(dirname "$p")")" = "$ROOT" -o "$(dirname "$p")" = "$ROOT" -o "$c" = "${parts[-1]}" ]; then echo',
     'the walk only checks the first-level component and the file (a deeper symlinked directory passes the walk)'),
]


REVIEWER_R3_MUTANTS = [
    # copied verbatim (old/new/intent) from the round-3 review's probes/rev3_mutants.py; only the path is
    # rewritten from repository-relative to this runner's form (module-relative for Go, repository-relative for sh)
    ('R3G01-first-history-by-id-not-min', P + 'restore_created_at.go',
     'if n == 0 || ht.Before(first) {',
     'if n == 0 {',
     'the first-event bound takes the lowest-id history row instead of the earliest time'),
    ('R3G02-identity-checks-first-evidence-row-only', P + 'restore_created_at.go',
     'for _, r := range evRows {\n\t\tif r.typ != target.typ',
     'for _, r := range evRows[:1] {\n\t\tif r.typ != target.typ',
     'a second evidence row (Issues + Fixed) of another type or title is not checked'),
    ('R3G03-opened-attests-any-earlier', P + 'restore_created_at.go',
     'if attest == "" && s == *value {',
     'if attest == "" && s <= *value {',
     'any Opened row at or before the value attests it'),
    ('R3G06-wal-threshold-8', P + 'restore_created_at.go',
     'si.Size() > 0',
     'si.Size() > 8',
     'a -wal or -journal sidecar of 1 to 8 bytes is ignored'),
    ('R3G08-required-flag-whitespace-only', P + 'restore_created_at.go',
     'if strings.TrimSpace(req.v) == "" {',
     'if req.v == "" {',
     "a white-space-only required flag (for example --reason ' ') is accepted"),
    ('R3G09-representation-filter-without-coalesce', P + 'restore_created_at.go',
     "q += ` AND COALESCE(representation,'section')=?`",
     'q += ` AND representation=?`',
     '--representation section does not find a row whose representation is NULL'),
    ('R3G10-reason-cr-allowed', P + 'restore_created_at.go',
     'strings.ContainsAny(*reason, "\\r\\n")',
     'strings.ContainsAny(*reason, "\\n")',
     'a reason with a carriage return passes the one-line check'),
    ('R3G11-by-case-insensitive', P + 'restore_created_at.go',
     'if *by != "AI" && *by != "User" {',
     'if !strings.EqualFold(*by, "AI") && !strings.EqualFold(*by, "User") {',
     '--by ai or user is accepted'),
    ('R3S01-walk-stops-at-empty-component', APPLIER,
     '[ -n "$c" ] || continue',
     '[ -n "$c" ] || break',
     'a path with an empty component (a//b) is walked only up to it'),
    ('R3S02-engine-exists-not-executable', APPLIER,
     '[ -x "$ENGINE" ] ||',
     '[ -e "$ENGINE" ] ||',
     'a non-executable engine is not reported BLIND by the applier'),
    ('R3S03-no-id-dash-accepted', APPLIER,
     '[ -n "$id" ] && [ "$id" != "-" ] ||',
     '[ -n "$id" ] ||',
     "a '-' id for the landing is passed to the engine"),
    ('R3S05-cp-leaves-temp-file', APPLIER,
     'mv -- "$tmp" "$dest" || exit 3',
     'cp -- "$tmp" "$dest" || exit 3',
     'the temporary extraction file is left in the evidence directory'),
    ('R3S06-header-row-not-skipped', APPLIER,
     "''|'#'*|vehicle_id) continue",
     "''|'#'*) continue",
     'the column header row is applied as a data row'),
]

OWN_R4_MUTANTS = [
    # ---- round 4 (review R3-F1): the comparison class of the attestation and validation paths. Every
    # comparison operator the census of created_at_r4_test.go lists for the value ordering, each replaced by
    # its siblings. EQUIVALENT ones are named with their argument.
    ("MV01-items-attest-le", R, 'if attest == "" && r.created == *value {', 'if attest == "" && r.created <= *value {',
     "an items row at or before the value attests it"),
    ("MV02-items-attest-lt", R, 'if attest == "" && r.created == *value {', 'if attest == "" && r.created < *value {',
     "an items row before the value attests it"),
    ("MV03-items-attest-ge", R, 'if attest == "" && r.created == *value {', 'if attest == "" && r.created >= *value {',
     "an items row at or after the value attests it"),
    ("MV04-items-attest-gt", R, 'if attest == "" && r.created == *value {', 'if attest == "" && r.created > *value {',
     "an items row after the value attests it"),
    ("MV05-items-attest-ne", R, 'if attest == "" && r.created == *value {', 'if attest == "" && r.created != *value {',
     "an items row that differs from the value attests it"),
    ("MV06-opened-attest-lt", R, 'if attest == "" && s == *value {', 'if attest == "" && s < *value {',
     "an Opened row before the value attests it"),
    ("MV07-opened-attest-ge", R, 'if attest == "" && s == *value {', 'if attest == "" && s >= *value {',
     "an Opened row at or after the value attests it"),
    ("MV08-opened-attest-gt", R, 'if attest == "" && s == *value {', 'if attest == "" && s > *value {',
     "an Opened row after the value attests it"),
    ("MV09-opened-attest-ne", R, 'if attest == "" && s == *value {', 'if attest == "" && s != *value {',
     "an Opened row that differs from the value attests it"),
    ("MV10-first-event-not-before", R, "if newT.After(first) {", "if !newT.Before(first) {",
     "a value equal to the first history row is refused"),
    ("MV11-first-event-minus-1s", R, "if newT.After(first) {", "if newT.After(first.Add(-time.Second)) {",
     "the first-event bound moves one second earlier"),
    ("MV12-earliest-row-not-after", R, "if n == 0 || ht.Before(first) {", "if n == 0 || !ht.After(first) {",
     "a history row equal to the current first replaces it"),
    ("MV13-tracker-not-after", R, "if newT.Before(trackerT.Add(-rcaTrackerSlack)) {",
     "if !newT.After(trackerT.Add(-rcaTrackerSlack)) {", "a value equal to the tracker bound is refused"),
    ("MV14-tracker-minus-1s", R, "trackerT.Add(-rcaTrackerSlack)", "trackerT.Add(-rcaTrackerSlack - time.Second)",
     "the tracker bound moves one second earlier"),
    ("MV15-already-le", R, "if target.created == *value {", "if target.created <= *value {",
     "a value later than the current one is answered 'already'"),
    ("MV16-already-ge", R, "if target.created == *value {", "if target.created >= *value {",
     "a value earlier than the current one is answered 'already' (nothing written)"),
    ("MV17-current-not-before", R, "if newT.After(curT) {", "if !newT.Before(curT) {",
     "a value equal to the current one is refused as later"),
    ("MV18-sidecar-gt-1", R, "si.Size() > 0", "si.Size() > 1", "a 1-byte -wal or -journal is ignored"),
    ("MV19-sidecar-ge-1", R, "si.Size() > 0", "si.Size() >= 1", "the sidecar check written as >= 1"),
    # ---- round 4 (review R3-F2): the path-shape class of the applier
    ("MW01-shape-check-removed", APPLIER, "case \"$evfile\" in ''|.|*/|*/.)", "case \"$evfile\" in '#never')",
     "an evidence_file that does not end in a file name is not refused"),
    ("MW02-shape-check-no-trailing-slash", APPLIER, "case \"$evfile\" in ''|.|*/|*/.)", "case \"$evfile\" in ''|.|*/.)",
     "an evidence_file ending in / is not refused"),
    ("MW03-shape-check-no-slash-dot", APPLIER, "case \"$evfile\" in ''|.|*/|*/.)", "case \"$evfile\" in ''|.|*/)",
     "an evidence_file ending in /. is not refused"),
    ("MW04-shape-check-no-dot", APPLIER, "case \"$evfile\" in ''|.|*/|*/.)", "case \"$evfile\" in ''|*/|*/.)",
     "an evidence_file . is not refused"),
    ("MW05-shape-check-no-empty", APPLIER, "case \"$evfile\" in ''|.|*/|*/.)", "case \"$evfile\" in .|*/|*/.)",
     "an empty evidence_file is not refused by the shape check"),
    ("MW06-nonregular-dest-check-removed", APPLIER, 'if [ -e "$dest" ] && [ ! -f "$dest" ]; then',
     'if false && [ -e "$dest" ] && [ ! -f "$dest" ]; then', "an existing directory or FIFO at the evidence path is written into or replaced"),
    ("MW07-nonregular-dest-only-dirs", APPLIER, 'if [ -e "$dest" ] && [ ! -f "$dest" ]; then',
     'if [ -d "$dest" ]; then', "only a directory at the evidence path is refused (a FIFO is replaced)"),
    ("MW08-walk-ignores-dangling-links", APPLIER, '    if [ -L "$p" ]; then echo', '    if [ -L "$p" ] && [ -e "$p" ]; then echo',
     "a dangling symbolic link in the evidence path passes the walk"),
]

OWN_MUTANTS = [
    # ---- restore-created-at: the round-2 plausibility lower bound (F3)
    ("MR01-tracker-bound-removed", R, "if newT.Before(trackerT.Add(-rcaTrackerSlack)) {",
     "if false && newT.Before(trackerT.Add(-rcaTrackerSlack)) {", "VALUE-BEFORE-TRACKER never refuses"),
    ("MR02-tracker-slack-sign", R, "trackerT.Add(-rcaTrackerSlack)", "trackerT.Add(rcaTrackerSlack)",
     "the slack moves the bound later instead of earlier"),
    ("MR03-tracker-slack-zero", R, "const rcaTrackerSlack = 60 * time.Second", "const rcaTrackerSlack = 0 * time.Second",
     "no slack: a value 1 s before the tracker's first row is refused"),
    ("MR04-tracker-slack-61", R, "const rcaTrackerSlack = 60 * time.Second", "const rcaTrackerSlack = 61 * time.Second",
     "the slack grows by one second"),
    ("MR05-tracker-glob-removed", R,
     " WHERE created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]'`",
     "`", "a malformed history row becomes the tracker minimum"),
    ("MR06-tracker-bound-uses-item-first", R, "newT.Before(trackerT.Add(-rcaTrackerSlack))",
     "newT.Before(first.Add(-rcaTrackerSlack)) && !trackerT.IsZero()", "the lower bound is the item's own first row, not the tracker's"),
    ("MR07-tracker-unreadable-ignored", R,
     "\ttrackerT, ok := parseStoredTime(trackerFirst.String)\n\tif !ok {",
     "\ttrackerT, ok := parseStoredTime(trackerFirst.String)\n\tif !ok && false {",
     "an unreadable tracker minimum is not refused (zero time: every value passes)"),
    # ---- compare-and-set write
    ("MR08-cas-accepts-zero-rows", R, "err != nil || n != 1 {", "err != nil || n > 1 {",
     "a CAS that matched no row is reported as written"),
    ("MR09-cas-ignores-location", R, "WHERE atm_id=? AND current_location=? AND COALESCE",
     "WHERE atm_id=? AND (current_location=? OR 1) AND COALESCE", "the UPDATE also hits the id's other location"),
    ("MR10-cas-ignores-representation", R, "AND COALESCE(representation,'section')=? AND created_at=?`",
     "AND (COALESCE(representation,'section')=? OR 1) AND created_at=?`", "the UPDATE also hits the other representation"),
    ("MR11-commit-becomes-rollback", R, "if err := tx.Commit(); err != nil {", "if err := tx.Rollback(); err != nil {",
     "the write is rolled back and success is reported"),
    ("MR12-audit-row-skipped", R, 'if err := recordHistory(tx, *id, "Updated", *by, audit, evRaw); err != nil {',
     'if err := error(nil); err != nil && audit != "" {', "no audit history row"),
    ("MR13-audit-evidence-absolute", R, 'recordHistory(tx, *id, "Updated", *by, audit, evRaw)',
     'recordHistory(tx, *id, "Updated", *by, audit, evAbs)', "the audit row records the host-absolute evidence path"),
    ("MR14-audit-by-fixed", R, 'recordHistory(tx, *id, "Updated", *by, audit, evRaw)',
     'recordHistory(tx, *id, "Updated", "AI", audit, evRaw)', "--by is not recorded"),
    ("MR15-dry-run-writes", R, "\tif *dryRun {\n\t\tfmt.Printf(\"restore-created-at: dry-run:",
     "\tif *dryRun && false {\n\t\tfmt.Printf(\"restore-created-at: dry-run:", "--dry-run writes"),
    ("MR16-already-writes", R, "if target.created == *value {", "if target.created == *value && false {",
     "an equal value is written again with a new audit row"),
    # ---- evidence provenance (sha, file identity, sidecars, path)
    ("MR17-sha-mismatch-ignored", R, "if gotSHA != *evidenceSHA {", "if false {",
     "the evidence file's sha256 is not compared"),
    ("MR18-samefile-by-path", R, "if os.SameFile(evInfo, liveInfo) {", "if evAbs == liveAbs {",
     "a hard link or symlink to the live DB passes as evidence"),
    ("MR19-empty-sidecar-refused", R, "err == nil && si.Size() > 0 {", "err == nil && si.Size() >= 0 {",
     "an empty -wal/-journal is refused (false positive)"),
    ("MR20-evidence-path-unchecked", R, "if err := checkEvidencePath(evRaw); err != nil {",
     "if err := error(nil); err != nil {", "absolute / .. / out-of-repo evidence paths pass"),
    ("MR21-identity-and", R, "if r.typ != target.typ || r.title != target.title {\n\t\t\treturn rcaRefuse(\"EVIDENCE-ITEM-MISMATCH\"",
     "if r.typ != target.typ && r.title != target.title {\n\t\t\treturn rcaRefuse(\"EVIDENCE-ITEM-MISMATCH\"",
     "only an item differing in BOTH type and title is refused"),
    ("MR22-attest-same-day", R, "if attest == \"\" && r.created == *value {",
     "if attest == \"\" && r.created[:10] == (*value)[:10] {", "an items row of the same day attests any time"),
    ("MR23-evidence-item-missing-ignored", R, "\tif len(evRows) == 0 {\n", "\tif len(evRows) < 0 {\n",
     "an evidence DB without the item passes (attestation by an Opened row of a deleted item)"),
    # ---- upper bounds and history
    ("MR24-first-event-direction", R, "if newT.After(first) {", "if newT.Before(first) {",
     "the first-event bound is inverted"),
    ("MR25-first-is-latest", R, "if n == 0 || ht.Before(first) {", "if n == 0 || ht.After(first) {",
     "the item's LATEST history row is taken as its first"),
    ("MR26-history-of-all-items", R, "SELECT created_at FROM item_history WHERE atm_id=? ORDER BY id`, *id)",
     "SELECT created_at FROM item_history WHERE atm_id=? OR 1 ORDER BY id`, *id)",
     "every item's history bounds this item"),
    ("MR27-no-history-accepted", R, "\tif n == 0 {\n\t\treturn rcaRefuse(\"NO-HISTORY\"",
     "\tif n < 0 {\n\t\treturn rcaRefuse(\"NO-HISTORY\"", "an item with no history is restored (zero first time)"),
    # ---- target selection and usage
    ("MR28-ambiguous-takes-first", R, "\tdefault:\n\t\tvar where []string", "\tcase -1:\n\t\tvar where []string",
     "an id with several rows silently restores the first"),
    ("MR29-location-filter-dropped", R, "q += ` AND current_location=?`", "q += ` AND (current_location=? OR 1)`",
     "--location does not narrow"),
    ("MR30-by-unchecked", R, 'if *by != "AI" && *by != "User" {', "if false {", "--by accepts anything"),
    ("MR31-positional-allowed", R, "if fs.NArg() > 0 {", "if fs.NArg() > 1 {", "one stray positional argument is ignored"),
    ("MR32-refusal-exit-ok", R, "\treturn exitUsage\n}\n\nfunc fileSHA256", "\treturn exitOK\n}\n\nfunc fileSHA256",
     "every refusal exits 0"),
    # ---- close (CON-339 root cause)
    ("MR33-close-reads-fixed", P + "crud.go", "current_location='Issues' AND representation=?`, id, src.repOrDefault()).Scan(&createdAt)",
     "current_location='Fixed' AND representation=?`, id, src.repOrDefault()).Scan(&createdAt)",
     "close reads created_at from a row that does not exist yet (nil: datetime('now'))"),
    # ---- the plan applier (shell)
    ("MS01-final-row-dropped", APPLIER, ' reason || [ -n "$vid" ]; do', " reason; do",
     "a last plan row without a trailing newline is dropped (F2)"),
    ("MS02-symlink-walk-removed", APPLIER, '    if [ -L "$p" ]; then echo', '    if false; then echo',
     "a symlinked evidence component is not refused by the walk (F7)"),
    ("MS03-realdir-check-weakened", APPLIER, 'case "$real_dir/" in "$ROOT"/*) ;;', 'case "$real_dir/" in /*) ;;',
     "the resolved evidence directory may lie outside --root (F7)"),
    ("MS04-dotdot-allowed", APPLIER, "case \"$evfile\" in /*|*..*)", "case \"$evfile\" in /*)",
     "an evidence path with .. is accepted"),
    ("MS05-sha-unchecked", APPLIER, 'if [ "$got" != "$sha" ]; then', "if false; then",
     "the extracted evidence file's sha256 is not compared with the plan"),
    ("MS06-apply-by-default", APPLIER, '[ "$APPLY" = 1 ] || args+=(--dry-run)', "true || args+=(--dry-run)",
     "the applier writes without --apply"),
    ("MS07-refusal-not-counted", APPLIER, '[ "$rc" = 0 ] || refused=$((refused + 1))', "true",
     "an engine refusal is not counted"),
    ("MS08-landing-columns-swapped", APPLIER, "main) IDCOL=2 ;;", "main) IDCOL=3 ;;",
     "--landing main reads the fix227 id column"),
    ("MS09-empty-plan-ok", APPLIER, '[ "$rows" -gt 0 ] ||', '[ "$rows" -ge 0 ] ||',
     "a plan with no rows is a success"),
    ("MS10-refused-exit-0", APPLIER, '[ "$refused" = 0 ] || exit 1', '[ "$refused" = 0 ] || exit 0',
     "a run with refused rows exits 0"),
    ("MS11-git-show-failure-ignored", APPLIER,
     '      rm -f -- "${tmp:?}"; echo "BLIND: git show $commit:$gitpath failed in $REPO" >&2; exit 3',
     '      rm -f -- "${tmp:?}"; echo "BLIND: git show $commit:$gitpath failed in $REPO" >&2',
     "a failed git show continues with an empty evidence file"),
    # ---- round 3 (review R2-F1): own mutants of the classes the round-2 reviewer named
    ("MT01-type-case-insensitive", R, "if r.typ != target.typ || r.title", "if !strings.EqualFold(r.typ, target.typ) || r.title",
     "evidence identity accepts a type that differs only in letter case"),
    ("MT02-type-trimmed", R, "if r.typ != target.typ || r.title",
     "if strings.TrimSpace(r.typ) != strings.TrimSpace(target.typ) || r.title",
     "evidence identity accepts a type with leading or trailing white space"),
    ("MT03-title-trimmed", R, "|| r.title != target.title {",
     "|| strings.TrimSpace(r.title) != strings.TrimSpace(target.title) {",
     "evidence identity accepts a title with leading or trailing white space"),
    ("MT04-live-id-nocase", R, "\t\tFROM items WHERE atm_id=?`\n\tqa :=", "\t\tFROM items WHERE atm_id=? COLLATE NOCASE`\n\tqa :=",
     "the live item is found by an id that differs only in letter case"),
    ("MT05-evidence-id-nocase", R, "FROM items WHERE atm_id=?`, evID)", "FROM items WHERE atm_id=? COLLATE NOCASE`, evID)",
     "the evidence item is found by an id that differs only in letter case"),
    ("MT06-live-id-trimmed", R, "qa := []any{*id}", "qa := []any{strings.TrimSpace(*id)}",
     "the live item is found by an id with leading or trailing white space"),
    ("MT07-attest-real-run-only", R, "if attest == \"\" {\n\t\tsort.Strings(recorded)",
     "if attest == \"\" && !*dryRun {\n\t\tsort.Strings(recorded)",
     "EVIDENCE-DOES-NOT-ATTEST only in a real run"),
    ("MT08-first-event-real-run-only", R, "if newT.After(first) {", "if newT.After(first) && !*dryRun {",
     "VALUE-AFTER-FIRST-EVENT only in a real run"),
    ("MT09-wal-real-run-only", R, "err == nil && si.Size() > 0 {", "err == nil && si.Size() > 0 && !*dryRun {",
     "EVIDENCE-WAL only in a real run"),
    ("MT10-sha-real-run-only", R, "if gotSHA != *evidenceSHA {", "if gotSHA != *evidenceSHA && !*dryRun {",
     "EVIDENCE-SHA256 only in a real run"),
    ("MT11-close-read-error-exit-ok", P + "crud.go",
     "\t\tfmt.Fprintf(os.Stderr, \"close: read created_at of %s: %v\\n\", id, err)\n\t\treturn exitUsage",
     "\t\tfmt.Fprintf(os.Stderr, \"close: read created_at of %s: %v\\n\", id, err)\n\t\treturn exitOK",
     "close reports success when the created_at read fails"),
    ("MU01-walk-skips-file", APPLIER, 'for c in "${parts[@]}"; do', 'for c in "${parts[@]:0:${#parts[@]}-1}"; do',
     "the walk does not look at the file component"),
    ("MU02-walk-skips-first", APPLIER, 'for c in "${parts[@]}"; do', 'for c in "${parts[@]:1}"; do',
     "the walk does not look at the first component"),
    ("MU03-realdir-logical", APPLIER, 'real_dir=$(cd "$(dirname "$dest")" && pwd -P)', 'real_dir=$(cd "$(dirname "$dest")" && pwd)',
     "the evidence directory is checked by its logical path (a racing link passes)"),
    ("MU04-root-unresolved", APPLIER, 'ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) ||', 'ROOT=$(cd "$ROOT" 2>/dev/null && echo "$ROOT") ||',
     "--root is used as given (relative or through a link)"),
    ("MU05-prefix-without-slash", APPLIER, 'case "$real_dir/" in "$ROOT"/*) ;;', 'case "$real_dir" in "$ROOT"*) ;;',
     "a sibling directory whose path starts with --root passes the check"),
]

MUTANTS = REVIEWER_MUTANTS + REVIEWER_R2_MUTANTS + REVIEWER_R3_MUTANTS + OWN_MUTANTS + OWN_R4_MUTANTS
RUN_TARGETED = "^(TestCON339|TestRestoreCreatedAt)"
SH_TEST = "docs/qa/engine_created_at_2026_11_13/round2/test_apply_restore_plan.sh"


def sha(b):
    return hashlib.sha256(b).hexdigest()


def arg(name, default=None):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


def main():
    if "--list" in sys.argv:
        for m in MUTANTS:
            print(m[0], "EQUIVALENT" if m[0] in EQUIVALENT else "", sep="\t")
        print("total", len(MUTANTS), "reviewer", len(REVIEWER_MUTANTS) + len(REVIEWER_R2_MUTANTS) + len(REVIEWER_R3_MUTANTS),
              "own", len(OWN_MUTANTS) + len(OWN_R4_MUTANTS))
        return 0
    wt, gobin = arg("--worktree"), arg("--go", "go")
    if not wt:
        repo = subprocess.run(["git", "-C", os.path.dirname(os.path.abspath(__file__)), "rev-parse", "--show-toplevel"],
                              capture_output=True, text=True)
        if repo.returncode != 0:
            print("BLIND: not in a git checkout", file=sys.stderr)
            return 3
        top = repo.stdout.strip()
        parent = tempfile.mkdtemp(prefix="ca_r2_wt_")
        wt = os.path.join(parent, "wt")
        add = subprocess.run(["git", "-C", top, "worktree", "add", "--detach", wt, "HEAD"], capture_output=True, text=True)
        if add.returncode != 0:
            os.rmdir(parent)
            print("BLIND: git worktree add failed: " + add.stderr, file=sys.stderr)
            return 3
        argv = sys.argv[:]
        argv += ["--worktree", wt]
        try:
            return subprocess.run([sys.executable] + argv).returncode
        finally:
            subprocess.run(["git", "-C", top, "worktree", "remove", "--force", wt], capture_output=True)
            if os.path.isdir(parent) and not os.listdir(parent):
                os.rmdir(parent)
    mode = arg("--mode", "targeted")
    if mode not in ("targeted", "full"):
        print("--mode must be targeted or full", file=sys.stderr)
        return 64
    only = set(arg("--only").split(",")) if arg("--only") else None
    shard = arg("--shard")
    wt = os.path.abspath(wt)
    mod = os.path.join(wt, "scripts", "workable-items")
    if not os.path.isfile(os.path.join(mod, R)):
        print("BLIND: %s is not a worktree of the engine" % wt, file=sys.stderr)
        return 3
    sel = [m for m in MUTANTS if only is None or m[0] in only]
    if shard:
        i, n = (int(x) for x in shard.split("/"))
        sel = [m for k, m in enumerate(sel) if k % n == i]
    names = {m[0] for m in sel}
    if only and names != only:
        print("BLIND: unknown mutant names: %s" % sorted(only - names), file=sys.stderr)
        return 3

    def gotest():
        a = [gobin, "test", "-count=1"]
        if mode == "targeted":
            a += ["-run", RUN_TARGETED]
        a += ["./cmd/workable-items/"]
        p = subprocess.run(a, cwd=mod, capture_output=True, text=True)
        return p.returncode, p.stdout + p.stderr

    tmpd = tempfile.mkdtemp(prefix="ca_r2_mut_")
    engine = os.path.join(tmpd, "wi_engine")

    def shtest():
        env = dict(os.environ, APPLY_TEST_ENGINE=engine, APPLY_RESTORE_PLAN_SH=os.path.join(wt, APPLIER))
        p = subprocess.run(["bash", os.path.join(wt, SH_TEST)], cwd=wt, env=env, capture_output=True, text=True)
        return p.returncode, p.stdout + p.stderr

    need_go = any(not m[1].endswith(".sh") for m in sel)
    need_sh = any(m[1].endswith(".sh") for m in sel)
    if need_go:
        rc, out = gotest()
        print("CONTROL go (%s)" % mode, "PASS" if rc == 0 else "FAIL", flush=True)
        if rc != 0:
            print("\n".join(l for l in out.splitlines() if "FAIL" in l)[:3000])
            return 3
    if need_sh:
        b = subprocess.run([gobin, "build", "-o", engine, "./cmd/workable-items/"], cwd=mod, capture_output=True, text=True)
        if b.returncode != 0:
            print("BLIND: engine build failed\n" + b.stderr[-2000:])
            return 3
        rc, out = shtest()
        print("CONTROL sh", "PASS" if rc == 0 else "FAIL", flush=True)
        if rc != 0:
            print(out[-3000:])
            return 3
    res = {}
    for name, rel, old, new, intent in sel:
        f = os.path.join(wt, rel) if rel.endswith(".sh") else os.path.join(mod, rel)
        orig = open(f, "rb").read()
        text = orig.decode()
        if text.count(old) != 1:
            print("STALE %s (anchor count %d)" % (name, text.count(old)), flush=True)
            res[name] = "STALE"
            continue
        open(f, "w").write(text.replace(old, new))
        try:
            rc, out = shtest() if rel.endswith(".sh") else gotest()
        finally:
            open(f, "wb").write(orig)
        if sha(open(f, "rb").read()) != sha(orig):
            print("RESTORE FAILED for", f, flush=True)
            return 4
        if rel.endswith(".sh"):
            fails = sorted(set(l.split()[1] for l in out.splitlines() if l.startswith("FAIL ")))
        else:
            fails = sorted(set(l.strip().split()[2] for l in out.splitlines() if l.strip().startswith("--- FAIL")))
        # round 4: the comparison census reads the source text, so it fails on ANY change to a comparison it
        # lists, whether or not the behaviour changed. A mutant failed by the census alone is not killed by a
        # behaviour test: it is reported CENSUS-ONLY and counted like a survivor (it must be EQUIVALENT).
        behav = [f for f in fails if f.split("/")[0] not in CENSUS_TESTS]
        if rc == 0:
            v = "SURVIVED"
        elif "[build failed]" in out or "[setup failed]" in out:
            v = "BUILD-BROKEN"
        elif fails and not behav:
            v = "CENSUS-ONLY"
        else:
            v = "KILLED"
        eq = " [EQUIVALENT: %s]" % EQUIVALENT[name] if name in EQUIVALENT else ""
        print("%s %s (%s)%s%s" % (v, name, intent, (" by " + ",".join(fails[:8])) if fails else "", eq), flush=True)
        if v == "BUILD-BROKEN":
            print(out[-1500:])
        res[name] = v
    os.remove(engine) if os.path.exists(engine) else None
    os.rmdir(tmpd)
    st = subprocess.run(["git", "-C", wt, "status", "--porcelain", "--untracked-files=no"],
                        capture_output=True, text=True).stdout
    print("WORKTREE CLEAN AFTER RUN:", st.strip() == "", flush=True)
    unexplained = [k for k, v in res.items() if v in ("SURVIVED", "CENSUS-ONLY") and k not in EQUIVALENT]
    print("TALLY", {k: list(res.values()).count(k) for k in sorted(set(res.values()))},
          "unexplained survivors:", unexplained, flush=True)
    return 0 if not unexplained and st.strip() == "" and "STALE" not in res.values() \
        and "BUILD-BROKEN" not in res.values() else 1


if __name__ == "__main__":
    sys.exit(main())
