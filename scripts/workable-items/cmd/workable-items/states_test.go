// states_test.go — unit, golden, round-trip property and negative-control
// coverage for the §11.4.292 reproduction / investigation records (states.go).
//
// Pure-function tests: no DB except the schema-CHECK pin. The CLI / DB paths are
// covered by states_cli_test.go. Paired mutations: scripts/workable-items/
// mutation/states_mutation_runner.sh applies each mutant to a copy of this
// package and requires `go test -run 'TestStates'` to FAIL.
package main

import (
	"database/sql"
	"fmt"
	"math/rand"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// ---- closed sets ------------------------------------------------------------

// TestStates_ClosedSetsPinned pins the vocabularies to the §11.4.292 draft
// literally, so adding, dropping or renaming a value anywhere is a test change.
func TestStates_ClosedSetsPinned(t *testing.T) {
	wantRepro := []string{"UNSET", "UNREPRODUCED", "reproduced-live", "reproduced-host-fixture",
		"not-reproducible-with-evidence", "blocked-no-device-with-recorded-blocker"}
	wantInv := []string{"UNSET", "not-started", "in-progress", "root-cause-found-with-evidence",
		"root-cause-unconfirmed", "closed-no-defect"}
	if !reflect.DeepEqual(reproStates, wantRepro) {
		t.Errorf("reproStates = %v, want %v", reproStates, wantRepro)
	}
	if !reflect.DeepEqual(investigationStates, wantInv) {
		t.Errorf("investigationStates = %v, want %v", investigationStates, wantInv)
	}
	if !reflect.DeepEqual(reproSurfaces, []string{"live-target", "host-only"}) {
		t.Errorf("reproSurfaces = %v", reproSurfaces)
	}
	if !reflect.DeepEqual(reproClosureAllowed, []string{"reproduced-live", "reproduced-host-fixture",
		"not-reproducible-with-evidence", "blocked-no-device-with-recorded-blocker"}) {
		t.Errorf("reproClosureAllowed = %v", reproClosureAllowed)
	}
	if got, ok := normalizeReproStateInput(" blocked-no-device "); !ok || got != reproBlocked {
		t.Errorf("alias blocked-no-device -> %q ok=%v, want %q", got, ok, reproBlocked)
	}
	for _, bad := range []string{"", "reproduced", "VERIFIED", "unset", "Reproduced-Live"} {
		if _, ok := normalizeReproStateInput(bad); ok && bad != "" {
			t.Errorf("normalizeReproStateInput(%q) accepted", bad)
		}
		if _, ok := normalizeInvStateInput(bad); ok && bad != "" {
			t.Errorf("normalizeInvStateInput(%q) accepted", bad)
		}
	}
}

var checkListRe = map[string]*regexp.Regexp{
	"reproduction_state":   regexp.MustCompile(`reproduction_state\s+IN\s*\(([^)]*)\)`),
	"investigation_state":  regexp.MustCompile(`investigation_state\s+IN\s*\(([^)]*)\)`),
	"reproduction_surface": regexp.MustCompile(`reproduction_surface\s+IN\s*\(([^)]*)\)`),
}

func checkListValues(t *testing.T, tableSQL, col string) []string {
	t.Helper()
	m := checkListRe[col].FindStringSubmatch(tableSQL)
	if m == nil {
		t.Fatalf("no CHECK (%s IN (...)) in items DDL:\n%s", col, tableSQL)
	}
	var out []string
	for _, v := range strings.Split(m[1], ",") {
		v = strings.TrimSpace(v)
		out = append(out, strings.Trim(v, "'"))
	}
	return out
}

func sortedCopy(s []string) []string {
	c := append([]string(nil), s...)
	sort.Strings(c)
	return c
}

// TestStates_SchemaCheckMatchesGoClosedSets pins the SQLite CHECK lists to the Go
// closed sets on BOTH paths: a fresh DB (schema_embed.sql CREATE TABLE) and a
// pre-v8 DB migrated by migrateStatesColumns (ALTER TABLE ADD COLUMN). It also
// proves the CHECK is live (a value outside the set is rejected).
func TestStates_SchemaCheckMatchesGoClosedSets(t *testing.T) {
	fresh := filepath.Join(t.TempDir(), "fresh.db")
	for name, path := range map[string]string{"fresh": fresh, "migrated-v5": makeV5LikeDB(t)} {
		db, err := openDB(path)
		if err != nil {
			t.Fatalf("%s: openDB: %v", name, err)
		}
		var ddl string
		if err := db.QueryRow(`SELECT sql FROM sqlite_master WHERE type='table' AND name='items'`).Scan(&ddl); err != nil {
			t.Fatalf("%s: read items DDL: %v", name, err)
		}
		for col, want := range map[string][]string{
			"reproduction_state":   reproStates,
			"investigation_state":  investigationStates,
			"reproduction_surface": reproSurfaces,
		} {
			if got := checkListValues(t, ddl, col); !reflect.DeepEqual(sortedCopy(got), sortedCopy(want)) {
				t.Errorf("%s: CHECK %s = %v, Go closed set = %v", name, col, got, want)
			}
		}
		assertStateCheckLive(t, name, db)
		db.Close()
	}
}

func assertStateCheckLive(t *testing.T, name string, db *sql.DB) {
	t.Helper()
	if _, err := db.Exec(`INSERT INTO items (atm_id, title, description, type, status, current_location, representation)
		VALUES ('CHK-1','check probe','schema CHECK probe row','Bug','Queued','Issues','section')`); err != nil {
		t.Fatalf("%s: seed probe row: %v", name, err)
	}
	for _, v := range reproStates {
		if _, err := db.Exec(`UPDATE items SET reproduction_state=? WHERE atm_id='CHK-1'`, v); err != nil {
			t.Errorf("%s: CHECK rejected closed-set reproduction_state %q: %v", name, v, err)
		}
	}
	for _, v := range investigationStates {
		if _, err := db.Exec(`UPDATE items SET investigation_state=? WHERE atm_id='CHK-1'`, v); err != nil {
			t.Errorf("%s: CHECK rejected closed-set investigation_state %q: %v", name, v, err)
		}
	}
	for col, bad := range map[string]string{"reproduction_state": "VERIFIED", "investigation_state": "done", "reproduction_surface": "somewhere"} {
		if _, err := db.Exec(`UPDATE items SET `+col+`=? WHERE atm_id='CHK-1'`, bad); err == nil {
			t.Errorf("%s: CHECK accepted %s=%q (constraint is not live)", name, col, bad)
		}
	}
	if _, err := db.Exec(`DELETE FROM items WHERE atm_id='CHK-1'`); err != nil {
		t.Fatalf("%s: delete probe: %v", name, err)
	}
}

// ---- golden rendering -------------------------------------------------------

func completeLive() stateRecord {
	return stateRecord{
		ReproState: reproLive, ReproSurface: surfaceLiveTarget,
		ReproEvidence: "qa-results/x/red.txt", ReproRedCmd: "bash scripts/red.sh --board D2",
		ReproGreenCmd: "bash scripts/red.sh --board D2", ReproEnv: "D2 serial 1234; image 1.0.0-dev-0.3.5",
		ReproSignature: "rc=1 and `frame-size 0` in logcat", ReproUpdatedAt: "2026-11-03T10:00:00Z", ReproUpdatedBy: "conductor",
		InvState: invRootCauseFound, InvRootCause: "start_threshold 0 — divide by zero", InvEvidence: "qa-results/x/rca.md",
		InvUpdatedAt: "2026-11-03T10:05:00Z", InvUpdatedBy: "agent-b",
	}
}

// TestStates_RenderGolden pins the exact Markdown of each record shape and its
// parse back.
func TestStates_RenderGolden(t *testing.T) {
	cases := []struct {
		name      string
		rec       stateRecord
		repro     string
		inv       string
		reproCell string
	}{
		{"unset", stateRecord{}, "", "", "UNSET"},
		{"unreproduced-plan", stateRecord{ReproState: reproUnreproduced, ReproRedCmd: "bash t.sh", ReproSignature: "rc=1"},
			"**Reproduction:** none — UNREPRODUCED — red-command `bash t.sh` — signature `rc=1`", "", "none — UNREPRODUCED"},
		{"live-complete", completeLive(),
			"**Reproduction:** reproduced-live — REPRODUCED — surface live-target — evidence `qa-results/x/red.txt` — red-command `bash scripts/red.sh --board D2` — green-command `bash scripts/red.sh --board D2` — env `D2 serial 1234; image 1.0.0-dev-0.3.5` — signature ``rc=1 and `frame-size 0` in logcat`` — updated 2026-11-03T10:00:00Z — by `conductor`",
			"**Investigation:** root-cause-found-with-evidence — root-cause `start_threshold 0 — divide by zero` — evidence `qa-results/x/rca.md` — updated 2026-11-03T10:05:00Z — by `agent-b`",
			"reproduced-live — REPRODUCED"},
		{"fixture-missing-env", stateRecord{ReproState: reproHostFixture, ReproSurface: surfaceHostOnly, ReproEvidence: "e.txt", ReproRedCmd: "go test", ReproSignature: "FAIL"},
			"**Reproduction:** reproduced-host-fixture — UNREPRODUCED — surface host-only — evidence `e.txt` — red-command `go test` — signature `FAIL`", "",
			"reproduced-host-fixture — UNREPRODUCED (missing env)"},
		{"blocked", stateRecord{ReproState: reproBlocked, ReproBlocker: "needs: D2; missing: capture", InvState: invNotStarted},
			"**Reproduction:** blocked-no-device-with-recorded-blocker — UNREPRODUCED — blocker `needs: D2; missing: capture`",
			"**Investigation:** not-started", "blocked-no-device-with-recorded-blocker — UNREPRODUCED"},
		{"backtick-edges", stateRecord{ReproState: reproNotReproducible, ReproEvidence: "`odd` name", ReproSignature: "ends with `"},
			"**Reproduction:** not-reproducible-with-evidence — UNREPRODUCED — evidence `` `odd` name `` — signature `` ends with ` ``", "",
			"not-reproducible-with-evidence — UNREPRODUCED"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := renderReproLine(c.rec); got != c.repro {
				t.Errorf("renderReproLine:\n got %s\nwant %s", got, c.repro)
			}
			if got := renderInvestigationLine(c.rec); got != c.inv {
				t.Errorf("renderInvestigationLine:\n got %s\nwant %s", got, c.inv)
			}
			if got := reproSummaryCell(c.rec); got != c.reproCell {
				t.Errorf("reproSummaryCell = %q, want %q", got, c.reproCell)
			}
			body := "## WIT-1 — golden\n\n**Status:** Queued\n"
			if c.repro != "" {
				body += c.repro + "\n"
			}
			if c.inv != "" {
				body += c.inv + "\n"
			}
			p := parseStateLines(body)
			if len(p.problems) > 0 {
				t.Fatalf("golden body has problems: %v", p.problems)
			}
			if p.rec != c.rec.norm() {
				t.Errorf("parse(golden) = %+v\nwant %+v", p.rec, c.rec.norm())
			}
		})
	}
}

// TestStates_LabelRules pins §11.4.292(B)/(C): REPRODUCED needs every required
// field, no UNCONFIRMED value, and a fixture is not a live-target reproduction.
func TestStates_LabelRules(t *testing.T) {
	full := completeLive()
	if l, why := reproLabel(full); l != labelReproduced || why != nil {
		t.Fatalf("complete live record labelled %s %v, want REPRODUCED", l, why)
	}
	for _, field := range []string{"surface", "evidence", "red-command", "env", "signature"} {
		r := full
		switch field {
		case "surface":
			r.ReproSurface = ""
		case "evidence":
			r.ReproEvidence = ""
		case "red-command":
			r.ReproRedCmd = ""
		case "env":
			r.ReproEnv = ""
		case "signature":
			r.ReproSignature = ""
		}
		l, why := reproLabel(r)
		if l != labelUnreproduced || !strings.Contains(strings.Join(why, ";"), "missing "+field) {
			t.Errorf("record without %s labelled %s %v, want UNREPRODUCED (missing %s)", field, l, why, field)
		}
	}
	r := full
	r.ReproEnv = "UNCONFIRMED: board serial not captured"
	if l, _ := reproLabel(r); l != labelUnreproduced {
		t.Errorf("UNCONFIRMED env labelled %s, want UNREPRODUCED", l)
	}
	r = full
	r.ReproState = reproHostFixture
	if l, why := reproLabel(r); l != labelUnreproduced || !strings.Contains(strings.Join(why, ";"), "live-target") {
		t.Errorf("host fixture on a live-target surface labelled %s %v, want UNREPRODUCED", l, why)
	}
	r.ReproSurface = surfaceHostOnly
	if l, _ := reproLabel(r); l != labelReproduced {
		t.Errorf("complete host-only fixture labelled %s, want REPRODUCED", l)
	}
	for _, st := range []string{reproUnreproduced, reproNotReproducible, reproBlocked} {
		r := full
		r.ReproState = st
		if l, _ := reproLabel(r); l != labelUnreproduced {
			t.Errorf("%s labelled %s, want UNREPRODUCED", st, l)
		}
	}
	if l, _ := reproLabel(stateRecord{}); l != "" {
		t.Errorf("UNSET labelled %q, want none", l)
	}
}

// ---- code spans ---------------------------------------------------------------

func TestStates_CodeSpanRoundTrip(t *testing.T) {
	for _, v := range []string{"a", "x — y", "`", "``", "a`b", "a``b`c", "`lead", "trail`", "` both `",
		"| pipe | cell |", "**bold**", "tab\there", "ünïcødé — ✓", "a — b — c", "```fence```"} {
		enc := encodeCodeSpan(v)
		got, rest, err := decodeCodeSpan(enc + " — tail")
		if err != nil || got != v || rest != " — tail" {
			t.Errorf("code span %q -> %q -> (%q, %q, %v)", v, enc, got, rest, err)
		}
	}
	for _, bad := range []string{"plain", "`unterminated", "``", "`` x`", "` `"} {
		if _, _, err := decodeCodeSpan(bad); err == nil {
			t.Errorf("decodeCodeSpan(%q) accepted a malformed span", bad)
		}
	}
}

// ---- round-trip property ------------------------------------------------------

var propBodies = []struct {
	name string
	body string
}{
	{"status-block", "## WIT-1 — t\n\n**Status:** Queued\n**Type:** Bug\n**Severity:** High\n\nProse paragraph.\n"},
	{"no-status", "## WIT-1 — t\n\nProse only, no meta.\n"},
	{"legacy-prose", "## WIT-1 — t\n\n**Status:** Queued\n**Reproduction:** reproduced by hand on D2, see the log\n**Investigation:** see the write-up\n\nProse.\n"},
	{"sub-item", "## WIT-1 — t\n\n**Status:** Queued\n\n### WIT-1.a — sub\n\n**Reproduction:** none — UNREPRODUCED\n**Status:** Queued\n"},
	{"no-trailing-newline", "## WIT-1 — t\n**Status:** Queued"},
	{"multiline-block", "## WIT-1 — t\n\n**Status:** Operator-blocked\n**Operator-Block-Details:** WHAT: x\n  - WHY: y\n  - UNBLOCK: z\n\nProse.\n\n---\n"},
	{"existing-record", "## WIT-1 — t\n\n**Status:** Queued\n**Reproduction:** none — UNREPRODUCED — signature `old`\n**Investigation:** in-progress\n\nProse.\n"},
}

const propAlphabet = "abcXYZ019 `—|*_/.:-é✓()"

func randValue(rng *rand.Rand) string {
	for {
		n := 1 + rng.Intn(14)
		var b strings.Builder
		runes := []rune(propAlphabet)
		for i := 0; i < n; i++ {
			if rng.Intn(6) == 0 {
				b.WriteString(" — ")
				continue
			}
			b.WriteRune(runes[rng.Intn(len(runes))])
		}
		v := strings.TrimSpace(b.String())
		if v != "" {
			return v
		}
	}
}

func randTimestamp(rng *rand.Rand) string {
	return fmt.Sprintf("2026-%02d-%02dT%02d:%02d:%02dZ", 1+rng.Intn(12), 1+rng.Intn(28), rng.Intn(24), rng.Intn(60), rng.Intn(60))
}

func randRecord(rng *rand.Rand) stateRecord {
	var r stateRecord
	r.ReproState = reproStates[rng.Intn(len(reproStates))]
	r.InvState = investigationStates[rng.Intn(len(investigationStates))]
	maybe := func() string {
		if rng.Intn(3) == 0 {
			return ""
		}
		return randValue(rng)
	}
	if r.ReproState != stateUnset {
		if rng.Intn(3) > 0 {
			r.ReproSurface = reproSurfaces[rng.Intn(len(reproSurfaces))]
		}
		r.ReproEvidence, r.ReproRedCmd, r.ReproGreenCmd = maybe(), maybe(), maybe()
		r.ReproEnv, r.ReproSignature, r.ReproBlocker, r.ReproUpdatedBy = maybe(), maybe(), maybe(), maybe()
		if rng.Intn(2) == 0 {
			r.ReproUpdatedAt = randTimestamp(rng)
		}
	}
	if r.InvState != stateUnset {
		r.InvRootCause, r.InvEvidence, r.InvUpdatedBy = maybe(), maybe(), maybe()
		if rng.Intn(2) == 0 {
			r.InvUpdatedAt = randTimestamp(rng)
		}
	}
	return r.norm()
}

// stripRecordLines removes exactly the rendered record lines of r from the
// item's own meta region (a sub-item's identical line is not the item's).
func stripRecordLines(body string, r stateRecord) string {
	lines := splitKeepNewlines(body)
	limit := ownMetaRegionLineCount(lines)
	var out []string
	for i, l := range lines {
		t := strings.TrimRight(l, "\n")
		if i < limit && t != "" && (t == renderReproLine(r) || t == renderInvestigationLine(r)) {
			continue
		}
		out = append(out, l)
	}
	return ensureTrailingNewline(strings.Join(out, ""))
}

// TestStates_RoundTripProperty: for random records r1, r2 over every base body
// shape — parse(canonicalize(b, r)) == r; canonicalize is idempotent; it is the
// identity on parse(b); and every non-record line is preserved.
func TestStates_RoundTripProperty(t *testing.T) {
	for seed := int64(1); seed <= 8; seed++ {
		rng := rand.New(rand.NewSource(seed))
		for i := 0; i < 250; i++ {
			for _, pb := range propBodies {
				base := pb.body
				p0 := parseStateLines(base)
				if len(p0.problems) > 0 {
					t.Fatalf("[%s] base body has problems: %v", pb.name, p0.problems)
				}
				if got := canonicalizeStateLines(base, p0.rec, "section"); got != base {
					t.Fatalf("[%s] canonicalize(b, parse(b)) is not the identity:\n%s", pb.name, firstDiff(base, got))
				}
				r1, r2 := randRecord(rng), randRecord(rng)
				if err := checkRecordFormats(r1); err != nil {
					t.Fatalf("generator produced an invalid record: %v", err)
				}
				b1 := canonicalizeStateLines(base, r1, "section")
				p1 := parseStateLines(b1)
				if len(p1.problems) > 0 || p1.rec != r1 {
					t.Fatalf("seed %d [%s] parse(canon(b, r1)) mismatch\nproblems %v\n got %+v\nwant %+v\nbody:\n%s", seed, pb.name, p1.problems, p1.rec, r1, b1)
				}
				if again := canonicalizeStateLines(b1, r1, "section"); again != b1 {
					t.Fatalf("seed %d [%s] canonicalize not idempotent:\n%s", seed, pb.name, firstDiff(b1, again))
				}
				b2 := canonicalizeStateLines(b1, r2, "section")
				if p2 := parseStateLines(b2); len(p2.problems) > 0 || p2.rec != r2 {
					t.Fatalf("seed %d [%s] parse(canon(canon(b, r1), r2)) mismatch\n got %+v\nwant %+v\nbody:\n%s", seed, pb.name, p2.rec, r2, b2)
				}
				if stripRecordLines(b2, r2) != stripRecordLines(base, p0.rec) {
					t.Fatalf("seed %d [%s] non-record lines changed:\n%s", seed, pb.name, firstDiff(stripRecordLines(base, p0.rec), stripRecordLines(b2, r2)))
				}
				b3 := canonicalizeStateLines(b2, stateRecord{}, "section")
				if p3 := parseStateLines(b3); p3.rec != (stateRecord{}).norm() {
					t.Fatalf("seed %d [%s] clearing to UNSET left %+v", seed, pb.name, p3.rec)
				}
			}
		}
	}
}

// ---- negative controls ----------------------------------------------------------

// TestStates_LegacyProseIsNeverInterpreted: free-form `**Reproduction:**` lines
// set no state, raise no problem, and survive canonicalization untouched.
func TestStates_LegacyProseIsNeverInterpreted(t *testing.T) {
	for _, line := range []string{
		"**Reproduction:** reproduced on D2 by the operator",
		"**Reproduction:** none observed so far",
		"**Reproduction:**",
		"**Reproduction:**reproduced-live — REPRODUCED",
		"**Investigation:** root cause is the mixer",
		"**Investigation:** in progress (see notes)",
	} {
		body := "## WIT-1 — t\n\n**Status:** Queued\n" + line + "\n\nProse.\n"
		p := parseStateLines(body)
		if len(p.problems) > 0 || p.rec != (stateRecord{}).norm() {
			t.Errorf("legacy line %q parsed as %+v problems %v", line, p.rec, p.problems)
		}
		if got := canonicalizeStateLines(body, stateRecord{}, "section"); got != body {
			t.Errorf("legacy line %q rewritten:\n%s", line, firstDiff(body, got))
		}
		r := stateRecord{ReproState: reproUnreproduced, InvState: invNotStarted}
		got := canonicalizeStateLines(body, r, "section")
		if !strings.Contains(got, line+"\n") {
			t.Errorf("legacy line %q dropped when a record was added", line)
		}
		if pr := parseStateLines(got); pr.rec != r.norm() {
			t.Errorf("record next to legacy line %q parsed as %+v", line, pr.rec)
		}
	}
}

// TestStates_MalformedRecordsAreProblems: a structured head with a broken tail
// is reported (never silently dropped), keeps its head state, and blocks
// canonicalization.
func TestStates_MalformedRecordsAreProblems(t *testing.T) {
	cases := []struct{ line, want string }{
		{"**Reproduction:** reproduced-live — VERIFIED", "label"},
		{"**Reproduction:** reproduced-live", "label"},
		{"**Reproduction:** reproduced-live — REPRODUCED — evidence `e`", "disagrees"},
		{"**Reproduction:** reproduced-live — UNREPRODUCED — color `red`", "unknown key"},
		{"**Reproduction:** reproduced-live — UNREPRODUCED — evidence `a` — evidence `b`", "duplicate"},
		{"**Reproduction:** reproduced-live — UNREPRODUCED — evidence `open", "unterminated"},
		{"**Reproduction:** reproduced-live — UNREPRODUCED — evidence plain", "code span"},
		{"**Reproduction:** reproduced-live — UNREPRODUCED — surface somewhere", "surface"},
		{"**Reproduction:** reproduced-live — UNREPRODUCED — updated 2026-13-01T00:00:00Z", "timestamp"},
		{"**Reproduction:** blocked-no-device — UNREPRODUCED", "canonical"},
		{"**Reproduction:** UNSET", "canonical"},
		{"**Reproduction:** UNREPRODUCED", "canonical"},
		{"**Investigation:** UNSET", "never written"},
		{"**Investigation:** in-progress — root-cause plain", "code span"},
		{"**Investigation:** in-progress trailing", ""},
	}
	for _, c := range cases {
		body := "## WIT-1 — t\n\n**Status:** Queued\n" + c.line + "\n"
		p := parseStateLines(body)
		if c.want == "" {
			// "in-progress trailing" is not a closed-set head: legacy prose.
			if len(p.problems) != 0 {
				t.Errorf("%q: unexpected problems %v", c.line, p.problems)
			}
			continue
		}
		if len(p.problems) == 0 || !strings.Contains(strings.Join(p.problems, ";"), c.want) {
			t.Errorf("%q: problems %v, want one mentioning %q", c.line, p.problems, c.want)
			continue
		}
		if got := canonicalizeStateLines(body, stateRecord{}, "section"); got != body {
			t.Errorf("%q: canonicalize rewrote a body with a malformed record", c.line)
		}
		if strings.HasPrefix(c.line, reproLinePrefix) && !strings.Contains(c.want, "canonical") {
			if p.rec.ReproState == stateUnset {
				t.Errorf("%q: malformed record lost its head state (silently UNSET)", c.line)
			}
		}
	}
	dup := "## WIT-1 — t\n\n**Status:** Queued\n**Reproduction:** none — UNREPRODUCED\n**Reproduction:** none — UNREPRODUCED\n"
	if p := parseStateLines(dup); len(p.problems) == 0 {
		t.Error("two structured Reproduction records were not reported")
	}
}

// TestStates_SubItemRecordsAreNotTheItemsOwn (ATM-842): a record inside a `###`
// sub-item does not describe the parent.
func TestStates_SubItemRecordsAreNotTheItemsOwn(t *testing.T) {
	body := "## WIT-1 — t\n\n**Status:** Queued\n\n### Sub\n\n**Reproduction:** none — UNREPRODUCED\n**Investigation:** in-progress\n"
	if p := parseStateLines(body); p.rec != (stateRecord{}).norm() || len(p.problems) > 0 {
		t.Fatalf("sub-item record adopted as the item's own: %+v %v", p.rec, p.problems)
	}
	r := stateRecord{ReproState: reproBlocked, ReproBlocker: "no board"}
	got := canonicalizeStateLines(body, r, "section")
	if !strings.HasSuffix(got, "### Sub\n\n**Reproduction:** none — UNREPRODUCED\n**Investigation:** in-progress\n") {
		t.Errorf("sub-item region changed:\n%s", got)
	}
	if !strings.Contains(got, "**Status:** Queued\n"+renderReproLine(r)+"\n") {
		t.Errorf("record not placed in the item's own meta block:\n%s", got)
	}
}

func TestStates_TableRowsAreNeverRewritten(t *testing.T) {
	row := "| 2026-10-01 | ATM-1 title | Bug | Fixed | r1 | abc | qa.txt |\n"
	if got := canonicalizeStateLines(row, stateRecord{ReproState: reproUnreproduced}, "table"); got != row {
		t.Errorf("table row rewritten: %q", got)
	}
}

// ---- record problems ------------------------------------------------------------

func TestStates_RecordProblems(t *testing.T) {
	root := newEvidenceRoot(t)
	ev := materialiseEvidence(t, root, "qa-results/wit/red.txt")
	cases := []struct {
		name    string
		r       stateRecord
		resolve bool
		want    string // "" = no problem
	}{
		{"unset-clean", stateRecord{}, true, ""},
		{"unset-with-detail", stateRecord{ReproEvidence: ev}, true, "UNSET but reproduction evidence"},
		{"inv-unset-with-detail", stateRecord{InvRootCause: "x"}, true, "UNSET but investigation root-cause"},
		{"live-no-evidence", stateRecord{ReproState: reproLive}, true, "requires an evidence path"},
		{"live-missing-file", stateRecord{ReproState: reproLive, ReproEvidence: "qa-results/absent.txt"}, true, "reproduced-live"},
		{"live-missing-file-format-only", stateRecord{ReproState: reproLive, ReproEvidence: "qa-results/absent.txt"}, false, ""},
		{"live-ok", stateRecord{ReproState: reproLive, ReproEvidence: ev}, true, ""},
		{"nrwe-no-evidence", stateRecord{ReproState: reproNotReproducible}, true, "requires an evidence path"},
		{"blocked-no-blocker", stateRecord{ReproState: reproBlocked}, true, "recorded blocker"},
		{"blocked-ok", stateRecord{ReproState: reproBlocked, ReproBlocker: "needs D2"}, true, ""},
		{"unreproduced-plan-ok", stateRecord{ReproState: reproUnreproduced, ReproRedCmd: "x"}, true, ""},
		{"rcf-no-cause", stateRecord{InvState: invRootCauseFound, InvEvidence: ev}, true, "requires investigation_root_cause"},
		{"rcf-no-evidence", stateRecord{InvState: invRootCauseFound, InvRootCause: "x"}, true, "requires an evidence path"},
		{"rcf-ok", stateRecord{InvState: invRootCauseFound, InvRootCause: "x", InvEvidence: ev}, true, ""},
		{"cnd-no-evidence", stateRecord{InvState: invClosedNoDefect}, true, "requires an evidence path"},
		{"bad-state", stateRecord{ReproState: "VERIFIED"}, true, "not in closed set"},
		{"multiline", stateRecord{ReproState: reproUnreproduced, ReproSignature: "a\nb"}, true, "single line"},
		{"bad-time", stateRecord{ReproState: reproUnreproduced, ReproUpdatedAt: "2026-11-03 10:00"}, true, "RFC 3339"},
	}
	for _, c := range cases {
		got := strings.Join(stateRecordProblems(c.r, c.resolve), "; ")
		if c.want == "" && got != "" {
			t.Errorf("%s: unexpected problems: %s", c.name, got)
		}
		if c.want != "" && !strings.Contains(got, c.want) {
			t.Errorf("%s: problems %q, want one containing %q", c.name, got, c.want)
		}
	}
}

// ---- closure invariants -----------------------------------------------------------

func closedItem(typ, status string, r stateRecord) item {
	return item{AtmID: "WIT-9", Type: typ, Status: status, CurrentLocation: "Fixed", Representation: "section", States: r}
}

func TestStates_ClosureRules(t *testing.T) {
	fixed := closeStatusMap["fixed"].status
	completed := closeStatusMap["completed"].status
	implemented := closeStatusMap["implemented"].status
	obsolete := closeStatusMap["obsolete"].status
	armed := closureGate{armed: true, exempt: map[string]string{}, obsoleteReason: map[string]string{}}
	unarmed := closureGate{exempt: map[string]string{}, obsoleteReason: map[string]string{}}
	withReason := func(reason string) closureGate {
		return closureGate{armed: true, exempt: map[string]string{}, obsoleteReason: map[string]string{"WIT-9": reason}}
	}
	exempted := closureGate{armed: true, exempt: map[string]string{"WIT-9\x00section": fixed}, obsoleteReason: map[string]string{}}

	type tc struct {
		name string
		it   item
		g    closureGate
		bad  bool
	}
	cases := []tc{
		{"C1 complete live REPRODUCED fixed", closedItem("Bug", fixed, completeLive()), armed, false},
		{"C1 UNREPRODUCED fixed (unarmed too)", closedItem("Bug", fixed, stateRecord{ReproState: reproUnreproduced}), unarmed, true},
		{"C1 blocked fixed", closedItem("Bug", fixed, stateRecord{ReproState: reproBlocked, ReproBlocker: "x"}), unarmed, true},
		{"C1 not-reproducible fixed", closedItem("Bug", fixed, stateRecord{ReproState: reproNotReproducible, ReproEvidence: "e"}), unarmed, true},
		{"C1 incomplete live fixed", closedItem("Bug", fixed, stateRecord{ReproState: reproLive, ReproEvidence: "e"}), unarmed, true},
		{"C1 Task UNREPRODUCED completed", closedItem("Task", completed, stateRecord{ReproState: reproUnreproduced}), unarmed, true},
		{"C1 Feature UNREPRODUCED implemented", closedItem("Feature", implemented, stateRecord{ReproState: reproUnreproduced}), unarmed, true},
		{"PROVISIONAL open item with UNREPRODUCED", item{AtmID: "WIT-9", Type: "Bug", Status: "Ready for testing", CurrentLocation: "Issues", States: stateRecord{ReproState: reproUnreproduced}}, armed, false},
		{"C2 armed Bug UNSET fixed", closedItem("Bug", fixed, stateRecord{}), armed, true},
		{"C2 unarmed Bug UNSET fixed", closedItem("Bug", fixed, stateRecord{}), unarmed, false},
		{"C2 exempt Bug UNSET fixed", closedItem("Bug", fixed, stateRecord{}), exempted, false},
		{"C2 exempt but status changed", closedItem("Bug", obsolete, stateRecord{}), exempted, true},
		{"C2 Feature UNSET implemented", closedItem("Feature", implemented, stateRecord{}), armed, false},
		{"C2 Task UNSET completed", closedItem("Task", completed, stateRecord{}), armed, false},
		{"C3 Bug UNSET obsolete no reason", closedItem("Bug", obsolete, stateRecord{}), armed, true},
		{"C3 Bug UNSET obsolete unarmed", closedItem("Bug", obsolete, stateRecord{}), unarmed, false},
		{"C3 Bug UNSET obsolete duplicate-of", closedItem("Bug", obsolete, stateRecord{}), withReason("duplicate-of"), false},
		{"C3 Bug UNSET obsolete feature-removed", closedItem("Bug", obsolete, stateRecord{}), withReason("feature-removed"), false},
		{"C3 not-reproducible reason with NRWE", closedItem("Bug", obsolete, stateRecord{ReproState: reproNotReproducible, ReproEvidence: "e"}), withReason("not-reproducible"), false},
		{"C3 not-reproducible reason with blocked", closedItem("Bug", obsolete, stateRecord{ReproState: reproBlocked, ReproBlocker: "x"}), withReason("not-reproducible"), true},
		{"C3 Bug blocked obsolete other reason", closedItem("Bug", obsolete, stateRecord{ReproState: reproBlocked, ReproBlocker: "x"}), armed, false},
		{"C3 Bug UNREPRODUCED obsolete", closedItem("Bug", obsolete, stateRecord{ReproState: reproUnreproduced}), armed, true},
		{"C3 Feature UNSET obsolete", closedItem("Feature", obsolete, stateRecord{}), armed, false},
		{"C3 Feature UNREPRODUCED obsolete", closedItem("Feature", obsolete, stateRecord{ReproState: reproUnreproduced}), armed, true},
	}
	for _, c := range cases {
		probs := closureReproProblems(c.it, c.g)
		if c.bad && len(probs) == 0 {
			t.Errorf("%s: no problem reported (closure gate is a bluff)", c.name)
		}
		if !c.bad && len(probs) > 0 {
			t.Errorf("%s: false-positive problem: %v", c.name, probs)
		}
	}
}

func TestStates_DesyncDetector(t *testing.T) {
	r := stateRecord{ReproState: reproUnreproduced}
	body := canonicalizeStateLines("## WIT-1 — t\n\n**Status:** Queued\n", r, "section")
	in := item{AtmID: "WIT-1", CurrentLocation: "Issues", Representation: "section", BodyMD: body, States: r}
	if d := stateColumnBodyDesyncs([]item{in}); len(d) != 0 {
		t.Fatalf("in-sync item reported: %v", d)
	}
	off := in
	off.States = stateRecord{ReproState: reproBlocked, ReproBlocker: "x"}
	if d := stateColumnBodyDesyncs([]item{off}); len(d) != 1 || !strings.Contains(d[0], "desync") {
		t.Errorf("column≠body not reported: %v", d)
	}
	tbl := item{AtmID: "WIT-2", CurrentLocation: "Fixed", Representation: "table", BodyMD: "| a |\n", States: r}
	if d := stateColumnBodyDesyncs([]item{tbl}); len(d) != 1 {
		t.Errorf("state on a table row not reported: %v", d)
	}
}
