package main

// detailcarry.go — CON-456 round 4 (review finding 1).
//
// Several commands regenerate an item body from its columns (renderItemBody):
// `update --description`, `block` and `close`. The columns do not hold the
// detail lines other commands wrote into the body: the closure `**Evidence:**`
// line (close), the §11.4.21 `**Operator-Block-Details:**` block and its
// `**Unblock-Choices:**` line (block), the §11.4.90 `**Obsolete-Details:**`
// line (obsolete-details) and the §11.4.34 `**Reopened-Details:**` line with
// its attribution bullets (reopen). A regeneration therefore dropped them, and
// for a blocked item the next sync md-to-db then deleted the
// operator_block_details row (validate: §11.4.148 D3).
//
// The class rule: a write that regenerates a body keeps every engine-written
// detail block of the old body, except the kinds the write itself replaces
// (block replaces the block record, close replaces the evidence line and ends
// the block, reopen replaces Reopened-Details). carryDetailBlocks applies the
// rule and detailLossProblems is the gate that refuses a write which still
// loses one (defence in depth: every regenerating write runs both).

import (
	"fmt"
	"strings"
)

// Detail-block kinds (the closed set the rule covers).
const (
	detailEvidence = "Evidence"
	detailOBD      = "Operator-Block-Details"
	detailChoices  = "Unblock-Choices"
	detailObsolete = "Obsolete-Details"
	detailReopened = "Reopened-Details"
)

var detailKinds = []string{detailEvidence, detailOBD, detailChoices, detailObsolete, detailReopened}

// detailBlock is one engine-written detail block of a body: its kind and its
// lines (without the trailing newline).
type detailBlock struct {
	kind  string
	lines []string
}

func (b detailBlock) text() string { return strings.Join(b.lines, "\n") }

// detailKindOf returns the kind of a body line that starts a detail block, or
// "" when it starts none. Leading whitespace is ignored as in the parser
// (operatorBlockParts trims), the marker must open the line.
func detailKindOf(line string) string {
	t := strings.TrimSpace(line)
	for _, k := range detailKinds {
		if k == detailOBD {
			// parseOperatorBlockDetails accepts the marker with or without
			// the colon form (`**Operator-Block-Details` prefix).
			if strings.HasPrefix(t, "**"+k) {
				return k
			}
			continue
		}
		if strings.HasPrefix(t, "**"+k+":**") {
			return k
		}
	}
	return ""
}

// isFenceLine reports whether a line opens or closes a fenced code block.
func isFenceLine(line string) bool {
	t := strings.TrimSpace(line)
	return strings.HasPrefix(t, "```") || strings.HasPrefix(t, "~~~")
}

// detailBlocks returns the engine-written detail blocks of body, in order.
// Lines inside a fenced code block are text, never a detail block. A line that
// is also a whole line of the item's own description is the operator's text
// and is skipped (the description is replaced by `update --description`, so
// carrying it would undo the operator's edit). The OBD block runs as far as
// the parser reads it (operatorBlockParts): to the first blank line, sibling
// `**Label:**` line, heading or `---`; a Reopened-Details line takes the
// contiguous attribution bullets after it (isReopenedDetailBullet).
func detailBlocks(body, description string) []detailBlock {
	desc := map[string]bool{}
	for _, ln := range strings.Split(description, "\n") {
		if t := strings.TrimSpace(ln); t != "" {
			desc[t] = true
		}
	}
	lines := strings.Split(body, "\n")
	var out []detailBlock
	inFence := false
	for i := 0; i < len(lines); i++ {
		ln := lines[i]
		if isFenceLine(ln) {
			inFence = !inFence
			continue
		}
		if inFence {
			continue
		}
		k := detailKindOf(ln)
		if k == "" || desc[strings.TrimSpace(ln)] {
			continue
		}
		b := detailBlock{kind: k, lines: []string{strings.TrimRight(ln, "\r")}}
		switch k {
		case detailOBD:
			for j := i + 1; j < len(lines); j++ {
				t := strings.TrimSpace(lines[j])
				if t == "" || (strings.HasPrefix(t, "**") && strings.Contains(t, ":**")) ||
					strings.HasPrefix(t, "## ") || strings.HasPrefix(t, "### ") ||
					strings.HasPrefix(t, "---") || isFenceLine(lines[j]) {
					break
				}
				b.lines = append(b.lines, strings.TrimRight(lines[j], "\r"))
				i = j
			}
		case detailReopened:
			for j := i + 1; j < len(lines) && isReopenedDetailBullet(lines[j]); j++ {
				b.lines = append(b.lines, strings.TrimRight(lines[j], "\r"))
				i = j
			}
		}
		out = append(out, b)
	}
	return out
}

// supersedes returns the set of kinds a write replaces itself.
func supersedes(kinds ...string) map[string]bool {
	m := map[string]bool{}
	for _, k := range kinds {
		m[k] = true
	}
	return m
}

// carryDetailBlocks returns newBody with every detail block of oldBody that
// newBody lacks inserted after its `**Type:**` line, in the old order. Kinds
// in replaced are not carried (the write wrote its own). A block newBody
// already holds verbatim is not added twice.
func carryDetailBlocks(oldBody, newBody, description string, replaced map[string]bool) string {
	var missing []string
	have := detailBlocks(newBody, "")
	for _, b := range detailBlocks(oldBody, description) {
		if replaced[b.kind] || containsBlock(have, b) {
			continue
		}
		missing = append(missing, b.text())
	}
	if len(missing) == 0 {
		return newBody
	}
	return insertMetaLine(newBody, strings.Join(missing, "\n"))
}

func containsBlock(bs []detailBlock, b detailBlock) bool {
	for _, x := range bs {
		if x.kind == b.kind && x.text() == b.text() {
			return true
		}
	}
	return false
}

// detailLossProblems is the gate: every detail block of oldBody that the write
// does not replace must still be a detail block of newBody, verbatim, and,
// when the block record is not replaced, the operator_block_details source the
// next md-to-db reads must be unchanged (operatorBlockSource, the comparison
// obdSnapshot keeps the stored row by).
func detailLossProblems(oldBody, newBody, description string, replaced map[string]bool) []string {
	var probs []string
	have := detailBlocks(newBody, "")
	engineOBD := false
	for _, b := range detailBlocks(oldBody, description) {
		if b.kind == detailOBD || b.kind == detailChoices {
			engineOBD = true
		}
		if replaced[b.kind] || containsBlock(have, b) {
			continue
		}
		probs = append(probs, fmt.Sprintf("the write would drop the engine-written %s line %q", b.kind, b.lines[0]))
	}
	// The record source is judged only when the old body carries an
	// engine-written block record (a block line that is the operator's own
	// description text is the operator's to replace).
	if engineOBD && !replaced[detailOBD] && !replaced[detailChoices] {
		oldSrc, ook := operatorBlockSource(oldBody)
		newSrc, nok := operatorBlockSource(newBody)
		if ook != nok || oldSrc != newSrc {
			probs = append(probs, "the write would change the Operator-Block-Details record the next sync md-to-db reads (operator_block_details, §11.4.148 D3)")
		}
	}
	return probs
}
