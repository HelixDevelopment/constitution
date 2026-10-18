# Helix Constitution — lean core (Layer 1)

This file is the ONLY constitution text an agent needs loaded up front. It is
deliberately small and byte-stable (it is a prompt-cache prefix). Everything else
lives on disk and is loaded on demand.

## Inheritance

This project inherits the full Helix Constitution from `constitution/`. For the
exact text of any rule, load `constitution/progressive/rules/<id>.md`, or call
`search_constitution(query)` / `load_rule(anchor_id)` on the local MCP server
(`constitution/progressive/mcp_server.py`). `Constitution.md` remains the
canonical source of truth and is never replaced by this core.

## Anti-bluff covenant (compressed §11.4)

1. **No PASS without recorded evidence.** Every green result emits a raw artifact
   (stdout, stderr, exit code, file hash, or provider `usage` metadata). Prose and
   screenshots are not evidence.
2. **No FAIL-bluff either.** A test that fails for the wrong reason (crash,
   timeout, missing dependency) is classified differently from one that fails on
   its assertion.
3. **Deterministic script logic is supreme.** LLM judgement is advisory until a
   deterministic check backs it.
4. **Every gate has a paired mutation.** A gate that cannot be shown to fail is a
   bluff gate and is repaired or removed before delivery.
5. **No guessing language.** Use captured evidence or mark `UNCONFIRMED:` and
   halt. `likely`, `probably`, `maybe`, `seems`, `appears` are forbidden as
   causes.
6. **No placeholders in delivered code** — no to-do/fix-me/hack markers, no stub
   bodies, and no "temporary" shims that claim to satisfy a deliverable.
7. **No history rewriting.** Merges only; no force-push, no squash that discards
   reviewed commits.
8. **No destructive operation without a hardlinked `.git` backup.**

## Cross-cutting invariants

- **Credentials never enter the constitution or the repository.** The canonical
  single source of truth is the consumer's `docs/accesses/accounts.md`;
  credential scanning is opt-in per consumer policy.
- **Host-session safety.** Heavy work stays bounded and below the host memory
  ceiling so the operator session is never OOM-killed. Never suspend, hibernate,
  log out, or weaken a session manager to go faster.
- **Review-round budget.** Ordinary work aims at ≤2 review rounds; a hard cap of
  5–7 exists for large features. Reviews end in a verdict, not in prose.
- **Definition of done** = implemented, wired by default, verified with captured
  evidence, and tracked to a terminal status. "Present but unreferenced" is not
  done.
- **Token efficiency (§11.4.141).** Prompt caching, model tiering, a thin
  always-loaded index, retrieval-first navigation, terse status output, batched
  tool calls, and compaction above 60% of the window. Exports are opt-in.
- **Progressive disclosure.** Load the smallest artifact that answers the
  question: a specific rule file, an area `CLAUDE.md`, or one `docs/context/*`
  note — never the whole `Constitution.md` when an anchor is named.
- **One task = one session; never switch accounts mid-session.** The cache is
  account-scoped and a switch re-bills the entire accumulated context.

## How to use this layer

| Need | Action |
|---|---|
| A specific rule | `load_rule("§11.4.141")` or read `progressive/rules/11.4.141.md` |
| A topic | `search_constitution("host safety")` → anchor ids, then `load_rule` |
| The full anchor list | `list_anchors()` (optionally by tag) |
| Prove a rule still matches source | `verify_anchor("§11.4.141")` |
| The canonical text | `Constitution.md` (never modified by the split) |
| Optimisation/rollout plan | `progressive/docs/PROGRESSIVE_DISCLOSURE.md` |
| What was measured and what was not | `progressive/EVIDENCE/` |

`HELIX_CONSTITUTION_MODE` selects the delivery mode: `progressive` (default,
this core + on-demand rules), `dual` (core + full text), `monolith` (the exact
pre-optimisation behaviour: `Constitution.md` only). All three remain functional.
