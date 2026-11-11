#!/usr/bin/env bash
# scripts/release/derive_release_facts.sh — print, mechanically, every number and id list a release
# CHANGELOG entry quotes from the repository and its tracker (§11.4.274: the cut is a script, not an
# agent re-typing counts; §11.4.294(H): states are quoted from the parent tracker, never paraphrased).
#
# Usage:
#   scripts/release/derive_release_facts.sh --base COMMIT --prev-tag TAG [--remotes "R1 R2 ..."] [--today YYYY-MM-DD]
#
# Reads ONLY committed data: `git show COMMIT:docs/workable_items.db` (copied to a temp file, opened
# read-only), `git rev-list`, `git diff --shortstat`, and the remote-tracking refs already present for
# each remote named in --remotes (fetch them first; the script never fetches, so a stale ref is the
# caller's to refresh). Output: one KEY=VALUE line per fact, id lists space-separated and sorted, in a
# fixed order. Every line is a fact read from data; nothing is estimated.
#
# Meaning of the §11.4.290(4) count line it prints:
#   P (provisional) = open items whose body carries a "**Verification:** provisional" line;
#   O (overdue)     = those of P whose "due:" field is a date before --today, or is not a date at all
#                     ("UNSCHEDULED, treated as OVERDUE", review of v73.4 I-4);
#   V (verified)    = items in the Fixed tracker whose closure_date is after the previous tag's date.
#
# Exit status: 0 facts printed; 2 usage; 3 data missing (no tracker at COMMIT, unknown tag, sqlite3
# absent) — never a partial set of facts reported as complete.
set -u
LC_ALL=C; export LC_ALL
BASE="" PREV="" REMOTES="" TODAY="$(date +%F)"
die() { printf 'derive_release_facts: %s\n' "$1" >&2; exit "$2"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || die "--base needs a value" 2; BASE="$2"; shift 2 ;;
    --prev-tag) [ $# -ge 2 ] || die "--prev-tag needs a value" 2; PREV="$2"; shift 2 ;;
    --remotes) [ $# -ge 2 ] || die "--remotes needs a value" 2; REMOTES="$2"; shift 2 ;;
    --today) [ $# -ge 2 ] || die "--today needs a value" 2; TODAY="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" 2 ;;
  esac
done
[ -n "$BASE" ] && [ -n "$PREV" ] || die "--base and --prev-tag are required" 2
printf '%s' "$TODAY" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "--today must be YYYY-MM-DD" 2
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required" 3
B="$(git rev-parse -q --verify "$BASE^{commit}")" || die "base $BASE is not a commit" 3
P="$(git rev-parse -q --verify "refs/tags/$PREV^{commit}")" || die "tag $PREV not found" 3
DBDIR="$(mktemp -d "${TMPDIR:-/tmp}/rf_db.XXXXXX")" || die "cannot create a temp dir" 3
DB="${DBDIR:?}/items.db"
# a WAL-mode database leaves -shm/-wal side files even when opened read-only; remove exactly those
cleanup() { for _f in "$DB" "$DB-shm" "$DB-wal" "$DB-journal"; do [ -f "$_f" ] && unlink "$_f"; done; [ -d "$DBDIR" ] && rmdir "$DBDIR"; }
trap cleanup EXIT
git show "$B:docs/workable_items.db" >"$DB" 2>/dev/null && [ -s "$DB" ] || die "no docs/workable_items.db at $B" 3
q() { sqlite3 -readonly -batch -noheader "$DB" "$1"; }
# ascii mode: columns end with US (0x1f), rows with RS (0x1e), values raw (the default mode escapes
# control characters, so a separator built with char(31) would come back as the two characters ^_)
qa() { sqlite3 -readonly -batch -noheader -ascii "$DB" "$1"; }
ids() { q "$1" | sort -V | tr '\n' ' ' | sed 's/ $//'; }
kv() { printf '%s=%s\n' "$1" "$2"; }

kv base "$B"
kv prev_tag "$PREV"; kv prev_tag_object "$(git rev-parse "refs/tags/$PREV")"; kv prev_tag_commit "$P"
PREV_DATE="$(git log -1 --format=%cs "$P")"; kv prev_tag_date "$PREV_DATE"
kv commits_since_prev "$(git rev-list --count "$P..$B")"
kv shortstat_since_prev "$(git diff --shortstat "$P" "$B" | sed 's/^ *//')"
kv merges_since_prev "$(git rev-list --merges --count "$P..$B")"
kv changelog_first_heading "$(git show "$B:CHANGELOG.md" | awk '/^## /{print substr($0,4); exit}' | cut -c1-120)"
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
while IFS=$'\x1f' read -r -d $'\x1e' id body; do
  PROV="$PROV $id"
  due="$(printf '%s\n' "$body" | grep -m1 -F '**Verification:** provisional' | sed -n 's/.*due:[[:space:]]*\([^[:space:]]*\).*/\1/p')"
  if printf '%s' "$due" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    [ "${due:0:10}" \< "$TODAY" ] && OVER="$OVER $id"
  else
    OVER="$OVER $id"     # no date: UNSCHEDULED, treated as OVERDUE
  fi
done < <(qa "select atm_id, body_md from items where $O and body_md like '%**Verification:** provisional%'")
sv() { printf '%s\n' $1 | sed '/^$/d' | sort -V | tr '\n' ' ' | sed 's/ $//'; }
PROV="$(sv "$PROV")"; OVER="$(sv "$OVER")"
kv provisional_ids "$PROV"; kv overdue_ids "$OVER"
# PREV_DATE is git's %cs (YYYY-MM-DD); checked before it is used in SQL
printf '%s' "$PREV_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "tag date $PREV_DATE is not YYYY-MM-DD" 3
VER="$(ids "select atm_id from items where current_location='Fixed' and coalesce(closure_date,'') > '$PREV_DATE'")"
kv verified_since_prev_ids "$VER"
words() { printf '%s\n' "$1" | wc -w | tr -d ' '; }
kv count_line "$(words "$VER") verified + $(words "$PROV") provisional ($(words "$OVER") overdue)"

# §11.4.288 debt: remote refs other than main/HEAD with commits not on the base, per remote counted
for r in $REMOTES; do
  n=0 list=""
  while IFS= read -r ref; do
    case "$ref" in "refs/remotes/$r/main"|"refs/remotes/$r/HEAD") continue ;; esac
    c="$(git rev-list --count "$B..$ref")"
    [ "$c" -gt 0 ] && { n=$((n+1)); list="$list ${ref#refs/remotes/"$r"/}:$c"; }
  done < <(git for-each-ref --format='%(refname)' "refs/remotes/$r/")
  kv "unmerged_refs_count[$r]" "$n"; kv "unmerged_refs[$r]" "${list# }"
done
exit 0
