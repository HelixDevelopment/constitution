// t103_review_remediation_test.go — SpecKit-004 "fast-dev-cycles" T103
// (batched independent review of US3) round-1 remediation tests, authored
// RED-first against the pre-fix code (§11.4.115 / §11.4.224) and kept as
// permanent regression guards (§11.4.135). Each test names the review
// finding it closes:
//
//	R1-I2  closure_seam.go guardHasVerdictForFingerprint: a producer-authored
//	       regression_guard id containing path separators ("../x") resolved a
//	       verdict file OUTSIDE the configured verdict store (the producer could
//	       forge its own verdict — §11.4.240), and the documented "a verdict
//	       store can never match UNKNOWN" assumption was false (a store entry
//	       literally "UNKNOWN" matched an unresolvable fingerprint).
//	R1-I6  closure_seam.go checkSiblingSearch: a sibling instance dispositioned
//	       "tracked-as <ItemId>" was accepted without checking the id exists in
//	       the tracker — an instance "tracked" as a non-existent item is a lost
//	       requirement (§11.4.197), not a tracked one.
//	R1-M1  closure_seam.go hasTargetFingerprint: ANY non-string value (false,
//	       0, {}) counted as a present target fingerprint.
//	R1-I3  intake_match.go writeIntakeMatchEvidence: a FIXED file name per
//	       output directory, so a second SAME_DEFECT reopen overwrote the first
//	       reopen's evidence and the first Reopened row's evidence_path silently
//	       pointed at the wrong item's rationale (§11.4.7 audit-trail loss).
//	R1-I4  intake_match.go mintIntakeReport: the minted id was taken as ANY id
//	       in the after-minus-before set (Go map iteration order), so a
//	       concurrent writer's item could be reported as ours.
package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeGuardStoreRecord(t *testing.T, dir, guardID string, fps []string) {
	t.Helper()
	body, _ := json.Marshal(map[string]interface{}{"guard_id": guardID, "green_fingerprints": fps})
	p := filepath.Join(dir, guardID+".json")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, body, 0o644); err != nil {
		t.Fatal(err)
	}
}

// R1-I2 (a) — traversal.
func TestT103_GuardVerdict_TraversingGuardIDNeverResolvesOutsideStore(t *testing.T) {
	root := t.TempDir()
	store := filepath.Join(root, "store")
	if err := os.MkdirAll(store, 0o755); err != nil {
		t.Fatal(err)
	}
	// A producer-controlled file OUTSIDE the configured store claiming GREEN.
	writeGuardStoreRecord(t, root, "outside/forged", []string{"abc123"})
	if guardHasVerdictForFingerprint(store, "../outside/forged", "abc123") {
		t.Fatalf("guard id %q resolved a verdict OUTSIDE the configured store %q — a producer can forge its own verdict (§11.4.240)", "../outside/forged", store)
	}
	// Negative control (§11.4.201(1)): a genuine in-store verdict still matches.
	writeGuardStoreRecord(t, store, "guard_ok", []string{"abc123"})
	if !guardHasVerdictForFingerprint(store, "guard_ok", "abc123") {
		t.Fatalf("negative control: a genuine in-store verdict for the current fingerprint was NOT found")
	}
}

// R1-I2 (b) — the UNKNOWN sentinel must never satisfy a verdict lookup.
func TestT103_GuardVerdict_UnknownFingerprintNeverMatches(t *testing.T) {
	store := t.TempDir()
	writeGuardStoreRecord(t, store, "guard_u", []string{"UNKNOWN"})
	if guardHasVerdictForFingerprint(store, "guard_u", "UNKNOWN") {
		t.Fatalf("an UNRESOLVABLE fingerprint (sentinel UNKNOWN) matched a store entry — the seam accepted a closure whose artifact fingerprint could not be read")
	}
}

// R1-M1.
func TestT103_HasTargetFingerprint_OnlyNonEmptyStringCounts(t *testing.T) {
	for _, bad := range []interface{}{false, true, 0, 1.5, map[string]interface{}{}, []interface{}{}, "   ", ""} {
		if hasTargetFingerprint(map[string]interface{}{"target_fingerprint": bad}) {
			t.Errorf("target_fingerprint=%#v was accepted as a present target fingerprint", bad)
		}
	}
	if !hasTargetFingerprint(map[string]interface{}{"target_fingerprint": "sha256:abc"}) {
		t.Errorf("negative control: a real string fingerprint was rejected")
	}
}

// R1-I6.
func TestT103_SiblingSearch_TrackedAsMustNameAnExistingItem(t *testing.T) {
	dbPath := newTestDB(t)
	for _, id := range []string{"ATM-9001", "ATM-9002"} {
		if code := addCmd([]string{
			"--db", dbPath, "--id", id,
			"--title", "t103 tracked-as existence probe " + id,
			"--description", "a sufficiently long description that clears the §11.4.91 floor",
			"Bug", "High",
		}); code != exitOK {
			t.Fatalf("add %s exited %d", id, code)
		}
	}
	mk := func(disposition string) closureAttempt {
		raw, _ := json.Marshal(map[string]interface{}{
			"class_statement":      "t103 probe class",
			"search_method":        "grep -rn probe",
			"control_needle":       "probe-needle",
			"control_needle_found": true,
			"instances_found": []map[string]string{
				{"location": "some/file.go:1", "disposition": disposition},
			},
		})
		return closureAttempt{ItemID: "ATM-9001", DefectLayer: "source", SiblingSearch: raw}
	}
	cfg := closureCheckConfig{dbPath: dbPath}

	decision, refused := checkSiblingSearch("Bug", mk("tracked-as ATM-99999999"), cfg)
	if !refused || !strings.Contains(decision, "ATM-99999999") {
		t.Fatalf("a sibling instance tracked-as a NON-EXISTENT item was accepted (refused=%v, decision=%q)", refused, decision)
	}
	// Negative control: tracked-as an item that genuinely exists is accepted.
	if decision, refused := checkSiblingSearch("Bug", mk("tracked-as ATM-9002"), cfg); refused {
		t.Fatalf("negative control: tracked-as an EXISTING item was refused: %q", decision)
	}
}

// R1-I3.
func TestT103_IntakeEvidence_DistinctFilePerReopenNeverOverwrites(t *testing.T) {
	dir := t.TempDir()
	out := filepath.Join(dir, "link.json")
	p1, err := writeIntakeMatchEvidence(out, "ATM-1", "r1.json", 70)
	if err != nil {
		t.Fatal(err)
	}
	p2, err := writeIntakeMatchEvidence(out, "ATM-2", "r2.json", 80)
	if err != nil {
		t.Fatal(err)
	}
	if p1 == p2 {
		t.Fatalf("two reopens wrote the SAME evidence path %q — the first Reopened row's evidence is overwritten", p1)
	}
	b1, err := os.ReadFile(p1)
	if err != nil || !strings.Contains(string(b1), "ATM-1") || strings.Contains(string(b1), "ATM-2") {
		t.Fatalf("first reopen's evidence no longer describes ATM-1 (err=%v): %q", err, string(b1))
	}
}

// R1-I4.
func TestT103_MintedIDIdentification_IgnoresConcurrentWriterItems(t *testing.T) {
	dbPath := newTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	before, err := allDistinctIDs(db)
	if err != nil {
		t.Fatal(err)
	}
	add := func(id, title string) {
		if code := addCmd([]string{"--db", dbPath, "--id", id, "--title", title,
			"--description", "a sufficiently long description that clears the §11.4.91 floor",
			"Bug", "Medium"}); code != exitOK {
			t.Fatalf("add %s exited %d", id, code)
		}
	}
	// Concurrent writers insert BEFORE and AFTER ours between the snapshots;
	// sorted and map-iteration order must not decide the answer.
	add("ATM-7001", "concurrent writer item A")
	add("ATM-7002", "our intake report title")
	add("ATM-7003", "concurrent writer item B")
	for i := 0; i < 20; i++ { // map iteration is randomised; repeat
		got, err := identifyMintedID(db, before, "our intake report title")
		if err != nil || got != "ATM-7002" {
			t.Fatalf("identifyMintedID = %q, %v; want ATM-7002", got, err)
		}
	}
	// Ambiguous (two new items with our exact title) must be an honest error, never a guess.
	add("ATM-7004", "our intake report title")
	if got, err := identifyMintedID(db, before, "our intake report title"); err == nil {
		t.Fatalf("ambiguous mint resolved to %q instead of an error", got)
	}
}
