#!/usr/bin/env bash
# lib_badge_row.sh — shared README badge-row parsing helpers for the
# §11.4.259 badge-mechanism gate family (cm_readme_badge_row_at_top.sh,
# cm_badge_closed_color_vocabulary.sh, cm_badge_machine_derived_source.sh,
# cm_badge_self_validated.sh).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.259 mandates a comprehensive badge row at the TOP of README.md,
# immediately below the H1 title and above the introduction — the reader's
# first visual signal. All four gates in this family need the SAME two
# primitives: (1) locate that badge row (or prove it is absent/misplaced),
# (2) parse the individual `![alt](url)` badge entries out of it. This
# library provides both, so each gate composes them rather than
# re-implementing markdown parsing four times.
#
# ── Badge-row location contract ─────────────────────────────────────────────
# The badge row is the FIRST non-blank line strictly AFTER the document's
# first-level heading (`# <title>`) that consists ENTIRELY of one or more
# Markdown image links (`![alt](url)`, optionally separated by whitespace)
# and nothing else. If the first non-blank line after the H1 is NOT
# badge-shaped (ordinary prose, a blockquote, another heading, etc.), there
# is NO badge row at the top — §11.4.259's placement requirement is violated
# and callers MUST treat that as absence, never search further down the
# document for a badge-shaped line elsewhere (a badge row buried mid-document
# is not "at the top" and is NOT what this library reports).
#
# ── Functions ────────────────────────────────────────────────────────────────
#   br_badge_row_text <readme_abs_path>
#       Prints the badge-row line's raw text on stdout (exit 0) if found per
#       the contract above; prints nothing and exits 1 if the file has no H1,
#       or the first non-blank line after the H1 is not badge-shaped, or the
#       file does not exist.
#
#   br_extract_entries <badge_row_text>
#       Reads badge-row text (e.g. via stdin redirection <<<) and emits one
#       line per badge entry: "<alt><TAB><url>". Badges are recognised by the
#       `![alt](url)` Markdown image syntax; anything else on the line is
#       ignored (so a badge row may freely mix inline whitespace/separators
#       between badges).
#
#   br_color_token <url_or_alt>
#       Extracts a color TOKEN from a badge's URL or alt text: the last
#       `-<word>` (or `_<word>`) segment before a query string, OR any
#       standalone occurrence of a closed-vocabulary color word anywhere in
#       the string (case-insensitive). Prints the lowercase token on stdout
#       (exit 0) if a plausible candidate is found, or prints nothing (exit 1)
#       if no color-shaped token is present at all. Does NOT validate the
#       token is in the closed set — that judgement belongs to the calling
#       gate (this function is a pure extraction primitive, reusable by any
#       future vocabulary decision).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.259 (this gate family's mandate), §11.4.6 (no-guessing — badge-row
#   location is a strict positional contract, never a document-wide search),
#   §11.4.28/§11.4.35 (manifests/provenance files are consumer DATA, never
#   project literals in this submodule).
#
# Classification: universal (§11.4.17).

br_badge_row_text() {
    # $1 = absolute path to README
    local readme="$1"
    [ -f "$readme" ] || return 1

    # Find the first H1 line number (a line starting with exactly "# ").
    local h1_line
    h1_line="$(grep -nE '^# ' "$readme" | head -n1 | cut -d: -f1)"
    [ -n "$h1_line" ] || return 1

    # First non-blank line strictly after the H1.
    local candidate
    candidate="$(tail -n +$((h1_line + 1)) "$readme" | grep -m1 -vE '^[[:space:]]*$')"
    [ -n "$candidate" ] || return 1

    # Badge-shaped: after stripping every ![alt](url) occurrence, nothing
    # but whitespace remains.
    local stripped
    # a linked badge `[![alt](img)](link)` (static badges, e.g. a DeepWiki link badge) is badge-shaped too
    stripped="$(printf '%s' "$candidate" | sed -E -e 's/\[!\[[^]]*\]\([^)]*\)\]\([^)]*\)//g' -e 's/!\[[^]]*\]\([^)]*\)//g')"
    if [ -n "${stripped//[$' \t\r\n']/}" ]; then
        return 1
    fi
    # Must contain at least one badge image to count as a badge row.
    if ! printf '%s' "$candidate" | grep -qE '!\[[^]]*\]\([^)]*\)'; then
        return 1
    fi

    printf '%s\n' "$candidate"
    return 0
}

br_extract_entries() {
    # $1 = badge-row text
    local text="$1"
    printf '%s' "$text" | grep -oE '!\[[^]]*\]\([^)]*\)' | while IFS= read -r entry; do
        local alt url
        alt="$(printf '%s' "$entry" | sed -E 's/^!\[([^]]*)\]\(.*/\1/')"
        url="$(printf '%s' "$entry" | sed -E 's/^!\[[^]]*\]\(([^)]*)\)/\1/')"
        printf '%s\t%s\n' "$alt" "$url"
    done
}

br_static_alts() {
    # $1 = project root. Prints, one per line, the alt text of every STATIC (non-derived) badge declared in
    # <root>/config/static_badges.list (see scripts/badges/compute_badges.sh static_badges). Prints nothing when the
    # file is absent. Static badges carry no computed colour/value, so the colour and provenance gates exempt exactly
    # these alts; a badge that is not declared there stays fully subject to both gates.
    local f="$1/config/static_badges.list" line
    [ -f "$f" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in ''|'#'*) continue ;; esac
        printf '%s\n' "$line" | sed -E -n 's/^\[?!\[([^]]*)\]\(.*/\1/p'
    done <"$f"
}

br_color_token() {
    # $1 = url or alt text to extract a color token from
    local s="$1"
    local lower
    lower="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
    # Closed-vocabulary word appearing anywhere as a whole token.
    local tok
    for tok in green amber red gray grey; do
        if printf '%s' "$lower" | grep -qE "(^|[-_/.? =])${tok}([-_/.? =]|\$)"; then
            printf '%s\n' "$tok"
            return 0
        fi
    done
    return 1
}
