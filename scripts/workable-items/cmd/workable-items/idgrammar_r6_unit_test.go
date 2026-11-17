package main

// CON-456 round 6: unit tests of ownlines.go (the one definition of the item's own line).

import (
	"strings"
	"testing"
)

// F1: the metadata-block finder, the state anchor and the owned-line gate use
// the same Status line as the parser (one definition of the item's own line).
func TestCON456R6_OneDefinitionOfTheOwnStatusLine(t *testing.T) {
	body := "## CON-1 — t\n\n**Status:** Queued\n**Type:** Task\n\nprose\n\n```\n**Status:** Fixed\n**Type:** Bug\n```\n"
	lines := splitKeepNewlines(body)
	m := metaBlockOf(lines)
	if m.start != 2 || m.end != 4 || m.typeIdx != 3 {
		t.Errorf("metaBlockOf = %+v, want the block [2,4) with Type at 3", m)
	}
	r := newOwnRegion(lines)
	if i := r.statusIdx(); i != 2 {
		t.Errorf("statusIdx = %d, want 2", i)
	}
	// The status canonicalizer writes the same line the parser reads.
	out := canonicalizeBodyStatusLine(strings.Replace(body, "**Status:** Fixed", "**Status:** Queued", 1), "In progress")
	if !strings.Contains(out, "**Status:** In progress\n**Type:** Task") || !strings.Contains(out, "```\n**Status:** Queued\n") {
		t.Errorf("canonicalizeBodyStatusLine wrote the wrong line:\n%s", out)
	}
	// The gate does not see a rewrite of the fenced line as the owned line.
	bad := strings.Replace(body, "```\n**Status:** Fixed", "```\n**Status:** Queued", 1)
	if p := ownedLinesProblems(body, bad, bodyOwnership{status: true}, "", ""); len(p) == 0 {
		t.Error("the gate accepted a rewrite of a fenced Status line")
	}
	good := strings.Replace(body, "**Status:** Queued\n**Type:** Task", "**Status:** Fixed\n**Type:** Task", 1)
	if p := ownedLinesProblems(body, good, bodyOwnership{status: true}, "", ""); len(p) != 0 {
		t.Errorf("golden-FALSE: the gate refused the own Status line: %v", p)
	}
}

// F1: an unterminated fence is not a fence, and a fence is closed
// only by the same marker (a tilde line does not close a backtick fence).
func TestCON456R6_FenceMask(t *testing.T) {
	cases := []struct {
		name  string
		lines []string
		want  []bool
	}{
		{"plain", []string{"a\n", "```\n", "b\n", "```\n", "c\n"}, []bool{false, true, true, true, false}},
		{"tilde does not close backtick", []string{"```\n", "~~~\n", "x\n", "```\n", "y\n"}, []bool{true, true, true, true, false}},
		{"unterminated is not a fence", []string{"a\n", "```\n", "b\n"}, []bool{false, false, false}},
		{"shorter run does not close", []string{"````\n", "x\n", "```\n", "y\n", "````\n", "z\n"}, []bool{true, true, true, true, true, false}},
		{"longer closes", []string{"```\n", "x\n", "````\n", "y\n"}, []bool{true, true, true, false}},
		{"info string opens, not closes", []string{"```go\n", "x\n", "```go\n", "y\n", "```\n", "z\n"}, []bool{true, true, true, true, true, false}},
	}
	for _, c := range cases {
		got := fencedMask(c.lines)
		for i := range c.want {
			if got[i] != c.want[i] {
				t.Errorf("%s: line %d fenced=%v want %v", c.name, i, got[i], c.want[i])
			}
		}
	}
}

// A stray fence line never turns the item's real Status line into text.
func TestCON456R6_StrayFenceDoesNotHideTheOwnStatus(t *testing.T) {
	body := "## CON-1 — a probe item with a long enough title for the floor\n\nprose\n\n```\nstray\n\n**Status:** In progress\n"
	it := buildItem("CON-1", "a probe item with a long enough title for the floor", body, "Issues")
	if it.Status != "In progress" {
		t.Errorf("status = %q: a stray fence hid the own Status line", it.Status)
	}
}
