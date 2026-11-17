#!/usr/bin/env bash
# scripts/release/derive_release_facts.sh — print, mechanically, every number and id list a release
# CHANGELOG entry quotes from the repository and its tracker (§11.4.274: the cut is a script, not an
# agent re-typing counts; §11.4.294(H): states are quoted from the parent tracker, never paraphrased).
#
# Usage:
#   scripts/release/derive_release_facts.sh --base COMMIT --prev-tag TAG [--remotes "R1 R2 ..."] [--today YYYY-MM-DD]
#                                           [--retest-item ID [--require-retest-evidence]]
#
# Reads ONLY committed data: `git show COMMIT:docs/workable_items.db` (copied to a temp file, opened
# read-only), `git rev-list`, `git diff --shortstat`, and the remote-tracking refs already present for
# each remote named in --remotes (fetch them first; the script never fetches, so a stale ref is the
# caller's to refresh). Output: one KEY=VALUE line per fact, id lists space-separated and sorted, in a
# fixed order. Every line is a fact read from data; nothing is estimated.
#
# Meaning of the §11.4.290(4) count line it prints:
#   P (provisional) = open items whose body carries a "**Verification:** provisional" LINE: a line that
#                     STARTS with that text, followed by the end of the line or a character that is not a
#                     letter, digit or underscore, and is outside a fenced code block (backtick or tilde fences
#                     indented 0 to 3 spaces, closed by the same character at least as long; a quotation of the
#                     marker inside prose or inside a fence is not a verification line; rel1, CON-521);
#   O (overdue)     = those of P whose first "due:" field of that line is a date before --today, or is not a date at all
#                     ("UNSCHEDULED, treated as OVERDUE", review of v73.4 I-4);
#   V (verified)    = items in the Fixed tracker whose closure_date is after the previous tag's date.
#
# --retest-item ID (rel2): prints retest_item_id, retest_item_status ("status (location)"), retest_item_closure
# (the closure_date, or "none") and retest_item_evidence=yes only when the item is in the Fixed tracker AND its
# closure_date is after the previous tag's date (the rule of V; review of e5efbf77, F8). Any other item (open, or
# Fixed but closed on or before the previous tag, or with no closure date) is not this candidate's recorded retest,
# and a line retest_item_flag=NOT-EVIDENCE ... is printed so a release entry never cites it as evidence. An id that
# is not in the tracker exits 3; a failed lookup query exits 3 with its own message (F9). With
# --require-retest-evidence a not-evidence item exits 3 too (no facts printed).
#
# Exit status: 0 facts printed; 2 usage; 3 data missing (no tracker at COMMIT, unknown tag, sqlite3
# absent, or any tracker query failed, e.g. a missing column) — never a partial set of facts: the
# facts are buffered and printed only when every query succeeded; on exit 3 stdout stays empty.
# Verified count boundary: an item closed ON the previous tag's date is not counted (the tag date
# has day granularity, so a same-day closure cannot be shown to postdate the tag).
set +x   # first: an inherited xtrace (bash -x, SHELLOPTS=xtrace) traces this one line only
set -u
unset -v GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py; written as unset -v because the network-spawn gate of tests/release/channel_census.py admits only that form)
LC_ALL=C; export LC_ALL
BASE="" PREV="" REMOTES="" TODAY="" RETEST="" REQ_RETEST=0
DIE_FD=2
die() { printf 'derive_release_facts: %s\n' "$1" >&"$DIE_FD"; exit "$2"; }
# the one redact-then-cut helper for external-command output (round 3, CON-234 n-4 class)
# shellcheck source=scripts/release/redact_cut.sh
_rc_d="${BASH_SOURCE[0]}"; case "$_rc_d" in */*) _rc_d="${_rc_d%/*}" ;; *) _rc_d=. ;; esac   # no external command before the lockdown (round 6)
. "$(cd "$_rc_d" && pwd)/redact_cut.sh" || die "cannot load redact_cut.sh" 3
rc_env_clean "" "$@"; _rc=$?   # children get an environment built from the allow-list only (round 7, L1 L2; K3)
[ "$_rc" -eq 0 ] || die "cannot build a clean environment for the child processes (rc_env_clean status $_rc; Linux /proc is required)" 3
rc_git_env   # no git trace anywhere, no terminal prompt, GIT_TRACE_REDACT=1
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || die "--base needs a value" 2; BASE="$2"; shift 2 ;;
    --prev-tag) [ $# -ge 2 ] || die "--prev-tag needs a value" 2; PREV="$2"; shift 2 ;;
    --remotes) [ $# -ge 2 ] || die "--remotes needs a value" 2; REMOTES="$2"; shift 2 ;;
    --today) [ $# -ge 2 ] || die "--today needs a value" 2; TODAY="$2"; shift 2 ;;
    --retest-item) [ $# -ge 2 ] || die "--retest-item needs a value" 2; RETEST="$2"; shift 2 ;;
    --require-retest-evidence) REQ_RETEST=1; shift ;;
    -h|--help) awk 'NR>1 && /^#/{print; next} NR>1{exit}' "$0"; exit 0 ;;
    *) if [[ $1 =~ ^--?[A-Za-z][A-Za-z0-9-]{0,40}$ ]]; then die "unknown argument: $1" 2
       else die "unknown argument (not shown: it is not shaped like an option)" 2; fi ;;
  esac
done
[ -n "$BASE" ] && [ -n "$PREV" ] || die "--base and --prev-tag are required" 2
# caller values are printed in messages and facts, so they are checked first and never echoed when invalid
# (round 5, CON-234 class): a revision name has no ":" (so it cannot be a URL), a tag and a remote are names
[[ $BASE =~ ^[A-Za-z0-9][A-Za-z0-9._/~^-]{0,199}$ ]] || die "--base is not a revision name of [A-Za-z0-9._/~^-] (the value is not shown)" 2
[[ $PREV =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$ ]] || die "--prev-tag has unsafe characters (the value is not shown)" 2
[ -z "$RETEST" ] || [[ $RETEST =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$ ]] || die "--retest-item is not an item id of [A-Za-z0-9._-] (the value is not shown)" 2
[ "$REQ_RETEST" -eq 0 ] || [ -n "$RETEST" ] || die "--require-retest-evidence needs --retest-item" 2
_n=0
for _r in $REMOTES; do
  _n=$((_n + 1)); [[ $_r =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] || die "remote name number $_n in --remotes has unsafe characters (not shown)" 2
done
[ -n "$TODAY" ] || TODAY="$(date +%F)"   # after the lockdown: date gets the allow-listed environment
printf '%s' "$TODAY" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "--today must be YYYY-MM-DD" 2
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required" 3
B="$(rc_net git rev-parse -q --verify "$BASE^{commit}")" || die "base $BASE is not a commit" 3
P="$(rc_net git rev-parse -q --verify "refs/tags/$PREV^{commit}")" || die "tag $PREV not found" 3
DBDIR="$(mktemp -d "${TMPDIR:-/tmp}/rf_db.XXXXXX")" || die "cannot create a temp dir" 3
DB="${DBDIR:?}/items.db"; chmod 700 "$DBDIR"
# a WAL-mode database leaves -shm/-wal side files even when opened read-only; remove exactly those
# stderr of every external command (sqlite3, git) goes to EXTERR and is printed once at exit through the
# helper (redacted, then cut at 2000 bytes); the script's own messages use fd 3 (the original stderr).
EXTERR="$DBDIR/exterr"; exec 3>&2 2>"$EXTERR"; DIE_FD=3
cleanup() { [ -f "$EXTERR" ] && rc_redact_cut 2000 mark <"$EXTERR" >&3; for _f in "$DB" "$DB-shm" "$DB-wal" "$DB-journal" "$DBDIR/out" "$DBDIR/qfail" "$EXTERR"; do [ -f "$_f" ] && unlink "$_f"; done; [ -d "$DBDIR" ] && rmdir "$DBDIR"; }
trap cleanup EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # signals end the run through cleanup (round 4)
rc_net git show "$B:docs/workable_items.db" >"$DB" 2>/dev/null && [ -s "$DB" ] || die "no docs/workable_items.db at $B" 3
# Every query records a failure in a flag file (a query inside $(...) or a pipeline cannot stop the
# script itself); the flag is checked before any fact is released (review m-2, CON-228).
QFAIL="$DBDIR/qfail"
# -safe (round 12, F1 of the round-11 review): the dot-commands that run a program (.system, .shell, the |cmd
# forms of .output, .once, .import, .read) and file access other than the database are refused
q() { sqlite3 -safe -readonly -batch -noheader "$DB" "$1" || { echo query >>"$QFAIL"; return 1; }; }
# ascii mode: columns end with US (0x1f), rows with RS (0x1e), values raw (the default mode escapes
# control characters, so a separator built with char(31) would come back as the two characters ^_)
qa() { sqlite3 -safe -readonly -batch -noheader -ascii "$DB" "$1" || { echo query >>"$QFAIL"; return 1; }; }
ids() { q "$1" | sort -V | tr '\n' ' ' | sed 's/ $//'; }
kv() { printf '%s=%s\n' "$1" "$2"; }

# stdout is buffered: nothing reaches the caller until every query has succeeded
exec 4>&1 >"$DBDIR/out"
kv base "$B"
kv prev_tag "$PREV"; kv prev_tag_object "$(rc_net git rev-parse "refs/tags/$PREV")"; kv prev_tag_commit "$P"
PREV_DATE="$(rc_net git log -1 --format=%cs "$P")"; kv prev_tag_date "$PREV_DATE"
kv commits_since_prev "$(rc_net git rev-list --count "$P..$B")"
kv shortstat_since_prev "$(rc_net git diff --shortstat "$P" "$B" | sed 's/^ *//')"
kv merges_since_prev "$(rc_net git rev-list --merges --count "$P..$B")"
rc_net git cat-file -e "$B:CHANGELOG.md" 2>/dev/null || echo changelog >>"$QFAIL"
kv changelog_first_heading "$(rc_net git show "$B:CHANGELOG.md" | awk '/^## /{print substr($0,4); exit}' | cut -c1-120)"
kv db_sha256 "$(sha256sum "$DB" | cut -d' ' -f1)"

O="current_location='Issues'"
kv items_total "$(q "select count(*) from items")"
kv items_open "$(q "select count(*) from items where $O")"
kv items_fixed "$(q "select count(*) from items where current_location='Fixed'")"
# No value read from the database is ever put back into SQL text (review of this script: a severity
# or state value with a quote would have altered the query). Each grouping is ONE query returning
# key,id rows in ascii mode; counts and id lists are built here, so any text in a value works.
grp() {   # grp PREFIX SQL-yielding-key,id [skipkey]  -> PREFIX[key]=count and PREFIX_ids[key]=ids
  qa "$2" | awk '
    BEGIN { FS = "\037"; RS = "\036" }
    { n[$1]++; ids[$1] = ids[$1] $2 "\n" }
    END { for (k in n) printf "%s\036%s\036%s\035", k, n[k], ids[k] }' |
  while IFS=$'\x1e' read -r -d $'\x1d' k n idl; do
    kv "$1[$k]" "$n"
    [ -n "${3:-}" ] && [ "$k" = "$3" ] && continue
    kv "$1_ids[$k]" "$(printf '%s' "$idl" | sort -V | tr '\n' ' ' | sed 's/ $//')"
  done | sort
}
grp open_status "select status, atm_id from items where $O" | grep -v '^open_status_ids\[Queued\]=' 
grp open_severity "select lower(coalesce(severity,'none')), atm_id from items where $O"
kv open_severity_raw_spellings "$(q "select distinct coalesce(severity,'none') from items where $O order by 1" | tr '\n' ' ' | sed 's/ $//')"
grp open_states "select reproduction_state||'/'||investigation_state, atm_id from items where $O" UNSET/UNSET
kv open_items_with_any_state "$(q "select count(*) from items where $O and (reproduction_state!='UNSET' or investigation_state!='UNSET')")"
kv reopened_ids "$(ids "select atm_id from items where status='Reopened'")"

# §11.4.290(4): V verified + P provisional (O overdue). Bodies come out with newlines replaced by RS
# (ascii mode, one RS-terminated row per item); the id is never interpolated back into SQL.
PROV="" OVER=""
# round 8 (N3 class): the rows are read from a here-string, never from a process substitution, whose pipe bash
# leaves open (without close-on-exec) in every command the loop body runs
rows="$(qa "select atm_id, body_md from items where $O and body_md like '%**Verification:** provisional%'")"
while IFS=$'\x1f' read -r -d $'\x1e' id body; do
  # rel1: the SQL like above only pre-filters; the verification LINE is the first line that starts with the marker
  # outside a fenced code block, so a quotation of the marker in prose or in a fence does not count. Fences follow
  # CommonMark (review of e5efbf77, F2): an opening fence is 3 or more backticks or tildes indented 0 to 3 spaces (a
  # backtick fence whose info string holds a backtick is not a fence); it is closed only by a line of the same
  # character, at least as long, indented 0 to 3 spaces, with nothing but blanks after it; an unclosed fence runs to
  # the end of the body. The marker must be followed by the end of the line or a character that is not a letter,
  # digit or underscore ("provisionally" is another word, F3). The awk prints "V" and the FIRST due: field of that
  # line (a "due:" preceded by a letter, digit or underscore, as in "overdue:", is not the field; F4).
  vline="$(printf '%s\n' "$body" | awk '
    { line = $0; sub(/\r$/, "", line)
      ind = 0; while (ind < 4 && substr(line, ind + 1, 1) == " ") ind++
      rest = substr(line, ind + 1); c = substr(rest, 1, 1)
      if (ind < 4 && (c == "`" || c == "~")) {
        n = 0; while (substr(rest, n + 1, 1) == c) n++
        tail = substr(rest, n + 1)
        if (n >= 3 && fc == "" && !(c == "`" && index(tail, "`") > 0)) { fc = c; fl = n; next }
        if (n >= 3 && fc == c && n >= fl && tail ~ /^[ \t]*$/) { fc = ""; next }
      }
      if (fc != "") next
      m = "**Verification:** provisional"
      if (index(line, m) != 1) next
      after = substr(line, length(m) + 1, 1)
      if (after ~ /[A-Za-z0-9_]/) next
      s = line; off = 0; due = ""
      while ((k = index(s, "due:")) > 0) {
        pre = (off + k > 1) ? substr(line, off + k - 1, 1) : ""
        if (pre !~ /[A-Za-z0-9_]/) { r = substr(s, k + 4); sub(/^[ \t]+/, "", r); match(r, /^[^ \t]*/); due = substr(r, 1, RLENGTH); break }
        off += k + 3; s = substr(s, k + 4)
      }
      print "V" due; exit
    }')"
  [ -n "$vline" ] || continue
  PROV="$PROV $id"
  due="${vline#V}"
  if printf '%s' "$due" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    [ "${due:0:10}" \< "$TODAY" ] && OVER="$OVER $id"
  else
    OVER="$OVER $id"     # no date: UNSCHEDULED, treated as OVERDUE
  fi
done <<<"$rows"
sv() { printf '%s\n' $1 | sed '/^$/d' | sort -V | tr '\n' ' ' | sed 's/ $//'; }
PROV="$(sv "$PROV")"; OVER="$(sv "$OVER")"
kv provisional_ids "$PROV"; kv overdue_ids "$OVER"
# PREV_DATE is git's %cs (YYYY-MM-DD); checked before it is used in SQL
printf '%s' "$PREV_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "tag date $PREV_DATE is not YYYY-MM-DD" 3
VER="$(ids "select atm_id from items where current_location='Fixed' and coalesce(closure_date,'') > '$PREV_DATE'")"
kv verified_since_prev_ids "$VER"
words() { printf '%s\n' "$1" | wc -w | tr -d ' '; }
kv count_line "$(words "$VER") verified + $(words "$PROV") provisional ($(words "$OVER") overdue)"

# rel2: the retest item a release entry cites. Evidence only when it is in the Fixed tracker AND its closure_date is
# after the previous tag's date (the same rule as V above; review of e5efbf77, F8): a Fixed item closed before the
# previous tag, or with no closure date, is not THIS candidate's §11.4.40 retest and is flagged like an open item.
# An unknown id is refused; a failed lookup query is reported as such (F9). The id is validated above and never
# interpolated into SQL: the lookup compares it in awk over a key,status,location,closure listing.
if [ -n "$RETEST" ]; then
  rok=1
  rlist="$(qa "select atm_id, status, current_location, coalesce(closure_date,'') from items")" || rok=0
  rrow="$(printf '%s' "$rlist" | awk -v want="$RETEST" '
    BEGIN { FS = "\037"; RS = "\036" }
    $1 == want { printf "%s\037%s\037%s", $2, $3, $4; exit }')"
  if [ "$rok" -eq 0 ]; then
    printf 'derive_release_facts: retest item lookup query failed at %s (the item is not judged); no facts printed\n' "$B" >&3
  elif [ -z "$rrow" ]; then
    printf 'derive_release_facts: retest item %s is not in the tracker at %s; no facts printed\n' "$RETEST" "$B" >&3
    echo retest >>"$QFAIL"
  else
    rstat="${rrow%%$'\x1f'*}"; rrest="${rrow#*$'\x1f'}"; rloc="${rrest%%$'\x1f'*}"; rclos="${rrest#*$'\x1f'}"
    kv retest_item_id "$RETEST"; kv retest_item_status "$rstat ($rloc)"; kv retest_item_closure "${rclos:-none}"
    if [ "$rloc" = Fixed ] && [ -n "$rclos" ] && [ "$rclos" \> "$PREV_DATE" ]; then kv retest_item_evidence yes
    else
      kv retest_item_evidence no
      if [ "$rloc" = Fixed ]; then
        kv retest_item_flag "NOT-EVIDENCE: $RETEST is in Fixed but its closure (${rclos:-none}) is not after the previous tag ($PREV_DATE), so it is not this candidate's retest (§11.4.40); a release entry must not cite it as a retest result"
      else
        kv retest_item_flag "NOT-EVIDENCE: $RETEST is $rstat in $rloc, an owed retest and not a recorded one (§11.4.40); a release entry must not cite it as a retest result"
      fi
      if [ "$REQ_RETEST" -eq 1 ]; then
        printf 'derive_release_facts: retest item %s is not recorded evidence (%s in %s); no facts printed\n' "$RETEST" "$rstat" "$rloc" >&3
        echo retest >>"$QFAIL"
      fi
    fi
  fi
fi

# §11.4.288 debt: remote refs other than main/HEAD with commits not on the base, per remote counted
for r in $REMOTES; do
  n=0 list=""
  refs="$(rc_net git for-each-ref --format='%(refname)' "refs/remotes/$r/")"   # a here-string below, not a process substitution (N3 class)
  while IFS= read -r ref; do
    case "$ref" in ""|"refs/remotes/$r/main"|"refs/remotes/$r/HEAD") continue ;; esac
    c="$(rc_net git rev-list --count "$B..$ref")"
    [ "$c" -gt 0 ] && { n=$((n+1)); list="$list ${ref#refs/remotes/"$r"/}:$c"; }
  done <<<"$refs"
  kv "unmerged_refs_count[$r]" "$n"; kv "unmerged_refs[$r]" "${list# }"
done
exec 1>&4 4>&-
if [ -e "$QFAIL" ]; then
  grep -q '^changelog$' "$QFAIL" && printf 'derive_release_facts: CHANGELOG.md is missing at the base %s; no facts printed\n' "$B" >&3
  grep -q '^query$' "$QFAIL" && printf 'derive_release_facts: a tracker query failed (the sqlite3 error is printed after this line); no facts printed\n' >&3
  exit 3
fi
cat -- "$DBDIR/out"
exit 0
