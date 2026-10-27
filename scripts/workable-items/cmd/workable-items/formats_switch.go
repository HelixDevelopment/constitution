// formats_switch.go — the exporter's read of the constitution "formats export"
// switch (operator order 2026-10-26: Markdown only, no .html/.pdf/.docx).
//
// # THE DEFECT THIS CLOSES
//
// `export` and `subtask-export` generated .html/.pdf/.docx siblings whenever
// pandoc was on PATH (the --no-formats flag defaulted to false). They ignored
// constitution/config/formats_export.conf (formats_export=false by default), so
// a bare `workable-items export --out-dir docs` re-created docs/Issues.pdf,
// docs/Issues_Summary.html ... after the operator had switched exports off, and
// the pre-commit sibling guard then refused them.
//
// # THE FIX: ONE SOURCE, NOT A COPY
//
// The switch has exactly one reader: constitution/scripts/formats_export_lib.sh
// (function formats_export_resolve). Precedence, owned THERE and nowhere else:
//
//	env DOCS_EXPORT  >  repo policy docs/context/doc_export.policy (enabled=1)
//	>  constitution/config/formats_export.conf  >  false (fail-closed)
//
// This file does NOT re-implement that precedence (a second copy could drift).
// It shells out to the library's resolve function and parses its one-line
// answer "<0|1> <source>". Anything that is not exactly "1 <source>" — library
// not found, bash missing, non-zero exit, empty or unparsable output — is
// DISABLED (fail-closed, §11.4.6: when in doubt, produce nothing), announced.
//
// Explicit command-line flags are more specific than any ambient switch:
//
//	--no-formats   force Markdown only (existing flag, unchanged)
//	--formats      force the sibling export on (new, explicit opt-in)
//	both           usage error
//	neither        the switch decides (default OFF)
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// formatsLibName is the single shared reader of the switch.
const formatsLibName = "formats_export_lib.sh"

// formatsDecision is the resolved state of the switch.
type formatsDecision struct {
	Enabled bool
	Source  string // env | policy | constitution-default | fail-closed | flag
	Detail  string // human reason, set on fail-closed paths
}

// failClosed is the ONLY place a "could not decide" outcome is built: disabled.
func failClosed(detail string) formatsDecision {
	return formatsDecision{Enabled: false, Source: "fail-closed", Detail: detail}
}

// invocationDir is the directory the user invoked the tool from (PWD, see
// pathresolve.go), falling back to the process cwd. The shell library derives
// the consuming repository root from the git toplevel of this directory.
func invocationDir() string {
	if pwd := os.Getenv("PWD"); pwd != "" && filepath.IsAbs(pwd) {
		if fi, err := os.Stat(pwd); err == nil && fi.IsDir() {
			return pwd
		}
	}
	d, _ := os.Getwd()
	return d
}

// findFormatsLib locates formats_export_lib.sh. Order: explicit env override
// WORKABLE_ITEMS_FORMATS_LIB (test seam / unusual layouts), then relative to
// the running executable (the tracked binary lives in
// constitution/scripts/workable-items/bin/), then walking up from the
// invocation directory looking for the constitution submodule layout. Returns
// "" when not found.
func findFormatsLib() string {
	if p := os.Getenv("WORKABLE_ITEMS_FORMATS_LIB"); p != "" {
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			return p
		}
		return "" // an explicit override that does not exist is NOT silently replaced
	}
	var cands []string
	if exe, err := os.Executable(); err == nil {
		if real, err := filepath.EvalSymlinks(exe); err == nil {
			exe = real
		}
		d := filepath.Dir(exe)
		cands = append(cands,
			filepath.Join(d, "..", "..", formatsLibName), // .../scripts/workable-items/bin/<exe>
			filepath.Join(d, "..", formatsLibName),       // .../scripts/workable-items/<exe>
		)
	}
	for d := invocationDir(); d != "" && d != filepath.Dir(d); d = filepath.Dir(d) {
		cands = append(cands,
			filepath.Join(d, "constitution", "scripts", formatsLibName),
			filepath.Join(d, "scripts", formatsLibName),
		)
	}
	for _, c := range cands {
		if fi, err := os.Stat(c); err == nil && !fi.IsDir() {
			return filepath.Clean(c)
		}
	}
	return ""
}

// resolveFormatsSwitch asks the shared shell library for the switch state.
func resolveFormatsSwitch() formatsDecision {
	lib := findFormatsLib()
	if lib == "" {
		return failClosed(formatsLibName + " not found (WORKABLE_ITEMS_FORMATS_LIB / executable-relative / constitution layout)")
	}
	bash, err := exec.LookPath("bash")
	if err != nil {
		return failClosed("bash not found on PATH; cannot read the switch")
	}
	cmd := exec.Command(bash, "-c", `. "$1" && formats_export_resolve`, "formats_switch", lib)
	cmd.Dir = invocationDir()
	out, err := cmd.Output()
	if err != nil {
		return failClosed(fmt.Sprintf("%s resolve failed: %v", formatsLibName, err))
	}
	return parseFormatsResolve(string(out))
}

// parseFormatsResolve parses the library's "<0|1> <source>" line. Only the
// exact token "1" enables; everything else is disabled.
func parseFormatsResolve(out string) formatsDecision {
	f := strings.Fields(strings.TrimSpace(out))
	if len(f) != 2 {
		return failClosed(fmt.Sprintf("unparsable resolve output %q", strings.TrimSpace(out)))
	}
	switch f[0] {
	case "1":
		return formatsDecision{Enabled: true, Source: f[1]}
	case "0":
		return formatsDecision{Enabled: false, Source: f[1]}
	}
	return failClosed(fmt.Sprintf("unparsable resolve output %q", strings.TrimSpace(out)))
}

// decideFormats applies the explicit-flag precedence over the ambient switch.
// ok=false means a usage error (both flags given).
func decideFormats(noFormats, formats bool) (d formatsDecision, ok bool) {
	switch {
	case noFormats && formats:
		return formatsDecision{}, false
	case noFormats:
		return formatsDecision{Enabled: false, Source: "flag"}, true
	case formats:
		return formatsDecision{Enabled: true, Source: "flag"}, true
	}
	return resolveFormatsSwitch(), true
}

// formatsDisabledNotice is the one honest line printed when the switch is off
// (never silent, §11.4.106(E)).
func formatsDisabledNotice(tool string, d formatsDecision) string {
	why := "source=" + d.Source
	if d.Detail != "" {
		why += ": " + d.Detail
	}
	return fmt.Sprintf("%s: formats export disabled (%s; constitution/config/formats_export.conf default false, "+
		"operator order 2026-10-26) -- Markdown only, no .html/.pdf/.docx written. "+
		"Enable explicitly: --formats, or DOCS_EXPORT=1, or 'enabled=1' in docs/context/doc_export.policy",
		tool, why)
}
