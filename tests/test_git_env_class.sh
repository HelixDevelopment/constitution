#!/usr/bin/env bash
# test_git_env_class.sh — proves the "ambient git variables redirect a write" class is closed (CON-402).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# A script that runs a writing git command inherits the caller's GIT_DIR / GIT_INDEX_FILE / ...; GIT_DIR beats
# `git -C` and `cd`, so under a git hook it writes into another repository (measured 2026-11-13/14:
# cm_agent_type_label.sh committed into a sentinel repository, cm_anchor_record_complete.sh renamed its branch
# and added a commit while reporting PASS). This test checks the census instrument and the behaviour:
#   C1  the census of this tree is PASS, its closed-world inventory accounts for every tracked path and is not
#       trivially small, every file an independent instrument (`git grep -i -P '(?<![A-Za-z])git'` over
#       sh/py/js/bash/zsh/ksh in the WHOLE tree) finds is a census member (C1b), every tracked code file in which
#       an independent write regex sees a git write is a census member (C1d, round 4 R4-1; control needle:
#       install_upstreams.sh, the writer round 3 missed), the round-3 and round-4 writers are HERMETIC and the
#       three guards carry subject-follows-caller rows;
#   C2  on fixture trees the census FAILs an unscrubbed shell file, a scrub with one variable missing, a scrub
#       placed after the first write, an unscrubbed python file, a stale and a malformed exemption row, git called
#       through a variable, an array or a python helper (round 3), a text-only member with no row, a row whose
#       reason the file contradicts, a legacy loop that clears nothing (R3-2), and PASSes the canonical scrub
#       (shell, python, javascript) and valid rows (golden-FALSE, §11.4.201(1));
#   C3  the census is BLIND (exit 2) when the canonical list is absent;
#   B1  behaviour: named gates and the sourced library run with GIT_DIR, GIT_INDEX_FILE and both aimed at a
#       sentinel repository, and the sentinel (paths, types, sizes, modes, every file's sha256, .git included)
#       must be unchanged; the gates must also give the same verdict as without the variables;
#   B2  the sourced library helix_code_home.sh does not clear the caller's own variables (it scrubs in a subshell);
#   B3  behaviour of the round-3 writers (review R3-1): cm_rule_binds_to_seam.sh --selftest, its mutation test and
#       the gitlink / helix-deps mutation tests run with GIT_DIR aimed at a sentinel, which must stay unchanged and
#       the verdict must equal the run without the variable;
#   B4  behaviour of round-4 members outside scripts/ and tests/ and of R4-2/R4-7 (review of 104bc231):
#       install_upstreams.sh in a throwaway repository, progressive/mutation_matrix.py make_sandbox, and
#       multitrack_device_lock.sh --help (a reader of a sourced library) under GIT_DIR (and GIT_INDEX_FILE) aimed
#       at a sentinel: sentinel unchanged; the PreToolUse guards are NOT scrubbed (subject-follows-caller): the
#       label guard names the GIT_DIR repository's branch, and the binding guard's `git status` takes no optional
#       lock (a stale index in the GIT_DIR repository is not rewritten; needle: a plain `git status` does).
#   A sentinel needle runs first: a bare `git commit` under the same GIT_DIR MUST change the sentinel, else the
#   sentinel cannot see a write and B1 proves nothing (§11.4.273).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   bash tests/test_git_env_class.sh [--fast] [--census <path>] [--only-census]
#   --fast skips the slow behavioural member (cm_agent_type_label.sh, about 4 minutes a run on a loaded host;
#   without --fast it runs twice, with no variable and with GIT_DIR + GIT_INDEX_FILE together).
#   --census runs C1 to C3 against another copy of the census (used for its paired mutants);
#   --only-census stops after C3.
#   Exit: 0 no case failed · 1 a case failed · 2 setup error. A behavioural case that cannot run is printed as
#   SKIP with its reason and counted in `skipped=`; it is never counted as passed.
#
# ── Side-effects ──────────────────────────────────────────────────────────
#   A trap-cleaned temp dir. The repository is only read.
#
# ── Dependencies ──────────────────────────────────────────────────────────
#   bash, git, python3, find, sort, sha256sum, mktemp; go for B1 of cm_anchor_record_complete.sh (SKIP with a
#   reason when go or submodules/continuum is absent). Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: this test's own git calls (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CENSUS="$ROOT/scripts/validation/git_env_class_census.py"
LIB="$ROOT/scripts/lib/constitution_layout.sh"
FAST=0; ONLY_CENSUS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --fast) FAST=1; shift ;;
        --census) [ $# -ge 2 ] || { echo "usage: --census <path>" >&2; exit 2; }; CENSUS="$2"; shift 2 ;;
        --only-census) ONLY_CENSUS=1; shift ;;
        *) echo "usage: ${0##*/} [--fast] [--census <path>] [--only-census]" >&2; exit 2 ;;
    esac
done
for _f in "$CENSUS" "$LIB"; do [ -f "$_f" ] || { echo "[git-env-class] setup: missing $_f" >&2; exit 2; }; done
for _t in git python3 find sort sha256sum mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[git-env-class] setup: required tool '$_t' missing" >&2; exit 2; }
done

T="$(mktemp -d)" || { echo "[git-env-class] setup: mktemp failed" >&2; exit 2; }
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() { [ -n "${T:-}" ] && [ -d "${T:?}" ] && rm -rf -- "${T:?}"; }
trap cleanup EXIT
pass=0; fail=0; skip=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
ko() { fail=$((fail + 1)); echo "FAIL $1"; }
sk() { skip=$((skip + 1)); echo "SKIP $1"; }
setup_bug() { echo "[git-env-class] setup: $1" >&2; exit 2; }
gitc() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$1" -c user.email=a@b -c user.name=t -c core.hooksPath=/dev/null "${@:2}"; }
CANON="$(sed -n 's/^CL_GIT_SCRUB_VARS="\([^"]*\)".*/\1/p' "$LIB")"
[ -n "$CANON" ] || setup_bug "CL_GIT_SCRUB_VARS not found in $LIB"
SCRUB_SH="for _ge_v in $CANON; do unset \"\$_ge_v\"; done; unset _ge_v"

# ---- C1 the tree ------------------------------------------------------------------------------
rc=0; python3 -I "$CENSUS" --root "$ROOT" --tsv >"$T/c1.log" 2>&1 || rc=$?
members="$(sed -n 's/.* members=\([0-9][0-9]*\) .*/\1/p' "$T/c1.log" | tail -n 1)"
universe="$(sed -n 's/.* universe=\([0-9][0-9]*\) .*/\1/p' "$T/c1.log" | tail -n 1)"
if [ "$rc" = 0 ] && grep -q ': PASS - ' "$T/c1.log" && [ "${members:-0}" -ge 500 ] && [ "${universe:-0}" -ge 1500 ] && grep -q 'unclassified=0 ' "$T/c1.log" && grep -qE 'tracked=([0-9]+) accounted=\1 ' "$T/c1.log"; then ok "C1: census of this tree PASS, universe $universe, $members members"
else ko "C1: census of this tree exit $rc, universe '${universe:-none}' members '${members:-none}' (want 0, PASS, >= 1500, >= 500, unclassified=0, tracked=accounted): $(tail -n 3 "$T/c1.log" | tr '\n' ' ')"
fi
# C1b: an independent instrument for membership (git grep, not the census's own reader). Control needle: the
# same query must find the census itself (a file known to mention git), else the instrument is blind.
( cd "$ROOT" && git grep -l -I -i -P '(?<![A-Za-z])git' -- '*.sh' '*.py' '*.js' '*.bash' '*.zsh' '*.ksh' ) | sort >"$T/c1_indep.txt"
cut -f3 "$T/c1.log" | sort -u >"$T/c1_members.txt"
nind="$(wc -l <"$T/c1_indep.txt")"
missing="$(comm -23 "$T/c1_indep.txt" "$T/c1_members.txt" | head -n 5 | tr '\n' ' ')"
if ! grep -qxF scripts/validation/git_env_class_census.py "$T/c1_indep.txt"; then ko "C1b: the independent query does not find the census itself (control needle): the instrument is blind"
elif [ "$nind" -ge 450 ] && [ -z "$missing" ]; then ok "C1b: all $nind files the independent query finds are census members"
else ko "C1b: independent query found $nind files; not census members: $missing"; fi
for f in scripts/gates/cm_rule_binds_to_seam.sh scripts/gates/cm_rule_binds_to_seam_mutation_test.sh \
         scripts/gates/cm_gitlink_on_remote_mutation_test.sh scripts/gates/cm_helix_deps_ref_matches_gitlink_mutation_test.sh \
         scripts/fastcycle/tests/test_fc_supervisor_v4r8_stream_matrix.sh scripts/fastcycle/tests/test_fc_supervisor_v4r9_shutdown_windows.sh \
         scripts/fastcycle/cycle/fc_supervisor.py scripts/codegraph/scope_enumerate.js \
         install_upstreams.sh find_constitution.sh progressive/mutation_matrix.py progressive/validate_submodule.py \
         scripts/multitrack/multitrack_device_lock.sh docs/qa/ownership_wave2/repro_p8.sh; do
    if grep -qP "^HERMETIC\t[a-z]+\t\Q$f\E\t" "$T/c1.log"; then ok "C1c: $f is HERMETIC"
    else ko "C1c: $f is not HERMETIC: $(grep -F "$f" "$T/c1.log" | head -n 1)"; fi
done

for f in scripts/hooks/guard-branch-consistency.sh scripts/hooks/guard-track-branch-label.sh scripts/hooks/guard-work-track-binding.sh; do
    if grep -qP "^EXEMPT\t[a-z]+\t\Q$f\E\t[0-9]+\tsubject-follows-caller" "$T/c1.log"; then ok "C1c: $f is EXEMPT subject-follows-caller (R4-7)"
    else ko "C1c: $f: $(grep -F "$f" "$T/c1.log" | head -n 1)"; fi
done
# C1d (R4-1): an independent write instrument over the WHOLE tree (its own ls-files, its own code test, its own
# regex): every tracked code file in which `git [-C x|-c k=v]... <write>` appears outside a comment line must be
# a census member. Control needle: install_upstreams.sh (a writer at the root, outside round 3's universe).
python3 -I - "$ROOT" >"$T/c1d.txt" 2>&1 <<'PY'
import os, re, subprocess, sys
root = sys.argv[1]
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
out = subprocess.run(["git", "-C", root, "ls-files", "-z", "-s"], capture_output=True, env=env, check=True).stdout.decode()
W = re.compile(r"(?<![\w./-])git(?:\s+-[Cc]\s+\S+)*\s+(?:init|add|commit|push|config|remote|reset|checkout|switch|branch|tag|merge|rebase|rm|mv|stash|worktree|submodule|update-ref|update-index|symbolic-ref|notes|fetch|pull|clone|apply|am|cherry-pick|revert|gc|prune)\b")
CODE = (".sh", ".bash", ".zsh", ".ksh", ".py", ".js", ".mjs", ".cjs")
for rec in out.split("\0"):
    if not rec:
        continue
    meta, path = rec.split("\t", 1)
    mode = meta.split()[0]
    if mode in ("160000", "120000"):
        continue
    p = os.path.join(root, path)
    try:
        raw = open(p, "rb").read()
    except OSError:
        continue
    if b"\0" in raw[:8192]:
        continue
    base = os.path.basename(path)
    code = base.endswith(CODE) or ("." not in base and (raw.startswith(b"#!") or mode == "100755"))
    if not code:
        continue
    text = raw.decode("utf-8", "replace")
    for line in text.split("\n"):
        st = line.lstrip()
        if st.startswith("#") or st.startswith("//"):
            continue
        if W.search(line):
            print(path)
            break
PY
sort -u "$T/c1d.txt" >"$T/c1d_writers.txt"
nw="$(wc -l <"$T/c1d_writers.txt")"
outside="$(comm -23 "$T/c1d_writers.txt" "$T/c1_members.txt" | head -n 5 | tr '\n' ' ')"
if ! grep -qxF install_upstreams.sh "$T/c1d_writers.txt"; then ko "C1d: the independent write instrument does not find install_upstreams.sh (control needle): the instrument is blind"
elif [ "$nw" -ge 150 ] && [ -z "$outside" ]; then ok "C1d: all $nw tracked code files with a git write (independent instrument, whole tree) are census members"
else ko "C1d: $nw writer files found; not census members: $outside"; fi

# ---- C2 fixtures ------------------------------------------------------------------------------
# fx <name> <file> <content>: a git tree with the canonical library and one scripts/ file, all tracked.
fx() {
    local d="$T/fx_$1"
    mkdir -p "$d/scripts/lib" "$d/config" "$(dirname "$d/$2")" || setup_bug "mkdir $1"
    cp "$LIB" "$d/scripts/lib/" || setup_bug "copy lib $1"
    printf '%s\n' "$3" >"$d/$2"
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q --template= "$d" || setup_bug "init $1"
    gitc "$d" add -A || setup_bug "add $1"
    printf '%s' "$d"
}
census_case() { # <label> <want-rc> <tree> <fixed string that must appear>
    local rc=0
    python3 -I "$CENSUS" --root "$3" >"$T/$1.log" 2>&1 || rc=$?
    if [ "$rc" = "$2" ] && grep -qF -- "$4" "$T/$1.log"; then ok "$1: census exit $rc, '$4'"
    else ko "$1: census exit $rc (want $2 and '$4'): $(tail -n 2 "$T/$1.log" | tr '\n' ' ')"
    fi
}
short="$(printf '%s' "$CANON" | sed 's/ GIT_INDEX_FILE / /')"
[ "$short" != "$CANON" ] || setup_bug "could not shorten the canonical list"
census_case C2a 1 "$(fx a scripts/x.sh "$(printf '#!/usr/bin/env bash\ngit -C "$d" init -q')")" "UNSCRUBBED scripts/x.sh"
census_case C2b 0 "$(fx b scripts/x.sh "$(printf '#!/usr/bin/env bash\n%s\ngit -C "$d" init -q' "$SCRUB_SH")")" "PASS"
census_case C2c 1 "$(fx c scripts/x.sh "$(printf '#!/usr/bin/env bash\nfor _ge_v in %s; do unset "$_ge_v"; done; unset _ge_v\ngit init -q' "$short")")" "UNSCRUBBED scripts/x.sh"
census_case C2d 1 "$(fx d scripts/x.sh "$(printf '#!/usr/bin/env bash\ngit init -q\n%s' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
census_case C2e 1 "$(fx e scripts/y.py "$(printf 'import subprocess\nsubprocess.run(["git", "init", "-q"])')")" "UNSCRUBBED scripts/y.py"
census_case C2f 0 "$(fx f scripts/y.py "$(printf 'import os as _ge_os\nfor _ge_v in "%s".split(): _ge_os.environ.pop(_ge_v, None)\nimport subprocess\nsubprocess.run(["git", "init", "-q"])' "$CANON")")" "PASS"
D="$(fx g scripts/x.sh "$(printf '#!/usr/bin/env bash\n# run git init by hand\necho x')")"
printf 'scripts/x.sh\tno-git-execution\ttext only in this fixture\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2g 0 "$D" "exempt=2"
D2="$(fx g2 scripts/x.sh "$(printf '#!/usr/bin/env bash\ngit init -q')")"
printf 'scripts/x.sh\tno-git-execution\ttext only (wrong: it writes)\n' >"$D2/config/git_env_class_exemptions.tsv"
census_case C2g2 1 "$D2" "row no-git-execution, but a git write is detected"
printf 'scripts/x.sh\tno-git-execution\ttext only\nscripts/gone.sh\tno-git-execution\tstale\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2h 1 "$D" "stale row"
printf 'scripts/x.sh\tbecause\tan invented reason\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2i 1 "$D" "malformed"
# round 2 (review of e0373341): F1 a scrub that clears a discovery LIMIT; F3 a scrub that does nothing (a
# carrier: the line names every variable but runs no unset/pop, or sits in a block that never runs); F2 git
# calls the line scan did not see (python inside a shell heredoc, a shell wrapper function); F4 a sourced
# library whose scrub lives in a wrapper but one call site bypasses it.
with_ceil="$CANON GIT_CEILING_DIRECTORIES"
census_case C2j 1 "$(fx j scripts/x.sh "$(printf '#!/usr/bin/env bash\nfor _ge_v in %s; do unset "$_ge_v"; done; unset _ge_v\ngit init -q' "$with_ceil")")" "UNSCRUBBED scripts/x.sh"
census_case C2j2 1 "$(fx j2 scripts/x.sh "$(printf '#!/usr/bin/env bash\n%s\nunset GIT_CEILING_DIRECTORIES\ngit init -q' "$SCRUB_SH")")" "discovery limit"
census_case C2k 1 "$(fx k scripts/y.py "$(printf '# list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh\nimport os as _ge_os\nfor _ge_v in "%s".split(): _ge_os.environ.get(_ge_v, None)\nimport subprocess\nsubprocess.run(["git", "init", "-q"])' "$CANON")")" "UNSCRUBBED scripts/y.py"
census_case C2l 1 "$(fx l scripts/x.sh "$(printf '#!/usr/bin/env bash\n# list = CL_GIT_SCRUB_VARS\nif false; then\n%s\nfi\ngit init -q' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
census_case C2m 1 "$(fx m scripts/x.sh "$(printf '#!/usr/bin/env bash\n# list = CL_GIT_SCRUB_VARS\nfor _ge_v in %s; do : "$_ge_v"; done; unset _ge_v\ngit init -q' "$CANON")")" "UNSCRUBBED scripts/x.sh"
census_case C2m2 1 "$(fx m2 scripts/y.py "$(printf '"""mentions cl_scrub_git_env and GIT_SCRUB_VARS only in a docstring"""\nimport subprocess\nsubprocess.run(["git", "init", "-q"])')")" "UNSCRUBBED scripts/y.py"
census_case C2n 1 "$(fx n scripts/x.sh "$(printf '#!/usr/bin/env bash\npython3 - <<%s\nimport subprocess\nsubprocess.run(["git", "init", "-q", "d"], check=True)\nPY' "'PY'")")" "UNSCRUBBED scripts/x.sh"
census_case C2o 1 "$(fx o scripts/x.sh "$(printf '#!/usr/bin/env bash\ng() { git -c core.hooksPath=/dev/null "$@"; }\ng commit -q -m x')")" "UNSCRUBBED scripts/x.sh"
census_case C2o2 0 "$(fx o2 scripts/x.sh "$(printf '#!/usr/bin/env bash\n%s\ng() { git -c core.hooksPath=/dev/null "$@"; }\ng commit -q -m x' "$SCRUB_SH")")" "PASS"
census_case C2p 1 "$(fx p scripts/x.sh "$(printf '#!/usr/bin/env bash\nw__git() {\n  (\n    %s\n    exec git "$@"\n  )\n}\nw__git -C "$d" commit -q -m x\ngit -C "$d" submodule update --init' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
D="$(fx p2 scripts/x.sh "$(printf '#!/usr/bin/env bash\nw__git() {\n  (\n    %s\n    exec git "$@"\n  )\n}\nw__git -C "$d" commit -q -m x\nw__git -C "$d" submodule update --init' "$SCRUB_SH")")"
census_case C2p2 1 "$D" "no sourced-library row"
printf 'scripts/x.sh\tsourced-library\tevery git call goes through w__git\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2p3 0 "$D" "PASS"
census_case C2q 1 "$(fx q scripts/x.sh "$(printf '#!/usr/bin/env bash\nset -u\n# list = CL_GIT_SCRUB_VARS\nf() {\n%s\n}\ngit init -q' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
census_case C2r 0 "$(fx r scripts/x.sh "$(printf '#!/usr/bin/env bash\nset -u -o pipefail\nexport LC_ALL=C\n%s\ngit init -q' "$SCRUB_SH")")" "PASS"
# a wrapper that runs git under `env -i` hands it no caller variable at all; an `env -i` that runs another
# command first does not; a limit name inside a quoted payload (a sed mutation text) is not a scrub
D="$(fx s scripts/x.sh "$(printf '#!/usr/bin/env bash\ng() {\n    env -i PATH="$PATH" \\\n        git -c a=b "$@"\n}\ng commit -q -m x')")"
printf 'scripts/x.sh\tsourced-library\tgit runs only under env -i\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2s 0 "$D" "PASS"
D="$(fx s2 scripts/x.sh "$(printf '#!/usr/bin/env bash\ng() { env -i true; git -c a=b "$@"; }\ng commit -q -m x')")"
printf 'scripts/x.sh\tsourced-library\tclaimed env -i wrapper\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2s2 1 "$D" "UNSCRUBBED scripts/x.sh"
census_case C2t 0 "$(fx t scripts/x.sh "$(printf "#!/usr/bin/env bash\n%s\nsed 's/x/env -u GIT_CEILING_DIRECTORIES y/' f\ngit init -q" "$SCRUB_SH")")" "PASS"

# legacy scrub that names the list but clears nothing; python scrub placed after the first write; a
# docstring that names the list and a pop (a carrier, not code)
census_case C2u 1 "$(fx u scripts/x.sh "$(printf '#!/usr/bin/env bash\nGIT_SCRUB_VARS="%s"\ngit init -q' "$CANON")")" "no file-level scrub"
census_case C2v 1 "$(fx v scripts/y.py "$(printf 'import subprocess\nsubprocess.run(["git", "init", "-q"])\nimport os as _ge_os\nfor _ge_v in "%s".split(): _ge_os.environ.pop(_ge_v, None)' "$CANON")")" "is not effective"
census_case C2w 1 "$(fx w scripts/y.py "$(printf '"""GIT_SCRUB_VARS %s: each os.environ.pop(v)"""\nimport subprocess\nsubprocess.run(["git", "init", "-q"])' "$CANON")")" "UNSCRUBBED scripts/y.py"

# round 3 (review of 005bcfd1, R3-1/R3-2): membership is closed-world (any `git` in the text), so git called
# through a variable, an array, a python helper or a list argument is a member; a row is checked against the file
census_case C2x 1 "$(fx x scripts/x.sh "$(printf '#!/usr/bin/env bash\nGIT="git -c a=b"\n$GIT init -q .')")" "UNSCRUBBED scripts/x.sh"
D="$(fx x2 scripts/x.sh "$(printf '#!/usr/bin/env bash\nGIT="git -c a=b"\n$GIT init -q .')")"
printf 'scripts/x.sh\tno-git-execution\tclaimed text only\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2x2 1 "$D" "row no-git-execution, but a git write is detected"
D="$(fx y scripts/x.sh "$(printf '#!/usr/bin/env bash\nG=(git -c a=b)\n"${G[@]}" -C "$d" commit -q -m x')")"
printf 'scripts/x.sh\tsourced-library\tclaimed library\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2y 1 "$D" "row sourced-library, but"
D="$(fx z scripts/x.sh "$(printf '#!/usr/bin/env bash\npython3 - <<%s\nimport subprocess\ndef g(*a):\n    return subprocess.run(["git"] + list(a))\ng("init", "-q", "d")\nPY' "'PY'")")"
printf 'scripts/x.sh\tno-git-execution\tclaimed text only\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2z 1 "$D" "row no-git-execution, but a git write is detected"
D="$(fx aa scripts/y.py "$(printf 'import subprocess\ndef _git(repo, args):\n    return subprocess.run(["git", "-C", repo] + args)\n_git(r, ["worktree", "prune"])')")"
printf 'scripts/y.py\tno-git-execution\tclaimed text only\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2aa 1 "$D" "row no-git-execution, but a git write is detected"
census_case C2ab 1 "$(fx ab scripts/x.sh "$(printf '#!/usr/bin/env bash\n# mentions GITHUB only\necho x')")" "no row in the exemption list"
census_case C2ac 1 "$(fx ac scripts/x.sh "$(printf '#!/usr/bin/env bash\n_git_scrub=(%s)\nfor _v in "${_git_scrub[@]}"; do : "$_v"; done\nunset _v\ngit init -q' "$CANON")")" "UNSCRUBBED scripts/x.sh"
census_case C2ac2 0 "$(fx ac2 scripts/x.sh "$(printf '#!/usr/bin/env bash\n_git_scrub=(%s)\nfor _v in "${_git_scrub[@]}"; do unset "$_v"; done\nunset _v\ngit init -q' "$CANON")")" "PASS"
census_case C2ad 0 "$(fx ad scripts/z.js "$(printf "#!/usr/bin/env node\n'use strict';\nfor (const _ge_v of \"%s\".split(\" \")) delete process.env[_ge_v];\nrequire('child_process').execFileSync('git', ['init']);" "$CANON")")" "PASS"
census_case C2ad2 1 "$(fx ad2 scripts/z.js "$(printf "#!/usr/bin/env node\nrequire('child_process').execFileSync('git', ['init']);")")" "UNSCRUBBED scripts/z.js"
D="$(fx ae scripts/fixtures/t/hook "$(printf '#!/bin/sh\n# a fake git hook\necho hook')")"
printf 'scripts/fixtures/t/\tfixture-tree\tdata tree\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2ae 0 "$D" "PASS"
D="$(fx ae2 scripts/fixtures/t/hook "$(printf '#!/bin/sh\ngit commit -q -m x')")"
printf 'scripts/fixtures/t/\tfixture-tree\tdata tree\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2ae2 1 "$D" "needs its own row"
D="$(fx ae3 scripts/t/hook "$(printf '#!/bin/sh\n# git\necho hook')")"
printf 'scripts/t/\tfixture-tree\tnot under fixtures\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2ae3 1 "$D" "prefix row"
D="$(fx af scripts/x.sh "$(printf '#!/usr/bin/env bash\nmain() {\n  local _v\n  for _v in %s; do unset "$_v"; done\n  git add f\n}\nmain "$@"' "$CANON")")"
printf 'scripts/x.sh\tentry-function-scrub\tmain clears first\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2af 0 "$D" "PASS"
D="$(fx af2 scripts/x.sh "$(printf '#!/usr/bin/env bash\nmain() {\n  local _v\n  for _v in %s; do : "$_v"; done\n  unset _v\n  git add f\n}\nmain "$@"' "$CANON")")"
printf 'scripts/x.sh\tentry-function-scrub\tclaimed\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2af2 1 "$D" "no list-operating clear"
# a canonical line at column 0 that is inside a multi-line string is text, not a scrub (own mutant M6); a
# javascript scrub after a statement (C2ai, own mutant M7) or after the first git call (C2ai2) is too late: both are fixtures, not only needles
census_case C2ah 1 "$(fx ah scripts/x.sh "$(printf '#!/usr/bin/env bash\nMSG="\n%s\n"\ngit init -q' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
census_case C2ai 1 "$(fx ai scripts/z.js "$(printf "#!/usr/bin/env node\nconst cp = require('child_process');\nfor (const _ge_v of \"%s\".split(\" \")) delete process.env[_ge_v];\ncp.execFileSync('git', ['init']);" "$CANON")")" "UNSCRUBBED scripts/z.js"
census_case C2ai2 1 "$(fx ai2 scripts/z.js "$(printf "#!/usr/bin/env node\nrequire('child_process').execFileSync('git', ['init']);\nfor (const _ge_v of \"%s\".split(\" \")) delete process.env[_ge_v];" "$CANON")")" "UNSCRUBBED scripts/z.js"
census_case C2ag 0 "$(fx ag scripts/x.sh "$(printf '#!/usr/bin/env bash\necho digit legitimate')")" "members=1 "

# round 4 (review of 104bc231). R4-1: the universe is the whole tree: a writer at the root, under docs/ or in an
# executable file without a shebang (the kernel runs it as shell) is a member; an unknown extension fails the run.
census_case C2r4a 1 "$(fx r4a tool.sh "$(printf '#!/usr/bin/env bash\ngit init -q')")" "UNSCRUBBED tool.sh"
census_case C2r4a2 1 "$(fx r4a2 docs/qa/repro.sh "$(printf '#!/usr/bin/env bash\ngit -C "$d" commit -q -m x')")" "UNSCRUBBED docs/qa/repro.sh"
D="$(fx r4b bin/run "$(printf 'git init -q x')")"
chmod +x "$D/bin/run" && gitc "$D" update-index --chmod=+x bin/run || setup_bug "chmod r4b"
census_case C2r4b 1 "$D" "UNSCRUBBED bin/run"
D="$(fx r4b2 bin/notes "$(printf 'git init -q x')")"
census_case C2r4b2 0 "$D" "PASS"   # boundary: an extensionless file without exec bit or shebang is data (it runs only as `sh file`, like any text file)
census_case C2r4c 1 "$(fx r4c scripts/x.weird "$(printf 'whatever')")" "unclassified"
D="$(fx r4c3 tools/run.txt "$(printf '#!/bin/sh\ngit init -q x')")"
chmod +x "$D/tools/run.txt" && gitc "$D" update-index --chmod=+x tools/run.txt || setup_bug "chmod r4c3"
census_case C2r4c3 1 "$D" "UNSCRUBBED tools/run.txt"
census_case C2r4c2 0 "$(fx r4c2 docs/notes.md "$(printf '#!/bin/sh\ngit init -q x')")" "PASS"
# merge of origin/main (gitenv-r4): a .canon transcript is data unless executable; `unset -v <list>` (the only unset form
# the release network-spawn gate admits) is an own scrub only when it names every variable of the list
census_case C2mrg1 0 "$(fx mrg1 docs/qa/run1.canon "$(printf 'PASS git init\ngit commit -m x')")" "PASS"
D="$(fx mrg1b tools/run.canon "$(printf '#!/bin/sh\ngit init -q x')")"
chmod +x "$D/tools/run.canon" && gitc "$D" update-index --chmod=+x tools/run.canon || setup_bug "chmod mrg1b"
census_case C2mrg1b 1 "$D" "UNSCRUBBED tools/run.canon"
census_case C2mrg2 0 "$(fx mrg2 scripts/x.sh "$(printf '#!/usr/bin/env bash\nunset -v %s\ngit -C "$d" init -q' "$CANON")")" "PASS"
census_case C2mrg3 1 "$(fx mrg3 scripts/x.sh "$(printf '#!/usr/bin/env bash\nunset -v %s\ngit -C "$d" init -q' "$short")")" "UNSCRUBBED scripts/x.sh"
# R4-2: a reader of a sourced library that runs git (unwrapped) must itself be hermetic
D="$(fx r4d scripts/lib2.sh "$(printf '#!/usr/bin/env bash\nlib_top() { git rev-parse --show-toplevel; }')")"
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/lib2.sh"\nlib_top\n' >"$D/scripts/reader.sh"
gitc "$D" add -A || setup_bug "add r4d"
printf 'scripts/lib2.sh\tsourced-library\tread only\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4d 1 "$D" "(R4-2)"
printf '#!/usr/bin/env bash\n%s\n. "$(dirname "$0")/lib2.sh"\nlib_top\n' "$SCRUB_SH" >"$D/scripts/reader.sh"
census_case C2r4d2 0 "$D" "PASS"
# a reader whose own row says it runs no git is still a reader of the library's git calls
printf '#!/usr/bin/env bash\n# reads lib2 (git inside)\n. "$(dirname "$0")/lib2.sh"\nlib_top\n' >"$D/scripts/reader.sh"
printf 'scripts/lib2.sh\tsourced-library\tread only\nscripts/reader.sh\tno-git-execution\tclaimed text only\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4d3 1 "$D" "(R4-2)"
# R4-3: `set -e; git ...` is not a preamble line
census_case C2r4e 1 "$(fx r4e scripts/x.sh "$(printf '#!/usr/bin/env bash\nset -e; git init -q x\n%s\ngit add f' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
census_case C2r4e3 1 "$(fx r4e3 scripts/x.sh "$(printf '#!/usr/bin/env bash\nset -e; . "$0.lib"\n%s\ngit init -q x' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
census_case C2r4e4 1 "$(fx r4e4 scripts/x.sh "$(printf '#!/usr/bin/env bash\nset -e; "git" init -q x\n%s\ngit add f' "$SCRUB_SH")")" "UNSCRUBBED scripts/x.sh"
census_case C2r4e2 0 "$(fx r4e2 scripts/x.sh "$(printf '#!/usr/bin/env bash\nset -e\nshopt -s nullglob\numask 022\n%s\ngit init -q x' "$SCRUB_SH")")" "PASS"
# R4-4: an entry-function-scrub row needs the clear in the entry function, before its first git call, and no
# git at top level
D="$(fx r4f scripts/x.sh "$(printf '#!/usr/bin/env bash\ngit init -q x\nmain() {\n  local _v\n  for _v in %s; do unset "$_v"; done\n  git add f\n}\nmain "$@"' "$CANON")")"
printf 'scripts/x.sh\tentry-function-scrub\tclaimed\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4f 1 "$D" "row entry-function-scrub, but"
D="$(fx r4f2 scripts/x.sh "$(printf '#!/usr/bin/env bash\nmain() {\n  git add f\n  local _v\n  for _v in %s; do unset "$_v"; done\n}\nmain "$@"' "$CANON")")"
printf 'scripts/x.sh\tentry-function-scrub\tclaimed\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4f2 1 "$D" "row entry-function-scrub, but"
# R4-5: a list-operating clear over the wrong list, or inside a heredoc, is not a clear
D="$(fx r4g scripts/x.sh "$(printf '#!/usr/bin/env bash\n# %s\nmain() {\n  local _v\n  for _v in A B; do unset "$_v"; done\n  git add f\n}\nmain "$@"' "$CANON")")"
printf 'scripts/x.sh\tentry-function-scrub\tclaimed\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4g 1 "$D" "row entry-function-scrub, but"
D="$(fx r4g2 scripts/x.sh "$(printf '#!/usr/bin/env bash\nmain() {\n  cat <<EOF\nfor _v in %s; do unset "$_v"; done\nEOF\n  git add f\n}\nmain "$@"' "$CANON")")"
printf 'scripts/x.sh\tentry-function-scrub\tclaimed\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4g2 1 "$D" "row entry-function-scrub, but"
# R4-7: a subject-follows-caller row holds for a read-only guard and fails for a writing one
D="$(fx r4h scripts/hooks/g.sh "$(printf '#!/usr/bin/env bash\nB="$(git rev-parse --abbrev-ref HEAD)"\necho "stage with git add <paths>" >&2')")"
printf 'scripts/hooks/g.sh\tsubject-follows-caller\tread-only guard\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4h 0 "$D" "PASS"
D="$(fx r4h2 scripts/hooks/g.sh "$(printf '#!/usr/bin/env bash\ngit add -A')")"
printf 'scripts/hooks/g.sh\tsubject-follows-caller\tclaimed read-only\n' >"$D/config/git_env_class_exemptions.tsv"
census_case C2r4h2 1 "$D" "row subject-follows-caller, but a git write is detected"

# Jev round 12 (review of a1eeb0d7, R11-C): `.rc` / `.ls` are data only under docs/qa/, not executable, and in the
# captured shape (one exit status; an `ls -l` listing). The reviewer's census mutants CM1 to CM3, then own rows.
census_case C2rc1 1 "$(fx rc1 scripts/evil_env.rc "$(printf 'git -C "$1" commit -qm x')")" "unclassified"          # CM1
D="$(fx rc2 scripts/evil_env.rc "$(printf 'git -C "$1" commit -qm x')")"
chmod +x "$D/scripts/evil_env.rc" && gitc "$D" update-index --chmod=+x scripts/evil_env.rc || setup_bug "chmod rc2"
census_case C2rc2 1 "$D" "UNSCRUBBED scripts/evil_env.rc"                                                             # CM2
census_case C2rc3 1 "$(fx rc3 scripts/evil_list.ls "$(printf '#!/bin/sh\ngit init -q x')")" "UNSCRUBBED scripts/evil_list.ls" # CM3
census_case C2rc4 1 "$(fx rc4 docs/qa/r/gate.rc "$(printf 'GIT_DIR=/tmp/x git commit -q -m m')")" "unclassified"
census_case C2rc5 1 "$(fx rc5 docs/qa/r/d.ls "$(printf 'total 8\ndrwxrwxr-x 2 u u 4096 Nov 13 18:38 .\ngit -C d commit -q -m x')")" "unclassified"
census_case C2rc6 1 "$(fx rc6 docs/qa/r/d.ls "$(printf 'GIT_DIR=/tmp/x git commit -q -m m')")" "unclassified"
census_case C2rc7 1 "$(fx rc7 tests/r/gate.rc "$(printf '0')")" "unclassified"
census_case C2rc8 1 "$(fx rc8 docs/qa/r/gate.rc "$(printf '256')")" "unclassified"
D="$(fx rc9 docs/qa/r/gate.rc "$(printf 'git -C d commit -q -m x')")"
chmod +x "$D/docs/qa/r/gate.rc" && gitc "$D" update-index --chmod=+x docs/qa/r/gate.rc || setup_bug "chmod rc9"
census_case C2rc9 1 "$D" "UNSCRUBBED docs/qa/r/gate.rc"
census_case C2rc10 1 "$(fx rc10 docs/qa/r/gate.rc "$(printf '0\ngit init -q x')")" "unclassified"
census_case C2rc11 0 "$(fx rc11 docs/qa/r/gate.rc "$(printf '0')")" "PASS"                                    # golden-FALSE
census_case C2rc12 0 "$(fx rc12 docs/qa/r/d.ls "$(printf 'total 8\ndrwxrwxr-x 2 <USER> <USER> 4096 Nov 13 18:38 .\ndrwx------ 8 <USER> <USER> 4096 Nov 13 18:38 ..')")" "PASS" # golden-FALSE
census_case C2rc13 1 "$(fx rc13 docs/qa/r/d.ls "$(printf 'total 8\n-rw-rw-r-- 1 u u 1 Nov 13 18:38 x; git commit -q -m y')")" "unclassified"  # an ls-shaped line naming git
census_case C2rc14 1 "$(fx rc14 docs/qa/r/d.ls "$(printf 'total 0\nrm -rf x')")" "unclassified"                    # header, then a non-listing line
D="$(fx rc15 docs/qa/r/gate.rc "$(printf '0')")"
chmod +x "$D/docs/qa/r/gate.rc" && gitc "$D" update-index --chmod=+x docs/qa/r/gate.rc || setup_bug "chmod rc15"
census_case C2rc15 0 "$D" "PASS"     # golden-FALSE: an executable record is code (no git mention, not a member); never data by shape

# ---- C3 BLIND ---------------------------------------------------------------------------------
D="$(fx nolib scripts/x.sh "$(printf '#!/usr/bin/env bash\ngit init -q')")"
gitc "$D" rm -q --cached scripts/lib/constitution_layout.sh || setup_bug "rm lib"
rm -f -- "${D:?}/scripts/lib/constitution_layout.sh"
census_case C3 2 "$D" "BLIND"
# the canonical list must never hold a discovery limit: the census refuses to judge against such a list
D="$(fx ceilcanon scripts/x.sh "$(printf '#!/usr/bin/env bash\n%s\ngit init -q' "$SCRUB_SH")")"
sed -i 's/^CL_GIT_SCRUB_VARS="GIT_DIR /CL_GIT_SCRUB_VARS="GIT_DIR GIT_CEILING_DIRECTORIES /' "$D/scripts/lib/constitution_layout.sh"
grep -q '^CL_GIT_SCRUB_VARS="GIT_DIR GIT_CEILING_DIRECTORIES ' "$D/scripts/lib/constitution_layout.sh" || setup_bug "C3b: could not add the ceiling to the fixture's list"
census_case C3b 2 "$D" "holds the discovery limit GIT_CEILING_DIRECTORIES"

if [ "$ONLY_CENSUS" = 1 ]; then
    echo "[git-env-class] passed=$pass failed=$fail skipped=$skip (census cases only)"
    [ "$fail" = 0 ] || exit 1
    exit 0
fi

# ---- B sentinel -------------------------------------------------------------------------------
fingerprint() { (cd "$1" && { find . -printf '%p\t%y\t%s\t%m\n' | sort; find . -type f -exec sha256sum {} + | sort -k 2; } | sha256sum | cut -c1-64); }
mksen() { # <dir>: a one-commit sentinel repository
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q -b sentinel --template= "$1" || setup_bug "init sentinel"
    printf 's\n' >"$1/s"; gitc "$1" add s && gitc "$1" commit -q -m sentinel || setup_bug "commit sentinel"
}
# needle: the sentinel must see a write made under the same variable
NS="$T/needle_sen"; mksen "$NS"; f0="$(fingerprint "$NS")"
mkdir -p "$T/needle_cwd"
( cd "$T/needle_cwd" && GIT_DIR="$NS/.git" GIT_CONFIG_GLOBAL=/dev/null git -c user.email=a@b -c user.name=t commit -q --allow-empty -m needle ) >/dev/null 2>&1
[ "$(fingerprint "$NS")" != "$f0" ] || setup_bug "sentinel needle: a bare commit under GIT_DIR did not change the sentinel, so it cannot see a write"
ok "B needle: a bare git commit under GIT_DIR changes the sentinel"

# member <label> <want-rc> <modes> <script> [args]: run once per mode (none, git_dir, git_index_file, both)
member() {
    local label="$1" want="$2" modes="$3" script="$4"; shift 4
    local mode rc sen f0 env_
    for mode in $modes; do
        sen="$T/sen_${label}_$mode"; mksen "$sen"; f0="$(fingerprint "$sen")"
        case "$mode" in
            none) env_=() ;;
            git_dir) env_=(GIT_DIR="$sen/.git") ;;
            git_index_file) env_=(GIT_INDEX_FILE="$sen/.git/index") ;;
            both) env_=(GIT_DIR="$sen/.git" GIT_INDEX_FILE="$sen/.git/index") ;;
        esac
        rc=0; ( cd "$ROOT" && env "${env_[@]}" bash "$script" "$@" ) >"$T/${label}_$mode.log" 2>&1 || rc=$?
        if [ "$rc" = "$want" ]; then ok "$label [$mode]: exit $rc"; else ko "$label [$mode]: exit $rc, want $want: $(tail -n 2 "$T/${label}_$mode.log" | tr '\n' ' ')"; fi
        if [ "$(fingerprint "$sen")" = "$f0" ]; then ok "$label [$mode]: sentinel unchanged"; else ko "$label [$mode]: the sentinel repository was written"; fi
    done
}
if ! command -v go >/dev/null 2>&1; then sk "B1 cm_anchor_record_complete.sh: go not on PATH (the gate builds its engine with go)"
elif [ ! -f "$ROOT/submodules/continuum/go.mod" ]; then sk "B1 cm_anchor_record_complete.sh: submodules/continuum is not checked out (the gate's engine)"
else member B1_anchor 0 "none git_dir git_index_file both" scripts/gates/cm_anchor_record_complete.sh
fi
if [ "$FAST" = 1 ]; then sk "B1 cm_agent_type_label.sh: --fast given (about 4 minutes)"
else member B1_agent_label 0 "none both" scripts/gates/cm_agent_type_label.sh
fi

# ---- B2 the sourced library keeps the caller's variables --------------------------------------
sen="$T/sen_b2"; mksen "$sen"; f0="$(fingerprint "$sen")"
# The library sets `set -euo pipefail`, so the probe runs in a plain repository (cwd) where the scrubbed
# hc__git must answer `.git` (its own cwd repository) and an unscrubbed one would answer the sentinel.
plain="$T/plain_b2"; mksen "$plain"
out="$(cd "$plain" && GIT_DIR="$sen/.git" bash -c 'set +u; . "$1" 2>/dev/null; inner="$(hc__git rev-parse --git-dir 2>&1 || true)"; printf "caller=%s\ninner=%s\n" "${GIT_DIR:-unset}" "$inner"' _ "$ROOT/scripts/helix_code/helix_code_home.sh")"
if printf '%s\n' "$out" | grep -qxF "caller=$sen/.git"; then ok "B2: sourcing helix_code_home.sh keeps the caller's GIT_DIR"; else ko "B2: the caller's GIT_DIR was changed by sourcing: $out"; fi
if printf '%s\n' "$out" | grep -qxF "inner=.git"; then ok "B2: hc__git answers its own cwd repository, not the caller's GIT_DIR"; else ko "B2: hc__git did not answer '.git' (an unscrubbed call answers the sentinel): $out"; fi
if [ "$(fingerprint "$sen")" = "$f0" ]; then ok "B2: sentinel unchanged"; else ko "B2: the sentinel was written"; fi
# B2b: hc__git called in the CURRENT shell (not inside $(...), which is already a subshell): the wrapper's own
# subshell is what keeps the caller's variables, so this kills a wrapper that drops it (review M6).
out="$(cd "$plain" && GIT_DIR="$sen/.git" bash -c 'set +u; . "$1" 2>/dev/null; hc__git -C "$2" rev-parse --git-dir >/dev/null 2>&1; printf "caller=%s\n" "${GIT_DIR:-unset}"' _ "$ROOT/scripts/helix_code/helix_code_home.sh" "$plain")"
if printf '%s\n' "$out" | grep -qxF "caller=$sen/.git"; then ok "B2b: a direct hc__git call keeps the caller's GIT_DIR"; else ko "B2b: a direct hc__git call cleared the caller's GIT_DIR: $out"; fi

# ---- B3 the round-3 writers (review R3-1) ------------------------------------------------------
# member compares each mode's exit with <want>; the verdict without the variable is measured first, so a test
# that already fails without it (a pre-existing failure) is compared with itself, never assumed to be 0.
b3_member() { # <label> <script> [args]
    local label="$1" script="$2" rc0=0; shift 2
    ( cd "$ROOT" && bash "$script" "$@" ) >"$T/${label}_base.log" 2>&1 || rc0=$?
    member "$label" "$rc0" "git_dir both" "$script" "$@"
}
b3_member B3_seam scripts/gates/cm_rule_binds_to_seam.sh --selftest
b3_member B3_seam_mut scripts/gates/cm_rule_binds_to_seam_mutation_test.sh
b3_member B3_gitlink_mut scripts/gates/cm_gitlink_on_remote_mutation_test.sh
b3_member B3_helixdeps_mut scripts/gates/cm_helix_deps_ref_matches_gitlink_mutation_test.sh

# ---- B4 round 4 (review of 104bc231) -----------------------------------------------------------------------
# install_upstreams.sh configures remotes of the repository it lives in, so it runs from a copy inside a
# throwaway repository (never this checkout); no remote is contacted.
for mode in none git_dir both; do
    iu="$T/iu_$mode"; mkdir -p "$iu" || setup_bug "mkdir iu"
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q --template= "$iu" || setup_bug "init iu"
    cp "$ROOT/install_upstreams.sh" "$iu/" && cp -r "$ROOT/upstreams" "$iu/" || setup_bug "copy iu"
    sen="$T/sen_iu_$mode"; mksen "$sen"; f0="$(fingerprint "$sen")"
    case "$mode" in none) env_=() ;; git_dir) env_=(GIT_DIR="$sen/.git") ;; both) env_=(GIT_DIR="$sen/.git" GIT_INDEX_FILE="$sen/.git/index") ;; esac
    rc=0; ( cd "$iu" && env "${env_[@]}" GIT_CONFIG_GLOBAL=/dev/null timeout 120 bash ./install_upstreams.sh ) </dev/null >"$T/iu_$mode.log" 2>&1 || rc=$?
    nrem="$(git -C "$iu" remote | wc -l)"
    if [ "$rc" = 0 ] && [ "$nrem" -ge 2 ]; then ok "B4_install_upstreams [$mode]: exit 0, $nrem remotes in its own repository"
    else ko "B4_install_upstreams [$mode]: exit $rc, $nrem remotes in its own repository: $(tail -n 2 "$T/iu_$mode.log" | tr '\n' ' ')"; fi
    if [ "$(fingerprint "$sen")" = "$f0" ]; then ok "B4_install_upstreams [$mode]: sentinel unchanged"; else ko "B4_install_upstreams [$mode]: the sentinel repository was written"; fi
done
# progressive/mutation_matrix.py make_sandbox: importing the module runs its scrub; its git init/add/commit
# must land in the sandbox. The consumer pin it reads last is absent in this repository (FileNotFoundError
# after the git steps), which is expected here.
for mode in git_dir both; do
    sen="$T/sen_mm_$mode"; mksen "$sen"; f0="$(fingerprint "$sen")"
    case "$mode" in git_dir) env_=(GIT_DIR="$sen/.git") ;; both) env_=(GIT_DIR="$sen/.git" GIT_INDEX_FILE="$sen/.git/index") ;; esac
    mkdir -p "$T/mm_$mode" || setup_bug "mkdir mm"
    rc=0; ( cd "$ROOT" && env "${env_[@]}" GIT_CONFIG_GLOBAL=/dev/null python3 -c '
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1] + "/progressive")
import mutation_matrix as mm
mm.ROOT = Path(sys.argv[1])
try:
    mm.make_sandbox(Path(sys.argv[2]))
except FileNotFoundError:
    pass
' "$ROOT" "$T/mm_$mode" ) >"$T/mm_$mode.log" 2>&1 || rc=$?
    if [ "$rc" = 0 ] && git -C "$T/mm_$mode/consumer/constitution" rev-parse --verify -q HEAD >/dev/null; then ok "B4_mutation_matrix [$mode]: the sandbox got its own commit"
    else ko "B4_mutation_matrix [$mode]: exit $rc, no commit in the sandbox: $(tail -n 2 "$T/mm_$mode.log" | tr '\n' ' ')"; fi
    if [ "$(fingerprint "$sen")" = "$f0" ]; then ok "B4_mutation_matrix [$mode]: sentinel unchanged"; else ko "B4_mutation_matrix [$mode]: the sentinel repository was written"; fi
done
member B4_device_lock_help 0 "git_dir" scripts/multitrack/multitrack_device_lock.sh --help
# R4-7: the guards follow the caller's repository. The label guard is copied alone into a temp dir so its
# sibling labeler is unreachable and its own git fallback answers; under GIT_DIR it must name the GIT_DIR
# repository's branch ("sentinel"), not the cwd repository's.
sen="$T/sen_guard"; mksen "$sen"
plain="$T/plain_guard"; GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q -b plainb --template= "$plain" || setup_bug "init plain_guard"
mkdir -p "$T/guard_copy" && cp "$ROOT/scripts/hooks/guard-track-branch-label.sh" "$T/guard_copy/" || setup_bug "copy guard"
out="$( cd "$plain" && printf '%s' '{"tool_name":"Agent","tool_input":{"description":"no label","prompt":"x"}}' | GIT_DIR="$sen/.git" bash "$T/guard_copy/guard-track-branch-label.sh" 2>&1 )"
if printf '%s\n' "$out" | grep -qF "(T?/sentinel - "; then ok "B4_guard_label: under GIT_DIR the guard names the GIT_DIR repository's branch (subject follows the caller)"
else ko "B4_guard_label: the guard did not name the GIT_DIR repository's branch: $(printf '%s' "$out" | grep -m1 'Correct prefix')"; fi
# the binding guard's `git status` must not rewrite the caller-selected repository's index (optional lock).
# Needle first: a plain `git status` under the same variables on a stale index DOES rewrite it.
touch -d '2001-01-01 00:00' "$sen/s"; f0="$(fingerprint "$sen")"
( cd "$plain" && GIT_DIR="$sen/.git" GIT_WORK_TREE="$sen" GIT_CONFIG_GLOBAL=/dev/null git status --porcelain ) >/dev/null 2>&1
if [ "$(fingerprint "$sen")" != "$f0" ]; then ok "B4_guard_status needle: a plain git status rewrites a stale index"
else ko "B4_guard_status needle: a plain git status did not rewrite the stale index, so the case below proves nothing"; fi
touch -d '2002-01-01 00:00' "$sen/s"; f0="$(fingerprint "$sen")"
( cd "$plain" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -a -m x"}}' | GIT_DIR="$sen/.git" GIT_WORK_TREE="$sen" GIT_CONFIG_GLOBAL=/dev/null bash "$ROOT/scripts/hooks/guard-work-track-binding.sh" ) >"$T/guard_wtb.log" 2>&1
if [ "$(fingerprint "$sen")" = "$f0" ]; then ok "B4_guard_status: the binding guard left the caller's repository unchanged (no optional lock)"
else ko "B4_guard_status: the binding guard rewrote the caller's repository index"; fi

# ---- K discovery limits are the caller's: GIT_CEILING_DIRECTORIES must survive every scrub (round 2, F1) ---
# The repository-locating variables REDIRECT git; GIT_CEILING_DIRECTORIES only LIMITS discovery (git(1): "a list
# of directories that Git should not chdir up into while looking for a repository"). A caller that fences a
# directory off (tests/install/lib.sh, cm_installer_truncation_safe.sh) must keep that fence.
REDIRECT_14="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX"
if [ "$CANON" = "$REDIRECT_14" ]; then ok "K0: CL_GIT_SCRUB_VARS is the 14 redirecting names (literal list in this test), no discovery limit"
else ko "K0: CL_GIT_SCRUB_VARS differs from the literal 14-name list: '$CANON'"; fi
# K1: the installer, run from a non-repository directory fenced by the caller's ceiling inside an enclosing
# repository, must refuse ("not a git repository") and never plan an install into the enclosing repository.
# --upstream-url names a local path that does not exist, so nothing reaches the network.
encl="$T/encl_k1"; mksen "$encl"; mkdir -p "$encl/tmp/run"; f0="$(fingerprint "$encl")"
rc=0; ( cd "$encl/tmp/run" && GIT_CEILING_DIRECTORIES="$encl/tmp" timeout 120 bash "$ROOT/scripts/install_constitution.sh" \
    --dry-run --non-interactive --agent none --upstream-url "$T/no_such_upstream.git" ) >"$T/k1.log" 2>&1 || rc=$?
if grep -q "is not a git repository" "$T/k1.log" && ! grep -q "^project:" "$T/k1.log" && [ "$rc" = 3 ]; then
    ok "K1: installer honours the caller's GIT_CEILING_DIRECTORIES (refuses, exit 3, no plan for the enclosing repository)"
else ko "K1: installer ignored the caller's ceiling (exit $rc): $(grep -m2 -E '^project:|not a git|ERROR' "$T/k1.log" | tr '\n' ' ')"; fi
if [ "$(fingerprint "$encl")" = "$f0" ]; then ok "K1: enclosing repository unchanged"; else ko "K1: the enclosing repository was written"; fi
# K2: sourcing the installer in lib mode (tests/install/*, two gates) keeps the caller shell's ceiling.
out="$(GIT_CEILING_DIRECTORIES=/x/ceil GIT_DIR=/x/gd bash -c 'HELIX_INSTALLER_LIB_MODE=1 . "$1" >/dev/null 2>&1; printf "C=%s D=%s" "${GIT_CEILING_DIRECTORIES-UNSET}" "${GIT_DIR-UNSET}"' _ "$ROOT/scripts/install_constitution.sh")"
if [ "$out" = "C=/x/ceil D=UNSET" ]; then ok "K2: lib-mode sourcing keeps GIT_CEILING_DIRECTORIES and clears GIT_DIR ($out)"
else ko "K2: lib-mode sourcing: want 'C=/x/ceil D=UNSET', got '$out'"; fi
# K3: the library scrub keeps the ceiling and drops every redirecting name.
out="$(env GIT_CEILING_DIRECTORIES=/x/ceil $(for v in $REDIRECT_14; do printf '%s=/x/v ' "$v"; done) bash -c '. "$1"; cl_scrub_git_env quiet; for v in GIT_CEILING_DIRECTORIES '"$REDIRECT_14"'; do eval "printf \"%s=%s \" \"\$v\" \"\${$v-UNSET}\""; done' _ "$LIB")"
want="GIT_CEILING_DIRECTORIES=/x/ceil $(for v in $REDIRECT_14; do printf '%s=UNSET ' "$v"; done)"
if [ "$out" = "$want" ]; then ok "K3: cl_scrub_git_env keeps the ceiling and drops all 14 redirecting names"
else ko "K3: cl_scrub_git_env: want '$want', got '$out'"; fi
# K4: every scrub line of the canonical form in a tracked file (shell and python, whole tree) is RUN with
# the ceiling and all 14 names set: each must keep the ceiling and clear all 14. A file count needle first.
python3 -I - "$ROOT" "$REDIRECT_14" >"$T/k4.log" 2>&1 <<'PY'
import os, re, subprocess, sys
root, names = sys.argv[1], sys.argv[2].split()
SH = re.compile(r'^\s*for _ge_v in [A-Z_ ]+; do unset "\$_ge_v"; done; unset _ge_v\b.*$', re.M)
PY = re.compile(r'^for _ge_v in "[A-Z_ ]+"\.split\(\):\s*_ge_os\.environ\.pop\(_ge_v, None\).*$', re.M)
env0 = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
env0.update({n: "/x/v" for n in names}); env0["GIT_CEILING_DIRECTORIES"] = "/x/ceil"
clean = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
files = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, env=clean).stdout.decode().split("\0")
nsh = npy = bad = 0
seen = {}
for f in files:
    p = os.path.join(root, f)
    if not f or os.path.islink(p) or not os.path.isfile(p):
        continue
    try:
        t = open(p, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    for m in SH.finditer(t):
        nsh += 1
        line = m.group(0).strip()
        r = seen.get(line)
        if r is None:
            probe = line + '\nfor v in GIT_CEILING_DIRECTORIES %s; do eval "printf \\"%%s=%%s \\" \\"\\$v\\" \\"\\${$v-UNSET}\\""; done' % " ".join(names)
            r = seen[line] = subprocess.run(["bash", "-c", probe], capture_output=True, text=True, env=env0).stdout
        if r != "GIT_CEILING_DIRECTORIES=/x/ceil " + "".join("%s=UNSET " % n for n in names):
            bad += 1; print("BAD sh", f, r[:200])
    for m in PY.finditer(t):
        npy += 1
        line = m.group(0).strip()
        r = seen.get(line)
        if r is None:
            probe = "import os as _ge_os\n" + line + "\nimport os\nprint(' '.join('%s=%s' % (v, os.environ.get(v, 'UNSET')) for v in " + repr(["GIT_CEILING_DIRECTORIES"] + names) + "))"
            r = seen[line] = subprocess.run([sys.executable, "-I", "-c", probe], capture_output=True, text=True, env=env0).stdout.strip()
        if r != " ".join(["GIT_CEILING_DIRECTORIES=/x/ceil"] + ["%s=UNSET" % n for n in names]):
            bad += 1; print("BAD py", f, r[:200])
print("K4 sh=%d py=%d distinct=%d bad=%d" % (nsh, npy, len(seen), bad))
PY
k4="$(tail -n 1 "$T/k4.log")"
k4sh="$(printf '%s' "$k4" | sed -n 's/.* sh=\([0-9]*\) .*/\1/p')"; k4py="$(printf '%s' "$k4" | sed -n 's/.* py=\([0-9]*\) .*/\1/p')"
if printf '%s' "$k4" | grep -q ' bad=0$' && [ $(( ${k4sh:-0} + ${k4py:-0} )) -ge 100 ]; then ok "K4: every canonical scrub line keeps the ceiling and clears all 14 ($k4)"
else ko "K4: $k4 $(grep -m3 '^BAD' "$T/k4.log" | tr '\n' ' ')"; fi
# K5: tests/install/lib.sh's sandbox ceiling survives sourcing the installer in a sandboxed test shell.
out="$(bash -c 'cd "$2" && . tests/install/lib.sh >/dev/null 2>&1 && new_sandbox >/dev/null 2>&1; c1="$GIT_CEILING_DIRECTORIES"; HELIX_INSTALLER_LIB_MODE=1 . "$1" >/dev/null 2>&1; [ -n "$c1" ] && [ "${GIT_CEILING_DIRECTORIES-UNSET}" = "$c1" ] && echo KEPT || echo "LOST c1=[$c1] now=[${GIT_CEILING_DIRECTORIES-UNSET}]"' _ "$ROOT/scripts/install_constitution.sh" "$ROOT")"
if [ "$out" = KEPT ]; then ok "K5: tests/install/lib.sh sandbox ceiling survives lib-mode sourcing of the installer"
else ko "K5: tests/install/lib.sh sandbox ceiling: $out"; fi

echo "[git-env-class] passed=$pass failed=$fail skipped=$skip"
[ "$fail" = 0 ] || exit 1
exit 0
