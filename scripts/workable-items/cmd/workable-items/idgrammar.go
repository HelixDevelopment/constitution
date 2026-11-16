// idgrammar.go — the ONE ticket-id grammar of the workable-items engine.
//
// Every place that decides what an item id looks like reads the patterns
// below: the renderer (renderItemBody chooses the heading form), the parser
// (issueHeadingRe, atmShape1*Re, fixedTitleIDRe), the mint path (add, and
// intake-match through add), validate, and the sub-task parent check. Before
// this file each of those carried its own regular expression, and they
// disagreed: the renderer treated `[A-Z]{3,}-…` as canonical while the parser
// read only `[A-Z]{3}-…`, and the renderer wrote any other id in the dot form
// `## <id>. <title>` that the parser reads only for a code with at most one
// `-<alnum>` part. An id in the gap (`CON-PENDING-x2`, `CATS-001`, `con-001`,
// …) was accepted by `add`, rendered by `sync db-to-md`, then dropped by
// `sync md-to-db` (CON-435 review finding; class sweep in the commit message).
//
// The grammar is NOT widened here. The two heading shapes an id can be written
// in are exactly the two the parser already read:
//
//	canonical    <KEY>-<suffix>   KEY = exactly three ASCII uppercase letters,
//	                              suffix = one or more [0-9A-Za-z]
//	                              written `## <id> — <title>`
//	legacy code  [A-Z][A-Za-z0-9]* with at most one `-[A-Za-z0-9]+` part
//	                              (G01, GS-2, BJ-SOURCE) written `## <id>. <title>`
//
// `add` refuses an id that does not round-trip through the renderer and the
// parser (checkIDRoundTrips), so an accepted id can never be dropped by the
// next md-to-db. Placeholder ids with a second hyphen (`CON-PENDING-x2`) are
// refused; the one-hyphen placeholder form (`CON-PENDINGengine`) is canonical
// and accepted.
package main

import (
	"database/sql"
	"fmt"
	"regexp"
	"strings"
)

const (
	// idKeyPattern is the canonical KEY: exactly three ASCII uppercase letters
	// (prefix.go deriveKeyPrefix produces exactly this shape).
	idKeyPattern = `[A-Z]{3}`
	// idSuffixPattern is the canonical suffix after the single hyphen.
	idSuffixPattern = `[0-9A-Za-z]+`
	// canonicalIDPattern is `<KEY>-<suffix>`, e.g. CON-123, HXC-014b.
	canonicalIDPattern = idKeyPattern + `-` + idSuffixPattern
	// legacyCodePattern is the shape-1 letter code read from `## <code>. …`.
	legacyCodePattern = `[A-Z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)?`
	// bracketIDPattern is the `[PREFIX-NNN]` id read from inside a heading
	// (any ≥2-letter uppercase prefix, digits only — §11.4.28 decoupling).
	bracketIDPattern = `[A-Z]{2,}-\d+`
)

// canonicalIDRe matches a whole canonical id. It is the SAME pattern the
// parser's canonical heading (issueHeadingRe) reads, so the renderer never
// writes the em-dash heading for an id the parser would not read back.
var canonicalIDRe = regexp.MustCompile(`^` + canonicalIDPattern + `$`)

// itemIDRe matches a whole id in either renderable shape (canonical or legacy
// code). Used where a stored reference must name a real renderable item id
// (intake-match duplicate-chain following).
var itemIDRe = regexp.MustCompile(`^(?:` + canonicalIDPattern + `|` + legacyCodePattern + `)$`)

// idGrammarHelp is the precise refusal text shared by every refusing seam.
const idGrammarHelp = "an id must be <KEY>-<suffix> with KEY exactly three ASCII uppercase " +
	"letters and suffix one or more of [0-9A-Za-z] (e.g. CON-123, CON-14b, CON-PENDINGengine), " +
	"or a legacy code [A-Z][A-Za-z0-9]* with at most one -[A-Za-z0-9]+ part (e.g. G01, GS-2); " +
	"a second hyphen, a lowercase or non-three-letter key followed by more than one part, " +
	"whitespace, dots, '#', brackets, '§' and non-ASCII characters cannot round-trip through " +
	"the Markdown trackers"

// baseItemID strips the parser's `#N` dedup counter (parseIssues/parseFixed
// append it to a repeated id) so a stored `GS-2#1` compares as `GS-2`.
func baseItemID(id string) string {
	if i := strings.LastIndex(id, "#"); i > 0 {
		tail := id[i+1:]
		if tail != "" && strings.Trim(tail, "0123456789") == "" {
			return id[:i]
		}
	}
	return id
}

// checkIDRoundTrips returns nil iff an item with this id, rendered by
// renderItemBody in either tracker, is read back by the parser as exactly
// this id. The check runs the real renderer and the real parsers, so the
// answer cannot drift from what sync md-to-db actually does.
func checkIDRoundTrips(id string) error {
	if id == "" {
		return fmt.Errorf("empty id; %s", idGrammarHelp)
	}
	const probeTitle = "id grammar probe"
	const probeDesc = "id grammar probe description, long enough for the description floor."
	for _, doc := range []struct {
		name, status string
		parse        func(string) ([]item, []segment)
	}{
		{"Issues", "Queued", parseIssues},
		{"Fixed", "Fixed (→ Fixed.md)", parseFixed},
	} {
		body := renderItemBody(id, probeTitle, "Task", "", probeDesc, doc.status, "", "")
		items, _ := doc.parse(body)
		if len(items) != 1 || items[0].AtmID != id {
			got := "no item"
			if len(items) >= 1 {
				got = fmt.Sprintf("id %q", items[0].AtmID)
			}
			return fmt.Errorf("id %q does not round-trip through %s.md (the heading %q parses to %s); %s",
				id, doc.name, strings.TrimRight(strings.SplitN(body, "\n", 2)[0], "\n"), got, idGrammarHelp)
		}
	}
	return nil
}

// checkStoredBodyRoundTrips returns nil iff a stored section item's own
// body_md is read back by the parser of its tracker as the item's id (modulo
// the `#N` dedup counter). An empty body is not judged here.
func checkStoredBodyRoundTrips(it item) error {
	if strings.TrimSpace(it.BodyMD) == "" || it.repOrDefault() != "section" {
		return nil
	}
	parse := parseIssues
	if it.CurrentLocation == "Fixed" {
		parse = parseFixed
	}
	items, _ := parse(it.BodyMD)
	want := baseItemID(it.AtmID)
	for _, p := range items {
		if baseItemID(p.AtmID) == want {
			return nil
		}
	}
	return fmt.Errorf("%s [%s/section]: stored body heading %q is not read back as this id by the %s.md parser, so the next sync md-to-db would drop the item; %s",
		it.AtmID, it.CurrentLocation, strings.TrimRight(strings.SplitN(it.BodyMD, "\n", 2)[0], "\n"),
		it.CurrentLocation, idGrammarHelp)
}

// droppedButPresentItems lists DB section items of `document` that the new
// parse result no longer contains although their stored heading line is still
// in the Markdown as unrecognised (raw) text. Such an item is not a deletion
// by the operator: the parser cannot read its heading, and replacing the
// document would silently drop it. An item whose heading was removed from the
// Markdown is a real deletion and is not listed.
func droppedButPresentItems(db *sql.DB, document string, parsed []item, segs []segment) ([]string, error) {
	have := map[string]bool{}
	for _, p := range parsed {
		have[baseItemID(p.AtmID)] = true
	}
	rawLines := map[string]bool{}
	for _, s := range segs {
		if s.Kind != "raw" {
			continue
		}
		for _, ln := range splitKeepNewlines(s.Raw) {
			rawLines[strings.TrimRight(ln, "\n")] = true
		}
	}
	rows, err := db.Query(`SELECT atm_id, COALESCE(body_md,'') FROM items
		WHERE current_location = ? AND COALESCE(representation,'section') = 'section'`, document)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id, body string
		if err := rows.Scan(&id, &body); err != nil {
			return nil, err
		}
		if have[baseItemID(id)] || strings.TrimSpace(body) == "" {
			continue
		}
		heading := strings.TrimRight(strings.SplitN(body, "\n", 2)[0], "\n")
		if strings.HasPrefix(heading, "## ") && rawLines[heading] {
			out = append(out, fmt.Sprintf("%s (heading %q)", id, heading))
		}
	}
	return out, rows.Err()
}
