#!/usr/bin/env bash
# cm_release_tag_carry.sh — CM-RELEASE-TAG-CARRY gate (§11.4.151 decimal-carry
# clause; grammar owned by §11.4.235(E.5)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Every release tag and version name of a project (§11.4.151) obeys the
# POSITIONAL-DIGIT ID GRAMMAR of §11.4.235(E.5): in EVERY dotted numeric group
# of the name every non-leftmost position is a single digit 0..9, and the
# leftmost has no leading zero; no two numeric runs are joined by a single
# dash. So `<PREFIX>-1.0.0-dev-0.0.9` is followed by `<PREFIX>-1.0.0-dev-0.1.0`
# and NEVER by `<PREFIX>-1.0.0-dev-0.0.10` (the operator directive of
# 2026-11-25). This gate reads the REAL tag names of a repository (or a tag
# list) and FAILs on any tag of the project's prefix that breaks the grammar.
# It is the tag-level counterpart of the ledger-level CM-VERSION-DECIMAL-CARRY
# check inside cm_version_increment_on_deploy.sh.
#
# Honest scope (§11.4.6): proves no prefixed tag is in the no-carry form. It
# does NOT prove each tag is the immediate successor of the previous one, and
# it ignores tags that do not start with `<PREFIX>-` (prefix naming is
# §11.4.151's own recommended gate CM-RELEASE-PREFIX-NAMING).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_release_tag_carry.sh --prefix <PREFIX> (--repo <dir> | --tags-file <file>)
#                           [--exempt-decision-ref <ref>]
#     --prefix <P>   release prefix (default: $HELIX_RELEASE_PREFIX; one of
#                    the two MUST be set, else exit 2)
#     --repo <dir>   read `git tag -l '<P>-*'` of that repository
#     --tags-file F  read one tag name per line (blank/# lines ignored)
#     --exempt-decision-ref R  the consumer declared a non-positional scheme
#                    (SemVer/CalVer) by recorded operator decision R
#                    (§11.4.235(E.5), §11.4.66): honest SKIP, never a PASS
#     -h|--help      print this header
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; `git tag -l` only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, awk, git (only with --repo). Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.151, §11.4.235(E.5), §11.4.201(1), §11.4.6, §1.1 (paired mutation:
#   cm_release_tag_carry_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL (a tag breaks the grammar) · 2 environment/usage error ·
#   4 SKIP (no prefixed tag yet, or declared exemption) — never read as PASS.
#   Machine-readable line: `VERDICT: PASS|FAIL|ERROR|SKIP`.
#
# Classification: universal (§11.4.17).

set -uo pipefail
GATE="CM-RELEASE-TAG-CARRY"

usage() { sed -n '2,/^# Classification/p' "$0" | sed 's/^# \{0,1\}//'; }
err() { echo "VERDICT: ERROR"; echo "${GATE}: $*" >&2; exit 2; }

prefix="${HELIX_RELEASE_PREFIX:-}"; repo=""; tfile=""; exempt=""
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) [ $# -ge 2 ] || err "--prefix needs a value"; prefix="$2"; shift 2 ;;
        --repo) [ $# -ge 2 ] || err "--repo needs a value"; repo="$2"; shift 2 ;;
        --tags-file) [ $# -ge 2 ] || err "--tags-file needs a value"; tfile="$2"; shift 2 ;;
        --exempt-decision-ref) [ $# -ge 2 ] || err "--exempt-decision-ref needs a value"; exempt="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) err "unknown argument: $1" ;;
    esac
done

[ -n "$prefix" ] || err "no release prefix: pass --prefix or set HELIX_RELEASE_PREFIX (§11.4.151)"
case "$prefix" in *[!A-Za-z0-9_]*) err "prefix '$prefix' has characters outside [A-Za-z0-9_]" ;; esac
[ -n "$repo" ] && [ -n "$tfile" ] && err "give --repo OR --tags-file, not both"
[ -n "$repo" ] || [ -n "$tfile" ] || err "give --repo <dir> or --tags-file <file>"

if [ -n "$exempt" ]; then
    echo "SKIP: declared non-positional scheme, recorded operator decision '${exempt}' (§11.4.235(E.5)); the carry check is not run"
    echo "VERDICT: SKIP"; exit 4
fi

if [ -n "$repo" ]; then
    [ -d "$repo" ] || err "--repo '$repo' is not a directory"
    tags="$(git -C "$repo" tag -l "${prefix}-*" 2>&1)" || err "git tag -l failed in '$repo': $tags"
else
    [ -r "$tfile" ] || err "--tags-file '$tfile' is not readable"
    tags="$(grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$tfile" || true)"
fi
tags="$(printf '%s\n' "$tags" | awk -v p="${prefix}-" 'index($0,p)==1')"
if [ -z "$tags" ]; then
    echo "SKIP: no tag starting with '${prefix}-' (an empty set is never a PASS)"
    echo "VERDICT: SKIP"; exit 4
fi

report="$(printf '%s\n' "$tags" | awk '
function bad(t, why) { printf "FAIL %s: %s\n", t, why; n++ }
{
    t = $0; s = t
    # (ii) two numeric runs joined by a single dash: digit-dash-digit
    if (t ~ /[0-9]-[0-9]/) { bad(t, "two numeric runs joined by a single dash (ambiguous owned group)"); next }
    # every dotted numeric group: runs of digits joined by dots, 2+ positions
    while (match(s, /[0-9]+(\.[0-9]+)+/)) {
        g = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        m = split(g, pos, ".")
        if (pos[1] !~ /^(0|[1-9][0-9]*)$/) bad(t, "leftmost position \"" pos[1] "\" of group " g " has a leading zero")
        for (i = 2; i <= m; i++)
            if (pos[i] !~ /^[0-9]$/) { bad(t, "position \"" pos[i] "\" of group " g " is not a single digit 0..9 (carry required)"); break }
    }
    checked++
}
END { printf "CHECKED %d tag(s), %d violation(s)\n", checked + 0, n + 0; exit (n > 0) }')" && rc=0 || rc=$?

echo "$report"
if [ "$rc" -ne 0 ]; then
    echo "VERDICT: FAIL"; echo "❌ ${GATE}: FAIL — a release tag breaks the decimal-carry grammar (§11.4.151 / §11.4.235(E.5))"; exit 1
fi
echo "VERDICT: PASS"; echo "✅ ${GATE}: PASS — every '${prefix}-' tag obeys the decimal-carry grammar"; exit 0
