// states_cli_test.go — end-to-end coverage for the §11.4.292 reproduction /
// investigation states through the REAL subcommands and the real SQLite driver:
// golden md→db→md round trip, add/update flags, close/move/update closure
// refusals, `states freeze`, `states import`, validate/diff desync detection,
// export summaries, report, and the pre-v8 migration.
//
// HARD CONSTRAINT: temp DBs only (newTestDB / t.TempDir); never the live DB.
package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const statesAt = "2026-11-03T12:00:00Z"

func mustOpen(t *testing.T, dbPath string) *sql.DB {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	return db
}

func mustItem(t *testing.T, dbPath, id, loc string) *item {
	t.Helper()
	db := mustOpen(t, dbPath)
	defer db.Close()
	it, err := loadItem(db, id, loc)
	if err != nil || it == nil {
		t.Fatalf("loadItem %s [%s]: it=%v err=%v", id, loc, it, err)
	}
	return it
}

func addBug(t *testing.T, dbPath, id string, extra ...string) int {
	t.Helper()
	args := append([]string{"--db", dbPath, "--id", id,
		"--title", "states fixture item " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor for states"}, extra...)
	return addCmd(append(args, "Bug", "High"))
}

func completeLiveFlags(ev string) []string {
	return []string{"--reproduction-state", "reproduced-live", "--reproduction-surface", "live-target",
		"--reproduction-evidence", ev, "--reproduction-red-cmd", "bash tests/red.sh",
		"--reproduction-green-cmd", "bash tests/red.sh", "--reproduction-env", "D2 serial 42, image 0.3.5",
		"--reproduction-signature", "rc=1", "--states-updated-by", "agent-t", "--states-updated-at", statesAt}
}

// exportRoundTrip exports the DB, re-imports the export into a NEW DB, and
// re-exports it: every item's state columns must survive and the two exports
// must be byte-identical (export loses no field, the parse loses no field).
func exportRoundTrip(t *testing.T, dbPath string) (issues, fixed string) {
	t.Helper()
	dir := t.TempDir()
	if rc := exportCmd([]string{"--db", dbPath, "--out-dir", dir, "--no-formats"}); rc != exitOK {
		t.Fatalf("export exited %d", rc)
	}
	db2 := filepath.Join(dir, "reimport.db")
	if rc := syncMDToDB([]string{"--db", db2, "--issues", filepath.Join(dir, "Issues.md"), "--fixed", filepath.Join(dir, "Fixed.md")}); rc != exitOK {
		t.Fatalf("md-to-db of the export exited %d", rc)
	}
	dir2 := t.TempDir()
	if rc := exportCmd([]string{"--db", db2, "--out-dir", dir2, "--no-formats"}); rc != exitOK {
		t.Fatalf("re-export exited %d", rc)
	}
	for _, f := range []string{"Issues.md", "Fixed.md"} {
		a, _ := os.ReadFile(filepath.Join(dir, f))
		b, _ := os.ReadFile(filepath.Join(dir2, f))
		if string(a) != string(b) {
			t.Errorf("%s not byte-identical after export → md-to-db → export: %s", f, firstDiff(string(a), string(b)))
		}
	}
	// The summaries' Description cell is re-derived from the body on md-to-db
	// (pre-existing, unrelated to states), so only the two state cells of each
	// item row are compared.
	for _, f := range []string{"Issues_Summary.md", "Fixed_Summary.md"} {
		a, _ := os.ReadFile(filepath.Join(dir, f))
		b, _ := os.ReadFile(filepath.Join(dir2, f))
		if sa, sb := summaryStateCells(string(a)), summaryStateCells(string(b)); sa != sb {
			t.Errorf("%s state cells differ after export → md-to-db → export:\n%s\n---\n%s", f, sa, sb)
		}
	}
	d1, d2 := mustOpen(t, dbPath), mustOpen(t, db2)
	defer d1.Close()
	defer d2.Close()
	i1, err := loadItems(d1)
	if err != nil {
		t.Fatal(err)
	}
	i2, err := loadItems(d2)
	if err != nil {
		t.Fatal(err)
	}
	byKey := map[string]stateRecord{}
	for _, it := range i2 {
		byKey[it.AtmID+"\x00"+it.CurrentLocation] = it.States
	}
	for _, it := range i1 {
		if got := byKey[it.AtmID+"\x00"+it.CurrentLocation]; got != it.States {
			t.Errorf("%s states lost in export round trip:\n got %+v\nwant %+v", it.AtmID, got, it.States)
		}
	}
	is, _ := os.ReadFile(filepath.Join(dir, "Issues_Summary.md"))
	fs, _ := os.ReadFile(filepath.Join(dir, "Fixed_Summary.md"))
	return string(is), string(fs)
}

// summaryStateCells returns "<ATM id> <repro cell> | <inv cell>" per item row of
// a summary (the id is the first cell, or the prefix of the description cell in
// Fixed_Summary).
func summaryStateCells(doc string) string {
	var out []string
	for _, l := range strings.Split(doc, "\n") {
		if !strings.HasPrefix(l, "| ") || strings.HasPrefix(l, "| ATM ID") || strings.HasPrefix(l, "| # ") || strings.HasPrefix(l, "|---") {
			continue
		}
		cells := strings.Split(strings.Trim(l, "|"), " | ")
		if len(cells) < 7 {
			continue
		}
		id := strings.TrimSpace(cells[0])
		if len(cells) == 8 {
			id = strings.SplitN(strings.TrimSpace(cells[5]), " ", 2)[0]
		}
		out = append(out, id+" "+strings.TrimSpace(cells[len(cells)-2])+" | "+strings.TrimSpace(cells[len(cells)-1]))
	}
	return strings.Join(out, "\n")
}

// TestStatesCLI_GoldenFixtureRoundTrip: the golden tracker round-trips
// byte-identical and parses to the exact expected columns.
func TestStatesCLI_GoldenFixtureRoundTrip(t *testing.T) {
	orig, regen, dbPath := roundTripFixture(t, "fx_states_golden.md")
	if orig != regen {
		t.Fatalf("fx_states_golden.md NOT byte-identical: %s", firstDiff(orig, regen))
	}
	want := map[string]stateRecord{
		"WIT-801": {},
		"WIT-802": {ReproState: reproUnreproduced, ReproRedCmd: "bash tests/red.sh --board D2", ReproSignature: `rc=1 and "frame-size 0"`,
			ReproUpdatedAt: "2026-11-03T10:00:00Z", ReproUpdatedBy: "conductor",
			InvState: invInProgress, InvUpdatedAt: "2026-11-03T10:00:00Z", InvUpdatedBy: "conductor"},
		"WIT-803": {ReproState: reproHostFixture, ReproSurface: surfaceHostOnly, ReproEvidence: "qa-results/wit803/red.txt",
			ReproRedCmd: "go test -run TestX ./...", ReproGreenCmd: "go test -run TestX ./...", ReproEnv: "host linux, go 1.26",
			ReproSignature: "the log carries `frame-size 0` | twice", ReproUpdatedAt: "2026-11-03T11:00:00Z", ReproUpdatedBy: "agent-a",
			InvState: invRootCauseFound, InvRootCause: "off-by-one in the parser — fixed in parse.go", InvEvidence: "qa-results/wit803/rca.md",
			InvUpdatedAt: "2026-11-03T11:00:00Z", InvUpdatedBy: "agent-a"},
		"WIT-804": {ReproState: reproBlocked, ReproBlocker: "needs: D2 board; missing: HDMI capture rig",
			ReproUpdatedAt: "2026-11-03T12:00:00Z", ReproUpdatedBy: "conductor"},
		"WIT-805": {},
		"WIT-806": {ReproState: reproLive, ReproSurface: surfaceLiveTarget, ReproEvidence: "qa-results/wit806/red.txt",
			ReproRedCmd: "adb shell dumpsys media.audio_flinger", ReproSignature: "count=0"},
	}
	for id, w := range want {
		if got := mustItem(t, dbPath, id, "Issues").States; got != w.norm() {
			t.Errorf("%s columns:\n got %+v\nwant %+v", id, got, w.norm())
		}
	}
	root := newEvidenceRoot(t)
	for _, p := range []string{"qa-results/wit803/red.txt", "qa-results/wit803/rca.md", "qa-results/wit806/red.txt"} {
		materialiseEvidence(t, root, p)
	}
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate on the golden fixture exited %d", rc)
	}
	issuesSummary, _ := exportRoundTrip(t, dbPath)
	golden, err := os.ReadFile(filepath.Join("testdata", "fx_states_golden.summary_rows.txt"))
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range strings.Split(strings.TrimRight(string(golden), "\n"), "\n") {
		if !strings.Contains(issuesSummary, row+"\n") {
			t.Errorf("Issues_Summary missing golden row:\n%s\n--- summary ---\n%s", row, issuesSummary)
		}
	}
}

// TestStatesCLI_AddUpdateFlags: add / update write the columns AND the body,
// stamp the changed block only, and validate + round-trip stay clean.
func TestStatesCLI_AddUpdateFlags(t *testing.T) {
	dbPath := newTestDB(t)
	root := newEvidenceRoot(t)
	ev := materialiseEvidence(t, root, "qa-results/wit300/red.txt")
	if rc := addBug(t, dbPath, "WIT-300", "--reproduction-state", "UNREPRODUCED",
		"--reproduction-red-cmd", "bash tests/red.sh", "--reproduction-signature", "rc=1",
		"--investigation-state", "not-started", "--states-updated-by", "agent-t", "--states-updated-at", statesAt); rc != exitOK {
		t.Fatalf("add with state flags exited %d", rc)
	}
	it := mustItem(t, dbPath, "WIT-300", "Issues")
	if it.States.ReproState != reproUnreproduced || it.States.ReproUpdatedBy != "agent-t" || it.States.ReproUpdatedAt != statesAt ||
		it.States.InvState != invNotStarted || it.States.InvUpdatedAt != statesAt {
		t.Fatalf("add stored %+v", it.States)
	}
	if !strings.Contains(it.BodyMD, "**Reproduction:** none — UNREPRODUCED — red-command `bash tests/red.sh` — signature `rc=1` — updated "+statesAt+" — by `agent-t`\n") ||
		!strings.Contains(it.BodyMD, "**Investigation:** not-started — updated "+statesAt+" — by `agent-t`\n") {
		t.Fatalf("add body lacks the records:\n%s", it.BodyMD)
	}
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate after add exited %d", rc)
	}

	later := "2026-11-04T08:00:00Z"
	args := append([]string{"--db", dbPath, "--id", "WIT-300"}, completeLiveFlags(ev)...)
	args[len(args)-1] = later
	if rc := updateCmd(args); rc != exitOK {
		t.Fatalf("update to reproduced-live exited %d", rc)
	}
	it = mustItem(t, dbPath, "WIT-300", "Issues")
	if l, why := reproLabel(it.States); l != labelReproduced {
		t.Fatalf("complete record labelled %s %v", l, why)
	}
	if it.States.ReproUpdatedAt != later || it.States.InvUpdatedAt != statesAt {
		t.Errorf("stamps: repro %q (want %s, changed) inv %q (want %s, unchanged)", it.States.ReproUpdatedAt, later, it.States.InvUpdatedAt, statesAt)
	}
	if !strings.Contains(it.BodyMD, "**Reproduction:** reproduced-live — REPRODUCED — surface live-target — evidence `"+ev+"`") {
		t.Errorf("body not updated:\n%s", it.BodyMD)
	}
	if strings.Count(it.BodyMD, "**Reproduction:**") != 1 {
		t.Errorf("record duplicated:\n%s", it.BodyMD)
	}
	db := mustOpen(t, dbPath)
	var reason string
	_ = db.QueryRow(`SELECT reason FROM item_history WHERE atm_id='WIT-300' ORDER BY id DESC LIMIT 1`).Scan(&reason)
	db.Close()
	if !strings.Contains(reason, "reproduction UNREPRODUCED -> reproduced-live") {
		t.Errorf("history reason = %q", reason)
	}
	// Clearing a block to UNSET removes its line and its details.
	if rc := updateCmd([]string{"--db", dbPath, "--id", "WIT-300", "--investigation-state", "UNSET", "--states-updated-by", "agent-t"}); rc != exitOK {
		t.Fatalf("update investigation UNSET exited %d", rc)
	}
	it = mustItem(t, dbPath, "WIT-300", "Issues")
	if it.States.InvState != stateUnset || it.States.InvUpdatedAt != "" || strings.Contains(it.BodyMD, "**Investigation:**") {
		t.Errorf("UNSET left %+v / body:\n%s", it.States, it.BodyMD)
	}
	if it.States.ReproUpdatedAt != later {
		t.Errorf("an investigation-only update re-stamped the unchanged reproduction record: %q, want %s", it.States.ReproUpdatedAt, later)
	}
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate after update exited %d", rc)
	}
	exportRoundTrip(t, dbPath)
}

// TestStatesCLI_FlagRefusals: closed sets, attribution, details without a
// state, unresolvable evidence and bad timestamps are refused and write nothing.
func TestStatesCLI_FlagRefusals(t *testing.T) {
	dbPath := newTestDB(t)
	newEvidenceRoot(t)
	if rc := addBug(t, dbPath, "WIT-310"); rc != exitOK {
		t.Fatalf("seed add exited %d", rc)
	}
	before := mustItem(t, dbPath, "WIT-310", "Issues")
	for name, extra := range map[string][]string{
		"bad repro state":        {"--reproduction-state", "VERIFIED", "--states-updated-by", "a"},
		"bad inv state":          {"--investigation-state", "done", "--states-updated-by", "a"},
		"bad surface":            {"--reproduction-state", "UNREPRODUCED", "--reproduction-surface", "somewhere", "--states-updated-by", "a"},
		"no attribution":         {"--reproduction-state", "UNREPRODUCED"},
		"detail without state":   {"--reproduction-signature", "rc=1", "--states-updated-by", "a"},
		"unresolvable evidence":  {"--reproduction-state", "reproduced-live", "--reproduction-evidence", "qa-results/absent.txt", "--states-updated-by", "a"},
		"blocked without reason": {"--reproduction-state", "blocked-no-device", "--states-updated-by", "a"},
		"bad timestamp":          {"--reproduction-state", "UNREPRODUCED", "--states-updated-by", "a", "--states-updated-at", "yesterday"},
		"rcf without evidence":   {"--investigation-state", "root-cause-found-with-evidence", "--investigation-root-cause", "x", "--states-updated-by", "a"},
	} {
		if rc := updateCmd(append([]string{"--db", dbPath, "--id", "WIT-310"}, extra...)); rc == exitOK {
			t.Errorf("%s: update accepted", name)
		}
		if rc := addBug(t, dbPath, "WIT-311", extra...); rc == exitOK {
			t.Errorf("%s: add accepted", name)
			break
		}
	}
	after := mustItem(t, dbPath, "WIT-310", "Issues")
	if after.States != before.States || after.BodyMD != before.BodyMD {
		t.Errorf("a refused update wrote: %+v", after.States)
	}
	// The alias is accepted and stored canonical.
	if rc := updateCmd([]string{"--db", dbPath, "--id", "WIT-310", "--reproduction-state", "blocked-no-device",
		"--reproduction-blocker", "needs D2", "--states-updated-by", "a"}); rc != exitOK {
		t.Fatalf("alias refused: %d", rc)
	}
	if st := mustItem(t, dbPath, "WIT-310", "Issues").States.ReproState; st != reproBlocked {
		t.Errorf("alias stored as %q", st)
	}
}

// TestStatesCLI_ClosureRefusals: an UNREPRODUCED item is never closed VERIFIED
// by close, move or update; PROVISIONAL-DONE (Ready for testing) is allowed.
func TestStatesCLI_ClosureRefusals(t *testing.T) {
	dbPath := newTestDB(t)
	root := newEvidenceRoot(t)
	closeEv := materialiseEvidence(t, root, "docs/qa/WIT-320/close.md")
	redEv := materialiseEvidence(t, root, "qa-results/wit320/red.txt")
	if rc := addBug(t, dbPath, "WIT-320", "--reproduction-state", "UNREPRODUCED", "--states-updated-by", "a"); rc != exitOK {
		t.Fatalf("seed add exited %d", rc)
	}
	if rc := closeCmd([]string{"WIT-320", "--db", dbPath, "--status", "fixed", "--evidence", closeEv}); rc == exitOK {
		t.Fatal("close --status fixed ACCEPTED an UNREPRODUCED Bug")
	}
	if rc := moveCmd([]string{"--db", dbPath, "--id", "WIT-320", "--to", "Fixed", "--status", closeStatusMap["fixed"].status,
		"--why", "test", "--evidence", closeEv}); rc == exitOK {
		t.Fatal("move --to Fixed ACCEPTED an UNREPRODUCED Bug")
	}
	mustItem(t, dbPath, "WIT-320", "Issues")
	// PROVISIONAL-DONE with UNREPRODUCED is legal.
	if rc := updateCmd([]string{"--db", dbPath, "--id", "WIT-320", "--status", "Ready for testing"}); rc != exitOK {
		t.Fatalf("update to Ready for testing refused (PROVISIONAL-DONE must be allowed): %d", rc)
	}
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate refused a PROVISIONAL-DONE UNREPRODUCED item: %d", rc)
	}
	// Blocked is not enough for VERIFIED either.
	if rc := updateCmd([]string{"--db", dbPath, "--id", "WIT-320", "--reproduction-state", "blocked-no-device-with-recorded-blocker",
		"--reproduction-blocker", "needs D2", "--states-updated-by", "a"}); rc != exitOK {
		t.Fatalf("update to blocked exited %d", rc)
	}
	if rc := closeCmd([]string{"WIT-320", "--db", dbPath, "--status", "fixed", "--evidence", closeEv}); rc == exitOK {
		t.Fatal("close --status fixed ACCEPTED a blocked Bug")
	}
	// A REPRODUCED record closes.
	if rc := updateCmd(append([]string{"--db", dbPath, "--id", "WIT-320"}, completeLiveFlags(redEv)...)); rc != exitOK {
		t.Fatalf("update to complete live exited %d", rc)
	}
	if rc := closeCmd([]string{"WIT-320", "--db", dbPath, "--status", "fixed", "--evidence", closeEv}); rc != exitOK {
		t.Fatalf("close of a REPRODUCED Bug refused: %d", rc)
	}
	closed := mustItem(t, dbPath, "WIT-320", "Fixed")
	if closed.States.ReproState != reproLive || !strings.Contains(closed.BodyMD, "**Reproduction:** reproduced-live — REPRODUCED") {
		t.Fatalf("close lost the record: %+v\n%s", closed.States, closed.BodyMD)
	}
	// Downgrading the record of a VERIFIED closure is refused.
	if rc := updateCmd([]string{"--db", dbPath, "--id", "WIT-320", "--location", "Fixed", "--reproduction-state", "UNREPRODUCED",
		"--states-updated-by", "a"}); rc == exitOK {
		t.Fatal("update ACCEPTED an UNREPRODUCED record on a Fixed item")
	}
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate after the closure exited %d", rc)
	}
	exportRoundTrip(t, dbPath)
}

// TestStatesCLI_FreezeArmsTheGate: unarmed, a closed Bug without a record
// passes with an honest note; freeze exempts it once; afterwards a new
// record-less Bug closure is refused, and a reopen drops the exemption.
func TestStatesCLI_FreezeArmsTheGate(t *testing.T) {
	dbPath := newTestDB(t)
	root := newEvidenceRoot(t)
	ev := materialiseEvidence(t, root, "docs/qa/close.md")
	for _, id := range []string{"WIT-330", "WIT-331"} {
		if rc := addBug(t, dbPath, id); rc != exitOK {
			t.Fatalf("add %s exited %d", id, rc)
		}
	}
	if rc := closeCmd([]string{"WIT-330", "--db", dbPath, "--status", "fixed", "--evidence", ev}); rc != exitOK {
		t.Fatalf("unarmed close of a record-less Bug refused: %d", rc)
	}
	rc, out := captureStdoutRun(t, func() int { return validateCmd([]string{"--db", dbPath}) })
	if rc != exitOK || !strings.Contains(out, "NOT armed") {
		t.Fatalf("unarmed validate rc=%d out=%s", rc, out)
	}
	rc, out = captureStdoutRun(t, func() int {
		return statesCmd([]string{"freeze", "--db", dbPath, "--by", "conductor", "--at", statesAt, "--dry-run"})
	})
	if rc != exitOK || !strings.Contains(out, "1 closed item(s) would be exempted") || !strings.Contains(out, "exempt WIT-330") {
		t.Fatalf("freeze --dry-run rc=%d out=%s", rc, out)
	}
	db := mustOpen(t, dbPath)
	if g, _ := loadClosureGate(db); g.armed || len(g.exempt) != 0 {
		t.Fatalf("--dry-run wrote: %+v", g)
	}
	db.Close()
	if rc := statesCmd([]string{"freeze", "--db", dbPath, "--by", "conductor", "--at", statesAt}); rc != exitOK {
		t.Fatalf("freeze exited %d", rc)
	}
	if rc := statesCmd([]string{"freeze", "--db", dbPath, "--by", "conductor"}); rc == exitOK {
		t.Fatal("a second freeze was accepted (would grandfather new violations)")
	}
	rc, out = captureStdoutRun(t, func() int { return validateCmd([]string{"--db", dbPath}) })
	if rc != exitOK || strings.Contains(out, "NOT armed") {
		t.Fatalf("armed validate rc=%d out=%s", rc, out)
	}
	if rc := closeCmd([]string{"WIT-331", "--db", dbPath, "--status", "fixed", "--evidence", ev}); rc == exitOK {
		t.Fatal("armed close ACCEPTED a Bug without a reproduction record")
	}
	// Detective layer: the exemption is the ONLY thing hiding WIT-330; without
	// it, validate reports the armed C2 violation.
	db = mustOpen(t, dbPath)
	if _, err := db.Exec(`DELETE FROM repro_gate_exemptions WHERE atm_id='WIT-330'`); err != nil {
		t.Fatal(err)
	}
	db.Close()
	rc, errOut := captureStderrRun(t, func() int { return validateCmd([]string{"--db", dbPath}) })
	if rc == exitOK || !strings.Contains(errOut, "WIT-330: Bug closed") || !strings.Contains(errOut, "reproduction_state UNSET") {
		t.Fatalf("validate without the exemption rc=%d stderr=%s", rc, errOut)
	}
	db = mustOpen(t, dbPath)
	if _, err := db.Exec(`INSERT INTO repro_gate_exemptions (atm_id, representation, status, frozen_at) VALUES ('WIT-330','section',?,?)`,
		closeStatusMap["fixed"].status, statesAt); err != nil {
		t.Fatal(err)
	}
	db.Close()
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate with the exemption restored exited %d", rc)
	}
	// Reopen drops the exemption: the next closure is judged like any other.
	inc := materialiseEvidence(t, root, "docs/incidents/wit330.md")
	if rc := reopenCmd([]string{"--id", "WIT-330", "--db", dbPath, "--why", "test-failed", "--who", "AI", "--when", "2026-11-03", "--incident", inc}); rc != exitOK {
		t.Fatalf("reopen exited %d", rc)
	}
	db = mustOpen(t, dbPath)
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM repro_gate_exemptions WHERE atm_id='WIT-330'`).Scan(&n)
	db.Close()
	if n != 0 {
		t.Fatalf("reopen kept %d exemption(s)", n)
	}
	if rc := closeCmd([]string{"WIT-330", "--db", dbPath, "--status", "fixed", "--evidence", ev}); rc == exitOK {
		t.Fatal("re-close of a reopened record-less Bug was grandfathered")
	}
}

func writeTSV(t *testing.T, rows ...string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "states.tsv")
	content := strings.Join(importColumns, "\t") + "\n" + strings.Join(rows, "\n") + "\n"
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func tsvRow(cells map[string]string) string {
	var out []string
	for _, c := range importColumns {
		out = append(out, cells[c])
	}
	return strings.Join(out, "\t")
}

// TestStatesCLI_ImportAllOrNothingIdempotent.
func TestStatesCLI_ImportAllOrNothingIdempotent(t *testing.T) {
	dbPath := newTestDB(t)
	root := newEvidenceRoot(t)
	ev := materialiseEvidence(t, root, "qa-results/wit340/red.txt")
	for _, id := range []string{"WIT-340", "WIT-341"} {
		if rc := addBug(t, dbPath, id); rc != exitOK {
			t.Fatalf("add %s exited %d", id, rc)
		}
	}
	good := writeTSV(t,
		tsvRow(map[string]string{"atm_id": "WIT-340", "reproduction_state": "reproduced-host-fixture", "reproduction_surface": "host-only",
			"reproduction_evidence": ev, "reproduction_red_cmd": "go test ./x", "reproduction_env": "host", "reproduction_signature": "FAIL x"}),
		tsvRow(map[string]string{"atm_id": "WIT-341", "location": "Issues", "reproduction_state": "UNREPRODUCED",
			"reproduction_red_cmd": "bash red.sh | grep -c x", "investigation_state": "in-progress"}),
	)
	rc, out := captureStdoutRun(t, func() int {
		return statesCmd([]string{"import", "--db", dbPath, "--tsv", good, "--by", "importer", "--at", statesAt})
	})
	if rc != exitOK || !strings.Contains(out, "2 change(s)") {
		t.Fatalf("import rc=%d out=%s", rc, out)
	}
	a := mustItem(t, dbPath, "WIT-340", "Issues")
	if l, _ := reproLabel(a.States); l != labelReproduced || a.States.ReproUpdatedBy != "importer" || a.States.ReproUpdatedAt != statesAt {
		t.Fatalf("WIT-340 imported as %+v", a.States)
	}
	b := mustItem(t, dbPath, "WIT-341", "Issues")
	if b.States.ReproRedCmd != "bash red.sh | grep -c x" || b.States.InvState != invInProgress {
		t.Fatalf("WIT-341 imported as %+v", b.States)
	}
	if rc := validateCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("validate after import exited %d", rc)
	}
	db := mustOpen(t, dbPath)
	hist := func() int {
		var n int
		_ = db.QueryRow(`SELECT COUNT(*) FROM item_history WHERE reason LIKE 'states import %'`).Scan(&n)
		return n
	}
	if h := hist(); h != 2 {
		t.Errorf("history rows = %d, want 2", h)
	}
	// Idempotent re-run: no change, stamps kept, no new history.
	rc, out = captureStdoutRun(t, func() int {
		return statesCmd([]string{"import", "--db", dbPath, "--tsv", good, "--by", "someone-else", "--at", "2026-12-01T00:00:00Z"})
	})
	if rc != exitOK || !strings.Contains(out, "0 change(s)") {
		t.Fatalf("re-import rc=%d out=%s", rc, out)
	}
	if h := hist(); h != 2 {
		t.Errorf("re-import wrote history: %d rows", h)
	}
	db.Close()
	if s := mustItem(t, dbPath, "WIT-340", "Issues").States; s.ReproUpdatedBy != "importer" || s.ReproUpdatedAt != statesAt {
		t.Errorf("re-import restamped an unchanged record: %+v", s)
	}
	// An investigation-only row keeps the reproduction record and its stamps.
	invOnly := writeTSV(t, tsvRow(map[string]string{"atm_id": "WIT-340", "investigation_state": "in-progress"}))
	if rc := statesCmd([]string{"import", "--db", dbPath, "--tsv", invOnly, "--by", "other", "--at", "2026-12-02T00:00:00Z"}); rc != exitOK {
		t.Fatalf("investigation-only import exited %d", rc)
	}
	if s := mustItem(t, dbPath, "WIT-340", "Issues").States; s.ReproUpdatedBy != "importer" || s.ReproUpdatedAt != statesAt ||
		s.InvState != invInProgress || s.InvUpdatedBy != "other" {
		t.Errorf("investigation-only import: %+v", s)
	}
	// Empty state cell leaves the block; the alias is stored canonical.
	alias := writeTSV(t, tsvRow(map[string]string{"atm_id": "WIT-341", "reproduction_state": "blocked-no-device", "reproduction_blocker": "needs D2"}))
	if rc := statesCmd([]string{"import", "--db", dbPath, "--tsv", alias, "--by", "importer", "--at", statesAt}); rc != exitOK {
		t.Fatalf("alias import exited %d", rc)
	}
	if s := mustItem(t, dbPath, "WIT-341", "Issues").States; s.ReproState != reproBlocked || s.InvState != invInProgress || s.ReproRedCmd != "" {
		t.Errorf("alias import stored %+v", s)
	}
	// All-or-nothing: one bad row and nothing is written.
	snapshot := mustItem(t, dbPath, "WIT-340", "Issues").States
	for name, rows := range map[string][]string{
		"bad state": {tsvRow(map[string]string{"atm_id": "WIT-340", "reproduction_state": "UNREPRODUCED"}),
			tsvRow(map[string]string{"atm_id": "WIT-341", "reproduction_state": "VERIFIED"})},
		"duplicate": {tsvRow(map[string]string{"atm_id": "WIT-340", "reproduction_state": "UNREPRODUCED"}),
			tsvRow(map[string]string{"atm_id": "WIT-340", "reproduction_state": "UNREPRODUCED"})},
		"unknown id": {tsvRow(map[string]string{"atm_id": "WIT-340", "reproduction_state": "UNREPRODUCED"}),
			tsvRow(map[string]string{"atm_id": "WIT-999", "reproduction_state": "UNREPRODUCED"})},
		"unresolvable evidence": {tsvRow(map[string]string{"atm_id": "WIT-340", "reproduction_state": "reproduced-live", "reproduction_evidence": "qa-results/absent"})},
		"detail without state":  {tsvRow(map[string]string{"atm_id": "WIT-340", "reproduction_signature": "x"})},
		"bad location":          {tsvRow(map[string]string{"atm_id": "WIT-340", "location": "Elsewhere", "reproduction_state": "UNREPRODUCED"})},
	} {
		if rc := statesCmd([]string{"import", "--db", dbPath, "--tsv", writeTSV(t, rows...), "--by", "x", "--at", statesAt}); rc == exitOK {
			t.Errorf("%s: import accepted", name)
		}
		if s := mustItem(t, dbPath, "WIT-340", "Issues").States; s != snapshot {
			t.Errorf("%s: partial write: %+v", name, s)
		}
	}
	badHeader := filepath.Join(t.TempDir(), "bad.tsv")
	_ = os.WriteFile(badHeader, []byte("atm_id\treproduction_state\nWIT-340\tUNREPRODUCED\n"), 0o644)
	if rc := statesCmd([]string{"import", "--db", dbPath, "--tsv", badHeader, "--by", "x"}); rc == exitOK {
		t.Error("import accepted a non-canonical header")
	}
	exportRoundTrip(t, dbPath)
}

// TestStatesCLI_ValidateAndDiffDetectDesync: a column changed behind the body's
// back, and a malformed body record, both fail validate and diff.
func TestStatesCLI_ValidateAndDiffDetectDesync(t *testing.T) {
	dbPath := newTestDB(t)
	newEvidenceRoot(t)
	if rc := addBug(t, dbPath, "WIT-350", "--reproduction-state", "UNREPRODUCED", "--states-updated-by", "a"); rc != exitOK {
		t.Fatalf("add exited %d", rc)
	}
	db := mustOpen(t, dbPath)
	if _, err := db.Exec(`UPDATE items SET reproduction_state='blocked-no-device-with-recorded-blocker', reproduction_blocker='x' WHERE atm_id='WIT-350'`); err != nil {
		t.Fatal(err)
	}
	db.Close()
	if rc := validateCmd([]string{"--db", dbPath}); rc == exitOK {
		t.Fatal("validate passed a column≠body state desync")
	}
	rc, out := captureStdoutRun(t, func() int { return diffCmd([]string{"--db", dbPath, "--db-only"}) })
	if rc == exitOK || !strings.Contains(out, "column↔body desync") {
		t.Fatalf("diff --db-only rc=%d out=%s", rc, out)
	}
	// db-to-md renders the records FROM THE COLUMNS (authoritative), exactly as
	// it does the Status line; the exported Markdown is then edited by hand and
	// diff reports the Markdown-side drift.
	dir := t.TempDir()
	md := filepath.Join(dir, "Issues.md")
	if rc := syncDBToMD([]string{"--db", dbPath, "--out-issues", md, "--out-fixed", filepath.Join(dir, "Fixed.md")}); rc != exitOK {
		t.Fatalf("db-to-md exited %d", rc)
	}
	exported, _ := os.ReadFile(md)
	if !strings.Contains(string(exported), "**Reproduction:** blocked-no-device-with-recorded-blocker — UNREPRODUCED — blocker `x`") {
		t.Fatalf("db-to-md did not render the record from the columns:\n%s", exported)
	}
	edited := strings.Replace(string(exported), "— blocker `x`", "— blocker `edited by hand`", 1)
	if err := os.WriteFile(md, []byte(edited), 0o644); err != nil {
		t.Fatal(err)
	}
	rc, out = captureStdoutRun(t, func() int { return diffCmd([]string{"--db", dbPath, "--issues", md}) })
	if rc == exitOK || !strings.Contains(out, "WIT-350 states:") {
		t.Fatalf("diff --issues rc=%d out=%s", rc, out)
	}
	// Malformed body record.
	db = mustOpen(t, dbPath)
	if _, err := db.Exec(`UPDATE items SET reproduction_state='UNREPRODUCED', reproduction_blocker=NULL,
		body_md=replace(body_md, '**Reproduction:** none — UNREPRODUCED', '**Reproduction:** reproduced-live — VERIFIED') WHERE atm_id='WIT-350'`); err != nil {
		t.Fatal(err)
	}
	db.Close()
	rc, errOut := captureStderrRun(t, func() int { return validateCmd([]string{"--db", dbPath}) })
	if rc == exitOK || !strings.Contains(errOut, "malformed **Reproduction:** record") {
		t.Fatalf("validate on a malformed record rc=%d stderr=%s", rc, errOut)
	}
	// md-to-db of a malformed record keeps the head state and the bytes.
	raw := "# Issues\n\n## WIT-351 — malformed\n\n**Status:** Queued\n**Type:** Bug\n**Reproduction:** reproduced-live — VERIFIED\n\nx\n"
	in := filepath.Join(dir, "In.md")
	_ = os.WriteFile(in, []byte(raw), 0o644)
	db2 := filepath.Join(dir, "m.db")
	if rc := syncMDToDB([]string{"--db", db2, "--issues", in}); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	out2 := filepath.Join(dir, "Out.md")
	if rc := syncDBToMD([]string{"--db", db2, "--out-issues", out2, "--out-fixed", filepath.Join(dir, "F.md")}); rc != exitOK {
		t.Fatalf("db-to-md exited %d", rc)
	}
	if got, _ := os.ReadFile(out2); string(got) != raw {
		t.Errorf("malformed record not preserved byte-for-byte: %s", firstDiff(raw, string(got)))
	}
	if st := mustItem(t, db2, "WIT-351", "Issues").States.ReproState; st != reproLive {
		t.Errorf("malformed record head state = %q, want reproduced-live (never silently UNSET)", st)
	}
	if rc := validateCmd([]string{"--db", db2}); rc == exitOK {
		t.Error("validate passed a malformed record")
	}
}

// TestStatesCLI_ExportSummaryColumns: both summaries carry the two columns with
// the state, label and the missing-field reasons.
func TestStatesCLI_ExportSummaryColumns(t *testing.T) {
	dbPath := newTestDB(t)
	root := newEvidenceRoot(t)
	ev := materialiseEvidence(t, root, "qa-results/wit360/red.txt")
	closeEv := materialiseEvidence(t, root, "docs/qa/wit361.md")
	if rc := addBug(t, dbPath, "WIT-360", "--reproduction-state", "reproduced-live", "--reproduction-evidence", ev,
		"--investigation-state", "in-progress", "--states-updated-by", "a"); rc != exitOK {
		t.Fatalf("add exited %d", rc)
	}
	if rc := addBug(t, dbPath, "WIT-361", completeLiveFlags(ev)...); rc != exitOK {
		t.Fatalf("add exited %d", rc)
	}
	if rc := closeCmd([]string{"WIT-361", "--db", dbPath, "--status", "fixed", "--evidence", closeEv}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	issues, fixed := exportRoundTrip(t, dbPath)
	if !strings.Contains(issues, "| ATM ID | Type | Status | Severity | Description | Reproduction | Investigation |\n|---|---|---|---|---|---|---|\n") {
		t.Errorf("Issues_Summary header:\n%s", issues)
	}
	if !strings.Contains(issues, "| reproduced-live — UNREPRODUCED (missing surface; missing red-command; missing env; missing signature) | in-progress |\n") {
		t.Errorf("Issues_Summary WIT-360 cells:\n%s", issues)
	}
	if !strings.Contains(fixed, "| # | Level | Status | Type | Fixed-In Tag(s) | One-line description | Reproduction | Investigation |\n|---|---|---|---|---|---|---|---|\n") {
		t.Errorf("Fixed_Summary header:\n%s", fixed)
	}
	if !strings.Contains(fixed, "| reproduced-live — REPRODUCED | UNSET |\n") {
		t.Errorf("Fixed_Summary WIT-361 cells:\n%s", fixed)
	}
	rc, out := captureStdoutRun(t, func() int { return reportCmd([]string{"--db", dbPath, "--by-reproduction"}) })
	if rc != exitOK || !strings.Contains(out, "reproduced-live  2") {
		t.Errorf("report --by-reproduction rc=%d out=%s", rc, out)
	}
}

// TestStatesCLI_PreV8MigrationIsLossless: a populated pre-v8 DB gains the
// columns as UNSET, keeps every row, and re-opening is a no-op.
func TestStatesCLI_PreV8MigrationIsLossless(t *testing.T) {
	for name, path := range map[string]string{"v3": makeV3LikeDB(t), "v5": makeV5LikeDB(t)} {
		for i := 0; i < 2; i++ {
			db := mustOpen(t, path)
			items, err := loadItems(db)
			if err != nil {
				t.Fatalf("%s: loadItems: %v", name, err)
			}
			if len(items) != 3 {
				t.Fatalf("%s: %d items after migration, want 3", name, len(items))
			}
			for _, it := range items {
				if it.States != (stateRecord{}).norm() {
					t.Errorf("%s: %s migrated with state %+v, want UNSET", name, it.AtmID, it.States)
				}
			}
			cols := pragmaColsDB(t, db)
			for _, c := range statesColumnDDL {
				if !cols[c.name] {
					t.Errorf("%s: column %s missing", name, c.name)
				}
			}
			var n int
			_ = db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE name IN ('idx_items_reproduction_state','idx_items_investigation_state','repro_gate_exemptions')`).Scan(&n)
			if n != 3 {
				t.Errorf("%s: %d of 3 states schema objects present", name, n)
			}
			db.Close()
		}
	}
}
