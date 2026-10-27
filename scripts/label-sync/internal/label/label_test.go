package label

import (
	"os"
	"path/filepath"
	"testing"
)

func TestComposeTable(t *testing.T) {
	cases := []struct {
		name string
		in   Fields
		want string
	}{
		{"full", Fields{"3", "feature/x", "claude2", "opus", "xhigh"}, "(T3/feature/x - claude2 - opus - xhigh)"},
		{"T prefix stripped", Fields{"T3", "main", "claude1", "sonnet", "high"}, "(T3/main - claude1 - sonnet - high)"},
		{"all unknown", Fields{}, "(T?/? - ? - ? - ?)"},
		{"non numeric track", Fields{"abc", "main", "a", "m", "e"}, "(T?/main - a - m - e)"},
		{"paren in branch sanitised", Fields{"1", "we)ird", "a", "m", "e"}, "(T1/we_ird - a - m - e)"},
		{"newline in alias sanitised", Fields{"1", "b", "a\nb", "m", "e"}, "(T1/b - a_b - m - e)"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Compose(c.in)
			if got != c.want {
				t.Fatalf("got %q want %q", got, c.want)
			}
			if err := ValidateFull(got); err != nil {
				t.Fatalf("composed label must validate: %v", err)
			}
		})
	}
}

func TestValidateTable(t *testing.T) {
	cases := []struct {
		label string
		ok    bool
		full  bool
	}{
		{"(T1/main - claude1 - opus - high)", true, true},
		{"(T1/main - claude1 - opus - high) ", true, true},
		{"(T?/? - ? - ? - ?)", true, true},
		{"(T1/main - claude1 - opus)", true, false},
		{"(T1/main - claude1)", true, false},
		{"(T12/feature/a-b - prov-x - m - low)", true, true},
		// malformed
		{"", false, false},
		{"T1/main - a - b - c", false, false},
		{"(Tx/main - a - b - c)", false, false},
		{"(T/main - a - b - c)", false, false},
		{"(T1/main)", false, false},
		{"(T1/main - a - b - c - d - e)", false, false},
		{"(T1/main -  - b - c)", false, false},
		{"(T1/main - a - b - c)extra", false, false},
		{"(T1/main - a - b - c)\n(T1/x - a - b - c)", false, false},
		{"(T1/main - a - b - c", false, false},
	}
	for _, c := range cases {
		err := Validate(c.label)
		if (err == nil) != c.ok {
			t.Errorf("Validate(%q) err=%v want ok=%v", c.label, err, c.ok)
		}
		if c.ok {
			if (ValidateFull(c.label) == nil) != c.full {
				t.Errorf("ValidateFull(%q) mismatch want %v", c.label, c.full)
			}
		}
	}
}

func TestParseRoundTrip(t *testing.T) {
	f := Fields{"4", "feature/label-sync", "claude2", "sonnet", "xhigh"}
	got, n, err := Parse(Compose(f))
	if err != nil || n != 5 || got != f {
		t.Fatalf("got %+v n=%d err=%v", got, n, err)
	}
	g, n, err := Parse("(T1/main - claude1 - opus)") // 4-field legacy
	if err != nil || n != 4 || g.Alias != "claude1" || g.Model != "opus" || g.Effort != "" {
		t.Fatalf("4-field parse: %+v n=%d err=%v", g, n, err)
	}
	if _, _, err := Parse("garbage"); err == nil {
		t.Fatal("garbage must not parse")
	}
}

func fakeScript(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "labeler.sh")
	if err := os.WriteFile(p, []byte("#!/usr/bin/env bash\n"+body+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestDeriveDelegates(t *testing.T) {
	s := fakeScript(t, `printf '(T2/%s - %s - opus - high)\n' "$(basename "$PWD")" "${FAKE_ALIAS:-?}"`)
	dir := t.TempDir()
	f, err := Derive(s, dir, []string{"FAKE_ALIAS=claude7", "PATH=" + os.Getenv("PATH")})
	if err != nil {
		t.Fatal(err)
	}
	if f.Track != "2" || f.Alias != "claude7" || f.Model != "opus" || f.Effort != "high" || f.Branch != filepath.Base(dir) {
		t.Fatalf("unexpected %+v", f)
	}
}

func TestDeriveFailuresAreErrorsNotInventions(t *testing.T) {
	if _, err := Derive(fakeScript(t, `echo not-a-label`), t.TempDir(), nil); err == nil {
		t.Fatal("malformed labeler output must error")
	}
	if _, err := Derive(fakeScript(t, `exit 3`), t.TempDir(), nil); err == nil {
		t.Fatal("failing labeler must error")
	}
	if _, err := Derive("/nonexistent/labeler.sh", t.TempDir(), nil); err == nil {
		t.Fatal("missing labeler must error")
	}
}

func TestParseThreeField(t *testing.T) {
	g, n, err := Parse("(T1/main - claude1) ")
	if err != nil || n != 3 || g.Alias != "claude1" || g.Model != "" {
		t.Fatalf("3-field parse: %+v n=%d err=%v", g, n, err)
	}
}
