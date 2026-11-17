package main

// CON-456 round 5 (structural). Review r4 findings 1 to 5: every body writer
// patches the stored body in place and may change only the lines it owns
// (bodypatch.go). These tests drive the writers on an item READ BY md-to-db
// with a rich authored body (the class the r4 sweep missed: the description
// column of such an item is derived, so a writer that regenerated the body from
// the columns dropped everything else), and pin the reviewer's distinguishing
// inputs for the r4 mutants RM1, RM3, RM4, RM6 and M2.

import (
	"os"
	"strings"
	"testing"
)

// r5Authored are the lines an operator wrote into an item's Markdown that no
// column holds. Every body writer must keep every one of them.
var r5Authored = []string{
	"Acceptance criteria: the r5 probe line survives every body writer.",
	"**Verification:** provisional (section 11.4.290) -- job: r5 probe -- due: next run.",
	"**Reported-Via:** BUG directive",
	"**Reported-By:** operator (r5 probe)",
	"**Candidate-Duplicate-Of:** CON-001 (r5 probe, undecided)",
	"  **Evidence:** indented quote of an evidence line in prose (RM3 input)",
	"| column a | column b |",
	"### Notes",
	"A note under a sub-heading.",
}

// r5Fenced are authored lines inside fenced code blocks: text, never metadata.
var r5Fenced = []string{
	"~~~",
	"**Evidence:** fenced quote under a tilde fence (RM4 input)",
	"~~~",
	"```",
	"**Operator-Block-Details:** WHAT: a fenced quote, not a record",
	"**Unblock-Choices:** [X] fenced · [Y] quote",
	"```",
}

// r5RichItem adds id, exports the trackers, writes the authored lines into its
// Markdown after the description and imports it back, so the item is one READ
// BY md-to-db (its description column is derived). It returns the db path.
func r5RichItem(t *testing.T, id string) string {
	t.Helper()
	dbPath := newTestDB(t)
	g456Add(t, dbPath, id, "r5 rich body probe", "Task", "Low")
	dir := t.TempDir()
	iss, fix := g456Export(t, dbPath, dir)
	raw, err := os.ReadFile(iss)
	if err != nil {
		t.Fatal(err)
	}
	extra := strings.Join(r5Authored[:6], "\n\n") + "\n\n" + strings.Join(r5Authored[6:7], "\n") + "\n\n" +
		strings.Join(r5Fenced, "\n") + "\n\n" + strings.Join(r5Authored[7:], "\n\n")
	s := strings.Replace(string(raw), g456Desc+"\n", g456Desc+"\n\n"+extra+"\n", 1)
	if s == string(raw) {
		t.Fatal("control: could not place the authored lines")
	}
	if err := os.WriteFile(iss, []byte(s), 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := g456Import(dbPath, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	body := r4Body(t, dbPath, id)
	for _, want := range append(append([]string{}, r5Authored...), r5Fenced...) {
		if !strings.Contains(body, want) {
			t.Fatalf("control: the imported body lacks %q:\n%s", want, body)
		}
	}
	if d := g456Query(t, dbPath, `SELECT description FROM items WHERE atm_id=?`, id); strings.Contains(d, "\n") {
		t.Fatalf("control: the description column of a md-read item is derived, got %q", d)
	}
	return dbPath
}

func r5Block(t *testing.T, dbPath, id, what string) {
	t.Helper()
	if rc := blockCmd([]string{"--db", dbPath, "--id", id, "--details", what,
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
}

// r5Fence returns the number of lines equal to line outside fenced code blocks.
func r5Unfenced(body, line string) int {
	n, in := 0, false
	for _, ln := range strings.Split(body, "\n") {
		t := strings.TrimSpace(ln)
		if strings.HasPrefix(t, "```") || strings.HasPrefix(t, "~~~") {
			in = !in
			continue
		}
		if !in && strings.HasPrefix(ln, line) {
			n++
		}
	}
	return n
}

// r5Check asserts every authored and fenced line is in the body, the fenced
// lines are still fenced (none was lifted into metadata), and the item reads
// back unchanged over a db-to-md -> md-to-db cycle with a consistent block
// record (a row iff the item is Operator-blocked) and validate OK.
func r5Check(t *testing.T, dbPath, id, what string) {
	t.Helper()
	body := r4Body(t, dbPath, id)
	for _, want := range append(append([]string{}, r5Authored...), r5Fenced...) {
		if !strings.Contains(body, want) {
			t.Errorf("%s dropped the authored line %q:\n%s", what, want, body)
		}
	}
	if n := r5Unfenced(body, "**Evidence:** fenced quote"); n != 0 {
		t.Errorf("%s lifted a fenced quote into the metadata (%d unfenced copies):\n%s", what, n, body)
	}
	const obd = `SELECT COUNT(*) FROM operator_block_details WHERE atm_id=?`
	status := g456Query(t, dbPath, `SELECT status FROM items WHERE atm_id=?`, id)
	want := "0"
	if status == "Operator-blocked" {
		want = "1"
	}
	if got := g456Query(t, dbPath, obd, id); got != want {
		t.Errorf("%s: status %s with %s operator_block_details rows, want %s", what, status, got, want)
	}
	rt := r3Cycle(t, dbPath)
	if got := r4Body(t, rt, id); got != body {
		t.Errorf("%s: the body changed on a cycle:\n got %q\nwant %q", what, got, body)
	}
	if got := g456Query(t, rt, obd, id); got != want {
		t.Errorf("%s: after a cycle %s operator_block_details rows, want %s", what, got, want)
	}
	r4Validate(t, rt)
}

// Finding 1 (class): every body writer on a md-read item with a rich body.
func TestCON456R5_EveryWriterKeepsAuthoredBodyOfMdReadItem(t *testing.T) {
	ev := r4Evidence(t, "ev.txt")
	inc := r4Evidence(t, "incident.txt")
	reopen := func(dbPath, id string) int {
		return reopenCmd([]string{"--db", dbPath, "--id", id, "--why", "test-failed", "--who", "AI",
			"--when", "2026-11-17", "--incident", inc})
	}
	closeIt := func(dbPath, id, status string) int {
		return closeCmd([]string{id, "--db", dbPath, "--status", status, "--evidence", ev})
	}
	cases := []struct {
		name string
		run  func(t *testing.T, dbPath, id string)
	}{
		{"update --description (same text)", func(t *testing.T, dbPath, id string) {
			d := g456Query(t, dbPath, `SELECT description FROM items WHERE atm_id=?`, id)
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--description", d}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
		}},
		{"update --description (new text)", func(t *testing.T, dbPath, id string) {
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--description", g456Desc + " Replaced in round five."}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
			if b := r4Body(t, dbPath, id); !strings.Contains(b, "Replaced in round five.") {
				t.Fatalf("the new description is not in the body:\n%s", b)
			}
		}},
		{"update --status", func(t *testing.T, dbPath, id string) {
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--status", "In progress"}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
		}},
		{"block", func(t *testing.T, dbPath, id string) { r5Block(t, dbPath, id, "the operator decides") }},
		{"block twice", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "first decision")
			r5Block(t, dbPath, id, "second decision")
			if b := r4Body(t, dbPath, id); r5Unfenced(b, "**Operator-Block-Details:**") != 1 || !strings.Contains(b, "WHAT: second decision") {
				t.Fatalf("block did not replace its record:\n%s", b)
			}
		}},
		{"block then update --description", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "the operator decides")
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--description", g456Desc + " Edited while blocked."}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
		}},
		{"block then update --status (unblock)", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "the operator decides")
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--status", "In progress"}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
		}},
		{"block then move to Fixed", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "the operator decides")
			if rc := moveCmd([]string{"--db", dbPath, "--id", id, "--to", "Fixed", "--status", "Completed (→ Fixed.md)",
				"--why", "r5 probe", "--evidence", ev}); rc != exitOK {
				t.Fatalf("move exited %d", rc)
			}
		}},
		{"block then reopen", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "the operator decides")
			if rc := reopen(dbPath, id); rc != exitOK {
				t.Fatalf("reopen exited %d", rc)
			}
		}},
		{"block then close", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "the operator decides")
			if rc := closeIt(dbPath, id, "completed"); rc != exitOK {
				t.Fatalf("close exited %d", rc)
			}
		}},
		{"close", func(t *testing.T, dbPath, id string) {
			if rc := closeIt(dbPath, id, "completed"); rc != exitOK {
				t.Fatalf("close exited %d", rc)
			}
			if b := r4Body(t, dbPath, id); r5Unfenced(b, "**Evidence:** "+ev) != 1 {
				t.Fatalf("close did not write its evidence line:\n%s", b)
			}
		}},
		{"close then reopen then close", func(t *testing.T, dbPath, id string) {
			if rc := closeIt(dbPath, id, "completed"); rc != exitOK {
				t.Fatalf("close exited %d", rc)
			}
			if rc := reopen(dbPath, id); rc != exitOK {
				t.Fatalf("reopen exited %d", rc)
			}
			if rc := closeIt(dbPath, id, "completed"); rc != exitOK {
				t.Fatalf("second close exited %d", rc)
			}
		}},
		{"close obsolete then obsolete-details then update --description", func(t *testing.T, dbPath, id string) {
			if rc := closeIt(dbPath, id, "obsolete"); rc != exitOK {
				t.Fatalf("close exited %d", rc)
			}
			if rc := obsoleteDetailsCmd([]string{id, "--db", dbPath, "--since", "2026-11-17",
				"--reason", "duplicate-of", "--superseding", "CON-082", "--evidence", ev}); rc != exitOK {
				t.Fatalf("obsolete-details exited %d", rc)
			}
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--location", "Fixed", "--description", g456Desc + " Edited after."}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
			if b := r4Body(t, dbPath, id); !strings.Contains(b, "**Obsolete-Details:** Since: 2026-11-17") {
				t.Fatalf("the Obsolete-Details line was lost:\n%s", b)
			}
		}},
		// Round-5 class sweep (mdsweep upd_sev / upd_type / upd_assign): a field
		// update patches the item's own metadata line, so the stored body
		// already reads what the next md-to-db leaves (r5Check cycles it).
		{"update --severity --type --assigned-to --created-by", func(t *testing.T, dbPath, id string) {
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--severity", "High", "--type", "Bug",
				"--assigned-to", "r5 assignee", "--created-by", "r5 creator"}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
			b := r4Body(t, dbPath, id)
			for _, want := range []string{"**Severity:** High", "**Type:** Bug", "**Assigned-To:** r5 assignee", "**Created-By:** r5 creator"} {
				if r5Unfenced(b, want) != 1 {
					t.Fatalf("the field update did not patch %q:\n%s", want, b)
				}
			}
			if r5Unfenced(b, "**Severity:** Low") != 0 || r5Unfenced(b, "**Type:** Task") != 0 {
				t.Fatalf("a stale metadata line is left:\n%s", b)
			}
		}},
		{"update --assigned-to then clear it", func(t *testing.T, dbPath, id string) {
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--assigned-to", "someone"}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--assigned-to", ""}); rc != exitOK {
				t.Fatalf("clearing update exited %d", rc)
			}
			if b := r4Body(t, dbPath, id); r5Unfenced(b, "**Assigned-To:**") != 0 {
				t.Fatalf("the cleared field still has a metadata line:\n%s", b)
			}
		}},
		{"block then update --severity", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "the operator decides")
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--severity", "High"}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
			if b := r4Body(t, dbPath, id); r5Unfenced(b, "**Severity:** High") != 1 || r5Unfenced(b, "**Operator-Block-Details:**") != 1 {
				t.Fatalf("the blocked field update lost a line:\n%s", b)
			}
		}},
		{"move to Fixed and back", func(t *testing.T, dbPath, id string) {
			if rc := moveCmd([]string{"--db", dbPath, "--id", id, "--to", "Fixed", "--status", "Completed (→ Fixed.md)",
				"--why", "r5 probe", "--evidence", ev}); rc != exitOK {
				t.Fatalf("move exited %d", rc)
			}
			if rc := moveCmd([]string{"--db", dbPath, "--id", id, "--to", "Issues", "--status", "Queued", "--why", "r5 probe back"}); rc != exitOK {
				t.Fatalf("move back exited %d", rc)
			}
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dbPath := r5RichItem(t, "CON-970")
			c.run(t, dbPath, "CON-970")
			r5Check(t, dbPath, "CON-970", c.name)
		})
	}
}

// Finding 3: ending a block through update --status, reopen or move removes
// the operator_block_details row in the same transaction (as close does), so
// the database already holds what the next md-to-db would leave.
func TestCON456R5_UnblockingWritersRemoveBlockRow(t *testing.T) {
	inc := r4Evidence(t, "incident.txt")
	ev := r4Evidence(t, "ev.txt")
	for _, c := range []struct {
		name string
		run  func(dbPath string) int
	}{
		{"update --status", func(p string) int {
			return updateCmd([]string{"--db", p, "--id", "CON-971", "--status", "In progress"})
		}},
		{"reopen", func(p string) int {
			return reopenCmd([]string{"--db", p, "--id", "CON-971", "--why", "test-failed", "--who", "AI",
				"--when", "2026-11-17", "--incident", inc})
		}},
		{"move", func(p string) int {
			return moveCmd([]string{"--db", p, "--id", "CON-971", "--to", "Fixed", "--status", "Completed (→ Fixed.md)",
				"--why", "r5 probe", "--evidence", ev})
		}},
	} {
		t.Run(c.name, func(t *testing.T) {
			dbPath := newTestDB(t)
			g456Add(t, dbPath, "CON-971", "unblock row probe", "Task", "Low")
			r5Block(t, dbPath, "CON-971", "the operator decides")
			if rc := c.run(dbPath); rc != exitOK {
				t.Fatalf("%s exited %d", c.name, rc)
			}
			const q = `SELECT COUNT(*) FROM operator_block_details WHERE atm_id='CON-971'`
			if got := g456Query(t, dbPath, q); got != "0" {
				t.Fatalf("%s left %s operator_block_details rows on a %s item", c.name, got,
					g456Query(t, dbPath, `SELECT status FROM items WHERE atm_id='CON-971'`))
			}
			body := r4Body(t, dbPath, "CON-971")
			if strings.Contains(body, "**Operator-Block-Details") {
				t.Fatalf("%s kept a stale block record in the body of a non-blocked item:\n%s", c.name, body)
			}
			if h := g456Query(t, dbPath, `SELECT COUNT(*) FROM item_history WHERE atm_id='CON-971' AND reason='operator-block-ended' AND evidence_path LIKE '%the operator decides%'`); h != "1" {
				t.Fatalf("%s: the ended block record is not in item_history (%s rows)", c.name, h)
			}
			rt := r3Cycle(t, dbPath)
			if got := r4Body(t, rt, "CON-971"); got != body {
				t.Fatalf("the body changed on a cycle")
			}
			r4Validate(t, rt)
		})
	}
}

// RM1 input: a blocked item with no Severity line, then update --description.
// The block record must stay and the update must be accepted.
func TestCON456R5_BlockedNoSeverityUpdateDescription(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-972", "no severity probe", "Task", "")
	r5Block(t, dbPath, "CON-972", "the operator decides")
	if b := r4Body(t, dbPath, "CON-972"); strings.Contains(b, "**Severity:**") {
		t.Fatalf("control: the body carries a Severity line:\n%s", b)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-972", "--description", g456Desc + " Edited."}); rc != exitOK {
		t.Fatalf("update --description on a blocked item without a Severity line exited %d", rc)
	}
	b := r4Body(t, dbPath, "CON-972")
	if !strings.Contains(b, "**Operator-Block-Details:** WHAT: the operator decides") || !strings.Contains(b, "Edited.") {
		t.Fatalf("update lost the block record or the new text:\n%s", b)
	}
	rt := r3Cycle(t, dbPath)
	if got := g456Query(t, rt, `SELECT COUNT(*) FROM operator_block_details WHERE atm_id='CON-972'`); got != "1" {
		t.Fatalf("after a cycle %s block rows", got)
	}
	r4Validate(t, rt)
}

// RM6 input: a Bug add whose description carries the legacy template once
// unfenced and once fenced is refused (the fenced copy is text, but the
// unfenced copy is ambiguous with it; nothing is adopted).
func TestCON456R5_LegacyAdoptionMixedFencedRefused(t *testing.T) {
	legacy := r3LegacyRepro + "\n" + r3LegacyInv
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-001", "seed so the database exists", "Task", "Low")
	desc := g456Desc + "\n\n" + legacy + "\n\n```\n" + legacy + "\n```"
	r3Refused(t, dbPath, "a Bug add with the legacy template unfenced and fenced", func() int {
		return addCmd([]string{"--db", dbPath, "--id", "CON-973", "--title", "mixed legacy probe", "--description", desc, "Bug", "Low"})
	})
}

// Finding 5 (M2): a blocked item whose description holds an Unblock-Choices
// line; update --description without it is accepted (the line is description
// text, not the block record), and the stored row is unchanged before and
// after a cycle.
func TestCON456R5_DescriptionChoicesLineIsDescriptionText(t *testing.T) {
	dbPath := newTestDB(t)
	desc := g456Desc + "\n**Unblock-Choices:** [C] a choice quoted in the description · [D] other"
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-974", "--title", "choices probe", "--description", desc, "Task", "Low"}); rc != exitOK {
		t.Fatalf("add exited %d", rc)
	}
	r5Block(t, dbPath, "CON-974", "the operator decides")
	const q = `SELECT what||'|'||why_exhausted_alternatives||'|'||unblock_condition||'|'||COALESCE(who,'')
		FROM operator_block_details WHERE atm_id='CON-974'`
	row := g456Query(t, dbPath, q)
	if row == "" {
		t.Fatal("control: no block row")
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-974", "--description", g456Desc + " Without the choices line."}); rc != exitOK {
		t.Fatalf("update --description exited %d (the removed line was description text)", rc)
	}
	b := r4Body(t, dbPath, "CON-974")
	if strings.Contains(b, "[C] a choice quoted") || !strings.Contains(b, "**Operator-Block-Details:** WHAT: the operator decides") {
		t.Fatalf("unexpected body:\n%s", b)
	}
	if got := g456Query(t, dbPath, q); got != row {
		t.Fatalf("the row changed on the write: %q, want %q", got, row)
	}
	rt := r3Cycle(t, dbPath)
	if got := g456Query(t, rt, q); got != row {
		t.Fatalf("the row changed on a cycle: %q, want %q", got, row)
	}
	r4Validate(t, rt)
}

// Finding 6: block refuses an item at Fixed (Operator-blocked is not a
// terminal status; the item would be an INTEG-03 violation).
func TestCON456R5_BlockAtFixedRefused(t *testing.T) {
	dbPath, _ := r3ObsoleteItem(t)
	r3Refused(t, dbPath, "block --location Fixed", func() int {
		return blockCmd([]string{"--db", dbPath, "--id", "CON-927", "--location", "Fixed", "--details", "d",
			"--why", "w", "--unblock", "[A] a · [B] b", "--who", "o"})
	})
}

// Finding 2, second shape: a closure Evidence line quoted into the description
// then dropped from it stays as the closure's own record.
func TestCON456R5_DescriptionQuoteThenDropKeepsEvidence(t *testing.T) {
	dbPath, ev := r3ObsoleteItem(t)
	var rec string
	for _, ln := range strings.Split(r4Body(t, dbPath, "CON-927"), "\n") {
		if strings.HasPrefix(ln, "**Evidence:**") {
			rec = ln
		}
	}
	if rec == "" {
		t.Fatal("control: no evidence line")
	}
	for _, d := range []string{g456Desc + "\n" + rec, g456Desc + " Edited twice."} {
		if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-927", "--location", "Fixed", "--description", d}); rc != exitOK {
			t.Fatalf("update exited %d", rc)
		}
	}
	b := r4Body(t, dbPath, "CON-927")
	if r5Unfenced(b, "**Evidence:** "+ev) != 1 {
		t.Fatalf("the closure evidence line was lost or duplicated:\n%s", b)
	}
	r4Validate(t, r3Cycle(t, dbPath))
}
