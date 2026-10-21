# label-sync

| Field | Value |
|---|---|
| Document | `docs/label-sync/README.md` |
| Revision | 5 (2026-10-15) |
| Anchors | §11.4.182, §11.4.116, §11.4.233, §11.4.18 |

Real-time label + alias synchronisation for every stream, agent, subagent,
shell, command and flow. The data contract is `CONTRACT.md` (read it first);
this file is the operator quick-start.

## Layout

```
scripts/label-sync/
  labelctl.sh              build-if-stale wrapper (bash entry point)
  cmd/labelctl             CLI client
  cmd/label-busd           daemon: reconcile loop + push socket + single-instance lock
  internal/model           wire types
  internal/state           bounded flock + compacted event log + offset index + atomic snapshot (crash safe)
  internal/bus             seq-poll subscribe + one-hub unix-socket fan-out (short-path fallback via bus.addr)
  internal/label           §11.4.182 compose / validate / sanitise / derive-via-labeler
  prove_mutations.sh       paired-mutation proof (59 mutants against a scratch copy; a kill needs a `--- FAIL:` line, a non-compiling mutant is UNDETERMINED and fails the proof)
scripts/label-sync/render/   renderers (statusline, title, shell integration, labelrun, …) — see RENDERERS.md
scripts/gates/cm_label_sync_core.sh (+ _mutation_test.sh)   gate
```

## Quick start

```bash
export LABEL_SYNC_DIR=$(mktemp -d)          # tests: always a temp dir
L=scripts/label-sync/labelctl.sh
$L busd &                                   # optional daemon
$L switch-alias --alias claude2 --model sonnet --effort xhigh
$L register --id sh1 --kind shell --derive --pid $$   # prints the label; pinned when CLAUDE_CONFIG_DIR names an alias
$L list --text
$L watch --text                             # live; --socket uses the daemon
$L verify                                   # exit 0 ok / 1 problem / 2 cannot determine
```

Key semantics (details in CONTRACT.md): bindings are DERIVED at render time —
a child shows its session's alias, a pinned session/terminal keeps its own
alias through every `switch-alias`, only alias-less roots follow the active
context. Writers wait at most `--lock-timeout` (default 2 s, exit 2 on
timeout). Without `label-busd`, `snapshot.json`'s `stale` flag only refreshes
on the next write — use `labelctl list/get` for live staleness.

## Tests and proofs

```bash
cd scripts/label-sync && nice go test -race -p 2 ./...
bash scripts/label-sync/prove_mutations.sh          # every mutant must be killed
bash scripts/gates/cm_label_sync_core.sh                 # exit 2 when go/grep absent
LABEL_SYNC_PERF=1 go test -run TestPerfLogGrowth -v ./internal/state/   # 10k/100k event timings
```

Host notes: builds/tests are stdlib-only (`GOPROXY=off` works). Run heavy jobs
niced and one at a time on a loaded host (§12.6/§12.7).

## Not in the CORE stream

Hook wiring (SessionStart/PreToolUse), registry bridges (§11.4.147/§11.4.208) and
`install` auto-wiring (§11.4.164/228) consume this contract and are built by other
streams. The statusLine / terminal-title / shell / tmux / `labelrun` / live-watch
RENDERERS are documented in [`RENDERERS.md`](RENDERERS.md). The review-2 fix
round (findings, fix commits, RED evidence, mutants) is in
[`REVIEW-FIXES.md`](REVIEW-FIXES.md).
