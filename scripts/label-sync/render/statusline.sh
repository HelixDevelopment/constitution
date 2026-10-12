#!/usr/bin/env bash
# scripts/label-sync/render/statusline.sh
#
# Purpose : Claude Code `statusLine` command. Reads the status-line JSON on
#           stdin and prints ONE line: the live §11.4.182 label
#           `(T<N>/<branch> - <alias> - <model> - <effort>)` of THIS session,
#           taken from the label-sync snapshot, plus a marker when it is not a
#           plain live reading:
#             [stale]            the entity stopped heartbeating (CONTRACT §6)
#             [done]             the session was unregistered
#             [no-session]       state exists but holds no entity for this session
#             [no-state]         no readable snapshot (bus/state down)
#             [derived:<why>]    fallback: label derived from the live process
#                                by the canonical labeler (never guessed)
#           With no data at all it prints `(T?/? - ? - ? - ?)` + marker — the
#           honest-unknown form, never an invented value (§11.4.6).
# Usage   : in settings: {"statusLine":{"type":"command","command":"bash <abs>/statusline.sh"}}
#           (install text: docs/label-sync/RENDERERS.md)
# Inputs  : stdin JSON from Claude Code. Fields read (defensively; unknown /
#           missing => ignored): .session_id, .workspace.current_dir, .cwd.
#           UNCONFIRMED against the Claude Code docs (not found on this host):
#           the exact stdin schema — see RENDERERS.md "Honest boundary".
#           env LABEL_SYNC_DIR; LABEL_SYNC_STATUSLINE_DERIVE (default 1) enable
#           the derived fallback; LABEL_SYNC_STATUSLINE_CACHE_TTL (default 5 s,
#           0 = off) caches ONLY the derived fallback; LABEL_SYNC_CACHE_DIR;
#           LABEL_SYNC_LABELER (canonical labeler override).
# Outputs : one line on stdout, passed through lib.sh ls_sanitize (no terminal
#           control / C1 / bidi / invalid UTF-8 byte can reach the host UI, under
#           any locale; capped at 512 bytes).
# Exit    : 0 ALWAYS (a status line must never break the host UI). stderr silent.
# Cost    : primary path = one `jq` fork over the snapshot, no other fork;
#           measured avg latency is reported by tests/test_render.sh (METRIC
#           statusline_avg_ms). The derived fallback forks the labeler (bounded
#           by `timeout 1`) and is cached.
# Side-effects: derived-fallback cache file under LABEL_SYNC_CACHE_DIR only.
# Deps    : bash>=4.2, jq; timeout/stat only on the fallback path.
# Cross-refs: §11.4.182, §11.4.116, docs/label-sync/CONTRACT.md, RENDERERS.md.
# Classification: universal (§11.4.17).
set -u
UNKNOWN='(T?/? - ? - ? - ?)'
RDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
. "$RDIR/lib.sh" 2>/dev/null || { printf '%s [no-render-lib]\n' "$UNKNOWN"; exit 0; }

input=""
if [ ! -t 0 ]; then IFS= read -r -d '' -t 1 input 2>/dev/null || :; fi

snap="$(ls_dir)/snapshot.json"
status="nostate"; text=""; sid=""; cwd=""
JQ_PROG='
  ((try ($in | fromjson) catch {}) | if type == "object" then . else {} end) as $i
  | ($i.session_id // "" | tostring) as $sid
  | ($i.workspace.current_dir // $i.cwd // "" | tostring) as $cwd
  | ($snap[0].entities // []) as $es
  | ([$es[] | select(.session_id == $sid and $sid != "")] | (map(select(.kind == "session")) + .) | first) as $e
  | if $e then ["ok", $sid, $cwd, ($e.label + (if $e.stale then " [stale]" elif $e.state == "done" then " [done]" else "" end))]
    else ["nosession", $sid, $cwd, ""] end
  | join("\u001f")'
if command -v jq >/dev/null 2>&1; then
  res=""
  if [ -r "$snap" ] && res="$(jq -nr --slurpfile snap "$snap" --arg in "$input" "$JQ_PROG" 2>/dev/null)" && [ -n "$res" ]; then
    :
  else
    # snapshot absent/corrupt: still extract session + cwd for the derived fallback
    res="$(jq -nr --argjson snap '[null]' --arg in "$input" "$JQ_PROG" 2>/dev/null)"
    [ -n "$res" ] && res="nostate"$'\037'"${res#*$'\037'}"
  fi
  if [ -n "$res" ]; then
    IFS=$'\037' read -r status sid cwd text <<<"$res"
  fi
fi

if [ "$status" = "ok" ] && [ -n "$text" ]; then
  ls_sanitize_into text "$text"          # strict: C0/DEL/C1/bidi/invalid UTF-8, capped
  printf '%s\n' "$text"
  exit 0
fi

why="no-state"; [ "$status" = "nosession" ] && why="no-session"
derived=""
if [ "${LABEL_SYNC_STATUSLINE_DERIVE:-1}" != "0" ]; then
  labeler="${LABEL_SYNC_LABELER:-$RDIR/../../multitrack/track_branch_label.sh}"
  ttl="${LABEL_SYNC_STATUSLINE_CACHE_TTL:-5}"
  cdir="${LABEL_SYNC_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/constitution-label-sync}/statusline"
  cfile="$cdir/${sid//[^A-Za-z0-9_-]/_}.label"
  if [ "$ttl" != "0" ] && [ -r "$cfile" ]; then
    age=$(( $(printf '%(%s)T' -1) - $(stat -c %Y "$cfile" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$ttl" ] && IFS= read -r derived <"$cfile"
  fi
  if [ -z "$derived" ] && [ -r "$labeler" ] && command -v timeout >/dev/null 2>&1; then
    derived="$( { [ -n "$cwd" ] && cd "$cwd" 2>/dev/null; CLAUDE_CODE_SESSION_ID="$sid" timeout 1 bash "$labeler" 2>/dev/null | head -n 1; } )"
    ls_sanitize_into derived "$derived"   # before the shape check: locale-independent
    if [[ "$derived" =~ ^\(T([0-9]+|\?)/.+\)$ ]]; then
      if [ "$ttl" != "0" ]; then mkdir -p "$cdir" 2>/dev/null && printf '%s\n' "$derived" >"$cfile" 2>/dev/null; fi
    else
      derived=""
    fi
  fi
fi
if [ -n "$derived" ]; then
  ls_sanitize_into derived "$derived"
  printf '%s [derived:%s]\n' "$derived" "$why"
else
  printf '%s [%s]\n' "$UNKNOWN" "$why"
fi
exit 0
