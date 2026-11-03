# credscan User Guide - counts-only credential-shape ratchet

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-28 |
| Last modified | 2026-10-28T12:00:00Z |
| Status | active |
| Status summary | How to baseline, check, schedule and read the credential ratchet without ever printing a value. |
| Authority | Tool documentation for `scripts/credscan/`; no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.201 / §11.4.273 (instrument honesty) and §11.4.18 (script documentation) govern. |
| Scope | Universal (§11.4.17): any host that keeps agent transcripts, prompt history or scratch secrets. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not regenerated for this revision (honestly stale, §11.4.106(E)). |

## What it is for

Agent transcripts (`~/.claude-shared/projects`), prompt history (`~/.claude-shared/history.jsonl`) and scratch secret directories persist whatever was typed or printed. credscan counts credential-SHAPED strings in those places. It never prints a value, a prefix or a hash. It does not remove anything: it makes sure the count never grows silently.

## Quick start

1. Record today's exposure as the baseline (counts only, mode 0600). This is a deliberate operator act.
   `python3 -I scripts/credscan/credscan.py baseline --default-roots --baseline ~/.local/state/credscan/baseline.json`
2. Check against it at any time.
   `python3 -I scripts/credscan/credscan.py check --default-roots --baseline ~/.local/state/credscan/baseline.json`
3. Ad-hoc counts for a directory or a repository tree: `credscan.py scan --root DIR [--json]`.
4. After you rotate keys, re-run step 1 to lock in the lower numbers.

Exit codes: 0 ok, 5 partial (unreadable or oversize entries; the zero is not evidence); wrapper-only: 124 timeout, 137/143 killed, 1 ratchet violated (a file/class count rose or a new file has hits), 2 cannot run (missing or malformed baseline, missing root, bad arguments, no HOME, no flock), 3 BLIND (the control needle failed, so the result is not evidence), 4 internal error (never confused with a violation; the status file says `error`).

## Run it on a timer (systemd user, low priority)

```
scripts/credscan/install_timer.sh --dry-run        # print the plan, change nothing
scripts/credscan/install_timer.sh --seed-baseline /path/to/counts.json
scripts/credscan/install_timer.sh --enable         # or: systemctl --user enable --now credscan-check.timer
```

The timer fires 10 minutes after boot and then every 30 minutes (`OnUnitActiveSec=30min`). The service runs at `Nice=19`, idle I/O and CPU scheduling, `MemoryMax=1G`, a 110-minute scan timeout inside the unit's 115-minute limit (measured: a first, uncached pass reads about 15-17 MB/s at normal priority, so an 11 GB tree needs on the order of 15 minutes to over an hour at idle priority; later passes use the counts-only incremental cache `~/.local/state/credscan/cache.json` and re-read only files whose mtime, size, inode, device or ctime changed (ctime cannot be set from user space, so `cp -p`/`touch -r` replacement is still detected; the cache is also invalidated whenever credscan.py itself or the size limit changes, and is checkpointed every 60 s and on SIGTERM so a timed-out first run keeps its progress), typically seconds), and takes a lock so two runs never overlap (an overlapping tick is skipped, exit 0). The installer never enables the timer unless asked, never scans to create a baseline, and never touches any `settings.json`.

Read the result in `~/.local/state/credscan/status.json` (counts only): `state` is one of `ok`, `ratchet_violated`, `baseline_missing`, `baseline_invalid`, `roots_missing`, `blind`, `timeout`, `error`, `running`, `partial`, `killed`. The wrapper sets `running` before each scan, so a run killed mid-way cannot leave an old `ok`; compare `time` with the clock to spot a stale record. The unit treats exit 0 and exit 1 as success (1 is a recorded ratchet violation, visible only in `status.json`, NOT in `systemctl --failed`); 2, 3, 4, 5 (`partial`: part of the scope could not be read, e.g. an unreadable root), 124 (timeout) and 137 (killed, e.g. by the OOM killer; recorded as `killed`) are real unit failures. An unattended run with no baseline reports `baseline_missing` and exit 2; it does not silently accept the current exposure.

## Reading "skipped"

Files that cannot be scanned are counted, never dropped silently: `binary`, `oversize` (files are streamed in 8 MiB chunks so large transcripts ARE scanned; only files above the 4 GiB ceiling, `CREDSCAN_MAX_BYTES`, are skipped; any oversize entry turns a `check` into `partial`, exit 5, and `baseline` warns that it is under-counted. A single unbroken run of 32 MiB without a newline is cut, so a token spanning that cut is missed), `special` (FIFOs, sockets, devices: never opened), `unreadable` (including directories that could not be listed; any such entry turns a `check` into `partial`, exit 5), `dangling` (symlinks whose target does not exist; counted, not an error). A large skipped count means the zero is weaker evidence; investigate before trusting it.

## The optional prompt hook

`credscan_hook.py` can warn or block on prompts and tool output (events UserPromptSubmit, PostToolUse). It is NOT installed by this tooling. See the manual for what a hook can and cannot do.
