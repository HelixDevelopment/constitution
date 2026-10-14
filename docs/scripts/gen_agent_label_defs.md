# gen_agent_label_defs.sh — agent-type label definition generator

**Revision:** 1
**Last modified:** 2026-10-15T00:00:00Z
**Authority:** constitution submodule §11.4.182 (work-stream label, agent-type extension) · §11.4.231(F) (effort tiering) · §11.4.209 / §11.4.211 (reviewer / merge-conflict pins) · §11.4.18 (script docs)
**Classification:** universal (§11.4.17)

## Why

The Claude Code agents list renders `<subagent_type>  <live progress>`. The only
caller-controlled text in that row is the **type name**, so the §11.4.182 label
is baked into it: `T<N>-<sanitised-branch>-<model>-<effort>` (for example
`T1-main-sonnet-medium`). A custom agent definition also **enforces** its
`model:` and `effort:` frontmatter, which closes the per-agent effort gap
documented in §11.4.231(F.2) by construction. `T<N>-<branch>-opus-xhigh` is the
§11.4.209 reviewer / §11.4.211 merge-conflict-resolution substrate.

## Usage

```bash
bash constitution/scripts/multitrack/gen_agent_label_defs.sh \
  --track 1 --branch main --out-dir .claude/agents          # 2 models x 5 efforts = 10 files
bash ... --track 2 --branch feature/x --out-dir .claude/agents --models opus --efforts xhigh
bash ... --track 1 --branch main --out-dir .claude/agents --check     # drift report, writes nothing
bash ... --track 1 --branch main --out-dir .claude/agents --dry-run   # plan, writes nothing
bash ... --classify some.md          # absent | handmade | edited | genuine
```

| Flag | Meaning |
|---|---|
| `--track N` | decimal track number (required) |
| `--branch NAME` | git branch; sanitised for the name: lowercase, `/` -> `-`, only `[a-z0-9-]` |
| `--out-dir DIR` | target directory (created on write) |
| `--models` / `--efforts` | comma lists, closed sets `{sonnet,opus}` / `{low,medium,high,xhigh,max}` |
| `--colors-file F` | track -> colour data (default `agent_label_colors.tsv`: T1 blue, T2 green, T3 orange, T4 purple, T5 cyan, `*` yellow) |

Exit codes: `0` ok - `1` drift (`--check`) - `2` usage - `3` a target is a
**hand-made** file (no generated marker): refused, nothing written - `4` a target
is a generated file that was **hand-edited** (hash mismatch): refused, nothing
written - `5` internal error.

## Generated file form

```
---
name: T1-main-sonnet-medium
description: "(T1/main - <alias> - sonnet - medium) T1/main worker on Sonnet at medium effort. ..."
model: sonnet
effort: medium
color: blue
---
<!-- generated-by: gen_agent_label_defs.sh v1 (...); content-sha256: <hex>; regenerate with the generator, do not edit -->
<short project-agnostic worker preamble>
```

The marker follows the closing `---`, so it cannot affect frontmatter parsing.
`content-sha256` covers the frontmatter block plus the body. Output has no
timestamps; reruns are byte-identical. `<alias>` in the description is a literal
placeholder - the live alias stays in the Agent `description` the dispatcher
writes (the alias is not part of the type name).

## Safety

- A target without the marker (hand-made) is **never** overwritten (exit 3); a
  generated file whose hash no longer matches (hand-edited) is not overwritten
  either (exit 4). The check is all-or-nothing: nothing is written if any target
  is refused. Writes are atomic (temp + rename) and stay inside `--out-dir`.
- `--check` reports missing, stale, hand-edited and *extra* generated files for
  the same `T<N>-<branch>-` prefix; hand-made files are never "extra".
- The strict, generator-independent validator is
  `agent_label_frontmatter_check.py` (name regex, file name == name, closed
  model/effort/colour sets, label text in the description consistent with the
  name, no duplicate/unknown keys, PyYAML cross-parse when available).

## Honest boundary (§11.4.6)

Agent definitions are loaded by the agent platform. In one headless session a
file created mid-session became dispatchable after about 2 minutes; whether an
interactive session hot-loads is UNVERIFIED, so assume the next session start.
The row text beyond the type name (live progress, elapsed time, tokens) is not
controllable. Whether `xhigh`/`max` are honoured for every model is a platform
property and is UNVERIFIED here.

## Tests / gates

`test_gen_agent_label_defs.sh` (65 cases, run twice), gate `CM-AGENT-TYPE-LABEL`
(`scripts/gates/cm_agent_type_label.sh`) with its paired §1.1 mutation test.

**Last verified:** 2026-10-15.
