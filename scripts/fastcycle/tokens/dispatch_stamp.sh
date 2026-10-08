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
# DECOUPLING (§11.4.177 / §11.4.28 -- F13 fix, T048 round-2 review): this
# file lives in the constitution submodule, inherited BY REFERENCE (never
# copied), and MUST carry ZERO project-specific literals. Its accepted
# ticket-id PREFIX(ES) are therefore CONFIGURABLE, never a hardcoded `ATM-`:
#
#   1. `FC_DISPATCH_ITEM_ID_RE` (env, highest priority) -- if set, this
#      value REPLACES the whole `item=` value alternation verbatim (e.g.
#      `ATM-[0-9]+|SPK-[0-9]+`), the consuming project's own explicit,
#      unvalidated choice (§11.4.6: an operator-supplied value is trusted,
#      never second-guessed).
#   2. Else, the DEFAULT prefix is DERIVED (never hardcoded) the SAME way
#      the sibling `constitution/scripts/release_prefix.sh` (§11.4.151) /
#      `constitution/scripts/workable-items/cmd/workable-items/prefix.go`'s
#      `deriveKeyPrefix()` already do for this exact class of value: resolve
#      the project's release prefix (HELIX_RELEASE_PREFIX env -> its .env
#      entry -> snake_case(project root dir name)), then take its first 3
#      ASCII letters, uppercased (padded with 'X' if <3, the neutral "WIT"
#      fallback if none) -- for THIS checkout that derives "ATM" from
#      "atmosphere" (verified live, 2026-09-30: `bash
#      constitution/scripts/release_prefix.sh` prints "atmosphere"), so
#      EVERY existing fixture/test in this suite (all written against
#      literal `ATM-nnnn` ids) keeps passing unchanged with ZERO test
#      edits -- while a DIFFERENT consuming project derives ITS OWN correct
#      prefix automatically, with no source edit to this file.
#   3. `FC_DISPATCH_EXTRA_ITEM_PREFIXES` (env, additive, comma/pipe/space-
#      separated) -- extra accepted prefixes ADDED to the derived default
#      from (2), e.g. `FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK` lets a dispatch
#      naming `item=SPK-609` (the real T045-sample id round-2's F13 finding
#      named) pass, entirely via CONFIGURATION -- never a source edit, and
#      never silently widening the DEFAULT (which stays exactly `ATM-` for
#      an unconfigured checkout, preserving §11.4.6's "don't guess a wider
#      set than what's asked for" reasoning this file's earlier revision
#      already applied to the ATM-only default -- see git history).
#
# HERMETICITY NOTE: this DOES read `constitution/scripts/release_prefix.sh`
# (which in turn reads the git-tracked, checked-in project `.env`) once per
# invocation UNLESS `FC_DISPATCH_ITEM_ID_RE` is set -- a deliberate, narrow
# widening of the "no ambient ENV state affects this tool" claim in the
# companion `test_dispatch_stamp.sh` suite's own header, which is about
# session-scoped vars (CLAUDE_*, CLAUDE_CONFIG_DIR) varying RUN TO RUN, not
# about this repository's own stable, git-tracked `.env` release-prefix
# entry, which resolves identically on every invocation of this exact
# checkout (the same "hermetic within a fixed checkout" guarantee every
# other file-content-dependent check in this test family already relies on).
#
# NOW WIRED (T037 landed -- this comment corrected 2026-09-30, T048
#   round-2 review F13; the file previously said "NOT YET WIRED" long after
#   T037 registered it): this file IS the guard command in
#   `.claude/settings.json`'s PreToolUse hook chain (search "dispatch_stamp"
#   in that file) AND is invoked by `scripts/hooks/agent_registry_writer.sh`
#   (its `--extract-item-id` EXTRACTION mode, search "DISPATCH_STAMP" in
#   that file) -- both confirmed present in this checkout, 2026-09-30.
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
# DEFERRALS LEDGER (T048 restart round 2, V1-M4):
#   CLOSED in round 2: (a) the jq-less fallback took the FIRST "description"
#   key anywhere in the payload and failed OPEN on a nested one -- replaced by
#   an exact-path JSON reader that fails closed (see json_field); (b) the
#   release_prefix.sh fallback to "WIT" was silent -- GUARD mode now prints a
#   notice (see _fc_resolve_default_prefix). (c) "file order" belongs to
#   transcript_ingest.py and is closed there.
#   OWED-DS-1: the test suites next to this file (test_dispatch_stamp*.sh,
#   including the r6 mutation proof) are not invoked by any runner or gate;
#   tests/run_all.sh globs tests/ only. Wiring them is the conductor's step.
#
# Classification: universal.

set -uo pipefail

PAYLOAD="$(cat || true)"

# LOCALE (V1-M2, T048 restart round 2): every regex, character class and
# `tr` below runs under LC_ALL=C, so the accepted tag set is the same for
# every caller locale and equals transcript_ingest.py's (which spells the
# same ASCII classes out and compiles with re.ASCII). Before this, bash's
# [[:space:]] / [[:alnum:]] followed the caller's locale: `item=ATM-12é`
# extracted ATM-12 under C but nothing under C.UTF-8, and U+2003 before the
# tag counted as a separator under C.UTF-8 only.
export LC_ALL=C

# --------------------------------------------------------------------------
# json_field <path> -- print the STRING value at <path> (".tool_name",
# ".tool_input.description", ".tool_input.subagent") of the payload.
# Exit 0 with the value (empty if the path is absent or not a string), or
# exit 3 if the payload is not empty and cannot be parsed as one JSON
# object. jq is used when present.
#
# Without jq, a small JSON reader in awk walks the document and takes the
# value at the exact path, as jq does (the last one if a key repeats). T048
# restart round 2, V1-M4(a): the previous awk fallback took the FIRST
# '"description"' key anywhere in the payload, so a nested
# {"metadata":{"description":"item=ATM-1"}} placed before the real untagged
# description was ALLOWED by the guard and extracted as ATM-1 (fail open);
# jq refused it. A payload this reader cannot parse is reported as exit 3,
# which the guard turns into a refusal (fail closed) and the extraction
# mode into an empty result.
# --------------------------------------------------------------------------
json_field() {
  local path="$1" out rc
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$PAYLOAD" | jq -r "(if type == \"object\" then . else error(\"not an object\") end) | ($path | if type == \"string\" then . else empty end)" 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] || return 3
    printf '%s' "$out"
    return 0
  fi
  printf '%s' "$PAYLOAD" | awk -v want="${path#.}" '
    function hexval(h,   i, c, v) {
      if (length(h) != 4) return -1
      v = 0
      for (i = 1; i <= 4; i++) {
        c = index("0123456789abcdef", tolower(substr(h, i, 1)))
        if (c == 0) return -1
        v = v * 16 + c - 1
      }
      return v
    }
    function utf8(cp) {
      if (cp < 128) return sprintf("%c", cp)
      if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
      if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
      return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
    }
    # parse_string: s[pos] is the opening quote. Sets STR and moves pos past
    # the closing quote; returns 0 on an invalid or unterminated string.
    function parse_string(   c, out, cp, lo) {
      pos++
      out = ""
      while (pos <= n) {
        c = substr(s, pos, 1)
        if (c == "\"") { pos++; STR = out; return 1 }
        if (c < " ") return 0
        if (c == "\\") {
          c = substr(s, pos + 1, 1)
          if (c == "n") out = out "\n"
          else if (c == "t") out = out "\t"
          else if (c == "r") out = out "\r"
          else if (c == "b") out = out "\b"
          else if (c == "f") out = out "\f"
          else if (c == "\"" || c == "\\" || c == "/") out = out c
          else if (c == "u") {
            cp = hexval(substr(s, pos + 2, 4))
            if (cp < 0) return 0
            pos += 4
            if (cp >= 55296 && cp < 56320 && substr(s, pos + 2, 2) == "\\u") {
              lo = hexval(substr(s, pos + 4, 4))
              if (lo >= 56320 && lo < 57344) { cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); pos += 6 }
            }
            if (cp > 0) out = out utf8(cp)
          } else return 0
          pos += 2
          continue
        }
        out = out c
        pos++
      }
      return 0
    }
    function skip_ws() { while (pos <= n && index(" \t\r\n", substr(s, pos, 1)) > 0) pos++ }
    function cur_path(   j, p) {
      p = ""
      for (j = 1; j <= d; j++) p = p (j > 1 ? "." : "") (typ[j] == "o" ? key[j] : "[]")
      return p
    }
    # value_done: a value was completed at the current depth.
    function value_done() { need = (d == 0) ? "done" : "sep" }
    { buf = buf $0 }
    END {
      s = buf; n = length(s); pos = 1; d = 0; need = "value"; val = ""
      skip_ws()
      if (pos > n) exit 0
      if (substr(s, pos, 1) != "{") exit 3
      while (1) {
        skip_ws()
        if (pos > n) break
        c = substr(s, pos, 1)
        if (need == "done") exit 3
        if (need == "key" || need == "key_or_end") {
          if (c == "}" && need == "key_or_end") { pos++; d--; value_done(); continue }
          if (c != "\"") exit 3
          if (!parse_string()) exit 3
          key[d] = STR; need = "colon"; continue
        }
        if (need == "colon") { if (c != ":") exit 3; pos++; need = "value"; continue }
        if (need == "sep") {
          if (c == ",") { pos++; need = (typ[d] == "o") ? "key" : "value"; continue }
          if ((c == "}" && typ[d] == "o") || (c == "]" && typ[d] == "a")) { pos++; d--; value_done(); continue }
          exit 3
        }
        # need is "value" or "value_or_end"
        if (c == "]" && need == "value_or_end") { pos++; d--; value_done(); continue }
        if (c == "{") { pos++; d++; typ[d] = "o"; key[d] = ""; need = "key_or_end"; continue }
        if (c == "[") { pos++; d++; typ[d] = "a"; need = "value_or_end"; continue }
        if (c == "\"") {
          if (!parse_string()) exit 3
          if (cur_path() == want) val = STR
          value_done(); continue
        }
        tok = ""
        while (pos <= n && index("-+.0123456789eEtrufalsn", substr(s, pos, 1)) > 0) { tok = tok substr(s, pos, 1); pos++ }
        if (tok != "true" && tok != "false" && tok != "null" && tok !~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) exit 3
        value_done()
      }
      if (need != "done") exit 3
      printf "%s", val
    }
  '
}

# The item token lives on `description`; fall back to a `subagent` label if
# present — identical fallback order to guard-track-branch-label.sh. A
# payload that cannot be parsed (json_field exit 3) yields no description.
PARSE_OK=1
DESCRIPTION="$(json_field .tool_input.description)" || PARSE_OK=0
if [[ "$PARSE_OK" -eq 1 && -z "$DESCRIPTION" ]]; then
  DESCRIPTION="$(json_field .tool_input.subagent)" || PARSE_OK=0
fi

# F13 fix (T048 round-2 review, §11.4.28/§11.4.177): the accepted ticket-id
# PREFIX(ES) are resolved, never hardcoded -- see the DECOUPLING header
# comment above for the full 3-tier priority + hermeticity reasoning.
_fc_derive_key_prefix() {
  # Mirror constitution/scripts/workable-items/cmd/workable-items/prefix.go's
  # deriveKeyPrefix(): first 3 ASCII letters of $1, uppercased; padded with
  # 'X' if fewer than 3; the neutral "WIT" fallback if the input has no
  # ASCII letters at all.
  local input="$1" letters="" i=0 n c
  n=${#input}
  while [ "$i" -lt "$n" ] && [ "${#letters}" -lt 3 ]; do
    c="${input:$i:1}"
    case "$c" in
      [a-zA-Z]) letters="${letters}$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]')" ;;
    esac
    i=$((i + 1))
  done
  if [ -z "$letters" ]; then
    printf 'WIT'
    return 0
  fi
  while [ "${#letters}" -lt 3 ]; do
    letters="${letters}X"
  done
  printf '%s' "$letters"
}

# _fc_resolve_default_prefix -- sets FC_DEFAULT_PREFIX to the 3-letter key
# derived from the project's release prefix (scripts/release_prefix.sh:
# HELIX_RELEASE_PREFIX env -> its .env entry -> snake_case(project root
# dir name)), and FC_PREFIX_NOTICE to a one-line explanation when that
# resolution failed and the neutral "WIT" key (or a key derived from partial
# output) is used instead. Runs in the current shell, never in $(...), so
# both variables reach the caller.
#
# T048 round-3 review finding R3-M1 (2026-09-30): this used to fall back to
# the LITERAL "ATM" -- a project-specific guess inside this project-agnostic
# constitution submodule (§11.4.28/§11.4.177). The fallback is the neutral
# "WIT" from _fc_derive_key_prefix().
#
# T048 restart round 2, V1-M3: the fallback used to be silent (release_
# prefix.sh's stderr and exit status were discarded), while
# transcript_ingest.py warns on the same failure. FC_PREFIX_NOTICE is now
# printed on stderr in GUARD mode; EXTRACTION mode stays silent, because its
# contract is "stdout is the id, no other output".
_fc_resolve_default_prefix() {
  local self_path self_dir rp_script="" base="" rc=0
  FC_PREFIX_NOTICE=""
  # Pure bash parameter-expansion dirname (never the external `dirname`
  # command): the G-section AWK-fallback tests in test_dispatch_stamp.sh
  # restrict PATH to only awk+cat.
  self_path="${BASH_SOURCE[0]:-$0}"
  self_dir="${self_path%/*}"
  [ "$self_dir" = "$self_path" ] && self_dir="."
  if [ -n "$self_dir" ]; then
    rp_script="$(cd "$self_dir/../.." 2>/dev/null && pwd 2>/dev/null || true)/release_prefix.sh"
  fi
  if [ -n "$rp_script" ] && [ -f "$rp_script" ]; then
    base="$(bash "$rp_script" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      FC_PREFIX_NOTICE="release_prefix.sh ($rp_script) exited $rc"
    elif [ -z "$base" ]; then
      FC_PREFIX_NOTICE="release_prefix.sh ($rp_script) printed nothing"
    fi
  else
    FC_PREFIX_NOTICE="release_prefix.sh not found (looked for ${rp_script:-<unresolvable>})"
  fi
  FC_DEFAULT_PREFIX="$(_fc_derive_key_prefix "$base")"
  if [ -n "$FC_PREFIX_NOTICE" ]; then
    FC_PREFIX_NOTICE="dispatch_stamp: NOTICE: $FC_PREFIX_NOTICE -- the item-tag prefix for this run is '$FC_DEFAULT_PREFIX'"
  fi
}

FC_PREFIX_NOTICE=""
if [ -n "${FC_DISPATCH_ITEM_ID_RE:-}" ]; then
  ITEM_VALUE_RE="$FC_DISPATCH_ITEM_ID_RE"
  ITEM_FORM_LABEL="item=<an id matching FC_DISPATCH_ITEM_ID_RE='$FC_DISPATCH_ITEM_ID_RE'>"
  ITEM_EXAMPLE="item=<id>"
else
  _fc_resolve_default_prefix
  ITEM_ALL_PREFIXES="$FC_DEFAULT_PREFIX"
  if [ -n "${FC_DISPATCH_EXTRA_ITEM_PREFIXES:-}" ]; then
    for _fc_p in $(printf '%s' "$FC_DISPATCH_EXTRA_ITEM_PREFIXES" | tr ',|' '  '); do
      _fc_p_upper="$(printf '%s' "$_fc_p" | tr '[:lower:]' '[:upper:]')"
      [ -n "$_fc_p_upper" ] && ITEM_ALL_PREFIXES="${ITEM_ALL_PREFIXES}|${_fc_p_upper}"
    done
  fi
  ITEM_VALUE_RE="(${ITEM_ALL_PREFIXES})-[0-9]+"
  # V1-M3: the refusal names the RESOLVED prefix(es), never a project literal.
  ITEM_FORM_LABEL="item=<${FC_DEFAULT_PREFIX}-nnnn> (accepted prefixes: ${ITEM_ALL_PREFIXES//|/, })"
  ITEM_EXAMPLE="item=${FC_DEFAULT_PREFIX}-1041"
fi

# item=(<resolved-prefix(es)>-[0-9]+|\?) as a whole token -- the honest '?'
# form is unconditionally accepted (see header: no live-derivable value
# exists to cross-check it against, unlike the sibling label guard's
# <effort> field). Left: start of string or one ASCII whitespace character.
# Right (T048 restart round-1, R3 boundary note): end of string or anything
# but an ASCII letter, digit or underscore, so 'item=ATM-12x', 'item=ATM-12_x'
# and 'item=?foo' are not tags. Under LC_ALL=C (above) these classes are
# exactly transcript_ingest.py's ITEM_TAG_TEMPLATE classes, so the two tools
# accept the same set of tags in any caller locale; the shared guard is
# test_token_attribution_red.sh PART I4. The capture group used below stays
# BASH_REMATCH[2].
ITEM_RE="(^|[[:space:]])item=(${ITEM_VALUE_RE}|\\?)([^[:alnum:]_]|\$)"

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
[ -n "$FC_PREFIX_NOTICE" ] && echo "$FC_PREFIX_NOTICE" >&2

if [[ "$PARSE_OK" -eq 1 ]]; then
  TOOL_NAME="$(json_field .tool_name)" || PARSE_OK=0
fi
if [[ "$PARSE_OK" -eq 0 ]]; then
  # Fail closed: without a parsed tool_name this hook cannot tell an agent
  # dispatch from any other tool, so it refuses rather than guessing.
  {
    echo "guardrails: BLOCKED — T036 dispatch-stamp: the hook payload could not be parsed as a JSON object"
    echo "  parser: $(command -v jq >/dev/null 2>&1 && echo jq || echo 'built-in awk reader (jq not installed)')"
    echo "  payload starts: $(printf '%s' "$PAYLOAD" | head -c 120)"
  } >&2
  exit 2
fi

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
  echo "guardrails: BLOCKED — T036 dispatch-stamp: ${ITEM_FORM_LABEL} required"
  echo "Every ${TOOL_NAME} dispatch's description MUST carry an '${ITEM_FORM_LABEL%% (*}'"
  echo "token (or the honest 'item=?' form when genuinely unknown) alongside its"
  echo "§11.4.182 (T<N>/<branch> - <alias>...) label."
  if [[ -z "$DESCRIPTION" ]]; then
    echo "  Found: <no description/subagent label>"
  else
    echo "  Found: ${DESCRIPTION}"
  fi
  echo "  Recommended placement: immediately after the label, e.g.:"
  echo "    (T1/main - claude5 - sonnet - high) ${ITEM_EXAMPLE} <task text>"
  echo "  Honest-unknown form: item=?"
} >&2
exit 2
