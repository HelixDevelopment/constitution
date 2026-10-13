// mutate.go — the in-place mutating subcommands: update, reopen, block.
//
// §11.4.93: these extend crud.go's add/close with the remaining lifecycle
// transitions the §11.4.74 LVA-3 migration found OWED:
//
//   - update  — change fields (title / severity / description / type / status /
//               created-by / assigned-to) on an existing item; append an
//               item_history 'Updated' row (§11.4.34 audit). Rejects unknown IDs.
//   - reopen  — §11.4.34 reopened-source attribution. Flips status to Reopened
//               and records all four attribution facts (By / On / Reason /
//               Evidence). Rejects partial attribution; --why drawn from the
//               §11.4.34 closed reason vocabulary.
//   - block   — §11.4.21 operator-blocked status. Flips status to
//               Operator-blocked and records operator_block_details. Rejects
//               empty details.
//   - move    — the general REVERSE-OF-CLOSE relocation: moves an item between the
//               Issues and Fixed trackers (row + doc_segment) with an optional new
//               status, WITHOUT the §11.4.34 reopen semantics (no Reopened-Details
//               block, no 'Reopened' history event, so the §11.4.55 reopens_count
//               signal is never inflated by a non-demotion transition). Refuses any
//               destination/status pair that would create an INTEG-03 desync.
//
// All four keep the byte-identical round-trip invariant intact, and all four are
// BODY-PRESERVING: a mutation patches ONLY the slots it actually changes in the
// existing body_md (the `## <ID> — <title>` heading, the `**Status:**` line, its own
// `**…-Details:**` meta line) and leaves every other authored line byte-for-byte.
// Regeneration from renderItemBody is permitted ONLY where there is nothing to
// preserve (an empty body) or where the caller explicitly replaces the freeform
// content (`update --description`). Regenerating unconditionally is the §11.4.93
// truncation defect this file has now been fixed for twice: `update --severity`
// collapsed SPK-481 10 KB → 294 bytes, and `reopen` collapsed ATM-406 3740 → 328
// bytes (91%), each destroying operator-authored forensic anchors, gate definitions
// and cross-references that exist in NO column.
//
// Each operation runs in a single transaction (items row + body_md +
// item_history audit, plus operator_block_details for block) so a crash never
// leaves a half-applied mutation.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

// reopenReasons is the §11.4.34 closed reason vocabulary. reopen's --why MUST be
// one of these (free-text is permitted only by the markdown clause, not the CLI,
// which keeps the audit-log query-able per §11.4.34).
var reopenReasons = map[string]bool{
	"test-failed":                    true,
	"manual-testing-detected":        true,
	"captured-evidence-contradicts":  true,
	"end-user-report":                true,
	"cycle-re-discovered":            true,
	"design-reconsidered":            true,
}

func reopenReasonList() string {
	// Stable, human-readable order for the usage / error message.
	return "test-failed | manual-testing-detected | captured-evidence-contradicts | " +
		"end-user-report | cycle-re-discovered | design-reconsidered"
}

// ---- update ----

// runUpdate implements `update --id <ID> [--title|--severity|--description|
// --type|--status|--created-by|--assigned-to ...] --db <p>`.
func runUpdate(args []string) {
	os.Exit(updateCmd(args))
}

func updateCmd(args []string) int {
	fs := flag.NewFlagSet("update", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "ticket id of the item to update (required)")
	location := fs.String("location", "Issues", "which tracker the item lives in: Issues | Fixed")
	title := fs.String("title", "", "new title (heading text)")
	severity := fs.String("severity", "", "new severity")
	description := fs.String("description", "", "new description (§11.4.91 floor: ≥6 words OR ≥40 chars)")
	typ := fs.String("type", "", "new type: Bug | Feature | Task (§11.4.16)")
	status := fs.String("status", "", "new status (must be a §11.4.15 closed-set value)")
	createdBy := fs.String("created-by", "", "new §11.4.104 created-by handle")
	assignedTo := fs.String("assigned-to", "", "new §11.4.104 assigned-to handle")
	// Track which flags were actually set so we mutate ONLY those fields (an
	// unset --severity must not blank an existing severity).
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	set := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { set[f.Name] = true })

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "update: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*id) == "" {
		fmt.Fprintln(os.Stderr, "update: --id is required")
		return exitUsage
	}
	loc := strings.TrimSpace(*location)
	if loc != "Issues" && loc != "Fixed" {
		fmt.Fprintln(os.Stderr, "update: --location must be Issues or Fixed")
		return exitUsage
	}
	if !set["title"] && !set["severity"] && !set["description"] &&
		!set["type"] && !set["status"] && !set["created-by"] && !set["assigned-to"] {
		fmt.Fprintln(os.Stderr, "update: at least one mutable field flag is required "+
			"(--title / --severity / --description / --type / --status / --created-by / --assigned-to)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "update: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	cur, err := loadItem(db, *id, loc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "update: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "update: item %s not found in %s\n", *id, loc)
		return exitUsage
	}

	// Apply only the explicitly-set fields onto the loaded item.
	if set["title"] {
		if strings.TrimSpace(*title) == "" {
			fmt.Fprintln(os.Stderr, "update: --title cannot be empty")
			return exitUsage
		}
		cur.Title = *title
	}
	if set["severity"] {
		cur.Severity = *severity
	}
	if set["description"] {
		if wordCount(*description) < 6 && len(*description) < 40 {
			fmt.Fprintf(os.Stderr, "update: --description fails §11.4.91 floor (%d words / %d chars; need ≥6 words OR ≥40 chars)\n",
				wordCount(*description), len(*description))
			return exitUsage
		}
		cur.Description = *description
	}
	if set["type"] {
		cur.Type = normalizeType(*typ)
	}
	if set["status"] {
		ns := normalizeStatus(*status)
		// normalizeStatus never returns a non-closed-set value, but guard
		// explicitly so a typo'd --status surfaces rather than silently mapping
		// to Queued. We accept the input only if it normalises to itself OR is a
		// recognised synonym whose intent is unambiguous.
		//
		// §11.4.15 / §11.4.19 / ATM-627 INTEG-03 LOCATION↔STATUS GUARD. Closed-set
		// MEMBERSHIP is necessary but NOT sufficient: a terminal `… (→ Fixed.md)`
		// value is legal in the abstract yet ILLEGAL for a row still located in
		// Issues. `close` performs the §11.4.19 ATOMIC migration (row + doc_segment
		// Issues→Fixed, plus a mandatory captured-evidence artefact); a bare status
		// write here performs NEITHER, stranding a closed item in the OPEN tracker —
		// it does not disappear from the open summary and never appears in the closed
		// one. The predicate is terminalStatuses(), the SAME closed set moveCmd's
		// guard and the fixedLocationNonTerminalStatus / issuesLocationTerminalStatus
		// detective gates (sync.go) use, so preventive and detective halves can never
		// drift apart. Scoped to set["status"] deliberately (§11.4.201(1) — a guard
		// asserts the REAL condition and refuses NOTHING else): a non-status field
		// edit on a row already in the forbidden state must still succeed, or the
		// guard would block the very remediation it exists to prompt.
		if loc == "Issues" && terminalStatuses()[strings.TrimSpace(ns)] {
			fmt.Fprintf(os.Stderr,
				"update: refusing to set terminal status %q on %s while it is located in Issues — "+
					"a terminal status without the migration strands a closed item in the OPEN tracker "+
					"(§11.4.19 requires the closure move to be atomic; §11.4.15/ATM-627 INTEG-03).\n"+
					"  new closure (records captured evidence):  close %s --db <db> --status <fixed|implemented|completed|obsolete> --evidence <path>\n"+
					"  already closed elsewhere (reconcile):     move --id %s --db <db> --to Fixed --why <text>\n",
				ns, *id, *id, *id)
			return exitUsage
		}
		// BOB-175 — the MIRROR half of the same invariant. BOB-166 (the guard
		// above) left this direction OPEN deliberately: `update --location Fixed
		// --status <non-terminal>` still exits 0 and mints a row that validate's
		// own fixedLocationNonTerminalStatus check (f) immediately refuses — the
		// exact §11.4.196(F) shape (configured in validate, unenforced at the
		// seam that can violate it) BOB-166 closed in the OTHER direction only.
		//
		// WHY IT WAS LEFT OPEN, AND WHY CLOSING IT DOES NOT COLLIDE WITH
		// reopenCmd's SANCTIONED --location Fixed OVERRIDE (BOB-166's stated
		// reason for deferring this — the design decision this item exists to
		// make and record, §11.4.6, not to infer from the diff):
		//
		//  1. STRUCTURAL INDEPENDENCE, VERIFIED NOT ASSUMED: reopenCmd (below)
		//     performs its OWN `tx.Exec(...)` write directly against the items
		//     table — it never calls updateCmd, and nothing else in this package
		//     routes through it either (the only two callers of updateCmd are
		//     runUpdate and updateCmd's own tests). A guard added HERE therefore
		//     cannot intercept, alter, or refuse anything reopenCmd does
		//     internally. The "collision" BOB-166 anticipated does not exist at
		//     the code-execution level — it can only be an OPERATOR-FACING
		//     question: should the generic `update` command be ABLE to
		//     independently mint the same Fixed+non-terminal state reopen's
		//     override mints?
		//
		//  2. THE ANSWER IS NO — and for a reason stronger than mere symmetry
		//     with the guard above. reopenCmd's `--location Fixed` override EARNS
		//     its exemption from the ordinary Fixed⇒terminal rule: it forces
		//     status='Reopened', writes a `**Reopened-Details:**` block, and
		//     MANDATES full §11.4.34 attribution (--why from the closed reason
		//     vocabulary, --who AI|User, --when an ISO date, --incident an
		//     evidence path — reopenCmd refuses to proceed without every one of
		//     them). A bare `update --location Fixed --status 'In progress'`
		//     would mint the IDENTICAL desync-flagged state with NONE of that
		//     attribution: an unaudited, unattributed "quiet reopen". Leaving
		//     `update` free to do this is not a neutral omission that happens to
		//     overlap reopen's override — it is a strictly WEAKER, unaudited back
		//     door to the exact same state reopen's override deliberately makes
		//     expensive. Closing it here therefore also closes a §11.4.34
		//     attribution-bypass vector, distinct from (and in addition to) the
		//     bare INTEG-03 location↔status gap.
		//
		//  3. WHY NO OVERRIDE FLAG IS ADDED TO `update` (the item's second listed
		//     candidate design, considered and rejected): a flag on `update`
		//     mirroring `--location Fixed` could never carry reopen's mandatory
		//     --why/--who/--when/--incident payload without update becoming
		//     reopen under a different name — it would just re-open the same
		//     unaudited back door point 2 closes. The refusal below instead
		//     redirects the operator to the mechanisms that already carry that
		//     payload.
		//
		//  4. terminalStatuses() is reused — never a second predicate, so this
		//     direction and the Issues⇒terminal direction above can never drift
		//     apart (the same discipline BOB-166 established). Scoped to
		//     set["status"] for the identical §11.4.201(1) reason as above: a
		//     non-status field edit on a row already in this state (planted
		//     before the guard existed, or by raw SQL) must still succeed, or the
		//     guard would block the very remediation it exists to prompt — see
		//     TestUpdateCmd_AllowsNonStatusFieldEditOnFixedLocatedForbiddenRow.
		//
		// NEGATIVE CONTROL (§11.4.201(1), the sharp one this item calls out):
		// because of point 1, reopenCmd's own existing test suite — in
		// particular TestReopenCmd_LocationFixedOverrideKeepsInFixed — is
		// unmodified and unaffected by this guard; it is re-run verbatim as the
		// closure evidence for this item.
		if loc == "Fixed" && !terminalStatuses()[strings.TrimSpace(ns)] {
			fmt.Fprintf(os.Stderr,
				"update: refusing to set non-terminal status %q on %s while it is located in Fixed — "+
					"a Fixed-location item must carry a terminal `… (→ Fixed.md)` status; writing a "+
					"non-terminal one here mints exactly the state validate's fixedLocationNonTerminalStatus "+
					"check refuses (§11.4.15/§11.4.148/ATM-627 INTEG-03) — and, unlike a plain column write, "+
					"SKIPS the mandatory §11.4.34 reopen attribution (--why/--who/--when/--incident) a real "+
					"reopen requires.\n"+
					"  genuine demotion (records §11.4.34 attribution, relocates to Issues by default):\n"+
					"    reopen --id %s --db <db> --why <reason> --who <AI|User> --when <ISO-date> --incident <path>\n"+
					"  non-demotion relocation (fix landed, runtime GREEN still owed — no reopens_count inflation):\n"+
					"    move --id %s --db <db> --to Issues --status <non-terminal> --why <text>\n"+
					"  keep it in Fixed anyway (the SANCTIONED, deliberately transient override — validate WILL flag it):\n"+
					"    reopen --id %s --db <db> --location Fixed --why <reason> --who <AI|User> --when <ISO-date> --incident <path>\n",
				ns, *id, *id, *id, *id)
			return exitUsage
		}
		// BOB-240 §11.4.33 Type↔Status guard — the update-command analogue of
		// closeCmd's guard (crud.go). Scoped to ns TERMINAL deliberately: by
		// this point EITHER loc=="Issues" && !terminal (survived the guard
		// above unchanged) OR loc=="Fixed" && terminal (survived the BOB-175
		// mirror above) — the only two combinations that can still reach this
		// line, since the two location↔status guards above already refuse the
		// other two cells of the (location, terminality) partition — so
		// terminalStatuses()[ns] is true precisely in the loc=="Fixed" case
		// this check exists to cover, and is a no-op (never fires) in the
		// loc=="Issues" case: the two guard families can never mask or compete
		// with each other for a single call (see
		// TestUpdateCmd_LocationGuardFiresBeforeTypeStatusGuard).
		if terminalStatuses()[strings.TrimSpace(ns)] {
			if wantKeyword, wantStatus, mismatch := typeStatusMismatch(cur.Type, ns); mismatch {
				gotKeyword := closeKeywordForStatus(ns)
				fmt.Fprintf(os.Stderr,
					"update: refusing — %s has Type=%s, whose §11.4.33 closure vocabulary is %q (--status %s), not %q (--status %s); Obsolete is valid for any Type.\n"+
						"  correct command:  update --id %s --db <db> --location %s --status %s\n",
					*id, cur.Type, wantStatus, wantKeyword, ns, gotKeyword,
					*id, loc, wantKeyword)
				return exitUsage
			}
		}
		cur.Status = ns
	}
	if set["created-by"] {
		cur.CreatedBy = strings.TrimSpace(*createdBy)
	}
	if set["assigned-to"] {
		cur.AssignedTo = strings.TrimSpace(*assignedTo)
	}

	// §11.4.93 data-integrity: a field-only update MUST mutate only the specified
	// column(s) and PRESERVE the authored body_md. A real md→db-synced item carries
	// multi-KB of operator-authored freeform content; regenerating it from
	// renderItemBody's minimal template collapses it to ~250 bytes — the truncation
	// defect this fixes (forensic anchor: SPK-481 10 KB → 294 bytes on `update
	// --severity`). Regeneration is permitted ONLY when --description explicitly
	// replaces the freeform content.
	//
	// For a field-only update we start from the existing body and surgically sync
	// only the two slots the tool treats as column-authoritative:
	//   - the `## <ID> — <title>` heading, when --title changes (the item's rendered
	//     display identity; renderDocument emits it from body_md, not the column);
	//   - the `**Status:**` line, when --status changes (the sole column↔body
	//     invariant enforced by statusColumnBodyDesyncs). canonicalizeBodyStatusLine
	//     is a STRICT no-op when status is unchanged, so a non-status field-only
	//     update (e.g. --severity) leaves body_md byte-identical (diff stays 0).
	// Every other line — the entire authored freeform body plus the
	// severity/type/attribution meta lines — is preserved verbatim.
	//
	// F-DBTOOL-2 fix (2026-07-12): renderItemBody unconditionally emits the H2
	// "## <ID> — <title>" section shape. For a 'table'-representation item (a
	// legacy Fixed.md pipe-table closure row — parseFixed's emitLegacyTable,
	// parse.go) that shape is WRONG: it replaces the single "| date | title |
	// type | status | round | commit(s) | evidence |" row line with a multi-line
	// H2 block, which (a) issueHeadingRe / isATMCandidateHeading (parse.go) never
	// recognise as ANY heading shape for a synthetic "FIX-<date>#<n>" id
	// (multiple dashes + "#" fail every pattern), so the item is swallowed into
	// raw prose on the next db-to-md + re-parse round-trip, and (b) because
	// emitLegacyTable derives an un-ID'd row's atm_id POSITIONALLY — the Nth
	// same-dated row encountered during the scan, not a stable identifier — every
	// later same-dated row's re-derived id silently shifts down by one, cascading
	// dozens of spurious "body differs" / "absent in Markdown" / status-type
	// mismatches (docs/research/f_dbtool2_20260712/ROOTCAUSE.md; reproduced by
	// a SINGLE `update --description` on one table-representation item). A
	// pipe-table row has no dedicated description cell to update (Description is
	// DERIVED from Title+Evidence at parse time, deriveDescription), so the safe,
	// minimal fix is: update the `items.description` COLUMN (already applied
	// above) but do NOT regenerate body_md for a table-representation item —
	// preserve the verbatim pipe-row text via the same field-only path used for
	// --severity/--status, which is a proven no-op-safe path for this shape
	// (replaceHeadingTitle/canonicalizeBodyStatusLine both require "## "/"**" -
	// prefixed lines that a pipe-row never contains, so they leave it unchanged).
	var newBody string
	if set["description"] && cur.repOrDefault() != "table" {
		newBody = renderItemBody(cur.AtmID, cur.Title, cur.Type, cur.Severity, cur.Description, cur.Status, cur.CreatedBy, cur.AssignedTo)
	} else {
		newBody = cur.BodyMD
		if set["title"] {
			newBody = replaceHeadingTitle(newBody, cur.AtmID, cur.Title)
		}
		newBody = canonicalizeBodyStatusLine(newBody, cur.Status)
	}
	// ATM-627-part-2 STORE-side normalization (defense-in-depth). A field-only
	// update PROPAGATES the existing cur.BodyMD verbatim; a pre-existing body that
	// ended with NO "\n" (the live 9-item residual) would be re-stored no-"\n"
	// otherwise, keeping the byte-identical round-trip broken. ensureTrailingNewline
	// is a strict no-op on an already-"\n"-terminated body (the normal "\n\n"
	// convention), so it preserves the "diff stays 0 for a non-status field-only
	// update" invariant while self-healing a no-"\n" body.
	newBody = ensureTrailingNewline(newBody)

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "update: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	// F-DBTOOL fix (2026-07-12): scope by representation — cur came from
	// loadItem's now-deterministic (atm_id, location) read; without this the
	// WHERE clause matches EVERY representation row sharing (atm_id, location)
	// (GAP A dual-representation items, e.g. HXC-044's 'section'+'table' pair)
	// and clobbers the sibling representation's body_md with cur's content.
	// See docs/research/f_dbtool_20260712/ROOTCAUSE.md.
	if _, err := tx.Exec(`UPDATE items SET
		type=?, status=?, severity=?, title=?, description=?,
		created_by=?, assigned_to=?, body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND representation=?`,
		cur.Type, cur.Status, nullable(cur.Severity), cur.Title, cur.Description,
		cur.CreatedBy, cur.AssignedTo, newBody, *id, loc, cur.repOrDefault()); err != nil {
		fmt.Fprintf(os.Stderr, "update: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, *id, "Updated", "AI", "", ""); err != nil {
		fmt.Fprintf(os.Stderr, "update: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "update: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("update: %s updated in %s (status=%s, type=%s)\n", *id, loc, cur.Status, cur.Type)
	return exitOK
}

// ---- reopen ----

// runReopen implements `reopen --id <ID> --why <reason> --who <AI|User>
// --when <ISO> --incident <path> --db <p>` per §11.4.34.
func runReopen(args []string) {
	os.Exit(reopenCmd(args))
}

func reopenCmd(args []string) int {
	fs := flag.NewFlagSet("reopen", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "ticket id of the item to reopen (required)")
	location := fs.String("location", "Issues", "destination tracker for the reopened item: Issues (default; non-terminal Reopened belongs in Issues) | Fixed (operator override, keep in Fixed)")
	why := fs.String("why", "", "§11.4.34 reason (closed-set): "+reopenReasonList())
	who := fs.String("who", "", "§11.4.34 By: AI | User")
	when := fs.String("when", "", "§11.4.34 On: ISO date (YYYY-MM-DD)")
	incident := fs.String("incident", "", "§11.4.34 Evidence: path to captured artefact")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "reopen: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*id) == "" {
		fmt.Fprintln(os.Stderr, "reopen: --id is required")
		return exitUsage
	}
	// §11.4.34 / ATM-627 INTEG-03: --location is the DESTINATION tracker for the
	// reopened item. Reopened is a NON-terminal status, so the default destination is
	// Issues — a reopened item BELONGS in Issues (a Fixed-location item carrying a
	// non-terminal status is the location↔status desync validateCmd now catches). The
	// item's CURRENT location is auto-detected below, so `reopen` finds a Fixed item
	// too; `--location Fixed` is a deliberate operator override that keeps it in Fixed.
	if wantLoc := strings.TrimSpace(*location); wantLoc != "Issues" && wantLoc != "Fixed" {
		fmt.Fprintln(os.Stderr, "reopen: --location must be Issues or Fixed")
		return exitUsage
	}
	// §11.4.34: all four attribution facts are mandatory. A reopen IS a
	// demotion-from-Fixed (§11.4.7) — partial attribution is a bluff.
	if strings.TrimSpace(*why) == "" {
		fmt.Fprintf(os.Stderr, "reopen: --why is required (§11.4.34 closed-set): %s\n", reopenReasonList())
		return exitUsage
	}
	if !reopenReasons[strings.TrimSpace(*why)] {
		fmt.Fprintf(os.Stderr, "reopen: --why %q not in §11.4.34 closed-set: %s\n", *why, reopenReasonList())
		return exitUsage
	}
	byVal := strings.TrimSpace(*who)
	if byVal != "AI" && byVal != "User" {
		fmt.Fprintln(os.Stderr, "reopen: --who is required and must be AI or User (§11.4.34 By)")
		return exitUsage
	}
	if strings.TrimSpace(*when) == "" {
		fmt.Fprintln(os.Stderr, "reopen: --when is required (§11.4.34 On: ISO date YYYY-MM-DD)")
		return exitUsage
	}
	if strings.TrimSpace(*incident) == "" {
		fmt.Fprintln(os.Stderr, "reopen: --incident is required (§11.4.34 Evidence; a reopen without evidence is a §11.4.7 demotion-without-evidence bluff)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "reopen: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	// Auto-detect the item's CURRENT location (Issues first, then Fixed) so reopen
	// works regardless of where the item lives — the pre-fix reopen searched ONLY the
	// --location value (default Issues) and therefore could not even find a Fixed item
	// to reopen (ATM-627 INTEG-03).
	srcLoc := "Issues"
	cur, err := loadItem(db, *id, srcLoc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "reopen: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		srcLoc = "Fixed"
		cur, err = loadItem(db, *id, srcLoc)
		if err != nil {
			fmt.Fprintf(os.Stderr, "reopen: %v\n", err)
			return exitUsage
		}
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "reopen: item %s not found in Issues or Fixed\n", *id)
		return exitUsage
	}

	// Destination: default Issues (non-terminal Reopened belongs in Issues); an
	// explicit --location Fixed keeps it in Fixed (operator override). This single
	// line is the §1.1 mutation seam — forcing `dest := srcLoc` reverts the INTEG-03
	// migration so reopen strands a Fixed item in Fixed again.
	dest := strings.TrimSpace(*location)

	cur.Status = "Reopened"
	newBody := reopenedBody(cur, byVal, *when, *why, *incident)

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "reopen: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	// Relocate the row to the destination in place: an UPDATE that flips
	// current_location is LOSSLESS (it preserves forensic_anchor / closure_criteria /
	// composes_with / parent_atm_id / session_ref / version_tags — columns a
	// delete+insert would drop). The (atm_id, current_location, representation) PK
	// admits the flip because the item lives in exactly one location.
	//
	// F-DBTOOL fix (2026-07-12): scope by representation (cur.repOrDefault(),
	// now populated correctly by loadItem) so a dual-representation item's
	// sibling row is never relocated/clobbered alongside the one actually
	// reopened. See docs/research/f_dbtool_20260712/ROOTCAUSE.md.
	if _, err := tx.Exec(`UPDATE items SET status='Reopened', current_location=?, body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND representation=?`, dest, newBody, *id, srcLoc, cur.repOrDefault()); err != nil {
		fmt.Fprintf(os.Stderr, "reopen: %v\n", err)
		return exitUsage
	}
	// Move the doc_segment with the row when the location changes — mirrors close's
	// atomic Issues→Fixed segment move, reversed. Without this the regenerated
	// Markdown would still carry the item under its OLD document (the ATM-627
	// dangling-segment class validateCmd's renderability guard flags).
	if dest != srcLoc {
		if err := removeItemSegment(tx, srcLoc, *id); err != nil {
			fmt.Fprintf(os.Stderr, "reopen: remove %s segment: %v\n", srcLoc, err)
			return exitUsage
		}
		if err := appendSegment(tx, dest, *id); err != nil {
			fmt.Fprintf(os.Stderr, "reopen: append %s segment: %v\n", dest, err)
			return exitUsage
		}
	}
	// §11.4.34 audit: by + on_date + reason + evidence_path all captured.
	if _, err := tx.Exec(`INSERT INTO item_history
		(atm_id, event_type, by, on_date, reason, evidence_path)
		VALUES (?,?,?,?,?,?)`,
		*id, "Reopened", byVal, *when, *why, *incident); err != nil {
		fmt.Fprintf(os.Stderr, "reopen: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "reopen: commit: %v\n", err)
		return exitUsage
	}

	if dest != srcLoc {
		fmt.Printf("reopen: %s reopened, relocated %s→%s (By:%s On:%s Reason:%s Evidence:%s)\n", *id, srcLoc, dest, byVal, *when, *why, *incident)
	} else {
		fmt.Printf("reopen: %s reopened in %s (By:%s On:%s Reason:%s Evidence:%s)\n", *id, dest, byVal, *when, *why, *incident)
	}
	return exitOK
}

// reopenedBody produces the body_md for a Reopened item, PRESERVING the authored
// freeform content.
//
// §11.4.93 data-integrity — the reopen half of the body-preservation contract that
// `update` already carries (see updateCmd's field-only path above). Forensic anchor
// (FACT, measured on a throwaway copy of the live DB, 2026-07-20): `reopen --id
// ATM-406` collapsed that item's authored body_md 3740 → 328 bytes (91% destroyed),
// losing the verbatim user-mandate forensic anchor, the Phase 39.P source-fix
// description, the `CM-P-PRIMARY-INTERACTIVE` 5-invariant gate + its paired mutation,
// and every cross-reference. Root cause: the pre-fix renderReopenedBody regenerated
// the body from COLUMNS via renderItemBody — a minimal template — rather than patching
// the existing body, so every line the columns do not carry was destroyed. `update`
// received the preservation fix (SPK-481, 10 KB → 294 bytes); `reopen` never did.
//
// A reopen changes exactly TWO things a body must reflect, so exactly two slots are
// patched and every other line is preserved byte-for-byte:
//   - the `**Status:**` line → "Reopened" (canonicalizeBodyStatusLine is a SURGICAL
//     single-line rewrite and a STRICT no-op when the line already reads Reopened);
//   - the §11.4.34 `**Reopened-Details:**` meta line → UPSERTed (replaced in place when
//     the item was reopened before, so re-reopening never stacks duplicate detail
//     lines; inserted into the heading-adjacent meta block otherwise).
//
// Two shapes are handled explicitly rather than by regeneration:
//   - representation == "table" (a legacy Fixed.md pipe-table closure row, parseFixed's
//     emitLegacyTable): a pipe row has NO meta block, so injecting a `**Reopened-
//     Details:**` line would corrupt the table and emitting an H2 block would make the
//     row unparseable on the next round-trip (the F-DBTOOL-2 defect class updateCmd
//     documents). The row is preserved verbatim; the four §11.4.34 attribution facts
//     are still captured in full by the item_history row reopenCmd writes, which is the
//     query-able audit surface §11.4.34 mandates.
//   - an EMPTY body: the ONLY case where regeneration is correct (there is nothing to
//     preserve, and canonicalizeBodyStatusLine is a documented no-op on an empty body,
//     so patching alone would leave the item body-less). Mirrors the empty-body class
//     owned by repair-bodies / renderItemBody.
func reopenedBody(it *item, by, when, why, incident string) string {
	detail := fmt.Sprintf("**Reopened-Details:** By: %s On: %s Reason: %s Evidence: %s", by, when, why, incident)

	if it.repOrDefault() == "table" {
		return ensureTrailingNewline(it.BodyMD)
	}
	if strings.TrimSpace(it.BodyMD) == "" {
		body := renderItemBody(it.AtmID, it.Title, it.Type, it.Severity, it.Description, "Reopened", it.CreatedBy, it.AssignedTo)
		return ensureTrailingNewline(insertMetaLine(body, detail))
	}
	body := canonicalizeBodyStatusLine(it.BodyMD, "Reopened")
	body = upsertMetaLine(body, "**Reopened-Details:**", detail)
	return ensureTrailingNewline(body)
}

// upsertMetaLine REPLACES the first `**Key:** …` metadata line whose prefix matches
// key, preserving that line's original newline; when no such line exists it delegates
// to insertMetaLine (insert into the heading-adjacent meta block). Every other line is
// preserved byte-for-byte.
//
// Why replace rather than always insert: a second reopen of an already-reopened item
// would otherwise stack a duplicate `**Reopened-Details:**` line on every cycle, and
// the §11.4.34 walk-pattern gates read the detail line adjacent to the heading — two
// contradictory detail lines is a §11.4.6 ambiguity, not an audit trail (the audit
// trail is the append-only item_history table, which correctly keeps EVERY reopen).
func upsertMetaLine(body, key, metaLine string) string {
	lines := splitKeepNewlines(body)
	for i, ln := range lines {
		if strings.HasPrefix(strings.TrimRight(ln, "\n"), key) {
			nl := ""
			if strings.HasSuffix(ln, "\n") {
				nl = "\n"
			}
			// F1 (§11.4.34 / §11.4.6): when the matched line is the
			// `**Reopened-Details:**` header, a PRIOR reopen may have written its
			// attribution as a MULTI-LINE bulleted block (the ATM-393/398/448 live
			// shape) whose `- **(By|On|Reason|Evidence):**` bullets do NOT start with
			// the header key. Replacing only the header would leave those bullets
			// ORPHANED — a contradictory dual attribution, the exact ambiguity this
			// upsert exists to prevent. So ALSO consume the CONTIGUOUS run of
			// attribution bullets IMMEDIATELY following the matched header, so a
			// single canonical inline attribution survives. Only the immediately-
			// following contiguous run is consumed: a blank line or any
			// non-`- **(By|On|Reason|Evidence):**` line ends the run, so a body-
			// content bullet elsewhere is never touched (§11.4.201(7)(a)
			// carrier-vs-thing). Scoped to the Reopened-Details header so no other
			// upsert path is affected.
			end := i + 1
			if key == "**Reopened-Details:**" {
				for end < len(lines) && isReopenedDetailBullet(lines[end]) {
					end++
				}
			}
			out := make([]string, 0, len(lines)-(end-i-1))
			out = append(out, lines[:i]...)
			out = append(out, metaLine+nl)
			out = append(out, lines[end:]...)
			return strings.Join(out, "")
		}
	}
	return insertMetaLine(body, metaLine)
}

// isReopenedDetailBullet reports whether a body line is one of the four §11.4.34
// `**Reopened-Details:**` attribution bullets (`- **By:**` / `- **On:**` /
// `- **Reason:**` / `- **Evidence:**`) that the pre-1.2.1 MULTI-LINE reopen shape
// emitted (the ATM-393/398/448 live shape). upsertMetaLine uses it to consume the
// contiguous bullet run a prior multi-line reopen left behind. Matches the exact
// canonical bullet prefix only — no leading-whitespace tolerance — so an indented
// or differently-shaped body bullet is never mistaken for one
// (§11.4.201(7)(a) match-structure-not-substring).
func isReopenedDetailBullet(line string) bool {
	s := strings.TrimRight(line, "\n")
	for _, f := range []string{"By", "On", "Reason", "Evidence"} {
		if strings.HasPrefix(s, "- **"+f+":**") {
			return true
		}
	}
	return false
}

// ---- move ----

// runMove implements `move --id <ID> --to <Issues|Fixed> [--status <S>]
// --why <text> [--evidence <p>] --db <p>`.
func runMove(args []string) {
	os.Exit(moveCmd(args))
}

// moveCmd is the general REVERSE-OF-CLOSE relocation: it moves an item between the
// Issues and Fixed trackers (row + doc_segment) and optionally sets a new §11.4.15
// status, LOSSLESSLY — the authored body_md is preserved byte-for-byte apart from the
// surgical `**Status:**` line sync.
//
// WHY THIS EXISTS (and is NOT `reopen --status`): `reopen` is the §11.4.34 mechanism
// and carries §11.4.34 semantics — it forces status='Reopened', writes a
// `**Reopened-Details:**` attribution block into the body, and mints a `Reopened`
// item_history event. §11.4.34's `Reopened` presupposes a closure to demote FROM
// (§11.4.7), and the reopen event feeds the §11.4.55 reopens_count that §11.4.132(d)
// + §11.4.189 use to rank the most-fragile work for the deepest live scrutiny.
// Routing a NON-demotion transition through `reopen` would therefore (a) assert a
// defect in a fix that has none and (b) INFLATE the reopens_count, corrupting exactly
// the prioritisation signal §11.4.214 exists to keep true. The canonical case: a fix
// that has landed and is wired but whose runtime GREEN is still owed (§11.4.69
// `artifact_not_yet_built`) belongs at `Ready for testing` in Issues — a relocation,
// not a reopen.
//
// LOCATION↔STATUS INVARIANT (§11.4.15 / ATM-627 INTEG-03, enforced not assumed): a
// terminal `… (→ Fixed.md)` status belongs at Fixed and a non-terminal status belongs
// at Issues. move REFUSES a combination that would CREATE the very INTEG-03 desync
// validate catches, so this command can never be the source of the defect class it
// exists to repair. The predicate is terminalStatuses() — the same closed set
// fixedLocationNonTerminalStatus (sync.go) checks against, so the guard and the
// detective gate can never drift apart.
func moveCmd(args []string) int {
	fs := flag.NewFlagSet("move", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "ticket id of the item to move (required)")
	to := fs.String("to", "", "destination tracker: Issues | Fixed (required)")
	status := fs.String("status", "", "new §11.4.15 status to set during the move (optional; must satisfy the location↔status invariant)")
	why := fs.String("why", "", "reason for the move, recorded in the item_history audit row (required)")
	evidence := fs.String("evidence", "", "captured-evidence path for the audit row (§11.4.5)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	set := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { set[f.Name] = true })

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "move: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*id) == "" {
		fmt.Fprintln(os.Stderr, "move: --id is required")
		return exitUsage
	}
	dest := strings.TrimSpace(*to)
	if dest != "Issues" && dest != "Fixed" {
		fmt.Fprintln(os.Stderr, "move: --to is required and must be Issues or Fixed")
		return exitUsage
	}
	// The audit row is the whole point of routing a relocation through the tool
	// rather than a raw UPDATE; an unexplained relocation is a §11.4.6 gap.
	if strings.TrimSpace(*why) == "" {
		fmt.Fprintln(os.Stderr, "move: --why is required (recorded in the item_history audit row)")
		return exitUsage
	}
	// HXC-224 record-time closure-evidence guard. --evidence stays OPTIONAL on
	// this command (checkEvidencePath is a no-op on an empty value) — but a
	// SUPPLIED path must resolve, because `move --to Fixed --status <terminal>`
	// relocates an item INTO the closed set, making its audit row exactly the
	// kind of closure-evidence row the HXC-217 validator scopes to.
	if !requireEvidencePath("move", *evidence) {
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "move: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	// Auto-detect the item's CURRENT location (Issues first, then Fixed), mirroring
	// reopen — the caller states the DESTINATION, never has to know the source.
	srcLoc := "Issues"
	cur, err := loadItem(db, *id, srcLoc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "move: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		srcLoc = "Fixed"
		cur, err = loadItem(db, *id, srcLoc)
		if err != nil {
			fmt.Fprintf(os.Stderr, "move: %v\n", err)
			return exitUsage
		}
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "move: item %s not found in Issues or Fixed\n", *id)
		return exitUsage
	}

	newStatus := cur.Status
	if set["status"] {
		newStatus = normalizeStatus(*status)
	}
	// §11.4.15 / INTEG-03 guard — refuse to create the desync, naming the real
	// resolved values so the refusal is actionable (§11.4.201(5)).
	terminal := terminalStatuses()
	if dest == "Fixed" && !terminal[strings.TrimSpace(newStatus)] {
		fmt.Fprintf(os.Stderr, "move: refusing — status %q is NON-terminal and cannot live at Fixed "+
			"(§11.4.15/ATM-627 INTEG-03: a Fixed-location item must carry a terminal `… (→ Fixed.md)` status)\n", newStatus)
		return exitUsage
	}
	if dest == "Issues" && terminal[strings.TrimSpace(newStatus)] {
		fmt.Fprintf(os.Stderr, "move: refusing — status %q is TERMINAL and belongs at Fixed, not Issues "+
			"(§11.4.15; pass --status with a non-terminal value to move it back to Issues)\n", newStatus)
		return exitUsage
	}

	// Lossless body: preserve the authored content, syncing ONLY the `**Status:**`
	// line when the status actually changed (canonicalizeBodyStatusLine is a STRICT
	// no-op otherwise, so a pure relocation leaves body_md byte-identical).
	newBody := ensureTrailingNewline(canonicalizeBodyStatusLine(cur.BodyMD, newStatus))

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "move: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	// Relocate in place (an UPDATE, never delete+insert) so every column a
	// delete+insert would drop — forensic_anchor / closure_criteria / composes_with /
	// version_tags / assignment — survives. Scoped by representation so a
	// dual-representation item's sibling row is never clobbered (F-DBTOOL).
	if _, err := tx.Exec(`UPDATE items SET status=?, current_location=?, body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND representation=?`,
		newStatus, dest, newBody, *id, srcLoc, cur.repOrDefault()); err != nil {
		fmt.Fprintf(os.Stderr, "move: %v\n", err)
		return exitUsage
	}
	// The doc_segment moves with the row — otherwise `sync db-to-md` would still
	// render the item under its OLD document (the ATM-627 dangling-segment class).
	if dest != srcLoc {
		if err := removeItemSegment(tx, srcLoc, *id); err != nil {
			fmt.Fprintf(os.Stderr, "move: remove %s segment: %v\n", srcLoc, err)
			return exitUsage
		}
		if err := appendSegment(tx, dest, *id); err != nil {
			fmt.Fprintf(os.Stderr, "move: append %s segment: %v\n", dest, err)
			return exitUsage
		}
	}
	// 'Updated' is the correct event_type: the schema's item_history CHECK is a
	// CLOSED set ('Opened','Updated','Reopened','Fixed','Implemented','Completed',
	// 'Obsolete') and a relocation is deliberately NOT a 'Reopened' event (see the
	// §11.4.55 reopens_count rationale above). Adding a 'Moved' member would be a
	// live-schema migration whose blast radius exceeds this fix.
	if err := recordHistory(tx, *id, "Updated", "AI", *why, strings.TrimSpace(*evidence)); err != nil {
		fmt.Fprintf(os.Stderr, "move: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "move: commit: %v\n", err)
		return exitUsage
	}

	if dest != srcLoc {
		fmt.Printf("move: %s relocated %s→%s (status=%s, reason=%s)\n", *id, srcLoc, dest, newStatus, *why)
	} else {
		fmt.Printf("move: %s stays in %s (status=%s, reason=%s)\n", *id, dest, newStatus, *why)
	}
	return exitOK
}

// ---- block ----

// runBlock implements `block --id <ID> --details <text> --db <p>` per §11.4.21.
func runBlock(args []string) {
	os.Exit(blockCmd(args))
}

func blockCmd(args []string) int {
	fs := flag.NewFlagSet("block", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "ticket id of the item to block (required)")
	location := fs.String("location", "Issues", "which tracker the item lives in: Issues | Fixed")
	details := fs.String("details", "", "§11.4.21 WHAT (concrete blocked action; required, non-empty)")
	why := fs.String("why", "", "§11.4.21 WHY (each exhausted self-resolution alternative)")
	unblock := fs.String("unblock", "", "§11.4.21 UNBLOCK CONDITION (observable signal)")
	who := fs.String("who", "", "§11.4.21 WHO (handle / contact / doc pointer)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "block: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*id) == "" {
		fmt.Fprintln(os.Stderr, "block: --id is required")
		return exitUsage
	}
	loc := strings.TrimSpace(*location)
	if loc != "Issues" && loc != "Fixed" {
		fmt.Fprintln(os.Stderr, "block: --location must be Issues or Fixed")
		return exitUsage
	}
	// §11.4.21: Operator-blocked is a last-resort classification. The WHAT
	// (--details) is mandatory and non-empty; a bare Operator-blocked with no
	// details is a §11.4 covenant violation at the planning layer.
	if strings.TrimSpace(*details) == "" {
		fmt.Fprintln(os.Stderr, "block: --details is required and must be non-empty (§11.4.21 WHAT)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "block: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	cur, err := loadItem(db, *id, loc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "block: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "block: item %s not found in %s\n", *id, loc)
		return exitUsage
	}

	cur.Status = "Operator-blocked"
	newBody := renderBlockedBody(cur, *details, *why, *unblock, *who)

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "block: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	// F-DBTOOL fix (2026-07-12): scope by representation, mirroring update/
	// reopen — see docs/research/f_dbtool_20260712/ROOTCAUSE.md.
	if _, err := tx.Exec(`UPDATE items SET status='Operator-blocked', body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND representation=?`, newBody, *id, loc, cur.repOrDefault()); err != nil {
		fmt.Fprintf(os.Stderr, "block: %v\n", err)
		return exitUsage
	}
	// §11.4.21 operator_block_details: WHAT / WHY / UNBLOCK / WHO. The schema
	// requires what + why_exhausted_alternatives + unblock_condition NOT NULL;
	// supply a stable placeholder for the optional fields when the operator does
	// not pass them (the CLI guarantees WHAT is non-empty above).
	whyVal := strings.TrimSpace(*why)
	if whyVal == "" {
		whyVal = "(not enumerated)"
	}
	unblockVal := strings.TrimSpace(*unblock)
	if unblockVal == "" {
		unblockVal = "(not specified)"
	}
	if _, err := tx.Exec(`INSERT OR REPLACE INTO operator_block_details
		(atm_id, what, why_exhausted_alternatives, unblock_condition, who)
		VALUES (?,?,?,?,?)`,
		*id, strings.TrimSpace(*details), whyVal, unblockVal, nullable(strings.TrimSpace(*who))); err != nil {
		fmt.Fprintf(os.Stderr, "block: operator_block_details: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, *id, "Updated", "AI", "operator-blocked", strings.TrimSpace(*details)); err != nil {
		fmt.Fprintf(os.Stderr, "block: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "block: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("block: %s set Operator-blocked in %s (WHAT:%s)\n", *id, loc, strings.TrimSpace(*details))
	return exitOK
}

// renderBlockedBody regenerates the item body for an Operator-blocked item,
// embedding the §11.4.21 `**Operator-Block-Details:**` line in the heading-
// adjacent meta block.
func renderBlockedBody(it *item, what, why, unblock, who string) string {
	body := renderItemBody(it.AtmID, it.Title, it.Type, it.Severity, it.Description, "Operator-blocked", it.CreatedBy, it.AssignedTo)
	var b strings.Builder
	fmt.Fprintf(&b, "**Operator-Block-Details:** WHAT: %s", what)
	if strings.TrimSpace(why) != "" {
		fmt.Fprintf(&b, " WHY: %s", why)
	}
	if strings.TrimSpace(unblock) != "" {
		fmt.Fprintf(&b, " UNBLOCK: %s", unblock)
	}
	if strings.TrimSpace(who) != "" {
		fmt.Fprintf(&b, " WHO: %s", who)
	}
	return insertMetaLine(body, b.String())
}

// replaceHeadingTitle surgically rewrites the title portion of an item body's
// canonical `## <ID> — <title>` heading line to newTitle, preserving every other
// line byte-for-byte (the heading-analogue of canonicalizeBodyStatusLine). It
// rewrites the FIRST line whose prefix is `## <id> — `; when no such canonical
// heading is present (a rich body may use a non-canonical heading form) the body
// is returned UNCHANGED — the title column still updates, and no authored content
// is ever disturbed. This keeps a field-only --title update's heading in sync with
// the column without regenerating (and thus truncating) the authored body.
func replaceHeadingTitle(body, id, newTitle string) string {
	prefix := "## " + id + " — "
	lines := splitKeepNewlines(body)
	for i, ln := range lines {
		if strings.HasPrefix(strings.TrimRight(ln, "\n"), prefix) {
			nl := ""
			if strings.HasSuffix(ln, "\n") {
				nl = "\n"
			}
			lines[i] = prefix + newTitle + nl
			return strings.Join(lines, "")
		}
	}
	return body
}

// insertMetaLine inserts a `**Key:** …` metadata line into a rendered item body
// immediately after the `**Type:**` line (mirroring appendEvidence), so the
// regenerated Markdown keeps the detail line within the heading-adjacent meta
// block where the §11.4.21 / §11.4.34 walk-pattern gates look for it.
func insertMetaLine(body, metaLine string) string {
	lines := strings.SplitAfter(body, "\n")
	var out strings.Builder
	inserted := false
	for _, ln := range lines {
		out.WriteString(ln)
		if !inserted && strings.HasPrefix(ln, "**Type:**") {
			out.WriteString(metaLine)
			out.WriteString("\n")
			inserted = true
		}
	}
	if !inserted {
		out.WriteString(metaLine)
		out.WriteString("\n")
	}
	return out.String()
}

// hasEnumeratedUnblockChoices reports whether an unblock_condition string
// enumerates the §11.4.148 D3 closed list of decisions/actions that would
// unblock an Operator-blocked item — `[A]…·[B]…`, `[1]…·[2]…`, or a
// dash/asterisk bullet list. Bare prose (a single un-enumerated sentence) and
// empty/whitespace input are rejected: a BLOCKED item with no enumerated unblock
// CHOICES is a §11.4.148 D3 PASS-bluff (the operator has no enumerated way to
// clear the block). Deterministic, no regexp — scans for the marker shapes.
func hasEnumeratedUnblockChoices(s string) bool {
	if strings.TrimSpace(s) == "" {
		return false
	}
	// (1) Bracketed choice markers `[A]` / `[a]` / `[1]` anywhere in the text.
	for i := 0; i+2 < len(s); i++ {
		if s[i] != '[' || s[i+2] != ']' {
			continue
		}
		c := s[i+1]
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			return true
		}
	}
	// (2) Bullet-list markers: a line beginning (after optional leading
	//     whitespace) with "- " or "* ". Require ≥2 bullets so a single dashed
	//     prose line is not mistaken for an enumeration.
	bullets := 0
	for _, ln := range strings.Split(s, "\n") {
		t := strings.TrimLeft(ln, " \t")
		if strings.HasPrefix(t, "- ") || strings.HasPrefix(t, "* ") {
			bullets++
		}
	}
	return bullets >= 2
}
