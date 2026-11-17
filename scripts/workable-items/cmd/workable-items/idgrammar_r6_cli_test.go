package main

// CON-456 round 6 (structural). Review r5 finding F1 and follow-ups M1, M2.
//
// F1: an item's own Status / Type / Reproduction / Investigation /
// Unblock-Choices / Operator-Block-Details line is defined ONCE (ownlines.go):
// a line of the item's own region that is not inside a fenced code block. The
// parser, the status writers, the metadata-block finder and the owned-line gate
// all read that one definition. Before round 6 the parser, canonicalizeBody
// StatusLine and the gate took the LAST Status line of the region fences
// included, while metaBlockOf took the FIRST, so a status writer rewrote a
// fenced `**Status:**` example and left the item's own line stale while
// validate exited 0 (reproduction: ev/repro_F1_fenced_status.sh of the r5
// review, kept as a Go test here, section 11.4.292 RED first).
//
// M1 adopts the reviewer mutants RV4, RV6, RV9 and RV10 as failing-first
// tests (section 11.4.276(D)); M2 pins CRLF preservation.

import (
	"os"
	"strings"
	"testing"
)

// r6Members are the owned-looking lines a fenced block can quote. Each is a
// member of the class "a line the engine reads or writes as the item's own".
var r6Members = []struct{ name, line string }{
	{"Status", "**Status:** Fixed (→ Fixed.md)"},
	{"StatusQueued", "**Status:** Queued"},
	{"Type", "**Type:** Bug"},
	{"Reproduction", reproLinePrefix + " none" + stateSep + labelUnreproduced},
	{"Investigation", invLinePrefix + " not-started"},
	{"UnblockChoices", "**Unblock-Choices:** [Z] fenced · [Y] quote"},
	{"OperatorBlockDetails", "**Operator-Block-Details:** WHAT: fenced quote WHY: none UNBLOCK: [Z] x WHO: nobody"},
	{"Severity", "**Severity:** Critical"},
}

// r6FencedItem adds id (a Task, severity Low) and imports an Issues.md whose
// description is followed by one fenced block holding lines.
func r6FencedItem(t *testing.T, id string, lines ...string) (dbPath, fenced string) {
	t.Helper()
	dbPath = newTestDB(t)
	g456Add(t, dbPath, id, "r6 fence probe", "Task", "Low")
	dir := t.TempDir()
	iss, fix := g456Export(t, dbPath, dir)
	raw, err := os.ReadFile(iss)
	if err != nil {
		t.Fatal(err)
	}
	fenced = "Example of the format:\n\n```\n" + strings.Join(lines, "\n") + "\n```\n"
	s := strings.Replace(string(raw), g456Desc+"\n", g456Desc+"\n\n"+fenced, 1)
	if s == string(raw) {
		t.Fatal("control: could not place the fenced block")
	}
	if err := os.WriteFile(iss, []byte(s), 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := g456Import(dbPath, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	if b := r4Body(t, dbPath, id); !strings.Contains(b, fenced) {
		t.Fatalf("control: the imported body lacks the fenced block:\n%s", b)
	}
	return dbPath, fenced
}

// r6OwnStatus returns the values of the unfenced `**Status:**` lines.
func r6OwnStatus(body string) []string {
	var out []string
	in := false
	for _, ln := range strings.Split(body, "\n") {
		if isFenceLine(ln) {
			in = !in
			continue
		}
		if !in && strings.HasPrefix(ln, "**Status:**") {
			out = append(out, strings.TrimSpace(strings.TrimPrefix(ln, "**Status:**")))
		}
	}
	return out
}

// r6Check asserts the fenced block is byte-identical, the item's own Status
// line is the one that reads the column, the Type and the state columns were
// not read from the fence, and a cycle and validate hold.
func r6Check(t *testing.T, dbPath, id, fenced, what string) {
	t.Helper()
	body := r4Body(t, dbPath, id)
	if !strings.Contains(body, fenced) {
		t.Errorf("%s changed the fenced block:\n%s", what, body)
	}
	col := g456Query(t, dbPath, `SELECT status FROM items WHERE atm_id=?`, id)
	own := r6OwnStatus(body)
	if len(own) != 1 || normalizeStatus(own[0]) != col {
		t.Errorf("%s: column status %q, unfenced Status lines %q:\n%s", what, col, own, body)
	}
	if g := g456Query(t, dbPath, `SELECT type FROM items WHERE atm_id=?`, id); g != "Task" {
		t.Errorf("%s: the Type column read %q (a fenced Type line is text)", what, g)
	}
	for _, c := range []string{"reproduction_state", "investigation_state"} {
		if g := g456Query(t, dbPath, `SELECT `+c+` FROM items WHERE atm_id=?`, id); g != "UNSET" {
			t.Errorf("%s: %s = %q (a fenced record is text)", what, c, g)
		}
	}
	rt := r3Cycle(t, dbPath)
	if got := r4Body(t, rt, id); got != body {
		t.Errorf("%s: the body changed on a cycle:\n got %q\nwant %q", what, got, body)
	}
	r4Validate(t, rt)
	r4Validate(t, dbPath)
}

// F1 (class): the parser takes none of the owned-looking lines of a fence.
func TestCON456R6_FencedOwnedLookingLinesAreTextToTheParser(t *testing.T) {
	for _, m := range r6Members {
		t.Run(m.name, func(t *testing.T) {
			body := "## CON-1 — probe item with a long enough title for the floor\n\n**Status:** Queued\n**Type:** Task\n\nprose\n\n```\n" + m.line + "\n```\n"
			it := buildItem("CON-1", "probe item with a long enough title for the floor", body, "Issues")
			if it.Status != "Queued" || it.Type != "Task" || it.Severity != "" {
				t.Errorf("fenced %s was read: status %q type %q severity %q", m.name, it.Status, it.Type, it.Severity)
			}
			if it.States.ReproState != stateUnset || it.States.InvState != stateUnset {
				t.Errorf("fenced %s was read as a state record: %+v", m.name, it.States)
			}
			if _, ok := lastBodyStatus(body); !ok {
				t.Error("control: the unfenced Status line is not seen")
			}
			if _, _, ok := operatorBlockParts(body); ok {
				t.Errorf("fenced %s was read as the block record", m.name)
			}
			if _, c, ok := operatorBlockParts(body + "\n**Operator-Block-Details:** WHAT: w\n"); !ok || strings.Contains(c, "Z") {
				t.Errorf("fenced %s was read as the choices (ok=%v choices=%q)", m.name, ok, c)
			}
		})
	}
}

// F1 (reviewer repro, class): every status writer leaves a fenced owned-
// looking block byte-identical and writes the item's own Status line.
func TestCON456R6_StatusWritersKeepFencedBlockAndWriteOwnLine(t *testing.T) {
	ev := r4Evidence(t, "ev.txt")
	inc := r4Evidence(t, "incident.txt")
	all := []string{}
	for _, m := range r6Members {
		all = append(all, m.line)
	}
	writers := []struct {
		name string
		run  func(t *testing.T, dbPath, id string)
	}{
		{"block", func(t *testing.T, dbPath, id string) { r5Block(t, dbPath, id, "the operator decides") }},
		{"update --status", func(t *testing.T, dbPath, id string) {
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--status", "In progress"}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
		}},
		{"block then update --status", func(t *testing.T, dbPath, id string) {
			r5Block(t, dbPath, id, "the operator decides")
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--status", "In progress"}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
		}},
		{"update --description", func(t *testing.T, dbPath, id string) {
			if rc := updateCmd([]string{"--db", dbPath, "--id", id, "--description", g456Desc + " Replaced in round six."}); rc != exitOK {
				t.Fatalf("update exited %d", rc)
			}
		}},
		{"close", func(t *testing.T, dbPath, id string) {
			if rc := closeCmd([]string{id, "--db", dbPath, "--status", "completed", "--evidence", ev}); rc != exitOK {
				t.Fatalf("close exited %d", rc)
			}
		}},
		{"close obsolete", func(t *testing.T, dbPath, id string) {
			if rc := closeCmd([]string{id, "--db", dbPath, "--status", "obsolete", "--evidence", ev}); rc != exitOK {
				t.Fatalf("close exited %d", rc)
			}
		}},
		{"close then reopen", func(t *testing.T, dbPath, id string) {
			if rc := closeCmd([]string{id, "--db", dbPath, "--status", "completed", "--evidence", ev}); rc != exitOK {
				t.Fatalf("close exited %d", rc)
			}
			if rc := reopenCmd([]string{"--db", dbPath, "--id", id, "--why", "test-failed", "--who", "AI",
				"--when", "2026-11-17", "--incident", inc}); rc != exitOK {
				t.Fatalf("reopen exited %d", rc)
			}
		}},
		{"move to Fixed", func(t *testing.T, dbPath, id string) {
			if rc := moveCmd([]string{"--db", dbPath, "--id", id, "--to", "Fixed", "--status", "Completed (→ Fixed.md)",
				"--why", "r6 probe", "--evidence", ev}); rc != exitOK {
				t.Fatalf("move exited %d", rc)
			}
		}},
	}
	sets := []struct {
		name  string
		lines []string
	}{{"all members", all}}
	for _, m := range r6Members {
		sets = append(sets, struct {
			name  string
			lines []string
		}{m.name, []string{m.line}})
	}
	for _, s := range sets {
		for _, w := range writers {
			t.Run(s.name+"/"+w.name, func(t *testing.T) {
				dbPath, fenced := r6FencedItem(t, "CON-971", s.lines...)
				w.run(t, dbPath, "CON-971")
				r6Check(t, dbPath, "CON-971", fenced, w.name)
			})
		}
	}
}

// F1: a fenced `### ` line does not end the item's own region.
func TestCON456R6_FencedSubHeadingDoesNotEndOwnRegion(t *testing.T) {
	lines := splitKeepNewlines("## CON-1 — t\n\n**Status:** Queued\n\n```\n### not a heading\n```\n**Severity:** Low\n### real sub\n**Status:** Fixed\n")
	if n := ownMetaRegionLineCount(lines); n != 8 {
		t.Errorf("own region = %d lines, want 8", n)
	}
}

// M1 / RV4: ending... re-blocking drops the old Unblock-Choices record of the
// metadata block (a fresh md-to-db rebuild must not read it).
func TestCON456R6_ReblockDropsOldUnblockChoices(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-972", "r6 reblock probe", "Task", "Low")
	dir := t.TempDir()
	iss, fix := g456Export(t, dbPath, dir)
	raw, err := os.ReadFile(iss)
	if err != nil {
		t.Fatal(err)
	}
	s := strings.Replace(string(raw), "**Type:** Task\n", "**Type:** Task\n**Unblock-Choices:** [A] stale\n", 1)
	if s == string(raw) {
		t.Fatal("control: could not place the stale choices line")
	}
	if err := os.WriteFile(iss, []byte(s), 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := g456Import(dbPath, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-972", "--details", "the operator decides",
		"--why", "every alternative was tried", "--unblock", "[B] new · [C] newer", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	body := r4Body(t, dbPath, "CON-972")
	if strings.Contains(body, "[A] stale") {
		t.Errorf("the old Unblock-Choices record survived the re-block:\n%s", body)
	}
	rt := r3Cycle(t, dbPath)
	if u := g456Query(t, rt, `SELECT unblock_condition FROM operator_block_details WHERE atm_id='CON-972'`); strings.Contains(u, "stale") || !strings.Contains(u, "[B] new") {
		t.Errorf("a fresh rebuild reads unblock %q", u)
	}
}

// M1 / RV6: Obsolete-Details is added at the END of the metadata block.
func TestCON456R6_ObsoleteDetailsGoesAtTheEndOfTheBlock(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Obsolete\n**Type:** Task\n**Severity:** Low\n**Evidence:** /e\n\nprose\n"
	out := setRecord(b, recObsolete, "**Obsolete-Details:** Since: d; Reason: r")
	if !strings.Contains(out, "**Evidence:** /e\n**Obsolete-Details:** Since: d; Reason: r\n\nprose") {
		t.Errorf("the record is not at the end of the block:\n%s", out)
	}
	// Any other record is added right after Type.
	r := setRecord("## CON-1 — t\n\n**Status:** Fixed\n**Type:** Task\n**Severity:** Low\n\nprose\n", recReopened, "**Reopened-Details:** By: AI")
	if !strings.Contains(r, "**Type:** Task\n**Reopened-Details:** By: AI\n**Severity:** Low") {
		t.Errorf("a non-Obsolete record is not after Type:\n%s", r)
	}
}

// M1 / RV9: a replaced description region keeps the missing trailing newline
// of the last line of the body.
func TestCON456R6_ReplaceDescriptionKeepsMissingTrailingNewline(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Queued\n\nold description line"
	out := replaceDescription(b, "old description line", "new description line")
	if out != "## CON-1 — t\n\n**Status:** Queued\n\nnew description line" {
		t.Errorf("the line ending changed:\n%q", out)
	}
	b2 := b + "\n"
	if out := replaceDescription(b2, "old description line", "new description line"); !strings.HasSuffix(out, "line\n") {
		t.Errorf("golden-FALSE: the newline was lost: %q", out)
	}
}

// M1 / RV10: the description region is matched exactly; a line that differs in
// white space is the operator's line, kept, and the new text is inserted.
func TestCON456R6_DescriptionRegionMatchIsExact(t *testing.T) {
	b := "## CON-1 — t\n\n**Status:** Queued\n\nold description line  \n"
	out := replaceDescription(b, "old description line", "new description line")
	if !strings.Contains(out, "old description line  \n") {
		t.Errorf("a line that is not the description was replaced:\n%q", out)
	}
	if !strings.Contains(out, "new description line\n") {
		t.Errorf("the new text was not inserted:\n%q", out)
	}
	if _, _, ok := descriptionRegion(splitKeepNewlines(b), "old description line"); ok {
		t.Error("a white-space-different line matched as the description region")
	}
}

// M2: rewriting an owned line keeps the body's CRLF line endings.
func TestCON456R6_CRLFBodyKeepsLineEndings(t *testing.T) {
	b := "## CON-1 — t\r\n\r\n**Status:** Queued\r\n**Type:** Task\r\n\r\ndescription line\r\n"
	crlf := func(s string) int { return strings.Count(s, "\r\n") }
	if out := canonicalizeBodyStatusLine(b, "In progress"); crlf(out) != crlf(b) || !strings.Contains(out, "**Status:** In progress\r\n") {
		t.Errorf("Status rewrite lost CRs:\n%q", out)
	}
	if out := replaceHeadingTitle(b, "CON-1", "new title"); crlf(out) != crlf(b) || !strings.Contains(out, "## CON-1 — new title\r\n") {
		t.Errorf("heading rewrite lost CRs:\n%q", out)
	}
	if out := setRecord(b, recEvidence, "**Evidence:** /e"); crlf(out) != crlf(b)+1 || strings.Contains(strings.ReplaceAll(out, "\r\n", ""), "\n") {
		t.Errorf("an inserted record has a bare LF:\n%q", out)
	}
	rec := setRecord(b, recEvidence, "**Evidence:** /e")
	if out := setRecord(rec, recEvidence, "**Evidence:** /f"); crlf(out) != crlf(rec) || strings.Contains(strings.ReplaceAll(out, "\r\n", ""), "\n") {
		t.Errorf("a replaced record lost its CR:\n%q", out)
	}
	if out := replaceDescription(b, "description line", "two\nlines"); strings.Contains(strings.ReplaceAll(out, "\r\n", ""), "\n") {
		t.Errorf("a replaced description has a bare LF:\n%q", out)
	}
	if out := setOwnMetaLine(b, "Severity", "Low"); strings.Contains(strings.ReplaceAll(out, "\r\n", ""), "\n") {
		t.Errorf("an inserted meta line has a bare LF:\n%q", out)
	}
	if out := setOwnMetaLine(b, "Type", "Bug"); crlf(out) != crlf(b) || !strings.Contains(out, "**Type:** Bug\r\n") {
		t.Errorf("a replaced meta line lost its CR:\n%q", out)
	}
	if out := setStateLinesForTest(b); strings.Contains(strings.ReplaceAll(out, "\r\n", ""), "\n") {
		t.Errorf("an inserted state record has a bare LF:\n%q", out)
	}
}

func setStateLinesForTest(body string) string {
	return canonicalizeStateLines(body, stateRecord{ReproState: reproUnreproduced, InvState: "not-started"}, "section")
}
