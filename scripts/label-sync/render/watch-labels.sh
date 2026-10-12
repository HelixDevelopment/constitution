#!/usr/bin/env bash
# scripts/label-sync/render/watch-labels.sh
#
# Purpose : Live operator view of every label-sync entity: polls the `seq` file,
#           and on change clears + redraws a compact table grouped by alias,
#           one row per entity (id, kind, state, label, [stale]).
# Usage   : watch-labels.sh [--once] [--interval-ms N] [--iterations N]
#                           [--timeout-s N] [--kind K]
#           --once            render one frame and exit (no screen clear)
#           --interval-ms N   poll period (default 200)
#           --iterations N    exit after N frames drawn (default: run forever)
#           --timeout-s N     exit after N seconds regardless (default: none)
#           --kind K          only entities of kind K
# Inputs  : snapshot.json + seq in $LABEL_SYNC_DIR (CONTRACT §1, §3).
# Outputs : frames on stdout; every line passes lib.sh ls_sanitize (C0/DEL/C1/
#           bidi/invalid UTF-8, capped) so no snapshot value can drive the
#           terminal; the clear-screen escape is emitted ONLY when stdout is a tty. Works with the daemon down (polling needs none).
# Exit    : 0 normal end | 2 jq missing (cannot determine — never a pass).
# Side-effects: none (read-only).
# Deps    : bash>=4, jq.
# Cross-refs: §11.4.182, §11.4.116, docs/label-sync/CONTRACT.md §3.
# Classification: universal (§11.4.17).
set -u
RDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
. "$RDIR/lib.sh" || exit 2
command -v jq >/dev/null 2>&1 || { echo "watch-labels: jq missing" >&2; exit 2; }
once="" ms=200 iters=0 tmo=0 kind=""
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1; shift ;;
    --interval-ms) ms="${2:-200}"; shift 2 ;;
    --iterations) iters="${2:-0}"; shift 2 ;;
    --timeout-s) tmo="${2:-0}"; shift 2 ;;
    --kind) kind="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done
dir="$(ls_dir)"
# c: drop every C0/DEL/C1 code point INSIDE a field so a hostile value can never
# split or forge a table row; every emitted line then passes lib.sh ls_sanitize
# (bidi + invalid UTF-8 + cap) — the one shared sanitiser.
JQ='
  def c: tostring | explode | map(select(. >= 32 and (. < 127 or . > 159))) | implode;
  def pad(n): (c + ("                                                  ")) | .[0:n];
  "label-sync  seq=\(.seq | c)  active=\(.active.alias // "?" | c)/\(.active.model // "?" | c)/\(.active.effort // "?" | c)  entities=\(.entities | length)",
  ( .entities | map(select($kind == "" or .kind == $kind)) | group_by(.alias // "") | .[]
    | "== alias: \(if (.[0].alias // "") == "" then "?" else (.[0].alias | c) end)  (\(length))",
      ( .[] | "   " + (.id | pad(30)) + " " + (.kind | pad(8)) + " " + (.state | pad(8)) + " " + (.label | c)
              + (if .stale then " [stale]" else "" end) ) )'
draw() {
  local out line
  if [ -r "$dir/snapshot.json" ] && out="$(jq -r --arg kind "$kind" "$JQ" "$dir/snapshot.json" 2>/dev/null)"; then
    while IFS= read -r line || [ -n "$line" ]; do      # last line may lack a newline
      ls_sanitize_into line "$line" 1024; printf '%s\n' "$line"
    done <<<"$out"
  else
    ls_sanitize_into line "label-sync: no readable snapshot in $dir" 1024; printf '%s\n' "$line"
  fi
}
last="" frames=0 t0=$SECONDS first=1
while :; do
  s=""; { read -r s <"$dir/seq"; } 2>/dev/null
  if [ "$first" = 1 ] || [ "$s" != "$last" ]; then
    first=0; last="$s"
    [ -z "$once" ] && [ -t 1 ] && printf '\033[H\033[2J'
    draw
    frames=$((frames+1))
  fi
  [ -n "$once" ] && break
  [ "$iters" -gt 0 ] && [ "$frames" -ge "$iters" ] && break
  [ "$tmo" -gt 0 ] && [ $((SECONDS - t0)) -ge "$tmo" ] && break
  sleep "$(printf '0.%03d' "$ms" 2>/dev/null | sed 's/^0\.\([0-9]\{3\}\)$/0.\1/')" 2>/dev/null || sleep 0.2
done
exit 0
