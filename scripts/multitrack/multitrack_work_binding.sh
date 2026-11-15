#!/usr/bin/env bash
# constitution/scripts/multitrack/multitrack_work_binding.sh
#
# §11.4.191 work-to-track/branch binding RESOLVER — the single, project-agnostic
# engine that answers "does this changed-file set (or this ticket) belong to a
# logic-group whose canonical branch/track is NOT the current checkout?". It is
# the shared lookup both entry points call: the PreToolUse guard hook
# (guard-work-track-binding.sh, the PREVENTIVE layer) AND the commit wrapper /
# pre-build gate (the DETECTIVE boundary).
#
# ── Purpose ────────────────────────────────────────────────────────────────
#   Map each input to its owning logic-group via the group_paths file-scope
#   manifest (longest-glob, most-specific wins) OR via items.logic_group for a
#   ticket, then look up logic_groups.destination (authoritative branch) +
#   logic_groups.canonical_track. BLOCK a change whose group's branch/track !=
#   the change's branch/track. Unclassified input (no glob owner / no ticket
#   group) is main-eligible → skipped (honest partial coverage, §11.4.3).
#
# ── Usage ──────────────────────────────────────────────────────────────────
#   multitrack_work_binding.sh resolve [--db P] [--file P]... [--files-from F|-]
#                                      [--ticket ATM-NNN]... [--staged]
#     → prints, per matched input: '<group>\t<dest-branch>\t<canonical-track>\t<input>'
#     → unmatched inputs print nothing; exit 0. Fail-closed exit 2 on unreadable DB.
#
#   multitrack_work_binding.sh check   --branch B [--track T] [--db P]
#                                      [--file P]... [--files-from F|-]
#                                      [--ticket ATM-NNN]... [--staged]
#     → exit 0  = every matched input agrees with (B[, T]);
#     → exit 2  = BLOCK — reason(s) on stderr (fed back to Claude by the hook);
#     → --staged (no --branch/--track): derive B = `git rev-parse --abbrev-ref
#       HEAD`, T from cwd /mnt/track<N>, and the file set from staged-or-worktree
#       (used by scripts/commit_all.sh: `multitrack_work_binding.sh check --staged`).
#
# ── Inputs ─────────────────────────────────────────────────────────────────
#   --db P         registry DB path (else $WI_DB, else <git-top>/docs/workable_items.db)
#   --branch B     the branch the change lands on / is dispatched to
#   --track  T     the track (track-<N>); '?' or '' => track assertion skipped (honest)
#   --file P       a repo-root-relative changed path (repeatable)
#   --files-from F one path per line (F='-' => stdin)
#   --ticket T     ATM-NNN / SPK-NNN (repeatable); resolved via items.logic_group
#   --staged       derive branch/track/file-set from git + cwd (check only)
#
# ── Outputs / exit codes ───────────────────────────────────────────────────
#   resolve → stdout tab-separated rows; exit 0 (2 fail-closed on unreadable DB).
#   check   → exit 0 allow / exit 2 BLOCK (reason on stderr) / exit 2 fail-closed.
#
# ── Side-effects ───────────────────────────────────────────────────────────
#   None. Read-only sqlite3 queries + read-only git plumbing. No writes, no locks.
#
# ── Dependencies ───────────────────────────────────────────────────────────
#   sqlite3 (fail-closed BLOCK if absent — §11.4.6, never allow-because-unverifiable);
#   git (only when --staged / cwd-track derivation is used). jq NOT required.
#
# ── Cross-references ───────────────────────────────────────────────────────
#   §11.4.191 (work-to-track binding) · §11.4.181/§11.4.182 (branch-name /
#   label consistency — this is the file-PLACEMENT generalisation) · §11.4.93/
#   §11.4.95 (workable-items DB SoT) · §11.4.6 (no-guessing / fail-closed) ·
#   §11.4.177/§11.4.28(B) (project-agnostic, inherited by reference — zero project
#   literals). Companion doc: constitution/docs/scripts/multitrack_work_binding.md.
#   Mirrors the DB-discovery + fail-closed discipline of
#   guard-branch-consistency.sh:289-335.
#
# Classification: universal.

set -uo pipefail

PROG="multitrack_work_binding"

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
usage() {
  cat <<'USAGE'
multitrack_work_binding.sh — §11.4.191 work-to-track/branch binding resolver.

  resolve [--db P] [--file P]... [--files-from F|-] [--ticket ATM-NNN]... [--staged]
      Print '<group>\t<dest-branch>\t<canonical-track>\t<input>' per matched input.

  check   --branch B [--track T] [--db P] [--file P]... [--files-from F|-]
          [--ticket ATM-NNN]... [--staged]
      Exit 0 = all matched inputs agree with (B[,T]); exit 2 = BLOCK (reason on
      stderr) OR fail-closed (unreadable registry / ambiguous scope).
      --staged (no --branch): derive branch/track/file-set from git + cwd.
USAGE
}

# --------------------------------------------------------------------------
# Argument parsing.
# --------------------------------------------------------------------------
SUBCMD="${1:-}"
if [ -z "$SUBCMD" ]; then
  echo "$PROG: missing subcommand (resolve|check). Try --help." >&2
  exit 2
fi
case "$SUBCMD" in
  resolve|check) shift ;;
  -h|--help)     usage; exit 0 ;;
  *) echo "$PROG: unknown subcommand '$SUBCMD' (resolve|check)." >&2; exit 2 ;;
esac

DB_ARG=""
BRANCH=""
TRACK=""
FILES_FROM=""
STAGED=0
FILES=()
TICKETS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --db)         DB_ARG="${2:-}";     shift 2 ;;
    --branch)     BRANCH="${2:-}";     shift 2 ;;
    --track)      TRACK="${2:-}";      shift 2 ;;
    --file)       FILES+=("${2:-}");   shift 2 ;;
    --files-from) FILES_FROM="${2:-}"; shift 2 ;;
    --ticket)     TICKETS+=("${2:-}"); shift 2 ;;
    --staged)     STAGED=1;            shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'." >&2; exit 2 ;;
  esac
done

# --------------------------------------------------------------------------
# Fail-closed exit (§11.4.6): registry unreadable => BLOCK, never allow-because-
# unverifiable. Same doctrine as guard-branch-consistency.sh:330-335.
# --------------------------------------------------------------------------
fail_closed() {
  echo "$PROG: BLOCKED (fail-closed, §11.4.6) — $1" >&2
  exit 2
}

# --------------------------------------------------------------------------
# Resolve the workable-items DB (registry SoT). $DB_ARG overrides; else $WI_DB;
# else the §11.4.93/§11.4.95 convention path relative to the git toplevel/cwd.
#
# SUBMODULE-CWD SUPERPROJECT-WALK (§11.4.191 fix, mirrors
# guard-work-track-binding.sh's resolve_workable_items_db — see that script's
# header for the forensic anchor). When THIS process's own cwd is INSIDE a
# nested submodule (e.g. the constitution submodule itself, edited/committed
# per §11.4.26), `$GIT_TOP` binds to the SUBMODULE's own innermost root, so
# `<submodule-root>/docs/workable_items.db` never exists there — the single
# project-level registry (§11.4.93/§11.4.95) lives at the OUTERMOST
# (super)project root, never inside a submodule. Previously ANY caller of
# this resolver invoked without an explicit `--db` (the guard now always
# supplies one; the detective gate `CM-WORK-TRACK-BINDING-ENFORCED` and any
# other direct invocation may not) fail-closed BLOCKed unconditionally from
# submodule cwd, regardless of file-scope classification.
#
# Fix: walk UP from `$GIT_TOP` through every `git rev-parse
# --show-superproject-working-tree` hop (depth-bounded to 10 — no realistic
# nesting exceeds the §11.4.28(C) depth-1 carve-out plus a safety margin),
# then probe every discovered OUTER root (excluding `$GIT_TOP` itself, which
# is already covered by the unchanged candidate list below) OUTERMOST-first
# for `docs/workable_items.db` / `docs/.workable_items.db`. This WIDENS
# discovery only — a non-nested checkout (no superproject) walks to zero
# outer roots, so the candidate list is byte-identical to the pre-fix
# behaviour. `$WI_DB` (checked first) and the plain cwd-relative /
# `$GIT_TOP`-relative candidates (checked after, in their original order)
# bracket the new outer-root candidates unchanged, so neither existing
# precedence nor the fail-closed-when-nothing-found guarantee (§11.4.6 — no
# weakening) below is disturbed.
# --------------------------------------------------------------------------
GIT_TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
DB_PATH=""
if [ -n "$DB_ARG" ]; then
  # Explicit --db is used EXCLUSIVELY: a named-but-absent registry is fail-closed
  # (via the `if [ -z "$DB_PATH" ]` check below), NEVER a silent fall-through to
  # auto-discovery of a DIFFERENT DB. The operator named THIS registry; reading
  # a different one instead would fail-OPEN on a stale/empty registry (§11.4.6).
  [ -f "$DB_ARG" ] && DB_PATH="$DB_ARG"
else
  _wtb_outer_cands=()
  if [ -n "$GIT_TOP" ]; then
    _wtb_d="$GIT_TOP"
    _wtb_hops=0
    _wtb_outer_roots=()
    while [ "$_wtb_hops" -lt 10 ]; do
      _wtb_sp="$(cd "$_wtb_d" 2>/dev/null && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
      [ -n "$_wtb_sp" ] || break
      _wtb_outer_roots+=("$_wtb_sp")
      _wtb_d="$_wtb_sp"
      _wtb_hops=$((_wtb_hops + 1))
    done
    # Outermost-first: the real registry lives at the ultimate parent
    # project's root, never a submodule's own (mirrors the guard's walk).
    for (( _wtb_i = ${#_wtb_outer_roots[@]} - 1; _wtb_i >= 0; _wtb_i-- )); do
      _wtb_outer_cands+=("${_wtb_outer_roots[$_wtb_i]}/docs/workable_items.db" "${_wtb_outer_roots[$_wtb_i]}/docs/.workable_items.db")
    done
  fi
  for _cand in \
      "${WI_DB:-}" \
      ${_wtb_outer_cands[@]+"${_wtb_outer_cands[@]}"} \
      "${GIT_TOP:+$GIT_TOP/docs/workable_items.db}" \
      "docs/workable_items.db" \
      "${GIT_TOP:+$GIT_TOP/docs/.workable_items.db}" \
      "docs/.workable_items.db"; do
    [ -n "$_cand" ] || continue
    if [ -f "$_cand" ]; then DB_PATH="$_cand"; break; fi
  done
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  fail_closed "sqlite3 unavailable — cannot read logic_groups/group_paths to verify work placement."
fi
if [ -z "$DB_PATH" ]; then
  fail_closed "workable-items DB not found (set \$WI_DB or --db, or run from the project tree)."
fi

# Verify the DB is actually READABLE with the expected schema — `-f` (file
# exists) is NOT the same as `readable sqlite DB with logic_groups`: a corrupt /
# non-sqlite / truncated / permission-denied / pre-v4 file passes `-f` but fails
# every query, and the `2>/dev/null || true` on the registry-load queries below
# would silently degrade that to an EMPTY registry => "no owner => allow"
# (fail-OPEN). §11.4.6 fail-closed: an unverifiable registry BLOCKS, never allows.
_wtb_schema="$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='logic_groups';" 2>/dev/null || echo '__WTB_DB_ERR__')"
if [ "$_wtb_schema" != "logic_groups" ]; then
  fail_closed "workable-items DB unreadable or missing 'logic_groups' table (corrupt / non-sqlite / pre-v4 schema): $DB_PATH"
fi

# --------------------------------------------------------------------------
# --staged (check only): derive branch/track/file-set from git + cwd.
# --------------------------------------------------------------------------
current_track_from_cwd() {
  local d
  d="$(pwd -P 2>/dev/null || pwd)"
  case "$d" in
    /mnt/track[0-9]*)
      local n="${d#/mnt/track}"; n="${n%%/*}"
      case "$n" in ''|*[!0-9]*) printf '?' ;; *) printf 'track-%s' "$n" ;; esac
      ;;
    *) printf '?' ;;
  esac
}

if [ "$STAGED" -eq 1 ]; then
  [ -n "$BRANCH" ] || BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -n "$TRACK" ]  || TRACK="$(current_track_from_cwd)"
  _staged_set="$(git diff --cached --name-only 2>/dev/null || true)"
  if [ -n "$_staged_set" ]; then
    while IFS= read -r _p; do [ -n "$_p" ] && FILES+=("$_p"); done <<EOF
$_staged_set
EOF
  else
    # Nothing staged: a commit_all-class broad stage sweeps the whole dirty tree.
    _wt_set="$(git status --porcelain --untracked-files=all 2>/dev/null | sed 's/^...//; s/^.* -> //' || true)"
    while IFS= read -r _p; do [ -n "$_p" ] && FILES+=("$_p"); done <<EOF
$_wt_set
EOF
  fi
fi

# --------------------------------------------------------------------------
# Gather --files-from (F='-' => stdin).
# --------------------------------------------------------------------------
if [ -n "$FILES_FROM" ]; then
  if [ "$FILES_FROM" = "-" ]; then
    while IFS= read -r _p; do [ -n "$_p" ] && FILES+=("$_p"); done
  elif [ -f "$FILES_FROM" ]; then
    while IFS= read -r _p; do [ -n "$_p" ] && FILES+=("$_p"); done < "$FILES_FROM"
  else
    fail_closed "--files-from path not found: $FILES_FROM"
  fi
fi

# --------------------------------------------------------------------------
# Load the registry into memory (one round-trip each). `|` is a safe separator:
# group_ids, branches, tracks and path globs never contain it.
# group_paths may be absent on a pre-v4 DB (2>/dev/null || true) => no file
# owners => honest partial coverage (branch-enforced-only until the manifest
# lands); TICKET resolution still works via items/logic_groups.
# --------------------------------------------------------------------------
declare -A DEST_OF=()      # group_id -> branch (feature:x normalised to feature/x)
declare -A CTRACK_OF=()    # group_id -> canonical_track ('' when NULL)
GP=()                      # each = 'group_id|path_glob'

while IFS='|' read -r _g _d _t; do
  [ -n "$_g" ] || continue
  DEST_OF["$_g"]="$_d"
  CTRACK_OF["$_g"]="$_t"
done <<EOF
$(sqlite3 "$DB_PATH" "SELECT group_id, REPLACE(destination,'feature:','feature/'), COALESCE(canonical_track,'') FROM logic_groups;" 2>/dev/null || true)
EOF

while IFS='|' read -r _g _glob; do
  [ -n "$_g" ] || continue
  [ -n "$_glob" ] || continue
  GP+=("$_g|$_glob")
done <<EOF
$(sqlite3 "$DB_PATH" "SELECT group_id, path_glob FROM group_paths;" 2>/dev/null || true)
EOF

# --------------------------------------------------------------------------
# Resolution helpers set globals (NOT stdout) so ambiguity flags survive — a
# `$(…)` capture would run them in a subshell and lose the flag (§11.4.6: an
# unverifiable ambiguity that silently vanishes is a bluff). Contract:
#   WTB_OWNER        -> owning group_id ('' = unclassified -> skip)
#   WTB_AMBIG        -> 1 when the input maps ambiguously (fail-closed BLOCK)
#   WTB_AMBIG_DETAIL -> human-readable ambiguity description
WTB_OWNER=""
WTB_AMBIG=0
WTB_AMBIG_DETAIL=""

# owner_of_file <path> — longest-glob (most-specific) owner. Ambiguous ties (two
# DIFFERENT groups at the same max glob length) set WTB_AMBIG=1. Uses
# `[[ path == glob ]]` pattern matching (glob unquoted): '*'/'**' match any run
# of chars incl '/'.
owner_of_file() {
  local path="$1" best_len=-1 best_group="" entry g glob len
  WTB_OWNER=""; WTB_AMBIG=0; WTB_AMBIG_DETAIL=""
  for entry in ${GP[@]+"${GP[@]}"}; do
    g="${entry%%|*}"
    glob="${entry#*|}"
    # shellcheck disable=SC2053
    if [[ "$path" == $glob ]]; then
      len=${#glob}
      if [ "$len" -gt "$best_len" ]; then
        best_len="$len"; best_group="$g"; WTB_AMBIG=0; WTB_AMBIG_DETAIL=""
      elif [ "$len" -eq "$best_len" ] && [ "$g" != "$best_group" ]; then
        WTB_AMBIG=1; WTB_AMBIG_DETAIL="'$best_group' and '$g' both claim '$path' at glob length $len"
      fi
    fi
  done
  WTB_OWNER="$best_group"
}

# ticket_group <ATM-NNN> — DISTINCT items.logic_group for the ticket. Empty =>
# unclassified (skip). >1 distinct group => ambiguous (fail-closed BLOCK). The
# ticket is validated against [A-Z]+-[0-9]+ before it is interpolated.
ticket_group() {
  local t="$1" rows n _qrc
  WTB_OWNER=""; WTB_AMBIG=0; WTB_AMBIG_DETAIL=""
  # STRICT anchored full-match (NO trailing wildcard). The prior `case
  # [A-Z]*-[0-9]*` glob's trailing `*` let a quote/semicolon-bearing suffix
  # (e.g. "ATM-1'; SELECT …") pass validation and be interpolated UNESCAPED into
  # the SQL below — an injection surface AND a fail-open (an errored query then
  # degraded to "unclassified => allow"). Reject anything that is not exactly
  # <UPPER>+-<DIGITS>+ (§11.4.6 no-guessing / §11.4.10 no-injection).
  # WHOLE-STRING anchored match. bash `[[ =~ ]]` anchors `^`/`$` to string start/end
  # (regexec without REG_NEWLINE) — unlike a line-oriented `grep -qE`, which would
  # accept a MULTI-LINE payload whose FIRST line is ticket-shaped (`ATM-1\n' UNION
  # SELECT …`) and let the newline-bearing remainder be interpolated UNESCAPED into
  # the SQL below (RV-A' proved that bypass). Reject anything that is not exactly
  # <UPPER>+-<DIGITS>+ across the WHOLE string (§11.4.6 / §11.4.10 no-injection).
  if ! [[ "$t" =~ ^[A-Z]+-[0-9]+$ ]]; then
    fail_closed "malformed ticket id '$t' (expected e.g. ATM-123 — strict whole-string anchored form)."
  fi
  rows="$(sqlite3 "$DB_PATH" "SELECT DISTINCT logic_group FROM items WHERE atm_id='$t' AND logic_group IS NOT NULL AND logic_group != '';" 2>/dev/null)"; _qrc=$?
  # Fail-CLOSED on a query error (DB locked / corrupt mid-run): an errored query
  # returning empty must NOT degrade to "unclassified => allow" (§11.4.6 fail-open ban).
  [ "$_qrc" -eq 0 ] || fail_closed "ticket registry query failed (rc=$_qrc) for '$t' — registry unreadable mid-query."
  n="$(printf '%s\n' "$rows" | grep -c . || true)"
  if [ "${n:-0}" -gt 1 ]; then
    WTB_AMBIG=1
    WTB_AMBIG_DETAIL="ticket '$t' maps to >1 logic_group: $(printf '%s' "$rows" | tr '\n' ',' )"
    return 0
  fi
  WTB_OWNER="$(printf '%s\n' "$rows" | grep . | head -n1 || true)"
}

# --------------------------------------------------------------------------
# Emit the resolved binding for a matched input (resolve subcommand).
# --------------------------------------------------------------------------
emit_resolved() {
  local grp="$1" label="$2"
  printf '%s\t%s\t%s\t%s\n' "$grp" "${DEST_OF[$grp]:-}" "${CTRACK_OF[$grp]:-}" "$label"
}

# --------------------------------------------------------------------------
# verdict_for <group> <label> — append BLOCK reason(s) to VIOLATIONS if the
# group's canonical branch/track disagrees with (BRANCH[, TRACK]).
# --------------------------------------------------------------------------
VIOLATIONS=""
verdict_for() {
  local grp="$1" label="$2"
  local dest="${DEST_OF[$grp]:-}" ctrack="${CTRACK_OF[$grp]:-}"
  # LOAD-BEARING branch comparison (the §6 paired-mutation target). Do NOT
  # collapse or short-circuit: stripping this clause must make the gate pass a
  # planted mis-placement, proving the comparison is load-bearing.
  if [ "$dest" != "$BRANCH" ]; then
    VIOLATIONS="${VIOLATIONS}  - ${label}: owned by group '${grp}' whose canonical branch is '${dest}', but the change is on '${BRANCH}' (§11.4.191).
"
  fi
  # Track assertion only when the group is track-pinned AND the change's track
  # is known (not '' / '?') — honest boundary (§11.4.6): an unknown track is not
  # a proven mismatch, so it is never blocked on track.
  if [ -n "$ctrack" ] && [ -n "$TRACK" ] && [ "$TRACK" != "?" ] && [ "$ctrack" != "$TRACK" ]; then
    VIOLATIONS="${VIOLATIONS}  - ${label}: owned by group '${grp}' pinned to canonical track '${ctrack}', but the change is on track '${TRACK}' (§11.4.191).
"
  fi
}

# --------------------------------------------------------------------------
# Drive resolve / check over files + tickets.
# --------------------------------------------------------------------------
FAIL_AMBIG=""

process_file() {
  local p="$1" grp
  owner_of_file "$p"
  if [ "$WTB_AMBIG" -eq 1 ]; then
    FAIL_AMBIG="${FAIL_AMBIG}  - ambiguous file scope: ${WTB_AMBIG_DETAIL}
"
    return 0
  fi
  grp="$WTB_OWNER"
  [ -n "$grp" ] || return 0   # unclassified -> main-eligible -> skip
  if [ "$SUBCMD" = "resolve" ]; then emit_resolved "$grp" "$p"; else verdict_for "$grp" "$p"; fi
}

process_ticket() {
  local t="$1" grp
  ticket_group "$t"
  if [ "$WTB_AMBIG" -eq 1 ]; then
    FAIL_AMBIG="${FAIL_AMBIG}  - ambiguous ticket scope: ${WTB_AMBIG_DETAIL}
"
    return 0
  fi
  grp="$WTB_OWNER"
  [ -n "$grp" ] || return 0   # unticketed / unclassified -> skip
  if [ "$SUBCMD" = "resolve" ]; then emit_resolved "$grp" "$t"; else verdict_for "$grp" "$t"; fi
}

for _f in ${FILES[@]+"${FILES[@]}"}; do
  [ -n "$_f" ] && process_file "$_f"
done
for _t in ${TICKETS[@]+"${TICKETS[@]}"}; do
  [ -n "$_t" ] && process_ticket "$_t"
done

# check requires a branch to compare against (unless --staged supplied it).
if [ "$SUBCMD" = "check" ] && [ -z "$BRANCH" ]; then
  fail_closed "check needs --branch (or --staged) to know which branch the change lands on."
fi

if [ -n "$FAIL_AMBIG" ]; then
  {
    echo "$PROG: BLOCKED (fail-closed, §11.4.6) — ambiguous work-scope binding:"
    printf '%s' "$FAIL_AMBIG"
    echo "  Make the group_paths globs precise (most-specific ownership) and retry."
  } >&2
  exit 2
fi

if [ "$SUBCMD" = "check" ] && [ -n "$VIOLATIONS" ]; then
  {
    echo "$PROG: BLOCKED — §11.4.191 work-to-track/branch binding:"
    printf '%s' "$VIOLATIONS"
    echo "  A logic-group's work MUST land on / be dispatched to its canonical (branch, track) ONLY."
    echo "  Reconcile by MERGING onto the group's canonical branch (§11.4.191(4)/§11.4.113 — never force-push),"
    echo "  or, for a genuine one-off, append '# guardrails:allow <reason>' to the commit command."
  } >&2
  exit 2
fi

exit 0
