// states_cli.go — the CLI surface of the §11.4.292 reproduction / investigation
// states: the shared `add` / `update` flags, the closure-gate loader, and the
// `states` subcommand (`freeze`, `import`).
package main

import (
	"bufio"
	"database/sql"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// stateFlagNames are the state flags `add` and `update` accept.
var stateFlagNames = []string{
	"reproduction-state", "reproduction-surface", "reproduction-evidence",
	"reproduction-red-cmd", "reproduction-green-cmd", "reproduction-env",
	"reproduction-signature", "reproduction-blocker",
	"investigation-state", "investigation-root-cause", "investigation-evidence",
	"states-updated-by", "states-updated-at",
}

type stateFlags struct {
	v map[string]*string
}

func registerStateFlags(fs *flag.FlagSet) *stateFlags {
	help := map[string]string{
		"reproduction-state":       "§11.4.292 reproduction state: " + strings.Join(reproStates, " | ") + " (alias blocked-no-device)",
		"reproduction-surface":     "defect surface: live-target | host-only (\"\" clears)",
		"reproduction-evidence":    "captured RED (or non-reproduction) evidence path; must resolve",
		"reproduction-red-cmd":     "exact RED command (§11.4.292(C)(1))",
		"reproduction-green-cmd":   "GREEN command (the same command, polarity flipped)",
		"reproduction-env":         "environment / target identity: board serial, image id, fixture sha256",
		"reproduction-signature":   "symptom signature (the predicate that reads TRUE while the defect is present)",
		"reproduction-blocker":     "recorded blocker (required for blocked-no-device-with-recorded-blocker)",
		"investigation-state":      "investigation state: " + strings.Join(investigationStates, " | "),
		"investigation-root-cause": "root cause text (required for root-cause-found-with-evidence)",
		"investigation-evidence":   "root-cause / no-defect evidence path; must resolve",
		"states-updated-by":        "who records the state change (required with any state flag)",
		"states-updated-at":        "RFC 3339 UTC time of the state change (default: now)",
	}
	sf := &stateFlags{v: map[string]*string{}}
	for _, n := range stateFlagNames {
		sf.v[n] = fs.String(n, "", help[n])
	}
	return sf
}

// anySet reports whether at least one state flag was given.
func (sf *stateFlags) anySet(set map[string]bool) bool {
	for _, n := range stateFlagNames {
		if set[n] {
			return true
		}
	}
	return false
}

// apply returns cur with the explicitly-set flags applied. A block whose
// content changes gets updated_at / updated_by stamped. Setting a state to
// UNSET clears that block's details (they would have no line to live on).
// Values are trimmed; closed sets and formats are checked; the evidence
// requirements are checked by the caller (stateRecordProblems).
func (sf *stateFlags) apply(cur stateRecord, set map[string]bool, now time.Time) (stateRecord, string, error) {
	cur = cur.norm()
	r := cur
	get := func(n string) string { return strings.TrimSpace(*sf.v[n]) }
	if !sf.anySet(set) {
		return r, "", nil
	}
	by := get("states-updated-by")
	if by == "" {
		return r, "", fmt.Errorf("--states-updated-by is required with any reproduction/investigation flag (attribution, §11.4.34)")
	}
	at := recordStatesTimestamp(now)
	if set["states-updated-at"] {
		at = get("states-updated-at")
		if err := checkTimestamp("--states-updated-at", at); err != nil {
			return r, "", err
		}
	}
	if set["reproduction-state"] {
		v, ok := normalizeReproStateInput(get("reproduction-state"))
		if !ok {
			return r, "", fmt.Errorf("--reproduction-state %q not in closed set {%s} (alias blocked-no-device)", get("reproduction-state"), strings.Join(reproStates, ", "))
		}
		r.ReproState = v
	}
	if set["investigation-state"] {
		v, ok := normalizeInvStateInput(get("investigation-state"))
		if !ok {
			return r, "", fmt.Errorf("--investigation-state %q not in closed set {%s}", get("investigation-state"), strings.Join(investigationStates, ", "))
		}
		r.InvState = v
	}
	if set["reproduction-surface"] {
		v := get("reproduction-surface")
		if v != "" && !inSet(v, reproSurfaces) {
			return r, "", fmt.Errorf("--reproduction-surface %q not in closed set {%s}", v, strings.Join(reproSurfaces, ", "))
		}
		r.ReproSurface = v
	}
	for flagName, dst := range map[string]*string{
		"reproduction-evidence":    &r.ReproEvidence,
		"reproduction-red-cmd":     &r.ReproRedCmd,
		"reproduction-green-cmd":   &r.ReproGreenCmd,
		"reproduction-env":         &r.ReproEnv,
		"reproduction-signature":   &r.ReproSignature,
		"reproduction-blocker":     &r.ReproBlocker,
		"investigation-root-cause": &r.InvRootCause,
		"investigation-evidence":   &r.InvEvidence,
	} {
		if set[flagName] {
			v := get(flagName)
			if err := checkStateValue("--"+flagName, v); err != nil {
				return r, "", err
			}
			*dst = v
		}
	}
	if r.ReproState == stateUnset {
		for _, n := range []string{"reproduction-surface", "reproduction-evidence", "reproduction-red-cmd",
			"reproduction-green-cmd", "reproduction-env", "reproduction-signature", "reproduction-blocker"} {
			if set[n] && get(n) != "" {
				return r, "", fmt.Errorf("--%s needs a reproduction state other than UNSET", n)
			}
		}
		r.copyRepro(stateRecord{ReproState: stateUnset})
	}
	if r.InvState == stateUnset {
		for _, n := range []string{"investigation-root-cause", "investigation-evidence"} {
			if set[n] && get(n) != "" {
				return r, "", fmt.Errorf("--%s needs an investigation state other than UNSET", n)
			}
		}
		r.copyInv(stateRecord{InvState: stateUnset})
	}
	return stampStates(cur, r, by, at)
}

// stampStates sets updated_at / updated_by on each block whose content differs
// from cur (and is not UNSET), and returns a one-line audit reason.
func stampStates(cur, r stateRecord, by, at string) (stateRecord, string, error) {
	cur, r = cur.norm(), r.norm()
	reproKey := func(s stateRecord) stateRecord {
		s.ReproUpdatedAt, s.ReproUpdatedBy = "", ""
		var o stateRecord
		o.copyRepro(s)
		return o
	}
	invKey := func(s stateRecord) stateRecord {
		s.InvUpdatedAt, s.InvUpdatedBy = "", ""
		var o stateRecord
		o.copyInv(s)
		return o
	}
	var why []string
	if reproKey(cur) != reproKey(r) {
		r.ReproUpdatedAt, r.ReproUpdatedBy = "", ""
		if r.ReproState != stateUnset {
			r.ReproUpdatedAt, r.ReproUpdatedBy = at, by
		}
		why = append(why, fmt.Sprintf("reproduction %s -> %s", cur.ReproState, r.ReproState))
	} else {
		// Unchanged content keeps its original stamps.
		r.ReproUpdatedAt, r.ReproUpdatedBy = cur.ReproUpdatedAt, cur.ReproUpdatedBy
	}
	if invKey(cur) != invKey(r) {
		r.InvUpdatedAt, r.InvUpdatedBy = "", ""
		if r.InvState != stateUnset {
			r.InvUpdatedAt, r.InvUpdatedBy = at, by
		}
		why = append(why, fmt.Sprintf("investigation %s -> %s", cur.InvState, r.InvState))
	} else {
		r.InvUpdatedAt, r.InvUpdatedBy = cur.InvUpdatedAt, cur.InvUpdatedBy
	}
	if err := checkRecordFormats(r); err != nil {
		return r, "", err
	}
	return r, strings.Join(why, "; "), nil
}

// ---- closure gate -----------------------------------------------------------

// loadClosureGate reads the arming marker, the exemptions and the §11.4.90
// obsolete reasons.
func loadClosureGate(db *sql.DB) (closureGate, error) {
	g := closureGate{exempt: map[string]string{}, obsoleteReason: map[string]string{}}
	var armedAt string
	err := db.QueryRow(`SELECT value FROM meta WHERE key='repro_gate_armed_at'`).Scan(&armedAt)
	switch {
	case err == sql.ErrNoRows:
	case err != nil:
		return g, err
	default:
		g.armed = armedAt != ""
	}
	rows, err := db.Query(`SELECT atm_id, representation, status FROM repro_gate_exemptions`)
	if err != nil {
		return g, err
	}
	for rows.Next() {
		var id, rep, st string
		if err := rows.Scan(&id, &rep, &st); err != nil {
			rows.Close()
			return g, err
		}
		g.exempt[id+"\x00"+rep] = st
	}
	rows.Close()
	rows, err = db.Query(`SELECT atm_id, reason FROM obsolete_details`)
	if err != nil {
		return g, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, reason string
		if err := rows.Scan(&id, &reason); err != nil {
			return g, err
		}
		g.obsoleteReason[id] = reason
	}
	return g, rows.Err()
}

// preventiveClosureCheck evaluates the closure invariants for an item that is
// ABOUT to sit at Fixed with status newStatus. A new closure is never
// grandfathered (no exemption). Obsolete closures are left to `validate`
// (their §11.4.90 reason is recorded only after the close). A VERIFIED closure
// additionally requires the record itself to be valid (evidence resolves).
func preventiveClosureCheck(db *sql.DB, it item, newStatus string, keepExemption bool) []string {
	if !verifiedClosureStatus(newStatus) {
		return nil
	}
	g, err := loadClosureGate(db)
	if err != nil {
		return []string{"closure gate: " + err.Error()}
	}
	if !keepExemption {
		g.exempt = map[string]string{}
	}
	target := it
	target.Status = newStatus
	target.CurrentLocation = "Fixed"
	out := closureReproProblems(target, g)
	if it.States.norm().ReproState != stateUnset {
		for _, p := range stateRecordProblems(it.States, true) {
			out = append(out, it.AtmID+": "+p)
		}
	}
	return out
}

// ---- `states` subcommand ------------------------------------------------------

func runStates(args []string) { os.Exit(statesCmd(args)) }

func statesCmd(args []string) int {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "states: missing action (freeze | import)")
		return exitUsage
	}
	switch args[0] {
	case "freeze":
		return statesFreezeCmd(args[1:])
	case "import":
		return statesImportCmd(args[1:])
	default:
		fmt.Fprintf(os.Stderr, "states: unknown action %q (freeze | import)\n", args[0])
		return exitUsage
	}
}

// statesFreezeCmd ARMS the reproduction closure gate, once. Every item that is
// already closed (Fixed location, terminal status) and would fail the armed
// checks C2/C3 today is recorded in repro_gate_exemptions with its current
// status; every later closure is checked. A second run is refused (re-freezing
// would grandfather new violations).
func statesFreezeCmd(args []string) int {
	fs := flag.NewFlagSet("states freeze", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	by := fs.String("by", "", "who arms the gate (required)")
	at := fs.String("at", "", "RFC 3339 UTC arming time (default: now)")
	dryRun := fs.Bool("dry-run", false, "report what would be exempted; write nothing")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" || strings.TrimSpace(*by) == "" {
		fmt.Fprintln(os.Stderr, "states freeze: --db and --by are required")
		return exitUsage
	}
	when := recordStatesTimestamp(time.Now())
	if *at != "" {
		if err := checkTimestamp("--at", *at); err != nil {
			fmt.Fprintf(os.Stderr, "states freeze: %v\n", err)
			return exitUsage
		}
		when = *at
	}
	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "states freeze: %v\n", err)
		return exitUsage
	}
	defer db.Close()
	g, err := loadClosureGate(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "states freeze: %v\n", err)
		return exitUsage
	}
	if g.armed {
		fmt.Fprintln(os.Stderr, "states freeze: the reproduction closure gate is already armed; refusing to re-freeze (a second freeze would grandfather new violations)")
		return exitUsage
	}
	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "states freeze: %v\n", err)
		return exitUsage
	}
	armedGate := g
	armedGate.armed = true
	var exempt []item
	for _, it := range items {
		if len(closureReproProblems(it, armedGate)) > 0 && len(closureReproProblems(it, g)) == 0 {
			exempt = append(exempt, it)
		}
	}
	// C1 problems exist regardless of arming; freezing does not hide them.
	var c1 []string
	for _, it := range items {
		c1 = append(c1, closureReproProblems(it, g)...)
	}
	fmt.Printf("states freeze: %d closed item(s) would be exempted (closed before arming, no reproduction record); %d unconditional closure problem(s) stay reported by validate\n", len(exempt), len(c1))
	if *dryRun {
		for _, it := range exempt {
			fmt.Printf("  exempt %s [%s] %s\n", it.AtmID, it.repOrDefault(), it.Status)
		}
		fmt.Println("states freeze: --dry-run, nothing written")
		return exitOK
	}
	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "states freeze: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()
	for _, it := range exempt {
		if _, err := tx.Exec(`INSERT INTO repro_gate_exemptions (atm_id, representation, status, frozen_at) VALUES (?,?,?,?)`,
			it.AtmID, it.repOrDefault(), it.Status, when); err != nil {
			fmt.Fprintf(os.Stderr, "states freeze: exempt %s: %v\n", it.AtmID, err)
			return exitUsage
		}
	}
	for k, v := range map[string]string{"repro_gate_armed_at": when, "repro_gate_armed_by": strings.TrimSpace(*by)} {
		// OR REPLACE: an empty-valued marker counts as not armed (loadClosureGate).
		if _, err := tx.Exec(`INSERT OR REPLACE INTO meta(key, value, last_modified) VALUES (?,?,datetime('now'))`, k, v); err != nil {
			fmt.Fprintf(os.Stderr, "states freeze: meta %s: %v\n", k, err)
			return exitUsage
		}
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "states freeze: commit: %v\n", err)
		return exitUsage
	}
	fmt.Printf("states freeze: gate armed at %s by %s; %d exemption(s) recorded\n", when, strings.TrimSpace(*by), len(exempt))
	return exitOK
}

// importColumns is the canonical header of a `states import` TSV. Every column
// except atm_id may be empty (see importRecord for what an empty cell means).
var importColumns = []string{
	"atm_id", "location", "reproduction_state", "reproduction_surface",
	"reproduction_evidence", "reproduction_red_cmd", "reproduction_green_cmd",
	"reproduction_env", "reproduction_signature", "reproduction_blocker",
	"investigation_state", "investigation_root_cause", "investigation_evidence",
}

// statesImportCmd applies a canonical TSV of states in ONE transaction
// (all-or-nothing). Per block, a non-empty state cell REPLACES that record with
// exactly the row's values and an empty state cell leaves it as stored
// (importRecord); a row equal to the stored record is a no-op (idempotent
// re-run). Every row is checked before anything is
// written: unknown or ambiguous item, a pipe-table row, closed sets, formats,
// evidence resolution, a malformed record already in the body, and the
// closure invariants for the item's current status.
func statesImportCmd(args []string) int {
	fs := flag.NewFlagSet("states import", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	tsvPath := fs.String("tsv", "", "canonical states TSV (header: "+strings.Join(importColumns, ",")+")")
	by := fs.String("by", "", "who records the states (required)")
	at := fs.String("at", "", "RFC 3339 UTC time stamped on changed records (default: now)")
	dryRun := fs.Bool("dry-run", false, "check every row; write nothing")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" || *tsvPath == "" || strings.TrimSpace(*by) == "" {
		fmt.Fprintln(os.Stderr, "states import: --db, --tsv and --by are required")
		return exitUsage
	}
	when := recordStatesTimestamp(time.Now())
	if *at != "" {
		if err := checkTimestamp("--at", *at); err != nil {
			fmt.Fprintf(os.Stderr, "states import: %v\n", err)
			return exitUsage
		}
		when = *at
	}
	rows, err := readStatesTSV(resolveInvocationRelative(*tsvPath))
	if err != nil {
		fmt.Fprintf(os.Stderr, "states import: %v\n", err)
		return exitUsage
	}
	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "states import: %v\n", err)
		return exitUsage
	}
	defer db.Close()
	g, err := loadClosureGate(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "states import: %v\n", err)
		return exitUsage
	}

	type planned struct {
		it      item
		rec     stateRecord
		body    string
		reason  string
		changed bool
	}
	var plan []planned
	var problems []string
	seen := map[string]int{}
	for _, row := range rows {
		id := row.cells["atm_id"]
		if prev, dup := seen[id]; dup {
			problems = append(problems, fmt.Sprintf("line %d: %s already given on line %d", row.line, id, prev))
			continue
		}
		seen[id] = row.line
		it, perr := resolveImportItem(db, id, row.cells["location"])
		if perr != "" {
			problems = append(problems, fmt.Sprintf("line %d: %s", row.line, perr))
			continue
		}
		if it.repOrDefault() != "section" {
			problems = append(problems, fmt.Sprintf("line %d: %s is a pipe-table row, which cannot carry a record", row.line, id))
			continue
		}
		if bp := parseStateLines(it.BodyMD).problems; len(bp) > 0 {
			problems = append(problems, fmt.Sprintf("line %d: %s body already carries a malformed record: %s", row.line, id, strings.Join(bp, "; ")))
			continue
		}
		rec, rerr := importRecord(row.cells, it.States)
		if rerr != nil {
			problems = append(problems, fmt.Sprintf("line %d: %s: %v", row.line, id, rerr))
			continue
		}
		// stampStates keeps the existing stamps of an unchanged block.
		stamped, why, serr := stampStates(it.States, rec, strings.TrimSpace(*by), when)
		if serr != nil {
			problems = append(problems, fmt.Sprintf("line %d: %s: %v", row.line, id, serr))
			continue
		}
		for _, p := range stateRecordProblems(stamped, true) {
			problems = append(problems, fmt.Sprintf("line %d: %s: %s", row.line, id, p))
		}
		after := *it
		after.States = stamped
		for _, p := range closureReproProblems(after, g) {
			problems = append(problems, fmt.Sprintf("line %d: %s", row.line, p))
		}
		plan = append(plan, planned{
			it: *it, rec: stamped, reason: why, changed: why != "",
			body: ensureTrailingNewline(canonicalizeStateLines(it.BodyMD, stamped, it.repOrDefault())),
		})
	}
	if len(problems) > 0 {
		fmt.Fprintf(os.Stderr, "states import: %d problem(s); nothing written:\n", len(problems))
		for _, p := range problems {
			fmt.Fprintf(os.Stderr, "  - %s\n", p)
		}
		return exitUsage
	}
	counts := map[string]int{}
	changed := 0
	for _, p := range plan {
		counts["reproduction="+p.rec.ReproState]++
		counts["investigation="+p.rec.InvState]++
		if p.changed {
			changed++
		}
	}
	fmt.Printf("states import: %d row(s), %d change(s), %d unchanged\n", len(plan), changed, len(plan)-changed)
	for _, k := range sortedKeys(counts) {
		fmt.Printf("  %s %d\n", k, counts[k])
	}
	if *dryRun {
		fmt.Println("states import: --dry-run, nothing written")
		return exitOK
	}
	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "states import: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()
	src := filepath.Base(*tsvPath)
	for _, p := range plan {
		if !p.changed {
			continue
		}
		args := append(statesInsertArgs(p.rec), p.body, p.it.AtmID, p.it.CurrentLocation, p.it.repOrDefault())
		res, err := tx.Exec(`UPDATE items SET `+statesUpdateSet+`, body_md=?, last_modified=datetime('now')
			WHERE atm_id=? AND current_location=? AND representation=?`, args...)
		if err != nil {
			fmt.Fprintf(os.Stderr, "states import: update %s: %v\n", p.it.AtmID, err)
			return exitUsage
		}
		if n, _ := res.RowsAffected(); n != 1 {
			fmt.Fprintf(os.Stderr, "states import: update %s affected %d rows (expected 1)\n", p.it.AtmID, n)
			return exitUsage
		}
		if err := recordHistory(tx, p.it.AtmID, "Updated", "AI", "states import "+src+": "+p.reason, ""); err != nil {
			fmt.Fprintf(os.Stderr, "states import: history %s: %v\n", p.it.AtmID, err)
			return exitUsage
		}
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "states import: commit: %v\n", err)
		return exitUsage
	}
	fmt.Printf("states import: applied %d change(s) from %s\n", changed, src)
	return exitOK
}

type statesTSVRow struct {
	line  int
	cells map[string]string
}

// readStatesTSV reads a canonical states TSV: the exact header, tab-separated,
// no quoting, one item per line.
func readStatesTSV(path string) ([]statesTSVRow, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<24)
	var out []statesTSVRow
	n := 0
	for sc.Scan() {
		n++
		line := strings.TrimSuffix(sc.Text(), "\r")
		cols := strings.Split(line, "\t")
		if n == 1 {
			if strings.Join(cols, ",") != strings.Join(importColumns, ",") {
				return nil, fmt.Errorf("%s: header must be exactly %q", path, strings.Join(importColumns, "\\t"))
			}
			continue
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		if len(cols) != len(importColumns) {
			return nil, fmt.Errorf("%s line %d: %d columns, want %d", path, n, len(cols), len(importColumns))
		}
		row := statesTSVRow{line: n, cells: map[string]string{}}
		for i, c := range importColumns {
			row.cells[c] = strings.TrimSpace(cols[i])
		}
		if row.cells["atm_id"] == "" {
			return nil, fmt.Errorf("%s line %d: empty atm_id", path, n)
		}
		out = append(out, row)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if n == 0 {
		return nil, fmt.Errorf("%s: empty file (no header)", path)
	}
	return out, nil
}

// importRecord builds the record a TSV row asks for, starting from the item's
// current record cur. Per block: an EMPTY state cell leaves that block exactly
// as stored (its detail cells must then be empty too); a non-empty state cell
// REPLACES the block with exactly the row's values (write `UNSET` to clear a
// block). Closed sets and formats are checked.
func importRecord(c map[string]string, cur stateRecord) (stateRecord, error) {
	r := cur.norm()
	reproDetailCells := []string{"reproduction_surface", "reproduction_evidence", "reproduction_red_cmd",
		"reproduction_green_cmd", "reproduction_env", "reproduction_signature", "reproduction_blocker"}
	invDetailCells := []string{"investigation_root_cause", "investigation_evidence"}
	anyCell := func(cols []string) string {
		for _, k := range cols {
			if c[k] != "" {
				return k
			}
		}
		return ""
	}
	if v := c["reproduction_state"]; v == "" {
		if k := anyCell(reproDetailCells); k != "" {
			return r, fmt.Errorf("%s is set but reproduction_state is empty (an empty state cell leaves the block unchanged)", k)
		}
	} else {
		s, ok := normalizeReproStateInput(v)
		if !ok {
			return r, fmt.Errorf("reproduction_state %q not in closed set {%s} (alias blocked-no-device)", v, strings.Join(reproStates, ", "))
		}
		r.copyRepro(stateRecord{
			ReproState: s, ReproSurface: c["reproduction_surface"], ReproEvidence: c["reproduction_evidence"],
			ReproRedCmd: c["reproduction_red_cmd"], ReproGreenCmd: c["reproduction_green_cmd"],
			ReproEnv: c["reproduction_env"], ReproSignature: c["reproduction_signature"],
			ReproBlocker: c["reproduction_blocker"],
		})
	}
	if v := c["investigation_state"]; v == "" {
		if k := anyCell(invDetailCells); k != "" {
			return r, fmt.Errorf("%s is set but investigation_state is empty (an empty state cell leaves the block unchanged)", k)
		}
	} else {
		s, ok := normalizeInvStateInput(v)
		if !ok {
			return r, fmt.Errorf("investigation_state %q not in closed set {%s}", v, strings.Join(investigationStates, ", "))
		}
		r.copyInv(stateRecord{InvState: s, InvRootCause: c["investigation_root_cause"], InvEvidence: c["investigation_evidence"]})
	}
	r = r.norm()
	if err := checkRecordFormats(r); err != nil {
		return r, err
	}
	return r, nil
}

// resolveImportItem finds the item a row names: the given location, or Issues
// then Fixed when the cell is empty (refusing an id present in both).
func resolveImportItem(db *sql.DB, id, location string) (*item, string) {
	switch location {
	case "Issues", "Fixed":
		it, err := loadItem(db, id, location)
		if err != nil {
			return nil, err.Error()
		}
		if it == nil {
			return nil, fmt.Sprintf("%s not found in %s", id, location)
		}
		return it, ""
	case "":
		iss, err := loadItem(db, id, "Issues")
		if err != nil {
			return nil, err.Error()
		}
		fix, err := loadItem(db, id, "Fixed")
		if err != nil {
			return nil, err.Error()
		}
		switch {
		case iss != nil && fix != nil:
			return nil, fmt.Sprintf("%s exists in both Issues and Fixed; give the location column", id)
		case iss != nil:
			return iss, ""
		case fix != nil:
			return fix, ""
		}
		return nil, fmt.Sprintf("%s not found in Issues or Fixed", id)
	default:
		return nil, fmt.Sprintf("location %q must be Issues, Fixed or empty", location)
	}
}
