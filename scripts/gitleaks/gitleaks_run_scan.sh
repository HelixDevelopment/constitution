#!/usr/bin/env bash
# gitleaks_run_scan.sh — Helix Universal gitleaks — run a REAL secrets scan +
#                         capture REAL findings as sink-side evidence (§11.4.69).
#
# Purpose      : Run `gitleaks detect` against the INVOCATION project
#                (§11.4.177), covering the full git history by default, and
#                write the REAL findings (JSON) plus a Markdown report to a
#                captured-evidence dir. A PASS here cites the real findings
#                count pulled from gitleaks' own report — never "command
#                exited 0" alone (§11.4 / §11.4.5 / §11.4.69).
# Usage        : bash gitleaks_run_scan.sh [project-root] [-- <extra gitleaks args>]
# Inputs (env) : GITLEAKS_CONFIG override path to a .gitleaks.toml
# Outputs      : Evidence dir containing findings.json, GITLEAKS_SCAN_REPORT.md.
# Exit codes   : 0 scan ran, ZERO leaks found ·
#                1 scan ran, ONE OR MORE leaks found (gitleaks' own convention) ·
#                2 gitleaks missing / scan could not run ·
#                3 INCONCLUSIVE: the attribute control needles were not all seen,
#                  or git could not read the whole history (for example a really
#                  shallow clone); never a PASS
# Side-effects : Creates the evidence dir. Read-only against the scanned repo.
#                Builds and removes one throwaway needle repository under
#                ${TMPDIR:-/tmp} (glrs_selfcheck.*) before the scan.
# Dependencies : bash, git, gitleaks, ../lib/safe_rm.sh
# Cross-ref    : §11.4.184(I) · §11.4.5 · §11.4.6 · §11.4.69 · §11.4.177
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
# CON-435: gitleaks detect reads the full history through its own `git log -p`, which follows
# refs/replace/* unless GIT_NO_REPLACE_OBJECTS is set, so a replace ref can hide a secret commit
# or blob. Export it AFTER the scrub above (which clears a caller's value) so the scanner, which
# inherits this environment, reads the stored objects. git honours any value; measured with
# gitleaks 8.30.1 and git 2.53.0 it also wins over core.useReplaceRefs=true in the repository
# config and in GIT_CONFIG_PARAMETERS (tests/security/test_gitleaks_run_scan_replace.sh).
export GIT_NO_REPLACE_OBJECTS=1
# CON-453: the scanned repository's own .git/info/grafts and .git/shallow also rewrite
# what `git log` walks: a graft can drop the parent of a commit and a shallow entry stops the
# walk there, so the commits behind them (and the secrets in them) are never read. Measured with
# gitleaks 8.30.1 and git 2.53.0: GIT_NO_REPLACE_OBJECTS does not disable grafts. Point both at
# files that hold nothing (after the scrub, which clears a caller's values) so the scan walks the
# stored parents. The graft path is one that cannot exist: any existing graft file, /dev/null
# included, makes git print a deprecation hint on stderr, and gitleaks then stops reading the
# history and reports 0 leaks (measured). A repository that really is shallow (the objects are absent) then makes git
# fail; the pre-flight below turns that into INCONCLUSIVE (exit 3), never a PASS.
export GIT_GRAFT_FILE=/dev/null/no-grafts GIT_SHALLOW_FILE=/dev/null
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./gitleaks_lib.sh
. "${SCRIPT_DIR}/gitleaks_lib.sh"

PROJ_ARG=""; EXTRA_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --) shift; while [ "$#" -gt 0 ]; do EXTRA_ARGS+=("$1"); shift; done ;;
        *) if [ -z "${PROJ_ARG}" ]; then PROJ_ARG="$1"; fi; shift ;;
    esac
done
ROOT="$(gl_project_root "${PROJ_ARG}")"
[ -d "${ROOT}" ] || { gl_err "project root not found: ${PROJ_ARG:-$PWD}"; exit 2; }

gl_have_gitleaks || { gl_err "gitleaks not on PATH — run gitleaks_install_check.sh"; exit 2; }

EVID="$(gl_evidence_dir "${ROOT}")"
mkdir -p "${EVID}"
gl_log "project root : ${ROOT}"
gl_log "evidence dir : ${EVID}"

CFG_ARGS=()
if [ -n "${GITLEAKS_CONFIG:-}" ] && [ -f "${GITLEAKS_CONFIG}" ]; then
    CFG_ARGS=(--config "${GITLEAKS_CONFIG}")
    gl_log "using config: ${GITLEAKS_CONFIG}"
elif [ -f "${ROOT}/.gitleaks.toml" ]; then
    CFG_ARGS=(--config "${ROOT}/.gitleaks.toml")
    gl_log "using project config: ${ROOT}/.gitleaks.toml"
fi

# CON-453 (CON-438 class): gitleaks detect reads the history through its own
# `git log -p -U0 ...`, and git applies diff attributes to that output. A path marked -diff
# (or `binary`, or a diff driver with binary=true) is shown as "Binary files differ", and a
# diff driver with a textconv shows the converted text; either way gitleaks never sees the
# added lines (measured live with gitleaks 8.30.1 and git 2.53.0: exit 0, 0 leaks). The
# attribute can come from the scanned history itself (a committed .gitattributes), from
# .git/info/attributes, from attr.tree, or from the caller (core.attributesFile at any config
# level, the default $XDG_CONFIG_HOME/git/attributes, GIT_CONFIG_PARAMETERS/COUNT,
# GIT_ATTR_SOURCE). No environment setting reaches all of these, so the fix works on the
# effect: --text makes git print every change as text whatever the attributes say, and
# --no-textconv turns every textconv off. -m (also forced) prints the diff of a merge against
# each parent, so a secret that exists only in a merge commit (an "evil merge") is read too;
# without it `git log -p` prints no diff for merges at all. They are appended LAST to the log options, so a
# caller value cannot undo them (git: the last of --text/--textconv wins). Without a caller
# --log-opts the value starts with gitleaks 8.30.1's own default (measured from its argv:
# `--full-history --all --diff-filter=tuxdb`), because --log-opts replaces that default.
GLRS_TEXT_OPTS="-m --text --no-textconv"
GLRS_DEFAULT_LOG_OPTS="--full-history --all --diff-filter=tuxdb"
SCAN_ARGS=(); _glrs_lo=0; _glrs_i=0
while [ "${_glrs_i}" -lt "${#EXTRA_ARGS[@]}" ]; do
    _glrs_a="${EXTRA_ARGS[${_glrs_i}]}"
    case "${_glrs_a}" in
        --log-opts=*) SCAN_ARGS+=("${_glrs_a} ${GLRS_TEXT_OPTS}"); _glrs_lo=1 ;;
        --log-opts)
            if [ $((_glrs_i + 1)) -lt "${#EXTRA_ARGS[@]}" ]; then
                _glrs_i=$((_glrs_i + 1))
                SCAN_ARGS+=(--log-opts "${EXTRA_ARGS[${_glrs_i}]} ${GLRS_TEXT_OPTS}"); _glrs_lo=1
            else
                gl_err "--log-opts needs a value"; exit 2
            fi ;;
        *) SCAN_ARGS+=("${_glrs_a}") ;;
    esac
    _glrs_i=$((_glrs_i + 1))
done
[ "${_glrs_lo}" = 1 ] || SCAN_ARGS+=(--log-opts "${GLRS_DEFAULT_LOG_OPTS} ${GLRS_TEXT_OPTS}")
unset _glrs_a _glrs_i _glrs_lo

# Positive evidence for the options above (§11.4.201(7)(b), §11.4.273): before the real scan,
# the SAME gitleaks binary, in the SAME environment, scans a throwaway repository whose needles
# are hidden by attributes: n.env is marked -diff (found only if --text is honoured), t.env has
# a diff driver whose textconv prints nothing (found only if --no-textconv is honoured), m.env
# exists only in a merge commit (found only if -m is honoured), and c.txt holds plain text
# (must NOT be found). A miss means this scan cannot see what the
# attributes hide, and the run stops as INCONCLUSIVE (exit 3), never PASS. The needle values
# are random per run and never printed.
glrs_attr_selfcheck() {
    local sc rc nn nt nm nc
    [ -f "${SCRIPT_DIR}/../lib/safe_rm.sh" ] || { gl_err "missing ${SCRIPT_DIR}/../lib/safe_rm.sh"; return 2; }
    # shellcheck source=../lib/safe_rm.sh
    . "${SCRIPT_DIR}/../lib/safe_rm.sh" || return 2
    sc="$(mktemp -d "${TMPDIR:-/tmp}/glrs_selfcheck.XXXXXX")" || return 2
    rc=0
    (
        set -e
        export GIT_AUTHOR_NAME=glrs-needle GIT_AUTHOR_EMAIL=needle@invalid GIT_COMMITTER_NAME=glrs-needle GIT_COMMITTER_EMAIL=needle@invalid
        r="${sc}/r"
        tn="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-36)"
        tt="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-36)"
        tm="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-36)"
        [ "${#tn}" -eq 36 ] && [ "${#tt}" -eq 36 ] && [ "${#tm}" -eq 36 ]
        git init -q "${r}"
        git -C "${r}" config diff.glrsneedle.textconv true
        printf 'n.env -diff\nt.env diff=glrsneedle\n' >"${r}/.gitattributes"
        bn="$(printf 'T=%s%s\n' "gh""p_" "${tn}" | git -C "${r}" hash-object -w --stdin)"
        bt="$(printf 'T=%s%s\n' "gh""p_" "${tt}" | git -C "${r}" hash-object -w --stdin)"
        bc="$(printf 'glrs negative control, plain text\n' | git -C "${r}" hash-object -w --stdin)"
        t="$(printf '100644 blob %s\tc.txt\n100644 blob %s\tn.env\n100644 blob %s\tt.env\n' "${bc}" "${bn}" "${bt}" | git -C "${r}" mktree)"
        c="$(git -C "${r}" commit-tree "${t}" -m glrs-needle)"
        e="$(git -C "${r}" mktree </dev/null)"
        c="$(git -C "${r}" commit-tree "${e}" -p "${c}" -m glrs-needle)"
        # merge-only needle: two empty-tree parents, the merge adds m.env, the next commit drops it
        bm="$(printf 'T=%s%s\n' "gh""p_" "${tm}" | git -C "${r}" hash-object -w --stdin)"
        x="$(git -C "${r}" commit-tree "${e}" -m glrs-x)"
        y1="$(printf 'y1\n' | git -C "${r}" hash-object -w --stdin)"
        y2="$(printf 'y2\n' | git -C "${r}" hash-object -w --stdin)"
        y1="$(git -C "${r}" commit-tree "$(printf '100644 blob %s\ty1.txt\n' "${y1}" | git -C "${r}" mktree)" -p "${x}" -m glrs-y1)"
        y2="$(git -C "${r}" commit-tree "$(printf '100644 blob %s\ty2.txt\n' "${y2}" | git -C "${r}" mktree)" -p "${x}" -m glrs-y2)"
        m="$(git -C "${r}" commit-tree "$(printf '100644 blob %s\tm.env\n100644 blob %s\ty1.txt\n100644 blob %s\ty2.txt\n' "${bm}" \
            "$(git -C "${r}" rev-parse "${y1}:y1.txt")" "$(git -C "${r}" rev-parse "${y2}:y2.txt")" | git -C "${r}" mktree)" -p "${y1}" -p "${y2}" -m glrs-merge)"
        m="$(git -C "${r}" commit-tree "$(git -C "${r}" rev-parse "${y1}^{tree}")" -p "${m}" -m glrs-drop)"
        git -C "${r}" update-ref refs/heads/main "${c}"
        git -C "${r}" update-ref refs/heads/merge "${m}"
    ) >"${sc}/setup.log" 2>&1 || rc=2
    if [ "${rc}" = 0 ]; then
        ( cd "${sc}/r" && gitleaks detect --source "${sc}/r" --report-format json \
            --report-path "${sc}/needle.json" --no-banner \
            --log-opts "${GLRS_DEFAULT_LOG_OPTS} ${GLRS_TEXT_OPTS}" ) >"${sc}/needle.log" 2>&1
        case "$?" in 0|1) ;; *) rc=2 ;; esac
        nn=0; nt=0; nm=0; nc=0
        if [ -s "${sc}/needle.json" ]; then
            nn="$(grep -c '"File": *"n\.env"' "${sc}/needle.json")"
            nt="$(grep -c '"File": *"t\.env"' "${sc}/needle.json")"
            nm="$(grep -c '"File": *"m\.env"' "${sc}/needle.json")"
            nc="$(grep -c '"File": *"c\.txt"' "${sc}/needle.json")"
        fi
        gl_log "control needles: -diff=${nn} textconv=${nt} merge=${nm} negative=${nc}"
        if [ "${rc}" = 0 ] && { [ "${nn}" -lt 1 ] || [ "${nt}" -lt 1 ] || [ "${nm}" -lt 1 ] || [ "${nc}" -ne 0 ]; }; then rc=3; fi
    fi
    safe_rm_rf "${sc:?}" || gl_err "cleanup refused for ${sc}"
    return "${rc}"
}
glrs_attr_selfcheck; _glrs_sc=$?
if [ "${_glrs_sc}" = 3 ]; then
    gl_err "INCONCLUSIVE: the control needles were not all seen (this scan cannot see what git attributes hide, or merge diffs)"
    echo "INCONCLUSIVE: gitleaks scan not trusted (attribute control needles failed)"
    exit 3
elif [ "${_glrs_sc}" != 0 ]; then
    gl_err "the attribute self-check could not run"; exit 2
fi

# Git pre-flight (measured with gitleaks 8.30.1: when its `git log` fails, for example on a
# really shallow clone, gitleaks logs "stderr is not empty", scans 0 commits and exits 0 with
# no leaks, a false PASS). Run the same git log, with the same options and environment, and
# require exit 0 and an empty stderr; otherwise the history cannot be read and the run is
# INCONCLUSIVE. Not done with --no-git (no history is read then).
_glrs_lopt=""; _glrs_nogit=0; _glrs_i=0
while [ "${_glrs_i}" -lt "${#SCAN_ARGS[@]}" ]; do
    case "${SCAN_ARGS[${_glrs_i}]}" in
        --log-opts=*) _glrs_lopt="${SCAN_ARGS[${_glrs_i}]#--log-opts=}" ;;
        --log-opts) _glrs_i=$((_glrs_i + 1)); _glrs_lopt="${SCAN_ARGS[${_glrs_i}]}" ;;
        --no-git|--no-git=true) _glrs_nogit=1 ;;
    esac
    _glrs_i=$((_glrs_i + 1))
done
if [ "${_glrs_nogit}" = 0 ]; then
    # gitleaks splits --log-opts on spaces; so does this unquoted expansion.
    # shellcheck disable=SC2086
    git -C "${ROOT}" log -p -U0 ${_glrs_lopt} >/dev/null 2>"${EVID}/git_preflight.err"; _glrs_grc=$?
    if [ "${_glrs_grc}" != 0 ] || [ -s "${EVID}/git_preflight.err" ]; then
        gl_err "INCONCLUSIVE: git could not read the whole history (git log exit ${_glrs_grc}; see ${EVID}/git_preflight.err)"
        _glrs_cd="$(git -C "${ROOT}" rev-parse --git-common-dir 2>/dev/null)"
        case "${_glrs_cd}" in /*) ;; ?*) _glrs_cd="${ROOT}/${_glrs_cd}" ;; esac
        if [ -n "${_glrs_cd}" ] && [ -s "${_glrs_cd}/shallow" ]; then gl_err "the repository is shallow: fetch the full history (git fetch --unshallow) and scan again"; fi
        echo "INCONCLUSIVE: gitleaks scan not run (git could not read the whole history)"
        exit 3
    fi
fi
unset _glrs_lopt _glrs_nogit _glrs_i _glrs_grc _glrs_cd

gl_log "running gitleaks detect (full history) ..."
set +e
( cd "${ROOT}" && gitleaks detect \
    --source "${ROOT}" \
    --report-format json \
    --report-path "${EVID}/findings.json" \
    --no-banner \
    "${CFG_ARGS[@]}" \
    "${SCAN_ARGS[@]}" ) >"${EVID}/gitleaks.log" 2>&1
SCAN_RC=$?
set -e 2>/dev/null || true

# gitleaks' own convention: 0 = no leaks, 1 = leaks found, >1 = scan error.
if [ "${SCAN_RC}" -gt 1 ]; then
    gl_err "gitleaks exited ${SCAN_RC} (scan error) — see ${EVID}/gitleaks.log"
    tail -20 "${EVID}/gitleaks.log" >&2 || true
    exit 2
fi

TOTAL=0
if [ -s "${EVID}/findings.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        TOTAL="$(jq 'length' "${EVID}/findings.json" 2>/dev/null || echo 0)"
    else
        TOTAL="$(grep -c '"RuleID"' "${EVID}/findings.json" 2>/dev/null || echo 0)"
    fi
fi
TOTAL="${TOTAL:-0}"

REPORT="${EVID}/GITLEAKS_SCAN_REPORT.md"
{
    echo "# gitleaks Scan Report"
    echo
    echo "**Revision:** 1"
    echo "**Last modified:** $(date -u +%FT%TZ)"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Project root | \`${ROOT}\` |"
    echo "| gitleaks | $(gitleaks version 2>&1 | head -1) |"
    echo "| Real findings (leaks) | **${TOTAL}** |"
    echo
    echo "Full finding list captured at \`findings.json\` in this directory as the §11.4.69 sink-side evidence for this scan."
} >"${REPORT}"

echo "----------------------------------------------------------------------"
if [ "${SCAN_RC}" -eq 0 ]; then
    echo "PASS: gitleaks scan completed — ${TOTAL} real leak(s) found"
else
    echo "FAIL: gitleaks scan completed — ${TOTAL} real leak(s) found"
fi
echo "      [evidence: ${EVID}]"
echo "----------------------------------------------------------------------"
exit "${SCAN_RC}"
