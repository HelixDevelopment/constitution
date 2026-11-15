#!/usr/bin/env bash
# scripts/hooks/guard-work-track-binding.sh
#
# Claude Code PreToolUse guard hook (mechanical block) enforcing constitution
# §11.4.191 (work-to-track/branch binding) at the tool-call boundary — the
# PREVENTIVE layer. It makes a mis-track COMMIT or a mis-track DISPATCH
# IMPOSSIBLE to issue, independent of any agent's recall (§11.4.109 anti-
# forgetting; a rule the orchestrator forgets to paste is not enforcement).
# §11.4.191 is the file-PLACEMENT generalisation of §11.4.181 (branch-NAME
# consistency): the sibling guard-branch-consistency.sh fires only on a
# feature-branch CREATE, so committing a logic-group's files onto an
# already-existing branch (the scrcpy → main mis-landing, 2026-07-04) slipped
# past it. This hook closes exactly that gap.
#
# CONTRACT (Claude Code PreToolUse hook):
#   - Receives the tool invocation as JSON on stdin.
#   - Exit 0  -> allow (Claude proceeds).
#   - Exit 2  -> BLOCK; stderr text is fed back to Claude as the refusal reason.
#   - Any other exit -> non-blocking error (never used).
#
# SCOPE (two handled classes; every other tool passes through exit 0):
#   - Bash  -> a git-commit-class command (the mis-COMMIT path). The to-be-
#     committed file set (git plumbing: staged, else the dirty worktree for a
#     commit_all-class broad stage) is resolved against the current branch/track.
#   - Agent | Task | TaskCreate -> an agent dispatch (the mis-DISPATCH path). The
#     §11.4.182 `(T<N>/<branch> …)` label + the ATM-/SPK- ticket(s) in the
#     description are resolved against the ticket's group's canonical (branch,
#     track).
#
# WHAT IT BLOCKS / ALLOWS: it delegates the actual (branch, track) decision to
# the shared resolver multitrack_work_binding.sh (single code path, two entry
# points). The resolver BLOCKs (exit 2) when a group_paths-owned file / a
# ticket's group has a canonical branch/track != the change's, and FAIL-CLOSES
# (exit 2) when the registry cannot be read or a scope is ambiguous. An
# unclassified file (no glob owner) / an unticketed dispatch is main-eligible →
# allowed (honest partial coverage, §11.4.3). A `# guardrails:allow <reason>`
# marker downgrades a commit-path block to an audited WARN (mirrors
# guard-forbidden-commands.sh / guard-branch-consistency.sh).
#
# HONEST BOUNDARY (§11.4.6 — best-effort prevention, NOT a security boundary):
# the file set is derived from git PLUMBING (staged/worktree), never argv-parsed,
# so a `$(…)`/backtick-fed dynamic PATHSPEC that would commit a DIFFERENT subset
# than the plumbing set cannot be verified — those commit-path calls fail-closed
# to BLOCK (clearable with the escape marker). A raw `git` invoked from inside a
# script this hook never parses is caught by the DETECTIVE pre-build gate
# CM-WORK-TRACK-BINDING-ENFORCED, which inspects the real committed diff
# regardless of HOW the commit happened — THAT gate is the enforcement boundary;
# this hook is defense-in-depth (same split as guard-branch-consistency.sh:33-45).
#
# DECOUPLING (§11.4.177 / §11.4.28(B)): lives in the constitution submodule,
# inherited BY REFERENCE (never copied). Project-agnostic — reads only the
# §11.4.93/§11.4.95 universal DB (via the resolver) + cwd + git, zero project
# literals. Companion doc: constitution/docs/scripts/guard-work-track-binding.md.
#
# SUBMODULE-COMMIT DB RESOLUTION: when this guard's own cwd is INSIDE a
# submodule (e.g. this constitution submodule, committed per §11.4.26), the
# shared resolver's own auto-discovery binds to `git rev-parse
# --show-toplevel` — the SUBMODULE's innermost root — so `docs/
# workable_items.db` never exists there and the resolver fail-closed BLOCKs
# every legitimate submodule commit unconditionally. `resolve_workable_items_db`
# (below) walks UP through every nested submodule -> superproject link
# (`git rev-parse --show-superproject-working-tree`) so the guard passes an
# explicit `--db` pointing at the real registry in the PARENT (super)project
# root whenever one is found there; when none is found anywhere the walk
# resolves to empty and `--db` is simply omitted, so the resolver's own
# unchanged auto-discovery + fail-closed BLOCK still applies (§11.4.6 — no
# weakening of the fail-closed guarantee).
#
# Classification: universal.

set -uo pipefail

PAYLOAD="$(cat || true)"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$HOOK_DIR/../multitrack/multitrack_work_binding.sh"

# --------------------------------------------------------------------------
# Extract a JSON string field WITHOUT requiring jq (prefer jq if present).
# Leaf keys we need: tool_name, command, description, subagent. Same extractor
# as guard-branch-consistency.sh:79-125 / guard-track-branch-label.sh:41-88.
# --------------------------------------------------------------------------
json_field() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | jq -r "$path // empty" 2>/dev/null || true
    return 0
  fi
  local key
  case "$path" in
    .tool_name)               key="tool_name" ;;
    .tool_input.command)      key="command" ;;
    .tool_input.description)  key="description" ;;
    .tool_input.subagent)     key="subagent" ;;
    *)                        key="${path##*.}" ;;
  esac
  printf '%s' "$PAYLOAD" | awk -v key="$key" '
    BEGIN { RS="\0" }
    {
      s = $0
      idx = index(s, "\"" key "\"")
      if (idx == 0) { exit }
      rest = substr(s, idx + length(key) + 2)
      sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") { exit }
      rest = substr(rest, 2)
      out = ""
      i = 1
      n = length(rest)
      while (i <= n) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          nx = substr(rest, i+1, 1)
          if (nx == "n") out = out "\n"
          else if (nx == "t") out = out "\t"
          else if (nx == "r") out = out "\r"
          else if (nx == "\"") out = out "\""
          else if (nx == "\\") out = out "\\"
          else if (nx == "/") out = out "/"
          else out = out nx
          i += 2
          continue
        }
        if (c == "\"") break
        out = out c
        i += 1
      }
      printf "%s", out
    }
  '
}

TOOL_NAME="$(json_field .tool_name)"

# --------------------------------------------------------------------------
# current_track — cwd /mnt/track<N>/... -> track-<N>, else '?' (honest;
# mirrors guard-track-branch-label.sh:117-127).
# --------------------------------------------------------------------------
current_track() {
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

# --------------------------------------------------------------------------
# resolve_workable_items_db — locate the §11.4.93/§11.4.95 workable-items DB
# from THIS guard's own git context, walking UP through every nested
# submodule -> superproject link (`git rev-parse --show-superproject-working-
# tree`) so a commit/dispatch whose cwd is INSIDE a submodule (e.g. this
# constitution submodule itself, committed per §11.4.26) resolves against the
# PARENT (super)project's registry — never a submodule-relative path where
# the DB does not live. Without this walk, `multitrack_work_binding.sh`'s own
# auto-discovery binds `git rev-parse --show-toplevel` to the SUBMODULE's own
# root (its innermost repo), so `<submodule-root>/docs/workable_items.db`
# never exists and the resolver fail-closes — BLOCKING every legitimate
# submodule commit unconditionally, regardless of file-scope classification.
#
# $WI_DB (if set) wins outright — same override the resolver itself honours;
# this function returns it verbatim (even if the path doesn't exist) so the
# existing fail-closed behaviour for an explicit-but-absent override is
# unchanged. Otherwise: walk from `git rev-parse --show-toplevel` up through
# every `--show-superproject-working-tree` hop (depth-bounded to 10 — no
# realistic nesting exceeds the §11.4.28(C) depth-1 carve-out plus a safety
# margin) and probe each root, OUTERMOST first, for
# `docs/workable_items.db` / `docs/.workable_items.db`. Prints the first
# match, or empty when none is found (in which case the caller omits --db so
# the resolver's own — unchanged — auto-discovery + fail-closed applies,
# preserving today's behaviour for the non-submodule / DB-genuinely-absent
# case). This function NEVER itself fails or blocks — it only WIDENS where a
# real registry is discovered; the resolver alone owns the fail-closed BLOCK
# decision (§11.4.6).
# --------------------------------------------------------------------------
resolve_workable_items_db() {
  if [ -n "${WI_DB:-}" ]; then
    printf '%s' "$WI_DB"
    return 0
  fi
  local git_top d sp hops=0
  git_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$git_top" ] || { printf ''; return 0; }
  local roots=("$git_top")
  d="$git_top"
  while [ "$hops" -lt 10 ]; do
    sp="$(cd "$d" 2>/dev/null && git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
    [ -n "$sp" ] || break
    roots+=("$sp")
    d="$sp"
    hops=$((hops + 1))
  done
  # Probe OUTERMOST-first (the last element walked to) — the real registry
  # lives at the ultimate parent project's root, never a submodule's own.
  local i cand
  for (( i = ${#roots[@]} - 1; i >= 0; i-- )); do
    for cand in "${roots[$i]}/docs/workable_items.db" "${roots[$i]}/docs/.workable_items.db"; do
      if [ -f "$cand" ]; then printf '%s' "$cand"; return 0; fi
    done
  done
  printf ''
}

# ==========================================================================
# DISPATCH path — Agent | Task | TaskCreate.
# ==========================================================================
if [ "$TOOL_NAME" = "Agent" ] || [ "$TOOL_NAME" = "Task" ] || [ "$TOOL_NAME" = "TaskCreate" ]; then
  LABEL="$(json_field .tool_input.description)"
  [ -n "$LABEL" ] || LABEL="$(json_field .tool_input.subagent)"

  # Parse the §11.4.182 prefix (T<N>/<branch>[ - <alias>]). If absent/malformed,
  # exit 0 — the SIBLING guard-track-branch-label.sh BLOCKs that (single
  # responsibility; do not double-report).
  if [[ ! "$LABEL" =~ ^\(T([0-9]+)/([^\)]+)\) ]]; then
    exit 0
  fi
  T_LBL="track-${BASH_REMATCH[1]}"
  B_FIELD="${BASH_REMATCH[2]}"
  # Strip a trailing ' - <alias>' (a git branch ref never contains a space, so
  # any ' - ' inside the field is the §11.4.182 alias separator).
  B_LBL="$B_FIELD"
  if [[ "$B_FIELD" == *" - "* ]]; then
    B_LBL="${B_FIELD%% - *}"
  fi

  # Extract the work ticket(s): \b(ATM|SPK)-[0-9]+\b.
  TICKETS="$(printf '%s' "$LABEL" | grep -oE '\b(ATM|SPK)-[0-9]+\b' | sort -u || true)"
  [ -n "$TICKETS" ] || exit 0   # nothing to bind against; label hook enforced format

  ARGS=(check --branch "$B_LBL" --track "$T_LBL")
  WTB_DB="$(resolve_workable_items_db)"
  [ -n "$WTB_DB" ] && ARGS+=(--db "$WTB_DB")
  while IFS= read -r _t; do
    [ -n "$_t" ] && ARGS+=(--ticket "$_t")
  done <<EOF
$TICKETS
EOF

  RES_OUT="$(bash "$RESOLVER" "${ARGS[@]}" 2>&1)"
  RES_RC=$?
  if [ "$RES_RC" -ne 0 ]; then
    LABEL1="$(printf '%s' "$LABEL" | head -n1)"
    {
      echo "guardrails: BLOCKED — §11.4.191 work-to-track/branch binding (dispatch)"
      echo "  Dispatch label: ${LABEL1}"
      echo "  This ${TOOL_NAME} would work a ticket whose logic-group is bound to a"
      echo "  DIFFERENT (branch, track) than the label declares."
      printf '%s\n' "$RES_OUT" | sed 's/^/  /'
    } >&2
    exit 2
  fi
  exit 0
fi

# ==========================================================================
# COMMIT path — Bash. Everything else passes through untouched.
# ==========================================================================
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

CMD="$(json_field .tool_input.command)"
[ -n "$CMD" ] || exit 0

# --- Commit-intent detection (argv-segment-aware, executable == git commit /
#     commit_all.sh / commit_docs.sh; same honesty as guard-branch-consistency
#     .sh:203-256). BROAD_STAGE marks a whole-worktree sweep (commit_all.sh /
#     commit_docs.sh / `git add -A|.|--all` / `git commit -a|--all`).
COMMIT_INTENT=0
BROAD_STAGE=0
DYN_PATHSPEC=0

# Split on ; && || | and newlines; judge each segment on its own executable.
_scan_segments() {
  printf '%s' "$1" | awk '
    {
      nseg = split($0, seg, /&&|\|\||;|\|/)
      for (i = 1; i <= nseg; i++) {
        s = seg[i]; sub(/^[ \t]+/, "", s)
        if (s ~ /^#/) continue
        # strip leading VAR= assignments and env/sudo-style prefixes
        chg = 1
        while (chg) {
          chg = 0
          if (s ~ /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/) { sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/, "", s); chg = 1 }
          if (s ~ /^(env|command|nohup|time|nice|ionice|bash|sh)[ \t]+/) { sub(/^(env|command|nohup|time|nice|ionice|bash|sh)[ \t]+/, "", s); chg = 1 }
        }
        exe = s; sub(/[ \t].*$/, "", exe); sub(/^.*\//, "", exe)   # basename of first token
        if (exe == "git") {
          if (s ~ /^([^ \t]*\/)?git[ \t]+commit([ \t]|$)/) {
            print "COMMIT"
            if (s ~ /[ \t](-a|--all)([ \t]|$)/) print "BROAD"
            if (s ~ /--[ \t].*(\$\(|`)/) print "DYN"        # dynamic pathspec after `--`
          } else if (s ~ /^([^ \t]*\/)?git[ \t]+add([ \t]|$)/) {
            if (s ~ /[ \t](-A|--all|\.)([ \t]|$)/) print "BROAD"
            if (s ~ /(\$\(|`)/) print "DYN"                 # `git add $(…)` dynamic set
          }
        } else if (exe == "commit_all.sh" || exe == "commit_docs.sh") {
          print "COMMIT"; print "BROAD"
        }
      }
    }'
}
_SCAN="$(_scan_segments "$CMD")"
printf '%s\n' "$_SCAN" | grep -qx 'COMMIT' && COMMIT_INTENT=1
printf '%s\n' "$_SCAN" | grep -qx 'BROAD'  && BROAD_STAGE=1
printf '%s\n' "$_SCAN" | grep -qx 'DYN'    && DYN_PATHSPEC=1

[ "$COMMIT_INTENT" -eq 1 ] || exit 0

# --- Documented-exception escape hatch (mirrors guard-forbidden-commands.sh):
#     `# guardrails:allow <reason>` downgrades the block to an audited WARN.
ESCAPE=0
if [[ "$CMD" =~ \#[[:space:]]*guardrails:allow[[:space:]]+(.+) ]]; then
  ESCAPE=1
  ESCAPE_REASON="${BASH_REMATCH[1]}"
fi

# --- Fail-closed (§11.4.6): a dynamic pathspec we cannot resolve against the
#     plumbing set. Escape marker clears it (an operator-vetted dynamic commit).
if [ "$DYN_PATHSPEC" -eq 1 ]; then
  if [ "$ESCAPE" -eq 1 ]; then
    echo "guardrails: WARNING — §11.4.191: dynamic \$(…) pathspec in a commit; allowed by documented exception: ${ESCAPE_REASON}" >&2
    exit 0
  fi
  {
    echo "guardrails: BLOCKED — §11.4.191 (fail-closed, §11.4.6)"
    echo "  A commit with a \$(…)/backtick-fed pathspec cannot be verified against the"
    echo "  registered work-scope. Stage explicitly (git add <paths>) or, for a vetted"
    echo "  one-off, append '# guardrails:allow <reason>' to the command."
  } >&2
  exit 2
fi

# --- Resolve the to-be-committed file set from git plumbing (§2.2 step 3):
#     staged if non-empty; else, for a broad stage, the whole dirty worktree.
STAGED_SET="$(git diff --cached --name-only 2>/dev/null || true)"
FILESET=""
if [ -n "$STAGED_SET" ]; then
  FILESET="$STAGED_SET"
elif [ "$BROAD_STAGE" -eq 1 ]; then
  FILESET="$(git --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null | sed 's/^...//; s/^.* -> //' || true)"
fi
[ -n "$FILESET" ] || exit 0   # nothing to commit -> nothing to check

B_CUR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
T_CUR="$(current_track)"

# --- Delegate to the shared resolver (fail-closed on unreadable DB / ambiguity).
#     WTB_DB_ARGS carries an explicit --db when this guard's OWN submodule-
#     aware walk (resolve_workable_items_db) finds the real registry — e.g.
#     when cwd is inside a submodule and the resolver's own toplevel-only
#     auto-discovery would otherwise miss the parent (super)project's DB.
WTB_DB="$(resolve_workable_items_db)"
WTB_DB_ARGS=()
[ -n "$WTB_DB" ] && WTB_DB_ARGS=(--db "$WTB_DB")
RES_OUT="$(printf '%s\n' "$FILESET" | bash "$RESOLVER" check --branch "$B_CUR" --track "$T_CUR" "${WTB_DB_ARGS[@]}" --files-from - 2>&1)"
RES_RC=$?
if [ "$RES_RC" -eq 0 ]; then
  exit 0
fi

if [ "$ESCAPE" -eq 1 ]; then
  echo "guardrails: WARNING — §11.4.191 work-to-track/branch binding; allowed by documented exception: ${ESCAPE_REASON}" >&2
  echo "  (resolver said: $(printf '%s' "$RES_OUT" | tr '\n' ' '))" >&2
  exit 0
fi

{
  echo "guardrails: BLOCKED — §11.4.191 work-to-track/branch binding (commit)"
  echo "  Current checkout: branch '${B_CUR:-?}' / track '${T_CUR}'."
  echo "  The staged change contains file(s) owned by a logic-group bound to a"
  echo "  DIFFERENT canonical (branch, track):"
  printf '%s\n' "$RES_OUT" | sed 's/^/  /'
} >&2
exit 2
