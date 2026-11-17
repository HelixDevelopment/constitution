# Round 5 ground truth: the `llmctl capacity --json` answer (§11.4.276(B))

| Field | Value |
|---|---|
| Item | CON-299, round 5 of R_max 5 (structural round, §11.4.276(E)) |
| Why | Round-4 review finding R4-2: the placement producer `scripts/jev/jev-place.sh` and its S4 stub shared a capacity model (unit status `running`/`active`, a `fits` verdict for a running profile) that the pinned llmctl never emits. That is wrong-layer evidence (§11.4.226). |
| Source read | the pinned llmctl commit `391d8177650bdb7eb2a94107a755c733d6ea4a2f` (gitlink of `submodules/llmctl`), read with `git archive` from a local object store; files `lib/capacity.sh` (sha256 `47d84f34e99269b3996a35363d0798d12ddffe05a318046a8100fe55622d1b55`), `docs/capacity.md` (sha256 `e0d7770f4f0f8c20a0ce9d22ffd77c28ca3ceacb3eb9bcdfa705a13f9cb2be79`), `bin/llmctl` (sha256 `a3c93a91f8a14eab8009219e77cbc78a36935dae0f3227b7aea5ba336386c8e7`) |
| Canon read | `Constitution.md` §11.4.291(A) (line 12702) and (C) (contract table, lines 12706 to 12722) of this vehicle |
| Not done | The pinned llmctl was NOT run. No real `llmctl capacity --json` document was captured in this round. The model below is derived from reading the source; it is gate-logic ground truth, not live evidence (§11.4.289(C)(2)). |

## The answer, field by field

| Fact | Where it is stated |
|---|---|
| Every running llmctl engine unit is one entry of `llmctl.units[]` with `unit` (the systemd unit name, e.g. `llmctl-llama@decide-a.service`), `profile` (the instance key: the part after `@`, without `.service`), `base_profile`, `owner`, `status`, `reasons` | `lib/capacity.sh:39` (`_cap_unit_profile`), `:448-470`; `docs/capacity.md:193-196` |
| A unit's `status` is exactly `ok` or `degraded`: `"degraded" if reasons else "ok"`. No other value exists; `running`, `active`, `failed`, `starting` and `activating` never appear | `lib/capacity.sh:469`; `docs/capacity.md:194` |
| A unit is `degraded` when host pressure is present (every unit starts with `reasons = list(pressure)`), when it has no CPU limit, or when its memory is at 90% or more of its limit | `lib/capacity.sh:461-464`; `docs/capacity.md:240-241` |
| `owner` is `self` for this user's own units and `user-<uid>` / `system` / `other` for units that are only consumption | `lib/capacity.sh:453-455`; `docs/capacity.md:196, 369-370` |
| A profile is "running" only when THIS user's own unit instance is up: the unit's `profile` equals `<LLMCTL_TENANT_ID>--<p>` when a tenant is set, `<p>` otherwise, and `owner` is `self`. Another instance (`decide-a.2`) or another tenant's unit (`t1--decide-a`) is not "running" for `p` | `lib/capacity.sh:473-477, 503`; `docs/capacity.md:244-248` |
| For a running profile the verdict is `running` (whatever its reasons), `verdict_class` is `null`, `running` is `true`, `threads` is `0`, and `reasons` starts with `already running` | `lib/capacity.sh:503, 507-508, 530-534`; `docs/capacity.md:157` |
| For a profile that is not running the verdict is `fits`, `fits_with_reduced_threads` or `does_not_fit`; `threads` is the start thread count for a fit and `0` otherwise | `lib/capacity.sh:506, 529-534` |
| When the measurement fails or times out the whole document has `measurement.ok: false`, `null` host fields, every named profile `undetermined` | `lib/capacity.sh:199-214, 582-588`; `docs/capacity.md:249-250` |
| `degraded` (top level) is true when any unit is `degraded` | `lib/capacity.sh:622` |
| Exit status of `llmctl capacity --json` with no profile named (how jev-place calls it): `75` when `measurement.ok` is false, `3` when some unit is degraded, `0` otherwise | `lib/capacity.sh:634-642`; `bin/llmctl:256-258`; `docs/capacity.md:131-133` |
| `fallback.recommended` is `local` when a decide profile fits or an own decide unit is running and `ok` | `lib/capacity.sh:551-555`; `docs/capacity.md:251` |

Canon agrees: §11.4.291(A) "llmctl also reports `running` for a profile that is already running: that is not a verdict for a start; the running instance is judged by its unit `status` (`ok` keeps it eligible for routing, `degraded` is treated as `does_not_fit` for that instance and triggers clause (D)(1))"; the (C) table lists the verdict set `fits` / `fits_with_reduced_threads` / `does_not_fit` / `running` and `llmctl.units[]` (`profile`, `status`, `reasons`).

## The behavioural model the producer and the stub now share

The producer classifies each candidate profile `p` into one instance state:

| State | When | What the producer does |
|---|---|---|
| `ok` | verdict `running`, and the own unit (owner `self`, or no `owner` field; `profile` = the tenant-keyed name of `p`) has status `ok` | join an existing lease set; adopt it as operator-started when there is no set; a lease-less constitution-started set is JOINED, never stopped |
| `degraded` | verdict `running` and that unit's status is `degraded` | `does_not_fit` for that instance: never joined or adopted; a lease-less constitution-started set is stopped (clause (D)(1)) |
| `absent` | verdict `fits`, `fits_with_reduced_threads` or `does_not_fit` and no own unit for `p` | a start candidate when the verdict is a fit and the producer's own checks (RLIMIT_NPROC headroom, pressure) pass; a lease-less constitution-started set whose unit is gone is dropped after a bounded stop |
| `unknown` | anything else: verdict `undetermined` or outside the set, verdict `running` with no own unit, an own unit next to a non-`running` verdict, a unit status outside `ok`/`degraded` | nothing is started, joined or stopped for `p`; it counts as undetermined |

The stub `tests/jev/fixtures/bin-place/llmctl` builds its answer with the same rules: a profile it "runs" becomes a unit `llmctl-llama@<key>.service` with `owner: self`, status `ok` (or `degraded` when the scenario says so or host pressure is present, as `lib/capacity.sh:461` does), and the profile verdict becomes `running` with `threads: 0` and `already running` first in its reasons; the exit status follows `capacity_exit_code` (75 / 3 / 0).

## What is still not modelled (UNCONFIRMED)

- The values of `headroom`, `inputs`, `host.psi`, `host.cgroup`: the producer records them but does not decide on them.
- `CAP_NEW_INSTANCES` / `CAP_REPLACE` (scale and restart): jev-place never names a profile, so they never apply.
- What the decide gateway does with a request for a model that is not running.
