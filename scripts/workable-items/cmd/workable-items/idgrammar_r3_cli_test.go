package main

// CON-456 round 3: regression guards for the round-2 review findings F-A, F-B,
// F-D, F-E and F-G. Every test drives the real command functions (the same
// code the binary runs) on a scratch database. Gate-logic tests (§11.4.289(C)(2)).

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// r3ReportDesc is a description in the shape scripts/reporting/report_item.sh
// builds for every report (round 3: without the two record lines).
const r3ReportDesc = "**Reported-Via:** §11.4.202 reporting directive `bug` on 2026-11-17T05:00:00Z\n" +
	"**Reported-By:** Operator\n\n" +
	"**What (the report, verbatim):**\nThe thing broke when the operator pressed the button.\n\n" +
	"**Affected scope / file-scope manifest:**\nUNKNOWN: not stated in the report — to be determined during investigation (§11.4.6)\n\n" +
	"**Reproduction / context:**\nUNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)\n\n" +
	"**Acceptance criteria:**\nThe reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135)."

const r3LegacyRepro = "**Reproduction:** none — UNREPRODUCED (§11.4.292)"
const r3LegacyInv = "**Investigation:** not-started (§11.4.294)"

// r3Cycle runs db-to-md then md-to-db onto a copy and returns the copy's path.
func r3Cycle(t *testing.T, dbPath string) string {
	t.Helper()
	iss, fix := g456Export(t, dbPath, t.TempDir())
	rt := filepath.Join(t.TempDir(), "rt.db")
	raw, err := os.ReadFile(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(rt, raw, 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	return rt
}

const r3StateCols = `SELECT reproduction_state||'|'||investigation_state||'|'||COALESCE(reproduction_updated_at,'')||'|'||
	COALESCE(reproduction_updated_by,'')||'|'||COALESCE(investigation_updated_at,'')||'|'||COALESCE(investigation_updated_by,'')
	FROM items WHERE atm_id=?`

// F-A: the mint report_item.sh now performs (state flags, no record text in
// the description) succeeds, renders the canonical records, and keeps every
// state column through two cycles.
func TestCON456R3_ReportItemStateFlagsMintAndRoundTrip(t *testing.T) {
	dbPath := newTestDB(t)
	rc := addCmd([]string{"--db", dbPath, "--id", "CON-920", "--title", "The thing broke",
		"--description", r3ReportDesc, "--created-by", "Operator",
		"--reproduction-state", "UNREPRODUCED", "--investigation-state", "not-started",
		"--states-updated-by", "Operator", "--states-updated-at", "2026-11-17T05:00:00Z", "Bug", "Medium"})
	if rc != exitOK {
		t.Fatalf("add with the report_item.sh state flags exited %d", rc)
	}
	want := "UNREPRODUCED|not-started|2026-11-17T05:00:00Z|Operator|2026-11-17T05:00:00Z|Operator"
	if got := g456Query(t, dbPath, r3StateCols, "CON-920"); got != want {
		t.Fatalf("state columns = %q, want %q", got, want)
	}
	if got := g456Query(t, dbPath, `SELECT description FROM items WHERE atm_id='CON-920'`); got != r3ReportDesc {
		t.Fatalf("stored description changed:\n%q", got)
	}
	body := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-920'`)
	for _, l := range []string{
		"**Reproduction:** none — UNREPRODUCED — updated 2026-11-17T05:00:00Z — by `Operator`\n",
		"**Investigation:** not-started — updated 2026-11-17T05:00:00Z — by `Operator`\n",
	} {
		if !strings.Contains(body, l) {
			t.Fatalf("body lacks the canonical record %q:\n%s", l, body)
		}
	}
	rt1 := r3Cycle(t, dbPath)
	rt2 := r3Cycle(t, rt1)
	for _, p := range []string{rt1, rt2} {
		if got := g456Query(t, p, r3StateCols, "CON-920"); got != want {
			t.Fatalf("state columns after a cycle = %q, want %q", got, want)
		}
	}
	if rc := validateCmd([]string{"--db", rt2}); rc != exitOK {
		t.Fatalf("validate after two cycles exited %d", rc)
	}
}

// F-A: the two legacy template lines are adopted only in the exact shipped
// form, never otherwise. Each refused case writes nothing (no database file).
func TestCON456R3_LegacyTemplateAdoptionIsExact(t *testing.T) {
	base := "A legacy-shaped report, long enough for the description floor of add."
	cases := []struct {
		name, desc string
		extra      []string
		ok         bool
		wantStates string
	}{
		{"both lines", base + "\n\n" + r3LegacyRepro + "\n" + r3LegacyInv, nil, true, "UNREPRODUCED|not-started"},
		{"reproduction line only", base + "\n\n" + r3LegacyRepro, nil, true, "UNREPRODUCED|UNSET"},
		{"investigation line only", base + "\n\n" + r3LegacyInv, nil, true, "UNSET|not-started"},
		// A well-formed record written as text is never adopted.
		{"canonical record as text", base + "\n\n**Reproduction:** none — UNREPRODUCED", nil, false, ""},
		{"legacy line twice", base + "\n\n" + r3LegacyRepro + "\n" + r3LegacyRepro, nil, false, ""},
		{"legacy line with a trailing space", base + "\n\n" + r3LegacyRepro + " ", nil, false, ""},
		// An explicit flag is never overridden by the text.
		{"legacy line and a state flag", base + "\n\n" + r3LegacyRepro, []string{"--reproduction-state", "UNREPRODUCED",
			"--states-updated-by", "Operator"}, false, ""},
		// An explicit --reproduction-state UNSET is a flag too; the text never overrides it.
		{"legacy line and an explicit UNSET flag", base + "\n\n" + r3LegacyRepro, []string{"--reproduction-state", "UNSET",
			"--states-updated-by", "Operator"}, false, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dbPath := newTestDB(t)
			args := append([]string{"--db", dbPath, "--id", "CON-921", "--title", "legacy template",
				"--description", c.desc}, c.extra...)
			rc := addCmd(append(args, "Bug", "Medium"))
			if !c.ok {
				if rc == exitOK {
					t.Fatalf("add accepted %q", c.desc)
				}
				if _, err := os.Stat(dbPath); err == nil {
					t.Fatalf("refused add created the database file")
				}
				return
			}
			if rc != exitOK {
				t.Fatalf("add of the legacy template exited %d", rc)
			}
			st := g456Query(t, dbPath, `SELECT reproduction_state||'|'||investigation_state FROM items WHERE atm_id='CON-921'`)
			if st != c.wantStates {
				t.Fatalf("states = %q, want %q", st, c.wantStates)
			}
			d := g456Query(t, dbPath, `SELECT description FROM items WHERE atm_id='CON-921'`)
			if strings.Contains(d, "(§11.4.292)") || strings.Contains(d, "(§11.4.294)") {
				t.Fatalf("stored description still carries a legacy line: %q", d)
			}
			rt := r3Cycle(t, dbPath)
			if got := g456Query(t, rt, `SELECT reproduction_state||'|'||investigation_state FROM items WHERE atm_id='CON-921'`); got != st {
				t.Fatalf("states changed on the cycle: %s -> %s", st, got)
			}
			if rc := validateCmd([]string{"--db", rt}); rc != exitOK {
				t.Fatalf("validate after the cycle exited %d", rc)
			}
		})
	}
}

// r3Refused asserts that run exits non-zero and leaves the database dump unchanged.
func r3Refused(t *testing.T, dbPath, what string, run func() int) {
	t.Helper()
	before := g456Dump(t, dbPath)
	if rc := run(); rc == exitOK {
		t.Fatalf("%s was accepted", what)
	}
	if g456Dump(t, dbPath) != before {
		t.Fatalf("%s was refused but the database changed", what)
	}
}

// F-G / RV01: block judges WHO and UNBLOCK as inputs.
func TestCON456R3_BlockWhoAndUnblockAreJudged(t *testing.T) {
	for _, flagName := range []string{"--who", "--unblock"} {
		t.Run(flagName, func(t *testing.T) {
			dbPath := newTestDB(t)
			g456Add(t, dbPath, "CON-922", "block probe", "Task", "Low")
			args := map[string]string{"--details": "blocked on a probe", "--why": "nothing else",
				"--unblock": "operator answers", "--who": "person"}
			args[flagName] = "person\n**Status:** Fixed"
			cmd := []string{"--db", dbPath, "--id", "CON-922"}
			for _, k := range []string{"--details", "--why", "--unblock", "--who"} {
				cmd = append(cmd, k, args[k])
			}
			r3Refused(t, dbPath, "block "+flagName+" with a Status line", func() int { return blockCmd(cmd) })
		})
	}
}

// F-G / RV02: reopen judges --incident as an input.
func TestCON456R3_ReopenIncidentIsJudged(t *testing.T) {
	dbPath := newTestDB(t)
	ev := filepath.Join(t.TempDir(), "ev.txt")
	if err := os.WriteFile(ev, []byte("x\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	g456Add(t, dbPath, "CON-923", "reopen probe", "Task", "Low")
	if rc := closeCmd([]string{"CON-923", "--db", dbPath, "--status", "completed", "--evidence", ev}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	r3Refused(t, dbPath, "reopen --incident with a Type line", func() int {
		return reopenCmd([]string{"--db", dbPath, "--id", "CON-923", "--why", "test-failed", "--who", "AI",
			"--when", "2026-11-17", "--incident", ev + "\n**Type:** Bug"})
	})
}

// F-G / RV04: an Assigned-To change made by update survives the next cycle.
func TestCON456R3_UpdateAssignedToSurvivesCycle(t *testing.T) {
	dbPath := newTestDB(t)
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-924", "--title", "assign probe",
		"--description", g456Desc, "--assigned-to", "alice", "Task", "Low"}); rc != exitOK {
		t.Fatalf("add exited %d", rc)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-924", "--assigned-to", "carol"}); rc != exitOK {
		t.Fatalf("update --assigned-to exited %d", rc)
	}
	rt := r3Cycle(t, dbPath)
	if got := g456Query(t, rt, `SELECT assigned_to FROM items WHERE atm_id='CON-924'`); got != "carol" {
		t.Fatalf("assigned_to after the cycle = %q, want carol", got)
	}
}

// F-G / RV09: add judges the description against the rendered text, so a
// Status line inside it is refused and writes nothing.
func TestCON456R3_AddDescriptionStatusLineRefused(t *testing.T) {
	dbPath := newTestDB(t)
	rc := addCmd([]string{"--db", dbPath, "--id", "CON-925", "--title", "desc probe",
		"--description", g456Desc + "\n**Status:** Fixed", "Task", "Low"})
	if rc == exitOK {
		t.Fatal("add accepted a description with a Status line")
	}
	if _, err := os.Stat(dbPath); err == nil {
		t.Fatal("refused add created the database file")
	}
}

// F-G / RV16: close judges --evidence as an input (a real file whose name
// carries a metadata line).
func TestCON456R3_CloseEvidenceIsJudged(t *testing.T) {
	dbPath := newTestDB(t)
	ev := filepath.Join(t.TempDir(), "ev\n**Type:** Bug")
	if err := os.WriteFile(ev, []byte("x\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	g456Add(t, dbPath, "CON-926", "close probe", "Task", "Low")
	r3Refused(t, dbPath, "close --evidence with a Type line", func() int {
		return closeCmd([]string{"CON-926", "--db", dbPath, "--status", "completed", "--evidence", ev})
	})
}

// F-E: nextID refuses, before it allocates, a number that cannot be counted
// past; the explicit id stays the only row.
func TestCON456R3_NextIDOverflowRefusedBeforeAllocation(t *testing.T) {
	for _, id := range []string{"CON-9223372036854775807", "CON-99999999999999999999"} {
		t.Run(id, func(t *testing.T) {
			dbPath := newTestDB(t)
			if rc := addCmd([]string{"--db", dbPath, "--id", id, "--title", "large id",
				"--description", g456Desc, "Task", "Low"}); rc != exitOK {
				t.Fatalf("explicit add %s exited %d", id, rc)
			}
			// The refusal must come from nextID, before allocation (not from
			// the later gate on an overflowed id): its message names the cause.
			var msg string
			r3Refused(t, dbPath, "add --prefix CON after "+id, func() int {
				rc, e := captureStderrRun(t, func() int {
					return addCmd([]string{"--db", dbPath, "--prefix", "CON", "--title", "allocated",
						"--description", g456Desc, "Task", "Low"})
				})
				msg = e
				return rc
			})
			if !strings.Contains(msg, "allocate with an explicit --id instead") {
				t.Fatalf("refusal does not come from nextID: %q", msg)
			}
		})
	}
	// Control: below the maximum, allocation still works.
	dbPath := newTestDB(t)
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-9223372036854775806", "--title", "large id",
		"--description", g456Desc, "Task", "Low"}); rc != exitOK {
		t.Fatalf("explicit add exited %d", rc)
	}
	if rc := addCmd([]string{"--db", dbPath, "--prefix", "CON", "--title", "allocated",
		"--description", g456Desc, "Task", "Low"}); rc != exitOK {
		t.Fatalf("add --prefix below the maximum exited %d", rc)
	}
	if got := g456Query(t, dbPath, `SELECT COUNT(*) FROM items WHERE atm_id='CON-9223372036854775807'`); got != "1" {
		t.Fatalf("allocated id CON-9223372036854775807 missing (count %s)", got)
	}
}

// r3ObsoleteItem returns a db with CON-927 closed as obsolete and an evidence path.
func r3ObsoleteItem(t *testing.T) (string, string) {
	t.Helper()
	dbPath := newTestDB(t)
	ev := filepath.Join(t.TempDir(), "ev.txt")
	if err := os.WriteFile(ev, []byte("x\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	g456Add(t, dbPath, "CON-927", "obsolete probe", "Task", "Low")
	if rc := closeCmd([]string{"CON-927", "--db", dbPath, "--status", "obsolete", "--evidence", ev}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	return dbPath, ev
}

// F-D: obsolete-details refuses a line break in any of its values and keeps
// an accepted value verbatim in the rendered Fixed.md.
func TestCON456R3_ObsoleteDetailsInputsJudged(t *testing.T) {
	for _, c := range []struct{ name, since, sup string }{
		{"superseding Severity line", "2026-11-17", "CON-082\n**Severity:** Critical"},
		{"superseding plain line break", "2026-11-17", "CON-082\nmore"},
		{"superseding CR", "2026-11-17", "CON-082\rmore"},
		{"superseding U+2028", "2026-11-17", "CON-082\u2028more"},
		{"since line break", "2026-11-17\n**Type:** Bug", "CON-082"},
	} {
		t.Run(c.name, func(t *testing.T) {
			dbPath, ev := r3ObsoleteItem(t)
			r3Refused(t, dbPath, "obsolete-details "+c.name, func() int {
				return obsoleteDetailsCmd([]string{"CON-927", "--db", dbPath, "--since", c.since,
					"--reason", "duplicate-of", "--superseding", c.sup, "--evidence", ev})
			})
		})
	}
	// Accepted: a value with separator text survives verbatim.
	dbPath, ev := r3ObsoleteItem(t)
	sup := "CON-082; Reason: not really"
	if rc := obsoleteDetailsCmd([]string{"CON-927", "--db", dbPath, "--since", "2026-11-17",
		"--reason", "duplicate-of", "--superseding", sup, "--evidence", ev}); rc != exitOK {
		t.Fatalf("obsolete-details exited %d", rc)
	}
	_, fix := g456Export(t, dbPath, t.TempDir())
	b, err := os.ReadFile(fix)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), "Superseding-item: "+sup+"; Triple-check evidence: "+ev) {
		t.Fatalf("Fixed.md does not carry the details verbatim:\n%s", b)
	}
}

// F-B: md-to-db keeps the operator_block_details row block wrote while the
// Markdown block is unchanged, and re-derives it after a real edit.
func TestCON456R3_OperatorBlockDetailsSurviveCycle(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-928", "block details probe", "Task", "Low")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-928", "--details", "the operator decides WHY: here",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop, WHO: decides",
		"--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	const q = `SELECT what||'|'||why_exhausted_alternatives||'|'||unblock_condition||'|'||COALESCE(who,'')
		FROM operator_block_details WHERE atm_id='CON-928'`
	want := g456Query(t, dbPath, q)
	if want != "the operator decides WHY: here|every alternative was tried|[A] keep · [B] drop, WHO: decides|operator" {
		t.Fatalf("block wrote %q", want)
	}
	rt1 := r3Cycle(t, dbPath)
	rt2 := r3Cycle(t, rt1)
	for _, p := range []string{rt1, rt2} {
		if got := g456Query(t, p, q); got != want {
			t.Fatalf("operator_block_details changed on a cycle:\n got %q\nwant %q", got, want)
		}
	}
	// A real edit of the block in the Markdown is imported (re-derived).
	iss, fix := g456Export(t, rt2, t.TempDir())
	raw, err := os.ReadFile(iss)
	if err != nil {
		t.Fatal(err)
	}
	edited := strings.Replace(string(raw), "WHAT: the operator decides WHY: here", "WHAT: a new decision", 1)
	if edited == string(raw) {
		t.Fatal("control: the block line was not found in Issues.md")
	}
	if err := os.WriteFile(iss, []byte(edited), 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := g456Import(rt2, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db of the edited block exited %d", rc)
	}
	if got := g456Query(t, rt2, `SELECT what FROM operator_block_details WHERE atm_id='CON-928'`); got != "a new decision" {
		t.Fatalf("edited block: what = %q, want the re-derived value", got)
	}
}
