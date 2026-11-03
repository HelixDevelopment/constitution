# shellcheck shell=bash
# scripts/lib/gate_env_override.sh -- verdict-affecting ambient environment overrides of gates (11.4.201(6)-(8), 11.4.276 round 8 class F1).
#
# A gate verdict (FAIL -> PASS, or what is scanned) must never be changeable by a stray environment variable: a baseline
# that lists every offender, an exclude list that prunes the offenders, a scan root pointing at an empty directory, a fake
# interpreter or tool that exits 0, a lowered threshold. Every such variable a verdict-bearing gate reads goes through
# cm_gate_env_set; every OTHER ambient read must be listed (with a kind and a justification) in config/gate_env_allowlist.tsv,
# which scripts/gates/cm_gate_env_reads_allowlisted.sh checks statically against every gate. An explicit CLI flag is not an
# ambient variable and stays honoured by each gate.
#
#   cm_gate_env_set <outvar> <ENV_NAME> <default> <kind: value|path> [--test-root <dir>]... [--trusted <abs-path>]...
#       Sets <outvar> to the guarded value:
#         * ENV_NAME unset or empty            -> <default> (no note).
#         * kind=path, value resolves (readlink -m: symlinks and '..' resolved) to exactly a --trusted path -> honoured
#           (the production tool the gate may be pointed at; returned as the resolved absolute path).
#         * HELIX_TEST_MODE is exactly "1" AND (kind=value, OR kind=path and the resolved path lies strictly under the temp
#           root ${TMPDIR:-/tmp} (itself resolved; a temp root of "/" is refused) or under a resolved --test-root) -> honoured,
#           returned as the RESOLVED ABSOLUTE path (a relative path is never returned as typed: the check and the use would
#           then depend on two different working directories).
#         * anything else -> IGNORED with a stderr note, <default> used (fail closed).
#       An honoured override is never invisible: its name is appended to CM_GATE_OVERRIDES_HONOURED (which the gate may print
#       in its verdict line) and a stderr note "gate_env_override: honouring ..." is printed.
#
# BOUNDARY (stated, not hidden; 11.4.6):
#   (a) HELIX_TEST_MODE=1 is the ONLY real barrier. It is itself an ambient variable: a shell that exports HELIX_TEST_MODE=1
#       re-opens every guarded override (value kind entirely, path kind for temp/test-root paths). The guard defends against
#       a stray or leaked single override, not against an actor who sets the test switch on purpose. Honoured overrides are
#       therefore always announced (stderr + CM_GATE_OVERRIDES_HONOURED) so a verdict produced under them is visible.
#   (b) The temp-root check is lexical-after-resolution at call time (readlink -m); a path swapped for a symlink after the
#       check is not re-checked (time-of-check/time-of-use is narrowed, not closed).
#   (c) Only variables routed through this helper are guarded; the census gate is what makes "every other read is
#       allowlisted" true, and it is a static, text-level instrument (see scripts/gates/lib/gate_env_census.py).
#   (d) A child process inherits the whole environment. A tool or interpreter the gate RUNS reads its own variables;
#       the census covers the gate and the libraries it sources, not the programs it starts.
#   (e) readlink -m is a GNU coreutils option; on a host without it every path override resolves to "" and is ignored
#       (fail closed), so a path override cannot be honoured there at all.
CM_GATE_OVERRIDES_HONOURED=""   # never inherited from the environment: a leaked value would forge the verdict line
cm_gate_env_set() {
    local __out="$1" __name="$2" __def="$3" __kind="${4:-value}" __val __root __real __ok=0 __why="" __r
    local -a __troots=() __trusted=()
    shift 4 2>/dev/null || shift $#
    while [ $# -gt 0 ]; do
        case "$1" in
            --test-root) if [ $# -ge 2 ]; then __troots+=("$2"); shift 2; else shift; fi ;;
            --trusted)   if [ $# -ge 2 ]; then __trusted+=("$2"); shift 2; else shift; fi ;;
            *) shift ;;
        esac
    done
    __val="${!__name:-}"
    if [ -z "$__val" ]; then printf -v "$__out" '%s' "$__def"; return 0; fi
    if [ "$__kind" = path ]; then
        __real="$(readlink -m -- "$__val" 2>/dev/null)" || __real=""
        if [ -n "$__real" ] && [ ${#__trusted[@]} -gt 0 ]; then
            for __r in "${__trusted[@]}"; do
                [ -n "$__r" ] || continue
                if [ "$__real" = "$(readlink -m -- "$__r" 2>/dev/null)" ]; then __ok=2; break; fi
            done
        fi
    fi
    if [ "$__ok" = 0 ] && [ "${HELIX_TEST_MODE:-}" = "1" ]; then
        if [ "$__kind" = path ]; then
            __root="$(readlink -m -- "${TMPDIR:-/tmp}" 2>/dev/null)"
            if [ -n "$__root" ] && [ -n "$__real" ] && [ "$__root" != "/" ] && [ "${__real#"$__root"/}" != "$__real" ]; then
                __ok=1
            else
                for __r in ${__troots[@]+"${__troots[@]}"}; do
                    __r="$(readlink -m -- "$__r" 2>/dev/null)" || continue
                    if [ -n "$__r" ] && [ "$__r" != "/" ] && [ -n "$__real" ] && [ "${__real#"$__r"/}" != "$__real" ]; then __ok=1; break; fi
                done
            fi
            [ "$__ok" = 1 ] || __why=" and a path under the temp root"
        else
            __ok=1
        fi
    elif [ "$__ok" = 0 ]; then
        # an if, not "$([ .. ] && echo ..)": that substitution returns 1 for kind=value and a set -e caller would exit
        if [ "$__kind" = path ]; then __why=' and a path under the temp root'; fi
    fi
    if [ "$__ok" != 0 ]; then
        CM_GATE_OVERRIDES_HONOURED="${CM_GATE_OVERRIDES_HONOURED:+$CM_GATE_OVERRIDES_HONOURED,}${__name}"
        if [ "$__kind" = path ]; then printf -v "$__out" '%s' "$__real"; else printf -v "$__out" '%s' "$__val"; fi
        echo "gate_env_override: honouring ${__name}$([ "$__ok" = 2 ] && echo ' (trusted production path)' || echo ' (HELIX_TEST_MODE=1)')" >&2
    else
        echo "gate_env_override: ignoring ${__name} (a verdict-affecting override needs HELIX_TEST_MODE=1${__why}); using the real default" >&2
        printf -v "$__out" '%s' "$__def"
    fi
}
