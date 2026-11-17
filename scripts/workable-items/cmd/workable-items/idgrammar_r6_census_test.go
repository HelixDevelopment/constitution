package main

// CON-456 round 6: closed census of the class "a function that reads or writes
// an item's own Status / Type / Severity / Reproduction / Investigation /
// Unblock-Choices / Operator-Block-Details line" (sections 11.4.273 and
// 11.4.276(C)). Each member must get its lines through the shared fence-aware
// definition (ownlines.go), or be listed in r6OwnLineExempt with its reason.
// The instrument is control-needled: it must find the known members, find
// nothing for a fabricated marker, flag a synthetic member that scans lines
// itself and pass one that uses the shared helpers.

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// r6Markers are the strings that name an own-line scan in Go source.
var r6Markers = []string{
	`"**Status:**"`, `"**Type:**"`, `"**Severity:**"`, `"**Operator-Block-Details`,
	`"**Unblock-Choices`, `metaLineRe`, `reproLinePrefix`, `invLinePrefix`,
}

// r6Shared are the names whose presence in a function means it gets its lines
// from the shared definition.
var r6Shared = []string{"newOwnRegion(", "itemOwnMetaRegion(", "blankFenced(", "fencedMask(", "metaBlockOf(", "parseStateLines(", "stateAnchor("}

// r6OwnLineExempt lists functions that name a marker without scanning a body
// for an own line, each with the reason.
var r6OwnLineExempt = map[string]string{
	"renderItemBody":          "generates a new body; it reads no body",
	"renderReproLine":         "renders a record from columns",
	"renderInvestigationLine": "renders a record from columns",
	"operatorBlockLine":       "renders the block record from arguments",
	"recordKindOf":            "classifies ONE line the caller selected from the metadata block",
	"isReopenedDetailBullet":  "classifies ONE line the caller selected",
	"deriveDescription":       "picks the first prose line; a metadata-looking line is skipped, a fenced one is skipped or kept as prose, never read as a field",
	"normalizeType":           "maps a value, reads no body",
	"upsertMetaLine":          "record kinds go through setRecord; other keys through the shared own region (newOwnRegion in the same function body)",
	"parseReproRemainder":     "parses the text after a record prefix the caller selected",
	"parseInvRemainder":       "parses the text after a record prefix the caller selected",
	"reproLabel":              "maps a state to a label",
	"statusIdx":               "the shared definition itself (ownlines.go)",
	"describeStates":          "renders a human text from a record, reads no body",
}

var r6FuncRe = regexp.MustCompile(`(?m)^func (?:\([^)]*\) )?([A-Za-z0-9_]+)\(`)

// r6Census returns the functions of src that name an own-line marker and the
// subset that neither use a shared helper nor are exempt.
func r6Census(src string, exempt map[string]string) (members, flagged []string) {
	locs := r6FuncRe.FindAllStringSubmatchIndex(src, -1)
	for i, l := range locs {
		end := len(src)
		if i+1 < len(locs) {
			end = locs[i+1][0]
		}
		name := src[l[2]:l[3]]
		body := src[l[0]:end]
		// Strip line comments so a marker in prose does not count.
		var code []string
		for _, ln := range strings.Split(body, "\n") {
			if j := strings.Index(ln, "//"); j >= 0 && !strings.Contains(ln[:j], `"`) {
				ln = ln[:j]
			}
			code = append(code, ln)
		}
		text := strings.Join(code, "\n")
		hit := false
		for _, m := range r6Markers {
			if strings.Contains(text, m) {
				hit = true
				break
			}
		}
		if !hit {
			continue
		}
		members = append(members, name)
		shared := false
		for _, s := range r6Shared {
			if strings.Contains(text, s) {
				shared = true
				break
			}
		}
		if _, ok := exempt[name]; !shared && !ok {
			flagged = append(flagged, name)
		}
	}
	return members, flagged
}

func TestCON456R6_OwnLineScansUseTheSharedDefinition(t *testing.T) {
	// Instrument self-test (golden-bad, golden-good, fabricated marker).
	bad := "func scanOwn(lines []string) int {\n\tfor i, l := range lines {\n\t\tif strings.HasPrefix(l, \"**Status:**\") {\n\t\t\treturn i\n\t\t}\n\t}\n\treturn -1\n}\n"
	good := "func scanOwn(lines []string) int {\n\tr := newOwnRegion(lines)\n\treturn r.lastIdx(\"**Status:**\")\n}\n"
	if m, f := r6Census(bad, nil); len(m) != 1 || len(f) != 1 {
		t.Fatalf("self-test golden-bad: members %v flagged %v", m, f)
	}
	if m, f := r6Census(good, nil); len(m) != 1 || len(f) != 0 {
		t.Fatalf("self-test golden-good: members %v flagged %v", m, f)
	}
	if m, _ := r6Census(strings.ReplaceAll(bad, "**Status:**", "**Nonexistent-Marker:**"), nil); len(m) != 0 {
		t.Fatalf("self-test negative control: a fabricated marker found members %v", m)
	}
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) == 0 {
		t.Fatalf("no source files: %v", err)
	}
	var all, flagged []string
	for _, f := range files {
		if strings.HasSuffix(f, "_test.go") {
			continue
		}
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		m, fl := r6Census(string(b), r6OwnLineExempt)
		for _, x := range m {
			all = append(all, f+":"+x)
		}
		for _, x := range fl {
			flagged = append(flagged, f+":"+x)
		}
	}
	sort.Strings(all)
	// Positive control: the known members are in the census.
	for _, want := range []string{"parse.go:buildItem", "states.go:parseStateLines",
		"idgrammar.go:setOwnMetaLine", "bodypatch.go:metaBlockOf", "parse.go:lastBodyStatus", "mutate.go:insertMetaLine", "parse.go:operatorBlockParts"} {
		found := false
		for _, a := range all {
			if a == want {
				found = true
			}
		}
		if !found {
			t.Errorf("control: the census did not find the known member %s (instrument blind); members: %v", want, all)
		}
	}
	if len(flagged) > 0 {
		t.Errorf("functions that scan an own-line marker without the shared fence-aware definition (ownlines.go) and are not exempt: %v", flagged)
	}
	t.Logf("census: %d members, %d flagged", len(all), len(flagged))
}
