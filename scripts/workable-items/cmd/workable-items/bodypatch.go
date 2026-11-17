package main

// bodypatch.go — CON-456 round 5 (structural; review r4 findings 1 to 5).
//
// Rounds 3 and 4 kept `update --description`, `block` and `close` regenerating
// an item body from its columns (renderItemBody) and then carried back a closed
// list of engine-written detail lines. The columns do not hold the rest of a
// body: for an item read by `sync md-to-db` the description column is derived
// (deriveDescription), so a regeneration dropped every authored line (measured
// on a copy of the real tracker: 207 items lost more than 100 bytes each,
// 314,118 bytes in total, among them 24 §11.4.290 Verification lines). And the
// carry list had holes (a description line equal to an engine line was
// skipped, so two edits lost a block record).
//
// The structural rule, one invariant for every body writer:
//
//	A body writer may change only the lines it owns. Every other line of the
//	stored body stays, byte for byte and in order.
//
// Writers patch the existing body in place (as reopen and move already did).
// The owned lines are named by position, never by a list of line kinds to
// carry:
//
//   - the heading line (update --title);
//   - the item's own `**Status:**` line (every status writer);
//   - the structured reproduction and investigation records, which follow the
//     state columns (canonicalizeStateLines, every writer);
//   - the description region: the lines of the body equal to the old
//     description column, found after the metadata block (update
//     --description replaces exactly that region; when the body holds no such
//     region the new text is inserted as a paragraph after the metadata block
//     and nothing is removed);
//   - records of the metadata block (the run of `**Key:**` lines that holds
//     the item's own Status line): the closure `**Evidence:**` line (close),
//     the §11.4.21 `**Operator-Block-Details:**` record with its continuation
//     and `**Unblock-Choices:**` lines (block writes it; a writer that moves
//     the item off Operator-blocked ends it and removes it), `**Obsolete-
//     Details:**` (obsolete-details) and `**Reopened-Details:**` (reopen).
//
// A record line outside the metadata block (an indented quote in prose, a line
// in a fenced block, a quote in the description) is the operator's text and
// is never a record a writer owns. ownedLinesProblems is the gate every
// patching writer runs: it removes the owned lines from the old and the new
// body and refuses the write when what remains differs.

import (
	"database/sql"
	"fmt"
	"strings"
)

// Record kinds of the metadata block.
const (
	recEvidence = "Evidence"
	recOBD      = "Operator-Block-Details"
	recChoices  = "Unblock-Choices"
	recObsolete = "Obsolete-Details"
	recReopened = "Reopened-Details"
)

// isFenceLine reports whether a line opens or closes a fenced code block.
func isFenceLine(line string) bool {
	t := strings.TrimSpace(line)
	return strings.HasPrefix(t, "```") || strings.HasPrefix(t, "~~~")
}

// bodyText is a body line without its line ending.
func bodyText(line string) string { return strings.TrimRight(line, "\r\n") }

// recordKindOf returns the record kind a metadata-block line starts, or "".
// The block record marker is matched as the parser matches it (leading space
// ignored, with or without the colon form, operatorBlockParts); the other
// records are `**Key:**` lines at the start of the line (metaLineRe).
func recordKindOf(line string) string {
	t := bodyText(line)
	if strings.HasPrefix(strings.TrimSpace(t), "**Operator-Block-Details") {
		return recOBD
	}
	for _, k := range []string{recEvidence, recChoices, recObsolete, recReopened} {
		if strings.HasPrefix(t, "**"+k+":**") {
			return k
		}
	}
	return ""
}

// metaBlock is the item's own metadata block: the contiguous lines [start,end)
// around the item's first own `**Status:**` line, bounded by a blank line, a
// `---` separator, a heading or a fence. typeIdx is the block's `**Type:**`
// line or -1. A body without a Status line has an empty block at the state
// anchor (stateAnchor).
type metaBlock struct{ start, end, typeIdx int }

func metaBlockEnds(line string) bool {
	t := strings.TrimSpace(line)
	return t == "" || t == "---" || strings.HasPrefix(t, "#") || isFenceLine(line)
}

func metaBlockOf(lines []string) metaBlock {
	limit := ownMetaRegionLineCount(lines)
	s := -1
	for i := 0; i < limit; i++ {
		if strings.HasPrefix(lines[i], "**Status:**") {
			s = i
			break
		}
	}
	if s < 0 {
		a := stateAnchor(lines, limit)
		return metaBlock{a, a, -1}
	}
	start := s
	for start > 0 && !metaBlockEnds(lines[start-1]) {
		start--
	}
	end := s + 1
	for end < limit && !metaBlockEnds(lines[end]) {
		end++
	}
	ty := -1
	for i := start; i < end; i++ {
		if strings.HasPrefix(lines[i], "**Type:**") {
			ty = i
			break
		}
	}
	return metaBlock{start, end, ty}
}

// recSpan is one record of the metadata block: lines [a,b).
type recSpan struct {
	kind string
	a, b int
}

// metaRecords returns the records of the metadata block in order. The block
// record runs as the parser reads it (operatorBlockParts: continuation lines
// up to a sibling `**Label:**` line); a Reopened-Details line takes the
// contiguous attribution bullets after it (isReopenedDetailBullet).
func metaRecords(lines []string, m metaBlock) []recSpan {
	var out []recSpan
	for i := m.start; i < m.end; i++ {
		k := recordKindOf(lines[i])
		if k == "" {
			continue
		}
		j := i + 1
		switch k {
		case recOBD:
			for j < m.end {
				t := strings.TrimSpace(lines[j])
				if strings.HasPrefix(t, "**") && strings.Contains(t, ":**") {
					break
				}
				j++
			}
		case recReopened:
			for j < m.end && isReopenedDetailBullet(lines[j]) {
				j++
			}
		}
		out = append(out, recSpan{k, i, j})
		i = j - 1
	}
	return out
}

// withNewline returns s ending in exactly the line ending ref ends with.
func withNewline(s, ref string) string {
	if strings.HasSuffix(ref, "\n") {
		return s + "\n"
	}
	return s
}

// joinLines joins lines that carry their own line endings; a line that is not
// the last and has no ending gets one (an insertion after a body's last line).
func joinLines(lines []string) string {
	var b strings.Builder
	for i, ln := range lines {
		b.WriteString(ln)
		if i < len(lines)-1 && !strings.HasSuffix(ln, "\n") {
			b.WriteString("\n")
		}
	}
	return b.String()
}

// setRecord writes one record of kind into the metadata block: the first
// record of that kind is replaced in place (with its continuation lines) and
// any later record of the same kind in the block is removed; with none, the
// record is inserted after the block's Type line (Obsolete-Details: at the end
// of the block). Lines outside the block are never touched.
func setRecord(body, kind, record string) string {
	lines := splitKeepNewlines(body)
	m := metaBlockOf(lines)
	recs := metaRecords(lines, m)
	var out []string
	done := false
	pos := 0
	for _, r := range recs {
		if r.kind != kind {
			continue
		}
		out = append(out, lines[pos:r.a]...)
		if !done {
			out = append(out, withNewline(record, lines[r.b-1]))
			done = true
		}
		pos = r.b
	}
	if done {
		out = append(out, lines[pos:]...)
		return joinLines(out)
	}
	at := m.end
	if kind != recObsolete && m.typeIdx >= 0 {
		at = m.typeIdx + 1
	}
	out = append(out, lines[:at]...)
	out = append(out, record+"\n")
	out = append(out, lines[at:]...)
	return joinLines(out)
}

// dropRecords removes every record of the given kinds from the metadata block
// and returns the new body and the removed text. Lines outside the block are
// never touched.
func dropRecords(body string, kinds ...string) (string, string) {
	want := map[string]bool{}
	for _, k := range kinds {
		want[k] = true
	}
	lines := splitKeepNewlines(body)
	var out, removed []string
	pos := 0
	for _, r := range metaRecords(lines, metaBlockOf(lines)) {
		if !want[r.kind] {
			continue
		}
		out = append(out, lines[pos:r.a]...)
		for _, ln := range lines[r.a:r.b] {
			removed = append(removed, bodyText(ln))
		}
		pos = r.b
	}
	if len(removed) == 0 {
		return body, ""
	}
	out = append(out, lines[pos:]...)
	return joinLines(out), strings.Join(removed, "\n")
}

// descriptionRegion returns the lines [a,b) of the body equal, line for line,
// to desc: the first such run after the metadata block within the item's own
// region; ok is false when desc is blank or there is no such run.
func descriptionRegion(lines []string, desc string) (a, b int, ok bool) {
	if strings.TrimSpace(desc) == "" {
		return 0, 0, false
	}
	want := strings.Split(desc, "\n")
	m := metaBlockOf(lines)
	limit := ownMetaRegionLineCount(lines)
	for i := m.end; i+len(want) <= limit; i++ {
		match := true
		for k, w := range want {
			if bodyText(lines[i+k]) != strings.TrimRight(w, "\r") {
				match = false
				break
			}
		}
		if match {
			return i, i + len(want), true
		}
	}
	return 0, 0, false
}

// replaceDescription replaces the description region of body (oldDesc) with
// newDesc. Without a region, an unchanged description changes nothing and a
// new one is inserted as a paragraph right after the metadata block; no line
// of the body is removed.
func replaceDescription(body, oldDesc, newDesc string) string {
	lines := splitKeepNewlines(body)
	nl := strings.Split(newDesc, "\n")
	if a, b, ok := descriptionRegion(lines, oldDesc); ok {
		var out []string
		out = append(out, lines[:a]...)
		for i, ln := range nl {
			if i == len(nl)-1 {
				out = append(out, withNewline(ln, lines[b-1]))
			} else {
				out = append(out, ln+"\n")
			}
		}
		out = append(out, lines[b:]...)
		return joinLines(out)
	}
	if strings.TrimSpace(oldDesc) == strings.TrimSpace(newDesc) {
		return body
	}
	m := metaBlockOf(lines)
	var ins []string
	at := m.end
	if at < len(lines) && strings.TrimSpace(lines[at]) == "" {
		at++
	} else {
		ins = append(ins, "\n")
	}
	for _, ln := range nl {
		ins = append(ins, ln+"\n")
	}
	ins = append(ins, "\n")
	var out []string
	out = append(out, lines[:at]...)
	out = append(out, ins...)
	out = append(out, lines[at:]...)
	return joinLines(out)
}

// bodyOwnership names the lines a writer owns (see the file comment).
type bodyOwnership struct {
	title, status bool
	records       []string
	description   bool
	// fields are the `**Key:**` lines of the item's own metadata region the
	// writer owns (update --severity / --type / --assigned-to / --created-by),
	// matched by key, case-insensitive.
	fields []string
}

// unownedLines returns the non-blank lines of body that the writer does not
// own, without line endings, in order. desc is the description the body is
// expected to hold (the old one in the old body, the new one in the new).
func unownedLines(body string, own bodyOwnership, desc string) []string {
	lines := splitKeepNewlines(body)
	skip := make([]bool, len(lines))
	if own.title {
		for i, ln := range lines {
			if strings.HasPrefix(ln, "## ") {
				skip[i] = true
				break
			}
		}
	}
	limit := ownMetaRegionLineCount(lines)
	if own.status {
		last := -1
		for i := 0; i < limit; i++ {
			if strings.HasPrefix(bodyText(lines[i]), "**Status:**") {
				last = i
			}
		}
		if last >= 0 {
			skip[last] = true
		}
	}
	if len(own.fields) > 0 {
		fk := map[string]bool{}
		for _, k := range own.fields {
			fk[strings.ToLower(k)] = true
		}
		for i := 0; i < limit; i++ {
			if m := metaLineRe.FindStringSubmatch(bodyText(lines[i])); m != nil && fk[strings.ToLower(m[1])] {
				skip[i] = true
			}
		}
	}
	sp := parseStateLines(body)
	for _, i := range []int{sp.reproIdx, sp.invIdx} {
		if i >= 0 && i < len(skip) {
			skip[i] = true
		}
	}
	owned := map[string]bool{}
	for _, k := range own.records {
		owned[k] = true
	}
	for _, r := range metaRecords(lines, metaBlockOf(lines)) {
		if owned[r.kind] {
			for i := r.a; i < r.b; i++ {
				skip[i] = true
			}
		}
	}
	if own.description {
		if a, b, ok := descriptionRegion(lines, desc); ok {
			for i := a; i < b; i++ {
				skip[i] = true
			}
		}
	}
	var out []string
	for i, ln := range lines {
		if skip[i] || strings.TrimSpace(ln) == "" {
			continue
		}
		out = append(out, bodyText(ln))
	}
	return out
}

// ownedLinesProblems is the gate: the lines of oldBody the writer does not own
// must be the lines of newBody it does not own, in the same order. Blank lines
// are not compared (a paragraph break carries no content). It returns nil for
// an empty old body (nothing to keep).
func ownedLinesProblems(oldBody, newBody string, own bodyOwnership, oldDesc, newDesc string) []string {
	if strings.TrimSpace(oldBody) == "" {
		return nil
	}
	o := unownedLines(oldBody, own, oldDesc)
	n := unownedLines(newBody, own, newDesc)
	for i := 0; i < len(o) || i < len(n); i++ {
		switch {
		case i >= len(n):
			return []string{fmt.Sprintf("the write would drop the line %q, which the writer does not own", o[i])}
		case i >= len(o):
			return []string{fmt.Sprintf("the write would add the line %q, which the writer does not own", n[i])}
		case o[i] != n[i]:
			return []string{fmt.Sprintf("the write would change the line %q into %q; the writer does not own it", o[i], n[i])}
		}
	}
	return nil
}

// blockRecordKept reports a problem when an Operator-blocked item's body would
// no longer carry the block record the parser reads, or a different one: the
// next md-to-db rebuilds operator_block_details from that record (a body
// without one loses the row, §11.4.148 D3). The `**Unblock-Choices:**` value
// is not compared: a choices line outside the metadata block is text a
// description may hold (review r4 finding 5), and obdSnapshot keeps the
// stored row while the Markdown and the database agree.
func blockRecordKept(oldBody, newBody string) []string {
	oldText, _, ook := operatorBlockParts(oldBody)
	newText, _, nok := operatorBlockParts(newBody)
	if ook && (!nok || oldText != newText) {
		return []string{"the write would change or drop the Operator-Block-Details record the next sync md-to-db reads (operator_block_details, §11.4.148 D3)"}
	}
	return nil
}

// endBlockInTx ends an item's §11.4.21 block in the writer's transaction
// (review r4 finding 3): the operator_block_details row is deleted, so the
// database already holds what the next md-to-db leaves, and the removed block
// record (the body text, when there was one) is kept in item_history.
func endBlockInTx(tx *sql.Tx, id, removed string) error {
	if _, err := tx.Exec(`DELETE FROM operator_block_details WHERE atm_id=?`, id); err != nil {
		return fmt.Errorf("remove the block record: %v", err)
	}
	if err := recordHistory(tx, id, "Updated", "AI", "operator-block-ended", removed); err != nil {
		return fmt.Errorf("history: %v", err)
	}
	return nil
}
