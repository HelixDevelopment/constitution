#!/usr/bin/env bash
# Render article Markdown sources into standalone HTML fragments for the
# "Read more" modal. Universal + reusable across sites and languages.
#
# Convention:
#   SOURCES:  <site-root>/_article_src/<lang>/*.md   (underscore dir => Jekyll-excluded)
#   OUTPUT:   <site-root>/articles/<lang>/*.html      (no front-matter => served verbatim)
#
# Usage: render-articles.sh <site-root> <lang> [<lang> ...]
# Pipeline: extract frontmatter (title/repo/tech) -> pandoc(body md->html5) -> wrap fragment.
set -euo pipefail
# Operator order 2026-10-26 ("stop exporting Markdown docs into other formats"): Markdown -> HTML rendering is gated by the
# constitution's ONE formats-export switch (config/formats_export.conf, default false). OFF => announced skip, rc 0.
# shellcheck source=../formats_export_lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/formats_export_lib.sh"
formats_export_gate render-articles "${FORMATS_EXPORT_ROOT:-$PWD}" || exit 0
command -v pandoc >/dev/null || { echo "pandoc required"; exit 1; }

root="${1:?site-root required}"; shift
for lang in "$@"; do
  src="$root/_article_src/$lang"; out="$root/articles/$lang"
  [ -d "$src" ] || { echo "skip (no src dir): $src"; continue; }
  mkdir -p "$out"; n=0
  for md in "$src"/*.md; do
    [ -e "$md" ] || continue
    slug="$(basename "$md" .md)"
    title="$(awk '/^title:/{sub(/^title:[[:space:]]*/,"");print;exit}' "$md")"
    repo="$(awk '/^repo:/{sub(/^repo:[[:space:]]*/,"");gsub(/^["'"'"']|["'"'"']$/,"");print;exit}' "$md")"
    tech="$(awk '/^tech:/{sub(/^tech:[[:space:]]*/,"");print;exit}' "$md")"
    awk 'BEGIN{s=0} s==2{print;next} /^---[[:space:]]*$/{s++;next}' "$md" \
      | pandoc -f markdown -t html5 -o /tmp/_art_body.html
    {
      echo "<article class=\"hx-article\">"
      echo "  <header class=\"hx-article-head\">"
      echo "    <h1>${title}</h1>"
      [ -n "$tech" ] && echo "    <p class=\"hx-article-tech\">${tech}</p>"
      [ -n "$repo" ] && echo "    <p class=\"hx-article-repo\"><a href=\"${repo}\" target=\"_blank\" rel=\"noopener\">${repo} &rarr;</a></p>"
      echo "  </header>"
      cat /tmp/_art_body.html
      echo "</article>"
    } > "$out/$slug.html"
    n=$((n+1))
  done
  echo "rendered $n fragment(s) -> $out"
done
