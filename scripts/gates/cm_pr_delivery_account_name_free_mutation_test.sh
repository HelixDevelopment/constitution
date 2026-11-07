#!/usr/bin/env bash
# cm_pr_delivery_account_name_free_mutation_test.sh — paired §1.1 mutation test for CM-PR-DELIVERY-ACCOUNT-NAME-FREE
#
# Purpose
#   Proves cm_pr_delivery_account_name_free.sh genuinely discriminates. It copies the rule corpus
#   into a scratch layout <tmp>/consumer/constitution next to a FIXTURE consumer configuration
#   <tmp>/consumer/config/delivery.conf whose reviewer list holds two fixture accounts (no real
#   account name is stored in this file) and runs the gate:
#     * GREEN control    the unmodified copy with the fixture consumer MUST pass (exit 0);
#     * golden-FALSE     a longer account name that contains a fixture account, and a fixture account
#                        written into a file outside the corpus, MUST still pass (§11.4.201(1));
#     * RED              a fixture account written into each corpus file class (the canon block, each
#                        of the four mirrors, the group file, the progressive rule file, the index,
#                        the changelog, the readme, the owed-gates page, the deferral registry, a gate
#                        file), a case variant, an account given only by --forbid-login, and an
#                        @-mention in a mirror block MUST exit 1 and name the file;
#     * SKIP / BLIND     no consumer data MUST exit 3 (never 0); a configuration without the key, a
#                        malformed value and a missing configuration file MUST exit 2;
#     * REAL consumer    when a consumer configuration exists next to this constitution
#                        (<root>/../config/delivery.conf, or PR_DELIVERY_REAL_CONSUMER_CONFIG), the
#                        gate MUST pass on the real tree with it, and each account read from it AT RUN
#                        TIME, written into a copy of the canon block, MUST exit 1; without such a file
#                        this leg is reported SKIP;
#     * gate mutants     seven edits of a copy of the gate (blind matcher, case-sensitive matcher,
#                        substring matcher, SKIP reported as PASS, present-means-mandatory removed, a
#                        corpus file dropped, the scan skipped) MUST each be killed by a scenario above.
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
# Dependencies: bash, python3, awk, grep, cp, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GATE="$HERE/cm_pr_delivery_account_name_free.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
for _t in python3 awk grep cp mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "[mutation:account-name] required tool '$_t' missing" >&2; exit 2; }
done
[ -f "$GATE" ] || { echo "[mutation:account-name] SETUP FAILURE: gate missing: $GATE" >&2; exit 2; }

TMPD="$(mktemp -d)" || exit 2
trap 'rm -rf "${TMPD:?}"' EXIT
BASE="$TMPD/base"; L="$TMPD/layout"; C="$L/consumer/constitution"; PY="$TMPD/op.py"
RESULT=0; NOK=0; NKILL=0
say() { printf '[mutation:account-name] %s\n' "$*"; }
qsay() { [ "$QUIET" = 1 ] || say "$@"; }
F1="fixture-rev-one"; F2="fixtwo"

FILES=(Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md README.md CHANGELOG.md constitution_index.yaml
       progressive/catalog.json progressive/rules/11.4.297.md groups/git-and-data-safety.md
       docs/owed_gate_implementations.md scripts/gates/gate_ledger_deferrals.tsv
       scripts/gates/cm_pr_delivery_anchor_wired.sh scripts/gates/cm_pr_delivery_account_name_free.sh)
mkdir -p "$BASE/consumer/constitution" "$BASE/consumer/config"
for f in "${FILES[@]}"; do
    [ -f "$ROOT/$f" ] || { say "SETUP FAILURE: input missing: $f"; exit 2; }
    (cd "$ROOT" && cp --parents "$f" "$BASE/consumer/constitution/") || { say "SETUP FAILURE: copy failed: $f"; exit 2; }
done
mkdir -p "$BASE/consumer/constitution/docs/research"
printf '%s\n' 'A research note outside the rule corpus.' >"$BASE/consumer/constitution/docs/research/note.md"
printf '%s\n' '# fixture consumer configuration' 'mode=pr' "pr_reviewers=$F1,$F2" >"$BASE/consumer/config/delivery.conf"

cat >"$PY" <<'PYEOF'
import sys
op, path = sys.argv[1], sys.argv[2]
raw = open(path, encoding='utf-8').read()
if op == 'sub':
    old, new = sys.argv[3], sys.argv[4]
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
op() { python3 "$PY" "$@" || { say "SETUP FAILURE: operator '$1 $2' failed (a no-op mutation is a test bug)"; exit 2; }; }
fresh() { rm -rf "${L:?}"; cp -a "$BASE" "$L" || { say "SETUP FAILURE: scratch copy failed"; exit 2; }; }
G="$GATE"
run() { bash "$G" --root "$C" "$@" 2>&1; }

# expect <label> <rc> <regex-in-output> [gate args...]
expect() {
    local label="$1" want="$2" rx="$3" out rc; shift 3
    out="$(run "$@")"; rc=$?
    if [ "$rc" -ne "$want" ]; then say "CASE FAILED [$label]: exit $rc, expected $want"; printf '%s\n' "$out" | tail -n 4; RESULT=1; return; fi
    if ! grep -E -q -- "$rx" <<<"$out"; then say "CASE FAILED [$label]: exit $rc but output lacks /$rx/"; RESULT=1; return; fi
    NOK=$((NOK + 1)); qsay "ok: $label (exit $rc)"
}
# outcome -> the exit status of one run of $G on the current scratch layout (used for the gate mutants)
outcome() { run >/dev/null 2>&1; echo $?; }

CANON_SPOT='(5) The same rule binds the pull requests a submodule cascade opens'
MIRROR_SPOT='(D) Reviewers are a configured list'
INDEX_SPOT='Pull-request delivery: a project that declares it by a recorded operator'

# ── GREEN control, golden-FALSE ──────────────────────────────────────────────
fresh; expect "GREEN control: fixture consumer, clean corpus" 0 'PASS — .*2 declared account'
fresh; op sub "$C/Constitution.md" "$CANON_SPOT" "(5) A reviewer named x$F1 or ${F1}x is another account. The same rule binds the pull requests a submodule cascade opens"
expect "golden-FALSE: longer account names that contain a fixture account" 0 'PASS'
fresh; op append "$C/docs/research/note.md" "This note names $F1 outside the rule corpus."
expect "golden-FALSE: a fixture account in a file outside the corpus" 0 'PASS'

# ── RED: one corpus file class at a time ─────────────────────────────────────
fresh; op sub "$C/Constitution.md" "$CANON_SPOT" "(5) Ask $F1 first. The same rule binds the pull requests a submodule cascade opens"
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
for f in CHANGELOG.md README.md docs/owed_gate_implementations.md scripts/gates/gate_ledger_deferrals.tsv scripts/gates/cm_pr_delivery_anchor_wired.sh; do
    fresh; op append "$C/$f" "# reviewer $F1"
    expect "RED: fixture account in $f" 1 "appears in $f:"
done
UPPER="$(printf '%s' "$F1" | tr '[:lower:]' '[:upper:]')"
fresh; op sub "$C/Constitution.md" "$CANON_SPOT" "(5) Ask $UPPER first. The same rule binds the pull requests a submodule cascade opens"
expect "RED: a case variant of a fixture account" 1 "appears in Constitution.md:"
fresh; rm -f "$L/consumer/config/delivery.conf"; op append "$C/CHANGELOG.md" "named fixture-extra here"
expect "RED: an account given only by --forbid-login" 1 "appears in CHANGELOG.md:" --forbid-login fixture-extra
fresh; op sub "$C/AGENTS.md" "$MIRROR_SPOT" "(D) Reviewers (ask @some-other-account) are a configured list"
expect "RED: an @-mention in a mirror block" 1 "structure: mirror AGENTS.md .*@-mention"

# ── SKIP and BLIND ───────────────────────────────────────────────────────────
fresh; rm -f "$L/consumer/config/delivery.conf"
expect "SKIP: no consumer data is exit 3, never PASS" 3 'SKIP — no consumer reviewer list'
fresh; printf '%s\n' 'mode=pr' >"$L/consumer/config/delivery.conf"
expect "BLIND: a consumer configuration without the reviewer key" 2 'BLIND — .*carries no .pr_reviewers. key'
fresh; printf '%s\n' 'pr_reviewers=org/team' >"$L/consumer/config/delivery.conf"
expect "BLIND: a malformed reviewer value" 2 'BLIND — .*not a list of account names'
fresh; expect "BLIND: a named consumer configuration that does not exist" 2 'BLIND — consumer configuration not found' --consumer-config "$L/nowhere.conf"
fresh; printf '%s\n' 'mode=pr' 'reviewers_of_record=fixture-rev-one' >"$L/consumer/config/delivery.conf"
op sub "$C/Constitution.md" "$CANON_SPOT" "(5) Ask $F1 first. The same rule binds the pull requests a submodule cascade opens"
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
        op sub "$C/Constitution.md" "$CANON_SPOT" "(5) Ask $acct first. The same rule binds the pull requests a submodule cascade opens"
        expect "REAL: consumer account #$k written into the canon block" 1 "appears in Constitution.md:" --consumer-config "$REAL"
    done < <(awk '{ l = $0; sub(/#.*/, "", l) } l ~ /^[ \t]*pr_reviewers[ \t]*=/ { sub(/^[ \t]*pr_reviewers[ \t]*=/, "", l); n = split(l, p, /[ \t,]+/); for (i = 1; i <= n; i++) if (p[i] != "") print p[i] }' "$REAL")
    [ "$k" -ge 1 ] || { say "CASE FAILED [REAL]: the consumer configuration lists no account"; RESULT=1; }
else
    say "REAL consumer leg: SKIP (no consumer configuration with pr_reviewers at $REAL)"
fi

# ── gate mutants: each MUST be killed ────────────────────────────────────────
mutant() { # mutant <name> <old> <new> ; writes $TMPD/mut_<name>.sh
    local name="$1" m="$TMPD/mut_$1.sh"
    cp "$GATE" "$m"; python3 "$PY" sub "$m" "$2" "$3" || { say "SETUP FAILURE: gate mutant $name is a no-op"; exit 2; }
    printf '%s' "$m"
}
killed() { # killed <name> <want-rc-of-original> <rc-of-mutant>
    if [ "$3" -ne "$2" ]; then NKILL=$((NKILL + 1)); qsay "killed: $1 (exit $3, the original gives $2)"
    else say "MUTANT SURVIVED: $1 (exit $3, same as the original)"; RESULT=1; fi
}
G="$(mutant blind_matcher '"(^|[^A-Za-z0-9-])$2([^A-Za-z0-9-]|\$)"' '"(^|[^A-Za-z0-9-])$2XNEVER([^A-Za-z0-9-]|\$)"')"
fresh; killed blind_matcher 0 "$(outcome)"
G="$(mutant case_sensitive "GREP_CASE='-i'" "GREP_CASE=''")"
fresh; killed case_sensitive 0 "$(outcome)"
G="$(mutant substring_matcher '"(^|[^A-Za-z0-9-])$2([^A-Za-z0-9-]|\$)"' '"$2"')"
fresh; killed substring_matcher 0 "$(outcome)"
G="$(mutant skip_as_pass 'the account scan did not run (not a PASS)"
    exit 3' 'the account scan did not run (not a PASS)"
    exit 0')"
fresh; rm -f "$L/consumer/config/delivery.conf"; killed skip_as_pass 3 "$(outcome)"
G="$(mutant key_optional "3) blind \"consumer configuration \$c carries no" "3) : \"consumer configuration \$c carries no")"
fresh; printf '%s\n' 'mode=pr' >"$L/consumer/config/delivery.conf"; killed key_optional 2 "$(outcome)"
G="$(mutant corpus_drops_claude 'for f in Constitution.md CLAUDE.md AGENTS.md' 'for f in Constitution.md AGENTS.md')"
fresh; op sub "$C/CLAUDE.md" "$MIRROR_SPOT" "(D) Reviewers ($F2) are a configured list"
killed corpus_drops_claude 1 "$(outcome)"
G="$(mutant scan_skipped 'if [ "$NLOGIN" -gt 0 ]; then
    while IFS= read -r login; do' 'if false; then
    while IFS= read -r login; do')"
fresh; op sub "$C/Constitution.md" "$CANON_SPOT" "(5) Ask $F1 first. The same rule binds the pull requests a submodule cascade opens"; killed scan_skipped 1 "$(outcome)"
G="$GATE"

if [ "$RESULT" -eq 0 ]; then
    say "PASS: $NOK cases behaved as required and $NKILL of 7 gate mutants were killed — cm_pr_delivery_account_name_free.sh genuinely discriminates"
else
    say "FAIL: at least one case misbehaved or one gate mutant survived"
fi
exit "$RESULT"
