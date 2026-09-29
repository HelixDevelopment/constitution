// closure_seam.go — T-D02/T-D03: extends the SOL-01/SOL-04 status-custody
// seam (constitution/docs/research/quality/solutions/SOL-01_status_custody.md,
// SOL-04_evidence_class.md) with the `closure-check` subcommand
// (contracts/closure-refusal.md "Invocations"):
//
//	$WI closure-check --config <cfg> --item <ItemId> --to <Fixed|Implemented|Completed>
//	                   --attempt <attempt.json> --out <decision.json>
//
// T095 scope (tasks.md T087/T095, verbatim): "runtime/user-visible Bug/
// Feature cannot reach terminal status on source/artifact evidence
// (refusal names the missing class); the registered guard must hold a
// verdict for the current artifact fingerprint (E4)" — CR-001/CR-002
// (evidence-class-at-closure layer floor + anti-echo reclassification) and
// the E4 slice of CR-005 (a CITED regression_guard must hold a verdict for
// the current artifact fingerprint).
//
// T097 scope (tasks.md T097, verbatim): "Wire `sibling_search_check.sh`
// into ... closure_seam.go after T095 so Bug closure is refused without a
// valid artefact, until T088 is fully GREEN" — CR-004 (sibling-instance
// search), implemented in checkSiblingSearch below by SHELLING OUT to the
// already-landed, already-GREEN (T096) sibling_search_check.sh — never a
// second, duplicate Go port of that tool's own SiblingSearchArtefact
// validation logic (§11.4.227 reuse; §11.4.251 byte-identical-fork
// prohibition — one validator, one schema, one place it can drift).
//
// This file does NOT implement the "a Bug closure requires a registered
// guard at all" half of CR-005 (data-model.md §6.3 states the field itself
// as "guard id ... or absent"; no RED test in this batch exercises that
// broader clause). Producer != Verifier (§11.4.240): implementing an
// unconditional guard requirement here, unrequested and untested, would
// refuse every one of T088's own Bug fixtures for the WRONG reason (a
// missing guard, since closureAttemptFixture in
// fastcycle_sibling_search_test.go never populates regression_guard)
// instead of the CR-004 reason this file's own CR-004 wiring exists to
// enforce — silently defeating T097's own stated goal.
//
// closure-check is READ-ONLY on the tracker — CR-007: "Refusals never
// modify the tracker; acceptance writes through the single writer only."
// No Exec/Begin call against the tracker DB appears anywhere below (the
// DB is opened only to resolve the cited item's Type); the sibling_search_
// check.sh subprocess and its staged artefact temp file are the ONLY
// exec/write this file performs, and neither touches the tracker. Per the
// contract's own words this subcommand is "the dry-run face of the seam
// T-D02 extends" — it does not gate the existing `close` subcommand
// itself; no RED test in this batch exercises that wiring, so it is out of
// this file's scope.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

// closureDecisionAccepted is the exact ACCEPTED literal contracts/
// closure-refusal.md's exit-codes table and data-model.md §6.3's `decision`
// field both name.
const closureDecisionAccepted = "ACCEPTED"

// ---- CLI dispatch -----------------------------------------------------

// runClosureCheck implements the `closure-check` subcommand.
func runClosureCheck(args []string) int {
	fs := flag.NewFlagSet("closure-check", flag.ContinueOnError)
	cfgPath := fs.String("config", "", "closure-check config YAML (top-level `db:` key; contracts/closure-refusal.md)")
	itemID := fs.String("item", "", "item id under closure evaluation")
	toStatus := fs.String("to", "", "target terminal status: Fixed | Implemented | Completed")
	attemptPath := fs.String("attempt", "", "ClosureAttempt JSON path (data-model.md §6.3)")
	outPath := fs.String("out", "", "path to write the decision JSON")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if strings.TrimSpace(*cfgPath) == "" || strings.TrimSpace(*itemID) == "" ||
		strings.TrimSpace(*toStatus) == "" || strings.TrimSpace(*attemptPath) == "" ||
		strings.TrimSpace(*outPath) == "" {
		fmt.Fprintln(os.Stderr, "closure-check: --config, --item, --to, --attempt and --out are all required")
		return exitUsage
	}

	cfg, err := readClosureCheckConfig(*cfgPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "closure-check: %v\n", err)
		return exitUsage
	}
	if cfg.dbPath == "" {
		fmt.Fprintln(os.Stderr, "closure-check: config is missing its required `db:` key")
		return exitUsage
	}

	attempt, err := readClosureAttempt(*attemptPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "closure-check: %v\n", err)
		return exitUsage
	}

	db, err := openDB(cfg.dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "closure-check: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	it, err := loadItem(db, *itemID, "Issues")
	if err != nil {
		fmt.Fprintf(os.Stderr, "closure-check: %v\n", err)
		return exitUsage
	}
	if it == nil {
		fmt.Fprintf(os.Stderr, "closure-check: item %s not found in Issues\n", *itemID)
		return exitUsage
	}

	decision := evaluateClosureAttempt(it.Type, attempt, cfg)

	body, marshalErr := json.MarshalIndent(map[string]interface{}{
		"item_id":       *itemID,
		"target_status": *toStatus,
		"decision":      decision,
	}, "", "  ")
	if marshalErr != nil {
		fmt.Fprintf(os.Stderr, "closure-check: marshal decision: %v\n", marshalErr)
		return exitUsage
	}
	outResolved := resolveInvocationRelative(*outPath)
	if err := os.WriteFile(outResolved, body, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "closure-check: write %s: %v\n", outResolved, err)
		return exitUsage
	}

	if decision == closureDecisionAccepted {
		fmt.Printf("closure-check: %s ACCEPTED\n", *itemID)
		return exitOK
	}
	fmt.Printf("closure-check: %s %s\n", *itemID, decision)
	return exitUsage
}

// ---- config -------------------------------------------------------------

type closureCheckConfig struct {
	dbPath              string
	guardVerdictsDir    string
	siblingSearchScript string
}

// readClosureCheckConfig parses the minimal line-based `key: value` YAML
// this seam's --config takes (contracts/closure-refusal.md "Invocations";
// data-model.md §6.3; the shape DEFINED here per this codebase's own
// established precedent — fastcycle_sibling_search_test.go's own
// writeMinimalClosureCheckConfig — for exactly the same reason that file
// documents: no example JSON/YAML body is given anywhere beyond the field
// list). Recognised keys: `db` (required, the workable-items SQLite DB
// path), `guard_verdicts_dir` (optional, E4's guard-verdict store — see
// currentArtifactFingerprint / guardHasVerdictForFingerprint below), and
// `sibling_search_script` (optional, CR-004's override of the
// sibling_search_check.sh location — see siblingSearchScriptPath below;
// project-supplied per §11.4.28, mirroring guard_verdicts_dir's own
// precedent). A full YAML parser is not needed — nothing this seam reads
// is nested, quoted or multi-line.
func readClosureCheckConfig(path string) (closureCheckConfig, error) {
	var cfg closureCheckConfig
	body, err := os.ReadFile(resolveInvocationRelative(path))
	if err != nil {
		return cfg, fmt.Errorf("read --config %q: %w", path, err)
	}
	for _, line := range strings.Split(string(body), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, val, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		val = strings.Trim(strings.TrimSpace(val), `"'`)
		switch key {
		case "db":
			cfg.dbPath = val
		case "guard_verdicts_dir":
			cfg.guardVerdictsDir = val
		case "sibling_search_script":
			cfg.siblingSearchScript = val
		}
	}
	return cfg, nil
}

// ---- ClosureAttempt (data-model.md §6.3) ---------------------------------

// closureEvidenceEntry mirrors data-model.md §6.3's evidence entry shape
// (`{EvidencePath, claimed_class, machine_fields}`) — field-name-compatible
// with fastcycle_closure_evidence_class_test.go's and
// fastcycle_sibling_search_test.go's own `map[string]interface{}` fixture
// entries (`"EvidencePath"`/`"claimed_class"`, exactly as written there).
type closureEvidenceEntry struct {
	EvidencePath  string                 `json:"EvidencePath"`
	ClaimedClass  string                 `json:"claimed_class"`
	MachineFields map[string]interface{} `json:"machine_fields,omitempty"`
}

// closureAttempt mirrors data-model.md §6.3 ClosureAttempt for THIS file's
// own reader side (the writer side is each RED test's own fixture type).
type closureAttempt struct {
	ItemID       string                 `json:"item_id"`
	TargetStatus string                 `json:"target_status"`
	DefectLayer  string                 `json:"defect_layer"`
	Evidence     []closureEvidenceEntry `json:"evidence"`
	// SiblingSearch (data-model.md §6.4) is NOT interpreted by this file —
	// CR-004 is T096/T097's scope (see the file header). Captured as raw
	// JSON purely so an attempt supplying one (e.g. this package's own E4
	// fixture, which supplies a fully-valid one precisely to keep that
	// test's assertion isolated from an unrelated CR-004 refusal) still
	// unmarshals without error, without this file needing its own copy of
	// the SiblingSearchArtefact shape.
	SiblingSearch   json.RawMessage `json:"sibling_search,omitempty"`
	RegressionGuard string          `json:"regression_guard,omitempty"`
}

func readClosureAttempt(path string) (closureAttempt, error) {
	var a closureAttempt
	body, err := os.ReadFile(resolveInvocationRelative(path))
	if err != nil {
		return a, fmt.Errorf("read --attempt %q: %w", path, err)
	}
	if err := json.Unmarshal(body, &a); err != nil {
		return a, fmt.Errorf("parse --attempt %q: %w", path, err)
	}
	return a, nil
}

// ---- evaluation -----------------------------------------------------------

// evaluateClosureAttempt is the seam's pure decision function: ACCEPTED or a
// CR-00x refusal text. Check order (CR-001/CR-002 layer floor, then CR-004
// sibling search, then E4/CR-005) matches this file's own stated scope —
// deliberately, since T087/T088's own fixtures keep the conditions isolated
// (the E4 fixture supplies source-layer/source-class evidence AND a fully
// valid sibling_search artefact so neither CR-001 nor CR-004 fires there;
// the CR-001 golden-bad fixture uses a Feature, exempt from CR-004/CR-005
// entirely; the CR-004 golden-bad fixtures use a source-layer/source-
// evidence Bug so CR-001 never fires there). A real future closure could in
// principle violate more than one clause at once, in which case the
// earliest-checked clause is reported first — the caller fixes it and
// re-runs to discover any remaining refusal (CR-007: refusals never modify
// the tracker, so nothing is lost by reporting one refusal at a time).
func evaluateClosureAttempt(itemType string, attempt closureAttempt, cfg closureCheckConfig) string {
	if decision, refused := checkEvidenceClassFloor(itemType, attempt); refused {
		return decision
	}
	if decision, refused := checkSiblingSearch(itemType, attempt, cfg); refused {
		return decision
	}
	if decision, refused := checkGuardFreshness(itemType, attempt, cfg); refused {
		return decision
	}
	return closureDecisionAccepted
}

// ---- CR-001 / CR-002 -------------------------------------------------------

// evidenceClassRank is the SOL-04 closed-set ordering {runtime > artifact >
// source}; -1 marks an unrecognised/absent claimed_class (never a floor
// satisfier).
func evidenceClassRank(class string) int {
	switch class {
	case "runtime":
		return 2
	case "artifact":
		return 1
	case "source":
		return 0
	default:
		return -1
	}
}

func evidenceClassName(rank int) string {
	switch rank {
	case 2:
		return "runtime"
	case 1:
		return "artifact"
	case 0:
		return "source"
	default:
		return "none"
	}
}

// layerFloorRank maps a ClosureAttempt's defect_layer onto the minimum
// evidence-class rank it requires (SOL-04 §2; data-model.md §6.3: "user-
// visible defects require runtime"). T095's own task line scopes this
// clause to "runtime/user-visible" layers; "artifact", "source" and any
// unrecognised layer value carry no floor here — an under-specified/legacy
// layer is accepted rather than spuriously refused (§11.4.201(1), the
// false-refusal guard: an unresolvable signal defaults to the SAFE choice,
// and here "safe" means not blocking work this file was never asked to
// gate).
func layerFloorRank(defectLayer string) int {
	switch defectLayer {
	case "user-visible", "runtime":
		return 2 // requires runtime-class evidence
	default:
		return -1 // no floor enforced by this clause
	}
}

// sourceScanTranscriptRe matches CR-002's own worked example ("the recorded
// command is a text search over the repo") — a shell-prompt line invoking a
// grep-family search tool. Deliberately a closed pattern list (SOL-04 §5.4's
// own documented honest boundary: "a determined writer can phrase an echo
// differently" — the negative pressure against that comes from the paired
// §1.1 mutation, not from a longer regexp).
var sourceScanTranscriptRe = regexp.MustCompile(`(?m)^\$\s*(grep|rg|ag|ack|git\s+grep)\b`)

// looksLikeSourceScanTranscript applies CR-002's second detection branch to
// an evidence file's own content.
func looksLikeSourceScanTranscript(content string) bool {
	return sourceScanTranscriptRe.MatchString(content)
}

// hasTargetFingerprint applies CR-002's first detection branch: SOL-04 §2
// requires a `runtime` claim to carry TARGET_FINGERPRINT (read from the
// target at run time) among its machine fields.
func hasTargetFingerprint(fields map[string]interface{}) bool {
	for _, key := range []string{"target_fingerprint", "TARGET_FINGERPRINT", "TargetFingerprint"} {
		v, ok := fields[key]
		if !ok || v == nil {
			continue
		}
		// Only a non-empty STRING is a fingerprint (T103 review R1-M1): a
		// bool/number/object/array value is not a fingerprint read from the
		// target, and previously ANY non-string value (even `false`) counted.
		if s, ok := v.(string); ok && strings.TrimSpace(s) != "" {
			return true
		}
	}
	return false
}

// effectiveEvidenceRank applies CR-002's anti-echo reclassification (a
// `runtime`-claimed entry with no target fingerprint, OR whose own file
// content is a source-scan transcript, is reclassified `source` BEFORE
// CR-001 is evaluated) and returns the resulting SOL-04 rank. An evidence
// file that cannot be read is treated as failing the runtime proof (never
// silently trusted, §11.4.6): the claim is reclassified exactly as the
// transcript-detected case, since an unreadable "runtime" artefact can no
// more prove a target fingerprint than a grep transcript can.
func effectiveEvidenceRank(e closureEvidenceEntry) int {
	rank := evidenceClassRank(e.ClaimedClass)
	if e.ClaimedClass != "runtime" {
		return rank
	}
	if hasTargetFingerprint(e.MachineFields) {
		content, err := os.ReadFile(resolveInvocationRelative(e.EvidencePath))
		if err == nil && !looksLikeSourceScanTranscript(string(content)) {
			return rank // genuinely runtime-class
		}
	}
	return evidenceClassRank("source") // CR-002 reclassification
}

// checkEvidenceClassFloor implements CR-001 (+ CR-002's reclassification),
// scoped per T095's task line to Bug/Feature items only.
func checkEvidenceClassFloor(itemType string, attempt closureAttempt) (decision string, refused bool) {
	if itemType != "Bug" && itemType != "Feature" {
		return "", false
	}
	floor := layerFloorRank(attempt.DefectLayer)
	if floor < 0 {
		return "", false
	}
	highest := -1
	for _, e := range attempt.Evidence {
		if r := effectiveEvidenceRank(e); r > highest {
			highest = r
		}
	}
	if highest >= floor {
		return "", false
	}
	return fmt.Sprintf(
		"REFUSED(missing evidence class: %s; supplied: %s; layer: %s)",
		evidenceClassName(floor), evidenceClassName(highest), attempt.DefectLayer,
	), true
}

// ---- CR-004 (sibling-instance search, T097) --------------------------------

// checkSiblingSearch implements CR-004 (contracts/closure-refusal.md:
// "Every Bug closure requires a valid SiblingSearchArtefact ... Absent or
// invalid => REFUSED(missing: sibling-instance search) ... There is no
// exemption flag ... Tasks and Features are not bound by CR-004 (DEC-20
// alternative (b))"). Scoped to Bug ONLY, matching CR-004's own text
// exactly and CR-005/E4's identical scope below — Features and Tasks are
// always accepted by this clause regardless of what (if anything) their
// attempt's sibling_search field carries.
//
// §11.4.227 reuse, never re-implemented (§11.4.251 byte-identical-fork
// prohibition): this function does NOT duplicate sibling_search_validate.py
// / sibling_search_check.sh's own SiblingSearchArtefact schema logic in Go
// — it stages the attempt's raw `sibling_search` JSON to a temp file and
// shells out to the ALREADY-LANDED, ALREADY-GREEN (T096)
// sibling_search_check.sh, which is the ONE place that schema is validated.
func checkSiblingSearch(itemType string, attempt closureAttempt, cfg closureCheckConfig) (decision string, refused bool) {
	if itemType != "Bug" {
		return "", false
	}

	raw := strings.TrimSpace(string(attempt.SiblingSearch))
	if raw == "" || raw == "null" {
		// The absent case, verbatim per CR-004: "Absent or invalid =>
		// REFUSED(missing: sibling-instance search)". There is no need to
		// invoke the script at all — an absent artefact cannot be staged.
		return "REFUSED(missing: sibling-instance search)", true
	}

	scriptPath := siblingSearchScriptPath(cfg)
	if scriptPath == "" {
		// Conservative-safe default (§11.4.201): the validator could not be
		// located at all, so the artefact cannot be proven valid — refuse,
		// never silently trust an un-validated artefact.
		return "REFUSED(missing: sibling-instance search; sibling_search_check.sh could not be located)", true
	}

	artefactPath, cleanup, stageErr := stageSiblingSearchArtefact(attempt.SiblingSearch)
	if stageErr != nil {
		return fmt.Sprintf("REFUSED(missing: sibling-instance search; could not stage artefact: %v)", stageErr), true
	}
	defer cleanup()

	out, runErr := exec.Command(scriptPath, artefactPath).CombinedOutput()
	if runErr == nil {
		// sibling_search_check.sh exit 0 == the artefact is SCHEMA-valid.
		// The schema validator has no tracker access, so the one check only
		// this seam can make is done here (T103 review R1-I6): every
		// "tracked-as <ItemId>" disposition must name an item that genuinely
		// EXISTS in the tracker — a sibling "tracked" as a non-existent id is
		// a lost requirement (§11.4.197), not a tracked one. This is a
		// cross-reference, not a second copy of the schema rules (§11.4.251).
		if missing, err := untrackedSiblingIDs(attempt.SiblingSearch, cfg.dbPath); err != nil {
			return fmt.Sprintf("REFUSED(missing: sibling-instance search; tracked-as ids could not be verified: %v)", err), true
		} else if len(missing) > 0 {
			return fmt.Sprintf("REFUSED(missing: sibling-instance search; tracked-as id(s) not found in the tracker: %s)",
				strings.Join(missing, ", ")), true
		}
		return "", false
	}
	// Any non-zero exit (1 FINDING, 2 usage error, 4 BLIND — see
	// sibling_search_check.sh's own header for the exit-code table) means
	// the artefact was NOT proven valid, which per CR-004's own text is the
	// SAME refusal as an absent artefact ("Absent OR INVALID => REFUSED
	// (missing: sibling-instance search)"). The tool's own FINDING/BLIND
	// lines are folded in for auditability, never dropped.
	findings := strings.TrimSpace(string(out))
	if findings == "" {
		findings = runErr.Error()
	}
	return fmt.Sprintf(
		"REFUSED(missing: sibling-instance search; %s)",
		strings.ReplaceAll(findings, "\n", "; "),
	), true
}

// siblingSearchScriptPath resolves the sibling_search_check.sh location.
// A `sibling_search_script:` config key ALWAYS wins (project-supplied
// override, §11.4.28 — mirrors guardVerdictsDir's own precedent above).
// Absent that, the script is located relative to THIS SOURCE FILE's own
// on-disk location (runtime.Caller(0)) — the SAME technique
// fastcycle_sibling_search_test.go's own workableItemsModuleDir already
// uses in this package, robust regardless of the invoking cwd or of the
// built binary's own location (the path is captured at COMPILE time from
// the source tree, not derived from os.Args[0] or the process cwd).
// closure_seam.go lives at
// .../constitution/scripts/workable-items/cmd/workable-items/closure_seam.go;
// sibling_search_check.sh lives at the SIBLING directory
// .../constitution/scripts/fastcycle/closure/sibling_search_check.sh — both
// under the SAME constitution/scripts/ tree (§11.4.28/§11.4.177
// decoupling: never a project-specific absolute path).
func siblingSearchScriptPath(cfg closureCheckConfig) string {
	if strings.TrimSpace(cfg.siblingSearchScript) != "" {
		return resolveInvocationRelative(cfg.siblingSearchScript)
	}
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		return ""
	}
	dir := filepath.Dir(thisFile) // .../workable-items/cmd/workable-items
	return filepath.Join(dir, "..", "..", "..", "fastcycle", "closure", "sibling_search_check.sh")
}

// stageSiblingSearchArtefact writes an attempt's raw sibling_search JSON to
// a fresh temp file for sibling_search_check.sh's own single positional
// <artefact.json> argument. The returned cleanup func removes it; callers
// MUST defer it.
func stageSiblingSearchArtefact(raw json.RawMessage) (path string, cleanup func(), err error) {
	f, createErr := os.CreateTemp("", "sibling-search-artefact-*.json")
	if createErr != nil {
		return "", func() {}, createErr
	}
	if _, writeErr := f.Write(raw); writeErr != nil {
		f.Close()
		os.Remove(f.Name())
		return "", func() {}, writeErr
	}
	if closeErr := f.Close(); closeErr != nil {
		os.Remove(f.Name())
		return "", func() {}, closeErr
	}
	return f.Name(), func() { os.Remove(f.Name()) }, nil
}

// ---- E4 (the CR-005 slice this file is scoped to) --------------------------

// checkGuardFreshness implements the E4 slice of CR-005: a Bug closure that
// CITES a regression_guard must have a verdict for the CURRENT artifact
// fingerprint on record for that guard, or the closure is refused. Scoped
// to Bug per CR-005's own text ("A Bug closure requires a registered
// guard ..."), matching CR-004's identical scope. A Bug closure citing NO
// regression_guard at all is deliberately NOT refused here — see this
// file's header for why (T088's own downstream scope; §11.4.240 Producer
// != Verifier).
func checkGuardFreshness(itemType string, attempt closureAttempt, cfg closureCheckConfig) (decision string, refused bool) {
	guardID := strings.TrimSpace(attempt.RegressionGuard)
	if itemType != "Bug" || guardID == "" {
		return "", false
	}
	fingerprint := currentArtifactFingerprint(cfg.dbPath)
	if guardHasVerdictForFingerprint(cfg.guardVerdictsDir, guardID, fingerprint) {
		return "", false
	}
	return fmt.Sprintf(
		"REFUSED(missing: guard verdict for current artifact fingerprint %s; guard: %s)",
		fingerprint, guardID,
	), true
}

// currentArtifactFingerprint reads the current artifact fingerprint FROM
// THE TARGET AT RUN TIME (§11.4.115(F)) — never invented, never a
// placeholder. For this dev-process-tooling feature (plan.md: "no device
// firmware, kernel, HAL or flash-path change is in scope") the deployable
// artifact IS the git working tree, so the fingerprint is that tree's own
// current commit: `git rev-parse HEAD`, run from the nearest enclosing git
// worktree found by walking up from each of startDirs in turn (a
// submodule's `.git` is a FILE, not a directory — os.Stat sees either).
// An UNRESOLVABLE fingerprint (no enclosing git tree found, or `git` itself
// unavailable/erroring — both real, expected states for e.g. a fixture
// written under a bare tempdir, as every RED test in this package's own
// suite exercises) returns the honest sentinel "UNKNOWN" rather than a
// fabricated hash; a verdict store can never match "UNKNOWN", so an
// unresolvable fingerprint still correctly refuses (§11.4.201's
// conservative-safe default) — it just cannot name the real one.
func currentArtifactFingerprint(startDirs ...string) string {
	for _, start := range startDirs {
		if start == "" {
			continue
		}
		dir := filepath.Dir(resolveInvocationRelative(start))
		for {
			if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
				out, gitErr := exec.Command("git", "-C", dir, "rev-parse", "HEAD").Output()
				if gitErr == nil {
					if hash := strings.TrimSpace(string(out)); hash != "" {
						return hash
					}
				}
				break
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return "UNKNOWN"
}

// guardHasVerdictForFingerprint reports whether a guard-verdict store names
// a GREEN verdict for guardID at fingerprint. Honest, real lookup — an
// unconfigured store (cfg.guardVerdictsDir == "", the state every RED test
// in this package exercises since writeMinimalClosureCheckConfig never sets
// it), an absent per-guard record, or a fingerprint with no matching entry
// are all, correctly, NOT a verdict — never fabricated, never assumed
// present (§11.4.6). Store shape (DEFINED here; UNCONFIRMED by contracts/
// data-model.md beyond the field list — this file's own house precedent,
// matching fastcycle_sibling_search_test.go's "Assumed CLI contract" note):
// `<dir>/<guardID>.json`: `{"guard_id": "...", "green_fingerprints": ["<hash>", ...]}`.
//
// T103 review R1-I2 hardening: (a) guardID comes from the PRODUCER-authored
// ClosureAttempt, so it must be a single plain file-name component — any
// path separator, "." / ".." or NUL is refused, otherwise "../x" resolved a
// producer-controlled verdict file OUTSIDE the configured store (§11.4.240:
// the producer can never write its own verdict); (b) the "UNKNOWN" sentinel
// (an unresolvable fingerprint) never matches, even if a store entry
// literally contains it — the previous "a store can never match UNKNOWN"
// comment was an unproven assumption (§11.4.194(2)).
func guardHasVerdictForFingerprint(dir, guardID, fingerprint string) bool {
	if dir == "" || guardID == "" || fingerprint == "" || fingerprint == "UNKNOWN" {
		return false
	}
	if !plainGuardIDComponent(guardID) {
		return false
	}
	p := filepath.Join(resolveInvocationRelative(dir), guardID+".json")
	body, err := os.ReadFile(p)
	if err != nil {
		return false
	}
	var rec struct {
		GreenFingerprints []string `json:"green_fingerprints"`
	}
	if err := json.Unmarshal(body, &rec); err != nil {
		return false
	}
	for _, fp := range rec.GreenFingerprints {
		if fp == fingerprint {
			return true
		}
	}
	return false
}

// plainGuardIDComponent reports whether guardID is safe to use as a single
// file-name component inside the verdict store (T103 review R1-I2).
func plainGuardIDComponent(guardID string) bool {
	if guardID == "." || guardID == ".." || strings.ContainsAny(guardID, "/\\\x00") {
		return false
	}
	return filepath.Base(guardID) == guardID
}

// untrackedSiblingIDs returns every "tracked-as <ItemId>" disposition id in
// the raw SiblingSearchArtefact that does NOT exist in the tracker at dbPath
// (any location). Called only after sibling_search_check.sh accepted the
// artefact, so the JSON is known to be a well-formed object. An unreadable
// tracker is an error (the caller refuses — §11.4.201 conservative-safe).
func untrackedSiblingIDs(raw json.RawMessage, dbPath string) ([]string, error) {
	var doc struct {
		Instances []struct {
			Disposition string `json:"disposition"`
		} `json:"instances_found"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("parse sibling_search: %w", err)
	}
	var ids []string
	for _, in := range doc.Instances {
		if rest, ok := strings.CutPrefix(in.Disposition, "tracked-as "); ok {
			ids = append(ids, strings.TrimSpace(rest))
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}
	if strings.TrimSpace(dbPath) == "" {
		return nil, fmt.Errorf("no tracker db configured")
	}
	db, err := openDB(dbPath)
	if err != nil {
		return nil, err
	}
	defer db.Close()
	var missing []string
	for _, id := range ids {
		var n int
		if err := db.QueryRow(`SELECT COUNT(*) FROM items WHERE atm_id=?`, id).Scan(&n); err != nil {
			return nil, err
		}
		if n == 0 {
			missing = append(missing, id)
		}
	}
	return missing, nil
}
