#!/bin/sh
# shellcheck shell=sh
# Purpose : sourced helper for SpecKit-004 fastcycle tests that exercise CONSUMER-project data
#           (tracker DB, specs/, config/, device/ trees) which does not exist in the canon repository.
#           fc_require_consumer <path>...  exits 77 (honest SKIP, section 11.4.3 / 11.4.69
#           topology_unsupported) when any named path is absent, naming each; never a PASS.
#           A relative <path> is resolved under the consumer root. An absolute <path> is checked
#           as given: a test whose input can be redirected by an env override (for example
#           FC_TIMER_RED_PREBUILD) passes the EFFECTIVE path it will read, so the SKIP fires only
#           when the input the run actually needs is absent (review F2, section 11.4.201(1)).
# Usage   : . "$(dirname "$0")/lib/consumer_required.sh" && fc_require_consumer <path>...
#           fc_require_items <db> <id>...  (see the function below: SKIP only on proven absence)
# Shell   : plain POSIX sh. It runs under bash and under dash (the full-suite runner runs a
#           #!/bin/sh test with sh). It reads no bash-only variable (review F1: BASH_SOURCE is
#           empty under dash, which resolved the root to / and gave a false SKIP).
# Root    : the consumer root is four directories above the calling test, taken from $0 (in a
#           sourced file $0 is the calling script under every POSIX shell); the test lives at
#           <consumer>/<canon>/scripts/fastcycle/tests/<test>.sh.
# Output  : on SKIP one line on stdout ending in reason=topology_unsupported (the runner reads
#           reason=<code> from the last line, review F9). Exit 77. Otherwise nothing, returns 0.
# Test    : scripts/fastcycle/tests/test_consumer_required_helper.sh (bash and dash, data present
#           and absent, absolute effective paths).
fc_require_consumer() {
  _fcr_root=$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd) || _fcr_root=""
  if [ -z "$_fcr_root" ]; then
    echo "SKIP: consumer root not resolvable from \$0='$0' reason=topology_unsupported"
    exit 77
  fi
  _fcr_missing=""
  for _fcr_p in "$@"; do
    case $_fcr_p in
      /*) _fcr_abs=$_fcr_p ;;
      *)  _fcr_abs=$_fcr_root/$_fcr_p ;;
    esac
    [ -e "$_fcr_abs" ] || _fcr_missing="$_fcr_missing $_fcr_p"
  done
  if [ -n "$_fcr_missing" ]; then
    echo "SKIP: consumer-project files absent under $_fcr_root:$_fcr_missing (test targets a consumer layout, not canon alone) reason=topology_unsupported"
    exit 77
  fi
  unset _fcr_root _fcr_missing _fcr_p _fcr_abs
  return 0
}

# fc_require_items <db> <id>...   (review round 2 CR-1, CR-3 of the full-suite fix vehicle)
#   A suite that reads named real items of ONE consumer's tracker (for example ATM-953) SKIPs (exit 77,
#   reason=topology_unsupported) only when the database PROVES it is another consumer's register: the
#   items table answers, an id column is found (atm_id and/or ticket_id after the section 11.4.54 rename;
#   when both exist BOTH are examined, CR3-2),
#   the table holds at least one item, the count of the named ids is a NUMBER below the number named,
#   AND the table holds no id with the named ids' prefix at all (e.g. no ATM-* row). Every other outcome
#   returns 0 and the suite's own checks run and report what they find:
#     - a query that errors (no sqlite3, unreadable file, no items table, no known id column, a lock):
#       the guard cannot prove absence, so it never SKIPs (section 11.4.201: an error is not "absent");
#     - a register that holds ids with the prefix but lacks a named one: it LOST that item; the checks
#       must FAIL, not SKIP (CR-3);
#     - an empty items table: nothing is proven; the checks run.
#   Ids must match [A-Z][A-Z0-9]*-[0-9]+ (they are interpolated into SQL); another shape is a usage error
#   (exit 2). A foreign register that happens to hold any <PREFIX>-* row runs the checks and FAILs; that is
#   the intended CR-3 trade-off, so such a FAIL is not read as a lost item (CR3-5).
#   The last stdout line of a SKIP ends in reason=topology_unsupported; nothing is written on stderr, on a SKIP or a run.
#   Every sqlite3 call is opened -readonly, so the database file's bytes never change and no database is created for
#   an absent path; on a WAL-mode database sqlite may leave <db>-wal (empty) and <db>-shm beside it when the last
#   connection is read-only (here docs/workable_items.db-wal and -shm are gitignored). A BLOB-stored id (the real schema
#   stores TEXT): LIKE reads it as text, so a BLOB id with the prefix makes C3 >= 1 and the checks run; IN never
#   matches a BLOB to a TEXT id, which cannot cause a SKIP while C3 >= 1. Legs, bounds and paired mutants are in
#   test_consumer_required_helper.sh Part 3 (rounds 7 and 8 of the full-suite fix vehicle, CON-152/CON-157).
#   The reads see committed content of a WAL-mode database that is not yet checkpointed (a live writer or a crash
#   leaves it in <db>-wal); opening the file immutable would hide it and SKIP a register that lost an item (L26).
#   IFS: the prefix list and the three counts are split with the caller's IFS. With an IFS that lacks a space
#   (IFS=, or IFS=) the counts arrive as one field, so the helper never SKIPs and the checks run (fail-closed); an
#   IFS holding a digit can produce an empty field, which also never SKIPs. Callers keep the default IFS.
fc_require_items() {
  _fci_db=$1; shift
  _fci_need=$#; _fci_in=""; _fci_pfx=""
  [ "$_fci_need" -gt 0 ] || { echo "fc_require_items: no item id given" >&2; exit 2; }
  for _fci_id in "$@"; do
    _fci_p=${_fci_id%%-*}; _fci_n=${_fci_id#*-}
    [ "$_fci_p" != "$_fci_id" ] || { echo "fc_require_items: bad item id '$_fci_id'" >&2; exit 2; }
    case $_fci_p in ''|[!A-Z]*|*[!A-Z0-9]*) echo "fc_require_items: bad item id '$_fci_id'" >&2; exit 2 ;; esac
    case $_fci_n in ''|*[!0-9]*) echo "fc_require_items: bad item id '$_fci_id'" >&2; exit 2 ;; esac
    _fci_in="$_fci_in${_fci_in:+,}'$_fci_id'"
    case " $_fci_pfx " in *" $_fci_p "*) ;; *) _fci_pfx="$_fci_pfx${_fci_pfx:+ }$_fci_p" ;; esac
  done
  command -v sqlite3 >/dev/null 2>&1 || return 0
  _fci_cols=$(sqlite3 -readonly "$_fci_db" "SELECT name FROM pragma_table_info('items');" 2>/dev/null) || return 0
  _fci_src=""; _fci_key=""
  for _fci_c in atm_id ticket_id; do
    if printf '%s\n' "$_fci_cols" | grep -qx "$_fci_c"; then
      _fci_src="$_fci_src${_fci_src:+ UNION ALL }SELECT $_fci_c AS k FROM items"
      _fci_key="$_fci_key${_fci_key:+,}$_fci_c"
    fi
  done
  [ -n "$_fci_src" ] || return 0
  _fci_like=""
  for _fci_p in $_fci_pfx; do _fci_like="$_fci_like${_fci_like:+ OR }k LIKE '$_fci_p-%'"; done
  _fci_q=$(sqlite3 -readonly -separator ' ' "$_fci_db" "SELECT (SELECT COUNT(*) FROM items), (SELECT COUNT(DISTINCT k) FROM ($_fci_src) WHERE k IN ($_fci_in)), (SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like);" 2>/dev/null) || return 0
  set -- $_fci_q
  [ $# -eq 3 ] || return 0
  for _fci_v in "$1" "$2" "$3"; do case $_fci_v in ''|*[!0-9]*) return 0 ;; esac; done
  if [ "$1" -gt 0 ] && [ "$2" -lt "$_fci_need" ] && [ "$3" -eq 0 ]; then
    echo "SKIP: tracker DB $_fci_db ($1 items, column $_fci_key) is another consumer's register: it holds no $_fci_pfx-* item, so not the real items this suite reads ($(echo "$_fci_in" | tr -d "'"); found $2 of $_fci_need) reason=topology_unsupported"
    exit 77
  fi
  unset _fci_db _fci_need _fci_in _fci_pfx _fci_id _fci_p _fci_n _fci_cols _fci_key _fci_src _fci_c _fci_like _fci_q _fci_v
  return 0
}
