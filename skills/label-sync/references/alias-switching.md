# Alias switching — exact semantics (reference for the label-sync skill)

Source of truth: `docs/label-sync/CONTRACT.md` §4. Summary an agent needs:

* `switch-alias --alias A [--model M] [--effort E]` writes the operator's ACTIVE
  context. The same transaction re-renders every entity that follows it.
* **Who follows:** entities with `follow_active=true` (default for Claude
  sessions/agents registered without `--derive` divergence). Resolution order for
  an entity's shown alias/model/effort: active triple (if following) → its own
  triple → nearest non-following ancestor's → `?`.
* **Per-process truth wins:** a session resumed under a *different* alias than
  the active one is registered with `follow_active=false`; the whole subtree of
  that session (same session id + descendants) keeps showing the session's alias
  across later operator switches. Unrelated sessions keep following.
* **Non-Claude agents** (adapters) default to `follow_active=false`; the operator
  can opt one in with `LABEL_SYNC_FOLLOW_ACTIVE=1` in that agent's environment.
* **Never invent:** unspecified `--model/--effort` are stored empty and render
  `?`. Ask the operator if you need them; do not copy another field's value.

Verify a switch took effect:

```bash
labelctl.sh switch-alias --alias claude2 --model sonnet --effort high
labelctl.sh list --json | jq -r '.entities[] | "\(.id)\t\(.follow_active)\t\(.label)"'
```
