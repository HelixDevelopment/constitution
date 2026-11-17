package main

// Unit tests of bodypatch.go (CON-456 round 5). Each case names the mutant of
// the round-5 mutation plan it kills (docs/qa/engine_idgrammar_2026_11_17/r5/).

import (
	"strings"
	"testing"
)

const bpBody = "## CON-1 — t\n\n" +
	"**Status:** Operator-blocked\n" +
	"**Type:** Task\n" +
	"**Evidence:** /e\n" +
	"**Operator-Block-Details:** WHAT: w WHY: y\n" +
	"- choice bullet\n" +
	"**Unblock-Choices:** [A] keep · [B] drop\n" +
	"**Reopened-Details:** By: AI On: 2026 Reason: r Evidence: /i\n" +
	"- **By:** AI\n" +
	"\n" +
	"prose line\n" +
	"  **Evidence:** indented quote in prose\n" +
	"\n" +
	"~~~\n" +
	"**Evidence:** tilde-fenced quote\n" +
	"**Operator-Block-Details:** WHAT: fenced\n" +
	"~~~\n"

func TestBodyPatch_RecordsOfTheMetadataBlockOnly(t *testing.T) {
	lines := splitKeepNewlines(bpBody)
	var kinds []string
	for _, r := range metaRecords(lines, metaBlockOf(lines)) {
		kinds = append(kinds, r.kind+":"+strings.TrimSpace(bodyText(lines[r.a]))[:12])
		// RM5 analogue: the Reopened-Details record takes its bullets.
		if r.kind == recReopened && r.b-r.a != 2 {
			t.Fatalf("the Reopened-Details record spans %d lines, want 2 (its attribution bullet)", r.b-r.a)
		}
		// RM1 analogue: the block record runs to its continuation bullet only.
		if r.kind == recOBD && r.b-r.a != 2 {
			t.Fatalf("the block record spans %d lines, want 2", r.b-r.a)
		}
	}
	want := "Evidence:**Evidence:* Operator-Block-Details:**Operator-B Unblock-Choices:**Unblock-Ch Reopened-Details:**Reopened-D"
	if got := strings.Join(kinds, " "); got != want {
		t.Fatalf("records = %q, want %q", got, want)
	}
}

// RM3 analogue: an indented `**Evidence:**` line is prose, never the closure
// record; close replaces the column-0 record and keeps the indented line.
func TestBodyPatch_IndentedRecordLineIsProse(t *testing.T) {
	if k := recordKindOf("  **Evidence:** x\n"); k != "" {
		t.Fatalf("an indented Evidence line is record %q", k)
	}
	if k := recordKindOf("  **Operator-Block-Details:** x\n"); k != recOBD {
		t.Fatalf("an indented block marker is %q; the parser reads it as the block record", k)
	}
	out := setRecord(bpBody, recEvidence, "**Evidence:** /new")
	if !strings.Contains(out, "  **Evidence:** indented quote in prose\n") || !strings.Contains(out, "**Evidence:** /new\n") || strings.Contains(out, "**Evidence:** /e\n") {
		t.Fatalf("setRecord touched a line outside the record:\n%s", out)
	}
}

// RM4 analogue: a `~~~` fence that directly follows the metadata block (no
// blank line) ends the block; the fenced quotes are never records.
func TestBodyPatch_TildeFenceEndsTheMetadataBlock(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Queued\n**Type:** Task\n~~~\n**Evidence:** fenced\n~~~\n"
	out, removed := dropRecords(b, recEvidence)
	if removed != "" || out != b {
		t.Fatalf("dropRecords removed a fenced line: %q\n%s", removed, out)
	}
	b2 := strings.ReplaceAll(b, "~~~", "```")
	if out, removed := dropRecords(b2, recEvidence); removed != "" || out != b2 {
		t.Fatalf("dropRecords removed a backtick-fenced line: %q", removed)
	}
	// Control needle: an unfenced record in the same position is removed.
	b3 := strings.Replace(b, "~~~\n**Evidence:** fenced\n~~~\n", "**Evidence:** real\n", 1)
	if _, removed := dropRecords(b3, recEvidence); removed != "**Evidence:** real" {
		t.Fatalf("control: the unfenced record was not removed (%q)", removed)
	}
}

func TestBodyPatch_SetRecordReplacesInPlaceAndInserts(t *testing.T) {
	out := setRecord(bpBody, recOBD, "**Operator-Block-Details:** WHAT: new")
	if strings.Count(out, "WHAT: new") != 1 || strings.Contains(out, "- choice bullet") || !strings.Contains(out, "WHAT: fenced") {
		t.Fatalf("setRecord did not replace the block record (with its continuation) in place:\n%s", out)
	}
	plain := "## CON-1 — t\n\n**Status:** Queued\n**Type:** Task\n\nprose\n"
	ins := setRecord(plain, recEvidence, "**Evidence:** /x")
	if ins != "## CON-1 — t\n\n**Status:** Queued\n**Type:** Task\n**Evidence:** /x\n\nprose\n" {
		t.Fatalf("setRecord insert after Type = %q", ins)
	}
	obs := setRecord(plain, recObsolete, "**Obsolete-Details:** x")
	if !strings.Contains(obs, "**Type:** Task\n**Obsolete-Details:** x\n\nprose") {
		t.Fatalf("Obsolete-Details not at the end of the block: %q", obs)
	}
}

func TestBodyPatch_DescriptionRegion(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Queued\n**Type:** Task\n\nold one\nold two\n\nkeep me\n"
	if got := replaceDescription(b, "old one\nold two", "new"); got != "## CON-1 — t\n\n**Status:** Queued\n**Type:** Task\n\nnew\n\nkeep me\n" {
		t.Fatalf("replaceDescription = %q", got)
	}
	// No region: an unchanged description changes nothing; a new one is
	// inserted after the metadata block and nothing is removed.
	if got := replaceDescription(b, "derived", "derived"); got != b {
		t.Fatalf("an unchanged derived description changed the body: %q", got)
	}
	got := replaceDescription(b, "derived", "fresh text")
	if !strings.Contains(got, "**Type:** Task\n\nfresh text\n\nold one\nold two\n\nkeep me\n") {
		t.Fatalf("insert = %q", got)
	}
	// A region inside the metadata block is never the description.
	if _, _, ok := descriptionRegion(splitKeepNewlines(b), "**Type:** Task"); ok {
		t.Fatal("a metadata line was taken as the description region")
	}
}

func TestBodyPatch_OwnedLinesGateOrderAndOwnership(t *testing.T) {
	swapped := strings.Replace(bpBody, "prose line\n  **Evidence:** indented quote in prose\n", "  **Evidence:** indented quote in prose\nprose line\n", 1)
	if p := ownedLinesProblems(bpBody, swapped, bodyOwnership{status: true}, "", ""); len(p) == 0 {
		t.Fatal("a reordered pair of unowned lines was not refused")
	}
	st := canonicalizeBodyStatusLine(bpBody, "Queued")
	if p := ownedLinesProblems(bpBody, st, bodyOwnership{status: true}, "", ""); len(p) != 0 {
		t.Fatalf("golden-FALSE: an owned Status change was refused: %v", p)
	}
	if p := ownedLinesProblems(bpBody, st, bodyOwnership{}, "", ""); len(p) == 0 {
		t.Fatal("a Status change by a writer that does not own it was not refused")
	}
	// RM7 analogue: block owns its own record, not Reopened-Details.
	noRe, _ := dropRecords(bpBody, recReopened)
	if p := ownedLinesProblems(bpBody, noRe, bodyOwnership{status: true, records: []string{recOBD, recChoices}}, "", ""); len(p) == 0 {
		t.Fatal("a dropped Reopened-Details record was not refused for a block-shaped ownership")
	}
	if p := ownedLinesProblems("", "anything\n", bodyOwnership{}, "", ""); p != nil {
		t.Fatalf("an empty old body has nothing to keep: %v", p)
	}
}

// OM5: a second record of the same kind in the metadata block is removed, not
// replaced by a second copy of the new record.
func TestBodyPatch_SetRecordCollapsesDuplicateRecords(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Fixed\n**Type:** Task\n**Evidence:** /a\n**Evidence:** /b\n\nprose\n"
	out := setRecord(b, recEvidence, "**Evidence:** /new")
	if out != "## CON-1 — t\n\n**Status:** Fixed\n**Type:** Task\n**Evidence:** /new\n\nprose\n" {
		t.Fatalf("setRecord over two records = %q", out)
	}
}

// OM11: a blocked item whose only block record sits inside its description
// (a legacy shape the parser reads, first marker wins): replacing the
// description would drop the record while the row stays, so update refuses.
// Control needle: the same edit with the record kept is accepted.
func TestBodyPatch_UpdateRefusesDroppingBlockRecordFromDescription(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-960", "legacy block record probe", "Task", "Low")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-960", "--details", "w", "--why", "y",
		"--unblock", "[A] a · [B] b", "--who", "o"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	rec := "**Operator-Block-Details:** WHAT: w WHY: y UNBLOCK: [A] a · [B] b WHO: o"
	desc := "Legacy description line one of the probe item.\n" + rec
	body := "## CON-960 — legacy block record probe\n\n**Status:** Operator-blocked\n**Type:** Task\n**Severity:** Low\n\n" + desc + "\n\n"
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE items SET body_md=?, description=? WHERE atm_id='CON-960'`, body, desc); err != nil {
		t.Fatal(err)
	}
	db.Close()
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-960", "--description", "A replacement description without the record line."}); rc == exitOK {
		t.Fatalf("update dropped the block record living in the description:\n%s", r4Body(t, dbPath, "CON-960"))
	}
	if got := r4Body(t, dbPath, "CON-960"); got != body {
		t.Fatalf("a refused update wrote the body:\n%s", got)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-960", "--description", "A replacement first line.\n" + rec}); rc != exitOK {
		t.Fatal("control: an edit that keeps the record was refused")
	}
}

// Class sweep (upd_sev / upd_type / upd_assign): a field update owns only the
// lines of the fields it sets.
func TestBodyPatch_FieldOwnership(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Queued\n**Type:** Task\n**Severity:** Low\n\nprose\n"
	sev := strings.Replace(b, "**Severity:** Low", "**Severity:** High", 1)
	if p := ownedLinesProblems(b, sev, bodyOwnership{fields: []string{"Severity"}}, "", ""); len(p) != 0 {
		t.Fatalf("golden-FALSE: an owned Severity change was refused: %v", p)
	}
	if p := ownedLinesProblems(b, sev, bodyOwnership{fields: []string{"Type"}}, "", ""); len(p) == 0 {
		t.Fatal("a Severity change by a writer owning only Type was not refused")
	}
	if p := ownedLinesProblems(b, strings.Replace(b, "prose", "", 1), bodyOwnership{fields: []string{"Severity"}}, "", ""); len(p) == 0 {
		t.Fatal("a dropped prose line was not refused for a field owner")
	}
}

// upsertMetaLine (reopen) replaces the Reopened-Details record of the
// metadata block; a fenced quote of the same kind elsewhere is kept, and with
// no record in the block one is inserted (round 4 replaced the first such line
// anywhere in the body, the fenced quote included).
func TestBodyPatch_UpsertReopenedKeepsFencedQuote(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Fixed\n**Type:** Task\n\nprose\n\n```\n**Reopened-Details:** quoted\n```\n"
	out := upsertMetaLine(b, "**Reopened-Details:**", "**Reopened-Details:** By: AI On: d Reason: r Evidence: /i")
	if !strings.Contains(out, "```\n**Reopened-Details:** quoted\n```") {
		t.Fatalf("the fenced quote was replaced:\n%s", out)
	}
	if !strings.Contains(out, "**Type:** Task\n**Reopened-Details:** By: AI") {
		t.Fatalf("no record was inserted into the metadata block:\n%s", out)
	}
	again := upsertMetaLine(out, "**Reopened-Details:**", "**Reopened-Details:** By: User On: d2 Reason: r Evidence: /j")
	if strings.Count(again, "**Reopened-Details:** By:") != 1 || !strings.Contains(again, "By: User On: d2") {
		t.Fatalf("a second upsert did not replace the block record:\n%s", again)
	}
}

// setStatusAndSyncBody (subtask-status) ends a block like every other status
// writer (review r4 finding 3, writer sweep).
func TestBodyPatch_SetStatusAndSyncBodyEndsBlock(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-980", "status choke point probe", "Task", "Low")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-980", "--details", "the operator decides",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	if n := g456Query(t, dbPath, `SELECT count(*) FROM operator_block_details WHERE atm_id='CON-980'`); n != "1" {
		t.Fatalf("control: %s block rows after block", n)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := setStatusAndSyncBody(tx, "CON-980", "Issues", "In progress"); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	db.Close()
	if n := g456Query(t, dbPath, `SELECT count(*) FROM operator_block_details WHERE atm_id='CON-980'`); n != "0" {
		t.Fatalf("%s block rows after the status write off Operator-blocked", n)
	}
	body := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-980'`)
	if strings.Contains(body, "Operator-Block-Details") {
		t.Fatalf("the body still carries the block record:\n%s", body)
	}
	if h := g456Query(t, dbPath, `SELECT count(*) FROM item_history WHERE atm_id='CON-980' AND reason='operator-block-ended' AND evidence_path LIKE '%the operator decides%'`); h != "1" {
		t.Fatalf("history rows for the ended block = %s", h)
	}
	r4Validate(t, r3Cycle(t, dbPath))
}
