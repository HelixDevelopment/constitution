// crud.go — the mutating subcommands: add, close.
//
// §11.4.93: add/close mutate the DB AND keep the byte-identical round-trip
// invariant intact. Both operations write an items row, an item_history audit
// entry, and a doc_segments item entry (add) / move the segment between
// documents (close) so that a subsequent `sync db-to-md` regenerates a
// well-formed, re-parseable Markdown tracker. The generated item body_md uses
// the canonical `## <ID> — <title>` heading + `**Status:**`/`**Type:**` meta
// block the parser already recognises, so add→sync db-to-md→sync md-to-db is a
// stable fixed point.
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"time"
)

// canonicalIDRe (the canonical id shape) is defined in idgrammar.go, the one
// id grammar shared by the renderer, the parser, add and validate.

// partitionArgs separates positional (non-flag) tokens from flag tokens so the
// Go flag package — which stops at the first positional — can still parse flags
// that appear AFTER positionals (e.g. `add Bug Critical --db x`). boolFlags are
// flags that take NO value; every other `--flag` / `-flag` token is assumed to
// consume the following token as its value (whether `--db x` or `--db=x`).
// Returns (positionals, flagArgs). Order within each group is preserved.
func partitionArgs(args []string, boolFlags map[string]bool) (positionals, flagArgs []string) {
	i := 0
	for i < len(args) {
		a := args[i]
		if strings.HasPrefix(a, "-") && a != "-" {
			flagArgs = append(flagArgs, a)
			name := strings.TrimLeft(a, "-")
			// `--flag=value` carries its own value; a bare bool flag takes none;
			// otherwise the next token is this flag's value.
			if !strings.Contains(a, "=") && !boolFlags[name] && i+1 < len(args) {
				flagArgs = append(flagArgs, args[i+1])
				i++
			}
			i++
			continue
		}
		positionals = append(positionals, a)
		i++
	}
	return positionals, flagArgs
}

// runAdd implements `add <type> <severity> --title <T> --description <D>`.
//
//	type      positional (Bug | Feature | Task) — §11.4.16 closed-set
//	severity  positional (free text; informational)
//	--title   heading title (required)
//	--description  §11.4.91 floor (≥6 words OR ≥40 chars; required)
//	--id      explicit ticket id (optional; auto-generated from --prefix when absent)
//	--prefix  3-letter id prefix for auto-generated ids (default: derived per §11.4.151)
//	--db      SQLite DB path (required)
func runAdd(args []string) {
	os.Exit(addCmd(args))
}

func addCmd(args []string) int {
	fs := flag.NewFlagSet("add", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	title := fs.String("title", "", "item title (heading text)")
	description := fs.String("description", "", "item description (§11.4.91 floor: ≥6 words OR ≥40 chars)")
	explicitID := fs.String("id", "", "explicit ticket id (auto-generated when absent)")
	// §11.4.151/§11.4.29: the default KEY is DERIVED (HELIX_RELEASE_PREFIX env /
	// .env / lowercased snake_case project-dir name), never a hardcoded real
	// project key. An explicit --prefix still overrides.
	prefix := fs.String("prefix", defaultKeyPrefix(), "3-letter id prefix for auto-generated ids (derived per §11.4.151)")
	createdBy := fs.String("created-by", "", "§11.4.104 canonical handle that opened the item (default '')")
	assignedTo := fs.String("assigned-to", "", "§11.4.104 canonical handle the item is assigned to (default '')")
	// §11.4.292 (v8): optional initial reproduction / investigation records
	// (default UNSET — `add` never invents a state).
	sf := registerStateFlags(fs)
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	setFlags := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { setFlags[f.Name] = true })
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "add: missing positional <type> (Bug | Feature | Task)")
		return exitUsage
	}
	typ := normalizeType(pos[0])
	severity := ""
	if len(pos) >= 2 {
		// CON-456 round 2: surrounding whitespace is trimmed (the parser
		// trims every metadata value, so it could never read it back).
		severity = strings.TrimSpace(pos[1])
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "add: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*title) == "" {
		fmt.Fprintln(os.Stderr, "add: --title is required")
		return exitUsage
	}
	if strings.TrimSpace(*description) == "" {
		fmt.Fprintln(os.Stderr, "add: --description is required")
		return exitUsage
	}
	// §11.4.91 description floor — enforced at entry per the mandate.
	if wordCount(*description) < 6 && len(*description) < 40 {
		fmt.Fprintf(os.Stderr, "add: --description fails §11.4.91 floor (%d words / %d chars; need ≥6 words OR ≥40 chars)\n",
			wordCount(*description), len(*description))
		return exitUsage
	}
	states, _, serr := sf.apply(stateRecord{}, setFlags, time.Now())
	if serr != nil {
		fmt.Fprintf(os.Stderr, "add: %v\n", serr)
		return exitUsage
	}
	if probs := stateRecordProblems(states, true); len(probs) > 0 {
		fmt.Fprintf(os.Stderr, "add: refusing — %s\n", strings.Join(probs, "; "))
		return exitUsage
	}

	// CON-456 round 2: surrounding whitespace of the title is trimmed, as the
	// id's is: a legacy-code heading cannot carry it (review F3), and a
	// canonical one keeps it only by accident of the regular expression.
	itemTitle := strings.TrimSpace(*title)
	cb := strings.TrimSpace(*createdBy)
	at := strings.TrimSpace(*assignedTo)
	// desc and states are what add stores. They differ from the flags only
	// when the description carries the engine's own legacy Bug template lines
	// (adoptLegacyTemplateStates, CON-456 round 3).
	desc := *description
	newItemWith := func(id, d string, st stateRecord) item {
		return item{AtmID: id, Title: itemTitle, Type: typ, Status: "Queued", Severity: severity,
			CreatedBy: cb, AssignedTo: at, CurrentLocation: "Issues", Representation: "section",
			States: st,
			BodyMD: canonicalizeStateLines(renderItemBody(id, itemTitle, typ, severity, d, "Queued", cb, at), st, "section")}
	}
	newItem := func(id string) item { return newItemWith(id, desc, states) }
	// Judge the whole item BEFORE the database is opened, so a refusal never
	// creates a database file at a fresh --db path (review F8). An id to be
	// allocated from --prefix is judged by the shape of its first id here and
	// the allocated id is judged again below; nextID refuses, before it
	// allocates, a number that would overflow (CON-456 round 3, review F-E).
	probeID := strings.TrimSpace(*explicitID)
	probeNote := ""
	if probeID == "" {
		probeID = *prefix + "-001"
		probeNote = fmt.Sprintf(" (judged with %s, the first id --prefix %s allocates; the real id is allocated after this check)", probeID, *prefix)
	}
	// CON-456 round 4 (review finding 5): the legacy template was the Bug
	// template only, so only a Bug adopts it.
	if typ == "Bug" {
		if ad, ast, ok := adoptLegacyTemplateStates(desc, states, setFlags); ok {
			if _, err := gateNewItem(newItemWith(probeID, ad, ast), ad); err == nil {
				desc, states = ad, ast
			}
		}
	}
	if _, err := gateNewItem(newItem(probeID), desc); err != nil {
		fmt.Fprintf(os.Stderr, "add: refusing (nothing written)%s — %v\n", probeNote, err)
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "add: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	id := strings.TrimSpace(*explicitID)
	if id == "" {
		id, err = nextID(db, *prefix)
		if err != nil {
			fmt.Fprintf(os.Stderr, "add: allocate id: %v\n", err)
			return exitUsage
		}
	} else {
		exists, err := itemExists(db, id, "Issues")
		if err != nil {
			fmt.Fprintf(os.Stderr, "add: %v\n", err)
			return exitUsage
		}
		if exists {
			fmt.Fprintf(os.Stderr, "add: item %s already exists in Issues\n", id)
			return exitUsage
		}
	}
	// One round trip (idgrammar.go): refuse, before any write, an item whose
	// stored Markdown the next db-to-md → md-to-db would not read back as this
	// item. This covers an explicit --id and an id allocated from --prefix.
	body, err := gateNewItem(newItem(id), desc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "add: refusing (nothing written) — %v\n", err)
		return exitUsage
	}

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "add: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`INSERT INTO items
		(atm_id, type, status, severity, title, description, created_by, assigned_to, current_location, body_md, `+statesInsertCols+`)
		VALUES (?,?,?,?,?,?,?,?,?,?,`+statesInsertMarks+`)`,
		append([]any{id, typ, "Queued", nullable(severity), itemTitle, desc, cb, at, "Issues", body},
			statesInsertArgs(states)...)...); err != nil {
		fmt.Fprintf(os.Stderr, "add: insert item: %v\n", err)
		return exitUsage
	}
	if err := appendSegment(tx, "Issues", id); err != nil {
		fmt.Fprintf(os.Stderr, "add: append segment: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, id, "Opened", "User", "", ""); err != nil {
		fmt.Fprintf(os.Stderr, "add: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "add: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("add: created %s (%s, status=Queued) in Issues\n", id, typ)
	return exitOK
}

// legacyTemplateStateLines are the two record lines scripts/reporting/report_item.sh
// appended, as text, to the description of every Bug until CON-456 round 3.
// They never matched the record grammar (states.go): the first is a malformed
// `**Reproduction:**` record (the ` (§11.4.292)` tail is not a ` — <key>
// <value>` detail), the second is prose. On main such an add stored UNSET and
// the next md-to-db silently set UNREPRODUCED; a round-2 engine refused the
// add, which broke the §11.4.202 fallback mint for every Bug (review F-A).
// The lines are the engine's own shipped template, so add adopts them: each
// line is read as the state it names and replaced by the canonical record
// line of that state.
var legacyTemplateStateLines = []struct {
	line  string
	repro bool
	state string
}{
	{"**Reproduction:** none — UNREPRODUCED (§11.4.292)", true, reproUnreproduced},
	{"**Investigation:** not-started (§11.4.294)", false, invNotStarted},
}

// adoptLegacyTemplateStates returns the description with each legacy
// template line (legacyTemplateStateLines) replaced by the canonical record
// line of the state it names, and the state record with that state set; ok
// is false when nothing was adopted. A line is adopted only when it is a whole
// line of desc, occurs exactly once, and its block has no state yet (an
// explicit state flag is never overridden by text). No other text is ever
// adopted, a well-formed record line included: a state read from description
// text would be a state nobody set with the state flags. The caller still
// runs the whole-item gate on the adopted item and keeps the original text
// when that gate refuses it.
func adoptLegacyTemplateStates(desc string, st stateRecord, set map[string]bool) (string, stateRecord, bool) {
	st = st.norm()
	lines := strings.Split(desc, "\n")
	// CON-456 round 4 (review finding 5): a template line inside a fenced
	// code block is quoted text, never adopted.
	fenced := fencedMask(lines) // CON-456 round 6: the shared fence definition
	adopted := false
	for _, l := range legacyTemplateStateLines {
		at, n := -1, 0
		for i, ln := range lines {
			if ln == l.line {
				if fenced[i] {
					// A fenced copy makes the line ambiguous: adopt nothing.
					n += 2
					continue
				}
				at, n = i, n+1
			}
		}
		if n != 1 {
			continue
		}
		var canon string
		if l.repro {
			if set["reproduction-state"] || st.ReproState != stateUnset {
				continue
			}
			st.ReproState = l.state
			canon = renderReproLine(stateRecord{ReproState: l.state})
		} else {
			if set["investigation-state"] || st.InvState != stateUnset {
				continue
			}
			st.InvState = l.state
			canon = renderInvestigationLine(stateRecord{InvState: l.state})
		}
		lines[at] = canon
		adopted = true
	}
	if !adopted {
		return desc, st, false
	}
	return strings.Join(lines, "\n"), st, true
}

// closeStatusMap maps the close --status keyword onto the closed-set terminal
// value + the item_history event_type per §11.4.33 / §11.4.90.
var closeStatusMap = map[string]struct {
	status string
	event  string
}{
	"fixed":       {"Fixed (→ Fixed.md)", "Fixed"},
	"implemented": {"Implemented (→ Fixed.md)", "Implemented"},
	"completed":   {"Completed (→ Fixed.md)", "Completed"},
	"obsolete":    {"Obsolete (→ Fixed.md)", "Obsolete"},
}

// typeCloseKeyword is the §11.4.33 closed Type→close-keyword mapping BOB-240
// enforces: which `close --status <word>` / `update --status <word>` keyword
// is the ONLY correct one for each Type (Bug→fixed, Feature→implemented,
// Task→completed). Obsolete is deliberately ABSENT from this table — per
// §11.4.90/§11.4.33 it is valid closure vocabulary for ANY Type (criterion 5),
// so it is exempted explicitly in typeStatusMismatch rather than being a
// fourth, always-true entry here.
var typeCloseKeyword = map[string]string{
	"Bug":     "fixed",
	"Feature": "implemented",
	"Task":    "completed",
}

// closeKeywordForStatus reverse-maps a terminal closed-set status TEXT back
// onto its closeStatusMap keyword — the inverse of closeStatusMap[keyword]
// .status — for refusal messages that need to echo the wrong keyword a
// caller effectively supplied. Returns "" when status is not a recognised
// terminal value (unreached in practice: every caller invokes this only on
// an ns already confirmed terminal by terminalStatuses()).
func closeKeywordForStatus(status string) string {
	for k, m := range closeStatusMap {
		if m.status == status {
			return k
		}
	}
	return ""
}

// typeStatusMismatch reports whether TERMINAL status ns violates the §11.4.33
// Type↔Status mapping for typ (typeCloseKeyword, resolved through
// closeStatusMap so the STATUS TEXT itself is never re-derived — §11.4.251).
// Obsolete is exempt for ANY Type (criterion 5). Callers MUST confirm ns is
// terminal (terminalStatuses()[ns]) before calling — this predicate does not
// itself distinguish "non-terminal" from "terminal but wrong", the same
// §11.4.201(1) scoping discipline BOB-166/BOB-175's location↔status guards
// already use.
//
// wantKeyword/wantStatus name the CORRECT `close --status`/`update --status`
// word and its full terminal-status text for the caller's refusal message —
// BOB-240 criterion 1/2's "printing the correct word to use".
func typeStatusMismatch(typ, ns string) (wantKeyword, wantStatus string, mismatch bool) {
	if ns == closeStatusMap["obsolete"].status {
		return "", "", false
	}
	keyword, ok := typeCloseKeyword[typ]
	if !ok {
		// typ outside {Bug,Feature,Task} is itself the §11.4.16 type-closed-set
		// violation validateCmd's typeSet check already reports; refusing to
		// ALSO flag a Type/Status mismatch here would misattribute the real
		// defect and is unreachable in practice (normalizeType defaults every
		// unrecognised input to "Task").
		return "", "", false
	}
	wantStatus = closeStatusMap[keyword].status
	return keyword, wantStatus, ns != wantStatus
}

// runClose implements `close <atm-id> --status <fixed|implemented|completed|
// obsolete> --evidence <path>`. It performs the §11.4.19 atomic move from
// Issues to Fixed: the item's current_location flips, its status becomes the
// terminal closed-set value, its body_md is regenerated with the closure
// metadata (so it round-trips), the Issues item-segment is removed, a Fixed
// item-segment is appended, and an item_history closure entry with mandatory
// captured-evidence (§11.4.5/§11.4.90) is recorded.
func runClose(args []string) {
	os.Exit(closeCmd(args))
}

func closeCmd(args []string) int {
	fs := flag.NewFlagSet("close", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	status := fs.String("status", "", "terminal status: fixed | implemented | completed | obsolete")
	evidence := fs.String("evidence", "", "path to captured-evidence artefact (§11.4.5/§11.4.90)")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "close: missing positional <atm-id>")
		return exitUsage
	}
	id := pos[0]
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "close: --db is required")
		return exitUsage
	}
	mapping, ok := closeStatusMap[strings.ToLower(strings.TrimSpace(*status))]
	if !ok {
		fmt.Fprintln(os.Stderr, "close: --status must be one of: fixed | implemented | completed | obsolete")
		return exitUsage
	}
	// §11.4.5 / §11.4.90 — closure requires captured evidence.
	if strings.TrimSpace(*evidence) == "" {
		fmt.Fprintln(os.Stderr, "close: --evidence is required (§11.4.5/§11.4.90 captured-evidence mandate)")
		return exitUsage
	}
	// HXC-224 — and that evidence must RESOLVE, refused HERE, at the moment of
	// recording. A non-empty check alone let a closure citing a path that had
	// never existed land in the single source of truth, to be flagged only by a
	// later `validate` sweep if one ever ran (the HXC-217 detective half). The
	// evidence path is what makes a closure falsifiable; recording a fabricated
	// one is a §11.4 PASS-bluff written straight into the tracker. Refusing
	// before openDB/Begin means a refused closure leaves no trace at all.
	if !requireEvidencePath("close", *evidence) {
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "close: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	src, err := loadItem(db, id, "Issues")
	if err != nil {
		fmt.Fprintf(os.Stderr, "close: %v\n", err)
		return exitUsage
	}
	if src == nil {
		fmt.Fprintf(os.Stderr, "close: item %s not found in Issues (nothing to close)\n", id)
		return exitUsage
	}
	exists, err := itemExists(db, id, "Fixed")
	if err != nil {
		fmt.Fprintf(os.Stderr, "close: %v\n", err)
		return exitUsage
	}
	if exists {
		fmt.Fprintf(os.Stderr, "close: item %s already present in Fixed\n", id)
		return exitUsage
	}

	// BOB-240 §11.4.33 Type↔Status guard: refuse a --status keyword whose
	// implied Type-mapping does not match src.Type (Obsolete exempt for ANY
	// Type — criterion 5). Placed AFTER the not-found/already-in-Fixed checks
	// (matching this command's existing refusal order) but BEFORE any write,
	// so a mismatched call — the exact BOB-077/100/179/226 shape, this
	// session's conductor's own repeated mistake — leaves no trace at all,
	// mirroring the requireEvidencePath refusal-before-write discipline
	// already established above.
	if wantKeyword, wantStatus, mismatch := typeStatusMismatch(src.Type, mapping.status); mismatch {
		fmt.Fprintf(os.Stderr,
			"close: refusing — %s has Type=%s, whose §11.4.33 closure vocabulary is %q (--status %s), not %q (--status %s); Obsolete is valid for any Type.\n"+
				"  correct command:  close %s --db <db> --status %s --evidence %s\n",
			id, src.Type, wantStatus, wantKeyword, mapping.status, strings.ToLower(strings.TrimSpace(*status)),
			id, wantKeyword, *evidence)
		return exitUsage
	}

	// §11.4.292 (v8) closure gate, refused BEFORE any write: a VERIFIED closure
	// (fixed / implemented / completed) of an item whose reproduction record is
	// labelled UNREPRODUCED — and, once `states freeze` armed the gate, of a Bug
	// with no record at all — is the claim §11.4.292(D) forbids. An Obsolete
	// closure is judged by `validate` once its §11.4.90 reason is recorded.
	if probs := preventiveClosureCheck(db, *src, mapping.status, false); len(probs) > 0 {
		fmt.Fprintf(os.Stderr, "close: refusing — %s\n", strings.Join(probs, "\n  "))
		return exitUsage
	}

	// §11.4.104: closure preserves the attribution columns unchanged.
	//
	// CON-456 round 5 (review r4 finding 1, structural): close patches the body
	// in place — its Status line, its closure Evidence record, and (when it
	// ends a block) the block record — and keeps every other line
	// (bodypatch.go). Only an empty body is rendered from the columns.
	var closedBody, endedRecord string
	endsBlock := src.Status == "Operator-blocked"
	if strings.TrimSpace(src.BodyMD) == "" {
		closedBody = renderItemBody(id, src.Title, src.Type, src.Severity, src.Description, mapping.status, src.CreatedBy, src.AssignedTo)
		closedBody = appendEvidence(closedBody, *evidence)
	} else {
		closedBody = canonicalizeBodyStatusLine(src.BodyMD, mapping.status)
		closedBody = setRecord(closedBody, recEvidence, "**Evidence:** "+*evidence)
	}
	// A closed item carries no block record (Fixed.md has no Operator-blocked
	// section); the row goes in the transaction below.
	closedBody, endedRecord = dropRecords(closedBody, recOBD, recChoices)
	// §11.4.292: the body carries the item's records (the state columns move
	// with the row below).
	closedBody = canonicalizeStateLines(closedBody, src.States, src.repOrDefault())
	// One round trip (idgrammar.go, CON-456): the closed item's Markdown in
	// Fixed.md must read back as the closed item on the next md-to-db.
	closed := *src
	closed.Status = mapping.status
	closed.CurrentLocation = "Fixed"
	closed.BodyMD = closedBody
	if closedBody, err = gateItemWrite(closed, *evidence); err != nil {
		fmt.Fprintf(os.Stderr, "close: refusing (nothing written) — %v\n", err)
		return exitUsage
	}
	if probs := ownedLinesProblems(src.BodyMD, closedBody, bodyOwnership{status: true, records: []string{recEvidence, recOBD, recChoices}}, src.Description, src.Description); len(probs) > 0 {
		fmt.Fprintf(os.Stderr, "close: refusing (nothing written) — %s\n", strings.Join(probs, "; "))
		return exitUsage
	}

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "close: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	// Remove the Issues item row + its Issues item-segment (atomic move out).
	//
	// F-DBTOOL fix (2026-07-12): scope by representation too — an unscoped
	// DELETE would remove BOTH representations of a dual-representation Issues
	// item (GAP A) while the INSERT below only recreates ONE row in Fixed,
	// silently losing the sibling representation. No Issues-side dual-rep item
	// exists in the live tree today (verified), so this is a latent-but-dormant
	// defect class closed defensively, mirroring the loadItem fix above.
	//
	// CON-339 (2026-11-13): read the row's created_at inside the transaction,
	// before the delete, and carry it into the Fixed row below. Omitting the
	// column from the INSERT let the schema DEFAULT (datetime('now')) stamp the
	// closure time over the item's real creation time.
	var createdAt string
	if err := tx.QueryRow(`SELECT created_at FROM items WHERE atm_id=? AND current_location='Issues' AND representation=?`, id, src.repOrDefault()).Scan(&createdAt); err != nil {
		fmt.Fprintf(os.Stderr, "close: read created_at of %s: %v\n", id, err)
		return exitUsage
	}
	if _, err := tx.Exec(`DELETE FROM items WHERE atm_id=? AND current_location='Issues' AND representation=?`, id, src.repOrDefault()); err != nil {
		fmt.Fprintf(os.Stderr, "close: remove from Issues: %v\n", err)
		return exitUsage
	}
	if err := removeItemSegment(tx, "Issues", id); err != nil {
		fmt.Fprintf(os.Stderr, "close: remove Issues segment: %v\n", err)
		return exitUsage
	}

	// Insert the Fixed item row + append its Fixed item-segment (atomic move in).
	//
	// destination/logic_group (ASSIGNMENT_MECHANISM_DESIGN.md §3.1 "Nullable
	// for closed: Fixed-location items may carry the group they were closed
	// under (kept for audit) but are not re-dispatched") are carried over
	// from src. P3 plumbing fix (docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md P3),
	// in scope not scope-creep, mirroring the loadItems/loadItem plumbing fix
	// P2 already made: without this, every item closed via THIS subcommand
	// silently lost its logic_group the instant it closed (these two columns
	// were absent from this INSERT's column list), so `assign group-complete
	// <g>` could never see a closed item as a member and would vacuously
	// report a group "complete" the moment its real members all closed —
	// exactly the PASS-bluff §11.4 forbids, and directly load-bearing for
	// P3's own group-complete gate.
	// F-DBTOOL fix (2026-07-12): carry the source row's OWN representation
	// forward instead of relying on the schema's implicit 'section' DEFAULT —
	// closing a 'table'-representation item (none exist in Issues today, but
	// the schema permits it) would otherwise silently retag it 'section'.
	if _, err := tx.Exec(`INSERT INTO items
		(atm_id, type, status, severity, title, description, created_by, assigned_to, current_location, body_md, representation, destination, logic_group, created_at, `+statesInsertCols+`)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,`+statesInsertMarks+`)`,
		append([]any{id, src.Type, mapping.status, nullable(src.Severity), src.Title, src.Description, src.CreatedBy, src.AssignedTo, "Fixed", closedBody, src.repOrDefault(), nullable(src.Destination), nullable(src.LogicGroup), createdAt},
			statesInsertArgs(src.States)...)...); err != nil {
		fmt.Fprintf(os.Stderr, "close: insert into Fixed: %v\n", err)
		return exitUsage
	}
	if err := appendSegment(tx, "Fixed", id); err != nil {
		fmt.Fprintf(os.Stderr, "close: append Fixed segment: %v\n", err)
		return exitUsage
	}
	// CON-456 round 4 (class sweep, RT_SIDE) and round 5: a closed item has
	// no block, so the operator_block_details row goes in the same
	// transaction; when close ended a block, the removed record is kept in
	// item_history (endBlockInTx).
	if endsBlock || endedRecord != "" {
		if err := endBlockInTx(tx, id, endedRecord); err != nil {
			fmt.Fprintf(os.Stderr, "close: %v\n", err)
			return exitUsage
		}
	} else if _, err := tx.Exec(`DELETE FROM operator_block_details WHERE atm_id=?`, id); err != nil {
		fmt.Fprintf(os.Stderr, "close: remove the block record: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, id, mapping.event, "AI", "", *evidence); err != nil {
		fmt.Fprintf(os.Stderr, "close: history: %v\n", err)
		return exitUsage
	}
	// Per §11.4.90, Obsolete closures carry triple-check evidence in their own
	// table when the operator supplies the required fields; the minimal close
	// path records the evidence path in item_history (above) and leaves the
	// richer obsolete_details entry to a dedicated flow.
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "close: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("close: moved %s Issues→Fixed (status=%s, evidence=%s)\n", id, mapping.status, *evidence)
	return exitOK
}

// ---- shared persistence helpers ----

// nextID allocates the next monotonic ticket id for prefix by scanning existing
// ids of the form <PREFIX>-<NNN> and returning prefix-(max+1), zero-padded to 3
// digits. Append-only per §11.4.54 — ids are never reused.
func nextID(db *sql.DB, prefix string) (string, error) {
	rows, err := db.Query(`SELECT atm_id FROM items WHERE atm_id LIKE ?`, prefix+"-%")
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var max int64
	want := prefix + "-"
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return "", err
		}
		if !strings.HasPrefix(id, want) {
			continue
		}
		n, err := idNumber(id[len(want):])
		if err != nil {
			// CON-456 round 3 (review F-E): atoiSafe wrapped an id number at
			// the int64 maximum to a negative one, so the next allocation
			// was CON--9223372036854775808, an id no parser reads. Refuse
			// before anything is allocated.
			return "", fmt.Errorf("existing id %s: %v; allocate with an explicit --id instead", id, err)
		}
		if n > max {
			max = n
		}
	}
	if err := rows.Err(); err != nil {
		return "", err
	}
	if max == math.MaxInt64 {
		return "", fmt.Errorf("existing id %s-%d is the largest number an id can carry, so no next id exists; allocate with an explicit --id instead", prefix, max)
	}
	return fmt.Sprintf("%s-%03d", prefix, max+1), nil
}

// idNumber parses the leading run of digits of an id suffix (stops at the
// first non-digit, tolerating suffixes like "014b"), 0 when there is none.
// Unlike atoiSafe it reports a number that does not fit an int64.
func idNumber(s string) (int64, error) {
	end := 0
	for end < len(s) && s[end] >= '0' && s[end] <= '9' {
		end++
	}
	if end == 0 {
		return 0, nil
	}
	n, err := strconv.ParseInt(s[:end], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("its number %s does not fit a 64-bit id counter", s[:end])
	}
	return n, nil
}

// atoiSafe parses the leading run of digits in s (stops at the first non-digit,
// tolerating suffixes like "014b"). Returns 0 when no leading digit is present.
func atoiSafe(s string) int {
	n := 0
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			break
		}
		n = n*10 + int(s[i]-'0')
	}
	return n
}

func itemExists(db *sql.DB, id, location string) (bool, error) {
	var n int
	err := db.QueryRow(`SELECT COUNT(1) FROM items WHERE atm_id=? AND current_location=?`, id, location).Scan(&n)
	return n > 0, err
}

// loadItem returns the single item at (id, location), or nil when absent.
//
// ASSIGNMENT_MECHANISM_DESIGN.md §3.1 (P2, ATM-659): destination + logic_group
// are included in the SELECT so every caller of THIS loader — group.go's
// groupSetItemMode foremost — observes the item's current classification, not
// a stale Go zero-value. Mirrors the same fix already applied to loadItems
// (plural, db.go); purely additive (two new trailing columns/scan targets),
// every existing caller is unaffected because each accesses fields by name
// (cur.Title, cur.Severity, ...), never by struct-literal position.
//
// F-DBTOOL fix (2026-07-12): the schema's PRIMARY KEY is the 3-tuple
// (atm_id, current_location, representation) — GAP A lets the SAME atm_id
// carry BOTH a 'section' (H2 narrative) row AND a 'table' (pipe-summary) row
// in the SAME tracker (the HXC-044 shape). This query's WHERE clause only
// constrained (atm_id, current_location), so on a dual-representation item
// `QueryRow` non-deterministically returned WHICHEVER row SQLite happened to
// scan first — AND `it.Representation` was never populated (Go zero-value ""),
// so every caller's `cur.repOrDefault()` always reported "section" regardless
// of which row was actually loaded. Every write-path caller (update/reopen/
// block/obsolete-details) then issued its UPDATE with a WHERE clause ALSO
// missing `representation`, so it silently clobbered BOTH rows with the
// content read from whichever ONE was loaded — corrupting the sibling
// representation's body (reproduced live: `obsolete-details HXC-044` made the
// 'table' row's body_md byte-identical to the 'section' row's, replacing its
// pipe-row content with an H2 section body; `sync db-to-md` then rendered that
// malformed 'table' segment, and the missing trailing-newline glued the next
// document segment onto it, corrupting parseFixed's view of ~188 subsequent
// items — see docs/research/f_dbtool_20260712/ROOTCAUSE.md).
//
// Fix: (1) SELECT + Scan the row's ACTUAL representation so `it.Representation`
// is always correct (never a phantom "section" default); (2) ORDER BY prefers
// the 'section' row when BOTH exist for the same (atm_id, location) — a
// deterministic tie-break instead of "whatever SQLite returns first" — while a
// location that has ONLY a 'table' row (the common case — ~187 of the DB's 188
// pipe-only closure rows) is returned unchanged, LIMIT 1 is a no-op there. This
// is purely additive for every single-representation item (the overwhelming
// majority): the same row is loaded, its representation field is now merely
// POPULATED rather than defaulted. Write-path callers then scope their UPDATE
// by `cur.repOrDefault()` so they only ever touch the row they actually read.
func loadItem(db *sql.DB, id, location string) (*item, error) {
	row := db.QueryRow(`SELECT atm_id, type, status,
		COALESCE(severity,''), title, description,
		COALESCE(forensic_anchor,''), COALESCE(closure_criteria,''),
		COALESCE(composes_with,''),
		COALESCE(created_by,''), COALESCE(assigned_to,''),
		current_location, COALESCE(body_md,''),
		COALESCE(representation,'section'),
		COALESCE(closure_date,''), COALESCE(round,''), COALESCE(commit_ref,''),
		COALESCE(destination,''), COALESCE(logic_group,''),
		`+statesSelectCols+`
		FROM items WHERE atm_id=? AND current_location=?
		ORDER BY CASE WHEN COALESCE(representation,'section')='section' THEN 0 ELSE 1 END
		LIMIT 1`, id, location)
	var it item
	dest := []any{&it.AtmID, &it.Type, &it.Status, &it.Severity,
		&it.Title, &it.Description, &it.ForensicAnchor, &it.ClosureCriteria,
		&it.ComposesWith, &it.CreatedBy, &it.AssignedTo, &it.CurrentLocation, &it.BodyMD,
		&it.Representation, &it.ClosureDate, &it.Round, &it.CommitRef,
		&it.Destination, &it.LogicGroup}
	err := row.Scan(append(dest, statesScanDest(&it.States)...)...)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &it, nil
}

// appendSegment appends an item-segment to the END of a document's segment list
// (max(seq)+1), so a freshly added/closed item renders after the existing
// content. A raw newline separator is NOT injected here — renderItemBody emits a
// trailing blank line so consecutive items stay well-formed.
func appendSegment(tx *sql.Tx, document, id string) error {
	var maxSeq sql.NullInt64
	if err := tx.QueryRow(`SELECT MAX(seq) FROM doc_segments WHERE document=?`, document).Scan(&maxSeq); err != nil {
		return err
	}
	next := 0
	if maxSeq.Valid {
		next = int(maxSeq.Int64) + 1
	}
	_, err := tx.Exec(`INSERT INTO doc_segments (document, seq, kind, atm_id, raw) VALUES (?,?,?,?,?)`,
		document, next, "item", id, nil)
	return err
}

// removeItemSegment deletes the item-segment for id from document. Remaining
// segments keep their seq values (gaps are harmless — render walks ORDER BY
// seq), so no renumbering is required.
func removeItemSegment(tx *sql.Tx, document, id string) error {
	_, err := tx.Exec(`DELETE FROM doc_segments WHERE document=? AND kind='item' AND atm_id=?`, document, id)
	return err
}

// recordHistory appends an append-only audit entry per §11.4.34 / §11.4.90.
// Delegates to recordHistoryWithTime (occurred_at.go, T-A05) with an empty
// occurred_at — every existing call site keeps writing NULL/"UNKNOWN"
// exactly as before this migration, with no behavioural change beyond the
// two new (always-populated-honestly) columns.
func recordHistory(tx *sql.Tx, id, event, by, reason, evidence string) error {
	return recordHistoryWithTime(tx, id, event, by, reason, evidence, "", "")
}

// setStatusAndSyncBody is the SINGLE choke-point for a BARE items.status write —
// a status transition that changes ONLY the status column (no title / type /
// description / detail-block change). It advances the column AND canonicalizes
// body_md's `**Status:**` line to the same value in the SAME transaction, so the
// §11.4.93/ATM-627 (task #20) column↔body invariant can never be re-created by a
// direct `UPDATE items SET status=…`: without the body write, `sync db-to-md`
// (renderDocument) would replay the STALE body Status line and `validate`
// (statusColumnBodyDesyncs) would flag the item.
//
// The other mutators (add / update / reopen / move / block / close) do NOT use this
// helper: each already emits a body carrying the new status (proven 0-desync by
// TestNoStatusMutationLeavesDesync) and legitimately changes other slots (title /
// description / `**…-Details:**` meta blocks) that a bare-status helper would leave
// stale. This helper is for the status-ONLY paths (subtask-status today; any future
// bare-status write).
//
// NOTE (2026-07-20): "emit a body carrying the new status" no longer means
// "regenerate from columns". `update` (SPK-481) and `reopen` (ATM-406) were BOTH
// found to destroy authored body_md by regenerating from renderItemBody, and both now
// PATCH the existing body through this same canonicalizeBodyStatusLine surgical
// rewrite. Regeneration survives only where there is nothing to preserve (empty body)
// or the caller explicitly replaces the freeform content (`update --description`).
//
// PROSE PRESERVATION: canonicalizeBodyStatusLine is a SURGICAL single-line rewrite —
// every other line, including prose + `**Reopened-Details:**` / `**Operator-Block-
// Details:**` blocks, is preserved byte-for-byte. On an empty/whitespace body it is a
// STRICT no-op (no Status line to rewrite), matching the empty-body class that
// repair-bodies / renderItemBody own — so this helper never fabricates a body.
func setStatusAndSyncBody(tx *sql.Tx, atmID, location, newStatus string) error {
	var body, oldStatus string
	if err := tx.QueryRow(`SELECT COALESCE(body_md,''), status FROM items
		WHERE atm_id=? AND current_location=?`, atmID, location).Scan(&body, &oldStatus); err != nil {
		return err
	}
	synced := canonicalizeBodyStatusLine(body, newStatus)
	// CON-456 round 5 (review r4 finding 3, writer sweep): a status write off
	// Operator-blocked ends the block — body record and row together.
	endsBlock := oldStatus == "Operator-blocked" && newStatus != "Operator-blocked"
	var endedRecord string
	if endsBlock {
		synced, endedRecord = dropRecords(synced, recOBD, recChoices)
	}
	res, err := tx.Exec(`UPDATE items SET status=?, body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=?`, newStatus, synced, atmID, location)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n != 1 {
		return fmt.Errorf("setStatusAndSyncBody: %s [%s] affected %d rows (expected 1)", atmID, location, n)
	}
	if endsBlock {
		return endBlockInTx(tx, atmID, endedRecord)
	}
	return nil
}

// renderItemBody produces a canonical, re-parseable Markdown item block:
//
//	## <ID> — <title>
//
//	**Status:** <status>
//	**Type:** <type>
//	[**Severity:** <severity>]
//	[**Created-By:** <createdBy>]
//	[**Assigned-To:** <assignedTo>]
//
//	<description>
//
// The trailing blank line keeps consecutive item segments separated. The block
// round-trips: parseIssues/parseFixed recognise the canonical heading + meta.
//
// §11.4.104: the **Created-By:** / **Assigned-To:** lines are emitted ONLY when
// the corresponding handle is non-empty. A legacy item with empty attribution
// renders exactly as before (no empty fields injected), preserving the
// byte-identical round-trip for fixtures that never carried the fields.
func renderItemBody(id, title, typ, severity, description, status, createdBy, assignedTo string) string {
	var b strings.Builder
	// Use dot separator for non-canonical IDs (Gxx, Rxx) so the parser's
	// shape-1 regex (## [A-Z][A-Za-z0-9]*. title) matches on re-import.
	// Canonical IDs (ABC-123) keep the dash separator.
	if canonicalIDRe.MatchString(id) {
		fmt.Fprintf(&b, "## %s — %s\n\n", id, title)
	} else {
		fmt.Fprintf(&b, "## %s. %s\n\n", id, title)
	}
	fmt.Fprintf(&b, "**Status:** %s\n", status)
	fmt.Fprintf(&b, "**Type:** %s\n", typ)
	if strings.TrimSpace(severity) != "" {
		fmt.Fprintf(&b, "**Severity:** %s\n", severity)
	}
	if strings.TrimSpace(createdBy) != "" {
		fmt.Fprintf(&b, "**Created-By:** %s\n", createdBy)
	}
	if strings.TrimSpace(assignedTo) != "" {
		fmt.Fprintf(&b, "**Assigned-To:** %s\n", assignedTo)
	}
	fmt.Fprintf(&b, "\n%s\n\n", description)
	return b.String()
}

// appendEvidence inserts an `**Evidence:**` metadata line into a rendered item
// body, immediately after the `**Type:**` line, so closures carry their
// captured-evidence reference in the regenerated Markdown.
func appendEvidence(body, evidence string) string {
	// CON-456 round 6: one implementation, after the item's own (unfenced) Type line.
	return insertMetaLine(body, "**Evidence:** "+evidence)
}
