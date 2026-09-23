---
name: Multitrack
description: Automatic multi-track ruler orchestration per §11.4.187 — one conductor session spawning, driving, resuming, monitoring and controlling per-track headless workers with per-subscription auth, rate-limit rebind and crash-resilient supervision. Use when working with parallel development tracks, per-track headless workers, or the multitrack orchestrator, supervisor and bootstrap.
version: 1.0.0
# --- HXC-159 F-13 superset fields (HelixCode builtin_skills REPL loader) ---
# Optional fields consumed ONLY by helix_code's internal regex-triggered REPL
# completion-prompt loader (markdown_skills.go). Other Agent-Skills-format
# consumers ignore unknown YAML keys. Carried forward verbatim from the
# pre-superset builtin_skills copy — never invented (§11.4.6).
triggers:
  - "(?i)^(?:how do i |how to )?(?:start|create|spin up|set up|begin)\\b.*\\bmultitrack\\b.*$"
  - "(?i)^.*\\bmultitrack\\b.*\\b(?:work ?stream|track|branch|worktree)s?\\b.*$"
requires_isolation: false
---

# Multitrack

Automatic multi-track ruler orchestration (§11.4.187): a universal, automatic,
out-of-the-box, inherited-by-reference engine. One conductor session spawns,
drives, resumes, monitors and controls per-track headless workers
(`claude -p --output-format stream-json`, session id taken from the `init`
event, success read from `result.is_error` — never the exit code), with
per-subscription authentication, rate-limit (429) rebind and fallback, and a
crash-resilient self-supervisor over durable state. Bootstrap is idempotent
and auto-invoked on every constitution pull through the §11.4.164 seam.

The consuming project supplies only per-host data:
`config/multitrack/<hostname>.yaml`. The conductor stays home; tracks execute
in their own checkouts.

## Registration

`register.sh <project-root>` (defaults to `$PWD`) is the §11.4.164
auto-install trigger — it carries no wiring logic of its own and delegates
entirely to `scripts/multitrack/multitrack_bootstrap.sh`, whose six
idempotent steps are: install the cwd-hook symlink, check the CLI alias
availability, validate the per-host config (fatal only here — host data is
never invented), seed the orchestrator (`reconcile` + `status`), run the
read-only drive-preparation probe, and leave the opt-in supervisor watchdog
off by default.

## Activation ceiling and similarity

Active-track count and worker fan-out are bounded by the host's measured
budgets (§12.6 / §12.12); a second concurrent heavy build on one host is
never scheduled (§11.4.96 UNSAFE catalogue).
