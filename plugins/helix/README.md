# `helix` — Claude Code plugin (action directives + commands)

**GENERATED** by `scripts/generate_agent_prefix_commands.sh` from `actions/registry.yaml`.
DO NOT EDIT BY HAND — add a registry row and re-run the generator.

Every registered §11.4.140 action is exposed as a Claude Code slash command.

| Invoke | Always-unambiguous form | What it does |
|---|---|---|
| `/background` | `/helix:background` · `/default-background` | Run the remainder of the prompt as a DURABLE (never-lost), background, subagent-driven work stream in parallel with all main work, producing rock-solid physical proof. |
| `/reminder` | `/helix:reminder` · `/default-reminder` | Re-surface previously-scheduled, critical, status-UNCERTAIN work; verify actual status from captured evidence before acting (never assume done). |
| `/critical` | `/helix:critical` · `/default-critical` | Tag the remainder of the prompt HIGHEST-PRIORITY / potentially release-blocking — address with maximum urgency + rigor, track it, and do not defer it behind lower-priority work. |
| `/important` | `/helix:important` · `/default-important` | Tag the remainder of the prompt HIGH-PRIORITY — prioritize it above routine work (but below a CRITICAL / release-blocking matter), track it, and apply full anti-bluff rigor. |
| `/note` | `/helix:note` · `/default-note` | Capture the remainder of the prompt as durable CONTEXT / a note to remember (request-history + persistent memory), applied when relevant — not an urgent action unless it contains an explicit action. |
| `/helix:bug` | `/bug` **COLLIDES** with host `bug` → use `/helix:bug` or `/default-bug` | Report a product DEFECT — create a fully-populated Type=Bug workable item and drive the full DB → docs → external-tracker sync. |
| `/task` | `/helix:task` · `/default-task` | Report an internal WORKSTREAM item — create a fully-populated Type=Task workable item and drive the full DB → docs → external-tracker sync. |
| `/issue` | `/helix:issue` · `/default-issue` | Report ANYTHING trackable — classify into the §11.4.16 closed set {Bug \| Feature \| Task}, then create the fully-populated, fully-synced item. |
| `/feature` | `/helix:feature` · `/default-feature` | SCHEDULE (never synchronously run) a deep, enterprise-grade research + implementation-planning effort on a described feature as a tracked workable item — the multi-day research itself is performed later by the autonomous loop, not by this directive. |
| `/jev_bootstrap` | `/helix:jev_bootstrap` · `/default-jev_bootstrap` | Run the Jev decision-layer bootstrap wizard: detect decision models, provision llmctl + claude_toolkit, wire every detected agent, start shadow calibration (§11.4.279–§11.4.286). |
| `/jev_status` | `/helix:jev_status` · `/default-jev_status` | Show decision-layer status: detected endpoints, per-agent wiring, mode (shadow/enforce), calibrated thresholds, pending bootstrap stamp, and the jev-stats savings summary. |

## Conflict rule (§11.4.140)

A bare `/<name>` is honored ONLY when it does not collide with a host built-in
(declared as data in the registry `slash_conflicts:` field). The plugin-namespaced
`/helix:<name>` is ALWAYS unambiguous — Claude Code plugin namespacing IS the
§11.4.140 form-4 `PREFIX::ACTION` escape. `/default-<name>` is a third,
collision-free form that works identically on every supported CLI agent.

The plugin NEVER silently shadows a host command: on a collision Claude Code
resolves the bare name to its own built-in, and the colliding command file says so.

Install: see `docs/actions/QUICKSTART_INSTALL.md` (one command, or fully automatic
on every constitution pull via `scripts/post_update_hook.sh` per §11.4.164).
