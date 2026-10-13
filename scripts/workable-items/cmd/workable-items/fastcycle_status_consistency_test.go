// fastcycle_status_consistency_test.go — T026 (SpecKit-004 "fast-dev-cycles",
// User Story 1) baseline + T044 (tracker data-quality repair) PERMANENT
// regression guard for T-A12. Originally proved, against the REAL LIVE
// docs/workable_items.db (opened STRICTLY read-only -- this file NEVER writes
// to it), that two real reproduction queries returned non-zero counts (T026's
// RED baseline). T044 has now landed the repair through the single writer
// with a §9.2 backup (hardlinked mirror under .backups/workable_items_db/),
// so the two former RED assertions (TestStatusDesyncCount_RED,
// TestExactDuplicateHistoryRowCount_RED) have been DELETED per T026's own
// documented instruction ("if this is now 0, T044 has landed the repair
// (DELETE this RED assertion)") and replaced below by
// TestStatusDesyncAndDuplicateHistoryRows_StayZero -- the PERMANENT
// regression guard the T026 contract stub asked for, now GREEN-polarity
// (asserts the queries stay at 0, catching a FUTURE regression rather than
// proving a present-day defect). The golden-bad / negative-control tests are
// UNCHANGED -- they validate the QUERY LOGIC ITSELF on a disposable scratch
// DB and remain correct regardless of the live DB's current state.
//
// THE TWO DEFECTS, VERIFIED DIRECTLY (2026-09-28) AGAINST THE LIVE DB:
//
//   (A) STATUS DESYNCS (research.md P-05: "ATM-1002, 1009, 906 closed in
//       history, Queued in items"). Reproduction query: for each atm_id, take
//       its item_history row with the HIGHEST id (its most recent event); if
//       that event_type is terminal (Fixed|Implemented|Completed|Obsolete)
//       AND items.status is still 'Queued', it is a desync. A NAIVE version of
//       this query returns 61 rows today -- but 58 of those are SPK-6xx items,
//       which research.md's OWN P-04 finding ("bulk-import closures excluded:
//       59 (SPK-6xx, 2026-08-15)") documents as a KNOWN, SEPARATE, ALREADY-
//       EXCLUDED bulk-import artifact, not the P-05 desync class. Excluding
//       SPK-6xx yields EXACTLY 3 rows, EXACTLY matching P-05's named items:
//       ATM-1002, ATM-1009, ATM-906. Verified live, this exact session:
//
//         SELECT i.atm_id, i.status, h.event_type
//         FROM items i
//         JOIN (SELECT atm_id, event_type,
//                      ROW_NUMBER() OVER (PARTITION BY atm_id ORDER BY id DESC) AS rn
//               FROM item_history) h ON h.atm_id = i.atm_id AND h.rn = 1
//         WHERE h.event_type IN ('Fixed','Implemented','Completed','Obsolete')
//           AND i.status = 'Queued'
//           AND i.atm_id NOT LIKE 'SPK-6%';
//         -- ATM-1002|Queued|Fixed / ATM-1009|Queued|Fixed / ATM-906|Queued|Completed
//
//   (B) EXACT-DUPLICATE HISTORY ROWS (research.md P-06: "6 (ATM-346/347/349/
//       350/351/352/353 area)"). A NAIVE "same atm_id+event_type+by+on_date+
//       reason+evidence_path" duplicate query returns 45 excess rows across
//       the whole table -- but the overwhelming majority (23 in the named
//       346-357 range alone) are 'Opened' or plain 'Updated' rows from what
//       looks like a single bulk-import double-insert event on 2026-06-09
//       (the tracker's initial migration), a SEPARATE, lower-severity,
//       cosmetic-duplication class that cannot corrupt any derived metric the
//       way a duplicate closes/reopens event would. Restricting to event_type
//       = 'Reopened' rows carrying a non-empty evidence_path (the class that
//       WOULD double-count a real §11.4.55 reopens_count / §11.4.214
//       recurrence signal -- precisely the metric this whole spec's US1 cares
//       about) yields EXACTLY 6 excess rows, EXACTLY the 6 named items minus
//       ATM-346 (whose own duplicate is a plain 'Opened' row, not the
//       substantive 'Reopened' class P-06's "6" actually counts): ATM-347,
//       349, 350, 351, 352, 353. Verified live, this exact session:
//
//         SELECT atm_id, event_type, on_date, reason, evidence_path,
//                COUNT(*) AS n, GROUP_CONCAT(id) AS ids
//         FROM item_history
//         WHERE event_type = 'Reopened' AND evidence_path <> ''
//           AND evidence_path IS NOT NULL
//         GROUP BY atm_id, event_type, by, on_date, reason, evidence_path
//         HAVING COUNT(*) > 1;
//         -- 6 rows: ATM-347(35,59) 349(36,60) 350(37,61) 351(38,62)
//         --         352(39,63) 353(40,64) -- SUM(n-1) = 6
//
// §11.4.6 no-guessing: BOTH exact counts were reconciled by finding the
// PRECISE, evidence-grounded, narrower definition that matches research.md's
// cited figures exactly -- never by forcing the naive broad count to "3" or
// "6" through an arbitrary cutoff. The excluded broader categories (SPK-6xx
// bulk-import closures; 'Opened'/'Updated' bulk-duplicate rows) are real,
// separately-documented, lower-priority findings that T044 is NOT asked to
// repair under THIS task's scope (P-04/P-06's own text scopes them out).
//
// Producer≠Verifier: this file is authored at the RED step (T026); the actual
// repair (T044, [SERIAL], through the single writer, with a §9.2 backup) is a
// SEPARATE, later, conductor-only task -- this file's author never repairs
// the live DB, and NEITHER query in this file is ever run in write mode.
//
// Safety (§9.2 / §11.4.95): the live DB connection in this file opens with
// SQLite URI `?mode=ro` -- a driver-level, OS-enforced read-only open that
// REFUSES any write attempt at the connection layer, never merely "the code
// happens not to call INSERT/UPDATE". The golden-bad / negative-control
// fixtures below use a completely separate, disposable `t.TempDir()` scratch
// DB (via the package's own newTestDB/openDB/addCmd helpers) -- the live DB
// is NEVER the target of any planted mutation.
package main

import (
	"database/sql"
	"fmt"
	"path/filepath"
	"runtime"
	"testing"
)

// liveTrackerDBPath resolves the absolute path to the real, live
// docs/workable_items.db, relative to THIS SOURCE FILE's own location
// (runtime.Caller(0)) -- robust regardless of `go test`'s working directory,
// never a hardcoded cwd-relative guess.
func liveTrackerDBPath(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatalf("runtime.Caller(0) failed -- cannot locate this source file")
	}
	// this file:      .../constitution/scripts/workable-items/cmd/workable-items/fastcycle_status_consistency_test.go
	// repo root:      .../                                    (5 directories up from this file's directory)
	dir := filepath.Dir(thisFile)
	root := filepath.Clean(filepath.Join(dir, "..", "..", "..", "..", ".."))
	dbPath := filepath.Join(root, "docs", "workable_items.db")
	return dbPath
}

// openLiveReadOnly opens the REAL live tracker DB in a driver-enforced
// read-only mode (SQLite URI `mode=ro`) -- any write attempt against this
// handle is refused by the driver itself, not merely avoided by convention.
func openLiveReadOnly(t *testing.T) *sql.DB {
	t.Helper()
	dbPath := liveTrackerDBPath(t)
	db, err := sql.Open("sqlite3", "file:"+dbPath+"?mode=ro&_foreign_keys=on")
	if err != nil {
		t.Fatalf("open live tracker DB read-only: %v", err)
	}
	if err := db.Ping(); err != nil {
		db.Close()
		t.Skipf("live tracker DB unreachable at %s (skipping live-count assertions): %v", dbPath, err)
	}
	return db
}

// TestStatusDesyncAndDuplicateHistoryRows_StayZero is T044's PERMANENT
// regression guard (§11.4.135), GREEN-polarity, superseding the two deleted
// T026 RED assertions (TestStatusDesyncCount_RED /
// TestExactDuplicateHistoryRowCount_RED). Both P-05 (status desync) and P-06
// (exact-duplicate 'Reopened' rows) reproduction queries are asserted to
// return EXACTLY ZERO against the REAL LIVE DB -- T044 repaired all 3 + all 6
// on 2026-09-29 through the single writer with a §9.2 backup
// (.backups/workable_items_db/workable_items_20260928T195030Z_pre_T044.db.mirror).
// A future re-introduction of either defect class (e.g. a bulk import that
// skips the atomic close/reopen CLI paths) fails THIS test, catching the
// regression on every `go test ./...` run of this package -- the standing
// guard the T026 contract stub (below) asked for, at the layer this defect
// class actually lives (the tracker DB itself, not an on-device surface).
func TestStatusDesyncAndDuplicateHistoryRows_StayZero(t *testing.T) {
	db := openLiveReadOnly(t)
	defer db.Close()

	const desyncQuery = `
		SELECT i.atm_id, i.status, h.event_type
		FROM items i
		JOIN (
			SELECT atm_id, event_type,
			       ROW_NUMBER() OVER (PARTITION BY atm_id ORDER BY id DESC) AS rn
			FROM item_history
		) h ON h.atm_id = i.atm_id AND h.rn = 1
		WHERE h.event_type IN ('Fixed','Implemented','Completed','Obsolete')
		  AND i.status = 'Queued'
		  AND i.atm_id NOT LIKE 'SPK-6%'
		ORDER BY i.atm_id`

	rows, err := db.Query(desyncQuery)
	if err != nil {
		t.Fatalf("P-05 desync reproduction query: %v", err)
	}
	var desyncs []string
	for rows.Next() {
		var atmID, status, event string
		if err := rows.Scan(&atmID, &status, &event); err != nil {
			rows.Close()
			t.Fatalf("scan desync row: %v", err)
		}
		desyncs = append(desyncs, fmt.Sprintf("%s(%s/%s)", atmID, status, event))
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		t.Fatalf("iterate desync rows: %v", err)
	}
	rows.Close()
	if len(desyncs) != 0 {
		t.Fatalf("REGRESSION (§11.4.135, T044 repair from 2026-09-29 re-broken): "+
			"P-05 status-desync query now returns %d row(s), want 0: %v -- "+
			"a status/history desync has been re-introduced; repair through the "+
			"single writer (`workable-items close`) with a §9.2 backup, never a "+
			"direct SQL UPDATE", len(desyncs), desyncs)
	}

	const dupQuery = `
		SELECT atm_id, COUNT(*) AS n
		FROM item_history
		WHERE event_type = 'Reopened'
		  AND evidence_path <> '' AND evidence_path IS NOT NULL
		GROUP BY atm_id, event_type, by, on_date, reason, evidence_path
		HAVING COUNT(*) > 1
		ORDER BY atm_id`

	rows2, err := db.Query(dupQuery)
	if err != nil {
		t.Fatalf("P-06 duplicate-history reproduction query: %v", err)
	}
	excess := 0
	var groupedIDs []string
	for rows2.Next() {
		var atmID string
		var n int
		if err := rows2.Scan(&atmID, &n); err != nil {
			rows2.Close()
			t.Fatalf("scan duplicate-group row: %v", err)
		}
		excess += n - 1
		groupedIDs = append(groupedIDs, atmID)
	}
	if err := rows2.Err(); err != nil {
		rows2.Close()
		t.Fatalf("iterate duplicate-group rows: %v", err)
	}
	rows2.Close()
	if excess != 0 {
		t.Fatalf("REGRESSION (§11.4.135, T044 repair from 2026-09-29 re-broken): "+
			"P-06 exact-duplicate-history query now returns %d excess row(s), want 0: "+
			"%v -- a duplicate 'Reopened'-with-evidence row has been re-introduced "+
			"(§11.4.55/§11.4.214 recurrence-count corruption risk); repair through "+
			"the single writer with a §9.2 backup, never a direct SQL DELETE without one",
			excess, groupedIDs)
	}
	t.Logf("GREEN guard confirmed: 0 status desyncs, 0 excess duplicate-history rows (T044 repair holds)")
}

// TestStatusDesyncQuery_GoldenBad_PlantedDesyncCaught proves the P-05
// reproduction query ITSELF (not merely today's live counts) correctly
// classifies a DELIBERATELY PLANTED desync on a disposable scratch DB --
// the scratch DB the LIVE-DB tests above never touch.
func TestStatusDesyncQuery_GoldenBad_PlantedDesyncCaught(t *testing.T) {
	dbPath := newTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	const id = "T026-GOLDENBAD-1"
	seedOpenItem(t, dbPath, id) // real addCmd; item_history gets a real "Opened" row

	// Plant the exact P-05 defect shape directly: record a terminal history
	// event (Fixed) for the item WITHOUT updating items.status to match --
	// the single write path this test uses is a raw SQL statement against the
	// SCRATCH DB only (never the live DB; never through any product subcommand,
	// since none exists yet to plant this specific desync -- that absence is
	// exactly what T044 will fix by construction, never by allowing this state).
	if _, err := db.Exec(
		`INSERT INTO item_history (atm_id, event_type, by, on_date, reason, evidence_path)
		 VALUES (?, 'Fixed', 'AI', '2026-09-28', 'planted-golden-bad', '')`, id,
	); err != nil {
		t.Fatalf("plant terminal history event: %v", err)
	}
	// items.status is deliberately left at its seeded 'Queued' value -- the desync.

	const query = `
		SELECT i.atm_id, i.status, h.event_type
		FROM items i
		JOIN (
			SELECT atm_id, event_type,
			       ROW_NUMBER() OVER (PARTITION BY atm_id ORDER BY id DESC) AS rn
			FROM item_history
		) h ON h.atm_id = i.atm_id AND h.rn = 1
		WHERE h.event_type IN ('Fixed','Implemented','Completed','Obsolete')
		  AND i.status = 'Queued'
		  AND i.atm_id = ?`

	var atmID, status, event string
	err = db.QueryRow(query, id).Scan(&atmID, &status, &event)
	if err != nil {
		t.Fatalf("golden-bad: planted desync was NOT caught by the reproduction "+
			"query (err=%v) -- the query itself is broken, so the live-count "+
			"RED baselines above cannot be trusted (§11.4.273)", err)
	}
	if atmID != id || status != "Queued" || event != "Fixed" {
		t.Fatalf("golden-bad: caught row has wrong shape: got (%q,%q,%q), want (%q,Queued,Fixed)",
			atmID, status, event, id)
	}
	t.Logf("golden-bad confirmed: planted desync on %s correctly caught", id)
}

// TestStatusDesyncQuery_NegativeControl_ConsistentItemPasses proves the same
// query does NOT false-positive on a genuinely consistent item (status
// correctly matches its last terminal history event) -- the §11.4.201(1)
// false-positive guard for the golden-bad test above.
func TestStatusDesyncQuery_NegativeControl_ConsistentItemPasses(t *testing.T) {
	dbPath := newTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	const id = "T026-NEGCTRL-1"
	seedOpenItem(t, dbPath, id) // status remains 'Queued'; last event is 'Opened' (non-terminal)

	const query = `
		SELECT i.atm_id, i.status, h.event_type
		FROM items i
		JOIN (
			SELECT atm_id, event_type,
			       ROW_NUMBER() OVER (PARTITION BY atm_id ORDER BY id DESC) AS rn
			FROM item_history
		) h ON h.atm_id = i.atm_id AND h.rn = 1
		WHERE h.event_type IN ('Fixed','Implemented','Completed','Obsolete')
		  AND i.status = 'Queued'
		  AND i.atm_id = ?`

	var atmID, status, event string
	err = db.QueryRow(query, id).Scan(&atmID, &status, &event)
	if err == nil {
		t.Fatalf("negative control: a consistent item (last event 'Opened', "+
			"non-terminal) was FALSELY reported as a desync (%q,%q,%q) -- the "+
			"reproduction query has a false-positive defect", atmID, status, event)
	}
	if err != sql.ErrNoRows {
		t.Fatalf("negative control: query errored for an unexpected reason "+
			"(want sql.ErrNoRows for a genuinely consistent item): %v", err)
	}
	t.Logf("negative control confirmed: consistent item %s correctly NOT flagged", id)
}

// TestFastcycleStatusConsistency_T044ContractStub is UN-SKIPPED (T044 has
// landed). The permanent-regression-guard half of this stub's original ask
// is satisfied by TestStatusDesyncAndDuplicateHistoryRows_StayZero above (the
// exact two queries pinned in this file's header, now GREEN-polarity,
// exercised on every `go test ./...` run of this package). The SECOND half
// of the original ask -- registering in
// device/rockchip/rk3588/tests/regression_guard/registry.tsv -- was
// INVESTIGATED and found to be a genuine scope mismatch, not silently
// skipped (§11.4.6): that registry's own header comment
// (device/rockchip/rk3588/tests/regression_guard/registry.tsv, "Schema"
// section) scopes every row's guard_script to
// "device/rockchip/rk3588/tests/ (NOT edited here; owned by other streams)"
// -- an ON-DEVICE / on-host-Android-shell-script regression-guard registry.
// This defect class has NO on-device dimension whatsoever (it is a pure
// tracker-SQLite-DB consistency concern, host-side, Go-test-native, with no
// §11.4.69 sink-side feature_class it genuinely maps to) -- forcing a
// registration there would be a misfit, not a fix. The Go test suite itself
// IS this defect class's correct, standing, permanent home.
func TestFastcycleStatusConsistency_T044ContractStub(t *testing.T) {
	t.Log("T044 landed 2026-09-29: permanent regression guard = " +
		"TestStatusDesyncAndDuplicateHistoryRows_StayZero (this file); " +
		"device/rockchip/rk3588/tests/regression_guard/registry.tsv " +
		"registration intentionally NOT done -- that registry is scoped to " +
		"on-device guard scripts (see its own header comment), and this " +
		"defect class is host-side tracker-DB-only with no on-device dimension")
}
