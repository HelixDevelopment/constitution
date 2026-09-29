// closure_evidence_terminal_types_test.go — §11.4.209 Round-2 review
// MINOR-obs-3 remedy for the `unresolvableClosureEvidence` guard (sync.go).
//
// FORENSIC ANCHOR (Round-2 review, `.superpowers/sdd/task-review-round2-
// fab6707-report.md`, reviewer-authored adversarial mutation #4): commit
// `ce1946f`'s paired §1.1 mutation only proves the ENTIRE
// `AND h.event_type IN ('Fixed', 'Implemented', 'Completed', 'Obsolete')`
// clause is load-bearing (strip the whole clause → the existing
// TestClosureEvidence_UpdatedEventOnClosedItem_UnresolvablePath_NoViolation
// regresses). It does NOT prove each of the FOUR individual terminal values
// inside that tuple is load-bearing. A future edit that silently NARROWS the
// tuple — e.g. `AND h.event_type IN ('Completed')` — would leave that
// existing test GREEN (it only exercises an `Updated` event) while items
// closed with `Fixed` / `Implemented` / `Obsolete` silently escape
// evidence-path validation: exactly the §11.4.226(2) "class proven by a
// LABEL, not by machine fields" bluff the guard exists to prevent, reopened
// through a narrower door.
//
// This file closes that gap with POSITIVE-SIDE coverage: for EACH of the
// four terminal event types, seed a closure whose evidence_path is
// UNRESOLVABLE and assert the guard reports it. Every sub-test independently
// proves its own event_type is checked — narrowing the tuple to any proper
// subset breaks at least one of these four sub-tests, closing the 4-way
// partial-narrowing hole the existing single-event-type test cannot see.
//
// §1.1 PAIRED MUTATION (verified live in this session, §11.4.115(F)
// polarity): narrow sync.go's `unresolvableClosureEvidence` query clause from
//
//	AND h.event_type IN ('Fixed', 'Implemented', 'Completed', 'Obsolete')
//
// to
//
//	AND h.event_type IN ('Completed')
//
// and re-run `go test -run TestClosureEvidence_EveryTerminalEventType
// ./cmd/workable-items/`: the Fixed/Implemented/Obsolete sub-tests FAIL
// (guard reports 0 violations instead of 1 for each), the Completed sub-test
// still PASSes — proving the narrowing is caught by exactly the sub-tests it
// should break, and none of the others. Restoring the real four-value tuple
// makes all four sub-tests GREEN again.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// seedClosedWithEvidenceAndStatus is seedClosedWithEvidence (see
// validate_evidence_test.go) generalised over the close --status keyword, so
// every one of the four terminal event types (Fixed/Implemented/Completed/
// Obsolete) can be exercised through the REAL close subcommand — never a
// hand-written INSERT for the closure row itself.
func seedClosedWithEvidenceAndStatus(t *testing.T, id, status, evidence string) string {
	t.Helper()
	dbPath := newTestDB(t)
	// BOB-240 §11.4.33 Type↔Status guard reconciliation: this fixture
	// independently exercises ALL FOUR terminal event types BY CONSTRUCTION
	// (the whole point of this file, see the header comment) — a hard-coded
	// Type="Bug" for every case would now be refused by `close` for three of
	// the four (implemented/completed), the exact BOB-077/100/179/226-class
	// mismatch this session's forensic anchor documents. Seeding the Type
	// that §11.4.33 actually maps to each status keyword keeps the closure
	// itself legitimate, so this test continues to isolate ONLY the
	// evidence-resolvability dimension it was written to prove.
	typ := "Bug"
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "implemented":
		typ = "Feature"
	case "completed":
		typ = "Task"
	case "obsolete":
		typ = "Bug" // Obsolete is valid for ANY Type; Bug keeps this fixture minimal.
	}
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "terminal-event-type closure evidence probe item " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		typ, "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	// close --evidence is refused at record-time unless it resolves (HXC-224),
	// so — exactly like seedClosedWithEvidence — close with a REAL artefact
	// first, then rewrite item_history.evidence_path directly to the
	// (possibly-unresolvable) value under test. This reaches the same honest
	// row-shape the detective validator exists to catch: a closure recorded
	// when the artefact was real, whose evidence_path no longer resolves.
	real := filepath.Join(t.TempDir(), "closure-artefact.log")
	if err := os.WriteFile(real, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write seed artefact: %v", err)
	}
	if code := closeCmd([]string{
		"--db", dbPath, "--status", status, "--evidence", real, id,
	}); code != exitOK {
		t.Fatalf("close %s --status %s exited %d, want %d", id, status, code, exitOK)
	}
	if evidence != real {
		mapping, ok := closeStatusMap[strings.ToLower(strings.TrimSpace(status))]
		if !ok {
			t.Fatalf("seedClosedWithEvidenceAndStatus: unknown status keyword %q", status)
		}
		db, err := openDB(dbPath)
		if err != nil {
			t.Fatalf("openDB: %v", err)
		}
		if _, err := db.Exec(
			`UPDATE item_history SET evidence_path=? WHERE atm_id=? AND event_type=?`,
			evidence, id, mapping.event); err != nil {
			db.Close()
			t.Fatalf("rewrite evidence_path: %v", err)
		}
		db.Close()
	}
	return dbPath
}

// TestClosureEvidence_EveryTerminalEventType_UnresolvablePath_Violation is the
// MINOR-obs-3 positive-side 4-way narrowing-coverage test: EVERY terminal
// event_type in the §11.4.33 closed set (Fixed/Implemented/Completed/
// Obsolete) MUST independently trigger the guard when its OWN closure's
// evidence_path is unresolvable — not just whichever one value a narrower
// clause happens to keep.
func TestClosureEvidence_EveryTerminalEventType_UnresolvablePath_Violation(t *testing.T) {
	cases := []struct {
		name      string
		closeFlag string // close --status keyword
		eventType string // the item_history.event_type this closure records
		atmID     string
	}{
		{"Fixed", "fixed", "Fixed", "WIT-710"},
		{"Implemented", "implemented", "Implemented", "WIT-711"},
		{"Completed", "completed", "Completed", "WIT-712"},
		{"Obsolete", "obsolete", "Obsolete", "WIT-713"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			missing := filepath.Join(t.TempDir(), "docs", "qa", "never-committed-"+c.name, "capture.log")

			dbPath := seedClosedWithEvidenceAndStatus(t, c.atmID, c.closeFlag, missing)

			got := findingsFor(t, dbPath)
			if len(got) != 1 {
				t.Fatalf("guard reported %d violation(s) for an UNRESOLVABLE %s-event closure evidence_path, want exactly 1 (narrowing the closureEvents tuple would silently drop this event_type): %v",
					len(got), c.eventType, got)
			}
			msg := got[0]
			if !strings.Contains(msg, c.atmID) {
				t.Errorf("violation does not name the offending item: %s", msg)
			}
			if !strings.Contains(msg, "well-formed path, but nothing exists there") {
				t.Errorf("violation does not carry the missing-file sub-class wording: %s", msg)
			}
			if code := validateCmd([]string{"--db", dbPath}); code == exitOK {
				t.Fatalf("validate exited %d (OK) on a %s closure with an unresolvable evidence_path — MUST FAIL (§11.4.226 evidence-class-at-closure)", code, c.eventType)
			}
		})
	}
}

// TestClosureEvidence_EveryTerminalEventType_ResolvablePath_NoViolation is the
// negative-control sibling per §11.4.201(1) (a guard that refuses a clean
// state is a FAIL-bluff exactly as a false pass is a PASS-bluff): the SAME
// four terminal event types, but with a RESOLVABLE evidence_path, MUST NOT
// trip the guard. Without this pairing, TestClosureEvidence_
// EveryTerminalEventType_UnresolvablePath_Violation alone could be satisfied
// by an over-broad mutation that flags every closure regardless of whether
// its evidence resolves — a tautology in the opposite direction.
func TestClosureEvidence_EveryTerminalEventType_ResolvablePath_NoViolation(t *testing.T) {
	cases := []struct {
		name      string
		closeFlag string
		atmID     string
	}{
		{"Fixed", "fixed", "WIT-720"},
		{"Implemented", "implemented", "WIT-721"},
		{"Completed", "completed", "WIT-722"},
		{"Obsolete", "obsolete", "WIT-723"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			evidence := filepath.Join(dir, "capture.log")
			if err := os.WriteFile(evidence, []byte("captured runtime evidence\n"), 0o644); err != nil {
				t.Fatalf("write evidence: %v", err)
			}

			dbPath := seedClosedWithEvidenceAndStatus(t, c.atmID, c.closeFlag, evidence)

			if got := findingsFor(t, dbPath); len(got) != 0 {
				t.Fatalf("guard reported %d violation(s) for a RESOLVABLE %s-event closure evidence_path (false positive, §11.4.201(1)): %v", len(got), c.name, got)
			}
			if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
				t.Fatalf("validate exited %d on a %s closure with resolvable evidence (expected OK)", code, c.name)
			}
		})
	}
}
