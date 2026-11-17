package main

// CON-456 round 6 (follow-up found while fixing review r5 F1): a `## ` heading
// line inside a fenced code block is quoted text. parseIssues and parseFixed cut
// item blocks at the next `## ` line and recognised item headings without
// looking at fences, so a quoted `## ID — title` plus a Status line inside an
// item's description minted a phantom item and truncated the real one.

import (
	"strings"
	"testing"
)

// docHeadingForms is the class: every heading form the two parsers recognise.
var docHeadingForms = []struct{ name, heading string }{
	{"canonical", "## CON-901 — Quoted example"},
	{"atm-shape2-bracket", "## [ATM-901] Quoted example"},
	{"atm-shape1-code", "## GO. Quoted example"},
	{"atm-shape3-section", "## §A1 Quoted example"},
}

func r6DocParsers() map[string]func(string) ([]item, []segment) {
	return map[string]func(string) ([]item, []segment){"parseIssues": parseIssues, "parseFixed": parseFixed}
}

func TestCON456R6_FencedHeadingInsideItemMintsNoPhantomItem(t *testing.T) {
	for pn, parse := range r6DocParsers() {
		for _, f := range docHeadingForms {
			for _, fence := range []string{"```", "~~~~"} {
				doc := "# Doc\n\n## CON-100 — Real item\n\n**Status:** Queued\n**Type:** Task\n\nExample:\n\n" +
					fence + "\n" + f.heading + "\n\n**Status:** Queued\n**Type:** Task\n" + fence + "\n\nafter the example\n\n" +
					"## CON-101 — Second item\n\n**Status:** Queued\n**Type:** Task\n\ntext\n"
				items, _ := parse(doc)
				if len(items) != 2 {
					t.Errorf("%s/%s/%s: %d items, want 2 (a quoted heading minted an item)", pn, f.name, fence, len(items))
					continue
				}
				if items[0].AtmID != "CON-100" || !strings.Contains(items[0].BodyMD, "after the example") || !strings.Contains(items[0].BodyMD, f.heading) {
					t.Errorf("%s/%s/%s: the real item was cut at the quoted heading:\n%s", pn, f.name, fence, items[0].BodyMD)
				}
			}
		}
	}
}

func TestCON456R6_FencedHeadingInRawProseMintsNoItem(t *testing.T) {
	for pn, parse := range r6DocParsers() {
		for _, f := range docHeadingForms {
			doc := "# Doc\n\nHow to write an entry:\n\n```\n" + f.heading + "\n\n**Status:** Queued\n```\n\n## CON-100 — Real item\n\n**Status:** Queued\n**Type:** Task\n\ntext\n"
			items, _ := parse(doc)
			if len(items) != 1 || items[0].AtmID != "CON-100" {
				t.Errorf("%s/%s: items=%d, want only CON-100", pn, f.name, len(items))
			}
		}
	}
}

// golden-FALSE: unfenced headings still start items, an UNTERMINATED stray fence
// does not hide the next real item, and a longer fence is closed only by an
// equal or longer run.
func TestCON456R6_FencedHeadingGoldenFalse(t *testing.T) {
	for pn, parse := range r6DocParsers() {
		plain := "## CON-100 — A\n\n**Status:** Queued\n\n## CON-101 — B\n\n**Status:** Queued\n"
		if items, _ := parse(plain); len(items) != 2 {
			t.Errorf("%s: plain two items -> %d", pn, len(items))
		}
		stray := "## CON-100 — A\n\n**Status:** Queued\n\n```\nstray fence never closed\n\n## CON-101 — B\n\n**Status:** Queued\n"
		if items, _ := parse(stray); len(items) != 2 {
			t.Errorf("%s: an unterminated fence hid the next item (%d items)", pn, len(items))
		}
		longer := "## CON-100 — A\n\n**Status:** Queued\n\n````\n```\n## CON-999 — quoted\n\n**Status:** Queued\n````\n\n## CON-101 — B\n\n**Status:** Queued\n"
		if items, _ := parse(longer); len(items) != 2 {
			t.Errorf("%s: a shorter run closed a longer fence (%d items)", pn, len(items))
		}
	}
}

// Byte round trip: item bodies + raw segments reassemble the source.
func TestCON456R6_FencedHeadingKeepsByteRoundTrip(t *testing.T) {
	doc := "# Doc\n\n## CON-100 — Real\n\n**Status:** Queued\n\n```\n## CON-999 — quoted\n\n**Status:** Fixed\n```\n\ntail\n"
	items, _ := parseIssues(doc)
	if len(items) != 1 || items[0].BodyMD != strings.TrimPrefix(doc, "# Doc\n\n") {
		t.Errorf("body not the verbatim block: %d items", len(items))
	}
}

// The legacy pipe-table closure row is the third item-shaped form parseFixed
// recognises; a row quoted inside a fenced block is text, not an item.
func TestCON456R6_FencedLegacyTableRowMintsNoItem(t *testing.T) {
	row := "| 2026-01-02 | CON-900 quoted example | a | b | c | d | e |"
	doc := "# Fixed\n\nExample row:\n\n```\n" + row + "\n```\n\n" + row + "\n"
	items, _ := parseFixed(doc)
	if len(items) != 1 {
		t.Fatalf("%d items, want 1 (only the unfenced row)", len(items))
	}
}
