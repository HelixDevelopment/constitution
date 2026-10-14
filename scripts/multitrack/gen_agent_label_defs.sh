#!/usr/bin/env bash
# =============================================================================
# gen_agent_label_defs.sh — generate the §11.4.182 / §11.4.231(F) agent-type
#   label definitions: one Claude Code custom agent per selected (model, effort),
#   named exactly T<N>-<branch>-<alias>-<model>-<effort>
#   (e.g. T1-main-claude5-opus-xhigh).
#
# Purpose : the agents list shows only "<subagent_type>  <live progress>", so the
#   work-stream label (track, branch, Claude Toolkit alias, model, effort) is
#   baked into the agent TYPE NAME. The definition SETS model and effort in its
#   frontmatter. HONEST BOUNDARY (§11.4.6): on the current platform a
#   per-invocation `model` / `effort` parameter overrides the frontmatter and
#   CLAUDE_CODE_EFFORT_LEVEL overrides both; the §11.4.182 guard hook flags such
#   overrides for these types (WARN; BLOCK under AGENT_TYPE_LABEL_ENFORCE=1) — it
#   is the guard, not this file, that keeps the name honest.
# Usage   : gen_agent_label_defs.sh --track <N> --branch <name> --alias <alias>
#             --out-dir <dir> [--types m-e,m-e,...|--all-types]
#             [--colors-file <tsv>] [--check] [--dry-run] [--print-names]
#           gen_agent_label_defs.sh --classify <file>   (prints absent|handmade|edited|genuine)
#           gen_agent_label_defs.sh --owner-alias <file> (prints the alias that owns a
#             generated v2 file, read from its description label; empty for a
#             hand-made, v1 or absent file — used by the installer's prune rule)
#   Default types: sonnet-medium,sonnet-high,opus-high,opus-xhigh (AL_DEFAULT_TYPES);
#   --all-types: the full 2 x 5 ladder.
# Inputs  : the flags above; agent_label_colors.tsv beside this script (DATA:
#   track -> colour, "*" = default); agent_label_lib.sh (shared naming rules).
#   The alias is NEVER guessed: '?' or a value that sanitises to empty is
#   refused (exit 2).
# Outputs : <out-dir>/<name>.md files (frontmatter + generated marker line +
#   short worker preamble). Deterministic on every locale (LC_ALL=C), no
#   timestamps, idempotent (rerun = byte-identical).
#   --check      : write nothing; exit 1 on missing / stale / hand-edited / extra
#                  generated files for this track+branch+alias prefix.
#   --dry-run    : write nothing; print the plan.
#   --print-names: print the desired file names, one per line; write nothing.
# Exit codes: 0 ok · 1 drift (--check) · 2 usage (incl. unknown alias, a name
#   that fails validation or exceeds AL_NAME_MAX) · 3 a target exists and is
#   HAND-MADE (no marker) — refused, nothing written · 4 a target is a generated
#   file that was HAND-EDITED (front matter or body) — refused, nothing written
#   · 5 internal error · 7 bash older than 4 (needs associative arrays).
# Generated-file form (the marker is the line right AFTER the closing ---):
#     ---
#     name / description / model / effort / color
#     ---
#     <!-- generated-by: gen_agent_label_defs.sh v2 (...); content-sha256: <hex>; ... -->
#     <body>
#   content-sha256 covers the frontmatter block + the body (not the marker line).
#   v1 markers (round-1 files, no alias segment) are still RECOGNISED by
#   --classify so the installer can prune them; they are never written.
# Side-effects: writes only inside --out-dir (temp file + rename); never deletes.
# Deps    : bash >= 4, sha256sum, sed, awk, tr, grep, cmp.
#   Test hook: AGENT_LABEL_BASH_MAJOR=<n> simulates another bash major version.
# Cross-refs: §11.4.182 clause (8), §11.4.231 (F.5), §11.4.209, §11.4.211,
#   §11.4.177, §11.4.201, gate CM-AGENT-TYPE-LABEL, docs/scripts/gen_agent_label_defs.md.
# Classification: universal (§11.4.17) — no project literal.
# =============================================================================
set -uo pipefail
export LC_ALL=C

if [ "${AGENT_LABEL_BASH_MAJOR:-${BASH_VERSINFO[0]}}" -lt 4 ]; then
  echo "gen_agent_label_defs: needs bash >= 4 (associative arrays); this is bash ${BASH_VERSION:-?} — nothing generated" >&2
  exit 7
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=agent_label_lib.sh disable=SC1091 # sibling library path resolved at runtime from the script directory
. "$HERE/agent_label_lib.sh" || { echo "gen_agent_label_defs: cannot load agent_label_lib.sh" >&2; exit 5; }
COLORS_ALLOWED=(red blue green yellow purple orange pink cyan)

# --- classify <file>: absent | handmade | edited | genuine
classify() {
  local f="$1" k mk want got
  [ -e "$f" ] || { echo absent; return; }
  [ "$(sed -n 1p "$f" 2>/dev/null)" = "---" ] || { echo handmade; return; }
  k="$(awk 'NR>1 && $0=="---" {print NR; exit}' "$f")"
  [ -n "$k" ] || { echo handmade; return; }
  mk="$(sed -n "$((k+1))p" "$f")"
  if ! [[ "$mk" =~ $AL_MARK_RE ]]; then echo handmade; return; fi
  want="${BASH_REMATCH[1]}"
  got="$({ sed -n "1,${k}p" "$f"; sed -n "$((k+2)),\$p" "$f"; } | sha256sum | cut -d' ' -f1)"
  if [ "$want" = "$got" ]; then echo genuine; else echo edited; fi
}

# --- owner-alias <file>: the alias label text of a generated (genuine or edited) v2 file
owner_alias() {
  local f="$1" k mk d
  case "$(classify "$f")" in genuine|edited) ;; *) return 0 ;; esac
  k="$(awk 'NR>1 && $0=="---" {print NR; exit}' "$f")"
  mk="$(sed -n "$((k+1))p" "$f")"
  case "$mk" in *'gen_agent_label_defs.sh v2 '*) ;; *) return 0 ;; esac
  d="$(sed -n "2,$((k-1))p" "$f" | sed -n 's/^description: "(T[0-9][0-9]*\/[^ ]* - \([^ ]*\) - \(sonnet\|opus\) - [a-z]*).*/\1/p' | head -n1)"
  printf '%s' "$d"
}

track=""; branch=""; alias_in=""; alias_set=0; out_dir=""; types="$AL_DEFAULT_TYPES"
colors_file="$HERE/agent_label_colors.tsv"; do_check=0; dry=0; print_names=0

usage() { sed -n '2,56p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; }
die2() { echo "gen_agent_label_defs: $*" >&2; exit 2; }
# need_val <argc> <option> <value>: one rule for every option taking a value (missing, empty or
# starting with '-' -> exit 2 naming the option; a path starting with '-' can be given as ./-name)
need_val() { if [ "$1" -lt 2 ] || ! al_value_ok "$3"; then die2 "$2 needs a value (got '${3-<missing>}'; a value may not be empty or start with '-')"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --track)       need_val $# --track "${2-}"; track="$2"; shift 2 ;;
    --branch)      need_val $# --branch "${2-}"; branch="$2"; shift 2 ;;
    --alias)       need_val $# --alias "${2-}"; alias_in="$2"; alias_set=1; shift 2 ;;
    --out-dir)     need_val $# --out-dir "${2-}"; out_dir="$2"; shift 2 ;;
    --types)       need_val $# --types "${2-}"; types="$2"; shift 2 ;;
    --all-types)   types="$AL_ALL_TYPES"; shift ;;
    --colors-file) need_val $# --colors-file "${2-}"; colors_file="$2"; shift 2 ;;
    --classify)    need_val $# --classify "${2-}"; classify "$2"; exit 0 ;;
    --owner-alias) need_val $# --owner-alias "${2-}"; owner_alias "$2"; echo; exit 0 ;;
    --check)       do_check=1; shift ;;
    --dry-run)     dry=1; shift ;;
    --print-names) print_names=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die2 "unknown argument '$1'" ;;
  esac
done

track="$(al_norm_track "$track")" || die2 "--track must be a decimal number"
[ -n "$branch" ]  || die2 "--branch is required"
[ -n "$out_dir" ] || die2 "--out-dir is required"
al_path_ok "$out_dir" || die2 "--out-dir contains a control character; refused (nothing written)"
[ "$alias_set" -eq 1 ] || die2 "--alias is required (the live Claude Toolkit alias, e.g. from track_branch_label.sh)"
case "$alias_in" in
  '?'|'') die2 "alias '${alias_in}' is unknown; refusing to generate (an alias is never guessed, §11.4.6)" ;;
esac

san_b="$(al_sanitise "$branch")"; [ -n "$san_b" ] || die2 "branch sanitises to an empty name"
san_a="$(al_sanitise "$alias_in")"; [ -n "$san_a" ] || die2 "alias '${alias_in}' sanitises to an empty name"
label_branch="$(al_label_text "$branch")"
label_alias="$(al_label_text "$alias_in")"
prefix="T${track}-${san_b}-${san_a}-"

# --- type list -> ordered unique (model effort) pairs
TYPE_LIST=()
IFS=',' read -r -a _raw <<<"$types"
for t in "${_raw[@]}"; do
  t="${t// /}"; [ -n "$t" ] || continue
  m="${t%%-*}"; e="${t#*-}"
  case " $AL_MODELS " in *" $m "*) ;; *) die2 "type '$t': model '$m' not in {${AL_MODELS// /,}}" ;; esac
  case " $AL_EFFORTS " in *" $e "*) ;; *) die2 "type '$t': effort '$e' not in {${AL_EFFORTS// /,}}" ;; esac
  dup=0; for x in "${TYPE_LIST[@]:-}"; do [ "$x" = "$m-$e" ] && dup=1; done
  [ "$dup" -eq 1 ] || TYPE_LIST+=("$m-$e")
done
[ "${#TYPE_LIST[@]}" -gt 0 ] || die2 "--types is empty"

# --- every name is validated BEFORE anything is written (AL-6)
for t in "${TYPE_LIST[@]}"; do
  n="${prefix}${t}"
  if [ "${#n}" -gt "$AL_NAME_MAX" ]; then die2 "type name too long (${#n} > ${AL_NAME_MAX} chars): ${n:0:60}... — shorten the branch or alias; names are never truncated"; fi
  al_name_ok "$n" || die2 "type name '$n' fails validation"
done

if [ "$print_names" -eq 1 ]; then
  for t in "${TYPE_LIST[@]}"; do echo "${prefix}${t}.md"; done
  exit 0
fi

# --- colour by track (DATA file)
[ -r "$colors_file" ] || { echo "gen_agent_label_defs: colours file unreadable: $colors_file" >&2; exit 2; }
color="$(awk -F'\t' -v t="$track" '/^#/ || NF<2 {next} $1==t {print $2; f=1; exit} $1=="*" {d=$2} END{ if(!f && d!="") print d }' "$colors_file")"
okc=0; for c in "${COLORS_ALLOWED[@]}"; do [ "$c" = "$color" ] && okc=1; done
[ "$okc" -eq 1 ] || { echo "gen_agent_label_defs: colour '${color}' for track $track not in the supported set" >&2; exit 2; }

cap() { case "$1" in sonnet) echo Sonnet ;; opus) echo Opus ;; *) echo "$1" ;; esac; }

# --- render <model> <effort>: the full expected file content on stdout
render() {
  local m="$1" e="$2" fm body hash lbl
  lbl="T${track}/${label_branch} - ${label_alias} - ${m} - ${e}"
  fm="$(printf -- '---\nname: %s\ndescription: "(%s) Worker for T%s/%s via alias %s, %s at %s effort."\nmodel: %s\neffort: %s\ncolor: %s\n---' \
    "${prefix}${m}-${e}" "$lbl" "$track" "$label_branch" "$label_alias" "$(cap "$m")" "$e" "$m" "$e" "$color")"
  body="$(printf 'You are a worker agent for track T%s, branch %s, Claude Toolkit alias %s, on %s at %s effort.\nFollow the dispatching prompt exactly and stay inside its scope. Report concrete evidence (commands run, outputs, file paths), never narrated success. Do not commit, push, tag or change shared state unless the prompt says so.\nModel and effort come from this definition unless the dispatch passes its own model or effort, or CLAUDE_CODE_EFFORT_LEVEL is set; the 11.4.182 label guard flags such overrides (WARN; BLOCK under AGENT_TYPE_LABEL_ENFORCE=1).' \
    "$track" "$label_branch" "$label_alias" "$(cap "$m")" "$e")"
  if [ "$m" = opus ] && [ "$e" = xhigh ]; then
    body="$body
This type is the 11.4.209 code-review and 11.4.211 merge-conflict substrate (Opus at xhigh effort) when dispatched without overrides. Act as a structurally separate verifier, never as the author of the work under review."
  fi
  hash="$({ printf '%s\n' "$fm"; printf '%s\n' "$body"; } | sha256sum | cut -d' ' -f1)"
  printf '%s\n' "$fm"
  printf '<!-- generated-by: gen_agent_label_defs.sh v2 (constitution 11.4.182/11.4.231(F)); content-sha256: %s; regenerate with the generator, do not edit -->\n' "$hash"
  printf '%s\n' "$body"
}

TMPS=()
# shellcheck disable=SC2329 # invoked indirectly through the EXIT trap
cleanup() { local t; for t in "${TMPS[@]:-}"; do [ -n "$t" ] && rm -f "$t"; done; }
trap cleanup EXIT

declare -A STATE
nhand=0; nedit=0; ndrift=0
for t in "${TYPE_LIST[@]}"; do
  f="$out_dir/${prefix}${t}.md"
  case "$(classify "$f")" in
    absent)   STATE[$t]="absent" ;;
    handmade) STATE[$t]="handmade"; nhand=$((nhand+1)) ;;
    edited)   STATE[$t]="edited";   nedit=$((nedit+1)) ;;
    genuine)  if render "${t%%-*}" "${t#*-}" | cmp -s - "$f"; then STATE[$t]="same"; else STATE[$t]="stale"; fi ;;
  esac
done

# extra generated files for this track+branch+alias prefix (check mode)
EXTRA=()
if [ -d "$out_dir" ]; then
  shopt -s nullglob
  for f in "$out_dir/${prefix}"*.md; do
    b="${f##*/}"; rest="${b#"$prefix"}"; rest="${rest%.md}"
    [[ "$rest" =~ ^(sonnet|opus)-(low|medium|high|xhigh|max)$ ]] || continue
    inset=0; for t in "${TYPE_LIST[@]}"; do [ "$t" = "$rest" ] && inset=1; done
    [ "$inset" -eq 1 ] && continue
    case "$(classify "$f")" in genuine|edited) EXTRA+=("$f") ;; esac   # hand-made files are never "extra"
  done
  shopt -u nullglob
fi

if [ "$do_check" -eq 1 ]; then
  for t in "${TYPE_LIST[@]}"; do
    case "${STATE[$t]}" in
      same) echo "OK       ${prefix}${t}.md" ;;
      *)    echo "DRIFT    ${prefix}${t}.md (${STATE[$t]})"; ndrift=$((ndrift+1)) ;;
    esac
  done
  for f in "${EXTRA[@]:-}"; do [ -n "$f" ] && { echo "DRIFT    ${f##*/} (extra generated file)"; ndrift=$((ndrift+1)); }; done
  echo "gen_agent_label_defs: --check ${prefix%-}: ${#TYPE_LIST[@]} expected, ${ndrift} drift"
  [ "$ndrift" -eq 0 ] && exit 0 || exit 1
fi

# write / dry-run: refuse before touching anything
if [ "$nhand" -gt 0 ] || [ "$nedit" -gt 0 ]; then
  for t in "${TYPE_LIST[@]}"; do
    case "${STATE[$t]}" in
      handmade) echo "REFUSE   ${prefix}${t}.md exists and is HAND-MADE (no generated marker); not overwriting" >&2 ;;
      edited)   echo "REFUSE   ${prefix}${t}.md is a generated file that was HAND-EDITED (hash mismatch); not overwriting" >&2 ;;
    esac
  done
  [ "$nhand" -gt 0 ] && exit 3
  exit 4
fi

nw=0; nu=0
for t in "${TYPE_LIST[@]}"; do
  f="$out_dir/${prefix}${t}.md"
  case "${STATE[$t]}" in
    same) echo "UNCHANGED ${f##*/}"; nu=$((nu+1)) ;;
    absent|stale)
      if [ "$dry" -eq 1 ]; then echo "PLAN     ${f##*/} (${STATE[$t]})"; nw=$((nw+1)); continue; fi
      mkdir -p "$out_dir" || { echo "gen_agent_label_defs: cannot create $out_dir" >&2; exit 5; }
      tmp="$out_dir/.${f##*/}.tmp.$$"; TMPS+=("$tmp")
      render "${t%%-*}" "${t#*-}" >"$tmp" || { echo "gen_agent_label_defs: render failed for ${f##*/}" >&2; exit 5; }
      mv -f "$tmp" "$f" || { echo "gen_agent_label_defs: cannot place ${f##*/}" >&2; exit 5; }
      echo "WROTE    ${f##*/} (${STATE[$t]})"; nw=$((nw+1)) ;;
  esac
done
echo "gen_agent_label_defs: ${prefix%-}: ${#TYPE_LIST[@]} definitions, written=${nw} unchanged=${nu}$([ "$dry" -eq 1 ] && echo ' (dry-run)')"
exit 0
