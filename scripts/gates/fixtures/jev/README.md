# fixtures/jev — self-contained fixtures for the cm_jev_* gate pairs

Owned by the gates (scripts/gates/). Do NOT depend on tests/jev/ (separate scope).
- `evidence/` — genuine jev-detection.json, token-harness before/after, decisions.jsonl
- `home/` — fake HOME with claude/kimi/opencode/pi decision-layer wiring (genuine GREEN state)
- `tools/` — stand-in checkout dirs so detection provenance paths exist on disk
- `bin/` — probe stubs + fixture bootstrap stub + git stub (clone-fallback assertion)
- `helix-deps.yaml` — fixture pin source for the clone-fallback clause
