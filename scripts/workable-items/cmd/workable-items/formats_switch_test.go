// formats_switch_test.go — behavioural tests for the exporter's read of the
// constitution formats-export switch (operator order 2026-10-26).
//
// Real command dispatch, real SQLite, the REAL shared shell library
// (formats_export_lib.sh) answering the switch question. Only the converter is
// faked: a stub `pandoc` / `weasyprint` on PATH writes the -o target, so these
// tests need no real pandoc and prove "a sibling file was (not) produced" by
// the file's existence. The oracle for precedence is written independently in
// Go (expectedPrecedence) and compared with what the real library returns.
//
// Test names start with TestFormatsSwitch so the paired-mutation harness
// (scripts/testing/test_workable_items_export_formats_switch.sh) can select them.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// realFormatsLib locates the real formats_export_lib.sh relative to this test
// file: .../scripts/workable-items/cmd/workable-items -> .../scripts/.
func realFormatsLib(t *testing.T) string {
	t.Helper()
	if p := os.Getenv("FORMATS_SWITCH_TEST_LIB"); p != "" { // mutation harness seam
		return p
	}
	p, err := filepath.Abs(filepath.Join("..", "..", "..", formatsLibName))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(p); err != nil {
		t.Fatalf("real %s not found at %s: %v", formatsLibName, p, err)
	}
	return p
}

type fmtCase struct {
	conf    string // "" => file missing; else "true"/"false"/"garbage"
	policy  string // "" => file missing; else file body
	env     string // DOCS_EXPORT value ("" = unset/empty)
	libPath string // "" => real lib; "MISSING" => nonexistent path
}

// setupFormatsEnv installs the stubs and the env for one case and returns.
func setupFormatsEnv(t *testing.T, c fmtCase) {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	stub := "#!/bin/sh\nout=''\nwhile [ $# -gt 0 ]; do if [ \"$1\" = \"-o\" ]; then out=\"$2\"; fi; shift; done\nprintf 'stub' > \"$out\"\n"
	for _, n := range []string{"pandoc", "weasyprint"} {
		if err := os.WriteFile(filepath.Join(bin, n), []byte(stub), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	// bash/sed/grep/git come from the standard dirs; the real pandoc is NOT on this PATH.
	t.Setenv("PATH", bin+":/usr/bin:/bin")

	conf := filepath.Join(dir, "formats_export.conf")
	if c.conf != "" {
		if err := os.WriteFile(conf, []byte("formats_export="+c.conf+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	} // else: path stays non-existent
	policy := filepath.Join(dir, "doc_export.policy")
	if c.policy != "" {
		if err := os.WriteFile(policy, []byte(c.policy), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("FORMATS_EXPORT_CONF", conf)
	t.Setenv("FORMATS_EXPORT_POLICY", policy)
	t.Setenv("DOCS_EXPORT", c.env)
	switch c.libPath {
	case "":
		t.Setenv("WORKABLE_ITEMS_FORMATS_LIB", realFormatsLib(t))
	case "MISSING":
		t.Setenv("WORKABLE_ITEMS_FORMATS_LIB", filepath.Join(dir, "no-such-lib.sh"))
	default:
		t.Setenv("WORKABLE_ITEMS_FORMATS_LIB", c.libPath)
	}
}

var siblingNames = []string{
	"Issues.html", "Issues.docx", "Issues.pdf",
	"Fixed.html", "Fixed.docx", "Fixed.pdf",
	"Issues_Summary.html", "Issues_Summary.docx", "Issues_Summary.pdf",
	"Fixed_Summary.html", "Fixed_Summary.docx", "Fixed_Summary.pdf",
}

func countSiblings(dir string) int {
	n := 0
	for _, s := range siblingNames {
		if _, err := os.Stat(filepath.Join(dir, s)); err == nil {
			n++
		}
	}
	return n
}

func runExportCase(t *testing.T, c fmtCase, extra ...string) (rc int, out, outDir string) {
	t.Helper()
	setupFormatsEnv(t, c)
	db := newTestDB(t)
	outDir = t.TempDir()
	args := append([]string{"--db", db, "--out-dir", outDir}, extra...)
	rc, out = captureStdoutRun(t, func() int { return exportCmd(args) })
	for _, md := range []string{"Issues.md", "Fixed.md", "Issues_Summary.md", "Fixed_Summary.md"} {
		if _, err := os.Stat(filepath.Join(outDir, md)); err != nil {
			t.Fatalf("Markdown %s must always be written: %v", md, err)
		}
	}
	return rc, out, outDir
}

// expectedPrecedence is the INDEPENDENT oracle: env > repo policy > conf > false.
func expectedPrecedence(c fmtCase) bool {
	switch strings.ToLower(c.env) {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	}
	for _, ln := range strings.Split(c.policy, "\n") {
		if strings.TrimSpace(ln) == "enabled=1" {
			return true
		}
	}
	return strings.ToLower(c.conf) == "true"
}

// TestFormatsSwitch_DefaultOffWithPandocPresent: the reported defect. Conf says
// false, nothing else set, converters present on PATH: Markdown only + honest line.
func TestFormatsSwitch_DefaultOffWithPandocPresent(t *testing.T) {
	rc, out, dir := runExportCase(t, fmtCase{conf: "false"})
	if rc != exitOK {
		t.Fatalf("rc=%d", rc)
	}
	if n := countSiblings(dir); n != 0 {
		t.Errorf("default (switch off) produced %d sibling file(s); must produce 0", n)
	}
	if !strings.Contains(out, "formats export disabled") {
		t.Errorf("missing honest 'formats export disabled' line; got:\n%s", out)
	}
}

// TestFormatsSwitch_PrecedenceMatrix: every combination of env x policy x conf,
// real library vs the independent Go oracle (siblings produced iff oracle says on).
func TestFormatsSwitch_PrecedenceMatrix(t *testing.T) {
	for _, env := range []string{"", "1", "0", "TRUE", "off", "garbage"} {
		for _, pol := range []string{"", "enabled=1\n", "enabled=0\n", "# enabled=1\n"} {
			for _, conf := range []string{"", "false", "true", "garbage"} {
				c := fmtCase{conf: conf, policy: pol, env: env}
				name := "env=" + env + "/pol=" + strings.TrimSpace(pol) + "/conf=" + conf
				t.Run(name, func(t *testing.T) {
					_, _, dir := runExportCase(t, c)
					want := 0
					if expectedPrecedence(c) {
						want = len(siblingNames)
					}
					if got := countSiblings(dir); got != want {
						t.Errorf("siblings=%d want %d (oracle enabled=%v)", got, want, expectedPrecedence(c))
					}
				})
			}
		}
	}
}

// TestFormatsSwitch_EnvOverrideWinsBothWays: DOCS_EXPORT=1 over conf false; =0 over conf true.
func TestFormatsSwitch_EnvOverrideWinsBothWays(t *testing.T) {
	_, _, dir := runExportCase(t, fmtCase{conf: "false", env: "1"})
	if n := countSiblings(dir); n != len(siblingNames) {
		t.Errorf("DOCS_EXPORT=1 over conf=false: siblings=%d want %d", n, len(siblingNames))
	}
	_, _, dir = runExportCase(t, fmtCase{conf: "true", env: "0"})
	if n := countSiblings(dir); n != 0 {
		t.Errorf("DOCS_EXPORT=0 over conf=true: siblings=%d want 0", n)
	}
}

// TestFormatsSwitch_PolicyOptInHonoured: repo policy enabled=1 turns it on when conf+env say nothing/false.
func TestFormatsSwitch_PolicyOptInHonoured(t *testing.T) {
	_, _, dir := runExportCase(t, fmtCase{conf: "false", policy: "enabled=1\n"})
	if n := countSiblings(dir); n != len(siblingNames) {
		t.Errorf("policy enabled=1: siblings=%d want %d", n, len(siblingNames))
	}
	_, _, dir = runExportCase(t, fmtCase{conf: "false", policy: "enabled=1\n", env: "0"})
	if n := countSiblings(dir); n != 0 {
		t.Errorf("env 0 must beat policy: siblings=%d want 0", n)
	}
}

// TestFormatsSwitch_FailClosed: a missing or unparsable conf, a missing library,
// all mean OFF with an honest announcement.
func TestFormatsSwitch_FailClosed(t *testing.T) {
	cases := map[string]fmtCase{
		"missing-conf":    {conf: ""},
		"garbage-conf":    {conf: "garbage"},
		"missing-library": {conf: "true", libPath: "MISSING"}, // conf true but the reader is gone
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			rc, out, dir := runExportCase(t, c)
			if rc != exitOK {
				t.Fatalf("rc=%d", rc)
			}
			if n := countSiblings(dir); n != 0 {
				t.Errorf("fail-closed case produced %d sibling file(s)", n)
			}
			if !strings.Contains(out, "formats export disabled") {
				t.Errorf("missing honest disabled line; got:\n%s", out)
			}
		})
	}
	// the missing-library case must say WHY (fail-closed), not pretend the conf said false
	_, out, _ := runExportCase(t, fmtCase{conf: "true", libPath: "MISSING"})
	if !strings.Contains(out, "fail-closed") {
		t.Errorf("missing-library notice must name fail-closed; got:\n%s", out)
	}
}

// TestFormatsSwitch_ExplicitFlags: --formats forces on, --no-formats forces off,
// both together is a usage error and writes nothing.
func TestFormatsSwitch_ExplicitFlags(t *testing.T) {
	_, _, dir := runExportCase(t, fmtCase{conf: "false", env: "0"}, "--formats")
	if n := countSiblings(dir); n != len(siblingNames) {
		t.Errorf("--formats: siblings=%d want %d", n, len(siblingNames))
	}
	_, _, dir = runExportCase(t, fmtCase{conf: "true", env: "1"}, "--no-formats")
	if n := countSiblings(dir); n != 0 {
		t.Errorf("--no-formats: siblings=%d want 0", n)
	}
	setupFormatsEnv(t, fmtCase{conf: "true"})
	db := newTestDB(t)
	out := t.TempDir()
	if rc := exportCmd([]string{"--db", db, "--out-dir", out, "--formats", "--no-formats"}); rc != exitUsage {
		t.Errorf("--formats --no-formats: rc=%d want exitUsage", rc)
	}
	if _, err := os.Stat(filepath.Join(out, "Issues.md")); err == nil {
		t.Errorf("conflicting flags must be rejected BEFORE any write")
	}
}

// TestFormatsSwitch_SubtaskExport: the second producer in this binary obeys the switch too.
func TestFormatsSwitch_SubtaskExport(t *testing.T) {
	for _, tc := range []struct {
		name  string
		c     fmtCase
		extra []string
		want  int
	}{
		{"default-off", fmtCase{conf: "false"}, nil, 0},
		{"env-on", fmtCase{conf: "false", env: "1"}, nil, 3},
		{"flag-on", fmtCase{conf: "false", env: "0"}, []string{"--formats"}, 3},
		{"no-formats-beats-env", fmtCase{conf: "true", env: "1"}, []string{"--no-formats"}, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			setupFormatsEnv(t, tc.c)
			db, child := newTestDBWithSubtask(t)
			out := filepath.Join(t.TempDir(), "issues")
			args := append([]string{"--subtask", child, "--db", db, "--out-dir", out}, tc.extra...)
			rc, stdout := captureStdoutRun(t, func() int { return subtaskExportCmd(args) })
			if rc != exitOK {
				t.Fatalf("rc=%d", rc)
			}
			dir := filepath.Join(out, "ATM-300", "sessions", "001")
			n := 0
			for _, b := range []string{"Session", "Diary", "Summary"} {
				for _, e := range []string{".html", ".docx", ".pdf"} {
					if _, err := os.Stat(filepath.Join(dir, b+e)); err == nil {
						n++
					}
				}
			}
			wantFiles := 0
			if tc.want > 0 {
				wantFiles = 9 // 3 docs x html/docx/pdf
			}
			if n != wantFiles {
				t.Errorf("sibling files=%d want %d", n, wantFiles)
			}
			if tc.want == 0 && tc.name == "default-off" && !strings.Contains(stdout, "formats export disabled") {
				t.Errorf("missing honest disabled line:\n%s", stdout)
			}
		})
	}
}

// TestFormatsSwitch_ParseResolve: only the exact token "1" enables; everything
// else (empty, junk, wrong arity, "true") is fail-closed.
func TestFormatsSwitch_ParseResolve(t *testing.T) {
	for in, want := range map[string]bool{
		"1 env\n":                 true,
		"1 constitution-default":  true,
		"0 env":                   false,
		"0 fail-closed":           false,
		"":                        false,
		"\n":                      false,
		"true env":                false,
		"1":                       false,
		"1 env extra":             false,
		"11 env":                  false,
		"yes policy":              false,
		"garbage garbage garbage": false,
	} {
		if got := parseFormatsResolve(in).Enabled; got != want {
			t.Errorf("parseFormatsResolve(%q).Enabled = %v, want %v", in, got, want)
		}
	}
}
