#!/usr/bin/env bash
# Fixture bootstrap stub — simulates scripts/jev/bootstrap.sh inside gate/test
# sandboxes (the real wizard is another work item's scope). Deterministic,
# idempotent (marker-guarded writes), supports:
#   --non-interactive   run without prompts
#   --defer             write pending stamp, exit 0
# Env:
#   JEV_FAKE_HOME         fixture host root (required)
#   JEV_STATE_DIR         state dir (default $JEV_FAKE_HOME/.local/state/jev)
#   JEV_SUBMODULES_ABSENT=1  force managed-clone fallback path
#   JEV_FIXTURE_DEPS      helix-deps.yaml to read pinned refs from (clone fallback)
set -uo pipefail

NON_INTERACTIVE=0; DEFER=0
for a in "$@"; do
  case "$a" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    --defer) DEFER=1 ;;
  esac
done

: "${JEV_FAKE_HOME:?fixture stub requires JEV_FAKE_HOME}"
STATE_DIR="${JEV_STATE_DIR:-$JEV_FAKE_HOME/.local/state/jev}"
mkdir -p "$STATE_DIR" "$JEV_FAKE_HOME/.config/jev"

log() { printf '[fixture-bootstrap] %s\n' "$*" >&2; }

if [ "$DEFER" -eq 1 ]; then
  printf 'pending=%s\n' "$(date +%s 2>/dev/null || echo 0)" > "$STATE_DIR/bootstrap.pending"
  log "deferred — pending stamp written to $STATE_DIR/bootstrap.pending"
  exit 0
fi

# Non-TTY without --non-interactive is an error, never a hang (§11.4.281(B)).
if [ "$NON_INTERACTIVE" -eq 0 ] && [ ! -t 0 ]; then
  echo "fixture-bootstrap: non-TTY without --non-interactive — refusing to hang" >&2
  exit 2
fi

# Provision path: submodule present vs managed-clone fallback (pinned ref).
if [ "${JEV_SUBMODULES_ABSENT:-0}" = "1" ]; then
  DEPS="${JEV_FIXTURE_DEPS:?clone-fallback fixture requires JEV_FIXTURE_DEPS}"
  for tool in llmctl claude_toolkit; do
    url=$(awk -v n="$tool" '$0 ~ "name: "n {f=1} f && /ssh_url:/ {print $2; exit}' "$DEPS")
    ref=$(awk -v n="$tool" '$0 ~ "name: "n {f=1} f && /ref:/ {print $2; exit}' "$DEPS")
    dest="$JEV_FAKE_HOME/.local/share/helix/$tool"
    if [ ! -d "$dest" ]; then
      git clone "$url" "$dest"
      (cd "$dest" && git checkout "$ref")
      log "clone-fallback: $tool @ $ref -> $dest"
    else
      log "clone-fallback: $tool already present (no-change)"
    fi
  done
fi

# Idempotent marker-guarded config write.
ENV_FILE="$JEV_FAKE_HOME/.config/jev/env"
if [ ! -f "$ENV_FILE" ]; then
  printf 'JEV_MODE=shadow\n' > "$ENV_FILE"
  log "wrote $ENV_FILE"
else
  log "env present (no-change)"
fi

touch "$JEV_FAKE_HOME/.config/jev/decisions.jsonl"

# Resulting-state digest stamp (idempotency contract).
digest=$(find "$JEV_FAKE_HOME/.config" -type f -exec sha256sum {} + | sort | sha256sum | cut -d' ' -f1)
printf 'version=fixture-1\ndigest=%s\n' "$digest" > "$STATE_DIR/bootstrap.stamp"
log "complete — stamp digest=$digest"
exit 0
