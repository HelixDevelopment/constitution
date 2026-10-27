// diary.go — §11.4.149 per-workable-item testing diary tooling.
//
// A test run against an item (or an ATM-NNN-SSS session sub-task) is recorded as
// ONE append-only test_diary row. The diary is the in-depth forensic record a
// future fix needs; the summary is a DERIVED rollup (the test_diary_summary
// VIEW, never a second source of truth — §11.4.93). Deterministic bash/Go —
// ZERO LLM in the data path (the observations prose is authored by whoever ran
// the test; the tooling only stores / renders / validates it).
//
// Design source: docs/research/forgettable_sync/WORKABLE_ITEMS_DIARY_DESIGN.md §1-2
//                + SUBTASK_HIERARCHY_DESIGN.md §4.
//
// Commands:
//
//	diary-add --subtask ID --tested-by W --result R --observations-file F
//	          [--result-detail D] [--action A] [--status-from S --status-to T]
//	          [--evidence P] [--feature-class C] [--date-time ISO] [--db p]
//	summary-gen {--subtask ID | --all} [--db p]
//	subtask-export {--subtask ID | --parent ID | --all} [--out-dir d] [--db p]
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var diaryTestedBy = map[string]bool{"User": true, "Operator": true, "AI-agent": true, "HelixQA": true}
var diaryResults = map[string]bool{"PASS": true, "FAIL": true, "SKIP": true}

// runDiaryAdd implements `diary-add` (see file header for flags).
func runDiaryAdd(args []string) { os.Exit(diaryAddCmd(args)) }

func diaryAddCmd(args []string) int {
	fs := flag.NewFlagSet("diary-add", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	atm := fs.String("subtask", "", "item OR ATM-NNN-SSS sub-task id the run targets")
	atmAlt := fs.String("atm", "", "alias for --subtask")
	testedBy := fs.String("tested-by", "", "User | Operator | AI-agent | HelixQA")
	result := fs.String("result", "", "PASS | FAIL | SKIP")
	resultDetail := fs.String("result-detail", "", "short verdict detail")
	obsFile := fs.String("observations-file", "", "file with in-depth observations (markdown)")
	obsInline := fs.String("observations", "", "inline observations (alternative to --observations-file)")
	action := fs.String("action", "", "action taken (status change or not, + why)")
	statusFrom := fs.String("status-from", "", "status before this run (when it changed)")
	statusTo := fs.String("status-to", "", "status after this run (when it changed)")
	evidence := fs.String("evidence", "", "§11.4.69 captured-evidence path (REQUIRED for PASS)")
	featureClass := fs.String("feature-class", "", "§11.4.69 sink-side feature class")
	dateTime := fs.String("date-time", "", "ISO-8601 UTC run time (default: now)")
	_, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}

	id := strings.TrimSpace(firstNonEmpty(*atm, *atmAlt))
	if id == "" {
		fmt.Fprintln(os.Stderr, "diary-add: --subtask (or --atm) is required")
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "diary-add: --db is required")
		return exitUsage
	}
	tb := strings.TrimSpace(*testedBy)
	if !diaryTestedBy[tb] {
		fmt.Fprintln(os.Stderr, "diary-add: --tested-by must be one of: User | Operator | AI-agent | HelixQA")
		return exitUsage
	}
	res := strings.ToUpper(strings.TrimSpace(*result))
	if !diaryResults[res] {
		fmt.Fprintln(os.Stderr, "diary-add: --result must be one of: PASS | FAIL | SKIP")
		return exitUsage
	}
	ev := strings.TrimSpace(*evidence)
	// §11.4.69: a PASS without evidence is a PASS-bluff — refuse pre-insert (the
	// schema CHECK is the belt; this is the suspenders + a clear message).
	if res == "PASS" && ev == "" {
		fmt.Fprintln(os.Stderr, "diary-add: a PASS run REQUIRES --evidence (§11.4.69 — a PASS without captured evidence is a bluff)")
		return exitUsage
	}

	obs := strings.TrimSpace(*obsInline)
	if strings.TrimSpace(*obsFile) != "" {
		b, err := os.ReadFile(*obsFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diary-add: read --observations-file: %v\n", err)
			return exitUsage
		}
		obs = strings.TrimSpace(string(b))
	}
	if obs == "" {
		fmt.Fprintln(os.Stderr, "diary-add: observations are required (--observations-file or --observations)")
		return exitUsage
	}

	dt := strings.TrimSpace(*dateTime)
	if dt == "" {
		dt = time.Now().UTC().Format(time.RFC3339)
	}
	act := strings.TrimSpace(*action)
	if act == "" {
		act = "status unchanged"
	}
	statusChanged := 0
	if strings.TrimSpace(*statusFrom) != "" || strings.TrimSpace(*statusTo) != "" {
		statusChanged = 1
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary-add: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	// §11.4.6 soft-FK: the diary target id MUST exist as an item / sub-task.
	exists, err := itemExistsAnyLocation(db, id)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary-add: %v\n", err)
		return exitUsage
	}
	if !exists {
		fmt.Fprintf(os.Stderr, "diary-add: target %s not found in items (a diary entry needs an existing item / sub-task)\n", id)
		return exitUsage
	}

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary-add: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	res2 := tx.QueryRow(`INSERT INTO test_diary
		(atm_id, date_time, tested_by, result, result_detail, observations,
		 action_taken, status_changed, status_from, status_to, evidence_path, feature_class)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?) RETURNING entry_id`,
		id, dt, tb, res, nullable(*resultDetail), obs,
		act, statusChanged, nullable(*statusFrom), nullable(*statusTo),
		nullable(ev), nullable(*featureClass))
	var entryID int64
	if err := res2.Scan(&entryID); err != nil {
		fmt.Fprintf(os.Stderr, "diary-add: insert diary row: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "diary-add: commit: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("diary-add: recorded entry_id=%d on %s (%s, tested_by=%s)\n", entryID, id, res, tb)
	return exitOK
}

// diaryRow is one in-memory test_diary record.
type diaryRow struct {
	EntryID      int64
	AtmID        string
	DateTime     string
	TestedBy     string
	Result       string
	ResultDetail string
	Observations string
	ActionTaken  string
	StatusFrom   string
	StatusTo     string
	EvidencePath string
	FeatureClass string
}

// loadDiary returns every diary row for atm_id, newest first.
func loadDiary(db *sql.DB, id string) ([]diaryRow, error) {
	rows, err := db.Query(`SELECT entry_id, atm_id, date_time, tested_by, result,
		COALESCE(result_detail,''), observations, action_taken,
		COALESCE(status_from,''), COALESCE(status_to,''),
		COALESCE(evidence_path,''), COALESCE(feature_class,'')
		FROM test_diary WHERE atm_id=? ORDER BY date_time DESC, entry_id DESC`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []diaryRow
	for rows.Next() {
		var r diaryRow
		if err := rows.Scan(&r.EntryID, &r.AtmID, &r.DateTime, &r.TestedBy, &r.Result,
			&r.ResultDetail, &r.Observations, &r.ActionTaken, &r.StatusFrom, &r.StatusTo,
			&r.EvidencePath, &r.FeatureClass); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// diarySummary is the test_diary_summary VIEW row.
type diarySummary struct {
	AtmID         string
	TotalRuns     int
	PassRuns      int
	FailRuns      int
	SkipRuns      int
	LastRun       string
	LastResult    string
	StatusChanges int
	Testers       string
	FeatureClasses string
}

// loadSummary returns the rollup for id (zero-valued when no diary rows exist).
func loadSummary(db *sql.DB, id string) (diarySummary, error) {
	var s diarySummary
	s.AtmID = id
	row := db.QueryRow(`SELECT
		COALESCE(total_runs,0), COALESCE(pass_runs,0), COALESCE(fail_runs,0),
		COALESCE(skip_runs,0), COALESCE(last_run,''), COALESCE(last_result,''),
		COALESCE(status_changes,0), COALESCE(testers,''), COALESCE(feature_classes,'')
		FROM test_diary_summary WHERE atm_id=?`, id)
	err := row.Scan(&s.TotalRuns, &s.PassRuns, &s.FailRuns, &s.SkipRuns,
		&s.LastRun, &s.LastResult, &s.StatusChanges, &s.Testers, &s.FeatureClasses)
	if err == sql.ErrNoRows {
		return s, nil
	}
	return s, err
}

// itemDescription returns the description column for id (any location), "" when absent.
func itemDescription(db *sql.DB, id string) (string, error) {
	var d string
	err := db.QueryRow(`SELECT description FROM items WHERE atm_id=? LIMIT 1`, id).Scan(&d)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return d, err
}

// buildSummaryEssence renders the level-(c) one-line essence from the rollup +
// the most-recent diary detail, then asserts it is STRICTLY SHORTER than the
// sub-task description (§11.4.149(b) / SUBTASK_HIERARCHY_DESIGN.md §4.1). If the
// essence is not shorter, it is truncated to description-length − 1 (the summary
// is by-construction the smallest). Deterministic, no LLM.
func buildSummaryEssence(s diarySummary, lastDetail, description string) string {
	essence := fmt.Sprintf("%d runs (P%d/F%d/S%d), last=%s",
		s.TotalRuns, s.PassRuns, s.FailRuns, s.SkipRuns, defaultStr(s.LastResult, "none"))
	if lastDetail != "" {
		essence += " — " + lastDetail
	}
	if s.StatusChanges > 0 {
		essence += fmt.Sprintf(" [%d status change(s)]", s.StatusChanges)
	}
	// Enforce summary < description (when a description exists to compare to).
	if d := strings.TrimSpace(description); d != "" && len(essence) >= len(d) {
		max := len(d) - 1
		if max < 0 {
			max = 0
		}
		if len(essence) > max {
			essence = essence[:max]
		}
	}
	return essence
}

// runSummaryGen implements `summary-gen {--subtask ID | --all}`. It prints the
// derived essence per target (and enforces the size invariant). Read-only.
func runSummaryGen(args []string) { os.Exit(summaryGenCmd(args)) }

func summaryGenCmd(args []string) int {
	fs := flag.NewFlagSet("summary-gen", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	subtask := fs.String("subtask", "", "single target id")
	all := fs.Bool("all", false, "all ids present in test_diary")
	_, flagArgs := partitionArgs(args, map[string]bool{"all": true})
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "summary-gen: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*subtask) == "" && !*all {
		fmt.Fprintln(os.Stderr, "summary-gen: one of --subtask <id> | --all is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "summary-gen: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	ids, err := summaryTargets(db, strings.TrimSpace(*subtask), *all)
	if err != nil {
		fmt.Fprintf(os.Stderr, "summary-gen: %v\n", err)
		return exitUsage
	}
	for _, id := range ids {
		s, err := loadSummary(db, id)
		if err != nil {
			fmt.Fprintf(os.Stderr, "summary-gen: %s: %v\n", id, err)
			return exitUsage
		}
		desc, _ := itemDescription(db, id)
		lastDetail := mostRecentDetail(db, id)
		essence := buildSummaryEssence(s, lastDetail, desc)
		fmt.Printf("%s: %s\n", id, essence)
	}
	return exitOK
}

// mostRecentDetail returns the result_detail of the newest diary row for id.
func mostRecentDetail(db *sql.DB, id string) string {
	var d sql.NullString
	_ = db.QueryRow(`SELECT result_detail FROM test_diary WHERE atm_id=?
		ORDER BY date_time DESC, entry_id DESC LIMIT 1`, id).Scan(&d)
	if d.Valid {
		return d.String
	}
	return ""
}

// summaryTargets resolves the id list (single or all-in-diary).
func summaryTargets(db *sql.DB, single string, all bool) ([]string, error) {
	if single != "" {
		return []string{single}, nil
	}
	rows, err := db.Query(`SELECT DISTINCT atm_id FROM test_diary ORDER BY atm_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// ---- subtask-export: Session / Diary / Summary × four formats ----

// runSubtaskExport implements `subtask-export {--subtask ID | --parent ID |
// --all}`. For each sub-task it renders, under
// docs/issues/<PARENT>/sessions/<SSS>/: Session.md (level (a)), Diary.md (level
// (b)), Summary.md (level (c)) + their HTML/PDF/DOCX siblings (§11.4.65).
func runSubtaskExport(args []string) { os.Exit(subtaskExportCmd(args)) }

func subtaskExportCmd(args []string) int {
	fs := flag.NewFlagSet("subtask-export", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	subtask := fs.String("subtask", "", "single sub-task id")
	parent := fs.String("parent", "", "all sub-tasks of this parent")
	all := fs.Bool("all", false, "every sub-task in the DB")
	outDir := fs.String("out-dir", "docs/issues", "root directory for per-item session docs")
	noFormats := fs.Bool("no-formats", false, "emit Markdown only (skip HTML/PDF/DOCX siblings; force off)")
	formats := fs.Bool("formats", false, "force HTML/PDF/DOCX siblings on (default: the constitution formats-export switch decides, which is OFF)")
	_, flagArgs := partitionArgs(args, map[string]bool{"all": true, "no-formats": true, "formats": true})
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	fmtDecision, fmtOK := decideFormats(*noFormats, *formats)
	if !fmtOK {
		fmt.Fprintln(os.Stderr, "subtask-export: --formats and --no-formats are mutually exclusive")
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "subtask-export: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-export: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	targets, err := subtaskExportTargets(db, strings.TrimSpace(*subtask), strings.TrimSpace(*parent), *all)
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-export: %v\n", err)
		return exitUsage
	}
	if len(targets) == 0 {
		fmt.Println("subtask-export: no matching sub-tasks")
		return exitOK
	}

	var mdFiles []string
	for _, t := range targets {
		dir := filepath.Join(*outDir, t.Parent, "sessions", t.Suffix)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: mkdir %s: %v\n", dir, err)
			return exitUsage
		}
		desc, _ := itemDescription(db, t.ChildID)
		diary, err := loadDiary(db, t.ChildID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: load diary %s: %v\n", t.ChildID, err)
			return exitUsage
		}
		s, err := loadSummary(db, t.ChildID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: load summary %s: %v\n", t.ChildID, err)
			return exitUsage
		}
		essence := buildSummaryEssence(s, mostRecentDetail(db, t.ChildID), desc)

		sessionMD := filepath.Join(dir, "Session.md")
		diaryMD := filepath.Join(dir, "Diary.md")
		summaryMD := filepath.Join(dir, "Summary.md")
		if err := os.WriteFile(sessionMD, []byte(renderSessionDoc(t.ChildID, t.Parent, t.SessionRef, desc)), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: write %s: %v\n", sessionMD, err)
			return exitUsage
		}
		if err := os.WriteFile(diaryMD, []byte(renderDiaryDoc(t.ChildID, diary)), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: write %s: %v\n", diaryMD, err)
			return exitUsage
		}
		if err := os.WriteFile(summaryMD, []byte(renderSummaryDoc(t.ChildID, s, essence)), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: write %s: %v\n", summaryMD, err)
			return exitUsage
		}
		mdFiles = append(mdFiles, sessionMD, diaryMD, summaryMD)
		fmt.Printf("subtask-export: wrote %s {Session,Diary,Summary}.md\n", dir)
	}

	if *noFormats {
		fmt.Println("subtask-export: --no-formats set; skipped HTML/PDF/DOCX siblings")
		return exitOK
	}
	if !fmtDecision.Enabled {
		fmt.Println(formatsDisabledNotice("subtask-export", fmtDecision))
		return exitOK
	}
	return emitFourFormatSiblings(mdFiles)
}

// emitFourFormatSiblings generates .html/.docx/.pdf for each .md via pandoc
// (+ weasyprint for PDF). §11.4.6 anti-bluff: a missing tool emits an honest
// message and produces NO fake file — mirrors export.go's gating.
func emitFourFormatSiblings(mdFiles []string) int {
	pandoc, hasPandoc := exec.LookPath("pandoc")
	if hasPandoc != nil {
		fmt.Println("subtask-export: pandoc not found on PATH — emitted Markdown only; " +
			"HTML/PDF/DOCX siblings NOT generated (install pandoc + weasyprint to enable)")
		return exitOK
	}
	_, weasyErr := exec.LookPath("weasyprint")
	hasWeasy := weasyErr == nil
	if !hasWeasy {
		fmt.Println("subtask-export: weasyprint not found on PATH — HTML + DOCX generated, PDF SKIPPED")
	}
	failures := 0
	for _, md := range mdFiles {
		base := strings.TrimSuffix(md, ".md")
		if err := runPandoc(pandoc, md, base+".html", "--standalone"); err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: pandoc HTML %s: %v\n", md, err)
			failures++
		}
		if err := runPandoc(pandoc, md, base+".docx"); err != nil {
			fmt.Fprintf(os.Stderr, "subtask-export: pandoc DOCX %s: %v\n", md, err)
			failures++
		}
		if hasWeasy {
			if err := runPandoc(pandoc, md, base+".pdf", "--pdf-engine=weasyprint"); err != nil {
				fmt.Fprintf(os.Stderr, "subtask-export: pandoc PDF %s: %v\n", md, err)
				failures++
			}
		}
	}
	if failures > 0 {
		fmt.Fprintf(os.Stderr, "subtask-export: %d sibling-format failure(s)\n", failures)
		return exitUsage
	}
	return exitOK
}

// exportTarget resolves a sub-task to its parent + suffix for the doc path.
type exportTarget struct {
	ChildID    string
	Parent     string
	Suffix     string // the SSS portion
	SessionRef string
}

func subtaskExportTargets(db *sql.DB, single, parent string, all bool) ([]exportTarget, error) {
	var where string
	var arg any
	switch {
	case single != "":
		where = "atm_id=?"
		arg = single
	case parent != "":
		where = "parent_atm_id=?"
		arg = parent
	case all:
		where = "parent_atm_id IS NOT NULL"
	default:
		return nil, fmt.Errorf("one of --subtask | --parent | --all is required")
	}
	q := `SELECT atm_id, COALESCE(parent_atm_id,''), COALESCE(session_ref,'')
		FROM items WHERE ` + where + ` AND parent_atm_id IS NOT NULL ORDER BY atm_id`
	var rows *sql.Rows
	var err error
	if arg != nil {
		rows, err = db.Query(q, arg)
	} else {
		rows, err = db.Query(q)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []exportTarget
	for rows.Next() {
		var t exportTarget
		if err := rows.Scan(&t.ChildID, &t.Parent, &t.SessionRef); err != nil {
			return nil, err
		}
		// Suffix = the trailing -NNN of the child id.
		if i := strings.LastIndex(t.ChildID, "-"); i >= 0 && i+1 < len(t.ChildID) {
			t.Suffix = t.ChildID[i+1:]
		} else {
			t.Suffix = t.ChildID
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// ---- markdown renderers (each carries the §11.4.44 revision header) ----

func revHeader() string {
	return fmt.Sprintf("**Revision:** 1\n**Last modified:** %s\n\n", time.Now().UTC().Format(time.RFC3339))
}

func renderSessionDoc(child, parent, sessionRef, description string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# Session %s\n\n", child)
	b.WriteString(revHeader())
	fmt.Fprintf(&b, "- **Parent:** %s\n", parent)
	fmt.Fprintf(&b, "- **Session:** %s\n\n", defaultStr(sessionRef, "(unspecified)"))
	b.WriteString("## Scope\n\n")
	b.WriteString(defaultStr(strings.TrimSpace(description), "(no description)"))
	b.WriteString("\n")
	return b.String()
}

func renderDiaryDoc(child string, rows []diaryRow) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# Diary %s\n\n", child)
	b.WriteString(revHeader())
	if len(rows) == 0 {
		b.WriteString("_No diary entries recorded yet._\n")
		return b.String()
	}
	for _, r := range rows {
		fmt.Fprintf(&b, "### %s — %s — %s\n\n", r.DateTime, r.TestedBy, r.Result)
		if r.ResultDetail != "" {
			fmt.Fprintf(&b, "**Detail:** %s\n\n", r.ResultDetail)
		}
		if r.FeatureClass != "" {
			fmt.Fprintf(&b, "**Feature-Class:** %s\n\n", r.FeatureClass)
		}
		b.WriteString(strings.TrimSpace(r.Observations))
		b.WriteString("\n\n")
		fmt.Fprintf(&b, "**Action:** %s\n", r.ActionTaken)
		if r.StatusFrom != "" || r.StatusTo != "" {
			fmt.Fprintf(&b, "**Status:** %s → %s\n", defaultStr(r.StatusFrom, "?"), defaultStr(r.StatusTo, "?"))
		}
		if r.EvidencePath != "" {
			fmt.Fprintf(&b, "**Evidence:** %s\n", r.EvidencePath)
		}
		b.WriteString("\n")
	}
	return b.String()
}

func renderSummaryDoc(child string, s diarySummary, essence string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# Summary %s\n\n", child)
	b.WriteString(revHeader())
	fmt.Fprintf(&b, "%s\n\n", essence)
	b.WriteString("| Metric | Value |\n|---|---|\n")
	fmt.Fprintf(&b, "| Total runs | %d |\n", s.TotalRuns)
	fmt.Fprintf(&b, "| PASS | %d |\n", s.PassRuns)
	fmt.Fprintf(&b, "| FAIL | %d |\n", s.FailRuns)
	fmt.Fprintf(&b, "| SKIP | %d |\n", s.SkipRuns)
	fmt.Fprintf(&b, "| Last result | %s |\n", defaultStr(s.LastResult, "none"))
	fmt.Fprintf(&b, "| Last run | %s |\n", defaultStr(s.LastRun, "—"))
	fmt.Fprintf(&b, "| Status changes | %d |\n", s.StatusChanges)
	fmt.Fprintf(&b, "| Testers | %s |\n", defaultStr(s.Testers, "—"))
	fmt.Fprintf(&b, "| Feature classes | %s |\n", defaultStr(s.FeatureClasses, "—"))
	return b.String()
}

// ---- tiny helpers ----

func firstNonEmpty(a, b string) string {
	if strings.TrimSpace(a) != "" {
		return a
	}
	return b
}

func defaultStr(v, def string) string {
	if strings.TrimSpace(v) == "" {
		return def
	}
	return v
}
