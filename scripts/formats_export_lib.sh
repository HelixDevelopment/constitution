#!/usr/bin/env bash
# formats_export_lib.sh -- ONE shared reader of the "formats export" switch (operator order 2026-10-26).
#
# Purpose:
#   Decide, for every exporter and every sibling-parity gate of a consuming repository, whether Markdown documents
#   may be turned into .html / .pdf / .docx siblings. The DEFAULT is owned HERE (constitution/config/formats_export.conf,
#   shipped as `formats_export=false`): with no environment and no repository override NOTHING is exported and nothing
#   demands an export. Callers source this file and ask; they never parse the conf, the policy file or DOCS_EXPORT
#   themselves.
#
# Resolution order (first match wins; the source is reportable through formats_export_resolve):
#   1. env DOCS_EXPORT   1|true|yes|on => enabled; 0|false|no|off => disabled   (one-run override, any case)
#   2. the repository policy file $ROOT/docs/context/doc_export.policy containing a line  enabled=1   (explicit
#      repository opt-in; a missing file, no such line, or enabled=0 falls through -- the repo can only OPT IN)
#   3. constitution/config/formats_export.conf  key formats_export=true|false   (the single default, false)
#   4. nothing readable / unparsable => disabled (fail-closed)
#
# Usage (sourced):
#   . constitution/scripts/formats_export_lib.sh
#   formats_export_enabled [ROOT]        # rc 0 enabled, rc 1 disabled; prints nothing
#   formats_export_resolve [ROOT]        # prints "<0|1> <env|policy|constitution-default|fail-closed>"
#   formats_export_skip_notice SEAM      # one honest "SKIP" line on stdout (name the seam)
#   formats_export_gate SEAM [ROOT]      # rc 0 enabled (silent); disabled => notice + rc 1.   `gate X || exit 0`
# Root of the consuming repository (for the policy file): the ROOT argument, else $FORMATS_EXPORT_ROOT, else git toplevel.
# Test seams (tests only): FORMATS_EXPORT_CONF (alternative conf path), FORMATS_EXPORT_POLICY (alternative policy path).
# Side effects: none (read-only). Dependencies: bash, grep, sed, git (optional, to find the root).
# Cross-references: scripts/lib/formats_export.sh (the consuming repo's thin wrapper), docs/context/doc_export.policy,
#   scripts/testing/test_formats_export_flag.sh (paired mutations), Constitution section 11.4.65 / 11.4.74 / 11.4.141 M7.

_FE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_fe_truthy() { case "${1:-}" in 1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;; esac; return 1; }
_fe_falsy()  { case "${1:-}" in 0|false|FALSE|False|no|NO|No|off|OFF|Off) return 0 ;; esac; return 1; }

# formats_export_default -- prints true|false from the constitution conf (missing/unparsable => false).
formats_export_default() {
    local conf="${FORMATS_EXPORT_CONF:-$_FE_LIB_DIR/../config/formats_export.conf}" v
    [ -r "$conf" ] || { echo false; return 0; }
    v="$(sed -n 's/^[[:space:]]*formats_export=\([A-Za-z0-9]*\)[[:space:]]*$/\1/p' "$conf" 2>/dev/null | tail -n 1)"
    if _fe_truthy "$v"; then echo true; else echo false; fi
}

# formats_export_resolve [ROOT] -- "<0|1> <source>".
formats_export_resolve() {
    local root="${1:-${FORMATS_EXPORT_ROOT:-}}" policy conf="${FORMATS_EXPORT_CONF:-$_FE_LIB_DIR/../config/formats_export.conf}"
    if _fe_truthy "${DOCS_EXPORT:-}"; then echo "1 env"; return 0; fi
    if _fe_falsy "${DOCS_EXPORT:-}"; then echo "0 env"; return 0; fi
    [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    policy="${FORMATS_EXPORT_POLICY:-${root:+$root/docs/context/doc_export.policy}}"
    if [ -n "$policy" ] && [ -r "$policy" ] && grep -qE '^[[:space:]]*enabled=1[[:space:]]*$' "$policy" 2>/dev/null; then
        echo "1 policy"; return 0
    fi
    if [ ! -r "$conf" ]; then echo "0 fail-closed"; return 0; fi
    if [ "$(formats_export_default)" = "true" ]; then echo "1 constitution-default"; else echo "0 constitution-default"; fi
}

formats_export_enabled() {
    local r; r="$(formats_export_resolve "${1:-}")"
    [ "${r%% *}" = "1" ]
}

formats_export_skip_notice() {
    printf '%s\n' "[formats-export] SKIP (${1:-exporter}): Markdown -> .html/.pdf/.docx export is DISABLED (constitution/config/formats_export.conf default false; operator order 2026-10-26) -- no format sibling is produced, demanded or checked; only .md documents are docs. Enable explicitly: DOCS_EXPORT=1 <command>, or 'enabled=1' in docs/context/doc_export.policy."
}

# formats_export_gate SEAM [ROOT] -- rc 0 when enabled (silent); otherwise print the skip notice and rc 1.
formats_export_gate() {
    if formats_export_enabled "${2:-}"; then return 0; fi
    formats_export_skip_notice "${1:-exporter}"
    return 1
}
