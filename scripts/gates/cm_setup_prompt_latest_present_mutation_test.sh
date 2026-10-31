#!/usr/bin/env bash
# cm_setup_prompt_latest_present_mutation_test.sh — §1.1 paired-mutation meta-test
# for CM-SETUP-PROMPT-LATEST-PRESENT (scripts/gates/cm_setup_prompt_latest_present.sh).
#
# Throwaway fixtures only (the real repository is never touched).
# Part 1 — fixture classification with the real gate:
#   PASS-expected : GOOD (valid latest.md, 01/02 history, valid follow-ups)
#                   · LEGACY-MENTION (a ./constitution line that says "legacy" — golden-FALSE)
#                   · NO-FOLLOWUPS (follow-up directory absent is not a defect)
#                   · SUBMODULE-PATH (submodules/constitution/... citations — golden-FALSE)
#   FAIL-expected : NO-LATEST · NO-PROMPT-HEADING · UNCLOSED-FENCE · EMPTY-BLOCK
#                   · MISSING-SCRIPT (cites submodules/constitution/scripts/nope.sh)
#                   · MISSING-BARE-SCRIPT (cites scripts/nope_bare.sh)
#                   · LEGACY-ADD (`git submodule add <url> constitution` without "legacy")
#                   · LEGACY-IMPORT (@constitution/CLAUDE.md) · DOT-PATH (./constitution/...)
#                   · GAP (01, 03) · DUP (02_a, 02_b) · BAD-NAME (03_Bad.md)
#                   · LOCK (.rotate.lock left) · FOLLOWUP-NO-FM · FOLLOWUP-BAD-BOOL · FOLLOWUP-GAP
#                   · LATER-HEADING-FENCE (the only fence sits under a later `## ` heading:
#                     the installer rejects it, so must the gate) · PAD-003 / PAD-3
#                     (non-canonical number prefix) · LEGACY-SUBSTRING ("legacy" only
#                     inside a file name) · FOLLOWUP-MISSING-SCRIPT · FOLLOWUP-BAD-FLAG
#   PASS-expected (round 2): TILDE-FENCE (~~~ fence, accepted by the installer)
#                   · TEN-PLUS (01..11 history: numeric, not lexical, order)
#                   · FOLLOWUP-GOOD-CITE (a follow-up citing an existing script + flag)
#   BLIND-expected: NO-DIR (docs/prompts/setup absent) · NO-CITATION (the citation
#                   instrument found zero script citations — its control needle failed)
# Part 2 — gate mutants: the gate is copied, one defect injected per mutant, every
#   fixture re-classified; each mutant MUST change at least one verdict (be KILLED).
# Part 3 — the real repository: the gate is run on this repository and its verdict printed.
# Usage: cm_setup_prompt_latest_present_mutation_test.sh   Exit: 0 proof holds · 1 misclassified/survivor · 2 env error.
# Dependencies: bash, sed, cmp, mktemp. Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
gate="$here/cm_setup_prompt_latest_present.sh"
[ -r "$gate" ] || { echo "META: gate missing: $gate" >&2; exit 2; }
# shellcheck source=../lib/safe_rm.sh
. "$repo/scripts/lib/safe_rm.sh"
export SETUP_PROMPT_EXTRACT_LIB="$repo/scripts/lib/setup_prompt_extract.sh"
# the mutant gate copies live outside this repository, so their own scripts/lib does not
# hold the library: mark this test environment as trusted (the gate refuses otherwise)
export SETUP_PROMPT_EXTRACT_LIB_TRUST=1
[ -r "$SETUP_PROMPT_EXTRACT_LIB" ] || { echo "META: extractor library missing: $SETUP_PROMPT_EXTRACT_LIB" >&2; exit 2; }
tmp="$(mktemp -d)" || exit 2
trap 'safe_rm_rf "${tmp:?}" >/dev/null 2>&1' EXIT
bad=0

doc() { # <extra-line-inside-block> -> a valid prompt document
  printf '# Setup prompt\n\n| Field | Value |\n|---|---|\n| Revision | 1 |\n\n## PROMPT\n\n```\nYou are the setup agent.\nRun: bash submodules/constitution/scripts/real.sh --help\nThen: bash scripts/real_bare.sh\n%s\n```\n\n## Notes\n\nend\n' "$1"
}
fu() { printf -- '---\ntitle: %s\nrequires_previous_success: %s\n---\n\nFollow-up %s body.\n' "$1" "$2" "$1"; }
base() { # <label> -> creates a GOOD fixture root, prints it
  local r="$tmp/$1"; mkdir -p "$r/docs/prompts/setup/followups" "$r/scripts"
  printf '#!/bin/sh\n# flags: --help --quiet\n' >"$r/scripts/real.sh"; printf '#!/bin/sh\n' >"$r/scripts/real_bare.sh"
  doc "" >"$r/docs/prompts/setup/latest.md"
  doc "old" >"$r/docs/prompts/setup/01_old.md"; doc "mid" >"$r/docs/prompts/setup/02_middle.md"
  fu one true >"$r/docs/prompts/setup/followups/01_one.md"; fu two false >"$r/docs/prompts/setup/followups/02_two.md"
  printf '%s\n' "$r"
}
FIX=""
fx() { FIX+="$1:$2 "; }
L() { printf '%s/docs/prompts/setup/latest.md' "$tmp/$1"; }

r="$(base GOOD)"; fx GOOD 0
r="$(base LEGACY-MENTION)"; doc "Legacy layout: if ./constitution exists, migrate it (legacy)." >"$(L LEGACY-MENTION)"; fx LEGACY-MENTION 0
r="$(base NO-FOLLOWUPS)"; rm -rf -- "${r:?}/docs/prompts/setup/followups"; fx NO-FOLLOWUPS 0
r="$(base SUBMODULE-PATH)"; doc "Read submodules/constitution/CLAUDE.md and @submodules/constitution/CLAUDE.md" >"$(L SUBMODULE-PATH)"; fx SUBMODULE-PATH 0
r="$(base NO-LATEST)"; rm -f "$(L NO-LATEST)"; fx NO-LATEST 1
r="$(base NO-PROMPT-HEADING)"; sed -i 's/^## PROMPT$/## Something/' "$(L NO-PROMPT-HEADING)"; fx NO-PROMPT-HEADING 1
r="$(base UNCLOSED-FENCE)"; printf '# x\n\n## PROMPT\n\n```\nbash submodules/constitution/scripts/real.sh\n' >"$(L UNCLOSED-FENCE)"; fx UNCLOSED-FENCE 1
r="$(base EMPTY-BLOCK)"; printf '# x\n\nbash submodules/constitution/scripts/real.sh\n\n## PROMPT\n\n```\n   \n```\n' >"$(L EMPTY-BLOCK)"; fx EMPTY-BLOCK 1
r="$(base MISSING-SCRIPT)"; doc "bash submodules/constitution/scripts/nope.sh" >"$(L MISSING-SCRIPT)"; fx MISSING-SCRIPT 1
r="$(base MISSING-BARE-SCRIPT)"; doc "curl .../main/scripts/nope_bare.sh" >"$(L MISSING-BARE-SCRIPT)"; fx MISSING-BARE-SCRIPT 1
r="$(base LEGACY-ADD)"; doc "git submodule add git@github.com:HelixDevelopment/HelixConstitution.git constitution" >"$(L LEGACY-ADD)"; fx LEGACY-ADD 1
r="$(base LEGACY-IMPORT)"; doc "@constitution/CLAUDE.md" >"$(L LEGACY-IMPORT)"; fx LEGACY-IMPORT 1
r="$(base DOT-PATH)"; doc "bash ./constitution/scripts/real.sh" >"$(L DOT-PATH)"; fx DOT-PATH 1
r="$(base GAP)"; mv "$r/docs/prompts/setup/02_middle.md" "$r/docs/prompts/setup/03_middle.md"; fx GAP 1
r="$(base DUP)"; doc d >"$r/docs/prompts/setup/02_another.md"; fx DUP 1
r="$(base BAD-NAME)"; doc b >"$r/docs/prompts/setup/03_Bad.md"; fx BAD-NAME 1
r="$(base LOCK)"; mkdir "$r/docs/prompts/setup/.rotate.lock"; fx LOCK 1
r="$(base FOLLOWUP-NO-FM)"; printf 'no front matter\n' >"$r/docs/prompts/setup/followups/02_two.md"; fx FOLLOWUP-NO-FM 1
r="$(base FOLLOWUP-BAD-BOOL)"; fu two maybe >"$r/docs/prompts/setup/followups/02_two.md"; fx FOLLOWUP-BAD-BOOL 1
r="$(base FOLLOWUP-GAP)"; mv "$r/docs/prompts/setup/followups/02_two.md" "$r/docs/prompts/setup/followups/03_two.md"; fx FOLLOWUP-GAP 1
r="$(base SYMLINK-LATEST)"; mv "$(L SYMLINK-LATEST)" "$r/docs/prompts/real_latest.md"; ln -s ../real_latest.md "$(L SYMLINK-LATEST)"; fx SYMLINK-LATEST 1
r="$(base FOLLOWUP-STALE)"; printf -- '---\ntitle: two\nrequires_previous_success: false\n---\n\nRun bash ./constitution/scripts/real.sh first.\n' >"$r/docs/prompts/setup/followups/02_two.md"; fx FOLLOWUP-STALE 1
r="$(base FOLLOWUP-STALE-LEGACY)"; printf -- '---\ntitle: two\nrequires_previous_success: false\n---\n\nLegacy layout: ./constitution is migrated.\n' >"$r/docs/prompts/setup/followups/02_two.md"; fx FOLLOWUP-STALE-LEGACY 0
r="$(base DOTDOT-CITE)"; doc "bash submodules/constitution/scripts/../scripts/real.sh" >"$(L DOTDOT-CITE)"; fx DOTDOT-CITE 1
r="$(base ASSIGN-PATH)"; doc "CONST_DIR=constitution bash submodules/constitution/scripts/real.sh" >"$(L ASSIGN-PATH)"; fx ASSIGN-PATH 1
r="$(base TEST-PATH)"; doc "[ -d constitution ] && echo found" >"$(L TEST-PATH)"; fx TEST-PATH 1
r="$(base ASSIGN-PATH-LEGACY)"; doc "CONST_DIR=constitution   # legacy layout only" >"$(L ASSIGN-PATH-LEGACY)"; fx ASSIGN-PATH-LEGACY 0
r="$(base TEST-PATH-LEGACY)"; doc "[ -d constitution ] && echo legacy layout" >"$(L TEST-PATH-LEGACY)"; fx TEST-PATH-LEGACY 0
r="$(base ASSIGN-SUBMODULE)"; doc "c=submodules/constitution; CONST_DIR=\"\$PWD/submodules/constitution\"" >"$(L ASSIGN-SUBMODULE)"; fx ASSIGN-SUBMODULE 0
r="$(base BAD-FLAG)"; doc "bash submodules/constitution/scripts/real.sh --no-such-flag" >"$(L BAD-FLAG)"; fx BAD-FLAG 1
r="$(base GOOD-FLAG)"; doc "bash submodules/constitution/scripts/real.sh --quiet --help" >"$(L GOOD-FLAG)"; fx GOOD-FLAG 0
r="$(base BLIND-AND-GAP)"; printf '# x\n\n## PROMPT\n\n```\nno script cited at all\n```\n' >"$(L BLIND-AND-GAP)"; mv "$r/docs/prompts/setup/02_middle.md" "$r/docs/prompts/setup/03_middle.md"; fx BLIND-AND-GAP 1
r="$(base NONASCII-NAME)"; doc n >"$r/docs/prompts/setup/03_é.md"; fx NONASCII-NAME 1
r="$(base LATER-HEADING-FENCE)"; printf '# x\n\n## PROMPT\n\nprose only\n\n## Notes\n\n```\nbash submodules/constitution/scripts/real.sh\n```\n' >"$(L LATER-HEADING-FENCE)"; fx LATER-HEADING-FENCE 1
r="$(base TILDE-FENCE)"; printf '# x\n\n## PROMPT\n\n~~~\nbash submodules/constitution/scripts/real.sh --help\n~~~\n' >"$(L TILDE-FENCE)"; fx TILDE-FENCE 0
r="$(base TEN-PLUS)"; for i in 03 04 05 06 07 08 09 10 11; do doc "n$i" >"$r/docs/prompts/setup/${i}_n$i.md"; done; fx TEN-PLUS 0
r="$(base PAD-003)"; doc p >"$r/docs/prompts/setup/003_third.md"; fx PAD-003 1
r="$(base PAD-3)"; doc p >"$r/docs/prompts/setup/3_third.md"; fx PAD-3 1
r="$(base LEGACY-SUBSTRING)"; doc "bash ./constitution/scripts/legacy_tool.sh" >"$(L LEGACY-SUBSTRING)"; fx LEGACY-SUBSTRING 1
r="$(base FOLLOWUP-MISSING-SCRIPT)"; printf -- '---\ntitle: two\nrequires_previous_success: false\n---\n\nRun bash submodules/constitution/scripts/nope_fu.sh\n' >"$r/docs/prompts/setup/followups/02_two.md"; fx FOLLOWUP-MISSING-SCRIPT 1
r="$(base FOLLOWUP-BAD-FLAG)"; printf -- '---\ntitle: two\nrequires_previous_success: false\n---\n\nRun bash submodules/constitution/scripts/real.sh --no-such-flag\n' >"$r/docs/prompts/setup/followups/02_two.md"; fx FOLLOWUP-BAD-FLAG 1
r="$(base FOLLOWUP-GOOD-CITE)"; printf -- '---\ntitle: two\nrequires_previous_success: false\n---\n\nRun bash submodules/constitution/scripts/real.sh --quiet\n' >"$r/docs/prompts/setup/followups/02_two.md"; fx FOLLOWUP-GOOD-CITE 0
r="$(base NO-DIR)"; rm -rf -- "${r:?}/docs/prompts"; fx NO-DIR 2
r="$(base NO-CITATION)"; printf '# x\n\n## PROMPT\n\n```\nno script cited at all\n```\n' >"$(L NO-CITATION)"; fx NO-CITATION 2

classify() { # <gate-path> -> "label:rc ..." for every fixture
  local out="" f lbl rc
  for f in $FIX; do lbl="${f%%:*}"; bash "$1" --root "$tmp/$lbl" >/dev/null 2>&1; rc=$?; out+="$lbl:$rc "; done
  printf '%s' "$out"
}

echo "== Part 1: fixture classification with the real gate =="
got="$(classify "$gate")"
for f in $FIX; do
  lbl="${f%%:*}"; want="${f##*:}"
  have="$(printf '%s' "$got" | tr ' ' '\n' | sed -n "s/^${lbl}:\(.*\)$/\1/p")"
  if [ "$have" = "$want" ]; then echo "OK   $lbl rc=$have"; else echo "BAD  $lbl rc=$have want=$want"; bad=$((bad + 1)); fi
done

echo "== Part 2: gate mutants =="
mutant() { # <name> <sed-expression>
  local m="$tmp/mutant_$1.sh"
  sed -e "$2" "$gate" >"$m"
  if cmp -s "$m" "$gate"; then echo "BAD  mutant $1: sed did not change the gate (stale mutation)"; bad=$((bad + 1)); return; fi
  if [ "$(classify "$m")" = "$got" ]; then echo "BAD  mutant $1 SURVIVED"; bad=$((bad + 1)); else echo "OK   mutant $1 killed"; fi
}
mutant skip-latest-check        's/^MUT_LATEST=1$/MUT_LATEST=0/'
mutant skip-block-check         's/^MUT_BLOCK=1$/MUT_BLOCK=0/'
mutant skip-citation-check      's/^MUT_CITE=1$/MUT_CITE=0/'
mutant skip-legacy-check        's/^MUT_LEGACY=1$/MUT_LEGACY=0/'
mutant skip-numbering-check     's/^MUT_NUMBERING=1$/MUT_NUMBERING=0/'
mutant skip-followup-check      's/^MUT_FOLLOWUPS=1$/MUT_FOLLOWUPS=0/'
mutant skip-control-needle      's/^MUT_NEEDLE=1$/MUT_NEEDLE=0/'
mutant legacy-word-not-needed   's/legacy_ok_re=.*$/legacy_ok_re="."/'
mutant no-submodule-add-form    "/^stale_re=/s/|(git submodule add.*'\$/'/"
mutant no-symlink-check         's/ \[ -L "\$latest" \] || / /'
mutant no-followup-stale-check  's/^    fstale="\$(grep -E "\$stale_re" "\$f" || true)"$/    fstale=""/'
mutant no-dotdot-refusal        '/case "\$c" in \*\.\.\*)/d'
mutant no-flag-check            's/^MUT_FLAGS=1$/MUT_FLAGS=0/'
mutant no-assign-test-forms     's/^stale_ext=1$/stale_ext=0/'
mutant blind-short-circuits     's/^  blind=1  # needle-blind$/  echo "VERDICT: BLIND"; exit 2/'
mutant locale-dependent         's/^export LC_ALL=C$/export LC_ALL=en_US.UTF-8/'
mutant lexical-sort            's/sort -n)$/sort)/'
mutant non-canonical-allowed   's/^MUT_CANON=1$/MUT_CANON=0/'
mutant followup-cites-skipped  's/^MUT_FU_CITE=1$/MUT_FU_CITE=0/'
mutant legacy-substring        's/^legacy_ok_re=.*$/legacy_ok_re="[Ll][Ee][Gg][Aa][Cc][Yy]"/'
mutant block-check-old-awk     's/^      if ! spx_has_prompt_block "\$latest"; then  # block-check$/      if ! awk '"'"'\/^## PROMPT\/{h=1;next} h\&\&\/^```\/{if(inb){c=1;exit} inb=1;next} inb\&\&\/[^[:space:]]\/{t=1} END{exit !(c\&\&t)}'"'"' "$latest"; then/'
mutant block-accepts-blank     's/^      if ! spx_has_prompt_block "\$latest"; then  # block-check$/      if ! spx_extract_prompt "$latest" >\/dev\/null; then/'
mutant fail-is-pass            's/^  exit 1  # verdict-fail$/  exit 0/'

echo "== Part 3: real repository =="
bash "$gate" --root "$repo"; echo "real-repo rc=$?"

if [ "$bad" -eq 0 ]; then echo "META RESULT: PASS (all fixtures classified, all mutants killed)"; exit 0; fi
echo "META RESULT: FAIL ($bad problems)"; exit 1
