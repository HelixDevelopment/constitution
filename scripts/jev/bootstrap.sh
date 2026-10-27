#!/usr/bin/env bash
# bootstrap.sh — Jev decision-layer master bootstrap wizard (§11.4.281).
#
# 7 stages: detect-tools -> provision (llmctl + claude_toolkit) -> detect-models
# -> install-per-agent -> configure -> calibrate-shadow -> report.
#
# Interactive-but-automatable:
#   - TTY present: prompts go to stderr, answers are read from /dev/tty.
#   - --non-interactive (or JEV_BOOTSTRAP_NON_INTERACTIVE=1): defaults plus
#     JEV_BOOTSTRAP_* env overrides; never prompts.
#   - No TTY and no --non-interactive: exit 2 immediately (never hangs).
#   The wizard runs ONCE per invocation. Whether the post-update hook calls it
#   again with --defer after a failure is the hook's decision, not this file's.
#
# Idempotency: every stage computes an input digest; digests live in
# $JEV_STATE_DIR/bootstrap.stamp. A second run with unchanged inputs prints
# "no-change" per stage and rewrites nothing (the stamp is byte-stable: it
# keeps its first created_at and is replaced only when a digest changes).
#
# Consent boundaries (nothing below happens silently; the DEFAULT run, including
# the post-update hook's --non-interactive run, touches NO network and writes
# nothing outside the state/config/evidence dirs):
#   - provisioning (git clone / fetch / checkout of llmctl and claude_toolkit
#     into $JEV_BOOTSTRAP_HOME) runs ONLY with --allow-clone / --yes /
#     JEV_BOOTSTRAP_ALLOW_CLONE=1 / JEV_BOOTSTRAP_CONSENT=1 or an interactive
#     "y". Without it a tool that is not already present (explicit dir,
#     submodule or existing clone) is recorded source=unavailable with a reason,
#     the pending stamp says "provision requires consent", and rc stays 0.
#   - tool installers (llmctl `make install`, claude_toolkit scripts/install.sh)
#     run ONLY with --install-tools / JEV_BOOTSTRAP_INSTALL_TOOLS=1 or an
#     interactive "y". They link into PATH and edit shell rc files.
#   - editing agent homes (claude_toolkit scripts/jev-setup.sh) runs ONLY with
#     --yes / JEV_BOOTSTRAP_CONSENT=1 or an interactive "y".
#   - a model download (`llmctl models download <profile>`) runs ONLY with
#     JEV_BOOTSTRAP_DOWNLOAD_PROFILE=<profile> or an interactive "y".
#
# Exit codes (three-valued; 2 is never a pass):
#   0 completed (degraded states are reported on stderr and in the evidence)
#   2 cannot determine / cannot proceed (no TTY without --non-interactive,
#     usage error, or a hard prerequisite such as jq is absent)
#   3 operator-required stop (a managed clone has local changes; nothing is
#     overwritten)
#
# Usage:
#   bootstrap.sh [--non-interactive] [--defer] [--enforce] [--yes]
#                [--allow-clone] [--install-tools] [--agent <csv>|all]
#                [--llmctl-ref <ref>] [--toolkit-ref <ref>] [--report-json PATH]
# Env (names only; values are never printed):
#   JEV_BOOTSTRAP_NON_INTERACTIVE, JEV_BOOTSTRAP_DEFER, JEV_BOOTSTRAP_CONSENT,
#   JEV_BOOTSTRAP_ALLOW_CLONE, JEV_BOOTSTRAP_INSTALL_TOOLS, JEV_BOOTSTRAP_DOWNLOAD_PROFILE,
#   JEV_BOOTSTRAP_MODE (shadow|enforce), JEV_BOOTSTRAP_AGENTS (csv|all),
#   JEV_BOOTSTRAP_HOME (managed-clone root, default ~/.local/share/helix),
#   LLMCTL_DIR / CLAUDE_TOOLKIT_DIR (explicit existing checkouts),
#   JEV_STATE_DIR (default ~/.local/state/jev),
#   JEV_EVIDENCE_DIR (default .jev), JEV_CONFIG_DIR (default ~/.config/jev),
#   CMA_PROVIDERS_DIR (toolkit endpoint cache dir),
#   JEV_CONSTITUTION_ROOT (default: derived from this script's location),
#   JEV_NOW_EPOCH (deterministic-clock seam for tests).

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JEV_CONSTITUTION_ROOT="${JEV_CONSTITUTION_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
JEV_STATE_DIR="${JEV_STATE_DIR:-$HOME/.local/state/jev}"
JEV_EVIDENCE_DIR="${JEV_EVIDENCE_DIR:-.jev}"
JEV_CONFIG_DIR="${JEV_CONFIG_DIR:-$HOME/.config/jev}"
JEV_BOOTSTRAP_HOME="${JEV_BOOTSTRAP_HOME:-$HOME/.local/share/helix}"
CMA_PROVIDERS_DIR="${CMA_PROVIDERS_DIR:-$HOME/.local/share/claude-multi-account/providers}"
NOW="${JEV_NOW_EPOCH:-$(date +%s)}"

STAMP_FILE="$JEV_STATE_DIR/bootstrap.stamp"
PENDING_FILE="$JEV_STATE_DIR/bootstrap.pending"
PROV_FILE="$JEV_STATE_DIR/tools.provenance.json"   # inner JSON body of tools{...}
ENV_FILE="$JEV_CONFIG_DIR/env"
DETECTION_FILE="$JEV_EVIDENCE_DIR/jev-detection.json"

# ---------------------------------------------------------------- args ----
NON_INTERACTIVE="${JEV_BOOTSTRAP_NON_INTERACTIVE:-0}"
DEFER="${JEV_BOOTSTRAP_DEFER:-0}"
CONSENT="${JEV_BOOTSTRAP_CONSENT:-0}"
INSTALL_TOOLS="${JEV_BOOTSTRAP_INSTALL_TOOLS:-0}"
ALLOW_CLONE="${JEV_BOOTSTRAP_ALLOW_CLONE:-0}"
DOWNLOAD_PROFILE="${JEV_BOOTSTRAP_DOWNLOAD_PROFILE:-}"
MODE="${JEV_BOOTSTRAP_MODE:-shadow}"
AGENTS="${JEV_BOOTSTRAP_AGENTS:-all}"
LLMCTL_REF_OVERRIDE=""
TOOLKIT_REF_OVERRIDE=""
REPORT_JSON=""

usage() { sed -n '/^# Usage:/,/^# Env/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; }
need_val() { [ "$1" -ge 2 ] || { echo "jev-bootstrap: $2 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --defer)           DEFER=1; shift ;;
    --enforce)         MODE="enforce"; shift ;;
    --yes)             CONSENT=1; shift ;;
    --allow-clone)     ALLOW_CLONE=1; shift ;;
    --install-tools)   INSTALL_TOOLS=1; shift ;;
    --agent|--agents)  need_val $# "$1"; AGENTS="$2"; shift 2 ;;
    --llmctl-ref)      need_val $# "$1"; LLMCTL_REF_OVERRIDE="$2"; shift 2 ;;
    --toolkit-ref)     need_val $# "$1"; TOOLKIT_REF_OVERRIDE="$2"; shift 2 ;;
    --report-json)     need_val $# "$1"; REPORT_JSON="$2"; shift 2 ;;
    --help|-h)         sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 0 ;;
    *) echo "jev-bootstrap: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$MODE" in shadow|enforce) ;; *) echo "jev-bootstrap: JEV_BOOTSTRAP_MODE must be shadow|enforce" >&2; exit 2 ;; esac
case "$AGENTS" in
  all) ;;
  *[!a-z,]*|""|,*|*,|*,,*) echo "jev-bootstrap: --agent expects 'all' or a comma list of claude,kimi,pi,opencode" >&2; exit 2 ;;
esac
if [ -n "$DOWNLOAD_PROFILE" ]; then
  case "$DOWNLOAD_PROFILE" in *[!A-Za-z0-9._-]*) echo "jev-bootstrap: JEV_BOOTSTRAP_DOWNLOAD_PROFILE must be a profile name" >&2; exit 2 ;; esac
fi

# ------------------------------------------------------------- helpers ----
log() { printf '[jev-bootstrap %s] %s\n' "$1" "$2" >&2; }

report_json_line() { # report_json_line <stage-no> <name> <result>
  [ -n "$REPORT_JSON" ] || return 0
  printf '{"stage":%s,"name":"%s","result":%s,"ts":%s}\n' \
    "$1" "$2" "$(json_escape "$3")" "$NOW" >> "$REPORT_JSON"
}

digest() { # digest <string> -> sha256 hex (portable fallbacks)
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | cksum | awk '{print $1 "-" $2}'
  fi
}

# jq is the one JSON engine here: re-implementing a parser in bash would fork a
# wire format. Its absence is a hard prerequisite (stage 1 reports it, rc 2).
HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

json_escape() { # json_escape <string> -> JSON string literal (with quotes)
  if [ "$HAVE_JQ" = "1" ]; then
    printf '%s' "$1" | jq -Rs '.'
  else # minimal escaper for the pre-flight error path only
    local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
  fi
}

atomic_write() { # atomic_write <dest>  (content on stdin); same-dir tmp + mv
  local dest="$1" tmp
  tmp="$(mktemp "$(dirname "$dest")/.jev-tmp.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$dest"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/old.tsv"; : > "$WORK/new.tsv"; : > "$WORK/results.txt"
PENDING_REASONS=""   # accumulated reasons the run is not fully complete

add_pending() { PENDING_REASONS="${PENDING_REASONS:+$PENDING_REASONS; }$1"; }
# stage_taint <name>: the stage ended unavailable/incomplete. Replace its stored
# digest with a marker that can never equal a computed one, so the next run
# retries it instead of reporting no-change.
stage_taint() { awk -F'\t' -v n="$1" 'BEGIN{OFS="\t"} $1==n{$2="tainted-retry"} {print}' "$WORK/new.tsv" > "$WORK/new.tsv.t" && mv "$WORK/new.tsv.t" "$WORK/new.tsv"; }

# ------------------------------------------------------------- defer ------
# --defer is always lawful (the hook fallback runs it with no TTY): it writes
# the pending stamp and exits 0, so it precedes the TTY gate.
if [ "$DEFER" = "1" ]; then
  mkdir -p "$JEV_STATE_DIR"
  printf '{"pending_at":%s,"reason":"operator-defer","version":"%s"}\n' \
    "$NOW" "$VERSION" | atomic_write "$PENDING_FILE"
  log "defer" "bootstrap deferred; pending stamp written to $PENDING_FILE"
  exit 0
fi

# ------------------------------------------- interactivity resolution -----
INTERACTIVE=0
if [ "$NON_INTERACTIVE" != "1" ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    INTERACTIVE=1
  else
    echo "jev-bootstrap: no TTY and --non-interactive not given; refusing to hang (rc 2)." >&2
    echo "jev-bootstrap: re-run with --non-interactive or JEV_BOOTSTRAP_NON_INTERACTIVE=1." >&2
    exit 2
  fi
fi

prompt_yn() { # prompt_yn <question> <default Y|N>  -> 0 yes / 1 no
  local question="$1" default="$2" reply=""
  if [ "$INTERACTIVE" = "1" ]; then
    printf '%s ' "$question" >&2
    read -r reply </dev/tty || reply=""
    reply="${reply:-$default}"
  else
    reply="$default"
  fi
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ------------------------------------------------- stage idempotency ------
if [ -f "$STAMP_FILE" ] && [ "$HAVE_JQ" = "1" ]; then
  jq -r '(.stages // {}) | to_entries[] | "\(.key)\t\(.value)"' "$STAMP_FILE" \
    > "$WORK/old.tsv" 2>/dev/null || : > "$WORK/old.tsv"
fi
tsv_get() { awk -F'\t' -v n="$2" '$1==n{print $2; exit}' "$1"; }

stage_begin() { # stage_begin <num> <name> <key-material> -> 0 run, 1 no-change
  local num="$1" name="$2" key
  key="$(digest "$3")"
  printf '%s\t%s\n' "$name" "$key" >> "$WORK/new.tsv"
  if [ "$(tsv_get "$WORK/old.tsv" "$name")" = "$key" ]; then
    log "$num/7" "$name: no-change"
    report_json_line "$num" "$name" "no-change"
    return 1
  fi
  log "$num/7" "$name: running"
  return 0
}
stage_commit() { # stage_commit <num> <name> <result>
  report_json_line "$1" "$2" "$3"
  printf '%s=%s\n' "$2" "$3" >> "$WORK/results.txt"
  log "$1/7" "$2: $3"
}

mkdir -p "$JEV_STATE_DIR" "$JEV_EVIDENCE_DIR" "$JEV_CONFIG_DIR"

# ---------------------------------------------- tool provisioning helpers --
manifest_field() { # manifest_field <tool> <ref|ssh_url> from helix-deps.yaml
  local deps="$JEV_CONSTITUTION_ROOT/helix-deps.yaml"
  [ -f "$deps" ] || return 0
  awk -v n="$1" -v f="$2:" '
    $0 ~ "^  - name: " n "[[:space:]]*$" {found=1; next}
    found && $0 ~ /^  - name: / {found=0}
    found && $1 == f {print $2; exit}
  ' "$deps" | tr -d "\"'"
}

provision_tool() { # provision_tool <tool> <ENVDIR_VAR> <ref-override>
  local tool="$1" envdir_var="$2" ref_override="$3"
  local envdir="" subdir="$JEV_CONSTITUTION_ROOT/submodules/$tool"
  local clone_dir="$JEV_BOOTSTRAP_HOME/$tool"
  local url path="" source="" ref head="" ref_status="unpinned" installer="not-run" reason=""
  local may_net=0
  { [ "$ALLOW_CLONE" = "1" ] || [ "$CONSENT" = "1" ]; } && may_net=1

  url="$(manifest_field "$tool" ssh_url)"
  [ -n "$url" ] || url="git@github.com:vasic-digital/$tool.git"
  ref="$ref_override"
  [ -n "$ref" ] || ref="$(manifest_field "$tool" ref)"
  [ -n "$ref" ] || ref="unpinned"

  case "$envdir_var" in
    LLMCTL_DIR) envdir="${LLMCTL_DIR:-}" ;;
    CLAUDE_TOOLKIT_DIR) envdir="${CLAUDE_TOOLKIT_DIR:-}" ;;
  esac

  if [ -n "$envdir" ] && [ -d "$envdir" ]; then
    path="$envdir"; source="explicit"
  elif [ -d "$subdir" ] && [ -n "$(ls -A "$subdir" 2>/dev/null)" ]; then
    path="$subdir"; source="submodule"
  elif [ -d "$clone_dir" ]; then
    # Managed clone exists: update only if clean; never reset over local changes.
    if [ -n "$(git -C "$clone_dir" status --porcelain 2>/dev/null)" ]; then
      echo "jev-bootstrap: ERROR: managed clone $clone_dir has local changes;" >&2
      echo "jev-bootstrap: operator-required stop (conflict_resolution); nothing overwritten." >&2
      exit 3
    fi
    if [ "$may_net" = "1" ]; then
      git -C "$clone_dir" fetch --quiet 2>/dev/null || log "" "  fetch failed for $tool (offline?); using the existing clone"
    else
      ref_status="not-synced-no-consent"
    fi
    path="$clone_dir"; source="clone"
  elif [ "$may_net" != "1" ]; then
    source="unavailable"; reason="provisioning requires consent (--allow-clone); no network access was attempted"
    log "" "  $tool not present locally and cloning needs consent; recording it as unavailable"
    add_pending "provision requires consent ($tool)"
  elif command -v git >/dev/null 2>&1; then
    mkdir -p "$JEV_BOOTSTRAP_HOME"
    if git clone --quiet "$url" "$clone_dir" 2>/dev/null; then
      path="$clone_dir"; source="clone"
    else
      log "" "  clone of $tool failed ($url); recording it as unavailable"
      source="unavailable"; reason="git clone failed (offline, no access, or host unreachable)"
    fi
  else
    log "" "  git absent: cannot clone $tool; recording it as unavailable"
    source="unavailable"; reason="git is not installed"
  fi
  [ "$source" = "unavailable" ] && PROV_UNAVAILABLE=1

  if [ "$source" = "clone" ] && [ "$ref" != "unpinned" ] && [ "$may_net" = "1" ]; then
    if git -C "$path" checkout --quiet "$ref" 2>/dev/null; then ref_status="pinned-checked-out"
    else ref_status="pin-not-reachable"; log "" "  $tool: pinned ref $ref could not be checked out; staying on the current head"; fi
  elif [ "$source" = "submodule" ] || [ "$source" = "explicit" ]; then
    ref_status="as-checked-out"   # the gitlink / the operator's checkout is authoritative
  fi
  [ -n "$path" ] && head="$(git -C "$path" rev-parse --short=12 HEAD 2>/dev/null || true)"

  # Tool installers run only with explicit consent (they link into PATH / edit rc files).
  if [ -n "$path" ] && [ "$INSTALL_TOOLS" = "1" ]; then
    case "$tool" in
      llmctl)
        if [ -f "$path/Makefile" ] && command -v make >/dev/null 2>&1; then
          if make -C "$path" install >/dev/null 2>&1; then installer="make-install"; else installer="make-install-failed"; fi
        else installer="no-installer-found"; fi ;;
      claude_toolkit)
        if [ -f "$path/scripts/install.sh" ]; then
          if bash "$path/scripts/install.sh" >/dev/null 2>&1; then installer="scripts/install.sh"; else installer="scripts/install.sh-failed"; fi
        else installer="no-installer-found"; fi ;;
    esac
  fi

  printf '"%s":{"path":%s,"ref":%s,"source":%s,"installer":%s,"head":%s,"ref_status":%s,"reason":%s}' \
    "$tool" "$(json_escape "$path")" "$(json_escape "$ref")" "$(json_escape "$source")" \
    "$(json_escape "$installer")" "$(json_escape "$head")" "$(json_escape "$ref_status")" "$(json_escape "$reason")" \
    > "$WORK/prov.$tool.json"
  log "" "  provision $tool: source=$source path=${path:-none} ref=$ref ref_status=$ref_status installer=$installer"
}

provenance_load() { # reassemble tools{...} inner body from the fragments
  local out="" f
  for f in "$WORK"/prov.*.json; do
    [ -f "$f" ] || continue
    [ -n "$out" ] && out="$out,"
    out="$out$(cat "$f")"
  done
  printf '%s' "$out"
}

tool_path() { # tool_path <tool> -> checkout path recorded in provenance ('' if none or unavailable)
  [ -s "$PROV_FILE" ] || return 0
  printf '{%s}' "$(cat "$PROV_FILE")" | jq -r --arg t "$1" '.[$t].path // empty' 2>/dev/null || true
}

# ============================================================== STAGES ====

# ---- Stage 1: detect-tools (pre-flight) ----
S1_KEY="v$VERSION|$MODE|$AGENTS|$JEV_CONSTITUTION_ROOT|jq=$HAVE_JQ|consent=$CONSENT|clone=$ALLOW_CLONE|install=$INSTALL_TOOLS|dl=$DOWNLOAD_PROFILE"
if [ "$HAVE_JQ" = "0" ]; then
  echo "jev-bootstrap: jq is a hard prerequisite (JSON parsing) and is absent; cannot determine (rc 2)." >&2
  printf '{"pending_at":%s,"reason":"missing-prerequisite:jq","version":"%s"}\n' "$NOW" "$VERSION" | atomic_write "$PENDING_FILE"
  exit 2
fi
if stage_begin 1 "detect-tools" "$S1_KEY"; then
  tools_found="" tools_missing=""
  for t in jq curl git make; do
    if command -v "$t" >/dev/null 2>&1; then tools_found="$tools_found $t"; else tools_missing="$tools_missing $t"; fi
  done
  log "" "  tools present:${tools_found:- none}"
  [ -n "$tools_missing" ] && log "" "  tools absent (optional unless needed):$tools_missing"
  if [ "$INTERACTIVE" = "1" ]; then
    if ! prompt_yn "Run the tools' own installers (links into PATH, may edit shell rc files)? [y/N]" "N"; then :; else INSTALL_TOOLS=1; fi
    if ! prompt_yn "Allow cloning/fetching llmctl and claude_toolkit over the network into $JEV_BOOTSTRAP_HOME? [y/N]" "N"; then :; else ALLOW_CLONE=1; fi
    if ! prompt_yn "Allow editing agent configuration under your home (jev-setup; backups are made first)? [y/N]" "N"; then :; else CONSENT=1; fi
  fi
  stage_commit 1 "detect-tools" "ok"
fi

# ---- Stage 2: provision (llmctl + claude_toolkit) ----
S2_KEY="prov|${LLMCTL_DIR:-}|${CLAUDE_TOOLKIT_DIR:-}|${LLMCTL_REF_OVERRIDE}|${TOOLKIT_REF_OVERRIDE}|install=$INSTALL_TOOLS|clone=$ALLOW_CLONE|consent=$CONSENT|$JEV_BOOTSTRAP_HOME|$(manifest_field llmctl ref)|$(manifest_field claude_toolkit ref)|sm=$({ ls -d "$JEV_CONSTITUTION_ROOT"/submodules/llmctl "$JEV_CONSTITUTION_ROOT"/submodules/claude_toolkit 2>/dev/null || true; } | tr '\n' ',')"
if stage_begin 2 "provision" "$S2_KEY"; then
  rm -f "$WORK"/prov.*.json
  PROV_UNAVAILABLE=0
  provision_tool "llmctl" "LLMCTL_DIR" "$LLMCTL_REF_OVERRIDE"
  provision_tool "claude_toolkit" "CLAUDE_TOOLKIT_DIR" "$TOOLKIT_REF_OVERRIDE"
  provenance_load | atomic_write "$PROV_FILE"
  if [ "$PROV_UNAVAILABLE" = "1" ]; then
    stage_taint "provision"   # retried on the next run; never cached as done
    stage_commit 2 "provision" "incomplete tool(s) unavailable"
  else
    stage_commit 2 "provision" "ok"
  fi
fi
TOOL_PROVENANCE=""
[ -f "$PROV_FILE" ] && TOOL_PROVENANCE="$(cat "$PROV_FILE")"

# ---- Stage 3: detect-models ----
LLMCTL_BIN=""; TOOLKIT_BIN=""
if command -v llmctl >/dev/null 2>&1; then LLMCTL_BIN="llmctl"
elif [ -n "$(tool_path llmctl)" ] && [ -x "$(tool_path llmctl)/bin/llmctl" ]; then LLMCTL_BIN="$(tool_path llmctl)/bin/llmctl"; fi
if command -v claude-providers >/dev/null 2>&1; then TOOLKIT_BIN="claude-providers"
elif [ -n "$(tool_path claude_toolkit)" ] && [ -x "$(tool_path claude_toolkit)/scripts/claude-providers.sh" ]; then TOOLKIT_BIN="$(tool_path claude_toolkit)/scripts/claude-providers.sh"; fi

# Read-only inputs, gathered BEFORE the stage key so a model started later
# changes the digest (a key built from tool presence alone would never re-detect).
LLM_STATUS="{}"; LLM_CAP="{}"
if [ -n "$LLMCTL_BIN" ]; then
  LLM_STATUS="$("$LLMCTL_BIN" decide status --json 2>/dev/null | jq -c '.' 2>/dev/null)" || LLM_STATUS="{}"
  [ -n "$LLM_STATUS" ] || LLM_STATUS="{}"
  LLM_CAP="$("$LLMCTL_BIN" decide capacity --json 2>/dev/null | jq -c '.' 2>/dev/null)" || LLM_CAP="{}"
  [ -n "$LLM_CAP" ] || LLM_CAP="{}"
fi
CACHE="$CMA_PROVIDERS_DIR/jev-endpoints.json"
CACHE_BODY=""
[ -f "$CACHE" ] && CACHE_BODY="$(jq -c '[.endpoints[]? | {provider_id,base_url,model,key_var}]' "$CACHE" 2>/dev/null || true)"
S3_KEY="det|bin=${LLMCTL_BIN:+1}${TOOLKIT_BIN:+t}|st=$LLM_STATUS|cache=$CACHE_BODY|dl=$DOWNLOAD_PROFILE|$TOOL_PROVENANCE"
if stage_begin 3 "detect-models" "$S3_KEY"; then
  # Refresh the toolkit endpoint cache (hosted/LAN pins: key var NAMES only).
  if [ -n "$TOOLKIT_BIN" ]; then
    "$TOOLKIT_BIN" sync-jev --quiet >/dev/null 2>&1 || log "" "  claude-providers sync-jev failed or was skipped; using the existing cache (if any)"
    [ -f "$CACHE" ] && CACHE_BODY="$(jq -c '[.endpoints[]? | {provider_id,base_url,model,key_var}]' "$CACHE" 2>/dev/null || true)"
  fi
  : > "$WORK/endpoints.tsv"   # id source model reachable parallel url basis (TAB separated)
  gw_running="$(printf '%s' "$LLM_STATUS" | jq -r '.gateway.running // false' 2>/dev/null || echo false)"
  # Gateway URL: first https URL in the status detail; otherwise llmctl's documented default port.
  gw_url="$(printf '%s' "$LLM_STATUS" | jq -r '.gateway.detail // ""' 2>/dev/null | grep -Eo 'https://[^ ")]+' | head -1 || true)"
  gw_basis="llmctl-status-detail"
  if [ -z "$gw_url" ]; then gw_url="https://127.0.0.1:8095"; gw_basis="llmctl-default-port"; fi
  # Local decision instances: a decide profile that is RUNNING. `plan --json`
  # is a capacity report ("nothing reserved"), so it cannot say what is running.
  printf '%s' "$LLM_STATUS" | jq -r '.profiles[]? | select(.running == true) | .profile' 2>/dev/null \
  | while IFS= read -r prof; do
      [ -n "$prof" ] || continue
      par="$(printf '%s' "$LLM_CAP" | jq -r --arg p "$prof" '.decision_instances[$p].effective_slots_per_instance // 1' 2>/dev/null || echo 1)"
      printf 'llmctl-%s\tlocal-llmctl\t%s\t%s\t%s\t%s\t%s\n' "$prof" "$prof" "$gw_running" "$par" "$gw_url" "$gw_basis" >> "$WORK/endpoints.tsv"
    done
  if [ -n "$CACHE_BODY" ]; then
    # reachable is UNKNOWN from the cache (it records resolution, not a probe): null.
    jq -r '.endpoints[]? | [.provider_id, "toolkit-cache", (.model // "jev-latest"), "null", "1", (.base_url // ""), "resolution-only"] | @tsv' "$CACHE" \
      >> "$WORK/endpoints.tsv" 2>/dev/null || true
  fi
  endpoints_count="$(grep -c . "$WORK/endpoints.tsv" || true)"
  endpoints_json="$(jq -Rn --argjson now "$NOW" '[inputs | select(length > 0) | split("\t") |
      {id:.[0], source:.[1], model:.[2],
       reachable:(if .[3]=="true" then true elif .[3]=="false" then false else null end),
       parallel:((.[4] | tonumber? ) // 1), probed_at:$now, reason:null}
      + (if (.[5] // "") != "" then {url:.[5]} else {} end)
      + (if .[6] == "resolution-only" then {reachable_basis:"resolution-only"}
         elif .[1] == "local-llmctl" then {reachable_basis:"llmctl-status-claim", url_basis:.[6]}
         else {} end)]' < "$WORK/endpoints.tsv")"
  absence_reason=""
  if [ "${endpoints_count:-0}" -eq 0 ]; then
    if [ -z "$LLMCTL_BIN" ]; then
      absence_reason="llmctl not found and the toolkit endpoint cache is empty: no decision endpoints detectable"
    else
      absence_reason="no decide profile is running and the toolkit endpoint cache is empty"
    fi
    log "" "  no decision endpoints detected: $absence_reason"
    # Optional local profile download (network, ~0.5 GiB for decide-tiny): consent only.
    want_profile=""
    if [ -n "$LLMCTL_BIN" ]; then
      if [ -n "$DOWNLOAD_PROFILE" ]; then want_profile="$DOWNLOAD_PROFILE"
      elif [ "$INTERACTIVE" = "1" ] && prompt_yn "No decision endpoints found. Download a local decision profile (decide-tiny) with llmctl? [y/N]" "N"; then want_profile="decide-tiny"; fi
    fi
    if [ -n "$want_profile" ]; then
      fits="$(printf '%s' "$LLM_CAP" | jq -r --arg p "$want_profile" '((.decision_instances[$p].instances_gpu // 0) + (.decision_instances[$p].instances_cpu // 0)) > 0' 2>/dev/null || echo false)"
      if [ "$fits" = "true" ]; then
        if "$LLMCTL_BIN" models download "$want_profile" >/dev/null 2>&1; then
          log "" "  downloaded decision profile $want_profile (start it, then re-run bootstrap to detect)"
          add_pending "profile $want_profile downloaded but not started"
        else
          log "" "  download of $want_profile failed; see: llmctl models download $want_profile"
          absence_reason="$absence_reason; download of $want_profile failed"
        fi
      else
        absence_reason="$absence_reason; $want_profile does not fit this host's capacity (llmctl decide capacity)"
        log "" "  $want_profile does not fit this host's capacity; not downloading"
      fi
    fi
  else
    printf '%s' "$endpoints_json" | jq -r '.[] | "  endpoint: \(.id) (source=\(.source) model=\(.model) reachable=\(.reachable))"' | while IFS= read -r l; do log "" "$l"; done
  fi
  reason_json="null"
  [ -n "$absence_reason" ] && reason_json="$(json_escape "$absence_reason")"
  par_total="$(printf '%s' "$endpoints_json" | jq '[.[].parallel] | add // 0')"
  printf '{"version":1,"generated_at":%s,"endpoints":%s,"reason":%s,"capacity":{"instances":%s,"decision_instances":%s,"parallel_total":%s},"tools":{%s}}\n' \
    "$NOW" "$endpoints_json" "$reason_json" "${endpoints_count:-0}" "${endpoints_count:-0}" "$par_total" "$TOOL_PROVENANCE" \
    | jq -c '.' | atomic_write "$DETECTION_FILE"
  stage_commit 3 "detect-models" "ok endpoints=${endpoints_count:-0}"
fi

# ---- Stage 4: install-per-agent ----
TK_PATH="$(tool_path claude_toolkit)"
TK_SETUP=""
[ -n "$TK_PATH" ] && [ -f "$TK_PATH/scripts/jev-setup.sh" ] && TK_SETUP="$TK_PATH/scripts/jev-setup.sh"
CHECK_OUT=""; CHECK_RC=0
if [ -n "$TK_SETUP" ]; then
  CHECK_OUT="$(bash "$TK_SETUP" --check --agents "$AGENTS" 2>&1)" || CHECK_RC=$?
fi
S4_KEY="agents|$AGENTS|consent=$CONSENT|setup=${TK_SETUP:+1}|rc=$CHECK_RC|$CHECK_OUT"
if stage_begin 4 "install-per-agent" "$S4_KEY"; then
  if [ -z "$TK_SETUP" ]; then
    log "" "  SKIP wiring: claude_toolkit scripts/jev-setup.sh unavailable (no toolkit checkout)"
    add_pending "agent wiring skipped: claude_toolkit unavailable"
    stage_commit 4 "install-per-agent" "skipped toolkit-unavailable"
  elif [ "$CHECK_RC" = "0" ]; then
    stage_commit 4 "install-per-agent" "ok already-wired (jev-setup --check clean)"
  elif [ "$CONSENT" != "1" ]; then
    log "" "  wiring not applied: consent not given. jev-setup --check reported:"
    printf '%s\n' "$CHECK_OUT" | while IFS= read -r l; do log "" "    $l"; done
    log "" "  apply with: bootstrap.sh --yes   (or JEV_BOOTSTRAP_CONSENT=1)"
    add_pending "agent wiring awaits consent"
    stage_commit 4 "install-per-agent" "pending-consent"
  else
    setup_rc=0
    bash "$TK_SETUP" --agents "$AGENTS" --yes >"$WORK/setup.out" 2>&1 || setup_rc=$?
    if [ "$setup_rc" = "0" ]; then
      stage_commit 4 "install-per-agent" "ok wired agents=$AGENTS"
    else
      tail -n 5 "$WORK/setup.out" | while IFS= read -r l; do log "" "    $l"; done
      add_pending "jev-setup exited rc $setup_rc"
      stage_taint "install-per-agent"
      stage_commit 4 "install-per-agent" "failed jev-setup rc=$setup_rc"
    fi
  fi
fi

# ---- Stage 5: configure ----
S5_KEY="cfg|$MODE|thr=$([ -f "$JEV_CONFIG_DIR/jev-thresholds.json" ] && echo 1 || echo 0)"
if stage_begin 5 "configure" "$S5_KEY"; then
  [ -f "$JEV_STATE_DIR/decisions.jsonl" ] || : > "$JEV_STATE_DIR/decisions.jsonl"   # shadow-log scaffold
  effective_mode="$MODE"; enforce_note=""
  if [ "$MODE" = "enforce" ] && [ ! -f "$JEV_CONFIG_DIR/jev-thresholds.json" ] && [ ! -f "$JEV_EVIDENCE_DIR/jev-thresholds.json" ]; then
    effective_mode="shadow"
    enforce_note="enforce-deferred: no-calibrated-thresholds"
    log "" "  $enforce_note — staying in shadow"
  fi
  if [ ! -f "$ENV_FILE" ]; then
    printf 'JEV_MODE=%s\n' "$effective_mode" | atomic_write "$ENV_FILE"
  elif ! grep -q '^JEV_MODE=' "$ENV_FILE"; then
    { cat "$ENV_FILE"; printf 'JEV_MODE=%s\n' "$effective_mode"; } | atomic_write "$ENV_FILE"
  fi
  if [ -n "$enforce_note" ]; then printf '%s\n' "$enforce_note" | atomic_write "$JEV_STATE_DIR/enforce-deferred"
  else rm -f "$JEV_STATE_DIR/enforce-deferred"; fi
  stage_commit 5 "configure" "ok mode=$effective_mode"
fi

# ---- Stage 6: calibrate-shadow ----
MAIN_ALIAS="$(grep -s '^MAIN_LLM_ALIAS=' "$ENV_FILE" | head -1 | cut -d= -f2 || true)"
S6_KEY="cal|$MODE|alias=$MAIN_ALIAS|thr=$([ -f "$JEV_CONFIG_DIR/jev-thresholds.json" ] && echo 1 || echo 0)"
if stage_begin 6 "calibrate-shadow" "$S6_KEY"; then
  calib="$SCRIPT_DIR/jev-calibrate.sh"
  if [ "$MODE" = "enforce" ] && [ ! -f "$JEV_CONFIG_DIR/jev-thresholds.json" ] && [ -n "$MAIN_ALIAS" ] && [ -f "$calib" ]; then
    cal_rc=0
    bash "$calib" --now --alias "$MAIN_ALIAS" >&2 || cal_rc=$?
    if [ "$cal_rc" = "0" ]; then stage_commit 6 "calibrate-shadow" "ok ran-calibration"
    else add_pending "calibration rc $cal_rc (see jev-calibrate.sh output)"; stage_taint "calibrate-shadow"; stage_commit 6 "calibrate-shadow" "incomplete calibration-rc=$cal_rc"; fi
  else
    log "" "  shadow mode: decisions are logged to $JEV_STATE_DIR/decisions.jsonl; enforcement requires calibrated thresholds"
    stage_commit 6 "calibrate-shadow" "ok shadow"
  fi
fi

# ---- Stage 7: report ----
S7_KEY="rep|v$VERSION|$(cat "$WORK/new.tsv" | tr '\n' '|')"
if stage_begin 7 "report" "$S7_KEY"; then
  # Re-entrancy guard: cm_jev_bootstrap_idempotent runs bootstrap.sh itself, so a
  # gate run from inside bootstrap must never start another bootstrap (unbounded
  # fork recursion, measured 2026-10-23). The marker makes nested runs skip this loop.
  log "" "  gate cm_jev_bootstrap_idempotent: not run from bootstrap (it executes bootstrap; run it directly)"
  for g in cm_jev_detection cm_jev_wiring cm_jev_token_reduction; do
    if [ -n "${JEV_BOOTSTRAP_NESTED:-}" ]; then
      log "" "  gate $g: skipped (nested bootstrap run; re-entrancy guard)"
    elif [ -f "$JEV_CONSTITUTION_ROOT/scripts/gates/$g.sh" ]; then
      if JEV_BOOTSTRAP_NESTED=1 bash "$JEV_CONSTITUTION_ROOT/scripts/gates/$g.sh" >/dev/null 2>&1; then
        log "" "  gate $g: PASS (advisory)"
      else
        log "" "  gate $g: FAIL or could not run (advisory, non-blocking; run it directly for detail)"
      fi
    else
      log "" "  gate $g: absent (advisory skip)"
    fi
  done
  log "" "  summary: state=$JEV_STATE_DIR evidence=$JEV_EVIDENCE_DIR mode=$(awk -F= '$1=="JEV_MODE"{print $2; f=1; exit} END{if(!f)print "shadow"}' "$ENV_FILE" 2>/dev/null || echo shadow)"
  log "" "  next: scripts/jev/jev-status.sh for status; claude_toolkit scripts/jev-stats.sh for savings (ESTIMATES only)"
  stage_commit 7 "report" "ok"
fi

# ---- stamp (byte-stable) and pending bookkeeping ----
{
  first_created="$NOW"
  if [ -f "$STAMP_FILE" ]; then
    old_created="$(jq -r '.created_at // empty' "$STAMP_FILE" 2>/dev/null || true)"
    [ -n "$old_created" ] && first_created="$old_created"
  fi
  printf '{\n  "version": "%s",\n  "created_at": %s,\n  "stages": {' "$VERSION" "$first_created"
  sep=""
  for name in detect-tools provision detect-models install-per-agent configure calibrate-shadow report; do
    k="$(tsv_get "$WORK/new.tsv" "$name")"
    printf '%s\n    "%s": "%s"' "$sep" "$name" "${k:-none}"
    sep=","
  done
  printf '\n  },\n  "tools": {%s}\n}\n' "$TOOL_PROVENANCE"
} > "$WORK/stamp.new"
if [ -f "$STAMP_FILE" ] && cmp -s "$WORK/stamp.new" "$STAMP_FILE"; then
  :   # unchanged: leave the existing stamp untouched
else
  atomic_write "$STAMP_FILE" < "$WORK/stamp.new"
fi

if [ -n "$PENDING_REASONS" ]; then
  printf '{"pending_at":%s,"reason":%s,"version":"%s"}\n' "$NOW" "$(json_escape "$PENDING_REASONS")" "$VERSION" | atomic_write "$PENDING_FILE"
  log "" "  PENDING: $PENDING_REASONS"
else
  rm -f "$PENDING_FILE"   # a fully completed run discharges an earlier deferral
fi

exit 0
