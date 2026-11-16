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
#     and untracked-not-ignored, listed NUL-separated with core.quotePath=false so any file name is read
#     exactly), the STAGED version of each such file when it differs from the working tree or the working-tree
#     file is gone (labelled index:<path>), the target text of a changed symbolic link (and the file it points
#     to when that lies inside the root), and the NAMES of the changed paths, so a later pull request is
#     scanned over exactly the files, versions and names it touches.
#   The gate scans this corpus, NOT the whole tree: a PASS says nothing about files outside it.
#
# Normalisation (the steps are exercised by control-needle lines and by gate mutants in the mutation test; audit 3
#   of 2026-11-07 found steps that no case discriminates yet: the U+01C0 mapping, the i side of the i/l class,
#   the upper-case Greek row and the U+2212 minus; they are open follow-ups, not claimed here)
#   A line is a hit when the account is a whole word in the raw line or in its normalised form, OR when its
#   skeleton pattern is a whole word in the skeleton form of the line. The normalised form is: compatibility
#   decomposition (NFKD: full-width and mathematical letters become ASCII), format characters dropped
#   (category Cf: zero-width space and joiners, soft hyphen, bidirectional marks, byte-order mark), combining
#   marks dropped (Mn, Me), the Hangul and Braille fillers dropped (U+115F, U+1160, U+3164, U+FFA0, U+2800:
#   letters or symbols that render as blank), the Cyrillic and Greek letters that imitate Latin letters or
#   digits mapped to them (a confusables table, applied before and after NFKD), and hyphen look-alikes mapped
#   to '-'. The skeleton form is the normalised form (with a long s mapped to f before NFKD, which would make
#   it s) lower-cased, with 0 mapped to o and 1, | and U+01C0 mapped to l only inside a word (a run of a-z,
#   0-9, '-', '|' and U+01C0) that holds a letter a-z, so a number such as 11.4, 2026-11-07 or 101 and a
#   shell || stay as they are (audit 3, B2: mapped everywhere, every section number and every || read as
#   two letters l); the skeleton
#   pattern of an account is the account lower-cased with 0 -> o and 1 -> l, where each i or l matches either
#   letter, so inside such a word a 1, a bar, an I or a Cyrillic or Greek look-alike of i or l is seen as
#   either letter, and a 0 or a look-alike of o as o. The raw scan stays,
#   so normalisation only ever adds hits (an account followed by a sign that decomposes into letters, such as
#   a trademark sign, is still seen in the raw line).
#
# Consumer data (§11.4.35; all sources are read, none is required)
#   --consumer-config FILE   a delivery configuration of the consumer (key=value lines, '#' starts a
#                            comment); repeatable. Default when none is given: every one of
#                            <root>/config/delivery.conf (a constitution that is its own consumer,
#                            CON-PENDINGprgate) and <root>/../config/delivery.conf (a constitution checked
#                            out as a submodule; the parent of the root path AS GIVEN, so a symlinked layout reads
#                            its logical parent) that exists; both are read when both exist. Every configuration
#                            read must be a regular file, NOT a symbolic link, in a directory named config, and,
#                            when it lies inside the root, exactly <root>/config/<name>; otherwise the gate is
#                            BLIND (a data file passed as a configuration is never left out of the scan). Keys
#                            other than the reviewer and assignee keys are not read; a key outside the known list
#                            (the §11.4.297(A) keys plus the extension keys pr_repository, pr_assignees,
#                            decision_date, decision_id_round2, own_repositories, author_only_reviewer_policy,
#                            go_record_location) is named in a NOTE and never refused.
#   --reviewers-key KEY      the key that holds the reviewer list (default pr_reviewers; a consumer may
#                            declare another name, §11.4.297(D)(1)). Present means mandatory: a consumer
#                            configuration without it, or with it present and empty, is BLIND.
#   --assignees-key KEY      the key that holds the assignee list (default pr_assignees). Optional: an
#                            absent key or an empty value is not an error; a present value that is not a list
#                            of account names is BLIND.
#   --forbid-login LOGIN     an account to scan for, in addition; repeatable.
#   --changed-since REV      add every file changed since REV to the corpus (needs git; an unreadable REV is BLIND).
#                            One kind of changed file is left out, named in the output and counted in the verdict:
#                            a consumer configuration the gate READ in this run, matched when the changed path is
#                            itself not a symbolic link and its resolved path EQUALS (never prefixes, never shares a
#                            directory or a name with) the resolved path of a configuration read (it is the one
#                            file that must hold the names; its staged version is left out with it). A file that
#                            starts with the 16-byte SQLite header "SQLite format 3\0" is opened read-only as an
#                            SQLite database (a copy, with any -wal file) and every text and BLOB cell and the
#                            schema text are scanned (round 3: the header alone is never trusted); a file with that
#                            header that cannot be opened as a database is BLIND, and a PASS names every database
#                            scanned this way. A changed symbolic link that points outside the root, a listed path
#                            that cannot be read, and any other changed file with a NUL byte are BLIND; a file of
#                            the fixed corpus is never left out.
#
# Usage
#   cm_pr_delivery_account_name_free.sh [--root <constitution-dir>] [--consumer-config FILE]...
#       [--reviewers-key KEY] [--assignees-key KEY] [--forbid-login LOGIN]... [--changed-since REV] [--quiet]
#
# Exit codes
#   0  PASS    at least one account was read and none appears in the scanned corpus; the structure checks
#              hold (the verdict names the files --changed-since left out and why)
#   1  FAIL    an account appears (file and line named) or a structure check failed
#   2  BLIND   a control needle failed, Constitution.md is absent, consumer data exists and cannot be read,
#              the reviewer list is present and empty, a corpus file holds a NUL byte (grep would read it as
#              binary and scan nothing in it), or --changed-since cannot be resolved
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
# (the safe direction: a reported line is read, never silently passed), and the skeleton form over-reports in
# the same safe direction (an account with an l is also reported where an i stands for it, and the other way round);
# a 0, a 1 or a bar is read as a letter only inside a word that holds a letter, so a name of the letters l, i and o
# written with digits or bars only is seen only in its raw form, and a disguised name glued to a table bar
# with no space between (the bar reads as l and joins the word) is not seen in the skeleton form; a corpus file
# with a NUL byte makes the gate BLIND instead of being skipped as binary; the confusables table covers the
# Cyrillic and Greek letters that imitate Latin letters and digits, not every script: letters of other scripts
# (Armenian, Cherokee, Canadian syllabics, Lisu and others), Latin small capitals and other Latin look-alikes,
# symbols (such as APL), a bidirectional reordering, a character reference or percent-encoding and markup that
# splits a name are NOT undone (the reviewer's round-2 fool cases URL-encoding, a name split across lines
# and HTML entities stay documented limits, not fixed). A SQLite database is read through its cells, not its
# pages: text kept only in free pages or a -journal file is not seen. A symbolic link pointing outside the root
# is BLIND, not followed.
#
# Dependencies: bash, python3, awk, grep, sort, mktemp, readlink, head, cmp, cp, tr, wc, cut, basename, dirname; git only for --changed-since. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
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
for _t in python3 awk grep sort mktemp readlink head cmp cp tr wc cut basename dirname; do
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
import os, re, sys, unicodedata
CONF = {}
for _src, _dst in (('\u0430\u0435\u043e\u0440\u0441\u0443\u0445\u0456\u0458\u0455\u0501\u04bb\u04cf\u051b\u051d\u04af', 'aeopcyxijsdhlqwy'), ('\u0410\u0412\u0415\u041a\u041c\u041d\u041e\u0420\u0421\u0422\u0425\u0405\u0406\u0408', 'ABEKMHOPCTXSIJ'),
                   ('\u03b1\u03bf\u03c1\u03b9\u03c5\u03bd\u03ba', 'aopiuvk'), ('\u0391\u0392\u0395\u0396\u0397\u0399\u039a\u039c\u039d\u039f\u03a1\u03a4\u03a5\u03a7', 'ABEZHIKMNOPTYX'), ('\u0131\u0261\u0251', 'iga'),
                   ('\u043a\u043c\u0442\u043f\u0433\u0475\u0461\u04bd\u0437\u0431\u04c0\u0417', 'kmtnrvwe36I3'), ('\u03f2\u03f3\u03b3\u03c7', 'cjyx')):
    for _a, _b in zip(_src, _dst):
        CONF[ord(_a)] = _b
DASH = {0x2010: '-', 0x2011: '-', 0x2012: '-', 0x2212: '-', 0xFE63: '-'}
DROP = ('Cf', 'Mn', 'Me')
FILL = (0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800)
SKEL_PRE = {0x017F: 'f'}
SKEL_MAP = {ord('0'): 'o', ord('1'): 'l', ord('|'): 'l', 0x01C0: 'l'}
SKEL_DIGITS = {k: v for k, v in SKEL_MAP.items() if chr(k).isdigit()}
SKEL_BARS = {k: v for k, v in SKEL_MAP.items() if not chr(k).isdigit()}
SKEL_WORD = re.compile('[a-z0-9|\u01c0-]+')
SKEL_LETTER = re.compile('[a-z]')
def norm(s):
    # the table is applied before NFKD too: some look-alikes decompose into a letter the table does not list
    # (U+03F2 GREEK LUNATE SIGMA SYMBOL becomes U+03C2 under NFKD)
    s = unicodedata.normalize('NFKD', s.translate(CONF))
    s = ''.join(ch for ch in s if unicodedata.category(ch) not in DROP and ord(ch) not in FILL)
    return s.translate(CONF).translate(DASH)
def skel_word(m):
    # a 0, a 1 or a bar stands for a letter only inside a word that holds a letter (a bar is part of the word, not
    # a letter): a number such as 11.4, 2026-11-07 or 101 and a shell || stay as they are (audit 3, B2)
    w = m.group(0)
    return w.translate(SKEL_DIGITS).translate(SKEL_BARS) if SKEL_LETTER.search(w) else w
def skel(s):
    return SKEL_WORD.sub(skel_word, norm(s.translate(SKEL_PRE)).lower())
def skel_login(s):
    # the account as a pattern over the skeleton form: i and l both match [il], so an I, a 1, a | or a look-alike
    # of either letter is seen whichever of the two it stands for
    return ''.join('[il]' if ch in 'il' else ch for ch in s.lower().translate(SKEL_MAP))
NEEDLE = ['line one names needle-login-a in prose.',
          'line two names Needle-Login-A in another case.',
          'line three names xneedle-login-a and needle-login-ab, which are other accounts.',
          'line four splits ne\u200bedle-login-a with a zero-width space.',
          'line five spells n\u0435edle-login-a with a Cyrillic letter.',
          'line six writes \uff4e\uff45\uff45\uff44\uff4c\uff45-login-a in full width.',
          'line seven marks ne\u0301edle-login-a with a combining accent.',
          'line eight writes needle\u2011login\u2011a with non-breaking hyphens.',
          'line nine writes Needle-Login-A\u2122 with a trademark sign, in another case.',
          'line ten writes needle-\u0406ogin-a with a Cyrillic letter for l.',
          'line eleven splits nee\u3164dle-login-a with a Hangul filler.',
          'line twelve splits needle-lo\u2800gin-a with a Braille blank.',
          'line thirteen spells \u043feedle-login-a with a Cyrillic pe.',
          'line fourteen writes needle-\u04cf\u041e with Cyrillic letters for the digits of the second needle.',
          'line fifteen names needle-10x, another account.',
          'line sixteen writes needle-\u03f2\u017f with a lunate sigma for c (it decomposes into a final sigma) and a long s for f.',
          'line seventeen spells n\u0451edle-login-a with a Cyrillic io (it decomposes into a Cyrillic e and a mark).',
          'line eighteen writes |n\u0435edle-login-a| in a table cell without spaces (the skeleton reads each bar as an l).',
          'line nineteen cites \u00a711.4.297, 2026-11-07, the serial 101-100-011 and the rule ||-|||: numbers and bars, never accounts.',
          'line twenty writes needle-l0gin-a with a zero for o.']
if sys.argv[1] == '--needle':
    with open(sys.argv[2], 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(NEEDLE) + '\n')
    sys.exit(0)
if sys.argv[1] == '--skel-login':
    print(skel_login(sys.argv[2]))
    sys.exit(0)
if sys.argv[1] == '--sqlite-dump':
    # --sqlite-dump DB OUT: write every text and BLOB cell of every table, and the schema text, one cell per line
    # (a NUL becomes a space). Exit 3 when the file cannot be read as an SQLite database (the caller is BLIND).
    import sqlite3
    db, out = sys.argv[2], sys.argv[3]
    try:
        con = sqlite3.connect('file:' + db + '?mode=ro', uri=True)
        con.text_factory = lambda b: b.decode('utf-8', errors='surrogateescape')
        cells = []
        tables = []
        for typ, name, tbl, sql in con.execute('select type, name, tbl_name, sql from sqlite_master'):
            cells.extend(x for x in (name, tbl, sql) if isinstance(x, str))
            if typ == 'table':
                tables.append(name)
        for name in tables:
            for row in con.execute('select * from "%s"' % name.replace('"', '""')):
                for v in row:
                    if isinstance(v, bytes):
                        v = v.decode('utf-8', errors='surrogateescape')
                    if isinstance(v, str):
                        cells.append(v)
        con.close()
    except (sqlite3.Error, OSError) as e:
        sys.stderr.write('%s\n' % e); sys.exit(3)
    with open(out, 'w', encoding='utf-8', errors='surrogateescape', newline='') as fh:
        for v in cells:
            fh.write(v.replace('\x00', ' ') + '\n')
    sys.exit(0)
# normaliser: DST SKELDST MANIFEST < NUL-separated records "label\0absolute-path\0"; writes the normalised and the
# skeleton form of record i to DST/i and SKELDST/i, writes the NUL-separated manifest "i\0label\0path\0" and prints
# the label (control characters shown as '?') of every file that holds a NUL byte (grep would read it as binary)
dst, sdst, manifest = sys.argv[1], sys.argv[2], sys.argv[3]
data = sys.stdin.buffer.read().split(b'\0')
recs = [(data[k], data[k + 1]) for k in range(0, len(data) - 1, 2)]
os.makedirs(dst, exist_ok=True); os.makedirs(sdst, exist_ok=True)
with open(manifest, 'wb') as man:
    for i, (lab, path) in enumerate(recs):
        label = re.sub('[\x00-\x1f\x7f]', '?', lab.decode('utf-8', errors='replace'))
        with open(path, 'rb') as fh:
            raw = fh.read().decode('utf-8', errors='surrogateescape')
        if '\x00' in raw:
            print(label)
        for root, fn in ((dst, norm), (sdst, skel)):
            with open(os.path.join(root, str(i)), 'w', encoding='utf-8', errors='surrogateescape', newline='') as fh:
                fh.write('\n'.join(fn(line) for line in raw.split('\n')))
        man.write(str(i).encode() + b'\0' + label.encode('utf-8', errors='surrogateescape') + b'\0' + path + b'\0')
PYEOF
# normalise DSTROOT SKELROOT MANIFEST < NUL-separated "label\0path\0" records -> the labels of the files that hold a NUL byte
normalise() { python3 -I "$NORM" "$1" "$2" "$3"; }
# skel_login LOGIN -> the account as a pattern over the skeleton form (lower case, 0 -> o, 1 -> l, i and l -> [il])
skel_login() { python3 -I "$NORM" --skel-login "$1"; }

# ── the matcher and the parser (single definitions; the mutation test breaks them on a copy) ──
# An account name is a whole word of the class [A-Za-z0-9-]: nothing of that class touches it.
LOGIN_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'
GREP_CASE='-i'
# hits RAW NORMALISED SKELETON LOGIN LOGIN-PATTERN -> "line:text" lines where LOGIN occurs as a whole account name
# in the raw or the normalised form, or LOGIN-PATTERN (skel_login) in the skeleton form
hits() {
    local re="(^|[^A-Za-z0-9-])$4([^A-Za-z0-9-]|\$)" rs="(^|[^A-Za-z0-9-])$5([^A-Za-z0-9-]|\$)"
    { grep -I -n -E $GREP_CASE -- "$re" "$1"
      grep -I -n -E $GREP_CASE -- "$re" "$2"
      grep -I -n -E $GREP_CASE -- "$rs" "$3"; } 2>/dev/null | sort -t: -k1,1n -s | awk -F: '!seen[$1]++'
}
# parse_conf FILE KEY -> one account per line on stdout; exit 3 when the key is absent, 4 when a value is malformed,
# 5 when the key is present and lists no account
parse_conf() {
    awk -v key="$2" '
        { line = $0; sub(/#.*/, "", line) }
        line ~ "^[ \t]*" key "[ \t]*=" {
            found = 1; sub("^[ \t]*" key "[ \t]*=", "", line)
            n = split(line, parts, /[ \t,]+/)
            for (i = 1; i <= n; i++) { if (parts[i] == "") continue; if (parts[i] !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/ || length(parts[i]) > 39) bad = 1; else { print parts[i]; cnt++ } }
        }
        END { if (!found) exit 3; if (bad) exit 4; if (!cnt) exit 5 }
    ' "$1"
}

# ── control needles (§11.4.273) ──────────────────────────────────────────────
NDOC="$TMP/needle/needle.txt"; mkdir -p "$TMP/needle" "$TMP/nneedle" "$TMP/sneedle"
python3 -I "$NORM" --needle "$NDOC" || blind "the needle text could not be written"
printf '%s\0' needle.txt "$NDOC" | normalise "$TMP/nneedle" "$TMP/sneedle" "$TMP/needle.man" >/dev/null || blind "the normaliser failed on the needle text"
NHITS="$(hits "$NDOC" "$TMP/nneedle/0" "$TMP/sneedle/0" needle-login-a "$(skel_login needle-login-a)" | cut -d: -f1 | tr '\n' ' ')"
[ "$NHITS" = "1 2 4 5 6 7 8 9 10 11 12 13 17 18 20 " ] || blind "matcher control needle: expected whole-name hits on lines '1 2 4 5 6 7 8 9 10 11 12 13 17 18 20' (plain, case, zero-width, Cyrillic, full width, combining mark, non-breaking hyphen, trademark sign in another case, a Cyrillic letter for l, a Hangul filler, a Braille blank, a Cyrillic pe, a Cyrillic io, a disguised name between bars, a zero for o inside the name), got '$NHITS'"
NHITS="$( { hits "$NDOC" "$TMP/nneedle/0" "$TMP/sneedle/0" lol-loo-oll "$(skel_login lol-loo-oll)"; hits "$NDOC" "$TMP/nneedle/0" "$TMP/sneedle/0" ll-lll "$(skel_login ll-lll)"; } | cut -d: -f1 | tr '\n' ' ')"
[ -z "$NHITS" ] || blind "number control needle: the serial 101-100-011 or the rule ||-||| was read as the account lol-loo-oll or ll-lll on line(s) '$NHITS': a 0, a 1 or a bar is a letter only inside a word that holds a letter"
NHITS="$(hits "$NDOC" "$TMP/nneedle/0" "$TMP/sneedle/0" needle-10 "$(skel_login needle-10)" | cut -d: -f1 | tr '\n' ' ')"
[ "$NHITS" = "14 " ] || blind "skeleton control needle: expected the second needle (digits written as Cyrillic letters) on line '14' only, got '$NHITS'"
NHITS="$(hits "$NDOC" "$TMP/nneedle/0" "$TMP/sneedle/0" needle-cf "$(skel_login needle-cf)" | cut -d: -f1 | tr '\n' ' ')"
[ "$NHITS" = "16 " ] || blind "table-before-NFKD and long-s control needle: expected the third needle (a lunate sigma for c, a long s for f) on line '16' only, got '$NHITS'"
printf 'clean line\nnul line \000 here\n' >"$TMP/needle/nul.txt"
[ "$(printf '%s\0' nul.txt "$TMP/needle/nul.txt" needle.txt "$NDOC" | normalise "$TMP/nneedle2" "$TMP/sneedle2" "$TMP/needle2.man")" = "nul.txt" ] || blind "NUL control needle: a file with a NUL byte was not reported (or a clean file was)"
NCONF="$TMP/needle.conf"
printf '%s\n' '# comment pr_reviewers=commented-out' 'mode=pr' "$KEY=needle-one, needle-two # trailing comment" >"$NCONF"
[ "$(parse_conf "$NCONF" "$KEY" | tr '\n' ' ')" = "needle-one needle-two " ] || blind "parser control needle: the known list was not read as 'needle-one needle-two'"
printf '%s\n' "$KEY=bad/login" >"$TMP/bad.conf"
parse_conf "$TMP/bad.conf" "$KEY" >/dev/null 2>&1; [ $? -eq 4 ] || blind "parser control needle: a malformed value was not refused"
printf '%s\n' 'mode=pr' >"$TMP/nokey.conf"
parse_conf "$TMP/nokey.conf" "$KEY" >/dev/null 2>&1; [ $? -eq 3 ] || blind "parser control needle: an absent key was not reported"
printf '%s\n' "$KEY=  # nothing listed" >"$TMP/empty.conf"
parse_conf "$TMP/empty.conf" "$KEY" >/dev/null 2>&1; [ $? -eq 5 ] || blind "parser control needle: a present but empty list was not reported"

python3 -I -c 'import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("create table t(x text, y blob)"); c.execute("insert into t values (?, ?)", ("row names needle-login-a here", b"blob names needle-login-b")); c.commit()' "$TMP/needle.db" \
    && python3 -I "$NORM" --sqlite-dump "$TMP/needle.db" "$TMP/needle.db.txt" 2>/dev/null \
    && grep -q 'needle-login-a' "$TMP/needle.db.txt" && grep -q 'needle-login-b' "$TMP/needle.db.txt" \
    || blind "SQLite control needle: a text cell and a BLOB cell of a known database were not read"
printf 'SQLite format 3\000 not a database, names needle-login-a\n' >"$TMP/fake.db"
python3 -I "$NORM" --sqlite-dump "$TMP/fake.db" "$TMP/fake.db.txt" 2>/dev/null; [ $? -eq 3 ] || blind "SQLite control needle: a text file that starts with the SQLite header was not refused as a database"

CANON="$ROOT/Constitution.md"
[ -f "$CANON" ] || blind "Constitution.md not found under $ROOT"

# ── consumer accounts ────────────────────────────────────────────────────────
# The parent is taken from the path string (dirname), not by resolving "..", so a constitution reached through a
# symlinked layout still finds the configuration of the project that holds it.
# A constitution that is its own consumer declares at <root>/config/delivery.conf; both defaults are read.
if [ "$CONFIG_GIVEN" = 0 ]; then
    for _d in "$ROOT/config/delivery.conf" "$(dirname "$ROOT")/config/delivery.conf"; do
        [ -e "$_d" ] && CONFIGS+=("$_d")
    done
    unset _d
fi
ROOT_REAL="$(readlink -f -- "$ROOT")" || blind "the root cannot be resolved: $ROOT"
# A configuration that is read MUST be a regular file that is not a symbolic link, whose resolved parent directory
# is named config, and, when it lies inside the root, is <root>/config/<name>: the one file --changed-since leaves
# out can then never be a data file elsewhere in the tree (a symlink or a --consumer-config pointing at evidence).
CONF_REALS=()
for c in ${CONFIGS[@]+"${CONFIGS[@]}"}; do
    [ -e "$c" ] || [ -L "$c" ] || blind "consumer configuration not found: $c"
    [ -L "$c" ] && blind "consumer configuration $c is a symbolic link: name the real file"
    [ -f "$c" ] || blind "consumer configuration $c is not a regular file"
    [ -r "$c" ] || blind "consumer configuration $c cannot be read"
    _r="$(readlink -f -- "$c")" || blind "consumer configuration $c cannot be resolved"
    case "$_r" in *$'\n'*) blind "consumer configuration $c resolves to a path with a newline" ;; esac
    [ "$(basename -- "$(dirname -- "$_r")")" = config ] || blind "consumer configuration $c does not lie in a directory named config (it resolves to $_r)"
    case "$_r" in
        "$ROOT_REAL"/*) [ "$(dirname -- "$_r")" = "$ROOT_REAL/config" ] || blind "consumer configuration $c lies inside the root but not in <root>/config/ (it resolves to $_r)" ;;
    esac
    CONF_REALS+=("$_r")
done
unset _r
# is_read_config ABSOLUTE-PATH -> 0 when the path is not a symbolic link and resolves EXACTLY to a configuration read in this run
is_read_config() {
    local p="$1" r x
    [ -L "$p" ] && return 1
    [ -f "$p" ] || return 1
    r="$(readlink -f -- "$p")" || return 1
    for x in ${CONF_REALS[@]+"${CONF_REALS[@]}"}; do [ "$r" = "$x" ] && return 0; done
    return 1
}
# Known keys (§11.4.297(A) and the declared extension keys). Any other key is named in a NOTE and never refuses;
# only the reviewer and assignee keys are read as accounts.
KNOWN_KEYS=" mode base pr_remote branch_prefix pr_reviewers landing_form merger protected_branches direct_push_guard shared_single_files tool_written_paths evidence_dir merge_window_hours pr_repository pr_assignees decision_id decision_date decision_id_round2 own_repositories author_only_reviewer_policy go_record_location $KEY $AKEY "
LOGINS="$TMP/logins.txt"; : >"$LOGINS"
NREV=0; NASG=0; UNKNOWN_KEYS=""
for c in ${CONFIGS[@]+"${CONFIGS[@]}"}; do
    parse_conf "$c" "$KEY" >"$TMP/rev.txt"; rc=$?
    case "$rc" in
        0) ;;
        3) blind "consumer configuration $c carries no '$KEY' key (present means mandatory: pass --reviewers-key or --forbid-login)" ;;
        4) blind "consumer configuration $c: the '$KEY' value is not a list of account names" ;;
        5) blind "consumer configuration $c: the '$KEY' value is empty (an empty reviewer list is refused, §11.4.297(D)(1); present means mandatory)" ;;
        *) blind "consumer configuration $c could not be read (awk exit $rc)" ;;
    esac
    parse_conf "$c" "$AKEY" >"$TMP/asg.txt"; rc=$?
    case "$rc" in
        0|3|5) ;;
        4) blind "consumer configuration $c: the '$AKEY' value is not a list of account names" ;;
        *) blind "consumer configuration $c could not be read (awk exit $rc)" ;;
    esac
    NREV=$((NREV + $(grep -c . "$TMP/rev.txt"))); NASG=$((NASG + $(grep -c . "$TMP/asg.txt")))
    cat "$TMP/rev.txt" "$TMP/asg.txt" >>"$LOGINS"
    for k in $(awk '{ l = $0; sub(/#.*/, "", l) } l ~ /^[ \t]*[A-Za-z0-9_.-]+[ \t]*=/ { sub(/^[ \t]*/, "", l); sub(/[ \t]*=.*/, "", l); print l }' "$c"); do
        case "$KNOWN_KEYS" in *" $k "*) ;; *) UNKNOWN_KEYS="$UNKNOWN_KEYS $k" ;; esac
    done
done
[ -n "$UNKNOWN_KEYS" ] && [ "$QUIET" != 1 ] && echo "NOTE  keys not in the known list (not read, not refused):$UNKNOWN_KEYS"
for l in ${EXTRA[@]+"${EXTRA[@]}"}; do
    printf '%s\n' "$l" | grep -E -q -- "$LOGIN_RE" || blind "--forbid-login value is not an account name: $l"
    printf '%s\n' "$l" >>"$LOGINS"
done
sort -u -f "$LOGINS" -o "$LOGINS"
NLOGIN="$(grep -c . "$LOGINS" | tr -d ' ')"

# ── the corpus ───────────────────────────────────────────────────────────────
# The scan list holds NUL-separated records "label\0absolute-path\0" (labels and paths may hold any byte but NUL).
CORPUS_FILES="Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md README.md CHANGELOG.md constitution_index.yaml
    progressive/catalog.json progressive/rules_manifest.json docs/owed_gate_implementations.md
    scripts/gates/gate_ledger_deferrals.tsv scripts/gates/covenant_propagation_anchors.tsv scripts/gates/rule_seam_bindings.tsv
    tests/test_post_update_hub_gates.sh scripts/post_update_hook.sh config/full_suite_manifest.tsv
    scripts/anchors/anchor_lib.py scripts/anchors/tests/test_query_us2.py"
CORPUS_GLOBS="scripts/gates/cm_pr_delivery_* scripts/gates/cm_release_gate_* scripts/gates/cm_covenant_114_297_* scripts/gates/cm_covenant_114_298_*"
CORPUS_MD_DIRS="groups progressive/rules docs/guides"
FIXED="$TMP/fixed.z"; : >"$FIXED"
for f in $CORPUS_FILES; do
    [ -f "$ROOT/$f" ] && printf '%s\0' "$f" >>"$FIXED"
done
(cd "$ROOT" && for f in $CORPUS_GLOBS; do [ -f "$f" ] && printf '%s\0' "$f"; done) >>"$FIXED"
for d in $CORPUS_MD_DIRS; do
    [ -d "$ROOT/$d" ] && (cd "$ROOT" && find "$d" -type f -name '*.md' -print0) >>"$FIXED"
done
sort -z -u "$FIXED" -o "$FIXED"
SCAN="$TMP/scan.z"; : >"$SCAN"
add_scan() { printf '%s\0%s\0' "$1" "$2" >>"$SCAN"; }
NFIXED=0
while IFS= read -r -d '' rel; do add_scan "$rel" "$ROOT/$rel"; NFIXED=$((NFIXED + 1)); done <"$FIXED"
in_fixed() { local x; while IFS= read -r -d '' x; do [ "$x" = "$1" ] && return 0; done <"$FIXED"; return 1; }
NCHANGED=0; NEXCL=0; NSQL=0; NIDX=0; NNAMES=0; EXCL_LIST=""; SQL_LIST=""
SQLITE_MAGIC="$TMP/sqlite_magic"; printf 'SQLite format 3\000' >"$SQLITE_MAGIC"
# sqlite_text SRC LABEL -> a text file of SRC's cells added to the scan; BLIND when SRC cannot be read as a database
sqlite_text() {
    local k="$TMP/sql/$NSQL"
    mkdir -p "$TMP/sql"; cp -- "$1" "$k.db" || blind "cannot copy the SQLite file $2"
    [ -f "$1-wal" ] && { cp -- "$1-wal" "$k.db-wal" || blind "cannot copy the write-ahead log of $2"; }
    python3 -I "$NORM" --sqlite-dump "$k.db" "$k.txt" 2>"$k.err" || blind "$2 starts with the SQLite header but cannot be read as an SQLite database ($(head -c 200 "$k.err" | tr '\n' ' ')): its text is not scanned"
    add_scan "$2 (SQLite text cells)" "$k.txt"
    NSQL=$((NSQL + 1)); SQL_LIST="$SQL_LIST $2"
    [ "$QUIET" = 1 ] || echo "NOTE  scanned as its SQLite text cells: $2"
}
# add_content SRC LABEL -> scan SRC as text, or as its SQLite text cells when it starts with the SQLite header
add_content() {
    if head -c 16 -- "$1" | cmp -s - "$SQLITE_MAGIC"; then sqlite_text "$1" "$2"; else add_scan "$2" "$1"; fi
}
if [ -n "$SINCE" ]; then
    command -v git >/dev/null 2>&1 || blind "--changed-since needs git"
    git -C "$ROOT" rev-parse -q --verify "$SINCE^{commit}" >/dev/null 2>&1 || blind "--changed-since: '$SINCE' is not a commit of the repository at $ROOT"
    # worktree and index against REV, the index against REV, and untracked-not-ignored files; NUL-separated and
    # unquoted, so a name with a newline, a tab, a quote or a non-ASCII byte is listed as it is
    { git -C "$ROOT" -c core.quotePath=false diff -z --relative --name-only "$SINCE" -- \
      && git -C "$ROOT" -c core.quotePath=false diff -z --cached --relative --name-only "$SINCE" -- \
      && git -C "$ROOT" -c core.quotePath=false ls-files -z --others --exclude-standard; } >"$TMP/changed.z" \
        || blind "--changed-since: git could not list the files changed since '$SINCE'"
    sort -z -u "$TMP/changed.z" -o "$TMP/changed.z"
    NAMES="$TMP/names.txt"; : >"$NAMES"
    mkdir -p "$TMP/idx"
    while IFS= read -r -d '' rel; do
        [ -n "$rel" ] || continue
        # the changed path NAME is scanned too (a name can carry an account); control characters become spaces
        printf '%s\n' "${rel//[$'\001'-$'\037']/ }" >>"$NAMES"; NNAMES=$((NNAMES + 1))
        p="$ROOT/$rel"
        if is_read_config "$p"; then
            # its staged version is the same configuration file and holds the names too
            NEXCL=$((NEXCL + 1)); EXCL_LIST="$EXCL_LIST $rel"
            [ "$QUIET" = 1 ] || echo "NOTE  excluded from --changed-since: $rel (a consumer configuration read in this run: it holds the account names)"
            continue
        fi
        # the staged content, when it differs from the working tree (or the working-tree file is gone)
        _ls="$(git -C "$ROOT" ls-files -z -s -- ":(literal)$rel" | tr '\0' '\n' | head -n 1)" \
            || blind "--changed-since: git could not read the index entry of a changed path"
        if [ -n "$_ls" ]; then
            _mode="${_ls%% *}"; _obj="${_ls#* }"; _obj="${_obj%% *}"
            if [ "$_mode" != 160000 ]; then
                git -C "$ROOT" cat-file blob "$_obj" >"$TMP/idx/$NIDX" || blind "--changed-since: git could not read the staged content of a changed path"
                if [ -L "$p" ] || [ ! -f "$p" ] || ! cmp -s -- "$TMP/idx/$NIDX" "$p"; then
                    add_content "$TMP/idx/$NIDX" "index:$rel"; NIDX=$((NIDX + 1))
                fi
            fi
        fi
        # a fixed-corpus file is already scanned as it is (never as SQLite cells, never left out)
        in_fixed "$rel" && continue
        if [ -L "$p" ]; then
            # a symbolic link is never followed into an exclusion: its target text is scanned, and a target inside the
            # root is scanned as content; a target outside the root is BLIND
            _t="$(readlink -- "$p")"; printf '%s\n' "${_t//[$'\001'-$'\037']/ }" >"$TMP/idx/link$NCHANGED"
            add_scan "$rel (symbolic link target)" "$TMP/idx/link$NCHANGED"
            _tr="$(readlink -f -- "$p")" || _tr=""
            if [ -n "$_tr" ] && [ -f "$_tr" ]; then
                case "$_tr" in
                    "$ROOT_REAL"/*) add_content "$_tr" "$rel -> ${_tr#"$ROOT_REAL"/}" ;;
                    *) blind "--changed-since: the changed symbolic link $rel points outside the root ($_tr); its content is not scanned" ;;
                esac
            fi
            NCHANGED=$((NCHANGED + 1)); continue
        fi
        [ -e "$p" ] || continue
        [ -d "$p" ] && continue
        [ -f "$p" ] && [ -r "$p" ] || blind "--changed-since: the changed path $rel cannot be read"
        add_content "$p" "$rel"; NCHANGED=$((NCHANGED + 1))
    done <"$TMP/changed.z"
    add_scan "(names of the paths changed since $SINCE)" "$NAMES"
fi
NFILES="$(tr -cd '\0' <"$SCAN" | wc -c)"; NFILES=$((NFILES / 2))
[ "$NFILES" -ge 1 ] || blind "empty corpus"
NROOT="$TMP/normalised"; SROOT="$TMP/skeleton"; MAN="$TMP/manifest.z"
normalise "$NROOT" "$SROOT" "$MAN" <"$SCAN" >"$TMP/nul.txt" || blind "the normaliser failed on the corpus"
[ -s "$TMP/nul.txt" ] && blind "$(grep -c . "$TMP/nul.txt") corpus file(s) hold a NUL byte, so grep would read them as binary and scan nothing in them: $(head -n 3 "$TMP/nul.txt" | tr '\n' ' ')"

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
        idx=$((idx + 1)); found=0; lskel="$(skel_login "$login")"
        while IFS= read -r -d '' i && IFS= read -r -d '' rel && IFS= read -r -d '' src; do
            hits "$src" "$NROOT/$i" "$SROOT/$i" "$login" "$lskel" >"$TMP/h.txt"
            if [ -s "$TMP/h.txt" ]; then
                found=1
                while IFS= read -r h; do fail "account '$login' appears in $rel:${h%%:*}"; done <"$TMP/h.txt"
            fi
        done <"$MAN"
        [ "$found" = 0 ] && pass "account #$idx of $NLOGIN appears in none of the $NFILES corpus files"
    done <"$LOGINS"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((NPASS + NFAIL))
SCOPE="$NFILES corpus files ($NFIXED fixed; $NCHANGED changed, $NIDX staged versions and $NNAMES changed path names named by --changed-since${SINCE:+ $SINCE})"
LEFT_OUT=""
[ "$NEXCL" -gt 0 ] && LEFT_OUT="$LEFT_OUT; excluded from --changed-since: $NEXCL consumer configuration file(s) read in this run:$EXCL_LIST"
[ "$NSQL" -gt 0 ] && LEFT_OUT="$LEFT_OUT; $NSQL SQLite database file(s) scanned as their text cells:$SQL_LIST"
if [ "$NFAIL" -gt 0 ]; then
    echo "$GATE: FAIL — $NFAIL of $TOTAL checks failed over $SCOPE$LEFT_OUT (root: $ROOT)"
    exit 1
fi
if [ "$NLOGIN" -eq 0 ]; then
    echo "$GATE: SKIP — no consumer reviewer list was found or given: the structure checks passed ($NPASS), the account scan did not run (not a PASS)"
    exit 3
fi
echo "$GATE: PASS — $NPASS/$TOTAL checks: $NLOGIN declared account(s) ($NREV reviewer and $NASG assignee entries read) appear in none of the $SCOPE$LEFT_OUT; files outside the corpus are not scanned (root: $ROOT)"
exit 0
