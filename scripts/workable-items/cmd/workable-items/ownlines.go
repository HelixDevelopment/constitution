package main

// ownlines.go — CON-456 round 6 (review r5 finding F1).
//
// ONE definition of "the item's own line". A line of an item body is the
// item's own (a candidate for its Status, Type, Severity, Reproduction,
// Investigation, Unblock-Choices or Operator-Block-Details line) only when it is
//
//   - in the item's own region (before the first nested sub-item heading), and
//   - not inside a fenced code block (the fence delimiter lines included).
//
// A fenced line is text the operator quoted, never metadata. Before round 6
// the parser, the Status canonicalizer and the owned-line gate scanned fenced
// lines (last Status line wins), while the metadata-block finder took the first
// Status line, so a status writer rewrote a fenced `**Status:**` example and
// left the item's own line stale (review r5 F1).
//
// Every reader and writer of an item's own lines gets its lines through
// ownRegion (or itemOwnMetaRegion, the same definition as text). The census
// test TestCON456R6_OwnLineScansUseTheSharedDefinition lists the places that
// may name an own-line marker and fails when a new one is added without going
// through this file.

import "strings"

// fenceRun returns the marker byte and the run length of a fence delimiter
// line (``` or ~~~, at least three), judged on the trimmed line.
func fenceRun(t string) (byte, int, bool) {
	if t == "" || (t[0] != '`' && t[0] != '~') {
		return 0, 0, false
	}
	c := t[0]
	n := 0
	for n < len(t) && t[n] == c {
		n++
	}
	if n < 3 {
		return 0, 0, false
	}
	return c, n, true
}

// fencedMask marks the lines inside a fenced code block, the delimiter lines
// included. A fence closes on a line of the same marker, at least as long as
// the opening run, with nothing after it. An UNTERMINATED fence is not a fence:
// CommonMark would let it run to the end of the body, but a stray fence line
// must never turn the item's real Status line (or any later metadata) into
// quoted text, so such lines keep the pre-round-6 reading (own lines).
func fencedMask(lines []string) []bool {
	mask := make([]bool, len(lines))
	var open byte
	openN, openAt := 0, 0
	for i, ln := range lines {
		t := strings.TrimSpace(ln)
		if open == 0 {
			if c, n, ok := fenceRun(t); ok {
				open, openN, openAt = c, n, i
				mask[i] = true
			}
			continue
		}
		mask[i] = true
		if c, n, ok := fenceRun(t); ok && c == open && n >= openN && strings.TrimSpace(t[n:]) == "" {
			open = 0
		}
	}
	if open != 0 {
		for j := openAt; j < len(lines); j++ {
			mask[j] = false
		}
	}
	return mask
}

// ownRegion is an item body seen as its own lines.
type ownRegion struct {
	lines  []string
	limit  int    // lines [0,limit) are the item's own region
	fenced []bool // line i is inside a fenced code block
}

func newOwnRegion(lines []string) ownRegion {
	f := fencedMask(lines)
	limit := len(lines)
	for i, ln := range lines {
		if !f[i] && isSubItemHeading(strings.TrimRight(ln, "\r\n")) {
			limit = i
			break
		}
	}
	return ownRegion{lines: lines, limit: limit, fenced: f}
}

// own reports whether line i is one of the item's own lines.
func (r ownRegion) own(i int) bool { return i >= 0 && i < r.limit && !r.fenced[i] }

// lastIdx returns the last own line with the prefix, or -1.
func (r ownRegion) lastIdx(prefix string) int {
	for i := r.limit - 1; i >= 0; i-- {
		if !r.fenced[i] && strings.HasPrefix(bodyText(r.lines[i]), prefix) {
			return i
		}
	}
	return -1
}

// firstIdx returns the first own line with the prefix at or after from, or -1.
func (r ownRegion) firstIdx(prefix string, from int) int {
	for i := from; i < r.limit; i++ {
		if i >= 0 && !r.fenced[i] && strings.HasPrefix(bodyText(r.lines[i]), prefix) {
			return i
		}
	}
	return -1
}

// statusIdx is the item's own Status line: the last own `**Status:**` line,
// which is the line the parser reads (buildItem lets the last one win).
func (r ownRegion) statusIdx() int { return r.lastIdx("**Status:**") }

// blockEnd returns the end of the metadata block that holds line s: the first
// line after s that ends a block (blank, `---`, a heading, a fence), within the
// own region.
func (r ownRegion) blockEnd(s int) int {
	end := s + 1
	for end < r.limit && !metaBlockEnds(r.lines[end]) {
		end++
	}
	return end
}

// eolOf is the line ending of a line: "\r\n", "\n" or "".
func eolOf(line string) string {
	t := strings.TrimRight(line, "\r\n")
	return line[len(t):]
}

// bodyEOL is the line ending new lines inserted into the body get: CRLF when
// more of its lines end in CRLF than in a bare LF, else LF.
func bodyEOL(lines []string) string {
	crlf, lf := 0, 0
	for _, ln := range lines {
		switch eolOf(ln) {
		case "\r\n":
			crlf++
		case "\n":
			lf++
		}
	}
	if crlf > lf {
		return "\r\n"
	}
	return "\n"
}

// blankFenced returns body with every fenced line replaced by an empty line
// (the line count and the unfenced lines are unchanged); body itself when it
// has no fenced line.
func blankFenced(body string) string {
	lines := splitKeepNewlines(body)
	mask := fencedMask(lines)
	any := false
	for _, f := range mask {
		if f {
			any = true
			break
		}
	}
	if !any {
		return body
	}
	var b strings.Builder
	for i, ln := range lines {
		if mask[i] {
			b.WriteString(eolOf(ln))
			continue
		}
		b.WriteString(ln)
	}
	return b.String()
}
