// fastcycle_sibling_search_test.go — T088 RED test, Go half (SpecKit-004
// "fast-dev-cycles", Phase 5 / User Story 3; plan.md T-D03; contract
// closure-refusal.md CR-004; FR-011, SC-004).
//
// Task line (tasks.md T088, verbatim): "[P] [US3] [TDD] RED tests
// `constitution/scripts/fastcycle/tests/test_sibling_search_check_red.sh`
// and
// `constitution/scripts/workable-items/cmd/workable-items/fastcycle_sibling_search_test.go`
// (Bug closure without the artefact accepted today; golden-bad: refused;
// golden-bad: an artefact whose search shows no control needle is rejected;
// negative control: a Task closes without it) (plan T-D03; FR-011,
// SC-004)". The shell half (test_sibling_search_check_red.sh) proves the
// standalone `sibling_search_check.sh` (T096) artefact-shape validator in
// isolation; THIS file proves the two ends of T-D03's own scope at the
// SEAM layer -- today's real `close` subcommand (the gap) and the future
// `closure-check` subcommand (contracts/closure-refusal.md's "Invocations"
// section) that T095 introduces and T097 wires the sibling-search check
// into.
//
// THE GAP, PROVEN LIVE (TestSiblingSearch_BugClosureWithoutArtefact_
// AcceptedToday): today's REAL `close` subcommand (crud.go closeCmd) has NO
// concept of a sibling-instance-search artefact whatsoever -- a Bug closes
// to Fixed with nothing resembling CR-004's requirement supplied, and
// nothing refuses it. contracts/closure-refusal.md CR-004: "Every Bug
// closure requires a valid SiblingSearchArtefact ... Absent or invalid =>
// REFUSED(missing: sibling-instance search). There is no exemption flag...
// Tasks and Features are not bound by CR-004 (DEC-20 alternative (b))."
//
// COMPILE-SAFETY (§11.4.28/§11.4.177's own reuse discipline applied to
// package boundaries, §11.4.240 producer!=verifier): `closure_seam.go`
// (T095) and its `closure-check` subcommand dispatch (main.go, T095/T097)
// do NOT exist yet. This file therefore NEVER references a not-yet-existing
// Go SYMBOL at compile time -- doing so would break `go test ./...` for
// the WHOLE `package main` (crud.go, sync.go, every sibling *_test.go file
// this package already ships), not merely this file, which would be an
// unacceptable blast radius against every OTHER task's parallel RED test
// landing into this same package this session. Instead, exactly like the
// shell-tool precedent (test_io_trace_red.sh invoking the absent
// io_trace.sh as an external process), the "golden-bad" and
// "negative control" bullets below build the REAL `workable-items` binary
// FRESH from the CURRENT source tree via `go build` and invoke it as a
// subprocess with the contract's own documented argv shape. TODAY,
// main.go's subcommand switch does not recognise `closure-check` at all
// (its `default:` case fires, prints "unknown subcommand: closure-check",
// exits 1) -- a real, live, non-fabricated RED signal that self-flips to
// exercising the genuine seam logic the moment T095/T097 land, with NO
// edit to this file.
//
// Assumed CLI contract for `closure-check`'s two file arguments (UNCONFIRMED
// by contracts/closure-refusal.md's own text beyond the field LIST in
// data-model.md §6.3/§6.4 -- no example JSON body is given anywhere;
// DEFINED here, binding-if-adopted on T095/T097's implementer, following
// the house precedent in fixtures/io_trace/README.md and
// fixtures/verdict_cache/README.md):
//
//	--config <cfg>   a YAML file with (at minimum) a top-level `db: <path>`
//	                 key naming the workable-items SQLite DB to check
//	                 the cited --item against (common-conventions.md:
//	                 "the item DB path is consumer DATA under
//	                 config/fastcycle/... passed with --config").
//	--attempt <p>    a JSON file matching data-model.md §6.3 ClosureAttempt:
//	                   {"item_id":..., "target_status":"Fixed"|"Implemented"|"Completed",
//	                    "defect_layer":"source"|"artifact"|"runtime"|"user-visible",
//	                    "evidence":[{"EvidencePath":...,"claimed_class":...}],
//	                    "sibling_search": <SiblingSearchArtefact, §6.4, or absent>}
//	--out <p>        the tool writes a JSON body here with (at minimum) a
//	                 "decision" field: "ACCEPTED" or the CR-007 refusal
//	                 text "REFUSED(missing: <what>)" (exit-codes table:
//	                 "closure-check: 0 ACCEPTED, 1 REFUSED (reason in
//	                 body)").
//
// Producer != Verifier (§11.4.240): this file writes ONLY the RED test. It
// does NOT implement closure_seam.go (T095), the `closure-check` dispatch
// (T095/T097's main.go wiring), or sibling_search_check.sh (T096) -- every
// assertion below is a REAL invocation of either today's REAL `close`
// subcommand (in-process, via the package's own existing closeCmd/addCmd)
// or the freshly REAL-built `workable-items` binary's REAL subprocess exit
// code + REAL --out file content, never a fabricated result.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// Bullet 1 (accepted today) -- proven entirely in-process against the REAL,
// EXISTING close subcommand. No subprocess, no compile-safety concern: every
// symbol referenced here (addCmd, closeCmd, itemLocation, realEvidenceFile)
// already exists in this package today.
// ---------------------------------------------------------------------------

// TestSiblingSearch_BugClosureWithoutArtefact_AcceptedToday is the T-D03 RED
// baseline: today's real `close` subcommand closes a Bug to Fixed with ZERO
// sibling-instance-search-artefact concept supplied anywhere -- the exact
// CR-004 gap ("Every Bug closure requires a valid SiblingSearchArtefact
// ... Absent or invalid => REFUSED") that T095/T096/T097 exist to close.
// realEvidenceFile / itemLocation are reused, unmodified, from
// close_evidence_recordtime_test.go (same package) -- this test invents no
// new fixture helper for a concern those files already cover correctly.
func TestSiblingSearch_BugClosureWithoutArtefact_AcceptedToday(t *testing.T) {
	dbPath := newTestDB(t)
	const id = "WIT-730"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "sibling-search-artefact CR-004 gap probe " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	evidence := realEvidenceFile(t)
	if code := closeCmd([]string{
		"--db", dbPath, "--status", "fixed", "--evidence", evidence, id,
	}); code != exitOK {
		t.Fatalf("RED baseline broken: close %s exited %d, want %d (exitOK) -- "+
			"today's close subcommand should accept a Bug closure with no "+
			"sibling-search-artefact concept at all, since T-D03's seam has "+
			"not landed yet", id, code, exitOK)
	}

	status, loc := itemLocation(t, dbPath, id)
	if status != closeStatusMap["fixed"].status || loc != "Fixed" {
		t.Fatalf("close %s reported success but the item's own row is "+
			"inconsistent: status=%q location=%q, want status=%q location=Fixed",
			id, status, loc, closeStatusMap["fixed"].status)
	}

	t.Logf("RED baseline confirmed (CR-004 gap, plan.md T-D03): Bug %s "+
		"closed successfully via the REAL close subcommand with ZERO "+
		"sibling-search-artefact concept supplied at all -- this is exactly "+
		"what T095 (closure_seam.go extending the status-write seam) and "+
		"T097 (wiring sibling_search_check.sh into it) must refuse once "+
		"landed", id)
}

// ---------------------------------------------------------------------------
// Bullets 2-4 -- the future `closure-check` seam. Exercised ONLY as an
// external subprocess of a binary this test builds fresh from the CURRENT
// source tree (never a possibly-stale prebuilt bin/workable-items -- the
// BOB-188 lesson: a stale copy can fabricate a mismatch). §11.4.6: built,
// never assumed present.
// ---------------------------------------------------------------------------

var (
	sharedWIBinOnce sync.Once
	sharedWIBinPath string
	sharedWIBinErr  error
)

// workableItemsModuleDir resolves the workable-items Go module root
// (parent of cmd/workable-items/, where go.mod lives), relative to THIS
// SOURCE FILE's own location (runtime.Caller(0)) -- robust regardless of
// `go test`'s working directory, never a hardcoded cwd-relative guess (the
// same technique fastcycle_status_consistency_test.go's liveTrackerDBPath
// already uses in this package).
func workableItemsModuleDir(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatalf("runtime.Caller(0) failed -- cannot locate this source file")
	}
	// this file: .../constitution/scripts/workable-items/cmd/workable-items/fastcycle_sibling_search_test.go
	// module root: .../constitution/scripts/workable-items          (2 dirs up)
	dir := filepath.Dir(thisFile)
	return filepath.Clean(filepath.Join(dir, "..", ".."))
}

// sharedWorkableItemsBinary builds the REAL workable-items binary once per
// `go test` process (sync.Once -- every caller in this file shares the
// SAME freshly-built binary; building 3x for 3 tests would be wasted wall
// clock for no additional evidentiary value, since all 3 exercise the
// SAME source tree in the SAME test run). Skips (never fails) when `go` is
// not on PATH -- an honest §11.4.3 SKIP, not a fabricated result.
func sharedWorkableItemsBinary(t *testing.T) string {
	t.Helper()
	sharedWIBinOnce.Do(func() {
		if _, err := exec.LookPath("go"); err != nil {
			sharedWIBinErr = err
			return
		}
		moduleDir := workableItemsModuleDir(t)
		dir, err := os.MkdirTemp("", "wi-fastcycle-siblingsearch-bin-*")
		if err != nil {
			sharedWIBinErr = err
			return
		}
		outPath := filepath.Join(dir, "workable-items")
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, "go", "build", "-o", outPath, "./cmd/workable-items")
		cmd.Dir = moduleDir
		out, buildErr := cmd.CombinedOutput()
		if buildErr != nil {
			sharedWIBinErr = fmt.Errorf("go build ./cmd/workable-items (from %s) failed: %w\noutput:\n%s",
				moduleDir, buildErr, string(out))
			return
		}
		sharedWIBinPath = outPath
	})
	if sharedWIBinErr != nil {
		t.Skipf("cannot build a fresh workable-items binary for this subprocess-based RED test: %v", sharedWIBinErr)
	}
	return sharedWIBinPath
}

// runWorkableItemsBinary runs the given built binary as a real subprocess
// with args, bounded to 30s, and returns its captured stdout, stderr and
// process exit code. A non-ExitError failure (binary not found, context
// deadline) fails the test outright -- only a genuine process exit is
// reported back to the caller as exitCode.
func runWorkableItemsBinary(t *testing.T, binPath string, args ...string) (stdout, stderr string, exitCode int) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, binPath, args...)
	outBuf, errBuf := &bytes.Buffer{}, &bytes.Buffer{}
	cmd.Stdout = outBuf
	cmd.Stderr = errBuf
	err := cmd.Run()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return outBuf.String(), errBuf.String(), ee.ExitCode()
		}
		t.Fatalf("run %s %v: %v (stdout=%q stderr=%q)", binPath, args, err, outBuf.String(), errBuf.String())
	}
	return outBuf.String(), errBuf.String(), 0
}

// closureAttemptFixture mirrors data-model.md §6.3 ClosureAttempt for this
// RED test's own JSON fixtures (see the file header for the field-shape
// UNCONFIRMED/DEFINED-here caveat).
type closureAttemptFixture struct {
	ItemID        string                        `json:"item_id"`
	TargetStatus  string                        `json:"target_status"`
	DefectLayer   string                        `json:"defect_layer"`
	Evidence      []map[string]interface{}      `json:"evidence"`
	SiblingSearch *siblingSearchArtefactFixture `json:"sibling_search,omitempty"`
}

// siblingSearchArtefactFixture mirrors data-model.md §6.4 SiblingSearchArtefact.
type siblingSearchArtefactFixture struct {
	ClassStatement     string              `json:"class_statement"`
	SearchMethod       string              `json:"search_method"`
	ControlNeedle      string              `json:"control_needle"`
	ControlNeedleFound bool                `json:"control_needle_found"`
	InstancesFound     []map[string]string `json:"instances_found"`
}

// writeAttemptJSON marshals a closureAttemptFixture to a fresh temp file and
// returns its path.
func writeAttemptJSON(t *testing.T, attempt closureAttemptFixture) string {
	t.Helper()
	body, err := json.MarshalIndent(attempt, "", "  ")
	if err != nil {
		t.Fatalf("marshal ClosureAttempt fixture: %v", err)
	}
	p := filepath.Join(t.TempDir(), "attempt.json")
	if err := os.WriteFile(p, body, 0o644); err != nil {
		t.Fatalf("write attempt.json: %v", err)
	}
	return p
}

// writeMinimalClosureCheckConfig writes the UNCONFIRMED/DEFINED-here minimal
// --config YAML this RED test assumes closure-check needs (see file header):
// just enough to name the DB the --item is looked up in.
func writeMinimalClosureCheckConfig(t *testing.T, dbPath string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "fastcycle.yaml")
	body := "db: " + dbPath + "\n"
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatalf("write minimal closure-check config: %v", err)
	}
	return p
}

// decisionOf reads and JSON-decodes a --out decision file, returning ("", false)
// when the file is absent or unparseable (both are honest, expected states
// TODAY, since closure-check does not exist yet and therefore never writes
// one) rather than failing the whole test on that alone -- the caller's own
// exit-code assertion already reports the RED state.
func decisionOf(t *testing.T, decisionPath string) (decision string, ok bool) {
	t.Helper()
	body, err := os.ReadFile(decisionPath)
	if err != nil {
		return "", false
	}
	var parsed map[string]interface{}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", false
	}
	d, _ := parsed["decision"].(string)
	return d, d != ""
}

// TestSiblingSearch_GoldenBad_ClosureCheckRefusesWithoutSiblingSearch is
// CR-004's own golden-bad: a Bug ClosureAttempt with `sibling_search`
// entirely ABSENT MUST be REFUSED naming "sibling-instance search"
// (contracts/closure-refusal.md CR-004: "Absent or invalid =>
// REFUSED(missing: sibling-instance search)"). TODAY: closure-check is not
// a recognised subcommand at all (main.go's `default:` case fires), so no
// decision.json is EVER written -- decisionOf() correctly reports
// (\"\", false) and this test fails loudly, naming the missing file, the
// documented RED state for the right reason.
func TestSiblingSearch_GoldenBad_ClosureCheckRefusesWithoutSiblingSearch(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const id = "WIT-731"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "CR-004 golden-bad (no sibling_search) " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	cfg := writeMinimalClosureCheckConfig(t, dbPath)
	attempt := closureAttemptFixture{
		ItemID:       id,
		TargetStatus: "Fixed",
		DefectLayer:  "source",
		Evidence: []map[string]interface{}{
			{"EvidencePath": realEvidenceFile(t), "claimed_class": "source"},
		},
		SiblingSearch: nil, // the golden-bad condition: entirely absent
	}
	attemptPath := writeAttemptJSON(t, attempt)
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
		t.Errorf("RED (T095/T096/T097 not yet landed): closure-check wrote no "+
			"parseable decision to %s at all -- want a body whose \"decision\" "+
			"field is the CR-004 refusal text `REFUSED(missing: sibling-instance "+
			"search)`; stdout=%q stderr=%q", decisionPath, stdout, stderr)
		return
	}
	if !containsAll(decision, "REFUSED", "sibling-instance search") {
		t.Errorf("decision=%q, want it to contain both %q and %q per CR-004's "+
			"exact refusal text `REFUSED(missing: sibling-instance search)`",
			decision, "REFUSED", "sibling-instance search")
	}
}

// TestSiblingSearch_GoldenBad_ArtefactWithoutControlNeedle_Rejected is
// T-D03's own SECOND protecting-tests bullet, verbatim from plan.md: "an
// artefact whose search shows no needle is rejected (a null without a
// needle is not evidence)". Here the sibling_search artefact IS present but
// its control_needle_found is false and it reports zero instances_found --
// exactly the "null without a needle" shape plan.md names. Same RED shape
// as the test above: today closure-check does not exist, so no decision.json
// is ever written.
func TestSiblingSearch_GoldenBad_ArtefactWithoutControlNeedle_Rejected(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const id = "WIT-732"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "CR-004 golden-bad (needle not found) " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	cfg := writeMinimalClosureCheckConfig(t, dbPath)
	attempt := closureAttemptFixture{
		ItemID:       id,
		TargetStatus: "Fixed",
		DefectLayer:  "source",
		Evidence: []map[string]interface{}{
			{"EvidencePath": realEvidenceFile(t), "claimed_class": "source"},
		},
		SiblingSearch: &siblingSearchArtefactFixture{
			ClassStatement:     "a closure whose evidence_path was accepted at record time despite never resolving",
			SearchMethod:       "grep -rln 'evidence_path' constitution/scripts/workable-items/cmd/workable-items/*.go",
			ControlNeedle:      "crud.go:requireEvidencePath",
			ControlNeedleFound: false, // the golden-bad condition: the mechanism's own proof-of-life failed
			InstancesFound:     []map[string]string{},
		},
	}
	attemptPath := writeAttemptJSON(t, attempt)
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
		t.Errorf("closure-check exited %d, want %d (REFUSED); stdout=%q stderr=%q",
			code, exitUsage, stdout, stderr)
	}
	decision, ok := decisionOf(t, decisionPath)
	if !ok {
		t.Errorf("RED (T095/T096/T097 not yet landed): closure-check wrote no "+
			"parseable decision to %s at all -- want a body whose \"decision\" "+
			"field names the artefact's failed control needle (plan.md T-D03: "+
			"\"a null without a needle is not evidence\"); stdout=%q stderr=%q",
			decisionPath, stdout, stderr)
		return
	}
	if !containsAll(decision, "REFUSED") {
		t.Errorf("decision=%q, want it to contain %q (a control-needle failure "+
			"is still an invalid artefact per CR-004)", decision, "REFUSED")
	}
}

// TestSiblingSearch_NegativeControl_TaskClosesWithoutSiblingSearch is
// T-D03's own THIRD protecting-tests bullet: "negative control: a Task
// closes without it". contracts/closure-refusal.md CR-004, verbatim:
// "Tasks and Features are not bound by CR-004 (DEC-20 alternative (b))."
// This mirrors the contract's OWN named fixture `cr_negctrl_source_layer_
// task` ("a Task whose layer is source, closed on source evidence" =>
// "ACCEPTED (source-on-source is legal; the §11.4.201(1) false-refusal
// guard)"). §11.4.201(1): this negative control exists precisely so a
// FUTURE over-broad implementation of CR-004 (one that refuses EVERY
// closure lacking a sibling_search artefact, not just Bugs) is caught --
// without it, TestSiblingSearch_GoldenBad_ClosureCheckRefusesWithoutSibling
// Search alone could be satisfied by a seam that blanket-refuses every
// closure regardless of item type. TODAY: closure-check does not exist, so
// this ALSO fails RED (exit 1, "unknown subcommand", not the wanted exit 0)
// -- the same honest, self-flipping RED shape as the two golden-bad tests
// above, and the shell test's own C3 negative-control precedent
// (test_io_trace_red.sh) for the same reason.
func TestSiblingSearch_NegativeControl_TaskClosesWithoutSiblingSearch(t *testing.T) {
	bin := sharedWorkableItemsBinary(t)
	dbPath := newTestDB(t)
	const id = "WIT-733"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "CR-004 negative control (Task, source layer) " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Task", "Low",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}

	cfg := writeMinimalClosureCheckConfig(t, dbPath)
	attempt := closureAttemptFixture{
		ItemID:       id,
		TargetStatus: "Completed",
		DefectLayer:  "source",
		Evidence: []map[string]interface{}{
			{"EvidencePath": realEvidenceFile(t), "claimed_class": "source"},
		},
		SiblingSearch: nil, // Tasks are exempt from CR-004 -- this MUST still be ACCEPTED
	}
	attemptPath := writeAttemptJSON(t, attempt)
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
		t.Errorf("RED (T095/T096/T097 not yet landed OR CR-004's Tasks-exemption "+
			"not yet honoured): closure-check exited %d, want %d (ACCEPTED) -- "+
			"CR-004 explicitly states \"Tasks and Features are not bound by "+
			"CR-004\"; stdout=%q stderr=%q", code, exitOK, stdout, stderr)
	}
	if decision, ok := decisionOf(t, decisionPath); ok && decision != "ACCEPTED" {
		t.Errorf("decision=%q, want exactly \"ACCEPTED\" for a Task closing on "+
			"source evidence with no sibling_search artefact", decision)
	}
}

// containsAll reports whether s contains every one of subs (order-independent).
func containsAll(s string, subs ...string) bool {
	for _, sub := range subs {
		if !strings.Contains(s, sub) {
			return false
		}
	}
	return true
}
