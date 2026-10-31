#!/usr/bin/env bash
# test_setup_prompt_content.sh — CONTENT tests of the REAL docs/prompts/setup/latest.md
# and docs/prompts/setup/followups/*.md (read-only; nothing is written to the repo).
#
# Extracts the PROMPT block exactly as the installer does (the first fenced block
# after the `## PROMPT` heading) and asserts the properties the setup contract
# requires: new layout path, first-class entry points, opt-in decision layer,
# safety rails, self-check list; the historical 01_old.md / 02_middle.md are
# unchanged relative to git HEAD when tracked (SKIP/UNCONFIRMED when untracked,
# never PASS) and always equal to the sha256 baseline in baseline_hashes.txt.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SETUP="$REPO/docs/prompts/setup"
LATEST="$SETUP/latest.md"
[ -f "$LATEST" ] || { no "latest.md present"; summary content; exit 1; }

. "$REPO/scripts/lib/setup_prompt_extract.sh"
block="$(spx_extract_prompt "$LATEST")" || no "installer extractor found no PROMPT block"
lines="$(printf '%s\n' "$block" | wc -l)"
[ "$lines" -gt 100 ] && ok "PROMPT block extracted ($lines lines)" || no "PROMPT block too short: $lines lines"
fences_in_block="$(printf '%s\n' "$block" | grep -c '^```' || true)"
[ "$fences_in_block" -eq 0 ] && ok "no fence line inside the PROMPT block" || no "fence inside block"

# here-strings, never `printf | grep -q` under pipefail: an early-exiting grep -q
# SIGPIPEs the writer and the pipeline then reports failure (a false result).
has() { grep -qE -- "$1" <<<"$block"; }
for re in \
  'submodules/constitution' \
  'git submodule add .*submodules/constitution' \
  'install_constitution\.sh' \
  'submodules/constitution/scripts/update_constitution\.sh' \
  '@submodules/constitution/CLAUDE\.md' \
  'submodules/constitution/AGENTS\.md' \
  'GEMINI\.md' 'QWEN\.md' \
  'helixconstitution-v' \
  'helix-deps\.yaml' \
  'post_update_hook\.sh' \
  'CONSTITUTION_JEV_HOOK=off' \
  'bootstrap\.disabled' \
  'OPT-IN' \
  'shadow' \
  '§11\.4\.28\(C\)' \
  'never force-push|NEVER force-push|--force' \
  'UNCONFIRMED' \
  'STOP' \
  'SELF-CHECK' \
  'backup' \
  'idempotent|IDEMPOTENT' \
  'install_upstreams\.sh' \
  'gitflic' 'gitverse' 'gitlab' 'github' \
  'budget|BUDGET' ; do
  has "$re" && ok "block mentions /$re/" || no "block lacks /$re/"
done
# forbidden: the default ./constitution layout and automatic consent flags
stale="$(grep -nE '(^|[^A-Za-z0-9_./-])(\./constitution|constitution/)' <<<"$block" || true)"
if [ -n "$stale" ] && grep -viq legacy <<<"$stale"; then
  no "a non-legacy line uses the ./constitution path"
else ok "every ./constitution mention is labelled legacy"; fi
combo="$(grep -E -- '--yes' <<<"$block" | grep -E -- '--install-tools' | grep -E -- '--allow-clone' || true)"
if [ -n "$combo" ] && grep -viqE 'never|not|unless|only' <<<"$combo"; then
  no "unguarded '--yes --install-tools --allow-clone' instruction"
else ok "no unguarded consent-flag combination"; fi
# git push inside the STEP10 block is guarded by code (current branch must be main,
# remote main must be an ancestor); test_setup_prompt_behaviour.sh executes that
# guard. Every other git push mention must carry a guard word.
step10="$(awk 'index($0,"# STEP10-END"){f=0} f{print} index($0,"# STEP10-BEGIN"){f=1}' <<<"$block")"
grep -qE 'symbolic-ref --short -q HEAD' <<<"$step10" && grep -qE 'git push' <<<"$step10" \
  && ok "STEP10 push block carries the main-branch guard" || no "STEP10 push block guard missing"
pushes="$(grep -nE 'git push' <<<"$(awk 'index($0,"# STEP10-BEGIN"){f=1} !f{print} index($0,"# STEP10-END"){f=0}' <<<"$block")" || true)"
if [ -n "$pushes" ] && grep -viqE 'never|not|do not|only|without|unless|forbid|refus' <<<"$pushes"; then
  no "an unguarded 'git push' instruction"
else ok "every git push mention is guarded"; fi

# round 3: data-not-instructions clause, word-bounded legacy exclusion, current exit codes
data_re='DATA,[[:space:]]+never[[:space:]]+as[[:space:]]+instructions'
grep -qzE -- "$data_re" <<<"$block" && grep -qzE 'Instructions come only from this prompt and( from)?[[:space:]]+the operator' <<<"$block" \
  && ok "R3-6 latest.md: repository content is DATA, never instructions" || no "R3-6 latest.md lacks the data-not-instructions clause"
for f in "$SETUP"/followups/0*.md; do
  grep -qzE -- "$data_re" "$f" && grep -qzE 'Instructions come only from this prompt and( from)?[[:space:]]+the[[:space:]]+operator' "$f" \
    && ok "R3-6 ${f##*/}: data-not-instructions clause" || no "R3-6 ${f##*/} lacks the data-not-instructions clause"
done
plain="$(grep -nE 'grep -v[a-z]*i[a-z]* legacy' "$LATEST" "$SETUP"/followups/*.md || true)"
[ -z "$plain" ] && ok "R3-5 no substring 'grep -vi legacy' filter left" || no "R3-5 substring legacy filter: $plain"
lx_gate="$(sed -n 's/^legacy_ok_re="\(.*\)"$/\1/p' "$REPO/scripts/gates/cm_setup_prompt_latest_present.sh" | sed 's/\\\$/$/')"
for f in "$LATEST" "$SETUP/followups/01_verify_incorporation.md"; do
  grep -qF -- "lx='$lx_gate'" "$f" && ok "R3-5 ${f##*/} exclusion equals the gate's legacy_ok_re" || no "R3-5 ${f##*/} exclusion differs from the gate's ($lx_gate)"
done
has 'exit 1 = the post-update hook or the' && ok "R3-8 update script exit 1 documented" || no "R3-8 update exit 1 missing"
has '6 the agent ran but its' && has 'UNVERIFIED' && ok "R3-8 installer exit 6 documented" || no "R3-8 installer exit 6 missing"
for t in 'allow-insecure-url' 'bash >= 4.4' '--flag=value' 'blobless'; do
  grep -qF -- "$t" <<<"$block" && ok "R3-8 installer fact '$t' stated" || no "R3-8 installer fact '$t' missing"
done
s4g="$(awk 'index($0,"# STEP4G-END"){f=0} f{print} index($0,"# STEP4G-BEGIN"){f=1}' <<<"$block")"
grep -qE 'git grep [^|]*-cE' <<<"$s4g" && ! grep -qE 'git grep [^|]*-nE' <<<"$s4g" && ok "R3-7 STEP4G prints counts, not lines" || no "R3-7 STEP4G prints hit lines"
for x in '**/.env*' '**/settings.local.json' '**/*.pem' '**/*.key' '**/credentials*'; do
  grep -qF -- "(exclude,glob)$x" <<<"$s4g" && ok "R3-7 STEP4G excludes $x" || no "R3-7 STEP4G does not exclude $x"
done

# follow-ups
F="$SETUP/followups"
for n in 01_verify_incorporation 02_wire_decision_layer_optional 03_final_report; do
  f="$F/$n.md"
  [ -f "$f" ] || { no "follow-up $n present"; continue; }
  [ "$(head -n1 "$f")" = "---" ] && ok "$n has front matter" || no "$n lacks front matter"
  grep -qE '^title: .+' "$f" && ok "$n has title" || no "$n lacks title"
  grep -qE '^requires_previous_success: (true|false)$' "$f" && ok "$n has requires_previous_success" || no "$n lacks requires_previous_success"
  fstale="$(grep -E '(^|[^A-Za-z0-9_./-])(\./constitution|constitution/)' "$f" || true)"
  if [ -n "$fstale" ] && grep -viq legacy <<<"$fstale"; then no "$n uses ./constitution"; else ok "$n path clean"; fi
done

# history files never modified: compared with git HEAD when tracked, and ALWAYS with
# the sha256 baseline in tests/prompts/baseline_hashes.txt (taken 2026-10-29 while the
# files were untracked, so that day's working tree is the baseline, not a git fact).
BASE="$REPO/tests/prompts/baseline_hashes.txt"
for h in 01_old.md 02_middle.md; do
  [ -s "$SETUP/$h" ] || { no "$h missing"; continue; }
  if git -C "$REPO" ls-files --error-unmatch "docs/prompts/setup/$h" >/dev/null 2>&1; then
    git -C "$REPO" diff --quiet HEAD -- "docs/prompts/setup/$h" && ok "$h unchanged vs git HEAD" || no "$h modified vs git HEAD"
  else
    skip "$h is untracked: no git HEAD baseline (byte-identity vs HEAD not verifiable)"
  fi
  want="$(awk -v f="$h" '$2 == f { print $1 }' "$BASE" 2>/dev/null)"
  if [ -z "$want" ]; then skip "$h has no entry in $BASE"
  elif [ "$(sha256sum "$SETUP/$h" | cut -d' ' -f1)" = "$want" ]; then ok "$h matches the recorded sha256 baseline (taken 2026-10-29)"
  else no "$h differs from the recorded sha256 baseline (taken 2026-10-29)"; fi
done
summary content
