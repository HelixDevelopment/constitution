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
//	command ends the parser does not model (r12: anything outside the runtime-grammar allowlist, see unmodelled;
//	a NUL byte).
//
// r11 (round-1 review F1, F2, F6 and the 11.4.276(C) class "the parser and the real shell disagree about where a
// unit ends or what is executed"): (1) a POSIX script is parsed TWICE, as POSIX (dash) and as bash (bash --posix is
// /bin/sh on some hosts), and its units are the UNION of both partitions (a superset: a line counts as unchanged only
// when its unit is unchanged under both); a failure of either parse is a failure. (2) dash and bash --posix expand
// aliases in scripts, so `alias p='x |'` makes the next line continue a pipeline the parser splits. r12 replaces the
// r11 member list with an allowlist (unmodelled, rules R1-R5): a file is credited only while every command that runs
// in the current shell is statically known and outside the closed set of alias / code / mode builtins; everything
// else exits 5. Sourcing always fails closed (the sourced text is never seen). (3) A NUL byte:
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

// r12 (review round 2 G1, 11.4.276(E)(3) structural round): the class "runtime grammar modifiers the static parser
// does not model" is closed by an ALLOWLIST, not by naming members. Aliases are the one way a later line can be
// joined to an earlier command at run time, and only code running in the CURRENT shell can define one (a
// subshell, a $( ), a pipeline element or a child shell cannot change the parent's alias table; measured: an alias
// defined in an arithmetic-subscript $( ) does not survive). So the helper credits a file only while every command
// that runs in the current shell is statically known and harmless:
//
//	R1 every command word (after `command` / `builtin` and their options, and after exec-style wrappers) is a
//	   STATIC word: literal after quote removal ($'..' decoded), no expansion, no pathname or brace expansion
//	   character (a lone `[` is the test command). Anything else ($cmd, "$@", ${a}, $( ), `..`, alia?, {a,b},
//	   ~x) is a dynamically computed command word and fails closed.
//	R2 the closed set of builtins that run text as code or change alias state or the parser's mode fails closed:
//	   alias, unalias, . , source, enable, fc, bind, complete, compgen, compopt, history; mapfile/readarray -C
//	   (callback); declare/typeset/local -n (nameref). `eval` is allowed only when every argument is static: the
//	   joined text is parsed and checked by these same rules (depth <= 8). `trap` is allowed when it lists or
//	   resets, when every signal is EXIT / 0 (the action runs after the last line was read), or when the action
//	   is static and passes these rules recursively; a computed action or signal fails closed.
//	   `set` / `shopt` are allowed only with static option names from an allowlist (posix, expand_aliases, the
//	   history options and every unlisted name fail closed; `set --` operands are free).
//	R3 every variable-NAME sink takes a static name: read, printf -v, mapfile/readarray, getopts, declare-family
//	   names; a computed name fails closed.
//	R4 the names that change alias state or run prompt expansion fail closed wherever they are ASSIGNED
//	   (assignment, declare, ${x:=v}): BASH_ALIASES, POSIXLY_CORRECT, PS0-PS4, PROMPT_COMMAND, BASH_ENV, ENV,
//	   SHELLOPTS, BASHOPTS; the words BASH_ALIASES, POSIXLY_CORRECT and expand_aliases fail closed ANYWHERE
//	   (in any word, quoted or not, after quote removal and $'..' decoding); the prompt operator ${x@P} fails
//	   closed; a variable set to the word alias / unalias fails closed.
//	R5 `exec` with no command and a redirection of fd 0 fails closed (the shell would read the rest of a
//	   script from another file when the script is read on stdin).
//
// The census tests/units_runtime_grammar_census.py runs >= 200 generated channel scripts through dash and
// bash --posix (and bash) and asserts that no script on which a real shell joins the two lines is split here.
// Stated limits: the content of a file the script sources is never seen (sourcing fails closed), and a script
// that rewrites ITSELF at run time is not modelled.

const maxCodeDepth = 8

// assignSinks: names whose assignment changes alias state, the shell's mode, or is expanded as a prompt
var assignSinks = map[string]bool{"BASH_ALIASES": true, "POSIXLY_CORRECT": true, "PS0": true, "PS1": true,
	"PS2": true, "PS3": true, "PS4": true, "PROMPT_COMMAND": true, "BASH_ENV": true, "ENV": true,
	"SHELLOPTS": true, "BASHOPTS": true}

// anywhereTokens: sink NAMES that fail closed wherever they occur in a word (a static name reaches them through
// printf -v / read / mapfile / getopts / declare / export / unset / [[ -v ]]). expand_aliases is not one: it has an
// effect only as a shopt operand, and shopt operands are allowlisted (a data word "expand_aliases" stays credited).
var anywhereTokens = []string{"BASH_ALIASES", "POSIXLY_CORRECT"}

// codeBuiltins: builtins that run text as code, change alias state, or load code
var codeBuiltins = map[string]bool{"alias": true, "unalias": true, ".": true, "source": true, "enable": true,
	"fc": true, "bind": true, "complete": true, "compgen": true, "compopt": true, "history": true}

// setOptsOK: `set -o NAME` / `shopt -o NAME` names that cannot change how a later line is read
var setOptsOK = map[string]bool{"allexport": true, "braceexpand": true, "emacs": true, "errexit": true,
	"errtrace": true, "functrace": true, "hashall": true, "ignoreeof": true, "keyword": true, "monitor": true,
	"noclobber": true, "noexec": true, "noglob": true, "nolog": true, "notify": true, "nounset": true,
	"onecmd": true, "physical": true, "pipefail": true, "privileged": true, "verbose": true, "vi": true,
	"xtrace": true}

// shoptOK: `shopt -s/-u NAME` names that cannot change how a later line is read (expand_aliases, extglob-like
// parser options outside this list, and every unlisted name fail closed)
var shoptOK = map[string]bool{"autocd": true, "cdable_vars": true, "cdspell": true, "checkhash": true,
	"checkjobs": true, "checkwinsize": true, "direxpand": true, "dirspell": true, "dotglob": true, "execfail": true,
	"extglob": true, "failglob": true, "globasciiranges": true, "globskipdots": true, "globstar": true,
	"gnu_errfmt": true, "huponexit": true, "inherit_errexit": true, "lastpipe": true, "localvar_inherit": true,
	"localvar_unset": true, "mailwarn": true, "nocaseglob": true, "nocasematch": true, "noexpand_translation": true,
	"nullglob": true, "patsub_replacement": true, "progcomp": true, "progcomp_alias": false, "promptvars": true,
	"shift_verbose": true, "sourcepath": true, "varredir_close": true, "xpg_echo": true}

// setLetters: single-letter `set` options allowed (H = history expansion is not)
const setLetters = "abeEfhkmnpPtTuvxBC"

// wrappers: commands that run their operand; the operand is checked as a command word
var shellWrappers = map[string]bool{"command": true, "builtin": true}
var execWrappers = map[string]bool{"exec": true, "env": true, "nohup": true, "time": true, "xargs": true,
	"nice": true, "timeout": true, "stdbuf": true, "setsid": true, "ionice": true, "chrt": true, "taskset": true,
	"sudo": true, "doas": true}

type checker struct {
	lang  syntax.LangVariant
	depth int
	why   string
}

func (c *checker) note(n syntax.Node, what string) {
	if c.why == "" {
		ln := uint(0)
		if n != nil && n.Pos().IsValid() {
			ln = n.Pos().Line()
		}
		c.why = fmt.Sprintf("line %d: %s", ln, what)
		if c.depth == 0 { // the suffix once, on the outermost reason (nested reasons are embedded in it)
			c.why += " (runtime grammar: not modelled, r12 allowlist)"
		}
	}
}

// ansiC decodes the body of a $'..' string (bash rules; an unknown escape keeps the backslash).
func ansiC(v string) string {
	var b strings.Builder
	for i := 0; i < len(v); i++ {
		if v[i] != '\\' || i+1 >= len(v) {
			b.WriteByte(v[i])
			continue
		}
		i++
		switch c := v[i]; c {
		case 'a':
			b.WriteByte(7)
		case 'b':
			b.WriteByte(8)
		case 'e', 'E':
			b.WriteByte(27)
		case 'f':
			b.WriteByte(12)
		case 'n':
			b.WriteByte('\n')
		case 'r':
			b.WriteByte('\r')
		case 't':
			b.WriteByte('\t')
		case 'v':
			b.WriteByte(11)
		case '\\', '\'', '"', '?':
			b.WriteByte(c)
		case 'c':
			if i+1 < len(v) {
				i++
				b.WriteByte(v[i] & 0x1f)
			}
		case 'x', 'u', 'U':
			max := map[byte]int{'x': 2, 'u': 4, 'U': 8}[c]
			j, n := i+1, 0
			for j < len(v) && n < max && strings.IndexByte("0123456789abcdefABCDEF", v[j]) >= 0 {
				j++
				n++
			}
			if n == 0 {
				b.WriteByte('\\')
				b.WriteByte(c)
				continue
			}
			var r rune
			fmt.Sscanf(v[i+1:j], "%x", &r)
			if c == 'x' {
				b.WriteByte(byte(r))
			} else {
				b.WriteRune(r)
			}
			i = j - 1
		default:
			if c >= '0' && c <= '7' {
				j, r := i, 0
				for j < len(v) && j < i+3 && v[j] >= '0' && v[j] <= '7' {
					r = r*8 + int(v[j]-'0')
					j++
				}
				b.WriteByte(byte(r))
				i = j - 1
			} else {
				b.WriteByte('\\')
				b.WriteByte(c)
			}
		}
	}
	return b.String()
}

// static: the word's value when it is fully known at parse time -- literal after quote removal ($'..' decoded),
// with no expansion and no unquoted pathname / brace / tilde expansion character (a lone `[` is a command name).
func static(w *syntax.Word) (string, bool) {
	if w == nil {
		return "", false
	}
	var buf bytes.Buffer
	ok := true
	var walk func(parts []syntax.WordPart, dq bool)
	walk = func(parts []syntax.WordPart, dq bool) {
		for _, p := range parts {
			switch x := p.(type) {
			case *syntax.Lit:
				v := x.Value
				for i := 0; i < len(v); i++ {
					ch := v[i]
					if ch == '\\' && i+1 < len(v) {
						n := v[i+1]
						if !dq || n == '$' || n == '`' || n == '"' || n == '\\' || n == '\n' {
							i++
							if n != '\n' {
								buf.WriteByte(n)
							}
							continue
						}
					}
					if !dq && (ch == '*' || ch == '?' || ch == '[' || ch == '{' || ch == '}' || (ch == '~' && buf.Len() == 0)) {
						// a '[' with no ']' after it in the same, last literal opens no bracket expression ([ / [[)
						if !(ch == '[' && p == parts[len(parts)-1] && !strings.Contains(v[i+1:], "]")) {
							ok = false
						}
					}
					buf.WriteByte(ch)
				}
			case *syntax.SglQuoted:
				if x.Dollar {
					buf.WriteString(ansiC(x.Value))
				} else {
					buf.WriteString(x.Value)
				}
			case *syntax.DblQuoted:
				walk(x.Parts, true)
			default:
				ok = false
			}
		}
	}
	walk(w.Parts, false)
	return buf.String(), ok
}

// tokenText: every literal piece of a word after quote removal ($'..' decoded), expansions skipped -- the text in
// which the anywhere-tokens are searched (so BASH_ALI"AS"ES, BASH_ALI\ASES, "BASH_ALI"ASES all read as the token).
func tokenText(w *syntax.Word) string {
	var buf bytes.Buffer
	syntax.Walk(w, func(node syntax.Node) bool {
		switch x := node.(type) {
		case *syntax.Lit:
			buf.WriteString(strings.NewReplacer("\\", "", "\n", "").Replace(x.Value))
		case *syntax.SglQuoted:
			if x.Dollar {
				buf.WriteString(ansiC(x.Value))
			} else {
				buf.WriteString(x.Value)
			}
		}
		return true
	})
	return buf.String()
}

// code checks a text that the shell will run in the current shell (a static eval argument, a static trap action)
// by the same rules, parsed in the checker's dialect.
func (c *checker) code(n syntax.Node, text, what string) {
	if c.depth >= maxCodeDepth {
		c.note(n, what+" nested deeper than the checked depth")
		return
	}
	f, err := syntax.NewParser(syntax.Variant(c.lang), syntax.KeepComments(false)).Parse(strings.NewReader(text), "")
	if err != nil {
		c.note(n, what+" whose text does not parse")
		return
	}
	sub := &checker{lang: c.lang, depth: c.depth + 1}
	sub.file(f)
	if sub.why != "" {
		c.note(n, what+": "+sub.why)
	}
}

// commandWords: the command name and the arguments that follow it, after the shell-builtin wrappers (command,
// builtin and their options) and the exec-style wrappers (their options and VAR=val operands). ok=false when a
// command word is not static (R1).
func (c *checker) commandWords(x *syntax.CallExpr) (string, []*syntax.Word, bool) {
	args := x.Args
	for len(args) > 0 {
		name, ok := static(args[0])
		if !ok {
			c.note(args[0], "a dynamically computed command word")
			return "", nil, false
		}
		if !shellWrappers[name] && !execWrappers[name] {
			return name, args[1:], true
		}
		args = args[1:]
		for len(args) > 0 {
			o, ok := static(args[0])
			if ok && name == "command" && strings.HasPrefix(o, "-") && strings.ContainsAny(o, "vV") {
				return "", nil, true // command -v / -V only looks a name up; nothing runs
			}
			if !ok {
				if execWrappers[name] {
					return name, args, true // a child process runs the computed operand: no effect on this shell
				}
				c.note(args[0], "a dynamically computed operand of "+name)
				return "", nil, false
			}
			if o == "--" {
				args = args[1:]
				break
			}
			if strings.HasPrefix(o, "-") || (execWrappers[name] && strings.Contains(o, "=") && !strings.HasPrefix(o, "=")) {
				args = args[1:]
				continue
			}
			break
		}
		if len(args) == 0 {
			return name, nil, true
		}
	}
	return "", nil, true
}

func (c *checker) staticAll(ws []*syntax.Word) ([]string, bool) {
	out := make([]string, 0, len(ws))
	for _, w := range ws {
		v, ok := static(w)
		if !ok {
			return nil, false
		}
		out = append(out, v)
	}
	return out, true
}

func (c *checker) checkSet(x syntax.Node, args []*syntax.Word, name string) {
	for i := 0; i < len(args); i++ {
		v, ok := static(args[i])
		if !ok {
			c.note(x, "a "+name+" with a computed option")
			return
		}
		if v == "--" || v == "-" || !(strings.HasPrefix(v, "-") || strings.HasPrefix(v, "+")) {
			return // operands (positional parameters) follow
		}
		for _, l := range v[1:] {
			if l == 'o' {
				if i+1 >= len(args) {
					return // `set -o` / `set +o` alone prints
				}
				i++
				o, ok := static(args[i])
				if !ok || !setOptsOK[o] {
					c.note(x, "a "+name+" -o naming a not allowlisted option ("+o+"; posix and alias-related options are refused)")
					return
				}
			} else if !strings.ContainsRune(setLetters, l) {
				c.note(x, fmt.Sprintf("a %s option -%c that is not allowlisted", name, l))
				return
			}
		}
	}
}

func (c *checker) checkShopt(x syntax.Node, args []*syntax.Word) {
	oMode := false
	for _, a := range args {
		v, ok := static(a)
		if !ok {
			c.note(x, "a shopt with a computed option name")
			return
		}
		if strings.HasPrefix(v, "-") {
			if strings.Contains(v, "o") {
				oMode = true
			}
			for _, l := range v[1:] {
				if !strings.ContainsRune("supqo", l) {
					c.note(x, "a shopt flag that is not allowlisted")
					return
				}
			}
			continue
		}
		if (oMode && !setOptsOK[v]) || (!oMode && !shoptOK[v]) {
			c.note(x, "a shopt naming a not allowlisted option ("+v+"; posix and expand_aliases are refused)")
			return
		}
	}
}

// signalsAllExit: every signal word is static and names the EXIT pseudo-signal
func signalsAllExit(ws []*syntax.Word) (bool, bool) {
	if len(ws) == 0 {
		return false, true
	}
	for _, w := range ws {
		v, ok := static(w)
		if !ok {
			return false, false
		}
		if v != "EXIT" && v != "0" && v != "SIGEXIT" {
			return false, true
		}
	}
	return true, true
}

func (c *checker) checkTrap(x syntax.Node, args []*syntax.Word) {
	if len(args) > 0 {
		if v, ok := static(args[0]); ok && v == "--" {
			args = args[1:]
		} else if ok && strings.HasPrefix(v, "-") && len(v) > 1 {
			return // -p / -l / -P list
		}
	}
	if len(args) < 2 {
		return // no action: prints, or resets one signal
	}
	act, sigs := args[0], args[1:]
	allExit, sigStatic := signalsAllExit(sigs)
	if !sigStatic {
		c.note(x, "a trap with a computed signal")
		return
	}
	if allExit {
		return // the EXIT action runs after the last line of the file was read
	}
	v, ok := static(act)
	if !ok {
		c.note(x, "a trap whose action is computed")
		return
	}
	if v == "-" || v == "" {
		return
	}
	c.code(x, v, "a trap action")
}

// nameSinks (R3): the operands of read / printf -v / mapfile / getopts that name a variable must be static
func (c *checker) checkNameSink(x syntax.Node, name string, args []*syntax.Word) {
	valueOpts := map[string]string{"read": "adinNptu", "mapfile": "dnOscuC", "readarray": "dnOscuC"}
	switch name {
	case "printf":
		if len(args) >= 2 {
			if v, ok := static(args[0]); ok && v == "-v" {
				if _, ok := static(args[1]); !ok {
					c.note(x, "a printf -v with a computed variable name")
				}
			} else if !ok {
				c.note(x, "a printf with a computed first argument (could be -v)")
			}
		}
	case "getopts":
		if len(args) >= 2 {
			if _, ok := static(args[1]); !ok {
				c.note(x, "a getopts with a computed variable name")
			}
		}
	case "read", "mapfile", "readarray":
		vo := valueOpts[name]
		for i := 0; i < len(args); i++ {
			v, ok := static(args[i])
			if !ok {
				c.note(x, "a "+name+" with a computed variable name or option")
				return
			}
			if v == "--" {
				continue
			}
			if strings.HasPrefix(v, "-") && len(v) > 1 {
				for k, l := range v[1:] {
					if (name == "mapfile" || name == "readarray") && l == 'C' {
						c.note(x, "a "+name+" -C callback (runs code)")
						return
					}
					if strings.ContainsRune(vo, l) {
						if k == len(v)-2 { // the option's value is the next argument
							i++
							if l == 'a' && i < len(args) {
								if _, ok := static(args[i]); !ok {
									c.note(x, "a read -a with a computed array name")
									return
								}
							}
						}
						break
					}
				}
			}
		}
	}
}

func (c *checker) checkDecl(x *syntax.DeclClause) {
	for _, a := range x.Args {
		if a.Naked && a.Name == nil && a.Value != nil {
			v, ok := static(a.Value)
			if !ok {
				c.note(x, "a "+x.Variant.Value+" with a computed name or flag")
				return
			}
			if strings.HasPrefix(v, "-") && strings.Contains(v, "n") {
				c.note(x, "a "+x.Variant.Value+" -n (nameref)")
				return
			}
		}
	}
	if x.Variant.Value == "nameref" {
		c.note(x, "a nameref declaration")
	}
}

func (c *checker) file(f *syntax.File) {
	syntax.Walk(f, func(node syntax.Node) bool {
		if node == nil || c.why != "" {
			return false
		}
		switch x := node.(type) {
		case *syntax.Word:
			t := tokenText(x)
			for _, tok := range anywhereTokens {
				if strings.Contains(t, tok) {
					c.note(x, "the word "+tok)
				}
			}
		case *syntax.Assign:
			if x.Name != nil && assignSinks[x.Name.Value] {
				c.note(x, "an assignment to "+x.Name.Value)
			}
			if x.Value != nil {
				if t, ok := static(x.Value); ok && (t == "alias" || t == "unalias") {
					c.note(x, "a variable set to the word "+t)
				}
			}
		case *syntax.ParamExp:
			if x.Exp != nil {
				switch x.Exp.Op {
				case syntax.OtherParamOps:
					if x.Exp.Word != nil {
						if v, _ := static(x.Exp.Word); strings.Contains(v, "P") {
							c.note(x, "a prompt expansion ${x@P}")
						}
					}
				case syntax.AssignUnset, syntax.AssignUnsetOrNull:
					if x.Param != nil && assignSinks[x.Param.Value] {
						c.note(x, "an assignment to "+x.Param.Value)
					}
				}
			}
		case *syntax.DeclClause:
			c.checkDecl(x)
		case *syntax.Stmt:
			if ce, ok := x.Cmd.(*syntax.CallExpr); ok && len(ce.Args) == 1 {
				if v, ok := static(ce.Args[0]); ok && v == "exec" {
					for _, r := range x.Redirs {
						in := r.Op == syntax.RdrIn || r.Op == syntax.RdrInOut || r.Op == syntax.DplIn ||
							r.Op == syntax.Hdoc || r.Op == syntax.DashHdoc || r.Op == syntax.WordHdoc
						if in && (r.N == nil || r.N.Value == "0") {
							c.note(x, "an exec that redirects the shell's standard input")
						}
					}
				}
			}
		case *syntax.CallExpr:
			if len(x.Args) == 0 {
				return true
			}
			name, args, ok := c.commandWords(x)
			if !ok || name == "" {
				return true
			}
			switch {
			case codeBuiltins[name]:
				c.note(x, "an "+name+" command (alias state or code from outside the file)")
			case name == "eval":
				vs, ok := c.staticAll(args)
				if !ok {
					c.note(x, "an eval with a computed argument")
				} else {
					c.code(x, strings.Join(vs, " "), "an eval")
				}
			case name == "trap":
				c.checkTrap(x, args)
			case name == "set":
				c.checkSet(x, args, "set")
			case name == "shopt":
				c.checkShopt(x, args)
			case name == "declare" || name == "typeset" || name == "local" || name == "export" || name == "readonly":
				for _, a := range args {
					v, ok := static(a)
					if !ok {
						c.note(x, "a "+name+" with a computed name or flag")
						break
					}
					if strings.HasPrefix(v, "-") && strings.Contains(v, "n") {
						c.note(x, "a "+name+" -n (nameref)")
						break
					}
					if i := strings.IndexByte(v, '='); i > 0 && assignSinks[strings.SplitN(v[:i], "[", 2)[0]] {
						c.note(x, "an assignment to "+v[:i])
						break
					}
					if assignSinks[v] {
						c.note(x, "a "+name+" of "+v)
						break
					}
				}
			default:
				c.checkNameSink(x, name, args)
				for _, a := range args {
					if v, ok := static(a); ok && (name == "unset" || name == "export") && assignSinks[v] {
						c.note(x, "a "+name+" of "+v)
					}
				}
			}
		}
		return true
	})
}

// unmodelled: "" when the file uses no runtime grammar modifier (r12 rules R1-R5 above), else the first reason.
func unmodelled(f *syntax.File, lang syntax.LangVariant) string {
	c := &checker{lang: lang}
	c.file(f)
	return c.why
}

// stmtSpans: the [first, last] line of every outermost statement of one parse of the script, or (reason, exit code).
func stmtSpans(data []byte, lines [][]byte, n int, lang syntax.LangVariant) ([][2]uint, string, int) {
	file, err := syntax.NewParser(syntax.Variant(lang), syntax.KeepComments(false)).Parse(bytes.NewReader(data), "")
	if err != nil {
		return nil, "parse: " + err.Error(), 3
	}
	if why := unmodelled(file, lang); why != "" {
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
