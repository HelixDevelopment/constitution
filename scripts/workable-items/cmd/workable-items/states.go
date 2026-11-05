// states.go — reproduction + investigation states on every workable item
// (schema v8; Constitution §11.4.292 "reproduce first").
//
// # WHAT THIS ADDS
//
// Two closed-vocabulary state machines carried by EVERY item, each with detail
// fields, stored as columns on `items` (authoritative, §11.4.93/§11.4.95) and
// rendered into the item body as ONE single-line record each:
//
//	**Reproduction:** <head>[ — <key> <value>]...
//	**Investigation:** <state>[ — <key> <value>]...
//
// reproduction_state closed set (§11.4.292(B) results + the two absence states):
//
//	UNSET                                   no record (never assessed; never invented)
//	UNREPRODUCED                            rendered `none — UNREPRODUCED` (§11.4.292(C):
//	                                        `none` is the absence of a result)
//	reproduced-live
//	reproduced-host-fixture
//	not-reproducible-with-evidence
//	blocked-no-device-with-recorded-blocker (input alias: blocked-no-device)
//
// investigation_state closed set:
//
//	UNSET | not-started | in-progress | root-cause-found-with-evidence |
//	root-cause-unconfirmed | closed-no-defect
//
// The reproduction LABEL (§11.4.292(B): REPRODUCED | UNREPRODUCED) is never
// stored: it is computed from the record (reproLabel) and rendered next to the
// result so a hand-edited label that disagrees with the record is a parse
// problem, not a silent claim.
//
// # LOSSLESS ROUND TRIP
//
// md→db (buildItem) parses the records into the columns; db→md
// (renderDocument) canonicalizes the records from the columns with
// canonicalizeStateLines, a STRICT no-op whenever the body already parses to
// the column values. Free-text values are written as CommonMark code spans
// whose fence is one backtick longer than the longest backtick run inside the
// value, so any single-line value (including one that contains ` — `) parses
// back byte-for-byte. Values are trimmed and may not contain a newline.
//
// A `**Reproduction:**` / `**Investigation:**` line whose remainder does not
// start with a closed-set head is LEGACY PROSE (the trackers carried 25 + 1
// such free-form lines before v8) and is never interpreted: it neither sets a
// state nor is rewritten.
package main

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

const stateUnset = "UNSET"

// Reproduction states (§11.4.292(B) results + the two absence states).
const (
	reproUnreproduced    = "UNREPRODUCED"
	reproLive            = "reproduced-live"
	reproHostFixture     = "reproduced-host-fixture"
	reproNotReproducible = "not-reproducible-with-evidence"
	reproBlocked         = "blocked-no-device-with-recorded-blocker"
)

// reproStates is the closed reproduction_state vocabulary, in lifecycle order.
// The schema CHECK (schema_embed.sql + migrateStatesColumns) carries the SAME
// list; TestStates_SchemaCheckMatchesGoClosedSets pins the two together.
var reproStates = []string{
	stateUnset, reproUnreproduced, reproLive, reproHostFixture,
	reproNotReproducible, reproBlocked,
}

// reproStateAliases are INPUT-ONLY spellings (CLI flags, import TSV). They are
// normalised to the canonical token before storage; the Markdown parser
// accepts canonical tokens only, so a stored record always renders and parses
// back identically.
var reproStateAliases = map[string]string{
	"blocked-no-device": reproBlocked,
}

// Investigation states.
const (
	invNotStarted           = "not-started"
	invInProgress           = "in-progress"
	invRootCauseFound       = "root-cause-found-with-evidence"
	invRootCauseUnconfirmed = "root-cause-unconfirmed"
	invClosedNoDefect       = "closed-no-defect"
)

var investigationStates = []string{
	stateUnset, invNotStarted, invInProgress, invRootCauseFound,
	invRootCauseUnconfirmed, invClosedNoDefect,
}

// Reproduction surface (§11.4.292(B)): where the defect manifests. "" = not
// recorded.
const (
	surfaceLiveTarget = "live-target"
	surfaceHostOnly   = "host-only"
)

var reproSurfaces = []string{surfaceLiveTarget, surfaceHostOnly}

// Reproduction labels (§11.4.292(B)).
const (
	labelReproduced   = "REPRODUCED"
	labelUnreproduced = "UNREPRODUCED"
)

const (
	reproLinePrefix = "**Reproduction:**"
	invLinePrefix   = "**Investigation:**"
	stateSep        = " — "
)

// stateRecord is the in-memory form of the 15 state columns of one item.
type stateRecord struct {
	ReproState     string
	ReproSurface   string
	ReproEvidence  string
	ReproRedCmd    string
	ReproGreenCmd  string
	ReproEnv       string
	ReproSignature string
	ReproBlocker   string
	ReproUpdatedAt string
	ReproUpdatedBy string

	InvState     string
	InvRootCause string
	InvEvidence  string
	InvUpdatedAt string
	InvUpdatedBy string
}

// norm maps the Go zero value of a state onto UNSET so a record built in code
// (tests, add, legacy rows) compares equal to one loaded from the DB.
func (r stateRecord) norm() stateRecord {
	if r.ReproState == "" {
		r.ReproState = stateUnset
	}
	if r.InvState == "" {
		r.InvState = stateUnset
	}
	return r
}

// reproDetails / invDetails return the detail fields of each block as
// (key, value) pairs in canonical render order. The keys are the Markdown keys.
func (r stateRecord) reproDetails() [][2]string {
	return [][2]string{
		{"surface", r.ReproSurface},
		{"evidence", r.ReproEvidence},
		{"red-command", r.ReproRedCmd},
		{"green-command", r.ReproGreenCmd},
		{"env", r.ReproEnv},
		{"signature", r.ReproSignature},
		{"blocker", r.ReproBlocker},
		{"updated", r.ReproUpdatedAt},
		{"by", r.ReproUpdatedBy},
	}
}

func (r stateRecord) invDetails() [][2]string {
	return [][2]string{
		{"root-cause", r.InvRootCause},
		{"evidence", r.InvEvidence},
		{"updated", r.InvUpdatedAt},
		{"by", r.InvUpdatedBy},
	}
}

// setReproDetail / setInvDetail assign one detail by its Markdown key; false
// for an unknown key (a parse problem).
func (r *stateRecord) setReproDetail(key, val string) bool {
	switch key {
	case "surface":
		r.ReproSurface = val
	case "evidence":
		r.ReproEvidence = val
	case "red-command":
		r.ReproRedCmd = val
	case "green-command":
		r.ReproGreenCmd = val
	case "env":
		r.ReproEnv = val
	case "signature":
		r.ReproSignature = val
	case "blocker":
		r.ReproBlocker = val
	case "updated":
		r.ReproUpdatedAt = val
	case "by":
		r.ReproUpdatedBy = val
	default:
		return false
	}
	return true
}

func (r *stateRecord) setInvDetail(key, val string) bool {
	switch key {
	case "root-cause":
		r.InvRootCause = val
	case "evidence":
		r.InvEvidence = val
	case "updated":
		r.InvUpdatedAt = val
	case "by":
		r.InvUpdatedBy = val
	default:
		return false
	}
	return true
}

func inSet(v string, set []string) bool {
	for _, s := range set {
		if v == s {
			return true
		}
	}
	return false
}

// normalizeReproStateInput maps a CLI / import value onto the closed set
// (trimmed; aliases resolved). ok=false for anything outside the set.
func normalizeReproStateInput(v string) (string, bool) {
	v = strings.TrimSpace(v)
	if a, ok := reproStateAliases[v]; ok {
		v = a
	}
	return v, inSet(v, reproStates)
}

func normalizeInvStateInput(v string) (string, bool) {
	v = strings.TrimSpace(v)
	return v, inSet(v, investigationStates)
}

// reproLabel computes the §11.4.292(B) label of a record and, for a
// reproduced-* result that is NOT labelled REPRODUCED, the reasons. UNSET has no
// label (""). A reproduced-* record is REPRODUCED only when every required field
// of §11.4.292(C) is present (surface, evidence, red-command, env, signature),
// no field is written `UNCONFIRMED…`, and a host-fixture reproduction has a
// host-only surface (a live-target defect reproduced only on a fixture stays
// UNREPRODUCED until its live RED exists, §11.4.292(D)).
func reproLabel(r stateRecord) (string, []string) {
	r = r.norm()
	switch r.ReproState {
	case stateUnset:
		return "", nil
	case reproLive, reproHostFixture:
		var why []string
		for _, kv := range [][2]string{
			{"surface", r.ReproSurface}, {"evidence", r.ReproEvidence},
			{"red-command", r.ReproRedCmd}, {"env", r.ReproEnv},
			{"signature", r.ReproSignature},
		} {
			if kv[1] == "" {
				why = append(why, "missing "+kv[0])
			}
		}
		if r.ReproState == reproHostFixture && r.ReproSurface == surfaceLiveTarget {
			why = append(why, "host fixture on a live-target surface")
		}
		for _, kv := range r.reproDetails() {
			if strings.HasPrefix(kv[1], "UNCONFIRMED") {
				why = append(why, kv[0]+" UNCONFIRMED")
			}
		}
		if len(why) == 0 {
			return labelReproduced, nil
		}
		return labelUnreproduced, why
	default:
		return labelUnreproduced, nil
	}
}

// ---- code spans -----------------------------------------------------------

func longestBacktickRun(s string) int {
	best, cur := 0, 0
	for i := 0; i < len(s); i++ {
		if s[i] == '`' {
			cur++
			if cur > best {
				best = cur
			}
		} else {
			cur = 0
		}
	}
	return best
}

// encodeCodeSpan writes v as a CommonMark code span. The fence is one backtick
// longer than the longest backtick run in v; a value that starts or ends with a
// backtick is padded with one space on each side (CommonMark strips exactly
// that). v is non-empty, trimmed and newline-free (checked by
// checkStateValue), so a leading space inside a span can only be padding.
func encodeCodeSpan(v string) string {
	fence := strings.Repeat("`", longestBacktickRun(v)+1)
	if strings.HasPrefix(v, "`") || strings.HasSuffix(v, "`") {
		return fence + " " + v + " " + fence
	}
	return fence + v + fence
}

// decodeCodeSpan parses a code span at the start of s, returning its content
// and the remainder after the closing fence.
func decodeCodeSpan(s string) (val, rest string, err error) {
	n := 0
	for n < len(s) && s[n] == '`' {
		n++
	}
	if n == 0 {
		return "", "", fmt.Errorf("value is not a code span: %q", firstLine(s))
	}
	i := n
	for i < len(s) {
		if s[i] != '`' {
			i++
			continue
		}
		j := i
		for j < len(s) && s[j] == '`' {
			j++
		}
		if j-i == n {
			content := s[n:i]
			if strings.HasPrefix(content, " ") {
				if !strings.HasSuffix(content, " ") || len(content) < 3 {
					return "", "", fmt.Errorf("code span has unbalanced padding: %q", firstLine(s[:j]))
				}
				content = content[1 : len(content)-1]
			}
			if content == "" {
				return "", "", fmt.Errorf("empty code span")
			}
			return content, s[j:], nil
		}
		i = j
	}
	return "", "", fmt.Errorf("unterminated code span: %q", firstLine(s))
}

// ---- record lines ---------------------------------------------------------

// isBareKey reports whether a Markdown key's value is a bare token (not a code
// span): the closed-set surface and the RFC 3339 timestamp.
func isBareKey(key string) bool { return key == "surface" || key == "updated" }

func appendDetails(b *strings.Builder, details [][2]string) {
	for _, kv := range details {
		if kv[1] == "" {
			continue
		}
		b.WriteString(stateSep)
		b.WriteString(kv[0])
		b.WriteString(" ")
		if isBareKey(kv[0]) {
			b.WriteString(kv[1])
		} else {
			b.WriteString(encodeCodeSpan(kv[1]))
		}
	}
}

// renderReproLine renders the reproduction record WITHOUT a trailing newline,
// or "" when the state is UNSET (no record).
func renderReproLine(r stateRecord) string {
	r = r.norm()
	if r.ReproState == stateUnset {
		return ""
	}
	var b strings.Builder
	b.WriteString(reproLinePrefix + " ")
	if r.ReproState == reproUnreproduced {
		b.WriteString("none" + stateSep + labelUnreproduced)
	} else {
		label, _ := reproLabel(r)
		b.WriteString(r.ReproState + stateSep + label)
	}
	appendDetails(&b, r.reproDetails())
	return b.String()
}

// renderInvestigationLine renders the investigation record, "" when UNSET.
func renderInvestigationLine(r stateRecord) string {
	r = r.norm()
	if r.InvState == stateUnset {
		return ""
	}
	var b strings.Builder
	b.WriteString(invLinePrefix + " " + r.InvState)
	appendDetails(&b, r.invDetails())
	return b.String()
}

// parseDetails parses the ` — <key> <value>` tail of a record line. set
// assigns a key (false = unknown key). Keys may appear in any order; a
// duplicate key is a problem.
func parseDetails(rest string, set func(key, val string) bool) error {
	seen := map[string]bool{}
	for rest != "" {
		if !strings.HasPrefix(rest, stateSep) {
			return fmt.Errorf("expected %q before %q", stateSep, firstLine(rest))
		}
		rest = rest[len(stateSep):]
		sp := strings.IndexByte(rest, ' ')
		if sp <= 0 {
			return fmt.Errorf("detail %q has no value", firstLine(rest))
		}
		key := rest[:sp]
		rest = rest[sp+1:]
		if seen[key] {
			return fmt.Errorf("duplicate key %q", key)
		}
		seen[key] = true
		var val string
		if isBareKey(key) {
			end := strings.Index(rest, stateSep)
			if end < 0 {
				end = len(rest)
			}
			val, rest = rest[:end], rest[end:]
			if val == "" || strings.ContainsAny(val, " \t`") {
				return fmt.Errorf("key %q needs a bare token, got %q", key, firstLine(val))
			}
		} else {
			var err error
			if val, rest, err = decodeCodeSpan(rest); err != nil {
				return fmt.Errorf("key %q: %v", key, err)
			}
		}
		if !set(key, val) {
			return fmt.Errorf("unknown key %q", key)
		}
	}
	return nil
}

// parseReproRemainder parses the text after `**Reproduction:**`. structured is
// false for legacy free-form prose (no closed-set head); err is non-nil for a
// structured record that is malformed. On error rec still carries the head
// state so the item is not silently UNSET.
func parseReproRemainder(rem string) (rec stateRecord, structured bool, err error) {
	if !strings.HasPrefix(rem, " ") {
		return rec, false, nil
	}
	rem = strings.TrimRight(rem[1:], " \t\r")
	head := rem
	if i := strings.Index(rem, stateSep); i >= 0 {
		head = rem[:i]
	}
	var rest, label string
	switch {
	case head == "none":
		if !strings.HasPrefix(rem, "none"+stateSep+labelUnreproduced) {
			return rec, false, nil // legacy prose that happens to start with "none"
		}
		rec.ReproState = reproUnreproduced
		rest = rem[len("none"+stateSep+labelUnreproduced):]
	case inSet(head, reproStates) && head != stateUnset && head != reproUnreproduced:
		rec.ReproState = head
		after := rem[len(head):]
		if !strings.HasPrefix(after, stateSep) {
			return rec, true, fmt.Errorf("result %q is not followed by %q and a label", head, stateSep)
		}
		after = after[len(stateSep):]
		label = after
		if i := strings.Index(after, stateSep); i >= 0 {
			label = after[:i]
		}
		if label != labelReproduced && label != labelUnreproduced {
			return rec, true, fmt.Errorf("label %q not in {%s, %s}", label, labelReproduced, labelUnreproduced)
		}
		rest = after[len(label):]
	default:
		// The head names no closed-set result: legacy prose, unless it is an
		// alias / UNSET spelled into the line (a structured intent that is not
		// a canonical token — reported, never silently accepted).
		if _, isAlias := reproStateAliases[head]; isAlias || head == stateUnset || head == reproUnreproduced {
			return rec, true, fmt.Errorf("head %q is not a canonical Markdown result token", head)
		}
		return rec, false, nil
	}
	err = parseDetails(rest, rec.setReproDetail)
	if err == nil {
		err = checkRecordFormats(rec)
	}
	if err == nil && label != "" {
		if want, _ := reproLabel(rec); want != label {
			err = fmt.Errorf("label %s disagrees with the record (computed %s)", label, want)
		}
	}
	if err != nil {
		return stateRecord{ReproState: rec.ReproState}, true, err
	}
	return rec, true, nil
}

// parseInvRemainder parses the text after `**Investigation:**`.
func parseInvRemainder(rem string) (rec stateRecord, structured bool, err error) {
	if !strings.HasPrefix(rem, " ") {
		return rec, false, nil
	}
	rem = strings.TrimRight(rem[1:], " \t\r")
	head := rem
	if i := strings.Index(rem, stateSep); i >= 0 {
		head = rem[:i]
	}
	if !inSet(head, investigationStates) {
		return rec, false, nil
	}
	rec.InvState = head
	if head == stateUnset {
		return rec, true, fmt.Errorf("UNSET is never written as a record")
	}
	err = parseDetails(rem[len(head):], rec.setInvDetail)
	if err == nil {
		err = checkRecordFormats(rec)
	}
	if err != nil {
		return stateRecord{InvState: head}, true, err
	}
	return rec, true, nil
}

// stateParse is the result of scanning one body for its records.
type stateParse struct {
	rec      stateRecord
	reproIdx int // line index of the structured Reproduction record, -1 if none
	invIdx   int
	problems []string
}

// parseStateLines finds the structured records in the item's OWN metadata
// region (ATM-842: a nested `### ` sub-item's records describe the sub-item).
func parseStateLines(body string) stateParse {
	p := stateParse{reproIdx: -1, invIdx: -1}
	lines := splitKeepNewlines(body)
	limit := ownMetaRegionLineCount(lines)
	for i := 0; i < limit; i++ {
		t := strings.TrimRight(lines[i], "\n")
		switch {
		case strings.HasPrefix(t, reproLinePrefix):
			r, structured, err := parseReproRemainder(t[len(reproLinePrefix):])
			if !structured {
				continue
			}
			if p.reproIdx >= 0 {
				p.problems = append(p.problems, fmt.Sprintf("second structured %s record on body line %d", reproLinePrefix, i+1))
				continue
			}
			p.reproIdx = i
			p.rec.copyRepro(r)
			if err != nil {
				p.problems = append(p.problems, fmt.Sprintf("malformed %s record on body line %d: %v", reproLinePrefix, i+1, err))
			}
		case strings.HasPrefix(t, invLinePrefix):
			r, structured, err := parseInvRemainder(t[len(invLinePrefix):])
			if !structured {
				continue
			}
			if p.invIdx >= 0 {
				p.problems = append(p.problems, fmt.Sprintf("second structured %s record on body line %d", invLinePrefix, i+1))
				continue
			}
			p.invIdx = i
			p.rec.copyInv(r)
			if err != nil {
				p.problems = append(p.problems, fmt.Sprintf("malformed %s record on body line %d: %v", invLinePrefix, i+1, err))
			}
		}
	}
	p.rec = p.rec.norm()
	return p
}

func (r *stateRecord) copyRepro(s stateRecord) {
	r.ReproState, r.ReproSurface, r.ReproEvidence = s.ReproState, s.ReproSurface, s.ReproEvidence
	r.ReproRedCmd, r.ReproGreenCmd, r.ReproEnv = s.ReproRedCmd, s.ReproGreenCmd, s.ReproEnv
	r.ReproSignature, r.ReproBlocker = s.ReproSignature, s.ReproBlocker
	r.ReproUpdatedAt, r.ReproUpdatedBy = s.ReproUpdatedAt, s.ReproUpdatedBy
}

func (r *stateRecord) copyInv(s stateRecord) {
	r.InvState, r.InvRootCause, r.InvEvidence = s.InvState, s.InvRootCause, s.InvEvidence
	r.InvUpdatedAt, r.InvUpdatedBy = s.InvUpdatedAt, s.InvUpdatedBy
}

// stateAnchor returns the line index at which a NEW record is inserted: the end
// of the non-blank run that holds the item's own `**Status:**` line (the
// heading-adjacent meta block, including any continuation bullets, so a
// multi-line `**Operator-Block-Details:**` / `**Reopened-Details:**` block is
// never split). Without a Status line: right after the heading line.
func stateAnchor(lines []string, limit int) int {
	s := -1
	for i := 0; i < limit; i++ {
		if strings.HasPrefix(lines[i], "**Status:**") {
			s = i
			break
		}
	}
	if s < 0 {
		if limit > 0 && strings.HasPrefix(lines[0], "## ") {
			return 1
		}
		return 0
	}
	j := s + 1
	for j < limit {
		t := strings.TrimSpace(lines[j])
		if t == "" || t == "---" || strings.HasPrefix(t, "## ") {
			break
		}
		j++
	}
	return j
}

// canonicalizeStateLines returns body with its records made to match want.
// STRICT no-op when the body already parses to want, when the representation
// is a pipe-table row (no record can live in a row), and when the body carries a
// malformed or duplicated record (left byte-for-byte for `validate` to report).
// Otherwise it replaces / deletes / inserts exactly the record lines that
// differ; every other line is preserved.
func canonicalizeStateLines(body string, want stateRecord, representation string) string {
	if representation == "table" {
		return body
	}
	want = want.norm()
	p := parseStateLines(body)
	if len(p.problems) > 0 || p.rec == want {
		return body
	}
	lines := splitKeepNewlines(body)
	limit := ownMetaRegionLineCount(lines)
	newRepro := renderReproLine(want)
	newInv := renderInvestigationLine(want)

	type op struct {
		idx  int    // line index (existing) or insertion point
		line string // "" = delete
		ins  bool
	}
	setLine := func(i int, s string) {
		nl := ""
		if strings.HasSuffix(lines[i], "\n") {
			nl = "\n"
		}
		lines[i] = s + nl
	}
	// Replace or blank-out existing records in place (a blanked line is
	// removed below), so indices stay valid while we decide insertions.
	const drop = "\x00drop"
	if p.reproIdx >= 0 {
		if newRepro == "" {
			lines[p.reproIdx] = drop
		} else {
			setLine(p.reproIdx, newRepro)
		}
	}
	if p.invIdx >= 0 {
		if newInv == "" {
			lines[p.invIdx] = drop
		} else {
			setLine(p.invIdx, newInv)
		}
	}
	var inserts []op
	needRepro := p.reproIdx < 0 && newRepro != ""
	needInv := p.invIdx < 0 && newInv != ""
	switch {
	case needRepro && needInv:
		a := stateAnchor(lines, limit)
		inserts = append(inserts, op{idx: a, line: newRepro, ins: true}, op{idx: a, line: newInv, ins: true})
	case needRepro && p.invIdx >= 0 && newInv != "":
		inserts = append(inserts, op{idx: p.invIdx, line: newRepro, ins: true})
	case needRepro:
		inserts = append(inserts, op{idx: stateAnchor(lines, limit), line: newRepro, ins: true})
	case needInv && p.reproIdx >= 0 && newRepro != "":
		inserts = append(inserts, op{idx: p.reproIdx + 1, line: newInv, ins: true})
	case needInv:
		inserts = append(inserts, op{idx: stateAnchor(lines, limit), line: newInv, ins: true})
	}
	var out []string
	pos := 0
	emitUpTo := func(n int) {
		for ; pos < n && pos < len(lines); pos++ {
			out = append(out, lines[pos])
		}
	}
	for _, o := range inserts {
		emitUpTo(o.idx)
		if len(out) > 0 && !strings.HasSuffix(out[len(out)-1], "\n") && out[len(out)-1] != drop {
			out[len(out)-1] += "\n"
		}
		out = append(out, o.line+"\n")
	}
	emitUpTo(len(lines))
	var b strings.Builder
	for _, l := range out {
		if l != drop {
			b.WriteString(l)
		}
	}
	return b.String()
}

// ---- validation -------------------------------------------------------------

// checkStateValue rejects a detail value that cannot round-trip: a newline, or
// surrounding whitespace (callers trim CLI / TSV input first).
func checkStateValue(key, v string) error {
	if v == "" {
		return nil
	}
	if strings.ContainsAny(v, "\r\n") {
		return fmt.Errorf("%s must be a single line", key)
	}
	if strings.TrimSpace(v) != v {
		return fmt.Errorf("%s has leading/trailing whitespace", key)
	}
	return nil
}

// checkTimestamp accepts RFC 3339 UTC with a literal Z, seconds precision
// (`2026-11-03T17:05:00Z`), the form recordStatesTimestamp writes.
func checkTimestamp(key, v string) error {
	if v == "" {
		return nil
	}
	t, err := time.Parse("2006-01-02T15:04:05Z", v)
	if err != nil || t.UTC().Format("2006-01-02T15:04:05Z") != v {
		return fmt.Errorf("%s %q is not an RFC 3339 UTC timestamp (YYYY-MM-DDTHH:MM:SSZ)", key, v)
	}
	return nil
}

// checkRecordFormats checks the closed sets and the per-value formats of a
// record (no filesystem access).
func checkRecordFormats(r stateRecord) error {
	r = r.norm()
	if !inSet(r.ReproState, reproStates) {
		return fmt.Errorf("reproduction_state %q not in closed set {%s}", r.ReproState, strings.Join(reproStates, ", "))
	}
	if !inSet(r.InvState, investigationStates) {
		return fmt.Errorf("investigation_state %q not in closed set {%s}", r.InvState, strings.Join(investigationStates, ", "))
	}
	if r.ReproSurface != "" && !inSet(r.ReproSurface, reproSurfaces) {
		return fmt.Errorf("reproduction_surface %q not in closed set {%s}", r.ReproSurface, strings.Join(reproSurfaces, ", "))
	}
	for _, kv := range append(r.reproDetails(), r.invDetails()...) {
		if err := checkStateValue(kv[0], kv[1]); err != nil {
			return err
		}
	}
	if err := checkTimestamp("reproduction updated", r.ReproUpdatedAt); err != nil {
		return err
	}
	return checkTimestamp("investigation updated", r.InvUpdatedAt)
}

// stateRecordProblems returns every invariant problem of one record:
// closed sets + formats, UNSET-carries-no-details (so omitting the line is
// lossless), and the evidence requirements:
//
//	reproduced-live / reproduced-host-fixture / not-reproducible-with-evidence
//	    → reproduction_evidence present and resolvable (checkEvidencePath)
//	blocked-no-device-with-recorded-blocker → reproduction_blocker present
//	root-cause-found-with-evidence → investigation_root_cause present and
//	    investigation_evidence present and resolvable
//	closed-no-defect → investigation_evidence present and resolvable
//
// resolveEvidence=false skips the filesystem check (pure-format callers).
func stateRecordProblems(r stateRecord, resolveEvidence bool) []string {
	r = r.norm()
	var out []string
	if err := checkRecordFormats(r); err != nil {
		out = append(out, err.Error())
	}
	if r.ReproState == stateUnset {
		for _, kv := range r.reproDetails() {
			if kv[1] != "" {
				out = append(out, fmt.Sprintf("reproduction_state is UNSET but reproduction %s is set (details need a state)", kv[0]))
			}
		}
	}
	if r.InvState == stateUnset {
		for _, kv := range r.invDetails() {
			if kv[1] != "" {
				out = append(out, fmt.Sprintf("investigation_state is UNSET but investigation %s is set (details need a state)", kv[0]))
			}
		}
	}
	needEvidence := func(what, path string) {
		if path == "" {
			out = append(out, what+" requires an evidence path")
			return
		}
		if resolveEvidence {
			if err := checkEvidencePath(path); err != nil {
				out = append(out, what+": "+err.Error())
			}
		}
	}
	switch r.ReproState {
	case reproLive, reproHostFixture, reproNotReproducible:
		needEvidence("reproduction_state "+r.ReproState, r.ReproEvidence)
	case reproBlocked:
		if r.ReproBlocker == "" {
			out = append(out, "reproduction_state "+reproBlocked+" requires a recorded blocker (reproduction_blocker)")
		}
	}
	switch r.InvState {
	case invRootCauseFound:
		if r.InvRootCause == "" {
			out = append(out, "investigation_state "+invRootCauseFound+" requires investigation_root_cause")
		}
		needEvidence("investigation_state "+invRootCauseFound, r.InvEvidence)
	case invClosedNoDefect:
		needEvidence("investigation_state "+invClosedNoDefect, r.InvEvidence)
	}
	return out
}

// verifiedClosureStatuses are the §11.4.33 type-aware closure values, which mean
// VERIFIED-DONE (§11.4.290(I)). Obsolete is a closure but not a verified fix.
func verifiedClosureStatus(status string) bool {
	switch strings.TrimSpace(status) {
	case closeStatusMap["fixed"].status, closeStatusMap["implemented"].status, closeStatusMap["completed"].status:
		return true
	}
	return false
}

// reproClosureAllowed is the set a defect item must carry to be CLOSED at all
// (the four §11.4.292(B) results; never UNSET, never UNREPRODUCED).
var reproClosureAllowed = []string{reproLive, reproHostFixture, reproNotReproducible, reproBlocked}

// closureGate carries the DB facts closureReproProblems needs.
type closureGate struct {
	armed          bool              // `states freeze` has run (meta repro_gate_armed_at)
	exempt         map[string]string // atm_id\x00rep -> status frozen at arming
	obsoleteReason map[string]string // atm_id -> obsolete_details.reason
}

func (g closureGate) isExempt(it item) bool {
	st, ok := g.exempt[it.AtmID+"\x00"+it.repOrDefault()]
	return ok && st == it.Status
}

// closureReproProblems evaluates the closure invariants for one item:
//
//	(C1, always) an item whose status is a VERIFIED closure value
//	     (Fixed/Implemented/Completed) and which carries a reproduction record
//	     must be labelled REPRODUCED (§11.4.292(B)/(D): an UNREPRODUCED item —
//	     including blocked and not-reproducible — never reaches VERIFIED-DONE;
//	     PROVISIONAL-DONE stays open with Ready for testing / In testing).
//	(C2, armed) a Bug closed with a VERIFIED value must carry a record (UNSET is
//	     the "never reproduced" case C1 cannot see).
//	(C3, armed) a defect item (a Bug, or any item that carries a record) closed
//	     Obsolete must carry one of the four results, unless its §11.4.90 reason
//	     is a non-defect one (duplicate-of / superseded-* / feature-removed /
//	     unsupported-topology); reason not-reproducible requires the
//	     not-reproducible-with-evidence result (§11.4.292(F)).
//
// Items exempted by `states freeze` (closed before the gate was armed, still in
// the frozen status) are skipped for C2/C3 only; C1 has no legacy instances.
func closureReproProblems(it item, g closureGate) []string {
	if it.CurrentLocation != "Fixed" || !terminalStatuses()[strings.TrimSpace(it.Status)] {
		return nil
	}
	st := it.States.norm()
	var out []string
	if verifiedClosureStatus(it.Status) {
		if st.ReproState != stateUnset {
			if label, why := reproLabel(st); label != labelReproduced {
				detail := ""
				if len(why) > 0 {
					detail = " (" + strings.Join(why, "; ") + ")"
				}
				out = append(out, fmt.Sprintf("%s: status %q is a VERIFIED closure but the reproduction record %s is labelled %s%s — an UNREPRODUCED item may be PROVISIONAL-DONE (Ready for testing / In testing) but never VERIFIED (§11.4.292(B)/(D)) [%s]",
					it.AtmID, it.Status, st.ReproState, label, detail, it.repOrDefault()))
			}
		} else if g.armed && it.Type == "Bug" && !g.isExempt(it) {
			out = append(out, fmt.Sprintf("%s: Bug closed %q with reproduction_state UNSET — a fix is closed only on a reproduction record (§11.4.292(A)/(C)) [%s]",
				it.AtmID, it.Status, it.repOrDefault()))
		}
		return out
	}
	// Obsolete.
	inScope := it.Type == "Bug" || st.ReproState != stateUnset
	if !g.armed || !inScope || g.isExempt(it) {
		return nil
	}
	reason := g.obsoleteReason[it.AtmID]
	switch reason {
	case "duplicate-of", "superseded-by-design-change", "superseded-by-later-mandate",
		"feature-removed", "unsupported-topology":
		return nil
	case "not-reproducible":
		if st.ReproState != reproNotReproducible {
			out = append(out, fmt.Sprintf("%s: Obsolete with reason not-reproducible but reproduction_state is %s — §11.4.292(F) closes a non-reproduction only on a %s record [%s]",
				it.AtmID, st.ReproState, reproNotReproducible, it.repOrDefault()))
		}
	default:
		if !inSet(st.ReproState, reproClosureAllowed) {
			out = append(out, fmt.Sprintf("%s: %s closed Obsolete with reproduction_state %s and no non-defect §11.4.90 reason — a closed defect carries one of {%s} [%s]",
				it.AtmID, it.Type, st.ReproState, strings.Join(reproClosureAllowed, ", "), it.repOrDefault()))
		}
	}
	return out
}

// stateColumnBodyDesyncs is the column↔body guard for the records (the
// counterpart of statusColumnBodyDesyncs): a section body whose records are
// malformed, duplicated, or parse to values other than the columns. A 'table'
// row cannot carry a record, so a non-UNSET state on one is reported as
// unrepresentable.
func stateColumnBodyDesyncs(items []item) []string {
	var out []string
	for _, it := range items {
		cols := it.States.norm()
		if it.repOrDefault() != "section" {
			if cols != (stateRecord{}).norm() {
				out = append(out, fmt.Sprintf("%s [%s/%s]: reproduction/investigation state set on a pipe-table row, which cannot carry a record",
					it.AtmID, it.CurrentLocation, it.repOrDefault()))
			}
			continue
		}
		p := parseStateLines(it.BodyMD)
		for _, pr := range p.problems {
			out = append(out, fmt.Sprintf("%s [%s/%s]: %s", it.AtmID, it.CurrentLocation, it.repOrDefault(), pr))
		}
		if len(p.problems) == 0 && p.rec != cols {
			out = append(out, fmt.Sprintf("%s [%s/%s]: state columns disagree with the body records (columns %s / body %s) — column↔body desync",
				it.AtmID, it.CurrentLocation, it.repOrDefault(), describeStates(cols), describeStates(p.rec)))
		}
	}
	return out
}

// describeStates is a compact one-line rendering for messages.
func describeStates(r stateRecord) string {
	r = r.norm()
	return fmt.Sprintf("repro=%s inv=%s", strings.TrimPrefix(renderReproLine(r), reproLinePrefix+" "),
		strings.TrimPrefix(renderInvestigationLine(r), invLinePrefix+" "))
}

// reproSummaryCell / invSummaryCell are the Issues_Summary / Fixed_Summary
// cells: the state, its label, and (for a reproduced-* record that is not
// REPRODUCED) what is missing.
func reproSummaryCell(r stateRecord) string {
	r = r.norm()
	switch r.ReproState {
	case stateUnset:
		return stateUnset
	case reproUnreproduced:
		return "none — " + labelUnreproduced
	}
	label, why := reproLabel(r)
	cell := r.ReproState + " — " + label
	if len(why) > 0 {
		cell += " (" + strings.Join(why, "; ") + ")"
	}
	return cell
}

func invSummaryCell(r stateRecord) string {
	return r.norm().InvState
}

// recordStatesTimestamp is the canonical updated_at form.
func recordStatesTimestamp(t time.Time) string {
	return t.UTC().Truncate(time.Second).Format("2006-01-02T15:04:05Z")
}

// sortedKeys is a small helper for deterministic messages.
func sortedKeys(m map[string]int) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
