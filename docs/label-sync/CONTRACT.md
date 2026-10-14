# label-sync data contract

| Field | Value |
|---|---|
| Document | `docs/label-sync/CONTRACT.md` |
| Revision | 3 (2026-10-14) — review-2 fixes: stale sweeper (§6), explicit alias pins (§4.2), bus.addr only after bind + busd exit 3 + hello limit (§1, §3), pid range + patch ids (§2.1, §7), per-checkout binary cache (§7), same-user trust boundary (§8). Revision 2 (2026-10-12) — FIX-A: derived binding, sanitising, compaction, pid start-time, bounded lock, socket fallback |
| Status | CORE implemented and tested on branch `feature/label-sync` (local, unpushed) |
| Implements | §11.4.182 (label), §11.4.116 (event stream + atomic status snapshot), §11.4.233 (level-triggered reconcile) |
| Code | `scripts/label-sync/` (Go, stdlib only) + `scripts/label-sync/labelctl.sh` |

Other streams (hooks, statusline, multitrack registry, agent dispatch) build on
this document. Where this file and the code disagree, the code's tests win and
this file is a defect — report it.

## 1. State directory

`${LABEL_SYNC_DIR:-$HOME/.local/state/constitution-label-sync}`. Every `Open`
forces the directory to mode 0700 (even when it already existed) and REFUSES a
directory owned by another uid. Files are 0600. Orphaned `.*.tmp-*` files (a
writer killed mid-write) older than 60 s are removed at open; younger ones are
left alone because a concurrent writer may own them. Tests MUST set
`LABEL_SYNC_DIR` to a temp dir.

| File | Writer | Semantics |
|---|---|---|
| `events.jsonl` | any (under flock) | Append-only SOURCE OF TRUTH from `base.json` onward. One JSON `Event` per line, `seq` strictly increasing. Compacted (§1.2). |
| `base.json` | compaction (under flock) | Authoritative folded state at `seq = B`; the log holds `B+1..head`. Absent until the first compaction (B = 0). |
| `fold.json` | any (under flock) | INTERNAL cache: declared state at head + `index{ino,off,events,base_seq}` locating it in `events.jsonl`, so readers parse only newer events. Rebuildable; do not read. |
| `snapshot.json` | any (under flock) | Rendered view (§2.3) — what consumers read. Write-temp-fsync-rename + dir fsync. Never torn. |
| `active.json` | any (under flock) | The operator's ACTIVE context `{alias, model, effort, switched_at, seq}`. Atomic. |
| `seq` | any (under flock) | Decimal head sequence + `\n`. Written LAST: a reader that sees `N` can read a snapshot at `seq >= N` (enforced by a test that checks the files after every persist step). |
| `lock` | — | flock(2) target serialising writers. Acquisition is bounded (§7). |
| `compact.failed` | any | Present only while the last compaction failed AND the log is still over its bound; `verify` reports it. |
| `busd.lock`, `busd.pid` | `label-busd` | Single-instance flock and pid. |
| `bus.sock` / `bus.addr` | `label-busd` | Push socket (0600 from birth: created under umask 0177). When `<dir>/bus.sock` would exceed 100 bytes the socket lives in a 0700 private dir (`$XDG_RUNTIME_DIR/ls-<hash>/`, else `$TMPDIR/ls-<uid>-<hash>/`, else `/tmp/ls-<uid>-<hash>/`) and its path is recorded in `bus.addr`; clients use `bus.ResolveSocket(dir)`. |

**`label-busd` leftovers.** A CLEAN shutdown (SIGINT/SIGTERM) removes
`busd.pid`, `bus.sock`, `bus.addr` and an empty fallback dir. A `kill -9`
leaves `busd.pid`, `bus.sock` (and `bus.addr`) behind: they are stale, not
live — the next daemon replaces the stale socket (it first probes it; a LIVE
socket makes it refuse) and rewrites the pid file; the flock on `busd.lock` is
the only single-instance truth. Never treat `busd.pid` as proof a daemon runs.
**Ordering (review-2 finding 6):** the daemon binds the socket FIRST and writes
`bus.addr` only after a successful bind, so a client that reads `bus.addr` can
always dial; a stale `bus.addr` is removed at start and none is left when the
bind fails (the daemon then runs the reconcile loop only and says so).
`label-busd` exit codes: **0** clean shutdown, **2** cannot start (state dir
unusable, usage), **3** another instance already holds `busd.lock` (the daemon
is already up — not an error of this invocation). Exit 1 is not used.

Crash safety: a torn final line of `events.jsonl` is tolerated by every reader
and truncated away by the next writer (it was never acknowledged). A missing or
corrupt `fold.json`/`snapshot.json` is rebuilt from `base.json` + log. An event
durably appended but not yet folded is caught up by readers and by the next
writer. Corruption of a non-final log line is reported by `labelctl verify`
(exit 1) and blocks compaction (compaction never silently discards it).

### 1.2 Compaction

Under the writer lock, when the log holds more than `LABEL_SYNC_COMPACT_EVENTS`
(default 5000) events or `LABEL_SYNC_COMPACT_BYTES` (default 2 MiB), all but the
last 256 events are folded into `base.json`. Steps, each atomic + fsynced:
(1) write `base.json` at seq B (log still complete); (2) replace
`events.jsonl` by the tail `B+1..head`; (3) rewrite `fold.json`. A `kill -9`
between any two steps is recoverable (a reader skips log events `<= B`; a read
that raced the rotation is retried) — tested by injecting a crash at every
step. `seq` never moves backwards. A legacy uncompacted log is compacted by the
first write (one-time cost measured at ~0.1 s for 10k, ~1.1 s for 100k events).
A subscriber whose `since` predates the horizon receives ONE synthetic
`reconcile` event at seq B, then the retained tail: it must re-read
`snapshot.json`.

## 2. Schemas

### 2.1 Entity

```
id            string   unique, caller-chosen, stable for the life of the thing
kind          string   session | agent | subagent | stream | shell | command | flow
parent_id     string   id of the parent entity ("" = root)
session_id    string   Claude session id this belongs to ("" = unknown)
pid           int      OS process id (0 = none/unknown); only meaningful on `host`
pid_start     string   "<boot_id>:<starttime>" of pid, recorded by the store at register/pid change (§6)
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
binding       string   COMPUTED (§4): own | inherited:<ancestor id> | active | unknown
```

**Ids** (`id`, `parent_id`, `session_id`) must match `^[A-Za-z0-9._:@/-]{1,160}$`;
anything else is rejected (`labelctl` exit 1, store error). **Free text**
(`track branch alias model effort source host cwd`, the active triple) is
SANITISED before it is logged: C0 controls (incl. ESC, NUL, BEL), DEL, C1
controls (U+0080–U+009F), bidi embeddings/overrides/isolates/marks and invalid
UTF-8 bytes are removed; fields are capped at 128 runes (`host` 255, `cwd`
4096). Rendering sanitises again (defence in depth for old logs) and every
byte `labelctl` prints passes the same filter, so no field value can drive the
operator's terminal (OSC title/clipboard, CSI, C1) under any locale.

In `snapshot.json` the `alias/model/effort/track/branch` of an entity are the
EFFECTIVE (rendered) values, i.e. already resolved per §4 — consumers never
re-implement resolution; they print `label`.

### 2.2 Event (`events.jsonl`)

`{"seq":N,"ts":RFC3339,"type":T, ...}` where `type` is:

| type | payload | effect |
|---|---|---|
| `register` | `entity` | create/replace entity (started_at kept). Writes ONLY that entity — bindings are derived (§4) |
| `update` | `id`, `patch` (string map) | change only the keys given; an EMPTY value clears a field (`labelctl update --clear k1,k2`). Keys: `parent_id session_id pid pid_start host cwd track branch alias model effort follow_active source state kind` |
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
Protocol: client sends `{"since":N}\n` (`N=18446744073709551615` = "from now";
the hello line is read through a 4096-byte limit — a longer line, or none
within 2 s, closes the connection);
server replies `{"hello":true,"seq":N}\n`, then streams Event JSON lines. The
daemon polls `seq` every 50 ms from ONE shared subscription (a hub with a
1024-event ring) and fans out to every client, so log reads do not scale with
the number of clients; a client more than 1024 events behind is disconnected
and may resubscribe with its last seq. Go consumers use
`bus.Dial(ctx, bus.ResolveSocket(dir), since)`; `labelctl watch --socket`.
Absence of the socket is never an error for correctness; subscribers fall back
to polling. `EventsSince` reads `events.jsonl` backwards from its end only as
far as needed (a poller one event behind reads one chunk).

**Staleness bound for file readers (bash `jq` on `snapshot.json`).** The
`stale`/`state=unknown` fields in `snapshot.json` are computed when the file is
written. With `label-busd` UP, a TTL expiry is published within its reconcile
interval (1 s) + one poll. With `label-busd` DOWN, `snapshot.json` keeps showing
an expired entity as live until the NEXT write by anyone — there is NO time
bound. Readers needing live staleness without the daemon must use
`labelctl get/list/label` (or Go `Store.Snapshot`), which compute it at read
time. Writers reap past-retention `done` entities on every write, so the
snapshot stays bounded even without the daemon.

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

### 4.2 Binding rule — DERIVED, never copied

An entity's displayed `alias/model/effort` is resolved at RENDER time:

1. **Pinned** (`follow_active == false` AND own non-empty `alias`) → its own
   triple (`binding: own`).
2. Else its **nearest ancestor's binding, resolved by this same rule**
   (`binding: inherited:<id>` when it ends at a pinned ancestor). The nearest
   ancestor is the `parent_id` entity when it exists, else — for non-session
   entities — the `kind=session` entity with the same `session_id`. Depth ≤ 32,
   cycles tolerated.
3. A **root** (no ancestor) that follows → the ACTIVE context
   (`binding: active`); nothing active yet → `? - ? - ?`.
4. A root that neither follows nor has an alias → unknown (`?`).

Consequences: a child of a pinned session shows the session's alias whatever
the child's own `follow_active`; a child of a FOLLOWING session follows the
active context THROUGH the session (a following ancestor's stale stored alias
never leaks); re-registering or updating a session changes every descendant
immediately with NO write to them; two sessions pinned to different aliases
never cross-contaminate through any number of `alias_switch` events (tested
over randomised sequences). A child can still pin itself (own alias +
`follow_active=false`).

`track` and `branch`, when empty, are inherited along the same ancestor chain
(real data from the parent, not a guess).

**Defaults.** `labelctl register` sets `follow_active=true` for an ALIAS-LESS
entity. An EXPLICIT `--alias` (labelctl `register`/`update`, MCP
`label_register`) pins it (`follow_active=false`) unless `--follow-active` /
`follow_active` is given explicitly (review-2 finding 4: the explicit triple
used to be ignored and the entity followed ACTIVE). With `--derive`,
an alias DERIVED from the process (the canonical labeler reads it from
`CLAUDE_CONFIG_DIR`) PINS the entity (`follow_active=false`) unless
`--follow-active` is given: per-process truth wins, so two terminals on
different aliases each keep their own. Only alias-less roots follow the active
context. No read of `active.json` happens during `register`, so there is no
check-then-act window (the previous implementation's TOCTOU is gone).

### 4.3 Session resumed under another alias

Re-register (or `update --alias`) the session with the new alias: rule 4.2
rebinds its whole subtree on the next render. Re-register it with
`--follow-active true` (no alias) to make the subtree follow the active
context again. Nothing else needs touching; there is no republish step and no
child is ever left pinned by a past session binding.

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
* An entity is **stale** iff `state != done` AND `now - updated_at > TTL`
  (strictly greater; age == TTL is not stale) AND no provably alive local
  process. "Provably alive" (`host` empty or this host, `pid > 0`): on Linux
  `/proc/<pid>/stat` exists AND, when `pid_start` was recorded, its starttime
  (field 22) plus `/proc/sys/kernel/random/boot_id` equals `pid_start` — a
  RECYCLED pid is not alive. Without `/proc`, `kill(pid,0) == nil` counts only
  for entities with no recorded `pid_start`; EPERM never counts. Remote-host and
  pid-less entities go stale on TTL alone. Stale entities render
  `state=unknown`, `stale=true`; the label stays grammar-valid (text mode
  appends `[stale]`). They are NEVER deleted by staleness. A `heartbeat` revives
  them (and turns a declared `unknown` back to `running` unless it carries a
  state).
* `done` entities are reaped (`reap` event) after `LABEL_SYNC_DONE_RETENTION`
  (default 300 s) by EVERY writer and by `label-busd`'s reconcile, so the
  snapshot is bounded by (done rate × retention) even with the daemon down.
* **Stale sweeper (review-2 finding 7).** `kill -9` / power-cycle leftovers
  used to stay forever (2000 of them: write cost 17-22 ms -> 65-83 ms, snapshot
  695 KB, inside the 500 ms hook lock bound). Every writer and the reconcile
  loop now REMOVE (a logged `reap` event, so compaction and replay stay
  consistent) an entity that is not `done`, is local (`host` empty or this
  host), has a recorded `pid > 0` whose process is provably gone by the same
  rule as staleness (pid + start identity), and has not been updated for
  `LABEL_SYNC_STALE_SWEEP` (Go duration or seconds; default **15m**; `off`
  disables). Pid-less and remote entities are never swept (their liveness
  cannot be proven): they stay `[stale]`. A live process is never swept; a
  RECYCLED pid with a recorded start identity is not "alive". At most
  `LABEL_SYNC_SWEEP_BATCH` (default 256) entities go per transaction, appended
  with ONE fsync, so the lock hold stays bounded; later writes continue the
  sweep. Measured (`TestStaleSweeperRestoresWriteCost`): 2000 leftovers —
  write 76 ms, snapshot 900 KB; the sweeping write 31 ms; afterwards 13.9 ms
  and 195 B (empty store 13.4 ms).
* Reconcile is level-triggered and idempotent: when the rendered view differs
  from the published `snapshot.json` (an entity just went stale) it appends a
  `reconcile` event so `seq` moves and watchers refresh. Staleness bound for
  file readers: §3.

## 7. CLI (`labelctl`) and exit codes

`register update heartbeat unregister reap switch-alias get list snapshot watch
verify label` — see `labelctl --help`. Global flags before the command:
`--dir D`, `--lock-timeout D` (env `LABEL_SYNC_LOCK_TIMEOUT`, default 2 s; Go
duration or seconds). `register` prints the entity's rendered label on stdout.
`update --clear k1,k2` clears fields (`parent session pid host cwd track branch
alias model effort source`). Every printed byte is sanitised (§2.1).
`--pid` must be 0..4194304 (Linux PID_MAX_LIMIT); anything else is exit 1
(also rejected by the store for register and update patches). A patch's
`parent_id` / `session_id` is validated against the id grammar by the store
itself (prepare) AND by the fold (replayed logs). `labelctl.sh` keeps its
binaries in a PER-CHECKOUT cache (`<cache>/constitution-label-sync/bin-<hash
of the module path>`, `bincache.sh`) and treats them as stale when the git
HEAD differs from the `.source-commit` recorded at build — one shared cache
used to let checkout A run checkout B's binary (review-2 finding 13).
`LABEL_SYNC_BIN` still overrides.

**Writer lock.** Writers wait at most the lock timeout (a blocking flock in a
helper goroutine, so waiters are kernel-queued, not sleep-polled); on timeout
the write is NOT performed and `labelctl` exits **2** with `state lock busy`.
No child process is involved, so nothing is left behind. Readers never take
the lock. Hooks should pass a short bound (e.g. `--lock-timeout 500ms`). **Exit codes: 0 ok; 1 finding/invalid (unknown id, invalid id, bad input,
verify problem); 2 cannot determine (state dir unusable or foreign-owned, lock
timeout, labeler missing, no go toolchain, usage error). 2 is never a pass.** `labelctl.sh` builds the Go
binaries on demand and execs them (`labelctl.sh busd` runs the daemon).

## 8. Trust boundary: same-user spoofing (honest limit, §11.4.6)

The state directory is `0700` and every file `0600`; the push socket is `0600`
and PUSH-ONLY (a client can subscribe, it cannot write through it). That
protects the bus from OTHER users. It does NOT protect it from processes of
the SAME user: any of them can run `labelctl`, append events, register an
entity with any id, alias or pid, switch the active alias, or rewrite the
files directly. Labels are therefore a coordination signal between
cooperating agents of one operator, never an authentication or authorisation
mechanism, and must not be used to gate anything security-relevant. The pid +
start identity proves only that the RECORDED process is alive, not that it is
the process that wrote the entity.

