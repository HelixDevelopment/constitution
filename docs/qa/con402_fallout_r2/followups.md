# CON-402 audit fallout, round 2: follow-up items and honest boundaries

Status: PROVISIONAL. Every item below is a placeholder for the tracker (no id minted here). Evidence class:
gate-logic (hermetic tests of a census and of test layers), not a live product run.

## FU-1 (from F1-A, corrected scope): attributes inherited from a sourcing parent or BASH_ENV

Measured 2026-11-17 (`gitenv_census_attr_probe.txt`): the file-scope git-env census
(`scripts/validation/git_env_class_census.py`) already refuses an in-file `declare -l _ge_v` before the canonical
line (`UNSCRUBBED`, the declare is not a preamble statement); `_ge_v=x` and `shopt -s nullglob` before it are
accepted and harmless (no attribute). An earlier working note of this fixer that this census had the same in-file
gap was wrong and is withdrawn here.

The residual is outside any file-scope census: when a file carrying the canonical line is SOURCED by a shell that
already holds `declare -l _ge_v` (or a `BASH_ENV` script sets it), the loop unsets lower-case names. Bash truth
(same probe): `declare -l _ge_v; for _ge_v in WT_PATH _FC_SAFE GIT_DIR; do unset "$_ge_v"; done` leaves
`wt_path=[UNSET]` and the function `_fc_safe` gone; the control without the attribute keeps both.
Proposed item text: "Make the canonical shell scrub immune to inherited attributes: prefix it with
`unset -v _ge_v;` (removes any attribute before the loop) or `declare +l +u +c +i _ge_v`, update CANON_SH in both
censuses and every file carrying the canonical line in one generated change, with a paired mutant and a sourced-parent RED."

## FU-2 (F1-E residual): `unset -f` of other functions of the file is not modelled

The round-2 census refuses `unset` / `unset -f` of the three trusted functions (`_fc_safe`, `_fc_run_child`,
`_fc_mktemp`). An `unset -f` of any other function defined in the file (for example `_sc_one`) is not modelled;
a later call then runs an external command or fails with 127. Proposed item text: "safepath census: treat
`unset -f NAME` (and `unset NAME` that resolves to a function) of any function defined in the file as a
violation, with golden-false for unrelated names."

## FU-3 (F1-D, pre-existing, record only, as the review asked)

Two here-documents opened on one line: the safepath census reports an EXEMPT row for a heredoc-data line and then
refuses an unrelated line (rc=1). Fail-closed, not an escape; it comes from the single-match `HEREDOC_RE`. Not
changed in round 2. Proposed item text: "safepath census: handle every here-document opened on one line
(multi-match HEREDOC_RE), with a two-heredoc needle."

## FU-4 (N6): unchanged in round 2

The CON-402 scrub still sits before `import _signal as _early_sig` in fc_supervisor.py. Round 2 does not move it.
The review's proposal stands: keep N6 open in CON-450 or split it out, with an acceptance that adds a
DEGRADED-environment (no `--block-signal`) case that sends SIGINT inside the `import os` window; whether the
widening matters there is UNCONFIRMED.

## FU-5: work-directory mode drift on this host

`/mnt/DATA1TB/claude-work/scratch` and `/mnt/DATA1TB/claude-work/tmp` are `drwxrwxr-x` (group-writable, no
sticky bit); the operator decision of 2026-11-14 placed TMPDIR under `/mnt/DATA1TB/claude-work/` with owner-only
directories. Any TMPDIR under `scratch` is therefore classed `shared:` by the round-2 sweep probe
(`topology_probe.txt`), and the kill ledger regenerated there is refused by the guard table (GB12). Not changed
by this fixer (host configuration, operator's decision, section 11.4.66).
