# CON-402 audit fallout, round 3: follow-up items and honest boundaries

Status: PROVISIONAL. Every item below is a placeholder for the tracker (no id minted here). Evidence class:
gate-logic (hermetic tests of a census and of test layers), not a live product run. This file supersedes
`../con402_fallout_r2/followups.md` for FU-1, FU-2 and FU-5; FU-3 and FU-4 are carried over unchanged.

## FU-1 (corrected per review R2-5): attributes inherited from a sourcing parent or BASH_ENV

Measured 2026-11-17 on GNU bash 5.3.9 (`fu1/fu1_probe_r3.txt`, `fu1/fu1_probe_r3_combo.txt`):

| inherited state (set before the file runs) | no prefix | `unset -v _ge_v;` | `unset -n _ge_v;` | `unset -n _ge_v; unset -v _ge_v;` |
|---|---|---|---|---|
| `declare -n _ge_v=wt_path` (nameref) | wt_path kept | **wt_path unset** | wt_path kept | wt_path kept |
| `declare -l _ge_v` (no value) | **wt_path unset** | wt_path kept | **wt_path unset** | wt_path kept |
| DEBUG trap (`set -T`) | **unset** | **unset** | **unset** | not measured; a trap runs before every command |
| exported function `BASH_FUNC_unset%%` | **unset** | **unset** | **unset** | not measured; it shadows the builtin |

So `unset -v _ge_v` alone is wrong (it follows an inherited nameref and unsets the proved variable), and
`unset -n _ge_v` alone does not remove an inherited value-less `declare -l`. Proposed item text: "Make the canonical
shell scrub immune to inherited attributes: prefix it with `unset -n _ge_v; unset -v _ge_v;` (first drop a nameref
without following it, then drop any remaining attribute), update CANON_SH in both censuses and every file carrying
the canonical line in one generated change, with a paired mutant and a BASH_ENV / sourced-parent RED for both the
nameref and the value-less attribute case."

Boundary (stated, not closed): code that runs before the file (BASH_ENV, a sourcing parent, an exported function
from the environment, measured here for `BASH_FUNC_unset%%`) holds the script's rights. No prefix defeats an
inherited DEBUG trap or an exported `unset` function, and no file-scope census can see them. IFS is not inherited
from the environment (measured: `env IFS=_ bash -c ...` keeps the default IFS).

## FU-2: CLOSED in round 3 by the unset allow-list

`unset -f` (or `unset` without `-v`) of any function of the file is now refused unless the function is a scoped
helper (defined once inside one enclosing function, unset in it after its body, every mention between the two, no
loop keyword in the span). Rows `GE-sh-post-unset-other-func`, `GE-sh-post-helper-call-after`,
`GE-sh-post-helper-loop`; golden-false `GE-sh-gf-scoped-helper`; the real file's `_sc_one` is accepted.

## FU-3 (carried over, pre-existing): two here-documents opened on one line

Unchanged: the safepath census reports an EXEMPT row for a heredoc-data line and then refuses an unrelated line
(rc=1). Fail-closed. Proposed item text: "safepath census: handle every here-document opened on one line
(multi-match HEREDOC_RE), with a two-heredoc needle."

## FU-4 (carried over): N6 in fc_supervisor.py

Unchanged: the CON-402 scrub still sits before `import _signal as _early_sig`; whether the widening matters in a
DEGRADED environment is UNCONFIRMED.

## FU-5 (corrected per review R2-8): work-directory mode drift on this host

`/mnt/DATA1TB/claude-work/scratch` is `drwxrwxr-x` (group-writable, no sticky bit); the operator decision of
2026-11-14 placed TMPDIR under `/mnt/DATA1TB/claude-work/` with owner-only directories. Measured sequence (review
round 2, `out/f4/shared/sweep_shared.log`, `out/f4/shared/header_guard_summary.txt`): with TMPDIR under that shared
chain the kill sweep's control is RED at `test_review_record_resolution_ground_truth.sh` (ok 13 / NOT ok 10, every
capability-tier case returns `instance` because the scratch directory "is writable by others"), the sweep exits 1
and writes NO ledger. Separately, a `tmpdir_chain=shared:...` header written into the real 345-row ledger is refused
by the guard table (`NOT ok M4`, `NOT ok GT-REAL`); restored, the guard is GREEN again. Both seams refuse a shared
chain. GB12 stays a defence-in-depth check for a host where the control would pass on a shared chain. The host
mode is not changed by this fixer (host configuration, operator's decision, section 11.4.66).
