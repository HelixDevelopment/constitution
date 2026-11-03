# Helix Constitution Submodule — Reusable Porting Prompt

Copy-paste this into any CLI agent (Claude Code, Cursor, Aider, Codex,
Gemini CLI, future LLMs) at the **root of any project** to set up the
shared Helix Constitution submodule and port universal rules into it.

The prompt is intentionally self-contained — no external context
required. Project-specific names below are placeholders; the agent
will discover the actual project structure when it runs.

---

## PROMPT

```
You are the Constitution Submodule Setup Agent. Your job is to:

  1. Add the Helix Constitution as a git submodule under ./constitution
  2. Configure all four upstream remotes (GitHub primary + GitLab +
     GitFlic + GitVerse) via the bundled install_upstreams.sh helper
  3. Port every UNIVERSAL rule from this project's existing
     Constitution / CLAUDE.md / AGENTS.md into the constitution
     submodule
  4. Wire the parent project (and every owned nested submodule
     recursively) to inherit from the constitution submodule
  5. Add a pre-build / pre-merge gate verifying inheritance is real
  6. Add a paired meta-test mutation that PROVES the gate catches the
     missing-inheritance regression (anti-bluff per Constitution §1.1)
  7. Commit + push the constitution submodule to ALL FOUR upstreams
  8. Commit + push the parent project and every owned submodule to
     ALL their respective upstreams

ABSOLUTE CONSTRAINTS — read these FIRST and obey:

  * NO credentials, secrets, API tokens, signing keys, passwords,
    phone numbers, or sensitive data may be ported into the
    constitution submodule. The constitution is read by every
    project that includes it — treat it as public-by-policy even
    if it's hosted in a private repo. (Constitution §11.4.10.)
  * NO project-specific content may be ported. Hardware SKUs,
    vendor names, service names, port numbers, table names, file
    paths, fix numbers, phase dates — all stay in the consuming
    project's own files. Universal status has to be EARNED.
  * NO bluffing. Every gate added MUST have a paired mutation
    proving it catches regressions (Constitution §1.1). A gate
    without a paired mutation is itself a Constitution violation.
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

═══════════════════════════════════════════════════════════════════
STEP 1 — Add the constitution submodule
═══════════════════════════════════════════════════════════════════

From the parent project's root:

  git submodule add git@github.com:HelixDevelopment/HelixConstitution.git constitution

If you have a preferred pinning tag (recommended), check out that tag
inside the submodule:

  cd constitution
  git checkout v1.0.0    # or whatever stable tag exists
  cd ..
  git add constitution

Verify the submodule loaded:

  ls constitution/Constitution.md \
     constitution/CLAUDE.md \
     constitution/AGENTS.md \
     constitution/install_upstreams.sh \
     constitution/find_constitution.sh \
     constitution/Upstreams/

All six paths MUST exist. If any is missing, the submodule revision
you pulled is broken — STOP and report.

═══════════════════════════════════════════════════════════════════
STEP 2 — Configure all four upstream remotes for the submodule
═══════════════════════════════════════════════════════════════════

From the constitution submodule root, run the bundled installer:

  cd constitution
  bash install_upstreams.sh

This reads every ./Upstreams/*.sh declaration and configures one git
remote per upstream, then sets the `origin` remote to fan out pushes
to ALL upstreams in one command.

Alternative (if your toolkit ships the system-wide `install_upstreams`
command from Project-Toolkit/Upstreamable/):

  cd constitution
  install_upstreams        # reads ./Upstreams/ same as above

Verify:

  git remote -v

You should see:
  - github  → git@github.com:HelixDevelopment/HelixConstitution.git
  - gitlab  → git@gitlab.com:helixdevelopment1/helixconstitution.git
  - gitflic → git@gitflic.ru:helixdevelopment/helixconstitution.git
  - gitverse → git@gitverse.ru:helixdevelopment/HelixConstitution.git
  - origin  → first URL (fetch) + four push URLs (one per upstream)

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
  §12   Host-session safety
  §12.6 60% RAM budget ceiling
  §12.10 CONTINUATION document maintenance

If your project has a universal rule NOT covered by the above, add
it to constitution/Constitution.md under a section number that
matches its scope (extend §11.4.x for end-user-quality-related, §12
for host-safety-related, §9 for data-safety-related, etc).

Open a sibling PR against the constitution submodule for the
addition; do not commit it directly to a tagged release.

═══════════════════════════════════════════════════════════════════
STEP 5 — Wire the project to inherit
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
STEP 6 — Propagate the inheritance pointer to every nested submodule
═══════════════════════════════════════════════════════════════════

CRITICAL: between the parent project root and any consuming submodule
there may be N intermediate levels. The constitution submodule's
`find_constitution.sh` helper walks up parents until it locates the
submodule, so nested submodules can source it without knowing their
own depth. USE IT — do not hardcode any specific depth.

Enumerate every owned submodule (recursively):

  git submodule status --recursive | awk '{print $2}'

For each submodule, inject the inheritance pointer into its CLAUDE.md
and AGENTS.md (creating the files if they don't exist). Use the
same pointer template as Step 5 but reference the constitution by
NAME ("Helix Constitution") and canonical URL rather than by path,
because nested submodules sit at different filesystem depths.

Suggested pointer for nested submodules:

  ## INHERITED FROM Helix Constitution

  This module is a submodule of a project that includes the Helix
  Constitution submodule. All rules in `constitution/CLAUDE.md` and
  the `constitution/Constitution.md` it references apply
  unconditionally. Locate the constitution submodule from any
  arbitrary nested depth using its `find_constitution.sh` helper.

  Canonical reference: https://github.com/HelixDevelopment/HelixConstitution

═══════════════════════════════════════════════════════════════════
STEP 7 — Add the inheritance verification gate
═══════════════════════════════════════════════════════════════════

Add a pre-build (or pre-merge / pre-commit) gate that verifies:

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

Wire the gate into the project's pre-build / pre-commit pipeline
(typically `<project>/tests/pre_build_verification.sh` or
`.git/hooks/pre-commit`).

═══════════════════════════════════════════════════════════════════
STEP 8 — Add the PAIRED meta-test mutation (anti-bluff)
═══════════════════════════════════════════════════════════════════

Constitution §1.1 mandates that every gate be paired with a mutation
proving the gate is not itself a bluff gate.

Add to your project's meta-test harness (typically
`scripts/testing/meta_test_false_positive_proof.sh` or equivalent):

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
runs the mutation+restore loop generically. Your project can invoke
it directly with the project's own gate command as argument.

═══════════════════════════════════════════════════════════════════
STEP 9 — Comprehensive inheritance test (host-side)
═══════════════════════════════════════════════════════════════════

Add a host-side test (e.g. `tests/test_constitution_inheritance.sh`)
that asserts ALL invariants from Step 7 PLUS the recursive child-
submodule inheritance pointers. The reference implementation lives
in the ATMOSphere Android 15 project at
`device/rockchip/rk3588/tests/test_constitution_inheritance.sh` —
copy + adapt to your project's submodule list.

Wire it into your project's full-test orchestrator
(`test_all_fixes.sh`, `npm test`, `cargo test`, `pytest`, whatever)
as a pre-flight sanity check.

═══════════════════════════════════════════════════════════════════
STEP 10 — Commit + push everything to ALL upstreams
═══════════════════════════════════════════════════════════════════

For the constitution submodule (multi-upstream push):

  cd constitution
  git add -A
  git commit -m "Initial extraction of universal rules from <PROJECT>"
  git push origin main         # fans out to all 4 upstreams via origin's
                               # multiple push URLs
  cd ..

For the parent project, use the project's official commit wrapper
(NEVER direct `git commit` / `git push` on main repo):

  bash scripts/commit_all.sh   # or whatever your project uses

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

MUST return 0 with PASS for every invariant. If any FAIL, fix at
root cause per Constitution §11.4.4 — never silently accept the
FAIL.

Report back to the operator:
  - Confirmation that all four upstreams received the commit
  - SHA of the constitution submodule pointer captured in the parent
  - The output of `bash tests/test_constitution_inheritance.sh`
  - List of files touched in each owned submodule
```

---

## When to use this prompt

- Setting up a brand-new project that wants to inherit the Helix
  engineering culture.
- Onboarding an existing project to the shared constitution.
- Re-running on an already-onboarded project after the constitution
  submodule has been updated upstream (the agent will detect the
  existing setup and only refresh the inheritance pointers).

## When NOT to use this prompt

- A project whose engineering culture genuinely diverges from the
  Helix universal rules (rare — most universal rules are
  cross-domain).
- A project whose owner has not authorized inheriting from
  HelixDevelopment/HelixConstitution. Always confirm with the owner
  before adding a submodule.

## License

This prompt itself, like the Helix Constitution submodule, is
provided under the LICENSE bundled with the constitution submodule.

