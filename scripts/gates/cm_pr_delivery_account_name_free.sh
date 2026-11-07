#!/usr/bin/env bash
# cm_pr_delivery_account_name_free.sh — gate CM-PR-DELIVERY-ACCOUNT-NAME-FREE (§11.4.297(D)(1), (H)(2))
#
# Purpose
#   §11.4.297 carries the reviewer RULE into the constitution and keeps the reviewer and assignee NAMES
#   out of it: account names are the consuming project's DATA (§11.4.17, §11.4.35). This gate proves it
#   for the accounts a consumer actually declares. It reads the consumer's reviewer and assignee accounts
#   AT RUN TIME from the consumer's own delivery configuration (never from this repository; this file and
#   its mutation test store no account name) and scans a corpus of the constitution for each one as a
#   whole account name, case-insensitively, in the raw text AND in a normalised form of it.
#
# The corpus (every file class the pull-request and release-gate rules added or changed)
#   the canon and its carriers: Constitution.md, CLAUDE.md, AGENTS.md, QWEN.md, GEMINI.md, README.md,
#     CHANGELOG.md, constitution_index.yaml;
#   the generated forms: groups/*.md, progressive/rules/*.md, progressive/catalog.json,
#     progressive/rules_manifest.json;
#   the gates, their tests and their registries: scripts/gates/cm_pr_delivery_*, scripts/gates/cm_release_gate_*,
#     the generated propagation gates scripts/gates/cm_covenant_114_297_* and cm_covenant_114_298_*,
#     scripts/gates/gate_ledger_deferrals.tsv, covenant_propagation_anchors.tsv, rule_seam_bindings.tsv,
#     docs/owed_gate_implementations.md, tests/test_post_update_hub_gates.sh, scripts/post_update_hook.sh,
#     config/full_suite_manifest.tsv, scripts/anchors/anchor_lib.py, scripts/anchors/tests/test_query_us2.py;
#   the guides: every docs/guides/**/*.md;
#   and, with --changed-since REV, every file git reports changed since REV (committed, staged, unstaged
#     and untracked-not-ignored), so a later pull request is scanned over exactly the files it touches.
#   The gate scans this corpus, NOT the whole tree: a PASS says nothing about files outside it.
#
# Normalisation (each step is exercised by its own control-needle line and its own mutant)
#   A line is a hit when the account is a whole word in the raw line OR in its normalised form. The
#   normalised form is: compatibility decomposition (NFKD: full-width and mathematical letters become ASCII),
#   format characters dropped (category Cf: zero-width space and joiners, soft hyphen, bidirectional marks,
#   byte-order mark), combining marks dropped (Mn, Me), letters of other scripts that imitate Latin ones
#   mapped to the Latin letter (a Cyrillic and Greek confusables table), and hyphen look-alikes mapped to '-'.
#   The raw scan stays, so normalisation only ever adds hits (an account followed by a sign that decomposes
#   into letters, such as a trademark sign, is still seen in the raw line).
#
# Consumer data (§11.4.35; all sources are read, none is required)
#   --consumer-config FILE   a delivery configuration of the consumer (key=value lines, '#' starts a
#                            comment); repeatable. Default when none is given: <root>/../config/delivery.conf
#                            if that file exists (the layout of a constitution checked out as a submodule).
#   --reviewers-key KEY      the key that holds the reviewer list (default pr_reviewers; a consumer may
#                            declare another name, §11.4.297(D)(1)). Present means mandatory: a consumer
#                            configuration without it is BLIND.
#   --assignees-key KEY      the key that holds the assignee list (default pr_assignees). Optional: an
#                            absent key is not an error; a present value that is not a list of account names
#                            is BLIND.
#   --forbid-login LOGIN     an account to scan for, in addition; repeatable.
#   --changed-since REV      add every file changed since REV to the corpus (needs git; an unreadable REV is BLIND).
#
# Usage
#   cm_pr_delivery_account_name_free.sh [--root <constitution-dir>] [--consumer-config FILE]...
#       [--reviewers-key KEY] [--assignees-key KEY] [--forbid-login LOGIN]... [--changed-since REV] [--quiet]
#
# Exit codes
#   0  PASS    at least one account was read and none appears in the corpus; the structure checks hold
#   1  FAIL    an account appears (file and line named) or a structure check failed
#   2  BLIND   a control needle failed, Constitution.md is absent, consumer data exists and cannot be read,
#              or --changed-since cannot be resolved
#   3  SKIP    no consumer account list exists (a constitution checked out on its own): the structure
#              checks ran, the account scan did not; never reported as PASS
#   64 usage error
#
# Instrument discipline (§11.4.273): before any verdict the matcher and the normaliser are run on synthetic
# text whose answer is known (a whole name is seen in each disguise the normaliser undoes and in another case,
# a longer name that contains it is not), and the configuration parser reads a known list and refuses a
# malformed one. Honest boundary (§11.4.6): only declared accounts can be scanned; an account name that is
# also a common word is reported wherever that word appears in the corpus; the raw scan counts every
# non-ASCII character as a boundary, so a name that directly touches a letter of another script is reported
# (the safe direction: a reported line is read, never silently passed); binary files are not scanned;
# the confusables table covers the Cyrillic and Greek letters that imitate Latin ones, not every script.
#
# Dependencies: bash, python3, awk, grep, sort, mktemp; git only for --changed-since. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
QUIET=0
GATE="CM-PR-DELIVERY-ACCOUNT-NAME-FREE"
N=297
KEY="pr_reviewers"
AKEY="pr_assignees"
SINCE=""
CONFIGS=()
EXTRA=()
CONFIG_GIVEN=0

usage() { echo "usage: ${0##*/} [--root DIR] [--consumer-config FILE]... [--reviewers-key KEY] [--assignees-key KEY] [--forbid-login LOGIN]... [--changed-since REV] [--quiet] | --help" >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --consumer-config) [ $# -ge 2 ] || usage; CONFIGS+=("$2"); CONFIG_GIVEN=1; shift 2 ;;
        --reviewers-key) [ $# -ge 2 ] || usage; KEY="$2"; shift 2 ;;
        --assignees-key) [ $# -ge 2 ] || usage; AKEY="$2"; shift 2 ;;
        --forbid-login) [ $# -ge 2 ] || usage; EXTRA+=("$2"); shift 2 ;;
        --changed-since) [ $# -ge 2 ] || usage; SINCE="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; exit 0 ;;
        *) usage ;;
    esac
done
[ -d "$ROOT" ] || { echo "$GATE: BLIND — root is not a directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
for k in "$KEY" "$AKEY"; do
    case "$k" in ''|*[!A-Za-z0-9_.-]*) echo "$GATE: usage — --reviewers-key and --assignees-key must be plain key names" >&2; exit 64 ;; esac
done
[ "$KEY" != "$AKEY" ] || { echo "$GATE: usage — the reviewer key and the assignee key must differ" >&2; exit 64; }
for _t in python3 awk grep sort mktemp; do
    command -v "$_t" >/dev/null 2>&1 || { echo "$GATE: BLIND — required tool '$_t' missing" >&2; exit 2; }
done

TMP="$(mktemp -d)" || { echo "$GATE: BLIND — mktemp failed" >&2; exit 2; }
trap 'rm -rf "${TMP:?}"' EXIT

NPASS=0; NFAIL=0
pass() { NPASS=$((NPASS + 1)); [ "$QUIET" = 1 ] || printf 'PASS  %s\n' "$*"; }
fail() { NFAIL=$((NFAIL + 1)); printf 'FAIL  %s\n' "$*"; }
blind() { echo "$GATE: BLIND — $*" >&2; exit 2; }

# ── the normaliser (one definition; the mutation test breaks each step on a copy) ──
NORM="$TMP/norm.py"
cat >"$NORM" <<'PYEOF'
import os, sys, unicodedata
CONF = {}
for _src, _dst in (('\u0430\u0435\u043e\u0440\u0441\u0443\u0445\u0456\u0458\u0455\u0501\u04bb\u04cf\u051b\u051d\u04af', 'aeopcyxijsdhlqwy'), ('\u0410\u0412\u0415\u041a\u041c\u041d\u041e\u0420\u0421\u0422\u0425\u0405\u0406\u0408', 'ABEKMHOPCTXSIJ'),
                   ('\u03b1\u03bf\u03c1\u03b9\u03c5\u03bd\u03ba', 'aopiuvk'), ('\u0391\u0392\u0395\u0396\u0397\u0399\u039a\u039c\u039d\u039f\u03a1\u03a4\u03a5\u03a7', 'ABEZHIKMNOPTYX'), ('\u0131\u0261\u0251', 'iga')):
    for _a, _b in zip(_src, _dst):
        CONF[ord(_a)] = _b
DASH = {0x2010: '-', 0x2011: '-', 0x2012: '-', 0x2212: '-', 0xFE63: '-'}
DROP = ('Cf', 'Mn', 'Me')
def norm(s):
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(ch for ch in s if unicodedata.category(ch) not in DROP)
    return s.translate(CONF).translate(DASH)
NEEDLE = ['line one names needle-login-a in prose.',
          'line two names Needle-Login-A in another case.',
          'line three names xneedle-login-a and needle-login-ab, which are other accounts.',
          'line four splits ne\u200bedle-login-a with a zero-width space.',
          'line five spells n\u0435edle-login-a with a Cyrillic letter.',
          'line six writes \uff4e\uff45\uff45\uff44\uff4c\uff45-login-a in full width.',
          'line seven marks ne\u0301edle-login-a with a combining accent.',
          'line eight writes needle\u2011login\u2011a with non-breaking hyphens.',
          'line nine writes needle-login-a\u2122 with a trademark sign.']
if sys.argv[1] == '--needle':
    with open(sys.argv[2], 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(NEEDLE) + '\n')
    sys.exit(0)
src, dst = sys.argv[1], sys.argv[2]
for rel in sys.stdin.read().split('\n'):
    if not rel:
        continue
    with open(os.path.join(src, rel), encoding='utf-8', errors='surrogateescape', newline='') as fh:
        raw = fh.read()
    out = os.path.join(dst, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8', errors='surrogateescape', newline='') as fh:
        fh.write('\n'.join(norm(line) for line in raw.split('\n')))
PYEOF
# normalise SRCROOT DSTROOT < list-of-relative-paths
normalise() { python3 -I "$NORM" "$1" "$2"; }

# ── the matcher and the parser (single definitions; the mutation test breaks them on a copy) ──
# An account name is a whole word of the class [A-Za-z0-9-]: nothing of that class touches it.
LOGIN_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'
GREP_CASE='-i'
# hits RAW NORMALISED LOGIN -> "line:text" lines where LOGIN occurs as a whole account name in either form
hits() {
    local re="(^|[^A-Za-z0-9-])$3([^A-Za-z0-9-]|\$)"
    { grep -I -n -E $GREP_CASE -- "$re" "$1"
      grep -I -n -E $GREP_CASE -- "$re" "$2"; } 2>/dev/null | sort -t: -k1,1n -s | awk -F: '!seen[$1]++'
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
NDOC="$TMP/needle/needle.txt"; mkdir -p "$TMP/needle" "$TMP/nneedle"
python3 -I "$NORM" --needle "$NDOC" || blind "the needle text could not be written"
printf '%s\n' needle.txt | normalise "$TMP/needle" "$TMP/nneedle" || blind "the normaliser failed on the needle text"
NHITS="$(hits "$NDOC" "$TMP/nneedle/needle.txt" needle-login-a | cut -d: -f1 | tr '\n' ' ')"
[ "$NHITS" = "1 2 4 5 6 7 8 9 " ] || blind "matcher control needle: expected whole-name hits on lines '1 2 4 5 6 7 8 9' (plain, case, zero-width, Cyrillic, full width, combining mark, non-breaking hyphen, trademark sign), got '$NHITS'"
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
NREV=0; NASG=0
for c in ${CONFIGS[@]+"${CONFIGS[@]}"}; do
    [ -f "$c" ] || blind "consumer configuration not found: $c"
    parse_conf "$c" "$KEY" >"$TMP/rev.txt"; rc=$?
    case "$rc" in
        0) ;;
        3) blind "consumer configuration $c carries no '$KEY' key (present means mandatory: pass --reviewers-key or --forbid-login)" ;;
        4) blind "consumer configuration $c: the '$KEY' value is not a list of account names" ;;
        *) blind "consumer configuration $c could not be read (awk exit $rc)" ;;
    esac
    parse_conf "$c" "$AKEY" >"$TMP/asg.txt"; rc=$?
    case "$rc" in
        0|3) ;;
        4) blind "consumer configuration $c: the '$AKEY' value is not a list of account names" ;;
        *) blind "consumer configuration $c could not be read (awk exit $rc)" ;;
    esac
    NREV=$((NREV + $(grep -c . "$TMP/rev.txt"))); NASG=$((NASG + $(grep -c . "$TMP/asg.txt")))
    cat "$TMP/rev.txt" "$TMP/asg.txt" >>"$LOGINS"
done
for l in ${EXTRA[@]+"${EXTRA[@]}"}; do
    printf '%s\n' "$l" | grep -E -q -- "$LOGIN_RE" || blind "--forbid-login value is not an account name: $l"
    printf '%s\n' "$l" >>"$LOGINS"
done
sort -u -f "$LOGINS" -o "$LOGINS"
NLOGIN="$(grep -c . "$LOGINS" | tr -d ' ')"

# ── the corpus ───────────────────────────────────────────────────────────────
CORPUS_FILES="Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md README.md CHANGELOG.md constitution_index.yaml
    progressive/catalog.json progressive/rules_manifest.json docs/owed_gate_implementations.md
    scripts/gates/gate_ledger_deferrals.tsv scripts/gates/covenant_propagation_anchors.tsv scripts/gates/rule_seam_bindings.tsv
    tests/test_post_update_hub_gates.sh scripts/post_update_hook.sh config/full_suite_manifest.tsv
    scripts/anchors/anchor_lib.py scripts/anchors/tests/test_query_us2.py"
CORPUS_GLOBS="scripts/gates/cm_pr_delivery_* scripts/gates/cm_release_gate_* scripts/gates/cm_covenant_114_297_* scripts/gates/cm_covenant_114_298_*"
CORPUS_MD_DIRS="groups progressive/rules docs/guides"
CORPUS="$TMP/corpus.txt"; : >"$CORPUS"
for f in $CORPUS_FILES; do
    [ -f "$ROOT/$f" ] && printf '%s\n' "$f" >>"$CORPUS"
done
(cd "$ROOT" && for f in $CORPUS_GLOBS; do [ -f "$f" ] && printf '%s\n' "$f"; done) >>"$CORPUS"
for d in $CORPUS_MD_DIRS; do
    [ -d "$ROOT/$d" ] && (cd "$ROOT" && find "$d" -type f -name '*.md') >>"$CORPUS"
done
NCHANGED=0
if [ -n "$SINCE" ]; then
    command -v git >/dev/null 2>&1 || blind "--changed-since needs git"
    git -C "$ROOT" rev-parse -q --verify "$SINCE^{commit}" >/dev/null 2>&1 || blind "--changed-since: '$SINCE' is not a commit of the repository at $ROOT"
    { git -C "$ROOT" diff --relative --name-only "$SINCE" -- && git -C "$ROOT" ls-files --others --exclude-standard; } >"$TMP/changed.txt" \
        || blind "--changed-since: git could not list the files changed since '$SINCE'"
    while IFS= read -r rel; do
        [ -n "$rel" ] && [ -f "$ROOT/$rel" ] && { printf '%s\n' "$rel" >>"$CORPUS"; NCHANGED=$((NCHANGED + 1)); }
    done <"$TMP/changed.txt"
fi
sort -u "$CORPUS" -o "$CORPUS"
NFILES="$(grep -c . "$CORPUS" | tr -d ' ')"
[ "$NFILES" -ge 1 ] || blind "empty corpus"
NROOT="$TMP/normalised"
normalise "$ROOT" "$NROOT" <"$CORPUS" || blind "the normaliser failed on the corpus"

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
    idx=0
    while IFS= read -r login; do
        [ -n "$login" ] || continue
        idx=$((idx + 1)); found=0
        while IFS= read -r rel; do
            hits "$ROOT/$rel" "$NROOT/$rel" "$login" >"$TMP/h.txt"
            if [ -s "$TMP/h.txt" ]; then
                found=1
                while IFS= read -r h; do fail "account '$login' appears in $rel:${h%%:*}"; done <"$TMP/h.txt"
            fi
        done <"$CORPUS"
        [ "$found" = 0 ] && pass "account #$idx of $NLOGIN appears in none of the $NFILES corpus files"
    done <"$LOGINS"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((NPASS + NFAIL))
SCOPE="$NFILES corpus files ($NCHANGED named by --changed-since${SINCE:+ $SINCE})"
if [ "$NFAIL" -gt 0 ]; then
    echo "$GATE: FAIL — $NFAIL of $TOTAL checks failed over $SCOPE (root: $ROOT)"
    exit 1
fi
if [ "$NLOGIN" -eq 0 ]; then
    echo "$GATE: SKIP — no consumer reviewer list was found or given: the structure checks passed ($NPASS), the account scan did not run (not a PASS)"
    exit 3
fi
echo "$GATE: PASS — $NPASS/$TOTAL checks: $NLOGIN declared account(s) ($NREV reviewer and $NASG assignee entries read) appear in none of the $SCOPE; files outside the corpus are not scanned (root: $ROOT)"
exit 0
