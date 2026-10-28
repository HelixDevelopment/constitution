# credscan Manual - classes, exit codes, files, limits

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-28 |
| Last modified | 2026-10-28T12:00:00Z |
| Status | active |
| Status summary | Reference for the credential-shape classes, control needle, status file, timer units and the honest limits of the tool. |
| Authority | Tool documentation for `scripts/credscan/`; no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.201 / §11.4.273 (instrument honesty) and §11.4.18 (script documentation) govern. |
| Scope | Universal (§11.4.17): any host that keeps agent transcripts, prompt history or scratch secrets. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not regenerated for this revision (honestly stale, §11.4.106(E)). |

## Files

| File | Role |
|---|---|
| `scripts/credscan/credscan.py` | engine: `scan`, `baseline`, `check`, `selftest` |
| `scripts/credscan/credscan_hook.py` | optional Claude Code hook (warn/block); not installed by default |
| `scripts/credscan/credscan_check_timer.sh` | the timer's ExecStart: lock, priority, timeout, `check`, status file |
| `scripts/credscan/install_timer.sh` | idempotent installer for the user units (`--dry-run`, `--enable`, `--seed-baseline`) |
| `scripts/credscan/systemd/credscan-check.{service,timer}` | the units |
| `scripts/credscan/tests/test_credscan.py` | tests: engine, honesty, status file, wrapper, units |

## Classes

`github` (ghp_/gho_/ghu_/ghs_/ghr_, github_pat_), `gitlab` (glpat-), `sk` (sk-, sk-ant-, sk-proj-), `aws` (AKIA/ASIA), `pem` (private-key header), `jev_gateway` (SHAPE only: 2-8 letters, `-`/`_`, at least 96 base64url characters; may also match other long tokens), `bearer` (`Bearer` plus 24 or more characters). One token counts once, in that priority order. Rejected as placeholders: runs of x, `<...>`, `$VAR`, example/dummy/fake/test/sample/redacted, low entropy.

## Instrument honesty (§11.4.273)

Every run plants one synthetic token per class (all seven) in text, plus one through the real file-reading path, and a negative control; any miss exits 3 (BLIND). Tokens are assembled at run time, so the source holds no scannable literal. A named root that does not exist, or no roots at all, exits 2 instead of reporting a quiet zero. Skipped files are counted (`SKIPPED` line, JSON `skipped`, the `check` summary line and the status file): `binary`, `oversize`, `special`, `unreadable` (directory listing errors included). An internal error exits 4 and is never reported as a violation. Symlinked directories are followed once each.

## Status file

`status.json` (mode 0600, directory 0700): `state`, `exit`, `violations`, `time`, and when a scan ran `total`, `files_with_findings`, `skipped`. `running` is written before each scan; `error` after an internal error. No paths of findings, no values.

## Baseline handling

The baseline holds per-file counts, therefore host-specific paths. It is never committed to a repository. Keep it at `~/.local/state/credscan/baseline.json` (0600). Refresh it only deliberately.

## Hook limits (docs-derived, partly UNKNOWN)

UserPromptSubmit can block and suppress the prompt but cannot rewrite it, and the text may still reach transcript and history. PostToolUse can only warn. No hook redacts persisted transcript or history lines. `CLAUDE_CODE_SKIP_PROMPT_HISTORY` disables all history writing (an operator decision); `cleanupPeriodDays` does not sweep `history.jsonl`. The hook fails open on malformed input. Its `suppressOriginalPrompt` field is not confirmed by documentation. A token directly after a JSON escape such as `\t` can be missed, and a very long identifier of 99 or more characters can be counted as `jev_gateway` (noise for the ratchet). `CREDSCAN_HOOK_MODE=warn` disables blocking.

## Honest limits

Shape matching finds shapes, not truth: a real secret in an unknown format is missed; a look-alike is counted. Only the default roots (or those given) are examined. Counting does not remove anything; rotation does. An operator may accept existing plaintext exposure until keys are rotated; the baseline records that decision as numbers and the ratchet prevents growth.

## Additions (exit 5, cache, dangling)

- Exit 5 = PARTIAL: no ratchet violation, but unreadable entries, oversize files (above the 4 GiB ceiling, `CREDSCAN_MAX_BYTES`) or unreadable roots were not examined, so the zero is not evidence. A violation (exit 1) takes precedence. Wrapper-only codes: 124 timeout, 137 killed; the wrapper returns 4 if the engine exited 0 without recording a result.
- `--cache F` (the wrapper uses `~/.local/state/credscan/cache.json`): counts-only, mode 0600, entry = path, mtime_ns, size, inode, device, ctime_ns, counts, skip reason; never a value. Keyed also on a hash of credscan.py and the size limit; a malformed entry is a miss. `scan` returns 0 on a partial scan (informational); only `check` maps partial to exit 5.
- `dangling` symlinks (target missing) are counted and reported, not an error.
