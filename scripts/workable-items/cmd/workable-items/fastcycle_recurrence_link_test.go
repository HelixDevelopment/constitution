// fastcycle_recurrence_link_test.go — T089 RED test (SpecKit-004
// "fast-dev-cycles", Phase 5 / User Story 3; plan.md T-D04; contract
// closure-refusal.md RL-001..RL-004; data-model.md §6.5 RecurrenceLink;
// DEC-39; SOL-07 intake-dedup-writer; §11.4.214; §11.4.34; FR-012, SC-004).
//
// Task line (tasks.md T089, verbatim): "[P] [US3] [TDD] RED Go test
// `constitution/scripts/workable-items/cmd/workable-items/
// fastcycle_recurrence_link_test.go` (a recurrence mints a new id today;
// golden: the recurrence reopens the original with §11.4.34 attribution,
// increments its reopen count, mints no id; golden-bad: an unrelated
// similar report is not merged — candidate link only) (plan T-D04; FR-012,
// SC-004)".
//
// THE GAP, PROVEN LIVE (TestRecurrenceLink_SimilarReportMintsNewIDToday):
// today this package has NO dedup/recurrence-detection mechanism anywhere.
// The only intake path that exists is the real `add` subcommand, and it
// mints unconditionally — a brand-new report describing the EXACT SAME
// defect as an already-closed item gets its own, entirely unlinked id, and
// no record anywhere in the tracker connects the two. This is precisely
// SOL-07's measured problem (docs/research/quality/solutions/
// SOL-07_intake_dedup_writer.md: "15 first-touch tickets ≈ 9 root causes;
// 4 high-confidence recurrences of 'done' items entered as NEW ids") and
// exactly what DEC-39/T-D04's intake-dedup matcher exists to close.
//
// COMPILE-SAFETY (§11.4.28/§11.4.177 reuse discipline applied to package
// boundaries, §11.4.240 producer!=verifier — the SAME discipline
// fastcycle_sibling_search_test.go's own header already establishes for
// this package): the future `intake-match` subcommand (contracts/
// closure-refusal.md's "Invocations" section: "$WI intake-match --config
// <cfg> --report <report.json> --out <link.json> [--apply] # T-D04: SOL-07
// intake-dedup matcher through the single writer") does NOT exist yet —
// main.go's subcommand switch has no `intake-match` case, so its `default:`
// branch fires ("unknown subcommand: intake-match", exit exitUsage). This
// file therefore NEVER references a not-yet-existing Go SYMBOL at compile
// time for that seam — the golden and golden-bad bullets below build the
// REAL `workable-items` binary FRESH from the CURRENT source tree (reusing
// the package-shared sharedWorkableItemsBinary/runWorkableItemsBinary
// helpers fastcycle_sibling_search_test.go already defines — §11.4.227,
// never a second build-and-invoke mechanism) and invoke it as a real
// subprocess with the contract's own documented argv shape. Only the FIRST
// bullet (today mints new id) is proven in-process, against the REAL,
// EXISTING addCmd/closeCmd — no compile-safety concern there, since those
// symbols already exist in this package today.
//
// ASSUMED CLI/JSON CONTRACT for `intake-match` (UNCONFIRMED by
// contracts/closure-refusal.md's own text beyond the field LISTS in
// data-model.md §6.5 RecurrenceLink — no example report.json/link.json body
// is given anywhere; DEFINED here, binding-if-adopted on T098's
// implementer, following the house precedent
// fastcycle_sibling_search_test.go's own header already sets for
// closure-check's --attempt/--config/--out shape):
//
//	--config <cfg>   a YAML file with (at minimum) a top-level `db: <path>`
//	                 key naming the workable-items SQLite DB to match/mint
//	                 against (common-conventions.md: "the item DB path is
//	                 consumer DATA under config/fastcycle/... passed with
//	                 --config").
//	--report <p>     a JSON file describing the incoming report — DEFINED
//	                 here as {"title", "scope", "description", "intake_path"}
//	                 (title/scope/description reuse the EXACT vocabulary
//	                 constitution/scripts/reporting/report_item.sh's own
//	                 --title/--scope/--description CLI flags already use —
//	                 §11.4.227, never invented fresh; intake_path is the
//	                 data-model.md §6.5 closed set {reporting-directive,
//	                 gate-failure, manual-qa} verbatim).
//	--out <p>        the tool writes a JSON RecurrenceLink body here
//	                 (data-model.md §6.5 fields, verbatim): {"new_report_ref",
//	                 "intake_path", "original_item_id", "match_basis",
//	                 "verdict"} — verdict ∈ {SAME_DEFECT, DISTINCT, UNDECIDED}.
//	--apply          per RL-004: with no --apply, --out is a dry-run only;
//	                 with --apply, the seam performs the write through the
//	                 single writer (RL-002: SAME_DEFECT reopens the resolved
//	                 chain head with §11.4.34 attribution; RL-003: UNDECIDED
//	                 mints a new id with a candidate-duplicate link, DISTINCT
//	                 mints with no link) and re-reads it back to confirm.
//
// Exit codes (contracts/closure-refusal.md's own exit-codes table, verbatim):
// "intake-match: 0 decision written, 1 invalid report." A written decision
// covers EVERY verdict (SAME_DEFECT/DISTINCT/UNDECIDED alike) — only a
// malformed/unreadable report.json is the exit-1 case, so both the golden
// and golden-bad bullets below expect exitOK once the seam exists.
//
// GOLDEN-BAD FIXTURE DESIGN NOTE (the RL-003 DISTINCT-vs-UNDECIDED
// ambiguity, honestly disclosed rather than silently resolved): the task
// line's own wording — "an unrelated similar report is not merged —
// candidate link only" — names the UNDECIDED shape (RL-003: "mint a new id
// WITH a candidate-duplicate link to the head"), which is a genuinely
// unspecified SIMILARITY-THRESHOLD judgement call T098 (not this task) owns.
// Rather than guess that threshold (§11.4.6), the fixture below is built to
// be unambiguously DISTINCT under any reasonable implementation — same
// scope as the original (so scope alone cannot trivially force the verdict)
// but a description naming an entirely different root cause, mirroring
// SOL-07's own documented "false-merge counter-case that bounds the
// design" (SOL-07 doc §1: "one suspected same-defect pair was proven
// DISTINCT on close reading ... auto-merge would have silently deleted a
// real defect"). The three assertions this test makes — verdict !=
// SAME_DEFECT, the original's reopen-event count is untouched, and a new,
// DISTINCT id is minted rather than the report being silently dropped —
// hold identically whether the correct verdict resolves DISTINCT (RL-003:
// "mint, no link") or UNDECIDED (RL-003: "mint... with a candidate-duplicate
// link"); both are "not merged" per this task's own wording, and neither is
// asserted over the other.
//
// Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
// its fixtures. It does NOT implement the `intake-match` subcommand, the
// SOL-07 matcher wiring into main.go's dispatch, or any change to
// mutate.go/crud.go — every assertion below is a REAL invocation of either
// today's REAL add/close subcommands (in-process) or the freshly REAL-built
// `workable-items` binary's REAL subprocess exit code + REAL --out file
// content, never a fabricated result. T098 (a separate, later, SERIAL task)
// is the implementer this RED test exists to gate.
package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// ---------------------------------------------------------------------------
// Bullet 1 (today mints new id) -- proven entirely in-process against the
// REAL, EXISTING add/close subcommands. No subprocess, no compile-safety
// concern.
// ---------------------------------------------------------------------------

// seedRecurrenceOriginal creates a Bug item through the REAL add subcommand
// and closes it (Fixed) through the REAL close subcommand, so the "original"
// item in every scenario below starts life as a genuinely terminal, closed
// tracker row -- the state RL-002's "reopen the resolved chain head" acts on.
// The description embeds the SAME "**Affected scope / file-scope
// manifest:**\n<scope>" convention constitution/scripts/reporting/
// report_item.sh already writes into every intake description (line 329:
// "**Affected scope / file-scope manifest:**\n${SCOPE}") -- §11.4.227 reuse,
// never an invented second scope-encoding convention -- so a future matcher
// reading the item's EXISTING stored description can re-derive its scope by
// the identical convention this test's own report.json fixtures state
// independently.
func seedRecurrenceOriginal(t *testing.T, dbPath, id, title, symptom, scope string) {
	t.Helper()
	description := symptom + "\n\n**Affected scope / file-scope manifest:**\n" + scope
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", title,
		"--description", description,
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("seed: add %s exited %d, want %d", id, code, exitOK)
	}
	if code := closeCmd([]string{
		"--db", dbPath, "--status", "fixed", "--evidence", realEvidenceFile(t), id,
	}); code != exitOK {
		t.Fatalf("seed: close %s exited %d, want %d", id, code, exitOK)
	}
	status, loc := itemLocation(t, dbPath, id)
	if status != closeStatusMap["fixed"].status || loc != "Fixed" {
		t.Fatalf("seed: %s not terminal after close: status=%q location=%q", id, status, loc)
	}
}

// TestRecurrenceLink_SimilarReportMintsNewIDToday is the T-D04 RED baseline:
// today, a brand-new report describing the EXACT SAME already-closed defect
// is handled through the only intake mechanism this package has (the real
// `add` subcommand) -- which mints an entirely fresh, unlinked id every
// time, with ZERO dedup/recurrence-detection concept anywhere. This is
// exactly the DEC-39/SOL-07 gap T-D04/T098 exist to close.
func TestRecurrenceLink_SimilarReportMintsNewIDToday(t *testing.T) {
	dbPath := newTestDB(t)
	const originalID = "WIT-740"
	seedRecurrenceOriginal(t, dbPath, originalID,
		"audio output silently drops to mono after HDMI hot-unplug reconnect",
		"Reported symptom: after unplugging and replugging the HDMI cable, surround audio output silently reverts to mono and stays that way until the device reboots.",
		"hardware/rockchip/audio/tinyalsa_hal")

	if got := distinctItemCount(t, dbPath); got != 1 {
		t.Fatalf("seed sanity: distinct item count = %d, want 1 (only %s)", got, originalID)
	}
	if got := reopenEventCount(t, dbPath, originalID); got != 0 {
		t.Fatalf("seed sanity: %s already shows %d Reopened event(s) before any recurrence report was ever filed", originalID, got)
	}

	// The recurrence: a NEW report describing the SAME defect, filed with no
	// knowledge of originalID at all -- the realistic shape of a genuine
	// recurrence (an operator or an automated gate-failure intake does not
	// know a ticket already exists for this symptom). Today's only intake
	// path is `add`, which mints unconditionally.
	const recurrenceID = "WIT-741"
	if code := addCmd([]string{
		"--db", dbPath, "--id", recurrenceID,
		"--title", "HDMI reconnect again drops audio output to mono, no 5.1",
		"--description", "Same symptom as before: after unplugging and replugging the HDMI cable, surround audio output silently reverts to mono and stays that way until the device reboots.\n\n**Affected scope / file-scope manifest:**\nhardware/rockchip/audio/tinyalsa_hal",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("RED baseline broken: add %s exited %d, want %d (exitOK) -- "+
			"today's add subcommand should mint the recurrence unconditionally, "+
			"since T-D04's intake-dedup matcher has not landed yet", recurrenceID, code, exitOK)
	}

	if got := distinctItemCount(t, dbPath); got != 2 {
		t.Errorf("RED baseline broken: distinct item count = %d, want 2 -- "+
			"the SAME defect now has TWO entirely separate ids (%s, %s) and "+
			"today's add mechanism recorded no link, no reopen, no attribution "+
			"connecting them anywhere in the tracker: exactly the DEC-39/T-D04 "+
			"gap this RED test exists to gate", got, originalID, recurrenceID)
	}
	if got := reopenEventCount(t, dbPath, originalID); got != 0 {
		t.Errorf("%s shows %d Reopened event(s) after a plain `add` call -- "+
			"the seeding/assertion helpers themselves are broken (add alone must "+
			"never touch the original's history)", originalID, got)
	}
	if status, _ := itemLocation(t, dbPath, originalID); status != closeStatusMap["fixed"].status {
		t.Errorf("%s status = %q after the recurrence was minted as a separate id, "+
			"want it UNCHANGED at %q -- a plain `add` call must never mutate an "+
			"unrelated existing row", originalID, status, closeStatusMap["fixed"].status)
	}
}

// ---------------------------------------------------------------------------
// Bullets 2-3 -- the future `intake-match` seam. Exercised ONLY as an
// external subprocess of a binary built fresh from the CURRENT source tree,
// via the package-shared sharedWorkableItemsBinary/runWorkableItemsBinary
// helpers fastcycle_sibling_search_test.go already defines in this SAME
// package (§11.4.227 reuse -- never a second build-and-invoke mechanism).
// ---------------------------------------------------------------------------

// recurrenceReportFixture is this RED test's own DEFINED (UNCONFIRMED
// elsewhere) shape for intake-match's --report input -- see the file header.
type recurrenceReportFixture struct {
	Title       string `json:"title"`
	Scope       string `json:"scope"`
	Description string `json:"description"`
	IntakePath  string `json:"intake_path"`
}

// writeRecurrenceReportJSON marshals a recurrenceReportFixture to a fresh
// temp file and returns its path.
func writeRecurrenceReportJSON(t *testing.T, report recurrenceReportFixture) string {
	t.Helper()
	body, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		t.Fatalf("marshal recurrence report fixture: %v", err)
	}
	p := filepath.Join(t.TempDir(), "report.json")
	if err := os.WriteFile(p, body, 0o644); err != nil {
		t.Fatalf("write report.json: %v", err)
	}
	return p
}

// writeMinimalIntakeMatchConfig writes the UNCONFIRMED/DEFINED-here minimal
// --config YAML this RED test assumes intake-match needs (see file header):
// just enough to name the DB the --report is resolved against. Deliberately
// its OWN helper (not a reuse of fastcycle_sibling_search_test.go's
// writeMinimalClosureCheckConfig) -- intake-match and closure-check are
// distinct seams whose config needs may diverge (e.g. a future similarity
// threshold), even though their minimal content is identical today.
func writeMinimalIntakeMatchConfig(t *testing.T, dbPath string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "fastcycle.yaml")
	body := "db: " + dbPath + "\n"
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatalf("write minimal intake-match config: %v", err)
	}
	return p
}

// recurrenceLinkOf reads and JSON-decodes a --out RecurrenceLink file,
// returning ok=false when the file is absent or unparseable (both are
// honest, expected states TODAY, since intake-match does not exist yet and
// therefore never writes one) rather than failing the whole test on that
// alone -- mirrors fastcycle_sibling_search_test.go's own decisionOf.
func recurrenceLinkOf(t *testing.T, linkPath string) (verdict, originalItemID, matchBasis, newReportRef, intakePath string, ok bool) {
	t.Helper()
	body, err := os.ReadFile(linkPath)
	if err != nil {
		return "", "", "", "", "", false
	}
	var parsed map[string]interface{}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", "", "", "", "", false
	}
	v, _ := parsed["verdict"].(string)
	orig, _ := parsed["original_item_id"].(string)
	mb, _ := parsed["match_basis"].(string)
	nrr, _ := parsed["new_report_ref"].(string)
	ip, _ := parsed["intake_path"].(string)
	return v, orig, mb, nrr, ip, v != ""
}

// distinctItemCount returns COUNT(DISTINCT atm_id) across the whole items
// table (both Issues and Fixed locations) -- the "how many separate ids
// exist" signal a mint-vs-no-mint assertion needs, robust to a
// dual-representation item (a single atm_id spanning >1 representation row,
// the mutate.go-documented HXC-044 shape) never being double-counted.
func distinctItemCount(t *testing.T, dbPath string) int {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var n int
	row := db.QueryRow(`SELECT COUNT(DISTINCT atm_id) FROM items`)
	if err := row.Scan(&n); err != nil {
		t.Fatalf("count distinct items: %v", err)
	}
	return n
}

// reopenEventCount returns the number of item_history rows recorded for id
// with event_type='Reopened' -- the §11.4.55 reopens_count signal (derived,
// never a stored column in this schema) RL-002's "increment reopen_count"
// language refers to.
func reopenEventCount(t *testing.T, dbPath, id string) int {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var n int
	row := db.QueryRow(`SELECT COUNT(*) FROM item_history WHERE atm_id=? AND event_type='Reopened'`, id)
	if err := row.Scan(&n); err != nil {
		t.Fatalf("count Reopened events for %s: %v", id, err)
	}
	return n
}

// latestReopenAttribution returns the §11.4.34 By/On/Reason/Evidence
// attribution fields of the MOST RECENT Reopened item_history row for id, or
// found=false when no such row exists. COALESCE avoids needing
// database/sql's sql.NullString import in this file (the schema permits `by`
// and `reason` to be NULL; evidence_path likewise).
func latestReopenAttribution(t *testing.T, dbPath, id string) (by, onDate, reason, evidencePath string, found bool) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	row := db.QueryRow(`SELECT COALESCE(by,''), on_date, COALESCE(reason,''), COALESCE(evidence_path,'')
		FROM item_history WHERE atm_id=? AND event_type='Reopened' ORDER BY id DESC LIMIT 1`, id)
	if err := row.Scan(&by, &onDate, &reason, &evidencePath); err != nil {
		return "", "", "", "", false
	}
	return by, onDate, reason, evidencePath, true
}

// TestRecurrenceLink_GoldenRecurrenceReopensOriginalWithAttribution is
// T-D04's own GOLDEN bullet, verbatim from tasks.md: "the recurrence reopens
// the original with §11.4.34 attribution, increments its reopen count,
// mints no id" (contracts/closure-refusal.md RL-002: "SAME_DEFECT =>
// resolve the matched item through duplicate-of links to its chain head; if
// the head is terminal, reopen it (increment reopen_count, write a Reopened
// event with §11.4.34 details); ... No new id is minted."). TODAY:
// intake-match is not a recognised subcommand at all (main.go's `default:`
// case fires), so no link.json is EVER written and the original's row is
// never touched -- this test fails RED for that honest, self-flipping
// reason and requires NO edit once T098 lands.
func TestRecurrenceLink_GoldenRecurrenceReopensOriginalWithAttribution(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const originalID = "WIT-742"
	seedRecurrenceOriginal(t, dbPath, originalID,
		"audio output silently drops to mono after HDMI hot-unplug reconnect",
		"Reported symptom: after unplugging and replugging the HDMI cable, surround audio output silently reverts to mono and stays that way until the device reboots.",
		"hardware/rockchip/audio/tinyalsa_hal")
	beforeCount := distinctItemCount(t, dbPath)
	if beforeCount != 1 {
		t.Fatalf("seed sanity: distinct item count = %d, want 1", beforeCount)
	}

	cfg := writeMinimalIntakeMatchConfig(t, dbPath)
	reportPath := writeRecurrenceReportJSON(t, recurrenceReportFixture{
		Title:       "HDMI reconnect again drops audio output to mono, no 5.1",
		Scope:       "hardware/rockchip/audio/tinyalsa_hal",
		Description: "Same symptom as before: after unplugging and replugging the HDMI cable, surround audio output silently reverts to mono and stays that way until the device reboots.",
		IntakePath:  "reporting-directive",
	})
	linkPath := filepath.Join(t.TempDir(), "link.json")

	stdout, stderr, code := runWorkableItemsBinary(t, bin,
		"intake-match",
		"--config", cfg,
		"--report", reportPath,
		"--out", linkPath,
		"--apply",
	)

	if code != exitOK {
		t.Errorf("RED (T098 not yet landed): intake-match exited %d, want %d "+
			"(contracts/closure-refusal.md exit-codes: \"intake-match: 0 decision "+
			"written, 1 invalid report\" -- a SAME_DEFECT verdict is still a "+
			"written decision, not an invalid-report error); stdout=%q stderr=%q",
			code, exitOK, stdout, stderr)
	}

	verdict, origID, matchBasis, newReportRef, intakePath, ok := recurrenceLinkOf(t, linkPath)
	if !ok {
		t.Errorf("RED (T098 not yet landed): intake-match wrote no parseable "+
			"RecurrenceLink to %s at all -- want a body whose \"verdict\" field "+
			"is \"SAME_DEFECT\" and whose \"original_item_id\" is %q "+
			"(data-model.md §6.5); stdout=%q stderr=%q",
			linkPath, originalID, stdout, stderr)
	} else {
		if verdict != "SAME_DEFECT" {
			t.Errorf("verdict = %q, want %q (RL-001/RL-002: a report describing "+
				"the exact same defect, same scope, as an already-closed item)",
				verdict, "SAME_DEFECT")
		}
		if origID != originalID {
			t.Errorf("original_item_id = %q, want %q", origID, originalID)
		}
		if matchBasis == "" {
			t.Errorf("match_basis is empty, want one of data-model.md §6.5's " +
				"closed set {ticket, normalised(subject,scope), operator-confirmed}")
		}
		if newReportRef == "" {
			t.Errorf("new_report_ref is empty, want a reference to the incoming report")
		}
		if intakePath != "reporting-directive" {
			t.Errorf("intake_path = %q, want %q (echoed from the --report input)", intakePath, "reporting-directive")
		}
	}

	// RL-002: "increment reopen_count, write a Reopened event with §11.4.34
	// details" -- the load-bearing attribution + counter assertions.
	if got := reopenEventCount(t, dbPath, originalID); got != 1 {
		t.Errorf("RED (T098 not yet landed): %s shows %d Reopened event(s) "+
			"after --apply, want exactly 1 (RL-002: the recurrence reopens the "+
			"original and increments its reopen count)", originalID, got)
	} else {
		by, onDate, reason, evidence, found := latestReopenAttribution(t, dbPath, originalID)
		if !found {
			t.Errorf("reopenEventCount reported 1 but latestReopenAttribution found none for %s", originalID)
		} else {
			if by != "AI" && by != "User" {
				t.Errorf("§11.4.34 By = %q, want %q or %q", by, "AI", "User")
			}
			if onDate == "" {
				t.Errorf("§11.4.34 On (on_date) is empty, want an ISO date")
			}
			if reason == "" || !reopenReasons[reason] {
				t.Errorf("§11.4.34 Reason = %q, want a member of the closed reopen-reason "+
					"vocabulary: %s", reason, reopenReasonList())
			}
			if evidence == "" {
				t.Errorf("§11.4.34 Evidence (evidence_path) is empty, want a path to " +
					"captured evidence for the reopen (§11.4.7: a reopen without " +
					"evidence is a demotion-without-evidence bluff)")
			}
		}
	}
	if status, _ := itemLocation(t, dbPath, originalID); status != "Reopened" {
		t.Errorf("RED (T098 not yet landed): %s status = %q after --apply, want %q",
			originalID, status, "Reopened")
	}

	// RL-002's own explicit "No new id is minted": the SAME defect resolving
	// SAME_DEFECT must never grow the distinct-item count.
	if got := distinctItemCount(t, dbPath); got != beforeCount {
		t.Errorf("distinct item count = %d after --apply, want unchanged at %d "+
			"(RL-002: a SAME_DEFECT recurrence mints no id)", got, beforeCount)
	}
}

// TestRecurrenceLink_GoldenBad_UnrelatedSimilarReportNotMerged is T-D04's
// own GOLDEN-BAD bullet, verbatim from tasks.md: "an unrelated similar
// report is not merged — candidate link only" — see the file header's
// "GOLDEN-BAD FIXTURE DESIGN NOTE" for why this asserts the
// verdict-!=-SAME_DEFECT / no-reopen / new-id-minted triple rather than
// pinning DISTINCT-vs-UNDECIDED, and mirrors SOL-07's own documented
// false-merge counter-case (a shallow keyword overlap that a naive matcher
// could wrongly auto-merge — exactly what T093's "auto-merge on similarity"
// paired mutation later exercises against this same guard).
func TestRecurrenceLink_GoldenBad_UnrelatedSimilarReportNotMerged(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const originalID = "WIT-743"
	seedRecurrenceOriginal(t, dbPath, originalID,
		"audio output silently drops to mono after HDMI hot-unplug reconnect",
		"Reported symptom: after unplugging and replugging the HDMI cable, surround audio output silently reverts to mono and stays that way until the device reboots.",
		"hardware/rockchip/audio/tinyalsa_hal")
	beforeCount := distinctItemCount(t, dbPath)
	if beforeCount != 1 {
		t.Fatalf("seed sanity: distinct item count = %d, want 1", beforeCount)
	}
	if got := reopenEventCount(t, dbPath, originalID); got != 0 {
		t.Fatalf("seed sanity: %s already shows %d Reopened event(s)", originalID, got)
	}

	cfg := writeMinimalIntakeMatchConfig(t, dbPath)
	// Shares generic subject tokens ("audio output") and the SAME scope as
	// originalID, so scope alone cannot trivially force the verdict — but
	// names an entirely different root cause (a Bluetooth codec-switch
	// stutter, not an HDMI-reconnect mono downmix); the description even
	// states the distinction explicitly, mirroring how a real analyst would
	// read the two as unrelated on close reading (SOL-07 doc §1).
	reportPath := writeRecurrenceReportJSON(t, recurrenceReportFixture{
		Title:       "audio output stutters briefly when switching Bluetooth codec",
		Scope:       "hardware/rockchip/audio/tinyalsa_hal",
		Description: "When the connected Bluetooth headset renegotiates its codec mid-playback, the audio output stutters for roughly half a second; unrelated to HDMI or channel downmixing.",
		IntakePath:  "manual-qa",
	})
	linkPath := filepath.Join(t.TempDir(), "link.json")

	stdout, stderr, code := runWorkableItemsBinary(t, bin,
		"intake-match",
		"--config", cfg,
		"--report", reportPath,
		"--out", linkPath,
		"--apply",
	)

	if code != exitOK {
		t.Errorf("RED (T098 not yet landed): intake-match exited %d, want %d "+
			"(a DISTINCT/UNDECIDED verdict is still a written decision, not an "+
			"invalid-report error); stdout=%q stderr=%q", code, exitOK, stdout, stderr)
	}

	verdict, origID, _, _, _, ok := recurrenceLinkOf(t, linkPath)
	if !ok {
		t.Errorf("RED (T098 not yet landed): intake-match wrote no parseable "+
			"RecurrenceLink to %s at all -- want a body whose \"verdict\" field "+
			"is NOT \"SAME_DEFECT\" (RL-003: an unrelated report is never merged); "+
			"stdout=%q stderr=%q", linkPath, stdout, stderr)
	} else if verdict == "SAME_DEFECT" {
		t.Errorf("verdict = %q for two genuinely UNRELATED defects that merely "+
			"share generic subject vocabulary and scope -- this IS the "+
			"\"auto-merge on similarity\" false-merge failure mode SOL-07/RL-003 "+
			"exist to forbid (original_item_id in the wrongly-merged decision: %q)",
			verdict, origID)
	}

	// The decisive "not merged" assertions -- true regardless of whether the
	// correct verdict resolves DISTINCT or UNDECIDED (see file header):
	if got := reopenEventCount(t, dbPath, originalID); got != 0 {
		t.Errorf("%s shows %d Reopened event(s) after an UNRELATED report's "+
			"intake-match --apply, want exactly 0 -- the original must never be "+
			"touched by a report describing a different defect", originalID, got)
	}
	if got := distinctItemCount(t, dbPath); got != beforeCount+1 {
		t.Errorf("RED (T098 not yet landed): distinct item count = %d after "+
			"--apply, want %d (beforeCount+1) -- RL-003: both DISTINCT and "+
			"UNDECIDED verdicts mint a fresh id for a genuinely unrelated report; "+
			"it must never be silently dropped nor silently merged into %s",
			got, beforeCount+1, originalID)
	}
}
