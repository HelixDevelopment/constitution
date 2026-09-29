#!/usr/bin/env bash
# constitution/scripts/fastcycle/tokens/dispatch_stamp.sh
#
# T036 (SpecKit-004 "fast-dev-cycles", User Story 1) — item-id dispatch-
# stamping mechanism. In GUARD mode it enforces that every Agent/Task/
# TaskCreate dispatch's description carries an `item=<ATM-nnnn>` token
# (or the honest `item=?` form) alongside the constitution §11.4.182
# `(T<N>/<branch> - <alias>...)` label. In EXTRACTION mode it exposes a
# one-line helper a LATER, SEPARATE task (T037, SERIAL, conductor-only —
# "Wire dispatch_stamp.sh into ... the PreToolUse hook list in
# .claude/settings.json AND into agent_registry_writer.sh") can call to
# pull the extracted id into the dispatch registry's JSONL row WITHOUT
# re-deriving this file's parsing regex.
#
# DERIVED CONTRACT (tasks.md:120 is the ONLY spec line naming this file as
# ITS OWN deliverable; no contracts/*.md exists for it). CLARIFIED
# 2026-09-28 (§11.4.6, found by independent review): this file IS also
# referenced as a guarded dependency by a SIBLING RED test in the same
# T015-T026 batch, `constitution/scripts/fastcycle/tests/
# test_token_attribution_red.sh` (T020, "PART A"), which independently
# corroborates the item=<ATM-nnnn> contract derived below — see that
# file's own header + test_dispatch_stamp_red.sh's "THE GAP" section for
# the full correction. Every clause below traces to a REAL,
# currently-existing sibling mechanism, read in full before writing this
# file. See constitution/scripts/fastcycle/tests/test_dispatch_stamp_red.sh
# for the complete derivation trail:
#   constitution/scripts/hooks/guard-track-branch-label.sh   (GUARD-mode
#     stdin-JSON / exit-0-allow / exit-2-block contract + json_field
#     extractor, reused verbatim here for consistency — see that file's own
#     comment: each guard hook is a single self-contained file, not a
#     shared-lib import, so duplicating the extractor matches the
#     established sibling convention rather than diverging from it)
#   constitution/scripts/hooks/guard-work-track-binding.sh   (same
#     PreToolUse contract on the SAME Agent|Task|TaskCreate matcher)
#   scripts/hooks/agent_registry_writer.sh                    (its
#     CRITICAL ROBUSTNESS GUARANTEE — always-exit-0 — is the model for
#     this file's EXTRACTION mode; its {ts,event,key,tool_name,session_id,
#     description,note} JSONL schema has NO `item` field today, confirming
#     "hands the id to the registry writer" is T037's wiring step, not
#     this task's)
#
# =============================================================================
# MODE 1 (default, GUARD mode) — Claude Code PreToolUse guard-hook contract,
#   IDENTICAL to its two siblings on the SAME Agent|Task|TaskCreate matcher:
#     - Receives the tool invocation as JSON on stdin.
#     - Exit 0  -> allow (Claude proceeds).
#     - Exit 2  -> BLOCK; stderr text is fed back to Claude as the refusal
#       reason.
#   SCOPE: tool_name in {Agent, Task, TaskCreate} MUST carry an
#     `item=(ATM-[0-9]+|\?)` token SOMEWHERE in `.tool_input.description`
#     (falling back to `.tool_input.subagent`, exactly as
#     guard-track-branch-label.sh does). EVERY OTHER tool_name passes
#     through untouched (exit 0) — this hook never breaks non-agent tools.
#
#   HONEST '?' HANDLING (a genuinely ambiguous point this file resolves
#     with explicit reasoning, per the RED test's own instruction not to
#     guess it): the honest `item=?` form is ALWAYS accepted (exit 0),
#     matching the §11.4.6/§11.4.182 no-fabricated-verdict precedent the
#     sibling label guard already establishes for its alias/model/effort
#     fields. UNLIKE that sibling's <effort> field, though, this file adds
#     NO bluff-check against a "live" value for `?` — guard-track-branch-
#     label.sh can cross-check a dispatcher's honest `?` effort against a
#     REAL, environment-derivable live effort signal (CLAUDE_EFFORT et al,
#     via the reference labeler) and BLOCK a `?` that is provably dishonest
#     given that signal. There is NO equivalent "live item id" an ATM
#     ticket number could be derived from: a work-item id is a human/agent
#     CHOICE at dispatch time, not a value computable from the environment
#     (unlike track/branch/alias/model/effort, which the reference labeler
#     genuinely derives). Building a bluff-check here would therefore
#     require GUESSING what the "correct" id should have been — exactly
#     the §11.4.6 violation the RED test warns against — so `item=?` is
#     treated as unconditionally honest in this file.
#
#   PLACEMENT (the second genuinely ambiguous point, likewise resolved with
#     explicit reasoning rather than guessed): tasks.md's one line —
#     "requires item=<ATM-nnnn> ... alongside the §11.4.182 label" — settles
#     WHAT is required, not WHERE. The RECOMMENDED placement is immediately
#     AFTER the §11.4.182 label prefix, e.g.:
#       (T1/main - claude5 - sonnet - high) item=ATM-1041 T036 implement ...
#     but the regex below matches `item=` ANYWHERE in the description (at a
#     token boundary — see ITEM_RE), so a dispatcher that places it later in
#     the free-text task description is still accepted. This file does NOT
#     enforce a fixed position, since tasks.md's wording does not settle one
#     and inventing a stricter rule than the spec states would itself be a
#     guess.
#
# MODE 2 (`--extract-item-id`, EXTRACTION mode) — T037's prerequisite helper:
#   Reads the SAME stdin JSON shape as MODE 1. tool_name is NOT restricted
#   in this mode (T037 will call it only from inside the same
#   Agent|Task|TaskCreate PreToolUse/PostToolUse matcher
#   agent_registry_writer.sh already runs under, so re-gating on tool_name
#   here would be redundant and would only make this helper less reusable).
#   Prints to stdout, with NO other output:
#     - the extracted `ATM-nnnn` token, if a well-formed `item=ATM-nnnn` is
#       present;
#     - the literal `?`, if the honest `item=?` form is present;
#     - nothing (empty stdout), if `item=` is genuinely absent from the
#       description — so `id=$(... --extract-item-id <<<"$json")` yields an
#       empty string T037 can test with `[ -n "$id" ]` without a separate
#       sentinel value.
#   ALWAYS exits 0, in EVERY case (found / honest-unknown / absent / stdin
#   empty or unparseable) — see the ROBUSTNESS NOTE below.
#
# EXACT INVOCATION FOR T037 (so it never has to rediscover this):
#   id="$(printf '%s' "$RAW_STDIN_JSON" | bash \
#     "$REPO_ROOT/constitution/scripts/fastcycle/tokens/dispatch_stamp.sh" \
#     --extract-item-id)"
#   # $id is "" | "?" | "ATM-nnnn" — never anything else, never exits non-zero.
#
# ROBUSTNESS NOTE FOR T037 (derived contract stub 4): GUARD mode (MODE 1)
#   legitimately BLOCKS (exit 2) on a missing item= token — matching its
#   sibling label guard's identical blocking behaviour for a missing label;
#   that IS this tool's purpose in that mode. EXTRACTION mode (MODE 2) is a
#   DIFFERENT code path with a DIFFERENT guarantee: it NEVER exits non-zero,
#   under any input (mirrors agent_registry_writer.sh's own "CRITICAL
#   ROBUSTNESS GUARANTEE" that a non-zero PreToolUse-adjacent hook exit
#   BLOCKS the tool call — the exact §11.4.201(1) false-positive-refusal
#   class that writer's own header warns against). If T037 embeds a call to
#   `--extract-item-id` inside agent_registry_writer.sh's own always-exit-0
#   PreToolUse/PostToolUse contract, it can rely on THIS file's MODE 2
#   already being always-exit-0 in isolation — but T037's wiring step
#   remains responsible for not letting some OTHER failure in ITS OWN glue
#   code (e.g. an unguarded `set -e` around the call, or a `$(...)` command
#   substitution whose exit status is checked and misinterpreted) turn a
#   benign empty result into a hook-level non-zero effect; that isolation
#   is T037's job and is not derivable from this file alone.
#
# DECOUPLING (§11.4.177): lives in the constitution submodule, inherited BY
# REFERENCE (never copied). Project-agnostic: validates the `item=` token
# format only — no project-specific paths, no hardcoded ticket prefixes
# beyond the `ATM-` form the RED test's own derivation names (SPK- tickets,
# which the SIBLING guard-work-track-binding.sh separately recognises for
# its own ticket-binding purpose, are deliberately NOT accepted here —
# tasks.md's line and the RED test's stub 1 both name only `item=<ATM-nnnn>`,
# and widening the accepted set beyond what the spec states would itself be
# an unstated guess per §11.4.6).
#
# NOT YET WIRED (deliberately, by design — T037's job, NOT this task's):
#   this file is NOT registered in .claude/settings.json's PreToolUse hook
#   chain. Wiring it prematurely could start blocking every agent dispatch
#   in a live session before its interaction with the two existing sibling
#   guards has been carefully tested. Invoke it directly/manually until
#   T037 lands.
#
# Producer != Verifier (constitution §11.4.240): this implementation is a
# separate, later step from the RED-test's author; it is followed by an
# INDEPENDENT §11.4.209 Opus-xhigh review before being trusted — this file's
# author never self-certifies it as that review.
#
# Usage:
#   printf '%s' "$json" | bash dispatch_stamp.sh                  # GUARD mode
#   printf '%s' "$json" | bash dispatch_stamp.sh --extract-item-id # EXTRACTION mode
#
# Classification: universal.

set -uo pipefail

PAYLOAD="$(cat || true)"

# --------------------------------------------------------------------------
# Extract a JSON string field WITHOUT requiring jq (prefer jq if present).
# IDENTICAL extractor to guard-track-branch-label.sh / guard-work-track-
# binding.sh (same leaf keys: tool_name, description, subagent) — kept as a
# literal copy, matching the established sibling convention of each guard
# hook being a single self-contained file rather than importing a shared lib.
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

# The item token lives on `description`; fall back to a `subagent` label if
# present — identical fallback order to guard-track-branch-label.sh.
DESCRIPTION="$(json_field .tool_input.description)"
if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="$(json_field .tool_input.subagent)"
fi

# item=(ATM-[0-9]+|\?) at a token boundary (start-of-string or preceded by
# whitespace) — the honest '?' form is unconditionally accepted (see header:
# no live-derivable value exists to cross-check it against, unlike the
# sibling label guard's <effort> field).
ITEM_RE='(^|[[:space:]])item=(ATM-[0-9]+|\?)'

extract_item() {
  # Prints the captured item value (ATM-nnnn or literal '?') if ITEM_RE
  # matches anywhere in $1, else prints nothing.
  if [[ "$1" =~ $ITEM_RE ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  fi
}

# ==========================================================================
# MODE 2: --extract-item-id (ALWAYS exit 0; stdout is the id / '?' / empty,
# NO other output).
# ==========================================================================
if [[ "${1:-}" == "--extract-item-id" ]]; then
  extract_item "$DESCRIPTION"
  exit 0
fi

# ==========================================================================
# MODE 1 (default): PreToolUse guard.
# ==========================================================================
TOOL_NAME="$(json_field .tool_name)"

# Only the agent-dispatching tools carry an item stamp. Anything else is
# allowed untouched.
case "$TOOL_NAME" in
  Agent|Task|TaskCreate) ;;
  *) exit 0 ;;
esac

FOUND="$(extract_item "$DESCRIPTION")"
if [[ -n "$FOUND" ]]; then
  exit 0
fi

{
  echo "guardrails: BLOCKED — T036 dispatch-stamp: item=<ATM-nnnn> required"
  echo "Every ${TOOL_NAME} dispatch's description MUST carry an 'item=<ATM-nnnn>'"
  echo "token (or the honest 'item=?' form when genuinely unknown) alongside its"
  echo "§11.4.182 (T<N>/<branch> - <alias>...) label."
  if [[ -z "$DESCRIPTION" ]]; then
    echo "  Found: <no description/subagent label>"
  else
    echo "  Found: ${DESCRIPTION}"
  fi
  echo "  Recommended placement: immediately after the label, e.g.:"
  echo "    (T1/main - claude5 - sonnet - high) item=ATM-1041 <task text>"
  echo "  Honest-unknown form: item=?"
} >&2
exit 2
