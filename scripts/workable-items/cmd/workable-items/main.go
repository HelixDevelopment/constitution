// Package main is the entrypoint for the `workable-items` Go binary.
//
// §11.4.93 SQLite-backed single-source-of-truth for workable items.
// Forensic anchor: User mandate 2026-05-27.
//
// Phase 2 scaffold — subcommands stubbed; Phase 3 (md→db) + Phase 4
// (db→md) + Phase 5 (generator shims) follow per the 6-phase migration
// defined in Constitution.md §11.4.93.
package main

import (
	"fmt"
	"os"
)

const (
	exitOK    = 0
	exitUsage = 1
)

func usage() {
	fmt.Fprint(os.Stderr, `workable-items — §11.4.93 SQLite-SSoT for workable items

Usage:
  workable-items <subcommand> [args...]

Subcommands:
  sync md-to-db --db <p> [--issues <p>] [--fixed <p>]   Parse trackers, upsert DB.
  sync db-to-md --db <p> [--out-issues <p>] [--out-fixed <p>]  Regenerate trackers from DB.
  diff --db <p> (--issues <p> | --fixed <p>)            Show DB vs Markdown divergence.
                                                       At least one Markdown path is
                                                       REQUIRED; the verdict names the
                                                       files it read.
  diff --db <p> --db-only                              DB-internal integrity checks only
                                                       (reads no Markdown, and says so).
  validate --db <p>                                     Closed-set + §11.4.91 invariants.
  repair-bodies --db <p> [--dry-run]                    Canonicalize stale body **Status:** lines + populate empty bodies from columns (ATM-627/task #20).
  add <type> <severity> --db <p> --title <T> --description <D> [--id <id>] [--prefix <P>] [--created-by <h>] [--assigned-to <h>]
                                                        Create a new Queued item in Issues.
  update --id <ID> --db <p> [--title|--severity|--description|--type|--status|--created-by|--assigned-to ...] [--location Issues|Fixed]
                                                        Mutate fields on an existing item (§11.4.34 audit).
  reopen --id <ID> --db <p> --why <reason> --who <AI|User> --when <ISO> --incident <p> [--location Issues|Fixed]
  move --id <ID> --db <p> --to <Issues|Fixed> --why <text> [--status <S>] [--evidence <p>]
                                                        Set Status=Reopened with §11.4.34 source attribution.
  block --id <ID> --db <p> --details <T> [--why <T>] [--unblock <T>] [--who <T>] [--location Issues|Fixed]
                                                        Set Status=Operator-blocked with §11.4.21 details.
  close <atm-id> --db <p> --status <fixed|implemented|completed|obsolete> --evidence <p>
                                                        Atomic Issues→Fixed closure (§11.4.19).
  closure-check --config <cfg> --item <ID> --to <Fixed|Implemented|Completed> --attempt <a.json> --out <d.json>
                                                        Dry-run status-custody seam check (contracts/closure-refusal.md
                                                        CR-001/CR-002 evidence-class floor + E4 guard-freshness;
                                                        T-D02). Read-only; never modifies the tracker.
  obsolete-details <atm-id> --db <p> --since <ISO> --reason <r> --superseding <s> --evidence <p>
                                                        Write the §11.4.90 obsolete_details row for an Obsolete item.
  intake-match --config <cfg> --report <report.json> --out <link.json> [--apply]
                                                        §11.4.214/T-D04 SOL-07 intake-dedup matcher: resolve an incoming
                                                        report (title/scope/description/intake_path) against existing
                                                        items by normalised(subject,scope); SAME_DEFECT reopens the
                                                        matched chain head (§11.4.34 attribution, no new id); DISTINCT
                                                        or UNDECIDED mints a new id (UNDECIDED carries a candidate-
                                                        duplicate-of note). --apply performs the write through the
                                                        single writer; without it, --out is a dry-run decision only.
  report --db <p> [--by-type|--by-status|--by-severity|--by-assigned|--by-creator|--obsolete-audit]
                                                        Read-only grouped tally / §11.4.90 audit.
  diary add --id <atm> --db <p> --tested-by <User|Operator|AI-agent|HelixQA> --result <PASS|FAIL|SKIP>
            [--detail T] [--observations T] [--evidence path] [--feature-class c]
            [--action-taken T] [--status-from s] [--status-to s] [--date-time ISO]
                                                        Record one §11.4.149 test_diary run (PASS requires evidence that exists).
  diary list --id <atm> --db <p>                        Print an item's testing-diary rows chronologically.
  diary summary --db <p> [--id <atm>]                   Print the test_diary_summary rollup (per-item or all).
  export --db <p> [--out-dir <d>] [--issues <p>] [--fixed <p>] [--out-issues <p>] [--out-fixed <p>]
                                                        Regenerate Issues.md + Fixed.md + Summary docs + HTML/PDF/DOCX (§11.4.12/§11.4.53).
  version-tags --db <p> --repo <p> [--issues <p>] [--fixed <p>]  Derive + persist release-tag column (feature 2026-05-30).
  group add <group_id> <destination> <priority> --title <T> [--state s]
            [--scope-note <T>] [--roadmap-ref <T>] --db <p>
                                                        Create a logic_groups row (ASSIGNMENT_MECHANISM_DESIGN.md §3.2).
  group branch <group_id> --db <p> [--repo <dir>] [--print-only]
                                                        §11.4.181 SANCTIONED feature-branch mint: resolve feature/<slug>
                                                        from the group's registered destination and git-checkout -b it
                                                        (refuses unknown group / non-feature destination; idempotent if
                                                        the canonical branch already exists). --print-only just resolves.
  group list [--destination <D>] [--state <S>] --db <p>  List logic_groups, priority-then-group_id ordered (read-only).
  group set <group_id> [--title|--destination|--priority|--scope-note|--roadmap-ref ...] --db <p>
            group set --item <ATM-ID> --group <group_id> [--location Issues|Fixed] --db <p>
                                                        Edit a group's fields, OR classify one item into a group
                                                        (destination inherited from the group — §3.1 agreement).
  group state <group_id> <open|in-progress|group-complete> --db <p>
                                                        Set a group's lifecycle state (raw setter; the gated
                                                        group-complete check is a later phase).
  validate-groups --db <p>                               §3.1 group-atomic invariants: single-valued,
                                                        destination-agreement, totality, referential, urgent-routing.
  assign next-group --track T --destinations D1[,D2,...] --claim-script <path>
            [--ttl SEC] --db <p>                          Priority-ordered group pick + exactly-once claim via the
                                                        §11.4.176-A registry (ASSIGNMENT_MECHANISM_DESIGN.md §5).
  assign next-item --track T --group <group_id> [--exclude ID1[,ID2,...]] --db <p>
                                                        Next open member item of a group, by STORED logic_group
                                                        (never a substring re-derivation — design §5).
  assign group-complete <group_id> --db <p>              Refuses unless every member item is terminal-with-evidence
                                                        (design §4 group-atomic completion gate).
  classify --propose --db <p> [--out <path-prefix>]      Propose logic_group/destination per unclassified item from
                                                        STRUCTURED signals + a title-scoped weak hint (NEVER
                                                        description) — writes a review file, never the DB (design §9).
  correct-history-evidence --db <p> --atm-id <ID> --history-id <N>
                           --evidence-path <path> [--reason <text>]
                                                        Rewrite one CLOSED item's item_history.evidence_path to a
                                                        resolvable file/dir (§11.4.226) — refuses non-terminal items,
                                                        non-closure history rows, and unresolvable paths; appends an
                                                        'Updated' audit row citing old→new.

Canonical authority: Constitution.md §11.4.93; docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §3 (group subcommands),
§5 (assigner), §9 (classifier).
`)
}

func main() {
	args := os.Args[1:]
	if len(args) < 1 {
		usage()
		os.Exit(exitUsage)
	}

	switch args[0] {
	case "sync":
		runSync(args[1:])
	case "diff":
		runDiff(args[1:])
	case "validate":
		runValidate(args[1:])
	case "repair-bodies":
		runRepairBodies(args[1:])
	case "version-tags":
		os.Exit(versionTagsCmd(args[1:]))
	case "add":
		runAdd(args[1:])
	case "update":
		runUpdate(args[1:])
	case "reopen":
		runReopen(args[1:])
	case "move":
		runMove(args[1:])
	case "block":
		runBlock(args[1:])
	case "close":
		runClose(args[1:])
	case "closure-check":
		os.Exit(runClosureCheck(args[1:]))
	case "obsolete-details":
		runObsoleteDetails(args[1:])
	case "intake-match":
		runIntakeMatch(args[1:])
	case "report":
		runReport(args[1:])
	case "diary":
		runDiary(args[1:])
	case "export":
		runExport(args[1:])
	case "group":
		runGroup(args[1:])
	case "validate-groups":
		runValidateGroups(args[1:])
	case "assign":
		runAssign(args[1:])
	case "classify":
		runClassify(args[1:])
	case "correct-history-evidence":
		runCorrectHistoryEvidence(args[1:])
	case "-h", "--help", "help":
		usage()
		os.Exit(exitOK)
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", args[0])
		usage()
		os.Exit(exitUsage)
	}
}

func runSync(args []string) {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "sync: missing direction (md-to-db | db-to-md)")
		os.Exit(exitUsage)
	}
	switch args[0] {
	case "md-to-db":
		os.Exit(syncMDToDB(args[1:]))
	case "db-to-md":
		os.Exit(syncDBToMD(args[1:]))
	default:
		fmt.Fprintf(os.Stderr, "unknown sync direction: %s\n", args[0])
		os.Exit(exitUsage)
	}
}

func runDiff(args []string) {
	os.Exit(diffCmd(args))
}

func runValidate(args []string) {
	os.Exit(validateCmd(args))
}
