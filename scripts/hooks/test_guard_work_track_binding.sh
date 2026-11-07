#!/usr/bin/env bash
# test_guard_work_track_binding.sh — hermetic test suite for the §11.4.191
# work-to-track/branch binding PreToolUse guard (guard-work-track-binding.sh)
# and its shared resolver (multitrack_work_binding.sh).
#
# Anti-bluff (§11.4.107(10) analogue): the suite proves the guard BLOCKS (exit 2)
# a mis-track COMMIT (a logic-group's file staged on the wrong branch) AND a
# mis-track DISPATCH (an ATM ticket dispatched onto the wrong (track, branch)),
# ALLOWS (exit 0) a correctly-placed commit / dispatch / an unclassified path /
# an unticketed dispatch / a documented `# guardrails:allow` exception / a
# non-Bash-non-Agent tool, and FAIL-CLOSES (exit 2) on an unreadable registry, an
# ambiguous file-scope, and a dynamic `$(…)` pathspec — so the enforcement itself
# provably cannot bluff (both block AND allow AND fail-closed exercised).
#
# The registry SoT is a throwaway sqlite DB built here; the commit-path cases use
# a throwaway git repo with a real initial commit (so `git rev-parse
# --abbrev-ref HEAD` yields a born branch name). No project DB, no project git
# tree, no binary dependency — fully self-contained.
#
# Usage: bash constitution/scripts/hooks/test_guard_work_track_binding.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed (or a premise of the suite is false:
# every such refusal prints "PRECONDITION FAIL: <one cause>" and no case runs).
#
# Environment:
#   TMPDIR              where the fixtures are built; must name an existing directory (a relative one is
#                       resolved at start); when its PHYSICAL path is under /mnt/track<N> the fixtures go to /tmp.
#   GWTB_TRACK_LAYOUT   how section E gets a cwd whose physical path is /mnt/track<N>/...:
#                         auto (default) a private mount namespace (unshare -Urm) that shows /mnt/track12, else
#                                        a writable /mnt/track<N> of the host, else the 7 cases are SKIPPED
#                                        (printed as SKIP, counted apart, never as PASS);
#                         ns | real      only that source; refuses (PRECONDITION FAIL) when it is not available;
#                         none           skip the 7 cases on purpose.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-work-track-binding.sh"
RES="$HERE/../multitrack/multitrack_work_binding.sh"

PASS=0
FAIL=0

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 unavailable — the registry-backed cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git unavailable — the commit-path cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Throwaway registry (schema-v4 shape: logic_groups.canonical_track + group_paths).
#   mistiq-vader   -> feature/mistiq-vader / track-2   (the incident group)
#   token-reduction-> main                / track-1
#   unified-product-> main                / track-1    (SINGLE-TRACK binding: a group
#                     whose work lives on trunk + one pinned track, the shape a consumer
#                     registry takes after an operator ruling that all work happens on one
#                     track; file-scoped via group_paths so the commit path is exercised too)
#   roster-2026-07 -> feature/roster-2026-07 / NULL    (branch-enforced-only)
#   grp-a / grp-b  -> same-length globs claiming one 'ambig/' file (ambiguity probe)
#   trk-here / trk-away -> main / pinned to track-$TL_N and track-$((TL_N + 1)): section E's probes of the
#                     track the hook derives from its cwd ($TL_N = the track number of the layout it runs under)
# The feature-bound 'mistiq-vader' row stays: the multi-track path (a group pinned to a
# feature branch + track) is still a supported registry shape and keeps its coverage; the
# group id is test data, not a statement about any consumer's live registry.
# ---------------------------------------------------------------------------
# Fixture root outside /mnt/track<N>. The hook derives the CURRENT TRACK from its physical cwd
# (current_track: /mnt/track<N>/... -> track-<N>, anything else -> '?') and every commit-path case
# below runs the hook from a cwd inside this root and is written for track '?'. With TMPDIR under
# /mnt/track4 (exported by a consumer's pre-build launcher) the hook derived 'track-4' and BLOCKED
# the two pinned-track ALLOW cases (track-2 mistiq on its branch, track-1 unified on main): 2 FAIL
# while the hook behaved as designed. So the root is built under TMPDIR when the PHYSICAL path of
# TMPDIR is outside /mnt/track<N>, else under /tmp. TMPDIR is resolved to a physical absolute path
# before anything changes directory (a relative TMPDIR stops resolving at the first cd), and the
# suite refuses (PRECONDITION FAIL, exit 1, one cause per message) instead of running cases whose
# premise is false: TMPDIR names no directory, no fixture directory can be created under it, or no
# root outside a track mount exists. An unusable TMPDIR is never silently replaced by /tmp.
_phys() { ( cd -- "$1" 2>/dev/null && pwd -P ); }
_on_track_mount() { case "$1" in /mnt/track[0-9]*) return 0 ;; esac; return 1; }
_precond_fail() { echo "  PRECONDITION FAIL: $1"; echo "  RESULT: FAIL"; exit 1; }
# _new_root <base>: sets TMP to a new empty directory under <base> (physical absolute path); on failure
# TMP="" and FIXTURE_WHY names the cause.
FIXTURE_WHY=""; TMP=""; TL_FX=""
_new_root() {
  local base="$1" phys
  TMP=""
  phys="$(_phys "$base")" || { FIXTURE_WHY="'$base' is not an existing directory"; return 1; }
  TMP="$(mktemp -d "${phys%/}/gwtb.XXXXXX" 2>/dev/null)" || { TMP=""; FIXTURE_WHY="mktemp could not create a directory under '$phys'"; return 1; }
  return 0
}
trap '[ -z "$TMP" ] || rm -rf "$TMP"; [ -z "$TL_FX" ] || rm -rf "$TL_FX"' EXIT
if _new_root "${TMPDIR:-/tmp}"; then
  if _on_track_mount "$TMP"; then
    UNDER_TRACK="$TMP"; rmdir "$TMP"
    _new_root /tmp || _precond_fail "TMPDIR=${TMPDIR:-unset} resolves under a track mount ($UNDER_TRACK) and the /tmp fallback is unusable: $FIXTURE_WHY"
    _on_track_mount "$TMP" && _precond_fail "no fixture root outside /mnt/track<N>: TMPDIR=${TMPDIR:-unset} and /tmp both resolve under a track mount ($TMP)"
  fi
else
  _precond_fail "TMPDIR=${TMPDIR:-unset}: $FIXTURE_WHY"
fi

# ---------------------------------------------------------------------------
# Track layout for section E: a cwd whose PHYSICAL path is /mnt/track<N>/... (the only input the hook
# reads to derive the track, so the only way to exercise that derivation).
#   ns   a private user+mount namespace (unshare -Urm): tmpfs on /mnt, every entry of the real /mnt
#        bound back in, plus /mnt/track12 (two digits on purpose: a parser that keeps one digit is caught).
#        Nothing outside the namespace is touched. _NS_PREP is shared by the availability probe and the run.
#   real a writable /mnt/track<N> of this host (a fresh gwtb_track.* directory, removed on exit).
# ---------------------------------------------------------------------------
_track_no() { # <physical path> -> N when it is /mnt/track<N> or below (digits only, as the hook requires)
  local n
  case "$1" in /mnt/track[0-9]*) n="${1#/mnt/track}"; n="${n%%/*}" ;; *) return 1 ;; esac
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$n"
}
_layout_probe() { # <dir> -> track-<N> when its physical path is under /mnt/track<N>, none when it is not
  local p n
  p="$(_phys "$1")" || { printf 'unresolvable'; return 0; }
  if n="$(_track_no "$p")"; then printf 'track-%s' "$n"; else printf 'none'; fi
}
# shellcheck disable=SC2016  # the script is for the namespace's own bash: nothing may expand here
_NS_PREP='OLD="$1"; N="$2"; cd / || exit 90
mount --rbind /mnt "$OLD" || exit 91
mount -t tmpfs tmpfs /mnt || exit 92
for e in "$OLD"/*; do [ -d "$e" ] || continue; mkdir "/mnt/${e##*/}" && mount --rbind "$e" "/mnt/${e##*/}" || exit 93; done
mkdir -p "/mnt/track$N" || exit 94
FX="$(mktemp -d "/mnt/track$N/gwtb_track.XXXXXX")" || exit 95'
_probe_ns_layout() { # sets NS_OLD; rc 0 when the namespace layout can be built here
  command -v unshare >/dev/null 2>&1 || { TL_WHY="unshare is not installed"; return 1; }
  case "$TMP" in /mnt/*) TL_WHY="the fixture root $TMP is under /mnt, which the namespace replaces"; return 1 ;; esac
  NS_OLD="$(mktemp -d "$TMP/oldmnt.XXXXXX")" || { TL_WHY="mktemp failed for the namespace staging directory"; return 1; }
  unshare -Urm bash -c "$_NS_PREP" _ "$NS_OLD" 12 >/dev/null 2>&1 || { TL_WHY="an unprivileged user+mount namespace with a private /mnt could not be built here"; return 1; }
  return 0
}
_pick_real_layout() { # sets TL_FX and TL_N; rc 0 when a writable /mnt/track<N> exists
  local d p n
  for d in /mnt/track[0-9]*; do
    [ -d "$d" ] && [ -w "$d" ] || continue
    p="$(_phys "$d")" || continue
    n="$(_track_no "$p")" || continue
    TL_FX="$(mktemp -d "$p/gwtb_track.XXXXXX" 2>/dev/null)" || { TL_FX=""; continue; }
    TL_N="$n"; return 0
  done
  TL_WHY="no writable /mnt/track<N> directory on this host"
  return 1
}
TL_MODE=none; TL_N=12; TL_WHY=""; NS_OLD=""; TL_CASES=7; SKIP=0
TL_WANT="${GWTB_TRACK_LAYOUT:-auto}"
case "$TL_WANT" in
  auto|ns|real|none) ;;
  *) _precond_fail "GWTB_TRACK_LAYOUT='$TL_WANT' is not one of auto, ns, real, none" ;;
esac
if [ "$TL_WANT" = auto ] || [ "$TL_WANT" = ns ]; then
  if _probe_ns_layout; then TL_MODE=ns; TL_N=12
  elif [ "$TL_WANT" = ns ]; then _precond_fail "GWTB_TRACK_LAYOUT=ns: $TL_WHY"
  fi
fi
if [ "$TL_MODE" = none ] && { [ "$TL_WANT" = auto ] || [ "$TL_WANT" = real ]; }; then
  _ns_why="$TL_WHY"
  if _pick_real_layout; then TL_MODE=real
  elif [ "$TL_WANT" = real ]; then _precond_fail "GWTB_TRACK_LAYOUT=real: $TL_WHY"
  else TL_WHY="${_ns_why:+$_ns_why; }$TL_WHY"
  fi
fi
[ "$TL_WANT" != none ] || TL_WHY="GWTB_TRACK_LAYOUT=none"
DB="$TMP/registry.db"
sqlite3 "$DB" "
CREATE TABLE logic_groups (group_id TEXT PRIMARY KEY, title TEXT, destination TEXT NOT NULL, priority INTEGER NOT NULL, state TEXT, scope_note TEXT, roadmap_ref TEXT, canonical_track TEXT);
INSERT INTO logic_groups (group_id,title,destination,priority,state,canonical_track) VALUES
 ('mistiq-vader','t','feature:mistiq-vader',2,'open','track-2'),
 ('token-reduction','t','main',5,'open','track-1'),
 ('unified-product','t','main',4,'open','track-1'),
 ('roster-2026-07','t','feature:roster-2026-07',6,'open',NULL),
 ('grp-a','t','feature:grp-a',7,'open','track-1'),
 ('grp-b','t','feature:grp-b',8,'open','track-1'),
 ('trk-here','t','main',20,'open','track-$TL_N'),
 ('trk-away','t','main',21,'open','track-$((TL_N + 1))');
CREATE TABLE group_paths (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, path_glob TEXT NOT NULL, note TEXT, UNIQUE(group_id,path_glob));
INSERT INTO group_paths (group_id,path_glob) VALUES
 ('mistiq-vader','device/rockchip/atmosphere/remote_host/**'),
 ('mistiq-vader','device/rockchip/rk3588/tests/test_scrcpy_*.sh'),
 ('unified-product','unified_product/**'),
 ('grp-a','ambig/a*.kt'),
 ('grp-b','ambig/*b.kt'),
 ('trk-here','trk_probe/here/**'),
 ('trk-away','trk_probe/away/**');
CREATE TABLE items (atm_id TEXT, type TEXT, status TEXT, title TEXT, description TEXT, logic_group TEXT, current_location TEXT, PRIMARY KEY(atm_id,current_location));
INSERT INTO items (atm_id,type,status,title,description,logic_group,current_location) VALUES
 ('ATM-900','Feature','In progress','t','desc','mistiq-vader','Issues'),
 ('ATM-901','Task','In progress','t','desc','token-reduction','Issues'),
 ('ATM-902','Bug','In progress','t','desc',NULL,'Issues'),
 ('ATM-903','Feature','In progress','t','desc','unified-product','Issues');
"

# ---------------------------------------------------------------------------
# Throwaway git repo: seed commit on main so the branch is BORN, plus a
# feature/mistiq-vader branch. Files are created untracked; each commit case
# resets the index then stages exactly what it needs.
# ---------------------------------------------------------------------------
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name  t
echo seed > "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -qm seed
git -C "$REPO" branch feature/mistiq-vader
mkdir -p "$REPO/device/rockchip/atmosphere/remote_host" "$REPO/device/rockchip/rk3588/tests"
echo x > "$REPO/device/rockchip/atmosphere/remote_host/Foo.kt"
echo y > "$REPO/README.md"
echo z > "$REPO/device/rockchip/rk3588/tests/test_scrcpy_box.sh"
echo z > "$REPO/device/rockchip/rk3588/tests/test_other.sh"
mkdir -p "$REPO/unified_product"
echo u > "$REPO/unified_product/Bar.kt"

assert() { # <name> <want> <got>
  local name="$1" want="$2" got="$3"
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-58s (exit %s)\n' "$name" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL  %-58s (got %s, want %s)\n' "$name" "$got" "$want"; FAIL=$((FAIL+1))
  fi
}

# run_hook <payload>  — dispatch/non-git path (WI_DB=$DB, cwd irrelevant).
run_hook() { WI_DB="$DB" bash "$HOOK" <<<"$1" >/dev/null 2>&1; echo $?; }

# commit_hook <branch> <payload> [db]  — checkout branch, run guard from $REPO.
commit_hook() {
  local branch="$1" payload="$2" db="${3:-$DB}"
  git -C "$REPO" checkout -q "$branch"
  ( cd "$REPO" && WI_DB="$db" bash "$HOOK" <<<"$payload" >/dev/null 2>&1 ); echo $?
}
stage() { git -C "$REPO" reset -q; git -C "$REPO" add "$@" 2>/dev/null || true; }
unstage_all() { git -C "$REPO" reset -q; }

# assert_eq <name> <want> <got> — string comparison (the hook's own text as the oracle).
assert_eq() {
  local name="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    printf '  PASS  %-58s (%s)\n' "$name" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL  %-58s (got "%s", want "%s")\n' "$name" "$got" "$want"; FAIL=$((FAIL+1))
  fi
}

# probe_hook <cwd> <repo> <file> — stage <file> in <repo> (its current branch), run the hook from <cwd>
# (which may reach <repo> through a symlink) and print the exit code; 99 when the file did not get staged,
# so an ALLOW never comes from an empty index. probe_err prints the hook's stderr (its refusal text) instead.
_probe_stage() { git -C "$1" reset -q; git -C "$1" add "$2" 2>/dev/null; git -C "$1" diff --cached --name-only | grep -qxF "$2"; }
probe_hook() {
  _probe_stage "$2" "$3" || { echo 99; return 0; }
  ( cd "$1" && WI_DB="$DB" bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' >/dev/null 2>&1 ); echo $?
}
probe_err() {
  _probe_stage "$2" "$3" || { echo "FILE-NOT-STAGED"; return 0; }
  ( cd "$1" && WI_DB="$DB" bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' 2>&1 >/dev/null )
}

# track_layout_cases <fixture dir whose physical path is /mnt/track<N>/...> <N> <outside repo>
# Builds a repo there and asks the real hook what it derives, from four cwds: inside the track mount;
# inside through a symlink that lives outside; outside through a symlink that lives inside. Oracle = the
# hook's exit code and its own refusal text (the track it names, the track its resolver text was given).
# Prints PASS/FAIL lines like every other case (7 of them: TL_CASES); also runs inside the namespace.
track_layout_cases() {
  local fx="$1" n="$2" orepo="$3" repo here away
  repo="$fx/repo"; here=trk_probe/here/X.kt; away=trk_probe/away/X.kt
  { git init -q -b main "$repo" \
    && git -C "$repo" config user.email t@t && git -C "$repo" config user.name t \
    && echo seed > "$repo/seed.txt" && git -C "$repo" add seed.txt && git -C "$repo" commit -qm seed \
    && mkdir -p "$repo/trk_probe/here" "$repo/trk_probe/away" \
    && echo h > "$repo/$here" && echo a > "$repo/$away" \
    && git -C "$orepo" reset -q && git -C "$orepo" checkout -q main \
    && ln -s "$repo" "$TMP/link_into_track" && ln -s "$orepo" "$fx/link_to_outside"; } \
    || { echo "  FAIL  setup of the track-layout fixtures under $fx"; return 1; }
  assert_eq "layout control: fixture cwd physically under /mnt/track$n, symlink target not" "track-$n/none" "$(_layout_probe "$repo")/$(_layout_probe "$orepo")"
  assert    "this-track file staged on main, cwd under /mnt/track$n allowed"        0 "$(probe_hook "$repo" "$repo" "$here")"
  assert    "other-track file staged on main, cwd under /mnt/track$n BLOCKED"       2 "$(probe_hook "$repo" "$repo" "$away")"
  assert_eq "refusal names the derived track 'track-$n'" "track-$n" \
    "$(probe_err "$repo" "$repo" "$away" | sed -n "s/^  Current checkout: branch '[^']*' \/ track '\([^']*\)'\.\$/\1/p" | head -n 1)"
  assert_eq "resolver text of the refusal got --track 'track-$n' from the hook" 1 \
    "$(probe_err "$repo" "$repo" "$away" | grep -cF "but the change is on track 'track-$n'")"
  assert    "other-track file, cwd via an outside symlink (physical = track-$n) BLOCKED" 2 "$(probe_hook "$TMP/link_into_track" "$repo" "$away")"
  assert    "other-track file, cwd via an inside symlink (physical = outside) allowed"   0 "$(probe_hook "$fx/link_to_outside" "$orepo" "$away")"
}

echo "§11.4.191 guard-work-track-binding.sh hermetic test suite"
echo "hook: $HOOK"
echo "resolver: $RES"
echo "registry: $DB (mistiq-vader=feature/mistiq-vader/track-2, unified-product=main/track-1)"
# Control needle (§11.4.201: the real condition, read from the hook itself, not a copy of its glob):
# the track the hook derives for a cwd inside $REPO must be '?', the premise of every commit-path
# case. A mistiq file staged on main is a known BLOCK whose refusal names the derived track. Every way
# the probe can go wrong ends in its own PRECONDITION FAIL line: the file not staged, the hook allowing
# (fail-open) or exiting other than 2, a refusal without the 'Current checkout' line (reworded), a line
# of another shape, and a derived track other than '?'.
PROBE_FILE=device/rockchip/atmosphere/remote_host/Foo.kt
stage "$PROBE_FILE"
PROBE_STAGED="$(git -C "$REPO" diff --cached --name-only)"
PROBE_ERR="$( cd "$REPO" && WI_DB="$DB" bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' 2>&1 >/dev/null )"
PROBE_RC=$?
unstage_all
PROBE_FIRST="$(printf '%s\n' "$PROBE_ERR" | head -n 1)"
[ "$PROBE_STAGED" = "$PROBE_FILE" ] || _precond_fail "the probe file could not be staged in the fixture repo $REPO (staged set: '${PROBE_STAGED:-<empty>}')"
case "$PROBE_RC" in
  2) ;;
  0) _precond_fail "the hook ALLOWED (exit 0) a mistiq file staged on main, a known BLOCK: it is fail-open on the commit path, so no commit-path verdict below can be trusted" ;;
  *) _precond_fail "the hook exited $PROBE_RC (expected 2) on the probe in $REPO; first stderr line: ${PROBE_FIRST:-<none>}" ;;
esac
TRACK_LINE="$(printf '%s\n' "$PROBE_ERR" | sed -n '/^  Current checkout: branch /{p;q;}')"
[ -n "$TRACK_LINE" ] || _precond_fail "the hook BLOCKED the probe (exit 2) but its refusal has no '  Current checkout: branch ... / track ...' line (refusal text changed?); first stderr line: ${PROBE_FIRST:-<none>}"
TRACK_SEEN="$(printf '%s\n' "$TRACK_LINE" | sed -n "s/^  Current checkout: branch '[^']*' \/ track '\([^']*\)'\.\$/\1/p")"
[ -n "$TRACK_SEEN" ] || _precond_fail "the 'Current checkout' line of the refusal has another shape, the track cannot be read from it: $TRACK_LINE"
[ "$TRACK_SEEN" = "?" ] || _precond_fail "the hook derives track '$TRACK_SEEN' for the fixture cwd $REPO; every commit-path case is written for track '?'"
echo "precondition: the hook derives track '${TRACK_SEEN}' for the fixture cwd (fixture root $TMP)"
echo

# ===========================================================================
# A. DISPATCH path (Agent | Task | TaskCreate) — label + ticket binding.
# ===========================================================================
echo "-- A. dispatch path --"
assert "dispatch mistiq ticket onto (T1/main) BLOCKED"        2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - claude4) ATM-900 scrcpy box"}}')"
assert "dispatch mistiq ticket onto (T2/feature/mistiq-vader)" 0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T2/feature/mistiq-vader - deepseek) ATM-900 scrcpy box"}}')"
assert "dispatch main ticket onto (T1/main) allowed"           0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) ATM-901 token-reduction"}}')"
assert "dispatch unclassified ticket ATM-902 allowed"          0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) ATM-902 misc"}}')"
assert "dispatch mistiq ticket onto (T3/feature/dolby-remap) BLOCKED" 2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T3/feature/dolby-remap - x) ATM-900 wrong branch"}}')"
assert "dispatch with NO label passes (sibling hook handles)"  0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"unlabeled dispatch ATM-900"}}')"
assert "dispatch labeled with NO ticket allowed"               0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) generic docs task"}}')"
assert "Task tool: mistiq ticket onto (T1/main) BLOCKED"       2 "$(run_hook '{"tool_name":"Task","tool_input":{"description":"(T1/main - x) ATM-900 scrcpy"}}')"
assert "TaskCreate: mistiq ticket onto (T2/feature/mistiq-vader)" 0 "$(run_hook '{"tool_name":"TaskCreate","tool_input":{"description":"(T2/feature/mistiq-vader - kimi) ATM-900 scrcpy"}}')"
assert "dispatch unknown ticket SPK-500 (no item row) allowed" 0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) SPK-500 unknown"}}')"
assert "non-Bash non-Agent tool (Read) passes through"         0 "$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"x"}}')"
# A2. SINGLE-TRACK binding (group -> main / track-1). The registry shape a consumer reaches
# when an operator rules that all work happens on ONE track: the canonical branch is trunk and
# the canonical track is pinned, so the guard must ALLOW exactly (T1, main) and refuse every
# other (track, branch) pair — a pinned track is enforced even on the right branch.
assert "single-track: ticket onto (T1/main) allowed"               0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) ATM-903 unified"}}')"
assert "single-track: ticket onto (T2/main) BLOCKED (pinned track)" 2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T2/main - x) ATM-903 unified"}}')"
assert "single-track: ticket onto (T1/feature/mistiq-vader) BLOCKED" 2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/feature/mistiq-vader - x) ATM-903 unified"}}')"
assert "single-track: ticket onto (T2/feature/mistiq-vader) BLOCKED" 2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T2/feature/mistiq-vader - x) ATM-903 unified"}}')"
assert "pinned track enforced for token-reduction (T2/main) BLOCKED" 2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T2/main - x) ATM-901 token-reduction"}}')"

# ===========================================================================
# B. COMMIT path (Bash) — file-scope binding via git plumbing.
# ===========================================================================
echo "-- B. commit path --"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "mistiq file staged on main BLOCKED"                    2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "mistiq file staged on feature/mistiq-vader allowed"    0 "$(commit_hook feature/mistiq-vader '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage README.md
assert "unclassified README staged on main allowed"            0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/rk3588/tests/test_scrcpy_box.sh
assert "test_scrcpy_*.sh staged on main BLOCKED (glob)"        2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/rk3588/tests/test_other.sh
assert "test_other.sh staged on main allowed (glob precision)" 0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "mistiq on main + # guardrails:allow => WARN allowed"   0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip # guardrails:allow operator-approved reconciliation"}}')"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "non-commit Bash (git status) allowed"                  0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git status"}}')"
# broad-stage (commit_all.sh) sweeps the whole dirty worktree even when nothing
# is staged: the mistiq file dirty+unstaged on main must BLOCK.
unstage_all
assert "commit_all.sh broad stage, mistiq dirty on main BLOCKED" 2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"bash scripts/commit_all.sh -m wip"}}')"
# dynamic $(…) pathspec -> fail-closed (unless escape marker).
unstage_all
assert "dynamic \$(…) pathspec commit BLOCKED (fail-closed)"   2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m x -- $(ls)"}}')"
assert "dynamic \$(…) pathspec + escape => WARN allowed"       0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m x -- $(ls) # guardrails:allow vetted"}}')"
# DB unreadable in the commit path -> fail-closed (WI_DB points nowhere, $REPO
# has no docs/workable_items.db). A mistiq file is staged so FILESET is non-empty.
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "commit path, registry unreadable => fail-closed BLOCK" 2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' "$TMP/does-not-exist.db")"
# B2. SINGLE-TRACK commit path: a group bound to trunk is committable on main and BLOCKED on a
# feature branch (the mirror image of the feature-bound cases above).
stage unified_product/Bar.kt
assert "single-track: unified file staged on main allowed"          0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage unified_product/Bar.kt
assert "single-track: unified file staged on feature branch BLOCKED" 2 "$(commit_hook feature/mistiq-vader '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"

# ===========================================================================
# C. RESOLVER-direct — track dimension, glob precision, ambiguity, fail-closed.
# ===========================================================================
echo "-- C. resolver-direct --"
rd() { bash "$RES" "$@" >/dev/null 2>&1; echo $?; }
MF=device/rockchip/atmosphere/remote_host/X.kt
assert "resolver: mistiq file wrong TRACK (branch OK) BLOCKED" 2 "$(rd check --db "$DB" --branch feature/mistiq-vader --track track-9 --file "$MF")"
assert "resolver: mistiq file unknown track '?' allowed"       0 "$(rd check --db "$DB" --branch feature/mistiq-vader --track '?' --file "$MF")"
assert "resolver: ambiguous file scope => fail-closed BLOCK"   2 "$(rd check --db "$DB" --branch main --file ambig/ab.kt)"
assert "resolver: unreadable DB => fail-closed BLOCK"          2 "$(rd check --db "$TMP/nope.db" --branch main --file "$MF")"
UF=unified_product/X.kt
assert "resolver: single-track file on (main, track-1) allowed"      0 "$(rd check --db "$DB" --branch main --track track-1 --file "$UF")"
assert "resolver: single-track file on (main, track-2) BLOCKED"      2 "$(rd check --db "$DB" --branch main --track track-2 --file "$UF")"
assert "resolver: single-track file on (feature, track-1) BLOCKED"   2 "$(rd check --db "$DB" --branch feature/mistiq-vader --track track-1 --file "$UF")"
assert "resolver: single-track file, unknown track '?' on main allowed" 0 "$(rd check --db "$DB" --branch main --track '?' --file "$UF")"
# Ticket-path injection guard (RV-A' newline-bypass regression, §11.4.6/§11.4.10):
# single-line AND newline (multi-line) payloads must fail-closed; a valid-format ticket is accepted.
assert "resolver: single-line injection ticket => fail-closed" 2 "$(rd check --db "$DB" --branch main --ticket "ATM-1'; SELECT x")"
assert "resolver: NEWLINE injection ticket => fail-closed"     2 "$(rd check --db "$DB" --branch main --ticket "$(printf 'ATM-1\nINJ')")"
assert "resolver: valid-format ticket accepted (unclassified)" 0 "$(rd check --db "$DB" --branch main --ticket ATM-999999)"
# resolve prints the owning group (stdout content assertion).
RESOLVE_OUT="$(bash "$RES" resolve --db "$DB" --file "$MF" 2>/dev/null)"
if printf '%s' "$RESOLVE_OUT" | grep -q 'mistiq-vader'; then
  printf '  PASS  %-58s\n' "resolve prints owning group 'mistiq-vader'"; PASS=$((PASS+1))
else
  printf '  FAIL  %-58s (got: %s)\n' "resolve prints owning group 'mistiq-vader'" "$RESOLVE_OUT"; FAIL=$((FAIL+1))
fi

# ===========================================================================
# D. SUBMODULE-CONTEXT DB resolution (§11.4.191 forensic fix, this cycle).
#
# The guard's cwd is INSIDE a REAL git submodule (own `.git` file, gitlink in
# the outer superproject's index — built with `git submodule add`, not a bare
# nested `git init`). BEFORE the fix, the shared resolver's own auto-discovery
# bound to `git rev-parse --show-toplevel` — the SUBMODULE's own innermost
# root — so `<submodule-root>/docs/workable_items.db` never existed and the
# resolver fail-closed BLOCKed every commit issued from inside ANY submodule,
# unconditionally, regardless of file-scope classification (reproduced
# manually: `cd constitution && git commit`-class payload -> exit 2 even
# though the real parent registry at `<repo-root>/docs/workable_items.db`
# exists and is readable).
#
# This section proves all three properties in one hermetic pass:
#   (1) the real PARENT registry is FOUND — an unclassified submodule file no
#       longer falsely fail-closed-BLOCKs (the direct regression case);
#   (2) it is GENUINELY CONSULTED, not merely found-and-ignored — a submodule
#       file owned by a group whose canonical branch != the submodule's
#       current branch is still BLOCKED, and the correctly-placed branch is
#       still ALLOWED;
#   (3) the fail-closed guarantee is UNWEAKENED — an explicit-but-absent
#       $WI_DB override still fail-closes even from submodule cwd (§11.4.6).
# ===========================================================================
echo "-- D. submodule-context DB resolution --"

OUTER="$TMP/outer"
SUBSRC="$TMP/subsrc"
git init -q -b main "$OUTER"
git -C "$OUTER" config user.email t@t
git -C "$OUTER" config user.name  t
mkdir -p "$OUTER/docs"
cp "$DB" "$OUTER/docs/workable_items.db"
sqlite3 "$OUTER/docs/workable_items.db" "
INSERT INTO logic_groups (group_id,title,destination,priority,state,canonical_track) VALUES
 ('sub-work','t','feature:sub-work',9,'open',NULL);
INSERT INTO group_paths (group_id,path_glob) VALUES
 ('sub-work','tracked.kt');
"
echo seed > "$OUTER/seed.txt"
git -C "$OUTER" add seed.txt docs/workable_items.db
git -C "$OUTER" commit -qm seed

git init -q -b main "$SUBSRC"
git -C "$SUBSRC" config user.email t@t
git -C "$SUBSRC" config user.name  t
echo x > "$SUBSRC/seed.txt"
git -C "$SUBSRC" add seed.txt
git -C "$SUBSRC" commit -qm seed
git -C "$SUBSRC" branch feature/sub-work

git -C "$OUTER" -c protocol.file.allow=always submodule add -q "$SUBSRC" sub >/dev/null 2>&1
git -C "$OUTER" commit -qm "add submodule" -q

SUB="$OUTER/sub"
echo new > "$SUB/bar.txt"       # unclassified — no group_paths glob owns it
echo new > "$SUB/tracked.kt"    # owned by 'sub-work' -> canonical branch feature/sub-work

# submodule_hook <branch> <payload> — checkout branch INSIDE the submodule,
# run the guard from cwd=$SUB with WI_DB explicitly UNSET (so ONLY the guard's
# own submodule-aware walk can find the registry — the exact bug scenario).
submodule_hook() {
  local branch="$1" payload="$2"
  git -C "$SUB" checkout -q "$branch"
  ( cd "$SUB" && unset WI_DB && bash "$HOOK" <<<"$payload" >/dev/null 2>&1 ); echo $?
}
stage_sub()   { git -C "$SUB" reset -q; git -C "$SUB" add "$@" 2>/dev/null || true; }

stage_sub bar.txt
assert "submodule: unclassified file on main allowed (parent DB found)" 0 "$(submodule_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage_sub tracked.kt
assert "submodule: sub-work file on main BLOCKED (parent DB enforced)"  2 "$(submodule_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage_sub tracked.kt
assert "submodule: sub-work file on feature/sub-work allowed"          0 "$(submodule_hook feature/sub-work '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
# Fail-closed unweakened: an explicit-but-absent $WI_DB override still BLOCKs
# even from submodule cwd (the walk NEVER overrides an explicit $WI_DB).
git -C "$SUB" checkout -q main
stage_sub bar.txt
SUB_ABSENT_RC="$(cd "$SUB" && WI_DB="$TMP/does-not-exist.db" bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' >/dev/null 2>&1; echo $?)"
assert "submodule: explicit absent WI_DB override still fail-closed BLOCK" 2 "$SUB_ABSENT_RC"

# ===========================================================================
# E. TRACK DERIVATION — the hook's current_track (physical cwd -> track-<N> / '?') and the --track it
# hands the resolver. Every other section runs from a cwd outside /mnt/track<N> (track '?'), where the
# resolver never asserts a pinned track, so none of them could notice a hook that derives the wrong track
# or passes the wrong one on. The registry pins trk-here to track-$TL_N and trk-away to track-$((TL_N+1)).
# Oracle: the hook's own exit code and refusal text; the resolver-direct controls prove the pins bite.
# ===========================================================================
echo "-- E. track derivation from the physical cwd --"
TRKH=trk_probe/here/X.kt; TRKA=trk_probe/away/X.kt
mkdir -p "$REPO/trk_probe/here" "$REPO/trk_probe/away"
echo h > "$REPO/$TRKH"; echo a > "$REPO/$TRKA"
git -C "$REPO" reset -q; git -C "$REPO" checkout -q main
assert "resolver control: this-track file on track-$TL_N allowed"                        0 "$(rd check --db "$DB" --branch main --track "track-$TL_N" --file "$TRKH")"
assert "resolver control: other-track file on track-$TL_N BLOCKED"                       2 "$(rd check --db "$DB" --branch main --track "track-$TL_N" --file "$TRKA")"
assert "cwd outside /mnt/track<N> (track '?'): this-track file staged on main allowed"  0 "$(probe_hook "$REPO" "$REPO" "$TRKH")"
assert "cwd outside /mnt/track<N> (track '?'): other-track file staged on main allowed" 0 "$(probe_hook "$REPO" "$REPO" "$TRKA")"
case "$TL_MODE" in
  none)
    printf '  SKIP  %-58s (%s)\n' "$TL_CASES cases: the hook run from a cwd under /mnt/track<N>" "$TL_WHY"
    SKIP=$((SKIP + TL_CASES)) ;;
  *)
    export PASS FAIL HOOK RES DB TMP
    export -f assert assert_eq probe_hook probe_err _probe_stage track_layout_cases _phys _track_no _layout_probe
    if [ "$TL_MODE" = ns ]; then
      # shellcheck disable=SC2016  # $FX, $N and $3 belong to the namespace's bash
      TL_OUT="$(unshare -Urm bash -c "$_NS_PREP"'; track_layout_cases "$FX" "$N" "$3"' _ "$NS_OLD" "$TL_N" "$REPO" 2>&1)"
    else
      TL_OUT="$(track_layout_cases "$TL_FX" "$TL_N" "$REPO" 2>&1)"
    fi
    [ -z "$TL_OUT" ] || printf '%s\n' "$TL_OUT"
    TL_P="$(printf '%s\n' "$TL_OUT" | grep -c '^  PASS ')"; TL_F="$(printf '%s\n' "$TL_OUT" | grep -c '^  FAIL ')"
    PASS=$((PASS + TL_P)); FAIL=$((FAIL + TL_F))
    if [ $((TL_P + TL_F)) -ne "$TL_CASES" ]; then
      printf '  FAIL  %-58s (got %s case lines, want %s)\n' "the $TL_MODE track-layout run reports all its cases" $((TL_P + TL_F)) "$TL_CASES"
      FAIL=$((FAIL + 1))
    fi ;;
esac

echo
if [ "$SKIP" -gt 0 ]; then
  echo "  skipped: $SKIP case(s) not run, not counted as PASS (section E: $TL_WHY)"
fi
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
if [ "$SKIP" -gt 0 ]; then
  echo "  RESULT: PASS ($PASS cases run, $SKIP skipped)"
else
  echo "  RESULT: PASS (all $PASS cases)"
fi
exit 0
