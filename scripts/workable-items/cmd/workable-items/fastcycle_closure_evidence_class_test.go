// fastcycle_closure_evidence_class_test.go -- T087 RED test (SpecKit-004
// "fast-dev-cycles", Phase 5 / User Story 3; plan.md T-D02; contracts
// closure-refusal.md CR-001/CR-002/CR-005; data-model.md 6.1 (E4)/6.3
// ClosureAttempt; FR-010, SC-004).
//
// Task line (tasks.md T087, verbatim): "[P] [US3] [TDD] RED Go test
// `constitution/scripts/workable-items/cmd/workable-items/
// fastcycle_closure_evidence_class_test.go` (an item closed with grep-only
// evidence is accepted today; golden-bad: refused with `missing evidence
// class: runtime`; negative control: a source-layer Task closed on source
// evidence is accepted; E4: closure refused when the registered guard has
// no verdict for the current artifact fingerprint) (plan T-D02; FR-010,
// SC-004)".
//
// Downstream implementation task this RED test gates (NOT implemented
// here -- Producer != Verifier, §11.4.240): T095, "Extend the SOL-01/
// SOL-04 status-custody seam in a new
// constitution/scripts/workable-items/cmd/workable-items/closure_seam.go:
// runtime/user-visible Bug/Feature cannot reach terminal status on source/
// artifact evidence (refusal names the missing class); the registered
// guard must hold a verdict for the current artifact fingerprint (E4);
// until T087 is GREEN".
//
// THE GAP, PROVEN LIVE (TestClosureEvidenceClass_UserVisibleItemClosedOn
// GrepOnlyEvidence_AcceptedToday): today's REAL `close` subcommand (crud.go
// closeCmd) has NO concept whatsoever of a defect's evidence layer, an
// evidence entry's claimed class, or a runtime target fingerprint --
// closing a user-visible-layer item on nothing but a grep transcript
// succeeds silently. This is exactly the §11.4.226 evidence-class-at-
// closure gap contracts/closure-refusal.md CR-001/CR-002 exist to close,
// and (per research.md DEC-19) it is escape mechanism E1 wrong-layer-
// evidence -- the very class T-D01 (T086, already landed) measured as the
// largest single reopen driver in this tracker's own history (R1:25,
// ATM-953's routing-only GREEN).
//
// HONEST SPEC-FIGURE DRIFT, DOCUMENTED PER §11.4.6 (never silently
// resolved -- see the memory-index card "speckit-004-spec-figure-drift-
// phase4.md" for this feature's established pattern of tasks.md
// parentheticals paraphrasing rather than quoting contracts/ verbatim):
// T087's own task line quotes the literal string `missing evidence class:
// runtime`. contracts/closure-refusal.md CR-001 gives a DIFFERENT literal
// for the SAME refusal: `REFUSED(missing: runtime evidence at
// user-visible layer; supplied: <highest class>)`. data-model.md 6.3's
// `decision` field description is generic on the point ("refusal names
// the missing evidence class or artefact"). Neither literal is a
// substring of the other, so this file does NOT pick a side by asserting
// one exact string (that would silently discard whichever source disagrees
// with the choice, and T095's implementer -- reading this file -- would
// have no signal the drift exists at all). Instead every golden-bad/E4
// assertion below checks the INTERSECTION of tokens common to every
// candidate literal ("REFUSED" + "missing" + the specific missing class's
// own name, e.g. "runtime" or "guard"/"fingerprint") -- a decision text
// satisfying T087's literal, CR-001's literal, OR any reasonable
// T095-authored variant in between all pass; a decision that fails to
// name REFUSED, "missing" and the specific gap at all fails regardless of
// exact wording chosen. This is deliberately weaker than picking one
// side's exact string, and deliberately documented as such rather than
// silently narrowed -- reconciling which literal is authoritative is
// T095's own implementation decision, not this RED test's to make.
//
// COMPILE-SAFETY (§11.4.28/§11.4.177's own reuse discipline applied to
// package boundaries, §11.4.240 producer!=verifier): `closure_seam.go`
// (T095) and its `closure-check` subcommand dispatch (main.go, T095) do
// NOT exist yet. This file therefore NEVER references a not-yet-existing
// Go SYMBOL at compile time -- exactly the fastcycle_sibling_search_
// test.go (T088) precedent this file follows verbatim: the future-seam
// bullets build the REAL `workable-items` binary FRESH from the CURRENT
// source tree via `go build` and invoke it as a subprocess with the
// contract's own documented argv shape (contracts/closure-refusal.md
// "Invocations": `$WI closure-check --config <cfg> --item <ItemId> --to
// <Fixed|Implemented|Completed> --attempt <attempt.json> --out
// <decision.json>`). TODAY, main.go's subcommand switch does not
// recognise `closure-check` at all (its `default:` case fires, prints
// "unknown subcommand: closure-check", exits 1 == exitUsage) -- a real,
// live, non-fabricated RED signal that self-flips to exercising the
// genuine seam logic the moment T095 lands, with NO edit to this file.
//
// SHARED-INFRASTRUCTURE REUSE, NOT DUPLICATION (§11.4.124/§11.4.274):
// this file reuses, unmodified, every package-level helper the already-
// landed T088 sibling file (fastcycle_sibling_search_test.go, commit
// 133ef34) and crud.go/close_evidence_recordtime_test.go already provide
// and that are NOT tied to a specific fixture-struct shape: newTestDB,
// addCmd, closeCmd, itemLocation, realEvidenceFile, closeStatusMap,
// exitOK, exitUsage, sharedWorkableItemsBinary, runWorkableItemsBinary,
// workableItemsModuleDir (transitively), decisionOf, containsAll, and the
// sibling file's own siblingSearchArtefactFixture type (needed here
// because this file's E4 fixture is a Bug closure, which independently
// requires a VALID CR-004 sibling-search artefact to isolate the E4/CR-005
// assertion from an unrelated CR-004 refusal -- see the E4 test's own
// doc comment). This file does NOT modify fastcycle_sibling_search_
// test.go to add this file's own regression_guard field to its
// closureAttemptFixture type -- that would edit another task's already-
// landed, reviewed, pushed deliverable merely to save one local struct
// declaration; instead this file declares its OWN, differently-named
// evidenceClassAttemptFixture type (data-model.md 6.3 ClosureAttempt,
// plus the regression_guard field T-D02/CR-005 needs that T-D03's own
// fixture never populates) and its own JSON-marshalling helper.
package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// evidenceClassAttemptFixture mirrors data-model.md 6.3 ClosureAttempt for
// THIS file's own fixtures -- a distinct type from fastcycle_sibling_
// search_test.go's closureAttemptFixture (same shape for the fields both
// files need, PLUS this file's own regression_guard field) so this file
// never edits that already-landed T088 deliverable merely to add one
// field neither T088's own tests populate.
type evidenceClassAttemptFixture struct {
	ItemID          string                        `json:"item_id"`
	TargetStatus    string                        `json:"target_status"`
	DefectLayer     string                        `json:"defect_layer"`
	Evidence        []map[string]interface{}      `json:"evidence"`
	SiblingSearch   *siblingSearchArtefactFixture `json:"sibling_search,omitempty"`
	RegressionGuard string                        `json:"regression_guard,omitempty"`
}

// writeEvidenceClassAttemptJSON marshals an evidenceClassAttemptFixture to
// a fresh temp file and returns its path -- the same shape as the sibling
// file's writeAttemptJSON, parameterised over this file's own fixture
// type.
func writeEvidenceClassAttemptJSON(t *testing.T, attempt evidenceClassAttemptFixture) string {
	t.Helper()
	body, err := json.MarshalIndent(attempt, "", "  ")
	if err != nil {
		t.Fatalf("marshal evidence-class ClosureAttempt fixture: %v", err)
	}
	p := filepath.Join(t.TempDir(), "attempt.json")
	if err := os.WriteFile(p, body, 0o644); err != nil {
		t.Fatalf("write attempt.json: %v", err)
	}
	return p
}

// grepOnlyRuntimeEvidenceFile writes an evidence artefact whose CONTENT is
// a plain grep transcript -- no target fingerprint, no captured device/
// pixel/audio observable, no runtime command trace -- exactly the
// contracts/closure-refusal.md CR-002 anti-echo detection criterion ("no
// target fingerprint field, or the recorded command is a text search over
// the repo"). Used by BOTH the RED baseline test (today's close subcommand
// has zero concept of evidence class and accepts it unconditionally) and
// the golden-bad test (the SAME artefact, claimed "runtime", against the
// future seam) -- deliberately the identical file across both tests per
// plan.md T-D02's own protecting-tests wording, "RED fixture: an item
// closed with grep-only evidence is accepted today; golden-bad: SAME ITEM
// refused ...".
func grepOnlyRuntimeEvidenceFile(t *testing.T) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "grep-transcript.txt")
	body := "$ grep -rn \"routeToSecondary\" device/rockchip/atmosphere/presenter/\n" +
		"device/rockchip/atmosphere/presenter/.../VideoOutputManagerService.kt:142: fun routeToSecondary(surfaceId: Int) {\n" +
		"device/rockchip/atmosphere/presenter/.../VideoOutputManagerService.kt:151:     mirrorLayers.remove(surfaceId)\n"
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatalf("write grep-only evidence transcript: %v", err)
	}
	return p
}

// validSiblingSearchArtefact returns a fully-valid CR-004 SiblingSearch
// Artefact fixture (control needle found, one instance with a legal DEC-20
// disposition) -- used ONLY by this file's E4/CR-005 test to keep that
// assertion isolated from an UNRELATED CR-004 refusal, since T-D02 and
// T-D03 extend the SAME closure_seam.go (plan.md: "T-D03 -- Depends on:
// T-D02 (same seam)") and a Bug closure is independently bound by CR-004
// regardless of whether this file's own CR-005/E4 condition is met.
func validSiblingSearchArtefact() *siblingSearchArtefactFixture {
	return &siblingSearchArtefactFixture{
		ClassStatement:     "a Bug closure whose regression guard has no verdict for the current artifact fingerprint (E4)",
		SearchMethod:       "grep -rln 'guard-not-run' constitution/docs/workable_items.db (no other open item shares this class statement)",
		ControlNeedle:      "fastcycle_closure_evidence_class_test.go:E4-fixture",
		ControlNeedleFound: true,
		InstancesFound: []map[string]string{
			{"location": "this fixture's own item", "disposition": "fixed-here"},
		},
	}
}

// ---------------------------------------------------------------------------
// Bullet 1 (accepted today) -- proven entirely in-process against the REAL,
// EXISTING close subcommand. No subprocess, no compile-safety concern.
// ---------------------------------------------------------------------------

// TestClosureEvidenceClass_UserVisibleItemClosedOnGrepOnlyEvidence_
// AcceptedToday is the T-D02 RED baseline: today's real `close` subcommand
// closes a user-visible-layer Feature to Implemented with nothing but a
// grep-transcript evidence file supplied -- no defect_layer concept, no
// claimed_class concept, no runtime-fingerprint concept exists in closeCmd
// at all. Exactly the CR-001/CR-002 gap (§11.4.226 evidence-class-at-
// closure) T095 (closure_seam.go) exists to close.
func TestClosureEvidenceClass_UserVisibleItemClosedOnGrepOnlyEvidence_AcceptedToday(t *testing.T) {
	dbPath := newTestDB(t)
	const id = "WIT-740"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "user-visible defect closed on grep-only evidence " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Feature", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	evidence := grepOnlyRuntimeEvidenceFile(t)
	if code := closeCmd([]string{
		"--db", dbPath, "--status", "implemented", "--evidence", evidence, id,
	}); code != exitOK {
		t.Fatalf("RED baseline broken: close %s exited %d, want %d (exitOK) -- "+
			"today's close subcommand should accept a user-visible-layer item "+
			"closed on nothing but a grep transcript, since T-D02's evidence-"+
			"class seam has not landed yet", id, code, exitOK)
	}

	status, loc := itemLocation(t, dbPath, id)
	if status != closeStatusMap["implemented"].status || loc != "Fixed" {
		t.Fatalf("close %s reported success but the item's own row is "+
			"inconsistent: status=%q location=%q, want status=%q location=Fixed",
			id, status, loc, closeStatusMap["implemented"].status)
	}

	t.Logf("RED baseline confirmed (§11.4.226 gap, plan.md T-D02): user-"+
		"visible-layer Feature %s closed successfully via the REAL close "+
		"subcommand with nothing but a grep-transcript evidence file -- "+
		"this is exactly what T095 (closure_seam.go extending the status-"+
		"write seam) must refuse once landed", id)
}

// ---------------------------------------------------------------------------
// Bullets 2-4 -- the future `closure-check` seam, exercised ONLY as an
// external subprocess of a binary built fresh from the CURRENT source tree
// (sharedWorkableItemsBinary / runWorkableItemsBinary, reused unmodified
// from fastcycle_sibling_search_test.go). Never a possibly-stale prebuilt
// bin/workable-items -- the BOB-188 lesson: a stale copy can fabricate a
// mismatch (§11.4.6: built, never assumed present).
// ---------------------------------------------------------------------------

// TestClosureEvidenceClass_GoldenBad_UserVisibleItemRefusedOnGrepOnly
// Evidence is CR-001/CR-002's own golden-bad: the SAME grep-only-evidence
// artefact from the RED baseline above, claimed_class "runtime" (the exact
// mislabel CR-002's anti-echo clause exists to catch), against a Feature
// whose defect_layer is "user-visible" -- CR-001: "For user-visible, at
// least one evidence entry must be class runtime proven by machine fields
// ... Otherwise REFUSED(missing: runtime evidence at user-visible layer;
// supplied: <highest class>)". Feature (not Bug) is used deliberately so
// this assertion stays isolated from the UNRELATED CR-004/CR-005 Bug-only
// requirements the same seam also enforces (see the file header's Bug-vs-
// Feature reasoning). TODAY: closure-check is not a recognised subcommand
// at all (main.go's `default:` case fires), so no decision.json is EVER
// written -- decisionOf() correctly reports ("", false) and this test
// fails loudly, naming the missing file, the documented RED state for the
// right reason.
func TestClosureEvidenceClass_GoldenBad_UserVisibleItemRefusedOnGrepOnlyEvidence(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const id = "WIT-741"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "CR-001/CR-002 golden-bad (grep-only claimed runtime) " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Feature", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	cfg := writeMinimalClosureCheckConfig(t, dbPath)
	attempt := evidenceClassAttemptFixture{
		ItemID:       id,
		TargetStatus: "Implemented",
		DefectLayer:  "user-visible",
		Evidence: []map[string]interface{}{
			{"EvidencePath": grepOnlyRuntimeEvidenceFile(t), "claimed_class": "runtime"},
		},
		// No SiblingSearch / RegressionGuard: Features are exempt from both
		// CR-004 and CR-005 (DEC-20 alternative (b); CR-005's own text is
		// scoped to "A Bug closure requires ..."), so this fixture supplies
		// neither -- keeping the golden-bad assertion isolated to CR-001/CR-002.
	}
	attemptPath := writeEvidenceClassAttemptJSON(t, attempt)
	decisionPath := filepath.Join(t.TempDir(), "decision.json")

	stdout, stderr, code := runWorkableItemsBinary(t, bin,
		"closure-check",
		"--config", cfg,
		"--item", id,
		"--to", "Implemented",
		"--attempt", attemptPath,
		"--out", decisionPath,
	)

	if code != exitUsage {
		t.Errorf("closure-check exited %d, want %d (contracts/closure-refusal.md "+
			"exit-codes: \"closure-check: 0 ACCEPTED, 1 REFUSED\"); stdout=%q stderr=%q",
			code, exitUsage, stdout, stderr)
	}
	decision, ok := decisionOf(t, decisionPath)
	if !ok {
		t.Errorf("RED (T095 not yet landed): closure-check wrote no parseable "+
			"decision to %s at all -- want a body whose \"decision\" field is "+
			"CR-001's refusal naming the missing runtime evidence class (tasks.md "+
			"T087's own literal: \"missing evidence class: runtime\"; "+
			"contracts/closure-refusal.md CR-001's literal: "+
			"\"REFUSED(missing: runtime evidence at user-visible layer; "+
			"supplied: <highest class>)\" -- see this file's header for the "+
			"honestly-documented drift between the two); stdout=%q stderr=%q",
			decisionPath, stdout, stderr)
		return
	}
	// Deliberately the INTERSECTION of both candidate literals (see file
	// header): REFUSED + the concept "missing" + the specific missing
	// class's own name "runtime" -- satisfied by either tasks.md T087's
	// literal or CR-001's literal, and by any reasonable T095-authored
	// variant in between; NEVER a fabricated single string this file
	// picked unilaterally.
	if !containsAll(decision, "REFUSED", "missing", "runtime") {
		t.Errorf("decision=%q, want it to contain %q, %q and %q -- the "+
			"intersection of tasks.md T087's literal (\"missing evidence "+
			"class: runtime\") and contracts/closure-refusal.md CR-001's "+
			"literal (\"REFUSED(missing: runtime evidence at user-visible "+
			"layer; supplied: <highest class>)\")",
			decision, "REFUSED", "missing", "runtime")
	}
}

// TestClosureEvidenceClass_NegativeControl_SourceLayerTaskClosedOnSource
// Evidence_Accepted is T-D02's own THIRD protecting-tests bullet, verbatim
// from plan.md and tasks.md T087: "a source-layer Task closed on source
// evidence is accepted". CR-001's layer floor only requires runtime
// evidence for a user-visible defect_layer -- source-on-source is legal
// (the §11.4.201(1) false-refusal guard, matching contracts/closure-
// refusal.md's own named fixture cr_negctrl_source_layer_task: "ACCEPTED
// (source-on-source is legal; the §11.4.201(1) false-refusal guard)").
// Without this test, TestClosureEvidenceClass_GoldenBad_UserVisibleItem
// RefusedOnGrepOnlyEvidence alone could be satisfied by a future seam that
// blanket-refuses every closure lacking runtime evidence regardless of the
// item's own defect_layer -- exactly the over-broad-implementation risk
// this negative control exists to catch. TODAY: closure-check does not
// exist, so this ALSO fails RED (exit 1, "unknown subcommand", not the
// wanted exit 0) -- the same honest, self-flipping RED shape as the
// golden-bad test above and the T088 sibling file's own negative-control
// precedent.
func TestClosureEvidenceClass_NegativeControl_SourceLayerTaskClosedOnSourceEvidence_Accepted(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const id = "WIT-742"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "CR-001 negative control (Task, source layer) " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Task", "Low",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	cfg := writeMinimalClosureCheckConfig(t, dbPath)
	attempt := evidenceClassAttemptFixture{
		ItemID:       id,
		TargetStatus: "Completed",
		DefectLayer:  "source",
		Evidence: []map[string]interface{}{
			{"EvidencePath": realEvidenceFile(t), "claimed_class": "source"},
		},
		// Tasks are exempt from CR-004/CR-005 exactly as Features are; and
		// source-on-source needs no runtime evidence per CR-001's own text.
	}
	attemptPath := writeEvidenceClassAttemptJSON(t, attempt)
	decisionPath := filepath.Join(t.TempDir(), "decision.json")

	stdout, stderr, code := runWorkableItemsBinary(t, bin,
		"closure-check",
		"--config", cfg,
		"--item", id,
		"--to", "Completed",
		"--attempt", attemptPath,
		"--out", decisionPath,
	)

	if code != exitOK {
		t.Errorf("RED (T095 not yet landed OR CR-001's source-on-source "+
			"legality not yet honoured): closure-check exited %d, want %d "+
			"(ACCEPTED) -- CR-001 only requires runtime evidence for a "+
			"user-visible defect_layer; a source-layer defect closed on "+
			"source evidence is legal per contracts/closure-refusal.md's own "+
			"cr_negctrl_source_layer_task fixture; stdout=%q stderr=%q",
			code, exitOK, stdout, stderr)
	}
	if decision, ok := decisionOf(t, decisionPath); ok && decision != "ACCEPTED" {
		t.Errorf("decision=%q, want exactly \"ACCEPTED\" for a Task closing "+
			"on source evidence at the source defect_layer with no runtime "+
			"evidence supplied", decision)
	}
}

// TestClosureEvidenceClass_E4_RefusedWhenGuardHasNoVerdictForCurrent
// ArtifactFingerprint is T-D02's own FOURTH protecting-tests bullet
// (tasks.md T087, verbatim): "E4: closure refused when the registered
// guard has no verdict for the current artifact fingerprint". CR-005
// (data-model.md 6.1's own E4 guard-not-run entry, "A guard existed but
// was not executed against the deployed artifact"; contracts/closure-
// refusal.md CR-005: "A Bug closure requires a registered guard with a
// machine-written RED verdict on the pre-fix artifact and GREEN on the
// fixed artifact ..., and that guard must have a verdict for the current
// artifact fingerprint (E4 guard-not-run, T-D02); absent => refused").
// CR-005 is scoped to Bug closures exactly like CR-004, so this fixture
// uses a Bug item, defect_layer "source" (so CR-001 does not fire) with
// genuinely-source evidence, and a FULLY VALID CR-004 sibling-search
// artefact (validSiblingSearchArtefact) precisely so that clause is
// satisfied and this test's own E4/CR-005 assertion is isolated -- the
// ONLY thing missing is a regression_guard whose verdict store holds
// nothing for the CURRENT artifact fingerprint (the RegressionGuard field
// names a plausible guard id; per data-model.md 6.3 the field itself is
// just an id-or-absent -- resolving whether THAT guard has a fresh
// verdict is the seam's own lookup, which does not exist at all today).
// TODAY: closure-check does not exist, so this ALSO fails RED (exit 1,
// "unknown subcommand", no decision.json ever written) -- the same
// honest, self-flipping RED shape as every other bullet in this file.
func TestClosureEvidenceClass_E4_RefusedWhenGuardHasNoVerdictForCurrentArtifactFingerprint(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const id = "WIT-743"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "E4/CR-005 golden-bad (guard has no current-fingerprint verdict) " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	cfg := writeMinimalClosureCheckConfig(t, dbPath)
	attempt := evidenceClassAttemptFixture{
		ItemID:       id,
		TargetStatus: "Fixed",
		DefectLayer:  "source",
		Evidence: []map[string]interface{}{
			{"EvidencePath": realEvidenceFile(t), "claimed_class": "source"},
		},
		SiblingSearch:   validSiblingSearchArtefact(), // satisfies CR-004 so it does not pollute this assertion
		RegressionGuard: "guard-atm953-routeToSecondary-red-green",
	}
	attemptPath := writeEvidenceClassAttemptJSON(t, attempt)
	decisionPath := filepath.Join(t.TempDir(), "decision.json")

	stdout, stderr, code := runWorkableItemsBinary(t, bin,
		"closure-check",
		"--config", cfg,
		"--item", id,
		"--to", "Fixed",
		"--attempt", attemptPath,
		"--out", decisionPath,
	)

	if code != exitUsage {
		t.Errorf("closure-check exited %d, want %d (contracts/closure-refusal.md "+
			"exit-codes: \"closure-check: 0 ACCEPTED, 1 REFUSED\"); stdout=%q stderr=%q",
			code, exitUsage, stdout, stderr)
	}
	decision, ok := decisionOf(t, decisionPath)
	if !ok {
		t.Errorf("RED (T095 not yet landed): closure-check wrote no parseable "+
			"decision to %s at all -- want a body whose \"decision\" field names "+
			"the E4/CR-005 gap (a registered guard with no verdict for the "+
			"current artifact fingerprint); stdout=%q stderr=%q",
			decisionPath, stdout, stderr)
		return
	}
	// data-model.md 6.1's own E4 vocabulary ("guard-not-run" / "guard
	// verdict history vs the deployed artifact fingerprint") and CR-005's
	// own text ("registered guard", "verdict for the current artifact
	// fingerprint") both use "guard"; this file asserts on that shared
	// term rather than inventing an exact refusal string neither source
	// gives verbatim.
	if !containsAll(decision, "REFUSED", "missing", "guard") {
		t.Errorf("decision=%q, want it to contain %q, %q and %q per data-"+
			"model.md 6.1's E4 (\"guard-not-run\") and contracts/closure-"+
			"refusal.md CR-005 (\"a registered guard ... a verdict for the "+
			"current artifact fingerprint ... absent => refused\")",
			decision, "REFUSED", "missing", "guard")
	}
}
