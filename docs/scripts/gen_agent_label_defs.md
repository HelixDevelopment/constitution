# gen_agent_label_defs.sh — agent-type label definition generator

**Revision:** 3
**Last modified:** 2026-10-15T03:50:00Z
**Authority:** constitution submodule §11.4.182 clause (8) (work-stream label, agent-type extension) · §11.4.231 (F.5) (effort tiering) · §11.4.209 / §11.4.211 (reviewer / merge-conflict pins) · §11.4.18 (script docs)
**Classification:** universal (§11.4.17)

## Why

The Claude Code agents list renders `<subagent_type>  <live progress>`. The only
caller-controlled text in that row is the **type name**, so the §11.4.182 label
is baked into it, including the Claude Toolkit alias:
`T<N>-<branch>-<alias>-<model>-<effort>`, for example `T1-main-claude5-opus-xhigh`.
The description starts with the full label `(T1/main - claude5 - opus - xhigh)`.

The definition **sets** `model:` and `effort:` in its frontmatter. It does not
enforce them on its own: on the current platform a per-invocation `model` or
`effort` parameter overrides the frontmatter, and `CLAUDE_CODE_EFFORT_LEVEL`
overrides both. The §11.4.182 guard hook flags such overrides for label types
(WARN; BLOCK under `AGENT_TYPE_LABEL_ENFORCE=1`; see `guard-track-branch-label.md`),
which is what keeps the type name honest. A model set by an installed mod's
`agent.spawn` hook also replaces the per-invocation one; the guard cannot see it.
`T<N>-<branch>-<alias>-opus-xhigh` is the §11.4.209 reviewer / §11.4.211
merge-conflict substrate when dispatched without overrides.

## Usage

```bash
G=constitution/scripts/multitrack/gen_agent_label_defs.sh
bash $G --track 1 --branch main --alias claude5 --out-dir .claude/agents            # default 4 types
bash $G --track 1 --branch main --alias claude5 --out-dir .claude/agents --all-types # 10 types
bash $G ... --types opus-xhigh,sonnet-low      # explicit list of <model>-<effort>
bash $G ... --check        # drift report, writes nothing
bash $G ... --dry-run      # plan, writes nothing
bash $G ... --print-names  # desired file names, writes nothing (used by the installer)
bash $G --classify some.md # absent | handmade | edited | genuine
bash $G --owner-alias some.md # alias that owns a generated v2 file (from its label)
```

| Flag | Meaning |
|---|---|
| `--track N` | decimal track number (required; `01` is normalised to `1`) |
| `--branch NAME` | git branch (required) |
| `--alias A` | the live Claude Toolkit alias (required). `?` or a value that sanitises to empty is **refused** (exit 2): an alias is never guessed. The installer derives it from `track_branch_label.sh` on every run, never from a cache. |
| `--out-dir DIR` | target directory (created on write) |
| `--types` / `--all-types` | default `sonnet-medium,sonnet-high,opus-high,opus-xhigh`; `--all-types` = `{sonnet,opus} x {low,medium,high,xhigh,max}` |
| `--colors-file F` | track -> colour data (default `agent_label_colors.tsv`: T1 blue, T2 green, T3 orange, T4 purple, T5 cyan, `*` yellow) |

Name segments come from the shared library `agent_label_lib.sh`
(`al_sanitise`): ASCII letters are lowercased, every other byte (`/`, `.`,
spaces, newlines, control characters, any non-ASCII byte) becomes `-`, runs
collapse, the ends are trimmed. It runs under `LC_ALL=C`, so the result is the
same on every host and locale. Names longer than 120 characters are refused
(exit 2, "too long"), never truncated. Every name is validated before anything
is written.

Exit codes: `0` ok · `1` drift (`--check`) · `2` usage (incl. unknown alias,
invalid or too long name, an option value that is missing, empty or starts with
`-`, an `--out-dir` containing a control character) · `3` a target is a **hand-made** file (no marker):
refused, nothing written · `4` a target is a generated file that was
**hand-edited** (front matter or body): refused, nothing written · `5` internal
error · `7` bash older than 4.

Requires **bash >= 4** (associative arrays). On older bash it exits 7 and the
post-update hook reports a warning.

## Generated file form

```
---
name: T1-main-claude5-sonnet-medium
description: "(T1/main - claude5 - sonnet - medium) Worker for T1/main via alias claude5, Sonnet at medium effort."
model: sonnet
effort: medium
color: blue
---
<!-- generated-by: gen_agent_label_defs.sh v2 (...); content-sha256: <hex>; regenerate with the generator, do not edit -->
<worker preamble: scope, evidence, no shared-state changes; the override boundary>
```

The marker is the line right after the closing `---`; `content-sha256` covers the
front matter and the body. A v1 marker (round-1 files without the alias
segment) is still recognised by `--classify`, so the installer can prune those
files; v1 is never written. The default 4 types cost about 490 characters of
name + description (about 120 tokens) in the Agent tool listing.

## Safety

- A hand-made target is never overwritten (exit 3); a hand-edited generated file
  is not overwritten either (exit 4). All-or-nothing: nothing is written if any
  target is refused. Files are written to a temp file and renamed, inside
  `--out-dir` only.
- `--check` reports missing, stale, hand-edited and extra generated files with
  the same `T<N>-<branch>-<alias>-` prefix; hand-made files are never "extra".
- `agent_label_frontmatter_check.py` is the independent validator (name ==
  `T<N>-<branch>-<alias>-<model>-<effort>` rebuilt from the description label,
  closed key, model, effort and colour sets, a `?` alias rejected, PyYAML
  cross-parse when available; each OK line says `cross-parse: ran|skipped`).

## Honest boundary (§11.4.6)

When a new or changed definition becomes dispatchable is decided by the agent
platform, and **no load time is guaranteed**. Measurements so far are listed in
`install_agent_label_defs.md` ("Load boundary"). Restart the session after an
install that changed files. The row text beyond the type name (live progress,
elapsed, tokens) is not controllable. Whether `xhigh`/`max` are honoured for
every model is a platform property, UNVERIFIED.

## Tests / gates

`test_gen_agent_label_defs.sh` (134 cases), gate `CM-AGENT-TYPE-LABEL`
(`scripts/gates/cm_agent_type_label.sh`) and its paired §1.1 mutation test.

**Last verified:** 2026-10-15.
