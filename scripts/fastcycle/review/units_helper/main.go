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
//	2 usage error or unreadable input; 4 an internal inconsistency (a position outside the file, a here-document
//	terminator that is not the delimiter the shell derives); 5 the script uses a construct whose effect on where a
//	command ends the parser does not model (an in-file alias definition or alias-expansion switch, a NUL byte).
//
// r11 (round-1 review F1, F2, F6 and the 11.4.276(C) class "the parser and the real shell disagree about where a
// unit ends or what is executed"): (1) a POSIX script is parsed TWICE, as POSIX (dash) and as bash (bash --posix is
// /bin/sh on some hosts), and its units are the UNION of both partitions (a superset: a line counts as unchanged only
// when its unit is unchanged under both); a failure of either parse is a failure. (2) dash and bash --posix expand
// aliases in scripts, so `alias p='x |'` makes the next line continue a pipeline the parser splits: every in-file
// alias definition or switch fails closed (exit 5); aliases from sourced files are a stated limit. (3) A NUL byte:
// dash drops it, bash refuses the file, the parser keeps it -> exit 5. (4) The here-document delimiter is derived by
// the shell's quote removal and the terminator line is checked against it.
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
	"strings"

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

// delimText: the here-document delimiter as the shell derives it from the word (quote removal, unquote()).
func delimText(w *syntax.Word) string {
	t, _ := unquote(w)
	return t
}

// unquote: the word's text after the shell's quote removal, and whether the whole word is literal (no expansion).
// Unquoted: a backslash quotes the next character, a backslash-newline is removed. Inside double quotes a backslash
// is removed only before $ ` " \ and newline (bash and dash, measured: `<<"a\b"` ends at the line a\b, and
// `<<"a\\b"` wants the line a\b). Single quotes: the text as written.
func unquote(w *syntax.Word) (string, bool) {
	var buf bytes.Buffer
	lit := true
	var walk func(parts []syntax.WordPart, dq bool)
	walk = func(parts []syntax.WordPart, dq bool) {
		for _, p := range parts {
			switch x := p.(type) {
			case *syntax.Lit:
				v := x.Value
				for i := 0; i < len(v); i++ {
					if v[i] == '\\' && i+1 < len(v) {
						c := v[i+1]
						if !dq || c == '$' || c == '`' || c == '"' || c == '\\' || c == '\n' {
							i++
							if c == '\n' {
								continue
							}
						}
					}
					buf.WriteByte(v[i])
				}
			case *syntax.SglQuoted:
				buf.WriteString(x.Value)
			case *syntax.DblQuoted:
				walk(x.Parts, true)
			default:
				lit = false
			}
		}
	}
	walk(w.Parts, false)
	return buf.String(), lit
}

// unmodelled: the first construct of the tree that can change where a LATER command ends in a way the parser does
// not model, or "". These are the in-file ways to define an alias or to turn alias expansion on (measured with dash
// 0.5.12 and bash 5.3.9): an `alias` / `unalias` command (also quoted, escaped, after `builtin` / `command`, inside a
// function or a substitution), an `eval` whose argument mentions alias, a variable set to the word alias (run later
// as $a), an assignment to BASH_ALIASES or POSIXLY_CORRECT, a command naming POSIXLY_CORRECT, `set` / `shopt` with
// posix or expand_aliases. A command name built by an expansion and aliases from sourced files are stated limits.
func unmodelled(f *syntax.File) string {
	why := ""
	note := func(n syntax.Node, what string) {
		if why == "" {
			why = fmt.Sprintf("line %d: %s (alias expansion can continue a command on a later line; not modelled)", n.Pos().Line(), what)
		}
	}
	syntax.Walk(f, func(node syntax.Node) bool {
		if node == nil || why != "" {
			return false
		}
		switch x := node.(type) {
		case *syntax.Assign:
			if x.Name != nil && (x.Name.Value == "BASH_ALIASES" || x.Name.Value == "POSIXLY_CORRECT") {
				note(x, "an assignment to "+x.Name.Value)
			}
			if x.Value != nil {
				if t, ok := unquote(x.Value); ok && (t == "alias" || t == "unalias") {
					note(x, "a variable set to the word "+t)
				}
			}
		case *syntax.CallExpr:
			args := x.Args
			i := 0
			for i < len(args) {
				t, ok := unquote(args[i])
				if !ok || (t != "builtin" && t != "command") {
					break
				}
				for i++; i < len(args); i++ {
					if o, ok := unquote(args[i]); !ok || !strings.HasPrefix(o, "-") {
						break
					}
				}
			}
			if i < len(args) {
				t, _ := unquote(args[i])
				switch t {
				case "alias", "unalias":
					note(x, "an "+t+" command")
				case "eval":
					for _, a := range args[i+1:] {
						if strings.Contains(litPieces(a), "alias") {
							note(x, "an eval that mentions alias")
						}
					}
				case "set", "shopt":
					for _, a := range args[i+1:] {
						if p := litPieces(a); strings.Contains(p, "posix") || strings.Contains(p, "expand_aliases") {
							note(x, "a "+t+" that mentions posix / expand_aliases")
						}
					}
				}
			}
			for _, a := range args {
				if t, ok := unquote(a); ok && (t == "POSIXLY_CORRECT" || strings.HasPrefix(t, "POSIXLY_CORRECT=")) {
					note(x, "a command naming POSIXLY_CORRECT")
				}
			}
		}
		return true
	})
	return why
}

// litPieces: the literal text of every part of a word (expansions skipped), for a substring test.
func litPieces(w *syntax.Word) string {
	var buf bytes.Buffer
	syntax.Walk(w, func(node syntax.Node) bool {
		switch x := node.(type) {
		case *syntax.Lit:
			buf.WriteString(x.Value)
		case *syntax.SglQuoted:
			buf.WriteString(x.Value)
		}
		return true
	})
	return buf.String()
}

// stmtSpans: the [first, last] line of every outermost statement of one parse of the script, or (reason, exit code).
func stmtSpans(data []byte, lines [][]byte, n int, lang syntax.LangVariant) ([][2]uint, string, int) {
	file, err := syntax.NewParser(syntax.Variant(lang), syntax.KeepComments(false)).Parse(bytes.NewReader(data), "")
	if err != nil {
		return nil, "parse: " + err.Error(), 3
	}
	if why := unmodelled(file); why != "" {
		return nil, why, 5
	}
	// nextStart(l): the first line > l on which a top-level statement starts, or n+1
	nextStart := func(l uint) uint {
		for _, st := range file.Stmts {
			if st.Pos().Line() > l {
				return st.Pos().Line()
			}
		}
		return uint(n) + 1
	}
	var spans [][2]uint
	for _, st := range file.Stmts {
		lo, hi := st.Pos().Line(), st.End().Line()
		if !st.Pos().IsValid() || !st.End().IsValid() || lo == 0 || hi == 0 {
			return nil, "a statement without a valid position", 4
		}
		bad := ""
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
			return nil, bad, 4
		}
		spans = append(spans, [2]uint{lo, hi})
	}
	return spans, "", 0
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
	if bytes.IndexByte(data, 0) >= 0 {
		res.Error = "a NUL byte (dash drops it, bash refuses the file, the parser keeps it; not modelled)"
		emit(res, 5)
	}
	lines := bytes.Split(data, []byte("\n"))
	if len(lines) > 0 && len(lines[len(lines)-1]) == 0 {
		lines = lines[:len(lines)-1]
	}
	spans, why, code := stmtSpans(data, lines, n, lang)
	if why == "" && lang == syntax.LangPOSIX {
		// r11: the same bytes as bash parses them (bash --posix is /bin/sh on some hosts); units = the union
		var bspans [][2]uint
		bspans, why, code = stmtSpans(data, lines, n, syntax.LangBash)
		if why != "" {
			why = "bash cross-parse: " + why
		}
		spans = append(spans, bspans...)
	}
	if why != "" {
		res.Error = why
		emit(res, code)
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
