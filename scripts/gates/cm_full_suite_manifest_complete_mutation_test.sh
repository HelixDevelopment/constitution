#!/usr/bin/env bash
# cm_full_suite_manifest_complete_mutation_test.sh — paired §1.1 mutation test for CM-FULL-SUITE-MANIFEST-COMPLETE
#
# Purpose
#   Proves cm_full_suite_manifest_complete.sh discriminates instead of passing whatever it is shown.
#   Every case builds a throwaway git repository that uses the REAL runner of this constitution
#   (scripts/run_full_suite.sh, copied with its engine scripts/full_suite/run_full_suite.py and
#   scripts/lib/safe_rm.sh + protected_paths.list, which the engine uses to remove its own temp
#   dirs), writes its manifest with the runner's own --generate-manifest --write, commits it, and
#   runs the gate on it. The gate judges HEAD, so every RED mutation is COMMITTED:
#     * GREEN control     the generated, committed fixture MUST pass (exit 0) and stay unchanged
#                         (paths, sizes, mtimes, modes and inodes of the whole fixture, .git included);
#                         RO2 a tracked file that is only stat-dirty MUST pass with no NOTE and its
#                         index MUST NOT be rewritten (a `git diff` refresh would rewrite it); RO3 an
#                         unreadable index MUST still pass, with a NOTE that the state is unknown;
#     * golden-FALSE      MUST pass: G1 a committed non-census file; W1..W6 working-tree-only or
#                         index-only changes HEAD does not carry (an untracked census file, an
#                         untracked file named `test_[o]ne.sh` next to a committed test_one.sh, an
#                         untracked dangling test symlink, a test deleted only on disk, a staged
#                         rename, a guide edited only on disk); they MUST also print the NOTE that
#                         the work tree was not judged (§11.4.201(1));
#     * RED mutations     ONE at a time, each MUST exit 1 and name the problem:
#                         M1 a committed census file with no row (the bd0036bd incident shape),
#                         M2 a row deleted, M3 a stale row, M4 a stale guide census block,
#                         M5 three census files with no rows (all named, the count right),
#                         M6 an excluded row without an accepted lock, M7 a row whose file was
#                         `git rm --cached` and committed while the file stays on disk (P07a),
#                         W7 a committed defect with an uncommitted runner that answers OK (HEAD's
#                         runner is the one used: FAIL + NOTE),
#                         D1 a duplicated row, D2 a row with six columns, D3 HEAD without a
#                         manifest, D4 a manifest line with a vertical tab, D5 an excluded lock
#                         with a vertical tab (D1, D2, D4, D5 relay the runner's own refusal);
#     * BLIND             MUST exit 2, never 0: B1 HEAD has a manifest but no runner; B2 a stub
#                         runner that answers MANIFEST-OK to anything; N1..N7 a runner that misses
#                         one member of the control needle (exit code, each of the four problem
#                         lines, the result line, the duplicated row, a failed generate);
#                         R1..R6 a runner whose answer on HEAD is not trustworthy (exit 0 without
#                         the OK line, a census total of 0, exit 5, exit 3 without a result line, a
#                         `census instrument blind` refusal, a malformed `manifest line` refusal,
#                         R7 a MANIFEST-MISMATCH with no problem line and no readable reason);
#                         X1 --root is a subdirectory that holds a runner, X2 an unborn HEAD,
#                         X3 not a git repository, X4 no git on PATH (each with a runner on disk;
#                         with neither file on disk any of them is SKIP, nothing inspected);
#     * SKIP              MUST exit 3: an empty git repository, a plain empty directory, and a
#                         commit that carries neither file (even with both on disk, untracked);
#     * usage             --root without a value and an unknown argument exit 64, --help exits 0;
#     * no leak           no gate run leaves anything in its TMPDIR.
#   Each mutation asserts it really changed what it claims to change (HEAD, or only the work tree);
#   a no-op mutation is a test bug (exit 2). `--gate <path>` runs the cases against another gate
#   file (used to show the test is RED against a gate that always passes, and against mutants).
#
# Usage
#   cm_full_suite_manifest_complete_mutation_test.sh [--quiet] [--gate <path>]
#
# Exit codes
#   0  every control and every mutation behaved as required
#   1  at least one mutation survived, or a control case did not hold
#   2  setup failure (missing input, no-op mutation)
#
# Side effects: a trap-cleaned temp dir; the real repository is only read. Like the gate, it first
#   clears the caller's repository-locating git variables, and every fixture repository is created
#   and committed with no global or system git configuration and an empty hooks directory, so an
#   ambient GIT_DIR / GIT_INDEX_FILE (a pre-commit hook passes both) cannot send a fixture commit
#   into another repository.
# Dependencies: bash, git, python3, grep, sed, cp, find, sha256sum, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

# The same list as the gate (tests/test_full_suite_manifest_gate_git_env.sh checks they are equal).
_git_scrub=(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_INDEX_VERSION GIT_OBJECT_DIRECTORY
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
    GIT_DEFAULT_HASH GIT_DEFAULT_REF_FORMAT GIT_PREFIX
    GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX
    GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_ATTR_SOURCE GIT_TEMPLATE_DIR
    GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GIT_CONFIG_PARAMETERS
    GIT_CONFIG_COUNT GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS
    GIT_ICASE_PATHSPECS)
for _v in "${_git_scrub[@]}"; do unset "$_v"; done
unset _v

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GATE="$HERE/cm_full_suite_manifest_complete.sh"
QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=1; shift ;;
        --gate) [ $# -ge 2 ] || { echo "usage: --gate <path>" >&2; exit 2; }; GATE="$2"; shift 2 ;;
        *) echo "usage: ${0##*/} [--quiet] [--gate <path>]" >&2; exit 2 ;;
    esac
done
for _t in git python3 grep sed cp find sha256sum mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[mutation:manifest-complete] setup: required tool '$_t' missing" >&2; exit 2; }
done
for _f in "$GATE" "$ROOT/scripts/run_full_suite.sh" "$ROOT/scripts/full_suite/run_full_suite.py" \
          "$ROOT/scripts/lib/safe_rm.sh" "$ROOT/scripts/lib/protected_paths.list"; do
    [ -f "$_f" ] || { echo "[mutation:manifest-complete] setup: missing $_f" >&2; exit 2; }
done

T="$(mktemp -d)" || { echo "[mutation:manifest-complete] setup: mktemp failed" >&2; exit 2; }
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() { [ -n "${T:-}" ] && [ -d "${T:?}" ] && rm -rf -- "${T:?}"; }
trap cleanup EXIT
GT="$T/gate_tmp"; RT="$T/runner_tmp"; NOHOOKS="$T/nohooks"
mkdir -p "$GT" "$RT" "$NOHOOKS" || { echo "[mutation:manifest-complete] setup: mkdir failed" >&2; exit 2; }

pass=0; fail=0; runs=0; leak=""
ok() { pass=$((pass + 1)); [ "$QUIET" = 1 ] || echo "ok   $1"; }
ko() { fail=$((fail + 1)); echo "FAIL $1"; }
setup_bug() { echo "[mutation:manifest-complete] setup: $1" >&2; exit 2; }
# gitc <dir> ...: git on a fixture repository, no global/system config, no hooks, literal pathspecs.
gitc() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git --literal-pathspecs -C "$1" -c user.email=a@b -c user.name=t -c core.hooksPath="$NOHOOKS" "${@:2}"; }
ginit() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q --template= "$1"; }
runner() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null TMPDIR="$RT" bash "$1/scripts/run_full_suite.sh" --root "$1" "${@:2}"; }
commit() { gitc "$1" add -A && gitc "$1" commit -q -m "$2"; }

# mkfix <dir>: a git repo with the real runner, two test files, a guide with a census block, and a
# manifest + guide generated by the runner itself; everything committed.
mkfix() {
    local d="${1:?}"
    mkdir -p "$d/scripts/full_suite" "$d/scripts/lib" "$d/tests/a" "$d/docs/guides" "$d/config" || setup_bug "mkdir $d"
    cp "$ROOT/scripts/run_full_suite.sh" "$d/scripts/run_full_suite.sh" || setup_bug "copy runner"
    cp "$ROOT/scripts/full_suite/run_full_suite.py" "$d/scripts/full_suite/run_full_suite.py" || setup_bug "copy engine"
    cp "$ROOT/scripts/lib/safe_rm.sh" "$ROOT/scripts/lib/protected_paths.list" "$d/scripts/lib/" || setup_bug "copy safe_rm"
    printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' >"$d/tests/a/test_one.sh"
    printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' >"$d/tests/a/test_two.sh"
    printf '# guide\n\n<!-- census:begin -->\nx\n<!-- census:end -->\n' >"$d/docs/guides/full_suite_runner_guide.md"
    ginit "$d" || setup_bug "git init $d"
    gitc "$d" add -A || setup_bug "git add $d"
    runner "$d" --generate-manifest --write >"$d.gen.log" 2>&1 || setup_bug "generate in $d: $(tail -n 3 "$d.gen.log")"
    runner "$d" --sync-guide >"$d.sync.log" 2>&1 || setup_bug "sync-guide in $d: $(tail -n 3 "$d.sync.log")"
    runner "$d" --verify-manifest >"$d.verify.log" 2>&1 || setup_bug "the fresh fixture does not verify: $(tail -n 3 "$d.verify.log")"
    commit "$d" fixture || setup_bug "commit $d"
}
# gate <root> <log>: run the gate under test; sets RC; any file left in its TMPDIR is a leak.
gate() {
    RC=0; runs=$((runs + 1))
    TMPDIR="$GT" bash "$GATE" --root "$1" >"$2" 2>&1 || RC=$?
    if [ -z "$leak" ] && [ -n "$(find "$GT" -mindepth 1 -maxdepth 1 -print -quit)" ]; then leak="$2"; fi
}
expect() { # <label> <want-rc> <log> [<fixed-string that must appear>]... ; a string starting with '!' must NOT appear
    local label="$1" want="$2" log="$3"; shift 3
    if [ "$RC" != "$want" ]; then ko "$label: exit $RC, want $want — $(tail -n 2 "$log" | tr '\n' ' ')"; return; fi
    local s
    for s in "$@"; do
        case "$s" in
            '!'*) if grep -qF -- "${s#!}" "$log"; then ko "$label: output has '${s#!}'"; return; fi ;;
            *) grep -qF -- "$s" "$log" || { ko "$label: output lacks '$s'"; return; } ;;
        esac
    done
    ok "$label (exit $RC)"
}
tree_of() { gitc "$1" rev-parse 'HEAD^{tree}' 2>/dev/null; }
committed_changed() { # <fixture>: HEAD must carry the mutation
    [ "$(tree_of "$1")" != "$(tree_of "$BASE")" ] || setup_bug "no-op committed mutation in $1"
}
wt_changed() { # <fixture>: the work tree or index changed, HEAD did not
    [ "$(tree_of "$1")" = "$(tree_of "$BASE")" ] || setup_bug "work-tree mutation in $1 changed HEAD"
    if diff -rq -x .git "$1" "$BASE" >/dev/null 2>&1 && [ "$(gitc "$1" ls-files -s)" = "$(gitc "$BASE" ls-files -s)" ]; then
        setup_bug "no-op work-tree mutation in $1"
    fi
}
fingerprint() { (cd "$1" && find . -printf '%p\t%y\t%s\t%T@\t%m\t%i\n' | sort | sha256sum); }

BASE="$T/base"; mkfix "$BASE"
clone() { # <name>: a fresh copy of the base fixture; prints its path
    local name="${1:?}" dst
    dst="${T:?}/$name"
    [ -e "$dst" ] && setup_bug "fixture $name exists"
    cp -a "$BASE" "$dst" || setup_bug "copy fixture $name"
    printf '%s' "$dst"
}
edit_manifest() { # <fixture> replace <old> <new> | append <text>: rewrite config/full_suite_manifest.tsv
    python3 -I -c 'import sys
p, op, a = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
if op == "replace" and len(sys.argv) == 5 and a in s:
    s2 = s.replace(a, sys.argv[4], 1)
elif op == "append" and len(sys.argv) == 4:
    s2 = s + a
else:
    sys.exit(3)
if s2 == s:
    sys.exit(3)
open(p, "w", encoding="utf-8").write(s2)' "$1/config/full_suite_manifest.tsv" "${@:2}" || setup_bug "manifest edit in $1"
}
ROW_ONE=$'tests/a/test_one.sh\tsh\tentry\tdefault\tbash\t-\tauto\n'
ROW_TWO=$'tests/a/test_two.sh\tsh\tentry\tdefault\tbash\t-\tauto\n'
# mkstub <fixture> <mode> [<arg>] : replace the runner by a shim that answers some calls itself
# and runs the real engine for the others; modes are listed in the shim. Committed.
mkstub() {
    local d="$1"
    cat >"$d/scripts/run_full_suite.sh" <<'SHIM'
#!/usr/bin/env bash
# test shim of cm_full_suite_manifest_complete_mutation_test.sh: answers some calls itself
# (mode in stub_mode), runs the real engine for the others.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
mode=$(cat "$HERE/stub_mode") || exit 2
root=""; prev=""; verify=0
for a in "$@"; do
    [ "$prev" = --root ] && root="$a"
    [ "$a" = --verify-manifest ] && verify=1
    prev="$a"
done
case "$root" in */needle) kind=needle ;; */needle_dup) kind=dup ;; *) kind=real ;; esac
engine() { python3 -I -B "$HERE/full_suite/run_full_suite.py" "$@"; }
case "$mode:$kind:$verify" in
    always_ok:*:1) echo "census: sh/entry=2 total=2"; echo "RESULT: MANIFEST-OK"; exit 0 ;;
    needle_rc0:needle:1) engine "$@" 2>&1; exit 0 ;;
    needle_drop:needle:1)
        out=$(engine "$@" 2>&1); rc=$?
        pat=$(cat "$HERE/stub_arg") || exit 2
        printf '%s\n' "$out" | grep -vF -- "$pat"; exit "$rc" ;;
    dup_ok:dup:1) echo "census: sh/entry=2 total=2"; echo "RESULT: MANIFEST-OK"; exit 0 ;;
    gen_fail:needle:0) echo "boom" >&2; exit 1 ;;
    canned:real:1) cat "$HERE/stub_arg"; exit "$(cat "$HERE/stub_rc")" ;;
esac
exec python3 -I -B "$HERE/full_suite/run_full_suite.py" "$@"
SHIM
    printf '%s\n' "$2" >"$d/scripts/stub_mode"
    [ $# -ge 3 ] && printf '%s\n' "$3" >"$d/scripts/stub_arg"
    [ $# -ge 4 ] && printf '%s\n' "$4" >"$d/scripts/stub_rc"
    commit "$d" "stub $2" || setup_bug "commit stub $2"
}

# ---- GREEN control + read-only -----------------------------------------------------------------
fp0="$(fingerprint "$BASE")"
gate "$BASE" "$T/green.log"; expect "GREEN control: generated, committed manifest passes" 0 "$T/green.log" \
    "CM-FULL-SUITE-MANIFEST-COMPLETE: PASS" "control needle seen" "!NOTE"
if [ "$(fingerprint "$BASE")" = "$fp0" ]; then ok "read-only: the inspected fixture is unchanged (paths, sizes, mtimes, modes, inodes)"
else ko "read-only: the gate changed the inspected fixture"; fi
# RO2: a tracked file whose stat data no longer matches the index (content unchanged). A porcelain
# `git diff` refreshes, i.e. REWRITES, the index of such a repository even with
# --no-optional-locks (measured, git 2.53.0); the gate must not.
F="$(clone ro2)"; touch -d '@2000000000' "$F/tests/a/test_one.sh"
if gitc "$F" diff-files --quiet; then setup_bug "ro2: the touched file must be stat-dirty"; fi
ix0="$(cd "$F/.git" && sha256sum index && stat -c '%Y %i' index)"
gate "$F" "$T/ro2.log"; expect "RO2: a stat-dirty tracked file with unchanged content PASSes without a NOTE" 0 "$T/ro2.log" "PASS" "!NOTE"
if [ "$(cd "$F/.git" && sha256sum index && stat -c '%Y %i' index)" = "$ix0" ]; then ok "RO2: the gate did not refresh (rewrite) the inspected repository's index"
else ko "RO2: the gate rewrote the inspected repository's index (an index refresh by git diff)"; fi
# RO3: an index git cannot read; HEAD is still judged and the NOTE says the state is unknown.
F="$(clone ro3)"; printf 'not an index\n' >"$F/.git/index"
if gitc "$F" ls-files -s >/dev/null 2>&1; then setup_bug "ro3: the index must be unreadable"; fi
gate "$F" "$T/ro3.log"; expect "RO3: an unreadable index still judges HEAD; the NOTE says unknown" 0 "$T/ro3.log" \
    "PASS" "staged: unknown, unstaged: unknown, untracked: unknown"

# ---- golden-FALSE ------------------------------------------------------------------------------
F="$(clone g1)"; printf 'notes\n' >"$F/scripts/helper_notes.md"; commit "$F" notes; committed_changed "$F"
gate "$F" "$T/g1.log"; expect "G1: a committed non-census file does not trip the gate" 0 "$T/g1.log" "PASS"

F="$(clone w1)"; printf '#!/usr/bin/env bash\necho ok\n' >"$F/tests/a/test_untracked.sh"; wt_changed "$F"
gate "$F" "$T/w1.log"; expect "W1: an untracked census file is not judged (PASS + NOTE)" 0 "$T/w1.log" "PASS" "staged: no, unstaged: no, untracked: yes" "were NOT judged"

F="$(clone w2)"; printf '#!/usr/bin/env bash\necho x\n' >"$F/tests/a/test_[o]ne.sh"; wt_changed "$F"
gate "$F" "$T/w2.log"; expect "W2: an untracked test_[o]ne.sh next to test_one.sh is not judged (P04)" 0 "$T/w2.log" "PASS" "staged: no, unstaged: no, untracked: yes" "were NOT judged"

F="$(clone w3)"; ln -s nowhere "$F/tests/a/test_dang.sh"; wt_changed "$F"
gate "$F" "$T/w3.log"; expect "W3: an untracked dangling test symlink is not judged (P05)" 0 "$T/w3.log" "PASS" "staged: no, unstaged: no, untracked: yes" "were NOT judged"

F="$(clone w4)"; python3 -I -c 'import os,sys; os.remove(sys.argv[1])' "$F/tests/a/test_two.sh"; wt_changed "$F"
gate "$F" "$T/w4.log"; expect "W4: a test deleted only on disk is not judged (P06)" 0 "$T/w4.log" "PASS" "staged: no, unstaged: yes, untracked: no"

F="$(clone w5)"; gitc "$F" mv tests/a/test_two.sh tests/a/test_deux.sh; wt_changed "$F"
gate "$F" "$T/w5.log"; expect "W5: a staged, uncommitted rename is not judged (P14)" 0 "$T/w5.log" "PASS" "staged: yes, unstaged: no, untracked: no"

F="$(clone w6)"; sed -i 's/ total=2$/ total=9/' "$F/docs/guides/full_suite_runner_guide.md"; wt_changed "$F"
gate "$F" "$T/w6.log"; expect "W6: a guide edited only on disk is not judged (P26)" 0 "$T/w6.log" "PASS" "staged: no, unstaged: yes, untracked: no"

# ---- RED mutations (committed) -----------------------------------------------------------------
F="$(clone m1)"; printf '#!/usr/bin/env bash\necho ok\n' >"$F/tests/a/test_registry_login.sh"; commit "$F" m1; committed_changed "$F"
gate "$F" "$T/m1.log"; expect "M1: a committed census file without a row FAILs" 1 "$T/m1.log" \
    "FAIL — census file without manifest row: tests/a/test_registry_login.sh" "1 manifest problem(s) in the committed tree"

F="$(clone m2)"; edit_manifest "$F" replace "$ROW_TWO" ""; commit "$F" m2; committed_changed "$F"
gate "$F" "$T/m2.log"; expect "M2: a deleted row FAILs" 1 "$T/m2.log" "census file without manifest row: tests/a/test_two.sh"

F="$(clone m3)"; gitc "$F" rm -q tests/a/test_two.sh; commit "$F" m3; committed_changed "$F"
gate "$F" "$T/m3.log"; expect "M3: a stale row FAILs" 1 "$T/m3.log" "stale manifest row (no such test file / module): tests/a/test_two.sh"

F="$(clone m4)"; sed -i 's/ total=2$/ total=7/' "$F/docs/guides/full_suite_runner_guide.md"; commit "$F" m4; committed_changed "$F"
gate "$F" "$T/m4.log"; expect "M4: a stale guide census block FAILs" 1 "$T/m4.log" "census block is stale"

F="$(clone m5)"
for n in a b c; do printf '#!/usr/bin/env bash\necho ok\n' >"$F/tests/a/test_new_$n.sh"; done
commit "$F" m5; committed_changed "$F"
gate "$F" "$T/m5.log"; expect "M5: three committed census files without rows, all named" 1 "$T/m5.log" \
    "tests/a/test_new_a.sh" "tests/a/test_new_b.sh" "tests/a/test_new_c.sh" "3 manifest problem(s) in the committed tree"

F="$(clone m6)"; edit_manifest "$F" replace "$ROW_TWO" $'tests/a/test_two.sh\tsh\texcluded\t-\t-\t-\toverride: reason: tool: m6\n'
commit "$F" m6; committed_changed "$F"
gate "$F" "$T/m6.log"; expect "M6: an excluded row without an accepted lock FAILs (temp path stripped)" 1 "$T/m6.log" \
    "FAIL — excluded set (1 row(s)) is not accepted: config/full_suite_excluded.lock is absent"

F="$(clone m7)"; gitc "$F" rm -q --cached tests/a/test_two.sh; gitc "$F" commit -q -m untrack; committed_changed "$F"
[ -f "$F/tests/a/test_two.sh" ] || setup_bug "m7: the file must stay on disk"
gate "$F" "$T/m7.log"; expect "M7: a committed stale row hidden by the file left on disk FAILs (P07a)" 1 "$T/m7.log" \
    "stale manifest row (no such test file / module): tests/a/test_two.sh" "untracked: yes"

F="$(clone w7)"; printf '#!/usr/bin/env bash\necho ok\n' >"$F/tests/a/test_registry_login.sh"; commit "$F" w7; committed_changed "$F"
printf '#!/usr/bin/env bash\necho "census: sh/entry=2 total=2"\necho "RESULT: MANIFEST-OK"\nexit 0\n' >"$F/scripts/run_full_suite.sh"
gate "$F" "$T/w7.log"; expect "W7: an uncommitted runner edit is not used; HEAD's own runner judges HEAD (FAIL + NOTE)" 1 "$T/w7.log" \
    "census file without manifest row: tests/a/test_registry_login.sh" "staged: no, unstaged: yes, untracked: no"

F="$(clone d1)"; edit_manifest "$F" append "$ROW_ONE"; commit "$F" d1; committed_changed "$F"
gate "$F" "$T/d1.log"; expect "D1: a committed duplicated row FAILs with the runner's reason (F1)" 1 "$T/d1.log" \
    "RESULT: MANIFEST-MISMATCH (manifest line" "duplicate path tests/a/test_one.sh)" "the runner refused the committed manifest"

F="$(clone d2)"; edit_manifest "$F" replace "$ROW_TWO" $'tests/a/test_two.sh\tsh\tentry\tdefault\tbash\t-\n'
commit "$F" d2; committed_changed "$F"
gate "$F" "$T/d2.log"; expect "D2: a committed row with six columns FAILs with the runner's reason (F1)" 1 "$T/d2.log" "want 7 TAB columns, got 6"

F="$(clone d3)"; gitc "$F" rm -q config/full_suite_manifest.tsv; commit "$F" d3; committed_changed "$F"
gate "$F" "$T/d3.log"; expect "D3: HEAD with the runner but no manifest FAILs" 1 "$T/d3.log" "carries scripts/run_full_suite.sh but no config/full_suite_manifest.tsv"

F="$(clone d4)"; edit_manifest "$F" replace "# config/" $'# config\v/'; commit "$F" d4; committed_changed "$F"
gate "$F" "$T/d4.log"; expect "D4: a committed manifest line with a vertical tab FAILs with the runner's reason" 1 "$T/d4.log" \
    "RESULT: MANIFEST-MISMATCH (manifest: config/full_suite_manifest.tsv line 1 holds the character"

F="$(clone d5)"; printf '# lock\x0b\n' >"$F/config/full_suite_excluded.lock"; commit "$F" d5; committed_changed "$F"
gate "$F" "$T/d5.log"; expect "D5: a committed excluded lock with a vertical tab FAILs with the runner's reason" 1 "$T/d5.log" \
    "RESULT: MANIFEST-MISMATCH (excluded lock: config/full_suite_excluded.lock line 1 holds the character"

# ---- BLIND -------------------------------------------------------------------------------------
F="$(clone b1)"; gitc "$F" rm -q scripts/run_full_suite.sh; commit "$F" b1; committed_changed "$F"
gate "$F" "$T/b1.log"; expect "B1: HEAD with a manifest but no runner is BLIND" 2 "$T/b1.log" "no runner file"

F="$(clone b2)"; printf '#!/usr/bin/env bash\necho ok\n' >"$F/tests/a/test_hidden.sh"; mkstub "$F" always_ok
gate "$F" "$T/b2.log"; expect "B2: a runner that answers OK to anything is caught by the control needle" 2 "$T/b2.log" "control needle"

F="$(clone n1)"; mkstub "$F" needle_rc0
gate "$F" "$T/n1.log"; expect "N1: a needle answer with exit 0 is BLIND" 2 "$T/n1.log" "control needle: the runner exited 0"
i=2
for pat in "census file without manifest row:" "stale manifest row" "excluded set (1 row(s))" "census block is stale" "RESULT: MANIFEST-MISMATCH"; do
    F="$(clone "n$i")"; mkstub "$F" needle_drop "$pat"
    gate "$F" "$T/n$i.log"; expect "N$i: a runner blind to the needle's '$pat' line is BLIND (F5)" 2 "$T/n$i.log" "control needle:"
    i=$((i + 1))
done
F="$(clone n7)"; mkstub "$F" dup_ok
gate "$F" "$T/n7.log"; expect "N7: a runner that accepts a duplicated row is BLIND" 2 "$T/n7.log" "did not refuse a duplicated manifest row"
F="$(clone n8)"; mkstub "$F" gen_fail
gate "$F" "$T/n8.log"; expect "N8: a runner that cannot generate the needle manifest is BLIND" 2 "$T/n8.log" "could not generate"

F="$(clone r1)"; mkstub "$F" canned "census: sh/entry=2 total=2" 0
gate "$F" "$T/r1.log"; expect "R1: exit 0 without 'RESULT: MANIFEST-OK' is BLIND" 2 "$T/r1.log" "without 'RESULT: MANIFEST-OK'"
F="$(clone r2)"; mkstub "$F" canned "$(printf 'census: sh/entry=0 total=0\nRESULT: MANIFEST-OK')" 0
gate "$F" "$T/r2.log"; expect "R2: MANIFEST-OK on a census total of 0 is BLIND" 2 "$T/r2.log" "census total of '0'"
F="$(clone r3)"; mkstub "$F" canned "boom" 5
gate "$F" "$T/r3.log"; expect "R3: an unexpected runner exit code is BLIND" 2 "$T/r3.log" "runner exit 5"
F="$(clone r4)"; mkstub "$F" canned "MANIFEST: census file without manifest row: tests/a/test_x.sh" 3
gate "$F" "$T/r4.log"; expect "R4: exit 3 without a result line is BLIND" 2 "$T/r4.log" "without a MANIFEST-MISMATCH result"
F="$(clone r5)"; mkstub "$F" canned "RESULT: MANIFEST-MISMATCH (census instrument blind: git ls-files listed nothing)" 3
gate "$F" "$T/r5.log"; expect "R5: a 'census instrument blind' refusal is BLIND, not FAIL" 2 "$T/r5.log" "not a manifest defect" "census instrument blind"
F="$(clone r6)"; mkstub "$F" canned "RESULT: MANIFEST-MISMATCH (manifest line x: duplicate path y)" 3
gate "$F" "$T/r6.log"; expect "R6: a malformed 'manifest line' refusal is BLIND" 2 "$T/r6.log" "not a manifest defect"
F="$(clone r7)"; mkstub "$F" canned "RESULT: MANIFEST-MISMATCH with no reason in parentheses" 3
gate "$F" "$T/r7.log"; expect "R7: a MANIFEST-MISMATCH with no MANIFEST: line and no readable reason is BLIND" 2 "$T/r7.log" \
    "without a MANIFEST: line or a readable reason"

F="$(clone x1)"; mkdir -p "$F/sub/scripts" "$F/sub/config"; cp "$F/scripts/run_full_suite.sh" "$F/sub/scripts/"; cp "$F/config/full_suite_manifest.tsv" "$F/sub/config/"
gate "$F/sub" "$T/x1.log"; expect "X1: --root below the top of the work tree (runner on disk there) is BLIND" 2 "$T/x1.log" "not the top of its git work tree"
X="$T/x2"; mkdir -p "$X/scripts" "$X/config"; ginit "$X" || setup_bug "init x2"; : >"$X/scripts/run_full_suite.sh"; : >"$X/config/full_suite_manifest.tsv"
gate "$X" "$T/x2.log"; expect "X2: an unborn HEAD with files on disk is BLIND" 2 "$T/x2.log" "HEAD is unborn"
X="$T/x3"; mkdir -p "$X/scripts"; : >"$X/scripts/run_full_suite.sh"
gate "$X" "$T/x3.log"; expect "X3: a directory that is not a git repository but has a runner is BLIND" 2 "$T/x3.log" "BLIND"
X="$T/x4"; mkdir -p "$X/scripts" "$T/x4bin"; : >"$X/scripts/run_full_suite.sh"; ln -s "$(command -v dirname)" "$T/x4bin/dirname"
RC=0; runs=$((runs + 1)); PATH="$T/x4bin" TMPDIR="$GT" "$BASH" "$GATE" --root "$X" >"$T/x4.log" 2>&1 || RC=$?
expect "X4: no git on PATH (a runner on disk) is BLIND and says why" 2 "$T/x4.log" "git not found"

# ---- caller's default git files, layouts, fsmonitor, runner temp (review round 2, N1 N2 N6) -----
# genv <root> <log> <VAR=value>...: run the gate with extra environment; sets RC (like gate()).
genv() {
    local r="$1" log="$2"; shift 2
    RC=0; runs=$((runs + 1))
    env "$@" TMPDIR="$GT" bash "$GATE" --root "$r" >"$log" 2>&1 || RC=$?
    if [ -z "$leak" ] && [ -n "$(find "$GT" -mindepth 1 -maxdepth 1 -print -quit)" ]; then leak="$log"; fi
}
# xdg <name> <file under git/> <content>: an XDG config home holding one git default file.
xdg() {
    local d="${T:?}/xdg_$1"
    mkdir -p "$d/git" || setup_bug "mkdir xdg $1"
    printf '%s\n' "$3" >"$d/git/$2" || setup_bug "write xdg $1"
    printf '%s' "$d"
}
F="$(clone a1)"; XA="$(xdg a1 attributes '* text eol=crlf')"
genv "$F" "$T/a1.log" XDG_CONFIG_HOME="$XA"; expect "A1: a caller's default attributes file with eol=crlf does not change the verdict" 0 "$T/a1.log" "PASS"
F="$(clone a2)"; XA="$(xdg a2 attributes '*.tsv text working-tree-encoding=UTF-16LE')"
genv "$F" "$T/a2.log" XDG_CONFIG_HOME="$XA"; expect "A2: a caller's default attributes file with working-tree-encoding does not make a correct HEAD FAIL" 0 "$T/a2.log" "PASS"
F="$(clone a3)"; XA="$(xdg a3 ignore 'tests/')"
genv "$F" "$T/a3.log" XDG_CONFIG_HOME="$XA"; expect "A3: a caller's default ignore file does not blind the needle" 0 "$T/a3.log" "PASS" "control needle seen"
F="$(clone a4)"; XA="$(xdg a4 attributes '* text eol=crlf')"; edit_manifest "$F" append "$(printf 'tests/a/test_gone.sh\tsh\tentry\tdefault\tbash\t-\tauto')"$'\n'; commit "$F" a4 || setup_bug "commit a4"; committed_changed "$F"
genv "$F" "$T/a4.log" XDG_CONFIG_HOME="$XA"; expect "A4: with that attributes file a stale committed row still FAILs" 1 "$T/a4.log" "stale manifest row" "test_gone.sh"

F="$(clone l1)"; gitc "$F" rm -q --cached config/full_suite_manifest.tsv || setup_bug "rm l1"
rm -f -- "${F:?}/config/full_suite_manifest.tsv"; ln -s no_such_manifest.tsv "$F/config/full_suite_manifest.tsv"; commit "$F" l1 || setup_bug "commit l1"; committed_changed "$F"
genv "$F" "$T/l1.log"; expect "L1: a committed dangling-symlink manifest is a FAIL (manifest missing)" 1 "$T/l1.log" "manifest missing"
F="$(clone l2base)"; W2="$T/l2wt"
gitc "$F" worktree add -q --detach "$W2" HEAD >"$T/l2.setup.log" 2>&1 || setup_bug "worktree add: $(tail -n 2 "$T/l2.setup.log")"
[ -f "$W2/.git" ] || setup_bug "l2: the linked worktree has no gitfile"
genv "$W2" "$T/l2.log"; expect "L2: a linked worktree (gitfile root) passes" 0 "$T/l2.log" "PASS"
F="$(clone l3)"; FM="$T/l3_fsmonitor_ran"; HK="$T/l3_fsmonitor.sh"
printf '#!/usr/bin/env bash\n: >"%s"\nexit 1\n' "$FM" >"$HK"; chmod +x "$HK"
gitc "$F" config core.fsmonitor "$HK" || setup_bug "config l3"
genv "$F" "$T/l3.log"; expect "L3: the inspected repository's fsmonitor setting is not run" 0 "$T/l3.log" "PASS"
if [ -e "$FM" ]; then ko "L3: the fsmonitor hook of the inspected repository ran (marker $FM exists)"; else ok "L3: the fsmonitor hook did not run"; fi
gitc "$F" -c core.fsmonitor="$HK" status --porcelain >/dev/null 2>&1
if [ -e "$FM" ]; then ok "L3 needle: the same hook does run under a plain git status"; else setup_bug "l3: the fsmonitor needle hook never runs, so L3 proves nothing"; fi

F="$(clone f1)"; FT="$T/f1_fst"; mkdir -p "$FT"
genv "$F" "$T/f1.log" FULL_SUITE_TMPDIR="$FT"; expect "F1: an ambient FULL_SUITE_TMPDIR does not change the verdict" 0 "$T/f1.log" "PASS"
if [ -z "$(find "$FT" -mindepth 1 -print -quit)" ]; then ok "F1: nothing was left in the ambient FULL_SUITE_TMPDIR"; else ko "F1: files left in the ambient FULL_SUITE_TMPDIR"; fi

# ---- SKIP --------------------------------------------------------------------------------------
X="$T/skip1"; mkdir -p "$X"; ginit "$X" || setup_bug "init skip1"
gate "$X" "$T/skip1.log"; expect "SKIP: an empty git repository" 3 "$T/skip1.log" "SKIP"
X="$T/skip2"; mkdir -p "$X"
gate "$X" "$T/skip2.log"; expect "SKIP: a plain empty directory" 3 "$T/skip2.log" "SKIP"
X="$T/skip3"; mkdir -p "$X"; ginit "$X" || setup_bug "init skip3"; printf 'x\n' >"$X/readme"; commit "$X" s3 || setup_bug "commit skip3"
mkdir -p "$X/scripts" "$X/config"; : >"$X/scripts/run_full_suite.sh"; : >"$X/config/full_suite_manifest.tsv"
gate "$X" "$T/skip3.log"; expect "SKIP: HEAD carries neither file (both only on disk)" 3 "$T/skip3.log" "SKIP" "HEAD"

# ---- usage -------------------------------------------------------------------------------------
RC=0; bash "$GATE" --root >"$T/u1.log" 2>&1 || RC=$?; expect "usage: --root without a value" 64 "$T/u1.log"
RC=0; bash "$GATE" --bogus >"$T/u2.log" 2>&1 || RC=$?; expect "usage: an unknown argument" 64 "$T/u2.log"
RC=0; bash "$GATE" --help >"$T/u3.log" 2>&1 || RC=$?; expect "usage: --help" 0 "$T/u3.log" "Usage" "Control needle"

# ---- no leak -----------------------------------------------------------------------------------
if [ -z "$leak" ]; then ok "no leak: $runs gate runs left nothing in their TMPDIR"
else ko "leak: the gate left files in its TMPDIR (first seen after $leak)"; fi

echo "[mutation:manifest-complete] passed=$pass failed=$fail"
[ "$fail" = 0 ] && { echo "MUTATION PAIR VALID"; exit 0; }
exit 1
