#!/usr/bin/env bash
# cm_setup_prompt_latest_present.sh — CM-SETUP-PROMPT-LATEST-PRESENT gate.
#
# Asserts that the constitution's setup prompt set is usable by the installer
# (scripts/install_constitution.sh reads the first fenced block under the
# `## PROMPT` heading of docs/prompts/setup/latest.md) and is not stale:
#   (1) docs/prompts/setup/latest.md exists, is a regular file, non-empty;
#   (2) it has a `## PROMPT` heading followed by a closed fenced block with at
#       least one non-blank line, judged by the ONE shared extractor
#       scripts/lib/setup_prompt_extract.sh (installer semantics: backtick or tilde
#       fences; a fence under a LATER `## ` heading is not the prompt); the only
#       deliberate extra rule is "at least one non-blank line" (the installer
#       accepts a whitespace-only block);
#   (3) every script it (and every follow-up NN_name.md) cites exists in this repository: every
#       `submodules/constitution/<path>.sh|.py` and every bare `scripts/<path>.sh|.py`
#       token, and every raw-URL `main/scripts/<path>` / `file=scripts/<path>` token,
#       resolves to <root>/<path>; a citation containing `..` is refused.
#       FLAGS: on a line that names a cited script, every `--flag` token written
#       after the script's name must occur literally in that script's source (a
#       textual check: it proves the script mentions the flag, not that it
#       parses it). CONTROL NEEDLE (§11.4.201(7)(b), §11.4.273): the citation
#       extractor must find at least one citation, otherwise that part is BLIND,
#       never PASS (a zero from a blind instrument is not evidence); the other
#       checks still run, and any FAIL wins over BLIND;
#   (4) no stale default path: every line with a `./constitution` or `constitution/`
#       path token (submodules/constitution/ excluded), or with the bare word
#       `constitution` as the path operand of `git submodule add`, `cd` or
#       `git -C`, or assigned (`X=constitution`) or tested (`[ -d constitution ]`),
#       must carry the explicit marker: the WHOLE word "legacy" on that same line
#       (case-insensitive; "legacy_tool.sh" or "illegacy" do not count) — the
#       standard layout is submodules/constitution;
#   (5) the numbered history `NN_name.md` is gap-free (1..N), unique, numbered
#       canonically (two digits below 100, no extra zero padding: 03_x not 003_x
#       or 3_x; 100 and up unpadded), names are
#       lowercase ASCII snake_case (LC_ALL=C is forced, so the verdict does
#       not depend on the caller's locale); no interrupted rotation (.rotate.lock) is present;
#   (6) when docs/prompts/setup/followups/ exists: every `NN_name.md` has a `---`
#       front matter with `title:` and `requires_previous_success: true|false`,
#       and its numbering is gap-free and unique.
#
# Usage:   cm_setup_prompt_latest_present.sh [--root DIR] | --help
#          DIR = the constitution repository root (default: two levels above this script)
# Exit:    0 PASS · 1 FAIL · 2 BLIND (setup directory unreadable/absent, or the
#          citation control needle found nothing) · 64 usage error.
#          The last stdout line is `VERDICT: PASS|FAIL|BLIND`.
# Paired mutation test: cm_setup_prompt_latest_present_mutation_test.sh (§1.1).
# Environment: SETUP_PROMPT_EXTRACT_LIB = path of the shared extractor library
#          (default: ../lib/setup_prompt_extract.sh next to this gate; missing => BLIND).
#          The library is sourced, so an override that does not resolve to that same
#          file is refused (BLIND) unless SETUP_PROMPT_EXTRACT_LIB_TRUST=1 marks the
#          environment as trusted (tests only).
# Read-only; no network. Dependencies: bash, awk, grep, sed, sort.
# Classification: universal (§11.4.17).
set -uo pipefail
export LC_ALL=C

# Check switches: each is a literal line so the paired mutation test can flip it.
MUT_LATEST=1
MUT_BLOCK=1
MUT_CITE=1
MUT_LEGACY=1
MUT_NUMBERING=1
MUT_FOLLOWUPS=1
MUT_NEEDLE=1
MUT_FLAGS=1
MUT_CANON=1
MUT_FU_CITE=1
stale_ext=1
legacy_ok_re="(^|[^A-Za-z0-9_])[Ll][Ee][Gg][Aa][Cc][Yy]([^A-Za-z0-9_]|\$)"
# a path token ./constitution or constitution/ (not submodules/constitution/), or the
# bare word `constitution` used as the path operand of submodule add / cd / git -C
stale_re='(^|[^A-Za-z0-9_./-])(\./constitution|constitution/)|(git submodule add[^#]*[[:space:]]|cd[[:space:]]+|git -C[[:space:]]+)(\./)?constitution([[:space:];&|)]|$)'
# assignment (X=constitution, X="./constitution") and file tests ([ -d constitution ])
if [ "$stale_ext" = 1 ]; then
  stale_re="$stale_re"'|=["'"'"']?(\./)?constitution(["'"'"'[:space:];&|)]|$)|-[defLrwx][[:space:]]+["'"'"']?(\./)?constitution(["'"'"'[:space:]]|\]|$)'
fi

root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "usage: --root needs a value" >&2; exit 64; }; root="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$root" ] || root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

own_lib="$(dirname "${BASH_SOURCE[0]}")/../lib/setup_prompt_extract.sh"
spx_lib="${SETUP_PROMPT_EXTRACT_LIB:-$own_lib}"
# The library is SOURCED (executed): an override is accepted only when it resolves to
# this gate's own scripts/lib/setup_prompt_extract.sh, or when the caller explicitly
# marks the environment as trusted (SETUP_PROMPT_EXTRACT_LIB_TRUST=1, used by tests).
lib_untrusted=0
if [ "$spx_lib" != "$own_lib" ] && [ "${SETUP_PROMPT_EXTRACT_LIB_TRUST:-0}" != 1 ]; then
  a="$(readlink -f -- "$spx_lib" 2>/dev/null)"; b="$(readlink -f -- "$own_lib" 2>/dev/null)"
  if [ -z "$a" ] || [ "$a" != "$b" ]; then lib_untrusted=1; fi
fi
setup="$root/docs/prompts/setup"
latest="$setup/latest.md"
fails=0
blind=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

if [ ! -d "$setup" ] || [ ! -r "$setup" ]; then
  echo "BLIND: setup directory missing or unreadable: $setup"
  echo "VERDICT: BLIND"; exit 2
fi

name_re='^[a-z][a-z0-9]*(_[a-z0-9]+)*$'
canon_num() { local n=$((10#$1)); if [ "$n" -lt 100 ]; then printf '%02d' "$n"; else printf '%d' "$n"; fi; }
check_numbering() { # <dir> <label>
  local d="$1" lbl="$2" f b num name expect=1
  local -A seen=()
  for f in "$d"/*.md; do
    [ -e "$f" ] || continue
    b="${f##*/}"
    [[ "$b" =~ ^([0-9]+)_(.*)\.md$ ]] || continue
    num=$((10#${BASH_REMATCH[1]})); name="${BASH_REMATCH[2]}"
    if [ "$MUT_CANON" = 1 ] && [ "${BASH_REMATCH[1]}" != "$(canon_num "${BASH_REMATCH[1]}")" ]; then
      fail "$lbl: non-canonical number prefix in $b (use $(canon_num "${BASH_REMATCH[1]}")_$name.md)"
    fi
    [[ "$name" =~ $name_re ]] || fail "$lbl: file name not lowercase snake_case: $b"
    if [ -n "${seen[$num]:-}" ]; then fail "$lbl: duplicate number $num (${seen[$num]}, $b)"; fi
    seen[$num]="$b"
  done
  while IFS= read -r num; do
    [ -n "$num" ] || continue
    if [ "$num" -ne "$expect" ]; then fail "$lbl: numbering gap: expected $expect, found $num"; break; fi
    expect=$((expect + 1))
  done < <(printf '%s\n' "${!seen[@]}" | sort -n)
  echo "INFO: $lbl numbered files: $((expect - 1))"
}

# cite_check <file> <label>: every cited script exists ('..' refused); every --flag
# written after a cited script's name on the same line occurs in that script.
# Sets CITE_N (number of distinct citations found).
CITE_N=0
cite_check() {
  local file="$1" lbl="$2" cites c line rest script after b tail_ fl nflag=0
  cites="$( { grep -oE 'submodules/constitution/[A-Za-z0-9_./-]+\.(sh|py)' "$file" | sed 's#^submodules/constitution/##'
              grep -oE '(^|[^A-Za-z0-9_./-])scripts/[A-Za-z0-9_./-]+\.(sh|py)' "$file" | sed -E 's#^[^s]##'
              grep -oE '(main/|file=)scripts/[A-Za-z0-9_./-]+\.(sh|py)' "$file" | sed -E 's#^(main/|file=)##'
            } | sort -u )"
  CITE_N="$(printf '%s\n' "$cites" | grep -c . || true)"
  if [ "$MUT_CITE" = 1 ]; then
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$c" in *..*) fail "$lbl: citation with '..' refused: $c"; continue ;; esac
      [ -f "$root/$c" ] || fail "$lbl: cited script does not exist: $c"
    done <<<"$cites"
  fi
  if [ "$MUT_FLAGS" = 1 ] && [ "$CITE_N" -gt 0 ]; then
    local -A cpath=()
    while IFS= read -r c; do [ -n "$c" ] && cpath["${c##*/}"]="$c"; done <<<"$cites"
    while IFS= read -r line; do
      rest="$line"; script=""; after=""
      while [[ "$rest" =~ ([A-Za-z0-9_]+\.(sh|py))(.*)$ ]]; do
        b="${BASH_REMATCH[1]}"; tail_="${BASH_REMATCH[3]}"
        if [ -n "${cpath[$b]:-}" ]; then script="${cpath[$b]}"; after="$tail_"; fi
        rest="$tail_"
      done
      [ -n "$script" ] && [ -f "$root/$script" ] || continue
      for fl in $(grep -oE '(^|[[:space:]])--[a-z][a-z0-9-]*' <<<"$after" | sed -E 's/^[[:space:]]+//' | sort -u); do
        nflag=$((nflag + 1))
        grep -qF -- "$fl" "$root/$script" || fail "$lbl: flag $fl is not mentioned in $script: $line"
      done
    done <"$file"
    echo "INFO: $lbl flags checked against cited scripts: $nflag"
  fi
}

# (1) latest.md present
if [ "$MUT_LATEST" = 1 ]; then
  if [ ! -f "$latest" ] || [ -L "$latest" ] || [ ! -s "$latest" ]; then
    fail "latest.md missing, not a regular file, or empty: $latest"
  fi
fi

if [ -f "$latest" ]; then
  # (2) PROMPT block
  if [ "$MUT_BLOCK" = 1 ]; then
    # shellcheck source=../lib/setup_prompt_extract.sh
    if [ "$lib_untrusted" = 1 ]; then
      echo "BLIND: refusing extractor library outside this gate's scripts/lib: $spx_lib (set SETUP_PROMPT_EXTRACT_LIB_TRUST=1 only in tests)"
      blind=1
    elif [ -r "$spx_lib" ] && . "$spx_lib" && declare -F spx_has_prompt_block >/dev/null; then
      if ! spx_has_prompt_block "$latest"; then  # block-check
        fail "no '## PROMPT' heading followed by a closed, non-empty fenced block in latest.md (installer extractor)"
      fi
    else
      echo "BLIND: shared extractor library missing or unusable: $spx_lib"
      blind=1
    fi
  fi
  # (3) script citations + control needle (latest.md); follow-ups below
  cite_check "$latest" "latest.md"
  ncite="$CITE_N"
  echo "INFO: script citations found: $ncite"
  if [ "$MUT_NEEDLE" = 1 ] && [ "$ncite" -eq 0 ]; then
    echo "BLIND: the citation extractor found zero script citations in latest.md (control needle failed); the other checks still run"
  blind=1  # needle-blind
  fi
  # (4) stale default path
  if [ "$MUT_LEGACY" = 1 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      grep -qE "$legacy_ok_re" <<<"$line" || fail "non-legacy ./constitution path: $line"
    done < <(grep -nE "$stale_re" "$latest" || true)
  fi
fi

# (5) numbering + interrupted rotation
if [ "$MUT_NUMBERING" = 1 ]; then
  [ ! -e "$setup/.rotate.lock" ] || fail "interrupted rotation: $setup/.rotate.lock present (re-run rotate_setup_prompt.sh to recover)"
  check_numbering "$setup" "setup"
fi

# (6) follow-ups
fu="$setup/followups"
if [ "$MUT_FOLLOWUPS" = 1 ] && [ -d "$fu" ]; then
  check_numbering "$fu" "followups"
  for f in "$fu"/*.md; do
    [ -e "$f" ] || continue
    b="${f##*/}"
    fm="$(awk 'NR==1{if($0!="---")exit; next} /^---$/{exit} {print}' "$f")"
    # here-strings, never `producer | grep -q` under pipefail (a SIGPIPEd producer
    # turns a match into a pipeline failure: a false null, §11.4.273)
    grep -qE '^title: .*[^[:space:]]' <<<"$fm" || fail "followups/$b: front matter lacks title"
    grep -qE '^requires_previous_success: (true|false)$' <<<"$fm" || fail "followups/$b: requires_previous_success must be true|false"
    if [ "$MUT_FU_CITE" = 1 ]; then cite_check "$f" "followups/$b"; fi
    fstale="$(grep -E "$stale_re" "$f" || true)"
    if [ -n "$fstale" ] && grep -qvE "$legacy_ok_re" <<<"$fstale"; then
      fail "followups/$b: non-legacy ./constitution path"
    fi
  done
fi

if [ "$fails" -eq 0 ] && [ "$blind" -eq 1 ]; then echo "VERDICT: BLIND"; exit 2; fi
if [ "$fails" -eq 0 ]; then echo "VERDICT: PASS"; exit 0; fi
echo "VERDICT: FAIL ($fails)"
if true; then
  exit 1  # verdict-fail
fi
