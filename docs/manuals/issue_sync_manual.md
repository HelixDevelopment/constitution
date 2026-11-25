# issue_sync manual: the workable-items Issues mirror (anchor 11.4.300)

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-11-24 |
| Last modified | 2026-11-25T13:00:00Z |
| Status | active, PROVISIONAL (NO host has a proven write path: every write verb of every host is UNCONFIRMED and `apply` refuses to write until `config/forge/issue_sync_proven.tsv` lists the host together with a recorded live create and read-back; the engine is proven only against test doubles) |
| Status summary | Reference, operator guide and FAQ for `scripts/issue_sync.sh`, `scripts/verify_issues_sync.sh` and `scripts/issue_sync/`. |
| Authority | Anchor 11.4.300; 11.4.93, 11.4.106, 11.4.156, 11.4.289, 11.4.296, 11.4.299, 11.4.257 govern. |
| Scope | Universal (11.4.17): a consuming project supplies its declaration and its tokens (by variable NAME) as DATA. |
| Issues | none |

## Table of contents

1. What it does
2. Turning it on (default OFF)
3. Commands and exit codes
4. Visibility and redaction rules
5. Identity, idempotency and resume
6. Hooks, Docs Chain and schedule
7. Inbound intake and loops
8. Rollout order: dry run, review, tiered apply
9. The facade: one pipeline, both directions (`issues_sync_pipeline.sh`)
10. FAQ

## 1. What it does

The workable-items SQLite database (11.4.93) is the source of truth. The engine mirrors each item, one way, to the Issues of the repository that owns it, on every declared upstream whose repository exists and has Issues enabled. A tracker edit never changes an item; the next run resets the tracker. The issue text is a GENERATED PUBLIC SUMMARY (operator decision 2026-11-25). Only `atm_id`, `type`, `status`, `title` and `severity` come from the database; `description` is a generated field (a fixed sentence), and the body is a fixed template: summary, severity, status and type, a link to the owning repository and a repository-relative pointer to `docs/workable_items.db` with the item id. The database's description and body text are NEVER mirrored. Mirror issues are the carve-out of §11.4.300(H): they are exempt from the §11.4.296 scope ruling only while they carry the hidden footer; an issue without the footer is never created, adopted, commented, labelled, changed or closed (an unkeyed issue whose title starts with `[ID]` is reported as an anomaly and counts as drift). Verbatim operator quotes, long bodies, reproduction evidence and test diaries are never sent.

## 2. Turning it on (default OFF)

Copy `templates/workable-items-sync.yaml.template` to `.workable-items-sync.yaml` at the repository root and set `enabled: true`. The template ships `enabled: false` (gate `CM-ISSUE-SYNC-TEMPLATE-DEFAULT-OFF`). `mode` stays `dry-run`; `apply` needs `apply_decision`: a RELATIVE path (no `..`) of an existing, non-empty, git-tracked file in the repository that holds the config (checked at apply time; a string alone is refused). The config is read by a strict loader: a duplicate key and a YAML 1.1 bare boolean (`yes`, `on`) are errors, so an invalid declaration is never ON. `trackers` holds bare host names only. Hooks take the effective mode from the same validator (`python3 -m issue_sync.mode FILE`). An invalid declaration is treated as OFF with errors, never as ON. Token variables are named in `token_vars` (names only) or default from `config/forge/hosts.tsv`; values are read from the environment, then parsed (never sourced) from `~/api_keys.sh`, which must be mode 0600 and owned by you.

## 3. Commands and exit codes

```
scripts/issue_sync.sh plan   --config .workable-items-sync.yaml --db docs/workable_items.db --owner-repo H/O/R [--db-repo H/O/R] --target H/O/R [--target ...] [--only-open] [--limit N] [--private-corpus FILE] [--json]
scripts/issue_sync.sh apply  ... --apply          # writes only with --apply AND mode: apply
scripts/issue_sync.sh status ...                  # offline: pending changes versus issue_sync_map
scripts/verify_issues_sync.sh ...                 # read-only verifier
scripts/verify_issues_sync.sh --prove-failure     # paired mutations over a test double
python3 -m issue_sync.live_probe H/O/R ...        # read-only repo existence, visibility, issues-enabled
```

`--db-repo` is REQUIRED when the DB has parent prefixes (the parent's items go to the repo you name, never to whichever `--owner-repo` was passed). A DB with no routing data (no or empty `sub_projects`) is routed only when ALL its items share ONE prefix; otherwise nothing is sent. `--private-corpus FILE` (repeatable, also `ISSUE_SYNC_PRIVATE_CORPUS`) fingerprints a private corpus whose 8-word shingles may never appear in an outgoing title or description; an unreadable or empty corpus is exit 2. Independently of any corpus, each item's own `forensic_anchor` and `body_md` text is fingerprinted (7-word runs) against every outgoing field, the title above all. One allowance: a body LINE that repeats the item's WHOLE title (its heading; a title stitched from two lines gets nothing) does not make the title block itself; a title that is not repeated whole in the body, or any run of the operator quote, gets no allowance. Residuals: a title that is exactly a private body sentence cannot be told from a restated title, and a confusable-homoglyph title. Runs stitched across hard-wrapped lines are caught (per line and joined). `--only-open` and `--limit` verify only part of the items: they never create orphans, but a partial verify is not a statement about the rest. `verify` with no routed item is exit 2, never 0.

Exit: 0 in sync (or disabled), 1 drift (item ids and trackers named), 2 cannot determine (no token, host unreachable, capability unverified, visibility undetermined, redaction stop, quota). 2 is never a pass; precedence 1 over 2 over 0.

## 4. Visibility and redaction rules

The owning repository is probed itself; an item goes only to trackers of that repository (any host mirror of the same owner and name). Private to public is refused; GitLab `internal` (readable by every signed-in user) and any unknown visibility value are undetermined, never private; undetermined visibility on either side blocks; third-party prefixes (`sub_projects.class = third-party`) are never synced. Every payload is scanned before every write for secret shapes (GitHub, GitLab, AWS, Slack, Stripe, Google, SendGrid, npm and LLM keys, JWT, private keys, URL credentials, quoted assignments), personal data (email, phone), operator-quote markers and, optionally, fingerprints of a private corpus. A hit is a hard stop that names the item by id and the kind only. (Because the DB description is not mirrored, it is not scanned; the title and every generated field are.)

## 5. Identity, idempotency and resume

Each issue has the title prefix `[ID] ` and a hidden footer `<!-- workable-item: ID | sha256: HASH -->`; the issue number is never the identity. A second run with unchanged items makes no write. Create, update, close (completed or not-planned for Obsolete where the host supports it) and reopen are decided from the listing with `state=all`. Label semantics: the engine sets the issue's WHOLE label set on create and on every update (GitHub PATCH and GitLab PUT replace the set), so a label added by hand is removed by the next sync that updates the issue; the DB is the truth. A run interrupted at any point is resumed by running it again: the footer key prevents duplicates. Duplicate keys and keyed issues without an item are reported as drift (rc 1) and are never deleted automatically.

## 6. Hooks, Docs Chain and schedule

- `scripts/hooks/issue_sync_pre_commit.sh`: offline; refuses a commit when DB changes are not reflected in the mirror map unless `ISSUE_SYNC_ACK=1`.
- `scripts/hooks/issue_sync_post_merge.sh`: when enabled and `mode: apply`, starts `apply` detached under a lock (needs `ISSUE_SYNC_TARGETS` and `ISSUE_SYNC_OWNER_REPO`).
- `templates/docs_chain/issues-sync.yaml`: the Docs Chain context; the database is the upstream node, the status documents and the mirror are downstream.
- Schedule: a user systemd timer or cron entry running `scripts/verify_issues_sync.sh` at most every 24 hours (`interval_hours`). Never in CI/CD (11.4.156).

## 7. Inbound intake and loops

Issues assigned to a declared account enter through 11.4.296, once. An issue carrying the hidden footer is ours and is never imported. Inbound intake (C7) is implemented by `pull` (section 9): tracker comments, new issues and conflicting tracker edits become reviewable PROPOSAL files; nothing is adopted automatically. Adopting a human issue as the mirror of its item (writing the footer into the same issue) is NOT implemented: it stays a human decision made through the proposal.

## 8. Rollout order: dry run, review, tiered apply

1. Enable with `mode: dry-run` and run `plan --json`; review counts, blocked and unconfirmed reasons.
2. Apply tier 1 with `--only-open`, then closed items. Public repositories first, then private ones, each to its own trackers only.
3. Run `verify_issues_sync.sh`; schedule it.

## 9. The facade: one pipeline, both directions (`issues_sync_pipeline.sh`)

`scripts/issues_sync_pipeline.sh` is the ONE entry point (operator decision 2026-11-25). It wraps the existing engine (`issue_sync.cli`, reused, not reimplemented, 11.4.74) and adds the inbound and reconcile legs. Language: bash facade over the repository's existing Python engine, because every module it needs (adapters, redaction, visibility routing) already lives there.

```
issues_sync_pipeline.sh plan|verify|reconcile|pull|apply  [same options as issue_sync.sh] [--out-dir D] [--write] [--apply]
issues_sync_pipeline.sh run [--root DIR] [--write] [options]       # the whole chain through Docs Chain
issues_sync_pipeline.sh init-context --root DIR [--owner-repo H/O/R] [--write]   # installs .docs_chain/contexts/issues-sync.yaml (never overwrites)
issues_sync_pipeline.sh --prove-failure
```

Policy (operator decision 2026-11-25): the workable-items database WINS; inbound is reviewable PROPOSALS; a conflicting tracker edit is REPORTED and is never silently applied. Dry-run is the default everywhere; exits are 0 ok or disabled, 1 drift / conflict / refusal, 2 cannot determine (never a pass).

- `reconcile` (read-only) classes each difference: `missing-in-tracker`, `db-ahead` (the DB moved since the last sync; the next apply updates the tracker, no conflict), `tracker-edited` (the issue's footer hash equals the DB's current hash yet its title, body, labels or state differ: a human edited the tracker; CONFLICT), `duplicate`, `orphan`, `anomaly`. Residual: when the DB moved AND a human edited the same issue, the edit is classed `db-ahead` (it cannot be told apart without the old rendering); the next apply overwrites it, so review the issue first when in doubt.
- `pull` reads the trackers (read-only) and, with `--write`, creates proposal files under `docs/issues_sync/inbound/` (next to the config; `--out-dir` overrides): kinds `new-issue` (an issue without the footer; with `inbound.assignees` set, only issues assigned to a declared account, 11.4.296), `comment` (a human comment on an engine-owned issue, mapped to its item id from the hidden footer), `adoption-candidate` (a human issue whose title is `[ITEM-ID]` of a known item), `footer-stripped` (carries the `wi-sync` label without the footer) and `conflict` (the tracker version of a `tracker-edited` issue). Engine-owned issues are never re-imported. Reading new intake is default OFF (`inbound.enabled`); capturing conflicts is always on. File names are `<ITEM|NEW>--<kind>--<tracker>-<number>-<sha8>.md`: the text hash makes `pull` idempotent, a changed text becomes a new file, and an existing file (reviewed or not) is never overwritten. Comments are read only where the adapter supports it (GitHub today); elsewhere the leg is `comments-unsupported` and exits 2, never "no comments".
- Tracker-originated text is DATA, never instructions: it is normalised, length-capped, scanned for secret and personal-data shapes (a hit withholds the whole text and records the kinds), and placed only inside a code fence longer than any backtick run it contains. Nothing in the pipeline executes it, interpolates it into a command, or calls the workable-items tool. Adoption is a human opening or updating the item through the normal procedure (`workable-items add` / `update`) and setting the proposal's Status to ADOPTED or REJECTED.
- `apply` runs the existing outbound path (`--apply` AND `mode: apply` AND a tracked `apply_decision`, proven write verbs) and additionally REFUSES while any `tracker-edited` issue has no captured proposal: run `pull --write`, review, then apply (the DB wins and the human's version survives as a proposal).
- `run` is the single documented command for the chain DB -> generated docs -> outbound sync -> inbound proposals -> verify, as the Docs Chain context `issues-sync` (`templates/docs_chain/issues-sync.yaml`): nodes `workable_items_db`, `issues_md`, `fixed_md`, `outbound_report`, `inbound_report`, `verify_report`. `run` (read-only) = `docs_chain doctor` + `docs_chain verify` + the facade `verify`; `run --write` = `docs_chain doctor` + `docs_chain sync` + `pull --write` + `verify`. Stages write only their staged output file, so `docs_chain verify` stays side-effect free; the outbound stage is a PLAN and writes trackers only if its args carry `--apply` and the config allows it. `docs_chain` is found through `DOCS_CHAIN_BIN` or PATH (its absence is exit 2).
- Root cause of the missing context (11.4.102): the earlier `templates/docs_chain/issues-sync.yaml` declared `derived_from`, `run`, `verify` and `verify_rc` on nodes and no `edges:` / `transforms:`; `docs_chain doctor` rejects it with exit 4 (`field derived_from not found in type config.rawNode`), so no consumer could ever load it, and the umbrella has no such context. The template is now a valid context (verified with the real `docs_chain doctor`). The umbrella still needs `init-context` run once and a `.workable-items-sync.yaml`, both its own decisions.
- Honest boundary: unit and `--prove-failure` evidence uses an in-memory tracker double and proves this tool's logic only. No host write path is proven (section 8), so `apply` still stops at the proof list; no live inbound read was recorded in this revision.

## 10. FAQ

**Why is a leg UNCONFIRMED?** The host's write API is not proven by a live create and read-back (Gitea family, GitVerse, GitFlic), the repository does not exist there, or Issues are disabled. It is never counted in sync.

**Why does an issue not show the item's description?** The issue text is a generated public summary (operator decision 2026-11-25): title, type, status, severity, a link to the owning repository and a pointer to `docs/workable_items.db` with the item id. The database's description and body are never mirrored, so they can neither leak nor block an item; read them in the repository.

**Can a tracker edit change an item?** No. The next apply resets it, and only after the edit was preserved as a `conflict` proposal (`pull --write`); inbound text becomes an item only through a human following the normal procedure.

**Why does apply refuse on GitHub and GitLab?** Their write verbs are declared but UNPROVEN: nothing may write until a live create and read-back is recorded and the host is listed in `config/forge/issue_sync_proven.tsv` (host, evidence path; the host must be a declared forge host and the evidence file must exist and carry a line starting `LIVE-CREATE-READBACK-RECORDED`). The read-only probe (`live_probe`) proves reads only and prints `writes=UNCONFIRMED`.

**Does it print my token?** No. Tokens are used only in a request header to the origin named in `hosts.tsv`; redirects are refused.

**What if visibility cannot be read?** The item is blocked and the verdict is 2.
