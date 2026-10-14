#!/usr/bin/env bash
# =============================================================================
# gen_agent_label_defs.sh — generate the §11.4.182 / §11.4.231(F) agent-type
#   label definitions: one Claude Code custom agent per (model x effort),
#   named exactly T<N>-<sanitised-branch>-<model>-<effort>.
#
# Purpose : the agents list shows only "<subagent_type>  <live progress>", so the
#   work-stream label is baked into the agent TYPE NAME. The definition also
#   ENFORCES model and effort (frontmatter `model:` / `effort:`), closing the
#   per-agent effort gap by construction. T<N>-<branch>-opus-xhigh is the
#   §11.4.209 reviewer / §11.4.211 merge-conflict substrate.
# Usage   : gen_agent_label_defs.sh --track <N> --branch <name> --out-dir <dir>
#             [--models sonnet,opus] [--efforts low,medium,high,xhigh,max]
#             [--colors-file <tsv>] [--check] [--dry-run]
#           gen_agent_label_defs.sh --classify <file>   (prints absent|handmade|edited|genuine)
# Inputs  : the flags above; agent_label_colors.tsv beside this script (DATA:
#   track -> colour, "*" = default).
# Outputs : <out-dir>/T<N>-<branch>-<model>-<effort>.md files (frontmatter +
#   generated marker line + short project-agnostic worker preamble). Output is
#   deterministic (no timestamps) and idempotent (rerun = byte-identical).
#   --check : write nothing; exit 1 on missing / stale / hand-edited / extra
#             generated files for this track+branch prefix.
#   --dry-run: write nothing; print the plan.
# Exit codes: 0 ok · 1 drift (--check) · 2 usage · 3 a target exists and is
#   HAND-MADE (no generated marker) — refused, nothing written · 4 a target is a
#   generated file that was HAND-EDITED (hash mismatch) — refused, nothing
#   written · 5 internal error.
# Generated-file form (marker is AFTER the closing --- so frontmatter parsing
#   cannot be affected):
#     ---
#     name: ... / description: "..." / model: ... / effort: ... / color: ...
#     ---
#     <!-- generated-by: gen_agent_label_defs.sh v1 (...); content-sha256: <hex>; ... -->
#     <body>
#   content-sha256 covers the frontmatter block + the body (not the marker line).
# Side-effects: writes only inside --out-dir (atomic temp+rename); never deletes.
# Deps    : bash, sha256sum, sed, awk, tr, cmp.
# Cross-refs: §11.4.182, §11.4.231(F), §11.4.209, §11.4.211, §11.4.177 (inherited
#   by reference), §11.4.201 (refuses on unresolvable state), gate
#   CM-AGENT-TYPE-LABEL, docs/scripts/gen_agent_label_defs.md.
# Classification: universal (§11.4.17) — no project literal.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MODELS_ALLOWED=(sonnet opus)
EFFORTS_ALLOWED=(low medium high xhigh max)
COLORS_ALLOWED=(red blue green yellow purple orange pink cyan)

# --- classify <file>: absent | handmade | edited | genuine
MARK_RE='^<!-- generated-by: gen_agent_label_defs\.sh v1 .*content-sha256: ([0-9a-f]{64});'
classify() {
  local f="$1" k mk want got
  [ -e "$f" ] || { echo absent; return; }
  [ "$(sed -n 1p "$f" 2>/dev/null)" = "---" ] || { echo handmade; return; }
  k="$(awk 'NR>1 && $0=="---" {print NR; exit}' "$f")"
  [ -n "$k" ] || { echo handmade; return; }
  mk="$(sed -n "$((k+1))p" "$f")"
  if ! [[ "$mk" =~ $MARK_RE ]]; then echo handmade; return; fi
  want="${BASH_REMATCH[1]}"
  got="$({ sed -n "1,${k}p" "$f"; sed -n "$((k+2)),\$p" "$f"; } | sha256sum | cut -d' ' -f1)"
  if [ "$want" = "$got" ]; then echo genuine; else echo edited; fi
}


track=""; branch=""; out_dir=""; models="sonnet,opus"; efforts="low,medium,high,xhigh,max"
colors_file="$HERE/agent_label_colors.tsv"; do_check=0; dry=0

usage() { sed -n '2,41p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; }
die2() { echo "gen_agent_label_defs: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --track)       [ $# -ge 2 ] || die2 "--track needs a value"; track="$2"; shift 2 ;;
    --branch)      [ $# -ge 2 ] || die2 "--branch needs a value"; branch="$2"; shift 2 ;;
    --out-dir)     [ $# -ge 2 ] || die2 "--out-dir needs a value"; out_dir="$2"; shift 2 ;;
    --models)      [ $# -ge 2 ] || die2 "--models needs a value"; models="$2"; shift 2 ;;
    --efforts)     [ $# -ge 2 ] || die2 "--efforts needs a value"; efforts="$2"; shift 2 ;;
    --colors-file) [ $# -ge 2 ] || die2 "--colors-file needs a value"; colors_file="$2"; shift 2 ;;
    --classify)    [ $# -ge 2 ] || die2 "--classify needs a file"; classify "$2"; exit 0 ;;
    --check)       do_check=1; shift ;;
    --dry-run)     dry=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die2 "unknown argument '$1'" ;;
  esac
done

case "$track" in ''|*[!0-9]*) die2 "--track must be a decimal number (got '${track}')" ;; esac
[ -n "$branch" ]  || die2 "--branch is required"
[ -n "$out_dir" ] || die2 "--out-dir is required"

in_set() { # value set...
  local v="$1"; shift; local x
  for x in "$@"; do [ "$x" = "$v" ] && return 0; done
  return 1
}
split_list() { printf '%s' "$1" | tr ',' ' '; }
read -r -a MODEL_LIST <<<"$(split_list "$models")"
read -r -a EFFORT_LIST <<<"$(split_list "$efforts")"
[ "${#MODEL_LIST[@]}" -gt 0 ]  || die2 "--models is empty"
[ "${#EFFORT_LIST[@]}" -gt 0 ] || die2 "--efforts is empty"
for m in "${MODEL_LIST[@]}";  do in_set "$m" "${MODELS_ALLOWED[@]}" || die2 "model '$m' not in {sonnet,opus}"; done
for e in "${EFFORT_LIST[@]}"; do in_set "$e" "${EFFORTS_ALLOWED[@]}" || die2 "effort '$e' not in {low,medium,high,xhigh,max}"; done

# --- branch sanitisation: lowercase, '/'->'-', only [a-z0-9-], collapsed, trimmed
san="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]' | sed -e 's#/#-#g' -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
[ -n "$san" ] || die2 "branch '$branch' sanitises to an empty name"
# label branch text: the raw branch only when it is plain; otherwise the sanitised form
case "$branch" in
  *[!A-Za-z0-9._/-]*) label_branch="$san" ;;
  *)                  label_branch="$branch" ;;
esac
case "$label_branch" in *' '*|*')'*|*'"'*|*"\\"*) label_branch="$san" ;; esac

# --- colour by track (DATA file)
[ -r "$colors_file" ] || { echo "gen_agent_label_defs: colours file unreadable: $colors_file" >&2; exit 2; }
color="$(awk -F'\t' -v t="$track" '/^#/ || NF<2 {next} $1==t {print $2; f=1; exit} $1=="*" {d=$2} END{ if(!f && d!="") print d }' "$colors_file")"
in_set "$color" "${COLORS_ALLOWED[@]}" || { echo "gen_agent_label_defs: colour '${color}' for track $track not in the supported set" >&2; exit 2; }

cap() { case "$1" in sonnet) echo Sonnet ;; opus) echo Opus ;; *) echo "$1" ;; esac; }

# --- render <model> <effort>: the full expected file content on stdout
render() {
  local m="$1" e="$2" name fm body hash
  name="T${track}-${san}-${m}-${e}"
  fm="$(printf -- '---\nname: %s\ndescription: "(T%s/%s - <alias> - %s - %s) T%s/%s worker on %s at %s effort. The work-stream label is baked into this agent type and model and effort are enforced by this definition (constitution 11.4.182, 11.4.231(F)). The Agent description must still carry the live label and the item id."\nmodel: %s\neffort: %s\ncolor: %s\n---' \
    "$name" "$track" "$label_branch" "$m" "$e" "$track" "$label_branch" "$(cap "$m")" "$e" "$m" "$e" "$color")"
  body="$(printf 'You are a worker agent for track T%s, branch %s, running on %s at %s effort. The model and the effort are enforced by this agent definition.\nFollow the dispatching prompt exactly and stay inside its scope. Report concrete evidence (commands run, outputs, file paths), never narrated success. Do not commit, push, tag or change shared state unless the prompt says so.' \
    "$track" "$label_branch" "$(cap "$m")" "$e")"
  if [ "$m" = opus ] && [ "$e" = xhigh ]; then
    body="$body
This type is the independent code-review (11.4.209) and merge-conflict-resolution (11.4.211) substrate: Opus at xhigh effort, enforced by construction. Act as a structurally separate verifier, never as the author of the work under review."
  fi
  hash="$({ printf '%s\n' "$fm"; printf '%s\n' "$body"; } | sha256sum | cut -d' ' -f1)"
  printf '%s\n' "$fm"
  printf '<!-- generated-by: gen_agent_label_defs.sh v1 (constitution 11.4.182/11.4.231(F)); content-sha256: %s; regenerate with the generator, do not edit -->\n' "$hash"
  printf '%s\n' "$body"
}

TMPS=()
# shellcheck disable=SC2329 # this function is invoked indirectly through the EXIT trap handler
cleanup() { local t; for t in "${TMPS[@]:-}"; do [ -n "$t" ] && rm -f "$t"; done; }
trap cleanup EXIT

declare -A STATE
TARGETS=()
for m in "${MODEL_LIST[@]}"; do
  for e in "${EFFORT_LIST[@]}"; do
    f="$out_dir/T${track}-${san}-${m}-${e}.md"
    dup=0; for t in "${TARGETS[@]:-}"; do [ "$t" = "$f" ] && dup=1; done
    [ "$dup" -eq 1 ] && continue
    TARGETS+=("$f")
  done
done

# decide each target's state
nhand=0; nedit=0; ndrift=0
for f in "${TARGETS[@]}"; do
  c="$(classify "$f")"
  b="${f##*/}"; b="${b%.md}"; mo="${b#"T${track}-${san}-"}"; mo_m="${mo%%-*}"; mo_e="${mo#*-}"
  case "$c" in
    absent)   STATE[$f]="absent" ;;
    handmade) STATE[$f]="handmade"; nhand=$((nhand+1)) ;;
    edited)   STATE[$f]="edited";   nedit=$((nedit+1)) ;;
    genuine)
      if render "$mo_m" "$mo_e" | cmp -s - "$f"; then STATE[$f]="same"; else STATE[$f]="stale"; fi ;;
  esac
done

# extra generated files for this track+branch prefix (check mode)
EXTRA=()
if [ -d "$out_dir" ]; then
  shopt -s nullglob
  for f in "$out_dir"/T"${track}"-"${san}"-*.md; do
    b="${f##*/}"
    [[ "$b" =~ ^T${track}-${san}-(sonnet|opus)-(low|medium|high|xhigh|max)\.md$ ]] || continue
    inset=0; for t in "${TARGETS[@]}"; do [ "$t" = "$f" ] && inset=1; done
    [ "$inset" -eq 1 ] && continue
    cl="$(classify "$f")"
    case "$cl" in genuine|edited) EXTRA+=("$f") ;; esac   # hand-made files are never "extra"
  done
  shopt -u nullglob
fi

if [ "$do_check" -eq 1 ]; then
  for f in "${TARGETS[@]}"; do
    case "${STATE[$f]}" in
      same) echo "OK       ${f##*/}" ;;
      *)    echo "DRIFT    ${f##*/} (${STATE[$f]})"; ndrift=$((ndrift+1)) ;;
    esac
  done
  for f in "${EXTRA[@]:-}"; do [ -n "$f" ] && { echo "DRIFT    ${f##*/} (extra generated file)"; ndrift=$((ndrift+1)); }; done
  echo "gen_agent_label_defs: --check T${track}/${label_branch}: ${#TARGETS[@]} expected, ${ndrift} drift"
  [ "$ndrift" -eq 0 ] && exit 0 || exit 1
fi

# write / dry-run: refuse before touching anything
if [ "$nhand" -gt 0 ] || [ "$nedit" -gt 0 ]; then
  for f in "${TARGETS[@]}"; do
    case "${STATE[$f]}" in
      handmade) echo "REFUSE   ${f##*/} exists and is HAND-MADE (no generated marker); not overwriting" >&2 ;;
      edited)   echo "REFUSE   ${f##*/} is a generated file that was HAND-EDITED (hash mismatch); not overwriting" >&2 ;;
    esac
  done
  [ "$nhand" -gt 0 ] && exit 3
  exit 4
fi

nw=0; nu=0
for f in "${TARGETS[@]}"; do
  case "${STATE[$f]}" in
    same)
      echo "UNCHANGED ${f##*/}"; nu=$((nu+1)) ;;
    absent|stale)
      b="${f##*/}"; b="${b%.md}"; mo="${b#"T${track}-${san}-"}"
      if [ "$dry" -eq 1 ]; then echo "PLAN     ${f##*/} (${STATE[$f]})"; nw=$((nw+1)); continue; fi
      mkdir -p "$out_dir" || { echo "gen_agent_label_defs: cannot create $out_dir" >&2; exit 5; }
      tmp="$out_dir/.${f##*/}.tmp.$$"; TMPS+=("$tmp")
      render "${mo%%-*}" "${mo#*-}" >"$tmp" || { echo "gen_agent_label_defs: render failed for ${f##*/}" >&2; exit 5; }
      mv -f "$tmp" "$f" || { echo "gen_agent_label_defs: cannot place ${f##*/}" >&2; exit 5; }
      echo "WROTE    ${f##*/} (${STATE[$f]})"; nw=$((nw+1)) ;;
  esac
done
echo "gen_agent_label_defs: T${track}/${label_branch}: ${#TARGETS[@]} definitions, written=${nw} unchanged=${nu}$([ "$dry" -eq 1 ] && echo ' (dry-run)')"
exit 0
