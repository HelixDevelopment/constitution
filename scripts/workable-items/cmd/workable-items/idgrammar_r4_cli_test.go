package main

// CON-456 round 4. Finding 1 of the round-3 review: a write that regenerates
// an item body (update --description, block, close) must keep the
// engine-written detail lines of the old body (detailcarry.go), and its gate
// refuses a write that would still lose one. Findings 3 and 5: tests that kill
// the reviewer mutants RR2 (an --evidence line break) and RR3b (a choices-only
// edit of the block record), and the Bug-only, fence-aware legacy adoption.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func r4Evidence(t *testing.T, name string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte("evidence\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func r4Body(t *testing.T, dbPath, id string) string {
	t.Helper()
	return g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id=? ORDER BY rowid DESC LIMIT 1`, id)
}

func r4Validate(t *testing.T, dbPath string) {
	t.Helper()
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate exited %d", rc)
	}
}

// r4Reopened adds id, closes it with evidence ev1 and reopens it, so its body
// carries an Evidence line and a Reopened-Details line.
func r4Reopened(t *testing.T, dbPath, id string) (ev1, inc string) {
	t.Helper()
	g456Add(t, dbPath, id, "detail carry probe", "Task", "Low")
	ev1 = r4Evidence(t, "ev1.txt")
	if rc := closeCmd([]string{id, "--db", dbPath, "--status", "completed", "--evidence", ev1}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	inc = r4Evidence(t, "incident.txt")
	if rc := reopenCmd([]string{"--db", dbPath, "--id", id, "--why", "test-failed", "--who", "AI",
		"--when", "2026-11-17", "--incident", inc}); rc != exitOK {
		t.Fatalf("reopen exited %d", rc)
	}
	return ev1, inc
}

// Every detail kind an Issues item can carry survives update --description,
// two db-to-md -> md-to-db cycles and validate (the class, not one instance).
func TestCON456R4_UpdateDescriptionKeepsEveryDetailKind(t *testing.T) {
	dbPath := newTestDB(t)
	ev1, _ := r4Reopened(t, dbPath, "CON-950")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-950", "--details", "the operator decides",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	before := r4Body(t, dbPath, "CON-950")
	for _, want := range []string{"**Evidence:** " + ev1, "**Reopened-Details:**", "**Operator-Block-Details:**"} {
		if !strings.Contains(before, want) {
			t.Fatalf("control: the body before the update lacks %q:\n%s", want, before)
		}
	}
	const q = `SELECT what||'|'||why_exhausted_alternatives||'|'||unblock_condition||'|'||COALESCE(who,'')
		FROM operator_block_details WHERE atm_id='CON-950'`
	row := g456Query(t, dbPath, q)
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-950", "--description", g456Desc + " Edited once."}); rc != exitOK {
		t.Fatalf("update --description exited %d", rc)
	}
	after := r4Body(t, dbPath, "CON-950")
	// Round 5: detailcarry.go is gone (bodypatch.go); the check names the
	// detail lines of the old body directly.
	for _, ln := range strings.Split(before, "\n") {
		for _, p := range []string{"**Evidence:**", "**Reopened-Details:**", "**Operator-Block-Details", "**Unblock-Choices:**", "- **"} {
			if strings.HasPrefix(ln, p) && !strings.Contains(after, ln) {
				t.Errorf("update --description dropped the detail line %q:\n%s", ln, after)
			}
		}
	}
	if !strings.Contains(after, "Edited once.") {
		t.Fatalf("the new description is not in the body:\n%s", after)
	}
	rt1 := r3Cycle(t, dbPath)
	rt2 := r3Cycle(t, rt1)
	for _, p := range []string{rt1, rt2} {
		if got := g456Query(t, p, q); got != row {
			t.Fatalf("operator_block_details after a cycle = %q, want %q", got, row)
		}
		if got := r4Body(t, p, "CON-950"); got != after {
			t.Fatalf("body changed on a cycle:\n got %q\nwant %q", got, after)
		}
		r4Validate(t, p)
	}
}

// The Obsolete-Details line of a Fixed item survives update --description.
func TestCON456R4_UpdateDescriptionKeepsObsoleteDetails(t *testing.T) {
	dbPath, ev := r3ObsoleteItem(t)
	if rc := obsoleteDetailsCmd([]string{"CON-927", "--db", dbPath, "--since", "2026-11-17",
		"--reason", "duplicate-of", "--superseding", "CON-082", "--evidence", ev}); rc != exitOK {
		t.Fatalf("obsolete-details exited %d", rc)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-927", "--location", "Fixed",
		"--description", g456Desc + " Edited."}); rc != exitOK {
		t.Fatalf("update --description exited %d", rc)
	}
	body := r4Body(t, dbPath, "CON-927")
	if !strings.Contains(body, "**Obsolete-Details:** Since: 2026-11-17; Reason: duplicate-of; Superseding-item: CON-082") {
		t.Fatalf("update --description dropped the Obsolete-Details line:\n%s", body)
	}
	if !strings.Contains(body, "**Evidence:** "+ev) {
		t.Fatalf("update --description dropped the closure Evidence line:\n%s", body)
	}
	r4Validate(t, r3Cycle(t, dbPath))
}

// block writes its own record and keeps the Reopened-Details and Evidence
// lines; a second block replaces the record (no stale Unblock-Choices).
func TestCON456R4_BlockKeepsOtherDetailLines(t *testing.T) {
	dbPath := newTestDB(t)
	ev1, _ := r4Reopened(t, dbPath, "CON-951")
	blk := func(what string) {
		t.Helper()
		if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-951", "--details", what,
			"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
			t.Fatalf("block exited %d", rc)
		}
	}
	blk("first decision")
	blk("second decision")
	body := r4Body(t, dbPath, "CON-951")
	if !strings.Contains(body, "**Reopened-Details:**") || !strings.Contains(body, "**Evidence:** "+ev1) {
		t.Fatalf("block dropped a detail line:\n%s", body)
	}
	if strings.Count(body, "**Operator-Block-Details:**") != 1 || !strings.Contains(body, "WHAT: second decision") {
		t.Fatalf("block did not replace its record:\n%s", body)
	}
	r4Validate(t, r3Cycle(t, dbPath))
}

// close keeps the Reopened-Details line and replaces the evidence line.
func TestCON456R4_CloseKeepsReopenedDetailsAndReplacesEvidence(t *testing.T) {
	dbPath := newTestDB(t)
	ev1, _ := r4Reopened(t, dbPath, "CON-952")
	ev2 := r4Evidence(t, "ev2.txt")
	if rc := closeCmd([]string{"CON-952", "--db", dbPath, "--status", "completed", "--evidence", ev2}); rc != exitOK {
		t.Fatalf("second close exited %d", rc)
	}
	body := r4Body(t, dbPath, "CON-952")
	if !strings.Contains(body, "**Reopened-Details:**") {
		t.Fatalf("close dropped the Reopened-Details line:\n%s", body)
	}
	if strings.Count(body, "**Evidence:**") != 1 || !strings.Contains(body, "**Evidence:** "+ev2) || strings.Contains(body, ev1) {
		t.Fatalf("close did not replace the evidence line:\n%s", body)
	}
	r4Validate(t, r3Cycle(t, dbPath))
}

// The operator's own description text is the operator's to replace: a detail
// line that is a line of the old description, or that sits in a fenced code
// block, is not carried.
func TestCON456R4_DescriptionOwnedAndFencedLinesNotCarried(t *testing.T) {
	dbPath := newTestDB(t)
	desc := g456Desc + "\n\n**Evidence:** quoted by the operator in the description\n\n```\n**Reopened-Details:** inside a fence\n```"
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-953", "--title", "owned lines", "--description", desc, "Task", "Low"}); rc != exitOK {
		t.Fatalf("add exited %d", rc)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-953", "--description", g456Desc + " Replaced."}); rc != exitOK {
		t.Fatalf("update --description exited %d", rc)
	}
	body := r4Body(t, dbPath, "CON-953")
	if strings.Contains(body, "quoted by the operator") || strings.Contains(body, "inside a fence") {
		t.Fatalf("an operator-owned line was carried into the new body:\n%s", body)
	}
}

// Round 5: the round-4 detail-loss gate (detailcarry.go) is replaced by the
// owned-lines gate (bodypatch.go); the same cases, judged by ownership.
func TestCON456R4_DetailLossGate(t *testing.T) {
	old := "## CON-1 — t\n\n**Status:** Operator-blocked\n**Type:** Task\n**Evidence:** /e\n" +
		"**Operator-Block-Details:** WHAT: w WHY: y\n- choice bullet\n**Reopened-Details:** By: AI On: 2026 Reason: r Evidence: /i\n- **By:** AI\n\nprose\n"
	none := bodyOwnership{}
	if p := ownedLinesProblems(old, old, none, "", ""); len(p) != 0 {
		t.Fatalf("golden-FALSE: an unchanged body was refused: %v", p)
	}
	noEv := strings.Replace(old, "**Evidence:** /e\n", "", 1)
	if p := ownedLinesProblems(old, noEv, none, "", ""); len(p) != 1 || !strings.Contains(p[0], "Evidence") {
		t.Fatalf("a dropped Evidence line: %v", p)
	}
	if p := ownedLinesProblems(old, noEv, bodyOwnership{records: []string{recEvidence}}, "", ""); len(p) != 0 {
		t.Fatalf("an owned record was refused: %v", p)
	}
	noBullet := strings.Replace(old, "- choice bullet\n", "", 1)
	if p := ownedLinesProblems(old, noBullet, none, "", ""); len(p) == 0 {
		t.Fatal("a changed block record (continuation bullet dropped) was not refused")
	}
	noAttr := strings.Replace(old, "- **By:** AI\n", "", 1)
	if p := ownedLinesProblems(old, noAttr, none, "", ""); len(p) == 0 {
		t.Fatal("a dropped Reopened-Details attribution bullet was not refused")
	}
	choices := strings.Replace(old, "prose\n", "prose\n**Unblock-Choices:** [A] x · [B] y\n", 1)
	if p := ownedLinesProblems(choices, old, bodyOwnership{records: []string{recChoices}}, "", ""); len(p) == 0 {
		t.Fatal("a dropped Unblock-Choices line outside the metadata block was not refused")
	}
	fenced := "## CON-1 — t\n\n**Type:** Task\n\n```\n**Evidence:** /e\n```\n"
	if p := ownedLinesProblems(fenced, "## CON-1 — t\n\n**Type:** Task\n", bodyOwnership{records: []string{recEvidence}}, "", ""); len(p) == 0 {
		t.Fatal("a dropped fenced line was not refused (a fenced line is never a record a writer owns)")
	}
	// Own mutant M9 (round 4): a new marker ahead of the record changes what
	// the next md-to-db reads; blockRecordKept refuses it.
	forged := strings.Replace(old, "**Type:** Task\n", "**Type:** Task\n**Operator-Block-Details:** WHAT: forged\n\n", 1)
	if p := blockRecordKept(old, forged); len(p) == 0 {
		t.Fatal("a changed Operator-Block-Details source (forged marker ahead of the record) was not refused")
	}
	if p := blockRecordKept(old, old); len(p) != 0 {
		t.Fatalf("golden-FALSE: an unchanged record was refused: %v", p)
	}
}

// RR2: an --evidence path with a line break is refused before anything is
// written, although the file exists (requireEvidencePath alone accepts it).
func TestCON456R4_ObsoleteDetailsEvidenceLineBreakRefused(t *testing.T) {
	for _, sep := range []string{"\n", "\r", "\u2028"} {
		dbPath, _ := r3ObsoleteItem(t)
		ev := r4Evidence(t, "ev"+sep+"tail.txt")
		r3Refused(t, dbPath, "obsolete-details --evidence with a line break", func() int {
			return obsoleteDetailsCmd([]string{"CON-927", "--db", dbPath, "--since", "2026-11-17",
				"--reason", "duplicate-of", "--superseding", "CON-082", "--evidence", ev})
		})
	}
}

// RR3b: an edit that changes only the `**Unblock-Choices:**` line of a block
// record is imported: the stored row is re-derived, never kept stale.
func TestCON456R4_UnblockChoicesOnlyEditRederived(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-954", "choices probe", "Task", "Low")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-954", "--details", "the decision",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	rt := r3Cycle(t, dbPath)
	iss, fix := g456Export(t, rt, t.TempDir())
	raw, err := os.ReadFile(iss)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.SplitAfter(string(raw), "\n")
	var b strings.Builder
	found := false
	for _, ln := range lines {
		b.WriteString(ln)
		if !found && strings.HasPrefix(ln, "**Operator-Block-Details:**") {
			b.WriteString("**Unblock-Choices:** [C] newly enumerated · [D] other\n")
			found = true
		}
	}
	if !found {
		t.Fatal("control: the block line was not found in Issues.md")
	}
	if err := os.WriteFile(iss, []byte(b.String()), 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	got := g456Query(t, rt, `SELECT unblock_condition FROM operator_block_details WHERE atm_id='CON-954'`)
	if !strings.Contains(got, "[C] newly enumerated · [D] other") {
		t.Fatalf("a choices-only edit kept the stale row: unblock_condition = %q", got)
	}
}

// Finding 5: the legacy Bug template is adopted for a Bug only, and never
// from a fenced code block.
func TestCON456R4_LegacyAdoptionBugOnlyAndNotFenced(t *testing.T) {
	legacy := "**Reproduction:** none — UNREPRODUCED (§11.4.292)\n**Investigation:** not-started (§11.4.294)"
	for _, c := range []struct{ name, typ, desc string }{
		{"task", "Task", g456Desc + "\n\n" + legacy},
		{"fenced bug", "Bug", g456Desc + "\n\n```\n" + legacy + "\n```"},
	} {
		t.Run(c.name, func(t *testing.T) {
			dbPath := newTestDB(t)
			rc := addCmd([]string{"--db", dbPath, "--id", "CON-955", "--title", "legacy probe", "--description", c.desc, c.typ, "Low"})
			if rc != exitOK {
				return // refused, as before round 3: nothing adopted
			}
			st := g456Query(t, dbPath, `SELECT reproduction_state||'|'||investigation_state FROM items WHERE atm_id='CON-955'`)
			if st != "UNSET|UNSET" {
				t.Fatalf("%s: the legacy lines were adopted as states %q", c.name, st)
			}
		})
	}
	// Control: an unfenced legacy Bug is still adopted.
	dbPath := newTestDB(t)
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-956", "--title", "legacy probe", "--description", g456Desc + "\n\n" + legacy, "Bug", "Low"}); rc != exitOK {
		t.Fatalf("control: the legacy Bug add exited %d", rc)
	}
	if st := g456Query(t, dbPath, `SELECT reproduction_state||'|'||investigation_state FROM items WHERE atm_id='CON-956'`); st != "UNREPRODUCED|not-started" {
		t.Fatalf("control: the legacy Bug was not adopted: %q", st)
	}
}

// Review finding 4 (RR5): obsolete-details passes its values to the whole-item
// gate. Recorded equivalence argument (README r4, section 4): every value is
// written verbatim on the one `**Obsolete-Details:**` line, which the renderer
// never rewrites, so the gate's input check can only fail when a line break
// splits that line, and the line-break pre-check refuses that first. This test
// pins the input check itself, which block, close, update and reopen rely on:
// a value that does not survive in the rendered Markdown is refused, and a
// value that does survive is accepted (golden-FALSE).
func TestCON456R4_GateItemWriteInputCheckPinned(t *testing.T) {
	desc := g456Desc
	body := renderItemBody("CON-960", "gate input probe", "Task", "Low", desc, "Queued", "", "")
	it := item{AtmID: "CON-960", Title: "gate input probe", Type: "Task", Severity: "Low", Status: "Queued",
		CurrentLocation: "Issues", Representation: "section", Description: desc, BodyMD: body}
	if _, err := gateItemWrite(it, "the description floor"); err != nil {
		t.Fatalf("golden-FALSE: a value present in the Markdown was refused: %v", err)
	}
	if _, err := gateItemWrite(it, "a value the Markdown does not carry"); err == nil {
		t.Fatal("a value absent from the rendered Markdown was accepted")
	}
	if _, err := gateItemWrite(it, ""); err != nil {
		t.Fatalf("an empty input must be ignored: %v", err)
	}
}

// Class sweep finding (round 4, RT_SIDE on block then close): close ends the
// block and drops the Operator-Block-Details record from the body, but left the
// operator_block_details row behind; the next sync md-to-db deleted it, so the
// database and the Markdown disagreed between the two steps (the same on main
// and r3). close now removes the row in its own transaction, so a md-to-db
// cycle right after close changes no side-table row.
func TestCON456R4_CloseOfBlockedItemRemovesBlockRow(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-961", "block then close probe", "Task", "Low")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-961", "--details", "the operator decides",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	const q = `SELECT COUNT(*) FROM operator_block_details WHERE atm_id='CON-961'`
	if got := g456Query(t, dbPath, q); got != "1" {
		t.Fatalf("control: block wrote %s operator_block_details rows, want 1", got)
	}
	ev := r4Evidence(t, "ev.txt")
	if rc := closeCmd([]string{"CON-961", "--db", dbPath, "--status", "completed", "--evidence", ev}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	if body := r4Body(t, dbPath, "CON-961"); strings.Contains(body, "**Operator-Block-Details") {
		t.Fatalf("close kept the block record in the body:\n%s", body)
	}
	if got := g456Query(t, dbPath, q); got != "0" {
		t.Fatalf("close left %s operator_block_details rows behind (the next md-to-db deletes them)", got)
	}
	rt := r3Cycle(t, dbPath)
	if got := g456Query(t, rt, q); got != "0" {
		t.Fatalf("after a cycle: %s rows", got)
	}
	r4Validate(t, rt)
}
