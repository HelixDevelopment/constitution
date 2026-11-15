#!/bin/bash
# docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh -- apply restore_plan.tsv (CON-339) through the
# engine's `restore-created-at`; the tracker is never edited by hand (section 11.4.93).
#
# For every plan row: extract the evidence database with `git show <commit>:<path>` into the row's
# evidence_file (under --root), check its sha256 against the plan, then run
#   <engine> restore-created-at --db <db> --id <id for --landing> --evidence-id <vehicle_id>
#       --value <value> --evidence <evidence_file> --evidence-sha256 <sha256> --reason <reason> [--dry-run]
# from --root, so the evidence path the audit row records is the repository-relative one in the plan.
#
# Usage: apply_restore_plan.sh --engine <workable-items binary> --db <tracker db> --landing main|fix227
#                              [--root <dir>] [--repo <git dir>] [--plan <tsv>] [--apply]
#   --root   where the evidence files are written and the engine runs (default: the current directory)
#   --repo   the repository `git show` reads the evidence commits from (default: --root)
#   --plan   default: restore_plan.tsv next to this script
#   --apply  write; without it every row runs with --dry-run (all checks, nothing written)
# Exit: 0 every row restored, already restored, or passed its dry run; 1 the engine refused a row;
#       2 usage; 3 BLIND (missing engine/db/plan, git show failed, evidence sha256 differs from the plan,
#       an evidence path that is absolute, contains .., does not end in a file name, passes through a
#       symbolic link, or names an existing entry that is not a regular file).
# Rows are applied ONE BY ONE, each in its own engine transaction: when the engine refuses a row, the rows
# before it stay applied and the script goes on with the next row, then exits 1. A BLIND condition stops
# the run at that row (earlier rows stay applied). Every row is idempotent, so a re-run after a fix only
# answers "already" for the rows that were applied (round 2, F8). A final plan row without a trailing
# newline is read like every other row (round 2, F2).
# Evidence class: gate-logic / unit when run on a copy; the lander runs it with --apply on the landed tracker.
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE=$(cd "$(dirname "$0")" && pwd) || exit 3
ENGINE="" DB="" LANDING="" ROOT="$PWD" REPO="" PLAN="$HERE/restore_plan.tsv" APPLY=0
usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --engine) [ $# -ge 2 ] || usage; ENGINE=$2; shift 2 ;;
    --db) [ $# -ge 2 ] || usage; DB=$2; shift 2 ;;
    --landing) [ $# -ge 2 ] || usage; LANDING=$2; shift 2 ;;
    --root) [ $# -ge 2 ] || usage; ROOT=$2; shift 2 ;;
    --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
    --plan) [ $# -ge 2 ] || usage; PLAN=$2; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$ENGINE" ] && [ -n "$DB" ] && [ -n "$LANDING" ] || usage
case "$LANDING" in main) IDCOL=2 ;; fix227) IDCOL=3 ;; *) echo "--landing must be main or fix227" >&2; exit 2 ;; esac
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || { echo "BLIND: --root not a directory" >&2; exit 3; }
[ -n "$REPO" ] || REPO=$ROOT
[ -x "$ENGINE" ] || { echo "BLIND: engine not executable: $ENGINE" >&2; exit 3; }
[ -f "$DB" ] || { echo "BLIND: tracker db not found: $DB" >&2; exit 3; }
[ -f "$PLAN" ] || { echo "BLIND: plan not found: $PLAN" >&2; exit 3; }
case "$ENGINE" in /*) ;; *) ENGINE="$PWD/$ENGINE" ;; esac
case "$DB" in /*) ;; *) DB="$PWD/$DB" ;; esac
rows=0 refused=0
while IFS=$'\t' read -r vid idmain idfix value commit gitpath sha evfile attests reason || [ -n "$vid" ]; do
  case "$vid" in ''|'#'*|vehicle_id) continue ;; esac
  rows=$((rows + 1))
  if [ "$IDCOL" = 2 ]; then id=$idmain; else id=$idfix; fi
  [ -n "$id" ] && [ "$id" != "-" ] || { echo "BLIND: row $vid has no id for --landing $LANDING" >&2; exit 3; }
  case "$evfile" in /*|*..*) echo "BLIND: row $vid: evidence_file must be repository-relative without ..: $evfile" >&2; exit 3 ;; esac
  # round 4 (path-shape class): the last component must be a file name; '', '.', 'x/.' and 'x/' would make
  # mktemp and mv work on a directory and leave a temporary file behind.
  case "$evfile" in ''|.|*/|*/.) echo "BLIND: row $vid: evidence_file must end in a file name: '$evfile'" >&2; exit 3 ;; esac
  dest="$ROOT/$evfile"
  # round 2, F7: the evidence path must stay under --root; no component may be a symbolic link (a linked
  # directory or file would make the script write or read outside --root).
  p=$ROOT
  IFS=/ read -r -a parts <<<"$evfile"
  for c in "${parts[@]}"; do
    [ -n "$c" ] || continue
    p="$p/$c"
    if [ -L "$p" ]; then echo "BLIND: row $vid: evidence path component is a symbolic link: $p" >&2; exit 3; fi
  done
  # round 4: an existing entry that is not a regular file (a directory, a FIFO, a device) is never replaced
  # and never written into.
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then echo "BLIND: row $vid: evidence path exists and is not a regular file: $dest" >&2; exit 3; fi
  mkdir -p "$(dirname "$dest")" || exit 3
  real_dir=$(cd "$(dirname "$dest")" && pwd -P) || exit 3
  case "$real_dir/" in "$ROOT"/*) ;; *) echo "BLIND: row $vid: evidence directory $real_dir is outside --root $ROOT" >&2; exit 3 ;; esac
  if [ ! -f "$dest" ]; then
    tmp=$(mktemp "$dest.XXXXXX") || exit 3
    if ! git -C "$REPO" show "$commit:$gitpath" >"$tmp"; then
      rm -f -- "${tmp:?}"; echo "BLIND: git show $commit:$gitpath failed in $REPO" >&2; exit 3
    fi
    mv -- "$tmp" "$dest" || exit 3
  fi
  got=$(sha256sum "$dest" | cut -c1-64)
  if [ "$got" != "$sha" ]; then
    echo "BLIND: $evfile sha256 $got is not the plan's $sha" >&2; exit 3
  fi
  echo "== $vid -> $id ($LANDING): created_at := $value (evidence $commit:$gitpath, $attests)"
  args=(restore-created-at --db "$DB" --id "$id" --evidence-id "$vid" --value "$value"
        --evidence "$evfile" --evidence-sha256 "$sha" --reason "$reason")
  [ "$APPLY" = 1 ] || args+=(--dry-run)
  ( cd "$ROOT" && "$ENGINE" "${args[@]}" )
  rc=$?
  echo "   engine exit=$rc"
  [ "$rc" = 0 ] || refused=$((refused + 1))
done <"$PLAN"
[ "$rows" -gt 0 ] || { echo "BLIND: the plan has no rows" >&2; exit 3; }
echo "RESULT: rows=$rows refused=$refused mode=$([ "$APPLY" = 1 ] && echo apply || echo dry-run)"
[ "$refused" = 0 ] || exit 1
exit 0
