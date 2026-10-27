// Package label composes, parses, validates and derives the §11.4.182
// work-stream identity label:
//
//	(T<N>/<branch> - <alias> - <model> - <effort>)
//
// Derivation of the label from a live process is DELEGATED to the canonical
// labeler scripts/multitrack/track_branch_label.sh (single source of truth,
// §11.4.251) via Derive; this package never re-implements that derivation.
// Compose only assembles already-known fields and writes '?' for unknown
// ones (§11.4.6: never invent a value).
package label

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

// Fields are the five label components. Empty means unknown.
type Fields struct {
	Track  string // digits only, no leading "T"
	Branch string
	Alias  string
	Model  string
	Effort string
}

// outer shape: guard-hook compatible; inner structure checked by splitting.
const labelPattern = `^\(T([0-9]+|\?)/([^)\n]+)\) ?$`

var labelRE = regexp.MustCompile(labelPattern)

var trackDigits = regexp.MustCompile(`^[0-9]+$`)

// MaxFieldRunes caps every rendered label field (review finding 2).
const MaxFieldRunes = 128

// idRE is the closed id grammar for entity ids, parent ids and session ids.
var idRE = regexp.MustCompile(`^[A-Za-z0-9._:@/-]{1,160}$`)

// ValidID reports whether s is an acceptable entity/parent/session id.
func ValidID(s string) bool { return idRE.MatchString(s) }

// dangerous reports runes that can drive a terminal or reorder displayed
// text: C0 controls (incl. ESC, NUL, BEL), DEL, C1 controls (U+0080-U+009F),
// bidi embeddings/overrides/isolates/marks, and invalid UTF-8 (RuneError).
func dangerous(r rune) bool {
	switch {
	case r < 0x20, r == 0x7f, r >= 0x80 && r <= 0x9f: // MUT:sanitize
		return true
	case r >= 0x202a && r <= 0x202e, r >= 0x2066 && r <= 0x2069, r == 0x200e, r == 0x200f, r == 0x061c:
		return true
	case r == utf8.RuneError:
		return true
	}
	return false
}

// Clean removes every dangerous rune (see dangerous) and caps the result at
// max runes. It is safe to print to any terminal under any locale (an
// invalid byte such as a raw 0x9d is dropped, never passed through).
func Clean(s string, max int) string {
	var b strings.Builder
	n := 0
	for i := 0; i < len(s); {
		r, w := utf8.DecodeRuneInString(s[i:])
		i += w
		if dangerous(r) {
			continue
		}
		if max > 0 && n >= max {
			break
		}
		b.WriteRune(r)
		n++
	}
	return b.String()
}

// CleanText is Clean for multi-line human output: it keeps '\n' and '\t'
// and strips everything else dangerous, without a length cap.
func CleanText(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		r, w := utf8.DecodeRuneInString(s[i:])
		i += w
		if r == '\n' || r == '\t' || !dangerous(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func clean(s string) string {
	s = strings.NewReplacer("\n", "_", "\r", "_", "\t", "_").Replace(s)
	s = strings.TrimSpace(Clean(s, MaxFieldRunes))
	r := strings.NewReplacer(")", "_", " - ", "_")
	s = r.Replace(s)
	if s == "" {
		return "?"
	}
	return s
}

// Compose renders the 5-field label; unknown fields become '?'.
func Compose(f Fields) string {
	t := strings.TrimPrefix(strings.TrimSpace(f.Track), "T")
	if !trackDigits.MatchString(t) {
		t = "?"
	}
	return fmt.Sprintf("(T%s/%s - %s - %s - %s)", t, clean(f.Branch), clean(f.Alias), clean(f.Model), clean(f.Effort))
}

// split returns track and the 2..4 inner parts after "T<N>/".
func split(l string) (track string, parts []string, err error) {
	m := labelRE.FindStringSubmatch(l)
	if m == nil {
		return "", nil, fmt.Errorf("label %q does not match (T<N>/<branch> - <alias> [- <model> [- <effort>]])", l)
	}
	parts = strings.Split(m[2], " - ")
	if len(parts) < 2 || len(parts) > 4 {
		return "", nil, fmt.Errorf("label %q has %d fields after T<N>/, want 2..4", l, len(parts))
	}
	for _, p := range parts {
		if p == "" || strings.TrimSpace(p) != p {
			return "", nil, fmt.Errorf("label %q has an empty or space-padded field", l)
		}
	}
	return m[1], parts, nil
}

// Validate accepts the 3-, 4- and 5-field forms accepted by the §11.4.182
// guard hook (T/branch + alias [+ model [+ effort]]).
func Validate(l string) error {
	_, _, err := split(l)
	return err
}

// ValidateFull accepts only the current 5-field form.
func ValidateFull(l string) error {
	_, parts, err := split(l)
	if err != nil {
		return err
	}
	if len(parts) != 4 {
		return fmt.Errorf("label %q is not the 5-field form", l)
	}
	return nil
}

// Parse splits a valid label into Fields and reports the field count (3..5).
// Fields absent from a legacy form are left empty; '?' is returned as "?".
func Parse(l string) (Fields, int, error) {
	t, parts, err := split(l)
	if err != nil {
		return Fields{}, 0, err
	}
	f := Fields{Track: t, Branch: parts[0], Alias: parts[1]}
	if len(parts) > 2 {
		f.Model = parts[2]
	}
	if len(parts) > 3 {
		f.Effort = parts[3]
	}
	return f, len(parts) + 1, nil
}

// Derive runs the canonical labeler script in cwd with env (nil = inherit)
// and parses its single line of output. Any failure is an error; nothing is
// guessed.
func Derive(script, cwd string, env []string) (Fields, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", script)
	cmd.Dir = cwd
	if env != nil {
		cmd.Env = env
	}
	var out, errb bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errb
	if err := cmd.Run(); err != nil {
		return Fields{}, fmt.Errorf("labeler %s failed: %w (%s)", script, err, strings.TrimSpace(errb.String()))
	}
	line := strings.TrimRight(out.String(), "\r\n")
	if strings.Contains(line, "\n") || line == "" {
		return Fields{}, errors.New("labeler output is not exactly one line")
	}
	f, _, err := Parse(line)
	return f, err
}
