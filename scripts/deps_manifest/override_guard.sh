# shellcheck shell=bash
# scripts/deps_manifest/override_guard.sh -- production-safe test-override resolution (11.4.276 round 5, M-3).
#
# cm_hdeps_override <ENV_NAME> <default-path>
#   prints the helper path to use. The env override is honoured ONLY when HELIX_TEST_MODE=1 AND the override
#   resolves (readlink -m) under the temp root (${TMPDIR:-/tmp}); otherwise it is IGNORED with a stderr note and
#   the real default is printed, so a stray variable in a production environment cannot swap the parser.
cm_hdeps_override() {
    local name="$1" def="$2" val root real
    val="${!name:-}"
    [ -n "$val" ] || { printf '%s\n' "$def"; return 0; }
    root="$(readlink -m -- "${TMPDIR:-/tmp}" 2>/dev/null)"
    real="$(readlink -m -- "$val" 2>/dev/null)"
    if [ "${HELIX_TEST_MODE:-}" = "1" ] && [ -n "$root" ] && [ -n "$real" ] && [ "$root" != "/" ] && [ "${real#"$root"/}" != "$real" ]; then
        printf '%s\n' "$val"
    else
        echo "override_guard: ignoring $name (needs HELIX_TEST_MODE=1 and a path under the temp root); using the real helper" >&2
        printf '%s\n' "$def"
    fi
}
