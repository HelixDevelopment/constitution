# shellcheck shell=bash
# scripts/deps_manifest/helix_deps_tsv.sh -- bash wrapper (sourced) around helix_deps_tsv.py.
#
# cm_hdeps_tsv <manifest>
#   stdout: one US(0x1f)-separated record per dep: name path ssh_url ref third_party(0|1)
#   return: 0 ok | 3 PyYAML unavailable | 4 unreadable/unparseable/duplicate key | 6 unknown shape
#           | 5 CROSS-CHECK FAILED: parsed dep count != an independent line count of the
#             top-level `deps:` list items (also flow-style non-empty lists, which the cheap count cannot see)
#           | 7 python3 missing
#   On any non-zero return NOTHING is printed to stdout (callers fail closed).
# HELIX_DEPS_TSV_PY overrides the helper path (tests only: needs HELIX_TEST_MODE=1 and a path under the temp root, see override_guard.sh).
_CM_HDEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# cm_hdeps_cheap_count <manifest> : prints the number of list items of the top-level `deps:`
# (items at the smallest dash indent), or `flow` for a non-empty inline value.
cm_hdeps_cheap_count() {
    LC_ALL=C tr -d '\000' < "$1" 2>/dev/null | head -c 1048576 | LC_ALL=C awk '
        { sub(/\r$/, "") }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        /^deps:/ {
            rest = $0; sub(/^deps:[[:space:]]*/, "", rest)
            if (rest ~ /^(#.*)?$/) { inb = 1; next }
            if (rest ~ /^\[[[:space:]]*\][[:space:]]*(#.*)?$/) { inb = 0; next }
            flowx = 1; inb = 0; next
        }
        inb && /^[^[:space:]-]/ { inb = 0 }
        inb && /^[[:space:]]*-([[:space:]]|$)/ {
            match($0, /^[[:space:]]*/); ind = RLENGTH
            if (min < 0 || min == "" || ind < min) min = ind
            c[ind]++
        }
        BEGIN { min = -1 }
        END { if (flowx) print "flow"; else if (min < 0) print 0; else print c[min] }'
}

cm_hdeps_tsv() {
    local mf="$1" py out rc cheap n errf
    # shellcheck disable=SC1091
    . "$_CM_HDEPS_DIR/override_guard.sh"
    py="$(cm_hdeps_override HELIX_DEPS_TSV_PY "$_CM_HDEPS_DIR/helix_deps_tsv.py")"
    command -v python3 >/dev/null 2>&1 || { echo "helix_deps_tsv: python3 missing" >&2; return 7; }
    [ -f "$py" ] || { echo "helix_deps_tsv: parser helper missing: $py" >&2; return 3; }
    errf="$(mktemp)" || return 7
    out="$(python3 -I -B "$py" "$mf" 2>"$errf"; echo "rc=$?")"
    rc="${out##*rc=}"; out="${out%rc=*}"
    if [ "$rc" != 0 ]; then head -n 3 "$errf" >&2; rm -f -- "$errf"; return "$rc"; fi
    rm -f -- "$errf"
    cheap="$(cm_hdeps_cheap_count "$mf")"
    n=0; [ -n "$out" ] && n="$(printf '%s' "$out" | grep -c '')"
    if [ "$cheap" != "$n" ]; then
        echo "helix_deps_tsv: cross-check failed (parsed $n deps, independent list-item count $cheap) in $mf" >&2
        return 5
    fi
    printf '%s' "$out"
    return 0
}
