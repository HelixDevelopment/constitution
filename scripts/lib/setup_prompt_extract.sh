#!/usr/bin/env bash
# scripts/lib/setup_prompt_extract.sh — the ONE PROMPT-block extractor shared by the
# setup-prompt validators (scripts/gates/cm_setup_prompt_latest_present.sh and
# scripts/prompts/rotate_setup_prompt.sh).
#
# Source this file (it defines functions only; it changes no shell option):
#
#   spx_extract_prompt FILE
#       Prints the body of the FIRST fenced block under the `## PROMPT` heading of
#       FILE and returns 0, or returns 1. Semantics are a byte-for-byte copy of the
#       installer's hi_extract_prompt (scripts/install_constitution.sh):
#         - the heading line is `## PROMPT` optionally followed by whitespace
#           (a trailing CR counts as whitespace, so CRLF files work);
#         - a later `## ` heading BEFORE the opening fence ends the search (rc 1:
#           a fence under a later heading is NOT the prompt);
#         - an opening fence is a line starting with 3+ backticks or 3+ tildes
#           (an info string such as ```bash is allowed);
#         - the block closes on a line of the SAME fence character, at least as
#           long as the opener, with nothing else on the line except trailing
#           whitespace (leading whitespace makes it content); shorter inner
#           fences and fences of the other character are kept as content;
#         - rc 0 only when the block was closed and had at least one line
#           (a block of blank or whitespace-only lines counts as non-empty here,
#           exactly as in the installer).
#
#   spx_has_prompt_block FILE
#       The VALIDATOR form: rc 0 when spx_extract_prompt succeeds AND the block
#       holds at least one line with a non-whitespace character. This one rule is
#       deliberately stricter than the installer (a whitespace-only prompt is
#       useless to an agent); every other outcome is identical to the installer's.
#
# KEEP IN SYNC: the installer carries an inline copy of the same awk program
# (the installer is one self-contained file, it cannot source this library).
# tests/prompts/test_setup_prompt_extract_equivalence.sh runs both on a fixture
# matrix and fails on any difference.
# Dependencies: awk. No network, no writes. Classification: universal (§11.4.17).

spx_extract_prompt() {
  awk '
    BEGIN { st = 0; got = 0 }
    st == 0 && /^## PROMPT[[:space:]]*$/ { st = 1; next }
    st == 1 && /^## / { exit }
    st == 1 && match($0, /^(```+|~~~+)/) { fch = substr($0, 1, 1); flen = RLENGTH; st = 2; next }
    st == 2 {
      line = $0; sub(/[[:space:]]+$/, "", line)
      if (length(line) >= flen && substr(line, 1, 1) == fch) {
        rest = line; if (fch == "`") gsub(/`/, "", rest); else gsub(/~/, "", rest)
        if (rest == "") { got = 1; exit }
      }
      print; n++
    }
    END { exit (got && n > 0) ? 0 : 1 }
  ' "$1"
}

spx_has_prompt_block() {
  local body
  body="$(spx_extract_prompt "${1:?file}" 2>/dev/null)" || return 1
  [[ "$body" =~ [^[:space:]] ]]
}
