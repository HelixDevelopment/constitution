// subtask.go — §11.4.149 sub-task hierarchy (ATM-NNN-SSS) tooling.
//
// A testing session against a workable item is modelled as a FIRST-CLASS
// workable item with its OWN status + type, distinguished by a non-NULL
// items.parent_atm_id. Its id is the parent's id + "-" + a 3-digit,
// auto-incremental, append-only PER-PARENT suffix (ATM-025-001, ATM-025-002, …).
//
// Design source: docs/research/forgettable_sync/SUBTASK_HIERARCHY_DESIGN.md §1-3.
// Deterministic bash/Go — ZERO LLM in the data path.
//
// Commands:
//
//	subtask-add <parent> [--session REF] [--description-file F] [--db p]
//	subtask-status <child> --to {Queued|In progress|Completed} [--db p]
//	subtask-export {--subtask ID | --parent ID | --all} [--db p] [--out-dir d]
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// parentIDRe matches a top-level workable-item id (the §11.4.54 grammar): an
// ATM-NNN / 3-letter-NNN form (`ATM-025`, `BOB-014`) OR a legacy §-letter id
// (1-3 uppercase letters, e.g. `BG`).
var parentIDRe = regexp.MustCompile(`^(` + canonicalIDPattern + `|[A-Z]{1,3})$`)

// childSuffixRe splits a candidate child id into <parent>-<3+ digits>. The
// parent portion is validated SEPARATELY against parentIDRe so a full parent id
// (e.g. `ATM-025`) is never mis-classified as a child of `ATM` (the regex is
// greedy on the parent — it captures the longest prefix before the final
// -NNN block).
var childSuffixRe = regexp.MustCompile(`^(.+)-([0-9]{3,})$`)

// isChildID reports whether id is a sub-task id: it splits into <parent>-<3+
// digits> where the parent portion is a valid top-level id, AND id is NOT itself
// a valid top-level id (the canonical `ATM-NNN` parent form would otherwise be
// mis-read as legacy-parent `ATM` + suffix `NNN`). Examples accepted:
// ATM-025-001, BOB-014-002, BG-001. Rejected: ATM-025 (a full parent id),
// ATM-025-1 (too few suffix digits).
func isChildID(id string) bool {
	if parentIDRe.MatchString(id) {
		return false // a whole valid parent id is never a child
	}
	m := childSuffixRe.FindStringSubmatch(id)
	if m == nil {
		return false
	}
	return parentIDRe.MatchString(m[1])
}

// subtaskSeqMetaKey returns the meta key holding the per-parent suffix counter.
func subtaskSeqMetaKey(parent string) string { return "subtask_seq:" + parent }

// allocSubtaskID allocates the next monotonic ATM-NNN-SSS id for parent inside
// tx. It reads the per-parent counter from meta (0 when absent), increments it
// ATOMICALLY in the SAME transaction as the caller's row INSERT (so the counter
// and the row are never out of step — §11.4.6 crash-safety, never re-derived
// from a scan that could double-allocate after a partial write), and returns
// the zero-padded child id. Append-only per §11.4.54 — never reused/decremented.
func allocSubtaskID(tx *sql.Tx, parent string) (string, error) {
	key := subtaskSeqMetaKey(parent)
	var cur sql.NullString
	err := tx.QueryRow(`SELECT value FROM meta WHERE key=?`, key).Scan(&cur)
	if err != nil && err != sql.ErrNoRows {
		return "", err
	}
	max := 0
	if cur.Valid {
		max = atoiSafe(cur.String)
	}
	next := max + 1
	if _, err := tx.Exec(`INSERT INTO meta(key,value,last_modified) VALUES(?,?,datetime('now'))
		ON CONFLICT(key) DO UPDATE SET value=excluded.value, last_modified=datetime('now')`,
		key, fmt.Sprintf("%d", next)); err != nil {
		return "", err
	}
	return fmt.Sprintf("%s-%03d", parent, next), nil
}

// runSubtaskAdd implements `subtask-add <parent> [--session REF]
// [--description-file F] [--type Task] [--db p]`.
func runSubtaskAdd(args []string) { os.Exit(subtaskAddCmd(args)) }

func subtaskAddCmd(args []string) int {
	fs := flag.NewFlagSet("subtask-add", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	session := fs.String("session", "", "testing-session label (items.session_ref)")
	descFile := fs.String("description-file", "", "file with the §11.4.91 session description (markdown)")
	descInline := fs.String("description", "", "inline session description (alternative to --description-file)")
	typ := fs.String("type", "Task", "item type (§11.4.16; a testing session is a Task)")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "subtask-add: missing positional <parent-atm-id>")
		return exitUsage
	}
	parent := strings.TrimSpace(pos[0])
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "subtask-add: --db is required")
		return exitUsage
	}

	// Resolve the description (file takes precedence over inline).
	desc := strings.TrimSpace(*descInline)
	if strings.TrimSpace(*descFile) != "" {
		b, err := os.ReadFile(*descFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "subtask-add: read --description-file: %v\n", err)
			return exitUsage
		}
		desc = strings.TrimSpace(string(b))
	}
	if desc == "" {
		// Provide a §11.4.91-compliant default scoped to the session so the
		// description floor never blocks a session sub-task creation.
		ref := *session
		if ref == "" {
			ref = "unspecified-session"
		}
		desc = fmt.Sprintf("Testing session %s for parent %s — scope, environment and entry conditions recorded in the diary.", ref, parent)
	}
	if wordCount(desc) < 6 && len(desc) < 40 {
		fmt.Fprintf(os.Stderr, "subtask-add: description fails §11.4.91 floor (%d words / %d chars)\n",
			wordCount(desc), len(desc))
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	// Parent MUST exist as a workable item (soft FK check §11.4.6 — never guess).
	pExists, err := itemExistsAnyLocation(db, parent)
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: %v\n", err)
		return exitUsage
	}
	if !pExists {
		fmt.Fprintf(os.Stderr, "subtask-add: parent %s not found in items (a sub-task needs an existing parent)\n", parent)
		return exitUsage
	}

	t := normalizeType(*typ)

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	childID, err := allocSubtaskID(tx, parent)
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: allocate id: %v\n", err)
		return exitUsage
	}

	title := fmt.Sprintf("Testing session %s", *session)
	if strings.TrimSpace(*session) == "" {
		title = "Testing session"
	}
	body := renderItemBody(childID, title, t, "", desc, "Queued", "", "")

	if _, err := tx.Exec(`INSERT INTO items
		(atm_id, type, status, severity, title, description, created_by, assigned_to,
		 current_location, body_md, parent_atm_id, session_ref)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
		childID, t, "Queued", nil, title, desc, "", "", "Issues", body,
		parent, nullable(*session)); err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: insert sub-task: %v\n", err)
		return exitUsage
	}
	if err := appendSegment(tx, "Issues", childID); err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: append segment: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, childID, "Opened", "AI", "", ""); err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "subtask-add: commit: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("subtask-add: created %s (parent=%s, session=%q, status=Queued)\n", childID, parent, *session)
	return exitOK
}

// subtaskStatusMap maps the operator not-started/ongoing/done lifecycle onto the
// EXISTING §11.4.15 closed-set status values — no new status value is introduced.
var subtaskStatusMap = map[string]string{
	"queued":      "Queued",
	"todo":        "Queued",
	"in progress": "In progress",
	"in-progress": "In progress",
	"ongoing":     "In progress",
	"completed":   "Completed (→ Fixed.md)",
	"complete":    "Completed (→ Fixed.md)",
	"done":        "Completed (→ Fixed.md)",
}

// runSubtaskStatus implements `subtask-status <child> --to {Queued|In progress|
// Completed} [--evidence p] [--db p]`. Reaching Completed REQUIRES evidence
// (§11.4.69) — a session marked done without captured proof is a PASS-bluff.
func runSubtaskStatus(args []string) { os.Exit(subtaskStatusCmd(args)) }

func subtaskStatusCmd(args []string) int {
	fs := flag.NewFlagSet("subtask-status", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	to := fs.String("to", "", "target status: Queued | In progress | Completed")
	evidence := fs.String("evidence", "", "captured-evidence path (required to reach Completed, §11.4.69)")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "subtask-status: missing positional <child-id>")
		return exitUsage
	}
	child := strings.TrimSpace(pos[0])
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "subtask-status: --db is required")
		return exitUsage
	}
	target, ok := subtaskStatusMap[strings.ToLower(strings.TrimSpace(*to))]
	if !ok {
		fmt.Fprintln(os.Stderr, "subtask-status: --to must be one of: Queued | In progress | Completed")
		return exitUsage
	}
	if target == "Completed (→ Fixed.md)" && strings.TrimSpace(*evidence) == "" {
		fmt.Fprintln(os.Stderr, "subtask-status: --evidence is required to reach Completed (§11.4.69)")
		return exitUsage
	}
	// HXC-224 record-time closure-evidence guard. Checked whenever a value is
	// supplied (not only on the Completed transition): a sub-task reaching a
	// terminal status carries the same falsifiability burden as any other
	// closure, and an unresolvable path recorded on a non-terminal transition
	// would simply become a violation the moment that sub-task closes.
	if !requireEvidencePath("subtask-status", *evidence) {
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-status: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	it, err := loadItem(db, child, "Issues")
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-status: %v\n", err)
		return exitUsage
	}
	if it == nil {
		fmt.Fprintf(os.Stderr, "subtask-status: sub-task %s not found in Issues\n", child)
		return exitUsage
	}

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "subtask-status: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	// §11.4.93/ATM-627 (task #20) column↔body invariant: advancing the status column
	// MUST also canonicalize body_md's `**Status:**` line in the SAME transaction, or
	// `sync db-to-md` replays the stale line and `validate` (statusColumnBodyDesyncs)
	// flags a desync. setStatusAndSyncBody is the single bare-status choke-point; it
	// preserves all prose + detail blocks (surgical single-line rewrite).
	if err := setStatusAndSyncBody(tx, child, "Issues", target); err != nil {
		fmt.Fprintf(os.Stderr, "subtask-status: update: %v\n", err)
		return exitUsage
	}
	ev := strings.TrimSpace(*evidence)
	if err := recordHistory(tx, child, "Updated", "AI", "status: "+it.Status+" -> "+target, ev); err != nil {
		fmt.Fprintf(os.Stderr, "subtask-status: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "subtask-status: commit: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("subtask-status: %s %s -> %s\n", child, it.Status, target)
	return exitOK
}

// ---- shared sub-task helpers ----

// itemExistsAnyLocation reports whether id is present in EITHER tracker.
func itemExistsAnyLocation(db *sql.DB, id string) (bool, error) {
	var n int
	err := db.QueryRow(`SELECT COUNT(1) FROM items WHERE atm_id=?`, id).Scan(&n)
	return n > 0, err
}

// listSubtasks returns the (childID, status, sessionRef) of every sub-task of
// parent, ordered by id (suffix order). Read-only.
type subtaskRow struct {
	ChildID    string
	Status     string
	SessionRef string
}

func listSubtasks(db *sql.DB, parent string) ([]subtaskRow, error) {
	rows, err := db.Query(`SELECT atm_id, status, COALESCE(session_ref,'')
		FROM items WHERE parent_atm_id=? ORDER BY atm_id`, parent)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []subtaskRow
	for rows.Next() {
		var r subtaskRow
		if err := rows.Scan(&r.ChildID, &r.Status, &r.SessionRef); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// walCheckpoint truncates the WAL so the tracked .db is commit-clean per
// §11.4.95 (transient .db-wal / .db-shm sidecars are safely discardable). Best
// effort — a failure here is non-fatal (the write already committed).
func walCheckpoint(db *sql.DB) {
	_, _ = db.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`)
}
