// parse.go — Markdown → (items + segments) parsers for Issues.md and Fixed.md.
//
// §11.4.93: parsing is byte-preserving. Each source file is decomposed into an
// ordered segment list; item segments additionally carry parsed fields. db→md
// reassembles from segments + items.body_md for a byte-identical round-trip.
package main

import (
	"crypto/sha1"
	"encoding/hex"
	"regexp"
	"strings"
)

// issueHeadingRe matches the canonical HelixCode Issues.md item heading:
// `## <ID> — <title>` where <ID> is a ticket id (3 uppercase letters, dash,
// alnum suffix e.g. HXC-014b). The em-dash separator (` — `, U+2014)
// distinguishes item headings from structural headings like
// `## Prefix convention`. This is the ORIGINAL, backward-compatible form and
// is recognised unconditionally (no Status-block requirement).
var issueHeadingRe = regexp.MustCompile(`^## ([A-Z]{3}-[0-9A-Za-z]+)(?: \([^)]*\))? — (.+)$`)

// atmBracketIDRe matches a project-neutral `[PREFIX-NNN]` ticket id appearing
// anywhere in a heading line, e.g. `## §GL CRITICAL — [ATM-238] title …` or
// `## §JY [SPK-478] title …`. §11.4.28 project-decoupling: this UNIVERSAL tool
// MUST NOT hardcode any consuming project's specific ticket prefixes — the
// prefix is any uppercase-alpha token of ≥2 chars, so a project registering a
// `[XYZ-NNN]` heading id is recognised without a code change. Without a match a
// Shape-1/Shape-3 heading whose real id is bracketed silently falls through to
// the section-letter code or a content-hash pseudo-id, producing phantom sync
// divergences.
var atmBracketIDRe = regexp.MustCompile(`\[([A-Z]{2,}-\d+)\]`)

// atmCandidateHeadingRe recognises a consuming project's real tracker heading
// SHAPES that MAY be workable items (subject to the Status-block test below).
// THREE shapes are accepted — the three the real docs/Fixed.md uses:
//
//	shape 1: ## <CODE>. <title> …      letter-code + a DOT, NO § (dominant ~29 items)
//	                                   e.g. `## GO. …`, `## GS-2. …`, `## BJ-SOURCE. …`
//	shape 2: ## [PREFIX-NNN] <title> … heading STARTS with a `[PREFIX-NNN]` bracket
//	                                   e.g. `## [ATM-248] D11 — VideoOutputManager …`
//	shape 3: ## §<code> <title> …      §-prefixed
//	                                   e.g. `## §FL …`, `## §GB …`
//
// shape 1's CODE is one uppercase letter followed by [A-Za-z0-9]* and an
// optional `-<suffix>` (so `GS-2`, `BJ-SOURCE`, `AD.0`'s `AD` all match), then a
// literal `. ` (dot + space). Single-letter codes (`## U. …`, `## T. …`) match
// too. shape 2's PREFIX is any uppercase-alpha token of ≥2 chars (§11.4.28
// project-decoupling — this UNIVERSAL tool MUST NOT hardcode any consuming
// project's specific ticket prefix; a project registering a `[XYZ-NNN]`
// heading is recognised without a code change). A heading matching ANY shape
// is treated as an item ONLY when its body carries a `**Status:**` metadata
// line BEFORE any nested `### ` subheading (see statusBeforeSubheading) —
// without one it is a section header (`## A. Tooling …`, `## AI/AK. …
// closure cycle`, whose Status sits under a `### `) and is skipped, kept raw.
// Backward-compat note: the canonical `## ABC-123 — …` form is handled by
// issueHeadingRe FIRST and never reaches this path.
var (
	atmShape1HeadingRe = regexp.MustCompile(`^## [A-Z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)?\. \S`)
	atmShape2HeadingRe = regexp.MustCompile(`^## \[[A-Z]{2,}-\d+\] \S`)
	atmShape3HeadingRe = regexp.MustCompile(`^## §\S`)
)

// isATMCandidateHeading reports whether a heading line matches any of the three
// project item-heading shapes. The Status-block test (statusBeforeSubheading)
// is applied separately to confirm it is an item and not a section header.
func isATMCandidateHeading(trimmed string) bool {
	return atmShape1HeadingRe.MatchString(trimmed) ||
		atmShape2HeadingRe.MatchString(trimmed) ||
		atmShape3HeadingRe.MatchString(trimmed)
}

// statusBeforeSubheading is the section-header-vs-item discriminator for
// ATMOSphere-shaped headings. An H2 is an ITEM only when its OWN block carries a
// `**Status:**` line before any nested `### ` (or `#### …`) subheading. Section
// headers like `## A. Tooling …` / `## AI/AK. … closure cycle` carry their
// Status only under a nested `### `, so they correctly fail this test and stay
// raw. `body` is the verbatim H2 block (already cut at the next `## ` / EOF).
func statusBeforeSubheading(body string) bool {
	for _, ln := range splitKeepNewlines(body) {
		t := strings.TrimRight(ln, "\n")
		if isSubItemHeading(t) {
			return false
		}
		if strings.HasPrefix(t, "**Status:**") {
			return true
		}
	}
	return false
}

// isSubItemHeading reports whether a newline-trimmed line opens a NESTED
// sub-item / sub-section inside an item's H2 block. Both parseIssues and
// parseFixed cut item blocks at the next `## ` (any H2), so a `### ` / `#### `
// line inside a block is ALWAYS nested content, never the item's own heading.
//
// Single source of truth for the item-own-region boundary (ATM-842): shared by
// statusBeforeSubheading (the item-vs-section discriminator) and
// ownMetaRegionLineCount (the metadata-derivation scope), so the two can never
// drift apart.
func isSubItemHeading(trimmed string) bool {
	return strings.HasPrefix(trimmed, "### ") || strings.HasPrefix(trimmed, "#### ")
}

// ownMetaRegionLineCount returns how many of `lines` belong to the item ITSELF —
// every line before the first nested sub-item heading (all of them when the
// block has no sub-items).
//
// ATM-842: metadata derivation MUST NOT reach past this boundary. An item block
// containing `### ` sub-items carries their `**Status:**` / `**Type:**` meta
// lines too, and whole-block LAST-wins scanning silently adopted the LAST
// SUB-ITEM's values as the item's own (measured on the live registry: 11 items
// carried a sub-item Status, 8 carried a sub-item Type — e.g. ATM-415, whose
// own `Fixed (→ Fixed.md)`/`Bug` was displaced by its last sub-item's
// `Completed (→ Fixed.md)`/`Task`, breaking §11.4.33 Status↔Type pairing).
func ownMetaRegionLineCount(lines []string) int {
	for i, ln := range lines {
		if isSubItemHeading(strings.TrimRight(ln, "\n")) {
			return i
		}
	}
	return len(lines)
}

// itemOwnMetaRegion returns the prefix of an item's block that belongs to the
// item itself (see ownMetaRegionLineCount). Returns `body` unchanged — the same
// string, no copy — when the block has no nested sub-items, which is the
// overwhelmingly common case.
func itemOwnMetaRegion(body string) string {
	lines := splitKeepNewlines(body)
	n := ownMetaRegionLineCount(lines)
	if n == len(lines) {
		return body
	}
	return strings.Join(lines[:n], "")
}

// metaLineRe extracts `**Key:** value` metadata lines from an item body.
var metaLineRe = regexp.MustCompile(`(?m)^\*\*([A-Za-z-]+):\*\*[ \t]*(.*)$`)

// splitKeepNewlines splits text into lines, each retaining its trailing "\n"
// (the final element has no "\n" iff the source did not end with one). This
// lets us reassemble byte-identically.
func splitKeepNewlines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i+1])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

// parseIssues decomposes Issues.md into items + segments.
func parseIssues(content string) ([]item, []segment) {
	lines := splitKeepNewlines(content)
	var items []item
	var segs []segment
	seq := 0

	var rawBuf strings.Builder
	flushRaw := func() {
		if rawBuf.Len() == 0 {
			return
		}
		segs = append(segs, segment{Document: "Issues", Seq: seq, Kind: "raw", Raw: rawBuf.String()})
		seq++
		rawBuf.Reset()
	}

	seenID := map[string]int{} // atm_id -> dedup counter (PK-collision guard)

	i := 0
	for i < len(lines) {
		trimmed := strings.TrimRight(lines[i], "\n")

		canonical := issueHeadingRe.FindStringSubmatch(trimmed)
		atmShaped := canonical == nil && isATMCandidateHeading(trimmed)

		if canonical == nil && !atmShaped {
			rawBuf.WriteString(lines[i])
			i++
			continue
		}

		// Candidate item heading. Capture the block from this line up to the
		// next `## ` heading (any H2) or EOF — verbatim, for byte-identical
		// round-trip. body_md preserves the exact source bytes regardless of
		// which heading form recognised it.
		var block strings.Builder
		block.WriteString(lines[i])
		i++
		for i < len(lines) {
			lt := strings.TrimRight(lines[i], "\n")
			if strings.HasPrefix(lt, "## ") {
				break
			}
			block.WriteString(lines[i])
			i++
		}
		body := block.String()

		var it item
		if canonical != nil {
			// Canonical `## ABC-123 — title` — unchanged behaviour; recognised
			// unconditionally (no Status-block requirement), exactly as before.
			it = buildItem(canonical[1], canonical[2], body, "Issues")
		} else {
			// ATMOSphere-shaped item. It is a workable item ONLY if its OWN
			// block carries a `**Status:**` line before any nested `### `;
			// otherwise it is a section header → keep it raw so the round-trip
			// is unaffected.
			if !statusBeforeSubheading(body) {
				rawBuf.WriteString(body)
				continue
			}
			id, title := parseATMHeading(trimmed)
			// PK-collision guard: ATMOSphere reuses §-letters across reopened
			// items, and derived ids could theoretically collide. The DB
			// identity is (atm_id, current_location), so disambiguate within
			// Issues here, matching parseFixed's seen-counter discipline.
			if n, ok := seenID[id]; ok {
				seenID[id] = n + 1
				id = id + "#" + itoa(n+1)
			} else {
				seenID[id] = 0
			}
			it = buildItem(id, title, body, "Issues")
		}

		// Close any preceding raw prose into its own segment BEFORE the item
		// segment, preserving source order for byte-identical regeneration.
		flushRaw()
		items = append(items, it)
		segs = append(segs, segment{Document: "Issues", Seq: seq, Kind: "item", AtmID: it.AtmID})
		seq++
	}
	flushRaw()
	return items, segs
}

// atmShape1CodeRe captures the shape-1 letter-code that precedes the `. `
// boundary, e.g. `GO`, `GS-2`, `BJ-SOURCE`, `U`. atmShape2CodeRe captures the
// leading `[PREFIX-NNN]` bracket (any ≥2-char uppercase prefix per §11.4.28
// project-decoupling — see atmBracketIDRe / atmShape2HeadingRe); atmShape3CodeRe
// captures the §-code token.
var (
	atmShape1CodeRe = regexp.MustCompile(`^([A-Z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)?)\. (.*)$`)
	atmShape2CodeRe = regexp.MustCompile(`^\[([A-Z]{2,}-\d+)\] (.*)$`)
	atmShape3CodeRe = regexp.MustCompile(`^§(\S+)\s*(.*)$`)
)

// parseATMHeading extracts the (id, title) pair from a project-shaped H2
// heading line (the leading `## ` already present in `headingLine`). It
// dispatches on the heading shape:
//
//	shape 2 `## [PREFIX-NNN] <rest>` -> id = PREFIX-NNN (the bracket), title = trim(rest)
//	shape 3 `## §<code> <rest>`    -> id = a `[PREFIX-NNN]` bracket anywhere in the
//	                                 heading if present, else derived from the
//	                                 §-code; title = trim(rest)
//	shape 1 `## <CODE>. <rest>`    -> id = a `[PREFIX-NNN]` bracket anywhere in the
//	                                 heading if present, else the CODE itself
//	                                 (`GO`, `GS-2`, `BJ-SOURCE`); title = trim(rest)
//
// The title is the human text AFTER the code-terminating boundary (the `. `
// after a shape-1 code, the `] ` after a shape-2 bracket, the §-code token for
// shape 3) — NOT the first ` — ` (which lands inside the description). trimTitle
// then cuts the trailing backtick-status / `[migrated …]` suffix while
// PRESERVING any inner ` — ` and inner `code` spans the title legitimately
// contains.
//
//	"## GO. 2nd display … — `Fixed (→ Fixed.md)` (…)"            -> ("GO", "2nd display …")
//	"## BJ-SOURCE. Fix #135 — c2.rk.avc.encoder … — `Fixed …`"  -> ("BJ-SOURCE", "Fix #135 — c2.rk.avc.encoder …")
//	"## [ATM-248] D11 — VideoOutputManager … — `Completed …`"   -> ("ATM-248", "D11 — VideoOutputManager …")
//	"## §FL Phase 39.FL D3 … — `Completed …` [migrated …]"      -> ("ATM-DERIVED-xxxxxxxx", "Phase 39.FL D3 …")
func parseATMHeading(headingLine string) (id, title string) {
	heading := strings.TrimSpace(strings.TrimPrefix(headingLine, "## "))

	var rest string
	switch {
	case atmShape2CodeRe.MatchString(heading):
		m := atmShape2CodeRe.FindStringSubmatch(heading)
		id, rest = m[1], m[2]
	case strings.HasPrefix(heading, "§"):
		m := atmShape3CodeRe.FindStringSubmatch(heading)
		rest = m[2]
		if b := atmBracketIDRe.FindStringSubmatch(heading); b != nil {
			id = b[1]
		} else {
			id = deriveATMID(heading)
		}
	case atmShape1CodeRe.MatchString(heading):
		m := atmShape1CodeRe.FindStringSubmatch(heading)
		code, r := m[1], m[2]
		rest = r
		if b := atmBracketIDRe.FindStringSubmatch(heading); b != nil {
			id = b[1]
		} else {
			id = code
		}
	default:
		// Defensive fallback — should not happen for candidate headings.
		rest = heading
		id = deriveATMID(heading)
	}

	title = trimTitle(rest)
	return id, title
}

// statusBacktickRe matches the trailing closure-status boundary: a ` — ` (em-
// dash) immediately followed by a backtick-quoted status token. This is the
// canonical title-terminating boundary across all three shapes.
var statusBacktickRe = regexp.MustCompile(`\s+—\s+\x60`)

// statusBacktickNoDashRe handles the rarer `<title> \`Status…\“ form with a
// bare space before the backtick (e.g. `## JD. … investigation outcome
// \`Completed …\“). It only fires on a recognised closure-status keyword to
// avoid cutting an inner inline `code` span.
var statusBacktickNoDashRe = regexp.MustCompile(`\s+\x60(?:Fixed|Implemented|Completed|Obsolete|FIXED|OPEN|OBSOLETE|RESOLVED)`)

// trimTitle returns the human-readable title from the post-code remainder of an
// ATMOSphere heading: cut at the trailing backtick-status boundary (preserving
// inner ` — ` and inner `code` spans), strip any leftover `[ATM-NNN]` bracket,
// and drop a trailing ` [migrated …]` / parenthetical when no status backtick
// is present.
func trimTitle(rest string) string {
	if loc := statusBacktickRe.FindStringIndex(rest); loc != nil {
		rest = rest[:loc[0]]
	} else if loc := statusBacktickNoDashRe.FindStringIndex(rest); loc != nil {
		rest = rest[:loc[0]]
	} else if idx := strings.Index(rest, " [migrated"); idx >= 0 {
		rest = rest[:idx]
	}
	rest = atmBracketIDRe.ReplaceAllString(rest, "")
	return strings.TrimSpace(rest)
}

// deriveATMID produces a stable, deterministic id for a bracket-less
// ATMOSphere heading: "ATM-DERIVED-<8hexchars>" of the sha1 of the heading
// text (mirrors Herald commons_workable/parser.go deriveID).
func deriveATMID(heading string) string {
	sum := sha1.Sum([]byte(heading))
	return "ATM-DERIVED-" + hex.EncodeToString(sum[:])[:8]
}

// buildItem parses the metadata + description out of an item's raw body block.
func buildItem(id, titleRest, body, location string) item {
	it := item{
		AtmID:           id,
		Title:           titleRest,
		CurrentLocation: location,
		BodyMD:          body,
		Type:            "Task", // §11.4.16 lowest-stakes default when absent
		Status:          "Queued",
	}
	// ATM-842: scan ONLY the item's own metadata region. A nested `### `
	// sub-item's meta lines describe the SUB-ITEM, never the item.
	for _, mm := range metaLineRe.FindAllStringSubmatch(itemOwnMetaRegion(body), -1) {
		key := strings.ToLower(mm[1])
		val := strings.TrimSpace(mm[2])
		switch key {
		case "type":
			it.Type = normalizeType(val)
		case "status":
			it.Status = normalizeStatus(val)
		case "severity":
			it.Severity = val
		case "created-by":
			// §11.4.104 participant attribution. Empty/absent → "" (legacy items
			// parse unchanged). Canonical handle string, stored verbatim.
			it.CreatedBy = val
		case "assigned-to":
			it.AssignedTo = val
		}
	}
	// §11.4.292 (v8): the structured `**Reproduction:**` / `**Investigation:**`
	// records of the item's OWN region become the state columns. Legacy
	// free-form lines carrying the same labels set nothing (never invented); a
	// malformed record contributes only its head state and is reported by
	// `validate` / `diff` (stateColumnBodyDesyncs re-parses the body).
	it.States = parseStateLines(body).rec
	it.Description = deriveDescription(it.Title, body)
	return it
}

// deriveDescription returns a §11.4.91-compliant description (≥6 words OR ≥40
// chars). Deterministic rule: prefer the heading title; if that is too short,
// append the first non-metadata, non-separator prose sentence from the body.
func deriveDescription(title, body string) string {
	base := strings.TrimSpace(title)
	if wordCount(base) >= 6 || len(base) >= 40 {
		return base
	}
	// Find the first prose line in the body that is not a heading, not a
	// `**Key:**` metadata line, not a separator, not blank.
	for _, ln := range splitKeepNewlines(body) {
		t := strings.TrimSpace(ln)
		if t == "" || t == "---" || strings.HasPrefix(t, "## ") {
			continue
		}
		if metaLineRe.MatchString(ln) {
			continue
		}
		// Strip a leading inline `**Key:**` fragment if any remained.
		combined := base
		if combined != "" {
			combined += " — "
		}
		combined += firstSentence(t)
		return combined
	}
	return base
}

func firstSentence(s string) string {
	if idx := strings.IndexAny(s, ".!?"); idx >= 0 {
		return strings.TrimSpace(s[:idx+1])
	}
	return s
}

func wordCount(s string) int {
	return len(strings.Fields(s))
}

// normalizeType maps a raw `**Type:**` value onto the closed set
// {Bug, Feature, Task}. Unknown values default to Task (§11.4.16).
func normalizeType(v string) string {
	v = strings.TrimSpace(v)
	switch {
	case strings.EqualFold(v, "Bug"):
		return "Bug"
	case strings.EqualFold(v, "Feature"):
		return "Feature"
	case strings.EqualFold(v, "Task"):
		return "Task"
	default:
		return "Task"
	}
}

// closedStatuses is the §11.4.15/§11.4.21/§11.4.90 closed-set the schema CHECK
// enforces. normalizeStatus maps a raw `**Status:**` value onto it, tolerating
// trailing prose after the canonical token (e.g. "Fixed (→ Fixed.md) — see…").
var closedStatuses = []string{
	"Fixed (→ Fixed.md)",
	"Implemented (→ Fixed.md)",
	"Completed (→ Fixed.md)",
	"Obsolete (→ Fixed.md)",
	"Queued",
	"In progress",
	"Ready for testing",
	"In testing",
	"Reopened",
	"Operator-blocked",
}

func normalizeStatus(v string) string {
	v = strings.TrimSpace(v)
	// Exact closed-set match first.
	for _, s := range closedStatuses {
		if v == s {
			return s
		}
	}
	// Prefix match (closure values often carry trailing prose).
	for _, s := range closedStatuses {
		if strings.HasPrefix(v, s) {
			return s
		}
	}
	// Graceful fallback for non-closed-set inputs: keep the work moving by
	// mapping common synonyms, else Queued (a valid closed-set value).
	lv := strings.ToLower(v)
	switch {
	case strings.Contains(lv, "obsolete"):
		return "Obsolete (→ Fixed.md)"
	case strings.Contains(lv, "implemented"):
		return "Implemented (→ Fixed.md)"
	case strings.Contains(lv, "completed"):
		return "Completed (→ Fixed.md)"
	case strings.Contains(lv, "fixed"):
		return "Fixed (→ Fixed.md)"
	case strings.Contains(lv, "operator"):
		return "Operator-blocked"
	case strings.Contains(lv, "blocked"):
		// §11.4.148 D3: `Blocked` / `BLOCKED` / `blocked` is the documented alias
		// of the canonical `Operator-blocked` value — normalised here, NOT a
		// silent fork (§11.4.6).
		return "Operator-blocked"
	case strings.Contains(lv, "reopen"):
		return "Reopened"
	case strings.Contains(lv, "in testing"):
		return "In testing"
	case strings.Contains(lv, "ready"):
		return "Ready for testing"
	case strings.Contains(lv, "progress"):
		return "In progress"
	default:
		return "Queued"
	}
}

// lastBodyStatus reconstructs the Status the md→db parser (buildItem) would derive
// from a body_md block, returning (normalizedStatus, true) when the body carries at
// least one `**Status:**` meta line and ("", false) when it carries none. It mirrors
// buildItem EXACTLY: walk every `**Key:** value` line via metaLineRe and let the LAST
// `**Status:**` line win, normalised through normalizeStatus (buildItem's switch
// overwrites it.Status on each `status` key, so last-wins is the faithful semantics).
//
// This shared derivation is the generator-symmetric oracle for the ATM-627 (task #20)
// column↔body Status invariant: a body whose Status line carries trailing prose, a
// `**Priority:**` tail on the same line, or multiple `**Status:**` tokens normalises to
// the SAME value the column was first set to — so those shapes are NOT false-positive
// desyncs (the 8 false-positives the reconciliation plan calls out are resolved here).
func lastBodyStatus(body string) (string, bool) {
	status := ""
	found := false
	// ATM-842: mirrors buildItem EXACTLY — the item's OWN metadata region only.
	for _, mm := range metaLineRe.FindAllStringSubmatch(itemOwnMetaRegion(body), -1) {
		if strings.EqualFold(mm[1], "status") {
			status = normalizeStatus(strings.TrimSpace(mm[2]))
			found = true
		}
	}
	return status, found
}

// canonicalizeBodyStatusLine returns body with the value of its LAST `**Status:**`
// line forced to columnStatus, so `sync db-to-md` emits a Status line consistent with
// the authoritative items.status column even if a direct `UPDATE items SET status=…`
// (bypassing renderItemBody) left body_md stale — the ATM-627 (task #20) generator-
// symmetry / defense-in-depth half of the durable fix.
//
// It is a STRICT no-op — body returned unchanged, byte-for-byte — when the body has no
// `**Status:**` line OR already derives columnStatus (lastBodyStatus == columnStatus).
// Because every freshly md→db-synced item satisfies lastBodyStatus(body)==status BY
// CONSTRUCTION (buildItem sets the column from exactly this derivation), the entire
// clean DB round-trips BYTE-IDENTICALLY through this function; only a genuinely desynced
// item's line is rewritten. Only the Status line's value changes — every other line,
// including `**Reopened-Details:**` / `**Operator-Block-Details:**` blocks and all prose,
// is preserved verbatim (surgical single-line replacement). Composes with the R3
// dangling-segment guard (sync.go danglingItemSegments) — that guards segment↔item
// location; this guards column↔body Status; the two are orthogonal invariants.
func canonicalizeBodyStatusLine(body, columnStatus string) string {
	if cur, ok := lastBodyStatus(body); !ok || cur == columnStatus {
		return body
	}
	lines := splitKeepNewlines(body)
	// ATM-842: the patch target is the item's OWN Status line. Scanning the
	// whole block rewrote the LAST NESTED SUB-ITEM's Status line instead —
	// corrupting the sub-item while leaving the item's own line stale.
	limit := ownMetaRegionLineCount(lines)
	lastIdx := -1
	for i := 0; i < limit; i++ {
		if strings.HasPrefix(strings.TrimRight(lines[i], "\n"), "**Status:**") {
			lastIdx = i
		}
	}
	if lastIdx < 0 {
		return body // defensive: lastBodyStatus said a Status line exists → unreachable
	}
	nl := ""
	if strings.HasSuffix(lines[lastIdx], "\n") {
		nl = "\n"
	}
	lines[lastIdx] = "**Status:** " + columnStatus + nl
	return strings.Join(lines, "")
}

// ensureTrailingNewline normalizes a stored `items.body_md` to end with AT LEAST
// one trailing "\n" — the STORE-side half of the ATM-627 byte-identical
// round-trip (the db-to-md WRITER half landed in 97d405c). Root cause it closes:
// a stored body_md that ends with NO "\n" (the live 9-item residual, e.g.
// `…PROGRESS.md.`) forces renderDocument (db.go) to SYNTHESIZE a separator "\n"
// before the next heading so a heading never glues onto the prior body line — but
// the re-parsed body is then one "\n" longer than the stored body, so
// `workable-items diff` reports `~ <id> body differs (md=N+1 db=N)` and the
// round-trip is not byte-identical.
//
// It is IDEMPOTENT and BYTE-IDENTICAL for an already-normalized body: a body that
// already ends with "\n" is returned UNCHANGED — this deliberately PRESERVES the
// renderItemBody "\n\n" convention (494 live items end "\n\n", 2 end "\n"); it is
// NOT "trim to exactly one \n" (that would mutate every "\n\n" body + collapse the
// inter-item blank line the writer relies on). An EMPTY body is left empty — the
// empty-body class is owned by the classifyRepair populate path (renderItemBody),
// not here, so this never fabricates a heading-less body.
func ensureTrailingNewline(body string) string {
	if body == "" || strings.HasSuffix(body, "\n") {
		return body
	}
	return body + "\n"
}

// operatorBlock is the reconstruction of an item's §11.4.21
// `**Operator-Block-Details:**` block, so the md→db sync can repopulate the
// operator_block_details sub-table (§11.4.148 D3). The four fields mirror the
// schema columns what / why_exhausted_alternatives / unblock_condition / who.
type operatorBlock struct {
	what    string
	why     string
	unblock string
	who     string
}

// parseOperatorBlockDetails reconstructs the §11.4.21 Operator-Block-Details
// fields from an item body_md. Returns ok=false when the body carries NO
// `**Operator-Block-Details` block — the item then gets no sub-table row, which
// the §11.4.148 D3 validator correctly flags for a genuinely-missing block.
//
// The live trackers use several real shapes for the block (all six live
// Operator-blocked items exercised): an inline single line
// (`… WHAT: … WHY: … UNBLOCK: [A]…·[B]… WHO: …`, ATM-356/388/651); a bulleted
// bold block (`- **WHAT operator must do:** …` / `- **WHY …:** …` / …,
// ATM-387/474); and a By/On/Reason/Evidence bullet list whose enumerated
// choices live in a SEPARATE `**Unblock-Choices:**` line (ATM-015/356). The
// captured block runs from the marker line up to the first blank line, sibling
// `**Label:**` field, heading, or `---`. unblock_condition folds in the
// `**Unblock-Choices:**` line + the block's own UNBLOCK text + the whole block,
// so the §11.4.148 D3 enumerated-choice assertion always sees the real choices.
//
// It is READ-ONLY over body_md and never touches the round-trip path
// (renderDocument reassembles documents from body_md/segments, NOT from the
// operator_block_details sub-table), so this reconstruction cannot perturb the
// byte-identical md↔db round-trip.
func parseOperatorBlockDetails(body string) (operatorBlock, bool) {
	lines := strings.Split(body, "\n")
	start := -1
	for i, ln := range lines {
		if strings.HasPrefix(strings.TrimSpace(ln), "**Operator-Block-Details") {
			start = i
			break
		}
	}
	if start < 0 {
		return operatorBlock{}, false
	}
	// Capture the marker line + continuation lines up to the first blank line,
	// sibling `**Label:**` field, heading, or `---` separator. Bullet lines
	// (`- …` / `* …`) are continuation, NOT siblings, so they are included.
	block := []string{lines[start]}
	for j := start + 1; j < len(lines); j++ {
		t := strings.TrimSpace(lines[j])
		if t == "" ||
			(strings.HasPrefix(t, "**") && strings.Contains(t, ":**")) ||
			strings.HasPrefix(t, "## ") || strings.HasPrefix(t, "### ") ||
			strings.HasPrefix(t, "---") {
			break
		}
		block = append(block, lines[j])
	}
	blockText := strings.TrimSpace(strings.Join(block, "\n"))

	// A separate `**Unblock-Choices:**` line (ATM-015/356) carries the enumerated
	// [A]…·[B]… choices OUTSIDE the OBD block; fold it into the unblock text so
	// the §11.4.148 D3 enumerated-choice assertion sees it.
	choices := ""
	for _, mm := range metaLineRe.FindAllStringSubmatch(body, -1) {
		if strings.EqualFold(mm[1], "Unblock-Choices") {
			choices = strings.TrimSpace(mm[2])
		}
	}

	ob := operatorBlock{
		what: firstNonEmpty(extractOBDField(blockText, "WHAT"), blockText),
		why:  firstNonEmpty(extractOBDField(blockText, "WHY"), blockText),
		who:  extractOBDField(blockText, "WHO"), // nullable column → "" is fine
	}
	var parts []string
	if choices != "" {
		parts = append(parts, choices)
	}
	if u := extractOBDField(blockText, "UNBLOCK"); u != "" {
		parts = append(parts, u)
	}
	parts = append(parts, blockText) // safety net: the whole block (its bullets satisfy the enumeration check)
	ob.unblock = strings.TrimSpace(strings.Join(parts, "\n"))
	return ob, true
}

// extractOBDField pulls the text of a single §11.4.21 field (key one of
// WHAT/WHY/UNBLOCK/WHO) from an OBD block, recognising BOTH the bulleted bold
// form (`- **WHAT operator must do:** <text>`) and the inline form
// (`… WHAT: <text> WHY: …`). Returns "" when the field is absent (callers fall
// back to the whole block for the NOT-NULL what/why columns; who is nullable).
func extractOBDField(block, key string) string {
	// (1) bulleted bold form: a bullet whose payload is **<key…>:** <text>.
	for _, ln := range strings.Split(block, "\n") {
		t := strings.TrimSpace(ln)
		t = strings.TrimPrefix(t, "- ")
		t = strings.TrimPrefix(t, "* ")
		if !strings.HasPrefix(t, "**") {
			continue
		}
		closeIdx := strings.Index(t, ":**")
		if closeIdx < 0 {
			continue
		}
		label := strings.ToUpper(strings.TrimSpace(t[2:closeIdx]))
		if strings.HasPrefix(label, key) {
			return strings.TrimSpace(t[closeIdx+3:])
		}
	}
	// (2) inline form: find `KEY:` at a word boundary; the value runs to the
	//     next WHAT:/WHY:/UNBLOCK:/WHO: label or the end of the block.
	upper := strings.ToUpper(block)
	inlineKeys := []string{"WHAT:", "WHY:", "UNBLOCK:", "WHO:"}
	find := func(k string) int {
		from := 0
		for {
			idx := strings.Index(upper[from:], k)
			if idx < 0 {
				return -1
			}
			pos := from + idx
			if pos == 0 || !isOBDWordChar(upper[pos-1]) {
				return pos
			}
			from = pos + len(k)
		}
	}
	kk := key + ":"
	pos := find(kk)
	if pos < 0 {
		return ""
	}
	valStart := pos + len(kk)
	valEnd := len(block)
	for _, other := range inlineKeys {
		if other == kk {
			continue
		}
		if oi := find(other); oi >= valStart && oi < valEnd {
			valEnd = oi
		}
	}
	return strings.TrimSpace(block[valStart:valEnd])
}

// isOBDWordChar reports whether b is an ASCII letter/digit — used to enforce a
// word boundary before an inline `KEY:` so a substring hit inside a larger word
// is not mistaken for the field label.
func isOBDWordChar(b byte) bool {
	return (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') || (b >= '0' && b <= '9')
}

// fixedRowRe matches a LEGACY Fixed.md closure table data row:
// `| <date> | <title> | <Type> | <Status> | <Round> | <Commit(s)> | <Evidence> |`
// The title cell holds `<ID>[ (...)]: <title>` (colon separator in Fixed.md).
// NOTE: the real Fixed.md uses the H2-heading + `**Status:**` block form (see
// parseFixed); this regex remains only for backward-compatible table-form docs.
var fixedRowRe = regexp.MustCompile(`^\| *([0-9]{4}-[0-9]{2}-[0-9]{2}) *\| *(.*?) *\| *([^|]*?) *\| *([^|]*?) *\| *([^|]*?) *\| *(.*?) *\| *(.*?) *\|\s*$`)

// fixedTitleIDRe pulls the leading ticket id out of a Fixed.md title cell.
var fixedTitleIDRe = regexp.MustCompile(`^([A-Z]{3}-[0-9A-Za-z]+)(?: \([^)]*\))?`)

// parseFixed decomposes Fixed.md into items + segments. The REAL Fixed.md uses
// the SAME H2-heading + `**Status:**` metadata-block shape as Issues.md (the
// canonical `## ABC-123 — title` form and the ATMOSphere `## §… [— [ATM-NNN]]
// title` forms), so the primary path mirrors parseIssues. For backward
// compatibility the legacy pipe-table closure rows (fixedRowRe) are ALSO
// recognised inside any raw span. Every emitted item carries
// current_location='Fixed'. The decomposition is byte-preserving: item bodies
// + raw segments reassemble the source exactly.
func parseFixed(content string) ([]item, []segment) {
	lines := splitKeepNewlines(content)
	var items []item
	var segs []segment
	seq := 0

	seenID := map[string]int{} // atm_id -> dedup counter (PK-collision guard)

	// flushRaw emits the buffered raw prose, but FIRST gives the legacy
	// pipe-table closure rows a chance to be recognised within it. Any line
	// matching fixedRowRe becomes its own item segment; surrounding lines stay
	// raw. This preserves the original table-form behaviour byte-identically.
	var rawBuf strings.Builder
	flushRaw := func() {
		if rawBuf.Len() == 0 {
			return
		}
		raw := rawBuf.String()
		rawBuf.Reset()
		emitLegacyTable(raw, &items, &segs, &seq, seenID)
	}

	i := 0
	for i < len(lines) {
		trimmed := strings.TrimRight(lines[i], "\n")

		canonical := issueHeadingRe.FindStringSubmatch(trimmed)
		atmShaped := canonical == nil && isATMCandidateHeading(trimmed)

		if canonical == nil && !atmShaped {
			rawBuf.WriteString(lines[i])
			i++
			continue
		}

		// Candidate item heading. Capture the block verbatim from this line up
		// to the next `## ` heading (any H2) or EOF, for byte-identical
		// round-trip — exactly as parseIssues does.
		var block strings.Builder
		block.WriteString(lines[i])
		i++
		for i < len(lines) {
			lt := strings.TrimRight(lines[i], "\n")
			if strings.HasPrefix(lt, "## ") {
				break
			}
			block.WriteString(lines[i])
			i++
		}
		body := block.String()

		var it item
		if canonical != nil {
			it = buildItem(canonical[1], canonical[2], body, "Fixed")
		} else {
			// ATMOSphere-shaped item. It is a workable item ONLY if its OWN
			// block carries a `**Status:**` line before any nested `### `;
			// otherwise it is a section header (`## A. Tooling …`,
			// `## AI/AK. … closure cycle`) → keep it raw so the round-trip is
			// unaffected.
			if !statusBeforeSubheading(body) {
				rawBuf.WriteString(body)
				continue
			}
			id, title := parseATMHeading(trimmed)
			if n, ok := seenID[id]; ok {
				seenID[id] = n + 1
				id = id + "#" + itoa(n+1)
			} else {
				seenID[id] = 0
			}
			it = buildItem(id, title, body, "Fixed")
		}

		// Close any preceding raw prose into its own segment(s) BEFORE the item
		// segment, preserving source order for byte-identical regeneration.
		flushRaw()
		items = append(items, it)
		segs = append(segs, segment{Document: "Fixed", Seq: seq, Kind: "item", AtmID: it.AtmID})
		seq++
	}
	flushRaw()
	return items, segs
}

// emitLegacyTable walks a raw span line-by-line, splitting out any legacy
// pipe-table closure rows (fixedRowRe) as their own item segments and keeping
// everything else as raw segments. Pointers into parseFixed's running state are
// mutated in place. This keeps the original table-form Fixed.md round-tripping
// byte-identically while the H2-heading form is the primary path.
func emitLegacyTable(raw string, items *[]item, segs *[]segment, seq *int, seenID map[string]int) {
	var buf strings.Builder
	flush := func() {
		if buf.Len() == 0 {
			return
		}
		*segs = append(*segs, segment{Document: "Fixed", Seq: *seq, Kind: "raw", Raw: buf.String()})
		*seq++
		buf.Reset()
	}

	for _, ln := range splitKeepNewlines(raw) {
		trimmed := strings.TrimRight(ln, "\n")
		m := fixedRowRe.FindStringSubmatch(trimmed)
		if m == nil {
			buf.WriteString(ln)
			continue
		}
		// A legacy data row. Resolve its id from the title cell.
		titleCell := m[2]
		idm := fixedTitleIDRe.FindStringSubmatch(titleCell)
		var id string
		if idm != nil {
			id = idm[1]
		} else {
			// No ticket id (legacy narrative rows). Synthesize a stable,
			// document-unique key so the row still round-trips + validates.
			id = "FIX-" + m[1] // date-based
		}
		if n, ok := seenID[id]; ok {
			seenID[id] = n + 1
			id = id + "#" + itoa(n+1)
		} else {
			seenID[id] = 0
		}

		flush()
		it := item{
			AtmID:           id,
			Title:           strings.TrimSpace(titleCell),
			Type:            normalizeType(m[3]),
			Status:          normalizeStatus(m[4]),
			CurrentLocation: "Fixed",
			BodyMD:          ln, // verbatim row (with trailing newline)
			// GAP A: a pipe-table closure row is the 'table' representation, so an
			// id that ALSO has an H2 'section' block in the SAME tracker (HXC-044)
			// does not collide on the (atm_id, current_location, representation) PK.
			Representation: "table",
			// GAP B: capture the pipe-table closure metadata so db→md can
			// SYNTHESIZE a pipe row from DB fields (round-trip already replays
			// body_md; these fields make the row queryable + re-emittable).
			// fixedRowRe groups: 1=Closure 2=Title 3=Type 4=Status 5=Round
			// 6=Commit(s) 7=Evidence.
			ClosureDate: strings.TrimSpace(m[1]),
			Round:       strings.TrimSpace(m[5]),
			CommitRef:   strings.TrimSpace(m[6]),
		}
		it.Description = deriveDescription(it.Title, m[7])
		*items = append(*items, it)
		*segs = append(*segs, segment{Document: "Fixed", Seq: *seq, Kind: "item", AtmID: it.AtmID, Representation: "table"})
		*seq++
	}
	flush()
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
