#!/usr/bin/env bash
# scripts/hooks/guard-track-branch-label.sh
#
# Claude Code PreToolUse guard hook (mechanical block) enforcing constitution
# §11.4.182 (track+branch[+alias[+model]] work-stream labeling), which
# composes §11.4.178 (track-qualified identity). Every agent / subagent /
# work-stream dispatch MUST carry a `(T<N>/<branch> - <alias>[ - <model>])`
# label prefix on its description so multi-track work (/mnt/track1..4) is
# never ambiguous — and enforcement MUST be independent of any agent's recall
# (§11.4.109-class anti-forgetting hook: a rule the orchestrator forgets to
# paste is not enforcement).
#
# CONTRACT (Claude Code PreToolUse hook):
#   - Receives the tool invocation as JSON on stdin.
#   - Exit 0  -> allow (Claude proceeds).
#   - Exit 2  -> BLOCK; stderr text is fed back to Claude as the refusal reason.
#   - Any other exit -> non-blocking error (never used).
#
# SCOPE: only the agent-dispatching tools carry a work-stream label:
#   tool_name in { Agent, Task, TaskCreate }.
#   For those, the `description` (or, as a fallback, a `subagent` label) MUST
#   START with ONE of the 3-field legacy form `^\(T[0-9]+/[^)]+ - [^)]+\) `
#   (e.g. `(T1/main - claude1) ATM-312 ...`), the 4-field form
#   `^\(T[0-9]+/[^)]+ - [^)]+ - [^)]+\) ` (e.g.
#   `(T1/main - claude1 - opus) ATM-312 ...`), OR the 5-field form the reference
#   labeler now emits, `^\(T[0-9]+/[^)]+ - [^)]+ - [^)]+ - [^)]+\) ` (e.g.
#   `(T1/main - claude1 - opus - high) ATM-312 ...`) — ALL THREE accepted so an
#   already-in-flight dispatcher using the pre-model-field or pre-effort-field
#   labeler is never blocked during migration (§11.4.6 — an honest `?` model or
#   `?` effort, or NO model/effort field at all, is a valid label, never a
#   block-cause; mirrors §11.4.182's existing honest-`?` rule for track/alias —
#   EXCEPT that a dispatch using a generated label agent type must state that
#   type's model/effort, see the AGENT-TYPE CHECK below).
#   Missing / malformed label -> exit 2 with the expected form + how to fix.
#   EVERY OTHER tool passes through untouched (exit 0) — this hook never breaks
#   non-agent tools.
#
# ALIAS-CORRECTNESS (§11.4.182): a format-valid label is NOT sufficient — the
#   label's `<alias>` field (the SECOND field — always the field immediately
#   after the track/branch segment, REGARDLESS of whether a 3rd `<model>`
#   field follows it) MUST match the LIVE alias derived from CLAUDE_CONFIG_DIR
#   (basename `.claude-<alias>` -> `<alias>`). A hand-typed / remembered /
#   STALE alias (e.g. `claude4` while the live session is `claude3`) is
#   BLOCKED (exit 2) with the CORRECT label printed. The live alias is derived
#   by CALLING the reference labeler (scripts/multitrack/track_branch_label.sh)
#   — the single source of truth, so the derivation regex is never duplicated
#   here (DRY). Honest boundary (§11.4.6): a `?` on EITHER side — the live
#   alias genuinely unknown (CLAUDE_CONFIG_DIR unset) OR the caller honestly
#   declaring `?` — is ACCEPTED; the hook only BLOCKS a CONCRETE alias that
#   provably disagrees with a KNOWN live alias, never a fabricated verdict.
#   The `<model>` and `<effort>` fields (when present) are NEVER cross-checked
#   against a "live" value here — a model/effort can legitimately switch mid-turn (§11.4.6: no guard
#   asserts a condition it cannot resolve authoritatively at dispatch time;
#   the labeler's own model derivation already documents its honest
#   limitations — see track_branch_label.sh header, CASE A).
#
# AGENT-TYPE CHECK (§11.4.182 (8) / §11.4.231 (F.5), 2026-10-15): see _type_check
#   below — WARN by default (exit 0 + additionalContext), BLOCK with
#   AGENT_TYPE_LABEL_ENFORCE=1: a catch-all dispatch while GENERATED
#   T<N>-<branch>-<alias>-<model>-<effort> types exist for the label's identity, a
#   label type that disagrees with the label, or a per-dispatch model/effort /
#   CLAUDE_CODE_EFFORT_LEVEL override that would make the type name lie.
#   Specialist and plugin types are never touched; AGENT_TYPE_LABEL_BYPASS=<reason>
#   is an audited bypass.
#
# DECOUPLING (§11.4.177): this hook lives in the constitution submodule and is
# inherited BY REFERENCE (never copied). It is project-agnostic: it validates
# the label FORMAT and derives the expected example from the cwd (`/mnt/trackN`)
# + git directly — it does NOT depend on any project-specific helper path.
#
# Classification: universal.

set -uo pipefail

PAYLOAD="$(cat || true)"

# --------------------------------------------------------------------------
# Extract a JSON string field WITHOUT requiring jq (prefer jq if present).
# Only leaf keys we need: tool_name, description, subagent.
# --------------------------------------------------------------------------
json_field() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | jq -r "$path // empty" 2>/dev/null || true
    return 0
  fi
  local key
  case "$path" in
    .tool_name)               key="tool_name" ;;
    .tool_input.description)  key="description" ;;
    .tool_input.subagent)     key="subagent" ;;
    *)                        key="${path##*.}" ;;
  esac
  printf '%s' "$PAYLOAD" | awk -v key="$key" '
    BEGIN { RS="\0" }
    {
      s = $0
      idx = index(s, "\"" key "\"")
      if (idx == 0) { exit }
      rest = substr(s, idx + length(key) + 2)
      sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") { exit }
      rest = substr(rest, 2)
      out = ""
      i = 1
      n = length(rest)
      while (i <= n) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          nx = substr(rest, i+1, 1)
          if (nx == "n") out = out "\n"
          else if (nx == "t") out = out "\t"
          else if (nx == "r") out = out "\r"
          else if (nx == "\"") out = out "\""
          else if (nx == "\\") out = out "\\"
          else if (nx == "/") out = out "/"
          else out = out nx
          i += 2
          continue
        }
        if (c == "\"") break
        out = out c
        i += 1
      }
      printf "%s", out
    }
  '
}

TOOL_NAME="$(json_field .tool_name)"

# Only the agent-dispatching tools carry a work-stream label. Anything else is
# allowed untouched.
case "$TOOL_NAME" in
  Agent|Task|TaskCreate) ;;
  *) exit 0 ;;
esac

# The label lives on `description`; fall back to a `subagent` label if present.
LABEL="$(json_field .tool_input.description)"
if [[ -z "$LABEL" ]]; then
  LABEL="$(json_field .tool_input.subagent)"
fi

# The required prefix: (T<N>/<branch> - <alias>[ - <model>[ - <effort>]]) followed
# by a single space. §11.4.182 mandates the alias component — the claude-toolkit
# alias in use — so parallel-track work (each track driven by a DISTINCT
# alias) is never ambiguous; the OPTIONAL trailing <model> field records which
# model is currently answering for that alias (native short-name or provider
# real model id — see track_branch_label.sh), and the OPTIONAL <effort> field
# (added 2026-07-26 per §11.4.231 clause (F)) records the reasoning-effort setting
# in force. Track MAY be '?' (honest when not on a /mnt/trackN path — §11.4.6);
# alias MAY be '?' (honest when CLAUDE_CONFIG_DIR is unset / non-matching); model
# and effort MAY be '?' or simply ABSENT (3-field / 4-field legacy forms) — all
# accepted, none is ever a block-cause here (the AGENT-TYPE CHECK below flags a '?'
# model/effort only for a dispatch using a generated label type). The regex admits AT LEAST the 3-, 4-, and
# 5-field forms via the 0/1/2 optional " - <field>" segments after the alias
# ({0,2}); because each field atom is [^)]+ (which itself matches ' - '), a label
# carrying MORE than 5 fields ALSO matches — permissive by design, an extra field
# is never a block-cause, and the positional alias-correctness check below reads
# the alias field (the one immediately after the track/branch segment) regardless
# of how many trailing fields follow. NOTE the atom is intentionally NOT tightened
# to a dash-excluding class ([^)-]): branch names AND aliases legitimately contain
# '-' (e.g. `feature/mistiq-vader`, `kimi-for-coding`), which such a class would
# wrongly REJECT (a §11.4.201(1) false-positive refusal).
LABEL_RE='^\(T([0-9]+|\?)/[^)]+ - [^)]+( - [^)]+){0,2}\) '

# --------------------------------------------------------------------------
# Canonical label for THIS checkout + session, from the reference labeler
# (scripts/multitrack/track_branch_label.sh) — the SINGLE SOURCE OF TRUTH for
# the T/branch/alias derivation (§11.4.182 / §11.4.177 inherited-by-reference).
# Calling it keeps this hook DRY: the alias-derivation regex lives in ONE place,
# and the same output drives BOTH the alias-correctness check AND the block
# message's "correct label" line.
# --------------------------------------------------------------------------
_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || true)"
[[ -n "$_hook_dir" ]] || _hook_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
_labeler="${_hook_dir}/../multitrack/track_branch_label.sh"

_expected=""
if [[ -r "$_labeler" ]]; then
  _expected="$(bash "$_labeler" 2>/dev/null || true)"
fi
# Defensive fallback (ONLY if the sibling labeler is unreachable): derive the
# track/branch/alias fields inline so the hook always emits an actionable
# message and never exits with a non-0/2 code. This fallback intentionally
# does NOT duplicate the labeler's <model>/<effort> derivation (session-transcript
# / provider-registry / effort-signal lookup, §11.4.182 — kept in ONE place, DRY);
# it honestly reports the model AND effort as '?' (genuinely not derived on this
# path) rather than guess (§11.4.6), so the emitted example stays FORMAT-consistent
# with the primary path's 5-field shape without silently fabricating a value.
if [[ -z "$_expected" ]]; then
  _dir="$(pwd -P 2>/dev/null || pwd)"
  case "$_dir" in
    /mnt/track[0-9]*) _n="${_dir#/mnt/track}"; _n="${_n%%/*}"; case "$_n" in ''|*[!0-9]*) _n='?' ;; esac ;;
    *) _n='?' ;;
  esac
  _br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"; [[ -n "$_br" ]] || _br='?'
  _al='?'
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    _cfgbase="$(basename "$CLAUDE_CONFIG_DIR" 2>/dev/null || true)"
    case "$_cfgbase" in .claude-?*) _al="${_cfgbase#.claude-}" ;; esac
  fi
  _expected="(T${_n}/${_br} - ${_al} - ? - ?)"
fi

# Extract the <alias> field from a
# "(T<N>/<branch> - <alias>[ - <model>]) ..." string: take the parenthesised
# prefix (up to the first ')'), strip the "T<N>/<branch>" segment up to the
# FIRST ' - ' (a git ref name cannot contain a space, so ' - ' inside the
# prefix is unambiguously a field separator), then <alias> is everything
# BEFORE the NEXT ' - ' if one follows (4-field form: alias precedes model)
# or the remainder (3-field legacy form: alias is the last field). This stays
# correct whether or not an optional <model> 3rd field is present — unlike a
# naive "take everything after the LAST ' - '" rule, which would silently
# grab <model> instead of <alias> once dispatchers start emitting 4-field
# labels (§11.4.182 §11.4.6 — the extraction must not regress under the new
# field).
_label_alias() {
  local _pfx="${1%%)*}"
  local _rest
  case "$_pfx" in
    *' - '*) _rest="${_pfx#*' - '}" ;;
    *)       printf '%s' ''; return ;;
  esac
  case "$_rest" in
    *' - '*) printf '%s' "${_rest%%' - '*}" ;;   # 4-field: alias is BEFORE the next ' - '
    *)       printf '%s' "$_rest" ;;              # 3-field: alias is the remainder
  esac
}
_live_alias="$(_label_alias "$_expected")"
_dispatch_alias="$(_label_alias "$LABEL")"

# --------------------------------------------------------------------------
# EFFORT-BLUFF CHECK (§11.4.201 "assert the real condition" applied to the
# §11.4.182/§11.4.231-clause-(F) <effort> field). Extract the trailing
# <effort> field (the 4th ' - '-separated field inside the parens) from BOTH
# the LIVE expected label and the caller's LABEL. Returns EMPTY when the
# label is the 3-field or 4-field legacy form (no effort field present at
# all — that shape is ALWAYS accepted, §11.4.6 honest-boundary: a field that
# was never asked for cannot be a bluff), and returns the literal field text
# ('?' or a real ladder value) when a 4th field IS present. Split on the
# LITERAL ' - ' (space-dash-space) — mirrors _label_alias's rationale: git
# ref names/aliases/models/efforts never legitimately contain that exact
# 3-char sequence, so it is an unambiguous field separator.
# --------------------------------------------------------------------------
_label_effort_field() {
  local _pfx="${1%%)*}"
  local -a _fields=()
  local _rest="$_pfx"
  local _piece
  while [[ "$_rest" == *' - '* ]]; do
    _piece="${_rest%%' - '*}"
    _fields+=("$_piece")
    _rest="${_rest#*' - '}"
  done
  _fields+=("$_rest")
  # _fields[0]="(T<N>/<branch>"  _fields[1]=<alias>  _fields[2]=<model>  _fields[3]=<effort>
  if (( ${#_fields[@]} >= 4 )); then
    printf '%s' "${_fields[3]}"
  else
    printf '%s' ''
  fi
}
_live_effort="$(_label_effort_field "$_expected")"
_dispatch_effort="$(_label_effort_field "$LABEL")"

# --------------------------------------------------------------------------
# AGENT-TYPE CHECK (§11.4.182 (8) / §11.4.231 (F.5), added 2026-10-15). The agents
# list shows only "<subagent_type>  <live progress>", so the work-stream label is
# also baked into GENERATED agent types named T<N>-<branch>-<alias>-<model>-<effort>
# (scripts/multitrack/gen_agent_label_defs.sh). The naming rules come from the
# shared library scripts/multitrack/agent_label_lib.sh (never a second copy).
#   (a) catch-all dispatch — subagent_type empty or in AGENT_TYPE_LABEL_CATCHALL
#       (default "general-purpose claude") — while generated types exist for the
#       label's exact identity (track, branch, alias): WARN, or BLOCK under
#       AGENT_TYPE_LABEL_ENFORCE=1. If generated types exist for the track but
#       only for ANOTHER identity (stale alias / branch), WARN only ("re-run the
#       installer") — a dispatch is never blocked on types it cannot use.
#   (b) a label-shaped subagent_type (T<N>-...-<model>-<effort>) must agree with
#       the dispatch label: same track, same branch + alias prefix, and — when the
#       label carries them — the same model and effort ('?' is not honest for a
#       label type: the type states the value).
#   (c) the type name must not lie: a per-invocation `model` / `effort` on the
#       dispatch, or CLAUDE_CODE_EFFORT_LEVEL in the environment, overrides the
#       definition's frontmatter on the current platform; a value that differs
#       from the type's model / effort is flagged.
# (b)/(c) WARN by default and BLOCK under AGENT_TYPE_LABEL_ENFORCE=1.
# Specialist / plugin types (Explore, Plan, plugin:agent, ...) are NEVER touched.
# AGENT_TYPE_LABEL_BYPASS="<reason>" (non-empty) lets a dispatch through and AUDITS
# the reason on stderr. The WARN payload is JSON-escaped (hostile input safe).
# Honest boundary (§11.4.6): the agent platform loads definitions; a running
# session may not see newly generated types until restart (WARN is the default).
# --------------------------------------------------------------------------
_type_check() {
  case "$TOOL_NAME" in Agent|Task) ;; *) return 0 ;; esac
  local lib="${_hook_dir}/../multitrack/agent_label_lib.sh"
  if [[ ! -r "$lib" ]]; then
    echo "guardrails: NOTE — agent_label_lib.sh not found ($lib); agent-type check skipped" >&2
    return 0
  fi
  # shellcheck source=../multitrack/agent_label_lib.sh disable=SC1091 # library path resolved at runtime from the hook directory
  . "$lib"
  [[ "$LABEL" =~ ^\(T([0-9]+)/ ]] || return 0
  local ltrack lpfx lfields lbranch lalias lmodel leffort
  ltrack="$(al_norm_track "${BASH_REMATCH[1]}")"
  lpfx="${LABEL%%)*}"; lpfx="${lpfx#(}"
  lfields=()
  local _r="$lpfx"
  while [[ "$_r" == *' - '* ]]; do lfields+=("${_r%%' - '*}"); _r="${_r#*' - '}"; done
  lfields+=("$_r")
  lbranch="${lfields[0]#*/}"; lalias="${lfields[1]:-?}"; lmodel="${lfields[2]:-}"; leffort="${lfields[3]:-}"
  local idpfx
  idpfx="T${ltrack}-$(al_sanitise "$lbranch")-"
  local alias_known=0
  [[ "$lalias" != '?' && -n "$lalias" ]] && { idpfx="${idpfx}$(al_sanitise "$lalias")-"; alias_known=1; }
  # EXACT identity match (AL2-4): segments may contain '-', so a prefix test would let
  # T1-main-cmatl-zz-opus-xhigh pass for alias 'cmatl'. With a known alias the rest after the
  # prefix must be exactly <model>-<effort>; with an honest '?' alias, <alias>-<model>-<effort>.
  _id_match() {
    local r
    [[ "$1" == "$idpfx"* ]] || return 1
    r="${1#"$idpfx"}"
    if [[ "$alias_known" -eq 1 ]]; then
      [[ "$r" =~ ^(sonnet|opus)-(low|medium|high|xhigh|max)$ ]]
    else
      [[ "$r" =~ ^[a-z0-9]+(-[a-z0-9]+)*-(sonnet|opus)-(low|medium|high|xhigh|max)$ ]]
    fi
  }

  local stype dmodel deffort pdir adir f b names="" nmatch=0 ntrack=0 reason="" blockable=1
  stype="$(json_field .tool_input.subagent_type)"
  dmodel="$(json_field .tool_input.model)"
  deffort="$(json_field .tool_input.effort)"
  pdir="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$pdir" ]] || pdir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  adir="${AGENT_TYPE_LABEL_AGENTS_DIR:-$pdir/.claude/agents}"
  # GENERATED types only (the marker proves generated-ness; hand-made never counts)
  if [[ -d "$adir" ]]; then
    for f in "$adir"/T"${ltrack}"-*.md; do
      [[ -f "$f" ]] || continue
      grep -Eq '^<!-- generated-by: gen_agent_label_defs\.sh v[12] ' "$f" 2>/dev/null || continue
      b="${f##*/}"; b="${b%.md}"
      ntrack=$((ntrack+1))
      if _id_match "$b"; then nmatch=$((nmatch+1)); [[ "$nmatch" -le 10 ]] && names="$names $b"; fi
    done
  fi

  local catchall=" ${AGENT_TYPE_LABEL_CATCHALL:-general-purpose claude} " tm te ttrack
  if [[ -z "$stype" || "$catchall" == *" $stype "* ]]; then
    if [[ "$nmatch" -gt 0 ]]; then
      reason="subagent_type is '${stype:-<empty>}' (catch-all) but generated label agent types exist for this label's identity"
    elif [[ "$ntrack" -gt 0 ]]; then
      reason="generated label agent types exist for T${ltrack}, but only for other aliases or stale identities, none for this label's branch/alias (re-run install_agent_label_defs.sh in this session and restart it)"
      blockable=0
    else
      return 0
    fi
  elif [[ "$stype" =~ ^T([0-9]+)-.+-(sonnet|opus)-(low|medium|high|xhigh|max)$ ]]; then
    ttrack="$(al_norm_track "${BASH_REMATCH[1]}")"; tm="${BASH_REMATCH[2]}"; te="${BASH_REMATCH[3]}"
    if [[ "$ttrack" != "$ltrack" ]]; then
      reason="subagent_type '${stype}' belongs to track T${ttrack} but the dispatch label says T${ltrack}"
    elif ! _id_match "$stype"; then
      reason="subagent_type '${stype}' does not match the label's branch/alias exactly (expected ${idpfx}<model>-<effort>)"
    elif [[ -n "$lmodel" && "$lmodel" != "$tm" ]]; then
      reason="subagent_type '${stype}' runs ${tm} but the dispatch label says model '${lmodel}'"
    elif [[ -n "$leffort" && "$leffort" != "$te" ]]; then
      reason="subagent_type '${stype}' runs at ${te} effort but the dispatch label says effort '${leffort}'"
    elif [[ -n "$dmodel" && "$dmodel" != "$tm" ]]; then
      reason="the dispatch passes model '${dmodel}', which overrides label type '${stype}' (${tm}); the type name would lie"
    elif [[ -n "$deffort" && "$deffort" != "$te" ]]; then
      reason="the dispatch passes effort '${deffort}', which overrides label type '${stype}' (${te}); the type name would lie"
    elif [[ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" && "${CLAUDE_CODE_EFFORT_LEVEL}" != "$te" ]]; then
      reason="CLAUDE_CODE_EFFORT_LEVEL=${CLAUDE_CODE_EFFORT_LEVEL} overrides label type '${stype}' (${te}); the type name would lie"
    else
      return 0
    fi
  else
    return 0
  fi
  if [[ -n "${AGENT_TYPE_LABEL_BYPASS:-}" ]]; then
    echo "guardrails: AUDIT — §11.4.182 agent-type check bypassed: ${AGENT_TYPE_LABEL_BYPASS} (${reason})" >&2
    return 0
  fi
  local msg="§11.4.182/§11.4.231(F) agent type: ${reason}. Dispatch with subagent_type = one of:${names:- <none generated for this identity>} (T<N>-<branch>-<alias>-<model>-<effort>), with no per-dispatch model/effort override, so the agents list shows the true track/branch/alias/model/effort. Specialist/plugin types are exempt. A running session may need a restart to load new types. Bypass: AGENT_TYPE_LABEL_BYPASS=<reason>."
  if [[ "${AGENT_TYPE_LABEL_ENFORCE:-0}" == "1" && "$blockable" -eq 1 ]]; then
    echo "guardrails: BLOCKED — ${msg}" >&2
    return 2
  fi
  echo "guardrails: WARN — ${msg}" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$(al_json_escape "$msg")"
  return 0
}

# --------------------------------------------------------------------------
# Decision.
#   1. FORMAT must match LABEL_RE (existing check).
#   2. ALIAS-CORRECTNESS (§11.4.182, new): the label's alias MUST match the LIVE
#      alias. Honest boundary (§11.4.6): a '?' on EITHER side (live unknown OR
#      the caller honestly declaring 'unknown') is ACCEPTED — the hook only
#      BLOCKS a CONCRETE alias that provably disagrees with a KNOWN live alias.
# --------------------------------------------------------------------------
_block_reason=""
if [[ -n "$LABEL" && "$LABEL" =~ $LABEL_RE ]]; then
  if [[ -n "$_live_alias"     && "$_live_alias"     != '?' \
     && -n "$_dispatch_alias" && "$_dispatch_alias" != '?' \
     && "$_dispatch_alias" != "$_live_alias" ]]; then
    _block_reason="alias"
  elif [[ "$_dispatch_effort" == '?' && -n "$_live_effort" && "$_live_effort" != '?' ]]; then
    # §11.4.201: the effort SIGNAL is present + resolvable right now (the
    # labeler proves it by emitting a real ladder value) yet the dispatch
    # label honestly-shaped a '?' anyway -- that '?' is no longer honest
    # (§11.4.6), it is a hand-typed/stale label that never ran the labeler.
    # A label with NO effort field at all (3-field/4-field legacy form,
    # _dispatch_effort == '') is NEVER flagged here -- only a PRESENT '?'
    # is a bluff when the live signal disproves it.
    _block_reason="effort"
  else
    _type_check
    exit $?
  fi
else
  _block_reason="format"
fi

# --------------------------------------------------------------------------
# BLOCK. Print the CORRECT label so the caller can fix the dispatch.
# --------------------------------------------------------------------------
{
  if [[ "$_block_reason" == "alias" ]]; then
    echo "guardrails: BLOCKED — §11.4.182 track+branch+alias label ALIAS MISMATCH"
    echo "The ${TOOL_NAME} dispatch label's alias '${_dispatch_alias}' does NOT match the LIVE alias '${_live_alias}'."
    echo "  (Live alias is derived from CLAUDE_CONFIG_DIR basename '.claude-<alias>'; a stale/remembered alias is the usual cause.)"
    echo "  Found label:  ${LABEL}"
  elif [[ "$_block_reason" == "effort" ]]; then
    echo "guardrails: BLOCKED — §11.4.182/§11.4.201 track+branch+effort label DISHONEST '?'"
    echo "The ${TOOL_NAME} dispatch label declares effort '?' but the LIVE effort signal is currently RESOLVABLE and reads '${_live_effort}'."
    echo "  ('?' is honest ONLY when no effort signal (CLAUDE_EFFORT/CLAUDE_CODE_EFFORT/AGENT_EFFORT/CMA_EFFORT) is present in the environment."
    echo "   A signal IS present here, so '?' is a §11.4.6 bluff — run the labeler instead of hand-typing/remembering the label.)"
    echo "  Found label:  ${LABEL}"
  else
    echo "guardrails: BLOCKED — §11.4.182 track+branch+alias[+model[+effort]] label required"
    echo "Every ${TOOL_NAME} dispatch's description MUST start with a (T<N>/<branch> - <alias>[ - <model>[ - <effort>]]) label."
    if [[ -z "$LABEL" ]]; then
      echo "  Found: <no description/subagent label>"
    else
      echo "  Found: ${LABEL}"
    fi
  fi
  echo "  Correct prefix for THIS checkout+session: '${_expected} '"
  echo "  Form: (T<track-number>/<git-branch> - <alias>[ - <model>[ - <effort>]]) <space> then the task text."
  echo "    (<model> and <effort> are OPTIONAL — the 3-field and 4-field legacy forms without them are still accepted; a '?' effort is never a block-cause except when the dispatch uses a generated label type T<N>-...-<model>-<effort>, whose effort is known.)"
  echo "  Example: '${_expected} ATM-312 MPV drm_prime investigation'"
  echo "  Derive the exact label with: scripts/multitrack/track_branch_label.sh"
} >&2
exit 2
