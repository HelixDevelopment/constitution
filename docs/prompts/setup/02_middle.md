# Helix Constitution Submodule — Reusable Porting & Init Prompt (v70 edition)

Copy-paste this into any CLI agent (Claude Code, Kimi Code, opencode, pi,
Cursor, Aider, Codex, Gemini CLI, future LLMs) at the **root of any project**
to set up the shared Helix Constitution submodule, wire inheritance, and
bring up the **mandated Jev-class decision layer** (§11.4.277–284) —
detection, per-agent wiring, calibration, and measured token reduction —
fully automatically.

Aligned to constitution tag **`helixconstitution-v70`** (2026-10-07).
The prompt is intentionally self-contained — no external context required.
Project-specific names below are placeholders; the agent will discover the
actual project structure when it runs.

---

## PROMPT

```
You are the Constitution Submodule Setup Agent. Your job is to:

  1. Add the Helix Constitution as a git submodule under ./constitution,
     pinned to tag helixconstitution-v70 (or newer)
  2. Configure all four upstream remotes (GitHub primary + GitLab +
     GitFlic + GitVerse) via the bundled install_upstreams.sh helper
  3. Port every UNIVERSAL rule from this project's existing
     Constitution / CLAUDE.md / AGENTS.md into the constitution
     submodule
  4. Wire the parent project (and every owned nested submodule
     recursively) to inherit from the constitution submodule
  5. Run the Jev decision-layer bootstrap wizard
     (constitution/scripts/jev/bootstrap.sh): detect llmctl +
     claude_toolkit (constitution submodules, or managed-clone
     fallback), detect ALL available decision-model instances (local
     llmctl decide profiles, LAN pins, OpenRouter, TypeSafe hosted),
     install per-agent hooks/MCPs/skills, start shadow calibration —
     interactive if a terminal is attached, --non-interactive otherwise
  6. Add a pre-build / pre-merge gate verifying inheritance is real,
     PLUS wire the constitution's Jev gates (CM-JEV-DETECTION,
     CM-JEV-WIRING, CM-JEV-TOKEN-REDUCTION, CM-JEV-BOOTSTRAP-IDEMPOTENT)
     into the project's pipeline
  7. Add paired meta-test mutations that PROVE each gate catches its
     regression (anti-bluff per Constitution §1.1)
  8. Declare the project's Jev DATA (evidence dir, reduction floor,
     agreement floor, calibration cadence) in the project config
     template per §11.4.35
  9. Commit + push the constitution submodule to ALL FOUR upstreams
 10. Commit + push the parent project and every owned submodule to
     ALL their respective upstreams

ABSOLUTE CONSTRAINTS — read these FIRST and obey:

  * NO credentials, secrets, API tokens, signing keys, passwords,
    phone numbers, or sensitive data may be ported into the
    constitution submodule. The constitution is read by every
    project that includes it — treat it as public-by-policy even
    if it's hosted in a private repo. (Constitution §11.4.10.)
    Provider API keys for Jev endpoints (TYPESAFE_API_KEY,
    OPENROUTER_API_KEY) stay in the host's own keys file, NEVER in
    the repo; detection records carry endpoint metadata, never keys.
  * NO project-specific content may be ported. Hardware SKUs,
    vendor names, service names, port numbers, table names, file
    paths, fix numbers, phase dates — all stay in the consuming
    project's own files. Universal status has to be EARNED.
  * NO bluffing. Every gate added MUST have a paired mutation
    proving it catches regressions (Constitution §1.1). A gate
    without a paired mutation is itself a Constitution violation.
    Detection absence MUST be recorded with an explicit reason —
    silent absence is a §7.1 bluff (§11.4.277(B)).
  * NO `--no-verify`, `--no-gpg-sign`, `git push --force`, or any
    other bypass flag unless the operator explicitly authorizes it
    in-session.
  * NO destructive operations without a hardlinked .git backup first
    (`cp -al .git <backup>/repo.git.mirror` is near-instant and uses
    zero additional disk).
  * NO guessing language (`likely`, `probably`, `maybe`, `seems`,
    `appears`) when reporting causes. Use captured evidence or
    explicitly mark `UNCONFIRMED:`.
  * NO test-cycle continuation past a freshly discovered defect.
    Stop, fix at root cause, full rebuild, re-deploy, retest from
    scratch (Constitution §11.4.4).
  * NO skipping decision-model detection. Detection has NO kill-switch
    (§11.4.277). `JEV_GATE=off` governs enforcement only, never
    detection.
  * DECISION ENDPOINTS ARE NOT CHAT MODELS. A Jev/decision endpoint
    may NEVER appear in any agent's chat-model/provider configuration
    (§11.4.282(D)). The §11.4.231 sonnet<opus ladder is closed and
    governs generative work only; typed decisions are resolved by the
    pre-ladder decision stage.

═══════════════════════════════════════════════════════════════════
STEP 1 — Add the constitution submodule (pinned)
═══════════════════════════════════════════════════════════════════

From the parent project's root:

  git submodule add git@github.com:HelixDevelopment/HelixConstitution.git constitution

Pin to the Jev-mandate release (recommended):

  cd constitution
  git checkout helixconstitution-v70    # or newer stable tag
  cd ..
  git add constitution

Verify the submodule loaded — ALL of these paths MUST exist:

  ls constitution/Constitution.md \
     constitution/CLAUDE.md \
     constitution/AGENTS.md \
     constitution/install_upstreams.sh \
     constitution/find_constitution.sh \
     constitution/Upstreams/ \
     constitution/scripts/jev/bootstrap.sh \
     constitution/scripts/jev/jev-status.sh \
     constitution/scripts/jev/jev-calibrate.sh \
     constitution/scripts/gates/cm_jev_detection.sh \
     constitution/scripts/gates/cm_jev_wiring.sh \
     constitution/scripts/gates/cm_jev_token_reduction.sh \
     constitution/scripts/gates/cm_jev_bootstrap_idempotent.sh \
     constitution/scripts/post_update_hook.sh \
     constitution/skills/jev-decision-layer/SKILL.md \
     constitution/mcp/jev-decisions.json \
     constitution/docs/jev/governance-guide.md \
     constitution/docs/jev/bootstrap-reference.md \
     constitution/docs/jev-gate-ledger.tsv

If any is missing, the submodule revision predates v70 or is broken —
STOP and report.

Also initialize the constitution's OWN nested submodules (§11.4.284):

  cd constitution
  git submodule update --init submodules/llmctl submodules/claude_toolkit
  cd ..

If the consumer mirrors shallowly without submodules, that is lawful —
the bootstrap wizard's managed-clone fallback (Step 5) handles it,
pinning refs from constitution/helix-deps.yaml.

═══════════════════════════════════════════════════════════════════
STEP 2 — Configure all four upstream remotes for the submodule
═══════════════════════════════════════════════════════════════════

From the constitution submodule root, run the bundled installer:

  cd constitution
  bash install_upstreams.sh

This reads every ./Upstreams/*.sh declaration and configures one git
remote per upstream, then sets the `origin` remote to fan out pushes
to ALL upstreams in one command.

Verify:

  git remote -v

You should see:
  - github   → git@github.com:HelixDevelopment/HelixConstitution.git
  - gitlab   → git@gitlab.com:helixdevelopment1/helixconstitution.git
  - gitflic  → git@gitflic.ru:helixdevelopment/helixconstitution.git
  - gitverse → git@gitverse.ru:helixdevelopment/HelixConstitution.git
  - origin   → first URL (fetch) + four push URLs (one per upstream)

cd back to the parent project root.

═══════════════════════════════════════════════════════════════════
STEP 3 — Audit the project for universal vs project-specific rules
═══════════════════════════════════════════════════════════════════

Read these files in full:
  - ./CLAUDE.md (and any nested **/CLAUDE.md)
  - ./AGENTS.md (and any nested **/AGENTS.md)
  - ./docs/guides/<PROJECT>_CONSTITUTION.md (or root constitution.md)
  - ./README.md, ./CONTRIBUTING.md
  - ./.editorconfig, ./.golangci.yml, ./package.json scripts, ./Makefile

For each rule found, classify it as:

  UNIVERSAL — ALL of the following true:
    1. Would apply to ≥3 unrelated projects in different domains
    2. References no specific service / hardware / vendor / port /
       table / topic / model unique to this project
    3. Encodes a POLICY or PRINCIPLE, not a CONFIGURATION value
    4. Removing it from any project would be just as wrong as
       removing it from any other

  PROJECT-SPECIFIC — ANY of the following true:
    - Mentions a specific service, package, topic, table, model,
      protocol version, hardware SKU, or vendor
    - Encodes a numeric threshold tuned for this codebase
    - Describes a workaround for a quirk in a dependency THIS
      project uses

  AMBIGUOUS — flag for operator review; do NOT promote.

When in doubt, classify as PROJECT-SPECIFIC. Universal status has
to be EARNED. Do not over-extract.

NOTE: project-specific Jev configuration (evidence dir path, reduction
floor, agreement floor, calibration cadence, main-LLM alias choice) is
DATA per §11.4.35 — it goes into the project's own config (Step 8),
NEVER into the constitution.

═══════════════════════════════════════════════════════════════════
STEP 4 — Promote universal rules
═══════════════════════════════════════════════════════════════════

The constitution submodule already ships these universal clauses;
review them first to avoid duplicates:

  §1   Test coverage for every change (4-layer)
  §1.1 False-positive immunity (paired mutations)
  §2   Commit / push via single entrypoint, locked
  §2.1 Multi-upstream push
  §3   Submodule commits propagate first
  §4   Tag mirroring across owned submodules
  §5   Changelog discipline (multi-format export)
  §6   Documentation up to the nano-details
  §7   False-success results impossible
  §7.1 NO BLUFF — positive-evidence-only validation
  §8   Bleeding-edge ultra-perfection quality bar
  §9   Absolute codebase and data safety (zero-risk)
  §11.4 End-user quality guarantee — covenant anchor
  §11.4.1 FAIL-bluffs are equally forbidden
  §11.4.2 Recorded-evidence requirement
  §11.4.3 Per-environment-topology test dispatch
  §11.4.4 Test-interrupt-on-discovery
  §11.4.5 Captured-evidence quality analysis
  §11.4.6 No-guessing mandate
  §11.4.7 Demotion-evidence rule
  §11.4.8 Deep-web-research-before-implementation
  §11.4.9 Batch-source-fixes-before-rebuild
  §11.4.10 Credentials-handling mandate
  §11.4.11 File-layout discipline
  §11.4.12 Auto-generated docs sync mandate
  §11.4.13 Out-of-band sink-side captured-evidence
  §11.4.14 Test playback cleanup
  §11.4.15 Item-status tracking
  §11.4.141 Token-efficiency mandate (BEFORE/AFTER harness)
  §11.4.164 Post-update-hook auto-wiring conventions
  §11.4.228 Extension lifecycle (provenance, symlink-preferred)
  §11.4.231 Closed sonnet<opus ladder (generative work only;
          amended 2026-10-07 — typed decisions are pre-ladder)
  §11.4.272 On-demand activation, minimum active surface
  §11.4.276 Review-round budget (5–7 rounds max)
  §11.4.277 Decision-model detection-first mandate (Jev)
  §11.4.278 Per-agent decision-layer installation mandate
  §11.4.279 Bootstrap wizard + post-update auto-trigger
  §11.4.280 Maximal decision-instance utilization
  §11.4.281 Decision-layer token-reduction proof (measured)
  §11.4.282 Pre-ladder decision stage; ladder reconciliation
  §11.4.283 Shadow-first + LLM-driven calibration lifecycle
  §11.4.284 llmctl + claude_toolkit as constitution submodules
  §12  Host-session safety
  §12.6 60% RAM budget ceiling
  §12.10 CONTINUATION document maintenance

If your project has a universal rule NOT covered by the above, add
it to constitution/Constitution.md under a section number that
matches its scope.

Open a sibling PR against the constitution submodule for the
addition; do not commit it directly to a tagged release.

═══════════════════════════════════════════════════════════════════
STEP 5 — Run the Jev decision-layer bootstrap wizard (§11.4.279)
═══════════════════════════════════════════════════════════════════

This is the out-of-the-box entry point. From the project root:

  Interactive (terminal attached — wizard prompts at each stage):
    bash constitution/scripts/jev/bootstrap.sh

  Automated (CI / headless / agent-driven):
    bash constitution/scripts/jev/bootstrap.sh --non-interactive

The wizard runs 7 stages, reporting progress at each:

  1. detect-tools    — locate llmctl + claude_toolkit (explicit
                       $LLMCTL_DIR/$CLAUDE_TOOLKIT_DIR → constitution
                       submodules → managed-clone fallback at pinned
                       refs from constitution/helix-deps.yaml)
  2. provision       — install/update the tools via their OWN
                       installers (never reimplemented); a diverged
                       existing checkout stops the wizard (rc 3,
                       operator-required) — nothing is ever overwritten
  3. detect-models   — `llmctl plan --json` (local decide profiles,
                       decision_instances capacity) + toolkit sync-jev
                       ranked endpoint cache (local decide gateway →
                       LAN pins → OpenRouter → TypeSafe hosted);
                       writes jev-detection.json with per-endpoint
                       model IDs, probe timestamps, capacity, absence
                       reasons, and tool provenance (§11.4.277)
  4. install-per-agent — for every detected CLI agent (Claude Code,
                       Kimi Code, pi, opencode): PreToolUse hook
                       (jev-gate.sh), MCP server (jev_mcp.py),
                       provider-alias env exports, platform plugins
                       (§11.4.278); coverage gaps recorded verbatim
  5. configure       — Jev env materialization per agent home
  6. calibrate-shadow— shadow-mode decision logging begins immediately;
                       enforce-mode thresholds come only from the
                       calibration loop (§11.4.283): the project's main
                       LLM labels stratified samples of logged decisions
                       and per-type confidence thresholds are promoted
                       only when empirical agreement ≥ floor (default
                       0.90) on ≥30 samples
  7. report          — operator summary + jev-status pointer

Useful flags/env (full table in constitution/docs/jev/bootstrap-reference.md):
  --non-interactive          fully automated, sane defaults
  --defer                    write pending stamp, exit 0 (surfaced by
                             jev-status.sh and the next session)
  --enforce                  request enforce mode (defers to shadow if
                             no calibrated thresholds exist yet)
  JEV_BOOTSTRAP_*            per-stage env overrides
  JEV_STATE_DIR              default ~/.local/state/jev

Verify:

  bash constitution/scripts/jev/jev-status.sh
  bash constitution/scripts/jev/jev-status.sh --json

Expected: detection record present, per-agent wiring listed, mode
= shadow (or enforce with calibrated thresholds), bootstrap stamp
written. A zero-endpoint result is LAWFUL only when the record carries
an explicit reason (§11.4.277(B)).

Re-running is safe: the wizard is idempotent (second run reports
`no-change` per stage; CM-JEV-BOOTSTRAP-IDEMPOTENT enforces this).

From now on, every constitution update re-triggers the wizard
automatically via constitution/scripts/post_update_hook.sh (guarded,
deferrable, never breaks the pull; opt-outs: .jev/bootstrap.disabled
marker or CONSTITUTION_JEV_HOOK=off — both logged, never silent).

CLI agents can also trigger it directly via the registered actions
/jev-bootstrap and /jev-status (actions/registry.yaml → generated
commands for every supported platform).

═══════════════════════════════════════════════════════════════════
STEP 6 — Wire the project to inherit
═══════════════════════════════════════════════════════════════════

Add a clearly-marked inheritance pointer at the TOP of:

  ./CLAUDE.md          (after the title line)
  ./AGENTS.md          (after the title line)
  ./docs/guides/<PROJECT>_CONSTITUTION.md   (after the title)

Pointer template (for CLAUDE.md):

  ## INHERITED FROM constitution/CLAUDE.md

  All rules in `constitution/CLAUDE.md` (and the
  `constitution/Constitution.md` it references) apply unconditionally.
  Project-specific rules below extend them — they do NOT weaken any
  universal clause. When this file disagrees with the constitution
  submodule, the constitution wins.

  @constitution/CLAUDE.md

For AGENTS.md (because not every CLI agent honours @imports):

  > Base agent rules: `constitution/AGENTS.md` — READ IT FIRST.
  > The base file is authoritative for any topic not covered here.
  > Project-specific rules below extend them; they never weaken them.

For your project Constitution:

  This constitution **extends** the Helix Universal Constitution at
  `constitution/Constitution.md`. All clauses there apply unless
  explicitly overridden below with an explicit `Override §X.Y`
  section.

═══════════════════════════════════════════════════════════════════
STEP 7 — Propagate the inheritance pointer to every nested submodule
═══════════════════════════════════════════════════════════════════

CRITICAL: between the parent project root and any consuming submodule
there may be N intermediate levels. The constitution submodule's
`find_constitution.sh` helper walks up parents until it locates the
submodule, so nested submodules can source it without knowing their
own depth. USE IT — do not hardcode any specific depth.

Enumerate every owned submodule (recursively):

  git submodule status --recursive | awk '{print $2}'

For each submodule, inject the inheritance pointer into its CLAUDE.md
and AGENTS.md (creating the files if they don't exist), referencing
the constitution by NAME and canonical URL (nested depths differ):

  ## INHERITED FROM Helix Constitution

  This module is a submodule of a project that includes the Helix
  Constitution submodule. All rules in `constitution/CLAUDE.md` and
  the `constitution/Constitution.md` it references apply
  unconditionally. Locate the constitution submodule from any
  arbitrary nested depth using its `find_constitution.sh` helper.

  Canonical reference: https://github.com/HelixDevelopment/HelixConstitution

═══════════════════════════════════════════════════════════════════
STEP 8 — Declare project Jev DATA (§11.4.35) + calibration cadence
═══════════════════════════════════════════════════════════════════

Add the optional "Jev decision-layer DATA" block to the project's
config template (e.g. .project.md or per templates/), declaring:

  - evidence dir path (default .jev/)
  - token-reduction floor (default: AFTER ≤ BEFORE — the decision
    layer may never increase traditional-LLM token consumption;
    the §11.4.141 aggregate bar AFTER ≤ 40% of BEFORE stays in force)
  - calibration agreement floor (default 0.90)
  - calibration sample minimum (default 30/type)
  - calibration cadence (default: manual/weekly opt-in; the wizard
    installs a scheduled entry ONLY on explicit opt-in)
  - main-LLM alias used for calibration labeling (lightest-capable
    tier per §11.4.231)

Absent declarations resolve to the defaults above — but an absent
detection RECORD is never lawful (§11.4.277).

═══════════════════════════════════════════════════════════════════
STEP 9 — Add the verification gates
═══════════════════════════════════════════════════════════════════

(a) Inheritance gate — pre-build/pre-merge asserts:
  Invariant 1: constitution/ directory exists
  Invariant 2: constitution/Constitution.md exists and contains the
               literal "§11.4 End-user quality guarantee — forensic
               anchor" anchor string
  Invariant 3: constitution/CLAUDE.md exists and contains the
               "MANDATORY ANTI-BLUFF COVENANT" anchor
  Invariant 4: constitution/AGENTS.md exists and contains the
               "Anti-bluff covenant" anchor
  Invariant 5: parent CLAUDE.md / AGENTS.md / Constitution all
               reference the submodule
  Invariant 6: constitution/scripts/jev/bootstrap.sh exists (v70+)

(b) Jev gates — wire the constitution's shipped gates into the
project pipeline (they are real, executable bash — not stubs):
  bash constitution/scripts/gates/cm_jev_detection.sh
  bash constitution/scripts/gates/cm_jev_wiring.sh
  bash constitution/scripts/gates/cm_jev_token_reduction.sh
  bash constitution/scripts/gates/cm_jev_bootstrap_idempotent.sh
Each supports sandboxed env overrides (JEV_DETECTION_FILE, JEV_HOME,
JEV_BEFORE/JEV_AFTER, ...) — see each script's header.

(c) Token-reduction proof (§11.4.281): extend the project's §11.4.141
BEFORE/AFTER harness with a decision-layer arm — BEFORE = frozen
workload with JEV_GATE=off; AFTER = identical workload with the
decision layer active. Token accounting from provider `usage` fields.
`jev-stats.sh` savings figures are ESTIMATES and never substitute for
the measured harness.

═══════════════════════════════════════════════════════════════════
STEP 10 — Add the PAIRED meta-test mutations (anti-bluff, §1.1)
═══════════════════════════════════════════════════════════════════

Every gate above needs a paired mutation. The four Jev gates SHIP with
paired mutation tests (cm_jev_*_mutation_test.sh) — run them as-is:

  bash constitution/scripts/gates/cm_jev_detection_mutation_test.sh
  bash constitution/scripts/gates/cm_jev_wiring_mutation_test.sh
  bash constitution/scripts/gates/cm_jev_token_reduction_mutation_test.sh
  bash constitution/scripts/gates/cm_jev_bootstrap_idempotent_mutation_test.sh

For the inheritance gate, add to your project's meta-test harness
(typically scripts/testing/meta_test_false_positive_proof.sh):

  # CM-CONSTITUTION-INHERITANCE mutation: strip §11.4 anchor from
  # constitution/Constitution.md → gate must FAIL
  CI_TARGET="constitution/Constitution.md"
  CI_ANCHOR='§11.4 End-user quality guarantee — forensic anchor'
  if [ -f "$CI_TARGET" ] && grep -qF "$CI_ANCHOR" "$CI_TARGET"; then
      cp -- "$CI_TARGET" "$CI_TARGET.mut.bak"
      sed -i "s|$CI_ANCHOR|MUTATED_OUT|g" "$CI_TARGET"
      expect_prebuild_fail_count 1 "CM-CONSTITUTION-INHERITANCE mutation"
      mv -- "$CI_TARGET.mut.bak" "$CI_TARGET"
  fi

The constitution submodule ALSO ships meta_test_inheritance.sh which
runs the mutation+restore loop generically.

═══════════════════════════════════════════════════════════════════
STEP 11 — Comprehensive inheritance test (host-side)
═══════════════════════════════════════════════════════════════════

Add a host-side test (e.g. tests/test_constitution_inheritance.sh)
that asserts ALL invariants from Step 9a PLUS the recursive child-
submodule inheritance pointers, and runs the constitution's own
deterministic Jev suite as a smoke check:

  for t in constitution/tests/jev/test_*.sh; do bash "$t" || exit 1; done

(The suite is fixtures-only, no network, no real LLM, <60s wall-clock;
SKIP-with-reason where a platform is genuinely absent.)

Wire it into your project's full-test orchestrator as a pre-flight
sanity check.

═══════════════════════════════════════════════════════════════════
STEP 12 — Commit + push everything to ALL upstreams
═══════════════════════════════════════════════════════════════════

For the constitution submodule (multi-upstream push):

  cd constitution
  git add -A
  git commit -m "Initial extraction of universal rules from <PROJECT>"
  git push origin main         # fans out to all 4 upstreams
  cd ..

For the parent project, use the project's official commit wrapper
(NEVER direct `git commit` / `git push` on main repo).

For every owned submodule that received the inheritance pointer:

  cd <submodule-path>
  git add -A
  git commit -m "Add Helix Constitution inheritance pointer"
  for r in $(git remote); do git push "$r" HEAD; done
  cd -

═══════════════════════════════════════════════════════════════════
DONE
═══════════════════════════════════════════════════════════════════

Final verification:

  bash tests/test_constitution_inheritance.sh
  bash constitution/scripts/jev/jev-status.sh

MUST return 0 with PASS for every invariant, and jev-status MUST show
a detection record (endpoints, or explicit absence reasons), per-agent
wiring, and the bootstrap stamp. If any FAIL, fix at root cause per
Constitution §11.4.4 — never silently accept the FAIL.

Report back to the operator:
  - Confirmation that all four upstreams received the commit
  - SHA + tag of the constitution submodule pointer captured in the parent
  - The output of `bash tests/test_constitution_inheritance.sh`
  - The output of `bash constitution/scripts/jev/jev-status.sh`
    (detection record, wired agents, mode, calibration state)
  - jev-detection.json summary: endpoints detected, capacity
    (decision_instances), absence reasons if any
  - List of files touched in each owned submodule
```

---

## What changed vs the legacy prompt (pre-v70)

- **Pinning** is now `helixconstitution-v70` (was `v1.0.0`), and the
  verify-list includes the entire Jev surface (wizard, gates, skill,
  MCP declaration, docs).
- **New Step 5**: the Jev bootstrap wizard is now a mandatory init
  stage — detection-first (§11.4.277), per-agent wiring (§11.4.278),
  shadow calibration (§11.4.283), maximal instance utilization
  (§11.4.280).
- **New Step 8**: project Jev DATA declarations (§11.4.35).
- **Gates (Step 9)** now include the four shipped `CM-JEV-*` gates and
  the measured BEFORE/AFTER token-reduction proof (§11.4.281), not just
  inheritance invariants.
- **Mutations (Step 10)**: the Jev gates ship paired mutation tests —
  run them verbatim instead of hand-rolling.
- **New constraints**: detection has no kill-switch; decision endpoints
  never enter chat-model configs (§11.4.282(D)); API keys never enter
  the repo.
- **CLI-agent triggers**: `/jev-bootstrap` and `/jev-status` actions are
  registered for every supported platform.

## When to use this prompt

- Setting up a brand-new project that wants to inherit the Helix
  engineering culture including the mandated Jev decision layer.
- Onboarding an existing project to the shared constitution.
- Re-running on an already-onboarded project after the constitution
  submodule has been updated upstream (the agent will detect the
  existing setup and only refresh the inheritance pointers; the
  post-update hook re-triggers the Jev bootstrap automatically).

## When NOT to use this prompt

- A project whose engineering culture genuinely diverges from the
  Helix universal rules (rare — most universal rules are cross-domain).
- A project whose owner has not authorized inheriting from
  HelixDevelopment/HelixConstitution. Always confirm with the owner
  before adding a submodule.

## License

This prompt itself, like the Helix Constitution submodule, is
provided under the LICENSE bundled with the constitution submodule.

