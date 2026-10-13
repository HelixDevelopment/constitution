// assign_test.go — anti-bluff coverage for the `assign` subcommand family
// (next-group | next-item | group-complete), P3 of
// docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md.
//
// Every test exercises the REAL SQLite driver against a t.TempDir() scratch
// DB (never the live docs/workable_items.db, per §11.4.6/§9.2) via the exact
// same *Cmd entry points main.go dispatches to. The §11.4.176-A exactly-once
// claim registry is exercised against a SELF-CONTAINED, hermetic shell-script
// test double (writeFakeClaimScript) — never the project-layer
// scripts/multitrack/multitrack_claim.sh, so this package's tests stay
// portable per §11.4.28 (a constitution-submodule Go package must be
// completely testable standalone, in ANY consuming project, without that
// project-specific script existing at any particular relative path).
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// ---- fake claim-script test doubles ----

// writeFakeClaimScript writes a minimal, hermetic test double for the
// §11.4.176-A exactly-once claim CLI contract assignNextGroupCmd shells out
// to: `claim <id> <track> [--ttl N]` -> exit 0 (free, or the SAME track
// idempotently re-claiming) | exit 3 (EBUSY, held by a DIFFERENT track) —
// mirroring multitrack_claim.sh's documented exit-code contract exactly.
// preHeld optionally seeds "already held by <track>" state for specific
// group ids (nil/empty = a fully free registry).
func writeFakeClaimScript(t *testing.T, preHeld map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	statePath := filepath.Join(dir, "state.txt")
	var seed strings.Builder
	for id, track := range preHeld {
		fmt.Fprintf(&seed, "%s|%s\n", id, track)
	}
	if err := os.WriteFile(statePath, []byte(seed.String()), 0o644); err != nil {
		t.Fatalf("seed fake claim state: %v", err)
	}
	script := "#!/bin/sh\n" +
		"set -eu\n" +
		"cmd=$1\n" +
		"id=$2\n" +
		"track=$3\n" +
		"state=\"" + statePath + "\"\n" +
		"case \"$cmd\" in\n" +
		"  claim)\n" +
		"    owner=\"\"\n" +
		"    if [ -f \"$state\" ]; then\n" +
		"      owner=$(awk -F'|' -v i=\"$id\" '$1==i{print $2; exit}' \"$state\")\n" +
		"    fi\n" +
		"    if [ -n \"$owner\" ] && [ \"$owner\" != \"$track\" ]; then\n" +
		"      echo \"EBUSY: $id held by $owner\" >&2\n" +
		"      exit 3\n" +
		"    fi\n" +
		"    if [ -z \"$owner\" ]; then\n" +
		"      printf '%s|%s\\n' \"$id\" \"$track\" >> \"$state\"\n" +
		"    fi\n" +
		"    echo \"CLAIMED: $id -> $track\"\n" +
		"    exit 0\n" +
		"    ;;\n" +
		"  *)\n" +
		"    echo \"fake-claim: unsupported command $cmd\" >&2\n" +
		"    exit 2\n" +
		"    ;;\n" +
		"esac\n"
	scriptPath := filepath.Join(dir, "fake_claim.sh")
	if err := os.WriteFile(scriptPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake claim script: %v", err)
	}
	return scriptPath
}

// writeFakeClaimScriptAlwaysExit writes a claim-script test double whose
// `claim` verb ALWAYS exits with code regardless of arguments — for proving
// assignNextGroupCmd treats a genuinely unexpected exit code (neither 0 nor
// 3) as a hard error, never a silent skip-to-next-candidate.
func writeFakeClaimScriptAlwaysExit(t *testing.T, code int) string {
	t.Helper()
	dir := t.TempDir()
	script := fmt.Sprintf("#!/bin/sh\necho \"FATAL: simulated claim-registry failure\" >&2\nexit %d\n", code)
	scriptPath := filepath.Join(dir, "fake_claim_fatal.sh")
	if err := os.WriteFile(scriptPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write fatal fake claim script: %v", err)
	}
	return scriptPath
}

// ---- shared capture helper (mirrors validate_groups_test.go's
// captureValidateGroupsStderr, generalised to any thunk) ----

func captureStderrRun(t *testing.T, fn func() int) (int, string) {
	t.Helper()
	orig := os.Stderr
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stderr = w
	rc := fn()
	w.Close()
	os.Stderr = orig
	out, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read captured stderr: %v", err)
	}
	return rc, string(out)
}

// ================================================================
// candidateGroups (pure DB-side ordering + filtering, no exec)
// ================================================================

func TestCandidateGroups_OrdersByPriorityThenSeverityThenGroupID(t *testing.T) {
	dbPath := newGroupTestDB(t)

	// priority=5 tie between two groups, broken by max_member_severity DESC.
	groupAddCmd([]string{"g-low-pri-high-sev", "main", "5", "--db", dbPath, "--title", "candidate ordering fixture high severity"})
	groupAddCmd([]string{"g-low-pri-low-sev", "main", "5", "--db", dbPath, "--title", "candidate ordering fixture low severity"})
	// priority=1: highest overall priority among eligible groups (lower wins).
	groupAddCmd([]string{"g-high-pri", "main", "1", "--db", dbPath, "--title", "candidate ordering fixture highest priority"})
	// priority=0 but has NO open member -> must be excluded despite best priority.
	groupAddCmd([]string{"g-no-open-members", "main", "0", "--db", dbPath, "--title", "candidate ordering fixture no open members"})
	// priority=0 but state=group-complete -> must be excluded despite best priority.
	groupAddCmd([]string{"g-complete-state", "main", "0", "--db", dbPath, "--title", "candidate ordering fixture already complete"})
	// Different destination -> must be excluded entirely (track doesn't serve it).
	groupAddCmd([]string{"g-other-dest", "feature:x", "0", "--db", dbPath, "--title", "candidate ordering fixture wrong destination"})

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-CG-1", "Issues", "Queued", "Critical", "t1", "", "main", "g-low-pri-high-sev")
	insertRawItem(t, db, "ATM-CG-2", "Issues", "Queued", "Low", "t2", "", "main", "g-low-pri-low-sev")
	insertRawItem(t, db, "ATM-CG-3", "Issues", "Queued", "Low", "t3", "", "main", "g-high-pri")
	insertRawItem(t, db, "ATM-CG-4", "Issues", "Queued", "Critical", "t4", "", "main", "g-complete-state")
	insertRawItem(t, db, "ATM-CG-5", "Issues", "Queued", "Critical", "t5", "", "feature:x", "g-other-dest")
	db.Close()

	if code := groupStateCmd([]string{"g-complete-state", "group-complete", "--db", dbPath}); code != exitOK {
		t.Fatalf("group state -> group-complete exited %d", code)
	}

	candidates, err := runCandidateGroupsFresh(t, dbPath, []string{"main"})
	if err != nil {
		t.Fatalf("candidateGroups: %v", err)
	}

	want := []string{"g-high-pri", "g-low-pri-high-sev", "g-low-pri-low-sev"}
	var got []string
	for _, c := range candidates {
		got = append(got, c.GroupID)
	}
	if len(got) != len(want) {
		t.Fatalf("candidateGroups returned %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("position %d: %q, want %q (full: %v)", i, got[i], want[i], got)
		}
	}
}

// runCandidateGroupsFresh opens dbPath fresh and calls candidateGroups —
// small helper so the N-run determinism test below can call it repeatedly
// through independent *sql.DB handles, matching how a real orchestrator
// would invoke assignNextGroupCmd repeatedly (fresh process each time).
func runCandidateGroupsFresh(t *testing.T, dbPath string, destinations []string) ([]groupCandidate, error) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		return nil, err
	}
	defer db.Close()
	return candidateGroups(db, destinations)
}

func TestCandidateGroups_DeterministicOverTenRuns(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"g-a", "main", "3", "--db", dbPath, "--title", "determinism fixture group a"})
	groupAddCmd([]string{"g-b", "main", "3", "--db", dbPath, "--title", "determinism fixture group b"})
	groupAddCmd([]string{"g-c", "main", "1", "--db", dbPath, "--title", "determinism fixture group c"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-DET-1", "Issues", "Queued", "Medium", "t", "", "main", "g-a")
	insertRawItem(t, db, "ATM-DET-2", "Issues", "Queued", "Medium", "t", "", "main", "g-b")
	insertRawItem(t, db, "ATM-DET-3", "Issues", "Queued", "Low", "t", "", "main", "g-c")
	db.Close()

	var first []string
	for i := 0; i < 10; i++ {
		candidates, err := runCandidateGroupsFresh(t, dbPath, []string{"main"})
		if err != nil {
			t.Fatalf("run %d: candidateGroups: %v", i, err)
		}
		var ids []string
		for _, c := range candidates {
			ids = append(ids, c.GroupID)
		}
		if i == 0 {
			first = ids
			continue
		}
		if len(ids) != len(first) {
			t.Fatalf("run %d: %v, want same length as run 0 %v", i, ids, first)
		}
		for j := range first {
			if ids[j] != first[j] {
				t.Fatalf("run %d NOT deterministic vs run 0 (§11.4.50 violation): %v vs %v", i, ids, first)
			}
		}
	}
}

// ================================================================
// assign next-group
// ================================================================

func TestAssignNextGroupCmd_ClaimsFirstAvailableCandidate(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-solo", "main", "1", "--db", dbPath, "--title", "solo candidate for a free claim"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NG-1", "Issues", "Queued", "Low", "t", "", "main", "grp-solo")
	db.Close()

	scriptPath := writeFakeClaimScript(t, nil)
	code := assignNextGroupCmd([]string{
		"--db", dbPath, "--track", "track-1", "--destinations", "main", "--claim-script", scriptPath,
	})
	if code != exitOK {
		t.Fatalf("assign next-group exited %d, want %d", code, exitOK)
	}

	db, _ = openDB(dbPath)
	g, err := loadGroup(db, "grp-solo")
	db.Close()
	if err != nil || g == nil {
		t.Fatalf("loadGroup after claim: err=%v nil=%v", err, g == nil)
	}
	if g.State != "in-progress" {
		t.Errorf("grp-solo.State = %q after a successful claim, want in-progress", g.State)
	}
}

func TestAssignNextGroupCmd_SkipsEBusyCandidateToNextPriority(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-high", "main", "1", "--db", dbPath, "--title", "highest priority but held by another track"})
	groupAddCmd([]string{"grp-low", "main", "2", "--db", dbPath, "--title", "lower priority but free"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NG-2", "Issues", "Queued", "Low", "t", "", "main", "grp-high")
	insertRawItem(t, db, "ATM-NG-3", "Issues", "Queued", "Low", "t", "", "main", "grp-low")
	db.Close()

	// grp-high is ALREADY held by a different track in the claim registry.
	scriptPath := writeFakeClaimScript(t, map[string]string{"grp-high": "track-OTHER"})

	code := assignNextGroupCmd([]string{
		"--db", dbPath, "--track", "track-1", "--destinations", "main", "--claim-script", scriptPath,
	})
	if code != exitOK {
		t.Fatalf("assign next-group exited %d, want %d (should have fallen through to grp-low)", code, exitOK)
	}

	db, _ = openDB(dbPath)
	high, _ := loadGroup(db, "grp-high")
	low, _ := loadGroup(db, "grp-low")
	db.Close()
	if high == nil || high.State == "in-progress" {
		t.Errorf("grp-high.State = %+v after an EBUSY claim attempt, want UNCHANGED (still not in-progress via THIS track)", high)
	}
	if low == nil || low.State != "in-progress" {
		t.Errorf("grp-low.State = %+v, want in-progress (the fallthrough candidate should have been claimed)", low)
	}
}

func TestAssignNextGroupCmd_NoCandidateReturnsExitNoCandidate(t *testing.T) {
	dbPath := newGroupTestDB(t)
	// A group exists but has no open members -> not a candidate.
	groupAddCmd([]string{"grp-empty", "main", "1", "--db", dbPath, "--title", "a group with zero open members"})
	scriptPath := writeFakeClaimScript(t, nil)

	code := assignNextGroupCmd([]string{
		"--db", dbPath, "--track", "track-1", "--destinations", "main", "--claim-script", scriptPath,
	})
	if code != exitNoCandidate {
		t.Fatalf("assign next-group exited %d, want exitNoCandidate=%d when nothing is actionable", code, exitNoCandidate)
	}
}

func TestAssignNextGroupCmd_ClaimScriptMissingIsHardError(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-a", "main", "1", "--db", dbPath, "--title", "group present so candidates is non-empty"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NG-4", "Issues", "Queued", "Low", "t", "", "main", "grp-a")
	db.Close()

	code := assignNextGroupCmd([]string{
		"--db", dbPath, "--track", "track-1", "--destinations", "main",
		"--claim-script", filepath.Join(t.TempDir(), "does-not-exist.sh"),
	})
	if code != exitUsage {
		t.Fatalf("assign next-group exited %d, want exitUsage=%d on a missing claim-script (genuine invocation error)", code, exitUsage)
	}
}

func TestAssignNextGroupCmd_UnexpectedClaimExitIsHardError(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-a", "main", "1", "--db", dbPath, "--title", "group present so candidates is non-empty"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NG-5", "Issues", "Queued", "Low", "t", "", "main", "grp-a")
	db.Close()

	scriptPath := writeFakeClaimScriptAlwaysExit(t, 7)
	code, stderr := captureStderrRun(t, func() int {
		return assignNextGroupCmd([]string{
			"--db", dbPath, "--track", "track-1", "--destinations", "main", "--claim-script", scriptPath,
		})
	})
	if code != exitUsage {
		t.Fatalf("assign next-group exited %d, want exitUsage=%d on an unexpected (neither 0 nor 3) claim exit code — a silent skip here would be a bluff", code, exitUsage)
	}
	if !strings.Contains(stderr, "exited 7") {
		t.Errorf("stderr does not mention the unexpected exit code:\n%s", stderr)
	}
}

func TestAssignNextGroupCmd_RequiredFlags(t *testing.T) {
	dbPath := newGroupTestDB(t)
	scriptPath := writeFakeClaimScript(t, nil)
	cases := []struct {
		name string
		args []string
	}{
		{"missing --db", []string{"--track", "t", "--destinations", "main", "--claim-script", scriptPath}},
		{"missing --track", []string{"--db", dbPath, "--destinations", "main", "--claim-script", scriptPath}},
		{"missing --destinations", []string{"--db", dbPath, "--track", "t", "--claim-script", scriptPath}},
		{"missing --claim-script", []string{"--db", dbPath, "--track", "t", "--destinations", "main"}},
	}
	for _, c := range cases {
		if code := assignNextGroupCmd(c.args); code == exitOK || code == exitNoCandidate {
			t.Errorf("%s: exited %d, want a usage error (neither exitOK nor exitNoCandidate)", c.name, code)
		}
	}
}

// ================================================================
// assign next-item
// ================================================================

// TestAssignNextItemCmd_SelectsByStoredLogicGroup_NeverSubstring is the
// decisive ATM-633-class anti-defect proof for next-item: an item's TITLE
// mentions a DIFFERENT group's name as a red herring, but its STORED
// logic_group is grp-target — next-item --group grp-target MUST find it;
// next-item --group grp-other (the group its title merely LOOKS like it
// belongs to) MUST NOT.
func TestAssignNextItemCmd_SelectsByStoredLogicGroup_NeverSubstring(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-target", "main", "1", "--db", dbPath, "--title", "the group this item is REALLY classified into"})
	groupAddCmd([]string{"grp-other", "main", "1", "--db", dbPath, "--title", "a different group merely name-dropped in the title"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NI-1", "Issues", "Queued", "Low",
		"investigate a regression related to grp-other subsystem", "", "main", "grp-target")
	db.Close()

	code, out := captureStdoutRun(t, func() int {
		return assignNextItemCmd([]string{"--db", dbPath, "--track", "t1", "--group", "grp-target"})
	})
	if code != exitOK {
		t.Fatalf("next-item --group grp-target exited %d, want %d", code, exitOK)
	}
	if !strings.Contains(out, "ATM-NI-1") {
		t.Errorf("next-item --group grp-target did not return the item stored under that group:\n%s", out)
	}

	code = assignNextItemCmd([]string{"--db", dbPath, "--track", "t1", "--group", "grp-other"})
	if code != exitNoCandidate {
		t.Fatalf("next-item --group grp-other exited %d, want exitNoCandidate=%d — the item's TITLE mentions grp-other but its STORED logic_group is grp-target; matching by title/substring here would be the exact ATM-633 defect", code, exitNoCandidate)
	}
}

func TestAssignNextItemCmd_OrdersByCritDescThenAtmIDAsc(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-order", "main", "1", "--db", dbPath, "--title", "ordering fixture group"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NI-9", "Issues", "Queued", "Low", "low sev higher id", "", "main", "grp-order")
	insertRawItem(t, db, "ATM-NI-2", "Issues", "Queued", "Critical", "critical sev", "", "main", "grp-order")
	insertRawItem(t, db, "ATM-NI-3", "Issues", "Queued", "Critical", "critical sev tie lower id wins", "", "main", "grp-order")
	db.Close()

	code, out := captureStdoutRun(t, func() int {
		return assignNextItemCmd([]string{"--db", dbPath, "--track", "t1", "--group", "grp-order"})
	})
	if code != exitOK {
		t.Fatalf("next-item exited %d, want %d", code, exitOK)
	}
	if !strings.Contains(out, "ATM-NI-2") {
		t.Errorf("next-item did not pick the highest-crit, lowest-atm_id-tiebreak item (ATM-NI-2):\n%s", out)
	}
}

func TestAssignNextItemCmd_ExcludeSkipsGivenIDs(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-exclude", "main", "1", "--db", dbPath, "--title", "exclude fixture group"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NI-4", "Issues", "Queued", "Critical", "highest sev but excluded", "", "main", "grp-exclude")
	insertRawItem(t, db, "ATM-NI-5", "Issues", "Queued", "Low", "next best after exclusion", "", "main", "grp-exclude")
	db.Close()

	code, out := captureStdoutRun(t, func() int {
		return assignNextItemCmd([]string{"--db", dbPath, "--track", "t1", "--group", "grp-exclude", "--exclude", "ATM-NI-4"})
	})
	if code != exitOK {
		t.Fatalf("next-item exited %d, want %d", code, exitOK)
	}
	if strings.Contains(out, "ATM-NI-4") {
		t.Errorf("next-item returned an EXCLUDED item:\n%s", out)
	}
	if !strings.Contains(out, "ATM-NI-5") {
		t.Errorf("next-item did not fall through to the next candidate after exclusion:\n%s", out)
	}
}

func TestAssignNextItemCmd_NoOpenItemReturnsExitNoCandidate(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-none-open", "main", "1", "--db", dbPath, "--title", "group with only closed members"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-NI-6", "Fixed", "Fixed (→ Fixed.md)", "Low", "already done", "", "main", "grp-none-open")
	db.Close()

	code := assignNextItemCmd([]string{"--db", dbPath, "--track", "t1", "--group", "grp-none-open"})
	if code != exitNoCandidate {
		t.Fatalf("next-item exited %d, want exitNoCandidate=%d when every member is already closed", code, exitNoCandidate)
	}
}

func TestAssignNextItemCmd_NonexistentGroupIsUsageError(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := assignNextItemCmd([]string{"--db", dbPath, "--track", "t1", "--group", "no-such-group"})
	if code == exitOK || code == exitNoCandidate {
		t.Fatalf("next-item exited %d against a NONEXISTENT group, want a usage error", code)
	}
}

func TestAssignNextItemCmd_RequiredFlags(t *testing.T) {
	dbPath := newGroupTestDB(t)
	cases := []struct {
		name string
		args []string
	}{
		{"missing --db", []string{"--track", "t1", "--group", "g"}},
		{"missing --track", []string{"--db", dbPath, "--group", "g"}},
		{"missing --group", []string{"--db", dbPath, "--track", "t1"}},
	}
	for _, c := range cases {
		if code := assignNextItemCmd(c.args); code == exitOK || code == exitNoCandidate {
			t.Errorf("%s: exited %d, want a usage error", c.name, code)
		}
	}
}

// ================================================================
// assign group-complete
// ================================================================

func TestAssignGroupCompleteCmd_RefusesNonTerminalMember(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-open-member", "main", "1", "--db", dbPath, "--title", "group with a still-open member"})
	db, _ := openDB(dbPath)
	insertRawItem(t, db, "ATM-GC-1", "Issues", "Queued", "Low", "still open", "", "main", "grp-open-member")
	db.Close()

	code, stderr := captureStderrRun(t, func() int {
		return assignGroupCompleteCmd([]string{"grp-open-member", "--db", dbPath})
	})
	if code == exitOK {
		t.Fatal("assign group-complete ACCEPTED a group with a non-terminal member — the group-atomic gate is a bluff")
	}
	if !strings.Contains(stderr, "not terminal") {
		t.Errorf("stderr does not mention the non-terminal violation:\n%s", stderr)
	}

	db, _ = openDB(dbPath)
	g, _ := loadGroup(db, "grp-open-member")
	db.Close()
	if g == nil || g.State == "group-complete" {
		t.Errorf("group state = %+v after a REFUSED completion, want unchanged (not group-complete)", g)
	}
}

func TestAssignGroupCompleteCmd_RefusesTerminalWithoutEvidence(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-no-evidence", "main", "1", "--db", dbPath, "--title", "group whose member was closed with no item_history evidence"})
	db, _ := openDB(dbPath)
	// Terminal status directly via raw SQL — bypasses crud.go's `close`
	// (which REQUIRES --evidence), simulating a state no CLI path would
	// create but which the gate must still catch.
	insertRawItem(t, db, "ATM-GC-2", "Fixed", "Fixed (→ Fixed.md)", "Low", "closed with no evidence trail", "", "main", "grp-no-evidence")
	db.Close()

	code, stderr := captureStderrRun(t, func() int {
		return assignGroupCompleteCmd([]string{"grp-no-evidence", "--db", dbPath})
	})
	if code == exitOK {
		t.Fatal("assign group-complete ACCEPTED a terminal member with NO captured-evidence closure event — the evidence gate is a bluff")
	}
	if !strings.Contains(stderr, "no captured-evidence") {
		t.Errorf("stderr does not mention the missing-evidence violation:\n%s", stderr)
	}
}

// TestAssignGroupCompleteCmd_SucceedsWhenAllMembersTerminalWithEvidence
// exercises the REAL end-to-end flow (group add -> item add -> classify ->
// close --evidence) and is ALSO the regression proof for this phase's
// crud.go plumbing fix: closeCmd now carries destination/logic_group across
// the Issues->Fixed move, so the closed item is STILL visible as this
// group's member afterward (before the fix, it would have silently
// vanished from `WHERE logic_group=?` and group-complete would have
// reported a vacuous, evidence-free "complete").
func TestAssignGroupCompleteCmd_SucceedsWhenAllMembersTerminalWithEvidence(t *testing.T) {
	dbPath := newGroupTestDB(t)
	if code := groupAddCmd([]string{
		"grp-e2e-complete", "main", "1", "--db", dbPath, "--title", "group completed via the real add/classify/close flow",
	}); code != exitOK {
		t.Fatalf("group add exited %d", code)
	}
	if code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-700",
		"--title", "an item to fully close for the group-complete e2e test",
		"--description", "a sufficiently long description clearing the §11.4.91 floor for this fixture",
		"Task", "Medium",
	}); code != exitOK {
		t.Fatalf("add item exited %d", code)
	}
	if code := groupSetCmd([]string{"--db", dbPath, "--item", "WIT-700", "--group", "grp-e2e-complete"}); code != exitOK {
		t.Fatalf("group set --item exited %d", code)
	}
	// BOB-240 §11.4.33 Type↔Status guard reconciliation: WIT-700 is seeded
	// Type=Task, whose §11.4.33 closure vocabulary is "completed", not
	// "fixed" (Bug's word) — the ORIGINAL literal here was itself the exact
	// Type↔Status mismatch BOB-240's guard now refuses. This test's actual
	// intent (group-complete sees the closed member with its logic_group
	// intact) is unaffected by which terminal status keyword closes it.
	evRoot := newEvidenceRoot(t)
	if code := closeCmd([]string{"WIT-700", "--db", dbPath, "--status", "completed",
		"--evidence", materialiseEvidence(t, evRoot, "qa-results/assign-p3/wit-700-evidence.log")}); code != exitOK {
		t.Fatalf("close exited %d", code)
	}

	// Sanity: the closed item must STILL carry its logic_group (the P3
	// plumbing fix) — if this regresses, the group-complete assertion below
	// would pass VACUOUSLY (zero members found) rather than for the right
	// reason, so this is asserted explicitly.
	db, _ := openDB(dbPath)
	closed, err := loadItem(db, "WIT-700", "Fixed")
	db.Close()
	if err != nil || closed == nil {
		t.Fatalf("loadItem(WIT-700, Fixed): err=%v nil=%v", err, closed == nil)
	}
	if closed.LogicGroup != "grp-e2e-complete" {
		t.Fatalf("closed item's logic_group = %q, want grp-e2e-complete (crud.go close plumbing fix regressed — group-complete would vacuously pass)", closed.LogicGroup)
	}

	code := assignGroupCompleteCmd([]string{"grp-e2e-complete", "--db", dbPath})
	if code != exitOK {
		t.Fatalf("assign group-complete exited %d, want %d for a fully terminal-with-evidence group", code, exitOK)
	}

	db, _ = openDB(dbPath)
	g, _ := loadGroup(db, "grp-e2e-complete")
	db.Close()
	if g == nil || g.State != "group-complete" {
		t.Errorf("group state = %+v after a successful completion, want group-complete", g)
	}
}

func TestAssignGroupCompleteCmd_RefusesWithZeroMembers(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-zero-members", "main", "1", "--db", dbPath, "--title", "a group nobody has ever classified into"})
	code := assignGroupCompleteCmd([]string{"grp-zero-members", "--db", dbPath})
	if code == exitOK {
		t.Fatal("assign group-complete ACCEPTED a group with ZERO classified members — vacuous-truth guard is a bluff")
	}
}

func TestAssignGroupCompleteCmd_NonexistentGroupIsUsageError(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := assignGroupCompleteCmd([]string{"no-such-group", "--db", dbPath})
	if code == exitOK {
		t.Fatal("assign group-complete ACCEPTED a nonexistent group_id — existence guard is a bluff")
	}
}

// ================================================================
// splitCSV (pure, DB-free unit coverage)
// ================================================================

func TestSplitCSV(t *testing.T) {
	cases := []struct {
		in   string
		want []string
	}{
		{"", nil},
		{"   ", nil},
		{"main", []string{"main"}},
		{"main,feature:x", []string{"main", "feature:x"}},
		{" main , feature:x ,, ", []string{"main", "feature:x"}},
	}
	for _, c := range cases {
		got := splitCSV(c.in)
		if len(got) != len(c.want) {
			t.Errorf("splitCSV(%q) = %v, want %v", c.in, got, c.want)
			continue
		}
		for i := range c.want {
			if got[i] != c.want[i] {
				t.Errorf("splitCSV(%q)[%d] = %q, want %q", c.in, i, got[i], c.want[i])
			}
		}
	}
}

// ---- stdout capture helper (mirrors captureStderrRun) ----

func captureStdoutRun(t *testing.T, fn func() int) (int, string) {
	t.Helper()
	orig := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stdout = w
	rc := fn()
	w.Close()
	os.Stdout = orig
	out, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read captured stdout: %v", err)
	}
	return rc, string(out)
}
