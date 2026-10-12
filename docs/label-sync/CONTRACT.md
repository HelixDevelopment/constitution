# label-sync data contract

| Field | Value |
|---|---|
| Document | `docs/label-sync/CONTRACT.md` |
| Revision | 1 (2026-10-12) |
| Status | CORE implemented and tested on branch `feature/label-sync` (local, unpushed) |
| Implements | §11.4.182 (label), §11.4.116 (event stream + atomic status snapshot), §11.4.233 (level-triggered reconcile) |
| Code | `scripts/label-sync/` (Go, stdlib only) + `scripts/label-sync/labelctl.sh` |

Other streams (hooks, statusline, multitrack registry, agent dispatch) build on
this document. Where this file and the code disagree, the code's tests win and
this file is a defect — report it.

## 1. State directory

`${LABEL_SYNC_DIR:-$HOME/.local/state/constitution-label-sync}` (mode 0700). All
files 0600. Tests MUST set `LABEL_SYNC_DIR` to a temp dir.

| File | Writer | Semantics |
|---|---|---|
| `events.jsonl` | any (under flock) | Append-only SOURCE OF TRUTH. One JSON `Event` per line, `seq` strictly increasing. |
| `fold.json` | any (under flock) | INTERNAL declared state (rebuildable from the log; do not read). |
| `snapshot.json` | any (under flock) | Rendered view (§2.3) — what consumers read. Atomically replaced (write-temp-then-rename in the same dir + fsync). Never torn. |
| `active.json` | any (under flock) | The operator's ACTIVE context `{alias, model, effort, switched_at, seq}`. Atomic. |
| `seq` | any (under flock) | Decimal head sequence + `\n`. Written LAST, atomically: a reader that sees `N` can read a snapshot at `seq >= N`. |
| `lock` | — | flock(2) target serialising writers. |
| `busd.lock`, `busd.pid`, `bus.sock` | `label-busd` | Single-instance flock, pid, optional push socket (0600). Absent when the daemon is down. |

Crash safety: a torn final line of `events.jsonl` is tolerated by every reader
and truncated away by the next writer (it was never acknowledged). A missing or
corrupt `fold.json`/`snapshot.json` is rebuilt from the log. An event durably
appended but not yet folded is caught up by readers and by the next writer.
Corruption of a non-final log line is reported by `labelctl verify` (exit 1).

## 2. Schemas

### 2.1 Entity

```
id            string   unique, caller-chosen, stable for the life of the thing
kind          string   session | agent | subagent | stream | shell | command | flow
parent_id     string   id of the parent entity ("" = root)
session_id    string   Claude session id this belongs to ("" = unknown)
pid           int      OS process id (0 = none/unknown); only meaningful on `host`
host          string   defaults to the registering host
cwd           string
track         string   digits only ("3"), "" = unknown ('?')
branch        string   "" = unknown ('?')
alias         string   claude1, claude2, prov-*, ... ("" = unknown)
model         string   opus|sonnet|haiku|fable|<provider model>|"" unknown
effort        string   low|medium|high|xhigh|max|"" unknown
follow_active bool     see §4
source        string   who reported it (hook name, script, agent)
started_at    RFC3339  first registration (kept on re-register)
updated_at    RFC3339  last register/update/heartbeat/unregister
label         string   COMPUTED (§5), always (T<N>/<branch> - <alias> - <model> - <effort>)
state         string   running | idle | done | unknown (rendered; see §6)
stale         bool     COMPUTED (§6); omitted when false
```

In `snapshot.json` the `alias/model/effort/track/branch` of an entity are the
EFFECTIVE (rendered) values, i.e. already resolved per §4 — consumers never
re-implement resolution; they print `label`.

### 2.2 Event (`events.jsonl`)

`{"seq":N,"ts":RFC3339,"type":T, ...}` where `type` is:

| type | payload | effect |
|---|---|---|
| `register` | `entity` | create/replace entity; republishes the subtree if a non-following session (§4.3) |
| `update` | `id`, `patch` (string map) | change only the keys given. Keys: `parent_id session_id pid host cwd track branch alias model effort follow_active source state kind` |
| `heartbeat` | `id` [`patch`] | `updated_at=now`; `unknown`→`running` unless `state` given |
| `unregister` | `id` | `state=done` (kept for retention, §6) |
| `alias_switch` | `active{alias,model,effort}` | set `active.json` (§4) |
| `reap` | `id` | delete the entity from the declared state |
| `reconcile` | — | no-op that bumps `seq` so watchers re-read after a time-driven change |

A rejected event (unknown id, bad kind/state/pid/key, empty alias on switch) is
NOT logged; the writer gets an error (`labelctl` exit 1).

### 2.3 Snapshot

`{"seq":N,"generated_at":RFC3339,"active":{...},"entities":[Entity...]}` sorted
by `(started_at, id)`.

## 3. Real-time transport (decision and justification)

**Primary: the `seq` file, polled.** A consumer remembers the last `seq`,
reads the tiny `seq` file every 100-250 ms, and on change re-reads
`snapshot.json` (state) or reads `events.jsonl` lines with `seq > last`
(stream). Why: (a) works from plain bash (`cat`, `jq`) with no client library;
(b) works with the daemon down — writers never depend on it; (c) atomic-rename
makes the read side lock-free; (d) no inotify (Go stdlib has none) and no
network. Cost: up to one poll interval of latency (measured propagation in Go
tests: well under 1 s with 20 ms polls).

**Optional accelerator: `bus.sock`** (unix, 0600), served by `label-busd`.
Protocol: client sends `{"since":N}\n` (`N=18446744073709551615` = "from now");
server replies `{"hello":true,"seq":N}\n`, then streams Event JSON lines. The
daemon fans out by polling `seq` every 50 ms. Go consumers use
`internal/bus.Dial`; `labelctl watch --socket`. Absence of the socket is never
an error for correctness; subscribers fall back to polling.

Bash example (all labels, live):

```bash
last=0; while sleep 0.2; do s=$(cat "$LABEL_SYNC_DIR/seq" 2>/dev/null || echo 0)
  [ "$s" != "$last" ] && { last=$s; jq -r '.entities[]|"\(.id)\t\(.label)"' "$LABEL_SYNC_DIR/snapshot.json"; }; done
```

## 4. Alias-switch semantics (precise)

### 4.1 `alias_switch`
`labelctl switch-alias --alias A [--model M] [--effort E]` sets `active.json` to
`{A, M, E}`. Unspecified model/effort are stored empty and render as `?` —
a switch never invents a model or effort (§11.4.6). The very next snapshot
(same write transaction) re-renders every follower; there is no separate
propagation step.

### 4.2 Who follows
Resolution of an entity's displayed `alias/model/effort`:

1. `follow_active == true` → the ACTIVE triple (its own stored alias/model/effort are ignored). If nothing is active yet: `? - ? - ?`.
2. else, if the entity has its own `alias` → its own triple.
3. else the nearest ancestor (by `parent_id`, max depth 32) that is non-following and has an alias → that ancestor's triple (per-process truth inherited by children).
4. else unknown (`?`).

`track` and `branch`, when empty, are inherited from the nearest ancestor that
has them (real data from the parent, not a guess).

**Defaults.** `labelctl register` sets `follow_active=true`, except that with
`--derive` an entity whose derived alias DIFFERS from the active alias (or when
no alias is active yet) is registered `follow_active=false`: its process env
(`CLAUDE_CONFIG_DIR`) names another alias, and per-process truth wins. An
entity whose derived alias equals the active alias follows, so an operator
switch relabels it.

### 4.3 SessionStart under a different alias (subtree republish)
When a `kind=session` entity is registered/updated with `follow_active=false`
and an `alias`, EVERY entity in its subtree — same non-empty `session_id`, plus
all `parent_id` descendants, transitively — is rewritten to `follow_active=false`
with the session's alias/model/effort. Result: that whole subtree keeps showing
the session's alias across later operator switches; unrelated sessions keep
following. Re-registering the session under yet another alias republishes again.

## 5. Label computation

* Derivation from a live process is DELEGATED to
  `scripts/multitrack/track_branch_label.sh` (`labelctl register --derive
  [--cwd D] [--config-dir C]`, Go `label.Derive`). Derived `?` fields are stored
  as unknown; explicit flags override derived values. A failing/absent labeler
  is exit 2 — nothing is guessed.
* Rendering composes the 5-field form from the effective fields with `?` for
  every unknown (`label.Compose`). Characters that would break the grammar
  (`)`, newline, ` - `) in a field are replaced by `_`.
* Validation (`label.Validate`): the `(T<N>|T?/<branch> - <alias> [- <model> [- <effort>]])`
  family accepted by `guard-track-branch-label.sh` (3/4/5 fields), additionally
  rejecting empty or space-padded fields. `label.ValidateFull`: exactly 5 fields.

## 6. Staleness and retention

* TTL default 120 s (`LABEL_SYNC_TTL`, Go duration or seconds).
* An entity is **stale** iff `state != done` AND `now - updated_at > TTL` AND no
  provably alive local process (`host` empty or equal to this host, `pid>0`,
  `kill(pid,0)` ok/EPERM). Remote-host and pid-less entities cannot be proven
  alive and go stale on TTL alone. Stale entities render `state=unknown`,
  `stale=true`; the label stays grammar-valid (text mode appends `[stale]`).
  They are NEVER deleted by staleness. A `heartbeat` revives them.
* `done` entities are removed by `label-busd` reconcile (`reap` event) after
  `LABEL_SYNC_DONE_RETENTION` (default 300 s).
* Reconcile is level-triggered and idempotent: when the rendered view differs
  from the published `snapshot.json` (an entity just went stale) it appends a
  `reconcile` event so `seq` moves and watchers refresh.
* Known limit (UNCONFIRMED mitigation): pid reuse can keep a dead entity
  looking alive; heartbeat discipline bounds the effect.

## 7. CLI (`labelctl`) and exit codes

`register update heartbeat unregister reap switch-alias get list snapshot watch
verify label` — see `labelctl --help`. `register` prints the entity's rendered
label on stdout. **Exit codes: 0 ok; 1 finding/invalid (unknown id, bad input,
verify problem); 2 cannot determine (state dir unusable, labeler missing, no go
toolchain, usage error). 2 is never a pass.** `labelctl.sh` builds the Go
binaries on demand and execs them (`labelctl.sh busd` runs the daemon).
