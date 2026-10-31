#!/usr/bin/env bash
# test_rotate_unit.sh — UNIT tests of the pure functions of
# scripts/prompts/rotate_setup_prompt.sh (sourced with
# ROTATE_SETUP_PROMPT_SOURCE_ONLY=1, so main never runs).
# Real files in mktemp sandboxes; no test doubles.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ ! -r "$ROTATE" ]; then no "rotate script present at $ROTATE"; summary unit; exit 1; fi
# shellcheck disable=SC1090
ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 . "$ROTATE" || { no "source rotate script"; summary unit; exit 1; }

# --- name validation ---------------------------------------------------------
for n in a abc snake_case v73 a1_b2 release_2026_10_29; do
  check "valid name '$n'" rsp_valid_name "$n"
done
for n in "" A Abc "has space" "../x" "a/b" "a-b" "_a" "a_" "a__b" "1abc" "a.md" "a
b" "$(printf 'x%.0s' $(seq 1 65))"; do
  if rsp_valid_name "$n"; then no "invalid name accepted: '$n'"; else ok "invalid name refused: '$(printf %q "$n")'"; fi
done

# --- number formatting -------------------------------------------------------
for pair in 1:01 3:03 9:09 10:10 99:99 100:100 101:101 999:999 1000:1000; do
  got="$(rsp_format_number "${pair%%:*}")"
  [ "$got" = "${pair##*:}" ] && ok "format ${pair%%:*} -> $got" || no "format ${pair%%:*} -> $got (want ${pair##*:})"
done

# --- next number over real files ---------------------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
got="$(rsp_next_number "$D")"; [ "$got" = 3 ] && ok "next number after 01,02 is 3" || no "next number got '$got' want 3"
touch "$D/03_x.md" "$D/08_y.md"
got="$(rsp_next_number "$D")"; [ "$got" = 9 ] && ok "next number after 08 (octal-looking) is 9" || no "next number got '$got' want 9"
touch "$D/README.md" "$D/notes.txt" "$D/latest.md.bak"
got="$(rsp_next_number "$D")"; [ "$got" = 9 ] && ok "non-numbered files ignored" || no "non-numbered files changed next number: '$got'"
S2="$(mk_sandbox)"; D2="$S2/docs/prompts/setup"; mkdir -p "$D2"; touch "$D2/99_a.md"
got="$(rsp_next_number "$D2")"; [ "$got" = 100 ] && ok "next after 99 is 100" || no "next after 99 got '$got'"
touch "$D2/100_b.md"
got="$(rsp_next_number "$D2")"; [ "$got" = 101 ] && ok "next after 99,100 is 101 (numeric, not lexical max)" || no "next after 99,100 got '$got' (lexical max would give 100)"

# --- numbering scan (duplicates / gaps) --------------------------------------
S3="$(mk_sandbox)"; D3="$(mk_setup_dir "$S3")"
check "scan clean 01,02" rsp_scan_numbering "$D3"
touch "$D3/02_dup.md"
if rsp_scan_numbering "$D3" 2>/dev/null; then no "duplicate number 02 accepted"; else ok "duplicate number 02 refused"; fi
S4="$(mk_sandbox)"; D4="$(mk_setup_dir "$S4")"; touch "$D4/04_gap.md"
if rsp_scan_numbering "$D4" 2>/dev/null; then no "gap (missing 03) accepted"; else ok "gap (missing 03) refused"; fi
# canonical numbering: two digits below 100, no extra zero padding
for bad in 003_pad 3_short; do
  S5="$(mk_sandbox)"; D5="$(mk_setup_dir "$S5")"; touch "$D5/$bad.md"
  if rsp_scan_numbering "$D5" 2>"$S5/err"; then no "non-canonical prefix $bad accepted"
  else grep -q 'non-canonical' "$S5/err" && ok "non-canonical prefix $bad refused with a clear message" || no "non-canonical $bad refused without message: $(cat "$S5/err")"; fi
done
S6="$(mk_sandbox)"; D6="$S6/docs/prompts/setup"; mkdir -p "$D6"
for i in $(seq 1 101); do touch "$D6/$(rsp_format_number "$i")_n$i.md"; done
check "canonical 01..99,100,101 accepted" rsp_scan_numbering "$D6"

# --- PROMPT block detection --------------------------------------------------
F="$S/good.md"; prompt_doc g >"$F"
check "prompt block detected" rsp_has_prompt_block "$F"
printf '# x\n\n## PROMPT\n\nno fence here\n' >"$S/nofence.md"
if rsp_has_prompt_block "$S/nofence.md"; then no "missing fence accepted"; else ok "missing fence refused"; fi
printf '# x\n\n## PROMPT\n\n```\nopen only\n' >"$S/open.md"
if rsp_has_prompt_block "$S/open.md"; then no "unclosed fence accepted"; else ok "unclosed fence refused"; fi
printf '# x\n\n```\nblock before heading\n```\n' >"$S/noheading.md"
if rsp_has_prompt_block "$S/noheading.md"; then no "missing PROMPT heading accepted"; else ok "missing PROMPT heading refused"; fi
printf '# x\n\n## PROMPT\n\n```\n\n   \n```\n' >"$S/empty.md"
if rsp_has_prompt_block "$S/empty.md"; then no "blank block accepted"; else ok "blank block refused"; fi

summary unit
