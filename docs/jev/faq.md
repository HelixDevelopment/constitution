# Jev Decision Layer — FAQ

| Field | Value |
|---|---|
| Revision | 7 |
| Created | 2026-10-23 |
| Last modified | 2026-11-15T11:43:50Z |
| Status | active |
| Status summary | Short answers to recurring questions, each tied to the source that settles it. |
| Authority | Constitution §11.4.279–§11.4.286. The canonical anchor texts and the scripts govern where this document and they disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation; revision 2 adds question 23 (§11.4.291 placement); revision 4 adds questions 28 and 29 (placement freshness, round 7); revision 5 corrects question 23 (the capacity source is vendored); revision 7 adds questions 30 and 31 (round 9: one mark per stop, monotonic ages) |
| Fixed summary | — |
| Continuation | none |

Related: [governance guide](governance-guide.md) · [bootstrap reference](bootstrap-reference.md) · [diagrams](diagrams.md)

## Table of contents

- [General](#general)
- [Endpoints and models](#endpoints-and-models)
- [Safety and privacy](#safety-and-privacy)
- [Calibration and proof](#calibration-and-proof)
- [Bootstrap](#bootstrap)
- [Capacity and placement](#capacity-and-placement)
- [Default-on wiring and exit 5 (2026-11-12)](#default-on-wiring-and-exit-5-2026-11-12)
- [Placement freshness (2026-11-13)](#placement-freshness-2026-11-13)

## General

**1. Is the Jev layer a chat model or an alias?**
No. Decision endpoints are classified `decision` by the toolkit: they get no launchable alias and never appear in chat or provider configs (§11.4.284(D)).

**2. Does it block anything today?**
Only if `JEV_MODE=enforce`. The default is shadow: it logs and passes everything through.

**3. What happens if the decision service is down?**
Fail-open by default: the gate steps aside (asserts nothing) and logs `fallback` (`endpoint_error` or `timeout`). `JEV_GATE_FAIL=closed` denies instead. In enforce mode a deterministic pattern floor can still escalate known-destructive patterns to `ask`.

**4. Which MCP tools exist?**
`jev_ask`, `jev_models`, `jev_stats_summary`, `jev_recommend_tier`. `jev_recommend_tier` is advisory only: hooks cannot rewrite a subagent's model.

## Endpoints and models

**5. Which endpoints are supported?**
The local llmctl decide gateway (HTTPS, port 8095), LAN pins, OpenRouter and TypeSafe hosted. Source: claude_toolkit `scripts/providers/jev.json`.

**6. Which local models can the gateway serve?**
The `decide-*` profiles in llmctl's catalog: `decide-tiny`, `decide-2b`, `decide`, `decide-pro`, `decide-max`, `decide-nli`, and the native `decide-julia`, `decide-kev-08b`, `decide-kev-4b`, `decide-kev-9b`, `decide-laya`, `decide-lev`. Native ones need `LLMCTL_DECIDE_NATIVE=1`. Only validated profiles are served.

**7. Are Kev and Laya accurate?**
Unknown. llmctl records their accuracy as unverified and says some were not run live. Calibrate on your own data before enforcing.

**8. What about Verdict and Strands profiles?**
UNKNOWN. Neither appears in llmctl's catalog or docs at `f42bad6`.

**9. Why is the local URL `https://`?**
The llmctl gateway is HTTPS only, with a local CA and a mandatory bearer key. The toolkit gate sends the key only over `https://` and accepts a CA file through the operator's `JEV_CA_FILE` environment variable (a `ca_file` in the detection record is not trusted for keyed requests). A plain `http://127.0.0.1:8095` URL will not work.

**10. Why does a slow local model make the gate fall back?**
The gate's curl timeout is `JEV_GATE_TIMEOUT` (2 s). The gateway's own budget is `LLMCTL_DECIDE_TIMEOUT` (8 s, or 120 s when a CPU llama instance is served). Raise the gate timeout or use a faster profile.

## Safety and privacy

**11. What leaves my machine?**
With a hosted endpoint: the tool name and tool input (up to 12,000 characters), sent to that provider. With the local gateway: nothing leaves the host. The local log stores a 16-hex-character hash, never the text.

**12. Where do secrets go?**
Nowhere in this layer. Files and docs carry key variable NAMES (`LLMCTL_API_KEY`, `OPENROUTER_API_KEY`, `TYPESAFE_API_KEY`). The gate reads the value at call time and never puts it on a command line. One caveat in the toolkit (outside this repository, tracked upstream): `jev-setup.sh` writes the key VALUE as `TYPESAFE_API_KEY` / `JEV_API_KEY` into `<home>/.mcp.json` of every Claude home, the Kimi `mcp.json` and a third agent config, so treat those files as key-bearing (see the governance guide, key-handling section). This layer never backs such a file up.

**13. Can I disable it?**
Yes: `JEV_GATE=off` (recorded), shadow mode, the `.jev/bootstrap.disabled` marker, or `jev-setup.sh --uninstall`. Silent disabling is non-compliance.

## Calibration and proof

**14. Can I cite `jev-stats.sh` savings?**
No. They are estimates from constants. Only the §11.4.283 measured BEFORE/AFTER harness is proof.

**15. Why does calibration skip all my rows?**
Today's gate logs a hash and the literal question name `gate`; calibration needs question text, criteria and state text. The skip count is printed.

**16. Does calibration change the gate?**
Not directly: the gate does not read `jev-thresholds.json`. UNCONFIRMED whether any component bridges the two files.

**17. Why isn't the Jev answer shown to the labeling LLM?**
Showing it would anchor the label toward agreement and inflate the promotion statistic.

## Bootstrap

**18. Why did bootstrap say `pending-consent`?**
It found unwired agents and did not have permission to edit agent homes. Re-run with `--yes` after reading the audit lines.

**19. Why does a second run print `no-change` everywhere?**
By design: stage digests equal the stamp, nothing is rewritten. Stage 3 still probes each endpoint of the previous record once, because the answer is part of its digest; when an answer changed (for example credit was added) that stage runs again and the record is rewritten.

**20. Why does it want `jq`?**
JSON parsing; a second parser would fork the wire format. Without it the wizard stops with rc 2 and a pending stamp.

**21. Does bootstrap use the network?**
Not by default. Cloning or fetching llmctl/claude_toolkit needs `--allow-clone` (or `--yes`); the post-update hook runs without it, so a pull never triggers a clone.

**22. Does bootstrap run the tools' installers?**
Only with `--install-tools` (or a "y" at the prompt). They link into PATH and edit shell rc files.

## Capacity and placement

**23. My host is busy. Will a local decision model still start?**
Not unless it fits. (Update 2026-11-12: `scripts/jev/jev-place.sh` now reads `llmctl capacity --json` when the installed llmctl provides it; the paragraph below describes the rules it follows.) §11.4.291 gives each decision profile a placement verdict from the live host load with a reserve kept free; only `fits` (or `fits_with_reduced_threads`, started with the fewer threads llmctl reports) allows a start, or an explicit, recorded operator override of `undetermined`. Otherwise the route is `cloud` (the hosted endpoint, in shadow mode) when a non-placeholder key is present, or `none`, and you get a notice plus a `placement` entry in `jev-detection.json`. The constitution never runs `llmctl enable`. The live capacity source (`llmctl capacity --json`, schema `llmctl.capacity/1`, llmctl 3.4.0) is not vendored yet, so today the verdict is `undetermined` and no local model is started by automation (see the governance guide, "Capacity-aware placement"). (Correction 2026-11-13: the sentence about the capacity source is stale. The vendored llmctl (gitlink `391d8177`, 3.4.1) provides `llmctl capacity --json` and `scripts/jev/jev-place.sh` reads it. What still keeps automation from starting a local model is that no session calls `acquire` today; and a host whose `RLIMIT_NPROC` is unlimited gets `undetermined` (`nproc_unlimited`) until the operator decides whether that admits a start.)

## Default-on wiring and exit 5 (2026-11-12)

**24. Why did my constitution pull wire the Jev hook without asking?**
The operator decision of 2026-11-12 made consent a standing order: when a non-placeholder decision key is present, the post-update hook runs the bootstrap with `--default-on`, which wires the hook and MCP server at user level and logs it. Undo: claude_toolkit `jev-setup --uninstall`. Opt out for good: `touch ~/.config/jev/wiring.disabled` (or `JEV_WIRING=off`).

**25. Why does the bootstrap now exit 5?**
It found decision endpoints but is not serving: either none answered 2xx (no credit, refused key, rate limit, unreachable) or no agent is wired. Before this change it exited 0 and printed `ok` in that state.

**26. My key is real but OpenRouter is "not usable". Why?**
A real key and a usable endpoint are different facts. HTTP 402 means the account has no credit; it is recorded `no_credit`, never reachable.

**27. Are thresholds shared between endpoints?**
No longer only per question type: `jev-thresholds.json` also has `per_endpoint["<endpoint>|<model>"]`, and each group earns enforce on its own sample. Rows that do not say which endpoint answered are grouped as `unknown|unknown`.

## Placement freshness (2026-11-13)

**28. Why did `acquire` start nothing and say `stale_answer`?**
Another session changed the lease registry (started, stopped, joined or released a model) between this acquire's capacity read and its start, three times in a row. Since round 7 a start is decided only on a capacity answer read after the last registry change (the token is the registry's generation counter plus the sha256 of `leases.json`, checked at the plan and again at the start mark). A stale answer is read again; after three stale reads nothing is started and the route falls back. It means heavy contention, not a fault; the next acquire tries again.

**29. Why does a held model stay unrouted for a while after its starter died?**
Clearing a dead starter's mark sets the set's health to `pending` at the current observation counter (a floor): only an observation that begins after the clear may judge the set, so a capacity answer read before the start finished can never mark a running model gone. A live starter's mark is kept until the mark itself is older than `MARK_TTL` (the start/stop timeout + 2 s + retries × lock timeout + 30 s). The age counts from the mark's own `at`, stamped when the mark is written (round 8; up to round 7 it was stamped at the producer's process start, so a mark set late in a long acquire could be cleared while its starter was still running). Run `status` or the next `acquire` to observe the set.

**30. Why does `acquire` or `release` log `stop of <p> (...) not run at its turn: <reason>`?**
When one call has to stop several sets, each set is marked `stopping` and judged again under the lock immediately before its own `llmctl stop`, never at planning time (round 9, review R8-1). Up to round 8 every listed set got one mark written when the stops were planned, so the mark of a later set aged while the earlier stops ran and another session could clear the mark of a live stopper and join the set. Now a set that was joined, started, marked by another process, observed `ok` again (a disposal) or removed meanwhile is simply not stopped, and the reason is logged. That is not a failure: `release` exits 0 for it. A stop that returns rc 0 while the set holds a lease never deletes the set (`stopped_while_held` is recorded and the set is not routed until the next observation; when the unit is gone every lease is released as `endpoint_gone`). Gate-logic evidence only, `docs/qa/jev_s3s4_20261112/round9/`.

**31. Can a clock step (NTP) clear a live mark or reap a live lease?**
Not on a host with `/proc` (round 9, review R8-6). Every mark and lease heartbeat carries `mono` = `<boot id>:<uptime seconds>` next to the wall-clock `at` / `heartbeat_at`, and an age is judged on the monotonic difference when both records are from this boot. A record from another boot counts as expired; a record without `mono` (written by an older producer, or a host without `/proc`) is judged on wall time as before. While an acquire runs a bounded llmctl call, a lease whose holder is named by that process's live mark is not aged out. Gate-logic evidence only.
