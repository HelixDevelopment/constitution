# Jev Decision Layer — FAQ

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-23 |
| Last modified | 2026-10-23T00:00:00Z |
| Status | active |
| Status summary | Short answers to recurring questions, each tied to the source that settles it. |
| Authority | Constitution §11.4.279–§11.4.286. The canonical anchor texts and the scripts govern where this document and they disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation |
| Fixed summary | — |
| Continuation | none |

Related: [governance guide](governance-guide.md) · [bootstrap reference](bootstrap-reference.md) · [diagrams](diagrams.md)

## Table of contents

- [General](#general)
- [Endpoints and models](#endpoints-and-models)
- [Safety and privacy](#safety-and-privacy)
- [Calibration and proof](#calibration-and-proof)
- [Bootstrap](#bootstrap)

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
The llmctl gateway is HTTPS only, with a local CA and a mandatory bearer key. The toolkit gate sends the key only over `https://` and accepts a CA file through `JEV_CA_FILE`. A plain `http://127.0.0.1:8095` URL will not work.

**10. Why does a slow local model make the gate fall back?**
The gate's curl timeout is `JEV_GATE_TIMEOUT` (2 s). The gateway's own budget is `LLMCTL_DECIDE_TIMEOUT` (8 s, or 120 s when a CPU llama instance is served). Raise the gate timeout or use a faster profile.

## Safety and privacy

**11. What leaves my machine?**
With a hosted endpoint: the tool name and tool input (up to 12,000 characters), sent to that provider. With the local gateway: nothing leaves the host. The local log stores a 16-hex-character hash, never the text.

**12. Where do secrets go?**
Nowhere in this layer. Files and docs carry key variable NAMES (`LLMCTL_API_KEY`, `OPENROUTER_API_KEY`, `TYPESAFE_API_KEY`). The gate reads the value at call time and never puts it on a command line. One caveat in the toolkit: its kimi MCP config can contain a materialized key in a 0700 directory (comment in `jev-setup.sh`).

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
By design: stage digests equal the stamp, nothing is rewritten.

**20. Why does it want `jq`?**
JSON parsing; a second parser would fork the wire format. Without it the wizard stops with rc 2 and a pending stamp.

**21. Does bootstrap use the network?**
Not by default. Cloning or fetching llmctl/claude_toolkit needs `--allow-clone` (or `--yes`); the post-update hook runs without it, so a pull never triggers a clone.

**22. Does bootstrap run the tools' installers?**
Only with `--install-tools` (or a "y" at the prompt). They link into PATH and edit shell rc files.
