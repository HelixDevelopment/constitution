#!/usr/bin/env bash
# cm_pr_delivery_account_name_free_mutation_test.sh — paired §1.1 mutation test for CM-PR-DELIVERY-ACCOUNT-NAME-FREE
#
# Purpose
#   Proves cm_pr_delivery_account_name_free.sh genuinely discriminates. It copies the corpus files into a
#   scratch layout <tmp>/consumer/constitution next to a FIXTURE consumer configuration
#   <tmp>/consumer/config/delivery.conf whose reviewer list holds two fixture accounts (no real account name
#   is stored in this file) and runs the gate:
#     * GREEN control    the unmodified copy with the fixture consumer MUST pass (exit 0);
#     * golden-FALSE     a longer account name that contains a fixture account, a fixture account written
#                        into a file outside the corpus, a NUL byte in a file outside the corpus, an empty
#                        assignee list, a changed file outside the corpus without --changed-since and a
#                        number (a serial of 0s and 1s) under an account of the letters l and o and a rule
#                        of bars under an account of the letter l (audit 3, B2) MUST still pass (§11.4.201(1));
#     * RED              a fixture account written into each corpus file class (the canon block, each of
#                        the four mirrors, the group file, the progressive rule file, the index, the rules
#                        manifest, the changelog, the readme, the owed-gates page, the three registries, each
#                        pull-request and release-gate file, the generated propagation gates, the hub test,
#                        the post-update hook, the suite manifest, the anchor library and its test, a guide),
#                        a case variant, each disguise the normaliser undoes (Cyrillic and Greek look-alike
#                        letters, the Cyrillic and Greek set of audit 2 written all at once in lower and in
#                        upper case, a Cyrillic io, a lunate sigma, a zero-width space, a soft hyphen, a
#                        Hangul filler, a halfwidth Hangul filler, a Braille blank, full-width letters, a
#                        combining mark, non-breaking hyphens), each disguise the skeleton form undoes (a
#                        Cyrillic letter for l, Cyrillic letters for the digits, an upper-case name with a
#                        Cyrillic letter for L, a vertical bar for 1, a long s for f, a 1 for i and a 0
#                        for o inside a name, digits after a hyphen in a name) and a sign that
#                        decomposes into letters, an assignee account,
#                        an account given only by --forbid-login, a file named by --changed-since (changed,
#                        untracked, committed after the base) and an @-mention in a mirror block MUST exit 1
#                        and name the file;
#     * SKIP / BLIND     no consumer data MUST exit 3 (never 0); a configuration without the reviewer key,
#                        an empty reviewer list (bare, or with a comment only), a malformed reviewer or
#                        assignee value, a missing configuration file, a corpus file with a NUL byte (also
#                        one that hides a fixture account after the NUL) and an unresolvable --changed-since
#                        MUST exit 2; equal reviewer and assignee keys exit 64;
#     * CON-PENDINGprgate          a constitution that is its own consumer: a root-level <root>/config/delivery.conf
#                        (with the extra keys decision_id, decision_date, pr_repository, own_repositories) is
#                        read by default and its accounts are scanned; under --changed-since that file is left
#                        out by its resolved path (another file next to it, and a root-level file that was not
#                        read, are still scanned); a changed SQLite database is left out and named in the PASS,
#                        while another changed binary file and a changed fixed-corpus file stay BLIND;
#     * REAL consumer    when a consumer configuration exists for this constitution
#                        (<root>/../config/delivery.conf, else <root>/config/delivery.conf, or
#                        PR_DELIVERY_REAL_CONSUMER_CONFIG), the gate
#                        MUST pass on the real tree with it, and each account read from it AT RUN TIME,
#                        written into a copy of the canon block, MUST exit 1; without such a file this leg is
#                        reported SKIP;
#     * gate mutants     edits of a copy of the gate (the matcher, the case rule, each normaliser step, the
#                        table before and after NFKD, the table rows added by audit 2, the fillers, each
#                        skeleton step, the digits or the bars read as letters in every word, the digits in
#                        none, the bar or the hyphen left
#                        out of a word, each of the three scans, the NUL report and its verdict, SKIP
#                        reported as PASS, present-means-mandatory removed, an empty reviewer list accepted
#                        or not detected, an empty assignee list refused, the assignee list ignored or its
#                        malformed value accepted, --changed-since ignored, a corpus file, file pattern or
#                        guide directory dropped, the scan skipped, and for CON-PENDINGprgate: either default location
#                        dropped, extra keys read as accounts, the configuration exclusion removed or widened to
#                        a directory or a file name, the SQLite skip removed or widened to every changed file,
#                        the skipped database not named in the PASS) MUST each
#                        be killed by a scenario above.
#   Each mutation operator asserts it really changed the file; a no-op mutation is a test bug (exit 2).
#
# Usage
#   cm_pr_delivery_account_name_free_mutation_test.sh [--quiet]
#
# Exit codes
#   0  every case and every mutant behaved as required
#   1  a case misbehaved or a mutant survived
#   2  setup failure
#
# Dependencies: bash, python3, awk, grep, cp, mktemp, git. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GATE="$HERE/cm_pr_delivery_account_name_free.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
for _t in python3 awk grep cp mktemp git; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[mutation:account-name] required tool '$_t' missing" >&2; exit 2; }
done
[ -f "$GATE" ] || { echo "[mutation:account-name] SETUP FAILURE: gate missing: $GATE" >&2; exit 2; }

TMPD="$(mktemp -d)" || exit 2
trap 'rm -rf "${TMPD:?}"' EXIT
BASE="$TMPD/base"; L="$TMPD/layout"; C="$L/consumer/constitution"; PY="$TMPD/op.py"
RESULT=0; NOK=0; NKILL=0; NMUT=0
say() { printf '[mutation:account-name] %s\n' "$*"; }
qsay() { [ "$QUIET" = 1 ] || say "$@"; }
F1="fixture-rev-one"; F2="fixtwo"; F3="fixloc10"; F4="kmtnrvw-ejyx36"

FILES=(Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md README.md CHANGELOG.md constitution_index.yaml
       progressive/catalog.json progressive/rules_manifest.json progressive/rules/11.4.297.md groups/git-and-data-safety.md
       docs/owed_gate_implementations.md scripts/gates/gate_ledger_deferrals.tsv
       scripts/gates/covenant_propagation_anchors.tsv scripts/gates/rule_seam_bindings.tsv
       scripts/gates/cm_pr_delivery_anchor_wired.sh scripts/gates/cm_pr_delivery_account_name_free.sh
       scripts/gates/cm_release_gate_anchor_wired.sh scripts/gates/cm_release_gate_anchor_wired_mutation_test.sh
       scripts/gates/cm_covenant_114_297_propagation.sh scripts/gates/cm_covenant_114_298_propagation_mutation_test.sh
       tests/test_post_update_hub_gates.sh scripts/post_update_hook.sh config/full_suite_manifest.tsv
       scripts/anchors/anchor_lib.py scripts/anchors/tests/test_query_us2.py docs/guides/full_suite_runner_guide.md)
mkdir -p "$BASE/consumer/constitution" "$BASE/consumer/config"
for f in "${FILES[@]}"; do
    [ -f "$ROOT/$f" ] || { say "SETUP FAILURE: input missing: $f"; exit 2; }
    (cd "$ROOT" && cp --parents "$f" "$BASE/consumer/constitution/") || { say "SETUP FAILURE: copy failed: $f"; exit 2; }
done
mkdir -p "$BASE/consumer/constitution/docs/research"
printf '%s\n' 'A research note outside the rule corpus.' >"$BASE/consumer/constitution/docs/research/note.md"
printf '%s\n' '# fixture consumer configuration' 'mode=pr' "pr_reviewers=$F1,$F2" >"$BASE/consumer/config/delivery.conf"

# op sub FILE OLD NEW | op subesc FILE OLD NEW-with-\uXXXX-escapes | op append FILE TEXT
cat >"$PY" <<'PYEOF'
import sys
op, path = sys.argv[1], sys.argv[2]
raw = open(path, encoding='utf-8').read()
if op in ('sub', 'subesc'):
    old, new = sys.argv[3], sys.argv[4]
    if op == 'subesc':
        new = new.encode('ascii').decode('unicode_escape')
    if old not in raw:
        sys.stderr.write('NOOP: %r not in %s\n' % (old, path)); sys.exit(3)
    out = raw.replace(old, new, 1)
elif op == 'append':
    out = raw.rstrip('\n') + '\n' + sys.argv[3] + '\n'
else:
    sys.stderr.write('unknown op\n'); sys.exit(2)
if out == raw:
    sys.stderr.write('NOOP\n'); sys.exit(3)
open(path, 'w', encoding='utf-8').write(out)
PYEOF
op() { python3 -I "$PY" "$@" || { say "SETUP FAILURE: operator '$1 $2' failed (a no-op mutation is a test bug)"; exit 2; }; }
fresh() { rm -rf "${L:?}"; cp -a "$BASE" "$L" || { say "SETUP FAILURE: scratch copy failed"; exit 2; }; }
G="$GATE"
# RUNROOT and RUNCWD let a case pass a symlinked root or run from the scratch root (a relative --consumer-config)
run() { (cd "${RUNCWD:-.}" && bash "$G" --root "${RUNROOT:-$C}" "$@" 2>&1); }
# a git history in the scratch constitution, isolated from the caller's git configuration
fgit() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$C" -c user.name=fixture -c user.email=fixture@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
gitfresh() {
    fresh
    if ! { fgit init -q && fgit add -A && fgit commit -q -m base; }; then say "SETUP FAILURE: scratch git history"; exit 2; fi
}

# expect <label> <rc> <regex-in-output> [gate args...]
expect() {
    local label="$1" want="$2" rx="$3" out rc; shift 3
    out="$(run "$@")"; rc=$?
    if [ "$rc" -ne "$want" ]; then say "CASE FAILED [$label]: exit $rc, expected $want"; printf '%s\n' "$out" | tail -n 4; RESULT=1; return; fi
    if ! grep -E -q -- "$rx" <<<"$out"; then say "CASE FAILED [$label]: exit $rc but output lacks /$rx/"; RESULT=1; return; fi
    NOK=$((NOK + 1)); qsay "ok: $label (exit $rc)"
}
# outcome [gate args...] -> the exit status of one run of $G on the current scratch layout (used for the gate mutants)
outcome() { run "$@" >/dev/null 2>&1; echo $?; }

CANON_SPOT='(5) The same rule binds the pull requests a submodule cascade opens'
MIRROR_SPOT='(D) Reviewers are a configured list'
INDEX_SPOT='Pull-request delivery: a project that declares it by a recorded operator'
canon_with() { op "${2:-sub}" "$C/Constitution.md" "$CANON_SPOT" "(5) Ask $1 first. The same rule binds the pull requests a submodule cascade opens"; }

# ── GREEN control, golden-FALSE ──────────────────────────────────────────────
fresh; expect "GREEN control: fixture consumer, clean corpus" 0 'PASS — .*2 declared account'
fresh; op sub "$C/Constitution.md" "$CANON_SPOT" "(5) A reviewer named x$F1 or ${F1}x is another account. The same rule binds the pull requests a submodule cascade opens"
expect "golden-FALSE: longer account names that contain a fixture account" 0 'PASS'
fresh; op append "$C/docs/research/note.md" "This note names $F1 outside the rule corpus."
expect "golden-FALSE: a fixture account in a file outside the corpus" 0 'PASS'

# ── RED: one corpus file class at a time ─────────────────────────────────────
fresh; canon_with "$F1"
expect "RED: fixture account in the canon block" 1 "appears in Constitution.md:"
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    fresh; op sub "$C/$f" "$MIRROR_SPOT" "(D) Reviewers ($F2) are a configured list"
    expect "RED: fixture account in mirror $f" 1 "appears in $f:"
done
fresh; op sub "$C/groups/git-and-data-safety.md" "$CANON_SPOT" "(5) Ask $F1 first. The same rule binds the pull requests a submodule cascade opens"
expect "RED: fixture account in the group file" 1 "appears in groups/git-and-data-safety.md:"
fresh; op sub "$C/progressive/rules/11.4.297.md" "$CANON_SPOT" "(5) Ask $F1 first. The same rule binds the pull requests a submodule cascade opens"
expect "RED: fixture account in the progressive rule file" 1 "appears in progressive/rules/11.4.297.md:"
fresh; op sub "$C/constitution_index.yaml" "$INDEX_SPOT" "Pull-request delivery: $F2 a project that declares it by a recorded operator"
expect "RED: fixture account in the index" 1 "appears in constitution_index.yaml:"
for f in CHANGELOG.md README.md progressive/rules_manifest.json docs/owed_gate_implementations.md \
         scripts/gates/gate_ledger_deferrals.tsv scripts/gates/covenant_propagation_anchors.tsv scripts/gates/rule_seam_bindings.tsv \
         scripts/gates/cm_pr_delivery_anchor_wired.sh scripts/gates/cm_release_gate_anchor_wired.sh \
         scripts/gates/cm_release_gate_anchor_wired_mutation_test.sh scripts/gates/cm_covenant_114_297_propagation.sh \
         scripts/gates/cm_covenant_114_298_propagation_mutation_test.sh tests/test_post_update_hub_gates.sh \
         scripts/post_update_hook.sh config/full_suite_manifest.tsv scripts/anchors/anchor_lib.py scripts/anchors/tests/test_query_us2.py; do
    fresh; op append "$C/$f" "# reviewer $F1"
    expect "RED: fixture account in $f" 1 "appears in $f:"
done
fresh; op append "$C/docs/guides/full_suite_runner_guide.md" "reviewer @$F2"
expect "RED: fixture account as an @-mention in a guide" 1 "appears in docs/guides/full_suite_runner_guide.md:"
UPPER="$(printf '%s' "$F1" | tr '[:lower:]' '[:upper:]')"
fresh; canon_with "$UPPER"
expect "RED: a case variant of a fixture account" 1 "appears in Constitution.md:"

# ── RED: the disguises the normaliser undoes, and a sign the raw scan sees ───
for d in 'Cyrillic look-alike letters|fixtur\u0435-r\u0435v-\u043ene' 'a Greek look-alike letter|fixtw\u03bf' \
         'a zero-width space|fix\u200bture-rev-one' 'a soft hyphen|fixt\u00adure-rev-one' \
         'full-width letters|\uff46\uff49\uff58\uff54\uff57\uff4f' 'a combining mark|fi\u0301xtwo' \
         'non-breaking hyphens|fixture\u2011rev\u2011one' 'a trademark sign after the name|fixtwo\u2122'; do
    fresh; canon_with "${d#*|}" subesc
    expect "RED: a fixture account disguised by ${d%%|*}" 1 "appears in Constitution.md:"
done
# audit 2: the Cyrillic and Greek letters it found missed, the fillers, and the skeleton disguises (fixture
# accounts given by --forbid-login, so the fixture consumer stays unchanged)
for d in 'the audit-2 Cyrillic and Greek set in lower case|\u043a\u043c\u0442\u043f\u0433\u0475\u0461-\u04bd\u03f3\u03b3\u03c7\u0437\u0431' \
         'the audit-2 Cyrillic set with capital letters|kmtnrvw-ejyx\u04176' \
         'a Cyrillic io|fixtur\u0451-rev-one' 'a Hangul filler|fix\u3164two' 'a halfwidth Hangul filler|fixt\uffa0wo' \
         'a Hangul choseong filler|fi\u115fxtwo' 'a Hangul jungseong filler|fixtw\u1160o' 'a Braille blank|fixt\u2800wo' \
         'a lunate sigma for c|fixlo\u03f210' 'a long s for f|\u017fixloc10' 'a Cyrillic letter for l|fix\u0406oc10' \
         'a Cyrillic palochka for l|fix\u04c0oc10' 'Cyrillic letters for the digits|fixloc\u04cf\u041e' \
         'an upper-case name with a Cyrillic letter for L|FIX\u0406OC10' 'a vertical bar for 1|fixloc|0' \
         'a Latin capital I for l|fixIoc10'; do
    fresh; canon_with "${d#*|}" subesc
    expect "RED: a fixture account disguised by ${d%%|*}" 1 "appears in Constitution.md:" --forbid-login "$F3" --forbid-login "$F4"
done
# audit 3 (B2): a 0 or a 1 is a letter only inside a word that holds a letter, so a digit inside a name is seen and a
# number is not read as an account
fresh; canon_with 'f1xtw0'
expect "RED: a fixture account disguised by a 1 for i and a 0 for o inside the name" 1 "appears in Constitution.md:"
fresh; canon_with 'fix-10'
expect "RED: a hyphenated account whose last part is disguised by digits (the hyphen joins the word)" 1 "appears in Constitution.md:" --forbid-login fix-lo
# (the accounts below appear in no corpus file of the scratch copy, which does not hold this file; the gate's needle
# accounts are in the gate source, which it does hold; on the real tree both files are in the corpus, so these accounts
# hit there, as the fixture accounts do)
fresh; canon_with '1001-011'
expect "golden-FALSE: a serial of 0s and 1s is not read as an account of the letters l and o" 0 'PASS' --forbid-login lool-oll
fresh; canon_with '|||-||'
expect "golden-FALSE: a rule of bars is not read as an account of the letter l" 0 'PASS' --forbid-login lll-ll

# ── assignees, --forbid-login, structure ─────────────────────────────────────
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" 'pr_assignees=fixture-asg' >"$L/consumer/config/delivery.conf"; canon_with fixture-asg
expect "RED: an assignee account in the canon block" 1 "appears in Constitution.md:"
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" 'owners=fixture-own' >"$L/consumer/config/delivery.conf"; canon_with fixture-own
expect "RED: an assignee key declared with --assignees-key" 1 "appears in Constitution.md:" --assignees-key owners
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" 'pr_assignees=org/team' >"$L/consumer/config/delivery.conf"
expect "BLIND: a malformed assignee value" 2 "BLIND — .*the 'pr_assignees' value is not a list of account names"
fresh; expect "usage: equal reviewer and assignee keys" 64 'must differ' --assignees-key pr_reviewers
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" 'pr_assignees=' >"$L/consumer/config/delivery.conf"
expect "golden-FALSE: an empty assignee list is not an error" 0 'PASS — .*1 reviewer and 0 assignee entries'
fresh; rm -f "$L/consumer/config/delivery.conf"; op append "$C/CHANGELOG.md" "named fixture-extra here"
expect "RED: an account given only by --forbid-login" 1 "appears in CHANGELOG.md:" --forbid-login fixture-extra
fresh; op sub "$C/AGENTS.md" "$MIRROR_SPOT" "(D) Reviewers (ask @some-other-account) are a configured list"
expect "RED: an @-mention in a mirror block" 1 "structure: mirror AGENTS.md .*@-mention"

# ── --changed-since ──────────────────────────────────────────────────────────
gitfresh; op append "$C/docs/research/note.md" "This note names $F1."
expect "golden-FALSE: a changed file outside the corpus without --changed-since" 0 'PASS'
expect "RED: a changed file named by --changed-since" 1 "appears in docs/research/note.md:" --changed-since HEAD
gitfresh; printf '%s\n' "names $F2" >"$C/docs/research/new.md"
expect "RED: an untracked file named by --changed-since" 1 "appears in docs/research/new.md:" --changed-since HEAD
gitfresh; op append "$C/docs/research/note.md" "This note names $F2."; fgit commit -q -a -m second || { say "SETUP FAILURE: second commit"; exit 2; }
expect "RED: a file committed after the base named by --changed-since" 1 "appears in docs/research/note.md:" --changed-since HEAD~1
gitfresh; expect "BLIND: an unresolvable --changed-since" 2 "BLIND — --changed-since: 'no-such-rev' is not a commit" --changed-since no-such-rev

# ── CON-PENDINGprgate: a constitution that is its own consumer (root-level config/delivery.conf) ──
# self_consumer: the consumer-level configuration is removed and the fixture reviewers are declared at
# <root>/config/delivery.conf instead, with the extra keys a real declaration carries (CON-423 decision (4))
self_consumer() {
    rm -f "$L/consumer/config/delivery.conf"
    printf '%s\n' '# fixture root-level declaration' 'decision_id=FIXTURE-1' 'decision_date=2026-11-16' 'mode=pr' \
        'pr_repository=FixtureOrg/fixture-repo' "pr_reviewers=$F1,$F2" 'pr_assignees=fixture-asg' \
        'own_repositories=.:FixtureOrg/fixture-repo:pr,submodules/x:FixtureOrg/x:pr' >"$C/config/delivery.conf"
}
mkdb() { python3 -I -c 'import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("create table t(x text)"); c.execute("insert into t values (?)", (sys.argv[2],)); c.commit()' "$1" "$2" \
    || { say "SETUP FAILURE: fixture SQLite database"; exit 2; }; }
fresh; self_consumer
expect "PASS: a root-level config/delivery.conf is read by default, the extra keys parse" 0 'PASS — .*3 declared account.*2 reviewer and 1 assignee entries'
fresh; self_consumer; canon_with "$F2"
expect "RED: an account of the root-level configuration in the canon block" 1 "appears in Constitution.md:"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }
op append "$C/config/delivery.conf" "# edited after the base: reviewer $F1 kept"
expect "golden-FALSE: the declared configuration is excluded from --changed-since by path" 0 'excluded from --changed-since: config/delivery.conf' --changed-since HEAD
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }
printf '%s\n' "other=$F1" >"$C/config/other.conf"
expect "RED: another file next to the declared configuration is still scanned under --changed-since" 1 "appears in config/other.conf:" --changed-since HEAD
gitfresh; cp "$L/consumer/config/delivery.conf" "$C/config/delivery.conf"
expect "RED: a root-level configuration that was not read (an explicit --consumer-config) is scanned like any file" 1 "appears in config/delivery.conf:" --changed-since HEAD --consumer-config "$L/consumer/config/delivery.conf"
# round 3 (B1): this case used to require a PASS for a database that HOLDS a fixture account (the database was left
# unscanned); it now requires the account to be found in its text cells, and a clean database to pass and be named
gitfresh; mkdb "$C/docs/workable_items.db" "$F1"
expect "RED: a changed SQLite database holding an account is scanned through its text cells" 1 'appears in docs/workable_items.db \(SQLite text cells\):' --changed-since HEAD
gitfresh; mkdb "$C/docs/workable_items.db" "no account here"
expect "golden-FALSE: a clean changed SQLite database passes, and the PASS names it" 0 'PASS — .*1 SQLite database file\(s\) scanned as their text cells:.*docs/workable_items.db' --changed-since HEAD
gitfresh; printf 'bin\000ary\n' >"$C/docs/research/blob.bin"
expect "BLIND: a changed binary file that is not an SQLite database stays BLIND" 2 'BLIND — 1 corpus file\(s\) hold a NUL byte.*docs/research/blob.bin' --changed-since HEAD
gitfresh; printf 'SQLite format 3\000 reviewer %s\n' "$F1" >"$C/CHANGELOG.md"
expect "BLIND: a changed file of the fixed corpus is never skipped as an SQLite database" 2 'BLIND — 1 corpus file\(s\) hold a NUL byte.*CHANGELOG.md' --changed-since HEAD

# ── round 3: SQLite by content, symlinks, path classes, the index, path names (B1, B2, F1, F2, F3) ──
# the reviewer's scenarios S_db, S_near, S_prefix, S_symchg, S_symroot, S_relconf, S_untracked, S_unstaged,
# S_explother (rev_prdeliv_r2 revmut.py) are the cases marked [S_...] below
mkblobdb() { python3 -I -c 'import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("create table t(x blob)"); c.execute("insert into t values (?)", (sys.argv[2].encode(),)); c.commit()' "$1" "$2" \
    || { say "SETUP FAILURE: fixture SQLite database"; exit 2; }; }
mknuldb() { python3 -I -c 'import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("create table t(x text)"); c.execute("insert into t values (?)", ("a\x00b clean",)); c.commit()' "$1" \
    || { say "SETUP FAILURE: fixture SQLite database"; exit 2; }; }
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }; mkdb "$C/docs/research/t.db" "reviewer $F1"
expect "RED [S_db]: a real SQLite database holding an account, next to an edited declared configuration" 1 'appears in docs/research/t.db \(SQLite text cells\):' --changed-since HEAD
gitfresh; mkblobdb "$C/docs/research/b.db" "blob names $F2"
expect "RED: an account in a BLOB cell of a changed SQLite database" 1 'appears in docs/research/b.db \(SQLite text cells\):' --changed-since HEAD
gitfresh; mknuldb "$C/docs/research/n.db"
expect "golden-FALSE: a NUL inside a text cell of a clean database does not make the gate BLIND" 0 'PASS — .*scanned as their text cells' --changed-since HEAD
gitfresh; printf 'SQLite format 3\000 a text file faking the header, reviewer %s\n' "$F1" >"$C/docs/research/fake.md"
expect "BLIND: a text file that starts with the SQLite header cannot be opened as a database" 2 'BLIND — docs/research/fake.md starts with the SQLite header but cannot be read as an SQLite database' --changed-since HEAD
gitfresh; printf 'SQLite format 3 near the header, reviewer %s\n' "$F1" >"$C/docs/research/near.md"
expect "RED [S_near]: a text file whose first bytes resemble the SQLite header is scanned as text" 1 'appears in docs/research/near.md:' --changed-since HEAD
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }; printf '%s\n' "$F1" >"$C/config/delivery.c"
expect "RED [S_prefix]: a changed path that is a prefix of the declared configuration path is scanned" 1 'appears in config/delivery.c:' --changed-since HEAD
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }
op append "$C/config/delivery.conf" "# edited"; ln -s ../../config/delivery.conf "$C/docs/research/l.md"
expect "RED [S_symchg]: a changed symbolic link to the declared configuration is never excluded" 1 'appears in docs/research/l.md -> config/delivery.conf:' --changed-since HEAD
gitfresh; ln -s "no-such-target/$F2" "$C/docs/research/dangling.md"
expect "RED: an account in the target text of a changed dangling symbolic link" 1 'appears in docs/research/dangling.md \(symbolic link target\):' --changed-since HEAD
gitfresh; printf '%s\n' "outside $F1" >"$L/outside.txt"; ln -s "$L/outside.txt" "$C/docs/research/out.md"
expect "BLIND: a changed symbolic link that points outside the root" 2 'BLIND — --changed-since: the changed symbolic link docs/research/out.md points outside the root' --changed-since HEAD
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }; op append "$C/config/delivery.conf" "# edited"; ln -s "$C" "$L/rlink"
RUNROOT="$L/rlink" expect "PASS [S_symroot]: a symlinked root still leaves exactly the declared configuration out" 0 'excluded from --changed-since: 1 consumer configuration file\(s\) read in this run: config/delivery.conf' --changed-since HEAD
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }; op append "$C/config/delivery.conf" "# edited"
RUNCWD="$C" expect "PASS [S_relconf]: a relative --consumer-config is resolved and its file is left out" 0 'excluded from --changed-since: 1 consumer configuration' --changed-since HEAD --consumer-config config/delivery.conf
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/u.md"
expect "RED [S_untracked]: an untracked file" 1 'appears in docs/research/u.md:' --changed-since HEAD
gitfresh; op append "$C/docs/research/note.md" "This note names $F1."
expect "RED [S_unstaged]: an unstaged change to a tracked file outside the fixed corpus" 1 'appears in docs/research/note.md:' --changed-since HEAD
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf || { say "SETUP FAILURE: commit conf"; exit 2; }; op append "$C/config/delivery.conf" "# edited"
printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$L/consumer/config/delivery.conf"
expect "RED [S_explother]: with an explicit --consumer-config the root-level configuration is not read and is scanned" 1 'appears in config/delivery.conf:' --changed-since HEAD --consumer-config "$L/consumer/config/delivery.conf"
fresh; rm -f "$L/consumer/config/delivery.conf"; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$C/docs/research/data.conf"; mkdir -p "$C/config"; ln -s ../docs/research/data.conf "$C/config/delivery.conf"
expect "BLIND: the declared configuration is a symbolic link (to a data file)" 2 'BLIND — consumer configuration .*config/delivery.conf is a symbolic link'
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" "prose $F2" >"$L/data.md"
expect "BLIND: a --consumer-config outside a directory named config" 2 'BLIND — consumer configuration .*data.md does not lie in a directory named config' --consumer-config "$L/data.md"
fresh; mkdir -p "$C/docs/research/config"; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$C/docs/research/config/x.conf"
expect "BLIND: a --consumer-config inside the root but not in <root>/config/" 2 'BLIND — consumer configuration .*lies inside the root but not in <root>/config/' --consumer-config "$C/docs/research/config/x.conf"
fresh; rm -f "$L/consumer/config/delivery.conf"; mkdir -p "$L/elsewhere/config" "$C/config"; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$L/elsewhere/config/delivery.conf"; ln -s "$L/elsewhere/config/delivery.conf" "$C/config/delivery.conf"
expect "BLIND: the declared configuration is a symbolic link (to a configuration elsewhere)" 2 'BLIND — consumer configuration .*is a symbolic link'
gitfresh; mkdir -p "$C/docs/research"; printf '%s\n' "$F1" >"$C/docs/research/ü.md"
expect "RED: a non-ASCII file name (F1)" 1 'appears in docs/research/ü.md:' --changed-since HEAD
gitfresh; printf '%s\n' clean >"$C/docs/research/ü2.md"; fgit add -A; fgit commit -q -m u2 || { say "SETUP FAILURE: commit"; exit 2; }; printf '%s\n' "$F1" >>"$C/docs/research/ü2.md"
expect "RED: a modified tracked file with a non-ASCII name (F1)" 1 'appears in docs/research/ü2.md:' --changed-since HEAD
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/a"$'\n'"b.md"
expect "RED: a file name with a newline (F1)" 1 'appears in docs/research/a\?b.md:' --changed-since HEAD
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/a"$'\t'"b.md"
expect "RED: a file name with a tab (F1)" 1 'appears in docs/research/a\?b.md:' --changed-since HEAD
gitfresh; printf '%s\n' clean >"$C/docs/research/$F2.md"
expect "RED: an account only in a changed path name (F3)" 1 'appears in \(names of the paths changed since HEAD\):' --changed-since HEAD
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/s.md"; fgit add docs/research/s.md; printf '%s\n' clean >"$C/docs/research/s.md"
expect "RED: an account in the staged version while the working tree was cleaned (F2)" 1 'appears in index:docs/research/s.md:' --changed-since HEAD
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/g.md"; fgit add docs/research/g.md; rm -f "$C/docs/research/g.md"
expect "RED: an account in a staged new file removed from the working tree (F2)" 1 'appears in index:docs/research/g.md:' --changed-since HEAD
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/locked.md"; chmod 000 "$C/docs/research/locked.md"
if [ -r "$C/docs/research/locked.md" ]; then qsay "skip: unreadable-file case (this user reads mode-000 files)"; chmod 644 "$C/docs/research/locked.md"
else expect "BLIND: a listed changed path that cannot be read (F1)" 2 'BLIND — --changed-since: the changed path docs/research/locked.md cannot be read' --changed-since HEAD; chmod 644 "$C/docs/research/locked.md"; fi
# R12: the parent default is taken from the logical root path, not the physical one
fresh; rm -f "$L/consumer/config/delivery.conf"; mkdir -p "$L/consumer2/config"; ln -s "$C" "$L/consumer2/constitution"
printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$L/consumer2/config/delivery.conf"
RUNROOT="$L/consumer2/constitution" expect "PASS: a root reached through a symlinked layout reads the logical parent's configuration" 0 'PASS — .*1 declared account'
# the known-key list (round-3 operator answer): the extension keys raise no NOTE, another key a NOTE, never a refusal
fresh; self_consumer
expect "golden-FALSE: the declared extension keys are known (no NOTE)" 0 '^(PASS|CM-)' 
if grep -q 'keys not in the known list' <<<"$(run 2>&1)"; then say "CASE FAILED [the extension keys raised a NOTE]"; RESULT=1; else NOK=$((NOK + 1)); qsay "ok: no NOTE for the extension keys"; fi
fresh; self_consumer; printf '%s\n' 'some_future_key=x' 'decision_id_round2=R2' 'author_only_reviewer_policy=report-and-merge' 'go_record_location=pr-comment' >>"$C/config/delivery.conf"
expect "PASS: an unknown key is named in a NOTE and not refused" 0 'NOTE  keys not in the known list \(not read, not refused\): some_future_key$'

# ── SKIP and BLIND ───────────────────────────────────────────────────────────
fresh; rm -f "$L/consumer/config/delivery.conf"
expect "SKIP: no consumer data is exit 3, never PASS" 3 'SKIP — no consumer reviewer list'
fresh; printf '%s\n' 'mode=pr' >"$L/consumer/config/delivery.conf"
expect "BLIND: a consumer configuration without the reviewer key" 2 'BLIND — .*carries no .pr_reviewers. key'
fresh; printf '%s\n' 'pr_reviewers=org/team' >"$L/consumer/config/delivery.conf"
expect "BLIND: a malformed reviewer value" 2 'BLIND — .*not a list of account names'
fresh; printf '%s\n' 'mode=pr' 'pr_reviewers=' >"$L/consumer/config/delivery.conf"
expect "BLIND: an empty reviewer list" 2 "BLIND — .*the 'pr_reviewers' value is empty"
fresh; printf '%s\n' 'mode=pr' 'pr_reviewers=   # nobody' >"$L/consumer/config/delivery.conf"
expect "BLIND: a reviewer list that holds only a comment" 2 "BLIND — .*the 'pr_reviewers' value is empty"
fresh; printf 'x\000y\n' >>"$C/CHANGELOG.md"
expect "BLIND: a corpus file with a NUL byte" 2 'BLIND — 1 corpus file\(s\) hold a NUL byte.*CHANGELOG.md'
fresh; printf 'x\000y reviewer %s\n' "$F1" >>"$C/CHANGELOG.md"
expect "BLIND: a fixture account hidden after a NUL byte in a corpus file" 2 'BLIND — 1 corpus file\(s\) hold a NUL byte'
fresh; printf 'x\000y reviewer %s\n' "$F1" >>"$C/docs/research/note.md"
expect "golden-FALSE: a NUL byte in a file outside the corpus" 0 'PASS'
fresh; expect "BLIND: a named consumer configuration that does not exist" 2 'BLIND — consumer configuration not found' --consumer-config "$L/nowhere.conf"
fresh; printf '%s\n' 'mode=pr' 'reviewers_of_record=fixture-rev-one' >"$L/consumer/config/delivery.conf"
canon_with "$F1"
expect "RED: a consumer key name declared with --reviewers-key" 1 "appears in Constitution.md:" --reviewers-key reviewers_of_record

# ── REAL consumer leg (accounts read at run time, never stored here) ─────────
REAL="${PR_DELIVERY_REAL_CONSUMER_CONFIG:-$(dirname "$ROOT")/config/delivery.conf}"
[ -n "${PR_DELIVERY_REAL_CONSUMER_CONFIG:-}" ] || [ -f "$REAL" ] || REAL="$ROOT/config/delivery.conf"
if [ -f "$REAL" ] && grep -E -q '^[[:space:]]*pr_reviewers[[:space:]]*=' "$REAL"; then
    out="$(bash "$GATE" --root "$ROOT" --consumer-config "$REAL" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then NOK=$((NOK + 1)); qsay "ok: REAL: the real tree passes with the real consumer list ($(grep -E -o '[0-9]+ declared account' <<<"$out"))"
    else say "CASE FAILED [REAL: the real tree with the real consumer list]: exit $rc"; printf '%s\n' "$out" | tail -n 4; RESULT=1; fi
    k=0
    while IFS= read -r acct; do
        [ -n "$acct" ] || continue
        k=$((k + 1)); fresh
        canon_with "$acct"
        expect "REAL: consumer account #$k written into the canon block" 1 "appears in Constitution.md:" --consumer-config "$REAL"
    done < <(awk '{ l = $0; sub(/#.*/, "", l) } l ~ /^[ \t]*(pr_reviewers|pr_assignees)[ \t]*=/ { sub(/^[ \t]*[a-z_]+[ \t]*=/, "", l); n = split(l, p, /[ \t,]+/); for (i = 1; i <= n; i++) if (p[i] != "") print p[i] }' "$REAL")
    [ "$k" -ge 1 ] || { say "CASE FAILED [REAL]: the consumer configuration lists no account"; RESULT=1; }
else
    say "REAL consumer leg: SKIP (no consumer configuration with pr_reviewers at $REAL)"
fi

# ── gate mutants: each MUST be killed ────────────────────────────────────────
mutant() { # mutant <name> <old> <new> ; writes $TMPD/mut_<name>.sh
    local name="$1" m="$TMPD/mut_$1.sh"
    cp "$GATE" "$m"; python3 -I "$PY" sub "$m" "$2" "$3" || { say "SETUP FAILURE: gate mutant $name is a no-op"; exit 2; }
    printf '%s' "$m"
}
killed() { # killed <name> <want-rc-of-original> <rc-of-mutant>
    NMUT=$((NMUT + 1))
    if [ "$3" -ne "$2" ]; then NKILL=$((NKILL + 1)); qsay "killed: $1 (exit $3, the original gives $2)"
    else say "MUTANT SURVIVED: $1 (exit $3, same as the original)"; RESULT=1; fi
}
# the matcher and the case rule
G="$(mutant blind_matcher 'local re="(^|[^A-Za-z0-9-])$4([^A-Za-z0-9-]|\$)" rs="(^|[^A-Za-z0-9-])$5([^A-Za-z0-9-]|\$)"' 'local re="(^|[^A-Za-z0-9-])$4XNEVER([^A-Za-z0-9-]|\$)" rs="(^|[^A-Za-z0-9-])$5XNEVER([^A-Za-z0-9-]|\$)"')"
fresh; killed blind_matcher 0 "$(outcome)"
G="$(mutant case_sensitive "GREP_CASE='-i'" "GREP_CASE=''")"
fresh; killed case_sensitive 0 "$(outcome)"
G="$(mutant substring_matcher 'local re="(^|[^A-Za-z0-9-])$4([^A-Za-z0-9-]|\$)" rs="(^|[^A-Za-z0-9-])$5([^A-Za-z0-9-]|\$)"' 'local re="$4" rs="$5"')"
fresh; killed substring_matcher 0 "$(outcome)"
# each normaliser step and each of the two scans
G="$(mutant nfkd_off "s = unicodedata.normalize('NFKD', s.translate(CONF))" "s = s.translate(CONF)")"
fresh; canon_with '\uff46\uff49\uff58\uff54\uff57\uff4f' subesc; killed nfkd_off 1 "$(outcome)"
G="$(mutant format_chars_kept "DROP = ('Cf', 'Mn', 'Me')" "DROP = ('Mn', 'Me')")"
fresh; canon_with 'fix\u200bture-rev-one' subesc; killed format_chars_kept 1 "$(outcome)"
G="$(mutant combining_marks_kept "DROP = ('Cf', 'Mn', 'Me')" "DROP = ('Cf',)")"
fresh; canon_with 'fi\u0301xtwo' subesc; killed combining_marks_kept 1 "$(outcome)"
G="$(mutant confusables_off '        CONF[ord(_a)] = _b' '        pass')"
fresh; canon_with 'fixtur\u0435-r\u0435v-\u043ene' subesc; killed confusables_off 1 "$(outcome)"
G="$(mutant confusables_before_nfkd_off "s = unicodedata.normalize('NFKD', s.translate(CONF))" "s = unicodedata.normalize('NFKD', s)")"
fresh; canon_with 'fixlo\u03f210' subesc; killed confusables_before_nfkd_off 1 "$(outcome --forbid-login "$F3")"
G="$(mutant confusables_after_nfkd_off 'return s.translate(CONF).translate(DASH)' 'return s.translate(DASH)')"
fresh; canon_with 'fixtur\u0451-rev-one' subesc; killed confusables_after_nfkd_off 1 "$(outcome)"
G="$(mutant audit2_rows_dropped "('\\u043a\\u043c\\u0442\\u043f\\u0433\\u0475\\u0461\\u04bd\\u0437\\u0431\\u04c0\\u0417', 'kmtnrvwe36I3'), ('\\u03f2\\u03f3\\u03b3\\u03c7', 'cjyx')" "")"
fresh; canon_with '\u043a\u043c\u0442\u043f\u0433\u0475\u0461-\u04bd\u03f3\u03b3\u03c7\u0437\u0431' subesc; killed audit2_rows_dropped 1 "$(outcome --forbid-login "$F4")"
G="$(mutant fillers_kept 'FILL = (0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800)' 'FILL = ()')"
fresh; canon_with 'fix\u3164two' subesc; killed fillers_kept 1 "$(outcome)"
G="$(mutant long_s_off "SKEL_PRE = {0x017F: 'f'}" "SKEL_PRE = {}")"
fresh; canon_with '\u017fixloc10' subesc; killed long_s_off 1 "$(outcome --forbid-login "$F3")"
G="$(mutant skeleton_digit_map_off "SKEL_MAP = {ord('0'): 'o', ord('1'): 'l', ord('|'): 'l', 0x01C0: 'l'}" "SKEL_MAP = {ord('|'): 'l', 0x01C0: 'l'}")"
fresh; canon_with 'fixloc\u04cf\u041e' subesc; killed skeleton_digit_map_off 1 "$(outcome --forbid-login "$F3")"
G="$(mutant skeleton_bar_map_off "SKEL_MAP = {ord('0'): 'o', ord('1'): 'l', ord('|'): 'l', 0x01C0: 'l'}" "SKEL_MAP = {ord('0'): 'o', ord('1'): 'l'}")"
fresh; canon_with 'fixloc|0' subesc; killed skeleton_bar_map_off 1 "$(outcome --forbid-login "$F3")"
G="$(mutant skeleton_il_class_off "return ''.join('[il]' if ch in 'il' else ch for ch in s.lower().translate(SKEL_MAP))" "return s.lower().translate(SKEL_MAP)")"
fresh; canon_with 'FIX\u0406OC10' subesc; killed skeleton_il_class_off 1 "$(outcome --forbid-login "$F3")"
G="$(mutant skeleton_digits_in_numbers "if SKEL_LETTER.search(w) else w" "if SKEL_LETTER.search(w) else w.translate(SKEL_DIGITS)")"
fresh; canon_with '1001-011'; killed skeleton_digits_in_numbers 0 "$(outcome --forbid-login lool-oll)"
G="$(mutant skeleton_bars_in_numbers "if SKEL_LETTER.search(w) else w" "if SKEL_LETTER.search(w) else w.translate(SKEL_BARS)")"
fresh; canon_with '|||-||'; killed skeleton_bars_in_numbers 0 "$(outcome --forbid-login lll-ll)"
G="$(mutant skeleton_digits_never "return w.translate(SKEL_DIGITS).translate(SKEL_BARS) if SKEL_LETTER.search(w) else w" "return w")"
fresh; canon_with 'f1xtw0'; killed skeleton_digits_never 1 "$(outcome)"
G="$(mutant skeleton_word_without_bar "SKEL_WORD = re.compile('[a-z0-9|\\u01c0-]+')" "SKEL_WORD = re.compile('[a-z0-9-]+')")"
fresh; canon_with 'fixloc|0' subesc; killed skeleton_word_without_bar 1 "$(outcome --forbid-login "$F3")"
G="$(mutant skeleton_word_without_hyphen "SKEL_WORD = re.compile('[a-z0-9|\\u01c0-]+')" "SKEL_WORD = re.compile('[a-z0-9|\\u01c0]+')")"
fresh; canon_with 'fix-10'; killed skeleton_word_without_hyphen 1 "$(outcome --forbid-login fix-lo)"
G="$(mutant hyphen_map_off 'return s.translate(CONF).translate(DASH)' 'return s.translate(CONF)')"
fresh; canon_with 'fixture\u2011rev\u2011one' subesc; killed hyphen_map_off 1 "$(outcome)"
G="$(mutant raw_scan_dropped '{ grep -I -n -E $GREP_CASE -- "$re" "$1"' '{ :')"
fresh; canon_with 'fixtwo\u2122' subesc; killed raw_scan_dropped 1 "$(outcome)"
G="$(mutant normalised_scan_dropped '      grep -I -n -E $GREP_CASE -- "$re" "$2"
' '      :
')"
fresh; canon_with '|fixtw\u03bf|' subesc; killed normalised_scan_dropped 1 "$(outcome)"
G="$(mutant skeleton_scan_dropped '      grep -I -n -E $GREP_CASE -- "$rs" "$3"; }' '      :; }')"
fresh; canon_with 'fix\u0406oc10' subesc; killed skeleton_scan_dropped 1 "$(outcome --forbid-login "$F3")"
G="$(mutant nul_not_reported "    if '\\x00' in raw:" "    if False:")"
fresh; killed nul_not_reported 0 "$(outcome)"
G="$(mutant nul_verdict_dropped '[ -s "$TMP/nul.txt" ] && blind' '[ -s "$TMP/nul.txt" ] && :')"
fresh; printf 'x\000y reviewer %s\n' "$F1" >>"$C/CHANGELOG.md"; killed nul_verdict_dropped 2 "$(outcome)"
# verdict and consumer data
G="$(mutant skip_as_pass 'the account scan did not run (not a PASS)"
    exit 3' 'the account scan did not run (not a PASS)"
    exit 0')"
fresh; rm -f "$L/consumer/config/delivery.conf"; killed skip_as_pass 3 "$(outcome)"
G="$(mutant key_optional "3) blind \"consumer configuration \$c carries no" "3) : \"consumer configuration \$c carries no")"
fresh; printf '%s\n' 'mode=pr' >"$L/consumer/config/delivery.conf"; killed key_optional 2 "$(outcome)"
G="$(mutant empty_reviewers_accepted "5) blind \"consumer configuration \$c: the '\$KEY' value is empty" "5) : \"consumer configuration \$c: the '\$KEY' value is empty")"
fresh; printf '%s\n' 'mode=pr' 'pr_reviewers=' >"$L/consumer/config/delivery.conf"; killed empty_reviewers_accepted 2 "$(outcome)"
G="$(mutant empty_list_not_detected 'if (bad) exit 4; if (!cnt) exit 5 }' 'if (bad) exit 4 }')"
fresh; killed empty_list_not_detected 0 "$(outcome)"
G="$(mutant empty_assignees_refused '        0|3|5) ;;' '        0|3) ;;')"
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" 'pr_assignees=' >"$L/consumer/config/delivery.conf"; killed empty_assignees_refused 0 "$(outcome)"
G="$(mutant assignees_ignored 'cat "$TMP/rev.txt" "$TMP/asg.txt" >>"$LOGINS"' 'cat "$TMP/rev.txt" >>"$LOGINS"')"
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" 'pr_assignees=fixture-asg' >"$L/consumer/config/delivery.conf"; canon_with fixture-asg
killed assignees_ignored 1 "$(outcome)"
G="$(mutant malformed_assignees_accepted "4) blind \"consumer configuration \$c: the '\$AKEY' value" "4) : \"consumer configuration \$c: the '\$AKEY' value")"
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" 'pr_assignees=org/team' >"$L/consumer/config/delivery.conf"; killed malformed_assignees_accepted 2 "$(outcome)"
# the corpus
G="$(mutant corpus_drops_claude 'CORPUS_FILES="Constitution.md CLAUDE.md AGENTS.md' 'CORPUS_FILES="Constitution.md AGENTS.md')"
fresh; op sub "$C/CLAUDE.md" "$MIRROR_SPOT" "(D) Reviewers ($F2) are a configured list"; killed corpus_drops_claude 1 "$(outcome)"
G="$(mutant corpus_drops_rules_manifest 'progressive/catalog.json progressive/rules_manifest.json' 'progressive/catalog.json')"
fresh; op append "$C/progressive/rules_manifest.json" "# reviewer $F1"; killed corpus_drops_rules_manifest 1 "$(outcome)"
G="$(mutant corpus_drops_gate_patterns 'for f in $CORPUS_GLOBS; do' 'for f in ; do')"
fresh; op append "$C/scripts/gates/cm_release_gate_anchor_wired.sh" "# reviewer $F1"; killed corpus_drops_gate_patterns 1 "$(outcome)"
G="$(mutant corpus_drops_guides 'CORPUS_MD_DIRS="groups progressive/rules docs/guides"' 'CORPUS_MD_DIRS="groups progressive/rules"')"
fresh; op append "$C/docs/guides/full_suite_runner_guide.md" "reviewer @$F2"; killed corpus_drops_guides 1 "$(outcome)"
G="$(mutant changed_since_ignored 'if [ -n "$SINCE" ]; then' 'if false; then')"
gitfresh; op append "$C/docs/research/note.md" "This note names $F1."; killed changed_since_ignored 1 "$(outcome --changed-since HEAD)"
# CON-PENDINGprgate: the root-level default, the configuration exclusion and the SQLite scan
G="$(mutant root_default_off 'for _d in "$ROOT/config/delivery.conf" "$(dirname "$ROOT")/config/delivery.conf"; do' 'for _d in "$(dirname "$ROOT")/config/delivery.conf"; do')"
fresh; self_consumer; killed root_default_off 0 "$(outcome)"
G="$(mutant parent_default_off 'for _d in "$ROOT/config/delivery.conf" "$(dirname "$ROOT")/config/delivery.conf"; do' 'for _d in "$ROOT/config/delivery.conf"; do')"
fresh; killed parent_default_off 0 "$(outcome)"
G="$(mutant extra_keys_read_as_accounts 'line ~ "^[ \t]*" key "[ \t]*=" {' 'line ~ "^[ \t]*pr_[a-z_]*[ \t]*=" {')"
fresh; self_consumer; killed extra_keys_read_as_accounts 0 "$(outcome)"
G="$(mutant config_exclusion_off 'if is_read_config "$p"; then' 'if false; then')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited: reviewer $F1"
killed config_exclusion_off 0 "$(outcome --changed-since HEAD)"
G="$(mutant config_exclusion_by_directory 'if is_read_config "$p"; then' 'if [ "${rel%/*}" = config ]; then')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; printf '%s\n' "other=$F1" >"$C/config/other.conf"
killed config_exclusion_by_directory 1 "$(outcome --changed-since HEAD)"
G="$(mutant config_exclusion_by_name 'if is_read_config "$p"; then' 'if [ "${rel##*/}" = delivery.conf ]; then')"
gitfresh; cp "$L/consumer/config/delivery.conf" "$C/config/delivery.conf"
killed config_exclusion_by_name 1 "$(outcome --changed-since HEAD --consumer-config "$L/consumer/config/delivery.conf")"
G="$(mutant sqlite_skip_off 'if head -c 16 -- "$1" | cmp -s - "$SQLITE_MAGIC"; then' 'if false; then')"
gitfresh; mkdb "$C/docs/workable_items.db" "$F1"; killed sqlite_skip_off 1 "$(outcome --changed-since HEAD)"
G="$(mutant skip_every_changed_file 'if head -c 16 -- "$1" | cmp -s - "$SQLITE_MAGIC"; then' 'if true; then')"
gitfresh; op append "$C/docs/research/note.md" "This note names $F1."; killed skip_every_changed_file 1 "$(outcome --changed-since HEAD)"
G="$(mutant sqlite_skip_not_reported '[ "$NSQL" -gt 0 ] && LEFT_OUT=' '[ "$NSQL" -lt 0 ] && LEFT_OUT=')"
gitfresh; mkdb "$C/docs/workable_items.db" "clean"
NMUT=$((NMUT + 1))
if grep -E -q 'PASS — .*SQLite database file\(s\) scanned as their text cells' <<<"$(run --changed-since HEAD --quiet)"; then say "MUTANT SURVIVED: sqlite_skip_not_reported (the PASS still names the skipped database)"; RESULT=1
else NKILL=$((NKILL + 1)); qsay "killed: sqlite_skip_not_reported (the PASS no longer names the skipped database)"; fi
# ── round 3: the reviewer's mutants R1 to R12 (rev_prdeliv_r2 revmut.py). R1, R5 to R11 apply verbatim to this gate;
# R2, R3, R4 and R12 are the same edit on the lines that replaced the round-2 code (the round-2 lines no longer exist)
textkill() { # textkill <name> <regex the original's output holds> [gate args...]: the mutant's output must lack it
    local name="$1" rx="$2"; shift 2; NMUT=$((NMUT + 1))
    if grep -E -q -- "$rx" <<<"$(run "$@")"; then say "MUTANT SURVIVED: $name (output still matches /$rx/)"; RESULT=1
    else NKILL=$((NKILL + 1)); qsay "killed: $name (output no longer matches /$rx/)"; fi
}
mutant2() { # mutant2 <name> <old1> <new1> <old2> <new2>
    local name="$1" m="$TMPD/mut_$1.sh"
    cp "$GATE" "$m"; python3 -I "$PY" sub "$m" "$2" "$3" && python3 -I "$PY" sub "$m" "$4" "$5" || { say "SETUP FAILURE: gate mutant $name is a no-op"; exit 2; }
    printf '%s' "$m"
}
near_fx() { gitfresh; printf 'SQLite format 3 near the header, reviewer %s\n' "$F1" >"$C/docs/research/near.md"; }
G="$(mutant2 R1_magic_no_nul "printf 'SQLite format 3\\000' >\"\$SQLITE_MAGIC\"" "printf 'SQLite format 3' >\"\$SQLITE_MAGIC\"" 'head -c 16 --' 'head -c 15 --')"
near_fx; killed R1_magic_no_nul 1 "$(outcome --changed-since HEAD)"
G="$(mutant R2_confreal_raw_path '_r="$(readlink -f -- "$c")" || blind' '_r="$c" || blind')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited"
RUNCWD="$C" killed R2_confreal_raw_path 0 "$(RUNCWD="$C" outcome --changed-since HEAD --consumer-config config/delivery.conf)"
G="$(mutant R3_changed_raw_path '    r="$(readlink -f -- "$p")" || return 1' '    r="$p" || return 1')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited"; ln -s "$C" "$L/rlink"
killed R3_changed_raw_path 0 "$(RUNROOT="$L/rlink" outcome --changed-since HEAD)"
G="$(mutant R4_substring_match 'for x in ${CONF_REALS[@]+"${CONF_REALS[@]}"}; do [ "$r" = "$x" ] && return 0; done' 'for x in ${CONF_REALS[@]+"${CONF_REALS[@]}"}; do case "$x" in "$r"*) return 0 ;; esac; done')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; printf '%s\n' "$F1" >"$C/config/delivery.c"; killed R4_substring_match 1 "$(outcome --changed-since HEAD)"
G="$(mutant R5_excl_not_named '[ "$NEXCL" -gt 0 ] && LEFT_OUT=' '[ "$NEXCL" -lt 0 ] && LEFT_OUT=')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited"
textkill R5_excl_not_named 'PASS — .*excluded from --changed-since: 1 consumer configuration' --changed-since HEAD --quiet
G="$(mutant2 R6_magic_prefix6 'head -c 16 -- "$1" | cmp -s - "$SQLITE_MAGIC"' 'head -c 6 -- "$1" | cmp -s -n 6 - "$SQLITE_MAGIC"' 'SQLITE_MAGIC="$TMP/sqlite_magic";' 'SQLITE_MAGIC="$TMP/sqlite_magic";')"
near_fx; killed R6_magic_prefix6 1 "$(outcome --changed-since HEAD)"
G="$(mutant R7_defaults_always 'if [ "$CONFIG_GIVEN" = 0 ]; then' 'if true; then')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited"; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$L/consumer/config/delivery.conf"
killed R7_defaults_always 1 "$(outcome --changed-since HEAD --consumer-config "$L/consumer/config/delivery.conf")"
G="$(mutant R8_pass_line_drops_leftout 'appear in none of the $SCOPE$LEFT_OUT; files outside' 'appear in none of the $SCOPE; files outside')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited"
textkill R8_pass_line_drops_leftout 'PASS — .*excluded from --changed-since: 1 consumer configuration' --changed-since HEAD --quiet
G="$(mutant R9_untracked_dropped '&& git -C "$ROOT" -c core.quotePath=false ls-files -z --others --exclude-standard; }' '; }')"
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/u.md"; killed R9_untracked_dropped 1 "$(outcome --changed-since HEAD)"
G="$(mutant R10_committed_only 'git -C "$ROOT" -c core.quotePath=false diff -z --relative --name-only "$SINCE" --' 'git -C "$ROOT" -c core.quotePath=false diff -z --relative --name-only "$SINCE" HEAD --')"
gitfresh; op append "$C/docs/research/note.md" "This note names $F1."; killed R10_committed_only 1 "$(outcome --changed-since HEAD)"
G="$(mutant R11_sql_count_noop 'NSQL=$((NSQL + 1)); SQL_LIST="$SQL_LIST $2"' 'SQL_LIST="$SQL_LIST $2"')"
gitfresh; mkdb "$C/docs/workable_items.db" "clean"
textkill R11_sql_count_noop 'PASS — .*1 SQLite database file\(s\) scanned as their text cells' --changed-since HEAD --quiet
G="$(mutant R12_parent_default_physical '"$(dirname "$ROOT")/config/delivery.conf"; do' '"$(dirname "$(readlink -f "$ROOT")")/config/delivery.conf"; do')"
fresh; rm -f "$L/consumer/config/delivery.conf"; mkdir -p "$L/consumer2/config"; ln -s "$C" "$L/consumer2/constitution"; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$L/consumer2/config/delivery.conf"
killed R12_parent_default_physical 0 "$(RUNROOT="$L/consumer2/constitution" outcome)"
# ── round 3: own mutants of the new code ────────────────────────────────────
G="$(mutant sqlite_tables_skipped "            if typ == 'table':" "            if False:")"
gitfresh; mkdb "$C/docs/research/t.db" "reviewer $F1"; killed sqlite_tables_skipped 1 "$(outcome --changed-since HEAD)"
G="$(mutant sqlite_blob_ignored "                    if isinstance(v, bytes):" "                    if False:")"
gitfresh; mkblobdb "$C/docs/research/b.db" "blob names $F2"; killed sqlite_blob_ignored 1 "$(outcome --changed-since HEAD)"
G="$(mutant sqlite_error_swallowed "sys.stderr.write('%s\\n' % e); sys.exit(3)" "cells = []")"
# the control needle (a fake header must give exit 3) makes the mutant BLIND on any input, so a clean database discriminates
gitfresh; mkdb "$C/docs/research/t.db" "clean"; killed sqlite_error_swallowed 0 "$(outcome --changed-since HEAD)"
G="$(mutant sqlite_nul_kept "fh.write(v.replace('\\x00', ' ') + '\\n')" "fh.write(v + '\\n')")"
gitfresh; mknuldb "$C/docs/research/n.db"; killed sqlite_nul_kept 0 "$(outcome --changed-since HEAD)"
G="$(mutant symlink_into_exclusion '    [ -L "$p" ] && return 1' '    :')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited"; ln -s ../../config/delivery.conf "$C/docs/research/l.md"
killed symlink_into_exclusion 1 "$(outcome --changed-since HEAD)"
G="$(mutant symlink_target_text_dropped 'add_scan "$rel (symbolic link target)"' ': "$rel (symbolic link target)"')"
gitfresh; ln -s "no-such-target/$F2" "$C/docs/research/dangling.md"; killed symlink_target_text_dropped 1 "$(outcome --changed-since HEAD)"
G="$(mutant symlink_outside_not_blind '*) blind "--changed-since: the changed symbolic link' '*) : "--changed-since: the changed symbolic link')"
gitfresh; printf '%s\n' "outside $F1" >"$L/outside.txt"; ln -s "$L/outside.txt" "$C/docs/research/out.md"; killed symlink_outside_not_blind 2 "$(outcome --changed-since HEAD)"
G="$(mutant config_symlink_accepted '[ -L "$c" ] && blind "consumer configuration $c is a symbolic link' '[ -L "$c" ] && : "consumer configuration $c is a symbolic link')"
fresh; rm -f "$L/consumer/config/delivery.conf"; mkdir -p "$L/elsewhere/config" "$C/config"; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$L/elsewhere/config/delivery.conf"; ln -s "$L/elsewhere/config/delivery.conf" "$C/config/delivery.conf"
killed config_symlink_accepted 2 "$(outcome)"
G="$(mutant config_dir_check_off '[ "$(basename -- "$(dirname -- "$_r")")" = config ] || blind' 'true || blind')"
fresh; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" >"$L/data.md"; killed config_dir_check_off 2 "$(outcome --consumer-config "$L/data.md")"
G="$(mutant inside_root_config_check_off '[ "$(dirname -- "$_r")" = "$ROOT_REAL/config" ] || blind' 'true || blind')"
gitfresh; mkdir -p "$C/docs/research/config"; printf '%s\n' 'mode=pr' "pr_reviewers=$F1" "prose $F1" >"$C/docs/research/config/x.conf"
killed inside_root_config_check_off 2 "$(outcome --changed-since HEAD --consumer-config "$C/docs/research/config/x.conf")"
G="$(mutant index_scan_dropped 'add_content "$TMP/idx/$NIDX" "index:$rel"' ': "$TMP/idx/$NIDX" "index:$rel"')"
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/s.md"; fgit add docs/research/s.md; printf '%s\n' clean >"$C/docs/research/s.md"; killed index_scan_dropped 1 "$(outcome --changed-since HEAD)"
G="$(mutant cached_listing_dropped '      && git -C "$ROOT" -c core.quotePath=false diff -z --cached --relative --name-only "$SINCE" -- \' '      && : \')"
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/g.md"; fgit add docs/research/g.md; rm -f "$C/docs/research/g.md"; killed cached_listing_dropped 1 "$(outcome --changed-since HEAD)"
G="$(mutant names_scan_dropped 'add_scan "(names of the paths changed since $SINCE)" "$NAMES"' ': "$NAMES"')"
gitfresh; printf '%s\n' clean >"$C/docs/research/$F2.md"; killed names_scan_dropped 1 "$(outcome --changed-since HEAD)"
G="$(mutant worktree_listing_not_nul 'git -C "$ROOT" -c core.quotePath=false diff -z --relative --name-only "$SINCE" --' 'git -C "$ROOT" -c core.quotePath=false diff --relative --name-only "$SINCE" --')"
gitfresh; printf '%s\n' clean >"$C/docs/research/ü2.md"; fgit add -A; fgit commit -q -m u2; printf '%s\n' "$F1" >>"$C/docs/research/ü2.md"; killed worktree_listing_not_nul 1 "$(outcome --changed-since HEAD)"
G="$(mutant unreadable_path_skipped '|| blind "--changed-since: the changed path $rel cannot be read"' '|| continue')"
gitfresh; printf '%s\n' "$F1" >"$C/docs/research/locked.md"; chmod 000 "$C/docs/research/locked.md"
if [ -r "$C/docs/research/locked.md" ]; then qsay "skip: mutant unreadable_path_skipped (this user reads mode-000 files)"; chmod 644 "$C/docs/research/locked.md"
else killed unreadable_path_skipped 2 "$(outcome --changed-since HEAD)"; chmod 644 "$C/docs/research/locked.md"; fi
G="$(mutant known_keys_dropped 'decision_id_round2 own_repositories author_only_reviewer_policy go_record_location $KEY' 'own_repositories $KEY')"
fresh; self_consumer; printf '%s\n' 'decision_id_round2=R2' >>"$C/config/delivery.conf"; NMUT=$((NMUT + 1))
if grep -q 'keys not in the known list' <<<"$(run)"; then NKILL=$((NKILL + 1)); qsay "killed: known_keys_dropped (a NOTE appears for an extension key)"; else say "MUTANT SURVIVED: known_keys_dropped"; RESULT=1; fi
G="$(mutant staged_config_scanned '(a consumer configuration read in this run: it holds the account names)"
            continue' '(a consumer configuration read in this run: it holds the account names)"
            :')"
gitfresh; self_consumer; fgit add -A; fgit commit -q -m conf; op append "$C/config/delivery.conf" "# edited"; fgit add config/delivery.conf; op append "$C/config/delivery.conf" "# edited again"
killed staged_config_scanned 0 "$(outcome --changed-since HEAD)"
G="$(mutant scan_skipped 'if [ "$NLOGIN" -gt 0 ]; then
    idx=0' 'if false; then
    idx=0')"
fresh; canon_with "$F1"; killed scan_skipped 1 "$(outcome)"
G="$GATE"

if [ "$RESULT" -eq 0 ]; then
    say "PASS: $NOK cases behaved as required and $NKILL of $NMUT gate mutants were killed — cm_pr_delivery_account_name_free.sh genuinely discriminates"
else
    say "FAIL: at least one case misbehaved or one gate mutant survived"
fi
exit "$RESULT"
