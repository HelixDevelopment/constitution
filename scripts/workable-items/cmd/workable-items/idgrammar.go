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

// ---------------------------------------------------------------------------
// Whole-item round trip (CON-456 round 2).
//
// checkIDRoundTrips above judges an id alone, with a fixed probe title, so it
// could not see the rest of the class "what the engine stores is not what
// sync md-to-db reads back": a legacy-code item whose title carries a
// `[XX-N]` bracket id parses as that other id (review F1), a title with a
// leading space parses as no item at all (F3), a status-suffixed title is cut
// (O2), and a description line `## CON-N — …` splits the item in two (O1).
// The functions below run the REAL renderer transforms and the REAL parser on
// the complete stored item (id, title, body, representation, carried fields),
// so every write path and md-to-db judge the same thing the next sync does.
// ---------------------------------------------------------------------------

// renderedItemBody returns the exact text `sync db-to-md` writes for it.
// renderDocument applies these same three transforms, in this order.
func renderedItemBody(it item) string {
	body := canonicalizeBodyStatusLine(it.BodyMD, it.Status)
	body = alignMetaLines(body, it)
	return canonicalizeStateLines(body, it.States, it.repOrDefault())
}

// metaFieldOrder is the order renderItemBody writes the item's own metadata
// lines in; alignMetaLines inserts a missing line after its predecessors.
var metaFieldOrder = []string{"Status", "Type", "Severity", "Created-By", "Assigned-To"}

// alignMetaLines returns body with its own `**Type:**`, `**Severity:**`,
// `**Created-By:**` and `**Assigned-To:**` lines carrying the item's column
// values: the generator symmetry renderDocument already applies to the Status
// line (ATM-627) and the state records (§11.4.292), extended to the other
// fields the parser derives from the body. Without it a column changed by a
// path that did not rewrite the body (measured: three live items whose
// severity column differs from their body) is silently reverted by the next
// md-to-db. STRICT no-op when the body already parses to the columns, which
// every md-to-db-synced item does by construction.
func alignMetaLines(body string, it item) string {
	if it.repOrDefault() != "section" || strings.TrimSpace(body) == "" {
		return body
	}
	parsed := buildItem(it.AtmID, it.Title, body, it.CurrentLocation)
	for _, f := range []struct{ key, col, got string }{
		{"Type", it.Type, parsed.Type},
		{"Severity", strings.TrimSpace(it.Severity), parsed.Severity},
		{"Created-By", strings.TrimSpace(it.CreatedBy), parsed.CreatedBy},
		{"Assigned-To", strings.TrimSpace(it.AssignedTo), parsed.AssignedTo},
	} {
		if f.key == "Type" && (f.col == "" || normalizeType(f.col) == f.got) {
			continue
		}
		if f.col == f.got {
			continue
		}
		body = setOwnMetaLine(body, f.key, f.col)
	}
	return body
}

// setOwnMetaLine makes the item's own metadata region read `**key:** value`:
// the LAST own line for key (the one buildItem reads, last-wins) is replaced;
// with no such line one is inserted after the nearest preceding key of
// metaFieldOrder (or after the heading block); an empty value removes every own
// line for key.
func setOwnMetaLine(body, key, value string) string {
	lines := splitKeepNewlines(body)
	// CON-456 round 6: only unfenced lines of the own region (ownlines.go).
	r := newOwnRegion(lines)
	eol := bodyEOL(lines)
	keyOf := func(ln string) string {
		m := metaLineRe.FindStringSubmatch(strings.TrimRight(ln, "\n"))
		if m == nil {
			return ""
		}
		return strings.ToLower(m[1])
	}
	want := strings.ToLower(key)
	if value == "" {
		out := make([]string, 0, len(lines))
		for i, ln := range lines {
			if r.own(i) && keyOf(ln) == want {
				continue
			}
			out = append(out, ln)
		}
		return strings.Join(out, "")
	}
	newLine := "**" + key + ":** " + value
	last := -1
	for i := 0; i < r.limit; i++ {
		if r.own(i) && keyOf(lines[i]) == want {
			last = i
		}
	}
	if last >= 0 {
		lines[last] = newLine + eolOf(lines[last])
		return strings.Join(lines, "")
	}
	// Insert after the last own line of the nearest preceding key that exists.
	at := -1
	for k := len(metaFieldOrder) - 1; k >= 0 && at < 0; k-- {
		if strings.EqualFold(metaFieldOrder[k], key) {
			continue
		}
		before := false
		for _, o := range metaFieldOrder {
			if strings.EqualFold(o, key) {
				break
			}
			if o == metaFieldOrder[k] {
				before = true
			}
		}
		if !before {
			continue
		}
		pk := strings.ToLower(metaFieldOrder[k])
		for i := 0; i < r.limit; i++ {
			if r.own(i) && keyOf(lines[i]) == pk {
				at = i
			}
		}
	}
	if at < 0 {
		// No preceding key: after the heading and its blank line.
		at = 0
		if len(lines) > 1 && strings.TrimSpace(lines[1]) == "" {
			at = 1
		}
	}
	if !strings.HasSuffix(lines[at], "\n") {
		lines[at] += eol
	}
	out := make([]string, 0, len(lines)+1)
	out = append(out, lines[:at+1]...)
	out = append(out, newLine+eol)
	out = append(out, lines[at+1:]...)
	return strings.Join(out, "")
}

// parseForLocation runs the parser of the tracker an item lives in.
func parseForLocation(location, content string) ([]item, []segment, bool) {
	switch location {
	case "Issues":
		items, segs := parseIssues(content)
		return items, segs, true
	case "Fixed":
		items, segs := parseFixed(content)
		return items, segs, true
	}
	return nil, nil, false
}

// carriedFieldDiffs lists every field the parser derives from an item's
// Markdown that differs between got (parsed) and want (stored). The
// description is not compared: md-to-db derives it from the title and the
// body (deriveDescription) by design, so it is not a round-trip field.
func carriedFieldDiffs(got, want item) []string {
	var d []string
	cmp := func(field, g, w string) {
		if g != w {
			d = append(d, fmt.Sprintf("%s reads back as %q, stored %q", field, g, w))
		}
	}
	cmp("title", got.Title, want.Title)
	cmp("type", got.Type, want.Type)
	cmp("status", got.Status, want.Status)
	cmp("severity", got.Severity, want.Severity)
	cmp("created-by", got.CreatedBy, want.CreatedBy)
	cmp("assigned-to", got.AssignedTo, want.AssignedTo)
	if want.repOrDefault() == "table" {
		cmp("closure date", got.ClosureDate, want.ClosureDate)
		cmp("round", got.Round, want.Round)
		cmp("commit", got.CommitRef, want.CommitRef)
	}
	if got.States.norm() != want.States.norm() {
		d = append(d, "the reproduction/investigation records read back differently from the stored state columns")
	}
	return d
}

// itemWhere names an item in a refusal or a violation.
func itemWhere(it item) string {
	return fmt.Sprintf("%s (%s, %s)", it.AtmID, it.CurrentLocation, it.repOrDefault())
}

// roundTripProblems returns nil iff the text sync db-to-md writes for it,
// read back by the parser of its tracker, is exactly one item segment with the
// same id, the same representation, the same body bytes and the same carried
// fields. An empty body is not judged (no heading is written for it).
func roundTripProblems(it item) []string {
	body := renderedItemBody(it)
	if strings.TrimSpace(body) == "" {
		return nil
	}
	where := itemWhere(it)
	items, segs, ok := parseForLocation(it.CurrentLocation, body)
	if !ok {
		return []string{fmt.Sprintf("%s: unknown tracker %q", where, it.CurrentLocation)}
	}
	if len(items) != 1 || len(segs) != 1 || segs[0].Kind != "item" {
		ids := make([]string, 0, len(items))
		for _, p := range items {
			ids = append(ids, p.AtmID)
		}
		return []string{fmt.Sprintf("%s: its Markdown reads back as %d item(s) %v in %d segment(s), not as this one item",
			where, len(items), ids, len(segs))}
	}
	got := items[0]
	var p []string
	if got.AtmID != baseItemID(it.AtmID) {
		p = append(p, fmt.Sprintf("%s: its heading reads back as id %q", where, got.AtmID))
	}
	if got.repOrDefault() != it.repOrDefault() {
		p = append(p, fmt.Sprintf("%s: it reads back as a %s item", where, got.repOrDefault()))
	}
	if got.BodyMD != body {
		p = append(p, fmt.Sprintf("%s: its body does not read back byte-identically", where))
	}
	for _, d := range carriedFieldDiffs(got, it) {
		p = append(p, where+": "+d)
	}
	return p
}

// gateItemWrite is the write gate every body-writing command calls before it
// stores an item (it.BodyMD is the body the command is about to store). It
// judges the text sync db-to-md will write for that item (renderedItemBody)
// and refuses when that text does not read back as the item, or when an
// operator-supplied text the command embeds (inputs) does not survive in it
// verbatim. It returns the body to store, unchanged: the stored body keeps
// the command's own bytes (the body-preservation contracts of move, reopen and
// update hold), and the generator symmetry is applied at render, as for the
// Status line. Nothing is written on a refusal; the caller exits non-zero.
func gateItemWrite(it item, inputs ...string) (string, error) {
	rendered := renderedItemBody(it)
	if probs := roundTripProblems(it); len(probs) > 0 {
		return "", fmt.Errorf("the Markdown of %s would not read back as this item on the next sync md-to-db: %s",
			itemWhere(it), strings.Join(probs, "; "))
	}
	for _, in := range inputs {
		if in != "" && !strings.Contains(rendered, in) {
			return "", fmt.Errorf("the text %q would not survive in the Markdown of %s: a line in it that reads as one of the item's own metadata lines (for example `**Status:**`, `**Severity:**`) is rewritten from the item's columns",
				in, itemWhere(it))
		}
	}
	return it.BodyMD, nil
}

// titleRoundTrips reports why a title, rendered under id in either tracker,
// does not read back as that title (nil when it does). It isolates the title
// as the cause for a refusal message (review F9).
func titleRoundTrips(id, title string) error {
	const probeDesc = "title round-trip probe description, long enough for the description floor."
	for _, doc := range []struct{ name, status string }{
		{"Issues", "Queued"}, {"Fixed", "Fixed (→ Fixed.md)"},
	} {
		it := item{AtmID: id, Title: title, Type: "Task", Status: doc.status, CurrentLocation: doc.name,
			Representation: "section"}
		it.BodyMD = renderItemBody(id, title, "Task", "", probeDesc, doc.status, "", "")
		if probs := roundTripProblems(it); len(probs) > 0 {
			return fmt.Errorf("title %q does not round-trip under id %q in %s.md: %s",
				title, id, doc.name, strings.Join(probs, "; "))
		}
	}
	return nil
}

// mdImportLosses returns every item of `document` the database holds that a
// rebuild from content would drop or change although the Markdown still
// carries what sync db-to-md wrote for it. stored is the whole items table,
// parsed what the parser read from content. The cases:
//
//   - the Markdown holds the item's rendered text unchanged and the parser
//     reads an item with its id and representation: refuse when a carried
//     field would change (the parser reads the unchanged text differently);
//   - the Markdown holds the rendered text verbatim, but the parser reads no
//     item with the id, or only a truncated body (a description line split it,
//     O1): refuse;
//   - the parser reads no item with the id but the item's heading line is still
//     a line of the Markdown (the heading now parses as another id or as no
//     item, F1/F4): refuse.
//
// Anything else is a real edit or a deletion in the Markdown and is imported.
func mdImportLosses(stored []item, document, content string, parsed []item) []string {
	byKey := map[string][]item{}
	for _, p := range parsed {
		k := baseItemID(p.AtmID) + "\x00" + p.repOrDefault()
		byKey[k] = append(byKey[k], p)
	}
	lines := map[string]bool{}
	for _, ln := range splitKeepNewlines(content) {
		lines[strings.TrimRight(ln, "\n")] = true
	}
	var out []string
	for _, x := range stored {
		if x.CurrentLocation != document {
			continue
		}
		r := renderedItemBody(x)
		if strings.TrimSpace(r) == "" {
			continue
		}
		where := itemWhere(x)
		ps := byKey[baseItemID(x.AtmID)+"\x00"+x.repOrDefault()]
		var same *item
		truncated := false
		for i := range ps {
			switch {
			case ps[i].BodyMD == r || ps[i].BodyMD == r+"\n":
				same = &ps[i]
			case len(ps[i].BodyMD) < len(r) && strings.HasPrefix(r, ps[i].BodyMD):
				truncated = true
			}
			if same != nil {
				break
			}
		}
		present := strings.Contains(content, r)
		heading := strings.TrimRight(strings.SplitN(r, "\n", 2)[0], "\n")
		switch {
		case same != nil:
			if d := carriedFieldDiffs(*same, x); len(d) > 0 {
				out = append(out, fmt.Sprintf("%s: the Markdown is unchanged but the import would change it: %s",
					where, strings.Join(d, "; ")))
			}
		case present && (truncated || len(ps) == 0):
			out = append(out, fmt.Sprintf("%s: the Markdown still holds its text but the parser reads it as %s",
				where, readAs(parsed, r)))
		case len(ps) == 0 && lines[heading]:
			out = append(out, fmt.Sprintf("%s: its heading line %q is still in the Markdown but the parser reads it as %s",
				where, heading, readAs(parsed, heading)))
		}
	}
	return out
}

// readAs names what the parser made of a text the database item wrote: the
// parsed items whose body starts with, or contains, its first line.
func readAs(parsed []item, text string) string {
	head := strings.TrimRight(strings.SplitN(text, "\n", 2)[0], "\n")
	var ids []string
	for _, p := range parsed {
		if strings.Contains(p.BodyMD, head) {
			ids = append(ids, fmt.Sprintf("%s [%s]", p.AtmID, p.repOrDefault()))
		}
	}
	if len(ids) == 0 {
		return "no item (raw text)"
	}
	return "item(s) " + strings.Join(ids, ", ")
}

// gateNewItem is the gate of a path that writes an item from operator text
// (add, update --title): it names the cause of a refusal in the order id,
// title, then the rest of the item (review F9: a title that cannot round-trip
// was reported as an id-grammar error), and returns the body to store.
func gateNewItem(it item, inputs ...string) (string, error) {
	if err := checkIDRoundTrips(baseItemID(it.AtmID)); err != nil {
		return "", err
	}
	if err := titleRoundTrips(baseItemID(it.AtmID), it.Title); err != nil {
		return "", err
	}
	return gateItemWrite(it, inputs...)
}
