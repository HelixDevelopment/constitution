# Changelog — HelixDevelopment/HelixConstitution

## Unreleased — 2026-10-24 — §11.4.287 destructive-path safeguard

Not tagged. Work is staged in the working tree of the `feat/destructive-path-safeguard` branch and is not committed.

### Added

- **§11.4.287 — Destructive-path safeguard (User mandate, 2026-10-23).** No agent, script, hook, test or subagent may recursively delete, re-permission or sync-delete the filesystem root, a system directory, `/home`, a home directory, an ancestor of it or a protected child of it. Trigger: a review subagent ran a scratch script of the shape `W="$2"; export HOME="$W/home"; rm -rf "$HOME"` with empty arguments, so `$HOME` became `/home` and a recursive delete ran until a timeout stopped it (forensic anchor in the canon). The anchor has five clauses: (A) a PreToolUse guard with classes P, X, H, V and U (P and X are never overridable by the audited allow marker), (B) a refusing runtime helper, (C) script hygiene, (D) a brief every script-writing subagent must carry, (E) honest boundary and known limits.
- **Number.** The anchor is §11.4.287 because §11.4.280 is already the per-agent decision-layer (Jev) installation anchor in this canon.
- **Machinery:** `scripts/hooks/guard-destructive-paths.py`, `scripts/lib/safe_rm.sh` with `scripts/lib/protected_paths.list`, and the tests `scripts/hooks/test_guard_destructive_paths.sh`, `scripts/hooks/test_guard_bypasses.py`, `scripts/lib/test_safe_rm.sh`.
- **Gates (with paired mutation tests):** `CM-COVENANT-114-287-PROPAGATION` and `CM-GUARD-CLASS-P-NOT-OVERRIDABLE`. Further checks are owed and listed in `docs/owed_gate_implementations.md`.
- **Documents:** [guide](docs/guides/destructive_path_safeguard.md), [manual](docs/manuals/destructive_path_safeguard_manual.md) (the decision-path diagram is embedded in the manual) and [FAQ](docs/faq/destructive_path_safeguard_faq.md); linked from `README.md`.

### Changed

- `Constitution.md` (revision 79), the four governance mirrors, `constitution_index.yaml` (297 anchors in 12 groups, group `host-and-resource-safety` 22 anchors), `groups/host-and-resource-safety.md`, `groups/project-lifecycle-and-release.md`, `scripts/anchors/anchor_lib.py` and `scripts/gates/covenant_propagation_anchors.tsv` carry the new anchor.

### Measured (2026-10-24, this working tree)

- `scripts/hooks/test_guard_bypasses.py`: pass=308 fail=0. The anchor text records 305 for this suite, so the figure in the anchor's evidence paragraph is stale by 3 and should be re-checked.
- `scripts/hooks/test_guard_destructive_paths.sh`: pass=62 fail=0 (it also runs the bypass suite).
- `scripts/lib/test_safe_rm.sh`: pass=138 fail=0.

### Honest boundaries

- **The hook is shipped, not registered.** It is not registered in any user `settings.json`; until the operator registers it, it protects nothing.
- **Known limits (from the anchor, not exhaustive):** the guard is a text scan, not a security boundary. A `# guardrails:allow <reason>` marker downgrades every overridable (H/V/U) finding in the same payload. A guard token is accepted without checking its position or reachability. `alias`, `source` of an existing file, namerefs and brace ranges are not modelled. A single-quoted `$VAR` is treated as live (false positive). A command substitution inside a larger value, a heredoc body read into a variable and used as a target, and a script written under a non-script name and run later are not followed. The guard's built-in home-children set and `protected_paths.list` are separate data aligned by a test. `safe_rm_rf` narrows, but does not close, the check-to-use race.
- Rendered twins (`.html`, `.pdf`, `.docx`) are not regenerated in this entry.

## helixconstitution-v71 — 2026-10-23 — Decision layer (Jev) §11.4.279–§11.4.286, label-sync, mandatory `helix-deps.yaml`, hub-engine resolution

**Previous tag:** `helixconstitution-v70` (`b95b853cc5c1eb61e6b5b7098026cf2b82c0605f`, 2026-10-19). **Base commit of the pre-existing part of this entry:** `5f8503b` (2026-10-22). 80 commits separate it from v70 (`git rev-list --count helixconstitution-v70..5f8503b`); the diff is 154 files, 22,390 insertions, 679 deletions (`git diff --stat helixconstitution-v70 5f8503b`). The decision-layer addition is two commits on top of that base (`089f789` the Jev layer; the second moves the `claude_toolkit` pin to `adae02d`, tag `claude_toolkit-1.32.0`). The release tag is `helixconstitution-v71`; a tag cannot name its own commit inside the file it tags, so the release commit is whatever `git rev-list -n1 helixconstitution-v71` returns.

### Added

- **Decision layer (Jev) — eight anchors, §11.4.279–§11.4.286.** Typed decisions (yes/no, choice, score) are answered by decision models (Jev hosted via TypeSafe/OpenRouter, the local `llmctl` decide gateway; Kev, Laya, Verdict and Strands profiles) before the model ladder, so only generative work spends traditional-LLM tokens. §11.4.279 detection-first mandate; §11.4.280 per-agent decision-layer installation; §11.4.281 bootstrap wizard with post-update trigger; §11.4.282 maximal use of decision instances; §11.4.283 token-reduction proof; §11.4.284 pre-ladder routing stage (amends §11.4.231 with a dated paragraph; the ladder is not extended); §11.4.285 shadow-first auto-tuning of thresholds; §11.4.286 `llmctl` and `claude_toolkit` as dependency submodules. The numbers were renumbered from a proof-of-concept that used §11.4.277–§11.4.284, which collide with the live §11.4.277 (llmctl model validation gate) and §11.4.278 (HelixQA UI QA with Vision eyes); the live anchors keep their numbers and text.
- **Gates:** four `CM-JEV-*` gates (`CM-JEV-DETECTION`, `CM-JEV-WIRING`, `CM-JEV-BOOTSTRAP-IDEMPOTENT`, `CM-JEV-TOKEN-REDUCTION`) and eight propagation gates `CM-COVENANT-114-279-PROPAGATION` to `CM-COVENANT-114-286-PROPAGATION`.
- **Machinery:** `scripts/jev/` (bootstrap wizard and tools), skill `skills/jev-decision-layer/`, MCP declaration `mcp/jev-decisions.json`, `actions/registry.yaml` rows for `/jev_bootstrap` and `/jev_status`, tests, and operator documents under `docs/jev/`.
- **Carriers and README:** compact entries for §11.4.279–§11.4.286 and the §11.4.231 amendment paragraph in `CLAUDE.md` (revision 82), `AGENTS.md` (79), `QWEN.md` (76) and `GEMINI.md` (50); README revision 9 with a "Decision layer (Jev)" section (two Mermaid diagrams).
- **label-sync (67 of the 80 commits, 2026-10-12 to 2026-10-15):** a Go core (`labelctl`, `label-busd`, state store, bus, label grammar), renderers (statusline, title, tmux status, shell integration, `labelrun`), Claude Code hooks, an idempotent `settings.json` installer with `post_update_hook.sh` step 4c, an MCP stdio server, CLI-agent adapters (kimi, opencode, crush, aider, codex, gemini, qwen), the `label-sync` skill, the gates `CM-LABEL-SYNC-CORE`, `CM-LABEL-SYNC-RENDER`, `CM-LABEL-SYNC-HOOKS`, `CM-LABEL-SYNC-MCP` with mutation tests, and the documents under `docs/label-sync/`. The commit history records several independent review rounds and their fixes (`docs/label-sync/REVIEW-FIXES.md`).
- **Mandatory `helix-deps.yaml` in every own-org repository (`1a21952`, §11.4.31, §11.4.28(C)):** canonical engine, gates and docs; hub engines resolve flat. `CM-HELIX-DEPS-REF-MATCHES-GITLINK` (`fd3f71c`) fails when a recorded ref differs from its gitlink.

### Changed

- **§11.4.231** carries a dated amendment paragraph (ladder governs generative work only); no rung is added.
- **Pins:** `claude_toolkit` moved to `1f6dad3` (flat, with `helix-deps.yaml`) in `5f8503b`; 12 behind-only submodules fast-forwarded in cascade `94b8836`; `anti_bluff`, `token_optimizer` and `llmctl` refs re-synchronised to their gitlinks in `4c5ae23`; `fd3f71c` makes the `helix-deps.yaml` refs of `docs_chain`, `continuum` and `design-toolkit` equal their gitlinks and adds the gate that enforces it.
- **`scripts/post_update_hook.sh`:** step 4b never aborts the hook before step 4c, `install_hooks` never aborts the run and uses the real hooks directory, and the step-1 changed-file list is NUL-safe.

### Fixed

- `CM-LABEL-SYNC-CORE` and `CM-LABEL-SYNC-RENDER` exited 0 when `jq`, `go`, `python3`, `grep` or `find` were absent; they now exit 2 (`84d8b48`, `b543400`).
- The label-sync findings recorded per review round: secret-safe hooks, a stale-process sweeper, signal forwarding in the spawn window, and an adapter-test server leak (see the commit log between `helixconstitution-v70` and `5f8503b`).

### Honest boundaries

- **Rendered twins are NOT regenerated in this entry.** The `.html` / `.pdf` / `.docx` siblings of `CLAUDE`, `AGENTS`, `QWEN`, `GEMINI`, `README`, `CHANGELOG`, `Constitution`, the group files and `CLAUDE_ANCHORS_FULL` are stale until `scripts/render/render-governance-twins.sh` is run upstream; the README `Twins` badge is amber for that reason.
- **README badge row not hand-edited.** Version, Anchors, Groups, Gates and Mutation badges are computed by `scripts/badges/compute_badges.sh` and show v70 values until it is re-run at tag time.
- **Decision layer evidence:** the anchors, gates and machinery are new; no end-to-end measured token reduction from a real consumer exists yet (§11.4.283 requires one per consumer).
- **Five `Auto-commit` commits** (`0876bb2` to `4bcb512`, 2026-10-20) have non-descriptive messages; the last changes `.gitignore` by two lines, the others were not itemised here.

## helixconstitution-v70 — 2026-10-19 — Progressive-disclosure layer, optimization audit and remediation, §11.4.277 / §11.4.278 + llmctl, gate hardening, README quality-badge computer

**Previous tag:** `helixconstitution-v69` (`4d0172cbf95d8f42a440151cc9ffeb84209d70af`, 2026-10-05). **Base commit of this entry:** `4ca320809665728d8c41012b72bd1a7352348b46` (2026-10-19); the release commit that carries this entry follows it. 69 commits separate the base commit from v69 (`git rev-list --count helixconstitution-v69..4ca3208`).

This is a layer-and-tooling round more than an anchor round: two new anchors (§11.4.277, §11.4.278), one in-place extension of §11.4.141 (measures M2–M9), and a large body of machinery — the progressive-disclosure layer, its measured evidence, the SIGPIPE-class gate hardening, the credential-scanner carrier strips #31–#37 and the README badge computer. `Constitution.md` is revision 76; the index carries 288 anchors in 12 groups, the progressive catalog 289 rules.

### Added

- **Progressive-disclosure layer (`progressive/`, commit `87e72cc`, remediated in `4ca3208`).** A deterministic splitter turns the canon into a 999-token lean core (`core.md`), a slim catalog (`catalog.json`, 21,052 tokens = 4.1 % of the 516,424-token monolith) and 289 per-anchor rule files; digests and line ranges live in `rules_manifest.json`. A real stdio MCP server (`mcp_server.py`) serves `search_constitution`, `load_rule`, `list_anchors` and `verify_anchor` with per-call accounting. Surfaces: skill, plugin, LSP, CodeGraph and MCP templates with a double-load guard. Five validators (`validate_structure`, `validate_behavior`, `validate_tokens`, `validate_submodule`, `validate_evidence`) and a mutation matrix (20 of 20 mutations killed). `HELIX_CONSTITUTION_MODE=monolith` restores the exact pre-optimization behaviour. `Constitution.md` is untouched.
- **Real provider token measurement (`progressive/token_harness.py`, `progressive/EVIDENCE/TOKENS_*.json`).** Claude Code 2.1.303, model `sonnet`, 24 frozen prompts: progressive arm 1,274,168 tokens against 7,168,066 for the monolithic arm (ratio 0.178), 0.6981 USD against 2.2808 USD, 24 of 24 answers correct against 22 of 24. Measurements on one host, one model, one corpus — not guarantees.
- **§11.4.277 — llmctl model validation gate (User mandate, 2026-10-12).** Every model run through llmctl by a project or any component, service or submodule (recursively) passes deterministic known-answer validation before decision-bearing use; decision-bearing use runs with `LLMCTL_VALIDATE_STRICT=1` and gates on `llmctl require-validated <profile>` (UNDETERMINED is never a pass; `LLMCTL_VALIDATE_ON_START=0` is diagnostics-only). Aligned to llmctl `v3.2.2` as shipped, including the host-safety reference values (`Restart=on-failure` with backoff, StartLimit 3/900 s, `RestartPreventExitStatus=SIGKILL SIGTERM 98`, MemoryHigh 1.25x / MemoryMax 1.5x footprint with floors, always below 90 % of RAM, `MemorySwapMax=0`, refuse at memory PSI some avg10 above 10 / full avg10 above 2 / MemAvailable below footprint plus 4 GiB), stated as host-dependent. Honest evidence boundary: one host, two runs (both pass 21 / fail 0 / undetermined 0), Vision profile `vision` only.
- **§11.4.278 — Mandatory HelixQA UI QA with Vision eyes (User mandate, 2026-10-12). STATUS: PROPOSED — operator decision 2026-10-13: ship as proposed, evidence PENDING.** No HelixQA end-to-end evidence exists yet; a real bank run through llmctl `vision` with `LLMCTL_VALIDATE_STRICT=1` and `llmctl require-validated` is a separate future work item.
- **Submodule `submodules/llmctl`** pinned to tag `v3.2.2` (`5c3dea57fb35215cdaa4b7412da438e7a8d96d86`) and recorded in `helix-deps.yaml` (§11.4.31). It is a depth-1 hub entry that MUST NOT be initialised recursively (`recursive_init: false`); the gate `CM-LLMCTL-SUBMODULE-NONRECURSIVE` (+ 12-fixture mutation test) enforces the marker and that the mutual reference with llmctl's own `constitution` pin stays finite. An unresolvable pin is BLIND (exit 2).
- **Gates.** `CM-COVENANT-114-277-PROPAGATION`, `CM-COVENANT-114-278-PROPAGATION`, `CM-LLMCTL-SUBMODULE-NONRECURSIVE`, `CM-CONSTITUTION-INDEX-FRESH` (+ paired mutation tests); the 22 mechanism gates of §11.4.277 / §11.4.278 are registered as `OWED-GATE-121` to `OWED-GATE-142` (gate code is a separate work item, NOT claimed shipped).
- **README quality-badge computer (`scripts/badges/compute_badges.sh`, `docs/BADGES.md`).** §11.4.259 applied to this repository: a badge row directly below the README title, every badge computed from the working tree (anchor and group counts from `constitution_index.yaml`, gate and mutation counts from `scripts/gates`, submodule linkage from `.gitmodules` against the recorded gitlinks, twin staleness from commit order, version from the top release heading of this file), a closed green / amber / red vocabulary, a composite readiness gauge, and a `--selftest` with golden-good, golden-bad and negative-control fixtures. A missing source of truth exits 2 (BLIND) and prints no row.
- **Exhaustive README rewrite (revision 7).** Facts at a glance, the anchor catalogue by group, the progressive-disclosure layer, token and speed machinery, credential scanning, the dependency-submodule table, the tooling map, consumption steps pinned to `helixconstitution-v70`, the six-remote topology, verification commands and the release process.

### Changed

- **§11.4.141 extended in place with measures M2–M9** (commit `f9290df`; no new anchor number, no new block-start, propagation literal unchanged): always-loaded byte budget, mandatory progressive disclosure, one task per session with no mid-session account switch, rare procedures as on-demand artefacts, mechanically checkable rules as seams, opt-in document exports, parallelism and review-round bounds, routine work on the default model tier. Measured root cause recorded: the always-loaded instruction files, not task volume, dominated recurring token spend (about 402k tokens re-injected every turn in the reference consumer).
- **§11.4.54 / §11.4.248 extended (commit `5082389`):** the ticket-id key is per-project data (`ATM-NNN` remains the default notation); engine key-grammar validation and the `atm_id` rename are owed engine work, not done.
- **Optimization packs 01–03 independently audited and remediated (commit `4ca3208`).** Real measurements replace earlier "host cannot" claims; content-based gates for account stores, ccusage, O-INV2, M-INV2 and the build cache; +8 token and +11 speed paired mutations; the ccache root cause (the build image lacked ccache and `CCACHE_EXEC` was never set) fixed in the consumer; the post-commit hook honours the document-export policy; open items recorded honestly (shared account stores, branch protection, image rebuild).
- **Credential scanner (`scripts/hooks/credential_scan_lib.sh`):** carrier strips #31–#37 (ssh-URL email adjacency, AKIA documentation placeholders, double-escaped HTML tags, bounded three-pass entity decode, synthetic PEM, reserved documentation TLDs) and removal of contiguous AKIA-shaped literals from the scanner's own source, with new sub-suites. Running the scan by default is the consumer's decision; the reference consumer made it opt-in (2026-10-17) — see `README.md`.
- **Gates: SIGPIPE-class hardening** across `scripts/gates` (`efc40b6`, `36eda36`, `01568c6`), compact-index and H2-block-boundary engine branches in the propagation engine, a consumer-side verdict-set checker for the covenant and credscan suites, and a genericised core-script literal test.
- **`helix-deps.yaml` re-synchronised with the recorded gitlinks:** `docs_chain` `8e0abe0`, `continuum` `4639347`, `design-toolkit` `4ddc964` and its grouped layout (it had pointed at `helixcode-v1.1.0`, `d88a007`, `16e4e76` and a flat layout; `design-toolkit` moved under `submodules/` in `1c89813`).
- **§11.4.230(E) quick visible first deliverable** (commit `02587b9`, operator CRITICAL mandate 2026-10-12) and its regenerated twins (`4091798`); fast-cycle (`scripts/fastcycle`) T048 structural remediation rounds 1–3; anchor recognition of bare `### N.M Title` headings and a group assignment for §11.4.276 (`45df76b`).
- **Skill frontmatter and Bridge layer (HXC-159, 2026-09-22/23):** superset skill frontmatter, a 6-layer Bridge architecture with a layer-presence gate, and the permanent `CM-NO-NESTED-MARKDOWN-FENCE-LEAK` gate.

### Fixed

- Orphan root `design-toolkit` gitlink and the `kedge` submodule removed (`33ff52e`, `fa3a9cb`); the `.gitmodules` path of `design-toolkit` corrected (`1c89813`).
- `constitution_index.yaml` regenerated after drift (`c28bacb`, `45df76b`).

### Honest boundaries

- **Rendered twins are NOT regenerated in this release.** The `.html` / `.pdf` / `.docx` siblings of the root governance files, `README`, `CHANGELOG`, the group files and `docs/owed_gate_implementations` are declared PENDING upstream regeneration (`scripts/render/render-governance-twins.sh`); the README `Twins` badge is amber for exactly this reason.
- **Gate code for the recommended mechanism gates of §11.4.277 / §11.4.278 is a separate work item, NOT claimed shipped.** §11.4.278 itself is PROPOSED with evidence pending.
- **Known failures carried into this release, not hidden** (observed 2026-10-19, none introduced by this release): `CM-CONTINUUM-RESUME-ENGINE-PRESENT` fails — it finds project-specific literals in `submodules/continuum/pkg/chain/exec_call_test.go` and `submodules/continuum/test/e2e/e2e_test.go`, and `go test -race ./...` fails `TestStress_ConcurrentWriters` with a lock-acquisition timeout (root cause UNCONFIRMED; the host was under load) — the fix belongs in the `continuum` repository. `CM-LLMCTL-SUBMODULE-NONRECURSIVE` reports BLIND here because llmctl's own `containers` pin is not initialised in this checkout (by design; it needs one extra submodule level). `progressive/validate_tokens.py` reports UNCONFIRMED without a live provider measurement. `progressive/validate_submodule.py` compares the consumer's `.constitution-pin` with this repository's `HEAD`; the consumer must re-record the pin after taking this release.
- **The 288-versus-289 anchor figure is a recorded discrepancy** (index inventory against progressive catalog), documented in `progressive/EVIDENCE/DISCREPANCIES.md`; the literal "catalog at most 5,000 tokens" target is not met (the ids plus one-line descriptions alone measure 6,034 tokens).
- **Not verified by this entry:** byte-for-byte correctness of stale twins; a full independent review of every one of the 69 commits.

### Dependency submodules at this tag

The release is recorded across the eight own-org dependencies at their recorded gitlinks: `docs_chain` `8e0abe0`, `continuum` `4639347`, `anti_bluff` `bcc7f3d`, `session_orchestrator` `78b77bb`, `token_optimizer` `c0591b5`, `helix_perf_cache` `6adcfb2`, `llmctl` `5c3dea5` (`v3.2.2`), `design-toolkit` `4ddc964`; each carries the coordinated tag `helixconstitution-v70` at that commit (§11.4.151: one prefix across the main repository and every owned submodule of a release). The fifteen third-party submodules are pinned read-only and are not tagged.

### Commit provenance (since `helixconstitution-v69`)

- `4ca3208` (2026-10-19) optimization packs 01–03 audit and remediation; evidence artifacts, token harness, slim catalog.
- `87e72cc` (2026-10-18) progressive-disclosure layer incorporated.
- `077ce4c`, `acd6261` (2026-10-17/18) credential-scan carrier strips #36/#37; context-budget measures; index drift fixes.
- `f9290df` (2026-10-17) §11.4.141 M2–M9.
- `01568c6`, `efc40b6`, `36eda36` (2026-10-15) SIGPIPE-class gate hardening.
- `c28bacb` … `427cc34` (2026-10-14) index-fresh gate, verdict-set checker, propagation-engine branches, AKIA-literal-free scanner source, llmctl pin v3.2.1 to v3.2.2, §11.4.277 re-read against v3.2.2.
- `4bcc95b`, `411389f`, `a890f60`, `83ca503` (2026-10-13) §11.4.277 / §11.4.278 and the llmctl submodule.
- `02587b9`, `4091798` (2026-10-12/13) §11.4.230(E).
- `ef82977`, `3e8e855`, `30b2dd1`, `45df76b` and related (2026-10-08) fast-cycle T048 remediation; anchor recognition.
- `a71b176` … `a174007` (2026-10-05) credential-scanner carrier strips #31–#35.
- HXC-159 commits (2026-09-13 to 2026-09-23) skill frontmatter, Bridge layer, nested-fence gate.

### Verification

Run against the live repository when this entry was written: `bash scripts/badges/compute_badges.sh --selftest` (PASS), `--check` (README badge row equals the computed row), and the README quality-badge gate family `CM-README-BADGE-ROW-AT-TOP`, `CM-BADGE-CLOSED-COLOR-VOCABULARY`, `CM-BADGE-MACHINE-DERIVED-SOURCE`, `CM-BADGE-SELF-VALIDATED`; `CM-CONSTITUTION-INDEX-FRESH` (index matches the canon's SHA-256 `1667ded1…`); `progressive/validate_structure.py` and `validate_behavior.py` (PASS). Per-remote branch tips, tags and release pages for this tag are recorded by the release tooling in the consuming repository's `qa-results/constitution_release_helixconstitution-v70/`.

## helixconstitution-v69 — 2026-10-05 — Process-safety + release-engineering + anti-slop-enforcement + review-round-budget round (14 anchors + 19 targeted extensions)

**HEAD:** `f9d1cde348a8374510d1d6f545173f5c3b2b3691`
**Round scope:** process-group signal-safety (BOB-126, 1 anchor) + release-engineering/delivery-integrity AI-curriculum harvest round 2 (4 anchors + 5 targeted extensions) + SpecKit 002-anti-slop-enforcement T402/T403/T404 (4 anchors + 3 targeted extensions) + dynamic skill activation + measurement-instrument verification + mechanical-work extraction (3 anchors) + semantic (Lumen) code-index mandate (1 anchor + 3 targeted extensions) + model-substrate corrections to the Opus/Sonnet review pin (3 targeted extensions across two dates) + incremental-delivery-granularity extension to the parallelized-pipeline anchor (3 targeted extensions across three rounds) + review-round-budget mandate (1 anchor + 2 reconciling extensions).

This round spans 381 commits on the constitution submodule between `helixconstitution-v68` (`1389ebe5a78f25d0b369a7860e6f8ccfbc4c7942`, tagged 2026-08-18) and this HEAD (2026-10-05). It is less monolithic than v68 — 9 separate landing dates rather than one batch — reflecting the project's shift (per §11.4.230(D), itself extended this round) toward per-increment delivery rather than withholding anchors until a single large round is ready.

### New universal anchors (14)

- **§11.4.263 — Process-group signal-safety mandate (BOB-126 forensic anchor, 2026-08-19).** NEVER signal `pgid ≤ 1`, NEVER trust a mock-derived pid/pgid — validate as `int > 1` before every `killpg` / `kill(-pid, sig)` / `pkill` / `killall` call. Forensic anchor: seven forced-logout incidents on the operator's workstation traced to `AsyncMock().pid` unset → `MagicMock.__int__ == 1` default → `os.killpg(1, SIGKILL)` == `kill(-1, SIGKILL)` == SIGKILL every UID-1000 process (systemd user manager, gnome-shell, tmux, ssh, Claude Code itself) — with the syscall SUCCEEDING, so exception-suppression caught nothing. Four-layer defense: pre-build grep gate, post-build CodeGraph query, runtime kernel audit rule, paired §1.1 mutation; tests MUST set `mock.pid` explicitly, never rely on mock-library defaults.
- **§11.4.264 — Build once, promote ONE immutable content-addressed artifact through every environment; never rebuild per stage (research-derived, 2026-08-20).** Exactly one artifact per release candidate, promoted by content-address (a digest, never a mutable tag) — rebuilding per environment silently breaks the chain of evidence because every gate that ran against the rebuilt artifact measured a DIFFERENT binary than the one that ships. Environment config is injected at deploy, never baked at build; rollback points at the previous known-good digest, never a rebuild-from-source scramble under incident pressure.
- **§11.4.265 — Progressive delivery: traffic-shifted rollout gated by automated analysis on SLO AND business metrics (research-derived, 2026-08-20).** Canary or blue-green rollout with an AUTOMATED promote/abort decision over multiple consecutive analysis windows — a manual-approval click is explicitly rejected as "a rubber stamp with no receipt." The load-bearing clause: the analysis MUST include business KPIs, not only infrastructure metrics — "HTTP error rate is fine" can hide a quietly-dropped checkout-completion rate, and an infra-only canary re-creates the "green pipeline that proves nothing" at the deploy layer.
- **§11.4.266 — Claim-vs-reality ledger: every ADVERTISED capability is a row, typed from the closed bluff-type vocabulary, and a capability with no passing challenge is a release blocker (research-derived, 2026-08-20).** Closed seven-member bluff-type vocabulary — green-but-broken / coverage-theater / rubber-stamp-verified / stubbed-core / doc-vs-code-drift / config-present-but-unwired / byte-identical-fork — each type routed to the anchor that already owns its counter-gate. Keyed on what the project ADVERTISES (README, docs, API/CLI surface), not what it knows it has — a claim with no feature row is invisible to a feature-keyed coverage ledger by construction.
- **§11.4.267 — Shared attempt record + converge-on-evidence / escalate-on-stall: a failed approach is never silently retried (research-derived, 2026-08-20).** A durable, shared record of attempts and outcomes is consulted BEFORE the next attempt; loops converge on a single source of ground-truth evidence (a build's exit code beats a fluent paragraph); a detected stall (the same criterion red after N tries, or oscillating diffs) routes to escalation — human or stronger model — rather than burning cycles. `N` is consumer-declared DATA, never a constitutional literal (extended this round by §11.4.276(E), see below).
- **§11.4.268 — Tamper-evident evidence chain + periodic anchor record (spec-derived, speckit 002-anti-slop-enforcement, 2026-08-26).** Deletion, reordering, and tail-truncation of an accepted evidence record are DETECTED, not merely discouraged. A forward hash-chain alone detects deletion/reorder only when it leaves the chain internally inconsistent — it does NOT detect an actor who deletes an entry and recomputes the chain forward (measured 0.43s for 100k entries); a separate periodic ANCHOR record (head digest + entry count, strength recorded honestly as `mechanism` or `policy`) closes that gap. Verification that cannot complete REFUSES, never defaults to a clean pass.
- **§11.4.269 — Critic/consensus advisory-only ban AT THE EVIDENCE-ACCEPTANCE SEAM (spec-derived, speckit 002-anti-slop-enforcement, 2026-08-26).** An ungoverned confidence score, LLM-judge, or consensus aggregation may inform but MUST NEVER substitute for a recorded receipt or adjudicate producer-verifier disagreement — recorded with role `advisory`, never entered into an evidence chain, and the accept/refuse outcome of a claim must be IDENTICAL whether the critic ran or not. Explicitly scoped NARROWER than "no second model may ever review a producer's work" — it does not weaken, override, or substitute for the constitution's own mandatory independent-review-verdict family (§11.4.125/§11.4.134/§11.4.142/§11.4.165/§11.4.209/§11.4.237/§11.4.256), all of which remain fully in force.
- **§11.4.270 — Dependency-existence-verdict register (spec-derived, speckit 002-anti-slop-enforcement, 2026-08-26).** Every proposed dependency carries a closed-set existence verdict {VERIFIED, AMBIGUOUS, UNVERIFIED} with citable evidence (or an explicit statement none was found) before adoption. Forensic motivation: "existing is not the same as working" — several VERIFIED-marked entries in a prior register were at initial-release versions, one declared a repository that 404s, and one's "tamper-evident" claim was, on inspection, only "append-only" (which detects nothing if the appender is the party being checked). Adoption is additionally gated behind mapping to a recorded uncovered capability gap and behind the wiring-sweep result.
- **§11.4.271 — Waiver mechanism (spec-derived, speckit 002-anti-slop-enforcement, 2026-08-26).** The strict FORMALIZATION of allow-with-tracked-debt, unifying §11.4.234(D)'s recorded deferral, §11.4.236(4)'s explicit-operator-override, and §11.4.248(A)'s deadline-bound quarantine into one schema: a waiver MUST resolve to a rostered, NON-PRODUCER authoriser, carry a mandatory UNELAPSED expiry, and name a mandatory tracked item for the blocker that remains open — distinct from the §11.4.21 refusal and §11.4.90 closure vocabularies, never a substitute for either.
- **§11.4.272 — Dynamic, on-demand skill/extension activation: the active capability surface is the MINIMUM needed now (User mandate, 2026-09-07).** Everything beyond a minimal declared `core` set stays inactive-by-default, discoverable, and one command away. Forensic case study: a 955-skill host pool renders ~29,153 B (~7,288 tok) of names every turn in name-only mode, and ~101,279 B (~25,319 tok/turn) in description-eager mode — a 3.5× render-mode cliff. Fails safe never silent on a bad activation; concurrency-safe by reference counting; "prune-to-core" default is structurally reversible (moved/linked, never deleted) and explicitly NOT a §11.4.122 silent removal.
- **§11.4.273 — Measuring-instrument verification: a census that INFORMS a decision must be control-needled before its result is believed (research-derived, 2026-09-08).** Forensic anchor: 15 distinct ad-hoc-measurement instrument failures in one working session — a regex missing a heading form manufactured 24 phantom anchors, `comm` on unsorted input reported false-absent, `$?` read after a pipeline reported the wrong stage's exit status, a denylist search that needled only 1 of 2 required members left a live credential undetected across four files, and more. Mandates positive control (a known-present value must be found) AND negative control (a known-absent value must NOT be found) before any decision-bearing empty/positive result is trusted.
- **§11.4.274 — Mechanical work belongs in a script, not in an agent's context (User mandate, 2026-09-08).** Deterministic, repeatable, zero-judgment work (mutation apply/run/restore/verify loops, suite fan-outs, scratch-tree setup/teardown, census queries, artifact fingerprinting) MUST be extracted into a tested, documented tool rather than performed turn-by-turn by an LLM at roughly four orders of magnitude the cost of a script. Judgment — root-cause determination, review verdicts, "is this fix correct" — MUST NEVER be scripted; a script that renders a verdict is itself a bluff gate.
- **§11.4.275 — Semantic (Lumen) index + indexing-efficiency gate + universal agent/subagent accessibility (research-derived, 2026-09-24).** Every code index (structural CodeGraph + semantic Lumen) MUST be reachable by every agent AND every dispatched subagent, proven COMPLETE (pending work == 0, known-symbol hit, negative control, freshness within TTL) before it is called ready, and must earn its place via a deterministic benchmark (fixed queries + golden answers, N≥3 identical canonical hashes, wrong answers listed by ID and never averaged away). Forensic facts: a configured semantic server reported 0 files/no model/never indexed; the structural index cut tokens 69.2% over 8 both-correct fixture queries yet answered 5 of 15 fixture queries wrong. Extended twice more within this round (2026-09-25): a host-adaptive V8 heap-budget fix closing a real OOM crash on this project's own 584K-file bulk-index run, and wiring CodeGraph as a genuine project-tracked MCP tool (which in turn surfaced and fixed a two-writer database-lock collision between the MCP serve daemon's file watcher and an in-flight bulk `sync`).
- **§11.4.276 — Review-round budget: every independently-reviewed work item converges within a declared budget of at most 7 rounds (User mandate, 2026-10-05, `CRITICAL`).** Consumer-declared ceiling in the closed range 5–7 (absent declaration resolves to 5), converged by front-loading ground truth, class-exhaustive enumeration on first instance, real-invocation-path regression tests, and a declared, fixed threat boundary, with a binding STRUCTURAL round forced at round 3+ on specific trigger conditions. Root-cause investigation (five recurring, avoidable mechanisms) traced this project's own 30–39+-round review sagas to: wrong-model ground truth shared by a fix and its own gate; instance-at-a-time closure of a nameable class; fixer-authored tests that never drive the real code; non-binding escalation signals (§11.4.250 cited ~30 times, never binding); and scope drift. At the budget ceiling without GO, the item STOPS and escalates to a recorded operator decision — never a silent 8th round.

### Targeted extensions (19)

- **§11.4.148 EXTENSION — SLICING (2026-08-20).** An item too big to test is an item whose "done" cannot be proven; mandates vertical slices only (never horizontal layers) sliced small enough that acceptance criteria are provable end-to-end from the item's own evidence. AI-curriculum module 27 (INVEST checklist, citation-disciplined to its two defined letters — Small and Testable).
- **§11.4.169 EXTENSION — SUITE SHAPE (2026-08-20).** The test-suite shape is a consequence, not a goal (no pyramid/trophy ratio is mandated); the generating rule IS mandated — push each test as far down as it still catches the bug, and a high-level-only failure with no lower-level counterpart opens a tracked follow-up. Names the ice-cream-cone and mock-heavy-unit-theater anti-patterns at the two ends.
- **§11.4.233(G) EXTENSION — DEPENDENCY-POINTER PREFLIGHT (2026-08-20).** Extends the anti-mess control plane's drifted-submodule-pointer class to three distinct mess classes — STALE, ABSENT/UNINITIALISED, and UNFETCHABLE (a pointer resolving on no configured remote) — all three fail closed at a hard preflight gate, never caught only after a fresh clone.
- **§11.4.242 EXTENSION — DELTA DEBUGGING (2026-08-20).** Generalises bisection beyond commit ranges: `git bisect` is delta debugging over commits, not the reverse — a non-monotone or non-commit-discriminated failure is narrowed along config/data/dependency/flag axes to a minimal failing case, which becomes the RED test's input.
- **§11.4.260(B)(2) EXTENSION — OBSERVABILITY mechanism (2026-08-20).** Clause (B)(2) named observability as a property; this extension supplies the mechanism — three distinct signals (structured logs, metrics, traces) plus crash/ANR analytics, a correlation id that MUST survive async boundaries, the metric→trace→log pivot order, and crash-free users/sessions as a release gate where a new crash signature at a release boundary blocks regardless of volume.
- **§11.4.115 clause (H) EXTENSION — evidence-record full field set + stream-digest-before-truncation + recorder reconciliation (2026-08-26).** Mandates a precise command-execution field schema (start timestamp, cwd, argv as a genuine list, exit status, duration), a content digest computed over a captured stream BEFORE any storage truncation, and automatic reconciliation of every evidence-citing claim against a matching recorder entry.
- **§11.4.238 EXTENSION — Discovery-channel record schema + escape-ratchet no-data-point rule (2026-08-26).** Supplies §11.4.238(C)'s coverage-escape-audit concept a decidable field schema (a closed discovery-channel set + a named `should_have_been_caught_by` seam or a justified `none`, verifier-seam-written never producer-authored) and a monotone-decreasing escape ratchet where a cycle whose manual-QA pass did not run contributes NO data point and must not lower the baseline.
- **§11.4.240 clause (F) EXTENSION — Independence-tier vocabulary + Tier-C capability-separation triggers (2026-08-26).** Closed `{instance, model, capability}` tier vocabulary for HOW MUCH producer≠verifier separation was actually achieved; same-model independent-INSTANCE verdicts are accepted (never demanded to be a different model) except at two named Tier-C triggers (producer holds evidence-store write access; the `release-tag`/`qa-deploy`/`manual-qa-handoff` seams), where capability-tier is required but a single-uid host honestly reports `instance`, never a falsely-claimed `capability`.
- **§11.4.78/§11.4.79/§11.4.80 EXTENSION — scope, launcher, runner patches and verification consumed BY REFERENCE (2026-09-24).** Closes measured gaps in the CodeGraph indexing mechanism: a self-contradictory filter clause, a config-file mismatch causing silent zero-config fallback, no derivation of scope from the submodule graph, and an anti-bluff gate that treated any database above a size threshold as a real index (so a stalled, partial index would have PASSED).
- **§11.4.78 EXTENSION — host-adaptive V8 heap budget (2026-09-25).** Fixes a real OOM crash (rc=134, ~85 minutes of bulk-index progress discarded) by computing the Node.js heap budget from measured `MemAvailable` rather than inheriting V8's ~4 GiB stock default; independently verified live via `/proc/<pid>/environ`.
- **§11.4.78 EXTENSION — heap ceiling corrected to the real §12.6 bound + CodeGraph wired as a genuine MCP tool (2026-09-25, round 2).** Corrects an earlier round's invented 64 GiB heap ceiling to the real `MemTotal * 60/100` §12.6 bound; registers CodeGraph in `.mcp.json` via a new incident-hardened, `--no-watch`-forced wrapper after discovering `serve --mcp`'s file watcher can WRITE the database, causing a real two-writer database-lock collision with an in-flight bulk `sync` during testing (recovered via `REINDEX`, no data loss).
- **§11.4.209 + §11.4.211 EXTENSION — model-substrate correction (operator mandate `CRITICAL`, 2026-09-26, landed 2026-09-28).** Re-pins the code-review and merge-conflict-resolution model substrate to Opus at `xhigh` effort ALWAYS, removing the 2026-09-15 Fable-escalation-for-big/complex clause; verbatim operator mandate: "Main model to use is Sonet, reviews and other heavy stuff have to be done by Opus instead of Fable!!! Fix this permanently on all levels!"
- **§11.4.231 EXTENSION — ladder changed to `sonnet < opus` + clause (D.1) haiku prohibition (same 2026-09-26/28 round).** Sonnet becomes the default working tier (Fable removed as a dispatch tier entirely); new clause (D.1) prohibits `haiku` where it cannot receive its governing context, grounded in a measured FACT — a `haiku` subagent dispatch failed with "Prompt too long (~421k tokens vs 200k limit)."
- **§11.4.235 EXTENSION — clause (D) FINDING-LAYER CLASSIFIER (2026-10-03).** Mandates every review verdict record a `finding_layer` from the closed set {source-defect, test-instrumentation, process-doc}, decided by the reviewer (never lowered unilaterally by the producer); research-derived from this project's own four-agent audit of a SpecKit-004 remediation saga.
- **§11.4.230 EXTENSION — clause (D) INCREMENTAL DELIVERY GRANULARITY + DECLARED QA-BUILD CADENCE (operator mandate `CRITICAL`, 2026-10-04), then corrected twice more the same day.** Original landing mandates shipping each already-proven-correct increment as it clears its own bar rather than withholding delivery until a whole spec completes. Round-2 fix-forward (same day, on an independent Opus-xhigh NO-GO: 0 Blocking/2 Important/6 Minor) re-keys the delivery unit from "trunk" to the increment's own integration branch and makes builds coalesce. Round-3 precision fix adds coalescing for failed/refused-build handling and a per-branch multi-coexistence clause.
- **§11.4.209 + §11.4.211 EXTENSION — genuine-unavailability Sonnet review fallback (operator mandate `CRITICAL`, 2026-10-04).** Relaxes the Opus-xhigh-only, no-fallback, BLOCKED-on-unavailability pin to a PRIMARY-Opus-xhigh-plus-genuine-unavailability-SONNET-fallback pin (Fable/Haiku remain permanently forbidden); verbatim operator mandate: "If we do not have access to Opus model for some reason but only to Sonnet, we MUST USE what we have! Reviews MUST BE done. ... apply the rule asap so nothing is blocked with review which is not performed yet!"
- **§11.4.267(E) + §11.4.134 EXTENSION — reconciling one-sentence extensions landed with §11.4.276 (2026-10-05).** §11.4.267(E) records that an operator-mandated ceiling carried with its own verbatim mandate in its own anchor is the one permitted `N`-bound literal that clause allows; §11.4.134's unconditional re-run-until-GO obligation is now bounded per-approach by §11.4.276, escalating at the ceiling per §11.4.276(E)(3) rather than continuing indefinitely.

### Provenance

- **Operator CRITICAL mandate driving §11.4.276 (2026-10-05)**, verbatim: "Make sure we never ever get to such extremely high never ending review rounds count! Determine exact causes of issues we are facing with deep planning and exhaustive analisys so all work ALWAYS gets done with 5 to 7 reviews max! This MUST BE mandatory part of the constitution!!!"
- **Operator CRITICAL mandate driving §11.4.230(D)'s original landing (2026-10-04)**, verbatim (abridged): "All work we do, especially SpecKit specs, gets incorporated right away. Fully deterministic validation/verification tests ... get incorporated too ... IN PARALLEL we keep building specs one by one, phase by phase, story by story, task by task. We get fast delivery results and AS SOON AS POSSIBLE builds that can be handed to QA teams for manual testing RIGHT AWAY ... We do NOT wait for all of that to finish first."
- **Operator CRITICAL mandate driving the §11.4.209/§11.4.211 Sonnet-fallback amendment (2026-10-04)**, verbatim: "If we do not have access to Opus model for some reason but only to Sonnet, we MUST USE what we have! Reviews MUST BE done. Ideally with Opus model, however Sonet MUST BE used if Opus for any reason cannot be used! ... We MUST BE maximally efficient!"
- **Operator CRITICAL mandate driving the 2026-09-26 model-substrate correction (§11.4.209/§11.4.211/§11.4.231)**, verbatim: "Main model to use is Sonet, reviews and other heavy stuff have to be done by Opus instead of Fable!!! Fix this permanently on all levels!"
- **Operator mandate driving §11.4.272 (2026-09-07)**, verbatim (abridged): "We MUST use activelly only Skills we need at particular moment! ... fully dynamic so token use is ALWAYS at the minimum and any of Skills and the extensions activated / deactivated as they are needed / used!"
- **Operator mandate driving the 2026-09-25 round-2 CodeGraph-MCP-wiring extension**, per its own landing commit message: "operator mandate: no artificial caps, indexed space exposed and used by all agents."
- **Research corpora**: the AI-curriculum module corpus (`docs/research/ai_curriculum_2026_08/source_corpus/`, modules 27/30/31/32/33/34/35 — the same corpus v68's monolithic round already harvested, mined further in this round's 2026-08-20 batch for material not used in v68) and the SpecKit `002-anti-slop-enforcement` spec (T402/T403/T404 tasks, driving §11.4.268–271 + their 3 extensions).
- **Independent review**: §11.4.276 itself was landed after an independent Opus-xhigh review returned NO-GO (2 Blocking/7 Important/6 Minor, all concrete and evidence-cited); every finding was applied directly in one remediation pass per the reviewer's own "GO-ready without another structural round" assessment — itself cited in the anchor's own header as an instance of the discipline §11.4.276 establishes. §11.4.230(D)'s original landing was likewise followed same-day by a round-2 fix-forward on an independent Opus-xhigh NO-GO (0 Blocking/2 Important/6 Minor).

### Honest boundaries per §11.4.6

- **§11.4.115 clause (H) (and the base §11.4.115 anchor itself) is NOT mirrored into CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md as of this HEAD** — independently re-verified this round: `grep -c` for the §11.4.115 block-start pattern returns 0 in all 4 mirror files and 1 in Constitution.md. This was disclosed as a deliberate, recorded exception at the 2026-08-26 landing ("syncing §11.4.115 would additionally overwrite pre-existing divergent mirror wording and insert the block currently MISSING from GEMINI.md ... that mirror gap ... is RECORDED as owed, not left implicit") and remains true today — it is an owed §11.4.157 lockstep item, not newly discovered, but not yet closed either. By contrast, §11.4.238's and §11.4.240(F)'s extension text WERE independently confirmed present and byte-identical across all 4 mirrors this round.
- **Gate code for every recommended `CM-*` mechanism gate named in this round's 14 new anchors and 19 extensions is a separate work item, NOT claimed shipped** (§11.4.6/§11.4.227) — each anchor's own text states this explicitly. `CM-CODE-REVIEW-OPUS-XHIGH` and `CM-MERGE-CONFLICT-OPUS-XHIGH` (the §11.4.209/§11.4.211 model-substrate-correction gate names) were independently confirmed UNIMPLEMENTED this round — no implementation file found under `scripts/gates/`, and `gate_ledger_removals.tsv` rows for their two predecessor-token renames (`CM-CODE-REVIEW-FABLE-XHIGH` → `...-OPUS-XHIGH-DEFAULT-FABLE-ESCALATION` → `CM-CODE-REVIEW-OPUS-XHIGH`; `CM-MERGE-CONFLICT-FABLE-XHIGH` → `CM-MERGE-CONFLICT-OPUS-XHIGH`) explicitly record each successor as "a live, currently-UNIMPLEMENTED entry counted by the ratchet."
- **§11.4.209 substrate honesty is self-referential this round**: the independent Opus-xhigh reviews cited above for §11.4.276 and §11.4.230(D) round-2 are, per their own commit messages, genuine Opus-xhigh reviews (not the Opus-best-effort-fork-substrate disclosed as a gap at v68) — this is recorded as a forward improvement, not re-asserted as fully resolved for every review in this round's full 381-commit span, which this agent did not individually audit.
- **Generated `.html`/`.pdf`/`.docx` twins WERE regenerated this round** (commit `f9d1cde`, "regenerate html/pdf/docx twins — §11.4.276 + §11.4.272-274 mirror-gap fix") — unlike v68, which left them honestly stale; this round's regeneration is real and commit-attested, not re-verified byte-for-byte by this changelog entry's author beyond confirming the commit exists and touched the expected files.
- **This changelog entry's commit-hash citations below were found via `git log -S<exact-string> -- Constitution.md`** (pickaxe search on the literal anchor-heading text), not via author self-report; where a commit's message does not itself mention the anchor number (several of the dated landings above are bundled inside `cascade:`-prefixed multi-file commits whose subject line describes an unrelated primary change, e.g. `b3a73cf` "bump submodule pointer to 6d4c2fde67b" actually carries the full §11.4.275 anchor text and the §11.4.78/79/80 extension), this is noted inline rather than silently assumed from the commit message alone.

### Commit provenance (this round on the constitution submodule)

- **§11.4.263 (2026-08-19)**: `502586c` — "anchor(§11.4.263): NEW — process-group signal-safety mandate (BOB-126 forensic anchor)".
- **§11.4.264 / §11.4.265 / §11.4.266 / §11.4.267 + the 5 AI-curriculum-round-2 extensions (§11.4.148/§11.4.169/§11.4.233(G)/§11.4.242/§11.4.260(B)(2)) (2026-08-20)**: `8d017dd` — "cascade: AI-Curriculum enforcement: wire propagation suite, close 55->0 carrier debt, fix ledger ratchet + T5 fixture, purge fabricated F-n taxonomy".
- **§11.4.268 / §11.4.269 / §11.4.270 / §11.4.271 + the 3 SpecKit-002 extensions (§11.4.115(H)/§11.4.238-ext/§11.4.240(F)) (2026-08-26)**: `baa702a` — "cascade: feat(002): anti-slop-enforcement COMPLETE — 161/162, ratchet 418->397, 4 anchors + 21 gates".
- **§11.4.272 (2026-09-07)**: `b1b4de9` — "feat(skills): §11.4.272 — dynamic on-demand skill activation, prune by default".
- **§11.4.273 (2026-09-08)**: `0bfe885` — "feat(constitution): §11.4.273 — control-needle a census before believing it".
- **§11.4.274 (2026-09-08)**: `2db64ee` — "feat(constitution): §11.4.274 — mechanical work belongs in a script, not an agent's context".
- **§11.4.275 + the §11.4.78/79/80 scope/launcher/runner-patch extension (2026-09-25 01:20, work dated 2026-09-24)**: `b3a73cf` — "cascade: chore(constitution): bump submodule pointer to 6d4c2fde67b (codegraph watcher/scope fixes + upstream churn)".
- **§11.4.78 host-adaptive heap-budget extension (2026-09-25 13:01)**: `c7f38f4` — "docs(§11.4.78/§11.4.275): extend existing anchors with today's forensic evidence — no new anchor minted".
- **§11.4.78 heap-ceiling correction + CodeGraph-MCP-wiring extension (2026-09-25 14:01)**: `8d98f1e` — "fix(codegraph): correct heap ceiling to real §12.6 bound + wire CodeGraph as a genuine MCP tool (operator mandate: no artificial caps, indexed space exposed and used by all agents)".
- **§11.4.209 + §11.4.211 model-substrate correction + §11.4.231 ladder/D.1 extension (work dated 2026-09-26, landed 2026-09-28)**: `7ce30dc` — "cascade: chore(constitution): bump submodule pointer for SpecKit-004 Foundational batch".
- **§11.4.235 clause (D) FINDING-LAYER CLASSIFIER extension (2026-10-03)**: `e44f22f` — "feat(governance): §11.4.235 extended with clause (D) FINDING-LAYER CLASSIFIER".
- **§11.4.230 clause (D) original landing (2026-10-04 01:40)**: `5fd59fa` — "feat(governance): §11.4.230 extended with clause (D) INCREMENTAL DELIVERY GRANULARITY + DECLARED QA-BUILD CADENCE".
- **§11.4.230(D) round-2 fix-forward (2026-10-04 01:56)**: `567581b` — "fix(governance): §11.4.230(D) round-2 fix-forward on Opus-xhigh review NO-GO (2 Important, 6 Minor)".
- **§11.4.230(D) round-3 precision fix (2026-10-04 02:19)**: `00697b5` — "fix(governance): §11.4.230(D) round-3 precision fix -- coalescing failed/refused-build handling + per-branch multi-coexistence clause + ledger row 107/108 parity".
- **§11.4.209 + §11.4.211 Sonnet-fallback extension (2026-10-04 16:57)**: `52da419` — "feat(§11.4.209/§11.4.211): add genuine-unavailability Sonnet review fallback; fix carrier-strip #28/#29 false-positive test fixtures".
- **§11.4.276 + §11.4.267(E)/§11.4.134 reconciling extensions (2026-10-05 12:49)**: `b0cff47` — "feat(governance): add §11.4.276 review-round budget (5-7 max, root-cause-driven)".
- **Mirror-gap fix for §11.4.272-274 across all 4 mirrors (2026-10-05 15:29)**: `1901233` — "fix(governance): close §11.4.157 lockstep gap — §11.4.272-274 missing from all 4 mirrors".
- **Generated-twin regeneration (2026-10-05 16:10, = this round's HEAD)**: `f9d1cde` — "docs(constitution): regenerate html/pdf/docx twins — §11.4.276 + §11.4.272-274 mirror-gap fix".

### Verification

All checks below were independently re-run against the live repository by the author of this changelog entry (not copied from a prior commit message):

- **Anchor presence + exactly-once block-start integrity**: all 14 new anchors (§11.4.263 through §11.4.276) confirmed present as exactly-one block-start in Constitution.md AND in each of the 4 mirrors (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md) = 14 × 5 = 70/70 block instances, via `grep -cE "^(### |\*\*)§11\.4\.<N> "` per file.
- **Lockstep byte-identity per §11.4.157**: the anchor block-start line for all 14 new anchors is md5-identical across the 4 mirror files (CLAUDE.md = AGENTS.md = QWEN.md = GEMINI.md) — confirmed individually per anchor, not assumed from a single spot-check; §11.4.276's full paragraph additionally confirmed identical across all 4 at md5 `7bea11811139cc5ed53de218f08af729`.
- **Propagation-gate literal registration**: all 14 new anchors (`11.4.263` through `11.4.276`) present as registered `CM-COVENANT-114-<N>-PROPAGATION` rows in the data pack `scripts/gates/covenant_propagation_anchors.tsv`.
- **Fast-forward push completion (§2.1 + §11.4.113)**: `git ls-remote --heads <remote> main` returns `f9d1cde348a8374510d1d6f545173f5c3b2b3691` — identical to local HEAD — on all 8 configured remotes (gitflic, github, gitlab, gitverse, origin, upstream, vasicdigitalgithub, vasicdigitalgitlab); 8/8 in sync at the time this entry was written.
- **Gate-ledger ratchet baseline**: `scripts/gates/gate_ledger_baseline.txt` currently reads `402` (the monotone-decreasing unimplemented/deferred-gate count per §11.4.227(A), down from 418 and 403 at intermediate points this round per commit messages — not independently re-derived from first principles by this entry, cited as the file's current committed value).
- **Not verified by this entry** (left for the operator / a future audit, per the honest-boundaries section above): byte-for-byte correctness of the regenerated `.html`/`.pdf`/`.docx` twins; full §11.4.209-substrate audit of every one of the 381 commits in this round; whether a `helixconstitution-v69` tag has actually been created yet (none existed at the time this entry was written — `git tag -l helixconstitution-v69` returned empty).

### Anchor propagation gates landed this round

`CM-COVENANT-114-263-PROPAGATION` through `CM-COVENANT-114-276-PROPAGATION` (14 gates) = 14 new anchor-block-start propagation gate literals present in this round's Constitution.md + 4-mirror Status summary text and registered in `scripts/gates/covenant_propagation_anchors.tsv`.

---

## helixconstitution-v68 — 2026-08-18 — MONOLITHIC amendment round (22 anchors + 5 targeted extensions + §11.4.140/141 collision resolution)

**HEAD:** `1389ebe5a78f25d0b369a7860e6f8ccfbc4c7942`
**Round scope:** AI-curriculum-modules-27-35 harvest (18 anchors) + operator's 9-point enterprise-quality mandate (6 anchors) + 5 targeted extensions to existing anchors + collision remediation for the long-standing §11.4.140 / §11.4.141 double-mandate (§11.4.54 anchor-number reuse).

This is the largest amendment round in the project's history: **22 net-new universal anchors + 33 targeted extensions (5 in this round, 28 in prior 2026-07 through 2026-08 rounds now consolidated)**, landed as a single monolithic commit followed by 4 lockstep-mirror commits and a 1 extensions commit.

Per §11.4.126 release-scope terminal condition + §11.4.113 absolute-no-force-push, this tag was created only after: (a) full amendment-region md5 lockstep-identity verified across the 4 mirrors (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md); (b) exactly-once block-start integrity per §11.4.227(B) confirmed for all 22 new anchors + all 4 mirror-set members = 22/22 x 4 = 88/88 block instances; (c) fast-forward pushes completed on all 8 configured remotes (§2.1); (d) consumer-project pointer bump verified on boba HEAD `f8aa956` across all 3 boba remotes.

### New universal anchors (22)

**AI-curriculum modules 27-35 harvest (§11.4.239-§11.4.254 → 16 anchors, condensed):**

- **§11.4.239 — Critical-invariant work-class Definition of Done mandate.** Every DoD MUST identify a closed CRITICAL-INVARIANT WORK CLASS (money movement, safety-of-life/property outputs, availability of the primary user-facing capability, integrity of the persistent record) and MUST require that every change touching this class carry EXPLICIT FAILURE-PATH SCENARIOS as passing tests BEFORE closure. Canonical MONEY set: fresh / idempotent retry / same-key-different-payload / crash-in-the-middle. Composes §11.4.146(D3) status-custody chain.
- **§11.4.240 — Producer ≠ Verifier scope separation.** STRUCTURAL SEPARATION between the actor that PRODUCES a change/artifact/verdict and the actor that GATES it — the producer cannot write, weaken, delete, or edit the acceptance tests, oracle, gate configuration, verdict store, paired §1.1 mutation, or any check gating its own work; enforcement by CAPABILITY, never INSTRUCTION. Mutual composes with §11.4.249 four-role architecture.
- **§11.4.241 — Illegal-state-unrepresentability preference ladder.** Every load-bearing invariant lands at the STRONGEST enforcement rung the target language/toolchain supports: type-system > API-shape > lint > property-test > runtime-assert. Defect PREVENTABLE at rung N caught only at rung > N is a finding.
- **§11.4.242 — Bisection-not-blame regression cause-finding + failure-mode catalogue.** First-choice mechanism is `git bisect` (O(log N)) over range from last known-good tag to HEAD, NOT blame-log walking (O(N)) NOR speculative hunting. Six-class failure catalogue: flaky/non-monotone, build-broken, merge-commit-introductions, external/env-changes, delayed-fuse, test-infra-regressions.
- **§11.4.243 — Characterization / golden-master safety net before behaviour-changing legacy modification.** Before ANY behaviour-changing modification to legacy code, author CHARACTERIZATION TESTS asserting CURRENT observable behaviour as GROUND TRUTH. Feathers's WORKING EFFECTIVELY WITH LEGACY CODE + generalised GOLDEN-MASTER pattern.
- **§11.4.244 — Cross-boundary contract tests + can-i-deploy gate.** Changes modifying independently-deployable boundaries MUST be covered by CONSUMER-DRIVEN CONTRACT TESTS on both sides AND a `can-i-deploy` gate MUST verify proposed provider version compatibility against every currently-deployed consumer version BEFORE the change ships. Merges the two mechanisms as they are useless in isolation.
- **§11.4.245 — Oracle-problem-first test authoring.** Every test MUST FIRST identify its ORACLE — mechanism deciding PASS vs FAIL — DIFFERENT from code under test AND from test's own assertion mechanism. Seven-class closed set: specified / derived / metamorphic / golden-master / invariant / statistical / human.
- **§11.4.246 — Reproducible + hermetic builds + supply-chain integrity at SLSA Build Level 2 as fleet-wide minimum.** Operator decision 2026-08-15: SLSA L2 is fleet-wide minimum, L3+ tracked as backlog per §11.4.197. Reproducible + hermetic + signed provenance + provenance-attested dependencies. Boba already satisfies ancillary requirements (SSH-only §2.1, rootless podman §11.4.161, fixed-tag pins §11.4.30/§11.4.77).
- **§11.4.247 — Composite-output layer-move must move every layer.** When a change moves a system-boundary layer, MUST move EVERY LAYER of the composite output atomically or via explicit compatibility window. Seven-layer taxonomy: server / client / infrastructure / data-stores / observability / documentation / tests. Zero-residuals check.
- **§11.4.248 — Flaky-test quarantine + [PROTECTED-SPEC: ATM-NNN] tag + CODEOWNERS required reviewer.** Operator decision 2026-08-15 for the tag+CODEOWNERS mechanism. Two disciplines: mechanical quarantine detection + protected-regression-spec elevated review; makes modification VISIBLE not preventable.
- **§11.4.249 — Producer ≠ oracle ≠ gate ≠ verifier four-role separation + flight recorder.** Four distinct roles that MUST be structurally separate: PRODUCER / ORACLE / GATE / VERIFIER. Flight recorder captures producer inputs + oracle verdict + gate decision + verifier audit as durable replayable artifact (composes §11.4.116 event stream + §11.4.207 content-addressed). Four detectable-collapse taxonomy.
- **§11.4.250 — Heuristic-tower signals a primitive defect.** Codebase accumulating TOWER of heuristics compensating for same underlying issue IS the diagnostic: primitive is defective. Systematic-debugging response on tower depth ≥ 2: stop, invoke §11.4.102, fix primitive, remove layers one at a time.
- **§11.4.251 — Byte-identical-fork prohibition + role-as-data-pack extraction.** Copies differing only in configuration/data/role-specific parameters MUST NOT be maintained as parallel forks. Extraction: identify configuration surface → extract to data pack per role → refactor single code copy → delete one fork → verify per §11.4.5 → commit extraction per §11.4.124.
- **§11.4.252 — Fail-closed-on-dangerous-combination.** Every code path COMBINING ≥ 2 dangerous capabilities (mutation / untrusted-input / credential-access / external-side-effect / shell-exec / irreversible) MUST FAIL CLOSED. Security-engineering generalisation of §11.4.201 guard-honesty. Six-class dangerous-combination taxonomy.
- **§11.4.253 — Idempotency under retry + DB-level durable uniqueness guard.** Every retryable operation MUST BE IDEMPOTENT: N executions = same observable end state as one. Enforced at LOWEST layer where "same end state" is durably provable — typically DATABASE UNIQUENESS CONSTRAINT on caller-supplied idempotency key, NEVER only application-layer check-then-insert. Prevents DOUBLE-CHARGE / DOUBLE-EMAIL / DOUBLE-DELETE / DOUBLE-EFFECT bugs.
- **§11.4.254 — Boot-time invariant assertion + capability matrix.** Every service MUST assert BOOT-TIME INVARIANTS at startup and FAIL FAST + LOUD if violated. Seven invariant classes: environment / configuration / dependencies / credentials / schema / capabilities / host. Capability matrix declares boot invariants + offered runtime capabilities + required runtime capabilities from other services.

**Operator 9-point enterprise-quality mandate (§11.4.257-§11.4.262 → 6 anchors):**

- **§11.4.257 — Comprehensive user-manual + guide + FAQ coverage.** Every consuming project MUST cover the whole project with three cooperating documentation classes: complete USER MANUAL per component/service/product, task-oriented GUIDES for every user-facing workflow, properly-created FAQs derived from real operator/QA/end-user questions. Always in sync, always exported, always reachable from README, always tracked when incomplete. Generalises §11.4.18 + §11.4.153 to whole-project doc coverage.
- **§11.4.258 — Architectural + data-flow + state-machine + sequence-diagram coverage.** Every consuming project MUST cover the whole project with properly created graphs/diagrams/schemes across FOUR canonical classes: system architecture / data flow / state machine / sequence. INCORPORATED at the point of use, NEVER an orphan gallery. Open-format-diffable (Mermaid/PlantUML/D2/diffable SVG). Strengthens §11.4.218/§11.4.219 (design-side) to whole-project.
- **§11.4.259 — README quality-status badge row.** Every consuming project's README MUST carry, at the TOP (immediately below the H1), a comprehensive BADGE ROW with closed color vocabulary GREEN/AMBER/RED/GRAY, minimum floor covering build / test-breadth / coverage / security / documentation completeness / diagram completeness / live health / open defects / supply-chain integrity / zero-shortcomings verdict / machine-evidence coverage / PRODUCTION-READINESS GAUGE. Every badge machine-derived, self-validated. Extends §11.4.57.
- **§11.4.260 — Cutting-edge enterprise quality + production-deployment readiness.** Every work product MUST be built for cutting-edge enterprise quality targeted at production deployment + maximal stability + zero nasty surprises — standing default from first prompt. Closed 10-clause production-readiness invariant set: functional completeness / observability / resilience / security / performance / maintainability / deployability / documentability / testability / operational runbook. Strengthens §11.4.190 (web-only) to universal.
- **§11.4.261 — Zero shortcomings / gaps / weak spots / danger zones invariant + mechanical audit ratchet.** Every consuming project MUST hold at ALL TIMES exactly ZERO findings across code / services / components / gates / docs / config — enforced by mechanical audit sweep from a CLOSED 10-class vocabulary. Monotone-decreasing ratchet (§11.4.135 pattern). Every finding either CLOSED (evidence at defect layer per §11.4.226) OR TRACKED (§11.4.197 + §11.4.148 + §11.4.223 + §11.4.101 + §11.4.135). Generalises §11.4.124 + §11.4.118 + §11.4.238.
- **§11.4.262 — Machine-created + machine-verifiable evidence at every gate.** Every claim of works/passes/verified MUST cite MACHINE-CREATED + MACHINE-VERIFIABLE evidence — no operator eyeballing, no narrative-only PASS, no prediction, no assumption. Strengthens §11.4 covenant preamble from CAPTURED to CAPTURED-AND-MACHINE-VERIFIABLE. Applies §11.4.107(10) self-validating analyzers universally. Three-gate coverage: confirmation / validation / verification.

### Targeted extensions (5)

Applied this round in commit `1389ebe`:

- **§11.4.212 EXTENSION clauses (E) + (F)** — README introduction + illustration coverage + linkage-completeness ratchet. Extends the README-as-canonical-entry-point rule with linkage-completeness monotone-decrease and illustrates-work invariant.
- **§11.4 covenant preamble EXTENSION** — machine-created evidence at every gate binding. Anchors the §11.4.262 requirement into the anti-bluff covenant preamble as an always-on binding.
- **§11.4.108 EXTENSION clause (7)** — each of the 4 four-layer verification layers MUST cite machine-created + machine-verifiable evidence produced at THAT layer; higher layer citing lower-layer-only = §11.4.226 wrong-layer violation.
- **§11.4.224 EXTENSION (B)** — 7-canonical-test-type coverage floor with 100% aim, cross-referenced to §11.4.27 seven test types.
- **§11.4.27 EXTENSION (B)** — 7-canonical-type breadth enumeration explicit, cross-referenced from §11.4.224.

### §11.4.140 / §11.4.141 collision resolution (§11.4.255 + §11.4.256 re-mint)

Long-standing operator-owned anchor-number collision resolved this round in commits `5ed8c80` (Constitution.md re-mint) + `6dff307` (CLAUDE.md mirror) + `f497412` (AGENTS.md mirror) + `9e45dec` (QWEN.md mirror) + `e5f2891` (GEMINI.md mirror):

- **§11.4.140 (translation pipeline sense)** re-minted to **§11.4.255** — HelixTranslate canonical translation pipeline (2026-06-25 mandate). §11.4.140 retains its 2026-06-09 universal action-prefix-system mandate exclusively.
- **§11.4.141 (per-language review sense)** re-minted to **§11.4.256** — independent per-language translation review (2026-06-25 mandate). §11.4.141 retains its 2026-06-09 token-efficiency mandate exclusively.
- All cross-references in the 4 mirrors updated to the new anchor numbers; §11.4.237 (context-and-spirit translation review) now cites §11.4.255/§11.4.256 rather than the ambiguous §11.4.140/§11.4.141. No new collision introduced.

### Provenance

- **AI curriculum extraction**: 9 modules (27-35), 7,096 lines, sourced from local instructor mirror `http://mistborn.local:8099/` under §11.4.99 latest-source-verification cadence + §11.4.150 deep multi-angle web research.
- **Operator-answered decisions on 2026-08-15**:
  - SLSA Build Level 2 as fleet-wide minimum (rather than L3+ immediately, tracked per §11.4.197).
  - [PROTECTED-SPEC: ATM-NNN] tag + CODEOWNERS required-reviewer mechanism (rather than harder mechanical block or lighter warning).
  - 5-atomic-commit strategy for landing the 22 anchors (Constitution.md monolithic + 4 mirror commits, rather than 22 separate anchor commits).
  - Resolve §11.4.140/§11.4.141 collision FIRST (5 commits `5ed8c80..e5f2891`), then land the 22 anchors, then land the 5 extensions.
- **§11.4.209 substrate honest disclosure per §11.4.231(F)(b) harness gap**: this round's independent code-review ran on the Opus best-effort parent-inherited fork substrate. The Claude Code Agent tool exposes a `model` parameter but NO `effort` parameter, so subagent effort is not presently settable via that path — the §11.4.182 `<effort>` label field degrades honestly to `?` per §11.4.6. This is not a Fable-`xhigh` review as §11.4.209 mandates by default; a re-review at the true §11.4.209 Fable-`xhigh` substrate via the Workflow-tool `agent()` path REMAINS RECOMMENDED (not blocking) before the 22 anchors are considered fully substrate-verified, tracked as an owed §11.4.197 upgrade item.
- **Round 2 iterate-to-GO per §11.4.134**: subagent `a6b89ff0` returned all IMPORTANT-1/2/3 + MINOR-1/2/3/4 findings resolved, zero new BLOCKING or IMPORTANT introduced. Structural layer (§11.4.227(B) block-integrity + §11.4.157 lockstep byte-identity + no-collision + gate-deferral-honesty) verified GREEN.
- **Fable-substrate review of the 2026-07-26 round precedent**: substantive-on-structural verified GREEN on round 2, per the §11.4.134 iterate-to-GO discipline.

### Honest boundaries per §11.4.6

- **§11.4.241-254 shipped in condensed form** in commit `697c750` (the monolithic anchor commit), grouped into 16 anchors covering the 9 AI-curriculum modules (27-35). Full canonical text expansion for each of §11.4.241-254 as separate top-level `### §11.4.NNN` blocks in Constitution.md is tracked as an owed §11.4.197 follow-up item, per operator's 5-atomic-commit strategy decision (2026-08-15). The mirror files (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md) carry the compact-summary variant of each anchor in the amended Status field (§11.4.227(B) canonical-vs-mirror variance legitimate; content-hash equality binds within the lockstep set).
- **§11.4.209 substrate**: as disclosed above, this round's review substrate is opus-class best-effort, not Fable-`xhigh`. A future round SHOULD re-review the 22 new anchors on Fable-`xhigh` when the Workflow tool path becomes available; that upgrade is a tracked §11.4.197 item, not a claim of shipped Fable-xhigh review.
- **Recommended per-anchor mechanism gates** (`CM-*` tokens introduced in the 22 anchors' anti-bluff paragraphs) are `gate-code = separate work item, NOT claimed shipped` per §11.4.6/§11.4.227. This round lands the ANCHOR TEXT + PROPAGATION GATE literals (`CM-COVENANT-114-239-PROPAGATION` through `CM-COVENANT-114-254-PROPAGATION` + `CM-COVENANT-114-257-PROPAGATION` through `CM-COVENANT-114-262-PROPAGATION` = 22 new anchor-block-start propagation gates); the 40+ recommended mechanism gates each anchor names are separate follow-up items per §11.4.227.
- **Generated `.html` / `.pdf` / `.docx` twins NOT regenerated this round** — the governance-twin exporter is still not a documented runnable in-repo script (§11.4.106(E)); twins remain honestly STALE pending the exporter commit. No silent divergence claimed otherwise.

### Commit provenance (this round on the constitution submodule)

- **Phase 0 (§11.4.140/141 collision resolution, 2026-08-15)**: `5ed8c80` (Constitution.md re-mint to §11.4.255/§11.4.256) → `6dff307` (CLAUDE.md mirror) → `f497412` (AGENTS.md mirror) → `9e45dec` (QWEN.md mirror) → `e5f2891` (GEMINI.md mirror).
- **Prior amendments to prior amendment round (2026-08-05..07)**: `47d41f8` (docs_chain incorporation per §11.4.106/§11.4.28(C) carve-out) → `c6f8da8` (missing `helix-deps.yaml` per §11.4.31).
- **Phase 3 landing (2026-08-15)**: `697c750` — MONOLITHIC amendment round, 22 new anchors §11.4.239-262 (AI curriculum modules 27-35 + enterprise-quality 9-point mandate) applied to Constitution.md.
- **Phase 3 mirror fix-forward (2026-08-15..16)**: `4c5bcaa` (CLAUDE.md mirror lockstep) → `277ca6f` (AGENTS.md mirror lockstep) → `d00bc2a` (QWEN.md mirror lockstep) → `00bbd49` (GEMINI.md mirror lockstep).
- **Phase 3 extensions (2026-08-17)**: `1389ebe` — 5 targeted extensions per unified amendment round §11.4.212 / §11.4 preamble / §11.4.108 / §11.4.224 / §11.4.27.

### Verification (per §11.4.227(B) + §11.4.157)

- **Block-integrity per §11.4.227(B)**: 22/22 new anchors present as exactly-once block-starts in each of Constitution.md + 4 mirrors = 22 × 5 = 110/110 block instances verified.
- **Lockstep byte-identity per §11.4.157**: md5 `90c0607d0b34fb020040772007911d65` byte-identical across the 4 mirrors CLAUDE.md + AGENTS.md + QWEN.md + GEMINI.md for the amendment region; Constitution.md carries the canonical `### §11.4.NNN` heading variant per §11.4.227(B) canonical-vs-mirror layer variance legitimate.
- **Fast-forward push completion (§2.1 + §11.4.113)**: 43/43 pushes complete across the 8 configured remotes for the constitution submodule (github HelixDevelopment, gitlab HelixDevelopment1, gitflic HelixDevelopment, gitverse HelixDevelopment, github vasic-digital, gitlab vasic-digital, and the origin+upstream multi-push wrappers).
- **Consumer pointer bump (§11.4.26 step 7)**: boba HEAD `f8aa956` on all 3 boba remotes verified 0/0 in-sync.

### Anchor propagation gates landed this round

`CM-COVENANT-114-239-PROPAGATION` through `CM-COVENANT-114-254-PROPAGATION` (16 gates) + `CM-COVENANT-114-257-PROPAGATION` through `CM-COVENANT-114-262-PROPAGATION` (6 gates) = 22 new anchor-block-start propagation gate literals present in this round's Status summary text across the mirror set.

---

## Prior tags

### v1.0.0 — 2026-07-24 — first constitution version tag

This tag captures the constitution state at the end of the 2026-07-22→24
work round, bracketed by `helixcode-v1.1.0` (2026-07-12) and current HEAD.
**182 commits** of systematic governance codification, measurement-semantics
harvest, design-methodology round, and tooling hardening.

#### Added

- **§11.4.216–223 — Design-methodology codification round (2026-07-22).**
  Eight new anchors codifying the design-methodology harvest from the
  Helix Thready MVP design: problem-first, research-before-design,
  architecture-before-components, data-first, security-by-design,
  testability-by-design, design-documentation, and iterative-design.
- **§11.4.224 — Test-first (TDD) for all work + >=85% code-coverage floor.**
  Necessary but never sufficient — coverage without runtime-evidence is a
  §11.4 bluff.
- **§11.4.225 — Measurement-semantics codification.** The distinction
  between carrier and thing, null-is-not-evidence, and the control-needle
  principle codified as mandatory rule.
- **§11.4.226 + §11.4.227 + §11.4.194(6) — Reopen / first-touch root-cause
  harvest.** Reopens now trigger a mandatory systematic-debugging pass and
  permanent regression guard; first-touch tasks are tracked to prevent
  silent re-entry.
- **§11.4.228 — Cross-agent extension lifecycle + speckit exports.**
  Defines the lifecycle for extensions shared across CLI agents and exports
  the speckit bridge documentation to all governance carrier files.
- **§11.4.115(G), §11.4.201(9)–(12), §11.4.67(6), §11.4.142-FACT** —
  Extensions from the HEL-010 systematic-debugging / measurement-semantics
  harvest of 2026-07-23.
- **Shell-instrument footgun checklist** (7 documented footguns — I1 through
  I7) encoding recurring instrument-caused failures.
- **Mechanical anti-bluff seams engine** (`submodules/anti_bluff`) —
  reusable, decoupled from any single project.
- **SpecKit-Superpowers bridge documentation** — comprehensive implementation
  guide for the constitution-powered bridge.

#### Fixed

- **Credential scan (cred-scan) carrier strips #5, #6, #7.** Multiple
  false-positive carrier-identification bugs in detectors 1 and 2 patched
  (ATM-864): markdown-word heuristic, proximity-window over-match, and
  value-starts-with-reference/placeholder sigil.
- **Workable-items engine fixes:** reopen body-preservation, orphaned-bullets
  (F1), SQL index gaps (missing indexes on status/type/location/attribution),
  unbounded queries, dot-separator for non-canonical IDs.
- **SECURITY: `report_item.sh` hardened.** Replaced `eval` with `bash -c`;
  indirect expansion for credential checks.
- **Multitrack hardening:** owner-lock fix, probe-race fix, config
  alias-exclusion, conductor-slot exclusion, §11.4.201(4)/§11.4.111 PARSE
  guard.
- **Curl timeouts** added across the tooling surface.

#### Docs

- Companion docs for §11.4.141 (`scoped_read.sh`, `token_efficiency_lib`,
  `context_compactor`) per §11.4.18.
- Pandoc twins regenerated for Rev 54 (§11.4.216–223 amendment).
- BG-QUALITY-ROOTCAUSE Phase 4 deliverables documented.
