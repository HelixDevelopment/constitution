#!/usr/bin/env bash
# cm_pr_delivery_account_name_free.sh — gate CM-PR-DELIVERY-ACCOUNT-NAME-FREE (§11.4.297(D)(1), (H)(2))
#
# Purpose
#   §11.4.297 carries the reviewer RULE into the constitution and keeps the reviewer NAMES out
#   of it: account names are the consuming project's DATA (§11.4.17, §11.4.35). This gate proves
#   it for the accounts a consumer actually declares. It reads the consumer's reviewer accounts AT
#   RUN TIME from the consumer's own delivery configuration (never from this repository; this file
#   and its mutation test store no account name) and scans the rule corpus of the constitution for
#   each one as a whole account name, case-insensitively:
#     Constitution.md, CLAUDE.md, AGENTS.md, QWEN.md, GEMINI.md, README.md, CHANGELOG.md,
#     constitution_index.yaml, groups/*.md, progressive/rules/*.md, progressive/catalog.json,
#     docs/owed_gate_implementations.md, scripts/gates/gate_ledger_deferrals.tsv and the four
#     cm_pr_delivery_* gate files.
#   It also checks, without consumer data, that the §11.4.297 canon block and its four mirror
#   blocks carry no @-mention of an account (structure, not names).
#
# Consumer data (§11.4.35; all sources are read, none is required)
#   --consumer-config FILE   a delivery configuration of the consumer (key=value lines, '#' starts a
#                            comment); repeatable. Default when none is given: <root>/../config/delivery.conf
#                            if that file exists (the layout of a constitution checked out as a submodule).
#   --reviewers-key KEY      the key that holds the reviewer list (default pr_reviewers; a consumer may
#                            declare another name, §11.4.297(D)(1)).
#   --forbid-login LOGIN     an account to scan for, in addition; repeatable.
#   Present means mandatory: a consumer configuration that exists but carries no reviewer key, or a
#   value that is not a list of account names, makes the gate BLIND (exit 2), never a silent pass.
#
# Usage
#   cm_pr_delivery_account_name_free.sh [--root <constitution-dir>] [--consumer-config FILE]...
#       [--reviewers-key KEY] [--forbid-login LOGIN]... [--quiet]
#
# Exit codes
#   0  PASS    at least one account was read and none appears in the corpus; the structure checks hold
#   1  FAIL    an account appears (file and line named) or a structure check failed
#   2  BLIND   a control needle failed, Constitution.md is absent, or consumer data exists and cannot be read
#   3  SKIP    no consumer account list exists (a constitution checked out on its own): the structure
#              checks ran, the account scan did not; never reported as PASS
#   64 usage error
#
# Instrument discipline (§11.4.273): before any verdict the matcher is run on synthetic text whose
# answer is known: a whole account name is seen, a different-case spelling is seen, a longer name that
# contains it is not, and the configuration parser reads a known list and refuses a malformed one.
# Honest boundary (§11.4.6): only declared accounts can be scanned; an account name that is also a
# common word is reported wherever that word appears in the corpus.
#
# Dependencies: bash, awk, grep, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
QUIET=0
GATE="CM-PR-DELIVERY-ACCOUNT-NAME-FREE"
N=297
KEY="pr_reviewers"
CONFIGS=()
EXTRA=()
CONFIG_GIVEN=0

usage() { echo "usage: ${0##*/} [--root DIR] [--consumer-config FILE]... [--reviewers-key KEY] [--forbid-login LOGIN]... [--quiet] | --help" >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --consumer-config) [ $# -ge 2 ] || usage; CONFIGS+=("$2"); CONFIG_GIVEN=1; shift 2 ;;
        --reviewers-key) [ $# -ge 2 ] || usage; KEY="$2"; shift 2 ;;
        --forbid-login) [ $# -ge 2 ] || usage; EXTRA+=("$2"); shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; exit 0 ;;
        *) usage ;;
    esac
done
[ -d "$ROOT" ] || { echo "$GATE: BLIND — root is not a directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
case "$KEY" in ''|*[!A-Za-z0-9_.-]*) echo "$GATE: usage — --reviewers-key must be a plain key name" >&2; exit 64 ;; esac

TMP="$(mktemp -d)" || { echo "$GATE: BLIND — mktemp failed" >&2; exit 2; }
trap 'rm -rf "${TMP:?}"' EXIT

NPASS=0; NFAIL=0
pass() { NPASS=$((NPASS + 1)); [ "$QUIET" = 1 ] || printf 'PASS  %s\n' "$*"; }
fail() { NFAIL=$((NFAIL + 1)); printf 'FAIL  %s\n' "$*"; }
blind() { echo "$GATE: BLIND — $*" >&2; exit 2; }

# ── the matcher and the parser (single definitions; the mutation test breaks them on a copy) ──
# An account name is a whole word of the class [A-Za-z0-9-]: nothing of that class touches it.
LOGIN_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'
GREP_CASE='-i'
# hits FILE LOGIN -> "line:text" lines where LOGIN occurs as a whole account name
hits() {
    grep -n -E $GREP_CASE -- "(^|[^A-Za-z0-9-])$2([^A-Za-z0-9-]|\$)" "$1" 2>/dev/null
}
# parse_conf FILE KEY -> one account per line on stdout; exit 3 when the key is absent, 4 when a value is malformed
parse_conf() {
    awk -v key="$2" '
        { line = $0; sub(/#.*/, "", line) }
        line ~ "^[ \t]*" key "[ \t]*=" {
            found = 1; sub("^[ \t]*" key "[ \t]*=", "", line)
            n = split(line, parts, /[ \t,]+/)
            for (i = 1; i <= n; i++) { if (parts[i] == "") continue; if (parts[i] !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/ || length(parts[i]) > 39) bad = 1; else print parts[i] }
        }
        END { if (!found) exit 3; if (bad) exit 4 }
    ' "$1"
}

# ── control needles (§11.4.273) ──────────────────────────────────────────────
NDOC="$TMP/needle.txt"
printf '%s\n' 'line one names needle-login-a in prose.' 'line two names Needle-Login-A in another case.' \
    'line three names xneedle-login-a and needle-login-ab, which are other accounts.' >"$NDOC"
[ "$(hits "$NDOC" needle-login-a | wc -l | tr -d ' ')" = 2 ] || blind "matcher control needle: expected exactly 2 whole-name hits (one per case form) in the needle text"
hits "$NDOC" needle-login-a | grep -q '^3:' && blind "matcher control needle: a longer account name was matched as the needle"
NCONF="$TMP/needle.conf"
printf '%s\n' '# comment pr_reviewers=commented-out' 'mode=pr' "$KEY=needle-one, needle-two # trailing comment" >"$NCONF"
[ "$(parse_conf "$NCONF" "$KEY" | tr '\n' ' ')" = "needle-one needle-two " ] || blind "parser control needle: the known list was not read as 'needle-one needle-two'"
printf '%s\n' "$KEY=bad/login" >"$TMP/bad.conf"
parse_conf "$TMP/bad.conf" "$KEY" >/dev/null 2>&1; [ $? -eq 4 ] || blind "parser control needle: a malformed value was not refused"
printf '%s\n' 'mode=pr' >"$TMP/nokey.conf"
parse_conf "$TMP/nokey.conf" "$KEY" >/dev/null 2>&1; [ $? -eq 3 ] || blind "parser control needle: an absent key was not reported"

CANON="$ROOT/Constitution.md"
[ -f "$CANON" ] || blind "Constitution.md not found under $ROOT"

# ── consumer accounts ────────────────────────────────────────────────────────
# The parent is taken from the path string (dirname), not by resolving "..", so a constitution reached through a
# symlinked layout still finds the configuration of the project that holds it.
CONSUMER_DEFAULT="$(dirname "$ROOT")/config/delivery.conf"
if [ "$CONFIG_GIVEN" = 0 ] && [ -f "$CONSUMER_DEFAULT" ]; then
    CONFIGS+=("$CONSUMER_DEFAULT")
fi
LOGINS="$TMP/logins.txt"; : >"$LOGINS"
for c in ${CONFIGS[@]+"${CONFIGS[@]}"}; do
    [ -f "$c" ] || blind "consumer configuration not found: $c"
    parse_conf "$c" "$KEY" >>"$LOGINS"; rc=$?
    case "$rc" in
        0) ;;
        3) blind "consumer configuration $c carries no '$KEY' key (present means mandatory: pass --reviewers-key or --forbid-login)" ;;
        4) blind "consumer configuration $c: the '$KEY' value is not a list of account names" ;;
        *) blind "consumer configuration $c could not be read (awk exit $rc)" ;;
    esac
done
for l in ${EXTRA[@]+"${EXTRA[@]}"}; do
    printf '%s\n' "$l" | grep -E -q -- "$LOGIN_RE" || blind "--forbid-login value is not an account name: $l"
    printf '%s\n' "$l" >>"$LOGINS"
done
sort -u -f "$LOGINS" -o "$LOGINS"
NLOGIN="$(grep -c . "$LOGINS" | tr -d ' ')"

# ── the corpus ───────────────────────────────────────────────────────────────
CORPUS="$TMP/corpus.txt"; : >"$CORPUS"
for f in Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md README.md CHANGELOG.md constitution_index.yaml \
         progressive/catalog.json docs/owed_gate_implementations.md scripts/gates/gate_ledger_deferrals.tsv \
         scripts/gates/cm_pr_delivery_anchor_wired.sh scripts/gates/cm_pr_delivery_anchor_wired_mutation_test.sh \
         scripts/gates/cm_pr_delivery_account_name_free.sh scripts/gates/cm_pr_delivery_account_name_free_mutation_test.sh; do
    [ -f "$ROOT/$f" ] && printf '%s\n' "$f" >>"$CORPUS"
done
for d in groups progressive/rules; do
    [ -d "$ROOT/$d" ] && (cd "$ROOT" && find "$d" -maxdepth 1 -type f -name '*.md' | sort) >>"$CORPUS"
done
NFILES="$(grep -c . "$CORPUS" | tr -d ' ')"
[ "$NFILES" -ge 1 ] || blind "empty corpus"

# ── 1. structure: no @-mention of an account in the §11.4.297 blocks ─────────
block_of() { awk -v n="$2" 'BEGIN { pat = "^### §11\\.4\\." n "( |$)" } $0 ~ pat { p = 1; print; next } p && (/^### §/ || /^## /) { exit } p { print }' "$1"; }
carrier_block() {
    awk -v n="$2" 'BEGIN { s = "^(\\*\\*|### |- )§11\\.4\\." n "([^0-9]|$)"; g = "^(\\*\\*|### |- )§11\\.4\\.[0-9]|^## " }
        p && $0 ~ g { exit } !p && $0 ~ s { p = 1 } p { print }' "$1"
}
MENTION_RE='(^|[^A-Za-z0-9_`/.-])@[A-Za-z0-9][A-Za-z0-9-]*([^A-Za-z0-9-]|$)'
block_of "$CANON" "$N" >"$TMP/blk.txt"
if [ -s "$TMP/blk.txt" ]; then
    if grep -n -E -- "$MENTION_RE" "$TMP/blk.txt" >"$TMP/m.txt"; then fail "structure: the §11.4.$N canon block carries an @-mention: $(head -n1 "$TMP/m.txt")"
    else pass "structure: the §11.4.$N canon block carries no @-mention"; fi
else
    fail "structure: the §11.4.$N canon block is absent from Constitution.md"
fi
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    [ -f "$ROOT/$f" ] || { fail "structure: mirror $f missing"; continue; }
    carrier_block "$ROOT/$f" "$N" >"$TMP/cb.txt"
    if [ ! -s "$TMP/cb.txt" ]; then fail "structure: mirror $f carries no §11.4.$N block"
    elif grep -n -E -- "$MENTION_RE" "$TMP/cb.txt" >"$TMP/m.txt"; then fail "structure: mirror $f §11.4.$N block carries an @-mention: $(head -n1 "$TMP/m.txt")"
    else pass "structure: mirror $f §11.4.$N block carries no @-mention"; fi
done

# ── 2. the account scan ──────────────────────────────────────────────────────
if [ "$NLOGIN" -gt 0 ]; then
    while IFS= read -r login; do
        [ -n "$login" ] || continue
        found=0
        while IFS= read -r rel; do
            if hits "$ROOT/$rel" "$login" >"$TMP/h.txt"; then
                found=1
                while IFS= read -r h; do fail "account '$login' appears in $rel:${h%%:*}"; done <"$TMP/h.txt"
            fi
        done <"$CORPUS"
        [ "$found" = 0 ] && pass "account #$(grep -n -F -x -- "$login" "$LOGINS" | head -n1 | cut -d: -f1) of $NLOGIN appears in none of the $NFILES corpus files"
    done <"$LOGINS"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((NPASS + NFAIL))
if [ "$NFAIL" -gt 0 ]; then
    echo "$GATE: FAIL — $NFAIL of $TOTAL checks failed (root: $ROOT)"
    exit 1
fi
if [ "$NLOGIN" -eq 0 ]; then
    echo "$GATE: SKIP — no consumer reviewer list was found or given: the structure checks passed ($NPASS), the account scan did not run (not a PASS)"
    exit 3
fi
echo "$GATE: PASS — $NPASS/$TOTAL checks: $NLOGIN declared account(s) appear in none of the $NFILES corpus files (root: $ROOT)"
exit 0
