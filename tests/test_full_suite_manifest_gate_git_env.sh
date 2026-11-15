#!/usr/bin/env bash
# test_full_suite_manifest_gate_git_env.sh — proves CM-FULL-SUITE-MANIFEST-COMPLETE and its paired mutation
# test write into no repository named by the caller's git environment (review finding F8, 2026-11-13).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# A git hook hands its children repository-locating variables: a pre-commit hook receives GIT_INDEX_FILE
# (absolute `<repo>/.git/index.lock` on `git commit -a`), and GIT_DIR / GIT_WORK_TREE are common in wrappers.
# Round 1 of the gate ran `git init` / `git add` for its control needle with that environment, so the needle's
# two entries replaced the index of the inspected repository (GIT_INDEX_FILE) or of another repository
# (GIT_DIR), and the mutation test committed a `fixture` commit onto another repository's branch. This test
# builds a SENTINEL repository (a valid, clean fixture with its own hooks directory whose hooks write a marker
# into it) and runs, with the caller's variables aimed at it:
#   E1 the gate on a GREEN fixture with GIT_INDEX_FILE = the fixture's own index (finding F8 case A),
#   E2 the gate on a GREEN fixture with GIT_DIR = the sentinel's git dir (case B),
#   E3 the gate on a RED fixture (a committed census file without a row) with every variable at once
#      (GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY, GIT_COMMON_DIR, GIT_NAMESPACE,
#      GIT_CEILING_DIRECTORIES, GIT_CONFIG_COUNT/KEY_0/VALUE_0 = core.hooksPath -> the sentinel's hooks,
#      GIT_CONFIG_PARAMETERS, GIT_CONFIG_GLOBAL, GIT_TEMPLATE_DIR, GIT_GLOB_PATHSPECS); it MUST still FAIL
#      on the fixture, never PASS on the clean sentinel,
#   E4 the paired mutation test with every variable at once; it MUST still end MUTATION PAIR VALID,
# and asserts after each that the sentinel and the inspected fixture are unchanged: paths, types, sizes,
# mtimes, modes and inodes of every file and directory, and the sha256 of every file, .git included.
# It also checks that the gate and the mutation test clear the same variable list and that the list holds
# all 29 REQUIRED names below, and holds neither discovery limit (FORBIDDEN below) (the source of each is recorded next to the list).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   bash tests/test_full_suite_manifest_gate_git_env.sh [--gate <path>] [--mutation-test <path>]
#   (the options run the cases against other copies, used to show the test is RED on the round-1 gate)
#   Exit: 0 all cases hold · 1 a case failed · 2 setup error.
#
# ── Side-effects ──────────────────────────────────────────────────────────
#   A trap-cleaned temp dir; the real repository is only read. Every git call this test makes itself runs
#   with the caller's git variables cleared and with no global or system configuration.
#
# ── Dependencies ──────────────────────────────────────────────────────────
#   bash, git, python3, find, sort, sha256sum, grep, sed, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C
# REQUIRED: the 29 names the gate and its mutation test must clear, with where each comes from (git 2.53.0).
#   repo    `git help git`, section "The Git Repository" (10 of its 12 names: the discovery limits
#           GIT_CEILING_DIRECTORIES and GIT_DISCOVERY_ACROSS_FILESYSTEM stay the caller's, FORBIDDEN)
#   config  config sources: `git help git` (GIT_CONFIG_GLOBAL, _SYSTEM, _NOSYSTEM, _COUNT) and the
#           legacy or internal GIT_CONFIG, GIT_CONFIG_PARAMETERS (`git help config`)
#   spec    the global pathspec magic of `git help git` (4 names)
#   other   real git variables that `git help git` does not list: GIT_PREFIX, GIT_SHALLOW_FILE,
#           GIT_GRAFT_FILE, GIT_QUARANTINE_PATH, GIT_INTERNAL_SUPER_PREFIX, GIT_REPLACE_REF_BASE (git
#           internals and `git help replace`), GIT_NO_REPLACE_OBJECTS, GIT_ATTR_SOURCE, GIT_TEMPLATE_DIR
#           (`git help init`), GIT_DEFAULT_REF_FORMAT
# (review round 2, N3: round 1 asserted 22 of them, so 9 could be dropped from both lists unnoticed.)
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
REQUIRED=(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_INDEX_VERSION GIT_OBJECT_DIRECTORY
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
    GIT_DEFAULT_HASH GIT_DEFAULT_REF_FORMAT GIT_PREFIX
    GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX
    GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_ATTR_SOURCE GIT_TEMPLATE_DIR
    GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GIT_CONFIG_PARAMETERS
    GIT_CONFIG_COUNT GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS
    GIT_ICASE_PATHSPECS)
for _v in "${REQUIRED[@]}"; do unset "$_v"; done
unset _v

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/gates/cm_full_suite_manifest_complete.sh"
MUT="$ROOT/scripts/gates/cm_full_suite_manifest_complete_mutation_test.sh"
while [ $# -gt 0 ]; do
    case "$1" in
        --gate) [ $# -ge 2 ] || { echo "usage: --gate <path>" >&2; exit 2; }; GATE="$2"; shift 2 ;;
        --mutation-test) [ $# -ge 2 ] || { echo "usage: --mutation-test <path>" >&2; exit 2; }; MUT="$2"; shift 2 ;;
        *) echo "usage: ${0##*/} [--gate <path>] [--mutation-test <path>]" >&2; exit 2 ;;
    esac
done
for _f in "$GATE" "$MUT" "$ROOT/scripts/run_full_suite.sh" "$ROOT/scripts/full_suite/run_full_suite.py" \
          "$ROOT/scripts/lib/safe_rm.sh" "$ROOT/scripts/lib/protected_paths.list"; do
    [ -f "$_f" ] || { echo "[git-env] setup: missing $_f" >&2; exit 2; }
done

T="$(mktemp -d)" || { echo "[git-env] setup: mktemp failed" >&2; exit 2; }
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() { [ -n "${T:-}" ] && [ -d "${T:?}" ] && rm -rf -- "${T:?}"; }
trap cleanup EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
ko() { fail=$((fail + 1)); echo "FAIL $1"; }
setup_bug() { echo "[git-env] setup: $1" >&2; exit 2; }
gitc() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git --literal-pathspecs -C "$1" -c user.email=a@b -c user.name=t -c core.hooksPath="$T/nohooks" "${@:2}"; }
runner() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null TMPDIR="$T/rt" bash "$1/scripts/run_full_suite.sh" --root "$1" "${@:2}"; }
mkdir -p "$T/nohooks" "$T/rt" || setup_bug "mkdir"

# ---- the scrub lists ---------------------------------------------------------------------------
# list_of <file>: the words of the `_git_scrub=( ... )` array, sorted.
list_of() {
    python3 -I -c 'import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^_git_scrub=\(([^)]*)\)", s, re.M)
print("\n".join(sorted(m.group(1).split())) if m else "")' "$1"
}
lg="$(list_of "$GATE")"; lm="$(list_of "$MUT")"
if [ -z "$lg" ]; then ko "L1: the gate has no _git_scrub list"
elif [ "$lg" != "$lm" ]; then ko "L1: the gate and the mutation test clear different lists: $(diff <(printf '%s\n' "$lg") <(printf '%s\n' "$lm") | tr '\n' ' ')"
else ok "L1: the gate and the mutation test clear the same $(printf '%s\n' "$lg" | wc -l) variables"
fi
missing=""
[ "${#REQUIRED[@]}" = 29 ] || setup_bug "REQUIRED holds ${#REQUIRED[@]} names, want 29"
# FORBIDDEN: discovery limits; a scrub that clears them widens discovery past a caller's fence.
FORBIDDEN=(GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM)
for v in "${REQUIRED[@]}"; do
    printf '%s\n' "$lg" | grep -qxF "$v" || missing="$missing $v"
done
# control needle (§11.4.273): the same instrument must find a name that is certainly in the list
# and must not find a fabricated one, else an empty `missing` proves nothing.
printf '%s\n' "$lg" | grep -qxF GIT_DIR || setup_bug "L2 needle: GIT_DIR not found in the gate's list"
! printf '%s\n' "$lg" | grep -qxF GIT_NOPE_ZZZ || setup_bug "L2 needle: a fabricated name was found"
if [ -z "$missing" ]; then ok "L2: the gate's list holds all ${#REQUIRED[@]} required names"
else ko "L2: the gate's list lacks:$missing"
fi
extra=""
for v in "${FORBIDDEN[@]}"; do
    printf '%s\n' "$lg" "$lm" | grep -qxF "$v" && extra="$extra $v"
done
if [ -z "$extra" ]; then ok "L3: neither list clears a discovery limit (${FORBIDDEN[*]})"
else ko "L3: a list clears the discovery limit(s):$extra (they stay the caller's)"
fi

# ---- fixtures ----------------------------------------------------------------------------------
mkfix() { # <dir>: real runner, two tests, generated manifest and guide, committed
    local d="${1:?}"
    mkdir -p "$d/scripts/full_suite" "$d/scripts/lib" "$d/tests/a" "$d/docs/guides" || setup_bug "mkdir $d"
    { cp "$ROOT/scripts/run_full_suite.sh" "$d/scripts/" && cp "$ROOT/scripts/full_suite/run_full_suite.py" "$d/scripts/full_suite/" \
        && cp "$ROOT/scripts/lib/safe_rm.sh" "$ROOT/scripts/lib/protected_paths.list" "$d/scripts/lib/"; } || setup_bug "copy runner into $d"
    printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' >"$d/tests/a/test_one.sh"
    printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' >"$d/tests/a/test_two.sh"
    printf '# guide\n\n<!-- census:begin -->\nx\n<!-- census:end -->\n' >"$d/docs/guides/full_suite_runner_guide.md"
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q --template= "$d" || setup_bug "git init $d"
    gitc "$d" add -A || setup_bug "add $d"
    runner "$d" --generate-manifest --write >/dev/null 2>&1 || setup_bug "generate in $d"
    runner "$d" --sync-guide >/dev/null 2>&1 || setup_bug "sync-guide in $d"
    { gitc "$d" add -A && gitc "$d" commit -q -m fixture; } || setup_bug "commit $d"
}
fingerprint() { # <dir>: every path's type, size, mtime, mode, inode, and every file's sha256
    (cd "$1" && { find . -printf '%p\t%y\t%s\t%T@\t%m\t%i\n' | sort; find . -type f -exec sha256sum {} + | sort -k 2; } | sha256sum)
}
SEN="$T/sentinel"; mkfix "$SEN"
mkdir -p "$SEN/.hooks" "$SEN/.tmpl/hooks" || setup_bug "mkdir hooks"
for h in pre-commit post-commit post-checkout post-index-change reference-transaction; do
    printf '#!/bin/sh\necho "%s ran" >>"%s/HOOK_RAN"\nexit 0\n' "$h" "$SEN" >"$SEN/.hooks/$h"
    cp "$SEN/.hooks/$h" "$SEN/.tmpl/hooks/$h"
    chmod +x "$SEN/.hooks/$h" "$SEN/.tmpl/hooks/$h"
done
# a global config and a template directory that would install the sentinel's hooks if they were honoured
printf '[core]\n\thooksPath = %s/.hooks\n[init]\n\ttemplateDir = %s/.tmpl\n' "$SEN" "$SEN" >"$SEN/.gitconfig_global"
GREEN="$T/green"; mkfix "$GREEN"
RED="$T/red"; mkfix "$RED"
printf '#!/usr/bin/env bash\necho ok\n' >"$RED/tests/a/test_registry_login.sh"
{ gitc "$RED" add -A && gitc "$RED" commit -q -m red; } || setup_bug "commit red"

ALL=(GIT_DIR="$SEN/.git" GIT_WORK_TREE="$SEN" GIT_INDEX_FILE="$SEN/.git/index" GIT_OBJECT_DIRECTORY="$SEN/.git/objects"
     GIT_COMMON_DIR="$SEN/.git" GIT_NAMESPACE=sentinel GIT_CEILING_DIRECTORIES="$T"
     GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$SEN/.hooks"
     GIT_CONFIG_PARAMETERS="'core.hookspath'='$SEN/.hooks'" GIT_CONFIG_GLOBAL="$SEN/.gitconfig_global"
     GIT_TEMPLATE_DIR="$SEN/.tmpl" GIT_GLOB_PATHSPECS=1)

check_unchanged() { # <label> <dir> <fingerprint-before>
    if [ "$(fingerprint "$2")" = "$3" ] && [ ! -e "$2/HOOK_RAN" ]; then ok "$1"; else ko "$1 (the directory changed or a hook ran)"; fi
}
run_gate() { # <label> <root> <want-rc> <want-string> <env...>
    local label="$1" root="$2" want="$3" str="$4"; shift 4
    local f0 g0 rc=0
    f0="$(fingerprint "$SEN")"; g0="$(fingerprint "$root")"
    env "$@" bash "$GATE" --root "$root" >"$T/$label.log" 2>&1 || rc=$?
    if [ "$rc" = "$want" ] && grep -qF -- "$str" "$T/$label.log"; then ok "$label: gate exit $rc, '$str'"
    else ko "$label: gate exit $rc (want $want and '$str'): $(tail -n 2 "$T/$label.log" | tr '\n' ' ')"
    fi
    check_unchanged "$label: the sentinel is unchanged" "$SEN" "$f0"
    check_unchanged "$label: the inspected fixture is unchanged" "$root" "$g0"
}

run_gate E1 "$GREEN" 0 "PASS" GIT_INDEX_FILE="$GREEN/.git/index"
run_gate E2 "$GREEN" 0 "PASS" GIT_DIR="$SEN/.git"
run_gate E3 "$RED" 1 "census file without manifest row: tests/a/test_registry_login.sh" "${ALL[@]}"

f0="$(fingerprint "$SEN")"; rc=0
env "${ALL[@]}" bash "$MUT" --quiet --gate "$GATE" >"$T/E4.log" 2>&1 || rc=$?
if [ "$rc" = 0 ] && grep -qxF "MUTATION PAIR VALID" "$T/E4.log"; then ok "E4: the paired mutation test stays valid under every variable"
else ko "E4: the paired mutation test exit $rc under every variable: $(tail -n 3 "$T/E4.log" | tr '\n' ' ')"
fi
check_unchanged "E4: the sentinel is unchanged after the paired mutation test" "$SEN" "$f0"

echo "[git-env] passed=$pass failed=$fail"
[ "$fail" = 0 ] && exit 0
exit 1
