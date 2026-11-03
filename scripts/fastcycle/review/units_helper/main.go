// Command units prints the top-level command units of a shell script (ATM-1217 r10, the structural replacement
// of the r9 lexical scanner). A unit is one OUTERMOST statement of the parse tree (an element of File.Stmts:
// a whole if / while / for / case / { } / ( ) / function definition / pipeline / list), from the line it starts
// on to the LAST line any node under it reaches -- here-document bodies and their terminator lines included,
// wherever the redirect sits (inside a pipeline, a list, a substitution). Statements that share a line are one
// unit. A line outside every statement (blank, comment) is a unit of its own. The output is a partition of the
// lines 1..N, where lines are counted as the gate counts them (split on '\n', a trailing empty piece dropped).
//
// Usage:  units -dialect posix|bash|mksh  <script
// Output: one JSON object on stdout:
//
//	{"schema":"precheck-units/1","dialect":"posix","lines":N,"units":[[first,last],...]}
//
// Exit:   0 units printed; 3 the script does not parse in that dialect (JSON {"schema":...,"error":...});
//
//	2 usage error or unreadable input; 4 an internal inconsistency (a position outside the file).
//
// Every non-zero exit means "no units": the caller (lib/precheck_pack_run.py) then judges the file as a new file
// (the whole-file verdict). The parser is mvdan.cc/sh/v3/syntax (BSD-3-Clause, vendored under vendor/).
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"

	"mvdan.cc/sh/v3/syntax"
)

const schema = "precheck-units/1"

type result struct {
	Schema  string    `json:"schema"`
	Dialect string    `json:"dialect"`
	Lines   int       `json:"lines"`
	Units   [][2]uint `json:"units,omitempty"`
	Error   string    `json:"error,omitempty"`
}

func emit(r result, code int) {
	b, _ := json.Marshal(r)
	os.Stdout.Write(append(b, '\n'))
	os.Exit(code)
}

// lineCount mirrors precheck_pack_run._raw_lines: split on '\n', drop one trailing empty piece.
func lineCount(data []byte) int {
	if len(data) == 0 {
		return 0
	}
	n := bytes.Count(data, []byte("\n"))
	if data[len(data)-1] != '\n' {
		n++
	}
	return n
}

// hdocEnd: the last line a here-document reaches -- its closing delimiter line. With a body, the parser's body
// word ends ON the delimiter line (measured on v3.13.1: `cat <<EOF / ab / cd / EOF` gives Hdoc 2:1-4:4); that line
// must read as the delimiter, else the helper fails closed. An EMPTY body has no word: the delimiter then lies
// before the next top-level statement that starts on a later line than the operator (the lexer reads the body at
// the first newline after the operator, before any later statement), so the unit is extended up to that
// statement -- a superset, stricter only -- and the delimiter must be found in that range.
func hdocEnd(lines [][]byte, r *syntax.Redirect, nextStart uint) (uint, string) {
	if r.Word == nil {
		return 0, "a here-document without a delimiter word"
	}
	delim := delimText(r.Word)
	match := func(ln uint) bool {
		if ln == 0 || int(ln) > len(lines) {
			return false
		}
		l := lines[ln-1]
		if r.Op == syntax.DashHdoc {
			l = bytes.TrimLeft(l, "\t")
		}
		return string(l) == delim
	}
	if r.Hdoc != nil && r.Hdoc.End().IsValid() {
		t := r.Hdoc.End().Line()
		if !match(t) {
			return 0, fmt.Sprintf("here-document opened on line %d: line %d is not its delimiter", r.OpPos.Line(), t)
		}
		return t, ""
	}
	last := nextStart - 1
	for ln := r.OpPos.Line() + 1; ln <= last; ln++ {
		if match(ln) {
			return last, ""
		}
	}
	return 0, fmt.Sprintf("here-document opened on line %d: empty body, delimiter line not found", r.OpPos.Line())
}

// delimText: the here-document delimiter as it appears on its closing line (quoting removed; a backslash in an
// unquoted part only quotes the next character).
func delimText(w *syntax.Word) string {
	var buf bytes.Buffer
	var walk func(parts []syntax.WordPart)
	walk = func(parts []syntax.WordPart) {
		for _, p := range parts {
			switch x := p.(type) {
			case *syntax.Lit:
				v := x.Value
				for i := 0; i < len(v); i++ {
					if v[i] == '\\' && i+1 < len(v) {
						i++
					}
					buf.WriteByte(v[i])
				}
			case *syntax.SglQuoted:
				buf.WriteString(x.Value)
			case *syntax.DblQuoted:
				walk(x.Parts)
			}
		}
	}
	walk(w.Parts)
	return buf.String()
}

func main() {
	dialect := flag.String("dialect", "", "posix | bash | mksh")
	flag.Parse()
	langs := map[string]syntax.LangVariant{"posix": syntax.LangPOSIX, "bash": syntax.LangBash, "mksh": syntax.LangMirBSDKorn}
	lang, ok := langs[*dialect]
	if !ok || flag.NArg() != 0 {
		emit(result{Schema: schema, Dialect: *dialect, Error: "usage: units -dialect posix|bash|mksh <script"}, 2)
	}
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		emit(result{Schema: schema, Dialect: *dialect, Error: "read: " + err.Error()}, 2)
	}
	n := lineCount(data)
	res := result{Schema: schema, Dialect: *dialect, Lines: n}
	file, err := syntax.NewParser(syntax.Variant(lang), syntax.KeepComments(false)).Parse(bytes.NewReader(data), "")
	if err != nil {
		res.Error = "parse: " + err.Error()
		emit(res, 3)
	}
	lines := bytes.Split(data, []byte("\n"))
	if len(lines) > 0 && len(lines[len(lines)-1]) == 0 {
		lines = lines[:len(lines)-1]
	}
	var spans [][2]uint
	bad := ""
	// nextStart(l): the first line > l on which a top-level statement starts, or n+1
	nextStart := func(l uint) uint {
		for _, st := range file.Stmts {
			if st.Pos().Line() > l {
				return st.Pos().Line()
			}
		}
		return uint(n) + 1
	}
	for _, st := range file.Stmts {
		lo, hi := st.Pos().Line(), st.End().Line()
		if !st.Pos().IsValid() || !st.End().IsValid() || lo == 0 || hi == 0 {
			bad = "a statement without a valid position"
			break
		}
		syntax.Walk(st, func(node syntax.Node) bool {
			if node == nil || bad != "" {
				return false
			}
			for _, p := range []syntax.Pos{node.Pos(), node.End()} {
				if p.IsValid() && p.Line() > hi {
					hi = p.Line()
				}
			}
			if r, ok := node.(*syntax.Redirect); ok && (r.Op == syntax.Hdoc || r.Op == syntax.DashHdoc) {
				t, why := hdocEnd(lines, r, nextStart(r.OpPos.Line()))
				if why != "" {
					bad = why
					return false
				}
				if t > hi {
					hi = t
				}
			}
			return true
		})
		if bad != "" {
			break
		}
		spans = append(spans, [2]uint{lo, hi})
	}
	if bad != "" {
		res.Error = bad
		emit(res, 4)
	}
	sort.Slice(spans, func(i, j int) bool { return spans[i][0] < spans[j][0] })
	var merged [][2]uint
	for _, s := range spans {
		if len(merged) > 0 && s[0] <= merged[len(merged)-1][1] {
			if s[1] > merged[len(merged)-1][1] {
				merged[len(merged)-1][1] = s[1]
			}
			continue
		}
		merged = append(merged, s)
	}
	next := uint(1)
	for _, s := range merged {
		if s[0] < next || s[1] > uint(n) || s[1] < s[0] {
			res.Error = fmt.Sprintf("statement span %d-%d outside the file's %d lines", s[0], s[1], n)
			emit(res, 4)
		}
		for ; next < s[0]; next++ {
			res.Units = append(res.Units, [2]uint{next, next})
		}
		res.Units = append(res.Units, s)
		next = s[1] + 1
	}
	for ; next <= uint(n); next++ {
		res.Units = append(res.Units, [2]uint{next, next})
	}
	emit(res, 0)
}
