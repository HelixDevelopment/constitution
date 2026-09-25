// sync.go — the functional subcommands: md-to-db, db-to-md, validate, diff.
//
// §11.4.93 bidirectional sync between the Markdown trackers and the SQLite
// single-source-of-truth, plus closed-set validation (§11.4.15/16/91).
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
)

// syncMDToDB parses Issues.md + Fixed.md and upserts the DB.
func syncMDToDB(args []string) int {
	fs := flag.NewFlagSet("sync md-to-db", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	issuesPath := fs.String("issues", "", "path to Issues.md")
	fixedPath := fs.String("fixed", "", "path to Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "sync md-to-db: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sync md-to-db: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	total := 0
	if *issuesPath != "" {
		content, err := os.ReadFile(*issuesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: read issues: %v\n", err)
			return exitUsage
		}
		items, segs := parseIssues(string(content))
		if err := replaceDocument(db, "Issues", items, segs); err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: persist issues: %v\n", err)
			return exitUsage
		}
		// BOB-155 (same acceptance criterion, lesser instance): name the file
		// ACTUALLY read, not a hardcoded tracker filename. The literal label
		// misreported the input whenever the caller passed any other path, and
		// baked one consumer's tracker naming into a shared submodule (§11.4.28).
		fmt.Printf("%s: %d items, %d segments\n", *issuesPath, len(items), len(segs))
		total += len(items)
	}
	if *fixedPath != "" {
		content, err := os.ReadFile(*fixedPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: read fixed: %v\n", err)
			return exitUsage
		}
		items, segs := parseFixed(string(content))
		if err := replaceDocument(db, "Fixed", items, segs); err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: persist fixed: %v\n", err)
			return exitUsage
		}
		fmt.Printf("%s: %d items, %d segments\n", *fixedPath, len(items), len(segs))
		total += len(items)
	}
	if *issuesPath == "" && *fixedPath == "" {
		fmt.Fprintln(os.Stderr, "sync md-to-db: at least one of --issues / --fixed is required")
		return exitUsage
	}
	fmt.Printf("synced %d total items into %s\n", total, *dbPath)
	return exitOK
}

// syncDBToMD regenerates Issues.md + Fixed.md from the DB segments.
func syncDBToMD(args []string) int {
	fs := flag.NewFlagSet("sync db-to-md", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	outIssues := fs.String("out-issues", "", "output path for regenerated Issues.md")
	outFixed := fs.String("out-fixed", "", "output path for regenerated Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "sync db-to-md: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sync db-to-md: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	if *outIssues != "" {
		text, err := renderDocument(db, "Issues")
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: render issues: %v\n", err)
			return exitUsage
		}
		// §11.4.44 (task #86 / BOB-108 sibling-defect): `sync db-to-md`
		// shares export's renderDocument-replays-the-DB's-stale-header
		// mechanism, so it MUST go through the SAME reconciliation
		// (export_revision.go) that BOB-108 wired into `export` — never let
		// the DB's own stale header segment regress the Revision counter
		// already committed on disk.
		text, err = reconcileRevisionHeader(text, *outIssues)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: reconcile issues revision: %v\n", err)
			return exitUsage
		}
		if err := os.WriteFile(*outIssues, []byte(text), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: write issues: %v\n", err)
			return exitUsage
		}
		fmt.Printf("wrote %s (%d bytes)\n", *outIssues, len(text))
	}
	if *outFixed != "" {
		text, err := renderDocument(db, "Fixed")
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: render fixed: %v\n", err)
			return exitUsage
		}
		// §11.4.44 (task #86 / BOB-108 sibling-defect): see the --out-issues
		// branch above — the identical reconciliation applies to Fixed.md.
		text, err = reconcileRevisionHeader(text, *outFixed)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: reconcile fixed revision: %v\n", err)
			return exitUsage
		}
		if err := os.WriteFile(*outFixed, []byte(text), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: write fixed: %v\n", err)
			return exitUsage
		}
		fmt.Printf("wrote %s (%d bytes)\n", *outFixed, len(text))
	}
	if *outIssues == "" && *outFixed == "" {
		fmt.Fprintln(os.Stderr, "sync db-to-md: at least one of --out-issues / --out-fixed is required")
		return exitUsage
	}
	return exitOK
}

// validateCmd asserts the §11.4 closed-set + clarity invariants over the DB.
func validateCmd(args []string) int {
	fs := flag.NewFlagSet("validate", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "validate: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate: %v\n", err)
		return exitUsage
	}

	statusSet := map[string]bool{}
	for _, s := range closedStatuses {
		statusSet[s] = true
	}
	typeSet := map[string]bool{"Bug": true, "Feature": true, "Task": true}

	var violations []string
	seen := map[string]bool{}
	for _, it := range items {
		// §11.4.54 — duplicate (atm_id, location, representation). The composite
		// PRIMARY KEY makes this impossible at the storage layer (the same id MAY
		// appear once per tracker, AND once per representation within a tracker —
		// a pipe-table 'table' row + an H2 'section' block, GAP A / HXC-044), but
		// we assert it explicitly for clarity. The key MUST include representation
		// so the legitimate dual-representation case is not a false duplicate.
		key := it.AtmID + "\x00" + it.CurrentLocation + "\x00" + it.repOrDefault()
		if seen[key] {
			violations = append(violations, fmt.Sprintf("duplicate atm_id in %s [%s]: %s",
				it.CurrentLocation, it.repOrDefault(), it.AtmID))
		}
		seen[key] = true

		// §11.4.15/21/90 — status closed-set.
		if !statusSet[it.Status] {
			violations = append(violations, fmt.Sprintf("%s: status %q not in closed-set", it.AtmID, it.Status))
		}
		// §11.4.16 — type closed-set.
		if !typeSet[it.Type] {
			violations = append(violations, fmt.Sprintf("%s: type %q not in {Bug,Feature,Task}", it.AtmID, it.Type))
		}
		// §11.4.91 — description ≥6 words OR ≥40 chars.
		if wordCount(it.Description) < 6 && len(it.Description) < 40 {
			violations = append(violations, fmt.Sprintf("%s: description too short (%d words / %d chars): %q",
				it.AtmID, wordCount(it.Description), len(it.Description), it.Description))
		}
		// §11.4.148 D3 — every Operator-blocked item MUST carry an
		// operator_block_details row whose unblock_condition enumerates the
		// closed list of decisions/actions that would unblock it ([A]…·[B]…).
		// A missing details row OR a bare-prose unblock condition (no enumerated
		// CHOICES) is a §11.4.148 D3 PASS-bluff.
		if it.Status == "Operator-blocked" {
			var unblock sql.NullString
			err := db.QueryRow(`SELECT unblock_condition FROM operator_block_details WHERE atm_id=?`,
				it.AtmID).Scan(&unblock)
			switch {
			case err == sql.ErrNoRows:
				violations = append(violations, fmt.Sprintf(
					"%s: Operator-blocked with no operator_block_details row (§11.4.148 D3)", it.AtmID))
			case err != nil:
				violations = append(violations, fmt.Sprintf(
					"%s: operator_block_details query: %v", it.AtmID, err))
			case !hasEnumeratedUnblockChoices(unblock.String):
				violations = append(violations, fmt.Sprintf(
					"%s: Operator-blocked unblock_condition has no enumerated unblock CHOICES (§11.4.148 D3): %q",
					it.AtmID, unblock.String))
			}
		}
	}

	// §11.4.93 renderability + §11.4.111 current_location closed-set (ATM-627).
	// The DB is the single source of truth (§11.4.95); a DB that `db-to-md`
	// cannot render is NOT a faithful source — regen is silently blocked. The
	// prior validate checked status/type/description only and returned exit 0
	// on such a DB (a §11.4.6/§11.4.93 bluff gate: green while regen impossible).
	// These two checks fail-closed on exactly that corruption class.

	// (a) current_location closed-set {Issues, Fixed}. A stray value such as the
	// half-migration artifact "Fixed.md" orphans the item: renderDocument scopes
	// its body lookup to current_location=document, so a "Fixed.md" item is
	// invisible to BOTH the Issues and the Fixed render (§11.4.19 atomic-migration
	// invariant broken).
	for _, it := range items {
		switch it.CurrentLocation {
		case "Issues", "Fixed":
			// ok
		default:
			violations = append(violations, fmt.Sprintf(
				"%s: current_location %q not in closed-set {Issues,Fixed} (§11.4.93/§11.4.111) [%s]",
				it.AtmID, it.CurrentLocation, it.repOrDefault()))
		}
	}

	// (b) renderability guard: every doc_segment item-reference MUST resolve to
	// an item at (current_location=document, representation). renderDocument
	// returns a hard error on the first dangling segment; surfacing it here as a
	// validation violation turns the silent regen-blocker into a caught, actionable
	// failure (§11.4.120 — the gate asserts the real "DB is renderable" invariant).
	for _, document := range []string{"Issues", "Fixed"} {
		if _, err := renderDocument(db, document); err != nil {
			violations = append(violations, fmt.Sprintf(
				"%s: DB not renderable by db-to-md (§11.4.93): %v", document, err))
		}
	}

	// (c) §11.4.135 DIRECT dangling-doc_segment integrity guard (ATM-627 defect
	// class). renderDocument (b) catches this INDIRECTLY — it aborts on the FIRST
	// unresolvable segment per document. danglingItemSegments asserts the same
	// invariant DIRECTLY via an explicit segment↔item join, so EVERY offending
	// segment is enumerated (not just the first-in-seq per document) and the
	// finding is a self-documenting integrity violation rather than a "not
	// renderable" side-effect. Composes with (b); does not replace it.
	if dangling, derr := danglingItemSegments(db); derr != nil {
		violations = append(violations, fmt.Sprintf("dangling-segment integrity query: %v", derr))
	} else {
		violations = append(violations, dangling...)
	}

	// (d) §11.4.93 / ATM-627 — REVERSE dangling-segment guard: item exists with NO
	// doc_segments row for its (atm_id, current_location, representation). (c) above
	// catches segment->no-item; renderDocument silently DROPS this class instead of
	// erroring (it only iterates existing doc_segments rows, so an item lacking one
	// is invisible to db-to-md with NO error surfaced) — the exact "db-to-md drops
	// segmentless items" defect ATM-627 reports. Without this guard, validate
	// reported OK on a DB that would silently regenerate Issues.md/Fixed.md missing
	// every segmentless item (a §11.4.6/§11.4.93 bluff gate).
	if missing, merr := itemsMissingSegments(db); merr != nil {
		violations = append(violations, fmt.Sprintf("missing-segment integrity query: %v", merr))
	} else {
		violations = append(violations, missing...)
	}

	// (e) §11.4.93 / ATM-627 (task #20) — column↔body Status desync guard. items.status
	// is authoritative (§11.4.95); when a direct `UPDATE items SET status=…` bypasses
	// renderItemBody it advances the column while body_md's `**Status:**` line stays
	// stale → `sync db-to-md` (renderDocument) would emit the stale line, misreporting
	// the item to every reader. The prior validate checked the status CLOSED-SET only,
	// never column↔body agreement, so a desynced item passed exit 0 (a §11.4.6/§11.4.93
	// bluff gate). This guard fails-closed on exactly that class; the generator-symmetry
	// half (canonicalizeBodyStatusLine, wired into renderDocument, parse.go) prevents
	// recurrence by emitting the Status line from the column. Composes with (b)/(c) —
	// orthogonal invariants (those: segment↔item location; this: column↔body Status).
	violations = append(violations, statusColumnBodyDesyncs(items)...)

	// (f) §11.4.15 / §11.4.148 / ATM-627 INTEG-03 — location↔status invariant. A
	// Fixed-location item MUST carry a terminal closed-set status (a `… (→ Fixed.md)`
	// value); a NON-terminal status at Fixed (e.g. Reopened) is the exact INTEG-03
	// desync — the pre-fix `reopen` flipped status→Reopened WITHOUT migrating
	// current_location Fixed→Issues, stranding a non-terminal item in the CLOSED
	// archive. The prior validate never asserted location↔status, so such an item
	// passed exit 0 while every tracker reader saw a non-terminal item in Fixed (a
	// §11.4.6/§11.4.15 bluff gate). This guard fails-closed on exactly that class;
	// composes with (e) — orthogonal invariants (that: column↔body Status agreement;
	// this: current_location↔status closed-set agreement).
	violations = append(violations, fixedLocationNonTerminalStatus(items)...)

	// (f2) §11.4.15 / §11.4.19 / ATM-627 INTEG-03 — the MIRROR half of (f). An
	// Issues-location item MUST carry a NON-terminal status. (f) only ever asserted
	// Fixed ⇒ terminal, so the opposite desync — a terminal `… (→ Fixed.md)` status on
	// a row still in the OPEN tracker, produced by any bare status write that skipped
	// the §11.4.19 atomic migration — passed exit 0 while every reader saw a closed
	// item listed as open (a §11.4.6/§11.4.15 bluff gate). Both halves now share ONE
	// predicate source, terminalStatuses(), so they can never drift apart.
	violations = append(violations, issuesLocationTerminalStatus(items)...)

	// (g) §11.4.5 / §11.4.69 / §11.4.123 / §11.4.226 — closure-evidence
	// RESOLVABILITY. A closed item's item_history rows carry evidence_path: the
	// pointer to the captured proof that IS the closure's warrant. Nothing ever
	// asserted that pointer RESOLVES, so a closure could record a narrative
	// paragraph, or a well-formed path to a file that was never committed, and
	// still read as evidence-backed everywhere downstream (HXC-217: 16 such rows
	// across 14 tickets — 12 narrative, 4 clean-but-never-populated paths whose
	// real evidence had landed elsewhere). An unresolvable evidence_path is a
	// §11.4.226(2) "class proven by a LABEL, not by machine fields" bluff: the
	// closure claims captured proof that cannot be produced on demand.
	//
	// Scoped to CLOSED items deliberately (§11.4.201(1) — a guard must assert the
	// REAL condition and refuse nothing else): the mandate is that a CLOSURE's
	// evidence resolves. An open item's in-progress note is not a closure claim.
	if unresolvable, uerr := unresolvableClosureEvidence(db); uerr != nil {
		violations = append(violations, fmt.Sprintf("closure-evidence integrity query: %v", uerr))
	} else {
		violations = append(violations, unresolvable...)
	}

	// (h) §11.4.33 / BOB-240 — Type↔Status mapping invariant: a Fixed-location
	// item's terminal status must match its Type's mandated closure vocabulary
	// (Bug→Fixed, Feature→Implemented, Task→Completed; Obsolete valid for any
	// Type). CONFIRMED this session that `validate: OK` ran repeatedly against
	// a DB simultaneously holding 30+ live violations of exactly this class
	// (BOB-239) — the existing invariant set checked location↔status
	// ((f)/(f2)) and the status/type closed-sets independently, but never
	// their AGREEMENT. Composes with (f)/(f2) — orthogonal invariants (those:
	// location↔status closed-set membership; this: Type↔Status vocabulary
	// agreement).
	violations = append(violations, typeStatusMismatches(items)...)

	if len(violations) > 0 {
		sort.Strings(violations)
		fmt.Fprintf(os.Stderr, "validate: %d violation(s):\n", len(violations))
		for _, v := range violations {
			fmt.Fprintf(os.Stderr, "  - %s\n", v)
		}
		return exitUsage
	}
	fmt.Printf("validate: OK — %d items, all invariants satisfied\n", len(items))
	return exitOK
}

// danglingItemSegments returns, for the ATM-627 dangling-doc_segment defect
// CLASS, a human-readable description of every doc_segments row with kind='item'
// whose (atm_id, document, representation) has NO matching item at
// (atm_id, current_location=document, representation) — i.e. the invariant
// "item.current_location must equal the document of every doc_segment that
// belongs to that item" is violated.
//
// This is the DIRECT, first-class integrity assertion of the §11.4.135 guard,
// decoupled from renderDocument's control-flow side-effect. It is read-only, so
// it can never break an existing valid DB.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with
// `return nil, nil` removes the guard; atm627_integrity_guard_test.go then FAILs
// — proving the guard is not a tautology.
func danglingItemSegments(db *sql.DB) ([]string, error) {
	// A kind='item' segment is DANGLING when the LEFT JOIN to items on
	// (atm_id, current_location=document, representation) finds no partner. The
	// representation defaults to 'section' on both sides (COALESCE) to mirror
	// renderDocument's body-lookup key exactly.
	rows, err := db.Query(`
		SELECT s.document, s.seq, s.atm_id, COALESCE(s.representation,'section')
		FROM doc_segments s
		LEFT JOIN items i
		  ON i.atm_id = s.atm_id
		 AND i.current_location = s.document
		 AND COALESCE(i.representation,'section') = COALESCE(s.representation,'section')
		WHERE s.kind = 'item'
		  AND s.atm_id IS NOT NULL
		  AND i.atm_id IS NULL
		ORDER BY s.document, s.seq`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []string
	for rows.Next() {
		var document, atmID, rep string
		var seq int
		if err := rows.Scan(&document, &seq, &atmID, &rep); err != nil {
			return nil, err
		}
		out = append(out, fmt.Sprintf(
			"dangling item-segment (document=%s, seq=%d, atm_id=%s, rep=%s): no item at current_location=%s (§11.4.135/ATM-627)",
			document, seq, atmID, rep, document))
	}
	return out, rows.Err()
}

// terminalStatuses is the closed set of Fixed-location statuses, derived from
// closeStatusMap's terminal .status values so it can NEVER drift from the closer
// (add a new close status keyword → this set gains it automatically). These are the
// only statuses a current_location='Fixed' item may carry.
func terminalStatuses() map[string]bool {
	out := make(map[string]bool, len(closeStatusMap))
	for _, m := range closeStatusMap {
		out[m.status] = true
	}
	return out
}

// fixedLocationNonTerminalStatus returns, for the ATM-627 INTEG-03 location↔status
// defect CLASS, a description of every item at current_location='Fixed' whose status
// is NOT a terminal closed-set value (a `… (→ Fixed.md)` value). A non-terminal status
// in the Fixed archive means the item is not actually closed — it belongs in Issues.
// This is the detective gate for the reopen-does-not-relocate defect: after the fix a
// reopened item migrates to Issues, so a correctly-reopened DB has ZERO findings here.
// Read-only, so it can never break an already-consistent DB.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return nil`
// removes the guard; TestValidate_CatchesReopenedInFixed (RED polarity per §11.4.115)
// then FAILs — proving the guard is not a tautology.
func fixedLocationNonTerminalStatus(items []item) []string {
	terminal := terminalStatuses()
	var out []string
	for _, it := range items {
		if it.CurrentLocation != "Fixed" {
			continue
		}
		if !terminal[strings.TrimSpace(it.Status)] {
			out = append(out, fmt.Sprintf(
				"%s: Fixed-location item has NON-terminal status %q — a Fixed-location item must carry a terminal `… (→ Fixed.md)` status; a non-terminal item belongs in Issues (§11.4.15/ATM-627 INTEG-03) [%s]",
				it.AtmID, it.Status, it.repOrDefault()))
		}
	}
	return out
}

// issuesLocationTerminalStatus returns, for the MIRROR half of the ATM-627 INTEG-03
// location↔status defect CLASS, a description of every item at
// current_location='Issues' whose status IS a terminal closed-set value (a
// `… (→ Fixed.md)` value). A terminal status in the OPEN tracker means the item was
// closed WITHOUT the §11.4.19 atomic migration: it neither disappears from the open
// summary nor appears in the closed one, so every tracker reader sees a closed item
// listed as open work.
//
// WHY THIS EXISTS SEPARATELY FROM fixedLocationNonTerminalStatus. That function
// asserts Fixed ⇒ terminal; this one asserts Issues ⇒ NON-terminal. They are the two
// halves of ONE invariant, and only the first was ever implemented — so `update
// --status` could write a terminal value onto an Issues row and validate reported
// "OK — all invariants satisfied". Control-needled on a real corpus before this fix:
// the guarded direction had ZERO violations while the unguarded direction had ten,
// and the SAME validate on the SAME DB through the SAME path fired immediately when
// the guarded direction was injected — proving the silence was a genuine gap and not
// a blind instrument (§11.4.201(6)(7)(b)).
//
// A WRITE-SEAM GUARD ALONE IS NOT ENOUGH (§11.4.146(D3) full-table sweep): rows
// written before the preventive guard existed, and anything writing raw SQL that
// bypasses the CLI entirely, are invisible to a diff-only or forward-only check.
// Read-only, so it can never break an already-consistent DB.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return nil`
// removes the guard; TestValidate_CatchesTerminalStatusAtIssues (RED polarity per
// §11.4.115) then FAILs — proving the guard is not a tautology.
func issuesLocationTerminalStatus(items []item) []string {
	terminal := terminalStatuses()
	var out []string
	for _, it := range items {
		if it.CurrentLocation != "Issues" {
			continue
		}
		if terminal[strings.TrimSpace(it.Status)] {
			out = append(out, fmt.Sprintf(
				"%s: Issues-location item has TERMINAL status %q — a closed item must live at Fixed; the §11.4.19 closure migration was skipped (use `close` for a new closure, or `move --to Fixed` to reconcile one already closed elsewhere) (§11.4.15/ATM-627 INTEG-03) [%s]",
				it.AtmID, it.Status, it.repOrDefault()))
		}
	}
	return out
}

// typeStatusMismatches returns, for the BOB-240 §11.4.33 Type↔Status defect
// CLASS, a description of every Fixed-location item whose TERMINAL status
// does not match its Type's mandated closure vocabulary (Bug→Fixed,
// Feature→Implemented, Task→Completed; Obsolete valid for ANY Type —
// criterion 5). Confirmed this session that `validate: OK` ran repeatedly
// against a DB simultaneously holding 30+ live violations of exactly this
// class (BOB-239) — the existing invariant set checked location↔status
// ((f)/(f2), fixedLocationNonTerminalStatus/issuesLocationTerminalStatus) and
// the status/type CLOSED-SETS independently (validateCmd's statusSet/
// typeSet), but never their AGREEMENT. Scoped to items already confirmed
// terminal-at-Fixed (terminalStatuses()[ns]) deliberately — a Fixed-location
// item with a NON-terminal status is (f)'s own, DIFFERENT finding, and
// double-reporting it here under the wrong invariant would misattribute the
// defect (§11.4.201(1)). Read-only, so it can never break an already-
// consistent DB.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return
// nil` removes the guard; TestValidate_CatchesTypeStatusMismatch (RED
// polarity per §11.4.115) then FAILs — proving the guard is not a tautology.
func typeStatusMismatches(items []item) []string {
	terminal := terminalStatuses()
	var out []string
	for _, it := range items {
		if it.CurrentLocation != "Fixed" {
			continue
		}
		ns := strings.TrimSpace(it.Status)
		if !terminal[ns] {
			// Non-terminal-at-Fixed is fixedLocationNonTerminalStatus's OWN
			// finding (check (f)) — skip here to avoid a duplicate/incorrect
			// Type↔Status claim piled on top of an already-reported different
			// defect class.
			continue
		}
		if wantKeyword, wantStatus, mismatch := typeStatusMismatch(it.Type, ns); mismatch {
			out = append(out, fmt.Sprintf(
				"%s: Type=%s closed with status %q — §11.4.33 requires %q (`close --status %s`); Obsolete is valid for any Type [%s]",
				it.AtmID, it.Type, it.Status, wantStatus, wantKeyword, it.repOrDefault()))
		}
	}
	return out
}

// unresolvableClosureEvidence returns, for the HXC-217 unresolvable-evidence
// defect CLASS, a human-readable description of every item_history row that
// (a) IS ITSELF a closure event (event_type one of Fixed/Implemented/
// Completed/Obsolete — the SAME closed set correct_evidence.go's
// closureEvents recognises, §11.4.33), (b) belongs to an item whose CURRENT
// status is one of the four terminal closed-set values, and (c) carries a
// non-empty evidence_path that does NOT resolve to an existing filesystem
// entry.
//
// TASK-54 / BOB-010 id=64 FIX (2026-08-18): clause (a) — the event_type
// filter — was MISSING. The query previously checked ONLY the item's current
// status, so a non-closure history row (Updated/Reopened/Opened) belonging to
// an item that HAPPENS to be closed today was wrongly treated as a closure's
// captured-proof claim. FACT: BOB-010's real closure (history id=4,
// event=Completed) recorded a resolvable evidence_path; a LATER `Updated`
// row (history id=64) recorded evidence_path="scripts/docs_chain.sh" — a
// path that stopped resolving after that script was git-mv'd to
// scripts/workable-items-export.sh (commits 0558399/d9d512d). An `Updated`
// row is ordinary history-trail narrative, never a re-assertion of the
// closure's evidence (§11.4.5/§11.4.69/§11.4.123/§11.4.226 bind the CLOSURE
// event's pointer, not every subsequent note on an already-closed item), so
// checking it was over-scoping that mechanically BLOCKED `workable-items
// validate` on a healthy tracker the moment any closure-adjacent path was
// renamed. See TestClosureEvidence_UpdatedEventOnClosedItem_UnresolvablePath_NoViolation
// for the RED→GREEN regression guard.
//
// Path anchoring reuses resolveInvocationRelative (the HXC-201 mechanism): an
// absolute path is taken as-is, a relative one is anchored against the INVOKING
// shell's $PWD rather than this process's cwd — mandatory because `go run -C`
// relocates the child's cwd into this tool's own source tree, which would make
// every repo-root-relative evidence path fail and turn this guard into exactly
// the §11.4.201(1) false-positive refusal it must never become.
//
// The message distinguishes the two observed sub-classes so a finding is
// actionable in one read (§11.4.201(5) — a refusal prints its resolved
// evidence): a value carrying whitespace/newlines is narrative or a multi-value
// list pasted into a single-path field; a clean single token is a well-formed
// path that was never populated.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with
// `return nil, nil` removes the guard; validate_evidence_test.go then FAILs —
// proving the guard is not a tautology.
func unresolvableClosureEvidence(db *sql.DB) ([]string, error) {
	rows, err := db.Query(`
		SELECT h.id, h.atm_id, h.event_type, h.on_date, h.evidence_path
		FROM item_history h
		WHERE h.evidence_path IS NOT NULL
		  AND TRIM(h.evidence_path) <> ''
		  AND h.event_type IN ('Fixed', 'Implemented', 'Completed', 'Obsolete')
		  AND EXISTS (
		        SELECT 1 FROM items i
		        WHERE i.atm_id = h.atm_id
		          AND i.status IN (
		                'Fixed (→ Fixed.md)', 'Implemented (→ Fixed.md)',
		                'Completed (→ Fixed.md)', 'Obsolete (→ Fixed.md)'))
		ORDER BY h.atm_id, h.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []string
	for rows.Next() {
		var id int
		var atmID, event, onDate, evidence string
		if err := rows.Scan(&id, &atmID, &event, &onDate, &evidence); err != nil {
			return nil, err
		}
		if _, statErr := os.Stat(resolveInvocationRelative(evidence)); statErr == nil {
			continue
		}
		kind := "well-formed path, but nothing exists there"
		if strings.ContainsAny(evidence, " \t\r\n") {
			kind = "narrative or multi-value text in a single-path field"
		}
		out = append(out, fmt.Sprintf(
			"%s: closure evidence_path does not resolve (%s) — history id=%d, event=%s, on=%s: %q (§11.4.5/§11.4.69/§11.4.123/§11.4.226 — a closure's captured proof must be producible on demand)",
			atmID, kind, id, event, onDate, firstLine(evidence)))
	}
	return out, rows.Err()
}

// firstLine keeps a violation message single-line + bounded when the offending
// evidence_path holds a multi-line narrative, so one bad row cannot flood the
// validator's output and hide its siblings.
func firstLine(s string) string {
	if i := strings.IndexAny(s, "\r\n"); i >= 0 {
		s = s[:i] + " …"
	}
	if len(s) > 120 {
		s = s[:120] + " …"
	}
	return s
}

// itemsMissingSegments is the REVERSE of danglingItemSegments: it returns, for
// EVERY item at (atm_id, current_location, representation) that has NO matching
// doc_segments row (kind='item', document=current_location, atm_id, representation),
// a human-readable description of the gap. This is the direct-integrity assertion of
// the ATM-627 "db-to-md drops N segmentless items" defect class: renderDocument
// (validateCmd check (b)) walks doc_segments in seq order and only ever emits items
// THAT HAVE a segment row — an item with none is simply never visited, so
// renderDocument returns NO error and a naive `db-to-md` regen SILENTLY OMITS the
// item from the regenerated Markdown. Before this guard, `validate` reported "OK"
// on a DB in exactly that state (112 items on the live tree, captured 2026-07-05) —
// a §11.4.6/§11.4.93 bluff gate: green while regen is lossy.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return nil, nil`
// removes the guard; TestATM627_SegmentBackfill_ValidateCatchesMissingSegments (RED
// polarity per §11.4.115) then FAILs — proving the guard is not a tautology.
func itemsMissingSegments(db *sql.DB) ([]string, error) {
	rows, err := db.Query(`
		SELECT i.atm_id, i.current_location, COALESCE(i.representation,'section')
		FROM items i
		LEFT JOIN doc_segments s
		  ON s.atm_id = i.atm_id
		 AND s.document = i.current_location
		 AND COALESCE(s.representation,'section') = COALESCE(i.representation,'section')
		 AND s.kind = 'item'
		WHERE s.id IS NULL
		ORDER BY i.current_location, i.atm_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []string
	for rows.Next() {
		var atmID, document, rep string
		if err := rows.Scan(&atmID, &document, &rep); err != nil {
			return nil, err
		}
		out = append(out, fmt.Sprintf(
			"missing item-segment (atm_id=%s, rep=%s): item at current_location=%s has NO doc_segments row — db-to-md would silently drop it (§11.4.93/ATM-627)",
			atmID, rep, document))
	}
	return out, rows.Err()
}

// statusColumnBodyDesyncs returns a human-readable description of every item whose
// authoritative items.status column DISAGREES with the Status the md→db parser would
// derive from its body_md (lastBodyStatus). This is the ATM-627 (task #20) DURABLE
// guard for the column↔body Status desync CLASS: a direct `UPDATE items SET status=…`
// that bypasses renderItemBody advances the column while body_md's `**Status:**` line
// stays stale → `sync db-to-md` would emit the stale line, misreporting the item's
// state to every tracker reader. The prior validate checked the status CLOSED-SET only,
// never column↔body agreement, so a desynced item passed exit 0 (a §11.4.6/§11.4.93
// bluff gate: green while db-to-md emits a wrong Status).
//
// Read-only — it can never break a valid DB. Items whose body carries NO `**Status:**`
// line are SKIPPED (nothing to compare); only a PRESENT-but-disagreeing line is a
// violation. Generator-symmetric (§11.4.93): the oracle IS the parser's own column
// derivation (lastBodyStatus → normalizeStatus, last-Status-line-wins), so a body whose
// Status line carries trailing prose / a `**Priority:**` tail / multiple `**Status:**`
// tokens normalises to the column it was first derived from and is NOT a false positive.
// Composes with the R3 dangling-segment guard (danglingItemSegments) — orthogonal
// invariants (that: segment↔item location; this: column↔body Status).
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return nil`
// removes the guard; atm627_status_desync_test.go then FAILs — proving the guard is
// NOT a tautology.
func statusColumnBodyDesyncs(items []item) []string {
	var out []string
	for _, it := range items {
		// The `**Status:**`-line invariant governs H2 'section' bodies. A 'table'
		// representation carries its Status in the pipe cell (emitLegacyTable /
		// export.go pipe-row synthesizer), NOT a `**Status:**` line, so it is out of
		// scope for THIS guard (skipping it avoids a false positive against a valid
		// pipe row that legitimately has no `**Status:**` line).
		if it.repOrDefault() != "section" {
			continue
		}
		// deriveStatusFromBody: mirror buildItem's FULL column derivation for a section
		// body — the normalised last `**Status:**` line, OR buildItem's struct-default
		// "Queued" when the section body carries NO `**Status:**` line at all (an empty
		// / status-less body: md→db would set the column to "Queued", so a column that
		// is NOT "Queued" is NOT recoverable from body_md — the SPK-512/519/609
		// empty-body class). This is the exact generator-symmetric oracle.
		want, hasLine := lastBodyStatus(it.BodyMD)
		if !hasLine {
			want = "Queued"
		}
		if want == it.Status {
			continue
		}
		detail := fmt.Sprintf("body_md **Status:** line derives %q", want)
		if !hasLine {
			detail = "body_md has NO **Status:** line (md→db would derive \"Queued\")"
		}
		out = append(out, fmt.Sprintf(
			"%s [%s/%s]: items.status=%q but %s (§11.4.93/ATM-627 column↔body desync)",
			it.AtmID, it.CurrentLocation, it.repOrDefault(), it.Status, detail))
	}
	return out
}

// diffCmd reports items whose parsed-from-Markdown state differs from the DB.
func diffCmd(args []string) int {
	fs := flag.NewFlagSet("diff", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	issuesPath := fs.String("issues", "", "path to Issues.md")
	fixedPath := fs.String("fixed", "", "path to Fixed.md")
	// BOB-155: the explicit opt-in for the DB-internal-integrity-only shape.
	// It exists so the blanket refusal below cannot silently delete the
	// documented desync-only capability (statusColumnBodyDesyncs, wired at the
	// top of this function) — that shape survives, but it must be asked for BY
	// NAME rather than being what you get by forgetting a flag.
	dbOnly := fs.Bool("db-only", false,
		"run ONLY the DB-internal integrity checks and read no Markdown (the verdict says so)")
	// BOB-186: the named opt-in for the PARTIAL-Markdown shape, mirroring what
	// --db-only did for the no-Markdown shape. The per-tracker comparison is a
	// real, documented capability (see the "Restrict the 'absent in Markdown'
	// pass" comment below) and is NOT deleted by the accounting guard (§11.4.122
	// forbids silently removing an existing capability) — it survives, but must
	// be asked for BY NAME rather than being what you get by forgetting a flag.
	partialScope := fs.Bool("partial-scope", false,
		"compare ONLY the trackers whose paths were supplied; the verdict names the DB "+
			"locations it did not cover and never claims a full DB-vs-Markdown sync")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "diff: --db is required")
		return exitUsage
	}

	// BOB-155 (§11.4.201(6) false-null, severity High). Without this refusal,
	// `diff --db <p>` with no Markdown paths fell through to the unconditional
	// success verdict and printed "DB and Markdown are in sync" — BYTE-IDENTICAL
	// to a genuinely successful comparison — having opened zero Markdown files.
	// A blind instrument and a clean tree returned the same reassuring output,
	// so no reader could tell them apart, inside the very tool whose job is to
	// verify that sync. Measured 2026-08-21: with a planted `**Status:**`
	// divergence the flagless form said "in sync" (exit 0) while the path-ful
	// form correctly reported 2 difference(s) (exit 1).
	//
	// REFUSE rather than default to conventional paths: (1) the sibling
	// subcommands in this same file — syncMDToDB and syncDBToMD — already
	// refuse when all of their own path flags are absent, so refusing keeps
	// diff consistent with its siblings instead of making it the exception;
	// (2) this command ships in a submodule consumed by multiple projects
	// (§11.4.28), and a "conventional path" default would have to hardcode one
	// consumer's tracker layout as a project literal, which is exactly what a
	// decoupled submodule may not carry; (3) fail-closed is the conservative
	// default when an input to correctness is unverifiable (§11.4.252).
	haveMarkdown := *issuesPath != "" || *fixedPath != ""
	if !haveMarkdown && !*dbOnly {
		fmt.Fprintln(os.Stderr,
			"diff: at least one of --issues / --fixed is required — refusing to report a "+
				"DB-vs-Markdown verdict without reading any Markdown "+
				"(pass --db-only to run just the DB-internal integrity checks)")
		return exitUsage
	}
	// Mixing the modes would make the verdict misdescribe what was actually
	// read, which is the same class of defect as the false-null itself.
	if haveMarkdown && *dbOnly {
		fmt.Fprintln(os.Stderr,
			"diff: --db-only is mutually exclusive with --issues / --fixed")
		return exitUsage
	}
	// Same rationale, one flag over: --db-only compares NO Markdown, while
	// --partial-scope asserts something about WHICH Markdown trackers were
	// compared. Accepting both would mean silently ignoring one of them, which is
	// how a verdict starts misdescribing its own inputs — the same defect class
	// as the false-null itself.
	if *dbOnly && *partialScope {
		fmt.Fprintln(os.Stderr,
			"diff: --partial-scope is meaningless with --db-only, which compares no "+
				"Markdown at all — pass one or the other")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diff: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	dbItems, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diff: %v\n", err)
		return exitUsage
	}

	// BOB-186 (§11.4.201(6) false-null, severity High — the PARTIAL-read sibling
	// of the BOB-155 no-read false-null fixed above).
	//
	// Measured 2026-08-25 on a live 185-row registry:
	//
	//	$ workable-items diff --db docs/workable_items.db --issues docs/Issues.md
	//	diff: DB and Markdown are in sync (compared 77 Markdown item(s)
	//	                                   against 185 DB item(s); read docs/Issues.md)
	//	exit 0
	//
	// 77 against 185. The verdict printed BOTH numbers and still said "in sync".
	// The 107 rows located in Fixed were never compared against anything — the
	// terminal "absent in Markdown" pass deliberately (and CORRECTLY) skips a
	// tracker whose path the caller did not supply, so it would not manufacture
	// false positives; but the VERDICT then claimed a full DB-vs-Markdown sync it
	// had not performed. A partially blind instrument returned the same quiet
	// green a genuinely synced corpus returns, and no reader could tell them
	// apart from the output alone. Load-bearing: consuming projects wire this
	// verdict into their §11.4.106(F) commit seam, so a caller passing only
	// --issues was told the docs chain was clean while Fixed had silently
	// diverged.
	//
	// THE RULE: a DB-vs-Markdown verdict may only be emitted when the supplied
	// Markdown paths ACCOUNT FOR every DB item's current_location. Anything else
	// is refused (§11.4.201(4) conservative-safe default; consistent with the
	// no-paths refusal directly above and with diff's siblings syncMDToDB /
	// syncDBToMD, which likewise refuse rather than guess).
	//
	// KEYED ON MEASURED DB CONTENT, NEVER ON "were both flags given". A DB
	// holding zero Fixed rows IS fully accounted for by --issues alone and must
	// still pass — refusing it would trade this false-null for a §11.4.201(1)
	// false-positive refusal, which is forbidden in the same breath.
	//
	// The location set is CHECK-constrained by the schema to exactly
	// {'Issues','Fixed'} (schema.sql: current_location TEXT NOT NULL CHECK
	// (current_location IN ('Issues','Fixed'))), so every location has a
	// corresponding path flag and none can be structurally unaccountable. These
	// are the TOOL'S OWN schema literals, not a consumer's tracker filenames —
	// no project literal enters the submodule (§11.4.28).
	type trackerScope struct {
		location string // schema current_location value
		flag     string // the flag that supplies its Markdown
		supplied bool
	}
	trackers := []trackerScope{
		{location: "Issues", flag: "--issues", supplied: *issuesPath != ""},
		{location: "Fixed", flag: "--fixed", supplied: *fixedPath != ""},
	}
	// Deterministic order: iterate the fixed slice, never a map.
	type unaccountedTracker struct {
		location string
		flag     string
		rows     int
	}
	var unaccounted []unaccountedTracker
	unaccountedRowTotal := 0
	if haveMarkdown {
		for _, tr := range trackers {
			if tr.supplied {
				continue
			}
			rows := 0
			for _, it := range dbItems {
				if it.CurrentLocation == tr.location {
					rows++
				}
			}
			if rows > 0 {
				unaccounted = append(unaccounted, unaccountedTracker{
					location: tr.location, flag: tr.flag, rows: rows,
				})
				unaccountedRowTotal += rows
			}
		}
	}
	if len(unaccounted) > 0 && !*partialScope {
		// Print the RESOLVED EVIDENCE on the refusal (§11.4.201(5)): which
		// location, how many rows, and which flag supplies it — so a false
		// positive, if one ever occurs, is diagnosable in one step.
		var parts []string
		for _, u := range unaccounted {
			parts = append(parts, fmt.Sprintf("%d item(s) located in %s (supply %s)",
				u.rows, u.location, u.flag))
		}
		fmt.Fprintf(os.Stderr,
			"diff: refusing to report a DB-vs-Markdown verdict that would silently "+
				"exclude part of the DB — the supplied Markdown path(s) do not account "+
				"for %s. Supply the missing path(s) for a full verdict, or pass "+
				"--partial-scope to compare only the trackers supplied and receive a "+
				"scope-limited verdict.\n", strings.Join(parts, "; "))
		return exitUsage
	}

	// §11.4.93/ATM-627 defense-in-depth: diff ALSO surfaces the column<->body_md
	// Status DESYNC class (items.status disagreeing with the last **Status:**
	// line in body_md) independently of the Markdown-vs-DB comparison below.
	// validateCmd (the "correct home" per Constitution.md §11.4.93, since it is
	// the DB-internal-integrity gate) already asserts this via
	// statusColumnBodyDesyncs; wiring the SAME check into diff closes a real gap
	// in diff's OWN invocation surface: `diff --db <path>` with NEITHER
	// --issues NOR --fixed given performs no Markdown comparison at all (every
	// DB item is trivially reported "absent in Markdown" — uninformative noise
	// for this purpose), so a pure DB-internal desync was invisible to that
	// invocation shape. Reproduced + fixed 2026-07-07 (workable-items §11.4.93
	// tooling-integrity gate); see sync_diff_desync_test.go for the RED/GREEN
	// polarity proof.
	desyncs := statusColumnBodyDesyncs(dbItems)
	for _, d := range desyncs {
		fmt.Printf("! %s\n", d)
	}

	// Key by the COMPOSITE identity (atm_id, current_location, representation) —
	// the schema PRIMARY KEY — NOT by atm_id alone. loadItems returns one row per
	// composite key (an atm_id MAY appear once per tracker AND once per
	// representation within a tracker — a pipe-table 'table' row + an H2 'section'
	// block, GAP A / HXC-044), and renderDocument (db.go) already keys its body
	// lookup by id + "\x00" + representation for exactly this reason. Collapsing
	// to atm_id alone here kept only the LAST-loaded row, so the OTHER parsed
	// representation was compared against the wrong DB row → a spurious "body
	// differs" / "type differs" false-positive while validate + the round-trip
	// gate both PASS.
	itemKey := func(it item) string {
		return it.AtmID + "\x00" + it.CurrentLocation + "\x00" + it.repOrDefault()
	}
	dbByID := map[string]item{}
	for _, it := range dbItems {
		dbByID[itemKey(it)] = it
	}

	var parsed []item
	if *issuesPath != "" {
		c, err := os.ReadFile(*issuesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diff: read issues: %v\n", err)
			return exitUsage
		}
		its, _ := parseIssues(string(c))
		parsed = append(parsed, its...)
	}
	if *fixedPath != "" {
		c, err := os.ReadFile(*fixedPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diff: read fixed: %v\n", err)
			return exitUsage
		}
		its, _ := parseFixed(string(c))
		parsed = append(parsed, its...)
	}

	// Gate the parsed-vs-DB comparison on actually having Markdown to compare
	// against. When BOTH --issues and --fixed are absent (the desync-only
	// invocation shape documented at sync.go:618-630) there is no Markdown to
	// parse; running the two compare loops below still iterated `dbItems` with
	// an empty `parsedSeen` map and reported EVERY DB row as
	// "- <id> present in DB, absent in Markdown" — a false-positive equal to
	// the DB row count (102 in-repo, 2026-08-10; forensic FACT: reproduced on
	// a state where `sync db-to-md` writes byte-identical output to the
	// on-disk Issues.md/Fixed.md, so DB and Markdown were provably in-sync).
	// The desync check above (statusColumnBodyDesyncs) is ORTHOGONAL — it is
	// a DB-internal integrity gate that does not read Markdown — and runs
	// unconditionally, exactly as the block comment intended. When at least
	// one path IS given, we perform the comparison against the subset of
	// trackers actually provided (issues-only or fixed-only invocation stays
	// meaningful for its own tracker).
	differences := 0
	if haveMarkdown {
		parsedSeen := map[string]bool{}
		for _, p := range parsed {
			parsedSeen[itemKey(p)] = true
			d, ok := dbByID[itemKey(p)]
			if !ok {
				fmt.Printf("+ %s present in Markdown, absent in DB\n", p.AtmID)
				differences++
				continue
			}
			if p.Status != d.Status {
				fmt.Printf("~ %s status: md=%q db=%q\n", p.AtmID, p.Status, d.Status)
				differences++
			}
			if p.Type != d.Type {
				fmt.Printf("~ %s type: md=%q db=%q\n", p.AtmID, p.Type, d.Type)
				differences++
			}
			if p.BodyMD != d.BodyMD {
				fmt.Printf("~ %s body differs (md=%d bytes db=%d bytes)\n", p.AtmID, len(p.BodyMD), len(d.BodyMD))
				differences++
			}
		}
		// Restrict the "absent in Markdown" pass to trackers the caller actually
		// supplied. When --issues is given without --fixed we compare Issues rows
		// only; missing-in-Fixed lines would be their own class of false positive
		// against Fixed rows the caller never asked about. Same in reverse.
		for _, d := range dbItems {
			if d.CurrentLocation == "Issues" && *issuesPath == "" {
				continue
			}
			if d.CurrentLocation == "Fixed" && *fixedPath == "" {
				continue
			}
			if !parsedSeen[itemKey(d)] {
				fmt.Printf("- %s present in DB, absent in Markdown\n", d.AtmID)
				differences++
			}
		}
	}

	differences += len(desyncs)

	// BOB-155 acceptance: the verdict NAMES its inputs, always. This is what
	// lets a reader distinguish a real comparison from a vacuous one by reading
	// the output alone — the property whose absence made the false-null
	// invisible. The --db-only verdict deliberately never uses the phrase "DB
	// and Markdown are in sync", because it compared no Markdown.
	if *dbOnly {
		if differences == 0 {
			fmt.Printf("diff: DB-internal checks passed — %d item(s) inspected; "+
				"no Markdown compared (--db-only)\n", len(dbItems))
			return exitOK
		}
		fmt.Printf("diff: %d DB-internal difference(s) across %d item(s); "+
			"no Markdown compared (--db-only)\n", differences, len(dbItems))
		return exitUsage
	}

	var sources []string
	if *issuesPath != "" {
		sources = append(sources, *issuesPath)
	}
	if *fixedPath != "" {
		sources = append(sources, *fixedPath)
	}
	read := strings.Join(sources, ", ")

	// BOB-186: the verdict's SHAPE is decided by the MEASURED unaccounted set,
	// never by the flag. --partial-scope grants PERMISSION to proceed; it does not
	// change what is true. So a --partial-scope run that turns out to account for
	// every DB row still gets the ordinary full-sync verdict, and a scope-limited
	// run NEVER gets to say "in sync" — the phrase is reserved, by construction,
	// for a comparison that actually covered the whole DB.
	if len(unaccounted) > 0 {
		var skipped []string
		for _, u := range unaccounted {
			skipped = append(skipped, fmt.Sprintf("%d in %s (no %s supplied)",
				u.rows, u.location, u.flag))
		}
		notCovered := strings.Join(skipped, "; ")
		if differences == 0 {
			fmt.Printf("diff: PARTIAL SCOPE — no differences within the tracker(s) compared "+
				"(compared %d Markdown item(s); read %s), but %d of %d DB item(s) were NOT "+
				"compared: %s. This is NOT a full DB-vs-Markdown sync verdict.\n",
				len(parsed), read, unaccountedRowTotal, len(dbItems), notCovered)
			return exitOK
		}
		fmt.Printf("diff: PARTIAL SCOPE — %d difference(s) within the tracker(s) compared "+
			"(compared %d Markdown item(s); read %s), and %d of %d DB item(s) were NOT "+
			"compared: %s.\n", differences, len(parsed), read,
			unaccountedRowTotal, len(dbItems), notCovered)
		return exitUsage
	}

	if differences == 0 {
		fmt.Printf("diff: DB and Markdown are in sync (compared %d Markdown item(s) "+
			"against %d DB item(s); read %s)\n", len(parsed), len(dbItems), read)
		return exitOK
	}
	fmt.Printf("diff: %d difference(s) (compared %d Markdown item(s) against %d DB "+
		"item(s); read %s)\n", differences, len(parsed), len(dbItems), read)
	return exitUsage
}
