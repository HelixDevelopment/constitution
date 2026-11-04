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
//	terminator that is not the delimiter the shell derives); 5 the script is outside the r13 positive subset (see
//	unmodelled) or contains a NUL byte.
//
// r11 (round-1 review F1, F2, F6 and the 11.4.276(C) class "the parser and the real shell disagree about where a
// unit ends or what is executed"): (1) a POSIX script is parsed TWICE, as POSIX (dash) and as bash (bash --posix is
// /bin/sh on some hosts), and its units are the UNION of both partitions (a superset: a line counts as unchanged only
// when its unit is unchanged under both); a failure of either parse is a failure. (2) dash and bash --posix expand
// aliases in scripts, so `alias p='x |'` makes the next line continue a pipeline the parser splits. r13 (round-3
// review H1) replaces the r12 deny-list rules R1-R5 with a POSITIVE, MINIMAL credited subset checked on the parsed
// AST (unmodelled, rules P1-P10): every node kind is enumerated and an unknown kind fails closed; arithmetic, name
// operands with computed subscripts, PS4-class variables, code / alias / mode builtins, sourcing and any external
// command that may read the SHELL's stdin while the script itself is that stdin all exit 5. The census of the repo's
// 1150 tracked .sh files (r13 report) credits 70 of them; everything else is judged as a whole file. (3) A NUL byte:
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
					// r13 round 5 (review r4 F1, classes W3-W4): \u / \U decode by the locale (LC_ALL=C bash keeps
					// \u00E9 as text) and \c? is 0x7f in bash: neither has one value, so neither is static. (W2: the
					// posix parse never yields a $'..' node; it reads $ and a quoted string, as dash 0.5.12 does.)
					if strings.Contains(x.Value, "\\c") || strings.Contains(x.Value, "\\u") ||
						strings.Contains(x.Value, "\\U") {
						ok = false
					}
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
	if bytes.IndexByte(buf.Bytes(), 0) >= 0 {
		ok = false // W1: bash ends a word at a NUL ($'-v\0' is -v to bash, -v\0 to the decoder)
	}
	return buf.String(), ok
}

// r13 (ATM-1217 review round 3 H1, 11.4.276(E) change of approach): the r11 member list and the r12 allowlist of
// "harmless current-shell commands" both enumerated DANGEROUS constructs, and review round 3 found a third family
// they did not name: bash re-reads DATA as code in the current shell (arithmetic on a variable's value, a name
// operand's subscript, PS4 under xtrace) and bash 5.3 runs `${ cmd; }` there, so an alias can be defined without
// any alias command. r13 inverts the rule. A file is credited ONLY when every node of its parse tree is in a small,
// POSITIVE subset that is checked node kind by node kind (positive, below); any node kind, operator, builtin,
// option or name the subset does not list makes the helper exit 5 ("no units": the gate then judges the file by
// the whole-file rule). New parser node kinds fail closed by default (the switches have no permissive default and
// a second pass over every node rejects any type outside nodeKindsOK).
//
// The subset, rule by rule (P1-P10). Each rule is there because the real shell can otherwise run text that the
// static parse did not show as code, or read the rest of the script from somewhere else:
//
//	P1 node kinds: statements, simple commands, if / while / until / for-in / case, { } and ( ) groups, && || |
//	   |& lists, function definitions, [[ ]] (P7), local / export / readonly (P5), time. Never: arithmetic of any
//	   kind ($(( )), (( )), let, for (( )), $[ ]), coproc, select, arrays, process substitution, extended globs,
//	   backquotes, $"..", bash 5.3 function substitution ${ ..; } / ${| ..; }.
//	P2 words: literals, '..', $'..', "..", plain parameter expansion ($name ${name} and the special parameters),
//	   ${name-w} ${name:-w} ${name+w} ${name:+w} ${name?w} ${name:?w} ${name#w} ${name##w} ${name%w} ${name%%w}
//	   (w recursively in the subset), $( ) whose statements are in the subset, and a subscript that is a decimal
//	   literal, @ or * in an expansion (${BASH_SOURCE[0]}). Never: any other subscript, ${!..},
//	   ${#..}, slices, replacements, case modifiers, ${x@..}, ${x=w} / ${x:=w}.
//	P3 command words: a STATIC literal (quote removal, $'..' decoded, no expansion, no glob / brace / tilde
//	   character). It is a function defined in the file, a builtin on the safe list (P4), or an external command.
//	   Any other builtin (read, mapfile, printf -v, getopts, declare, typeset, let, eval, ., source, trap, alias,
//	   unalias, enable, builtin, hash, fc, bind, ...) and a reserved word used as a command name fail closed.
//	P4 safe builtins and their argument rules: : true false echo pwd times cd kill umask exit return shift break
//	   continue ulimit type (free arguments; measured: none of them evaluates an argument as arithmetic or code);
//	   printf (a static first argument that is not an option other than --); test / [ (no -v; a computed word may
//	   not stand where an operator could be, see testArgs); set (static options from a short list until the first
//	   operand or --; posix, keyword, monitor and every unlisted option fail closed); shopt (-s/-u/-q of a short
//	   list of glob options); unset (static plain names); wait (no -p; computed operands only after --);
//	   command -v / -V; exec WITH a static command (the shell is replaced and reads nothing more; exec without a
//	   command fails closed).
//	P5 assignments (prefix, local / export / readonly): a plain name, no subscript, no array, and not a shell
//	   variable the shell gives a meaning (denied: every variable bash 5.3 documents under "Shell Variables" and
//	   every BASH* / COMP_* / READLINE_* name, PATH included; allowed: HOME TMPDIR CDPATH SHELL COLUMNS LINES PWD
//	   OLDPWD; LANG / LC_* only as the prefix of an external command). local / export / readonly take no options.
//	P6 function definitions: a plain name that is not a builtin or a reserved word; the body is checked as if it
//	   ran where the shell's standard input is the script (P8).
//	P7 [[ ]]: string, pattern, regex and file operators only; never -v and never the arithmetic -eq family.
//	P8 standard input: when the script itself is read on stdin (sh < file, curl | sh), any command that reads stdin
//	   consumes the rest of the script, so later text starts at a point the static parse did not see (measured:
//	   `head -c 10 >/dev/null` before a `#xxxxxxxx echo hi |` comment line makes bash --posix run `echo hi | tr ..`
//	   with the next line). A command that may read stdin (every external command except a short list that never
//	   does: mkdir rmdir chmod chown chgrp touch basename dirname sleep uname mktemp realpath readlink id whoami
//	   nproc printenv ls true false) is credited only where its stdin is NOT the shell's: a later element of a
//	   pipeline, or a command whose LAST redirection of fd 0 is a here-document, a here-string or <&- (the shell
//	   applies redirections left to right, so <<E </dev/stdin reads the script). A `< file` redirection does not
//	   count (the file can be a committed symlink to /dev/stdin). A background command is NOT away (r13 round 5,
//	   review r4 F3: bash opens an explicit </dev/stdin after its implicit </dev/null, measured). rm is on the list
//	   only with static -r/-R/-f/-v/-d options and every computed operand after `--` (rm -i reads).
//	P9 redirections: numeric file descriptors only (no {var}); output to a file (> >> >| &> &>>) on a descriptor
//	   other than 0; >& only onto 1 or 2 or to close (>&1 >&2 >&-), never on fd 0; <& only to close (<&-); input
//	   (< <>) and here-documents only on fd 0, and <> never on an explicit fd 0. Measured (review r4 F2): a copy of
//	   fd 0 made with 3>&0 is restored after the here-document by 0>&3, or read by path (/dev/fd/3), and the
//	   command then reads the script.
//	P10 static words (r13 round 5, review r4 F1): a word is static only when every shell decodes it to the same
//	   bytes: no NUL after decoding (bash ends the word there: [ $'-v\0' .. ] is test -v), no \c (\c? is 0x7f in
//	   bash) and no \u / \U (their decoding depends on the locale) inside $'..'.
//
// The ways the shell can read the script or a word differently from this static parse, and how each is handled
// (r13 round 5 enumeration, each with a census family in tests/units_r13_census.py or a pinned refusal):
//	R1 a command reads the script on stdin: P8 (F1 census family, F4 order-*, bg-*).        refused
//	R2 a copy of stdin on another descriptor, restored or read by path: P9 (F4 dup-*, fd3-*). refused
//	R3 an external program opens the shell's descriptor by its own path (/proc/$$/fd/0, /proc/$PPID/fd/0) or
//	   rewrites the script file: an external program is arbitrary code.                       stated limit
//	R4 data run as code: arithmetic, subscripts, test -v, ${x@P}, PS4, traps, eval, ., alias: P1-P5 (F2 family). refused
//	R5 a word decoded differently: NUL truncation, locale-dependent \u, \c: P10 (F4 nul-*, u-eval). refused
//	R6 a dialect difference: dash does not decode $'..' (the posix parse reads it as dash does) and the posix
//	   file is also parsed as bash (bash --posix): main, cross-parse.                         modelled
//	R7 the parser and bash split the bytes differently (here-documents, quoting, continuation): hdocEnd and the
//	   reviewer's 2201-shape differential; a NUL byte in the file is refused (main).          modelled, measured
//	R8 the environment: inherited PATH, BASH_ENV / ENV, exported functions, a non-UTF-8 multibyte locale.
//	                                                                                         stated limit

// Stated limits: the subset is a claim about bash 5.3 and dash, measured against them (tests/
// units_runtime_grammar_census.py and the r13 adversarial census); the external no-stdin list is a claim about the
// usual GNU / busybox programs and about PATH (PATH is denied in the file; an inherited PATH, exported functions
// and a non-UTF-8 multibyte locale belong to the runner's environment, not to the file); a script that rewrites
// its own file at run time is not modelled.

// denyNames (P5): every variable bash 5.3 documents under "Shell Variables" (bash.1, measured 2026-11-04: 112
// names), plus PATH; minus the allowed names below. A name with a BASH, COMP_ or READLINE_ prefix is denied too.
var denyNames = setOf("_ auto_resume BASH BASH_ALIASES BASH_ARGC BASH_ARGV BASH_ARGV0 BASH_CMDS BASH_COMMAND " +
	"BASH_COMPAT BASH_ENV BASH_EXECUTION_STRING BASH_LINENO BASH_LOADABLES_PATH BASH_MONOSECONDS BASHOPTS BASHPID " +
	"BASH_REMATCH BASH_SOURCE BASH_SUBSHELL BASH_TRAPSIG BASH_VERSINFO BASH_VERSION BASH_XTRACEFD CHILD_MAX " +
	"COMP_CWORD COMP_KEY COMP_LINE COMP_POINT COMPREPLY COMP_TYPE COMP_WORDBREAKS COMP_WORDS COPROC DIRSTACK EMACS " +
	"ENV EPOCHREALTIME EPOCHSECONDS EUID EXECIGNORE FCEDIT FIGNORE FUNCNAME FUNCNEST GLOBIGNORE GLOBSORT GROUPS " +
	"histchars HISTCMD HISTCONTROL HISTFILE HISTFILESIZE HISTIGNORE HISTSIZE HISTTIMEFORMAT HOSTFILE HOSTNAME " +
	"HOSTTYPE IFS IGNOREEOF INPUTRC INSIDE_EMACS LINENO MACHTYPE MAIL MAILCHECK MAILPATH MAPFILE OPTARG OPTERR " +
	"OPTIND OSTYPE PATH PIPESTATUS POSIXLY_CORRECT PPID PROMPT_COMMAND PROMPT_DIRTRIM PS0 PS1 PS2 PS3 PS4 " +
	"RANDOM READLINE_ARGUMENT READLINE_LINE READLINE_MARK READLINE_POINT REPLY SECONDS SHELLOPTS SHLVL SRANDOM " +
	"TIMEFORMAT TMOUT UID TERM")

// allowNames: documented variables an assignment to which cannot run code or change how the shell reads text
var allowNames = setOf("HOME TMPDIR CDPATH SHELL COLUMNS LINES PWD OLDPWD")

// shellWords: bash 5.3 builtins (compgen -b), dash builtins, and reserved words (compgen -k)
var shellWords = setOf(". : [ alias bg bind break builtin caller cd chdir command compgen complete compopt continue " +
	"declare dirs disown echo enable eval exec exit export false fc fg getopts hash help history jobs kill let " +
	"local logout mapfile popd printf pushd pwd read readarray readonly return set shift shopt source suspend test " +
	"times trap true type typeset ulimit umask unalias unset wait " +
	"if then else elif fi case esac for select while until do done in function time { } ! [[ ]] coproc")

// freeBuiltins (P4): builtins whose arguments are free (measured with a funsub needle: no argument is evaluated
// as arithmetic or code, and none reads stdin)
var freeBuiltins = setOf(": true false echo pwd times cd kill umask exit return shift break continue ulimit type")

// noStdinExternals (P8): external programs that do not read their standard input whatever their arguments
var noStdinExternals = setOf("mkdir rmdir chmod chown chgrp touch basename dirname sleep uname mktemp realpath " +
	"readlink id whoami nproc printenv ls true false")

// setLettersOK / setOptsOK / shoptOK (P4)
const setLettersOK = "euxvfCabhnpTEBt"

var setOptsOK = setOf("errexit nounset xtrace verbose noglob noclobber allexport pipefail errtrace functrace " +
	"hashall braceexpand noexec physical notify")
var shoptOK = setOf("nullglob failglob dotglob globstar nocaseglob nocasematch inherit_errexit lastpipe")

// testBinOK: binary operators of test / [ (none evaluates an operand as code, measured)
var testBinOK = setOf("= == != < > -eq -ne -lt -le -gt -ge -nt -ot -ef -a -o")

// nodeKindsOK: every node type the subset admits (the second pass rejects any other, P1)
var nodeKindsOK = setOf("File Stmt Comment CallExpr Assign Word Lit SglQuoted DblQuoted ParamExp " +
	"CmdSubst Redirect BinaryCmd IfClause WhileClause ForClause WordIter CaseClause CaseItem Block Subshell " +
	"FuncDecl TestClause BinaryTest UnaryTest ParenTest DeclClause TimeClause")

func setOf(s string) map[string]bool {
	m := map[string]bool{}
	for _, w := range strings.Fields(s) {
		m[w] = true
	}
	return m
}

func ident(s string) bool {
	if s == "" {
		return false
	}
	for i, ch := range s {
		if !(ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (i > 0 && ch >= '0' && ch <= '9')) {
			return false
		}
	}
	return true
}

func funcName(s string) bool {
	return ident(strings.ReplaceAll(s, "-", "_")) && !strings.HasPrefix(s, "-")
}

// denied (P5): an assignment to this name is not in the subset
func denied(name string, prefixOfExternal bool) bool {
	if allowNames[name] {
		return false
	}
	if name == "LANG" || strings.HasPrefix(name, "LC_") {
		return !prefixOfExternal
	}
	return denyNames[name] || strings.HasPrefix(name, "BASH") || strings.HasPrefix(name, "COMP_") ||
		strings.HasPrefix(name, "READLINE_")
}

type checker struct {
	lang   syntax.LangVariant
	defIdx map[string]int // name -> index (in File.Stmts) of its first top-level definition
	at     int            // index of the top-level statement being checked
	inBody bool           // checking the body of the function defined at index at
	why    string
}

// isFunc: a call of name runs a function defined in the file. Only top-level, unconditional definitions count
// (P6); a call made before the definition has run finds a PATH program of the same name instead, so it is an
// external command for P8.
func (c *checker) isFunc(name string) bool {
	i, ok := c.defIdx[name]
	return ok && (i < c.at || (c.inBody && i <= c.at))
}

func (c *checker) fail(n syntax.Node, what string) {
	if c.why != "" {
		return
	}
	ln := uint(0)
	if n != nil && n.Pos().IsValid() {
		ln = n.Pos().Line()
	}
	c.why = fmt.Sprintf("line %d: %s (outside the r13 positive subset: not modelled)", ln, what)
}

func kind(n syntax.Node) string {
	return strings.TrimPrefix(fmt.Sprintf("%T", n), "*syntax.")
}

func (c *checker) stmts(ss []*syntax.Stmt, stdin bool) {
	for _, s := range ss {
		c.stmt(s, stdin)
	}
}

// fd0 (P8): the redirection sets the command's standard input (fd 0)
func fd0(r *syntax.Redirect) bool {
	if r.N != nil {
		return r.N.Value == "0"
	}
	switch r.Op {
	case syntax.RdrIn, syntax.RdrInOut, syntax.Hdoc, syntax.DashHdoc, syntax.WordHdoc, syntax.DplIn:
		return true
	}
	return false
}

// inputAway (P8): the redirection gives the command a standard input that is not the shell's (a here-document,
// a here-string, or <&- close). Only the LAST redirection of fd 0 counts: the shell applies them left to right.
func inputAway(r *syntax.Redirect) bool {
	switch r.Op {
	case syntax.Hdoc, syntax.DashHdoc, syntax.WordHdoc:
		return true
	case syntax.DplIn:
		v, ok := static(r.Word)
		return ok && v == "-"
	}
	return false
}

// redirect (P9, r13 round 5, review r4 F2 class-wide): a credited command's redirections can only write
// (> >> >| &> &>> to a file), duplicate output onto 1 or 2 or close it (>&1 >&2 >&-), give fd 0 a here-document,
// a here-string, a file (< file: not stdin-away, P8) or close it (<&-). Any redirection that reads into another
// descriptor (3<file, 3<>file), duplicates fd 0 or onto fd 0 (3>&0, 0>&3, 0>&1), or writes / opens fd 0 for
// writing (0>file, 0<>file) is outside the subset: a copy of the shell's stdin can be restored as fd 0 after the
// here-document (dd 3>&0 <<E 0>&3 reads the script, measured) or read by path (/dev/fd/3).
func (c *checker) redirect(r *syntax.Redirect, stdin bool) {
	n := ""
	if r.N != nil {
		for _, ch := range r.N.Value {
			if ch < '0' || ch > '9' {
				c.fail(r, "a {variable} file-descriptor redirection")
				return
			}
		}
		n = r.N.Value
	}
	switch r.Op {
	case syntax.RdrOut, syntax.AppOut, syntax.RdrClob, syntax.RdrAll, syntax.AppAll:
		if n == "0" {
			c.fail(r, "a redirection that opens fd 0 for writing")
			return
		}
	case syntax.RdrIn, syntax.RdrInOut:
		if n != "" && n != "0" {
			c.fail(r, "an input redirection to a descriptor other than 0 (it can hold a copy of the script)")
			return
		}
		if r.Op == syntax.RdrInOut && n == "0" {
			c.fail(r, "a <> redirection of fd 0")
			return
		}
	case syntax.Hdoc, syntax.DashHdoc, syntax.WordHdoc:
		if n != "" && n != "0" {
			c.fail(r, "a here-document on a descriptor other than 0")
			return
		}
	case syntax.DplOut:
		if v, ok := static(r.Word); n == "0" || !ok || (v != "1" && v != "2" && v != "-") {
			c.fail(r, "a >& redirection other than >&1, >&2 or >&- on a descriptor other than 0")
			return
		}
	case syntax.DplIn:
		if v, ok := static(r.Word); !ok || v != "-" {
			c.fail(r, "a <& redirection other than <&- (close)")
			return
		}
	default:
		c.fail(r, "the redirection operator "+r.Op.String())
		return
	}
	if r.Word != nil {
		c.word(r.Word, stdin)
	}
	if r.Hdoc != nil {
		c.word(r.Hdoc, stdin)
	}
}

// stmt (P8): r13 round 5 (review r4 F3): a background command is NOT stdin-away. bash opens an explicit
// redirection (</dev/stdin) after the implicit </dev/null, and the implicit one depends on job control; the
// background statement is checked exactly as a foreground one.
func (c *checker) stmt(s *syntax.Stmt, stdin bool) {
	if s.Coprocess || s.Disown {
		c.fail(s, "a coprocess or disown terminator")
		return
	}
	in := stdin
	for _, r := range s.Redirs {
		c.redirect(r, stdin)
		if fd0(r) {
			in = stdin && !inputAway(r)
		}
	}
	c.command(s.Cmd, in, stdin)
}

func (c *checker) command(cmd syntax.Command, in, outer bool) {
	switch x := cmd.(type) {
	case nil:
	case *syntax.CallExpr:
		c.call(x, in, outer)
	case *syntax.IfClause:
		for ic := x; ic != nil; ic = ic.Else {
			c.stmts(ic.Cond, in)
			c.stmts(ic.Then, in)
		}
	case *syntax.WhileClause:
		c.stmts(x.Cond, in)
		c.stmts(x.Do, in)
	case *syntax.ForClause:
		wi, ok := x.Loop.(*syntax.WordIter)
		if x.Select || !ok {
			c.fail(x, "a select or arithmetic for loop")
			return
		}
		if wi.Name == nil || !ident(wi.Name.Value) || denied(wi.Name.Value, false) {
			c.fail(x, "a for loop over a name outside P5")
			return
		}
		for _, w := range wi.Items {
			c.word(w, in)
		}
		c.stmts(x.Do, in)
	case *syntax.CaseClause:
		c.word(x.Word, in)
		for _, it := range x.Items {
			for _, p := range it.Patterns {
				c.word(p, in)
			}
			c.stmts(it.Stmts, in)
		}
	case *syntax.Block:
		c.stmts(x.Stmts, in)
	case *syntax.Subshell:
		c.stmts(x.Stmts, in)
	case *syntax.BinaryCmd:
		switch x.Op {
		case syntax.AndStmt, syntax.OrStmt:
			c.stmt(x.X, in)
			c.stmt(x.Y, in)
		case syntax.Pipe, syntax.PipeAll:
			c.stmt(x.X, in)
			c.stmt(x.Y, false) // a later pipeline element reads the pipe
		default:
			c.fail(x, "the list operator "+x.Op.String())
		}
	case *syntax.FuncDecl:
		c.fail(x, "a function defined inside another statement (only top-level definitions are in the subset)")
	case *syntax.TestClause:
		c.testExpr(x.X, in)
	case *syntax.DeclClause:
		if x.Variant == nil || !(x.Variant.Value == "local" || x.Variant.Value == "export" ||
			x.Variant.Value == "readonly") {
			c.fail(x, "a declaration builtin other than local / export / readonly")
			return
		}
		for _, a := range x.Args {
			if a.Naked && a.Name == nil {
				c.fail(x, "a "+x.Variant.Value+" with an option or a computed name")
				return
			}
			c.assign(a, outer, false)
		}
	case *syntax.TimeClause:
		if x.Stmt != nil {
			c.stmt(x.Stmt, in)
		}
	default:
		c.fail(cmd, "a "+kind(cmd)+" command")
	}
}

func (c *checker) assign(a *syntax.Assign, stdin bool, prefixOfExternal bool) {
	if a.Name == nil || a.Index != nil || a.Array != nil || !ident(a.Name.Value) {
		c.fail(a, "an assignment that is not to a plain name")
		return
	}
	if denied(a.Name.Value, prefixOfExternal) {
		c.fail(a, "an assignment to the shell variable "+a.Name.Value)
		return
	}
	if a.Value != nil {
		c.word(a.Value, stdin)
	}
}

func (c *checker) word(w *syntax.Word, stdin bool) {
	if w == nil {
		return
	}
	c.parts(w.Parts, stdin)
}

func (c *checker) parts(ps []syntax.WordPart, stdin bool) {
	for _, p := range ps {
		switch x := p.(type) {
		case *syntax.Lit, *syntax.SglQuoted:
		case *syntax.DblQuoted:
			if x.Dollar {
				c.fail(x, "a $\"..\" locale string")
				return
			}
			c.parts(x.Parts, stdin)
		case *syntax.ParamExp:
			c.param(x, stdin)
		case *syntax.CmdSubst:
			if x.Backquotes || x.TempFile || x.ReplyVar {
				c.fail(x, "a backquote or function substitution")
				return
			}
			c.stmts(x.Stmts, stdin)
		default:
			c.fail(p, "a "+kind(p)+" word part")
			return
		}
	}
}

func (c *checker) param(x *syntax.ParamExp, stdin bool) {
	if x.Param == nil || x.Flags != nil || x.Excl || x.Length || x.Width || x.IsSet || x.NestedParam != nil ||
		!literalIndex(x.Index) || len(x.Modifiers) > 0 || x.Slice != nil || x.Repl != nil || x.Names != 0 {
		c.fail(x, "a parameter expansion other than $name / ${name} / ${name<op>word} (P2)")
		return
	}
	p := x.Param.Value
	if !ident(p) && !(len(p) == 1 && strings.Contains("@*#?$!-0123456789", p)) && !allDigits(p) {
		c.fail(x, "a parameter expansion of "+p)
		return
	}
	if x.Exp != nil {
		switch x.Exp.Op {
		case syntax.AlternateUnset, syntax.AlternateUnsetOrNull, syntax.DefaultUnset, syntax.DefaultUnsetOrNull,
			syntax.ErrorUnset, syntax.ErrorUnsetOrNull, syntax.RemSmallSuffix, syntax.RemLargeSuffix,
			syntax.RemSmallPrefix, syntax.RemLargePrefix:
			c.word(x.Exp.Word, stdin)
		default:
			c.fail(x, "the parameter expansion operator "+x.Exp.Op.String())
		}
	}
}

// literalIndex: no subscript, or a subscript that is a decimal literal, @ or * (${BASH_SOURCE[0]}): the shell
// evaluates the literal itself, never a variable's value (P2)
func literalIndex(e syntax.ArithmExpr) bool {
	if e == nil {
		return true
	}
	w, ok := e.(*syntax.Word)
	if !ok || len(w.Parts) != 1 {
		return false
	}
	l, ok := w.Parts[0].(*syntax.Lit)
	return ok && (allDigits(l.Value) || l.Value == "@" || l.Value == "*")
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}

func (c *checker) testExpr(e syntax.TestExpr, stdin bool) {
	switch x := e.(type) {
	case *syntax.Word:
		c.word(x, stdin)
	case *syntax.BinaryTest:
		switch x.Op {
		case syntax.TsReMatch, syntax.TsNewer, syntax.TsOlder, syntax.TsDevIno, syntax.AndTest, syntax.OrTest,
			syntax.TsMatchShort, syntax.TsMatch, syntax.TsNoMatch, syntax.TsBefore, syntax.TsAfter:
		default:
			c.fail(x, "the [[ ]] operator "+x.Op.String()+" (arithmetic)")
			return
		}
		c.testExpr(x.X, stdin)
		c.testExpr(x.Y, stdin)
	case *syntax.UnaryTest:
		if x.Op == syntax.TsVarSet || x.Op == syntax.TsRefVar {
			c.fail(x, "the [[ ]] operator "+x.Op.String()+" (a name operand)")
			return
		}
		c.testExpr(x.X, stdin)
	case *syntax.ParenTest:
		c.testExpr(x.X, stdin)
	default:
		c.fail(e, "a "+kind(e)+" in [[ ]]")
	}
}

// wordShape: "static" (value known), "one" (exactly one field whatever its value), "many" (field count unknown)
func wordShape(w *syntax.Word) (string, string) {
	if v, ok := static(w); ok {
		return "static", v
	}
	if len(w.Parts) == 1 {
		if dq, ok := w.Parts[0].(*syntax.DblQuoted); ok {
			for _, p := range dq.Parts {
				if pe, ok := p.(*syntax.ParamExp); ok && pe.Param != nil &&
					(pe.Param.Value == "@" || pe.Param.Value == "*") {
					return "many", ""
				}
			}
			return "one", ""
		}
	}
	return "many", ""
}

// testArgs (P4): test / [ with no -v, and no computed word where the test grammar could read an operator
func (c *checker) testArgs(x syntax.Node, args []*syntax.Word, bracket bool) {
	if bracket {
		if len(args) == 0 {
			c.fail(x, "a [ without its closing ]")
			return
		}
		if v, ok := static(args[len(args)-1]); !ok || v != "]" {
			c.fail(x, "a [ whose last word is not a static ]")
			return
		}
		args = args[:len(args)-1]
	}
	shape := make([]string, len(args))
	val := make([]string, len(args))
	for i, a := range args {
		shape[i], val[i] = wordShape(a)
		if shape[i] == "many" {
			c.fail(x, "a test with a word whose number of fields is not known")
			return
		}
		if shape[i] == "static" && val[i] == "-v" {
			c.fail(x, "a test -v (a name operand)")
			return
		}
	}
	st := func(i int) bool { return shape[i] == "static" }
	var two func(i int) bool
	two = func(i int) bool { return st(i) } // the operator position is static and not -v
	switch n := len(args); {
	case n <= 1:
	case n == 2:
		if !two(0) {
			c.fail(x, "a two-word test whose first word is computed")
		}
	case n == 3:
		switch {
		case st(1) && testBinOK[val[1]]:
		case st(0) && val[0] == "!" && two(1):
		case st(0) && val[0] == "(" && st(2) && val[2] == ")":
		default:
			c.fail(x, "a three-word test whose operator position is computed")
		}
	default:
		for i := range args {
			if !st(i) {
				c.fail(x, "a test of four or more words with a computed word")
				return
			}
		}
	}
}

func (c *checker) setArgs(x syntax.Node, args []*syntax.Word) {
	for i := 0; i < len(args); i++ {
		v, ok := static(args[i])
		if !ok {
			c.fail(x, "a set with a computed word before its operands")
			return
		}
		if v == "--" || v == "-" || !(strings.HasPrefix(v, "-") || strings.HasPrefix(v, "+")) {
			return
		}
		for _, l := range v[1:] {
			if l == 'o' {
				if i+1 >= len(args) {
					return
				}
				i++
				o, ok := static(args[i])
				if !ok || !setOptsOK[o] {
					c.fail(x, "a set -o naming an option outside the subset ("+o+")")
					return
				}
			} else if !strings.ContainsRune(setLettersOK, l) {
				c.fail(x, fmt.Sprintf("a set option -%c outside the subset", l))
				return
			}
		}
	}
}

func (c *checker) shoptArgs(x syntax.Node, args []*syntax.Word) {
	for _, a := range args {
		v, ok := static(a)
		if !ok {
			c.fail(x, "a shopt with a computed word")
			return
		}
		if strings.HasPrefix(v, "-") {
			if len(v) < 2 || strings.Trim(v[1:], "supq") != "" {
				c.fail(x, "a shopt flag outside -s -u -q -p")
				return
			}
			continue
		}
		if !shoptOK[v] {
			c.fail(x, "a shopt option outside the subset ("+v+")")
			return
		}
	}
}

// declArgs: local / export / readonly as a simple command (the POSIX parse): NAME or NAME=word, no options
func (c *checker) declArgs(x syntax.Node, name string, args []*syntax.Word, stdin bool) {
	for _, w := range args {
		if lit, ok := w.Parts[0].(*syntax.Lit); ok && strings.Contains(lit.Value, "=") {
			n := lit.Value[:strings.IndexByte(lit.Value, '=')]
			if !ident(n) || denied(n, false) {
				c.fail(x, "a "+name+" of a name outside P5 ("+n+")")
				return
			}
			c.parts(w.Parts[1:], stdin)
			continue
		}
		v, ok := static(w)
		if !ok || !ident(v) || denied(v, false) {
			c.fail(x, "a "+name+" with an option, a computed name or a name outside P5")
			return
		}
	}
}

func (c *checker) call(x *syntax.CallExpr, in, outer bool) {
	if len(x.Args) == 0 {
		for _, a := range x.Assigns {
			c.assign(a, outer, false)
		}
		return
	}
	name, ok := static(x.Args[0])
	if !ok || name == "" {
		c.fail(x.Args[0], "a command word that is not a static literal")
		return
	}
	args := x.Args[1:]
	external := !c.isFunc(name) && !shellWords[name]
	for _, a := range x.Assigns {
		c.assign(a, outer, external)
	}
	for _, w := range args {
		c.word(w, outer)
	}
	if c.why != "" {
		return
	}
	switch {
	case c.isFunc(name):
	case freeBuiltins[name]:
	case name == "printf":
		if len(args) > 0 {
			v, ok := static(args[0])
			if !ok || (strings.HasPrefix(v, "-") && v != "--") {
				c.fail(x, "a printf whose first word is computed or an option (printf -v)")
			}
		}
	case name == "test" || name == "[":
		c.testArgs(x, args, name == "[")
	case name == "set":
		c.setArgs(x, args)
	case name == "shopt":
		c.shoptArgs(x, args)
	case name == "unset":
		for _, a := range args {
			v, ok := static(a)
			_, fn := c.defIdx[v]
			if !ok || fn || !(v == "-v" || ident(v)) {
				c.fail(x, "an unset of a computed, subscripted or function name, or unset -f")
				return
			}
		}
	case name == "wait":
		dd := false
		for _, a := range args {
			v, ok := static(a)
			switch {
			case ok && v == "--":
				dd = true
			case !ok && !dd:
				c.fail(x, "a wait with a computed word before --")
				return
			case ok && !dd && strings.HasPrefix(v, "-") && strings.Contains(v, "p"):
				c.fail(x, "a wait -p (a name operand)")
				return
			}
		}
	case name == "command":
		if len(args) == 0 {
			return
		}
		if v, ok := static(args[0]); !ok || (v != "-v" && v != "-V") {
			c.fail(x, "a command other than command -v / -V")
		}
	case name == "exec":
		if len(args) == 0 {
			c.fail(x, "an exec without a command (it changes the shell's own file descriptors)")
			return
		}
		if v, ok := static(args[0]); !ok || strings.HasPrefix(v, "-") || shellWords[v] {
			c.fail(x, "an exec whose command is computed, an option or a builtin")
		}
	case name == "local" || name == "export" || name == "readonly":
		c.declArgs(x, name, args, outer)
	case shellWords[name]:
		c.fail(x, "the builtin or reserved word "+name)
	default:
		if in && !c.noStdin(name, args) {
			c.fail(x, "the command "+name+" may read the shell's standard input (the script, when it is read on stdin)")
		}
	}
}

// noStdin (P8): the external command reads no standard input whatever its arguments
func (c *checker) noStdin(name string, args []*syntax.Word) bool {
	if noStdinExternals[name] {
		return true
	}
	if name != "rm" {
		return false
	}
	for _, a := range args {
		v, ok := static(a)
		if !ok {
			return false // a computed operand before -- could be -i
		}
		if v == "--" {
			return true
		}
		if strings.HasPrefix(v, "--") {
			if v != "--force" && v != "--recursive" && v != "--verbose" && v != "--dir" {
				return false
			}
		} else if strings.HasPrefix(v, "-") && strings.Trim(v[1:], "rRfvd") != "" {
			return false
		}
	}
	return true
}

// unmodelled: "" when the file is inside the r13 positive subset (P1-P10 above), else the first reason.
func unmodelled(f *syntax.File, lang syntax.LangVariant) string {
	if lang != syntax.LangPOSIX && lang != syntax.LangBash {
		return "line 0: the mksh dialect (outside the r13 positive subset: not modelled)"
	}
	c := &checker{lang: lang, defIdx: map[string]int{}}
	for i, s := range f.Stmts {
		if fd, ok := s.Cmd.(*syntax.FuncDecl); ok && fd.Name != nil {
			if _, seen := c.defIdx[fd.Name.Value]; !seen {
				c.defIdx[fd.Name.Value] = i
			}
		}
	}
	for i, s := range f.Stmts {
		c.at = i
		fd, ok := s.Cmd.(*syntax.FuncDecl)
		if !ok {
			c.stmt(s, true)
			continue
		}
		if fd.Name == nil || len(fd.Names) > 0 || !funcName(fd.Name.Value) || shellWords[fd.Name.Value] {
			c.fail(fd, "a function whose name is not a plain name or shadows a builtin or reserved word")
		} else if len(s.Redirs) > 0 || s.Background || s.Negated || s.Coprocess || s.Disown {
			c.fail(fd, "a function definition with redirections or a terminator other than ;")
		}
		c.inBody = true
		c.stmt(fd.Body, true) // P6: the body may run where stdin is the script
		c.inBody = false
	}
	if c.why != "" {
		return c.why
	}
	syntax.Walk(f, func(n syntax.Node) bool { // P1 second pass: no node of a kind outside the subset anywhere
		if n != nil && c.why == "" && !nodeKindsOK[kind(n)] {
			c.fail(n, "a "+kind(n)+" node")
		}
		return c.why == ""
	})
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
