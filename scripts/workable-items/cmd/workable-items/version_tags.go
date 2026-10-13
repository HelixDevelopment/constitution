// version_tags.go — release-tag column derivation for every workable item.
//
// Feature (operator mandate 2026-05-30): every workable item across Issues.md /
// Issues_Summary.md / Fixed.md / Fixed_Summary.md + their exports + this SQLite
// SSoT MUST carry the release tag(s)/version(s) in which it was OPENED (open
// items — the version when first reported) or FIXED (closed items — the
// version(s) it was closed in; MULTIPLE tags when worked across versions).
//
// This file owns:
//   - the schema migration that adds the `version_tags` column (idempotent),
//   - the `version-tags` subcommand that derives the tags from git history and
//     persists them into the column,
//   - the read helpers the summary generators consume (via `version-tags --emit`).
//
// Derivation algorithm (proven on the real ATMOSphere tree 2026-05-30, §11.4.6):
//
//	OPENED-IN (current_location='Issues' OR open-status closed items):
//	  first-add commit of the item's heading/id in docs/Issues.md
//	    →  git log --diff-filter=A -S'<key>' -- docs/Issues.md  (earliest)
//	    →  git describe --tags --abbrev=0 <commit>  (nearest tag AT/BEFORE open)
//	  When the item predates the first tag, opened_in = "" (pre-first-tag), which
//	  the generators render as "—".
//
//	FIXED-IN (current_location='Fixed'):
//	  every commit that touched the item's id/code in docs/Fixed.md
//	    →  git log -S'<key>' -- docs/Fixed.md
//	    →  for the EARLIEST such commit: git tag --contains <commit> --sort=creatordate
//	  yields the set of release tags that include the closure — MULTIPLE when the
//	  item was worked across several versions (BJ-SOURCE → 4 tags, proven).
//
// The column is DERIVED data (not stored in items.body_md) so the §11.4.93
// byte-identical round-trip is UNAFFECTED — db→md regeneration never emits this
// column into the tracker prose; only the summary generators surface it.
//
// Decoupling (§11.4.28): the git repo root and tracker paths are FLAGS — no
// ATMOSphere path / package / tag-naming is hardcoded. Reusable by any project.
package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
)

// versionTags is the JSON shape persisted in items.version_tags.
type versionTags struct {
	OpenedIn string   `json:"opened_in"`        // nearest tag at/before the item was opened ("" = pre-first-tag)
	FixedIn  []string `json:"fixed_in,omitempty"` // release tags containing the closure (may be multiple)
}

// migrateVersionTagsColumn adds the version_tags column if absent (idempotent),
// and bumps schema_version to >=3. Safe to call on every openDB consumer.
func migrateVersionTagsColumn(db *sql.DB) error {
	has, err := itemsHasVersionTagsColumn(db)
	if err != nil {
		return err
	}
	if !has {
		if _, err := db.Exec(`ALTER TABLE items ADD COLUMN version_tags TEXT`); err != nil {
			return fmt.Errorf("add version_tags column: %w", err)
		}
	}
	// Bump schema_version to 3 (only forward; never downgrade).
	//
	// T048 round-3 review finding R3-I4 (2026-09-30): this used to compare
	// schema_version as TEXT (`ver < "3"`) -- the exact SAME lexicographic-
	// string-comparison bug occurred_at.go's migrateItemHistoryOccurredAt()
	// and db.go's own schema_version bump were independently found+fixed
	// for (T048 round-2 review finding F15): '10' < '3' is lexicographically
	// TRUE, so a DB already at schema_version '10' would silently REGRESS
	// back down to '3' the next time this migration ran. Reproduced live
	// before fixing (adversarial test, seeding schema_version='10'): calling
	// migrateVersionTagsColumn regressed it to '3'; a subsequent openDB()
	// call (which re-runs db.go's own v6 bump) then advanced it to '7' --
	// the exact 10->3->7 round-trip a reviewer mutation demonstrated,
	// reachable in production via the real `workable-items version-tags`
	// subcommand against any DB already migrated past v3. strconv.Atoi
	// forces a genuine numeric comparison, matching this column's real
	// monotonic-integer semantics, consistent with the db.go/occurred_at.go
	// sibling fixes -- an unparseable (non-numeric, non-empty) value is
	// treated the same as "needs bumping" (never silently skipped) rather
	// than crashing this migration on a corrupted meta row.
	var ver string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver)
	verNum, convErr := strconv.Atoi(ver)
	if ver == "" || convErr != nil || verNum < 3 {
		if _, err := db.Exec(`INSERT INTO meta(key,value,last_modified) VALUES('schema_version','3',datetime('now'))
			ON CONFLICT(key) DO UPDATE SET value='3', last_modified=datetime('now')`); err != nil {
			return fmt.Errorf("bump schema_version: %w", err)
		}
	}
	return nil
}

// itemsHasVersionTagsColumn reports whether items.version_tags is present.
// The query is a constant literal (no format string, no external input) so it
// cannot be SQL-injected — the table + column names are compile-time constants.
func itemsHasVersionTagsColumn(db *sql.DB) (bool, error) {
	const q = "PRAGMA table_info(items)"
	rows, err := db.Query(q)
	if err != nil {
		return false, err
	}
	defer rows.Close()
	for rows.Next() {
		var cid int
		var name, ctype string
		var notnull, pk int
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notnull, &dflt, &pk); err != nil {
			return false, err
		}
		if name == "version_tags" {
			return true, nil
		}
	}
	return false, rows.Err()
}

// git runs `git -C <repo> <args...>` and returns trimmed stdout (empty on error).
func git(repo string, args ...string) string {
	full := append([]string{"-C", repo}, args...)
	out, err := exec.Command("git", full...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// deriveOpenedInTag finds the nearest tag at/before the commit that first added
// the item's key to issuesRel (a repo-relative path). Returns "" if pre-first-tag
// or unresolved.
func deriveOpenedInTag(repo, issuesRel, key string) string {
	// EARLIEST adding commit (the `A` diff-filter). `tail -1` equivalent: last line.
	out := git(repo, "log", "--diff-filter=A", "-S"+key, "--format=%H", "--", issuesRel)
	commit := lastLine(out)
	if commit == "" {
		// Fall back to the earliest commit that touched the key at all.
		commit = lastLine(git(repo, "log", "-S"+key, "--format=%H", "--", issuesRel))
	}
	if commit == "" {
		return ""
	}
	return git(repo, "describe", "--tags", "--abbrev=0", commit)
}

// deriveFixedInTags returns the release tags containing the EARLIEST commit that
// introduced the item's key into fixedRel — i.e. the version(s) it was fixed in,
// sorted by tag creation date. Multiple tags = worked across several versions.
func deriveFixedInTags(repo, fixedRel, key string) []string {
	commit := lastLine(git(repo, "log", "-S"+key, "--format=%H", "--", fixedRel))
	if commit == "" {
		return nil
	}
	out := git(repo, "tag", "--contains", commit, "--sort=creatordate")
	if out == "" {
		return nil
	}
	var tags []string
	for _, t := range strings.Split(out, "\n") {
		t = strings.TrimSpace(t)
		if t != "" {
			tags = append(tags, t)
		}
	}
	return tags
}

func lastLine(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	lines := strings.Split(s, "\n")
	return strings.TrimSpace(lines[len(lines)-1])
}

// itemKeyForGit picks the most reliable git -S search key for an item: the raw
// atm_id when it is a real bracket id (ATM-NNN) or a short code; for derived ids
// (ATM-DERIVED-xxxx) the heading title is a better needle than the synthetic id.
func itemKeyForGit(it item) string {
	if strings.HasPrefix(it.AtmID, "ATM-DERIVED-") {
		// Title is more stable in git history than the sha1-derived id.
		if t := strings.TrimSpace(it.Title); t != "" {
			// Use a leading slice to keep the -S needle specific but match-able.
			if len(t) > 48 {
				return t[:48]
			}
			return t
		}
	}
	// Strip the parser's `#N` PK-collision suffix before searching git.
	id := it.AtmID
	if h := strings.IndexByte(id, '#'); h >= 0 {
		id = id[:h]
	}
	return id
}

// versionTagsCmd is the `version-tags` subcommand.
//
//	workable-items version-tags --db <p> --repo <p> [--issues docs/Issues.md] [--fixed docs/Fixed.md]
//	workable-items version-tags --db <p> --emit <atm_id>   (print resolved tags for one item, for generators/tests)
func versionTagsCmd(args []string) int {
	fs := flag.NewFlagSet("version-tags", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	repo := fs.String("repo", ".", "git repository root (for tag derivation)")
	issuesRel := fs.String("issues", "docs/Issues.md", "repo-relative path to Issues tracker")
	fixedRel := fs.String("fixed", "docs/Fixed.md", "repo-relative path to Fixed tracker")
	emit := fs.String("emit", "", "print resolved version_tags JSON for a single atm_id then exit")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "version-tags: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "version-tags: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	if err := migrateVersionTagsColumn(db); err != nil {
		fmt.Fprintf(os.Stderr, "version-tags: migrate: %v\n", err)
		return exitUsage
	}

	if *emit != "" {
		var raw sql.NullString
		_ = db.QueryRow(`SELECT version_tags FROM items WHERE atm_id=? LIMIT 1`, *emit).Scan(&raw)
		if raw.Valid {
			fmt.Println(raw.String)
		} else {
			fmt.Println("{}")
		}
		return exitOK
	}

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "version-tags: %v\n", err)
		return exitUsage
	}

	upd, err := db.Prepare(`UPDATE items SET version_tags=?, last_modified=datetime('now') WHERE atm_id=? AND current_location=?`)
	if err != nil {
		fmt.Fprintf(os.Stderr, "version-tags: prepare: %v\n", err)
		return exitUsage
	}
	defer upd.Close()

	populated := 0
	for _, it := range items {
		key := itemKeyForGit(it)
		vt := versionTags{}
		if it.CurrentLocation == "Fixed" {
			vt.FixedIn = deriveFixedInTags(*repo, *fixedRel, key)
			// Also record where it was opened, for full lifecycle visibility.
			vt.OpenedIn = deriveOpenedInTag(*repo, *issuesRel, key)
		} else {
			vt.OpenedIn = deriveOpenedInTag(*repo, *issuesRel, key)
		}
		// Stable JSON (sorted fixed_in already by creatordate; keep as derived).
		sort.SliceStable(vt.FixedIn, func(i, j int) bool { return false }) // preserve creatordate order
		buf, _ := json.Marshal(vt)
		if _, err := upd.Exec(string(buf), it.AtmID, it.CurrentLocation); err != nil {
			fmt.Fprintf(os.Stderr, "version-tags: update %s: %v\n", it.AtmID, err)
			return exitUsage
		}
		populated++
	}

	fmt.Printf("version-tags: populated %d item(s) in %s\n", populated, *dbPath)
	return exitOK
}

// renderVersionTagCell turns a stored version_tags JSON into the human cell
// the summary generators emit. Issues → opened_in; Fixed → fixed_in (joined).
func renderVersionTagCell(jsonStr, location string) string {
	if jsonStr == "" {
		return "—"
	}
	var vt versionTags
	if err := json.Unmarshal([]byte(jsonStr), &vt); err != nil {
		return "—"
	}
	if location == "Fixed" {
		if len(vt.FixedIn) == 0 {
			return "—"
		}
		return strings.Join(vt.FixedIn, ", ")
	}
	if vt.OpenedIn == "" {
		return "—"
	}
	return vt.OpenedIn
}
