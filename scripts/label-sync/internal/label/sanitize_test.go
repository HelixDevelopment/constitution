package label

import (
	"strings"
	"testing"
	"unicode/utf8"
)

// Review finding 2: terminal-control injection through label fields.
var hostile = map[string]string{
	"OSC0 title":      "x\x1b]0;PWNED\x07y",
	"OSC52 clipboard": "x\x1b]52;c;aGk=\x07y",
	"CSI clear":       "x\x1b[2Jy",
	"C1 OSC/ST utf8":  "x\u009d0;C1\u009cy",
	"C1 raw byte":     "x\x9d0;C1\x9cy",
	"NUL":             "x\x00y",
	"DEL":             "x\x7fy",
	"bidi override":   "x‮gnp.exe‬y",
	"bidi isolate":    "x⁦z⁩y",
	"tab cr lf":       "x\t\r\ny",
}

func hasControl(s string) bool {
	for _, r := range s {
		if r < 0x20 || r == 0x7f || (r >= 0x80 && r <= 0x9f) || r == utf8.RuneError ||
			(r >= 0x202a && r <= 0x202e) || (r >= 0x2066 && r <= 0x2069) || r == 0x200e || r == 0x200f || r == 0x061c {
			return true
		}
	}
	return !utf8.ValidString(s)
}

func TestComposeStripsTerminalControls(t *testing.T) {
	for name, v := range hostile {
		t.Run(name, func(t *testing.T) {
			l := Compose(Fields{Track: "1", Branch: v, Alias: v, Model: v, Effort: v})
			if hasControl(l) {
				t.Fatalf("control/bidi/invalid bytes survive in label: %q", l)
			}
			if err := ValidateFull(l); err != nil {
				t.Fatalf("label invalid after sanitising: %v (%q)", err, l)
			}
		})
	}
}

func TestComposeCapsFieldLength(t *testing.T) {
	l := Compose(Fields{Track: "1", Branch: strings.Repeat("b", 1<<20), Alias: "a", Model: "m", Effort: "e"})
	if utf8.RuneCountInString(l) > 4*MaxFieldRunes+40 {
		t.Fatalf("label not capped: %d runes", utf8.RuneCountInString(l))
	}
}
