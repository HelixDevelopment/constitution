#!/usr/bin/env bash
# Proves no markdown LINK to the consumer-side PARALLEL_DEVELOPMENT_METHODOLOGY.md
# remains (the doc is consumer-owned, not shipped here); plain code-span mentions are fine.
# Scope: EVERY tracked *.md/*.html outside submodules (git ls-files; find in the mktemp mutant copies).
# Link shapes caught: inline `[t](path/PARALLEL_DEVELOPMENT_METHODOLOGY...)`, HTML href="...", autolinks <...>, AND reference-style definitions
# `[label]: path/PARALLEL_DEVELOPMENT_METHODOLOGY...` (any indentation up to a code-block-free line start).
# Control needle: the scan must see the code-span mention that is allowed to remain.
# Paired mutants (always run, in a mktemp copy): an injected inline link and an injected reference-style
# definition MUST each make the scanner FAIL; a plain code-span mention MUST NOT.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
PDM='PARALLEL_DEVELOPMENT_METHODOLOGY'
# Link shapes: inline `](..PDM`, reference definition `[l]: ..PDM`, HTML href="..PDM", autolink `<..PDM..>`.
LINK_RE="\\]\\([^)]*$PDM|^[[:space:]]*\\[[^]]+\\]:[[:space:]]*[^[:space:]]*$PDM|href=[\"'][^\"']*$PDM|<[^>[:space:]]*$PDM[^>[:space:]]*>"
list_files() { # $1 root -> NUL-separated *.md/*.html: every TRACKED one outside submodules (git), else a find copy
  local r="$1" top
  top="$(git -C "$r" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ] && [ "$(cd "$r" && pwd -P)" = "$(cd "$top" && pwd -P)" ]; then
    git -C "$r" ls-files -z -- '*.md' '*.html' | grep -zv '^submodules/\|/submodules/'
  else
    ( cd "$r" && find . \( -name '*.md' -o -name '*.html' \) -type f -not -path '*/submodules/*' -print0 | sed -z 's#^\./##' )
  fi
}
scan() { # $1 root -> prints "links needle missing"
  local r="$1" f n m links=0 needle=0 missing=0 nfiles=0
  while IFS= read -r -d '' f; do
    nfiles=$((nfiles+1))
    [ -f "$r/$f" ] || { missing=$((missing+1)); continue; }
    n=$(grep -cE "$LINK_RE" "$r/$f"); links=$((links+n))
    m=$(grep -c "$PDM" "$r/$f"); needle=$((needle+m))
  done < <(list_files "$r")
  [ "$nfiles" -gt 0 ] || missing=$((missing+1))
  echo "$links $needle $missing"
}
# ── paired mutants (self-validation of the scanner) ──
MT="$(mktemp -d)"; : "${MT:?}"; trap 'rm -rf -- "${MT:?}"' EXIT
while IFS= read -r -d '' f; do mkdir -p "$MT/base/$(dirname "$f")"; [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$MT/base/$f"; done < <(list_files "$ROOT")
read -r bl _ _ <<<"$(scan "$MT/base")"
[ "$bl" -eq 0 ] || echo "note: copy already holds $bl link(s)"
for kind in inline refstyle href autolink; do
  cp -r "$MT/base" "$MT/m_$kind"; mkdir -p "$MT/m_$kind/docs/other"
  case "$kind" in
    inline)   printf '\nsee [methodology](docs/guides/%s.md)\n' "$PDM" >> "$MT/m_$kind/docs/other/x.md" ;;
    refstyle) printf '\n[m]: docs/guides/%s.md\n' "$PDM" >> "$MT/m_$kind/docs/other/x.md" ;;
    href)     printf '<p><a href="../guides/%s.md">m</a></p>\n' "$PDM" >> "$MT/m_$kind/docs/other/x.html" ;;
    autolink) printf '\nsee <docs/guides/%s.md>\n' "$PDM" >> "$MT/m_$kind/docs/other/x.md" ;;
  esac
  read -r ml _ _ <<<"$(scan "$MT/m_$kind")"
  [ "$ml" -gt "$bl" ] || { echo "SELFTEST FAIL: $kind-link mutant not detected"; exit 3; }
done
cp -r "$MT/base" "$MT/m_code"; printf '\nsee `PARALLEL_DEVELOPMENT_METHODOLOGY.md` (consumer doc)\n' >> "$MT/m_code/AGENTS.md"
read -r cl _ _ <<<"$(scan "$MT/m_code")"
[ "$cl" -eq "$bl" ] || { echo "SELFTEST FAIL: a code-span mention was counted as a link"; exit 3; }
# ── real scan ──
read -r links needle missing <<<"$(scan "$ROOT")"
fail=0
[ "$missing" -eq 0 ] || { echo "MISSING $missing file(s)"; fail=1; }
[ "$needle" -gt 0 ] || { echo "BLIND: control needle (code-span mention) not seen"; exit 2; }
if [ "$links" -ne 0 ]; then echo "FAIL: $links dead markdown link(s)"; fail=1; else echo "PASS: 0 dead links ($needle mentions kept; inline, reference-style, href and autolink mutants detected over all tracked md/html)"; fi
exit $fail
