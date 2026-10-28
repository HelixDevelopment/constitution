# credscan FAQ

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-28 |
| Last modified | 2026-10-28T12:00:00Z |
| Status | active |
| Status summary | Short answers about what credscan does, why it refuses, and what it does not do. |
| Authority | Tool documentation for `scripts/credscan/`; no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.201 / §11.4.273 (instrument honesty) and §11.4.18 (script documentation) govern. |
| Scope | Universal (§11.4.17): any host that keeps agent transcripts, prompt history or scratch secrets. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not regenerated for this revision (honestly stale, §11.4.106(E)). |

**Does it print my secrets?** No. Output is counts per file and class. No value, prefix or hash.

**Why does the timer report `baseline_missing`?** Nobody created a baseline. An unattended job must not decide to accept the current exposure. Run `credscan.py baseline ...` once, or install with `--seed-baseline`.

**Why exit 2 for a path that does not exist?** A zero over a folder that was never looked at looks identical to a clean folder. It is refused.

**What does exit 3 mean?** A planted control needle (any of the seven classes, or the file-reading path) was not counted, or the negative control matched. The scanner is blind, so its numbers are not evidence.

**What does exit 4 mean?** An internal error. It is deliberately different from 1 (ratchet violated) so a crash is never read as a result; `status.json` says `error`.

**Does a high `skipped` count matter?** Yes. Binary, oversize and unreadable files were not examined (unreadable entries make a `check` report `partial`, exit 5, never `ok`). Check them before trusting a zero.

**Why is the baseline not in the repository?** It contains host-specific paths. It lives under `~/.local/state/credscan/`.

**Does it install the prompt hook?** No. Nothing here edits any `settings.json`.

**Is the timer on?** Only if you enable it (`install_timer.sh --enable`). The installer does not enable it by default.

**Can it clean up leaked keys?** No. Rotate them, then re-baseline.

**Will it overlap itself or slow my machine?** No: a lock skips overlapping ticks; the service is Nice=19, idle I/O, memory-capped, time-limited.
