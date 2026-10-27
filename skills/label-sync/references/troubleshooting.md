# label-sync troubleshooting

| Symptom | Check | Meaning / fix |
|---|---|---|
| `labelctl.sh` exit 2 "go toolchain not found" | `command -v go`; `ls ~/.cache/constitution-label-sync/bin` | no binary and no Go: install Go once or copy a prebuilt `labelctl`. 2 is never a pass. |
| label shows `T?` | cwd is not a `/mnt/track<N>` checkout | honest unknown; do not type a track number |
| label shows `/?` branch | cwd not a git work tree | same |
| alias unchanged after switch | `get --id X --json \| jq .follow_active` | entity is pinned (per-process truth) — expected for sessions resumed under another alias and for non-Claude agents |
| entity `[stale]` | `labelctl.sh get --id X --json \| jq '.updated_at,.pid'` | owner stopped heartbeating and pid dead; a heartbeat revives it |
| state dir unusable | `labelctl.sh verify`; check `LABEL_SYNC_DIR` perms (0700) | exit 2: fix the dir; nothing is guessed |
| MCP tools return `isError` "cannot determine" | same state dir check | the server stays up; fix the dir, retry |
| adapter never registers | `LABEL_SYNC_ADAPTER_DEBUG=1`, read `$LABEL_SYNC_DIR/adapters/debug.log` | see `docs/label-sync/ADAPTERS.md` per agent |
| kill switch | `LABEL_SYNC_DISABLE=1` | every hook/adapter becomes a silent no-op |

Rebuild the binaries: `bash scripts/label-sync/labelctl.sh --build` (also automatic when sources are newer).
