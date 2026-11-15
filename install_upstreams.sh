#!/usr/bin/env bash
# install_upstreams.sh — Configure every declared upstream as a local
# git remote so a single push fans out to every provider.
#
# Reads ./upstreams/*.sh (preferred, §11.4.29 / CONST-052 lowercase
# snake_case) OR ./Upstreams/*.sh (legacy, kept working during the
# migration window). When both directories exist, the lowercase
# variant wins; old projects with only `Upstreams/` continue to
# function unchanged.
#
# Each declaration MUST export UPSTREAMABLE_REPOSITORY=<git-url>.
# A declaration MAY additionally export UPSTREAMABLE_PRIMARY=1 to name
# itself the fetch source for `origin` (see "Primary selection" below).
#
# Usage (from the constitution submodule root):
#   bash install_upstreams.sh
#
# Constitution: §2.1 "Multi-upstream push is the norm";
# §11.4.29 "Lowercase-Snake_Case-Naming Mandate";
# §11.4.111 "Resolve by stable name, not by enumeration index".
#
# ── Remote naming (§11.4.111) ────────────────────────────────────────
# Every remote's name is a pure function of ITS OWN URL and of the set
# of declared URLs — never of the order declarations happen to be read
# in. Renaming a declaration file can never change any remote's name.
#
# A host contributing exactly ONE declaration keeps the bare host name
# (github, gitlab, gitflic, gitverse). When two or more declarations
# share a base name, the resolver escalates qualification until every
# member of that group is distinct, using the LEAST specific level that
# separates them:
#
#   L0  github                                  (bare — no collision)
#   L1  github_helixdevelopment                 (+ org)
#   L2  gitlab_group_subgroup_a                 (+ full namespace)
#   L3  gitlab_acme_repo1                       (+ namespace and repo)
#   L4  gitlab_com / gitlab_company_com         (full host — hosts differ)
#   L5  gitlab_com_acme_repo                    (full host + full path)
#
# The resolver fails closed ONLY when two DIFFERENT URLs are identical
# in every name-relevant component (e.g. the same repo declared over
# two transports), which is a genuine ambiguity no naming scheme can
# resolve.
#
# ── Primary selection (§11.4.111) ────────────────────────────────────
# `origin` fans out to EVERY upstream on push. Its FETCH url — the pull
# source of truth — is chosen by stable identity, never by position:
#   1. the declaration exporting UPSTREAMABLE_PRIMARY=1, if any;
#   2. otherwise the lexicographically smallest URL.
# Binding it to "whichever file globbed first" would mean a pure file
# rename silently repoints `git pull` — the §11.4.111 defect this
# script exists to avoid.

set -uo pipefail

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run a git command against this repo; abort with a directed error if it
# fails. Never let a failed mutation reach the success banner.
git_must() {
    if ! git -C "${SCRIPT_DIR}" "$@"; then
        echo "ERROR: 'git $*' failed." >&2
        echo "       The repository may now be partially configured." >&2
        echo "       Re-run once the cause is resolved." >&2
        exit 1
    fi
}

# Resolve the upstreams declaration directory. §11.4.29 transition:
# prefer the lowercase form; fall back to the legacy uppercase form so
# old checkouts keep working until they migrate. If neither exists,
# fail with a directed error pointing the user at the snake_case
# canonical name.
if [[ -d "${SCRIPT_DIR}/upstreams" ]]; then
    UPSTREAMS_DIR="${SCRIPT_DIR}/upstreams"
elif [[ -d "${SCRIPT_DIR}/Upstreams" ]]; then
    UPSTREAMS_DIR="${SCRIPT_DIR}/Upstreams"
    echo "WARN: using legacy 'Upstreams/' — please rename to 'upstreams/' per §11.4.29" >&2
else
    echo "ERROR: upstreams directory not found (expected ${SCRIPT_DIR}/upstreams or ${SCRIPT_DIR}/Upstreams)" >&2
    exit 1
fi

# Must run inside a git work-tree
if ! git -C "${SCRIPT_DIR}" rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: ${SCRIPT_DIR} is not a git repository" >&2
    exit 1
fi

declare -a UPSTREAM_URLS=()
declare -a UPSTREAM_BASES=()
declare -a UPSTREAM_HOSTS=()
declare -a UPSTREAM_ORGS=()
declare -a UPSTREAM_NSS=()
declare -a UPSTREAM_PATHS=()
declare -a UPSTREAM_NAMES=()
PRIMARY_URL=""

# Normalise an arbitrary token to lowercase snake_case (§11.4.29).
# printf, not echo: echo would eat a leading -n/-e.
normalise_token() {
    printf '%s' "${1:-}" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's#[^a-z0-9]+#_#g; s#^_+##; s#_+$##'
}

# Split a git URL into host and path. Handles the three real shapes:
#   scheme://[user@]host[:port]/path      (any scheme, incl. git+ssh)
#   [user@]host:path                      (scp-style)
#   /absolute/path                        (local; no host)
# Echoes the host (lowercased, may be empty for a local path).
url_host() {
    local u
    u="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
    case "${u}" in
        *://*)
            u="${u#*://}"      # strip scheme
            u="${u%%/*}"       # authority = [userinfo@]host[:port]
            u="${u##*@}"       # strip userinfo (last @ wins)
            u="${u%%:*}"       # host (drop port)
            printf '%s' "${u}"
            return 0
            ;;
        /*)
            printf ''          # local absolute path — no host
            return 0
            ;;
    esac
    # scp-style requires a colon appearing BEFORE any slash.
    case "${u}" in
        *:*)
            local before="${u%%:*}"
            case "${before}" in
                */*) printf '' ;;                     # colon after a slash
                *)   printf '%s' "${before##*@}" ;;   # strip userinfo
            esac
            ;;
        *) printf '' ;;
    esac
    return 0
}

# Echo the path portion (namespace + repo), with any trailing .git and
# surrounding slashes removed.
url_path() {
    local u="${1:-}"
    case "${u}" in
        *://*)
            u="${u#*://}"
            # Everything before the first '/' is the authority — the
            # remainder is the path. Do NOT strip to '@' first.
            case "${u}" in
                */*) u="${u#*/}" ;;
                *)   u="" ;;
            esac
            ;;
        /*) ;;                                        # local path, as-is
        *)
            case "${u}" in
                *:*)
                    local before="${u%%:*}"
                    case "${before}" in
                        */*) ;;                       # not scp-style
                        *)   u="${u#*:}" ;;
                    esac
                    ;;
            esac
            ;;
    esac
    u="${u%.git}"
    u="${u#/}"
    u="${u%/}"
    printf '%s' "${u}"
    return 0
}

# Decode a HOST into its short base name. Matches are ANCHORED on the
# host, never a substring of the whole URL.
base_name_for_host() {
    local host="${1:-}"
    case "${host}" in
        "")                          printf 'local' ;;
        github.com|*.github.com)     printf 'github' ;;
        gitlab.com|*.gitlab.com)     printf 'gitlab' ;;
        gitflic.ru|*.gitflic.ru)     printf 'gitflic' ;;
        gitverse.ru|*.gitverse.ru)   printf 'gitverse' ;;
        bitbucket.org|*.bitbucket.org) printf 'bitbucket' ;;
        codeberg.org|*.codeberg.org) printf 'codeberg' ;;
        *)                           printf '%s' "${host%%.*}" ;;
    esac
    return 0
}

# ── Read declarations ────────────────────────────────────────────────
# Declarations are sourced in a SUBSHELL, never in this shell (§11.4.1):
#   * a call to `exit` inside a declaration terminates only the subshell;
#   * a declaration cannot clobber this script's own variables.
# An EXIT trap inside the subshell captures exports even when the
# declaration exits early (empirically verified on bash 5.x). Capture
# uses two separate files so a newline inside one value cannot corrupt
# the other.
DECL_URL_CAPTURE="$(mktemp)"
DECL_PRIMARY_CAPTURE="$(mktemp)"
trap 'rm -f "${DECL_URL_CAPTURE}" "${DECL_PRIMARY_CAPTURE}"' EXIT

# Reject captured values containing control characters.
assert_clean_capture() {
    local label="$1" val="$2"
    if [[ "${val}" =~ [[:cntrl:]] ]]; then
        echo "ERROR: captured ${label} contains control characters." >&2
        echo "       Declarations must export a single-line value." >&2
        exit 1
    fi
}

read_declaration() {
    : > "${DECL_URL_CAPTURE}"
    : > "${DECL_PRIMARY_CAPTURE}"
    (
        unset UPSTREAMABLE_REPOSITORY UPSTREAMABLE_PRIMARY
        trap 'printf "%s" "${UPSTREAMABLE_REPOSITORY:-}" > "${DECL_URL_CAPTURE}"; printf "%s" "${UPSTREAMABLE_PRIMARY:-}" > "${DECL_PRIMARY_CAPTURE}"' EXIT
        # shellcheck disable=SC1090
        . "$1" >/dev/null 2>&1
    )
}

shopt -s nullglob
for decl in "${UPSTREAMS_DIR}"/*.sh; do
    if ! read_declaration "${decl}"; then
        echo "ERROR: failed to source declaration: ${decl}" >&2
        echo "       It exited non-zero. Fix or remove this declaration." >&2
        exit 1
    fi
    decl_url="$(< "${DECL_URL_CAPTURE}")"
    decl_primary="$(< "${DECL_PRIMARY_CAPTURE}")"

    assert_clean_capture "UPSTREAMABLE_REPOSITORY" "${decl_url}"
    assert_clean_capture "UPSTREAMABLE_PRIMARY" "${decl_primary}"

    if [[ -z "${decl_url}" ]]; then
        echo "WARN: ${decl} — captured UPSTREAMABLE_REPOSITORY is empty; skipping" >&2
        continue
    fi

    url="${decl_url}"
    host="$(url_host "${url}")"
    path="$(url_path "${url}")"

    UPSTREAM_URLS+=("${url}")
    UPSTREAM_HOSTS+=("$(normalise_token "${host}")")
    UPSTREAM_BASES+=("$(normalise_token "$(base_name_for_host "${host}")")")
    UPSTREAM_ORGS+=("$(normalise_token "${path%%/*}")")
    if [[ "${path}" == */* ]]; then
        UPSTREAM_NSS+=("$(normalise_token "${path%/*}")")
    else
        UPSTREAM_NSS+=("")
    fi
    UPSTREAM_PATHS+=("$(normalise_token "${path}")")

    if [[ "${decl_primary}" == "1" ]]; then
        if [[ -n "${PRIMARY_URL}" && "${PRIMARY_URL}" != "${url}" ]]; then
            echo "ERROR: more than one declaration exports UPSTREAMABLE_PRIMARY=1:" >&2
            echo "         ${PRIMARY_URL}" >&2
            echo "         ${url}" >&2
            exit 1
        fi
        PRIMARY_URL="${url}"
    fi
done
shopt -u nullglob

if [[ ${#UPSTREAM_URLS[@]} -eq 0 ]]; then
    echo "ERROR: no upstreams declared in ${UPSTREAMS_DIR}" >&2
    exit 1
fi

# Reject duplicate URLs outright — the same upstream declared twice can
# never be resolved into two distinct remotes.
for i in "${!UPSTREAM_URLS[@]}"; do
    for j in "${!UPSTREAM_URLS[@]}"; do
        if [[ ${i} -lt ${j} && "${UPSTREAM_URLS[$i]}" == "${UPSTREAM_URLS[$j]}" ]]; then
            echo "ERROR: duplicate upstream URL declared twice: ${UPSTREAM_URLS[$i]}" >&2
            exit 1
        fi
    done
done

# ── Resolve names ────────────────────────────────────────────────────
# Candidate name for entry <i> at qualification level <L>. Echoes the
# empty string when the level carries no usable identity for <i>.
name_at_level() {
    local i="$1" L="$2"
    local b="${UPSTREAM_BASES[$i]}"
    case "${L}" in
        0) printf '%s' "${b}" ;;
        1) if [[ -n "${UPSTREAM_ORGS[$i]}"  ]]; then printf '%s_%s' "${b}" "${UPSTREAM_ORGS[$i]}";  fi ;;
        2) if [[ -n "${UPSTREAM_NSS[$i]}"   ]]; then printf '%s_%s' "${b}" "${UPSTREAM_NSS[$i]}";   fi ;;
        3) if [[ -n "${UPSTREAM_PATHS[$i]}" ]]; then printf '%s_%s' "${b}" "${UPSTREAM_PATHS[$i]}"; fi ;;
        4) if [[ -n "${UPSTREAM_HOSTS[$i]}" ]]; then printf '%s' "${UPSTREAM_HOSTS[$i]}"; fi ;;
        5) if [[ -n "${UPSTREAM_HOSTS[$i]}" && -n "${UPSTREAM_PATHS[$i]}" ]]; then
               printf '%s_%s' "${UPSTREAM_HOSTS[$i]}" "${UPSTREAM_PATHS[$i]}"
           fi ;;
    esac
    return 0
}

# For each entry, find the group sharing its base name and pick the
# LEAST specific level that makes every member of that group distinct.
# The chosen level is a function of the group alone, so every member
# independently computes the same level — no order dependence.
for i in "${!UPSTREAM_URLS[@]}"; do
    base="${UPSTREAM_BASES[$i]}"

    declare -a members=()
    for j in "${!UPSTREAM_BASES[@]}"; do
        if [[ "${UPSTREAM_BASES[$j]}" == "${base}" ]]; then
            members+=("${j}")
        fi
    done

    if [[ ${#members[@]} -le 1 ]]; then
        UPSTREAM_NAMES+=("${base}")
        continue
    fi

    chosen=""
    for L in 1 2 3 4 5; do
        usable=1
        for m in "${members[@]}"; do
            if [[ -z "$(name_at_level "${m}" "${L}")" ]]; then usable=0; break; fi
        done
        [[ ${usable} -eq 1 ]] || continue

        distinct=1
        for a in "${members[@]}"; do
            for b2 in "${members[@]}"; do
                if [[ ${a} -lt ${b2} ]] \
                   && [[ "$(name_at_level "${a}" "${L}")" == "$(name_at_level "${b2}" "${L}")" ]]; then
                    distinct=0; break 2
                fi
            done
        done
        if [[ ${distinct} -eq 1 ]]; then chosen="$(name_at_level "${i}" "${L}")"; break; fi
    done

    if [[ -z "${chosen}" ]]; then
        echo "ERROR: cannot derive distinct remote names for these upstreams —" >&2
        echo "       they are identical in every name-relevant component:" >&2
        for m in "${members[@]}"; do echo "         ${UPSTREAM_URLS[$m]}" >&2; done
        exit 1
    fi
    UPSTREAM_NAMES+=("${chosen}")
done

# ── Validate BEFORE mutating anything ────────────────────────────────
# git rejects invalid remote names mid-loop, which would leave the repo
# half-configured (some remotes added, origin's fan-out never rebuilt).
# Validate every name first so the script either configures everything
# or touches nothing.
for i in "${!UPSTREAM_NAMES[@]}"; do
    name="${UPSTREAM_NAMES[$i]}"
    if [[ -z "${name}" ]] || ! [[ "${name}" =~ ^[a-z0-9][a-z0-9_]*$ ]]; then
        echo "ERROR: derived an invalid remote name '${name}' for:" >&2
        echo "         ${UPSTREAM_URLS[$i]}" >&2
        echo "       Nothing has been changed. Fix the declaration's URL." >&2
        exit 1
    fi
    # 'origin' is reserved for the multi-upstream fan-out remote.
    if [[ "${name}" == "origin" ]]; then
        echo "ERROR: upstream at ${UPSTREAM_URLS[$i]} resolved to the name 'origin'," >&2
        echo "       which is reserved for the multi-upstream fan-out remote." >&2
        echo "       Nothing has been changed. Rename or qualify this upstream's host." >&2
        exit 1
    fi
done

for i in "${!UPSTREAM_NAMES[@]}"; do
    for j in "${!UPSTREAM_NAMES[@]}"; do
        if [[ ${i} -lt ${j} && "${UPSTREAM_NAMES[$i]}" == "${UPSTREAM_NAMES[$j]}" ]]; then
            echo "ERROR: remote name '${UPSTREAM_NAMES[$i]}' claimed by two upstreams:" >&2
            echo "         ${UPSTREAM_URLS[$i]}" >&2
            echo "         ${UPSTREAM_URLS[$j]}" >&2
            exit 1
        fi
    done
done

# Pick origin's fetch source by stable identity, never by position.
if [[ -z "${PRIMARY_URL}" ]]; then
    PRIMARY_URL="$(printf '%s\n' "${UPSTREAM_URLS[@]}" | LC_ALL=C sort | head -n 1)"
fi

echo "Detected ${#UPSTREAM_URLS[@]} upstreams:"
for i in "${!UPSTREAM_URLS[@]}"; do
    echo "  ${UPSTREAM_NAMES[$i]} → ${UPSTREAM_URLS[$i]}"
done
echo

# ── Warn about remotes left by an earlier naming scheme ──────────────
while read -r existing; do
    [[ -n "${existing}" ]] || continue
    [[ "${existing}" == "origin" ]] && continue
    is_ours=0
    for n in "${UPSTREAM_NAMES[@]}"; do
        [[ "${existing}" == "${n}" ]] && { is_ours=1; break; }
    done
    [[ ${is_ours} -eq 1 ]] && continue

    existing_url="$(git -C "${SCRIPT_DIR}" remote get-url "${existing}" 2>/dev/null || true)"
    for u in "${UPSTREAM_URLS[@]}"; do
        if [[ "${existing_url}" == "${u}" ]]; then
            echo "WARN: remote '${existing}' points at a declared upstream but is not a" >&2
            echo "      name this script derives. If it was created by an earlier" >&2
            echo "      version of this script it may misdirect 'git push ${existing}'." >&2
            echo "      URL: ${existing_url}" >&2
            echo "      Remove it when you have confirmed nothing depends on it:" >&2
            echo "          git remote remove ${existing}" >&2
            break
        fi
    done
done < <(git -C "${SCRIPT_DIR}" remote 2>/dev/null)

# ── Pre-flight: is the git config writable? ──────────────────────────
# If the config is NOT writable (read-only checkout, CI container layer),
# we still run the read-only verify pass against our intent. A repo whose
# state already matches intent needs no mutation — refusing a correct
# read-only repo would be a §11.4.201 false-positive refusal.
if git -C "${SCRIPT_DIR}" config --local upstreams.installprobe ok >/dev/null 2>&1; then
    git -C "${SCRIPT_DIR}" config --local --unset upstreams.installprobe >/dev/null 2>&1 || true
    CONFIG_WRITABLE=1
else
    echo "WARN: cannot write to this repository's git config." >&2
    echo "       A concurrent git process may hold .git/config.lock, or" >&2
    echo "       the checkout may be read-only. Checking if already configured..." >&2
    CONFIG_WRITABLE=0
fi

# ── Mutate (only when writable) ──────────────────────────────────────
if [[ ${CONFIG_WRITABLE} -eq 1 ]]; then
    for i in "${!UPSTREAM_URLS[@]}"; do
        name="${UPSTREAM_NAMES[$i]}"
        url="${UPSTREAM_URLS[$i]}"
        if git -C "${SCRIPT_DIR}" remote get-url "${name}" >/dev/null 2>&1; then
            git_must remote set-url "${name}" "${url}"
            echo "Updated remote: ${name}"
        else
            git_must remote add "${name}" "${url}"
            echo "Added remote: ${name}"
        fi
    done

    if ! git -C "${SCRIPT_DIR}" remote get-url origin >/dev/null 2>&1; then
        git_must remote add origin "${PRIMARY_URL}"
        echo "Added remote: origin (fetch from ${PRIMARY_URL})"
    else
        git_must remote set-url origin "${PRIMARY_URL}"
    fi

    # Clear any existing push URLs on origin, then add one per upstream.
    git -C "${SCRIPT_DIR}" remote set-url --delete --push origin '.*' 2>/dev/null || true
    for url in "${UPSTREAM_URLS[@]}"; do
        git_must remote set-url --add --push origin "${url}"
    done
fi

# ── Verify-after-write (§11.4.200) ───────────────────────────────────
# Reads back the repo's real state and compares against intent. This is
# the single gate for the success banner, shared by both the mutate and
# the verify-only (read-only) paths.
verify_failed=0
for i in "${!UPSTREAM_URLS[@]}"; do
    name="${UPSTREAM_NAMES[$i]}"
    want="${UPSTREAM_URLS[$i]}"
    got="$(git -C "${SCRIPT_DIR}" remote get-url "${name}" 2>/dev/null || true)"
    if [[ "${got}" != "${want}" ]]; then
        echo "ERROR: verification failed for remote '${name}'" >&2
        echo "         expected: ${want}" >&2
        echo "         actual:   ${got:-<remote absent>}" >&2
        verify_failed=1
    fi
done

got_fetch="$(git -C "${SCRIPT_DIR}" remote get-url origin 2>/dev/null || true)"
if [[ "${got_fetch}" != "${PRIMARY_URL}" ]]; then
    echo "ERROR: verification failed for origin's fetch URL" >&2
    echo "         expected: ${PRIMARY_URL}" >&2
    echo "         actual:   ${got_fetch:-<absent>}" >&2
    verify_failed=1
fi

push_count="$(git -C "${SCRIPT_DIR}" remote get-url --push --all origin 2>/dev/null | grep -c . || true)"
if [[ "$(( push_count ))" -ne "${#UPSTREAM_URLS[@]}" ]]; then
    echo "ERROR: origin fans out to ${push_count} push URL(s), expected ${#UPSTREAM_URLS[@]}" >&2
    echo "       A single push would NOT reach every upstream (§2.1)." >&2
    verify_failed=1
fi

if [[ ${verify_failed} -ne 0 ]]; then
    if [[ ${CONFIG_WRITABLE} -eq 0 ]]; then
        echo "ERROR: repository is NOT correctly configured and cannot be written to." >&2
        echo "       Make the checkout writable and re-run." >&2
    else
        echo "ERROR: the repository is NOT correctly configured — see above." >&2
    fi
    exit 1
fi

if [[ ${CONFIG_WRITABLE} -eq 0 ]]; then
    echo "✓ Repository is already correctly configured — nothing changed."
fi

echo
echo "✓ origin fetch URL:"
git -C "${SCRIPT_DIR}" remote get-url origin | sed 's/^/    /'
echo "✓ origin push URLs:"
git -C "${SCRIPT_DIR}" remote get-url --push --all origin | sed 's/^/    /'

echo
echo "Done — configuration verified by read-back. Confirm with:  git remote -v"
exit 0
