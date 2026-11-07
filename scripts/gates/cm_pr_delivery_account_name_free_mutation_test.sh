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
#                        for o inside a name) and a sign that
#                        decomposes into letters, an assignee account,
#                        an account given only by --forbid-login, a file named by --changed-since (changed,
#                        untracked, committed after the base) and an @-mention in a mirror block MUST exit 1
#                        and name the file;
#     * SKIP / BLIND     no consumer data MUST exit 3 (never 0); a configuration without the reviewer key,
#                        an empty reviewer list (bare, or with a comment only), a malformed reviewer or
#                        assignee value, a missing configuration file, a corpus file with a NUL byte (also
#                        one that hides a fixture account after the NUL) and an unresolvable --changed-since
#                        MUST exit 2; equal reviewer and assignee keys exit 64;
#     * REAL consumer    when a consumer configuration exists next to this constitution
#                        (<root>/../config/delivery.conf, or PR_DELIVERY_REAL_CONSUMER_CONFIG), the gate
#                        MUST pass on the real tree with it, and each account read from it AT RUN TIME,
#                        written into a copy of the canon block, MUST exit 1; without such a file this leg is
#                        reported SKIP;
#     * gate mutants     edits of a copy of the gate (the matcher, the case rule, each normaliser step, the
#                        table before and after NFKD, the table rows added by audit 2, the fillers, each
#                        skeleton step, the digits or the bars read as letters in every word, the digits in
#                        none, the bar left
#                        out of a word, each of the three scans, the NUL report and its verdict, SKIP
#                        reported as PASS, present-means-mandatory removed, an empty reviewer list accepted
#                        or not detected, an empty assignee list refused, the assignee list ignored or its
#                        malformed value accepted, --changed-since ignored, a corpus file, file pattern or
#                        guide directory dropped, the scan skipped) MUST each be killed by a scenario above.
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
run() { bash "$G" --root "$C" "$@" 2>&1; }
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
# (the accounts below appear in no corpus file: the gate's own needle accounts are in its source, which is in the corpus)
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
