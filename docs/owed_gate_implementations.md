# Owed gate implementations — §11.4.227(A) deferral registry

**Revision:** 6
**Last modified:** 2026-10-05T09:59:56Z
**Description:** The tracked work items every row of `scripts/gates/gate_ledger_deferrals.tsv` points at.
**Authority:** §11.4.227(A) (named-gate ledger + monotone-decrease ratchet), §11.4.197 (started work reaches a terminal state), §11.4.6 (no-guessing).

**R6 (2026-10-05, currency check):** this document had fallen 8 rows behind `gate_ledger_deferrals.tsv` — `OWED-GATE-106` (§11.4.235(D), registered 2026-10-03) and `OWED-GATE-107` through `OWED-GATE-110` (§11.4.230(D), registered 2026-10-04) were both already in the TSV but documented nowhere in this file; `OWED-GATE-111` through `OWED-GATE-113` (§11.4.276, registered the same session as this currency check) were likewise TSV-only. All 8 are now documented in Section A below (new `### §11.4.235(D)`, `### §11.4.230(D)`, and `### §11.4.276` subsections). Verified by direct diff against the live TSV (`grep -E "OWED-GATE-10[6-9]|OWED-GATE-11[0-3]"`), not assumed.

## Why this document exists

§11.4.227(A) requires every `CM-*` gate named in the governance corpus to be **either**
implemented in an executable gate site **or** covered by a **registered deferral pointing at a
tracked item**. Silent gate debt is forbidden, and so is deleting a name to lower the count.

**64 of this document's then-76 `OWED-GATE-NNN` entries are still genuinely owed**
*(figure predates Section D, which registered 15 further ids on 2026-08-26 — re-derive per the
instruction below rather than adding to this number)* — confirmed
2026-08-20T15:32:40Z by diffing every `OWED-GATE-NNN` entry's backtick-quoted gate name (Sections A
+ C, numeric ids only — the non-numeric `OWED-GATE-ADV-F*` findings in Section B.1 are review
findings, not gates, and are excluded) against the first column of
`scripts/gates/gate_ledger_deferrals.tsv` (72 rows total; a control-needle overlap check confirmed
the diff instrument is not blind, §11.4.201(7)(b)). The remaining 12 entries already resolve to a
landed gate-site file under `constitution/scripts/gates/` — they are IMPLEMENTED, not yet pruned
from this list, and their discharge is a *different* stream's call, backed by a passing §1.1
mutation test (§11.4.227(A) Acceptance Criterion 5). **This count is a live snapshot, not a fixed
figure** — the TSV is under active concurrent implementation and the number moves; re-derive it
by re-running the same diff rather than trusting this sentence after the fact. *(Historical note:
an earlier draft of this sentence read "66" — no interpretation checked against evidence at the
time this note was written [Section A entry count, this document's total `OWED-GATE-NNN` count,
the TSV's row count, or the ledger's own live `unimplemented=` figure per §11.4.227(A), which reads
420 and matches the checked-in `gate_ledger_baseline.txt`] equalled 66 under any of those readings,
so the figure has been replaced with the one above rather than guessed at, §11.4.6.)* Each
still-owed gate needs a genuine per-domain harness (a build-reproducibility comparison, a SLSA
attestation verifier, a contract broker, a diagram-accuracy oracle, …). **Implementing them as
stubs that cannot FAIL would be the exact §11.4 bluff this corpus forbids** — a gate that cannot
refuse is decoration, and per §11.4.115(F) a guard never observed FAILing on a genuinely-broken
artifact is unvalidated instrumentation that mints nothing. So they are registered as **owed
debt**, visibly counted and monotone-decreasing, rather than faked green.

**Honest boundary (§11.4.6):** registering a deferral proves the debt is *tracked*, not that the
gate *works*. Each item is discharged only when its executable site lands with a paired §1.1
mutation observed to make it FAIL.

## Acceptance criteria (apply to every `OWED-GATE-*` item)

An item is discharged when **all** hold:

1. An executable gate site exists under `scripts/` carrying the gate's literal name structurally
   (§11.4.201(7)(a) — a prose carrier never counts).
2. A paired §1.1 mutation exists and was **observed** to make the gate FAIL before the gate is
   trusted (§11.4.115(F) observation-before-trust).
3. Golden-good **and** golden-bad fixtures are wired, plus a negative control where a
   false-positive refusal is possible (§11.4.107(10), §11.4.201(1)).
4. Any absence the gate reports is control-needle-proven (§11.4.201(7)(b)).
5. The gate's row moves out of `gate_ledger_deferrals.tsv`, and the ledger baseline in
   `scripts/gates/gate_ledger_baseline.txt` ratchets **down**, never up (§11.4.227(A)).

## A. Owed gate implementations


### §11.4.27

- **OWED-GATE-053** — `CM-TEST-TYPE-BREADTH-SEVEN-CANONICAL`
  - **Must assert:** asserts a consuming project's suite covers all seven canonical test types where applicable with honest SKIP-with-reason where not
  - **Blocked on:** needs the canonical type list and per-type detector as consumer DATA

### §11.4.33

- **OWED-GATE-012** — `CM-CLOSURE-VOCAB-TYPE-AWARE`
  - **Must assert:** asserts every closed item Status matches its Type - Bug to Fixed, Feature to Implemented, Task to Completed
  - **Blocked on:** the Issues/Fixed tracker DATA is consumer-owned and absent from this project-agnostic repo

### §11.4.148

- **OWED-GATE-071** — `CM-ITEM-SLICED-SMALL-AND-TESTABLE`
  - **Must assert:** asserts every item carries acceptance criteria whose satisfaction is decidable from that item's own evidence and is a vertical slice - a thin end-to-end capability a user can observe; a horizontal-layer item, or one whose criteria depend on a sibling item landing, FAILs naming the item
  - **Blocked on:** the workable-items tracker DATA is consumer-owned and absent from this project-agnostic repo, the same blocker class as OWED-GATE-012
  - **Paired 1.1 mutation:** re-shape one item into a horizontal layer whose criteria cannot be met alone and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a legitimately-dependent item that is nonetheless independently testable once its dependency is met MUST NOT fire it

### §11.4.169

- **OWED-GATE-075** — `CM-SUITE-SHAPE-DECLARED-AND-PUSHED-DOWN`
  - **Must assert:** asserts the project declares its chosen suite shape together with the risk-location justification that selected it, and that a high-level test failing with no lower-level counterpart opens a tracked 11.4.197 item to add the lower-level test
  - **Blocked on:** needs a consumer suite-shape declaration plus a test-level classifier able to tell high-level from low-level tests, neither adopted
  - **Paired 1.1 mutation:** remove the shape declaration, or record a high-level-only failure with no tracked lower-level follow-up, and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a declared trophy shape on a genuinely I/O-heavy system MUST NOT fire it merely for having few unit tests

### §11.4.233

- **OWED-GATE-069** — `CM-DEPENDENCY-POINTER-PREFLIGHT-FAIL-CLOSED`
  - **Must assert:** asserts the preflight resolves every submodule pointer, verifies it matches the intended ref, fails closed on a missing checkout, and for the truly load-bearing components asserts a runtime signature on the flashed or deployed artifact - closing all three mess classes stale, absent-uninitialised and unfetchable
  - **Blocked on:** separating the unfetchable class from the merely-absent class requires probing configured remotes, and the hermetic pre-build gate run has no guaranteed network reach
  - **Paired 1.1 mutation:** de-initialise one submodule and the gate MUST FAIL; point one gitlink at a commit no configured remote serves and it MUST FAIL; golden-FALSE - a fully-initialised tree at its intended refs MUST NOT fire it

### §11.4.234

- **OWED-GATE-013** — `CM-COMMIT-PUSH-ALWAYS-UNBLOCKED`
  - **Must assert:** asserts a failing validation yields a clear per-check report and a documented remediation path, never an opaque hung or rejected push
  - **Blocked on:** the consumer binds its own commit/push script path as DATA per 11.4.35
- **OWED-GATE-019** — `CM-DEDICATED-HOOK-VALIDATION-SCRIPT`
  - **Must assert:** asserts hook validations run as an explicit named stage of a dedicated idempotent commit/push script
  - **Blocked on:** the consumer binds the script path as DATA per 11.4.35
- **OWED-GATE-029** — `CM-HOOKS-NEVER-BLOCK-PUSH`
  - **Must assert:** asserts core.hooksPath does not gate routine commit/push while the hook file itself stays preserved and unmodified
  - **Blocked on:** the consumer binds its repo and hook paths as DATA
- **OWED-GATE-038** — `CM-NO-GATE-LOST-ON-HOOK-DISCONNECT`
  - **Must assert:** asserts every check a disconnected hook performed still executes at a named script stage or release gate
  - **Blocked on:** needs the consumer-owned stage list and deferral registry

### §11.4.236

- **OWED-GATE-045** — `CM-QA-DEPLOY-READINESS-GATE`
  - **Must assert:** asserts no manual-QA hand-off occurs without a machine-written PASS verdict whose artifact fingerprint equals the candidate
  - **Blocked on:** requires a verdict store keyed on artifact fingerprint

### §11.4.237

- **OWED-GATE-054** — `CM-TRANSLATION-CONTEXT-SPIRIT-REVIEW`
  - **Must assert:** asserts each localized artifact carries an independent review verdict with per-dimension rationale across the six dimensions
  - **Blocked on:** requires a translation-review verdict store and a reviewer substrate

### §11.4.238

- **OWED-GATE-036** — `CM-MANUAL-QA-FINDS-NOTHING-NEW`
  - **Must assert:** asserts a manual QA pass discovered zero previously-unknown defects
  - **Blocked on:** requires a discovery-channel ledger recording each defect's origin channel
- **OWED-GATE-046** — `CM-QA-IS-THE-DISCOVERER`
  - **Must assert:** asserts every out-of-band discovery triggers a coverage-escape audit and registers a new automated check that would have caught it
  - **Blocked on:** requires the discovery-channel ledger

### §11.4.239

- **OWED-GATE-015** — `CM-CRITICAL-INVARIANT-FAILURE-PATH-DOD`
  - **Must assert:** asserts every change touching money, safety, availability or integrity carries explicit failure-path scenarios as passing tests mapped to verdict pairs
  - **Blocked on:** needs a consumer criticality classification and wiring into the 11.4.146(D3) status-custody chain

### §11.4.240

- **OWED-GATE-034** — `CM-LEAST-PRIVILEGE-CAPABILITY-NOT-INSTRUCTION`
  - **Must assert:** asserts producer-versus-gate separation is enforced by capability - filesystem scope, branch protection, store isolation - never by prompt or policy text
  - **Blocked on:** requires CI permission-model introspection
- **OWED-GATE-041** — `CM-PRODUCER-NOT-VERIFIER-SCOPE-SPLIT`
  - **Must assert:** asserts producer, oracle, gate and verifier resolve to distinct actors with no collapse involving the producer
  - **Blocked on:** requires an actor-scope registry

### §11.4.241

- **OWED-GATE-032** — `CM-ILLEGAL-STATE-LADDER-PREFERENCE`
  - **Must assert:** asserts each load-bearing invariant lands at the strongest rung the toolchain supports - types over API-shape over lint over property-test over runtime-assert
  - **Blocked on:** needs per-language toolchain capability detection and a rung classifier

### §11.4.242

- **OWED-GATE-005** — `CM-BISECTION-BEFORE-BLAME`
  - **Must assert:** asserts regression localisation used bisection from the last known-good tag with a monotone-observable precheck rather than blame-log walking
  - **Blocked on:** needs a per-investigation evidence record format, none adopted yet
- **OWED-GATE-068** — `CM-DELTA-DEBUG-MINIMAL-CASE`
  - **Must assert:** asserts an investigation of a non-monotone or non-commit-discriminated failure records the narrowed axis and its minimal failing case, and that this case is the 11.4.115 RED test's input; a fix designed against an un-narrowed failing input FAILs
  - **Blocked on:** needs the same per-investigation evidence record format still owed by OWED-GATE-005, none adopted yet
  - **Paired 1.1 mutation:** strip the minimal-case record so the fix is designed against the full unreduced input and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a genuine monotone commit-range regression localised by git bisect alone MUST NOT fire it

### §11.4.243

- **OWED-GATE-011** — `CM-CHARACTERIZATION-BEFORE-LEGACY-MODIFICATION`
  - **Must assert:** asserts behaviour-changing edits to legacy code are preceded by a landed green characterization baseline
  - **Blocked on:** needs a legacy-classification rule and a baseline-precedence record

### §11.4.244

- **OWED-GATE-009** — `CM-CAN-I-DEPLOY-GATE-WIRED`
  - **Must assert:** asserts deploy is blocked unless the provider-by-consumer compatibility matrix is all-green, with a missing contract treated as a first-class refusal
  - **Blocked on:** requires a contract broker holding deployed-version state
- **OWED-GATE-014** — `CM-CONTRACT-TESTS-BOTH-SIDES`
  - **Must assert:** asserts each changed cross-boundary carries consumer-published and provider-verified contract tests on both sides
  - **Blocked on:** requires a contract broker and a boundary inventory

### §11.4.245

- **OWED-GATE-040** — `CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT`
  - **Must assert:** asserts each test names its oracle strategy from the closed seven-member set and that the oracle is structurally independent of the code under test
  - **Blocked on:** requires an oracle-annotation convention and parser, none adopted

### §11.4.246

- **OWED-GATE-007** — `CM-BUILD-HERMETICITY`
  - **Must assert:** asserts no undeclared build inputs - every dependency version-pinned and lockfile-hashed, no unpinned network reach, no host-env leakage
  - **Blocked on:** requires a sandboxed no-network build harness that does not exist here
- **OWED-GATE-008** — `CM-BUILD-REPRODUCIBILITY`
  - **Must assert:** asserts two independent builds of identical source yield byte-identical artifacts or a diff-set fully accounted for by declared non-determinisms
  - **Blocked on:** requires building real artifacts twice on conformant hosts - this repo has no build pipeline
- **OWED-GATE-050** — `CM-SLSA-L2-PROVENANCE-VERIFIED`
  - **Must assert:** asserts signed SLSA Build Level 2 provenance - source URI, commit hash, builder identity, invocation, artifact hash - verifies against the artifact
  - **Blocked on:** requires a hosted tamper-resistant build platform emitting attestations
- **OWED-GATE-052** — `CM-SUPPLY-CHAIN-DEPS-PROVENANCE-ATTESTED`
  - **Must assert:** asserts dependencies are vendored hash-verified, provenance-attested at source, or mirrored through a hash-pinning registry
  - **Blocked on:** requires a dependency inventory and an attestation verifier

### §11.4.247

- **OWED-GATE-033** — `CM-LAYER-MOVE-COMPLETENESS-CHECK`
  - **Must assert:** asserts a boundary move leaves zero residual references across all seven layers or an explicit tracked compatibility window per residual
  - **Blocked on:** requires the consumer layer-taxonomy audit script and a layer inventory

### §11.4.248

- **OWED-GATE-025** — `CM-FLAKY-TEST-QUARANTINE-WIRED`
  - **Must assert:** asserts a test-history aggregator detects flakes, moves them to quarantine and opens a deadlined stabilisation item
  - **Blocked on:** requires multi-run test-history storage
- **OWED-GATE-044** — `CM-PROTECTED-REGRESSION-SPEC-GATE`
  - **Must assert:** asserts tests tagged PROTECTED-SPEC require the designated CODEOWNERS reviewer before merge
  - **Blocked on:** requires forge branch-protection and CODEOWNERS introspection

### §11.4.249

- **OWED-GATE-026** — `CM-FLIGHT-RECORDER-CAPTURED`
  - **Must assert:** asserts producer inputs, oracle verdict, gate decision and verifier audit are captured as a durable replayable artifact
  - **Blocked on:** requires an event-stream recorder
- **OWED-GATE-048** — `CM-ROLE-SEPARATION-DECLARED`
  - **Must assert:** asserts each load-bearing quality mechanism declares its four roles with no forbidden collapse
  - **Blocked on:** requires a role-declaration convention

### §11.4.250

- **OWED-GATE-028** — `CM-HEURISTIC-TOWER-TRIGGERS-PRIMITIVE-DEBUG`
  - **Must assert:** asserts a stack of two or more compensating heuristics triggers a primitive systematic-debug instead of adding layer N+1
  - **Blocked on:** needs a tower detector that distinguishes accreted mitigation from deliberate defense-in-depth

### §11.4.251

- **OWED-GATE-037** — `CM-NO-BYTE-IDENTICAL-FORK`
  - **Must assert:** asserts no two near-identical trees exist differing only by configuration values
  - **Blocked on:** requires a cross-tree similarity analyzer plus consumer-owned threshold DATA

### §11.4.252

- **OWED-GATE-017** — `CM-DANGEROUS-COMBINATION-FAIL-CLOSED`
  - **Must assert:** asserts every path combining two or more dangerous capabilities refuses on any unverifiable precondition and never fails open
  - **Blocked on:** needs a capability-taxonomy static analyzer, none exists

### §11.4.253

- **OWED-GATE-030** — `CM-IDEMPOTENCY-CHAOS-VERIFIED`
  - **Must assert:** asserts simultaneous-retry, mid-operation-crash and retry-after-apparent-success chaos cases all pass
  - **Blocked on:** requires a live database plus a fault-injection harness
- **OWED-GATE-031** — `CM-IDEMPOTENCY-DB-LEVEL-UNIQUE-GUARD`
  - **Must assert:** asserts every retryable operation carries an idempotency key guarded by a database UNIQUE constraint rather than an application-level check-then-insert
  - **Blocked on:** requires schema introspection of a real database

### §11.4.254

- **OWED-GATE-006** — `CM-BOOT-TIME-INVARIANT-ASSERTED`
  - **Must assert:** asserts each service asserts env, config, dependency, credential, schema and host invariants at boot and exits non-zero rather than serving
  - **Blocked on:** this repo ships no services, so it needs a consumer service inventory as DATA
- **OWED-GATE-010** — `CM-CAPABILITY-MATRIX-PRESENT-AND-IN-SYNC`
  - **Must assert:** asserts the capability matrix declares boot invariants plus offered and required capabilities and stays fingerprint-fresh
  - **Blocked on:** needs a service inventory and an emitted-endpoint extractor

### §11.4.257

- **OWED-GATE-024** — `CM-FAQ-FROM-REAL-QUESTIONS`
  - **Must assert:** asserts a FAQ exists per component, derived from real operator, QA and end-user questions rather than invented
  - **Blocked on:** needs a component inventory and a captured question corpus
- **OWED-GATE-027** — `CM-GUIDE-PER-USER-WORKFLOW`
  - **Must assert:** asserts a task-oriented guide exists for every user-facing workflow
  - **Blocked on:** needs a workflow inventory as consumer DATA
- **OWED-GATE-055** — `CM-USER-MANUAL-PER-COMPONENT`
  - **Must assert:** asserts a complete user manual exists per component, service and product
  - **Blocked on:** needs a component inventory as consumer DATA

### §11.4.258

- **OWED-GATE-001** — `CM-ARCHITECTURE-DIAGRAM-PRESENT-ACCURATE`
  - **Must assert:** asserts a system-architecture diagram exists in an open diffable format, renders non-blank, and matches the live deployed topology
  - **Blocked on:** needs a diagram renderer plus a topology-extraction oracle able to prove diagram-vs-reality accuracy - neither exists in-repo
- **OWED-GATE-018** — `CM-DATAFLOW-DIAGRAM-PER-SERVICE`
  - **Must assert:** asserts a data-flow diagram per service, accurate against real data movement and embedded at its point of use
  - **Blocked on:** same renderer and accuracy-oracle gap as the architecture diagram gate
- **OWED-GATE-020** — `CM-DIAGRAM-EMBEDDED-NOT-ORPHAN`
  - **Must assert:** asserts every diagram is referenced from a README-reachable document rather than living in an orphan gallery
  - **Blocked on:** depends on the diagram inventory the other 11.4.258 gates establish
- **OWED-GATE-049** — `CM-SEQUENCE-DIAGRAM-PER-CRITICAL-WORKFLOW`
  - **Must assert:** asserts a sequence diagram per critical user workflow and per critical cross-component protocol
  - **Blocked on:** needs a workflow inventory and a renderer
- **OWED-GATE-051** — `CM-STATEMACHINE-DIAGRAM-PER-STATEFUL-ENTITY`
  - **Must assert:** asserts a state-machine diagram per stateful entity matching that entity's real transitions
  - **Blocked on:** needs an entity inventory and a transition extractor

### §11.4.259

- **OWED-GATE-002** — `CM-BADGE-CLOSED-COLOR-VOCABULARY`
  - **Must assert:** asserts every README badge colour is drawn from the closed set green/amber/red/gray with every gray carrying an explicit reason
  - **Blocked on:** needs a badge-row parser and a consumer-owned badge set defined as DATA per 11.4.35
- **OWED-GATE-003** — `CM-BADGE-MACHINE-DERIVED-SOURCE`
  - **Must assert:** asserts each badge value traces to a machine-derived provenance source and is never hand-typed
  - **Blocked on:** requires a per-badge provenance computer wired to build, test, coverage and security sources that do not yet exist
- **OWED-GATE-004** — `CM-BADGE-SELF-VALIDATED`
  - **Must assert:** asserts the badge computer passes golden-good, golden-bad and negative-control fixtures per 11.4.107(10)
  - **Blocked on:** depends on the badge computer landing first
- **OWED-GATE-042** — `CM-PRODUCTION-READINESS-GAUGE`
  - **Must assert:** asserts the composite readiness gauge reads green only when every invariant and every blocker is clear
  - **Blocked on:** depends on the readiness tracker and the badge computer
- **OWED-GATE-047** — `CM-README-BADGE-ROW-AT-TOP`
  - **Must assert:** asserts the badge row sits directly below the H1 and above the introduction
  - **Blocked on:** the consumer badge set is undefined and a README structural parser is needed

### §11.4.260

- **OWED-GATE-066** — `CM-CORRELATION-ID-THREADED-ACROSS-BOUNDARIES`
  - **Must assert:** asserts a declared request or trace id is emitted by every signal and survives every async hop - queue, worker and scheduled sweep; a hop that drops it FAILs
  - **Blocked on:** this repo ships no running services emitting signals across async hops, so it needs a consumer service and signal inventory as DATA
  - **Paired 1.1 mutation:** drop the correlation id at the queue boundary and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a surface with genuinely no async hop and no crash-reporting channel, honestly 11.4.3 SKIP-with-reason, MUST NOT fire it
- **OWED-GATE-067** — `CM-CRASH-FREE-RELEASE-GATE`
  - **Must assert:** asserts a crash-free users or sessions gate exists with a declared, locally-calibrated threshold, and that a crash signature new at the release boundary blocks regardless of volume
  - **Blocked on:** requires a crash-reporting backend and a calibrated per-project threshold, neither available in this project-agnostic repo; the anchor mandates that the gate exists and that its threshold is declared locally, never a constitutional numeric value
  - **Paired 1.1 mutation:** admit a release carrying a new crash signature at low volume and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a surface with no crash-reporting channel, honestly 11.4.3 SKIP-with-reason, MUST NOT fire it
- **OWED-GATE-016** — `CM-CUTTING-EDGE-POSTURE-ALWAYS-ON`
  - **Must assert:** asserts the ten production-readiness invariants are evaluated for every change
  - **Blocked on:** depends on the production-readiness tracker landing first
- **OWED-GATE-043** — `CM-PRODUCTION-READINESS-TRACKER-PRESENT`
  - **Must assert:** asserts the per-component by invariant by evidence-source readiness tracker exists and is fresh
  - **Blocked on:** needs a component inventory as consumer DATA
- **OWED-GATE-058** — `CM-ZERO-NASTY-SURPRISES-AUDIT`
  - **Must assert:** asserts no known-broken code ships, no gate is silenced and no test is disabled without a tracked follow-up
  - **Blocked on:** depends on the findings sweep and a tracker

### §11.4.261

- **OWED-GATE-021** — `CM-EVERY-FINDING-CLOSED-OR-TRACKED`
  - **Must assert:** asserts each audit-sweep finding is either closed with defect-layer evidence or carries a tracked item plus a regression guard
  - **Blocked on:** depends on the findings sweep and a tracker
- **OWED-GATE-056** — `CM-ZERO-FINDINGS-AUDIT-SWEEP`
  - **Must assert:** asserts the ten-class findings sweep runs and emits a machine-readable findings ledger
  - **Blocked on:** requires the sweep script plus per-class golden-good and golden-bad fixtures
- **OWED-GATE-057** — `CM-ZERO-FINDINGS-MONOTONE-RATCHET`
  - **Must assert:** asserts per-class and total findings counts never increase
  - **Blocked on:** depends on the sweep and an operator-owned brownfield baseline decision per 11.4.66

### §11.4.262

- **OWED-GATE-022** — `CM-EVIDENCE-ANALYZER-SELF-VALIDATED`
  - **Must assert:** asserts every evidence analyzer passes golden-good, golden-bad and negative-control fixtures
  - **Blocked on:** requires the analyzer fleet to exist before it can be validated
- **OWED-GATE-023** — `CM-EVIDENCE-LAYER-MATCH-108`
  - **Must assert:** asserts each 11.4.108 layer PASS cites evidence produced AT that layer, rejecting wrong-layer echo
  - **Blocked on:** requires a four-layer verdict store
- **OWED-GATE-035** — `CM-MACHINE-EVIDENCE-AT-EVERY-GATE`
  - **Must assert:** asserts every works, passes or verified claim cites machine-created evidence by path, sha256 and timestamp
  - **Blocked on:** requires a content-addressed evidence store
- **OWED-GATE-039** — `CM-NO-NARRATIVE-ONLY-PASS`
  - **Must assert:** asserts no PASS rests on prose, operator eyeballing or an absence-of-error observation
  - **Blocked on:** requires the evidence store to mechanically distinguish narrative from artifact

### §11.4.264

- **OWED-GATE-063** — `CM-BUILD-ONCE-PROMOTE-DIGEST`
  - **Must assert:** asserts the pipeline's build step is invoked at most once per release candidate and that every post-build environment stage references a pinned content-addressed digest and NOT a rebuild target; a stage that re-invokes the build FAILs
  - **Blocked on:** this project-agnostic repo ships no deployment pipeline, so the gate needs a consumer pipeline definition as DATA per 11.4.35
  - **Paired 1.1 mutation:** add a second per-environment build invocation and the gate MUST FAIL; replace a promoted digest reference with a mutable tag and it MUST FAIL; golden-FALSE per 11.4.201(1) - a single build followed by N digest-referencing promotion stages MUST NOT fire it
- **OWED-GATE-070** — `CM-DEPLOY-CONFIG-INJECTED-NOT-BAKED`
  - **Must assert:** asserts no environment-specific endpoint, secret or flag is materialised into the artifact at build time; a per-environment build argument that changes artifact bytes FAILs
  - **Blocked on:** proving byte-equality across two environment configurations requires a real build pipeline able to produce artifacts twice, which this repo does not have
  - **Paired 1.1 mutation:** bake an environment endpoint into the build and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a single build followed by N digest-referencing promotion stages MUST NOT fire it

### §11.4.265

- **OWED-GATE-064** — `CM-CANARY-ANALYSIS-INCLUDES-BUSINESS-METRIC`
  - **Must assert:** asserts the declared metric set contains at least one business or domain outcome metric and not exclusively infrastructure metrics; an infra-only analysis on a 11.4.239 critical-invariant surface FAILs
  - **Blocked on:** depends on the progressive-delivery strategy declaration landing first, since the metric set is a field of that declaration
  - **Paired 1.1 mutation:** strip every business metric from the analysis set leaving only error-rate and latency and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a genuinely non-routable artifact carrying an honest SKIP-with-reason MUST NOT fire it
- **OWED-GATE-073** — `CM-PROGRESSIVE-DELIVERY-STRATEGY-DECLARED`
  - **Must assert:** asserts a user-facing release either declares a bounded-blast-radius strategy with an automated analysis step, or carries an honest 11.4.3 SKIP-with-reason naming the absent traffic surface; an ungated full cutover with neither FAILs
  - **Blocked on:** needs a consumer release-strategy declaration format and a traffic-surface inventory, neither adopted
  - **Paired 1.1 mutation:** replace the automated abort with a manual approval step and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a genuinely non-routable artifact carrying an honest SKIP-with-reason MUST NOT fire it

### §11.4.266

- **OWED-GATE-065** — `CM-CLAIM-REALITY-LEDGER-COMPLETE`
  - **Must assert:** asserts every advertised capability on every declared advertised surface resolves to exactly one ledger row; an advertised capability with no row FAILs naming the capability and the surface it was advertised on
  - **Blocked on:** needs a consumer advertised-surface inventory plus a capability extractor, neither of which exists in-repo
  - **Paired 1.1 mutation:** add a README capability with no ledger row and the completeness gate MUST FAIL; golden-FALSE per 11.4.201(1) - a fully-populated ledger whose every row has a fresh candidate-fingerprinted PASS verdict MUST NOT fire it
- **OWED-GATE-072** — `CM-LEDGER-ROW-TYPED-FROM-CLOSED-VOCABULARY`
  - **Must assert:** asserts every ledger row carries a bluff type drawn from the seven-member closed set green-but-broken, coverage-theater, rubber-stamp-verified, stubbed-core, doc-vs-code-drift, config-present-but-unwired and byte-identical-fork; an ad-hoc type FAILs
  - **Blocked on:** depends on the claim-vs-reality ledger schema landing first, there is no ledger to type-check yet
  - **Paired 1.1 mutation:** retype a row to an invented type and the vocabulary gate MUST FAIL; golden-FALSE per 11.4.201(1) - a fully-populated ledger whose every row has a fresh candidate-fingerprinted PASS verdict MUST NOT fire it
- **OWED-GATE-076** — `CM-UNCHALLENGED-CAPABILITY-BLOCKS-RELEASE`
  - **Must assert:** asserts a ledger row whose challenge is absent, never executed, or has no verdict for the release-candidate artifact fingerprint blocks the release exactly as a FAIL does
  - **Blocked on:** depends on the claim-vs-reality ledger of OWED-GATE-065 plus a verdict store keyed by candidate fingerprint
  - **Paired 1.1 mutation:** blank a row's challenge reference and the blocking gate MUST FAIL; golden-FALSE per 11.4.201(1) - a fully-populated ledger whose every row has a fresh candidate-fingerprinted PASS verdict MUST NOT fire it

### §11.4.267

- **OWED-GATE-062** — `CM-ATTEMPT-RECORD-SHARED-AND-CONSULTED`
  - **Must assert:** asserts every multi-attempt effort writes each attempt and its outcome to the declared shared record, and that the record is read before the next attempt is dispatched; a second attempt duplicating a recorded-failed approach with no recorded material difference FAILs
  - **Blocked on:** no shared attempt-record store is declared or adopted in-repo, and the consumer binds its store path as DATA per 11.4.35
  - **Paired 1.1 mutation:** strip the record-read step so the loop dispatches blind and the gate MUST FAIL; golden-FALSE per 11.4.201(1) - a loop that converges on attempt 2 with both attempts recorded and no bound exceeded MUST NOT fire it
- **OWED-GATE-074** — `CM-STALL-BOUNDED-AND-ESCALATED`
  - **Must assert:** asserts a declared retry bound exists and that a loop exceeding it without a recorded escalation to a terminal disposition FAILs
  - **Blocked on:** depends on the shared attempt record of OWED-GATE-062 landing, plus a declared per-effort-class retry bound that no consumer has supplied
  - **Paired 1.1 mutation:** remove the retry bound leaving an unbounded loop and the gate MUST FAIL; record an escalation with no terminal disposition and it MUST FAIL; golden-FALSE per 11.4.201(1) - a loop that converges on attempt 2 with both attempts recorded and no bound exceeded MUST NOT fire it

## B. Token-extraction artifacts — not real gate names

These eight tokens are **not** gates. They are artifacts of the ledger's per-line token
extractor. They are **deferred rather than removed** because `gate_ledger_removals.tsv` is only
consulted in `check` mode for names **absent** from the ledger — these tokens are still present
in the corpus, so a removal citation never fires for them (proven empirically, not assumed).
Per §11.4.227(A) a name is never deleted to lower the count; the fix is a **naming/wrap cleanup
in the corpus prose**, after which these tokens stop being extracted and the ratchet drops by 8.

**Acceptance criteria for every `OWED-NAMING-*` item:** the producing prose is rewritten so the
token is no longer emitted — range endpoints written with their full `-PROPAGATION` suffix, and
hyphen-wrapped names re-flowed so no line ends mid-name — verified by re-running
`gate_ledger.sh generate` and confirming the bare token no longer appears in the ledger.

### B.1 Prose-range artifacts (Constitution.md line 9)

The sentence *"Propagation gates CM-COVENANT-114-239 through CM-COVENANT-114-254 +
CM-COVENANT-114-257 through CM-COVENANT-114-262"* writes each range endpoint **without** the
`-PROPAGATION` suffix the group shares. The extractor stops at the space, emitting a bare token.
Each real gate (`CM-COVENANT-114-NNN-PROPAGATION`) is present in all five governance files.

- **OWED-NAMING-003** — `CM-COVENANT-114-239` → real gate `CM-COVENANT-114-239-PROPAGATION`
- **OWED-NAMING-004** — `CM-COVENANT-114-254` → real gate `CM-COVENANT-114-254-PROPAGATION`
- **OWED-NAMING-005** — `CM-COVENANT-114-257` → real gate `CM-COVENANT-114-257-PROPAGATION`
- **OWED-NAMING-006** — `CM-COVENANT-114-262` → real gate `CM-COVENANT-114-262-PROPAGATION`

### B.2 Hyphen line-wrap artifacts (mirror files)

A gate name hyphen-wrapped across a line break yields a prefix ending in `-`, which the
extractor's trailing-punctuation stripper (`sed -E 's/[-.,:;)]+$//'`) turns into a bare token.
**All four have zero standalone occurrences corpus-wide** (boundary-anchored check, control-needle
verified) — they exist only as wrapped prefixes.

- **OWED-NAMING-001** — `CM-AF-KINOPOISK-5-1-DUAL` → real gate `CM-AF-KINOPOISK-5-1-DUAL-COVERAGE` (wrap at `AGENTS.md:960`)
- **OWED-NAMING-002** — `CM-AF-UI-DRIVEN-VIDEO` → real gate `CM-AF-UI-DRIVEN-VIDEO-COVERAGE` (wrap at `AGENTS.md:927`)
- **OWED-NAMING-007** — `CM-OPERATOR-BLOCKED-SELF` → real gate `CM-OPERATOR-BLOCKED-SELF-RESOLUTION-AUDIT` (wrap at `AGENTS.md:306`)
- **OWED-NAMING-008** — `CM-OPERATOR-BLOCKED-SELF-RESOLUTION` → same real gate, wrapped at a different point (`CLAUDE.md:440`)

## Note on `CM-COVENANT-114-27-PROPAGATION`

Investigated and **refuted as an artifact**. `Constitution.md:2645` reads *"existing
`CM-COVENANT-114-27-PROPAGATION` stays unchanged (literal `11.4.27` unchanged, stays GREEN)"* —
a deliberate reference to the real propagation gate for anchor §11.4.27, which exists as a real
anchor heading. It is a genuine gate name, not a range truncation, and it falls in the
`*-PROPAGATION` scope rather than the mechanism-gate scope covered here.

---

## B. Landed-but-not-wired: the 29 engine-driven propagation gates

**Status (§11.4.6 honest, measured 2026-08-20):** 29 `cm_covenant_114_*_propagation.sh`
gates (§11.4.27, §11.4.234, §11.4.236–§11.4.262) are IMPLEMENTED as executable gate
sites driven by `scripts/gates/lib/covenant_propagation_engine.sh` plus a 29-row data
pack, each with a paired `*_mutation_test.sh`. Measured facts, not claims:

- `bash -n` / `sh -n`: 83/83 clean.
- §1.1 mutations: 29 × 8 fixtures → `29 entries, 29 exit-0`. Every defect class
  (MISSING / DUPLICATED / DIVERGENT-HEAD / DIVERGENT-BODY / FENCE-MISSING) FAILs;
  every clean fixture (POINTER-OK / CLEAN control / ANCHOR-BOUNDARY) PASSes.
- Ledger delta, proven on a control scratch tree:
  `BEFORE IMPLEMENTED=36 UNIMPL=449` → `AFTER IMPLEMENTED=65 UNIMPL=420`.
  The §11.4.227(A) ratchet moved from **violated** (`449>420 fails=1`) to
  **satisfied** (`420==420 fails=0`) *because of these files*.

**They are NOT yet wired.** No runner, hook, or pre-build stage invokes them.
Per §11.4.227(A) an anchor's done-state is its SEAM landing, not its TEXT landing;
per §11.4.201(8) the ledger's 420 is a metric on a PROXY, and it reaches its true
target only when these gates are implemented **and wired and un-holed**. The GREEN
ratchet must not be read as "§11.4.227(A) satisfied in substance."

### B.1 Findings from the independent adversarial verification (2026-08-20)

Report: `adversarial-review.md` (session scratch). Findings F1–F3 are **defects in the
shared engine**, a faithful port of the already-landed 230-template — they therefore
exist in `main` today via the 5 pre-existing standalone gates, independent of this
batch. These 29 widen the surface; they did not create the hole.

- **OWED-GATE-ADV-F1 (CRITICAL)** — pointer carve-out swallows real propagation loss.
  All four project-root consumer carriers are `is_pointer_carrier`-true yet restate
  anchors; deleting a whole anchor block from all four still exits 0
  (`4 POINTER-INHERITANCE-SKIP, 0 MISSING`). The entire consumer layer can lose any
  anchor with all gates green.
- **OWED-GATE-ADV-F2 (CRITICAL)** — one-line permanent exemption. Adding an
  `## INHERITED FROM …` line to a carrier and deleting its block → exit 0. Any carrier
  can be silently removed from the lockstep set by one documentation-looking line.
- **OWED-GATE-ADV-F3 (CRITICAL)** — lockstep hash truncatable by the corpus's own
  convention. A compact `- §11.4.N — …` citation inside a block collapses the hashed
  region to the heading; 17 of 18 body lines replaced with filler in one carrier → exit 0.
- **OWED-GATE-ADV-F4 (HIGH)** — 29/29 red on the clean tree (55 MISSING each, of which
  18 are vendored third-party trees the prune list does not exclude) → a §11.4.201(1)
  FAIL-bluff surface and §11.4.248 flake-decay risk. §11.4.255/§11.4.256 red is a
  **real** defect: the canonical constitution mirrors lack the re-minted blocks.
- **OWED-GATE-ADV-F5 (HIGH)** — verdict is a function of cwd; nothing pins the root.
  From the repo root the scan reaches outside the repository.
- **OWED-GATE-ADV-F6 (HIGH)** — three false-positive refusals of legitimate corpora
  (sanctioned cross-layer compact summary; §11.4.141 compact index bullet read as
  DUPLICATED; unrelated EOF appendix marking the last anchor DIVERGENT).
- **OWED-GATE-ADV-F7 (MEDIUM)** — 29 names, zero enforcement (the wiring gap above).
- **OWED-GATE-ADV-F8 (LOW)** — a real `### … (§11.4.27, …)` heading the regex misses;
  DIVERGENT lines print ambiguous basenames.

**Acceptance for F1–F6:** each fix is a change to the SHARED engine and therefore
alters the 5 already-landed gates' behaviour — a §11.4.120 reconciliation, with the
golden-FALSE fixture set extended per §11.4.201(1) so the corrected engine still does
not refuse a legitimately-compliant corpus. Not attempted in this batch: the operator's
implementation lock is in force, and engine surgery under a lock is exactly the
unreviewed-change class §11.4.142 forbids.

**Acceptance for F7:** wire the suite into a runner/pre-build stage, at which point the
420 ledger figure stops being a proxy and starts being enforcement.

---

## C. Merge-introduced deferrals (§11.4.263, arrived 2026-08-20 via upstream 502586c)

Upstream commit `502586c` ("anchor(§11.4.263): process-group signal-safety mandate")
named three CM-* gates with neither an implementation nor a registered deferral. The
§11.4.227(A) ratchet caught it correctly on the post-merge re-run — `unimplemented=423
baseline=420 fails=1` — which is the mechanism working, not a false positive.

Remediation taken: register the three against tracked items (the sanctioned §11.4.227(A)
path). The baseline was NOT raised: raising it is the ratchet-gaming channel the anchor
explicitly closes, and these gates remain OWED, not satisfied. Post-registration the
canonical wrapper returns `unimplemented=420 baseline=420 fails=0`.

- **OWED-GATE-059** — `CM-COVENANT-114-263-PROPAGATION`. Asserts the §11.4.263 anchor
  block-start is present exactly once per governance file and lockstep-identical across
  the mirror set. **Blocked on:** the shared propagation engine carries
  OWED-GATE-ADV-F1..F3 (Section B); landing a 30th gate on a holed engine widens the
  surface again. Reconcile the engine first per §11.4.120, then land this gate.
- **OWED-GATE-060** — `CM-KILLPG-PGID-GUARD`. Asserts every `killpg` / `kill(-pid)` call
  site in production code carries the `pid > 1 && pgid > 1` guard. **Blocked on:** needs a
  per-language call-site scanner plus its paired §1.1 mutation (remove the guard → the
  regression test must FAIL, per §11.4.115 observation-before-trust).
- **OWED-GATE-061** — `CM-TEST-MOCK-PID-EXPLICIT-INT`. Asserts every subprocess mock in
  test code sets `mock.pid` explicitly as `int` with `killpg` patched. **Blocked on:**
  needs a test-corpus scanner plus its paired §1.1 mutation (unset `mock.pid` → the
  assertion must catch the `pgid <= 1` attempt).

Honest boundary (§11.4.6): a DEFERRED gate is owed work that is tracked and visible — it
is NOT a gate that runs. §11.4.263's signal-safety mandate is therefore **unenforced
mechanically** in this repository today; only its anchor text binds.

---

## D. Deferrals registered 2026-08-26 — the 15 `OWED-GATE-*` ids that pointed at no tracked item

These 15 ids appeared in the first column's partner field of
`scripts/gates/gate_ledger_deferrals.tsv` with **no corresponding entry in this document** —
a DANGLING pointer: the TSV header states every row "is registered as owed debt against a
tracked item in docs/owed_gate_implementations.md", and for these fifteen that item did not
exist. `gate_ledger.sh` never caught it because the ledger checks only that a deferral ROW
exists for the gate name, never that the row's id RESOLVES — an honest instrument gap, not a
miscount. Registering them here is the sanctioned §11.4.227(A) path (never renumbering, per
§11.4.54 id stability, and never deleting a row, per §11.4.227(A)).

**Measurement (§11.4.201(7)(b)):** the dangling set was derived by diffing every
`OWED-GATE-NNN` id in the TSV's field 2 against every such id in this document; the diff
instrument was control-needle-proven (a KNOWN-tracked id already registered in Section A
returned 1 hit in this document by the same `/usr/bin/grep` invocation, and an id whose
three-digit suffix appears nowhere returned 0). Ids in the **080-083 suffix range** were
checked and exist NOWHERE in the tree (same instrument, control-needle-proven against the
suffix-084 id registered below), so no entry is minted for them — inventing an id for a row that does not exist would be the §11.4.6 guess this
registry forbids.

**Honest boundary (§11.4.6):** registering a deferral proves the debt is *tracked*, not that
the gate *works*. Every entry below is still OWED; the §11.4.227(A) acceptance criteria at the
top of this document apply unchanged. The baseline in `gate_ledger_baseline.txt` was NOT
raised — these rows were already DEFERRED in the ledger's eyes; only their tracked item was
missing.

### §11.4.176

- **OWED-GATE-077** — `CM-LOGICAL-GROUP-COHESION`
  - **Must assert:** asserts every workable item in a logic group resolves to that group's single canonical (track, branch) destination per §11.4.176(A)/§11.4.191
  - **Blocked on:** needs the group→destination registry join wired as a checkable seam. Named ONLY in a prose comment at cm_covenant_114_176_propagation.sh:20; zero executable sites.
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-078** — `CM-NO-CROSS-TRACK-SCOPE-OVERLAP`
  - **Must assert:** asserts two concurrently-claimed work units never share a file-scope path per §11.4.176(A) disjoint-scope + §11.4.58 L3
  - **Blocked on:** needs a live cross-track claim registry to diff scopes against — the per-repo claim registries are empty. Named ONLY in a prose comment at cm_covenant_114_176_propagation.sh:20; zero executable sites.
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-079** — `CM-WORK-DIVISION-EXCLUSIVE-CLAIM`
  - **Must assert:** asserts the §11.4.176(A) exactly-once claim registry admits one and only one claimant per workable item, refusing a second claim
  - **Blocked on:** needs a shared cross-track claim store — not adopted in-repo. Named ONLY in a prose comment at cm_covenant_114_176_propagation.sh:19; zero executable sites.
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.269

- **OWED-GATE-084** — `CM-CRITIC-CONSENSUS-ADVISORY-ONLY`
  - **Must assert:** asserts a claim supported only by an ungoverned critic/consensus/confidence signal is refused, the accept/refuse outcome is identical whether the ungoverned critic step ran or was skipped, every stored critic output carries role advisory and enters no evidence chain, and a mandatory 11.4.125/.134/.142/.165/.209/.237/.256 review verdict is never downgraded to advisory
  - **Blocked on:** no critic/consensus mechanism and no advisory store are wired in-repo, and the consumer binds both as DATA per 11.4.35
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.270

- **OWED-GATE-085** — `CM-DEPENDENCY-EXISTENCE-VERDICT-REGISTER`
  - **Must assert:** asserts every claimed dependency has a register row carrying a closed-set {VERIFIED,AMBIGUOUS,UNVERIFIED} verdict plus an evidence field, a name collision resolves AMBIGUOUS never VERIFIED, adoption on an UNVERIFIED/AMBIGUOUS row is refused, and adoption neither precedes its wiring-sweep result nor targets an already-covered capability
  - **Blocked on:** no dependency-existence register exists in-repo, and the consumer supplies the register location plus its recorded uncovered-gap set as DATA per 11.4.35
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.238

- **OWED-GATE-086** — `CM-DISCOVERY-CHANNEL-RECORD-COMPLETE`
  - **Must assert:** asserts every recorded defect carries a closed-set discovery channel plus a should_have_been_caught_by seam-name or a justified none, verifier-seam-written and never producer-authored
  - **Blocked on:** the defect records carry no discovery-channel field today and no verifier-seam writer exists, so the gate has no field to read (11.4.238 EXTENSION, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-087** — `CM-ESCAPE-RATCHET-NO-DATA-POINT-HONEST`
  - **Must assert:** asserts a cycle whose escape count exceeds the recorded baseline refuses the release seam, a cycle with manual_qa_ran false contributes no data point and cannot lower the baseline, and none-tagged records are tallied separately
  - **Blocked on:** no escape-count baseline and no manual_qa_ran flag are recorded today, so the ratchet has no baseline to compare against (11.4.238 EXTENSION, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.268

- **OWED-GATE-088** — `CM-EVIDENCE-CHAIN-ANCHOR-CATCHES-RECOMPUTE-AND-TRUNCATION`
  - **Must assert:** asserts a periodic anchor record exists on the declared interval carrying head-digest plus entry-count plus an honest mechanism/policy strength, and that anchor cross-check detects a recomputed-forward deletion and a tail truncation that chain-alone verification passes cleanly on
  - **Blocked on:** no evidence chain and no anchor store exist in-repo, and the consumer binds the anchor location plus interval as DATA per 11.4.35
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-089** — `CM-EVIDENCE-CHAIN-DELETE-REORDER-DETECTED`
  - **Must assert:** asserts full forward chain-walk verification reports a deleted or reordered entry left internally inconsistent, recomputing every link rather than spot-checking one entry content
  - **Blocked on:** no evidence chain implementation exists in-repo, and 11.4.268 requires reusing an existing content-addressed store rather than standing up a rival one
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-090** — `CM-EVIDENCE-CHAIN-INCOMPLETE-VERIFICATION-REFUSES`
  - **Must assert:** asserts a chain truncated mid-verification or an anchor location unreachable at verification time yields UNVERIFIED refusal per 11.4.201 conservative-safe default, never a clean pass by default
  - **Blocked on:** depends on the chain and anchor stores landing first, since there is no verification path to make refuse
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.115

- **OWED-GATE-091** — `CM-EVIDENCE-RECORDER-RECONCILED`
  - **Must assert:** asserts every evidence-bearing claim citing a specific command output has a matching recorder entry for the exact command cited, refused at the same status-write seam 11.4.146(D3) already enforces
  - **Blocked on:** no command-execution recorder exists in-repo, so there is no entry set to reconcile citations against (11.4.115(H) EXTENSION, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-092** — `CM-EVIDENCE-RECORD-FIELD-SET-COMPLETE`
  - **Must assert:** asserts every command-execution evidence entry carries start-timestamp, working directory, argument list as a genuine list never a shell-joined string, exit status and duration, refusing the write on a missing or unparseable field
  - **Blocked on:** no command-execution recorder with this schema exists in-repo (11.4.115(H) EXTENSION, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-093** — `CM-EVIDENCE-STREAM-DIGEST-PRE-TRUNCATION`
  - **Must assert:** asserts a truncated or redacted stream entry carries a full-stream digest, byte count and an outside-VCS reference all computed BEFORE truncation, with truncation recorded as a fact rather than silent
  - **Blocked on:** depends on the command-execution recorder landing first, since there is no stream-capture path to digest (11.4.115(H) EXTENSION, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.240

- **OWED-GATE-094** — `CM-INDEPENDENCE-TIER-HONESTLY-RECORDED`
  - **Must assert:** asserts every accepted verdict carries an independence_tier field within the closed {instance,model,capability} set, never capability at a Tier-C-triggered seam lacking a mechanically-verified host boundary, while a same-model independent verdict at an ordinary seam is accepted without a capability check
  - **Blocked on:** verdicts carry no independence_tier field today, and 11.4.240(F) records that capability tier is unestablishable on a single-uid host until an operator takes the host-boundary action (11.4.240(F) EXTENSION, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.271

- **OWED-GATE-095** — `CM-WAIVER-ROSTERED-EXPIRY-TRACKED`
  - **Must assert:** asserts every active waiver resolves to a genuinely rostered non-producer authoriser identity, a future unelapsed expiry and a named stable-id tracked item, with any one of the three missing invalidating the waiver and reverting its gate to blocking
  - **Blocked on:** no authoriser roster and no waiver store exist in-repo, and the consumer binds both as DATA per 11.4.35
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.275 (registered 2026-09-28 — the 10 recommended gates the anchor's own landing left named-but-undeferred, discovered by CM-GATE-LEDGER-RATCHET going 403→412 with zero rows added to `gate_ledger_deferrals.tsv` for the new names)

- **OWED-GATE-096** — `CM-CODE-INDEX-AGENT-ACCESSIBLE`
  - **Must assert:** asserts every indexed space (structural CodeGraph + semantic Lumen + any future code index) answers an unforgeable challenge issued from a genuinely DISPATCHED subagent, per agent, and that an enabled-but-undeclared server (no resolvable definition where the agent/subagent runs) FAILs rather than reading as configured
  - **Blocked on:** no per-agent/per-subagent accessibility-challenge harness exists in-repo today (§11.4.275(A), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-097** — `CM-CODE-INDEX-COMPLETE-BEFORE-READY`
  - **Must assert:** asserts an index is called ready only when its pending backlog is zero, its state reports complete, its file count is within the consumer-declared tolerance of the accepted expected count, and its required schema indexes exist, with every count and every empty result control-needled per §11.4.273
  - **Blocked on:** no readiness-verdict harness reads the index's pending/state/count/schema fields today (§11.4.275(C), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-098** — `CM-LUMEN-MODEL-PROVEN`
  - **Must assert:** asserts the semantic index's embedding model is provisioned rootless (§11.4.161) and proven by a real embed call returning the declared dimensionality — a model listing alone is refused as insufficient evidence
  - **Blocked on:** no embed-call proof harness exists in-repo today (§11.4.275(B), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-099** — `CM-LUMEN-SCOPED-FRESH`
  - **Must assert:** asserts the semantic index's scope is GENERATED from the same class source as the structural CodeGraph scope (§11.4.78(7)–(8), `scripts/lumen/gen_lumenignore.py`) so third-party and secret classes are excluded identically, and that health = files AND chunks non-zero + a known-symbol search hit + a negative control + freshness within the consumer-declared TTL
  - **Blocked on:** no scope-provenance-plus-health harness exists in-repo today (§11.4.275(B), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-100** — `CM-CODE-INDEX-BENCH`
  - **Must assert:** asserts a fixed golden-answer query set is run N≥3 times against the index route AND a grep+read baseline with an identical canonical result hash (§11.4.50), token reduction computed ONLY over queries BOTH routes answered correctly, wrong answers reported separately BY QUERY ID and never averaged away, and thresholds sourced from consumer DATA never constitutional literals — the sanctioned `constitution/scripts/lumen/lumen_verify.sh` harness already exists and has been run live (see the §11.4.275 EXTENSION, 2026-09-25); only THIS recommended gate wiring it into the pre-build/pre-commit seam remains owed
  - **Blocked on:** the harness is landed (`constitution/scripts/lumen/lumen_verify.sh` + `constitution/scripts/lumen/tests/test_lumen_verify.sh`); the gate-code that WIRES its exit status into a pre-build/pre-commit CM-* check is the sole remaining piece (§11.4.275(D), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-101** — `CM-CODEGRAPH-SCOPE-PROOF`
  - **Must assert:** asserts the structural CodeGraph index's effective scope is enumerated through the runner's own discovery code and the resulting count is within tolerance of the accepted expected count, with zero third-party files, zero secret-class files, and at least one file per own-org root — every count control-needled per §11.4.273
  - **Blocked on:** no scope-enumeration-proof harness exists in-repo today (§11.4.78(7) cross-referenced by §11.4.275, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-102** — `CM-CODEGRAPH-UPGRADE-PROBE-GATED`
  - **Must assert:** asserts a CodeGraph runner upgrade is gated on a compatibility probe (loader config filename/keys, bulk-window hazard probe, runner-patch applicability) and refuses loudly, keeping the prior version, when the patched runner cannot be re-proven
  - **Blocked on:** no upgrade-compatibility-probe harness exists in-repo today (§11.4.80(4) cross-referenced by §11.4.275, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-103** — `CM-CODEGRAPH-WRITER-EXCLUSIVE`
  - **Must assert:** asserts every init/index/sync write goes through the single sanctioned writer entry, which refuses while any live process targets the same root (real cmdline per §11.4.196(D), regardless of lock age — never age-based lock deletion)
  - **Blocked on:** no single-writer-exclusivity proof harness exists in-repo today (§11.4.80(5) cross-referenced by §11.4.275(G), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-104** — `CM-CODEGRAPH-BULK-BY-BACKLOG`
  - **Must assert:** asserts a bulk re-index/re-sync classification is derived from PENDING backlog (unresolved-reference count, files still to parse), never from rows already stored — the exact launcher defect the §11.4.275 forensic anchor clause (5) captured (tens of millions of references bulk-run foreground and unsupervised because `sync` was classified by stored rows)
  - **Blocked on:** no backlog-classification proof harness exists in-repo today (§11.4.275 forensic anchor clause (5), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-105** — `CM-CODEGRAPH-STALL-WATCHDOG`
  - **Must assert:** asserts a long-running CodeGraph bulk operation emits a monotonic progress signal and a watchdog flags HUNG on no-advance past a declared no-progress budget — `kill -0`/process-alive is a necessary-not-sufficient pre-filter, never sufficient proof of progress (§11.4.201(6)–(7), §11.4.232(C))
  - **Blocked on:** no progress-heartbeat-plus-watchdog harness exists in-repo today (§11.4.232(C) cross-referenced by §11.4.275, gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.235(D) (registered 2026-10-03 — added 2026-10-05, currency check: this row existed in `gate_ledger_deferrals.tsv` but was never documented here)

- **OWED-GATE-106** — `CM-REVIEW-FINDING-CLASS-RECORDED`
  - **Must assert:** asserts a batched-review verdict covering more than one slice/file records a per-slice verdict AND a per-finding `finding_layer` from the closed set `{source-defect|test-instrumentation|process-doc}`; FAILs if a slice is marked build-eligible while any `source-defect` finding in it has not reached GO, or if a `finding_layer` is lowered by the producer without a fresh review round; binds ADDITIVELY by computing whether the existing `source_review_go` marker (consumed by `cm_build_on_source_proven_not_test_side.sh`) may be written — never by modifying that gate's own tested logic
  - **Blocked on:** no per-finding `finding_layer` recording/consuming harness exists in-repo yet (§11.4.235(D), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.230(D) (registered 2026-10-04 — added 2026-10-05, currency check: these four rows existed in `gate_ledger_deferrals.tsv` but were never documented here)

- **OWED-GATE-107** — `CM-INCREMENT-DELIVERED-NOT-SPEC-WITHHELD`
  - **Must assert:** asserts every increment holding its own source-correctness GO (§11.4.235(A)/(D)) appears in a completed-and-handed-to-QA or in-flight QA build from its integration branch once the declared trigger has fired (coalescing per (D.3): an in-flight build covers prior increments, later ones roll into the next build; a build that fails or is refused at §11.4.236 covers nothing and does not satisfy this gate), and that NO increment lacking that GO appears in any QA build (the §11.4.201(1) dual guard)
  - **Blocked on:** no increment-to-QA-build membership harness exists in-repo (§11.4.230(D.1), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-108** — `CM-QA-BUILD-CADENCE-DECLARED`
  - **Must assert:** asserts a consumer QA-build trigger `{per-increment|periodic|whichever-first}` resolves (absent declaration ⇒ `per-increment`, never "no cadence") and that no integration branch (D.1) holds build-eligible content past a fired trigger uncovered by any completed-and-handed-to-QA or in-flight QA build (the same (D.3) coalescing rule as OWED-GATE-107)
  - **Blocked on:** no QA-build-cadence evaluation harness exists in-repo (§11.4.230(D.3), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-109** — `CM-RELEASE-TOGGLE-TRACKED-EXPIRY`
  - **Must assert:** asserts every release toggle hiding an incomplete increment carries a tracked §11.4.197 removal item and a consumer-declared expiry, and FAILs on a toggle past its expiry
  - **Blocked on:** no release-toggle inventory harness exists in-repo (§11.4.230(D.2), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-110** — `CM-QA-HANDOFF-TRACKER-IN-SYNC`
  - **Must assert:** asserts each QA hand-off record names the deliverable fingerprint and an item set that matches the deliverable contents (no done-marked item whose fix is absent; no shipped fix without an item)
  - **Blocked on:** no hand-off-record-vs-deliverable reconciliation harness exists in-repo (§11.4.230(D.5), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.

### §11.4.276 (registered 2026-10-05 — landed the SAME session as this currency check, per the operator CRITICAL mandate on excessive review-round counts)

- **OWED-GATE-111** — `CM-REVIEW-ROUND-BUDGET`
  - **Must assert:** asserts every independently-reviewed work item has a declared round budget `R_max` in the closed range 5–7 (absent declaration resolves to 5) and a round count derived from its own review record; FAILs if a round `R_max`+1 is dispatched under the same approach with no recorded operator decision (§11.4.276(E)(3)), or if an item is closed without a GO verdict
  - **Blocked on:** no review-round-counting harness exists in-repo yet (§11.4.276(A), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-112** — `CM-REVIEW-ROUND3-CONVERGENCE-ASSESSMENT`
  - **Must assert:** asserts every review round ≥ 3 carries a recorded convergence classification (new-class / same-class-as-earlier / regression-introduced-by-a-fix / wrong-layer-evidence) per finding; FAILs if a structural-round trigger per (E)(1) is followed by a non-structural point-fix round, or if an adversarial/security review proceeds with no pre-round-1 declared scope/threat boundary
  - **Blocked on:** no convergence-assessment recording/consuming harness exists in-repo yet (§11.4.276(E), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
- **OWED-GATE-113** — `CM-FIX-GROUND-TRUTH-AND-CLASS-INVENTORY`
  - **Must assert:** asserts a fix touching a declared external-system surface (build tool / compiler / interpreter / shell semantics / kernel / runtime / third-party library / protocol) carries a recorded ground-truth probe (authoritative source + real-composition-path fixture + behavioural model) before its first fix attempt, and a class-shaped finding's "closed" claim cites a control-needled whole-scope inventory artifact per §11.4.201(7)(b); FAILs on either absence
  - **Blocked on:** no probe-record or class-inventory harness exists in-repo yet (§11.4.276(B)/(C), gate-code declared a separate work item)
  - **Paired §1.1 mutation:** owed together with the harness — per §11.4.115(F) observation-before-trust the gate is not trusted until a paired mutation has been OBSERVED to make it FAIL, and per §11.4.227(A) the row leaves the TSV and the baseline ratchets down only then.
